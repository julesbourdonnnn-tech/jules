--!nocheck
-- Relecture des écrans et de la manette du lot B2 (écran Améliorations et HUD v2.0) : défauts trouvés
-- en regardant les captures de l'outil d'écrans (tools/screens, tv1080, tv720, tv2160, FR et EN) et
-- en jouant l'écran à la manette ; chaque cas montré rouge avant sa correction (docs/04 §27.12,
-- lignes B2-71 et suivantes). Vrai client console, interrupteurs v2.0 ouverts DANS le test. Zéro trace.
local Screens = require("../harness/Screens")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function group(id)
		for _, g in Screens.groups() do
			if g.id == id then
				return g
			end
		end
		error("groupe d'écrans inconnu : " .. id)
	end

	describe(
		"Review_B2_screens › outil d'écrans : chaque état de l'écran Améliorations est capturé",
		function()
			-- Défaut 1 : depuis B2-66 (écran fermé quand r, Record R ou A changent), les réponses fabriquées des
			-- scénarios « upgrades.buy.card » et « upgrades.buy.card.refused » portaient l'instantané du profil
			-- témoin (r = 12) alors que l'écran s'ouvrait à r = 5 : l'écran se fermait, la capture montrait le
			-- HUD seul (retour « +1 niveau » sur une carte et refus sur une carte jamais vus, jamais mesurés
			-- dans leur vraie boîte). Chaque écran du groupe « upgrades » doit montrer l'écran ouvert.
			it(
				"chaque écran du groupe « upgrades » montre l'écran Améliorations ouvert, sans trace",
				function()
					local profile = Screens.profileById("tv1080")
					local g = group("upgrades")
					local c = Screens.boot(Harness, profile, "fr", g.state)
					local closed = {}
					for _, screen in Screens.expand(c, g) do
						local ok, err = Screens.show(c, screen)
						if not ok then
							table.insert(closed, screen.id .. " : " .. tostring(err))
						elseif not c.PC.isOpen("Upgrades") then
							table.insert(
								closed,
								screen.id .. " : écran fermé (panneau " .. tostring(c.PC.current()) .. ")"
							)
						end
					end
					expect(table.concat(closed, "\n")).toBe("")
					expect(table.concat(c.h.errors, "\n")).toBe("")
					Harness.disposeAll()
				end
			)
		end
	)

	-- Défaut 2 : une ligne (ou une carte) au maximum mettait toujours « Tout est acheté : bravo ! » /
	-- « Everything is bought: well done! » dans le bandeau, même quand les autres lignes de l'onglet
	-- montrent « Prêt » ou « Il manque » (captures upgrades.ranch, upgrades.ranch.max,
	-- upgrades.card.max, upgrades.workshop, upgrades.ref.r10.mat) : la phrase est fausse. Elle reste
	-- quand tout l'onglet est au maximum ; sinon le bandeau dit ce que devient la ligne au Grand Splorch,
	-- comme pour ses autres états
	describe("Review_B2_screens › bandeau d'une ligne au maximum (GDD §10.7.6)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local TvAudit = require("../harness/TvAudit")
		local S = UpgradeScreen.new(Harness)
		local ALL_MAX = {
			snack = 12,
			star = 8,
			decor = 18,
			pens = 14,
			cozyBed = true,
			gloves = 40,
			school = 20,
			monuments = 10,
		}
		local function bannerKey(c)
			return TvAudit.mod(c.h, "UI.Text").keyOf(c.Up._banner())
		end

		it(
			"Enclos au maximum, Tapis et Décorations encore à acheter : « Gardé pour toujours »",
			function()
				local c = S.client({
					snap = S.snap(1, function(p)
						p.tiles.pens = 14
						p.coins = 10
					end),
				})
				S.open(c, "ranch")
				S.select(c, c.Up._row("pens"))
				expect(c.Up._view(c.Up._row("pens")).state).toBe("max")
				expect(c.Up._view(c.Up._row("snack")).state).toBe("need")
				expect(bannerKey(c)).toBe("upgrades.detail.kept")
				-- une ligne qui repart de zéro : « Repart de zéro au Grand Splorch »
				S.patch(
					c,
					S.snap(2, function(p)
						p.tiles.pens = 14
						p.tiles.gloves = 40
						p.coins = 10
					end)
				)
				S.open(c, "ranch")
				S.select(c, c.Up._row("gloves"))
				expect(c.Up._view(c.Up._row("gloves")).state).toBe("max")
				expect(bannerKey(c)).toBe("upgrades.detail.resets")
				S.clean(c, expect)
			end
		)

		it("tout l'onglet au maximum : « Tout est acheté : bravo ! » reste", function()
			local c = S.client({
				snap = S.snap(1, function(p)
					for k, v in ALL_MAX do
						p.tiles[k] = v
					end
					p.ascend = 1
					p.R = 20
					p.bestR = 24
					p.coins = 9.87e30
				end),
			})
			S.open(c, "ranch")
			S.select(c, c.Up._row("gloves"))
			expect(bannerKey(c)).toBe("upgrades.detail.allMax")
			S.clean(c, expect)
		end)

		it(
			"carte du Conseillé passée au maximum, les deux autres encore à acheter : ce que devient la ligne",
			function()
				-- profil de l'écran upgrades.card.max : dernier niveau de chaque ligne, Lit douillet à acheter
				local function lastLevels(cozyBed)
					return function(p)
						for k, v in { snack = 11, star = 0, decor = 18, pens = 14, gloves = 39, school = 20 } do
							p.tiles[k] = v
						end
						p.tiles.cozyBed = cozyBed
						p.R = 5
						p.bestR = 5
						p.coins = 9.99e30
					end
				end
				local c = S.client({ snap = S.snap(1, lastLevels(false)) })
				S.open(c, "suggested")
				local index = table.find(c.Up._cards(), "cozyBed")
				expect(index ~= nil).toBe(true)
				local card = c.Up._card(index)
				-- la carte garde sa famille après l'achat (GDD §10.7.4) : elle passe au maximum
				S.hold(c, card, 0.7)
				local sent = S.sent(c, "BuyUpgrade")
				expect(#sent).toBe(1)
				S.answer(c, sent[1], { to = 1, spent = 1, snap = S.snap(2, lastLevels(true)) })
				S.run(c, 2)
				expect(c.Up._view(card).state).toBe("max")
				local others = 0
				for i = 1, #c.Up._cards() do
					local v = c.Up._view(c.Up._card(i))
					if i ~= index and v and v.state == "ready" then
						others += 1
					end
				end
				expect(others > 0).toBe(true)
				expect(bannerKey(c)).toBe("upgrades.detail.kept")
				S.clean(c, expect)
			end
		)
	end)

	describe("fin des écrans", function()
		Screens.finish()
	end)
end
