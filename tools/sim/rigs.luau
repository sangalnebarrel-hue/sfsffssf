-- rigs.luau: optional R15 / R6 character rigs (sim:AddPlayer({ rig = "R15" | "R6",
-- joints = "Motor6D" | "AnimationConstraint" })) and the engine work around them:
--
--   * body parts and joints with the standard Roblox names (R6 C0/C1 exact, R15 a block
--     approximation of the classic proportions), RigAttachments, RightGripAttachment,
--     Humanoid.RigType; AnimationConstraint rigs ("Avatar Joint Upgrade") keep their frames in
--     Attachment0/Attachment1 like the engine (C0/C1 are not written);
--   * the Animator stand-in: every frame after RunService.PreAnimation each rig joint's
--     Transform is reset to the emulated animation pose (sim:SetAnimatorPose, identity by
--     default) on the server and on every client (client-local Transform writes are dropped),
--     except on frames throttled with sim:ThrottleAnimator (then Animator.EvaluationThrottled
--     is true and Transform keeps whatever was written last);
--   * forward kinematics after PreSimulation (and humanoid walking): Part1 = Part0 * C0 *
--     Transform * C1:Inverse() for Motor6D / AnimationConstraint / Weld, from the
--     HumanoidRootPart outwards, so limbs, the equipped Tool (RightGrip) and anything welded
--     (HeldFish) follow the pose. Solved once with the replicated values and once per client
--     that wrote client-local joint values (Transform, C0, C1, attachment CFrames): that
--     client sees its own pose, everyone else the replicated one — like Roblox, where joint
--     writes made by a client never replicate. Part CFrames are written without Changed events;
--   * Tool equip/unequip on a rigged character adds / removes the "RightGrip" Weld (C0 = the
--     hand's grip attachment, C1 = Tool.Grip), like the engine.
-- Characters without the option keep the minimal HumanoidRootPart + Head body and cost nothing.

local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Instance = roblox.Instance
local Enum = roblox.Enum

local Rigs = {}
Rigs.__index = Rigs

local function cf(x, y, z, ...)
	if select("#", ...) > 0 then
		return CFrame.new(x, y, z, ...)
	end
	return CFrame.new(x, y, z)
end

local R6_ROOT = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local R6_R = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local R6_L = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }

-- parts: name -> size; joints: { name, part0, part1, C0, C1 } in parent-before-child order.
-- HumanoidRootPart (2×2×1) stands 3 studs above the floor, like the default characters.
local SPECS = {
	R15 = {
		hipHeight = 2,
		hand = "RightHand",
		grip = cf(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0),
		parts = {
			LowerTorso = Vector3.new(2, 0.4, 1),
			UpperTorso = Vector3.new(2, 1.6, 1),
			Head = Vector3.new(1.2, 1.2, 1.2),
			RightUpperArm = Vector3.new(1, 1.17, 1),
			RightLowerArm = Vector3.new(1, 1.05, 1),
			RightHand = Vector3.new(1, 0.3, 1),
			LeftUpperArm = Vector3.new(1, 1.17, 1),
			LeftLowerArm = Vector3.new(1, 1.05, 1),
			LeftHand = Vector3.new(1, 0.3, 1),
			RightUpperLeg = Vector3.new(1, 1.2, 1),
			RightLowerLeg = Vector3.new(1, 1, 1),
			RightFoot = Vector3.new(1, 0.2, 1),
			LeftUpperLeg = Vector3.new(1, 1.2, 1),
			LeftLowerLeg = Vector3.new(1, 1, 1),
			LeftFoot = Vector3.new(1, 0.2, 1),
		},
		joints = {
			{ "Root", "HumanoidRootPart", "LowerTorso", cf(0, -0.6, 0), cf(0, 0.2, 0) },
			{ "Waist", "LowerTorso", "UpperTorso", cf(0, 0.2, 0), cf(0, -0.8, 0) },
			{ "Neck", "UpperTorso", "Head", cf(0, 0.8, 0), cf(0, -0.6, 0) },
			{ "RightShoulder", "UpperTorso", "RightUpperArm", cf(1, 0.56, 0), cf(-0.5, 0.42, 0) },
			{ "RightElbow", "RightUpperArm", "RightLowerArm", cf(0, -0.42, 0), cf(0, 0.4, 0) },
			{ "RightWrist", "RightLowerArm", "RightHand", cf(0, -0.5, 0), cf(0, 0.12, 0) },
			{ "LeftShoulder", "UpperTorso", "LeftUpperArm", cf(-1, 0.56, 0), cf(0.5, 0.42, 0) },
			{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", cf(0, -0.42, 0), cf(0, 0.4, 0) },
			{ "LeftWrist", "LeftLowerArm", "LeftHand", cf(0, -0.5, 0), cf(0, 0.12, 0) },
			{ "RightHip", "LowerTorso", "RightUpperLeg", cf(0.5, -0.2, 0), cf(0, 0.5, 0) },
			{ "RightKnee", "RightUpperLeg", "RightLowerLeg", cf(0, -0.5, 0), cf(0, 0.45, 0) },
			{ "RightAnkle", "RightLowerLeg", "RightFoot", cf(0, -0.45, 0), cf(0, 0, 0) },
			{ "LeftHip", "LowerTorso", "LeftUpperLeg", cf(-0.5, -0.2, 0), cf(0, 0.5, 0) },
			{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", cf(0, -0.5, 0), cf(0, 0.45, 0) },
			{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", cf(0, -0.45, 0), cf(0, 0, 0) },
		},
	},
	R6 = {
		hipHeight = 0,
		hand = "Right Arm",
		grip = cf(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0),
		parts = {
			Torso = Vector3.new(2, 2, 1),
			Head = Vector3.new(2, 1, 1),
			["Right Arm"] = Vector3.new(1, 2, 1),
			["Left Arm"] = Vector3.new(1, 2, 1),
			["Right Leg"] = Vector3.new(1, 2, 1),
			["Left Leg"] = Vector3.new(1, 2, 1),
		},
		joints = {
			{
				"RootJoint",
				"HumanoidRootPart",
				"Torso",
				cf(0, 0, 0, table.unpack(R6_ROOT)),
				cf(0, 0, 0, table.unpack(R6_ROOT)),
			},
			{ "Neck", "Torso", "Head", cf(0, 1, 0, table.unpack(R6_ROOT)), cf(0, -0.5, 0, table.unpack(R6_ROOT)) },
			{
				"Right Shoulder",
				"Torso",
				"Right Arm",
				cf(1, 0.5, 0, table.unpack(R6_R)),
				cf(-0.5, 0.5, 0, table.unpack(R6_R)),
			},
			{
				"Left Shoulder",
				"Torso",
				"Left Arm",
				cf(-1, 0.5, 0, table.unpack(R6_L)),
				cf(0.5, 0.5, 0, table.unpack(R6_L)),
			},
			{ "Right Hip", "Torso", "Right Leg", cf(1, -1, 0, table.unpack(R6_R)), cf(0.5, 1, 0, table.unpack(R6_R)) },
			{ "Left Hip", "Torso", "Left Leg", cf(-1, -1, 0, table.unpack(R6_L)), cf(-0.5, 1, 0, table.unpack(R6_L)) },
		},
	},
}
Rigs.SPECS = SPECS

function Rigs.new(sim)
	local self = setmetatable({}, Rigs)
	self.sim = sim
	-- raw character -> { kind, jointClass, player, list (joint instances, nil = rescan) }
	self.chars = setmetatable({}, { __mode = "k" })
	self.count = 0
	self.poses = setmetatable({}, { __mode = "k" }) -- raw player -> { [jointName] = CFrame }
	-- (Strong keys: a raw instance's userdata is only interned while something holds it, so a
	-- weak key written in one frame and read later through a fresh lookup could vanish under GC
	-- — a flaky EvaluationThrottled. The tables live as long as this sim, i.e. one test.)
	self.throttle = {} -- raw player -> every Nth frame skipped
	self.throttled = {} -- raw Animator -> skipped this frame
	return self
end

function Rigs.validate(opts)
	if opts.rig ~= nil and SPECS[opts.rig] == nil then
		error('RbxSim: AddPlayer rig must be "R15" or "R6"', 3)
	end
	if opts.joints ~= nil and opts.joints ~= "Motor6D" and opts.joints ~= "AnimationConstraint" then
		error('RbxSim: AddPlayer joints must be "Motor6D" or "AnimationConstraint"', 3)
	end
	if opts.joints == "AnimationConstraint" and opts.rig ~= "R15" then
		error("RbxSim: AnimationConstraint joints exist on R15 rigs only", 3)
	end
end

-- Adds body parts and joints to a freshly built minimal character (HumanoidRootPart, Head,
-- Humanoid already there; the HumanoidRootPart already at its spawn CFrame).
function Rigs:build(char, playerReal, kind: string, jointClass: string?)
	local spec = SPECS[kind]
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	hum.RigType = if kind == "R15" then Enum.HumanoidRigType.R15 else Enum.HumanoidRigType.R6
	hum.HipHeight = spec.hipHeight
	local parts = { HumanoidRootPart = hrp }
	for name, size in spec.parts do
		local part = char:FindFirstChild(name)
		if part == nil then
			part = Instance.new("Part")
			part.Name = name
			part.Parent = char
		end
		part.Size = size
		part.CanCollide = false
		parts[name] = part
	end
	local motor = jointClass ~= "AnimationConstraint"
	for _, j in spec.joints do
		local name, p0, p1, c0, c1 = j[1], parts[j[2]], parts[j[3]], j[4], j[5]
		if motor then
			local m = Instance.new("Motor6D")
			m.Name = name
			m.Part0 = p0
			m.Part1 = p1
			m.C0 = c0
			m.C1 = c1
			m.Transform = CFrame.identity
			m.Parent = if kind == "R6" and name ~= "RootJoint" then p0 else p1
		else
			local a0 = Instance.new("Attachment")
			a0.Name = name .. "RigAttachment"
			a0.CFrame = c0
			a0.Parent = p0
			local a1 = Instance.new("Attachment")
			a1.Name = name .. "RigAttachment"
			a1.CFrame = c1
			a1.Parent = p1
			local ac = Instance.new("AnimationConstraint")
			ac.Name = name
			ac.Attachment0 = a0
			ac.Attachment1 = a1
			ac.Transform = CFrame.identity
			ac.Parent = p1
		end
	end
	local grip = Instance.new("Attachment")
	grip.Name = "RightGripAttachment"
	grip.CFrame = spec.grip
	grip.Parent = parts[spec.hand]
	self.chars[char] = {
		kind = kind,
		jointClass = jointClass or "Motor6D",
		player = playerReal,
		list = nil,
		views = setmetatable({}, { __mode = "k" }), -- client contexts with their own solve
	}
	self.count += 1
	-- rest pose right away (before the first frame)
	self:_solveView(char, self.chars[char], nil)
end

function Rigs:isRig(char): boolean
	return self.chars[char] ~= nil
end

-- A reparent inside / out of a rigged character: rescan its joints next frame.
function Rigs:onReparented(real, oldParent, newParent)
	if self.count == 0 then
		return
	end
	for char, info in self.chars do
		if
			(oldParent and (oldParent == char or oldParent:IsDescendantOf(char)))
			or (newParent and (newParent == char or newParent:IsDescendantOf(char)))
		then
			info.list = nil
		end
	end
	if real:IsA("Tool") then
		self:_onToolMoved(real, oldParent, newParent)
	end
end

local function jointList(char)
	local list = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") or d:IsA("Weld") then
			table.insert(list, d)
		end
	end
	return list
end

local function listOf(info, char)
	local list = info.list
	if list == nil then
		list = jointList(char)
		info.list = list
	end
	return list
end

-- Tools ---------------------------------------------------------------------------------------

function Rigs:_onToolMoved(tool, oldParent, newParent)
	local sim = self.sim
	local handle = tool:FindFirstChild("Handle")
	if oldParent and self.chars[oldParent] then
		for _, d in oldParent:GetDescendants() do
			if d:IsA("Weld") and d.Name == "RightGrip" and (d.Part1 == handle or d.Part1 == nil) then
				sim.proxy:destroy(d)
			end
		end
	end
	local info = newParent and self.chars[newParent]
	if info and handle and handle:IsA("BasePart") then
		local spec = SPECS[info.kind]
		local hand = newParent:FindFirstChild(spec.hand)
		local attachment = hand and hand:FindFirstChild("RightGripAttachment")
		if hand then
			local weld = Instance.new("Weld")
			weld.Name = "RightGrip"
			weld.Part0 = hand
			weld.Part1 = handle
			weld.C0 = if attachment then attachment.CFrame else spec.grip
			weld.C1 = tool.Grip
			sim.proxy:setParent(weld, hand)
		end
	end
end

-- Animator ------------------------------------------------------------------------------------

function Rigs:setPose(playerReal, poses)
	self.poses[playerReal] = poses
end

function Rigs:setThrottle(playerReal, everyN)
	self.throttle[playerReal] = if type(everyN) == "number" and everyN >= 1 then math.floor(everyN) else nil
end

function Rigs:isThrottled(animator): boolean
	return self.throttled[animator] == true
end

local function animatorOf(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

-- After PreAnimation: the emulated Animator writes every rig joint's Transform (server value;
-- client-local values are dropped) unless this frame is throttled.
function Rigs:animate(frame: number)
	if self.count == 0 then
		return
	end
	local proxy = self.sim.proxy
	for char, info in self.chars do
		if char.Parent ~= nil and not proxy:isDestroyed(char) then
			local animator = animatorOf(char)
			local every = self.throttle[info.player]
			local skip = every ~= nil and frame % every == 0
			if animator then
				self.throttled[animator] = skip or nil
			end
			if not skip then
				local pose = self.poses[info.player]
				for _, joint in listOf(info, char) do
					if not joint:IsA("Weld") then
						joint.Transform = (pose and pose[joint.Name]) or CFrame.identity
						for _, per in proxy.overlays do
							local o = per[joint]
							if o then
								o.Transform = nil
							end
						end
					end
				end
			end
		end
	end
end

-- Forward kinematics ---------------------------------------------------------------------------

-- Value of a property as one context sees it (nil ctx = the replicated value).
local function viewGet(proxy, ctx, real, key: string)
	if ctx then
		local per = proxy.overlays[ctx]
		local o = per and per[real]
		local v = o and o[key]
		if v ~= nil then
			if v == proxy.NIL then
				return nil
			end
			return v
		end
	end
	-- (Lune: a CFrame property never assigned reads as "missing default value")
	local ok, v = pcall(function()
		return real[key]
	end)
	return if ok then v else CFrame.identity
end

-- Joint as seen by a context: part0, part1, C0, C1, Transform (identity for welds).
local function jointView(proxy, ctx, joint)
	if joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 == nil or a1 == nil then
			return nil
		end
		return a0.Parent,
			a1.Parent,
			viewGet(proxy, ctx, a0, "CFrame"),
			viewGet(proxy, ctx, a1, "CFrame"),
			viewGet(proxy, ctx, joint, "Transform")
	end
	local transform = if joint:IsA("Motor6D") then viewGet(proxy, ctx, joint, "Transform") else CFrame.identity
	return joint.Part0, joint.Part1, viewGet(proxy, ctx, joint, "C0"), viewGet(proxy, ctx, joint, "C1"), transform
end

-- Solves the character for one view and writes the part CFrames (raw for the replicated view,
-- the context's overlay otherwise). Parts not connected to the HumanoidRootPart stay put.
function Rigs:_solveView(char, info, ctx)
	local proxy = self.sim.proxy
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp == nil then
		return
	end
	local edges = {}
	for _, joint in listOf(info, char) do
		if joint.Parent ~= nil then
			local p0, p1, c0, c1, transform = jointView(proxy, ctx, joint)
			if p0 and p1 and c0 and c1 and transform and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local e = { p0 = p0, p1 = p1, c0 = c0, c1 = c1, t = transform }
				edges[p0] = edges[p0] or {}
				table.insert(edges[p0], e)
				edges[p1] = edges[p1] or {}
				table.insert(edges[p1], e)
			end
		end
	end
	local solved = { [hrp] = proxy:get(hrp, "CFrame") }
	local queue = { hrp }
	local head = 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		local base = solved[part]
		for _, e in edges[part] or {} do
			local other, world
			if e.p0 == part then
				other = e.p1
				world = base * e.c0 * e.t * e.c1:Inverse()
			else
				other = e.p0
				world = base * e.c1 * e.t:Inverse() * e.c0:Inverse()
			end
			if solved[other] == nil and other ~= hrp then
				solved[other] = world
				table.insert(queue, other)
				if ctx then
					local o = proxy:overlayFor(ctx, other, true)
					o.CFrame = world
				else
					other.CFrame = world
				end
			end
		end
	end
end

-- Does this client hold client-local values for any joint frame of the character?
local function hasLocalJoints(proxy, ctx, list): boolean
	local per = proxy.overlays[ctx]
	if per == nil then
		return false
	end
	for _, joint in list do
		local o = per[joint]
		if o and (o.Transform ~= nil or o.C0 ~= nil or o.C1 ~= nil) then
			return true
		end
		if joint:IsA("AnimationConstraint") then
			local a0, a1 = joint.Attachment0, joint.Attachment1
			if (a0 and per[a0] and per[a0].CFrame ~= nil) or (a1 and per[a1] and per[a1].CFrame ~= nil) then
				return true
			end
		end
	end
	return false
end

-- After PreSimulation (and walking): every rigged character in the Workspace is solved for
-- the replicated view, then again for each client that posed it locally.
function Rigs:solve()
	if self.count == 0 then
		return
	end
	local sim = self.sim
	local proxy = sim.proxy
	for char, info in self.chars do
		if proxy:isDestroyed(char) then
			self.chars[char] = nil
			self.count -= 1
		elseif char.Parent ~= nil then
			self:_solveView(char, info, nil)
			local list = listOf(info, char)
			local views = info.views
			for _, ctx in sim.contexts do
				if ctx.kind == "client" and ctx.alive and hasLocalJoints(proxy, ctx, list) then
					self:_solveView(char, info, ctx)
					views[ctx] = true
				elseif views[ctx] then
					-- the client stopped posing it: it sees the replicated parts again
					views[ctx] = nil
					local per = proxy.overlays[ctx]
					if per then
						for _, d in char:GetDescendants() do
							local o = d:IsA("BasePart") and per[d]
							if o then
								o.CFrame = nil
							end
						end
					end
				end
			end
		end
	end
end

return Rigs
