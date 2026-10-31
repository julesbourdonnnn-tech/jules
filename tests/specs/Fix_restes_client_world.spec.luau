--!nocheck
-- Correctifs « restes client-world » (rendu du monde côté client) :
--   * N105 : la stèle de la Balise affiche aussi le top mondial Star Atlas (attribut Atlas, GDD §6.7,
--     ligne board.atlasEntry) ; toutes ses lignes tiennent sur la face de la stèle (10 × 6 studs) :
--     sections réparties en pages qui tournent, hauteurs de lignes relatives à la face
--   * N146 / N150 : la neige de Frostfall (Render/SkyFX) tient dans sa part des 300 particules à
--     l'écran (§12.8) : neige + part des rigs laissent toujours ≥ 60 particules aux rafales
--   * Q14 : boucle de rendu de CongaRenderer protégée étape par étape (pcall, avertissement limité
--     à un toutes les 10 s par étape) ; le BulkMoveTo final part toujours avec ce qui a été collecté
--   * Q15 : un seul AnimState réutilisé par module pour NebbyBuilder.animate (aucune table jetable)
--   * N31 : son de capture à la hauteur 1 + min(0,5 ; 0,01 × n) (GDD §9.4), n = file locale après
--     la capture ; AudioController.play(name, variation?, pitch?)
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local CODE_A = 1 -- Puffkin (Commun)
	local BOARD_SIZE = Vector3.new(10, 6, 0.8) -- Server/World/Palette.BoardSize (stèle de la Balise)
	local BURST_RESERVE = 60 -- une rafale complète (confettis Mythiques, MAX_EMIT de VFXController)

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
			Audio = h:require(CLIENT .. "Controllers.AudioController"),
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			NB = h:require("ReplicatedStorage.Shared.Render.NebbyBuilder"),
			SkyFX = h:require("ReplicatedStorage.Shared.Render.SkyFX"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			bulk = { calls = 0, maxPerFrame = 0 },
		}
		c.Render = c.Balance.Render
		local cm = MockInstance.classMethods.Workspace
		local original = cm.BulkMoveTo
		cm.BulkMoveTo = function(self, parts, cframes, mode)
			c.bulk.calls += 1
			return original(self, parts, cframes, mode)
		end
		if opts.vfx then
			c.VFX = h:require(CLIENT .. "Controllers.VFXController")
		end
		for _, fn in opts.before or {} do
			fn(c)
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
		local step = dt or 0.05
		for _ = 1, n do
			c.Clock.advance(step)
			local before = c.bulk.calls
			c.h:step(step, 1)
			c.bulk.maxPerFrame = math.max(c.bulk.maxPerFrame, c.bulk.calls - before)
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
			out[i] = code or CODE_A
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

	local function snapshot(c, lines, runs, extra)
		local all = {}
		for _, r in runs or {} do
			for _, e in c.PathCodec.split(r.slot, r.first or 1, r.points) do
				table.insert(all, e)
			end
		end
		local snap = {
			serverTime = T0,
			tick = 1,
			lines = lines,
			paths = c.PathCodec.encode(1, all),
			wild = {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 2 },
			crews = { crews = {} },
		}
		for k, v in extra or {} do
			snap[k] = v
		end
		fire(c, "WorldSnapshot", snap)
	end

	local function warningsWith(c, needle)
		local n = 0
		for _, line in c.h:warnings() do
			if string.find(line, needle, 1, true) then
				n += 1
			end
		end
		return n
	end

	-- Stèle ------------------------------------------------------------------------------------------

	local function boardEntries(prefix, count, base)
		local items = {}
		for i = 1, count do
			table.insert(items, string.format("%d:%s%d:%d", 900 + i, prefix, i, base - i))
		end
		return table.concat(items, ";")
	end

	local function boardSetup(attrs)
		return setup({
			before = {
				function(cc)
					local g = cc.g
					local beacon = g.Instance.new("Model")
					beacon.Name = "Beacon"
					local board = g.Instance.new("Part")
					board.Name = "Board"
					board.Size = BOARD_SIZE
					for k, v in attrs do
						board:SetAttribute(k, v)
					end
					board.Parent = beacon
					beacon.Parent = cc.h.workspace
					cc.h.game.CollectionService:AddTag(beacon, "Beacon")
				end,
			},
		})
	end

	-- Lignes visibles de la stèle (ordre d'affichage) et hauteur occupée en pixels, mesurée de façon
	-- prudente : marges du UIPadding comprises, échelles relatives à toute la face
	local function visibleBoard(c)
		local gui = c.CR.NestDisplay.boardGui()
		local canvas = BOARD_SIZE.Y * gui.PixelsPerStud
		local list = gui.List
		local used = 0
		local padding = list:FindFirstChildOfClass("UIPadding")
		if padding then
			for _, side in { padding.PaddingTop, padding.PaddingBottom } do
				if side then
					used += side.Scale * canvas + side.Offset
				end
			end
		end
		local lines = {}
		for _, child in list:GetChildren() do
			if child.ClassName == "TextLabel" and child.Visible then
				table.insert(lines, child)
			end
		end
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local texts, minEntry = {}, math.huge
		for _, label in lines do
			local px = label.Size.Y.Scale * canvas + label.Size.Y.Offset
			used += px
			table.insert(texts, label.Text)
			minEntry = math.min(minEntry, px)
		end
		return texts, used, canvas, minEntry
	end

	describe("Fix restes client-world › stèle : top mondial Star Atlas (N105)", function()
		it("l'attribut Atlas s'affiche (board.atlas, board.atlasEntry) et tout tient sur la face", function()
			local c = boardSetup({
				Live = boardEntries("Live", 5, 50),
				Record = "3:Léa:58",
				Weekly = boardEntries("Week", 10, 100),
				Atlas = boardEntries("Atlas", 10, 130),
			})
			placeLocal(c, V(0, 3, 30))
			local seen = {}
			local pages = 0
			for _ = 1, 300 do
				frames(c, 1, 0.1)
				local texts, used, canvas, minEntry = visibleBoard(c)
				-- chaque page tient sur la face de la stèle, en lignes lisibles (≥ 0,35 stud)
				expect(used <= canvas + 0.5).toBe(true) -- UDim : flottants 32 bits
				expect(minEntry >= 14).toBe(true)
				local key = table.concat(texts, "|")
				if not seen[key] then
					seen[key] = true
					pages += 1
				end
				for _, text in texts do
					seen[text] = true
				end
			end
			expect(pages >= 2).toBe(true)
			-- toutes les lignes des quatre sections finissent par être affichées
			expect(seen["Longest Congas"]).toBe(true)
			expect(seen["Star Atlas (world)"]).toBe(true)
			for i = 1, 5 do
				expect(seen[string.format("%d. Live%d ×%d", i, i, 50 - i)]).toBe(true)
			end
			expect(seen["1. Léa ×58"]).toBe(true)
			for i = 1, 10 do
				expect(seen[string.format("%d. Week%d ×%d", i, i, 100 - i)]).toBe(true)
				expect(seen[string.format("%d. Atlas%d · %d entries", i, i, 130 - i)]).toBe(true)
			end
			-- traduction et mise à jour de l'attribut
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(2)
			c.h.workspace.Beacon.Board:SetAttribute("Atlas", "7:Mira:321")
			local found = false
			for _ = 1, 300 do
				frames(c, 1, 0.1)
				local texts, used, canvas = visibleBoard(c)
				expect(used <= canvas + 0.5).toBe(true) -- UDim : flottants 32 bits
				for _, text in texts do
					if text == "1. Mira · 321 entrées" then
						found = true
					end
				end
			end
			expect(found).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it("sections mondiales vides : la page des congas en cours reste affichée", function()
			local c = boardSetup({ Live = "1:Mira:42", Record = "", Weekly = "", Atlas = "" })
			placeLocal(c, V(0, 3, 30))
			for _ = 1, 200 do
				frames(c, 1, 0.1)
				local texts, used, canvas = visibleBoard(c)
				expect(used <= canvas + 0.5).toBe(true) -- UDim : flottants 32 bits
				expect(table.find(texts, "1. Mira ×42") ~= nil).toBe(true)
			end
		end)
	end)

	-- Neige de Frostfall ------------------------------------------------------------------------------

	local function skyFolder(c)
		local sky = c.h.workspace:FindFirstChild("ClientSky")
		if sky == nil then
			sky = c.g.Instance.new("Folder")
			sky.Name = "ClientSky"
			sky.Parent = c.h.workspace
		end
		return sky
	end

	local function snowAlive(fx)
		local emitter = fx.folder.SnowEmitter:FindFirstChildOfClass("ParticleEmitter")
		local life = emitter.Lifetime
		return emitter.Rate * (life.Min + life.Max) / 2
	end

	describe("Fix restes client-world › neige de Frostfall sous budget (N146, N150)", function()
		it(
			"neige à pleine intensité + part des rigs ≤ 300 − une rafale complète (normal et léger)",
			function()
				local c = setup()
				for _, low in { false, true } do
					c.Prefs._onSettings({ lowGraphics = low })
					c.h:settle(1)
					local fx =
						c.SkyFX.create("snow", skyFolder(c), { lowGraphics = low, rng = c.g.Random.new(1) })
					fx:setIntensity(1)
					local alive = snowAlive(fx)
					expect(alive).toBeGreaterThan(0)
					expect(alive + c.CR.rigParticleBudget() + BURST_RESERVE <= c.Render.MaxParticles).toBe(
						true
					)
					fx:destroy()
				end
			end
		)

		it("pendant Frostfall, une capture près de files Blazing garde ses particules", function()
			local c = setup({ vfx = true })
			placeLocal(c, V(0, 3, 0))
			local blazing = c.Nebbies.pack(c.Nebbies.byKey.prismpaw, 3, 0)
			local lines, runs = {}, {}
			for k = 1, 6 do
				table.insert(lines, { slot = 2 + k, userId = 500 + k, ver = 1, codes = codes(30, blazing) })
				table.insert(runs, { slot = 2 + k, points = path(84, -42, 2 * k) })
			end
			snapshot(
				c,
				lines,
				runs,
				{ events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 7 } }
			)
			local fx = c.SkyFX.create("snow", skyFolder(c), { lowGraphics = false, rng = c.g.Random.new(1) })
			fx:setIntensity(1)
			frames(c, 40)
			local rigs = c.CR.fxParticles()
			local snow = snowAlive(fx)
			for _ = 1, 40 do
				c.VFX.burst(V(0, 3, 0), c.g.Color3.new(1, 1, 1), 30)
			end
			local bursts = c.VFX.particlesAlive()
			expect(bursts >= BURST_RESERVE).toBe(true)
			expect(bursts + rigs + snow <= c.Render.MaxParticles + 1e-6).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)
	end)

	-- Boucle de rendu protégée ---------------------------------------------------------------------------

	local function firstPart(model)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				return d
			end
		end
		return nil
	end

	describe("Fix restes client-world › boucle de rendu protégée (Q14)", function()
		it(
			"NestDisplay.collect qui lève : les files bougent, un BulkMoveTo par image, avertissement limité",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = codes(3) } })
				c.CR.NestDisplay.collect = function()
					error("collect cassé")
				end
				for i = 0, 30 do
					placeLocal(c, V(20 + i, 3, 0))
					frames(c, 1)
				end
				local node = c.CR.nodePositions(2)[1]
				expect(math.abs(node.X - 47) < 0.6).toBe(true)
				local part = firstPart(c.CR.nodeModel(2, 1))
				expect(part ~= nil).toBe(true)
				-- les pièces du rig ont suivi (BulkMoveTo exécuté malgré l'erreur)
				expect(math.abs(part.Position.X - node.X) < 3).toBe(true)
				expect(c.bulk.maxPerFrame).toBe(1)
				-- 31 images (1,55 s) : un seul avertissement pour l'étape, puis un autre 10 s plus tard
				expect(warningsWith(c, "collect cassé")).toBe(1)
				c.Clock.advance(10)
				frames(c, 3)
				expect(warningsWith(c, "collect cassé")).toBe(2)
				expect(#c.h.errors).toBe(0)
			end
		)

		it(
			"étape interrompue entre une pièce et son CFrame : listes réalignées, BulkMoveTo valide",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = codes(3) } })
				local stray = c.g.Instance.new("Part")
				stray.Parent = c.h.workspace
				c.CR.NestDisplay.collect = function(_t, parts, _cframes)
					table.insert(parts, stray)
					error("écriture à moitié")
				end
				for i = 0, 20 do
					placeLocal(c, V(20 + i, 3, 0))
					frames(c, 1)
				end
				local node = c.CR.nodePositions(2)[1]
				local part = firstPart(c.CR.nodeModel(2, 1))
				expect(math.abs(part.Position.X - node.X) < 3).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)

	-- AnimState réutilisé ----------------------------------------------------------------------------------

	describe("Fix restes client-world › AnimState réutilisé (Q15)", function()
		it("NebbyBuilder.animate reçoit au plus une table par module (files, sauvages, perchés)", function()
			local slot = 4
			local c = setup({
				before = {
					function(cc)
						local g = cc.g
						local model = g.Instance.new("Model")
						model.Name = string.format("Nest_%02d", slot)
						local attrs = {
							Slot = slot,
							OwnerUserId = 1,
							OwnerName = "Mira",
							Color = g.Color3.fromRGB(160, 220, 90),
							Supernovas = 0,
							PerchCount = 3,
							PerchData = "1.1,1.2,1.1",
							Title = "",
							NestTheme = "default",
							LineStyle = "default",
						}
						for k, v in attrs do
							model:SetAttribute(k, v)
						end
						local perches = g.Instance.new("Folder")
						perches.Name = "Perches"
						perches.Parent = model
						model.Parent = cc.h.workspace
						cc.h.game.CollectionService:AddTag(model, "Nest")
					end,
				},
			})
			local center = c.WorldLayout.nestCenter(slot)
			placeLocal(c, center + V(0, 3, 0))
			local x0, z0 = center.X, center.Z
			snapshot(
				c,
				{ { slot = 6, userId = 60, ver = 1, codes = codes(8) } },
				{ { slot = 6, points = path(40, x0 - 20, z0 + 6) } },
				{
					wild = {
						{ id = 1, code = CODE_A, x = x0 + 4, z = z0 - 4, seed = 3, t0 = T0, life = 60 },
						{ id = 2, code = CODE_A, x = x0 - 5, z = z0 - 3, seed = 4, t0 = T0, life = 60 },
					},
				}
			)
			local original = c.NB.animate
			local tables, distinct, calls = {}, 0, 0
			local speeds = {}
			c.NB.animate = function(rig, state)
				calls += 1
				if not tables[state] then
					tables[state] = true
					distinct += 1
				end
				speeds[state.speed] = true
				return original(rig, state)
			end
			frames(c, 20)
			expect(calls).toBeGreaterThan(100)
			expect(c.CR.NestDisplay.perchedCount(slot)).toBe(3)
			expect(distinct <= 2).toBe(true)
			-- chaque appel repose tous les champs (vitesse des files ≠ 0, sauvages et perchés à 0)
			expect(speeds[0]).toBe(true)
			expect(speeds[12]).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)
	end)

	-- Hauteur du son de capture ------------------------------------------------------------------------------

	describe("Fix restes client-world › son de capture qui monte avec la file (N31)", function()
		it("AudioController.play(name, variation?, pitch?) multiplie PlaybackSpeed par pitch", function()
			local h = Harness.new({ mode = "client" })
			local Sounds = h:require("ReplicatedStorage.Shared.Config.Sounds")
			Sounds.Catch.id = "rbxassetid://1"
			Sounds.Catch.pitch = 1.1
			local Audio = h:require(CLIENT .. "Controllers.AudioController")
			Audio.Init()
			local SoundService = h.game:GetService("SoundService")
			local known = {}
			for _, child in SoundService:GetChildren() do
				known[child] = true
			end
			local function play(...)
				Audio.play(...)
				for _, child in SoundService:GetChildren() do
					if not known[child] and child.ClassName == "Sound" then
						known[child] = true
						return child
					end
				end
				return nil
			end
			local s = play("Catch", 0, 1.3)
			expect(s ~= nil).toBe(true)
			expect(s.Playing).toBe(true)
			expect(s.PlaybackSpeed).toBeNear(1.1 * 1.3, 1e-6)
			-- appelants existants inchangés
			expect(play("Catch", 0).PlaybackSpeed).toBeNear(1.1, 1e-6)
			expect(play("Catch").PlaybackSpeed).toBeNear(1.1, 1e-6)
			-- hauteur absurde : ignorée
			expect(play("Catch", 0, 0 / 0).PlaybackSpeed).toBeNear(1.1, 1e-6)
			expect(play("Catch", 0, -2).PlaybackSpeed).toBeNear(1.1, 1e-6)
			expect(play("Catch", 0, math.huge).PlaybackSpeed).toBeNear(1.1, 1e-6)
			-- variation autour de la hauteur demandée
			local v = play("Catch", 0.05, 1.5).PlaybackSpeed
			expect(v >= 1.1 * 1.5 * 0.95 - 1e-6 and v <= 1.1 * 1.5 * 1.05 + 1e-6).toBe(true)
		end)

		it("capture locale : Catch à 1 + min(0,5 ; 0,01 × n), n = file locale après la capture", function()
			local c = setup({ vfx = true })
			local played = {}
			c.Audio.play = function(name, variation, pitch)
				table.insert(played, { name = name, variation = variation, pitch = pitch })
			end
			c.h.localPlayer:SetAttribute("Slot", 2)
			placeLocal(c, V(0, 3, 0))
			snapshot(c, { { slot = 2, userId = 1, ver = 0, codes = {} } })
			frames(c, 3) -- Trail local alimenté : tête de file connue (position des effets)
			local function lastCatch()
				for i = #played, 1, -1 do
					if played[i].name == "Catch" then
						return played[i]
					end
				end
				return nil
			end
			fire(c, "LineEvent", { { op = "add", slot = 2, ver = 1, codes = { CODE_A }, ids = { 0 } } })
			expect(lastCatch() ~= nil).toBe(true)
			expect(lastCatch().pitch).toBeNear(1.01, 1e-9)
			fire(c, "LineEvent", { { op = "add", slot = 2, ver = 2, codes = codes(19), ids = codes(19, 0) } })
			expect(lastCatch().pitch).toBeNear(1.2, 1e-9)
			fire(c, "LineEvent", { { op = "add", slot = 2, ver = 3, codes = codes(40), ids = codes(40, 0) } })
			expect(lastCatch().pitch).toBeNear(1.5, 1e-9) -- plafond : 60 Nebbies
			-- capture d'un autre joueur : aucun son de capture local
			local before = #played
			snapshot(c, {
				{ slot = 2, userId = 1, ver = 3, codes = codes(60) },
				{ slot = 7, userId = 70, ver = 0, codes = {} },
			})
			fire(c, "LineEvent", { { op = "add", slot = 7, ver = 1, codes = { CODE_A }, ids = { 0 } } })
			for i = before + 1, #played do
				expect(played[i].name ~= "Catch").toBe(true)
			end
			expect(#c.h.errors).toBe(0)
		end)
	end)
end
