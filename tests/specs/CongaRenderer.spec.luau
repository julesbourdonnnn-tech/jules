--!nocheck
-- CongaRenderer (paquet client-world) : rendu des files (miettes serveur pour les autres, Trail
-- local pour soi), un seul BulkMoveTo par image, niveaux de détail et budgets §12.8, sauvages
-- (flânerie, dispersion, étourdissement, priorité), passages de rigs (capture, coupe, parade),
-- lisibilité §6.4, Nids depuis leurs attributs (perchés, panneau, constellation), stèle,
-- Gloomwisps et orbe de la Comète, cycle de vie (départ, réapparition, personnage absent).
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
	local CODE_MYTHIC = 34 -- Chronomoth (Mythique)

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
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			LineSampler = h:require(CLIENT .. "World.LineSampler"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			bulk = { calls = 0, frames = 0, maxPerFrame = 0, lastCount = 0 },
		}
		-- compteur de BulkMoveTo par image
		local cm = MockInstance.classMethods.Workspace
		local original = cm.BulkMoveTo
		cm.BulkMoveTo = function(self, parts, cframes, mode)
			c.bulk.calls += 1
			c.bulk.lastCount = #parts
			assert(
				mode == roblox.Enum.BulkMoveMode.FireCFrameChanged,
				"BulkMoveMode attendu : FireCFrameChanged"
			)
			return original(self, parts, cframes, mode)
		end
		for _, fn in opts.before or {} do
			fn(c)
		end
		c.WSC.Init()
		c.CR.Init()
		c.WSC.Start()
		c.CR.Start()
		return c
	end

	local function frames(c, n, dt)
		local step = dt or 0.05
		for _ = 1, n do
			c.Clock.advance(step)
			local before = c.bulk.calls
			c.h:step(step, 1)
			local per = c.bulk.calls - before
			c.bulk.maxPerFrame = math.max(c.bulk.maxPerFrame, per)
			c.bulk.frames += 1
		end
	end

	local function fire(c, remote, ...)
		c.h:fireClient(REMOTES .. remote, ...)
	end

	local function V(x, y, z)
		return Vector3.new(x, y, z)
	end

	-- miettes en ligne droite d'un point par stud (tête = dernier point)
	local function path(n, x0, z, dir)
		local points = {}
		for i = 1, n do
			points[i] = V(x0 + (dir or 1) * i, 3, z)
		end
		return points
	end

	local function codes(n, code)
		local out = {}
		for i = 1, n do
			out[i] = code or CODE_A
		end
		return out
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

	local function placeLocal(c, pos)
		local root = c.h.localPlayer.Character.HumanoidRootPart
		root.CFrame = CFrame.new(pos)
	end

	local function addOther(c, userId, slot, pos)
		local p = c.h:addPlayer({ userId = userId, name = "P" .. userId, spawn = pos ~= nil })
		p:SetAttribute("Slot", slot)
		if pos then
			p.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
		end
		return p
	end

	local function fakeNest(c, slot, attrs)
		local g = c.g
		local model = g.Instance.new("Model")
		model.Name = string.format("Nest_%02d", slot)
		local defaults = {
			Slot = slot,
			OwnerUserId = 0,
			OwnerName = "",
			Color = g.Color3.fromRGB(120, 120, 130),
			Supernovas = 0,
			PerchCount = 0,
			PerchData = "",
			Title = "",
			NestTheme = "default",
			LineStyle = "default",
		}
		for k, v in defaults do
			model:SetAttribute(k, v)
		end
		for k, v in attrs or {} do
			model:SetAttribute(k, v)
		end
		local perches = g.Instance.new("Folder")
		perches.Name = "Perches"
		perches.Parent = model
		model.Parent = c.h.workspace
		c.h.game.CollectionService:AddTag(model, "Nest")
		return model
	end

	describe("CongaRenderer › files et BulkMoveTo", function()
		it(
			"dessine la file d'un autre joueur sur ses miettes serveur, un seul BulkMoveTo par image",
			function()
				local c = setup()
				local world = c.h.workspace:FindFirstChild("ClientWorld")
				for _, name in { "Lines", "Wild", "Perched", "Wisps", "Comet" } do
					expect(world:FindFirstChild(name) ~= nil).toBe(true)
				end
				placeLocal(c, V(120, 3, 30))
				local points = path(60, 100, 0)
				snapshot(
					c,
					{ { slot = 5, userId = 50, ver = 3, codes = codes(8) } },
					{ { slot = 5, points = points } }
				)
				frames(c, 6)
				expect(c.bulk.maxPerFrame).toBe(1)
				local positions = c.CR.nodePositions(5)
				expect(#positions).toBe(8)
				-- aucun personnage chargé pour 50 : exactement l'échantillonnage du chemin serveur
				local ref = c.LineSampler.sample(c.WSC.trail(5).points, 8, 2.6, 3, {})
				for i = 1, 8 do
					expect((positions[i] - ref[i]).Magnitude < 1e-3).toBe(true)
				end
				expect(positions[1].X < 160 and positions[1].X > 155).toBe(true)
				local model = c.CR.nodeModel(5, 1)
				expect(model ~= nil).toBe(true)
				expect(model.Parent).toBe(world.Lines)
				expect(c.CR.renderedParts()).toBeGreaterThan(8)
				expect(#c.h:warnings()).toBe(0)
			end
		)

		it(
			"raccorde le premier tronçon au personnage affiché, nœuds coupables exactement sur le chemin",
			function()
				local c = setup()
				placeLocal(c, V(120, 3, 30))
				local points = path(60, 100, 0)
				addOther(c, 50, 5, V(160, 3, 4)) -- personnage affiché à 4 studs de la tête serveur (160, 3, 0)
				snapshot(
					c,
					{ { slot = 5, userId = 50, ver = 3, codes = codes(6) } },
					{ { slot = 5, points = points } }
				)
				frames(c, 4)
				local positions = c.CR.nodePositions(5)
				local ref = c.LineSampler.sample(c.WSC.trail(5).points, 6, 2.6, 3, {})
				expect(positions[1].Z > 1).toBe(true) -- nœud 1 tiré vers le personnage
				expect(math.abs(positions[3].Z - ref[3].Z) < 1e-3).toBe(true) -- à 8,2 studs : sur le chemin
				for i = 4, 6 do
					expect((positions[i] - ref[i]).Magnitude < 1e-3).toBe(true)
				end
			end
		)

		it("dessine la file locale depuis le Trail local alimenté chaque image", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 2)
			snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = codes(3) } })
			for i = 0, 30 do
				placeLocal(c, V(20 + i, 3, 0))
				frames(c, 1)
			end
			local positions = c.CR.nodePositions(2)
			expect(#positions).toBe(3)
			-- tête à x = 50 : nœud 1 à 3 studs, puis tous les 2,6 studs, sur la ligne parcourue
			expect(math.abs(positions[1].X - 47) < 0.6).toBe(true)
			expect(math.abs(positions[2].X - 44.4) < 0.6).toBe(true)
			expect(math.abs(positions[1].Z) < 1e-6).toBe(true)
			expect(c.CR.nodeModel(2, 3) ~= nil).toBe(true)
		end)

		it("file lointaine (> 120 studs) : seulement la boule de tête et l'étiquette « ×N »", function()
			local c = setup()
			placeLocal(c, V(-150, 3, 0))
			local points = path(80, 100, 0)
			snapshot(
				c,
				{ { slot = 6, userId = 60, ver = 1, codes = codes(25) } },
				{ { slot = 6, points = points } }
			)
			frames(c, 8)
			local head = c.CR.nodeModel(6, 1)
			expect(head ~= nil).toBe(true)
			expect(#head:GetChildren()).toBe(1) -- une seule Ball
			for i = 2, 25 do
				expect(c.CR.nodeModel(6, i)).toBeNil()
			end
			expect(c.CR.lineLabel(6)).toBe("×25")
			-- en se rapprochant, la file repasse en détail
			placeLocal(c, V(170, 3, 5))
			frames(c, 12)
			expect(c.CR.lineLabel(6)).toBeNil()
			expect(#c.CR.nodeModel(6, 1):GetChildren() > 1).toBe(true)
		end)

		it(
			"budgets §12.8 : ≤ 100 Nebbies complets, ≤ 1 500 pièces, Highlights et lumières bornés",
			function()
				local c = setup()
				placeLocal(c, V(0, 3, 40))
				local lines, runs = {}, {}
				for slot = 1, 12 do
					table.insert(lines, {
						slot = slot,
						userId = 100 + slot,
						ver = 1,
						codes = codes(60, if slot % 3 == 0 then CODE_MYTHIC else CODE_A),
					})
					local z = 40 + (slot - 6) * 3
					table.insert(runs, { slot = slot, points = path(170, -85, z) })
				end
				snapshot(c, lines, runs)
				frames(c, 30)
				expect(c.CR.fullDetailCount() <= c.Balance.Render.MaxFullDetail).toBe(true)
				expect(c.CR.fullDetailCount()).toBeGreaterThan(20)
				expect(c.CR.renderedParts() <= c.Balance.Render.MaxNebbyParts).toBe(true)
				local highlights, lights = c.CR.decorCounts()
				expect(highlights <= c.Balance.Render.HighlightLines + c.Balance.Render.HighlightMythics).toBe(
					true
				)
				expect(highlights).toBeGreaterThan(0)
				expect(lights <= c.Balance.Render.LegendaryLights).toBe(true)
				expect(c.bulk.maxPerFrame).toBe(1)
				-- Graphismes légers : aucun Highlight, distances × 0,6
				c.Prefs._onSettings({ lowGraphics = true })
				frames(c, 30)
				local h2 = c.CR.decorCounts()
				expect(h2).toBe(0)
				expect(c.CR.fullDetailCount() <= c.Balance.Render.MaxFullDetail).toBe(true)
			end
		)
	end)

	describe("CongaRenderer › sauvages et passages de rigs", function()
		it(
			"sauvages : détail près, masqués loin, arc de dispersion, étourdissement, anneau de priorité",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 3)
				placeLocal(c, V(100, 3, 20))
				snapshot(c, { { slot = 3, userId = 1, ver = 1, codes = {} } }, nil, {
					wild = {
						{ id = 1, code = CODE_A, x = 104, z = 20, seed = 3, t0 = T0, life = 60 },
						{ id = 2, code = CODE_A, x = -100, z = 0, seed = 4, t0 = T0, life = 60 },
						{
							id = 3,
							code = CODE_A,
							x = 110,
							z = 25,
							seed = 5,
							t0 = T0,
							life = 60,
							fromX = 102,
							fromZ = 22,
							prioritySlot = 3,
							dizzyUntil = T0,
						},
					},
				})
				frames(c, 3, 0.05)
				expect(c.CR.wildModel(1) ~= nil).toBe(true)
				expect(c.CR.wildModel(2)).toBeNil()
				-- en vol (arc de 0,55 s) : au-dessus du sol
				local flying = c.CR.wildModel(3)
				local body = flying.PrimaryPart
				local ground = c.WorldLayout.groundY(body.Position.X, body.Position.Z)
				expect(body.Position.Y - ground > 1.5).toBe(true)
				-- après l'atterrissage : 3 boules d'étourdissement et l'anneau doré (Nebby prioritaire)
				frames(c, 10, 0.05)
				local wildFolder = c.h.workspace.ClientWorld.Wild
				local dizzy, rings = 0, 0
				for _, child in wildFolder:GetChildren() do
					if child.Name == "Dizzy" then
						dizzy += 1
					elseif child.Name == "Ring" then
						rings += 1
					end
				end
				expect(dizzy).toBe(3)
				expect(rings).toBe(1)
				frames(c, 30, 0.05)
				dizzy = 0
				for _, child in wildFolder:GetChildren() do
					if child.Name == "Dizzy" then
						dizzy += 1
					end
				end
				expect(dizzy).toBe(0)
			end
		)

		it(
			"capture : le modèle du sauvage devient le nœud de file (saut) ; coupe : les nœuds redeviennent sauvages",
			function()
				local c = setup()
				placeLocal(c, V(120, 3, 10))
				local points = path(40, 100, 0)
				snapshot(
					c,
					{ { slot = 5, userId = 50, ver = 1, codes = codes(2) } },
					{ { slot = 5, points = points } },
					{
						wild = { { id = 9, code = CODE_A, x = 130, z = 4, seed = 1, t0 = T0, life = 60 } },
					}
				)
				frames(c, 3)
				local wildModel = c.CR.wildModel(9)
				expect(wildModel ~= nil).toBe(true)
				fire(c, "LineEvent", { { op = "add", slot = 5, ver = 2, codes = { CODE_A }, ids = { 9 } } })
				frames(c, 1)
				expect(c.CR.wildModel(9)).toBeNil()
				expect(c.CR.nodeModel(5, 3)).toBe(wildModel)
				frames(c, 12)
				-- coupe au nœud 2 : les nœuds 2 et 3 deviennent les sauvages libres 41 et 42
				local cut2, cut3 = c.CR.nodeModel(5, 2), c.CR.nodeModel(5, 3)
				fire(c, "SnipEvent", {
					snipperSlot = 0,
					victimSlot = 5,
					ver = 3,
					cutIndex = 2,
					count = 2,
					looseIds = { 41, 42 },
					loose = {
						{
							id = 41,
							code = CODE_A,
							x = 125,
							z = 6,
							seed = 2,
							t0 = T0,
							life = 20,
							fromX = 132,
							fromZ = 0,
						},
						{
							id = 42,
							code = CODE_A,
							x = 122,
							z = -5,
							seed = 3,
							t0 = T0,
							life = 20,
							fromX = 130,
							fromZ = 0,
						},
					},
					byWisp = true,
					wispId = 1,
					x = 132,
					y = 3,
					z = 0,
					dust = 0,
				})
				frames(c, 1)
				expect(#c.CR.nodePositions(5)).toBe(1)
				expect(c.CR.wildModel(41)).toBe(cut2)
				expect(c.CR.wildModel(42)).toBe(cut3)
			end
		)

		it(
			"parade : les Nebbies sautent vers les perchoirs puis disparaissent ; vidange à la mort → libres",
			function()
				local c = setup()
				placeLocal(c, V(120, 3, 10))
				local points = path(40, 100, 0)
				snapshot(
					c,
					{ { slot = 1, userId = 70, ver = 1, codes = codes(5) } },
					{ { slot = 1, points = points } }
				)
				frames(c, 4)
				fire(c, "LineEvent", {
					{
						op = "bank",
						slot = 1,
						ver = 2,
						count = 5,
						glow = 500,
						bonus = 1.32,
						atBeacon = false,
						newEntries = 0,
					},
				})
				frames(c, 1)
				expect(c.CR.paradeCount()).toBe(5)
				expect(#c.CR.nodePositions(1)).toBe(0)
				frames(c, 30, 0.1)
				expect(c.CR.paradeCount()).toBe(0)
				-- parade à la Balise : les Nebbies s'envolent vers son sommet
				fire(
					c,
					"LineEvent",
					{ { op = "add", slot = 1, ver = 3, codes = codes(3), ids = { 0, 0, 0 } } }
				)
				frames(c, 3)
				fire(c, "LineEvent", {
					{
						op = "bank",
						slot = 1,
						ver = 4,
						count = 3,
						glow = 90,
						bonus = 1.16,
						atBeacon = true,
						newEntries = 0,
					},
				})
				frames(c, 1)
				expect(c.CR.paradeCount()).toBe(3)
				frames(c, 30, 0.1)
				expect(c.CR.paradeCount()).toBe(0)
				-- nouvelle file puis mort : rigs passés aux sauvages libres
				fire(c, "LineEvent", { { op = "add", slot = 1, ver = 5, codes = codes(2), ids = { 0, 0 } } })
				frames(c, 3)
				local m1 = c.CR.nodeModel(1, 1)
				fire(c, "LineEvent", {
					{
						op = "clear",
						slot = 1,
						ver = 6,
						reason = "death",
						loose = {
							{
								id = 60,
								code = CODE_A,
								x = 130,
								z = 0,
								seed = 1,
								t0 = T0 + 3.5,
								life = 20,
								fromX = 137,
								fromZ = 0,
								prioritySlot = 1,
							},
							{
								id = 61,
								code = CODE_A,
								x = 128,
								z = 3,
								seed = 2,
								t0 = T0 + 3.5,
								life = 20,
								fromX = 135,
								fromZ = 0,
								prioritySlot = 1,
							},
						},
					},
				})
				frames(c, 1)
				expect(c.CR.wildModel(60)).toBe(m1)
			end
		)
	end)

	describe("CongaRenderer › lisibilité (§6.4)", function()
		it(
			"rose/doré près d'une file coupable ; aucun pour un équipier, pendant la trêve ; pointillés de sa queue",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				addOther(c, 50, 5, V(161, 3, 0))
				placeLocal(c, V(140, 3, 8))
				local points = path(60, 100, 0)
				snapshot(c, {
					{ slot = 5, userId = 50, ver = 1, codes = codes(10) },
					{ slot = 2, userId = 1, ver = 1, codes = codes(8) },
				}, { { slot = 5, points = points } })
				frames(c, 4)
				expect(c.CR.lineMode(5)).toBe("cut")
				-- anneaux : doré pour les 3 Guard Links, rose ensuite
				local Cosmetics = c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local ringColors = {}
				for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
					if child.Name == "Ring" then
						ringColors[tostring(child.Color)] = true
					end
				end
				expect(ringColors[tostring(Cosmetics.Readability.Guard)]).toBe(true)
				expect(ringColors[tostring(Cosmetics.Readability.Snippable)]).toBe(true)
				-- équipiers : plus d'anneaux de coupe
				fire(c, "CrewState", { crews = { { id = 1, userIds = { 1, 50 } } } })
				frames(c, 3)
				expect(c.CR.lineMode(5)).toBe("style")
				fire(c, "CrewState", { crews = {} })
				-- trêve de la Balise
				fire(c, "EventState", {
					t = T0,
					wisps = {},
					snipsDisabled = false,
					activePlayers = 2,
					beacon = {
						phase = "active",
						warnAt = T0 - 20,
						startsAt = T0 - 5,
						endsAt = T0 + 175,
						points = 0,
						goal = 20,
					},
				})
				frames(c, 3)
				expect(c.CR.lineMode(5)).toBe("style")
				fire(c, "EventState", { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 2 })
				-- victime sous bouclier débutant : pas d'anneau rose
				c.h.game.Players:GetPlayerByUserId(50):SetAttribute("Rookie", true)
				frames(c, 3)
				expect(c.CR.lineMode(5)).toBe("style")
			end
		)

		it("sa propre queue passe en pointillés quand un non-équipier approche (≤ 15 studs)", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 2)
			snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = codes(8) } })
			for i = 0, 30 do
				placeLocal(c, V(i, 3, 0))
				frames(c, 1)
			end
			expect(c.CR.lineMode(2)).toBe("style")
			addOther(c, 77, 9, V(10, 3, 4)) -- près de la queue (nœuds 4-8 vers x 9-20)
			frames(c, 3)
			expect(c.CR.lineMode(2)).toBe("warn")
		end)
	end)

	describe("CongaRenderer › Nids, stèle, Gloomwisps et Comète", function()
		it("perchés, panneau traduit et constellation depuis les attributs du Nid", function()
			local c = setup({
				before = {
					function(cc)
						fakeNest(cc, 4, {
							OwnerUserId = 1,
							OwnerName = "Mira",
							Color = cc.g.Color3.fromRGB(160, 220, 90),
							Supernovas = 3,
							PerchCount = 3,
							PerchData = "9.2,1.1,garbage,1.9,99999.1",
							Title = "comet_hunter",
						})
					end,
				},
			})
			local center = c.WorldLayout.nestCenter(4)
			placeLocal(c, center + V(0, 3, 0))
			frames(c, 5)
			local NestDisplay = c.CR.NestDisplay
			expect(NestDisplay.perchedCount(4)).toBe(2) -- entrées invalides ignorées
			expect(NestDisplay.perchedRig(4, 1) ~= nil).toBe(true)
			local panel = NestDisplay.panel(4)
			expect(panel.Content.Owner.Text).toBe("Mira")
			expect(panel.Content.Rank.Text).toBe("★ 3")
			expect(panel.Content.Title.Text).toBe("Comet Hunter")
			expect(c.CR.constellationStar(4, 3) ~= nil).toBe(true)
			expect(c.CR.constellationStar(4, 4)).toBeNil()
			-- Supernova : une étoile de plus ; Nid libéré : panneau « Nid libre », plus d'étoiles
			local model = NestDisplay.model(4)
			model:SetAttribute("Supernovas", 4)
			expect(c.CR.constellationStar(4, 4) ~= nil).toBe(true)
			model:SetAttribute("PerchData", "1.1")
			frames(c, 3)
			expect(NestDisplay.perchedCount(4)).toBe(1)
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(2)
			expect(panel.Content.Title.Text).toBe("Chasseur de Comètes")
			model:SetAttribute("OwnerUserId", 0)
			expect(panel.Content.Owner.Text).toBe("Nid libre")
			expect(c.CR.constellationStar(4, 1)).toBeNil()
		end)

		it("stèle « Plus longues congas » depuis les attributs Live / Record / Weekly", function()
			local c = setup({
				before = {
					function(cc)
						local g = cc.g
						local beacon = g.Instance.new("Model")
						beacon.Name = "Beacon"
						local board = g.Instance.new("Part")
						board.Name = "Board"
						board:SetAttribute("Live", "1:Mira:42;2:Noah:17")
						board:SetAttribute("Record", "3:Léa:58")
						board:SetAttribute("Weekly", "")
						board.Parent = beacon
						beacon.Parent = cc.h.workspace
						cc.h.game.CollectionService:AddTag(beacon, "Beacon")
					end,
				},
			})
			local gui = c.CR.NestDisplay.boardGui()
			expect(gui ~= nil).toBe(true)
			local texts = {}
			for _, child in gui.List:GetChildren() do
				if child.ClassName == "TextLabel" then
					texts[child.LayoutOrder] = child.Text
				end
			end
			expect(texts[1]).toBe("Longest Congas")
			expect(texts[3]).toBe("1. Mira ×42")
			expect(texts[4]).toBe("2. Noah ×17")
			expect(texts[6]).toBe("1. Léa ×58")
			-- mise à jour chaque seconde : lignes réutilisées, aucune création en rafale
			local before = #gui.List:GetChildren()
			local board = c.h.workspace.Beacon.Board
			for i = 1, 5 do
				board:SetAttribute("Live", "1:Mira:" .. (42 + i) .. ";2:Noah:17")
			end
			expect(#gui.List:GetChildren()).toBe(before)
			for _, child in gui.List:GetChildren() do
				if child.ClassName == "TextLabel" and child.LayoutOrder == 3 then
					expect(child.Text).toBe("1. Mira ×47")
				end
			end
		end)

		it(
			"le perchoir le plus récent pousse du sol (animation locale), pas ceux déjà construits",
			function()
				local c = setup({
					before = {
						function(cc)
							fakeNest(cc, 7, { OwnerUserId = 1, PerchCount = 2 })
						end,
					},
				})
				placeLocal(c, c.WorldLayout.nestCenter(7) + V(0, 3, 0))
				frames(c, 2)
				local model = c.CR.NestDisplay.model(7)
				local function addPerch(index)
					local perch = c.g.Instance.new("Part")
					perch.Name = string.format("Perch_%02d", index)
					perch.Size = V(1.2, 2.2, 2.2)
					perch.CFrame = CFrame.new(c.WorldLayout.perchCFrame(7, index).Position + V(0, 0.6, 0))
					perch:SetAttribute("Index", index)
					perch:SetAttribute("TopY", 1.4)
					perch.Parent = model.Perches
					return perch
				end
				local tweens = c.h.stats.tweens
				addPerch(1) -- déjà construit (réplication d'arrivée)
				expect(c.h.stats.tweens).toBe(tweens)
				model:SetAttribute("PerchCount", 3)
				local perch = addPerch(3)
				expect(c.h.stats.tweens).toBeGreaterThan(tweens)
				expect(perch.Size.X).toBeNear(1.2, 1e-4) -- taille finale rendue
				expect(c.CR.perchTop(7, 3).Y).toBeNear(1.4, 1e-4)
			end
		)

		it(
			"Gloomwisps rendus sur leurs cordes, retirés une fois éclatés ; orbe de la Comète au sol puis porté",
			function()
				local c = setup()
				placeLocal(c, V(0, 3, 0))
				snapshot(c, {}, nil, {
					events = {
						t = T0,
						wisps = { { id = 1, seed = 42, t0 = T0 - 10 } },
						snipsDisabled = false,
						activePlayers = 1,
						comet = {
							id = T0,
							phase = "ground",
							x = 30,
							z = 10,
							code = 1700,
							warnAt = T0 - 8,
							impactAt = T0,
							burstAt = T0 + 75,
						},
					},
				})
				frames(c, 3)
				local wisp = c.CR.wispModel(1)
				expect(wisp ~= nil).toBe(true)
				expect(wisp.Parent).toBe(c.h.workspace.ClientWorld.Wisps)
				local orbPos = c.CR.cometOrbPosition()
				expect(math.abs(orbPos.X - 30) < 1e-6 and math.abs(orbPos.Z - 10) < 1e-6).toBe(true)
				fire(c, "EventState", {
					t = T0,
					wisps = { { id = 1, seed = 42, t0 = T0 - 10, poppedAt = T0 + 0.1, poppedBy = 1 } },
					snipsDisabled = false,
					activePlayers = 1,
					comet = {
						id = T0,
						phase = "carried",
						x = 30,
						z = 10,
						code = 1700,
						warnAt = T0 - 8,
						impactAt = T0,
						burstAt = T0 + 75,
						carrierId = 1,
						carrierSince = T0,
					},
				})
				frames(c, 10)
				expect(c.CR.wispModel(1)).toBeNil()
				local root = c.h.localPlayer.Character.HumanoidRootPart.Position
				expect((c.CR.cometOrbPosition() - (root + V(0, 5, 0))).Magnitude < 1e-3).toBe(true)
				fire(c, "EventState", { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 1 })
				frames(c, 2)
				expect(c.CR.cometOrb()).toBeNil()
			end
		)
	end)

	describe("CongaRenderer › LineSampler (aide pure)", function()
		it("échantillonne exactement comme Trail.sample, sans allocation de la liste de sortie", function()
			local h = Harness.new({ mode = "client" })
			local Trail = h:require("ReplicatedStorage.Shared.Logic.Trail")
			local LineSampler = h:require(CLIENT .. "World.LineSampler")
			local trail = Trail.new(170, 0.5)
			for i = 0, 80 do
				trail:push(V(math.cos(i * 0.1) * 30, 3, math.sin(i * 0.1) * 30))
			end
			local out = {}
			local same = LineSampler.sample(trail.points, 40, 2.6, 3, out)
			expect(same).toBe(out)
			local ref = trail:sample(40, 2.6, 3)
			for i = 1, 40 do
				expect((out[i] - ref[i]).Magnitude < 1e-9).toBe(true)
			end
			-- historique trop court : nœuds empilés au bout le plus ancien, jamais nil
			LineSampler.sample({ V(0, 0, 0), V(1, 0, 0) }, 5, 2.6, 3, out)
			expect(#out).toBe(5)
			expect(out[5]).toEqual(V(0, 0, 0))
			expect(#LineSampler.sample(nil, 3, 2.6, 3, out)).toBe(0)
			expect(#LineSampler.sample({ V(1, 2, 3) }, 2, 2.6, 3, out)).toBe(2)
		end)

		it("raccord : décalage pondéré jusqu'à 8,2 studs, nul au-delà", function()
			local h = Harness.new({ mode = "client" })
			local LineSampler = h:require(CLIENT .. "World.LineSampler")
			local positions = {}
			for i = 1, 5 do
				positions[i] = V(-(3 + (i - 1) * 2.6), 3, 0)
			end
			LineSampler.stitch(positions, V(0, 3, 0), V(0, 3, 4), 2.6, 3, 8.2)
			expect(positions[1].Z).toBeNear(4 * (1 - 3 / 8.2))
			expect(positions[2].Z).toBeNear(4 * (1 - 5.6 / 8.2))
			expect(positions[3].Z).toBe(0)
			expect(positions[5].Z).toBe(0)
		end)
	end)

	describe("CongaRenderer › cycle de vie", function()
		it(
			"départ d'un joueur, réapparition locale et personnage absent : rien ne casse, rigs libérés",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				placeLocal(c, V(120, 3, 10))
				local points = path(40, 100, 0)
				snapshot(c, {
					{ slot = 5, userId = 50, ver = 1, codes = codes(4) },
					{ slot = 2, userId = 1, ver = 1, codes = codes(2) },
				}, { { slot = 5, points = points } })
				frames(c, 4)
				local model = c.CR.nodeModel(5, 1)
				expect(model.Parent ~= nil).toBe(true)
				fire(c, "LineEvent", {
					{ op = "clear", slot = 5, ver = 2, reason = "leave", loose = {} },
					{ op = "owner", slot = 5, ver = 0, userId = 0 },
				})
				frames(c, 2)
				expect(model.Parent).toBeNil()
				expect(#c.CR.nodePositions(5)).toBe(0)
				-- réapparition : le Trail local repart de zéro
				c.h:respawn(c.h.localPlayer)
				placeLocal(c, V(-50, 3, 0))
				frames(c, 3)
				expect(#c.CR.nodePositions(2)).toBe(2)
				-- personnage absent : aucune erreur
				c.h.localPlayer.Character:Destroy()
				c.h.localPlayer.Character = nil
				frames(c, 5)
				expect(#c.h.errors).toBe(0)
				expect(#c.h:warnings()).toBe(0)
			end
		)
	end)

	-- Revue du paquet : chaque test reproduit un bogue corrigé
	describe("CongaRenderer › revue (bogues corrigés)", function()
		local function snip(c, ver, cutIndex, count)
			local ids, loose = {}, {}
			for k = 1, count do
				local id = ver * 10 + k
				ids[k] = id
				loose[k] = {
					id = id,
					code = CODE_A,
					x = 125 + k,
					z = 6,
					seed = k,
					t0 = T0,
					life = 20,
					fromX = 130,
					fromZ = 0,
				}
			end
			fire(c, "SnipEvent", {
				snipperSlot = 0,
				victimSlot = 5,
				ver = ver,
				cutIndex = cutIndex,
				count = count,
				looseIds = ids,
				loose = loose,
				byWisp = true,
				wispId = 1,
				x = 130,
				y = 3,
				z = 0,
				dust = 0,
			})
		end

		it(
			"Graphismes légers : le Nebby coupé ne flashe pas (Highlight réservé au porteur de Comète)",
			function()
				local c = setup()
				c.Prefs._onSettings({ lowGraphics = true })
				placeLocal(c, V(130, 3, 6))
				snapshot(
					c,
					{ { slot = 5, userId = 50, ver = 1, codes = codes(6) } },
					{ { slot = 5, points = path(40, 100, 0) } }
				)
				frames(c, 4)
				local flash = c.h.workspace.ClientWorld.SnipFlash
				snip(c, 2, 5, 2)
				expect(flash.Enabled).toBe(false)
				-- graphismes normaux : le flash blanc de 0,1 s est bien joué
				c.Prefs._onSettings({ lowGraphics = false })
				frames(c, 4)
				snip(c, 3, 3, 2)
				expect(flash.Enabled).toBe(true)
			end
		)

		it(
			"Highlights et lumières : attribution différentielle, rien n'est ré-adorné à chaque passe",
			function()
				local c = setup()
				placeLocal(c, V(0, 3, 0))
				snapshot(c, {}, nil, {
					wild = {
						{ id = 9, code = CODE_MYTHIC, x = 6, z = 0, seed = 1, t0 = T0 - 10, life = 120 },
					},
				})
				frames(c, 6)
				local model = c.CR.wildModel(9)
				expect(model ~= nil).toBe(true)
				local hl
				for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
					if child.Name == "NebbyHighlight" and child.Enabled then
						hl = child
					end
				end
				expect(hl ~= nil).toBe(true)
				expect(hl.Adornee).toBe(model)
				local light
				for _, d in model:GetDescendants() do
					if d.Name == "RarityLight" then
						light = d
					end
				end
				expect(light ~= nil).toBe(true)
				local adorneeChanges, lightMoves = 0, 0
				hl:GetPropertyChangedSignal("Adornee"):Connect(function()
					adorneeChanges += 1
				end)
				light.AncestryChanged:Connect(function()
					lightMoves += 1
				end)
				frames(c, 10) -- 0,5 s : au moins 4 passes du planificateur
				expect(adorneeChanges).toBe(0)
				expect(lightMoves).toBe(0)
				expect(hl.Adornee).toBe(model)
				expect(hl.Enabled).toBe(true)
				-- le Nebby s'éloigne au-delà des budgets : Highlight libéré
				placeLocal(c, V(0, 3, 400))
				frames(c, 6)
				expect(hl.Enabled).toBe(false)
				local h2, l2 = c.CR.decorCounts()
				expect(h2).toBe(0)
				expect(l2).toBe(0)
			end
		)

		it(
			"vague dans la file : Y = sin(4 t + 0,5 i) × 0,35 au-dessus du sol (amplitude du GDD §9.3)",
			function()
				local c = setup()
				placeLocal(c, V(130, 3, 10))
				snapshot(
					c,
					{ { slot = 5, userId = 50, ver = 1, codes = codes(3) } },
					{ { slot = 5, points = path(40, 100, 0) } }
				)
				local NebbyBuilder = c.h:require("ReplicatedStorage.Shared.Render.NebbyBuilder")
				local size = NebbyBuilder.bodySize(CODE_A)
				local worst, low, high = 0, math.huge, -math.huge
				for _ = 1, 12 do -- 0,6 s : file en mouvement récent (pas encore de danse)
					frames(c, 1)
					local t = c.Clock.now()
					local p = c.CR.nodePositions(5)[1]
					local ground = math.max(c.WorldLayout.groundY(p.X, p.Z), p.Y - 3)
					local wave = 0.35 * (1 + math.sin(4 * t + 0.5))
					local y = c.CR.nodeModel(5, 1).PrimaryPart.Position.Y - ground - size / 2
					worst = math.max(worst, math.abs(y - wave))
					low, high = math.min(low, y), math.max(high, y)
				end
				expect(worst < 1e-3).toBe(true)
				expect(low >= -1e-6).toBe(true) -- jamais sous le sol
				expect(high - low > 0.35).toBe(true)
			end
		)

		it("parade de la Nuit de la Balise : les Nebbies s'envolent vers l'étoile de la Balise", function()
			local c = setup()
			placeLocal(c, V(20, 3, 0))
			snapshot(
				c,
				{ { slot = 5, userId = 50, ver = 1, codes = codes(1) } },
				{ { slot = 5, points = path(20, 0, 5) } }
			)
			frames(c, 3)
			local model = c.CR.nodeModel(5, 1)
			expect(model ~= nil).toBe(true)
			fire(c, "LineEvent", {
				{
					op = "bank",
					slot = 5,
					ver = 2,
					count = 1,
					glow = 10,
					bonus = 1,
					atBeacon = true,
					newEntries = 0,
				},
			})
			frames(c, 8) -- 0,4 s : saut fini (0,35 s), rétrécissement au point d'arrivée
			local Zones = c.h:require("ReplicatedStorage.Shared.Config.Zones")
			local size = c.h:require("ReplicatedStorage.Shared.Render.NebbyBuilder").bodySize(CODE_A)
			expect(model.Parent ~= nil).toBe(true)
			expect(math.abs(model.PrimaryPart.Position.Y - (Zones.Beacon.StarY + size / 2)) < 0.5).toBe(true)
		end)

		it(
			"équipage formé de jour : le lien entre les Nids est tracé et visible, puis seulement la nuit",
			function()
				local c = setup()
				c.h.game.Lighting.ClockTime = 12
				snapshot(c, {
					{ slot = 3, userId = 30, ver = 0, codes = {} },
					{ slot = 4, userId = 40, ver = 0, codes = {} },
				})
				fire(c, "CrewState", { crews = { { id = 1, userIds = { 30, 40 } } } })
				frames(c, 3)
				local beam
				for _, d in c.h.workspace.ClientWorld:GetDescendants() do
					if d.Name == "CrewLink_3:4" then
						beam = d
					end
				end
				expect(beam ~= nil).toBe(true)
				expect(beam.Enabled).toBe(true)
				c.Clock.advance(5)
				frames(c, 3)
				expect(beam.Enabled).toBe(false)
				c.h.game.Lighting.ClockTime = 22
				frames(c, 3)
				expect(beam.Enabled).toBe(true)
			end
		)

		it("badge doré « ★ VIP » sous le nom d'un propriétaire VIP sur le panneau du Nid", function()
			local c = setup({
				before = {
					function(cc)
						fakeNest(cc, 6, { OwnerUserId = 66, OwnerName = "Mira" })
					end,
				},
			})
			local owner = addOther(c, 66, 6, nil)
			frames(c, 3)
			local vip = c.CR.NestDisplay.panel(6):FindFirstChild("Vip", true)
			expect(vip ~= nil).toBe(true)
			expect(vip.Visible).toBe(false)
			owner:SetAttribute("VIP", true)
			frames(c, 3)
			expect(vip.Visible).toBe(true)
			expect(vip.Text).toBe("★ VIP")
			owner:SetAttribute("VIP", false)
			frames(c, 3)
			expect(vip.Visible).toBe(false)
		end)
	end)
end
