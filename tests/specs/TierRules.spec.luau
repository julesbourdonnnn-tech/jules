--!nocheck
-- TierRules (paquet A1, docs/04 §27.7) : paliers nommés des familles (GDD §4.6 et Annexe B.4).
-- Seuils exacts du GDD à chaque bord, Tapis Étoilé numéroté à la suite du Tapis, accord entre
-- Config/Upgrades (clés de texte) et Config/Visuals.Tiers (rendu), entrées hostiles.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local TierRules = h:require("ReplicatedStorage.Shared.Logic.TierRules")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Visuals = h:require("ReplicatedStorage.Shared.Config.Visuals")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")

	local function series(id, from, to)
		local out = {}
		for L = from, to do
			table.insert(out, TierRules.of(id, L))
		end
		return out
	end

	describe("TierRules", function()
		it(
			"Tapis à Goûter : Nappe pique-nique 1-3, Biscuit sablé 4-6, Bonbon arc-en-ciel 7-9, Gelée dorée 10-12",
			function()
				expect(series("snack", 0, 12)).toEqual({ 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4 })
				expect(TierRules.key("snack", 0)).toBeNil()
				expect(TierRules.key("snack", 1)).toBe("upgrades.tier.snack.1")
				expect(TierRules.key("snack", 12)).toBe("upgrades.tier.snack.4")
			end
		)

		it(
			"Tapis Étoilé : « Étoilé » au Tapis 13 (palier 5), « Galaxie » au Tapis 17 (palier 6)",
			function()
				expect(series("star", 0, 8)).toEqual({ 0, 5, 5, 5, 5, 6, 6, 6, 6 })
				expect(TierRules.key("star", 1)).toBe("upgrades.tier.snack.5")
				expect(TierRules.key("star", 5)).toBe("upgrades.tier.snack.6")
				-- palier du ranch (attribut TapisTier) : le Tapis Étoilé passe devant dès son 1er niveau
				expect(TierRules.tapis(0, 0)).toBe(0)
				expect(TierRules.tapis(12, 0)).toBe(4)
				expect(TierRules.tapis(12, 1)).toBe(5)
				expect(TierRules.tapis(12, 8)).toBe(6)
				expect(TierRules.count("snack") + #Upgrades.ById.star.tiers).toBe(6)
			end
		)

		it(
			"Gants : 9 paliers (1, 5, 10 … 35, 40) ; École : 5 tabliers (1, 5, 10, 15, 20) ; Enclos : 3 aspects dès 0",
			function()
				local gloves = {}
				for _, L in { 0, 1, 4, 5, 9, 10, 14, 15, 19, 20, 24, 25, 29, 30, 34, 35, 39, 40 } do
					table.insert(gloves, TierRules.of("gloves", L))
				end
				expect(gloves).toEqual({ 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9 })
				expect(series("school", 0, 20)).toEqual({
					0,
					1,
					1,
					1,
					1,
					2,
					2,
					2,
					2,
					2,
					3,
					3,
					3,
					3,
					3,
					4,
					4,
					4,
					4,
					4,
					5,
				})
				-- Enclos : Herbe tendre (4-9 places, niveaux 0-5), Coussins moelleux (10-17), nuage (18-24)
				expect(series("pens", 0, 14)).toEqual({ 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3 })
			end
		)

		it(
			"familles sans palier, id inconnu, niveaux hostiles : 0 ou le dernier palier, jamais d'erreur",
			function()
				expect(TierRules.of("cozyBed", 1)).toBe(0)
				expect(TierRules.of("monument", 10)).toBe(0)
				expect(TierRules.of("nope", 5)).toBe(0)
				expect(TierRules.key("nope", 5)).toBeNil()
				expect(TierRules.count("nope")).toBe(0)
				for _, bad in { 0 / 0, -math.huge, -3, "4", nil, true } do
					expect(TierRules.of("gloves", bad)).toBe(0)
				end
				-- au-delà du maximum : le dernier palier (jamais un palier inexistant)
				expect(TierRules.of("gloves", 1e9)).toBe(9)
				expect(TierRules.of("gloves", math.huge)).toBe(9)
				expect(TierRules.of("snack", 4.9)).toBe(2)
				expect(TierRules.of(nil, 3)).toBe(0)
			end
		)

		it("crossed : seul le nouveau palier le plus haut est annoncé (achat ×1, ×10, Max)", function()
			expect(TierRules.crossed("gloves", 0, 1)).toBe(1)
			expect(TierRules.crossed("gloves", 1, 4)).toBeNil()
			expect(TierRules.crossed("gloves", 3, 14)).toBe(3)
			expect(TierRules.crossed("gloves", 14, 14)).toBeNil()
			expect(TierRules.crossed("snack", 9, 10)).toBe(4)
			expect(TierRules.crossed("star", 0, 1)).toBe(5)
			expect(TierRules.crossed("school", 20, 0)).toBeNil()
		end)

		it(
			"Config/Upgrades et Config/Visuals.Tiers disent les mêmes seuils ; chaque clé de palier existe en EN et FR",
			function()
				local function froms(id)
					local out = {}
					for _, tier in Upgrades.ById[id].tiers do
						table.insert(out, tier.from)
					end
					return out
				end
				local tapis = froms("snack")
				for _, f in froms("star") do
					table.insert(tapis, f + Upgrades.ById.star.levelOffset)
				end
				expect(tapis).toEqual(Visuals.Tiers.snack)
				expect(froms("gloves")).toEqual(Visuals.Tiers.gloves)
				expect(froms("school")).toEqual(Visuals.Tiers.school)
				expect(froms("pens")).toEqual(Visuals.Tiers.pens)
				for _, def in Upgrades.Families do
					for L = 0, def.levels do
						local key = TierRules.key(def.id, L)
						if key ~= nil then
							expect({ key = key, en = Strings.en[key] ~= nil, fr = Strings.fr[key] ~= nil }).toEqual({
								key = key,
								en = true,
								fr = true,
							})
						end
						-- le palier ne baisse jamais quand le niveau monte
						if L > 0 then
							expect(TierRules.of(def.id, L) >= TierRules.of(def.id, L - 1)).toBe(true)
						end
					end
				end
			end
		)
	end)
end
