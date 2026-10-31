--!nocheck
-- SpawnService (paquet conga) : apparitions par zone (plafonds, intervalles, probabilités,
-- modificateurs météo / Frenzy / Starfall), flânerie, requêtes spatiales, Nebbies libres
-- (étourdissement, priorité, plafonds de groupe), apparitions personnelles (bienvenue, Rare de Q4,
-- accueil dirigé), WildEvent à 4 Hz, nettoyage au départ.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local DT = 0.1

	local function setup()
		local h = Harness.new()
		local env = { h = h, slots = {}, V3 = h.globals.Vector3 }
		h:require("ReplicatedStorage.Shared.Net").setup()
		env.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		env.Clock.freeze(T0)
		env.B = h:require("ReplicatedStorage.Shared.Config.Balance")
		env.Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		env.Zones = h:require("ReplicatedStorage.Shared.Config.Zones")
		env.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		env.SP = h:require("ReplicatedStorage.Shared.Logic.SeededPath")
		local Nest = h:require("ServerScriptService.Server.Services.NestService")
		Nest.slotOf = function(p)
			return env.slots[p] or 0
		end
		env.Spawn = h:require("ServerScriptService.Server.Services.SpawnService")
		env.Spawn.Init()
		env.Spawn.Start()
		return env
	end

	local function run(env, seconds)
		for _ = 1, math.floor(seconds / DT + 0.5) do
			env.Clock.advance(DT)
			env.Spawn.step(env.Clock.now())
		end
	end

	local function wildEvents(env)
		local out = {}
		for _, e in env.h.log.allClientEvents do
			if e.remote == "WildEvent" then
				table.insert(out, e.args[1])
			end
		end
		return out
	end

	local function allPublic(env)
		return env.Spawn.snapshotFor({ UserId = -1 })
	end

	local function rarityOfCode(env, code)
		local s = env.Neb.unpack(code)
		return env.Neb.rarityOf(s)
	end

	-- Enregistrement serveur d'un sauvage par id (recherche sur toute l'île)
	local function wildById(env, id, player, now)
		for _, w in env.Spawn.query(env.V3.new(0, 0, 0), 400, now or env.Clock.now(), player) do
			if w.id == id then
				return w
			end
		end
		return nil
	end

	local function makeWild(env, code, pos, extra)
		local id = env.Spawn.spawnLoose(
			{ code },
			{ pos },
			env.Clock.now(),
			extra or { silent = true, dizzy = 0 }
		)
		return id[1]
	end

	describe("SpawnService › apparitions de zone", function()
		it("chaque zone se remplit jusqu'à son plafond (12 actifs) sans jamais le dépasser", function()
			local env = setup()
			env.Spawn.setActivePlayers(12)
			for _ = 1, 40 do
				run(env, 1)
				for _, def in env.Zones.List do
					expect(env.Spawn.aliveCount(def.key) <= def.cap).toBe(true)
				end
			end
			for _, def in env.Zones.List do
				expect({ zone = def.key, n = env.Spawn.aliveCount(def.key) }).toEqual({
					zone = def.key,
					n = def.cap,
				})
			end
		end)

		it("plafond effectif : round(plafond × capScale) avec peu de joueurs actifs", function()
			local env = setup()
			env.Spawn.setActivePlayers(0) -- capScale = 0,5
			run(env, 40)
			expect(env.Spawn.aliveCount("meadow")).toBe(20)
			expect(env.Spawn.aliveCount("glade")).toBe(12)
			expect(env.Spawn.aliveCount("crater")).toBe(5)
		end)

		it("intervalles de zone (0,4 / 0,8 / 2,5 s) et rattrapage borné", function()
			local env = setup()
			env.Spawn.setActivePlayers(12)
			run(env, 4)
			-- première tentative immédiate, puis une par intervalle
			expect(math.abs(env.Spawn.aliveCount("meadow") - 10) <= 1).toBe(true)
			expect(math.abs(env.Spawn.aliveCount("glade") - 5) <= 1).toBe(true)
			expect(math.abs(env.Spawn.aliveCount("crater") - 2) <= 1).toBe(true)
			-- un pas de 30 s d'un coup ne crée pas de rafale
			local before = env.Spawn.aliveCount("meadow")
			env.Clock.advance(30)
			env.Spawn.step(env.Clock.now())
			expect(env.Spawn.aliveCount("meadow") - before <= 8).toBe(true)
		end)

		it("ancres dans leur anneau, sur la grille, à ≥ 6 studs les unes des autres", function()
			local env = setup()
			env.Spawn.setActivePlayers(12)
			run(env, 30)
			local list = allPublic(env)
			expect(#list > 50).toBe(true)
			for i, a in list do
				local zone = env.WL.zoneAt(env.V3.new(a.x, 0, a.z))
				expect(zone ~= nil).toBe(true)
				expect(a.x % env.B.Spawn.GridStep).toBe(0)
				for j = i + 1, #list do
					local b = list[j]
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
					expect(d >= env.B.Spawn.MinSeparation).toBe(true)
				end
				-- hors des ports sûrs élargis
				expect(env.WL.inHarbor(env.V3.new(a.x, 0, a.z))).toBe(false)
			end
		end)

		it("raretés tirées selon les probabilités de la zone ; espèces activées seulement", function()
			local env = setup()
			env.Spawn.setActivePlayers(12)
			env.Spawn.setModifiers({
				formChance = 0,
				intervalDiv = 20,
				capMult = 100,
				featuredChance = 0,
				starbornChance = 0,
			})
			local counts = { meadow = {}, glade = {}, crater = {} }
			local totals = { meadow = 0, glade = 0, crater = 0 }
			for _ = 1, 450 do
				run(env, DT)
				for _, w in allPublic(env) do
					local zone = env.WL.zoneAt(env.V3.new(w.x, 0, w.z))
					local r = rarityOfCode(env, w.code)
					local s = env.Neb.unpack(w.code)
					expect(env.Neb.isSpeciesEnabled(s)).toBe(true)
					counts[zone][r] = (counts[zone][r] or 0) + 1
					totals[zone] += 1
					env.Spawn.consume(w.id, { UserId = 1 })
				end
			end
			expect(totals.meadow > 1500).toBe(true)
			for _, def in env.Zones.List do
				for _, o in def.odds do
					local share = (counts[def.key][o.rarity] or 0) / totals[def.key] * 100
					local tolerance =
						math.max(2, 4 * math.sqrt(o.weight * (100 - o.weight) / totals[def.key]))
					expect({ zone = def.key, rarity = o.rarity, ok = math.abs(share - o.weight) <= tolerance }).toEqual({
						zone = def.key,
						rarity = o.rarity,
						ok = true,
					})
				end
				for r in counts[def.key] do
					local listed = false
					for _, o in def.odds do
						listed = listed or o.rarity == r
					end
					expect(listed).toBe(true)
				end
			end
		end)

		it(
			"modificateurs : forme météo, vedette Starborn, Frenzy (÷4, ×2), valeurs invalides ignorées",
			function()
				local env = setup()
				env.Spawn.setActivePlayers(12)
				env.Spawn.setModifiers({
					form = 1,
					formChance = 1,
					intervalDiv = 4,
					capMult = 2,
					featured = 23,
					featuredChance = 1,
					starbornChance = 1,
				})
				run(env, 4)
				-- Frenzy : 4 fois plus d'apparitions (≈ 40 en Prairie en 4 s)
				expect(env.Spawn.aliveCount("meadow") >= 36).toBe(true)
				for _, w in allPublic(env) do
					local s, f, v = env.Neb.unpack(w.code)
					expect(s).toBe(23)
					expect(f).toBe(1)
					expect(bit32.btest(v, env.Neb.Variants.starborn.bit)).toBe(true)
				end
				-- forme non activée (Eclipse v1.1), espèce inconnue, NaN : ignorés
				env.Spawn.setModifiers({
					form = 4,
					formChance = 0 / 0,
					intervalDiv = -3,
					capMult = math.huge,
					featured = 999,
					featuredChance = 2,
					starbornChance = "x",
				})
				local env2 = setup()
				env2.Spawn.setModifiers("garbage")
				env2.Spawn.setModifiers({ form = 4, formChance = 1, intervalDiv = 0 / 0, capMult = -1 })
				env2.Spawn.setActivePlayers(0 / 0)
				env2.Spawn.setActivePlayers("12")
				run(env2, 3)
				for _, w in allPublic(env2) do
					local _, f = env2.Neb.unpack(w.code)
					expect(f).toBe(0)
				end
				expect(env2.Spawn.aliveCount("meadow") > 0).toBe(true)
			end
		)

		it(
			"expiration à t0 + durée de vie, despawn « expired » seulement s'il a été envoyé",
			function()
				local env = setup()
				env.Spawn.setActivePlayers(12)
				run(env, 0.1)
				env.Spawn.flush(env.Clock.now(), true)
				local sent = wildEvents(env)
				expect(#sent).toBe(1)
				local first = sent[1].spawns[1]
				expect(first.life).toBe(env.Zones.byKey.meadow.lifetime)
				run(env, env.Zones.byKey.meadow.lifetime + 1)
				env.Spawn.flush(env.Clock.now(), true)
				local despawned = {}
				for _, payload in wildEvents(env) do
					for _, d in payload.despawns do
						despawned[d.id] = d.reason
					end
				end
				expect(despawned[first.id]).toBe("expired")
			end
		)
	end)

	describe("SpawnService › flânerie, requêtes, captures", function()
		it("position = ancre + SeededPath.wander (amplitude ≤ 1,6 par axe)", function()
			local env = setup()
			local spawn =
				makeWild(env, env.Neb.pack(1, 0, 0), env.V3.new(60, 3, 60), { silent = true, dizzy = 0 })
			local wild = env.Spawn.query(env.V3.new(spawn.x, 0, spawn.z), 30, env.Clock.now() + 5)[1]
			expect(wild ~= nil).toBe(true)
			local t = env.Clock.now() + 5
			local p = env.Spawn.positionOf(wild, t)
			local expected = wild.anchor + env.SP.wander(wild.seed, t - wild.t0)
			expect((p - expected).Magnitude < 1e-4).toBe(true)
			expect(math.abs(p.X - wild.anchor.X) <= env.B.Spawn.WanderAmplitude + 1e-6).toBe(true)
		end)

		it("query : rayon XZ, visibilité onlyFor, entrées invalides", function()
			local env = setup()
			local a = { UserId = 1, Parent = true }
			local b = { UserId = 2, Parent = true }
			local now = env.Clock.now()
			local pos = env.V3.new(-40, 0, 80)
			local id = env.Spawn.spawnPersonal(a, env.Neb.pack(2, 0, 0), pos)
			expect(id > 0).toBe(true)
			expect(#env.Spawn.query(pos, 3, now, a)).toBe(1)
			expect(#env.Spawn.query(pos, 3, now, b)).toBe(0)
			expect(#env.Spawn.query(pos, 3, now, nil)).toBe(0)
			expect(#env.Spawn.query(pos + env.V3.new(8, 0, 0), 4, now, a)).toBe(0)
			expect(#env.Spawn.query(env.V3.new(0 / 0, 0, 0), 3, now, a)).toBe(0)
			expect(#env.Spawn.query(pos, -1, now, a)).toBe(0)
			expect(#env.Spawn.query(pos, 0 / 0, now, a)).toBe(0)
		end)

		it("libres : étourdis 1,2 s pour tous sauf la victime (slot prioritaire)", function()
			local env = setup()
			local victim = { UserId = 1 }
			local other = { UserId = 2 }
			local now = env.Clock.now()
			local spawns = env.Spawn.spawnLoose(
				{ env.Neb.pack(3, 0, 0), env.Neb.pack(4, 0, 0) },
				{ env.V3.new(70, 3, 0) },
				now,
				{ prioritySlot = 5, silent = true }
			)
			expect(#spawns).toBe(2)
			expect(spawns[1].prioritySlot).toBe(5)
			expect(spawns[1].dizzyUntil).toBe(now + env.B.Snip.Dizzy)
			local wild = wildById(env, spawns[1].id)
			expect(env.Spawn.canCatch(victim, 5, wild, now)).toBe(true)
			expect(env.Spawn.canCatch(other, 6, wild, now)).toBe(false)
			expect(env.Spawn.canCatch(other, 6, wild, now + env.B.Snip.Dizzy + 0.01)).toBe(true)
			-- expirent au bout de 20 s
			expect(spawns[1].life).toBe(env.B.Snip.LooseLifetime)
			expect(env.Spawn.canCatch(victim, 5, wild, now + env.B.Snip.LooseLifetime + 0.01)).toBe(false)
		end)

		it(
			"arc de dispersion : du point de départ vers un atterrissage à 4-9 studs, borné à l'île",
			function()
				local env = setup()
				local now = env.Clock.now()
				local origin = env.V3.new(20, 3, -90)
				local codes = {}
				for i = 1, 12 do
					codes[i] = env.Neb.pack(1, 0, 0)
				end
				local spawns = env.Spawn.spawnLoose(codes, { origin }, now, { silent = true })
				for _, s in spawns do
					local d = math.sqrt((s.x - origin.X) ^ 2 + (s.z - origin.Z) ^ 2)
					expect(d >= env.B.Snip.ScatterMin - 1e-3 and d <= env.B.Snip.ScatterMax + 1e-3).toBe(true)
					expect(s.fromX).toBe(origin.X)
					expect(s.fromZ).toBe(origin.Z)
				end
				local edge = env.Spawn.spawnLoose(codes, { env.V3.new(176, 3, 0) }, now, { silent = true })
				for _, s in edge do
					expect(math.sqrt(s.x ^ 2 + s.z ^ 2) <= 170 + 1e-3).toBe(true)
				end
				-- au milieu de l'arc, la position serveur est entre le départ et l'atterrissage
				local wild = wildById(env, spawns[1].id)
				local mid = env.Spawn.positionOf(wild, now + env.B.Snip.ScatterTime / 2)
				local target = wild.anchor
				expect(
					((mid - origin).Magnitude + (target - mid).Magnitude) - (target - origin).Magnitude < 1e-3
				).toBe(true)
			end
		)

		it("plafond de groupe : 1 Épique d'explosion par joueur", function()
			local env = setup()
			local p = { UserId = 9 }
			local now = env.Clock.now()
			local codes = {}
			for i = 1, 5 do
				codes[i] = env.Neb.pack(23, 0, 0)
			end
			local spawns = env.Spawn.spawnLoose(
				codes,
				{ env.V3.new(30, 3, 0) },
				now,
				{ group = "burst:7", groupCap = 1, dizzy = 0 }
			)
			expect(#spawns).toBe(5)
			local w1 = wildById(env, spawns[1].id)
			local w2 = wildById(env, spawns[2].id)
			expect(env.Spawn.canCatch(p, 1, w1, now + 1)).toBe(true)
			expect(env.Spawn.consume(w1.id, p) ~= nil).toBe(true)
			expect(env.Spawn.canCatch(p, 1, w2, now + 1)).toBe(false)
			expect(env.Spawn.canCatch({ UserId = 10 }, 2, w2, now + 1)).toBe(true)
			-- départ : le plafond du joueur est oublié
			env.Spawn.clearPlayer(p)
			expect(env.Spawn.canCatch(p, 1, w2, now + 1)).toBe(true)
		end)

		it("plafonds de groupe oubliés quand le groupe n'a plus de Nebby vivant (pas de fuite)", function()
			local env = setup()
			local p = { UserId = 9 }
			local now = env.Clock.now()
			-- une explosion de Comète toutes les 10 min : sans nettoyage, un groupe de plus à chaque fois
			for burst = 1, 3 do
				local codes = {}
				for i = 1, 5 do
					codes[i] = env.Neb.pack(23, 0, 0)
				end
				local spawns = env.Spawn.spawnLoose(
					codes,
					{ env.V3.new(30, 3, 0) },
					now,
					{ group = "burst:" .. burst, groupCap = 1, dizzy = 0 }
				)
				env.Spawn.consume(spawns[1].id, p)
				-- le dernier capturé du groupe : le plafond disparaît avec lui
				if burst == 3 then
					for i = 2, 5 do
						env.Spawn.consume(spawns[i].id, { UserId = 100 + i })
					end
				end
			end
			expect(env.Spawn.groupCount()).toBe(2)
			-- les autres expirent
			run(env, env.B.Snip.LooseLifetime + 1)
			expect(env.Spawn.groupCount()).toBe(0)
		end)

		it(
			"consume : une seule fois ; un capturé n'est jamais listé en despawn, ni envoyé s'il était en attente",
			function()
				local env = setup()
				env.Spawn.setActivePlayers(12)
				run(env, 0.1)
				local list = allPublic(env)
				expect(#list >= 1).toBe(true)
				local id = list[1].id
				expect(env.Spawn.consume(id, { UserId = 1 }) ~= nil).toBe(true)
				expect(env.Spawn.consume(id, { UserId = 1 })).toBeNil()
				env.Spawn.flush(env.Clock.now(), true)
				for _, payload in wildEvents(env) do
					for _, s in payload.spawns do
						expect(s.id ~= id).toBe(true)
					end
					for _, d in payload.despawns do
						expect(d.id ~= id).toBe(true)
					end
				end
			end
		)

		it("ids uniques, attribués en tourniquet (pas de réutilisation immédiate)", function()
			local env = setup()
			local seen = {}
			local p = { UserId = 1 }
			for i = 1, 300 do
				local spawn = makeWild(
					env,
					env.Neb.pack(1, 0, 0),
					env.V3.new(-100 + (i % 30) * 6, 3, 100 - (i // 30) * 6)
				)
				expect(seen[spawn.id]).toBeNil()
				seen[spawn.id] = true
				env.Spawn.consume(spawn.id, p)
			end
		end)
	end)

	describe("SpawnService › Nebbies libres et WildEvent", function()
		it("silent : transmis par l'appelant ; sinon envoi urgent par WildEvent", function()
			local env = setup()
			local now = env.Clock.now()
			env.Spawn.flush(now, true)
			env.Spawn.spawnLoose({ env.Neb.pack(1, 0, 0) }, { env.V3.new(60, 3, 0) }, now, { silent = true })
			env.Spawn.flush(now + 0.05)
			expect(#wildEvents(env)).toBe(0)
			local burst = env.Spawn.spawnLoose({ env.Neb.pack(23, 0, 0) }, { env.V3.new(30, 3, 0) }, now, {})
			env.Spawn.flush(now + 0.06) -- < 0,25 s depuis le dernier envoi, mais urgent
			local events = wildEvents(env)
			expect(#events).toBe(1)
			expect(events[1].spawns[1].id).toBe(burst[1].id)
		end)

		it("WildEvent groupé à 4 Hz ; personnels au seul joueur concerné", function()
			local env = setup()
			local alice = env.h:addPlayer({ userId = 1, name = "Alice" })
			local bob = env.h:addPlayer({ userId = 2, name = "Bob" })
			env.Spawn.setActivePlayers(12)
			run(env, 0.2)
			env.Spawn.flush(env.Clock.now())
			local n = #wildEvents(env)
			expect(n).toBe(1)
			run(env, 0.1)
			env.Spawn.flush(env.Clock.now()) -- 0,1 s plus tard : rien
			expect(#wildEvents(env)).toBe(n)
			env.Spawn.spawnPersonal(alice, env.Neb.pack(1, 0, 0), env.V3.new(0, 0, 130))
			run(env, 0.2)
			env.Spawn.flush(env.Clock.now())
			expect(#env.h:sentTo(alice, "WildEvent")).toBe(1)
			expect(#env.h:sentTo(bob, "WildEvent")).toBe(0)
			local payload = env.h:sentTo(alice, "WildEvent")[1][1]
			expect(payload.spawns[1].personal).toBe(true)
			for _, e in wildEvents(env) do
				for _, s in e.spawns do
					expect(s.personal).toBeNil()
				end
			end
		end)

		it("codes et origines invalides ignorés sans erreur", function()
			local env = setup()
			local now = env.Clock.now()
			local out = env.Spawn.spawnLoose(
				{ 0, 99999, "x", 0 / 0, env.Neb.pack(1, 0, 0) },
				{ env.V3.new(0 / 0, 0, 0) },
				now
			)
			expect(#out).toBe(1)
			expect(out[1].x == out[1].x).toBe(true)
			expect(#env.Spawn.spawnLoose("bad", {}, now)).toBe(0)
			expect(env.Spawn.spawnPersonal({ UserId = 1 }, -3, env.V3.new(0, 0, 0))).toBe(0)
			expect(
				env.Spawn.spawnPersonal({ UserId = 1 }, env.Neb.pack(1, 0, 0), env.V3.new(math.huge, 0, 0))
			).toBe(0)
		end)
	end)

	describe("SpawnService › accueil", function()
		it("3 Puffkins personnels devant la porte, dans le port sûr", function()
			local env = setup()
			local p = env.h:addPlayer({ userId = 1 })
			env.slots[p] = 4
			local ids = env.Spawn.spawnWelcome(p)
			expect(#ids).toBe(env.B.Spawn.WelcomeCount)
			local list = env.Spawn.snapshotFor(p)
			expect(#list).toBe(3)
			for _, s in list do
				local species = env.Neb.unpack(s.code)
				expect(species).toBe(env.Neb.Named.Welcome)
				expect(s.personal).toBe(true)
				expect(env.WL.inOwnHarbor(4, env.V3.new(s.x, 0, s.z))).toBe(true)
			end
			expect(#env.Spawn.snapshotFor({ UserId = 2 })).toBe(0)
			-- pas de Nid : rien
			local q = env.h:addPlayer({ userId = 2 })
			expect(#env.Spawn.spawnWelcome(q)).toBe(0)
			-- hors plafonds
			expect(env.Spawn.aliveCount("meadow")).toBe(0)
		end)

		it(
			"Rare garanti : personnel à 60-90 studs du centre, sauf si un Rare public est dans la Clairière",
			function()
				local env = setup()
				local p = env.h:addPlayer({ userId = 1 })
				env.slots[p] = 2
				local id = env.Spawn.spawnGuaranteedRare(p)
				expect(id ~= nil).toBe(true)
				local s = env.Spawn.snapshotFor(p)[1]
				local r = math.sqrt(s.x ^ 2 + s.z ^ 2)
				expect(r >= env.B.Spawn.GuaranteedRareMin and r <= env.B.Spawn.GuaranteedRareMax).toBe(true)
				expect(rarityOfCode(env, s.code)).toBe(3)
				expect(s.personal).toBe(true)
				-- un Rare public dans la Clairière : rien
				local env2 = setup()
				local q = env2.h:addPlayer({ userId = 1 })
				env2.Spawn.setActivePlayers(12)
				env2.Spawn.setModifiers({
					formChance = 0,
					intervalDiv = 1,
					capMult = 1,
					featured = 17,
					featuredChance = 1,
					starbornChance = 0,
				})
				run(env2, 2)
				expect(env2.Spawn.spawnGuaranteedRare(q)).toBeNil()
			end
		)

		it(
			"accueil dirigé : ≥ 6 Communs personnels près du Nid, vérifié chaque seconde, arrêté sur demande",
			function()
				local env = setup()
				local p = env.h:addPlayer({ userId = 1 })
				env.slots[p] = 1
				env.Spawn.setDirected(p, true)
				run(env, 0.1)
				local center = env.WL.nestCenter(1)
				-- Communs visibles par le joueur (publics ou personnels) près de son Nid
				local function nearCommons(personalOnly)
					local n = 0
					for _, s in env.Spawn.snapshotFor(p) do
						local d = math.sqrt((s.x - center.X) ^ 2 + (s.z - center.Z) ^ 2)
						if
							(s.personal or not personalOnly)
							and d < env.B.Spawn.DirectedRadius
							and rarityOfCode(env, s.code) == 1
						then
							n += 1
						end
					end
					return n
				end
				expect(nearCommons(false) >= env.B.Spawn.DirectedCommons).toBe(true)
				expect(nearCommons(true) >= 1).toBe(true)
				-- le joueur les attrape : le serveur en remet
				for _, s in env.Spawn.snapshotFor(p) do
					env.Spawn.consume(s.id, p)
				end
				run(env, 1.1)
				expect(nearCommons(false) >= env.B.Spawn.DirectedCommons).toBe(true)
				env.Spawn.setDirected(p, false)
				for _, s in env.Spawn.snapshotFor(p) do
					env.Spawn.consume(s.id, p)
				end
				run(env, 2)
				expect(nearCommons(true)).toBe(0)
			end
		)

		it("départ : apparitions personnelles retirées (PlayerRemoving), jamais envoyées", function()
			local env = setup()
			local p = env.h:addPlayer({ userId = 1 })
			env.slots[p] = 3
			env.Spawn.spawnWelcome(p)
			env.Spawn.setDirected(p, true)
			expect(env.Spawn.aliveCount()).toBe(3)
			env.h:removePlayer(p)
			expect(env.Spawn.aliveCount()).toBe(0)
			run(env, 2)
			env.Spawn.flush(env.Clock.now(), true)
			expect(#env.h:sentTo(p, "WildEvent")).toBe(0)
			for _, w in env.Spawn.snapshotFor({ UserId = 1 }) do
				expect(w.personal).toBeNil() -- seulement des apparitions publiques de zone
			end
		end)

		it("snapshotFor : publics + ses personnels, champs réseau complets", function()
			local env = setup()
			local a = env.h:addPlayer({ userId = 1 })
			local b = env.h:addPlayer({ userId = 2 })
			env.Spawn.setActivePlayers(12)
			run(env, 1)
			env.Spawn.spawnPersonal(a, env.Neb.pack(1, 0, 0), env.V3.new(0, 0, 130))
			local publicCount = #allPublic(env)
			expect(#env.Spawn.snapshotFor(a)).toBe(publicCount + 1)
			expect(#env.Spawn.snapshotFor(b)).toBe(publicCount)
			local s = env.Spawn.snapshotFor(b)[1]
			for _, key in { "id", "code", "x", "z", "seed", "t0", "life" } do
				expect(type(s[key])).toBe("number")
			end
		end)
	end)
end
