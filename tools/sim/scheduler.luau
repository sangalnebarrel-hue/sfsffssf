-- scheduler.luau: virtual-time cooperative scheduler.
-- Every sim thread is tagged with an execution context (server or a client) and,
-- optionally, the script instance that owns it. Nothing ever sleeps for real:
-- time only moves when the sim advances frames.

local Util = require("./util")

local Scheduler = {}
Scheduler.__index = Scheduler

local MAX_FLUSH_ITEMS = 200000

function Scheduler.new(sim)
	local self = setmetatable({}, Scheduler)
	self.sim = sim
	self.clock = 0
	self.frame = 0
	self.seq = 0
	self.timers = Util.Heap.new()
	self.deferred = {}
	self.threadCtx = setmetatable({}, { __mode = "k" })
	self.threadScript = setmetatable({}, { __mode = "k" })
	-- thread -> token; a thread is only woken by the token it is currently waiting on
	self.pending = setmetatable({}, { __mode = "k" })
	self.currentCtx = nil
	self.currentScript = nil
	self.depth = 0
	self.flushing = false
	return self
end

-- Context of the running code (harness code counts as the server context).
function Scheduler:context()
	local ctx = self.threadCtx[coroutine.running()]
	if ctx then
		return ctx
	end
	return self.currentCtx or self.sim.serverCtx
end

-- Script instance owning the running thread (nil for harness / internal threads).
function Scheduler:script()
	local s = self.threadScript[coroutine.running()]
	if s ~= nil then
		return s or nil
	end
	return self.currentScript
end

function Scheduler:inSimThread(): boolean
	return self.depth > 0
end

function Scheduler:tag(co: thread, ctx, script)
	self.threadCtx[co] = ctx
	self.threadScript[co] = script or false
	if ctx and ctx.threads then
		ctx.threads[co] = true
	end
	if script then
		self.sim.runtime:_trackThread(script, co)
	end
end

-- Makes sure a thread carries a context; untagged threads inherit the current one.
function Scheduler:ensureTagged(co: thread)
	if self.threadCtx[co] == nil then
		self:tag(co, self:context(), self:script())
	end
end

-- Resumes a thread with its context active. Errors are captured, never raised.
function Scheduler:resume(co: thread, ...)
	if coroutine.status(co) ~= "suspended" then
		return false
	end
	local ctx = self.threadCtx[co]
	if ctx and not ctx.alive then
		pcall(coroutine.close, co)
		return false
	end
	local script = self.threadScript[co]
	if script and self.sim.runtime:isScriptDead(script) then
		pcall(coroutine.close, co)
		return false
	end
	local prevCtx, prevScript = self.currentCtx, self.currentScript
	if ctx then
		self.currentCtx = ctx
	end
	if script ~= nil then
		self.currentScript = script or nil
	end
	self.depth += 1
	local ok, err = coroutine.resume(co, ...)
	self.depth -= 1
	self.currentCtx, self.currentScript = prevCtx, prevScript
	if not ok then
		self:reportError(co, err, ctx)
	end
	return ok
end

function Scheduler:reportError(co: thread, err: any, ctx)
	local message = Util.cleanError(err)
	local tb = debug.traceback(co, message)
	self.sim:_recordError(ctx or self:context(), message, tb)
end

-- Creates a thread for fn tagged with the given (or current) context and script.
function Scheduler:newThread(fn, ctx, script)
	local co = coroutine.create(fn)
	if ctx == nil then
		ctx = self:context()
		script = self:script()
	end
	self:tag(co, ctx, script)
	return co
end

-- Suspends the running sim thread until `wake(token, ...)` is called.
function Scheduler:suspend(token)
	if self.depth == 0 then
		error("RbxSim: cannot yield on the harness thread; wrap the code in sim:Run(function() ... end)", 3)
	end
	local co = coroutine.running()
	self:ensureTagged(co)
	token = token or {}
	token.co = co
	self.pending[co] = token
	local r = table.pack(coroutine.yield())
	if self.pending[co] == token then
		self.pending[co] = nil
	end
	return table.unpack(r, 1, r.n)
end

-- Wakes a suspended thread if it is still waiting on this token.
-- immediate=true resumes now, otherwise it is queued for the deferred flush.
function Scheduler:wake(token, immediate: boolean, ...)
	local co = token.co
	if co == nil or self.pending[co] ~= token then
		return false
	end
	self.pending[co] = nil
	if immediate then
		self:resume(co, ...)
	else
		table.insert(self.deferred, { kind = "resume", co = co, args = table.pack(...) })
	end
	return true
end

function Scheduler:isWaiting(token): boolean
	return token.co ~= nil and self.pending[token.co] == token
end

-- Queues a signal handler invocation (deferred) or runs it right away (immediate).
function Scheduler:invoke(conn, args, force: boolean, immediate: boolean)
	local item = { kind = "call", fn = conn.fn, ctx = conn.ctx, script = conn.script, conn = conn, force = force, args = args }
	if immediate then
		self:_runItem(item)
	else
		table.insert(self.deferred, item)
	end
end

-- Queues an internal function to run in a fresh thread during the next flush.
function Scheduler:queueFn(fn, ctx, ...)
	table.insert(self.deferred, { kind = "call", fn = fn, ctx = ctx or self.sim.serverCtx, script = nil, force = true, args = table.pack(...) })
end

function Scheduler:_runItem(item)
	if item.kind == "call" then
		local conn = item.conn
		if conn and not item.force and not conn.connected then
			return
		end
		if item.ctx and not item.ctx.alive then
			return
		end
		if item.script and self.sim.runtime:isScriptDead(item.script) then
			return
		end
		local co = coroutine.create(item.fn)
		self:tag(co, item.ctx, item.script)
		self:resume(co, table.unpack(item.args, 1, item.args.n))
	elseif item.kind == "resume" then
		self:resume(item.co, table.unpack(item.args, 1, item.args.n))
	elseif item.kind == "token" then
		local token = item.token
		if self.pending[token.co] == token then
			self.pending[token.co] = nil
			self:resume(token.co, table.unpack(item.args, 1, item.args.n))
		end
	end
end

-- Runs queued deferred work until the queue drains (only at top level).
function Scheduler:flush()
	if self.depth > 0 or self.flushing then
		return
	end
	self.flushing = true
	local count = 0
	while #self.deferred > 0 do
		local queue = self.deferred
		self.deferred = {}
		for _, item in queue do
			count += 1
			self:_runItem(item)
		end
		if count > MAX_FLUSH_ITEMS then
			self.deferred = {}
			self.sim:_recordError(self.sim.serverCtx, "RbxSim: deferred event re-entrancy limit exceeded (handlers keep re-triggering each other)", "")
			break
		end
	end
	self.flushing = false
end

-- Timer helpers --------------------------------------------------------------

function Scheduler:addTimer(delay: number, entry)
	self.seq += 1
	entry.t = self.clock + math.max(tonumber(delay) or 0, 0)
	entry.frame = self.frame
	entry.seq = self.seq
	self.timers:push(entry)
	return entry
end

-- Runs a plain callback (internal) after `delay` seconds in its own thread.
function Scheduler:after(delay: number, fn, ctx)
	local entry = { fn = fn, ctx = ctx or self.sim.serverCtx, cancelled = false }
	self:addTimer(delay, entry)
	return entry
end

-- Resumes every timer that is due. Timers created during the current frame
-- never fire in the same frame (task.wait(0) waits at least one frame).
function Scheduler:runTimers()
	local heap = self.timers
	while true do
		local top = heap:peek()
		if top == nil or top.t > self.clock + 1e-9 or top.frame >= self.frame then
			break
		end
		heap:pop()
		if not top.cancelled then
			if top.token then
				if top.wait then
					self:wake(top.token, true, self.clock - top.start)
				else
					self:wake(top.token, true, table.unpack(top.args or {}, 1, top.args and top.args.n or 0))
				end
			elseif top.fn then
				local co = coroutine.create(top.fn)
				self:tag(co, top.ctx, nil)
				self:resume(co)
			end
		end
	end
end

-- task library -----------------------------------------------------------------

function Scheduler:taskSpawn(f, ...)
	local co
	if type(f) == "function" then
		co = self:newThread(f)
	elseif type(f) == "thread" then
		co = f
		self:ensureTagged(co)
		self.pending[co] = nil
	else
		error("invalid argument #1 to 'spawn' (function or thread expected)", 3)
	end
	if self.depth == 0 then
		-- harness call: run, then process anything it queued
		self:resume(co, ...)
		self:flush()
	else
		self:resume(co, ...)
	end
	return co
end

function Scheduler:taskDefer(f, ...)
	local co
	if type(f) == "function" then
		co = self:newThread(f)
	elseif type(f) == "thread" then
		co = f
		self:ensureTagged(co)
	else
		error("invalid argument #1 to 'defer' (function or thread expected)", 3)
	end
	local token = { co = co }
	self.pending[co] = token
	table.insert(self.deferred, { kind = "token", token = token, args = table.pack(...) })
	return co
end

function Scheduler:taskDelay(t: number?, f, ...)
	local co
	if type(f) == "function" then
		co = self:newThread(f)
	elseif type(f) == "thread" then
		co = f
		self:ensureTagged(co)
	else
		error("invalid argument #2 to 'delay' (function or thread expected)", 3)
	end
	local token = { co = co }
	self.pending[co] = token
	self:addTimer(tonumber(t) or 0, { token = token, args = table.pack(...) })
	return co
end

function Scheduler:taskWait(t: number?)
	local token = { start = self.clock }
	self:addTimer(tonumber(t) or 0, { token = token, wait = true, start = self.clock })
	return self:suspend(token)
end

function Scheduler:taskCancel(co: thread)
	if type(co) ~= "thread" then
		error("invalid argument #1 to 'cancel' (thread expected)", 3)
	end
	if co == coroutine.running() then
		error("cannot cancel the running thread", 3)
	end
	self.pending[co] = nil
	if coroutine.status(co) == "suspended" then
		pcall(coroutine.close, co)
	end
end

-- Forgets a thread that is being discarded (closes it if suspended).
function Scheduler:kill(co: thread)
	self.pending[co] = nil
	if coroutine.status(co) == "suspended" then
		pcall(coroutine.close, co)
	end
end

return Scheduler
