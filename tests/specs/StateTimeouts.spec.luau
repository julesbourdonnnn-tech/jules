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
		feedHold = 5.5,
		leap = 0.35,
		runaway = 20,
		escape = 25,
		wild = 25,
		golden = 30,
		demo = 20,
		rush = 115,
		mega = 65,
		splorchQueue = 110,
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
	}

	describe("StateTimeouts", function()
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

		it("boopHold tient le pire maintien prolongé (5 s) + grâce (0,5 s)", function()
			expect(ST.seconds("boopHold")).toBe(5 + 0.5)
			expect(ST.seconds("feedHold")).toBe(5 + 0.5)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
