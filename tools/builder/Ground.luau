--[[
	Ground — turns the VoxelWorld heightfield into parts (Workspace.Map.Ground).

	Greedy meshing: neighbouring columns with the same top and kind merge into one rectangle.
	Every land rectangle becomes two parts — a thin coloured cap (grass/sand/snow …) and a body
	(dirt/stone) that reaches down to the lowest neighbouring column, so every visible side is
	covered and the terraces show the classic voxel "grass on dirt" stripes. Underwater
	rectangles are a single part. All parts are Locked (nobody drags the ground in Studio by
	accident) and anchored; underwater ones cast no shadow.
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb

local CAP = 1 -- cap thickness (studs)
local MAX_SPAN = 240 -- columns per rectangle side (part size limit 2048)

-- kind -> { cap = Color3?, body = Color3, name }
local GRASS_SHADES = { rgb(104, 214, 72), rgb(88, 198, 62), rgb(124, 226, 86) }
local DIRT = rgb(170, 116, 70)
local KIND_STYLE = {
	grass = { body = DIRT, name = "Grass" }, -- cap shade by terrace level
	meadow = { cap = rgb(156, 236, 92), body = DIRT, name = "Meadow" },
	path = { cap = rgb(238, 200, 132), body = DIRT, name = "Path" },
	sand = { cap = rgb(255, 228, 152), body = rgb(236, 200, 124), name = "Sand" },
	shallow = { body = rgb(248, 222, 150), name = "Shallows" },
	seabed = { body = rgb(222, 200, 136), name = "Seabed" },
	deep = { body = rgb(120, 168, 168), name = "DeepSeabed" },
	stone = { cap = rgb(196, 202, 212), body = rgb(150, 158, 172), name = "Stone" },
	snow = { cap = rgb(248, 252, 255), body = rgb(196, 202, 212), name = "Snow" },
	grassRock = { body = rgb(150, 158, 172), name = "Mountainside" }, -- grass cap, stone body
}

return function(parent: any, world: any): { parts: number, rects: number }
	local model = U.model(parent, "Ground")
	local folders = {
		land = U.folder(model, "Land"),
		water = U.folder(model, "Underwater"),
	}
	local n, size, cell = world.n, world.size, world.cell
	local Kinds = world.Kinds
	local waterTop = world.cfg.WaterTop
	local deepest = -world.cfg.OceanDepth - 4

	-- Merge keys per column: top * 16 + kind (tops are even integers, kinds < 16).
	local count = size * size
	local keys = table.create(count, 0)
	for i = 0, count - 1 do
		keys[i + 1] = buffer.readi16(world.top, i * 2) * 16 + buffer.readu8(world.kind, i)
	end
	local used = buffer.create(count)

	local function key(ix: number, iz: number): number
		return keys[(iz + n) * size + (ix + n) + 1]
	end
	local function topOf(ix: number, iz: number): number
		if ix < -n or ix >= n or iz < -n or iz >= n then
			return deepest
		end
		return world:topAtCell(ix, iz)
	end

	local parts, rects = 0, 0
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local idx = (iz + n) * size + (ix + n)
			if buffer.readu8(used, idx) == 0 then
				local k = keys[idx + 1]
				-- grow along +X
				local x1 = ix
				while
					x1 + 1 < n
					and x1 + 1 - ix < MAX_SPAN
					and key(x1 + 1, iz) == k
					and buffer.readu8(used, idx + (x1 + 1 - ix)) == 0
				do
					x1 += 1
				end
				-- grow along +Z while the whole row matches
				local z1 = iz
				while z1 + 1 < n and z1 + 1 - iz < MAX_SPAN do
					local row = (z1 + 1 + n) * size + n
					local ok = true
					for x = ix, x1 do
						if keys[row + x + 1] ~= k or buffer.readu8(used, row + x) ~= 0 then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					z1 += 1
				end
				for z = iz, z1 do
					local row = (z + n) * size + n
					for x = ix, x1 do
						buffer.writeu8(used, row + x, 1)
					end
				end

				local top = world:topAtCell(ix, iz)
				local kind = Kinds[k % 16]
				-- lowest neighbour around the rectangle: the body must reach down to it
				local low = top
				for x = ix, x1 do
					low = math.min(low, topOf(x, iz - 1), topOf(x, z1 + 1))
				end
				for z = iz, z1 do
					low = math.min(low, topOf(ix - 1, z), topOf(x1 + 1, z))
				end

				local style = KIND_STYLE[kind]
				local x0s, x1s = ix * cell, (x1 + 1) * cell
				local z0s, z1s = iz * cell, (z1 + 1) * cell
				local cx, cz = (x0s + x1s) / 2, (z0s + z1s) / 2
				local w, d = x1s - x0s, z1s - z0s
				local underwater = top < waterTop
				local folder = if underwater then folders.water else folders.land
				local capColor = style.cap
				if kind == "grass" or kind == "grassRock" then
					capColor = GRASS_SHADES[(top // 4) % 3 + 1]
				end
				local bodyTop = if capColor then top - CAP else top
				local bodyBottom = low - 0.5
				if bodyTop - bodyBottom < 1 then
					bodyBottom = bodyTop - 1
				end
				local extra = {
					Locked = true,
					CastShadow = not underwater,
				}
				if bodyTop > bodyBottom and (not capColor or low < top) then
					U.part(
						folder,
						style.name .. (if capColor then "Side" else ""),
						Vector3.new(w, bodyTop - bodyBottom, d),
						CFrame.new(cx, (bodyTop + bodyBottom) / 2, cz),
						style.body,
						Enum.Material.SmoothPlastic,
						extra
					)
					parts += 1
				end
				if capColor then
					U.part(
						folder,
						style.name,
						Vector3.new(w, CAP, d),
						CFrame.new(cx, top - CAP / 2, cz),
						capColor,
						Enum.Material.SmoothPlastic,
						extra
					)
					parts += 1
				end
				rects += 1
			end
		end
	end
	return { model = model, parts = parts, rects = rects }
end
