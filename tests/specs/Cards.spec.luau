--!nocheck
-- Cards (paquet client-hud ; docs/04 §10.3, §13.5, §14.2 ; GDD §10.3, §4.21.1) : une seule carte à
-- l'écran, ordre de Config/Layout.Cards.Order ; carte non bloquante 8 s à droite, jamais la sélection,
-- puis rangée (pastille « ! ») ; rouverte en fenêtre par le menu (« Pas ce joueur » → RefuseBooper,
-- ○ la range, △ aussi) ; Requested vers PanelController ; carte du choix au calme seulement, garde de
-- 0,6 s, « Je reste tranquille » par défaut, ○ = Cozy, 20 s → fermée sans intention ; UiSeen ;
-- aucune touche liée par Cards ; charges hostiles sans erreur. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local profile = opts.profile or {}
		profile.onboarding = profile.onboarding or { step = 11, done = true, demoDone = true }
		local h = TvAudit.client({ profile = profile, now = opts.now })
		local C = TvAudit.mod(h, "UI.Cards")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		return h, C, Clock
	end

	local function celebrate(h, kind, data)
		h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
		h:settle(1)
	end

	local function kindsOf(list)
		local out = {}
		for _, c in list do
			table.insert(out, c.kind)
		end
		return out
	end

	-- monde simulé pour le calme de la carte du choix : ranch 1, rien de porté
	local function world(h, opts)
		opts = opts or {}
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local ranch = { slot = 1, userId = 1, mode = "cozy", carry = opts.carry or "", ride = "", saddle = 0 }
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return if slot == 1 then ranch else nil
		end
		WSC.creatures = function()
			return {}
		end
		local inside = WorldLayout.toWorld(1, Vector3.new(0, 3, 36))
		h:moveTo(h.localPlayer, opts.pos or inside)
		return ranch, inside
	end

	describe("Cards › cartes non bloquantes", function()
		it("une seule à l'écran, dans l'ordre de la file ; 8 s puis rangée dans « ! »", function()
			local h, C, Clock = setup()
			celebrate(h, "dexNew", { species = 3, mutation = 0, star = 0 })
			expect(C.current().kind).toBe("dex")
			celebrate(h, "objectivesCard", { day = 1 })
			celebrate(h, "booped", { uid = "u5", species = 2, booperId = 77 })
			expect(C.current().kind).toBe("dex") -- une seule à la fois
			expect(C.queued()).toBe(2)
			Clock.advance(8.01)
			C._step()
			expect(C.current().kind).toBe("booped") -- avant les objectifs (Layout.Cards.Order)
			Clock.advance(8.01)
			C._step()
			expect(C.current().kind).toBe("objectives")
			Clock.advance(8.01)
			C._step()
			expect(C.current()).toBeNil()
			expect(kindsOf(C.pending())).toEqual({ "booped", "objectives", "dex" })
			clean(h)
		end)

		it("jamais la sélection de la manette ; la carte affichée compte déjà dans « ! »", function()
			local h, C = setup()
			local changed = 0
			C.Changed:Connect(function()
				changed += 1
			end)
			celebrate(h, "booped", { uid = "u5", species = 2, booperId = 77 })
			expect(h.game.GuiService.SelectedObject).toBeNil()
			local side = C.frame("side")
			expect(side.Visible).toBe(true)
			expect(side.Selectable).toBe(false)
			expect(side.Title.Text).toBe("Wibble is running away!")
			expect(kindsOf(C.pending())).toEqual({ "booped" })
			expect(changed >= 1).toBe(true)
			-- pastille « ! » de la puce Menu
			local HUD = TvAudit.mod(h, "UI.HUD")
			expect(HUD.element("menuChip"):GetAttribute("Bang")).toBe(true)
			clean(h)
		end)

		it("une fenêtre (panneau) passe devant : la carte affichée se range aussitôt", function()
			local h, C = setup()
			celebrate(h, "sleepy", { minutes = 60 })
			expect(C.current().kind).toBe("sleepy")
			TvAudit.mod(h, "UI.PanelController").open("Ranch")
			C._step()
			expect(C.current()).toBeNil()
			expect(kindsOf(C.pending())).toEqual({ "sleepy" })
			clean(h)
		end)

		it(
			"une seule carte d'objectifs, de « Plop a sommeil » : la nouvelle remplace l'ancienne",
			function()
				local h, C, Clock = setup()
				celebrate(h, "sleepy", { minutes = 60 })
				Clock.advance(8.01)
				C._step()
				celebrate(h, "sleepy", { minutes = 120 })
				Clock.advance(8.01)
				C._step()
				expect(kindsOf(C.pending())).toEqual({ "sleepy" })
				clean(h)
			end
		)
	end)

	describe("Cards › carte rouverte depuis le menu", function()
		it(
			"« booped » : △ → ✕ (entrée « ! ») → « Continuer » sélectionné → « Pas ce joueur »",
			function()
				local h, C, Clock = setup()
				celebrate(h, "booped", { uid = "u5", species = 2, booperId = 77 })
				Clock.advance(8.01)
				C._step()
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				local PC = TvAudit.mod(h, "UI.PanelController")
				PC.toggleMenu()
				expect(h.game.GuiService.SelectedObject).toBe(PC.entryButton("Pending"))
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				local id = C.current().id
				expect(C.current().kind).toBe("booped")
				expect(FG.isOpen("card:" .. id)).toBe(true)
				local buttons = C.buttons()
				expect(#buttons).toBe(2)
				expect(h.game.GuiService.SelectedObject).toBe(buttons[1])
				expect(buttons[1].Label.Text).toBe("Continue")
				expect(buttons[2].Label.Text).toBe("Not this player")
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				expect(h.game.GuiService.SelectedObject).toBe(buttons[2])
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "RefuseBooper")[1][1]).toBe(77)
				expect(FG.isOpen("card:" .. id)).toBe(false)
				expect(#C.pending()).toBe(0)
				-- la sélection revient au rail (le menu est toujours ouvert)
				expect(FG.isOpen("menu")).toBe(true)
				clean(h)
			end
		)

		it("○ referme la carte rouverte et la garde rangée ; △ (le menu se ferme) aussi", function()
			local h, C, Clock = setup()
			celebrate(h, "booped", { uid = "u5", species = 2, booperId = 77 })
			Clock.advance(8.01)
			C._step()
			local FG = TvAudit.mod(h, "UI.FocusGuard")
			local PC = TvAudit.mod(h, "UI.PanelController")
			PC.toggleMenu()
			TvAudit.tick(h, 0.5)
			local id = C.pending()[1].id
			C.open(id)
			expect(FG.isOpen("card:" .. id)).toBe(true)
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(FG.isOpen("card:" .. id)).toBe(false)
			expect(kindsOf(C.pending())).toEqual({ "booped" })
			expect(FG.isOpen("menu")).toBe(true)
			C.open(id)
			TvAudit.tick(h, 0.5)
			PC.toggleMenu() -- △ : ferme tout
			expect(FG.anyOpen()).toBe(false)
			expect(kindsOf(C.pending())).toEqual({ "booped" })
			expect(C.current()).toBeNil()
			clean(h)
		end)

		it('« Voir » : Requested(sorte, "open") pour PanelController, carte retirée', function()
			local h, C, Clock = setup()
			local requested = {}
			C.Requested:Connect(function(kind, action)
				table.insert(requested, kind .. ":" .. action)
			end)
			celebrate(h, "objectivesCard", { day = 1 })
			Clock.advance(8.01)
			C._step()
			C.open(C.pending()[1].id)
			local buttons = C.buttons()
			expect(buttons[1].Label.Text).toBe("See")
			TvAudit.tick(h, 0.5)
			h.game.GuiService.SelectedObject = buttons[1]
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			expect(requested).toEqual({ "objectives:open" })
			expect(#C.pending()).toBe(0)
			-- PanelController (plus tardif) ouvre le panneau Objectifs
			expect(TvAudit.mod(h, "UI.PanelController").current()).toBe("Objectives")
			clean(h)
		end)

		it(
			"carte « Wibble revient toujours ! » (premier boop subi) : Continuer, Mode Cozy, Pas ce joueur",
			function()
				local h, C, Clock = setup()
				celebrate(h, "booped", { uid = "u9", species = 2, booperId = 55 })
				celebrate(h, "ownerReturn", {
					uid = "u9",
					species = 2,
					coins = 1200,
					catcherId = 66,
					catcherName = "Noah",
					firstBoop = true,
				})
				Clock.advance(8.01)
				C._step()
				expect(C.current().kind).toBe("postBoop")
				Clock.advance(8.01)
				C._step()
				local postBoop = nil
				for _, c in C.pending() do
					if c.kind == "postBoop" then
						postBoop = c
					end
				end
				C.open(postBoop.id)
				local buttons = C.buttons()
				expect(#buttons).toBe(3)
				TvAudit.tick(h, 0.5)
				h.game.GuiService.SelectedObject = buttons[2]
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "SetMode")[1][1]).toBe(false)
				-- « Pas ce joueur » vise le boopeur (55), pas l'attrapeur
				C.open(C.pending()[1].id)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "RefuseBooper")[1][1]).toBe(55)
				clean(h)
			end
		)
	end)

	describe("Cards › carte du choix Rush / Cozy", function()
		it("attend le calme : dans son ranch, immobile 1,5 s, rien de porté", function()
			local h, C, Clock = setup()
			local ranch, inside = world(h, { carry = "u1" })
			h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
			h:settle(1)
			C._step()
			Clock.advance(2)
			C._step()
			expect(C.modeWaiting()).toBe(true) -- porte un squishy
			ranch.carry = ""
			h:moveTo(h.localPlayer, Vector3.new(0, 3, 0)) -- sur la place, hors du ranch
			C._step()
			Clock.advance(2)
			C._step()
			expect(C.modeWaiting()).toBe(true)
			h:moveTo(h.localPlayer, inside)
			C._step()
			Clock.advance(1)
			C._step()
			expect(C.modeWaiting()).toBe(true) -- pas encore immobile 1,5 s
			Clock.advance(0.6)
			C._step()
			expect(C.modeWaiting()).toBe(false)
			expect(C.current().kind).toBe("mode")
			clean(h)
		end)

		it("jamais pendant un Rush ni juste avant ; jamais derrière l'écran de retour", function()
			local h, C, Clock = setup({ now = 1800000300 - 30 }) -- Rush dans 30 s
			world(h)
			h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
			h:settle(1)
			C._step()
			Clock.advance(2)
			C._step()
			expect(C.modeWaiting()).toBe(true)
			TvAudit.mod(h, "UI.ReturnScreen").show({
				seconds = 900,
				uid = "u1",
				species = 1,
				grew = 0,
				pot = 0,
				splorchReady = false,
				nearlyReady = false,
			})
			Clock.advance(90 + 28) -- Rush fini, prochain dans ~9 min : calme, mais l'écran de retour est ouvert
			C._step()
			Clock.advance(2)
			C._step()
			expect(C.modeWaiting()).toBe(true)
			TvAudit.mod(h, "UI.FocusGuard").closeNow("return")
			C._step()
			Clock.advance(2)
			C._step()
			expect(C.current().kind).toBe("mode")
			clean(h)
		end)

		it("garde de 0,6 s, « Je reste tranquille » par défaut, UiSeen, cardIn ; ○ = Cozy", function()
			local h, C, Clock = setup()
			world(h)
			local played = {}
			TvAudit.mod(h, "Util.Haptics").Played:Connect(function(name)
				table.insert(played, name)
			end)
			h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
			h:settle(1)
			C._step()
			Clock.advance(1.6)
			C._step()
			local FG = TvAudit.mod(h, "UI.FocusGuard")
			local id = C.current().id
			expect(FG.isOpen("card:" .. id)).toBe(true)
			expect(FG.top().blocking).toBe(true)
			local buttons = C.buttons()
			expect(h.game.GuiService.SelectedObject).toBe(buttons[2])
			expect(buttons[2].Label.Text).toBe("I stay cozy")
			expect(TvAudit.sent(h, "UiSeen")[1][1]).toBe("modeCard")
			expect(table.find(played, "cardIn") ~= nil).toBe(true)
			-- ✕ martelé pendant la garde : rien n'est choisi
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			Clock.advance(0.4)
			C._step()
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(#TvAudit.sent(h, "SetMode")).toBe(0)
			expect(FG.isOpen("card:" .. id)).toBe(true)
			Clock.advance(0.3)
			C._step()
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(TvAudit.sent(h, "SetMode")[1][1]).toBe(false)
			expect(FG.isOpen("card:" .. id)).toBe(false)
			expect(C.current()).toBeNil()
			clean(h)
		end)

		it(
			"« Je joue au BOOP RUSH » envoie SetMode(true) ; sans réponse en 20 s, fermée sans intention",
			function()
				local h, C, Clock = setup()
				world(h)
				h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
				h:settle(1)
				C._step()
				Clock.advance(1.6)
				C._step()
				Clock.advance(0.7)
				C._step()
				local buttons = C.buttons()
				h.game.GuiService.SelectedObject = buttons[1]
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "SetMode")[1][1]).toBe(true)
				-- deuxième client : le délai
				local h2, C2, Clock2 = setup()
				world(h2)
				h2:fireClient("ReplicatedStorage.Remotes.ModePrompt")
				h2:settle(1)
				C2._step()
				Clock2.advance(1.6)
				C2._step()
				expect(C2.current().kind).toBe("mode")
				Clock2.advance(20.01)
				C2._step()
				expect(C2.current()).toBeNil()
				expect(#TvAudit.sent(h2, "SetMode")).toBe(0)
				expect(TvAudit.mod(h2, "UI.FocusGuard").anyOpen()).toBe(false)
				clean(h)
				clean(h2)
			end
		)
	end)

	describe("Cards › règles", function()
		it("Cards ne lie aucune touche (ContextActionService)", function()
			local h, C, Clock = setup()
			world(h)
			local before = {}
			for name in h.actionBindings do
				before[name] = true
			end
			celebrate(h, "booped", { uid = "u5", species = 2, booperId = 77 })
			Clock.advance(8.01)
			C._step()
			C.open(C.pending()[1].id)
			for name in h.actionBindings do
				expect({ name = name, card = string.find(string.lower(name), "card", 1, true) ~= nil }).toEqual({
					name = name,
					card = false,
				})
			end
			local src = require("@lune/fs").readFile("src/client/UI/Cards.luau")
			expect(string.find(src, "BindAction", 1, true)).toBeNil()
			clean(h)
		end)

		it("charges hostiles : aucune erreur, aucune carte fantôme", function()
			local h, C = setup()
			local bad = {
				{ kind = "booped", data = "x" },
				{ kind = "booped", data = { uid = string.rep("u", 5000), species = 0 / 0, booperId = -1 } },
				{ kind = "dexNew", data = { species = math.huge, mutation = "x" } },
				{ kind = "ownerReturn", data = { firstBoop = true, coins = 0 / 0 } },
				{ kind = 42, data = {} },
				"rien",
			}
			for _, p in bad do
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", p)
				h:settle(1)
			end
			expect(C.push(nil)).toBe("")
			expect(C.push({ kind = "inconnue" })).toBe("")
			expect(C.push({ kind = "return", data = {} })).toBe("")
			local id = C.push({ id = string.rep("z", 1000), kind = "clip", blocking = true, data = "x" })
			expect(id ~= "" and #id <= 40).toBe(true)
			C.dismiss(nil)
			C.dismiss(42)
			C.open(nil)
			C.open("nope")
			expect(#C.pending() <= 12).toBe(true)
			clean(h)
		end)

		it("API Roblox : chaque classe et propriété écrite existe (ApiAudit)", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, C, Clock = setup()
				world(h)
				celebrate(h, "dexNew", { species = 3, mutation = 2, star = 0 })
				Clock.advance(8.01)
				C._step()
				C.open(C.pending()[1].id)
				TvAudit.tick(h, 0.5)
				C.dismiss(C.current().id)
				h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
				h:settle(1)
				C._step()
				Clock.advance(1.6)
				C._step()
				Clock.advance(3)
				C._step()
				clean(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and "" or tostring(err)).toBe("")
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
