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
end
