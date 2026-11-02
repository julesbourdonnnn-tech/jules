--!nocheck
-- OnboardingController (paquet client-hud ; docs/04 §13.5 ; GDD §3) : une seule consigne à la fois
-- (glyphe + mot), montrée par l'invite du monde quand elle existe, sinon dans la puce spéciale du HUD ;
-- consigne rangée après 90 s puis remontrée (aucune étape ne bloque) ; « Marcher » après 4 s sans
-- bouger ; « Choisir » (L1 R1) 4 s une seule fois ; reprise après une réapparition ; affichage
-- progressif du HUD ; leçon du menu ; événements discrets avant l'étape 9 (LightingController,
-- Banners) ; joueur qui revient : HUD complet. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")

local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local spy = { hints = {}, quiet = {}, bannersQuiet = {} }
		-- espions posés AVANT le démarrage du client (les consignes déjà montrées ne sont pas renvoyées)
		local function before(h)
			local CLIENT = TvAudit.CLIENT
			local HUD = h:require(CLIENT .. "UI.HUD")
			HUD.setHint = function(action, key)
				table.insert(spy.hints, (action or "nil") .. "|" .. (key or "nil"))
				spy.last = if key then (action or "nil") .. "|" .. key else nil
			end
			h:require(CLIENT .. "Controllers.LightingController").setQuiet = function(q)
				table.insert(spy.quiet, q)
			end
			local Banners = h:require(CLIENT .. "UI.Banners")
			local origQuiet = Banners.setQuiet
			Banners.setQuiet = function(q)
				table.insert(spy.bannersQuiet, q)
				origQuiet(q)
			end
			local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
			WSC.mySlot = function()
				return 1
			end
			WSC.ranch = function(slot)
				return if slot == 1
					then { slot = 1, userId = 1, saddle = opts.saddle or 0, carry = "", ride = "" }
					else nil
			end
		end
		local h = TvAudit.client({
			profile = {
				onboarding = opts.onboarding or { step = 0, done = false, demoDone = false },
				stats = opts.stats,
			},
			before = before,
		})
		local O = TvAudit.mod(h, "Controllers.OnboardingController")
		local HUD = TvAudit.mod(h, "UI.HUD")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local inside = WorldLayout.toWorld(1, Vector3.new(0, 3, 36))
		h:moveTo(h.localPlayer, inside)
		return h, O, HUD, Clock, spy, inside
	end

	local function step(h, n)
		h:fireClient(
			"ReplicatedStorage.Remotes.Celebrate",
			{ kind = "onboarding", data = { step = n, hint = "" } }
		)
		h:settle(1)
	end

	describe("OnboardingController › consignes", function()
		it("« □ Presser » : l'invite du monde la montre ; sinon la puce spéciale du HUD", function()
			local h, O, _, _, spy = setup({ onboarding = { step = 1, done = false, demoDone = false } })
			O._tick()
			expect(spy.last).toBe("action|prompt.press")
			-- une invite du monde est affichée au-dessus de Plop : pas de deuxième consigne
			local P = TvAudit.mod(h, "UI.Prompt")
			P.plates = function()
				return { {} }
			end
			O._tick()
			expect(spy.last).toBeNil()
			clean(h)
		end)

		it("aucune étape ne bloque : rangée après 90 s, remontrée 90 s plus tard", function()
			local h, O, _, Clock, spy = setup({ onboarding = { step = 1, done = false, demoDone = false } })
			O._tick()
			expect(spy.last).toBe("action|prompt.press")
			Clock.advance(90.5)
			O._tick()
			expect(spy.last).toBeNil()
			Clock.advance(90)
			O._tick()
			expect(spy.last).toBe("action|prompt.press")
			-- l'étape suivante repart d'une consigne neuve
			step(h, 2)
			O._tick()
			expect(O.step()).toBe(2)
			clean(h)
		end)

		it(
			"« Marcher » (stick) seulement après 4 s sans bouger ; reprise après une réapparition",
			function()
				local h, O, _, Clock, spy, inside =
					setup({ onboarding = { step = 2, done = false, demoDone = false } })
				O._tick()
				expect(spy.last).toBeNil()
				Clock.advance(4.1)
				O._tick()
				expect(spy.last).toBe("move|prompt.walk")
				h:moveTo(h.localPlayer, inside + Vector3.new(3, 0, 0))
				O._tick()
				expect(spy.last).toBeNil()
				-- consigne rangée (90 s), puis le personnage réapparaît : elle se réaffiche
				Clock.advance(95)
				O._tick()
				expect(spy.last).toBeNil()
				h:respawn(h.localPlayer)
				h:settle(2)
				h:moveTo(h.localPlayer, inside)
				O._tick()
				Clock.advance(4.1)
				O._tick()
				expect(spy.last).toBe("move|prompt.walk")
				clean(h)
			end
		)

		it("« Monter » seulement quand une selle existe", function()
			local h, O, _, _, spy = setup({ onboarding = { step = 8, done = false, demoDone = true } })
			TvAudit.mod(h, "Controllers.InputController").Action:Fire("cycle") -- « Choisir » déjà appris
			O._tick()
			expect(spy.last).toBeNil()
			local h2, O2, _, _, spy2 =
				setup({ onboarding = { step = 8, done = false, demoDone = true }, saddle = 1 })
			TvAudit.mod(h2, "Controllers.InputController").Action:Fire("cycle")
			O2._tick()
			expect(spy2.last).toBe("ride|prompt.ride")
			clean(h)
			clean(h2)
		end)

		it(
			"L1 R1 « Choisir » : 4 s, une seule fois, après la démonstration, s'il n'a jamais changé de cible",
			function()
				local h, O, _, Clock, spy =
					setup({ onboarding = { step = 8, done = false, demoDone = true } })
				O._tick()
				expect(spy.last).toBe("target|prompt.choose")
				Clock.advance(4.1)
				O._tick()
				expect(spy.last).toBeNil()
				Clock.advance(100)
				O._tick()
				expect(spy.last).toBeNil() -- jamais remontrée
				clean(h)
			end
		)

		it(
			"leçon du menu : la puce Menu apparaît avec sa consigne une fois la balade faite et 5:00 de jeu",
			function()
				local h, O, HUD, _, spy = setup({
					onboarding = { step = 9, done = false, demoDone = true },
					stats = { playSeconds = 310 },
				})
				TvAudit.mod(h, "Controllers.InputController").Action:Fire("cycle")
				O._tick()
				HUD._refresh()
				expect(HUD.visible("menuChip")).toBe(true)
				expect(spy.last).toBe("menu|prompt.menu")
				local h2, O2, HUD2 = setup({
					onboarding = { step = 9, done = false, demoDone = true },
					stats = { playSeconds = 200 },
				})
				O2._tick()
				HUD2._refresh()
				expect(HUD2.visible("menuChip")).toBe(false)
				clean(h)
				clean(h2)
			end
		)
	end)

	describe("OnboardingController › HUD et événements", function()
		it(
			"affichage progressif : pièces seules, puis l'horloge des événements, puis le HUD complet",
			function()
				local h, O, HUD = setup()
				O._tick()
				HUD._refresh()
				expect(HUD.visible("coins")).toBe(true)
				expect(HUD.visible("goalTracker")).toBe(false)
				step(h, 8)
				O._tick()
				local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
				WSC.event = function()
					return {
						features = {
							boopRush = "on",
							megaSquish = true,
							golden = true,
							jellyMoon = true,
							gauge = true,
						},
						boost = { kind = "", untilT = 0, byName = "" },
						gauge = { points = 0, target = 1, partyUntil = 0, restUntil = 0 },
						spectacle = { queue = {} },
					}
				end
				HUD._refresh()
				expect(HUD.visible("eventPill")).toBe(true)
				expect(HUD.visible("goalTracker")).toBe(true)
				expect(HUD.visible("gauge")).toBe(false)
				step(h, 10)
				O._tick()
				HUD._refresh()
				expect(HUD.visible("gauge")).toBe(true)
				expect(HUD.visible("menuChip")).toBe(true)
				clean(h)
			end
		)

		it("événements discrets avant l'étape 9 : LightingController et Banners, puis normaux", function()
			local h, O, _, _, spy = setup()
			O._tick()
			expect(O.quiet()).toBe(true)
			step(h, 9)
			O._tick()
			expect(O.quiet()).toBe(false)
			expect(spy.quiet[#spy.quiet]).toBe(false)
			expect(spy.bannersQuiet[#spy.bannersQuiet]).toBe(false)
			clean(h)
		end)

		it("joueur qui revient (accueil fini) : HUD complet, aucune consigne, aucun mode discret", function()
			local h, O, HUD, _, spy = setup({ onboarding = { step = 11, done = true, demoDone = true } })
			O._tick()
			HUD._refresh()
			expect(O.quiet()).toBe(false)
			expect(spy.last).toBeNil()
			expect(HUD.visible("menuChip")).toBe(true)
			expect(HUD.visible("fame")).toBe(true)
			clean(h)
		end)

		it("célébrations hostiles : aucune erreur, l'étape ne recule jamais", function()
			local h, O = setup({ onboarding = { step = 5, done = false, demoDone = false } })
			for _, p in
				{
					{ kind = "onboarding", data = { step = 0 / 0 } },
					{ kind = "onboarding", data = { step = -4 } },
					{ kind = "onboarding", data = "x" },
					{ kind = "onboarding", data = { step = 1e9 } },
				}
			do
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", p)
				h:settle(1)
			end
			O._tick()
			expect(O.step() >= 5 and O.step() <= 99).toBe(true)
			clean(h)
		end)
	end)
end
