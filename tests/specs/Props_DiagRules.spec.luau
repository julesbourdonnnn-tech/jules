--!nocheck
-- Props_DiagRules (paquet logic, docs/04 §17.1 couche a) : tout texte (UTF-8 invalide, 100 000
-- octets) donne un texte valide, borné, sans chiffre ni nom ; la fusion du jour reste bornée.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")

	local h = Harness.new()
	local D = h:require("ReplicatedStorage.Shared.Logic.DiagRules")
	local L = D.Limits

	describe("Props › DiagRules", function()
		it("normalize : UTF-8 valide, aucun chiffre, aucun nom fourni, ≤ 4 000 octets", function()
			Props.check(
				3000,
				Props.tuple(Props.string(80), Props.oneOf({ "Alice", "Bob_42", "Zoé" })),
				function(v)
					local out = D.normalize(v[1] .. " " .. v[2] .. " 123", { v[2] })
					return D.validUtf8(out)
						and #out <= 4000
						and string.find(out, "%d") == nil
						and string.find(out, v[2], 1, true) == nil
				end
			)
		end)

		it("truncate : UTF-8 valide et ≤ max, idempotent", function()
			Props.check(4000, Props.tuple(Props.string(80), Props.int(0, 120)), function(v)
				local out = D.truncate(v[1], v[2])
				return D.validUtf8(out) and #out <= v[2] and D.truncate(out, v[2]) == out
			end)
		end)

		it("truncate d'une chaîne valide : un préfixe de l'original", function()
			Props.check(4000, Props.tuple(Props.utf8(40), Props.int(1, 200)), function(v)
				local out = D.truncate(v[1], v[2])
				return string.sub(v[1], 1, #out) == out
			end)
		end)

		it("validUtf8 : vrai pour toute chaîne construite de caractères valides", function()
			Props.check(4000, Props.utf8(60), function(s)
				return D.validUtf8(s)
			end)
		end)

		it("key : toujours 8 caractères hexadécimaux", function()
			Props.check(4000, Props.tuple(Props.any(), Props.any()), function(v)
				local k = D.key(v[1], v[2])
				return #k == 8 and string.match(k, "^[0-9a-f]+$") ~= nil
			end)
		end)

		it("context : ≤ 120 octets, UTF-8 valide, pour tous champs", function()
			local fields = Props.map(
				Props.tuple(
					Props.any(),
					Props.any(),
					Props.any(),
					Props.any(),
					Props.any(),
					Props.any(),
					Props.any(),
					Props.any()
				),
				function(v)
					return {
						device = v[1],
						input = v[2],
						resolution = v[3],
						lang = v[4],
						version = v[5],
						step = v[6],
						window = v[7],
						event = v[8],
					}
				end
			)
			Props.check(3000, fields, function(f)
				local c = D.context(f)
				return #c <= L.Context and D.validUtf8(c)
			end)
		end)

		it("mergeDaily : ≤ 50 entrées, triées, totaux conservés (gardés + others)", function()
			local entryGen = Props.map(
				Props.tuple(Props.int(1, 80), Props.int(0, 1000), Props.string(30)),
				function(v)
					return {
						key = "k" .. v[1],
						kind = 1,
						text = v[3],
						source = "client",
						count = v[2],
						players = 1,
						first = 1,
						last = 2,
					}
				end
			)
			Props.check(1500, Props.tuple(Props.array(entryGen, 40), Props.array(entryGen, 40)), function(v)
				local day = D.mergeDaily(D.mergeDaily(nil, v[1]), v[2])
				if #day.entries > L.DailyTop then
					return false
				end
				local kept = 0
				for i, e in day.entries do
					kept += e.count
					if i > 1 and day.entries[i - 1].count < e.count then
						return false
					end
				end
				local total = 0
				for _, list in v do
					for _, e in list do
						total += e.count
					end
				end
				return kept + day.others == total
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
