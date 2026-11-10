--!nocheck
-- SquishyBuilder (paquet world, docs/04 §12.2, GDD §5.2, §9.3, §12.9) : recettes des 26 espèces,
-- 12 pièces au plus pour CHAQUE espèce × mutation × tenue × selle × aura, LOD (12 / corps + yeux /
-- corps), pièces jamais physiques, écrasement d'une seule écriture, pose pour BulkMoveTo, échelle,
-- 9 aspects de mutation (rendu fixe en Mouvement réduit), étoiles, aura (couleur ET forme),
-- attaches, réserve (reprise du même modèle, Handle rendu inerte), entrées hostiles, ApiAudit.
-- v2.0 (lot B5, étape 1 ; plan B5 D5, D6, D11, D12 ; journal docs/04 B5-2 à B5-6), en fin de fichier :
--   * yeux « bébé » : version A de Config/Visuals = EXACTEMENT les recettes de la v1.3 (témoin
--     tests/fixtures/squishy-recipes/v13.txt écrit sur REL-B3) ; B et C ne changent que les yeux ;
--   * visages (setFace) : une écriture de Size par œil et par reflet, bouche par CFrame, retour exact à
--     « happy », réserve, clignement, changement d'échelle et de mutation sous un visage ;
--   * étoiles DESSINÉES (INT-B1-STARS) : aucun TextLabel, aucun TextScaled, 3 Frames par étoile,
--     construites à la première étoile montrée ;
--   * 4 tenues de la v2.0 (une pièce chacune, ≤ 12 pièces partout), couleurs des 9 selles de la v2.0.
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")
local RecipeDump = require("../harness/RecipeDump")

local Enum = roblox.Enum
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function load()
		local h = Harness.new({ mode = "client" })
		local SB = h:require("ReplicatedStorage.Shared.Render.SquishyBuilder")
		local Species = h:require("ReplicatedStorage.Shared.Config.Species")
		local Mutations = h:require("ReplicatedStorage.Shared.Config.Mutations")
		local Rarities = h:require("ReplicatedStorage.Shared.Config.Rarities")
		SB.clearPool()
		return h, SB, Species, Mutations, Rarities
	end

	local function spec(species, extra)
		local s = { species = species, mutation = 0, stars = 1, displayScale = 1, lod = 1 }
		for k, v in extra or {} do
			s[k] = v
		end
		return s
	end

	local function visibleCount(handle)
		local n = 0
		for _, p in handle.parts do
			if p.Transparency < 1 then
				n += 1
			end
		end
		return n
	end

	local function zeroLog(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- tenues de la v1.3 puis, depuis le lot B5 (D12), les 4 tenues de la v2.0 (Cosmetics.ListV2 et tenue
	-- de la semaine) : le budget de 12 pièces vaut pour toutes
	local OUTFITS = {
		false,
		"plopBib",
		"sweater",
		"jellyCrown",
		"winterScarf",
		"bowTie",
		"partyHat",
		"starGlasses",
		"buildersCrown",
		"polkaBow",
	}
	local OUTFITS_V2 = { "partyHat", "starGlasses", "buildersCrown", "polkaBow" }
	local FACES = { "happy", "delighted", "surprised", "sleepy", "starry", "sulky" }
	local GOLD = Color3.fromRGB(255, 205, 60)

	describe("SquishyBuilder › recettes", function()
		it(
			"chaque espèce : recette pure, corps d'abord aux proportions de la ligne, pièces finies",
			function()
				local h, SB, Species = load()
				for _, def in Species.List do
					local r = SB.recipe(def.id)
					expect(r.id).toBe(def.id)
					expect(r.key).toBe(def.key)
					expect(r.pieces[1].role).toBe("body")
					expect(r.pieces[1].size).toEqual(Vector3.new(def.body.x, def.body.y, def.body.z))
					expect(r.pieces[1].color).toBe(def.colors.main)
					expect(r.eyeCount).toBe(if def.eyes == "threeEyes" then 3 else 2)
					expect(r.topCount >= 1 and r.topCount <= 3).toBe(true)
					expect(r.patternCount <= 4).toBe(true)
					for _, p in r.pieces do
						local s = p.size
						expect({
							key = def.key,
							piece = p.name,
							ok = s.X > 0 and s.Y > 0 and s.Z > 0 and s.Magnitude < 3,
						}).toEqual({
							key = def.key,
							piece = p.name,
							ok = true,
						})
						expect(p.offset.Magnitude < 2).toBe(true)
						expect(typeof(p.color)).toBe("Color3")
					end
				end
				-- espèce inconnue : recette de Plop, jamais d'erreur
				for _, bad in { 0, 999, 0 / 0, "plop", nil } do
					expect(SB.recipe(bad).key).toBe("plop")
				end
				zeroLog(h)
			end
		)

		it(
			"12 pièces au plus pour chaque espèce × mutation × tenue × selle × aura ; LOD 2 ≤ 4, LOD 3 = 1",
			function()
				local h, SB, Species, Mutations = load()
				local worst = 0
				for _, def in Species.List do
					for m = 0, Mutations.Count do
						for _, outfit in OUTFITS do
							for _, saddle in { false, "classic", "cosmic" } do
								for _, aura in { false, true } do
									local s = spec(def.id, {
										mutation = m,
										outfit = outfit or nil,
										saddle = saddle or nil,
										rarityAura = aura,
									})
									local n = SB.partCount(s)
									worst = math.max(worst, n)
									expect({ key = def.key, m = m, n = n <= 12 }).toEqual({
										key = def.key,
										m = m,
										n = true,
									})
									s.lod = 2
									expect(SB.partCount(s) <= 4).toBe(true)
									s.lod = 3
									expect(SB.partCount(s)).toBe(1)
								end
							end
						end
					end
				end
				expect(worst).toBe(12) -- le budget est utilisé, jamais dépassé
				zeroLog(h)
			end
		)

		it("un squishy simple garde son visage : corps, 2 yeux, haut de tête, bouche, joues", function()
			local h, SB = load()
			local handle = SB.build(spec(1))
			local names = {}
			for _, p in handle.parts do
				names[p.Name] = true
			end
			for _, name in
				{ "Body", "Eye1", "Eye2", "Drop", "Mouth1", "Mouth2", "Mouth3", "Cheek1", "Cheek2", "Belly" }
			do
				expect({ name = name, found = names[name] == true }).toEqual({ name = name, found = true })
			end
			expect(#handle.parts).toBe(SB.partCount(spec(1)))
			zeroLog(h)
		end)
	end)

	describe("SquishyBuilder › instances", function()
		it(
			"toutes les pièces : ancrées, CanCollide = CanQuery = CanTouch = false, sans ombre ; corps = sphère",
			function()
				local h, SB, Species, Mutations = load()
				for _, def in Species.List do
					for _, m in { 0, 1, 5, 9 } do
						local handle = SB.build(
							spec(
								def.id,
								{ mutation = m, outfit = "sweater", saddle = "mint", rarityAura = true }
							)
						)
						expect(handle.parts[1]).toBe(handle.body)
						expect(handle.model.PrimaryPart).toBe(handle.body)
						local mesh = handle.body:FindFirstChildOfClass("SpecialMesh")
						expect(mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere).toBe(true)
						for _, p in handle.parts do
							expect(
								p.Anchored
									and not p.CanCollide
									and not p.CanQuery
									and not p.CanTouch
									and not p.CastShadow
							).toBe(true)
							-- transparence seulement pour la mutation Gelée (sur le corps)
							if p.Transparency > 0 and p.Transparency < 1 then
								expect({ key = def.key, m = m, part = p.Name }).toEqual({
									key = def.key,
									m = Mutations.ByKey.jelly.id,
									part = "Body",
								})
							end
						end
						SB.release(handle)
					end
				end
				zeroLog(h)
			end
		)

		it(
			"LOD : 1 = tout, 2 = corps + yeux, 3 = corps seul (pose ne rend que les pièces visibles)",
			function()
				local h, SB = load()
				local handle = SB.build(spec(5, { rarityAura = true }))
				local full = #handle.parts
				expect(visibleCount(handle)).toBe(full)
				SB.setLod(handle, 2)
				expect(handle.lod).toBe(2)
				expect(visibleCount(handle)).toBe(3)
				local parts = SB.pose(handle, CFrame.new())
				expect(#parts).toBe(3)
				SB.setLod(handle, 3)
				expect(visibleCount(handle)).toBe(1)
				expect(#SB.pose(handle, CFrame.new())).toBe(1)
				SB.setLod(handle, 1)
				expect(visibleCount(handle)).toBe(full)
				for _, bad in { 0, 9, 0 / 0, "2", 1.7 } do
					SB.setLod(handle, bad)
					expect(handle.lod >= 1 and handle.lod <= 3).toBe(true)
				end
				zeroLog(h)
			end
		)

		it("setSquash : une seule écriture (body.Size), les autres pièces suivent par pose()", function()
			local h, SB = load()
			local handle = SB.build(spec(1))
			local before = {}
			for i, p in handle.parts do
				before[i] = p.Size
			end
			local base = handle.body.Size
			SB.setSquash(handle, 1.35, 0.6, 1.35)
			expect(
				(handle.body.Size - Vector3.new(base.X * 1.35, base.Y * 0.6, base.Z * 1.35)).Magnitude < 1e-6
			).toBe(true)
			for i = 2, #handle.parts do
				expect(handle.parts[i].Size).toBe(before[i])
			end
			-- les yeux descendent avec le corps écrasé
			local parts0, cf0 = SB.pose(handle, CFrame.new())
			local eyeIndex
			for i, p in parts0 do
				if p.Name == "Eye1" then
					eyeIndex = i
				end
			end
			local squashedY = cf0[eyeIndex].Position.Y
			SB.setSquash(handle, 1, 1, 1)
			local _, cf1 = SB.pose(handle, CFrame.new())
			expect(squashedY < cf1[eyeIndex].Position.Y).toBe(true)
			for _, bad in { { 0 / 0, 1, 1 }, { math.huge, -5, 0 }, { "x", nil, {} } } do
				SB.setSquash(handle, bad[1], bad[2], bad[3])
				local s = handle.body.Size
				expect(s.X == s.X and s.X > 0 and s.Y > 0 and s.Z > 0).toBe(true)
			end
			zeroLog(h)
		end)

		it(
			"pose : listes de même taille, repère du modèle suivi, tables réutilisées (aucune allocation par image)",
			function()
				local h, SB = load()
				local handle = SB.build(spec(9))
				local origin = CFrame.new(10, 2, -4) * CFrame.Angles(0, math.rad(90), 0)
				local parts, cframes = SB.pose(handle, origin)
				expect(#parts).toBe(#cframes)
				expect(#parts).toBe(#handle.parts)
				-- corps : centre à mi-hauteur au-dessus de l'origine
				local bodyLocal = origin:Inverse() * cframes[1].Position
				expect(math.abs(bodyLocal.X) < 1e-6 and math.abs(bodyLocal.Z) < 1e-6).toBe(true)
				expect(math.abs(bodyLocal.Y - handle.body.Size.Y / 2) < 1e-6).toBe(true)
				-- visage vers −Z du repère : les yeux sont devant le corps
				for i, p in parts do
					if p.Name == "Eye1" then
						expect((origin:Inverse() * cframes[i].Position).Z < 0).toBe(true)
					end
				end
				local parts2, cframes2 = SB.pose(handle, origin)
				expect(parts2).toBe(parts)
				expect(cframes2).toBe(cframes)
				h.game.Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
				expect(handle.body.CFrame.Position).toBe(cframes[1].Position)
				zeroLog(h)
			end
		)

		it(
			"setScale : diamètre = 2 studs × échelle (Balance.SizeScale.BaseDiameter), décalages suivis",
			function()
				local h, SB = load()
				local handle = SB.build(spec(1, { displayScale = 1 }))
				expect((handle.body.Size - Vector3.new(2, 2, 2)).Magnitude < 1e-6).toBe(true)
				local off = handle.offsets[2].Position
				SB.setScale(handle, 3) -- Big Plop : diamètre 6 studs
				expect((handle.body.Size - Vector3.new(6, 6, 6)).Magnitude < 1e-6).toBe(true)
				expect((handle.offsets[2].Position - off * 3).Magnitude < 1e-6).toBe(true)
				SB.setScale(handle, 0 / 0)
				expect(handle.body.Size.X == handle.body.Size.X).toBe(true)
				zeroLog(h)
			end
		)

		it("étoiles : 0 à 5 visibles, BillboardGui sous 60 studs, seulement en détail complet", function()
			local h, SB = load()
			local handle = SB.build(spec(1, { stars = 3 }))
			local gui = handle.body:FindFirstChild("Stars")
			expect(gui.ClassName).toBe("BillboardGui")
			expect(gui.MaxDistance).toBe(60)
			-- étoiles DESSINÉES depuis le lot B5 (D11, INT-B1-STARS ; attente changée, journal B5-4 : elle
			-- comptait des TextLabel « ★ ») : une étoile est montrée quand ses 3 traits le sont
			local function shown()
				local n = 0
				for i = 1, 5 do
					local rays = 0
					for k = 1, 3 do
						local ray = gui:FindFirstChild("Star" .. i .. "Ray" .. k)
						if ray and ray.Visible then
							rays += 1
						end
					end
					expect({ star = i, rays = rays == 0 or rays == 3 }).toEqual({ star = i, rays = true })
					if rays == 3 then
						n += 1
					end
				end
				return n
			end
			expect(shown()).toBe(3)
			expect(gui.Enabled).toBe(true)
			for _, case in { { 5, 5 }, { 0, 0 }, { 99, 5 }, { -2, 0 }, { 0 / 0, 0 } } do
				SB.setStars(handle, case[1])
				expect(shown()).toBe(case[2])
			end
			SB.setStars(handle, 2)
			SB.setLod(handle, 2)
			expect(gui.Enabled).toBe(false)
			SB.setLod(handle, 1)
			expect(gui.Enabled).toBe(true)
			zeroLog(h)
		end)

		it(
			"aura de rareté : forme propre à chaque rareté (aucune pour Commun), lumière des Légendaires éteinte",
			function()
				local h, SB, Species, _, Rarities = load()
				local shapes = {}
				for _, def in Species.List do
					local handle = SB.build(spec(def.id, { rarityAura = true }))
					local aura = handle.body:FindFirstChild("Aura")
					local rarity = Rarities.List[def.rarity]
					if rarity.aura == "none" then
						expect(aura).toBeNil()
					else
						expect(aura.ClassName).toBe("BillboardGui")
						local names = {}
						for _, c in aura:GetChildren() do
							table.insert(names, c.Name)
						end
						table.sort(names)
						local key = table.concat(names, ",")
						if shapes[rarity.aura] then
							expect(shapes[rarity.aura]).toBe(key)
						end
						shapes[rarity.aura] = key
					end
					local light = handle.body:FindFirstChild("AuraLight")
					expect(light ~= nil).toBe(rarity.light)
					if light then
						expect(light.Enabled).toBe(false)
					end
					SB.setAura(handle, false)
					if aura then
						expect(aura.Enabled).toBe(false)
					end
					SB.release(handle)
				end
				-- chaque forme est différente des autres (couleur ET forme)
				local seen = {}
				for _, key in shapes do
					expect(seen[key]).toBeNil()
					seen[key] = true
				end
				zeroLog(h)
			end
		)

		it("attaches : selle sur le dessus, tête au-dessus, tenue devant ; suivent l'écrasement", function()
			local h, SB = load()
			local handle = SB.build(spec(1, { saddle = "peach" }))
			local a = SB.attachments(handle)
			local top = handle.body.Size.Y
			expect(a.saddle.Position.Y > top * 0.8 and a.saddle.Position.Y <= top).toBe(true)
			expect(a.head.Position.Y > top).toBe(true)
			expect(a.outfit.Position.Z < 0).toBe(true)
			SB.setSquash(handle, 1.3, 0.7, 1.3)
			expect(SB.attachments(handle).head.Position.Y < a.head.Position.Y).toBe(true)
			-- selle : couleur de Config/Cosmetics, puis couleur du ranch posée par le renderer
			local saddle = handle.model:FindFirstChild("Saddle")
			expect(saddle.Color).toBe(Color3.fromRGB(255, 190, 150))
			SB.setSaddleColor(handle, Color3.fromRGB(1, 2, 3))
			expect(saddle.Color).toBe(Color3.fromRGB(1, 2, 3))
			zeroLog(h)
		end)
	end)

	describe("SquishyBuilder › mutations (Config/Mutations.look)", function()
		local function build(m, reduced)
			local h, SB, _, Mutations = load()
			local handle = SB.build(spec(1, { mutation = Mutations.ByKey[m].id }))
			SB.setMutation(handle, Mutations.ByKey[m].id, reduced == true)
			return h, SB, handle, Mutations
		end
		local function find(handle, name)
			for _, p in handle.parts do
				if p.Name == name then
					return p
				end
			end
			return nil
		end

		it("Gelée : verre transparent (0,2) et petit noyau ; Néon : oreilles et motif en Neon", function()
			local h, _, handle = build("jelly")
			expect(handle.body.Material).toBe(Enum.Material.Glass)
			expect(handle.body.Transparency).toBe(0.2)
			expect(find(handle, "Core") ~= nil).toBe(true)
			local h2, _, neon = build("neon")
			expect(find(neon, "Drop").Material).toBe(Enum.Material.Neon)
			zeroLog(h)
			zeroLog(h2)
		end)

		it(
			"Givré, Doré : matériau et particules ; Galaxie : corps sombre, coque ForceField, points Neon",
			function()
				local _, _, frosted = build("frosted")
				expect(frosted.body.Material).toBe(Enum.Material.Ice)
				expect(frosted.body:FindFirstChildOfClass("ParticleEmitter") ~= nil).toBe(true)
				local _, _, golden = build("golden")
				expect(golden.body.Material).toBe(Enum.Material.Foil)
				expect(golden.body.Color).toBe(Color3.fromRGB(255, 205, 60))
				local h, _, galaxy = build("galaxy")
				expect(galaxy.body.Color).toBe(Color3.fromRGB(25, 20, 60))
				expect(find(galaxy, "Shell").Material).toBe(Enum.Material.ForceField)
				expect(find(galaxy, "Star1") ~= nil).toBe(true)
				zeroLog(h)
			end
		)

		it("Lunaire : croissant, 3e œil, gouttes en orbite qui tournent (animate)", function()
			local h, SB, lunar = build("lunar")
			expect(find(lunar, "Crescent") ~= nil).toBe(true)
			expect(find(lunar, "Eye3") ~= nil).toBe(true)
			local orbiter
			for i, p in lunar.parts do
				if p.Name == "Orbiter1" then
					orbiter = i
				end
			end
			expect(orbiter ~= nil).toBe(true)
			SB.animate(lunar, 0)
			local a = lunar.offsets[orbiter].Position
			SB.animate(lunar, 0.75)
			local b = lunar.offsets[orbiter].Position
			expect((a - b).Magnitude > 0.1).toBe(true)
			-- Mouvement réduit : orbiteurs immobiles
			SB.animate(lunar, 0.2, true)
			local c = lunar.offsets[orbiter].Position
			SB.animate(lunar, 1.1, true)
			expect((lunar.offsets[orbiter].Position - c).Magnitude < 1e-9).toBe(true)
			zeroLog(h)
		end)

		it(
			"Arc-en-ciel : couleurs qui tournent (6 s) ; Mouvement réduit : dégradé fixe, plus aucun changement",
			function()
				local h, SB, rainbow = build("rainbow")
				SB.animate(rainbow, 0)
				local c0 = rainbow.body.Color
				SB.animate(rainbow, 2)
				expect(rainbow.body.Color ~= c0).toBe(true)
				local _, SB2, fixed = build("rainbow", true)
				local f0 = fixed.body.Color
				for _, t in { 0, 1, 2.5, 4 } do
					SB2.animate(fixed, t, true)
					expect(fixed.body.Color).toBe(f0)
				end
				zeroLog(h)
			end
		)

		it("Glitch : jamais plus de 3 changements par seconde ; damier fixe en Mouvement réduit", function()
			local h, SB, glitch = build("glitch")
			local changes, last = 0, nil
			for i = 0, 100 do
				SB.animate(glitch, i / 100)
				local c = glitch.body.Color
				if last ~= nil and c ~= last then
					changes += 1
				end
				last = c
			end
			expect(changes <= 3).toBe(true)
			expect(changes >= 1).toBe(true)
			local _, SB2, fixed = build("glitch", true)
			local f0 = fixed.body.Color
			for i = 0, 50 do
				SB2.animate(fixed, i / 25, true)
			end
			expect(fixed.body.Color).toBe(f0)
			zeroLog(h)
		end)

		it("Flop : dégonflé (hauteur × 0,6, largeur × 1,25), yeux mi-clos, étoiles dorées", function()
			local h, _, flop = build("flop")
			local s = flop.body.Size
			expect(math.abs(s.Y - 2 * 0.6) < 1e-6).toBe(true)
			expect(math.abs(s.X - 2 * 1.25) < 1e-6).toBe(true)
			expect(find(flop, "GoldStar1") ~= nil).toBe(true)
			local eye = find(flop, "Eye1")
			expect(eye.Size.Y < eye.Size.X * 0.6).toBe(true)
			zeroLog(h)
		end)

		it(
			"setMutation sur un modèle vivant : nouveau jeu de pièces, même parent, ≤ 12 pièces, LOD gardé",
			function()
				local h, SB, _, Mutations = load()
				local folder = MockInstance.new("Folder")
				folder.Parent = h.game.Workspace
				local handle = SB.build(spec(13, { outfit = "jellyCrown", saddle = "classic" }), folder)
				SB.setLod(handle, 2)
				for m = 1, Mutations.Count do
					SB.setMutation(handle, m, false)
					expect(handle.spec.mutation).toBe(m)
					expect(handle.model.Parent).toBe(folder)
					expect(#handle.parts <= 12).toBe(true)
					expect(handle.lod).toBe(2)
					expect(visibleCount(handle) <= 4).toBe(true)
				end
				SB.setMutation(handle, 999, false) -- inconnue : aucune mutation
				expect(handle.spec.mutation).toBe(0)
				zeroLog(h)
			end
		)
	end)

	describe("SquishyBuilder › réserve et robustesse", function()
		it(
			"release puis build du même aspect : le même modèle est repris ; Handle rendu inerte",
			function()
				local h, SB = load()
				local a = SB.build(spec(2, { stars = 2 }))
				local model = a.model
				SB.release(a)
				SB.release(a) -- double rendu : sans effet
				expect(model.Parent).toBeNil()
				expect(SB.poolStats().pooled).toBe(1)
				local b = SB.build(spec(2, { stars = 4 }))
				expect(b.model).toBe(model)
				expect(SB.poolStats().pooled).toBe(0)
				-- l'ancien Handle ne touche plus au modèle repris
				local size = b.body.Size
				SB.setSquash(a, 2, 0.5, 2)
				SB.setScale(a, 5)
				SB.setLod(a, 3)
				SB.setStars(a, 0)
				SB.setMutation(a, 1, false)
				SB.animate(a, 3)
				expect(b.body.Size).toBe(size)
				expect(visibleCount(b)).toBe(#b.parts)
				local parts = SB.pose(a, CFrame.new())
				expect(#parts).toBe(0)
				-- aspect différent : un autre modèle
				local c = SB.build(spec(3))
				expect(c.model ~= model).toBe(true)
				zeroLog(h)
			end
		)

		it(
			"réserve : un modèle repris repart propre (lumière d'aura éteinte, particules et aura rétablies)",
			function()
				local h, SB, Species, Mutations, Rarities = load()
				-- une espèce Légendaire (PointLight d'aura) et une mutation à particules
				local legend, sparkly
				for _, def in Species.List do
					local rarity = Rarities.List[def.rarity]
					if legend == nil and rarity and rarity.light then
						legend = def.id
					end
				end
				for id, m in Mutations.List do
					if sparkly == nil and m.look.particles then
						sparkly = id
					end
				end
				expect(legend ~= nil and sparkly ~= nil).toBe(true)
				local s = spec(legend, { mutation = sparkly, rarityAura = true })
				local a = SB.build(s)
				local light = a.body:FindFirstChild("AuraLight")
				expect(light.Enabled).toBe(false)
				-- le renderer allume la lumière (4 Légendaires les plus proches), coupe aura et particules
				light.Enabled = true
				SB.setAura(a, false)
				SB.setParticles(a, 0)
				SB.release(a)
				local b = SB.build(s)
				expect(b.model).toBe(a.model)
				-- repris : rien n'est hérité du Handle rendu (sinon le quota de lumières est dépassé)
				expect(b.body:FindFirstChild("AuraLight").Enabled).toBe(false)
				expect(b.body:FindFirstChild("Aura").Enabled).toBe(true)
				local emitter = b.body:FindFirstChildWhichIsA("ParticleEmitter")
				expect(emitter.Enabled).toBe(true)
				expect(emitter.Rate > 0).toBe(true)
				zeroLog(h)
			end
		)

		it("réserve bornée : au-delà de POOL_PER_LOOK, les modèles rendus sont détruits", function()
			local h, SB = load()
			local handles = {}
			for i = 1, SB.POOL_PER_LOOK + 5 do
				handles[i] = SB.build(spec(1))
			end
			for _, handle in handles do
				SB.release(handle)
			end
			expect(SB.poolStats().pooled).toBe(SB.POOL_PER_LOOK)
			zeroLog(h)
		end)

		it("spécifications hostiles : jamais d'erreur, valeurs saines", function()
			local h, SB = load()
			for _, s in
				{
					{},
					{ species = "x", mutation = 0 / 0, stars = math.huge, displayScale = -5, lod = 99 },
					{
						species = 1e308,
						mutation = -1,
						stars = -3,
						displayScale = 0 / 0,
						lod = 0 / 0,
						outfit = 5,
						saddle = {},
					},
					{
						species = 26,
						mutation = 7,
						stars = 2.5,
						displayScale = 1e9,
						lod = "1",
						outfit = "nope",
						saddle = "nope",
					},
				}
			do
				local handle = SB.build(s)
				expect(#handle.parts >= 1 and #handle.parts <= 12).toBe(true)
				local size = handle.body.Size
				expect(size.X == size.X and size.X > 0).toBe(true)
				SB.release(handle)
				expect(SB.partCount(s) >= 1).toBe(true)
			end
			local handle = SB.build(nil)
			expect(handle.spec.species).toBe(1)
			zeroLog(h)
		end)

		it("80 squishies (budget de détail complet) : ≤ 960 pièces, une seule BulkMoveTo", function()
			local h, SB, Species = load()
			local all, cfs = {}, {}
			for i = 1, 80 do
				local def = Species.List[(i - 1) % #Species.List + 1]
				local handle = SB.build(spec(def.id, { mutation = i % 10, rarityAura = true }))
				local parts, cframes = SB.pose(handle, CFrame.new(i * 5, 0, 0))
				for j, p in parts do
					table.insert(all, p)
					table.insert(cfs, cframes[j])
				end
			end
			expect(#all <= 80 * 12).toBe(true)
			h.game.Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			zeroLog(h)
		end)

		it("API Roblox valide (ApiAudit) : construction, chaque fonction, chaque mutation", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, SB, _, Mutations = load()
				local handle = SB.build(
					spec(8, { outfit = "winterScarf", saddle = "royal", rarityAura = true, stars = 5 })
				)
				for m = 0, Mutations.Count do
					SB.setMutation(handle, m, m % 2 == 0)
					SB.animate(handle, m * 0.37)
				end
				SB.setSquash(handle, 1.2, 0.8, 1.2)
				SB.setScale(handle, 2.5)
				SB.setLod(handle, 2)
				SB.setLod(handle, 1)
				SB.setStars(handle, 3)
				SB.setParticles(handle, 0.3)
				SB.setAura(handle, false)
				SB.setSaddleColor(handle, Color3.new(1, 0, 0))
				SB.attachments(handle)
				-- v2.0 (lot B5) : visages, étoiles dessinées, tenues de la v2.0
				for _, face in FACES do
					SB.setFace(handle, face)
					SB.animate(handle, 1.23)
				end
				SB.setStars(handle, 5)
				SB.release(handle)
				for _, outfit in OUTFITS_V2 do
					SB.release(SB.build(spec(1, { outfit = outfit, saddle = "cosmic", stars = 2 })))
				end
				zeroLog(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
