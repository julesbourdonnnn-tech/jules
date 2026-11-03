--!nocheck
-- FontCmap (lot B1) : table `cmap` des deux polices du jeu rangées dans assets/fonts/ (fichiers de
-- test, docs/04 §27.0, décision C19), pour vérifier qu'un texte produit par le client (sorties de
-- UI/Format, textes témoins du panneau TextProbe) n'utilise que des caractères dessinés par
-- FredokaOne ET LuckiestGuy (règle 18 du GDD §10.8). Même lecture que Contract_glyphs.spec (formats
-- 4 et 12, sous-tables Unicode) ; toute lecture hors du fichier est une erreur.
--
--   local cmaps = FontCmap.load()                    -- { FredokaOne = { [code] = true }, LuckiestGuy = … }
--   local missing = FontCmap.missing(cmaps, "×1,175") -- { "U+00A0 (FredokaOne)" … } ou {}

local fs = require("@lune/fs")

local FontCmap = {}

FontCmap.DIR = "assets/fonts/"
FontCmap.FILES = { FredokaOne = "FredokaOne.ttf", LuckiestGuy = "LuckiestGuy.ttf" }
FontCmap.ORDER = { "FredokaOne", "LuckiestGuy" }

function FontCmap.read(data: string): { [number]: boolean }
	local size = #data
	local function u16(offset: number): number
		assert(offset >= 0 and offset + 2 <= size, "police tronquée (u16 à " .. offset .. ")")
		return (string.unpack(">I2", data, offset + 1))
	end
	local function u32(offset: number): number
		assert(offset >= 0 and offset + 4 <= size, "police tronquée (u32 à " .. offset .. ")")
		return (string.unpack(">I4", data, offset + 1))
	end
	local version = u32(0)
	assert(version == 0x00010000 or version == 0x74727565, "pas une police TrueType")
	local cmapOffset = nil
	for i = 0, u16(4) - 1 do
		local record = 12 + i * 16
		if string.sub(data, record + 1, record + 4) == "cmap" then
			cmapOffset = u32(record + 8)
		end
	end
	assert(cmapOffset ~= nil, "aucune table cmap")
	local base = cmapOffset
	local out = {}
	local subtables = 0
	for i = 0, u16(base + 2) - 1 do
		local record = base + 4 + i * 8
		local platform, encoding = u16(record), u16(record + 2)
		local sub = base + u32(record + 4)
		local unicode = platform == 0 or (platform == 3 and (encoding == 1 or encoding == 10))
		local format = u16(sub)
		if unicode and format == 4 then
			subtables += 1
			local segX2 = u16(sub + 6)
			local ends = sub + 14
			local starts = ends + segX2 + 2
			local deltas = starts + segX2
			local ranges = deltas + segX2
			for s = 0, segX2 // 2 - 1 do
				local first, last = u16(starts + 2 * s), u16(ends + 2 * s)
				local delta, rangeOffset = u16(deltas + 2 * s), u16(ranges + 2 * s)
				for code = first, last do
					if code ~= 0xFFFF then
						local glyph
						if rangeOffset == 0 then
							glyph = (code + delta) % 65536
						else
							glyph = u16(ranges + 2 * s + rangeOffset + 2 * (code - first))
							if glyph ~= 0 then
								glyph = (glyph + delta) % 65536
							end
						end
						if glyph ~= 0 then
							out[code] = true
						end
					end
				end
			end
		elseif unicode and format == 12 then
			subtables += 1
			for g = 0, u32(sub + 12) - 1 do
				local group = sub + 16 + g * 12
				local first, last, glyph = u32(group), u32(group + 4), u32(group + 8)
				for code = first, last do
					if glyph + (code - first) ~= 0 then
						out[code] = true
					end
				end
			end
		end
	end
	assert(subtables > 0, "aucune sous-table Unicode (formats 4 ou 12)")
	return out
end

local cache = nil

function FontCmap.load()
	if cache == nil then
		cache = {}
		for name, file in FontCmap.FILES do
			cache[name] = FontCmap.read(fs.readFile(FontCmap.DIR .. file))
		end
	end
	return cache
end

-- Caractères de `text` absents d'au moins une des deux polices (« U+00A0 (FredokaOne) »…) ;
-- « \n » permis (retour à la ligne, jamais dessiné)
function FontCmap.missing(cmaps, text: string): { string }
	local out = {}
	for _, code in utf8.codes(text) do
		if code ~= 10 then
			for _, name in FontCmap.ORDER do
				if not cmaps[name][code] then
					table.insert(out, string.format("U+%04X (%s)", code, name))
				end
			end
		end
	end
	return out
end

return FontCmap
