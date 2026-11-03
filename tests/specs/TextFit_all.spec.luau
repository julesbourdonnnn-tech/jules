--!nocheck
-- TextFit_all (outil d'écrans, tools/screens/README.md) : tous les textes de tous les écrans tiennent,
-- et chaque clé de localisation tient, en anglais ET en français, dans chaque boîte où elle s'affiche.
--
-- 1. Écrans : pour chaque appareil (PS5 TV 1920 × 1080, 3840 × 2160, 1280 × 720, PC 1366 × 768) ×
--    langue (fr, en) × écran (tests/harness/Screens : chargement, accueil pas à pas, HUD dans chaque
--    mode — Cozy, Rush, MEGA, Jelly Moon, Golden, fête, sieste —, invites, menu, chaque panneau et
--    chaque onglet, fiches, cartes, carte du choix, écran de retour, bannières, messages, très grands
--    nombres jusqu'à 999 Dc et 1,23e36), la mise en page FIDÈLE (Layout en mode fidèle + TextFit :
--    vraies largeurs des polices, règles TextScaled / TextWrapped / TextTruncate de Roblox) ne doit
--    montrer : aucun texte qui déborde (overflow), aucun mot coupé (splitWord), aucun « … » qui cache
--    un nombre ou un mot (truncated), aucun texte sous 28 px de référence × échelle de Root (small),
--    aucune ponctuation seule sur sa ligne (orphan), aucune clé brute, variable « {x} », « ? » ni
--    texte jamais posé.
-- 2. Clés : chaque clé de Localization/Strings mesurée dans les deux langues dans chaque boîte où un
--    scénario l'a affichée (tests/harness/TextFitKeys), ou dans les boîtes de sa famille ; une clé
--    utilisée par le client mais jamais affichée est listée avec sa raison dans
--    tests/fixtures/TextFitKeysPending.luau ; une clé que le client n'utilise pas encore (contrat d'un
--    écran à venir) est acceptée et comptée.
-- Cas EN ATTENTE (problèmes présents aujourd'hui) : tests/fixtures/TextFitPending.luau (écrans) et
-- TextFitKeysPending.luau (clés). Un cas listé est vérifié EXACTEMENT (mêmes problèmes) : un problème
-- NOUVEAU fait échouer, un problème listé mais disparu aussi (réparé : retirer sa ligne).

local Screens = require("../harness/Screens")
local Pending = require("../harness/TextFitPending")
local TextFitKeys = require("../harness/TextFitKeys")
local LIST = require("../fixtures/TextFitPending")
local KEYS_PENDING = require("../fixtures/TextFitKeysPending")

return function(T)
	local describe, it, Harness = T.describe, T.it, T.Harness

	local keyStore = TextFitKeys.new()
	local lastClient = nil

	local function verdict(caseKey, screenId, issues, err)
		if err then
			it(screenId, function()
				error("écran impossible à afficher : " .. tostring(err))
			end)
			return
		end
		local listed = LIST[caseKey]
		local fresh, fixed = Pending.compare(issues, listed)
		local name = screenId
		if listed ~= nil and #fresh == 0 and #fixed == 0 then
			name = string.format("%s — EN ATTENTE : %s", screenId, Pending.summary(issues))
			print("  \27[33m○ " .. caseKey .. " : " .. #listed .. " problème(s) connu(s)\27[0m")
		end
		it(name, function()
			local lines = {}
			if #fresh > 0 then
				table.insert(lines, "problèmes de texte NOUVEAUX dans " .. caseKey .. " :")
				local byEntry = {}
				for _, issue in issues do
					byEntry[Pending.entry(issue)] = issue
				end
				for _, e in fresh do
					local issue = byEntry[e]
					table.insert(
						lines,
						string.format(
							"  %s — « %s » : %s",
							e,
							string.sub(issue.text or "", 1, 60),
							issue.message
						)
					)
				end
			end
			if #fixed > 0 then
				table.insert(
					lines,
					"problèmes RÉPARÉS encore listés : retirer ces lignes de tests/fixtures/TextFitPending.luau ["
						.. caseKey
						.. "] :"
				)
				for _, e in fixed do
					table.insert(lines, "  " .. e)
				end
			end
			if #lines > 0 then
				error(table.concat(lines, "\n"), 0)
			end
		end)
	end

	local function measure(c)
		local okLayout, res = pcall(function()
			Screens.layout(c)
			TextFitKeys.collect(keyStore, c, c.profile.id, Screens)
			return Screens.textIssues(c)
		end)
		return okLayout, res
	end

	for _, profile in Screens.PROFILES do
		for _, lang in Screens.LANGS do
			local folder = profile.id .. "-" .. lang
			describe("TextFit_all › " .. profile.label .. " › " .. lang, function()
				for _, group in Screens.groups() do
					if group.loading then
						for _, screen in group.screens do
							local ok, c = pcall(Screens.bootLoading, Harness, profile, lang, screen.failed)
							local issues, err = {}, nil
							if ok then
								local okM, res = measure(c)
								if okM then
									issues = res
								else
									err = res
								end
							else
								err = c
							end
							verdict(folder .. "/" .. screen.id, screen.id, issues, err)
							Harness.disposeAll()
						end
					else
						local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
						if not ok then
							it("démarrage du client (" .. group.id .. ")", function()
								error(c)
							end)
						else
							lastClient = c
							for _, screen in Screens.expand(c, group) do
								local shown, err = Screens.show(c, screen)
								local issues = {}
								if shown then
									local okM, res = measure(c)
									if okM then
										issues = res
									else
										shown, err = false, res
									end
								end
								verdict(
									folder .. "/" .. screen.id,
									screen.id,
									issues,
									if shown then nil else err
								)
							end
							local errors = table.clone(c.h.errors)
							local warnings = c.h:warnings()
							it("aucune erreur ni avertissement du client (" .. group.id .. ")", function()
								local all = {}
								for _, e in errors do
									table.insert(all, "[erreur] " .. tostring(e))
								end
								for _, w in warnings do
									table.insert(all, "[avertissement] " .. tostring(w))
								end
								if #all > 0 then
									error(table.concat(all, "\n"), 0)
								end
							end)
						end
						Harness.disposeAll()
					end
				end
			end)
		end
	end

	describe(
		"TextFit_all › chaque clé de texte, EN et FR, dans chaque boîte où elle s'affiche",
		function()
			local result = nil
			if lastClient ~= nil then
				local Localization = lastClient.Localization
				result = TextFitKeys.check(keyStore, Localization, lastClient.Strings, function(lang, key)
					return Screens.varsFor(lastClient, key, lang)
				end)
			end
			it("relevé des boîtes disponible", function()
				if result == nil then
					error("aucun client démarré : pas de boîtes relevées", 0)
				end
			end)
			if result == nil then
				return
			end
			local nProven = 0
			for _ in result.proven do
				nProven += 1
			end
			local nPending = 0
			for _ in KEYS_PENDING do
				nPending += 1
			end
			print(
				string.format(
					"  %d clés prouvées dans les deux langues, %d en attente (raisons listées)",
					nProven,
					nPending
				)
			)
			it("toute clé qui s'affiche tient en EN et en FR (ou est en attente avec sa raison)", function()
				local lines = {}
				local keys = {}
				for key in result.failures do
					table.insert(keys, key)
				end
				table.sort(keys)
				for _, key in keys do
					if KEYS_PENDING[key] == nil then
						table.insert(lines, key .. " ne tient pas :")
						for i, m in result.failures[key] do
							if i > 4 then
								table.insert(
									lines,
									string.format("    … et %d autres", #result.failures[key] - 4)
								)
								break
							end
							table.insert(lines, "    " .. m)
						end
					end
				end
				if #lines > 0 then
					error(table.concat(lines, "\n"), 0)
				end
			end)
			it("toute clé jamais affichée est en attente avec une raison", function()
				local lines = {}
				local keys = {}
				for key in result.unseen do
					table.insert(keys, key)
				end
				table.sort(keys)
				local notUsed = 0
				for _, key in keys do
					if KEYS_PENDING[key] == nil then
						-- une clé que le client n'utilise pas encore (contrat d'un écran à venir, texte du
						-- serveur seul) n'a pas de boîte à prouver : acceptée, comptée
						if TextFitKeys.usedByClient(key) then
							table.insert(
								lines,
								key
									.. " : utilisée par le client mais jamais affichée par un scénario ; ajouter un scénario (tests/harness/Screens) ou une raison dans tests/fixtures/TextFitKeysPending.luau"
							)
						else
							notUsed += 1
						end
					end
				end
				if notUsed > 0 then
					print(
						string.format(
							"  %d clé(s) pas encore utilisée(s) par le client (contrat d'un écran à venir, texte du serveur) : acceptées",
							notUsed
						)
					)
				end
				if #lines > 0 then
					error(table.concat(lines, "\n"), 0)
				end
			end)
			it("aucune clé prouvée ne reste en attente (retirer sa ligne)", function()
				local lines = {}
				local keys = {}
				for key in KEYS_PENDING do
					table.insert(keys, key)
				end
				table.sort(keys)
				for _, key in keys do
					if result.proven[key] then
						table.insert(
							lines,
							key
								.. " est prouvée ("
								.. result.proven[key]
								.. " boîte(s)) : retirer sa ligne de tests/fixtures/TextFitKeysPending.luau"
						)
					elseif lastClient.Strings.en[key] == nil then
						-- clé retirée du registre (contrat) : signalée, sans bloquer l'autre équipe
						print(
							"  \27[33m○ "
								.. key
								.. " n'existe plus : retirer sa ligne de tests/fixtures/TextFitKeysPending.luau\27[0m"
						)
					end
				end
				if #lines > 0 then
					error(table.concat(lines, "\n"), 0)
				end
			end)
		end
	)
	-- fin : suivi des propriétés retiré (les specs suivantes retrouvent MockInstance tel quel)
	describe("fin des écrans", function()
		Screens.finish()
	end)
end
