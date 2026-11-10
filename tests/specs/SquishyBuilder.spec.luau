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

	-- =========================================================================================
	-- v2.0 (lot B5, étape 1)
	-- =========================================================================================

	local VISUALS = "ReplicatedStorage.Shared.Config.Visuals"

	-- Propriétés qui changent pendant fn() : [pièce][propriété] = nombre de changements
	local function watch(handle, fn)
		local counts, conns = {}, {}
		for i, part in handle.parts do
			counts[i] = {}
			table.insert(
				conns,
				part.Changed:Connect(function(prop)
					counts[i][prop] = (counts[i][prop] or 0) + 1
				end)
			)
		end
		fn()
		for _, c in conns do
			c:Disconnect()
		end
		return counts
	end

	local function partOf(handle, name)
		for i, part in handle.parts do
			if part.Name == name then
				return part, i
			end
		end
		return nil
	end

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-5)
	end

	-- identifiants d'une sorte dans Cosmetics.ListV2 puis dans la rotation de la semaine
	local function v2Ids(Cosmetics, kind)
		local out = {}
		for _, list in { Cosmetics.ListV2, Cosmetics.WeeklyRotation } do
			for _, def in list do
				if def.kind == kind then
					table.insert(out, def.id)
				end
			end
		end
		return out
	end

	local function witness()
		local lines = string.split(fs.readFile("tests/fixtures/squishy-recipes/v13.txt"), "\n")
		if lines[#lines] == "" then
			table.remove(lines)
		end
		return lines
	end

	describe("SquishyBuilder › yeux « bébé » (lot B5, D5)", function()
		it(
			"version A (livrée) : recettes et plans EXACTEMENT ceux de la v1.3 (témoin écrit sur REL-B3) pour les 26 espèces",
			function()
				local h, SB, Species, Mutations = load()
				local Visuals = h:require(VISUALS)
				expect(Visuals.EyeChoice).toBe("A")
				expect(Visuals.Eyes.A).toEqual({ size = 0.22, height = 0.12 })
				expect(Visuals.Eyes.B).toEqual({ size = 0.26, height = 0.04 })
				expect(Visuals.Eyes.C).toEqual({ size = 0.30, height = 0.00 })
				local expected = witness()
				local lines = RecipeDump.lines(SB, Species, Mutations)
				expect(#lines).toBe(#expected)
				expect(#lines > 26 * 6).toBe(true)
				for i, line in lines do
					if line ~= expected[i] then
						expect({ i = i, line = line }).toEqual({ i = i, line = expected[i] })
					end
				end
				zeroLog(h)
			end
		)

		it(
			"versions B et C : seuls les yeux et leurs reflets changent (plus gros, plus bas) ; yeux des grenouilles : taille seulement ; 12 pièces au plus",
			function()
				local hA, SBA, Species = load()
				local expected = witness()
				for _, choice in { "B", "C" } do
					local h, SB, _, Mutations = load()
					local Visuals = h:require(VISUALS)
					Visuals.EyeChoice = choice
					local k = Visuals.Eyes[choice].size / 0.22
					expect(k > 1).toBe(true)
					-- tout sauf les yeux et les reflets : lignes du témoin de la v1.3
					local lines = RecipeDump.lines(SB, Species, Mutations)
					expect(#lines).toBe(#expected)
					local eyeLines = 0
					for i, line in lines do
						local fields = string.split(expected[i], "|")
						local role = fields[2]
						if string.sub(line, 1, 2) == "D " then
							expect(string.sub(expected[i], 1, 2)).toBe("D ")
						elseif role == "eye" or role == "glint" then
							eyeLines += 1
							expect({ i = i, changed = line ~= expected[i] }).toEqual({ i = i, changed = true })
						elseif line ~= expected[i] then
							expect({ i = i, line = line }).toEqual({ i = i, line = expected[i] })
						end
					end
					expect(eyeLines > 26 * 2).toBe(true)
					for _, def in Species.List do
						local a, b = SBA.recipe(def.id), SB.recipe(def.id)
						expect(#b.pieces).toBe(#a.pieces)
						local bulgy = def.eyes == "bulgy"
							or def.eyes == "bulgyWink"
							or string.sub(def.top, 1, 7) == "bugEyes"
						for i, pa in a.pieces do
							local pb = b.pieces[i]
							expect(pb.name).toBe(pa.name)
							local label = def.key .. " " .. pa.name .. " " .. choice
							if pa.role == "eye" then
								-- largeur × k, pour chaque sorte d'œil
								expect({ label, math.abs(pb.size.X - pa.size.X * k) < 1e-5 }).toEqual({
									label,
									true,
								})
								if pa.name == "Eye3" or bulgy then
									expect({ label, near(pb.offset, pa.offset) }).toEqual({ label, true })
								else
									-- plus bas sur le visage, toujours à la surface du corps (devant)
									expect({ label, pb.offset.Y < pa.offset.Y - 0.03 * def.body.y }).toEqual({
										label,
										true,
									})
									expect({ label, pb.offset.Z < 0 }).toEqual({ label, true })
									local h0 = (pb.offset.Y - def.body.y / 2) / def.body.y
									expect({ label, math.abs(h0 - Visuals.Eyes[choice].height) < 0.01 }).toEqual({
										label,
										true,
									})
								end
							elseif pa.role == "glint" then
								expect({ label, near(pb.size, pa.size * k) }).toEqual({ label, true })
							end
						end
						-- budget inchangé : mêmes nombres de pièces à chaque niveau de détail
						for _, lod in { 1, 2, 3 } do
							local s = spec(def.id, { lod = lod, outfit = "partyHat", saddle = "classic" })
							expect(SB.partCount(s)).toBe(SBA.partCount(s))
							expect(SB.partCount(s) <= 12).toBe(true)
						end
					end
					zeroLog(h)
				end
				zeroLog(hA)
			end
		)

		it("version inconnue ou abîmée : les recettes de la version A, sans trace", function()
			local expected = witness()
			local bad = {
				function(V)
					V.EyeChoice = "Z"
				end,
				function(V)
					V.EyeChoice = nil
				end,
				function(V)
					V.EyeChoice = 3
				end,
				function(V)
					V.Eyes.A = { size = "gros", height = 0.12 }
				end,
				function(V)
					V.Eyes.A = { size = 0 / 0, height = 0.12 }
				end,
				function(V)
					V.Eyes.A = { size = 5, height = 0.12 }
				end,
				function(V)
					V.Eyes.A = { size = 0.22, height = -3 }
				end,
				function(V)
					V.Eyes.A = 7
				end,
				function(V)
					V.Eyes = {}
				end,
			}
			for case, spoil in bad do
				local h, SB, Species, Mutations = load()
				spoil(h:require(VISUALS))
				local lines = RecipeDump.lines(SB, Species, Mutations)
				for i, line in lines do
					if line ~= expected[i] then
						expect({ case = case, i = i, line = line }).toEqual({
							case = case,
							i = i,
							line = expected[i],
						})
					end
				end
				SB.release(SB.build(spec(1)))
				zeroLog(h)
			end
		end)
	end)

	describe("SquishyBuilder › visages (lot B5, D6)", function()
		it("FACES = Config/Visuals.Faces (les 6 visages du GDD §5.6), « happy » par défaut", function()
			local h, SB = load()
			local Visuals = h:require(VISUALS)
			expect(SB.FACES).toEqual(Visuals.Faces)
			expect(SB.FACES).toEqual(FACES)
			expect(table.isfrozen(SB.FACES)).toBe(true)
			local handle = SB.build(spec(1))
			expect(SB.faceOf(handle)).toBe("happy")
			zeroLog(h)
		end)

		it(
			"chaque espèce × chaque visage : UNE écriture de Size au plus par œil et par reflet, aucune ailleurs ; même visage : rien ; retour à « happy » : tailles, matériaux et décalages exacts",
			function()
				local h, SB, Species = load()
				for _, def in Species.List do
					local handle = SB.build(spec(def.id, { stars = 0 }))
					local pieces = SB._plan(handle.spec)
					expect(#pieces).toBe(#handle.parts)
					local size0, mat0, off0, tr0, col0 = {}, {}, {}, {}, {}
					for i, part in handle.parts do
						size0[i], mat0[i], off0[i] = part.Size, part.Material, handle.offsets[i]
						tr0[i], col0[i] = part.Transparency, part.Color
					end
					for _, face in FACES do
						if face ~= "happy" then
							local label = def.key .. " " .. face
							local counts = watch(handle, function()
								SB.setFace(handle, face)
							end)
							expect(SB.faceOf(handle)).toBe(face)
							local seen = false
							for i in handle.parts do
								local role = pieces[i].role
								local n = counts[i].Size or 0
								local limit = if role == "eye" or role == "glint" then 1 else 0
								expect({ label, pieces[i].name, n <= limit }).toEqual({
									label,
									pieces[i].name,
									true,
								})
								for prop in counts[i] do
									local allowed = prop == "Size" or (prop == "Material" and role == "glint")
									expect({ label, pieces[i].name, prop, allowed }).toEqual({
										label,
										pieces[i].name,
										prop,
										true,
									})
								end
								if n > 0 or handle.offsets[i] ~= off0[i] then
									seen = true
								end
								-- un décalage ne bouge que pour les yeux, les reflets et la bouche
								if handle.offsets[i] ~= off0[i] then
									local moves = role == "eye" or role == "glint" or role == "mouth"
									expect({ label, pieces[i].name, moves }).toEqual({
										label,
										pieces[i].name,
										true,
									})
								end
							end
							-- chaque visage se voit sur chaque espèce
							expect({ label, seen }).toEqual({ label, true })
							-- même visage : aucune écriture
							local again = watch(handle, function()
								SB.setFace(handle, face)
							end)
							for i in handle.parts do
								expect({ label, next(again[i]) == nil }).toEqual({ label, true })
							end
							-- retour à « happy » : une écriture au plus, tout revient exactement
							local back = watch(handle, function()
								SB.setFace(handle, "happy")
							end)
							expect(SB.faceOf(handle)).toBe("happy")
							for i, part in handle.parts do
								expect({ label, (back[i].Size or 0) <= 1 }).toEqual({ label, true })
								expect({ label, part.Size == size0[i] }).toEqual({ label, true })
								expect({ label, part.Material == mat0[i] }).toEqual({ label, true })
								expect({ label, handle.offsets[i] == off0[i] }).toEqual({ label, true })
								expect({ label, part.Transparency == tr0[i] }).toEqual({ label, true })
								expect({ label, part.Color == col0[i] }).toEqual({ label, true })
							end
						end
					end
					SB.release(handle)
				end
				zeroLog(h)
			end
		)

		it(
			"Plop : Ravi (yeux fermés relevés, reflets cachés, grand sourire), Surpris (× 1,2, bouche ronde), Endormi, Étoilé (reflets × 1,6 en Neon), Boudeur (yeux du Flop, bouche à l'envers)",
			function()
				local h, SB = load()
				local handle = SB.build(spec(1, { stars = 0 }))
				local d = handle.body.Size.X -- 2 studs
				local eye, eyeIndex = partOf(handle, "Eye1")
				local glint = partOf(handle, "Glint1")
				local _, m1 = partOf(handle, "Mouth1")
				local _, m2 = partOf(handle, "Mouth2")
				local _, m3 = partOf(handle, "Mouth3")
				local eye0, glint0 = eye.Size, glint.Size
				local function at(i)
					local parts, cframes = SB.pose(handle, CFrame.new())
					for j, part in parts do
						if part == handle.parts[i] then
							return cframes[j].Position
						end
					end
					return nil
				end
				local eyeY, mouth1, mouth2, mouth3 = at(eyeIndex).Y, at(m1), at(m2), at(m3)
				expect(mouth2.Y < mouth1.Y).toBe(true) -- sourire de la recette : le milieu plus bas
				local smile = mouth3.X - mouth1.X

				SB.setFace(handle, "delighted")
				expect(eye.Size.Y < eye.Size.X * 0.4).toBe(true)
				expect(eye.Size.Y >= 0.05 * d - 1e-6).toBe(true)
				expect(glint.Size.Magnitude < 0.01).toBe(true)
				expect(math.abs(at(eyeIndex).Y - (eyeY + 0.02 * d)) < 1e-5).toBe(true)
				expect(at(m3).X - at(m1).X > smile * 1.2).toBe(true)
				expect(at(m2).Y < at(m1).Y).toBe(true)

				SB.setFace(handle, "surprised")
				expect(near(eye.Size, eye0 * 1.2)).toBe(true)
				expect(near(glint.Size, glint0 * 1.2)).toBe(true)
				expect(math.abs(at(eyeIndex).Y - eyeY) < 1e-5).toBe(true)
				-- bouche ronde : les 3 pièces serrées (elles se touchent)
				local ball = handle.parts[m1].Size.X
				expect((at(m1) - at(m2)).Magnitude < ball).toBe(true)
				expect((at(m3) - at(m2)).Magnitude < ball).toBe(true)
				expect((at(m3) - at(m1)).Magnitude < ball).toBe(true)

				SB.setFace(handle, "sleepy")
				expect(eye.Size.Y < eye.Size.X * 0.4).toBe(true)
				expect(glint.Size.Magnitude < 0.01).toBe(true)
				expect(at(eyeIndex).Y < eyeY).toBe(true)
				expect(math.abs(at(m2).Y - at(m1).Y) < 0.002 * d).toBe(true) -- bouche droite
				expect(at(m3).X - at(m1).X < smile).toBe(true)

				SB.setFace(handle, "starry")
				expect(eye.Size).toBe(eye0)
				expect(near(glint.Size, glint0 * 1.6)).toBe(true)
				expect(glint.Material).toBe(Enum.Material.Neon)
				expect(at(m2)).toBe(mouth2)

				SB.setFace(handle, "sulky")
				expect(near(eye.Size, Vector3.new(eye0.X, eye0.Y * 0.5, eye0.Z))).toBe(true)
				expect(glint.Size.Magnitude < 0.01).toBe(true)
				expect(glint.Material).toBe(Enum.Material.SmoothPlastic)
				expect(at(m2).Y > at(m1).Y).toBe(true) -- bouche à l'envers : le milieu plus haut

				SB.setFace(handle, "happy")
				expect(eye.Size).toBe(eye0)
				expect(glint.Size).toBe(glint0)
				expect(at(m1)).toBe(mouth1)
				expect(at(m2)).toBe(mouth2)
				expect(at(m3)).toBe(mouth3)
				zeroLog(h)
			end
		)

		it(
			"yeux fermés ou mi-clos de la recette : Surpris les ouvre en rond ; Ravi et Endormi ne les amincissent jamais ; sans reflet, Étoilé agrandit les yeux",
			function()
				local h, SB = load()
				-- Purrpudding (6) : yeux fermés ; Wibble (2) : mi-clos ; Lotlolly (15) : clin d'œil ; aucun reflet
				for _, species in { 6, 2 } do
					local handle = SB.build(spec(species, { stars = 0 }))
					expect(partOf(handle, "Glint1")).toBeNil()
					local eye = partOf(handle, "Eye1")
					local eye0 = eye.Size
					expect(eye0.Y < eye0.X * 0.5).toBe(true)
					SB.setFace(handle, "surprised")
					expect(math.abs(eye.Size.Y - eye0.X * 1.2) < 1e-5).toBe(true)
					expect(math.abs(eye.Size.X - eye0.X * 1.2) < 1e-5).toBe(true)
					for _, face in { "delighted", "sleepy", "sulky" } do
						SB.setFace(handle, face)
						expect({ species, face, eye.Size.Y >= math.min(eye0.Y, 0.05 * 2) - 1e-6 }).toEqual({
							species,
							face,
							true,
						})
					end
					SB.setFace(handle, "starry")
					expect(near(eye.Size, eye0 * 1.15)).toBe(true)
					SB.setFace(handle, "happy")
					expect(eye.Size).toBe(eye0)
				end
				local wink = SB.build(spec(15, { stars = 0 }))
				local open, closed = partOf(wink, "Eye1"), partOf(wink, "Eye2")
				expect(closed.Size.Y < open.Size.Y).toBe(true)
				SB.setFace(wink, "surprised")
				expect(math.abs(closed.Size.Y - open.Size.Y) < 1e-5).toBe(true)
				zeroLog(h)
			end
		)

		it(
			"visage inconnu, valeurs hostiles, Handle rendu : rien, jamais d'erreur ; release() rend « happy » au modèle de la réserve et un modèle repris repart avec « happy »",
			function()
				local h, SB = load()
				local a = SB.build(spec(1, { stars = 0 }))
				local size0, mat0 = {}, {}
				for i, part in a.parts do
					size0[i], mat0[i] = part.Size, part.Material
				end
				SB.setFace(a, "starry")
				for _, bad in { "angry", "", "Happy", 5, 0 / 0, true, {}, nil } do
					local counts = watch(a, function()
						SB.setFace(a, bad)
					end)
					for i in a.parts do
						expect(next(counts[i]) == nil).toBe(true)
					end
					expect(SB.faceOf(a)).toBe("starry")
				end
				expect(SB.faceOf(nil)).toBe("happy")
				expect(SB.faceOf({})).toBe("happy")
				SB.setFace(nil, "starry")
				SB.setFace({}, "starry")
				-- rendu : le modèle de la réserve a déjà son visage de repos
				local parts = table.clone(a.parts)
				SB.release(a)
				expect(SB.faceOf(a)).toBe("happy")
				for i, part in parts do
					expect(part.Size).toBe(size0[i])
					expect(part.Material).toBe(mat0[i])
				end
				-- l'ancien Handle ne touche plus au modèle
				local counts = {}
				local conns = {}
				for i, part in parts do
					table.insert(
						conns,
						part.Changed:Connect(function(prop)
							counts[i] = prop
						end)
					)
				end
				SB.setFace(a, "sulky")
				expect(next(counts)).toBeNil()
				for _, c in conns do
					c:Disconnect()
				end
				-- repris : même modèle, visage « happy », tailles et décalages de la recette
				local b = SB.build(spec(1, { stars = 0 }))
				expect(b.model).toBe(a.model)
				expect(SB.faceOf(b)).toBe("happy")
				local fresh = SB.build(spec(1, { stars = 0 }))
				expect(fresh.model ~= b.model).toBe(true)
				for i, part in b.parts do
					expect(part.Size).toBe(fresh.parts[i].Size)
					expect(part.Material).toBe(fresh.parts[i].Material)
					expect(b.offsets[i]).toBe(fresh.offsets[i])
				end
				zeroLog(h)
			end
		)

		it(
			"sous un visage : setScale garde le visage, setMutation aussi (nouveau jeu de pièces), le niveau de détail ne change aucune taille",
			function()
				local h, SB, _, Mutations = load()
				local handle = SB.build(spec(1, { stars = 0 }))
				local eye = partOf(handle, "Eye1")
				local eye0 = eye.Size
				SB.setFace(handle, "surprised")
				SB.setScale(handle, 3)
				expect(near(eye.Size, eye0 * 1.2 * 3)).toBe(true)
				SB.setFace(handle, "happy")
				expect(near(eye.Size, eye0 * 3)).toBe(true)
				SB.setScale(handle, 1)
				expect(eye.Size).toBe(eye0)
				-- niveau de détail : les reflets cachés par le LOD gardent la taille du visage
				SB.setFace(handle, "starry")
				local glint = partOf(handle, "Glint1")
				local starry = glint.Size
				SB.setLod(handle, 2)
				expect(glint.Transparency).toBe(1)
				expect(glint.Size).toBe(starry)
				SB.setLod(handle, 1)
				expect(glint.Transparency).toBe(0)
				expect(glint.Size).toBe(starry)
				-- chaque mutation : le visage reste, sur les pièces du nouvel aspect
				for m = 1, Mutations.Count do
					SB.setMutation(handle, m, false)
					expect(SB.faceOf(handle)).toBe("starry")
					local pieces = SB._plan(handle.spec)
					local d = 2
					for i, p in pieces do
						if p.role == "glint" then
							expect({ m, near(handle.parts[i].Size, p.size * 1.6 * d) }).toEqual({ m, true })
							expect({ m, handle.parts[i].Material }).toEqual({ m, Enum.Material.Neon })
						elseif p.role == "eye" then
							local alone = true
							for _, q in pieces do
								if q.role == "glint" then
									alone = false
								end
							end
							local f = if alone then 1.15 else 1
							expect({ m, near(handle.parts[i].Size, p.size * f * d) }).toEqual({ m, true })
						end
					end
				end
				SB.setFace(handle, "happy")
				local pieces = SB._plan(handle.spec)
				for i, p in pieces do
					if p.role == "eye" or p.role == "glint" then
						expect(near(handle.parts[i].Size, p.size * 2)).toBe(true)
					end
				end
				zeroLog(h)
			end
		)

		it(
			"clignement : depuis la taille du visage (Surpris), jamais sous un visage qui ferme les yeux (Ravi, Endormi) ; visage posé pendant un clignement : la taille du visage, puis le clignement reprend",
			function()
				local h, SB = load()
				local handle = SB.build(spec(1, { stars = 0 }))
				local eye = partOf(handle, "Eye1")
				local eye0 = eye.Size
				-- t = 0 : début d'un clignement pour toute période ; t = 1 : yeux ouverts
				SB.animate(handle, 0)
				expect(near(eye.Size, Vector3.new(eye0.X, eye0.Y * 0.1, eye0.Z))).toBe(true)
				SB.animate(handle, 1)
				expect(eye.Size).toBe(eye0)
				SB.setFace(handle, "surprised")
				local wide = eye.Size
				SB.animate(handle, 0)
				expect(near(eye.Size, Vector3.new(wide.X, wide.Y * 0.1, wide.Z))).toBe(true)
				SB.animate(handle, 1)
				expect(eye.Size).toBe(wide)
				for _, face in { "delighted", "sleepy" } do
					SB.setFace(handle, face)
					local closed = eye.Size
					local counts = watch(handle, function()
						SB.animate(handle, 0)
						SB.animate(handle, 0.05)
						SB.animate(handle, 1)
					end)
					expect(eye.Size).toBe(closed)
					for i in handle.parts do
						expect({ face, counts[i].Size }).toEqual({ face, nil })
					end
				end
				-- visage posé pendant un clignement
				SB.setFace(handle, "happy")
				SB.animate(handle, 0)
				SB.setFace(handle, "sulky")
				local sulky = Vector3.new(eye0.X, eye0.Y * 0.5, eye0.Z)
				expect(near(eye.Size, sulky)).toBe(true)
				SB.animate(handle, 0.01)
				expect(near(eye.Size, Vector3.new(sulky.X, sulky.Y * 0.1, sulky.Z))).toBe(true)
				SB.animate(handle, 1)
				expect(near(eye.Size, sulky)).toBe(true)
				-- visage fermé posé pendant un clignement : il s'arrête là
				SB.animate(handle, 0)
				SB.setFace(handle, "sleepy")
				local closed = eye.Size
				SB.animate(handle, 0.02)
				expect(eye.Size).toBe(closed)
				SB.setFace(handle, "happy")
				SB.animate(handle, 1)
				expect(eye.Size).toBe(eye0)
				zeroLog(h)
			end
		)
	end)

	describe("SquishyBuilder › étoiles dessinées (lot B5, D11, INT-B1-STARS)", function()
		local function arc(handle)
			return handle.body:FindFirstChild("Stars")
		end

		-- instances de l'arc d'étoiles d'un modèle (l'arc et ce qu'il porte)
		local function arcInstances(handle)
			local gui = arc(handle)
			return if gui then 1 + #gui:GetDescendants() else 0
		end

		it(
			"ni TextLabel, ni TextScaled, ni caractère étoile : 3 Frames dorées par étoile, mêmes places en arc qu'en v1.3",
			function()
				local h, SB = load()
				local handle = SB.build(spec(1, { stars = 5 }))
				local gui = arc(handle)
				expect(gui.ClassName).toBe("BillboardGui")
				expect(gui.MaxDistance).toBe(60)
				expect(gui.Enabled).toBe(true)
				expect(gui.AlwaysOnTop).toBe(false)
				expect(gui.LightInfluence).toBe(0)
				expect(#gui:GetChildren()).toBe(15)
				for _, d in handle.model:GetDescendants() do
					local text = d.ClassName == "TextLabel"
						or d.ClassName == "TextButton"
						or d.ClassName == "TextBox"
					expect({ d.ClassName, text }).toEqual({ d.ClassName, false })
				end
				local angles = {}
				for i = 1, 5 do
					local x = 0.5 + (i - 3) * 0.2
					local y = 0.5 + math.abs(i - 3) * 0.12
					for k = 1, 3 do
						local ray = gui:FindFirstChild("Star" .. i .. "Ray" .. k)
						expect(ray.ClassName).toBe("Frame")
						expect(#ray:GetChildren()).toBe(0)
						expect(ray.Visible).toBe(true)
						expect(ray.BackgroundColor3).toBe(GOLD)
						expect(ray.BorderSizePixel).toBe(0)
						expect(ray.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
						expect(math.abs(ray.Position.X.Scale - x) < 1e-6).toBe(true)
						expect(math.abs(ray.Position.Y.Scale - y) < 1e-6).toBe(true)
						expect(ray.Position.X.Offset).toBe(0)
						-- un trait : long de 86 % du côté de l'étoile (0,2 × la largeur de l'arc), épais de
						-- 22 % ; à l'écran l'arc fait 1,4 D × 0,36 D
						local length = ray.Size.X.Scale * 1.4
						local thickness = ray.Size.Y.Scale * 0.36
						expect(math.abs(length - 0.2 * 1.4 * 0.86) < 1e-5).toBe(true)
						expect(math.abs(thickness - 0.2 * 1.4 * 0.22) < 1e-5).toBe(true)
						-- l'étoile tient dans sa case, avec de l'air entre deux voisines
						expect(length <= 0.9 * 0.2 * 1.4).toBe(true)
						angles[i] = angles[i] or {}
						angles[i][ray.Rotation] = true
					end
					-- 3 traits qui se croisent : 3 directions à 60° l'une de l'autre, une pointe en haut
					expect(angles[i][90] and angles[i][30] and angles[i][150]).toBe(true)
				end
				-- arc : l'étoile du milieu plus haute que celles des bouts
				expect(gui.Star3Ray1.Position.Y.Scale < gui.Star1Ray1.Position.Y.Scale).toBe(true)
				expect(gui.Star1Ray1.Position.Y.Scale).toBe(gui.Star5Ray1.Position.Y.Scale)
				-- le code n'écrit plus aucun texte d'étoile
				local src = fs.readFile("src/shared/Render/SquishyBuilder.luau")
				for _, pattern in
					{
						'Instance%.new%("TextLabel"%)',
						"%.TextScaled",
						"%.Text%s*=",
						"%.FontFace",
						'"[^"\n]*\u{2605}[^"\n]*"',
					}
				do
					expect({ pattern, string.find(src, pattern) }).toEqual({ pattern, nil })
				end
				zeroLog(h)
			end
		)

		it(
			"construites à la première étoile montrée : 0 instance sans étoile, 1 + 3 n pour n étoiles (v1.3 : 11 par modèle), rien de détruit ni de reconstruit ensuite",
			function()
				local h, SB = load()
				local a = SB.build(spec(1, { stars = 0 }))
				expect(arc(a)).toBeNil()
				expect(arcInstances(a)).toBe(0)
				-- sans étoile : chaque fonction marche sans arc
				SB.setLod(a, 2)
				SB.setLod(a, 1)
				SB.setScale(a, 2)
				SB.setScale(a, 1)
				SB.setStars(a, 0)
				expect(arc(a)).toBeNil()
				for n = 1, 5 do
					local b = SB.build(spec(n + 1, { stars = n }))
					expect({ n, arcInstances(b) }).toEqual({ n, 1 + 3 * n })
				end
				SB.setStars(a, 2)
				local gui = arc(a)
				expect(arcInstances(a)).toBe(7)
				expect(gui.Enabled).toBe(true)
				local first = gui.Star1Ray1
				SB.setStars(a, 1)
				expect(arcInstances(a)).toBe(7)
				expect(gui.Star1Ray1.Visible).toBe(true)
				expect(gui.Star2Ray1.Visible).toBe(false)
				SB.setStars(a, 0)
				expect(gui.Enabled).toBe(false)
				expect(gui.Star1Ray1.Visible).toBe(false)
				expect(arcInstances(a)).toBe(7)
				SB.setStars(a, 99)
				expect(arcInstances(a)).toBe(16)
				expect(gui.Star1Ray1).toBe(first)
				expect(arc(a)).toBe(gui)
				-- réserve : le modèle repris sans étoile garde son arc, éteint
				SB.release(a)
				local b = SB.build(spec(1, { stars = 0 }))
				expect(b.model).toBe(a.model)
				expect(arc(b)).toBe(gui)
				expect(gui.Enabled).toBe(false)
				for _, ray in gui:GetChildren() do
					expect(ray.Visible).toBe(false)
				end
				zeroLog(h)
			end
		)

		it(
			"l'arc suit la taille du modèle (1,4 D × 0,36 D au-dessus de la tête), même construit après un changement d'échelle ; détail complet seulement",
			function()
				local h, SB = load()
				local handle = SB.build(spec(1, { stars = 0, displayScale = 3 }))
				SB.setStars(handle, 1)
				local gui = arc(handle)
				local function sized(d)
					local s, o = gui.Size, gui.StudsOffsetWorldSpace
					return math.abs(s.X.Scale - 1.4 * d) < 1e-4
						and math.abs(s.Y.Scale - 0.36 * d) < 1e-4
						and math.abs(o.Y - (d / 2 + 0.32 * d)) < 1e-4
				end
				expect(sized(6)).toBe(true)
				SB.setScale(handle, 1)
				expect(sized(2)).toBe(true)
				SB.setLod(handle, 2)
				expect(gui.Enabled).toBe(false)
				SB.setStars(handle, 4) -- construites hors du détail complet : éteintes
				expect(gui.Enabled).toBe(false)
				expect(#gui:GetChildren()).toBe(12)
				SB.setLod(handle, 1)
				expect(gui.Enabled).toBe(true)
				-- autre aspect (mutation) : nouvel arc à la bonne taille, mêmes étoiles
				SB.setMutation(handle, 2, false)
				local next = arc(handle)
				expect(next ~= gui).toBe(true)
				expect(next.Enabled).toBe(true)
				expect(#next:GetChildren()).toBe(12)
				zeroLog(h)
			end
		)
	end)

	describe("SquishyBuilder › cosmétiques de la v2.0 (lot B5, D12)", function()
		it(
			"4 tenues de la v2.0 : une pièce « Outfit » chacune, pour chaque espèce, différente des autres tenues ; tenue inconnue : aucune pièce, aucune trace",
			function()
				local h, SB, Species = load()
				local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local ids = v2Ids(Cosmetics, "outfit")
				table.sort(ids)
				expect(table.concat(ids, ",")).toBe("buildersCrown,partyHat,polkaBow,starGlasses")
				local sorted = table.clone(OUTFITS_V2)
				table.sort(sorted)
				expect(sorted).toEqual(ids)
				for _, def in Species.List do
					local seen = {}
					for _, outfit in OUTFITS do
						if outfit then
							local found = {}
							for _, p in SB._plan(spec(def.id, { outfit = outfit })) do
								if p.role == "outfit" then
									table.insert(found, p)
								end
							end
							local label = def.key .. " " .. outfit
							expect({ label, #found }).toEqual({ label, 1 })
							expect(found[1].name).toBe("Outfit")
							local dump = RecipeDump.piece(found[1])
							expect({ label, seen[dump] }).toEqual({ label, nil })
							seen[dump] = outfit
							if table.find(OUTFITS_V2, outfit) then
								-- sur la tête : au-dessus des yeux, à moins d'un diamètre du centre
								local p = found[1]
								expect({ label, p.offset.Y > 0.75 * def.body.y }).toEqual({ label, true })
								expect({ label, p.offset.Magnitude < 1.6 }).toEqual({ label, true })
								expect({ label, p.size.X > 0.1 and p.size.Y > 0.1 and p.size.Z > 0.05 }).toEqual({
									label,
									true,
								})
								expect({ label, p.transparency }).toEqual({ label, 0 })
							end
						end
					end
					for _, outfit in OUTFITS_V2 do
						local handle = SB.build(spec(def.id, { outfit = outfit }))
						local part = handle.model:FindFirstChild("Outfit")
						expect({ def.key, outfit, part ~= nil }).toEqual({ def.key, outfit, true })
						expect(part.Transparency).toBe(0)
						expect(#handle.parts <= 12).toBe(true)
						SB.release(handle)
					end
				end
				for _, bad in { "nope", "", "PartyHat", "partyhat", 7, true } do
					for _, p in SB._plan(spec(1, { outfit = bad })) do
						expect(p.role ~= "outfit").toBe(true)
					end
					local handle = SB.build(spec(1, { outfit = bad }))
					expect(handle.model:FindFirstChild("Outfit")).toBeNil()
					SB.release(handle)
				end
				zeroLog(h)
			end
		)

		it(
			"9 selles de la v2.0 : chacune sa couleur sur un modèle construit seul, les mêmes que la table SADDLE_V2 de RanchRenderer ; selles de la v1.3 inchangées ; inconnue : rose par défaut",
			function()
				local h, SB = load()
				local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local DEFAULT = Color3.fromRGB(255, 150, 170)
				local function saddleOf(id)
					local handle = SB.build(spec(1, { saddle = id }))
					local part = handle.model:FindFirstChild("Saddle")
					local color = part.Color
					SB.release(handle)
					return color
				end
				-- table de RanchRenderer (lot B4, D19b), lue dans sa source : Shared ne peut pas la requérir
				local src = fs.readFile("src/client/Controllers/RanchRenderer.luau")
				local block = string.match(src, "local SADDLE_V2: { %[string%]: Color3 } = {(.-)\n}")
				expect(block ~= nil).toBe(true)
				local renderer = {}
				local count = 0
				for id, r, g, b in string.gmatch(block, "(%w+) = Color3%.fromRGB%((%d+), (%d+), (%d+)%)") do
					renderer[id] = Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
					count += 1
				end
				local ids = v2Ids(Cosmetics, "saddle")
				expect(#ids).toBe(9)
				expect(count).toBe(9)
				local seen = {}
				for _, id in ids do
					local color = saddleOf(id)
					expect({ id, color }).toEqual({ id, renderer[id] })
					expect({ id, SB._saddleColor(id) }).toEqual({ id, renderer[id] })
					expect({ id, color ~= DEFAULT }).toEqual({ id, true })
					local key = tostring(color)
					expect({ id, seen[key] }).toEqual({ id, nil })
					seen[key] = id
				end
				for _, def in Cosmetics.List do
					if def.kind == "saddle" then
						expect({ def.id, saddleOf(def.id) }).toEqual({ def.id, def.color or DEFAULT })
					end
				end
				for _, bad in { "nope", "", "Cosmic" } do
					expect({ bad, saddleOf(bad) }).toEqual({ bad, DEFAULT })
				end
				expect(SB._saddleColor(nil)).toBe(DEFAULT)
				expect(SB._saddleColor(5)).toBe(DEFAULT)
				zeroLog(h)
			end
		)
	end)
end
