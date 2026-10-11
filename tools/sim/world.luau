-- world.luau: geometry helpers (part movement, pivots, bounding boxes,
-- raycasts and overlap queries). No physics: parts only move when told to.

local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local World = {}
World.__index = World

local MOVE_KEYS = { "CFrame", "Position", "Orientation", "Rotation" }

function World.new(sim)
	local self = setmetatable({}, World)
	self.sim = sim
	self.raycastHandler = nil
	self.velocity = setmetatable({}, { __mode = "k" }) -- part -> { linear, angular }
	return self
end

local function orientationOf(cf)
	local rx, ry, rz = cf:ToOrientation()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end

local function rotationOf(cf)
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end

World.orientationOf = orientationOf
World.rotationOf = rotationOf

-- Moves a part, firing change events. Moving a character's HumanoidRootPart
-- moves the whole character rigidly (stand-in for the welded assembly).
function World:setPartCFrame(real, cf, noAssembly: boolean?)
	if typeof(cf) ~= "CFrame" then
		error("Unable to assign property CFrame. CFrame expected, got " .. typeof(cf), 0)
	end
	local sim = self.sim
	local proxy = sim.proxy
	local localCtx = sim:_clientLocal(real, "CFrame")
	if localCtx then
		-- a client moving a part it does not own only moves its local copy
		proxy:setLocal(localCtx, real, "CFrame", cf)
		local filter = function(c)
			return c == localCtx
		end
		for _, key in MOVE_KEYS do
			if key ~= "CFrame" and proxy:isWatched(real, key) then
				proxy:emitChanged(real, key, nil, filter)
			end
		end
		return
	end
	local old = real.CFrame
	real.CFrame = cf
	if proxy.signals[real] then
		for _, key in MOVE_KEYS do
			if proxy:isWatched(real, key) then
				local v = cf
				if key == "Position" then
					v = cf.Position
				elseif key == "Orientation" then
					v = orientationOf(cf)
				elseif key == "Rotation" then
					v = rotationOf(cf)
				end
				proxy:emitChanged(real, key, v)
			end
		end
	end
	if not noAssembly and real.Name == "HumanoidRootPart" then
		local model = real.Parent
		if model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
			local delta = cf * old:Inverse()
			for _, d in model:GetDescendants() do
				if d ~= real and d:IsA("BasePart") then
					self:setPartCFrame(d, delta * d.CFrame, true)
				end
			end
		end
	end
end

-- CFrame as seen by the running context (client-local moves included).
function World:partCFrame(real)
	return self.sim.proxy:get(real, "CFrame")
end

-- Returns a list of BaseParts at/under an instance.
function World:partsOf(real)
	local parts = {}
	if real:IsA("BasePart") then
		table.insert(parts, real)
	end
	for _, d in real:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- Box enclosing the given parts, aligned with `frame`'s rotation.
function World:boxOfParts(parts, frame)
	local rot = frame.Rotation
	local minV, maxV
	for _, part in parts do
		local cf, size = part.CFrame, part.Size
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local wp = cf * Vector3.new(hx * sx, hy * sy, hz * sz)
					local lp = rot:PointToObjectSpace(wp)
					if minV == nil then
						minV, maxV = lp, lp
					else
						minV = minV:Min(lp)
						maxV = maxV:Max(lp)
					end
				end
			end
		end
	end
	if minV == nil then
		return nil, nil
	end
	local centerLocal = (minV + maxV) / 2
	return CFrame.new(rot:PointToWorldSpace(centerLocal)) * rot, maxV - minV
end

function World:getPivot(real)
	if real:IsA("BasePart") then
		return real.CFrame * real.PivotOffset
	end
	if real:IsA("Model") then
		local pp = real.PrimaryPart
		if pp then
			return pp.CFrame * pp.PivotOffset
		end
		local ok, wp = pcall(function()
			return real.WorldPivotData
		end)
		if ok and wp ~= nil then
			return wp
		end
		-- Roblox initialises a model's pivot to its bounding-box centre.
		local center = self:boxOfParts(self:partsOf(real), CFrame.identity)
		local pivot = center or CFrame.identity
		pcall(function()
			real.WorldPivotData = pivot
		end)
		return pivot
	end
	return CFrame.identity
end

function World:pivotTo(real, target)
	if typeof(target) ~= "CFrame" then
		error("PivotTo: CFrame expected, got " .. typeof(target), 0)
	end
	if real:IsA("BasePart") then
		self:setPartCFrame(real, target * real.PivotOffset:Inverse())
		return
	end
	if real:IsA("Model") then
		local current = self:getPivot(real)
		local delta = target * current:Inverse()
		for _, d in real:GetDescendants() do
			if d:IsA("BasePart") then
				self:setPartCFrame(d, delta * d.CFrame, true)
			elseif d:IsA("Model") and d.PrimaryPart == nil then
				local ok, wp = pcall(function()
					return d.WorldPivotData
				end)
				if ok and wp ~= nil then
					d.WorldPivotData = delta * wp
				end
			end
		end
		if real.PrimaryPart == nil then
			real.WorldPivotData = target
		end
		return
	end
	error("PivotTo is not supported for " .. real.ClassName, 0)
end

function World:boundingBox(real)
	local pivot = self:getPivot(real)
	local cf, size = self:boxOfParts(self:partsOf(real), pivot)
	if cf == nil then
		return pivot, Vector3.zero
	end
	return cf, size
end

-- Parts considered by raycasts/overlaps (Terrain is handled separately).
function World.isQueryable(d): boolean
	return d:IsA("BasePart") and d.ClassName ~= "Terrain" and d.CanQuery ~= false
end

-- Filtering for RaycastParams / OverlapParams mocks.
local function makeFilter(sim, params)
	if params == nil then
		return function()
			return true
		end
	end
	local list = {}
	for _, v in params.FilterDescendantsInstances or {} do
		local r = sim.proxy:toReal(v)
		if r then
			table.insert(list, r)
		end
	end
	local include = params.FilterType == roblox.Enum.RaycastFilterType.Include
		or tostring(params.FilterType) == "Enum.RaycastFilterType.Whitelist"
	return function(part)
		local matched = false
		for _, f in list do
			if part == f or part:IsDescendantOf(f) then
				matched = true
				break
			end
		end
		if include then
			return matched
		end
		return not matched
	end
end

-- Ray vs oriented box; returns distance along unit ray and world normal.
local function rayBox(origin, dir, maxDist, cf, size)
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local h = { size.X / 2, size.Y / 2, size.Z / 2 }
	local oc = { o.X, o.Y, o.Z }
	local dc = { d.X, d.Y, d.Z }
	local tmin, tmax = -math.huge, math.huge
	local axis, sign = 0, 0
	for i = 1, 3 do
		if math.abs(dc[i]) < 1e-12 then
			if oc[i] < -h[i] or oc[i] > h[i] then
				return nil
			end
		else
			local t1 = (-h[i] - oc[i]) / dc[i]
			local t2 = (h[i] - oc[i]) / dc[i]
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin = t1
				axis = i
				sign = s
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmin < 0 or tmin > maxDist or axis == 0 then
		return nil
	end
	local n = { 0, 0, 0 }
	n[axis] = sign
	return tmin, cf:VectorToWorldSpace(Vector3.new(n[1], n[2], n[3]))
end

local function raySphere(origin, dir, maxDist, center, radius)
	local oc = origin - center
	local b = oc:Dot(dir)
	local c = oc:Dot(oc) - radius * radius
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local t = -b - math.sqrt(disc)
	if t < 0 or t > maxDist then
		return nil
	end
	local p = origin + dir * t
	return t, (p - center).Unit
end

-- Terrain volumes recorded from Fill* calls (Clear resets).
function World:terrainVolumes()
	local vols = {}
	for _, op in self.sim.TerrainOps do
		if op.op == "Clear" then
			vols = {}
		elseif op.op == "FillBlock" or op.op == "FillWedge" then
			table.insert(vols, { kind = "box", cframe = op.args[1], size = op.args[2], material = op.args[3] })
		elseif op.op == "FillBall" then
			table.insert(vols, { kind = "ball", center = op.args[1], radius = op.args[2], material = op.args[3] })
		elseif op.op == "FillCylinder" then
			local r = op.args[3]
			table.insert(vols, {
				kind = "box",
				cframe = op.args[1],
				size = Vector3.new(r * 2, op.args[2], r * 2),
				material = op.args[4],
			})
		elseif op.op == "FillRegion" then
			local region = op.args[1]
			table.insert(vols, { kind = "box", cframe = region.CFrame, size = region.Size, material = op.args[3] })
		end
	end
	return vols
end

-- Built-in raycaster: oriented boxes for parts, boxes/spheres for terrain fills.
function World:defaultRaycast(origin, direction, params)
	local sim = self.sim
	local maxDist = direction.Magnitude
	if maxDist <= 0 then
		return nil
	end
	local dir = direction / maxDist
	local filter = makeFilter(sim, params)
	local respectCollide = params ~= nil and params.RespectCanCollide == true
	local best
	for _, d in sim.workspaceReal:GetDescendants() do
		if World.isQueryable(d) and filter(d) and (not respectCollide or d.CanCollide) then
			local t, n = rayBox(origin, dir, maxDist, d.CFrame, d.Size)
			if t and (best == nil or t < best.t) then
				best = { t = t, normal = n, instance = d, material = d.Material }
			end
		end
	end
	local ignoreWater = params ~= nil and params.IgnoreWater == true
	local terrain = sim.workspaceReal:FindFirstChildOfClass("Terrain")
	if terrain and filter(terrain) then
		for _, v in self:terrainVolumes() do
			local mat = v.material
			if mat ~= roblox.Enum.Material.Air and not (ignoreWater and mat == roblox.Enum.Material.Water) then
				local t, n
				if v.kind == "ball" then
					t, n = raySphere(origin, dir, maxDist, v.center, v.radius)
				else
					t, n = rayBox(origin, dir, maxDist, v.cframe, v.size)
				end
				if t and (best == nil or t < best.t) then
					best = { t = t, normal = n, instance = terrain, material = mat }
				end
			end
		end
	end
	if best == nil then
		return nil
	end
	return sim.env.makeRaycastResult(sim, {
		Instance = sim.proxy:wrap(best.instance),
		Position = origin + dir * best.t,
		Normal = best.normal,
		Material = best.material,
		Distance = best.t,
	})
end

function World:raycast(origin, direction, params)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		error("Raycast: origin and direction must be Vector3", 0)
	end
	if self.raycastHandler then
		local default = function(o, d, p)
			return self:defaultRaycast(o or origin, d or direction, p or params)
		end
		return self.raycastHandler(origin, direction, params, default)
	end
	return self:defaultRaycast(origin, direction, params)
end

-- World-space AABB of an oriented box.
local function aabb(cf, s)
	local r = cf.Rotation
	local ex = Vector3.new(
		math.abs(r.XVector.X) * s.X / 2 + math.abs(r.YVector.X) * s.Y / 2 + math.abs(r.ZVector.X) * s.Z / 2,
		math.abs(r.XVector.Y) * s.X / 2 + math.abs(r.YVector.Y) * s.Y / 2 + math.abs(r.ZVector.Y) * s.Z / 2,
		math.abs(r.XVector.Z) * s.X / 2 + math.abs(r.YVector.Z) * s.Y / 2 + math.abs(r.ZVector.Z) * s.Z / 2
	)
	return cf.Position - ex, cf.Position + ex
end

local function overlapQuery(self, params, test)
	local sim = self.sim
	local filter = makeFilter(sim, params)
	local maxParts = params and params.MaxParts or 0
	local respectCollide = params ~= nil and params.RespectCanCollide == true
	local out = {}
	for _, d in sim.workspaceReal:GetDescendants() do
		if World.isQueryable(d) and filter(d) and (not respectCollide or d.CanCollide) then
			local lo, hi = aabb(d.CFrame, d.Size)
			if test(lo, hi, d) then
				table.insert(out, sim.proxy:wrap(d))
				if maxParts > 0 and #out >= maxParts then
					break
				end
			end
		end
	end
	return out
end

function World:partsInBox(cf, size, params)
	local qlo, qhi = aabb(cf, size)
	return overlapQuery(self, params, function(lo, hi)
		return lo.X <= qhi.X and hi.X >= qlo.X and lo.Y <= qhi.Y and hi.Y >= qlo.Y and lo.Z <= qhi.Z and hi.Z >= qlo.Z
	end)
end

function World:partsInRadius(pos, radius, params)
	return overlapQuery(self, params, function(lo, hi)
		local closest = pos:Max(lo):Min(hi)
		return (closest - pos).Magnitude <= radius
	end)
end

function World:partsInPart(part, params)
	local qlo, qhi = aabb(part.CFrame, part.Size)
	return overlapQuery(self, params, function(lo, hi, d)
		return d ~= part
			and lo.X <= qhi.X
			and hi.X >= qlo.X
			and lo.Y <= qhi.Y
			and hi.Y >= qlo.Y
			and lo.Z <= qhi.Z
			and hi.Z >= qlo.Z
	end)
end

return World
