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
-- Grass (Palette.luau GrassTop*): close shades in broad noise patches (calm lawns, not a contour-map quilt) and a
-- light highlight on high ground.
local GRASS_LIME, GRASS_FOREST, GRASS_MEADOW = rgb(110, 178, 70), rgb(96, 164, 62), rgb(128, 188, 82)
local GRASS_HIGH = rgb(102, 170, 66) -- slightly deeper on high ground
local HIGH_GROUND = 40
local FAR = 780 -- beyond the boundary: one tint (bigger merged rectangles)
-- Tall cliff bodies are split into horizontal strata (absolute y bands) of 2-3 shades.
local STRATUM = 12
local STRATA = {
	Dirt = { rgb(166, 118, 78), rgb(148, 104, 70) },
	-- warm grey stone in two bands
	Mountainside = { rgb(150, 146, 142), rgb(132, 128, 126) },
	Stone = { rgb(150, 146, 142), rgb(132, 128, 126) },
	Snow = { rgb(214, 224, 236), rgb(200, 212, 226) },
	-- red-rock mesas: terracotta bands with a cream band every fourth stratum
	Redrock = { rgb(190, 108, 78), rgb(206, 130, 92), rgb(222, 170, 124), rgb(232, 200, 160) },
	Sandstone = { rgb(206, 162, 112), rgb(190, 144, 98), rgb(222, 186, 138) },
}
local DIRT = rgb(166, 118, 78)
local KIND_STYLE = {
	grass = { body = DIRT, name = "Grass", strata = "Dirt" }, -- cap shade by noise patch
	meadow = { cap = rgb(138, 194, 88), body = DIRT, name = "Meadow", strata = "Dirt" },
	path = { cap = rgb(206, 180, 136), body = DIRT, name = "Path", strata = "Dirt" },
	sand = { cap = rgb(232, 212, 160), body = rgb(212, 188, 138), name = "Sand" },
	shallow = { body = rgb(222, 204, 150), name = "Shallows" },
	seabed = { body = rgb(176, 196, 150), name = "Seabed" },
	deep = { body = rgb(86, 150, 150), name = "DeepSeabed" },
	stone = { cap = rgb(176, 172, 166), body = rgb(150, 146, 142), name = "Stone", strata = "Stone" },
	snow = { cap = rgb(238, 242, 246), body = rgb(214, 224, 236), name = "Snow" }, -- one icy body, no bands
	grassRock = { body = rgb(150, 146, 142), name = "Mountainside", strata = "Mountainside" }, -- grass cap
	redrock = { body = rgb(190, 108, 78), name = "RedRock", strata = "Redrock" }, -- ochre/grass cap
	mesa = { body = rgb(204, 160, 112), name = "Sandstone", strata = "Sandstone" }, -- grass cap, warm cliff
}

-- Sea floor colour by depth: bright sand in the shallows, turquoise lagoon, deep-blue ocean.
local SEABED_BY_TOP = {
	[-2] = rgb(226, 206, 150),
	[-4] = rgb(212, 200, 150),
	[-6] = rgb(180, 196, 150),
	[-8] = rgb(146, 180, 156),
	[-14] = rgb(100, 160, 158),
	[-16] = rgb(84, 140, 150),
	[-24] = rgb(44, 96, 136),
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
				if kind == "redrock" then
					-- flat mesa tops are ochre sand, lower ledges grassy
					capColor = if top > 40 then rgb(218, 182, 122) else GRASS_LIME
				elseif kind == "grass" or kind == "grassRock" or kind == "mesa" then
					-- three tints in broad patches (forest floor / lime / warm meadow)
					local tint = world:noise(cx / 256 + 3.7, cz / 256 - 1.3)
					capColor = if math.sqrt(cx * cx + cz * cz) > FAR
						then GRASS_LIME
						elseif top > HIGH_GROUND then GRASS_HIGH
						elseif tint < -0.28 then GRASS_FOREST
						elseif tint > 0.32 then GRASS_MEADOW
						else GRASS_LIME
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
					local strataName = style.strata
					if kind == "path" and top > 24 then
						strataName = "Mountainside" -- the carved peak trail: rock walls, not dirt
					end
					local strata = not underwater and strataName and STRATA[strataName]
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
