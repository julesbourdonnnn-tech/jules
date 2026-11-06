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
--   "time"       nombre fini (horodatage Clock.now() du client ; borné par le handler) : Press, PetPress et
--                MegaPress par PressTiming.clampClientTime ([maintenant − 0,35 ; maintenant + 0,05]) ;
--                Catch et Leap ramenés dans [maintenant − Balance.Catch.ClientPast ; maintenant]
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
	-- intention de JEU : une fois acceptée (après débit, types et règles), le handler appelle
	-- Activity.note(player, Clock.now()) (Server/Util/Activity : joueurs actifs du MEGA et de la jauge,
	-- GDD v1.3 §4.22). Les intentions d'interface, de réglage et de diagnostic ne comptent pas.
	activity: boolean?,
}

local TILES = { "snack", "decor", "pens", "cozyBed" }
local MOVE_TO = { "pen", "dodo" }
-- v2.0 (lot A4, D20) : palette du spectacle du Grand Splorch et coussins des enclos (profil v2,
-- cosmetics.palette / cosmetics.cushions, attributs Palette / Cushions du ranch)
local COSMETIC_KINDS = { "saddle", "trail", "title", "theme", "flag", "palette", "cushions" }

-- stylua: ignore start
local Intents: { [string]: IntentSpec } = {
	-- Ranch, collection (SquishyService, EconomyService)
	Press = { owner = "SquishyService", rate = { 12, 1 }, activity = true, args = { { name = "uid", kind = "uid" }, { name = "tClient", kind = "time" } } },
	PickUp = { owner = "SquishyService", rate = { 4, 1 }, activity = true, args = { { name = "uid", kind = "uid" } } },
	PutDown = { owner = "SquishyService", rate = { 4, 1 }, activity = true, args = {} },
	Throw = { owner = "SquishyService", rate = { 4, 1 }, activity = true, args = {} },
	FuseMenu = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "uidA", kind = "uid" }, { name = "uidB", kind = "uid" } } },
	FuseAll = { owner = "SquishyService", rate = { 1, 2 }, activity = true, args = {} },
	BuyTile = { owner = "EconomyService", rate = { 10, 1 }, activity = true, args = { { name = "tile", kind = "key", set = TILES } } },
	-- v2.0 (lot A2, note INT-V2-INTENTS : venue de Config/IntentsV2 avec son handler) : écran
	-- Améliorations [UpgradesScreen] (EconomyService.buyUpgrade, même chemin que BuyTile) : id ∈
	-- Config/Upgrades (Families, WorkshopRows, lignes « bits » de Fun) ; mode 1, 10 ou 0 (= Max), toute
	-- autre valeur refusée par le handler AVANT UpgradeMath.plan ; expectedLevel = niveau que l'écran
	-- montre (sinon refus « périmé » : UpgradeResult sans retour visible, compteur UpgradeStale)
	BuyUpgrade = { owner = "EconomyService", rate = { 10, 1 }, activity = true, args = {
		{ name = "id", kind = "str", max = 24 },
		{ name = "mode", kind = "int", min = 0, max = 10 },
		{ name = "expectedLevel", kind = "int", min = 0, max = 64 },
	} },
	MoveSquishy = { owner = "SquishyService", rate = { 4, 1 }, activity = true, args = { { name = "uid", kind = "uid" }, { name = "to", kind = "key", set = MOVE_TO } } },
	ClaimMail = { owner = "SquishyService", rate = { 4, 1 }, activity = true, args = { { name = "uid", kind = "uid" } } },
	Sell = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "uids", kind = "uids", max = 84 }, { name = "confirmed", kind = "bool" } } },
	Release = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "uids", kind = "uids", max = 84 }, { name = "confirmed", kind = "bool" } } },
	SetLock = { owner = "SquishyService", rate = { 6, 1 }, activity = true, args = { { name = "uid", kind = "uid" }, { name = "locked", kind = "bool" } } },
	SetBestFriend = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "uid", kind = "uid" }, { name = "slot", kind = "int", min = 1, max = 3 } } },
	SetMount = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "uid", kind = "uid" } } },
	Ride = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "on", kind = "bool" } } },
	EquipOutfit = { owner = "SquishyService", rate = { 2, 1 }, activity = true, args = { { name = "outfit", kind = "str", max = 32 }, { name = "uid", kind = "uidOpt" } } },
	-- Poursuites (ChaseService)
	-- tClient (contrat v1.2, GDD §12.5, §12.8) : bond = crédit MoveCheck.grant rétroactif, capture à
	-- l'atterrissage tentée à tClient + Balance.Leap.Duration ; capture vérifiée à SON instant tClient
	Leap = { owner = "ChaseService", rate = { 3, 1 }, activity = true, args = { { name = "dirX", kind = "dir" }, { name = "dirZ", kind = "dir" }, { name = "tClient", kind = "time" } } },
	Catch = { owner = "ChaseService", rate = { 6, 1 }, activity = true, args = { { name = "id", kind = "int", min = 1, max = 65535 }, { name = "tClient", kind = "time" } } },
	-- BOOP RUSH (RushService)
	BoopHold = { owner = "RushService", rate = { 4, 1 }, activity = true, args = { { name = "ownerId", kind = "userId" }, { name = "uid", kind = "uid" }, { name = "holding", kind = "bool" } } },
	SetMode = { owner = "RushService", rate = { 1, 1 }, args = { { name = "rush", kind = "bool" } } },
	RefuseBooper = { owner = "RushService", rate = { 2, 1 }, args = { { name = "userId", kind = "userId" } } },
	-- Événements (EventService)
	MegaPress = { owner = "EventService", rate = { 3, 1 }, activity = true, args = { { name = "tClient", kind = "time" } } },
	AdminCommand = { owner = "EventService", rate = { 2, 1 }, args = { { name = "command", kind = "str", max = 32 }, { name = "arg", kind = "str", max = 64 } } },
	-- Grand Splorch (SplorchService)
	GrandSplorch = { owner = "SplorchService", rate = { 1, 2 }, activity = true, args = { { name = "film", kind = "bool" }, { name = "flyer", kind = "uid" } } },
	-- v2.0 (lot A2, note INT-V2-INTENTS : venue de Config/IntentsV2 avec son handler) : Jelly Ascend
	-- [JellyAscend] (SplorchService.ascend) : maintien de 3 s et carte « Prêt à monter ? » côté client ;
	-- confirm = true exigé ; Prestige.ascendReady et les conditions d'entrée vérifiés une seule fois, à
	-- l'entrée dans la file du Grand Splorch (un seul prestige par joueur dans la file)
	JellyAscend = { owner = "SplorchService", rate = { 1, 5 }, activity = true, args = {
		{ name = "confirm", kind = "bool" },
	} },
	-- Accueil, objectifs, Nourrir Plop, Squishydex (QuestService)
	FeedPlop = { owner = "QuestService", rate = { 2, 1 }, activity = true, args = { { name = "holding", kind = "bool" } } },
	ClaimObjective = { owner = "QuestService", rate = { 4, 1 }, activity = true, args = { { name = "slot", kind = "int", min = 1, max = 3 } } },
	RerollObjective = { owner = "QuestService", rate = { 4, 1 }, activity = true, args = { { name = "slot", kind = "int", min = 1, max = 3 } } },
	ClaimDexReward = { owner = "QuestService", rate = { 2, 1 }, activity = true, args = {} },
	-- Écran vu par le joueur (fait que seul le client connaît) : étape 10 de l'accueil (objectifs vus),
	-- départ du délai de la carte du choix (RushModeChosen = −1 sans réponse), analytique. Une fois par
	-- écran et par session ; ne donne jamais rien (aucune récompense, aucune mutation économique).
	-- v2.0 (lot A4, D32) : "nextBuy" = puce « Prochain achat » apparue (onboarding.nextBuyShown d'un
	-- profil v2, interrupteur UpgradesScreen ; envoyée par le HUD de B2)
	UiSeen = { owner = "QuestService", rate = { 2, 1 }, args = { { name = "screen", kind = "key", set = { "objectives", "modeCard", "postBoop", "booped", "shop", "dex", "leaderboards", "nextBuy" } } } },
	-- v2.0 (lot A4, N23, décision du propriétaire du 6 novembre) : la navigation dans un menu ouvert
	-- compte pour la sieste des Plopettes (le client l'envoie à l'ouverture d'un panneau et pendant la
	-- navigation, une au plus toutes les 20 s). Réveille seulement les Plopettes (Activity.noteMenu) :
	-- jamais une activité de jeu (ni MEGA ni jauge), jamais une récompense ni une progression
	MenuActivity = { owner = "QuestService", rate = { 1, 10 }, args = {} },
	-- Social (CommunityService)
	PetPress = { owner = "CommunityService", rate = { 12, 1 }, activity = true, args = { { name = "ownerId", kind = "userId" }, { name = "uid", kind = "uid" }, { name = "tClient", kind = "time" } } },
	SetSetting = { owner = "CommunityService", rate = { 4, 1 }, args = { { name = "key", kind = "str", max = 32 }, { name = "value", kind = "setting" } } },
	EquipCosmetic = { owner = "CommunityService", rate = { 2, 1 }, activity = true, args = { { name = "kind", kind = "key", set = COSMETIC_KINDS }, { name = "id", kind = "str", max = 32 } } },
	Emote = { owner = "CommunityService", rate = { 1, 1.2 }, activity = true, clientRate = { 1, 1.5 }, args = { { name = "kind", kind = "int", min = 1, max = 3 } } },
	Clap = { owner = "CommunityService", rate = { 2, 1 }, activity = true, args = { { name = "heroId", kind = "userId" } } },
	ReportBlocked = { owner = "CommunityService", rate = { 1, 10 }, args = { { name = "userIds", kind = "userIds", max = 200 } } },
	-- v2.0 (lot A4, note INT-V2-INTENTS : venues de Config/IntentsV2 avec leur handler, mêmes débits et
	-- arguments). Déco perso [DecoPerso] : objet possédé (1-64, 0 = retirer) dans un emplacement 1-12 de
	-- la bonne taille (Cosmetics.DecoSlots), jamais posé deux fois
	PlaceDeco = { owner = "CommunityService", rate = { 4, 1 }, args = {
		{ name = "item", kind = "int", min = 0, max = 64 },
		{ name = "slot", kind = "int", min = 1, max = 12 },
	} },
	-- Cœur [Hearts] donné au ranch d'un autre joueur présent (pas soi, pas bloqué, 1 par ranch et 20 par
	-- jour UTC) : intention de jeu
	GiveHeart = { owner = "CommunityService", rate = { 2, 1 }, activity = true, args = {
		{ name = "ownerId", kind = "userId" },
	} },
	-- Mode photo [PhotoMode] : analytique et état en mémoire ; personnage figé par le client MAIS VISIBLE
	-- des autres (N22) ; aucun avantage
	SetPhotoMode = { owner = "CommunityService", rate = { 1, 1 }, args = {
		{ name = "on", kind = "bool" },
	} },
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
	-- Faits d'analytique que seul le client connaît (contrat v1.2, remarque A21) : « qualityReduced »
	-- (QualityController : qualité adaptative descendue), « shopOpened » (Panels/Shop : chaque
	-- ouverture). Analytique SEULEMENT (QualityReduced, ShopOpened), 20 par session au plus ; ne change
	-- jamais rien au jeu. « Objectifs vus » (étape 10 de l'accueil) passe par UiSeen("objectives").
	ClientEvent = { owner = "DiagnosticsService", rate = { 1, 5 }, args = { { name = "kind", kind = "key", set = { "qualityReduced", "shopOpened" } } } },
	-- v2.0 (lot A4, D29) : faits que seul le client v2.0 mesure, 20 par session au plus. Compteurs de
	-- Diagnostics et analytique SEULEMENT (jamais un changement du jeu ; ClientEvent reste celui de la
	-- v1.3) ; chaque sorte derrière son interrupteur : upgradeTimeout (1 par réponse d'achat manquée en
	-- 3 s), upgradeMode (1 ×1, 10 ×10, 0 Max) [UpgradesScreen] ; ascendPreview (0 ouvert, 1 annulé,
	-- 2 confirmé), ascendDeclined (jours depuis que l'Ascension est prête) [JellyAscend] ; textScale
	-- (facteur mesuré × 100), styleFallback (1 UIShadow absent, 2 dégradé radial absent), visualBudget
	-- (budget visuel dépassé) : toujours
	ClientMetric = { owner = "DiagnosticsService", rate = { 1, 5 }, args = {
		{ name = "kind", kind = "key", set = { "upgradeTimeout", "upgradeMode", "ascendPreview", "ascendDeclined", "textScale", "styleFallback", "visualBudget" } },
		{ name = "value", kind = "int", min = 0, max = 1000 },
	} },
}
-- stylua: ignore end

return Intents
