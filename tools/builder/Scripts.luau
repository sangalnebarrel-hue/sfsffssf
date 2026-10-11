--[[
	Copies Luau sources from src/ into the place:
	  src/<Service>/.../<Name>.server.luau → Script
	  src/<Service>/.../<Name>.client.luau → LocalScript
	  src/<Service>/.../<Name>.luau        → ModuleScript
	  directories                          → Folder (or an existing built-in container,
	                                           e.g. StarterPlayer/StarterPlayerScripts)
	Existing Folders/scripts with the same name are replaced, so the build is repeatable.
	Returns a map Instance → source path (used for sourcemap.json).
]]

local fs = require("@lune/fs")

local U = require("./Util")

local Scripts = {}

local function classify(fileName: string): (string?, string?)
	local name = string.match(fileName, "^(.+)%.server%.luau$")
	if name then
		return "Script", name
	end
	name = string.match(fileName, "^(.+)%.client%.luau$")
	if name then
		return "LocalScript", name
	end
	name = string.match(fileName, "^(.+)%.luau$")
	if name then
		return "ModuleScript", name
	end
	return nil, nil
end

local function isReplaceable(inst: any): boolean
	return inst:IsA("Folder") or inst:IsA("LuaSourceContainer")
end

local function sortedEntries(dir: string): { string }
	local entries = fs.readDir(dir)
	table.sort(entries)
	return entries
end

local function syncDir(dir: string, parent: any, mapping: { [any]: string }, created: { any })
	for _, entry in sortedEntries(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			local existing = parent:FindFirstChild(entry)
			local container
			if existing and not isReplaceable(existing) then
				container = existing -- built-in container such as StarterPlayerScripts
			else
				if existing then
					existing:Destroy()
				end
				container = U.new("Folder", { Name = entry }, parent)
				table.insert(created, container)
			end
			syncDir(path, container, mapping, created)
		else
			local className, name = classify(entry)
			if className and name then
				local existing = parent:FindFirstChild(name)
				if existing then
					existing:Destroy()
				end
				local script = U.new(className, { Name = name }, parent)
				script.Source = fs.readFile(path)
				mapping[script] = path
				table.insert(created, script)
			end
		end
	end
end

function Scripts.sync(game: any, srcRoot: string): ({ [any]: string }, { any })
	local mapping: { [any]: string } = {}
	local created: { any } = {}
	for _, serviceName in sortedEntries(srcRoot) do
		local path = `{srcRoot}/{serviceName}`
		if fs.isDir(path) then
			local service = game:GetService(serviceName)
			syncDir(path, service, mapping, created)
		end
	end
	return mapping, created
end

return Scripts
