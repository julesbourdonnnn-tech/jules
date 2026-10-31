--!strict
-- Recipes — paquet « world » : recettes visuelles des Nebbies en primitives (GDD §5.2, §4.2, §11.6).
-- Module PUR de données : chaque pièce est décrite en multiples de la taille du corps T (T = 1 ici,
-- NebbyBuilder met à l'échelle). Repère du Nebby : avant = −Z (LookVector), haut = +Y.
-- Les dimensions et couleurs ci-dessous sont des constantes graphiques internes à la recette
-- (tolérées par le contrat, docs/04-architecture.md §1.5) ; les nombres de gameplay restent dans
-- Config/*.

local Recipes = {}

export type Shape = "Ball" | "Block" | "Cylinder" | "Wedge" | "CornerWedge" | "Eye"
-- Rôle de couleur résolu par NebbyBuilder selon l'espèce, la forme et les variantes
export type ColorRole =
	"body"
	| "accent"
	| "eye"
	| "cheek"
	| "crater"
	| "crown"
	| "rarity"
	| "shell"
	| "bubble"
export type AnimMode = "static" | "puff" | "sway" | "flap" | "spin" | "bounce" | "tail"

export type PartSpec = {
	name: string,
	shape: Shape,
	size: Vector3, -- × T
	cframe: CFrame, -- position × T, relative au centre du corps
	color: ColorRole,
	neon: boolean?, -- toujours en Néon (halo, antenne, couronne)
	material: Enum.Material?, -- matériau imposé (ForceField)
	anim: AnimMode,
	pivot: Vector3?, -- pivot de rotation (sway, flap), × T
	amp: number?, -- radians (sway, flap), fraction (puff), × T (bounce, tail)
	freq: number?, -- Hz ; pour "spin" : tours par seconde
	sign: number?, -- miroir gauche / droite (flap)
	phase: number?, -- décalage propre à la pièce (radians)
	trail: boolean?, -- porte un Trail en détail complet (queue de Comète)
}

local HALF_PI = math.pi / 2
local VERTICAL = CFrame.Angles(0, 0, HALF_PI) -- l'axe X d'un Cylinder devient vertical

-- Couleurs internes de la recette (GDD §5.2)
Recipes.CheekColor = Color3.fromRGB(255, 160, 190)
Recipes.EyeColor = Color3.fromRGB(24, 20, 34)
Recipes.EyeReflectance = 0.3
Recipes.CrownGold = Color3.fromRGB(255, 205, 60)
Recipes.CrownGoldBlend = 0.6 -- part d'or mélangée à la couleur d'accent (couronnes « dorées »)
Recipes.CraterShade = 0.8 -- cratères Moon : couleur du corps × 0,8
Recipes.BubbleColor = Color3.fromRGB(255, 215, 90)
Recipes.MaxParts = 8 -- pièces au plus en détail complet (GDD §5.2, §12.8)

local function spec(
	name: string,
	shape: Shape,
	size: Vector3,
	cframe: CFrame,
	color: ColorRole,
	anim: AnimMode?,
	extra: { [string]: any }?
): PartSpec
	local s: PartSpec = {
		name = name,
		shape = shape,
		size = size,
		cframe = cframe,
		color = color,
		anim = anim or "static",
	}
	if extra then
		for k, v in extra do
			(s :: any)[k] = v
		end
	end
	return s
end

-- Pièces de base : corps, 2 yeux, 2 joues --------------------------------------------------------

function Recipes.body(): PartSpec
	return spec("Body", "Ball", Vector3.one, CFrame.identity, "body")
end

function Recipes.eyes(): { PartSpec }
	local size = Vector3.new(0.28, 0.28, 0.28)
	return {
		spec("EyeL", "Eye", size, CFrame.new(-0.22, 0.12, -0.42), "eye"),
		spec("EyeR", "Eye", size, CFrame.new(0.22, 0.12, -0.42), "eye"),
	}
end

-- Disque plat posé sur la surface du corps, axe X le long de la normale
local function onSurface(pos: Vector3): CFrame
	local normal = pos.Unit
	return CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, HALF_PI, 0)
end

function Recipes.cheeks(): { PartSpec }
	local size = Vector3.new(0.03, 0.2, 0.2)
	return {
		spec("CheekL", "Cylinder", size, onSurface(Vector3.new(-0.32, -0.08, -0.38)), "cheek"),
		spec("CheekR", "Cylinder", size, onSurface(Vector3.new(0.32, -0.08, -0.38)), "cheek"),
	}
end

-- Accents par archétype : `limit` pièces au plus, les plus lisibles d'abord ----------------------

local function puff(limit: number): { PartSpec }
	local size = Vector3.new(0.45, 0.45, 0.45)
	local extra = { amp = 0.05, freq = 0.8 }
	if limit >= 3 then
		return {
			spec("Puff1", "Ball", size, CFrame.new(0, 0.5, 0.04), "accent", "puff", extra),
			spec("Puff2", "Ball", size, CFrame.new(-0.2, 0.41, 0.1), "accent", "puff", extra),
			spec("Puff3", "Ball", size, CFrame.new(0.2, 0.41, 0.1), "accent", "puff", extra),
		}
	elseif limit == 2 then
		return {
			spec("Puff1", "Ball", size, CFrame.new(-0.14, 0.46, 0.06), "accent", "puff", extra),
			spec("Puff2", "Ball", size, CFrame.new(0.14, 0.46, 0.06), "accent", "puff", extra),
		}
	end
	return { spec("Puff1", "Ball", size, CFrame.new(0, 0.5, 0.04), "accent", "puff", extra) }
end

local function sprout(limit: number): { PartSpec }
	local sway = { pivot = Vector3.new(0, 0.48, 0), amp = math.rad(10), freq = 0.9 }
	local out = {
		spec(
			"Stem",
			"Cylinder",
			Vector3.new(0.4, 0.08, 0.08),
			CFrame.new(0, 0.66, 0) * VERTICAL,
			"accent",
			"sway",
			sway
		),
		spec(
			"LeafL",
			"Wedge",
			Vector3.new(0.03, 0.14, 0.26),
			CFrame.new(-0.1, 0.86, 0) * CFrame.Angles(0, -HALF_PI, 0) * CFrame.Angles(math.rad(-25), 0, 0),
			"accent",
			"sway",
			sway
		),
		spec(
			"LeafR",
			"Wedge",
			Vector3.new(0.03, 0.14, 0.26),
			CFrame.new(0.1, 0.86, 0) * CFrame.Angles(0, HALF_PI, 0) * CFrame.Angles(math.rad(-25), 0, 0),
			"accent",
			"sway",
			sway
		),
	}
	while #out > limit do
		table.remove(out)
	end
	return out
end

local function horn(_limit: number): { PartSpec }
	return {
		spec(
			"Horn",
			"CornerWedge",
			Vector3.new(0.3, 0.4, 0.3),
			CFrame.new(0, 0.5, -0.16) * CFrame.Angles(0, math.rad(135), 0),
			"accent"
		),
	}
end

local function wing(limit: number): { PartSpec }
	local size = Vector3.new(0.05, 0.3, 0.42)
	local out = {
		spec(
			"WingL",
			"Wedge",
			size,
			CFrame.new(-0.52, 0.12, 0.08) * CFrame.Angles(0, 0, math.rad(20)),
			"accent",
			"flap",
			{ pivot = Vector3.new(-0.42, 0.12, 0.08), amp = math.rad(25), freq = 6, sign = 1 }
		),
		spec(
			"WingR",
			"Wedge",
			size,
			CFrame.new(0.52, 0.12, 0.08) * CFrame.Angles(0, 0, math.rad(-20)),
			"accent",
			"flap",
			{ pivot = Vector3.new(0.42, 0.12, 0.08), amp = math.rad(25), freq = 6, sign = -1 }
		),
	}
	while #out > limit do
		table.remove(out)
	end
	return out
end

local function ring(_limit: number): { PartSpec }
	return {
		spec(
			"Halo",
			"Cylinder",
			Vector3.new(0.06, 1.1, 1.1),
			CFrame.new(0, 0.78, 0) * CFrame.Angles(math.rad(12), 0, 0) * VERTICAL,
			"accent",
			"spin",
			{ neon = true, freq = 1 / 3 }
		),
	}
end

local function twin(_limit: number): { PartSpec }
	return {
		spec(
			"Twin",
			"Ball",
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(0.55, -0.12, 0.12),
			"accent",
			"bounce",
			{ amp = 0.08, freq = 1.6, phase = HALF_PI }
		),
	}
end

local function spike(limit: number): { PartSpec }
	local size = Vector3.new(0.05, 0.22, 0.24)
	local out = {
		spec(
			"Spike1",
			"Wedge",
			size,
			CFrame.new(0, 0.44, 0.2) * CFrame.Angles(math.rad(-25), 0, 0),
			"accent"
		),
		spec(
			"Spike2",
			"Wedge",
			size,
			CFrame.new(0, 0.22, 0.42) * CFrame.Angles(math.rad(-60), 0, 0),
			"accent"
		),
		spec(
			"Spike3",
			"Wedge",
			size,
			CFrame.new(0, -0.06, 0.48) * CFrame.Angles(math.rad(-95), 0, 0),
			"accent"
		),
	}
	while #out > limit do
		table.remove(out)
	end
	return out
end

local function moon(limit: number): { PartSpec }
	local size = Vector3.new(0.3, 0.3, 0.3)
	local out = {
		spec("Crater1", "Ball", size, CFrame.new(-0.3, 0.3, -0.16), "crater"),
		spec("Crater2", "Ball", size, CFrame.new(0.38, -0.1, -0.08), "crater"),
	}
	while #out > limit do
		table.remove(out)
	end
	return out
end

local function crown(limit: number): { PartSpec }
	local size = Vector3.new(0.06, 0.22, 0.12)
	local out = {
		spec("Crown1", "Wedge", size, CFrame.new(0, 0.58, 0) * CFrame.Angles(0, HALF_PI, 0), "crown"),
		spec(
			"Crown2",
			"Wedge",
			size,
			CFrame.new(-0.16, 0.53, 0.02) * CFrame.Angles(0, 0, math.rad(20)) * CFrame.Angles(0, HALF_PI, 0),
			"crown"
		),
		spec(
			"Crown3",
			"Wedge",
			size,
			CFrame.new(0.16, 0.53, 0.02) * CFrame.Angles(0, 0, math.rad(-20)) * CFrame.Angles(0, HALF_PI, 0),
			"crown"
		),
	}
	while #out > limit do
		table.remove(out)
	end
	return out
end

local function comet(_limit: number): { PartSpec }
	return {
		spec(
			"Tail",
			"Ball",
			Vector3.new(0.5, 0.5, 0.5),
			CFrame.new(0, 0.05, 0.62),
			"accent",
			"tail",
			{ amp = 0.12, freq = 1.2, trail = true }
		),
	}
end

local ARCHETYPES: { [string]: { natural: number, build: (number) -> { PartSpec } } } = {
	Puff = { natural = 3, build = puff },
	Sprout = { natural = 3, build = sprout },
	Horn = { natural = 1, build = horn },
	Wing = { natural = 2, build = wing },
	Ring = { natural = 1, build = ring },
	Twin = { natural = 1, build = twin },
	Spike = { natural = 3, build = spike },
	Moon = { natural = 2, build = moon },
	Crown = { natural = 3, build = crown },
	Comet = { natural = 1, build = comet },
}
Recipes.ARCHETYPES = ARCHETYPES

Recipes.MaxAccentParts = 3
Recipes.PrimaryComboParts = 2 -- Légendaires : 2 pièces au plus pour le 1er archétype, le reste au 2e

-- Pièces d'accent d'une espèce (1 ou 2 archétypes, ≤ 3 pièces)
function Recipes.accents(archetypes: { string }): { PartSpec }
	local out: { PartSpec } = {}
	if #archetypes == 0 then
		return out
	end
	local first = ARCHETYPES[archetypes[1]]
	local second = if archetypes[2] then ARCHETYPES[archetypes[2]] else nil
	if first and second then
		local limitA = math.min(first.natural, Recipes.PrimaryComboParts)
		local limitB = math.min(second.natural, Recipes.MaxAccentParts - limitA)
		for _, p in first.build(limitA) do
			table.insert(out, p)
		end
		for _, p in second.build(limitB) do
			table.insert(out, p)
		end
	elseif first then
		for _, p in first.build(math.min(first.natural, Recipes.MaxAccentParts)) do
			table.insert(out, p)
		end
	elseif second then
		for _, p in second.build(math.min(second.natural, Recipes.MaxAccentParts)) do
			table.insert(out, p)
		end
	end
	return out
end

-- Auras de rareté qui demandent des pièces ----------------------------------------------------

-- Peu commun : petite antenne Néon (bulbe lumineux au-dessus de la tête)
function Recipes.antenna(): PartSpec
	return spec(
		"Antenna",
		"Ball",
		Vector3.new(0.16, 0.16, 0.16),
		CFrame.new(0.24, 0.66, -0.06),
		"accent",
		"bounce",
		{ neon = true, amp = 0.04, freq = 2 }
	)
end

-- Mythique : couronne de `count` petites boules Néon qui tourne lentement
function Recipes.crownBalls(count: number): { PartSpec }
	local out = {}
	local n = math.clamp(count, 0, 3)
	for i = 1, n do
		local angle = (i - 1) * (2 * math.pi / 3)
		local pos = Vector3.new(math.cos(angle) * 0.24, 0.84, math.sin(angle) * 0.24)
		table.insert(
			out,
			spec(
				"CrownOrb" .. i,
				"Ball",
				Vector3.new(0.16, 0.16, 0.16),
				CFrame.new(pos),
				"rarity",
				"spin",
				{ neon = true, freq = 0.25 }
			)
		)
	end
	return out
end

-- Cosmique : coque ForceField qui cycle en HSV
function Recipes.shell(): PartSpec
	return spec("Shell", "Ball", Vector3.new(1.18, 1.18, 1.18), CFrame.identity, "shell", "static", {
		material = Enum.Material.ForceField,
	})
end

-- Bouclier débutant : bulle dorée ForceField de 1,3 T (GDD §9.4)
function Recipes.bubble(): PartSpec
	return spec("Bubble", "Ball", Vector3.new(1.3, 1.3, 1.3), CFrame.identity, "bubble", "static", {
		material = Enum.Material.ForceField,
	})
end

return Recipes
