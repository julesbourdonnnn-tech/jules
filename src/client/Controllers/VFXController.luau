--!strict
-- VFXController — paquet « client-world » (STUB du contrat : docs/04-architecture.md §13.8).
-- Effets 3D du §9 (le juice d'écran — tampons, pièces volantes, vignette — est dans UI/ScreenFX,
-- paquet client-hud). Réserves d'instances (aucune création en rafale), une animation par propriété,
-- fondus de pièces 3D en RÉTRÉCISSANT (Transparency reste 0 ou 1). Mouvement réduit : pas de
-- secousse, de coup de focale ni de flash. Graphismes légers : particules × 0,3, pas de Trail sauf
-- la Comète, Highlight seulement sur le porteur, lumières coupées au-delà de 60 studs.
-- Responsabilités (réactions aux signaux de WorldStateController) :
--   * capture : 10 particules couleur de rareté, « +1 Puffkin » (taille selon la rareté), « ? » doré
--     si nouvelle entrée ; Rare+ : colonne Néon 0,6 s ; Épique+ : focale 70 → 74 → 70, vibration ;
--     Légendaire+ : colonne de 4 s ; Mythique+ : confettis
--   * coupe : flash blanc du nœud coupé, 12 étincelles, « SNIP ! » 3D (Elastic Out) au point touché ;
--     victime : traînées de vitesse 3 s ; coupeur : anneau Snip Rush de 6 studs pendant 3 s
--   * parade : « +valeur » sur les 12 premiers puis un total, 3 feux d'artifice si ≥ 15, flash de
--     l'arche ; Balise : orbes vers la Balise
--   * Comète : traversée du ciel (6 s), impact (3 anneaux, PointLight, pilier, secousse selon la
--     distance), porteur (anneau de 8 boules dorées, Highlight, faisceau de 200 studs), vol (orbe en
--     arc 0,2 s), encaissement (5 feux) / explosion (clignote puis 5 Épiques en arcs)
--   * Gloomwisp éclaté, Supernova (séquence de 2,5 s, nouvelle étoile de constellation),
--     amélioration (anneau au sol, silhouette fantôme, perchoir qui pousse), Dash (Trail + focale),
--     bouclier débutant (bulles qui éclatent), Zen (anneau turquoise), pings (BillboardGui 4 × 4,
--     2,5 s, visible à 200 studs), acclamations (confettis vers le Nid du héros)
-- GDD : §9.1 (fonctions), §9.4, §13.2.
-- Dépendances : StateController, AudioController, Util/Prefs, UI/Juice, WorldStateController,
-- CongaRenderer, Render/NebbyBuilder, Logic/WorldLayout, Config/*, Shared/Util/Clock.

local VFXController = {}

function VFXController.Init() end

function VFXController.Start() end

-- Texte « +N » dans le monde (réserve de 20 BillboardGui)
function VFXController.floatText(_worldPos: Vector3, _text: string, _color: Color3, _scale: number?)
	error("TODO(client-world): VFXController.floatText")
end

-- Onde Néon au sol (Cylinder plat) de 0 à `radius`
function VFXController.ring(_worldPos: Vector3, _radius: number, _color: Color3, _duration: number)
	error("TODO(client-world): VFXController.ring")
end

-- ParticleEmitter:Emit sur un émetteur réutilisé
function VFXController.burst(_worldPos: Vector3, _color: Color3, _count: number)
	error("TODO(client-world): VFXController.burst")
end

-- Colonne Néon qui s'amincit
function VFXController.pillar(_worldPos: Vector3, _color: Color3, _duration: number, _height: number?)
	error("TODO(client-world): VFXController.pillar")
end

-- Coup de focale (ignoré en Mouvement réduit)
function VFXController.fovPunch(_delta: number, _outTime: number, _backTime: number)
	error("TODO(client-world): VFXController.fovPunch")
end

-- Vibration mobile via HapticService si supportée
function VFXController.haptic(_strength: number, _duration: number)
	error("TODO(client-world): VFXController.haptic")
end

function VFXController.fireworks(_worldPos: Vector3, _count: number, _color: Color3?)
	error("TODO(client-world): VFXController.fireworks")
end

-- Dash local confirmé par InputController : Trail aux pieds 1 s, nuage, focale 70 → 78 → 70
function VFXController.playDash()
	error("TODO(client-world): VFXController.playDash")
end

-- Amélioration (anneau, fantôme Conga, perchoir) — appelé sur Celebrate "upgrade"
function VFXController.playUpgrade(_track: string, _level: number)
	error("TODO(client-world): VFXController.playUpgrade")
end

-- Séquence de Supernova (2,5 s) au Nid du slot
function VFXController.playSupernova(_slot: number, _level: number)
	error("TODO(client-world): VFXController.playSupernova")
end

return VFXController
