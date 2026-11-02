--!nocheck
-- tests/harness/Fuzz (paquet meta, docs/04 §17.1 b) : charges hostiles par sorte d'argument (nil, NaN,
-- ±inf, 1e308, 100 000 caractères, UTF-8 invalide, tables profondes, mixtes, à trous, Vector3…), marque
-- « valide pour les types » juste, attaque au nom d'un joueur, détection d'un profil changé, mesure du
-- débit d'une rafale.
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("Fuzz", function()
		it(
			"payloads : chaque argument remplacé par chaque valeur hostile, plus aucun argument, tout à nil, en trop",
			function()
				local list = Fuzz.payloads("PetPress", { otherUid = "zz" })
				local labels = {}
				for _, e in list do
					labels[e.label] = e
				end
				for _, label in
					{
						"ownerId = NaN",
						"ownerId = +inf",
						"uid = 100 000 caractères",
						"uid = UTF-8 invalide",
						"uid = table profonde",
						"uid = table à trous",
						"uid = uid d'un autre joueur",
						"tClient = Vector3",
						"aucun argument",
						"tout à nil",
						"arguments en trop",
					}
				do
					expect(labels[label] ~= nil).toBe(true)
				end
				expect(labels["ownerId = NaN"].valid).toBe(false)
				expect(labels["uid = uid d'un autre joueur"].valid).toBe(true) -- refusé par les règles, pas les types
				expect(labels["arguments en trop"].valid).toBe(true)
				expect(labels["aucun argument"].valid).toBe(false)
				expect(#list > 3 * 20).toBe(true)
			end
		)

		it("typeValid suit les sortes de Config/Intents (bornes, ensembles, troncature)", function()
			local Intents = require("../../src/shared/Config/Intents")
			local slot = Intents.ClaimObjective.args[1]
			expect(Fuzz.typeValid(slot, 1)).toBe(true)
			expect(Fuzz.typeValid(slot, 4)).toBe(false)
			expect(Fuzz.typeValid(slot, 1.5)).toBe(false)
			local screen = Intents.UiSeen.args[1]
			expect(Fuzz.typeValid(screen, "objectives")).toBe(true)
			expect(Fuzz.typeValid(screen, "__index")).toBe(false)
			local message = Intents.ReportError.args[3]
			expect(Fuzz.typeValid(message, string.rep("a", 1000))).toBe(true) -- tronqué par le serveur
			local key = Intents.SetSetting.args[1]
			expect(Fuzz.typeValid(key, string.rep("a", 33))).toBe(false)
			local ids = Intents.ReportBlocked.args[1]
			expect(Fuzz.typeValid(ids, {})).toBe(true)
			expect(Fuzz.typeValid(ids, table.create(201, 5))).toBe(false)
			expect(Fuzz.typeValid(ids, { 1, -1 })).toBe(false)
		end)

		it("attack, profileUnchanged et rate sur un vrai serveur", function()
			local w = Brains.boot(Harness, { t0 = 1800000000 + 60, stubMeta = false })
			local p =
				Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 1, z = 10 } } }) })
			local n = Fuzz.attack(w.h, p, "UiSeen", 5)
			expect(n).toBe(5)
			-- un vrai changement est vu, avec son chemin
			local ok, path = Fuzz.profileUnchanged(w.h, p, function()
				w.DS.get(p).coins += 1
			end)
			expect(ok).toBe(false)
			expect(path).toBe("profil.coins")
			local same = Fuzz.profileUnchanged(w.h, p, function() end)
			expect(same).toBe(true)
			-- débit : 2 / 1 s, os.clock figé → 2 messages passent sur 1 000
			w.osClock.advance(10)
			expect(Fuzz.rate(w.h, p, "UiSeen", 1000)).toBe(2)
		end)
	end)
end
