--!nocheck
-- MegaRules (paquet logic, docs/04 §12.1, GDD §4.22) : objectif, indulgence, paliers, PERFECT du
-- géant, rotation de l'espèce.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local MR = h:require("ReplicatedStorage.Shared.Logic.MegaRules")
	local Species = h:require("ReplicatedStorage.Shared.Config.Species")

	describe("MegaRules", function()
		it("objectif : ceil((30 + 50 × N) × indulgence)", function()
			expect(MR.target(16, 0)).toBe(830)
			expect(MR.target(16, 1)).toBe(664)
			expect(MR.target(16, 2)).toBe(540) -- 830 × 0,65 = 539,5 → 540
			expect(MR.target(16, 9)).toBe(540)
			expect(MR.target(1, 0)).toBe(80)
			expect(MR.target(0, 0)).toBe(30)
			expect(MR.target(0 / 0, 0 / 0)).toBe(30)
		end)

		it("indulgence : 1 ; 0,8 après un échec ; 0,65 après deux de suite", function()
			expect(MR.leniency(0)).toBe(1)
			expect(MR.leniency(1)).toBe(0.8)
			expect(MR.leniency(2)).toBe(0.65)
			expect(MR.leniency(-3)).toBe(1)
		end)

		it("paliers : ≥ 10 → 1 bébé ; ≥ 40 → 2 ; ≥ 80 → 3", function()
			expect(MR.babiesFor(9)).toBe(0)
			expect(MR.babiesFor(10)).toBe(1)
			expect(MR.babiesFor(39)).toBe(1)
			expect(MR.babiesFor(40)).toBe(2)
			expect(MR.babiesFor(80)).toBe(3)
			expect(MR.babiesFor(1e9)).toBe(3)
			expect(MR.babiesFor(0 / 0)).toBe(0)
		end)

		it("PERFECT : de 0,12 s avant à 0,28 s après chaque sommet (landsAt + 1 + 2k)", function()
			local landsAt = 1000
			expect(MR.nextApex(landsAt, landsAt)).toBe(1001)
			expect(MR.nextApex(landsAt, 1001.5)).toBe(1003)
			expect(MR.isPerfect(landsAt, 1001)).toBe(true)
			expect(MR.isPerfect(landsAt, 1001 - 0.12)).toBe(true)
			expect(MR.isPerfect(landsAt, 1001 - 0.13)).toBe(false)
			expect(MR.isPerfect(landsAt, 1001.28)).toBe(true)
			expect(MR.isPerfect(landsAt, 1001.29)).toBe(false)
			expect(MR.isPerfect(landsAt, 1003.1)).toBe(true)
			expect(MR.isPerfect(landsAt, 1000)).toBe(false) -- au sol
			expect(MR.isPerfect(landsAt, 990)).toBe(false) -- avant l'atterrissage
			expect(MR.isPerfect(landsAt, 0 / 0)).toBe(false)
			expect(MR.phase(landsAt, 1001)).toBeNear(0.5, 1e-12)
		end)

		it("espèce de la semaine : ((semaine + n) mod 24) + 1, jamais un Secret", function()
			expect(MR.species(0, 0)).toBe(1)
			expect(MR.species(23, 0)).toBe(24)
			expect(MR.species(24, 0)).toBe(1)
			expect(MR.species(2900, 7)).toBe(((2900 + 7) % 24) + 1)
			for w = 0, 100 do
				for n = 0, 400, 37 do
					local s = MR.species(w, n)
					expect(Species.ById[s].family ~= "secret").toBe(true)
				end
			end
			expect(MR.species(0 / 0, -1)).toBe(24)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
