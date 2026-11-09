--!strict
-- Contrat v2.0, règle 18 du GDD §10.8 (« aucun symbole hors police ») : chaque caractère de chaque
-- clé de Localization/Strings, en anglais ET en français, existe dans la table `cmap` des deux polices
-- du jeu, FredokaOne (texte) et LuckiestGuy (tampons, titres des bannières et des cartes, puce
-- d'action spéciale) : n'importe quelle clé peut être posée dans l'une ou l'autre (GDD §10.1 v2.0),
-- donc la règle vaut pour les deux. Les fichiers de police sont rangés dans assets/fonts/ (fichiers
-- de TEST seulement, jamais dans une place construite par Rojo) avec leur licence : FredokaOne sous
-- SIL Open Font License 1.1, LuckiestGuy sous Apache License 2.0 (Google Fonts, dossier « apache »),
-- téléchargés de fonts.gstatic.com le 3 novembre 2026 (docs/04 §27.13, décision C19).
-- Le jeu de base (v1.3) a une liste FERMÉE d'exceptions qui ne fait que rétrécir : chaque ligne nomme
-- la clé, les caractères hors police et le paquet v2.0 qui la retire (icône dessinée ou mot, note
-- INT-V2-GLYPHS) ; une exception devenue inutile fait échouer la spec (on la retire de la liste).
-- Aucune clé v2.0 n'a d'exception.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

type FontSpec = {
	file: string,
	licence: string,
	licenceMarks: { string },
	sha256: string,
}

type Exception = {
	chars: string, -- caractères hors police de la clé, dans les deux langues
	owner: string, -- paquet v2.0 qui retire l'exception
}

local FONT_DIR = "assets/fonts/"

local FONTS: { [string]: FontSpec } = {
	FredokaOne = {
		file = "FredokaOne.ttf",
		licence = "FredokaOne-OFL.txt",
		licenceMarks = { "SIL Open Font License, Version 1.1", 'Reserved Font Name "Fredoka"' },
		sha256 = "6ac3a683c0a280a15ddc7c1a39c47b60ac4448c3273d79d7112f83a95e8b3d03",
	},
	LuckiestGuy = {
		file = "LuckiestGuy.ttf",
		licence = "LuckiestGuy-LICENSE.txt",
		licenceMarks = { "Apache License", "Version 2.0, January 2004" },
		sha256 = "47f7d9fbebf8b0f6d5e83e234b9fdb198340f879f6ab5679a41871c07d2d8f60",
	},
}

local FONT_ORDER = { "FredokaOne", "LuckiestGuy" }

-- Exceptions du jeu de base (clés v1.3 dessinées aujourd'hui en GothamBold ou avec un symbole écrit).
-- « ★ », « ♥ », « ← », « ≈ » : symboles absents des deux polices, à remplacer par une icône dessinée
-- (règle 18) ; U+00A0 (espace insécable) : absente de FredokaOne, dessinée blanche par le repli du
-- moteur mais d'une largeur qui n'est pas celle de la police ; remplacée par une espace ordinaire
-- au lot B1 (passage du texte courant à FredokaOne), avec TextFit_all reprouvé : ses 13 clés et les
-- 2 « ★ » (common.stars, celebrate.star : étoile dessinée, repère « {*} » de UI/Text) sont sorties de
-- la liste au lot B1 (étape 2) ; « ♥ » de hud.twins (cœur dessiné devant le nombre) et « ≈ » de
-- hud.queue.next / hud.queue.place (le mot « about » / « environ ») au lot B2 (étape 4, D18, D19,
-- journal B2-48) ; les 4 dernières au lot B3 (étape 1, D17, journal B3-6) : « ★ » de panel.dex.starBadge
-- (étoile dessinée, repère « {*} »), « ♥ » de panel.ranch.twins (le mot « Twins » / « Jumeaux »), « ← »
-- de settings.emoteLeft (les mots « D-pad left » / « croix gauche »), « ≈ » de panel.shop.coinsAmount
-- (le mot « about » / « environ »). La liste est vide : toute clé du jeu de base tient dans les polices.
local BASE_EXCEPTIONS: { [string]: Exception } = {}

-- Les formateurs de nombres et de durées écrivent eux aussi des caractères dans les étiquettes
-- (variables {x} des clés) : même règle, avec leur propre liste FERMÉE d'exceptions du jeu de base,
-- qui ne fait que rétrécir (note INT-V2-GLYPHS, d). « formateur » = module qui écrit le caractère.
-- U+202F (espace fine insécable) : absente des deux polices ; U+00A0 : absente de FredokaOne ;
-- « ∞ » (±inf, valeur hostile seulement) : absent des deux polices.
local NNBSP = utf8.char(0x202F)
local FORMATTER_EXCEPTIONS: { [string]: Exception } = {
	BigNumber = { chars = "", owner = "A1" }, -- U+202F et « ∞ » retirés (lot A1, INT-V2-GLYPHS d)
	Format = { chars = "", owner = "B1" }, -- U+00A0 et « ∞ » retirés (lot B1, INT-V2-GLYPHS d)
}

local V2_MARKER = "-- Contrat v2.0 (GDD v2.0, Annexe B"

-- Lecture d'une table `cmap` TrueType (formats 4 et 12, sous-tables Unicode : plateforme 0, ou
-- plateforme 3 avec encodage 1 ou 10). Rend l'ensemble des points de code qui ont un glyphe (≠ 0).
-- Toute lecture hors du fichier est une erreur (fichier tronqué ou qui n'est pas une police).
local function readCmap(data: string): { [number]: boolean }
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
	local cmapOffset: number? = nil
	for i = 0, u16(4) - 1 do
		local record = 12 + i * 16
		if string.sub(data, record + 1, record + 4) == "cmap" then
			cmapOffset = u32(record + 8)
		end
	end
	assert(cmapOffset ~= nil, "aucune table cmap")
	local base: number = cmapOffset
	local out: { [number]: boolean } = {}
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

local function loadFonts(): { [string]: { [number]: boolean } }
	local out = {}
	for name, font in FONTS do
		out[name] = readCmap(fs.readFile(FONT_DIR .. font.file))
	end
	return out
end

-- Caractères d'un texte, sans les variables {x} (remplies par les formateurs : chiffres, noms)
local function charsOf(text: string): { number }
	local stripped = string.gsub(text, "{%w+}", "")
	local out = {}
	for _, code in utf8.codes(stripped) do
		table.insert(out, code)
	end
	return out
end

local function hex(code: number): string
	return string.format("U+%04X", code)
end

return function(T: any)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function strings(): { [string]: { [string]: string } }
		local h = Harness.new()
		return h:require("ReplicatedStorage.Shared.Localization.Strings")
	end

	describe("Contrat v2 › Polices du jeu (assets/fonts, fichiers de test)", function()
		it("FredokaOne et LuckiestGuy rangées avec leur licence ; fichiers exacts (empreinte)", function()
			for _, name in FONT_ORDER do
				local font = FONTS[name]
				expect({ name = name, ttf = fs.isFile(FONT_DIR .. font.file) }).toEqual({
					name = name,
					ttf = true,
				})
				expect({ name = name, licence = fs.isFile(FONT_DIR .. font.licence) }).toEqual({
					name = name,
					licence = true,
				})
				local licence = fs.readFile(FONT_DIR .. font.licence)
				for _, mark in font.licenceMarks do
					expect({ name = name, mark = mark, found = string.find(licence, mark, 1, true) ~= nil }).toEqual({
						name = name,
						mark = mark,
						found = true,
					})
				end
				local data = fs.readFile(FONT_DIR .. font.file)
				expect({ name = name, sha256 = serde.hash("sha256", data) }).toEqual({
					name = name,
					sha256 = font.sha256,
				})
				-- la police nomme sa famille dans sa table `name` (UTF-16 BE)
				local family = string.gsub(name, "(%u)", " %1")
				family = string.sub(family, 2)
				local utf16 = string.gsub(family, ".", function(c)
					return "\0" .. c
				end)
				expect({ name = name, family = string.find(data, utf16, 1, true) ~= nil }).toEqual({
					name = name,
					family = true,
				})
			end
		end)

		it("table cmap lue : ASCII imprimable et lettres françaises dans les deux polices", function()
			local cmaps = loadFonts()
			local french = "àâçéèêëîïôûùüÿœæÀÂÇÉÈÊËÎÏÔÛÙÜŒÆ«»’…·×" -- Ÿ (U+0178) : absente de FredokaOne
			for _, name in FONT_ORDER do
				local missing = {}
				for code = 0x20, 0x7E do
					if not cmaps[name][code] then
						table.insert(missing, hex(code))
					end
				end
				for _, code in utf8.codes(french) do
					if not cmaps[name][code] then
						table.insert(missing, hex(code))
					end
				end
				expect({ name = name, missing = missing }).toEqual({ name = name, missing = {} })
			end
		end)

		it(
			"jamais livrées : aucun projet Rojo ne range assets/, aucun fichier de police dans src/",
			function()
				for _, project in { "default.project.json", "tests/engine.project.json" } do
					local function walk(node: any, path: string)
						if type(node) ~= "table" then
							return
						end
						local source = node["$path"]
						if type(source) == "string" then
							expect({
								project = project,
								at = path,
								path = source,
								assets = string.find(source, "assets") ~= nil,
							}).toEqual({
								project = project,
								at = path,
								path = source,
								assets = false,
							})
						end
						for key, child in node do
							if type(key) == "string" and string.sub(key, 1, 1) ~= "$" then
								walk(child, path .. "/" .. key)
							end
						end
					end
					local decoded = serde.decode("json", fs.readFile(project))
					walk(decoded.tree, "")
				end
				local fontsInSrc = {}
				local function scan(dir: string)
					for _, entry in fs.readDir(dir) do
						local full = dir .. "/" .. entry
						if fs.isDir(full) then
							scan(full)
						elseif
							string.find(string.lower(entry), "%.[ot]tf$")
							or string.find(string.lower(entry), "%.woff2?$")
						then
							table.insert(fontsInSrc, full)
						end
					end
				end
				scan("src")
				expect(fontsInSrc).toEqual({})
			end
		)
	end)

	describe("Contrat v2 › Règle 18 : aucun symbole hors police (GDD §10.8)", function()
		it(
			"chaque clé EN et FR n'utilise que des caractères de la cmap de FredokaOne et de LuckiestGuy",
			function()
				local cmaps = loadFonts()
				local S = strings()
				local offenders = {}
				for _, lang in { "en", "fr" } do
					for key, text in S[lang] do
						local exception = BASE_EXCEPTIONS[key]
						for _, code in charsOf(text) do
							local allowed = exception ~= nil
								and string.find(exception.chars, utf8.char(code), 1, true) ~= nil
							if not allowed then
								for _, name in FONT_ORDER do
									if not cmaps[name][code] then
										table.insert(
											offenders,
											lang .. " " .. key .. " : " .. hex(code) .. " absent de " .. name
										)
									end
								end
							end
						end
					end
				end
				table.sort(offenders)
				expect(offenders).toEqual({})
			end
		)

		it("exceptions du jeu de base : liste fermée, clés v1.3 seulement, aucune périmée", function()
			local cmaps = loadFonts()
			local S = strings()
			local source = fs.readFile("src/shared/Localization/Strings.luau")
			-- lignes des clés v2.0 : après le marqueur du contrat v2.0 dans chaque langue
			local v2Keys: { [string]: boolean } = {}
			local inV2 = false
			for line in string.gmatch(source, "[^\n]+") do
				if string.find(line, V2_MARKER, 1, true) then
					inV2 = true
				elseif string.find(line, "^Strings%.%a+ = {") or string.find(line, "^}") then
					inV2 = false
				elseif inV2 then
					local key = string.match(line, '^%s*%["([^"]+)"%]%s*=')
					if key then
						v2Keys[key] = true
					end
				end
			end
			local markers, from = 0, 1
			while true do
				local at = string.find(source, V2_MARKER, from, true)
				if at == nil then
					break
				end
				markers += 1
				from = at + #V2_MARKER
			end
			expect(markers).toBe(2) -- un marqueur par langue
			local v2Count = 0
			for _ in v2Keys do
				v2Count += 1
			end
			expect(v2Count >= 400).toBe(true)
			local known = { B1 = true, B2 = true, B3 = true }
			for key, exception in BASE_EXCEPTIONS do
				expect({ key = key, v2 = v2Keys[key] == true }).toEqual({ key = key, v2 = false })
				expect({ key = key, owner = known[exception.owner] == true }).toEqual({
					key = key,
					owner = true,
				})
				-- chaque caractère de l'exception est utilisé par la clé et manque à une police au moins
				for _, code in utf8.codes(exception.chars) do
					local used = false
					for _, lang in { "en", "fr" } do
						local text = S[lang][key]
						expect({ key = key, lang = lang, exists = text ~= nil }).toEqual({
							key = key,
							lang = lang,
							exists = true,
						})
						if text and string.find(text, utf8.char(code), 1, true) then
							used = true
						end
					end
					local outside = not cmaps.FredokaOne[code] or not cmaps.LuckiestGuy[code]
					expect({ key = key, char = hex(code), used = used, outside = outside }).toEqual({
						key = key,
						char = hex(code),
						used = true,
						outside = true,
					})
				end
			end
		end)

		it(
			"formateurs (Logic/BigNumber, Util/Format), EN et FR, de 0 à 1e300 : caractères des deux polices, exceptions fermées",
			function()
				local cmaps = loadFonts()
				local h = Harness.new()
				local BigNumber = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
				local Format = h:require("ReplicatedStorage.Shared.Util.Format")
				-- valeurs : chaque palier de suffixe (1e0 … 1e300), ses bords (999…, 1,5 ×), négatifs,
				-- et les valeurs hostiles (±inf, NaN, −0) que les formateurs acceptent sans erreur
				local nan = math.huge * 0
				local values =
					{ 0, -0, 7, 999, 1000, 1234, 9999, 10000, 12345, 999999, nan, math.huge, -math.huge }
				for e = 3, 300, 3 do
					table.insert(values, 10 ^ e)
					table.insert(values, 1.5 * 10 ^ e)
					table.insert(values, 10 ^ e - 1)
					table.insert(values, -4.56 * 10 ^ e)
				end
				local durations = { 0, 5, 59, 60, 61, 90, 600, 3599, 3600, 3725, 7200, 18720, 57600, 86399 }
				local outputs: { [string]: { string } } = { BigNumber = {}, Format = {} }
				for _, lang in { "en", "fr" } do
					for _, n in values do
						local short, words = BigNumber.words(n, lang)
						table.insert(outputs.BigNumber, BigNumber.abbreviate(n, lang))
						table.insert(outputs.BigNumber, BigNumber.full(n, lang))
						table.insert(outputs.BigNumber, short)
						table.insert(outputs.BigNumber, words)
						table.insert(outputs.Format, Format.abbreviate(n, lang))
						table.insert(outputs.Format, Format.commas(n, lang))
					end
					for _, s in durations do
						table.insert(outputs.Format, Format.duration(s, lang))
					end
				end
				for _, s in durations do
					table.insert(outputs.Format, Format.clock(s))
				end
				for _, ratio in { 0, 0.05, 0.256, 1, 1.5, 12.345 } do
					table.insert(outputs.Format, Format.percent(ratio))
					table.insert(outputs.Format, Format.percent(ratio, 1))
				end
				local offenders = {}
				local used: { [string]: { [number]: boolean } } = { BigNumber = {}, Format = {} }
				for formatter, texts in outputs do
					local exception = FORMATTER_EXCEPTIONS[formatter]
					for _, text in texts do
						expect({ formatter = formatter, utf8 = utf8.len(text) ~= nil }).toEqual({
							formatter = formatter,
							utf8 = true,
						})
						for _, code in utf8.codes(text) do
							used[formatter][code] = true
							if not string.find(exception.chars, utf8.char(code), 1, true) then
								for _, name in FONT_ORDER do
									if not cmaps[name][code] then
										offenders[formatter .. " : " .. hex(code) .. " absent de " .. name] =
											true
									end
								end
							end
						end
					end
				end
				local list = {}
				for line in offenders do
					table.insert(list, line)
				end
				table.sort(list)
				expect(list).toEqual({})
				-- liste fermée : chaque caractère d'exception est vraiment écrit et vraiment hors police
				for formatter, exception in FORMATTER_EXCEPTIONS do
					for _, code in utf8.codes(exception.chars) do
						local outside = not cmaps.FredokaOne[code] or not cmaps.LuckiestGuy[code]
						expect({
							formatter = formatter,
							char = hex(code),
							used = used[formatter][code] == true,
							outside = outside,
						}).toEqual({
							formatter = formatter,
							char = hex(code),
							used = true,
							outside = true,
						})
					end
				end
			end
		)

		it(
			"les icônes de la règle 18 ne sont jamais écrites dans une clé hors des exceptions du jeu de base (→ ✓ ★ ∞ ↺ □ △ ○ ✕)",
			function()
				local S = strings()
				local banned =
					{ "→", "✓", "★", "∞", "↺", "□", "△", "○", "✕", "♥", "≈", "←" }
				local offenders = {}
				for _, lang in { "en", "fr" } do
					for key, text in S[lang] do
						if BASE_EXCEPTIONS[key] == nil then
							for _, ch in banned do
								if string.find(text, ch, 1, true) then
									table.insert(offenders, lang .. " " .. key .. " : " .. ch)
								end
							end
						end
					end
				end
				table.sort(offenders)
				expect(offenders).toEqual({})
			end
		)
	end)
end
