--!strict
--[[
	Notify — всплывающие уведомления игрокам (RemoteEvent "Notify").
	Клиент показывает их вверху экрана (NotifyController).

	Notify.Send(player, "Твоя база: Красная", "success")
	Notify.All("Сервер перезапустится через минуту", "warning")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Kind = "info" | "success" | "warning" | "danger"

local remote = Net.Event("Notify")

local Notify = {}

function Notify.Send(player: Player, text: string, kind: Kind?)
	if player.Parent ~= Players then
		return
	end
	remote:FireClient(player, text, kind or "info")
end

function Notify.All(text: string, kind: Kind?)
	remote:FireAllClients(text, kind or "info")
end

return Notify
