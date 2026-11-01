--!nocheck
-- Validation de publication r6 : notes croisées des correcteurs.
--   * Pings (GDD §6.3) : le client limite à 1 / 1,5 s, le serveur limitait AUSSI à 1 / 1,5 s
--     (seau à 1 jeton). Deux pings envoyés à 1,5 s d'écart mais arrivés plus près (gigue réseau,
--     le premier retardé) voyaient le second refusé en silence. Maintenant : serveur
--     1 / (Cooldown − NetTolerance) = 1 / 1,2 s ; deux pings collés restent un seul PingShow.
--   Autres notes résolues, testées dans la spec de leur module :
--   * CongaRenderer : pointillés de sa propre queue, port sûr appliqué nœud par nœud comme
--     SnipRules.findCut et le cadre de PanelController (CongaRenderer.spec, « lisibilité »)
--   * Upgrades : « +1 perchoir (gardé à la Supernova) » à 16,3 px sur téléphone 640 × 360 ; audit
--     de texte de tous les panneaux sur téléphone (Fix_fin_client_panels_console.spec)
--   * DataService : reçu crédité pendant une panne puis rejoué à la reconnexion, déjà persisté par
--     les nouveaux essais de départ (Fix_divers_r2.spec)
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local R = "ReplicatedStorage.Remotes."

	-- `fakeClock` : os.clock des modules du harnais = horloge réelle jusqu'à ctx.freeze(), puis
	-- instant figé + décalage contrôlé par le test (RateLimit lit os.clock : pas de vraie attente
	-- de 1,2 s, aucune dépendance au temps réel)
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local ctx = { h = h, offset = 0, frozenAt = nil, calls = {} }
		if opts.fakeClock then
			local realOs = os
			local fakeOs = setmetatable({
				clock = function()
					return (ctx.frozenAt or realOs.clock()) + ctx.offset
				end,
			}, { __index = realOs })
			h.globals.os = fakeOs
		end
		function ctx.freeze()
			ctx.frozenAt = os.clock()
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if opts.recordRate then
			local RateLimit = h:require("ServerScriptService.Server.Util.RateLimit")
			local allow = RateLimit.allow
			RateLimit.allow = function(player, action, n, per)
				table.insert(ctx.calls, { action = action, n = n, per = per })
				return allow(player, action, n, per)
			end
		end
		ctx.Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		h:require("ServerScriptService.Server.Services.CrewService")
		h:boot()
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local DS = ctx.h:require("ServerScriptService.Server.Services.DataService")
		DS.waitFor(p, 2)
		ctx.h:settle(3)
		return p
	end

	local function pingShows(h)
		local n = 0
		for _, e in h.log.allClientEvents do
			if e.remote == "PingShow" then
				n += 1
			end
		end
		return n
	end

	describe("Fix r6 release › pings : débit serveur tolérant à la gigue (GDD §6.3)", function()
		it(
			"Ping limité côté serveur à 1 jeton par (Cooldown − NetTolerance) ≤ Cooldown − 0,25 s",
			function()
				local ctx = boot({ recordRate = true })
				local a = join(ctx, 1)
				ctx.h:fireServer(R .. "Ping", a, 2)
				local found = nil
				for _, c in ctx.calls do
					if c.action == "Ping" then
						found = c
					end
				end
				expect(found ~= nil).toBe(true)
				expect(found.n).toBe(1)
				expect(found.per <= ctx.Balance.Ping.Cooldown - 0.25).toBe(true)
				-- abus borné : jamais plus d'un ping par seconde
				expect(found.per >= 1).toBe(true)
				expect(found.per).toBe(ctx.Balance.Ping.Cooldown - ctx.Balance.Ping.NetTolerance)
				-- le client garde le rythme du GDD
				expect(ctx.Balance.Ping.Cooldown).toBe(1.5)
			end
		)

		it(
			"envoyés à 1,5 s d'écart, arrivés à 1,25 s (gigue) : les deux pings sont diffusés",
			function()
				local ctx = boot({ fakeClock = true })
				local a = join(ctx, 1)
				ctx.freeze()
				ctx.h:fireServer(R .. "Ping", a, 1)
				expect(pingShows(ctx.h)).toBe(1)
				ctx.offset += 1.25
				ctx.h:fireServer(R .. "Ping", a, 2)
				expect(pingShows(ctx.h)).toBe(2)
				-- collé au précédent : refusé ; puis 1 s plus tard : toujours refusé (1 jeton / 1,2 s)
				ctx.h:fireServer(R .. "Ping", a, 3)
				expect(pingShows(ctx.h)).toBe(2)
				ctx.offset += 1.0
				ctx.h:fireServer(R .. "Ping", a, 4)
				expect(pingShows(ctx.h)).toBe(2)
				-- 1,2 s après le dernier accepté : de nouveau diffusé
				ctx.offset += 0.25
				ctx.h:fireServer(R .. "Ping", a, 5)
				expect(pingShows(ctx.h)).toBe(3)
			end
		)

		it("rafale d'un tricheur sur 6 s : au plus un PingShow par 1,2 s", function()
			local ctx = boot({ fakeClock = true })
			local a = join(ctx, 1)
			ctx.freeze()
			for _ = 1, 60 do
				ctx.h:fireServer(R .. "Ping", a, 1)
				ctx.offset += 0.1
			end
			-- 6 s de rafale : 1 (jeton initial) + floor(5,9 / 1,2) = 5 au plus
			expect(pingShows(ctx.h) <= 1 + math.floor(5.9 / 1.2)).toBe(true)
			expect(pingShows(ctx.h) >= 4).toBe(true)
		end)
	end)
end
