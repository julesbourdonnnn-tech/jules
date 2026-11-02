--!nocheck
-- TextFitKeys : chaque clé de localisation, en anglais ET en français, mesurée dans CHAQUE boîte où
-- le jeu l'affiche (tests/specs/TextFit_all.spec.luau, outil tools/screens/capture.luau).
--
-- 1. Pendant les scénarios (tests/harness/Screens), TextFitKeys.collect(store, c, profile) relève
--    les boîtes de texte de l'écran reliées à une clé (Screens.keyBoxes : la clé dont la traduction a
--    produit exactement le texte affiché) : taille de la boîte (px de mise en page), police,
--    TextScaled, bornes, retours à la ligne, échelle (UIScale), variables utilisées.
-- 2. TextFitKeys.check(store, Localization, Strings) mesure ensuite le texte de la clé dans les DEUX
--    langues (avec les variables vues à l'écran) dans chacune de ses boîtes : il doit tenir sans
--    déborder, sans mot coupé, sans « … », à 28 px de référence au moins (× échelle de Root).
-- 3. Une clé jamais vue à l'écran est prouvée par sa FAMILLE (FAMILIES : clés interchangeables dans
--    le même emplacement, ex. toutes les clés feedback.* passent par l'emplacement de message) :
--    mesurée dans les boîtes de ses sœurs vues à l'écran, avec les variables les plus longues
--    plausibles (Screens.varsFor). Sinon elle n'est pas prouvée : elle doit être dans
--    tests/fixtures/TextFitKeysPending.luau avec une raison.
--
--   local store = TextFitKeys.new()
--   TextFitKeys.collect(store, c, profileId)        -- à chaque écran (après Screens.layout)
--   local r = TextFitKeys.check(store, Localization, Strings, varsFor)
--   r.failures[key] = { messages }  ; r.proven[key] = nombre de boîtes ; r.unseen[key] = true

local TextFit = require("./TextFit")
local Metrics = require("./TextMetrics")

local TextFitKeys = {}

-- Familles de clés interchangeables dans un même emplacement (motifs Lua) ; une clé jamais vue est
-- mesurée dans les boîtes de ses sœurs vues à l'écran
TextFitKeys.FAMILIES = {
	{ id = "species", pattern = "^species%.[%w_]+$" },
	{ id = "mutation", pattern = "^mutation%.[%w_]+$" },
	{ id = "rarity", pattern = "^rarity%.[%w_]+$" },
	{ id = "feedback", pattern = "^feedback%.[%w_%.]+$" },
	{ id = "banner", pattern = "^banner%.[%w_]+$" },
	{ id = "cosmetic.title", pattern = "^cosmetic%.title%.[%w_]+$" },
	{ id = "cosmetic.saddle", pattern = "^cosmetic%.saddle%.[%w_]+$" },
	{ id = "cosmetic.trail", pattern = "^cosmetic%.trail%.[%w_]+$" },
	{ id = "cosmetic.theme", pattern = "^cosmetic%.theme%.[%w_]+$" },
	{ id = "cosmetic.emote", pattern = "^cosmetic%.emote%.[%w_]+$" },
	{ id = "cosmetic.outfit", pattern = "^cosmetic%.outfit%.[%w_]+$" },
	{ id = "cosmetic.flag", pattern = "^cosmetic%.flag%.[%w_]+$" },
	{ id = "hud.now", pattern = "^hud%.now%.[%w_]+$" },
	{ id = "hud.next", pattern = "^hud%.next%.[%w_]+$" },
	-- pas de famille « prompt » : la plaque d'une invite est taillée sur SON mot (WorldText), chaque
	-- verbe a son scénario
}

function TextFitKeys.familyOf(key: string): string?
	for _, f in TextFitKeys.FAMILIES do
		if string.match(key, f.pattern) then
			return f.id
		end
	end
	return nil
end

function TextFitKeys.new()
	return { boxes = {}, seen = {} }
end

local function round(x)
	return math.floor(x * 10 + 0.5) / 10
end

-- Boîtes de l'écran courant (Screens.layout déjà appliqué) ajoutées au relevé
function TextFitKeys.collect(store, c, profileId: string, screens)
	local rootScale = c.Root.scale()
	for _, kb in screens.keyBoxes(c) do
		local b = kb.box
		local id = table.concat({
			profileId,
			c.lang,
			b.path,
			tostring(round(b.w)),
			tostring(round(b.h)),
			tostring(b.minS),
			tostring(b.maxS),
			tostring(b.size),
		}, "|")
		local list = store.boxes[kb.key]
		if list == nil then
			list = {}
			store.boxes[kb.key] = list
		end
		if list[id] == nil then
			b.profile = profileId
			b.rootScale = rootScale
			b.lang = c.lang
			list[id] = { box = b, vars = kb.vars }
		end
		store.seen[kb.key] = true
	end
end

-- Mesure d'un texte dans une boîte relevée ; liste de problèmes (vide : il tient)
function TextFitKeys.measure(text: string, box): { string }
	local issues = {}
	local plain = TextFit.plain(text)
	if string.gsub(plain, "%s", "") == "" then
		return issues
	end
	local font = box.font
	local size, fitsScaled
	if box.scaled then
		size, fitsScaled =
			TextFit.scaledSize(plain, font, box.w, box.h, box.wrapped, box.minS, box.maxS, box.lh)
	else
		size = math.clamp(box.size or 14, box.minS or 1, math.max(box.minS or 1, box.maxS or 100))
		fitsScaled = true
	end
	local lines, split, widths = TextFit.lines(plain, font, size, if box.wrapped then box.w else nil)
	local maxW = 0
	for _, w in widths do
		maxW = math.max(maxW, w)
	end
	local height = #lines * size * (box.lh or 1)
	local overflow = not fitsScaled or maxW > box.w + 0.5 or height > box.h + math.max(1, 0.2 * size)
	if overflow then
		if box.trunc ~= nil and box.trunc ~= "None" then
			table.insert(issues, string.format("« … » à %.0f px", size))
		else
			table.insert(
				issues,
				string.format(
					"déborde à %.0f px (texte %.0f × %.0f, boîte %.0f × %.0f)",
					size,
					maxW,
					height,
					box.w,
					box.h
				)
			)
		end
	end
	if split then
		table.insert(issues, string.format("mot coupé à %.0f px", size))
	end
	for i = 2, #lines do
		local prev = string.gsub(lines[i - 1], "%s+$", "")
		local cur = string.gsub(lines[i], "^%s+", "")
		if string.find(prev, "%d$") and TextFit.startsWithUnit(cur) then
			table.insert(
				issues,
				"unité séparée de son nombre (« "
					.. string.sub(prev, -6)
					.. " » / « "
					.. string.sub(cur, 1, 6)
					.. " »)"
			)
			break
		end
	end
	if not box.deco then
		local real = size * (box.k or 1)
		local need = TextFit.MIN_READABLE * (box.rootScale or 1)
		if real < need - 0.01 then
			table.insert(issues, string.format("%.1f px réels < %.1f px", real, need))
		end
	end
	return issues
end

-- Vérification de toutes les clés. varsFor(lang, key) : variables les plus longues plausibles (clés
-- prouvées par leur famille). Rend { proven, failures, unseen, byFamily }
function TextFitKeys.check(store, Localization, Strings, varsFor)
	local result = { proven = {}, failures = {}, unseen = {}, viaFamily = {} }
	local familyBoxes = {}
	for key, list in store.boxes do
		local fam = TextFitKeys.familyOf(key)
		if fam then
			familyBoxes[fam] = familyBoxes[fam] or {}
			for id, entry in list do
				familyBoxes[fam][id] = entry
			end
		end
	end
	local keys = {}
	for key in Strings.en do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local list = store.boxes[key]
		local viaFamily = false
		if list == nil then
			local fam = TextFitKeys.familyOf(key)
			if fam and familyBoxes[fam] then
				list = familyBoxes[fam]
				viaFamily = true
			end
		end
		if list == nil then
			result.unseen[key] = true
		else
			local messages = {}
			local n = 0
			-- boîtes groupées par emplacement (appareil, chemin) : dans chaque langue, d'abord les
			-- boîtes relevées DANS cette langue (une boîte taillée sur son texte change avec la langue),
			-- sinon celles de l'autre langue (mesure croisée, prudente)
			local groups = {}
			for id, entry in list do
				local slot = entry.box.profile .. "|" .. entry.box.path
				groups[slot] = groups[slot] or {}
				table.insert(groups[slot], { id = id, entry = entry })
			end
			local slots = {}
			for slot in groups do
				table.insert(slots, slot)
			end
			table.sort(slots)
			for _, slot in slots do
				local entries = groups[slot]
				table.sort(entries, function(a, b)
					return a.id < b.id
				end)
				n += 1
				for _, lang in { "en", "fr" } do
					local same = {}
					for _, e in entries do
						if e.entry.box.lang == lang then
							table.insert(same, e.entry)
						end
					end
					if #same == 0 then
						for _, e in entries do
							table.insert(same, e.entry)
						end
					end
					for _, entry in same do
						local vars = if viaFamily then varsFor(lang, key) else entry.vars
						local text = Localization.get(lang, key, vars)
						for _, issue in TextFitKeys.measure(text, entry.box) do
							table.insert(
								messages,
								string.format(
									"[%s %s] %s — « %s » : %s",
									entry.box.profile,
									lang,
									entry.box.path,
									string.sub(text, 1, 60),
									issue
								)
							)
						end
					end
				end
			end
			if #messages > 0 then
				result.failures[key] = messages
			else
				result.proven[key] = n
				if viaFamily then
					result.viaFamily[key] = true
				end
			end
		end
	end
	return result
end

-- Source Luau de la liste des clés en attente (outil : capture -- --keys-pending) ; `reasons`
-- (facultatif) : raisons déjà écrites à la main, gardées
function TextFitKeys.renderPending(result, reasons)
	reasons = reasons or {}
	local keys = {}
	for key in result.unseen do
		table.insert(keys, key)
	end
	for key in result.failures do
		table.insert(keys, key)
	end
	table.sort(keys)
	local lines = {
		"--!nocheck",
		"-- Clés EN ATTENTE de tests/specs/TextFit_all.spec.luau (partie « clés ») : clés pas encore",
		"-- prouvées dans les deux langues, chacune avec sa raison. Générée par",
		"-- « lune run tools/screens/capture -- --out <dossier> --keys-pending » puis relue à la main.",
		"-- Une clé prouvée encore listée fait échouer la spec : retirer sa ligne. Ne jamais ajouter une",
		"-- clé pour masquer un texte qui ne tient pas : corriger l'interface ou raccourcir le texte.",
		"return {",
	}
	for _, key in keys do
		local reason = reasons[key]
		if reason == nil then
			reason = if result.unseen[key]
				then "jamais affichée par les scénarios (tests/harness/Screens) : à couvrir"
				else "ne tient pas : " .. result.failures[key][1]
		end
		table.insert(lines, string.format('\t["%s"] = "%s",', key, (string.gsub(reason, '[\\"]', "\\%0"))))
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

TextFitKeys.metricsSize = Metrics.size

return TextFitKeys
