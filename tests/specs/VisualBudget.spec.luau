--!nocheck
-- VisualBudget (lot B4, étape 3 ; docs/04 §27.7 ; GDD v2.0 §11.5 « Budget visuel en direct », §12.9 ;
-- décision D13 du plan B4) : grand livre des décors v2.0 du client.
--   * declare / take / release / used / stats : l'usage ne dépasse jamais ce qui est déclaré (suite
--     tirée au hasard, graine fixe), une redéclaration garde l'usage, jamais sous 0 ;
--   * ordre de dégradation : mon ranch, le ranch courant, ses 2 voisins, puis du plus proche au plus
--     lointain ; allocate dégrade les plus lointains d'abord (complet → réduit → rien, jamais mieux
--     après une dégradation), mon ranch en dernier ;
--   * métrique : ClientMetric("visualBudget", n) au plus une fois par 60 s et 5 fois par séance, n borné
--     à 1 … 1000, envoi refusé par le seau non compté ; rien n'est déclaré interrupteurs coupés : aucun
--     envoi ; vrai chemin par Widgets.send (seau partagé) sur un vrai client ;
--   * entrées hostiles : aucune erreur, aucune trace.
local TvAudit = require("../harness/TvAudit")

local PATH = "StarterPlayer.StarterPlayerScripts.Client.Render.VisualBudget"

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Module neuf sur un client léger, horloge et envoi remplacés (intentions comptées)
	local function fresh()
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local VB = h:require(PATH)
		VB._reset()
		local f = { h = h, VB = VB, t = 1000, sent = {}, accept = true }
		VB._configure({
			now = function()
				return f.t
			end,
			send = function(name, kind, value)
				if not f.accept then
					return false
				end
				table.insert(f.sent, { name, kind, value })
				return true
			end,
		})
		function f.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return f
	end

	describe("VisualBudget › déclarer, réserver, rendre", function()
		it("take dans le budget, refus au-delà sans rien réserver, release jamais sous 0", function()
			local f = fresh()
			local VB = f.VB
			expect(VB.declared("tapis")).toBe(false)
			expect(VB.take("tapis", 1)).toBe(false) -- pas déclaré
			expect(VB.declare("tapis", VB.LIMITS.tapis)).toBe(true)
			expect(VB.declared("tapis")).toBe(true)
			expect(VB.take("tapis", 100)).toBe(true)
			expect(VB.take("tapis", 62)).toBe(true)
			expect(VB.used("tapis")).toBe(162)
			expect(VB.take("tapis", 1)).toBe(false)
			expect(VB.used("tapis")).toBe(162)
			expect(VB.take("tapis", 0)).toBe(true)
			VB.release("tapis", 50)
			expect(VB.used("tapis")).toBe(112)
			VB.release("tapis", 500)
			expect(VB.used("tapis")).toBe(0)
			-- particules et lumières : comptes à part
			expect(VB.take("tapis", 6, "particles")).toBe(true)
			expect(VB.take("tapis", 1, "particles")).toBe(false)
			expect(VB.take("tapis", 1, "lights")).toBe(false) -- 0 lumière de plus (§12.9)
			expect(VB.used("tapis", "particles")).toBe(6)
			expect(VB.used("tapis")).toBe(0)
			local st = VB.stats().tapis
			expect(st.parts).toBe(162)
			expect(st.particles).toBe(6)
			expect(st.lights).toBe(0)
			expect(st.peak).toBe(162)
			expect(st.refused).toBe(3)
			expect(VB.exceeded()).toBe(3)
			f.clean()
		end)

		it("les budgets sont ceux du GDD §11.5 (pièces, 0 lumière de plus)", function()
			local f = fresh()
			local L = f.VB.LIMITS
			expect(L.tapis.parts).toBe((20 + 24 + 10) * 3)
			expect(L.record.parts).toBe(40 * 3)
			expect(L.tiers.parts).toBe(3 * 96 + 13 * 9)
			expect(L.plinths.parts).toBe(18 * 2 * 3)
			expect(L.monuments.parts).toBe(200 + 120 + 130)
			expect(L.sky.parts).toBe(80 + 2 * 10 + 13 * 3)
			expect(L.decoPerso.parts).toBe(3 * 120 + 13 * 4)
			-- lot B4, étape 5 (B4-55) : halo à part du ciel (5 gouttes × 16 joueurs, il suit le personnage)
			-- et Prairie v2 (40, elle remplace la Prairie du serveur cachée sur ce client)
			expect(L.halo.parts).toBe(16 * 5)
			expect(L.meadow.parts).toBe(40)
			local total = 0
			for _, l in L do
				expect(l.lights).toBe(0)
				total += l.parts
			end
			-- ≈ 2 040 pièces du GDD (+ 20 pour le tas et l'anneau du Pot de MON ranch, D18 ; + 80 du halo et
			-- 40 de la Prairie v2, B4-55)
			expect(total <= 2040 + 20 + 80 + 40).toBe(true)
			f.clean()
		end)

		it(
			"suite au hasard (graine fixe) : l'usage reste égal au modèle et jamais au-delà du budget",
			function()
				local f = fresh()
				local VB = f.VB
				VB.declare("record", { parts = 120, particles = 3, lights = 0 })
				-- hasard contrôlé (Hash.stream, xorshift32 à graine fixe)
				local rng = f.h:require("ReplicatedStorage.Shared.Logic.Hash").stream(4242)
				local model = { parts = 0, particles = 0 }
				local limit = { parts = 120, particles = 3 }
				for _ = 1, 5000 do
					local kind = if rng:int(1, 4) == 1 then "particles" else "parts"
					local n = rng:int(0, 30)
					if rng:next() < 0.6 then
						local ok = VB.take("record", n, kind)
						expect(ok).toBe(model[kind] + n <= limit[kind])
						if ok then
							model[kind] += n
						end
					else
						VB.release("record", n, kind)
						model[kind] = math.max(0, model[kind] - n)
					end
					expect(VB.used("record", kind)).toBe(model[kind])
					expect(VB.used("record", kind) <= limit[kind]).toBe(true)
				end
				-- redéclaration plus petite : l'usage reste, plus aucune réservation tant qu'il dépasse
				VB.release("record", 1000)
				expect(VB.take("record", 100)).toBe(true)
				VB.declare("record", { parts = 50 })
				expect(VB.used("record")).toBe(100)
				expect(VB.take("record", 1)).toBe(false)
				VB.release("record", 60)
				expect(VB.take("record", 10)).toBe(true)
				expect(VB.used("record")).toBe(50)
				f.clean()
			end
		)
	end)

	describe("VisualBudget › ordre de dégradation", function()
		it("order : mon ranch, le courant, ses voisins, puis du plus proche au plus lointain", function()
			local f = fresh()
			local VB = f.VB
			expect(VB.order(3, 3)).toEqual({ 3, 4, 2, 5, 1, 6, 16, 7, 15, 8, 14, 9, 13, 10, 12, 11 })
			expect(VB.order(3, 7)).toEqual({ 3, 7, 8, 6, 9, 5, 10, 4, 11, 12, 2, 13, 1, 14, 16, 15 })
			expect(VB.order(16, 1)).toEqual({ 16, 1, 2, 3, 15, 4, 14, 5, 13, 6, 12, 7, 11, 8, 10, 9 })
			-- sans ranch (visiteur) : le courant d'abord ; tout illisible : depuis le ranch 1
			expect(VB.order(nil, 5)[1]).toBe(5)
			expect(#VB.order(0 / 0, "x")).toBe(16)
			expect(VB.order(0 / 0, "x")[1]).toBe(1)
			f.clean()
		end)

		it("allocate : 3 ranchs complets dans 162 pièces, les autres réduits ; le mien d'abord", function()
			local f = fresh()
			local VB = f.VB
			VB.declare("tapis", VB.LIMITS.tapis)
			local wants = {}
			for slot = 1, 16 do
				-- ranch courant (7) et voisins : complet 54 ; les autres : couleur seulement (0)
				local full = if slot >= 6 and slot <= 8 then 54 else 0
				wants[slot] = { full = full, reduced = 0 }
			end
			local levels = VB.allocate("tapis", VB.order(3, 7), wants)
			for slot = 1, 16 do
				expect(levels[slot]).toBe("full")
			end
			expect(VB.used("tapis")).toBe(162)
			expect(VB.exceeded()).toBe(0)
			-- mon ranch (3) veut aussi 54 : il passe avant, le voisin le plus lointain dans l'ordre
			-- (6, après 8) descend en réduit, et tout ce qui suit ne reçoit pas mieux
			wants[3] = { full = 54, reduced = 0 }
			levels = VB.allocate("tapis", VB.order(3, 7), wants)
			expect(levels[3]).toBe("full")
			expect(levels[7]).toBe("full")
			expect(levels[8]).toBe("full")
			expect(levels[6]).toBe("reduced")
			expect(VB.used("tapis")).toBe(162)
			expect(VB.exceeded()).toBe(1)
			f.clean()
		end)

		it("budget court : niveaux monotones le long de l'ordre, les plus lointains à rien", function()
			local f = fresh()
			local VB = f.VB
			VB.declare("tiers", { parts = 120 })
			local wants = {}
			for slot = 1, 16 do
				wants[slot] = { full = 30, reduced = 9 }
			end
			local order = VB.order(10, 2)
			local levels = VB.allocate("tiers", order, wants)
			local rank = { full = 2, reduced = 1, none = 0 }
			local prev = 2
			for _, slot in order do
				local r = rank[levels[slot]]
				expect(r <= prev).toBe(true)
				prev = r
			end
			expect(levels[10]).toBe("full") -- mon ranch, même loin du ranch courant
			expect(levels[order[16]]).toBe("none")
			expect(VB.used("tiers") <= 120).toBe(true)
			-- une nouvelle répartition remplace l'ancienne (idempotente)
			local again = VB.allocate("tiers", order, wants)
			expect(again).toEqual(levels)
			expect(VB.used("tiers") <= 120).toBe(true)
			f.clean()
		end)
	end)

	describe("VisualBudget › métrique de dépassement", function()
		it("au plus 1 envoi par 60 s et 5 par séance, n borné à 1 … 1000", function()
			local f = fresh()
			local VB = f.VB
			VB.declare("pot", VB.LIMITS.pot)
			expect(VB.take("pot", 20)).toBe(true)
			expect(VB.take("pot", 5000)).toBe(false)
			expect(#f.sent).toBe(1)
			expect(f.sent[1]).toEqual({ "ClientMetric", "visualBudget", 1000 })
			-- dépassements rapprochés : rien de plus avant 60 s
			for _ = 1, 20 do
				f.t += 2
				VB.take("pot", 1)
			end
			expect(#f.sent).toBe(1)
			f.t = 1060
			VB.take("pot", 3)
			expect(#f.sent).toBe(2)
			expect(f.sent[2][3]).toBe(3)
			for i = 3, 9 do
				f.t = 1000 + 60 * i
				VB.take("pot", 1)
			end
			expect(#f.sent).toBe(5)
			expect(VB.metricsSent()).toBe(5)
			expect(VB.exceeded()).toBe(29)
			f.clean()
		end)

		it("envoi refusé par le seau : pas compté, le dépassement suivant réessaie", function()
			local f = fresh()
			local VB = f.VB
			VB.declare("pot", { parts = 0 })
			f.accept = false
			VB.take("pot", 2)
			expect(VB.metricsSent()).toBe(0)
			f.accept = true
			f.t += 1
			VB.take("pot", 2)
			expect(#f.sent).toBe(1)
			expect(f.sent[1][3]).toBe(2)
			f.clean()
		end)

		it("interrupteurs coupés (rien de déclaré) : aucune intention, quoi qu'on demande", function()
			local f = fresh()
			local VB = f.VB
			for _, name in { "tapis", "record", "tiers", "plinths", "pot", "nope" } do
				expect(VB.take(name, 1e4)).toBe(false)
				expect(VB.allocate(name, VB.order(1, 1), { [1] = { full = 1e4, reduced = 1e4 } })).toEqual({})
			end
			expect(#f.sent).toBe(0)
			expect(VB.exceeded()).toBe(0)
			expect(next(VB.stats())).toBe(nil)
			f.clean()
		end)

		it("vrai client : ClientMetric part par Widgets.send (seau partagé de 1 / 5 s)", function()
			local h = TvAudit.client()
			local VB = h:require(PATH)
			VB._reset()
			VB._configure(nil)
			local Widgets = TvAudit.mod(h, "UI.Panels.Widgets")
			Widgets._resetBuckets()
			local before = #TvAudit.sent(h, "ClientMetric")
			VB.declare("world", VB.LIMITS.world)
			expect(VB.take("world", 41)).toBe(false)
			local sent = TvAudit.sent(h, "ClientMetric")
			expect(#sent).toBe(before + 1)
			expect(sent[#sent][1]).toBe("visualBudget")
			expect(sent[#sent][2]).toBe(1)
			-- même seau : une autre métrique du client dans les 5 s est retenue par Widgets.send
			expect(Widgets.send("ClientMetric", "textScale", 100)).toBe(false)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)
	end)

	describe("VisualBudget › entrées hostiles", function()
		it("noms, nombres, sortes, budgets, ordres et demandes illisibles : rien, sans trace", function()
			local f = fresh()
			local VB = f.VB
			local nan, inf = 0 / 0, math.huge
			for _, name in { nil, 5, "", string.rep("x", 40), {}, true } do
				expect(VB.declare(name, { parts = 5 })).toBe(false)
				expect(VB.take(name, 1)).toBe(false)
				VB.release(name, 1)
				expect(VB.used(name)).toBe(0)
				expect(VB.declared(name)).toBe(false)
			end
			expect(VB.declare("tapis", "beaucoup")).toBe(false)
			expect(VB.declare("tapis", { parts = nan, particles = -3, lights = "2" })).toBe(true)
			expect(VB.stats().tapis.parts).toBe(0)
			VB.declare("tapis", { parts = inf })
			expect(VB.stats().tapis.parts).toBe(0)
			VB.declare("tapis", { parts = 10.7 })
			for _, n in { nan, inf, -inf, -1, "3", {}, true, 1e9 } do
				expect(VB.take("tapis", n)).toBe(false)
				VB.release("tapis", n)
			end
			expect(VB.take("tapis", 10, "nimporte")).toBe(true) -- sorte inconnue : pièces
			expect(VB.used("tapis")).toBe(10)
			for _, order in { nil, 7, { nan, inf, "3", {}, 99, -1 } } do
				for _, wants in { nil, "x", { [1] = "x", [2] = { full = nan, reduced = -1 } } } do
					VB.allocate("tapis", order, wants)
				end
			end
			expect(VB.used("tapis") <= 10).toBe(true)
			VB.allocate("tapis", { 1, 1, 1 }, { [1] = { full = 4, reduced = 2 } })
			expect(VB.used("tapis")).toBe(4) -- doublons de l'ordre ignorés
			f.clean()
		end)
	end)
end
