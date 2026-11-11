--!nocheck
-- Moments de la v2.0 dessinés par le client (lot B5 ; GDD §4.15, §4.27, §9.4, §11.5, §12.10 ; docs/04
-- §27.10 « voisin = même état final que le propriétaire ; coupures dures » ; plan B5 D17 à D19, D29) :
--   * étape 3 : Chantier de Big Plop (World/BigPlop, sur RanchRenderer.ElementBuilt) : 3 coups de
--     maillet à 0,6 / 1,4 / 2,2 s, 4 s en tout, coupure dure à 6 s, son, vibration et étiquette pour MON
--     ranch seulement, jamais pendant un grand spectacle, état final sans aucune instance ; geste vers
--     l'Observatoire une fois par séance ; costume d'hiver ; interrupteurs coupés : rien ;
--   * étape 4 (à venir) : Petit Splorch, Jelly Ascend, Pluie d'étoiles, record, Palier, emotes.
-- Monde fabriqué, horloge figée, zéro trace (ZeroLog). Tout est en 3D : ces cas prouvent la structure
-- (instances, positions, heures, sons et vibrations demandés) ; personne n'a pu regarder Big Plop.

local roblox = require("@lune/roblox")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

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

	-- Client : miroir, éclairage (test d'hiver), RanchRenderer, VFXController (qui démarre BigPlop) ;
	-- le ranch 3 est le mien (joueur 1)
	local function client()
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:require(CLIENT .. "Util.Prefs").Init()
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
		local c = {
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
		})
		-- repères des éléments « dessinés » (RanchRenderer.elementCFrame remplacé : aucun décor v2.0 ici)
		RR.elementCFrame = function(slot, id)
			local at = c.elements[slot .. ":" .. id]
			return at
		end
		local ranches = {}
		for slot = 1, 16 do
			ranches[tostring(slot)] = ranch(slot, if slot == 3 then 1 else 100 + slot)
		end
		h:fireClient(REMOTES .. "RanchSnapshot", { seq = 1, ranches = ranches, squishies = {} })
		h:settle(1)
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
				expect({ s.chantiers, s.gestures, s.live, s.looping, s.connections }).toEqual({
					0,
					0,
					0,
					0,
					2,
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
				expect(c.BP.stats().looping).toBe(1)
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
end
