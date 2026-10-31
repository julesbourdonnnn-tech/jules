--!nocheck
-- Correctifs QA tour 2, paquet client-world : budget des effets de particules continus des Nebbies
-- rendus (GDD §12.8 « Particules à l'écran ≤ 300 », §9 Graphismes légers « particules ×0,3 »).
--   * CongaRenderer : à chaque passe du planificateur (10 Hz), NebbyBuilder.budgetFx allume les
--     effets continus (Fire des Blazing, Sparkles des Rares, orbite des Épiques) des Nebbies en
--     détail complet du plus proche au plus lointain, dans la part des rigs (moitié des 300,
--     × 0,3 en Graphismes légers) ; Nebbies de parade compris ; rigs neufs éteints jusqu'à la passe
--     suivante (RigPool : fxEnabled = false)
--   * VFXController : les rafales n'utilisent que le reste (300 − effets continus du rendu − neige
--     active du ciel − rafales encore vivantes)
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local BLAZING = 3
	local LINES = 6
	local LINE_LENGTH = 30

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			RigPool = h:require(CLIENT .. "World.RigPool"),
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			NB = h:require("ReplicatedStorage.Shared.Render.NebbyBuilder"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.Render = c.Balance.Render
		c.rareBlazing = c.Nebbies.pack(c.Nebbies.byKey.prismpaw, BLAZING, 0)
		if opts.settings then
			c.Prefs._onSettings(opts.settings)
		end
		if opts.vfx then
			c.VFX = h:require(CLIENT .. "Controllers.VFXController")
		end
		c.State.Init()
		c.WSC.Init()
		c.CR.Init()
		if c.VFX then
			c.VFX.Init()
		end
		c.WSC.Start()
		c.CR.Start()
		if c.VFX then
			c.VFX.Start()
		end
		return c
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.05)
			c.h:step(dt or 0.05, 1)
		end
	end

	local function fire(c, remote, ...)
		c.h:fireClient(REMOTES .. remote, ...)
	end

	local function V(x, y, z)
		return Vector3.new(x, y, z)
	end

	local function placeLocal(c, pos)
		c.h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
	end

	local function codes(n, code)
		local out = {}
		for i = 1, n do
			out[i] = code
		end
		return out
	end

	-- miettes en ligne droite d'un point par stud (tête = dernier point)
	local function path(n, x0, z)
		local points = {}
		for i = 1, n do
			points[i] = V(x0 + i, 3, z)
		end
		return points
	end

	-- 6 files de 30 Prismpaw Rares Blazing dans les 50 studs du joueur local (placé en x0, 3, z0)
	local function scene(c, x0, z0, count, length)
		x0 = x0 or 0
		z0 = z0 or 0
		length = length or LINE_LENGTH
		local lines, all = {}, {}
		for k = 1, count or LINES do
			local slot = 2 + k
			table.insert(lines, {
				slot = slot,
				userId = 500 + k,
				ver = 1,
				codes = codes(length, c.rareBlazing),
			})
			local span = math.ceil(length * 2.8)
			for _, e in c.PathCodec.split(slot, 1, path(span, x0 - span / 2, z0 + 2 * k)) do
				table.insert(all, e)
			end
		end
		fire(c, "WorldSnapshot", {
			serverTime = T0,
			tick = 1,
			lines = lines,
			paths = c.PathCodec.encode(1, all),
			wild = {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = LINES + 1 },
			crews = { crews = {} },
		})
	end

	local function isFx(inst)
		local cls = inst.ClassName
		return cls == "Fire" or cls == "Sparkles" or cls == "ParticleEmitter"
	end

	-- Coût d'un Nebby de ce code en détail complet, au multiplicateur de SON rig (pendant un
	-- changement de Graphismes légers, des rigs des deux modes coexistent : Fire / Sparkles hérités en
	-- mode normal, émetteurs au débit réduit en Graphismes légers)
	local refCost = {}
	local function costOf(c, code, low)
		local mult = if low then c.Render.LowGraphicsParticleMult else 1
		local key = code * 10 + mult
		if refCost[key] == nil then
			local rig = c.NB.build(code, 1, "full", { particleMult = mult, fxEnabled = false })
			refCost[key] = c.NB.fxParticles(rig)
			c.NB.destroy(rig)
		end
		return refCost[key]
	end

	-- Inventaire des effets continus des Nebbies rendus (files, sauvages, perchés) : particules
	-- allumées, nombre de modèles allumés / éteints, distance max des allumés / min des éteints
	-- (au sol, comme le planificateur : la hauteur du relief sous les Nebbies n'entre pas en compte)
	local function audit(c)
		local focus = c.h.localPlayer.Character.HumanoidRootPart.Position
		local r =
			{ lit = 0, on = 0, off = 0, maxOn = 0, minOff = math.huge, mixed = 0, fire = 0, sparkles = 0 }
		for _, name in { "Lines", "Wild", "Perched" } do
			for _, model in c.h.workspace.ClientWorld[name]:GetChildren() do
				if model.ClassName == "Model" then
					local fx, enabled, legacy = 0, 0, false
					for _, d in model:GetDescendants() do
						if isFx(d) then
							fx += 1
							legacy = legacy or d.ClassName ~= "ParticleEmitter"
							if d.Enabled then
								enabled += 1
								if d.ClassName == "Fire" then
									r.fire += 1
								elseif d.ClassName == "Sparkles" then
									r.sparkles += 1
								end
							end
						end
					end
					if fx > 0 then
						local dist = (model.PrimaryPart.Position - focus) * Vector3.new(1, 0, 1)
						dist = dist.Magnitude
						if enabled == fx then
							r.on += 1
							r.lit += costOf(c, model:GetAttribute("Code"), not legacy)
							r.maxOn = math.max(r.maxOn, dist)
						elseif enabled == 0 then
							r.off += 1
							r.minOff = math.min(r.minOff, dist)
						else
							r.mixed += 1
						end
					end
				end
			end
		end
		return r
	end

	describe("Fix client-world r2 › budget des effets continus des Nebbies (§12.8)", function()
		it(
			"100 Rares Blazing en détail complet à ≤ 50 studs : Σ particules allumées ≤ part des rigs, plus proches d'abord",
			function()
				local c = setup()
				placeLocal(c, V(0, 3, 0))
				scene(c)
				frames(c, 40)
				expect(c.CR.fullDetailCount()).toBe(c.Render.MaxFullDetail)
				local r = audit(c)
				-- avant correction : 100 Fire + 100 Sparkles allumés (≈ 3 500 particules)
				expect(r.lit <= c.Render.MaxParticles / 2 + 1e-6).toBe(true)
				local share = c.CR.rigParticleBudget()
				expect(share).toBe(c.Render.MaxParticles / 2)
				expect(r.mixed).toBe(0)
				expect(r.lit <= share + 1e-6).toBe(true)
				expect(r.on).toBeGreaterThan(0)
				expect(r.off).toBeGreaterThan(0)
				expect(r.fire <= r.on).toBe(true)
				-- le planificateur rapporte exactement ce qui est allumé
				expect(c.CR.fxParticles()).toBeNear(r.lit, 1e-6)
				-- plus proches d'abord (même coût pour tous : un préfixe de la liste triée)
				expect(r.maxOn <= r.minOff + 1).toBe(true)
				-- aucune dérive dans le temps : la passe suivante garde le même ensemble
				frames(c, 20)
				local r2 = audit(c)
				expect(r2.lit <= share + 1e-6).toBe(true)
				expect(r2.on).toBe(r.on)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("Graphismes légers : part × 0,3 (coûts déjà × 0,3), jamais au-delà", function()
			local c = setup({ settings = { lowGraphics = true } })
			placeLocal(c, V(0, 3, 0))
			scene(c)
			frames(c, 40)
			local share = c.CR.rigParticleBudget()
			expect(share).toBeNear(c.Render.MaxParticles / 2 * c.Render.LowGraphicsParticleMult, 1e-6)
			local r = audit(c)
			expect(r.mixed).toBe(0)
			expect(r.on).toBeGreaterThan(0)
			expect(r.lit <= share + 1e-6).toBe(true)
			-- aucun Fire / Sparkles hérités en Graphismes légers (émetteurs au débit réduit)
			expect(r.fire).toBe(0)
			expect(r.sparkles).toBe(0)
			-- retour au mode normal : la part remonte, toujours tenue pendant les reconstructions
			c.Prefs._onSettings({ lowGraphics = false })
			for _ = 1, 30 do
				frames(c, 1)
				expect(audit(c).lit <= c.Render.MaxParticles / 2 + 1e-6).toBe(true)
			end
			expect(c.CR.rigParticleBudget()).toBe(c.Render.MaxParticles / 2)
			expect(#c.h.errors).toBe(0)
		end)

		it("paillettes des files ≥ 40 déduites de la part des rigs (total du rendu ≤ part)", function()
			local c = setup()
			placeLocal(c, V(0, 3, 0))
			scene(c, 0, 0, 2, c.Render.SparkleLine + 5)
			frames(c, 40)
			local glitter = 0
			for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
				if child.Name == "Sparkle" then
					local e = child:FindFirstChildOfClass("ParticleEmitter")
					glitter += e.Rate * (e.Lifetime.Min + e.Lifetime.Max) / 2
				end
			end
			expect(glitter).toBeGreaterThan(0)
			local share = c.CR.rigParticleBudget()
			local r = audit(c)
			expect(r.on).toBeGreaterThan(0)
			expect(r.lit <= share - glitter + 1e-6).toBe(true)
			expect(c.CR.fxParticles()).toBeNear(r.lit + glitter, 1e-6)
			expect(c.CR.fxParticles() <= share + 1e-6).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it("rig neuf de la réserve : effets éteints jusqu'à la passe suivante du planificateur", function()
			local c = setup()
			local folder = c.g.Instance.new("Folder")
			folder.Parent = c.h.workspace
			local rig = c.RigPool.acquire(c.rareBlazing, 1, "full", false, folder)
			expect(c.NB.fxParticles(rig)).toBeGreaterThan(0)
			local fx = 0
			for _, d in rig.model:GetDescendants() do
				if isFx(d) then
					fx += 1
					expect(d.Enabled).toBe(false)
				end
			end
			expect(fx).toBeGreaterThan(0)
			-- reconstruction (bulle du bouclier débutant) : toujours éteint
			c.RigPool.conform(rig, true)
			for _, d in rig.model:GetDescendants() do
				if isFx(d) then
					expect(d.Enabled).toBe(false)
				end
			end
		end)

		it(
			"cycle de vie : le joueur se déplace, réapparaît loin, les files partent → ensemble allumé suivi, éteint à la réserve",
			function()
				local c = setup()
				placeLocal(c, V(0, 3, 0))
				scene(c)
				frames(c, 40)
				local share = c.CR.rigParticleBudget()
				local first = audit(c)
				expect(first.on).toBeGreaterThan(0)
				-- le joueur longe les files : le budget suit les plus proches
				for x = 0, 36, 6 do
					placeLocal(c, V(x, 3, 0))
					frames(c, 4)
					local r = audit(c)
					expect(r.mixed).toBe(0)
					expect(r.lit <= share + 1e-6).toBe(true)
					expect(r.maxOn <= r.minOff + 1).toBe(true)
				end
				-- réapparition loin (personnage remplacé) : plus aucun Nebby en détail complet proche
				c.h:respawn(c.h.localPlayer)
				placeLocal(c, V(400, 3, 400))
				frames(c, 40)
				expect(c.CR.fxParticles()).toBe(0)
				expect(audit(c).on).toBe(0)
				-- retour, puis toutes les files disparaissent : les rigs rendus à la réserve sont éteints
				placeLocal(c, V(0, 3, 0))
				frames(c, 40)
				expect(audit(c).on).toBeGreaterThan(0)
				fire(c, "WorldSnapshot", {
					serverTime = T0,
					tick = 2,
					lines = {},
					paths = c.PathCodec.encode(2, {}),
					wild = {},
					events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 1 },
					crews = { crews = {} },
				})
				frames(c, 6)
				expect(c.CR.fxParticles()).toBe(0)
				expect(c.RigPool.pooledCount()).toBeGreaterThan(0)
				-- rigs en réserve (déparentés) : tous éteints
				local rig = c.RigPool.acquire(c.rareBlazing, 1, "full", false, c.h.workspace)
				for _, d in rig.model:GetDescendants() do
					if isFx(d) then
						expect(d.Enabled).toBe(false)
					end
				end
				expect(#c.h.errors).toBe(0)
			end
		)

		it(
			"parade : les Nebbies qui marchent vers le joueur (à la porte) sont budgétés avec les autres",
			function()
				local c = setup()
				-- le joueur attend à la porte du Nid 3 : la file encaissée marche vers lui
				local gate = c.WorldLayout.gateCFrame(3).Position
				placeLocal(c, V(gate.X, 3, gate.Z))
				scene(c, gate.X, gate.Z)
				frames(c, 40)
				local share = c.CR.rigParticleBudget()
				fire(c, "LineEvent", {
					{
						op = "bank",
						slot = 3,
						ver = 2,
						count = LINE_LENGTH,
						glow = 500,
						bonus = 1.32,
						atBeacon = false,
						newEntries = 0,
					},
				})
				frames(c, 1)
				expect(c.CR.paradeCount()).toBeGreaterThan(0)
				local paraderLit = 0
				for _ = 1, 10 do
					frames(c, 1)
					expect(c.CR.fxParticles() <= share + 1e-6).toBe(true)
					expect(audit(c).lit <= share + 1e-6).toBe(true)
					-- modèles allumés qui ne sont plus des nœuds de file : Nebbies de parade
					local nodes = {}
					for slot = 4, 2 + LINES do
						for i = 1, LINE_LENGTH do
							local m = c.CR.nodeModel(slot, i)
							if m then
								nodes[m] = true
							end
						end
					end
					for _, model in c.h.workspace.ClientWorld.Lines:GetChildren() do
						if model.ClassName == "Model" and not nodes[model] then
							for _, d in model:GetDescendants() do
								if isFx(d) and d.Enabled then
									paraderLit += 1
									break
								end
							end
						end
					end
				end
				-- avant correction : les Nebbies de parade (hors des vues du planificateur) restaient éteints
				expect(paraderLit).toBeGreaterThan(0)
				frames(c, 60, 0.1)
				expect(c.CR.paradeCount()).toBe(0)
				expect(c.CR.fxParticles() <= share + 1e-6).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)

	describe("Fix client-world r2 › rafales de VFXController dans le reste du budget", function()
		local function snow(c, rate, lifetime)
			local g = c.g
			local sky = c.h.workspace:FindFirstChild("ClientSky")
			if sky == nil then
				sky = g.Instance.new("Folder")
				sky.Name = "ClientSky"
				sky.Parent = c.h.workspace
			end
			local folder = g.Instance.new("Folder")
			folder.Name = "snow"
			folder.Parent = sky
			local carrier = g.Instance.new("Part")
			carrier.Name = "SnowEmitter"
			carrier.Parent = folder
			local emitter = g.Instance.new("ParticleEmitter")
			emitter.Name = "Snow"
			emitter.Rate = rate
			emitter.Lifetime = g.NumberRange.new(lifetime)
			emitter.Parent = carrier
			return emitter, folder
		end

		local function spam(c, n)
			for _ = 1, n do
				c.VFX.burst(V(0, 3, 0), c.g.Color3.new(1, 1, 1), 30)
			end
		end

		it("rafales ≤ 300 − effets continus du rendu ; total ≤ 300", function()
			local c = setup({ vfx = true })
			placeLocal(c, V(0, 3, 0))
			scene(c)
			frames(c, 40)
			local rigs = c.CR.fxParticles()
			expect(rigs).toBeGreaterThan(0)
			spam(c, 40)
			expect(c.VFX.particlesAlive()).toBeNear(c.Render.MaxParticles - rigs, 1)
			expect(c.VFX.particlesAlive() + rigs <= c.Render.MaxParticles + 1e-6).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"neige active du ciel décomptée ; neige retirée → budget rendu ; débits absurdes ignorés",
			function()
				local c = setup({ vfx = true })
				-- Graphismes légers du GDD : 60 × 0,3 = 18 / s pendant 6 s ≈ 108 particules
				local emitter, folder = snow(c, 18, 6)
				frames(c, 10)
				spam(c, 40)
				expect(c.VFX.particlesAlive()).toBeNear(c.Render.MaxParticles - 108, 1)
				-- neige à pleine intensité (60 / s × 6 s = 360) : plus aucune place pour les rafales
				c.Clock.advance(2)
				emitter.Rate = 60
				frames(c, 10)
				spam(c, 5)
				expect(c.VFX.particlesAlive()).toBe(0)
				-- émetteur éteint ou retiré : tout le budget revient
				emitter.Enabled = false
				c.Clock.advance(2)
				frames(c, 10)
				spam(c, 40)
				expect(c.VFX.particlesAlive()).toBe(c.Render.MaxParticles)
				folder.Parent = nil
				c.Clock.advance(2)
				frames(c, 10)
				spam(c, 40)
				expect(c.VFX.particlesAlive()).toBe(c.Render.MaxParticles)
				-- débit négatif : compté 0, aucune erreur
				local bad = snow(c, 0, 6)
				bad.Rate = -50
				c.Clock.advance(2)
				frames(c, 10)
				spam(c, 40)
				expect(c.VFX.particlesAlive()).toBe(c.Render.MaxParticles)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)
end
