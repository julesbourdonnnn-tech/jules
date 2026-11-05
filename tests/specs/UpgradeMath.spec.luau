--!nocheck
-- UpgradeMath (paquet A1, docs/04 §27.7, GDD v2.0 §4.6, §4.26, §10.7.7, §10.8 règle 5) : le seul
-- calcul des prix. Cas exacts du GDD §4.6 (chaque niveau de chaque table, sommes, témoins du contrat
-- Contract_upgrades), Monuments, prix fixes, Confettis de l'Atelier, plafonds (ouverture, boucle,
-- interrupteurs coupés et ouverts), niveaux du profil, effets « avant → après » du §10.7.7,
-- instantané versionné, cadeau du Splorch, achat d'un message (plan) et entrées hostiles.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Bitset = h:require("ReplicatedStorage.Shared.Logic.Bitset")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local W = Upgrades.WorkshopIndex

	-- stylua: ignore start
	-- Prix exacts à r = 0 et A = 0 (le premier achat coûte la base) ; GDD §4.6.1 les écrit tronqués
	local EXACT = {
		snack = { 20, 90, 405, 1822, 8201, 36905, 166075, 747338, 3363025, 15133612, 68101257, 306455660 },
		star = { 383069575, 478836969, 598546211, 748182764, 935228455, 1169035569, 1461294461, 1826618076 },
		decor = { 80, 176, 387, 851, 1874, 4122, 9070, 19954, 43900, 96581, 212479, 467454, 1028400, 2262480, 4977457, 10950405, 24090891, 52999962 },
		pens = { 1200, 2640, 5808, 12777, 28110, 61843, 136055, 299322, 658510, 1448723, 3187190, 7011819, 15426003, 33937206 },
		school = { 20000, 35000, 61250, 107187, 187578, 328261, 574458, 1005301, 1759277, 3078735, 5387787, 9428628, 16500100, 28875175, 50531556, 88430224, 154752892, 270817561, 473930732, 829378782 },
		gloves = { 2000, 3100, 4805, 7447, 11544, 17893, 27734, 42988, 66632, 103279, 160083, 248129, 384600, 596131, 924003, 1432205, 2219919, 3440874, 5333355, 8266701, 12813387, 19860750, 30784163, 47715453, 73958952, 114636376, 177686383, 275413894, 426891536, 661681881, 1025606915, 1589690719, 2464020615, 3819231954, 5919809529, 9175704770, 14222342393, 22044630710, 34169177601, 52962225282 },
	}
	-- Tables du GDD §4.6.1 telles qu'écrites (3 chiffres significatifs, tronqués comme à l'écran)
	local GDD = {
		snack = { 20, 90, 405, 1822, 8201, 36.9e3, 166e3, 747e3, 3.36e6, 15.1e6, 68.1e6, 306e6 },
		star = { 383e6, 478e6, 598e6, 748e6, 935e6, 1.16e9, 1.46e9, 1.82e9 },
		decor = { 80, 176, 387, 851, 1874, 4122, 9070, 19.9e3, 43.9e3, 96.5e3, 212e3, 467e3, 1.02e6, 2.26e6, 4.97e6, 10.9e6, 24.0e6, 52.9e6 },
		pens = { 1200, 2640, 5808, 12.7e3, 28.1e3, 61.8e3, 136e3, 299e3, 658e3, 1.44e6, 3.18e6, 7.01e6, 15.4e6, 33.9e6 },
		school = { 20.0e3, 35.0e3, 61.2e3, 107e3, 187e3, 328e3, 574e3, 1.00e6, 1.75e6, 3.07e6, 5.38e6, 9.42e6, 16.5e6, 28.8e6, 50.5e6, 88.4e6, 154e6, 270e6, 473e6, 829e6 },
	}
	-- Gants : niveaux écrits par le GDD
	local GDD_GLOVES = { [1] = 2000, [5] = 11.5e3, [10] = 103e3, [15] = 924e3, [20] = 8.26e6, [25] = 73.9e6, [30] = 661e6, [31] = 1.02e9, [32] = 1.58e9, [33] = 2.46e9, [34] = 3.81e9, [35] = 5.91e9, [36] = 9.17e9, [37] = 14.2e9, [38] = 22.0e9, [39] = 34.1e9, [40] = 52.9e9 }
	-- Monuments « avant toute Ascension » (GDD §4.6, arrondis à 3 chiffres)
	local GDD_MONUMENTS = { 1.69e12, 20.7e12, 254e12, 3.11e15, 38.1e15, 466e15, 5.71e18, 70.0e18, 857e18, 10.5e21 }
	-- stylua: ignore end

	-- 3 chiffres significatifs : tronqué (écran) ou arrondi ; sous 10 000, l'entier (GDD §4.2)
	local function sig3(x, round)
		if x < 10000 then
			return x
		end
		local e = 1
		while x / e >= 1000 do
			e *= 10
		end
		local m = x / e
		return (if round then math.floor(m + 0.5) else math.floor(m)) * e
	end

	local function allOn()
		local f = {}
		for k, v in Features.Defaults do
			f[k] = if type(v) == "boolean" then true else v
		end
		return f
	end

	local function profile(fields)
		local d = Schema.defaultsFor(2)
		for k, v in fields or {} do
			if k == "tiles" then
				for tk, tv in v do
					d.tiles[tk] = tv
				end
			elseif k == "atelierLevels" then
				for id, lvl in v do
					d.atelier[W[id]] = lvl
				end
			else
				d[k] = v
			end
		end
		return d
	end

	describe("UpgradeMath › prix (GDD §4.6, multiplications successives)", function()
		it(
			"chaque niveau de chaque famille à r = 0, A = 0 : valeurs exactes, et le GDD les écrit tronquées",
			function()
				for id, list in EXACT do
					for L = 0, #list - 1 do
						local p = UpgradeMath.price(id, L, 0, 0, 0)
						expect({ id = id, L = L, p = p }).toEqual({ id = id, L = L, p = list[L + 1] })
						if GDD[id] then
							expect({ id = id, L = L, gdd = sig3(p, false) }).toEqual({
								id = id,
								L = L,
								gdd = GDD[id][L + 1],
							})
						end
					end
					-- niveau au maximum : n'existe pas
					expect(UpgradeMath.price(id, #list, 0, 0, 0)).toBe(math.huge)
				end
				for n, v in GDD_GLOVES do
					expect({ n = n, gdd = sig3(UpgradeMath.price("gloves", n - 1, 0, 0, 0), false) }).toEqual({
						n = n,
						gdd = v,
					})
				end
				expect(UpgradeMath.price("cozyBed", 0, 0, 0, 0)).toBe(25e6)
				expect(UpgradeMath.price("cozyBed", 1, 0, 0, 0)).toBe(math.huge)
			end
		)

		it(
			"témoins du contrat et cas exacts du §4.6 : Étoilé 13 à r = 10 (A = 0 et 1), Gants à r = 1, T12",
			function()
				expect(UpgradeMath.price("snack", 11, 0, 0, 0)).toBe(306455660) -- T12
				expect(UpgradeMath.price("star", 0, 10, 0, 10)).toBe(105671556317044)
				expect(UpgradeMath.price("star", 0, 10, 1, 10)).toBe(52835778158522)
				expect(UpgradeMath.price("gloves", 0, 1, 0, 1)).toBe(7000) -- « à peu près le Tapis niveau 4 »
				expect(UpgradeMath.price("gloves", 29, 0, 0, 0)).toBe(661681881)
				expect(UpgradeMath.price("gloves", 39, 0, 0, 0)).toBe(52962225282)
				expect(UpgradeMath.price("school", 19, 0, 0, 0)).toBe(829378782)
				-- r et A ne touchent que les familles de la boucle
				expect(UpgradeMath.price("snack", 0, 3, 0, 3)).toBe(math.floor(20 * 3.5 * 3.5 * 3.5))
				expect(UpgradeMath.price("snack", 4, 0, 2, 15)).toBe(math.floor(8201.25 * 0.25))
				for _, id in { "pens", "cozyBed" } do
					expect(UpgradeMath.price(id, 0, 17, 9, 30)).toBe(UpgradeMath.price(id, 0, 0, 0, 0))
				end
				-- même valeur que Formulas.tileCost (jeu de base) pour les 4 dalles, r = 0 … 20, A = 0
				for _, id in { "snack", "decor", "pens", "cozyBed" } do
					for r = 0, 20 do
						for L = 0, UpgradeMath.maxLevel(id) - 1 do
							local a, b = UpgradeMath.price(id, L, r, 0, r), Formulas.tileCost(id, L, r)
							expect({
								id = id,
								r = r,
								L = L,
								close = math.abs(a - b) <= math.max(1, b * 1e-12),
							}).toEqual({
								id = id,
								r = r,
								L = L,
								close = true,
							})
						end
					end
				end
			end
		)

		it(
			"sommes du GDD : Tapis 394 M, Étoilé 7,60 B (24,8 T12), Gants 1,86 B puis 149 B, École 1,93 B, Décos 97,1 M, Enclos 62,2 M",
			function()
				local function sum(id, n)
					local count, total = UpgradeMath.bulk(id, 0, n, 0, 0, 0)
					expect(count).toBe(n)
					return total
				end
				expect(sig3(sum("snack", 12), false)).toBe(394e6)
				local star = sum("star", 8)
				expect(star).toBe(7600812080)
				expect(math.floor(star / 306455660 * 10) / 10).toBe(24.8)
				expect(sig3(sum("gloves", 30), false)).toBe(1.86e9)
				expect(sig3(sum("gloves", 40), false)).toBe(149e9)
				expect(sig3(sum("school", 20), false)).toBe(1.93e9)
				expect(sig3(sum("decor", 18), false)).toBe(97.1e6)
				expect(sig3(sum("pens", 14), false)).toBe(62.2e6)
			end
		)

		it(
			"Monuments : 3 × T12 × 3,5^(ouverture), sans F(A) ; après une Ascension × 3,5^(r − Record R)",
			function()
				for n, v in GDD_MONUMENTS do
					expect({ n = n, gdd = sig3(UpgradeMath.price("monument", n - 1, 30, 0, 30), true) }).toEqual({
						n = n,
						gdd = v,
					})
				end
				-- avant toute Ascension (r = Record R), le prix ne dépend pas de r ; jamais de F(A)
				local m1 = UpgradeMath.price("monument", 0, 6, 0, 6)
				expect(m1).toBe(1690040717440)
				expect(UpgradeMath.price("monument", 0, 20, 0, 20)).toBe(m1)
				expect(UpgradeMath.price("monument", 0, 6, 5, 6)).toBe(m1)
				-- remontée : r = 5 pour un Record R 15 → ÷ 3,5^10, le puits des pièces en trop
				local low = UpgradeMath.price("monument", 0, 5, 1, 15)
				local expected = 1690040717440.0
				for _ = 1, 10 do
					expected /= 3.5
				end
				expect(low).toBe(math.floor(expected))
				-- r > Record R (abîmé) : comme r = Record R
				expect(UpgradeMath.price("monument", 0, 9, 0, 3)).toBe(m1)
			end
		)

		it(
			'Atelier et « Pour le plaisir » : coûts en Confettis listés ; ids nus et "fun.<id>"',
			function()
				expect(UpgradeMath.price("gift", 0, 99, 9, 99)).toBe(3)
				expect(UpgradeMath.price("gift", 1, 0, 0, 0)).toBe(25)
				expect(UpgradeMath.price("gift", 2, 0, 0, 0)).toBe(math.huge)
				expect(UpgradeMath.price("springboard", 2, 0, 0, 0)).toBe(150)
				expect(UpgradeMath.price("decoShop", 23, 0, 0, 0)).toBe(200)
				expect(UpgradeMath.price("fun.palettes", 5, 0, 0, 0)).toBe(20)
				expect(UpgradeMath.price("palettes", 5, 0, 0, 0)).toBe(20)
				expect(UpgradeMath.price("fun.title", 0, 0, 0, 0)).toBe(100)
				expect(UpgradeMath.canonical("title")).toBe("fun.title")
				expect(UpgradeMath.canonical("snack")).toBe("snack")
				expect(UpgradeMath.canonical("nope")).toBeNil()
				expect(UpgradeMath.currency("gloves")).toBe("coins")
				expect(UpgradeMath.currency("plume")).toBe("confetti")
				expect(UpgradeMath.currency("fun.emote")).toBe("confetti")
				expect(UpgradeMath.maxLevel("decoShop")).toBe(24)
				expect(UpgradeMath.maxLevel("star")).toBe(8)
				-- 8 familles, 10 lignes d'Atelier, 6 lignes « bits » de « Pour le plaisir », dans l'ordre fixe
				local ids = UpgradeMath.ids()
				expect(#ids).toBe(8 + 10 + 6)
				expect({ ids[1], ids[8], ids[9], ids[18], ids[19], ids[24] }).toEqual({
					"snack",
					"school",
					"gift",
					"decoShop",
					"fun.palettes",
					"fun.title",
				})
				table.remove(ids, 1)
				expect(UpgradeMath.ids()[1]).toBe("snack") -- copie
			end
		)

		it(
			"prix au moins 1 (C13) et entrées hostiles : niveau ou id illisible = math.huge, r et A bornés",
			function()
				expect(UpgradeMath.price("snack", 0, 0, MAX_A, 400)).toBe(1)
				expect(UpgradeMath.price("snack", 0, 0, 1e9, 0)).toBe(
					UpgradeMath.price("snack", 0, 0, MAX_A, 0)
				)
				expect(UpgradeMath.price("snack", 0, 1e9, 0, 1e9)).toBe(
					UpgradeMath.price("snack", 0, MAX_R, 0, MAX_R)
				)
				for _, bad in { -1, 0.5, 0 / 0, math.huge, -math.huge, "1", nil, true } do
					expect(UpgradeMath.price("snack", bad, 0, 0, 0)).toBe(math.huge)
					expect({ UpgradeMath.bulk("snack", bad, 3, 0, 0, 0) }).toEqual({ 0, 0 })
					expect({ UpgradeMath.maxAffordable("snack", bad, 1e9, 0, 0, 0) }).toEqual({ 0, 0 })
				end
				for _, bad in { "nope", nil, 3, "" } do
					expect(UpgradeMath.price(bad, 0, 0, 0, 0)).toBe(math.huge)
					expect(UpgradeMath.maxLevel(bad)).toBe(0)
					expect(UpgradeMath.currency(bad)).toBeNil()
				end
				expect(UpgradeMath.price("snack", 0, 0 / 0, 0 / 0, 0 / 0)).toBe(20)
			end
		)
	end)

	describe("UpgradeMath › achats groupés", function()
		it(
			"bulk : somme niveau par niveau, bornée aux niveaux qui existent ; maxAffordable ; plan = règle du serveur",
			function()
				expect({ UpgradeMath.bulk("snack", 0, 3, 0, 0, 0) }).toEqual({ 3, 20 + 90 + 405 })
				expect({ UpgradeMath.bulk("snack", 10, 40, 0, 0, 0) }).toEqual({ 2, 68101257 + 306455660 })
				expect({ UpgradeMath.bulk("snack", 12, 1, 0, 0, 0) }).toEqual({ 0, 0 })
				expect({ UpgradeMath.bulk("snack", 0, 0, 0, 0, 0) }).toEqual({ 0, 0 })
				expect({ UpgradeMath.bulk("snack", 0, -4, 0, 0, 0) }).toEqual({ 0, 0 })
				-- tout juste : 515 paie 3 niveaux, 514 seulement 2
				expect({ UpgradeMath.maxAffordable("snack", 0, 515, 0, 0, 0) }).toEqual({ 3, 515 })
				expect({ UpgradeMath.maxAffordable("snack", 0, 514, 0, 0, 0) }).toEqual({ 2, 110 })
				expect({ UpgradeMath.maxAffordable("snack", 0, 0 / 0, 0, 0, 0) }).toEqual({ 0, 0 })
				expect({ UpgradeMath.maxAffordable("snack", 0, math.huge, 0, 0, 0) }).toEqual({
					UpgradeMath.bulk("snack", 0, 12, 0, 0, 0),
				})
				-- plan : ×1, ×10, Max (0), plafond, BulkMax ; mode hors liste = rien
				expect({ UpgradeMath.plan("snack", 0, 1, 1e12, 12, 0, 0, 0) }).toEqual({ 1, 20 })
				expect({ UpgradeMath.plan("snack", 0, 10, 1e12, 12, 0, 0, 0) }).toEqual({
					UpgradeMath.bulk("snack", 0, 10, 0, 0, 0),
				})
				expect({ UpgradeMath.plan("snack", 0, 0, 1e12, 12, 0, 0, 0) }).toEqual({
					UpgradeMath.bulk("snack", 0, 12, 0, 0, 0),
				})
				expect({ UpgradeMath.plan("snack", 0, 0, 515, 12, 0, 0, 0) }).toEqual({ 3, 515 })
				expect({ UpgradeMath.plan("star", 0, 0, 1e30, 3, 8, 0, 8) }).toEqual({
					UpgradeMath.bulk("star", 0, 3, 8, 0, 8),
				})
				expect({ UpgradeMath.plan("gloves", 0, 0, 1e300, 40, 0, 0, 0) }).toEqual({
					UpgradeMath.bulk("gloves", 0, Balance.Upgrades.BulkMax, 0, 0, 0),
				})
				for _, bad in { -1, 0.5, 41, 0 / 0, math.huge, "10", nil } do
					expect({ UpgradeMath.plan("snack", 0, bad, 1e12, 12, 0, 0, 0) }).toEqual({ 0, 0 })
				end
				expect({ UpgradeMath.plan("snack", 5, 10, 1e12, 3, 0, 0, 0) }).toEqual({ 0, 0 }) -- plafond sous le niveau
				expect({ UpgradeMath.plan("gift", 0, 0, 28, 2, 0, 0, 0) }).toEqual({ 2, 28 })
			end
		)
	end)

	describe("UpgradeMath › plafonds, niveaux, interrupteurs", function()
		it("interrupteurs coupés (jeu de base) : seules les 4 dalles de la v1.3 s'achètent", function()
			local d = profile({ R = 20, bestR = 20, ascend = 3, tiles = { snack = 12 } })
			local caps = {}
			for _, id in UpgradeMath.ids() do
				caps[id] = UpgradeMath.cap(id, d, Features.Defaults)
			end
			for id, cap in caps do
				local expected = ({ snack = 12, decor = 18, pens = 14, cozyBed = 1 })[id] or 0
				expect({ id = id, cap = cap }).toEqual({ id = id, cap = expected })
			end
			-- le module Config/Features lui-même est accepté (fonction get)
			expect(UpgradeMath.cap("gloves", d, Features)).toBe(0)
			Features.set("Gloves", true)
			expect(UpgradeMath.cap("gloves", d, Features)).toBe(40)
			Features.reset()
		end)

		it(
			"interrupteurs ouverts : ouverture par le Record R ou A, plafond du Tapis Étoilé par r de la boucle",
			function()
				local on = allOn()
				local function cap(id, fields)
					return UpgradeMath.cap(id, profile(fields), on)
				end
				-- Tapis Étoilé : seulement après le Tapis 12, puis 1, 2, 3, 4, 8 niveaux à r = 6, 7, 8, 9, 10
				expect(cap("star", { R = 12, bestR = 12, tiles = { snack = 11 } })).toBe(0)
				local stars = {}
				for r = 5, 11 do
					table.insert(stars, cap("star", { R = r, bestR = 15, tiles = { snack = 12 } }))
				end
				expect(stars).toEqual({ 0, 1, 2, 3, 4, 8, 8 })
				-- le plafond suit r, pas le Record R (après une Ascension : Record R 15, r = 3)
				expect(cap("star", { R = 3, bestR = 15, ascend = 1, tiles = { snack = 12 } })).toBe(0)
				-- Gants (Record R 1), École (2), Lit (3), Monuments (6, 8 … 24)
				expect({ cap("gloves", { R = 0 }), cap("gloves", { R = 1, bestR = 1 }) }).toEqual({ 0, 40 })
				expect({ cap("school", { R = 1, bestR = 1 }), cap("school", { R = 2, bestR = 2 }) }).toEqual({
					0,
					20,
				})
				expect({ cap("cozyBed", { R = 2, bestR = 2 }), cap("cozyBed", { R = 0, bestR = 3 }) }).toEqual({
					0,
					1,
				})
				local mons = {}
				for _, best in { 5, 6, 7, 8, 15, 23, 24, 400 } do
					table.insert(mons, cap("monument", { R = best, bestR = best }))
				end
				expect(mons).toEqual({ 0, 1, 1, 2, 5, 9, 10, 10 })
				-- Atelier : Record R 1 ; Plume au Record R 12 ; Tremplin après la 1re Ascension
				expect({ cap("gift", { R = 0 }), cap("gift", { R = 1, bestR = 1 }) }).toEqual({ 0, 2 })
				expect({ cap("plume", { R = 11, bestR = 11 }), cap("plume", { R = 12, bestR = 12 }) }).toEqual({
					0,
					1,
				})
				expect({
					cap("springboard", { R = 15, bestR = 15 }),
					cap("springboard", { R = 0, bestR = 15, ascend = 1 }),
				}).toEqual({ 0, 3 })
				expect({ cap("fun.palettes", { R = 0 }), cap("fun.palettes", { R = 1, bestR = 1 }) }).toEqual({
					0,
					6,
				})
				expect(cap("decoShop", { R = 1, bestR = 1 })).toBe(24)
				-- chaque interrupteur ferme sa ligne
				local function capOff(id, key, fields)
					local f = allOn()
					f[key] = false
					return UpgradeMath.cap(id, profile(fields), f)
				end
				expect(capOff("star", "StarMat", { R = 10, bestR = 10, tiles = { snack = 12 } })).toBe(0)
				expect(capOff("gloves", "Gloves", { R = 1, bestR = 1 })).toBe(0)
				expect(capOff("monument", "Monuments", { R = 8, bestR = 8 })).toBe(0)
				expect(capOff("school", "Helpers", { R = 2, bestR = 2 })).toBe(0)
				expect(capOff("plume", "Helpers", { R = 12, bestR = 12 })).toBe(0)
				expect(capOff("gift", "Workshop", { R = 1, bestR = 1 })).toBe(0)
				expect(capOff("gift", "Confetti", { R = 1, bestR = 1 })).toBe(0)
				expect(capOff("springboard", "JellyAscend", { R = 0, bestR = 15, ascend = 1 })).toBe(0)
				expect(capOff("decoShop", "DecoPerso", { R = 1, bestR = 1 })).toBe(0)
				expect(capOff("fun.title", "Workshop", { R = 1, bestR = 1 })).toBe(0)
				-- jamais au-delà du maximum ; profil ou interrupteurs illisibles : fermé
				for _, id in UpgradeMath.ids() do
					expect(
						UpgradeMath.cap(
							id,
							profile({ R = 400, bestR = 400, ascend = 60, tiles = { snack = 12 } }),
							on
						) <= UpgradeMath.maxLevel(id)
					).toBe(true)
					expect(UpgradeMath.cap(id, nil, on)).toBe(0)
				end
				expect(UpgradeMath.cap("gloves", profile({ R = 1, bestR = 1 }), nil)).toBe(0)
			end
		)

		it(
			"niveaux lus dans le profil : dalles, Lit (booléen), Atelier, bits de « Pour le plaisir », valeurs abîmées bornées",
			function()
				local d = profile({
					tiles = { snack = 7, star = 2, decor = 30, cozyBed = true, monuments = 0 / 0 },
					atelierLevels = { gift = 1, decoShop = 5, plume = -2 },
				})
				Bitset.set(d.atelierCosmetics, 1)
				Bitset.set(d.atelierCosmetics, 2)
				Bitset.set(d.atelierCosmetics, 11)
				expect({
					UpgradeMath.level("snack", d),
					UpgradeMath.level("star", d),
					UpgradeMath.level("decor", d),
					UpgradeMath.level("cozyBed", d),
					UpgradeMath.level("monument", d),
					UpgradeMath.level("gift", d),
					UpgradeMath.level("decoShop", d),
					UpgradeMath.level("plume", d),
					UpgradeMath.level("fun.palettes", d),
					UpgradeMath.level("fun.title", d),
					UpgradeMath.level("fun.saddle", d),
				}).toEqual({ 7, 2, 18, 1, 0, 1, 5, 0, 2, 1, 0 })
				-- profil v1 (sans Atelier ni cosmétiques) et profil illisible
				local v1 = Schema.defaultsV1()
				expect({
					UpgradeMath.level("gift", v1),
					UpgradeMath.level("fun.palettes", v1),
					UpgradeMath.level("star", v1),
				}).toEqual({ 0, 0, 0 })
				expect(UpgradeMath.level("snack", nil)).toBe(0)
				expect(UpgradeMath.level("nope", d)).toBe(0)
				expect(UpgradeMath.tier("gloves", 10)).toBe(3)
			end
		)
	end)

	describe("UpgradeMath › effets « avant → après » (GDD §10.7.7)", function()
		it("libellés courts du tableau du GDD : valeurs exactes du joueur", function()
			local function fx(id, L, ctx)
				local e = UpgradeMath.effect(id, L, ctx or {})
				return { e.a, e.b }
			end
			expect(fx("star", 0)).toEqual({ 13, 14 }) -- Croissance ×13 → ×14
			expect(fx("snack", 0)).toEqual({ 1, 2 })
			expect(fx("snack", 12)).toEqual({ 13, 13 })
			expect(fx("star", 8)).toEqual({ 21, 21 })
			expect(fx("pens", 8)).toEqual({ 12, 13 }) -- Places : 12 → 13
			expect(fx("pens", 8, { bigRanch = true })).toEqual({ 18, 19 })
			expect(fx("pens", 14, { bigRanch = true })).toEqual({ 24, 24 })
			expect(fx("cozyBed", 0)).toEqual({ 8, 12 }) -- Nuit : 8 h → 12 h
			local g = fx("gloves", 6) -- Pressions ×1,150 → ×1,175
			expect(math.abs(g[1] - 1.15) < 1e-12 and math.abs(g[2] - 1.175) < 1e-12).toBe(true)
			local m = fx("monument", 3) -- Revenu +3 % → +4 %
			expect(math.abs(m[1] - 0.03) < 1e-12 and math.abs(m[2] - 0.04) < 1e-12).toBe(true)
			local s = fx("school", 9) -- Aide : 9,3 s → 9,0 s
			expect(math.abs(s[1] - 9.3) < 1e-9 and math.abs(s[2] - 9.0) < 1e-9).toBe(true)
			expect(fx("gift", 0)).toEqual({ 1, 2 }) -- Cadeau : 1 → 2 niv.
			expect(fx("startMat", 0)).toEqual({ 0, 1 }) -- Départ : Tapis 0 → 1
			expect(fx("magnet", 0)).toEqual({ 5, 8 }) -- Aimant : 5 → 8 studs
			expect(fx("magnet", 3)).toEqual({ 14, 14 })
			expect(fx("superStreak", 0)).toEqual({ 5, 6 }) -- Série max : 5 → 6
			expect(fx("keptDecor", 1, { bestR = 14 })).toEqual({ 9, 12 }) -- Déco gardées : 9 → 12
			expect(fx("nightBag", 0, { cozyBed = true })).toEqual({ 12, 13 }) -- Nuit : 12 h → 13 h
			expect(fx("nightBag", 3, { cozyBed = true, spikyFamily = true })).toEqual({ 16, 16 }) -- 16 h au plus
			local p = fx("nightPot", 0) -- Pot la nuit : 25 % → 28 % (Balance.OfflineV2.NightPotShares, §21)
			expect(math.abs(p[1] - 0.25) < 1e-12 and math.abs(p[2] - 0.28) < 1e-12).toBe(true)
			expect(fx("plume", 0, { bestR = 12 })).toEqual({ 5, 6 }) -- Plopettes : 5 → 6
			expect(fx("springboard", 0)).toEqual({ 0, 1 }) -- Tremplin : 0 → 1
			expect(fx("fun.palettes", 2)).toEqual({ 2, 3 })
			expect(UpgradeMath.effect("snack", 3, {}).key).toBe("upgrades.effect.growth")
			expect(UpgradeMath.effect("decor", 3, {}).key).toBe("upgrades.effect.incomeTotal")
			-- nom de la ligne du titre « Confetti Star », pas le titre de la section « Pour le plaisir »
			-- (« fun.title ») : INT-B1-FUNTITLE, journal docs/04 §27.12 REL-1
			expect(UpgradeMath.effect("fun.title", 0, {}).key).toBe("fun.title.confettiStar")
			expect(UpgradeMath.effect("nope", 0, {})).toEqual({ a = 0, b = 0, key = "" })
		end)

		it(
			"décorations : effet RÉEL du prochain niveau = 0,05 ÷ A_bonus (« Revenu total +1,2 % »), jamais « +5 % »",
			function()
				local e = UpgradeMath.effect("decor", 10, { aBonus = 4.2 })
				expect(math.abs(e.a - 0.05 / 4.2) < 1e-15).toBe(true)
				expect(math.floor(e.a * 1000 + 0.5) / 10).toBe(1.2)
				-- sans contexte : A_bonus des seules décorations (1 + 0,05 × niveau)
				expect(UpgradeMath.effect("decor", 0, {}).a).toBe(0.05)
				expect(math.abs(UpgradeMath.effect("decor", 10, nil).a - 0.05 / 1.5) < 1e-15).toBe(true)
				-- au maximum : 0 ; A_bonus abîmé : jamais NaN ni inf
				expect(UpgradeMath.effect("decor", 18, { aBonus = 3 }).a).toBe(0)
				for _, bad in { 0, -1, 0 / 0, math.huge } do
					local x = UpgradeMath.effect("decor", 4, { aBonus = bad }).a
					expect(x == x and x > 0 and x <= 0.05).toBe(true)
				end
			end
		)
	end)

	describe("UpgradeMath › instantané et cadeau du Splorch", function()
		it(
			"snapshot de la sauvegarde-témoin v2.json : niveaux, plafonds, pièces, Confettis, r, Record R, A, version",
			function()
				local d = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
				Tables.reconcile(d, Schema.defaultsFor(2))
				local off = UpgradeMath.snapshot(d, Features.Defaults, 7)
				expect({ off.coins, off.confetti, off.r, off.bestR, off.ascend, off.version }).toEqual({
					4250000000,
					139,
					12,
					12,
					0,
					7,
				})
				expect({
					off.levels.snack,
					off.levels.decor,
					off.levels.pens,
					off.levels.cozyBed,
					off.levels.star,
				}).toEqual({ 7, 9, 14, 1, 0 })
				expect({ off.caps.snack, off.caps.gloves, off.caps.gift, off.caps.star }).toEqual({
					12,
					0,
					0,
					0,
				})
				local on = UpgradeMath.snapshot(d, allOn(), 8)
				expect({
					on.caps.gloves,
					on.caps.school,
					on.caps.monument,
					on.caps.plume,
					on.caps.springboard,
				}).toEqual({ 40, 20, 4, 1, 0 })
				-- une entrée par ligne achetable, jamais de trou
				for _, id in UpgradeMath.ids() do
					expect(type(on.levels[id]) == "number" and type(on.caps[id]) == "number").toBe(true)
				end
				-- profil illisible et version abîmée : instantané sûr
				local bad = UpgradeMath.snapshot(nil, nil, 0 / 0)
				expect({ bad.coins, bad.confetti, bad.r, bad.bestR, bad.ascend, bad.version }).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect(
					UpgradeMath.snapshot(profile({ coins = math.huge }), {}, math.huge).version < math.huge
				).toBe(true)
			end
		)

		it(
			"cadeau du Splorch : prix des niveaux suivants du Tapis dans la boucle neuve (après Prestige.apply)",
			function()
				local d = profile({
					R = 4,
					bestR = 4,
					tiles = { snack = 12 },
					atelierLevels = { startMat = 2, gift = 1 },
				})
				d.squishies = {
					a = {
						s = 1,
						m = 0,
						st = 0,
						z = Prestige.target(4),
						zg = 0,
						bf = 0,
						lk = false,
						o = "",
						at = "pen",
						b = 0,
						gd = 0,
					},
				}
				local _, report = Prestige.apply(d, "splorch", 10)
				expect({ d.tiles.snack, report.giftLevels }).toEqual({ 2, 2 })
				local coins = UpgradeMath.giftCoins(d, report.giftLevels)
				expect(coins).toBe(
					UpgradeMath.price("snack", 2, 5, 0, 5) + UpgradeMath.price("snack", 3, 5, 0, 5)
				)
				expect(UpgradeMath.giftCoins(nil, 2)).toBe(0)
				expect(UpgradeMath.giftCoins(d, 0)).toBe(0)
			end
		)
	end)
end
