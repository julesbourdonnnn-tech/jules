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
	JellyAscend = false,
	Season = false,
	SlowJelly = false,
	Duo = false,
	Parcels = false,
	WorldFirst = false,
	FameLineage = false,
	GreatJelly = false,
}

local Features = {}

-- Valeurs en vigueur (copie modifiable par Features.set ; jamais par un client)
local current: { [string]: any } = table.clone(Defaults)

Features.Defaults = Defaults

-- Valeur en vigueur d'un interrupteur (nil pour une clé inconnue)
function Features.get(key: string): any
	return current[key]
end

-- Change un interrupteur (serveur : EventService sur un message LiveOps validé ; tests). Refuse une
-- clé inconnue ou une valeur d'un autre type que la valeur de lancement. Renvoie true si appliqué.
function Features.set(key: string, value: any): boolean
	local default = (Defaults :: any)[key]
	if default == nil or typeof(value) ~= typeof(default) then
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
