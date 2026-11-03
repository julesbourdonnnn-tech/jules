--!nocheck
-- Props_UpgradeMath (paquet A1, règle 5 du GDD §10.8, docs/04 §27.8) : propriétés du calcul des
-- prix sur des milliers de cas tirés à graine fixe. « bulk(n) = somme de n achats ×1 » ; « aperçu =
-- débit réel » (10 000 cas, montants tout juste suffisants compris) ; « coûts strictement
-- croissants, Tapis 12 → Étoilé 13 compris » pour chaque A de 0 à MaxA dès son Grand Splorch de
-- départ ; « jamais NaN ni inf à MaxR et MaxA ».
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")

	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local IDS = UpgradeMath.ids()
	local MODES = { 1, 10, 0 }

	local function isPrice(p)
		return type(p) == "number" and p == p and p >= 1 and p <= Balance.Numbers.Max and p % 1 == 0
	end

	-- r, A et Record R cohérents (r ≥ départ de A, r ≤ Record R), parfois aux bornes
	local function state(rng)
		local A = if rng.chance(0.1) then MAX_A elseif rng.chance(0.3) then 0 else rng.int(0, MAX_A)
		local start = Prestige.startR(A, 0)
		local r = if rng.chance(0.1) then MAX_R else rng.int(start, MAX_R)
		local best = if rng.chance(0.5) then r else rng.int(r, MAX_R)
		return r, A, best
	end

	describe("Props › UpgradeMath", function()
		it("bulk(n) = somme de n achats ×1, dans l'ordre (10 000 cas)", function()
			Props.check(
				10000,
				Props.gen(function(rng)
					local id = rng.pick(IDS)
					local r, A, best = state(rng)
					return {
						id = id,
						from = rng.int(0, UpgradeMath.maxLevel(id)),
						n = rng.int(0, 45),
						r = r,
						A = A,
						best = best,
					}
				end),
				function(c)
					local count, total = UpgradeMath.bulk(c.id, c.from, c.n, c.r, c.A, c.best)
					local want = math.max(0, math.min(c.n, UpgradeMath.maxLevel(c.id) - c.from))
					if count ~= want then
						error("count " .. count .. " ≠ " .. want, 0)
					end
					local sum = 0
					for k = 0, count - 1 do
						sum += UpgradeMath.price(c.id, c.from + k, c.r, c.A, c.best)
					end
					if sum ~= total then
						error(string.format("total %.17g ≠ somme %.17g", total, sum), 0)
					end
					-- additivité exacte tant que les sommes sont des entiers exacts
					if count >= 2 and total < 2 ^ 53 then
						local a = count // 2
						local _, t1 = UpgradeMath.bulk(c.id, c.from, a, c.r, c.A, c.best)
						local _, t2 = UpgradeMath.bulk(c.id, c.from + a, count - a, c.r, c.A, c.best)
						if t1 + t2 ~= total then
							error("additivité", 0)
						end
					end
					return total == total and total < math.huge
				end
			)
		end)

		it(
			"aperçu (plan) = débit réel de n achats ×1 du serveur (10 000 cas, montants tout juste suffisants)",
			function()
				Props.check(
					10000,
					Props.gen(function(rng)
						local id = rng.pick(IDS)
						local r, A, best = state(rng)
						local maxL = UpgradeMath.maxLevel(id)
						local from = rng.int(0, maxL)
						local cap = if rng.chance(0.7) then maxL else rng.int(0, maxL)
						local mode = rng.pick(MODES)
						-- montant : au hasard, ou exactement la somme de k niveaux (± 1)
						local money
						if rng.chance(0.5) then
							local _, exact = UpgradeMath.bulk(id, from, rng.int(0, 12), r, A, best)
							money = exact + rng.pick({ -1, 0, 0, 1 })
						else
							money = UpgradeMath.price(id, math.min(from, maxL - 1), r, A, best)
								* rng.range(0, 30)
						end
						return {
							id = id,
							from = from,
							cap = cap,
							mode = mode,
							money = money,
							r = r,
							A = A,
							best = best,
						}
					end),
					function(c)
						local count, total =
							UpgradeMath.plan(c.id, c.from, c.mode, c.money, c.cap, c.r, c.A, c.best)
						-- référence : le serveur achète niveau par niveau, tant que la somme tient dans les pièces
						local limit = math.min(
							if c.mode == 0 then Balance.Upgrades.BulkMax else c.mode,
							c.cap - c.from,
							Balance.Upgrades.BulkMax
						)
						local have = math.max(0, c.money)
						local level, spent, n = c.from, 0, 0
						while n < limit and level < UpgradeMath.maxLevel(c.id) do
							local p = UpgradeMath.price(c.id, level, c.r, c.A, c.best)
							if spent + p > have then
								break
							end
							spent += p
							level += 1
							n += 1
						end
						if n ~= count or spent ~= total then
							error(
								string.format("aperçu %d / %.17g, débit %d / %.17g", count, total, n, spent),
								0
							)
						end
						-- jamais de pièces négatives après le débit
						return have - total >= 0
					end
				)
			end
		)

		it(
			"maxAffordable : croît avec les pièces ; total ≤ pièces ; le niveau suivant ne tiendrait pas",
			function()
				Props.check(
					5000,
					Props.gen(function(rng)
						local id = rng.pick(IDS)
						local r, A, best = state(rng)
						local p = UpgradeMath.price(id, 0, r, A, best)
						return {
							id = id,
							from = rng.int(0, UpgradeMath.maxLevel(id)),
							a = p * rng.range(0, 50),
							b = p * rng.range(0, 50),
							r = r,
							A = A,
							best = best,
						}
					end),
					function(c)
						local lo, hi = math.min(c.a, c.b), math.max(c.a, c.b)
						local n1, t1 = UpgradeMath.maxAffordable(c.id, c.from, lo, c.r, c.A, c.best)
						local n2, t2 = UpgradeMath.maxAffordable(c.id, c.from, hi, c.r, c.A, c.best)
						if n1 > n2 or t1 > lo or t2 > hi then
							return false
						end
						local level = c.from + n2
						if level < UpgradeMath.maxLevel(c.id) then
							return t2 + UpgradeMath.price(c.id, level, c.r, c.A, c.best) > hi
						end
						return true
					end
				)
			end
		)

		it(
			"coûts strictement croissants, Tapis 12 → Étoilé 13 compris, pour chaque A = 0 … MaxA dès son départ",
			function()
				local checked = 0
				for A = 0, MAX_A do
					local start = Prestige.startR(A, 0)
					for r = start, MAX_R do
						-- ligne du Tapis : 12 niveaux puis les 8 du Tapis Étoilé
						local last = -1
						for L = 0, 11 do
							local p = UpgradeMath.price("snack", L, r, A, r)
							if not (p > last) then
								error(
									string.format("Tapis %d ≤ précédent à r = %d, A = %d", L + 1, r, A),
									0
								)
							end
							last = p
						end
						for L = 0, 7 do
							local p = UpgradeMath.price("star", L, r, A, r)
							if not (p > last) then
								error(
									string.format(
										"Étoilé %d ≤ précédent à r = %d, A = %d",
										L + 13,
										r,
										A
									),
									0
								)
							end
							last = p
						end
						for _, def in Upgrades.Families do
							if def.id ~= "snack" and def.id ~= "star" then
								local prev = -1
								for L = 0, def.levels - 1 do
									local p = UpgradeMath.price(def.id, L, r, A, math.min(MAX_R, r + (A % 7)))
									if not (p > prev) then
										error(
											string.format(
												"%s %d ≤ précédent à r = %d, A = %d",
												def.id,
												L + 1,
												r,
												A
											),
											0
										)
									end
									prev = p
								end
							end
						end
						checked += 1
					end
				end
				expect(checked > 15000).toBe(true)
			end
		)

		it(
			"jamais NaN ni inf à MaxR et MaxA : chaque niveau de chaque ligne, r et Record R aux bornes",
			function()
				for _, id in IDS do
					for _, A in { 0, 1, MAX_A } do
						for _, r in { 0, Prestige.startR(A, 0), MAX_R } do
							for _, best in { r, MAX_R } do
								for L = 0, UpgradeMath.maxLevel(id) - 1 do
									local p = UpgradeMath.price(id, L, r, A, best)
									expect({ id = id, A = A, r = r, best = best, L = L, ok = isPrice(p) }).toEqual({
										id = id,
										A = A,
										r = r,
										best = best,
										L = L,
										ok = true,
									})
								end
								local _, total = UpgradeMath.bulk(id, 0, UpgradeMath.maxLevel(id), r, A, best)
								expect(total == total and total < math.huge).toBe(true)
								local _, afford =
									UpgradeMath.maxAffordable(id, 0, Balance.Numbers.Max, r, A, best)
								expect(afford == afford and afford < math.huge).toBe(true)
							end
						end
					end
				end
				-- le prix le plus haut possible (Gants 40 à r = MaxR, A = 0) reste sous la borne des pièces
				local top = UpgradeMath.price("gloves", 39, MAX_R, 0, MAX_R)
				expect(isPrice(top) and top < 1e300).toBe(true)
			end
		)

		it(
			"entrées tirées au hasard (NaN, ±inf, chaînes, tables) : jamais d'erreur, prix ≥ 1 ou math.huge",
			function()
				Props.check(
					5000,
					Props.tuple(Props.oneOf(IDS), Props.any(), Props.any(), Props.any(), Props.any()),
					function(v)
						local p = UpgradeMath.price(v[1], v[2], v[3], v[4], v[5])
						local count, total = UpgradeMath.bulk(v[1], v[2], v[3], v[4], v[5], v[2])
						local c2, t2 = UpgradeMath.plan(v[1], v[2], v[3], v[4], v[5], v[2], v[3], v[4])
						return (p == math.huge or isPrice(p))
							and count >= 0
							and total == total
							and total < math.huge
							and c2 >= 0
							and t2 == t2
					end
				)
			end
		)
	end)
end
