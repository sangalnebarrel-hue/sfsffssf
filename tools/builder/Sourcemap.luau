--[[
	Writes a Rojo-style sourcemap.json describing the whole built DataModel, so luau-lsp can
	type-check instance paths (e.g. ReplicatedStorage.Shared.Net) and resolve require(script...)
	exactly as they exist inside Place1.rbxl. Only used for static analysis.
]]

local SKIP_CLASSES = {
	Terrain = true,
	Camera = true,
}

-- Only services our code touches; odd Studio-internal services confuse luau-lsp's DataModel types.
local SERVICES = {
	"Workspace",
	"Players",
	"Lighting",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"SoundService",
}

local Sourcemap = {}

local function node(inst: any, mapping: { [any]: string }): any
	local out: { [string]: any } = {
		name = inst.Name,
		className = inst.ClassName,
	}
	local file = mapping[inst]
	if file then
		out.filePaths = { file }
	end
	local children = {}
	for _, child in inst:GetChildren() do
		if not SKIP_CLASSES[child.ClassName] then
			table.insert(children, node(child, mapping))
		end
	end
	if #children > 0 then
		out.children = children
	end
	return out
end

function Sourcemap.build(game: any, mapping: { [any]: string }): any
	local children = {}
	for _, serviceName in SERVICES do
		local service = game:FindFirstChildOfClass(serviceName)
		if service then
			table.insert(children, node(service, mapping))
		end
	end
	return { name = "Game", className = "DataModel", children = children }
end

return Sourcemap
