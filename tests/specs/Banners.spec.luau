--!nocheck
-- Banners (paquet client-hud ; docs/04 §10.4, §13.5 ; GDD §6.6, §3, §9.4) : une seule bannière à
-- l'écran, 3 s, par priorité, 3 au plus en attente, dans l'emplacement de message du HUD ; messages
-- (Toast) retenus pendant une bannière ; nouveau avant l'étape 9 : bannières des autres retenues puis
-- jetées après 30 s, aucune bannière d'événement ; bannières d'événement (EventClock) seulement si
-- l'interrupteur du serveur est vrai, une fois par créneau ; alias d'un nom caché ; charges hostiles
-- sans erreur. Zéro trace.
local TvAudit = require("../harness/TvAudit")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000
	local RUSH_START = 1800000300 -- prochain BOOP RUSH après NOW (EventClock)
	local MEGA_LAND = 1800001200 -- prochain MEGA SQUISH

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- joueur qui a fini l'accueil (le mode discret du nouveau est testé à part)
	local function setup()
		local h = TvAudit.client({ profile = { onboarding = { step = 11, done = true, demoDone = true } } })
		local B = TvAudit.mod(h, "UI.Banners")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		return h, B, Clock
	end

	local function banner(h, kind, args, priority, personal)
		h:fireClient("ReplicatedStorage.Remotes.Banner", {
			kind = kind,
			args = args or { userId = 2, name = "Mira" },
			priority = priority or 5,
			personal = personal,
		})
		h:settle(1)
	end

	local function frame(h)
		local HUD = TvAudit.mod(h, "UI.HUD")
		return HUD.element("message"):FindFirstChild("Banner")
	end

	local function setFeatures(h, f)
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		WSC.event = function()
			return { features = f, boost = { kind = "", untilT = 0, byName = "" } }
		end
	end

	local function allOn()
		return {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
	end

	describe("Banners › file", function()
		it("une seule à l'écran, 3 s, dans l'emplacement de message, puis la plus prioritaire", function()
			local h, B, Clock = setup()
			banner(h, "goldenCaught", { userId = 2, name = "Noah" }, 6)
			expect(B.current().kind).toBe("goldenCaught")
			local f = frame(h)
			expect(f.Visible).toBe(true)
			expect(f.Title.Text).toBe("Noah caught the Golden Wobbler!")
			banner(h, "legendHatch", { userId = 3, name = "Léa", species = 1 }, 4)
			banner(h, "splorch", { userId = 4, name = "Mira" }, 1)
			banner(h, "combo5", { userId = 5, name = "Sam", n = 5 }, 3)
			expect(B.queued()).toBe(3)
			expect(B.current().kind).toBe("goldenCaught") -- une seule à la fois
			Clock.advance(3.01)
			B._step()
			expect(B.current().kind).toBe("splorch")
			Clock.advance(3.01)
			B._step()
			expect(B.current().kind).toBe("combo5")
			expect(B.current().title).toBe("Sam: COMBO x5!")
			Clock.advance(3.01)
			B._step()
			expect(B.current().kind).toBe("legendHatch")
			Clock.advance(3.01)
			B._step()
			expect(B.current()).toBeNil()
			expect(B.queued()).toBe(0)
			clean(h)
		end)

		it("3 au plus en attente : la moins prioritaire est jetée", function()
			local h, B = setup()
			banner(h, "squishParty", { userId = 0, name = "" }, 7)
			for i = 1, 5 do
				banner(h, "goldenCaught", { userId = 10 + i, name = "P" .. i }, 6)
			end
			banner(h, "splorch", { userId = 2, name = "Mira" }, 1)
			expect(B.queued()).toBe(3)
			clean(h)
		end)

		it("les messages attendent pendant une bannière, puis passent", function()
			local h, B, Clock = setup()
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			banner(h, "splorch", { userId = 2, name = "Mira" }, 1)
			h:fireClient(
				"ReplicatedStorage.Remotes.Feedback",
				{ key = "feedback.notEnoughCoins", vars = { missing = 1200 }, tone = "warning" }
			)
			h:settle(1)
			expect(M.pending()).toBe(1)
			Clock.advance(3.01)
			B._step()
			M.step(Clock.now())
			expect(M.pending()).toBe(0)
			expect(M.last().text).toBe("1,200 coins missing")
			clean(h)
		end)

		it("nom caché : l'alias « Squishy Fan #NNNN » ; mot entier du jalon de la fanfare", function()
			local h, B, Clock = setup()
			banner(h, "splorch", { userId = 77, name = "" }, 1)
			expect(string.find(B.current().title, "Squishy Fan #", 1, true) ~= nil).toBe(true)
			Clock.advance(3.01)
			B._step()
			banner(h, "record", { userId = 2, name = "Mira", threshold = 1e9 }, 5)
			expect(B.current().title).toBe("First to 1 BILLION: Mira!")
			clean(h)
		end)
	end)

	describe("Banners › nouveau avant l'étape 9", function()
		it(
			"celles des autres retenues puis jetées après 30 s ; les siennes et les personnelles passent",
			function()
				local h, B, Clock = setup()
				B.setQuiet(true)
				banner(h, "splorch", { userId = 2, name = "Mira" }, 1)
				expect(B.current()).toBeNil()
				expect(B.queued()).toBe(1)
				-- la sienne (joueur local, userId 1) passe
				banner(h, "legendHatch", { userId = 1, name = "Moi", species = 1 }, 4)
				expect(B.current().kind).toBe("legendHatch")
				Clock.advance(3.01)
				B._step()
				banner(h, "wobbleParty", { userId = 0, name = "" }, 7, true)
				expect(B.current().kind).toBe("wobbleParty")
				Clock.advance(30)
				B._step()
				expect(B.queued()).toBe(0) -- celle de Mira, retenue plus de 30 s, est jetée
				B.setQuiet(false)
				B._step()
				expect(B.current()).toBeNil()
				-- fin du mode discret avant 30 s : la bannière retenue passe
				B.setQuiet(true)
				banner(h, "goldenCaught", { userId = 2, name = "Noah" }, 6)
				Clock.advance(5)
				B.setQuiet(false)
				expect(B.current().kind).toBe("goldenCaught")
				clean(h)
			end
		)
	end)

	describe("Banners › événements", function()
		it(
			"sirène du Rush, début du Rush, alerte MEGA avec compte à rebours : une fois par créneau",
			function()
				local h, B, Clock = setup()
				setFeatures(h, allOn())
				Clock.freeze(RUSH_START - 10 + 0.5)
				B._step()
				expect(B.current().kind).toBe("rushSoon")
				B._step()
				Clock.freeze(RUSH_START + 0.5)
				B._step()
				expect(B.current().kind).toBe("rushStart")
				Clock.freeze(RUSH_START + 4)
				B._step()
				expect(B.current()).toBeNil() -- jamais rejouée dans le même créneau
				Clock.freeze(MEGA_LAND - 15 + 1)
				B._step()
				expect(B.current().kind).toBe("megaWarn")
				expect(frame(h).Line.Text).toBe("0:14")
				Clock.freeze(MEGA_LAND - 15 + 2.2)
				B._step()
				expect(frame(h).Line.Text).toBe("0:13")
				clean(h)
			end
		)

		it("interrupteur du serveur coupé, ou inconnu : aucune bannière d'événement", function()
			local h, B, Clock = setup()
			local f = allOn()
			f.boopRush = "off"
			f.megaSquish = false
			setFeatures(h, f)
			Clock.freeze(RUSH_START + 0.5)
			B._step()
			expect(B.current()).toBeNil()
			Clock.freeze(MEGA_LAND - 14)
			B._step()
			expect(B.current()).toBeNil()
			-- miroir du monde sans EventState (stub) : rien non plus
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			WSC.event = function()
				error("TODO(client-world): WorldStateController.event")
			end
			Clock.freeze(RUSH_START + 600 + 0.5)
			B._step()
			expect(B.current()).toBeNil()
			clean(h)
		end)

		it("nouveau avant l'étape 9 : aucune bannière d'événement", function()
			local h, B, Clock = setup()
			setFeatures(h, allOn())
			B.setQuiet(true)
			Clock.freeze(RUSH_START + 0.5)
			B._step()
			expect(B.current()).toBeNil()
			expect(B.queued()).toBe(0)
			clean(h)
		end)
	end)

	describe("Banners › charges hostiles", function()
		it("aucune erreur, aucun avertissement, rien d'affiché pour une sorte inconnue", function()
			local h, B = setup()
			local bad = {
				"x",
				42,
				{},
				{ kind = 42 },
				{ kind = "inconnue", args = {} },
				{ kind = string.rep("a", 100000), args = {} },
				{ kind = "splorch", args = "x", priority = 0 / 0 },
				{ kind = "splorch", args = { userId = 0 / 0, name = 42 }, priority = math.huge },
				{
					kind = "secretHatch",
					args = { name = string.rep("é", 5000), species = -1, odds = 0 / 0 },
				},
			}
			for _, p in bad do
				h:fireClient("ReplicatedStorage.Remotes.Banner", p)
				h:settle(1)
			end
			B.show(nil)
			B.show({ kind = "nope" })
			local count = B.queued() + (if B.current() then 1 else 0)
			expect(count <= 3).toBe(true)
			clean(h)
		end)
	end)
	-- =========================================================================================
	-- Lot B3, étape 5 (D20) : bannière de la Jelly Ascend, Pluie d'étoiles, petite ligne
	-- =========================================================================================
	describe("Banners › v2.0 (lot B3, étape 5)", function()
		local V2 = { RecordR = true, JellyAscend = true }
		local function v2on(h)
			local f = allOn()
			f.v2 = V2
			setFeatures(h, f)
		end
		local function celebrate(h, kind, data)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
			h:settle(1)
		end
		local function ascend(h, userId, now)
			celebrate(h, "ascend", {
				userId = userId,
				ascend = 1,
				startR = 1,
				bestR = 20,
				startedAt = now,
				burstAt = now + 4,
				endsAt = now + 10,
				flyer = { s = 1, m = 0, st = 0, z = 10 },
			})
		end
		local function gift(h, heroId)
			celebrate(
				h,
				"giftRain",
				{ heroId = heroId, heroName = "", coins = 10, uid = "", species = 0, short = false }
			)
		end
		local function splorch(h, userId, now)
			celebrate(h, "splorch", {
				userId = userId,
				level = 1,
				flyer = { s = 1, m = 0, st = 0, z = 10 },
				startedAt = now,
				burstAt = now + 4,
				endsAt = now + 8,
				short = false,
			})
		end
		-- messages montrés (textes), dans l'ordre
		local function shown(h)
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			local out = {}
			local last = M.last()
			if last then
				table.insert(out, last.text)
			end
			return out
		end
		local function run(h, B, Clock, seconds)
			local steps = math.max(1, math.floor(seconds / 0.25 + 0.5))
			for _ = 1, steps do
				Clock.advance(seconds / steps)
				B._step()
				TvAudit.tick(h, 0)
			end
			h:settle(1)
		end

		it(
			"banner.ascend : la Jelly Ascend d'un joueur a sa bannière (« banner. » + la sorte du serveur)",
			function()
				local h, B = setup()
				local L = h:require("ReplicatedStorage.Shared.Localization")
				banner(h, "ascend", { userId = 2, name = "Mira" }, 1)
				expect(B.current().kind).toBe("ascend")
				expect(B.current().title).toBe(L.get("en", "banner.ascend", { name = "Mira" }))
				clean(h)
			end
		)

		it(
			"Pluie d'étoiles : giftRain du héros de l'Ascension en cours → « Star Rain! », une fois ; un autre héros, après endsAt + 5 s ou interrupteurs coupés : rien",
			function()
				local h, B, Clock = setup()
				local M = TvAudit.mod(h, "UI.Hud.Messages")
				v2on(h)
				local now = Clock.now()
				ascend(h, 7, now)
				gift(h, 8) -- cadeaux d'un Grand Splorch d'un autre : aucune Pluie d'étoiles
				expect(M.last() == nil or M.last().text ~= "Star Rain!").toBe(true)
				gift(h, 7)
				expect(M.last().text).toBe("Star Rain!")
				-- une seule par Ascension
				run(h, B, Clock, 4)
				local before = M.last().at
				gift(h, 7)
				run(h, B, Clock, 4)
				expect(M.last().at).toBe(before)
				-- après endsAt + 5 s : le héros est oublié
				local t2 = Clock.now()
				ascend(h, 9, t2)
				run(h, B, Clock, 16)
				gift(h, 9)
				run(h, B, Clock, 4)
				expect(M.last().at).toBe(before)
				-- interrupteurs coupés : jamais
				setFeatures(h, allOn())
				ascend(h, 11, Clock.now())
				gift(h, 11)
				run(h, B, Clock, 4)
				expect(M.last().at).toBe(before)
				clean(h)
			end
		)

		it(
			"petite ligne : Grand Splorch d'un autre sans sa bannière à burstAt + 1,5 s → le texte de banner.splorch en message ; bannière à temps : aucune ligne ; bannière en retard : jetée ; le mien : rien",
			function()
				local h, B, Clock = setup()
				local M = TvAudit.mod(h, "UI.Hud.Messages")
				v2on(h)
				-- 1. aucune bannière : la ligne à burstAt + 1,5 s, nom caché → alias
				splorch(h, 7, Clock.now())
				run(h, B, Clock, 5)
				expect(M.last() == nil or not string.find(M.last().text, "GRAND SPLORCH", 1, true)).toBe(true)
				run(h, B, Clock, 0.75)
				expect(string.find(M.last().text, "GRAND SPLORCH", 1, true) ~= nil).toBe(true)
				expect(string.find(M.last().text, "Squishy Fan #", 1, true) ~= nil).toBe(true)
				local lineAt = M.last().at
				-- sa bannière arrive en retard (file du serveur) : jetée, jamais les deux
				banner(h, "splorch", { userId = 7, name = "" }, 1)
				expect(B.current()).toBe(nil)
				expect(B.queued()).toBe(0)
				-- 2. la bannière arrive à temps : aucune ligne
				run(h, B, Clock, 6)
				splorch(h, 8, Clock.now())
				run(h, B, Clock, 4)
				banner(h, "splorch", { userId = 8, name = "Mira" }, 1)
				expect(B.current().kind).toBe("splorch")
				run(h, B, Clock, 4)
				expect(M.last().at).toBe(lineAt)
				-- 3. mon Grand Splorch : jamais de ligne (ma bannière, ou rien)
				local me = h.localPlayer.UserId
				splorch(h, me, Clock.now())
				run(h, B, Clock, 8)
				expect(M.last().at).toBe(lineAt)
				expect(B._pendingLines()).toBe(0)
				-- 4. charges abîmées : rien, aucune trace
				celebrate(h, "splorch", { userId = "7", burstAt = Clock.now() })
				celebrate(h, "splorch", { userId = 7, burstAt = 0 / 0 })
				celebrate(h, "splorch", { userId = 7, burstAt = Clock.now() + 1e6 })
				celebrate(h, "ascend", { userId = -1, endsAt = Clock.now() })
				expect(B._pendingLines()).toBe(0)
				-- 5. au plus 16 suivis à la fois
				for uid = 100, 140 do
					splorch(h, uid, Clock.now())
				end
				expect(B._pendingLines()).toBe(16)
				run(h, B, Clock, 30)
				expect(B._pendingLines()).toBe(0)
				clean(h)
			end
		)

		it(
			"jamais pendant le mode discret du nouveau ; interrupteurs coupés : une bannière manquée ne donne jamais de ligne",
			function()
				local h, B, Clock = setup()
				local M = TvAudit.mod(h, "UI.Hud.Messages")
				v2on(h)
				B.setQuiet(true)
				splorch(h, 7, Clock.now())
				run(h, B, Clock, 8)
				expect(M.last() == nil or not string.find(M.last().text, "GRAND SPLORCH", 1, true)).toBe(true)
				B.setQuiet(false)
				-- ligne attendue puis mode discret : jetée
				splorch(h, 8, Clock.now())
				B.setQuiet(true)
				run(h, B, Clock, 8)
				expect(M.last() == nil or not string.find(M.last().text, "GRAND SPLORCH", 1, true)).toBe(true)
				B.setQuiet(false)
				-- interrupteurs coupés (aucun features.v2) : aucune ligne, comme la v1.3
				setFeatures(h, allOn())
				splorch(h, 9, Clock.now())
				run(h, B, Clock, 8)
				expect(M.last() == nil or not string.find(M.last().text, "GRAND SPLORCH", 1, true)).toBe(true)
				expect(B._pendingLines()).toBe(0)
				-- RecordR seul coupé (JellyAscend ouvert) : aucune ligne non plus
				local f = allOn()
				f.v2 = { JellyAscend = true }
				setFeatures(h, f)
				splorch(h, 10, Clock.now())
				run(h, B, Clock, 8)
				expect(M.last() == nil or not string.find(M.last().text, "GRAND SPLORCH", 1, true)).toBe(true)
				clean(h)
			end
		)
	end)
end
