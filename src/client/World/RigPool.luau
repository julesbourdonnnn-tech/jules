--!strict
-- RigPool — aide du paquet « client-world » : réserve de rigs NebbyBuilder par (code, étoiles).
--   * acquire(code, stars, lod, bubble, parent) : rig réutilisé (même code) ou construit ; options
--     communes (aura, Trail sauf Graphismes légers, particules × 0,3 en Graphismes légers, bulle du
--     bouclier débutant) ; jamais de Highlight ni de PointLight intégrés : CongaRenderer les attribue
--     lui-même aux plus proches (budgets §12.8)
--   * release(rig) : tailles de repos rendues, modèle déparenté et gardé (au plus MAX_POOLED rigs),
--     sinon détruit
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
local STAR_KEYS = 8

-- Appelé juste avant qu'un rig soit reconstruit, mis en réserve ou détruit : CongaRenderer y
-- détache les Highlight et PointLight qu'il lui avait prêtés (sinon détruits avec les pièces)
RigPool.beforeRebuild = nil :: ((Rig) -> ())?

local pools: { [number]: { Rig } } = {}
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
	}
end

local function sameOpts(rig: Rig, bubble: boolean): boolean
	local o = rig.opts
	return (o.rookieBubble == true) == bubble
		and (o.trail ~= false) == not lowGraphics
		and (o.particleMult or 1) == (if lowGraphics then Balance.Render.LowGraphicsParticleMult else 1)
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
end

function RigPool.acquire(code: number, stars: number, lod: Lod, bubble: boolean, parent: Instance): Rig
	local key = keyOf(code, stars)
	local list = pools[key]
	local rig: Rig? = if list then table.remove(list) else nil
	if rig then
		pooled -= 1
		if not sameOpts(rig, bubble) then
			rebuild(rig, bubble, lod)
		elseif rig.lod ~= lod then
			NebbyBuilder.setLod(rig, lod)
		end
	else
		rig = NebbyBuilder.build(code, stars, lod, optsFor(bubble))
	end
	local r = rig :: Rig
	r.model.Parent = parent
	return r
end

function RigPool.release(rig: Rig)
	if rig.destroyed then
		return
	end
	notify(rig)
	Fx.scaleRig(rig, Vector3.one)
	rig.model.Parent = nil
	if pooled >= MAX_POOLED then
		NebbyBuilder.destroy(rig)
		return
	end
	local key = keyOf(rig.code, rig.stars)
	local list = pools[key]
	if list == nil then
		list = {}
		pools[key] = list
	end
	table.insert(list, rig)
	pooled += 1
end

function RigPool.setLod(rig: Rig, lod: Lod)
	if rig.lod ~= lod and not rig.destroyed then
		notify(rig)
		Fx.scaleRig(rig, Vector3.one)
		NebbyBuilder.setLod(rig, lod)
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
	pooled = 0
end

function RigPool.pooledCount(): number
	return pooled
end

return RigPool
