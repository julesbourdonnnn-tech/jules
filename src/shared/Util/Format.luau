--!strict
-- Formatage des nombres et durées pour l'affichage.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 → "1.23K", 15300000 → "15.3M", 999 → "999"
function Format.abbreviate(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = tostring(math.floor(n))
		return if negative then "-" .. s else s
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
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
	text = text:gsub("%.?0+$", "")
	local s = text .. SUFFIXES[tier + 1]
	return if negative then "-" .. s else s
end

-- 1234567 → "1,234,567"
function Format.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
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

-- 90 → "1m 30s", 7200 → "2h", 45 → "45s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return `{seconds}s`
	end
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
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
