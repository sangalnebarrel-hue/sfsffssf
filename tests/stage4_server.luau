--[[
	Stage 4 server kit — helpers shared by the Wave 1 A server suites (tests/stage4_theft*,
	stage4_data*, stage4_defence*; docs/stage4_design.md §7.2–§7.4). Not a test file itself
	(tools/run_tests.luau only runs tests/*.test.luau). Everything of tests/stage4_kit.luau (and
	through it tests/stage3_e2e_kit.luau) is here too: S falls back to Kit.

	The players are headless (clientDelay = 1e9: no client scripts, the server and the DataStore
	run for real; holds go through sim:BeginHold like a stock prompt). opts.client = true starts a
	light client (the TheftController filter tests).

	  S.player(t, sim, id, spec?)      a player with a seeded save (Kit.seed: spec.tank / money /
	                                   lock / upgrades / saveCount / stats; spec.lastOnline; no
	                                   spec.tank and spec.fresh → a brand-new save), waited until
	                                   loaded and mounted; spec.protected keeps the join protection
	                                   (otherwise S.unprotect)
	  S.unprotect(sim, p)              DefenceService:EndProtection(p, "test") (the stage is set)
	  S.prompt(sim, owner, slot)       the StealPrompt of that display
	  S.hold(t, sim, thief, owner, slot, opts?)  stand 2 studs in front of the display and begin a
	                                   stock hold (opts: BeginHold's ignoreDistance / ignoreEnabled)
	  S.toCarry(t, sim, thief, owner, slot)       a whole hold → the carry phase (asserted)
	  S.out(sim, thief, owner, exit?, speed?, opts?)  Kit.drive from where he stands to an exit
	  S.events(sim, p, kind?) / S.last(sim, p, kind) the StealEvents of a player
	  S.slotAttrs(sim, owner, slot)    the display's attributes (fish fields and the steal channel)
	  S.walk(p)                        Humanoid.WalkSpeed
	  S.tankOf(sim, p) / S.rowOf(data, uid)       the live data rows
	  S.serverRun(sim, fn)             sim:Run(fn) (server context), returns its value
]]

local roblox = require("@lune/roblox")

local Kit = require("./stage4_kit")

local Vector3 = roblox.Vector3

local S = setmetatable({}, { __index = Kit })

S.FRAME = Kit.FRAME
S.COARSE = Kit.COARSE
S.LIMITS = Kit.StealConfig.Limits
S.CARRY_CFG = Kit.StealConfig.Carry
S.HOLD_CFG = Kit.StealConfig.Hold
S.SHIELD = Kit.DefenceConfig.Shield
S.DOG = Kit.DefenceConfig.Dog
S.LOCK = Kit.DefenceConfig.Lock
S.BASE_HOLD = Kit.DefenceConfig.Lock.BaseHold
S.Vector3 = Vector3

function S.Vector3up(y: number): any
	return Vector3.new(0, y, 0)
end

function S.serverRun(sim: any, fn: () -> any): any
	return sim:Run(fn)
end

function S.unprotect(sim: any, p: any)
	local defence = Kit.service(sim, "DefenceService")
	sim:Run(function()
		defence:EndProtection(p, "test")
	end)
end

-- A headless player with a seeded save, loaded, with a mounted tank.
function S.player(t: any, sim: any, id: number, spec: { [string]: any }?): any
	local s = spec or {}
	if not s.fresh then
		local seed = table.clone(s)
		Kit.seed(sim, id, seed)
		if s.lastOnline ~= nil or s.saveCount ~= nil then
			local key = Kit.key(id)
			local data = sim.DataStore:Peek(Kit.STORE, key)
			if s.lastOnline ~= nil then
				data.LastOnline = s.lastOnline
			end
			sim.DataStore:Poke(Kit.STORE, key, data)
		end
	end
	local p = sim:AddPlayer({
		UserId = id,
		Name = `Player{id}`,
		DisplayName = s.name or `Игрок{id}`,
		clientDelay = if s.client then nil else 1e9,
		device = s.device or "phone",
	})
	local tank = Kit.service(sim, "TankService")
	local ready = sim:WaitFor(function()
		local mode = p:GetAttribute("DataMode")
		return mode ~= nil and mode ~= "Loading" and p.Character ~= nil and tank:IsMounted(p)
	end, s.timeout or 12, Kit.COARSE)
	t.ok(ready, `{p.Name}: loaded, a character, a mounted tank`)
	sim:Advance(0.1)
	if not s.protected then
		S.unprotect(sim, p)
	end
	return p
end

function S.prompt(sim: any, owner: any, slot: number): any
	return Kit.stealPrompt(sim, owner, slot)
end

function S.hold(t: any, sim: any, thief: any, owner: any, slot: number, opts: { [string]: any }?): (any, any)
	local prompt = S.prompt(sim, owner, slot)
	t.ok(prompt, `Slot_{slot} of {owner.Name} has a StealPrompt`)
	Kit.standAt(sim, thief, prompt)
	local hold = sim:BeginHold(thief, prompt, opts)
	sim:Advance(S.FRAME)
	return hold, prompt
end

-- A complete hold: the carry starts (Stealing = "carry").
function S.toCarry(t: any, sim: any, thief: any, owner: any, slot: number): any
	local hold, prompt = S.hold(t, sim, thief, owner, slot)
	t.ok(hold.active, `the hold on Slot_{slot} began ({hold.cancelReason})`)
	t.eq(thief:GetAttribute("Stealing"), "hold", "Stealing = hold")
	local carried = sim:WaitFor(function()
		return thief:GetAttribute("Stealing") == "carry"
	end, prompt.HoldDuration + 1, S.FRAME)
	t.ok(carried, `the carry began ({thief:GetAttribute("Stealing")})`)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(S.FRAME)
	return prompt
end

function S.out(sim: any, thief: any, owner: any, exit: string?, speed: number?, opts: { [string]: any }?): boolean
	local base = Kit.baseOf(sim, owner)
	local o = table.clone(opts or {})
	o.stop = o.stop or function()
		return thief:GetAttribute("Stealing") == nil
	end
	o.timeout = o.timeout or (Kit.StealConfig.Carry.Timeout + 2)
	local arrived = Kit.drive(sim, thief, Kit.exitPoint(base, exit or "gate"), speed or Kit.CARRY, o)
	sim:Advance(0.3)
	return arrived
end

function S.events(sim: any, p: any, kind: string?): { any }
	return Kit.theftEvents(sim, p, kind)
end

function S.last(sim: any, p: any, kind: string): any
	local list = Kit.theftEvents(sim, p, kind)
	local e = list[#list]
	return e and e.data
end

function S.slotAttrs(sim: any, owner: any, slot: number): { [string]: any }
	return Kit.slot(sim, owner, slot):GetAttributes()
end

function S.walk(p: any): number
	local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.WalkSpeed else -1
end

function S.tankOf(sim: any, p: any): { any }
	local data = Kit.service(sim, "DataService"):Get(p)
	return if data then data.Tank else {}
end

function S.rowOf(rows: { any }?, uid: string): any
	for _, row in rows or {} do
		if row.Uid == uid then
			return row
		end
	end
	return nil
end

function S.rowByOrigin(rows: { any }?, origin: string): any
	for _, row in rows or {} do
		if row.Origin == origin then
			return row
		end
	end
	return nil
end

-- A fish straight into a tank through the server (reason "catch" by default: FreshUntil set).
function S.addFish(sim: any, p: any, id: string, kg: number?, reason: string?): any
	local rules = Kit.shared(sim, "FishingRules")
	local def = Kit.fishDef(id)
	local weight = kg or def.MinKg
	local value, income = rules.Price(id, weight, nil)
	local tank = Kit.service(sim, "TankService")
	return sim:Run(function()
		return tank:AddFish(
			p,
			{ Id = id, Rarity = def.Rarity, Kg = weight, Value = value, Income = income },
			reason or "catch"
		)
	end)
end

-- One hold attempt that the server should refuse: the Denied payload (nil — none came).
function S.denied(t: any, sim: any, thief: any, owner: any, slot: number, opts: { [string]: any }?): any
	local before = #Kit.theftEvents(sim, thief, "Denied")
	local o = opts or {}
	local prompt = S.prompt(sim, owner, slot)
	if o.fire then
		sim:FirePromptEvent(thief, prompt, "HoldBegan")
		sim:Advance(S.FRAME)
	else
		local hold = S.hold(t, sim, thief, owner, slot, o.holdOpts or { ignoreEnabled = true })
		if hold.active then
			sim:ReleasePrompt(thief, prompt)
		end
	end
	sim:Advance(S.FRAME)
	local list = Kit.theftEvents(sim, thief, "Denied")
	return if #list > before then list[#list].data else nil
end

-- Teleports a player's character (keeps the height).
function S.moveTo(sim: any, p: any, at: any)
	sim:Teleport(p, at)
	sim:Advance(S.FRAME)
end

-- A world point next to the thief (owner tag tests).
function S.beside(p: any, dx: number): any
	local root = p.Character.HumanoidRootPart
	return root.Position + Vector3.new(dx, 0, 0)
end

return S
