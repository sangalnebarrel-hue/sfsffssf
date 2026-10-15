--!strict
--[[
	AmbientController — «живой» мир, только для красоты и только на клиенте. Сам контроллер —
	сборка; работа в помощниках (модули рядом):
	  AmbientEngine   — общий «мотор»: ОДНО соединение PreRender на всё, ярусы по
	                    расстоянию (каждый кадр / ≈20 Гц / ≈7 Гц), только то, что на экране,
	                    бюджет деталей на кадр, все движения одним BulkMoveTo; рядом ничего —
	                    соединение отключается;
	  AmbientWind     — один ветер: порывы бегут волной по миру, Workspace.GlobalWind (дым,
	                    туман водопада, лепестки сносит по ветру);
	  AmbientWorld    — то, что пометил строитель карты (DESIGN.md «Ambient attributes»):
	                    Spin (мельница, колесо обозрения…), Bob (лодки, буйки), Sway (флаги,
	                    вымпелы, гирлянды, паруса, ветряной конус, колокольчики, пальмы, камыш,
	                    водоросли — по ветру), Pulse (пена прибоя), Drift (облака) и «бегущий
	                    огонь» лампочек колеса обозрения и гирлянд;
	  AmbientWater    — блики солнца на воде, выпрыгивающие рыбы, стайки у поверхности, пена
	                    вокруг лодок и свай, струи водопада;
	  AmbientCritters — чайки (машут / парят / пике у пирса), бабочки у клумб, стрекозы у пирса.

	Бюджеты (замер в RbxSim: tools/preview/ambient_dump.luau, tests/ambient.test.luau):
	  • 1 соединение (RunService.PreRender) на весь живой мир; 0 — когда рядом нечего двигать;
	  • не больше Budget деталей + записей свойств за кадр: телефон 220, ПК 400 (телефон: у точки
	    рыбалки ≈ 120–140 за кадр, пик = бюджет; на платформе пирса ≈ 60; во дворе базы 20–60);
	    в RbxSim кадр у точки рыбалки стоит 3,6 мс против 9,6 мс у старого «всё раз в 2 кадра»;
	  • своих деталей ≈ 200: стайки 60, чайки 56, бабочки 18, стрекозы 9, две рыбы для прыжка
	    (модели карася и окуня, 27) + брызги и 2 круга, блики 3, кольца пены 24
	    (MapConfig.PartBudget.RuntimeReserve.AmbientLife = 200);
	  • частиц: блики ≈ 10 одновременно, брызги прыжка 10–12 раз в 5–9 с;
	  • ни одного Instance в кадре (всё создаётся при старте, пул переиспользуется).

	API (тесты, превью): AmbientController.Engine (AmbientEngine или nil до загрузки карты),
	AmbientController.Ready (true, когда всё собрано), AmbientController.Summary (сколько чего
	нашлось), AmbientController.Water / .Critters (State помощников), AmbientController.JumpSoon() / SwoopSoon().
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientEngine = require(script.Parent:WaitForChild("AmbientEngine"))
local AmbientWind = require(script.Parent:WaitForChild("AmbientWind"))
local AmbientWorld = require(script.Parent:WaitForChild("AmbientWorld"))
local AmbientWater = require(script.Parent:WaitForChild("AmbientWater"))
local AmbientCritters = require(script.Parent:WaitForChild("AmbientCritters"))
local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapConfig"))

local BUDGET_TOUCH = 220
local BUDGET_DESKTOP = 400
local NEAREST_BASE = 170 -- ближайший к камере пирс (стаи, стрекозы, чайка, пена у свай) — не дальше
local FLOWER_CELL = 16 -- клумбы: цветы группами по клеткам столько studs
local FLOWER_MIN = 3 -- … не меньше стольких цветов в клетке

type Base = AmbientWater.Base

local AmbientController = {}
AmbientController.Engine = nil :: AmbientEngine.Engine?
AmbientController.Ready = false
AmbientController.Summary = {} :: { [string]: any }
AmbientController.Flowers = {} :: { Vector3 } -- клумбы для бабочек (верх цветов)
AmbientController.Water = AmbientWater.State
AmbientController.Critters = AmbientCritters.State

-- Рыба выпрыгнет на ближайшем тике (по обычным правилам места) — тесты и превью.
function AmbientController.JumpSoon()
	AmbientWater.JumpSoon()
end

-- «Пирсовая» чайка нырнёт к пирсу на ближайшем тике — тесты и превью.
function AmbientController.SwoopSoon()
	AmbientCritters.SwoopSoon()
end

-- Базы игроков: точка рыбалки, поворот базы (−Z — к лагуне), сваи пирса у воды.
local function collectBases(bases: Instance?): { Base }
	local list: { Base } = {}
	if not bases then
		return list
	end
	for _, model in bases:GetChildren() do
		local spot = model:FindFirstChild("FishingSpot")
		if model:IsA("Model") and spot and spot:IsA("BasePart") then
			local posts = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Post" then
					local half = d.Size.Y / 2
					local y = d.Position.Y
					if y - half < MapConfig.WaterTop and y + half > MapConfig.WaterTop + 0.5 and d.Size.X <= 3 then
						table.insert(posts, Vector3.new(d.Position.X, MapConfig.WaterTop, d.Position.Z))
					end
				end
			end
			table.insert(list, { model = model, spot = spot.Position, cf = model:GetPivot(), posts = posts })
		end
	end
	return list
end

-- Клумбы: верх цветов («Bloom…»), сгруппированных по клеткам.
local function collectFlowers(roots: { Instance }): { Vector3 }
	local cells: { [string]: { sum: Vector3, top: number, count: number } } = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if
				d:IsA("BasePart")
				and string.find(d.Name, "Bloom", 1, true)
				and not string.find(d.Name, "Eye", 1, true)
			then
				local p = d.Position
				local key = `{math.floor(p.X / FLOWER_CELL)},{math.floor(p.Z / FLOWER_CELL)}`
				local cell = cells[key]
				if not cell then
					cell = { sum = Vector3.zero, top = -math.huge, count = 0 }
					cells[key] = cell
				end
				cell.sum += p
				cell.top = math.max(cell.top, p.Y + d.Size.Y / 2)
				cell.count += 1
			end
		end
	end
	local list = {}
	for _, cell in cells do
		if cell.count >= FLOWER_MIN then
			local c = cell.sum / cell.count
			table.insert(list, Vector3.new(c.X, cell.top, c.Z))
		end
	end
	table.sort(list, function(a: Vector3, b: Vector3): boolean
		return a.X + a.Z * 1e-3 < b.X + b.Z * 1e-3
	end)
	return list
end

function AmbientController:Start(_hud: ScreenGui)
	local folder = Instance.new("Folder")
	folder.Name = "Ambient (client)"
	folder.Parent = Workspace

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local engine = AmbientEngine.new(if touch then BUDGET_TOUCH else BUDGET_DESKTOP)
	AmbientController.Engine = engine

	-- Карта уже в месте (StreamingEnabled выключен), базы сервер создаёт при старте —
	-- коротко ждём их, не задерживая остальные контроллеры.
	task.spawn(function()
		local map = Workspace:WaitForChild("Map", 10)
		local basesFolder = Workspace:WaitForChild("Bases", 10)
		local summary: { [string]: any } = { items = {}, parts = {} }
		local bobs = {}
		for _, root in { map, basesFolder } do
			if root then
				local s = AmbientWorld.Collect(root, engine)
				for kind, n in s.items do
					summary.items[kind] = (summary.items[kind] or 0) + n
				end
				for kind, n in s.parts do
					summary.parts[kind] = (summary.parts[kind] or 0) + n
				end
				for _, bob in s.bobs do
					table.insert(bobs, bob)
				end
				summary.windEmitters = (summary.windEmitters or 0) + AmbientWind.Follow(root)
			end
		end

		local bases = collectBases(basesFolder)
		local function nearestBase(): Base?
			local cam = engine.camPos
			local best, bestDist = nil, NEAREST_BASE
			for _, base in bases do
				local d = Vector3.new(base.spot.X - cam.X, 0, base.spot.Z - cam.Z).Magnitude
				if d < bestDist and base.model.Parent then
					best, bestDist = base, d
				end
			end
			return best
		end
		local roots: { Instance } = {}
		if map then
			table.insert(roots, map)
		end
		if basesFolder then
			table.insert(roots, basesFolder)
		end
		local flowers = collectFlowers(roots)
		AmbientController.Flowers = flowers
		local rng = Random.new(7)
		AmbientWater.Start(engine, folder, map, {
			bobs = bobs,
			bases = function()
				return bases
			end,
			nearestBase = nearestBase,
			rng = rng,
		})
		AmbientCritters.Start(engine, folder, {
			nearestBase = nearestBase,
			flowers = flowers,
			rng = rng,
		})
		engine:Every(0.25, function(now: number)
			AmbientWind.Apply(now, engine.camPos)
		end)
		summary.bobs = #bobs
		summary.bases = #bases
		summary.flowers = #flowers
		summary.parts.own = #folder:GetChildren()
		AmbientController.Summary = summary
		engine:Start()
		AmbientController.Ready = true
	end)
end

return AmbientController
