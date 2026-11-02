--!nocheck
-- Screens_display (outil d'écrans, tools/screens/README.md) : défauts d'affichage hors mesure du
-- texte, sur les vrais écrans du client (tests/harness/Screens), en PS5 TV 1920 × 1080 et 1280 × 720,
-- en français et en anglais :
--   * contraste : tout texte lisible (lettre ou chiffre, non décoratif) a un contraste ≥ 3 avec le
--     fond réellement dessiné derrière lui (WCAG, grand texte), son contour compté — y compris sur
--     les cases et boutons de couleur vive (onglet actif bleu, Acheter vert, rose, doré, case choisie
--     en vert dans Vendre, jours de Plop et étapes de l'accueil faits) ;
--   * textes coupés : aucune ligne coupée en deux par un parent qui découpe (Guide du Squishydex),
--     sauf la rangée entrouverte voulue d'une liste virtuelle (PeekRows) ;
--   * fenêtres : aucun objet visible ne dépasse de son panneau (un bouton qui grandit de 5 % quand il
--     est choisi reste dans sa fenêtre) ;
--   * curseur : l'objet sélectionné est visible, son halo est entier à l'écran et pas caché par un
--     parent qui découpe ;
--   * grand tampon des effets (« SECRET … · 1 sur 1 000 000 000 ») : jamais sur un élément du HUD ;
--   * écran de chargement : aucun texte ni bouton teinté par le dégradé d'un CanvasGroup (Roblox
--     applique l'UIGradient d'un CanvasGroup à TOUT son contenu).

local Screens = require("../harness/Screens")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local PROFILES = { Screens.profileById("tv1080"), Screens.profileById("tv720") }
	-- écrans vérifiés (identifiants de tests/harness/Screens), par groupe
	local WANTED = {
		new = {
			["hud.new"] = true,
			["onboarding.step05"] = true,
			["panel.Objectives.onboarding.new"] = true,
			["panel.Settings.new"] = true,
		},
		mid = {
			["menu"] = true,
			["panel.Ranch.pens"] = true,
			["panel.Ranch.pens.open"] = true,
			["panel.Ranch.dodo"] = true,
			["panel.Ranch.fuse"] = true,
			["panel.Ranch.sell"] = true,
			["panel.Ranch.sell.open"] = true,
			["panel.Ranch.pads"] = true,
			["panel.Ranch.style"] = true,
			["panel.Squishydex.species"] = true,
			["panel.Squishydex.species.open"] = true,
			["panel.Squishydex.families"] = true,
			["panel.Squishydex.guide"] = true,
			["panel.Objectives.today"] = true,
			["panel.Objectives.plop"] = true,
			["panel.Leaderboards.stamps"] = true,
			["panel.Shop.passes"] = true,
			["panel.Shop.party"] = true,
			["panel.Shop.outfits"] = true,
			["panel.Settings"] = true,
			["panel.SplorchPreview"] = true,
			["panel.SplorchPreview.details"] = true,
			["panel.OutfitPreview.crown"] = true,
			["panel.Diagnostics.server"] = true,
			["panel.Diagnostics.tools"] = true,
			["card.mode"] = true,
			["return.ready"] = true,
		},
		-- grands tampons des effets (le plus long : SECRET … · 1 sur 1 000 000 000) : jamais sur le HUD
		fx = {
			["stamp.secretTag"] = true,
			["stamp.splorchTitle"] = true,
			["stamp.flop"] = true,
			["stamp.combo"] = true,
		},
	}

	for _, profile in PROFILES do
		for _, lang in Screens.LANGS do
			describe("Screens_display › " .. profile.label .. " › " .. lang, function()
				for _, group in Screens.groups() do
					if group.loading then
						for _, screen in group.screens do
							local ok, c = pcall(Screens.bootLoading, Harness, profile, lang, screen.failed)
							local issues = if ok then nil else { tostring(c) }
							if ok then
								Screens.layout(c)
								issues = Screens.tintIssues(c)
							end
							it(
								screen.id
									.. " : aucun texte ni bouton teinté par un dégradé de CanvasGroup",
								function()
									expect(table.concat(issues, "\n")).toBe("")
								end
							)
							Harness.disposeAll()
						end
					elseif WANTED[group.id] then
						local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
						if not ok then
							it("démarrage du client (" .. group.id .. ")", function()
								error(c)
							end)
						else
							for _, screen in Screens.expand(c, group) do
								if WANTED[group.id][screen.id] then
									local shown, err = Screens.show(c, screen)
									local contrast, windows, selection, clips = {}, {}, {}, {}
									if shown then
										Screens.layout(c)
										contrast = Screens.contrastIssues(c)
										windows = Screens.windowIssues(c)
										selection = Screens.selectionIssues(c)
										clips = Screens.clipIssues(c)
										for _, line in Screens.crossOverlaps(c, "VFXStamp", { "HUD" }) do
											table.insert(clips, "tampon sur le HUD : " .. line)
										end
									end
									it(
										screen.id
											.. " : contraste ≥ 3, rien hors de sa fenêtre, curseur visible",
										function()
											if not shown then
												error("écran impossible à afficher : " .. tostring(err))
											end
											local all = {}
											for _, list in { contrast, windows, selection, clips } do
												for _, line in list do
													table.insert(all, line)
												end
											end
											expect(table.concat(all, "\n")).toBe("")
										end
									)
								end
							end
						end
						Harness.disposeAll()
					end
				end
			end)
		end
	end
	-- fin : suivi des propriétés retiré (les specs suivantes retrouvent MockInstance tel quel)
	describe("fin des écrans", function()
		Screens.finish()
	end)
end
