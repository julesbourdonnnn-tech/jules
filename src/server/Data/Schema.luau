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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.Settings)
local Species = require(Shared.Config.Species)

local Schema = {}

Schema.STORE_NAME = "PlayerData_v1"
Schema.VERSION = 1

Schema.PRIVATE_KEYS = {
	receipts = true,
	codes = true,
	flags = true,
} :: { [string]: boolean }

-- Tables de profil envoyées par morceaux (au-delà de DataService.Settings.SNAPSHOT_INLINE entrées) :
-- la collection (104 squishies au plus). Ordre d'envoi : SquishyService (setStreamOrder : enclos et
-- Bassin, puis Dodo, puis Lettres).
Schema.STREAMED_KEYS = { "squishies" } :: { string }

-- Propriétaire de chaque clé de premier niveau (docs/04 §8)
Schema.OWNERS = {
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

local function defaultSettings(): { [string]: any }
	local out = {}
	for key, def in SettingsConfig do
		if def.saved then
			out[key] = def.default
		end
	end
	return out
end

function Schema.defaults(): { [string]: any }
	return {
		version = Schema.VERSION,
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
function Schema.migrate(data: { [string]: any }, fromVersion: number): { [string]: any }
	if fromVersion < 1 then
		-- v0 → v1 : rien à transformer (reconcile ajoute les champs manquants, ProfileRepair répare).
		-- Les étapes suivantes s'ajoutent ici, chacune derrière « if fromVersion < N then ».
		local _ = data
	end
	return data
end

return Schema
