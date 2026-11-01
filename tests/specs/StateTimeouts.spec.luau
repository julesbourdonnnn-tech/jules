--!nocheck
-- StateTimeouts (paquet logic, docs/04 §12.1, §17.2, GDD §12.10) : chaque état a son délai et son
-- test de délai ; erreur claire pour un état inconnu ; début illisible = état échu (jamais bloqué).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local ST = h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")

	-- délais du GDD §12.10 et des ajouts du contrat (docs/04 §12.1)
	local EXPECTED = {
		profileLoad = 60,
		characterPlace = 10,
		playerReady = 15,
		serverFull = 30,
		worldResync = 3,
		unstable = 3,
		carry = math.huge,
		boopHold = 5.5,
		feedHold = 2.5, -- contrat v1.2 : bol en 2 s + 0,5 s (GDD v1.3 §12.10)
		leap = 0.35,
		runaway = 20,
		escape = 25,
		wild = 25,
		golden = 30,
		demo = 20,
		rush = 115,
		mega = 65,
		splorchQueue = 480, -- contrat v1.2 : coupure dure de l'attente dynamique (Events.SplorchQueueHardCut)
		spectacle = 10,
		squishParty = 600,
		wobbleParty = 300,
		modeCard = 20,
		card = 8,
		robloxPrompt = 60,
		onboardingStep = 90,
		clickTarget = 4,
		clapWindow = 8,
		fusion = 0.4,
		combo = 0.6,
		hatch = 2,
		splorchBurst = 3.2,
		clip = 8,
		tileDwell = 1.1, -- contrat v1.2 : 0,6 s sur la dalle + 0,5 s de grâce
		gaugeRest = 1200, -- contrat v1.2 : sieste de Big Plop (Events.Gauge.RestSeconds)
	}

	describe("StateTimeouts", function()
		it(
			"états du contrat v1.2 : chacun a son test de délai et suit sa valeur de configuration",
			function()
				local B = h:require("ReplicatedStorage.Shared.Config.Balance")
				local E = h:require("ReplicatedStorage.Shared.Config.Events")
				local Q = h:require("ReplicatedStorage.Shared.Config.Quests")
				expect(ST.seconds("tileDwell")).toBeNear(B.Tiles.DwellSeconds + 0.5, 1e-12)
				expect(ST.seconds("feedHold")).toBeNear(Q.Feed.Hold + 0.5, 1e-12)
				expect(ST.seconds("splorchQueue")).toBe(E.SplorchQueueHardCut)
				expect(ST.seconds("gaugeRest")).toBe(E.Gauge.RestSeconds)
				-- tileDwell : ouvert à 10 s ; à 11,1 s toujours ouvert, à 11,11 s échu
				expect(ST.expired("tileDwell", 10, 11.1)).toBe(false)
				expect(ST.expired("tileDwell", 10, 11.11)).toBe(true)
				-- feedHold : 2,5 s
				expect(ST.expired("feedHold", 0, 2.5)).toBe(false)
				expect(ST.expired("feedHold", 0, 2.51)).toBe(true)
				-- file des Grands Splorch : coupure dure à 8 min
				expect(ST.expired("splorchQueue", 100, 580)).toBe(false)
				expect(ST.expired("splorchQueue", 100, 580.01)).toBe(true)
				-- sieste de la jauge : 20 min
				expect(ST.expired("gaugeRest", 0, 1200)).toBe(false)
				expect(ST.expired("gaugeRest", 0, 1200.01)).toBe(true)
				expect(ST.deadline("gaugeRest", 50)).toBe(1250)
			end
		)

		it("chaque état connu a le délai du GDD, et la liste est triée et complète", function()
			local names = ST.names()
			local sorted = table.clone(names)
			table.sort(sorted)
			expect(names).toEqual(sorted)
			local count = 0
			for name, seconds in EXPECTED do
				count += 1
				expect({ name = name, seconds = ST.seconds(name) }).toEqual({ name = name, seconds = seconds })
			end
			expect(#names).toBe(count)
		end)

		it(
			"délai de CHAQUE état : pas échu à l'échéance, échu juste après (fermé par un événement : jamais)",
			function()
				for _, name in ST.names() do
					local seconds = ST.seconds(name)
					local start = 1000
					expect(ST.deadline(name, start)).toBe(start + seconds)
					if seconds == math.huge then
						expect(ST.expired(name, start, 1e12)).toBe(false)
					else
						expect({ name = name, at = ST.expired(name, start, start + seconds) }).toEqual({
							name = name,
							at = false,
						})
						expect({ name = name, after = ST.expired(name, start, start + seconds + 1e-3) }).toEqual({
							name = name,
							after = true,
						})
						expect(ST.expired(name, start, start + seconds + 0.4, 0.5)).toBe(false) -- grâce (extra)
					end
				end
			end
		)

		it("état inconnu : erreur claire (faute de programmation)", function()
			expect(function()
				ST.seconds("nope")
			end).toThrow("état inconnu")
			expect(function()
				ST.expired(nil, 0, 0)
			end).toThrow("état inconnu")
		end)

		it(
			"début illisible : échu (fermé plutôt que bloqué) ; « maintenant » illisible : jamais échu",
			function()
				expect(ST.deadline("leap", 0 / 0)).toBe(-math.huge)
				expect(ST.expired("leap", 0 / 0, 5)).toBe(true)
				expect(ST.expired("leap", math.huge, 5)).toBe(true)
				expect(ST.expired("leap", 0, 0 / 0)).toBe(false)
				expect(ST.deadline("leap", 10, 0 / 0)).toBe(10.35)
			end
		)

		it(
			"boopHold tient le pire maintien prolongé (5 s) + grâce (0,5 s) ; bol 2 s + 0,5 s (v1.2)",
			function()
				expect(ST.seconds("boopHold")).toBe(5 + 0.5)
				expect(ST.seconds("feedHold")).toBe(2 + 0.5)
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
