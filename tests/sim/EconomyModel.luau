--!nocheck
-- EconomyModel (paquet logic, docs/04 §16, §17.1 couche f ; GDD §3, §4.24) : un joueur de référence
-- de Raise a Squishy, joué avec les VRAIES règles (Shared/Logic/Formulas, Odds, FusionRules,
-- QuestRules, RushRules, EventClock et les tables de Shared/Config). Seules les hypothèses de
-- COMPORTEMENT du joueur appartiennent au modèle (GDD §4.24) :
--   * 35 min de jeu le premier jour, puis 30 min par jour, une séance par jour à la même heure (le
--     hors-ligne entre deux dépasse toujours la limite : 8 h, 12 h avec le Lit douillet, + 1 h Spiky) ;
--   * une pression toutes les 2 s sur le squishy prêt le plus rentable, PERFECT 40 % du temps ;
--   * Pot encaissé toutes les 40 s (le premier à 1:30, accueil) ;
--   * achats du moins cher utile d'abord (Tapis, Enclos si plein, décorations, Lit douillet), un
--     achat toutes les 2 s au plus (il faut marcher jusqu'à la dalle) ;
--   * fusion dès qu'une paire de jumeaux existe (« Tout fusionner », FusionRules.planMergeAll) ;
--   * le plus gros reste en enclos, les plus faibles vont dans la Boîte à dodo pour laisser naître la
--     Cuve (après l'accueil) ; Dodo plein : « Ranger » (GDD §4.13), sinon vente du plus faible ;
--   * 85 % des créatures en fuite attrapées ;
--   * boosts ×2 calculés d'après les règles, jamais supposés : boost de serveur (Wobble Party) 20 % du
--     temps par fenêtres de 5 min (après l'accueil, docs/04 §16) ; Nourrir Plop au début de chaque
--     séance (le premier jour, à la carte des objectifs de 5:00), durée Balance.Boosts.FeedDay /
--     FeedMilestone ; les objectifs du jour rapportent leurs minutes de revenu mais AUCUN boost
--     (GDD §4.24 et §7.4, révision 1.3 : les sources de boost du joueur de référence sont le bol et
--     la Wobble Party ; voir la note d'intégration sur Config/Quests.ObjectiveRules.Rewards) ;
--     un boost personnel est en pause pendant un boost de serveur (GDD §4.25) ;
--   * événements moyens : 60 % des Rush avec un bébé, 50 % des Wild Wobblers partagés, 85 % des
--     personnels, 2 bébés par MEGA, 30 % des Golden, un cadeau de Grand Splorch toutes les 20 min ;
--   * aucun achat Robux ; aucun ami sur le serveur ; 3 emotes par séance.
-- Le calendrier des événements est celui d'EventClock (heure de départ tirée pour chaque joueur) ;
-- les naissances utilisent Odds.roll avec la graine du jeu (Odds.seed) ; le Pot est l'intégrale
-- exacte (Formulas.potGain) ; le hors-ligne passe par Formulas.offline* (rebase de onPrepare).
-- Pas de 2 s pendant les 10 premières minutes (jalons de l'accueil), puis de 8 s avec 4 pressions
-- (une toutes les 2 s) : même comportement, quatre fois moins de pas.
--
--   local EconomyModel = require("../sim/EconomyModel")
--   local model = EconomyModel.new(L)  -- L : modules requis par le harnais (voir EconomyPacing.spec)
--   Sim.run({ players = 200, days = 28, simulate = model.simulate, gates = EconomyModel.GATES, … })

local EconomyModel = {}

local DAY = 86400
local PRESS_EVERY = 2 -- s : une pression toutes les 2 s
local FINE_UNTIL = 600 -- s de jeu en pas de 2 s (jalons de l'accueil)
local COARSE_STEP = 8 -- s ensuite (4 pressions par pas)
local FIRST_PRESS = 10 -- s : Big Plop pose Plop, le joueur presse (GDD §3)
local FIRST_POT = 90 -- s : premier Pot (étape 6 de l'accueil)
local POT_EVERY = 40
local TWIN_AT = 40
local FIRST_RUNAWAY_AT = 120
local FIRST_PULL_AT = 166 -- 2:45 + éclosion
local DEMO_AT = 180
local ONBOARDING_END = 300
local SPLORCH_DELAY = 23 -- s : file du serveur (≈ 20 s) + éclatement (3,2 s)
local BOOST_WINDOW = 300 -- s : fenêtres de 5 min, ×2 de serveur avec une chance de 20 %
local BOOST_SHARE = 0.2
local PERFECT_SHARE = 0.4
local CATCH_SHARE = 0.85
local CATCH_TIME = 10 -- s pour attraper une créature en fuite
local RUSH_BABY_SHARE = 0.6
local SHARED_WILD_SHARE = 0.5
local PERSONAL_WILD_SHARE = 0.85
local MEGA_BABIES = 2
local GOLDEN_SHARE = 0.3
local GIFT_EVERY = 1200
local EMOTES_AT = 120 -- s de séance : 3 emotes faites (objectif 6)
local PLAYERS_ON_SERVER = 16
local START_UNIX = 1797638400 -- lundi 14/12/2026 00:00 UTC (après le lancement)

-- Portes de la simulation (docs/04 §16, GDD §4.24). Les parts (≥ 90 %, ≥ 95 %) sont vérifiées à part
-- par la spec (EconomyModel.SHARES) : une médiane ne mesure pas une proportion.
EconomyModel.GATES = {
	{ key = "firstPress", label = "Première pression (s)", max = 15 },
	{ key = "firstBuy", label = "Premier achat (s)", max = 30 },
	{ key = "squishies5", label = "Squishies à 5:00", min = 3, max = 4 },
	{ key = "fusions5", label = "Fusions à 5:00", min = 1 },
	{ key = "captures5", label = "Captures à 5:00", min = 1 },
	{ key = "firstRide", label = "Première balade (s)", max = 300 },
	{ key = "firstSplorch", label = "Premier Grand Splorch (min)", min = 12, max = 16 },
	{ key = "r30", label = "R à 30 min", min = 1, max = 3 },
	{ key = "stamps30", label = "Tampons à 30 min", min = 14, max = 24 },
	{ key = "rDay1", label = "R en fin de jour 1", min = 2, max = 3 },
	{ key = "rDay7", label = "R en fin de jour 7", min = 8, max = 11 },
	{ key = "biggestDay7", label = "Plus gros, fin du jour 7", min = 5e7, max = 3e8 },
	{ key = "stampsDay7", label = "Tampons en fin de jour 7", min = 80, max = 110 },
	{ key = "rDay28", label = "R en fin de jour 28", min = 17, max = 22 },
}

EconomyModel.SHARES = {
	{ key = "penPayable5", label = "Dalle Enclos payable à 5:00", min = 0.9 },
	{ key = "objectivesDay1", label = "3 objectifs sur 3 au jour 1", min = 0.9 },
	{ key = "epicDay7", label = "Un Épique+ au jour 7", min = 0.95 },
}

EconomyModel.REPORTED = {
	{ key = "coins5", label = "Pièces à 5:00 (repère)" },
	{ key = "rDay14", label = "R en fin de jour 14" },
	{ key = "stampsDay28", label = "Tampons en fin de jour 28" },
	{ key = "first1e12Day", label = "Premier squishy de 1e12 (jour)" },
	{ key = "boostShare", label = "Part du temps de jeu en ×2 (%)" },
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
	local OBJECTIVE_REWARD = Quests.ObjectiveRules.Rewards
	local COOLDOWN = Balance.Press.Cooldown
	local MAX_COINS = Balance.Numbers.Max

	local function simulate(rng, index, days)
		-- =================================================================================
		-- État (même forme que le profil quand une règle du jeu le lit)
		-- =================================================================================
		local now = START_UNIX + math.floor(rng.range(0, 7 * DAY))
		local firstStart = now
		local playTime = 0 -- s de jeu cumulé
		local userId = 100000 + index
		local P = {
			coins = 0,
			pot = 0,
			R = 0,
			fame = 0,
			growth = { G = 0, g = 1, t = now },
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false },
			pen = {}, -- squishies en enclos (et Bassin) : rapportent et grandissent
			dodo = {}, -- Boîte à dodo : taille figée
			nextUid = 1,
			dex = { mut = table.create(SPECIES_COUNT, 0), stars = table.create(SPECIES_COUNT, 0) },
			trophies = table.create(SPECIES_COUNT, 0),
			biggestEver = 0,
			vat = {
				nextAt = math.huge,
				hatchAt = math.huge,
				pityRare = 0,
				pityEpic = 0,
				newPulls = Balance.Vat.NewPulls,
				pulls = 0,
			},
			personalBoost = 0,
			plopDays = 0,
			caps = { day = -1, rushBabies = 0, splorchGifts = 0, fameRush = 0 },
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
		}
		local fusions, captures = 0, 0
		local boostTime = 0 -- s de jeu en ×2 (boosts calculés)
		local ctx = {
			decor = 0,
			friends = 0,
			fame = 0,
			trophyBonus = 0,
			goldenPages = 0,
			doubleCoins = false,
			boost = false,
		}
		local families = {}
		local serverBoost = false
		local fuseDirty, buyDirty = true, true
		local dirtySpecies = {} -- espèces qui ont reçu une ligne : seules elles peuvent avoir une paire
		local cheapest = math.huge
		local onboardingTiles = true -- avant le premier Pot : seul le premier Tapis
		local objectives = {}
		local objectivesDay = -1
		local epicEver = false
		local moonPhase = { active = false, startsAt = -math.huge, endsAt = -math.huge }

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
		local function boostOn()
			return serverBoost or P.personalBoost > 0
		end
		local function refreshFamilies()
			for key in Species.Families do
				families[key] = QuestRules.familyComplete(P.dex, key)
			end
		end
		local capCache, capLevel = 0, -1
		local function penCap()
			if capLevel ~= P.tiles.pens then
				capLevel = P.tiles.pens
				capCache = Formulas.penCapacity(P.tiles.pens, false)
			end
			return capCache
		end
		local function allRecords()
			local map = {}
			for _, r in P.pen do
				map[r.uid] = r
			end
			for _, r in P.dodo do
				map[r.uid] = r
			end
			return map
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
		-- règlement : Pot intégré exactement sur [growth.t ; now] (EconomyService.settle), trophées
		-- (K, S1) de Formulas.ranchIncome ne changent qu'avec les lignes de l'enclos ou le contexte :
		-- recalculés seulement quand l'un d'eux a changé (incomeDirty)
		local cachedK, cachedS1, incomeDirty = 0, 0, true
		local function settle()
			local Gt = Formulas.G(P.growth, now)
			if incomeDirty then
				-- même somme que Formulas.ranchIncome (K = Σ k, S1 = Σ k × (z − zg)), avec les k
				-- déjà calculés par Formulas.incomeFactor pour le contexte en cours
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
			P.pot += Formulas.potGain(cachedK, cachedS1, P.growth, P.growth.t, now)
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
		local function biggest()
			local Gt = Gnow()
			local best, bestRec = 0, nil
			for _, r in P.pen do
				local s = sizeOf(r, Gt)
				if s > best then
					best, bestRec = s, r
				end
			end
			return best, bestRec
		end
		local function addCoins(x)
			P.coins = Formulas.clampCoins(P.coins + x)
		end
		local function incomeSeconds(seconds)
			addCoins(Formulas.secondsOfIncome(income(), seconds))
		end
		local function resetCaps()
			local day = math.floor(now / DAY)
			if P.caps.day ~= day then
				P.caps = { day = day, rushBabies = 0, splorchGifts = 0, fameRush = 0 }
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
		-- objectifs du jour : progression (QuestRules.apply), réclamation aussitôt terminés
		local function objective(stat, amount, perfect)
			for _, e in objectives do
				if not e.claimed and (e.stat == stat or (e.streak and stat == "press")) then
					local out = QuestRules.apply(e, stat, amount, perfect)
					e.p = out.p
					if out.done and not e.done then
						e.done = true
						e.claimed = true
						-- minutes de revenu seulement : pas de boost (politique du joueur de référence,
						-- GDD §4.24 et §7.4 révision 1.3 ; en-tête du fichier)
						local reward = OBJECTIVE_REWARD[Quests.Objectives[e.id].tier]
						incomeSeconds(reward.incomeSeconds)
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
				refreshFamilies() -- nouvelle espèce : un bonus de famille peut s'ouvrir
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
				readyAt = 0,
			}
			rec.k = incomeFactor(s, m, 0, ctx)
			if at == "pen" then
				settle() -- le Pot est réglé avec l'ancien enclos avant d'ajouter la ligne
				incomeDirty = true
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
			-- pré-test rapide : au moins deux lignes non verrouillées de même espèce et mêmes étoiles
			-- le joueur de référence fusionne aussi à la main ses jumeaux verrouillés (GDD §4.13) ;
			-- avant l'ajout il ne restait aucune paire : seules les espèces qui ont reçu une ligne
			-- peuvent en avoir une (le plan de FusionRules traite chaque espèce à part)
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
					merged.at = if a.at == "pen" or b.at == "pen" then "pen" else "dodo"
					merged.uid = kept
					merged.readyAt = 0
					merged.k = incomeFactor(merged.s, merged.m, merged.st, ctx)
					removeUid(pair[1])
					removeUid(pair[2])
					table.insert(if merged.at == "pen" then P.pen else P.dodo, merged)
					incomeDirty = true
					map[pair[1]], map[pair[2]] = nil, nil
					map[kept] = merged
					fusions += 1
					local resultSize = if merged.at == "pen" then sizeOf(merged, Gt) else merged.z
					addCoins(Formulas.comboReward(step, merged.k * resultSize))
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
			local _, bigRec = biggest()
			local weakest, weakestIncome = nil, math.huge
			for i, r in P.pen do
				if r.bf == 0 and r ~= bigRec then
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
			elseif best == "decor" then
				refreshK()
			end
		end

		local function collectPot()
			settle()
			addCoins(P.pot)
			P.pot = 0
			objective("potCollect", 1)
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
				newPull = P.vat.newPulls > 0,
				pityRare = P.vat.pityRare,
				pityEpic = P.vat.pityEpic,
			})
			P.vat.pulls += 1
			metrics.vatPulls = (metrics.vatPulls or 0) + 1
			if result.usedNewPull then
				P.vat.newPulls -= 1
			end
			P.vat.pityRare, P.vat.pityEpic = result.pityRare, result.pityEpic
			give(result.species, result.mutation, 1, "vat")
		end
		local function scheduleVat()
			P.vat.nextAt = now + Formulas.vatInterval(P.R, families.bunny == true)
		end

		-- bébé d'un événement (toutes familles ou familles débloquées), taille donnée
		local function rollBaby(quality, nozzles, mult, force, z, unlockedOnly)
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
			return give(result.species, result.mutation, z, "event")
		end

		-- Grand Splorch d'un bloc (EconomyService.applySplorch + SquishyService.resetSizes)
		local function applySplorch()
			settle()
			P.coins, P.pot = 0, 0
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
			P.growth = { G = 0, g = P.growth.g, t = now }
			boostChanged()
			buyDirty = true
			objective("splorch", 1)
			if metrics.firstSplorch == math.huge then
				metrics.firstSplorch = playTime / 60
			end
		end

		-- Nourrir Plop (jours au total) : boost personnel, palier du jour 2 en pièces
		local function feed()
			P.plopDays += 1
			local milestone = QuestRules.plopReward(P.plopDays)
			local was = boostOn()
			P.personalBoost += if milestone then Balance.Boosts.FeedMilestone else Balance.Boosts.FeedDay
			if milestone and milestone.kind == "coins" then
				incomeSeconds(Balance.Rewards.PlopDay2)
			end
			if not was then
				boostChanged()
			end
		end

		-- objectifs du jour (jour 1 : fixes) et Nourrir Plop (jours au total, boost personnel)
		local function chores(dayIndex, withFeed)
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
		-- Une séance
		-- =================================================================================
		local runawayAt = math.huge
		local splorchAt = math.huge
		local function playSession(duration, dayIndex)
			local sessionEnd = playTime + duration
			local sessionT0 = now
			local nextRush = EventClock.rush(now)
			local nextMega = EventClock.mega(now)
			local nextGolden = EventClock.golden(now)
			local nextGift = now + GIFT_EVERY
			local boostWindowEnd = now
			local nextPot = if playTime == 0 then FIRST_POT else playTime + POT_EVERY
			local rushEnd, megaEnd = -math.huge, -math.huge
			local wildPersonalAt = math.huge
			local emoted = false
			if dayIndex > 1 then
				runawayAt = now + Balance.Runaway.Interval
			end
			while playTime < sessionEnd do
				local fine = playTime < FINE_UNTIL
				local step = if fine then PRESS_EVERY else COARSE_STEP
				local onboarding = dayIndex == 1 and playTime < ONBOARDING_END

				-- --- script de l'accueil (premier jour) ---
				if dayIndex == 1 then
					if playTime == TWIN_AT then
						give(Species.PLOP, 0, 1, "vat") -- jumeau de Plop (naissance scriptée)
					elseif playTime == FIRST_RUNAWAY_AT then
						runawayAt = now -- Mochi Mew, attrapée (leçon du bond)
					elseif playTime == FIRST_PULL_AT then
						vatRoll() -- premier vrai tirage
					elseif playTime == DEMO_AT then
						local plop = 1
						for _, r in P.pen do
							if r.bf == 1 then
								plop = sizeOf(r, Gnow())
							end
						end
						captures += 1
						give(
							Species.PLOP,
							0,
							Formulas.babySize(Balance.Babies.DemoShare, Balance.Babies.DemoMin, plop),
							"demo"
						)
					end
					if playTime == ONBOARDING_END then
						-- carte de 5:00 : objectifs du jour 1 et « Nourris Plop : Jour 1 »
						chores(dayIndex, true)
						buyDirty = true
						scheduleVat()
						runawayAt = math.min(runawayAt, now + Balance.Runaway.Interval)
					end
				end

				-- --- boosts ---
				if not onboarding and now >= boostWindowEnd then
					local was = boostOn()
					serverBoost = rng.chance(BOOST_SHARE)
					boostWindowEnd = now + BOOST_WINDOW
					if was ~= boostOn() then
						boostChanged()
					end
				end
				if P.personalBoost > 0 and not serverBoost then
					P.personalBoost -= step
					if P.personalBoost <= 0 then
						P.personalBoost = 0
						boostChanged()
					end
				end

				-- --- événements du serveur (EventClock) ---
				if now >= moonPhase.endsAt or (not moonPhase.active and now >= moonPhase.startsAt) then
					moonPhase = EventClock.moon(now)
				end
				if now >= nextRush.startsAt then
					rushEnd = nextRush.endsAt
					if not onboarding then
						wildPersonalAt = nextRush.startsAt + Events.Wild.PersonalDelay
						local bg = biggest()
						local caught = 0
						for _ = 1, RushRules.wildShared(PLAYERS_ON_SERVER) do
							if
								caught < Events.Wild.SharedPerPlayerPerRush and rng.chance(SHARED_WILD_SHARE)
							then
								caught += 1
								rollBaby(
									Events.Wild.Quality,
									Events.Wild.Nozzles,
									nil,
									nil,
									Formulas.babySize(Balance.Babies.WildShare, Balance.Babies.WildMin, bg)
								)
								addFameRush(Balance.Fame.Wild)
								objective("wildCatch", 1)
								objective("rushCatchOrBoop", 1)
							end
						end
						resetCaps()
						if rng.chance(RUSH_BABY_SHARE) and P.caps.rushBabies < Balance.Caps.rushBabies then
							P.caps.rushBabies += 1
							local lvl = Formulas.vatLevel(P.R)
							rollBaby(
								lvl.quality,
								lvl.nozzles,
								nil,
								nil,
								RushRules.babySize(bg * rng.range(0.5, 2), bg)
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
							Formulas.babySize(Balance.Babies.WildShare, Balance.Babies.WildMin, (biggest()))
						)
						addFameRush(Balance.Fame.Wild)
						objective("wildCatch", 1)
						objective("rushCatchOrBoop", 1)
					end
				end
				if now >= nextMega.landsAt then
					megaEnd = nextMega.burstEndsAt
					if not onboarding then
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
						objective("megaJoin", 1)
					end
					nextMega = EventClock.mega(nextMega.burstEndsAt)
				end
				if now >= nextGolden.spawnAt then
					if
						not onboarding
						and now - P.goldenWinAt >= Balance.Golden.WinCooldown
						and rng.chance(GOLDEN_SHARE)
					then
						P.goldenWinAt = now
						rollBaby(
							Balance.Golden.Quality,
							0,
							nil,
							Mutations.GOLDEN,
							Formulas.babySize(Balance.Golden.SizeShare, Balance.Golden.MinSize, (biggest()))
						)
						objective("goldenRace", 1)
					end
					nextGolden = EventClock.golden(nextGolden.endsAt)
				end
				if now >= nextGift then
					nextGift = now + GIFT_EVERY
					if not onboarding then
						incomeSeconds(Balance.Splorch.GiftSeconds)
						resetCaps()
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
				if not emoted and now - sessionT0 >= EMOTES_AT then
					emoted = true
					objective("emote", 3)
				end

				-- --- créature en fuite personnelle ---
				local paused = now < rushEnd
					or now < megaEnd
					or (dayIndex == 1 and playTime >= 165 and playTime < ONBOARDING_END)
				if now >= runawayAt and not paused then
					local first = dayIndex == 1 and playTime < 165
					local endAt
					if first or rng.chance(CATCH_SHARE) then
						local bg = biggest()
						local z = Formulas.babySize(Balance.Runaway.SizeShare, Balance.Runaway.MinSize, bg)
						if first then
							captures += 1
							give(Quests.Onboarding.FirstRunawaySpecies, 0, z, "runaway")
						else
							local lvl = Formulas.vatLevel(P.R)
							rollBaby(lvl.quality, lvl.nozzles, nil, nil, z, true)
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

				-- --- Cuve (après l'accueil) ---
				if not onboarding then
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
						end
					end
				end

				-- --- fusions et Pot ---
				fuseAll()
				if playTime >= nextPot then
					collectPot()
					if onboardingTiles then
						onboardingTiles = false
						buyDirty = true
					end
					nextPot = playTime + POT_EVERY
				end

				-- --- pressions (une toutes les 2 s) et achats ---
				for k = 0, step - PRESS_EVERY, PRESS_EVERY do
					local t = now + k
					if playTime + k >= FIRST_PRESS then
						local Gt = Gnow() + P.growth.g * k
						local best, bestIncome = nil, -1
						for _, r in P.pen do
							if r.readyAt <= t then
								local inc = r.k * sizeOf(r, Gt)
								if inc > bestIncome then
									best, bestIncome = r, inc
								end
							end
						end
						if best then
							local perfect = rng.chance(PERFECT_SHARE)
							P.streak = if perfect then math.min(P.streak + 1, Balance.Press.StreakMax) else 0
							-- récompense déjà entière et bornée (Formulas.pressReward) : addition simple
							local c = P.coins
								+ pressReward(bestIncome, perfect, P.streak, families.kitty == true)
							P.coins = if c > MAX_COINS then MAX_COINS else c
							best.readyAt = t + COOLDOWN
							if metrics.firstPress == math.huge then
								metrics.firstPress = playTime + k
							end
							objective("press", 1, perfect)
							if perfect then
								objective("perfect", 1)
							end
						end
					end
					tryBuy()
				end

				-- --- Grand Splorch dès que l'objectif est atteint ---
				local bg = biggest()
				if bg >= 1200 and metrics.firstRide == math.huge then
					metrics.firstRide = playTime
				end
				if bg >= 1e12 and metrics.first1e12Day == math.huge then
					metrics.first1e12Day = dayIndex
				end

				if splorchAt == math.huge and bg >= Formulas.splorchTarget(P.R) then
					splorchAt = now + SPLORCH_DELAY
				end
				if now >= splorchAt then
					splorchAt = math.huge
					applySplorch()
				end

				-- --- jalons ---
				if dayIndex == 1 then
					if playTime == ONBOARDING_END then
						metrics.squishies5 = #P.pen + #P.dodo
						metrics.fusions5 = fusions
						metrics.captures5 = captures
						metrics.coins5 = P.coins
						local payable = P.tiles.pens > 0
							or P.coins >= Formulas.tileCost("pens", P.tiles.pens, P.R)
						metrics.penPayable5 = if payable then 1 else 0
					end
					if playTime == 1800 then
						metrics.r30 = P.R
						metrics.stamps30 = QuestRules.stampCount(P.dex)
					end
				end

				if serverBoost or P.personalBoost > 0 then
					boostTime += step
				end
				now += step
				playTime += step
			end
			settle()
		end

		-- =================================================================================
		-- Les jours
		-- =================================================================================
		give(Species.PLOP, 0, 1, "start") -- Plop, Meilleur Ami n° 1 (QuestService, étape 1)
		refreshFamilies()
		setGrowth()
		refreshK()

		for dayIndex = 1, days do
			if dayIndex > 1 then
				chores(dayIndex, true)
			end
			playSession(if dayIndex == 1 then 35 * 60 else 30 * 60, dayIndex)

			if dayIndex == 1 then
				local done = 0
				for _, e in objectives do
					if e.done then
						done += 1
					end
				end
				metrics.objectivesDay1 = if done == #objectives and done == 3 then 1 else 0
				metrics.rDay1 = P.R
			end
			if dayIndex == 7 then
				-- plus gros squishy en fin de jour 7, dans la boucle en cours (avant son Grand Splorch)
				metrics.biggestDay7 = (biggest())
				metrics.rDay7 = P.R
				metrics.stampsDay7 = QuestRules.stampCount(P.dex)
				metrics.epicDay7 = if epicEver then 1 else 0
			end
			if dayIndex == 14 then
				metrics.rDay14 = P.R
			end
			if dayIndex == days then
				metrics.boostShare = 100 * boostTime / math.max(1, playTime)
				metrics.rDay28 = P.R
				metrics.stampsDay28 = QuestRules.stampCount(P.dex)
			end

			-- départ (lastOnline), retour le lendemain à la même heure : rebase hors ligne pur
			if dayIndex < days then
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
				local lastOnline = math.floor(now)
				local nextStart = firstStart + DAY * dayIndex
				local seconds =
					Formulas.offlineSeconds(nextStart, lastOnline, P.tiles.cozyBed, families.spiky == true)
				now = nextStart
				P.growth.G = Gt + Formulas.offlineGrowth(gNoBoost, seconds)
				P.pot += Formulas.offlinePot(incomeNoBoost, seconds)
				P.growth.t = now
				serverBoost = false
				boostChanged()
				-- la Cuve ne tourne que joueur présent : elle repart à l'arrivée (goutte en cours perdue)
				P.vat.hatchAt = math.huge
				scheduleVat()
				splorchAt = math.huge
			end
		end
		return metrics
	end

	return { simulate = simulate }
end

return EconomyModel
