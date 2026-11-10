--!nocheck
-- Binoculars (lot B3, étape 5, D22 ; docs/04 §27.11 INT-B3-BINOCULARS ; GDD v2.0 §7.5, §13) : devant le
-- portail du ranch d'un voisin, l'invite □ « Regarder » (PromptController) ouvre les jumelles
-- (InputController) ; un seul bouton « Donner un cœur » : un GiveHeart par appui de ✕ capté, jamais un
-- ✕ tenu depuis le saut ; « Cœur donné ! » et « Plus de cœurs aujourd'hui » lus dans le profil ; aucun
-- nom ; ○ ramène au jeu ; interrupteurs coupés : ni invite, ni fenêtre, ni intention ; le HUD écrit
-- l'alias « Squishy Fan #NNNN » d'un donneur au nom caché. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local OWNER = 22

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)
	local DONE = { step = 11, done = true, demoDone = true }

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "",
			hidden = true,
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
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	-- Modèle Wobbleton/Ranches/<slot> avec ses attributs (BestR : preuve v2.0 du serveur)
	local function model(c, slot, attrs)
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local world = child(c.h.workspace, "Wobbleton", "Folder")
		local list = child(world, "Ranches", "Folder")
		local m = child(list, tostring(slot), "Model")
		for k, v in attrs do
			m:SetAttribute(k, v)
		end
		return m
	end

	-- Client v2 (profil v2, interrupteurs du serveur), mon ranch 1, le voisin OWNER au ranch 2 (BestR)
	local function client(opts)
		opts = opts or {}
		local profile = { version = if opts.v1 then 1 else 2, onboarding = DONE }
		if opts.hearts then
			profile.hearts = opts.hearts
		end
		local c = S.client({ profile = profile, lang = opts.lang })
		local me = c.h.localPlayer.UserId
		c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = {
				["1"] = ranch(1, me, { name = "Moi", hidden = false }),
				["2"] = ranch(2, OWNER),
				["3"] = ranch(3, 0),
			},
			squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {} },
		})
		c.h:settle(1)
		model(c, 2, { BestR = 5 })
		model(c, 3, { BestR = 5 })
		if not opts.v1 then
			S.event(c, opts.flags or UpgradeScreen.V2_ALL)
		end
		c.B = TvAudit.mod(c.h, "UI.Binoculars")
		c.Prompt = TvAudit.mod(c.h, "Controllers.PromptController")
		c.WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		return c
	end

	-- Debout dans la rue, à 6 studs devant le portail du ranch `slot`
	local function atGate(c, slot)
		c.h:moveTo(c.h.localPlayer, c.WorldLayout.gateOutside(slot))
		S.run(c, 0.3)
	end

	local function today(c)
		return math.floor(c.Clock.now() / 86400)
	end

	describe("Binoculars › invite et fenêtre", function()
		it(
			"devant le portail d'un voisin : □ « Look », □ ouvre les jumelles (bouton du cœur choisi, aucun nom) ; ○ ramène au jeu",
			function()
				local c = client()
				atGate(c, 2)
				local t = c.Prompt.current()
				expect(t ~= nil and t.kind).toBe("binoculars")
				expect(t.id).toBe(OWNER)
				expect(t.slot).toBe(2)
				local P = TvAudit.mod(c.h, "UI.Prompt")
				P._step()
				expect(P.plates()[1].Text.Text).toBe("Look")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
				c.h:settle(1)
				expect(c.B.isOpen()).toBe(true)
				expect(c.FG.top().name).toBe("binoculars")
				expect(S.selected(c)).toBe(c.B.button())
				expect(c.B.state()).toBe("give")
				expect(c.B.button().Label.Text).toBe("Give a heart")
				-- aucun texte du propriétaire (GDD §13 : sans texte) : le seul texte est celui du bouton
				local texts = {}
				for _, d in c.B.button().Parent:GetDescendants() do
					if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
						table.insert(texts, d.Text)
					end
				end
				expect(texts).toEqual({ "Give a heart" })
				expect(#S.sent(c, "GiveHeart")).toBe(0)
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				c.h:settle(1)
				expect(c.B.isOpen()).toBe(false)
				expect(c.FG.anyOpen()).toBe(false)
				expect(#S.sent(c, "GiveHeart")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"✕ capté : un GiveHeart(propriétaire) par appui (un en route à la fois) ; « Cœur donné ! » grisé quand le profil le dit",
			function()
				local c = client()
				atGate(c, 2)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				local sent = S.sent(c, "GiveHeart")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe(OWNER)
				-- un 2e appui avant la réponse : rien de plus (le cœur est en route)
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				expect(#S.sent(c, "GiveHeart")).toBe(1)
				-- la réponse du serveur (profil répliqué) : grisé, « Heart given! », plus aucun envoi
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ hearts = { receivedTotal = 0, givenDay = today(c), givenTo = { OWNER } } },
					{}
				)
				c.h:settle(1)
				expect(c.B.state()).toBe("given")
				expect(c.B.button().Label.Text).toBe("Heart given!")
				S.run(c, 4)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				expect(#S.sent(c, "GiveHeart")).toBe(1)
				S.clean(c, expect)
			end
		)

		it("un ✕ tenu depuis le saut n'envoie jamais rien ; un nouvel appui, si", function()
			local c = client()
			atGate(c, 2)
			Gamepad.press(c.h, Enum.KeyCode.ButtonA) -- saut tenu
			Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
			S.run(c, 1)
			expect(c.B.isOpen()).toBe(true)
			Gamepad.release(c.h, Enum.KeyCode.ButtonA)
			S.run(c, 0.5)
			expect(#S.sent(c, "GiveHeart")).toBe(0)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			c.h:settle(1)
			expect(#S.sent(c, "GiveHeart")).toBe(1)
			S.clean(c, expect)
		end)

		it(
			"états lus dans le profil : déjà donné aujourd'hui, plafond de 20, jour passé = de nouveau possible",
			function()
				local probe = client()
				local day = today(probe)
				local others = {}
				for i = 1, 20 do
					others[i] = 1000 + i
				end
				local given =
					client({ hearts = { receivedTotal = 3, givenDay = day, givenTo = { 7, OWNER } } })
				atGate(given, 2)
				expect(given.B.open(OWNER)).toBe(true)
				expect(given.B.state()).toBe("given")
				S.clean(given, expect)
				local limit =
					client({ hearts = { receivedTotal = 0, givenDay = day, givenTo = others }, lang = "fr" })
				atGate(limit, 2)
				expect(limit.B.open(OWNER)).toBe(true)
				expect(limit.B.state()).toBe("limit")
				expect(limit.B.button().Label.Text).toBe("Plus de cœurs aujourd'hui")
				S.run(limit, 0.5)
				Gamepad.tap(limit.h, Enum.KeyCode.ButtonA)
				limit.h:settle(1)
				expect(#S.sent(limit, "GiveHeart")).toBe(0)
				S.clean(limit, expect)
				-- liste d'hier : tout est permis de nouveau
				local yesterday =
					client({ hearts = { receivedTotal = 0, givenDay = day - 1, givenTo = others } })
				atGate(yesterday, 2)
				expect(yesterday.B.open(OWNER)).toBe(true)
				expect(yesterday.B.state()).toBe("give")
				-- profil abîmé : « give », aucune trace
				yesterday.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ hearts = { givenDay = "x", givenTo = 5 } },
					{}
				)
				yesterday.h:settle(1)
				expect(yesterday.B.state()).toBe("give")
				S.clean(yesterday, expect)
				S.clean(probe, expect)
			end
		)
	end)

	-- Lot B3, étape 5 : relevé sur les captures (tv2160) : la carte touchait la puce spéciale du bas
	-- (« GRAND SPLORCH ! », Layout.Hud.specialChip) ; elle reste 24 px au-dessus, et le glyphe ✕ n'est
	-- montré que quand ✕ donne un cœur
	describe("Binoculars › disposition", function()
		it(
			"la carte reste à 24 px au moins au-dessus des puces du bas ; ✕ caché sur un bouton grisé",
			function()
				local c = client()
				local Layout = c.h:require("ReplicatedStorage.Shared.Config.Layout")
				atGate(c, 2)
				expect(c.B.open(OWNER)).toBe(true)
				local card = c.B.button().Parent
				-- zone sûre : y de Layout.Safe.y à 1080 − Layout.Safe.y ; la carte est ancrée en bas
				local bottom = 1080 - Layout.Safe.y + card.Position.Y.Offset
				expect(card.AnchorPoint.Y).toBe(1)
				expect(card.Position.Y.Scale).toBe(1)
				expect(bottom <= Layout.Hud.specialChip.rect.y - 24).toBe(true)
				local glyph = c.B.button():FindFirstChild("Glyph", true)
				expect(glyph ~= nil and glyph.Visible).toBe(true)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ hearts = { receivedTotal = 0, givenDay = today(c), givenTo = { OWNER } } },
					{}
				)
				c.h:settle(1)
				expect(c.B.state()).toBe("given")
				expect(glyph.Visible).toBe(false)
				S.clean(c, expect)
			end
		)
	end)

	describe("Binoculars › interrupteurs et règles", function()
		it("interrupteurs coupés ou profil v1 : ni invite, ni fenêtre, ni intention", function()
			local v1 = client({ v1 = true })
			atGate(v1, 2)
			expect(v1.Prompt.current()).toBe(nil)
			Gamepad.tap(v1.h, Enum.KeyCode.ButtonX)
			v1.h:settle(1)
			expect(v1.B.open(OWNER)).toBe(false)
			expect(v1.B.isOpen()).toBe(false)
			expect(v1.FG.anyOpen()).toBe(false)
			expect(#S.sent(v1, "GiveHeart")).toBe(0)
			S.clean(v1, expect)
			-- Hearts seul coupé
			local flags = table.clone(UpgradeScreen.V2_ALL)
			flags.Hearts = nil
			local off = client({ flags = flags })
			atGate(off, 2)
			expect(off.Prompt.current()).toBe(nil)
			expect(off.B.open(OWNER)).toBe(false)
			S.clean(off, expect)
			-- coupé en direct, fenêtre ouverte : elle se referme
			local live = client()
			atGate(live, 2)
			expect(live.B.open(OWNER)).toBe(true)
			S.event(live, flags)
			expect(live.B.isOpen()).toBe(false)
			S.clean(live, expect)
		end)

		it(
			"jamais dans un ranch, ni à plus de 8 studs, ni sans BestR, ni devant un ranch libre ou le mien ; jamais pour moi-même ni un absent",
			function()
				local c = client()
				local me = c.h.localPlayer.UserId
				-- dans le ranch du voisin, à 4 studs de son portail
				c.h:moveTo(c.h.localPlayer, c.WorldLayout.toWorld(2, Vector3.new(0, 3, 4)))
				S.run(c, 0.3)
				expect(c.Prompt.current() == nil or c.Prompt.current().kind ~= "binoculars").toBe(true)
				-- à 9 studs du portail, dans la rue
				c.h:moveTo(c.h.localPlayer, c.WorldLayout.toWorld(2, Vector3.new(0, 3, -9)))
				S.run(c, 0.3)
				expect(c.Prompt.current() == nil or c.Prompt.current().kind ~= "binoculars").toBe(true)
				-- ranch libre (3) et mon ranch (1)
				atGate(c, 3)
				expect(c.Prompt.current() == nil or c.Prompt.current().kind ~= "binoculars").toBe(true)
				atGate(c, 1)
				expect(c.Prompt.current() == nil or c.Prompt.current().kind ~= "binoculars").toBe(true)
				-- sans BestR (profil v1 du voisin) : rien
				model(c, 2, {}):SetAttribute("BestR", nil)
				atGate(c, 2)
				expect(c.Prompt.current() == nil or c.Prompt.current().kind ~= "binoculars").toBe(true)
				model(c, 2, { BestR = 5 })
				S.run(c, 0.3)
				expect(c.Prompt.current().kind).toBe("binoculars")
				-- ouvertures refusées : moi-même, un joueur absent, des valeurs abîmées
				expect(c.B.open(me)).toBe(false)
				expect(c.B.open(99999)).toBe(false)
				expect(c.B.open(0 / 0)).toBe(false)
				expect(c.B.open(-3)).toBe(false)
				expect(c.B.open(2.5)).toBe(false)
				expect(c.B.isOpen()).toBe(false)
				S.clean(c, expect)
			end
		)
	end)

	describe("Binoculars › cœur reçu", function()
		it(
			"hearts.received d'un donneur au nom caché : l'alias « Squishy Fan #NNNN » (Hud/Util.vars)",
			function()
				local c = client()
				local M = TvAudit.mod(c.h, "UI.Hud.Messages")
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "hearts.received", vars = { name = "", userId = 4321 }, tone = "reward" }
				)
				c.h:settle(1)
				local text = M.last().text
				expect(string.find(text, "Squishy Fan #", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "gave you a heart!", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "{", 1, true)).toBe(nil)
				-- un nom visible reste le nom
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "hearts.received", vars = { name = "Mira", userId = 4322 }, tone = "reward" }
				)
				c.h:settle(1)
				S.run(c, 3)
				expect(M.last().text).toBe("Mira gave you a heart!")
				S.clean(c, expect)
			end
		)
	end)
end
