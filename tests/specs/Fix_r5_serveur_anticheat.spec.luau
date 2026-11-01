--!nocheck
-- Correctifs r5 « serveur anti-triche » (MoveCheck, CongaService, EventService, NestService) :
--   1. Budget d'action de MoveCheck (seau à jetons) : la règle de rafale d'r3/r4 ne regardait
--      qu'UN tick et redonnait la tolérance de 4 studs à chaque tick. Un bond (1 s d'arrêt puis
--      19 à 58 studs) suivi d'un petit pas agissait au tick SUIVANT (coupe, capture, ramassage,
--      vol et encaissement de la Comète, anneau de la Balise), et une chaîne de pas de 6 à 9 studs
--      agissait sans aucune rafale. Désormais la dette survit au tick : chaque exploit ci-dessous
--      est BLOQUÉ (0 infraction, jamais de retour : la tolérance des gels réseau est inchangée),
--      chaque contrôle honnête reste propre (paquets groupés, Dash, sauts sur la pente,
--      réapparition, rattrapage par SA porte, anneau à pied).
--   2. Gel réseau honnête de 0,7 à 1,5 s en courant : la fenêtre soutenue mesurait depuis la
--      position figée avec des instants frais → retour, 3 s de restriction, « instable » et un
--      avertissement vers l'exclusion des classements. Plus maintenant ; la téléportation reste
--      détectée (MoveCheck.spec « tricheurs » inchangé).
--   3. Récompenses de proximité de la Comète : jamais sur un point d'arrivée en rafale (ni en
--      dette de budget), le filet sans acteurs ne lit plus la racine brute.
--   4. Port sûr de NestService : un bond dans son port puis Zen dans le même tick est refusé
--      (neutre), un nouvel essai une fois le budget remboursé passe.
-- Contrat plus strict (pas un affaiblissement) : 5 tests d'r3/r4 qui faisaient agir le joueur au
-- tick suivant un bond attendent maintenant le remboursement du budget.
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

	-- chaîne de pas de `stepLen` studs vers `to`, un par tick ; rend le numéro du tick de la
	-- première coupe (nil : aucune) et le nombre de ticks en rafale
	local function chain(env, p, to, stepLen, maxTicks)
		local firstSnipTick = nil
		local bursts = 0
		local before = #snips(env)
		for i = 1, maxTicks do
			local pos = rootOf(p).Position
			local d = to - pos
			local done = d.Magnitude <= stepLen
			env.h:moveTo(p, if done then to else pos + d.Unit * stepLen)
			tick(env)
			if env.MoveCheck.lastWasBurst(p) then
				bursts += 1
			end
			if firstSnipTick == nil and #snips(env) > before then
				firstSnipTick = i
			end
			if done then
				break
			end
		end
		return firstSnipTick, bursts
	end

	-- =========================================================================================
	-- 1. Exploits bloqués (doublures, même montage que Fix_r4_serveur_3)
	-- =========================================================================================

	describe("Fix r5 serveur anti-triche › budget d'action : exploits bloqués", function()
		it(
			"bond seul (27 studs ; Dash + 42 ; Foulée max + Dash + 57) : aucune coupe, ni au tick suivant",
			function()
				for _, case in
					{
						{ from = 46, to = 73, stride = 0, dash = false },
						{ from = 39, to = 81, stride = 0, dash = true },
						{ from = 30, to = 87, stride = 20, dash = true },
					}
				do
					local env = setup()
					local A, B = lineScenario(env, env.V3.new(66, 3, case.from))
					env.profiles[1].upgrades.stride = case.stride
					tick(env, 12)
					if case.dash then
						env.h:fireServer("ReplicatedStorage.Remotes.Dash", A)
					end
					local v0 = env.MoveCheck.violations(A)
					env.h:moveTo(A, env.V3.new(66, 3, case.to))
					tick(env)
					expect(env.MoveCheck.lastWasBurst(A)).toBe(true)
					-- le tick suivant, un petit pas sur place : toujours rien
					env.h:moveTo(A, env.V3.new(66, 3, case.to - 1))
					tick(env)
					expect(env.MoveCheck.lastWasBurst(A)).toBe(true)
					expect(#snips(env)).toBe(0)
					expect(env.Conga.lineLength(B)).toBe(10)
					expect(env.MoveCheck.violations(A)).toBe(v0)
				end
			end
		)

		it(
			"V1 bond puis action : 19 studs jusqu'à 4 studs de la file, puis 6 studs à travers : aucune coupe",
			function()
				local env = setup()
				local A, B = lineScenario(env, env.V3.new(66, 3, 37))
				tick(env, 12)
				local v0 = env.MoveCheck.violations(A)
				env.h:moveTo(A, env.V3.new(66, 3, 56))
				tick(env)
				expect(env.MoveCheck.lastWasBurst(A)).toBe(true)
				env.h:moveTo(A, env.V3.new(66, 3, 62)) -- traverse la file (z = 60) au tick suivant
				tick(env)
				expect(env.MoveCheck.lastWasBurst(A)).toBe(true)
				expect(env.MoveCheck.canAct(A, env.Clock.now())).toBe(false)
				expect(#snips(env)).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(10)
				expect(env.MoveCheck.violations(A) - v0).toBe(0)
			end
		)

		it(
			"V2 chaîne : 4 pas de 6,25 studs (62 studs/s) après 1,2 s d'arrêt : aucune coupe, 0 infraction",
			function()
				local env = setup()
				local A, B = lineScenario(env, env.V3.new(66, 3, 37))
				tick(env, 12)
				local v0 = env.MoveCheck.violations(A)
				local first, bursts = chain(env, A, env.V3.new(66, 3, 62), 6.25, 10)
				expect(first).toBeNil()
				expect(bursts >= 3).toBe(true) -- seul le premier pas tient dans la règle d'un tick
				expect(env.Conga.lineLength(B)).toBe(10)
				expect(env.MoveCheck.violations(A) - v0).toBe(0)
			end
		)

		it("V3 chaîne au Dash, Foulée max : 9,2 studs par tick sur ≈ 55 studs : aucune coupe", function()
			local env = setup()
			local A, B = lineScenario(env, env.V3.new(66, 3, 7))
			env.profiles[1].upgrades.stride = 20
			tick(env, 12)
			env.h:fireServer("ReplicatedStorage.Remotes.Dash", A)
			local v0 = env.MoveCheck.violations(A)
			local first, bursts = chain(env, A, env.V3.new(66, 3, 62), 9.2, 10)
			expect(first).toBeNil()
			expect(bursts >= 3).toBe(true)
			expect(env.Conga.lineLength(B)).toBe(10)
			expect(env.MoveCheck.violations(A) - v0).toBe(0)
		end)

		it(
			"capture au tick qui suit un bond (bond à 6 studs d'un Nebby, puis pas dessus) : refusée",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				local start = env.V3.new(-60, 3, 40)
				local nebby = env.V3.new(-60, 3, 67)
				place(env, p, start)
				tick(env, 40)
				env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), nebby)
				tick(env, 12)
				expect(env.Conga.lineLength(p)).toBe(0)
				-- 21 studs : à 6 studs du Nebby, hors de portée de l'Attrait (5 + 0,75)
				env.h:moveTo(p, nebby - env.V3.new(0, 0, 6))
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.Conga.lineLength(p)).toBe(0)
				env.h:moveTo(p, nebby) -- 6 studs de plus (règle d'un tick) : sur le Nebby
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(env.Conga.lineLength(p)).toBe(0)
				expect(env.MoveCheck.violations(p)).toBe(0)
				-- immobile sur le Nebby : capture dès que le budget est remboursé (< 1,5 s), jamais avant
				local waited = 0
				while env.Conga.lineLength(p) == 0 and waited < 30 do
					expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
					tick(env)
					waited += 1
				end
				expect(env.Conga.lineLength(p)).toBe(1)
				expect(waited >= 4 and waited <= 15).toBe(true)
			end
		)

		it(
			"V9 bond jusqu'au bord de l'anneau de la Balise, puis pas dans l'anneau : pas d'encaissement",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(-38, 3, 9))
				tick(env)
				feed(env, p, 3)
				tick(env, 40)
				env.beacon = true
				tick(env, 12)
				env.h:moveTo(p, env.V3.new(-17.5, 3, 9))
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				env.h:moveTo(p, env.V3.new(-12, 3, 9))
				tick(env)
				expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
				expect(#lineOps(env, 1, "bank")).toBe(0)
				expect(#env.beaconLog).toBe(0)
				expect(env.Conga.lineLength(p)).toBe(3)
				expect(env.MoveCheck.violations(p)).toBe(0)
			end
		)

		it(
			"canAct : faux en dette ou restreint, vrai après remboursement ; joueur inconnu : vrai",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(-60, 3, 40))
				tick(env, 40)
				expect(env.MoveCheck.canAct(p, env.Clock.now())).toBe(true)
				tick(env, 12)
				env.h:moveTo(p, env.V3.new(-60, 3, 67))
				tick(env)
				expect(env.MoveCheck.canAct(p, env.Clock.now())).toBe(false)
				tick(env, 12)
				expect(env.MoveCheck.canAct(p, env.Clock.now())).toBe(true)
				-- restreint après un retour (téléportations répétées)
				for _ = 1, 3 do
					env.h:moveTo(p, env.V3.new(60, 3, -60))
					tick(env)
				end
				expect(env.MoveCheck.isRestricted(p, env.Clock.now())).toBe(true)
				expect(env.MoveCheck.canAct(p, env.Clock.now())).toBe(false)
				expect(env.MoveCheck.canAct({ Name = "Nobody" }, env.Clock.now())).toBe(true)
			end
		)
	end)

	-- =========================================================================================
	-- 1 bis. Vraie Comète (serveur complet, Bots)
	-- =========================================================================================

	local TC = 1800000000 -- impact de Comète (:00)

	local function cometWorld()
		local w = Bots.boot(Harness, {
			t0 = TC - 45,
			before = function(w)
				for _, id in { 801, 802, 803 } do
					Bots.saveProfile(w, id, Bots.veteranProfile(w, TC - 45))
				end
			end,
		})
		local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		local A = w.h:addPlayer({ userId = 801, name = "Ana" })
		local C = w.h:addPlayer({ userId = 802, name = "Cy" })
		local H = w.h:addPlayer({ userId = 803, name = "Honest" })
		w.h:settle(3)
		Bots.frames(10)
		local slot = w.EC.nextComet(Bots.now())
		local impact = w.EC.cometImpact(slot.id)
		local function around(angle, r)
			return Bots.ground(impact.X + math.cos(angle) * r, impact.Z + math.sin(angle) * r)
		end
		return w, MoveCheck, A, C, H, impact, around
	end

	-- chaîne de pas vers `target` ; rend le numéro du tick où `done()` devient vrai (nil : jamais)
	local function chainTo(w, p, target, stepLen, maxTicks, done)
		for i = 1, maxTicks do
			local pos = Bots.rootOf(p).Position
			local d = w.V3.new(target.X - pos.X, 0, target.Z - pos.Z)
			local last = d.Magnitude <= stepLen
			local nxt = if last then target else pos + d.Unit * stepLen
			w.h:moveTo(p, Bots.ground(nxt.X, nxt.Z))
			Bots.frame()
			if done() then
				return i
			end
			if last then
				break
			end
		end
		return nil
	end

	local function waitImpact(w)
		while Bots.now() < TC + 0.05 do
			Bots.frame()
		end
	end

	-- A ramasse honnêtement la Comète (à pied), puis l'immunité du porteur s'écoule
	local function honestPickup(w, A, impact)
		for _ = 1, 40 do
			Bots.stepToward(A, Bots.ground(impact.X, impact.Z))
			Bots.frame()
			if w.Event.carrier() == A then
				break
			end
		end
		expect(w.Event.carrier()).toBe(A)
	end

	describe("Fix r5 serveur anti-triche › vraie Comète (serveur complet)", function()
		it(
			"K1 course au ramassage : bond de 27 studs puis pas ; le joueur honnête à 12 studs gagne",
			function()
				local w, MoveCheck, A, C, H, impact, around = cometWorld()
				expect(
					Bots.walkAll(
						{ [A] = around(math.pi, 27), [H] = around(0, 12), [C] = around(-math.pi / 2, 40) },
						400
					)
				).toBe(true)
				waitImpact(w)
				Bots.frames(10) -- 1 s à l'arrêt
				expect(w.Event.snapshot().comet.phase).toBe("ground")
				local v0 = MoveCheck.violations(A)
				-- tick 1 : A bondit à côté de la Comète ; H part à pied (15 studs/s)
				w.h:moveTo(A, Bots.ground(impact.X - 4.5, impact.Z))
				Bots.stepToward(H, Bots.ground(impact.X, impact.Z))
				Bots.frame()
				expect(MoveCheck.lastWasBurst(A)).toBe(true)
				expect(w.Event.carrier()).toBeNil()
				-- tick 2 : A fait 1,5 stud (dans le rayon de ramassage) : toujours en dette
				w.h:moveTo(A, Bots.ground(impact.X - 3, impact.Z))
				Bots.stepToward(H, Bots.ground(impact.X, impact.Z))
				Bots.frame()
				expect(w.Event.carrier() ~= A).toBe(true)
				-- A reste là ; H continue : H arrive avant que la dette de A soit remboursée
				for _ = 1, 20 do
					if w.Event.carrier() ~= nil then
						break
					end
					Bots.stepToward(H, Bots.ground(impact.X, impact.Z))
					Bots.frame()
				end
				expect(w.Event.carrier()).toBe(H)
				expect(MoveCheck.violations(A) - v0).toBe(0)
				expect(#Bots.problems()).toBe(0)
			end
		)

		it("K2 ramassage par chaîne (4 × 6,2 studs depuis 27 studs) : rien pendant la chaîne", function()
			local w, MoveCheck, A, C, H, impact, around = cometWorld()
			expect(
				Bots.walkAll(
					{ [A] = around(math.pi, 27), [H] = around(0, 40), [C] = around(-math.pi / 2, 40) },
					400
				)
			).toBe(true)
			waitImpact(w)
			Bots.frames(10)
			local v0 = MoveCheck.violations(A)
			local got = chainTo(w, A, Bots.ground(impact.X, impact.Z), 6.2, 8, function()
				return w.Event.carrier() == A
			end)
			expect(got).toBeNil()
			expect(w.Event.carrier()).toBeNil()
			expect(MoveCheck.violations(A) - v0).toBe(0)
			-- immobile sur la Comète, A la ramasse une fois sa dette remboursée
			for _ = 1, 20 do
				if w.Event.carrier() ~= nil then
					break
				end
				Bots.frame()
			end
			expect(w.Event.carrier()).toBe(A)
		end)

		it("K3 vol : bond à côté du porteur, puis pas sur lui au tick suivant : pas de vol", function()
			local w, MoveCheck, A, C, H, impact, around = cometWorld()
			expect(
				Bots.walkAll(
					{ [A] = around(math.pi, 27), [C] = around(-math.pi / 2, 26), [H] = around(0, 40) },
					400
				)
			).toBe(true)
			waitImpact(w)
			honestPickup(w, A, impact)
			Bots.frames(25) -- immunité du porteur écoulée ; C immobile depuis plus d'1 s
			local apos = Bots.rootOf(A).Position
			local v0 = MoveCheck.violations(C)
			w.h:moveTo(C, Bots.ground(apos.X, apos.Z - 6))
			Bots.frame()
			expect(MoveCheck.lastWasBurst(C)).toBe(true)
			expect(w.Event.carrier()).toBe(A)
			w.h:moveTo(C, Bots.ground(apos.X, apos.Z - 2))
			Bots.frame()
			expect(w.Event.carrier()).toBe(A)
			expect(MoveCheck.violations(C) - v0).toBe(0)
		end)

		it(
			"K4 vol par chaîne (6,2 studs par tick depuis ≈ 26 studs) : pas de vol pendant la chaîne",
			function()
				local w, MoveCheck, A, C, H, impact, around = cometWorld()
				expect(
					Bots.walkAll(
						{ [A] = around(math.pi, 27), [C] = around(-math.pi / 2, 26), [H] = around(0, 40) },
						400
					)
				).toBe(true)
				waitImpact(w)
				honestPickup(w, A, impact)
				Bots.frames(25)
				local apos = Bots.rootOf(A).Position
				local v0 = MoveCheck.violations(C)
				local got = chainTo(w, C, Bots.ground(apos.X, apos.Z), 6.2, 8, function()
					return w.Event.carrier() == C
				end)
				expect(got).toBeNil()
				expect(w.Event.carrier()).toBe(A)
				expect(MoveCheck.violations(C) - v0).toBe(0)
			end
		)

		it(
			"K5 porteur : bond à 4 studs de sa porte puis traversée au tick suivant : pas d'encaissement ; à pied, si",
			function()
				local w, MoveCheck, A, C, H, impact, around = cometWorld()
				expect(Bots.walkAll({
					[A] = around(math.pi, 20),
					[C] = around(math.pi * 0.6, 40),
					[H] = around(math.pi * 1.4, 40),
				}, 400)).toBe(true)
				waitImpact(w)
				honestPickup(w, A, impact)
				local gate = w.WL.gateCFrame(w.Nest.slotOf(A))
				local look = gate.LookVector
				local g = w.V3.new(gate.Position.X, 0, gate.Position.Z)
				local before = g + look * 23
				for _ = 1, 600 do
					if Bots.stepToward(A, Bots.ground(before.X, before.Z), 1.3) then
						break
					end
					Bots.frame()
				end
				Bots.frames(12) -- 1,2 s à l'arrêt, à 23 studs devant sa porte
				expect(w.Event.carrier()).toBe(A)
				local v0 = MoveCheck.violations(A)
				local p1 = g + look * 4
				w.h:moveTo(A, Bots.ground(p1.X, p1.Z))
				Bots.frame()
				expect(MoveCheck.lastWasBurst(A)).toBe(true)
				w.h:moveTo(A, Bots.ground(g.X, g.Z)) -- à travers la porte
				Bots.frame()
				expect(w.Event.snapshot().comet.phase).toBe("carried")
				expect(w.Event.carrier()).toBe(A)
				-- la Comète suit le porteur même pendant la dette (l'orbe ne se fige pas)
				local snap = w.Event.snapshot().comet
				expect(math.abs(snap.x - g.X) < 0.5 and math.abs(snap.z - g.Z) < 0.5).toBe(true)
				expect(MoveCheck.violations(A) - v0).toBe(0)
				-- contrôle : budget remboursé (arrêt), ressortir puis rentrer à pied encaisse
				local out = g + look * 8
				for _ = 1, 15 do
					Bots.stepToward(A, Bots.ground(out.X, out.Z), 0.5)
					Bots.frame()
				end
				expect(MoveCheck.canAct(A, Bots.now())).toBe(true)
				expect(w.Event.carrier()).toBe(A)
				for _ = 1, 40 do
					if Bots.stepToward(A, Bots.ground(g.X, g.Z), 1.3) then
						Bots.frame()
						break
					end
					Bots.frame()
				end
				Bots.frame()
				expect(w.Event.snapshot().comet.phase).toBe("banked")
			end
		)
	end)

	-- =========================================================================================
	-- 2. Joueurs honnêtes : jamais de rafale, d'infraction ni d'acteur refusé
	-- =========================================================================================

	local function honestRun(env, p, ticks, stepFn)
		local v0 = env.MoveCheck.violations(p)
		local bursts, invalid = 0, 0
		for i = 1, ticks do
			stepFn(i)
			tick(env)
			if env.MoveCheck.lastWasBurst(p) then
				bursts += 1
			end
			local a = actorIn(env.cometActors, p)
			if a == nil or not a.valid then
				invalid += 1
			end
		end
		return bursts, env.MoveCheck.violations(p) - v0, invalid
	end

	describe("Fix r5 serveur anti-triche › joueurs honnêtes", function()
		it(
			"Hn1 paquets groupés par deux : marche 16 (0 ; 3,2), Dash 26 (0 ; 5,2), Foulée max + Dash 36 (0 ; 7,2)",
			function()
				local env = setup()
				local p, data = join(env, 1, 1)
				place(env, p, env.V3.new(-100, 3, -20))
				tick(env, 40)
				local b, v, inv = honestRun(env, p, 40, function(i)
					if i % 2 == 0 then
						env.h:moveTo(p, rootOf(p).Position + env.V3.new(3.2, 0, 0))
					end
				end)
				expect(b + v + inv).toBe(0)
				tick(env, 15)
				env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
				b, v, inv = honestRun(env, p, 10, function(i)
					if i % 2 == 0 then
						env.h:moveTo(p, rootOf(p).Position + env.V3.new(5.2, 0, 0))
					end
				end)
				expect(b + v + inv).toBe(0)
				data.upgrades.stride = 20
				tick(env, 80)
				env.h:fireServer("ReplicatedStorage.Remotes.Dash", p)
				b, v, inv = honestRun(env, p, 10, function(i)
					if i % 2 == 0 then
						env.h:moveTo(p, rootOf(p).Position + env.V3.new(-7.2, 0, 0))
					end
				end)
				expect(b + v + inv).toBe(0)
			end
		)

		it("Hn2 paquets groupés par trois (0 ; 0 ; 4,8 à 16 : gigue de 0,3 s)", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(-100, 3, -20))
			tick(env, 40)
			local b, v, inv = honestRun(env, p, 30, function(i)
				if i % 3 == 0 then
					env.h:moveTo(p, rootOf(p).Position + env.V3.new(4.8, 0, 0))
				end
			end)
			expect(b + v + inv).toBe(0)
		end)

		it("Hn4 sauts (JumpPower 50) en marchant à 16 vers le centre, en montant la pente", function()
			local env = setup()
			local p = join(env, 1, 1)
			local x, z = -150, 0
			place(env, p, env.V3.new(x, env.WL.groundY(x, z) + 3, z))
			tick(env, 40)
			local tAir = 0
			local b, v, inv = honestRun(env, p, 60, function()
				x += 1.6
				tAir += 0.1
				local h = 50 * tAir - 0.5 * 196.2 * tAir * tAir
				if h < 0 then
					h = 0
					tAir = 0
				end
				env.h:moveTo(p, env.V3.new(x, env.WL.groundY(x, z) + 3 + h, z))
			end)
			expect(b + v + inv).toBe(0)
		end)

		it("réapparition : de nouveau à pied, il attrape tout de suite (aucune dette héritée)", function()
			local env = setup()
			local p = join(env, 1, 1)
			local home = env.V3.new(-60, 3, 40)
			place(env, p, home)
			tick(env, 40)
			-- rattrapage (gel réseau) juste avant de mourir : budget en dette
			tick(env, 12)
			env.h:moveTo(p, home + env.V3.new(0, 0, 25))
			tick(env)
			expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
			env.h:respawn(p)
			place(env, p, home) -- NestService : PivotTo + ServerMoved
			tick(env)
			env.Spawn.spawnPersonal(p, env.Neb.pack(1, 0, 0), home + env.V3.new(0, 0, 8))
			local b, v, inv = honestRun(env, p, 6, function()
				env.h:moveTo(p, rootOf(p).Position + env.V3.new(0, 0, 1.4))
			end)
			expect(b + v + inv).toBe(0)
			expect(env.Conga.lineLength(p)).toBe(1)
		end)

		it("rattrapage après un gel de 0,7 s qui traverse SA porte : encaissé, 0 infraction", function()
			local env = setup()
			local p = join(env, 1, 1)
			local gate = env.WL.gateCFrame(1)
			local look = gate.LookVector
			local g = env.V3.new(gate.Position.X, 3, gate.Position.Z)
			local start = g - look * 20
			place(env, p, start)
			tick(env)
			feed(env, p, 3)
			tick(env, 40)
			expect(env.Conga.lineLength(p)).toBe(3)
			-- marche vers la porte à 16 studs/s, gel de 0,7 s, puis rattrapage à travers la porte
			for _ = 1, 5 do
				env.h:moveTo(p, rootOf(p).Position + look * 1.6)
				tick(env)
			end
			tick(env, 7)
			env.h:moveTo(p, rootOf(p).Position + look * 12.8)
			tick(env)
			expect(env.MoveCheck.lastWasBurst(p)).toBe(true)
			expect(env.Conga.lineLength(p)).toBe(0)
			expect(#lineOps(env, 1, "bank")).toBe(1)
			expect(env.MoveCheck.violations(p)).toBe(0)
		end)

		it("anneau de la Balise à pied (budget plein) : encaissé", function()
			local env = setup()
			local p = join(env, 1, 1)
			place(env, p, env.V3.new(-38, 3, 9))
			tick(env)
			feed(env, p, 3)
			tick(env, 40)
			env.beacon = true
			tick(env, 12)
			walk(env, p, env.V3.new(-12, 3, 9), 14)
			local banks = lineOps(env, 1, "bank")
			expect(#banks).toBe(1)
			expect(banks[1].atBeacon).toBe(true)
			expect(#env.beaconLog).toBe(1)
			expect(env.MoveCheck.violations(p)).toBe(0)
		end)
	end)

	-- =========================================================================================
	-- 3. Gel réseau honnête en courant : ni retour, ni restriction, ni « instable », ni strike
	-- =========================================================================================

	describe("Fix r5 serveur anti-triche › gel réseau en courant", function()
		-- marche à 16 studs/s, gel de `freeze` ticks (position figée), rattrapage d'un coup, puis
		-- `after` ticks à 16 (ou à l'arrêt) ; rend les mesures
		local function freezeRun(freeze, walkOn)
			local env = setup()
			local p, data = join(env, 1, 1)
			local x, z = -160, 30
			place(env, p, env.V3.new(x, env.WL.groundY(x, z) + 3, z))
			tick(env, 40)
			local function go(d)
				x += d
				env.h:moveTo(p, env.V3.new(x, env.WL.groundY(x, z) + 3, z))
			end
			for _ = 1, 10 do
				go(1.6)
				tick(env)
			end
			local v0 = env.MoveCheck.violations(p)
			tick(env, freeze)
			go(1.6 * (freeze + 1))
			local pulledBack = false
			local noAction = 0
			for i = 0, 40 do
				if i > 0 and walkOn then
					go(1.6)
				end
				local expected = rootOf(p).Position
				tick(env)
				if (rootOf(p).Position - expected).Magnitude > 0.01 then
					pulledBack = true -- PivotTo du serveur (retour)
				end
				local a = actorIn(env.cometActors, p)
				if a == nil or not a.valid then
					noAction += 1
				end
			end
			return {
				violations = env.MoveCheck.violations(p) - v0,
				rewinds = env.MoveCheck.recentRewinds(p, env.Clock.now()),
				restricted = env.MoveCheck.isRestricted(p, env.Clock.now()),
				strikes = data.flags.strikes or 0,
				unstable = p:GetAttribute("Unstable") == true,
				pulledBack = pulledBack,
				noAction = noAction,
			}
		end

		it(
			"gels de 0,7 / 1,0 / 1,5 s : 0 infraction, aucun retour, aucun strike, jamais « instable »",
			function()
				-- dette ≈ 16 × (gel + 0,1) − 6,4 studs, remboursée à 0,8 stud par tick en courant à 16
				for _, case in
					{
						{ freeze = 7, maxNoAction = 10 },
						{ freeze = 10, maxNoAction = 16 },
						{ freeze = 15, maxNoAction = 26 },
					}
				do
					local r = freezeRun(case.freeze, true)
					expect(r.violations).toBe(0)
					expect(r.rewinds).toBe(0)
					expect(r.restricted).toBe(false)
					expect(r.strikes).toBe(0)
					expect(r.unstable).toBe(false)
					expect(r.pulledBack).toBe(false)
					expect(r.noAction <= case.maxNoAction).toBe(true)
				end
			end
		)

		it("arrêté après le rattrapage : de nouveau « agissant » en moins d'une seconde", function()
			for _, freeze in { 7, 10, 15 } do
				local r = freezeRun(freeze, false)
				expect(r.violations).toBe(0)
				expect(r.rewinds).toBe(0)
				expect(r.noAction <= 10).toBe(true)
			end
		end)

		it(
			"la téléportation reste détectée : 2 s d'arrêt puis 40 studs ; 28 studs puis 2 × vmax → retour",
			function()
				local env = setup()
				local p = join(env, 1, 1)
				place(env, p, env.V3.new(-100, 3, -20))
				tick(env, 40)
				tick(env, 20)
				local v0 = env.MoveCheck.violations(p)
				env.h:moveTo(p, rootOf(p).Position + env.V3.new(40, 0, 0))
				tick(env)
				expect(env.MoveCheck.violations(p)).toBe(v0 + 1)
				expect(actorIn(env.cometActors, p).valid).toBe(false)
				-- départ d'un arrêt avec tout le crédit (28 studs, accepté mais en rafale), puis course à
				-- 32 studs/s : la fenêtre allongée depuis le départ reste bornée à 1,5 × vmax
				local env2 = setup()
				local q = join(env2, 1, 1)
				place(env2, q, env2.V3.new(-100, 3, -20))
				tick(env2, 40)
				tick(env2, 20)
				env2.h:moveTo(q, rootOf(q).Position + env2.V3.new(28, 0, 0))
				tick(env2)
				expect(env2.MoveCheck.lastWasBurst(q)).toBe(true)
				expect(env2.MoveCheck.violations(q)).toBe(0)
				for _ = 1, 3 do
					env2.h:moveTo(q, rootOf(q).Position + env2.V3.new(3.2, 0, 0))
					tick(env2)
				end
				expect(env2.MoveCheck.violations(q)).toBe(3)
				expect(env2.MoveCheck.recentRewinds(q, env2.Clock.now())).toBe(1)
			end
		)
	end)

	-- =========================================================================================
	-- 4. Port sûr de NestService (serveur complet) : bond dans son port puis Zen → refusé
	-- =========================================================================================

	describe("Fix r5 serveur anti-triche › port sûr : pas sur un point d'arrivée en dette", function()
		it(
			"bond de 26 studs dans son port puis Zen : refus neutre ; à l'arrêt, budget remboursé : accepté",
			function()
				local T1 = 1800000000 + 1200
				local w = Bots.boot(Harness, {
					t0 = T1,
					before = function(w)
						Bots.saveProfile(w, 801, Bots.veteranProfile(w, T1))
					end,
				})
				local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
				local A = w.h:addPlayer({ userId = 801, name = "Ana" })
				w.h:settle(3)
				Bots.frames(10)
				local slot = w.Nest.slotOf(A)
				expect(slot > 0).toBe(true)
				local gate = Bots.gateOf(A)
				local inward = (w.WL.nestCenter(slot) - gate).Unit
				local outside = gate - inward * 26
				local landing = gate + inward * 0.5
				expect(w.WL.inOwnHarbor(slot, outside)).toBe(false)
				expect(w.WL.inOwnHarbor(slot, landing)).toBe(true)
				expect(Bots.walkAll({ [A] = outside }, 600)).toBe(true)
				Bots.frames(30) -- exemption terminée, 3 s à l'arrêt
				expect(w.Nest.inOwnHarbor(A)).toBe(false)
				local data = w.DS.get(A)
				expect(data.settings.zen == true).toBe(false)
				w.h:moveTo(A, Bots.ground(landing.X, landing.Z))
				Bots.frame()
				expect(MoveCheck.lastWasBurst(A)).toBe(true)
				expect(MoveCheck.violations(A)).toBe(0)
				local ok, reason = w.Nest.applySetting(A, "zen", true)
				expect(ok).toBe(false)
				expect(reason).toBe("feedback.notInHarbor")
				expect(data.settings.zen == true).toBe(false)
				-- immobile dans son port : le budget se rembourse, le même essai passe
				for _ = 1, 20 do
					if MoveCheck.canAct(A, Bots.now()) then
						break
					end
					Bots.frame()
				end
				expect(MoveCheck.canAct(A, Bots.now())).toBe(true)
				local ok2 = w.Nest.applySetting(A, "zen", true)
				expect(ok2).toBe(true)
				expect(data.settings.zen).toBe(true)
				expect(#Bots.problems()).toBe(0)
			end
		)
	end)
end
