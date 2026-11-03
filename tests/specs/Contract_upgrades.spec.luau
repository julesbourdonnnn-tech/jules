--!nocheck
-- Contrat v2.0 (docs/04 §27.6) : catalogue Config/Upgrades et tables v2.0 de Config/Balance (GDD v2.0
-- §4.6, §4.26, §4.27). Ordre fixe et identifiants définitifs, une seule source de prix par famille,
-- coûts strictement croissants (Tapis 12 → Étoilé 13 compris), cas exacts du GDD calculés par
-- MULTIPLICATIONS SUCCESSIVES (aucune puissance, règle 5 du GDD §10.8), liste fermée des effets de
-- l'Atelier, aucune chance ni aucun Robux, textes EN et FR, invariant de stabilité de la Jelly Ascend.
-- Les VALEURS de Balance appartiennent au paquet A1 (porte EconomyPacing) : un réglage qui change un
-- témoin met à jour ce fichier avec le GDD et l'écrit au journal (docs/04 §21).

local FAMILY_ORDER = { "snack", "star", "decor", "pens", "cozyBed", "gloves", "monument", "school" }
local WORKSHOP_ORDER = {
	"gift",
	"startMat",
	"magnet",
	"superStreak",
	"keptDecor",
	"nightBag",
	"nightPot",
	"plume",
	"springboard",
	"decoShop",
}
local FORBIDDEN_FIELDS =
	{ "chance", "odds", "prob", "luck", "weight", "robux", "product", "pass", "gamepass" }

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	-- Prix de référence du test, construit comme UpgradeMath doit le faire : base, puis × croissance
	-- L fois, puis × RScale r fois, puis × PriceByA[min(k, #)] pour k = 1 … A ; floor à la fin
	local function rawPrice(B, def, L)
		local src, key = string.match(def.price, "^(%w+):(%w+)$")
		local p, growth
		if src == "tile" then
			local t = B.Tiles[key]
			p, growth = t.Base, t.Growth
		elseif key == "star" then
			local snack = B.Tiles.snack
			p = snack.Base
			for _ = 1, snack.Levels - 1 do
				p *= snack.Growth
			end
			growth = B.UpgradePrices.star.Growth
		else
			local u = B.UpgradePrices[key]
			p, growth = u.Base, u.Growth
		end
		for _ = 1, L do
			p *= growth
		end
		return p
	end

	local function price(B, def, L, r, A)
		local p = rawPrice(B, def, L)
		if def.scaleR then
			for _ = 1, r do
				p *= B.Tiles.RScale
			end
		end
		if def.scaleA then
			local F = B.Ascend.PriceByA
			for k = 1, A do
				p *= F[math.min(k, #F)]
			end
		end
		return math.floor(p)
	end

	local function byId(U, id)
		for _, def in U.Families do
			if def.id == id then
				return def
			end
		end
		return nil
	end

	describe("Contrat v2 › Config/Upgrades", function()
		it("ordre fixe des lignes et identifiants définitifs ; profile.atelier rangé par ligne", function()
			local h = Harness.new()
			local U = shared(h, "Config.Upgrades")
			local ids = {}
			for _, def in U.Families do
				table.insert(ids, def.id)
			end
			expect(ids).toEqual(FAMILY_ORDER)
			local rows = {}
			for i, row in U.WorkshopRows do
				table.insert(rows, row.id)
				expect(U.WorkshopIndex[row.id]).toBe(i)
			end
			expect(rows).toEqual(WORKSHOP_ORDER)
			expect(U.Tabs).toEqual({ "suggested", "ranch", "helpers", "workshop" })
			expect(U.Modes).toEqual({ 1, 10, 0 })
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			expect(#Schema.defaultsFor(2).atelier).toBe(#U.WorkshopRows)
		end)

		it(
			"chaque famille : onglet, une seule source de prix, niveaux, champ du profil, textes EN/FR",
			function()
				local h = Harness.new()
				local U = shared(h, "Config.Upgrades")
				local B = shared(h, "Config.Balance")
				local S = shared(h, "Localization.Strings")
				local F = shared(h, "Config.Features")
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				local d = Schema.defaultsFor(2)
				local tabs = { ranch = true, helpers = true, workshop = true }
				local function hasText(key)
					return S.en[key] ~= nil and S.fr[key] ~= nil
				end
				for _, def in U.Families do
					expect({ id = def.id, tab = tabs[def.tab] == true }).toEqual({ id = def.id, tab = true })
					expect(def.currency).toBe("coins")
					expect(def.hold).toBe(true) -- tout achat de l'écran se maintient 0,6 s (critique m16)
					local src, key = string.match(def.price, "^(%w+):(%w+)$")
					local levels = if src == "tile" then B.Tiles[key].Levels else B.UpgradePrices[key].Levels
					expect({ id = def.id, levels = def.levels }).toEqual({ id = def.id, levels = levels })
					local a, b = string.match(def.profileKey, "^(%w+)%.(%w+)$")
					expect({ id = def.id, field = d[a] ~= nil and d[a][b] ~= nil }).toEqual({
						id = def.id,
						field = true,
					})
					for _, k in { def.nameKey, def.effectKey, def.reasonKey } do
						expect({ id = def.id, key = k, text = hasText(k) }).toEqual({
							id = def.id,
							key = k,
							text = true,
						})
					end
					for _, tier in def.tiers do
						expect({ id = def.id, key = tier.key, text = hasText(tier.key) }).toEqual({
							id = def.id,
							key = tier.key,
							text = true,
						})
					end
					expect(def.feature == "" or F.Defaults[def.feature] ~= nil).toBe(true)
				end
				for _, row in U.WorkshopRows do
					for _, k in { row.nameKey, row.effectKey } do
						expect({ id = row.id, key = k, text = hasText(k) }).toEqual({
							id = row.id,
							key = k,
							text = true,
						})
					end
				end
				for _, def in U.ReadOnly do
					expect({ id = def.id, text = hasText(def.nameKey) }).toEqual({ id = def.id, text = true })
				end
				for _, line in U.Fun do
					expect({ id = line.id, text = hasText(line.nameKey) }).toEqual({
						id = line.id,
						text = true,
					})
				end
			end
		)

		it(
			"totaux du GDD : 144 niveaux achetables ; Atelier 9 lignes, 21 niveaux, 654 ; « Pour le plaisir » 2 770",
			function()
				local h = Harness.new()
				local U = shared(h, "Config.Upgrades")
				local total = 0
				for _, def in U.Families do
					total += def.levels
				end
				local rows, levels, cost = 0, 0, 0
				for _, row in U.WorkshopRows do
					if row.id ~= "decoShop" then
						rows += 1
						levels += #row.costs
						for _, c in row.costs do
							cost += c
						end
					end
				end
				expect(total + levels).toBe(144)
				expect({ rows, levels, cost }).toEqual({ 9, 21, 654 })
				local fun = 0
				for _, line in U.Fun do
					for _, c in line.costs do
						fun += c
					end
				end
				for _, c in U.WorkshopRows[U.WorkshopIndex.decoShop].costs do
					fun += c
				end
				expect(fun).toBe(2770)
				expect(#U.WorkshopRows[U.WorkshopIndex.decoShop].costs).toBe(24)
				-- bits de « Pour le plaisir » : contigus, sans chevauchement, dans CosmeticBits
				local seen = {}
				for _, line in U.Fun do
					if line.store == "bits" then
						for i = 0, #line.costs - 1 do
							local bit = line.firstBit + i
							expect(seen[bit]).toBeNil()
							seen[bit] = true
							expect(bit >= 1 and bit <= U.CosmeticBits).toBe(true)
						end
						expect(#line.grants).toBe(#line.costs)
					end
				end
			end
		)

		it(
			"Atelier : coûts croissants, effets de la liste fermée, rien sur la croissance ni la chance",
			function()
				local h = Harness.new()
				local U = shared(h, "Config.Upgrades")
				for _, row in U.WorkshopRows do
					expect({ id = row.id, effect = U.WorkshopEffects[row.effect] == true }).toEqual({
						id = row.id,
						effect = true,
					})
					for i = 2, #row.costs do
						local ok = if row.id == "decoShop"
							then row.costs[i] >= row.costs[i - 1]
							else row.costs[i] > row.costs[i - 1]
						expect({ id = row.id, i = i, ok = ok }).toEqual({ id = row.id, i = i, ok = true })
					end
				end
				-- liste fermée : exactement ces effets (un effet nouveau passe par le contrat et la porte)
				local effects = {}
				for k in U.WorkshopEffects do
					table.insert(effects, k)
				end
				table.sort(effects)
				expect(effects).toEqual({
					"cosmetic",
					"extraHelper",
					"giftLevels",
					"keptDecor",
					"magnetRadius",
					"nightBagHours",
					"nightPotShare",
					"springboard",
					"startMat",
					"superStreak",
				})
				-- aucun champ de probabilité ni de Robux, nulle part dans le catalogue
				local function scan(t, path)
					for k, v in t do
						if type(k) == "string" then
							local lower = string.lower(k)
							for _, bad in FORBIDDEN_FIELDS do
								if lower == bad or string.find(lower, bad, 1, true) == 1 then
									error(path .. "." .. k .. " : champ interdit dans Config/Upgrades")
								end
							end
						end
						if type(v) == "table" then
							scan(v, path .. "." .. tostring(k))
						end
					end
				end
				scan(U, "Upgrades")
			end
		)
	end)

	describe("Contrat v2 › Prix (multiplications successives, cas exacts du GDD §4.6)", function()
		it(
			"cas exacts : Tapis, Tapis Étoilé 13 et 20, Gants 30 et 40, École, à r et A donnés",
			function()
				local h = Harness.new()
				local U = shared(h, "Config.Upgrades")
				local B = shared(h, "Config.Balance")
				local snack, star, gloves, school =
					byId(U, "snack"), byId(U, "star"), byId(U, "gloves"), byId(U, "school")
				local first = {}
				for L = 0, 4 do
					table.insert(first, price(B, snack, L, 0, 0))
				end
				expect(first).toEqual({ 20, 90, 405, 1822, 8201 })
				expect(price(B, snack, 11, 0, 0)).toBe(306455660) -- T12
				expect(price(B, star, 1, 0, 0)).toBe(383069575) -- Tapis Étoilé 13
				expect(price(B, star, 8, 0, 0)).toBe(1826618076) -- Tapis Étoilé 20
				expect(price(B, star, 1, 10, 0)).toBe(105671556317044)
				expect(price(B, star, 1, 10, 1)).toBe(52835778158522)
				expect(price(B, gloves, 0, 0, 0)).toBe(2000)
				expect(price(B, gloves, 0, 1, 0)).toBe(7000)
				expect(price(B, gloves, 29, 0, 0)).toBe(661681881)
				expect(price(B, gloves, 39, 0, 0)).toBe(52962225282)
				expect(price(B, school, 0, 0, 0)).toBe(20000)
				expect(price(B, school, 19, 0, 0)).toBe(829378782)
			end
		)

		it(
			"coûts strictement croissants, Tapis 12 → Étoilé 13 compris, pour chaque A = 0 … 8 dès son départ",
			function()
				local h = Harness.new()
				local U = shared(h, "Config.Upgrades")
				local B = shared(h, "Config.Balance")
				local snack, star = byId(U, "snack"), byId(U, "star")
				-- r d'une boucle après la A-ième Ascension : r ≥ StartR(A) (GDD §4.27) ; en dessous, des prix
				-- de moins d'une pièce n'existent jamais dans le jeu (UpgradeMath borne aussi à 1 au moins)
				local START = { [0] = 0, 0, 4, 8, 13, 17, 21, 25, 29 }
				for A = 0, 8 do
					for r = START[A], START[A] + 20, 5 do
						local last = -1
						for L = 0, snack.levels - 1 do
							local p = price(B, snack, L, r, A)
							expect(p > last).toBe(true)
							last = p
						end
						for L = 0, star.levels - 1 do
							local p = price(B, star, L + 1, r, A)
							expect({ r = r, A = A, L = L, up = p > last }).toEqual({
								r = r,
								A = A,
								L = L,
								up = true,
							})
							last = p
						end
					end
				end
				for _, def in U.Families do
					if def.price ~= "price:monument" and def.id ~= "star" then
						local last = -1
						for L = 0, def.levels - 1 do
							local p = price(B, def, L, 3, 1)
							expect({ id = def.id, L = L, up = p > last }).toEqual({
								id = def.id,
								L = L,
								up = true,
							})
							last = p
						end
					end
				end
			end
		)

		it("Monuments : 3 × T12 × 3,5^(R d'ouverture), ouverts aux Record R 6, 8 … 24", function()
			local h = Harness.new()
			local U = shared(h, "Config.Upgrades")
			local B = shared(h, "Config.Balance")
			local m = byId(U, "monument")
			expect(m.open.recordRByLevel).toEqual(B.Monuments.OpenAt)
			local t12 = price(B, byId(U, "snack"), 11, 0, 0)
			local expected =
				{ 1.69e12, 20.7e12, 254e12, 3.11e15, 38.1e15, 466e15, 5.71e18, 70.0e18, 857e18, 10.5e21 }
			for n, at in B.Monuments.OpenAt do
				local p = B.UpgradePrices.monument.PriceT12 * t12
				for _ = 1, at do
					p *= B.Tiles.RScale
				end
				local ratio = p / expected[n]
				expect({ n = n, close = ratio > 0.99 and ratio < 1.01 }).toEqual({ n = n, close = true })
			end
		end)

		it("Tapis Étoilé : plafond par r de la boucle (13 à r ≥ 6 … 20 à r ≥ 10)", function()
			local h = Harness.new()
			local U = shared(h, "Config.Upgrades")
			local cap = byId(U, "star").open.loopCapByR
			expect(cap).toEqual({ [6] = 1, [7] = 2, [8] = 3, [9] = 4, [10] = 8 })
		end)
	end)

	describe("Contrat v2 › Jelly Ascend et Confettis (Config/Balance v2.0)", function()
		it(
			"invariant de stabilité : (BeyondMult / 2)^ReqStep ≥ 0,95 × GrowthMult ; objectifs × 2,5 dès r = 16",
			function()
				local h = Harness.new()
				local B = shared(h, "Config.Balance")
				local q = 1
				for _ = 1, B.Ascend.ReqStep do
					q *= B.Splorch.BeyondMult / 2
				end
				expect(q >= 0.95 * B.Ascend.GrowthMult).toBe(true)
				local targets = B.Splorch.Targets
				for r = 16, #targets - 2 do
					-- Targets[r + 1] = objectif pour passer de r à r + 1
					expect({ r = r, ok = targets[r + 2] / targets[r + 1] >= 2.5 }).toEqual({
						r = r,
						ok = true,
					})
				end
				expect(B.Splorch.BeyondMult >= 2.5).toBe(true)
			end
		)

		it(
			"prix × F(A) : 0,5 aux 4 premières Ascensions, puis 0,32 ; Grand Splorch de départ du GDD",
			function()
				local h = Harness.new()
				local B = shared(h, "Config.Balance")
				local F = B.Ascend.PriceByA
				local f = 1
				local got = {}
				for k = 1, 6 do
					f *= F[math.min(k, #F)]
					table.insert(got, math.floor(f * 1e6 + 0.5) / 1e6)
				end
				expect(got).toEqual({ 0.5, 0.25, 0.125, 0.0625, 0.02, 0.0064 })
				-- StartR(A) sans Tremplin (référence du test ; Prestige.startR le calcule sans puissance)
				local function req(k)
					local list = B.Ascend.ReqR
					if k <= #list then
						return list[k]
					end
					return list[#list] + (k - #list) * B.Ascend.ReqStep
				end
				local starts = {}
				for A = 1, 10 do
					local floorR = math.ceil(A * math.log(3) / math.log(1.3) - B.Ascend.StartFloorOffset)
					table.insert(
						starts,
						math.min(req(A + 1) - 10, math.max(B.Ascend.StartStepPerA * (A - 1), floorR))
					)
				end
				expect(starts).toEqual({ 0, 4, 8, 13, 17, 21, 25, 29, 33, 38 })
				expect({ req(1), req(2), req(3), req(4) }).toEqual({ 15, 20, 24, 28 })
			end
		)

		it("Confettis, bornes et Souvenir de gelée : valeurs de départ du GDD v2.0", function()
			local h = Harness.new()
			local B = shared(h, "Config.Balance")
			expect(B.GddValuesV2).toBe("2.0")
			expect(B.GddValues).toBe("1.3") -- valeurs des clés de la v1.3 inchangées
			expect(B.Prestige).toEqual({ MaxR = 400, MaxA = 60 })
			expect(B.Confetti.PerGrandSplorchBase + math.min(1, B.Confetti.CapR)).toBe(4)
			expect(B.Confetti.PerGrandSplorchBase + math.min(30, B.Confetti.CapR)).toBe(23)
			expect(B.Confetti.Max).toBe(1e9)
			expect(B.Ascend.RegainMult).toBe(3)
			expect(B.Ascend.RegainTaper).toEqual({ 2, 1.5, 1.25 })
			expect(B.Ascend.GrowthMult * B.Ascend.RegainMult).toBe(9) -- « 9 fois plus vite »
			expect(B.SplorchV2.KeptDecorMax).toBe(12)
			expect(B.OfflineV2.MaxHours).toBe(16)
			expect(#B.PotV2.MagnetRadii).toBe(4)
			expect(#B.Helpers.ByRecordR).toBe(5)
			expect(B.Upgrades.HoldSeconds).toBe(0.6)
			-- jamais une clé v2.0 dans les tables parcourues par le code de base
			for _, key in { "star", "gloves", "school", "monument", "monuments" } do
				expect(B.Tiles[key]).toBeNil()
			end
			for key in B.CapsV2 do
				expect(B.Caps[key]).toBeNil()
			end
		end)
	end)
end
