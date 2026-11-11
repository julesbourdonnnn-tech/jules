--!nocheck
-- Captures d'écrans hors moteur de Raise a Squishy (outil, jamais livré : Rojo ne prend que src/).
-- Démarre le VRAI client dans le harnais pour chaque appareil × langue × état, joue chaque écran
-- (tests/harness/Screens), applique la mise en page fidèle (textes mesurés) et écrit un instantané
-- JSON par écran (tests/harness/ScreenDump) : <sortie>/<appareil>-<langue>/<écran>.json, plus
-- <sortie>/manifest.json (liste des écrans et problèmes de texte vus côté Luau).
--
--   lune run tools/screens/capture -- --out /tmp/captures
--   options : --profiles tv1080,pc   --langs fr   --groups mid,fx   --screens panel.Ranch
--             --pending tests/fixtures/TextFitPending.luau  (régénère la liste des cas en attente
--             de tests/specs/TextFit_all.spec.luau à partir des problèmes vus aujourd'hui)
--             --keys-pending tests/fixtures/TextFitKeysPending.luau  (régénère la liste des clés pas
--             encore prouvées, raisons écrites à la main gardées)
-- Écrit aussi <sortie>/keys.json : chaque clé de localisation prouvée (nombre de boîtes), en échec
-- (messages) ou jamais affichée.
-- À lancer depuis la racine du projet (le harnais monte src/ depuis le dossier courant).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = require("../../tests/harness/Harness")
local Screens = require("../../tests/harness/Screens")
local ScreenDump = require("../../tests/harness/ScreenDump")
local Pending = require("../../tests/harness/TextFitPending")
local TextFitKeys = require("../../tests/harness/TextFitKeys")

local args = { out = "captures" }
do
	local i = 1
	local argv = process.args
	while i <= #argv do
		local a = argv[i]
		if string.sub(a, 1, 2) == "--" and a ~= "--" then
			local key = string.sub(a, 3)
			local value = argv[i + 1]
			if value == nil or string.sub(value, 1, 2) == "--" then
				args[key] = true
			else
				args[key] = value
				i += 1
			end
		end
		i += 1
	end
end

local function set(list)
	if type(list) ~= "string" then
		return nil
	end
	local out = {}
	for item in string.gmatch(list, "[^,]+") do
		out[item] = true
	end
	return out
end

-- lot I (matrice de nuit) : taille de texte du joueur (--text-size medium | largest : facteur 1,5 de
-- GuiService.PreferredTextSize, moteur de texte simulé et dessin) et qualité graphique (--quality
-- normal | low : réglage lowGraphics du profil)
local textSize = if type(args["text-size"]) == "string" then args["text-size"] else "medium"
local quality = if type(args.quality) == "string" then args.quality else "normal"
if textSize ~= "medium" and textSize ~= "largest" then
	error("--text-size : medium ou largest")
end
if quality ~= "normal" and quality ~= "low" then
	error("--quality : normal ou low")
end
Screens.OPTIONS = { textFactor = if textSize == "largest" then 1.5 else 1, lowGraphics = quality == "low" }

local onlyProfiles = set(args.profiles)
local onlyLangs = set(args.langs)
local onlyGroups = set(args.groups)
local screenFilter = if type(args.screens) == "string" then args.screens else nil

local function mkdir(path)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

local OUT = args.out
mkdir(OUT)

local manifest = { generated = os.date("!%Y-%m-%dT%H:%M:%SZ"), profiles = {}, screens = {}, cases = {} }
local issuesByCase = {}
local t0 = os.clock()
local count = 0

local function wanted(id)
	return screenFilter == nil or string.find(id, screenFilter, 1, true) ~= nil
end

local keyStore = TextFitKeys.new()
local lastClient = nil

local function write(dir, screenId, c, meta)
	Screens.layout(c)
	if c.Species then
		lastClient = c
	end
	TextFitKeys.collect(keyStore, c, c.profile.id, Screens)
	local rootScale = Screens.rootScale(c)
	local issues = Screens.textIssues(c)
	local data = ScreenDump.dump(c, meta, rootScale, Screens.LAYOUT_OPTIONS, { luauIssues = issues })
	fs.writeFile(dir .. "/" .. screenId .. ".json", serde.encode("json", data, false))
	count += 1
	return issues
end

for _, profile in Screens.PROFILES do
	if onlyProfiles == nil or onlyProfiles[profile.id] then
		table.insert(
			manifest.profiles,
			{ id = profile.id, label = profile.label, w = profile.w, h = profile.h }
		)
		for _, lang in Screens.LANGS do
			if onlyLangs == nil or onlyLangs[lang] then
				local folder = profile.id .. "-" .. lang
				local dir = OUT .. "/" .. folder
				mkdir(dir)
				for _, group in Screens.groups() do
					if onlyGroups == nil or onlyGroups[group.id] then
						if group.loading then
							for _, screen in group.screens do
								if wanted(screen.id) then
									local ok, c =
										pcall(Screens.bootLoading, Harness, profile, lang, screen.failed)
									if ok then
										local issues = write(dir, screen.id, c, { id = screen.id })
										issuesByCase[folder .. "/" .. screen.id] = issues
										table.insert(
											manifest.cases,
											{ folder = folder, screen = screen.id, issues = #issues }
										)
									else
										print("✗ " .. folder .. "/" .. screen.id .. " : " .. tostring(c))
									end
									Harness.disposeAll()
								end
							end
						else
							local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
							if not ok then
								print("✗ démarrage " .. folder .. "/" .. group.id .. " : " .. tostring(c))
							else
								for _, screen in Screens.expand(c, group) do
									if wanted(screen.id) then
										local shown, err = Screens.show(c, screen)
										if not shown then
											print("✗ " .. folder .. "/" .. screen.id .. " : " .. err)
										end
										local issues =
											write(dir, screen.id, c, { id = screen.id, error = err })
										issuesByCase[folder .. "/" .. screen.id] = issues
										table.insert(manifest.cases, {
											folder = folder,
											screen = screen.id,
											issues = #issues,
											error = err,
										})
									end
								end
								if #c.h.errors > 0 then
									print("  erreurs du client (" .. folder .. "/" .. group.id .. ") :")
									for _, e in c.h.errors do
										print("    " .. e)
									end
								end
							end
							Harness.disposeAll()
						end
					end
				end
				print(string.format("%-12s %4d écrans  (%.0f s)", folder, count, os.clock() - t0))
			end
		end
	end
end

local seen = {}
for _, case in manifest.cases do
	if not seen[case.screen] then
		seen[case.screen] = true
		table.insert(manifest.screens, case.screen)
	end
end
fs.writeFile(OUT .. "/manifest.json", serde.encode("json", manifest, true))

do
	local keysResult = nil
	if lastClient then
		local Localization = lastClient.Localization
		local Strings = lastClient.Strings
		keysResult = TextFitKeys.check(keyStore, Localization, Strings, function(lang, key)
			return Screens.varsFor(lastClient, key, lang)
		end)
		local nProven, nFail, nUnseen, nFamily = 0, 0, 0, 0
		for _ in keysResult.proven do
			nProven += 1
		end
		for _ in keysResult.failures do
			nFail += 1
		end
		for _ in keysResult.unseen do
			nUnseen += 1
		end
		for _ in keysResult.viaFamily do
			nFamily += 1
		end
		fs.writeFile(OUT .. "/keys.json", serde.encode("json", keysResult, true))
		print(
			string.format(
				"clés : %d prouvées (dont %d par leur famille), %d en échec, %d jamais affichées",
				nProven,
				nFamily,
				nFail,
				nUnseen
			)
		)
		if args["keys-pending"] then
			local path = if type(args["keys-pending"]) == "string"
				then args["keys-pending"]
				else "tests/fixtures/TextFitKeysPending.luau"
			local reasons = {}
			if fs.isFile(path) then
				local ok, list = pcall(function()
					return require("../../" .. string.gsub(path, "%.luau$", ""))
				end)
				if ok and type(list) == "table" then
					reasons = list
				end
			end
			-- une raison automatique (« jamais affichée », « ne tient pas », classement par les sources) est
			-- recalculée ; une raison écrite à la main est gardée
			for key, reason in reasons do
				if
					string.find(reason, "^jamais affichée par les scénarios")
					or string.find(reason, "^ne tient pas : ")
					or string.find(reason, "^%[auto%]")
				then
					reasons[key] = nil
				end
			end
			-- classement des clés jamais affichées d'après les sources (TextFitKeys.reference)
			local SPECIAL = {
				["shop.product.CoinsSmall"] = "article caché au lancement (hidden, Config/Monetization)",
				["shop.product.CoinsSmall.desc"] = "article caché au lancement (hidden, Config/Monetization)",
				["shop.product.CoinsBig"] = "article caché au lancement (hidden, Config/Monetization)",
				["shop.product.CoinsBig.desc"] = "article caché au lancement (hidden, Config/Monetization)",
				["shop.pass.SeasonPass"] = "passe caché au lancement (hidden ; jamais de piste décorative payante)",
				["shop.pass.SeasonPass.desc"] = "passe caché au lancement (hidden ; jamais de piste décorative payante)",
			}
			for key in keysResult.unseen do
				if reasons[key] == nil and TextFitKeys.usedByClient(key) then
					local reason = SPECIAL[key]
					if reason == nil then
						local how, file, prefix = TextFitKeys.reference(key, "client")
						if how == "direct" then
							reason = "[auto] affichée par le client ("
								.. file
								.. ") dans un état que les scénarios ne montrent pas encore"
						else
							reason = "[auto] clé construite par le client (préfixe « "
								.. tostring(prefix)
								.. " », "
								.. tostring(file)
								.. ") dans un état que les scénarios ne montrent pas encore"
						end
					end
					reasons[key] = reason
				end
			end
			fs.writeFile(path, TextFitKeys.renderPending(keysResult, reasons))
			print("clés en attente écrites dans " .. path)
		end
	end
end

if args.pending then
	local path = if type(args.pending) == "string" then args.pending else "tests/fixtures/TextFitPending.luau"
	fs.writeFile(path, Pending.render(issuesByCase))
	print("cas en attente écrits dans " .. path)
end

print(string.format("%d instantanés JSON dans %s (%.0f s)", count, OUT, os.clock() - t0))
-- des threads du jeu attendent encore (boucles réelles) : on sort sans les attendre
process.exit(0)
