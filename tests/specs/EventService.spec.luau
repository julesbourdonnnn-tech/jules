--!nocheck
-- EventService : météo, Grande Comète (ramassage, vol balayé, encaissement, explosion, chute),
-- Nuit de la Balise (réussite immédiate, Frenzy → Nuit d'Or, échec, miséricorde), Gloomwisps,
-- Starfall Saturday, boost de serveur et Glow Party, LiveOps, EventState, charges malveillantes
-- et cycle de vie.

local MockInstance = require("../harness/MockInstance")

-- types de données Roblox du harnais (posés au démarrage de chaque test)
local Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC (impact de Comète, :00)
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC (Starfall Saturday)

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		Vector3 = h.globals.Vector3
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
			Atlas = h:require("ServerScriptService.Server.Services.AtlasService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Admins = h:require("ServerScriptService.Server.Data.Admins"),
			Tuning = h:require("ServerScriptService.Server.Events.Tuning"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			banners = {},
			phases = {},
			comets = {},
			calls = { mods = {}, boost = {}, loose = {}, nebbies = {} },
		}
		if opts.before then
			opts.before(ctx)
		end
		h:boot()
		-- espions (les modules sont des tables : on enveloppe les fonctions)
		local Spawn, Econ, Atlas = ctx.Spawn, ctx.Econ, ctx.Atlas
		local setModifiers = Spawn.setModifiers
		Spawn.setModifiers = function(m)
			table.insert(ctx.calls.mods, m)
			return setModifiers(m)
		end
		local spawnLoose = Spawn.spawnLoose
		Spawn.spawnLoose = function(codes, from, now, o)
			table.insert(ctx.calls.loose, { codes = codes, from = from, now = now, opts = o })
			return spawnLoose(codes, from, now, o)
		end
		local setBoost = Econ.setServerBoostUntil
		Econ.setServerBoostUntil = function(t)
			table.insert(ctx.calls.boost, t)
			return setBoost(t)
		end
		local addNebbies = Atlas.addNebbies
		Atlas.addNebbies = function(p, codes, source, stars)
			table.insert(ctx.calls.nebbies, { player = p, codes = codes, source = source })
			return addNebbies(p, codes, source, stars)
		end
		ctx.Signals.BannerRequested:Connect(function(kind, args, source)
			table.insert(ctx.banners, { kind = kind, args = args, source = source })
		end)
		ctx.Signals.EventPhase:Connect(function(event, phase)
			table.insert(ctx.phases, event .. ":" .. phase)
		end)
		ctx.Signals.CometEvent:Connect(function(sig)
			table.insert(ctx.comets, sig)
		end)
		return ctx
	end

	local function join(ctx, userId, name)
		local p = ctx.h:addPlayer({ userId = userId, name = name or ("P" .. userId) })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, ctx.DS.get(p)
	end

	local function at(ctx, t)
		ctx.Clock.freeze(t)
		ctx.E.step(t)
	end

	local function actor(ctx, p, pos, prev, extra)
		local a = {
			player = p,
			userId = p.UserId,
			slot = ctx.N.slotOf(p),
			pos = pos,
			prev = prev or pos,
			valid = true,
			zen = false,
			crewId = 0,
			rookie = false,
			touch = false,
		}
		for k, v in extra or {} do
			a[k] = v
		end
		return a
	end

	local function has(list, value)
		return table.find(list, value) ~= nil
	end

	local function bannerKinds(ctx)
		local out = {}
		for _, b in ctx.banners do
			table.insert(out, b.kind)
		end
		return out
	end

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function setIncome(ctx, p, income)
		ctx.Econ.settle(p)
		ctx.DS.get(p).perchIncome = income
		ctx.Econ.refreshRate(p)
	end

	local function lastMods(ctx)
		return ctx.calls.mods[#ctx.calls.mods]
	end

	-- Premier créneau météo après T0 dont la clé vérifie `pred`
	local function findWeather(ctx, pred)
		local slot = math.floor(T0 / 360) + 1
		for s = slot, slot + 500 do
			local key = ctx.EventClock.weatherKeyForSlot(s)
			if pred(ctx.Events.WeatherByKey[key]) then
				return s * 360 + 120, key
			end
		end
		error("aucun créneau météo trouvé")
	end

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › météo (§4.15.1)", function()
		it("ouvre la fenêtre avec bannière, phase et modificateurs, puis la referme", function()
			local ctx = boot()
			local start, key = findWeather(ctx, function(def)
				return def.form ~= nil and def.version == "mvp"
			end)
			local def = ctx.Events.WeatherByKey[key]
			at(ctx, start - 1)
			expect(ctx.E.snapshot().weather).toBeNil()
			at(ctx, start)
			local w = ctx.E.snapshot().weather
			expect(w.key).toBe(key)
			expect(w.form).toBe(def.form)
			expect(w.startsAt).toBe(start)
			expect(w.endsAt).toBe(start + ctx.Events.Weather.Duration)
			expect(ctx.E.weatherForm()).toBe(def.form)
			expect(has(bannerKinds(ctx), "weather")).toBe(true)
			expect(has(ctx.phases, "weather:start")).toBe(true)
			local m = lastMods(ctx)
			expect(m.form).toBe(def.form)
			expect(m.formChance).toBe(ctx.Balance.Spawn.WeatherFormChance)
			expect(m.intervalDiv).toBe(1)
			at(ctx, start + ctx.Events.Weather.Duration)
			expect(ctx.E.snapshot().weather).toBeNil()
			expect(ctx.E.weatherForm()).toBeNil()
			expect(has(ctx.phases, "weather:end")).toBe(true)
			expect(lastMods(ctx).form).toBeNil()
			expect(lastMods(ctx).formChance).toBe(0)
		end)

		it("Meteor Shower : pas de forme, intervalles ÷3 et plafonds ×1,5", function()
			local ctx = boot()
			local start = findWeather(ctx, function(def)
				return def.key == "meteor"
			end)
			at(ctx, start + 1)
			local m = lastMods(ctx)
			expect(m.form).toBeNil()
			expect(m.formChance).toBe(0)
			expect(m.intervalDiv).toBe(3)
			expect(m.capMult).toBe(1.5)
			expect(ctx.E.weatherForm()).toBeNil()
		end)

		it("ne repousse pas les modificateurs quand rien ne change", function()
			local ctx = boot()
			at(ctx, T0 + 10)
			local n = #ctx.calls.mods
			at(ctx, T0 + 10.1)
			at(ctx, T0 + 10.2)
			expect(#ctx.calls.mods).toBe(n)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › Grande Comète (§4.15.2)", function()
		local T1 = T0 + 600 -- impact pendant une fenêtre météo (600 mod 360 = 240)

		it("alerte à −8 s, impact au point déterministe avec la forme de la météo active", function()
			local ctx = boot()
			at(ctx, T1 - 9)
			expect(ctx.E.snapshot().comet).toBeNil()
			at(ctx, T1 - 8)
			local c = ctx.E.snapshot().comet
			expect(c.id).toBe(T1)
			expect(c.phase).toBe("warn")
			expect(c.warnAt).toBe(T1 - 8)
			expect(c.burstAt).toBe(T1 + 75)
			expect(has(bannerKinds(ctx), "cometWarn")).toBe(true)
			expect(ctx.comets[#ctx.comets].kind).toBe("warn")
			at(ctx, T1)
			c = ctx.E.snapshot().comet
			expect(c.phase).toBe("ground")
			local impact = ctx.EventClock.cometImpact(T1)
			expect(c.x).toBeNear(impact.X)
			expect(c.z).toBeNear(impact.Z)
			local _, s = ctx.EventClock.cometContent(T1)
			local w = ctx.EventClock.weather(T1)
			local form = if w and w.form then w.form else 0
			expect(c.code).toBe(ctx.Nebbies.pack(s, form, 0))
			expect(has(ctx.phases, "comet:impact")).toBe(true)
		end)

		it("ramassage par le plus proche acteur valide ; Zen, tick signalé et sans Nid exclus", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local z = join(ctx, 3)
			at(ctx, T1)
			local impact = ctx.EventClock.cometImpact(T1)
			local near = Vector3.new(impact.X + 1, 3, impact.Z)
			-- Zen, tick signalé, slot 0 : jamais porteurs
			ctx.E.stepComet(T1, {
				actor(ctx, z, near, nil, { zen = true }),
				actor(ctx, a, near, nil, { valid = false }),
				actor(ctx, b, near, nil, { slot = 0 }),
			})
			expect(ctx.E.carrier()).toBeNil()
			-- trop loin
			ctx.E.stepComet(T1, { actor(ctx, a, Vector3.new(impact.X + 10, 3, impact.Z)) })
			expect(ctx.E.carrier()).toBeNil()
			-- balayage qui traverse le point : ramassé, le plus proche gagne
			ctx.E.stepComet(T1 + 0.1, {
				actor(ctx, b, Vector3.new(impact.X + 3, 3, impact.Z)),
				actor(
					ctx,
					a,
					Vector3.new(impact.X - 20, 3, impact.Z),
					Vector3.new(impact.X + 20, 3, impact.Z)
				),
			})
			expect(ctx.E.carrier()).toBe(a)
			expect(ctx.E.isCarrier(a)).toBe(true)
			expect(ctx.E.isCarrier(b)).toBe(false)
			local c = ctx.E.snapshot().comet
			expect(c.phase).toBe("carried")
			expect(c.carrierId).toBe(1)
			expect(has(bannerKinds(ctx), "cometPickup")).toBe(true)
		end)

		it(
			"vol balayé : immunité 2 s, interdiction de reprise 4 s, pas entre équipiers, +50 après 3 s",
			function()
				local ctx = boot()
				local a, da = join(ctx, 1)
				local b = join(ctx, 2)
				local c = join(ctx, 3)
				local held, parts = {}, {}
				ctx.Signals.CometHeld:Connect(function(p, s)
					table.insert(held, { p = p, s = s })
				end)
				ctx.Signals.CometParticipation:Connect(function(p, kind)
					table.insert(parts, { p = p, kind = kind })
				end)
				at(ctx, T1)
				local impact = ctx.EventClock.cometImpact(T1)
				local pa = Vector3.new(impact.X, 3, impact.Z)
				ctx.E.stepComet(T1, { actor(ctx, a, pa) })
				expect(ctx.E.carrier()).toBe(a)
				local through = function(p, crew)
					return actor(
						ctx,
						p,
						pa - Vector3.new(10, 0, 0),
						pa + Vector3.new(10, 0, 0),
						{ crewId = crew or 0 }
					)
				end
				-- immunité du nouveau porteur
				at(ctx, T1 + 1)
				ctx.E.stepComet(T1 + 1, { actor(ctx, a, pa), through(b) })
				expect(ctx.E.carrier()).toBe(a)
				-- équipier du porteur : ne vole pas
				at(ctx, T1 + 2.5)
				ctx.E.stepComet(T1 + 2.5, { actor(ctx, a, pa, nil, { crewId = 7 }), through(c, 7) })
				expect(ctx.E.carrier()).toBe(a)
				-- tenue ≥ 3 s : +50 Stardust à a
				local dust0 = da.stardust
				at(ctx, T1 + 3.5)
				ctx.E.stepComet(T1 + 3.5, { actor(ctx, a, pa), through(b) })
				expect(ctx.E.carrier()).toBe(b)
				expect(da.stardust - dust0).toBe(ctx.Balance.Comet.HoldDust)
				expect(has(feedbackKeys(ctx.h, a), "feedback.cometStolen")).toBe(true)
				expect(has(feedbackKeys(ctx.h, a), "feedback.cometHold")).toBe(true)
				expect(parts[1].p).toBe(a)
				expect(parts[1].kind).toBe("hold")
				expect(held[1].p).toBe(a)
				expect(held[1].s).toBeNear(3.5)
				expect(ctx.E.snapshot().comet.prevCarrierId).toBe(1)
				expect(has(bannerKinds(ctx), "cometStolen")).toBe(true)
				local steal = ctx.comets[#ctx.comets]
				expect(steal.kind).toBe("steal")
				expect(steal.player).toBe(b)
				expect(steal.from).toBe(a)
				-- a ne peut pas reprendre pendant 4 s (même après l'immunité de b)
				at(ctx, T1 + 6)
				ctx.E.stepComet(T1 + 6, { actor(ctx, b, pa), through(a) })
				expect(ctx.E.carrier()).toBe(b)
				at(ctx, T1 + 8)
				ctx.E.stepComet(T1 + 8, { actor(ctx, b, pa), through(a) })
				expect(ctx.E.carrier()).toBe(a)
				-- la récompense de tenue n'est versée qu'une fois par Comète
				at(ctx, T1 + 12)
				ctx.E.stepComet(T1 + 12, { actor(ctx, a, pa) })
				expect(da.stardust - dust0).toBe(ctx.Balance.Comet.HoldDust)
			end
		)

		it(
			"encaissement à la porte de son Nid : Nebby, 120 s de revenu, proches et équipiers récompensés",
			function()
				local ctx = boot()
				local a, da = join(ctx, 1)
				local b, db = join(ctx, 2)
				local c, dc = join(ctx, 3)
				local far, dfar = join(ctx, 4)
				setIncome(ctx, a, 10)
				setIncome(ctx, b, 4)
				at(ctx, T1)
				local impact = ctx.EventClock.cometImpact(T1)
				local pa = Vector3.new(impact.X, 3, impact.Z)
				ctx.E.stepComet(T1, { actor(ctx, a, pa, nil, { crewId = 5 }) })
				a:SetAttribute("CrewId", 5)
				c:SetAttribute("CrewId", 5)
				local gate = ctx.WorldLayout.gateCFrame(ctx.N.slotOf(a)).Position
				local code = ctx.E.snapshot().comet.code
				local b0, c0, f0 = db.stardust, dc.stardust, dfar.stardust
				at(ctx, T1 + 30)
				ctx.E.stepComet(T1 + 30, {
					actor(ctx, a, gate, nil, { crewId = 5 }),
					actor(ctx, b, gate + Vector3.new(8, 0, 0)),
					actor(ctx, far, gate + Vector3.new(60, 0, 0)),
				})
				local snap = ctx.E.snapshot().comet
				expect(snap.phase).toBe("banked")
				expect(snap.endedAt).toBe(T1 + 30)
				expect(ctx.E.carrier()).toBeNil()
				local call = ctx.calls.nebbies[#ctx.calls.nebbies]
				expect(call.player).toBe(a)
				expect(call.codes[1]).toBe(code)
				expect(call.source).toBe("comet")
				local cel = nil
				for _, args in ctx.h:sentTo(a, "Celebrate") do
					if args[1].kind == "cometBanked" then
						cel = args[1].data
					end
				end
				expect(cel.glow).toBe(1200) -- 120 s × 10 Glow/s
				expect(cel.code).toBe(code)
				expect(db.stardust - b0).toBe(ctx.Balance.Comet.NearDust)
				expect(has(feedbackKeys(ctx.h, b), "feedback.cometNear")).toBe(true)
				expect(dc.stardust - c0).toBe(ctx.Balance.Comet.CrewDust)
				expect(has(feedbackKeys(ctx.h, c), "feedback.cometCrew")).toBe(true)
				expect(dfar.stardust).toBe(f0)
				expect(has(bannerKinds(ctx), "cometBanked")).toBe(true)
				expect(ctx.comets[#ctx.comets].kind).toBe("bank")
				-- reste affichée ResultLinger s, puis disparaît sans être relancée dans ce créneau
				at(ctx, T1 + 30 + ctx.Tuning.ResultLinger)
				expect(ctx.E.snapshot().comet).toBeNil()
				at(ctx, T1 + 40)
				expect(ctx.E.snapshot().comet).toBeNil()
				expect(#ctx.calls.loose).toBe(0)
			end
		)

		it("explosion à +75 s : 5 Épiques libres (1 par joueur), récompenses de proximité", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local b, db = join(ctx, 2)
			at(ctx, T1)
			local impact = ctx.EventClock.cometImpact(T1)
			local pa = Vector3.new(impact.X, 3, impact.Z)
			ctx.E.stepComet(T1, { actor(ctx, a, pa) })
			local held = {}
			ctx.Signals.CometHeld:Connect(function(p, s)
				table.insert(held, { p = p, s = s })
			end)
			local b0 = db.stardust
			at(ctx, T1 + 75)
			ctx.E.stepComet(T1 + 75, { actor(ctx, a, pa), actor(ctx, b, pa + Vector3.new(0, 0, 15)) })
			local snap = ctx.E.snapshot().comet
			expect(snap.phase).toBe("burst")
			expect(#ctx.calls.loose).toBe(1)
			local loose = ctx.calls.loose[1]
			expect(#loose.codes).toBe(ctx.Balance.Comet.BurstCount)
			for _, code in loose.codes do
				local s = ctx.Nebbies.unpack(code)
				expect(ctx.Nebbies.rarityOf(s)).toBe(ctx.Balance.Comet.BurstRarity)
			end
			expect(loose.opts.group).toBe("burst:" .. T1)
			expect(loose.opts.groupCap).toBe(1)
			expect(db.stardust - b0).toBe(ctx.Balance.Comet.NearDust)
			expect(held[1].p).toBe(a)
			expect(held[1].s).toBeNear(75)
			expect(has(bannerKinds(ctx), "cometBurst")).toBe(true)
			expect(has(ctx.phases, "comet:burst")).toBe(true)
		end)

		it("filet : explose depuis step si stepComet n'a pas tourné", function()
			local ctx = boot()
			at(ctx, T1)
			at(ctx, T1 + 77)
			expect(ctx.E.snapshot().comet.phase).toBe("burst")
			expect(#ctx.calls.loose).toBe(1)
		end)

		it(
			"chute (départ, mort, Zen) : retombe à la dernière position valide, reprise interdite 4 s",
			function()
				local ctx = boot()
				local a = join(ctx, 1)
				local b = join(ctx, 2)
				at(ctx, T1)
				local impact = ctx.EventClock.cometImpact(T1)
				local pa = Vector3.new(impact.X, 3, impact.Z)
				ctx.E.stepComet(T1, { actor(ctx, a, pa) })
				local moved = pa + Vector3.new(6, 0, 0)
				at(ctx, T1 + 1)
				ctx.E.stepComet(T1 + 1, { actor(ctx, a, moved) })
				ctx.E.dropComet(b) -- pas porteur : sans effet
				expect(ctx.E.carrier()).toBe(a)
				ctx.E.dropComet(a)
				local snap = ctx.E.snapshot().comet
				expect(snap.phase).toBe("ground")
				expect(snap.x).toBeNear(moved.X)
				expect(snap.z).toBeNear(moved.Z)
				expect(ctx.comets[#ctx.comets].kind).toBe("drop")
				at(ctx, T1 + 2)
				ctx.E.stepComet(T1 + 2, { actor(ctx, a, moved) })
				expect(ctx.E.carrier()).toBeNil()
				at(ctx, T1 + 5.5)
				ctx.E.stepComet(T1 + 5.5, { actor(ctx, a, moved) })
				expect(ctx.E.carrier()).toBe(a)
				-- passage en Zen : chute + Feedback
				ctx.Signals.SettingChanged:Fire(a, "zen", true)
				expect(ctx.E.carrier()).toBeNil()
				expect(has(feedbackKeys(ctx.h, a), "feedback.cometNoZen")).toBe(true)
				-- porteur dont le personnage est mort et absent des acteurs : chute
				at(ctx, T1 + 6)
				ctx.E.stepComet(T1 + 6, { actor(ctx, b, moved) })
				expect(ctx.E.carrier()).toBe(b)
				b.Character:FindFirstChildOfClass("Humanoid").Health = 0
				at(ctx, T1 + 7)
				ctx.E.stepComet(T1 + 7, {})
				expect(ctx.E.carrier()).toBeNil()
				-- départ du porteur
				ctx.h:respawn(b)
				at(ctx, T1 + 12)
				ctx.E.stepComet(T1 + 12, { actor(ctx, b, moved) })
				expect(ctx.E.carrier()).toBe(b)
				ctx.h:removePlayer(b)
				expect(ctx.E.carrier()).toBeNil()
				expect(ctx.E.snapshot().comet.phase).toBe("ground")
			end
		)

		it("départ du porteur : son dernier temps de port est dans la sauvegarde (quête 21)", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			at(ctx, T1)
			-- quête du jour « Porteur de Comète » (10 s au total)
			da.quests.list = { { id = 21, p = 0, done = false, claimed = false } }
			da.quests.day = ctx.Clock.day()
			local impact = ctx.EventClock.cometImpact(T1)
			ctx.E.stepComet(T1, { actor(ctx, a, Vector3.new(impact.X, 3, impact.Z)) })
			expect(ctx.E.carrier()).toBe(a)
			at(ctx, T1 + 2)
			ctx.h:removePlayer(a)
			ctx.h:settle(5)
			expect(ctx.E.carrier()).toBeNil()
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			local saved = store:GetAsync("player_1").data
			expect(saved.quests.list[1].p).toBeNear(2)
			expect(saved.stats.cometsHeld).toBe(1)
		end)

		it("encaissement balayé : porte franchie entre deux ticks (pas de 6 studs) → encaissée", function()
			local ctx = boot()
			local a = join(ctx, 1)
			at(ctx, T1)
			local impact = ctx.EventClock.cometImpact(T1)
			ctx.E.stepComet(T1, { actor(ctx, a, Vector3.new(impact.X, 3, impact.Z)) })
			expect(ctx.E.carrier()).toBe(a)
			-- deux échantillons de part et d'autre de la boîte de porte (profonde de 4 studs)
			local gate = ctx.WorldLayout.gateCFrame(ctx.N.slotOf(a))
			local before = gate.Position - gate.LookVector * 3
			local after = gate.Position + gate.LookVector * 3
			expect(ctx.WorldLayout.inGateBox(ctx.N.slotOf(a), before)).toBe(false)
			expect(ctx.WorldLayout.inGateBox(ctx.N.slotOf(a), after)).toBe(false)
			at(ctx, T1 + 20)
			ctx.E.stepComet(T1 + 20, { actor(ctx, a, before) })
			expect(ctx.E.snapshot().comet.phase).toBe("carried")
			at(ctx, T1 + 20.1)
			ctx.E.stepComet(T1 + 20.1, { actor(ctx, a, after, before) })
			expect(ctx.E.snapshot().comet.phase).toBe("banked")
			-- un pas refusé (valid = false) ne compte jamais
			local ctx2 = boot()
			local b = join(ctx2, 2)
			at(ctx2, T1)
			ctx2.E.stepComet(T1, { actor(ctx2, b, Vector3.new(impact.X, 3, impact.Z)) })
			local g2 = ctx2.WorldLayout.gateCFrame(ctx2.N.slotOf(b))
			at(ctx2, T1 + 20)
			ctx2.E.stepComet(T1 + 20, {
				actor(
					ctx2,
					b,
					g2.Position + g2.LookVector * 3,
					g2.Position - g2.LookVector * 3,
					{ valid = false }
				),
			})
			expect(ctx2.E.snapshot().comet.phase).toBe("carried")
		end)

		it("acteurs absurdes ou temps non fini : aucune erreur", function()
			local ctx = boot()
			at(ctx, T1)
			expect(function()
				ctx.E.stepComet(T1, "nope")
				ctx.E.stepComet(0 / 0, {})
				ctx.E.stepComet(math.huge, {})
				ctx.E.step(0 / 0)
				ctx.E.step(math.huge)
			end).notToThrow()
			expect(ctx.E.snapshot().comet.phase).toBe("ground")
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › Nuit de la Balise (§4.15.3)", function()
		local B1 = T0 + 1500 -- :25:00

		it("alerte, trêve, objectif figé, réussite immédiate → Frenzy → Nuit d'Or", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local b, db = join(ctx, 2)
			local late, dl = join(ctx, 3)
			local results = {}
			ctx.Signals.BeaconResult:Connect(function(success, list)
				table.insert(results, { success = success, list = list })
			end)
			ctx.E.setActivePlayers(3)
			at(ctx, B1 - 16)
			expect(ctx.E.snapshot().beacon).toBeNil()
			at(ctx, B1 - 15)
			local st = ctx.E.snapshot()
			expect(st.beacon.phase).toBe("warn")
			expect(ctx.E.isTruce()).toBe(false)
			expect(#st.wisps).toBe(0) -- les Gloomwisps s'effacent dès l'alerte
			at(ctx, B1)
			expect(ctx.E.isTruce()).toBe(true)
			expect(ctx.E.beaconOpen()).toBe(true)
			local goal = ctx.Formulas.beaconGoal(3, 0)
			expect(ctx.E.snapshot().beacon.goal).toBe(goal)
			expect(has(bannerKinds(ctx), "beaconStart")).toBe(true)
			-- l'objectif est figé au début de la nuit
			ctx.E.setActivePlayers(9)
			expect(ctx.E.snapshot().beacon.goal).toBe(goal)
			local a0, b0, l0 = da.stardust, db.stardust, dl.stardust
			ctx.E.onBeaconParade(a, goal - 5)
			expect(ctx.E.snapshot().beacon.phase).toBe("active")
			at(ctx, B1 + 20)
			ctx.E.onBeaconParade(b, 5)
			local snap = ctx.E.snapshot()
			expect(snap.beacon.phase).toBe("success")
			expect(snap.beacon.points).toBe(goal)
			expect(snap.beacon.topUserId).toBe(1)
			expect(snap.frenzy.endsAt).toBe(B1 + 20 + ctx.Balance.Beacon.FrenzySeconds)
			expect(da.stardust - a0).toBe(ctx.Balance.Beacon.WinDust)
			expect(db.stardust - b0).toBe(ctx.Balance.Beacon.WinDust)
			expect(results[1].success).toBe(true)
			expect(#results[1].list).toBe(2)
			expect(has(bannerKinds(ctx), "beaconWin")).toBe(true)
			expect(has(bannerKinds(ctx), "beaconTop")).toBe(true)
			expect(has(ctx.phases, "frenzy:start")).toBe(true)
			-- contributeur tardif : récompense de réussite tout de suite
			ctx.E.onBeaconParade(late, 2)
			expect(dl.stardust - l0).toBe(ctx.Balance.Beacon.WinDust)
			expect(results[2].list[1]).toBe(late)
			-- deuxième contribution : rien de plus
			ctx.E.onBeaconParade(a, 3)
			expect(da.stardust - a0).toBe(ctx.Balance.Beacon.WinDust)
			-- Frenzy : intervalles ÷4 et plafonds ×2
			at(ctx, B1 + 21)
			local m = lastMods(ctx)
			expect(m.intervalDiv % ctx.Balance.Beacon.FrenzyIntervalDiv).toBe(0)
			expect(m.capMult >= ctx.Balance.Beacon.FrenzyCapMult).toBe(true)
			-- fin du Frenzy → Nuit d'Or (boost ×2 de serveur 5 min)
			local frenzyEnd = B1 + 20 + ctx.Balance.Beacon.FrenzySeconds
			at(ctx, frenzyEnd)
			expect(ctx.E.snapshot().frenzy).toBeNil()
			local boost = ctx.E.snapshot().serverBoost
			expect(boost.source).toBe("goldenNight")
			expect(boost.endsAt).toBe(frenzyEnd + ctx.Balance.Beacon.GoldenNightSeconds)
			expect(ctx.calls.boost[#ctx.calls.boost]).toBe(boost.endsAt)
			expect(ctx.E.serverBoostActive()).toBe(true)
			expect(has(bannerKinds(ctx), "goldenNight")).toBe(true)
			-- la trêve dure jusqu'à la fin de la fenêtre
			expect(ctx.E.isTruce()).toBe(true)
			at(ctx, B1 + ctx.Balance.Beacon.Duration)
			expect(ctx.E.isTruce()).toBe(false)
			expect(ctx.E.snapshot().beacon).toBeNil()
			at(ctx, boost.endsAt)
			expect(ctx.E.snapshot().serverBoost).toBeNil()
			expect(ctx.E.serverBoostActive()).toBe(false)
			expect(has(ctx.phases, "goldenNight:end")).toBe(true)
		end)

		it("échec à la fin : +15 par contributeur, miséricorde après 2 puis 3 échecs", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local results = {}
			ctx.Signals.BeaconResult:Connect(function(success, list)
				table.insert(results, { success = success, list = list })
			end)
			ctx.E.setActivePlayers(4)
			local goals = {}
			for night = 0, 3 do
				local start = B1 + night * 1800
				at(ctx, start - 15)
				at(ctx, start)
				table.insert(goals, ctx.E.snapshot().beacon.goal)
				if night == 0 then
					local a0 = da.stardust
					ctx.E.onBeaconParade(a, 1)
					at(ctx, start + ctx.Balance.Beacon.Duration)
					expect(ctx.E.snapshot().beacon.phase).toBe("fail")
					expect(ctx.E.isTruce()).toBe(false)
					expect(da.stardust - a0).toBe(ctx.Balance.Beacon.FailDust)
					expect(has(feedbackKeys(ctx.h, a), "feedback.beaconFail")).toBe(true)
					expect(results[1].success).toBe(false)
					expect(results[1].list[1]).toBe(a)
				else
					at(ctx, start + ctx.Balance.Beacon.Duration)
				end
				at(ctx, start + ctx.Balance.Beacon.Duration + ctx.Tuning.ResultLinger)
				expect(ctx.E.snapshot().beacon).toBeNil()
			end
			expect(goals[1]).toBe(ctx.Formulas.beaconGoal(4, 0))
			expect(goals[2]).toBe(ctx.Formulas.beaconGoal(4, 1))
			expect(goals[3]).toBe(ctx.Formulas.beaconGoal(4, 2))
			expect(goals[4]).toBe(ctx.Formulas.beaconGoal(4, 3))
			expect(goals[3] < goals[1]).toBe(true)
			expect(goals[4] < goals[3]).toBe(true)
			expect(has(bannerKinds(ctx), "beaconFail")).toBe(true)
		end)

		it("parades hors nuit ou charges invalides : sans effet", function()
			local ctx = boot()
			local a = join(ctx, 1)
			at(ctx, T0 + 100)
			ctx.E.onBeaconParade(a, 10)
			expect(ctx.E.snapshot().beacon).toBeNil()
			at(ctx, B1)
			for _, bad in { 0 / 0, math.huge, -3, 0, 1.5, "5", {} } do
				ctx.E.onBeaconParade(a, bad)
			end
			ctx.E.onBeaconParade("player", 5)
			ctx.E.onBeaconParade(nil, 5)
			expect(ctx.E.snapshot().beacon.points).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › Gloomwisps (§4.15.4)", function()
		it(
			"nombre selon les joueurs actifs, balayages, éclatement et réapparition 10 s plus tard",
			function()
				local ctx = boot()
				local a, da = join(ctx, 1)
				local popped = {}
				ctx.Signals.WispPopped:Connect(function(p)
					table.insert(popped, p)
				end)
				local t = T0 + 100
				ctx.E.setActivePlayers(1)
				at(ctx, t)
				expect(#ctx.E.snapshot().wisps).toBe(ctx.Formulas.wispCount(1, false))
				ctx.E.setActivePlayers(12)
				at(ctx, t + 1)
				expect(#ctx.E.snapshot().wisps).toBe(ctx.Formulas.wispCount(12, false))
				at(ctx, t + 1.1)
				local sweeps = ctx.E.wispSweeps(t + 1.1)
				expect(#sweeps).toBe(1)
				local sw = sweeps[1]
				local w = ctx.E.snapshot().wisps[1]
				expect(sw.id).toBe(w.id)
				local SeededPath = ctx.h:require("ReplicatedStorage.Shared.Logic.SeededPath")
				local expected = SeededPath.chordAt(w.seed, w.t0, t + 1.1)
				expect(sw.to.X).toBeNear(expected.X)
				expect(sw.to.Z).toBeNear(expected.Z)
				expect(sw.to.Y).toBeNear(
					ctx.WorldLayout.groundY(expected.X, expected.Z) + ctx.Tuning.WispBodyHeight
				)
				-- un tick signalé n'éclate rien
				local through = function(valid)
					return actor(
						ctx,
						a,
						sw.to - Vector3.new(3, 0, 0),
						sw.to + Vector3.new(3, 0, 0),
						{ valid = valid }
					)
				end
				ctx.E.stepWisps(t + 1.1, { through(false) })
				expect(ctx.E.snapshot().wisps[1].poppedAt).toBeNil()
				local dust0 = da.stardust
				ctx.E.stepWisps(t + 1.1, { through(true) })
				w = ctx.E.snapshot().wisps[1]
				expect(w.poppedAt).toBe(t + 1.1)
				expect(w.poppedBy).toBe(1)
				expect(w.respawnAt).toBe(t + 1.1 + ctx.Balance.Wisps.RespawnDelay)
				expect(da.stardust - dust0).toBe(ctx.Balance.Wisps.PopDust)
				expect(popped[1]).toBe(a)
				expect(has(feedbackKeys(ctx.h, a), "feedback.wispPop")).toBe(true)
				expect(#ctx.E.wispSweeps(t + 1.1)).toBe(0)
				-- réapparition sur une nouvelle graine
				local oldSeed = w.seed
				at(ctx, t + 1.1 + ctx.Balance.Wisps.RespawnDelay)
				w = ctx.E.snapshot().wisps[1]
				expect(w.poppedAt).toBeNil()
				expect(w.seed ~= oldSeed).toBe(true)
				expect(#ctx.E.wispSweeps(t + 12)).toBe(1)
			end
		)

		it("plafond wispDust atteint : Feedback capReached, aucune Stardust", function()
			local ctx = boot()
			local a, da = join(ctx, 1)
			local t = T0 + 100
			ctx.E.setActivePlayers(12)
			at(ctx, t)
			da.caps.day = ctx.Clock.day(t)
			da.caps.wispDust = ctx.Balance.DailyCaps.wispDust
			at(ctx, t + 0.1)
			local sw = ctx.E.wispSweeps(t + 0.1)[1]
			local dust0 = da.stardust
			ctx.E.stepWisps(t + 0.1, { actor(ctx, a, sw.to, sw.to + Vector3.new(2, 0, 0)) })
			expect(da.stardust).toBe(dust0)
			expect(has(feedbackKeys(ctx.h, a), "feedback.capReached")).toBe(true)
		end)

		it("aucun balayage pendant la trêve ; onWispSnip ignore les charges invalides", function()
			local ctx = boot()
			local a = join(ctx, 1)
			at(ctx, T0 + 1500)
			expect(ctx.E.isTruce()).toBe(true)
			expect(#ctx.E.wispSweeps(T0 + 1500)).toBe(0)
			expect(function()
				ctx.E.onWispSnip(1, a, 3)
				ctx.E.onWispSnip(0 / 0, a, 3)
				ctx.E.onWispSnip(1, "x", 3)
				ctx.E.onWispSnip(1, a, -1)
			end).notToThrow()
			expect(ctx.E.debugCounters().wispSnips).toBe(3)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › Starfall Saturday (§4.15.5)", function()
		it("Rainbow continu, boost 20 min, vedette, comètes toutes les 3 min, Starborn garanti", function()
			local ctx = boot({ t = SAT - 50 })
			local a = join(ctx, 1)
			local Events = ctx.Events
			at(ctx, SAT - 1)
			expect(ctx.E.snapshot().starfall).toBeNil()
			at(ctx, SAT)
			local st = ctx.E.snapshot()
			local featured = ctx.EventClock.featuredSpecies(ctx.Clock.week(SAT))
			expect(st.starfall.featured).toBe(featured)
			expect(st.starfall.endsAt).toBe(SAT + Events.Starfall.Duration)
			expect(st.weather.key).toBe("rainbow")
			expect(st.weather.endsAt).toBe(SAT + Events.Starfall.Duration)
			expect(st.serverBoost.source).toBe("starfall")
			expect(st.serverBoost.endsAt).toBe(SAT + Events.Starfall.BoostSeconds)
			expect(#st.wisps).toBe(0)
			expect(has(bannerKinds(ctx), "starfall")).toBe(true)
			expect(has(bannerKinds(ctx), "weather")).toBe(false)
			local m = lastMods(ctx)
			expect(m.featured).toBe(featured)
			expect(m.featuredChance).toBe(Events.Starfall.FeaturedChance)
			expect(m.starbornChance).toBe(Events.Starfall.StarbornChance)
			expect(m.form).toBe(Events.WeatherByKey.rainbow.form)
			-- Comète toutes les 3 min
			at(ctx, SAT + Events.Starfall.CometEvery - 8)
			expect(ctx.E.snapshot().comet.id).toBe(SAT + Events.Starfall.CometEvery)
			-- présence : a tout le show, b arrive trop tard
			local b
			local t = SAT + Events.Starfall.CometEvery - 8
			while t < SAT + Events.Starfall.Duration do
				t += 5
				at(ctx, t)
				if b == nil and t >= SAT + Events.Starfall.Duration - 100 then
					b = join(ctx, 2)
				end
			end
			expect(ctx.E.snapshot().starfall).toBeNil()
			local gifts = {}
			for _, call in ctx.calls.nebbies do
				if call.source == "starfall" then
					table.insert(gifts, call)
				end
			end
			expect(#gifts).toBe(1)
			expect(gifts[1].player).toBe(a)
			expect(gifts[1].codes[1]).toBe(ctx.Nebbies.pack(featured, 0, ctx.Nebbies.Variants.starborn.bit))
			expect(has(feedbackKeys(ctx.h, a), "feedback.starfallGift")).toBe(true)
			expect(has(ctx.phases, "starfall:end")).toBe(true)
		end)

		it("départ après 5 min de show : Starborn remis ET sauvegardé ; avant 5 min : rien", function()
			local ctx = boot({ t = SAT - 50 })
			local Events = ctx.Events
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			local t = SAT
			at(ctx, t)
			while t < SAT + Events.Starfall.PresenceSeconds + 10 do
				t += 5
				at(ctx, t)
			end
			local c = join(ctx, 3) -- arrivé trop tard pour être qualifié
			t += 5
			at(ctx, t)
			ctx.h:removePlayer(a)
			ctx.h:removePlayer(c)
			ctx.h:settle(5)
			local featured = ctx.EventClock.featuredSpecies(ctx.Clock.week(SAT))
			local bit = ctx.Nebbies.Variants.starborn.bit
			local function savedStarborn(userId)
				local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
				local record = store:GetAsync("player_" .. userId)
				local n = 0
				for _, rec in record.data.nebbies do
					if rec.s == featured and rec.v == bit then
						n += 1
					end
				end
				return n
			end
			expect(savedStarborn(1)).toBe(1)
			expect(savedStarborn(3)).toBe(0)
			-- fin du show : b le reçoit, a (parti) ne le reçoit pas une seconde fois
			while t < SAT + Events.Starfall.Duration do
				t += 5
				at(ctx, t)
			end
			local gifts = {}
			for _, call in ctx.calls.nebbies do
				if call.source == "starfall" then
					table.insert(gifts, call.player.UserId)
				end
			end
			table.sort(gifts)
			expect(gifts).toEqual({ 1, 2 })
			expect(b.Parent ~= nil).toBe(true)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › boost de serveur et Glow Party (§4.10, §16.11)", function()
		it("Glow Party : depuis max(now, fin), jamais refusée, source et acheteur", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local t = T0 + 100
			at(ctx, t)
			expect(ctx.E.queueGlowParty(a, 600)).toBe(t + 600)
			expect(ctx.E.queueGlowParty(a, 600)).toBe(t + 1200)
			expect(ctx.E.glowPartyRemaining()).toBe(1200)
			expect(ctx.E.serverBoostActive()).toBe(true)
			expect(ctx.calls.boost[#ctx.calls.boost]).toBe(t + 1200)
			ctx.E.flush()
			local st = ctx.E.snapshot().serverBoost
			expect(st.source).toBe("glowParty")
			expect(st.buyerId).toBe(1)
			-- valeurs invalides : rien ne change
			for _, bad in { 0 / 0, math.huge, -5, 0, "600" } do
				expect(ctx.E.queueGlowParty(a, bad)).toBe(t + 1200)
			end
			-- au-delà de 60 min : honorée quand même (limite de bouton seulement)
			for _ = 1, 6 do
				ctx.E.queueGlowParty(a, 600)
			end
			expect(ctx.E.glowPartyRemaining()).toBe(4800)
			at(ctx, t + 4800)
			expect(ctx.E.snapshot().serverBoost).toBeNil()
			expect(ctx.E.glowPartyRemaining()).toBe(0)
		end)

		it("Nuit d'Or pendant une Glow Party : la ligne de temps unique n'est jamais raccourcie", function()
			local ctx = boot()
			local a = join(ctx, 1)
			local t = T0 + 100
			at(ctx, t)
			ctx.E.queueGlowParty(a, 3600)
			ctx.E.runLiveOps("goldenNight")
			expect(ctx.E.snapshot().serverBoost.endsAt).toBe(t + 3600)
			expect(ctx.E.snapshot().serverBoost.source).toBe("glowParty")
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › LiveOps (§7.6)", function()
		local function bootLive(noRateLimit)
			local captured = {}
			local ctx = boot({
				before = function(c)
					if noRateLimit then
						local RateLimit = c.h:require("ServerScriptService.Server.Util.RateLimit")
						RateLimit.allow = function()
							return true
						end
					end
					MockInstance.classMethods.MessagingService.SubscribeAsync = function(_, topic, cb)
						captured.topic = topic
						captured.cb = cb
						return { Disconnect = function() end }
					end
					c.Admins[7] = true
				end,
			})
			ctx.h:settle(1)
			return ctx, captured
		end

		it(
			"attribut Admin, commandes d'un admin exécutées et publiées, refusées pour les autres",
			function()
				local ctx, captured = bootLive()
				expect(captured.topic).toBe(ctx.Events.LiveOps.Topic)
				local admin = join(ctx, 7)
				local other = join(ctx, 8)
				expect(admin:GetAttribute("Admin")).toBe(true)
				expect(other:GetAttribute("Admin")).toBe(false)
				at(ctx, T0 + 100)
				ctx.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", other, "frenzy")
				expect(ctx.E.snapshot().frenzy).toBeNil()
				expect(#ctx.h.log.messages).toBe(0)
				ctx.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", admin, "weather:frost")
				ctx.h:settle(1)
				local w = ctx.E.snapshot().weather
				expect(w.key).toBe("frost")
				expect(w.forced).toBe(true)
				expect(w.endsAt).toBe(T0 + 100 + ctx.Events.Weather.Duration)
				expect(#ctx.h.log.messages).toBe(1)
				expect(ctx.h.log.messages[1].topic).toBe("LiveOps")
				expect(ctx.h.log.messages[1].msg.cmd).toBe("weather:frost")
				expect(has(feedbackKeys(ctx.h, admin), "feedback.liveOpsDone")).toBe(true)
				-- débit : 1 commande / 2 s
				ctx.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", admin, "frenzy")
				expect(ctx.E.snapshot().frenzy).toBeNil()
			end
		)

		it("charges malveillantes : aucune exécution, aucune publication, aucune erreur", function()
			local ctx = bootLive(true)
			local admin = join(ctx, 7)
			at(ctx, T0 + 100)
			local before = ctx.E.snapshot()
			local bad = {
				0 / 0,
				math.huge,
				42,
				{},
				{ "frenzy" },
				true,
				string.rep("a", 100),
				"weather:eclipse", -- contenu v1.1 désactivé
				"weather:",
				"weather:lava",
				"comet:now",
				"frenzy ",
				"rm -rf",
			}
			for _, payload in bad do
				ctx.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", admin, payload)
			end
			ctx.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", admin)
			ctx.h:settle(1)
			expect(#ctx.h.log.messages).toBe(0)
			local after = ctx.E.snapshot()
			expect(after.frenzy).toBeNil()
			expect(after.weather == nil or after.weather.forced ~= true).toBe(true)
			expect(after.comet == nil or after.comet.id == (before.comet and before.comet.id)).toBe(true)
			expect(#feedbackKeys(ctx.h, admin)).toBe(0)
			expect(#ctx.h.errors).toBe(0)
		end)

		it(
			"messages MessagingService d'autres serveurs : exécutés ; les siens, vieux ou absurdes ignorés",
			function()
				local ctx, captured = bootLive()
				at(ctx, T0 + 100)
				local cb = captured.cb
				expect(type(cb)).toBe("function")
				cb({ Data = { cmd = "frenzy", at = T0 + 100, job = ctx.h.game.JobId } })
				expect(ctx.E.snapshot().frenzy).toBeNil()
				cb({ Data = { cmd = "frenzy", at = T0 - 3600, job = "autre" } })
				expect(ctx.E.snapshot().frenzy).toBeNil()
				expect(function()
					cb(nil)
					cb("x")
					cb({ Data = "frenzy" })
					cb({ Data = { cmd = 5, at = T0 + 100, job = "autre" } })
					cb({ Data = { cmd = "frenzy", at = 0 / 0, job = "autre" } })
				end).notToThrow()
				expect(ctx.E.snapshot().frenzy).toBeNil()
				cb({ Data = { cmd = "frenzy", at = T0 + 99, job = "autre" } })
				expect(ctx.E.snapshot().frenzy.endsAt).toBe(T0 + 100 + ctx.Balance.Beacon.FrenzySeconds)
			end
		)

		it("Comète supplémentaire : alerte immédiate, refusée si une Comète est en cours", function()
			local ctx = boot()
			local t = T0 + 200
			at(ctx, t)
			expect(ctx.E.snapshot().comet).toBeNil()
			ctx.E.runLiveOps("comet")
			local c = ctx.E.snapshot().comet
			expect(c.phase).toBe("warn")
			expect(c.impactAt).toBe(t + ctx.Balance.Comet.WarnSeconds)
			ctx.E.runLiveOps("comet")
			expect(ctx.E.snapshot().comet.id).toBe(c.id)
			at(ctx, c.impactAt)
			expect(ctx.E.snapshot().comet.phase).toBe("ground")
			ctx.E.runLiveOps("goldenNight")
			expect(ctx.E.snapshot().serverBoost.source).toBe("liveOps")
			ctx.E.runLiveOps("frenzy")
			expect(ctx.E.snapshot().frenzy).toBeTruthy()
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("EventService › EventState et cycle de vie", function()
		it("état complet à l'arrivée, puis une diffusion seulement quand quelque chose change", function()
			local ctx = boot()
			local a = join(ctx, 1)
			expect(#ctx.h:sentTo(a, "EventState")).toBe(1)
			local function stateCount()
				local n = 0
				for _, e in ctx.h.log.allClientEvents do
					if e.remote == "EventState" then
						n += 1
					end
				end
				return n
			end
			at(ctx, T0 + 100)
			ctx.E.flush()
			local n = stateCount()
			expect(n >= 1).toBe(true)
			ctx.E.flush()
			expect(stateCount()).toBe(n)
			ctx.E.setActivePlayers(5)
			ctx.E.flush()
			expect(stateCount()).toBe(n + 1)
			local last
			for _, e in ctx.h.log.allClientEvents do
				if e.remote == "EventState" then
					last = e.args[1]
				end
			end
			expect(last.activePlayers).toBe(5)
			expect(last.t).toBe(T0 + 100)
			expect(type(last.wisps)).toBe("table")
			expect(last.snipsDisabled).toBe(false)
		end)

		it("setActivePlayers ignore les valeurs non finies", function()
			local ctx = boot()
			ctx.E.setActivePlayers(4)
			ctx.E.setActivePlayers(0 / 0)
			ctx.E.setActivePlayers(math.huge)
			ctx.E.setActivePlayers("8")
			expect(ctx.E.snapshot().activePlayers).toBe(4)
			ctx.E.setActivePlayers(-3)
			expect(ctx.E.snapshot().activePlayers).toBe(0)
		end)

		it("démarrage complet : le tick de CongaService pilote EventService sans erreur", function()
			local ctx = boot({ t = T0 - 5 })
			local a = join(ctx, 1)
			join(ctx, 2)
			for _ = 1, 30 do
				ctx.Clock.advance(0.1)
				ctx.h:step(0.1)
			end
			ctx.h:respawn(a)
			for _ = 1, 10 do
				ctx.Clock.advance(0.1)
				ctx.h:step(0.1)
			end
			ctx.h:removePlayer(a)
			ctx.h:settle(2)
			expect(#ctx.h.errors).toBe(0)
			for _, w in ctx.h:warnings() do
				expect(string.find(w, "EventService", 1, true)).toBeNil()
			end
		end)
	end)
end
