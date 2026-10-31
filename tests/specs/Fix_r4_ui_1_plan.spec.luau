--!nocheck
-- QA round 4 — fixer r4-ui-1, Hud/OnboardingPlan : Q6 « Attrape un Nebby météo » pendant une Pluie de
-- météores (fenêtre météo SANS forme, ~19 % des fenêtres MVP). La pastille d'événement montre alors
-- le compte à rebours de la pluie en cours, pas de la prochaine météo : « Météo bientôt ! » à côté
-- d'une pastille qui pulse et arrive à 0 sans rien déclencher trompait l'enfant. Nouveau fait
-- `weatherFormless` → instruction « ☁ Météo dans {time} » (onboarding.waitWeatherIn), pastille
-- immobile ; Plan.formWeatherIn(now) donne {time} (prochaine fenêtre qui donne une forme).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local h = Harness.new({ mode = "client" })
	local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")
	local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
	local Events = h:require("ReplicatedStorage.Shared.Config.Events")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")

	local function q6(over)
		local f = {
			step = 6,
			returning = false,
			parades = 8,
			conga = 3,
			stardust = 100,
			lineCount = 0,
			lineFull = false,
			upgradesOpen = false,
			canBuyConga = false,
			canBuyStride = false,
			canBuyPerches = false,
			rareTarget = false,
			weatherActive = false,
			weatherTarget = false,
			cometActive = false,
		}
		for k, v in over or {} do
			f[k] = v
		end
		return f
	end

	-- première Pluie de météores (fenêtre régulière, sans forme) après t
	local function meteorWindow(t)
		local x = t
		for _ = 1, 500 do
			local w = EventClock.nextWeather(x)
			if w.key == "meteor" and not w.starfall then
				return w
			end
			x = w.startsAt
		end
		error("aucune Pluie de météores trouvée")
	end

	describe("Fix r4-ui-1 › Q6 pendant une Pluie de météores", function()
		it("prémisse : la Pluie de météores ne donne aucune forme", function()
			expect(Events.WeatherByKey.meteor.form).toBeNil()
			local w = meteorWindow(T0)
			expect(w.form).toBeNil()
		end)

		it("météo sans forme : « Météo dans {time} », la pastille ne pulse pas", function()
			local f = q6({ weatherFormless = true })
			expect(Plan.hint(f)).toBe("onboarding.waitWeatherIn")
			expect(Plan.attention(f).eventPill).toBeNil()
			expect(Plan.guide(f)).toBeNil()
			-- seul fait connu : suffit à décider
			local only =
				q6({ weatherActive = nil, weatherTarget = nil, cometActive = nil, weatherFormless = true })
			expect(Plan.hint(only)).toBe("onboarding.waitWeatherIn")
		end)

		it(
			"pas de fenêtre en cours : « Météo bientôt ! » et la pastille (prochaine météo) pulse",
			function()
				local f = q6({ weatherFormless = false })
				expect(Plan.hint(f)).toBe("onboarding.waitWeather")
				expect(Plan.attention(f).eventPill).toBe(true)
				-- fait absent (contrôleur d'avant) : comportement d'origine
				local before = q6()
				expect(Plan.hint(before)).toBe("onboarding.waitWeather")
				expect(Plan.attention(before).eventPill).toBe(true)
			end
		)

		it("une Comète à rejoindre ou un Nebby météo connu passent avant l'attente", function()
			expect(Plan.hint(q6({ weatherFormless = true, cometActive = true }))).toBe("onboarding.joinComet")
			expect(Plan.guide(q6({ weatherFormless = true, cometActive = true }))).toBe("toComet")
			expect(Plan.hint(q6({ weatherFormless = true, weatherTarget = true }))).toBe("onboarding.weather")
			-- file pleine : rentrer d'abord
			expect(Plan.hint(q6({ weatherFormless = true, lineFull = true }))).toBe("onboarding.goHome")
		end)

		it("hors Q6 : le fait est ignoré", function()
			for _, step in { 1, 2, 3, 4, 5, 7, 8 } do
				local f = q6({ step = step, weatherFormless = true, parades = 8, conga = 3 })
				expect(Plan.hint(f) ~= "onboarding.waitWeatherIn").toBe(true)
			end
		end)

		it("Plan.formWeatherIn : jusqu'à la prochaine météo QUI DONNE une forme", function()
			for _, base in { T0, T0 + 86400 * 3 + 777, T0 + 86400 * 11 + 4321 } do
				local w = meteorWindow(base)
				for _, now in { w.startsAt, w.startsAt + 70, w.endsAt - 1 } do
					local s = Plan.formWeatherIn(now)
					expect(s ~= nil).toBe(true)
					expect(s > 0).toBe(true)
					expect(s % 1).toBe(0)
					-- à l'échéance, une météo à forme a commencé
					local at = EventClock.weather(now + s)
					expect(at ~= nil and at.form ~= nil).toBe(true)
					-- aucune météo à forme ne commence avant (balayage par pas de 10 s)
					local x = now
					while x < now + s - 1 do
						local cur = EventClock.weather(x)
						expect(cur == nil or cur.form == nil).toBe(true)
						x += 10
					end
				end
			end
		end)

		it("Plan.formWeatherIn : entrées invalides → nil, sans erreur", function()
			for _, bad in { 0 / 0, math.huge, -math.huge, "12", {}, nil } do
				expect(Plan.formWeatherIn(bad)).toBeNil()
			end
		end)

		it("textes EN / FR avec le compte à rebours", function()
			expect(Strings.en["onboarding.waitWeatherIn"]).toBe("☁ Weather in {time}")
			expect(Strings.fr["onboarding.waitWeatherIn"]).toBe("☁ Météo dans {time}")
		end)
	end)
end
