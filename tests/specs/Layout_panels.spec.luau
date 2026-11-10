--!nocheck
-- Layout_panels (paquet client-panels ; couche d, GDD §10.1, §10.3 ; docs/04 §14.1, §17.1 d) : le
-- parcours à 3 touches sur un profil riche en 1920 × 1080, 3840 × 2160 et 1280 × 720 (barre de Roblox
-- de 58 px comprise), en anglais puis en français : aucun chevauchement, aucun texte coupé ni sous
-- 28 px TV, rien hors de la zone sûre de 5 %, glyphes PlayStation ; puis le budget d'objets
-- d'interface (≤ 3 000 GuiObject avec tous les panneaux construits, docs/04 §18.3). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Layout_panels › 3 résolutions × 2 langues", function()
		it("aucune faute de disposition sur aucun écran ; ≤ 3 000 objets d'interface", function()
			local profile = TvAudit.richProfile()
			profile.squishies.u20.z = 300000 -- Grand Splorch prêt
			local h = TvAudit.client({ before = TvAudit.enableShop, profile = profile })
			h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
			h:settle(1)
			local report = TvAudit.run(h, {
				resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
				langs = { "en", "fr" },
			})
			expect(table.concat(report.issues, "\n")).toBe("")
			local n = 0
			for _ in report.screens do
				n += 1
			end
			expect(n >= 30).toBe(true)
			-- tous les panneaux sont construits à ce stade (une seule fois chacun)
			local gui = TvAudit.guiObjects(h)
			expect(gui <= 3000).toBe(true)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)

	-- v2.0 (lot B2, étape 5) : même parcours avec l'instantané du serveur (interrupteur UpgradesScreen
	-- ouvert DANS le test) : rail v2.0, écran Améliorations et ses 4 onglets, HUD v2.0 ; budgets : écran
	-- ≤ 1 400 objets d'interface (règle 20, GDD §10.7.10), interface au chargement ≤ 3 000 (§12.9) ;
	-- interface entière, tous les panneaux construits : garde de non-régression ≤ 3 800 (journal B2-13,
	-- B2-49 : les 3 000 du §12.9 ne tiennent pas avec la v1.3 entière plus l'écran, décision demandée) ;
	-- ≤ 3 875 depuis le lot B3, étape 1 (D24, journal B3-8 : + 75 des 5 badges d'étoiles dessinés de la
	-- fiche du Squishydex, règle 18) ; ≤ 3 950 depuis le lot B3, étape 2 (D24, journal B3-19 : + 57 de
	-- l'aperçu de renaissance de la v2.0, SplorchPreview 63 → 120) ; ≤ 4 125 depuis le lot B3, étape 3
	-- (D24, journal B3-31 : + 152, cœurs et coche dessinés des 30 cases du Ranch, garde-robe, Dalles
	-- non construites sur le chemin de l'écran Améliorations)
	describe("Layout_panels › v2.0 : écran Améliorations et rail v2.0 (lot B2)", function()
		it("aucune faute de disposition sur aucun écran, 3 résolutions × 2 langues ; budgets", function()
			local UpgradeScreen = require("../harness/UpgradeScreen")
			local S = UpgradeScreen.new(T.Harness)
			local profile = TvAudit.richProfile()
			profile.squishies.u20.z = 300000 -- Grand Splorch prêt
			profile.upgradeSnapshot = S.snap(1)
			local h = TvAudit.client({ before = TvAudit.enableShop, profile = profile })
			h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
			h:settle(1)
			-- au chargement : HUD v2.0, rail et écran Améliorations construits, aucun autre panneau ouvert
			local atLoad = TvAudit.guiObjects(h)
			local report = TvAudit.run(h, {
				resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
				langs = { "en", "fr" },
				maxScreens = 120,
			})
			expect(table.concat(report.issues, "\n")).toBe("")
			local tabs = {}
			for id in report.screens do
				local tab = string.match(id, "^panel:Upgrades/(%w+)")
				if tab then
					tabs[tab] = true
				end
			end
			for _, tab in { "suggested", "ranch", "helpers", "workshop" } do
				expect({ tab = tab, reached = tabs[tab] == true }).toEqual({ tab = tab, reached = true })
			end
			local PC = TvAudit.mod(h, "UI.PanelController")
			local screen = 0
			for _, d in PC.window("Upgrades"):GetDescendants() do
				if d:IsA("GuiObject") then
					screen += 1
				end
			end
			local whole = TvAudit.guiObjects(h)
			print(
				string.format(
					"    objets d'interface : chargement %d, écran %d, tout construit %d",
					atLoad,
					screen + 1,
					whole
				)
			)
			expect(screen + 1 <= 1400).toBe(true)
			expect(atLoad <= 3000).toBe(true)
			expect(whole <= 4125).toBe(true)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)

	-- v2.0 méta (lot B3, étape 6, D24 ; journal B3-65) : même parcours avec les 11 interrupteurs v2.0 annoncés
	-- par le serveur (EventState.features.v2), l'instantané, MON ranch prêt à la Jelly Ascend (AscendReady,
	-- HaloOn, DecoPerso, BestR, GiantTier) et un profil v2 riche (piste, Défis, Carnet, maîtrise, cœurs, Déco
	-- perso, tenues et cosmétiques de la v2.0) : aucune faute sur aucun écran, chaque onglet v2.0 du lot B3
	-- atteint (aperçu : Jelly Ascend ; Ranch : Mon style et son plan ; Squishydex : Records ; Objectifs :
	-- Cette semaine, Carnet ; Réglages : le halo), puis une carte v2.0 rouverte et les jumelles une fois.
	-- Budgets : écran ≤ 1 400 et chargement ≤ 3 000 tenus ; interface entière du chemin méta, toutes les
	-- fenêtres construites : garde de non-régression (mesure arrondie aux 25 du dessus, règle D24 ; les
	-- 3 000 du §12.9 ne tiennent pas, décision B2-13 à prendre par le lot I)
	describe("Layout_panels › v2.0 méta (lot B3)", function()
		it(
			"aucune faute de disposition, 3 résolutions × 2 langues ; chaque onglet v2.0 du lot B3 atteint ; budgets",
			function()
				local UpgradeScreen = require("../harness/UpgradeScreen")
				local MockInstance = require("../harness/MockInstance")
				local S = UpgradeScreen.new(T.Harness)
				local OWNER = 22
				local WEEK, EPOCH = 604800, 345600
				local week = math.floor((1800000000 - EPOCH) / WEEK)
				local profile = TvAudit.richProfile()
				-- Grand Splorch ET Jelly Ascend prêts (r = Record R = 15 = reqR(1)) : l'aperçu a deux onglets
				profile.squishies.u20.z = 3e15
				profile.version = 2
				profile.R = 15
				profile.bestR = 15
				profile.ascend = 0
				profile.biggestEver = 3e15
				profile.confetti = 139
				profile.confettiTotal = 2500
				profile.atelierCosmetics = { 7 }
				profile.cosmetics = {
					saddle = "classic",
					trail = "",
					title = "",
					theme = "marshmallow",
					flag = "",
					palette = "candy",
					cushions = "",
				}
				profile.outfits = {
					owned = { plopBib = 1, sweater = 2, partyHat = 1, starGlasses = 1 },
					worn = {},
				}
				profile.decoPerso = { owned = { 0, 0 }, slots = { 1, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }
				profile.weeklyTrack = {
					period = week,
					firstPeriodEnd = EPOCH + (week - 4) * WEEK,
					points = 9,
					claimed = { 15 },
					won = { 1 },
					challenges = {
						{ id = 7, p = 1, done = false },
						{ id = 6, p = 1, done = true },
						{ id = 12, p = 17, done = false },
					},
					play = { 0, 0, 0, 0, 0, 0, 0 },
					playDay = 0,
				}
				profile.carnet = { 15 }
				profile.mastery = { 2 }
				profile.hearts = { receivedTotal = 42, givenDay = 0, givenTo = {} }
				profile.moon = { lastSession = 0, sessions = 1 }
				profile.stats.upgradesBought = 600
				profile.stats.objectivesClaimed = 30
				profile.stats.tracksDone = 1
				profile.stats.splorches = 40
				profile.stats.bestCombo = 12
				local defaults = TvAudit.defaults()
				profile.settings = defaults.settings
				profile.settings.haloOn = true
				local snap = S.snap(1, function(p)
					p.R = 15
					p.bestR = 15
					p.ascend = 0
				end)
				local c = S.client({
					snap = snap,
					profile = profile,
					before = TvAudit.enableShop,
					ranch = {
						AscendReady = true,
						HaloOn = true,
						DecoPerso = "1,7,0,0,0,0,0,0,0,0,0,0",
						BestR = 15,
						GiantTier = 3,
					},
				})
				local h = c.h
				h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
				h:settle(1)
				S.event(c, UpgradeScreen.V2_ALL)
				-- au chargement : HUD v2.0, rail et écran Améliorations construits, aucun autre panneau ouvert
				local atLoad = TvAudit.guiObjects(h)
				local report = TvAudit.run(h, {
					resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
					langs = { "en", "fr" },
					maxScreens = 200,
				})
				local ids = {}
				for id in report.screens do
					table.insert(ids, id)
				end
				table.sort(ids)
				print("    écrans atteints (" .. #ids .. ") : " .. table.concat(ids, ", "))
				expect(table.concat(report.issues, "\n")).toBe("")
				local function reached(prefix)
					for _, id in ids do
						if string.sub(id, 1, #prefix) == prefix then
							return true
						end
					end
					return false
				end
				for _, prefix in
					{
						"panel:SplorchPreview/ascend",
						"panel:Ranch/style",
						"panel:Squishydex/records",
						"panel:Objectives/track",
						"panel:Objectives/carnet",
						"panel:Settings",
					}
				do
					expect({ screen = prefix, reached = reached(prefix) }).toEqual({
						screen = prefix,
						reached = true,
					})
				end
				local PC = c.PC
				-- chemin v2.0 bien pris : onglet « Mon style », plan de Déco perso, ligne du halo
				local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
				expect(PC.window("Ranch").Body.Tabs.Strip.Tab_style.Label.Text).toBe("Mon style")
				expect(Ranch._decoSlot(12) ~= nil).toBe(true)
				-- (lignes recyclées par Widgets.rows : la liste des réglages affichés, pas les libellés)
				local halo = false
				for _, item in TvAudit.mod(h, "UI.Panels.Settings")._items() do
					if item.key == "haloOn" then
						halo = true
					end
				end
				expect(halo).toBe(true)
				-- une carte v2.0 rouverte depuis « ! » (boîte des cartes v2.0) et les jumelles, une fois
				local Cards = TvAudit.mod(h, "UI.Cards")
				h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "trackTier", data = { tier = 2, reward = "confetti" } }
				)
				h:settle(1)
				c.Clock.advance(8.01)
				Cards._step()
				TvAudit.tick(h, 0.2)
				expect(#Cards.pending()).toBe(1)
				expect(TvAudit.openMenu(h)).toBe(true)
				h.game.GuiService.SelectedObject = PC.entryButton("Pending")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				TvAudit.tick(h, 0.5)
				expect(Cards.current() ~= nil and Cards.current().kind).toBe("trackTier")
				local cardIssues = TvAudit.check(h, "[carte rouverte] ")
				expect(table.concat(cardIssues, "\n")).toBe("")
				expect(TvAudit.toGame(h)).toBe(true)
				local me = h.localPlayer.UserId
				local function ranchRow(slot, userId)
					return {
						slot = slot,
						userId = userId,
						name = if userId == me then "Moi" else "",
						hidden = userId ~= me,
						R = 0,
						fame = 0,
						day = 0,
						mode = "cozy",
						shield = false,
						boopable = false,
						tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
						vat = true,
						pool = true,
						vatFill = 0,
						growth = { G = 0, g = 0, t = 1800000000 },
						carry = "",
						ride = "",
						saddle = 0,
						waiting = "",
						theme = "",
						flag = "",
						title = "",
						saddleColor = "",
						trail = "",
						best = { s = 0, m = 0, z = 0, zg = 0 },
					}
				end
				h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
					seq = 1,
					ranches = { ["1"] = ranchRow(1, me), ["2"] = ranchRow(2, OWNER) },
					squishies = { ["1"] = {}, ["2"] = {} },
				})
				h:settle(1)
				local list = h.workspace.Wobbleton.Ranches
				local other = list:FindFirstChild("2")
				if other == nil then
					other = MockInstance.new("Model")
					other.Name = "2"
					other.Parent = list
				end
				other:SetAttribute("BestR", 5)
				local B = TvAudit.mod(h, "UI.Binoculars")
				expect(B.open(OWNER)).toBe(true)
				TvAudit.tick(h, 0.5)
				expect(table.concat(TvAudit.check(h, "[jumelles] "), "\n")).toBe("")
				local whole = TvAudit.guiObjects(h)
				B.close()
				TvAudit.tick(h, 0.5)
				-- relevé par fenêtre (panneaux de la zone sûre) et par ScreenGui
				local parts = {}
				local safe = h.localPlayer.PlayerGui:FindFirstChild("Panels")
				safe = safe and safe:FindFirstChild("Safe")
				for _, w in if safe then safe:GetChildren() else {} do
					if
						string.sub(w.Name, 1, 6) == "Panel_" and not string.find(w.Name, "_Shadow", 1, true)
					then
						local n = 1
						for _, d in w:GetDescendants() do
							if d:IsA("GuiObject") then
								n += 1
							end
						end
						table.insert(parts, string.sub(w.Name, 7) .. " " .. n)
					end
				end
				table.sort(parts)
				local guis = {}
				for _, g in h.localPlayer.PlayerGui:GetChildren() do
					local n = 0
					for _, d in g:GetDescendants() do
						if d:IsA("GuiObject") then
							n += 1
						end
					end
					table.insert(guis, g.Name .. " " .. n)
				end
				table.sort(guis)
				local screen = 0
				for _, d in PC.window("Upgrades"):GetDescendants() do
					if d:IsA("GuiObject") then
						screen += 1
					end
				end
				print(
					string.format(
						"    objets d'interface (chemin méta) : chargement %d, écran %d, tout construit %d ; panneaux : %s ; ScreenGui : %s",
						atLoad,
						screen + 1,
						whole,
						table.concat(parts, ", "),
						table.concat(guis, ", ")
					)
				)
				expect(screen + 1 <= 1400).toBe(true)
				expect(atLoad <= 3000).toBe(true)
				-- garde de non-régression du chemin méta (D24, journal B3-65) : 4 631 mesurés à l'étape 6 du lot
				-- B3 (chargement 1 506, écran 1 219 ; + 865 sur la référence de 3 766 du lot B2 : Ranch + 322,
				-- Objectifs + 230, aperçu + 166, Squishydex + 123, jumelles + 16, garde-robe + 6, cartes + 2),
				-- arrondis aux 25 du dessus ; les 3 000 du §12.9 ne tiennent pas (B2-13, décision du lot I)
				expect(whole <= 4650).toBe(true)
				expect(#TvAudit.sent(h, "JellyAscend")).toBe(0)
				expect(#TvAudit.sent(h, "GiveHeart")).toBe(0)
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
