--!nocheck
-- WorldBuild (paquet world, docs/04 §3.1, §11.3, §17.1, §17.3, §18.2) : Wobbleton construit par
-- WorldService à partir de Logic/WorldLayout.
--   * tout est ancré et CanTouch = false ; les pièces « Solid » sont EXACTEMENT les boîtes de
--     WorldLayout.solids() (le client, la capture au bond et les règles du serveur utilisent les
--     mêmes) ; tout le reste est CanCollide = CanQuery = false ;
--   * chaque boîte solide (sauf le plateau) monte à Const.SolidMinHeight (30) au moins : murs des
--     clôtures, murs du bord et coiffes invisibles des maisons, qui couvrent toute la maison visible ;
--   * deux solides sont collés ou séparés d'au moins 6 studs (aucun recoin) ;
--   * ≤ 4 500 pièces ; transparence 0 ou 1 sauf la gelée, les portails, le Bassin, la Cuve, la jarre ;
--   * API : setRanchOwner, setRanchBuild, setStatue, setGauge, ranchModel, partCount (entrées
--     hostiles comprises), construction par blocs protégés, groupe de collision, ApiAudit, zéro trace.
local roblox = require("@lune/roblox")
local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local EPS = 1e-4

	local function zeroLog(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- Serveur avec le seul WorldService construit (Init : groupe de collision + monde)
	local function world()
		local h = Harness.new()
		local W = h:require("ServerScriptService.Server.Services.WorldService")
		local L = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		W.Init()
		W.Start()
		local root = h.game.Workspace:FindFirstChild("Wobbleton")
		return h, W, L, root
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

	local function sameCFrame(a, b)
		if (a.Position - b.Position).Magnitude > EPS then
			return false
		end
		for _, axis in { "XVector", "YVector", "ZVector" } do
			if (a[axis] - b[axis]).Magnitude > EPS then
				return false
			end
		end
		return true
	end

	local function sameSize(a, b)
		return (a - b).Magnitude < EPS
	end

	-- Coins (X, Z) d'une boîte verticale
	local function corners(box)
		local c, s = box.cframe, box.size
		local out = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = c * Vector3.new(sx * s.X / 2, 0, sz * s.Z / 2)
				table.insert(out, Vector2.new(p.X, p.Z))
			end
		end
		-- ordre du contour
		return { out[1], out[2], out[4], out[3] }
	end

	local function project(points, axis)
		local lo, hi = math.huge, -math.huge
		for _, p in points do
			local d = p.X * axis.X + p.Y * axis.Y
			lo = math.min(lo, d)
			hi = math.max(hi, d)
		end
		return lo, hi
	end

	local function overlap(a, b)
		for _, poly in { a, b } do
			for i = 1, 4 do
				local e = poly[i % 4 + 1] - poly[i]
				local axis = Vector2.new(-e.Y, e.X).Unit
				local a0, a1 = project(a, axis)
				local b0, b1 = project(b, axis)
				if a1 < b0 - 1e-6 or b1 < a0 - 1e-6 then
					return false
				end
			end
		end
		return true
	end

	local function pointSegment(p, a, b)
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		return (p - (a + ab * t)).Magnitude
	end

	local function gap(a, b)
		local best = math.huge
		for _, pair in { { a, b }, { b, a } } do
			for _, p in pair[1] do
				for i = 1, 4 do
					best = math.min(best, pointSegment(p, pair[2][i], pair[2][i % 4 + 1]))
				end
			end
		end
		return best
	end

	describe("WorldBuild › construction", function()
		it("workspace.Wobbleton : tous les blocs, 16 ranchs, attributs, point d'apparition neutre", function()
			local h, W, _, root = world()
			expect(root ~= nil).toBe(true)
			expect(root.ClassName).toBe("Folder")
			for _, name in
				{ "Plate", "Hills", "Walls", "Plaza", "Streets", "Houses", "Lamps", "Meadow", "Ranches" }
			do
				expect({ name = name, found = root:FindFirstChild(name) ~= nil }).toEqual({
					name = name,
					found = true,
				})
			end
			local plaza = root.Plaza
			for _, name in
				{ "MegaPad", "Statue", "Shop", "Altar", "GaugeJar", "Stage", "GoldenFountain", "Boards" }
			do
				expect({ name = name, found = plaza:FindFirstChild(name) ~= nil }).toEqual({
					name = name,
					found = true,
				})
			end
			expect(#plaza.Boards:GetChildren()).toBe(5)
			for i = 1, 5 do
				local board = plaza.Boards:FindFirstChild(tostring(i))
				expect(board:GetAttribute("Index")).toBe(i)
				expect(board:FindFirstChild("Board", true).ClassName).toBe("SurfaceGui")
			end
			expect(plaza.Statue:GetAttribute("StatueSpecies")).toBe(0)
			expect(plaza.Statue:GetAttribute("StatueName")).toBe("")
			expect(plaza.GaugeJar:GetAttribute("Fill")).toBe(0)
			local spawn = root:FindFirstChild("NeutralSpawn")
			expect(spawn.ClassName).toBe("SpawnLocation")
			expect(spawn.Neutral).toBe(true)
			expect(#root.Ranches:GetChildren()).toBe(16)
			for slot = 1, 16 do
				local ranch = root.Ranches:FindFirstChild(tostring(slot))
				expect(ranch.ClassName).toBe("Model")
				expect(W.ranchModel(slot)).toBe(ranch)
				expect(ranch:GetAttribute("Slot")).toBe(slot)
				expect(ranch:GetAttribute("OwnerUserId")).toBe(0)
				for _, name in
					{
						"Fence",
						"FenceWall",
						"Gate",
						"Fountain",
						"Sign",
						"PenFloor",
						"SnackMat",
						"Pot",
						"Vat",
						"Pool",
						"Bowl",
						"Cushion",
						"Shelf",
						"Pads",
						"Decor",
					}
				do
					expect({ slot = slot, name = name, found = ranch:FindFirstChild(name) ~= nil }).toEqual({
						slot = slot,
						name = name,
						found = true,
					})
				end
				expect(#ranch.Pads:GetChildren()).toBe(4)
				for i, key in { "snack", "decor", "pens", "cozyBed" } do
					expect(ranch.Pads:FindFirstChild(tostring(i)):GetAttribute("Tile")).toBe(key)
				end
				expect(#ranch.Decor:GetChildren()).toBe(18)
				expect(ranch.Gate.Membrane.CanCollide).toBe(false)
			end
			expect(W.ranchModel(0)).toBeNil()
			expect(W.ranchModel(17)).toBeNil()
			expect(W.ranchModel(0 / 0)).toBeNil()
			expect(W.ranchModel(1.5)).toBeNil()
			expect(#W.failures()).toBe(0)
			zeroLog(h)
		end)

		it("idempotent : un second build rend le même dossier, sans une pièce de plus", function()
			local h, W, _, root = world()
			local n = W.partCount()
			expect(W.build()).toBe(root)
			expect(W.partCount()).toBe(n)
			local count = 0
			for _, child in h.game.Workspace:GetChildren() do
				if child.Name == "Wobbleton" then
					count += 1
				end
			end
			expect(count).toBe(1)
			zeroLog(h)
		end)

		it("budget : ≤ 4 500 pièces, partCount = pièces réelles", function()
			local h, W, _, root = world()
			local n = #parts(root)
			expect(W.partCount()).toBe(n)
			expect(n).toBeLessThanOrEqual(W.PART_BUDGET)
			expect(n).toBeGreaterThan(2000) -- le monde est vraiment construit (16 ranchs, place, rues)
			zeroLog(h)
		end)

		it("groupe de collision Characters enregistré et non collisionnable avec lui-même", function()
			local h = Harness.new()
			local calls = {}
			MockInstance.classMethods.PhysicsService.IsCollisionGroupRegistered = function()
				return false
			end
			MockInstance.classMethods.PhysicsService.RegisterCollisionGroup = function(_, name)
				table.insert(calls, "register:" .. name)
			end
			MockInstance.classMethods.PhysicsService.CollisionGroupSetCollidable = function(_, a, b, c)
				table.insert(calls, `collidable:{a}:{b}:{tostring(c)}`)
			end
			local W = h:require("ServerScriptService.Server.Services.WorldService")
			W.Init()
			expect(calls).toEqual({ "register:Characters", "collidable:Characters:Characters:false" })
			zeroLog(h)
		end)
	end)

	describe("WorldBuild › règle robuste : ancré, sans Touched, solides = boîtes", function()
		it(
			"chaque pièce est ancrée et CanTouch = false ; le décor est CanCollide = CanQuery = false",
			function()
				local h, W, _, root = world()
				local bad = {}
				for _, p in parts(root) do
					local solid = p:HasTag(W.SOLID_TAG)
					if not p.Anchored or p.CanTouch then
						table.insert(bad, p:GetFullName() .. " (ancrage / CanTouch)")
					end
					if solid then
						if not p.CanCollide or p.Transparency ~= 1 then
							table.insert(bad, p:GetFullName() .. " (solide visible ou sans collision)")
						end
					elseif p.CanCollide or p.CanQuery then
						table.insert(bad, p:GetFullName() .. " (décor solide)")
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
				zeroLog(h)
			end
		)

		it("les pièces « Solid » sont exactement les boîtes de WorldLayout.solids()", function()
			local h, W, L, root = world()
			local solids = {}
			for _, p in parts(root) do
				if p:HasTag(W.SOLID_TAG) then
					table.insert(solids, p)
				end
			end
			expect(#W.solidParts()).toBe(#solids)
			local boxes = L.solids()
			expect(#solids).toBe(#boxes)
			local used = {}
			local missing = {}
			for i, box in boxes do
				local found = nil
				for j, p in solids do
					if not used[j] and sameCFrame(p.CFrame, box.cframe) and sameSize(p.Size, box.size) then
						found = j
						break
					end
				end
				if found then
					used[found] = true
				else
					table.insert(missing, `boîte {i} sans pièce`)
				end
			end
			expect(table.concat(missing, "\n")).toBe("")
			zeroLog(h)
		end)

		it("chaque boîte solide (sauf le plateau) monte à 30 studs au moins depuis le sol", function()
			local h, _, L = world()
			local min = L.Const.SolidMinHeight
			expect(min).toBe(30)
			local low = {}
			local kinds = { fence = 0, edge = 0, house = 0 }
			for i, box in L.solids() do
				if i > 1 then
					local p = box.cframe.Position
					local top = p.Y + box.size.Y / 2
					local bottom = p.Y - box.size.Y / 2
					if top - math.max(bottom, 0) < min - EPS or bottom > EPS then
						table.insert(low, `boîte {i} : {bottom} → {top}`)
					end
					local r = math.sqrt(p.X * p.X + p.Z * p.Z)
					if r > L.Const.WallRadius - 2 then
						kinds.edge += 1
					elseif L.ranchNear(p, 1) ~= 0 then
						kinds.fence += 1
					else
						kinds.house += 1
					end
				end
			end
			expect(table.concat(low, "\n")).toBe("")
			expect(kinds).toEqual({ fence = 16 * 5, edge = L.Const.EdgeSegments, house = 24 })
			zeroLog(h)
		end)

		it(
			"coiffe des maisons : la boîte solide couvre toute la maison visible (aucun toit atteignable)",
			function()
				local h, W, _, root = world()
				local issues = {}
				local houses = 0
				for _, house in root.Houses:GetChildren() do
					if house:IsA("Model") then
						houses += 1
						local solid = house:FindFirstChild("Solid")
						expect(solid:HasTag(W.SOLID_TAG)).toBe(true)
						local top = solid.Position.Y + solid.Size.Y / 2
						local inv = solid.CFrame:Inverse()
						for _, p in parts(house) do
							if p ~= solid then
								local lp = inv * p.CFrame.Position
								local reach = math.max(p.Size.X, p.Size.Z) / 2
								if
									math.abs(lp.X) > solid.Size.X / 2 + 1
									or math.abs(lp.Z) > solid.Size.Z / 2 + 1
									or p.CFrame.Position.Y + p.Size.Y / 2 > top
								then
									table.insert(issues, `{house.Name}.{p.Name} hors de la coiffe ({reach})`)
								end
							end
						end
					end
				end
				expect(houses).toBe(24)
				expect(table.concat(issues, "\n")).toBe("")
				zeroLog(h)
			end
		)

		it("deux solides sont collés ou séparés d'au moins 6 studs (aucun recoin)", function()
			local h, _, L = world()
			local boxes = L.solids()
			local polys, centers, reach = {}, {}, {}
			for i, box in boxes do
				polys[i] = corners(box)
				centers[i] = Vector2.new(box.cframe.Position.X, box.cframe.Position.Z)
				reach[i] = math.sqrt(box.size.X ^ 2 + box.size.Z ^ 2) / 2
			end
			local issues = {}
			for i = 2, #boxes do
				for j = i + 1, #boxes do
					if (centers[i] - centers[j]).Magnitude <= reach[i] + reach[j] + 6 then
						if not overlap(polys[i], polys[j]) then
							local d = gap(polys[i], polys[j])
							if d < 6 - 1e-6 then
								table.insert(issues, `boîtes {i} et {j} : fente de {d}`)
							end
						end
					end
				end
			end
			expect(table.concat(issues, "\n")).toBe("")
			zeroLog(h)
		end)

		it(
			"murs de clôture : la clôture visible (4 studs) est sous le mur invisible de 30 studs",
			function()
				local h, _, L, root = world()
				for slot = 1, 16 do
					local ranch = root.Ranches[tostring(slot)]
					local walls = ranch.FenceWall:GetChildren()
					expect(#walls).toBe(5)
					for _, wall in walls do
						expect(wall.Size.Y).toBeGreaterThanOrEqual(L.Const.FenceWallHeight)
					end
					for _, post in parts(ranch.Fence) do
						expect(post.CFrame.Position.Y + post.Size.Y / 2).toBeLessThan(L.Const.FenceWallHeight)
					end
				end
				zeroLog(h)
			end
		)

		it("transparence 0 ou 1, sauf la gelée, les portails, le Bassin, la Cuve et la jarre", function()
			local h, _, _, root = world()
			local allowed = { Membrane = true, Glass = true, Water = true }
			local bad = {}
			for _, p in parts(root) do
				if p.Transparency > 0 and p.Transparency < 1 and not allowed[p.Name] then
					table.insert(bad, p:GetFullName())
				end
			end
			expect(table.concat(bad, "\n")).toBe("")
			zeroLog(h)
		end)

		it(
			"lumières : 16 lampadaires allumés (un sur quatre), lumières des ranchs éteintes sur le serveur",
			function()
				local h, W, _, root = world()
				local lamps, ranchLights, other = 0, 0, 0
				for _, d in root:GetDescendants() do
					if d.ClassName == "PointLight" then
						if d:HasTag(W.LAMP_LIGHT_TAG) then
							expect(d.Enabled).toBe(true)
							lamps += 1
						elseif d:HasTag(W.RANCH_LIGHT_TAG) then
							expect(d.Enabled).toBe(false)
							ranchLights += 1
						else
							other += 1
						end
					end
				end
				expect(lamps).toBe(16)
				expect(ranchLights).toBe(16 * 4)
				expect(other).toBe(0)
				zeroLog(h)
			end
		)

		it(
			"objets du ranch dans son rectangle (sauf la Fontaine, côté rue) ; dalles aux prises de WorldLayout",
			function()
				local h, _, L, root = world()
				local issues = {}
				for slot = 1, 16 do
					local ranch = root.Ranches[tostring(slot)]
					for _, child in ranch:GetChildren() do
						if child.Name ~= "Fountain" and child.Name ~= "Sign" then
							for _, p in parts(child) do
								if not L.inRanch(slot, p.CFrame.Position) then
									table.insert(issues, `{slot}.{child.Name}.{p.Name}`)
								end
							end
						end
					end
					for i = 1, 4 do
						local pad = ranch.Pads[tostring(i)]
						local socket = L.padSocket(slot, i)
						local p = pad.CFrame.Position
						expect(Vector2.new(p.X - socket.X, p.Z - socket.Z).Magnitude).toBeLessThan(EPS)
					end
					local fountain = ranch.Fountain.Basin.CFrame.Position
					local anchor = L.anchor(slot, "fountain")
					expect(Vector2.new(fountain.X - anchor.X, fountain.Z - anchor.Z).Magnitude).toBeLessThan(
						EPS
					)
				end
				expect(table.concat(issues, "\n")).toBe("")
				zeroLog(h)
			end
		)
	end)

	describe("WorldBuild › API", function()
		it(
			"setRanchOwner : couleur du ranch, attribut, gris et état remis à zéro quand il se libère",
			function()
				local h, W, _, root = world()
				local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local ranch = root.Ranches["3"]
				local post = ranch.Gate.PostL
				expect(post.Color).toBe(Cosmetics.FreeRanchColor)
				W.setRanchOwner(3, 42)
				expect(ranch:GetAttribute("OwnerUserId")).toBe(42)
				expect(post.Color).toBe(Cosmetics.RanchColors[3])
				W.setRanchBuild(3, { snack = 4, decor = 5, pens = 2, cozyBed = false, seen = 15 }, true, true)
				expect(ranch.Decor["5"]:FindFirstChildWhichIsA("BasePart").Transparency).toBe(0)
				local custom = Color3.fromRGB(1, 2, 3)
				W.setRanchOwner(3, 42, custom)
				expect(post.Color).toBe(custom)
				W.setRanchOwner(3, 0, custom) -- libre : gris, quelle que soit la couleur passée
				expect(ranch:GetAttribute("OwnerUserId")).toBe(0)
				expect(post.Color).toBe(Cosmetics.FreeRanchColor)
				expect(ranch.Decor["1"]:FindFirstChildWhichIsA("BasePart").Transparency).toBe(1)
				expect(ranch.Vat.Glass.Transparency).toBe(1)
				expect(ranch.Pads["1"].Transparency).toBe(1)
				for _, light in ranch:GetDescendants() do
					if light.ClassName == "PointLight" then
						expect(light.Enabled).toBe(false)
					end
				end
				zeroLog(h)
			end
		)

		it(
			"ordre indifférent : dalles découvertes avant l'arrivée du propriétaire, montrées dès qu'il arrive",
			function()
				local h, W, _, root = world()
				local ranch = root.Ranches["9"]
				W.setRanchBuild(9, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 3 }, true, false)
				expect(ranch.Pads["1"].Transparency).toBe(1) -- ranch libre : aucune dalle
				W.setRanchOwner(9, 99)
				expect(ranch.Pads["1"].Transparency).toBe(0)
				expect(ranch.Pads["2"].Transparency).toBe(0)
				expect(ranch.Pads["3"].Transparency).toBe(1)
				zeroLog(h)
			end
		)

		it("setRanchOwner / setRanchBuild : entrées hostiles ignorées sans erreur", function()
			local h, W, _, root = world()
			local before = {}
			for slot = 1, 16 do
				before[slot] = root.Ranches[tostring(slot)]:GetAttribute("OwnerUserId")
			end
			for _, slot in { 0, 17, -1, 1.5, 0 / 0, math.huge, "1", nil, {} } do
				W.setRanchOwner(slot, 5)
				W.setRanchBuild(
					slot,
					{ snack = 1, decor = 1, pens = 1, cozyBed = false, seen = 1 },
					true,
					true
				)
			end
			for slot = 1, 16 do
				expect(root.Ranches[tostring(slot)]:GetAttribute("OwnerUserId")).toBe(before[slot])
			end
			for _, id in { 0 / 0, -5, 1.5, math.huge, "7" } do
				W.setRanchOwner(2, id)
				expect(root.Ranches["2"]:GetAttribute("OwnerUserId")).toBe(0)
			end
			W.setRanchOwner(2, 9)
			for _, tiles in
				{
					nil,
					"tiles",
					{},
					{ snack = 0 / 0, decor = math.huge, pens = -3, seen = "x", cozyBed = 1 },
					{ snack = 1e308, decor = -1e308, pens = 1e9, seen = 1e308 },
				}
			do
				W.setRanchBuild(2, tiles, "yes", 0 / 0)
			end
			local ranch = root.Ranches["2"]
			expect(ranch.Vat.Glass.Transparency).toBe(1) -- « yes » n'est pas true
			zeroLog(h)
		end)

		it(
			"setRanchBuild : décorations construites, Tapis (13 aspects), Cuve, Bassin, dalles découvertes",
			function()
				local h, W, _, root = world()
				local Palette = h:require("ReplicatedStorage.Shared.Render.Palette")
				local Pads = h:require("ReplicatedStorage.Shared.Config.Pads")
				W.setRanchOwner(7, 77)
				local ranch = root.Ranches["7"]
				local function decorShown()
					local n = 0
					for i = 1, 18 do
						local all, any = true, false
						for _, p in parts(ranch.Decor[tostring(i)]) do
							if p.Transparency == 0 then
								any = true
							else
								all = false
							end
						end
						expect({ i = i, consistent = all == any }).toEqual({ i = i, consistent = true })
						if all then
							n += 1
						end
					end
					return n
				end
				expect(decorShown()).toBe(0)
				for _, level in { 0, 1, 7, 18, 3, 0 } do
					W.setRanchBuild(
						7,
						{ snack = 0, decor = level, pens = 0, cozyBed = false, seen = 0 },
						false,
						false
					)
					expect(decorShown()).toBe(level)
					for i = 1, 18 do
						local visible = parts(ranch.Decor[tostring(i)])[1].Transparency == 0
						expect(visible).toBe(i <= level)
					end
				end
				W.setRanchBuild(
					7,
					{ snack = 99, decor = 99, pens = 0, cozyBed = false, seen = 0 },
					false,
					false
				)
				expect(decorShown()).toBe(18)
				for level = 0, 12 do
					W.setRanchBuild(
						7,
						{ snack = level, decor = 0, pens = 0, cozyBed = false, seen = 0 },
						false,
						false
					)
					local look = Palette.snackLook(level)
					expect(ranch.SnackMat.Mat.Color).toBe(look.mat)
					local shown = 0
					for i = 1, Palette.SnackDots do
						if ranch.SnackMat["Dot" .. i].Transparency == 0 then
							shown += 1
						end
					end
					expect(shown).toBe(look.count)
				end
				W.setRanchBuild(7, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 }, true, false)
				expect(ranch.Vat.Glass.Transparency).toBe(0.5)
				expect(ranch.Vat.Jelly.Transparency).toBe(0)
				expect(ranch.Pool.Water.Transparency).toBe(1)
				W.setRanchBuild(7, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 }, true, true)
				expect(ranch.Pool.Water.Transparency).toBe(0.3)
				expect(ranch.Pool.Rim.Transparency).toBe(0)
				-- dalles : visibles une fois découvertes (bit de tiles.seen), cachées une fois au maximum
				local function padVisible(key)
					return ranch.Pads[tostring(Pads.Defs[key].socket)].Transparency == 0
				end
				W.setRanchBuild(7, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 1 }, true, true)
				expect(padVisible("snack")).toBe(true)
				expect(padVisible("decor")).toBe(false)
				W.setRanchBuild(7, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 15 }, true, true)
				for _, key in Pads.Order do
					expect(padVisible(key)).toBe(true)
				end
				W.setRanchBuild(
					7,
					{ snack = 12, decor = 18, pens = 14, cozyBed = true, seen = 15 },
					true,
					true
				)
				for _, key in Pads.Order do
					expect(padVisible(key)).toBe(false)
					expect(ranch.Pads[tostring(Pads.Defs[key].socket)]:GetAttribute("Maxed")).toBe(true)
				end
				zeroLog(h)
			end
		)

		it("setStatue : attributs validés (espèce, mutation, taille, nom UTF-8 tronqué)", function()
			local h, W, _, root = world()
			local statue = root.Plaza.Statue
			W.setStatue(4, 5, 1.5e9, "Mira")
			expect(statue:GetAttribute("StatueSpecies")).toBe(4)
			expect(statue:GetAttribute("StatueMutation")).toBe(5)
			expect(statue:GetAttribute("StatueSize")).toBe(1.5e9)
			expect(statue:GetAttribute("StatueName")).toBe("Mira")
			W.setStatue(1, 99, 0 / 0, string.rep("é", 80))
			expect(statue:GetAttribute("StatueMutation")).toBe(0)
			expect(statue:GetAttribute("StatueSize")).toBe(0)
			expect(utf8.len(statue:GetAttribute("StatueName"))).toBe(50)
			W.setStatue(1, 0, math.huge, "\255\254")
			expect(statue:GetAttribute("StatueName")).toBe("")
			expect(statue:GetAttribute("StatueSize")).toBe(0) -- infini : invalide
			W.setStatue(1, 0, 1e308, "A")
			expect(statue:GetAttribute("StatueSize")).toBe(1e300) -- borné à Balance.Numbers.Max
			for _, s in { 0, 999, -1, 1.5, 0 / 0, "2" } do
				W.setStatue(s, 3, 10, "x")
				expect(statue:GetAttribute("StatueSpecies")).toBe(0)
				expect(statue:GetAttribute("StatueName")).toBe("")
			end
			zeroLog(h)
		end)

		it("setGauge : remplissage borné à 0 … 1, gelée de la jarre à la bonne hauteur", function()
			local h, W, _, root = world()
			local jar = root.Plaza.GaugeJar
			local jelly = jar.Jelly
			local glass = jar.Glass
			local function jellyTop()
				return jelly.CFrame.Position.Y + jelly.Size.X / 2
			end
			local glassTop = glass.CFrame.Position.Y + glass.Size.X / 2
			W.setGauge(0)
			local low = jellyTop()
			W.setGauge(0.5)
			expect(jar:GetAttribute("Fill")).toBe(0.5)
			local mid = jellyTop()
			W.setGauge(1)
			local high = jellyTop()
			expect(mid > low and high > mid).toBe(true)
			expect(high).toBeLessThanOrEqual(glassTop)
			for _, bad in { 0 / 0, -3, math.huge, "1", nil } do
				W.setGauge(bad)
				local fill = jar:GetAttribute("Fill")
				expect(fill >= 0 and fill <= 1).toBe(true)
			end
			W.setGauge(7)
			expect(jar:GetAttribute("Fill")).toBe(1)
			zeroLog(h)
		end)

		it(
			"étiquettes du monde : clés de Localization/Strings (EN et FR), jamais de texte posé",
			function()
				local h, _, _, root = world()
				local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
				local keys = {}
				for _, d in root:GetDescendants() do
					local key = d:GetAttribute("LabelKey")
					if key ~= nil then
						table.insert(keys, key)
						expect({ key = key, en = Strings.en[key] ~= nil, fr = Strings.fr[key] ~= nil }).toEqual({
							key = key,
							en = true,
							fr = true,
						})
					end
					expect(d.ClassName ~= "TextLabel" and d.ClassName ~= "TextButton").toBe(true)
				end
				table.sort(keys)
				expect(keys).toEqual({
					"event.altarCountdown",
					"world.bigPlop",
					"world.gauge",
					"world.meadow",
					"world.shop",
				})
				-- le compte à rebours de l'Autel est calculé par le client (LabelTimer), sur la poutre
				local beam = root.Plaza.Altar.Beam
				expect(beam:GetAttribute("LabelKey")).toBe("event.altarCountdown")
				expect(beam:GetAttribute("LabelTimer")).toBe("moon")
				zeroLog(h)
			end
		)
	end)

	describe("WorldBuild › robustesse", function()
		it(
			"un bloc en panne est compté par Diagnostics (world:<bloc>), les autres se construisent",
			function()
				local h = Harness.new()
				local Town = h:require("ServerScriptService.Server.World.Town")
				local Diag = h:require("ServerScriptService.Server.Services.DiagnosticsService")
				local caught = {}
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " " .. tostring(err))
				end
				Town.lamps = function()
					error("panne simulée")
				end
				local W = h:require("ServerScriptService.Server.Services.WorldService")
				W.Init()
				expect(#caught).toBe(1)
				expect(string.find(caught[1], "world:lamps", 1, true) ~= nil).toBe(true)
				expect(W.failures()).toEqual({ "world:lamps" })
				local root = h.game.Workspace.Wobbleton
				expect(root:FindFirstChild("Plaza") ~= nil).toBe(true)
				expect(#root.Ranches:GetChildren()).toBe(16)
				-- les fonctions de l'API restent sûres
				W.setRanchOwner(1, 5)
				W.setGauge(0.3)
				W.setStatue(1, 0, 10, "A")
				expect(table.concat(h.errors, "\n")).toBe("")
			end
		)

		it("plaza absente (bloc en panne) : setStatue et setGauge ne font rien, sans erreur", function()
			local h = Harness.new()
			local Town = h:require("ServerScriptService.Server.World.Town")
			local Diag = h:require("ServerScriptService.Server.Services.DiagnosticsService")
			Diag.reportCaught = function() end
			Town.plaza = function()
				error("panne simulée")
			end
			local W = h:require("ServerScriptService.Server.Services.WorldService")
			W.Init()
			W.setStatue(1, 0, 10, "A")
			W.setGauge(0.5)
			expect(W.failures()).toEqual({ "world:plaza" })
			expect(table.concat(h.errors, "\n")).toBe("")
		end)

		it(
			"serveur complet (Main.server) avec 2 joueurs : monde construit, zéro erreur, zéro avertissement",
			function()
				local h = Harness.new()
				local DS = h:require("ServerScriptService.Server.Services.DataService")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				h:boot()
				local a = h:addPlayer({ userId = 301, name = "Ana" })
				local b = h:addPlayer({ userId = 302, name = "Bo" })
				DS.waitFor(a, 2)
				DS.waitFor(b, 2)
				h:step(1 / 60, 30)
				expect(h.game.Workspace:FindFirstChild("Wobbleton") ~= nil).toBe(true)
				h:removePlayer(a)
				h:settle(3)
				zeroLog(h)
			end
		)

		it("API Roblox valide (ApiAudit) : construction et chaque fonction", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, W = world()
				W.setRanchOwner(5, 12)
				W.setRanchBuild(
					5,
					{ snack = 6, decor = 18, pens = 3, cozyBed = false, seen = 15 },
					true,
					true
				)
				W.setRanchOwner(5, 0)
				W.setStatue(3, 2, 5e6, "Lea")
				W.setGauge(0.75)
				zeroLog(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)

	-- Revue adversariale (paquet world, contrat v1.2) : défauts trouvés en revue, chacun reproduit ici
	-- avant sa correction (le test reste).
	describe("WorldBuild › revue (contrat v1.2)", function()
		-- Emprise au sol (XZ) d'une pièce : disque (cylindre vertical, boule) ou rectangle orienté
		local function footprint(p)
			local pos = p.CFrame.Position
			if p.Shape == roblox.Enum.PartType.Cylinder then
				-- cylindres du monde : axe X tourné vers le haut (Parts.UPRIGHT), diamètre = Size.Y
				return { kind = "circle", c = Vector2.new(pos.X, pos.Z), r = p.Size.Y / 2 }
			elseif p.Shape == roblox.Enum.PartType.Ball then
				return { kind = "circle", c = Vector2.new(pos.X, pos.Z), r = p.Size.X / 2 }
			end
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
				-- ellipsoïde (bloc + SpecialMesh Sphere) : disque englobant de son emprise
				return { kind = "circle", c = Vector2.new(pos.X, pos.Z), r = math.max(p.Size.X, p.Size.Z) / 2 }
			end
			return { kind = "rect", poly = corners({ cframe = p.CFrame, size = p.Size }) }
		end

		local function circleRect(circle, poly)
			-- centre dans le rectangle (quel que soit le sens du contour) : chevauchement
			local positive, negative = false, false
			for i = 1, 4 do
				local a, b = poly[i], poly[i % 4 + 1]
				local e = b - a
				local cross = e.X * (circle.c.Y - a.Y) - e.Y * (circle.c.X - a.X)
				if cross > 0 then
					positive = true
				elseif cross < 0 then
					negative = true
				end
			end
			if not (positive and negative) then
				return true
			end
			local best = math.huge
			for i = 1, 4 do
				best = math.min(best, pointSegment(circle.c, poly[i], poly[i % 4 + 1]))
			end
			return best < circle.r - 1e-6
		end

		local function overlaps(fa, fb)
			if fa.kind == "circle" and fb.kind == "circle" then
				return (fa.c - fb.c).Magnitude < fa.r + fb.r - 1e-6
			elseif fa.kind == "circle" then
				return circleRect(fa, fb.poly)
			elseif fb.kind == "circle" then
				return overlaps(fb, fa)
			end
			return overlap(fa.poly, fb.poly)
		end

		it(
			"une dalle cachée (ranch libre, non découverte, au maximum) cache aussi son icône (SurfaceGui)",
			function()
				local h, W, _, root = world()
				local Pads = h:require("ReplicatedStorage.Shared.Config.Pads")
				local function icon(ranch, key)
					return ranch.Pads[tostring(Pads.Defs[key].socket)].Icon
				end
				-- après la construction : 16 × 4 dalles cachées, aucune icône visible au sol
				local shown = {}
				for slot = 1, 16 do
					local ranch = root.Ranches[tostring(slot)]
					for _, key in Pads.Order do
						local pad = ranch.Pads[tostring(Pads.Defs[key].socket)]
						expect(pad.Transparency).toBe(1)
						if icon(ranch, key).Enabled then
							table.insert(shown, `{slot}.{key}`)
						end
					end
				end
				expect(table.concat(shown, ", ")).toBe("")
				-- découverte : dalle et icône visibles ensemble
				W.setRanchOwner(4, 44)
				local ranch = root.Ranches["4"]
				W.setRanchBuild(4, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 1 }, true, true)
				expect(icon(ranch, "snack").Enabled).toBe(true)
				expect(icon(ranch, "decor").Enabled).toBe(false)
				-- au maximum : dalle et icône cachées
				W.setRanchBuild(4, { snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 1 }, true, true)
				expect(ranch.Pads["1"].Transparency).toBe(1)
				expect(icon(ranch, "snack").Enabled).toBe(false)
				-- ranch libéré : plus aucune icône
				W.setRanchBuild(4, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 15 }, true, true)
				expect(icon(ranch, "pens").Enabled).toBe(true)
				W.setRanchOwner(4, 0)
				for _, key in Pads.Order do
					expect(icon(ranch, key).Enabled).toBe(false)
				end
				zeroLog(h)
			end
		)

		it(
			"icône d'une dalle dessinée sur la face du dessus du disque (tournée vers le ciel), en Frames",
			function()
				local h, W, _, root = world()
				W.setRanchOwner(6, 66)
				W.setRanchBuild(6, { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 15 }, true, true)
				local normals = {
					[roblox.Enum.NormalId.Top] = function(cf)
						return cf.UpVector
					end,
					[roblox.Enum.NormalId.Bottom] = function(cf)
						return -cf.UpVector
					end,
					[roblox.Enum.NormalId.Right] = function(cf)
						return cf.RightVector
					end,
					[roblox.Enum.NormalId.Left] = function(cf)
						return -cf.RightVector
					end,
					[roblox.Enum.NormalId.Front] = function(cf)
						return cf.LookVector
					end,
					[roblox.Enum.NormalId.Back] = function(cf)
						return -cf.LookVector
					end,
				}
				for slot = 1, 16 do
					for _, pad in root.Ranches[tostring(slot)].Pads:GetChildren() do
						local icon = pad.Icon
						local up = normals[icon.Face](pad.CFrame)
						expect({ pad = pad:GetFullName(), up = up.Y > 0.99 }).toEqual({
							pad = pad:GetFullName(),
							up = true,
						})
						expect(#icon:GetChildren() > 0).toBe(true)
					end
				end
				-- tableaux des classements : face avant (SurfaceGui « Board ») tournée vers le centre de la place
				for _, board in root.Plaza.Boards:GetChildren() do
					local panel = board.Panel
					local gui = panel.Board
					local normal = normals[gui.Face](panel.CFrame)
					local p = panel.CFrame.Position
					local toCenter = Vector3.new(-p.X, 0, -p.Z).Unit
					expect(normal:Dot(toCenter) > 0.9).toBe(true)
				end
				-- points d'accroche lus par le client (LightingController) : anneau Neon, gelée de la jarre
				local plaza = root.Plaza
				expect(plaza.MegaPad.Ring.Material).toBe(roblox.Enum.Material.Neon)
				expect(plaza.GaugeJar.Jelly.Material).toBe(roblox.Enum.Material.Neon)
				zeroLog(h)
			end
		)

		it(
			"prises de dalles et décorations lues dans WorldLayout seulement (rangée déplacée à Z = 67, contrat v1.2)",
			function()
				local h = Harness.new()
				local L = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				-- logic déplace les prises à Z = 67 et les décorations : le monde suit sans une ligne changée
				local xs = { -18, -6, 6, 18 }
				local originalDecor = L.decorSlot
				L.padSocket = function(slot, socket)
					return L.toWorld(slot, Vector3.new(xs[socket] or xs[1], 0, 67))
				end
				L.decorSlot = function(slot, index)
					return originalDecor(slot, index) * roblox.CFrame.new(0.75, 0, -1.25)
				end
				local W = h:require("ServerScriptService.Server.Services.WorldService")
				W.Init()
				local root = h.game.Workspace.Wobbleton
				for slot = 1, 16 do
					local ranch = root.Ranches[tostring(slot)]
					for socket = 1, 4 do
						local p = ranch.Pads[tostring(socket)].CFrame.Position
						local want = L.padSocket(slot, socket)
						expect(Vector2.new(p.X - want.X, p.Z - want.Z).Magnitude).toBeLessThan(EPS)
						local localZ = L.toLocal(slot, p).Z
						expect(math.abs(localZ - 67)).toBeLessThan(EPS)
					end
					for i = 1, 18 do
						local holder = ranch.Decor[tostring(i)]
						expect(sameCFrame(holder.WorldPivot, L.decorSlot(slot, i))).toBe(true)
					end
				end
				expect(#W.failures()).toBe(0)
				zeroLog(h)
			end
		)

		it(
			"aucun texte à lire posé dans le monde construit : ni TextLabel ni BillboardGui ; SurfaceGui = icônes en Frames et tableaux vides",
			function()
				local h, _, _, root = world()
				local bad = {}
				for _, d in root:GetDescendants() do
					local cls = d.ClassName
					if
						cls == "TextLabel"
						or cls == "TextButton"
						or cls == "TextBox"
						or cls == "BillboardGui"
					then
						table.insert(bad, d:GetFullName())
					elseif cls == "SurfaceGui" then
						local isBoard = d.Name == "Board"
						local isIcon = d.Name == "Icon" and d.Parent.Parent.Name == "Pads"
						if not (isBoard or isIcon) then
							table.insert(bad, d:GetFullName())
						end
						for _, g in d:GetDescendants() do
							if g.ClassName ~= "Frame" and g.ClassName ~= "UICorner" then
								table.insert(bad, g:GetFullName())
							end
						end
						if isBoard then
							expect(#d:GetChildren()).toBe(0) -- rempli par le client (LeaderboardState)
						end
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
				zeroLog(h)
			end
		)

		it(
			"objets de la place sans chevauchement au sol (jardinières hors de la scène de Big Plop)",
			function()
				local h, _, _, root = world()
				local plaza = root.Plaza
				local groups = {}
				for _, child in plaza:GetChildren() do
					if child.Name ~= "Floor" and child.Name ~= "Border" then
						if child.Name == "Boards" then
							for _, board in child:GetChildren() do
								groups["Board" .. board.Name] = parts(board)
							end
						elseif child:IsA("BasePart") then
							local index = string.match(child.Name, "%d+$") or child.Name
							local key = "Planter" .. index
							groups[key] = groups[key] or {}
							table.insert(groups[key], child)
						else
							groups[child.Name] = parts(child)
						end
					end
				end
				local names = {}
				for name in groups do
					table.insert(names, name)
				end
				table.sort(names)
				expect(#names).toBe(7 + 5 + 4)
				local clashes = {}
				for i = 1, #names do
					for j = i + 1, #names do
						local hit = false
						for _, a in groups[names[i]] do
							for _, b in groups[names[j]] do
								if not hit and overlaps(footprint(a), footprint(b)) then
									hit = true
								end
							end
						end
						if hit then
							table.insert(clashes, names[i] .. " / " .. names[j])
						end
					end
				end
				expect(table.concat(clashes, "\n")).toBe("")
				-- tout reste sur la place (r < 50)
				for _, name in names do
					for _, p in groups[name] do
						local pos = p.CFrame.Position
						expect(Vector2.new(pos.X, pos.Z).Magnitude).toBeLessThan(50)
					end
				end
				zeroLog(h)
			end
		)

		it(
			"objets d'un ranch sans chevauchement au sol (18 décorations, dalles, Pot, Cuve, Bassin, bol, coussin, étagère, clôture)",
			function()
				local h, W, _, root = world()
				W.setRanchOwner(1, 11)
				W.setRanchBuild(
					1,
					{ snack = 12, decor = 18, pens = 0, cozyBed = false, seen = 15 },
					true,
					true
				)
				local clashes = {}
				for slot = 1, 16 do
					local ranch = root.Ranches[tostring(slot)]
					local groups = {}
					for i = 1, 18 do
						groups["Decor" .. i] = parts(ranch.Decor[tostring(i)])
					end
					for _, pad in ranch.Pads:GetChildren() do
						groups["Pad" .. pad.Name] = { pad }
					end
					for _, name in { "Pot", "Vat", "Pool", "Bowl", "Shelf", "Fence" } do
						groups[name] = parts(ranch[name])
					end
					groups.Cushion = { ranch.Cushion }
					local names = {}
					for name in groups do
						table.insert(names, name)
					end
					table.sort(names)
					for i = 1, #names do
						for j = i + 1, #names do
							local hit = false
							for _, a in groups[names[i]] do
								for _, b in groups[names[j]] do
									if not hit and overlaps(footprint(a), footprint(b)) then
										hit = true
									end
								end
							end
							if hit then
								table.insert(clashes, `{slot}: {names[i]} / {names[j]}`)
							end
						end
					end
				end
				expect(table.concat(clashes, " | ")).toBe("")
				zeroLog(h)
			end
		)

		it(
			"murs du bord : faces intérieures sur le cercle r = 322 (WorldLayout), 30 studs de haut",
			function()
				local h, _, L, root = world()
				expect(L.Const.WallRadius).toBe(322)
				local walls = root.Walls:GetChildren()
				expect(#walls).toBe(L.Const.EdgeSegments)
				for _, wall in walls do
					local p = wall.CFrame.Position
					local inner = Vector2.new(p.X, p.Z).Magnitude - wall.Size.Z / 2
					expect(math.abs(inner - 322)).toBeLessThan(1e-3)
					expect(wall.Size.Y).toBeGreaterThanOrEqual(30)
					expect(wall.CanCollide).toBe(true)
				end
				zeroLog(h)
			end
		)
	end)

	-- =========================================================================================
	-- Dalle du Tapis Étoilé (lot B4, étape 1, décision D11 du plan B4 ; N21, docs/04 §27.13) : avec
	-- StarMat et un profil v2, la dalle du Tapis reste allumée au-delà du Tapis 12 tant qu'un niveau du
	-- Tapis Étoilé est ouvert dans la boucle (PadRules.visible) ; interrupteur coupé ou profil v1 : la
	-- v1.3 au bit près (dalle cachée au Tapis 12), sans lecture du profil
	-- =========================================================================================
	describe("WorldBuild › dalle du Tapis Étoilé (lot B4)", function()
		local Bots = require("../harness/Bots")
		local T0 = 1800000000
		local S = "ServerScriptService.Server.Services."
		local HarnessV2 = setmetatable({
			new = function(options)
				local hh = Harness.new(options)
				hh:require("ReplicatedStorage.Shared.Config.Features").Defaults.SchemaV2 = true
				return hh
			end,
		}, { __index = Harness })

		-- Serveur complet ; le joueur 1 arrive avec un profil au Tapis 12 (r = R, Record R = R)
		local function boot(flags, R, harness)
			local caught = {}
			local w = Bots.boot(harness or HarnessV2, {
				t0 = T0,
				before = function(w)
					w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
					local Diag = w.h:require(S .. "DiagnosticsService")
					Diag.reportCaught = function(where, err)
						table.insert(caught, where .. " : " .. tostring(err))
					end
					Diag.stateTimedOut = function() end
					w.F = w.h:require("ReplicatedStorage.Shared.Config.Features")
					for _, key in flags do
						assert(w.F.set(key, true), key)
					end
					local d = Bots.profile(w, { onboarding = { step = 11, done = true, demoDone = true } })
					d.tiles.seen = 15
					d.tiles.snack = 12
					d.coins = 1e30
					d.R = R
					if d.version >= 2 then
						d.bestR = R
						d.tiles.star = 0
					end
					Bots.saveProfile(w, 1, d)
				end,
			})
			w.caught = caught
			w.Economy = w.h:require(S .. "EconomyService")
			w.Ranch = w.h:require(S .. "RanchService")
			w.World = w.h:require(S .. "WorldService")
			w.Pads = w.h:require("ReplicatedStorage.Shared.Config.Pads")
			return w
		end

		local function clean(w)
			expect(table.concat(w.caught, "\n")).toBe("")
			expect(table.concat(w.h.errors, "\n")).toBe("")
			expect(table.concat(w.h:warnings(), "\n")).toBe("")
		end

		-- (visible, Maxed) de la dalle du Tapis du ranch `slot`
		local function snackPad(w, slot)
			local pad = w.World.ranchModel(slot).Pads[tostring(w.Pads.Defs.snack.socket)]
			return { visible = pad.Transparency == 0, maxed = pad:GetAttribute("Maxed") }
		end

		it(
			"StarMat ouvert, profil v2 : allumée (Maxed = false) du Tapis 12 jusqu'au plafond de la boucle, cachée au plafond",
			function()
				-- r = 7 : 2 niveaux du Tapis Étoilé ouverts dans la boucle (Prestige.starCap)
				local w = boot({ "StarMat" }, 7)
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				expect(slot > 0).toBe(true)
				expect(snackPad(w, slot)).toEqual({ visible = true, maxed = false })
				-- un achat par la dalle (Tapis Étoilé 1) : toujours allumée
				expect(w.Economy.buyTile(p, "snack", "pad")).toBe(true)
				expect(w.DS.get(p).tiles.star).toBe(1)
				expect(snackPad(w, slot)).toEqual({ visible = true, maxed = false })
				-- deuxième achat : plafond de la boucle atteint, la dalle se cache
				expect(w.Economy.buyTile(p, "snack", "pad")).toBe(true)
				expect(w.DS.get(p).tiles.star).toBe(2)
				expect(snackPad(w, slot)).toEqual({ visible = false, maxed = true })
				-- un niveau rouvert (r plus haut au prochain passage, ici écrit à la main) : rallumée
				w.DS.get(p).R = 10
				w.Ranch.refreshBuild(p)
				expect(snackPad(w, slot)).toEqual({ visible = true, maxed = false })
				clean(w)
			end
		)

		it(
			"StarMat coupé, profil v1, ou aucun niveau ouvert (r < 6) : cachée au Tapis 12 comme en v1.3, sans lire le profil",
			function()
				local cases = {
					{ flags = {}, R = 10, harness = HarnessV2 }, -- interrupteur coupé
					{ flags = { "StarMat" }, R = 10, harness = Harness }, -- profil v1
					{ flags = { "StarMat" }, R = 3, harness = HarnessV2 }, -- r = 3 : aucun niveau ouvert
				}
				for i, case in cases do
					local w = boot(case.flags, case.R, case.harness)
					local p = Bots.join(1)
					local slot = w.Ranch.slotOf(p)
					expect({ i = i, pad = snackPad(w, slot) }).toEqual({
						i = i,
						pad = { visible = false, maxed = true },
					})
					-- interrupteur coupé : setRanchBuild ne lit aucun profil (même chemin que la v1.3)
					if #case.flags == 0 then
						local reads = 0
						local get = w.DS.get
						w.DS.get = function(...)
							reads += 1
							return get(...)
						end
						w.World.setRanchBuild(
							slot,
							{ snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15 },
							true,
							true
						)
						w.DS.get = get
						expect(reads).toBe(0)
						expect(snackPad(w, slot)).toEqual({ visible = false, maxed = true })
					end
					clean(w)
				end
			end
		)

		it(
			"ranch libre ou propriétaire parti : jamais allumée au-delà du Tapis 12, aucune erreur",
			function()
				local w = boot({ "StarMat" }, 7)
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				expect(snackPad(w, slot).visible).toBe(true)
				-- autre ranch, libre : StarMat ouvert, Tapis 12 → cachée (personne à lire)
				local free = slot % 16 + 1
				w.World.setRanchBuild(
					free,
					{ snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15 },
					true,
					true
				)
				expect(snackPad(w, free)).toEqual({ visible = false, maxed = true })
				-- propriétaire inconnu du serveur (identifiant sans joueur) : cachée
				w.World.setRanchOwner(free, 424242)
				w.World.setRanchBuild(
					free,
					{ snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15 },
					true,
					true
				)
				expect(snackPad(w, free)).toEqual({ visible = false, maxed = true })
				clean(w)
			end
		)
	end)
end
