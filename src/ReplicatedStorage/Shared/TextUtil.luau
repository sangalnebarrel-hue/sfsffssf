--!strict
--[[
	TextUtil — мелочи для текста интерфейса (клиент и сервер).

	  TextUtil.upper(text) — ЗАГЛАВНЫЕ буквы, включая кириллицу: string.upper знает только
	    латиницу («Лазурная» → «ЛАЗУРНАЯ», ё → Ё). Интерфейс «Кирпичики» пишет заглавными плашки,
	    кнопки, баннеры и заголовки (tools/builder/gui/STYLE.md §1); подсказки и обычные
	    уведомления — как есть.
	  TextUtil.fill(template, values) — шаблон текста из конфига с полями в фигурных скобках:
	    fill("Замена! «{new}» вместо «{old}» +{price}", { new = "Меч-рыба", old = "Карасик",
	    price = "$24" }) → «Замена! «Меч-рыба» вместо «Карасик» +$24». Поле, которого нет в values,
	    остаётся как есть («{old}») — опечатку в конфиге видно сразу.

	Модуль «чистый» (без require и game): его можно звать откуда угодно.
]]

local TextUtil = {}

function TextUtil.upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20 -- а…я → А…Я, a…z → A…Z
		elseif code >= 0x450 and code <= 0x45F then
			code -= 0x50 -- ё, ђ … џ → Ё, Ђ … Џ
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

function TextUtil.fill(template: string, values: { [string]: string | number }): string
	return (
		string.gsub(template, "{(%w+)}", function(key: string): string
			local value = values[key]
			return if value ~= nil then tostring(value) else "{" .. key .. "}"
		end)
	)
end

return TextUtil
