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

		it(
			"espèce de la semaine (contrat v1.2) : liste publiée non secrète, (semaine + n) mod #liste",
			function()
				-- au lancement : 24 espèces non secrètes (les Secrets 25 et 26 exclus), ids 1 … 24
				expect(MR.species(0, 0)).toBe(1)
				expect(MR.species(23, 0)).toBe(24)
				expect(MR.species(24, 0)).toBe(1)
				expect(MR.species(2900, 7)).toBe(((2900 + 7) % 24) + 1)
				expect(MR.species(2900, 7, 0)).toBe(((2900 + 7) % 24) + 1)
				for w = 0, 100 do
					for n = 0, 400, 37 do
						local s = MR.species(w, n, 2e9)
						expect(Species.ById[s].family ~= "secret").toBe(true)
						expect(Species.ById[s].rarity ~= 7).toBe(true)
					end
				end
				expect(MR.species(0 / 0, -1)).toBe(24)
				expect(MR.species(nil, nil, nil)).toBe(1)
			end
		)

		-- Harnais à part dont la liste d'espèces reçoit `extra` lignes de plus (copies de Plop) publiées à
		-- `release` ; rend (MegaRules, EventClock, Species) de ce harnais
		local function withSpecies(extra, release, secretEvery)
			local hh = Harness.new()
			local S = hh:require("ReplicatedStorage.Shared.Config.Species")
			for i = 1, extra do
				local def = table.clone(S.List[1])
				def.id = #S.List + 1
				def.key = "test_" .. def.id
				def.rarity = if secretEvery and i % secretEvery == 0 then 7 else 1 + (i % 6)
				def.family = if def.rarity == 7 then "secret" else "jelly"
				def.release = release or 0
				table.insert(S.List, def)
				S.ById[def.id] = def
			end
			return hh:require("ReplicatedStorage.Shared.Logic.MegaRules"),
				hh:require("ReplicatedStorage.Shared.Logic.EventClock"),
				S,
				hh
		end

		-- liste attendue : espèces publiées à unix, non secrètes, triées par id
		local function expected(S, unix)
			local list = {}
			for _, def in S.List do
				if def.release <= unix and def.rarity ~= 7 then
					table.insert(list, def.id)
				end
			end
			table.sort(list)
			return list
		end

		for _, size in { 24, 27, 30, 64 } do
			it(
				`rotation du MEGA sur {size} espèces publiées : jamais mod 24, chaque espèce une fois par tour`,
				function()
					local MRx, _, S, hh = withSpecies(size - 24, 0)
					local list = expected(S, 1e9)
					expect(#list).toBe(size)
					for w = 0, 60, 7 do
						local seen = {}
						for n = 0, size - 1 do
							local sp = MRx.species(w, n, 1e9)
							expect(sp).toBe(list[(w + n) % size + 1])
							expect(S.ById[sp].rarity ~= 7).toBe(true)
							seen[sp] = true
						end
						local count = 0
						for _ in seen do
							count += 1
						end
						expect(count).toBe(size)
					end
					expect(#hh.errors).toBe(0)
				end
			)
		end

		it("une espèce pas encore publiée ou secrète n'entre jamais dans la rotation", function()
			local RELEASE = 1.8e9
			local MRx, _, S = withSpecies(6, RELEASE, 3) -- 6 lignes futures dont 2 Secrets
			local before, after = expected(S, RELEASE - 1), expected(S, RELEASE)
			expect(#before).toBe(24)
			expect(#after).toBe(28)
			for n = 0, 200 do
				local early = MRx.species(3, n, RELEASE - 1)
				local late = MRx.species(3, n, RELEASE)
				expect(early).toBe(before[(3 + n) % 24 + 1])
				expect(late).toBe(after[(3 + n) % 28 + 1])
				expect(S.ById[early].release <= RELEASE - 1).toBe(true)
				expect(S.ById[late].rarity ~= 7).toBe(true)
			end
			-- sans unix : seulement les espèces du lancement (release ≤ 0)
			expect(MRx.species(30, 0)).toBe(before[(30 % 24) + 1])
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
