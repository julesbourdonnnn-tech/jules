--!strict
-- Interrupteurs de configuration (GDD §12.2). Contrat (architecte).
-- Lus au démarrage, puis remplacés en direct par un message LiveOps d'administrateur
-- (EventService, sujet MessagingService Events.Party.LiveOpsTopic) : chaque lecture passe par
-- Features.get(clé) et jamais par une copie locale gardée en mémoire.
-- Les valeurs ci-dessous sont celles du LANCEMENT. Les fonctions de janvier et février restent à
-- false : le code de lancement n'en contient que les crochets (GDD §17.2).

export type BoopRushMode = "on" | "events" | "off"

local Defaults = {
	BoopRush = "on" :: BoopRushMode, -- "events" : Lune et fêtes d'administrateur seulement ; "off" : Wild Wobblers seuls
	MegaSquish = true,
	GoldenWobbler = true,
	JellyMoon = true,
	ServerGauge = true,
	Clips = true, -- captures vidéo automatiques
	Costumes = "winter2026", -- costume de saison actif (Events.Costumes)
	Diagnostics = true, -- false : coupe seulement l'envoi des clients ; les comptes du serveur restent
	RewardedAds = false, -- aucune publicité au lancement (la clé existe pour ne jamais l'ajouter par défaut)
	-- janvier et février (crochets seulement)
	JellyAscend = true, -- OUVERT au lot I, étape 2 (avec PetitSplorch, même commit : D32 du lot B2)
	Season = false,
	SlowJelly = false,
	Duo = false,
	Parcels = false,
	WorldFirst = false,
	FameLineage = false,
	GreatJelly = false,
	-- =========================================================================================
	-- Contrat v2.0 (GDD v2.0, docs/04 §27) : CHAQUE système du jeu complet derrière son
	-- interrupteur, COUPÉ tant que son paquet n'est pas implémenté ET relu. Le jeu de base joue donc
	-- exactement comme la version de test (commit 7382f88). Valeur de lancement de chacun : true
	-- (décision par défaut n° 6 : tout au lancement) ; elle est posée à l'étape d'intégration I, dans
	-- le même lot que la spec qui la vérifie (docs/04 §27.3). JellyAscend (plus haut) en fait partie.
	-- =========================================================================================
	-- OUVERT au lot I (étape 1, docs/04 §27.2 règle D3) : une fois ouvert, JAMAIS recoupé en production
	-- (un profil migré ne revient jamais en v1 ; un serveur v1 refuse un profil v2 sans rien écrire)
	SchemaV2 = true, -- schéma v2 et migration v1 → v2 (Data/Schema) ; FIGÉ : jamais changé en direct
	-- OUVERTS au lot I, étape 2 (progression, journal I-19) : coupables en direct par LiveOps
	UpgradesScreen = true, -- écran Améliorations (4 onglets), BuyUpgrade, puce « Prochain achat »
	Confetti = true, -- 2e monnaie (gains de Prestige.apply, piste, maîtrise)
	Workshop = true, -- Atelier de Big Plop (9 lignes) et « Pour le plaisir »
	StarMat = true, -- Tapis Étoilé (niveaux 13 à 20 du Tapis)
	Gloves = true, -- Gants Moelleux (40 niveaux)
	Monuments = true, -- 10 Monuments derrière le ranch
	RecordR = true, -- Record R séparé de r (bestR), table des déblocages du §4.29
	PetitSplorch = true, -- Petit Splorch hors file (après une Ascension)
	Helpers = true, -- Plopettes (HelperService) et École des Plopettes
	-- OUVERTS au lot I, étape 3 (méta, journal I-24) : coupables en direct par LiveOps
	WeeklyTrack = true, -- piste de la semaine et Défis de Splorch
	Carnet = true, -- Carnet du Ranch (paliers d'achats)
	Mastery = true, -- maîtrise d'espèce (+25 Confettis) et jalons géants
	RanchTiers = false, -- ranch qui évolue (paliers, Cuve, Pot, coussins, socles) ; lot I, étape 5
	RanchSkins = true, -- 11 habillages de ranch de plus (valeurs de cosmetics.theme, EquipCosmetic)
	DecoPerso = true, -- Déco perso : 40 objets, 12 emplacements (PlaceDeco)
	Hearts = true, -- cœurs entre ranchs (GiveHeart)
	PhotoMode = false, -- mode photo (SetPhotoMode)
	Weather = false, -- météo de Wobbleton (purement visuelle, décision par défaut n° 4)
	Fete = false, -- place en fête
	Personalities = false, -- personnalités, saynètes, visages, tours appris
	Ambience = false, -- directeur d'ambiance et Unified Lighting (N12)
}

-- Interrupteurs FIGÉS : lus à la création du module (Features.Defaults), jamais changés en direct
-- (Features.set les refuse) : changer le schéma des données pendant qu'un serveur tourne est interdit.
local STATIC = { SchemaV2 = true } :: { [string]: boolean }

local Features = {}

-- Valeurs en vigueur (copie modifiable par Features.set ; jamais par un client)
local current: { [string]: any } = table.clone(Defaults)

Features.Defaults = Defaults
Features.Static = STATIC

-- Valeur en vigueur d'un interrupteur (nil pour une clé inconnue)
function Features.get(key: string): any
	return current[key]
end

-- Change un interrupteur (serveur : EventService sur un message LiveOps validé ; tests). Refuse une
-- clé inconnue ou une valeur d'un autre type que la valeur de lancement. Renvoie true si appliqué.
function Features.set(key: string, value: any): boolean
	local default = (Defaults :: any)[key]
	if default == nil or typeof(value) ~= typeof(default) or STATIC[key] then
		return false
	end
	if key == "BoopRush" and value ~= "on" and value ~= "events" and value ~= "off" then
		return false
	end
	current[key] = value
	return true
end

-- Remet les valeurs de lancement (tests)
function Features.reset()
	current = table.clone(Defaults)
end

return Features
