--!strict
-- Schéma des données sauvegardées, version 1 (GDD §12.6, docs/04 §8). Contrat (architecte).
--  * augmenter VERSION et ajouter une étape dans migrate() à chaque changement incompatible
--  * ajouter un champ = l'ajouter dans defaults() (Tables.reconcile le crée chez les anciens joueurs)
--  * PRIVATE_KEYS : jamais envoyé au client
--  * STREAMED_KEYS : grandes tables envoyées par morceaux après l'instantané (DataService)
--  * UN SEUL service propriétaire écrit chaque clé (tableau OWNERS) ; les autres lisent
--    DataService.get(player) sans jamais muter, ou passent par l'API du propriétaire.
--  * Données lues = données à revalider : après migrate + reconcile, Server/Data/ProfileRepair
--    (paquet ranch) revérifie chaque champ et répare avec une valeur sûre, puis les crochets
--    DataService.onPrepare (EconomyService : rebase hors ligne) tournent AVANT l'instantané et Loaded
--    (note INT-REPAIR, docs/04 §8.5, §22)
--  * Règles des valeurs : pièces, Pot et tailles dans [0 ; 1e300], jamais NaN ni infini ; tableaux
--    denses sans trou dès les valeurs par défaut (les DataStores refusent les tableaux à trous) ;
--    horodatages SAUVEGARDÉS en Clock.unix() (entiers), jamais Clock.now() — sauf `growth.t`
--    (Clock.now() fractionnaire, borne de l'intégrale du Pot), remis à l'heure par le rebase.
-- Contract.spec : valeurs par défaut sérialisables, une clé = un propriétaire, clés privées.
--
-- Schéma v2 (contrat v2.0, GDD v2.0 §12.6, docs/04 §27.2) : décrit ICI, ACTIVÉ par l'interrupteur
-- FIGÉ Config/Features.SchemaV2 (coupé : Schema.VERSION = 1, le jeu de base lit et écrit
-- exactement la v1 de la version de test). defaultsFor(2), ownersFor(2) et l'étape pure
-- migrate(v1 → v2) existent et sont testées dès maintenant (Schema_v2.spec) ; l'étape d'intégration
-- passe SchemaV2 à true dans le même lot que Contract.spec (VERSION 2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.Settings)
local Species = require(Shared.Config.Species)
local Features = require(Shared.Config.Features)
local Upgrades = require(Shared.Config.Upgrades)

local Schema = {}

Schema.STORE_NAME = "PlayerData_v1"
-- Version écrite par CE serveur (1 tant que l'interrupteur figé SchemaV2 est coupé) ; LATEST = la
-- plus haute version que ce code sait décrire et migrer
Schema.LATEST = 2
Schema.VERSION = if Features.Defaults.SchemaV2 == true then 2 else 1

Schema.PRIVATE_KEYS = {
	receipts = true,
	codes = true,
	flags = true,
} :: { [string]: boolean }

-- Tables de profil envoyées par morceaux (au-delà de DataService.Settings.SNAPSHOT_INLINE entrées) :
-- la collection (104 squishies au plus). Ordre d'envoi : SquishyService (setStreamOrder : enclos et
-- Bassin, puis Dodo, puis Lettres).
Schema.STREAMED_KEYS = { "squishies" } :: { string }

-- Propriétaire de chaque clé de premier niveau du schéma v1 (docs/04 §8) : JAMAIS modifié
Schema.OWNERS_V1 = {
	version = "DataService",
	firstJoin = "QuestService",
	lastOnline = "EconomyService",
	settings = "CommunityService",
	passes = "MonetizationService",
	receipts = "MonetizationService",
	codes = "QuestService", -- pas de codes au lancement (aucun champ de texte, GDD §13) : toujours {}
	flags = "ChaseService", -- anti-triche : retours forcés, exclusion des classements
	-- économie
	coins = "EconomyService",
	pot = "EconomyService",
	R = "EconomyService",
	growth = "EconomyService",
	tiles = "EconomyService",
	fame = "EconomyService",
	boosts = "EconomyService",
	caps = "EconomyService",
	-- collection
	squishies = "SquishyService",
	nextUid = "SquishyService",
	mount = "SquishyService",
	vat = "SquishyService",
	released = "SquishyService",
	trophies = "SquishyService",
	outfits = "SquishyService",
	biggestEver = "SquishyService",
	-- poursuites
	golden = "ChaseService",
	-- événements : Goutte de Lune (une par séance et par compte, GDD §4.23)
	moon = "EventService",
	-- BOOP RUSH
	mode = "RushService",
	-- accueil, objectifs, Squishydex, statistiques
	dex = "QuestService",
	plopDays = "QuestService",
	lastFeedDay = "QuestService",
	onboarding = "QuestService",
	objectives = "QuestService",
	stats = "QuestService",
	-- social
	cosmetics = "CommunityService",
	-- classements
	weekly = "LeaderboardService",
	-- réservé (janvier, février) : jamais lu ni écrit au lancement
	ascend = "(réservé : Jelly Ascend)",
	season = "(réservé : saison)",
	slowJelly = "(réservé : Gelée lente)",
	parcels = "(réservé : colis)",
	fameLineage = "(réservé : lignée de Fame)",
	worldFirst = "(réservé : World First)",
	costumes = "(réservé : costumes)",
	packs = "(réservé : paquets)",
} :: { [string]: string }

-- Clés ajoutées par le schéma v2 (et propriétaires changés). ascend : le champ réservé devient A.
-- Confettis : un seul écrivain, EconomyService (addConfetti pour les gains, buyUpgrade pour les
-- dépenses) ; les autres services passent par son API (docs/04 §27.2).
Schema.OWNERS_V2 = {
	ascend = "SplorchService",
	bestR = "SplorchService",
	regainBonusA = "SplorchService",
	memoryR = "SplorchService", -- décision INT-A1-MEMORY (lot A2, journal A2-1) : écrit par Prestige.apply
	confetti = "EconomyService",
	confettiTotal = "EconomyService",
	atelier = "EconomyService",
	atelierCosmetics = "EconomyService",
	decorBuilds = "EconomyService",
	carnet = "QuestService",
	weeklyTrack = "QuestService",
	mastery = "QuestService",
	unlocksSeen = "QuestService",
	season = "QuestService", -- champ réservé : seul season.frostDays (costume d'hiver) est écrit
	decoPerso = "CommunityService",
	hearts = "CommunityService",
} :: { [string]: string }

-- Propriétaires d'une version du schéma (copie)
function Schema.ownersFor(version: number): { [string]: string }
	local out = table.clone(Schema.OWNERS_V1)
	if version >= 2 then
		for key, owner in Schema.OWNERS_V2 do
			out[key] = owner
		end
	end
	return out
end

-- Propriétaires de la version écrite par ce serveur (v1 tant que SchemaV2 est coupé)
Schema.OWNERS = Schema.ownersFor(Schema.VERSION)

local function defaultSettings(): { [string]: any }
	local out = {}
	for key, def in SettingsConfig do
		if def.saved then
			out[key] = def.default
		end
	end
	return out
end

-- Valeurs par défaut de la version écrite par ce serveur
function Schema.defaults(): { [string]: any }
	return Schema.defaultsFor(Schema.VERSION)
end

-- Ensemble de bits vide de n éléments : tableau dense de mots de 32 bits (Logic/Bitset)
local function bitset(n: number): { number }
	return table.create(math.max(1, math.ceil(n / 32)), 0)
end

-- Champs ajoutés par le schéma v2 (GDD v2.0 §12.6, docs/04 §27.2) dans un profil v1 par défaut
local function addV2Defaults(d: { [string]: any })
	d.version = 2
	-- progression : r = d.R (boucle) ; bestR = Record R (≥ R) ; ascend = A (0 à MaxA)
	d.bestR = 0
	d.ascend = 0
	d.regainBonusA = 0 -- dernier A pour lequel le bonus de retour au record a été donné
	-- Record R au moment du dernier retour au record (entier 0-400, ≤ bestR) : la 1re boucle record
	-- qui suit le retour (× 1,25, Prestige.firstRecordLoop) est celle où r = bestR = memoryR
	d.memoryR = 0
	-- Confettis : entiers de 0 à 1e9, confettiTotal ≥ confetti (jamais remis à zéro)
	d.confetti = 0
	d.confettiTotal = 0
	-- familles nouvelles (niveaux) : Tapis Étoilé 0-8, Gants 0-40, École 0-20, Monuments 0-10 (gardés)
	d.tiles.star = 0
	d.tiles.gloves = 0
	d.tiles.school = 0
	d.tiles.monuments = 0
	-- Atelier : une case par ligne de Config/Upgrades.WorkshopRows (ordre définitif) ; cosmétiques de
	-- « Pour le plaisir » en ensemble de bits
	d.atelier = table.create(#Upgrades.WorkshopRows, 0)
	d.atelierCosmetics = bitset(Upgrades.CosmeticBits)
	-- décorations dorées : constructions par décoration (18 petits entiers bornés à 10)
	d.decorBuilds = table.create(18, 0)
	-- méta
	d.stats.upgradesBought = 0 -- Carnet du Ranch
	d.stats.petitSplorches = 0 -- jamais compté dans stats.splorches
	d.carnet = bitset(8) -- paliers du Carnet réclamés
	d.weeklyTrack = {
		period = 0, -- numéro de période de QuestRules.weekIndex (jamais une semaine de l'année)
		points = 0,
		claimed = bitset(12), -- paliers réclamés (12)
		challenges = {}, -- { Types.ChallengeEntry × 3 }
		firstPeriodEnd = 0, -- Clock.unix() de fin de la 1re période (0 = à fixer par QuestService)
	}
	d.mastery = bitset(#Species.List) -- un bit par espèce, agrandi par reconcile
	d.unlocksSeen = 0 -- plus haut Record R dont la carte « Nouveau : … » a été montrée
	d.onboarding.nextBuyShown = false -- puce « Prochain achat » déjà apparue
	d.onboarding.welcomeV2Pending = false -- carte « Bienvenue dans la v2 ! » à montrer une fois
	d.season.frostDays = 0 -- costume d'hiver (la saison de 28 jours est supprimée)
	-- plafonds v2 (Balance.CapsV2), remis à zéro au changement de jour avec les autres
	d.caps.fameSplorch = 0
	d.caps.starRain = 0
	-- social
	d.decoPerso = { owned = bitset(64), slots = table.create(12, 0) } -- slots : 0 = vide
	d.hearts = { givenDay = 0, givenTo = {}, receivedTotal = 0 } -- givenTo : 20 UserIds au plus
end

-- Valeurs par défaut d'une version du schéma (1 ou 2)
function Schema.defaultsFor(version: number): { [string]: any }
	local d = Schema.defaultsV1()
	if version >= 2 then
		addV2Defaults(d)
	end
	return d
end

-- Valeurs par défaut du schéma v1 (version de test, commit 7382f88) : JAMAIS modifiées
function Schema.defaultsV1(): { [string]: any }
	return {
		version = 1,
		-- horodatages (Clock.unix()) : première arrivée, dernière présence (gains hors ligne)
		firstJoin = 0,
		lastOnline = 0,
		-- réglages du joueur (Config/Settings, clés saved = true)
		settings = defaultSettings(),
		-- achats
		passes = {}, -- [passKey] = true (MonetizationService)
		receipts = {}, -- PurchaseId déjà crédités, au plus 100 (MonetizationService)
		codes = {}, -- [CODE] = true : réservé (aucun code au lancement)
		-- anti-triche : retours forcés comptés ; exclusion des classements jusqu'à lbBanUntil
		-- (Clock.unix(), fin de la semaine suivante). lbBanned : champ du socle, toujours false.
		flags = { strikes = 0, lbBanned = false, lbBanUntil = 0 },

		-- économie (GDD §4.1, §4.6, §4.8, §4.19) — EconomyService
		coins = 0,
		pot = 0,
		R = 0, -- niveau de Grand Splorch
		-- croissance cumulée du ranch : G(t) = G + g × (t − t) ; la taille d'un squishy d'enclos est
		-- z + (G(t) − zg). G repart de 0 à chaque Grand Splorch (précision des doubles).
		-- t = Clock.now() (fractionnaire) du dernier règlement : chaque règlement intègre le Pot sur
		-- [growth.t ; now] puis pose growth.t = now (jamais deux fois la même seconde, docs/04 §11.5) ;
		-- au chargement, le rebase hors ligne (DataService.onPrepare) le remet à Clock.now().
		growth = { G = 0, g = 1, t = 0 },
		-- dalles : niveaux ; seen = masque des dalles découvertes (Config/Pads.Defs[].seenBit)
		tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
		fame = 0,
		-- boost personnel ×2 : secondes restantes (en pause pendant un boost de serveur)
		boosts = { personalLeft = 0 },
		-- plafonds journaliers (Balance.Caps), remis à zéro au changement de jour UTC (Clock.day()) :
		-- petSit = pressions de pet-sitting récompensées comme visiteur ; petSitIn = reçues comme
		-- propriétaire ; petSitBy[tostring(UserId du propriétaire)] = pressions comptées pour « Plus
		-- serviable » (Balance.CapsPerFriend.petSit par ami) ; splorchCoins = cadeaux en pièces des
		-- Grands Splorch des autres (au-delà : Balance.Rewards.GiftSecondsAfterCap)
		caps = {
			day = 0,
			rushBabies = 0,
			splorchGifts = 0,
			splorchCoins = 0,
			fameRush = 0,
			fameRelease = 0,
			petSit = 0,
			petSitIn = 0,
			petSitBy = {},
			claps = 0,
			partyBuys = 0,
		},

		-- collection (GDD §4.3, §4.9, §4.14) — SquishyService
		squishies = {}, -- [uid] = Types.SquishyRecord
		nextUid = 1, -- uid suivant (base 36)
		mount = "", -- uid de la monture choisie ("" = la plus grosse, dès la première selle)
		-- Cuve : fillAt = Clock.unix() où la goutte en cours tombe (0 = arrêtée), pending = goutte
		-- prête mais enclos pleins, pity = naissances depuis le dernier Rare+ / Épique+, newPulls =
		-- tirages « nouveauté garantie » restants, pulls = tirages naturels faits
		vat = { fillAt = 0, pending = false, pityRare = 0, pityEpic = 0, newPulls = 3, pulls = 0 },
		released = {}, -- 12 derniers relâchés { s, m } (Prairie des copains), le plus récent à la fin
		trophies = table.create(#Species.List, 0), -- trophies[s] = taille record (tableau dense, une case par espèce)
		-- owned[id] = nombre d'exemplaires. La tenue portée n'est gardée QUE dans squishies[uid].o (une tenue
		-- par squishy ; portées = nombre de squishies dont o == id, ≤ owned[id]). `worn` est OBSOLÈTE
		-- (contrat v1.2) : gardé vide, jamais lu ni écrit par le jeu (règle : on n'efface pas un champ),
		-- vidé par ProfileRepair
		outfits = { owned = {}, worn = {} },
		biggestEver = 0, -- plus grande taille jamais atteinte (selles gagnées pour toujours)

		-- poursuites — ChaseService
		golden = { lastWinAt = 0 }, -- Clock.unix() du dernier Golden Wobbler gagné (recharge 20 min)

		-- événements — EventService : séance de Jelly Moon (EventClock.moon(t).session, numéro global) où
		-- une Goutte de Lune a été donnée ; une par séance et par compte, même après un changement de serveur
		moon = { lastSession = 0 },

		-- BOOP RUSH (GDD §4.21.1) — RushService
		mode = { rush = false, chosen = false, changedAt = 0, cardShown = false, postBoopCardShown = false },

		-- accueil, objectifs, Squishydex, statistiques — QuestService
		dex = {
			-- tableaux denses, une case par espèce (0 par défaut) dès la création, allongés par
			-- ProfileRepair quand une espèce arrive : mut[s] = masque (bit 0 = page de l'espèce, bit m =
			-- mutation m) ; stars[s] = masque de 5 bits (bit k − 1 = badge ★k)
			mut = table.create(#Species.List, 0),
			stars = table.create(#Species.List, 0),
			-- fam[f] = 1 quand le bonus de la famille Species.FamilyOrder[f] est gagné (les 4 espèces
			-- tamponnées) : gagné POUR TOUJOURS (une espèce ajoutée plus tard ne le retire jamais, GDD
			-- §4.17) ; tableau dense, une case par famille (liste de familles en ajout seul)
			fam = table.create(#Species.FamilyOrder, 0),
			rewards = 0, -- dernier jalon réclamé (Quests.Dex.Milestones, nombre de tampons)
		},
		plopDays = 0, -- jours de Plop au total (jamais une série)
		lastFeedDay = 0, -- Clock.day() du dernier repas
		onboarding = { step = 0, done = false, demoDone = false },
		objectives = { day = 0, list = {}, rerolls = 0, allClaimed = false }, -- list = { Types.ObjectiveEntry × 3 }
		stats = {
			presses = 0,
			perfects = 0,
			fusions = 0,
			bestCombo = 0,
			hatches = 0,
			catches = 0,
			boops = 0,
			booped = 0,
			heroCatches = 0,
			megas = 0,
			splorches = 0,
			playSeconds = 0, -- jeu cumulé (bouclier, Boutique, carte du choix)
			sessions = 0,
			firstBoopReceivedAt = 0, -- secondes de jeu au premier boop subi
			lastFriendDay = 0,
		},

		-- social — CommunityService
		cosmetics = { saddle = "classic", trail = "", title = "", theme = "color", flag = "" },

		-- classements de la semaine (GDD §6.9) — LeaderboardService
		weekly = {
			week = 0,
			stamps = 0,
			combo = 0,
			catchScore = 0,
			helpful = 0,
			generous = 0,
			prev = { stamps = 0, combo = 0, catchScore = 0, helpful = 0, generous = 0 },
		},

		-- réservé pour plus tard (GDD §17.2) : valeurs neutres, jamais lues au lancement
		ascend = 0,
		season = { id = 0, xp = 0, premium = false, claimed = {} },
		slowJelly = { slots = {} },
		parcels = { inbox = {}, sentDay = 0, sent = 0 },
		fameLineage = 0,
		worldFirst = {},
		costumes = {},
		-- paquets de pièces, si le propriétaire les rouvre (janvier au plus tôt, GDD §8.3, §17.2) :
		-- porte-monnaie « Pièces de côté » qui survit au Grand Splorch, devis du serveur écrit avant l'invite
		packs = { side = 0, quoteProduct = "", quoteAmount = 0, quoteAt = 0 },
	}
end

-- Migrations pures, appliquées dans l'ordre. On n'efface jamais un champ dans la version qui le
-- remplace ; DataService appelle ensuite Tables.reconcile(data, defaults()), puis ProfileRepair.
-- Une version absente ou illisible (sauvegarde abîmée) vaut 0.
-- toVersion (par défaut Schema.VERSION) : une étape N ne s'applique que si fromVersion < N ≤ toVersion
-- (tant que SchemaV2 est coupé, DataService ne migre jamais au-delà de la v1).
function Schema.migrate(data: { [string]: any }, fromVersion: number, toVersion: number?): { [string]: any }
	local target = toVersion or Schema.VERSION
	if fromVersion < 1 and target >= 1 then
		-- v0 → v1 : rien à transformer (reconcile ajoute les champs manquants, ProfileRepair répare).
		-- Les étapes suivantes s'ajoutent ici, chacune derrière « if fromVersion < N then ».
		local _ = data
	end
	if fromVersion < 2 and target >= 2 then
		Schema.migrateV1toV2(data)
	end
	return data
end

-- Constantes FIGÉES de la migration v1 → v2 (contrat v2.0) : une migration est de l'histoire, elle
-- ne suit jamais un réglage ultérieur de Config/Balance (deux joueurs migrés à un mois d'écart
-- reçoivent exactement le même rattrapage). Valeurs du GDD v2.0 §4.26, §4.6.
Schema.MIGRATION_V2 = {
	ConfettiBase = 3, -- 3 + min(k, CapR) par Record R k déjà atteint
	CapR = 20,
	RecordBonus = 10, -- + 10 par Record R k ≥ RecordBonusFrom
	RecordBonusFrom = 21,
	OfferedPensAt = { 2, 6, 11, 16 }, -- places d'enclos offertes pour les Record R déjà atteints
	PensMax = 14, -- niveaux de la dalle Enclos
	FullPenBonus = 25, -- place offerte sur une dalle pleine
	DecorLevels = 18,
	MaxR = 400,
}

-- Entier borné, 0 pour une valeur illisible (jamais d'erreur sur une sauvegarde abîmée)
local function intIn(v: any, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v then
		return lo
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Rattrapage en Confettis des Record R 1 … R déjà atteints (sans les places offertes)
function Schema.confettiCatchUp(R: number): number
	local m = Schema.MIGRATION_V2
	local total = 0
	for k = 1, intIn(R, 0, m.MaxR) do
		total += m.ConfettiBase + math.min(k, m.CapR)
		if k >= m.RecordBonusFrom then
			total += m.RecordBonus
		end
	end
	return total
end

-- Étape pure v1 → v2 (GDD v2.0 §12.6, docs/04 §27.2) : aucun champ effacé ; idempotente (un profil
-- déjà en v2 n'est jamais retouché) ; ne lit que des champs v1 ; ne lève jamais d'erreur.
--  1. bestR = R (avant la v2.0 il n'y avait pas d'Ascension) ; ascend = 0 (champ réservé)
--  2. Confettis du premier passage rendus d'un coup : Σ (3 + min(k, 20)) + 10 par k ≥ 21
--  3. places offertes aux Record R 2, 6, 11, 16 déjà atteints : +1 niveau d'Enclos (14 au plus),
--     +25 Confettis chacune si la dalle est pleine
--  4. unlocksSeen = R (une seule carte « Bienvenue dans la v2 ! » au lieu de R cartes « Nouveau »)
--  5. stats.upgradesBought = somme des niveaux v1 (dalles, Enclos, Lit), jamais 0 pour un joueur
--     qui a construit ; decorBuilds[k] = 1 pour chaque décoration construite
--  6. weeklyTrack.firstPeriodEnd reste 0 : QuestService le fixe au premier chargement v2 (2e lundi
--     après Clock.unix()) — la migration reste pure, sans horloge
--  7. le reste : valeurs par défaut v2, ÉCRITES par la migration (lot A2, journal A2-3) : un champ
--     que la v2 ajoute (clé de premier niveau, ou sous-clé d'une table de la v1 : tiles.star,
--     caps.starRain, season.frostDays…) n'a aucun sens dans un profil v1 ; une valeur qui s'y
--     trouverait (essai, vieux bug) ne passe jamais en v2. Les clés inconnues de la v2 sont gardées.
function Schema.migrateV1toV2(data: { [string]: any }): { [string]: any }
	if type(data.version) == "number" and data.version >= 2 then
		return data
	end
	local m = Schema.MIGRATION_V2
	local R = intIn(data.R, 0, m.MaxR)
	if type(data.tiles) ~= "table" then
		data.tiles = {}
	end
	local tiles = data.tiles
	local snack = intIn(tiles.snack, 0, 12)
	local decor = intIn(tiles.decor, 0, m.DecorLevels)
	local pensBefore = intIn(tiles.pens, 0, m.PensMax)
	local cozy = if tiles.cozyBed == true then 1 else 0

	-- champs ajoutés par la v2 : valeurs par défaut (tables neuves), puis les valeurs calculées
	local v1 = Schema.defaultsV1()
	for key, value in Schema.defaultsFor(2) do
		local old = v1[key]
		if old == nil then
			data[key] = value
		elseif type(old) == "table" and type(value) == "table" and type(data[key]) == "table" then
			local target = data[key]
			for sub, subValue in value do
				if old[sub] == nil then
					target[sub] = subValue
				end
			end
		end
	end

	data.bestR = R
	if type(data.ascend) ~= "number" or data.ascend ~= 0 then
		data.ascend = 0
	end

	local confetti = Schema.confettiCatchUp(R)
	local pens = pensBefore
	for _, at in m.OfferedPensAt do
		if R >= at then
			if pens < m.PensMax then
				pens += 1
			else
				confetti += m.FullPenBonus
			end
		end
	end
	tiles.pens = pens -- entier borné (identique pour une sauvegarde saine)
	data.confetti = confetti
	data.confettiTotal = confetti
	data.unlocksSeen = R

	if type(data.stats) ~= "table" then
		data.stats = {}
	end
	data.stats.upgradesBought = snack + decor + pensBefore + cozy
	local builds = table.create(m.DecorLevels, 0)
	for k = 1, decor do
		builds[k] = 1
	end
	data.decorBuilds = builds

	if type(data.onboarding) ~= "table" then
		data.onboarding = {}
	end
	data.onboarding.welcomeV2Pending = R >= 1
	data.version = 2
	return data
end

return Schema
