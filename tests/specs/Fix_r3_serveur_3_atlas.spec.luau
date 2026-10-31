--!nocheck
-- Correctifs r3 « serveur 3 » — réserve pleine (AtlasService.enforceStash, GDD §4.9, §8.1.6) :
--   * seuls les arrivants d'une PARADE peuvent être libérés par le débordement (« la parade a déjà
--     payé leur Glow ») : le cadeau Starfall, la Comète encaissée, la récompense du Grand Défilé…
--     restent toujours dans la collection (la réserve dépasse sa capacité jusqu'à la prochaine
--     parade)
--   * un Starborn (édition limitée) n'est jamais libéré automatiquement, même C/U/R
--   * le toast « cadeau Starfall » et la célébration « cometBanked » suivent les uids gardés
-- Vétéran type : 3 Mythiques ★3 perchés, réserve pleine d'Épiques (capacité réduite à 4).

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC (Starfall Saturday)
	local STASH = 4

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		Balance.Stash.Base = STASH
		if opts.noRateLimit then
			h:require("ServerScriptService.Server.Util.RateLimit").allow = function()
				return true
			end
		end
		h:boot()
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			Balance = Balance,
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			E = h:require("ServerScriptService.Server.Services.EventService"),
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Econ = h:require("ServerScriptService.Server.Services.EconomyService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
		}
		ctx.STARBORN = ctx.Nebbies.Variants.starborn.bit
		return ctx
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	local function speciesOf(ctx, key)
		for id, def in ctx.Nebbies.Rarities do
			if def.key == key then
				return ctx.Nebbies.speciesOfRarity(id)[1]
			end
		end
		error("rareté inconnue " .. key)
	end

	local function codes(ctx, s, n, v)
		local out = {}
		for i = 1, n do
			out[i] = ctx.Nebbies.pack(s, 0, v or 0)
		end
		return out
	end

	local function feedbackKeys(ctx, p)
		local out = {}
		for _, args in ctx.h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function has(list, value)
		return table.find(list, value) ~= nil
	end

	-- Vétéran : 3 Mythiques ★3 perchés et une réserve PLEINE d'Épiques ★1
	local function veteran(ctx, p, data)
		ctx.A.addNebbies(p, codes(ctx, speciesOf(ctx, "mythic"), 3), "parade", 3)
		ctx.A.addNebbies(p, codes(ctx, speciesOf(ctx, "epic"), STASH), "parade")
		expect(ctx.A.perchCount(p)).toBe(3)
		expect(count(data.nebbies)).toBe(3 + STASH)
	end

	local function hasRecord(data, s, v)
		for _, rec in data.nebbies do
			if rec.s == s and rec.v == v then
				return true
			end
		end
		return false
	end

	describe("Fix r3 serveur 3 › réserve pleine : une récompense n'est jamais libérée", function()
		it("cas A : Légendaire Starborn du Starfall gardé (réserve au-delà de sa capacité)", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local dust0 = data.stardust
			local legendary = speciesOf(ctx, "legendary")
			local kept = ctx.A.addNebbies(p, codes(ctx, legendary, 1, ctx.STARBORN), "starfall")
			expect(#kept).toBe(1)
			expect(data.nebbies[kept[1]].s).toBe(legendary)
			expect(count(data.nebbies)).toBe(3 + STASH + 1)
			expect(data.stardust).toBe(dust0)
			expect(has(feedbackKeys(ctx, p), "feedback.autoRelease")).toBe(false)
		end)

		it("cas B : Starborn C/U/R gardé, puis jamais libéré à l'arrivée suivante (Comète)", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local common = speciesOf(ctx, "common")
			local gift = ctx.A.addNebbies(p, codes(ctx, common, 1, ctx.STARBORN), "starfall")
			expect(#gift).toBe(1)
			local comet = ctx.A.addNebbies(p, codes(ctx, speciesOf(ctx, "legendary"), 1), "comet")
			expect(#comet).toBe(1)
			expect(data.nebbies[gift[1]] ~= nil).toBe(true)
			expect(data.nebbies[comet[1]] ~= nil).toBe(true)
			expect(count(data.nebbies)).toBe(3 + STASH + 2)
		end)

		for _, source in { "comet", "quest", "calendar", "product", "code" } do
			it(`source « {source} » : l'arrivant reste, aucune libération`, function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				veteran(ctx, p, data)
				local kept = ctx.A.addNebbies(p, codes(ctx, speciesOf(ctx, "rare"), 3), source)
				expect(#kept).toBe(3)
				expect(count(data.nebbies)).toBe(3 + STASH + 3)
			end)
		end

		it("la parade suivante rééquilibre, sans jamais libérer un Starborn ni un verrouillé", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local common = speciesOf(ctx, "common")
			local starborn = ctx.A.addNebbies(p, codes(ctx, common, 1, ctx.STARBORN), "starfall")[1]
			local reward = ctx.A.addNebbies(p, codes(ctx, common, 1), "quest")[1]
			ctx.A.setLock(p, reward, true)
			expect(count(data.nebbies)).toBe(3 + STASH + 2)
			-- parade de 3 Communs : réserve à 4 + 2 + 3 = 9 pour 4 places
			local arrivals = ctx.A.addNebbies(p, codes(ctx, common, 3), "parade")
			expect(#arrivals).toBe(0) -- les arrivants de la parade partent (Glow déjà payé)
			expect(data.nebbies[starborn] ~= nil).toBe(true)
			expect(data.nebbies[reward] ~= nil).toBe(true)
			expect(has(feedbackKeys(ctx, p), "feedback.autoRelease")).toBe(true)
			-- les Épiques non verrouillés de la réserve ne sont jamais libérés automatiquement
			expect(count(data.nebbies)).toBe(3 + STASH + 2)
		end)
	end)

	describe("Fix r3 serveur 3 › vrais parcours de récompense, réserve pleine d'Épiques", function()
		it("cadeau Starfall de fin de show : Starborn dans la collection ET toast", function()
			local ctx = boot({ t = SAT - 50 })
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local SF = ctx.Events.Starfall
			local t = SAT
			ctx.Clock.freeze(t)
			ctx.E.step(t)
			while t < SAT + SF.Duration + 5 do
				t += 5
				ctx.Clock.freeze(t)
				ctx.E.step(t)
			end
			expect(ctx.E.snapshot().starfall).toBeNil()
			local featured = ctx.EventClock.featuredSpecies(ctx.Clock.week(SAT))
			expect(hasRecord(data, featured, ctx.STARBORN)).toBe(true)
			expect(has(feedbackKeys(ctx, p), "feedback.starfallGift")).toBe(true)
		end)

		it("Comète encaissée : Nebby gardé, célébration avec son code", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local T1 = T0 + 600
			ctx.Clock.freeze(T1)
			ctx.E.step(T1)
			local Vector3 = ctx.h.globals.Vector3
			local impact = ctx.EventClock.cometImpact(T1)
			local function actor(pos)
				return {
					player = p,
					userId = p.UserId,
					slot = ctx.N.slotOf(p),
					pos = pos,
					prev = pos,
					valid = true,
					zen = false,
					crewId = 0,
					rookie = false,
					touch = false,
				}
			end
			ctx.E.stepComet(T1, { actor(Vector3.new(impact.X, 3, impact.Z)) })
			expect(ctx.E.carrier()).toBe(p)
			local code = ctx.E.snapshot().comet.code
			local gate = ctx.WorldLayout.gateCFrame(ctx.N.slotOf(p)).Position
			ctx.Clock.freeze(T1 + 30)
			ctx.E.step(T1 + 30)
			ctx.E.stepComet(T1 + 30, { actor(gate) })
			expect(ctx.E.snapshot().comet.phase).toBe("banked")
			local s = ctx.Nebbies.unpack(code)
			local found = false
			for _, rec in data.nebbies do
				if ctx.Nebbies.pack(rec.s, rec.f, rec.v) == code then
					found = true
				end
			end
			expect(found).toBe(true)
			expect(count(data.nebbies)).toBe(3 + STASH + 1)
			local cel = nil
			for _, args in ctx.h:sentTo(p, "Celebrate") do
				if args[1].kind == "cometBanked" then
					cel = args[1].data
				end
			end
			expect(cel ~= nil).toBe(true)
			expect(cel.code).toBe(code)
			expect(s ~= nil).toBe(true)
		end)

		it("Grand Défilé : le Légendaire de la semaine reste dans la collection", function()
			local ctx = boot({ noRateLimit = true })
			local p, data = join(ctx, 1)
			veteran(ctx, p, data)
			local function parade(n)
				local list = {}
				for _ = 1, n do
					table.insert(list, ctx.Nebbies.pack(1, 0, 0))
				end
				ctx.Signals.Parade:Fire(p, {
					count = n,
					codes = list,
					uids = {},
					glow = 0,
					bonus = 1,
					atBeacon = false,
					idleSeconds = 0,
					newEntries = 0,
					forced = false,
				})
			end
			parade(150)
			parade(150)
			ctx.h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "weekly", 1)
			expect(data.weekly.claimed).toBe(true)
			local legendary = ctx.EventClock.rotation("GrandParadeLegendary", ctx.Clock.week())
			expect(hasRecord(data, legendary, 0)).toBe(true)
			expect(count(data.nebbies)).toBe(3 + STASH + 1)
		end)
	end)
end
