--!strict
-- VFXController (paquet client-world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Effets des moments de jeu (GDD §9.1, §9.4) sur Celebrate et sur les signaux du miroir : SPLORCH
-- (fontaine de pièces, « +N »), PERFECT et série, dalle construite, Pot, naissances par rareté et
-- révélation de mutation (Flop, Glitch, Arc-en-ciel en grand), fusion et combo, captures, ATCHOUM,
-- Grand Splorch (7,5 s, ralenti, pluie de cadeaux), MEGA (atterrissage, pression, éclatement,
-- échec), jauge pleine, Golden, Jelly Moon, Nourrir Plop, achat. Réserves (120 gouttes, 20 textes),
-- budgets de QualityController, Mouvement réduit, vibrations (Haptics) au bon moment. Clips
-- automatiques (CaptureService sous pcall : Légendaire+, Arc-en-ciel / Glitch / Flop, COMBO ×5, mon
-- Grand Splorch ; réglage clips, interrupteur du serveur, PolicyService IsContentSharingAllowed en
-- cache ; arrêt au plus tard 8 s après) → carte « clip » de Cards SEULEMENT si StartVideoCaptureAsync a
-- réussi (contrat v1.2). Grand Splorch d'un autre en version courte (data.short) : ni capsule, ni
-- secousse, ni vibration ; « +N » par UI/WorldText ; vibration pressTick seulement sur une pression
-- PERFECT du MEGA (VFXController seul la borne à 2 par seconde) ; perfect + 0,03 par cran de série. Bannières et effets d'événement
-- seulement si l'interrupteur du serveur est vrai (WorldStateController.event().features).

local VFXController = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function VFXController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function VFXController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Texte qui monte (« +1,2K »)
function VFXController.floatText(pos: Vector3, text: string, color: Color3?, scale: number?)
	local _ = { pos, text, color, scale }
	error("TODO(client-world): VFXController.floatText")
end

-- Grand tampon à l'écran (« PERFECT ! », « COMBO x5 ! »)
function VFXController.stamp(key: string, vars: { [string]: any }?, color: Color3?)
	local _ = { key, vars, color }
	error("TODO(client-world): VFXController.stamp")
end

-- Pièces qui volent vers le compteur
function VFXController.flyCoins(from: Vector3, count: number)
	local _ = { from, count }
	error("TODO(client-world): VFXController.flyCoins")
end

-- Anneau Neon qui s'élargit
function VFXController.ring(pos: Vector3, color: Color3, diameter: number, duration: number)
	local _ = { pos, color, diameter, duration }
	error("TODO(client-world): VFXController.ring")
end

-- Gerbe de particules (bornée par le budget)
function VFXController.burst(pos: Vector3, color: Color3, count: number)
	local _ = { pos, color, count }
	error("TODO(client-world): VFXController.burst")
end

-- Gouttes de gelée (réserve de 120)
function VFXController.blobs(pos: Vector3, color: Color3, count: number)
	local _ = { pos, color, count }
	error("TODO(client-world): VFXController.blobs")
end

-- Capsule de bébé qui tombe près du joueur puis saute vers son ranch
function VFXController.capsule(pos: Vector3, species: number)
	local _ = { pos, species }
	error("TODO(client-world): VFXController.capsule")
end

-- Compteurs (particules actives, instances en réserve) pour les specs de budget
function VFXController.stats(): { [string]: number }
	error("TODO(client-world): VFXController.stats")
end

return VFXController
