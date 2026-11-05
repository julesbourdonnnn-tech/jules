--!nocheck
-- Props_Prestige (paquet A1, docs/04 §27.10, §27.9) : propriétés de Prestige sur des milliers de
-- profils tirés à graine fixe (tests/harness/Props), abîmés compris, et une carrière complète
-- jusqu'à MaxA et MaxR. Invariant de stabilité (GDD §4.27, critique M13) ; squishies jamais perdus ;
-- Record R, Confettis, A et Atelier jamais en baisse ; apply deux fois = apply une fois ; jamais NaN
-- ni inf ; toutes les tailles à 1 après un prestige.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local KINDS = { "splorch", "petit", "ascend", "nope" }
	local AT = { "pen", "pool", "dodo", "mail" }
	local WEIRD = { 0 / 0, math.huge, -math.huge, -1, 1e308, "x" }

	local function finite(x)
		return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
	end

	-- Profil v2 tiré au hasard (graine fixe) : progression, dalles, Atelier, pièces, squishies, parfois
	-- abîmé ; prêt pour un Grand Splorch une fois sur deux
	local function randomCase(rng)
		local d = Schema.defaultsFor(2)
		local R = rng.int(0, MAX_R)
		d.R = R
		d.bestR = if rng.chance(0.1)
			then rng.int(0, R)
			elseif rng.chance(0.35) then R
			else math.min(MAX_R, R + rng.int(0, 40))
		d.ascend = rng.int(0, MAX_A)
		d.regainBonusA = rng.int(0, d.ascend)
		if rng.chance(0.3) then
			d.memoryR = rng.int(0, MAX_R)
		end
		d.coins = if rng.chance(0.1) then rng.pick(WEIRD) else rng.range(0, 1e20)
		d.pot = rng.range(0, 1e12)
		d.confetti = rng.int(0, 5000)
		d.confettiTotal = d.confetti + rng.int(0, 5000)
		d.tiles.snack = rng.int(0, 12)
		d.tiles.star = rng.int(0, 8)
		d.tiles.decor = rng.int(0, 18)
		d.tiles.pens = rng.int(0, 14)
		d.tiles.gloves = rng.int(0, 40)
		d.tiles.school = rng.int(0, 20)
		d.tiles.monuments = rng.int(0, 10)
		d.tiles.cozyBed = rng.chance(0.5)
		for i, row in Upgrades.WorkshopRows do
			d.atelier[i] = if rng.chance(0.05) then rng.pick(WEIRD) else rng.int(0, #row.costs)
		end
		d.growth = { G = rng.range(0, 1e9), g = rng.range(1, 1e6), t = rng.range(0, 1e5) }
		d.squishies = {}
		for k = 1, rng.int(0, 6) do
			d.squishies["u" .. k] = {
				s = rng.int(1, 26),
				m = rng.int(0, 9),
				st = rng.int(0, 5),
				z = rng.range(1, 1e9),
				zg = rng.range(0, 1e9),
				bf = rng.int(0, 3),
				lk = rng.chance(0.5),
				o = "",
				at = rng.pick(AT),
				b = 0,
				gd = 0,
			}
		end
		if rng.chance(0.5) and d.squishies.u1 then
			d.squishies.u1.z = Prestige.target(R) * rng.range(1, 3)
			d.squishies.u1.at = "dodo" -- taille figée : prête quel que soit G
		end
		local now = if rng.chance(0.03) then 0 / 0 else d.growth.t + rng.range(0, 1e5)
		return { d = d, kind = rng.pick(KINDS), now = now }
	end

	-- Égalité profonde où NaN vaut NaN (une sauvegarde abîmée garde ses NaN tant qu'on n'y touche pas)
	local function same(a, b)
		if a ~= a and b ~= b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not same(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function failIf(cond, why)
		if cond then
			error(why, 0)
		end
	end

	describe("Props › Prestige.apply", function()
		it(
			"4 000 profils : squishies jamais perdus ; Record R, Confettis, A et Atelier jamais en baisse ; bornes",
			function()
				local applied = { splorch = 0, petit = 0, ascend = 0 }
				Props.check(4000, Props.gen(randomCase), function(case)
					local d = case.d
					local before = Tables.deepCopy(d)
					local bestBefore, aBefore = Prestige.bestR(before), Prestige.ascend(before)
					local changed, report = Prestige.apply(d, case.kind, case.now)
					-- jamais en baisse
					failIf(Prestige.bestR(d) < bestBefore, "Record R en baisse")
					failIf(Prestige.ascend(d) < aBefore, "A en baisse")
					failIf(d.ascend ~= before.ascend and d.ascend ~= before.ascend + 1, "A saute")
					failIf(not same(d.atelier, before.atelier), "Atelier changé")
					failIf(not same(d.atelierCosmetics, before.atelierCosmetics), "cosmétiques changés")
					failIf(
						d.confetti ~= before.confetti or d.confettiTotal ~= before.confettiTotal,
						"Confettis écrits"
					)
					failIf(d.fame ~= before.fame, "Fame écrite")
					failIf(d.tiles.pens < before.tiles.pens, "Enclos en baisse")
					failIf(d.tiles.monuments ~= before.tiles.monuments, "Monuments changés")
					failIf(d.tiles.cozyBed ~= before.tiles.cozyBed, "Lit douillet changé")
					-- squishies jamais perdus ni changés (sauf la taille)
					for uid, old in before.squishies do
						local rec = d.squishies[uid]
						failIf(rec == nil, "squishy perdu " .. uid)
						for _, key in { "s", "m", "st", "bf", "lk", "o", "at", "b", "gd" } do
							failIf(rec[key] ~= old[key], "squishy changé " .. uid .. "." .. key)
						end
					end
					for uid in d.squishies do
						failIf(before.squishies[uid] == nil, "squishy créé " .. uid)
					end
					-- rapport fini, ≥ 0
					for _, key in
						{ "confetti", "confettiBase", "lost", "fame", "skipped", "keptDecor", "giftLevels" }
					do
						failIf(not finite(report[key]) or report[key] < 0, "rapport " .. key)
					end
					if not report.applied then
						failIf(next(changed) ~= nil, "clés changées sans application")
						failIf(not same(d, before), "profil touché sans application")
						return true
					end
					-- appliqué : bornes, tout repart de zéro, toutes les tailles à 1
					applied[report.kind] += 1
					local r, best, A = d.R, d.bestR, d.ascend
					failIf(not (r >= 0 and r <= best and best <= MAX_R and A <= MAX_A), "bornes r, bestR, A")
					failIf(d.coins ~= 0 or d.pot ~= 0, "pièces gardées")
					failIf(d.tiles.star > Prestige.starCap(r), "Tapis Étoilé au-delà du plafond")
					failIf(d.tiles.decor > Balance.SplorchV2.KeptDecorMax, "plus de 12 décorations gardées")
					failIf(
						d.tiles.snack + report.giftLevels > Balance.SplorchV2.FreeSnackMax,
						"plus de 6 niveaux offerts"
					)
					failIf(
						d.tiles.gloves ~= 0 or d.tiles.school ~= 0 or d.tiles.star ~= 0,
						"dalles de la boucle gardées"
					)
					for uid, rec in d.squishies do
						failIf(rec.z ~= 1 or rec.zg ~= 0, "taille non remise à 1 : " .. uid)
					end
					failIf(d.growth.G ~= 0 or d.growth.t ~= case.now or not finite(d.growth.g), "croissance")
					failIf(
						report.toR ~= r or report.bestR ~= best or report.ascend ~= A,
						"rapport ≠ profil"
					)
					if report.kind == "ascend" then
						failIf(A ~= aBefore + 1, "A + 1")
						failIf(
							r ~= Prestige.startR(A, 0) + report.skipped or report.skipped > 3,
							"départ et Tremplin"
						)
						failIf(r >= best, "départ au-dessus du record")
					else
						failIf(r ~= Prestige.r(before) + 1, "r + 1")
						failIf(report.record ~= (r > bestBefore), "record")
					end
					for key in changed do
						failIf(
							type(key) ~= "string" or d[key] == nil,
							"clé changée inconnue " .. tostring(key)
						)
					end
					-- apply deux fois (même instant) = apply une fois
					local once = Tables.deepCopy(d)
					local again, report2 = Prestige.apply(d, case.kind, case.now)
					failIf(next(again) ~= nil or report2.applied, "second apply a changé quelque chose")
					failIf(not same(d, once), "second apply a touché le profil")
					return true
				end)
				-- le tirage exerce vraiment les trois sortes (sinon la propriété serait vide)
				expect(applied.splorch > 300 and applied.petit > 300 and applied.ascend > 300).toBe(true)
			end
		)

		it(
			"carrière complète (Ascension dès qu'elle est prête) jusqu'à MaxA puis MaxR : Confettis exacts, jamais NaN",
			function()
				local d = Schema.defaultsFor(2)
				d.tiles.pens = Balance.Tiles.pens.Levels -- places offertes sur un enclos plein : +25
				d.squishies = {
					a = {
						s = 1,
						m = 0,
						st = 0,
						z = 1,
						zg = 0,
						bf = 1,
						lk = false,
						o = "",
						at = "pen",
						b = 0,
						gd = 0,
					},
				}
				local now = 0
				local confetti, petits, records, regains, ascends, fullPens = 0, 0, 0, 0, 0, 0
				local lastBest, lastA = 0, 0
				local steps = 0
				while steps < 10000 do
					steps += 1
					now += 1
					local kind
					if Prestige.ascendReady(d) then
						kind = "ascend"
					elseif Prestige.r(d) < MAX_R then
						d.squishies.a.z = Prestige.target(Prestige.r(d))
						kind = Prestige.nextKind(d)
					else
						break
					end
					local fromR = Prestige.r(d)
					local _, report = Prestige.apply(d, kind, now)
					expect({ step = steps, applied = report.applied }).toEqual({
						step = steps,
						applied = true,
					})
					confetti += report.confetti
					if report.kind == "ascend" then
						ascends += 1
						-- le départ est toujours sous le record : la remontée existe (Petits Splorch, retour)
						expect(report.toR < Prestige.bestR(d)).toBe(true)
					elseif report.record then
						records += 1
						if report.fullPen then
							fullPens += 1
						end
					else
						petits += 1
						if report.regain then
							regains += 1
						end
					end
					expect(Prestige.bestR(d) >= lastBest and Prestige.ascend(d) >= lastA).toBe(true)
					lastBest, lastA = Prestige.bestR(d), Prestige.ascend(d)
					expect(finite(d.growth.g) and finite(report.confetti)).toBe(true)
					if report.kind ~= "ascend" then
						expect(Prestige.r(d)).toBe(fromR + 1)
					end
				end
				expect({ R = Prestige.r(d), best = Prestige.bestR(d), A = Prestige.ascend(d) }).toEqual({
					R = MAX_R,
					best = MAX_R,
					A = MAX_A,
				})
				expect({ records = records, ascends = ascends, regains = regains, fullPens = fullPens }).toEqual({
					records = MAX_R,
					ascends = MAX_A,
					regains = MAX_A, -- un retour au record par Ascension, jamais deux
					fullPens = 4,
				})
				-- Confettis : premier passage de chaque Record R, + 1 par Petit Splorch, + 10 par retour, + 20
				-- par Ascension, + 25 par place offerte sur un enclos plein (aucun Tremplin)
				local expected = Schema.confettiCatchUp(MAX_R) + petits + 10 * MAX_A + 20 * MAX_A + 25 * 4
				expect(confetti).toBe(expected)
				-- après la dernière Ascension, plus rien : ni Ascension, ni Grand Splorch à MaxR
				d.squishies.a.z = Balance.Numbers.Max
				expect(next((Prestige.apply(d, "ascend", now + 1)))).toBeNil()
				expect(next((Prestige.apply(d, "splorch", now + 1)))).toBeNil()
			end
		)
	end)

	describe("Props › invariant de stabilité", function()
		it(
			"validateConfig = (BeyondMult / 2)^ReqStep ≥ 0,95 × GrowthMult et objectifs × 2,5 dès r = 16, sur 3 000 réglages",
			function()
				expect((Prestige.validateConfig(Balance))).toBe(true)
				Props.check(
					3000,
					Props.gen(function(rng)
						return {
							step = rng.int(1, 8),
							beyond = rng.pick({ 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3, 3.5 }),
							growth = rng.pick({ 1.5, 2, 2.5, 2.8, 3, 3.2, 4, 6 }),
							tail = rng.pick({ 2.3, 2.5, 2.6, 2.9 }), -- rapport des 3 derniers objectifs de la table
						}
					end),
					function(c)
						local b = Tables.deepCopy(Balance)
						b.Ascend.ReqStep = c.step
						b.Splorch.BeyondMult = c.beyond
						b.Ascend.GrowthMult = c.growth
						for i = 18, 20 do
							b.Splorch.Targets[i] = b.Splorch.Targets[i - 1] * c.tail
						end
						-- référence indépendante (puissance permise dans le test) : objectifs refaits ici
						local stable = (c.beyond / 2) ^ c.step >= 0.95 * c.growth
						local t = {}
						for r = 0, Balance.Prestige.MaxR do
							if r < #b.Splorch.Targets then
								t[r] = b.Splorch.Targets[r + 1]
							else
								t[r] = math.min(1e300, tonumber(string.format("%.1e", t[r - 1] * c.beyond)))
							end
							if r > 16 and t[r] < 1e300 and t[r] < 2.5 * t[r - 1] then
								stable = false
							end
						end
						local ok, why = Prestige.validateConfig(b)
						if ok ~= stable then
							error(
								string.format(
									"validateConfig %s (%s), attendu %s",
									tostring(ok),
									tostring(why),
									tostring(stable)
								),
								0
							)
						end
						return true
					end
				)
			end
		)

		it(
			"valeurs livrées : la dernière boucle record avant chaque Ascension garde sa difficulté (au plus 10 % plus facile d'une Ascension à l'autre, au plus un Grand Splorch plus dure, jamais à plus de 30 % de celle de la 1re)",
			function()
				-- difficulté de la boucle record après A Ascensions (r = condition de la suivante − 1) :
				-- objectif(r) ÷ (2^r × 3^A) ; + 4 par Ascension donne × 0,952 (arrondis des objectifs à 2
				-- chiffres significatifs : 0,92 à 0,99), le Grand Splorch de plus toutes les 8 Ascensions
				-- (Balance.Ascend.ReqR, docs/04 §21) × 1,3 : la difficulté reste entre 0,73 et 1 fois celle
				-- de la 1re Ascension jusqu'à MaxA (avec + 4 seul, elle tombait à 0,13 : boucles record de plus
				-- en plus courtes, une Ascension tous les 3 jours pour le joueur de 2 h par jour)
				local function difficulty(A)
					local r = Prestige.reqR(A + 1) - 1
					local g = 1
					for _ = 1, r do
						g *= 2
					end
					return Prestige.target(r) / (g * Prestige.growthFactor(r, A, r, false))
				end
				local first = difficulty(1)
				for A = 1, MAX_A - 1 do
					local q = difficulty(A + 1) / difficulty(A)
					local rel = difficulty(A + 1) / first
					expect({ A = A, step = q >= 0.9 and q <= 1.35, drift = rel >= 0.7 and rel <= 1.05 }).toEqual({
						A = A,
						step = true,
						drift = true,
					})
				end
			end
		)
	end)
end
