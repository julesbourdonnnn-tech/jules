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

		-- lot B3, étape 6 (journal B3-72) : rentré tout seul (personne ne l'a attrapé,
		-- ChaseService.escapeReturned) : le serveur envoie ownerReturn sans attrapeur, 0 pièce et aucune
		-- Fame, pour la carte du premier boop seulement ; la carte promettait « +0 coins +1 Fame »
		it(
			"carte « revient toujours ! » d'un squishy rentré tout seul : aucune ligne « +0 coins +1 Fame »",
			function()
				local h, C, Clock = setup()
				celebrate(h, "booped", { uid = "u9", species = 2, booperId = 55 })
				celebrate(h, "ownerReturn", {
					uid = "u9",
					species = 2,
					coins = 0,
					catcherId = 0,
					catcherName = "",
					firstBoop = true,
				})
				Clock.advance(8.01)
				C._step()
				expect(C.current().kind).toBe("postBoop")
				local side = C.frame("side")
				expect(side.Title.Text).toBe("Wibble always comes back!")
				expect(side.Line.Visible).toBe(false)
				-- rouverte depuis le « ! » : la fenêtre non plus
				Clock.advance(8.01)
				C._step()
				local postBoop = nil
				for _, c in C.pending() do
					if c.kind == "postBoop" then
						postBoop = c
					end
				end
				C.open(postBoop.id)
				expect(C.frame("dialog").Line.Visible).toBe(false)
				expect(#C.buttons()).toBe(3)
				clean(h)
			end
		)

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
	-- Lot B3, étape 5 : défaut de la v1.3 trouvé par le nouvel écran « card.reopened.postBoop.refuse »
	-- (TextFit) : rouverte avec 3 boutons (boopeur connu), « Pas ce joueur » / « Not this player » passait
	-- sur 2 lignes de 40 px dans un bouton de 80 px (boutons de 229 px)
	describe("Cards › carte rouverte à 3 boutons", function()
		local TextFit = require("../harness/TextFit")
		for _, lang in { "en", "fr" } do
			it("chaque libellé tient sur une ligne dans son bouton (" .. lang .. ")", function()
				local h = TvAudit.client({
					profile = { onboarding = { step = 11, done = true, demoDone = true } },
					lang = lang,
				})
				local C = TvAudit.mod(h, "UI.Cards")
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
					kind = "booped",
					data = { uid = "u9", species = 2, booperId = 77 },
				})
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
					kind = "ownerReturn",
					data = { uid = "u9", species = 2, coins = 10, firstBoop = true },
				})
				h:settle(1)
				local postBoop = nil
				for _ = 1, 4 do
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					Clock.advance(8.01)
					C._step()
				end
				for _, card in C.pending() do
					if card.kind == "postBoop" then
						postBoop = card
					end
				end
				C.open(postBoop.id)
				local buttons = C.buttons()
				expect(#buttons).toBe(3)
				local dlg = C.frame("dialog")
				local right = 0
				for _, b in buttons do
					local label = b.Label
					local need = TextFit.width(label.Text, label.FontFace, label.TextSize)
					expect(need <= b.Size.X.Offset - 24).toBe(true)
					right = math.max(right, b.Position.X.Offset + b.Size.X.Offset)
				end
				-- les boutons restent dans la carte (32 px de marge de chaque côté)
				expect(right <= dlg.Size.X.Offset - 64).toBe(true)
				clean(h)
			end)
		end
	end)

	-- =========================================================================================
	-- Lot B3, étape 5 (D19) : cartes de la v2.0 (profil v2, EventState.features.v2 du serveur)
	-- =========================================================================================
	describe("Cards › v2.0 (lot B3, étape 5)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		local function v2client(opts)
			opts = opts or {}
			local c = S.client({
				profile = { version = if opts.v1 then 1 else 2, onboarding = DONE },
				lang = opts.lang,
				snap = opts.snap,
			})
			if not opts.v1 then
				S.event(c, opts.flags or UpgradeScreen.V2_ALL)
			end
			c.C = TvAudit.mod(c.h, "UI.Cards")
			c.L = c.h:require("ReplicatedStorage.Shared.Localization")
			c.Cos = c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
			c.lang = opts.lang or "en"
			return c
		end
		local function fire(c, kind, data)
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
			c.h:settle(1)
		end
		local function tr(c, key, vars)
			return c.L.get(c.lang, key, vars)
		end
		local function side(c)
			local f = c.C.frame("side")
			return f.Title.Text, if f.Line.Visible then f.Line.Text else ""
		end
		-- la carte affichée est retirée (la suivante peut passer)
		local function drop(c)
			local cur = c.C.current()
			if cur then
				c.C.dismiss(cur.id)
			end
			c.h:settle(1)
		end

		for _, lang in { "en", "fr" } do
			it("chaque sorte de carte v2.0 a son titre et sa ligne (" .. lang .. ")", function()
				local c = v2client({ lang = lang })
				local Balance = c.h:require("ReplicatedStorage.Shared.Config.Balance")
				local Species = c.h:require("ReplicatedStorage.Shared.Config.Species")
				local Format = TvAudit.mod(c.h, "UI.Format")
				local function check(kind, data, cardKind, title, line)
					fire(c, kind, data)
					local cur = c.C.current()
					expect(cur ~= nil and cur.kind).toBe(cardKind)
					local t, l = side(c)
					expect(t).toBe(title)
					if line ~= nil then
						expect(l).toBe(line)
					end
					drop(c)
				end
				check(
					"welcomeV2",
					{ highlights = {} },
					"welcomeV2",
					tr(c, "card.welcomeV2.title"),
					tr(c, "card.welcomeV2.body")
				)
				check(
					"regainDone",
					{ bestR = 15, confetti = 10 },
					"regainDone",
					tr(c, "card.regainDone", { r = "15" }),
					tr(c, "confetti.gain", { n = "10" })
				)
				-- un seul Confetti : « +1 Confetti », jamais « +1 Confettis »
				check(
					"regainDone",
					{ bestR = 15, confetti = 1 },
					"regainDone",
					tr(c, "card.regainDone", { r = "15" }),
					tr(c, "confetti.gainOne")
				)
				check("recordStep", { share = 0.5 }, "recordStep", tr(c, "card.recordStep", { p = "50" }), "")
				local deco = c.Cos.DecoPerso[1]
				check(
					"unlock",
					{ kind = "deco", id = deco.id },
					"unlockNew",
					tr(c, "card.unlockNew", { name = tr(c, deco.key) }),
					""
				)
				-- premier cosmétique de la v2.0 (Cosmetics.List fusionnée au lot I : since = 2)
				local v2 = nil
				for _, def in c.Cos.List do
					if v2 == nil and def.since ~= nil then
						v2 = def
					end
				end
				check(
					"unlock",
					{ kind = v2.kind, id = v2.id },
					"unlockNew",
					tr(c, "card.unlockNew", { name = tr(c, v2.key) }),
					""
				)
				check(
					"trackTier",
					{ tier = 4, reward = "drop" },
					"trackTier",
					tr(c, "track.tier", { n = "4" }),
					tr(c, "track.drop")
				)
				check(
					"trackTier",
					{ tier = 1, reward = "confetti" },
					"trackTier",
					tr(c, "track.tier", { n = "1" }),
					tr(c, "confetti.gain", { n = "2" })
				)
				local plop = Species.ById[1]
				check(
					"mastery",
					{ species = 1 },
					"mastery",
					tr(c, "mastery.done", {
						name = tr(c, "species." .. plop.key),
						n = Format.confetti(Balance.Confetti.Mastery, lang),
					}),
					""
				)
				-- Carnet et unlock2 : titre fixe, ligne = le nom de la récompense / le 2e déblocage
				fire(c, "carnet", { tier = 1, reward = "title.builder" })
				expect(c.C.current().kind).toBe("carnet")
				local t, l = side(c)
				expect(t).toBe(tr(c, "carnet.title"))
				expect(l ~= "" and not string.find(l, "{", 1, true)).toBe(true)
				drop(c)
				fire(c, "unlock2", { recordR = 1, keys = {} })
				expect(c.C.current().kind).toBe("unlockNew")
				t, l = side(c)
				local prefix = tr(c, "card.unlockNew", { name = "" })
				expect(string.sub(t, 1, #prefix)).toBe(prefix)
				expect(#t > #prefix and not string.find(t, "{", 1, true)).toBe(true)
				expect(l ~= "" and not string.find(l, "{", 1, true)).toBe(true)
				drop(c)
				S.clean(c, expect)
			end)
		end

		it(
			"« Bienvenue » : 3 lignes à la place de « △ Voir » ; rouverte, son corps et ses déblocages ; les autres cartes gardent la mise en page de la v1.3",
			function()
				-- Record R 5 (instantané de l'écran Améliorations) : les déblocages se lisent jusqu'à lui
				local c = v2client({
					snap = S.snap(1, function(p)
						p.R = 5
						p.bestR = 5
					end),
				})
				fire(c, "welcomeV2", { highlights = { "unlock.gloves", "unlock.inconnu" } })
				local f = c.C.frame("side")
				expect(f.Line.Size.Y.Offset).toBe(132)
				expect(f.Hint.Visible).toBe(false)
				c.Clock.advance(8.01)
				c.C._step()
				fire(c, "dexNew", { species = 3, mutation = 0, star = 0 })
				expect(c.C.current().kind).toBe("dex")
				expect(f.Line.Size.Y.Offset).toBe(76)
				expect(f.Hint.Visible).toBe(true)
				drop(c)
				local welcome = nil
				for _, card in c.C.pending() do
					if card.kind == "welcomeV2" then
						welcome = card
					end
				end
				c.C.open(welcome.id)
				local dlg = c.C.frame("dialog")
				expect(dlg.TitleV2.Text).toBe(tr(c, "card.welcomeV2.title"))
				expect(dlg.Title.Visible).toBe(false)
				expect(dlg.Line.Text).toBe(tr(c, "card.welcomeV2.body"))
				expect(dlg.Line.Size.Y.Offset).toBe(84)
				-- déblocage inconnu ignoré, celui du Record R 1 traduit
				expect(dlg.MoreV2.Visible).toBe(true)
				expect(string.find(dlg.MoreV2.Text, "{", 1, true)).toBe(nil)
				expect(#c.C.buttons()).toBe(1)
				expect(c.C.buttons()[1].Label.Text).toBe(tr(c, "common.ok"))
				S.clean(c, expect)
			end
		)

		it(
			"l'écran de retour passe d'abord ; puis l'ordre de Layout.Cards.Order (Bienvenue avant la piste)",
			function()
				local c = v2client()
				local RS = TvAudit.mod(c.h, "UI.ReturnScreen")
				fire(
					c,
					"return",
					{ seconds = 7200, uid = "", species = 1, grew = 10, pot = 5, splorchReady = false }
				)
				expect(RS.isOpen()).toBe(true)
				fire(c, "trackTier", { tier = 2, reward = "confetti" })
				fire(c, "welcomeV2", { highlights = {} })
				c.C._step()
				expect(c.C.current()).toBe(nil)
				expect(c.C.queued()).toBe(2)
				S.run(c, 0.5)
				RS._close()
				S.run(c, 0.5)
				expect(RS.isOpen()).toBe(false)
				expect(c.C.current().kind).toBe("welcomeV2")
				S.clean(c, expect)
			end
		)

		it(
			"premier passage d'un élément de MON ranch : palier, Monument, maisonnette ; autres ranchs et autres identifiants ignorés",
			function()
				local c = v2client({ lang = "fr" })
				local RR = TvAudit.mod(c.h, "Controllers.RanchRenderer")
				local function built(slot, id, name)
					RR.ElementBuilt:Fire(slot, id)
					c.h:settle(1)
					local cur = c.C.current()
					if name == nil then
						expect(cur).toBe(nil)
					else
						expect(cur ~= nil and cur.kind).toBe("unlockNew")
						expect((side(c))).toBe(tr(c, "card.unlockNew", { name = tr(c, name) }))
						drop(c)
					end
				end
				built(1, "tier6.floatingCrown", "ranchTier.6")
				built(1, "monument.10", "monument.10")
				built(1, "helper.house", "helper.house")
				built(2, "tier1.pompomArch", nil) -- le ranch d'un autre
				built(1, "vat", nil)
				built(1, "deco.3", nil)
				built(1, "monument.11", nil)
				built(1, string.rep("x", 300), nil)
				built(1, 42, nil)
				built("1", "tier1.pompomArch", nil)
				S.clean(c, expect)
			end
		)

		it("charges hostiles : aucune carte, aucune trace ; bornes de la copie", function()
			local c = v2client()
			for _, case in
				{
					{ "regainDone", { bestR = "15", confetti = 3 } },
					{ "regainDone", { bestR = 0 / 0 } },
					{ "regainDone", { bestR = 1e12 } },
					{ "recordStep", { share = 0.3 } },
					{ "recordStep", {} },
					{ "unlock", { kind = "deco", id = string.rep("x", 500) } },
					{ "unlock", { kind = {}, id = 1 } },
					{ "unlock", { kind = "deco", id = "inconnu" } },
					{ "unlock2", { recordR = -1 } },
					{ "unlock2", { recordR = 1.5 } },
					{ "trackTier", { tier = 13, reward = "drop" } },
					{ "trackTier", { tier = 1.5 } },
					{ "carnet", { tier = 0 } },
					{ "mastery", { species = 999 } },
					{ "mastery", { species = "1" } },
					{ "welcomeV2", 5 },
				}
			do
				fire(c, case[1], case[2])
			end
			c.C._step()
			expect(c.C.current()).toBe(nil)
			expect(#c.C.pending()).toBe(0)
			expect(c.C.queued()).toBe(0)
			-- « Bienvenue » à la liste énorme : 3 déblocages lus au plus, aucune erreur
			local big = {}
			for i = 1, 5000 do
				big[i] = if i % 2 == 0 then "unlock.gloves" else i
			end
			fire(c, "welcomeV2", { highlights = big })
			expect(c.C.current().kind).toBe("welcomeV2")
			expect(#c.C.current().data.payload.highlights <= 3).toBe(true)
			S.clean(c, expect)
		end)

		it(
			"rouverte depuis « ! » : « Voir » ouvre l'écran de la carte (piste, Carnet, fiche, Mon style, Réglages) ; sans écran : « OK »",
			function()
				local c = v2client()
				local PC = c.PC
				local opened = {}
				local realOpen = PC.open
				PC.open = function(panel, tab, ...)
					table.insert(opened, tostring(panel) .. ":" .. tostring(tab))
					return realOpen(panel, tab, ...)
				end
				local emote = nil
				for _, def in c.Cos.List do
					if def.kind == "emote" and def.since ~= nil and emote == nil then
						emote = def
					end
				end
				local function reopen(kind, data, want)
					PC.closeAll()
					S.run(c, 0.5)
					table.clear(opened)
					fire(c, kind, data)
					c.Clock.advance(8.01)
					c.C._step()
					local list = c.C.pending()
					c.C.open(list[#list].id)
					local buttons = c.C.buttons()
					if want == nil then
						expect(#buttons).toBe(1)
						expect(buttons[1].Label.Text).toBe("OK")
						c.h.game.GuiService.SelectedObject = buttons[1]
						S.run(c, 0.5)
						Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
						c.h:settle(1)
						expect(#opened).toBe(0)
						return
					end
					expect(#buttons).toBe(2)
					expect(buttons[1].Label.Text).toBe("See")
					c.h.game.GuiService.SelectedObject = buttons[1]
					S.run(c, 0.5)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
					c.h:settle(1)
					expect(opened).toEqual({ want })
					expect(#c.C.pending()).toBe(0)
				end
				reopen("trackTier", { tier = 3, reward = "confetti" }, "Objectives:track")
				reopen("carnet", { tier = 1, reward = "title.builder" }, "Objectives:carnet")
				reopen("mastery", { species = 2 }, "Squishydex:species")
				reopen("unlock", { kind = "deco", id = c.Cos.DecoPerso[2].id }, "Ranch:style")
				reopen("unlock", { kind = emote.kind, id = emote.id }, "Settings:nil")
				reopen("regainDone", { bestR = 4, confetti = 10 }, nil)
				PC.open = realOpen
				S.clean(c, expect)
			end
		)

		it(
			"jamais de carte en double avec le message du HUD (cosmétiques de la v1.3, de la v2.0, Déco perso)",
			function()
				local c = v2client()
				local MetaView = TvAudit.mod(c.h, "UI.MetaView")
				local Strings = c.h:require("ReplicatedStorage.Shared.Localization.Strings")
				local both = {}
				local function probe(kind, id)
					local hud = Strings.en["cosmetic." .. kind .. "." .. id] ~= nil
					local card = MetaView.cardText("unlock", { kind = kind, id = id }, { lang = "en" }) ~= nil
					if hud == card then
						table.insert(both, kind .. "." .. id .. (if hud then " (deux)" else " (aucun)"))
					end
				end
				-- Cosmetics.List fusionnée au lot I (D6) : v1.3, v2.0 et cosmétiques de la semaine
				for _, def in c.Cos.List do
					probe(def.kind, def.id)
				end
				for _, def in c.Cos.DecoPerso do
					probe("deco", def.id)
				end
				expect(table.concat(both, ", ")).toBe("")
				-- un cosmétique de la v1.3 : le message du HUD, aucune carte
				local v13 = c.Cos.List[1]
				fire(c, "unlock", { kind = v13.kind, id = v13.id })
				expect(c.C.current()).toBe(nil)
				local M = TvAudit.mod(c.h, "UI.Hud.Messages")
				expect(M.last() ~= nil).toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"interrupteurs coupés (profil v1, aucun features.v2) : aucune carte v2.0, aucun objet v2.0, comme la v1.3",
			function()
				local c = v2client({ v1 = true })
				for _, case in
					{
						{ "welcomeV2", { highlights = {} } },
						{ "regainDone", { bestR = 15, confetti = 10 } },
						{ "recordStep", { share = 0.5 } },
						{ "unlock", { kind = "deco", id = c.Cos.DecoPerso[1].id } },
						{ "unlock2", { recordR = 1, keys = {} } },
						{ "trackTier", { tier = 4, reward = "drop" } },
						{ "carnet", { tier = 1, reward = "title.builder" } },
						{ "mastery", { species = 1 } },
					}
				do
					fire(c, case[1], case[2])
				end
				local RR = TvAudit.mod(c.h, "Controllers.RanchRenderer")
				RR.ElementBuilt:Fire(1, "tier1.pompomArch")
				c.h:settle(1)
				c.C._step()
				expect(c.C.current()).toBe(nil)
				expect(#c.C.pending()).toBe(0)
				-- une carte de la v1.3 rouverte : sa mise en page d'origine, aucun objet v2.0
				fire(c, "objectivesCard", { day = 1 })
				c.Clock.advance(8.01)
				c.C._step()
				c.C.open(c.C.pending()[1].id)
				local dlg = c.C.frame("dialog")
				expect(dlg:FindFirstChild("TitleV2")).toBe(nil)
				expect(dlg:FindFirstChild("MoreV2")).toBe(nil)
				expect(dlg.Line.Size.Y.Offset).toBe(48)
				expect(dlg.Size.Y.Offset).toBe(280)
				expect(c.C.frame("side").Hint.Visible).toBe(true)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
