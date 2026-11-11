--!strict
-- HelperKit (lot B5, étape 3 ; GDD v2.0 §4.28 ; plan B5 D14, D16) : les 6 recettes des Plopettes et
-- leur réserve. Chaque Plopette est une petite goutte de 5 pièces au plus (corps, pointe de la goutte,
-- deux yeux, un accessoire) :
--   1 Pip   : goutte rose à tablier          4 Pom   : goutte lilas, nœud papillon
--   2 Pop   : goutte menthe, bonnet à pompon 5 Puff  : goutte nuage, cape
--   3 Pim   : goutte citron, lunettes rondes 6 Plume : goutte arc-en-ciel, plume sur la tête
-- Pièces simples (Part), ancrées, CanCollide = CanQuery = CanTouch = false, CastShadow = false, sans
-- texture ni lumière. La goutte est dessinée dans son repère : le pied au sol en (0, 0, 0), le
-- visage vers −Z (CFrame.lookAt la tourne vers sa cible).
--
--   HelperKit.take(helper, parent) → Kit?   -- une Plopette de la réserve (ou neuve), posée sous parent
--   HelperKit.release(kit)                  -- rendue à la réserve (Parent = nil), réutilisée ensuite
--   HelperKit.offsets(kit)                  -- repères locaux des pièces (dans l'ordre de kit.parts)
--   HelperKit.recipe(helper)                -- recette (specs) ; nil hors 1 … 6
--   HelperKit.stats()                       -- { live, pooled, created }
--   HelperKit.COUNT, HelperKit.PARTS        -- 6 recettes, 5 pièces au plus chacune
--   HelperKit.HEIGHT                        -- hauteur d'une Plopette (studs)
--   HelperKit._reset()                      -- specs : vide la réserve (détruit ce qu'elle garde)
-- Réserve par sorte de Plopette (et non par ranch, journal B5-28) : POOL_KEEP au plus de chaque sorte
-- gardées (3 ranchs en détail complet au plus) ; au-delà, une Plopette rendue est détruite. Jamais
-- d'erreur : une sorte inconnue rend nil.

local HelperKit = {}

HelperKit.COUNT = 6
HelperKit.PARTS = 5
HelperKit.HEIGHT = 1.25

local POOL_KEEP = 3

type PieceDef = {
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	at: CFrame, -- repère local (pied de la goutte = origine)
	color: Color3,
}

export type Recipe = { name: string, color: Color3, pieces: { PieceDef } }

export type Kit = {
	helper: number,
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	color: Color3,
}

local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local EYE = Color3.fromRGB(45, 30, 50)

-- Corps, pointe de la goutte et yeux, communs aux 6 recettes (couleur du corps et de la pointe)
local function drop(body: Color3, tip: Color3): { PieceDef }
	return {
		{
			name = "Body",
			shape = BALL,
			size = Vector3.new(1, 0.9, 1),
			at = CFrame.new(0, 0.45, 0),
			color = body,
		},
		{
			name = "Tip",
			shape = BALL,
			size = Vector3.new(0.5, 0.55, 0.5),
			at = CFrame.new(0, 0.95, 0),
			color = tip,
		},
		{
			name = "EyeL",
			shape = BALL,
			size = Vector3.new(0.14, 0.18, 0.08),
			at = CFrame.new(-0.18, 0.55, -0.46),
			color = EYE,
		},
		{
			name = "EyeR",
			shape = BALL,
			size = Vector3.new(0.14, 0.18, 0.08),
			at = CFrame.new(0.18, 0.55, -0.46),
			color = EYE,
		},
	}
end

local function with(pieces: { PieceDef }, extra: PieceDef): { PieceDef }
	table.insert(pieces, extra)
	return pieces
end

local RECIPES: { Recipe } = {
	{
		name = "Pip",
		color = Color3.fromRGB(255, 150, 190),
		pieces = with(drop(Color3.fromRGB(255, 150, 190), Color3.fromRGB(255, 150, 190)), {
			name = "Apron",
			shape = BLOCK,
			size = Vector3.new(0.6, 0.4, 0.06),
			at = CFrame.new(0, 0.28, -0.47),
			color = Color3.fromRGB(255, 255, 255),
		}),
	},
	{
		name = "Pop",
		color = Color3.fromRGB(150, 230, 190),
		-- bonnet : la pointe de la goutte prend la couleur du bonnet, le pompon par-dessus
		pieces = with(drop(Color3.fromRGB(150, 230, 190), Color3.fromRGB(240, 90, 110)), {
			name = "Pompom",
			shape = BALL,
			size = Vector3.new(0.3, 0.3, 0.3),
			at = CFrame.new(0, 1.28, 0),
			color = Color3.fromRGB(255, 255, 255),
		}),
	},
	{
		name = "Pim",
		color = Color3.fromRGB(255, 235, 120),
		-- lunettes : une monture fine posée sur les deux yeux (un disque cacherait les yeux ; en 5 pièces,
		-- la monture et les yeux font les lunettes, journal B5-29)
		pieces = with(drop(Color3.fromRGB(255, 235, 120), Color3.fromRGB(255, 235, 120)), {
			name = "Glasses",
			shape = BLOCK,
			size = Vector3.new(0.62, 0.05, 0.05),
			at = CFrame.new(0, 0.62, -0.47),
			color = Color3.fromRGB(90, 70, 60),
		}),
	},
	{
		name = "Pom",
		color = Color3.fromRGB(200, 170, 240),
		pieces = with(drop(Color3.fromRGB(200, 170, 240), Color3.fromRGB(200, 170, 240)), {
			name = "BowTie",
			shape = BLOCK,
			size = Vector3.new(0.42, 0.14, 0.08),
			at = CFrame.new(0, 0.3, -0.47),
			color = Color3.fromRGB(120, 70, 170),
		}),
	},
	{
		name = "Puff",
		color = Color3.fromRGB(235, 240, 255),
		pieces = with(drop(Color3.fromRGB(235, 240, 255), Color3.fromRGB(235, 240, 255)), {
			name = "Cape",
			shape = BLOCK,
			size = Vector3.new(0.8, 0.6, 0.06),
			at = CFrame.new(0, 0.4, 0.48) * CFrame.Angles(math.rad(-12), 0, 0),
			color = Color3.fromRGB(110, 150, 255),
		}),
	},
	{
		name = "Plume",
		color = Color3.fromRGB(255, 190, 150),
		-- arc-en-ciel en 5 pièces : corps pêche, pointe ciel, plume jaune penchée (journal B5-29)
		pieces = with(drop(Color3.fromRGB(255, 190, 150), Color3.fromRGB(140, 200, 255)), {
			name = "Feather",
			shape = BLOCK,
			size = Vector3.new(0.08, 0.6, 0.18),
			at = CFrame.new(0.12, 1.42, 0.05) * CFrame.Angles(0, 0, math.rad(-20)),
			color = Color3.fromRGB(255, 220, 80),
		}),
	},
}

local pools: { [number]: { Kit } } = {}
local counters = { live = 0, created = 0 }

local function build(helper: number): Kit
	local recipe = RECIPES[helper]
	local model = Instance.new("Model")
	model.Name = "Plopette_" .. recipe.name
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, def in recipe.pieces do
		local p = Instance.new("Part")
		p.Name = def.name
		p.Shape = def.shape
		p.Size = def.size
		p.Color = def.color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = def.at
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, def.at)
	end
	counters.created += 1
	return { helper = helper, model = model, parts = parts, offsets = offsets, color = recipe.color }
end

-- Une Plopette (1 … 6) de la réserve ou neuve, sous `parent` ; nil pour une sorte inconnue
function HelperKit.take(helper: number, parent: Instance): Kit?
	if type(helper) ~= "number" or helper % 1 ~= 0 or helper < 1 or helper > HelperKit.COUNT then
		return nil
	end
	local pool = pools[helper]
	local kit = if pool then table.remove(pool) else nil
	if kit == nil then
		kit = build(helper)
	end
	local k = kit :: Kit
	k.model.Parent = parent
	counters.live += 1
	return k
end

-- Rend une Plopette : gardée (Parent = nil) jusqu'à POOL_KEEP par sorte, détruite au-delà
function HelperKit.release(kit: Kit)
	if type(kit) ~= "table" or kit.model == nil then
		return
	end
	counters.live = math.max(0, counters.live - 1)
	local pool = pools[kit.helper]
	if pool == nil then
		pool = {}
		pools[kit.helper] = pool
	end
	if #pool < POOL_KEEP then
		kit.model.Parent = nil
		table.insert(pool, kit)
	else
		kit.model:Destroy()
	end
end

function HelperKit.offsets(kit: Kit): { CFrame }
	return kit.offsets
end

function HelperKit.recipe(helper: number): Recipe?
	return RECIPES[helper]
end

function HelperKit.stats(): { live: number, pooled: number, created: number }
	local pooled = 0
	for _, pool in pools do
		pooled += #pool
	end
	return { live = counters.live, pooled = pooled, created = counters.created }
end

function HelperKit._reset()
	for _, pool in pools do
		for _, kit in pool do
			kit.model:Destroy()
		end
	end
	table.clear(pools)
	counters.live = 0
	counters.created = 0
end

return HelperKit
