-- misc.luau: small engines with no gameplay effect: animation tracks and
-- sounds (state + timing only, nothing is rendered or heard).

local roblox = require("@lune/roblox")

local Misc = {}
Misc.__index = Misc

function Misc.new(sim)
	local self = setmetatable({}, Misc)
	self.sim = sim
	self.tracks = setmetatable({}, { __mode = "k" }) -- raw AnimationTrack -> state
	self.tracksOf = setmetatable({}, { __mode = "k" }) -- raw animator/humanoid -> { tracks }
	self.sounds = setmetatable({}, { __mode = "k" }) -- raw Sound -> state
	return self
end

-- Animation tracks -------------------------------------------------------------------------

function Misc:loadAnimation(owner, anim)
	local sim = self.sim
	local animReal = sim.proxy:toReal(anim)
	if animReal == nil or not animReal:IsA("Animation") then
		error("LoadAnimation requires an Animation object", 0)
	end
	local track = roblox.Instance.new("AnimationTrack")
	track.Name = animReal.Name
	local len = animReal:GetAttribute("SimLength")
	self.tracks[track] = {
		playing = false,
		speed = 1,
		length = type(len) == "number" and len or 1,
		started = 0,
		animation = animReal,
		token = 0,
	}
	local list = self.tracksOf[owner]
	if list == nil then
		list = {}
		self.tracksOf[owner] = list
	end
	table.insert(list, track)
	return sim.proxy:wrap(track)
end

function Misc:trackState(track)
	local st = self.tracks[track]
	if st == nil then
		st = { playing = false, speed = 1, length = 1, started = 0, token = 0 }
		self.tracks[track] = st
	end
	return st
end

function Misc:playTrack(track, speed)
	local sim = self.sim
	local st = self:trackState(track)
	st.playing = true
	st.speed = speed or st.speed
	st.started = sim.sched.clock
	st.token += 1
	local token = st.token
	local looped = track.Looped
	if not looped and st.length > 0 then
		sim.sched:after(st.length / math.max(st.speed, 1e-3), function()
			if st.token == token and st.playing then
				st.playing = false
				sim.proxy:fire(track, "Stopped")
				sim.proxy:fire(track, "Ended")
			end
		end)
	end
end

function Misc:stopTrack(track)
	local st = self:trackState(track)
	if st.playing then
		st.playing = false
		st.token += 1
		self.sim.proxy:fire(track, "Stopped")
		self.sim.proxy:fire(track, "Ended")
	end
end

function Misc:playingTracks(owner)
	local out = {}
	for _, t in self.tracksOf[owner] or {} do
		if self:trackState(t).playing then
			table.insert(out, self.sim.proxy:wrap(t))
		end
	end
	return out
end

-- Sounds --------------------------------------------------------------------------------------

function Misc:soundState(sound)
	local st = self.sounds[sound]
	if st == nil then
		st = { playing = false, paused = false, token = 0 }
		self.sounds[sound] = st
	end
	return st
end

function Misc:playSound(sound, resume: boolean?)
	local sim = self.sim
	local st = self:soundState(sound)
	st.playing = true
	st.paused = false
	st.token += 1
	local token = st.token
	sim.proxy:fire(sound, if resume then "Resumed" else "Played", sound.SoundId)
	local len = sound:GetAttribute("SimTimeLength")
	len = type(len) == "number" and len or 1
	if not sound.Looped then
		sim.sched:after(len / math.max(sound.PlaybackSpeed, 1e-3), function()
			if st.token == token and st.playing then
				st.playing = false
				sim.proxy:fire(sound, "Ended", sound.SoundId)
			end
		end)
	end
end

function Misc:stopSound(sound, how: string)
	local st = self:soundState(sound)
	if st.playing then
		st.playing = false
		st.paused = how == "Paused"
		st.token += 1
		self.sim.proxy:fire(sound, how, sound.SoundId)
	end
end

return Misc
