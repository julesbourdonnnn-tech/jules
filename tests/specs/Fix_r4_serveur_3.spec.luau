--!nocheck
-- Correctifs r4 « serveur 3 » — CongaService :
--   1. Rafale de MoveCheck (troisième valeur de step) : un bond accepté mais plus long que la règle
--      d'UN tick du GDD §12.7 (vmax × dt × 1,5 + 4), typiquement 1 s d'immobilité puis 27 à 42 studs
--      en un tick, ne doit AGIR sur rien : ni coupe, ni capture, ni ramassage ou vol de Comète, ni
--      Gloomwisp, ni parade à l'anneau de la Balise. Seule SA porte est balayée (rattrapage honnête
--      après un gel réseau). CongaService ignorait cette valeur : l'acteur restait `valid`.
--      Contrat r5 (plus strict, Fix_r5_serveur_anticheat) : la rafale vient d'un budget d'action à
--      mémoire ; le tick qui SUIT le bond n'agit pas non plus, le joueur ré-agit une fois la dette
--      remboursée (arrêt ou marche lente), jamais au tick suivant.
--   2. Explosion de la Comète : 5 Épiques libres, 1 au plus par joueur (groupe "burst:<id>",
--      groupCap 1). Le plafond n'était vérifié qu'à la collecte des candidatures, avant toute
--      capture : un même joueur en attrapait 3 à 5 dans le même tick.
-- Les services des autres paquets sont des doublures (même montage que CongaService.spec), sauf
-- le scénario de la vraie Comète (serveur complet, Bots).
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 41
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."

	local function setup()
		local h = Harness.new()
		local env = {
			h = h,
			V3 = h.globals.Vector3,
			profiles = {},
			slotByUser = {},
			zen = {},
			rookie = {},
			crews = {},
			carrier = nil,
			truce = false,
			beacon = false,
			disabled = false,
			sweeps = {},
			glowLog = {},
			beaconLog = {},
			cometActors = nil,
			wispActors = nil,
		}
		h:require("ReplicatedStorage.Shared.Net").setup()
		env.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		env.Clock.freeze(T0)
		env.B = h:require("ReplicatedStorage.Shared.Config.Balance")
		env.Neb = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		env.F = h:require("ReplicatedStorage.Shared.Logic.Formulas")
		env.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		env.Schema = h:require("ServerScriptService.Server.Data.Schema")
		env.Signals = h:require("ServerScriptService.Server.Signals")
		env.MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck")

		local DS = h:require(S .. "DataService")
		DS.get = function(p)
			return env.profiles[p.UserId]
		end
		DS.markDirty = function() end

		local Nest = h:require(S .. "NestService")
		Nest.slotOf = function(p)
			return env.slotByUser[p.UserId] or 0
		end
		Nest.isZen = function(p)
			return env.zen[p.UserId] == true
		end
		Nest.snipsDisabled = function()
			return env.disabled
		end

		local Econ = h:require(S .. "EconomyService")
		Econ.setLineBanker = function() end
		Econ.paradeGlow = function(p, codes, atBeacon)
			return env.F.paradeGlow(codes, 1, env.zen[p.UserId] == true, atBeacon)
		end
		Econ.addGlow = function(p, amount, sku)
			env.profiles[p.UserId].glow += amount
			table.insert(env.glowLog, { player = p, amount = amount, sku = sku })
			return amount
		end
		Econ.addStardustCapped = function(_, amount)
			return amount
		end
		Econ.step = function() end

		local Atlas = h:require(S .. "AtlasService")
		Atlas.addNebbies = function(_, codes)
			local uids = {}
			for i in codes do
				uids[i] = "u" .. i
			end
			return uids
		end

		local Event = h:require(S .. "EventService")
		Event.step = function() end
		Event.stepComet = function(_, actors)
			env.cometActors = actors
		end
		Event.wispSweeps = function()
			return env.sweeps
		end
		Event.onWispSnip = function() end
		Event.stepWisps = function(_, actors)
			env.wispActors = actors
		end
		Event.flush = function() end
		Event.isTruce = function()
			return env.truce
		end
		Event.beaconOpen = function()
			return env.beacon
		end
		Event.onBeaconParade = function(p, n)
			table.insert(env.beaconLog, { player = p, n = n })
		end
		Event.isCarrier = function(p)
			return env.carrier == p
		end
		Event.dropComet = function() end
		Event.setActivePlayers = function() end
		Event.snapshot = function()
			return { t = env.Clock.now(), wisps = {}, snipsDisabled = env.disabled, activePlayers = 0 }
		end

		local Crew = h:require(S .. "CrewService")
		Crew.step = function() end
		Crew.crewOf = function(p)
			return env.crews[p.UserId] or 0
		end
		Crew.escortersOf = function()
			return {}
		end
		Crew.snapshot = function()
			return { crews = {} }
		end

		local Quest = h:require(S .. "QuestService")
		Quest.step = function() end
		Quest.isRookie = function(p)
			return env.rookie[p.UserId] == true
		end
		Quest.onSafeMoment = function() end

		h:require(S .. "LeaderboardService").step = function() end

		env.Spawn = h:require(S .. "SpawnService")
		env.Spawn.Init()
		env.Spawn.Start()
		-- pas d'apparitions de zone : seuls les Nebbies posés par le test existent
		env.Spawn.setModifiers({
			formChance = 0,
			intervalDiv = 1,
			capMult = 0,
			featuredChance = 0,
			starbornChance = 0,
		})
		env.Conga = h:require(S .. "CongaService")
		env.Conga.Init()
		env.Conga.Start()
		return env
	end

	local function tick(env, n)
		for _ = 1, n or 1 do
			env.Clock.advance(DT)
			env.Conga.tick(env.Clock.now())
		end
	end

	local function join(env, userId, slot)
		env.slotByUser[userId] = slot
		local data = env.Schema.defaults()
		env.profiles[userId] = data
		local p = env.h:addPlayer({ userId = userId, name = "P" .. userId })
		return p, data
	end

	local function rootOf(p)
		return p.Character.HumanoidRootPart
	end

	-- Déplacement imposé par le serveur (exemption MoveCheck au prochain pas)
	local function place(env, p, pos)
		env.h:moveTo(p, pos)
		env.Signals.ServerMoved:Fire(p)
	end

	-- Marche à vitesse constante jusqu'à `to` (un pas par tick)
	local function walk(env, p, to, speed)
		local step = (speed or 14) * DT
		for _ = 1, 2000 do
			local pos = rootOf(p).Position
			local d = to - pos
			if d.Magnitude <= step then
				env.h:moveTo(p, to)
				tick(env)
				return
			end
			env.h:moveTo(p, pos + d.Unit * step)
			tick(env)
		end
	end

	-- `n` Nebbies personnels sous les pieds du joueur, attrapés au tick suivant
	local function feed(env, p, n)
		local pos = rootOf(p).Position
		for _ = 1, n do
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), pos)
		end
		tick(env)
	end

	local function snips(env)
		local out = {}
		for _, e in env.h.log.allClientEvents do
			if e.remote == "SnipEvent" then
				table.insert(out, e.args[1])
			end
		end
		return out
	end

	local function lineOps(env, slot, kind)
		local out = {}
		for _, e in env.h.log.allClientEvents do
			if e.remote == "LineEvent" then
				for _, op in e.args[1] do
					if op.slot == slot and op.op == kind then
						table.insert(out, op)
					end
				end
			end
		end
		return out
	end

	local function actorIn(list, p)
		for _, a in list or {} do
			if a.player == p then
				return a
			end
		end
		return nil
	end

	local function near(a, b)
		return (a - b).Magnitude < 0.01
	end

	-- File de B (10 Nebbies, slot 2) le long de z = 60, de x = 40 à x = 80 ; A (slot 1) à `aPos`
	local function lineScenario(env, aPos)
		local A = join(env, 1, 1)
		local B, dataB = join(env, 2, 2)
		dataB.upgrades.conga = 7
		place(env, B, env.V3.new(40, 3, 60))
		place(env, A, aPos)
		tick(env)
		feed(env, B, 10)
		walk(env, B, env.V3.new(80, 3, 60))
		tick(env, 2)
		return A, B
	end

	-- =========================================================================================
	-- 1. Rafale : le tick n'agit sur rien
	-- =========================================================================================

	describe("Fix r4 serveur 3 › rafale (bond après immobilité) : le tick n'agit sur rien", function()
		it(
			"immobile 1,2 s puis 27 studs en un tick à travers une file : aucune coupe, 0 infraction",
			function()
				local env = setup()
				local start = env.V3.new(66, 3, 46)
				local landing = env.V3.new(66, 3, 73) -- 27 studs : la file de B est à z = 60
				local A, B = lineScenario(env, start)
				expect(env.Conga.lineLength(B)).toBe(10)
				tick(env, 12) -- 1,2 s à l'arrêt (exemption terminée depuis longtemps)
				local violations = env.MoveCheck.violations(A)
				env.h:moveTo(A, landing)
				tick(env)
				-- position acceptée (gel réseau toléré), mais rafale : aucune infraction, aucun retour
				expect(env.MoveCheck.lastWasBurst(A)).toBe(true)
				expect(env.MoveCheck.violations(A)).toBe(violations)
				expect(near(env.MoveCheck.lastValid(A), landing)).toBe(true)
				expect(near(rootOf(A).Position, landing)).toBe(true)
				-- l'acteur du tick est à la position acceptée, mais n'agit pas
				local actor = actorIn(env.cometActors, A)
				expect(actor.valid).toBe(false)
				expect(near(actor.pos, landing)).toBe(true)
				expect(near(actor.prev, start)).toBe(true)
				expect(#snips(env)).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(10)
				-- le tick suivant repart de la position d'arrivée : rien à couper là
				tick(env, 3)
				expect(#snips(env)).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(10)
				-- contrat r5 : budget d'action encore en dette juste après le bond ; à l'arrêt, il se
				-- rembourse en moins d'une seconde
				expect(env.MoveCheck.canAct(A, env.Clock.now())).toBe(false)
				tick(env, 10)
				expect(env.MoveCheck.canAct(A, env.Clock.now())).toBe(true)
				-- contrôle : la même traversée à pied coupe bien la file (la géométrie est la bonne)
				walk(env, A, start, 14)
				expect(#snips(env)).toBe(1)
				expect(env.Conga.lineLength(B) < 10).toBe(true)
				expect(env.MoveCheck.violations(A)).toBe(violations)
			end
		)

		it(
			"bond sur un Nebby sauvage : aucune capture au tick du bond ni au suivant ; une fois le budget remboursé, si",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				local start = env.V3.new(-60, 3, 40)
				local landing = env.V3.new(-60, 3, 67)
				place(env, p, start)
				tick(env, 40) -- exemption terminée
				env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), landing)
				tick(env, 12) -- 1,2 s à l'arrêt, hors de portée de l'Attrait
				expect(env.Conga.lineLength(p)).toBe(0)
				env.h:moveTo(p, landing)
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.MoveCheck.violations(p)).toBe(0)
				expect(env.Conga.lineLength(p)).toBe(0)
				-- contrat r5 : le tick suivant reste une rafale (dette de budget d'action) : toujours rien
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.Conga.lineLength(p)).toBe(0)
				-- rattrapage honnête (gel réseau) : immobile, la dette se rembourse en moins d'une seconde,
				-- puis il joue normalement d'où il est (capture au premier tick « agissant »)
				local waited = 1
				while env.MoveCheck.lastWasBurst(p) and waited < 30 do
					expect(env.Conga.lineLength(p)).toBe(0)
					tick(env)
					waited += 1
				end
				expect(waited <= 10).toBe(true)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(false)
				expect(env.Conga.lineLength(p)).toBe(1)
				expect(env.MoveCheck.violations(p)).toBe(0)
			end
		)

		it(
			"Comète et Gloomwisps : l'acteur d'un tick en rafale n'est jamais `valid` pour EventService",
			function()
				local env = setup()
				local p, data = join(env, 1, 1)
				data.upgrades.stride = 20 -- Foulée maximale : 26 studs/s
				local start = env.V3.new(-60, 3, 40)
				place(env, p, start)
				tick(env, 40)
				expect(actorIn(env.cometActors, p).valid).toBe(true)
				expect(actorIn(env.wispActors, p).valid).toBe(true)
				tick(env, 12) -- 1,2 s à l'arrêt
				-- Dash légitime (WalkSpeed relevé et noté par le serveur), puis 42 studs en un tick
				env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
				local violations = env.MoveCheck.violations(p)
				local landing = start + env.V3.new(0, 0, 42)
				env.h:moveTo(p, landing)
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.MoveCheck.violations(p)).toBe(violations)
				-- EventService (ramassage, vol, encaissement, Gloomwisps) ne lit que `valid`
				for _, list in { env.cometActors, env.wispActors } do
					local actor = actorIn(list, p)
					expect(actor.valid).toBe(false)
					expect(near(actor.pos, landing)).toBe(true)
				end
				-- contrat r5 : le tick suivant n'est pas `valid` non plus (dette de budget d'action)
				tick(env)
				expect(actorIn(env.cometActors, p).valid).toBe(false)
				expect(actorIn(env.wispActors, p).valid).toBe(false)
				-- immobile, la dette se rembourse en moins d'une seconde : de nouveau `valid`
				tick(env, 10)
				expect(actorIn(env.cometActors, p).valid).toBe(true)
				expect(actorIn(env.wispActors, p).valid).toBe(true)
				expect(env.MoveCheck.violations(p)).toBe(violations)
			end
		)

		it("anneau de la Balise : un bond qui le traverse n'encaisse pas ; à pied, si", function()
			local env = setup()
			local p, data = join(env, 1, 1)
			data.upgrades.stride = 20 -- Foulée maximale : 26 studs/s
			local west = env.V3.new(-20, 3, 9)
			local east = env.V3.new(20, 3, 9) -- 40 studs ; z = 9 : la corde traverse l'anneau
			place(env, p, west)
			tick(env)
			feed(env, p, 3)
			tick(env, 40)
			expect(env.Conga.lineLength(p)).toBe(3)
			env.beacon = true
			tick(env, 12)
			env.h:moveTo(p, east)
			tick(env)
			expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
			expect(env.MoveCheck.violations(p)).toBe(0)
			expect(env.Conga.lineLength(p)).toBe(3)
			expect(#lineOps(env, 1, "bank")).toBe(0)
			expect(#env.beaconLog).toBe(0)
			-- contrôle : le même trajet à pied encaisse à l'anneau
			walk(env, p, west, 10)
			expect(env.Conga.lineLength(p)).toBe(0)
			local banks = lineOps(env, 1, "bank")
			expect(#banks).toBe(1)
			expect(banks[1].atBeacon).toBe(true)
			expect(#env.beaconLog).toBe(1)
		end)

		it(
			"SA porte : une rafale qui la traverse encaisse toujours (rattrapage après un gel réseau)",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				local gate = env.WL.gateCFrame(1)
				local look = gate.LookVector
				local before = env.V3.new(gate.Position.X, 3, gate.Position.Z) - look * 10
				local after = env.V3.new(gate.Position.X, 3, gate.Position.Z) + look * 10
				expect(env.WL.inGateBox(1, before)).toBe(false)
				expect(env.WL.inGateBox(1, after)).toBe(false)
				place(env, p, before)
				tick(env)
				feed(env, p, 3)
				tick(env, 40)
				expect(env.Conga.lineLength(p)).toBe(3)
				env.beacon = true -- l'anneau ouvert ne change rien : la porte passe d'abord
				env.h:moveTo(p, after) -- 20 studs en un tick, à travers la boîte de la porte
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.MoveCheck.violations(p)).toBe(0)
				expect(env.Conga.lineLength(p)).toBe(0)
				local banks = lineOps(env, 1, "bank")
				expect(#banks).toBe(1)
				expect(banks[1].atBeacon).toBe(false)
			end
		)
	end)

	-- =========================================================================================
	-- 1 bis. Vraie Comète (serveur complet) : ramassage et vol refusés au tick du bond
	-- =========================================================================================

	describe("Fix r4 serveur 3 › rafale et vraie Comète (serveur complet)", function()
		it(
			"bond sur la Comète au sol : pas de ramassage ; bond à côté du porteur : pas de vol",
			function()
				local TC = 1800000000 -- impact de Comète (:00)
				local w = Bots.boot(Harness, {
					t0 = TC - 45,
					before = function(w)
						Bots.saveProfile(w, 801, Bots.veteranProfile(w, TC - 45))
						Bots.saveProfile(w, 802, Bots.veteranProfile(w, TC - 45))
					end,
				})
				local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
				local A = w.h:addPlayer({ userId = 801, name = "Ana" })
				local C = w.h:addPlayer({ userId = 802, name = "Cy" })
				w.h:settle(3)
				Bots.frames(10)
				local slot = w.EC.nextComet(Bots.now())
				expect(slot.impactAt).toBe(TC)
				local impact = w.EC.cometImpact(slot.id)
				local function around(angle, r)
					return Bots.ground(impact.X + math.cos(angle) * r, impact.Z + math.sin(angle) * r)
				end
				-- départs à 27 studs de l'impact, de part et d'autre (sol plat, hors de l'anneau)
				local startA, startC = around(math.pi, 27), around(-math.pi / 2, 27)
				expect(Bots.walkAll({ [A] = startA, [C] = startC }, 400)).toBe(true)
				while Bots.now() < TC + 0.25 do
					Bots.frame()
				end
				expect(w.Event.snapshot().comet.phase).toBe("ground")
				Bots.frames(12) -- 1,2 s à l'arrêt
				local violationsA = MoveCheck.violations(A)
				-- A : 27 studs en un tick, droit sur la Comète
				w.h:moveTo(A, Bots.ground(impact.X, impact.Z))
				Bots.frame()
				expect(MoveCheck.lastWasBurst(A)).toBe(true)
				expect(MoveCheck.violations(A)).toBe(violationsA)
				expect(w.Event.carrier()).toBeNil()
				expect(w.Event.snapshot().comet.phase).toBe("ground")
				-- contrat r5 : le tick suivant, il est sur la Comète mais encore en dette de budget
				-- d'action : toujours pas de ramassage
				Bots.frame()
				expect(MoveCheck.lastWasBurst(A)).toBe(true)
				expect(w.Event.carrier()).toBeNil()
				-- immobile, la dette se rembourse en moins d'une seconde : ramassage normal
				local waited = 1
				while w.Event.carrier() == nil and waited < 30 do
					Bots.frame()
					waited += 1
				end
				expect(waited <= 11).toBe(true)
				expect(w.Event.carrier()).toBe(A)
				expect(MoveCheck.violations(A)).toBe(violationsA)
				-- immunité du porteur (2 s) écoulée, C immobile depuis plus d'1 s
				Bots.frames(25)
				expect(w.Event.carrier()).toBe(A)
				local violationsC = MoveCheck.violations(C)
				-- C : ≈ 25 studs en un tick, à 1,5 stud du porteur
				w.h:moveTo(C, Bots.ground(impact.X, impact.Z - 1.5))
				Bots.frame()
				expect(MoveCheck.lastWasBurst(C)).toBe(true)
				expect(MoveCheck.violations(C)).toBe(violationsC)
				expect(w.Event.carrier()).toBe(A)
				expect(#Bots.problems()).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	-- 2. Explosion de la Comète : 1 Épique au plus par joueur, même dans un seul tick
	-- =========================================================================================

	describe("Fix r4 serveur 3 › explosion de la Comète : 1 Épique par joueur dans un tick", function()
		local function epicCodes(env, n)
			local species = env.Neb.speciesOfRarity(4) -- Épique
			local codes = {}
			for i = 1, n do
				table.insert(codes, env.Neb.pack(species[(i - 1) % #species + 1], 0, 0))
			end
			return codes
		end

		local function burstAt(env, center, id)
			local from = {}
			for i = 1, 5 do
				from[i] = center
			end
			-- même appel qu'EventService.burstComet (étourdis 1,2 s, aucune priorité)
			return env.Spawn.spawnLoose(epicCodes(env, 5), from, env.Clock.now(), {
				group = "burst:" .. id,
				groupCap = 1,
			})
		end

		local function wildsAround(env, center)
			return #env.Spawn.query(center, 20, env.Clock.now())
		end

		it("Attrait 12 au point d'explosion : exactement 1 Épique, les 4 autres restent", function()
			local env = setup()
			local p, data = join(env, 1, 1)
			data.upgrades.lure = 12
			data.upgrades.conga = 7 -- place pour 10
			local center = env.V3.new(60, 3, 40)
			place(env, p, center)
			tick(env, 35)
			local spawns = burstAt(env, env.V3.new(center.X, 0.1, center.Z), 1)
			expect(#spawns).toBe(5)
			tick(env, 30) -- étourdissement (1,2 s) et dispersion terminés
			expect(env.Conga.lineLength(p)).toBe(1)
			expect(wildsAround(env, center)).toBe(4)
		end)

		it("deux joueurs au même point : 1 Épique chacun, dans le même tick", function()
			local env = setup()
			local A, dataA = join(env, 1, 1)
			local B, dataB = join(env, 2, 2)
			for _, data in { dataA, dataB } do
				data.upgrades.lure = 12
				data.upgrades.conga = 7
			end
			local center = env.V3.new(60, 3, 40)
			place(env, A, center)
			place(env, B, center + env.V3.new(1.5, 0, 0))
			tick(env, 35)
			burstAt(env, env.V3.new(center.X, 0.1, center.Z), 2)
			local first = nil
			for i = 1, 30 do
				tick(env)
				local a, b = env.Conga.lineLength(A), env.Conga.lineLength(B)
				if first == nil and (a > 0 or b > 0) then
					first = i
					-- premier tick de capture : un Épique refusé (plafond) reste pour l'autre joueur
					expect(a).toBe(1)
					expect(b).toBe(1)
				end
			end
			expect(first ~= nil).toBe(true)
			expect(env.Conga.lineLength(A)).toBe(1)
			expect(env.Conga.lineLength(B)).toBe(1)
			expect(wildsAround(env, center)).toBe(3)
		end)

		it(
			"le plafond ne vaut que pour son groupe : une autre explosion rapporte un autre Épique",
			function()
				local env = setup()
				local p, data = join(env, 1, 1)
				data.upgrades.lure = 12
				data.upgrades.conga = 7
				local center = env.V3.new(60, 3, 40)
				place(env, p, center)
				tick(env, 35)
				burstAt(env, env.V3.new(center.X, 0.1, center.Z), 3)
				tick(env, 30)
				expect(env.Conga.lineLength(p)).toBe(1)
				burstAt(env, env.V3.new(center.X, 0.1, center.Z), 4)
				tick(env, 30)
				expect(env.Conga.lineLength(p)).toBe(2)
			end
		)
	end)
end
