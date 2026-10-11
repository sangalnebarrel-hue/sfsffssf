--[[
	Encoder (and decoder, for tests) of Roblox smooth terrain as stored in a place file:
	Terrain.SmoothGrid and Terrain.PhysicsGrid (BinaryString properties).

	Format (reverse-engineered by github.com/chteau/rbx-native rbx_terrain, verified there to
	re-encode a real place byte for byte):
	  SmoothGrid:  byte version = 1, byte log2(chunk edge) = 5, then chunks sorted by (x, y, z).
	    Each chunk: offset from the previous chunk key (first: from 0,0,0) as three 32-bit
	    two's-complement ints, big-endian, bytes interleaved by significance (top byte of x, y, z,
	    then the next byte of each, ...). Then run records covering the 32³ voxels, X fastest,
	    then Z, then Y. Record lead byte: low 6 bits = material slot, bit 6 = occupancy byte
	    follows (default: Air empty, others full), bit 7 = count byte follows (run = count + 1).
	  PhysicsGrid: byte 2, byte 3 (log2 of an 8-voxel region), u32 BE count + region keys
	    (offsets encoded like chunk offsets), then two empty lists (8 zero bytes). Regions =
	    every 8³ region touched by a non-Air voxel grown by one voxel on each side.
	Voxel (i, j, k) spans studs 4i..4i+4 on each axis. Occupancy byte b means (b + 1) / 256 full.
]]

local SmoothGrid = {}
SmoothGrid.__index = SmoothGrid

local CHUNK = 32
local CHUNK_CELLS = CHUNK * CHUNK * CHUNK

-- Material slots in SmoothGrid order (NOT Enum.Material values).
SmoothGrid.Slots = {
	Air = 0,
	Water = 1,
	Grass = 2,
	Slate = 3,
	Concrete = 4,
	Brick = 5,
	Sand = 6,
	WoodPlanks = 7,
	Rock = 8,
	Glacier = 9,
	Snow = 10,
	Sandstone = 11,
	Mud = 12,
	Basalt = 13,
	Ground = 14,
	CrackedLava = 15,
	Asphalt = 16,
	Cobblestone = 17,
	Ice = 18,
	LeafyGrass = 19,
	Salt = 20,
	Limestone = 21,
	Pavement = 22,
}
SmoothGrid.SlotNames = {}
for name, slot in SmoothGrid.Slots do
	SmoothGrid.SlotNames[slot] = name
end

-- Byte writer on a growing buffer.
local Writer = {}
Writer.__index = Writer

function Writer.new(capacity: number?)
	return setmetatable({ buf = buffer.create(capacity or 65536), len = 0 }, Writer)
end

function Writer:ensure(extra: number)
	local need = self.len + extra
	local cap = buffer.len(self.buf)
	if need > cap then
		while cap < need do
			cap *= 2
		end
		local bigger = buffer.create(cap)
		buffer.copy(bigger, 0, self.buf, 0, self.len)
		self.buf = bigger
	end
end

function Writer:u8(v: number)
	self:ensure(1)
	buffer.writeu8(self.buf, self.len, v)
	self.len += 1
end

function Writer:tostring(): string
	local out = buffer.create(self.len)
	buffer.copy(out, 0, self.buf, 0, self.len)
	return buffer.tostring(out)
end

local function floor_div(a: number, b: number): number
	return math.floor(a / b)
end

-- Three signed 32-bit ints, big-endian, bytes interleaved by significance.
local function writeKey(w: any, dx: number, dy: number, dz: number)
	local ux, uy, uz = dx % 4294967296, dy % 4294967296, dz % 4294967296
	for _, shift in { 24, 16, 8, 0 } do
		local d = 2 ^ shift
		w:u8(floor_div(ux, d) % 256)
		w:u8(floor_div(uy, d) % 256)
		w:u8(floor_div(uz, d) % 256)
	end
end

--------------------------------------------------------------------------------
-- Voxel store
--------------------------------------------------------------------------------

function SmoothGrid.new()
	return setmetatable({ chunks = {} }, SmoothGrid)
end

local function chunkKey(cx: number, cy: number, cz: number): string
	return `{cx},{cy},{cz}`
end

local function getChunk(self: any, cx: number, cy: number, cz: number, create: boolean): any
	local key = chunkKey(cx, cy, cz)
	local chunk = self.chunks[key]
	if not chunk and create then
		chunk = {
			x = cx,
			y = cy,
			z = cz,
			material = buffer.create(CHUNK_CELLS),
			occupancy = buffer.create(CHUNK_CELLS),
			filled = 0,
		}
		self.chunks[key] = chunk
	end
	return chunk
end

-- Sets a voxel. occupancy is a 0..1 fraction (ignored for Air). Writing over an existing solid
-- voxel keeps the fuller of the two (so overlapping features merge).
function SmoothGrid:set(vx: number, vy: number, vz: number, slot: number, occupancy: number)
	local cx, cy, cz = math.floor(vx / CHUNK), math.floor(vy / CHUNK), math.floor(vz / CHUNK)
	local chunk = getChunk(self, cx, cy, cz, slot ~= 0)
	if not chunk then
		return
	end
	local index = (vx - cx * CHUNK) + (vz - cz * CHUNK) * CHUNK + (vy - cy * CHUNK) * CHUNK * CHUNK
	local byte = 0
	if slot ~= 0 then
		byte = math.clamp(math.floor(occupancy * 256 + 0.5) - 1, 0, 255)
	end
	local oldSlot = buffer.readu8(chunk.material, index)
	if oldSlot ~= 0 and slot ~= 0 and oldSlot ~= 1 and slot ~= 1 then
		if buffer.readu8(chunk.occupancy, index) >= byte then
			return
		end
	end
	if oldSlot == 0 and slot ~= 0 then
		chunk.filled += 1
	elseif oldSlot ~= 0 and slot == 0 then
		chunk.filled -= 1
	end
	buffer.writeu8(chunk.material, index, slot)
	buffer.writeu8(chunk.occupancy, index, byte)
end

function SmoothGrid:get(vx: number, vy: number, vz: number): (number, number)
	local cx, cy, cz = math.floor(vx / CHUNK), math.floor(vy / CHUNK), math.floor(vz / CHUNK)
	local chunk = getChunk(self, cx, cy, cz, false)
	if not chunk then
		return 0, 0
	end
	local index = (vx - cx * CHUNK) + (vz - cz * CHUNK) * CHUNK + (vy - cy * CHUNK) * CHUNK * CHUNK
	return buffer.readu8(chunk.material, index), buffer.readu8(chunk.occupancy, index)
end

local function sortedChunks(self: any): { any }
	local list = {}
	for _, chunk in self.chunks do
		if chunk.filled > 0 then
			table.insert(list, chunk)
		end
	end
	table.sort(list, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		elseif a.y ~= b.y then
			return a.y < b.y
		end
		return a.z < b.z
	end)
	return list
end

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

function SmoothGrid:encode(): string
	local w = Writer.new(1048576)
	w:u8(1)
	w:u8(5)
	local px, py, pz = 0, 0, 0
	for _, chunk in sortedChunks(self) do
		writeKey(w, chunk.x - px, chunk.y - py, chunk.z - pz)
		px, py, pz = chunk.x, chunk.y, chunk.z
		local mat, occ = chunk.material, chunk.occupancy
		local at = 0
		while at < CHUNK_CELLS do
			local slot = buffer.readu8(mat, at)
			local o = buffer.readu8(occ, at)
			local run = 1
			while at + run < CHUNK_CELLS and run < 256 do
				if buffer.readu8(mat, at + run) ~= slot or buffer.readu8(occ, at + run) ~= o then
					break
				end
				run += 1
			end
			local default = if slot == 0 then 0 else 255
			local lead = slot
			if o ~= default then
				lead += 0x40
			end
			if run > 1 then
				lead += 0x80
			end
			w:u8(lead)
			if o ~= default then
				w:u8(o)
			end
			if run > 1 then
				w:u8(run - 1)
			end
			at += run
		end
	end
	return w:tostring()
end

-- Regions (8³ voxels) touched by any non-Air voxel grown by one voxel.
function SmoothGrid:encodePhysics(): string
	local reachLo, reachHi = {}, {}
	for v = 0, CHUNK - 1 do
		reachLo[v] = math.floor((v - 1) / 8) + 1
		reachHi[v] = math.floor((v + 1) / 8) + 1
	end
	local regions = {}
	local list = {}
	for _, chunk in sortedChunks(self) do
		local touched = buffer.create(216)
		local mat = chunk.material
		local index = 0
		for y = 0, CHUNK - 1 do
			local ylo, yhi = reachLo[y], reachHi[y]
			for z = 0, CHUNK - 1 do
				local zlo, zhi = reachLo[z], reachHi[z]
				for x = 0, CHUNK - 1 do
					if buffer.readu8(mat, index) ~= 0 then
						for ry = ylo, yhi do
							for rz = zlo, zhi do
								for rx = reachLo[x], reachHi[x] do
									buffer.writeu8(touched, rx + 6 * (rz + 6 * ry), 1)
								end
							end
						end
					end
					index += 1
				end
			end
		end
		local bx, by, bz = chunk.x * 4 - 1, chunk.y * 4 - 1, chunk.z * 4 - 1
		for ry = 0, 5 do
			for rz = 0, 5 do
				for rx = 0, 5 do
					if buffer.readu8(touched, rx + 6 * (rz + 6 * ry)) == 1 then
						local key = `{bx + rx},{by + ry},{bz + rz}`
						if not regions[key] then
							regions[key] = true
							table.insert(list, { bx + rx, by + ry, bz + rz })
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		elseif a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[3] < b[3]
	end)
	local w = Writer.new(16 + #list * 12)
	w:u8(2)
	w:u8(3)
	local count = #list
	w:u8(math.floor(count / 16777216) % 256)
	w:u8(math.floor(count / 65536) % 256)
	w:u8(math.floor(count / 256) % 256)
	w:u8(count % 256)
	local px, py, pz = 0, 0, 0
	for _, region in list do
		writeKey(w, region[1] - px, region[2] - py, region[3] - pz)
		px, py, pz = region[1], region[2], region[3]
	end
	for _ = 1, 8 do
		w:u8(0)
	end
	return w:tostring()
end

--------------------------------------------------------------------------------
-- Decoding (tests / sanity checks)
--------------------------------------------------------------------------------

local function readKey(bytes: string, at: number): (number, number, number, number)
	local acc = { 0, 0, 0 }
	for _ = 1, 4 do
		for axis = 1, 3 do
			acc[axis] = acc[axis] * 256 + string.byte(bytes, at)
			at += 1
		end
	end
	for axis = 1, 3 do
		if acc[axis] >= 2147483648 then
			acc[axis] -= 4294967296
		end
	end
	return acc[1], acc[2], acc[3], at
end

-- Decodes a SmoothGrid blob into a new store. Errors on malformed data.
function SmoothGrid.decode(bytes: string): any
	assert(string.byte(bytes, 1) == 1, "SmoothGrid: version must be 1")
	assert(string.byte(bytes, 2) == 5, "SmoothGrid: chunk log2 must be 5")
	local grid = SmoothGrid.new()
	local at = 3
	local kx, ky, kz = 0, 0, 0
	while at <= #bytes do
		local dx, dy, dz
		dx, dy, dz, at = readKey(bytes, at)
		kx, ky, kz = kx + dx, ky + dy, kz + dz
		local chunk = getChunk(grid, kx, ky, kz, true)
		local filled = 0
		while filled < CHUNK_CELLS do
			local lead = string.byte(bytes, at)
			assert(lead, "SmoothGrid: truncated")
			at += 1
			local slot = lead % 64
			assert(SmoothGrid.SlotNames[slot], `SmoothGrid: bad material slot {slot}`)
			local o = if slot == 0 then 0 else 255
			if bit32.band(lead, 0x40) ~= 0 then
				o = string.byte(bytes, at)
				at += 1
			end
			local run = 1
			if bit32.band(lead, 0x80) ~= 0 then
				local count = string.byte(bytes, at)
				at += 1
				if count == 0 then
					at += 1 -- liquid byte
				else
					run = count + 1
				end
			end
			assert(filled + run <= CHUNK_CELLS, "SmoothGrid: run overflows chunk")
			for i = filled, filled + run - 1 do
				buffer.writeu8(chunk.material, i, slot)
				buffer.writeu8(chunk.occupancy, i, o)
			end
			if slot ~= 0 then
				chunk.filled += run
			end
			filled += run
		end
	end
	return grid
end

-- Count of non-Air voxels per material name.
function SmoothGrid:stats(): { [string]: number }
	local counts = {}
	for _, chunk in self.chunks do
		for i = 0, CHUNK_CELLS - 1 do
			local slot = buffer.readu8(chunk.material, i)
			if slot ~= 0 then
				local name = SmoothGrid.SlotNames[slot]
				counts[name] = (counts[name] or 0) + 1
			end
		end
	end
	return counts
end

return SmoothGrid
