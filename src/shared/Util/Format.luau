--!strict
-- Formatage des nombres et durées pour l'affichage.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
-- Français (GDD §13.1) : virgule décimale, espace insécable avant le suffixe : « 1,24 M »
local SUFFIXES_FR = { "", "k", "M", "Md", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local NBSP = "\194\160" -- U+00A0 (espace insécable) en UTF-8

-- 1234 → "1.23K", 15300000 → "15.3M", 999 → "999" ; lang "fr" : "1,23 k", "15,3 M"
function Format.abbreviate(n: number, lang: string?): string
	if n ~= n then
		return "0"
	end
	local fr = lang == "fr"
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = tostring(math.floor(n))
		return if negative then "-" .. s else s
	end
	local suffixes = if fr then SUFFIXES_FR else SUFFIXES
	local tier = math.min(math.floor(math.log10(n) / 3), #suffixes - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- 3 chiffres significatifs au total : 1.23K, 12.3K, 123K
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	-- zéros inutiles après la virgule seulement (100K reste 100K)
	if string.find(text, ".", 1, true) then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	local s
	if fr then
		s = string.gsub(text, "%.", ",") .. NBSP .. suffixes[tier + 1]
	else
		s = text .. suffixes[tier + 1]
	end
	return if negative then "-" .. s else s
end

-- 1234567 → "1,234,567" ; lang "fr" : "1 234 567" (espaces insécables)
function Format.commas(n: number, lang: string?): string
	local sep = if lang == "fr" then NBSP else ","
	local s = tostring(math.floor(math.abs(n)))
	local groups = {}
	local first = #s % 3
	if first > 0 then
		table.insert(groups, string.sub(s, 1, first))
	end
	for i = first + 1, #s, 3 do
		table.insert(groups, string.sub(s, i, i + 2))
	end
	local out = table.concat(groups, sep)
	return if n < 0 then "-" .. out else out
end

-- 75 → "1:15", 3725 → "1:02:05"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 90 → "1m 30s", 7200 → "2h", 45 → "45s" ; lang "fr" : "1 min 30 s", "2 h", "5 h 12"
function Format.duration(seconds: number, lang: string?): string
	seconds = math.max(0, math.floor(seconds))
	local fr = lang == "fr"
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if fr then
		if seconds < 60 then
			return `{seconds}{NBSP}s`
		end
		if h > 0 then
			return if m > 0 then string.format("%d%sh%s%02d", h, NBSP, NBSP, m) else `{h}{NBSP}h`
		end
		return if s > 0 then `{m}{NBSP}min{NBSP}{s}{NBSP}s` else `{m}{NBSP}min`
	end
	if seconds < 60 then
		return `{seconds}s`
	end
	if h > 0 then
		return if m > 0 then `{h}h {m}m` else `{h}h`
	end
	return if s > 0 then `{m}m {s}s` else `{m}m`
end

-- 0.256 → "26%"
function Format.percent(ratio: number, decimals: number?): string
	local d = decimals or 0
	local value = ratio * 100
	if d == 0 then
		return `{math.floor(value + 0.5)}%`
	end
	return string.format(`%.{d}f%%`, value)
end

return Format
