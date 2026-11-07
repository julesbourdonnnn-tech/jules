--!strict
-- RanchKit (lot B4, étape 3 ; GDD v2.0 §11.5 ; décisions D12, D14, D18, D18b, D26 du plan B4). Pièces
-- primitives des décors v2.0 du ranch, en listes PURES de « specs » (forme, taille, CFrame, couleur,
-- matériau) calculées depuis le repère du ranch (WorldLayout) : Render/RanchV2 les crée, les compare et
-- les anime. Règles des décors v2.0 (GDD §11.5, §12.9) : chaque pièce est ancrée, CanCollide = CanQuery
-- = CanTouch = false, CastShadow = false, Transparency 0 ; matériaux SmoothPlastic, Neon, Foil, Ice ;
-- aucune lumière, aucun Highlight.
--   * tapis(slot, tier, look) : pièces du palier du Tapis posées sur le grand tapis (54 × 32) ;
--   * cushions(slot, n, color, material) : un coussin rond par place d'enclos achetée ;
--   * bed(slot, color) : lit à baldaquin autour du coussin du Meilleur Ami, mobile de 3 lunes ;
--   * plinth(slot, k) : socle de souvenir de la décoration k (disque de vermicelles + icône Neon) ;
--   * pennant(slot, k, color, golden) : fanion ★ d'une décoration gardée ;
--   * heap(slot, state) : tas de pièces du Pot (0 … 3) ; ring(slot, radius) : anneau de l'aimant.
-- Rien n'est créé ici sauf par create ; jamais d'erreur.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local WorldLayout = require(Shared.Logic.WorldLayout)

local RanchKit = {}

export type Shape = "Block" | "Ball" | "Cylinder"
export type Spec = {
	key: string,
	shape: Shape,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	anim: string?, -- animation à 15 Hz (twinkle, orbit, shoot, hop) ; nil = immobile
	phase: number?, -- décalage de l'animation (0 … 1)
	alt: Color3?, -- seconde couleur du scintillement
}

-- Matériaux permis sur une pièce v2.0
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
	Ice = Enum.Material.Ice,
}
-- Matériaux permis sur une pièce du serveur habillée (habillages, Tapis, Pot : Sand en plus)
local PAINT_MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
	Ice = Enum.Material.Ice,
	Sand = Enum.Material.Sand,
}

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- axe d'un Cylinder vers le haut
local MAT_TOP = 0.07 -- dessus du grand tapis du serveur (World/Ranch : snackMatTop)
local MAT_Z = 28 -- centre du tapis (repère local)
local MAT_W, MAT_D = 54, 32
local THIN = 0.1

-- Matériau d'une pièce v2.0 (nom inconnu → SmoothPlastic)
function RanchKit.material(name: string?): Enum.Material
	return if name and MATERIALS[name] then MATERIALS[name] else Enum.Material.SmoothPlastic
end

-- Matériau posé sur une pièce du serveur (habillage) ; nom inconnu → nil (rien à poser)
function RanchKit.paintMaterial(name: string?): Enum.Material?
	return if name then PAINT_MATERIALS[name] else nil
end

-- Couleur éclaircie vers le blanc de `t` (0 … 1)
function RanchKit.lighten(c: Color3, t: number): Color3
	local k = math.clamp(if t == t then t else 0, 0, 1)
	return Color3.new(c.R + (1 - c.R) * k, c.G + (1 - c.G) * k, c.B + (1 - c.B) * k)
end

-- Mélange de deux couleurs
function RanchKit.mix(a: Color3, b: Color3, t: number): Color3
	local k = math.clamp(if t == t then t else 0, 0, 1)
	return Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
end

-- Crée la pièce d'une spec (propriétés fixes des décors v2.0) sous `parent`
function RanchKit.create(spec: Spec, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = spec.key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif spec.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Material = spec.material
	part.Color = spec.color
	part.Size = spec.size
	part.CFrame = spec.cf
	part.Parent = parent
	return part
end

-- Écrit sur `part` seulement ce qui diffère de la spec précédente `prev` (rien si identique)
function RanchKit.apply(part: BasePart, spec: Spec, prev: Spec)
	if spec.size ~= prev.size then
		part.Size = spec.size
	end
	if spec.cf ~= prev.cf then
		part.CFrame = spec.cf
	end
	if spec.color ~= prev.color then
		part.Color = spec.color
	end
	if spec.material ~= prev.material then
		part.Material = spec.material
	end
end

-- Deux specs donnent exactement la même pièce
function RanchKit.same(a: Spec, b: Spec): boolean
	return a.shape == b.shape
		and a.size == b.size
		and a.cf == b.cf
		and a.color == b.color
		and a.material == b.material
		and a.anim == b.anim
		and a.phase == b.phase
		and a.alt == b.alt
end

-- =============================================================================================
-- Formes
-- =============================================================================================

local function L(slot: number, x: number, y: number, z: number): CFrame
	return WorldLayout.ranchCFrame(slot) * CFrame.new(x, y, z)
end

-- Disque à axe vertical : centre de la base en (x, y, z) local, diamètre, épaisseur
local function disc(
	slot: number,
	key: string,
	x: number,
	y: number,
	z: number,
	diameter: number,
	thickness: number,
	color: Color3,
	material: Enum.Material
): Spec
	return {
		key = key,
		shape = "Cylinder",
		size = Vector3.new(thickness, diameter, diameter),
		cf = L(slot, x, y + thickness / 2, z) * UPRIGHT,
		color = color,
		material = material,
	}
end

local function block(
	slot: number,
	key: string,
	x: number,
	y: number,
	z: number,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Spec
	return {
		key = key,
		shape = "Block",
		size = size,
		cf = L(slot, x, y, z),
		color = color,
		material = material,
	}
end

local function ball(
	slot: number,
	key: string,
	x: number,
	y: number,
	z: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Spec
	return {
		key = key,
		shape = "Ball",
		size = Vector3.new(diameter, diameter, diameter),
		cf = L(slot, x, y, z),
		color = color,
		material = material,
	}
end

-- =============================================================================================
-- Tapis (GDD §11.5, tableau des 6 paliers)
-- =============================================================================================

-- 12 points du ciel étoilé (repère local, sur le tapis) : positions fixes, sans hasard
local STARRY: { { number } } = {
	{ -22, 16 },
	{ -13, 22 },
	{ -6, 15 },
	{ 3, 20 },
	{ 12, 14 },
	{ 21, 19 },
	{ -19, 33 },
	{ -9, 39 },
	{ 0, 30 },
	{ 8, 37 },
	{ 17, 31 },
	{ 23, 40 },
}

-- Pièces du palier `tier` (1 … 6) avec l'aspect `look` (RanchLook.tapisLook) ; liste vide sinon
function RanchKit.tapis(slot: number, tier: number, look: any): { Spec }
	local out: { Spec } = {}
	if type(look) ~= "table" then
		return out
	end
	local accents: { Color3 } = look.accents
	local plastic, neon = Enum.Material.SmoothPlastic, Enum.Material.Neon
	if tier == 1 then
		-- Nappe pique-nique : 6 pastilles rouges
		local i = 0
		for _, z in { 20, 36 } do
			for _, x in { -16, 0, 16 } do
				i += 1
				table.insert(out, disc(slot, "picnic" .. i, x, MAT_TOP, z, 3.5, THIN, accents[1], plastic))
			end
		end
	elseif tier == 2 then
		-- Biscuit sablé : 8 trous et un bord dentelé de 12 festons
		local i = 0
		for _, z in { 19, 37 } do
			for _, x in { -19.5, -6.5, 6.5, 19.5 } do
				i += 1
				table.insert(out, disc(slot, "hole" .. i, x, MAT_TOP, z, 2, THIN, accents[1], plastic))
			end
		end
		local j = 0
		for _, z in { MAT_Z - MAT_D / 2, MAT_Z + MAT_D / 2 } do
			for _, x in { -22.5, -13.5, -4.5, 4.5, 13.5, 22.5 } do
				j += 1
				table.insert(
					out,
					disc(slot, "scallop" .. j, x, MAT_TOP - 0.05, z, 3, THIN, accents[2], plastic)
				)
			end
		end
	elseif tier == 3 then
		-- Bonbon arc-en-ciel : 7 bandes Neon pastel en travers du tapis
		local step = MAT_D / 7
		for i = 1, 7 do
			local z = MAT_Z - MAT_D / 2 + step * (i - 0.5)
			table.insert(
				out,
				block(
					slot,
					"band" .. i,
					0,
					MAT_TOP + THIN / 2,
					z,
					Vector3.new(MAT_W, THIN, step * 0.7),
					accents[i] or accents[1],
					neon
				)
			)
		end
	elseif tier == 5 then
		-- Étoilé : 12 points Neon qui scintillent lentement
		for i, p in STARRY do
			local s = ball(slot, "star" .. i, p[1], MAT_TOP + 0.25, p[2], 0.9, accents[1], neon)
			s.anim = "twinkle"
			s.phase = (i - 1) / #STARRY
			s.alt = accents[2]
			table.insert(out, s)
		end
	elseif tier == 6 then
		-- Galaxie : 12 points qui tournent (un tour en 30 s) et 2 étoiles filantes
		for i = 1, 12 do
			local radius = 3 + ((i - 1) % 6) * 2.2
			local angle = (i - 1) * (2 * math.pi / 12) + (if i > 6 then math.pi / 6 else 0)
			local s = ball(
				slot,
				"galaxy" .. i,
				radius * math.cos(angle),
				MAT_TOP + 0.25,
				MAT_Z + radius * math.sin(angle),
				0.9,
				accents[1],
				neon
			)
			s.anim = "orbit"
			s.phase = angle / (2 * math.pi)
			table.insert(out, s)
		end
		for i = 1, 2 do
			local s = block(
				slot,
				"shoot" .. i,
				0,
				MAT_TOP + 0.3,
				MAT_Z,
				Vector3.new(0.3, 0.15, 2.6),
				accents[2],
				neon
			)
			s.anim = "shoot"
			s.phase = (i - 1) * 0.5
			table.insert(out, s)
		end
	end
	return out
end

-- Pièces de chaque palier (budget « tapis »)
local TAPIS_PARTS = { [0] = 0, 6, 20, 7, 0, 12, 14 }
function RanchKit.tapisCount(tier: number): number
	return TAPIS_PARTS[tier] or 0
end

-- Pose animée d'un point de la galaxie, d'un point étoilé ou d'une étoile filante à l'instant t (s)
-- depuis la pose de base `base` (repère du ranch) ; nil = rien à écrire pour cette animation
function RanchKit.orbit(slot: number, base: CFrame, t: number): CFrame
	local center = L(slot, 0, 0, MAT_Z).Position
	local angle = (t / 30) * 2 * math.pi
	local rel = base.Position - center
	local c, s = math.cos(angle), math.sin(angle)
	local p = Vector3.new(rel.X * c - rel.Z * s, rel.Y, rel.X * s + rel.Z * c)
	return CFrame.new(center + p)
end

-- Étoile filante : traverse le tapis en diagonale en 2,5 s, en boucle (phase 0 … 1)
function RanchKit.shoot(slot: number, t: number, phase: number): CFrame
	local u = ((t / 2.5) + phase) % 1
	local x = -MAT_W / 2 + 2 + (MAT_W - 4) * u
	local z = MAT_Z - MAT_D / 2 + 2 + (MAT_D - 4) * (if phase < 0.5 then u else 1 - u)
	local dir = if phase < 0.5
		then Vector3.new(MAT_W - 4, 0, MAT_D - 4)
		else Vector3.new(MAT_W - 4, 0, -(MAT_D - 4))
	local p = L(slot, x, MAT_TOP + 0.3, z).Position
	local worldDir = (L(slot, 0, 0, 0) - L(slot, 0, 0, 0).Position) * dir
	return CFrame.lookAt(p, p + worldDir)
end

-- =============================================================================================
-- Coussins, lit douillet (GDD §11.5)
-- =============================================================================================

-- Un coussin rond (Ø 3,6, 0,8 de haut) par place d'enclos achetée : places Base + 1 … Base + n
function RanchKit.cushions(slot: number, n: number, color: Color3, material: Enum.Material): { Spec }
	local out: { Spec } = {}
	local base = Balance.Pens.Base
	local count = math.clamp(math.floor(if n == n then n else 0), 0, Balance.Pens.Max - base)
	for k = 1, count do
		local p = WorldLayout.toLocal(slot, WorldLayout.penSlot(slot, base + k))
		table.insert(out, disc(slot, "cushion" .. k, p.X, MAT_TOP, p.Z, 3.6, 0.8, color, material))
	end
	return out
end

-- Lit à baldaquin autour du coussin du Meilleur Ami (le coussin du serveur devient le matelas) :
-- 4 colonnes, ciel de lit, tête de lit, mobile (barre + 3 lunes) ; 10 pièces, hors des enclos
function RanchKit.bed(slot: number, color: Color3): { Spec }
	local c = WorldLayout.toLocal(slot, WorldLayout.anchor(slot, "cushion"))
	local out: { Spec } = {}
	local post = Vector3.new(0.35, 5, 0.35)
	local wood = Color3.fromRGB(250, 236, 222)
	local plastic = Enum.Material.SmoothPlastic
	local i = 0
	for _, dz in { -1.8, 1.6 } do
		for _, dx in { -2.2, 2.2 } do
			i += 1
			table.insert(out, block(slot, "bedPost" .. i, c.X + dx, 2.5, c.Z + dz, post, wood, plastic))
		end
	end
	table.insert(out, block(slot, "bedCanopy", c.X, 5.15, c.Z - 0.1, Vector3.new(5, 0.3, 4), color, plastic))
	table.insert(
		out,
		block(
			slot,
			"bedHead",
			c.X,
			1,
			c.Z + 1.6,
			Vector3.new(4.4, 2, 0.3),
			RanchKit.lighten(color, 0.3),
			plastic
		)
	)
	table.insert(
		out,
		block(slot, "bedMobile", c.X, 4.55, c.Z - 0.1, Vector3.new(2.4, 0.12, 0.12), wood, plastic)
	)
	local moon = Color3.fromRGB(255, 240, 170)
	for k, dx in { -1, 0, 1 } do
		table.insert(
			out,
			ball(slot, "bedMoon" .. k, c.X + dx, 3.95, c.Z - 0.1, 0.6, moon, Enum.Material.Neon)
		)
	end
	return out
end

-- =============================================================================================
-- Socles de souvenir, fanions ★ (GDD §11.5)
-- =============================================================================================

-- Couleur de l'icône Neon du socle de la décoration k (une teinte par emplacement)
local function iconColor(k: number): Color3
	return Color3.fromHSV(((k - 1) * 0.137) % 1, 0.45, 1)
end

-- Socle de la décoration k : disque de vermicelles (Ø 2,5) et son icône en Neon (2 pièces)
function RanchKit.plinth(slot: number, k: number): { Spec }
	local cf = WorldLayout.decorSlot(slot, k)
	local p = WorldLayout.toLocal(slot, cf.Position)
	return {
		disc(
			slot,
			"plinth" .. k,
			p.X,
			0,
			p.Z,
			2.5,
			0.5,
			Color3.fromRGB(255, 226, 238),
			Enum.Material.SmoothPlastic
		),
		ball(slot, "plinthIcon" .. k, p.X, 1.05, p.Z, 0.9, iconColor(k), Enum.Material.Neon),
	}
end

-- Fanion ★ de la décoration gardée k : mât et drapeau (2 pièces), à côté de la décoration
function RanchKit.pennant(slot: number, k: number, color: Color3, golden: boolean): { Spec }
	local cf = WorldLayout.decorSlot(slot, k) * CFrame.new(1.9, 0, -1.2)
	local p = WorldLayout.toLocal(slot, cf.Position)
	local flagColor = if golden then Color3.fromRGB(255, 204, 84) else color
	local flagMaterial = if golden then Enum.Material.Foil else Enum.Material.SmoothPlastic
	return {
		block(
			slot,
			"pole" .. k,
			p.X,
			2.75,
			p.Z,
			Vector3.new(0.22, 5.5, 0.22),
			Color3.fromRGB(250, 250, 250),
			Enum.Material.SmoothPlastic
		),
		block(slot, "flag" .. k, p.X + 0.7, 4.9, p.Z, Vector3.new(1.4, 0.9, 0.12), flagColor, flagMaterial),
	}
end

-- =============================================================================================
-- Pot : tas de pièces et anneau de l'aimant (MON ranch, D18)
-- =============================================================================================

local COIN = Color3.fromRGB(255, 208, 70)
local LID_TOP = 4.2 -- dessus du couvercle du Pot (World/Ranch : couvercle à Y 3,5, 1,4 de haut)

-- Tas du Pot à l'état `state` (0 vide, 1 petit, 2 gros, 3 déborde : 3 pièces sautillent)
function RanchKit.heap(slot: number, state: number): { Spec }
	local out: { Spec } = {}
	if state < 1 then
		return out
	end
	local c = WorldLayout.toLocal(slot, WorldLayout.anchor(slot, "pot"))
	local foil = Enum.Material.Foil
	local mound = if state == 1 then 2.2 elseif state == 2 then 3 else 3.6
	table.insert(out, ball(slot, "mound", c.X, LID_TOP - mound * 0.25, c.Z, mound, COIN, foil))
	local coins = if state == 1 then 2 elseif state == 2 then 5 else 4
	for i = 1, coins do
		local a = (i - 1) * (2 * math.pi / coins)
		local r = mound * 0.32
		table.insert(
			out,
			disc(
				slot,
				"coin" .. i,
				c.X + r * math.cos(a),
				LID_TOP + mound * 0.15,
				c.Z + r * math.sin(a),
				0.9,
				0.18,
				COIN,
				foil
			)
		)
	end
	if state >= 3 then
		for i = 1, 3 do
			local a = (i - 1) * (2 * math.pi / 3) + 0.4
			local s = disc(
				slot,
				"hop" .. i,
				c.X + 3.2 * math.cos(a),
				0,
				c.Z + 3.2 * math.sin(a),
				0.9,
				0.18,
				COIN,
				foil
			)
			s.anim = "hop"
			s.phase = (i - 1) / 3
			table.insert(out, s)
		end
	end
	return out
end

-- Pièces du tas par état
local HEAP_PARTS = { [0] = 0, 3, 6, 8 }
function RanchKit.heapCount(state: number): number
	return HEAP_PARTS[state] or 0
end

-- Anneau de l'aimant : 12 points Neon au rayon d'encaissement autour du Pot
RanchKit.RING_DOTS = 12
function RanchKit.ring(slot: number, radius: number): { Spec }
	local out: { Spec } = {}
	local c = WorldLayout.toLocal(slot, WorldLayout.anchor(slot, "pot"))
	for i = 1, RanchKit.RING_DOTS do
		local a = (i - 1) * (2 * math.pi / RanchKit.RING_DOTS)
		table.insert(
			out,
			ball(
				slot,
				"ring" .. i,
				c.X + radius * math.cos(a),
				0.35,
				c.Z + radius * math.sin(a),
				0.6,
				Color3.fromRGB(255, 226, 120),
				Enum.Material.Neon
			)
		)
	end
	return out
end

return RanchKit
