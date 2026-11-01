--!nocheck
-- Squash (paquet world, docs/04 §12.2, GDD §5.2, §9.1, §9.3, §9.4) : profils d'écrasement aux
-- valeurs du GDD (étapes, durées, easings), amplitude × 0,5 en Mouvement réduit, volume à peu près
-- gardé, animation de repos (rebond de 1,2 s calé sur le PERFECT de Logic/PressTiming, contact au
-- sol (1 + a ; 1 − a ; 1 + a), tremblement amorti), entrées bizarres sûres.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function load()
		local h = Harness.new()
		return h, h:require("ReplicatedStorage.Shared.Render.Squash")
	end

	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-9)
	end

	describe("Squash › profils (GDD §9.4)", function()
		it(
			"8 profils ; durée = somme des étapes (press 0,53 s, perfect 0,53 s, sneeze 0,38 s…)",
			function()
				local _, S = load()
				local names = {}
				for name in S.PROFILES do
					table.insert(names, name)
				end
				table.sort(names)
				expect(names).toEqual({
					"fuse",
					"hatch",
					"hop",
					"land",
					"mount",
					"perfect",
					"press",
					"sneeze",
				})
				expect(near(S.duration("press"), 0.53)).toBe(true)
				expect(near(S.duration("perfect"), 0.53)).toBe(true)
				expect(near(S.duration("land"), 0.28)).toBe(true)
				expect(near(S.duration("sneeze"), 0.38)).toBe(true)
				expect(near(S.duration("mount"), 0.32)).toBe(true)
				expect(S.duration("inconnu")).toBe(0)
				expect(S.duration(nil)).toBe(0)
			end
		)

		it(
			"press : (1 ; 1 ; 1) → (1,35 ; 0,60 ; 1,35) à 0,06 s → (0,85 ; 1,25 ; 0,85) à 0,18 s → (1 ; 1 ; 1)",
			function()
				local _, S = load()
				local x, y, z, done = S.sample("press", 0)
				expect({ x, y, z, done }).toEqual({ 1, 1, 1, false })
				x, y, z = S.sample("press", 0.06)
				expect(near(x, 1.35) and near(y, 0.6) and near(z, 1.35)).toBe(true)
				x, y, z = S.sample("press", 0.18)
				expect(near(x, 0.85) and near(y, 1.25) and near(z, 0.85)).toBe(true)
				x, y, z, done = S.sample("press", 0.53)
				expect({ x, y, z, done }).toEqual({ 1, 1, 1, true })
				-- PERFECT : plus écrasé
				x, y = S.sample("perfect", 0.06)
				expect(near(x, 1.45) and near(y, 0.5)).toBe(true)
				-- sneeze et hop
				x, y = S.sample("sneeze", 0.08)
				expect(near(x, 1.5) and near(y, 0.6)).toBe(true)
				x, y = S.sample("hop", 0.08)
				expect(near(x, 0.85) and near(y, 1.25)).toBe(true)
			end
		)

		it(
			"valeurs toujours finies et bornées, volume à peu près gardé au plus fort de l'écrasement",
			function()
				local _, S = load()
				for name in S.PROFILES do
					local dur = S.duration(name)
					for i = 0, 200 do
						local t = dur * i / 200
						local x, y, z = S.sample(name, t)
						for _, v in { x, y, z } do
							expect(v == v and v >= S.Idle.MinScale and v <= S.Idle.MaxScale).toBe(true)
						end
					end
				end
				local x, y, z = S.sample("press", 0.06)
				expect(math.abs(x * y * z - 1) < 0.15).toBe(true)
			end
		)

		it("Mouvement réduit : amplitude 0,5 → écart à 1 divisé par deux", function()
			local _, S = load()
			for _, t in { 0.03, 0.06, 0.12, 0.3 } do
				local x, y, z = S.sample("press", t)
				local hx, hy, hz = S.sample("press", t, 0.5)
				expect(near(hx - 1, (x - 1) / 2, 1e-9)).toBe(true)
				expect(near(hy - 1, (y - 1) / 2, 1e-9)).toBe(true)
				expect(near(hz - 1, (z - 1) / 2, 1e-9)).toBe(true)
			end
			local x = S.sample("press", 0.06, 0)
			expect(x).toBe(1)
		end)

		it(
			"entrées bizarres : profil inconnu, t NaN / ±inf / négatif, amplitude bizarre → sûr",
			function()
				local _, S = load()
				for _, p in { "nope", nil, 3, {} } do
					local x, y, z, done = S.sample(p, 0.1)
					expect({ x, y, z, done }).toEqual({ 1, 1, 1, true })
				end
				for _, t in { 0 / 0, math.huge, -math.huge } do
					local x, y, z, done = S.sample("press", t)
					expect({ x, y, z, done }).toEqual({ 1, 1, 1, true })
				end
				local x, y, z, done = S.sample("press", -1)
				expect({ x, y, z, done }).toEqual({ 1, 1, 1, false })
				for _, a in { 0 / 0, math.huge, -5, "x" } do
					local sx = S.sample("press", 0.06, a)
					expect(sx == sx and sx >= 0.2 and sx <= 3).toBe(true)
				end
			end
		)
	end)

	describe("Squash › animation de repos (GDD §5.2, §9.3)", function()
		it(
			"période 1,2 s (Balance.Press.Period) ; sommet (0,18 D) à la phase 0 de PressTiming ; contact au milieu",
			function()
				local h, S = load()
				local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
				local PressTiming = h:require("ReplicatedStorage.Shared.Logic.PressTiming")
				expect(S.Idle.Period).toBe(Balance.Press.Period)
				local offset = PressTiming.offset(42, "7")
				local apex = PressTiming.nextApex(1000, offset)
				local _, _, _, top = S.idle(apex, offset, 1, 0.08)
				expect(near(top, 0.18, 1e-6)).toBe(true)
				local sx, sy, sz, ground = S.idle(apex + Balance.Press.Period / 2, offset, 1, 0.08)
				expect(ground).toBe(0)
				expect(near(sx, 1.08) and near(sy, 0.92) and near(sz, 1.08)).toBe(true)
				-- périodique
				local a = { S.idle(apex + 0.37, offset, 1.3, 0.1) }
				local b = { S.idle(apex + 0.37 + 5 * Balance.Press.Period, offset, 1.3, 0.1) }
				for i = 1, 4 do
					expect(near(a[i], b[i], 1e-6)).toBe(true)
				end
			end
		)

		it("hauteur dans [0 ; 0,18], écrasement borné, tremblement amorti après le contact", function()
			local _, S = load()
			local period = S.Idle.Period
			for i = 0, 1199 do
				local t = i * period / 1200
				local sx, sy, sz, height = S.idle(t, 0, 1.4, 0.12)
				expect(height >= 0 and height <= 0.18 + 1e-9).toBe(true)
				for _, v in { sx, sy, sz } do
					expect(v >= 0.8 and v <= 1.2).toBe(true)
				end
			end
			-- après le contact (milieu de la période), l'écart à 1 diminue
			local contactEnd = period / 2 + S.Idle.Contact / 2
			local early, late = 0, 0
			for i = 0, 99 do
				local _, e = S.idle(contactEnd + 0.01 + i * 0.001, 0, 2, 0.18)
				local _, l = S.idle(contactEnd + 0.4 + i * 0.001, 0, 2, 0.18)
				early = math.max(early, math.abs(e - 1))
				late = math.max(late, math.abs(l - 1))
			end
			expect(late < early).toBe(true)
		end)

		it("entrées bizarres (NaN, ±inf, négatif) : valeurs finies", function()
			local _, S = load()
			for _, v in { 0 / 0, math.huge, -math.huge, -3 } do
				local sx, sy, sz, height = S.idle(v, v, v, v)
				for _, x in { sx, sy, sz, height } do
					expect(x == x and x > -1 and x < 4).toBe(true)
				end
			end
		end)
	end)
end
