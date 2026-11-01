--!nocheck
-- Correctifs r5-serveur-3 (CongaService) : un enfant debout sur la tête d'un ami était PORTÉ par
-- lui (dans Roblox, un Humanoid debout sur une pièce qui bouge avance avec elle : vitesse au sol =
-- celle de l'ami + la sienne). MoveCheck, qui ne connaît que le WalkSpeed du porté, y voyait un
-- excès de vitesse : rafales (ni capture ni coupe), puis retours « connexion instable » comptés
-- (flags.strikes) et flags.lbBanned, définitif, au 10e retour en 10 min.
-- Correctif à la racine : aucune collision entre personnages. CongaService.Init enregistre le
-- groupe de collision « Characters », non collidable avec lui-même ; toutes les BasePart d'un
-- personnage y entrent (présentes à l'apparition, ajoutées plus tard : accessoires, nouveau
-- personnage) ; la sonde du sol (Blockcast) utilise ce groupe : elle ne voit que ce qui peut
-- vraiment porter un personnage (jamais un autre joueur).
-- Moteur physique simulé (règles Roblox) : PhysicsService tient la matrice des groupes ; deux
-- pièces se heurtent seulement si leurs groupes sont collidables ; Blockcast respecte
-- RaycastParams.CollisionGroup ; un personnage ne tient sur la tête d'un autre (et n'est porté)
-- que si ses pièces heurtent cette tête, sinon il passe au travers et retombe au sol.
-- Les services des autres paquets sont des doublures (même montage que CongaService.spec).
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 71
	local DT = 0.1
	local S = "ServerScriptService.Server.Services."
	local GROUP = "Characters"
	-- personnage R15 debout : sommet de la tête à racine + 2,5, bas des pieds à racine − 2,8
	local HEAD_ABOVE_ROOT = 2.5
	local FEET_BELOW_ROOT = 2.8
	-- racine d'un personnage debout sur la tête d'un autre (au-dessus de la racine du porteur)
	local RIDE = HEAD_ABOVE_ROOT + 3
	-- sol analytique de la Clairière en x ∈ [20 ; 90], z = 60 (hors du rebord du Cratère)
	local GROUND = 0.1

	-- ---------------------------------------------------------------------------------------------
	-- Physique simulée : groupes de collision (PhysicsService)
	-- ---------------------------------------------------------------------------------------------

	local function installPhysics(env, opts)
		local phys = { groups = { Default = true }, blocked = {}, calls = {} }
		if opts and opts.preRegistered then
			phys.groups[GROUP] = true -- groupe créé à l'avance (Collision Groups du lieu)
		end
		env.phys = phys
		local cm = MockInstance.classMethods.PhysicsService
		cm.IsCollisionGroupRegistered = function(_, name)
			return phys.groups[name] == true
		end
		cm.RegisterCollisionGroup = function(_, name)
			table.insert(phys.calls, { "register", name })
			if opts and opts.registerFails then
				error("Maximum number of collision groups reached")
			end
			assert(type(name) == "string" and name ~= "" and name ~= "Default", "nom de groupe invalide")
			assert(phys.groups[name] == nil, "groupe déjà enregistré : " .. name)
			phys.groups[name] = true
		end
		cm.CollisionGroupSetCollidable = function(_, a, b, collidable)
			table.insert(phys.calls, { "collidable", a, b, collidable })
			-- Roblox lève une erreur pour un groupe inconnu
			assert(phys.groups[a] and phys.groups[b], "groupe de collision inconnu")
			assert(type(collidable) == "boolean", "booléen attendu")
			phys.blocked[a .. "|" .. b] = not collidable
			phys.blocked[b .. "|" .. a] = not collidable
		end
		-- deux groupes se heurtent-ils ? (groupe absent = Default)
		env.collides = function(ga, gb)
			ga = ga or "Default"
			gb = gb or "Default"
			assert(phys.groups[ga] and phys.groups[gb], "pièce dans un groupe non enregistré")
			return phys.blocked[ga .. "|" .. gb] ~= true
		end
	end

	-- Les pièces de `rider` heurtent-elles la tête de `carrier` ? (porté seulement dans ce cas)
	local function rests(env, rider, carrier)
		local head = carrier.Character:FindFirstChild("Head")
		for _, part in rider.Character:GetDescendants() do
			if part:IsA("BasePart") and env.collides(part.CollisionGroup, head.CollisionGroup) then
				return true
			end
		end
		return false
	end

	-- ---------------------------------------------------------------------------------------------
	-- Montage (doublures des autres services, comme Fix_conga_r2)
	-- ---------------------------------------------------------------------------------------------

	local function setup(opts)
		local h = Harness.new()
		local env = {
			h = h,
			V3 = h.globals.Vector3,
			profiles = {},
			slotByUser = {},
			carrier = nil,
			dirty = {},
			casts = {},
		}
		installPhysics(env, opts)
		h:require("ReplicatedStorage.Shared.Net").setup()
		env.Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		env.Clock.freeze(T0)
		env.B = h:require("ReplicatedStorage.Shared.Config.Balance")
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
		Nest.isZen = function()
			return false
		end
		Nest.snipsDisabled = function()
			return false
		end

		local Econ = h:require(S .. "EconomyService")
		Econ.setLineBanker = function(fn)
			env.banker = fn
		end
		Econ.paradeGlow = function(_, codes, atBeacon)
			return env.F.paradeGlow(codes, 1, false, atBeacon)
		end
		Econ.addGlow = function(_, amount)
			return amount
		end
		Econ.addStardustCapped = function(_, amount)
			return amount
		end
		Econ.step = function() end

		h:require(S .. "AtlasService").addNebbies = function(_, codes)
			local uids = {}
			for i in codes do
				uids[i] = "u" .. i
			end
			return uids
		end

		local Event = h:require(S .. "EventService")
		Event.step = function() end
		Event.stepComet = function() end
		Event.wispSweeps = function()
			return {}
		end
		Event.onWispSnip = function() end
		Event.stepWisps = function() end
		Event.flush = function() end
		Event.isTruce = function()
			return false
		end
		Event.beaconOpen = function()
			return false
		end
		Event.onBeaconParade = function() end
		Event.isCarrier = function(p)
			return env.carrier == p
		end
		Event.dropComet = function() end
		Event.setActivePlayers = function() end
		Event.snapshot = function()
			return { t = env.Clock.now(), wisps = {}, snipsDisabled = false, activePlayers = 0 }
		end

		local Crew = h:require(S .. "CrewService")
		Crew.step = function() end
		Crew.crewOf = function()
			return 0
		end
		Crew.escortersOf = function()
			return {}
		end
		Crew.snapshot = function()
			return { crews = {} }
		end

		local Quest = h:require(S .. "QuestService")
		Quest.step = function() end
		Quest.isRookie = function()
			return false
		end
		Quest.onSafeMoment = function() end

		h:require(S .. "LeaderboardService").step = function() end

		env.Spawn = h:require(S .. "SpawnService")
		env.Spawn.Init()
		env.Spawn.Start()
		-- pas d'apparitions de zone : aucun Nebby ne vient perturber le scénario
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
	-- Sonde du sol simulée (workspace:Blockcast) : têtes et pieds des personnages ; respecte la liste
	-- d'exclusion, RespectCanCollide et RaycastParams.CollisionGroup ; ignore ce qui est déjà au
	-- contact au départ (comme un vrai shapecast)
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
				if params and not env.collides(params.CollisionGroup, inst.CollisionGroup) then
					return
				end
				if math.abs(o.X - cx) > size.X / 2 + hx or math.abs(o.Z - cz) > size.Z / 2 + hz then
					return
				end
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

	-- ---------------------------------------------------------------------------------------------
	-- Aides
	-- ---------------------------------------------------------------------------------------------

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

	local function place(env, p, pos)
		env.h:moveTo(p, pos)
		env.Signals.ServerMoved:Fire(p)
	end

	local function walkSpeed(p)
		local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
		local v = humanoid and humanoid.WalkSpeed
		return if type(v) == "number" and v > 0 then v else 16
	end

	local function partsOf(character)
		local parts = {}
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		return parts
	end

	local function expectAllInGroup(character)
		local parts = partsOf(character)
		expect(#parts >= 3).toBe(true)
		for _, part in parts do
			expect(part.CollisionGroup).toBe(GROUP)
		end
	end

	local function distXZ(a, b)
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	-- =========================================================================================

	describe("Correctifs r5-serveur-3 › aucune collision entre personnages", function()
		it(
			"Init enregistre le groupe Characters, non collidable avec lui-même (avec le décor : oui)",
			function()
				local env = setup()
				expect(env.phys.groups[GROUP]).toBe(true)
				expect(env.collides(GROUP, GROUP)).toBe(false)
				-- le monde (Default) porte toujours les personnages
				expect(env.collides(GROUP, "Default")).toBe(true)
			end
		)

		local function registers(env)
			local n = 0
			for _, c in env.phys.calls do
				if c[1] == "register" then
					n += 1
				end
			end
			return n
		end

		it("Init rejoué : aucune erreur, groupe enregistré une seule fois", function()
			local env = setup()
			expect(registers(env)).toBe(1)
			env.Conga.Init()
			expect(registers(env)).toBe(1)
			expect(env.collides(GROUP, GROUP)).toBe(false)
			expect(#env.h:warnings()).toBe(0)
		end)

		it(
			"groupe déjà présent dans le lieu : pas de second enregistrement, collisions quand même coupées",
			function()
				local env = setup({ preRegistered = true })
				expect(registers(env)).toBe(0)
				expect(env.collides(GROUP, GROUP)).toBe(false)
				expect(#env.h:warnings()).toBe(0)
			end
		)

		it(
			"toutes les BasePart du personnage entrent dans le groupe (déjà là, ajoutées, réapparition)",
			function()
				local env = setup()
				local A = join(env, 1, 1)
				expectAllInGroup(A.Character)
				-- accessoire chargé après l'apparition (Handle ajouté plus tard)
				local accessory = env.h.globals.Instance.new("Accessory")
				accessory.Name = "Hat"
				accessory.Parent = A.Character
				local handle = env.h.globals.Instance.new("Part")
				handle.Name = "Handle"
				handle.Parent = accessory
				expect(handle.CollisionGroup).toBe(GROUP)
				-- les autres instances ne sont pas touchées
				expect(accessory.CollisionGroup).toBeNil()
				-- réapparition : le NOUVEAU personnage, pièces présentes et ajoutées ensuite
				local old = A.Character
				env.h:respawn(A)
				expect(A.Character ~= old).toBe(true)
				expectAllInGroup(A.Character)
				local late = env.h.globals.Instance.new("Part")
				late.Name = "Late"
				late.Parent = A.Character
				expect(late.CollisionGroup).toBe(GROUP)
			end
		)

		it("joueur déjà présent avant Start : son personnage entre aussi dans le groupe", function()
			local h = Harness.new()
			local env = { h = h, profiles = {}, slotByUser = {} }
			installPhysics(env)
			h:require("ReplicatedStorage.Shared.Net").setup()
			local p = h:addPlayer({ userId = 5, name = "Early" })
			local Conga = h:require(S .. "CongaService")
			Conga.Init()
			Conga.Start()
			h:settle()
			expectAllInGroup(p.Character)
		end)

		it("la sonde du sol utilise le groupe Characters : un autre joueur n'est jamais un appui", function()
			local env = setup()
			installFloors(env)
			local A = join(env, 1, 1)
			local B = join(env, 2, 2)
			place(env, A, env.V3.new(60, GROUND + 3, 60))
			place(env, B, env.V3.new(60, GROUND + 3 + RIDE, 60))
			tick(env)
			local last = nil
			for _, c in env.casts do
				if c.params and table.find(c.params.FilterDescendantsInstances, B.Character) then
					last = c
				end
			end
			expect(last ~= nil).toBe(true)
			expect(last.params.CollisionGroup).toBe(GROUP)
			-- toujours : son propre personnage exclu, décor sans collision ignoré
			expect(last.params.RespectCanCollide).toBe(true)
			expect(last.params.FilterType).toBe(env.h.globals.Enum.RaycastFilterType.Exclude)
		end)

		it(
			"groupe impossible à créer : le jeu continue sans groupe (avertissement, aucune pièce changée)",
			function()
				local env = setup({ registerFails = true })
				local A = join(env, 1, 1)
				tick(env, 3)
				for _, part in partsOf(A.Character) do
					expect(part.CollisionGroup == nil or part.CollisionGroup == "Default").toBe(true)
				end
				local warned = false
				for _, w in env.h:warnings() do
					if string.find(tostring(w), "collision", 1, true) then
						warned = true
					end
				end
				expect(warned).toBe(true)
			end
		)
	end)

	-- =========================================================================================

	describe("Correctifs r5-serveur-3 › un enfant sur la tête d'un ami n'est jamais exclu", function()
		-- A (porteur, slot 1) fait des allers-retours à SA vitesse serveur (Humanoid.WalkSpeed posé par
		-- CongaService) entre x = 20 et x = 90, s'arrête 1,5 s à chaque bout et fonce (Dash) dès que
		-- sa recharge le permet. B (16 studs/s, slot 2) commence debout sur la tête de A et y reste
		-- tant que la physique le porte (il ne marche pas : porté, il va à la vitesse de A) ; sinon il
		-- court honnêtement vers A à SA vitesse et remonte sur sa tête quand il l'atteint.
		local function piggyback(env, stride, seconds)
			installFloors(env)
			local A, dataA = join(env, 1, 1)
			dataA.upgrades.stride = stride
			local B = join(env, 2, 2)
			local rewinds, dashes = 0, 0
			env.Signals.MoveViolation:Connect(function(p)
				if p == B then
					rewinds += 1
				end
			end)
			env.Signals.Dashed:Connect(function(p)
				if p == A then
					dashes += 1
				end
			end)
			local z = 60
			local ends = { 20, 90 }
			local target = 2
			local pause = 0
			local posA = env.V3.new(ends[1], GROUND + 3, z)
			place(env, A, posA)
			place(env, B, posA + env.V3.new(0, RIDE, 0))
			local riding = rests(env, B, A)
			local stats = { rideTicks = 0, rideSpeed = 0, overlapTicks = 0, rewinds = 0, dashes = 0 }
			-- exemptions d'apparition : A immobile
			for _ = 1, 35 do
				if not riding then
					env.h:moveTo(B, env.V3.new(posA.X, GROUND + 3, posA.Z))
				end
				tick(env)
			end
			for _ = 1, math.floor(seconds / DT) do
				-- 1) A
				local before = posA
				if pause > 0 then
					pause -= 1
				else
					-- (le limiteur du remote compte en temps réel : un essai refusé est rejoué au tick suivant)
					if (A:GetAttribute("DashReadyAt") or 0) <= env.Clock.now() then
						env.h:fireServer("ReplicatedStorage.Remotes.Dash", A)
					end
					local goal = env.V3.new(ends[target], GROUND + 3, z)
					local d = goal - posA
					local step = walkSpeed(A) * DT
					if d.Magnitude <= step then
						posA = goal
						target = 3 - target
						pause = 15
					else
						posA += d.Unit * step
					end
				end
				env.h:moveTo(A, posA)
				-- 2) B : porté par la tête de A, ou au sol à sa propre vitesse
				local posB = rootOf(B).Position
				local set
				if riding then
					set = posA + env.V3.new(0, RIDE, 0)
					stats.rideTicks += 1
					stats.rideSpeed = math.max(stats.rideSpeed, distXZ(posA, before) / DT)
				else
					local ground = env.V3.new(posB.X, GROUND + 3, posB.Z)
					local d = env.V3.new(posA.X - ground.X, 0, posA.Z - ground.Z)
					local step = walkSpeed(B) * DT
					set = if d.Magnitude <= step
						then env.V3.new(posA.X, GROUND + 3, posA.Z)
						else ground + d.Unit * step
					if distXZ(set, posA) <= 1 then
						stats.overlapTicks += 1
						-- sur A : il saute sur sa tête… et y tient seulement si leurs pièces se heurtent
						if rests(env, B, A) then
							riding = true
							set = posA + env.V3.new(0, RIDE, 0)
						end
					end
				end
				env.h:moveTo(B, set)
				tick(env)
				-- ramené par le serveur (PivotTo) : B n'est plus sur la tête de A
				if (rootOf(B).Position - set).Magnitude > 0.01 then
					riding = false
				end
			end
			stats.rewinds = rewinds
			stats.dashes = dashes
			return A, B, stats
		end

		for _, case in
			{
				{ label = "ami à 22 studs/s qui fonce à 32 (Dash)", stride = 12, dashSpeed = 32 },
				{ label = "ami à Foulée max (26) qui fonce à 36 (Dash)", stride = 20, dashSpeed = 36 },
			}
		do
			it(`{case.label}, 60 s : B jamais porté, aucun retour compté, lbBanned reste faux`, function()
				local env = setup()
				expect(env.F.baseWalkSpeed(case.stride) + env.B.Dash.Boost).toBe(case.dashSpeed)
				local A, B, stats = piggyback(env, case.stride, 60)
				-- le scénario a bien eu lieu : A a foncé, B a rejoint A (et l'a traversé)
				expect(stats.dashes >= 3).toBe(true)
				expect(stats.overlapTicks > 0).toBe(true)
				-- B passe au travers de A : jamais porté, donc jamais à la vitesse de A
				expect(stats.rideTicks).toBe(0)
				expect(stats.rewinds).toBe(0)
				expect(env.MoveCheck.violations(B)).toBe(0)
				expect(env.MoveCheck.recentRewinds(B, env.Clock.now())).toBe(0)
				expect(B:GetAttribute("Unstable") == true).toBe(false)
				expect(env.profiles[2].flags.strikes).toBe(0)
				expect(env.profiles[2].flags.lbBanned).toBe(false)
				-- A non plus n'est jamais gêné
				expect(env.MoveCheck.violations(A)).toBe(0)
				expect(env.profiles[1].flags.strikes).toBe(0)
				expect(env.profiles[1].flags.lbBanned).toBe(false)
			end)
		end
	end)
end
