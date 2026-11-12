--!nocheck
-- Relecture des écrans et de la manette du lot I (le jeu ouvert : les 23 interrupteurs de la v2.0 au
-- lancement) : défauts trouvés en regardant les captures de l'outil d'écrans (tools/screens, tous les
-- groupes, tv1080, tv720, tv2160, FR et EN) et en parcourant les écrans à la manette sur le vrai client
-- console ; chaque cas montré rouge avant sa correction (docs/04 §27.12, lignes I-60 et suivantes).
-- Zéro trace.
local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function groupOf(id)
		for _, group in Screens.groups() do
			if group.id == id then
				return group
			end
		end
		error("groupe inconnu : " .. id)
	end

	local function screenOf(group, id)
		for _, screen in group.screens do
			if screen.id == id then
				return screen
			end
		end
		error("écran inconnu : " .. id)
	end

	-- Défaut 1 (I-60) : les 3 écrans « launch.Shop.* » de l'outil (jeu ouvert) montraient le HUD seul :
	-- l'état du jeu ouvert (Screens.launchState) posait 400 s de jeu cumulé, sous les 10 min qui ouvrent
	-- la Boutique (Quests.ShopHiddenUntil, GDD §6.1) : le panneau ne s'ouvrait pas, et Screens_display,
	-- TextFit_all et la matrice de nuit passaient la Boutique du jeu ouvert à vide. Chaque écran
	-- « launch.<panneau>[.<onglet>] » doit montrer son panneau, sur son onglet.
	describe("Review_I_screens › groupe « launch » : chaque écran montre son panneau", function()
		local profile = Screens.profileById("tv1080")
		local group = groupOf("launch")
		for _, lang in Screens.LANGS do
			it(lang .. " : panneau ouvert et onglet choisi pour chaque écran launch.<panneau>", function()
				local c = Screens.boot(Harness, profile, lang, group.state)
				local missing = {}
				for _, entry in Screens.LAUNCH_TABS do
					local panel, tabs = entry[1], entry[2]
					for _, tab in tabs do
						local id = "launch." .. panel .. (if tab ~= "" then "." .. tab else "")
						local shown, err = Screens.show(c, screenOf(group, id))
						if not shown then
							table.insert(missing, id .. " : " .. tostring(err))
						elseif not c.PC.isOpen(panel) then
							table.insert(missing, id .. " : panneau fermé")
						elseif tab ~= "" then
							local mod = c.h:require(Screens.CLIENT .. "UI.Panels." .. panel)
							if type(mod.currentTab) == "function" and mod.currentTab() ~= tab then
								table.insert(missing, id .. " : onglet " .. tostring(mod.currentTab()))
							end
						end
					end
				end
				expect(table.concat(missing, "\n")).toBe("")
				Harness.disposeAll()
			end)
		end
	end)

	-- Défaut 2 (I-61) : carte rouverte à un seul bouton (« OK » de la carte « Nouveau : … » d'un Record R,
	-- unlock2) : le bouton occupe toute la largeur utile ; choisi, il grossit (Widgets, + 24 px TV au plus)
	-- depuis son coin haut gauche (AnchorPoint 0, 0) : il dépassait le bord droit de la carte (cadre de
	-- focus posé sur le bord, 1 364 px pour une carte qui finit à 1 362 en 1080p) et n'était plus centré.
	-- Les boutons d'une carte rouverte, choisis, restent dans la carte avec la même marge des deux côtés
	-- (± 2 px), à chaque résolution.
	describe("Review_I_screens › carte rouverte : le bouton choisi reste dans la carte", function()
		local group = groupOf("meta")
		for _, pid in { "tv1080", "tv720", "tv2160" } do
			for _, sid in { "meta.card.unlock2.open.r1", "meta.card.unlock.v2.open" } do
				it(pid .. " · " .. sid, function()
					local c = Screens.boot(Harness, Screens.profileById(pid), "fr", group.state)
					local shown, err = Screens.show(c, screenOf(group, sid))
					expect(err).toBeNil()
					expect(shown).toBe(true)
					Screens.layout(c)
					local sel = c.h.game.GuiService.SelectedObject
					expect(sel ~= nil).toBe(true)
					local card = sel
					while card ~= nil and card:GetAttribute("CardKind") == nil do
						card = card.Parent
					end
					expect(card ~= nil).toBe(true)
					local b, d = Layout.rect(sel), Layout.rect(card)
					local k = d.k or 1
					local left = (b.x - d.x) / k
					local right = (d.x + d.w - (b.x + b.w)) / k
					local problems = {}
					if left < 8 or right < 8 then
						table.insert(problems, string.format("bouton à %.1f / %.1f px des bords", left, right))
					end
					local buttons = 0
					for _, o in sel.Parent:GetChildren() do
						if o:IsA("GuiButton") and o.Visible then
							buttons += 1
						end
					end
					if buttons == 1 and math.abs(left - right) > 2 then
						table.insert(problems, string.format("bouton seul décentré : %.1f / %.1f px", left, right))
					end
					expect(table.concat(problems, "\n")).toBe("")
					Harness.disposeAll()
				end)
			end
		end
	end)

	describe("fin des écrans", function()
		Screens.finish()
	end)
	local _ = Enum
end
