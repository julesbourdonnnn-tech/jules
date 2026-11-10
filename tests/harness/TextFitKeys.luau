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
	-- titres de la v2.0 (Mon style, lot B3, étape 3) : 66 titres dans la même case de la grille ; les
	-- écrans montrent le début, la fin et le titre « taille 1e24 », les autres sont mesurés dans ces cases
	{ id = "title", pattern = "^title%.[%w_]+$" },
	{ id = "hud.now", pattern = "^hud%.now%.[%w_]+$" },
	{ id = "hud.next", pattern = "^hud%.next%.[%w_]+$" },
	-- écran Améliorations (lot B2, étape 2) : palier et raison courte d'une carte du Conseillé (une
	-- boîte chacun, 3 cartes à l'écran : chaque palier et chaque raison y passent tour à tour)
	{ id = "upgrades.tier", pattern = "^upgrades%.tier%.[%w_]+%.%d+$" },
	{ id = "upgrades.reason", pattern = "^upgrades%.reason%.[%w_]+$" },
	-- (étape 3) raison d'un refus du serveur : la même boîte (retour de la ligne ou de la carte) les
	-- montre tour à tour ; chacune a aussi son scénario dans une ligne (groupe Screens « upgrades »)
	{ id = "upgrades.refused", pattern = "^upgrades%.refused%.[%w_]+$" },
	-- (étape 4) nom court de la famille dans la puce « Prochain achat » du HUD : une seule boîte, la
	-- famille que le Conseillé désigne (8 familles de pièces, D21)
	{ id = "upgrades.short", pattern = "^upgrades%.short%.[%w_]+$" },
	-- (lot B3, étape 5) noms des Monuments et des paliers du ranch : la carte « Nouveau : {name} » du
	-- premier passage (RanchRenderer.ElementBuilt) les montre tour à tour dans la même case ; les écrans
	-- montrent le nom le plus long de chaque langue (et le Monument 10), les autres y sont mesurés
	{ id = "monument", pattern = "^monument%.%d+$" },
	{ id = "ranchTier", pattern = "^ranchTier%.%d$" },
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
	-- repère « {_} » de UI/Text (lot B1) : une espace qui ne coupe jamais la ligne, mesurée comme
	-- l'espace insécable (lot B3, étape 3 : « Selle «{_}Biscuit{_}» » était mesuré avec ses 3 signes)
	local plain = TextFit.plain((string.gsub(text, "{_}", "\u{A0}")))
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

-- Références d'une clé dans le code (chaîne littérale "clé" ou préfixe "a.b." d'une clé construite) :
-- côté client (src/client, src/first, src/shared/Logic, src/shared/Util) ou serveur (src/server).
-- Une clé que le client ne référence pas encore (clé du contrat pour un écran à venir, texte du
-- serveur seul) n'a pas de boîte à prouver : TextFit_all l'accepte sans ligne en attente.
local sourcesCache = nil
local function loadSources()
	if sourcesCache then
		return sourcesCache
	end
	local fs = require("@lune/fs")
	local sources = { client = {}, server = {} }
	local function walk(dir, side)
		if not fs.isDir(dir) then
			return
		end
		for _, entry in fs.readDir(dir) do
			local full = dir .. "/" .. entry
			if fs.isDir(full) then
				walk(full, side)
			elseif string.match(entry, "%.luau$") and full ~= "src/shared/Localization/Strings.luau" then
				table.insert(
					sources[side],
					{ file = (string.gsub(full, "^src/", "")), text = fs.readFile(full) }
				)
			end
		end
	end
	-- l'interface (src/client, src/first) et la logique partagée qu'elle appelle pour écrire un texte
	-- (Logic : BigNumber, Formulas ; Util : Format). Pas Config : une clé citée par une configuration
	-- du contrat n'est pas encore affichée par un écran
	walk("src/client", "client")
	walk("src/first", "client")
	walk("src/shared/Logic", "client")
	walk("src/shared/Util", "client")
	walk("src/server", "server")
	for _, side in sources do
		table.sort(side, function(a, b)
			return a.file < b.file
		end)
	end
	sourcesCache = sources
	return sources
end

-- (comment, fichier) : "direct" | "prefix" | nil, côté "client" ou "server"
function TextFitKeys.reference(key: string, side: string): (string?, string?, string?)
	local sources = loadSources()[side]
	local prefix = string.match(key, "^(.*%.)[^%.]+$")
	for _, src in sources do
		if string.find(src.text, '"' .. key .. '"', 1, true) then
			return "direct", src.file, nil
		end
	end
	if prefix then
		for _, src in sources do
			if string.find(src.text, '"' .. prefix .. '"', 1, true) then
				return "prefix", src.file, prefix
			end
		end
	end
	return nil, nil, nil
end

-- La clé est-elle utilisée par le client (et donc affichée quelque part) ?
function TextFitKeys.usedByClient(key: string): boolean
	return TextFitKeys.reference(key, "client") ~= nil
end

-- Source Luau de la liste des clés en attente (outil : capture -- --keys-pending) ; `reasons`
-- (facultatif) : raisons déjà écrites à la main, gardées
function TextFitKeys.renderPending(result, reasons)
	reasons = reasons or {}
	local keys = {}
	for key in result.unseen do
		if TextFitKeys.usedByClient(key) then
			table.insert(keys, key)
		end
	end
	for key in result.failures do
		table.insert(keys, key)
	end
	table.sort(keys)
	local lines = {
		"--!nocheck",
		"-- Clés EN ATTENTE de tests/specs/TextFit_all.spec.luau (partie « clés ») : clés pas encore",
		"-- prouvées dans les deux langues, chacune avec sa raison (les clés que le client n'utilise pas",
		"-- encore — contrat d'un écran à venir, texte du serveur seul — sont acceptées sans ligne). Générée par",
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
