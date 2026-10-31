--!nocheck
-- WorldService (paquet world) : construction de Lumora (arborescence, noms et tags du docs §3.1),
-- budgets (§11.7, §12.8), Nids (attributs, apparence, perchoirs), éclairage de base, démarrage.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new()
		local WS = h:require("ServerScriptService.Server.Services.WorldService")
		local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local Zones = h:require("ReplicatedStorage.Shared.Config.Zones")
		return h, WS, WL, Zones, h.globals
	end

	local function parts(root)
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function tagged(h, tag)
		return h.game.CollectionService:GetTagged(tag)
	end

	local function radiusXZ(p)
		return math.sqrt(p.X * p.X + p.Z * p.Z)
	end

	describe("WorldService › arborescence (docs §3.1)", function()
		it("Init construit workspace.Lumora avec les noms, classes et tags exacts", function()
			local h, WS = setup()
			WS.Init()
			local root = h.workspace:FindFirstChild("Lumora")
			expect(root ~= nil).toBe(true)
			expect(root.ClassName).toBe("Folder")
			expect(WS.root()).toBe(root)
			local island = root:FindFirstChild("Island")
			expect(island.ClassName).toBe("Model")
			expect(island.ModelStreamingMode.Name).toBe("Persistent")
			for _, name in { "Ground", "Glade", "CraterFloor" } do
				expect({
					name = name,
					part = island:FindFirstChild(name) ~= nil and island[name]:IsA("BasePart"),
				}).toEqual({
					name = name,
					part = true,
				})
			end
			expect(island.CraterRim.ClassName).toBe("Model")
			expect(island.Cracks.ClassName).toBe("Folder")
			expect(island.Cliff.ClassName).toBe("Model")
			expect(island.Walls.ClassName).toBe("Folder")
			for _, name in { "Beacon", "Nests", "Paths", "Lanterns", "Decor", "Islets", "Clouds" } do
				expect({ name = name, found = root:FindFirstChild(name) ~= nil }).toEqual({
					name = name,
					found = true,
				})
			end
			for _, name in { "Meadow", "Glade", "Crater" } do
				expect({ name = name, found = root.Decor:FindFirstChild(name) ~= nil }).toEqual({
					name = name,
					found = true,
				})
			end
		end)

		it(
			"île : sols aux bonnes hauteurs, rebord, 18 fissures Néon, 48 pans de falaise, 36 murs invisibles",
			function()
				local h, WS, _, Zones = setup()
				WS.Init()
				local island = WS.root().Island
				local ground = island.Ground
				expect(ground.Shape.Name).toBe("Cylinder")
				expect(ground.Position.Y + ground.Size.X / 2).toBeNear(Zones.Island.TopY, 1e-4)
				expect(ground.Size.Y).toBeNear(Zones.Island.Radius * 2)
				expect(ground.CanCollide).toBe(true)
				expect(island.Glade.Position.Y + island.Glade.Size.X / 2).toBeNear(
					Zones.Ground.GladeTopY,
					1e-4
				)
				expect(island.CraterFloor.Position.Y + island.CraterFloor.Size.X / 2).toBeNear(
					Zones.Ground.CraterTopY,
					1e-4
				)
				expect(island.CraterFloor.Material.Name).toBe("Basalt")
				expect(#island.CraterRim:GetChildren()).toBe(Zones.Ground.RimSegments * 2)
				local cracks = island.Cracks:GetChildren()
				expect(#cracks).toBe(Zones.Ground.CrackCount)
				for _, c in cracks do
					expect(c.Material.Name).toBe("Neon")
					expect(
						c.Size.Z >= Zones.Ground.CrackLengthMin and c.Size.Z <= Zones.Ground.CrackLengthMax
					).toBe(true)
					expect(radiusXZ(c.Position)).toBeLessThan(Zones.Ground.CraterDiameter / 2)
				end
				local cliff = island.Cliff:GetChildren()
				expect(#cliff).toBe(Zones.Island.CliffCount)
				for _, w in cliff do
					expect(w.ClassName).toBe("WedgePart")
					expect(radiusXZ(w.Position)).toBeNear(
						(Zones.Island.CliffInner + Zones.Island.CliffOuter) / 2,
						1e-3
					)
					expect(w.Position.Y - w.Size.Y / 2).toBeNear(Zones.Island.CliffBottomY, 1e-3)
				end
				local walls = island.Walls:GetChildren()
				expect(#walls).toBe(Zones.Island.WallCount)
				for _, w in walls do
					expect(w.Transparency).toBe(1)
					expect(w.CanCollide).toBe(true)
					expect(w.Size).toEqual(Zones.Island.WallSize)
					expect(radiusXZ(w.Position)).toBeNear(Zones.Island.WallRadius, 1e-3)
				end
			end
		)

		it("rebord du Cratère : ouvertures alignées sur les 12 chemins", function()
			local h, WS, _, Zones = setup()
			WS.Init()
			local step = 2 * math.pi / Zones.Paths.Count
			for _, wedge in WS.root().Island.CraterRim:GetChildren() do
				local a = math.atan2(wedge.Position.Z, wedge.Position.X)
				-- chaque segment est centré entre deux chemins
				local offset = (a / step) % 1
				expect(offset).toBeNear(0.5, 1e-3)
			end
		end)

		it(
			"Balise : étages Marble, 3 anneaux BeaconRing, étoile, faisceau jusqu'à Y = 300, dépôt éteint, stèle",
			function()
				local h, WS, WL, Zones = setup()
				WS.Init()
				local beacon = WS.beacon()
				expect(beacon.Name).toBe("Beacon")
				expect(beacon:HasTag("Beacon")).toBe(true)
				expect(beacon.ModelStreamingMode.Name).toBe("Persistent")
				for _, name in { "Base", "Shaft", "Top" } do
					expect(beacon[name].Material.Name).toBe("Marble")
				end
				local rings = beacon.Rings:GetChildren()
				expect(#rings).toBe(3)
				for _, r in rings do
					expect(r:HasTag("BeaconRing")).toBe(true)
					expect(r.Material.Name).toBe("Neon")
				end
				expect(#tagged(h, "BeaconRing")).toBe(3)
				expect(beacon.Star.ClassName).toBe("Model")
				local carrier = beacon.SkyBeam
				expect(carrier.Bottom.ClassName).toBe("Attachment")
				expect(carrier.Position.Y + carrier.Top.Position.Y).toBeNear(Zones.Beacon.BeamTopY, 1e-4)
				expect(carrier.Beam.Width0).toBe(Zones.Beacon.BeamWidth)
				expect(carrier.Beam.Attachment1).toBe(carrier.Top)
				local deposit = beacon.Deposit
				expect(deposit:HasTag("BeaconDeposit")).toBe(true)
				expect(deposit.Transparency).toBe(1)
				expect(deposit.Size.Y).toBe(Zones.Beacon.DepositDiameter)
				local board = WS.board()
				expect(board.Name).toBe("Board")
				expect(board:IsA("BasePart")).toBe(true)
				expect(radiusXZ(board.Position)).toBeNear(Zones.Beacon.BoardRadius, 1e-3)
				expect(board.CFrame.LookVector.Z).toBeNear(1, 1e-4) -- face au sud (+Z)
				expect(board:GetAttribute("Live")).toBe("")
				-- hauteur de la Balise = somme des étages (cohérent avec WorldLayout.groundY)
				local top = beacon.Top
				expect(top.Position.Y + top.Size.X / 2).toBeNear(WL.groundY(0, 0), 1e-3)
			end
		)
	end)

	describe("WorldService › Nids", function()
		it("12 Nids persistants tagués, attributs initiaux et Slot fixe", function()
			local h, WS, _, Zones, g = setup()
			WS.Init()
			local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
			local nests = WS.root().Nests:GetChildren()
			expect(#nests).toBe(Zones.Nests.Count)
			expect(#tagged(h, "Nest")).toBe(Zones.Nests.Count)
			for slot = 1, Zones.Nests.Count do
				local nest = WS.nest(slot)
				expect(nest.Name).toBe(string.format("Nest_%02d", slot))
				expect(nest.ModelStreamingMode.Name).toBe("Persistent")
				expect(nest:GetAttribute("Slot")).toBe(slot)
				expect(nest:GetAttribute("OwnerUserId")).toBe(0)
				expect(nest:GetAttribute("OwnerName")).toBe("")
				expect(nest:GetAttribute("Color")).toEqual(Cosmetics.FreeNestColor)
				expect(nest:GetAttribute("PerchCount")).toBe(0)
				expect(nest:GetAttribute("PerchData")).toBe("")
				for _, child in { "Platform", "Gate", "Observatory", "BillboardAnchor", "Spawn", "Perches" } do
					expect({ slot = slot, child = child, ok = nest:FindFirstChild(child) ~= nil }).toEqual({
						slot = slot,
						child = child,
						ok = true,
					})
				end
				expect(nest.Gate.PostL ~= nil and nest.Gate.PostR ~= nil).toBe(true)
				local arch = nest.Gate.Arch:GetChildren()
				expect(#arch).toBe(Zones.Nests.ArchPieces)
				for _, piece in arch do
					expect(piece:HasTag("NestArch")).toBe(true)
					expect(piece.Material.Name).toBe("SmoothPlastic") -- libre : sans Néon
					expect(
						piece.Position.Y >= Zones.Nests.ArchBottomY - 1
							and piece.Position.Y <= Zones.Nests.ArchTopY + 1
					).toBe(true)
				end
				expect(nest.BillboardAnchor.Transparency).toBe(1)
				expect(nest.BillboardAnchor.Position.Y).toBeNear(Zones.Nests.BillboardY)
				expect(nest.Platform.Color).toEqual(Cosmetics.FreeNestColor)
			end
			expect(g ~= nil).toBe(true)
		end)

		it("géométrie : centre, porte, observatoire et apparition conformes à WorldLayout", function()
			local _, WS, WL, Zones = setup()
			WS.Init()
			for slot = 1, Zones.Nests.Count do
				local nest = WS.nest(slot)
				local center = WL.nestCenter(slot)
				local platform = nest.Platform
				expect((platform.Position - center).Magnitude).toBeLessThan(0.5)
				expect(platform.Position.Y + platform.Size.X / 2).toBeNear(Zones.Nests.PlatformTopY, 1e-4)
				expect(platform.Size.Y).toBe(Zones.Nests.PlatformDiameter)
				local gate = WL.gateCFrame(slot).Position
				local mid = (nest.Gate.PostL.Position + nest.Gate.PostR.Position) / 2
				expect(math.abs(mid.X - gate.X) + math.abs(mid.Z - gate.Z)).toBeLessThan(1e-3)
				expect((nest.Gate.PostL.Position - nest.Gate.PostR.Position).Magnitude).toBeNear(
					2 * Zones.Nests.GatePostOffset,
					1e-3
				)
				local obs = WL.observatoryCFrame(slot).Position
				local tower = nest.Observatory.Tower.Position
				expect(math.abs(tower.X - obs.X) + math.abs(tower.Z - obs.Z)).toBeLessThan(1e-3)
				local spawn = WS.spawnLocation(slot)
				expect(spawn.ClassName).toBe("SpawnLocation")
				expect(spawn.Neutral).toBe(true)
				expect(spawn.Duration).toBe(0)
				expect(spawn.Transparency).toBe(1)
				expect(spawn.CanCollide).toBe(false)
				-- face à la porte (vers le centre de l'île)
				local toCenter = (-center).Unit
				expect(spawn.CFrame.LookVector:Dot(toCenter)).toBeGreaterThan(0.99)
			end
		end)

		it(
			"setPerchCount crée et détruit exactement les perchoirs, aux positions de WorldLayout",
			function()
				local _, WS, WL, Zones = setup()
				WS.Init()
				local total = 0
				for _, ring in Zones.Perches.Rings do
					total += ring.count
				end
				local nest = WS.nest(4)
				WS.setPerchCount(4, 5)
				expect(#nest.Perches:GetChildren()).toBe(5)
				expect(WS.perchCount(4)).toBe(5)
				for i = 1, 5 do
					local perch = nest.Perches:FindFirstChild(string.format("Perch_%02d", i))
					expect(perch ~= nil).toBe(true)
					local foot = WL.perchCFrame(4, i).Position
					expect(math.abs(perch.Position.X - foot.X) + math.abs(perch.Position.Z - foot.Z)).toBeLessThan(
						1e-3
					)
					expect(perch.Position.Y).toBeGreaterThan(foot.Y)
					expect(perch:GetAttribute("Index")).toBe(i)
					expect(perch:GetAttribute("TopY")).toBeNear(foot.Y + Zones.Perches.Height, 1e-6)
					expect(perch.CanCollide).toBe(false)
					expect(perch:FindFirstChild("Ring") ~= nil).toBe(true)
				end
				WS.setPerchCount(4, total)
				expect(#nest.Perches:GetChildren()).toBe(total)
				-- anneau haut : disques Néon flottants (pas de pied Wood)
				local last = nest.Perches:FindFirstChild(string.format("Perch_%02d", total))
				expect(last:FindFirstChild("Ring")).toBeNil()
				expect(last.Position.Y).toBeGreaterThan(5)
				WS.setPerchCount(4, 2)
				expect(#nest.Perches:GetChildren()).toBe(2)
				expect(nest.Perches:FindFirstChild("Perch_03")).toBeNil()
				WS.setPerchCount(4, 999) -- borné à 46
				expect(#nest.Perches:GetChildren()).toBe(total)
				WS.setPerchCount(4, -4) -- borné à 0
				expect(#nest.Perches:GetChildren()).toBe(0)
				WS.setPerchCount(4, 3.7) -- arrondi vers le bas
				expect(#nest.Perches:GetChildren()).toBe(3)
				-- les autres Nids ne bougent pas
				expect(#WS.nest(5).Perches:GetChildren()).toBe(0)
			end
		)

		it(
			"setNestAppearance : couleur et Néon du propriétaire, thème, retour au gris (perchoirs compris)",
			function()
				local h, WS, _, _, g = setup()
				WS.Init()
				local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local nest = WS.nest(2)
				WS.setPerchCount(2, 3)
				local coral = Cosmetics.NestColors[2]
				WS.setNestAppearance(2, coral)
				expect(nest.Platform.Color).toEqual(coral)
				for _, piece in nest.Gate.Arch:GetChildren() do
					expect(piece.Color).toEqual(coral)
					expect(piece.Material.Name).toBe("Neon")
				end
				expect(nest.Perches.Perch_01.Ring.Color).toEqual(coral)
				expect(nest.Perches.Perch_01.Ring.Material.Name).toBe("Neon")
				-- un perchoir créé après l'habillage prend la couleur du Nid
				WS.setPerchCount(2, 4)
				expect(nest.Perches.Perch_04.Ring.Color).toEqual(coral)
				-- thème : plateforme et arche différentes
				local plat, arch = g.Color3.fromRGB(70, 80, 140), g.Color3.fromRGB(150, 200, 255)
				WS.setNestAppearance(2, plat, arch)
				expect(nest.Platform.Color).toEqual(plat)
				expect(nest.Gate.Arch.Arch_1.Color).toEqual(arch)
				-- libéré : gris, sans Néon
				WS.setNestAppearance(2, nil, nil)
				expect(nest.Platform.Color).toEqual(Cosmetics.FreeNestColor)
				for _, piece in nest.Gate.Arch:GetChildren() do
					expect(piece.Material.Name).toBe("SmoothPlastic")
				end
				expect(nest.Perches.Perch_04.Ring.Material.Name).toBe("SmoothPlastic")
			end
		)

		it(
			"entrées invalides : slot hors 1-12, nombre non fini ou couleur invalide → erreur claire, rien ne change",
			function()
				local _, WS = setup()
				WS.Init()
				for _, bad in { 0, 13, 1.5, -1, 0 / 0, math.huge, "1", nil } do
					expect(function()
						WS.nest(bad)
					end).toThrow("slot")
					expect(function()
						WS.setPerchCount(bad, 3)
					end).toThrow("slot")
				end
				expect(function()
					WS.setPerchCount(1, 0 / 0)
				end).toThrow("fini")
				expect(function()
					WS.setPerchCount(1, math.huge)
				end).toThrow("fini")
				expect(function()
					WS.setNestAppearance(1, "red")
				end).toThrow("Color3")
				expect(#WS.nest(1).Perches:GetChildren()).toBe(0)
			end
		)
	end)

	describe("WorldService › budgets et performance (§11.7, §12.8)", function()
		it("≤ PartBudget pièces avec les 46 perchoirs des 12 Nids, tout est ancré", function()
			local h, WS, _, Zones = setup()
			WS.Init()
			local base = WS.partCount()
			expect(base).toBeGreaterThan(900)
			for slot = 1, Zones.Nests.Count do
				WS.setPerchCount(slot, 46)
			end
			local full = WS.partCount()
			expect(full).toBeLessThanOrEqual(Zones.PartBudget)
			expect(full).toBe(#parts(WS.root()))
			for _, p in parts(WS.root()) do
				expect({ name = p.Name, anchored = p.Anchored }).toEqual({ name = p.Name, anchored = true })
			end
			expect(#h:warnings()).toBe(0)
		end)

		it(
			"décor sans collision ni requête ; seuls sols, rebord, murs et structures sont solides",
			function()
				local _, WS = setup()
				WS.Init()
				local root = WS.root()
				for _, folder in { root.Paths, root.Lanterns, root.Decor, root.Islets, root.Clouds } do
					for _, p in parts(folder) do
						expect({
							name = p.Name,
							collide = p.CanCollide,
							query = p.CanQuery,
							shadow = p.CastShadow,
						}).toEqual({
							name = p.Name,
							collide = false,
							query = false,
							shadow = false,
						})
					end
				end
			end
		)

		it("lumières ≤ budget : 24 lanternes (r 90 et 60), 6 cristaux, 2 Balise", function()
			local h, WS, _, Zones = setup()
			WS.Init()
			local lanterns = tagged(h, "Lantern")
			expect(#lanterns).toBe(Zones.Paths.Count * #Zones.Paths.LanternRadii)
			local litLanterns = 0
			for _, bulb in lanterns do
				local light = bulb:FindFirstChildOfClass("PointLight")
				if light then
					litLanterns += 1
					local r = radiusXZ(bulb.Position)
					expect(r < 100).toBe(true) -- r 90 ou 60
				end
			end
			expect(litLanterns).toBe(Zones.Paths.Count * #Zones.Paths.LitRadii)
			local crystals = tagged(h, "Crystal")
			expect(#crystals).toBe(Zones.Decor.Glade.LitCrystals)
			local lights = 0
			for _, d in WS.root():GetDescendants() do
				if d.ClassName == "PointLight" or d.ClassName == "SpotLight" then
					lights += 1
				end
			end
			expect(lights).toBe(litLanterns + #crystals + 2)
			local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
			expect(lights).toBeLessThanOrEqual(Balance.Render.MaxLights)
		end)

		it(
			"cristaux ≤ CrystalMaxParts, Glass translucide 0,25 ; 144+ pas japonais ; îlots et nuages flottent",
			function()
				local h, WS, WL, Zones = setup()
				WS.Init()
				local root = WS.root()
				local crystals = 0
				for _, p in parts(root.Decor.Glade) do
					if p.Name == "Crystal" then
						crystals += 1
						expect(p.Material.Name).toBe("Glass")
						expect(p.Transparency).toBe(Zones.Decor.CrystalTransparency)
					end
				end
				expect(crystals).toBeLessThanOrEqual(Zones.Decor.Glade.CrystalMaxParts)
				expect(crystals).toBeGreaterThanOrEqual(Zones.Decor.Glade.CrystalClusters * 3)
				expect(#root.Paths:GetChildren()).toBe(#WL.pathStones())
				expect(#root.Paths:GetChildren()).toBeGreaterThanOrEqual(144)
				expect(#root.Islets:GetChildren()).toBe(Zones.Islets.Count)
				for _, p in parts(root.Islets) do
					expect(p:HasTag("Float")).toBe(true)
					expect(p:GetAttribute("amplitude")).toBe(Zones.Islets.FloatAmplitude)
				end
				expect(#root.Clouds:GetChildren()).toBe(Zones.Island.CloudCount)
				for _, p in parts(root.Clouds) do
					expect(p:HasTag("Float")).toBe(true)
					expect(p.Position.Y).toBeLessThan(-40)
				end
				local meadow = root.Decor.Meadow
				local counts = {}
				for _, m in meadow:GetChildren() do
					counts[m.Name] = (counts[m.Name] or 0) + 1
				end
				expect(counts.Puffbloom).toBe(Zones.Decor.Meadow.Puffblooms)
				expect(counts.Mushcap).toBe(Zones.Decor.Meadow.Mushcaps)
				expect(counts.Fence).toBe(#WL.decor().fences)
				expect(#tagged(h, "Spin")).toBeGreaterThanOrEqual(Zones.Decor.Glade.FloatingStones)
			end
		)

		it("aucune créature côté serveur (Nebbies, Gloomwisps, Comète : client seulement)", function()
			local h, WS = setup()
			WS.Init()
			for _, d in h.workspace:GetDescendants() do
				expect({
					name = d.Name,
					creature = d.Name == "Nebby" or d.Name == "Gloomwisp" or d.Name == "CometOrb",
				}).toEqual({
					name = d.Name,
					creature = false,
				})
			end
		end)
	end)

	describe("WorldService › cycle de vie", function()
		it("Init est synchrone, idempotent et remplace un ancien monde sauvegardé", function()
			local h, WS = setup()
			local stale = h.globals.Instance.new("Folder")
			stale.Name = "Lumora"
			stale.Parent = h.workspace
			local done = false
			local thread = coroutine.create(function()
				WS.Init()
				done = true
			end)
			coroutine.resume(thread)
			expect(done).toBe(true) -- aucun yield
			local count = 0
			for _, c in h.workspace:GetChildren() do
				if c.Name == "Lumora" then
					count += 1
				end
			end
			expect(count).toBe(1)
			expect(WS.root() ~= stale).toBe(true)
			local root = WS.root()
			WS.Init()
			expect(WS.root()).toBe(root)
		end)

		it("les accès avant Init construisent le monde à la demande", function()
			local h, WS = setup()
			local spawn = WS.spawnLocation(7)
			expect(spawn:IsDescendantOf(h.workspace)).toBe(true)
			expect(WS.board():IsDescendantOf(WS.beacon())).toBe(true)
		end)

		it("éclairage de base de Events.Lighting.Base et nuages du Terrain", function()
			local h, WS = setup()
			local Events = h:require("ReplicatedStorage.Shared.Config.Events")
			WS.Init()
			local L = h.game.Lighting
			local base = Events.Lighting.Base
			expect(L.Ambient).toEqual(base.Ambient)
			expect(L.OutdoorAmbient).toEqual(base.OutdoorAmbient)
			expect(L.Brightness).toBe(base.Brightness)
			expect(L.ClockTime).toBe(Events.Lighting.Cycle.Min)
			expect(L.Sky.StarCount).toBe(base.StarCount)
			expect(L.Sky.MoonAngularSize).toBe(base.MoonAngularSize)
			expect(L.Atmosphere.Density).toBe(base.AtmosphereDensity)
			expect(L.Atmosphere.Color).toEqual(base.AtmosphereColor)
			expect(L.Bloom.Intensity).toBe(base.BloomIntensity)
			expect(L.ColorCorrection.Saturation).toBe(base.Saturation)
			expect(L.SunRays.Intensity).toBe(base.SunRays)
			local clouds = h.workspace.Terrain:FindFirstChildOfClass("Clouds")
			expect(clouds ~= nil).toBe(true)
			expect(clouds.Cover).toBe(base.CloudCover)
			expect(clouds.Color).toEqual(base.CloudColor)
		end)

		it(
			"démarrage complet du serveur : monde construit, joueurs accueillis et partis sans erreur",
			function()
				local h = Harness.new()
				local DS = h:require("ServerScriptService.Server.Services.DataService")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				local WS = h:require("ServerScriptService.Server.Services.WorldService")
				h:boot()
				expect(h.workspace:FindFirstChild("Lumora") ~= nil).toBe(true)
				local a = h:addPlayer({ userId = 31, name = "Ana" })
				-- un service d'économie posera RespawnLocation sur le Spawn du Nid
				a.RespawnLocation = WS.spawnLocation(1)
				h:respawn(a)
				h:step(1 / 60, 5)
				h:removePlayer(a)
				h:settle(2)
				expect(#h.errors).toBe(0)
				expect(WS.partCount()).toBeLessThanOrEqual(3000)
			end
		)
	end)
end
