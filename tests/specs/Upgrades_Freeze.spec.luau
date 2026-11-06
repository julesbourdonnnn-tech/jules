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
-- Partie ACHATS (étape 3 ; décisions D7 et D28) :
--   * une ligne coupée en direct par le serveur reste montrée ouverte : son achat reçoit le refus du
--     serveur, MONTRÉ avec sa raison (jamais muet) ;
--   * « Grand Splorch écran ouvert : fermeture, puis réouverture à l'état neuf » : au début de SON
--     Grand Splorch ou de SA Jelly Ascend (Celebrate ou EventState.spectacle.current), l'écran se
--     ferme ; celui d'un autre joueur ne ferme rien ; la réouverture remet le mode à ×1, l'onglet
--     d'office, les cartes du Conseillé et les achats en cours à neuf.
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

	describe("Upgrades_Freeze › achats et prestige (D7, D28)", function()
		local function rich(p)
			p.tiles.gloves = 5
			p.coins = 1e30
		end

		it("ligne coupée en direct : l'achat reçoit le refus du serveur, montré avec sa raison", function()
			local c = S.client({ snap = S.snap(1, rich) })
			S.open(c, "ranch")
			local gloves = c.Up._row("gloves")
			expect(state(c, "gloves")).toBe("ready")
			-- l'interrupteur des Gants se coupe écran ouvert : la ligne reste montrée, Prête
			S.patch(c, S.snap(2, rich, flagsWith({ Gloves = false })))
			TvAudit.tick(c.h, 0.5)
			expect(gloves.Visible).toBe(true)
			expect(state(c, "gloves")).toBe("ready")
			S.hold(c, gloves, 0.7)
			local sent = S.sent(c, "BuyUpgrade")
			expect(#sent).toBe(1)
			S.answer(c, sent[1], {
				reason = "upgrades.refused.locked",
				snap = S.snap(3, rich, flagsWith({ Gloves = false })),
			})
			local fb = c.Up._feedbacks()
			expect(#fb).toBe(1)
			expect(fb[1]).toEqual({ id = "gloves", key = "upgrades.refused.locked" })
			expect(TvAudit.mod(c.h, "UI.Text").keyOf(gloves:FindFirstChild("EffectLabel"))).toBe(
				"upgrades.refused.locked"
			)
			expect(c.Up._pending()).toEqual({})
			S.clean(c, expect)
		end)

		local function celebrate(c, kind, userId, startedAt)
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = kind,
				data = {
					userId = userId,
					startedAt = startedAt,
					burstAt = startedAt + 4,
					endsAt = startedAt + 10,
				},
			})
			c.h:settle(1)
		end

		local function eventState(c, current)
			local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
			WSC.EventChanged:Fire({ spectacle = { current = current, queue = {} } })
			c.h:settle(1)
		end

		it("Grand Splorch écran ouvert : fermeture, puis réouverture à l'état neuf", function()
			local c = S.client({ snap = S.snap(1, rich) })
			local me = c.h.localPlayer.UserId
			S.open(c, "ranch")
			c.Up._playerMode()
			expect(c.Up.mode()).toBe(10)
			S.hold(c, c.Up._row("gloves"), 0.7)
			expect(c.Up._pending()).toEqual({ "gloves" })
			-- le Grand Splorch d'un AUTRE joueur ne ferme rien
			local now = c.Clock.now()
			celebrate(c, "splorch", me + 1, now)
			eventState(c, { kind = "splorch", userId = me + 1, startedAt = now })
			expect(c.PC.isOpen("Upgrades")).toBe(true)
			-- le MIEN : l'écran se ferme au début du spectacle
			celebrate(c, "splorch", me, now + 1)
			TvAudit.tick(c.h, 0.5)
			expect(c.PC.isOpen("Upgrades")).toBe(false)
			expect(c.PC.menuOpen()).toBe(false)
			-- le même spectacle annoncé encore (EventState) : rien de plus ; rouvert pendant le spectacle,
			-- l'écran reste ouvert
			S.open(c, "ranch")
			eventState(c, { kind = "splorch", userId = me, startedAt = now + 1 })
			expect(c.PC.isOpen("Upgrades")).toBe(true)
			-- réouverture neuve : mode ×1, aucun achat en cours
			expect(c.Up.mode()).toBe(1)
			expect(c.Up._pending()).toEqual({})
			expect(c.Up._row("gloves"):GetAttribute("State")).toBe("ready")
			S.clean(c, expect)
		end)

		it(
			"Jelly Ascend (EventState.spectacle.current, sorte ascend) : fermeture ; un Petit Splorch ne ferme rien",
			function()
				local c = S.client({ snap = S.snap(1, rich) })
				local me = c.h.localPlayer.UserId
				S.open(c, "suggested")
				local now = c.Clock.now()
				celebrate(c, "petitSplorch", me, now)
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				eventState(c, { kind = "dance", userId = 0, startedAt = now })
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				eventState(c, { kind = "ascend", userId = me, startedAt = now + 2 })
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				-- charges abîmées : ignorées sans trace
				for _, bad in
					{
						1,
						"x",
						{ kind = "ascend" },
						{ kind = "ascend", data = { userId = me, startedAt = 0 / 0 } },
					}
				do
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", bad)
				end
				c.h:settle(1)
				S.clean(c, expect)
			end
		)

		it(
			"interrupteur coupé : Celebrate et EventState de mon Grand Splorch ne font rien de plus qu'avant",
			function()
				local c = S.client({})
				local me = c.h.localPlayer.UserId
				local now = c.Clock.now()
				celebrate(c, "splorch", me, now)
				eventState(c, { kind = "splorch", userId = me, startedAt = now })
				expect(c.PC.window("Upgrades")).toBeNil()
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
