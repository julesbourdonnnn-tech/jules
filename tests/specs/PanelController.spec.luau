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
		-- lot B3, étape 6 (journal B3-72) : les enfants d'un libellé à UIPadding sont posés dans la zone du
		-- texte (moteur et harnais Layout) ; le cœur dessiné de la pastille (lot B2, D18) était posé à
		-- (0, 6) avec PaddingLeft 28 : dessiné à 34-54 px, sur le nombre (zone du texte 28-54 px)
		it("pastille des jumeaux : le cœur dessiné reste à gauche du nombre, jamais dessus", function()
			local Layout = require("../harness/Layout")
			local c = setup({
				profile = {
					squishies = {
						a = TvAudit.squishy(1, { z = 10 }),
						b = TvAudit.squishy(1, { z = 12 }),
						d = TvAudit.squishy(2, { z = 10 }),
						e = TvAudit.squishy(2, { z = 11 }),
					},
				},
			})
			c.PC.toggleMenu()
			TvAudit.tick(c.h, 0.5)
			local badge = c.PC.entryButton("Ranch").Badge
			expect(badge.Visible).toBe(true)
			expect(badge.Text).toBe("2")
			Layout.apply(c.h)
			local b = Layout.rect(badge)
			local heart = Layout.rect(badge.Heart)
			local pad = badge:FindFirstChildOfClass("UIPadding")
			local textLeft = b.x + pad.PaddingLeft.Offset
			-- le cœur dans la marge gauche de la pastille, le nombre à sa droite
			expect(heart.x >= b.x).toBe(true)
			expect(heart.x + heart.w <= textLeft).toBe(true)
			expect(math.abs((heart.y + heart.h / 2) - (b.y + b.h / 2)) <= 1).toBe(true)
			clean(c)
		end)

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

	-- v2.0 (lot B2, étape 3 ; D11, décision N23 du propriétaire) : MenuActivity — rail ou panneau
	-- ouvert, navigation dedans ; une au plus toutes les 20 s ; seulement si MON ranch porte Helpers > 0
	describe("PanelController › MenuActivity (lot B2, D11)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)

		local function activity(c)
			return #TvAudit.sent(c.h, "MenuActivity")
		end

		local function browse(c, seconds)
			-- navigation à la croix dans le rail ou le panneau, toutes les 0,5 s
			local t = 0
			while t < seconds do
				Gamepad.tap(c.h, Enum.KeyCode.DPadDown)
				S.run(c, 0.5)
				t += 0.5
			end
		end

		it(
			"interrupteur coupé (aucun attribut Helpers) : jamais envoyée, ni au rail, ni aux panneaux",
			function()
				local c = S.client({})
				c.PC.toggleMenu()
				S.run(c, 0.5)
				browse(c, 3)
				c.PC.open("Ranch")
				S.run(c, 0.5)
				browse(c, 25)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				S.run(c, 0.5)
				expect(activity(c)).toBe(0)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"Helpers = 0 ou attribut absent : rien ; Helpers > 0 : à l'ouverture, puis au plus une toutes les 20 s",
			function()
				local c = S.client({ snap = S.snap(1), ranch = { Helpers = 0 } })
				c.PC.toggleMenu()
				S.run(c, 0.5)
				browse(c, 2)
				expect(activity(c)).toBe(0)
				c.PC.closeAll()
				S.run(c, 0.5)
				-- des Plopettes : l'ouverture du rail envoie
				c.model:SetAttribute("Helpers", 2)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(activity(c)).toBe(1)
				-- navigation continue pendant 19 s : rien de plus ; à 20 s : une de plus
				browse(c, 18.5)
				expect(activity(c)).toBe(1)
				browse(c, 2)
				expect(activity(c)).toBe(2)
				-- panneau ouvert, onglets (L1 / R1), défilement : jamais plus d'une toutes les 20 s
				c.PC.open("Upgrades", "ranch")
				S.run(c, 0.5)
				for _ = 1, 10 do
					Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
					S.run(c, 0.5)
					Gamepad.stick(c.h, Enum.KeyCode.Thumbstick2, roblox.Vector2.new(0, -1))
					S.run(c, 0.5)
				end
				expect(activity(c)).toBe(2)
				S.run(c, 10)
				-- mode (□) et achat comptent comme navigation
				Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
				S.run(c, 0.5)
				expect(activity(c)).toBe(3)
				-- jeu (rien d'ouvert) : rien, même avec des Plopettes
				c.PC.closeAll()
				S.run(c, 25)
				expect(activity(c)).toBe(3)
				-- l'attribut disparaît (interrupteur coupé en direct) : plus rien
				c.model:SetAttribute("Helpers", nil)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				browse(c, 25)
				expect(activity(c)).toBe(3)
				S.clean(c, expect)
			end
		)
	end)
	-- =========================================================================================
	-- v2.0 (lot B2, étape 4 ; N9, D14-D18) : rail v2.0 et entrée de renaissance
	-- =========================================================================================
	describe("PanelController › rail v2.0 (lot B2, étape 4)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local FontCmap = require("../harness/FontCmap")
		local S = UpgradeScreen.new(T.Harness)
		local CMAPS = FontCmap.load()
		local NOW = 1800000000
		local BIG = { a = TvAudit.squishy(1, { z = 1e15 }) }
		local FROZEN = { G = 0, g = 0, t = NOW }

		local function regain(r)
			return function(p)
				p.ascend = 1
				p.R = r
				p.bestR = 15
			end
		end

		local function railCheck(c, v2)
			local L = S.Layout
			for _, entry in c.PC.entries() do
				local b = c.PC.entryButton(entry)
				-- symboles « ✦ ♥ ★ ✓ ⚙ » DESSINÉS (Hud/Icons), « ! # $ » de la police (règle 18, D18)
				local symbol = b.Icon.Symbol
				if entry == "Pending" or entry == "Leaderboards" or entry == "Shop" then
					expect({ entry = entry, text = symbol:IsA("TextLabel") }).toEqual({
						entry = entry,
						text = true,
					})
				else
					expect({ entry = entry, icon = symbol:GetAttribute("Icon") ~= "" }).toEqual({
						entry = entry,
						icon = true,
					})
				end
				for _, d in b:GetDescendants() do
					if d:IsA("TextLabel") and d.Text ~= "" then
						expect({ text = d.Text, missing = FontCmap.missing(CMAPS, d.Text) }).toEqual({
							text = d.Text,
							missing = {},
						})
					end
				end
				local h = if v2 then L.HudV2.Rail.size else nil
				if h then
					expect({ entry = entry, h = b.Size.Y.Offset, icon = b.Icon.Size.X.Offset }).toEqual({
						entry = entry,
						h = h,
						icon = L.HudV2.Rail.icon,
					})
				else
					expect(b.Icon.Size.X.Offset).toBe(L.HudContent.menuRail.icon)
				end
			end
		end

		it(
			"interrupteur coupé : rail de la v1.3 (icône 56, écart 12), symboles dessinés, ni Améliorations ni maintien",
			function()
				local c = S.client({ profile = { squishies = BIG, growth = FROZEN } })
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(c.PC.entries()).toEqual({
					"SplorchPreview",
					"Ranch",
					"Squishydex",
					"Objectives",
					"Leaderboards",
					"Settings",
				})
				expect(c.PC.entryButton("Upgrades")).toBeNil()
				expect(c.PC.entryButton("SplorchPreview").Label.Text).toBe("Grand Splorch")
				expect(c.PC.entryButton("SplorchPreview"):FindFirstChild("HoldFill")).toBeNil()
				expect(c.PC.entryButton("Ranch").Icon.Symbol:GetAttribute("Icon")).toBe("heart")
				expect(c.PC.entryButton("Squishydex").Icon.Symbol:GetAttribute("Icon")).toBe("star")
				expect(c.PC.entryButton("Objectives").Icon.Symbol:GetAttribute("Icon")).toBe("check")
				expect(c.PC.entryButton("Settings").Icon.Symbol:GetAttribute("Icon")).toBe("gear")
				local rail = c.PC.entryButton("Ranch").Parent
				expect(rail:GetAttribute("Gap")).toBe(S.Layout.HudContent.menuRail.gap)
				railCheck(c, false)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"v2.0 : Améliorations sous Ranch (flèche dessinée, aucune pastille), boutons de 80, écart 16, icône 48 ; ✕ l'ouvre",
			function()
				local c = S.client({
					snap = S.snap(1),
					profile = { squishies = { a = TvAudit.squishy(1, { z = 10 }) }, growth = FROZEN },
				})
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(c.PC.entries()).toEqual({
					"Ranch",
					"Upgrades",
					"Squishydex",
					"Objectives",
					"Leaderboards",
					"Settings",
				})
				local b = c.PC.entryButton("Upgrades")
				expect(b.Label.Text).toBe("Upgrades")
				expect(b.Icon.Symbol:GetAttribute("Icon")).toBe("arrowUp")
				expect(b.Badge.Visible).toBe(false)
				expect(b.LayoutOrder > c.PC.entryButton("Ranch").LayoutOrder).toBe(true)
				expect(b.LayoutOrder < c.PC.entryButton("Squishydex").LayoutOrder).toBe(true)
				expect(b.Parent:GetAttribute("Gap")).toBe(16)
				railCheck(c, true)
				S.select(c, b)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.5)
				expect(c.PC.current()).toBe("Upgrades")
				S.clean(c, expect)
			end
		)

		it(
			"entrée de renaissance nommée : Grand Splorch, Jelly Ascend (aperçu sur l'onglet « ascend »), Petit Splorch",
			function()
				local c = S.client({
					snap = S.snap(1),
					profile = { squishies = BIG, growth = FROZEN },
					ranch = { AscendReady = true },
				})
				local Preview = TvAudit.mod(c.h, "UI.Panels.SplorchPreview")
				local tabs = {}
				local open = Preview.open
				Preview.open = function(tab)
					table.insert(tabs, tostring(tab))
					return open(tab)
				end
				c.PC.toggleMenu()
				S.run(c, 0.5)
				-- Grand Splorch prêt : son nom, même avec l'Ascension prête (une renaissance à la fois)
				expect(c.PC.entries()[1]).toBe("SplorchPreview")
				expect(c.PC.entryButton("SplorchPreview").Label.Text).toBe("Grand Splorch")
				expect(c.PC.rebirth()).toBe("splorch")
				c.PC.closeAll()
				S.run(c, 0.5)
				-- plus prêt, Ascension prête : « Jelly Ascend », ✕ ouvre l'aperçu sur l'Ascension
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ squishies = { a = TvAudit.squishy(1, { z = 10 }) } },
					{}
				)
				S.run(c, 0.5)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				local entry = c.PC.entryButton("SplorchPreview")
				expect(entry.Visible).toBe(true)
				expect(entry.Label.Text).toBe("Jelly Ascend")
				expect(S.selected(c)).toBe(entry)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.5)
				expect(c.PC.current()).toBe("SplorchPreview")
				expect(tabs[#tabs]).toBe("ascend")
				c.PC.closeAll()
				S.run(c, 0.5)
				-- remontée et prestige de boucle prêt : « Petit Splorch »
				c.model:SetAttribute("AscendReady", false)
				S.patch(c, S.snap(2, regain(3)))
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { squishies = BIG, R = 3 }, {})
				S.run(c, 0.5)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(c.PC.entryButton("SplorchPreview").Label.Text).toBe("Petit Splorch")
				expect(c.PC.rebirth()).toBe("petit")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"Petit Splorch : ✕ maintenu 1,5 s = GrandSplorch une fois ; appui court = aperçu ; jamais confirmé par un ✕ tenu d'avant le rail ; premier de la remontée : aucun maintien",
			function()
				local c = S.client({
					snap = S.snap(1, regain(3)),
					profile = {
						R = 3,
						squishies = BIG,
						growth = FROZEN,
						onboarding = { step = 11, done = true, demoDone = true },
					},
				})
				local function grand()
					return #TvAudit.sent(c.h, "GrandSplorch")
				end
				-- ✕ tenu en jeu (saut), puis △ : le rail s'ouvre sur l'entrée ; ✕ tenu 3 s de plus : rien
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonY)
				S.run(c, 0.1)
				local entry = c.PC.entryButton("SplorchPreview")
				expect(c.PC.menuOpen()).toBe(true)
				expect(S.selected(c)).toBe(entry)
				expect(entry.Label.Text).toBe("Petit Splorch")
				expect(entry.Glyph.Visible).toBe(true)
				S.run(c, 3)
				Gamepad.release(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.3)
				expect(grand()).toBe(0)
				expect(c.PC.isOpen("SplorchPreview")).toBe(false)
				-- vrai maintien de 1,6 s : GrandSplorch(false, « a ») une fois, le rail se ferme
				S.hold(c, entry, 1.6)
				expect(grand()).toBe(1)
				local sent = TvAudit.sent(c.h, "GrandSplorch")[1]
				expect(sent[1]).toBe(false)
				expect(sent[2]).toBe("a")
				expect(c.PC.menuOpen()).toBe(false)
				-- appui court : l'aperçu, rien d'envoyé
				c.PC.toggleMenu()
				S.run(c, 0.5)
				S.hold(c, entry, 0.2)
				expect(c.PC.current()).toBe("SplorchPreview")
				expect(grand()).toBe(1)
				c.PC.closeAll()
				S.run(c, 0.5)
				-- premier Petit Splorch de la remontée (r = Prestige.startR(1, 0) = 0) : ✕ ouvre l'aperçu,
				-- même tenu 2 s ; aucun glyphe de maintien
				S.patch(c, S.snap(2, regain(0)))
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { R = 0 }, {})
				S.run(c, 0.5)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(entry.Label.Text).toBe("Petit Splorch")
				expect(entry.Glyph.Visible).toBe(false)
				S.hold(c, entry, 2)
				expect(grand()).toBe(1)
				expect(c.PC.current()).toBe("SplorchPreview")
				S.clean(c, expect)
			end
		)
	end)

	-- =========================================================================================
	-- Lot B3, étape 1, D4 (relecture du lot B2) : le serveur garde AscendReady vrai jusqu'à l'éclatement
	-- (4,0 s) : sans garde, l'entrée de renaissance redevenait « Jelly Ascend » pendant MA propre
	-- Ascension (et ✕ pouvait renvoyer l'intention). Chemin v2.0 (instantané reçu) : aucune renaissance
	-- tant que MON prestige est dans la file ou en cours (MetaFlags.myPrestige) ; v1.3 inchangée.
	describe("PanelController › renaissance pendant MON prestige (lot B3, D4)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local NOW = 1800000000
		local BIG = { a = TvAudit.squishy(1, { z = 1e15 }) }
		local SMALL = { a = TvAudit.squishy(1, { z = 10 }) }
		local FROZEN = { G = 0, g = 0, t = NOW }
		local ME = 1 -- joueur local du harnais client

		-- EventState complet ; `spectacle` : { current?, queue } ; `v2` : features.v2 (nil : absente)
		local function eventState(spectacle, v2)
			return {
				rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
				mega = {
					phase = "idle",
					index = 0,
					landsAt = 0,
					endsAt = 0,
					target = 0,
					points = 0,
					species = 1,
					moon = false,
					result = "",
				},
				golden = { active = false, id = 0, endsAt = 0 },
				moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
				gauge = { points = 0, target = 1000, partyUntil = 0, restUntil = 0 },
				boost = { kind = "", untilT = 0, byName = "" },
				spectacle = spectacle or { queue = {} },
				features = {
					boopRush = "on",
					megaSquish = true,
					golden = true,
					jellyMoon = true,
					gauge = true,
					clips = true,
					costume = "",
					diagnostics = true,
					v2 = v2,
				},
				offset = 0,
			}
		end

		local V2 = { JellyAscend = true, PetitSplorch = true, RecordR = true, Confetti = true }

		local function show(kind, userId)
			return {
				current = {
					kind = kind,
					userId = userId,
					startedAt = NOW,
					burstAt = NOW + 4,
					endsAt = NOW + 10,
					level = 16,
				},
				queue = {},
			}
		end

		local function queued(kind, userId)
			return {
				queue = {
					{ kind = kind, userId = userId, startAt = NOW + 20, slot = 1, position = 1, eta = 20 },
				},
			}
		end

		local function send(c, spectacle, v2)
			c.h:fireClient("ReplicatedStorage.Remotes.EventState", eventState(spectacle, v2))
			S.run(c, 0.2)
		end

		local function railEntry(c)
			c.PC.closeAll()
			S.run(c, 0.5)
			c.PC.toggleMenu()
			S.run(c, 0.5)
			local b = c.PC.entryButton("SplorchPreview")
			local shown = b ~= nil and b.Visible and table.find(c.PC.entries(), "SplorchPreview") ~= nil
			local label = if shown then b.Label.Text else nil
			c.PC.closeAll()
			S.run(c, 0.5)
			return label
		end

		it(
			"Jelly Ascend : MA Ascension dans la file puis en cours (AscendReady encore vrai) : aucune entrée « Jelly Ascend » ; celle d'un autre ou la danse : rien ne change ; après l'éclatement : normal",
			function()
				local c = S.client({
					snap = S.snap(1),
					profile = { squishies = SMALL, growth = FROZEN },
					ranch = { AscendReady = true },
				})
				send(c, nil, V2)
				expect(c.PC.rebirth()).toBe("ascend")
				expect(railEntry(c)).toBe("Jelly Ascend")
				-- MA Jelly Ascend dans la file
				send(c, queued("ascend", ME), V2)
				expect(c.PC.rebirth()).toBeNil()
				expect(railEntry(c)).toBeNil()
				-- MA Jelly Ascend en cours, AscendReady toujours vrai (jusqu'à l'éclatement)
				send(c, show("ascend", ME), V2)
				expect(c.model:GetAttribute("AscendReady")).toBe(true)
				expect(c.PC.rebirth()).toBeNil()
				expect(railEntry(c)).toBeNil()
				-- celle d'un autre joueur, la danse de Big Plop : MON Ascension reste proposée
				send(c, show("ascend", 77), V2)
				expect(c.PC.rebirth()).toBe("ascend")
				send(c, show("dance", 0), V2)
				expect(c.PC.rebirth()).toBe("ascend")
				send(c, queued("splorch", 77), V2)
				expect(c.PC.rebirth()).toBe("ascend")
				-- après l'éclatement : AscendReady faux, spectacle fini : rien ; puis boucle prête : normal
				c.model:SetAttribute("AscendReady", false)
				send(c, nil, V2)
				expect(c.PC.rebirth()).toBeNil()
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { squishies = BIG }, {})
				S.run(c, 0.5)
				expect(c.PC.rebirth()).toBe("splorch")
				expect(railEntry(c)).toBe("Grand Splorch")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"chemin v2.0 : MON Grand Splorch dans la file puis en cours : aucune entrée de renaissance (aucun second envoi possible)",
			function()
				local c = S.client({
					snap = S.snap(1),
					profile = { squishies = BIG, growth = FROZEN },
				})
				send(c, nil, V2)
				expect(c.PC.rebirth()).toBe("splorch")
				send(c, queued("splorch", ME), V2)
				expect(c.PC.rebirth()).toBeNil()
				expect(railEntry(c)).toBeNil()
				send(c, show("splorch", ME), V2)
				expect(c.PC.rebirth()).toBeNil()
				expect(railEntry(c)).toBeNil()
				-- fini (EventState sans spectacle) : le Grand Splorch revient s'il est encore prêt
				send(c, nil, V2)
				expect(c.PC.rebirth()).toBe("splorch")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"client de la v1.3 (aucun instantané, aucune clé v2) : MON Grand Splorch dans la file ne change rien (comportement de la v1.3)",
			function()
				local c = S.client({ profile = { squishies = BIG, growth = FROZEN } })
				send(c, nil, nil)
				expect(c.PC.rebirth()).toBe("splorch")
				send(c, queued("splorch", ME), nil)
				expect(c.PC.rebirth()).toBe("splorch")
				expect(railEntry(c)).toBe("Grand Splorch")
				send(c, show("splorch", ME), nil)
				expect(c.PC.rebirth()).toBe("splorch")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
