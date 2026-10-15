--[[
	Movers — one post-pass over a finished model tree (Workspace.Map at the end of Map.luau,
	ServerStorage.BaseTemplate at the end of BaseTemplate.luau): everything the client moves for
	the ambient life (attributes Bob / Sway / Spin / Pulse / Drift, DESIGN.md "Ambient attributes")
	never collides and takes no raycasts or touches (v3 fix F2).

	Why: the client moves these parts locally every frame (Workspace:BulkMoveTo); an anchored part
	that collides or is queryable also updates the physics broadphase and the spatial-query tree on
	every move (the camera's occlusion rays and the fishing FX's ground rays see it), and the server
	and the other clients see it standing still — a child standing on a bobbing raft would jitter
	on it. So the floats you can stand on (the swim platform, the raft, the fish farms, the
	houseboats) carry no Bob at all (Coast.luau / Nature.luau): still and solid.

	Movers.quiet(root) -> number   -- CanCollide / CanQuery / CanTouch = false on every BasePart of
	                                  every mover (the mover itself and all its descendants; marks
	                                  nested inside a mover ride on the outer one, as in
	                                  AmbientWorld.Collect). Exception: the palms' trunks (parts
	                                  named Trunk<n> of a mover whose name contains "Palm", or a
	                                  "FarTree"): they sway only 1.2° about their foot and stay solid.
	                                  CastShadow is left as built (palm fronds are the deliberate
	                                  shadow blocks). Returns how many parts it changed.
	Movers.KINDS                   -- the attribute names that mark a mover
	Movers.isSolidTrunk(mover, part) -- the exception above
]]

local Movers = {}

Movers.KINDS = { "Bob", "Sway", "Spin", "Pulse", "Drift" }

local function moving(node: any): boolean
	for _, kind in Movers.KINDS do
		local value = node:GetAttribute(kind)
		if typeof(value) == "number" and value ~= 0 then
			return true
		end
	end
	return false
end

function Movers.isSolidTrunk(mover: any, part: any): boolean
	local palm = string.find(mover.Name, "Palm") ~= nil or mover.Name == "FarTree"
	return palm and string.match(part.Name, "^Trunk%d") ~= nil
end

function Movers.quiet(root: any): number
	local changed = 0
	local function visit(node: any)
		if moving(node) and (node:IsA("Model") or node:IsA("BasePart")) then
			local parts = if node:IsA("BasePart") then { node } else {}
			for _, d in node:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for _, p in parts do
				if not Movers.isSolidTrunk(node, p) and (p.CanCollide or p.CanQuery or p.CanTouch) then
					p.CanCollide = false
					p.CanQuery = false
					p.CanTouch = false
					changed += 1
				end
			end
			return -- (inner marks ride on the outer one)
		end
		for _, child in node:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return changed
end

return Movers
