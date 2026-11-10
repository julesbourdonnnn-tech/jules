--!strict
-- SquishyBuilder (paquet world, docs/04 §12.2). Modèles de squishies en formes simples, construits
-- côté client à partir d'une ligne de Config/Species et de 4 nombres (GDD §5.2) : corps écrasable,
-- haut de tête (oreilles, collerette…), yeux (reflet blanc), joues, bouche en sourire, motif,
-- 9 aspects de mutation (Config/Mutations.look), arc d'étoiles (BillboardGui sous 60 studs), aura de
-- rareté (couleur ET forme, Config/Rarities), selle et tenue, points d'attache (selle, tenue, tête).
--   * 12 pièces au plus en détail complet (GDD §5.2, §12.9) : les pièces sont choisies par priorité
--     (corps, yeux, selle, tenue, cœur de la mutation, haut de tête, bouche, détails de la mutation,
--     joues, motif, reflets) ; une paire (oreilles, joues) est entière ou absente ; la bouche se
--     réduit à une pièce s'il ne reste qu'une place. LOD 2 : corps + yeux ; LOD 3 : corps seul.
--   * Toutes les pièces : ancrées, CanCollide = CanQuery = CanTouch = false, CastShadow = false (un
--     squishy n'est jamais un objet physique ; le clic de souris le désigne par projection, §10.4).
--     Transparence seulement pour la mutation Gelée. Le corps est un bloc + SpecialMesh Sphere (une
--     Part Ball reste toujours ronde) : setSquash n'écrit que body.Size ; les autres pièces suivent
--     par pose() + workspace:BulkMoveTo (une fois par image pour tous les squishies, par le renderer).
--   * Réserve : release() rend le modèle à une réserve par aspect (espèce, mutation, tenue, selle,
--     aura) ; build() en reprend un. Aucune création en rafale ; un Handle rendu ne fait plus rien.
--   * Repère du modèle : origine au CENTRE DU DESSOUS du corps (posé au sol), visage vers −Z
--     (LookVector) ; D = diamètre en studs = Balance.SizeScale.BaseDiameter × displayScale.
-- v2.0 (lot B5, étape 1 ; plan B5 D5, D6, D11, D12 ; GDD §5.6, §10.8 règle 18) :
--   * yeux « bébé » : taille et hauteur des yeux lues dans Config/Visuals.Eyes[Visuals.EyeChoice] à
--     chaque recette ; la version A donne EXACTEMENT les recettes de la v1.3 (témoin
--     tests/fixtures/squishy-recipes/v13.txt) ; B et C ne changent que les yeux et leurs reflets ;
--   * visages : setFace(handle, face) (Visuals.Faces) écrit les tailles des yeux et des reflets UNE
--     fois par changement (reflets en Neon pour « starry »), déplace la bouche et les yeux par leur
--     décalage (CFrame) seulement, jamais une animation de Size ; release() et un modèle repris dans
--     la réserve rendent « happy » ; visage inconnu : rien ;
--   * étoiles DESSINÉES (INT-B1-STARS) : plus de TextLabel « ★ » ni de TextScaled (« ★ » n'est dans
--     aucune police du jeu) ; chaque étoile = 3 traits dorés qui se croisent (3 Frames), construits à
--     la première fois qu'un modèle la montre (setStars) ; même arc, même or, mêmes règles de
--     visibilité (détail complet, 60 studs) ; dans les deux états des interrupteurs ;
--   * tenues de la v2.0 (partyHat, starGlasses, buildersCrown, polkaBow) : UNE pièce chacune ;
--     couleurs des 9 selles de la v2.0 (les mêmes que RanchRenderer) pour un modèle construit seul.
-- Dépendances : Config/{Species, Mutations, Rarities, Cosmetics, Balance, Visuals} seulement.

local Config = script.Parent.Parent.Config
local Species = require(Config.Species)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)
local Cosmetics = require(Config.Cosmetics)
local Balance = require(Config.Balance)
local Visuals = require(Config.Visuals)

export type BuildSpec = {
	species: number,
	mutation: number,
	stars: number,
	displayScale: number,
	lod: number,
	outfit: string?,
	saddle: string?, -- couleur de selle (monture)
	rarityAura: boolean?, -- aura de rareté visible
}

export type Handle = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
	spec: BuildSpec,
	lod: number,
}

export type Attachments = { saddle: CFrame, outfit: CFrame, head: CFrame }

-- Pièce d'une recette (pure) : tailles et positions en × D (diamètre du corps), positions depuis le
-- centre du dessous, visage vers −Z
export type Piece = {
	name: string,
	role: string, -- "body" | "eye" | "glint" | "cheek" | "mouth" | "top" | "pattern" | "saddle" | "outfit" | "mutation" | "extra"
	shape: string, -- "sphere" (bloc + SpecialMesh) | "ball" | "cylinder" | "block" | "wedge"
	size: Vector3,
	offset: Vector3,
	rot: CFrame,
	color: Color3,
	material: string,
	reflectance: number,
	transparency: number,
	lod: number, -- visible aux niveaux de détail ≤ lod (corps 3, yeux 2, le reste 1)
	orbit: { radius: number, height: number, period: number, phase: number }?,
}

local SquishyBuilder = {}

local MAX_PARTS = 12
SquishyBuilder.MAX_PARTS = MAX_PARTS
SquishyBuilder.STARS_MAX = 5
SquishyBuilder.STARS_DISTANCE = 60 -- studs : arc d'étoiles visible en dessous (GDD §5.2)
SquishyBuilder.POOL_PER_LOOK = 48 -- modèles gardés en réserve par aspect
SquishyBuilder.POOL_TOTAL = 400

local BASE_D = Balance.SizeScale.BaseDiameter

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Couleurs fixes (GDD §5.2)
local EYE = rgb(20, 18, 30)
local WHITE = rgb(255, 255, 255)
local CHEEK = rgb(255, 160, 190)
local MOUTH = rgb(90, 50, 50)
local LIGHT = rgb(255, 242, 214)
local ACCENT = rgb(255, 130, 180)
local CAPE = rgb(200, 40, 60)
local GOLD = rgb(255, 205, 60)
local NONE = CFrame.new()

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Orientation dont l'axe X (axe d'un cylindre Roblox) suit la direction `n`
local function alongX(n: Vector3): CFrame
	if n.Magnitude < 1e-6 then
		return NONE
	end
	local look = CFrame.lookAt(Vector3.zero, n.Unit)
	return (look * CFrame.Angles(0, math.pi / 2, 0)).Rotation
end

-- =============================================================================================
-- Recettes (pures)
-- =============================================================================================

type Body = { x: number, y: number, z: number }

-- Point de la surface du corps dans la direction (u, v, w) (sphère unité étirée), depuis le dessous
local function surface(b: Body, u: number, v: number, w: number, push: number?): Vector3
	local d = Vector3.new(u, v, w)
	d = if d.Magnitude > 0 then d.Unit else Vector3.new(0, 1, 0)
	local k = 0.5 * (push or 1)
	return Vector3.new(d.X * b.x * k, b.y * 0.5 + d.Y * b.y * k, d.Z * b.z * k)
end

-- Normale (approchée) de la surface dans la direction (u, v, w)
local function normal(b: Body, u: number, v: number, w: number): Vector3
	local n = Vector3.new(u / math.max(b.x, 1e-3), v / math.max(b.y, 1e-3), w / math.max(b.z, 1e-3))
	return if n.Magnitude > 0 then n.Unit else Vector3.new(0, 0, -1)
end

local function piece(
	name: string,
	role: string,
	shape: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	opts: {
		rot: CFrame?,
		material: string?,
		reflectance: number?,
		lod: number?,
		transparency: number?,
	}?
): Piece
	local o = opts or {}
	return {
		name = name,
		role = role,
		shape = shape,
		size = size,
		offset = offset,
		rot = o.rot or NONE,
		color = color,
		material = o.material or "SmoothPlastic",
		reflectance = o.reflectance or 0,
		transparency = o.transparency or 0,
		lod = o.lod or 1,
		orbit = nil,
	}
end

-- Yeux « bébé » (GDD §5.6, test M14 ; lot B5, D5) : version choisie de Config/Visuals, lue à chaque
-- recette. Rend (taille de l'œil courant, facteur de taille des autres yeux et des reflets, hauteur).
-- Version A (0,22 ; 0,12) : facteur exactement 1 et hauteur 0,12, soit les recettes de la v1.3 au
-- flottant près (2 × 0,12 == 0,24, la direction de la v1.3) ; version absente ou abîmée : A.
local EYE_SIZE_A = 0.22
local EYE_HEIGHT_A = 0.12
local function eyeVersion(): (number, number, number)
	local version: any = (Visuals.Eyes :: any)[Visuals.EyeChoice]
	if type(version) == "table" then
		local size, height = version.size, version.height
		if
			type(size) == "number"
			and type(height) == "number"
			and size == size
			and height == height
			and size >= 0.1
			and size <= 0.4
			and height >= -0.1
			and height <= 0.3
		then
			return size, size / EYE_SIZE_A, height
		end
	end
	return EYE_SIZE_A, 1, EYE_HEIGHT_A
end

-- Yeux (2, ou 3 pour Moonplop) et reflets selon le type d'yeux de la ligne
local function eyePieces(b: Body, eyes: string, top: string): ({ Piece }, { Piece })
	local list: { Piece } = {}
	local glints: { Piece } = {}
	local bulgy = eyes == "bulgy" or eyes == "bulgyWink" or string.sub(top, 1, 7) == "bugEyes"
	-- k : facteur des yeux de la version (1 pour A) ; les yeux sur le dessus de la tête (grenouilles)
	-- gardent leur place, signe de leur famille : seule leur taille suit la version
	local size, k, height = eyeVersion()
	if eyes == "bigShiny" then
		size = 0.26 * k
	elseif eyes == "dots" then
		size = 0.14 * k
	elseif bulgy then
		size = 0.2 * k
	end
	local color = if eyes == "hearts" then rgb(255, 90, 140) else EYE
	local glintColor = if eyes == "stars" then GOLD else WHITE
	local glintMaterial = if eyes == "stars" or eyes == "sparkle" then "Neon" else "SmoothPlastic"
	local glintSize = (if eyes == "sparkle" or eyes == "stars" then 0.09 else 0.07) * k
	for i, side in { -1, 1 } do
		local pos: Vector3
		if bulgy then
			pos = surface(b, side * 0.38, 0.85, -0.25, 1.15) + Vector3.new(0, 0.02, -0.12 * b.z)
		else
			pos = surface(b, side * 0.4, 2 * height, -0.88, 0.97)
		end
		local closed = eyes == "happyClosed" or (side > 0 and (eyes == "wink" or eyes == "bulgyWink"))
		local s = Vector3.new(size, size, size * 0.65)
		if closed then
			s = Vector3.new(size, 0.05, size * 0.5)
		elseif eyes == "sleepy" then
			s = Vector3.new(size, size * 0.42, size * 0.55)
		end
		table.insert(list, piece("Eye" .. i, "eye", "sphere", s, pos, color, { reflectance = 0.3, lod = 2 }))
		if not closed and eyes ~= "sleepy" and eyes ~= "dots" then
			table.insert(
				glints,
				piece(
					"Glint" .. i,
					"glint",
					"ball",
					Vector3.new(glintSize, glintSize, glintSize),
					pos + Vector3.new(0.04 * k, 0.05 * k, -size * 0.32),
					glintColor,
					{ material = glintMaterial }
				)
			)
		end
	end
	if eyes == "threeEyes" then
		table.insert(
			list,
			piece(
				"Eye3",
				"eye",
				"sphere",
				Vector3.new(0.13 * k, 0.13 * k, 0.09 * k),
				surface(b, 0, 0.5, -0.86, 0.98),
				color,
				{ reflectance = 0.3, lod = 2 }
			)
		)
	end
	return list, glints
end

-- Joues (2) et bouche (3 petites boules en sourire)
local function facePieces(b: Body): ({ Piece }, { Piece })
	local cheeks: { Piece } = {}
	for i, side in { -1, 1 } do
		local u, v, w = side * 0.62, -0.05, -0.78
		table.insert(
			cheeks,
			piece(
				"Cheek" .. i,
				"cheek",
				"cylinder",
				Vector3.new(0.03, 0.18, 0.18),
				surface(b, u, v, w, 0.99),
				CHEEK,
				{ rot = alongX(normal(b, u, v, w)) }
			)
		)
	end
	local mouth: { Piece } = {}
	for i, d in { { -0.1, -0.1 }, { 0, -0.15 }, { 0.1, -0.1 } } do
		table.insert(
			mouth,
			piece(
				"Mouth" .. i,
				"mouth",
				"ball",
				Vector3.new(0.045, 0.045, 0.045),
				surface(b, d[1], d[2], -0.99, 1.0),
				MOUTH
			)
		)
	end
	return cheeks, mouth
end

-- Hauts de tête (Config/Species.top) : 1 à 3 pièces
local function topPieces(b: Body, top: string, main: Color3, second: Color3): { Piece }
	local out: { Piece } = {}
	local function add(
		name: string,
		shape: string,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		rot: CFrame?,
		material: string?
	)
		table.insert(out, piece(name, "top", shape, size, offset, color, { rot = rot, material = material }))
	end
	local crown = surface(b, 0, 1, 0)
	local function ears(color: Color3, tall: boolean)
		for i, side in { -1, 1 } do
			if tall then
				add(
					"Ear" .. i,
					"sphere",
					Vector3.new(0.15, 0.45, 0.1),
					surface(b, side * 0.35, 0.92, 0) + Vector3.new(0, 0.15, 0),
					color,
					deg(0, 0, -side * 10)
				)
			else
				add(
					"Ear" .. i,
					"wedge",
					Vector3.new(0.12, 0.26, 0.22),
					surface(b, side * 0.55, 0.83, 0) + Vector3.new(0, 0.08, 0),
					color,
					deg(0, 90, -side * 15)
				)
			end
		end
	end
	local function bumps()
		for i, side in { -1, 1 } do
			add(
				"Bump" .. i,
				"sphere",
				Vector3.new(0.34, 0.3, 0.34),
				surface(b, side * 0.38, 0.85, -0.25),
				main
			)
		end
	end
	if top == "dropAntenna" then
		add("Drop", "sphere", Vector3.new(0.2, 0.28, 0.2), crown + Vector3.new(0, 0.1, 0), main)
	elseif top == "caramelCap" then
		add("Cap", "sphere", Vector3.new(0.8 * b.x, 0.32, 0.8 * b.z), crown - Vector3.new(0, 0.08, 0), second)
	elseif top == "leaf" then
		add(
			"Leaf",
			"sphere",
			Vector3.new(0.34, 0.06, 0.18),
			crown + Vector3.new(0.05, 0.03, 0),
			second,
			deg(0, 20, 20)
		)
	elseif top == "tinyCrown" then
		add(
			"Crown",
			"cylinder",
			Vector3.new(0.12, 0.26, 0.26),
			crown + Vector3.new(0, 0.05, 0),
			second,
			deg(0, 0, 90)
		)
		add(
			"Gem",
			"ball",
			Vector3.new(0.08, 0.08, 0.08),
			crown + Vector3.new(0, 0.14, -0.1),
			ACCENT,
			nil,
			"Neon"
		)
	elseif top == "catEars" then
		ears(main, false)
	elseif top == "catEarsWhiskers" then
		ears(main, false)
		add(
			"Whiskers",
			"cylinder",
			Vector3.new(0.9 * b.x + 0.2, 0.03, 0.03),
			surface(b, 0, 0, -1, 1.02) + Vector3.new(0, -0.02, 0),
			second
		)
	elseif top == "catEarsFlowers" then
		ears(main, false)
		add("Flowers", "cylinder", Vector3.new(0.08, 0.55 * b.x, 0.55 * b.z), crown, ACCENT, deg(0, 0, 90))
	elseif top == "bugEyes" then
		bumps()
	elseif top == "bugEyesLily" then
		bumps()
		add(
			"Lily",
			"cylinder",
			Vector3.new(0.04, 0.6, 0.6),
			crown + Vector3.new(0.08, 0.1, 0.12),
			second,
			deg(0, 0, 80)
		)
	elseif top == "bugEyesSpring" then
		bumps()
		add(
			"Spring",
			"cylinder",
			Vector3.new(0.16, 0.34, 0.34),
			Vector3.new(0, 0.04, 0),
			second,
			deg(0, 0, 90)
		)
	elseif top == "frill" or top == "bubbleFrill" then
		for i, side in { -1, 1 } do
			if top == "frill" then
				add(
					"Frill" .. i,
					"sphere",
					Vector3.new(0.12, 0.34, 0.26),
					surface(b, side * 0.92, 0.35, 0.05, 1.05),
					second,
					deg(0, 0, -side * 20)
				)
			else
				add(
					"Bubble" .. i,
					"ball",
					Vector3.new(0.2, 0.2, 0.2),
					surface(b, side * 0.85, 0.45, 0, 1.08),
					second
				)
			end
		end
	elseif top == "coralCrown" then
		for i, x in { -0.15, 0, 0.15 } do
			add(
				"Coral" .. i,
				"cylinder",
				Vector3.new(0.22 - math.abs(x) * 0.4, 0.08, 0.08),
				crown + Vector3.new(x, 0.08, if x == 0 then 0.04 else 0),
				second,
				deg(0, 0, 90 - x * 120)
			)
		end
	elseif top == "floppyEars" then
		for i, side in { -1, 1 } do
			add(
				"Ear" .. i,
				"sphere",
				Vector3.new(0.16, 0.42, 0.12),
				surface(b, side * 0.62, 0.62, 0) + Vector3.new(side * 0.06, -0.05, 0),
				main,
				deg(0, 0, side * 60)
			)
		end
	elseif top == "oddEars" then
		add(
			"Ear1",
			"sphere",
			Vector3.new(0.15, 0.45, 0.1),
			surface(b, -0.35, 0.92, 0) + Vector3.new(0, 0.15, 0),
			main,
			deg(0, 0, 10)
		)
		add(
			"Ear2",
			"sphere",
			Vector3.new(0.15, 0.42, 0.1),
			surface(b, 0.62, 0.62, 0) + Vector3.new(0.06, -0.05, 0),
			main,
			deg(0, 0, -60)
		)
	elseif top == "earsClover" then
		ears(main, true)
		add(
			"Clover",
			"ball",
			Vector3.new(0.16, 0.16, 0.16),
			surface(b, 0, 1, -0.2) + Vector3.new(0, 0.05, 0),
			second
		)
	elseif top == "crescentEars" then
		ears(second, true)
	elseif top == "softBumps" then
		for i, d in { { 0, 0.98, 0.15 }, { 0, 0.85, 0.5 }, { 0, 0.6, 0.78 } } do
			add(
				"Bump" .. i,
				"sphere",
				Vector3.new(0.18, 0.16, 0.18),
				surface(b, d[1], d[2], d[3], 1.02),
				second
			)
		end
	elseif top == "softSpikes" then
		for i, d in { { -0.35, 0.85, 0.35 }, { 0, 0.95, 0.25 }, { 0.35, 0.85, 0.35 } } do
			add(
				"Spike" .. i,
				"sphere",
				Vector3.new(0.12, 0.26, 0.12),
				surface(b, d[1], d[2], d[3], 1.05),
				second,
				deg(-20, 0, -d[1] * 50)
			)
		end
	elseif top == "wingsHorns" then
		for i, side in { -1, 1 } do
			add(
				"Wing" .. i,
				"wedge",
				Vector3.new(0.06, 0.22, 0.3),
				surface(b, side * 0.75, 0.45, 0.5, 1.05),
				second,
				deg(0, side * 30, 0)
			)
		end
		add("Horn", "sphere", Vector3.new(0.1, 0.18, 0.1), crown + Vector3.new(0, 0.06, -0.05), second)
	elseif top == "flameCrest" then
		for i, d in { { -0.4, 0.14, 0.3 }, { 0, 0.12, 0.24 }, { 0.4, 0.1, 0.18 } } do
			add(
				"Flame" .. i,
				"sphere",
				Vector3.new(d[2], d[3], d[2] * 0.7),
				surface(b, 0, 0.92, d[1]) + Vector3.new(0, d[3] * 0.35, 0),
				second,
				deg(d[1] * -40, 0, 0)
			)
		end
	elseif top == "crownCape" then
		add(
			"Crown",
			"cylinder",
			Vector3.new(0.14, 0.3, 0.3),
			crown + Vector3.new(0, 0.05, 0),
			second,
			deg(0, 0, 90)
		)
		add("Cape", "block", Vector3.new(0.75 * b.x, 0.55 * b.y, 0.04), surface(b, 0, 0.1, 1, 1.03), CAPE)
	elseif top == "crescentAntenna" then
		add("Stalk", "sphere", Vector3.new(0.06, 0.2, 0.06), crown + Vector3.new(0, 0.08, 0), main)
		add(
			"Crescent",
			"sphere",
			Vector3.new(0.22, 0.1, 0.05),
			crown + Vector3.new(0, 0.2, 0),
			second,
			deg(0, 0, 25),
			"Neon"
		)
	end
	return out
end

-- Motifs (Config/Species.pattern) : 0 à 4 pièces, couleur secondaire
local function patternPieces(b: Body, pattern: string, count: number, second: Color3): ({ Piece }, boolean)
	local out: { Piece } = {}
	local paired = false
	local function add(
		name: string,
		shape: string,
		size: Vector3,
		offset: Vector3,
		color: Color3?,
		rot: CFrame?,
		material: string?
	)
		table.insert(
			out,
			piece(name, "pattern", shape, size, offset, color or second, { rot = rot, material = material })
		)
	end
	local function spots(dirs: { { number } }, shape: string, size: number, color: Color3?, material: string?)
		for i, d in dirs do
			if i > math.max(1, count) then
				break
			end
			local n = normal(b, d[1], d[2], d[3])
			local s = if shape == "cylinder"
				then Vector3.new(0.02, size, size)
				else Vector3.new(size, size, size)
			local rot = if shape == "cylinder"
				then alongX(n)
				elseif shape == "block" then deg(0, 0, 45)
				else nil
			add("Spot" .. i, shape, s, surface(b, d[1], d[2], d[3], 1.0), color, rot, material)
		end
	end
	local belly = surface(b, 0, -0.25, -0.97, 0.93)
	if
		pattern == "lightBelly"
		or pattern == "creamBelly"
		or pattern == "goldBelly"
		or pattern == "lightScales"
	then
		add("Belly", "sphere", Vector3.new(0.55 * b.x, 0.5 * b.y, 0.18), belly)
	elseif pattern == "cloverBelly" or pattern == "lollipopSpiral" then
		add(
			"Belly",
			"cylinder",
			Vector3.new(0.03, 0.34, 0.34),
			surface(b, 0, -0.2, -0.98, 1.0),
			nil,
			alongX(normal(b, 0, -0.2, -0.98))
		)
	elseif pattern == "cap" then
		add(
			"Drip",
			"cylinder",
			Vector3.new(0.06, 0.9 * b.x, 0.9 * b.z),
			Vector3.new(0, b.y * 0.82, 0),
			nil,
			deg(0, 0, 90)
		)
	elseif pattern == "seeds" then
		spots(
			{ { -0.85, 0.1, 0.5 }, { 0.85, 0.1, 0.5 }, { -0.6, -0.4, 0.7 }, { 0.6, -0.4, 0.7 } },
			"sphere",
			0.07,
			LIGHT
		)
	elseif pattern == "layers" then
		for i, y in { 0.35, 0.65 } do
			local r = math.sqrt(math.max(0, 1 - (2 * y - 1) ^ 2))
			add(
				"Layer" .. i,
				"cylinder",
				Vector3.new(0.08, 1.02 * b.x * r, 1.02 * b.z * r),
				Vector3.new(0, b.y * y, 0),
				if i == 1 then second else LIGHT,
				deg(0, 0, 90)
			)
		end
	elseif pattern == "innerEars" then
		paired = true
		for i, side in { -1, 1 } do
			add(
				"InnerEar" .. i,
				"wedge",
				Vector3.new(0.04, 0.15, 0.12),
				surface(b, side * 0.55, 0.83, 0) + Vector3.new(0, 0.08, -0.05),
				nil,
				deg(0, 90, -side * 15)
			)
		end
	elseif pattern == "tigerStripes" then
		for i, d in { { 0, 0.9, 0.3 }, { 0, 0.7, 0.65 }, { 0, 0.4, 0.88 } } do
			if i > count then
				break
			end
			add("Stripe" .. i, "sphere", Vector3.new(0.5 * b.x, 0.05, 0.1), surface(b, d[1], d[2], d[3], 1.0))
		end
	elseif pattern == "spiralTail" then
		add("Tail", "sphere", Vector3.new(0.16, 0.16, 0.28), surface(b, 0, -0.3, 1, 1.05))
	elseif pattern == "petals" then
		for i, d in { { -0.3, 0.9, -0.2 }, { 0.3, 0.9, -0.2 }, { 0, 0.95, 0.25 } } do
			add(
				"Petal" .. i,
				"sphere",
				Vector3.new(0.1, 0.03, 0.1),
				surface(b, d[1], d[2], d[3], 1.02),
				ACCENT
			)
		end
	elseif pattern == "pondSpots" or pattern == "orangeSpots" then
		spots(
			{ { -0.7, 0.4, 0.4 }, { 0.7, 0.4, 0.4 }, { -0.5, -0.3, 0.75 }, { 0.5, -0.3, 0.75 } },
			"cylinder",
			0.14
		)
	elseif pattern == "starSpots" then
		spots({ { -0.7, 0.4, 0.4 }, { 0.7, 0.4, 0.4 }, { 0, 0.7, 0.7 } }, "block", 0.08, nil, "Neon")
	elseif pattern == "bubbles" then
		spots({ { -0.95, 0.6, 0.1 }, { 0.95, 0.6, 0.1 }, { 0.7, 0.9, 0 } }, "ball", 0.1)
	elseif pattern == "reefBumps" then
		spots({ { -0.4, 0.8, 0.4 }, { 0.4, 0.8, 0.4 }, { 0, 0.6, 0.8 }, { 0, 0.95, 0.2 } }, "sphere", 0.1)
	elseif pattern == "pinkNose" then
		add("Nose", "ball", Vector3.new(0.07, 0.07, 0.07), surface(b, 0, 0.02, -1, 1.01))
	elseif pattern == "whiteSocks" then
		paired = true
		for i, side in { -1, 1 } do
			add(
				"Sock" .. i,
				"sphere",
				Vector3.new(0.2, 0.08, 0.2),
				Vector3.new(side * 0.25 * b.x, 0.03, -0.3 * b.z)
			)
		end
	elseif pattern == "starSpeckles" then
		spots(
			{ { -0.5, 0.8, 0.3 }, { 0.5, 0.8, 0.3 }, { 0, 0.5, 0.85 }, { -0.8, 0.2, 0.5 } },
			"ball",
			0.05,
			nil,
			"Neon"
		)
	elseif pattern == "goldDrop" then
		add(
			"GoldDrop",
			"sphere",
			Vector3.new(0.12, 0.17, 0.12),
			surface(b, 0, 0.85, -0.5, 1.03),
			nil,
			nil,
			"Neon"
		)
	elseif pattern == "floatDrops" then
		for i = 1, math.max(1, math.min(count, 2)) do
			local p = piece(
				"FloatDrop" .. i,
				"pattern",
				"sphere",
				Vector3.new(0.1, 0.14, 0.1),
				Vector3.zero,
				second,
				{
					material = "Neon",
				}
			)
			p.orbit = { radius = 0.75, height = b.y * 0.6, period = 3, phase = (i - 1) / 2 }
			table.insert(out, p)
		end
	end
	return out, paired
end

-- Recette pure d'une espèce : tout ce qui ne dépend que de la ligne de Config/Species
local function speciesRecipe(def: Species.SpeciesDef)
	local b: Body = { x = def.body.x, y = def.body.y, z = def.body.z }
	local main, second = def.colors.main, def.colors.second
	local body = piece(
		"Body",
		"body",
		"sphere",
		Vector3.new(b.x, b.y, b.z),
		Vector3.new(0, b.y / 2, 0),
		main,
		{ lod = 3 }
	)
	local eyes, glints = eyePieces(b, def.eyes, def.top)
	local cheeks, mouth = facePieces(b)
	local top = topPieces(b, def.top, main, second)
	local pattern, paired = patternPieces(b, def.pattern, def.patternCount, second)
	return {
		body = body,
		eyes = eyes,
		glints = glints,
		cheeks = cheeks,
		mouth = mouth,
		top = top,
		pattern = pattern,
		patternPaired = paired,
		b = b,
	}
end

local function speciesDef(species: any): Species.SpeciesDef
	if type(species) == "number" and Species.ById[species] then
		return Species.ById[species]
	end
	return Species.ById[Species.PLOP]
end

local function mutationDef(mutation: any): Mutations.MutationDef?
	if type(mutation) == "number" then
		return Mutations.ById[mutation]
	end
	return nil
end

local function clonePiece(p: Piece): Piece
	local c = table.clone(p)
	if p.orbit then
		c.orbit = table.clone(p.orbit)
	end
	return c
end

-- v2.0 (lot B5, D12) : couleurs des 9 selles de la v2.0 (Cosmetics.ListV2 et selle de la semaine), LES
-- MÊMES que la table SADDLE_V2 de Controllers/RanchRenderer (lot B4, D19b ; Shared ne peut pas la lire :
-- égalité vérifiée par SquishyBuilder.spec) : un modèle construit seul (aperçus, spectacles) porte la
-- couleur que le ranch montre
local SADDLE_V2: { [string]: Color3 } = {
	confetti = rgb(255, 150, 200),
	goldenJelly = rgb(255, 205, 80),
	cosmos = rgb(70, 60, 150),
	titan = rgb(150, 160, 185),
	partyPopper = rgb(255, 125, 95),
	brick = rgb(205, 95, 65),
	icingSugar = rgb(235, 245, 255),
	cosmic = rgb(115, 75, 205),
	cookieSaddle = rgb(205, 150, 95),
}

-- Couleur d'une selle (Config/Cosmetics) ; « classic » = couleur du ranch, posée par setSaddleColor ;
-- une selle de la v1.3 garde sa couleur, une selle de la v2.0 prend la sienne, une inconnue le rose
local DEFAULT_SADDLE = rgb(255, 150, 170)
local function saddleColor(id: string?): Color3
	if type(id) == "string" then
		local def = Cosmetics.ByKindId["saddle:" .. id]
		if def and (def :: any).color then
			return (def :: any).color
		end
		if def == nil and SADDLE_V2[id] then
			return SADDLE_V2[id]
		end
	end
	return DEFAULT_SADDLE
end
SquishyBuilder._saddleColor = saddleColor

-- Tenue (Config/Cosmetics, + nœud papillon de Big Plop) : une pièce
local function outfitPiece(b: Body, outfit: string?): Piece?
	if type(outfit) ~= "string" then
		return nil
	end
	if outfit == "plopBib" then
		return piece(
			"Outfit",
			"outfit",
			"sphere",
			Vector3.new(0.5 * b.x, 0.35 * b.y, 0.12),
			surface(b, 0, -0.25, -0.97, 0.98),
			rgb(150, 210, 255)
		)
	elseif outfit == "sweater" then
		return piece(
			"Outfit",
			"outfit",
			"cylinder",
			Vector3.new(0.3 * b.y, 1.03 * b.x, 1.03 * b.z),
			Vector3.new(0, b.y * 0.32, 0),
			rgb(220, 70, 90),
			{ rot = deg(0, 0, 90) }
		)
	elseif outfit == "jellyCrown" then
		return piece(
			"Outfit",
			"outfit",
			"cylinder",
			Vector3.new(0.18, 0.35, 0.35),
			surface(b, 0, 1, 0) + Vector3.new(0, 0.08, 0),
			rgb(255, 140, 210),
			{ rot = deg(0, 0, 90), material = "Neon" }
		)
	elseif outfit == "winterScarf" then
		local r = math.sqrt(math.max(0, 1 - (2 * 0.62 - 1) ^ 2))
		return piece(
			"Outfit",
			"outfit",
			"cylinder",
			Vector3.new(0.12, 1.06 * b.x * r, 1.06 * b.z * r),
			Vector3.new(0, b.y * 0.62, 0),
			rgb(230, 60, 80),
			{ rot = deg(0, 0, 90) }
		)
	elseif outfit == "bowTie" then
		return piece(
			"Outfit",
			"outfit",
			"sphere",
			Vector3.new(0.3, 0.12, 0.08),
			surface(b, 0, -0.35, -0.94, 1.02),
			rgb(255, 220, 80)
		)
	elseif outfit == "partyHat" then
		-- v2.0 (lot B5, D12) : chapeau de fête pointu, un peu penché sur le côté de la tête
		return piece(
			"Outfit",
			"outfit",
			"sphere",
			Vector3.new(0.3, 0.52, 0.3),
			surface(b, 0.45, 1, -0.1) + Vector3.new(0.06, 0.2, 0),
			rgb(255, 110, 185),
			{ rot = deg(0, 0, -16) }
		)
	elseif outfit == "starGlasses" then
		-- lunettes étoiles relevées sur le front, couchées sur la surface (46° : la normale du front) :
		-- les yeux (et les visages) restent visibles
		return piece(
			"Outfit",
			"outfit",
			"sphere",
			Vector3.new(0.62 * b.x, 0.16, 0.12),
			surface(b, 0, 0.72, -0.7, 1.03),
			rgb(255, 214, 64),
			{ rot = deg(46, 0, 0), reflectance = 0.25 }
		)
	elseif outfit == "buildersCrown" then
		-- couronne de chantier : large, jaune casque, mate (la Couronne de gelée est rose et en Neon)
		return piece(
			"Outfit",
			"outfit",
			"cylinder",
			Vector3.new(0.14, 0.5, 0.5),
			surface(b, 0, 1, 0) + Vector3.new(0, 0.03, 0),
			rgb(255, 196, 40),
			{ rot = deg(0, 0, 90) }
		)
	elseif outfit == "polkaBow" then
		-- nœud à pois posé sur le côté de la tête
		return piece(
			"Outfit",
			"outfit",
			"sphere",
			Vector3.new(0.36, 0.17, 0.1),
			surface(b, 0.42, 0.82, -0.36, 1.03),
			rgb(255, 95, 150),
			{ rot = deg(0, 0, -22) }
		)
	end
	return nil
end

-- Pièces de la mutation : cœur (identité, entier ou absent) et détails (réductibles)
local function mutationPieces(
	b: Body,
	def: Mutations.MutationDef?,
	main: Color3
): ({ Piece }, { Piece }, { Piece })
	local core: { Piece } = {}
	local extra: { Piece } = {}
	local eyes: { Piece } = {}
	if def == nil then
		return core, extra, eyes
	end
	local look = def.look
	if look.core then
		table.insert(
			core,
			piece(
				"Core",
				"mutation",
				"ball",
				Vector3.new(0.35, 0.35, 0.35),
				Vector3.new(0, b.y / 2, 0),
				main:Lerp(Color3.new(0, 0, 0), 0.3)
			)
		)
	end
	if look.shell then
		table.insert(
			core,
			piece(
				"Shell",
				"mutation",
				"sphere",
				Vector3.new(b.x + 0.08, b.y + 0.08, b.z + 0.08),
				Vector3.new(0, b.y / 2, 0),
				def.color,
				{ material = look.shell }
			)
		)
	end
	if look.crescent then
		table.insert(
			core,
			piece(
				"Crescent",
				"mutation",
				"sphere",
				Vector3.new(0.2, 0.08, 0.05),
				surface(b, 0, 0.62, -0.78, 1.0),
				GOLD,
				{
					material = "Neon",
					rot = deg(0, 0, 20),
				}
			)
		)
	end
	if look.thirdEye then
		local _, k = eyeVersion()
		table.insert(
			eyes,
			piece(
				"Eye3",
				"eye",
				"sphere",
				Vector3.new(0.12 * k, 0.12 * k, 0.08 * k),
				surface(b, 0, 0.45, -0.89, 0.98),
				EYE,
				{
					reflectance = 0.3,
					lod = 2,
				}
			)
		)
	end
	local dots = look.dots or 0
	local dirs = {
		{ -0.6, 0.6, -0.5 },
		{ 0.6, 0.6, -0.5 },
		{ 0, 0.9, 0.4 },
		{ -0.8, 0, 0.6 },
		{ 0.8, 0, 0.6 },
		{ 0, 0.3, 0.95 },
	}
	for i = 1, math.min(dots, #dirs) do
		local d = dirs[i]
		table.insert(
			extra,
			piece(
				"Star" .. i,
				"extra",
				"ball",
				Vector3.new(0.06, 0.06, 0.06),
				surface(b, d[1], d[2], d[3], 1.0),
				WHITE,
				{
					material = "Neon",
				}
			)
		)
	end
	local orbiters = look.orbiters or 0
	for i = 1, orbiters do
		local glitch = look.steps ~= nil
		local p = piece(
			"Orbiter" .. i,
			"extra",
			if glitch then "block" else "sphere",
			if glitch then Vector3.new(0.12, 0.12, 0.12) else Vector3.new(0.12, 0.16, 0.12),
			Vector3.zero,
			if glitch then (if i % 2 == 0 then rgb(255, 80, 220) else def.color) else rgb(170, 220, 255),
			{ material = "Neon" }
		)
		p.orbit = {
			radius = 0.8,
			height = b.y * (if glitch then 0.7 else 0.55),
			period = if glitch then 2 else 3,
			phase = (i - 1) / orbiters,
		}
		table.insert(extra, p)
	end
	local stars = look.goldStars or 0
	for i = 1, stars do
		local p =
			piece("GoldStar" .. i, "extra", "block", Vector3.new(0.12, 0.12, 0.04), Vector3.zero, GOLD, {
				material = "Neon",
				rot = deg(0, 0, 45),
			})
		p.orbit = { radius = 0.35, height = b.y + 0.35, period = 2, phase = (i - 1) / stars }
		table.insert(extra, p)
	end
	return core, extra, eyes
end

-- Plan d'un modèle : pièces choisies (≤ 12) dans l'ordre de priorité, corps en premier
local function plan(spec: BuildSpec): ({ Piece }, Body)
	local def = speciesDef(spec.species)
	local r = speciesRecipe(def)
	local mut = mutationDef(spec.mutation)
	local b = r.b
	local body = clonePiece(r.body)
	local eyes = {}
	for _, p in r.eyes do
		table.insert(eyes, clonePiece(p))
	end
	local core, extra, extraEyes = mutationPieces(b, mut, def.colors.main)
	if def.eyes ~= "threeEyes" then
		for _, p in extraEyes do
			table.insert(eyes, p)
		end
	end
	if mut and mut.look.deflate then
		local d = mut.look.deflate
		body.size = Vector3.new(body.size.X * d.xz, body.size.Y * d.y, body.size.Z * d.xz)
		body.offset = Vector3.new(0, body.size.Y / 2, 0)
	end
	if mut and mut.look.halfEyes then
		for _, p in eyes do
			p.size = Vector3.new(p.size.X, math.max(0.04, p.size.Y * 0.5), p.size.Z)
		end
	end
	local groups: { { list: { Piece }, mode: string } } = {
		{ list = { body }, mode = "all" },
		{ list = eyes, mode = "all" },
	}
	if type(spec.saddle) == "string" then
		local sb = body.size
		table.insert(groups, {
			list = {
				piece(
					"Saddle",
					"saddle",
					"sphere",
					Vector3.new(0.7 * sb.X, 0.18, 0.75 * sb.Z),
					Vector3.new(0, sb.Y * 0.95, 0),
					saddleColor(spec.saddle)
				),
			},
			mode = "whole",
		})
	end
	local outfit = outfitPiece(b, spec.outfit)
	if outfit then
		table.insert(groups, { list = { outfit }, mode = "whole" })
	end
	table.insert(groups, { list = core, mode = "whole" })
	table.insert(groups, { list = r.top, mode = "whole" })
	table.insert(groups, { list = r.mouth, mode = "mouth" })
	table.insert(groups, { list = extra, mode = "partial" })
	table.insert(groups, { list = r.cheeks, mode = "whole" })
	table.insert(groups, { list = r.pattern, mode = if r.patternPaired then "whole" else "partial" })
	-- reflets : seulement pour les yeux restés ouverts et non réduits de moitié
	if not (mut and mut.look.halfEyes) then
		table.insert(groups, { list = r.glints, mode = "whole" })
	end
	local out: { Piece } = {}
	for _, g in groups do
		local left = MAX_PARTS - #out
		local n = #g.list
		if n > 0 and left > 0 then
			if g.mode == "all" or n <= left then
				for _, p in g.list do
					table.insert(out, clonePiece(p))
				end
			elseif g.mode == "partial" then
				for i = 1, left do
					table.insert(out, clonePiece(g.list[i]))
				end
			elseif g.mode == "mouth" then
				-- une seule place : un petit sourire d'une pièce au milieu
				local center = clonePiece(g.list[2] or g.list[1])
				center.name = "Mouth"
				center.shape = "sphere"
				center.size = Vector3.new(0.12, 0.04, 0.04)
				table.insert(out, center)
			end
		end
	end
	return out, { x = body.size.X, y = body.size.Y, z = body.size.Z }
end
SquishyBuilder._plan = plan

-- Recette pure (pièces, couleurs, tailles) d'une espèce, sans instance (tests)
function SquishyBuilder.recipe(species: number): { [string]: any }
	local def = speciesDef(species)
	local r = speciesRecipe(def)
	local pieces = { r.body }
	for _, list in { r.eyes, r.top, r.mouth, r.cheeks, r.pattern, r.glints } do
		for _, p in list do
			table.insert(pieces, p)
		end
	end
	local rarity = Rarities.List[def.rarity]
	return {
		id = def.id,
		key = def.key,
		body = { x = def.body.x, y = def.body.y, z = def.body.z },
		colors = { main = def.colors.main, second = def.colors.second },
		top = def.top,
		eyes = def.eyes,
		pattern = def.pattern,
		wobble = { hz = def.wobble.hz, amp = def.wobble.amp },
		rarity = def.rarity,
		aura = if rarity then rarity.aura else "none",
		pieces = pieces,
		eyeCount = #r.eyes,
		topCount = #r.top,
		patternCount = #r.pattern,
	}
end

-- =============================================================================================
-- Instances
-- =============================================================================================

type Record = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	pieces: { Piece },
	body3: Vector3, -- proportions du corps (× D), dégonflage du Flop compris
	speciesBody: Body, -- proportions de la ligne de l'espèce (places du visage, sans le dégonflage)
	glints: number, -- nombre de reflets des yeux (visages)
	signature: string,
	stars: BillboardGui?, -- arc d'étoiles : construit à la première étoile montrée (lot B5, D11)
	starRays: { { Frame } }, -- [étoile] = ses 3 traits
	aura: BillboardGui?,
	light: PointLight?,
	emitters: { ParticleEmitter },
	baseRates: { number },
}

type State = {
	record: Record,
	released: boolean,
	d: number,
	squash: Vector3,
	visible: { boolean },
	outParts: { BasePart },
	outCFrames: { CFrame },
	particles: number,
	auraOn: boolean,
	reduced: boolean,
	blinkSeed: number,
	blinking: boolean,
	face: string, -- visage courant (Visuals.Faces ; « happy » = la recette)
}

local states: { [Handle]: State } = setmetatable({}, { __mode = "k" }) :: any
local pools: { [string]: { Record } } = {}
local pooled = 0

local function signatureOf(spec: BuildSpec): string
	return table.concat({
		tostring(speciesDef(spec.species).id),
		tostring(if mutationDef(spec.mutation) then spec.mutation else 0),
		tostring(spec.outfit or ""),
		if type(spec.saddle) == "string" then "s" else "",
		if spec.rarityAura == true then "a" else "",
	}, "|")
end

local function newPart(p: Piece): BasePart
	local part: BasePart
	if p.shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if p.shape == "ball" then
			block.Shape = Enum.PartType.Ball
		elseif p.shape == "cylinder" then
			block.Shape = Enum.PartType.Cylinder
		end
		part = block
		if p.shape == "sphere" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
	end
	part.Name = p.name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	Ice = Enum.Material.Ice,
	Foil = Enum.Material.Foil,
	ForceField = Enum.Material.ForceField,
}

local function material(name: string?): Enum.Material
	return if name and MATERIALS[name] then MATERIALS[name] else Enum.Material.SmoothPlastic
end

local PARTICLE_COLORS: { [string]: Color3 } = {
	snow = rgb(240, 248, 255),
	sparkles = GOLD,
	stars = GOLD,
	petals = rgb(255, 170, 210),
	drops = rgb(190, 220, 255),
}

local function newEmitter(parent: BasePart, kind: string, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Particles_" .. kind
	e.Color = ColorSequence.new(PARTICLE_COLORS[kind] or WHITE)
	e.LightEmission = if kind == "snow" or kind == "petals" then 0 else 0.6
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 1.6)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.2)
	e.Enabled = rate > 0
	e.Parent = parent
	return e
end

-- Forme de l'aura de rareté (BillboardGui en Frames : couleur ET forme, GDD §14)
local function buildAura(body: BasePart, rarity: Rarities.RarityDef): BillboardGui?
	if rarity.aura == "none" then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Aura"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = true
	gui.Parent = body
	local function frame(
		name: string,
		size: number,
		x: number,
		y: number,
		round: boolean,
		rotation: number?
	): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromScale(size, size)
		f.Position = UDim2.fromScale(x, y)
		f.BackgroundColor3 = rarity.color
		f.BorderSizePixel = 0
		f.Rotation = rotation or 0
		if round then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
		end
		f.Parent = gui
		return f
	end
	local function ring(name: string, size: number)
		local f = frame(name, size, 0.5, 0.5, true)
		f.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = rarity.color
		stroke.Parent = f
		if rarity.rainbow then
			stroke.Color = WHITE
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 90, 90)),
				ColorSequenceKeypoint.new(0.25, rgb(255, 230, 90)),
				ColorSequenceKeypoint.new(0.5, rgb(90, 230, 140)),
				ColorSequenceKeypoint.new(0.75, rgb(90, 160, 255)),
				ColorSequenceKeypoint.new(1, rgb(220, 110, 255)),
			})
			g.Parent = stroke
			local back = frame(name .. "Back", size + 0.06, 0.5, 0.5, true)
			back.BackgroundTransparency = 1
			back.ZIndex = 0
			local edge = Instance.new("UIStroke")
			edge.Thickness = 5
			edge.Color = rarity.color
			edge.Parent = back
		end
	end
	if rarity.aura == "dots3" then
		for i = 1, 3 do
			local a = math.rad(90 + (i - 1) * 120)
			frame("Dot" .. i, 0.12, 0.5 + 0.45 * math.cos(a), 0.5 + 0.45 * math.sin(a), true)
		end
	elseif rarity.aura == "diamonds4" then
		for i = 1, 4 do
			local a = math.rad(45 + (i - 1) * 90)
			frame("Diamond" .. i, 0.12, 0.5 + 0.45 * math.cos(a), 0.5 + 0.45 * math.sin(a), false, 45)
		end
	elseif rarity.aura == "starCrown" then
		for i = 1, 5 do
			local x = 0.3 + (i - 1) * 0.1
			local y = 0.08 + math.abs(i - 3) * 0.03
			frame("Point" .. i, 0.09, x, y, false, 45)
		end
		ring("Ring", 0.95)
	elseif rarity.aura == "doubleRing" then
		ring("Ring1", 0.98)
		ring("Ring2", 0.8)
	elseif rarity.aura == "floatingDiamond" then
		frame("Diamond", 0.16, 0.5, 0.05, false, 45)
		ring("Ring", 0.95)
	else
		ring("Ring", 0.95)
	end
	return gui
end

-- Arc d'étoiles DESSINÉES (lot B5, D11, INT-B1-STARS ; GDD §5.2, règle 18 du §10.8 « aucun symbole
-- hors police ») : BillboardGui sous 60 studs, 1 à 5 étoiles dorées. « ★ » n'est dans aucune des deux
-- polices du jeu : chaque étoile est faite de 3 traits dorés qui se croisent en son centre (6 branches,
-- une pointe en haut ; même idée que l'étoile de Client/UI/Glyph, que Shared ne peut pas lire), en
-- fractions de l'arc : elle suit la taille du modèle sans être reconstruite. L'arc et chaque étoile
-- sont construits la première fois qu'un modèle les montre : 1 + 3 n instances pour n étoiles (0 sans
-- étoile), contre 11 par modèle avec les 5 TextLabel et leurs 5 UIStroke de la v1.3.
local STAR_BOX = 0.2 -- côté d'une étoile, en fraction de la largeur de l'arc
local STAR_ARC_X, STAR_ARC_Y = 1.4, 0.36 -- taille de l'arc (× D), celle de la v1.3
-- trait : fractions du côté de l'étoile (0,86 : les étoiles voisines ne se touchent pas ; 0,22 : branches
-- nettes de près, encore pleines de loin ; choisi sur un aperçu hors moteur, à regarder sur une télé)
local STAR_RAY_LENGTH = 0.86
local STAR_RAY_THICKNESS = 0.22
local STAR_ANGLES = { 90, 30, 150 }

local function sizeStars(rec: Record, d: number)
	local gui = rec.stars
	if gui then
		gui.Size = UDim2.fromScale(STAR_ARC_X * d, STAR_ARC_Y * d)
		gui.StudsOffsetWorldSpace = Vector3.new(0, rec.body3.Y * d / 2 + 0.32 * d, 0)
	end
end

-- Construit l'arc (une fois) puis les étoiles qui manquent jusqu'à la n-ième
local function ensureStars(rec: Record, n: number, d: number)
	local gui = rec.stars
	if gui == nil then
		local created = Instance.new("BillboardGui")
		created.Name = "Stars"
		created.LightInfluence = 0
		created.AlwaysOnTop = false
		created.MaxDistance = SquishyBuilder.STARS_DISTANCE
		created.Enabled = false
		created.Parent = rec.body
		rec.stars = created
		gui = created
		sizeStars(rec, d)
	end
	-- un trait couché, puis tourné : longueur en fraction de la largeur de l'arc, épaisseur en
	-- fraction de sa hauteur (l'étoile reste carrée à l'écran)
	local size =
		UDim2.fromScale(STAR_BOX * STAR_RAY_LENGTH, STAR_BOX * STAR_RAY_THICKNESS * STAR_ARC_X / STAR_ARC_Y)
	for i = #rec.starRays + 1, math.min(n, SquishyBuilder.STARS_MAX) do
		local rays: { Frame } = {}
		for k, angle in STAR_ANGLES do
			local ray = Instance.new("Frame")
			ray.Name = "Star" .. i .. "Ray" .. k
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Size = size
			ray.Rotation = angle
			ray.BackgroundColor3 = GOLD
			ray.BorderSizePixel = 0
			ray.Visible = false
			ray.Parent = gui
			rays[k] = ray
		end
		rec.starRays[i] = rays
	end
end

local function newRecord(spec: BuildSpec): Record
	local pieces, body3 = plan(spec)
	local model = Instance.new("Model")
	model.Name = "Squishy"
	local parts: { BasePart } = {}
	for i, p in pieces do
		local part = newPart(p)
		part.Parent = model
		parts[i] = part
	end
	local body = parts[1]
	model.PrimaryPart = body
	local def = speciesDef(spec.species)
	local glints = 0
	for _, p in pieces do
		if p.role == "glint" then
			glints += 1
		end
	end
	local rarity = Rarities.List[def.rarity]
	local aura: BillboardGui? = nil
	local light: PointLight? = nil
	if rarity then
		if spec.rarityAura == true then
			aura = buildAura(body, rarity)
		end
		if rarity.light then
			local l = Instance.new("PointLight")
			l.Name = "AuraLight"
			l.Color = rarity.color
			l.Range = 8
			l.Brightness = 1
			l.Shadows = false
			l.Enabled = false -- le renderer allume les 4 Légendaires les plus proches (GDD §12.9)
			l.Parent = body
			light = l
		end
	end
	local emitters: { ParticleEmitter } = {}
	local rates: { number } = {}
	local mut = mutationDef(spec.mutation)
	if mut and mut.look.particles then
		local rate = mut.look.particleRate or 3
		table.insert(emitters, newEmitter(body, mut.look.particles, rate))
		table.insert(rates, rate)
	end
	if def.pattern == "petals" then
		table.insert(emitters, newEmitter(body, "petals", 3))
		table.insert(rates, 3)
	end
	return {
		model = model,
		body = body,
		parts = parts,
		pieces = pieces,
		body3 = Vector3.new(body3.x, body3.y, body3.z),
		speciesBody = { x = def.body.x, y = def.body.y, z = def.body.z },
		glints = glints,
		signature = signatureOf(spec),
		stars = nil,
		starRays = {},
		aura = aura,
		light = light,
		emitters = emitters,
		baseRates = rates,
	}
end

local function finite(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end

local function lodOf(x: any): number
	return math.clamp(math.floor(finite(x, 1)), 1, 3)
end

local function diameterOf(displayScale: any): number
	return BASE_D * math.clamp(finite(displayScale, 1), 0.05, 1e4)
end

-- =============================================================================================
-- Visages (v2.0, lot B5, D6 ; GDD §5.6) : six visages faits avec les pièces existantes. « happy »
-- (Content) est la recette ; les cinq autres changent la taille des yeux et des reflets (une écriture
-- par changement, jamais animée), le matériau des reflets (« starry »), et déplacent la bouche et les
-- yeux par leur décalage (CFrame). Les tailles restent des facteurs de la recette : elles suivent
-- l'espèce, la mutation (yeux mi-clos du Flop) et la version des yeux (Visuals.EyeChoice).
-- =============================================================================================

type FaceDef = {
	eye: Vector3, -- facteurs de taille des yeux
	eyeAlone: Vector3?, -- facteurs des yeux d'un modèle sans reflet (le visage se lit quand même)
	open: boolean, -- un œil fermé ou mi-clos de la recette s'ouvre en grand
	lift: number, -- décalage vertical des yeux et des reflets (× D)
	glint: number, -- facteur de taille des reflets (0 = cachés)
	neon: boolean, -- reflets en Neon
	mouth: { { number } }?, -- directions (u, v) des 3 pièces de la bouche ; nil = sourire de la recette
	turn: boolean, -- bouche d'une seule pièce tournée d'un quart de tour (bouche ronde)
	blink: boolean, -- les yeux clignent encore (jamais quand le visage les ferme)
}

local DEFAULT_FACE = "happy"

-- stylua: ignore start
local FACES: { [string]: FaceDef } = {
	-- Ravi : yeux fermés en arc, un peu relevés, grand sourire
	delighted = { eye = Vector3.new(1.1, 0.3, 0.8), open = false, lift = 0.02, glint = 0, neon = false,
		mouth = { { -0.13, -0.09 }, { 0, -0.17 }, { 0.13, -0.09 } }, turn = false, blink = false },
	-- Surpris : yeux × 1,2 (un œil fermé s'ouvre), bouche ronde
	surprised = { eye = Vector3.new(1.2, 1.2, 1.2), open = true, lift = 0, glint = 1.2, neon = false,
		mouth = { { -0.035, -0.105 }, { 0, -0.165 }, { 0.035, -0.105 } }, turn = true, blink = true },
	-- Endormi : yeux fermés, un peu bas, petite bouche droite
	sleepy = { eye = Vector3.new(1, 0.2, 0.8), open = false, lift = -0.015, glint = 0, neon = false,
		mouth = { { -0.07, -0.125 }, { 0, -0.125 }, { 0.07, -0.125 } }, turn = false, blink = false },
	-- Étoilé : reflets × 1,6 en Neon (sans reflet : yeux × 1,15)
	starry = { eye = Vector3.one, eyeAlone = Vector3.new(1.15, 1.15, 1.15), open = false, lift = 0, glint = 1.6,
		neon = true, mouth = nil, turn = false, blink = true },
	-- Boudeur : le visage du Flop (yeux mi-clos, sans reflet), bouche à l'envers
	sulky = { eye = Vector3.new(1, 0.5, 1), open = false, lift = 0, glint = 0, neon = false,
		mouth = { { -0.1, -0.15 }, { 0, -0.1 }, { 0.1, -0.15 } }, turn = false, blink = true },
}
-- stylua: ignore end

local EYE_CLOSED = 0.05 -- épaisseur d'un œil fermé (× D), celle des yeux fermés de la v1.3
local GLINT_HIDDEN = Vector3.new(0.001, 0.001, 0.001) -- reflet caché : la plus petite pièce du moteur
local MOUTH_INDEX: { [string]: number } = { Mouth1 = 1, Mouth2 = 2, Mouth3 = 3 }
local QUARTER_TURN = CFrame.Angles(0, 0, math.pi / 2)

-- Taille (× D) d'un œil sous un visage ; `alone` : le modèle n'a aucun reflet
local function faceEyeSize(face: FaceDef, p: Piece, alone: boolean): Vector3
	local s = p.size
	local f = if alone and face.eyeAlone then face.eyeAlone else face.eye
	if face.open and s.Y < s.X * 0.5 then
		-- œil fermé ou mi-clos de la recette : rond comme un œil ouvert, puis le facteur du visage
		return Vector3.new(s.X * f.X, s.X * f.Y, s.X * 0.65 * f.Z)
	end
	local y = s.Y * f.Y
	if f.Y < 1 and y < EYE_CLOSED then
		y = math.min(s.Y, EYE_CLOSED) -- jamais plus fin qu'un œil fermé
	end
	return Vector3.new(s.X * f.X, y, s.Z * f.Z)
end

-- Taille (studs) d'un reflet sous un visage
local function faceGlintSize(face: FaceDef, p: Piece, d: number): Vector3
	if face.glint <= 0 then
		return GLINT_HIDDEN
	end
	return p.size * (face.glint * d)
end

-- Décalage d'une pièce sous un visage (les pièces en orbite sont posées par animate)
local function faceOffset(face: FaceDef, p: Piece, d: number, b: Body): CFrame
	if p.role == "eye" or p.role == "glint" then
		if face.lift ~= 0 then
			return CFrame.new((p.offset + Vector3.new(0, face.lift, 0)) * d) * p.rot
		end
	elseif p.role == "mouth" then
		local index = MOUTH_INDEX[p.name]
		local mouth = face.mouth
		if index and mouth then
			local uv = mouth[index]
			return CFrame.new(surface(b, uv[1], uv[2], -0.99, 1.0) * d) * p.rot
		elseif index == nil and face.turn then
			return CFrame.new(p.offset * d) * p.rot * QUARTER_TURN
		end
	end
	return CFrame.new(p.offset * d) * p.rot
end

-- Pose le visage courant : yeux et reflets (une écriture de Size au plus par pièce, aucune si la
-- taille ne change pas), matériau des reflets, décalages des yeux, des reflets et de la bouche
local function applyFace(handle: Handle, st: State)
	local rec = st.record
	local d = st.d
	local face = FACES[st.face]
	local alone = rec.glints == 0
	local offsets = handle.offsets
	for i, p in rec.pieces do
		local role = p.role
		if role == "eye" or role == "glint" then
			local part = rec.parts[i]
			local size: Vector3
			if face == nil then
				size = p.size * d
			elseif role == "eye" then
				size = faceEyeSize(face, p, alone) * d
			else
				size = faceGlintSize(face, p, d)
			end
			if part.Size ~= size then
				part.Size = size
			end
			if role == "glint" then
				local mat = material(if face and face.neon then "Neon" else p.material)
				if part.Material ~= mat then
					part.Material = mat
				end
			end
		end
		if (role == "eye" or role == "glint" or role == "mouth") and p.orbit == nil then
			offsets[i] = if face
				then faceOffset(face, p, d, rec.speciesBody)
				else CFrame.new(p.offset * d) * p.rot
		end
	end
	-- les yeux viennent d'être écrits ouverts : le clignement repart de là (animate)
	st.blinking = false
end

-- Couleurs, matériaux et transparences des pièces selon la mutation (rendu fixe en Mouvement réduit)
local function applyLook(st: State, spec: BuildSpec)
	local rec = st.record
	local def = speciesDef(spec.species)
	local mut = mutationDef(spec.mutation)
	local look = if mut then mut.look else nil
	local reduced = st.reduced
	local rainbowFixed =
		{ rgb(255, 120, 120), rgb(255, 210, 110), rgb(130, 230, 150), rgb(120, 180, 255), rgb(210, 140, 255) }
	local featureIndex = 0
	-- v2.0 (lot B5, D6) : reflets en Neon tant que le visage le demande (« starry »)
	local face = FACES[st.face]
	local neonGlints = face ~= nil and face.neon
	for i, p in rec.pieces do
		local part = rec.parts[i]
		local color = p.color
		local mat = p.material
		local transparency = p.transparency
		if neonGlints and p.role == "glint" then
			mat = "Neon"
		end
		if p.role == "body" and look then
			color = look.color or def.colors.main
			mat = look.material or "SmoothPlastic"
			transparency = look.transparency or 0
			if look.hueCycle and reduced then
				color = rgb(255, 190, 220) -- Arc-en-ciel figé : dégradé fixe sur les pièces
			end
		elseif look and (p.role == "top" or p.role == "pattern" or p.role == "cheek") then
			if look.neonFeatures then
				mat = "Neon"
			end
			featureIndex += 1
			if look.hueCycle and reduced then
				color = rainbowFixed[(featureIndex - 1) % #rainbowFixed + 1]
			elseif look.steps and reduced then
				local glitch = (mut :: Mutations.MutationDef).color
				color = if featureIndex % 2 == 0 then rgb(255, 80, 220) else glitch -- damier fixe
			end
		end
		part.Color = color
		part.Material = material(mat)
		part.Reflectance = p.reflectance
		local visible = st.visible[i] ~= false
		part.Transparency = if visible then transparency else 1
	end
end

-- Tailles et décalages au diamètre courant (écrasement : seulement le corps). Visage « happy »
-- (face == nil) : exactement le chemin de la v1.3 ; sinon yeux, reflets et bouche du visage.
local function applyScale(handle: Handle, st: State)
	local rec = st.record
	local d = st.d
	local face = FACES[st.face]
	local alone = rec.glints == 0
	local offsets: { CFrame } = {}
	for i, p in rec.pieces do
		local part = rec.parts[i]
		local size = p.size * d
		if i == 1 then
			size = Vector3.new(size.X * st.squash.X, size.Y * st.squash.Y, size.Z * st.squash.Z)
		elseif face then
			if p.role == "eye" then
				size = faceEyeSize(face, p, alone) * d
			elseif p.role == "glint" then
				size = faceGlintSize(face, p, d)
			end
		end
		part.Size = size
		offsets[i] = if face
			then faceOffset(face, p, d, rec.speciesBody)
			else CFrame.new(p.offset * d) * p.rot
	end
	handle.offsets = offsets
	local b = rec.body3
	sizeStars(rec, d)
	local aura = rec.aura
	if aura then
		aura.Size = UDim2.fromScale(1.7 * d * math.max(b.X, b.Y), 1.7 * d * math.max(b.X, b.Y))
	end
	local light = rec.light
	if light then
		light.Range = math.clamp(4 * d, 4, 20)
	end
end

local function applyLod(handle: Handle, st: State, lod: number)
	local rec = st.record
	handle.lod = lod
	handle.spec.lod = lod
	for i, p in rec.pieces do
		local visible = p.lod >= lod
		st.visible[i] = visible
		local part = rec.parts[i]
		local target = 1
		if visible then
			target = if i == 1 then part:GetAttribute("BaseTransparency") :: number? or 0 else 0
		end
		if part.Transparency ~= target then
			part.Transparency = target
		end
	end
	local stars = rec.stars
	if stars then
		stars.Enabled = lod == 1 and (handle.spec.stars or 0) > 0
	end
	local aura = rec.aura
	if aura then
		aura.Enabled = st.auraOn and lod <= 2
	end
	for j, e in rec.emitters do
		local rate = rec.baseRates[j] * st.particles
		e.Rate = rate
		e.Enabled = lod == 1 and rate > 0
	end
end

-- Transparence propre du corps (Gelée) gardée pour les changements de LOD
local function rememberBodyTransparency(st: State)
	local body = st.record.body
	body:SetAttribute("BaseTransparency", body.Transparency)
end

local function newState(rec: Record): State
	local visible = {}
	for i in rec.pieces do
		visible[i] = true
	end
	return {
		record = rec,
		released = false,
		d = BASE_D,
		squash = Vector3.one,
		visible = visible,
		outParts = {},
		outCFrames = {},
		particles = 1,
		auraOn = true,
		reduced = false,
		blinkSeed = math.random(),
		blinking = false,
		face = DEFAULT_FACE,
	}
end

local function sanitizeSpec(spec: any): BuildSpec
	local s: any = if type(spec) == "table" then spec else {}
	return {
		species = speciesDef(s.species).id,
		mutation = if mutationDef(s.mutation) then s.mutation else 0,
		stars = math.clamp(math.floor(finite(s.stars, 1)), 0, SquishyBuilder.STARS_MAX),
		displayScale = math.clamp(finite(s.displayScale, 1), 0.05, 1e4),
		lod = lodOf(s.lod),
		outfit = if type(s.outfit) == "string" then s.outfit else nil,
		saddle = if type(s.saddle) == "string" then s.saddle else nil,
		rarityAura = s.rarityAura == true,
	}
end

-- Construit (ou reprend dans la réserve) un modèle
function SquishyBuilder.build(spec: BuildSpec, parent: Instance?): Handle
	local clean = sanitizeSpec(spec)
	local sig = signatureOf(clean)
	local pool = pools[sig]
	local rec: Record
	if pool and #pool > 0 then
		rec = table.remove(pool) :: Record
		pooled -= 1
	else
		rec = newRecord(clean)
	end
	local handle: Handle = {
		model = rec.model,
		body = rec.body,
		parts = table.clone(rec.parts),
		offsets = {},
		spec = clean,
		lod = clean.lod,
	}
	local st = newState(rec)
	st.d = diameterOf(clean.displayScale)
	states[handle] = st
	applyLook(st, clean)
	rememberBodyTransparency(st)
	if type(clean.saddle) == "string" then
		SquishyBuilder.setSaddleColor(handle, saddleColor(clean.saddle))
	end
	applyScale(handle, st)
	SquishyBuilder.setStars(handle, clean.stars)
	applyLod(handle, st, clean.lod)
	-- pose de départ (origine) : chaque pièce à son décalage
	local parts, cframes = SquishyBuilder.pose(handle, CFrame.new())
	for i, part in parts do
		part.CFrame = cframes[i]
	end
	rec.model.Parent = parent
	return handle
end

-- Niveau de détail 1 (complet), 2 (corps + yeux), 3 (corps seul)
function SquishyBuilder.setLod(handle: Handle, lod: number)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local l = lodOf(lod)
	if l == handle.lod then
		return
	end
	applyLod(handle, st, l)
end

-- Échelle affichée (SizeScale.display)
function SquishyBuilder.setScale(handle: Handle, displayScale: number)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local d = diameterOf(displayScale)
	if math.abs(d - st.d) < 1e-6 then
		return
	end
	st.d = d
	handle.spec.displayScale = d / BASE_D
	applyScale(handle, st)
end

-- Écrasement du corps (une écriture de Size), volume à peu près gardé
function SquishyBuilder.setSquash(handle: Handle, sx: number, sy: number, sz: number)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local x = math.clamp(finite(sx, 1), 0.2, 3)
	local y = math.clamp(finite(sy, 1), 0.2, 3)
	local z = math.clamp(finite(sz, 1), 0.2, 3)
	local squash = Vector3.new(x, y, z)
	if squash == st.squash then
		return
	end
	st.squash = squash
	local base = st.record.pieces[1].size * st.d
	handle.body.Size = Vector3.new(base.X * x, base.Y * y, base.Z * z)
end

-- Pièces et CFrames à passer à workspace:BulkMoveTo pour ce modèle. Les deux listes sont réutilisées
-- d'un appel à l'autre pour ce Handle (aucune allocation de table par image) : les consommer tout
-- de suite.
function SquishyBuilder.pose(handle: Handle, cframe: CFrame): ({ BasePart }, { CFrame })
	local st = states[handle]
	if st == nil or st.released then
		return {}, {}
	end
	local outParts, outCFrames = st.outParts, st.outCFrames
	table.clear(outParts)
	table.clear(outCFrames)
	local sx, sy, sz = st.squash.X, st.squash.Y, st.squash.Z
	local n = 0
	for i, part in st.record.parts do
		if st.visible[i] then
			local off = handle.offsets[i]
			local p = off.Position
			n += 1
			outParts[n] = part
			outCFrames[n] = cframe * CFrame.new(p.X * sx, p.Y * sy, p.Z * sz) * off.Rotation
		end
	end
	return outParts, outCFrames
end

-- Aspect de mutation (rendu fixe en Mouvement réduit)
function SquishyBuilder.setMutation(handle: Handle, mutation: number, reducedMotion: boolean)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local m = if mutationDef(mutation) then mutation else 0
	st.reduced = reducedMotion == true
	if m == handle.spec.mutation then
		applyLook(st, handle.spec)
		return
	end
	-- autre aspect : nouveau jeu de pièces (rare : révélation à la naissance), même Handle
	local spec = table.clone(handle.spec)
	spec.mutation = m
	local old = st.record
	local parent = old.model.Parent
	local pivot = old.body.CFrame * CFrame.new(0, -old.body.Size.Y / 2, 0)
	local rec = newRecord(spec)
	old.model:Destroy()
	st.record = rec
	st.visible = {}
	for i in rec.pieces do
		st.visible[i] = true
	end
	handle.model = rec.model
	handle.body = rec.body
	handle.parts = table.clone(rec.parts)
	handle.spec = spec
	applyLook(st, spec)
	rememberBodyTransparency(st)
	if type(spec.saddle) == "string" then
		SquishyBuilder.setSaddleColor(handle, saddleColor(spec.saddle))
	end
	local squash = st.squash
	st.squash = Vector3.one
	applyScale(handle, st)
	SquishyBuilder.setSquash(handle, squash.X, squash.Y, squash.Z)
	SquishyBuilder.setStars(handle, spec.stars)
	local lod = handle.lod
	handle.lod = 0
	applyLod(handle, st, lod)
	local parts, cframes = SquishyBuilder.pose(handle, pivot)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
	rec.model.Parent = parent
end

-- Arc d'étoiles (BillboardGui sous 60 studs)
function SquishyBuilder.setStars(handle: Handle, stars: number)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local n = math.clamp(math.floor(finite(stars, 0)), 0, SquishyBuilder.STARS_MAX)
	handle.spec.stars = n
	local rec = st.record
	if n > #rec.starRays then
		ensureStars(rec, n, st.d) -- première fois que ce modèle montre cette étoile
	end
	for i, rays in rec.starRays do
		local visible = i <= n
		-- arc : les étoiles du milieu un peu plus haut
		local x = 0.5 + (i - (n + 1) / 2) * STAR_BOX
		local y = 0.5 + math.abs(i - (n + 1) / 2) * 0.12
		for _, ray in rays do
			ray.Visible = visible
			if visible then
				ray.Position = UDim2.fromScale(x, y)
			end
		end
	end
	local gui = rec.stars
	if gui then
		gui.Enabled = n > 0 and handle.lod == 1
	end
end

-- Points d'attache (selle, tenue, tête) en repère du modèle
function SquishyBuilder.attachments(handle: Handle): Attachments
	local st = states[handle]
	if st == nil then
		return { saddle = CFrame.new(), outfit = CFrame.new(), head = CFrame.new() }
	end
	local b = st.record.body3 * st.d
	local sy, sz = st.squash.Y, st.squash.Z
	return {
		saddle = CFrame.new(0, b.Y * sy * 0.95, 0),
		outfit = CFrame.new(0, b.Y * sy * 0.5, -b.Z * sz * 0.5),
		head = CFrame.new(0, b.Y * sy + 0.05 * st.d, 0),
	}
end

-- Rend le modèle à la réserve
function SquishyBuilder.release(handle: Handle)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	-- v2.0 (lot B5, D6) : le modèle repart à la réserve avec son visage de repos
	if st.face ~= DEFAULT_FACE then
		st.face = DEFAULT_FACE
		applyFace(handle, st)
	end
	st.released = true
	local rec = st.record
	rec.model.Parent = nil
	-- la lumière d'aura (allumée par le renderer pour ses 4 Légendaires) repart éteinte : un modèle
	-- repris dans la réserve n'hérite jamais d'une lumière hors quota
	local light = rec.light
	if light and light.Enabled then
		light.Enabled = false
	end
	local pool = pools[rec.signature]
	if pool == nil then
		pool = {}
		pools[rec.signature] = pool
	end
	if #pool < SquishyBuilder.POOL_PER_LOOK and pooled < SquishyBuilder.POOL_TOTAL then
		table.insert(pool, rec)
		pooled += 1
	else
		rec.model:Destroy()
	end
end

-- Nombre de pièces du modèle (≤ 12 en complet ; specs de budget)
function SquishyBuilder.partCount(spec: BuildSpec): number
	local clean = sanitizeSpec(spec)
	local pieces = plan(clean)
	local n = 0
	for _, p in pieces do
		if p.lod >= clean.lod then
			n += 1
		end
	end
	return n
end

-- =============================================================================================
-- Fonctions ajoutées (renderers)
-- =============================================================================================

-- Couleur de la selle (« classic » = couleur du ranch, choisie par le renderer)
function SquishyBuilder.setSaddleColor(handle: Handle, color: Color3)
	local st = states[handle]
	if st == nil or st.released or typeof(color) ~= "Color3" then
		return
	end
	for i, p in st.record.pieces do
		if p.role == "saddle" then
			st.record.parts[i].Color = color
		end
	end
end

-- Visages que setFace sait dessiner, dans l'ordre de Config/Visuals.Faces (v2.0, lot B5)
do
	local list: { string } = {}
	for _, name in Visuals.Faces do
		if name == DEFAULT_FACE or FACES[name] then
			table.insert(list, name)
		end
	end
	SquishyBuilder.FACES = table.freeze(list)
end

-- Visage du modèle (v2.0, lot B5, D6 ; Visuals.Faces) : une écriture des tailles des yeux et des
-- reflets, bouche et yeux déplacés par leur décalage (pris à la prochaine pose()). Même visage,
-- visage inconnu, Handle rendu : rien. release() et un modèle repris dans la réserve rendent « happy ».
function SquishyBuilder.setFace(handle: Handle, face: string)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	if type(face) ~= "string" or (face ~= DEFAULT_FACE and FACES[face] == nil) or face == st.face then
		return
	end
	st.face = face
	applyFace(handle, st)
end

-- Visage courant (« happy » pour un Handle rendu ou inconnu)
function SquishyBuilder.faceOf(handle: Handle): string
	local st = states[handle]
	if st == nil or st.released then
		return DEFAULT_FACE
	end
	return st.face
end

-- Facteur des particules de la mutation (budget : 1, 0,3 en qualité réduite, 0 = coupées)
function SquishyBuilder.setParticles(handle: Handle, factor: number)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	st.particles = math.clamp(finite(factor, 1), 0, 1)
	local lod = handle.lod
	for j, e in st.record.emitters do
		local rate = st.record.baseRates[j] * st.particles
		e.Rate = rate
		e.Enabled = lod == 1 and rate > 0
	end
end

-- Aura de rareté visible ou non (le renderer la coupe au-delà de son budget)
function SquishyBuilder.setAura(handle: Handle, visible: boolean)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	st.auraOn = visible == true
	local aura = st.record.aura
	if aura then
		aura.Enabled = st.auraOn and handle.lod <= 2
	end
end

-- Animation des aspects qui bougent, à la cadence du renderer : orbiteurs (Glitch, Lunaire, Flop,
-- gouttes de Moonplop), cycle de couleurs de l'Arc-en-ciel (6 s), pas du Glitch (2 par seconde,
-- jamais plus de 3 Hz), clignement des yeux toutes les 3 à 6 s (0,08 s). Mouvement réduit : rendu
-- fixe (aucun changement de couleur, orbiteurs immobiles).
function SquishyBuilder.animate(handle: Handle, t: number, reducedMotion: boolean?)
	local st = states[handle]
	if st == nil or st.released then
		return
	end
	local now = finite(t, 0)
	local reduced = reducedMotion == true
	local rec = st.record
	local mut = mutationDef(handle.spec.mutation)
	local look = if mut then mut.look else nil
	local d = st.d
	for i, p in rec.pieces do
		local orbit = p.orbit
		if orbit and st.visible[i] then
			local a = 2 * math.pi * ((if reduced then 0 else now / orbit.period) + orbit.phase)
			local pos = Vector3.new(orbit.radius * math.cos(a), orbit.height, orbit.radius * math.sin(a)) * d
			handle.offsets[i] = CFrame.new(pos) * p.rot
		end
	end
	if look and not reduced and handle.lod <= 2 then
		local body = rec.body
		if look.hueCycle then
			local h = (now / look.hueCycle) % 1
			body.Color = Color3.fromHSV(h, 0.45, 1)
		elseif look.steps then
			local step = math.floor(now * math.min(look.steps, 3)) % 2
			local color = if step == 0
				then speciesDef(handle.spec.species).colors.main
				else (mut :: Mutations.MutationDef).color
			if body.Color ~= color then
				body.Color = color
			end
		end
	end
	-- clignement : yeux à 10 % de leur hauteur pendant 0,08 s, toutes les 3 à 6 s (v2.0, lot B5 : depuis
	-- la taille du visage courant ; jamais sous un visage qui ferme déjà les yeux)
	local period = 3 + 3 * st.blinkSeed
	local blink = handle.lod <= 2 and (now % period) < 0.08
	local face: FaceDef? = nil
	if st.face ~= DEFAULT_FACE and (blink or st.blinking) then
		face = FACES[st.face]
		if face and not face.blink then
			blink = false
		end
	end
	if blink ~= st.blinking then
		st.blinking = blink
		local alone = rec.glints == 0
		for i, p in rec.pieces do
			if p.role == "eye" then
				local size = if face then faceEyeSize(face, p, alone) * d else p.size * d
				rec.parts[i].Size = if blink then Vector3.new(size.X, size.Y * 0.1, size.Z) else size
			end
		end
	end
end

-- Compteurs de la réserve (specs de budget)
function SquishyBuilder.poolStats(): { pooled: number, looks: number }
	local looks = 0
	for _, pool in pools do
		if #pool > 0 then
			looks += 1
		end
	end
	return { pooled = pooled, looks = looks }
end

-- Vide la réserve (tests, changement de qualité)
function SquishyBuilder.clearPool()
	for _, pool in pools do
		for _, rec in pool do
			rec.model:Destroy()
		end
	end
	table.clear(pools)
	pooled = 0
end

return SquishyBuilder
