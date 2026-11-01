--!nocheck
-- Finition (dernière passe avant publication), paquet client-world-perf — budgets du GDD §12.8 :
--   * VFXController : les étincelles d'immunité (Sparkles héritées, ≈ 15 particules chacune) et la
--     Comète du ciel (Fire + Sparkles, ≈ 35) comptent parmi les effets continus du budget de
--     300 particules ; les rafales n'utilisent que le reste ; étincelles attribuées du plus proche
--     au plus lointain des immunisés, dans la place que laissent les autres effets continus
--   * WorldFXController : attributs lus au suivi (rafraîchis sur AttributeChanged), pièces
--     déplacées par un BulkMoveTo, pièces lointaines (> 200 studs) à fréquence réduite, décor
--     immobile en Mouvement réduit, pièces lointaines figées en Graphismes légers
--   * RigPool : réserve LRU (le plus ancien rig mis en réserve est détruit quand elle est pleine,
--     au plus 24 rigs par clé)
--   * LightingController : ClockTime écrit par paliers d'une minute de jeu (≤ ~1 écriture par
--     seconde au plus fort de la pente du cycle)
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local BLAZING = 3
	local IMMUNITY_COST = 15 -- Sparkles héritées (même estimation que NebbyBuilder)
	local SKY_COMET_COST = 35 -- Comète du ciel : Fire (≈ 20) + Sparkles (≈ 15)

	local function V(x, y, z)
		return Vector3.new(x, y, z)
	end

	-- VFXController : budget de particules ----------------------------------------------------------

	local function vfxSetup(opts)
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
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.Render = c.Balance.Render
		c.rareBlazing = c.Nebbies.pack(c.Nebbies.byKey.prismpaw, BLAZING, 0)
		if opts.settings then
			c.Prefs._onSettings(opts.settings)
		end
		c.State.Init()
		c.WSC.Init()
		c.CR.Init()
		c.VFX.Init()
		c.WSC.Start()
		c.CR.Start()
		c.VFX.Start()
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

	local function path(n, x0, z)
		local points = {}
		for i = 1, n do
			points[i] = V(x0 + i, 3, z)
		end
		return points
	end

	-- 6 files de 30 Prismpaw Rares Blazing autour de l'origine : la part des rigs se remplit
	local function scene(c)
		local lines, all = {}, {}
		for k = 1, 6 do
			local slot = 2 + k
			table.insert(lines, { slot = slot, userId = 500 + k, ver = 1, codes = codes(30, c.rareBlazing) })
			for _, e in c.PathCodec.split(slot, 1, path(84, -42, 2 * k)) do
				table.insert(all, e)
			end
		end
		fire(c, "WorldSnapshot", {
			serverTime = T0,
			tick = 1,
			lines = lines,
			paths = c.PathCodec.encode(1, all),
			wild = {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 7 },
			crews = { crews = {} },
		})
	end

	local function spam(c, n)
		for _ = 1, n do
			c.VFX.burst(V(0, 3, 0), c.g.Color3.new(1, 1, 1), 30)
		end
	end

	-- n joueurs immunisés pour 8 s, alignés à partir de `origin` (pas de `spacing` studs)
	local function immunePlayers(c, n, origin, spacing)
		local players = {}
		for i = 1, n do
			local p = c.h:addPlayer({ userId = 700 + i, name = "Immune" .. i })
			c.h:moveTo(p, origin + V(i * spacing, 0, 0))
			p:SetAttribute("ImmuneUntil", c.Clock.now() + 8)
			players[i] = p
		end
		return players
	end

	local function sparklesOf(p)
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		return root and root:FindFirstChild("Immunity")
	end

	local function immunitySparkles(c)
		local n = 0
		for _, p in c.h.game.Players:GetPlayers() do
			if sparklesOf(p) then
				n += 1
			end
		end
		return n
	end

	local function skyComet(c)
		return c.h.workspace.ClientWorld.VFX:FindFirstChild("CometSky") ~= nil
	end

	-- Alerte Comète en cours : la Comète traverse déjà le ciel (impact dans 5 s)
	local function cometWarn(c)
		local now = math.floor(c.Clock.now())
		fire(c, "EventState", {
			t = now,
			wisps = {},
			snipsDisabled = false,
			activePlayers = 7,
			comet = {
				id = now + 5,
				phase = "warn",
				x = 20,
				z = 10,
				code = 1700,
				warnAt = now,
				impactAt = now + 5,
				burstAt = now + 80,
			},
		})
	end

	-- Particules continues propres à VFXController, recomptées sur les instances du monde
	local function ownContinuous(c)
		return immunitySparkles(c) * IMMUNITY_COST + (if skyComet(c) then SKY_COMET_COST else 0)
	end

	local function snow(c, rate, lifetime)
		local g = c.g
		local sky = c.h.workspace:FindFirstChild("ClientSky")
		if sky == nil then
			sky = g.Instance.new("Folder")
			sky.Name = "ClientSky"
			sky.Parent = c.h.workspace
		end
		local carrier = g.Instance.new("Part")
		carrier.Name = "SnowEmitter"
		carrier.Parent = sky
		local emitter = g.Instance.new("ParticleEmitter")
		emitter.Name = "Snow"
		emitter.Rate = rate
		emitter.Lifetime = g.NumberRange.new(lifetime)
		emitter.Parent = carrier
		return emitter
	end

	describe(
		"Fix fin client-world-perf › immunité et Comète du ciel dans le budget de particules",
		function()
			it(
				"rafales pleines, puis 6 immunisés et la Comète du ciel : le total reste ≤ Render.MaxParticles",
				function()
					local c = vfxSetup()
					placeLocal(c, V(0, 3, 0))
					scene(c)
					frames(c, 40)
					local rigs = c.CR.fxParticles()
					expect(rigs).toBeGreaterThan(0)
					-- les rafales remplissent tout le reste
					spam(c, 40)
					expect(c.VFX.particlesAlive()).toBeNear(c.Render.MaxParticles - rigs, 1)
					-- 6 immunisés près du joueur et une alerte Comète
					immunePlayers(c, 6, V(0, 3, 10), 4)
					cometWarn(c)
					frames(c, 4)
					expect(immunitySparkles(c)).toBe(6)
					expect(skyComet(c)).toBe(true)
					-- plus aucune place tant que les rafales précédentes vivent
					local alive = c.VFX.particlesAlive()
					spam(c, 10)
					expect(c.VFX.particlesAlive()).toBe(alive)
					-- les rafales suivantes n'utilisent que le reste : une nouvelle rafale ne fait jamais
					-- passer le total au-dessus de 300 (les rafales lancées avant l'arrivée des
					-- immunisés s'éteignent en ≤ 1 s, sans être remplacées)
					for _ = 1, 40 do
						frames(c, 1)
						local before = c.VFX.particlesAlive()
						spam(c, 3)
						local continuous = c.CR.fxParticles() + ownContinuous(c)
						local cap = math.max(before, c.Render.MaxParticles - continuous)
						expect(c.VFX.particlesAlive() <= cap + 1e-6).toBe(true)
					end
					-- 2 s plus tard : total ≤ 300, rafales comprises
					local total = c.VFX.particlesAlive() + c.CR.fxParticles() + ownContinuous(c)
					expect(total <= c.Render.MaxParticles + 1e-6).toBe(true)
					-- la place laissée a bien servi (le budget n'est pas simplement bloqué)
					expect(c.VFX.particlesAlive()).toBeGreaterThan(0)
					expect(#c.h.errors).toBe(0)
				end
			)

			it(
				"place réduite (neige dense + Comète du ciel) : étincelles des plus proches seulement, total continu ≤ 300",
				function()
					local c = vfxSetup()
					placeLocal(c, V(0, 3, 0))
					-- neige de test : 30 / s × 6 s = 180 particules ; Comète du ciel 35 → place 85 = 5 immunisés
					snow(c, 30, 6)
					cometWarn(c)
					frames(c, 2)
					local players = immunePlayers(c, 6, V(0, 3, 0), 10)
					frames(c, 4)
					expect(skyComet(c)).toBe(true)
					expect(immunitySparkles(c)).toBe(5)
					-- le plus lointain n'en a pas ; les 5 plus proches en ont
					for i = 1, 5 do
						expect(sparklesOf(players[i]) ~= nil).toBe(true)
					end
					expect(sparklesOf(players[6])).toBeNil()
					expect(180 + c.CR.fxParticles() + ownContinuous(c) <= c.Render.MaxParticles).toBe(true)
					-- aucune rafale : la place est prise par les effets continus
					spam(c, 5)
					expect(c.VFX.particlesAlive()).toBeLessThan(
						c.Render.MaxParticles - 180 - ownContinuous(c) + 1
					)
					-- le plus proche s'éloigne : le 6e (désormais plus proche que lui) prend sa place
					c.h:moveTo(players[1], V(400, 3, 0))
					frames(c, 4)
					expect(sparklesOf(players[1])).toBeNil()
					expect(sparklesOf(players[6]) ~= nil).toBe(true)
					expect(immunitySparkles(c)).toBe(5)
					-- fin de l'alerte (Comète au sol) : la place revient, tout le monde a ses étincelles
					local now = math.floor(c.Clock.now())
					fire(c, "EventState", { t = now, wisps = {}, snipsDisabled = false, activePlayers = 7 })
					frames(c, 4)
					expect(skyComet(c)).toBe(false)
					expect(immunitySparkles(c)).toBe(6)
					-- fin de l'immunité : plus rien
					c.Clock.advance(9)
					frames(c, 4)
					expect(immunitySparkles(c)).toBe(0)
					expect(#c.h.errors).toBe(0)
				end
			)
		end
	)

	-- WorldFXController ----------------------------------------------------------------------------

	local function decorSetup()
		local h = Harness.new({ mode = "client" })
		local g = h.globals
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h.workspace.CurrentCamera.CFrame = CFrame.new(0, 10, 0)
		local c = {
			h = h,
			g = g,
			Clock = Clock,
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			FX = h:require(CLIENT .. "Controllers.WorldFXController"),
			parts = {},
			bulk = { calls = 0, parts = 0 },
		}
		local cs = h.game.CollectionService
		local function part(name, pos, tags, attrs)
			local p = g.Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CFrame = CFrame.new(pos)
			p.Size = V(2, 2, 2)
			for k, v in attrs or {} do
				p:SetAttribute(k, v)
			end
			p.Parent = h.workspace
			for _, tag in tags do
				cs:AddTag(p, tag)
			end
			c.parts[p] = true
			return p
		end
		c.nearFloat = {}
		for i = 1, 4 do
			c.nearFloat[i] = part(
				"NearFloat",
				V(i * 10, 10, 0),
				{ "Float" },
				{ amplitude = 1, period = 4, phase = i }
			)
		end
		c.nearSpin = part(
			"NearSpin",
			V(0, 10, 20),
			{ "Spin", "Float" },
			{ speed = 1, axis = "Y", amplitude = 0.5 }
		)
		c.pulse = part("Star", V(0, 20, 0), { "Pulse" }, { amount = 0.1, period = 1.5 })
		c.farFloat = {}
		for i = 1, 20 do
			c.farFloat[i] = part(
				"FarFloat",
				V(500 + i * 8, 40, 0),
				{ "Float" },
				{ amplitude = 1, period = 5, phase = i }
			)
		end
		c.farSpin = part("FarSpin", V(0, 40, -600), { "Spin" }, { speed = 0.8, axis = "Y" })
		-- compteurs : BulkMoveTo, lectures d'attributs des pièces animées
		local cm = MockInstance.classMethods.Workspace
		local original = cm.BulkMoveTo
		cm.BulkMoveTo = function(self, list, cframes, mode)
			c.bulk.calls += 1
			c.bulk.parts += #list
			return original(self, list, cframes, mode)
		end
		c.FX.Start()
		return c
	end

	-- Compte les GetAttribute sur les pièces animées pendant fn()
	local function countAttributeReads(c, fn)
		local original = MockInstance.Methods.GetAttribute
		local reads = 0
		MockInstance.Methods.GetAttribute = function(self, name)
			if c.parts[self] then
				reads += 1
			end
			return original(self, name)
		end
		local ok, err = pcall(fn)
		MockInstance.Methods.GetAttribute = original
		if not ok then
			error(err, 0)
		end
		return reads
	end

	local function decorFrames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 1 / 60)
			c.h:step(dt or 1 / 60, 1)
		end
	end

	-- Nombre de changements de CFrame de chaque pièce pendant fn()
	local function countMoves(c, list, fn)
		local counts, conns = {}, {}
		for i, p in list do
			counts[i] = 0
			conns[i] = p:GetPropertyChangedSignal("CFrame"):Connect(function()
				counts[i] += 1
			end)
		end
		fn()
		for _, conn in conns do
			conn:Disconnect()
		end
		return counts
	end

	describe("Fix fin client-world-perf › décor animé (WorldFXController)", function()
		it("0 lecture d'attribut par image après le suivi ; un BulkMoveTo par image", function()
			local c = decorSetup()
			decorFrames(c, 2)
			local calls0 = c.bulk.calls
			local reads = countAttributeReads(c, function()
				decorFrames(c, 60)
			end)
			expect(reads).toBe(0)
			expect(c.bulk.calls - calls0 <= 60).toBe(true)
			expect(c.bulk.calls - calls0 >= 55).toBe(true)
			-- l'animation tourne toujours : flottement dans l'amplitude, rotation de la pièce Spin
			local p = c.nearFloat[1]
			expect(math.abs(p.Position.Y - 10) <= 1 + 1e-6).toBe(true)
			expect(p.Position.X).toBeNear(10, 1e-6)
			local look = c.nearSpin.CFrame.LookVector
			expect(math.abs(look.Z + 1) > 1e-3).toBe(true) -- a tourné autour de Y
			expect(math.abs(c.nearSpin.Position.Y - 10) <= 0.5 + 1e-6).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it("attribut changé après le suivi : nouvelle valeur prise en compte (AttributeChanged)", function()
			local c = decorSetup()
			local p = c.nearFloat[2]
			p:SetAttribute("amplitude", 6)
			local maxLift = 0
			for _ = 1, 240 do
				decorFrames(c, 1)
				maxLift = math.max(maxLift, math.abs(p.Position.Y - 10))
			end
			expect(maxLift > 3).toBe(true)
			expect(maxLift <= 6 + 1e-6).toBe(true)
			-- vitesse de rotation changée : l'angle parcouru suit la nouvelle vitesse
			c.nearSpin:SetAttribute("speed", 0)
			decorFrames(c, 1)
			local before = c.nearSpin.CFrame.LookVector
			decorFrames(c, 30)
			local after = c.nearSpin.CFrame.LookVector
			expect((before - after).Magnitude).toBeLessThan(1e-6)
			expect(#c.h.errors).toBe(0)
		end)

		it("pièces lointaines (> 200 studs de la caméra) mises à jour entre 10 et 20 Hz", function()
			local c = decorSetup()
			decorFrames(c, 2)
			local list = { c.nearFloat[1], c.nearSpin, c.farFloat[1], c.farFloat[10], c.farSpin }
			local counts = countMoves(c, list, function()
				decorFrames(c, 120) -- 2 s à 60 images/s
			end)
			expect(counts[1] >= 110).toBe(true) -- proche : chaque image
			expect(counts[2] >= 110).toBe(true)
			for i = 3, 5 do
				expect(counts[i] >= 20 and counts[i] <= 40).toBe(true) -- 10-20 Hz sur 2 s
			end
			-- la caméra s'approche : la pièce redevient « proche » et suit chaque image
			c.h.workspace.CurrentCamera.CFrame = CFrame.new(c.farFloat[1].Position)
			decorFrames(c, 10)
			local near = countMoves(c, { c.farFloat[1] }, function()
				decorFrames(c, 60)
			end)
			expect(near[1] >= 55).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it("Mouvement réduit : décor immobile à sa position d'origine ; repris ensuite", function()
			local c = decorSetup()
			decorFrames(c, 30)
			c.Prefs._onSettings({ reducedMotion = true })
			decorFrames(c, 1)
			local list = { c.nearFloat[1], c.nearSpin, c.farFloat[1], c.farSpin }
			local counts = countMoves(c, list, function()
				decorFrames(c, 60)
			end)
			for i = 1, #list do
				expect(counts[i]).toBe(0)
			end
			expect(c.nearFloat[1].Position).toEqual(V(10, 10, 0))
			expect(c.nearSpin.CFrame).toEqual(CFrame.new(0, 10, 20))
			expect(c.farFloat[1].Position).toEqual(V(508, 40, 0))
			expect(c.pulse.Size).toEqual(V(2, 2, 2))
			local size = c.pulse.Size
			decorFrames(c, 30)
			expect(c.pulse.Size).toEqual(size)
			-- réglage retiré : l'animation reprend
			c.Prefs._onSettings({ reducedMotion = false })
			local again = countMoves(c, { c.nearFloat[1] }, function()
				decorFrames(c, 30)
			end)
			expect(again[1] >= 25).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it("Graphismes légers : pièces lointaines figées, pièces proches animées", function()
			local c = decorSetup()
			decorFrames(c, 10)
			c.Prefs._onSettings({ lowGraphics = true })
			decorFrames(c, 2)
			local list = { c.nearFloat[1], c.farFloat[1], c.farFloat[20], c.farSpin }
			local counts = countMoves(c, list, function()
				decorFrames(c, 60)
			end)
			expect(counts[1] >= 55).toBe(true)
			expect(counts[2]).toBe(0)
			expect(counts[3]).toBe(0)
			expect(counts[4]).toBe(0)
			expect(#c.h.errors).toBe(0)
		end)

		it("pièce détruite ou étiquette retirée : oubliée, plus déplacée", function()
			local c = decorSetup()
			decorFrames(c, 2)
			local cs = c.h.game.CollectionService
			local p = c.nearFloat[3]
			cs:RemoveTag(p, "Float")
			decorFrames(c, 1)
			local pos = p.Position
			decorFrames(c, 30)
			expect(p.Position).toEqual(pos)
			expect(c.FX._entries.Float[p]).toBeNil()
			local d = c.nearFloat[4]
			d:Destroy()
			decorFrames(c, 2)
			expect(c.FX._entries.Float[d]).toBeNil()
			-- Spin retiré d'une pièce Spin + Float : elle continue de flotter sans tourner
			cs:RemoveTag(c.nearSpin, "Spin")
			decorFrames(c, 1)
			local look = c.nearSpin.CFrame.LookVector
			local y0 = c.nearSpin.Position.Y
			decorFrames(c, 40)
			expect((c.nearSpin.CFrame.LookVector - look).Magnitude).toBeLessThan(1e-6)
			expect(math.abs(c.nearSpin.Position.Y - y0) > 1e-4).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)
	end)

	-- RigPool -----------------------------------------------------------------------------------------

	describe("Fix fin client-world-perf › RigPool LRU", function()
		local function poolSetup()
			local h = Harness.new({ mode = "client" })
			local c = {
				h = h,
				RigPool = h:require(CLIENT .. "World.RigPool"),
				NB = h:require("ReplicatedStorage.Shared.Render.NebbyBuilder"),
				Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
				builds = 0,
				destroyed = 0,
			}
			local build, destroy = c.NB.build, c.NB.destroy
			c.NB.build = function(...)
				c.builds += 1
				return build(...)
			end
			c.NB.destroy = function(rig)
				if not rig.destroyed then
					c.destroyed += 1
				end
				return destroy(rig)
			end
			c.folder = h.globals.Instance.new("Folder")
			c.folder.Parent = h.workspace
			return c
		end

		-- clés distinctes (code, étoiles) : 36 espèces × 4 niveaux d'étoiles = 144 clés
		local function keys(c)
			local out = {}
			for stars = 1, 4 do
				for s = 1, 36 do
					table.insert(out, { code = c.Nebbies.pack(s, 0, 0), stars = stars })
				end
			end
			return out
		end

		it(
			"après plus de 120 clés distinctes, les clés récentes sont réutilisées ; réserve ≤ 120",
			function()
				local c = poolSetup()
				local list = keys(c)
				expect(#list > 120).toBe(true)
				for _, k in list do
					local rig = c.RigPool.acquire(k.code, k.stars, "full", false, c.folder)
					c.RigPool.release(rig)
					expect(c.RigPool.pooledCount() <= 120).toBe(true)
				end
				expect(c.RigPool.pooledCount()).toBe(120)
				expect(c.builds).toBe(#list)
				-- les 20 dernières clés relâchées : toutes réutilisées, aucune reconstruction
				local before = c.builds
				for i = #list - 19, #list do
					local k = list[i]
					local rig = c.RigPool.acquire(k.code, k.stars, "full", false, c.folder)
					expect(rig.destroyed).toBe(false)
					c.RigPool.release(rig)
				end
				expect(c.builds).toBe(before)
				-- les plus anciennes ont été évincées (détruites, pas gardées déparentées)
				expect(c.destroyed).toBe(#list - 120)
				local first = list[1]
				local rig = c.RigPool.acquire(first.code, first.stars, "full", false, c.folder)
				expect(c.builds).toBe(before + 1)
				c.RigPool.release(rig)
				expect(c.RigPool.pooledCount() <= 120).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("au plus quelques rigs par clé ; double release sans effet ; clear vide tout", function()
			local c = poolSetup()
			local code = c.Nebbies.pack(1, 0, 0)
			local N = 40
			local rigs = {}
			for i = 1, N do
				rigs[i] = c.RigPool.acquire(code, 1, "full", false, c.folder)
			end
			for i = 1, N do
				c.RigPool.release(rigs[i])
			end
			local kept = c.RigPool.pooledCount()
			expect(kept >= 6 and kept <= 24).toBe(true)
			-- les rigs gardés sont les derniers relâchés
			for i = N + 1 - kept, N do
				expect(rigs[i].destroyed).toBe(false)
			end
			for i = 1, N - kept do
				expect(rigs[i].destroyed).toBe(true)
			end
			c.RigPool.release(rigs[N])
			expect(c.RigPool.pooledCount()).toBe(kept)
			local again = c.RigPool.acquire(code, 1, "full", false, c.folder)
			expect(again).toBe(rigs[N])
			expect(c.RigPool.pooledCount()).toBe(kept - 1)
			c.RigPool.release(again)
			c.RigPool.clear()
			expect(c.RigPool.pooledCount()).toBe(0)
			for i = 1, N do
				expect(rigs[i].destroyed).toBe(true)
			end
			-- après clear : la réserve fonctionne normalement
			local fresh = c.RigPool.acquire(code, 1, "full", false, c.folder)
			c.RigPool.release(fresh)
			expect(c.RigPool.pooledCount()).toBe(1)
			expect(c.RigPool.acquire(code, 1, "full", false, c.folder)).toBe(fresh)
			expect(#c.h.errors).toBe(0)
		end)
	end)

	-- LightingController ------------------------------------------------------------------------------

	describe("Fix fin client-world-perf › ClockTime écrit par paliers", function()
		local CYCLE_T0 = 720 * 2500000 -- début d'un cycle : ClockTime = 17,6

		local function lightingSetup()
			local h = Harness.new({ mode = "client" })
			local g = h.globals
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
			local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
			local LC = h:require(CLIENT .. "Controllers.LightingController")
			local env = { beacon = nil }
			EventClock.weather = function()
				return nil
			end
			EventClock.beacon = function()
				return env.beacon
			end
			EventClock.comet = function()
				return nil
			end
			for className, name in { Atmosphere = "Atmosphere", Sky = "Sky" } do
				local inst = g.Instance.new(className)
				inst.Name = name
				inst.Parent = h.game.Lighting
			end
			-- pente maximale du cycle : t = 180 s (quart de période)
			Clock.freeze(CYCLE_T0 + 170)
			return { h = h, g = g, Clock = Clock, LC = LC, WSC = WSC, env = env, L = h.game.Lighting }
		end

		local function start(c)
			c.LC.Init()
			c.LC.Start()
			c.WSC.EventChanged:Fire(nil, nil)
		end

		it("au plus fort de la pente : ≤ ~1 écriture de ClockTime par seconde, valeur fidèle", function()
			local c = lightingSetup()
			start(c)
			local writes = 0
			c.L:GetPropertyChangedSignal("ClockTime"):Connect(function()
				writes += 1
			end)
			for _ = 1, 600 do -- 10 s à 60 images/s autour de t = 180 s
				c.Clock.advance(1 / 60)
				c.h:step(1 / 60, 1)
				-- jamais à plus d'une demi-minute de jeu du cycle exact
				local exact = c.LC.cycleClockTime(c.Clock.now())
				expect(math.abs(c.L.ClockTime - exact) <= 1 / 120 + 1e-9).toBe(true)
			end
			expect(writes <= 10).toBe(true)
			expect(writes >= 5).toBe(true) -- le soleil avance toujours
			c.LC._stop()
		end)

		it("Nuit de la Balise : fondu vers 21,5 toujours suivi, valeur finale exacte", function()
			local c = lightingSetup()
			start(c)
			local now = c.Clock.now()
			c.env.beacon = { startsAt = now - 1, endsAt = now + 600 }
			c.LC._update(0.3) -- réévaluation (0,25 s) : la Balise est voulue
			local seen = {}
			local last = c.L.ClockTime
			for _ = 1, 40 do
				c.LC._update(0.1)
				if c.L.ClockTime ~= last then
					last = c.L.ClockTime
					table.insert(seen, last)
				end
			end
			expect(#seen >= 10).toBe(true) -- le fondu de 4 s avance par paliers fins
			expect(c.L.ClockTime).toBeNear(21.5, 1e-6)
			c.LC._stop()
		end)
	end)
end
