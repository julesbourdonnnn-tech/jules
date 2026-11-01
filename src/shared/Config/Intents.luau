--!strict
-- Catalogue des INTENTIONS (remotes client → serveur, GDD §12.7). Contrat (architecte).
-- Source unique pour : le service propriétaire du handler, le débit (RateLimit.allow(player, nom,
-- rate[1], rate[2])), la forme de la charge utile (validée par le handler, ET utilisée par le
-- fuzzeur de la couche b, tests/harness/Fuzz) et le débit côté client (anti-rafale de l'interface).
-- Règle : un remote client → serveur porte une INTENTION, jamais une valeur de jeu. Chaque handler
-- suit l'ordre : débit → types (cette description) → existence → état → règles → mutation → réplication.
-- Un message refusé ne produit AUCUNE mutation et au plus un Feedback neutre.
--
-- Sortes d'arguments (`kind`) :
--   "uid"        chaîne base 36 de 1 à 8 caractères ([0-9a-z]) ; doit être possédée par l'envoyeur
--   "uidOpt"     "uid" ou nil
--   "uids"       table séquentielle de 1 à `max` uids UNIQUES (aucun trou, aucune clé non entière)
--   "time"       nombre fini (horodatage Clock.now() du client ; borné par le handler)
--   "dir"        nombre fini (composante d'une direction ; la norme est vérifiée par le handler)
--   "bool"       booléen
--   "int"        entier dans [min ; max]
--   "userId"     entier > 0 (≤ 2^53)
--   "userIds"    table séquentielle de 0 à `max` userId
--   "key"        chaîne dans l'ensemble `set` (clés de configuration)
--   "str"        chaîne UTF-8 valide de `max` caractères au plus (tronquée au-delà quand `truncate`)
--   "setting"    booléen ou chaîne (validé contre Config/Settings par le handler)

export type ArgSpec = {
	name: string,
	kind: string,
	min: number?,
	max: number?,
	set: { string }?,
	truncate: boolean?,
}

export type IntentSpec = {
	owner: string, -- service serveur qui connecte OnServerEvent (un seul)
	rate: { number }, -- { appels, par secondes } (seau à jetons, Server/Util/RateLimit)
	args: { ArgSpec },
	clientRate: { number }?, -- débit côté client quand il diffère (Emote)
}

local TILES = { "snack", "decor", "pens", "cozyBed" }
local MOVE_TO = { "pen", "dodo" }
local COSMETIC_KINDS = { "saddle", "trail", "title", "theme", "flag" }

-- stylua: ignore start
local Intents: { [string]: IntentSpec } = {
	-- Ranch, collection (SquishyService, EconomyService)
	Press = { owner = "SquishyService", rate = { 12, 1 }, args = { { name = "uid", kind = "uid" }, { name = "tClient", kind = "time" } } },
	PickUp = { owner = "SquishyService", rate = { 4, 1 }, args = { { name = "uid", kind = "uid" } } },
	PutDown = { owner = "SquishyService", rate = { 4, 1 }, args = {} },
	Throw = { owner = "SquishyService", rate = { 4, 1 }, args = {} },
	FuseMenu = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "uidA", kind = "uid" }, { name = "uidB", kind = "uid" } } },
	FuseAll = { owner = "SquishyService", rate = { 1, 2 }, args = {} },
	BuyTile = { owner = "EconomyService", rate = { 10, 1 }, args = { { name = "tile", kind = "key", set = TILES } } },
	MoveSquishy = { owner = "SquishyService", rate = { 4, 1 }, args = { { name = "uid", kind = "uid" }, { name = "to", kind = "key", set = MOVE_TO } } },
	ClaimMail = { owner = "SquishyService", rate = { 4, 1 }, args = { { name = "uid", kind = "uid" } } },
	Sell = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "uids", kind = "uids", max = 84 }, { name = "confirmed", kind = "bool" } } },
	Release = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "uids", kind = "uids", max = 84 }, { name = "confirmed", kind = "bool" } } },
	SetLock = { owner = "SquishyService", rate = { 6, 1 }, args = { { name = "uid", kind = "uid" }, { name = "locked", kind = "bool" } } },
	SetBestFriend = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "uid", kind = "uid" }, { name = "slot", kind = "int", min = 1, max = 3 } } },
	SetMount = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "uid", kind = "uid" } } },
	Ride = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "on", kind = "bool" } } },
	EquipOutfit = { owner = "SquishyService", rate = { 2, 1 }, args = { { name = "outfit", kind = "str", max = 32 }, { name = "uid", kind = "uidOpt" } } },
	-- Poursuites (ChaseService)
	Leap = { owner = "ChaseService", rate = { 3, 1 }, args = { { name = "dirX", kind = "dir" }, { name = "dirZ", kind = "dir" } } },
	Catch = { owner = "ChaseService", rate = { 6, 1 }, args = { { name = "id", kind = "int", min = 1, max = 65535 } } },
	-- BOOP RUSH (RushService)
	BoopHold = { owner = "RushService", rate = { 4, 1 }, args = { { name = "ownerId", kind = "userId" }, { name = "uid", kind = "uid" }, { name = "holding", kind = "bool" } } },
	SetMode = { owner = "RushService", rate = { 1, 1 }, args = { { name = "rush", kind = "bool" } } },
	RefuseBooper = { owner = "RushService", rate = { 2, 1 }, args = { { name = "userId", kind = "userId" } } },
	-- Événements (EventService)
	MegaPress = { owner = "EventService", rate = { 3, 1 }, args = { { name = "tClient", kind = "time" } } },
	AdminCommand = { owner = "EventService", rate = { 2, 1 }, args = { { name = "command", kind = "str", max = 32 }, { name = "arg", kind = "str", max = 64 } } },
	-- Grand Splorch (SplorchService)
	GrandSplorch = { owner = "SplorchService", rate = { 1, 2 }, args = { { name = "film", kind = "bool" }, { name = "flyer", kind = "uid" } } },
	-- Accueil, objectifs, Nourrir Plop, Squishydex (QuestService)
	FeedPlop = { owner = "QuestService", rate = { 2, 1 }, args = { { name = "holding", kind = "bool" } } },
	ClaimObjective = { owner = "QuestService", rate = { 4, 1 }, args = { { name = "slot", kind = "int", min = 1, max = 3 } } },
	RerollObjective = { owner = "QuestService", rate = { 4, 1 }, args = { { name = "slot", kind = "int", min = 1, max = 3 } } },
	ClaimDexReward = { owner = "QuestService", rate = { 2, 1 }, args = {} },
	-- Écran vu par le joueur (fait que seul le client connaît) : étape 10 de l'accueil (objectifs vus),
	-- départ du délai de la carte du choix (RushModeChosen = −1 sans réponse), analytique. Une fois par
	-- écran et par session ; ne donne jamais rien (aucune récompense, aucune mutation économique).
	UiSeen = { owner = "QuestService", rate = { 2, 1 }, args = { { name = "screen", kind = "key", set = { "objectives", "modeCard", "postBoop", "booped", "shop", "dex", "leaderboards" } } } },
	-- Social (CommunityService)
	PetPress = { owner = "CommunityService", rate = { 12, 1 }, args = { { name = "ownerId", kind = "userId" }, { name = "uid", kind = "uid" }, { name = "tClient", kind = "time" } } },
	SetSetting = { owner = "CommunityService", rate = { 4, 1 }, args = { { name = "key", kind = "str", max = 32 }, { name = "value", kind = "setting" } } },
	EquipCosmetic = { owner = "CommunityService", rate = { 2, 1 }, args = { { name = "kind", kind = "key", set = COSMETIC_KINDS }, { name = "id", kind = "str", max = 32 } } },
	Emote = { owner = "CommunityService", rate = { 1, 1.2 }, clientRate = { 1, 1.5 }, args = { { name = "kind", kind = "int", min = 1, max = 3 } } },
	Clap = { owner = "CommunityService", rate = { 2, 1 }, args = { { name = "heroId", kind = "userId" } } },
	ReportBlocked = { owner = "CommunityService", rate = { 1, 10 }, args = { { name = "userIds", kind = "userIds", max = 200 } } },
	-- Monde (RanchService) : redemande de l'état des ranchs, des événements et des créatures
	RequestWorld = { owner = "RanchService", rate = { 1, 2 }, args = {} },
	-- Diagnostics (DiagnosticsService, GDD §12.11)
	SetInputType = { owner = "DiagnosticsService", rate = { 1, 5 }, args = { { name = "kind", kind = "int", min = 1, max = 3 }, { name = "tenFoot", kind = "bool" } } },
	ReportError = { owner = "DiagnosticsService", rate = { 1, 2 }, args = {
		{ name = "kind", kind = "int", min = 1, max = 2 },
		{ name = "key", kind = "str", max = 64, truncate = true },
		{ name = "message", kind = "str", max = 300, truncate = true },
		{ name = "trace", kind = "str", max = 600, truncate = true },
		{ name = "ctx", kind = "str", max = 120, truncate = true },
	} },
	RequestDiagnostics = { owner = "DiagnosticsService", rate = { 1, 2 }, args = { { name = "tab", kind = "int", min = 1, max = 3 } } },
}
-- stylua: ignore end

return Intents
