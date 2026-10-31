--!nocheck
-- Correctifs du paquet conga, revue QA (tour 2) :
--   * racine sous le sol (passe-muraille, CFrame de la racine à Y −1,5 … −4,9) : la file reste à
--     hauteur de coupe (miettes posées à sol + RootHeight, jamais à la hauteur d'une racine enfouie)
--     et MoveCheck signale la racine enfouie (plus de Snip.MaxDy sous la hauteur debout pendant plus
--     de HoverTime), ou la ramène tout de suite à plus de MaxBelowGround sous la surface
--   * sol réel : un joueur honnête debout sur la stèle du tableau ou sur la tête d'un autre joueur
--     n'est pas un « vol bas » (CongaService sonde le sol réel sous la racine) ; jamais de retour,
--     d'« Unstable », de flags.strikes ni de flags.lbBanned ; un vrai vol reste signalé
-- Les services des autres paquets sont des doublures (même montage que CongaService.spec).
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 53
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."
	-- saut Roblox du projet (default.project.json) : JumpHeight 7,2, gravité 196,2
	local JUMP_HEIGHT = 7.2
	local GRAVITY = 196.2
	-- personnage R15 debout : sommet de la tête à racine + 2,5, bas des pieds à racine − 3
	local HEAD_ABOVE_ROOT = 2.5
	local FEET_BELOW_ROOT = 2.8
	-- stèle « Board » (World/Beacon, Palette.BoardSize) : 10 × 6 × 0,8, face au sud
	local BOARD_SIZE = { x = 10, y = 6, z = 0.8 }

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
			dustCap = 200,
			dustGiven = {},
			glowLog = {},
			atlasLog = {},
			beaconLog = {},
			wispSnips = {},
			dropped = {},
			safeMoments = {},
			activePushes = {},
			calls = { eventStep = 0, stepComet = 0, stepWisps = 0, eventFlush = 0, slow = 0 },
			dirty = {},
			floors = {},
			casts = {},
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
		env.Tuning = h:require("ServerScriptService.Server.Conga.Tuning")

		local DS = h:require(S .. "DataService")
		DS.get = function(p)
			return env.profiles[p.UserId]
		end
		DS.markDirty = function(_, key)
			env.dirty[key] = (env.dirty[key] or 0) + 1
		end

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
		Econ.setLineBanker = function(fn)
			env.banker = fn
		end
		Econ.paradeGlow = function(p, codes, atBeacon)
			return env.F.paradeGlow(codes, 1, env.zen[p.UserId] == true, atBeacon)
		end
		Econ.addGlow = function(p, amount, sku)
			local data = env.profiles[p.UserId]
			data.glow += amount
			table.insert(env.glowLog, { player = p, amount = amount, sku = sku })
			return amount
		end
		Econ.addStardustCapped = function(p, amount, capKey)
			local given = env.dustGiven[p.UserId] or 0
			local granted = math.max(0, math.min(amount, env.dustCap - given))
			env.dustGiven[p.UserId] = given + granted
			env.lastDust = { capKey = capKey, amount = amount }
			return granted
		end
		Econ.step = function()
			env.calls.slow += 1
		end

		local Atlas = h:require(S .. "AtlasService")
		Atlas.addNebbies = function(p, codes, source)
			table.insert(env.atlasLog, { player = p, codes = table.clone(codes), source = source })
			local uids = {}
			for i in codes do
				uids[i] = "u" .. i
			end
			return uids
		end

		local Event = h:require(S .. "EventService")
		Event.step = function()
			env.calls.eventStep += 1
		end
		Event.stepComet = function(_, actors)
			env.calls.stepComet += 1
			env.lastActors = actors
		end
		Event.wispSweeps = function()
			return env.sweeps
		end
		Event.onWispSnip = function(id, victim, count)
			table.insert(env.wispSnips, { id = id, victim = victim, count = count })
		end
		Event.stepWisps = function()
			env.calls.stepWisps += 1
		end
		Event.flush = function()
			env.calls.eventFlush += 1
		end
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
		Event.dropComet = function(p)
			table.insert(env.dropped, p)
		end
		Event.setActivePlayers = function(n)
			table.insert(env.activePushes, n)
		end
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
		Quest.onSafeMoment = function(p)
			table.insert(env.safeMoments, p)
		end

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

	-- ---------------------------------------------------------------------------------------------
	-- Monde physique simulé pour la sonde du sol (workspace:Blockcast) : pavés horizontaux posés par
	-- le test (stèle, décor sans collision) et personnages (tête et pieds de chaque joueur). Respecte
	-- la liste d'exclusion et RespectCanCollide, ignore ce qui est déjà au contact au départ.
	-- ---------------------------------------------------------------------------------------------

	local function excluded(env, inst, params)
		if params == nil then
			return false
		end
		local listed = false
		for _, x in params.FilterDescendantsInstances or {} do
			if inst == x or inst:IsDescendantOf(x) then
				listed = true
				break
			end
		end
		if params.FilterType == env.h.globals.Enum.RaycastFilterType.Include then
			return not listed
		end
		return listed
	end

	local function installFloors(env)
		local cm = MockInstance.classMethods.Workspace
		cm.Blockcast = function(_, cframe, size, direction, params)
			local o = cframe.Position
			table.insert(env.casts, { origin = o, size = size, direction = direction, params = params })
			local bottom = o.Y - size.Y / 2
			local reach = bottom + direction.Y
			local best = nil
			local function consider(inst, cx, cz, hx, hz, top)
				if excluded(env, inst, params) then
					return
				end
				if params and params.RespectCanCollide and inst.CanCollide == false then
					return
				end
				if math.abs(o.X - cx) > size.X / 2 + hx or math.abs(o.Z - cz) > size.Z / 2 + hz then
					return
				end
				-- déjà au contact au départ, ou hors de portée
				if top > bottom or top < reach then
					return
				end
				if best == nil or top > best.Position.Y then
					best = {
						Instance = inst,
						Position = env.V3.new(o.X, top, o.Z),
						Normal = env.V3.new(0, 1, 0),
						Distance = bottom - top,
					}
				end
			end
			for _, f in env.floors do
				consider(f.inst, f.cx, f.cz, f.hx, f.hz, f.top)
			end
			for _, p in env.h.game.Players:GetPlayers() do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then
					local r = root.Position
					consider(char.Head, r.X, r.Z, 1, 0.5, r.Y + HEAD_ABOVE_ROOT)
					consider(char.UpperTorso, r.X, r.Z, 1, 0.5, r.Y - FEET_BELOW_ROOT)
				end
			end
			return best
		end
	end

	-- Pavé horizontal (dessus à `top`) centré en (cx, cz), demi-tailles hx, hz
	local function addFloor(env, name, cx, cz, hx, hz, top, canCollide)
		local part = env.h.globals.Instance.new("Part")
		part.Name = name
		part.CanCollide = canCollide ~= false
		part.Parent = env.h.game.Workspace
		table.insert(env.floors, { inst = part, cx = cx, cz = cz, hx = hx, hz = hz, top = top })
		return part
	end

	-- La vraie stèle du tableau (WorldLayout.boardCFrame, face au sud : largeur selon X)
	local function addBoard(env)
		local cf = env.WL.boardCFrame()
		local p = cf.Position
		local top = p.Y + BOARD_SIZE.y
		addFloor(env, "Board", p.X, p.Z, BOARD_SIZE.x / 2, BOARD_SIZE.z / 2, top)
		return p, top
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

	-- Marche à vitesse constante jusqu'à `to` (un pas par tick), à la hauteur de `to`
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

	-- Hauteur d'une miette : la racine d'un personnage debout sur le sol analytique
	local function crumbTop(env, p)
		return env.WL.groundY(p.X, p.Z) + env.Tuning.RootHeight
	end

	-- Chaque nœud de la file est à hauteur de racine debout (ni en l'air, ni sous terre)
	local function expectLineAtStandingHeight(env, player)
		local nodes = env.Conga.nodePositions(player)
		expect(#nodes > 0).toBe(true)
		for _, node in nodes do
			expect(math.abs(node.Y - crumbTop(env, node)) <= 0.05).toBe(true)
		end
	end

	-- MoveCheck « aveugle » à la profondeur de `player` (sol vu `shift` studs plus bas) : isole la
	-- règle des miettes de CongaService de celle de MoveCheck
	local function blindMoveCheck(env, player, shift)
		local original = env.MoveCheck.step
		env.MoveCheck.step = function(p, pos, dt, now, groundY)
			if p == player then
				groundY += shift
			end
			return original(p, pos, dt, now, groundY)
		end
	end

	-- Sol analytique de la Clairière en x ∈ [20 ; 90], z = 60 (r > 58 : hors du rebord du Cratère)
	local GROUND = 0.1

	-- B (slot 2) descend à `depth` sous la hauteur debout en (x0, 3, 60), y attrape `n` Nebbies puis
	-- marche enfoui jusqu'à x1 ; A (slot 1) attend au sol en (ax, 3, 52)
	local function buriedScenario(env, n, x0, x1, depth, ax, blind)
		local A = join(env, 1, 1)
		local B, dataB = join(env, 2, 2)
		dataB.upgrades.conga = math.max(0, n - 3)
		place(env, B, env.V3.new(x0, GROUND + 3, 60))
		place(env, A, env.V3.new(ax, GROUND + 3, 52))
		tick(env, 35) -- exemptions terminées
		if blind then
			blindMoveCheck(env, B, -depth)
		end
		env.h:moveTo(B, env.V3.new(x0, GROUND + 3 - depth, 60))
		tick(env)
		feed(env, B, n)
		walk(env, B, env.V3.new(x1, GROUND + 3 - depth, 60))
		tick(env, 2)
		return A, B
	end

	-- A traverse la file de B debout (z = 52 → 68) à l'abscisse `x`
	local function crossAt(env, A, x)
		walk(env, A, env.V3.new(x, GROUND + 3, 52))
		walk(env, A, env.V3.new(x, GROUND + 3, 68))
	end

	-- =========================================================================================

	describe("Correctifs conga r2 › racine sous le sol : la file reste à hauteur de coupe", function()
		for _, depth in { 4.6, 5.6, 7.1 } do
			local label = string.format("%.1f", depth - 3)
			it(
				`racine à sol − {label} que MoveCheck ne voit pas : file debout, coupée par un joueur debout`,
				function()
					local env = setup()
					local A, B = buriedScenario(env, 10, 40, 80, depth, 66, true)
					expect(env.MoveCheck.violations(B)).toBe(0)
					expect(env.Conga.lineLength(B)).toBe(10)
					expectLineAtStandingHeight(env, B)
					crossAt(env, A, 66)
					local list = snips(env)
					expect(#list).toBe(1)
					local s = list[1]
					expect(s.byWisp).toBe(false)
					expect(env.Conga.lineLength(B)).toBe(s.cutIndex - 1)
					-- point touché (et Nebbies libres) à hauteur debout, pas sous terre
					expect(math.abs(s.y - crumbTop(env, env.V3.new(s.x, s.y, s.z))) <= 0.05).toBe(true)
				end
			)
		end

		it("racine enfouie : un Gloomwisp (corps à sol + 3) coupe la file", function()
			local env = setup()
			local _, B = buriedScenario(env, 10, 40, 80, 5.6, 20, true)
			local y = env.WL.groundY(62, 60) + env.Tuning.RootHeight
			env.sweeps = { { id = 9, from = env.V3.new(62, y, 54), to = env.V3.new(62, y, 66) } }
			tick(env)
			local s = snips(env)[1]
			expect(s ~= nil).toBe(true)
			expect(s.byWisp).toBe(true)
			expect(env.Conga.lineLength(B)).toBe(s.cutIndex - 1)
		end)

		it("PathStream : les miettes diffusées sont à hauteur debout (file visible des autres)", function()
			local env = setup()
			local _, B = buriedScenario(env, 10, 40, 80, 5.6, 20, true)
			local PC = env.h:require("ReplicatedStorage.Shared.Logic.PathCodec")
			local seen = 0
			for _, e in env.h.log.allClientEvents do
				if e.remote == "PathStream" then
					local _, runs = PC.decode(e.args[1])
					for _, run in runs do
						if run.slot == 2 then
							for _, pt in run.points do
								seen += 1
								-- quantification du codec : 1/8 de stud
								expect(math.abs(pt.Y - crumbTop(env, pt)) <= 0.15).toBe(true)
							end
						end
					end
				end
			end
			expect(seen > 10).toBe(true)
			expect(env.Conga.lineLength(B)).toBe(10)
		end)
	end)

	describe("Correctifs conga r2 › racine sous le sol : MoveCheck réel", function()
		it(
			"racine à sol − 1,5 : tolérée HoverTime, puis signalée, ramenée, plus aucune capture",
			function()
				local env = setup()
				local A = join(env, 1, 1)
				local B = join(env, 2, 2)
				place(env, B, env.V3.new(30, GROUND + 3, 60))
				place(env, A, env.V3.new(66, GROUND + 3, 52))
				tick(env, 35)
				-- file de 3 constituée debout
				feed(env, B, 3)
				expect(env.Conga.lineLength(B)).toBe(3)
				-- enfoui à sol − 1,5, marche 6 s vers x = 90 ; des Nebbies l'attendent sur le trajet
				local y = GROUND - 1.5
				env.h:moveTo(B, env.V3.new(30, y, 60))
				tick(env)
				for x = 50, 85, 5 do
					env.Spawn.spawnPersonal(B, env.Neb.pack(1, 0, 0), env.V3.new(x, GROUND, 60))
				end
				local caught = 0
				env.Signals.Caught:Connect(function(p)
					if p == B then
						caught += 1
					end
				end)
				walk(env, B, env.V3.new(90, y, 60))
				tick(env, 5)
				expect(caught).toBe(0)
				expect(env.Conga.lineLength(B)).toBe(3)
				expect(B:GetAttribute("Unstable")).toBe(true)
				expect(env.MoveCheck.violations(B) >= env.B.MoveCheck.FlagsToRewind).toBe(true)
				expect(env.profiles[2].flags.strikes >= 1).toBe(true)
				expectLineAtStandingHeight(env, B)
			end
		)

		for _, depth in { 2.5, 4 } do
			it(`racine à sol − {depth} : hors du monde, ramenée dès le premier tick`, function()
				local env = setup()
				local B = join(env, 2, 2)
				local start = env.V3.new(40, GROUND + 3, 60)
				place(env, B, start)
				tick(env, 35)
				local violations = {}
				env.Signals.MoveViolation:Connect(function(p, n)
					if p == B then
						table.insert(violations, n)
					end
				end)
				env.h:moveTo(B, env.V3.new(41, GROUND - depth, 60))
				tick(env)
				expect(#violations).toBe(1)
				-- PivotTo vers la dernière position valide, debout
				expect((rootOf(B).Position - start).Magnitude < 1e-6).toBe(true)
				expect(B:GetAttribute("Unstable")).toBe(true)
				expect(env.MoveCheck.isRestricted(B, env.Clock.now())).toBe(true)
				expect(env.profiles[2].flags.strikes).toBe(1)
			end)
		end

		it("la file d'un joueur enfoui reste coupable (MoveCheck réel)", function()
			local env = setup()
			local A = join(env, 1, 1)
			local B, dataB = join(env, 2, 2)
			dataB.upgrades.conga = 7
			place(env, B, env.V3.new(40, GROUND + 3, 60))
			place(env, A, env.V3.new(66, GROUND + 3, 52))
			tick(env, 35)
			feed(env, B, 10)
			walk(env, B, env.V3.new(56, GROUND + 3, 60))
			-- s'enfouit à sol − 1,5 et continue : les miettes tolérées restent debout
			env.h:moveTo(B, env.V3.new(56, GROUND - 1.5, 60))
			tick(env)
			walk(env, B, env.V3.new(80, GROUND - 1.5, 60))
			tick(env, 3)
			expectLineAtStandingHeight(env, B)
			local before = env.Conga.lineLength(B)
			expect(before).toBe(10)
			local nodes = env.Conga.nodePositions(B)
			local mid = (nodes[5] + nodes[6]) / 2
			crossAt(env, A, mid.X)
			expect(#snips(env)).toBe(1)
			expect(env.Conga.lineLength(B) < before).toBe(true)
		end)
	end)

	describe("Correctifs conga r2 › MoveCheck : racine enfouie (unitaire)", function()
		local function mc()
			local h = Harness.new()
			return h:require("ServerScriptService.Server.Util.MoveCheck"),
				h:require("ReplicatedStorage.Shared.Config.Balance"),
				h:require("ServerScriptService.Server.Conga.Tuning"),
				h.globals.Vector3
		end

		local function newPlayer(MC, B, start)
			local player = { Name = "Buried" }
			MC.noteSpeed(player, 16, T0 - 10)
			MC.reset(player, start, T0 - B.MoveCheck.Exemption)
			local p = { player = player, pos = start, now = T0 }
			assert(MC.step(player, start, DT, T0, 0) == "ok")
			return p
		end

		local function move(MC, p, delta, ground)
			p.now += DT
			p.pos = p.pos + delta
			return MC.step(p.player, p.pos, DT, p.now, ground or 0)
		end

		it(
			"racine basse mais à portée (sol − 0,9 : personnage tombé, pente) pendant 5 s : aucune infraction",
			function()
				local MC, B, Tuning, V3 = mc()
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				local low = Tuning.RootHeight - B.Snip.MaxDy -- −1
				expect(move(MC, p, V3.new(0, low + 0.1 - 3, 0))).toBe("ok")
				for _ = 1, 50 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it(
			"racine à sol − 1,5 : tolérée 1 s, puis infraction à chaque tick, retour à la 3e",
			function()
				local MC, B, _, V3 = mc()
				local p = newPlayer(MC, B, V3.new(60, 3, 0))
				expect(move(MC, p, V3.new(0, -4.5, 0))).toBe("ok")
				for _ = 1, 9 do
					expect(move(MC, p, V3.new(1.4, 0, 0))).toBe("ok")
				end
				local verdicts = {}
				for _ = 1, 4 do
					table.insert(verdicts, (move(MC, p, V3.new(1.4, 0, 0))))
				end
				local firstFlag = table.find(verdicts, "flag")
				expect(firstFlag ~= nil and firstFlag <= 2).toBe(true)
				expect(table.find(verdicts, "rewind")).toBe(firstFlag + 2)
				expect(MC.recentRewinds(p.player, p.now)).toBe(1)
				expect(MC.isRestricted(p.player, p.now)).toBe(true)
			end
		)

		it("racine à plus de MaxBelowGround sous le sol : retour immédiat, compté", function()
			local MC, B, Tuning, V3 = mc()
			expect(Tuning.MaxBelowGround).toBe(2)
			local p = newPlayer(MC, B, V3.new(60, 3, 0))
			local start = p.pos
			local verdict, back = move(MC, p, V3.new(1, -5.1, 0))
			expect(verdict).toBe("rewind")
			expect(back).toEqual(start)
			expect(MC.recentRewinds(p.player, p.now)).toBe(1)
			-- même chose sous un sol analytique plus haut (étage 1 de la Balise, dessus à 3,3)
			local q = newPlayer(MC, B, V3.new(6, 6.3, 0))
			expect((move(MC, q, V3.new(0, -5.5, 0), 3.3))).toBe("rewind")
			-- un sol FOURNI plus haut que l'île (appui réel) ne rend jamais « enfouie » une racine
			-- debout sur l'île : la surface est min(sol fourni, sol analytique)
			local s = newPlayer(MC, B, V3.new(-60, 3.1, 0))
			for _ = 1, 30 do
				expect((move(MC, s, V3.new(1, 0, 0), 6))).toBe("ok")
			end
			expect(MC.violations(s.player)).toBe(0)
			-- juste au-dessus de la limite : pas de retour immédiat
			local r = newPlayer(MC, B, V3.new(0, 3, 60))
			expect((move(MC, r, V3.new(1, -4.9, 0)))).toBe("ok")
		end)

		it(
			"exemption : une racine enfouie y est refusée sans retour ni restriction ; sol inconnu : jamais",
			function()
				local MC, B, _, V3 = mc()
				local player = {}
				MC.noteSpeed(player, 16, T0)
				local start = V3.new(30, 3, 30)
				MC.reset(player, start, T0)
				local now = T0
				while now < T0 + B.MoveCheck.Exemption - DT do
					now += DT
					local verdict, back = MC.step(player, V3.new(30.5, -3, 30), DT, now, 0)
					expect(verdict).toBe("flag")
					expect(back).toBeNil()
				end
				expect(MC.recentRewinds(player, now)).toBe(0)
				expect(MC.isRestricted(player, now)).toBe(false)
				expect(MC.lastValid(player)).toEqual(start)
				-- exemption terminée : hors du monde, retour compté vers la position posée par le serveur
				now += 2 * DT
				local verdict, back = MC.step(player, V3.new(30.5, -3, 30), DT, now, 0)
				expect(verdict).toBe("rewind")
				expect(back).toEqual(start)
				expect(MC.recentRewinds(player, now)).toBe(1)
				-- sol inconnu (NaN) : seule la borne absolue MinY s'applique
				local q = {}
				MC.noteSpeed(q, 16, T0)
				MC.reset(q, V3.new(30, 3, 30), T0 - 10)
				local now = T0
				for _ = 1, 30 do
					now += DT
					expect(MC.step(q, V3.new(30, -4, 30), DT, now, 0 / 0)).toBe("ok")
				end
			end
		)

		it("un plané à sol + 9 au-dessus d'un appui à sol + 6 est 'ok' pendant 60 s", function()
			local MC, B, _, V3 = mc()
			local p = newPlayer(MC, B, V3.new(0, 3, 15))
			-- saut sur l'appui (montée en deux ticks), puis 60 s debout dessus
			expect(move(MC, p, V3.new(0, 4.3, -1.5), 0)).toBe("ok")
			expect(move(MC, p, V3.new(0, 1.7, -1.5), 6)).toBe("ok")
			for _ = 1, 600 do
				expect(move(MC, p, V3.new(0, 0, 0), 6)).toBe("ok")
			end
			expect(MC.violations(p.player)).toBe(0)
			expect(MC.recentRewinds(p.player, p.now)).toBe(0)
		end)
	end)

	describe("Correctifs conga r2 › sol réel : stèle, tête d'un joueur", function()
		-- B (slot 2) saute sur la stèle depuis le Cratère puis y reste `seconds` s
		local function standOnBoard(env, B, seconds)
			local p, top = addBoard(env)
			local ground = env.WL.groundY(p.X, p.Z + 3)
			place(env, B, env.V3.new(p.X, ground + 3, p.Z + 3))
			tick(env, 35)
			-- vrai saut (JumpHeight 7,2) vers la stèle : la racine retombe à top + 3
			local v0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT)
			local t = 0
			local z = p.Z + 3
			local y = ground + 3
			while true do
				t += DT
				z = math.max(p.Z, z - 1.4)
				y = ground + 3 + v0 * t - GRAVITY * t * t / 2
				if t > v0 / GRAVITY and y <= top + 3 then
					break
				end
				env.h:moveTo(B, env.V3.new(p.X, y, z))
				tick(env)
			end
			env.h:moveTo(B, env.V3.new(p.X, top + 3, p.Z))
			tick(env)
			for _ = 1, math.floor(seconds / DT) do
				-- petits pas sur place (lecture du tableau)
				local x = p.X + 0.6 * math.sin(env.Clock.now())
				env.h:moveTo(B, env.V3.new(x, top + 3, p.Z))
				tick(env)
			end
			return top
		end

		it("debout 60 s sur la stèle du tableau : jamais signalé, jamais exclu des classements", function()
			local env = setup()
			installFloors(env)
			local B = join(env, 2, 2)
			local rewinds = 0
			env.Signals.MoveViolation:Connect(function(p)
				if p == B then
					rewinds += 1
				end
			end)
			local top = standOnBoard(env, B, 60)
			expect(math.abs(top - env.WL.groundY(0, 12) - 6) < 1e-4).toBe(true)
			expect(rootOf(B).Position.Y - env.WL.groundY(0, 12) > 7).toBe(true)
			expect(rewinds).toBe(0)
			expect(env.MoveCheck.violations(B)).toBe(0)
			expect(B:GetAttribute("Unstable") == true).toBe(false)
			expect(env.profiles[2].flags.strikes).toBe(0)
			expect(env.profiles[2].flags.lbBanned).toBe(false)
		end)

		it("la sonde exclut son propre personnage et ignore le décor sans collision", function()
			local env = setup()
			installFloors(env)
			local B = join(env, 2, 2)
			standOnBoard(env, B, 1)
			local last = env.casts[#env.casts]
			expect(last ~= nil).toBe(true)
			expect(last.params.RespectCanCollide).toBe(true)
			expect(last.params.FilterType).toBe(env.h.globals.Enum.RaycastFilterType.Exclude)
			expect(table.find(last.params.FilterDescendantsInstances, B.Character) ~= nil).toBe(true)
			-- portée : RootHeight + Snip.MaxDy + 1 sous la racine
			expect(last.direction.Y <= -(env.Tuning.RootHeight + env.B.Snip.MaxDy)).toBe(true)
			-- réapparition : la sonde exclut le NOUVEAU personnage
			local old = B.Character
			env.h:respawn(B)
			place(env, B, env.V3.new(60, GROUND + 3, 60))
			tick(env, 2)
			last = env.casts[#env.casts]
			expect(B.Character ~= old).toBe(true)
			expect(table.find(last.params.FilterDescendantsInstances, B.Character) ~= nil).toBe(true)
			expect(table.find(last.params.FilterDescendantsInstances, old)).toBeNil()
		end)

		it("debout 60 s sur la tête d'un ami : jamais signalé ; l'ami n'est pas gêné", function()
			local env = setup()
			installFloors(env)
			local A = join(env, 1, 1)
			local B = join(env, 2, 2)
			local base = env.V3.new(60, GROUND + 3, 60)
			place(env, A, base)
			place(env, B, base + env.V3.new(0, HEAD_ABOVE_ROOT + 3, 0))
			tick(env, 35)
			for _ = 1, 600 do
				local sway = env.V3.new(0.3 * math.sin(env.Clock.now()), 0, 0)
				env.h:moveTo(A, base + sway)
				env.h:moveTo(B, base + sway + env.V3.new(0, HEAD_ABOVE_ROOT + 3, 0))
				tick(env)
			end
			expect(env.MoveCheck.violations(B)).toBe(0)
			expect(env.MoveCheck.violations(A)).toBe(0)
			expect(B:GetAttribute("Unstable") == true).toBe(false)
			expect(env.profiles[2].flags.strikes).toBe(0)
			expect(env.profiles[2].flags.lbBanned).toBe(false)
		end)

		it(
			"un vrai vol bas (HipHeight relevé) reste signalé : ni ses propres pieds ni le décor ne le portent",
			function()
				local env = setup()
				installFloors(env)
				local B, dataB = join(env, 2, 2)
				dataB.upgrades.conga = 7
				local start = env.V3.new(40, GROUND + 3, 60)
				place(env, B, start)
				tick(env, 35)
				feed(env, B, 10)
				-- décor sans collision (perchoir néon flottant) sous le trajet
				addFloor(env, "Decor", 60, 60, 30, 3, GROUND + 5, false)
				env.h:moveTo(B, env.V3.new(40, GROUND + 8.5, 60))
				tick(env)
				walk(env, B, env.V3.new(80, GROUND + 8.5, 60))
				tick(env, 5)
				expect(B:GetAttribute("Unstable")).toBe(true)
				expect(env.MoveCheck.violations(B) >= env.B.MoveCheck.FlagsToRewind).toBe(true)
				expect(env.profiles[2].flags.strikes >= 1).toBe(true)
			end
		)

		it("au-delà de la portée de la sonde, un appui ne compte plus (plané à appui + 9)", function()
			local env = setup()
			installFloors(env)
			local B = join(env, 2, 2)
			addFloor(env, "Ledge", 60, 60, 30, 3, GROUND + 2, true)
			place(env, B, env.V3.new(40, GROUND + 2 + 3, 60))
			tick(env, 35)
			env.h:moveTo(B, env.V3.new(40, GROUND + 2 + 3 + 5, 60))
			tick(env)
			walk(env, B, env.V3.new(80, GROUND + 2 + 3 + 6, 60))
			tick(env, 5)
			expect(env.MoveCheck.violations(B) >= env.B.MoveCheck.FlagsToRewind).toBe(true)
			expect(B:GetAttribute("Unstable")).toBe(true)
		end)
	end)
end
