--!nocheck
-- DiagRules (paquet logic, docs/04 §11.2, §12.1, GDD §12.11) : nettoyage des noms et des nombres,
-- UTF-8, longueurs, clés courtes, contexte compact, fusion des totaux du jour.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local D = h:require("ReplicatedStorage.Shared.Logic.DiagRules")
	local L = D.Limits

	describe("DiagRules", function()
		it("normalize : nombres → #, Players.<nom> et noms fournis → <joueur>", function()
			local text = "Players.Alice.PlayerGui.Hud:42: attempt to index nil (Alice, 3 fois, BobTheBuilder)"
			local out = D.normalize(text, { "Alice", "BobTheBuilder" })
			expect(out).toBe(
				"Players.<joueur>.PlayerGui.Hud:#: attempt to index nil (<joueur>, # fois, <joueur>)"
			)
			expect(D.normalize('Players["Évé 2"].Character', nil)).toBe("Players.<joueur>.Character")
			expect(D.normalize("Workspace.Model12.Part3", nil)).toBe("Workspace.Model#.Part#")
		end)

		it(
			"normalize : un nom court n'abîme jamais un « <joueur> » déjà posé ; noms vides ignorés",
			function()
				local out = D.normalize("Players.ou failed for ou", { "ou", "", 5 })
				expect(out).toBe("Players.<joueur> failed for <joueur>")
				-- caractères magiques des motifs dans un nom
				expect(D.normalize("hi a.b%c", { "a.b%c" })).toBe("hi <joueur>")
			end
		)

		it("normalize : UTF-8 invalide remplacé, texte énorme borné, jamais d'erreur", function()
			local out = D.normalize("ok \255\254 fin", nil)
			expect(D.validUtf8(out)).toBe(true)
			expect(out).toBe("ok ?? fin")
			expect(#D.normalize(string.rep("é", 100000), nil) <= 4000).toBe(true)
			expect(D.normalize(nil, nil)).toBe("")
			expect(D.normalize("a\0b", nil)).toBe("ab")
		end)

		it("truncate : ≤ max octets, sans casser un caractère", function()
			expect(D.truncate("héllo", 2)).toBe("h") -- « é » (2 octets) ne tient pas
			expect(D.truncate("héllo", 3)).toBe("hé")
			expect(D.truncate("abc", 10)).toBe("abc")
			expect(D.truncate("😀😀", 5)).toBe("😀")
			expect(D.truncate("x", 0)).toBe("")
			expect(D.truncate(nil, 10)).toBe("")
			expect(D.truncate("ab\192cd", 10)).toBe("ab?cd")
			expect(#D.truncate(string.rep("a", 1000), L.Message)).toBe(300)
		end)

		it("validUtf8 : RFC 3629 (surlongues, substituts et > U+10FFFF refusés)", function()
			expect(D.validUtf8("")).toBe(true)
			expect(D.validUtf8("héllo 日本 😀")).toBe(true)
			expect(D.validUtf8("\192\128")).toBe(false) -- surlongue
			expect(D.validUtf8("\237\160\128")).toBe(false) -- substitut U+D800
			expect(D.validUtf8("\244\144\128\128")).toBe(false) -- > U+10FFFF
			expect(D.validUtf8("\226\130")).toBe(false) -- tronquée
			expect(D.validUtf8(5)).toBe(false)
		end)

		it("key : 8 caractères hexadécimaux, stable, différente selon le texte et la source", function()
			local k = D.key("attempt to index nil", "client")
			expect(#k).toBe(8)
			expect(string.match(k, "^[0-9a-f]+$") ~= nil).toBe(true)
			expect(D.key("attempt to index nil", "client")).toBe(k)
			expect(D.key("attempt to index nil", "server") ~= k).toBe(true)
			expect(D.key("other", "client") ~= k).toBe(true)
			expect(#D.key(nil, nil)).toBe(8)
		end)

		it("context : champs connus dans l'ordre, valeurs nettoyées, ≤ 120", function()
			local ctx = D.context({
				device = "console",
				input = 3,
				resolution = "1920x1080",
				lang = "fr",
				version = 42,
				step = 7,
				window = "Ranch;=x",
				event = "rush",
				secret = "ignoré",
			})
			expect(ctx).toBe("dev=console;in=3;res=1920x1080;lang=fr;ver=42;step=7;win=Ranchx;ev=rush")
			local long = D.context({
				device = string.rep("a", 500),
				input = string.rep("b", 500),
				lang = string.rep("c", 500),
				event = string.rep("d", 500),
				window = string.rep("e", 500),
				version = string.rep("f", 500),
			})
			expect(#long <= L.Context).toBe(true)
			expect(D.context(nil)).toBe("")
			expect(D.context({ input = 0 / 0, step = math.huge, device = true })).toBe("dev=1;in=0;step=0")
		end)

		it(
			"mergeDaily : additionne par clé, garde les 50 plus fréquentes, < 4 Ko, le reste dans « others »",
			function()
				local function entry(key, count)
					return {
						key = key,
						kind = 1,
						text = "err " .. key,
						source = "server",
						count = count,
						players = 1,
						first = 100,
						last = 200,
					}
				end
				local day = D.mergeDaily(nil, { entry("a", 3), entry("b", 1) })
				day = D.mergeDaily(day, { entry("a", 2), entry("c", 6) })
				expect(#day.entries).toBe(3)
				expect(day.entries[1].key).toBe("c")
				expect(day.entries[2].key).toBe("a")
				expect(day.entries[2].count).toBe(5)
				expect(day.entries[2].players).toBe(2)
				-- 80 clés : 50 au plus (et la taille reste sous 4 Ko)
				local many = {}
				for i = 1, 80 do
					table.insert(many, entry("k" .. i, i))
				end
				local big = D.mergeDaily(day, many)
				expect(#big.entries <= L.DailyTop).toBe(true)
				local bytes = 0
				for _, e in big.entries do
					bytes += #e.key + #e.text + 96
				end
				expect(bytes < L.DailyBytes).toBe(true)
				expect(big.others > 0).toBe(true)
				expect(big.entries[1].key).toBe("k80")
			end
		)

		it("mergeDaily : valeur actuelle abîmée (UpdateAsync) → repart proprement", function()
			local out = D.mergeDaily(
				{ entries = { { key = 5 }, "x", { key = "ok", count = 0 / 0, text = "\255" } }, others = -3 },
				{}
			)
			expect(#out.entries).toBe(1)
			expect(out.entries[1].count).toBe(0)
			expect(D.validUtf8(out.entries[1].text)).toBe(true)
			expect(out.others).toBe(0)
			expect(D.mergeDaily("garbage", nil)).toEqual({ entries = {}, others = 0 })
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
