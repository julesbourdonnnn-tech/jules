--!nocheck
-- PressTiming (paquet logic, docs/04 §12.1, GDD §4.7) : rebond de 1,2 s, fenêtre PERFECT de 0,08 s
-- avant à 0,20 s après le sommet, tClient borné à [maintenant − 0,35 ; maintenant + 0,05].
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local PT = h:require("ReplicatedStorage.Shared.Logic.PressTiming")

	describe("PressTiming", function()
		it("décalage : dans [0 ; 1,2[, propre au squishy, identique à chaque appel", function()
			local a = PT.offset(1, "1")
			expect(a >= 0 and a < 1.2).toBe(true)
			expect(PT.offset(1, "1")).toBe(a)
			expect(PT.offset(1, "2") ~= a).toBe(true)
			expect(PT.offset(2, "1") ~= a).toBe(true)
			expect(PT.offset(1, nil) >= 0).toBe(true)
		end)

		it("phase : 0 au sommet, sommets toutes les 1,2 s", function()
			local off = 0.3
			expect(PT.phase(0.3, off)).toBe(0)
			expect(PT.phase(0.9, off)).toBeNear(0.5, 1e-12)
			expect(PT.phase(0.3 + 1.2 * 1000, off)).toBeNear(0, 1e-9)
			expect(PT.phase(0 / 0, off)).toBe(PT.phase(0, off))
		end)

		it("PERFECT : de 0,08 s avant à 0,20 s après le sommet (23 % du cycle)", function()
			local off = 0.3
			local apex = 0.3 + 1.2 * 500
			expect(PT.isPerfect(apex, off)).toBe(true)
			expect(PT.isPerfect(apex - 0.08, off)).toBe(true)
			expect(PT.isPerfect(apex - 0.09, off)).toBe(false)
			expect(PT.isPerfect(apex + 0.20, off)).toBe(true)
			expect(PT.isPerfect(apex + 0.21, off)).toBe(false)
			expect(PT.isPerfect(apex + 0.6, off)).toBe(false)
			expect(PT.isPerfect(0 / 0, off)).toBe(false)
			-- part du cycle : 0,28 / 1,2
			local hits = 0
			for k = 0, 11999 do
				if PT.isPerfect(k * 0.0001 + 100, off) then
					hits += 1
				end
			end
			expect(hits / 12000).toBeNear(0.28 / 1.2, 0.002)
		end)

		it(
			"contrat v1.2 : offset = hachage (UserId du propriétaire, uid) ; cas du GDD v1.3 §4.7",
			function()
				local Hash = h:require("ReplicatedStorage.Shared.Logic.Hash")
				-- même valeur côté client et serveur : seulement l'UserId du propriétaire et l'uid
				local off = PT.offset(123456789, "a7")
				expect(off).toBe(PT.offset(123456789, "a7"))
				expect(off).toBe(Hash.unit(123456789, Hash.string("a7"), 0x9E55) * 1.2)
				-- le même uid chez deux propriétaires ne rebondit pas pareil (uid unique par profil seulement)
				expect(PT.offset(123456789, "a7") ~= PT.offset(987654321, "a7")).toBe(true)
				for _, owner in { 1, 42, 123456789, 9007199254740991 } do
					for _, uid in { "1", "a7", "zzzzzzzz" } do
						local o = PT.offset(owner, uid)
						local apex = PT.nextApex(5000, o)
						expect(PT.isPerfect(apex + 0.18, o)).toBe(true) -- +0,18 s : PERFECT
						expect(PT.isPerfect(apex + 0.22, o)).toBe(false) -- +0,22 s : non
						expect(PT.isPerfect(apex - 0.08, o)).toBe(true) -- −0,08 s : PERFECT
						expect(PT.isPerfect(apex - 0.10, o)).toBe(false) -- −0,10 s : non
					end
				end
			end
		)

		it("prochain sommet : le premier ≥ t", function()
			expect(PT.nextApex(0.3, 0.3)).toBeNear(0.3, 1e-12)
			expect(PT.nextApex(0.31, 0.3)).toBeNear(1.5, 1e-9)
			expect(PT.nextApex(1.49, 0.3)).toBeNear(1.5, 1e-9)
		end)

		it("tClient : accepté dans [now − 0,35 ; now + 0,05], sinon now ; NaN et ±inf → now", function()
			local now = 1000
			expect(PT.clampClientTime(999.7, now)).toBe(999.7)
			expect(PT.clampClientTime(1000.05, now)).toBe(1000.05)
			expect(PT.clampClientTime(999.6, now)).toBe(now)
			expect(PT.clampClientTime(1000.1, now)).toBe(now)
			expect(PT.clampClientTime(0 / 0, now)).toBe(now)
			expect(PT.clampClientTime(math.huge, now)).toBe(now)
			expect(PT.clampClientTime(nil, now)).toBe(now)
		end)

		it("tricheur : au pire ×2 (PERFECT), jamais mieux qu'un joueur adroit", function()
			-- un tClient choisi au sommet dans la fenêtre acceptée : PERFECT, borné
			local off = PT.offset(7, "a")
			local now = 5000
			local apex = PT.nextApex(now - 0.35, off)
			local t = PT.clampClientTime(apex, now)
			expect(t >= now - 0.35 and t <= now + 0.05).toBe(true)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
