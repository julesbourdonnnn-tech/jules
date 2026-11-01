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

EconomyModel.SIZES = { 4, 8, 16 }

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

	local function simulateWith(opts, rng, index, days)
		local N = opts.players or 16
		local spender = opts.spender == true
		local sharedWildShare = SHARED_WILD_SHARE[N] or (3 / N)
		local goldenShare = GOLDEN_SHARE[N] or (1 / N)
		local giftEvery = GIFT_EVERY_16 * 15 / math.max(1, N - 1)
		local gaugeTarget = GAUGE.TargetPerPlayer * math.max(GAUGE.MinPlayers, N)

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
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false },
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
			caps = { day = -1, rushBabies = 0, splorchGifts = 0, splorchCoins = 0, fameRush = 0 },
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
		}
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
		local function setGrowth()
			settle()
			P.growth.g = Formulas.growthRate({
				R = P.R,
				snack = P.tiles.snack,
				jellyFamily = families.jelly == true,
				boost = boostOn(),
			})
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
				P.caps = { day = day, rushBabies = 0, splorchGifts = 0, splorchCoins = 0, fameRush = 0 }
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

		-- achat : le moins cher utile d'abord ; un achat par appel (marcher jusqu'à la dalle)
		local function tryBuy()
			if not buyDirty and P.coins < cheapest then
				return
			end
			local best, bestCost = nil, math.huge
			local function consider(tile, useful)
				if useful then
					local lvl = if tile == "cozyBed"
						then (if P.tiles.cozyBed then 1 else 0)
						else P.tiles[tile]
					local cost = Formulas.tileCost(tile, lvl, P.R)
					if cost < bestCost then
						best, bestCost = tile, cost
					end
				end
			end
			if onboardingTiles then
				consider("snack", P.tiles.snack == 0)
			else
				consider("snack", true)
				consider("pens", #P.pen >= penCap() and playTime >= ONBOARDING_END)
				consider("decor", true)
				consider("cozyBed", P.R >= Balance.Tiles.cozyBed.MinR and not P.tiles.cozyBed)
			end
			cheapest, buyDirty = bestCost, false
			if best == nil or bestCost == math.huge or P.coins < bestCost then
				return
			end
			settle()
			P.coins -= bestCost
			if best == "cozyBed" then
				P.tiles.cozyBed = true
			else
				P.tiles[best] += 1
			end
			buyDirty = true
			if metrics.firstBuy == math.huge then
				metrics.firstBuy = playTime
			end
			objective("tileBuy", 1)
			if best == "snack" then
				setGrowth()
				if P.tiles.snack >= SNACK_LEVELS and snack12Play == nil then
					snack12Play = playTime
				end
			elseif best == "decor" then
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
			local lvl = Formulas.vatLevel(P.R)
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
				families = Odds.unlockedFamilies(P.R),
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
			P.vat.nextAt = now + Formulas.vatInterval(P.R, families.bunny == true)
		end

		-- bébé d'un événement (toutes familles ou familles débloquées), taille donnée
		local function rollBaby(quality, nozzles, mult, force, z, unlockedOnly, points)
			local result = Odds.roll(Hash.stream(Odds.seed(userId, 1e6 + P.nextUid)), {
				quality = quality,
				nozzles = nozzles,
				moon = moonPhase.active,
				unix = math.floor(now),
				families = if unlockedOnly then Odds.unlockedFamilies(P.R) else nil,
				mutationMult = mult,
				forceMutation = force,
			})
			captures += 1
			if points then
				addPoints(points)
			end
			return give(result.species, result.mutation, z, "event")
		end

		-- Grand Splorch d'un bloc (EconomyService.applySplorch + SquishyService.resetSizes)
		local function applySplorch()
			settle()
			local peak = biggest()
			if peak > dayPeak then
				dayPeak = peak -- le plus gros juste avant de repartir à 1
			end
			local lost = P.coins + P.potOn + P.potOff
			if dayIndex <= HEALTH_LAST_DAY then
				local loopLen = playTime - loopStartPlay
				local share = 1
				if snack12Play ~= nil and loopLen > 0 then
					share = math.clamp((snack12Play - loopStartPlay) / loopLen, 0, 1)
				end
				table.insert(loopShares, share)
				table.insert(lostRatios, lost / Formulas.tileCost("snack", SNACK_LEVELS - 1, P.R))
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
						"  splorch R=%d jour %d : jeu %.0f s, boucle %.0f s, Tapis12 à %s, Tapis %d, décos %d, pièces %.3g, Pot jeu %.3g, Pot hors ligne %.3g, Tapis 12 = %.3g (×%.1f)",
						P.R,
						dayIndex,
						playTime,
						playTime - loopStartPlay,
						tostring(snack12Play and (snack12Play - loopStartPlay)),
						P.tiles.snack,
						P.tiles.decor,
						P.coins,
						P.potOn,
						P.potOff,
						Formulas.tileCost("snack", SNACK_LEVELS - 1, P.R),
						lost / Formulas.tileCost("snack", SNACK_LEVELS - 1, P.R)
					)
				)
			end
			P.coins, P.potOn, P.potOff = 0, 0, 0
			P.tiles.snack, P.tiles.decor = 0, 0
			P.R += 1
			P.fame += Balance.Fame.Splorch
			for _, r in P.pen do
				r.z, r.zg = 1, 0
			end
			for _, r in P.dodo do
				r.z, r.zg = 1, 0
			end
			incomeDirty = true
			bigDirty = true
			P.growth = { G = 0, g = P.growth.g, t = now }
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
				if splorchAt == math.huge and bg >= Formulas.splorchTarget(P.R) then
					splorchAt = now + SPLORCH_DELAY
				end
			end

			-- une pression sur le squishy prêt le plus rentable, puis un achat éventuel
			local function press()
				local Gt = Gnow()
				local best, bestIncome = nil, -1
				for _, r in P.pen do
					if r.readyAt <= now then
						local inc = r.k * sizeOf(r, Gt)
						if inc > bestIncome then
							best, bestIncome = r, inc
						end
					end
				end
				if best then
					local perfect = rng.chance(PERFECT_SHARE)
					P.streak = if perfect then math.min(P.streak + 1, Balance.Press.StreakMax) else 0
					local reward = pressReward(bestIncome, perfect, P.streak, families.kitty == true)
					local c = P.coins + reward
					P.coins = if c > MAX_COINS then MAX_COINS else c
					onlineCoins += reward
					pressCoins += reward
					sourceCoins.press = (sourceCoins.press or 0) + reward
					best.readyAt = now + COOLDOWN
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
							local lvl = Formulas.vatLevel(P.R)
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
						local lvl = Formulas.vatLevel(P.R)
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
							local lvl = Formulas.vatLevel(P.R)
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
								local lvl = Formulas.vatLevel(P.R)
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

		for d = 1, days do
			dayIndex = d
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
			playSession(if d == 1 then 35 * 60 else 30 * 60)

			if opts.trace then
				local parts = {}
				for key, v in sourceCoins do
					table.insert(parts, string.format("%s %.3g", key, v))
				end
				table.sort(parts)
				local bg = biggest()
				print(
					string.format(
						"  jour %d : R=%d plus gros %.3g revenu %.3g/s ; %s",
						d,
						P.R,
						bg,
						income(),
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
				metrics.rDay7 = P.R
				metrics.stampsDay7 = QuestRules.stampCount(P.dex)
				metrics.epicDay7 = if epicEver then 1 else 0
				metrics.pressShareDay7 = if onlineCoins > 0 then pressCoins / onlineCoins else 0
				for key, v in sourceCoins do
					metrics["day7_" .. key] = if onlineCoins > 0 then v / onlineCoins else 0
				end
			end
			if d == 14 then
				metrics.rDay14 = P.R
			end
			if d == days then
				metrics.boostShare = 100 * boostTime / math.max(1, sessionTime)
				metrics.rDay28 = P.R
				metrics.stampsDay28 = QuestRules.stampCount(P.dex)
			end

			-- départ (lastOnline), retour le lendemain à la même heure : rebase hors ligne pur
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
				local gNoBoost = Formulas.growthRate({
					R = P.R,
					snack = P.tiles.snack,
					jellyFamily = families.jelly == true,
					boost = false,
				})
				local bg = biggest()
				local lastOnline = math.floor(now)
				local nextStart = firstStart + DAY * d
				local seconds =
					Formulas.offlineSeconds(nextStart, lastOnline, P.tiles.cozyBed, families.spiky == true)
				P.growth.G = Gt + Formulas.offlineGrowth(gNoBoost, seconds, P.R, bg)
				P.potOff += Formulas.offlinePot(incomeNoBoost, seconds)
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
