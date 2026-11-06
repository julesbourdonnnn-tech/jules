--!nocheck
-- Upgrades_Pending (lot B2, étape 3 ; docs/04 §27.8 règle 12, §27.10 ; GDD v2.0 §10.7.6, §10.8 ;
-- décisions D9 et D10 du plan B2) : état « en cours » de 3 s par ligne.
-- Partie MODULE (Hud/UpgradeBuys, pur : horloge et envoi injectés) :
--   * jamais une intention invalide (identifiant inconnu ou non canonique, mode hors de { 1, 10, 0 },
--     niveau attendu illisible) ; une ligne « en cours » ignore les appuis ; « Réessaie » après 3 s,
--     renvoi par le même geste ; une métrique upgradeTimeout par délai dépassé ;
--   * réponse tardive : exactement un retour ; refus périmé (reason nil, from == to) muet ; réponse sans
--     ligne en attente (BuyTile, achat au sol) : rien ; ×10 en partie : « n sur m » ;
--   * limiteur de ClientMetric : 1 envoi au plus toutes les 5 s, dernier mode fondu, délai d'abord, 20
--     au plus par séance, envoi refusé par le débit gardé en file ; horloge recalée en arrière.
-- Partie ÉCRAN (vrai client console, instantanés et réponses fabriqués, vrais maintiens) :
--   * « serveur muet : retour en 3 s, focus intact » ;
--   * « réponse à 3,5 s puis nouvel appui : exactement un retour +n niveaux » (le renvoi de « Réessaie »
--     part avec le MÊME niveau attendu : la seconde réponse est un refus périmé, muet) ;
--   * interrupteur coupé (aucun instantané) : aucune intention v2.0.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local S = UpgradeScreen.new(T.Harness)

	-- -----------------------------------------------------------------------------------------
	-- Module pur
	-- -----------------------------------------------------------------------------------------

	local mh = Harness.new({ mode = "client" })
	local UpgradeBuys = mh:require(TvAudit.CLIENT .. "UI.Hud.UpgradeBuys")
	local UM = S.UpgradeMath

	local function fake(opts)
		opts = opts or {}
		local f = { t = 1000, sent = {}, refuse = false }
		f.buys = UpgradeBuys.new({
			now = function()
				return f.t
			end,
			send = function(name, ...)
				if f.refuse then
					return false
				end
				table.insert(f.sent, { name, ... })
				return true
			end,
		})
		return f
	end

	local function count(f, name, kind)
		local n = 0
		for _, e in f.sent do
			if e[1] == name and (kind == nil or e[2] == kind) then
				n += 1
			end
		end
		return n
	end

	local snap = S.snap(1)

	local function payload(id, from, to, extra)
		local p = {
			id = id,
			from = from,
			to = to,
			spent = if to > from then 1234 else 0,
			currency = UM.currency(id),
			reason = nil,
			snapshot = snap,
		}
		for k, v in extra or {} do
			p[k] = v
		end
		return p
	end

	describe("Upgrades_Pending › Hud/UpgradeBuys (module pur)", function()
		it("intentions invalides : rien n'est envoyé, aucune ligne en attente", function()
			local f = fake()
			local bad = {
				{ "nope", 1, 0 },
				{ "palettes", 1, 0 }, -- id nu d'une ligne « Pour le plaisir » : jamais envoyé (canonique fun.<id>)
				{ "", 1, 0 },
				{ string.rep("a", 25), 1, 0 },
				{ 12, 1, 0 },
				{ "gloves", 2, 0 },
				{ "gloves", 5, 0 },
				{ "gloves", -1, 0 },
				{ "gloves", 0.5, 0 },
				{ "gloves", 0 / 0, 0 },
				{ "gloves", "1", 0 },
				{ "gloves", 1, -1 },
				{ "gloves", 1, 1.5 },
				{ "gloves", 1, 0 / 0 },
				{ "gloves", 1, math.huge },
				{ "gloves", 1, UM.maxLevel("gloves") + 1 },
				{ "gloves", 1, "3" },
				{ "gloves", 1, nil },
			}
			for _, a in bad do
				expect(f.buys:buy(a[1], a[2], a[3])).toBe(false)
			end
			expect(#f.sent).toBe(0)
			expect(f.buys:pendingIds()).toEqual({})
			-- les trois modes et le niveau maximal attendu passent
			for _, m in { 1, 10, 0 } do
				local ff = fake()
				expect(ff.buys:buy("gloves", m, UM.maxLevel("gloves"))).toBe(true)
				expect(ff.sent[1]).toEqual({ "BuyUpgrade", "gloves", m, UM.maxLevel("gloves") })
			end
			expect(fake().buys:buy("fun.palettes", 1, 0)).toBe(true)
		end)

		it(
			"« en cours » 3 s (appuis ignorés), puis « Réessaie » et une métrique upgradeTimeout ; renvoi",
			function()
				local f = fake()
				expect(f.buys:buy("decor", 1, 9)).toBe(true)
				expect(f.buys:state("decor")).toBe("busy")
				f.t += 1
				expect(f.buys:buy("decor", 1, 9)).toBe(false)
				expect(count(f, "BuyUpgrade")).toBe(1)
				f.t += 1.9
				expect(f.buys:step()).toEqual({})
				expect(f.buys:state("decor")).toBe("busy")
				f.t += 0.1
				expect(f.buys:step()).toEqual({ "decor" })
				expect(f.buys:state("decor")).toBe("retry")
				expect(count(f, "ClientMetric", "upgradeTimeout")).toBe(1)
				-- le délai ne compte qu'une fois
				f.t += 10
				expect(f.buys:step()).toEqual({})
				expect(count(f, "ClientMetric", "upgradeTimeout")).toBe(1)
				-- « Réessaie » : le même geste renvoie (même niveau attendu : le serveur jugera)
				expect(f.buys:buy("decor", 1, 9)).toBe(true)
				expect(count(f, "BuyUpgrade")).toBe(2)
				expect(f.buys:state("decor")).toBe("busy")
			end
		)

		it(
			"réponse tardive : un seul retour ; refus périmé muet ; réponse sans ligne en attente : rien",
			function()
				local f = fake()
				-- réponse d'un BuyTile ou de l'achat au sol : aucune ligne en attente
				expect(f.buys:result(payload("decor", 9, 10)).kind).toBe("none")
				f.buys:buy("decor", 1, 9)
				f.t += 3.2
				f.buys:step()
				-- renvoi à 3,2 s (« Réessaie »), même niveau attendu
				expect(f.buys:buy("decor", 1, 9)).toBe(true)
				f.t += 0.3
				local first = f.buys:result(payload("decor", 9, 10))
				expect(first.kind).toBe("bought")
				expect(first.levels).toBe(1)
				expect(first.spent).toBe(1234)
				-- la seconde demande attend encore
				expect(f.buys:state("decor") ~= nil).toBe(true)
				-- sa réponse : refus périmé (niveau attendu dépassé), muet ; la ligne quitte l'attente
				local second = f.buys:result(payload("decor", 10, 10))
				expect(second.kind).toBe("none")
				expect(f.buys:state("decor")).toBeNil()
				-- un refus du serveur est montré avec sa raison
				f.buys:buy("gloves", 1, 0)
				local refused = f.buys:result(payload("gloves", 0, 0, { reason = "upgrades.refused.coins" }))
				expect(refused.kind).toBe("refused")
				expect(refused.reason).toBe("upgrades.refused.coins")
				expect(f.buys:state("gloves")).toBeNil()
			end
		)

		it("×10 en partie : « n sur m » ; ×10 entier, ×1 et Max : jamais partiels", function()
			local f = fake()
			f.buys:buy("gloves", 10, 0)
			local partial = f.buys:result(payload("gloves", 0, 4))
			expect({ partial.kind, partial.levels, partial.requested, partial.partial }).toEqual({
				"bought",
				4,
				10,
				true,
			})
			f.buys:buy("gloves", 10, 4)
			local whole = f.buys:result(payload("gloves", 4, 14))
			expect(whole.partial).toBe(false)
			f.buys:buy("gloves", 0, 14)
			local max = f.buys:result(payload("gloves", 14, 17))
			expect({ max.partial, max.requested }).toEqual({ false, nil })
			f.buys:buy("gloves", 1, 17)
			local one = f.buys:result(payload("gloves", 17, 18))
			expect({ one.levels, one.partial, one.requested }).toEqual({ 1, false, 1 })
		end)

		it(
			"limiteur : 1 / 5 s, dernier mode fondu, délai d'abord, 20 par séance, envoi refusé gardé",
			function()
				local f = fake()
				f.buys:metric("upgradeMode", 10)
				expect(count(f, "ClientMetric")).toBe(1)
				expect(f.sent[1]).toEqual({ "ClientMetric", "upgradeMode", 10 })
				-- trois changements rapprochés : seul le dernier part, après 5 s
				f.t += 1
				f.buys:metric("upgradeMode", 0)
				f.buys:metric("upgradeMode", 1)
				f.buys:metric("upgradeMode", 10)
				-- mode invalide ou sorte inconnue : ignorés
				f.buys:metric("upgradeMode", 3)
				f.buys:metric("nope", 1)
				f.t += 3
				f.buys:step()
				expect(count(f, "ClientMetric")).toBe(1)
				-- un délai dépassé arrive : il part AVANT le mode en file
				f.buys:buy("decor", 1, 9)
				f.t += 3.1
				f.buys:step()
				expect(f.sent[#f.sent][2]).toBe("upgradeTimeout")
				expect(count(f, "ClientMetric")).toBe(2)
				f.t += 5
				f.buys:step()
				expect(f.sent[#f.sent]).toEqual({ "ClientMetric", "upgradeMode", 10 })
				expect(f.buys:busy()).toBe(true) -- l'achat de decor attend encore sa réponse
				-- envoi refusé par le débit du client : reste en file, part au tour suivant
				f.refuse = true
				f.t += 6
				f.buys:metric("upgradeMode", 0)
				f.refuse = false
				expect(count(f, "ClientMetric")).toBe(3)
				f.buys:step()
				expect(count(f, "ClientMetric")).toBe(4)
				-- 20 au plus par séance (le serveur n'en compte pas plus)
				for i = 1, 40 do
					f.t += 6
					f.buys:metric("upgradeMode", if i % 2 == 0 then 1 else 10)
					f.buys:step()
				end
				expect(count(f, "ClientMetric")).toBe(20)
				expect(f.buys:metricsSent()).toBe(20)
			end
		)

		it(
			"horloge recalée en arrière : la ligne passe à « Réessaie », jamais bloquée « en cours »",
			function()
				local f = fake()
				f.buys:buy("decor", 1, 9)
				f.t -= 100
				expect(f.buys:state("decor")).toBe("retry")
				expect(f.buys:step()).toEqual({ "decor" })
				expect(f.buys:buy("decor", 1, 9)).toBe(true)
				-- fermeture de l'écran : attentes oubliées, le limiteur garde sa file
				f.buys:clear()
				expect(f.buys:pendingIds()).toEqual({})
				expect(f.buys:result(payload("decor", 9, 10)).kind).toBe("none")
			end
		)
	end)

	-- -----------------------------------------------------------------------------------------
	-- Écran
	-- -----------------------------------------------------------------------------------------

	local function ready(p)
		p.tiles.decor = 9
		p.coins = 1e30
	end

	local function rowState(c, id)
		return c.Up._row(id):GetAttribute("State")
	end

	-- intentions BuyUpgrade envoyées : { id, mode, niveau attendu }
	local function buys(c)
		local out = {}
		for _, a in S.sent(c, "BuyUpgrade") do
			table.insert(out, { a[1], a[2], a[3] })
		end
		return out
	end

	local function metrics(c)
		local out = {}
		for _, a in S.sent(c, "ClientMetric") do
			table.insert(out, { a[1], a[2] })
		end
		return out
	end

	describe("Upgrades_Pending › écran (vrai client, vrais maintiens)", function()
		it("interrupteur coupé : aucune intention v2.0, même après des appuis tenus", function()
			local c = S.client({})
			expect(c.PC.available("Upgrades")).toBe(false)
			TvAudit.openMenu(c.h)
			S.run(c, 0.5)
			S.hold(c, nil, 1)
			S.run(c, 4)
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("serveur muet : retour en 3 s, focus intact", function()
			local c = S.client({ snap = S.snap(1, ready) })
			S.open(c, "ranch")
			local row = c.Up._row("decor")
			expect(rowState(c, "decor")).toBe("ready")
			S.hold(c, row, 0.7)
			local sent = buys(c)
			expect(#sent).toBe(1)
			expect(sent[1]).toEqual({ "decor", 1, 9 })
			expect(rowState(c, "decor")).toBe("busy")
			expect(c.Up._pending()).toEqual({ "decor" })
			-- appuis ignorés pendant « En cours »
			S.hold(c, nil, 0.7)
			expect(#buys(c)).toBe(1)
			S.run(c, 1.2) -- ≈ 2,2 s depuis l'envoi
			expect(rowState(c, "decor")).toBe("busy")
			S.run(c, 1)
			expect(rowState(c, "decor")).toBe("retry")
			expect(S.selected(c)).toBe(row)
			expect(c.h.game.GuiService.SelectedObject).toBe(row)
			expect(metrics(c)).toEqual({ { "upgradeTimeout", 0 } })
			-- le bandeau dit la consigne du maintien, glyphe de l'appareil dessiné
			expect(TvAudit.mod(c.h, "UI.Text").keyOf(c.Up._banner())).toBe("upgrades.detail.hold")
			expect(c.Up._holdGlyph().Visible).toBe(true)
			expect(#c.Up._feedbacks()).toBe(0)
			S.clean(c, expect)
		end)

		it("réponse à 3,5 s puis nouvel appui : exactement un retour +n niveaux", function()
			local c = S.client({ snap = S.snap(1, ready) })
			S.open(c, "ranch")
			local row = c.Up._row("decor")
			S.hold(c, row, 0.7)
			S.run(c, 3)
			expect(rowState(c, "decor")).toBe("retry")
			-- « Réessaie » : le même maintien renvoie, avec le MÊME niveau attendu
			S.hold(c, nil, 0.7)
			local sent = buys(c)
			expect(#sent).toBe(2)
			expect(sent[2]).toEqual({ "decor", 1, 9 })
			-- la première réponse arrive (tard) : un retour « +1 niveau »
			local after = S.snap(2, function(p)
				ready(p)
				p.tiles.decor = 10
			end)
			S.answer(c, sent[1], { to = 10, spent = 5000, snap = after })
			local fb = c.Up._feedbacks()
			expect(#fb).toBe(1)
			expect(fb[1]).toEqual({ id = "decor", key = "upgrades.boughtOne" })
			-- la réponse au renvoi : refus périmé (le niveau 9 est dépassé), muet
			S.answer(c, sent[2], {
				from = 10,
				to = 10,
				snap = S.snap(3, function(p)
					ready(p)
					p.tiles.decor = 10
				end),
			})
			expect(#c.Up._feedbacks()).toBe(1)
			expect(c.Up._pending()).toEqual({})
			expect(rowState(c, "decor")).toBe("ready")
			-- nouvel appui : le niveau suivant (jamais deux fois le même)
			S.run(c, 1.6)
			S.hold(c, nil, 0.7)
			sent = buys(c)
			expect(#sent).toBe(3)
			expect(sent[3]).toEqual({ "decor", 1, 10 })
			expect(S.selected(c)).toBe(row)
			S.clean(c, expect)
		end)
	end)
end
