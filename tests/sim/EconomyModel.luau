--!nocheck
-- EconomyModel (paquet logic, docs/04 §16, §17.1 couche f ; GDD §3, §4.23, §4.24) : un joueur de
-- référence de Raise a Squishy, joué avec les VRAIES règles (Shared/Logic/Formulas, Odds, FusionRules,
-- QuestRules, RushRules, EventClock et les tables de Shared/Config). Seules les hypothèses de
-- COMPORTEMENT du joueur appartiennent au modèle (GDD §4.24, politique exacte) :
--   * 35 min de jeu le premier jour, puis 30 min par jour, une séance par jour à la même heure (le
--     hors-ligne entre deux dépasse toujours la limite : 8 h, 12 h avec le Lit douillet, + 1 h Spiky) ;
--   * une pression toutes les 2 s sur le squishy prêt le plus rentable, PERFECT 40 % du temps ;
--   * Pot encaissé toutes les 40 s (le premier à 1:30, accueil) ;
--   * achats du moins cher utile d'abord (Tapis, Enclos si plein, décorations, Lit douillet dès son
--     MinR), un achat par pression au plus (il faut marcher jusqu'à la dalle) ;
--   * fusion dès qu'une paire de jumeaux existe (« Tout fusionner », FusionRules.planMergeAll) ;
--   * le plus gros reste en enclos, les plus faibles vont dans la Boîte à dodo pour laisser naître la
--     Cuve (après l'accueil) ; Dodo plein : « Ranger » (GDD §4.13), sinon vente du plus faible ;
--   * 85 % des créatures en fuite personnelles attrapées ;
--   * aucun achat Robux (sauf la variante « gros acheteur » : ×2 Pièces, Grand Ranch, Squish Party la
--     moitié du temps) ; aucun ami sur le serveur ; 3 emotes par séance.
-- Contrat v1.2 (docs/04 §16, GDD v1.3 §4.24) :
--   * boosts ×2 CALCULÉS d'après les règles, jamais supposés : Nourrir Plop au début de chaque séance
--     (le premier jour, à la carte des objectifs de 5:00), Balance.Boosts.FeedDay / FeedMilestone ;
--     Wobble Party tirée des règles de la jauge (Events.Gauge : seules les pressions PERFECT comptent
--     parmi les pressions, objectif 600 × max(2, N), fête de 5 min, sieste de 20 min ; les N − 1 autres
--     joueurs du serveur donnent chacun le débit de points mesuré du joueur de référence) ; un boost
--     personnel est en pause pendant un boost de serveur (GDD §4.25) ; les objectifs ne donnent aucun
--     boost ;
--   * vraies parts d'un serveur de N = 4, 8 ou 16 joueurs (GDD §4.24) : Wild Wobbler partagé 75 / 38 /
--     19 % par Rush, Golden 25 / 12 / 6 % ; cadeaux de Grand Splorch des N − 1 autres (un toutes les
--     20 min à 16) ; 60 % des Rush avec un bébé, Wild Wobbler personnel 85 %, 2 bébés par MEGA ;
--   * moteur PAR ÉVÉNEMENTS : le temps saute d'un événement au suivant (pression, Pot, Cuve, fuite,
--     Rush, MEGA, Golden, cadeau, boosts, jauge, Grand Splorch) avec les formules exactes du calcul
--     paresseux (Formulas.G, potGain) ;
--   * hors ligne : Formulas.offlineGrowth(g, durée, R, plus gros) (arrêt à 90 % de l'objectif) et
--     offlinePot ; bonus de famille lus par QuestRules.familyEarned (dex.fam posé à la complétion) ;
--     bébé du Rush : RushRules.babySize et RushRules.babyMutation.
--
-- GDD v2.0 (paquet A1, docs/04 §27.9, GDD §4.24.1) : extension de la simulation du design
-- (scratchpad/v2/gdd/sim/), jouée avec le VRAI code de la progression. Les interrupteurs
-- Config/Features décident, comme dans le jeu : coupés (valeurs du jeu de base), le modèle joue
-- exactement la v1.3 ; ouverts (ECON_FLAGS, posés par la spec), il joue la v2.0 complète :
--   * prix : Formulas.tileCost (dalles de la v1.3, = UpgradeMath.price dès UpgradesScreen) et
--     UpgradeMath.price (Tapis Étoilé, Gants, École, Monuments, Atelier, « Pour le plaisir ») ;
--     ouvertures et plafonds : UpgradeMath.cap (Config/Upgrades, Prestige.starCap) ;
--   * renaissances : Prestige.apply (Grand Splorch, Petit Splorch hors file, Jelly Ascend), ses
--     Confettis, sa Fame, ses places offertes, ses décorations gardées, son Tapis de départ et le
--     cadeau du Splorch (UpgradeMath.giftCoins) ; MaxR et MaxA appliqués par Prestige ;
--   * croissance : Formulas.growthRate (× Prestige.growthFactor : 3^A, Souvenir de gelée, 1re boucle
--     record par le champ memoryR proposé au contrat, note INT-A1-MEMORY ; Tapis Étoilé) ; revenu
--     × Monuments ; pressions × Gants, série jusqu'à Formulas.streakMax ; hors ligne : Sac et Pot de
--     nuit, arrêt à 120 s de Formulas.maxGrowthRate ;
--   * Atelier et « Pour le plaisir » : coûts de Config/Upgrades, la ligne la moins chère d'abord
--     (ordre de UpgradeMath.ids() à égalité) ; politique « Conseillé » : UpgradeAdvisor.next sur
--     UpgradeMath.snapshot ;
--   * Plopettes (Balance.Helpers) : une pression d'aide sur le squishy prêt depuis ReadyFor s que le
--     joueur ne presse pas, HELPER_REACH des pressions trouvent une cible (règle des 12 studs) ;
--   * piste de la semaine (Config/Quests.WeeklyTrack) : 2 points par objectif réclamé, un Défi par
--     jour joué (3 au plus par semaine UTC, QuestRules.weekIndex), Confettis des paliers atteints.
-- Seules les hypothèses de COMPORTEMENT sont des options (opts.v2) : durée des séances, jours joués,
-- politique d'achat, Ascension faite dès qu'elle est prête (ou refusée N jours, ou jamais), Atelier
-- ouvert ou jamais, profils de départ forcés (A par Prestige.apply répété, Atelier complet).
--
--   local EconomyModel = require("../sim/EconomyModel")
--   local model = EconomyModel.new(L)  -- L : modules requis par le harnais (voir EconomyPacing.spec)
--   Sim.run({ players = 50, days = 28, simulate = model.simulateFor({ players = 8 }), … })

local EconomyModel = {}

local DAY = 86400
local PRESS_EVERY = 2 -- s : une pression toutes les 2 s
local FIRST_PRESS = 10 -- s : Big Plop pose Plop, le joueur presse (GDD §3)
local FIRST_POT = 90 -- s : premier Pot (étape 6 de l'accueil)
local POT_EVERY = 40
local TWIN_AT = 40
local FIRST_RUNAWAY_AT = 120
local FIRST_PULL_AT = 166 -- 2:45 + éclosion
local DEMO_AT = 180
local RUNAWAY_PAUSE_FROM = 165 -- l'accueil met la créature en fuite en pause de 2:45 à 5:00
local ONBOARDING_END = 300
local SPLORCH_DELAY = 23 -- s : file du serveur (≈ 20 s) + éclatement (3,2 s)
local PERFECT_SHARE = 0.4
local CATCH_SHARE = 0.85
local CATCH_TIME = 10 -- s pour attraper une créature en fuite
local RUSH_BABY_SHARE = 0.6
local PERSONAL_WILD_SHARE = 0.85
local MEGA_BABIES = 2
local GIFT_EVERY_16 = 1200 -- s : un cadeau de Grand Splorch toutes les 20 min sur un serveur de 16
local EMOTES_AT = 120 -- s de séance : 3 emotes faites (objectif 6)
local VAT_RETRY = 2 -- s : la Cuve attend une place (enclos et Dodo pleins)
local REF_POINTS_PER_SECOND = 20 / 60 -- GDD §4.23 : graine du débit des autres avant toute mesure
local HEALTH_LAST_DAY = 14 -- jalons de santé : boucles des jours 1 à 14 (GDD §4.24)
local START_UNIX = 1797638400 -- lundi 14/12/2026 00:00 UTC (après le lancement)

-- Parts d'un serveur de N joueurs (GDD §4.24) : Wild Wobbler partagé attrapé par Rush, Golden gagné
local SHARED_WILD_SHARE = { [4] = 0.75, [8] = 0.38, [16] = 0.19 }
local GOLDEN_SHARE = { [4] = 0.25, [8] = 0.12, [16] = 0.06 }

-- v2.0 : hypothèses de comportement (GDD §4.24.1), pas des valeurs d'équilibrage
local HELPER_REACH = 0.75 -- part des pressions d'aide qui trouvent une cible (règle des 12 studs)
local ASSIDU_MIN = 120 -- min par jour du joueur assidu (une séance)

EconomyModel.SIZES = { 4, 8, 16 }

-- Bandes de jours du temps « sans but » (docs/04 §27.9) et seuil d'un moment « sans but » : plus de
-- 3 min de jeu depuis le dernier achat, Grand ou Petit Splorch, ou Ascension (GDD §4.24.1)
EconomyModel.BANDS = {
	{ key = "Day1", from = 1, to = 1 },
	{ key = "Day2to7", from = 2, to = 7 },
	{ key = "Day8to14", from = 8, to = 14 },
	{ key = "Day15to28", from = 15, to = 28 },
	{ key = "Day29to56", from = 29, to = 56 },
	{ key = "Day57to84", from = 57, to = 84 },
	{ key = "Day85to140", from = 85, to = math.huge },
}
EconomyModel.STARVED_AFTER = 180

-- Interrupteurs de l'économie v2.0 : tous coupés (jeu de base, porte v1.3) ou tous ouverts (porte
-- v2.0) ; un mélange n'est pas un état simulé (le modèle refuse de le jouer)
EconomyModel.ECON_FLAGS = {
	"RecordR",
	"UpgradesScreen",
	"Confetti",
	"Workshop",
	"StarMat",
	"Gloves",
	"Monuments",
	"JellyAscend",
	"PetitSplorch",
	"Helpers",
	"WeeklyTrack",
	"DecoPerso",
}

-- Portes de la simulation (docs/04 §16 v1.2, GDD §4.24) : médianes, à chaque taille de serveur. Les
-- parts (≥ 80 %, ≥ 90 %, ≥ 95 %) sont vérifiées à part par la spec (EconomyModel.SHARES) : une médiane
-- ne mesure pas une proportion.
EconomyModel.GATES = {
	{ key = "firstPress", label = "Première pression (s)", max = 15 },
	{ key = "firstBuy", label = "Premier achat (s)", max = 30 },
	{ key = "squishies5", label = "Squishies à 5:00", min = 3, max = 4 },
	{ key = "fusions5", label = "Fusions à 5:00", min = 1 },
	{ key = "captures5", label = "Captures à 5:00", min = 1 },
	{ key = "firstRide", label = "Première balade (s)", max = 300 },
	{ key = "firstSplorch", label = "Premier Grand Splorch (min)", min = 11, max = 16 },
	{ key = "r30", label = "R à 30 min", min = 1, max = 3 },
	{ key = "stamps30", label = "Tampons à 30 min", min = 14, max = 24 },
	{ key = "rDay1", label = "R en fin de jour 1", min = 2, max = 3 },
	{ key = "rDay7", label = "R en fin de jour 7", min = 8, max = 11 },
	{ key = "biggestDay7", label = "Plus gros, fin du jour 7", min = 4e7, max = 4e8 },
	{ key = "stampsDay7", label = "Tampons en fin de jour 7", min = 80, max = 110 },
	{ key = "rDay14", label = "R en fin de jour 14", min = 14, max = 16 },
	{ key = "rDay28", label = "R en fin de jour 28", min = 17, max = 22 },
	-- jalons de santé (jours 1 à 14 : médiane des boucles de chaque joueur)
	{ key = "snack12Share", label = "Santé : Tapis 12 (part de la boucle)", min = 0.5 },
	{ key = "coinsLostRatio", label = "Santé : pièces perdues / Tapis 12", max = 10 },
	{ key = "pressShareDay7", label = "Santé : part des pressions, jour 7", min = 0.5 },
	{ key = "readyAtLogin", label = "Santé : Splorch prêts à la connexion", max = 0.5 },
	{ key = "boostShare", label = "Santé : temps en ×2 (%)", min = 20, max = 40 },
}

-- Parts de joueurs : (clé, seuil) ; la clé vaut 1 ou 0 pour chaque joueur
EconomyModel.SHARES = {
	{ key = "penPayable5", label = "Dalle Enclos payable à 5:00", min = 0.9 },
	{ key = "objectivesDay1", label = "3 objectifs sur 3 au jour 1", min = 0.9 },
	{ key = "epicDay7", label = "Un Épique+ au jour 7", min = 0.95 },
	{ key = "splorchIn10to18", label = "Premier Grand Splorch en 10-18 min", min = 0.8 },
}

-- Gros acheteur (×2 Pièces, Grand Ranch, Squish Party la moitié du temps) : avance au jour 28 ≤ 2 R
EconomyModel.SPENDER_MAX_LEAD = 2

EconomyModel.REPORTED = {
	{ key = "coins5", label = "Pièces à 5:00 (repère 5K-17K)" },
	{ key = "stampsDay28", label = "Tampons en fin de jour 28" },
	{ key = "first1e12Day", label = "Premier squishy de 1e12 (jour)" },
	{ key = "gaugeFillMin", label = "Remplissage de la jauge (min)" },
	{ key = "gaugeCycleMin", label = "Cycle de la Wobble Party (min)" },
	{ key = "pointsPerMin", label = "Points de jauge du joueur (/min)" },
}

function EconomyModel.new(L)
	local Formulas, Odds, FusionRules, QuestRules = L.Formulas, L.Odds, L.FusionRules, L.QuestRules
	local RushRules, EventClock, Hash = L.RushRules, L.EventClock, L.Hash
	local Balance, Species, Rarities, Mutations = L.Balance, L.Species, L.Rarities, L.Mutations
	local Quests, Events = L.Quests, L.Events

	local pressReward = Formulas.pressReward
	local incomeFactor = Formulas.incomeFactor
	local SPECIES_COUNT = #Species.List
	local RARITY_OF = {}
	for _, def in Species.List do
		RARITY_OF[def.id] = def.rarity
	end
	local AUTO_LOCK = {}
	for _, def in Rarities.List do
		AUTO_LOCK[def.id] = def.autoLock
	end
	local MUT_LOCK = {}
	for _, def in Mutations.List do
		MUT_LOCK[def.id] = def.autoLock
	end
	local FAMILY_INDEX = {}
	for i, key in Species.FamilyOrder do
		FAMILY_INDEX[key] = i
	end
	local OBJECTIVE_REWARD = Quests.ObjectiveRules.Rewards
	local COOLDOWN = Balance.Press.Cooldown
	local MAX_COINS = Balance.Numbers.Max
	local GAUGE = Events.Gauge
	local POINTS = GAUGE.Points
	local SNACK_LEVELS = Balance.Tiles.snack.Levels

	-- v2.0 : vrais modules de la progression (requis par le harnais, comme les autres)
	local Prestige, UpgradeMath, UpgradeAdvisor = L.Prestige, L.UpgradeMath, L.UpgradeAdvisor
	local Bitset, Features, Upgrades = L.Bitset, L.Features, L.Upgrades
	local MAX_R, MAX_A = Balance.Prestige.MaxR, Balance.Prestige.MaxA
	local HELPERS = Balance.Helpers
	local WORKSHOP_ROW = Upgrades.WorkshopIndex
	local ROW_SUPER_STREAK, ROW_PLUME = WORKSHOP_ROW.superStreak, WORKSHOP_ROW.plume
	local ROW_NIGHT_BAG, ROW_NIGHT_POT = WORKSHOP_ROW.nightBag, WORKSHOP_ROW.nightPot
	-- Plopettes arrivées par le Record R (Helpers.ByRecordR)
	local function helpersAt(bestR)
		local n = 0
		for _, at in HELPERS.ByRecordR do
			if bestR >= at then
				n += 1
			end
		end
		return n
	end
	-- lignes de l'Atelier qui ne sont pas des cosmétiques (les 9 lignes, 21 niveaux : workshopAllDay)
	local WORKSHOP_LINES = {}
	for _, row in Upgrades.WorkshopRows do
		if row.effect ~= "cosmetic" then
			table.insert(WORKSHOP_LINES, row.id)
		end
	end
	-- tout ce qui s'achète en Confettis, dans l'ordre fixe de l'écran (UpgradeMath.ids)
	local CONFETTI_IDS = {}
	for _, id in UpgradeMath.ids() do
		if UpgradeMath.currency(id) == "confetti" then
			table.insert(CONFETTI_IDS, id)
		end
	end
	-- lignes « bits » de « Pour le plaisir » par identifiant canonique ("fun.<id>")
	local FUN_BY_ID = {}
	for _, line in Upgrades.Fun do
		if line.store == "bits" then
			FUN_BY_ID["fun." .. line.id] = line
		end
	end
	-- familles de pièces (ordre de la politique « la moins chère d'abord » : v1.3 puis v2.0)
	local V2_FAMILIES = { "gloves", "school", "star", "monument" }
	-- Confettis des paliers de la piste de la semaine (nombres de WeeklyTrack.Tiers ; le reste :
	-- Goutte chanceuse, cosmétique)
	local TRACK = Quests.WeeklyTrack

	-- état des interrupteurs de l'économie : "off" (tous coupés), "on" (tous ouverts), sinon erreur
	local function econState()
		local on, off = 0, 0
		for _, key in EconomyModel.ECON_FLAGS do
			if Features.get(key) == true then
				on += 1
			else
				off += 1
			end
		end
		if on > 0 and off > 0 then
			error("EconomyModel : interrupteurs v2.0 mélangés (tous coupés ou tous ouverts)")
		end
		return on > 0
	end

	-- Résumé v2.0 d'un joueur (docs/04 §27.9, GDD §4.24.1 ; même lecture du journal que la simulation
	-- du design) : temps « sans but » par bande, boucles (sorte, A, durée, pertes, Tapis 12, achats par
	-- famille, plus long écart entre deux achats), Ascensions, retours au record, falaise du retour,
	-- renaissances au même instant. Le journal est ensuite jeté (seul ce résumé est gardé)
	local function bandOf(d)
		for i, b in EconomyModel.BANDS do
			if d >= b.from and d <= b.to then
				return i
			end
		end
		return nil
	end
	local function summarize(log, daily, offPot, startedAscended)
		local bands = {}
		for i in EconomyModel.BANDS do
			bands[i] = { tot = 0, over = 0, maxGap = 0 }
		end
		local loops, ascendDays, regain, regainDays, cliff = {}, {}, {}, {}, {}
		local zeroGap, nonFinite = 0, 0
		local lastGoal = 0 -- temps de jeu du dernier achat, Grand ou Petit Splorch ou Ascension
		local lastBuy, maxBuyGap = 0, 0
		local buys = {}
		local firstReach = { [0] = 0 }
		local pending = nil -- retour au record en cours : { t, d, target, from }
		local afterAscend, waitFirstRecord = startedAscended == true, false
		local regainLens = {}
		local lastSplorchT = -1
		for _, e in log do
			local k = e.k
			if k == "buy" or k == "splorch" or k == "ascend" then
				local gap = e.t - lastGoal
				local bi = bandOf(e.d)
				if bi then
					local b = bands[bi]
					b.tot += gap
					b.over += math.max(0, gap - EconomyModel.STARVED_AFTER)
					if gap > b.maxGap then
						b.maxGap = gap
					end
				end
				lastGoal = e.t
			end
			if k == "buy" then
				buys[e.tile] = (buys[e.tile] or 0) + 1
				maxBuyGap = math.max(maxBuyGap, e.t - lastBuy)
				lastBuy = e.t
			elseif k == "splorch" then
				if e.t == lastSplorchT then
					zeroGap += 1
				end
				lastSplorchT = e.t
				if e.lost ~= e.lost or e.lost == math.huge then
					nonFinite += 1
				end
				local loop = {
					d = e.d,
					petit = e.petit,
					A = e.A,
					r = e.fromR,
					lost = e.lost,
					share12 = e.share12,
					len = e.len,
					sinceFuse = e.sinceFuse,
					maxBuyGap = maxBuyGap,
					afterAscend = afterAscend,
					snack = buys.snack or 0,
					star = buys.star or 0,
					decor = buys.decor or 0,
					gloves = buys.gloves or 0,
					school = buys.school or 0,
				}
				table.insert(loops, loop)
				if e.petit then
					table.insert(regainLens, e.len)
				else
					-- falaise du retour : 1re boucle record ÷ médiane des 3 dernières boucles de remontée
					if waitFirstRecord and #regainLens >= 3 then
						local last = {
							regainLens[#regainLens],
							regainLens[#regainLens - 1],
							regainLens[#regainLens - 2],
						}
						table.sort(last)
						table.insert(cliff, e.len / math.max(1, last[2]))
					end
					waitFirstRecord = false
				end
				if firstReach[e.R] == nil then
					firstReach[e.R] = e.t
				end
				-- retour au record : temps de jeu de la remontée ÷ temps de la 1re fois (du même départ)
				if pending and e.R >= pending.target then
					local first = (firstReach[pending.target] or e.t) - (firstReach[pending.from] or 0)
					table.insert(regain, (e.t - pending.t) / math.max(1, first))
					table.insert(regainDays, e.d - pending.d)
					pending = nil
				end
				buys = {}
				lastBuy, maxBuyGap = e.t, 0
			elseif k == "ascend" then
				table.insert(ascendDays, e.d)
				afterAscend, waitFirstRecord = true, true
				regainLens = {}
				pending = { t = e.t, d = e.d, target = e.best, from = e.R }
				buys = {}
				lastBuy, maxBuyGap = e.t, 0
			end
		end
		return {
			bands = bands,
			loops = loops,
			ascendDays = ascendDays,
			regain = regain,
			regainDays = regainDays,
			cliff = cliff,
			zeroGap = zeroGap,
			nonFinite = nonFinite,
			daily = daily,
			offPot = offPot,
		}
	end

	local function simulateWith(opts, rng, index, days)
		local N = opts.players or 16
		local spender = opts.spender == true
		local sharedWildShare = SHARED_WILD_SHARE[N] or (3 / N)
		local goldenShare = GOLDEN_SHARE[N] or (1 / N)
		local giftEvery = GIFT_EVERY_16 * 15 / math.max(1, N - 1)
		local gaugeTarget = GAUGE.TargetPerPlayer * math.max(GAUGE.MinPlayers, N)
		-- v2.0 : interrupteurs de l'économie (lus une fois : tous ouverts ou tous coupés) et
		-- hypothèses de comportement du joueur
		local v2 = econState()
		local V = opts.v2 or {}
		local firstMin = V.firstMin or (if V.assidu then ASSIDU_MIN else 35)
		local dailyMin = V.dailyMin or (if V.assidu then ASSIDU_MIN else 30)
		local takesAscend = V.ascend ~= false -- la Jelly Ascend dès qu'elle est prête
		local usesAtelier = V.atelier ~= false -- l'Atelier ouvert après chaque renaissance
		local advisorPolicy = V.policy == "advisor"
		local playDay = V.playDay -- function(jour) → joué ; nil : tous les jours

		-- =================================================================================
		-- État (même forme que le profil quand une règle du jeu le lit)
		-- =================================================================================
		local now = START_UNIX + math.floor(rng.range(0, 7 * DAY))
		local firstStart = now
		local playTime = 0 -- s de jeu cumulé
		local userId = 100000 + index
		local P = {
			coins = 0,
			potOn = 0, -- Pot gagné en jeu
			potOff = 0, -- Pot versé hors ligne (rebase)
			R = 0,
			fame = 0,
			growth = { G = 0, g = 1, t = now },
			tiles = {
				snack = 0,
				decor = 0,
				pens = 0,
				cozyBed = false,
				star = 0,
				gloves = 0,
				school = 0,
				monuments = 0,
			},
			-- v2.0 (schéma v2, docs/04 §27.2) : lus et écrits par Prestige, UpgradeMath ; coupés, jamais lus
			bestR = 0,
			ascend = 0,
			regainBonusA = 0,
			memoryR = 0, -- champ proposé au contrat (INT-A1-MEMORY) : 1re boucle record × 1,25
			confetti = 0,
			confettiTotal = 0,
			atelier = table.create(#Upgrades.WorkshopRows, 0),
			atelierCosmetics = Bitset.new(Upgrades.CosmeticBits),
			pot = 0, -- vue de Prestige.apply (le modèle sépare potOn et potOff)
			weeklyTrack = { firstPeriodEnd = 0 }, -- fin de la 1re période, fixée au 1er calcul
			pen = {}, -- squishies en enclos (et Bassin) : rapportent et grandissent
			dodo = {}, -- Boîte à dodo : taille figée
			nextUid = 1,
			dex = {
				mut = table.create(SPECIES_COUNT, 0),
				stars = table.create(SPECIES_COUNT, 0),
				fam = table.create(#Species.FamilyOrder, 0),
			},
			trophies = table.create(SPECIES_COUNT, 0),
			biggestEver = 0,
			vat = { nextAt = math.huge, hatchAt = math.huge, pityRare = 0, pityEpic = 0, pulls = 0 },
			newPulls = Balance.Vat.NewPulls,
			personalLeft = 0, -- s de boost personnel (en pause pendant un boost de serveur)
			plopDays = 0,
			caps = {
				day = -1,
				rushBabies = 0,
				splorchGifts = 0,
				splorchCoins = 0,
				fameRush = 0,
				fameSplorch = 0,
			},
			streak = 0,
			goldenWinAt = -math.huge,
		}
		local metrics = {
			firstPress = math.huge,
			firstBuy = math.huge,
			firstRide = math.huge,
			firstSplorch = math.huge,
			first1e12Day = math.huge,
			biggestDay7 = 0,
			objectivesDay1 = 0,
			epicDay7 = 0,
			penPayable5 = 0,
			splorchIn10to18 = 0,
			-- v2.0
			firstWorkshopBuy = math.huge,
			applyRefused = 0, -- Prestige.apply refusé alors que le modèle le croyait possible (défaut)
			maxR = 0,
			maxBestR = 0,
			maxA = 0,
			nonFinite = 0,
			workshopAllDay = math.huge, -- jour où les 9 lignes de l'Atelier (21 niveaux) sont finies
			atelierCompleteDay = math.huge, -- jour où l'Atelier et « Pour le plaisir » sont complets
		}
		local daily = {} -- v2.0 : état de fin de chaque jour
		local offPotShares = {} -- v2.0 : Pot de chaque nuit ÷ pièces gagnées en jeu le jour même
		-- journal des achats, renaissances et achats de l'Atelier (v2.0 seulement : clés de la porte,
		-- résumé à la fin de la simulation puis jeté)
		local log = if v2 then {} else nil
		local fusions, captures = 0, 0
		local boostTime, sessionTime = 0, 0 -- s de jeu en ×2 / s de jeu (part du temps en ×2)
		local ctx = {
			decor = 0,
			friends = 0,
			fame = 0,
			trophyBonus = 0,
			goldenPages = 0,
			doubleCoins = spender,
			boost = false,
		}
		local families = {}
		local fuseDirty, buyDirty = true, true
		local dirtySpecies = {} -- espèces qui ont reçu une ligne : seules elles peuvent avoir une paire
		local cheapest = math.huge
		local onboardingTiles = true -- avant le premier Pot : seul le premier Tapis
		local objectives = {}
		local objectivesDay = -1
		local epicEver = false
		local moonPhase = { active = false, startsAt = -math.huge, endsAt = -math.huge }
		local dayIndex = 0

		-- jauge du serveur (Wobble Meter) et boosts de serveur
		local gauge = { points = 0, at = now, state = "fill", untilAt = math.huge }
		local othersRate = (N - 1) * REF_POINTS_PER_SECOND -- points/s des N − 1 autres joueurs
		local measuredRate = REF_POINTS_PER_SECOND
		local ownPoints, ownPointsTime = 0, 0
		local gaugeFills, gaugeFillTime = 0, 0
		local fillStartAt = nil -- fin de la dernière fête vue en jeu (la jauge repart de 0)
		local squishOn = false -- Squish Party (gros acheteur) en cours

		-- santé de l'économie (boucles des jours 1 à 14)
		local loopStartPlay = 0
		local lastFusionPlay = -math.huge
		local helperBudget = 0 -- pressions d'aide dues (Plopettes), fraction comprise
		local helpersBestR, helpersNow = -1, 0 -- Plopettes du Record R (recalculées quand il change)
		local readyRecs, readyIncs = {}, {} -- squishies prêts de la pression en cours (cibles des aides)
		local snack12Play = nil
		local loopShares, lostRatios = {}, {}
		local loginReadyPending = false
		local splorchDays2to14, readyAtLoginCount = 0, 0
		local pressCoins, onlineCoins = 0, 0 -- jour en cours (part des pressions au jour 7)
		local dayPeak = 0 -- plus grande taille atteinte ce jour-là (avant un éventuel Grand Splorch)
		local sourceCoins = {} -- jour en cours : pièces gagnées en jeu par source (rapport)
		local currentSource = "other"

		-- =================================================================================
		-- Aides (formules du jeu ; G(t) en ligne pour la boucle chaude)
		-- =================================================================================
		local function Gnow()
			local g = P.growth
			if now <= g.t then
				return g.G
			end
			return g.G + g.g * (now - g.t)
		end
		local function sizeOf(rec, Gt)
			local s = rec.z + Gt - rec.zg
			return if s < 1 then 1 else s
		end
		local function serverBoost()
			return gauge.state == "party" or squishOn
		end
		local function boostOn()
			return serverBoost() or P.personalLeft > 0
		end
		local function refreshFamilies()
			for key in Species.Families do
				-- QuestService pose dex.fam[f] = 1 au tampon qui complète la famille (pour toujours)
				if QuestRules.familyComplete(P.dex, key) and FAMILY_INDEX[key] then
					P.dex.fam[FAMILY_INDEX[key]] = 1
				end
				families[key] = QuestRules.familyEarned(P.dex, key)
			end
		end
		local capCache, capLevel = 0, -1
		local function penCap()
			if capLevel ~= P.tiles.pens then
				capLevel = P.tiles.pens
				capCache = Formulas.penCapacity(P.tiles.pens, spender)
			end
			return capCache
		end
		local incomeDirty = true
		local bigDirty = true
		local bigOffset, bigRec = -math.huge, nil -- plus gros d'enclos : argmax(z − zg)
		local function refreshBig()
			bigOffset, bigRec = -math.huge, nil
			for _, r in P.pen do
				local off = r.z - r.zg
				if off > bigOffset then
					bigOffset, bigRec = off, r
				end
			end
			bigDirty = false
		end
		local function biggest()
			if bigDirty then
				refreshBig()
			end
			if bigRec == nil then
				return 0, nil
			end
			local s = bigOffset + Gnow()
			return (if s < 1 then 1 else s), bigRec
		end
		local function refreshK()
			ctx.decor = P.tiles.decor
			ctx.fame = P.fame
			ctx.trophyBonus = Formulas.trophyBonus(P.trophies)
			ctx.goldenPages = QuestRules.goldenPages(P.dex)
			ctx.boost = boostOn()
			-- v2.0 : Monuments (multiplicateur à part de Formulas, interrupteur Monuments)
			ctx.monuments = if v2 then P.tiles.monuments else nil
			for _, r in P.pen do
				r.k = incomeFactor(r.s, r.m, r.st, ctx)
			end
			for _, r in P.dodo do
				r.k = nil -- recalculé à la demande (vente)
			end
			incomeDirty = true
		end
		-- règlement : Pot intégré exactement sur [growth.t ; now] (EconomyService.settle) ; (K, S1) de
		-- Formulas.ranchIncome ne changent qu'avec les lignes de l'enclos ou le contexte
		local ascendReadyDay = nil -- v2.0 : jour où la 1re Ascension est devenue possible (« refuse N jours »)
		local cachedK, cachedS1 = 0, 0
		local function settle()
			local Gt = Formulas.G(P.growth, now)
			if incomeDirty then
				local K, S1 = 0, 0
				local G0 = P.growth.G
				for _, r in P.pen do
					local offset = r.z - r.zg
					if offset + G0 < 1 then
						offset = 1 - G0
					end
					K += r.k
					S1 += r.k * offset
				end
				cachedK, cachedS1 = K, S1
				incomeDirty = false
			end
			P.potOn += Formulas.potGain(cachedK, cachedS1, P.growth, P.growth.t, now)
			P.growth.G = Gt
			P.growth.t = now
			for _, r in P.pen do
				local s = sizeOf(r, Gt)
				if s > P.trophies[r.s] then
					P.trophies[r.s] = s
				end
				if s > P.biggestEver then
					P.biggestEver = s
				end
			end
		end
		-- contexte de croissance (Formulas.GrowthCtx) : les champs v2.0 ne comptent qu'interrupteurs
		-- ouverts (Tapis Étoilé, A, Souvenir de gelée, 1re boucle record) ; coupés, la v1.3 exacte
		local function growthCtx(boost)
			return {
				R = P.R,
				snack = P.tiles.snack,
				jellyFamily = families.jelly == true,
				boost = boost,
				star = if v2 then P.tiles.star else nil,
				A = if v2 then P.ascend else nil,
				bestR = if v2 then P.bestR else nil,
				firstRecordLoop = if v2 then Prestige.firstRecordLoop(P) else nil,
			}
		end
		local function setGrowth()
			settle()
			P.growth.g = Formulas.growthRate(growthCtx(boostOn()))
		end
		local function boostChanged()
			setGrowth()
			refreshK()
		end
		local function income()
			local Gt = Gnow()
			local total = 0
			for _, r in P.pen do
				total += r.k * sizeOf(r, Gt)
			end
			return total
		end
		local function addCoins(x, fromPress)
			local before = P.coins
			P.coins = Formulas.clampCoins(P.coins + x)
			local gained = P.coins - before
			onlineCoins += gained
			sourceCoins[currentSource] = (sourceCoins[currentSource] or 0) + gained
			if fromPress then
				pressCoins += gained
			end
		end
		local function incomeSeconds(seconds)
			addCoins(Formulas.secondsOfIncome(income(), seconds))
		end
		local function resetCaps()
			local day = math.floor(now / DAY)
			if P.caps.day ~= day then
				P.caps = {
					day = day,
					rushBabies = 0,
					splorchGifts = 0,
					splorchCoins = 0,
					fameRush = 0,
					fameSplorch = 0,
				}
			end
		end
		local function addFameRush(n)
			resetCaps()
			local granted = math.min(n, Balance.Caps.fameRush - P.caps.fameRush)
			if granted > 0 then
				P.caps.fameRush += granted
				P.fame += granted
			end
		end

		-- ---------------------------------------------------------------------------------
		-- Jauge du serveur : points du joueur + (N − 1) autres joueurs au débit mesuré
		-- ---------------------------------------------------------------------------------
		local function gaugeAdvance()
			-- points des autres joueurs depuis la dernière mise à jour (pendant la fête : perdus, la jauge
			-- repart de 0 à la fin de la fête ; pendant la sieste : comptés)
			if now > gauge.at then
				if gauge.state ~= "party" then
					gauge.points += othersRate * (now - gauge.at)
				end
				gauge.at = now
			end
		end
		local function addPoints(n)
			ownPoints += n
			gaugeAdvance()
			if gauge.state ~= "party" then
				gauge.points += n
			end
		end
		-- Pleine : objectif atteint, ou si proche que l'instant de remplissage arrondi est déjà là
		local function gaugeFull()
			if gauge.points >= gaugeTarget then
				return true
			end
			return othersRate > 0 and now + (gaugeTarget - gauge.points) / othersRate <= now
		end
		-- Instant où la jauge sera pleine au débit actuel des autres (la prochaine transition)
		local function gaugeNextAt()
			if gauge.state ~= "fill" then
				return gauge.untilAt
			end
			gaugeAdvance()
			if gaugeFull() then
				return now
			end
			if othersRate <= 0 then
				return math.huge
			end
			return now + (gaugeTarget - gauge.points) / othersRate
		end
		local function gaugeStep()
			gaugeAdvance()
			local was = boostOn()
			if gauge.state == "party" and now >= gauge.untilAt then
				gauge.state = "rest"
				gauge.untilAt = now + GAUGE.RestSeconds
				gauge.points = 0 -- la jauge repart de 0 à la fin de la fête
				fillStartAt = now
			elseif gauge.state == "rest" and now >= gauge.untilAt then
				gauge.state = "fill"
				gauge.untilAt = math.huge
			end
			if gauge.state == "fill" and gaugeFull() then
				gauge.state = "party"
				gauge.untilAt = now + GAUGE.PartyDuration
				if fillStartAt ~= nil then
					-- remplissage complet vu en jeu : de 0 (fin de fête) à pleine, sieste comprise
					gaugeFills += 1
					gaugeFillTime += now - fillStartAt
				end
				fillStartAt = nil
			end
			if was ~= boostOn() then
				boostChanged()
			end
		end
		-- État du serveur à l'arrivée du joueur : phase uniforme dans le cycle stationnaire (fête, sieste,
		-- remplissage) au débit de N joueurs de référence
		local function gaugeJoin()
			local rate = N * measuredRate
			local fill = if rate > 0 then gaugeTarget / rate else math.huge
			local party, rest = GAUGE.PartyDuration, GAUGE.RestSeconds
			local afterRest = math.max(0, fill - rest)
			local cycle = party + rest + afterRest
			local phi = rng.range(0, cycle)
			gauge.at = now
			if phi < party then
				gauge.state, gauge.untilAt, gauge.points = "party", now + party - phi, 0
			elseif phi < party + rest then
				local elapsed = phi - party
				gauge.state, gauge.untilAt = "rest", now + rest - elapsed
				gauge.points = math.min(gaugeTarget, elapsed * rate)
			else
				gauge.state, gauge.untilAt = "fill", math.huge
				gauge.points = math.min(gaugeTarget, rest * rate + (phi - party - rest) * rate)
			end
			fillStartAt = nil
		end

		-- Confettis (EconomyService.addConfetti : seul point d'entrée des gains, bornés à Confetti.Max)
		local CONFETTI_MAX = Balance.Confetti.Max
		local function confetti(n)
			P.confetti = math.min(CONFETTI_MAX, P.confetti + n)
			P.confettiTotal = math.min(CONFETTI_MAX, P.confettiTotal + n)
		end
		-- piste de la semaine (v2.0, GDD §7.5) : points de la période en cours (QuestRules.trackPeriod : la
		-- 1re période va de la 1re connexion au 2e lundi qui suit, puis une par semaine UTC ; la fin de la
		-- 1re est gardée comme QuestService la garde), paliers payés dès qu'ils sont atteints (« paliers
		-- réclamés tout seuls ») ; un palier en nombre = des Confettis (les autres : Goutte chanceuse,
		-- cosmétique de la semaine)
		local trackPeriod, trackPoints, trackTiers, trackChallenges = -1, 0, 0, 0
		local function trackRoll()
			local tp = QuestRules.trackPeriod(P, math.floor(now))
			P.weeklyTrack.firstPeriodEnd = tp.firstPeriodEnd
			if tp.period ~= trackPeriod then
				trackPeriod, trackPoints, trackTiers, trackChallenges = tp.period, 0, 0, 0
			end
		end
		local function trackAdd(points)
			trackRoll()
			trackPoints += points
			local reach = math.min(#TRACK.Tiers, math.floor(trackPoints / TRACK.PointsPerTier))
			while trackTiers < reach do
				trackTiers += 1
				local reward = TRACK.Tiers[trackTiers]
				if type(reward) == "number" then
					confetti(reward)
				end
			end
		end

		-- objectifs du jour : progression (QuestRules.apply), réclamation aussitôt terminés
		local function objective(stat, amount, perfect)
			for _, e in objectives do
				if not e.claimed and (e.stat == stat or (e.streak and stat == "press")) then
					local out = QuestRules.apply(e, stat, amount, perfect)
					e.p = out.p
					if out.done and not e.done then
						e.done = true
						e.claimed = true
						-- minutes de revenu seulement : aucun boost (GDD §7.4 révision 1.3)
						local reward = OBJECTIVE_REWARD[Quests.Objectives[e.id].tier]
						local was = currentSource
						currentSource = "objective"
						incomeSeconds(reward.incomeSeconds)
						currentSource = was
						if v2 then
							trackAdd(TRACK.PointsPerObjective)
						end
					end
				end
			end
		end

		-- Squishydex : tampons d'espèce, de mutation et badges d'étoiles
		local function popcount(x)
			local n = 0
			while x ~= 0 do
				x = bit32.band(x, x - 1)
				n += 1
			end
			return n
		end
		local function stamp(s, m, st)
			if not QuestRules.isNewStamp(P.dex, s, m, st) then
				return
			end
			local mut, stars = P.dex.mut, P.dex.stars
			local beforeMut, beforeStars = mut[s] or 0, stars[s] or 0
			mut[s] = bit32.bor(beforeMut, 1)
			if m > 0 then
				mut[s] = bit32.bor(mut[s], bit32.lshift(1, m))
			end
			for k = 1, st do
				stars[s] = bit32.bor(stars[s] or 0, bit32.lshift(1, k - 1))
			end
			local gained = popcount(bit32.bxor(mut[s], beforeMut))
				+ popcount(bit32.bxor(stars[s], beforeStars))
			if gained > 0 then
				objective("stamps", gained)
			end
			if not bit32.btest(beforeMut, 1) then
				local before = families.jelly
				refreshFamilies() -- nouvelle espèce : un bonus de famille peut s'ouvrir (dex.fam)
				if families.jelly ~= before then
					setGrowth()
				end
			end
		end

		-- Dodo plein : « Ranger » (Communs et Peu communs, 0 étoile, sans mutation, non verrouillés,
		-- espèce tamponnée, le plus gros de chaque espèce gardé), sinon le plus faible part (vente)
		local function sell(list, i)
			local r = list[i]
			local k = r.k or incomeFactor(r.s, r.m, r.st, ctx)
			addCoins(Formulas.sellValue(k * r.z))
			table.remove(list, i)
			buyDirty = true
		end
		local function tidyDodo()
			if #P.dodo < Balance.Pens.Dodo then
				return
			end
			local keep = {}
			for _, r in P.dodo do
				if keep[r.s] == nil or r.z > keep[r.s].z then
					keep[r.s] = r
				end
			end
			for i = #P.dodo, 1, -1 do
				local r = P.dodo[i]
				if
					(RARITY_OF[r.s] or 1) <= 2
					and r.st == 0
					and r.m == 0
					and not r.lk
					and r.bf == 0
					and keep[r.s] ~= r
				then
					sell(P.dodo, i)
				end
			end
			if #P.dodo >= Balance.Pens.Dodo then
				-- rien à ranger : le plus faible part, déverrouillé à la main s'il le faut
				local weakest, weakestValue = nil, math.huge
				for i, r in P.dodo do
					r.k = r.k or incomeFactor(r.s, r.m, r.st, ctx)
					local value = r.k * r.z
					if r.bf == 0 and value < weakestValue then
						weakest, weakestValue = i, value
					end
				end
				if weakest then
					sell(P.dodo, weakest)
				end
			end
		end

		-- squishy obtenu : tamponné, verrouillé si besoin, placé (enclos → Dodo → pièces)
		local function give(s, m, z, source)
			local at
			if #P.pen < penCap() then
				at = "pen"
			else
				tidyDodo()
				if #P.dodo < Balance.Pens.Dodo then
					at = "dodo"
				else
					incomeSeconds(Balance.Babies.FallbackSeconds)
					return nil
				end
			end
			local Gt = Gnow()
			local uid = string.format("%x", P.nextUid)
			P.nextUid += 1
			local rarity = RARITY_OF[s] or 1
			local rec = {
				uid = uid,
				s = s,
				m = m,
				st = 0,
				z = Formulas.clampSize(z),
				zg = Gt,
				bf = if uid == "1" then 1 else 0,
				lk = AUTO_LOCK[rarity] == true or MUT_LOCK[m] == true,
				o = "",
				at = at,
				b = math.floor(now),
				gd = 0,
				readyAt = 0,
			}
			rec.k = incomeFactor(s, m, 0, ctx)
			if at == "pen" then
				settle() -- le Pot est réglé avec l'ancien enclos avant d'ajouter la ligne
				incomeDirty = true
				bigDirty = true
			end
			table.insert(if at == "pen" then P.pen else P.dodo, rec)
			fuseDirty, buyDirty = true, true
			dirtySpecies[s] = true
			stamp(s, m, 0)
			if rarity >= 3 then
				objective("rareGet", 1)
			end
			if rarity >= 4 then
				epicEver = true
			end
			if source == "vat" then
				objective("vatHatch", 1)
				addPoints(POINTS.hatch)
			end
			return rec
		end

		-- « Tout fusionner » dès qu'une paire existe (verrouillés exclus), combos récompensés
		local function removeUid(uid)
			for i, r in P.pen do
				if r.uid == uid then
					table.remove(P.pen, i)
					return
				end
			end
			for i, r in P.dodo do
				if r.uid == uid then
					table.remove(P.dodo, i)
					return
				end
			end
		end
		local function fuseAll()
			if not fuseDirty then
				return
			end
			fuseDirty = false
			-- le joueur de référence fusionne aussi à la main ses jumeaux verrouillés (GDD §4.13) ; avant
			-- l'ajout il ne restait aucune paire : seules les espèces qui ont reçu une ligne peuvent en
			-- avoir une (le plan de FusionRules traite chaque espèce à part)
			local wanted = dirtySpecies
			dirtySpecies = {}
			local seen, speciesWithPair = {}, {}
			local any = false
			for _, list in { P.pen, P.dodo } do
				for _, r in list do
					if wanted[r.s] then
						local key = r.s * 8 + r.st
						if seen[key] then
							speciesWithPair[r.s] = true
							any = true
						end
						seen[key] = true
					end
				end
			end
			if not any then
				return
			end
			local map, planView = {}, {}
			for _, list in { P.pen, P.dodo } do
				for _, r in list do
					if speciesWithPair[r.s] then
						map[r.uid] = r
						local view = table.clone(r)
						view.lk = false
						planView[r.uid] = view
					end
				end
			end
			local plan = FusionRules.planMergeAll(planView, Formulas.poolSlots(families.axolo == true))
			if #plan == 0 then
				return
			end
			buyDirty = true
			settle()
			local Gt = Gnow()
			-- étape du combo : une paire qui part de l'uid gardé précédent continue la chaîne
			-- (même règle que FusionRules.comboSteps)
			local prevKept, step = nil, 0
			for _, pair in plan do
				local a, b = map[pair[1]], map[pair[2]]
				if a and b then
					step = if prevKept ~= nil and pair[1] == prevKept then step + 1 else 1
					local kept = FusionRules.keepUid(pair[1], pair[2], a, b)
					prevKept = kept
					local merged = FusionRules.fuse(a, b, Gt, math.floor(now))
					-- GDD §4.10 : le résultat va dans l'enclos s'il y a de la place (une fusion libère
					-- toujours une place quand l'un des deux y était)
					merged.at = if merged.at == "pool" then "pen" else merged.at
					if merged.at == "dodo" and #P.pen < penCap() then
						merged.at = "pen"
					end
					merged.uid = kept
					merged.readyAt = 0
					merged.k = incomeFactor(merged.s, merged.m, merged.st, ctx)
					removeUid(pair[1])
					removeUid(pair[2])
					table.insert(if merged.at == "pen" then P.pen else P.dodo, merged)
					incomeDirty = true
					bigDirty = true
					map[pair[1]], map[pair[2]] = nil, nil
					map[kept] = merged
					fusions += 1
					lastFusionPlay = playTime
					local resultSize = if merged.at == "pen" then sizeOf(merged, Gt) else merged.z
					currentSource = "combo"
					addCoins(Formulas.comboReward(step, merged.k * resultSize))
					currentSource = "other"
					addPoints(POINTS.fuseStep)
					objective("fusion", 1)
					if step >= 2 then
						objective("combo2", 1)
					end
					stamp(merged.s, merged.m, merged.st)
				end
			end
		end

		-- le plus faible de l'enclos part au Dodo (jamais le Meilleur Ami ni le plus gros)
		local function makeRoom()
			if #P.pen < penCap() then
				return true
			end
			tidyDodo()
			if #P.dodo >= Balance.Pens.Dodo then
				return false
			end
			local Gt = Gnow()
			local _, big = biggest()
			local weakest, weakestIncome = nil, math.huge
			for i, r in P.pen do
				if r.bf == 0 and r ~= big then
					local inc = r.k * sizeOf(r, Gt)
					if inc < weakestIncome then
						weakest, weakestIncome = i, inc
					end
				end
			end
			if weakest == nil then
				return false
			end
			settle()
			local r = table.remove(P.pen, weakest)
			r.z = sizeOf(r, Gt)
			r.at = "dodo"
			table.insert(P.dodo, r)
			incomeDirty = true
			bigDirty = true
			fuseDirty, buyDirty = true, true
			return true
		end

		-- prix (GDD v2.0 §4.6) : dalles de la v1.3 par Formulas.tileCost (= UpgradeMath.price dès
		-- UpgradesScreen, × F(A) avec JellyAscend), familles nouvelles par UpgradeMath.price (le seul
		-- calcul des prix du jeu) ; niveau actuel lu dans le profil (UpgradeMath.level)
		local TILE_PRICED = { snack = true, decor = true, pens = true, cozyBed = true }
		local TILE_KEY = { monument = "monuments" }
		local function levelOf(id)
			if id == "cozyBed" then
				return if P.tiles.cozyBed then 1 else 0
			end
			return P.tiles[TILE_KEY[id] or id]
		end
		-- (prix gardé par famille tant que niveau, r, A et Record R ne changent pas : le même nombre,
		-- calculé une fois ; la boucle chaude réévalue les achats après presque chaque pression)
		local priceCache = {}
		local function costOf(id, lvl)
			local c = priceCache[id]
			if c and c.l == lvl and c.r == P.R and c.a == P.ascend and c.b == P.bestR then
				return c.p
			end
			local price
			if TILE_PRICED[id] then
				price = Formulas.tileCost(id, lvl, P.R, P.ascend)
			else
				price = UpgradeMath.price(id, lvl, P.R, P.ascend, P.bestR)
			end
			priceCache[id] = { l = lvl, r = P.R, a = P.ascend, b = P.bestR, p = price }
			return price
		end
		-- plafond d'une famille (UpgradeMath.cap), gardé tant que r, Record R, A et le Tapis 12 ne
		-- changent pas (les interrupteurs ne changent pas pendant une simulation)
		local familyCaps, capStamp = {}, nil
		local function capOf(id)
			local stamp = P.R
				+ 1e3 * P.bestR
				+ 1e6 * P.ascend
				+ (if P.tiles.snack >= SNACK_LEVELS then 1e9 else 0)
			if stamp ~= capStamp then
				capStamp = stamp
				table.clear(familyCaps)
			end
			local cap = familyCaps[id]
			if cap == nil then
				cap = UpgradeMath.cap(id, P, Features)
				familyCaps[id] = cap
			end
			return cap
		end
		local function T12now()
			return costOf("snack", SNACK_LEVELS - 1)
		end
		local snapVersion = 0

		-- achat : le moins cher utile d'abord ; un achat par appel (marcher jusqu'à la dalle)
		local best, bestCost = nil, math.huge -- candidate de l'évaluation en cours (tryBuy)
		local function consider(id, useful)
			if useful then
				local cost = costOf(id, levelOf(id))
				if cost < bestCost then
					best, bestCost = id, cost
				end
			end
		end
		local function tryBuy()
			if not buyDirty and P.coins < cheapest then
				return
			end
			best, bestCost = nil, math.huge
			if onboardingTiles then
				consider("snack", P.tiles.snack == 0)
			elseif advisorPolicy then
				-- politique « Conseillé » (GDD §10.7.4) : les candidates de UpgradeAdvisor (familles de
				-- pièces ouvertes, pas au maximum ; Monuments après le Tapis 12)
				for _, def in Upgrades.Families do
					local id = def.id
					consider(
						id,
						capOf(id) > levelOf(id) and (id ~= "monument" or P.tiles.snack >= SNACK_LEVELS)
					)
				end
			else
				consider("snack", true)
				consider("pens", #P.pen >= penCap() and playTime >= ONBOARDING_END)
				consider("decor", true)
				consider("cozyBed", P.bestR >= Balance.Tiles.cozyBed.MinR and not P.tiles.cozyBed)
				if v2 then
					for _, id in V2_FAMILIES do
						consider(id, capOf(id) > levelOf(id))
					end
				end
			end
			cheapest, buyDirty = bestCost, false
			if best == nil or bestCost == math.huge or P.coins < bestCost then
				return
			end
			if advisorPolicy and not onboardingTiles then
				-- la cible de la puce « Prochain achat », sur l'instantané versionné de l'écran
				snapVersion += 1
				local target = UpgradeAdvisor.next(UpgradeMath.snapshot(P, Features, snapVersion), {})
				if target == nil or target.price > P.coins then
					error("EconomyModel : le Conseillé ne désigne aucun achat payable")
				end
				best, bestCost = target.id, target.price
			end
			local id, cost = best, bestCost -- (copie : rien ne doit dépendre de l'état partagé après)
			settle()
			P.coins -= cost
			if id == "cozyBed" then
				P.tiles.cozyBed = true
			else
				local key = TILE_KEY[id] or id
				P.tiles[key] += 1
			end
			buyDirty = true
			if log then
				table.insert(log, { t = playTime, d = dayIndex, k = "buy", tile = id })
			end
			if metrics.firstBuy == math.huge then
				metrics.firstBuy = playTime
			end
			objective("tileBuy", 1)
			if id == "snack" or id == "star" then
				setGrowth()
				if P.tiles.snack >= SNACK_LEVELS and snack12Play == nil then
					snack12Play = playTime
				end
			elseif id == "decor" or id == "monument" then
				refreshK()
			end
		end

		local function collectPot()
			settle()
			-- le Pot en jeu compte dans les pièces gagnées en jeu ; le Pot hors ligne non
			local before = P.coins
			P.coins = Formulas.clampCoins(P.coins + P.potOn + P.potOff)
			local gained = P.coins - before
			local total = P.potOn + P.potOff
			if total > 0 then
				onlineCoins += gained * P.potOn / total
				sourceCoins.pot = (sourceCoins.pot or 0) + gained * P.potOn / total
			end
			P.potOn, P.potOff = 0, 0
			objective("potCollect", 1)
			buyDirty = true
		end

		-- tirage de la Cuve (graine Odds.seed, nouveauté garantie, protections, Lune)
		local function vatRoll()
			local lvl = Formulas.vatLevel(P.bestR)
			local owned = {}
			for s = 1, SPECIES_COUNT do
				if bit32.btest(P.dex.mut[s] or 0, 1) then
					owned[s] = true
				end
			end
			local result = Odds.roll(Hash.stream(Odds.seed(userId, P.vat.pulls)), {
				quality = lvl.quality,
				nozzles = lvl.nozzles,
				moon = moonPhase.active,
				unix = math.floor(now),
				families = Odds.unlockedFamilies(P.bestR),
				owned = owned,
				newPull = P.newPulls > 0,
				pityRare = P.vat.pityRare,
				pityEpic = P.vat.pityEpic,
			})
			P.vat.pulls += 1
			if result.usedNewPull then
				P.newPulls -= 1
			end
			P.vat.pityRare, P.vat.pityEpic = result.pityRare, result.pityEpic
			give(result.species, result.mutation, 1, "vat")
		end
		local function scheduleVat()
			P.vat.nextAt = now + Formulas.vatInterval(P.bestR, families.bunny == true)
		end

		-- bébé d'un événement (toutes familles ou familles débloquées), taille donnée
		local function rollBaby(quality, nozzles, mult, force, z, unlockedOnly, points)
			local result = Odds.roll(Hash.stream(Odds.seed(userId, 1e6 + P.nextUid)), {
				quality = quality,
				nozzles = nozzles,
				moon = moonPhase.active,
				unix = math.floor(now),
				families = if unlockedOnly then Odds.unlockedFamilies(P.bestR) else nil,
				mutationMult = mult,
				forceMutation = force,
			})
			captures += 1
			if points then
				addPoints(points)
			end
			return give(result.species, result.mutation, z, "event")
		end

		-- niveau acheté d'une ligne payée en Confettis (case de l'Atelier ou bit de « Pour le plaisir »)
		local function buyConfettiLine(id, level)
			local row = WORKSHOP_ROW[id]
			if row then
				P.atelier[row] += 1
			else
				Bitset.set(P.atelierCosmetics, FUN_BY_ID[id].firstBit + level)
			end
		end
		-- l'Atelier, puis « Pour le plaisir » : la ligne la moins chère d'abord (ordre fixe de l'écran à
		-- égalité), tant que les Confettis suffisent ; ouverture et plafond par UpgradeMath.cap
		local function atelierBuy()
			if not usesAtelier then
				return
			end
			while true do
				local bestId, bestLevel, bestCost = nil, 0, math.huge
				for _, id in CONFETTI_IDS do
					local level = UpgradeMath.level(id, P)
					if level < UpgradeMath.cap(id, P, Features) then
						local cost = UpgradeMath.price(id, level, P.R, P.ascend, P.bestR)
						if cost < bestCost then
							bestId, bestLevel, bestCost = id, level, cost
						end
					end
				end
				if bestId == nil or P.confetti < bestCost then
					break
				end
				P.confetti -= bestCost
				buyConfettiLine(bestId, bestLevel)
				if log then
					table.insert(
						log,
						{ t = playTime, d = dayIndex, k = "atelier", line = bestId, lvl = bestLevel + 1 }
					)
				end
				if metrics.firstWorkshopBuy == math.huge then
					metrics.firstWorkshopBuy = playTime / 60
				end
			end
		end

		-- v2.0 : un prestige par Prestige.apply (le seul code qui l'applique dans le jeu) sur le profil
		-- du modèle (vue `squishies` : enclos et Boîte à dodo, par référence ; Pot = potOn + potOff) ;
		-- les gains RENDUS sont versés comme le fait l'appelant (EconomyService.addConfetti, Fame des
		-- Grands Splorch sous le plafond du jour, Fame de l'Ascension hors plafond)
		local function prestige(kind)
			local view = {}
			for _, r in P.pen do
				view[r.uid] = r
			end
			for _, r in P.dodo do
				view[r.uid] = r
			end
			P.squishies = view
			P.pot = P.potOn + P.potOff
			local _, report = Prestige.apply(P, kind, now)
			P.squishies = nil
			if not report.applied then
				metrics.applyRefused += 1
				P.pot = 0
				return report
			end
			P.potOn, P.potOff, P.pot = 0, 0, 0
			confetti(report.confetti)
			if report.kind == "ascend" then
				P.fame += report.fame
			elseif report.fame > 0 then
				resetCaps()
				local granted = math.min(report.fame, Balance.CapsV2.fameSplorch - P.caps.fameSplorch)
				if granted > 0 then
					P.caps.fameSplorch += granted
					P.fame += granted
				end
			end
			if P.R > metrics.maxR then
				metrics.maxR = P.R
			end
			if P.bestR > metrics.maxBestR then
				metrics.maxBestR = P.bestR
			end
			if P.ascend > metrics.maxA then
				metrics.maxA = P.ascend
			end
			return report
		end

		-- Grand Splorch d'un bloc (EconomyService.applySplorch + SquishyService.resetSizes) ; v2.0 :
		-- Grand ou Petit Splorch (Prestige.apply), puis la Jelly Ascend si elle est prête, l'Atelier et
		-- le cadeau du Splorch
		local function applySplorch()
			settle()
			local peak = biggest()
			if peak > dayPeak then
				dayPeak = peak -- le plus gros juste avant de repartir à 1
			end
			local lost = P.coins + P.potOn + P.potOff
			local T12 = T12now()
			local record = not v2 or Prestige.nextKind(P) == "splorch"
			local loopLen = playTime - loopStartPlay
			local share = 1
			if snack12Play ~= nil and loopLen > 0 then
				share = math.clamp((snack12Play - loopStartPlay) / loopLen, 0, 1)
			end
			if dayIndex <= HEALTH_LAST_DAY then
				-- jalons de santé de la v1.3 : boucles des Grands Splorch (record) des jours 1 à 14
				if record then
					table.insert(loopShares, share)
					table.insert(lostRatios, lost / T12)
				end
				if dayIndex >= 2 then
					splorchDays2to14 += 1
					if loginReadyPending then
						readyAtLoginCount += 1
					end
				end
			end
			loginReadyPending = false
			if opts.trace then
				print(
					string.format(
						"  splorch R=%d (Record %d, A %d) jour %d : jeu %.0f s, boucle %.0f s, Tapis12 à %s, Tapis %d, décos %d, pièces %.3g, Pot jeu %.3g, Pot hors ligne %.3g, Tapis 12 = %.3g (×%.1f)",
						P.R,
						P.bestR,
						P.ascend,
						dayIndex,
						playTime,
						loopLen,
						tostring(snack12Play and (snack12Play - loopStartPlay)),
						P.tiles.snack,
						P.tiles.decor,
						P.coins,
						P.potOn,
						P.potOff,
						T12,
						lost / T12
					)
				)
			end
			if v2 then
				local loop = {
					t = playTime,
					d = dayIndex,
					k = "splorch",
					fromR = P.R,
					A = P.ascend,
					lost = lost / T12,
					share12 = share,
					len = loopLen,
					sinceFuse = playTime - lastFusionPlay,
					star = P.tiles.star,
					petit = not record,
				}
				local report = prestige("splorch")
				loop.R = P.R
				if log then
					table.insert(log, loop)
				end
				-- Jelly Ascend : le joueur la fait dès qu'elle est prête (option : refusée N jours, jamais)
				if takesAscend and Prestige.ascendReady(P) then
					local ok = true
					if V.ascendDelayDays and P.ascend == 0 then
						ascendReadyDay = ascendReadyDay or dayIndex
						ok = dayIndex >= ascendReadyDay + V.ascendDelayDays
					end
					if ok then
						local fromR, fromBest = P.R, P.bestR
						report = prestige("ascend")
						if log and report.applied then
							table.insert(log, {
								t = playTime,
								d = dayIndex,
								k = "ascend",
								A = P.ascend,
								R = P.R,
								fromR = fromR,
								best = fromBest,
							})
						end
					end
				end
				atelierBuy()
				-- cadeau du Splorch : prix des niveaux offerts du Tapis dans la boucle neuve
				if report.applied then
					P.coins = Formulas.clampCoins(P.coins + UpgradeMath.giftCoins(P, report.giftLevels))
				end
			else
				P.coins, P.potOn, P.potOff = 0, 0, 0
				P.tiles.snack, P.tiles.decor = 0, 0
				P.R += 1
				P.bestR = math.max(P.bestR, P.R)
				P.fame += Balance.Fame.Splorch
				for _, r in P.pen do
					r.z, r.zg = 1, 0
				end
				for _, r in P.dodo do
					r.z, r.zg = 1, 0
				end
				P.growth = { G = 0, g = P.growth.g, t = now }
			end
			incomeDirty = true
			bigDirty = true
			boostChanged()
			buyDirty = true
			addPoints(POINTS.splorch)
			objective("splorch", 1)
			if metrics.firstSplorch == math.huge then
				metrics.firstSplorch = playTime / 60
				metrics.splorchIn10to18 = if metrics.firstSplorch >= 10
						and metrics.firstSplorch <= 18
					then 1
					else 0
			end
			loopStartPlay = playTime
			snack12Play = nil
		end

		-- Nourrir Plop (jours au total) : boost personnel de 5 min, palier du jour 2 en pièces
		local function feed()
			P.plopDays += 1
			local milestone = QuestRules.plopReward(P.plopDays)
			local was = boostOn()
			P.personalLeft += if milestone then Balance.Boosts.FeedMilestone else Balance.Boosts.FeedDay
			if milestone and milestone.kind == "coins" then
				incomeSeconds(Balance.Rewards.PlopDay2)
			end
			addPoints(POINTS.feed)
			if not was then
				boostChanged()
			end
		end

		-- objectifs du jour (jour 1 : fixes) et Nourrir Plop
		local function chores(withFeed)
			resetCaps()
			local day = math.floor(now / DAY)
			if objectivesDay ~= day then
				objectivesDay = day
				local need = math.max(0, Formulas.splorchTarget(P.R) - (biggest()))
				local ids = QuestRules.draw(userId, day, {
					R = P.R,
					tilesLeft = 10,
					megaIn = EventClock.mega(now).landsAt - now,
					friendOnServer = false,
					splorchEta = need / math.max(1e-9, P.growth.g),
					stamps = QuestRules.stampCount(P.dex),
				}, dayIndex == 1)
				objectives = {}
				for _, id in ids do
					local def = Quests.Objectives[id]
					table.insert(objectives, {
						id = id,
						p = 0,
						done = false,
						claimed = false,
						stat = def.stat,
						streak = def.streak == true,
					})
				end
			end
			if withFeed then
				feed()
			end
		end

		-- =================================================================================
		-- Une séance : moteur par événements
		-- =================================================================================
		local runawayAt = math.huge
		local splorchAt = math.huge
		local function playSession(duration)
			local sessionStart = now
			local sessionEnd = now + duration
			local playStart = playTime
			local function playAt(t)
				return playStart + (t - sessionStart)
			end
			local function atPlay(p)
				return sessionStart + (p - playStart)
			end
			local first = dayIndex == 1
			local nextRush = EventClock.rush(now)
			local nextMega = EventClock.mega(now)
			local nextGolden = EventClock.golden(now)
			local nextGift = now + rng.range(0, giftEvery)
			local nextPotAt = atPlay(if first then FIRST_POT else playStart + POT_EVERY)
			local nextPressAt = atPlay(if first then FIRST_PRESS else playStart)
			local emoteAt = now + EMOTES_AT
			local rushEnd, megaEnd = -math.huge, -math.huge
			local wildPersonalAt = math.huge
			local squishEnd = if spender then now + duration / 2 else -math.huge
			if spender and not first then
				squishOn = true
				boostChanged()
			end
			-- jalons et script de l'accueil (temps de jeu → instants)
			local script = {}
			if first then
				script = {
					{ at = atPlay(TWIN_AT), kind = "twin" },
					{ at = atPlay(FIRST_RUNAWAY_AT), kind = "firstRunaway" },
					{ at = atPlay(FIRST_PULL_AT), kind = "firstPull" },
					{ at = atPlay(DEMO_AT), kind = "demo" },
					{ at = atPlay(ONBOARDING_END), kind = "card" },
					{ at = atPlay(1800), kind = "m30" },
				}
			else
				runawayAt = now + Balance.Runaway.Interval
			end
			local scriptIndex = 1
			local ownPointsAtStart = ownPoints

			local function onboarding()
				return first and playAt(now) < ONBOARDING_END
			end
			local function personalEndAt()
				if P.personalLeft > 0 and not serverBoost() then
					return now + P.personalLeft
				end
				return math.huge
			end
			-- avance l'horloge à t (boost personnel décompté hors boost de serveur, temps en ×2)
			local function advanceTo(t)
				local dt = t - now
				if dt <= 0 then
					return
				end
				if boostOn() then
					boostTime += dt
				end
				sessionTime += dt
				if P.personalLeft > 0 and not serverBoost() then
					P.personalLeft -= dt
					-- reste d'arrondi (instants de l'ordre de 1,8e9 s) : fini
					if P.personalLeft < 1e-3 then
						P.personalLeft = 0
					end
				end
				now = t
				playTime = playAt(t)
			end
			local function splorchReadyCheck()
				local bg = biggest()
				if bg > dayPeak then
					dayPeak = bg
				end
				if bg >= 1200 and metrics.firstRide == math.huge then
					metrics.firstRide = playTime
				end
				if bg >= 1e12 and metrics.first1e12Day == math.huge then
					metrics.first1e12Day = dayIndex
				end
				-- v2.0 : jamais au-delà de MaxR (Prestige.splorchReady, « Record absolu ! »)
				if
					splorchAt == math.huge
					and bg >= Formulas.splorchTarget(P.R)
					and (not v2 or P.R < MAX_R)
				then
					-- v2.0 : le Petit Splorch (remontée) se fait hors file, son spectacle dure PetitShow
					splorchAt = now
						+ (
							if v2 and P.R < P.bestR
								then Balance.SplorchV2.PetitShow.Duration
								else SPLORCH_DELAY
						)
				end
			end

			-- une pression sur le squishy prêt le plus rentable, puis un achat éventuel
			local function press()
				local Gt = Gnow()
				local best, bestIncome = nil, -1
				local nReady = 0
				for _, r in P.pen do
					if r.readyAt <= now then
						local inc = r.k * sizeOf(r, Gt)
						if inc > bestIncome then
							best, bestIncome = r, inc
						end
						if v2 then
							-- squishies prêts : cibles possibles des Plopettes (même revenu, même instant)
							nReady += 1
							readyRecs[nReady], readyIncs[nReady] = r, inc
						end
					end
				end
				if best then
					local perfect = rng.chance(PERFECT_SHARE)
					-- série jusqu'à 5 + Super Série, × Gants (Formulas, interrupteurs Workshop et Gloves)
					local superStreak = P.atelier[ROW_SUPER_STREAK]
					P.streak = if perfect then math.min(P.streak + 1, Formulas.streakMax(superStreak)) else 0
					local reward = pressReward(
						bestIncome,
						perfect,
						P.streak,
						families.kitty == true,
						P.tiles.gloves,
						superStreak
					)
					local c = P.coins + reward
					P.coins = if c > MAX_COINS then MAX_COINS else c
					onlineCoins += reward
					pressCoins += reward
					sourceCoins.press = (sourceCoins.press or 0) + reward
					best.readyAt = now + COOLDOWN
					-- Plopettes (GDD §4.28) : une par Record R de Helpers.ByRecordR, + Plume ; une pression
					-- toutes les IntervalBase − IntervalStep × École secondes, sur le squishy prêt depuis
					-- ReadyFor s que le joueur ne presse pas ; pressReward sans PERFECT ni série × Gants
					if v2 then
						if helpersBestR ~= P.bestR then
							helpersBestR, helpersNow = P.bestR, helpersAt(P.bestR)
						end
						local nh = helpersNow + P.atelier[ROW_PLUME]
						if nh > 0 then
							local interval = HELPERS.IntervalBase - HELPERS.IntervalStep * P.tiles.school
							helperBudget += PRESS_EVERY * nh / interval * HELPER_REACH
							local readyBefore = now - HELPERS.ReadyFor
							while helperBudget >= 1 do
								helperBudget -= 1
								local hb, hbInc = nil, -1
								for i = 1, nReady do
									local r = readyRecs[i]
									if r.readyAt <= readyBefore and r ~= best and readyIncs[i] > hbInc then
										hb, hbInc = r, readyIncs[i]
									end
								end
								if hb == nil then
									helperBudget = 0
									break
								end
								local hr = pressReward(
									hbInc,
									false,
									0,
									families.kitty == true,
									P.tiles.gloves
								) * HELPERS.RewardShare
								local c2 = P.coins + hr
								P.coins = if c2 > MAX_COINS then MAX_COINS else c2
								onlineCoins += hr
								sourceCoins.helper = (sourceCoins.helper or 0) + hr
								hb.readyAt = now + COOLDOWN
							end
						end
					end
					if metrics.firstPress == math.huge then
						metrics.firstPress = playTime
					end
					objective("press", 1, perfect)
					if perfect then
						objective("perfect", 1)
						addPoints(POINTS.perfect + POINTS.press)
					elseif POINTS.press > 0 then
						addPoints(POINTS.press)
					end
				end
				tryBuy()
			end

			local stuckAt, stuckCount = -1, 0
			while true do
				-- garde-fou de l'outil : un événement jamais consommé bloquerait la boucle au même instant
				if now == stuckAt then
					stuckCount += 1
					if stuckCount > 200 then
						error(
							string.format(
								"EconomyModel : boucle bloquée à t = %.3f (jeu %.1f s)",
								now,
								playTime
							)
						)
					end
				else
					stuckAt, stuckCount = now, 0
				end
				-- prochain événement (hors pressions)
				local tNext, nextName = sessionEnd, "fin"
				local function at(t, name)
					if t < tNext then
						tNext, nextName = t, name
					end
				end
				if script[scriptIndex] then
					at(script[scriptIndex].at, script[scriptIndex].kind)
				end
				at(nextPotAt, "pot")
				at(nextRush.startsAt, "rush")
				at(wildPersonalAt, "wild")
				at(nextMega.landsAt, "mega")
				at(nextGolden.spawnAt, "golden")
				at(nextGift, "gift")
				at(emoteAt, "emote")
				at(runawayAt, "runaway")
				at(P.vat.hatchAt, "hatch")
				at(P.vat.nextAt, "vat")
				at(splorchAt, "splorch")
				at(personalEndAt(), "personal")
				at(gaugeNextAt(), "gauge")
				at(moonPhase.endsAt, "moonEnd")
				if not moonPhase.active then
					at(moonPhase.startsAt, "moonStart")
				end
				if squishOn then
					at(squishEnd, "squish")
				end
				if stuckCount > 100 then
					error(
						string.format(
							"EconomyModel : événement « %s » jamais consommé (jeu %.1f s)",
							nextName,
							playTime
						)
					)
				end
				if tNext < now then
					tNext = now
				end

				-- pressions jusqu'au prochain événement (avec un éventuel Grand Splorch prêt)
				while nextPressAt < tNext do
					advanceTo(nextPressAt)
					press()
					splorchReadyCheck()
					nextPressAt += PRESS_EVERY
					if splorchAt < tNext then
						tNext = math.max(now, splorchAt)
					end
					-- une pression PERFECT peut remplir la jauge : la fête part tout de suite
					local gNext = gaugeNextAt()
					if gNext < tNext then
						tNext = math.max(now, gNext)
					end
				end
				advanceTo(tNext)
				if now >= sessionEnd then
					break
				end

				-- --- script de l'accueil et jalons (premier jour) ---
				local ev = script[scriptIndex]
				if ev and now >= ev.at then
					scriptIndex += 1
					if ev.kind == "twin" then
						give(Species.PLOP, 0, 1, "vat") -- jumeau de Plop (naissance scriptée)
					elseif ev.kind == "firstRunaway" then
						runawayAt = now -- Mochi Mew, attrapée (leçon du bond)
					elseif ev.kind == "firstPull" then
						vatRoll() -- premier vrai tirage
					elseif ev.kind == "demo" then
						local plop = 1
						for _, r in P.pen do
							if r.bf == 1 then
								plop = sizeOf(r, Gnow())
							end
						end
						captures += 1
						addPoints(POINTS.catch)
						give(
							Species.PLOP,
							0,
							Formulas.babySize(Balance.Babies.DemoShare, Balance.Babies.DemoMin, plop),
							"demo"
						)
					elseif ev.kind == "card" then
						-- jalons de 5:00 (avant la carte), puis objectifs du jour 1 et « Nourris Plop »
						metrics.squishies5 = #P.pen + #P.dodo
						metrics.fusions5 = fusions
						metrics.captures5 = captures
						metrics.coins5 = P.coins
						local payable = P.tiles.pens > 0
							or P.coins >= Formulas.tileCost("pens", P.tiles.pens, P.R)
						metrics.penPayable5 = if payable then 1 else 0
						chores(true)
						buyDirty = true
						scheduleVat()
						runawayAt = math.min(runawayAt, now + Balance.Runaway.Interval)
						if spender then
							squishOn = true
							squishEnd = now + (sessionEnd - now) / 2
							boostChanged()
						end
					elseif ev.kind == "m30" then
						metrics.r30 = P.R
						metrics.stamps30 = QuestRules.stampCount(P.dex)
					end
				end

				-- --- boosts et jauge ---
				if squishOn and now >= squishEnd then
					squishOn = false
					boostChanged()
				end
				if now >= gaugeNextAt() then
					gaugeStep()
				end
				-- le boost personnel vient de finir : g et k sans ×2
				if ctx.boost ~= boostOn() then
					boostChanged()
				end

				-- --- Jelly Moon ---
				if now >= moonPhase.endsAt or (not moonPhase.active and now >= moonPhase.startsAt) then
					moonPhase = EventClock.moon(now)
				end

				-- --- BOOP RUSH et Wild Wobblers ---
				if now >= nextRush.startsAt then
					rushEnd = nextRush.endsAt
					if not onboarding() then
						wildPersonalAt = nextRush.startsAt + Events.Wild.PersonalDelay
						local bg = biggest()
						-- Wild Wobbler partagé : part du serveur de N joueurs
						if rng.chance(sharedWildShare) then
							rollBaby(
								Events.Wild.Quality,
								Events.Wild.Nozzles,
								nil,
								nil,
								Formulas.babySize(Balance.Babies.WildShare, Balance.Babies.WildMin, bg),
								false,
								POINTS.catch
							)
							addFameRush(Balance.Fame.Wild)
							objective("wildCatch", 1)
							objective("rushCatchOrBoop", 1)
						end
						resetCaps()
						if rng.chance(RUSH_BABY_SHARE) and P.caps.rushBabies < Balance.Caps.rushBabies then
							P.caps.rushBabies += 1
							local lvl = Formulas.vatLevel(P.bestR)
							-- original : un squishy d'un autre joueur, de taille voisine ; sa mutation tirée
							-- comme une naissance de la Cuve, puis RushRules.babyMutation (≤ ×5 copiée)
							local original = bg * rng.range(0.5, 2)
							local origMut = Odds.rollMutation(rng(), lvl.nozzles, moonPhase.active)
							local mut = RushRules.babyMutation(origMut, rng(), lvl.nozzles, moonPhase.active)
							rollBaby(
								lvl.quality,
								lvl.nozzles,
								nil,
								mut,
								RushRules.babySize(original, bg),
								false,
								POINTS.rushCatch
							)
							objective("rushCatchOrBoop", 1)
						end
					end
					nextRush = EventClock.rush(nextRush.endsAt)
				end
				if now >= wildPersonalAt then
					wildPersonalAt = math.huge
					if rng.chance(PERSONAL_WILD_SHARE) then
						rollBaby(
							Events.Wild.Quality,
							Events.Wild.Nozzles,
							nil,
							nil,
							Formulas.babySize(Balance.Babies.WildShare, Balance.Babies.WildMin, (biggest())),
							false,
							POINTS.catch
						)
						addFameRush(Balance.Fame.Wild)
						objective("wildCatch", 1)
						objective("rushCatchOrBoop", 1)
					end
				end

				-- --- MEGA SQUISH ---
				if now >= nextMega.landsAt then
					megaEnd = nextMega.burstEndsAt
					if not onboarding() then
						local lvl = Formulas.vatLevel(P.bestR)
						local bg = biggest()
						for _ = 1, MEGA_BABIES do
							local force = if nextMega.moon and rng.chance(Events.Mega.MoonLunarChance)
								then Mutations.LUNAR
								else nil
							rollBaby(
								math.min(8, lvl.quality + Events.Mega.QualityBonus),
								lvl.nozzles,
								Events.Mega.MutationMult,
								force,
								Formulas.babySize(Balance.Babies.MegaShare, Balance.Babies.MegaMin, bg)
							)
						end
						incomeSeconds(Balance.Rewards.MegaSuccess)
						P.fame += Balance.Fame.Mega
						addPoints(POINTS.mega)
						objective("megaJoin", 1)
					end
					nextMega = EventClock.mega(nextMega.burstEndsAt)
				end

				-- --- Golden Wobbler ---
				if now >= nextGolden.spawnAt then
					if
						not onboarding()
						and now - P.goldenWinAt >= Balance.Golden.WinCooldown
						and rng.chance(goldenShare)
					then
						P.goldenWinAt = now
						rollBaby(
							Balance.Golden.Quality,
							0,
							nil,
							Mutations.GOLDEN,
							Formulas.babySize(Balance.Golden.SizeShare, Balance.Golden.MinSize, (biggest())),
							false,
							POINTS.catch
						)
						objective("goldenRace", 1)
					end
					nextGolden = EventClock.golden(nextGolden.endsAt)
				end

				-- --- cadeaux des Grands Splorch des N − 1 autres joueurs ---
				if now >= nextGift then
					nextGift = now + giftEvery
					if not onboarding() then
						resetCaps()
						if P.caps.splorchCoins < Balance.Caps.splorchCoins then
							P.caps.splorchCoins += 1
							incomeSeconds(Balance.Splorch.GiftSeconds)
						else
							incomeSeconds(Balance.Rewards.GiftSecondsAfterCap)
						end
						if P.caps.splorchGifts < Balance.Caps.splorchGifts then
							P.caps.splorchGifts += 1
							local lvl = Formulas.vatLevel(P.bestR)
							rollBaby(
								lvl.quality,
								0,
								nil,
								nil,
								Formulas.babySize(
									Balance.Splorch.GiftSizeShare,
									Balance.Splorch.GiftMinSize,
									(biggest())
								)
							)
							captures -= 1 -- un cadeau n'est pas une capture
						end
					end
				end
				if now >= emoteAt then
					emoteAt = math.huge
					objective("emote", 3)
				end

				-- --- créature en fuite personnelle ---
				if now >= runawayAt then
					local paused = now < rushEnd
						or now < megaEnd
						or (first and playTime >= RUNAWAY_PAUSE_FROM and playTime < ONBOARDING_END)
					if paused then
						runawayAt = math.max(
							rushEnd,
							megaEnd,
							if first and playTime < ONBOARDING_END then atPlay(ONBOARDING_END) else now
						)
						if runawayAt <= now then
							runawayAt = now + 1
						end
					else
						local firstCatch = first and playTime < RUNAWAY_PAUSE_FROM
						local endAt
						if firstCatch or rng.chance(CATCH_SHARE) then
							local bg = biggest()
							local z =
								Formulas.babySize(Balance.Runaway.SizeShare, Balance.Runaway.MinSize, bg)
							if firstCatch then
								captures += 1
								addPoints(POINTS.catch)
								give(Quests.Onboarding.FirstRunawaySpecies, 0, z, "runaway")
							else
								local lvl = Formulas.vatLevel(P.bestR)
								rollBaby(lvl.quality, lvl.nozzles, nil, nil, z, true, POINTS.catch)
							end
							objective("runawayCatch", 1)
							endAt = now + CATCH_TIME
						else
							endAt = now + Balance.Runaway.Duration
						end
						local interval = if families.froggy
							then Species.Families.froggy.bonus.value
							else Balance.Runaway.Interval
						runawayAt = endAt + interval
					end
				end

				-- --- Cuve (après l'accueil) ---
				if not onboarding() then
					if P.vat.hatchAt <= now then
						P.vat.hatchAt = math.huge
						vatRoll()
						scheduleVat()
					end
					if now >= P.vat.nextAt and P.vat.hatchAt == math.huge then
						if #P.pen >= penCap() then
							tryBuy()
						end
						if #P.pen >= penCap() then
							makeRoom()
						end
						if #P.pen < penCap() then
							P.vat.hatchAt = now + Balance.Vat.HatchTime
							P.vat.nextAt = math.huge
						else
							P.vat.nextAt = now + VAT_RETRY
						end
					end
				end

				-- --- fusions, Pot ---
				fuseAll()
				if now >= nextPotAt then
					collectPot()
					if onboardingTiles then
						onboardingTiles = false
						buyDirty = true
					end
					nextPotAt = now + POT_EVERY
				end
				tryBuy()

				-- --- Grand Splorch dès que l'objectif est atteint ---
				splorchReadyCheck()
				if now >= splorchAt then
					splorchAt = math.huge
					applySplorch()
				end
			end
			settle()
			if squishOn then
				squishOn = false
				boostChanged()
			end
			-- débit de points mesuré (les autres joueurs du serveur jouent comme lui)
			local own = ownPoints - ownPointsAtStart
			local span = playTime - playStart
			if first then
				span -= ONBOARDING_END
			end
			if span > 0 then
				local rate = own / span
				measuredRate = if dayIndex <= 2 then rate else 0.5 * measuredRate + 0.5 * rate
				ownPointsTime += span
				othersRate = (N - 1) * measuredRate
			end
		end

		-- =================================================================================
		-- Les jours
		-- =================================================================================
		give(Species.PLOP, 0, 1, "start") -- Plop, Meilleur Ami n° 1 (QuestService, étape 1)
		refreshFamilies()
		setGrowth()
		refreshK()

		-- v2.0 : profil de départ forcé à A Ascensions (nuit, GDD §4.24.1) : un vétéran (Enclos au
		-- maximum, Lit douillet) dont r monte jusqu'à la condition de chaque Ascension par Prestige.apply
		-- répété (le plus gros posé à l'objectif de la boucle), puis l'Ascension ; les Confettis rendus
		-- sont versés et dépensés à l'Atelier, comme en jeu
		local function forceAscends(target)
			P.tiles.pens = Balance.Tiles.pens.Levels
			P.tiles.cozyBed = true
			capLevel = -1
			local plop = P.pen[1]
			local guard = 0
			while P.ascend < math.min(target, MAX_A) do
				while not Prestige.ascendReady(P) do
					settle()
					plop.z, plop.zg = Prestige.target(P.R), P.growth.G
					bigDirty = true
					if not prestige("splorch").applied then
						error("EconomyModel : Prestige.apply refuse un Grand Splorch du profil forcé")
					end
					guard += 1
					if guard > 100000 then
						error("EconomyModel : profil forcé sans fin")
					end
				end
				if not prestige("ascend").applied then
					error("EconomyModel : Prestige.apply refuse l'Ascension du profil forcé")
				end
				atelierBuy()
			end
			incomeDirty, bigDirty, buyDirty = true, true, true
			boostChanged()
		end
		-- « Atelier complet dès le début » (nuit) : chaque ligne de l'Atelier et de « Pour le plaisir »
		-- au maximum avant la première séance
		local function fullAtelier()
			for _, id in CONFETTI_IDS do
				local level = UpgradeMath.level(id, P)
				for l = level, UpgradeMath.maxLevel(id) - 1 do
					buyConfettiLine(id, l)
				end
			end
		end

		-- v2.0 : profils de départ forcés (nuit) : A par Prestige.apply répété, Atelier complet
		if v2 and V.forcedA then
			forceAscends(V.forcedA)
			metrics.startA = P.ascend
		end
		if v2 and V.fullAtelier then
			fullAtelier()
		end

		-- fin de journée (jouée ou non) : jalons et état du jour
		local function endOfDay(d)
			if d == 7 then
				metrics.rDay7 = P.R
				metrics.recordDay7 = P.bestR
				metrics.stampsDay7 = QuestRules.stampCount(P.dex)
				metrics.epicDay7 = if epicEver then 1 else 0
			end
			if d == 14 then
				metrics.rDay14 = P.R
				metrics.recordDay14 = P.bestR
			end
			if d == 28 then
				metrics.rDay28 = P.R
				metrics.recordDay28 = P.bestR
				metrics.stampsDay28 = QuestRules.stampCount(P.dex)
			end
			if d == days then
				metrics.boostShare = 100 * boostTime / math.max(1, sessionTime)
			end
			if v2 then
				local linesDone = true
				for _, id in WORKSHOP_LINES do
					if UpgradeMath.level(id, P) < UpgradeMath.maxLevel(id) then
						linesDone = false
					end
				end
				if linesDone and metrics.workshopAllDay == math.huge then
					metrics.workshopAllDay = d
				end
				local allDone = linesDone
				for _, id in CONFETTI_IDS do
					if UpgradeMath.level(id, P) < UpgradeMath.maxLevel(id) then
						allDone = false
					end
				end
				if allDone and metrics.atelierCompleteDay == math.huge then
					metrics.atelierCompleteDay = d
				end
				local big = (biggest())
				daily[d] = {
					R = P.R,
					best = P.bestR,
					A = P.ascend,
					conf = P.confetti,
					confTotal = P.confettiTotal,
					mon = P.tiles.monuments,
					coins = P.coins,
					big = big,
				}
				if P.coins ~= P.coins or P.coins == math.huge or big ~= big or big == math.huge then
					metrics.nonFinite += 1
				end
			end
		end

		for d = 1, days do
			dayIndex = d
			if playDay and not playDay(d) then
				-- jour sans séance (joueur du week-end) : le hors-ligne a été compté jusqu'au prochain jour joué
				endOfDay(d)
				continue
			end
			pressCoins, onlineCoins = 0, 0
			sourceCoins = {}
			dayPeak = 0
			gaugeJoin()
			if gauge.state == "party" then
				boostChanged()
			end
			if d > 1 then
				chores(true)
				-- Grand Splorch déjà prêt à la connexion (santé : jamais plus d'une fois sur deux)
				if biggest() >= Formulas.splorchTarget(P.R) then
					loginReadyPending = true
				end
			end
			playSession(if d == 1 then firstMin * 60 else dailyMin * 60)
			if v2 then
				-- piste : un Défi fait par séance jouée (3 au plus par période : QuestRules.drawChallenges), puis l'Atelier
				trackRoll()
				if trackChallenges < TRACK.ChallengesPerWeek then
					trackChallenges += 1
					trackAdd(TRACK.PointsPerChallenge)
				end
				atelierBuy()
			end

			if opts.trace then
				local parts = {}
				for key, v in sourceCoins do
					table.insert(parts, string.format("%s %.3g", key, v))
				end
				table.sort(parts)
				local bg = biggest()
				print(
					string.format(
						"  jour %d : R=%d (Record %d, A %d) plus gros %.3g revenu %.3g/s ; Confettis %d ; %s",
						d,
						P.R,
						P.bestR,
						P.ascend,
						bg,
						income(),
						P.confetti,
						table.concat(parts, ", ")
					)
				)
			end
			if d == 1 then
				local done = 0
				for _, e in objectives do
					if e.done then
						done += 1
					end
				end
				metrics.objectivesDay1 = if done == #objectives and done == 3 then 1 else 0
				metrics.rDay1 = P.R
			end
			if d == 7 then
				-- GDD §4.24 « plus gros squishy (avant Grand Splorch) » au jour 7 : la plus grande taille
				-- atteinte ce jour-là, juste avant le Grand Splorch s'il y en a eu un (cible ≈ 1e8, au-dessus de
				-- l'objectif 81 M de R = 9 → 10), sinon le plus gros en fin de séance
				metrics.biggestDay7 = math.max(dayPeak, (biggest()))
				metrics.pressShareDay7 = if onlineCoins > 0 then pressCoins / onlineCoins else 0
				metrics.helperShareDay7 = if onlineCoins > 0
					then (sourceCoins.helper or 0) / onlineCoins
					else 0
				for key, v in sourceCoins do
					metrics["day7_" .. key] = if onlineCoins > 0 then v / onlineCoins else 0
				end
			end
			endOfDay(d)

			-- départ (lastOnline), retour au prochain jour joué à la même heure : rebase hors ligne pur
			if d < days then
				gauge.state, gauge.untilAt = "fill", math.huge
				-- le boost personnel restant est gardé (en pause hors ligne, boosts.personalLeft)
				ctx.boost = false
				local map = {}
				for _, r in P.pen do
					map[r.uid] = r
				end
				local Gt = Formulas.G(P.growth, now)
				local K, S1 = Formulas.ranchIncome(map, Gt, ctx)
				local incomeNoBoost = S1 + K * Gt
				local gctx = growthCtx(false)
				local gNoBoost = Formulas.growthRate(gctx)
				local bg = biggest()
				local lastOnline = math.floor(now)
				local nd = d + 1
				if playDay then
					while nd < days and not playDay(nd) do
						nd += 1
					end
				end
				local nextStart = firstStart + DAY * (nd - 1)
				-- v2.0 : Sac de nuit, Pot de nuit (Workshop), arrêt à 120 s de croissance maximale (RecordR)
				local seconds = Formulas.offlineSeconds(
					nextStart,
					lastOnline,
					P.tiles.cozyBed,
					families.spiky == true,
					if v2 then P.atelier[ROW_NIGHT_BAG] else nil
				)
				local gMax = if v2 then Formulas.maxGrowthRate(gctx) else nil
				P.growth.G = Gt + Formulas.offlineGrowth(gNoBoost, seconds, P.R, bg, gMax)
				local offPot =
					Formulas.offlinePot(incomeNoBoost, seconds, if v2 then P.atelier[ROW_NIGHT_POT] else nil)
				P.potOff += offPot
				if v2 then
					-- offlinePotShare : Pot de la nuit ÷ pièces gagnées en jeu ce jour-là
					table.insert(offPotShares, offPot / math.max(1, onlineCoins))
				end
				now = nextStart
				P.growth.t = now
				boostChanged()
				-- la Cuve ne tourne que joueur présent : elle repart à l'arrivée (goutte en cours perdue)
				P.vat.hatchAt = math.huge
				scheduleVat()
				splorchAt = math.huge
			end
		end

		-- santé : médiane des boucles du joueur (jours 1 à 14)
		local function median(list)
			if #list == 0 then
				return nil
			end
			local sorted = table.clone(list)
			table.sort(sorted)
			local n = #sorted
			if n % 2 == 1 then
				return sorted[(n + 1) / 2]
			end
			return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
		end
		metrics.snack12Share = median(loopShares) or 1
		metrics.coinsLostRatio = median(lostRatios) or 0
		metrics.readyAtLogin = if splorchDays2to14 > 0 then readyAtLoginCount / splorchDays2to14 else 0
		-- remplissage de 0 à pleine au débit mesuré des N joueurs (sans la sieste) ; cycle observé en jeu :
		-- fin de fête → fête suivante, sieste comprise (au moins 20 min)
		local rate = N * measuredRate
		metrics.gaugeFillMin = if rate > 0 then gaugeTarget / rate / 60 else math.huge
		metrics.gaugeCycleMin = if gaugeFills > 0
			then gaugeFillTime / gaugeFills / 60 + GAUGE.PartyDuration / 60
			else math.huge
		metrics.pointsPerMin = if ownPointsTime > 0 then 60 * measuredRate else 0
		if v2 then
			metrics.v2 = summarize(log, daily, offPotShares, (metrics.startA or 0) >= 1)
		end
		return metrics
	end

	local function simulateFor(opts)
		return function(rng, index, days)
			return simulateWith(opts or {}, rng, index, days)
		end
	end

	return { simulate = simulateFor({ players = 16 }), simulateFor = simulateFor }
end

return EconomyModel
