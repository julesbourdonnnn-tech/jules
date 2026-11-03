--!nocheck
-- Prestige (paquet A1, docs/04 §27.7, GDD v2.0 §4.15, §4.26, §4.27, §4.29) : seule source de r, du
-- Record R et de A. Cas exacts du GDD et de la simulation du design (scratchpad v2/gdd/sim) :
-- objectifs, croissance × 3^A × Souvenir, conditions 15, 20, +4, Grand Splorch de départ, facteur
-- des prix, Confettis (cumul du GDD et rattrapage de la migration), déblocages, décorations
-- gardées, plafond du Tapis Étoilé, invariant de stabilité ; apply : Grand Splorch, Petit Splorch,
-- retour au record, places offertes, Ascension et Tremplin, sur la sauvegarde-témoin v2.json et
-- aux bords (profil vide, r = 0, MaxR, A = 0, MaxA, bestR < r abîmé, entrées hostiles).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local W = Upgrades.WorkshopIndex

	-- Profil v2 par défaut avec un squishy d'enclos de taille z (prêt si z ≥ objectif)
	local function profile(fields)
		local d = Schema.defaultsFor(2)
		d.squishies = {
			["1"] = {
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
		d.growth = { G = 0, g = 1, t = 0 }
		for k, v in fields or {} do
			if k == "tiles" or k == "atelierLevels" then
				continue
			end
			d[k] = v
		end
		for k, v in (fields and fields.tiles) or {} do
			d.tiles[k] = v
		end
		for id, v in (fields and fields.atelierLevels) or {} do
			d.atelier[W[id]] = v
		end
		return d
	end

	-- Rend le profil prêt pour un Grand ou Petit Splorch (plus gros = objectif de r)
	local function ready(d)
		d.squishies["1"].z = Prestige.target(Prestige.r(d))
		return d
	end

	local function readV2()
		return serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
	end

	describe("Prestige › objectifs, croissance, conditions", function()
		it(
			"objectifs du GDD §4.15 (table puis × 2,6 arrondi) = Formulas.splorchTarget, de r = 0 à MaxR, jamais inf",
			function()
				local gdd = {
					15000,
					39000,
					100000,
					260000,
					690000,
					1.8e6,
					4.6e6,
					12e6,
					31e6,
					81e6,
					210e6,
					550e6,
					1.4e9,
					3.7e9,
					9.7e9,
					25e9,
					65e9,
					170e9,
					440e9,
					1.1e12,
				}
				for r = 0, 19 do
					expect(Prestige.target(r)).toBe(gdd[r + 1])
				end
				expect(Prestige.target(20)).toBe(2.9e12)
				for r = 0, MAX_R do
					local t = Prestige.target(r)
					expect({ r = r, same = t == Formulas.splorchTarget(r) }).toEqual({ r = r, same = true })
					expect(t < math.huge and t == t and t > 0).toBe(true)
				end
				-- au-delà de MaxR et entrées hostiles : bornées, jamais d'erreur
				expect(Prestige.target(MAX_R + 50)).toBe(Prestige.target(MAX_R))
				expect(Prestige.target(0 / 0)).toBe(15000)
				expect(Prestige.target(-math.huge)).toBe(15000)
				expect(Prestige.target(math.huge)).toBe(Prestige.target(MAX_R))
			end
		)

		it(
			"croissance × 3^A × Souvenir : × 3 (écart ≥ 3), 2, 1,5, 1,25 sur la 1re boucle record, puis 1",
			function()
				expect(Prestige.growthFactor(0, 0, 0, false)).toBe(1)
				expect(Prestige.growthFactor(15, 1, 15, false)).toBe(3)
				expect(Prestige.growthFactor(20, 2, 20, false)).toBe(9)
				-- remontée après la 1re Ascension (Record R 15) : ×3 × Souvenir
				expect(Prestige.growthFactor(0, 1, 15, false)).toBe(9)
				expect(Prestige.growthFactor(12, 1, 15, false)).toBe(9) -- écart 3
				expect(Prestige.growthFactor(13, 1, 15, false)).toBe(6) -- écart 2
				expect(Prestige.growthFactor(14, 1, 15, false)).toBe(4.5) -- écart 1
				expect(Prestige.growthFactor(15, 1, 15, true)).toBe(3.75) -- 1re boucle record
				expect(Prestige.growthFactor(15, 1, 15, false)).toBe(3)
				-- jamais de × 1,25 sans Ascension ; bestR < r (abîmé) : aucun Souvenir
				expect(Prestige.growthFactor(15, 0, 15, true)).toBe(1)
				expect(Prestige.growthFactor(15, 2, 10, false)).toBe(9)
				expect(Prestige.memoryFactor(15, 15, true)).toBe(1.25)
				expect(Prestige.memoryFactor(16, 15, true)).toBe(1)
				-- « 9 fois plus vite » de l'aperçu
				expect(Prestige.regainSpeedup()).toBe(9)
				-- 3^A par multiplications : exact tant que 3^A < 2^53 (A ≤ 33), fini jusqu'à MaxA
				local p = 1
				for A = 0, MAX_A do
					expect(Prestige.growthFactor(5, A, 5, false)).toBe(p)
					if A <= 33 then
						expect(p).toBe(3 ^ A)
					end
					p *= 3
				end
				expect(Prestige.growthFactor(5, MAX_A + 9, 5, false)).toBe(
					Prestige.growthFactor(5, MAX_A, 5, false)
				)
				expect(Prestige.growthFactor(0 / 0, 0 / 0, 0 / 0, nil)).toBe(1)
			end
		)

		it(
			"conditions de l'Ascension : 15, 20, puis + 4 ; ascendReady (r ≥ condition, A < MaxA)",
			function()
				local got = {}
				for k = 1, 6 do
					table.insert(got, Prestige.reqR(k))
				end
				expect(got).toEqual({ 15, 20, 24, 28, 32, 36 })
				expect(Prestige.reqR(61)).toBe(256)
				expect(Prestige.reqR(0)).toBe(15)
				expect(Prestige.reqR(0 / 0)).toBe(15)
				expect(Prestige.ascendReady(profile({ R = 14, bestR = 14 }))).toBe(false)
				expect(Prestige.ascendReady(profile({ R = 15, bestR = 15 }))).toBe(true)
				expect(Prestige.ascendReady(profile({ R = 19, bestR = 30, ascend = 1 }))).toBe(false)
				expect(Prestige.ascendReady(profile({ R = 20, bestR = 30, ascend = 1 }))).toBe(true)
				expect(Prestige.ascendReady(profile({ R = MAX_R, bestR = MAX_R, ascend = MAX_A }))).toBe(
					false
				)
				expect(Prestige.ascendReady(profile({ R = MAX_R, bestR = MAX_R, ascend = MAX_A - 1 }))).toBe(
					true
				)
				expect(Prestige.ascendReady(nil)).toBe(false)
			end
		)

		it(
			"Grand Splorch de départ : 0, 4, 8, 13, 17, 21, 25, 29, 33, 38 ; le Tremplin s'ajoute ; toujours sous le record",
			function()
				local starts = {}
				for A = 1, 10 do
					table.insert(starts, Prestige.startR(A, 0))
				end
				expect(starts).toEqual({ 0, 4, 8, 13, 17, 21, 25, 29, 33, 38 })
				expect(Prestige.startR(0, 3)).toBe(0) -- sans Ascension : le début du jeu
				expect({ Prestige.startR(1, 1), Prestige.startR(1, 2), Prestige.startR(1, 3) }).toEqual({
					1,
					2,
					3,
				})
				expect(Prestige.startR(4, 3)).toBe(16)
				expect(Prestige.startR(1, 9)).toBe(3) -- Tremplin borné à ses 3 niveaux
				expect(Prestige.startR(1, -2)).toBe(0)
				expect(Prestige.startR(0 / 0, 0 / 0)).toBe(0)
				local q = math.log(3) / math.log(1.3)
				for A = 1, MAX_A do
					for sb = 0, 3 do
						local s = Prestige.startR(A, sb)
						-- jamais au-dessus de « condition suivante − 10 », donc toujours une remontée (Petits
						-- Splorch, retour au record) : StartR(A) < condition de la A-ième Ascension ≤ Record R
						expect(s <= Prestige.reqR(A + 1) - 10 and s < Prestige.reqR(A) and s >= 0).toBe(true)
						expect(s >= Prestige.startR(A, 0)).toBe(true)
					end
					-- plancher du GDD (A × ln 3 / ln 1,3 − 4,7) loin d'un entier : même résultat partout
					local x = A * q - Balance.Ascend.StartFloorOffset
					expect(math.abs(x - math.floor(x + 0.5)) > 1e-6).toBe(true)
				end
				expect(Prestige.startR(MAX_A, 0)).toBe(246)
			end
		)

		it(
			"facteur des prix F(A) : 0,5 aux 4 premières Ascensions, puis 0,32 ; fini et > 0 jusqu'à MaxA",
			function()
				local got = {}
				for A = 0, 6 do
					table.insert(got, math.floor(Prestige.priceFactor(A) * 1e6 + 0.5) / 1e6)
				end
				expect(got).toEqual({ 1, 0.5, 0.25, 0.125, 0.0625, 0.02, 0.0064 })
				expect(Prestige.priceFactor(4)).toBe(0.0625) -- exact (puissances de 2)
				local f = Prestige.priceFactor(MAX_A)
				expect(f > 0 and f < 1e-25).toBe(true)
				expect(Prestige.priceFactor(MAX_A + 1)).toBe(f)
				expect(Prestige.priceFactor(-1)).toBe(1)
			end
		)

		it(
			"plafond du Tapis Étoilé par r de la boucle : 0 avant 6, puis 1, 2, 3, 4, et 8 dès r = 10",
			function()
				local got = {}
				for r = 0, 12 do
					table.insert(got, Prestige.starCap(r))
				end
				expect(got).toEqual({ 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 8, 8, 8 })
				expect(Prestige.starCap(MAX_R)).toBe(8)
				expect(Prestige.starCap(0 / 0)).toBe(0)
			end
		)

		it(
			"lecture du profil : r, Record R (≥ r, profil v1 sans bestR), A ; valeurs abîmées bornées",
			function()
				local v1 = Schema.defaultsV1()
				v1.R = 7
				expect({ Prestige.r(v1), Prestige.bestR(v1), Prestige.ascend(v1) }).toEqual({ 7, 7, 0 })
				local d = profile({ R = 3, bestR = 15, ascend = 2 })
				expect({ Prestige.r(d), Prestige.bestR(d), Prestige.ascend(d) }).toEqual({ 3, 15, 2 })
				-- bestR < r (sauvegarde abîmée) : le Record R vaut au moins r
				expect(Prestige.bestR(profile({ R = 12, bestR = 4 }))).toBe(12)
				local bad = profile({ R = 0 / 0, bestR = math.huge, ascend = -4 })
				expect({ Prestige.r(bad), Prestige.bestR(bad), Prestige.ascend(bad) }).toEqual({ 0, MAX_R, 0 })
				local big = profile({ R = 1e9, bestR = 1e9, ascend = 1e9 })
				expect({ Prestige.r(big), Prestige.bestR(big), Prestige.ascend(big) }).toEqual({
					MAX_R,
					MAX_R,
					MAX_A,
				})
				expect({ Prestige.r(nil), Prestige.bestR("x"), Prestige.ascend(5) }).toEqual({ 0, 0, 0 })
				expect(Prestige.nextKind(profile({ R = 3, bestR = 15, ascend = 1 }))).toBe("petit")
				expect(Prestige.nextKind(profile({ R = 14, bestR = 15, ascend = 1 }))).toBe("petit")
				expect(Prestige.nextKind(profile({ R = 15, bestR = 15, ascend = 1 }))).toBe("splorch")
			end
		)

		it("1re boucle record : seulement au Record R du retour (memoryR), jamais sans le champ", function()
			local d = profile({ R = 15, bestR = 15, ascend = 1, regainBonusA = 1 })
			expect(Prestige.firstRecordLoop(d)).toBe(false) -- champ memoryR absent (note INT-A1-MEMORY)
			d.memoryR = 15
			expect(Prestige.firstRecordLoop(d)).toBe(true)
			d.R, d.bestR = 16, 16 -- boucle record suivante
			expect(Prestige.firstRecordLoop(d)).toBe(false)
			expect(
				Prestige.firstRecordLoop(
					profile({ R = 15, bestR = 15, ascend = 0, regainBonusA = 0, memoryR = 15 })
				)
			).toBe(false)
			expect(
				Prestige.firstRecordLoop(
					profile({ R = 14, bestR = 15, ascend = 1, regainBonusA = 1, memoryR = 15 })
				)
			).toBe(false)
			expect(Prestige.firstRecordLoop(nil)).toBe(false)
		end)
	end)

	describe("Prestige › Confettis, déblocages, décorations gardées", function()
		it(
			"Confettis : 3 + min(r, 20) au nouveau Record R, prime de 10 dès 21, Petit 1, Ascension 20 + Tremplin (3 au plus)",
			function()
				expect(Prestige.confettiGain("splorch", 1, 0, 0)).toBe(4)
				expect(Prestige.confettiGain("splorch", 10, 9, 0)).toBe(13)
				expect(Prestige.confettiGain("splorch", 20, 19, 0)).toBe(23)
				expect(Prestige.confettiGain("splorch", 21, 20, 0)).toBe(33)
				expect(Prestige.confettiGain("splorch", MAX_R, MAX_R - 1, 0)).toBe(33)
				expect(Prestige.confettiGain("petit", 11, 15, 0)).toBe(1)
				expect(Prestige.confettiGain("splorch", 11, 15, 0)).toBe(1) -- ne bat pas le record : Petit
				expect(Prestige.confettiGain("petit", 16, 15, 0)).toBe(19) -- bat le record : Grand
				expect(Prestige.confettiGain("ascend", 0, 15, 0)).toBe(20)
				expect(Prestige.confettiGain("ascend", 3, 15, 3)).toBe(23)
				expect(Prestige.confettiGain("ascend", 3, 15, 7)).toBe(23)
				expect(Prestige.confettiGain("ascend", 3, 15, 0 / 0)).toBe(20)
				expect(Prestige.confettiGain("nope", 3, 2, 0)).toBe(0)
				-- cumul du GDD §4.26 au premier passage (sans la piste ni les places offertes)
				local cumul, total = {}, 0
				for k = 1, 30 do
					total += Prestige.confettiGain("splorch", k, k - 1, 0)
					cumul[k] = total
				end
				expect({
					cumul[1],
					cumul[2],
					cumul[5],
					cumul[8],
					cumul[10],
					cumul[12],
					cumul[15],
					cumul[20],
					cumul[25],
					cumul[30],
				}).toEqual({
					4,
					9,
					30,
					60,
					85,
					114,
					165,
					270,
					435,
					600,
				})
				-- même somme que le rattrapage de la migration v1 → v2 (constantes figées du contrat)
				total = 0
				for R = 1, MAX_R do
					total += Prestige.confettiGain("splorch", R, R - 1, 0)
					if R % 7 == 0 or R <= 25 or R == MAX_R then
						expect({ R = R, same = total == Schema.confettiCatchUp(R) }).toEqual({
							R = R,
							same = true,
						})
					end
				end
			end
		)

		it(
			"déblocages nommés : table du §4.29 de 1 à 20, puis prime, Monuments 9 et 10, titres ; jamais vide de 1 à 400",
			function()
				expect(Prestige.unlocksFor(0)).toEqual({})
				expect(Prestige.unlocksFor(1)).toEqual({
					"unlock.workshop",
					"unlock.gloves",
					"panel.splorch.unlock.family.axolo",
					"unlock.splorchGift",
					"unlock.skin",
				})
				expect(Prestige.unlocksFor(15)).toEqual({
					"panel.splorch.unlock.title.splorch_hero",
					"unlock.jellyAscend",
					"unlock.skin",
				})
				expect(Prestige.unlocksFor(21)).toEqual({ "unlock.recordBonus" })
				expect(Prestige.unlockTiles(22)).toEqual({
					{ key = "unlock.recordBonus", vars = { n = 10 } },
					{ key = "unlock.monument", vars = { n = 9 } },
				})
				expect(Prestige.unlockTiles(24)[2]).toEqual({ key = "unlock.monument", vars = { n = 10 } })
				expect(Prestige.unlocksFor(23)).toEqual({ "unlock.recordBonus" })
				local t25 = Prestige.unlockTiles(25)
				expect(#t25).toBe(3)
				expect(t25[1].key).toBe("unlock.recordBonus")
				expect(Prestige.unlockTiles(50)[2]).toEqual({
					key = "unlock.item",
					vars = { name = "title.r50" },
				})
				for R = 1, MAX_R do
					expect({ R = R, n = #Prestige.unlocksFor(R) > 0 }).toEqual({ R = R, n = true })
				end
				-- copie : modifier le résultat ne touche jamais la table du contrat
				local tiles = Prestige.unlockTiles(1)
				tiles[5].vars.name = "x"
				expect(Prestige.unlockTiles(1)[5].vars.name).toBe("skin.marshmallow")
				expect(Prestige.unlocksFor(0 / 0)).toEqual({})
			end
		)

		it(
			"décorations gardées : 3 au Record R 8, 6 au 14, + 3 par niveau de « Déco qui reste », 12 au plus",
			function()
				expect(Prestige.keptDecor(0, nil)).toBe(0)
				expect(Prestige.keptDecor(7, {})).toBe(0)
				expect(Prestige.keptDecor(8, {})).toBe(3)
				expect(Prestige.keptDecor(13, Schema.defaultsFor(2).atelier)).toBe(3)
				expect(Prestige.keptDecor(14, nil)).toBe(6)
				local atelier = Schema.defaultsFor(2).atelier
				atelier[W.keptDecor] = 1
				expect(Prestige.keptDecor(1, atelier)).toBe(3)
				expect(Prestige.keptDecor(14, atelier)).toBe(9)
				atelier[W.keptDecor] = 2
				expect(Prestige.keptDecor(14, atelier)).toBe(12)
				expect(Prestige.keptDecor(MAX_R, atelier)).toBe(12)
				atelier[W.keptDecor] = 99 -- abîmé : borné aux 2 niveaux de la ligne
				expect(Prestige.keptDecor(8, atelier)).toBe(9)
				expect(Prestige.keptDecor(14, 2)).toBe(12) -- le niveau seul est accepté
				expect(Prestige.keptDecor(0 / 0, 0 / 0)).toBe(0)
			end
		)
	end)

	describe("Prestige › invariant de stabilité (validateConfig)", function()
		it(
			"la configuration livrée passe ; ReqStep 3, objectifs × 2,3 ou une table abîmée sont refusés sans erreur",
			function()
				expect({ Prestige.validateConfig(Balance) }).toEqual({ true })
				local function with(mutate)
					local b = Tables.deepCopy(Balance)
					mutate(b)
					return (Prestige.validateConfig(b))
				end
				expect(with(function(b)
					b.Ascend.ReqStep = 3
				end)).toBe(false)
				expect(with(function(b)
					b.Splorch.BeyondMult = 2.3
				end)).toBe(false)
				expect(with(function(b)
					b.Ascend.GrowthMult = 4
				end)).toBe(false)
				-- ancien levier H10 de docs/09 : objectifs × 2,3 dès R16
				expect(with(function(b)
					for i = 18, 20 do
						b.Splorch.Targets[i] = b.Splorch.Targets[i - 1] * 2.3
					end
				end)).toBe(false)
				expect(with(function(b)
					b.Ascend.RegainTaper = { 2, 2.5, 1.25 }
				end)).toBe(false)
				expect(with(function(b)
					b.Ascend.ReqR = { 20, 15 }
				end)).toBe(false)
				expect(with(function(b)
					b.Prestige.MaxR = 0 / 0
				end)).toBe(false)
				expect(with(function(b)
					b.Ascend.PriceByA = { 0.5, -1 }
				end)).toBe(false)
				for _, bad in { nil, 3, "x", {}, { Prestige = {}, Ascend = {}, Splorch = {} } } do
					local ok, why = Prestige.validateConfig(bad)
					expect(ok).toBe(false)
					expect(type(why)).toBe("string")
				end
				-- une configuration plus généreuse mais stable reste acceptée
				expect(with(function(b)
					b.Ascend.ReqStep = 5
				end)).toBe(true)
			end
		)
	end)

	describe("Prestige › apply (un bloc, idempotent)", function()
		it("profil vide, profil illisible, sorte inconnue, now illisible : rien ne change", function()
			local d = Schema.defaultsFor(2)
			local before = Tables.deepCopy(d)
			for _, kind in { "splorch", "petit", "ascend", "nope", nil } do
				local changed, report = Prestige.apply(d, kind, 100)
				expect(next(changed)).toBeNil()
				expect(report.applied).toBe(false)
			end
			expect(Tables.deepEqual(d, before)).toBe(true)
			local r = ready(profile({ R = 3, bestR = 3 }))
			local copy = Tables.deepCopy(r)
			for _, now in { 0 / 0, math.huge, nil, "5" } do
				local changed = Prestige.apply(r, "splorch", now)
				expect(next(changed)).toBeNil()
			end
			expect(Tables.deepEqual(r, copy)).toBe(true)
			for _, bad in { nil, 3, "x" } do
				local changed, report = Prestige.apply(bad, "splorch", 10)
				expect(next(changed)).toBeNil()
				expect(report.applied).toBe(false)
			end
		end)

		it(
			"sauvegarde-témoin v2.json : Grand Splorch 12 → 13, gardé, repart de zéro, toutes les tailles à 1",
			function()
				local d = readV2()
				Tables.reconcile(d, Schema.defaultsFor(2))
				-- à l'instant de la sauvegarde, le plus gros (5,5e8) n'a pas l'objectif de r = 12 (1,4e9)
				expect(Prestige.splorchReady(d, d.growth.t)).toBe(false)
				local before = Tables.deepCopy(d)
				local changed = Prestige.apply(d, "splorch", d.growth.t)
				expect(next(changed)).toBeNil()
				expect(Tables.deepEqual(d, before)).toBe(true)
				-- 2 jours plus tard (croissance 8 192 /s), il l'a
				local now = d.growth.t + 2 * 86400
				expect(Prestige.splorchReady(d, now)).toBe(true)
				local changed2, report = Prestige.apply(d, "splorch", now)
				expect(report.applied).toBe(true)
				expect(report.kind).toBe("splorch")
				expect(report.record).toBe(true)
				expect({ d.R, d.bestR, d.ascend }).toEqual({ 13, 13, 0 })
				expect({ report.fromR, report.toR, report.bestR }).toEqual({ 12, 13, 13 })
				expect(report.lost).toBe(before.coins + before.pot)
				expect({ d.coins, d.pot }).toEqual({ 0, 0 })
				-- dalles : Tapis et Étoilé, Gants, École à 0 ; 3 décorations gardées (Record R 12 ≥ 8) ;
				-- Enclos, Lit douillet, Monuments, dalles découvertes gardés
				expect(d.tiles).toEqual({
					snack = 0,
					decor = 3,
					pens = before.tiles.pens,
					cozyBed = true,
					seen = before.tiles.seen,
					star = 0,
					gloves = 0,
					school = 0,
					monuments = before.tiles.monuments,
				})
				expect({ report.keptDecor, report.decorBefore }).toEqual({ 3, 9 })
				-- Confettis rendus (versés par addConfetti) : 3 + 13 ; Fame du Grand Splorch avant plafond
				expect({ report.confetti, report.confettiBase, report.fame }).toEqual({ 16, 16, 5 })
				expect(d.confetti).toBe(before.confetti)
				expect(report.unlocks).toEqual(Prestige.unlocksFor(13))
				expect({ report.snackStart, report.giftLevels }).toEqual({ 0, 1 })
				-- toutes les tailles à 1 : enclos, Bassin, Dodo, Lettres ; aucun squishy perdu ni changé
				local n = 0
				for uid, rec in d.squishies do
					n += 1
					local old = before.squishies[uid]
					expect({ uid = uid, z = rec.z, zg = rec.zg }).toEqual({ uid = uid, z = 1, zg = 0 })
					for _, key in { "s", "m", "st", "bf", "lk", "o", "at", "b", "gd" } do
						expect({ uid = uid, key = key, same = rec[key] == old[key] }).toEqual({
							uid = uid,
							key = key,
							same = true,
						})
					end
				end
				local m = 0
				for _ in before.squishies do
					m += 1
				end
				expect(n).toBe(m)
				expect(d.growth).toEqual({ G = 0, g = before.growth.g, t = now })
				-- jamais touchés : Atelier, Confettis, Squishydex, Fame, statistiques, réglages
				for _, key in
					{
						"atelier",
						"atelierCosmetics",
						"confetti",
						"confettiTotal",
						"dex",
						"fame",
						"stats",
						"settings",
						"trophies",
						"biggestEver",
					}
				do
					expect({ key = key, same = Tables.deepEqual(d[key], before[key]) }).toEqual({
						key = key,
						same = true,
					})
				end
				-- clés à marquer pour la sauvegarde
				expect(changed2).toEqual({
					coins = true,
					pot = true,
					tiles = true,
					R = true,
					growth = true,
					squishies = true,
					bestR = true,
				})
				-- deuxième appel au même instant : rien (tailles à 1, condition fausse)
				local after = Tables.deepCopy(d)
				local again, report2 = Prestige.apply(d, "splorch", now)
				expect(next(again)).toBeNil()
				expect(report2.applied).toBe(false)
				expect(Tables.deepEqual(d, after)).toBe(true)
			end
		)

		it(
			"places offertes (Record R 2, 6, 11, 16) : +1 niveau d'Enclos, ou +25 Confettis sur un enclos plein",
			function()
				local d = ready(profile({ R = 1, bestR = 1, tiles = { pens = 3 } }))
				local _, report = Prestige.apply(d, "splorch", 10)
				expect({ d.tiles.pens, report.offeredPen, report.fullPen, report.confetti }).toEqual({
					4,
					true,
					false,
					5,
				})
				local full = ready(profile({ R = 5, bestR = 5, tiles = { pens = 14 } }))
				local _, r2 = Prestige.apply(full, "splorch", 10)
				expect({ full.tiles.pens, r2.offeredPen, r2.fullPen, r2.confetti }).toEqual({
					14,
					false,
					true,
					9 + 25,
				})
				-- pas de place offerte au Record R 3, ni au retour à un record déjà passé
				local d3 = ready(profile({ R = 2, bestR = 2, tiles = { pens = 3 } }))
				Prestige.apply(d3, "splorch", 10)
				expect(d3.tiles.pens).toBe(3)
				local back = ready(profile({ R = 5, bestR = 15, ascend = 1, tiles = { pens = 3 } }))
				local _, r4 = Prestige.apply(back, "petit", 10)
				expect({ back.tiles.pens, r4.offeredPen, r4.kind }).toEqual({ 3, false, "petit" })
			end
		)

		it(
			"prime de record au-delà de 20 ; première boucle (r = 0) ; MaxR : plus de Grand Splorch (« Record absolu ! »)",
			function()
				local d = ready(profile({ R = 0, bestR = 0 }))
				local _, report = Prestige.apply(d, "splorch", 5)
				expect({ d.R, d.bestR, report.confetti, report.record }).toEqual({ 1, 1, 4, true })
				local r21 = ready(profile({ R = 20, bestR = 20 }))
				local _, report21 = Prestige.apply(r21, "splorch", 5)
				expect(report21.confetti).toBe(3 + 20 + 10)
				local top = profile({ R = MAX_R, bestR = MAX_R })
				top.squishies["1"].z = Balance.Numbers.Max
				local changed = Prestige.apply(top, "splorch", 5)
				expect(next(changed)).toBeNil()
				expect(top.R).toBe(MAX_R)
				local last = ready(profile({ R = MAX_R - 1, bestR = MAX_R - 1 }))
				local _, rl = Prestige.apply(last, "splorch", 5)
				expect({ last.R, last.bestR, rl.applied }).toEqual({ MAX_R, MAX_R, true })
			end
		)

		it("Petit Splorch, retour au record (+10 une fois par Ascension), puis boucle record", function()
			local d = ready(profile({ R = 13, bestR = 15, ascend = 1, regainBonusA = 0 }))
			local _, r1 = Prestige.apply(d, "splorch", 10)
			expect({ r1.kind, r1.record, r1.regain, r1.confetti, r1.fame, d.R, d.bestR }).toEqual({
				"petit",
				false,
				false,
				1,
				0,
				14,
				15,
			})
			ready(d)
			local changed, r2 = Prestige.apply(d, "petit", 20)
			expect({ r2.kind, r2.regain, r2.confetti, d.R, d.regainBonusA }).toEqual({
				"petit",
				true,
				11,
				15,
				1,
			})
			expect(changed.regainBonusA).toBe(true)
			expect(changed.bestR).toBeNil()
			-- avec le champ memoryR (note INT-A1-MEMORY) : la 1re boucle record est reconnue
			local m = ready(profile({ R = 14, bestR = 15, ascend = 1, regainBonusA = 0, memoryR = 0 }))
			Prestige.apply(m, "petit", 20)
			expect({ m.memoryR, Prestige.firstRecordLoop(m) }).toEqual({ 15, true })
			ready(m)
			Prestige.apply(m, "splorch", 30)
			expect({ m.R, m.bestR, Prestige.firstRecordLoop(m) }).toEqual({ 16, 16, false })
			-- bonus déjà donné pour ce A (sauvegarde rejouée) : jamais deux fois
			local again = ready(profile({ R = 14, bestR = 15, ascend = 1, regainBonusA = 1 }))
			local _, r3 = Prestige.apply(again, "petit", 10)
			expect({ r3.regain, r3.confetti }).toEqual({ false, 1 })
			-- sans Ascension, aucun retour au record n'existe
			local none = ready(profile({ R = 14, bestR = 15, ascend = 0, regainBonusA = 0 }))
			local _, r4 = Prestige.apply(none, "petit", 10)
			expect(r4.regain).toBe(false)
		end)

		it("Tapis de départ et cadeau du Splorch : 6 niveaux offerts au plus", function()
			local d = ready(profile({
				R = 4,
				bestR = 4,
				tiles = { snack = 12 },
				atelierLevels = { startMat = 3, gift = 2 },
			}))
			local _, report = Prestige.apply(d, "splorch", 10)
			expect({ d.tiles.snack, report.snackStart, report.giftLevels }).toEqual({ 3, 3, 3 })
			local one = ready(profile({
				R = 4,
				bestR = 4,
				tiles = { snack = 12 },
				atelierLevels = { startMat = 1, gift = 0 },
			}))
			local _, r1 = Prestige.apply(one, "splorch", 10)
			expect({ one.tiles.snack, r1.giftLevels }).toEqual({ 1, 1 })
			local bad = ready(profile({ R = 4, bestR = 4, atelierLevels = { startMat = 50, gift = -3 } }))
			local _, r2 = Prestige.apply(bad, "splorch", 10)
			expect({ bad.tiles.snack, r2.giftLevels }).toEqual({ 3, 1 })
		end)

		it(
			"Jelly Ascend : A + 1, r au départ, Record R gardé, +20 Confettis (+1 par Grand Splorch sauté grâce au Tremplin)",
			function()
				local d = profile({
					R = 15,
					bestR = 15,
					coins = 5e9,
					pot = 1e6,
					tiles = {
						snack = 12,
						star = 3,
						decor = 18,
						gloves = 20,
						school = 4,
						pens = 14,
						monuments = 4,
					},
				})
				d.squishies["1"].z = 7e9
				local changed, report = Prestige.apply(d, "ascend", 40)
				expect(report.applied).toBe(true)
				expect({ d.ascend, d.R, d.bestR, report.confetti, report.fame, report.skipped }).toEqual({
					1,
					0,
					15,
					20,
					20,
					0,
				})
				expect({ d.coins, d.pot, d.tiles.snack, d.tiles.star, d.tiles.gloves, d.tiles.school }).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect({ d.tiles.decor, d.tiles.pens, d.tiles.monuments }).toEqual({ 6, 14, 4 }) -- 6 gardées (Record R 15)
				expect(d.squishies["1"].z).toBe(1)
				expect(changed.ascend).toBe(true)
				expect(report.lost).toBe(5e9 + 1e6)
				-- deuxième appel : la condition (r ≥ 20 pour A = 1) est fausse
				local again = Prestige.apply(d, "ascend", 40)
				expect(next(again)).toBeNil()
				-- Tremplin 2 à la 2e Ascension : départ 4 + 2, 2 Confettis de plus
				local s = profile({ R = 20, bestR = 22, ascend = 1, atelierLevels = { springboard = 2 } })
				local _, rs = Prestige.apply(s, "ascend", 40)
				expect({ s.ascend, s.R, s.bestR, rs.skipped, rs.confetti }).toEqual({ 2, 6, 22, 2, 22 })
				-- Tremplin 3 à la 4e (condition 28) : min(32 − 10, 13 + 3) = 16
				local s4 = profile({ R = 28, bestR = 28, ascend = 3, atelierLevels = { springboard = 3 } })
				local _, r4 = Prestige.apply(s4, "ascend", 40)
				expect({ s4.R, r4.skipped, r4.confetti }).toEqual({ 16, 3, 23 })
				-- Ascension pas prête (r = 14) : rien
				local early = profile({ R = 14, bestR = 14 })
				local copy = Tables.deepCopy(early)
				expect(next((Prestige.apply(early, "ascend", 40)))).toBeNil()
				expect(Tables.deepEqual(early, copy)).toBe(true)
			end
		)

		it(
			"MaxA : la 60e Ascension se fait (départ 246, Tremplin sans effet au plafond), la 61e jamais",
			function()
				local d = profile({
					R = Prestige.reqR(MAX_A),
					bestR = 300,
					ascend = MAX_A - 1,
					atelierLevels = { springboard = 3 },
				})
				local _, report = Prestige.apply(d, "ascend", 40)
				expect({ d.ascend, d.R, report.skipped, report.confetti }).toEqual({ MAX_A, 246, 0, 20 })
				d.R = MAX_R
				d.bestR = MAX_R
				expect(next((Prestige.apply(d, "ascend", 41)))).toBeNil()
				expect(d.ascend).toBe(MAX_A)
			end
		)

		it("profil v1 (sans bestR) et bestR < r abîmé : le Record R n'est jamais perdu", function()
			local v1 = Schema.defaultsV1()
			v1.R = 15
			v1.squishies = {
				a = {
					s = 1,
					m = 0,
					st = 0,
					z = 1,
					zg = 0,
					bf = 0,
					lk = false,
					o = "",
					at = "pen",
					b = 0,
					gd = 0,
				},
			}
			local changed, report = Prestige.apply(v1, "ascend", 40)
			expect(report.applied).toBe(true)
			expect({ v1.R, v1.bestR, v1.ascend }).toEqual({ 0, 15, 1 })
			expect(changed.bestR).toBe(true)
			local bad = ready(profile({ R = 10, bestR = 4 }))
			local _, r2 = Prestige.apply(bad, "splorch", 10)
			expect({ bad.R, bad.bestR, r2.record }).toEqual({ 11, 11, true })
		end)

		it(
			"tailles : Dodo, Lettres et squishy porté repartent aussi à 1 ; un squishy abîmé ne bloque rien",
			function()
				local d = ready(profile({ R = 2, bestR = 2 }))
				d.squishies.dodo = {
					s = 2,
					m = 0,
					st = 0,
					z = 5e6,
					zg = 0,
					bf = 0,
					lk = false,
					o = "",
					at = "dodo",
					b = 0,
					gd = 0,
				}
				d.squishies.mail = {
					s = 3,
					m = 0,
					st = 0,
					z = 77,
					zg = 0,
					bf = 0,
					lk = false,
					o = "",
					at = "mail",
					b = 0,
					gd = 0,
				}
				d.squishies.pool = {
					s = 4,
					m = 0,
					st = 0,
					z = 9,
					zg = 3,
					bf = 0,
					lk = false,
					o = "",
					at = "pool",
					b = 0,
					gd = 0,
				}
				d.squishies.broken = "abîmé"
				local _, report = Prestige.apply(d, "splorch", 10)
				expect(report.applied).toBe(true)
				for _, uid in { "1", "dodo", "mail", "pool" } do
					expect({ uid = uid, z = d.squishies[uid].z, zg = d.squishies[uid].zg }).toEqual({
						uid = uid,
						z = 1,
						zg = 0,
					})
				end
				expect(d.squishies.broken).toBe("abîmé")
				-- la plus grosse taille compte TOUS les squishies (jamais plus strict que SplorchService)
				local frozen = profile({ R = 0, bestR = 0 })
				frozen.squishies["1"].at = "dodo"
				frozen.squishies["1"].z = 15000
				expect(Prestige.splorchReady(frozen, 0)).toBe(true)
			end
		)
	end)
end
