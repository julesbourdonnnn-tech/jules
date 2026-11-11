--!nocheck
-- UpgradeAdvisor (paquet A1, docs/04 §27.7, GDD v2.0 §10.7.4, §10.2, N18, N24) : cartes du Conseillé
-- et cible de la puce « Prochain achat ». Règle du GDD pas à pas (Tapis payable d'abord, puis les
-- moins chères payables d'autres familles, puis les moins chères non payables, ordre fixe à
-- égalité, Monuments après le Tapis 12), 3 familles distinctes, jamais une carte vide, carte
-- « ascend » (Ascend.DeclineCardAfter), interrupteurs coupés et ouverts, instantanés abîmés, et
-- « après Prestige.apply, next ne désigne jamais un niveau déjà possédé ni inexistant ».
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	-- interrupteurs v2.0 coupés au départ (préréglage « cut » ; lot I, étape 2, D2 a, journal I-19) :
	-- chaque cas ouvre ce qu'il prouve
	local h = Harness.new({ flags = "cut" })
	local UpgradeAdvisor = h:require("ReplicatedStorage.Shared.Logic.UpgradeAdvisor")
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local DECLINE = Balance.Ascend.DeclineCardAfter
	local NEUTRAL, ASCEND = UpgradeAdvisor.NEUTRAL, UpgradeAdvisor.ASCEND

	local ON = {}
	for k, v in Features.Defaults do
		ON[k] = if type(v) == "boolean" then true else v
	end

	local function profile(fields)
		local d = Schema.defaultsFor(2)
		for k, v in fields or {} do
			if k == "tiles" then
				for tk, tv in v do
					d.tiles[tk] = tv
				end
			else
				d[k] = v
			end
		end
		return d
	end

	local function snap(fields, features)
		return UpgradeMath.snapshot(profile(fields), features or ON, 1)
	end

	local FAMILY = {}
	for _, def in Upgrades.Families do
		FAMILY[def.id] = def
	end

	-- Vérifie la forme des cartes : 3, familles distinctes (Tapis et Étoilé = une), jamais vide
	local function checkShape(cards)
		if #cards ~= 3 then
			return false, "pas 3 cartes"
		end
		local rows, ascends = {}, 0
		for _, id in cards do
			if id == ASCEND then
				ascends += 1
			elseif id ~= NEUTRAL then
				local def = FAMILY[id]
				if def == nil or def.currency ~= "coins" then
					return false, "carte inconnue " .. tostring(id)
				end
				if rows[def.row] then
					return false, "famille deux fois " .. id
				end
				rows[def.row] = true
			end
		end
		return ascends <= 1, "deux cartes ascend"
	end

	describe("UpgradeAdvisor › règle du Conseillé (GDD §10.7.4)", function()
		it(
			"début du jeu : Tapis payable d'abord, puis la moins chère payable (Décos), puis Enclos non payable",
			function()
				-- 100 pièces : Tapis 20 et Décoration 80 payables ; Enclos 1 200 ne l'est pas
				local s = snap({ coins = 100 })
				expect(UpgradeAdvisor.cards(s, {})).toEqual({ "snack", "decor", "pens" })
				expect(UpgradeAdvisor.next(s, {})).toEqual({ id = "snack", level = 1, price = 20 })
				-- 19 pièces : rien de payable ; les moins chères non payables dans l'ordre des prix
				local poor = snap({ coins = 19 })
				expect(UpgradeAdvisor.cards(poor, {})).toEqual({ "snack", "decor", "pens" })
				expect(UpgradeAdvisor.next(poor, {})).toEqual({ id = "snack", level = 1, price = 20 })
				-- Tapis non payable mais Décos payables : la Déco passe devant, puis les moins chères non
				-- payables (Enclos 1 200 avant Tapis 5 à 8 201)
				local mid = snap({ coins = 1000, tiles = { snack = 4, decor = 0 } })
				expect(UpgradeAdvisor.cards(mid, {})).toEqual({ "decor", "pens", "snack" })
				expect(UpgradeAdvisor.next(mid, {}).id).toBe("decor")
			end
		)

		it(
			"la moins chère d'abord parmi les payables, puis les non payables ; une case vide devient neutre",
			function()
				-- Record R 3 : Gants (2 000 × 3,5^3), École, Lit (25 M) ouverts ; beaucoup de pièces
				local s = snap({ R = 3, bestR = 3, coins = 1e12, tiles = { snack = 12, decor = 18 } })
				-- Tapis au maximum (Étoilé fermé à r = 3) ; payables : Enclos 1 200, Gants 85 750, École 857 500, Lit 25 M
				expect(UpgradeAdvisor.cards(s, {})).toEqual({ "pens", "gloves", "school" })
				-- Lit 25 M avant Enclos 14 à 33,9 M ; plus rien d'autre : carte neutre
				local tie = UpgradeMath.snapshot(profile({ R = 3, bestR = 3, coins = 1e12 }), ON, 1)
				tie.levels.snack, tie.levels.decor, tie.levels.gloves, tie.levels.school = 12, 18, 40, 20
				tie.levels.pens = 13
				expect(UpgradeAdvisor.cards(tie, {})).toEqual({ "cozyBed", "pens", NEUTRAL })
			end
		)

		it(
			"Tapis Étoilé : sur la ligne du Tapis après le Tapis 12, jamais avec lui ; plafond de la boucle respecté",
			function()
				local s = snap({ R = 10, bestR = 10, coins = 1e30, tiles = { snack = 12 } })
				local cards = UpgradeAdvisor.cards(s, {})
				expect(cards[1]).toBe("star")
				expect(table.find(cards, "snack")).toBeNil()
				-- plafond de la boucle atteint (r = 7 : 2 niveaux) : l'Étoilé n'est plus candidat
				local capped = snap({ R = 7, bestR = 7, coins = 1e30, tiles = { snack = 12, star = 2 } })
				expect(table.find(UpgradeAdvisor.cards(capped, {}), "star")).toBeNil()
			end
		)

		it("Monuments seulement après le Tapis 12 de la boucle", function()
			local early =
				snap({ R = 8, bestR = 8, coins = 1e30, tiles = { snack = 11, decor = 18, pens = 14 } })
			for _, id in UpgradeAdvisor.cards(early, {}) do
				expect(id ~= "monument").toBe(true)
			end
			local late = UpgradeMath.snapshot(
				profile({
					R = 8,
					bestR = 8,
					coins = 1e30,
					tiles = { snack = 12, star = 3, decor = 18, pens = 14, cozyBed = true },
				}),
				ON,
				1
			)
			late.levels.gloves, late.levels.school = 40, 20
			expect(UpgradeAdvisor.cards(late, {})).toEqual({ "monument", NEUTRAL, NEUTRAL })
		end)

		it(
			"tout au maximum : 3 cartes neutres, next = nil ; interrupteurs coupés : seulement les 4 dalles de la v1.3",
			function()
				local all = UpgradeMath.snapshot(profile({ R = 30, bestR = 30, coins = 1e30 }), ON, 1)
				for _, def in Upgrades.Families do
					all.levels[def.id] = def.levels
				end
				expect(UpgradeAdvisor.cards(all, {})).toEqual({ NEUTRAL, NEUTRAL, NEUTRAL })
				expect(UpgradeAdvisor.next(all, {})).toBeNil()
				-- jeu de base (interrupteurs coupés) : jamais une famille v2.0
				local base =
					snap({ R = 20, bestR = 20, coins = 1e30, tiles = { snack = 12 } }, Features.Defaults)
				for _, id in UpgradeAdvisor.cards(base, {}) do
					expect(id == "decor" or id == "pens" or id == "cozyBed" or id == "snack" or id == NEUTRAL).toBe(
						true
					)
				end
			end
		)
	end)

	describe("UpgradeAdvisor › carte « Jelly Ascend » (critique M1, N24)", function()
		local function stuck()
			-- Record R 15, r = 15 : rien de payable (0 pièce), familles restantes non payables
			return snap({ R = 15, bestR = 15, coins = 0, tiles = { snack = 12 } })
		end

		it(
			"prête et rien de payable depuis DeclineCardAfter (300 s) : la carte ascend prend la 3e place",
			function()
				local s = stuck()
				local plain = UpgradeAdvisor.cards(s, { ascendReady = true, unpayableSeconds = DECLINE - 1 })
				expect(table.find(plain, ASCEND)).toBeNil()
				local cards = UpgradeAdvisor.cards(s, { ascendReady = true, unpayableSeconds = DECLINE })
				expect(cards[3]).toBe(ASCEND)
				expect({ cards[1], cards[2] }).toEqual({ plain[1], plain[2] })
				-- pas prête, ou délai illisible : jamais
				expect(
					table.find(
						UpgradeAdvisor.cards(s, { ascendReady = false, unpayableSeconds = 1e6 }),
						ASCEND
					)
				).toBeNil()
				expect(
					table.find(
						UpgradeAdvisor.cards(s, { ascendReady = true, unpayableSeconds = 0 / 0 }),
						ASCEND
					)
				).toBeNil()
				expect(table.find(UpgradeAdvisor.cards(s, nil), ASCEND)).toBeNil()
				-- next ne désigne jamais l'Ascension (la puce montre un achat)
				expect(UpgradeAdvisor.next(s, { ascendReady = true, unpayableSeconds = 1e6 }).id).toBe(
					plain[1]
				)
			end
		)

		it(
			"un achat de pièces possible : jamais de carte ascend ; tout au maximum : elle remplace la 1re carte neutre",
			function()
				local rich = snap({ R = 15, bestR = 15, coins = 1e30, tiles = { snack = 12 } })
				expect(
					table.find(
						UpgradeAdvisor.cards(rich, { ascendReady = true, unpayableSeconds = 1e6 }),
						ASCEND
					)
				).toBeNil()
				local all = UpgradeMath.snapshot(profile({ R = 15, bestR = 15, coins = 0 }), ON, 1)
				for _, def in Upgrades.Families do
					all.levels[def.id] = def.levels
				end
				all.levels.gloves = 39 -- une seule famille restante, non payable
				expect(UpgradeAdvisor.cards(all, { ascendReady = true, unpayableSeconds = DECLINE })).toEqual({
					"gloves",
					ASCEND,
					NEUTRAL,
				})
			end
		)
	end)

	describe("UpgradeAdvisor › propriétés", function()
		it(
			"5 000 instantanés tirés au hasard (abîmés compris) : 3 cartes, familles distinctes, ouvertes et pas au maximum",
			function()
				local WEIRD = { 0 / 0, math.huge, -1, "x", nil, 1e300 }
				Props.check(
					5000,
					Props.gen(function(rng)
						local d = Schema.defaultsFor(2)
						d.R = rng.int(0, MAX_R)
						d.bestR = math.min(MAX_R, d.R + rng.int(0, 30))
						d.ascend = rng.int(0, MAX_A)
						d.coins = rng.range(0, 1e40)
						for _, def in Upgrades.Families do
							if def.id ~= "cozyBed" then
								local a, b = string.match(def.profileKey, "^(%w+)%.(%w+)$")
								d[a][b] = rng.int(0, def.levels)
							end
						end
						local s = UpgradeMath.snapshot(
							d,
							if rng.chance(0.2) then Features.Defaults else ON,
							rng.int(0, 99)
						)
						if rng.chance(0.1) then
							s.coins = rng.pick(WEIRD)
							s.levels[rng.pick({ "snack", "gloves", "decor" })] = rng.pick(WEIRD)
						end
						return {
							s = s,
							ctx = {
								ascendReady = rng.chance(0.5),
								unpayableSeconds = rng.pick({ 0, 299, 300, 1e6 }),
							},
						}
					end),
					function(c)
						local cards = UpgradeAdvisor.cards(c.s, c.ctx)
						local ok, why = checkShape(cards)
						if not ok then
							error(why, 0)
						end
						for _, id in cards do
							if FAMILY[id] then
								local lvl = c.s.levels[id]
								if
									type(lvl) == "number"
									and lvl == lvl
									and not (lvl < c.s.caps[id] and lvl < FAMILY[id].levels)
								then
									error("carte fermée ou au maximum : " .. id, 0)
								end
							end
						end
						local nxt = UpgradeAdvisor.next(c.s, c.ctx)
						if nxt ~= nil then
							if
								nxt.level > c.s.caps[nxt.id]
								or nxt.level > UpgradeMath.maxLevel(nxt.id)
								or nxt.price == math.huge
							then
								error("next au-delà du plafond", 0)
							end
						end
						-- instantané illisible : jamais d'erreur
						UpgradeAdvisor.cards(nil, nil)
						UpgradeAdvisor.next({ levels = "x", caps = 3 }, nil)
						return true
					end
				)
			end
		)

		it(
			"après Prestige.apply (Grand, Petit Splorch, Ascension), next ne désigne jamais un niveau déjà possédé ni inexistant",
			function()
				local applied = 0
				Props.check(
					3000,
					Props.gen(function(rng)
						local d = Schema.defaultsFor(2)
						d.R = rng.int(0, MAX_R - 1)
						d.bestR = if rng.chance(0.5) then d.R else math.min(MAX_R, d.R + rng.int(1, 30))
						d.ascend = rng.int(0, MAX_A)
						d.coins = rng.range(0, 1e20)
						for _, def in Upgrades.Families do
							if def.id ~= "cozyBed" then
								local a, b = string.match(def.profileKey, "^(%w+)%.(%w+)$")
								d[a][b] = rng.int(0, def.levels)
							end
						end
						for i, row in Upgrades.WorkshopRows do
							d.atelier[i] = rng.int(0, #row.costs)
						end
						d.squishies = {
							x = {
								s = 1,
								m = 0,
								st = 0,
								z = Prestige.target(d.R),
								zg = 0,
								bf = 0,
								lk = false,
								o = "",
								at = "dodo",
								b = 0,
								gd = 0,
							},
						}
						return { d = d, kind = rng.pick({ "splorch", "petit", "ascend" }) }
					end),
					function(c)
						local d = c.d
						local before = UpgradeAdvisor.next(UpgradeMath.snapshot(d, ON, 1), {})
						local _, report = Prestige.apply(d, c.kind, 100)
						if report.applied then
							applied += 1
						end
						local s = UpgradeMath.snapshot(d, ON, 2)
						local nxt = UpgradeAdvisor.next(s, {})
						if nxt == nil then
							-- rien d'ouvert sous le maximum : vrai seulement si chaque famille est fermée ou pleine
							for _, def in Upgrades.Families do
								if
									s.caps[def.id] > s.levels[def.id]
									and (def.id ~= "monument" or s.levels.snack >= 12)
								then
									error("next = nil alors que " .. def.id .. " est ouvert", 0)
								end
							end
							return true
						end
						local owned = UpgradeMath.level(nxt.id, d)
						if nxt.level ~= owned + 1 then
							error(
								string.format("next %s niveau %d, possédé %d", nxt.id, nxt.level, owned),
								0
							)
						end
						if
							nxt.level > UpgradeMath.cap(nxt.id, d, ON)
							or nxt.level > UpgradeMath.maxLevel(nxt.id)
						then
							error("next inexistant ou fermé", 0)
						end
						if
							nxt.price
							~= UpgradeMath.price(
								nxt.id,
								owned,
								Prestige.r(d),
								Prestige.ascend(d),
								Prestige.bestR(d)
							)
						then
							error("prix de next ≠ prix du serveur", 0)
						end
						local _ = before
						return true
					end
				)
				expect(applied > 1000).toBe(true)
			end
		)
	end)
end
