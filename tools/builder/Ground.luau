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

-- Cap thickness (studs): a whole 4-stud terrace step is grass, so single steps need no dirt
-- body at all (fewer parts, brighter hills); taller drops show grass over dirt/stone.
local CAP = 4
local MAX_SPAN = 240 -- columns per rectangle side (part size limit 2048)

-- kind -> { cap = Color3?, body = Color3, name }
-- Grass: two close shades in broad noise patches (calm lawns, not a contour-map quilt) and a
-- light highlight on high ground.
local GRASS_A, GRASS_B, GRASS_HIGH = rgb(118, 218, 66), rgb(128, 226, 74), rgb(146, 234, 82)
local HIGH_GROUND = 40
-- Tall cliff bodies are split into horizontal strata (absolute y bands) of 2-3 shades.
local STRATUM = 8
local STRATA = {
	Dirt = { rgb(206, 148, 88), rgb(186, 128, 74) },
	Mountainside = { rgb(168, 174, 192), rgb(150, 156, 176) },
	Stone = { rgb(168, 174, 192), rgb(150, 156, 176) },
	Snow = { rgb(224, 236, 252), rgb(206, 220, 240) },
	Sandstone = { rgb(232, 178, 112), rgb(214, 150, 92), rgb(246, 206, 150) },
}
local DIRT = rgb(206, 148, 88)
local KIND_STYLE = {
	grass = { body = DIRT, name = "Grass", strata = "Dirt" }, -- cap shade by noise patch
	meadow = { cap = rgb(170, 240, 96), body = DIRT, name = "Meadow", strata = "Dirt" },
	path = { cap = rgb(240, 204, 138), body = DIRT, name = "Path", strata = "Dirt" },
	sand = { cap = rgb(255, 230, 156), body = rgb(240, 206, 132), name = "Sand" },
	shallow = { body = rgb(250, 226, 156), name = "Shallows" },
	seabed = { body = rgb(200, 226, 170), name = "Seabed" },
	deep = { body = rgb(112, 208, 198), name = "DeepSeabed" },
	stone = { cap = rgb(206, 210, 222), body = rgb(168, 174, 192), name = "Stone", strata = "Stone" },
	snow = { cap = rgb(250, 252, 255), body = rgb(224, 236, 252), name = "Snow", strata = "Snow" },
	grassRock = { body = rgb(168, 174, 192), name = "Mountainside", strata = "Mountainside" }, -- grass cap
	mesa = { body = rgb(222, 170, 116), name = "Sandstone", strata = "Sandstone" }, -- grass cap, warm cliff
}

-- Sea floor colour by depth: bright sand in the shallows, turquoise lagoon, deep-blue ocean.
local SEABED_BY_TOP = {
	[-2] = rgb(250, 226, 156),
	[-4] = rgb(236, 224, 162),
	[-6] = rgb(200, 226, 170),
	[-8] = rgb(160, 214, 190),
	[-14] = rgb(112, 208, 198),
	[-16] = rgb(96, 184, 190),
	[-24] = rgb(36, 118, 168),
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
				if kind == "grass" or kind == "grassRock" or kind == "mesa" then
					capColor = if top > HIGH_GROUND
						then GRASS_HIGH
						elseif world:noise(cx / 192 + 3.7, cz / 192 - 1.3) > 0 then GRASS_A
						else GRASS_B
				end
				local bodyColor = style.body
				if underwater then
					bodyColor = SEABED_BY_TOP[top] or style.body
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
				-- a body only where the drop is deeper than the cap (or for the single-part sea floor)
				if bodyTop > bodyBottom and (not capColor or low < top - CAP) then
					local strata = not underwater and style.strata and STRATA[style.strata]
					local visibleBottom = math.max(bodyBottom, waterTop - 2) -- strata only above the water
					if strata and bodyTop - visibleBottom > 2 * STRATUM then
						-- horizontal bands on absolute y, so neighbouring cliffs line up
						if visibleBottom > bodyBottom then
							U.part(
								folder,
								style.name .. "Side",
								Vector3.new(w, visibleBottom - bodyBottom, d),
								CFrame.new(cx, (visibleBottom + bodyBottom) / 2, cz),
								bodyColor,
								Enum.Material.SmoothPlastic,
								extra
							)
							parts += 1
						end
						local y1 = bodyTop
						while y1 > visibleBottom do
							local band = math.floor((y1 - 0.01) / STRATUM)
							local y0 = math.max(visibleBottom, band * STRATUM)
							U.part(
								folder,
								style.name .. "Side",
								Vector3.new(w, y1 - y0, d),
								CFrame.new(cx, (y1 + y0) / 2, cz),
								strata[band % #strata + 1],
								Enum.Material.SmoothPlastic,
								extra
							)
							parts += 1
							y1 = y0
						end
					else
						U.part(
							folder,
							style.name .. (if capColor then "Side" else ""),
							Vector3.new(w, bodyTop - bodyBottom, d),
							CFrame.new(cx, (bodyTop + bodyBottom) / 2, cz),
							bodyColor,
							Enum.Material.SmoothPlastic,
							extra
						)
						parts += 1
					end
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
