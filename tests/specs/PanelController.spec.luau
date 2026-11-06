--!nocheck
-- PanelController (paquet client-panels) : rail et panneaux (GDD §10.3, §10.4, §10.6 ; docs/04 §13.6,
-- §14.2) sur le vrai client console : règle des 3 touches (croix, ✕, ○), △ ferme tout, L1 / R1 en
-- boucle, L2 / R2 seulement quand un panneau est ouvert, sélection par défaut du rail, Cards.Requested,
-- setNavigator avant build, PutDown à l'ouverture d'un panneau (pas du rail), bout de liste. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(opts)
		local h = TvAudit.client(opts)
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			FG = TvAudit.mod(h, "UI.FocusGuard"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	local function readyProfile()
		-- plus gros squishy au-dessus de l'objectif de R = 0 (15 000) : Grand Splorch prêt
		return {
			squishies = { a = TvAudit.squishy(1, { z = 20000 }), b = TvAudit.squishy(2, { z = 50 }) },
			growth = { G = 0, g = 1, t = 1800000000 },
		}
	end

	describe("PanelController › rail", function()
		it("△ ouvre le rail sur Ranch ; △ juste après est ignoré ; △ ensuite ferme tout", function()
			local c = setup()
			expect(c.PC.menuOpen()).toBe(false)
			c.PC.toggleMenu()
			expect(c.PC.menuOpen()).toBe(true)
			expect(sel(c)).toBe(c.PC.entryButton("Ranch"))
			-- entrées visibles : ni Grand Splorch (pas prêt), ni « ! », ni Boutique (< 10 min, ids à 0)
			expect(c.PC.entries()).toEqual({ "Ranch", "Squishydex", "Objectives", "Leaderboards", "Settings" })
			c.PC.toggleMenu() -- double appui (0,35 s)
			expect(c.PC.menuOpen()).toBe(true)
			TvAudit.tick(c.h, 0.5)
			c.PC.toggleMenu()
			expect(c.PC.menuOpen()).toBe(false)
			expect(sel(c)).toBeNil()
			clean(c)
		end)

		it(
			"sélection par défaut : Grand Splorch prêt, sinon « ! », sinon la dernière entrée",
			function()
				local c = setup({ profile = readyProfile() })
				c.PC.toggleMenu()
				expect(c.PC.entries()[1]).toBe("SplorchPreview")
				expect(sel(c)).toBe(c.PC.entryButton("SplorchPreview"))
				c.PC.closeAll()
				-- carte en attente (Cards.pending) : l'entrée « ! » est sélectionnée quand rien n'est prêt
				local c2 = setup()
				local Cards = TvAudit.mod(c2.h, "UI.Cards")
				local opened = {}
				Cards.pending = function()
					return { { id = "card1", kind = "booped", blocking = false, data = {} } }
				end
				Cards.open = function(id)
					table.insert(opened, id)
				end
				c2.PC.toggleMenu()
				expect(c2.PC.entries()[1]).toBe("Pending")
				expect(sel(c2)).toBe(c2.PC.entryButton("Pending"))
				TvAudit.tick(c2.h, 0.5)
				Gamepad.tap(c2.h, Enum.KeyCode.ButtonA)
				expect(opened).toEqual({ "card1" })
				-- dernière entrée utilisée
				local c3 = setup()
				c3.PC.open("Leaderboards")
				TvAudit.tick(c3.h, 0.5)
				c3.PC.closeAll()
				TvAudit.tick(c3.h, 0.5)
				c3.PC.toggleMenu()
				expect(sel(c3)).toBe(c3.PC.entryButton("Leaderboards"))
				clean(c)
				clean(c2)
				clean(c3)
			end
		)

		it(
			"Boutique : cachée < 10 min ou sans identifiant, visible ensuite ; Diagnostics jamais dans le rail",
			function()
				local c = setup({
					before = function(h)
						local M = h:require("ReplicatedStorage.Shared.Config.Monetization")
						M.Passes.AutoPot.id = 11
					end,
				})
				expect(table.find(c.PC.entries(), "Shop")).toBeNil()
				local State = TvAudit.mod(c.h, "Controllers.StateController")
				local stats = table.clone(State.get("stats"))
				stats.playSeconds = 601
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { stats = stats }, {})
				c.h:settle(2)
				expect(table.find(c.PC.entries(), "Shop") ~= nil).toBe(true)
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
				expect(table.find(c.PC.entries(), "Diagnostics")).toBeNil()
				clean(c)
			end
		)
	end)

	describe("PanelController › règle des 3 touches", function()
		it(
			"croix ↓ jusqu'à Squishydex, ✕ ouvre, ○ revient au bouton du rail, ○ rend la main au jeu",
			function()
				local c = setup()
				c.PC.toggleMenu()
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				expect(sel(c)).toBe(c.PC.entryButton("Squishydex"))
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.PC.current()).toBe("Squishydex")
				expect(c.PC.isOpen("Squishydex")).toBe(true)
				local root = c.PC.window("Squishydex")
				expect(sel(c):IsDescendantOf(root)).toBe(true)
				-- ○ trop tôt : double appui ignoré
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Squishydex")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBeNil()
				expect(c.PC.menuOpen()).toBe(true)
				expect(sel(c)).toBe(c.PC.entryButton("Squishydex"))
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.FG.anyOpen()).toBe(false)
				expect(sel(c)).toBeNil()
				clean(c)
			end
		)

		it("△ ferme tout depuis un panneau ; Changed signale le panneau puis nil", function()
			local c = setup()
			local seen = {}
			c.PC.Changed:Connect(function(p)
				table.insert(seen, p or "nil")
			end)
			c.PC.open("Objectives")
			expect(c.PC.menuOpen()).toBe(true) -- le rail reste dessous (○ y revient)
			TvAudit.tick(c.h, 0.5)
			c.PC.toggleMenu()
			expect(c.FG.anyOpen()).toBe(false)
			expect(seen).toEqual({ "Objectives", "nil" })
			clean(c)
		end)
	end)

	describe("PanelController › L1 / R1 et L2 / R2", function()
		it(
			"L1 / R1 changent d'onglet en boucle ; L2 / R2 de panneau en boucle (Boutique cachée sautée)",
			function()
				local c = setup()
				local Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
				-- L2 / R2 ne sont pas liés sans panneau (L2 = Monter, R2 = Bondir en jeu)
				c.PC.toggleMenu()
				expect(c.h.actionBindings.PanelCycle).toBeNil()
				c.PC.open("Ranch")
				expect(c.h.actionBindings.PanelCycle ~= nil).toBe(true)
				expect(Ranch.currentTab()).toBe("pens")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				expect(Ranch.currentTab()).toBe("dodo")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL1)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL1)
				expect(Ranch.currentTab()).toBe("style") -- en boucle
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
				expect(c.PC.current()).toBe("Squishydex")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL2)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL2)
				expect(c.PC.current()).toBe("Settings") -- en boucle, Boutique invisible sautée
				-- double appui de R2 : le second est ignoré
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
				expect(c.PC.current()).toBe("Ranch")
				c.PC.closeAll()
				expect(c.h.actionBindings.PanelCycle).toBeNil()
				expect(c.h.actionBindings.PanelTabs).toBeNil()
				clean(c)
			end
		)
	end)

	describe("PanelController › carte bloquante par-dessus un panneau", function()
		it(
			"L1 / R1 / L2 / R2 ne font rien derrière la carte ; ○ ferme la carte, pas le panneau",
			function()
				local c = setup()
				local Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
				c.PC.open("Ranch")
				TvAudit.tick(c.h, 0.5)
				local Instance = c.h.globals.Instance
				local root = Instance.new("Frame")
				root.Parent = TvAudit.mod(c.h, "UI.Root").safe("TestCard", 60)
				local b = Instance.new("TextButton")
				b.Parent = root
				c.FG.open({
					name = "card:mode",
					root = root,
					blocking = true,
					default = function()
						return b
					end,
					onBack = function()
						return false
					end,
				})
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
				expect(Ranch.currentTab()).toBe("pens")
				expect(c.PC.current()).toBe("Ranch")
				c.PC.toggleMenu() -- carte bloquante : △ ne ferme rien
				expect(c.FG.isOpen("card:mode")).toBe(true)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.FG.isOpen("card:mode")).toBe(false)
				expect(c.PC.current()).toBe("Ranch")
				clean(c)
			end
		)
	end)

	describe("PanelController › liens entre modules", function()
		it(
			"Cards.Requested ouvre le panneau demandé ; setNavigator avant build ; panneau inconnu ignoré",
			function()
				local c = setup()
				local LB = TvAudit.mod(c.h, "UI.Panels.Leaderboards")
				local order = {}
				local setNav, build = LB.setNavigator, LB.build
				LB.setNavigator = function(nav)
					table.insert(order, "setNavigator")
					expect(type(nav.open)).toBe("function")
					expect(type(nav.back)).toBe("function")
					setNav(nav)
				end
				LB.build = function(container)
					table.insert(order, "build")
					build(container)
				end
				c.PC.open("Leaderboards")
				expect(order).toEqual({ "setNavigator", "build" })
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Leaderboards") -- construit une seule fois
				expect(order).toEqual({ "setNavigator", "build" })
				c.PC.closeAll()
				local Cards = TvAudit.mod(c.h, "UI.Cards")
				Cards.Requested:Fire("objectives", "open")
				c.h:settle(2)
				expect(c.PC.current()).toBe("Objectives")
				expect(TvAudit.mod(c.h, "UI.Panels.Objectives").currentTab()).toBe("today")
				Cards.Requested:Fire("dex", "open")
				c.h:settle(2)
				expect(c.PC.current()).toBe("Squishydex")
				Cards.Requested:Fire("inconnue", "open")
				Cards.Requested:Fire("dex", "autre")
				c.PC.open("NExistePas")
				c.PC.open(nil)
				expect(c.PC.current()).toBe("Squishydex")
				clean(c)
			end
		)

		it("ouvrir un panneau termine le portage (PutDown) ; ouvrir le rail, non", function()
			local c = setup()
			local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
			WSC.mySlot = function()
				return 3
			end
			WSC.ranch = function()
				return { carry = "u7" }
			end
			local function putDowns()
				local n = 0
				for _, e in c.h.log.serverEvents do
					if e.remote == "PutDown" then
						n += 1
					end
				end
				return n
			end
			c.PC.toggleMenu()
			expect(putDowns()).toBe(0)
			c.PC.open("Ranch")
			expect(putDowns()).toBe(1)
			clean(c)
		end)

		it("fenêtre bloquante d'un autre écran (écran de retour) : △ et open ne font rien", function()
			local c = setup()
			local RS = TvAudit.mod(c.h, "UI.ReturnScreen")
			RS.show({
				seconds = 3600,
				uid = "a",
				species = 1,
				grew = 10,
				pot = 5,
				splorchReady = false,
				nearlyReady = false,
			})
			expect(RS.isOpen()).toBe(true)
			c.PC.toggleMenu()
			c.PC.open("Ranch")
			expect(c.PC.menuOpen()).toBe(false)
			expect(c.PC.current()).toBeNil()
			clean(c)
		end)

		it("bout de liste : son Bump, vibration listEnd, aucune sélection déplacée", function()
			local c = setup()
			local Haptics = TvAudit.mod(c.h, "Util.Haptics")
			local Audio = TvAudit.mod(c.h, "Controllers.AudioController")
			local played, sounds = {}, {}
			Haptics.Played:Connect(function(name)
				table.insert(played, name)
			end)
			local play = Audio.play
			Audio.play = function(name, ...)
				table.insert(sounds, name)
				return play(name, ...)
			end
			c.PC.toggleMenu()
			TvAudit.tick(c.h, 0.5)
			local first = sel(c)
			expect(first).toBe(c.PC.entryButton("Ranch"))
			-- ↑ depuis la première entrée : rien au-dessus dans la fenêtre (SelectionGroup Stop)
			c.h:step(1 / 60, 2)
			Gamepad.tap(c.h, Enum.KeyCode.DPadUp)
			c.h:settle(2)
			expect(sel(c)).toBe(first)
			expect(table.find(played, "listEnd") ~= nil).toBe(true)
			expect(table.find(sounds, "Bump") ~= nil).toBe(true)
			-- une navigation qui bouge ne rebondit pas
			table.clear(played)
			c.h:step(1 / 60, 2)
			Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
			c.h:settle(2)
			expect(sel(c)).toBe(c.PC.entryButton("Squishydex"))
			expect(table.find(played, "listEnd")).toBeNil()
			clean(c)
		end)
	end)
	-- v2.0 (lot B2, étape 2) : écran Améliorations (fenêtre nue, construit au premier instantané)
	describe("PanelController › écran Améliorations (lot B2)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)

		it(
			"interrupteur coupé : aucune instance, open ne fait rien (ni son), aucune intention v2.0",
			function()
				local c = S.client({})
				local Audio = TvAudit.mod(c.h, "Controllers.AudioController")
				local sounds = {}
				local play = Audio.play
				Audio.play = function(name, ...)
					table.insert(sounds, name)
					return play(name, ...)
				end
				expect(c.PC.available("Upgrades")).toBe(false)
				c.PC.open("Upgrades", "ranch")
				c.PC.open("Upgrades", "spendFirst")
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				expect(c.PC.menuOpen()).toBe(false)
				expect(#sounds).toBe(0)
				expect(c.PC.window("Upgrades")).toBeNil()
				for _, d in c.h.localPlayer.PlayerGui:GetDescendants() do
					expect(d.Name == "Panel_Upgrades").toBe(false)
				end
				-- les autres panneaux répondent comme avant
				expect(c.PC.available("Ranch")).toBe(true)
				expect(c.PC.available("Nope")).toBe(false)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it("instantané reçu : construit pendant le chargement, ouvert sur demande, fenêtre nue", function()
			local c = S.client({ snap = S.snap(1) })
			expect(c.PC.available("Upgrades")).toBe(true)
			local win = c.PC.window("Upgrades")
			expect(win ~= nil).toBe(true)
			expect(win.Visible).toBe(false)
			-- fenêtre nue (D5) : ni en-tête standard ni titre centré, le corps est tout le panneau
			expect(win:FindFirstChild("Header")).toBeNil()
			expect(win.Body.Size.Y.Offset).toBe(860)
			c.PC.open("Upgrades", "workshop")
			TvAudit.tick(c.h, 0.5)
			expect(c.PC.current()).toBe("Upgrades")
			expect(c.Up.currentTab()).toBe("workshop")
			expect(win.Visible).toBe(true)
			-- même panneau, autre onglet : l'onglet change, rien n'est refermé
			c.PC.open("Upgrades", "ranch")
			TvAudit.tick(c.h, 0.5)
			expect(c.Up.currentTab()).toBe("ranch")
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("L2 / R2 : Ranch → Améliorations → Squishydex, et retour", function()
			local c = S.client({ snap = S.snap(1) })
			c.PC.open("Ranch")
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
			expect(c.PC.current()).toBe("Upgrades")
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonR2)
			expect(c.PC.current()).toBe("Squishydex")
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonL2)
			expect(c.PC.current()).toBe("Upgrades")
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonL2)
			expect(c.PC.current()).toBe("Ranch")
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it(
			"« Dépenser d'abord » : onglet Ranch PAR-DESSUS l'aperçu, première ligne gardée payable, ○ y revient",
			function()
				local profile = {
					squishies = { a = TvAudit.squishy(1, { z = 20000 }), b = TvAudit.squishy(2, { z = 50 }) },
					growth = { G = 0, g = 1, t = 1800000000 },
				}
				-- Enclos au maximum (gardé, pas payable), Lit douillet payable (gardé), Monuments fermés (Tapis
				-- < 12) : la sélection va au Lit douillet, pas à la première ligne gardée
				local function prof(p)
					p.tiles.pens = 14
					p.tiles.cozyBed = false
					p.coins = 1e12
				end
				local c = S.client({ snap = S.snap(1, prof), profile = profile })
				c.PC.open("SplorchPreview")
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.current()).toBe("SplorchPreview")
				c.PC.open("Upgrades", "spendFirst")
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.current()).toBe("Upgrades")
				expect(c.PC.isOpen("SplorchPreview")).toBe(true)
				expect(c.Up.currentTab()).toBe("ranch")
				expect(sel(c)).toBe(c.Up._row("cozyBed"))
				expect(c.Up._row("cozyBed"):GetAttribute("State")).toBe("ready")
				-- ordre des lignes inchangé (jamais retrié pour « Dépenser d'abord »)
				expect(c.Up._shown("ranch")[1]).toBe("snack")
				-- ○ : retour à l'aperçu (toujours ouvert dessous)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				expect(c.PC.current()).toBe("SplorchPreview")
				-- rien de gardé payable : la première ligne gardée (Enclos, au maximum)
				S.patch(
					c,
					S.snap(2, function(p)
						prof(p)
						p.coins = 0
					end)
				)
				c.PC.open("Upgrades", "spendFirst")
				TvAudit.tick(c.h, 0.5)
				expect(sel(c)).toBe(c.Up._row("pens"))
				expect(c.Up._row("pens"):GetAttribute("State")).toBe("max")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
