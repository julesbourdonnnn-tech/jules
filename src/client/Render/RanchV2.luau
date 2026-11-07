--!strict
-- RanchV2 (lot B4, étape 3 ; docs/04 §27.5, §27.7 ; GDD v2.0 §9.4, §11.5, §12.9 ; décisions D1, D6,
-- D12-D14, D18, D18b, D19, D26 du plan B4). État v2.0 de chaque ranch et rendu de ses décors, pour
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
--   * travail par image seulement tant qu'un ranch v2.0 existe (RanchV2.on) : la cascade quand elle
--     joue, les pièces animées (points de la galaxie, étoiles, pièces qui sautillent) à 15 Hz.
-- Jamais d'erreur : un attribut illisible donne l'aspect sûr, un modèle ou un personnage absent ne
-- dessine rien.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local RanchLook = require(Shared.Logic.RanchLook)
local Prestige = require(Shared.Logic.Prestige)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Formulas = require(Shared.Logic.Formulas)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local QualityController = require(Client.Controllers.QualityController)
local Util = require(Client.World.Util)
local VisualBudget = require(script.Parent.VisualBudget)
local BuildCascade = require(script.Parent.BuildCascade)
local RanchKit = require(script.Parent.RanchKit)

local RanchV2 = {}

-- Au moins un ranch v2.0 (ou un décor à défaire) : RanchRenderer n'appelle step que si vrai
RanchV2.on = false
-- Les 16 modèles sont écoutés : RanchRenderer n'appelle plus watch
RanchV2.watchedAll = false

local RANCHES = WorldLayout.Const.Ranches
local MAX_R = Balance.Prestige.MaxR
local TIERS_MAX = 6
local DECOR_MAX = Balance.Tiles.decor.Levels
local ANIM_HZ = 15
local SLOW = 0.5 -- s : tas du Pot et anneau de l'aimant de MON ranch
local SHRINK = 0.2 -- s : le socle rétrécit avant que la décoration sorte
local RING_MARGIN = 8 -- studs : l'anneau se montre jusqu'au rayon + 8
local SPARKLE_RATE = 2 -- étincelles par seconde du Tapis doré (GDD §11.5)
local SPARKLE_PARTICLES = 2 -- particules à l'écran par Tapis doré (budget « tapis » ≤ 6)
local STRING_MAX = 32

-- Attributs qui changent les décors de cette étape (le reste viendra aux étapes 4 et 5)
local WATCHED: { [string]: boolean } = {
	TapisTier = true,
	BestR = true,
	DecorGold = true,
	GoldPennants = true,
	Cushions = true,
	OwnerUserId = true,
}

-- Objets dessinés et système du budget visuel de chacun
local OBJ_SYSTEM: { [string]: string } = {
	tapis = "tapis",
	cushions = "tapis",
	bed = "tapis",
	plinths = "plinths",
	pennants = "record",
	heap = "pot",
	ring = "pot",
}
local SYSTEMS = { "tapis", "record", "plinths", "pot" }

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
	tier: number,
	bestR: number,
	gold: number,
	goldPennants: boolean,
	cushions: string,
	snack: number,
	decor: number,
	pens: number,
	cozyBed: boolean,
	color: Color3,
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
	want: { [string]: number },
	objs: { [string]: Obj },
	folder: Folder?,
	saved: { [BasePart]: Painted },
	skin: { [BasePart]: boolean },
	decorParts: { [number]: { BasePart } },
	heap: number,
	ring: number, -- rayon montré (0 : aucun)
	view: View?,
}
type Anim = { slot: number, spec: RanchKit.Spec, still: boolean }
type Shrink = { slot: number, parts: { BasePart }, sizes: { Vector3 }, t: number }

local slots: { [number]: Slot } = {}
local anims: { [BasePart]: Anim } = {}
local shrinking: { Shrink } = {}
local hooks: { skinChanged: ((number) -> ())? } = {}
local declared = false
local anyDirty = false
local current = 0
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
				anims[part :: BasePart] = { slot = st.slot, spec = spec, still = false }
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

-- Rendu d'un objet de pièces v2.0 avec cascade sur un vrai changement
local function renderParts(st: Slot, key: string, sig: string, specs: { RanchKit.Spec }, level: string)
	local real = realChange(st, key, level)
	local created, createdSpecs = update(st, key, sig, specs, EMPTY :: any)
	if real and level == "full" then
		cascade(st, key, created, createdSpecs, nil)
	end
	markRendered(st, key, level)
end

-- Détruit tous les objets d'un ranch et rend les peintures (aspect exact de la v1.3)
local function clearSlot(st: Slot)
	BuildCascade.flush(st.slot)
	for key, obj in st.objs do
		for _, part in obj.parts do
			forget(part)
		end
		for _, inst in obj.extra do
			inst:Destroy()
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

local function readView(st: Slot): View?
	local model = st.model
	if model == nil or model.Parent == nil then
		return nil
	end
	local tierAttr = model:GetAttribute("TapisTier")
	if tierAttr == nil then
		return nil
	end
	local ranch = WorldStateController.ranch(st.slot)
	if ranch == nil or ranch.userId == 0 then
		return nil
	end
	local tiles: any = if type(ranch.tiles) == "table" then ranch.tiles else {}
	local bestAttr = model:GetAttribute("BestR")
	local bestR = if type(bestAttr) == "number" and bestAttr == bestAttr
		then int(bestAttr, 0, MAX_R)
		else Prestige.r(ranch :: any)
	local goldAttr = model:GetAttribute("DecorGold")
	local cushionsAttr = model:GetAttribute("Cushions")
	return {
		owner = ranch.userId,
		tier = int(tierAttr, 0, TIERS_MAX),
		bestR = bestR,
		gold = int(goldAttr, 0, 2 ^ DECOR_MAX - 1),
		goldPennants = model:GetAttribute("GoldPennants") == true,
		cushions = if type(cushionsAttr) == "string" and #cushionsAttr <= STRING_MAX
			then cushionsAttr
			else "",
		snack = int(tiles.snack, 0, Balance.Tiles.snack.Levels),
		decor = int(tiles.decor, 0, DECOR_MAX),
		pens = int(tiles.pens, 0, Balance.Tiles.pens.Levels),
		cozyBed = tiles.cozyBed == true,
		color = Cosmetics.RanchColors[st.slot] or Cosmetics.FreeRanchColor,
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

local function computeWants(st: Slot)
	local view = st.view
	local full = st.detail == "full"
	for _, sys in SYSTEMS do
		st.want[sys] = 0
	end
	if view == nil or not full then
		return
	end
	st.want.tapis = RanchKit.tapisCount(view.tier)
		+ RanchLook.cushions(view.pens, 0)
		+ (if view.cozyBed then 10 else 0)
	st.want.record = 2 * #pennantList(view)
	st.want.plinths = 2 * #plinthList(view)
	if st.slot == mySlot() then
		st.want.pot = RanchKit.heapCount(st.heap) + (if st.ring > 0 then RanchKit.RING_DOTS else 0)
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
	renderTapis(st, view)
	renderCushions(st, view)
	renderBed(st, view)
	renderPlinths(st, view)
	renderGolden(st, view)
	renderPennants(st, view)
	renderPotMaterial(st, view)
	renderPot(st, view)
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

-- Détail d'un ranch (« full » | « reduced ») : B5 et la cascade le lisent
function RanchV2.detail(slot: number): string
	if type(slot) ~= "number" or slot ~= slot then
		return "reduced"
	end
	return detailFor(slot, current, mySlot(), lowQuality())
end

-- Ranch courant (où se tient le personnage, D6)
function RanchV2.current(): number
	return current
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

local function slowRefresh(now: number)
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
	for _, st in slots do
		if st.dirty then
			local model = st.model
			st.on = model ~= nil and model.Parent ~= nil and model:GetAttribute("TapisTier") ~= nil
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
					wants[slot] = { full = st.want[sys] or 0, reduced = 0 }
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
	RanchV2.on = alive or #shrinking > 0 or BuildCascade.busy()
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
	if name == "OwnerUserId" and not st.on then
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
			if model:GetAttribute("TapisTier") ~= nil then
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
	BuildCascade.flush(nil)
	RanchV2.on = false
	RanchV2.watchedAll = false
	anyDirty = false
	current = 0
	animAcc, animTime, slowAcc = 0, 0, 0
	hooks = {}
	for key in counters do
		counters[key] = 0
	end
end

return RanchV2
