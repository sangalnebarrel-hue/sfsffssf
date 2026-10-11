-- run_tests.luau: discovers and runs RbxSim test files.
--
-- Usage (from anywhere):
--   /opt/tools/l11/lune run tools/run_tests.luau [filters...] [--inproc] [--verbose] [--list]
--
-- Discovers tests/*.test.luau and tests/sim_selftest*.luau. Each file runs in
-- its own Lune process (fresh sims, fresh module caches). A test file returns
-- either { [name] = function(t) ... end } or a list of { name = ..., fn = ... }
-- (or { "name", fn }). Filters are plain substrings matched against
-- "tests/file.luau::test name"; a test runs if any filter matches.
-- Exit code is non-zero when any test fails or a file crashes.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local MARK = "@@SIMTEST "

local function scriptPath(): string
	local src = debug.info(1, "s")
	src = string.gsub(src, "^@", "")
	return src
end

local function dirname(p: string): string
	return (string.match(p, "^(.*)/[^/]*$")) or "."
end

local ROOT = dirname(dirname(scriptPath()))
local SELF = ROOT .. "/tools/run_tests.luau"
local LUNE = process.env.LUNE_BIN or "/opt/tools/l11/lune"

-- Assertions ----------------------------------------------------------------------------------

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	if type(v) == "table" then
		local ok, s = pcall(serde.encode, "json", v)
		if ok then
			return s
		end
	end
	return tostring(v)
end

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if k ~= "n" or rawget(b, "n") ~= nil then
			if not deepEqual(v, b[k], seen) then
				return false
			end
		end
	end
	for k in pairs(b) do
		if a[k] == nil and k ~= "n" then
			return false
		end
	end
	return true
end

local function makeT(ctx)
	local t = {}
	t.root = ROOT
	t.place = ROOT .. "/Place1.rbxl"
	t.basePlace = ROOT .. "/tools/base/Place1.base.rbxl"
	t.sims = ctx.sims

	local function fail(msg, level)
		error(msg, (level or 1) + 2)
	end

	function t.ok(v, msg)
		if not v then
			fail("assertion failed: " .. (msg or "expected truthy, got " .. fmt(v)), 1)
		end
		return v
	end

	function t.eq(a, b, msg)
		if not deepEqual(a, b) then
			fail(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", fmt(b), fmt(a)), 1)
		end
	end

	function t.neq(a, b, msg)
		if deepEqual(a, b) then
			fail(string.format("%sexpected values to differ, both %s", msg and (msg .. ": ") or "", fmt(a)), 1)
		end
	end

	function t.near(a, b, eps, msg)
		eps = eps or 1e-6
		local d
		if type(a) == "number" and type(b) == "number" then
			d = math.abs(a - b)
		elseif typeof(a) == "CFrame" and typeof(b) == "CFrame" then
			d = (a.Position - b.Position).Magnitude
			local r1, r2 = { a:GetComponents() }, { b:GetComponents() }
			for i = 4, 12 do
				d = math.max(d, math.abs(r1[i] - r2[i]))
			end
		elseif typeof(a) == typeof(b) and (typeof(a) == "Vector3" or typeof(a) == "Vector2") then
			d = (a - b).Magnitude
		else
			fail(string.format("%scannot compare %s and %s with near()", msg and (msg .. ": ") or "", typeof(a), typeof(b)), 1)
		end
		if d > eps then
			fail(string.format("%sexpected %s ~= %s (eps %g, diff %g)", msg and (msg .. ": ") or "", tostring(a), tostring(b), eps, d), 1)
		end
	end

	function t.match(s, pattern, msg)
		if type(s) ~= "string" or not string.find(s, pattern) then
			fail(string.format("%sexpected %s to match %q", msg and (msg .. ": ") or "", fmt(s), pattern), 1)
		end
	end

	function t.fail(msg)
		fail(msg or "failed", 1)
	end

	-- Calls fn and expects it to error; returns the error message.
	function t.throws(fn, pattern, msg)
		local ok, err = pcall(fn)
		if ok then
			fail((msg and (msg .. ": ") or "") .. "expected an error", 1)
		end
		local s = tostring(err)
		if pattern and not string.find(s, pattern) then
			fail(string.format("%serror %q does not match %q", msg and (msg .. ": ") or "", s, pattern), 1)
		end
		return s
	end

	function t.skip(reason)
		error({ __skip = true, reason = reason or "skipped" }, 0)
	end

	function t.log(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		print(table.concat(parts, " "))
	end

	function t.sim(opts)
		local Sim = require("./sim")
		local s = Sim.new(opts)
		table.insert(ctx.sims, s)
		return s
	end

	return t
end

-- Child mode: run one file and emit machine-readable results --------------------------------------

local function emit(record)
	print(MARK .. serde.encode("json", record))
end

local function normalizeSuite(suite)
	local list = {}
	if type(suite) ~= "table" then
		return nil
	end
	if #suite > 0 then
		for i, item in suite do
			if type(item) == "function" then
				table.insert(list, { name = "test " .. i, fn = item })
			elseif type(item) == "table" then
				local name = item.name or item[1]
				local fn = item.fn or item[2]
				table.insert(list, { name = tostring(name), fn = fn })
			end
		end
	else
		local names = {}
		for k in pairs(suite) do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			table.insert(list, { name = tostring(k), fn = suite[k] })
		end
	end
	return list
end

local function matchesFilters(id: string, filters)
	if #filters == 0 then
		return true
	end
	for _, f in filters do
		if string.find(id, f, 1, true) then
			return true
		end
	end
	return false
end

-- Keeps only traceback lines that point into the test file itself.
local function trimTraceback(tb: string, rel: string): string
	local keep, seen = {}, {}
	local base = string.match(rel, "([^/]+)%.luau$") or rel
	for line in string.gmatch(tb, "[^\n]+") do
		local loc = string.match(line, "(" .. string.gsub(base, "%p", "%%%0") .. ":%d+)")
		if loc and not seen[loc] then
			seen[loc] = true
			table.insert(keep, "    at " .. loc)
		end
	end
	return table.concat(keep, "\n")
end

local function cleanMessage(msg: string): string
	msg = string.gsub(msg, "^runtime error: ", "")
	local cut = string.find(msg, "\nstack traceback:", 1, true) or string.find(msg, "\n%[Stack Begin%]")
	if cut then
		msg = string.sub(msg, 1, cut - 1)
	end
	return msg
end

local function runFile(rel: string, filters, report)
	local modPath = "../" .. string.gsub(rel, "%.luau$", "")
	local ok, suite = pcall(require, modPath)
	if not ok then
		report({ kind = "load_error", file = rel, message = tostring(suite) })
		return
	end
	local list = normalizeSuite(suite)
	if list == nil then
		report({ kind = "load_error", file = rel, message = "test file must return a table of tests" })
		return
	end
	for _, item in list do
		local id = rel .. "::" .. item.name
		if matchesFilters(id, filters) then
			local ctx = { sims = {} }
			local t = makeT(ctx)
			local start = os.clock()
			local okRun, err = xpcall(item.fn, function(e)
				if type(e) == "table" and e.__skip then
					return e
				end
				return { message = tostring(e), traceback = debug.traceback(tostring(e), 2) }
			end, t)
			local ms = math.floor((os.clock() - start) * 1000 + 0.5)
			if okRun then
				report({ kind = "result", file = rel, name = item.name, status = "pass", ms = ms })
			elseif type(err) == "table" and err.__skip then
				report({ kind = "result", file = rel, name = item.name, status = "skip", ms = ms, message = err.reason })
			else
				local msg = cleanMessage(err.message)
				local where = trimTraceback((err.traceback or "") .. "\n" .. err.message, rel)
				if where ~= "" then
					msg ..= "\n" .. where
				end
				for i, s in ctx.sims do
					if #s.Errors > 0 then
						msg ..= string.format("\n  sim #%d captured script errors:\n%s", i, (string.gsub(s:FormatErrors(), "([^\n]+)", "    %1")))
					end
				end
				report({ kind = "result", file = rel, name = item.name, status = "fail", ms = ms, message = msg })
			end
		end
	end
end

-- Discovery / parent mode ---------------------------------------------------------------------------

local function discover()
	local files = {}
	local dir = ROOT .. "/tests"
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if string.match(name, "%.test%.luau$") or string.match(name, "^sim_selftest.*%.luau$") then
				table.insert(files, "tests/" .. name)
			end
		end
	end
	table.sort(files)
	return files
end

local args = process.args
local filters = {}
local childFile, inproc, verbose, listOnly = nil, false, false, false
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--child" then
		childFile = args[i + 1]
		i += 1
	elseif a == "--inproc" then
		inproc = true
	elseif a == "--verbose" or a == "-v" then
		verbose = true
	elseif a == "--list" then
		listOnly = true
	else
		table.insert(filters, a)
	end
	i += 1
end

if childFile then
	runFile(childFile, filters, emit)
	process.exit(0)
end

local files = discover()
local passed, failed, skipped = 0, 0, 0
local failures = {}

local function printResult(r)
	if r.kind == "load_error" then
		failed += 1
		table.insert(failures, r.file .. " (load error)")
		print(string.format("FAIL %s (load error)\n  %s", r.file, (string.gsub(r.message, "\n", "\n  "))))
		return
	end
	local label = string.format("%s :: %s", r.file, r.name)
	if r.status == "pass" then
		passed += 1
		print(string.format("PASS %s (%d ms)", label, r.ms))
	elseif r.status == "skip" then
		skipped += 1
		print(string.format("SKIP %s (%s)", label, r.message or ""))
	else
		failed += 1
		table.insert(failures, label)
		print(string.format("FAIL %s (%d ms)\n  %s", label, r.ms, (string.gsub(r.message or "", "\n", "\n  "))))
	end
end

if listOnly then
	for _, rel in files do
		print(rel)
	end
	process.exit(0)
end

for _, rel in files do
	local fileFilters = {}
	local wholeFile = false
	for _, f in filters do
		if string.find(rel, f, 1, true) then
			wholeFile = true
		end
	end
	if not wholeFile then
		fileFilters = filters
	end
	if inproc then
		runFile(rel, fileFilters, printResult)
	else
		local childArgs = { "run", SELF, "--child", rel }
		for _, f in fileFilters do
			table.insert(childArgs, f)
		end
		local res = process.exec(LUNE, childArgs, { cwd = ROOT })
		local gotResult = false
		local otherOutput = {}
		for line in string.gmatch(res.stdout, "[^\n]*") do
			if string.sub(line, 1, #MARK) == MARK then
				gotResult = true
				printResult(serde.decode("json", string.sub(line, #MARK + 1)))
			elseif line ~= "" then
				table.insert(otherOutput, line)
			end
		end
		if verbose and #otherOutput > 0 then
			print("  output of " .. rel .. ":\n    " .. table.concat(otherOutput, "\n    "))
		end
		if not res.ok then
			failed += 1
			table.insert(failures, rel .. " (crashed)")
			print(string.format("FAIL %s (process exited with code %d)", rel, res.code))
			local tail = res.stderr ~= "" and res.stderr or table.concat(otherOutput, "\n")
			print("  " .. (string.gsub(string.sub(tail, -3000), "\n", "\n  ")))
		elseif not gotResult and #fileFilters == 0 then
			print(string.format("WARN %s produced no test results", rel))
		end
	end
end

print(string.format("\n%d passed, %d failed, %d skipped", passed, failed, skipped))
if failed > 0 then
	print("Failures:")
	for _, f in failures do
		print("  - " .. f)
	end
	process.exit(1)
end
process.exit(0)
