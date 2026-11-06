--!nocheck
-- Upgrades_Feedback (lot B2, étape 3 ; docs/04 §27.8 règle 13, §27.10 ; GDD v2.0 §10.7.8, §10.8) :
-- « Jamais un achat muet » : chaque réponse du serveur à un achat de l'écran produit EXACTEMENT un retour
-- visible, dans la ligne ou la carte même, sauf le refus périmé (règle 12).
--   * « 1 réponse = 1 retour » (réponses fabriquées) : achat ×1 (« +1 niveau · -prix »), ×10 entier
--     (« +10 niveaux · -prix »), ×10 en partie (« n sur m »), chaque raison de refus du serveur (sa clé),
--     refus périmé muet, réponse d'un BuyTile (aucune ligne en attente) muette ; montant et niveaux DU
--     SERVEUR (spent, to − from), jamais un calcul du client ; son TileBuild et vibration tileBuy (refus :
--     Bump et refuse) ; aucun toast ; retour effacé après 1,5 s ; la carte garde sa famille et le focus
--     reste sur la ligne achetée, même à MAX ;
--   * interrupteur coupé : aucun écran, aucune intention, aucun retour ;
--   * Wire (UN cas, vrai serveur ; recette SchemaV2 de DataChaos) : chaque BuyUpgrade produit par le
--     client (vrais maintiens) reçoit un UpgradeResult du vrai serveur, et l'écran montre l'état du
--     serveur (niveaux de son instantané, un retour par réponse).
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")
local Bots = require("../harness/Bots")
local Wire = require("../harness/Wire")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local S = UpgradeScreen.new(T.Harness)

	local function rich(p)
		p.tiles.decor = 2
		p.tiles.gloves = 5
		p.tiles.pens = 14
		p.coins = 1e30
	end

	local function after(edit)
		return function(p)
			rich(p)
			edit(p)
		end
	end

	-- Sons, vibrations et toasts relevés
	local function record(c)
		local log = { sounds = {}, haptics = {}, toasts = 0 }
		local Audio = TvAudit.mod(c.h, "Controllers.AudioController")
		local Haptics = TvAudit.mod(c.h, "Util.Haptics")
		local Toast = TvAudit.mod(c.h, "UI.Toast")
		local play, buzz = Audio.play, Haptics.play
		Audio.play = function(name, ...)
			table.insert(log.sounds, name)
			return play(name, ...)
		end
		Haptics.play = function(name, ...)
			table.insert(log.haptics, name)
			return buzz(name, ...)
		end
		for _, fn in { "show", "push" } do
			local orig = Toast[fn]
			if type(orig) == "function" then
				Toast[fn] = function(...)
					log.toasts += 1
					return orig(...)
				end
			end
		end
		return log
	end

	local function count(list, name)
		local n = 0
		for _, x in list do
			if x == name then
				n += 1
			end
		end
		return n
	end

	local function buys(c)
		local out = {}
		for _, a in S.sent(c, "BuyUpgrade") do
			table.insert(out, { a[1], a[2], a[3] })
		end
		return out
	end

	local function textOf(c, label)
		return TvAudit.mod(c.h, "UI.Text").keyOf(label), label.Text
	end

	describe("Upgrades_Feedback › 1 réponse = 1 retour", function()
		it("interrupteur coupé : ni écran, ni intention, ni retour", function()
			local c = S.client({})
			c.PC.open("Upgrades", "ranch")
			TvAudit.tick(c.h, 0.5)
			expect(c.PC.isOpen("Upgrades")).toBe(false)
			-- une réponse égarée (sans écran) ne fait rien
			S.result(c, {
				id = "decor",
				from = 2,
				to = 3,
				spent = 10,
				currency = "coins",
				snapshot = S.snap(2, rich),
			})
			S.run(c, 2)
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it(
			"×1, ×10, ×10 en partie, chaque refus, périmé, BuyTile : un retour par réponse (sauf périmé et BuyTile)",
			function()
				local c = S.client({ snap = S.snap(1, rich), lang = "fr" })
				S.open(c, "ranch")
				local log = record(c)
				local BN = c.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
				local version = 1
				local function nextSnap(edit)
					version += 1
					return S.snap(version, after(edit))
				end
				local row = c.Up._row("decor")
				local effect = row:FindFirstChild("EffectLabel")
				local word = row:FindFirstChild("Word")
				-- ×1 : « +1 niveau · -prix » (montant du serveur, BigNumber)
				S.hold(c, row, 0.7)
				local sent = buys(c)
				expect(sent[#sent]).toEqual({ "decor", 1, 2 })
				S.answer(c, sent[#sent], {
					to = 3,
					spent = 123456,
					snap = nextSnap(function(p)
						p.tiles.decor = 3
					end),
				})
				local key, text = textOf(c, effect)
				expect(key).toBe("upgrades.boughtOne")
				expect(string.find(text, BN.abbreviate(123456, "fr"), 1, true) ~= nil).toBe(true)
				expect(#c.Up._feedbacks()).toBe(1)
				expect(count(log.sounds, "TileBuild")).toBe(1)
				expect(count(log.haptics, "tileBuy")).toBe(1)
				expect(S.selected(c)).toBe(row)
				-- le retour s'efface après 1,5 s
				S.run(c, 1.6)
				expect(textOf(c, effect) ~= "upgrades.boughtOne").toBe(true)
				-- ×10 entier puis ×10 en partie (« 4 sur 10 » dans le mot de l'état)
				c.Up._playerMode()
				expect(c.Up.mode()).toBe(10)
				S.run(c, 0.5)
				S.hold(c, nil, 0.7)
				sent = buys(c)
				expect(sent[#sent]).toEqual({ "decor", 10, 3 })
				S.answer(c, sent[#sent], {
					to = 13,
					spent = 5e9,
					snap = nextSnap(function(p)
						p.tiles.decor = 13
					end),
				})
				expect((textOf(c, effect))).toBe("upgrades.bought")
				expect(#c.Up._feedbacks()).toBe(2)
				S.run(c, 1.6)
				S.hold(c, nil, 0.7)
				sent = buys(c)
				expect(sent[#sent]).toEqual({ "decor", 10, 13 })
				S.answer(c, sent[#sent], {
					to = 17,
					spent = 7e9,
					snap = nextSnap(function(p)
						p.tiles.decor = 17
					end),
				})
				expect((textOf(c, effect))).toBe("upgrades.bought")
				expect((textOf(c, word))).toBe("upgrades.partial")
				expect(word.Text).toBe("4 sur 10")
				expect(#c.Up._feedbacks()).toBe(3)
				S.run(c, 1.6)
				expect((textOf(c, word)) ~= "upgrades.partial").toBe(true)
				-- chaque raison de refus : sa clé, dans la ligne (montant de l'instantané du serveur)
				c.Up._playerMode() -- Max
				c.Up._playerMode() -- ×1
				expect(c.Up.mode()).toBe(1)
				local reasons = { "coins", "confetti", "locked", "maxed", "loopCap", "busy" }
				for i, reason in reasons do
					S.run(c, 0.5)
					S.hold(c, nil, 0.7)
					sent = buys(c)
					expect(sent[#sent]).toEqual({ "decor", 1, 17 })
					S.answer(c, sent[#sent], {
						reason = "upgrades.refused." .. reason,
						snap = nextSnap(function(p)
							p.tiles.decor = 17
						end),
					})
					expect((textOf(c, effect))).toBe("upgrades.refused." .. reason)
					expect(#c.Up._feedbacks()).toBe(3 + i)
					S.run(c, 1.6)
				end
				expect(count(log.sounds, "TileBuild")).toBe(3)
				expect(count(log.haptics, "refuse")).toBe(#reasons)
				-- refus périmé : muet ; réponse d'un BuyTile (aucune ligne en attente) : muette
				S.hold(c, nil, 0.7)
				sent = buys(c)
				S.answer(c, sent[#sent], {
					from = 18,
					to = 18,
					snap = nextSnap(function(p)
						p.tiles.decor = 18
					end),
				})
				S.result(c, {
					id = "gloves",
					from = 5,
					to = 6,
					spent = 99,
					currency = "coins",
					snapshot = nextSnap(function(p)
						p.tiles.decor = 18
						p.tiles.gloves = 6
					end),
				})
				S.run(c, 0.2)
				expect(#c.Up._feedbacks()).toBe(3 + #reasons)
				expect(c.Up._pending()).toEqual({})
				-- la ligne est à MAX (Décorations 18/18) : le focus reste dessus
				expect(row:GetAttribute("State")).toBe("max")
				expect(S.selected(c)).toBe(row)
				-- les Gants suivent l'instantané du serveur (6), sans retour
				expect(c.Up._view(c.Up._row("gloves")).level).toBe(6)
				expect(log.toasts).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"carte du Conseillé : un retour dans la carte, qui garde sa famille ; focus en place, même à MAX",
			function()
				-- tout au maximum sauf les Gants (39/40), les Monuments et l'École : une carte « Gants »
				local function nearlyAll(p)
					rich(p)
					p.tiles.snack = 12
					p.tiles.star = 8
					p.tiles.decor = 18
					p.tiles.cozyBed = true
					p.tiles.gloves = 39
				end
				local c = S.client({ snap = S.snap(1, nearlyAll) })
				S.open(c, "suggested")
				local families = c.Up._cards()
				local i = table.find(families, "gloves")
				expect(i ~= nil).toBe(true)
				local card = c.Up._card(i)
				S.hold(c, card, 0.7)
				local sent = buys(c)
				expect(sent[1]).toEqual({ "gloves", 1, 39 })
				S.answer(c, sent[1], {
					to = 40,
					spent = 77,
					snap = S.snap(2, function(p)
						nearlyAll(p)
						p.tiles.gloves = 40
					end),
				})
				expect(#c.Up._feedbacks()).toBe(1)
				expect(c.Up._cards()).toEqual(families)
				expect(card:GetAttribute("FocusId")).toBe("gloves")
				expect(card:GetAttribute("State")).toBe("max")
				expect(S.selected(c)).toBe(card)
				-- l'avant → après reste montré pendant le retour (retour dans la zone du bas)
				S.clean(c, expect)
			end
		)
	end)

	-- -----------------------------------------------------------------------------------------
	-- Wire : vrai serveur (SchemaV2 ouvert dans le harnais avant le premier require du schéma)
	-- -----------------------------------------------------------------------------------------

	local L = "ReplicatedStorage.Shared."
	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })
	local FLAGS = { "UpgradesScreen", "Confetti", "Workshop", "StarMat", "Gloves", "Monuments", "RecordR" }

	local function bootServer()
		local caught = {}
		local w = Bots.boot(HarnessV2, {
			t0 = 1800000000,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				local F = w.h:require(L .. "Config.Features")
				for _, key in FLAGS do
					assert(F.set(key, true), key)
				end
				local d = Bots.profile(w, { onboarding = { step = 11, done = true, demoDone = true } })
				d.tiles.seen = 15
				d.coins = 1e14
				d.R = 6
				d.bestR = 24
				d.confetti = 100000
				d.confettiTotal = 100000
				d.unlocksSeen = 24
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught = caught
		return w
	end

	describe("Upgrades_Feedback › Wire (vrai serveur)", function()
		it(
			"chaque BuyUpgrade du client reçoit un UpgradeResult ; l'écran montre l'état du serveur",
			function()
				local w = bootServer()
				local p = Bots.join(1)
				w.h:settle(3)
				local arrival = w.h:sentTo(p, "DataSnapshot")[1][1].upgradeSnapshot
				expect(type(arrival)).toBe("table")
				local serverCtx = Wire.saveContext()
				-- client console avec l'instantané d'arrivée du VRAI serveur
				local c = S.client({ snap = arrival })
				local clientCtx = Wire.saveContext()
				S.open(c, "ranch")
				-- vrais maintiens : Décorations ×1, Gants ×10, Enclos ×1 (refus ou achat : le serveur dit)
				S.hold(c, c.Up._row("decor"), 0.7)
				c.Up._playerMode()
				S.run(c, 0.5)
				S.hold(c, c.Up._row("gloves"), 0.7)
				c.Up._playerMode()
				c.Up._playerMode()
				S.run(c, 0.5)
				S.hold(c, c.Up._row("pens"), 0.7)
				local sent = S.sent(c, "BuyUpgrade")
				expect(#sent >= 2).toBe(true)
				-- au serveur
				Wire.restoreContext(serverCtx)
				local base = #w.h:sentTo(p, "UpgradeResult")
				for _, args in sent do
					w.h:fireServer("ReplicatedStorage.Remotes.BuyUpgrade", p, args[1], args[2], args[3])
					w.h:settle(2)
				end
				local results = {}
				for i = base + 1, #w.h:sentTo(p, "UpgradeResult") do
					table.insert(results, w.h:sentTo(p, "UpgradeResult")[i][1])
				end
				expect(#results).toBe(#sent)
				for i, r in results do
					expect(r.id).toBe(sent[i][1])
					expect(r.from).toBe(sent[i][3])
				end
				expect(table.concat(w.caught, "\n")).toBe("")
				expect(table.concat(w.h.errors, "\n")).toBe("")
				-- au client : chaque réponse, telle que le serveur l'a envoyée
				Wire.restoreContext(clientCtx)
				for _, r in results do
					S.result(c, r)
				end
				local last = results[#results].snapshot
				expect(c.US.current().version).toBe(last.version)
				-- l'écran montre l'état du serveur : niveaux de son instantané
				for _, id in { "decor", "gloves" } do
					local view = c.Up._view(c.Up._row(id))
					expect(view.level).toBe(last.levels[id])
				end
				-- un retour par réponse qui n'est pas un refus périmé
				local expected = 0
				for _, r in results do
					if not (r.reason == nil and r.to == r.from) then
						expected += 1
					end
				end
				expect(#c.Up._feedbacks()).toBe(expected)
				expect(c.Up._pending()).toEqual({})
				S.clean(c, expect)
			end
		)
	end)
end
