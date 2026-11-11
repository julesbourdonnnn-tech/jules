--!nocheck
-- File unique des mesures ClientMetric du client (lot I, étape 4, plan I M9 / D16 ; docs/04 §27.5) :
-- toutes les mesures passent par Widgets.send, un seul seau de 1 envoi / 5 s (débit client de
-- Config/Intents.ClientMetric), une file d'au plus 4 mesures en attente (une par sorte, la plus récente
-- gagne), vidée une par 5 s, et un plafond de 20 envois par séance (celui du serveur). Avant : une
-- mesure qui tombait pendant les 5 s du seau était perdue (« ascendDeclined » juste après
-- « ascendPreview »).
local TvAudit = require("../harness/TvAudit")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function client()
		local h = TvAudit.client({})
		local W = TvAudit.mod(h, "UI.Panels.Widgets")
		W._resetBuckets()
		return h, W
	end

	local function sent(h)
		local out = {}
		for _, args in TvAudit.sent(h, "ClientMetric") do
			table.insert(out, tostring(args[1]) .. "=" .. tostring(args[2]))
		end
		return table.concat(out, ",")
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	describe("ClientMetric_queue", function()
		it(
			"« ascendDeclined » juste après « ascendPreview » n'est plus perdu : envoyé 5 s plus tard",
			function()
				local h, W = client()
				local before = #TvAudit.sent(h, "ClientMetric")
				expect(W.send("ClientMetric", "ascendPreview", 1)).toBe(true)
				expect(W.send("ClientMetric", "ascendDeclined", 0)).toBe(true)
				TvAudit.tick(h, 1)
				expect(#TvAudit.sent(h, "ClientMetric") - before).toBe(1)
				for _ = 1, 10 do
					TvAudit.tick(h, 0.5)
				end
				expect(sent(h)).toBe("ascendPreview=1,ascendDeclined=0")
				clean(h)
			end
		)

		it("une par sorte, la plus récente gagne ; 4 sortes en attente au plus ; une par 5 s", function()
			local h, W = client()
			W.send("ClientMetric", "upgradeMode", 1)
			W.send("ClientMetric", "styleFallback", 2)
			W.send("ClientMetric", "textScale", 100)
			W.send("ClientMetric", "visualBudget", 7)
			W.send("ClientMetric", "textScale", 150) -- même sorte : la valeur la plus récente, même place
			W.send("ClientMetric", "upgradeTimeout", 0)
			W.send("ClientMetric", "ascendPreview", 3)
			-- 1 parti tout de suite ; en attente : 4 sortes au plus (la plus ancienne en trop oubliée)
			expect(#TvAudit.sent(h, "ClientMetric")).toBe(1)
			local times = {}
			for step = 1, 60 do
				TvAudit.tick(h, 0.5)
				local n = #TvAudit.sent(h, "ClientMetric")
				if times[n] == nil then
					times[n] = step * 0.5
				end
			end
			expect(sent(h)).toBe(
				"upgradeMode=1,textScale=150,visualBudget=7,upgradeTimeout=0,ascendPreview=3"
			)
			-- jamais deux envois à moins de 5 s
			for n = 3, 5 do
				expect(times[n] - times[n - 1] >= 4.99).toBe(true)
			end
			clean(h)
		end)

		it("plafond de la séance : 20 envois, puis plus rien (refus, aucune trace)", function()
			local h, W = client()
			for i = 1, 40 do
				W.send("ClientMetric", "visualBudget", i)
				for _ = 1, 11 do
					TvAudit.tick(h, 0.5)
				end
			end
			expect(#TvAudit.sent(h, "ClientMetric")).toBe(20)
			expect(W.send("ClientMetric", "visualBudget", 99)).toBe(false)
			clean(h)
		end)
	end)
end
