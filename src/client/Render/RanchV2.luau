--!strict
-- RanchV2 (lot B4, étapes 3 et 4 ; docs/04 §27.5, §27.7 ; GDD v2.0 §9.4, §11.5, §12.9 ; décisions
-- D1, D6, D12-D19, D23, D25, D26 du plan B4). État v2.0 de chaque ranch et rendu de ses décors, pour
-- RanchRenderer (qui reste le point d'entrée) :
--   * le client ne lit jamais Config/Features : un ranch dessine ses décors v2.0 tant que son modèle
--     Wobbleton/Ranches/<k> porte l'attribut TapisTier (RanchTiers), avec BestR (Record R, sinon le r
--     public), DecorGold, GoldPennants, Cushions ; une connexion AttributeChanged par modèle (branchée
--     à la demande, muette interrupteurs coupés) et les patchs du ranch (WorldStateController) marquent
--     le ranch à revoir ; un attribut qui disparaît rend l'aspect exact de la v1.3 ;
--   * une fonction de rendu idempotente par objet (signature : même état → aucune instance créée,
--     aucune propriété écrite) ; pièces des décors sous ClientWorld/RanchesV2/<k> ; pièces du serveur
--     peintes localement avec leur aspect d'origine gardé (une valeur réécrite entre temps par le
--     serveur devient la nouvelle origine, jamais écrasée au retour) ;
--   * détail par ranch, jamais par distance (RanchLook.currentRanch / detail) : le ranch courant et
--     ses 2 voisins en détail complet, les autres réduits (couleur seulement) ; Graphismes légers ou
--     qualité réduite : seulement mon ranch et le ranch courant ;
--   * budget visuel (Render/VisualBudget) réparti par système dans l'ordre fixe de dégradation ;
--   * cascade de construction (Render/BuildCascade) seulement sur un vrai changement : jamais au
--     chargement, à un changement de propriétaire, de détail ou de budget ;
--   * contenu de l'étape 3 : paliers du Tapis (aspect du grand tapis du serveur + pièces du palier,
--     étincelles du Tapis doré), coussins (style de l'attribut Cushions, étoilés au Record R 11), lit
--     douillet, socles de souvenir (le socle rétrécit en 0,2 s, la décoration sort en cascade avec
--     DecoPlace), décorations dorées (DecorGold), fanions ★ (dorés avec GoldPennants), matériau du Pot
--     pour tous ; tas de pièces et anneau de l'aimant pour MON ranch seulement ; habillages v2.0
--     (HaloOn) appliqués par stepTheme de RanchRenderer ;
--   * contenu de l'étape 4 (Render/RanchTiers, Render/MonumentKit, Render/DecoKit) : les 6 paliers
--     (un objet chacun, détail réduit : tour, phare et couronne en 3 pièces), chiffre romain du Record R
--     sur la plaque de l'arche (SurfaceGui, sorte « fit » de UI/Text), étoiles et couronne arc-en-ciel ;
--     éléments du Record R : Cuve (anneaux, agitateur, buses ; dorée), fontaine du Bassin, 8 lampions
--     (Neon pendant la Jelly Moon, RanchLook.moonLit), portail arc-en-ciel, geyser, étagère dorée,
--     maisonnette des Plopettes ; accessoires de la silhouette (cadre doré, anneau rose « prêt »,
--     anneau-soleil de GiantTier ≥ 3) ; étincelles des buses sur une naissance mutée de MON ranch
--     (onHatch) ; Monuments (attribut Monuments : ranch courant, voisins, autres) et Déco perso
--     (attribut DecoPerso) ; un ranch est allumé par TapisTier, Monuments ou DecoPerso (chacun son
--     interrupteur), tout le reste suit TapisTier ;
--   * crochets pour B5 : detail(slot), elementCFrame(slot, id), signal ElementBuilt(slot, id) (premier
--     passage seulement), et Render/BuildCascade.Piece ; lanternPart(slot) pour LightingController
--     (lumière du phare de MON ranch, D23) ;
--   * travail par image seulement tant qu'un ranch v2.0 existe (RanchV2.on) : la cascade quand elle
--     joue, les pièces animées à 15 Hz (galaxie, étoiles, pièces qui sautillent, couronne et lanterne
--     qui tournent, agitateur, goutte du geyser, anneau « prêt » qui pulse : 3 changements de couleur
--     par seconde au plus) ; Mouvement réduit : tout immobile à sa pose de base.
-- Jamais d'erreur : un attribut illisible donne l'aspect sûr, un modèle ou un personnage absent ne
-- dessine rien.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Visuals = require(Shared.Config.Visuals)
local RanchLook = require(Shared.Logic.RanchLook)
local Prestige = require(Shared.Logic.Prestige)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Formulas = require(Shared.Logic.Formulas)
local SizeScale = require(Shared.Logic.SizeScale)
local Clock = require(Shared.Util.Clock)
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local Util = require(Client.World.Util)
local VisualBudget = require(script.Parent.VisualBudget)
local BuildCascade = require(script.Parent.BuildCascade)
local RanchKit = require(script.Parent.RanchKit)
local RanchTiers = require(script.Parent.RanchTiers)
local MonumentKit = require(script.Parent.MonumentKit)
local DecoKit = require(script.Parent.DecoKit)
local SkyKit = require(script.Parent.SkyKit)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Theme = require(Client.UI.Theme)

local RanchV2 = {}

-- Crochets pour B5 (D25, plan B4 §2.2) : un élément du ranch vient d'être construit pour de vrai
-- (premier passage, joué en cascade) : (slot, identifiant de l'élément)
RanchV2.ElementBuilt = Signal.new() :: Signal.Signal<number, string>

-- Au moins un ranch v2.0 (ou un décor à défaire) : RanchRenderer n'appelle step que si vrai
RanchV2.on = false
-- Les 16 modèles sont écoutés : RanchRenderer n'appelle plus watch
RanchV2.watchedAll = false

local RANCHES = WorldLayout.Const.Ranches
local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local TIERS_MAX = 6
local DECOR_MAX = Balance.Tiles.decor.Levels
local ANIM_HZ = 15
local SLOW = 0.5 -- s : tas du Pot et anneau de l'aimant de MON ranch
local SHRINK = 0.2 -- s : le socle rétrécit avant que la décoration sorte
local RING_MARGIN = 8 -- studs : l'anneau se montre jusqu'au rayon + 8
local SPARKLE_RATE = 2 -- étincelles par seconde du Tapis doré (GDD §11.5)
local SPARKLE_PARTICLES = 2 -- particules à l'écran par Tapis doré (budget « tapis » ≤ 6)
local STRING_MAX = 32

-- Attributs qui changent les décors des étapes 3 et 4 (le reste viendra à l'étape 5)
local WATCHED: { [string]: boolean } = {
	TapisTier = true,
	BestR = true,
	DecorGold = true,
	GoldPennants = true,
	Cushions = true,
	OwnerUserId = true,
	SplorchReady = true,
	Monuments = true,
	DecoPerso = true,
	GiantTier = true,
	Ascend = true, -- étape 5 : ciel des Ascensions [JellyAscend]
}
-- Un de ces attributs allume les décors v2.0 du ranch (RanchTiers, Monuments, DecoPerso : D1)
local CARRIERS = { "TapisTier", "Monuments", "DecoPerso" }
local CARRIER: { [string]: boolean } = { TapisTier = true, Monuments = true, DecoPerso = true }

-- Objets dessinés et système du budget visuel de chacun ; fanions ★ comptés avec les socles (une
-- décoration gardée porte un fanion OU est un socle, jamais les deux : 18 × 2 par ranch)
local OBJ_SYSTEM: { [string]: string } = {
	tapis = "tapis",
	cushions = "tapis",
	bed = "tapis",
	plinths = "plinths",
	pennants = "plinths",
	heap = "pot",
	ring = "pot",
	vat = "record",
	fountain = "record",
	lanterns = "record",
	gate = "record",
	geyser = "record",
	house = "house",
	frame = "silhouette",
	ready = "silhouette",
	sun = "silhouette",
	sky = "sky", -- étape 5 : ciel des Ascensions (D25)
}
for k = 1, 6 do
	OBJ_SYSTEM["tier" .. k] = "tiers"
end
for n = 1, MonumentKit.COUNT do
	OBJ_SYSTEM["mon" .. n] = "monuments"
end
local DECO_SLOTS = #Cosmetics.DecoSlots
for i = 1, DECO_SLOTS do
	OBJ_SYSTEM["deco" .. i] = "decoPerso"
end
local SYSTEMS =
	{ "tapis", "record", "plinths", "pot", "tiers", "house", "silhouette", "monuments", "decoPerso", "sky" }

-- Identifiants des éléments (Visuals.RecordTable, Strings monument.n) de chaque objet : ElementBuilt,
-- elementCFrame
local ELEMENT_ID: { [string]: string } = {
	tier1 = "tier1.pompomArch",
	tier2 = "tier2.candyTower",
	tier3 = "tier3.jellyBalcony",
	tier4 = "tier4.jellyLighthouse",
	tier5 = "tier5.neonDome",
	tier6 = "tier6.floatingCrown",
	vat = "vat",
	fountain = "pool.fountain",
	lanterns = "fence.lanterns8",
	gate = "gate.rainbow",
	geyser = "geyser",
	frame = "frame.golden",
	sun = "giant.sun",
	house = "helper.house",
	sky = "sky",
}
for n = 1, MonumentKit.COUNT do
	ELEMENT_ID["mon" .. n] = "monument." .. n
end
for i = 1, DECO_SLOTS do
	ELEMENT_ID["deco" .. i] = "deco." .. i
end
-- Objets sans cascade : signal (anneau « prêt »)
local NO_CASCADE: { [string]: boolean } = { ready = true }
local NUMERAL_CANVAS = Vector2.new(320, 120) -- px de la plaque du chiffre romain (3,2 × 1,2 studs)
local NUMERAL_TEXT = 96 -- px : plus grande taille « fit » du chiffre romain
local NUMERAL_COLOR = Color3.fromRGB(110, 40, 90)
local SPARK_SPEED = NumberRange.new(2, 4)
local SPARK_LIFE = 0.8 -- s : l'émetteur d'une étincelle est détruit après sa particule

type Painted = { color: Color3, material: Enum.Material, paintColor: Color3, paintMaterial: Enum.Material }
type Paint = { part: BasePart, color: Color3, material: Enum.Material }
type Obj = {
	sig: string,
	specs: { [string]: RanchKit.Spec },
	parts: { [string]: BasePart },
	paints: { [BasePart]: boolean },
	extra: { Instance },
	inited: boolean,
	owner: number,
	level: string,
	data: any, -- état propre à l'objet (socles montrés)
}
type View = {
	owner: number,
	tapis: boolean, -- le ranch porte TapisTier (RanchTiers) : décors des étapes 3 et 4 sauf Monuments, Déco perso
	tier: number, -- palier du Tapis (TapisTier)
	bestR: number,
	gold: number,
	goldPennants: boolean,
	cushions: string,
	snack: number,
	decor: number,
	pens: number,
	cozyBed: boolean,
	color: Color3,
	has: { [string]: boolean }, -- éléments visibles (RanchLook.elements)
	ranchTier: number, -- palier du ranch 0 … 6 (RanchLook.tier)
	vat: RanchLook.VatLook,
	vatBuilt: boolean,
	poolBuilt: boolean,
	ready: boolean, -- SplorchReady
	giant: number, -- GiantTier
	monuments: number, -- 0 … 10 ; −1 sans attribut (Monuments coupé)
	deco: { number }?, -- 12 numéros sûrs ; nil sans attribut (DecoPerso coupé)
	radius: number, -- rayon montré de la silhouette, arrondi (0 : aucune silhouette)
	stars: number, -- étoiles de couronne 0 … 4
	rainbow: boolean, -- couronne arc-en-ciel
	ascend: number, -- A (attribut Ascend [JellyAscend]) ; 0 sans attribut : aucun ciel
}
type Slot = {
	slot: number,
	model: Instance?,
	conn: any,
	on: boolean,
	dirty: boolean,
	owner: number,
	detail: string,
	grants: { [string]: string },
	want: { [string]: VisualBudget.Want },
	objs: { [string]: Obj },
	folder: Folder?,
	saved: { [BasePart]: Painted },
	skin: { [BasePart]: boolean },
	decorParts: { [number]: { BasePart } },
	heap: number,
	ring: number, -- rayon montré (0 : aucun)
	view: View?,
}
type Anim = { slot: number, spec: RanchKit.Spec, still: boolean, idx: number }
type Shrink = { slot: number, parts: { BasePart }, sizes: { Vector3 }, t: number }

local slots: { [number]: Slot } = {}
local anims: { [BasePart]: Anim } = {}
local shrinking: { Shrink } = {}
-- étincelles des buses de MA Cuve en vol (une particule par buse, détruites après SPARK_LIFE)
local sparks: { { slot: number, emitter: ParticleEmitter, t: number } } = {}
local hooks: { skinChanged: ((number) -> ())? } = {}
local declared = false
local anyDirty = false
local current = 0
local moon = false -- Jelly Moon en cours (lampions allumés), revue toutes les 0,5 s
local animAcc = 0
local animTime = 0
local slowAcc = 0
local rootFolder: Folder? = nil
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local counters = { renders = 0, created = 0, destroyed = 0, cascades = 0, animWrites = 0 }

local EMPTY: { any } = table.freeze({}) :: any

-- =============================================================================================
-- Outils
-- =============================================================================================

local function ranchModel(slot: number): Instance?
	local root = workspace:FindFirstChild("Wobbleton")
	local list = root and root:FindFirstChild("Ranches")
	return list and list:FindFirstChild(tostring(slot))
end

local function int(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

local function mySlot(): number
	return Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot)
end

local function lowQuality(): boolean
	return Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics)
		or Util.safe("QualityController.reduced", false, QualityController.reduced)
end

local function reducedMotion(): boolean
	return Util.safe("Prefs.reducedMotion", false, Prefs.reducedMotion)
end

local function particleFactor(): number
	if Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics) then
		return 0
	end
	local b = Util.safe("QualityController.budgets", nil, QualityController.budgets)
	return Util.num(if type(b) == "table" then (b :: any).particles else 1, 1, 0, 1)
end

-- Clé de couleur (signatures) : teinte, saturation, valeur, identique d'un appel à l'autre
local function hex(c: Color3): string
	local h, sat, v = c:ToHSV()
	return string.format("%.4f,%.4f,%.4f", h, sat, v)
end

local function newObj(): Obj
	return {
		sig = "",
		specs = {},
		parts = {},
		paints = {},
		extra = {},
		inited = false,
		owner = 0,
		level = "",
		data = nil,
	}
end

local function stateOf(slot: number): Slot
	local st = slots[slot]
	if st == nil then
		st = {
			slot = slot,
			model = nil,
			conn = nil,
			on = false,
			dirty = false,
			owner = 0,
			detail = "reduced",
			grants = {},
			want = {},
			objs = {},
			folder = nil,
			saved = {},
			skin = {},
			decorParts = {},
			heap = 0,
			ring = 0,
			view = nil,
		}
		slots[slot] = st
	end
	return st
end

-- Dossier ClientWorld/RanchesV2/<k> (créé au premier décor seulement)
local function folderOf(st: Slot): Folder
	local f = st.folder
	if f and f.Parent ~= nil then
		return f
	end
	local root = rootFolder
	if root == nil or root.Parent == nil then
		local world = workspace:FindFirstChild("ClientWorld")
		if world == nil then
			local created = Instance.new("Folder")
			created.Name = "ClientWorld"
			created.Parent = workspace
			world = created
		end
		local found = (world :: Instance):FindFirstChild("RanchesV2")
		if found == nil or not found:IsA("Folder") then
			local created = Instance.new("Folder")
			created.Name = "RanchesV2"
			created.Parent = world
			found = created
		end
		rootFolder = found :: Folder
		root = found :: Folder
	end
	local made = Instance.new("Folder")
	made.Name = tostring(st.slot)
	made.Parent = root
	st.folder = made
	return made
end

-- Retire les dossiers vides (interrupteur coupé : aucune instance v2.0 ne reste)
local function pruneFolder(st: Slot)
	local f = st.folder
	if f and #f:GetChildren() == 0 then
		f:Destroy()
		st.folder = nil
	end
	local root = rootFolder
	if root and root.Parent ~= nil and #root:GetChildren() == 0 then
		root:Destroy()
		rootFolder = nil
	end
end

-- =============================================================================================
-- Pièces du serveur peintes localement (aspect d'origine gardé)
-- =============================================================================================

local function paint(st: Slot, part: BasePart, color: Color3, material: Enum.Material)
	local rec = st.saved[part]
	if rec == nil then
		rec = { color = part.Color, material = part.Material, paintColor = color, paintMaterial = material }
		st.saved[part] = rec
	else
		-- réécrite par le serveur depuis notre peinture : sa valeur devient l'origine
		if part.Color ~= rec.paintColor then
			rec.color = part.Color
		end
		if part.Material ~= rec.paintMaterial then
			rec.material = part.Material
		end
		rec.paintColor = color
		rec.paintMaterial = material
	end
	if part.Color ~= color then
		part.Color = color
	end
	if part.Material ~= material then
		part.Material = material
	end
end

local function unpaint(st: Slot, part: BasePart)
	local rec = st.saved[part]
	if rec == nil then
		return
	end
	st.saved[part] = nil
	if part.Parent == nil then
		return
	end
	-- une valeur réécrite par le serveur entre temps reste telle quelle
	if part.Color == rec.paintColor and part.Color ~= rec.color then
		part.Color = rec.color
	end
	if part.Material == rec.paintMaterial and part.Material ~= rec.material then
		part.Material = rec.material
	end
end

-- =============================================================================================
-- Objets : rendu idempotent
-- =============================================================================================

local function forget(part: BasePart)
	anims[part] = nil
	counters.destroyed += 1
	part:Destroy()
end

-- Met l'objet `key` dans l'état voulu (pièces `specs`, peintures `paints`) si sa signature change ;
-- `keep(specKey, part)` peut garder une pièce retirée (socle qui rétrécit). Rend les pièces créées.
local function update(
	st: Slot,
	key: string,
	sig: string,
	specs: { RanchKit.Spec },
	paints: { Paint },
	keep: ((string, BasePart) -> boolean)?
): ({ BasePart }, { RanchKit.Spec })
	local obj = st.objs[key]
	if obj == nil then
		obj = newObj()
		st.objs[key] = obj
	end
	if obj.sig == sig then
		return EMPTY, EMPTY
	end
	counters.renders += 1
	-- une cascade de cet objet en cours se termine sur ses poses finales avant tout changement
	BuildCascade.finish(st.slot, key)
	local created: { BasePart } = {}
	local createdSpecs: { RanchKit.Spec } = {}
	local wanted: { [string]: boolean } = {}
	for _, spec in specs do
		wanted[spec.key] = true
		local part = obj.parts[spec.key]
		local prev = obj.specs[spec.key]
		if part and part.Parent ~= nil and prev and prev.shape == spec.shape then
			if not RanchKit.same(spec, prev) then
				RanchKit.apply(part, spec, prev)
				local a = anims[part]
				if a then
					a.spec = spec
					a.still = false
					a.idx = -1
				end
			end
		else
			if part then
				forget(part)
			end
			part = RanchKit.create(spec, folderOf(st))
			counters.created += 1
			obj.parts[spec.key] = part
			table.insert(created, part :: BasePart)
			table.insert(createdSpecs, spec)
			if spec.anim then
				anims[part :: BasePart] = { slot = st.slot, spec = spec, still = false, idx = -1 }
			end
		end
		obj.specs[spec.key] = spec
	end
	for k, part in obj.parts do
		if not wanted[k] then
			obj.parts[k] = nil
			obj.specs[k] = nil
			if keep and part.Parent ~= nil and keep(k, part) then
				anims[part] = nil
			else
				forget(part)
			end
		end
	end
	local now: { [BasePart]: boolean } = {}
	for _, p in paints do
		now[p.part] = true
		paint(st, p.part, p.color, p.material)
		obj.paints[p.part] = true
	end
	for part in obj.paints do
		if not now[part] then
			obj.paints[part] = nil
			unpaint(st, part)
		end
	end
	obj.sig = sig
	return created, createdSpecs
end

-- Vrai changement (cascade) : objet déjà rendu pour ce propriétaire, au même niveau de détail
local function realChange(st: Slot, key: string, level: string): boolean
	local obj = st.objs[key]
	return obj ~= nil and obj.inited and obj.owner == st.owner and obj.level == level and st.owner ~= 0
end

local function markRendered(st: Slot, key: string, level: string)
	local obj = st.objs[key]
	if obj then
		obj.inited = true
		obj.owner = st.owner
		obj.level = level
	end
end

-- Pousse la cascade des pièces créées (détail complet seulement)
local function cascade(st: Slot, key: string, parts: { BasePart }, specs: { RanchKit.Spec }, sound: string?)
	if #parts == 0 then
		return
	end
	local finals: { CFrame } = {}
	local sizes: { Vector3 } = {}
	for i, spec in specs do
		finals[i] = spec.cf
		sizes[i] = spec.size
	end
	if
		BuildCascade.push({
			slot = st.slot,
			id = key,
			parts = parts,
			finals = finals,
			sizes = sizes,
			sound = sound,
		})
	then
		counters.cascades += 1
	end
end

-- Rendu d'un objet de pièces v2.0 avec cascade sur un vrai changement (premier passage d'un élément,
-- jamais au chargement, au changement de propriétaire ni de détail) ; ElementBuilt pour B5
local function renderParts(
	st: Slot,
	key: string,
	sig: string,
	specs: { RanchKit.Spec },
	level: string,
	sound: string?
)
	local real = realChange(st, key, level)
	local created, createdSpecs = update(st, key, sig, specs, EMPTY :: any)
	if real and level == "full" and #created > 0 and not NO_CASCADE[key] then
		cascade(st, key, created, createdSpecs, sound)
		local id = ELEMENT_ID[key]
		if id then
			RanchV2.ElementBuilt:Fire(st.slot, id)
		end
	end
	markRendered(st, key, level)
end

-- Détruit tous les objets d'un ranch et rend les peintures (aspect exact de la v1.3)
local function clearSlot(st: Slot)
	BuildCascade.flush(st.slot)
	for i = #sparks, 1, -1 do
		local sp = sparks[i]
		if sp.slot == st.slot then
			sp.emitter:Destroy()
			VisualBudget.release("record", 1, "particles")
			table.remove(sparks, i)
		end
	end
	for key, obj in st.objs do
		for _, part in obj.parts do
			forget(part)
		end
		for _, inst in obj.extra do
			inst:Destroy()
			-- étincelles du Tapis doré : leur réservation de particules est rendue (sans cela, le
			-- quota « tapis » fuyait à chaque Tapis doré retiré, B4-41)
			if key == "tapis" then
				VisualBudget.release("tapis", SPARKLE_PARTICLES, "particles")
			end
		end
		for part in obj.paints do
			unpaint(st, part)
		end
		st.objs[key] = nil
	end
	for i = #shrinking, 1, -1 do
		local s = shrinking[i]
		if s.slot == st.slot then
			for _, part in s.parts do
				part:Destroy()
			end
			table.remove(shrinking, i)
		end
	end
	pruneFolder(st)
end

-- =============================================================================================
-- Lecture de l'état v2.0 d'un ranch (attributs validés + ranch public)
-- =============================================================================================

local function carries(model: Instance?): boolean
	if model == nil or model.Parent == nil then
		return false
	end
	for _, name in CARRIERS do
		if model:GetAttribute(name) ~= nil then
			return true
		end
	end
	return false
end

-- Rayon montré de la silhouette du meilleur squishy (même calcul que RanchRenderer : taille d'après
-- la croissance, échelle « silhouette »), arrondi au pair (RanchTiers.quantize) ; 0 sans silhouette
local function silhouetteRadius(ranch: any): number
	local best = ranch.best
	if type(best) ~= "table" or type(best.s) ~= "number" or best.s == 0 then
		return 0
	end
	local ok, radius = pcall(function(): number
		local G = Formulas.G(ranch.growth, Clock.now())
		local size = Formulas.clampSize(best.z + (G - best.zg))
		return Balance.SizeScale.BaseDiameter * SizeScale.display(size, "silhouette") / 2
	end)
	return if ok then RanchTiers.quantize(radius) else 0
end

local function readView(st: Slot): View?
	local model = st.model
	if not carries(model) then
		return nil
	end
	local m = model :: Instance
	local ranch = WorldStateController.ranch(st.slot)
	if ranch == nil or ranch.userId == 0 then
		return nil
	end
	local tiles: any = if type(ranch.tiles) == "table" then ranch.tiles else {}
	local tierAttr = m:GetAttribute("TapisTier")
	local bestAttr = m:GetAttribute("BestR")
	local bestR = if type(bestAttr) == "number" and bestAttr == bestAttr
		then int(bestAttr, 0, MAX_R)
		else Prestige.r(ranch :: any)
	local goldAttr = m:GetAttribute("DecorGold")
	local cushionsAttr = m:GetAttribute("Cushions")
	local has: { [string]: boolean } = {}
	for _, id in RanchLook.elements(bestR, 0) do
		has[id] = true
	end
	local stars = 0
	for k = 1, #Visuals.CrownStarsAt do
		if has["crown.star" .. k] then
			stars += 1
		end
	end
	local monAttr = m:GetAttribute("Monuments")
	local decoAttr = m:GetAttribute("DecoPerso")
	return {
		owner = ranch.userId,
		tapis = tierAttr ~= nil,
		tier = int(tierAttr, 0, TIERS_MAX),
		bestR = bestR,
		gold = int(goldAttr, 0, 2 ^ DECOR_MAX - 1),
		goldPennants = m:GetAttribute("GoldPennants") == true,
		cushions = if type(cushionsAttr) == "string" and #cushionsAttr <= STRING_MAX
			then cushionsAttr
			else "",
		snack = int(tiles.snack, 0, Balance.Tiles.snack.Levels),
		decor = int(tiles.decor, 0, DECOR_MAX),
		pens = int(tiles.pens, 0, Balance.Tiles.pens.Levels),
		cozyBed = tiles.cozyBed == true,
		color = Cosmetics.RanchColors[st.slot] or Cosmetics.FreeRanchColor,
		has = has,
		ranchTier = RanchLook.tier(bestR),
		vat = RanchLook.vat(bestR),
		vatBuilt = ranch.vat == true,
		poolBuilt = ranch.pool == true,
		ready = m:GetAttribute("SplorchReady") == true,
		giant = int(m:GetAttribute("GiantTier"), 0, 99),
		monuments = if monAttr == nil then -1 else int(monAttr, 0, MonumentKit.COUNT),
		deco = if decoAttr == nil then nil else RanchLook.decoPerso(decoAttr),
		radius = silhouetteRadius(ranch),
		stars = stars,
		rainbow = has["crown.rainbow"] == true,
		ascend = int(m:GetAttribute("Ascend"), 0, MAX_A),
	}
end

-- Pièces d'une décoration du serveur (Decor/<k>), gardées après la première lecture
local function decorParts(st: Slot, k: number): { BasePart }
	local cached = st.decorParts[k]
	if cached and (cached[1] == nil or cached[1].Parent ~= nil) then
		return cached
	end
	local out: { BasePart } = {}
	local model = st.model
	local holder = model and model:FindFirstChild("Decor")
	local deco = holder and holder:FindFirstChild(tostring(k))
	if deco then
		for _, d in deco:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	st.decorParts[k] = out
	return out
end

-- =============================================================================================
-- Budgets voulus (pièces en détail complet)
-- =============================================================================================

local function plinthList(view: View): { number }
	local out: { number } = {}
	for k = 1, DECOR_MAX do
		if RanchLook.decorState(k, view.decor, view.bestR) == "plinth" then
			table.insert(out, k)
		end
	end
	return out
end

local function pennantList(view: View): { number }
	local out: { number } = {}
	for k = 1, RanchLook.pennants(view.bestR) do
		if view.decor >= k then
			table.insert(out, k)
		end
	end
	return out
end

local ZERO_WANT: VisualBudget.Want = table.freeze({ full = 0, reduced = 0 }) :: any

-- Niveau naturel des Monuments d'un ranch : « full » (ranch courant), « near » (ses voisins en détail
-- complet), « reduced » (les autres)
local function monumentNatural(st: Slot): string
	if st.detail ~= "full" then
		return "reduced"
	end
	return if st.slot == current then "full" else "near"
end

-- Niveau naturel du ciel d'un ranch (SkyKit) : « near » (ranch courant), « mid » (ses voisins en
-- détail complet), « far » (les autres)
local function skyNatural(st: Slot): string
	if st.detail ~= "full" then
		return "far"
	end
	return if st.slot == current then "near" else "mid"
end

local function tierWants(view: View, full: boolean): (number, number)
	local f, r = 0, 0
	for k = 1, view.ranchTier do
		f += RanchTiers.TIER_PARTS[k]
		r += RanchTiers.REDUCED_PARTS[k]
	end
	if view.ranchTier >= 6 then
		f += view.stars * RanchTiers.STAR_PARTS
	end
	return if full then f else r, r
end

local function vatState(view: View): RanchTiers.VatState
	local v = view.vat
	return {
		rings = v.rings,
		nozzles = v.nozzles,
		period = v.stirrerPeriod,
		rainbow = v.rainbow,
		golden = v.golden,
	}
end

local function recordWant(view: View): number
	local n = 0
	if view.vatBuilt then
		n += RanchTiers.vatCount(vatState(view))
	end
	if view.has["pool.fountain"] and view.poolBuilt then
		n += RanchTiers.FOUNTAIN_PARTS
	end
	if view.has["fence.lanterns8"] then
		n += RanchTiers.LANTERN_PARTS
	end
	if view.has["gate.rainbow"] then
		n += RanchTiers.GATE_PARTS
	end
	if view.has["geyser"] then
		n += RanchTiers.GEYSER_PARTS
	end
	return n
end

local function silhouetteWant(view: View): number
	if view.radius <= 0 then
		return 0
	end
	return (if view.has["frame.golden"] then RanchTiers.FRAME_PARTS else 0)
		+ (if view.ready then RanchTiers.READY_PARTS else 0)
		+ (if view.giant >= 3 then RanchTiers.SUN_PARTS else 0)
end

local function computeWants(st: Slot)
	local view = st.view
	local full = st.detail == "full"
	for _, sys in SYSTEMS do
		st.want[sys] = ZERO_WANT
	end
	if view == nil then
		return
	end
	local v = view :: View
	if v.tapis then
		local tf, tr = tierWants(v, full)
		st.want.tiers = { full = tf, reduced = tr }
		if full then
			st.want.tapis = {
				full = RanchKit.tapisCount(v.tier) + RanchLook.cushions(v.pens, 0) + (if v.cozyBed
					then 10
					else 0),
				reduced = 0,
			}
			st.want.plinths = { full = 2 * (#plinthList(v) + #pennantList(v)), reduced = 0 }
			st.want.record = { full = recordWant(v), reduced = 0 }
			st.want.house =
				{ full = if v.has["helper.house"] then RanchTiers.HOUSE_PARTS else 0, reduced = 0 }
			st.want.silhouette = { full = silhouetteWant(v), reduced = 0 }
			if st.slot == mySlot() then
				st.want.pot = {
					full = RanchKit.heapCount(st.heap) + (if st.ring > 0 then RanchKit.RING_DOTS else 0),
					reduced = 0,
				}
			end
		end
	end
	if v.tapis and v.ascend >= 1 then
		st.want.sky = {
			full = SkyKit.count(v.ascend, skyNatural(st)),
			reduced = SkyKit.count(v.ascend, "far"),
		}
	end
	if v.monuments > 0 then
		local natural = monumentNatural(st)
		local f, r = 0, 0
		for n = 1, v.monuments do
			f += MonumentKit.count(n, natural)
			r += MonumentKit.count(n, "reduced")
		end
		st.want.monuments = { full = f, reduced = r }
	end
	if v.deco then
		local f, r = 0, 0
		for _, n in v.deco :: { number } do
			if n ~= 0 then
				f += DecoKit.count(n, if full then "full" else "reduced")
				r += DecoKit.count(n, "reduced")
			end
		end
		st.want.decoPerso = { full = f, reduced = r }
	end
end

-- =============================================================================================
-- Rendu des objets de l'étape 3
-- =============================================================================================

local function levelOf(st: Slot, sys: string): string
	return if st.detail == "full" and st.grants[sys] == "full" then "full" else "reduced"
end

-- L'objet a déjà cette signature : rien à construire ni à écrire (rendu idempotent)
local function unchanged(st: Slot, key: string, sig: string, level: string): boolean
	local obj = st.objs[key]
	if obj ~= nil and obj.sig == sig then
		markRendered(st, key, level)
		return true
	end
	return false
end

local function dropSparkles(obj: Obj?)
	if obj == nil then
		return
	end
	for _, inst in obj.extra do
		inst:Destroy()
		VisualBudget.release("tapis", SPARKLE_PARTICLES, "particles")
	end
	table.clear(obj.extra)
end

-- Le ranch garde les étincelles de son Tapis doré après ce rafraîchissement (même règle que
-- renderTapis : Tapis doré, détail complet accordé, particules permises)
local function keepsSparkles(st: Slot): boolean
	local view = st.view
	return st.on
		and view ~= nil
		and view.tapis
		and view.tier == 4
		and levelOf(st, "tapis") == "full"
		and particleFactor() > 0
end

-- Paliers du Tapis : aspect du grand tapis et de ses biscuits (tous les ranchs), pièces du palier
-- et étincelles du Tapis doré (détail complet)
local function renderTapis(st: Slot, view: View?)
	local level = levelOf(st, "tapis")
	local model = st.model
	local snack = model and model:FindFirstChild("SnackMat")
	local look = if view then RanchLook.tapisLook(view.tier) else nil
	if view == nil or look == nil or snack == nil then
		if not unchanged(st, "tapis", "none", level) then
			update(st, "tapis", "none", EMPTY :: any, EMPTY :: any)
			dropSparkles(st.objs.tapis)
			markRendered(st, "tapis", level)
		end
		return
	end
	local v = view :: View
	local tapisLook = look :: RanchLook.TapisLook
	-- 8 % par niveau dans le palier : niveau public du Tapis (1 … 12) ; Tapis Étoilé : le palier seul
	local shade = if v.tier <= 4 then RanchLook.tapisShade(v.snack) else 0
	local factor = particleFactor()
	local sparkle = level == "full" and v.tier == 4 and factor > 0
	local sig = table.concat({ v.tier, shade, level, if sparkle then factor else 0 }, "|")
	if unchanged(st, "tapis", sig, level) then
		return
	end
	local matColor = RanchKit.lighten(tapisLook.mat, shade)
	local material = RanchKit.material(tapisLook.material)
	local paints: { Paint } = {}
	local mat = (snack :: Instance):FindFirstChild("Mat")
	if mat and mat:IsA("BasePart") then
		table.insert(paints, { part = mat, color = matColor, material = material })
	end
	for _, d in (snack :: Instance):GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 3) == "Dot" then
			table.insert(paints, { part = d, color = matColor, material = material })
		end
	end
	local specs = if level == "full" then RanchKit.tapis(st.slot, v.tier, tapisLook) else EMPTY :: any
	local real = realChange(st, "tapis", level)
	local created, createdSpecs = update(st, "tapis", sig, specs, paints)
	local obj = st.objs.tapis
	-- étincelles du Tapis doré : un émetteur sur le tapis du serveur, dans le quota de particules
	if obj then
		local rate = SPARKLE_RATE * factor
		if sparkle and #obj.extra == 0 and mat and mat:IsA("BasePart") then
			if VisualBudget.take("tapis", SPARKLE_PARTICLES, "particles") then
				local e = Instance.new("ParticleEmitter")
				e.Name = "TapisSparkles"
				e.Rate = rate
				e.Lifetime = NumberRange.new(0.8, 1.2)
				e.Speed = NumberRange.new(0.5, 1.5)
				e.Size = NumberSequence.new(0.4)
				e.Color = ColorSequence.new(tapisLook.accents[1] or tapisLook.mat)
				e.LightEmission = 1
				e.EmissionDirection = Enum.NormalId.Top
				e.Parent = mat
				table.insert(obj.extra, e)
			end
		elseif sparkle then
			for _, inst in obj.extra do
				if inst:IsA("ParticleEmitter") and inst.Rate ~= rate then
					inst.Rate = rate
				end
			end
		else
			dropSparkles(obj)
		end
	end
	if real and level == "full" then
		cascade(st, "tapis", created, createdSpecs, nil)
	end
	markRendered(st, "tapis", level)
end

-- Coussins ronds (un par place d'enclos achetée), style de l'attribut Cushions, étoilés au R11
local function renderCushions(st: Slot, view: View?)
	local level = levelOf(st, "tapis")
	if view == nil or level ~= "full" then
		local sig = "none:" .. level
		if not unchanged(st, "cushions", sig, level) then
			renderParts(st, "cushions", sig, EMPTY :: any, level)
		end
		return
	end
	local v = view :: View
	local n = RanchLook.cushions(v.pens, 0)
	local color = RanchLook.cushionStyle(v.cushions) or v.color
	local material = Enum.Material.SmoothPlastic
	if RanchLook.starCushions(v.bestR) then
		local star = RanchLook.STAR_CUSHION
		color = RanchKit.mix(color, star.gold, star.mix)
		material = RanchKit.material(star.material)
	end
	local sig = table.concat({ n, hex(color), material.Name, level }, "|")
	if not unchanged(st, "cushions", sig, level) then
		renderParts(st, "cushions", sig, RanchKit.cushions(st.slot, n, color, material), level)
	end
end

-- Lit douillet : lit à baldaquin et mobile de 3 lunes (tiles.cozyBed)
local function renderBed(st: Slot, view: View?)
	local level = levelOf(st, "tapis")
	if view == nil or level ~= "full" or not (view :: View).cozyBed then
		local sig = "none:" .. level
		if not unchanged(st, "bed", sig, level) then
			renderParts(st, "bed", sig, EMPTY :: any, level)
		end
		return
	end
	local color = RanchKit.lighten((view :: View).color, 0.35)
	local sig = "bed|" .. hex(color) .. "|" .. level
	if not unchanged(st, "bed", sig, level) then
		renderParts(st, "bed", sig, RanchKit.bed(st.slot, color), level)
	end
end

-- Socles de souvenir (décoration k pas construite, Record R ≥ 1) ; socle → décoration : le socle
-- rétrécit en 0,2 s, la décoration du serveur sort en cascade (DecoPlace)
local function renderPlinths(st: Slot, view: View?)
	local level = levelOf(st, "plinths")
	local list = if view and level == "full" then plinthList(view :: View) else EMPTY :: any
	local sig = table.concat(list, ",") .. "|" .. level
	if unchanged(st, "plinths", sig, level) then
		return
	end
	local real = realChange(st, "plinths", level)
	local obj = st.objs.plinths
	local before: { [number]: boolean } = if obj and type(obj.data) == "table" then obj.data else {}
	local built: { [number]: boolean } = {}
	if real and view then
		for k in before do
			if (view :: View).decor >= k then
				built[k] = true -- le socle k devient la décoration k
			end
		end
	end
	local specs: { RanchKit.Spec } = {}
	local shown: { [number]: boolean } = {}
	for _, k in list do
		shown[k] = true
		for _, spec in RanchKit.plinth(st.slot, k) do
			table.insert(specs, spec)
		end
	end
	local leaving: { [number]: { BasePart } } = {}
	local function keep(key: string, part: BasePart): boolean
		local k = tonumber(string.match(key, "%d+$") or "")
		if k and built[k] then
			local l = leaving[k] or {}
			table.insert(l, part)
			leaving[k] = l
			return true
		end
		return false
	end
	update(st, "plinths", sig, specs, EMPTY :: any, keep)
	obj = st.objs.plinths
	if obj then
		obj.data = shown
	end
	for k, parts in leaving do
		local sizes: { Vector3 } = {}
		for i, part in parts do
			sizes[i] = part.Size
		end
		table.insert(shrinking, { slot = st.slot, parts = parts, sizes = sizes, t = 0 })
		-- la décoration du serveur sort en cascade (poses finales = celles du serveur)
		local deco = decorParts(st, k)
		if #deco > 0 then
			local finals: { CFrame } = {}
			for i, part in deco do
				finals[i] = BuildCascade.finalOf(part) or part.CFrame
			end
			if
				BuildCascade.push({
					slot = st.slot,
					id = "decor" .. k,
					parts = deco,
					finals = finals,
					sound = "DecoPlace",
				})
			then
				counters.cascades += 1
			end
		end
	end
	markRendered(st, "plinths", level)
end

-- Décorations dorées (bit k − 1 de DecorGold) : couleur et matériau locaux de leurs pièces
local function renderGolden(st: Slot, view: View?)
	local gold = if view then (view :: View).gold else 0
	local sig = "gold|" .. gold
	if unchanged(st, "golden", sig, "all") then
		return
	end
	local paints: { Paint } = {}
	if gold ~= 0 then
		for k = 1, DECOR_MAX do
			if bit32.btest(gold, bit32.lshift(1, k - 1)) then
				for _, part in decorParts(st, k) do
					-- matériau d'origine (gardé s'il est déjà peint) : le Neon reste en Neon, le reste en Foil
					local rec = st.saved[part]
					local original = if rec then rec.material else part.Material
					local material = if original == Enum.Material.Neon
						then Enum.Material.Neon
						else Enum.Material.Foil
					table.insert(paints, { part = part, color = RanchLook.GOLD, material = material })
				end
			end
		end
	end
	update(st, "golden", sig, EMPTY :: any, paints)
	markRendered(st, "golden", "all")
end

-- Fanions ★ des décorations gardées (Record R 8 : 3, 14 : 6), dorés avec GoldPennants
local function renderPennants(st: Slot, view: View?)
	local level = levelOf(st, "record")
	if view == nil or level ~= "full" then
		local sig = "none:" .. level
		if not unchanged(st, "pennants", sig, level) then
			renderParts(st, "pennants", sig, EMPTY :: any, level)
		end
		return
	end
	local v = view :: View
	local list = pennantList(v)
	local sig = table.concat(list, ",") .. "|" .. (if v.goldPennants then "g" else "c") .. "|" .. level
	if unchanged(st, "pennants", sig, level) then
		return
	end
	local specs: { RanchKit.Spec } = {}
	for _, k in list do
		for _, spec in RanchKit.pennant(st.slot, k, v.color, v.goldPennants) do
			table.insert(specs, spec)
		end
	end
	renderParts(st, "pennants", sig, specs, level)
end

-- Matériau du Pot (tous les ranchs) : cuivre, argent (R2), doré (R6, l'aspect de la v1.3), cristal
local function renderPotMaterial(st: Slot, view: View?)
	local name = if view then RanchLook.potMaterial((view :: View).bestR) else "gold"
	local model = st.model
	local pot = model and model:FindFirstChild("Pot")
	local sig = "pot|" .. name .. "|" .. (if pot then 1 else 0)
	if unchanged(st, "potMat", sig, "all") then
		return
	end
	local look = RanchLook.potLook(name)
	local paints: { Paint } = {}
	if look and pot then
		local material = RanchKit.material(look.material)
		for _, partName in { "Body", "Rim" } do
			local part = pot:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				table.insert(paints, { part = part, color = look.color, material = material })
			end
		end
	end
	update(st, "potMat", sig, EMPTY :: any, paints)
	markRendered(st, "potMat", "all")
end

-- Tas de pièces et anneau de l'aimant : MON ranch seulement (le Pot et le revenu sont privés)
local function renderPot(st: Slot, view: View?)
	local level = levelOf(st, "pot")
	local mine = view ~= nil and st.slot == mySlot() and level == "full"
	local heap = if mine then st.heap else 0
	local ring = if mine then st.ring else 0
	local heapSig = "heap|" .. heap .. "|" .. level
	if not unchanged(st, "heap", heapSig, level) then
		update(st, "heap", heapSig, RanchKit.heap(st.slot, heap), EMPTY :: any)
		markRendered(st, "heap", level)
	end
	local ringSig = "ring|" .. ring .. "|" .. level
	if not unchanged(st, "ring", ringSig, level) then
		update(
			st,
			"ring",
			ringSig,
			if ring > 0 then RanchKit.ring(st.slot, ring) else EMPTY :: any,
			EMPTY :: any
		)
		markRendered(st, "ring", level)
	end
end

-- =============================================================================================
-- Rendu des objets de l'étape 4 : paliers, éléments du Record R, accessoires, Monuments, Déco perso
-- =============================================================================================

-- Niveau accordé par le budget : « full » (détail complet), « reduced » (dessin réduit), « none »
local function grantLevel(st: Slot, sys: string): string
	local g = st.grants[sys]
	if g == nil or g == "none" then
		return "none"
	end
	return if st.detail == "full" and g == "full" then "full" else "reduced"
end

local function tierState(view: View): RanchTiers.TierState
	return { color = view.color, ready = view.ready, stars = view.stars, rainbow = view.rainbow }
end

-- Les 6 paliers (un objet chacun : cascade et ElementBuilt par palier)
local function renderTiers(st: Slot, view: View?)
	local level = if view and view.tapis then grantLevel(st, "tiers") else "none"
	for k = 1, 6 do
		local key = "tier" .. k
		local sig = "none:" .. level
		local v: View? = if view and level ~= "none" and k <= view.ranchTier then view else nil
		if v then
			-- état propre au palier dans la signature : drapeau (tour), lanterne (phare), étoiles (couronne)
			local extra = if k == 2
				then hex(v.color)
				elseif k == 4 then (if v.ready then "ready" else "")
				elseif k == 6 then v.stars .. (if v.rainbow then "r" else "")
				else ""
			sig = table.concat({ k, level, extra }, "|")
		end
		if not unchanged(st, key, sig, level) then
			local specs: { RanchKit.Spec } = EMPTY :: any
			if v then
				specs = if level == "full"
					then RanchTiers.tier(st.slot, k, tierState(v))
					else RanchTiers.tierReduced(st.slot, k, tierState(v))
			end
			renderParts(st, key, sig, specs, level)
		end
	end
end

-- Chiffre romain du Record R sur la plaque de l'arche (SurfaceGui, sorte « fit » de UI/Text, jamais
-- TextScaled) ; détail complet seulement, texte réécrit seulement quand le Record R change
local function renderNumeral(st: Slot, view: View?)
	local obj = st.objs.tier1
	local plate = obj and obj.parts[RanchTiers.PLATE_KEY]
	if obj == nil or plate == nil or plate.Parent == nil or view == nil then
		return
	end
	local data: any = if type(obj.data) == "table" then obj.data else {}
	obj.data = data
	local gui: SurfaceGui? = data.gui
	local label: TextLabel? = data.label
	if gui == nil or label == nil or gui.Parent ~= plate then
		local g = Instance.new("SurfaceGui")
		g.Name = "Numeral"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		g.CanvasSize = NUMERAL_CANVAS
		g.LightInfluence = 0
		g.MaxDistance = 150
		g.ResetOnSpawn = false
		local l = Instance.new("TextLabel")
		l.Name = "Roman"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.FontFace = Theme.Fonts.Title
		l.TextColor3 = NUMERAL_COLOR
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextYAlignment = Enum.TextYAlignment.Center
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = l
		l.Parent = g
		g.Parent = plate
		Text.style(l, "fit", NUMERAL_TEXT, { min = 28, wrapped = false })
		data.gui, data.label, data.text = g, l, nil
		gui, label = g, l
	end
	local text = Format.roman((view :: View).bestR)
	if data.text ~= text then
		data.text = text
		Text.raw(label :: TextLabel, text)
	end
end

-- Cuve : anneaux, agitateur, buses (détail complet, Cuve construite) ; dorée (pièces du serveur) pour tous
local function renderVat(st: Slot, view: View?)
	local level = grantLevel(st, "record")
	local v = view
	local show = v ~= nil and v.tapis and v.vatBuilt and level == "full"
	local vs = if show then vatState(v :: View) else nil
	local sig = if vs
		then table.concat({
			vs.rings,
			vs.nozzles,
			vs.period,
			if vs.rainbow then 1 else 0,
			if vs.golden then 1 else 0,
			level,
		}, "|")
		else "none:" .. level
	if not unchanged(st, "vat", sig, level) then
		renderParts(st, "vat", sig, if vs then RanchTiers.vat(st.slot, vs) else EMPTY :: any, level)
	end
	-- Cuve dorée (Record R 7) : socle, couvercle et tuyau du serveur en or, sur tous les ranchs
	local golden = v ~= nil and v.tapis and v.vatBuilt and v.vat.golden
	local model = st.model
	local vat = model and model:FindFirstChild("Vat")
	local gsig = "vatGold|" .. (if golden then 1 else 0) .. "|" .. (if vat then 1 else 0)
	if not unchanged(st, "vatGold", gsig, "all") then
		local paints: { Paint } = {}
		if golden and vat then
			for _, name in { "Base", "Lid", "Pipe" } do
				local part = (vat :: Instance):FindFirstChild(name)
				if part and part:IsA("BasePart") then
					table.insert(
						paints,
						{ part = part, color = RanchLook.GOLD, material = Enum.Material.Foil }
					)
				end
			end
		end
		update(st, "vatGold", gsig, EMPTY :: any, paints)
		markRendered(st, "vatGold", "all")
	end
end

-- Étagère dorée (Record R 19) : pièces de l'étagère du serveur en or, sur tous les ranchs
local function renderShelf(st: Slot, view: View?)
	local golden = view ~= nil and (view :: View).tapis and (view :: View).has["shelf.golden"] == true
	local model = st.model
	local shelf = model and model:FindFirstChild("Shelf")
	local sig = "shelf|" .. (if golden then 1 else 0) .. "|" .. (if shelf then 1 else 0)
	if unchanged(st, "shelfGold", sig, "all") then
		return
	end
	local paints: { Paint } = {}
	if golden and shelf then
		for _, d in (shelf :: Instance):GetChildren() do
			if d:IsA("BasePart") then
				table.insert(paints, { part = d, color = RanchLook.GOLD, material = Enum.Material.Foil })
			end
		end
	end
	update(st, "shelfGold", sig, EMPTY :: any, paints)
	markRendered(st, "shelfGold", "all")
end

-- Un élément simple du Record R (détail complet) : `show` dit s'il est là, `build` ses pièces
local function renderElement(
	st: Slot,
	key: string,
	sys: string,
	show: boolean,
	extra: string,
	build: () -> { RanchKit.Spec }
)
	local level = grantLevel(st, sys)
	local on = show and level == "full"
	local sig = if on then key .. "|" .. extra .. "|" .. level else "none:" .. level
	if not unchanged(st, key, sig, level) then
		renderParts(st, key, sig, if on then build() else EMPTY :: any, level)
	end
end

-- Élément `id` visible sur ce ranch (décors derrière TapisTier)
local function hasEl(view: View?, id: string): boolean
	return view ~= nil and view.tapis and view.has[id] == true
end

local function renderRecord(st: Slot, view: View?)
	local t = view ~= nil and view.tapis
	local poolBuilt = view ~= nil and view.poolBuilt
	renderElement(st, "fountain", "record", hasEl(view, "pool.fountain") and poolBuilt, "", function()
		return RanchTiers.fountain(st.slot)
	end)
	renderElement(
		st,
		"lanterns",
		"record",
		hasEl(view, "fence.lanterns8"),
		if moon then "moon" else "",
		function()
			return RanchTiers.lanterns(st.slot, moon)
		end
	)
	renderElement(st, "gate", "record", hasEl(view, "gate.rainbow"), "", function()
		return RanchTiers.rainbowGate(st.slot)
	end)
	renderElement(st, "geyser", "record", hasEl(view, "geyser"), "", function()
		return RanchTiers.geyser(st.slot)
	end)
	renderElement(st, "house", "house", hasEl(view, "helper.house"), "", function()
		return RanchTiers.house(st.slot)
	end)
	local r = if view then view.radius else 0
	local ready = view ~= nil and view.ready
	local giant = if view then view.giant else 0
	renderElement(st, "frame", "silhouette", r > 0 and hasEl(view, "frame.golden"), tostring(r), function()
		return RanchTiers.frame(st.slot, r)
	end)
	renderElement(st, "ready", "silhouette", t and r > 0 and ready, tostring(r), function()
		return RanchTiers.readyRing(st.slot, r)
	end)
	renderElement(st, "sun", "silhouette", t and r > 0 and giant >= 3, tostring(r), function()
		return RanchTiers.sunRing(st.slot, r)
	end)
end

-- Monuments 1 … n (attribut Monuments) : 20 pièces pour le ranch courant, 6 pour ses voisins, une
-- silhouette pour les autres (D17) ; un nouveau Monument sort en cascade
local function renderMonuments(st: Slot, view: View?)
	local n = if view then (view :: View).monuments else -1
	local grant = grantLevel(st, "monuments")
	local level = if grant == "full"
		then monumentNatural(st)
		elseif grant == "reduced" then "reduced"
		else "none"
	for k = 1, MonumentKit.COUNT do
		local key = "mon" .. k
		local on = level ~= "none" and k <= n
		local sig = if on then key .. "|" .. level else "none:" .. level
		if not unchanged(st, key, sig, level) then
			renderParts(
				st,
				key,
				sig,
				if on then MonumentKit.specs(st.slot, k, level) else EMPTY :: any,
				level
			)
		end
	end
end

-- Déco perso (attribut DecoPerso, RanchLook.decoPerso) : un objet par emplacement ; détail complet :
-- le dessin, réduit : la silhouette des grands ; un objet posé sort en cascade (DecoPlace)
local function renderDeco(st: Slot, view: View?)
	local list = if view then (view :: View).deco else nil
	local grant = grantLevel(st, "decoPerso")
	for i = 1, DECO_SLOTS do
		local key = "deco" .. i
		local n = if list and grant ~= "none" then (list :: { number })[i] or 0 else 0
		-- niveau du ranch même pour un emplacement vide : l'objet posé ensuite est un vrai changement
		local level = grant
		local count = if n ~= 0 then DecoKit.count(n, level) else 0
		local sig = if count > 0 then key .. "|" .. n .. "|" .. level else "none:" .. level
		if not unchanged(st, key, sig, level) then
			renderParts(
				st,
				key,
				sig,
				if count > 0 then DecoKit.specs(st.slot, i, n, level) else EMPTY :: any,
				level,
				"DecoPlace"
			)
		end
	end
end

-- Ciel des Ascensions (D25, étape 5) au-dessus de la clôture du fond : le dessin de A (SkyKit), au
-- niveau du ranch (courant, voisin, autres) ; une Ascension de plus construit le nouvel élément pièce
-- par pièce (cascade), jamais au chargement ni au changement de ranch ; derrière TapisTier et Ascend
local function renderSky(st: Slot, view: View?)
	local a = if view and view.tapis then view.ascend else 0
	local grant = grantLevel(st, "sky")
	local level = if grant == "full" then skyNatural(st) elseif grant == "reduced" then "far" else "none"
	local on = a >= 1 and level ~= "none"
	local sig = if on then "sky|" .. a .. "|" .. level else "none:" .. level
	-- niveau de cascade : le ciel du ranch courant joue sa cascade comme un élément en détail complet
	local cascadeLevel = if level == "near" then "full" else level
	if not unchanged(st, "sky", sig, cascadeLevel) then
		renderParts(
			st,
			"sky",
			sig,
			if on then SkyKit.specs(st.slot, a, level) else EMPTY :: any,
			cascadeLevel
		)
	end
end

local function renderSlot(st: Slot)
	local view = st.view
	local owner = if view then view.owner else 0
	if owner ~= st.owner then
		-- nouveau propriétaire, premier rendu ou ranch libéré : rien ne joue, tout est posé tel quel
		BuildCascade.flush(st.slot)
		st.owner = owner
	end
	if view == nil then
		clearSlot(st)
		return
	end
	-- décors des étapes 3 et 4 derrière TapisTier (RanchTiers) ; Monuments et Déco perso à part
	local tv = if view.tapis then view else nil
	renderTapis(st, tv)
	renderCushions(st, tv)
	renderBed(st, tv)
	renderPlinths(st, tv)
	renderGolden(st, tv)
	renderPennants(st, tv)
	renderPotMaterial(st, tv)
	renderPot(st, tv)
	renderTiers(st, view)
	renderNumeral(st, tv)
	renderVat(st, view)
	renderShelf(st, view)
	renderRecord(st, view)
	renderMonuments(st, view)
	renderDeco(st, view)
	renderSky(st, view)
	pruneFolder(st)
end

-- =============================================================================================
-- Détail par ranch (D6)
-- =============================================================================================

local function detailFor(slot: number, cur: number, my: number, low: boolean): string
	if low then
		return if slot == cur or (slot == my and my ~= 0) then "full" else "reduced"
	end
	return RanchLook.detail(slot, cur)
end

local function updateDetail()
	local my = mySlot()
	local root = Util.localRoot()
	current = RanchLook.currentRanch(current, my, if root then root.Position else nil)
	local low = lowQuality()
	for slot, st in slots do
		if st.on then
			local d = detailFor(slot, current, my, low)
			if d ~= st.detail then
				st.detail = d
				st.dirty = true
				anyDirty = true
			end
		end
	end
end

-- Détail d'un ranch (« full » | « reduced ») : B5 et la cascade le lisent. Lot B5, étape 2 (défaut du
-- crochet, journal B5-13) : tant qu'aucun ranch ne porte de décor v2.0, step ne tourne pas et personne
-- ne tient le ranch courant à jour (il restait à 0 : « reduced » partout, donc ni saynète ni Plopette
-- avec les seuls interrupteurs du lot B5 ouverts) ; il est alors relu ici, à la demande
function RanchV2.detail(slot: number): string
	if type(slot) ~= "number" or slot ~= slot then
		return "reduced"
	end
	local my = mySlot()
	if not RanchV2.on then
		local root = Util.localRoot()
		current = RanchLook.currentRanch(current, my, if root then root.Position else nil)
	end
	return detailFor(slot, current, my, lowQuality())
end

-- Ranch courant (où se tient le personnage, D6)
function RanchV2.current(): number
	return current
end

-- Point d'un élément (repère tourné comme le ranch) : clé d'objet → repère WorldLayout
local ELEMENT_KEY: { [string]: string } = {}
for key, id in ELEMENT_ID do
	ELEMENT_KEY[id] = key
end
local TIER_ANCHOR = { "arch", "tower", "balcony", "lighthouse", "dome", "crown" }

local function anchorOf(slot: number, key: string): CFrame?
	local tier = tonumber(string.match(key, "^tier(%d)$") or "")
	if tier and TIER_ANCHOR[tier] then
		return WorldLayout.v2Anchor(slot, TIER_ANCHOR[tier] :: any)
	end
	local mon = tonumber(string.match(key, "^mon(%d+)$") or "")
	if mon then
		return WorldLayout.monumentSlot(slot, mon)
	end
	local deco = tonumber(string.match(key, "^deco(%d+)$") or "")
	if deco then
		return WorldLayout.decoPersoSlot(slot, deco)
	end
	local frame = WorldLayout.ranchCFrame(slot)
	local function at(p: Vector3): CFrame
		return frame * CFrame.new(WorldLayout.toLocal(slot, p))
	end
	if key == "vat" then
		return at(WorldLayout.anchor(slot, "vat"))
	elseif key == "fountain" then
		return at(WorldLayout.anchor(slot, "pool"))
	elseif key == "lanterns" then
		return WorldLayout.v2Anchor(slot, "lantern1")
	elseif key == "gate" then
		return at(WorldLayout.anchor(slot, "gate"))
	elseif key == "geyser" then
		return WorldLayout.v2Anchor(slot, "geyser")
	elseif key == "frame" or key == "sun" then
		return WorldLayout.v2Anchor(slot, "frame")
	elseif key == "house" then
		return at(WorldLayout.helperHouse(slot))
	elseif key == "sky" then
		return WorldLayout.v2Anchor(slot, "sky")
	end
	return nil
end

-- Repère d'un élément dessiné sur ce ranch (B5 : Chantier de Big Plop, squishies qui se tournent
-- vers lui) ; identifiants : tier1.pompomArch … tier6.floatingCrown, vat, pool.fountain,
-- fence.lanterns8, gate.rainbow, geyser, frame.golden, giant.sun, helper.house, monument.1 … 10,
-- deco.1 … 12 ; nil s'il n'est pas dessiné (interrupteur coupé, pas encore construit, détail réduit
-- sans pièce)
function RanchV2.elementCFrame(slot: number, id: string): CFrame?
	if type(slot) ~= "number" or type(id) ~= "string" then
		return nil
	end
	local key = ELEMENT_KEY[id]
	local st = slots[slot]
	local obj = if key and st then st.objs[key] else nil
	if obj == nil or next(obj.parts) == nil then
		return nil
	end
	return anchorOf(slot, key :: string)
end

-- Lanterne du phare de ce ranch quand le palier 4 est dessiné en détail complet (LightingController
-- y place une des 4 lumières de MON ranch, D23) ; nil sinon
function RanchV2.lanternPart(slot: number): BasePart?
	local st = if type(slot) == "number" then slots[slot] else nil
	local obj = if st then st.objs.tier4 else nil
	if obj == nil or obj.level ~= "full" then
		return nil
	end
	local part = obj.parts[RanchTiers.LANTERN_KEY]
	return if part and part.Parent ~= nil then part else nil
end

-- Naissance mutée sur MON ranch (Celebrate « hatch » de RanchRenderer) : une étincelle par buse de
-- la Cuve (au plus 5 particules, budget « record ») ; émetteurs créés pour l'étincelle et détruits
-- après SPARK_LIFE ; rien sans buse, sans détail complet ou en Graphismes légers
function RanchV2.onHatch(data: any)
	if type(data) ~= "table" or type(data.mutation) ~= "number" or data.mutation == 0 then
		return
	end
	local slot = mySlot()
	local st = slots[slot]
	local obj = if st then st.objs.vat else nil
	if obj == nil or obj.level ~= "full" or particleFactor() <= 0 then
		return
	end
	-- étincelles d'une naissance précédente encore en vol (moins de SPARK_LIFE) : l'effet passager est
	-- déjà à l'écran, rien de plus ; jamais un refus du quota compté comme dépassement du budget visuel
	-- ni de ClientMetric pour lui (relecture du lot B4, R-B4-1)
	for _, sp in sparks do
		if sp.slot == slot then
			return
		end
	end
	local nozzles: { BasePart } = {}
	for i = 1, 5 do
		local part = obj.parts["vatNozzle" .. i]
		if part and part.Parent ~= nil then
			table.insert(nozzles, part)
		end
	end
	if #nozzles == 0 or not VisualBudget.take("record", #nozzles, "particles") then
		return
	end
	for _, nozzle in nozzles do
		local e = Instance.new("ParticleEmitter")
		e.Name = "NozzleSpark"
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Speed = SPARK_SPEED
		e.Size = NumberSequence.new(0.35)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160))
		e.LightEmission = 1
		e.EmissionDirection = Enum.NormalId.Right
		e.Parent = nozzle
		e:Emit(1)
		table.insert(sparks, { slot = slot, emitter = e, t = SPARK_LIFE })
	end
	RanchV2.on = true
end

-- Pièce animée par RanchV2 (specs : écritures attendues d'une animation)
function RanchV2.isAnimated(part: Instance): boolean
	return anims[part :: any] ~= nil
end

-- =============================================================================================
-- Pot de MON ranch : secondes de revenu dedans, rayon de l'aimant
-- =============================================================================================

local upgradeSnapshot: any = nil
local snapshotTried = false

local function snapshot(): any
	if not snapshotTried then
		snapshotTried = true
		local ok, mod = pcall(function(): any
			return require(Client.UI.UpgradeSnapshot) :: any
		end)
		upgradeSnapshot = if ok and type(mod) == "table" then mod else nil
	end
	local mod = upgradeSnapshot
	if mod == nil then
		return nil
	end
	local ok, snap = pcall(function(): any
		return mod.current()
	end)
	return if ok and type(snap) == "table" then snap else nil
end

-- Revenu par seconde de MON ranch (enclos et Bassin, contexte simple : décorations, Fame, pass)
local function myIncome(now: number): number
	local squishies = StateController.get("squishies")
	local growth = StateController.get("growth")
	if type(squishies) ~= "table" or type(growth) ~= "table" then
		return 0
	end
	local G = Util.safe("Formulas.G", 0, Formulas.G, growth, now)
	local passes = StateController.get("passes")
	local ranch = WorldStateController.ranch(mySlot())
	local tiles: any = if ranch and type(ranch.tiles) == "table" then ranch.tiles else {}
	local ok, K, S1 = pcall(Formulas.ranchIncome, squishies, G, {
		decor = Util.num(tiles.decor, 0, 0, DECOR_MAX),
		friends = 0,
		fame = Util.num(StateController.get("fame"), 0, 0),
		trophyBonus = 0,
		goldenPages = 0,
		doubleCoins = type(passes) == "table" and passes.DoubleCoins == true,
		boost = false,
	})
	if not ok or type(K) ~= "number" or type(S1) ~= "number" then
		return 0
	end
	local income = S1 + K * G
	return if income == income and income > 0 and income < math.huge then income else 0
end

local function heapState(now: number): number
	local pot = Util.num(StateController.get("pot"), 0, 0)
	local income = myIncome(now)
	if pot <= 0 or income <= 0 then
		return 0
	end
	return RanchLook.potState(pot / income)
end

-- Rayon de l'aimant montré (0 : aucun) : ligne « Aimant » ouverte dans l'instantané de l'écran
-- Améliorations, personnage à moins de rayon + 8 studs du Pot
local function ringRadius(slot: number): number
	local snap = snapshot()
	if snap == nil or type(snap.caps) ~= "table" or type(snap.levels) ~= "table" then
		return 0
	end
	if Util.num(snap.caps.magnet, 0, 0) <= 0 then
		return 0
	end
	local radii = Balance.PotV2.MagnetRadii
	local level = int(snap.levels.magnet, 0, #radii - 1)
	local radius = radii[level + 1]
	local root = Util.localRoot()
	if root == nil then
		return 0
	end
	local pot = WorldLayout.anchor(slot, "pot")
	local p = root.Position
	local dx, dz = p.X - pot.X, p.Z - pot.Z
	if math.sqrt(dx * dx + dz * dz) > radius + RING_MARGIN then
		return 0
	end
	return radius
end

-- Jelly Moon (lampions de la clôture, Record R 12) : revue au rafraîchissement et toutes les 0,5 s
local function checkMoon(now: number)
	local payload = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	local m = RanchLook.moonLit(payload, now)
	if m == moon then
		return
	end
	moon = m
	for _, st in slots do
		local v = st.view
		if st.on and v and v.has["fence.lanterns8"] then
			st.dirty = true
			anyDirty = true
		end
	end
end

local function slowRefresh(now: number)
	checkMoon(now)
	-- rayon des silhouettes qui grandissent (cadre doré, anneau « prêt », anneau-soleil)
	for slot, st in slots do
		local v = st.view
		if
			st.on
			and v
			and v.tapis
			and st.detail == "full"
			and (v.has["frame.golden"] or v.ready or v.giant >= 3)
		then
			local ranch = WorldStateController.ranch(slot)
			local r = if ranch then silhouetteRadius(ranch) else 0
			if r ~= v.radius then
				st.dirty = true
				anyDirty = true
			end
		end
	end
	local my = mySlot()
	local st = slots[my]
	if st == nil or not st.on then
		return
	end
	local heap = heapState(now)
	local ring = ringRadius(my)
	if heap ~= st.heap or ring ~= st.ring then
		st.heap = heap
		st.ring = ring
		st.dirty = true
		anyDirty = true
	end
end

-- =============================================================================================
-- Boucle
-- =============================================================================================

local function declareSystems()
	if declared then
		return
	end
	declared = true
	for _, sys in SYSTEMS do
		VisualBudget.declare(sys, (VisualBudget.LIMITS :: any)[sys])
	end
end

-- Revoit les ranchs marqués : lecture, budgets, rendu
local function refresh()
	anyDirty = false
	local any = false
	local my = mySlot()
	checkMoon(Util.safe("Clock.now", 0, Clock.now))
	for _, st in slots do
		if st.dirty then
			local model = st.model
			st.on = carries(model)
			st.view = if st.on then readView(st) else nil
			if st.on and st.slot == my then
				-- tas et anneau de MON ranch tout de suite (puis toutes les 0,5 s)
				st.heap = heapState(Util.safe("Clock.now", 0, Clock.now))
				st.ring = ringRadius(my)
			end
		end
		if st.on then
			any = true
		end
	end
	-- détail des ranchs (un ranch qui vient de s'allumer a tout de suite le sien)
	updateDetail()
	if any then
		declareSystems()
		local order = VisualBudget.order(mySlot(), current)
		for _, st in slots do
			if st.on then
				computeWants(st)
			end
		end
		for _, sys in SYSTEMS do
			local wants: { [number]: VisualBudget.Want } = {}
			for slot, st in slots do
				if st.on then
					wants[slot] = st.want[sys] or ZERO_WANT
				end
			end
			local levels = VisualBudget.allocate(sys, order, wants)
			for slot, st in slots do
				if st.on then
					local g = levels[slot] or "none"
					if st.grants[sys] ~= g then
						st.grants[sys] = g
						st.dirty = true
					end
				end
			end
		end
	elseif declared then
		for _, sys in SYSTEMS do
			VisualBudget.allocate(sys, {}, {})
		end
	end
	-- quota de particules rendu avant d'être repris (lot B4, étape 6) : un ranch qui perd les
	-- étincelles de son Tapis doré (détail réduit, autre palier, Graphismes légers, ranch libéré) les
	-- rend avant que les ranchs rendus avant lui dans l'ordre des numéros ne les demandent
	for _, st in slots do
		if st.dirty then
			local obj = st.objs.tapis
			if obj and #obj.extra > 0 and not keepsSparkles(st) then
				dropSparkles(obj)
			end
		end
	end
	local alive = false
	for _, st in slots do
		if st.dirty then
			st.dirty = false
			Util.guard("RanchV2.render", renderSlot, st)
		end
		if st.on or next(st.objs) ~= nil then
			alive = true
		end
	end
	RanchV2.on = alive or #shrinking > 0 or #sparks > 0 or BuildCascade.busy()
end

-- Socles qui rétrécissent (0,2 s), puis détruits
local function stepShrink(dt: number)
	for i = #shrinking, 1, -1 do
		local s = shrinking[i]
		s.t += dt
		local k = math.max(0, 1 - s.t / SHRINK)
		for j, part in s.parts do
			if part.Parent ~= nil then
				if k <= 0 then
					part:Destroy()
				else
					part.Size = s.sizes[j] * math.max(k, 0.05)
				end
			end
		end
		if k <= 0 then
			table.remove(shrinking, i)
			anyDirty = true -- RanchV2.on revu au prochain rafraîchissement
		end
	end
end

-- Pièces animées à 15 Hz (Mouvement réduit : immobiles à leur pose de base)
local function animate()
	local rm = reducedMotion()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local writes = 0
	for part, a in anims do
		if part.Parent == nil then
			anims[part] = nil
		elseif BuildCascade.finalOf(part) == nil then
			local spec = a.spec
			if rm then
				if not a.still then
					a.still = true
					a.idx = -1
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, spec.cf)
					if part.Color ~= spec.color then
						part.Color = spec.color
					end
					writes += 1
				end
			else
				a.still = false
				local phase = spec.phase or 0
				if spec.anim == "orbit" then
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, RanchKit.orbit(a.slot, spec.cf, animTime))
					writes += 1
				elseif spec.anim == "shoot" then
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, RanchKit.shoot(a.slot, animTime, phase))
					writes += 1
				elseif spec.anim == "hop" then
					local h = 1.2 * math.abs(math.sin(2 * math.pi * (animTime / 0.8 + phase)))
					table.insert(bulkParts, part)
					table.insert(bulkCFrames, spec.cf + Vector3.new(0, h, 0))
					writes += 1
				elseif spec.anim == "twinkle" and spec.alt then
					local k = 0.5 + 0.5 * math.sin(2 * math.pi * (animTime / 3 + phase))
					part.Color = RanchKit.mix(spec.color, spec.alt :: Color3, k)
					writes += 1
				elseif spec.anim == "spin" and spec.pivot then
					table.insert(bulkParts, part)
					table.insert(
						bulkCFrames,
						RanchKit.spin(spec.cf, spec.pivot :: Vector3, spec.period or 1, animTime, phase)
					)
					writes += 1
				elseif spec.anim == "bob" then
					table.insert(bulkParts, part)
					table.insert(
						bulkCFrames,
						RanchKit.bob(spec.cf, spec.amp or 0.5, spec.period or 1, animTime, phase)
					)
					writes += 1
				elseif spec.anim == "pulse" and spec.alt then
					-- au plus 3 changements de couleur par seconde : écrite seulement quand l'indice change
					local idx = RanchKit.pulseIndex(animTime, phase)
					if idx ~= a.idx then
						a.idx = idx
						local c = if idx == 0 then spec.color else spec.alt :: Color3
						if part.Color ~= c then
							part.Color = c
						end
						writes += 1
					end
				end
			end
		end
	end
	if #bulkParts > 0 then
		local ok, err = pcall(function()
			workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		if not ok then
			Util.raise("RanchV2.bulk", tostring(err))
		end
	end
	counters.animWrites = writes
end

-- Une image (RanchRenderer, seulement tant que RanchV2.on) ; now = Clock.now()
function RanchV2.step(dt: number, now: number)
	local d = Util.num(dt, 0, 0, 1)
	for i = #sparks, 1, -1 do
		local sp = sparks[i]
		sp.t -= d
		if sp.t <= 0 or sp.emitter.Parent == nil then
			sp.emitter:Destroy()
			VisualBudget.release("record", 1, "particles")
			table.remove(sparks, i)
			anyDirty = true -- RanchV2.on revu
		end
	end
	if BuildCascade.busy() and not BuildCascade.step(now) then
		anyDirty = true -- cascade finie : RanchV2.on revu
	end
	animAcc += d
	if animAcc >= 1 / ANIM_HZ then
		local tick = animAcc
		animAcc = 0
		animTime += tick
		updateDetail()
		stepShrink(tick)
		animate()
	end
	slowAcc += d
	if slowAcc >= SLOW then
		slowAcc = 0
		slowRefresh(now)
	end
	if anyDirty then
		refresh()
	end
end

-- =============================================================================================
-- Signaux
-- =============================================================================================

local function onAttribute(slot: number, name: string)
	if name == "HaloOn" then
		local fn = hooks.skinChanged
		if fn then
			Util.guard("RanchV2.skin", fn, slot)
		end
		return
	end
	if not WATCHED[name] then
		return
	end
	local st = stateOf(slot)
	-- un ranch sans décor v2.0 ne se réveille que pour un attribut qui l'allume (TapisTier, Monuments,
	-- DecoPerso) : BestR, SplorchReady, GiantTier… d'un interrupteur voisin seuls ne coûtent rien
	if not st.on and not CARRIER[name] then
		return
	end
	st.dirty = true
	anyDirty = true
	RanchV2.on = true
end

-- Écoute les modèles des ranchs (une connexion AttributeChanged chacun) ; RanchRenderer l'appelle
-- dans son rafraîchissement lent tant que les 16 ne sont pas tous écoutés
function RanchV2.watch()
	local all = true
	for slot = 1, RANCHES do
		local model = ranchModel(slot)
		local st = slots[slot]
		if model == nil then
			all = false
		elseif st == nil or st.model ~= model then
			st = stateOf(slot)
			if st.conn then
				st.conn:Disconnect()
			end
			st.model = model
			st.decorParts = {}
			st.conn = model.AttributeChanged:Connect(function(name: string)
				onAttribute(slot, name)
			end)
			-- attributs déjà posés avant l'écoute
			if carries(model) then
				st.dirty = true
				anyDirty = true
				RanchV2.on = true
			end
		end
	end
	RanchV2.watchedAll = all
end

-- Patch du ranch public (WorldStateController.RanchChanged) : revoir ce ranch s'il est v2.0
-- Champs du ranch public qui changent ses décors v2.0 (les autres, fréquents, ne réveillent rien)
local RELEVANT: { [string]: boolean } = { ["*"] = true, tiles = true, R = true, userId = true }

function RanchV2.onRanchChanged(slot: number, fields: { string }?)
	local st = slots[slot]
	if st == nil or not (st.on or next(st.objs) ~= nil) then
		return
	end
	local relevant = type(fields) ~= "table"
	if not relevant then
		for _, f in fields :: { string } do
			if RELEVANT[f] then
				relevant = true
				break
			end
		end
	end
	if relevant then
		st.dirty = true
		anyDirty = true
		RanchV2.on = true
	end
end

-- Qualité ou Graphismes légers changés : détail et étincelles revus
function RanchV2.onQualityChanged()
	for _, st in slots do
		if st.on then
			st.dirty = true
			anyDirty = true
		end
	end
end

-- Branche les crochets de RanchRenderer et la source de détail de la cascade
function RanchV2.start(options: { skinChanged: ((number) -> ())? }?)
	hooks = {}
	if type(options) == "table" and type(options.skinChanged) == "function" then
		hooks.skinChanged = options.skinChanged
	end
	BuildCascade.configure({ detail = RanchV2.detail })
end

-- =============================================================================================
-- Habillages v2.0 (stepTheme de RanchRenderer, D14)
-- =============================================================================================

-- Ligne d'habillage v2.0 à poser sur ce ranch : un des 11 nouveaux, et le ranch porte HaloOn
-- (RanchSkins ouvert) ; nil sinon (les 3 de la v1.3 suivent le rendu d'aujourd'hui)
function RanchV2.skinFor(slot: number, theme: string): RanchLook.SkinLook?
	if not RanchLook.isV2Skin(theme) then
		return nil
	end
	local model = ranchModel(slot)
	if model == nil or model:GetAttribute("HaloOn") == nil then
		return nil
	end
	return RanchLook.skin(theme)
end

-- Pose l'habillage (clôture, sol des enclos, poteaux et arche du portail), origines gardées
function RanchV2.applySkin(slot: number, model: Instance, skin: RanchLook.SkinLook)
	local st = stateOf(slot)
	local now: { [BasePart]: boolean } = {}
	local function put(part: Instance?, color: Color3?, materialName: string?)
		if part == nil or not part:IsA("BasePart") then
			return
		end
		local p = part :: BasePart
		local material = RanchKit.paintMaterial(materialName)
			or (st.saved[p] and st.saved[p].material)
			or p.Material
		local c = color or (st.saved[p] and st.saved[p].color) or p.Color
		now[p] = true
		paint(st, p, c, material)
	end
	local fence = model:FindFirstChild("Fence")
	if fence and (skin.fence or skin.fenceMaterial) then
		for _, d in fence:GetDescendants() do
			put(d, skin.fence, skin.fenceMaterial)
		end
	end
	if skin.floor or skin.floorMaterial then
		put(model:FindFirstChild("PenFloor"), skin.floor, skin.floorMaterial)
	end
	local gate = model:FindFirstChild("Gate")
	if gate and skin.gate then
		for _, name in { "PostL", "PostR", "Arch" } do
			put(gate:FindFirstChild(name), skin.gate, nil)
		end
	end
	for part in st.skin do
		if not now[part] then
			unpaint(st, part)
		end
	end
	st.skin = now
end

-- Retire l'habillage v2.0 (aspect d'origine) ; rien s'il n'y en a pas
function RanchV2.clearSkin(slot: number)
	local st = slots[slot]
	if st == nil or next(st.skin) == nil then
		return
	end
	for part in st.skin do
		unpaint(st, part)
	end
	st.skin = {}
end

-- =============================================================================================
-- Compteurs et fin
-- =============================================================================================

-- Compteurs (specs, Diagnostics) : ranchs v2.0, pièces par système et au total, pièces animées,
-- écritures de la dernière image animée, rendus, créations, destructions, cascades
function RanchV2.stats(): { [string]: number }
	local out: { [string]: number } = {
		slots = 0,
		parts = 0,
		anims = 0,
		tapis = 0,
		record = 0,
		plinths = 0,
		pot = 0,
		tiers = 0,
		house = 0,
		silhouette = 0,
		monuments = 0,
		decoPerso = 0,
		sky = 0,
		painted = 0,
		renders = counters.renders,
		created = counters.created,
		destroyed = counters.destroyed,
		cascades = counters.cascades,
		animWrites = counters.animWrites,
		current = current,
	}
	for _, st in slots do
		if st.on then
			out.slots += 1
		end
		for key, obj in st.objs do
			local n = 0
			for _ in obj.parts do
				n += 1
			end
			out.parts += n
			local sys = OBJ_SYSTEM[key]
			if sys then
				out[sys] += n
			end
		end
		for _ in st.saved do
			out.painted += 1
		end
	end
	for _ in anims do
		out.anims += 1
	end
	return out
end

-- Coupe tout (fin de séance, specs) : décors détruits, peintures rendues, connexions coupées
function RanchV2.stop()
	for _, st in slots do
		clearSlot(st)
		RanchV2.clearSkin(st.slot)
		if st.conn then
			st.conn:Disconnect()
			st.conn = nil
		end
	end
	table.clear(slots)
	table.clear(anims)
	for _, s in shrinking do
		for _, part in s.parts do
			part:Destroy()
		end
	end
	table.clear(shrinking)
	for _, sp in sparks do
		sp.emitter:Destroy()
		VisualBudget.release("record", 1, "particles")
	end
	table.clear(sparks)
	BuildCascade.flush(nil)
	RanchV2.on = false
	RanchV2.watchedAll = false
	anyDirty = false
	current = 0
	moon = false
	animAcc, animTime, slowAcc = 0, 0, 0
	hooks = {}
	for key in counters do
		counters[key] = 0
	end
end

return RanchV2
