--!nocheck
-- Simulation de rythme de progression (GDD §4.18) — paquet « logic », aide de tests/specs/EconomyPacing.
--
-- Simule des joueurs de référence (30 min de jeu actif par jour, 35 le premier jour, gains hors
-- ligne gratuits 50 % / 8 h, aucun achat) sur N jours avec les VRAIES tables du jeu : Balance,
-- Nebbies, Zones, Quests, Events, et les VRAIES fonctions Logic/Formulas, Logic/EventClock,
-- Logic/WorldLayout. Tous les nombres de jeu viennent de là ; seules les hypothèses de
-- COMPORTEMENT du joueur et du serveur de référence sont propres au modèle (table Pacing.Model,
-- documentée dans docs/04-architecture.md §17).
--
-- Modèle d'une session : une suite de courses. Course = aller vers la zone choisie selon la
-- capacité de file → captures une à une (temps de capture = max(attente de l'apparition partagée,
-- marche jusqu'au Nebby) + ramassage) → pertes par coupe (12 % hors Prairie, sauf bouclier
-- débutant) → retour → parade (Formulas.paradeGlow avec M du moment) → collection, Atlas, quêtes
-- → Supernova si possible, sinon améliorations au moins cher d'abord. Revenu passif réglé en
-- continu (Formulas.settle), Comètes du planning réel (EventClock) gagnées 1 fois sur 6, météo
-- réelle (formes à 40 %, Meteor Shower ÷3), quêtes du jour, calendrier, Grand Défilé, chaîne
-- d'accueil Q1-Q7. Fin de session : fusions (Tout fusionner), tri des perchoirs, débordement de la
-- réserve (libération automatique C/U/R contre Stardust). Entre deux sessions : Formulas.offlineGlow.

local Pacing = {}

-- Hypothèses de comportement (jamais des nombres de jeu : ceux-ci viennent de la configuration)
Pacing.Model = {
	-- Serveur de référence : 8 joueurs actifs (capScale 0,75) qui se répartissent entre les zones
	-- selon une distribution idéale libre (joueurs ∝ valeur de parade apparue par seconde dans la
	-- zone, calculée depuis Config/Zones et Config/Nebbies) : chacun reçoit sa part du flux
	-- d'apparitions de sa zone (la zone se vide plus vite qu'elle ne se remplit)
	ReferenceActive = 8,
	AliveRatio = 0.5, -- population moyenne d'une zone disputée = moitié de son plafond effectif
	PickupSeconds = 0.3, -- viser et ramasser
	-- Temps de recherche par capture (chercher des yeux, contourner, rater, mobile) : calibré sur le
	-- bilan à 5 minutes du GDD §3 (4 à 6 parades ET 4 à 6 améliorations : 10 s donne 5 et 5), avec
	-- les valeurs du GDD, AVANT tout réglage de Balance ; vérifié par la porte « Parades à 5 min »
	SearchSeconds = 10,
	TravelSample = 0.2, -- trajet = distance moyenne aux 20 % de points d'apparition les plus proches
	MeadowBelow = 6, -- capacité < 6 : Prairie
	GladeBelow = 12, -- capacité < 12 : Clairière ; sinon Cratère
	SnipLoss = 0.12, -- part des Nebbies perdus par coupe hors Prairie (§4.18)
	CometWinChance = 1 / 6, -- Comètes gagnées 1 fois sur 6 (§4.18)
	SaveRatio = 0.10, -- n'achète pas une amélioration qui coûte plus de 10 % de la Supernova visée
	HardQuestChance = 2 / 3, -- quête difficile terminée 2 jours sur 3 (facile et moyenne : toujours)
	QuestAt = { 0.25, 0.5, 0.75 }, -- instants de fin des 3 quêtes du jour (fraction de la session)
	FirstDayMinutes = 35,
	DailyMinutes = 30,
	IntroSeconds = 1.5, -- travelling caméra de l'arrivée
	ReactionSeconds = 5, -- un nouveau joueur s'oriente avant de bouger
	UpgradeUiSeconds = 8, -- l'icône Améliorer apparaît, le joueur l'ouvre et achète
	FirstDay = 20759, -- jour UTC du 1er jour simulé (un lundi : semaine alignée sur Grand Défilé)
}

-- Tolérances du GDD §4.18 (en minutes pour S1, en jours 1-based sinon)
Pacing.Gates = {
	{ key = "firstParade", label = "Première parade (s)", max = 20 },
	{ key = "firstUpgrade", label = "Première amélioration (s)", max = 30 },
	{ key = "ftueParades", label = "Parades à 5 min (§3)", min = 4, max = 6 },
	{ key = "sn1Minutes", label = "Supernova 1 (min de jeu)", min = 20, max = 35 },
	{ key = "sn3Day", label = "Supernova 3 (jour)", min = 2, max = 4 },
	{ key = "sn6Star3Day", label = "Supernova 6 + premier ★3 (jour)", min = 6, max = 8 },
	{ key = "atlas50Day", label = "50 % de l'Atlas (jour)", min = 10, max = 16 },
	{ key = "sn10Day", label = "Supernova 10 (jour)", min = 18, max = 24 },
}

Pacing.Reported = {
	{ key = "ftueAtlas", label = "Entrées d'Atlas à 5 min (§3 : 5-8)" },
	{ key = "ftueUpgrades", label = "Améliorations à 5 min (§3 : 4-6)" },
	{ key = "star3Day", label = "Premier ★3 (jour)" },
	{ key = "sn6Day", label = "Supernova 6 (jour)" },
	{ key = "atlas80Day", label = "80 % de l'Atlas (jour)" },
	{ key = "finalR", label = "R au jour final" },
	{ key = "finalAtlas", label = "Entrées d'Atlas au jour final" },
}

local DAY = 86400

-- Générateur congruentiel (produits < 2^53 : exact en double), déterministe par joueur
local function newRng(seed: number)
	local state = (seed * 2654435761 + 12345) % 4294967296
	return function(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Prépare les tables partagées par tous les joueurs (zones, valeurs, météo)
local function prepare(deps)
	local Balance, Nebbies, Zones, Formulas, WorldLayout =
		deps.Balance, deps.Nebbies, deps.Zones, deps.Formulas, deps.WorldLayout
	local M = Pacing.Model
	local ctx = { deps = deps }

	-- Zones : tirage de rareté, intervalle, densité, trajet depuis la porte
	ctx.zones = {}
	local gate = WorldLayout.gateCFrame(1).Position
	local capScale = Formulas.capScale(M.ReferenceActive)
	-- valeur de parade apparue par seconde dans chaque zone (forme normale, sans variante)
	local zoneValue, valueSum = {}, 0
	for _, def in Zones.List do
		local ev, w = 0, 0
		for _, odd in def.odds do
			ev += odd.weight * Nebbies.Rarities[odd.rarity].parade
			w += odd.weight
		end
		zoneValue[def.key] = (ev / math.max(w, 1e-9)) / def.interval
		valueSum += zoneValue[def.key]
	end
	for _, def in Zones.List do
		local points = WorldLayout.spawnPoints(def.key)
		local area = math.max(1, #points) * Balance.Spawn.GridStep ^ 2
		local alive = math.max(1, math.floor(def.cap * capScale + 0.5) * M.AliveRatio)
		local distances = {}
		for _, p in points do
			local dx, dz = p.X - gate.X, p.Z - gate.Z
			table.insert(distances, math.sqrt(dx * dx + dz * dz))
		end
		table.sort(distances)
		local take = math.max(1, math.floor(#distances * M.TravelSample))
		local sum = 0
		for i = 1, take do
			sum += distances[i]
		end
		local rarities, cumulative, total = {}, {}, 0
		for _, odd in def.odds do
			if #Nebbies.speciesOfRarity(odd.rarity) > 0 then
				total += odd.weight
				table.insert(rarities, odd.rarity)
				table.insert(cumulative, total)
			end
		end
		ctx.zones[def.key] = {
			key = def.key,
			interval = def.interval,
			crowd = math.max(1, M.ReferenceActive * zoneValue[def.key] / valueSum),
			spacing = 0.5 / math.sqrt(alive / area), -- distance moyenne au plus proche voisin
			travel = sum / take,
			rarities = rarities,
			cumulative = cumulative,
			total = total,
		}
	end

	ctx.species = {}
	for r = 1, Nebbies.RARITY_COUNT do
		ctx.species[r] = Nebbies.speciesOfRarity(r)
	end
	ctx.variants = {}
	for _, key in Nebbies.VARIANT_ORDER do
		local v = Nebbies.Variants[key]
		if v.chance then
			table.insert(ctx.variants, { bit = v.bit, chance = v.chance })
		end
	end

	-- Valeurs mises en cache (Formulas)
	local paradeCache, incomeCache = {}, {}
	function ctx.paradeValue(code)
		local v = paradeCache[code]
		if v == nil then
			v = Formulas.paradeValue(code)
			paradeCache[code] = v
		end
		return v
	end
	function ctx.income(key) -- key = code × 8 + étoiles
		local v = incomeCache[key]
		if v == nil then
			local code = key // 8
			local s, f, var = Nebbies.unpack(code)
			v = Formulas.passiveIncome({ s = s, f = f, v = var, st = key % 8 })
			incomeCache[key] = v
		end
		return v
	end

	-- Météo (EventClock) mise en cache par créneau météo et par jour (Starfall) : forme, diviseur
	-- d'intervalle (Meteor Shower), boost de serveur du show
	local Events = deps.Events
	local period, starfallStart = Events.Weather.Period, Events.Starfall.StartSecond
	assert(Events.Weather.Offset + Events.Weather.Duration <= period, "fenêtre météo sur deux créneaux")
	local NONE = { form = 0, intervalDiv = 1, starfall = false }
	local slotCache, dayCache = {}, {}
	local function infoOf(win)
		local def = Events.WeatherByKey[win.key]
		return { form = win.form or 0, intervalDiv = def and def.intervalDiv or 1, starfall = win.starfall }
	end
	function ctx.weatherAt(t)
		local d = t // DAY
		local sf = dayCache[d]
		if sf == nil then
			local win = deps.EventClock.starfall(d * DAY + starfallStart)
			sf = if win
				then {
					startsAt = win.startsAt,
					endsAt = win.endsAt,
					info = infoOf(deps.EventClock.weather(win.startsAt)),
				}
				else false
			dayCache[d] = sf
		end
		if sf and t >= sf.startsAt and t < sf.endsAt then
			return sf.info
		end
		local slot = t // period
		local w = slotCache[slot]
		if w == nil then
			local win = deps.EventClock.weather(slot * period + Events.Weather.Offset)
			w = if win and not win.starfall
				then { startsAt = win.startsAt, endsAt = win.endsAt, info = infoOf(win) }
				else false
			slotCache[slot] = w
		end
		if w and t >= w.startsAt and t < w.endsAt then
			return w.info
		end
		return NONE
	end

	ctx.atlasTotal = Nebbies.atlasTotal()
	ctx.formChance = Balance.Spawn.WeatherFormChance
	return ctx
end

-- Un joueur sur `days` jours ; retourne ses jalons
local function simulatePlayer(ctx, index: number, days: number)
	local deps = ctx.deps
	local Balance, Nebbies, Formulas, Quests, EventClock =
		deps.Balance, deps.Nebbies, deps.Formulas, deps.Quests, deps.EventClock
	local M = Pacing.Model
	local rand = newRng(index)

	-- État du joueur
	local glow, carry, stardust, R = 0, 0, 0, 0
	local up = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 }
	local coll = {} -- clé (code × 8 + étoiles) → nombre
	local total = 0
	local perched = {} -- revenus perchés, décroissants
	local perchIncome = 0
	local atlas, atlasCount = {}, 0
	local boostUntil = -math.huge
	local activeSeconds = 0
	local onboarding = 1
	local onboardingCounter = 0
	local weekBanked, weekClaimed = {}, {}
	local calendarStep = 1
	local lastSettle = 0
	local lastEnd = nil
	local rookie = true
	local uiUnlocked = false -- 1er jour : le rail (Améliorer, calendrier) n'apparaît qu'après la 1re parade
	local ftue = { parades = 0, upgrades = 0 }
	local out = {
		firstParade = math.huge,
		firstUpgrade = math.huge,
		sn1Minutes = math.huge,
		sn3Day = math.huge,
		sn6Day = math.huge,
		star3Day = math.huge,
		sn10Day = math.huge,
		atlas50Day = math.huge,
		atlas80Day = math.huge,
		ftueParades = 0,
		ftueUpgrades = 0,
		ftueAtlas = 0,
	}
	local day = 0
	local sessionStart = 0

	local function perchCount()
		return Formulas.perchCount(up.perches, atlasCount, false)
	end

	local function multiplier(t)
		local boost = t < boostUntil or ctx.weatherAt(t).starfall
		return Formulas.multiplier({
			supernovas = R,
			vip = false,
			crewPresent = 0,
			doubleGlow = false,
			boost = boost,
		})
	end

	local function idleRate(t)
		return perchIncome * multiplier(t)
	end

	-- Règlement paresseux jusqu'à t
	local function settle(t)
		if t > lastSettle then
			local r = Formulas.settle(glow, carry, idleRate(lastSettle), t - lastSettle)
			glow, carry = r.glow, r.carry
			lastSettle = t
		end
	end

	-- Perchoirs : les N meilleurs revenus (insertion incrémentale ou recalcul complet)
	local function rebuildPerches()
		local list = {}
		for key, count in coll do
			if count > 0 then
				table.insert(list, key)
			end
		end
		table.sort(list, function(a, b)
			return ctx.income(a) > ctx.income(b)
		end)
		local n = perchCount()
		table.clear(perched)
		perchIncome = 0
		for _, key in list do
			local income = ctx.income(key)
			for _ = 1, coll[key] do
				if #perched >= n then
					break
				end
				table.insert(perched, income)
				perchIncome += income
			end
			if #perched >= n then
				break
			end
		end
	end

	local function insertPerch(income)
		local n = perchCount()
		if #perched < n then
			table.insert(perched, income)
			perchIncome += income
		elseif n > 0 and income > perched[#perched] then
			perchIncome += income - perched[#perched]
			perched[#perched] = income
		else
			return
		end
		local i = #perched
		while i > 1 and perched[i] > perched[i - 1] do
			perched[i], perched[i - 1] = perched[i - 1], perched[i]
			i -= 1
		end
	end

	local function addNebby(code, stars)
		local key = code * 8 + (stars or 1)
		coll[key] = (coll[key] or 0) + 1
		total += 1
		insertPerch(ctx.income(key))
		local s, f = Nebbies.unpack(code)
		local entry = s * 8 + f
		if not atlas[entry] then
			atlas[entry] = true
			atlasCount += 1
			if Formulas.atlasPerchMilestones(atlasCount) ~= Formulas.atlasPerchMilestones(atlasCount - 1) then
				rebuildPerches()
			end
			local dayIndex = day + 1
			if day == 0 and lastSettle - sessionStart <= 300 then
				out.ftueAtlas = atlasCount
			end
			if atlasCount >= ctx.atlasTotal * 0.5 and out.atlas50Day == math.huge then
				out.atlas50Day = dayIndex
			end
			if atlasCount >= ctx.atlasTotal * 0.8 and out.atlas80Day == math.huge then
				out.atlas80Day = dayIndex
			end
		end
	end

	local function grantReward(reward, t)
		if reward == nil then
			return
		end
		settle(t)
		if reward.glow then
			glow += reward.glow
		end
		if reward.idleSeconds then
			glow += Formulas.glowForSeconds(idleRate(t), reward.idleSeconds, reward.minGlow)
		end
		if reward.stardust then
			stardust += reward.stardust
		end
		if reward.boostSeconds then
			settle(t)
			boostUntil = math.max(t, boostUntil) + reward.boostSeconds
		end
		if reward.species then
			addNebby(Nebbies.pack(reward.species, 0, 0), 1)
		end
		if reward.rotation then
			addNebby(Nebbies.pack(EventClock.rotation(reward.rotation, EventClock.week(t)), 0, 0), 1)
		end
	end

	-- Chaîne d'accueil : avance tant que la quête active est remplie
	local function onboardingEvent(t, event)
		local quests = Quests.Onboarding
		while onboarding <= #quests do
			local q = quests[onboarding]
			local g = q.goal
			local done = false
			if g.kind == "paradeSize" then
				done = event.parade ~= nil and event.parade >= g.n
			elseif g.kind == "upgrade" then
				if event.upgrade == g.track then
					onboardingCounter += 1
				end
				done = onboardingCounter >= g.n
			elseif g.kind == "bankRarity" then
				done = event.maxRarity ~= nil and event.maxRarity >= g.minRarity
			elseif g.kind == "weatherOrComet" then
				done = event.weather == true or event.comet == true
			elseif g.kind == "perches" then
				done = perchCount() >= g.n
			end
			if not done then
				return
			end
			grantReward(q.reward, t)
			onboarding += 1
			onboardingCounter = 0
			event = {} -- un même événement ne remplit qu'une quête
		end
	end

	local function dayIndexNow()
		return day + 1
	end

	local function supernova(t)
		settle(t)
		glow, carry = 0, 0
		for track, def in Balance.Upgrades do
			if def.ResetOnSupernova then
				up[track] = 0
			end
		end
		R += 1
		if R == 1 then
			out.sn1Minutes = (activeSeconds + (t - sessionStart)) / 60
		elseif R == 3 then
			out.sn3Day = dayIndexNow()
		elseif R == 6 then
			out.sn6Day = dayIndexNow()
		elseif R == 10 then
			out.sn10Day = dayIndexNow()
		end
	end

	-- Supernova si possible, sinon améliorations au moins cher d'abord (épargne au-delà de SaveRatio)
	local function spend(t)
		if not uiUnlocked then
			return
		end
		settle(t)
		-- pendant la chaîne d'accueil, le panneau ne montre qu'une carte et se ferme après l'achat
		-- (§3) : une amélioration au plus par retour au Nid
		local budget = if day == 0 and onboarding <= #Quests.Onboarding then 1 else math.huge
		while true do
			local snCost = Formulas.supernovaCost(R)
			if glow >= snCost then
				supernova(t)
			else
				local best, bestCost = nil, math.huge
				for _, track in Balance.UpgradeOrder do
					if up[track] < Formulas.upgradeMaxLevel(track, R) then
						local c = Formulas.upgradeCost(track, up[track])
						if c < bestCost then
							best, bestCost = track, c
						end
					end
				end
				if best == nil or bestCost > glow or bestCost > M.SaveRatio * snCost or budget <= 0 then
					return
				end
				budget -= 1
				glow -= bestCost
				up[best] += 1
				if day == 0 and t - sessionStart <= 300 then
					ftue.upgrades += 1
				end
				if out.firstUpgrade == math.huge then
					out.firstUpgrade = activeSeconds + (t - sessionStart) + M.UpgradeUiSeconds
				end
				if best == "perches" then
					rebuildPerches()
				end
				if day == 0 then
					onboardingEvent(t, { upgrade = best })
				end
			end
		end
	end

	-- Tirage d'un Nebby sauvage dans une zone à l'instant t
	local function drawWild(zone, t)
		local u = rand() * zone.total
		local rarity = zone.rarities[#zone.rarities]
		for i, c in zone.cumulative do
			if u < c then
				rarity = zone.rarities[i]
				break
			end
		end
		local list = ctx.species[rarity]
		local s = list[math.floor(rand() * #list) + 1]
		local f = 0
		local w = ctx.weatherAt(t)
		if w.form ~= 0 and rand() < ctx.formChance then
			f = w.form
		end
		local v = 0
		for _, variant in ctx.variants do
			if rand() < variant.chance then
				v += variant.bit
			end
		end
		return Nebbies.pack(s, f, v), rarity, f
	end

	-- Fin de session : Tout fusionner (meilleur revenu obtenu d'abord), perchoirs, réserve
	local copies = Balance.Starforge.Copies
	local maxStars = Balance.Starforge.MaxStars
	local function fuseKey(key)
		-- fusionne tout ce que la Stardust permet pour cette clé, puis enchaîne l'étoile suivante
		while key % 8 < maxStars and (coll[key] or 0) >= copies do
			local stars = key % 8
			local cost = Formulas.fuseCost(stars)
			if cost == nil or cost > stardust then
				return
			end
			local times = math.min(coll[key] // copies, stardust // cost)
			coll[key] -= times * copies
			coll[key + 1] = (coll[key + 1] or 0) + times
			total -= times * (copies - 1)
			stardust -= times * cost
			if stars + 1 >= 3 and out.star3Day == math.huge then
				out.star3Day = day + 1
			end
			key += 1
		end
	end
	local function endOfSession()
		local candidates = {}
		for key, count in coll do
			if count >= copies and key % 8 < maxStars then
				table.insert(candidates, key)
			end
		end
		table.sort(candidates, function(a, b)
			return ctx.income(a + 1) > ctx.income(b + 1)
		end)
		for _, key in candidates do
			fuseKey(key)
		end
		rebuildPerches()
		-- réserve pleine : libération automatique des moins rentables (Commun, Peu commun, Rare)
		local capacity = perchCount() + Formulas.stashCap(false)
		if total > capacity then
			local releasable = {}
			for key, count in coll do
				local s = (key // 8) % 64
				if count > 0 and Nebbies.rarityOf(s) <= Balance.Stash.AutoReleaseMaxRarity then
					table.insert(releasable, key)
				end
			end
			table.sort(releasable, function(a, b)
				return ctx.income(a) < ctx.income(b)
			end)
			-- les perchés ne sont jamais libérés : on garde au moins ce qui est perché
			for _, key in releasable do
				if total <= capacity then
					break
				end
				local s = (key // 8) % 64
				local dust = Formulas.releaseDust(Nebbies.rarityOf(s), key % 8) or 0
				local n = math.min(coll[key], total - capacity)
				coll[key] -= n
				total -= n
				stardust += n * dust
			end
			rebuildPerches()
		end
	end

	-- -----------------------------------------------------------------------------------------
	-- Jours
	-- -----------------------------------------------------------------------------------------
	for d = 0, days - 1 do
		day = d
		local minutes = if d == 0 then M.FirstDayMinutes else M.DailyMinutes
		local duration = minutes * 60
		local dayStart = (M.FirstDay + d) * DAY
		sessionStart = dayStart + math.floor(rand() * (DAY - duration - 600))
		local tEnd = sessionStart + duration
		local t = sessionStart

		-- hors ligne depuis la fin de la session précédente
		if lastEnd then
			local rate = perchIncome * Formulas.offlineMultiplier(R, false, false)
			local gain = Formulas.offlineGlow(rate, sessionStart - lastEnd, false)
			glow += gain
		end
		lastSettle = t
		rookie = Formulas.rookieEligible(d + 1, activeSeconds, R)

		-- calendrier de connexion (indulgent : un jour joué = une étape) ; le 1er jour, après la
		-- 1re parade (interface progressive, aucune fenêtre avant)
		local calendarPending = d == 0
		if not calendarPending then
			uiUnlocked = true
			grantReward(Quests.Calendar[calendarStep], t)
			calendarStep = calendarStep % #Quests.Calendar + 1
		end
		spend(t)

		-- quêtes du jour
		local questDone = { false, false, rand() < M.HardQuestChance }
		questDone[1] = true
		questDone[2] = true
		local questIndex = 1

		-- Comètes du planning réel pendant la session
		local comets = {}
		local probe = sessionStart - Balance.Comet.WarnSeconds
		while true do
			local c = EventClock.nextComet(probe)
			if c.impactAt >= tEnd then
				break
			end
			table.insert(comets, c)
			probe = c.warnAt
		end
		local cometIndex = 1

		local week = d // 7
		local firstRun = d == 0

		while t < tEnd do
			local capacity = Formulas.congaCapacity(up.conga)
			local speed = Formulas.baseWalkSpeed(up.stride)
			local lure = Formulas.lureRadius(up.lure, false) + Balance.Catch.LatencyTolerance
			local codes, maxRarity, weatherCatch = {}, 0, false
			local zone
			if firstRun then
				-- Puffkins de bienvenue : 3 personnels à 12 studs devant la porte (§3)
				firstRun = false
				zone = nil
				local walk = Balance.Spawn.WelcomeDistance * 2 + deps.Zones.Nests.GateDistance + 6
				t += M.IntroSeconds + M.ReactionSeconds + walk / speed + 3 * M.PickupSeconds
				for _ = 1, Balance.Spawn.WelcomeCount do
					table.insert(codes, Nebbies.pack(Nebbies.Named.Welcome, 0, 0))
				end
				maxRarity = 1
			else
				local key = if capacity < M.MeadowBelow
					then "meadow"
					elseif capacity < M.GladeBelow then "glade"
					else "crater"
				zone = ctx.zones[key]
				t += zone.travel / speed
				local move = math.max(0, zone.spacing - lure) / speed
				for _ = 1, capacity do
					local w = ctx.weatherAt(t)
					local supply = zone.crowd * zone.interval / w.intervalDiv * -math.log(1 - rand())
					t += math.max(supply, move) + M.PickupSeconds + M.SearchSeconds
					local code, rarity, f = drawWild(zone, t)
					table.insert(codes, code)
					if t >= tEnd then
						break
					end
				end
				-- pertes par coupe hors Prairie (bouclier débutant : aucune)
				if key ~= "meadow" and not rookie then
					local kept = {}
					for _, code in codes do
						if rand() >= M.SnipLoss then
							table.insert(kept, code)
						end
					end
					codes = kept
				end
				t += zone.travel / speed
			end

			-- parade
			settle(t)
			if #codes > 0 then
				local glowGain = Formulas.paradeGlow(codes, multiplier(t), false, false)
				glow += glowGain
				for _, code in codes do
					local s, f = Nebbies.unpack(code)
					maxRarity = math.max(maxRarity, Nebbies.rarityOf(s))
					weatherCatch = weatherCatch or f ~= 0
					addNebby(code, 1)
				end
				weekBanked[week] = (weekBanked[week] or 0) + #codes
				if out.firstParade == math.huge then
					out.firstParade = t - sessionStart
				end
				if d == 0 and t - sessionStart <= 300 then
					ftue.parades += 1
				end
				if calendarPending then
					calendarPending = false
					uiUnlocked = true
					grantReward(Quests.Calendar[calendarStep], t + M.UpgradeUiSeconds)
					calendarStep = calendarStep % #Quests.Calendar + 1
				end
				if d == 0 then
					onboardingEvent(t, { parade = #codes, maxRarity = maxRarity, weather = weatherCatch })
				end
			end

			-- Comètes tombées pendant la course
			while cometIndex <= #comets and comets[cometIndex].impactAt <= t do
				local c = comets[cometIndex]
				cometIndex += 1
				if d == 0 then
					onboardingEvent(t, { comet = true })
				end
				if rand() < M.CometWinChance then
					local rarity, s = EventClock.cometContent(c.id)
					local _ = rarity
					local f = ctx.weatherAt(c.impactAt).form
					settle(t)
					glow += Formulas.glowForSeconds(idleRate(t), Balance.Comet.BankIdleSeconds)
					stardust += Balance.Comet.HoldDust
					addNebby(Nebbies.pack(s, f, 0), 1)
				end
			end

			-- quêtes du jour terminées pendant la course
			while questIndex <= 3 and t >= sessionStart + duration * M.QuestAt[questIndex] do
				if questDone[questIndex] then
					grantReward(Quests.DailyTiers[Quests.DailyTierOrder[questIndex]], t)
				end
				if questIndex == 3 and questDone[1] and questDone[2] and questDone[3] then
					grantReward(Quests.DailyStar, t)
				end
				questIndex += 1
			end

			-- Grand Défilé de la semaine
			if not weekClaimed[week] and (weekBanked[week] or 0) >= Quests.Weekly.goal.n then
				weekClaimed[week] = true
				grantReward(Quests.Weekly.reward, t)
			end

			spend(t)
		end

		settle(t)
		if d == 0 then
			out.ftueParades = ftue.parades
			out.ftueUpgrades = ftue.upgrades
		end
		activeSeconds += t - sessionStart
		lastEnd = t
		endOfSession()
		spend(t)
	end

	out.sn6Star3Day = math.max(out.sn6Day, out.star3Day)
	out.finalR = R
	out.finalAtlas = atlasCount
	return out
end

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return math.huge
	end
	if n % 2 == 1 then
		return sorted[(n + 1) // 2]
	end
	local a, b = sorted[n // 2], sorted[n // 2 + 1]
	if a == math.huge or b == math.huge then
		return math.huge
	end
	return (a + b) / 2
end

-- Lance la simulation. deps = { Balance, Nebbies, Zones, Events, Quests, Formulas, EventClock, WorldLayout }
function Pacing.run(deps, players: number, days: number)
	local ctx = prepare(deps)
	local results = {}
	for i = 1, players do
		results[i] = simulatePlayer(ctx, i, days)
	end
	local medians = {}
	local keys = {}
	for _, g in Pacing.Gates do
		table.insert(keys, g.key)
	end
	for _, r in Pacing.Reported do
		table.insert(keys, r.key)
	end
	for _, key in keys do
		local values = {}
		for _, r in results do
			table.insert(values, r[key])
		end
		medians[key] = median(values)
	end
	return { medians = medians, players = results }
end

-- Rapport lisible (affiché par la spec)
function Pacing.report(result): string
	local lines = {}
	local function fmt(x)
		if x == math.huge then
			return "jamais"
		end
		return string.format("%.1f", x)
	end
	for _, g in Pacing.Gates do
		local m = result.medians[g.key]
		local ok = (g.min == nil or m >= g.min) and (g.max == nil or m <= g.max)
		table.insert(
			lines,
			string.format(
				"  %-34s médiane %8s   tolérance [%s ; %s]   %s",
				g.label,
				fmt(m),
				tostring(g.min or "—"),
				tostring(g.max),
				if ok then "OK" else "HORS"
			)
		)
	end
	for _, r in Pacing.Reported do
		table.insert(lines, string.format("  %-34s médiane %8s", r.label, fmt(result.medians[r.key])))
	end
	return table.concat(lines, "\n")
end

return Pacing
