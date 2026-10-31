--!nocheck
-- NebbyBuilder (paquet world) : recettes en primitives, niveaux de détail, auras, formes,
-- variantes, animations, BulkMoveTo, Gloomwisp et Comète (GDD §5.2, §4.2, §4.4, §9.3, §11.6, §12.8).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new({ mode = "client" })
		local NB = h:require("ReplicatedStorage.Shared.Render.NebbyBuilder")
		local Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		return h, NB, Nebbies, h.globals
	end

	local function partsOf(model)
		local out = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function find(rig, name)
		for _, p in rig.parts do
			if p.Name == name then
				return p
			end
		end
		return nil
	end

	local function descendantOfClass(model, className)
		for _, d in model:GetDescendants() do
			if d.ClassName == className then
				return d
			end
		end
		return nil
	end

	describe("NebbyBuilder › recettes", function()
		it(
			"chaque espèce × forme × variantes : ≤ 8 pièces ancrées, sans collision, modèle non parenté",
			function()
				local _, NB, Nebbies = setup()
				for s = 1, Nebbies.SPECIES_COUNT do
					for f = 0, Nebbies.FORM_COUNT - 1 do
						for v = 0, 7 do
							local code = Nebbies.pack(s, f, v)
							for _, opts in
								{ nil, { highlight = true, light = true, trail = true, rookieBubble = true } }
							do
								local rig = NB.build(code, 1, "full", opts)
								local count = #rig.parts
								expect({ code = code, ok = count >= 3 and count <= 8 }).toEqual({
									code = code,
									ok = true,
								})
								expect(rig.model.Parent).toBeNil()
								expect(rig.parts[1]).toBe(rig.body)
								expect(#rig.offsets).toBe(count)
								expect(#rig.pose).toBe(count)
								expect(#partsOf(rig.model)).toBe(count)
								for _, p in rig.parts do
									expect({
										name = p.Name,
										anchored = p.Anchored,
										collide = p.CanCollide,
										query = p.CanQuery,
										touch = p.CanTouch,
										shadow = p.CastShadow,
									}).toEqual({
										name = p.Name,
										anchored = true,
										collide = false,
										query = false,
										touch = false,
										shadow = false,
									})
								end
								if opts == nil then
									expect(NB.partCount(code, "full")).toBe(count)
								end
								NB.destroy(rig)
							end
						end
					end
				end
			end
		)

		it("corps de taille T (rareté) et Huge × 2", function()
			local _, NB, Nebbies = setup()
			for s, def in Nebbies.Species do
				local size = Nebbies.Rarities[def.rarity].size
				expect(NB.bodySize(Nebbies.pack(s, 0, 0))).toBeNear(size)
				expect(NB.bodySize(Nebbies.pack(s, 0, Nebbies.Variants.huge.bit))).toBeNear(size * 2)
				local rig = NB.build(Nebbies.pack(s, 0, Nebbies.Variants.huge.bit), 1, "full")
				expect(rig.size).toBeNear(size * 2)
				expect(rig.body.Size.X).toBeNear(size * 2)
				expect(rig.body.Shape.Name).toBe("Ball")
			end
		end)

		it("yeux (2, maillage sphère, Reflectance 0,3) placés à (±0,22 ; 0,12 ; −0,42) T", function()
			local _, NB, Nebbies = setup()
			local code = Nebbies.pack(1, 0, 0)
			local rig = NB.build(code, 1, "full")
			local t = rig.size
			local left, right = find(rig, "EyeL"), find(rig, "EyeR")
			expect(left ~= nil and right ~= nil).toBe(true)
			expect(left.Position.X).toBeNear(-0.22 * t, 1e-4)
			expect(left.Position.Y).toBeNear(0.12 * t, 1e-4)
			expect(left.Position.Z).toBeNear(-0.42 * t, 1e-4)
			expect(right.Position.X).toBeNear(0.22 * t, 1e-4)
			expect(left.Size.X).toBeNear(0.28 * t, 1e-4)
			expect(left.Reflectance).toBeNear(0.3)
			expect(left:FindFirstChildOfClass("SpecialMesh") ~= nil).toBe(true)
			expect(#rig.eyes).toBe(2)
		end)

		it("Puffkin : 3 bouffées couleur d'accent + 2 joues roses (8 pièces)", function()
			local _, NB, Nebbies, g = setup()
			local rig = NB.build(Nebbies.pack(Nebbies.Named.Welcome, 0, 0), 1, "full")
			expect(#rig.parts).toBe(8)
			expect(find(rig, "Puff1").Color).toEqual(Nebbies.Species[1].accent)
			expect(find(rig, "CheekL") ~= nil and find(rig, "CheekR") ~= nil).toBe(true)
			expect(find(rig, "CheekL").Color).toEqual(g.Color3.fromRGB(255, 160, 190))
		end)

		it("Légendaires : deux archétypes et au plus 3 pièces d'accent", function()
			local _, NB, Nebbies = setup()
			local nova = NB.build(Nebbies.pack(Nebbies.byKey.nova_nimbus, 0, 0), 1, "full")
			expect(find(nova, "Halo") ~= nil).toBe(true)
			local puffs = 0
			for _, p in nova.parts do
				if string.sub(p.Name, 1, 4) == "Puff" then
					puffs += 1
				end
			end
			expect(puffs).toBe(2)
			local owlet = NB.build(Nebbies.pack(Nebbies.byKey.eclipse_owlet, 0, 0), 1, "full")
			expect(
				find(owlet, "WingL") ~= nil and find(owlet, "WingR") ~= nil and find(owlet, "Crater1") ~= nil
			).toBe(true)
			local wyrm = NB.build(Nebbies.pack(Nebbies.byKey.sunwyrm, 0, 0), 1, "full")
			expect(find(wyrm, "Spike1") ~= nil and find(wyrm, "Crown1") ~= nil).toBe(true)
			for _, rig in { nova, owlet, wyrm } do
				local accents = 0
				for _, p in rig.parts do
					local n = p.Name
					if n ~= "Body" and n ~= "EyeL" and n ~= "EyeR" and n ~= "CheekL" and n ~= "CheekR" then
						accents += 1
					end
				end
				expect(accents).toBeLessThanOrEqual(3)
			end
		end)
	end)

	describe("NebbyBuilder › raretés lisibles sans couleur (auras)", function()
		it("Peu commun : antenne Néon ; Rare : Sparkles ; Épique : particules en orbite", function()
			local _, NB, Nebbies = setup()
			local ringlet = NB.build(Nebbies.pack(Nebbies.byKey.ringlet, 0, 0), 1, "full")
			local antenna = find(ringlet, "Antenna")
			expect(antenna ~= nil).toBe(true)
			expect(antenna.Material.Name).toBe("Neon")
			local rare = NB.build(Nebbies.pack(Nebbies.byKey.prismpaw, 0, 0), 1, "full")
			expect(descendantOfClass(rare.model, "Sparkles") ~= nil).toBe(true)
			local epic = NB.build(Nebbies.pack(Nebbies.byKey.starhorn, 0, 0), 1, "full")
			expect(epic.orbit ~= nil).toBe(true)
			expect(epic.orbit:FindFirstChildOfClass("ParticleEmitter") ~= nil).toBe(true)
			-- Graphismes légers : débit des particules × 0,3
			local low =
				NB.build(Nebbies.pack(Nebbies.byKey.starhorn, 0, 0), 1, "full", { particleMult = 0.3 })
			local full = epic.orbit:FindFirstChildOfClass("ParticleEmitter").Rate
			expect(low.orbit:FindFirstChildOfClass("ParticleEmitter").Rate).toBeNear(full * 0.3, 1e-6)
		end)

		it(
			"Légendaire : Trail (sauf trail = false) et PointLight seulement si l'appelant le budgète",
			function()
				local _, NB, Nebbies = setup()
				local code = Nebbies.pack(Nebbies.byKey.sunwyrm, 0, 0)
				local plain = NB.build(code, 1, "full")
				expect(descendantOfClass(plain.model, "Trail") ~= nil).toBe(true)
				expect(descendantOfClass(plain.model, "PointLight")).toBeNil()
				local lit = NB.build(code, 1, "full", { light = true, trail = false })
				expect(descendantOfClass(lit.model, "PointLight") ~= nil).toBe(true)
				expect(descendantOfClass(lit.model, "Trail")).toBeNil()
			end
		)

		it("Mythique : couronne de boules Néon, Highlight seulement sur demande", function()
			local _, NB, Nebbies = setup()
			local code = Nebbies.pack(Nebbies.byKey.chronomoth, 0, 0)
			local rig = NB.build(code, 1, "full")
			expect(find(rig, "CrownOrb1") ~= nil).toBe(true)
			expect(descendantOfClass(rig.model, "Highlight")).toBeNil()
			local hl = NB.build(code, 1, "full", { highlight = true })
			local highlight = descendantOfClass(hl.model, "Highlight")
			expect(highlight ~= nil).toBe(true)
			expect(highlight.Adornee).toBe(hl.model)
		end)

		it("Cosmique : coque ForceField et corps qui cycle en HSV", function()
			local _, NB, Nebbies = setup()
			local code = Nebbies.pack(Nebbies.Named.Cosmic, 0, 0)
			local rig = NB.build(code, 1, "full")
			local shell = find(rig, "Shell")
			expect(shell ~= nil).toBe(true)
			expect(shell.Material.Name).toBe("ForceField")
			expect(NB.bodyColor(code, 0) ~= NB.bodyColor(code, 1)).toBe(true)
			local before = rig.body.Color
			NB.animate(rig, { t = 1.3, phase = 0, blink = false, speed = 0 })
			expect(rig.body.Color ~= before).toBe(true)
		end)

		it("aura = false : aucune instance d'aura", function()
			local _, NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(Nebbies.byKey.prismpaw, 0, 0), 1, "full", { aura = false })
			expect(descendantOfClass(rig.model, "Sparkles")).toBeNil()
			local un = NB.build(Nebbies.pack(Nebbies.byKey.ringlet, 0, 0), 1, "full", { aura = false })
			expect(find(un, "Antenna")).toBeNil()
		end)
	end)

	describe("NebbyBuilder › formes, variantes, étoiles", function()
		it("formes : matériaux et couleurs de Config/Nebbies.Forms", function()
			local _, NB, Nebbies = setup()
			local s = 1
			local rarity = Nebbies.Rarities[1]
			expect(NB.bodyColor(Nebbies.pack(s, 0, 0))).toEqual(rarity.color)
			expect(NB.bodyColor(Nebbies.pack(s, 3, 0))).toEqual(Nebbies.Forms[3].bodyColor)
			expect(NB.bodyColor(Nebbies.pack(s, 4, 0))).toEqual(Nebbies.Forms[4].bodyColor)
			local frozen = NB.bodyColor(Nebbies.pack(s, 2, 0))
			expect(frozen ~= rarity.color).toBe(true)
			local ice = NB.build(Nebbies.pack(s, 2, 0), 1, "full")
			expect(ice.body.Material.Name).toBe("Ice")
			local blazing = NB.build(Nebbies.pack(s, 3, 0), 1, "full")
			local fire = blazing.body:FindFirstChildOfClass("Fire")
			expect(fire ~= nil).toBe(true)
			expect(fire.Size).toBeNear(Nebbies.Forms[3].fire)
			local eclipse = NB.build(Nebbies.pack(s, 4, 0), 1, "full")
			expect(find(eclipse, "EyeL").Material.Name).toBe("Neon")
			expect(find(eclipse, "EyeL").Color).toEqual(Nebbies.Forms[4].eyeColor)
			local aurora = NB.build(Nebbies.pack(s, 1, 0), 1, "full")
			expect(find(aurora, "Puff1").Material.Name).toBe("Neon")
			expect(find(aurora, "Puff1").Color).toEqual(Nebbies.Forms[1].accentColors[1])
			expect(find(aurora, "Puff2").Color).toEqual(Nebbies.Forms[1].accentColors[2])
			local prism = NB.build(Nebbies.pack(s, 5, 0), 1, "full")
			expect(prism.body.Material.Name).toBe("Glass")
			expect(NB.bodyColor(Nebbies.pack(s, 5, 0), 0) ~= NB.bodyColor(Nebbies.pack(s, 5, 0), 2)).toBe(
				true
			)
		end)

		it("Golden : or et Foil ; Starborn : halo de 5 branches Néon (Beams, aucune pièce)", function()
			local _, NB, Nebbies = setup()
			local golden = NB.build(Nebbies.pack(2, 0, Nebbies.Variants.golden.bit), 1, "full")
			expect(golden.body.Color).toEqual(Nebbies.Variants.golden.color)
			expect(golden.body.Material.Name).toBe("Foil")
			local plain = NB.build(Nebbies.pack(2, 0, 0), 1, "full")
			local star = NB.build(Nebbies.pack(2, 0, Nebbies.Variants.starborn.bit), 1, "full")
			expect(#star.parts).toBe(#plain.parts)
			local beams = 0
			for _, d in star.model:GetDescendants() do
				if d.ClassName == "Beam" then
					beams += 1
				end
			end
			expect(beams).toBe(5)
		end)

		it("étoiles : ★2+ affichées de près, rien pour ★1, bornes 1-5", function()
			local _, NB, Nebbies = setup()
			local one = NB.build(Nebbies.pack(1, 0, 0), 1, "full")
			expect(one.body:FindFirstChild("Stars")).toBeNil()
			local three = NB.build(Nebbies.pack(1, 0, 0), 3, "full")
			local gui = three.body:FindFirstChild("Stars")
			expect(gui ~= nil).toBe(true)
			expect(gui.Text.Text).toBe("★★★")
			expect(gui.MaxDistance).toBeLessThanOrEqual(50)
			expect(NB.build(Nebbies.pack(1, 0, 0), 99, "full").stars).toBe(5)
			expect(NB.build(Nebbies.pack(1, 0, 0), 0 / 0, "full").stars).toBe(1)
			expect(NB.build(Nebbies.pack(1, 0, 0), -3, "full").stars).toBe(1)
		end)

		it("bulle dorée du bouclier débutant (ForceField 1,3 T) sans dépasser 8 pièces", function()
			local _, NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(1, 0, 0), 1, "full", { rookieBubble = true })
			local bubble = find(rig, "Bubble")
			expect(bubble ~= nil).toBe(true)
			expect(bubble.Material.Name).toBe("ForceField")
			expect(bubble.Size.X).toBeNear(1.3 * rig.size, 1e-4)
			expect(#rig.parts).toBeLessThanOrEqual(8)
		end)

		it("codes et paramètres invalides : repli Puffkin, jamais d'erreur", function()
			local _, NB, Nebbies = setup()
			local welcome = Nebbies.pack(Nebbies.Named.Welcome, 0, 0)
			for _, bad in { 0 / 0, -1, 4096, 1.5, math.huge, "12", nil, {}, 0 } do
				local rig = NB.build(bad, 1, "full")
				expect(rig.code).toBe(welcome)
				expect(#rig.parts).toBe(NB.partCount(welcome, "full"))
				expect(NB.bodySize(bad)).toBeNear(Nebbies.Rarities[1].size)
			end
			local rig = NB.build(welcome, 1, "nonsense")
			expect(rig.lod).toBe("full")
		end)
	end)

	describe("NebbyBuilder › niveaux de détail", function()
		it("ball : une seule Ball couleur du corps, Néon si Mythique+ ; hidden : aucune pièce", function()
			local _, NB, Nebbies = setup()
			local common = NB.build(Nebbies.pack(1, 0, 0), 1, "ball")
			expect(#common.parts).toBe(1)
			expect(common.body.Shape.Name).toBe("Ball")
			expect(common.body.Material.Name).toBe("SmoothPlastic")
			local mythic = NB.build(Nebbies.pack(Nebbies.byKey.prismara, 0, 0), 1, "ball")
			expect(mythic.body.Material.Name).toBe("Neon")
			local hidden = NB.build(Nebbies.pack(1, 0, 0), 1, "hidden")
			expect(#hidden.parts).toBe(0)
			expect(#partsOf(hidden.model)).toBe(0)
			expect(hidden.body ~= nil).toBe(true)
			expect(NB.partCount(Nebbies.pack(1, 0, 0), "ball")).toBe(1)
			expect(NB.partCount(Nebbies.pack(1, 0, 0), "hidden")).toBe(0)
		end)

		it("setLod garde la table et le modèle, réduit puis reconstruit", function()
			local h, NB, Nebbies = setup()
			local code = Nebbies.pack(Nebbies.byKey.chronomoth, 5, 3)
			local rig = NB.build(code, 4, "full", { highlight = true })
			rig.model.Parent = h.workspace
			local model = rig.model
			local full = #rig.parts
			local same = NB.setLod(rig, "ball")
			expect(same).toBe(rig)
			expect(rig.model).toBe(model)
			expect(rig.lod).toBe("ball")
			expect(#rig.parts).toBe(1)
			expect(#partsOf(model)).toBe(1)
			expect(descendantOfClass(model, "Highlight")).toBeNil()
			NB.setLod(rig, "hidden")
			expect(#partsOf(model)).toBe(0)
			NB.setLod(rig, "full")
			expect(#rig.parts).toBe(full)
			expect(descendantOfClass(model, "Highlight") ~= nil).toBe(true)
			expect(rig.stars).toBe(4)
			expect(model.Parent).toBe(h.workspace)
			NB.setLod(rig, "full") -- même niveau : rien ne change
			expect(#partsOf(model)).toBe(full)
		end)

		it("budget §12.8 : 100 Nebbies en détail complet ≤ 800 pièces", function()
			local _, NB, Nebbies = setup()
			local total = 0
			for i = 1, 100 do
				local s = (i - 1) % Nebbies.SPECIES_COUNT + 1
				total += NB.partCount(Nebbies.pack(s, i % 6, i % 8), "full")
			end
			expect(total).toBeLessThanOrEqual(800)
		end)
	end)

	describe("NebbyBuilder › animation et BulkMoveTo", function()
		it("animate : ailes qui battent, halo qui tourne, pièces statiques fixes", function()
			local _, NB, Nebbies = setup()
			local glimbug = NB.build(Nebbies.pack(Nebbies.byKey.glimbug, 0, 0), 1, "full")
			local wingIndex
			for i, p in glimbug.parts do
				if p.Name == "WingL" then
					wingIndex = i
				end
			end
			NB.animate(glimbug, { t = 0, phase = 0, blink = false, speed = 0 })
			local a = glimbug.pose[wingIndex]
			NB.animate(glimbug, { t = 1 / 24, phase = 0, blink = false, speed = 0 })
			local b = glimbug.pose[wingIndex]
			expect((a.LookVector - b.LookVector).Magnitude + (a.Position - b.Position).Magnitude).toBeGreaterThan(
				1e-3
			)
			-- le corps et les yeux ne bougent pas relativement au corps
			expect(glimbug.pose[1]).toEqual(glimbug.offsets[1])
			local ringlet = NB.build(Nebbies.pack(Nebbies.byKey.ringlet, 0, 0), 1, "full")
			local haloIndex
			for i, p in ringlet.parts do
				if p.Name == "Halo" then
					haloIndex = i
				end
			end
			NB.animate(ringlet, { t = 0.75, phase = 0, blink = false, speed = 0 })
			expect((ringlet.pose[haloIndex].LookVector - ringlet.offsets[haloIndex].LookVector).Magnitude).toBeGreaterThan(
				0.1
			)
		end)

		it("clignement : yeux à Y × 0,1 puis réouverts", function()
			local _, NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(1, 0, 0), 1, "full")
			NB.animate(rig, { t = 1, phase = 0, blink = true, speed = 0 })
			for _, mesh in rig.eyes do
				expect(mesh.Scale.Y).toBeNear(0.1)
			end
			NB.animate(rig, { t = 1.1, phase = 0, blink = false, speed = 0 })
			for _, mesh in rig.eyes do
				expect(mesh.Scale.Y).toBeNear(1)
			end
		end)

		it("orbite Épique : l'attachement tourne autour du corps", function()
			local _, NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(Nebbies.byKey.starhorn, 0, 0), 1, "full")
			NB.animate(rig, { t = 0, phase = 0, blink = false, speed = 0 })
			local p0 = rig.orbit.CFrame.Position
			NB.animate(rig, { t = 0.5, phase = 0, blink = false, speed = 0 })
			local p1 = rig.orbit.CFrame.Position
			expect((p1 - p0).Magnitude).toBeGreaterThan(0.5)
			expect(p1.Magnitude).toBeNear(p0.Magnitude, 1e-3)
		end)

		it("appendCFrames : root × pose ajoutés en fin de liste, un seul BulkMoveTo", function()
			local h, NB, Nebbies, g = setup()
			local a = NB.build(Nebbies.pack(1, 0, 0), 1, "full")
			local b = NB.build(Nebbies.pack(Nebbies.byKey.cometcub, 0, 0), 1, "ball")
			a.model.Parent = h.workspace
			b.model.Parent = h.workspace
			local parts, cframes = {}, {}
			local rootA = g.CFrame.new(10, 2, 5) * g.CFrame.Angles(0, 1, 0)
			local rootB = g.CFrame.new(-4, 1, 0)
			NB.appendCFrames(a, rootA, parts, cframes)
			NB.appendCFrames(b, rootB, parts, cframes)
			expect(#parts).toBe(#a.parts + #b.parts)
			expect(#cframes).toBe(#parts)
			h.workspace:BulkMoveTo(parts, cframes, g.Enum.BulkMoveMode.FireCFrameChanged)
			expect((a.body.Position - rootA.Position).Magnitude).toBeLessThan(1e-4)
			local eye = find(a, "EyeL")
			expect((eye.Position - (rootA * a.pose[2]).Position).Magnitude).toBeLessThan(1e-4)
			expect((b.body.Position - rootB.Position).Magnitude).toBeLessThan(1e-4)
			local hidden = NB.build(Nebbies.pack(1, 0, 0), 1, "hidden")
			NB.appendCFrames(hidden, rootA, parts, cframes)
			expect(#parts).toBe(#a.parts + #b.parts)
		end)

		it("animate et appendCFrames sur un rig masqué ou détruit : sans effet ni erreur", function()
			local _, NB, Nebbies, g = setup()
			local rig = NB.build(Nebbies.pack(1, 0, 0), 1, "full")
			local model = rig.model
			NB.destroy(rig)
			expect(#rig.parts).toBe(0)
			expect(#model:GetChildren()).toBe(0)
			NB.animate(rig, { t = 1, phase = 0, blink = true, speed = 0 })
			local parts, cframes = {}, {}
			NB.appendCFrames(rig, g.CFrame.new(), parts, cframes)
			expect(#parts).toBe(0)
			NB.setLod(rig, "full") -- rig détruit : rien n'est reconstruit
			expect(#rig.parts).toBe(0)
			NB.destroy(rig) -- deux fois : sans erreur
		end)
	end)

	describe("NebbyBuilder › Gloomwisp et Grande Comète", function()
		it("Gloomwisp : Ball indigo 2,4 + 3 bouffées + 2 yeux Néon ovales + Trail violet", function()
			local _, NB, _, g = setup()
			local rig = NB.buildWisp()
			expect(#rig.parts).toBe(6)
			expect(rig.body.Size.X).toBeNear(2.4)
			expect(rig.body.Color).toEqual(g.Color3.fromRGB(45, 35, 80))
			expect(find(rig, "EyeL").Material.Name).toBe("Neon")
			expect(#rig.eyes).toBe(2)
			expect(descendantOfClass(rig.model, "Trail") ~= nil).toBe(true)
			NB.animate(rig, { t = 0.13, phase = 0, blink = false, speed = 7 })
			expect(rig.model.Parent).toBeNil()
			expect(NB.setLod(rig, "ball")).toBe(rig) -- recette fixe
			expect(#rig.parts).toBe(6)
		end)

		it(
			"orbe au sol (3 studs, anneau doré qui tourne) et comète du ciel (Ball Néon 6 + Fire + Trail + Sparkles)",
			function()
				local _, NB = setup()
				local orb = NB.buildCometOrb()
				expect(orb.body.Size.X).toBeNear(3)
				expect(orb.body.Material.Name).toBe("Neon")
				expect(find(orb, "Ring") ~= nil).toBe(true)
				expect(descendantOfClass(orb.model, "PointLight") ~= nil).toBe(true)
				NB.animate(orb, { t = 0.5, phase = 0, blink = false, speed = 0 })
				expect(orb.pose[2] ~= orb.offsets[2]).toBe(true)
				local sky = NB.buildCometSky()
				expect(sky.PrimaryPart ~= nil).toBe(true)
				expect(sky.PrimaryPart.Size.X).toBeNear(6)
				local fire = descendantOfClass(sky, "Fire")
				expect(fire.Size).toBeNear(10)
				expect(fire.Heat).toBeNear(15)
				expect(descendantOfClass(sky, "Trail") ~= nil).toBe(true)
				expect(descendantOfClass(sky, "Sparkles") ~= nil).toBe(true)
				expect(sky.Parent).toBeNil()
			end
		)
	end)
end
