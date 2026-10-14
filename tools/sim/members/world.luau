-- members/world.luau: parts, models, humanoids, attachments, workspace,
-- terrain, camera, tools, sounds and animation stubs.

local roblox = require("@lune/roblox")
local World = require("../world")
local SmoothGrid = require("../../terrain/SmoothGrid")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(M)
	local function noop()
		return nil
	end

	local function expect(v, t: string, what: string)
		if typeof(v) ~= t then
			error(string.format("%s: %s expected, got %s", what, t, typeof(v)), 0)
		end
	end

	local function velocityState(sim, real)
		local v = sim.world.velocity[real]
		if v == nil then
			v = { linear = Vector3.zero, angular = Vector3.zero }
			sim.world.velocity[real] = v
		end
		return v
	end

	local function linearVel()
		return M.prop(function(sim, real)
			return velocityState(sim, real).linear
		end, function(sim, real, v)
			expect(v, "Vector3", "Velocity")
			velocityState(sim, real).linear = v
		end)
	end

	local function angularVel()
		return M.prop(function(sim, real)
			return velocityState(sim, real).angular
		end, function(sim, real, v)
			expect(v, "Vector3", "AngularVelocity")
			velocityState(sim, real).angular = v
		end)
	end

	local function mass(_, real)
		local s = real.Size
		return s.X * s.Y * s.Z * 0.7
	end

	M.define("PVInstance", {
		GetPivot = M.method(function(sim, real)
			return sim.world:getPivot(real)
		end),
		PivotTo = M.method(function(sim, real, cf)
			sim.world:pivotTo(real, cf)
		end),
	})

	M.define("BasePart", {
		CFrame = M.prop(function(sim, real)
			return sim.world:partCFrame(real)
		end, function(sim, real, v)
			sim.world:setPartCFrame(real, v)
		end),
		Position = M.prop(function(sim, real)
			return sim.world:partCFrame(real).Position
		end, function(sim, real, v)
			expect(v, "Vector3", "Position")
			sim.world:setPartCFrame(real, CFrame.new(v) * sim.world:partCFrame(real).Rotation)
		end),
		Orientation = M.prop(function(sim, real)
			return World.orientationOf(sim.world:partCFrame(real))
		end, function(sim, real, v)
			expect(v, "Vector3", "Orientation")
			local cf = CFrame.new(sim.world:partCFrame(real).Position)
				* CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			sim.world:setPartCFrame(real, cf)
		end),
		Rotation = M.prop(function(sim, real)
			return World.rotationOf(sim.world:partCFrame(real))
		end, function(sim, real, v)
			expect(v, "Vector3", "Rotation")
			local cf = CFrame.new(sim.world:partCFrame(real).Position)
				* CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			sim.world:setPartCFrame(real, cf)
		end),
		BrickColor = M.prop(function(sim, real)
			return roblox.BrickColor.new(sim.proxy:get(real, "Color"))
		end, function(sim, real, v)
			expect(v, "BrickColor", "BrickColor")
			sim.proxy:setProperty(real, "Color", v.Color)
			sim.proxy:emitChanged(real, "BrickColor", v)
		end),
		Mass = M.prop(mass),
		AssemblyMass = M.prop(mass),
		AssemblyLinearVelocity = linearVel(),
		Velocity = linearVel(),
		AssemblyAngularVelocity = angularVel(),
		RotVelocity = angularVel(),
		AssemblyRootPart = M.prop(function(sim, real)
			return sim.proxy:wrap(real)
		end),
		AssemblyCenterOfMass = M.prop(function(_, real)
			return real.CFrame.Position
		end),
		CenterOfMass = M.prop(function(_, real)
			return real.CFrame.Position
		end),
		ReceiveAge = M.prop(function()
			return 0
		end),

		GetMass = M.method(mass),
		GetTouchingParts = M.method(function()
			return {}
		end),
		GetConnectedParts = M.method(function(sim, real)
			return { sim.proxy:wrap(real) }
		end),
		GetRootPart = M.method(function(sim, real)
			return sim.proxy:wrap(real)
		end),
		GetJoints = M.method(function()
			return {}
		end),
		GetNoCollisionConstraints = M.method(function()
			return {}
		end),
		ApplyImpulse = M.method(noop),
		ApplyAngularImpulse = M.method(noop),
		ApplyImpulseAtPosition = M.method(noop),
		SetNetworkOwner = M.method(noop),
		GetNetworkOwner = M.method(noop),
		SetNetworkOwnershipAuto = M.method(noop),
		GetNetworkOwnershipAuto = M.method(function()
			return true
		end),
		CanSetNetworkOwnership = M.method(function()
			return true, nil
		end),
		BreakJoints = M.method(noop),
		MakeJoints = M.method(noop),
		Resize = M.method(function()
			return true
		end),
		GetVelocityAtPosition = M.method(function(sim, real)
			return velocityState(sim, real).linear
		end),
		CanCollideWith = M.method(function()
			return true
		end),
		Touched = M.signal(),
		TouchEnded = M.signal(),
	})

	M.define("Model", {
		WorldPivot = M.prop(function(sim, real)
			return sim.world:getPivot(real)
		end, function(_sim, real, v)
			expect(v, "CFrame", "WorldPivot")
			local pp = real.PrimaryPart
			if pp then
				pp.PivotOffset = pp.CFrame:Inverse() * v
			else
				real.WorldPivotData = v
			end
		end),
		GetBoundingBox = M.method(function(sim, real)
			return sim.world:boundingBox(real)
		end),
		GetExtentsSize = M.method(function(sim, real)
			local _, size = sim.world:boundingBox(real)
			return size
		end),
		GetModelCFrame = M.method(function(sim, real)
			return (sim.world:boundingBox(real))
		end),
		GetModelSize = M.method(function(sim, real)
			local _, size = sim.world:boundingBox(real)
			return size
		end),
		MoveTo = M.method(function(sim, real, pos)
			expect(pos, "Vector3", "MoveTo")
			local pivot = sim.world:getPivot(real)
			sim.world:pivotTo(real, CFrame.new(pos) * pivot.Rotation)
		end),
		TranslateBy = M.method(function(sim, real, delta)
			expect(delta, "Vector3", "TranslateBy")
			sim.world:pivotTo(real, sim.world:getPivot(real) + delta)
		end),
		SetPrimaryPartCFrame = M.method(function(sim, real, cf)
			local pp = real.PrimaryPart
			if pp == nil then
				error(
					"Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.",
					0
				)
			end
			expect(cf, "CFrame", "SetPrimaryPartCFrame")
			sim.world:pivotTo(real, cf * pp.PivotOffset)
		end),
		GetPrimaryPartCFrame = M.method(function(_, real)
			local pp = real.PrimaryPart
			if pp == nil then
				error(
					"Model:GetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.",
					0
				)
			end
			return pp.CFrame
		end),
		GetScale = M.method(function(_, real)
			return real.Scale
		end),
		ScaleTo = M.method(function(sim, real, scale)
			if type(scale) ~= "number" or scale <= 0 then
				error("ScaleTo: scale must be a positive number", 0)
			end
			local factor = scale / real.Scale
			local pivot = sim.world:getPivot(real)
			for _, part in sim.world:partsOf(real) do
				local rel = pivot:ToObjectSpace(part.CFrame)
				part.Size = part.Size * factor
				sim.world:setPartCFrame(part, pivot * (rel.Rotation + rel.Position * factor), true)
			end
			real.Scale = scale
		end),
		BreakJoints = M.method(noop),
		MakeJoints = M.method(noop),
		AddPersistentPlayer = M.method(noop),
		RemovePersistentPlayer = M.method(noop),
		GetPersistentPlayers = M.method(function()
			return {}
		end),
	})

	M.define("Humanoid", {
		Health = M.prop(function(sim, real)
			return sim.players:getHealth(real)
		end, function(sim, real, v)
			sim.players:setHealth(real, v)
		end),
		MaxHealth = M.prop(function(_, real)
			return real.MaxHealth
		end, function(sim, real, v)
			if type(v) ~= "number" then
				error("MaxHealth: number expected", 0)
			end
			sim.proxy:setProperty(real, "MaxHealth", v)
			if sim.players:getHealth(real) > v then
				sim.players:setHealth(real, v)
			end
		end),
		TakeDamage = M.method(function(sim, real, amount)
			if type(amount) ~= "number" then
				error("TakeDamage: number expected", 0)
			end
			local char = real.Parent
			if char and char:FindFirstChildOfClass("ForceField") then
				return
			end
			sim.players:setHealth(real, sim.players:getHealth(real) - amount)
		end),
		MoveTo = M.method(function(sim, real, pos, part)
			sim.players:humanoidMoveTo(real, pos, part)
		end),
		Move = M.method(noop),
		GetState = M.method(function(sim, real)
			return sim.players:getState(real)
		end),
		ChangeState = M.method(function(sim, real, state)
			sim.players:changeState(real, state)
		end),
		SetStateEnabled = M.method(noop),
		GetStateEnabled = M.method(function()
			return true
		end),
		LoadAnimation = M.method(function(sim, real, anim)
			return sim.misc:loadAnimation(real, anim)
		end),
		EquipTool = M.method(function(sim, real, tool)
			sim.players:equipTool(real, sim.proxy:toReal(tool))
		end),
		UnequipTools = M.method(function(sim, real)
			sim.players:unequipTools(real)
		end),
		GetAccessories = M.method(function(sim, real)
			local out = {}
			local char = real.Parent
			if char then
				for _, c in char:GetChildren() do
					if c:IsA("Accessory") then
						table.insert(out, sim.proxy:wrap(c))
					end
				end
			end
			return out
		end),
		AddAccessory = M.method(function(sim, real, acc)
			local r = sim.proxy:toReal(acc)
			if r and real.Parent then
				sim.proxy:setParent(r, real.Parent)
			end
		end),
		RemoveAccessories = M.method(noop),
		ApplyDescription = M.method(noop),
		ApplyDescriptionReset = M.method(noop),
		BuildRigFromAttachments = M.method(noop),
		RootPart = M.prop(function(sim, real)
			local char = real.Parent
			return char and sim.proxy:wrap(char:FindFirstChild("HumanoidRootPart")) or nil
		end),
		MoveDirection = M.prop(function()
			return Vector3.zero
		end),
		FloorMaterial = M.prop(function()
			return roblox.Enum.Material.Plastic
		end),
		SeatPart = M.prop(function()
			return nil
		end),
		Died = M.signal(),
		HealthChanged = M.signal(),
		StateChanged = M.signal(),
		Running = M.signal(),
		Jumping = M.signal(),
		FreeFalling = M.signal(),
		Climbing = M.signal(),
		Seated = M.signal(),
		MoveToFinished = M.signal(),
		Touched = M.signal(),
		AnimationPlayed = M.signal(),
		StateEnabledChanged = M.signal(),
	})

	local animatorDefs = {
		LoadAnimation = M.method(function(sim, real, anim)
			return sim.misc:loadAnimation(real, anim)
		end),
		GetPlayingAnimationTracks = M.method(function(sim, real)
			return sim.misc:playingTracks(real)
		end),
		AnimationPlayed = M.signal(),
		StepAnimations = M.method(noop),
		ApplyJointVelocities = M.method(noop),
	}
	M.define("Animator", animatorDefs)
	M.define("AnimationController", animatorDefs)

	M.define("AnimationTrack", {
		Play = M.method(function(sim, real, _fade, _weight, speed)
			sim.misc:playTrack(real, speed)
		end),
		Stop = M.method(function(sim, real)
			sim.misc:stopTrack(real)
		end),
		AdjustSpeed = M.method(function(sim, real, speed)
			sim.misc:trackState(real).speed = speed or 1
		end),
		AdjustWeight = M.method(noop),
		GetMarkerReachedSignal = M.method(function(sim, real, name)
			return sim.proxy:getSignal(real, "marker:" .. tostring(name)):facade()
		end),
		GetTimeOfKeyframe = M.method(function()
			return 0
		end),
		IsPlaying = M.prop(function(sim, real)
			return sim.misc:trackState(real).playing
		end),
		Length = M.prop(function(sim, real)
			return sim.misc:trackState(real).length
		end),
		Speed = M.prop(function(sim, real)
			return sim.misc:trackState(real).speed
		end),
		TimePosition = M.prop(function(sim, real)
			local st = sim.misc:trackState(real)
			if st.playing then
				return math.min((sim.sched.clock - st.started) * st.speed, st.length)
			end
			return 0
		end, noop),
		WeightCurrent = M.prop(function()
			return 1
		end),
		WeightTarget = M.prop(function()
			return 1
		end),
		Stopped = M.signal(),
		Ended = M.signal(),
		DidLoop = M.signal(),
		KeyframeReached = M.signal(),
	})

	local function attachmentParentCF(real)
		local parent = real.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame
		end
		return CFrame.identity
	end

	M.define("Attachment", {
		Position = M.prop(function(_, real)
			return real.CFrame.Position
		end, function(sim, real, v)
			expect(v, "Vector3", "Position")
			sim.proxy:setProperty(real, "CFrame", CFrame.new(v) * real.CFrame.Rotation)
		end),
		Orientation = M.prop(function(_, real)
			return World.orientationOf(real.CFrame)
		end, function(sim, real, v)
			expect(v, "Vector3", "Orientation")
			local cf = CFrame.new(real.CFrame.Position)
				* CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			sim.proxy:setProperty(real, "CFrame", cf)
		end),
		WorldCFrame = M.prop(function(_, real)
			return attachmentParentCF(real) * real.CFrame
		end, function(sim, real, v)
			expect(v, "CFrame", "WorldCFrame")
			sim.proxy:setProperty(real, "CFrame", attachmentParentCF(real):Inverse() * v)
		end),
		WorldPosition = M.prop(function(_, real)
			return (attachmentParentCF(real) * real.CFrame).Position
		end, function(sim, real, v)
			expect(v, "Vector3", "WorldPosition")
			local world = CFrame.new(v) * (attachmentParentCF(real) * real.CFrame).Rotation
			sim.proxy:setProperty(real, "CFrame", attachmentParentCF(real):Inverse() * world)
		end),
		WorldOrientation = M.prop(function(_, real)
			return World.orientationOf(attachmentParentCF(real) * real.CFrame)
		end),
		WorldAxis = M.prop(function(_, real)
			return (attachmentParentCF(real) * real.CFrame).XVector
		end),
		WorldSecondaryAxis = M.prop(function(_, real)
			return (attachmentParentCF(real) * real.CFrame).YVector
		end),
		Axis = M.prop(function(_, real)
			return real.CFrame.XVector
		end),
		SecondaryAxis = M.prop(function(_, real)
			return real.CFrame.YVector
		end),
	})

	local function rayArgs(ray)
		expect(ray, "Ray", "FindPartOnRay")
		return ray.Origin, ray.Direction
	end

	local function findPartOnRay(sim, ray, list, filterType)
		local origin, dir = rayArgs(ray)
		local params = sim.env.newRaycastParams(sim)
		params.FilterType = filterType
		params.FilterDescendantsInstances = list
		local r = sim.world:raycast(origin, dir, params)
		if r == nil then
			return nil, origin + dir, Vector3.zero, roblox.Enum.Material.Air
		end
		return r.Instance, r.Position, r.Normal, r.Material
	end

	M.define("WorldRoot", {
		Raycast = M.method(function(sim, _, origin, direction, params)
			return sim.world:raycast(origin, direction, params)
		end),
		Spherecast = M.method(function(sim, _, origin, _radius, direction, params)
			return sim.world:raycast(origin, direction, params)
		end),
		Blockcast = M.method(function(sim, _, cf, _size, direction, params)
			return sim.world:raycast(cf.Position, direction, params)
		end),
		Shapecast = M.method(function(sim, _, part, direction, params)
			return sim.world:raycast(sim.proxy:toReal(part).CFrame.Position, direction, params)
		end),
		FindPartOnRay = M.method(function(sim, _, ray, ignore)
			return findPartOnRay(sim, ray, ignore and { ignore } or {}, roblox.Enum.RaycastFilterType.Exclude)
		end),
		FindPartOnRayWithIgnoreList = M.method(function(sim, _, ray, list)
			return findPartOnRay(sim, ray, list or {}, roblox.Enum.RaycastFilterType.Exclude)
		end),
		FindPartOnRayWithWhitelist = M.method(function(sim, _, ray, list)
			return findPartOnRay(sim, ray, list or {}, roblox.Enum.RaycastFilterType.Include)
		end),
		GetPartBoundsInBox = M.method(function(sim, _, cf, size, params)
			expect(cf, "CFrame", "GetPartBoundsInBox")
			expect(size, "Vector3", "GetPartBoundsInBox")
			return sim.world:partsInBox(cf, size, params)
		end),
		GetPartBoundsInRadius = M.method(function(sim, _, pos, radius, params)
			expect(pos, "Vector3", "GetPartBoundsInRadius")
			return sim.world:partsInRadius(pos, radius, params)
		end),
		GetPartsInPart = M.method(function(sim, _, part, params)
			return sim.world:partsInPart(sim.proxy:toReal(part), params)
		end),
		FindPartsInRegion3 = M.method(function(sim, _, region, ignore, maxParts)
			local params = sim.env.newOverlapParams(sim)
			params.FilterDescendantsInstances = ignore and { ignore } or {}
			params.MaxParts = maxParts or 20
			return sim.world:partsInBox(region.CFrame, region.Size, params)
		end),
		FindPartsInRegion3WithIgnoreList = M.method(function(sim, _, region, list, maxParts)
			local params = sim.env.newOverlapParams(sim)
			params.FilterDescendantsInstances = list or {}
			params.MaxParts = maxParts or 20
			return sim.world:partsInBox(region.CFrame, region.Size, params)
		end),
		BulkMoveTo = M.method(function(sim, _, parts, cframes)
			for i, p in parts do
				sim.world:setPartCFrame(sim.proxy:toReal(p), cframes[i])
			end
		end),
		ArePartsTouchingOthers = M.method(function()
			return false
		end),
	})

	M.define("Workspace", {
		GetServerTimeNow = M.method(function(sim)
			return sim:_serverTime()
		end),
		DistributedGameTime = M.prop(function(sim)
			return sim.sched.clock
		end),
		GetRealPhysicsFPS = M.method(function()
			return 60
		end),
		GetNumAwakeParts = M.method(function()
			return 0
		end),
		PGSIsEnabled = M.method(function()
			return true
		end),
		JoinToOutsiders = M.method(noop),
		UnjoinFromOutsiders = M.method(noop),
	})

	local function terrainOp(name)
		return M.method(function(sim, _, ...)
			table.insert(sim.TerrainOps, { op = name, args = table.pack(...), time = sim.sched.clock })
		end)
	end

	M.define("Terrain", {
		FillBlock = terrainOp("FillBlock"),
		FillBall = terrainOp("FillBall"),
		FillCylinder = terrainOp("FillCylinder"),
		FillWedge = terrainOp("FillWedge"),
		FillRegion = terrainOp("FillRegion"),
		Clear = terrainOp("Clear"),
		ReplaceMaterial = terrainOp("ReplaceMaterial"),
		WriteVoxels = terrainOp("WriteVoxels"),
		PasteRegion = terrainOp("PasteRegion"),
		-- Answers from the terrain baked into the place (Terrain.SmoothGrid), decoded once.
		-- Terrain written at runtime (Fill*/WriteVoxels) is only recorded, not readable here.
		ReadVoxels = M.method(function(sim, real, region, resolution)
			assert(resolution == 4, "RbxSim: ReadVoxels supports resolution 4 only")
			if sim._terrainGrid == nil then
				local ok, bytes = pcall(function()
					return real.SmoothGrid
				end)
				sim._terrainGrid = if ok
						and type(bytes) == "string"
						and #bytes > 2
					then SmoothGrid.decode(bytes)
					else false
			end
			local grid = sim._terrainGrid
			local centre, size = region.CFrame.Position, region.Size
			local x0 = math.floor((centre.X - size.X / 2) / 4 + 0.5)
			local y0 = math.floor((centre.Y - size.Y / 2) / 4 + 0.5)
			local z0 = math.floor((centre.Z - size.Z / 2) / 4 + 0.5)
			local nx, ny, nz = math.round(size.X / 4), math.round(size.Y / 4), math.round(size.Z / 4)
			local materials, occupancies = {}, {}
			for ix = 1, nx do
				local mx, ox = {}, {}
				for iy = 1, ny do
					local mz, oz = {}, {}
					for iz = 1, nz do
						local slot, occupancy = 0, 0
						if grid then
							slot, occupancy = grid:get(x0 + ix - 1, y0 + iy - 1, z0 + iz - 1)
						end
						mz[iz] = roblox.Enum.Material[SmoothGrid.SlotNames[slot]]
						oz[iz] = if slot == 0 then 0 else (occupancy + 1) / 256
					end
					mx[iy], ox[iy] = mz, oz
				end
				materials[ix], occupancies[ix] = mx, ox
			end
			return materials, occupancies
		end),
		CopyRegion = M.method(noop),
		WorldToCell = M.method(function(_, _, pos)
			return Vector3.new(math.floor(pos.X / 4), math.floor(pos.Y / 4), math.floor(pos.Z / 4))
		end),
		WorldToCellPreferSolid = M.method(function(_, _, pos)
			return Vector3.new(math.floor(pos.X / 4), math.floor(pos.Y / 4), math.floor(pos.Z / 4))
		end),
		CellCenterToWorld = M.method(function(_, _, x, y, z)
			return Vector3.new(x * 4 + 2, y * 4 + 2, z * 4 + 2)
		end),
		GetMaterialColor = M.method(function()
			return roblox.Color3.new(0.5, 0.5, 0.5)
		end),
		SetMaterialColor = M.method(noop),
	})

	local FOV = math.rad(70)

	-- "Screen" points (WorldToScreenPoint / ScreenPointToRay) are in the same space as the
	-- sim's AbsolutePosition. Roblox reports both below the GUI inset; RbxSim lays every GUI out
	-- in viewport px (inset ScreenGuis start at y = 58), so here screen = viewport (`inset` is
	-- kept for the call sites, but subtracts nothing) — Camera:WorldToScreenPoint(p) -
	-- gui.AbsolutePosition is the same as in Roblox.
	local SCREEN_INSET = 0

	local function project(sim, real, pos, inset)
		local vp = sim:_viewportFor(sim.sched:context())
		local lp = real.CFrame:PointToObjectSpace(pos)
		local depth = -lp.Z
		local f = (vp.Y / 2) / math.tan(FOV / 2)
		if depth <= 0 then
			return Vector3.new(vp.X / 2, vp.Y / 2, depth), false
		end
		local x = vp.X / 2 + lp.X / depth * f
		local y = vp.Y / 2 - lp.Y / depth * f - (inset and SCREEN_INSET or 0)
		local on = x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
		return Vector3.new(x, y, depth), on
	end

	local function pointRay(sim, real, x, y, depth, inset)
		local vp = sim:_viewportFor(sim.sched:context())
		local f = (vp.Y / 2) / math.tan(FOV / 2)
		local yy = y + (inset and SCREEN_INSET or 0)
		local dirLocal = Vector3.new((x - vp.X / 2) / f, -(yy - vp.Y / 2) / f, -1).Unit
		local cf = real.CFrame
		return roblox.Ray.new(cf.Position, cf:VectorToWorldSpace(dirLocal) * (depth or 1))
	end

	M.define("Camera", {
		ViewportSize = M.prop(function(sim)
			return sim:_viewportFor(sim.sched:context())
		end),
		WorldToViewportPoint = M.method(function(sim, real, pos)
			return project(sim, real, pos, false)
		end),
		WorldToScreenPoint = M.method(function(sim, real, pos)
			return project(sim, real, pos, true)
		end),
		ViewportPointToRay = M.method(function(sim, real, x, y, depth)
			return pointRay(sim, real, x, y, depth, false)
		end),
		ScreenPointToRay = M.method(function(sim, real, x, y, depth)
			return pointRay(sim, real, x, y, depth, true)
		end),
		GetPartsObscuringTarget = M.method(function()
			return {}
		end),
		Interpolate = M.method(noop),
		GetRenderCFrame = M.method(function(_, real)
			return real.CFrame
		end),
		ZoomToExtents = M.method(noop),
		InterpolationFinished = M.signal(),
	})

	M.define("Tool", {
		Activated = M.signal(),
		Deactivated = M.signal(),
		Equipped = M.signal(),
		Unequipped = M.signal(),
		Activate = M.method(function(sim, real)
			sim.players:activateTool(real)
		end),
		Deactivate = M.method(function(sim, real)
			sim.players:deactivateTool(real)
		end),
	})

	M.define("Sound", {
		Play = M.method(function(sim, real)
			sim.misc:playSound(real)
		end),
		Stop = M.method(function(sim, real)
			sim.misc:stopSound(real, "Stopped")
		end),
		Pause = M.method(function(sim, real)
			sim.misc:stopSound(real, "Paused")
		end),
		Resume = M.method(function(sim, real)
			sim.misc:playSound(real, true)
		end),
		IsPlaying = M.prop(function(sim, real)
			return sim.misc:soundState(real).playing
		end),
		IsPaused = M.prop(function(sim, real)
			return sim.misc:soundState(real).paused
		end),
		IsLoaded = M.prop(function()
			return true
		end),
		TimeLength = M.prop(function(_, real)
			local v = real:GetAttribute("SimTimeLength")
			return type(v) == "number" and v or 1
		end),
		Ended = M.signal(),
		Played = M.signal(),
		Paused = M.signal(),
		Resumed = M.signal(),
		Stopped = M.signal(),
		Loaded = M.signal(),
		DidLoop = M.signal(),
	})

	M.define("SoundService", {
		PlayLocalSound = M.method(noop),
		SetListener = M.method(noop),
		GetListener = M.method(function()
			return roblox.Enum.ListenerType.Camera, nil
		end),
	})
end
