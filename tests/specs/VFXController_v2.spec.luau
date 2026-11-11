--!nocheck
-- Moments de la v2.0 dessinés par le client (lot B5 ; GDD §4.15, §4.27, §9.4, §11.5, §12.10 ; docs/04
-- §27.10 « voisin = même état final que le propriétaire ; coupures dures » ; plan B5 D17 à D19, D29) :
--   * étape 3 : Chantier de Big Plop (World/BigPlop, sur RanchRenderer.ElementBuilt) : 3 coups de
--     maillet à 0,6 / 1,4 / 2,2 s, 4 s en tout, coupure dure à 6 s, son, vibration et étiquette pour MON
--     ranch seulement, jamais pendant un grand spectacle, état final sans aucune instance ; geste vers
--     l'Observatoire une fois par séance ; costume d'hiver ; interrupteurs coupés : rien ;
--   * étape 4 : Petit Splorch, Jelly Ascend (et sa caméra), Pluie d'étoiles, record, Palier, palette,
--     emotes de la v2.0 ; interrupteurs coupés : aucune instance pour chaque message rejoué.
-- Monde fabriqué, horloge figée, zéro trace (ZeroLog). Tout est en 3D : ces cas prouvent la structure
-- (instances, positions, heures, sons et vibrations demandés) ; personne n'a pu regarder Big Plop.

local roblox = require("@lune/roblox")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local Color3 = roblox.Color3

local T0 = 1796724120
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local REMOTES = "ReplicatedStorage.Remotes."

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 12,
			fame = 0,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 1, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
	end

	local function folder(parent, name, class)
		local f = parent:FindFirstChild(name)
		if f == nil then
			f = MockInstance.new(class or "Folder")
			f.Name = name
			f.Parent = parent
		end
		return f
	end

	-- Client : miroir, éclairage (test d'hiver), RanchRenderer, VFXController (qui démarre BigPlop,
	-- ShowsV2 et Emotes) ; le ranch 3 est au joueur 1, le 4 au joueur 2, le 10 au joueur 3 ; `opts.me`
	-- choisit le joueur local (1 par défaut : propriétaire du ranch 3 ; 2 : son voisin, ranch 3 en détail
	-- complet ; 3 : un client lointain, ranch 3 en détail réduit) ; `opts.best` : squishy public
	-- ranch.best de chaque ranch ; `opts.squishies` : squishies du ranch 3 ; `opts.camera` : démarre
	-- aussi CameraController ; `opts.reducedMotion`
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		if opts.me then
			h.localPlayer.UserId = opts.me
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local Prefs = h:require(CLIENT .. "Util.Prefs")
		Prefs.Init()
		if opts.reducedMotion then
			Prefs.reducedMotion = function()
				return true
			end
		end
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local list = folder(folder(h.workspace, "Wobbleton"), "Ranches")
		local models = {}
		for slot = 1, 16 do
			models[slot] = folder(list, tostring(slot), "Model")
		end
		local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local VFX = h:require(CLIENT .. "Controllers.VFXController")
		VFX.Init()
		VFX.Start()
		local CAM = nil
		if opts.camera then
			CAM = h:require(CLIENT .. "Controllers.CameraController")
			CAM.Init()
			CAM.Start()
		end
		local c = {
			CAM = CAM,
			SH = h:require(CLIENT .. "World.ShowsV2"),
			EM = h:require(CLIENT .. "World.Emotes"),
			flashes = 0,
			h = h,
			RR = RR,
			VFX = VFX,
			WSC = WSC,
			Clock = Clock,
			models = models,
			BP = h:require(CLIENT .. "World.BigPlop"),
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			VB = h:require(CLIENT .. "Render.VisualBudget"),
			sounds = {},
			haptics = {},
			elements = {},
			snap = nil,
			payable = false,
			ready = true,
			cold = false,
			timers = {},
		}
		c.BP._configure({
			play = function(name)
				table.insert(c.sounds, { name = name, t = Clock.now() - (c.t0 or T0) })
			end,
			haptic = function(name)
				table.insert(c.haptics, { name = name, t = Clock.now() - (c.t0 or T0) })
			end,
			snapshot = function()
				return c.snap
			end,
			payable = function()
				return c.payable
			end,
			attr = function(name)
				return if name == "AscendReady" then c.ready else nil
			end,
			winter = function()
				return c.cold
			end,
			-- minuterie à 1 Hz de la condition du geste (lot I, étape 5) : jouée sur l'horloge figée
			after = function(seconds, fn, gen)
				table.insert(c.timers, { at = Clock.now() + seconds, fn = fn, gen = gen })
			end,
		})
		-- repères des éléments « dessinés » (RanchRenderer.elementCFrame remplacé : aucun décor v2.0 ici)
		RR.elementCFrame = function(slot, id)
			local at = c.elements[slot .. ":" .. id]
			return at
		end
		c.SH._configure({
			play = function(name, pitch)
				table.insert(c.sounds, { name = name, pitch = pitch, t = Clock.now() - (c.t0 or T0) })
			end,
			haptic = function(name)
				table.insert(c.haptics, { name = name, t = Clock.now() - (c.t0 or T0) })
			end,
			flash = function()
				c.flashes += 1
			end,
		})
		c.EM._configure({
			play = function(name)
				table.insert(c.sounds, { name = name, t = Clock.now() - (c.t0 or T0) })
			end,
		})
		local OWNERS = { [3] = 1, [4] = 2, [10] = 3 }
		local seq = 0
		-- instantané des ranchs ; `gone` : ranchs libérés (userId 0)
		function c.snapshot(gone)
			seq += 1
			local ranches = {}
			for slot = 1, 16 do
				local r = ranch(slot, if gone and gone[slot] then 0 else (OWNERS[slot] or 100 + slot))
				if opts.best then
					r.best = table.clone(opts.best)
				end
				ranches[tostring(slot)] = r
			end
			h:fireClient(
				REMOTES .. "RanchSnapshot",
				{ seq = seq, ranches = ranches, squishies = { ["3"] = opts.squishies or {} } }
			)
			h:settle(1)
		end
		c.snapshot()
		function c.event(v2, over)
			local ev = UpgradeScreen.eventState(v2, over and over.spectacle)
			for key, value in over or {} do
				if key ~= "spectacle" then
					ev[key] = value
				end
			end
			h:fireClient(REMOTES .. "EventState", ev)
			h:settle(1)
		end
		function c.frame(dt)
			Clock.advance(dt)
			-- minuteries échues (BigPlop) avant l'image, dans l'ordre d'armement
			local due = nil
			for i = #c.timers, 1, -1 do
				if c.timers[i].at <= Clock.now() + 1e-9 then
					due = due or {}
					table.insert(due, 1, table.remove(c.timers, i))
				end
			end
			for _, t in due or {} do
				t.fn(t.gen)
			end
			h.game.RunService.RenderStepped:Fire(dt)
		end
		function c.play(seconds, fps)
			local dt = 1 / (fps or 60)
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				c.frame(dt)
			end
			h:settle(1)
		end
		-- un élément v2.0 arrive dans le ranch `slot` (premier passage)
		function c.build(slot, id, at)
			c.elements[slot .. ":" .. id] = at or CFrame.new(c.WL.helperHouse(slot))
			c.t0 = Clock.now()
			RR.ElementBuilt:Fire(slot, id)
			h:settle(1)
		end
		function c.me(pos)
			if h.localPlayer.Character == nil then
				h:respawn(h.localPlayer)
			end
			h:moveTo(h.localPlayer, pos + Vector3.new(0, 3, 0))
		end
		function c.instances()
			local root = h.workspace:FindFirstChild("ClientWorld")
			local f = root and root:FindFirstChild("BigPlop")
			return if f then #f:GetChildren() else 0
		end
		function c.flat(a, b)
			return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
		end
		function c.labels()
			local out = {}
			for _, d in h.game:GetDescendants() do
				if d.Name == "ChantierLabel" and d:IsA("BillboardGui") and d.Enabled then
					for _, l in d:GetDescendants() do
						if l:IsA("TextLabel") and l.Text ~= "" then
							table.insert(out, l.Text)
						end
					end
				end
			end
			return out
		end
		function c.cele(kind, data)
			h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = data })
			h:settle(1)
		end
		function c.attr(slot, name, value)
			models[slot]:SetAttribute(name, value)
			h:settle(1)
		end
		-- images sans avancer l'horloge (horloge figée)
		function c.frozen(seconds)
			local dt = 1 / 60
			for _ = 1, math.floor(seconds / dt + 0.5) do
				h.game.RunService.RenderStepped:Fire(dt)
			end
			h:settle(1)
		end
		function c.vfxModels()
			local root = h.workspace:FindFirstChild("ClientWorld")
			local f = root and root:FindFirstChild("VFX")
			local n = 0
			for _, d in (if f then f:GetChildren() else {}) do
				if d:IsA("Model") then
					n += 1
				end
			end
			return n
		end
		function c.texts(pattern)
			local out = {}
			for _, d in h.game:GetDescendants() do
				if d:IsA("TextLabel") and d.Text ~= "" and string.find(d.Text, pattern, 1, true) then
					local gui = d:FindFirstAncestorWhichIsA("BillboardGui")
					if d.Visible and (gui == nil or gui.Enabled) then
						table.insert(out, d.Text)
					end
				end
			end
			return out
		end
		function c.named(list, name)
			local out = {}
			for _, e in list do
				if e.name == name then
					table.insert(out, e)
				end
			end
			return out
		end
		-- état final comparable entre deux clients
		function c.final()
			local st = c.SH._state()
			return {
				petits = next(st.petits) == nil,
				ascend = st.ascend == nil,
				models = c.vfxModels(),
				used = c.VB.used("shows"),
				looping = c.SH.stats().looping,
				best = WSC.ranch(3).best.s,
				owner = WSC.ranch(3).userId,
			}
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return c
	end

	describe("VFXController v2 › Chantier de Big Plop (lot B5, étape 3)", function()
		it(
			"interrupteurs coupés : aucun élément, aucun geste, aucune instance, aucune boucle par image ; deux écoutes de signaux seulement",
			function()
				local c = client()
				c.event(nil)
				c.snap = {}
				c.play(400, 2)
				local s = c.BP.stats()
				expect({ s.chantiers, s.gestures, s.live, s.looping, s.connections, s.timer }).toEqual({
					0,
					0,
					0,
					0,
					2,
					0,
				})
				expect(
					c.h.workspace:FindFirstChild("ClientWorld")
						and c.h.workspace.ClientWorld:FindFirstChild("BigPlop")
				).toBeNil()
				expect(c.VB.declared("bigPlop")).toBe(false)
				c.clean()
			end
		)

		it(
			"MON ranch : casqué, 2 studs à côté de l'élément et tourné vers lui ; 3 coups à 0,6 / 1,4 / 2,2 s (ChantierTap → Click, vibration « chantier ») ; étiquette « Nouveau : … » 3 s ; fini à 4 s sans aucune instance",
			function()
				local c = client()
				c.event(nil)
				local at = c.WL.helperHouse(3)
				c.build(3, "helper.house", CFrame.new(at))
				local st = c.BP._state()
				expect(st.kind).toBe("chantier")
				expect(st.mine).toBe(true)
				expect(math.abs(c.flat(st.base.Position, at) - 2) < 1e-4).toBe(true)
				local look = st.base.LookVector
				local want = (Vector3.new(at.X, 0, at.Z) - Vector3.new(
					st.base.Position.X,
					0,
					st.base.Position.Z
				)).Unit
				expect(look:Dot(want) > 0.999).toBe(true)
				expect(st.head.Name).toBe("Helmet")
				expect(st.mallet ~= nil).toBe(true)
				expect(st.outfit).toBe("bowTie")
				expect(c.labels()).toEqual({ "New: Plopette House" })
				c.play(2.9)
				expect(#c.labels()).toBe(1)
				c.play(0.2)
				expect(#c.labels()).toBe(0)
				c.play(1)
				expect(c.BP._state()).toBeNil()
				local times = {}
				for i, s in c.sounds do
					expect(s.name).toBe("Click")
					expect(c.haptics[i].name).toBe("chantier")
					times[i] = s.t
				end
				expect(#times).toBe(3)
				for i, want in { 0.6, 1.4, 2.2 } do
					expect(times[i] >= want - 1e-6 and times[i] < want + 1 / 60 + 1e-6).toBe(true)
				end
				expect(c.instances()).toBe(0)
				expect(c.VB.used("bigPlop")).toBe(0)
				expect(c.BP.stats().looping).toBe(0)
				c.clean()
			end
		)

		it(
			"ranch d'un voisin en détail complet : même chantier, sans son, sans vibration, sans étiquette ; même état final",
			function()
				local c = client()
				c.event(nil)
				expect(c.RR.detail(4)).toBe("full")
				c.build(4, "tier1.pompomArch", CFrame.new(c.WL.helperHouse(4)))
				expect(c.BP._state().mine).toBe(false)
				expect(#c.labels()).toBe(0)
				c.play(4.2)
				expect(c.BP.stats().taps).toBe(3)
				expect(#c.sounds + #c.haptics).toBe(0)
				expect(c.BP._state()).toBeNil()
				expect(c.instances()).toBe(0)
				c.clean()
			end
		)

		it(
			"jamais : ranch en détail réduit, éléments du ciel et de la silhouette, élément non dessiné, pendant un grand spectacle ; un seul chantier à la fois",
			function()
				local c = client()
				c.event(nil)
				expect(c.RR.detail(10)).toBe("reduced")
				c.build(10, "tier1.pompomArch")
				c.build(3, "sky")
				c.build(3, "frame.golden")
				c.build(3, "giant.sun")
				c.RR.ElementBuilt:Fire(3, "vat") -- aucun repère : élément non dessiné
				c.h:settle(1)
				expect(c.BP.stats().chantiers).toBe(0)
				for _, over in
					{
						{
							rush = {
								active = true,
								index = 1,
								endsAt = T0 + 999,
								nextAt = 0,
								moonBoopable = false,
							},
						},
						{
							spectacle = {
								current = {
									kind = "ascend",
									userId = 77,
									startedAt = T0,
									burstAt = T0 + 4,
									endsAt = c.Clock.now() + 10,
									level = 1,
								},
								queue = {},
							},
						},
					}
				do
					c.event(nil, over)
					c.build(3, "tier2.candyTower")
					expect(c.BP.stats().chantiers).toBe(0)
				end
				c.event(nil)
				c.build(3, "vat")
				expect(c.BP.stats().chantiers).toBe(1)
				expect(#c.labels()).toBe(0) -- la Cuve n'a pas de nom de carte : pas d'étiquette
				c.build(3, "tier3.jellyBalcony")
				expect(c.BP.stats().chantiers).toBe(1)
				c.play(4.2)
				expect(c.instances()).toBe(0)
				c.clean()
			end
		)

		it(
			"coupures dures : un grand spectacle qui commence coupe à l'image ; le ranch qui quitte le détail complet aussi ; une image en retard de 7 s finit tout",
			function()
				local c = client()
				c.event(nil)
				c.build(3, "monument.1")
				c.play(1)
				c.event(nil, {
					mega = {
						phase = "warn",
						index = 1,
						landsAt = T0 + 99,
						endsAt = T0 + 199,
						target = 10,
						points = 0,
						species = 1,
						moon = false,
						result = "",
					},
				})
				c.play(1 / 60)
				expect(c.BP._state()).toBeNil()
				expect(c.instances()).toBe(0)
				c.event(nil)
				c.build(4, "monument.2")
				c.play(0.5)
				c.me(c.WL.penSlot(10, 5))
				c.play(1 / 60)
				expect(c.BP._state()).toBeNil()
				c.me(c.WL.penSlot(3, 5))
				c.play(0.2)
				c.build(3, "monument.3")
				c.Clock.advance(7)
				c.frame(1 / 60)
				expect(c.BP._state()).toBeNil()
				expect(c.instances()).toBe(0)
				expect(c.VB.used("bigPlop")).toBe(0)
				expect(c.BP.stats().cut).toBe(2)
				c.clean()
			end
		)

		it(
			"costume d'hiver : écharpe d'hiver au lieu du nœud ; le casque gagne pendant un chantier",
			function()
				local c = client()
				c.event(nil)
				c.cold = true
				c.build(3, "helper.house")
				local st = c.BP._state()
				expect(st.outfit).toBe("winterScarf")
				expect(st.head.Name).toBe("Helmet")
				c.play(4.2)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › geste de Big Plop vers l'Observatoire (lot B5, étape 3)", function()
		it(
			"Ascension prête et rien de payable depuis 300 s : 6 studs devant moi, tourné vers l'Observatoire, 3 bonds et 3 points Neon, 4 s ; une fois par séance ; hiver : bonnet",
			function()
				local c = client()
				c.cold = true
				c.event({ JellyAscend = true })
				c.me(c.WL.penSlot(3, 5))
				c.snap = {}
				-- lot I, étape 5 (B5-69 c) : la condition se lit à 1 Hz par une minuterie, sans boucle par image
				expect(c.BP.stats().looping).toBe(0)
				expect(c.BP.stats().timer).toBe(1)
				c.play(298, 4)
				expect(c.BP.stats().gestures).toBe(0)
				c.play(4, 4)
				expect(c.BP.stats().gestures).toBe(1)
				local st = c.BP._state()
				expect(st.kind).toBe("gesture")
				local root = c.h.localPlayer.Character.HumanoidRootPart
				expect(math.abs(c.flat(st.base.Position, root.Position) - 6) < 1e-3).toBe(true)
				local obs = c.WL.observatory().Position
				local want = (Vector3.new(obs.X, 0, obs.Z) - Vector3.new(
					st.base.Position.X,
					0,
					st.base.Position.Z
				)).Unit
				expect(st.base.LookVector:Dot(want) > 0.999).toBe(true)
				expect(st.dots).toBe(3)
				expect(st.head.Name).toBe("WinterHat")
				expect(st.outfit).toBe("winterScarf")
				expect(st.mallet).toBeNil()
				for _, d in c.h.workspace.ClientWorld.BigPlop:GetChildren() do
					if string.match(d.Name, "^Dot") then
						expect(d.Material).toBe(Enum.Material.Neon)
					end
				end
				c.play(4.5)
				expect(c.BP._state()).toBeNil()
				expect(c.instances()).toBe(0)
				expect(c.BP.stats().looping).toBe(0)
				expect(c.BP.stats().timer).toBe(0)
				-- une fois par séance
				c.play(700, 2)
				expect(c.BP.stats().gestures).toBe(1)
				c.clean()
			end
		)

		it(
			"jamais : JellyAscend fermé, sans instantané, Ascension pas prête, un achat possible (le délai repart), hors de mon ranch, pendant un grand spectacle",
			function()
				local c = client()
				c.me(c.WL.penSlot(3, 5))
				c.snap = {}
				c.event(nil)
				c.play(400, 2)
				expect(c.BP.stats().looping).toBe(0)
				c.event({ JellyAscend = true })
				c.snap = nil
				c.play(400, 2)
				c.snap = {}
				c.ready = false
				c.play(400, 2)
				c.ready = true
				c.payable = true
				c.play(5, 2)
				c.payable = false
				c.play(290, 2)
				expect(c.BP.stats().gestures).toBe(0)
				c.me(c.WL.penSlot(10, 5))
				c.play(20, 2)
				expect(c.BP.stats().gestures).toBe(0)
				c.me(c.WL.penSlot(3, 5))
				c.event({ JellyAscend = true }, {
					rush = {
						active = true,
						index = 1,
						endsAt = T0 + 9999,
						nextAt = 0,
						moonBoopable = false,
					},
				})
				c.play(20, 2)
				expect(c.BP.stats().gestures).toBe(0)
				c.event({ JellyAscend = true })
				c.play(2, 2)
				expect(c.BP.stats().gestures).toBe(1)
				c.play(5)
				expect(c.instances()).toBe(0)
				c.clean()
			end
		)
	end)

	-- =========================================================================================
	-- Étape 4 : spectacles de la v2.0 (World/ShowsV2), caméra de l'Ascension, emotes (World/Emotes)
	-- =========================================================================================

	local BEST = { s = 1, m = 0, z = 2, zg = 0 }
	local function ascendData(c, over)
		local now = c.Clock.now()
		local d = {
			userId = 1,
			ascend = 3,
			startR = 0,
			bestR = 15,
			startedAt = now,
			burstAt = now + 4,
			endsAt = now + 10,
			flyer = { s = 1, m = 0, st = 0, z = 2 },
		}
		for k, v in over or {} do
			d[k] = v
		end
		return d
	end
	local function ascendEvent(c, v2, endsAt)
		c.event(v2, {
			spectacle = {
				current = {
					kind = "ascend",
					userId = 1,
					startedAt = c.Clock.now(),
					burstAt = c.Clock.now() + 4,
					endsAt = endsAt or c.Clock.now() + 10,
					level = 1,
				},
				queue = {},
			},
		})
	end

	describe("VFXController v2 › interrupteurs coupés (lot B5, étape 4)", function()
		it(
			"chaque message v2.0 rejoué, charges hostiles comprises : aucune instance, aucune boucle, une seule écoute ; Pluie d'étoiles = pluie de cadeaux de la v1.3",
			function()
				local c = client({ best = BEST })
				c.event(nil)
				c.me(c.WL.penSlot(3, 5))
				local friend = c.h:addPlayer({ userId = 50 })
				c.h:moveTo(friend, c.WL.penSlot(3, 6) + Vector3.new(0, 3, 0))
				local before = c.vfxModels()
				local now = c.Clock.now()
				local hostile = { 0 / 0, math.huge, -1, "x", {}, true }
				for _, bad in hostile do
					c.cele("petitSplorch", { userId = bad, level = bad, startedAt = bad, endsAt = bad })
					c.cele(
						"ascend",
						{ userId = bad, startedAt = bad, burstAt = bad, endsAt = bad, flyer = bad }
					)
					c.cele("tier", { family = bad, tier = bad, key = bad })
					c.cele("recordStep", { share = bad })
					c.cele("regainDone", { bestR = bad, confetti = bad })
				end
				c.cele("petitSplorch", { userId = 1, level = 3, startedAt = now, endsAt = now + 2.5 })
				c.cele("ascend", ascendData(c))
				c.cele("tier", { family = "tapis", tier = 1, key = "tier1" })
				c.cele("recordStep", { share = 0.5 })
				c.cele("regainDone", { bestR = 15, confetti = 10 })
				c.attr(3, "PetitSplorchAt", now)
				c.attr(4, "PetitSplorchAt", now)
				for _, id in c.EM.IDS do
					c.h:fireClient(REMOTES .. "EmoteShow", { userId = 50, kind = 3, emote = id })
				end
				c.h:settle(1)
				c.play(1)
				local s = c.SH.stats()
				expect({
					s.petits,
					s.ascends,
					s.tiers,
					s.recordSteps,
					s.regains,
					s.looping,
					s.attrConnections,
				}).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect(s.connections).toBe(1)
				expect(c.EM.stats().shown).toBe(0)
				expect(c.EM.stats().connections).toBe(1)
				expect(c.vfxModels()).toBe(before)
				expect(c.VB.declared("shows")).toBe(false)
				expect(c.h.workspace.ClientWorld:FindFirstChild("Emotes")).toBeNil()
				expect(#c.sounds + #c.haptics + c.flashes).toBe(0)
				-- giftRain d'un héros : la pluie de cadeaux de la v1.3 (texte celebrate.giftRain)
				c.cele(
					"giftRain",
					{ heroId = 1, heroName = "P3", coins = 5, uid = "", species = 1, short = false }
				)
				expect(c.SH.stats().starRains).toBe(0)
				expect(c.VFX.stats().texts).toBe(1)
				c.play(1)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › Petit Splorch (lot B5, étape 4)", function()
		it(
			"un dossier de ranch répliqué APRÈS l'ouverture de PetitSplorch reçoit aussi son écoute ; l'interrupteur fermé, plus aucune écoute (lot I, étape 5, constat B5-69 e)",
			function()
				local c = client({ me = 2, best = BEST })
				local list = c.models[5].Parent
				c.models[5].Parent = nil
				c.event({ PetitSplorch = true })
				expect(c.SH.stats().attrConnections).toBe(15)
				expect(c.SH.stats().listConnection).toBe(1)
				c.models[5].Parent = list
				c.h:settle(1)
				expect(c.SH.stats().attrConnections).toBe(16)
				local now = c.Clock.now()
				c.attr(5, "PetitSplorchAt", now)
				c.attr(3, "PetitSplorchAt", now)
				expect(c.SH.stats().petits >= 1).toBe(true)
				c.play(3)
				c.event(nil)
				expect(c.SH.stats().attrConnections).toBe(0)
				expect(c.SH.stats().listConnection).toBe(0)
				expect(c.SH.stats().connections).toBe(1)
				c.clean()
			end
		)

		it(
			"propriétaire et voisin nourris des mêmes messages : même copie qui saute, rétrécit et éclate (30 confettis), même état final ; texte, son 1,2 et vibration au propriétaire seul",
			function()
				local finals = {}
				for _, me in { 1, 2 } do
					local c = client({ me = me, best = BEST })
					c.event({ PetitSplorch = true })
					expect(c.SH.stats().attrConnections).toBe(16)
					local now = c.Clock.now()
					c.t0 = now
					c.cele("petitSplorch", { userId = 1, level = 4, startedAt = now, endsAt = now + 2.5 })
					c.attr(3, "PetitSplorchAt", now)
					local st = c.SH._state().petits[3]
					expect(st ~= nil and st.model ~= nil).toBe(true)
					local body = st.model:FindFirstChild("Body", true) or st.model.PrimaryPart
					c.play(0.45)
					local up = c.SH._state().petits[3]
					expect(up.popped).toBe(false)
					c.play(1.1)
					expect(c.SH._state().petits[3].popped).toBe(true)
					expect(c.SH._state().petits[3].model).toBeNil()
					local particles = c.VFX.stats().particles
					expect(particles >= 30 and particles <= 40).toBe(true)
					c.play(1.0)
					expect(c.SH._state().petits[3]).toBeNil()
					local texts = c.texts("is here! ×2!")
					if me == 1 then
						expect(#c.named(c.sounds, "SplorchPop")).toBe(1)
						expect(c.named(c.sounds, "SplorchPop")[1].pitch).toBe(1.2)
						expect(#c.named(c.haptics, "holdDone")).toBe(1)
						expect(c.SH.stats().petitTexts).toBe(1)
					else
						expect(#c.sounds + #c.haptics).toBe(0)
						expect(c.SH.stats().petitTexts).toBe(0)
						expect(#texts).toBe(0)
					end
					c.play(1)
					finals[me] = c.final()
					expect(finals[me].used).toBe(0)
					expect(finals[me].looping).toBe(0)
					c.clean()
					local _ = body
				end
				expect(finals[1]).toEqual(finals[2])
			end
		)

		it(
			"rien : client lointain (détail réduit), attribut plus vieux que 2,5 s, interrupteur fermé, pendant un grand spectacle ; coupure dure à 4 s d'images (horloge figée), héros parti, interrupteur fermé en direct",
			function()
				local far = client({ me = 3, best = BEST })
				far.event({ PetitSplorch = true })
				expect(far.RR.detail(3)).toBe("reduced")
				far.attr(3, "PetitSplorchAt", far.Clock.now())
				expect(far.SH.stats().petits).toBe(0)
				expect(far.vfxModels()).toBe(0)
				far.clean()
				local c = client({ best = BEST })
				c.event({ PetitSplorch = true })
				c.attr(3, "PetitSplorchAt", c.Clock.now() - 2.6)
				expect(c.SH.stats().petits).toBe(0)
				ascendEvent(c, { PetitSplorch = true })
				c.attr(4, "PetitSplorchAt", c.Clock.now())
				expect(c.SH.stats().petits).toBe(0)
				expect(c.SH.stats().quiet).toBe(1)
				c.event({ PetitSplorch = true })
				-- horloge figée : 4 s d'images au plus
				c.attr(3, "PetitSplorchAt", c.Clock.now())
				expect(c.SH.stats().livePetits).toBe(1)
				c.frozen(3.9)
				expect(c.SH.stats().livePetits).toBe(1)
				c.frozen(0.2)
				expect(c.SH.stats().livePetits).toBe(0)
				expect(c.SH.stats().cut).toBe(1)
				-- héros parti
				c.attr(4, "PetitSplorchAt", c.Clock.now() + 0.001)
				expect(c.SH.stats().livePetits).toBe(1)
				c.snapshot({ [4] = true })
				c.play(1 / 30)
				expect(c.SH.stats().livePetits).toBe(0)
				c.snapshot()
				-- interrupteur fermé en direct : tout rendu, plus aucune écoute
				c.attr(3, "PetitSplorchAt", c.Clock.now() + 0.01)
				expect(c.SH.stats().livePetits).toBe(1)
				c.event(nil)
				expect(c.SH.stats().livePetits).toBe(0)
				expect(c.SH.stats().attrConnections).toBe(0)
				expect(c.vfxModels()).toBe(0)
				expect(c.VB.used("shows")).toBe(0)
				c.play(0.5)
				expect(c.SH.stats().looping).toBe(0)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › Jelly Ascend (lot B5, étape 4)", function()
		it(
			"héros et voisin : copie à la taille copiée qui monte, éclat EXACTEMENT à burstAt (60 étincelles, anneau, tampon « JELLY ASCEND » étoile dessinée), redescend à sa nouvelle taille et se pose à endsAt ; vibration et éclair au héros seul ; même état final",
			function()
				local squishies =
					{ a1 = { s = 1, m = 0, st = 0, z = 1, zg = 0, bf = 1, o = "", at = "pen", ready = 0 } }
				local finals = {}
				for _, me in { 1, 2 } do
					local c = client({ me = me, best = BEST, squishies = squishies })
					c.event({ JellyAscend = true })
					c.t0 = c.Clock.now()
					local d = ascendData(c)
					c.cele("ascend", d)
					local st = c.SH._state().ascend
					expect(st ~= nil and st.model ~= nil).toBe(true)
					local SizeScale = c.h:require("ReplicatedStorage.Shared.Logic.SizeScale")
					expect(st.upScale).toBe(SizeScale.display(2, "pen"))
					local AscendPath = c.h:require(CLIENT .. "World.AscendPath")
					local start, sky = AscendPath.endpoints(3)
					c.play(2)
					local y2 = c.SH._state().ascend.body.Position.Y
					expect(y2 > start.Y + 5).toBe(true)
					c.play(1.97)
					expect(c.SH._state().ascend.marks.burst).toBeNil()
					c.play(0.05)
					expect(c.SH._state().ascend.marks.burst).toBe(true)
					local pop = c.named(c.sounds, "SplorchPop")
					expect(#pop).toBe(1)
					expect(pop[1].t >= 4 - 1e-6 and pop[1].t < 4 + 1 / 60 + 1e-6).toBe(true)
					expect(#c.named(c.sounds, "SplorchCharge")).toBe(1)
					expect(c.named(c.sounds, "SplorchCharge")[1].t < 1 / 60 + 1e-6).toBe(true)
					local particles = c.VFX.stats().particles
					expect(particles >= 60 and particles <= 120).toBe(true)
					local stamp = c.texts("JELLY ASCEND")
					expect(#stamp).toBe(1)
					expect(string.find(stamp[1], "{*}", 1, true)).toBeNil()
					local ratio = c.SH._state().ascend.newRatio
					expect(math.abs(ratio - SizeScale.display(1, "pen") / SizeScale.display(2, "pen")) < 1e-6).toBe(
						true
					)
					if me == 1 then
						expect(#c.named(c.haptics, "ascend")).toBe(1)
						expect(c.flashes).toBe(1)
					else
						expect(#c.haptics).toBe(0)
						expect(c.flashes).toBe(0)
					end
					c.play(2.5)
					expect(#c.texts("×3 every loop!")).toBe(1)
					-- redescente : sous le ciel, puis posé au départ
					c.play(2)
					local yd = c.SH._state().ascend.body.Position.Y
					expect(yd < sky.Y).toBe(true)
					c.play(1.6)
					expect(c.SH._state().ascend).toBeNil()
					expect(c.SH.heroId()).toBe(1)
					c.play(1)
					finals[me] = c.final()
					expect(finals[me].used).toBe(0)
					expect(c.SH.stats().cut).toBe(0)
					c.clean()
				end
				expect(finals[1]).toEqual(finals[2])
			end
		)

		it(
			"client lointain : rien de dessiné (héros retenu pour la Pluie d'étoiles) ; coupures dures : 12 s d'images sans fin, héros parti, interrupteur fermé en direct ; Mouvement réduit : pas d'éclair",
			function()
				local far = client({ me = 3, best = BEST })
				far.event({ JellyAscend = true })
				far.cele("ascend", ascendData(far))
				expect(far.SH.stats().ascends).toBe(1)
				expect(far.SH.stats().ascendDrawn).toBe(0)
				expect(far.vfxModels()).toBe(0)
				expect(far.SH.heroId()).toBe(1)
				far.play(11)
				expect(far.vfxModels()).toBe(0)
				far.clean()
				local c = client({ best = BEST, reducedMotion = true })
				c.event({ JellyAscend = true })
				c.cele("ascend", ascendData(c))
				c.frozen(11.9)
				expect(c.SH._state().ascend ~= nil).toBe(true)
				c.frozen(0.2)
				expect(c.SH._state().ascend).toBeNil()
				expect(c.flashes).toBe(0)
				c.cele("ascend", ascendData(c, { startedAt = c.Clock.now() + 0.001 }))
				c.play(1)
				c.snapshot({ [3] = true })
				c.play(1 / 30)
				expect(c.SH._state().ascend).toBeNil()
				c.snapshot()
				c.cele("ascend", ascendData(c, { startedAt = c.Clock.now() + 0.002 }))
				c.play(5)
				c.event(nil)
				expect(c.SH._state().ascend).toBeNil()
				expect(c.SH.heroId()).toBe(0)
				expect(c.vfxModels()).toBe(0)
				expect(c.VB.used("shows")).toBe(0)
				expect(c.SH.stats().cut).toBe(3)
				-- charges refusées : durée au-delà de 12 s, éclat hors du spectacle
				c.event({ JellyAscend = true })
				c.cele("ascend", ascendData(c, { endsAt = c.Clock.now() + 12.5 }))
				c.cele("ascend", ascendData(c, { burstAt = c.Clock.now() + 11 }))
				expect(c.SH._state().ascend).toBeNil()
				c.play(0.5)
				expect(c.SH.stats().looping).toBe(0)
				c.clean()
			end
		)

		it(
			"un seul grand spectacle : pendant l'Ascension, Petit Splorch, Palier et étape du record restent sans dessin (son et vibration du Palier gardés) ; aucun Chantier sur le ranch du spectacle",
			function()
				local c = client({ me = 2, best = BEST })
				c.event({ JellyAscend = true, PetitSplorch = true, RecordR = true })
				c.attr(4, "TapisTier", 1)
				c.cele("ascend", ascendData(c))
				c.play(1)
				c.attr(4, "PetitSplorchAt", c.Clock.now())
				c.cele("tier", { family = "tapis", tier = 2, key = "tier2" })
				c.cele("recordStep", { share = 0.25 })
				local s = c.SH.stats()
				expect(s.livePetits).toBe(0)
				expect(s.quiet).toBe(3)
				expect(#c.named(c.sounds, "LevelUp")).toBe(1)
				expect(#c.named(c.haptics, "tierUp")).toBe(1)
				c.build(3, "monument.1")
				expect(c.BP.stats().chantiers).toBe(0)
				c.play(10)
				expect(c.vfxModels()).toBe(0)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › Pluie d'étoiles, record, Palier, palette (lot B5, étape 4)", function()
		it(
			"Pluie d'étoiles seulement pour le héros de l'Ascension en cours (20 étincelles dorées en 3 s, GiftRain, aucun texte : celui de UI/Banners) ; un autre héros, short, ou une 2e : la v1.3",
			function()
				local c = client({ me = 2, best = BEST })
				c.event({ JellyAscend = true })
				c.me(c.WL.penSlot(4, 5))
				c.cele("ascend", ascendData(c))
				c.play(4.1)
				local before = c.VFX.stats().particles
				c.cele(
					"giftRain",
					{ heroId = 99, heroName = "X", coins = 5, uid = "", species = 1, short = false }
				)
				expect(c.SH.stats().starRains).toBe(0)
				expect(c.VFX.stats().texts).toBe(1)
				c.play(1)
				c.cele(
					"giftRain",
					{ heroId = 1, heroName = "P3", coins = 5, uid = "", species = 1, short = true }
				)
				expect(c.SH.stats().starRains).toBe(0)
				c.play(1)
				local texts = c.VFX.stats().texts
				c.cele(
					"giftRain",
					{ heroId = 1, heroName = "P3", coins = 5, uid = "", species = 1, short = false }
				)
				expect(c.SH.stats().starRains).toBe(1)
				expect(#c.named(c.sounds, "GiftRain")).toBe(1)
				expect(c.VFX.stats().texts).toBe(texts)
				local peak = 0
				for _ = 1, 200 do
					c.frame(1 / 60)
					peak = math.max(peak, c.VFX.stats().particles)
					expect(c.VFX.stats().particles <= 120).toBe(true)
				end
				expect(c.SH.stats().rain).toBe(0)
				c.cele(
					"giftRain",
					{ heroId = 1, heroName = "P3", coins = 5, uid = "", species = 1, short = false }
				)
				expect(c.SH.stats().starRains).toBe(1)
				local _ = before
				c.play(8)
				c.clean()
			end
		)

		it(
			"étape du record (30 confettis), retour au record (60 confettis, ConfettiGain → Coin), Palier (anneau 0 → 40 studs en 0,6 s, 30 confettis, LevelUp, tierUp, ola) ; aucun texte",
			function()
				local c = client({ best = BEST })
				c.event({ RecordR = true, PetitSplorch = true, Personalities = true })
				c.cele("recordStep", { share = 0.5 })
				expect(c.VFX.stats().particles).toBe(30)
				c.play(1)
				c.cele("regainDone", { bestR = 15, confetti = 10 })
				expect(c.VFX.stats().particles).toBe(60)
				expect(#c.named(c.sounds, "Coin")).toBe(1)
				c.play(1)
				-- Palier sans RanchTiers (pas d'attribut TapisTier sur MON ranch) : rien
				c.cele("tier", { family = "tapis", tier = 1, key = "tier1" })
				expect(c.SH.stats().tiers).toBe(0)
				c.attr(3, "TapisTier", 1)
				c.cele("tier", { family = "tapis", tier = 1, key = "tier1" })
				expect(c.SH.stats().tiers).toBe(1)
				expect(#c.named(c.sounds, "LevelUp")).toBe(1)
				expect(#c.named(c.haptics, "tierUp")).toBe(1)
				expect(c.VFX.stats().particles).toBe(30)
				local ring = nil
				for _, d in c.h.workspace.ClientWorld.VFX:GetChildren() do
					if d.Name == "Ring" then
						ring = d
					end
				end
				expect(ring ~= nil).toBe(true)
				expect(ring.Material).toBe(Enum.Material.Neon)
				c.play(0.55)
				expect(ring.Size.Y > 30 and ring.Size.Y <= 40).toBe(true)
				c.play(0.1)
				expect(ring.Parent).toBeNil()
				expect(#c.texts("Tier") + #c.texts("Palier")).toBe(0)
				c.play(3)
				c.clean()
			end
		)

		it(
			'Palier envoyé par le serveur (lot I, étape 5, M29 : RanchService, charge { family = "snack" | "star", tier, key }) : joué une fois par message, palier 5 du Tapis Étoilé compris',
			function()
				local c = client({ best = BEST })
				c.event({ RecordR = true })
				c.attr(3, "TapisTier", 3)
				c.cele("tier", { family = "snack", tier = 3, key = "upgrades.tier.snack.3" })
				expect(c.SH.stats().tiers).toBe(1)
				c.play(3)
				c.cele("tier", { family = "star", tier = 5, key = "upgrades.tier.snack.5" })
				expect(c.SH.stats().tiers).toBe(2)
				expect(#c.named(c.sounds, "LevelUp")).toBe(2)
				expect(#c.named(c.haptics, "tierUp")).toBe(2)
				c.play(3)
				expect(c.vfxModels()).toBe(0)
				c.clean()
			end
		)

		it(
			"palette du spectacle : « peachPalette » (identifiant gardé, lot I D4 ; « peach » n'en est plus un), nom inconnu ou abîmé = couleurs de la v1.3 ; le nuage du Grand Splorch du ranch prend la palette",
			function()
				local c = client({ best = BEST })
				c.event(nil)
				expect(c.SH.paletteOf(3)).toBeNil()
				c.attr(3, "Palette", "peachPalette")
				local peach = c.SH.paletteOf(3)
				expect(#peach).toBe(4)
				-- l'ancien nom de Visuals.Palettes n'est plus lu (aucun alias : un seul identifiant)
				c.attr(3, "Palette", "peach")
				expect(c.SH.paletteOf(3)).toBeNil()
				for _, bad in { "neon", "", string.rep("a", 40), 3, true } do
					c.attr(3, "Palette", bad)
					expect(c.SH.paletteOf(3)).toBeNil()
				end
				expect(c.SH.paletteOf(0)).toBeNil()
				expect(c.SH.paletteOf(17)).toBeNil()
				local function splorchColors()
					local now = c.Clock.now()
					c.cele("splorch", {
						userId = 1,
						level = 2,
						flyer = { s = 1, m = 0, st = 0, z = 2 },
						startedAt = now,
						burstAt = now + 3.2,
						endsAt = now + 7.5,
						short = false,
					})
					c.play(3.25)
					local colors = {}
					for _, d in c.h.workspace.ClientWorld.VFX:GetChildren() do
						if d.Name == "Blob" and d.Parent ~= nil then
							colors[d.Color:ToHex()] = true
						end
					end
					c.play(5)
					return colors
				end
				c.attr(3, "Palette", "neon")
				local plain = splorchColors()
				expect(plain).toEqual({ [Color3.fromRGB(255, 170, 210):ToHex()] = true })
				c.attr(3, "Palette", "peachPalette")
				local painted = splorchColors()
				local want = {}
				for _, col in peach do
					want[col:ToHex()] = true
				end
				expect(painted).toEqual(want)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › caméra de la Jelly Ascend (lot B5, étape 4)", function()
		it(
			"héros : la caméra suit la copie puis revient EXACTEMENT (type, focale, CFrame) à endsAt ; horloge figée : au plus 12 s d'images ; voisin et Mouvement réduit : jamais",
			function()
				for _, case in { "normal", "frozen", "neighbour", "reduced" } do
					local c = client({
						camera = true,
						best = BEST,
						me = if case == "neighbour" then 2 else 1,
						reducedMotion = case == "reduced",
					})
					c.event({ JellyAscend = true })
					local cam = c.h.workspace.CurrentCamera
					local before = { cam.CameraType, cam.FieldOfView, cam.CFrame }
					c.cele("ascend", ascendData(c))
					if case == "frozen" then
						c.frozen(1)
					else
						c.play(1)
					end
					if case == "neighbour" or case == "reduced" then
						expect(c.CAM.leaseHolder()).toBeNil()
						expect(cam.CameraType).toBe(before[1])
					else
						expect(c.CAM.leaseHolder()).toBe("show")
						expect(cam.CameraType).toBe(Enum.CameraType.Scriptable)
						local body = c.SH._state().ascend.body
						expect(cam.CFrame.LookVector:Dot((body.Position - cam.CFrame.Position).Unit) > 0.99).toBe(
							true
						)
					end
					if case == "frozen" then
						c.frozen(10.9)
						expect(c.CAM.leaseHolder()).toBe("show")
						c.frozen(0.2)
					else
						c.play(9.1)
					end
					expect(c.CAM.leaseHolder()).toBeNil()
					expect({ cam.CameraType, cam.FieldOfView, cam.CFrame }).toEqual(before)
					c.clean()
				end
			end
		)

		it(
			"bail : le spectacle prend le pas sur un bail plus faible et rend l'état gardé à la fin",
			function()
				local c = client({ camera = true, best = BEST })
				c.event({ JellyAscend = true })
				local cam = c.h.workspace.CurrentCamera
				local before = { cam.CameraType, cam.FieldOfView, cam.CFrame }
				local lost = 0
				expect(c.CAM.takeLease("binoculars", function()
					lost += 1
				end)).toBe(true)
				cam.CameraType = Enum.CameraType.Scriptable
				cam.FieldOfView = 50
				expect(c.CAM.takeLease("photo")).toBe(true)
				expect(lost).toBe(1)
				expect(c.CAM.takeLease("binoculars")).toBe(false)
				c.cele("ascend", ascendData(c))
				c.play(1)
				expect(c.CAM.leaseHolder()).toBe("show")
				c.play(9.1)
				expect(c.CAM.leaseHolder()).toBeNil()
				expect({ cam.CameraType, cam.FieldOfView, cam.CFrame }).toEqual(before)
				expect(c.CAM.takeLease("nope")).toBe(false)
				c.CAM.giveLease("photo") -- sans bail : rien
				c.clean()
			end
		)
	end)

	describe("VFXController › signaux de la croix de la v1.3 (lot I, étape 5, D27)", function()
		it(
			"bulle-icône 2,5 s au-dessus du joueur (main ↑, cœur →, étoile ←), dans les deux états des interrupteurs ; une par joueur toutes les 2 s ; emote de la v2.0 : rien ici ; à plus de 150 studs : rien ; PlayEmote sur MON personnage seulement ; bulles rendues à la réserve",
			function()
				local c = client({ best = BEST })
				local EB = c.h:require(CLIENT .. "World.EmoteBubble")
				local Icons = c.h:require(CLIENT .. "UI.Hud.Icons")
				local played, timers = {}, {}
				EB._configure({
					play = function(_, name)
						table.insert(played, name)
					end,
					after = function(seconds, fn)
						table.insert(timers, { at = c.Clock.now() + seconds, fn = fn })
					end,
				})
				local function flush()
					for i = #timers, 1, -1 do
						if timers[i].at <= c.Clock.now() + 1e-9 then
							table.remove(timers, i).fn()
						end
					end
				end
				c.event(nil)
				c.me(c.WL.penSlot(3, 5))
				local friend = c.h:addPlayer({ userId = 50 })
				c.h:moveTo(friend, c.WL.penSlot(3, 6) + Vector3.new(0, 3, 0))
				local far = c.h:addPlayer({ userId = 51 })
				c.h:moveTo(far, c.WL.penSlot(3, 6) + Vector3.new(400, 3, 0))
				local function emote(userId, kind, id)
					c.h:fireClient(REMOTES .. "EmoteShow", { userId = userId, kind = kind, emote = id })
					c.h:settle(1)
				end
				local function iconShown()
					local folder = c.h.workspace.ClientWorld:FindFirstChild("EmoteBubbles")
					for _, gui in folder and folder:GetChildren() or {} do
						if gui.Enabled then
							expect(gui.Adornee).toBe(friend.Character.HumanoidRootPart)
							return Icons.kindOf(gui.Back.Icon)
						end
					end
					return nil
				end
				-- interrupteurs coupés (v1.3) : ↑ Salut → main
				emote(50, 1, "wave")
				expect(EB.stats().live).toBe(1)
				expect(iconShown()).toBe("hand")
				-- un 2e signal dans les 2 s : ignoré
				c.Clock.advance(1)
				emote(50, 2, "wave")
				expect(EB.stats().skipped).toBe(1)
				c.Clock.advance(1.5)
				flush()
				expect(EB.stats().live).toBe(0)
				emote(50, 2, "wave")
				expect(iconShown()).toBe("heart")
				c.Clock.advance(2.5)
				flush()
				emote(50, 3, "cheer")
				expect(iconShown()).toBe("star")
				c.Clock.advance(2.5)
				flush()
				-- emote de la v2.0 (sorte 3) : World/Emotes la dessine, aucune bulle
				c.event({ RecordR = true })
				emote(50, 3, "splorch")
				expect(EB.stats().live).toBe(0)
				-- trop loin
				emote(51, 1, "wave")
				expect(EB.stats().live).toBe(0)
				-- MON signal : PlayEmote("wave") sur mon personnage ; aucun pour les autres
				expect(played).toEqual({})
				emote(c.h.localPlayer.UserId, 1, "wave")
				expect(played).toEqual({ "wave" })
				expect(EB.stats().shown).toBe(4)
				c.Clock.advance(3)
				flush()
				expect(EB.stats().live).toBe(0)
				expect(EB.stats().pooled >= 1).toBe(true)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › emotes de la v2.0 (lot B5, étape 4)", function()
		it(
			"les 6 emotes (croix ←, sorte 3) : effet au-dessus de la tête, 2,5 s au plus, pièces rendues ; refus : sorte 1 ou 2, emote de la v1.3, joueur à plus de 150 studs, aucun interrupteur",
			function()
				local c = client({ best = BEST })
				c.event({ RecordR = true })
				c.me(c.WL.penSlot(3, 5))
				local friend = c.h:addPlayer({ userId = 50 })
				c.h:moveTo(friend, c.WL.penSlot(3, 6) + Vector3.new(0, 3, 0))
				local far = c.h:addPlayer({ userId = 51 })
				c.h:moveTo(far, c.WL.penSlot(3, 6) + Vector3.new(400, 3, 0))
				local function emote(userId, kind, id)
					c.h:fireClient(REMOTES .. "EmoteShow", { userId = userId, kind = kind, emote = id })
					c.h:settle(1)
				end
				for _, id in c.EM.IDS do
					c.t0 = c.Clock.now()
					emote(50, 3, id)
					expect(c.EM.stats().live).toBe(1)
					local head = friend.Character.HumanoidRootPart.Position
					for _, p in c.h.workspace.ClientWorld.Emotes:GetChildren() do
						expect(p.Position.Y > head.Y + 1).toBe(true)
						expect((p.Position - head).Magnitude < 6).toBe(true)
					end
					c.play(2.6)
					expect(c.EM.stats().live).toBe(0)
					expect(c.EM.stats().parts).toBe(0)
					expect(c.EM.stats().looping).toBe(0)
				end
				expect(c.EM.stats().shown).toBe(6)
				expect(#c.named(c.sounds, "Click")).toBe(3) -- hammerTap : 3 coups (ChantierTap → Click)
				emote(50, 1, "wave")
				emote(50, 2, "wave")
				emote(50, 3, "cheer")
				emote(50, 3, "bravo")
				emote(51, 3, "splorch")
				expect(c.EM.stats().shown).toBe(6)
				expect(c.EM.stats().refused).toBe(1)
				c.event(nil)
				emote(50, 3, "splorch")
				expect(c.EM.stats().shown).toBe(6)
				-- même joueur : la nouvelle remplace l'ancienne
				c.event({ RecordR = true })
				emote(50, 3, "confettiCrown")
				emote(50, 3, "hugEmote")
				expect(c.EM.stats().live).toBe(1)
				expect(c.EM.stats().replaced).toBe(1)
				c.play(3)
				expect(c.EM.stats().parts).toBe(0)
				c.clean()
			end
		)
	end)

	describe("VFXController v2 › aucune fuite (lot B5, étape 4)", function()
		it(
			"40 tours de spectacles sur l'horloge figée (Petit Splorch ×2, Ascension, Pluie d'étoiles, Palier, record, emotes) : instances, connexions et fils identiques aux points calmes ; budgets rendus ; quota de particules jamais dépassé",
			function()
				local c = client({ me = 2, best = BEST })
				c.event({ JellyAscend = true, PetitSplorch = true, RecordR = true })
				c.me(c.WL.penSlot(4, 5))
				local friend = c.h:addPlayer({ userId = 50 })
				c.h:moveTo(friend, c.WL.penSlot(4, 6) + Vector3.new(0, 3, 0))
				c.attr(4, "TapisTier", 1)
				local calm = {}
				for round = 1, 40 do
					local now = c.Clock.now()
					c.attr(3, "PetitSplorchAt", now)
					c.attr(4, "PetitSplorchAt", now)
					c.cele("tier", { family = "tapis", tier = 1, key = "tier1" })
					c.cele("recordStep", { share = 0.75 })
					c.h:fireClient(
						REMOTES .. "EmoteShow",
						{ userId = 50, kind = 3, emote = c.EM.IDS[round % 6 + 1] }
					)
					c.h:settle(1)
					for _ = 1, 180 do
						c.frame(1 / 60)
						expect(c.VFX.stats().particles <= 120).toBe(true)
					end
					c.cele("ascend", ascendData(c))
					c.play(4.2, 30)
					c.cele(
						"giftRain",
						{ heroId = 1, heroName = "P3", coins = 5, uid = "", species = 1, short = false }
					)
					c.play(7, 30)
					c.play(1, 30)
					if round == 5 or round == 40 then
						local n = c.h:counts()
						table.insert(calm, { n.instances, n.connections, n.threads })
					end
					expect(c.VB.used("shows")).toBe(0)
					expect(c.SH.stats().looping + c.EM.stats().looping).toBe(0)
				end
				expect(calm[2]).toEqual(calm[1])
				expect(c.SH.stats().cut).toBe(0)
				expect(c.SH.stats().starRains).toBe(40)
				c.clean()
			end
		)
	end)
end
