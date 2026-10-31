--!strict
-- NebbyBuilder — paquet « world » (STUB du contrat : docs/04-architecture.md §12.2).
-- Recettes de modèles en primitives, construites CÔTÉ CLIENT à partir de 4 nombres (espèce, forme,
-- variantes, étoiles). Constructeur pur : Instance.new seulement, aucun service, aucun parentage
-- dans le Workspace (l'appelant parente et met en réserve). Toutes les pièces : Anchored,
-- CanCollide = CanQuery = CanTouch = false, CastShadow = false.
-- Responsabilités :
--   * corps (Ball, taille T de la rareté, ×2 si Huge), yeux (0,28 T à (±0,22 ; +0,12 ; −0,42) T,
--     noirs, Reflectance 0,3), joues (cylindres plats 0,20 T, roses), accents selon l'archétype
--     (Puff, Sprout, Horn, Wing, Ring, Twin, Spike, Moon, Crown, Comet ; Légendaires : 2 archétypes,
--     ≤ 3 pièces d'accent) — au plus 8 pièces en détail complet
--   * formes (matériaux et teintes de Config/Nebbies.Forms), variantes (Golden Foil, Huge ×2,
--     halo Starborn), étoiles (petit indicateur ★ au-dessus du corps pour ★2+)
--   * auras de rareté (antenne Néon, Sparkles, ParticleEmitter en orbite, PointLight + Trail,
--     Highlight + couronne de 3 boules, ForceField + HSV) selon BuildOptions (budgets du §12.8
--     décidés par l'appelant)
--   * niveaux de détail : "full" (< 50 studs), "ball" (50-120 : une Ball couleur du corps, Néon si
--     Mythique+), "hidden"
--   * animations d'archétype calculées sans tween : gonflement Puff ±5 %, balancement Sprout ±10°,
--     battement Wing ±25° à 6 Hz, rotation Ring 1 tour / 3 s, rebond Twin décalé, ondulation Comet ;
--     clignement des yeux (Y 0,1 pendant 0,08 s)
--   * recettes du Gloomwisp (§11.6 : Ball indigo 2,4 + 3 bouffées + 2 yeux Néon, Trail violet) et de
--     la Grande Comète (orbe au sol de 3 + anneau doré ; Ball Néon de 6 + Fire + Trail + Sparkles
--     dans le ciel)
--   * bulle dorée du bouclier débutant (Ball ForceField 1,3 T) en option
-- Le moteur de rendu (CongaRenderer) déplace toutes les pièces avec un seul workspace:BulkMoveTo :
-- Rig expose les pièces et leurs décalages (pose animée) relatifs au CFrame racine du corps.
-- GDD : §4.2, §4.4, §5.2, §9.3, §11.6, §12.8, §13.2 (lisible sans couleur).
-- Dépendances : Config/Nebbies, Config/Balance, Config/Cosmetics.

local Types = require(script.Parent.Parent.Types)

local NebbyBuilder = {}

export type Lod = "full" | "ball" | "hidden"

export type BuildOptions = {
	aura: boolean?, -- instances d'aura de rareté (défaut true en "full")
	highlight: boolean?, -- Highlight (Mythique+ ou tête de file ≥ 20), budget de l'appelant
	trail: boolean?, -- Trail (Légendaire, Comet) ; false en Graphismes légers
	light: boolean?, -- PointLight (Légendaire+), budget de l'appelant
	rookieBubble: boolean?, -- bulle dorée du bouclier débutant
	particleMult: number?, -- 0,3 en Graphismes légers
}

export type AnimState = {
	t: number, -- temps (s) pour les oscillations
	phase: number, -- décalage propre au Nebby
	blink: boolean, -- yeux fermés cette image
	speed: number, -- vitesse de déplacement (0 = immobile)
}

export type Rig = {
	model: Model, -- non parenté
	body: BasePart,
	parts: { BasePart }, -- toutes les pièces à déplacer (body en premier)
	offsets: { CFrame }, -- pose de repos relative au corps
	pose: { CFrame }, -- pose animée courante (mise à jour par animate)
	code: Types.NebbyCode,
	stars: number,
	lod: Lod,
	size: number, -- taille du corps T (avec Huge)
}

function NebbyBuilder.build(_code: Types.NebbyCode, _stars: number, _lod: Lod, _opts: BuildOptions?): Rig
	error("TODO(world): NebbyBuilder.build")
end

-- Reconstruit ou réduit le rig au nouveau niveau de détail (même code)
function NebbyBuilder.setLod(_rig: Rig, _lod: Lod): Rig
	error("TODO(world): NebbyBuilder.setLod")
end

-- Met à jour rig.pose (oscillations d'archétype, clignement)
function NebbyBuilder.animate(_rig: Rig, _state: AnimState)
	error("TODO(world): NebbyBuilder.animate")
end

-- Ajoute les pièces du rig et leurs CFrame monde (root × pose) aux listes de BulkMoveTo
function NebbyBuilder.appendCFrames(_rig: Rig, _root: CFrame, _parts: { BasePart }, _cframes: { CFrame })
	error("TODO(world): NebbyBuilder.appendCFrames")
end

-- Taille du corps (studs), Huge compris
function NebbyBuilder.bodySize(_code: Types.NebbyCode): number
	error("TODO(world): NebbyBuilder.bodySize")
end

-- Couleur du corps à l'instant t (cycle HSV pour Prismatic / Cosmique)
function NebbyBuilder.bodyColor(_code: Types.NebbyCode, _t: number?): Color3
	error("TODO(world): NebbyBuilder.bodyColor")
end

-- Nombre de pièces du rig pour ce code et ce niveau de détail (budget §12.8)
function NebbyBuilder.partCount(_code: Types.NebbyCode, _lod: Lod): number
	error("TODO(world): NebbyBuilder.partCount")
end

function NebbyBuilder.buildWisp(): Rig
	error("TODO(world): NebbyBuilder.buildWisp")
end

-- Orbe de la Comète au sol (3 studs + anneau Néon doré)
function NebbyBuilder.buildCometOrb(): Rig
	error("TODO(world): NebbyBuilder.buildCometOrb")
end

-- Comète dans le ciel (Ball Néon 6 + Fire + Trail + Sparkles)
function NebbyBuilder.buildCometSky(): Model
	error("TODO(world): NebbyBuilder.buildCometSky")
end

function NebbyBuilder.destroy(_rig: Rig)
	error("TODO(world): NebbyBuilder.destroy")
end

return NebbyBuilder
