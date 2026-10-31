--!nocheck
-- Correctifs r3 « serveur 3 » — EventService :
--   * boost ×2 de serveur : une fenêtre GRATUITE (Starfall, Nuit d'Or, LiveOps) ne chevauche plus
--     jamais une Glow Party payée : les secondes payées pas encore écoulées reprennent bout à bout
--     après elle (source glowParty et acheteur rétablis), une Nuit d'Or ajoute toujours ses 5 min,
--     le remboursement à l'arrêt compte les secondes repoussées
--   * explosion de Comète : les Épiques libres vivent Balance.Snip.LooseLifetime (20 s, GDD §4.5),
--     pas la durée de vie de la zone (60 s dans le Cratère)

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC (impact de Comète, :00)
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC (Starfall Saturday)
	local MIN = 60

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or (T0 - 100))
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			E = h:require("ServerScriptService.Server.Services.EventService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Econ = h:require("ServerScriptService.Server.Services.EconomyService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			calls = { boost = {}, loose = {}, personal = {} },
		}
		h:boot()
		local setBoost = ctx.Econ.setServerBoostUntil
		ctx.Econ.setServerBoostUntil = function(t)
			table.insert(ctx.calls.boost, t)
			return setBoost(t)
		end
		local grant = ctx.Econ.grantPersonalBoost
		ctx.Econ.grantPersonalBoost = function(p, seconds)
			table.insert(ctx.calls.personal, { player = p, seconds = seconds })
			return grant(p, seconds)
		end
		local spawnLoose = ctx.Spawn.spawnLoose
		ctx.Spawn.spawnLoose = function(codes, from, now, o)
			local out = spawnLoose(codes, from, now, o)
			table.insert(ctx.calls.loose, { now = now, opts = o, spawns = out })
			return out
		end
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function at(ctx, t)
		ctx.Clock.freeze(t)
		ctx.E.step(t)
	end

	local function boost(ctx)
		ctx.E.flush()
		return ctx.E.snapshot().serverBoost
	end

	describe("Fix r3 serveur 3 › une fenêtre gratuite n'avale jamais une Glow Party payée", function()
		it("Glow Party achetée à 15:58 un samedi de Starfall : ×2 jusqu'à 16:28", function()
			local ctx = boot({ t = SAT - 2 * MIN })
			local a = join(ctx, 1)
			at(ctx, SAT - 2 * MIN)
			expect(ctx.E.queueGlowParty(a, 10 * MIN)).toBe(SAT + 8 * MIN)
			expect(boost(ctx).source).toBe("glowParty")
			expect(boost(ctx).buyerId).toBe(1)
			-- 16:00 : Starfall (20 min gratuites) ; les 8 min payées restantes reprennent à 16:20
			at(ctx, SAT)
			local b = boost(ctx)
			expect(b.source).toBe("starfall")
			expect(b.buyerId).toBeNil()
			expect(b.endsAt).toBe(SAT + 28 * MIN)
			expect(ctx.calls.boost[#ctx.calls.boost]).toBe(SAT + 28 * MIN)
			expect(ctx.E.glowPartyRemaining()).toBe(28 * MIN)
			at(ctx, SAT + 19 * MIN)
			expect(boost(ctx).source).toBe("starfall")
			-- 16:20 : fin du boost Starfall, la Glow Party de l'acheteur reprend
			at(ctx, SAT + 20 * MIN)
			b = boost(ctx)
			expect(b.source).toBe("glowParty")
			expect(b.buyerId).toBe(1)
			expect(b.endsAt).toBe(SAT + 28 * MIN)
			expect(ctx.E.serverBoostActive()).toBe(true)
			at(ctx, SAT + 28 * MIN)
			expect(boost(ctx)).toBeNil()
			expect(ctx.E.serverBoostActive()).toBe(false)
		end)

		it(
			"achetée à 15:55 : les 5 min payées non écoulées passent après le Starfall (16:25)",
			function()
				local ctx = boot({ t = SAT - 5 * MIN })
				local a = join(ctx, 1)
				at(ctx, SAT - 5 * MIN)
				ctx.E.queueGlowParty(a, 10 * MIN)
				at(ctx, SAT)
				expect(boost(ctx).endsAt).toBe(SAT + 25 * MIN)
				at(ctx, SAT + 20 * MIN)
				expect(boost(ctx).source).toBe("glowParty")
				at(ctx, SAT + 25 * MIN)
				expect(boost(ctx)).toBeNil()
			end
		)

		it("Glow Party achetée PENDANT le Starfall : ajoutée après la fenêtre gratuite", function()
			local ctx = boot({ t = SAT - 10 })
			local a = join(ctx, 1)
			at(ctx, SAT)
			at(ctx, SAT + 5 * MIN)
			expect(ctx.E.queueGlowParty(a, 10 * MIN)).toBe(SAT + 30 * MIN)
			expect(boost(ctx).source).toBe("starfall")
			at(ctx, SAT + 20 * MIN)
			expect(boost(ctx).source).toBe("glowParty")
			expect(boost(ctx).buyerId).toBe(1)
		end)

		it("Nuit d'Or pendant une Glow Party : +5 min, la fête de l'acheteur reprend ensuite", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local t = T0 + 100
			at(ctx, t)
			ctx.E.queueGlowParty(a, 3600)
			at(ctx, t + 600)
			ctx.E.runLiveOps("goldenNight")
			local GN = ctx.Balance.Beacon.GoldenNightSeconds
			local b = boost(ctx)
			expect(b.endsAt).toBe(t + 3600 + GN)
			expect(b.source).toBe("liveOps")
			at(ctx, t + 600 + GN)
			b = boost(ctx)
			expect(b.source).toBe("glowParty")
			expect(b.buyerId).toBe(1)
			expect(b.endsAt).toBe(t + 3600 + GN)
		end)

		it("arrêt du serveur pendant le Starfall : les secondes payées repoussées sont rendues", function()
			local ctx = boot({ t = SAT - 2 * MIN })
			local a = join(ctx, 1)
			at(ctx, SAT - 2 * MIN)
			ctx.E.queueGlowParty(a, 10 * MIN)
			at(ctx, SAT)
			at(ctx, SAT + 10 * MIN)
			ctx.h:close()
			ctx.h:settle(3)
			local refunds = {}
			for _, call in ctx.calls.personal do
				if call.player == a then
					table.insert(refunds, call.seconds)
				end
			end
			expect(refunds).toEqual({ 8 * MIN })
		end)
	end)

	describe("Fix r3 serveur 3 › explosion de Comète : ruée courte", function()
		it("les Épiques libres vivent LooseLifetime (20 s), jamais la durée de vie de la zone", function()
			local ctx = boot()
			local T1 = T0 + 600
			at(ctx, T1)
			at(ctx, T1 + 77) -- explosion sans porteur (filet de step)
			expect(ctx.E.snapshot().comet.phase).toBe("burst")
			expect(#ctx.calls.loose).toBe(1)
			local call = ctx.calls.loose[1]
			expect(call.opts.life).toBeNil()
			expect(#call.spawns).toBe(ctx.Balance.Comet.BurstCount)
			for _, spawn in call.spawns do
				expect(spawn.life).toBe(ctx.Balance.Snip.LooseLifetime)
			end
		end)
	end)
end
