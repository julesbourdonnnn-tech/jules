--!strict
-- RigPool — aide du paquet « client-world » : réserve de rigs NebbyBuilder par (code, étoiles).
--   * acquire(code, stars, lod, bubble, parent) : rig réutilisé (même code) ou construit ; options
--     communes (aura, Trail sauf Graphismes légers, particules × 0,3 en Graphismes légers, bulle du
--     bouclier débutant) ; jamais de Highlight ni de PointLight intégrés : CongaRenderer les attribue
--     lui-même aux plus proches (budgets §12.8) ; effets de particules continus ÉTEINTS à chaque
--     construction, reconstruction (LOD, options), sortie ou retour en réserve : seule la passe
--     suivante du planificateur (NebbyBuilder.budgetFx, 10 Hz) les allume, au coût du rig tel qu'il
--     est alors (sinon un rig rallumé au coût d'avant dépasserait le budget jusqu'à la passe suivante)
--   * release(rig) : tailles de repos rendues, modèle déparenté et gardé ; réserve LRU : au plus
--     MAX_POOLED rigs en tout et MAX_PER_KEY par (code, étoiles), le plus ancien rig mis en réserve
--     est détruit pour faire place au nouveau (sinon, après une promenade sur l'île, la réserve
--     garderait pour toujours les 120 premières clés et chaque acquire reconstruirait)
--   * setLod / conform : changement de niveau de détail ou d'options sur place (même modèle)
--   * partCount(code, lod) : coût en pièces mis en cache (budget de 1 500 pièces)
-- GDD : §5.2, §12.8 (réserves d'instances).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local NebbyBuilder = require(Shared.Render.NebbyBuilder)

local Fx = require(script.Parent.Fx)

local RigPool = {}

export type Rig = NebbyBuilder.Rig
export type Lod = NebbyBuilder.Lod

-- Ce que le planificateur de niveaux de détail de CongaRenderer voit d'un Nebby rendu (nœud de
-- file, sauvage, perché) : distance au point de vue, LOD voulu, LOD imposé éventuel
export type View = {
	code: number,
	stars: number,
	rig: Rig?,
	want: Lod,
	dist: number,
	bubble: boolean,
	pinned: Lod?, -- LOD imposé (tête d'une file lointaine : "ball" ; reste d'une file lointaine : "hidden")
	mythic: boolean, -- Mythique+ : candidat à un Highlight
	bright: boolean, -- Légendaire+ : candidat à une PointLight
}

local MAX_POOLED = 120
-- Rigs gardés par (code, étoiles) : une longue file de clones relâchée d'un coup ne chasse pas toute
-- la diversité de la réserve ; 24 = constructions par image de CongaRenderer (MAX_REBUILDS) : un
-- groupe de clones qui revient réapparaît sans reconstruction dans la même image
local MAX_PER_KEY = 24
local STAR_KEYS = 8

-- Appelé juste avant qu'un rig soit reconstruit, mis en réserve ou détruit : CongaRenderer y
-- détache les Highlight et PointLight qu'il lui avait prêtés (sinon détruits avec les pièces)
RigPool.beforeRebuild = nil :: ((Rig) -> ())?

-- Rig en réserve : maillon de la liste LRU (du plus ancien au plus récent mis en réserve)
type Slot = { rig: Rig, key: number, older: Slot?, newer: Slot? }

-- Rigs en réserve par clé, du plus ancien au plus récent (acquire prend le plus récent)
local pools: { [number]: { Rig } } = {}
local slots: { [Rig]: Slot } = {}
local oldest: Slot? = nil
local newest: Slot? = nil
local pooled = 0
local lowGraphics = false
local partCache: { [number]: number } = {}

local function keyOf(code: number, stars: number): number
	return code * STAR_KEYS + math.clamp(math.floor(stars), 1, STAR_KEYS - 1)
end

local function optsFor(bubble: boolean): NebbyBuilder.BuildOptions
	return {
		aura = true,
		highlight = false,
		light = false,
		trail = not lowGraphics,
		rookieBubble = bubble,
		particleMult = if lowGraphics then Balance.Render.LowGraphicsParticleMult else 1,
		-- éteints jusqu'au prochain budgetFx de CongaRenderer (≤ 300 particules à l'écran, §12.8)
		fxEnabled = false,
	}
end

local function sameOpts(rig: Rig, bubble: boolean): boolean
	local o = rig.opts
	return (o.rookieBubble == true) == bubble
		and (o.trail ~= false) == not lowGraphics
		and (o.particleMult or 1) == (if lowGraphics then Balance.Render.LowGraphicsParticleMult else 1)
end

-- Liste LRU ---------------------------------------------------------------------------------------

local function unlink(slot: Slot)
	local older, newer = slot.older, slot.newer
	if older then
		older.newer = newer
	else
		oldest = newer
	end
	if newer then
		newer.older = older
	else
		newest = older
	end
	slot.older = nil
	slot.newer = nil
end

local function link(slot: Slot)
	local last = newest
	slot.older = last
	slot.newer = nil
	if last then
		last.newer = slot
	else
		oldest = slot
	end
	newest = slot
end

-- Retire un rig de la réserve (liste LRU et liste de sa clé) ; faux s'il n'y était pas
local function unpool(rig: Rig): boolean
	local slot = slots[rig]
	if slot == nil then
		return false
	end
	slots[rig] = nil
	unlink(slot)
	local list = pools[slot.key]
	if list then
		local i = table.find(list, rig)
		if i then
			table.remove(list, i)
		end
		if #list == 0 then
			pools[slot.key] = nil
		end
	end
	pooled -= 1
	return true
end

-- Détruit un rig en réserve (éviction : réserve pleine ou clé pleine)
local function evict(rig: Rig)
	if unpool(rig) then
		NebbyBuilder.destroy(rig)
	end
end

local function notify(rig: Rig)
	local hook = RigPool.beforeRebuild
	if hook then
		hook(rig)
	end
end

-- Reconstruit le rig avec de nouvelles options (passage par "hidden" : même table, même modèle)
local function rebuild(rig: Rig, bubble: boolean, lod: Lod)
	notify(rig)
	rig.opts = optsFor(bubble)
	if rig.lod ~= "hidden" then
		NebbyBuilder.setLod(rig, "hidden")
	end
	NebbyBuilder.setLod(rig, lod)
	NebbyBuilder.setFx(rig, false)
end

function RigPool.acquire(code: number, stars: number, lod: Lod, bubble: boolean, parent: Instance): Rig
	local key = keyOf(code, stars)
	local list = pools[key]
	local rig: Rig? = if list then list[#list] else nil
	-- rig de la réserve détruit ailleurs (jamais attendu) : écarté, le suivant ou un neuf sert
	while rig and rig.destroyed do
		unpool(rig)
		list = pools[key]
		rig = if list then list[#list] else nil
	end
	if rig then
		unpool(rig)
		if not sameOpts(rig, bubble) then
			rebuild(rig, bubble, lod)
		elseif rig.lod ~= lod then
			NebbyBuilder.setLod(rig, lod)
		end
	else
		rig = NebbyBuilder.build(code, stars, lod, optsFor(bubble))
	end
	local r = rig :: Rig
	NebbyBuilder.setFx(r, false) -- rig de la réserve : peut-être encore allumé par le dernier budget
	r.model.Parent = parent
	return r
end

function RigPool.release(rig: Rig)
	if rig.destroyed or slots[rig] ~= nil then
		return -- détruit, ou déjà en réserve (double release)
	end
	notify(rig)
	Fx.scaleRig(rig, Vector3.one)
	NebbyBuilder.setFx(rig, false)
	rig.model.Parent = nil
	local key = keyOf(rig.code, rig.stars)
	-- clé pleine : son plus ancien rig fait place
	local full = pools[key]
	if full and #full >= MAX_PER_KEY then
		evict(full[1])
	end
	-- réserve pleine : le plus ancien rig de toute la réserve fait place
	while pooled >= MAX_POOLED do
		local first = oldest
		if first == nil then
			break
		end
		evict(first.rig)
	end
	local list = pools[key]
	if list == nil then
		list = {}
		pools[key] = list
	end
	table.insert(list, rig)
	local slot: Slot = { rig = rig, key = key, older = nil, newer = nil }
	slots[rig] = slot
	link(slot)
	pooled += 1
end

function RigPool.setLod(rig: Rig, lod: Lod)
	if rig.lod ~= lod and not rig.destroyed then
		notify(rig)
		Fx.scaleRig(rig, Vector3.one)
		NebbyBuilder.setLod(rig, lod)
		NebbyBuilder.setFx(rig, false)
	end
end

-- Remet le rig aux options courantes (bulle du bouclier débutant, Graphismes légers) ; vrai si
-- une reconstruction a eu lieu
function RigPool.conform(rig: Rig, bubble: boolean): boolean
	if rig.destroyed or sameOpts(rig, bubble) then
		return false
	end
	Fx.scaleRig(rig, Vector3.one)
	rebuild(rig, bubble, rig.lod)
	return true
end

function RigPool.partCount(code: number, lod: Lod): number
	if lod == "hidden" then
		return 0
	elseif lod == "ball" then
		return 1
	end
	local cached = partCache[code]
	if cached == nil then
		cached = NebbyBuilder.partCount(code, "full")
		partCache[code] = cached
	end
	return cached
end

-- Graphismes légers : options changées → réserve vidée (les rigs suivants sont reconstruits)
function RigPool.setLowGraphics(on: boolean)
	if on == lowGraphics then
		return
	end
	lowGraphics = on
	RigPool.clear()
end

function RigPool.lowGraphics(): boolean
	return lowGraphics
end

function RigPool.clear()
	for _, list in pools do
		for _, rig in list do
			NebbyBuilder.destroy(rig)
		end
	end
	table.clear(pools)
	table.clear(slots)
	oldest = nil
	newest = nil
	pooled = 0
end

function RigPool.pooledCount(): number
	return pooled
end

return RigPool
