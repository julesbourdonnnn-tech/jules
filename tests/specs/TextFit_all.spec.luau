--!nocheck
-- Tous les textes de tous les écrans tiennent (docs/07-console-ps5.md §3, tools/screens/README.md).
-- Pour chaque appareil (6 : téléviseur console 1920 × 1080, 3840 × 2160 et 1280 × 720, téléphone,
-- tablette, PC) × langue (fr, en) × écran (tests/harness/Screens : HUD nouveau joueur / milieu / fin
-- de partie, chaque panneau et chaque onglet, Améliorer dans tous ses états, très grands nombres,
-- toasts, bannières, célébrations, accueil, chargement), la mise en page FIDÈLE (Layout en mode
-- fidèle + TextFit : vraies largeurs des polices, règles TextScaled / TextWrapped / TextTruncate de
-- Roblox) ne doit montrer :
--   * aucun texte qui déborde de sa boîte (overflow) ni mot coupé (splitWord) ;
--   * aucun « … » qui cache un nombre ou un mot entier (truncated) ;
--   * aucun TextScaled sous le minimum lisible : 18 px de référence × échelle de Root (small) ;
--   * aucune ponctuation seule sur sa ligne (orphan) ;
--   * aucune clé de traduction, variable « {x} », « ? » ou texte jamais posé (« Label ») à l'écran.
-- Cas EN ATTENTE (problèmes présents aujourd'hui) : tests/fixtures/TextFitPending.luau. Un écran dont
-- tous les problèmes sont listés est sauté (ligne jaune, liste des problèmes) ; un problème NOUVEAU
-- fait échouer, un problème listé mais disparu aussi (réparé : retirer sa ligne).

local Screens = require("../harness/Screens")
local Pending = require("../harness/TextFitPending")
local LIST = require("../fixtures/TextFitPending")

return function(T)
	local describe, it, Harness, skip = T.describe, T.it, T.Harness, T.skip

	local function verdict(caseKey, screenId, issues, err)
		if err then
			it(screenId, function()
				error("écran impossible à afficher : " .. tostring(err))
			end)
			return
		end
		local listed = LIST[caseKey]
		local fresh, fixed = Pending.compare(issues, listed)
		if #fresh == 0 and #fixed == 0 and listed ~= nil then
			skip(
				screenId,
				string.format("%d problème(s) connu(s) [%s] : %s", #listed, caseKey, Pending.summary(issues))
			)
			return
		end
		it(screenId, function()
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

	for _, profile in Screens.PROFILES do
		for _, lang in Screens.LANGS do
			local folder = profile.id .. "-" .. lang
			describe("TextFit_all › " .. profile.label .. " › " .. lang, function()
				for _, group in Screens.groups() do
					if group.loading then
						for _, screen in group.screens do
							local ok, c = pcall(Screens.bootLoading, Harness, profile, lang, screen.failed)
							local issues = {}
							if ok then
								Screens.layout(c)
								issues = Screens.textIssues(c)
							end
							verdict(folder .. "/" .. screen.id, screen.id, issues, if ok then nil else c)
							Harness.disposeAll()
						end
					else
						local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
						if not ok then
							it("démarrage du client (" .. group.id .. ")", function()
								error(c)
							end)
						else
							for _, screen in Screens.expand(c, group) do
								local shown, err = Screens.show(c, screen)
								local issues = {}
								if shown then
									local okLayout, res = pcall(function()
										Screens.layout(c)
										return Screens.textIssues(c)
									end)
									if okLayout then
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
							it("aucune erreur du client (" .. group.id .. ")", function()
								if #c.h.errors > 0 then
									error(table.concat(c.h.errors, "\n"))
								end
							end)
						end
						Harness.disposeAll()
					end
				end
			end)
		end
	end
end
