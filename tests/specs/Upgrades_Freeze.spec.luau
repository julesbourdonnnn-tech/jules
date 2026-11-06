--!nocheck
-- Upgrades_Freeze (lot B2, étape 2 : partie AFFICHAGE ; docs/04 §27.8 règle 19 ; GDD v2.0 §10.7.5 ;
-- décisions D7 et D8 du plan B2) : à l'ouverture, l'écran fige l'ensemble des lignes montrées,
-- l'état cadenas / boucle de chaque ligne (plafonds, r, Record R, A), les familles du Conseillé et les
-- lignes « Conseillé » de l'Atelier. Écran ouvert, un instantané plus récent ne change que les pièces,
-- les Confettis et les niveaux ; un interrupteur ou un plafond qui change n'apparaît qu'à la
-- prochaine ouverture :
--   * une famille coupée par son interrupteur (Gants, D8) reste cachée tant que l'écran est ouvert,
--     même si l'interrupteur s'ouvre ; elle apparaît à la réouverture (et l'inverse : coupée écran
--     ouvert, elle reste montrée jusqu'à la fermeture : le refus du serveur est l'étape 3) ;
--   * le plafond de la boucle du Tapis Étoilé qui s'ouvre écran ouvert : « Boucle 6 » reste ;
--   * les pièces, elles, suivent (compteur) et l'état Prêt / Il manque aussi.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function flagsWith(over)
		local f = table.clone(S.ON)
		for k, v in over do
			f[k] = v
		end
		return f
	end

	local function state(c, id)
		return c.Up._row(id):GetAttribute("State")
	end

	describe("Upgrades_Freeze › affichage figé à l'ouverture (D7, D8)", function()
		it(
			"interrupteur des Gants ouvert écran ouvert : la ligne n'apparaît qu'à la réouverture",
			function()
				local off = flagsWith({ Gloves = false })
				local c = S.client({ snap = S.snap(1, nil, off) })
				S.open(c, "ranch")
				local gloves = c.Up._row("gloves")
				expect(gloves.Visible).toBe(false)
				local shown = c.Up._shown("ranch")
				expect(table.find(shown, "gloves")).toBe(nil)
				-- l'interrupteur s'ouvre (nouvel instantané) : rien ne bouge écran ouvert
				S.patch(c, S.snap(2))
				TvAudit.tick(c.h, 0.5)
				expect(gloves.Visible).toBe(false)
				expect(c.Up._shown("ranch")).toEqual(shown)
				-- réouverture : la ligne est là
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				S.open(c, "ranch")
				expect(gloves.Visible).toBe(true)
				expect(table.find(c.Up._shown("ranch"), "gloves") ~= nil).toBe(true)
				S.clean(c, expect)
			end
		)

		it("interrupteur coupé écran ouvert : la ligne reste montrée jusqu'à la fermeture", function()
			local c = S.client({ snap = S.snap(1) })
			S.open(c, "ranch")
			local gloves = c.Up._row("gloves")
			expect(gloves.Visible).toBe(true)
			local before = state(c, "gloves")
			S.patch(c, S.snap(2, nil, flagsWith({ Gloves = false })))
			TvAudit.tick(c.h, 0.5)
			expect(gloves.Visible).toBe(true)
			expect(state(c, "gloves")).toBe(before)
			c.PC.closeAll()
			TvAudit.tick(c.h, 1)
			S.open(c, "ranch")
			expect(gloves.Visible).toBe(false)
			S.clean(c, expect)
		end)

		it(
			"plafond de la boucle du Tapis Étoilé ouvert écran ouvert : « Boucle 6 » jusqu'à la réouverture",
			function()
				local function loop(r)
					return function(p)
						p.tiles.snack = 12
						p.tiles.star = 0
						p.R = r
						p.bestR = 15
						p.ascend = 1
					end
				end
				local c = S.client({ snap = S.snap(1, loop(3)) })
				S.open(c, "ranch")
				expect(state(c, "snack")).toBe("loopCap")
				-- la boucle 6 commence (r = 6 : Étoilé 1 ouvert) : l'écran ouvert garde « Boucle 6 »
				S.patch(c, S.snap(2, loop(6)))
				TvAudit.tick(c.h, 0.5)
				expect(state(c, "snack")).toBe("loopCap")
				c.PC.closeAll()
				TvAudit.tick(c.h, 1)
				S.open(c, "ranch")
				expect(state(c, "snack") ~= "loopCap").toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"pièces et niveaux suivent écran ouvert : Il manque → Prêt, sans changer l'ensemble des lignes",
			function()
				local function coins(n)
					return function(p)
						p.coins = n
					end
				end
				local c = S.client({ snap = S.snap(1, coins(0)) })
				S.open(c, "ranch")
				expect(state(c, "decor")).toBe("need")
				local shown = c.Up._shown("ranch")
				S.patch(c, S.snap(2, coins(1e30)))
				TvAudit.tick(c.h, 0.5)
				expect(state(c, "decor")).toBe("ready")
				expect(c.Up._shown("ranch")).toEqual(shown)
				S.clean(c, expect)
			end
		)
	end)
end
