-- collection.luau: CollectionService tag signals. Tags themselves are stored
-- on the Lune instances (AddTag/HasTag); this module only adds the events.

local Collection = {}
Collection.__index = Collection

function Collection.new(sim)
	local self = setmetatable({}, Collection)
	self.sim = sim
	self.watched = 0 -- number of tag signals ever requested
	return self
end

function Collection:_signal(kind: string, tag: string)
	local sim = self.sim
	local key = kind .. ":" .. tag
	local sigs = sim.proxy.signals[sim.collectionReal]
	if sigs == nil or sigs[key] == nil then
		self.watched += 1
	end
	return sim.proxy:getSignal(sim.collectionReal, key)
end

function Collection:addedSignal(tag: string)
	return self:_signal("TagAdded", tag)
end

function Collection:removedSignal(tag: string)
	return self:_signal("TagRemoved", tag)
end

local function tagArg(tag)
	if type(tag) ~= "string" then
		error("Argument 2 missing or nil (tag must be a string)", 0)
	end
	return tag
end

function Collection:addTag(real, tag)
	tagArg(tag)
	if real:HasTag(tag) then
		return
	end
	real:AddTag(tag)
	if self.sim.proxy:isInGame(real) then
		self.sim.proxy:fire(self.sim.collectionReal, "TagAdded:" .. tag, self.sim.proxy:wrap(real))
	end
end

function Collection:removeTag(real, tag)
	tagArg(tag)
	if not real:HasTag(tag) then
		return
	end
	real:RemoveTag(tag)
	if self.sim.proxy:isInGame(real) then
		self.sim.proxy:fire(self.sim.collectionReal, "TagRemoved:" .. tag, self.sim.proxy:wrap(real))
	end
end

function Collection:getTagged(tag)
	tagArg(tag)
	local out = {}
	for _, d in self.sim.real:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(out, self.sim.proxy:wrap(d))
		end
	end
	return out
end

function Collection:allTags()
	local seen, out = {}, {}
	for _, d in self.sim.real:GetDescendants() do
		for _, t in d:GetTags() do
			if not seen[t] then
				seen[t] = true
				table.insert(out, t)
			end
		end
	end
	table.sort(out)
	return out
end

-- Called after a subtree enters or leaves the DataModel.
function Collection:onMembershipChanged(subtree, entered: boolean)
	if self.watched == 0 then
		return
	end
	local sim = self.sim
	local kind = if entered then "TagAdded:" else "TagRemoved:"
	for _, inst in subtree do
		for _, t in inst:GetTags() do
			sim.proxy:fire(sim.collectionReal, kind .. t, sim.proxy:wrap(inst))
		end
	end
end

return Collection
