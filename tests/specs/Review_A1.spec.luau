--!nocheck
-- Review_A1 (lot A1, étape 4 : relecture indépendante ; docs/04 §27.12 A1-37 et suivants, rapport
-- scratchpad/v2/revue-A1.md) : chaque cas est un défaut trouvé à la relecture du lot A1, écrit AVANT
-- sa correction (il échouait sur d0ab475).
--   1. Prestige.validateConfig : l'invariant de stabilité (GDD §4.27, critique M13) n'était vérifié
--      que sur Ascend.ReqStep. Depuis le réglage A1-32, les 60 conditions sont une LISTE
--      (Balance.Ascend.ReqR) et ReqStep ne sert plus qu'au-delà de la 60e Ascension (jamais jouée) :
--      une configuration envoyée en direct avec un pas de 3 dans la liste (boucle record de plus en
--      plus courte : l'économie qui s'emballe, A = 60 au jour 84 d'après la critique) était acceptée.
--      Chaque pas de la liste passe maintenant l'invariant, comme ReqStep.
--   2. UpgradeMath.effect("cozyBed") écrivait toujours « Nuit : 8 h → 12 h » : la famille Spiky
--      (+1 h) et le Sac de nuit de l'Atelier (+1 h par niveau, 16 h au plus) étaient oubliés, quand
--      la ligne du Sac de nuit les comptait (GDD §10.7.7 : « les valeurs sont celles du joueur »). Un
--      joueur au Sac de nuit 1 lisait 8 h → 12 h pour 9 h → 13 h réelles (Formulas.offlineSeconds).
-- Les défauts de la porte d'économie (alarme rapide élargie des deux côtés, Gants et École ouverts
-- par r au lieu du Record R dans everyFamilyBought) sont dans EconomyPacing.spec › « règles de la
-- porte » (fonctions locales de la spec).
-- Zéro trace : aucune erreur ni avertissement.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Tables = h:require("ReplicatedStorage.Shared.Util.Tables")

	local function with(mutate)
		local b = Tables.deepCopy(Balance)
		mutate(b)
		return Prestige.validateConfig(b)
	end

	describe("Review_A1 › 1. invariant de stabilité sur la liste des conditions", function()
		it("la configuration livrée passe (pas de 4 et de 5)", function()
			expect({ Prestige.validateConfig(Balance) }).toEqual({ true })
		end)

		it("un seul pas de 3 dans la liste (ReqStep 4 inchangé) est refusé, avec sa raison", function()
			local ok, why = with(function(b)
				local list = b.Ascend.ReqR
				-- 12e condition à + 3 au lieu de + 4, la suite décalée d'autant (liste croissante)
				for i = 12, #list do
					list[i] -= 1
				end
			end)
			expect(ok).toBe(false)
			expect(type(why) == "string" and string.find(why, "stabilité", 1, true) ~= nil).toBe(true)
		end)

		it("une liste entièrement à + 3 est refusée ; une liste à + 5 est acceptée", function()
			expect((with(function(b)
				local list = b.Ascend.ReqR
				for i = 3, #list do
					list[i] = list[i - 1] + 3
				end
			end))).toBe(false)
			expect((with(function(b)
				local list = b.Ascend.ReqR
				for i = 3, #list do
					list[i] = list[i - 1] + 5
				end
			end))).toBe(true)
		end)

		it(
			"propriété (2 000 listes tirées) : acceptée exactement quand CHAQUE pas (et ReqStep) tient l'invariant",
			function()
				Props.check(
					2000,
					Props.gen(function(rng)
						local steps = {}
						for i = 1, 59 do
							steps[i] = if rng.chance(0.03) then rng.int(1, 3) else rng.int(4, 6)
						end
						return {
							steps = steps,
							reqStep = rng.int(3, 6),
							growth = rng.pick({ 2.5, 2.85, 3, 3.2 }),
						}
					end),
					function(c)
						local b = Tables.deepCopy(Balance)
						b.Ascend.GrowthMult = c.growth
						b.Ascend.ReqStep = c.reqStep
						local list = { 15 }
						for i, s in c.steps do
							list[i + 1] = list[i] + s
						end
						b.Ascend.ReqR = list
						-- référence indépendante (puissance permise dans le test)
						local ratio = Balance.Splorch.BeyondMult / 2
						local stable = ratio ^ c.reqStep >= 0.95 * c.growth
						for _, s in c.steps do
							if ratio ^ s < 0.95 * c.growth then
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
	end)

	describe("Review_A1 › 2. Lit douillet : les vraies heures du joueur", function()
		-- limite réelle du jeu (Formulas.offlineSeconds, interrupteur Workshop ouvert pour le Sac)
		local function realHours(cozyBed, spiky, bag)
			Features.set("Workshop", true)
			local s = Formulas.offlineSeconds(1e9, 1, cozyBed, spiky, bag)
			Features.reset()
			return s / 3600
		end

		it("sans bonus : 8 h → 12 h (GDD §10.7.7)", function()
			local e = UpgradeMath.effect("cozyBed", 0, {})
			expect({ e.a, e.b }).toEqual({ 8, 12 })
		end)

		it("famille Spiky et Sac de nuit : les heures de Formulas.offlineSeconds, avant et après", function()
			for _, spiky in { false, true } do
				for bag = 0, 3 do
					local e = UpgradeMath.effect("cozyBed", 0, { spikyFamily = spiky, nightBag = bag })
					expect({ spiky = spiky, bag = bag, a = e.a, b = e.b }).toEqual({
						spiky = spiky,
						bag = bag,
						a = realHours(false, spiky, bag),
						b = realHours(true, spiky, bag),
					})
					local owned = UpgradeMath.effect("cozyBed", 1, { spikyFamily = spiky, nightBag = bag })
					expect({ a = owned.a, b = owned.b }).toEqual({
						a = realHours(true, spiky, bag),
						b = realHours(true, spiky, bag),
					})
				end
			end
		end)

		it("Sac de nuit illisible : borné à ses 3 niveaux, jamais d'erreur", function()
			for _, bad in { 0 / 0, math.huge, -2, 99, "x" } do
				local e = UpgradeMath.effect("cozyBed", 0, { nightBag = bad })
				expect(e.a == e.a and e.b == e.b and e.a >= 8 and e.b <= 16).toBe(true)
			end
		end)
	end)

	describe("Review_A1 › zéro trace", function()
		it("aucune erreur ni aucun avertissement", function()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)
end
