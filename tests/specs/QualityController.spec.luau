--!nocheck
-- QualityController (paquet client-world, docs/04 §13.3, GDD §12.9, remarque A23) : budgets pleins et
-- quotas partagés (particules 120 / 50 / 30 ≤ 200, Highlight 1 / 7 / 3 + réserve ≤ 12, lumières
-- 16 / 4 / 4 ≤ 24), descente après 10 s au-delà de 36 ms (ClientEvent « qualityReduced »), quotas
-- × 0,3 et 1 / 6 / 0, remontée après 60 s sous 25 ms, un changement par minute au plus, Graphismes
-- légers, copie des budgets, branchement sur Heartbeat, zéro trace.

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(1796724120)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		local low = opts.low == true
		Prefs.lowGraphics = function()
			return low
		end
		local QC = h:require(base .. "Controllers.QualityController")
		QC._reset()
		QC.Init()
		QC.Start()
		local changes = {}
		QC.Changed:Connect(function(r)
			table.insert(changes, r)
		end)
		local c = { h = h, QC = QC, changes = changes, Prefs = Prefs }
		function c.frames(dt, seconds)
			Clock.advance(seconds) -- horloge du jeu (débit client des intentions)
			for _ = 1, math.floor(seconds / dt + 0.5) do
				QC._frame(dt)
			end
			h:settle(1)
		end
		function c.setLow(v)
			low = v
			Prefs.Changed:Fire("lowGraphics", v)
			h:settle(1)
		end
		function c.sent(kind)
			local n = 0
			for _, e in h.log.serverEvents do
				if e.remote == "ClientEvent" and e.args[1] == kind then
					n += 1
				end
			end
			return n
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	describe("QualityController", function()
		it("budgets pleins : quotas partagés dans les plafonds du GDD (A23)", function()
			local c = client()
			local b = c.QC.budgets()
			expect(c.QC.reduced()).toBe(false)
			expect(b.lodScale).toBe(1)
			expect(b.animated).toBe(80)
			expect(b.blur).toBe(true)
			expect(b.particleQuota.vfx).toBe(120)
			expect(b.particleQuota.chase).toBe(50)
			expect(b.particleQuota.lighting).toBe(30)
			expect(b.particleQuota.vfx + b.particleQuota.chase + b.particleQuota.lighting <= 200).toBe(true)
			expect(b.highlightQuota.target).toBe(1)
			expect(b.highlightQuota.chase).toBe(7)
			expect(b.highlightQuota.ranch).toBe(3)
			expect(
				b.highlightQuota.target + b.highlightQuota.chase + b.highlightQuota.ranch + 1 <= b.highlights
			).toBe(true)
			expect(b.lightQuota.world).toBe(16)
			expect(b.lightQuota.ranch).toBe(4)
			expect(b.lightQuota.squishies).toBe(4)
			expect(b.lightQuota.world + b.lightQuota.ranch + b.lightQuota.squishies <= 24).toBe(true)
			-- copie : l'appelant ne peut rien abîmer
			b.particleQuota.vfx = 999
			expect(c.QC.budgets().particleQuota.vfx).toBe(120)
			c.clean()
		end)

		it(
			"36 ms pendant 9 s : rien ; pendant 10 s : qualité réduite, ClientEvent envoyé une fois",
			function()
				local c = client()
				c.frames(0.04, 9)
				expect(c.QC.reduced()).toBe(false)
				c.frames(0.04, 30) -- la série lente atteint 10 s
				expect(c.QC.reduced()).toBe(true)
				expect(c.changes[1]).toBe(true)
				expect(c.sent("qualityReduced")).toBe(1)
				local b = c.QC.budgets()
				expect(b.lodScale).toBe(0.6)
				expect(b.animated).toBe(40)
				expect(b.particles).toBe(0.3)
				expect(b.lightRange).toBe(60)
				expect(b.blur).toBe(false)
				expect(b.particleQuota.vfx).toBe(36)
				expect(b.particleQuota.chase).toBe(15)
				expect(b.particleQuota.lighting).toBe(9)
				expect(b.particleQuota.vfx + b.particleQuota.chase + b.particleQuota.lighting <= 60).toBe(
					true
				)
				expect(b.highlightQuota.target).toBe(1)
				expect(b.highlightQuota.chase).toBe(6)
				expect(b.highlightQuota.ranch).toBe(0)
				expect(b.highlights).toBe(7)
				c.clean()
			end
		)

		it("remonte après 60 s sous 25 ms, jamais deux changements dans la même minute", function()
			local c = client()
			c.frames(0.05, 10)
			expect(c.QC.reduced()).toBe(true)
			-- rapide tout de suite, mais moins d'une minute après la descente : on reste réduit
			c.frames(0.016, 45)
			expect(c.QC.reduced()).toBe(true)
			c.frames(0.016, 20)
			expect(c.QC.reduced()).toBe(false)
			expect(c.changes[#c.changes]).toBe(false)
			-- de nouveau lent dès la remontée : pas de nouvelle descente avant 60 s
			c.frames(0.05, 30)
			expect(c.QC.reduced()).toBe(false)
			c.frames(0.05, 35)
			expect(c.QC.reduced()).toBe(true)
			expect(c.sent("qualityReduced")).toBe(2)
			c.clean()
		end)

		it("entre 25 et 36 ms : aucun changement", function()
			local c = client()
			c.frames(0.03, 120)
			expect(c.QC.reduced()).toBe(false)
			expect(#c.changes).toBe(0)
			c.clean()
		end)

		it(
			"Graphismes légers force la qualité réduite (et la rend en le coupant), sans analytique",
			function()
				local c = client({ low = true })
				expect(c.QC.reduced()).toBe(true)
				expect(c.QC.budgets().particleQuota.vfx).toBe(36)
				c.setLow(false)
				expect(c.QC.reduced()).toBe(false)
				expect(c.changes[#c.changes]).toBe(false)
				c.setLow(true)
				expect(c.changes[#c.changes]).toBe(true)
				expect(c.sent("qualityReduced")).toBe(0)
				c.clean()
			end
		)

		it(
			"branché sur Heartbeat ; durées d'image hostiles (NaN, négatives, énormes) sans effet",
			function()
				local c = client()
				c.QC._frame(0 / 0)
				c.QC._frame(-5)
				c.QC._frame(math.huge)
				c.QC._frame("x")
				c.h:step(0.04, 30)
				expect(c.QC.reduced()).toBe(false)
				c.clean()
			end
		)
	end)
end
