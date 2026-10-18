--[[
	Stage 4 kit — the helpers shared by the stage 4 suites (docs/stage4_design.md §7.2–§7.7):
	tests/stage4_theft, stage4_data, stage4_defence (Wave 1 A), stage4_e2e* (Wave 3 E). It is not a
	test file itself (tools/run_tests.luau only runs tests/*.test.luau) and tests/stage4_rules does
	not use it. Everything of tests/stage3_e2e_kit.luau is here too (Kit falls back to it: join,
	hud, walkTo, forceFish, pokeSave, peek, writes, assertGaps, ledgerHolds, toasts, …).

	RbxSim answers RunService:IsStudio() == true, so every stage 4 server here boots with
	DefenceConfig.Debug.StudioProtect = false (the 10 s Studio protections would change every
	timing; DC-20). The sim additions of Wave 0 (tools/sim, S1–S8) are called by name:
	sim:FirePromptEvent(p, prompt, kind), sim.DataStore:FailKey / SetKeyLatency,
	sim:Shutdown({ order = "playersFirst" }), Sim.new({ removingOrder = "reverse" }) (Kit.boot's
	opts.removingOrder).

	  Kit.boot(t, opts?)            a server (the stage 3 boot) with the Studio knob off; opts: patches
	                                ({ path, from, to } source edits, applied before the start),
	                                latency (remoteLatency), dataStore / epoch / seed (a restart),
	                                removingOrder ("reverse": PlayerRemoving handlers backwards, S7),
	                                studio = true (keep the Studio knob), before(sim)
	  Kit.restart(t, old, gap, opts?) a NEW server on the old one's DataStore (the knob off again)
	  Kit.seed(sim, id, spec)       a save poked before the join (Kit.pokeSave): spec { tank = { { Id,
	                                Kg?, Mutation?, Age?, Origin? } }, money, lock, upgrades, saveCount,
	                                stats (merged over the template's: { Stolen = 2 } is enough) }
	  Kit.stealPrompt(sim, owner, slot) the "StealPrompt" of the owner's display slot (or nil)
	  Kit.standAt(sim, p, prompt)   puts the character 2 studs in front of the prompt, facing it
	  Kit.steal(t, sim, thief, owner, slot, opts?) a whole theft as a player does it: walk up, hold
	                                «Украсть» for the hold, then carry to an exit — or stop it:
	                                opts.cancel = "release" | "walk" | "die" | "tag" | "leave" |
	                                "shield" (opts.phase = "hold" (default) | "carry": when),
	                                opts.exit = "gate" | "side" | "back", opts.speed (the carry's
	                                studs/s, default the honest carry), opts.holdFor (seconds held,
	                                default the prompt's HoldDuration + a frame), opts.holdOpts
	                                (BeginHold opts: ignoreDistance / ignoreEnabled). Returns
	                                { prompt, hold, triggered, events } (the thief's StealEvents)
	  Kit.drive(sim, p, to, speed, opts?) moves the HRP every frame at `speed` studs/s towards `to`
	                                (horizontally), whatever the WalkSpeed (RbxSim cannot speed-hack
	                                otherwise; BE-35); opts.stall = { at, seconds } (the HRP stands
	                                still, then jumps to where it would be: a lagging phone),
	                                opts.hop = studs (one jump at the start), opts.stop(sim) -> true
	                                ends early, opts.timeout; returns true when it arrived
	  Kit.theftEvents(sim, p, kind?) the StealEvents this client got: { { time, kind, data } }
	  Kit.defenceEvents(sim, p, kind?) the DefenceEvents
	  Kit.exitPoint(base, kind)     a world point just outside the plot: "gate" | "side" (east) |
	                                "west" | "back" (the east arch), at the HRP's height
	  Kit.basePoint(base, x, z)     a base-local point (StealRules coordinates) in the world
	  Kit.sizesZero4(t, sim, what)  StealService, DefenceService, Lib/Speed and Lib/DogBrain report
	                                nothing left (with the stage 3 services)
]]

local roblox = require("@lune/roblox")

local Base = require("./stage3_e2e_kit")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Kit = setmetatable({}, { __index = Base })

local StealConfig = Base.config("StealConfig")
local DefenceConfig = Base.config("DefenceConfig")
local MapConfig = Base.config("MapConfig")
Kit.StealConfig, Kit.DefenceConfig, Kit.MapConfig = StealConfig, DefenceConfig, MapConfig
Kit.STEAL_TEXTS = StealConfig.Texts
Kit.DEFENCE_TEXTS = DefenceConfig.Texts
Kit.WALK = 16 -- StarterPlayer.CharacterWalkSpeed
Kit.CARRY = Kit.WALK * StealConfig.Carry.SpeedFactor -- the honest carry, 13.6
Kit.HRP_HEIGHT = 3 -- the root above the ground

-- The Studio knob off (its own line in DefenceConfig: tests/stage4_rules pins it).
Kit.STUDIO_OFF = {
	path = "ReplicatedStorage.Shared.Config.DefenceConfig",
	from = "\t\tStudioProtect = 10,",
	to = "\t\tStudioProtect = false,",
}

type Patch = { path: string, from: string, to: string }

--------------------------------------------------------------------------------
-- Servers
--------------------------------------------------------------------------------

function Kit.boot(t: any, opts: { [string]: any }?): any
	local o = opts or {}
	local simOpts: { [string]: any } = {
		place = Base.PLACE,
		remoteLatency = o.latency or 0,
		dataStore = o.dataStore,
		epoch = o.epoch,
		seed = o.seed or 1,
	}
	if o.removingOrder then
		simOpts.removingOrder = o.removingOrder -- (S7: Sim.new({ removingOrder = "reverse" }))
	end
	local sim = t.sim(simOpts)
	local patches: { Patch } = {}
	if not o.studio then
		table.insert(patches, Kit.STUDIO_OFF)
	end
	for _, patch in o.patches or {} do
		table.insert(patches, patch)
	end
	for _, patch in patches do
		local module = sim:Find(patch.path)
		t.ok(module, `module {patch.path} exists`)
		local source = module.Source
		local start = string.find(source, patch.from, 1, true)
		t.ok(start, `patch anchor «{patch.from}» found in {patch.path}`)
		if start then
			module.Source = string.sub(source, 1, start - 1) .. patch.to .. string.sub(source, start + #patch.from)
		end
	end
	if o.before then
		o.before(sim)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

function Kit.restart(t: any, old: any, gap: number, opts: { [string]: any }?): any
	local o = table.clone(opts or {})
	o.dataStore = old.DataStore:Snapshot()
	o.epoch = Base.EPOCH + math.floor(old:Time()) + gap
	o.seed = o.seed or 2
	return Kit.boot(t, o)
end

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

-- A save poked before the join. spec.tank: { { Id, Kg?, Mutation?, Age?, Origin? } } in slot order.
function Kit.seed(sim: any, id: number, spec: { [string]: any }?): { [string]: any }
	local s = spec or {}
	local tank = {}
	for i, f in s.tank or {} do
		local extra: { [string]: any } = { Age = f.Age or 0, Mutation = f.Mutation, Origin = f.Origin }
		if f.Kg then
			extra.Kg = f.Kg
		end
		table.insert(tank, Base.savedFish(f.Id, f.Uid or `f{i}`, f.Slot or i, extra))
	end
	local changes: { [string]: any } = { Tank = tank, Money = s.money or 0 }
	if s.lock ~= nil then
		changes.LockLevel = s.lock
	end
	if s.upgrades ~= nil then
		changes.Upgrades = s.upgrades
	end
	if s.saveCount ~= nil then
		changes.SaveCount = s.saveCount
	end
	if s.stats ~= nil then
		-- merged over the template's stats (Kit.template derives Earned, Caught and Species from them)
		local stats: { [string]: any } = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} }
		for k, v in s.stats do
			stats[k] = v
		end
		changes.Stats = stats
	end
	return Base.pokeSave(sim, id, changes)
end

--------------------------------------------------------------------------------
-- The base and its points
--------------------------------------------------------------------------------

function Kit.basePoint(base: any, x: number, z: number, y: number?): any
	return base:GetPivot() * Vector3.new(x, y or 0, z)
end

function Kit.exitPoint(base: any, kind: string?): any
	local half = MapConfig.PlotHalfWidth
	local front = MapConfig.PlotFront
	local back = MapConfig.PlotFront + MapConfig.PlotDepth
	local out = StealConfig.Carry.ExitMargin + 2
	local exits = StealConfig.Exits
	local which = kind or "gate"
	local x, z
	if which == "gate" then
		x, z = 0, front - out
	elseif which == "side" or which == "east" then
		x, z = half + out, (exits.SideFrom + exits.SideTo) / 2
	elseif which == "west" then
		x, z = -(half + out), (exits.SideFrom + exits.SideTo) / 2
	elseif which == "back" then
		x, z = exits.ArchX, back + out
	else
		error(`Kit.exitPoint: unknown exit «{which}»`)
	end
	return Kit.basePoint(base, x, z, Kit.HRP_HEIGHT)
end

function Kit.stealPrompt(sim: any, owner: any, slot: number): any
	local display = Base.slot(sim, owner, slot)
	local attachment = display and display.Pedestal:FindFirstChild("PromptAttachment")
	return attachment and attachment:FindFirstChild("StealPrompt")
end

-- 2 studs in front of the prompt (towards the aisle), at the HRP's height, facing it.
function Kit.standAt(sim: any, p: any, prompt: any)
	local attachment = prompt.Parent
	local pedestal = attachment.Parent
	local at = (pedestal.CFrame * attachment.CFrame).Position
	local out = at - pedestal.CFrame.Position
	local dir = Vector3.new(out.X, 0, out.Z)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
	local ground = pedestal.Position.Y - pedestal.Size.Y / 2
	local spot = Vector3.new(at.X, ground + Kit.HRP_HEIGHT, at.Z) + dir * 2
	sim:Teleport(p, CFrame.lookAt(spot, Vector3.new(at.X, spot.Y, at.Z)))
	sim:Advance(Base.FRAME)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local function events(sim: any, p: any, remote: string, kind: string?): { any }
	local out = {}
	for _, e in sim:ClientEventsFor(p, remote) do
		if kind == nil or e.args[1] == kind then
			table.insert(out, { time = e.time, kind = e.args[1], data = e.args[2] })
		end
	end
	return out
end

function Kit.theftEvents(sim: any, p: any, kind: string?): { any }
	return events(sim, p, "StealEvent", kind)
end

function Kit.defenceEvents(sim: any, p: any, kind: string?): { any }
	return events(sim, p, "DefenceEvent", kind)
end

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------

-- Moves the HRP every frame at `speed` studs/s (horizontally) towards `to`, whatever the
-- WalkSpeed: what a speed hack (or a lagging phone, opts.stall) looks like to the server.
function Kit.drive(sim: any, p: any, to: any, speed: number, opts: { [string]: any }?): boolean
	local o = opts or {}
	local frame = Base.FRAME
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	assert(root, `Kit.drive: {p.Name} has no character`)
	local goal = Vector3.new(to.X, 0, to.Z)
	local function flatHere(): any
		local pos = root.Position
		return Vector3.new(pos.X, 0, pos.Z)
	end
	local function place(at: any)
		local y = root.Position.Y
		local pos = Vector3.new(at.X, y, at.Z)
		local ahead = goal - Vector3.new(at.X, 0, at.Z)
		local look = if ahead.Magnitude > 1e-3 then pos + ahead.Unit else pos + root.CFrame.LookVector
		sim:Teleport(p, CFrame.lookAt(pos, Vector3.new(look.X, y, look.Z)))
	end
	if o.hop then
		local here = flatHere()
		local ahead = goal - here
		if ahead.Magnitude > 1e-3 then
			place(here + ahead.Unit * math.min(o.hop, ahead.Magnitude))
		end
	end
	local elapsed, timeout = 0, o.timeout or 60
	local stall = o.stall
	local owed = 0 -- studs the stall held back (paid in one jump when it ends)
	while elapsed < timeout do
		if o.stop and o.stop(sim) then
			return false
		end
		local here = flatHere()
		local ahead = goal - here
		if ahead.Magnitude < 0.05 then
			return true
		end
		local stalling = stall and elapsed >= stall.at and elapsed < stall.at + stall.seconds
		if stalling then
			owed += speed * frame
		else
			local step = math.min(ahead.Magnitude, speed * frame + owed)
			owed = 0
			place(here + ahead.Unit * step)
		end
		sim:Advance(frame)
		elapsed += frame
	end
	return false
end

--------------------------------------------------------------------------------
-- A theft as a player does it
--------------------------------------------------------------------------------

local function cancelNow(t: any, sim: any, thief: any, owner: any, prompt: any, how: string)
	if how == "release" then
		sim:ReleasePrompt(thief, prompt)
	elseif how == "walk" then
		local root = thief.Character.HumanoidRootPart
		sim:Teleport(thief, root.Position + root.CFrame.LookVector * -12)
	elseif how == "die" then
		sim:KillCharacter(thief)
	elseif how == "tag" then
		local root = thief.Character.HumanoidRootPart
		sim:Teleport(owner, root.Position + Vector3.new(StealConfig.Tag.Range - 1, 0, 0))
	elseif how == "leave" then
		sim:RemovePlayer(thief)
	elseif how == "shield" then
		sim:FireServer(owner, "ShieldActivate")
	else
		t.ok(false, `Kit.steal: unknown cancel «{how}»`)
	end
	sim:Advance(0.2)
end

function Kit.steal(t: any, sim: any, thief: any, owner: any, slot: number, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local prompt = Kit.stealPrompt(sim, owner, slot)
	t.ok(prompt, `Slot_{slot} of {owner.Name} has a StealPrompt`)
	local result: { [string]: any } = { prompt = prompt }
	if not prompt then
		return result
	end
	Kit.standAt(sim, thief, prompt)
	local hold = sim:BeginHold(thief, prompt, o.holdOpts)
	result.hold = hold
	if not hold.active then
		result.triggered = false
		result.events = Kit.theftEvents(sim, thief)
		return result
	end
	local phase = o.phase or "hold"
	if o.cancel and phase == "hold" then
		sim:Advance(math.min(1, (o.holdFor or prompt.HoldDuration) / 2))
		cancelNow(t, sim, thief, owner, prompt, o.cancel)
		result.triggered = hold.triggered
		result.events = Kit.theftEvents(sim, thief)
		return result
	end
	sim:Advance(o.holdFor or (prompt.HoldDuration + Base.FRAME))
	result.triggered = hold.triggered
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.1)
	if o.cancel and phase == "carry" then
		sim:Advance(0.5)
		cancelNow(t, sim, thief, owner, prompt, o.cancel)
	elseif thief.Parent and thief.Character then
		local base = Base.baseOf(sim, owner)
		Kit.drive(sim, thief, Kit.exitPoint(base, o.exit or "gate"), o.speed or Kit.CARRY, {
			stop = function()
				return thief:GetAttribute("Stealing") == nil
			end,
			timeout = StealConfig.Carry.Timeout + 2,
		})
		sim:Advance(0.5)
	end
	result.events = Kit.theftEvents(sim, thief)
	return result
end

--------------------------------------------------------------------------------
-- Leaks
--------------------------------------------------------------------------------

function Kit.sizesZero4(t: any, sim: any, what: string)
	Base.sizesZero(t, sim, what)
	for _, name in { "StealService", "DefenceService" } do
		for k, size in Base.service(sim, name)._debugSizes() do
			t.eq(size, 0, `{what}: {name}._debugSizes().{k}`)
		end
	end
	for _, lib in { "Speed", "DogBrain" } do
		local module = sim:Require(sim:Find(`ServerScriptService.Lib.{lib}`))
		for k, size in module._debugSizes() do
			t.eq(size, 0, `{what}: {lib}._debugSizes().{k}`)
		end
	end
end

return Kit
