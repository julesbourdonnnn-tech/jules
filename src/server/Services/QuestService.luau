--!strict
-- QuestService — paquet « events » (docs/04-architecture.md §11.10).
-- Propriétaire de : onboarding, daily (calendrier), quests (du jour), weekly, rookie, stats, codes.
-- Suit la progression en écoutant les signaux serveur (Signals.*), jamais en interrogeant les
-- services plus tardifs (table goal.kind → signal : en-tête de Config/Quests).
-- Responsabilités :
--   * chaîne d'accueil Q1-Q7 (Config/Quests.Onboarding) : récompense AUTOMATIQUE à la complétion,
--     Celebrate "questDone" puis "questClaimed", étape d'entonnoir ; au premier PlayerReady (step 0) :
--     SpawnService.spawnWelcome et setDirected pendant Q1-Q3 ; Q4 : spawnGuaranteedRare (une fois
--     par compte, au début de Q4)
--   * entonnoir d'accueil (§14.1) : TOUTES les étapes 1-10 sont envoyées ici (Analytics.funnel)
--   * quêtes du jour : tirage déterministe Hash(jour, UserId) d'1 facile, 1 moyenne, 1 difficile
--     (JcJ exclues en Zen et remplacées au passage en Zen, Équipage seulement si
--     stats.lastCrewDay ≥ jour − 7) ; relance gratuite (+1 VIP) ; remise à zéro à 00:00 UTC ;
--     récompenses par niveau ; « Étoile du jour » (boost 15 min) quand les 3 sont réclamées
--   * quête hebdomadaire Grand Défilé (300 Nebbies encaissés → Légendaire de la semaine + 300)
--   * calendrier de 7 jours indulgent (un jour manqué = pause) ; remote ClaimDaily 1/s
--   * remotes ClaimQuest(kind, slot) 4/s, RerollQuest(slot) 1/s, RedeemCode(code) 1/3 s et 10/h
--     (Data/Codes ; une fois par compte ; statut "ok" | "invalid" | "expired" | "used" | "busy")
--   * bouclier débutant (Formulas.rookieEligible) : isRookie() ; fin jamais en pleine course —
--     attendue jusqu'à onSafeMoment (parade ou file vide, appelé par CongaService ; la longueur de
--     file est suivie par Signals.LineChanged) ; bannière personnelle « rookieEnd », attribut
--     Player « Rookie », Signals.RookieEnded, Analytics RookieShieldEnded (minutes jouées)
--   * statistiques (clé « stats ») et temps de jeu (step, crochet onBeforeSave) ; titres de
--     statistiques (Cosmetics.Titles, source « stat ») via NestService.unlock ; SessionLength
--   * registre du cadeau Starfall Saturday (stats.starfallGift = startsAt du dernier show servi) :
--     crochet EventService.setStarfallClaim, un Starborn garanti par compte et par show
--   * PlayerReady : rattrapage au Start() (signal émis pendant le Start() d'un service précédent),
--     accueil une seule fois par session
-- GDD : §3, §4.16, §7.3-§7.5, §14.1, §4.17 (codes).
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService,
-- SpawnService, EventService, CrewService, Logic/Hash, Logic/Formulas, Logic/EventClock,
-- Config/Quests, Data/Codes, Signals, Util/Notify, Util/RateLimit, Util/Analytics, Shared/Util/Clock,
-- Events/QuestLogic, Events/Safe, Events/Tuning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Nebbies = require(Shared.Config.Nebbies)
local Quests = require(Shared.Config.Quests)
local EventClock = require(Shared.Logic.EventClock)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Codes = require(Server.Data.Codes)
local Signals = require(Server.Signals)
local Analytics = require(Server.Util.Analytics)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local QuestLogic = require(Server.Events.QuestLogic)
local Safe = require(Server.Events.Safe)
local Tuning = require(Server.Events.Tuning)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)
local EconomyService = require(script.Parent.EconomyService)
local AtlasService = require(script.Parent.AtlasService)
local SpawnService = require(script.Parent.SpawnService)
local EventService = require(script.Parent.EventService)
local CrewService = require(script.Parent.CrewService)

local QuestService = {}

local TAG = "QuestService"

-- Débits des remotes (docs §10.1)
local RATE = {
	claimDaily = { n = 1, per = 1 },
	claimQuest = { n = 4, per = 1 },
	reroll = { n = 1, per = 1 },
	redeem = { n = 1, per = 3 },
	redeemHour = { n = 10, per = 3600 },
}

local ONBOARDING_DONE = #Quests.Onboarding + 1 -- 8 : chaîne terminée
local DAILY_SLOTS = #Quests.DailyTierOrder

local FUNNEL_NAME: { [number]: string } = {}
for _, f in Quests.Funnel do
	FUNNEL_NAME[f.step] = f.name
end

local function onboardingIndex(id: string): number
	for i, q in Quests.Onboarding do
		if q.id == id then
			return i
		end
	end
	return 0
end
local DIRECTED_UNTIL = onboardingIndex(Tuning.DirectedUntilQuest)
local GUARANTEED_RARE_AT = onboardingIndex(Tuning.GuaranteedRareQuest)

-- ---------------------------------------------------------------------------------------------
-- État de session (mémoire)
-- ---------------------------------------------------------------------------------------------

type Session = {
	data: { [string]: any }, -- profil de cette session (détecte un rechargement)
	joinedAt: number,
	lastTick: number,
	playAcc: number, -- secondes de jeu pas encore écrites dans le profil
	lastFlush: number,
	firstSession: boolean,
	lineLen: number, -- longueur de file connue (Signals.LineChanged)
	rookieDue: boolean, -- fin du bouclier décidée, appliquée au prochain moment sûr
	day: number,
	week: number,
	ready: boolean, -- PlayerReady déjà traité (signal ou rattrapage du Start)
}

local sessions: { [Player]: Session } = {}
-- Joueurs partis (clés faibles) : aucune nouvelle session ne leur est ouverte par un signal tardif
local departed: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastSlowAt = 0

-- Clés initialisées à l'arrivée (sessions, quêtes du jour, semaine, accueil) : leur réplication
-- est groupée au prochain passage lent de step (≤ 1 s) plutôt qu'envoyée dans un patch séparé
-- juste après l'instantané d'arrivée
local pendingDirty: { [Player]: { [string]: boolean } } = {}

type Mark = (player: Player, key: string) -> ()

local function markLater(player: Player, key: string)
	local keys = pendingDirty[player]
	if keys == nil then
		keys = {}
		pendingDirty[player] = keys
	end
	keys[key] = true
end

local function flushPending(player: Player)
	local keys = pendingDirty[player]
	if keys == nil then
		return
	end
	pendingDirty[player] = nil
	for key in keys do
		DataService.markDirty(player, key)
	end
end

type Measures = { [string]: QuestLogic.Measure }

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function num(x: unknown, default: number): number
	if type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge then
		return x
	end
	return default
end

local function sub(data: { [string]: any }, key: string): { [string]: any }
	local t = data[key]
	if type(t) ~= "table" then
		t = {}
		data[key] = t
	end
	return t
end

-- Répare les clés possédées si une sauvegarde est corrompue (types attendus du schéma v1)
local function normalize(data: { [string]: any })
	local ob = sub(data, "onboarding")
	ob.step = math.clamp(math.floor(num(ob.step, 0)), 0, ONBOARDING_DONE)
	ob.p = math.max(0, num(ob.p, 0))
	local daily = sub(data, "daily")
	daily.day = math.floor(num(daily.day, 0))
	daily.step = math.clamp(math.floor(num(daily.step, 1)), 1, #Quests.Calendar)
	local quests = sub(data, "quests")
	quests.day = math.floor(num(quests.day, 0))
	if type(quests.list) ~= "table" then
		quests.list = {}
	end
	quests.rerolls = math.max(0, math.floor(num(quests.rerolls, 0)))
	quests.starClaimed = quests.starClaimed == true
	local weekly = sub(data, "weekly")
	weekly.week = math.floor(num(weekly.week, 0))
	weekly.banked = math.max(0, num(weekly.banked, 0))
	weekly.claimed = weekly.claimed == true
	local rookie = sub(data, "rookie")
	rookie.sessions = math.max(0, math.floor(num(rookie.sessions, 0)))
	rookie.playSeconds = math.max(0, num(rookie.playSeconds, 0))
	rookie.done = rookie.done == true
	local stats = sub(data, "stats")
	for k, v in stats do
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			stats[k] = 0
		end
	end
	sub(data, "codes")
end

local function funnel(player: Player, step: number, name: string?)
	local label = name or FUNNEL_NAME[step]
	if label then
		Analytics.funnel(player, step, label)
	end
end

local function supernovasOf(data: { [string]: any }): number
	return math.max(0, math.floor(num(data.supernovas, 0)))
end

-- ---------------------------------------------------------------------------------------------
-- Statistiques et titres
-- ---------------------------------------------------------------------------------------------

local function checkTitles(player: Player, data: { [string]: any }, statKey: string)
	local value = num(data.stats[statKey], 0)
	local unlocks = data.unlocks
	local titles = if type(unlocks) == "table" and type(unlocks.titles) == "table"
		then unlocks.titles
		else nil
	for id, def in Cosmetics.Titles do
		local source = def.source
		if source.kind == "stat" and source.stat == statKey and value >= (source.n or math.huge) then
			if not (titles and titles[id] == true) then
				Safe.call(TAG .. ".unlockTitle", NestService.unlock, player, "titles", id)
			end
		end
	end
end

local function addStat(player: Player, data: { [string]: any }, key: string, amount: number)
	if amount == 0 or amount ~= amount then
		return
	end
	local stats = data.stats
	stats[key] = num(stats[key], 0) + amount
	DataService.markDirty(player, "stats")
	checkTitles(player, data, key)
end

local function maxStat(player: Player, data: { [string]: any }, key: string, value: number)
	local stats = data.stats
	if value > num(stats[key], 0) then
		stats[key] = value
		DataService.markDirty(player, "stats")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Récompenses
-- ---------------------------------------------------------------------------------------------

type Granted = { glow: number, stardust: number, boostSeconds: number?, code: number? }

-- Applique une récompense (Config/Quests.Reward ou Data/Codes.CodeReward) ; chaque effet est
-- protégé : un échec n'empêche pas les autres. `quietBoost` : l'appelant annonce lui-même le boost
-- (Celebrate « dailyClaimed » porte boostSeconds, que le client affiche déjà en toast)
local function grantReward(
	player: Player,
	reward: { [string]: any },
	sku: string,
	txType: string?,
	source: string,
	quietBoost: boolean?
): Granted
	local out: Granted = { glow = 0, stardust = 0 }
	local glow = reward.glow
	if type(glow) == "number" and glow > 0 then
		out.glow += Safe.value(TAG .. ".glow", 0, EconomyService.addGlow, player, glow, sku, txType)
	end
	local idle = reward.idleSeconds
	if type(idle) == "number" and idle > 0 then
		out.glow += Safe.value(
			TAG .. ".glowSeconds",
			0,
			EconomyService.addGlowSeconds,
			player,
			idle,
			sku,
			reward.minGlow
		)
	end
	local dust = reward.stardust
	if type(dust) == "number" and dust > 0 then
		out.stardust += Safe.value(
			TAG .. ".stardust",
			0,
			EconomyService.addStardust,
			player,
			dust,
			sku,
			txType
		)
	end
	local boost = reward.boostSeconds
	if type(boost) == "number" and boost > 0 then
		if Safe.call(TAG .. ".boost", EconomyService.grantPersonalBoost, player, boost) then
			out.boostSeconds = boost
			if not quietBoost then
				Notify.feedback(player, "feedback.boostOn", { minutes = math.ceil(boost / 60) }, "reward")
			end
		end
	end
	local species: number? = nil
	if type(reward.species) == "number" then
		species = reward.species
	elseif type(reward.rotation) == "string" then
		local ok, s = Safe.call(TAG .. ".rotation", EventClock.rotation, reward.rotation, Clock.week())
		if ok and type(s) == "number" then
			species = s
		end
	end
	if species ~= nil and Nebbies.isSpeciesEnabled(species) then
		local code = Nebbies.pack(species, 0, 0)
		if Safe.call(TAG .. ".nebby", AtlasService.addNebbies, player, { code }, source) then
			out.code = code
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Jour, semaine
-- ---------------------------------------------------------------------------------------------

local function crewRecentFor(data: { [string]: any }, day: number): boolean
	return QuestLogic.crewRecent(num(data.stats.lastCrewDay, 0), day)
end

local function isZen(player: Player): boolean
	return Safe.value(TAG .. ".isZen", false, NestService.isZen, player)
end

-- Nouvelles quêtes du jour au premier accès du jour UTC
local function refreshDay(player: Player, data: { [string]: any }, day: number, mark: Mark?)
	local quests = data.quests
	if quests.day == day then
		return
	end
	local ids = QuestLogic.drawDaily(player.UserId, day, isZen(player), crewRecentFor(data, day))
	local list = {}
	for _, id in ids do
		table.insert(list, { id = id, p = 0, done = false, claimed = false })
	end
	quests.day = day
	quests.list = list
	quests.rerolls = 0
	quests.starClaimed = false
	local markFn: Mark = mark or DataService.markDirty
	markFn(player, "quests")
end

-- Grand Défilé : remise à zéro le lundi 00:00 UTC
local function refreshWeek(player: Player, data: { [string]: any }, week: number, mark: Mark?)
	local weekly = data.weekly
	if weekly.week == week then
		return
	end
	weekly.week = week
	weekly.banked = 0
	weekly.claimed = false
	local markFn: Mark = mark or DataService.markDirty
	markFn(player, "weekly")
end

-- ---------------------------------------------------------------------------------------------
-- Bouclier débutant (§4.16)
-- ---------------------------------------------------------------------------------------------

local function playSecondsOf(data: { [string]: any }, s: Session?): number
	return num(data.rookie.playSeconds, 0) + (if s then s.playAcc else 0)
end

local function eligibleNow(data: { [string]: any }, s: Session?): boolean
	return Formulas.rookieEligible(num(data.rookie.sessions, 0), playSecondsOf(data, s), supernovasOf(data))
end

local function endShield(player: Player, data: { [string]: any }, s: Session?)
	local rookie = data.rookie
	if rookie.done then
		return
	end
	rookie.done = true
	if s then
		s.rookieDue = false
	end
	DataService.markDirty(player, "rookie")
	player:SetAttribute("Rookie", false)
	Notify.personalBanner(player, "rookieEnd", {})
	Notify.celebrate(player, "rookieEnd", {})
	Signals.RookieEnded:Fire(player)
	Analytics.event(player, "RookieShieldEnded", math.floor(playSecondsOf(data, s) / 60))
end

-- Le bouclier n'est plus mérité : fin tout de suite si la file est vide, sinon au prochain moment sûr
local function checkRookie(player: Player, data: { [string]: any }, s: Session)
	if data.rookie.done or eligibleNow(data, s) then
		return
	end
	if s.lineLen <= 0 then
		endShield(player, data, s)
	else
		s.rookieDue = true
	end
end

-- ---------------------------------------------------------------------------------------------
-- Temps de jeu
-- ---------------------------------------------------------------------------------------------

local function flushPlay(player: Player, data: { [string]: any }, s: Session)
	local whole = math.floor(s.playAcc)
	if whole <= 0 then
		return
	end
	s.playAcc -= whole
	data.stats.playSeconds = num(data.stats.playSeconds, 0) + whole
	data.rookie.playSeconds = num(data.rookie.playSeconds, 0) + whole
	DataService.markDirty(player, "stats")
	DataService.markDirty(player, "rookie")
end

-- ---------------------------------------------------------------------------------------------
-- Session
-- ---------------------------------------------------------------------------------------------

-- Session courante (créée au premier besoin après le chargement du profil : sessions + 1)
local function ensureSession(player: Player): (Session?, { [string]: any }?)
	local data = DataService.get(player)
	if data == nil then
		return nil, nil
	end
	local s = sessions[player]
	if s ~= nil and s.data == data then
		-- session ouverte : valable jusqu'à son nettoyage, même pendant le départ (la progression
		-- accordée par la sauvegarde de départ, ex. dernier port de Comète, est bien écrite)
		return s, data
	end
	if player.Parent == nil or departed[player] then
		return nil, nil
	end
	normalize(data)
	local now = Clock.now()
	data.rookie.sessions += 1
	data.stats.sessions = num(data.stats.sessions, 0) + 1
	markLater(player, "rookie")
	markLater(player, "stats")
	local session: Session = {
		data = data,
		joinedAt = now,
		lastTick = now,
		playAcc = 0,
		lastFlush = now,
		firstSession = math.max(data.stats.sessions, data.rookie.sessions) <= 1,
		lineLen = 0,
		rookieDue = false,
		day = Clock.day(now),
		week = Clock.week(now),
		ready = false,
	}
	sessions[player] = session
	refreshDay(player, data, session.day, markLater)
	refreshWeek(player, data, session.week, markLater)
	player:SetAttribute("Rookie", not data.rookie.done)
	checkRookie(player, data, session)
	return session, data
end

-- ---------------------------------------------------------------------------------------------
-- Progression
-- ---------------------------------------------------------------------------------------------

local onQuestStart: (player: Player, data: { [string]: any }, s: Session) -> ()

local function completeOnboarding(player: Player, data: { [string]: any }, s: Session, index: number)
	local def = Quests.Onboarding[index]
	local ob = data.onboarding
	ob.step = index + 1
	ob.p = 0
	DataService.markDirty(player, "onboarding")
	local granted = grantReward(player, def.reward :: any, "Quest_" .. def.id, "Onboarding", "quest")
	Notify.celebrate(player, "questDone", { kind = "onboarding", slot = 1, id = def.id })
	Notify.celebrate(player, "questClaimed", {
		kind = "onboarding",
		slot = 1,
		glow = granted.glow,
		stardust = granted.stardust,
	})
	if def.funnel then
		funnel(player, def.funnel, def.funnelName)
	end
	if index == DIRECTED_UNTIL then
		Safe.call(TAG .. ".setDirected", SpawnService.setDirected, player, false)
	end
	onQuestStart(player, data, s)
end

-- Fait avancer la quête d'accueil en cours, les quêtes du jour et la quête hebdomadaire
local function progress(player: Player, data: { [string]: any }, s: Session, measures: Measures)
	-- accueil (une quête à la fois)
	local ob = data.onboarding
	local def = Quests.Onboarding[ob.step]
	if def ~= nil then
		local measure = measures[def.goal.kind]
		if measure then
			local mode, value = measure(def.goal)
			local p = QuestLogic.apply(def.goal, num(ob.p, 0), mode, value)
			if p ~= ob.p then
				ob.p = p
				DataService.markDirty(player, "onboarding")
				if p >= def.goal.n then
					completeOnboarding(player, data, s, ob.step)
				end
			end
		end
	end
	-- quêtes du jour
	local quests = data.quests
	local changed = false
	for slot, entry in quests.list do
		local q = if type(entry) == "table" then QuestLogic.dailyById[entry.id] else nil
		if q ~= nil and entry.done ~= true then
			local measure = measures[q.goal.kind]
			if measure then
				local mode, value = measure(q.goal)
				local p = QuestLogic.apply(q.goal, num(entry.p, 0), mode, value)
				if p ~= entry.p then
					entry.p = p
					changed = true
					if p >= q.goal.n then
						entry.p = q.goal.n
						entry.done = true
						Notify.celebrate(player, "questDone", { kind = "daily", slot = slot, id = q.id })
					end
				end
			end
		end
	end
	if changed then
		DataService.markDirty(player, "quests")
	end
	-- Grand Défilé
	local goal = Quests.Weekly.goal
	local measure = measures[goal.kind]
	if measure then
		local weekly = data.weekly
		local before = num(weekly.banked, 0)
		local mode, value = measure(goal)
		local after = if mode == "add" then QuestLogic.apply(goal, before, mode, value) else before
		if after ~= before then
			weekly.banked = after
			DataService.markDirty(player, "weekly")
			if before < goal.n and after >= goal.n then
				Notify.celebrate(player, "questDone", { kind = "weekly", slot = 1, id = Quests.Weekly.id })
			end
		end
	end
end

-- Début d'une quête d'accueil : Rare garanti (Q4), objectifs d'état déjà atteints (perchoirs)
onQuestStart = function(player: Player, data: { [string]: any }, s: Session)
	local ob = data.onboarding
	local def = Quests.Onboarding[ob.step]
	if def == nil then
		return
	end
	if ob.step == GUARANTEED_RARE_AT and ob.p == 0 then
		Safe.call(TAG .. ".guaranteedRare", SpawnService.spawnGuaranteedRare, player)
	end
	if def.goal.kind == "perches" then
		local count = Safe.value(TAG .. ".perchCount", 0, AtlasService.perchCount, player)
		progress(player, data, s, {
			perches = function()
				return "set", count
			end,
		})
	end
end

local function add(n: number): QuestLogic.Measure
	return function()
		return "add", n
	end
end

-- ---------------------------------------------------------------------------------------------
-- Signaux (docs §7)
-- ---------------------------------------------------------------------------------------------

local function withSession(player: unknown, fn: (Player, { [string]: any }, Session) -> ())
	if typeof(player) ~= "Instance" or not (player :: Instance):IsA("Player") then
		return
	end
	local p = player :: Player
	local s, data = ensureSession(p)
	if s == nil or data == nil then
		return
	end
	fn(p, data, s)
end

local function onPlayerReady(player: Player)
	withSession(player, function(p, data, s)
		-- une fois par session : le rattrapage du Start et le signal peuvent tous deux arriver
		if s.ready then
			return
		end
		s.ready = true
		if s.firstSession then
			funnel(p, 1)
		end
		local ob = data.onboarding
		if ob.step == 0 then
			ob.step = 1
			ob.p = 0
			markLater(p, "onboarding")
			Safe.call(TAG .. ".spawnWelcome", SpawnService.spawnWelcome, p)
			Safe.call(TAG .. ".setDirected", SpawnService.setDirected, p, true)
			onQuestStart(p, data, s)
		elseif ob.step >= 1 and ob.step <= DIRECTED_UNTIL then
			Safe.call(TAG .. ".setDirected", SpawnService.setDirected, p, true)
		end
		if
			ob.step >= 1
			and ob.step < ONBOARDING_DONE
			and Quests.Onboarding[ob.step].goal.kind == "perches"
		then
			onQuestStart(p, data, s)
		end
	end)
end

local function onCaught(player: Player, info: Types.CatchInfo)
	if type(info) ~= "table" or not Nebbies.isValidCode(info.code) then
		return
	end
	withSession(player, function(p, data, s)
		local first = num(data.stats.catches, 0) == 0
		addStat(p, data, "catches", 1)
		if first and s.firstSession then
			funnel(p, 2)
		end
		local _, f = Nebbies.unpack(info.code)
		local rarity = num(info.rarity, 0)
		local weatherForm = f ~= 0
		progress(p, data, s, {
			catch = add(1),
			catchRarity = function(goal)
				if rarity >= (goal.minRarity or 0) then
					return "add", 1
				end
				return nil, nil
			end,
			catchWeather = if weatherForm then add(1) else nil,
			weatherOrComet = if weatherForm then add(1) else nil,
			catchZone = function(goal)
				if goal.zone ~= nil and info.zone == goal.zone then
					return "add", 1
				end
				return nil, nil
			end,
		})
	end)
end

local function onParade(player: Player, info: Types.ParadeInfo)
	-- une parade vide ne compte pas (ni statistique, ni « Fais 5 parades »)
	if type(info) ~= "table" or not Validate.integer(info.count, 1) then
		return
	end
	withSession(player, function(p, data, s)
		local count = info.count
		local first = num(data.stats.parades, 0) == 0
		addStat(p, data, "parades", 1)
		maxStat(p, data, "longestParade", count)
		if first and s.firstSession then
			funnel(p, 3)
		end
		local codes = if type(info.codes) == "table" then info.codes else {}
		local idle = math.floor(num(info.idleSeconds, 0))
		progress(p, data, s, {
			parades = add(1),
			paradeSize = function()
				return "best", count
			end,
			paradeIdle = function()
				return "best", idle
			end,
			bankCount = add(count),
			bankRarity = function(goal)
				local k = 0
				for _, code in codes do
					if Nebbies.isValidCode(code) then
						local sp = Nebbies.unpack(code)
						if Nebbies.rarityOf(sp) >= (goal.minRarity or 0) then
							k += 1
						end
					end
				end
				return "add", k
			end,
			beaconFeed = if info.atBeacon == true then add(count) else nil,
		})
	end)
end

local function onUpgradeBought(player: Player, track: string, _level: number)
	withSession(player, function(p, data, s)
		if s.firstSession then
			funnel(p, 4)
		end
		progress(p, data, s, {
			upgrades = add(1),
			upgrade = function(goal)
				if goal.track == track then
					return "add", 1
				end
				return nil, nil
			end,
		})
	end)
end

local function onSnipped(info: Types.SnipInfo)
	if type(info) ~= "table" or not Validate.integer(info.count, 1) then
		return
	end
	local count = info.count
	if info.snipper ~= nil then
		withSession(info.snipper, function(p, data, s)
			addStat(p, data, "snipsDealt", 1)
			addStat(p, data, "nebbiesSnipped", count)
			progress(p, data, s, { snipNebbies = add(count) })
		end)
	end
	withSession(info.victim, function(p, data)
		addStat(p, data, "snipsTaken", 1)
	end)
end

local function onSupernova(player: Player, newR: number)
	withSession(player, function(p, data, s)
		if newR == 1 then
			funnel(p, 10)
		end
		checkRookie(p, data, s)
	end)
end

-- Passage en Zen : les quêtes JcJ non terminées sont remplacées (sans coûter de relance)
local function onSettingChanged(player: Player, key: string, value: any)
	if key ~= "zen" or value ~= true then
		return
	end
	withSession(player, function(p, data)
		local quests = data.quests
		local day = quests.day
		local exclude: { [number]: boolean } = {}
		for _, entry in quests.list do
			if type(entry) == "table" then
				exclude[entry.id] = true
			end
		end
		local changed = false
		for slot, entry in quests.list do
			local q = if type(entry) == "table" then QuestLogic.dailyById[entry.id] else nil
			if q ~= nil and q.pvp and entry.done ~= true then
				local id =
					QuestLogic.zenReplacement(p.UserId, day, slot, q.tier, exclude, crewRecentFor(data, day))
				if id ~= nil then
					exclude[id] = true
					quests.list[slot] = { id = id, p = 0, done = false, claimed = false }
					changed = true
				end
			end
		end
		if changed then
			DataService.markDirty(p, "quests")
		end
	end)
end

local function connectSignals()
	Signals.PlayerReady:Connect(onPlayerReady)
	Signals.Caught:Connect(onCaught)
	Signals.Parade:Connect(onParade)
	Signals.UpgradeBought:Connect(onUpgradeBought)
	Signals.Snipped:Connect(onSnipped)
	Signals.Supernova:Connect(onSupernova)
	Signals.SettingChanged:Connect(onSettingChanged)
	Signals.LineChanged:Connect(function(player: Player, n: number)
		local s = sessions[player]
		if s ~= nil and Validate.finiteNumber(n) then
			s.lineLen = n
		end
	end)
	Signals.Dashed:Connect(function(player: Player)
		withSession(player, function(p, data, s)
			progress(p, data, s, { dash = add(1) })
		end)
	end)
	Signals.EscortTime:Connect(function(player: Player, seconds: number)
		if not Validate.finiteNumber(seconds) or seconds <= 0 then
			return
		end
		withSession(player, function(p, data, s)
			addStat(p, data, "escortSeconds", seconds)
			progress(p, data, s, { escort = add(seconds) })
		end)
	end)
	Signals.IdleSettled:Connect(function(player: Player, _glow: number, seconds: number)
		if not Validate.finiteNumber(seconds) or seconds <= 0 then
			return
		end
		withSession(player, function(p, data, s)
			progress(p, data, s, { idle = add(seconds) })
		end)
	end)
	Signals.PerchesChanged:Connect(function(player: Player, count: number)
		if not Validate.finiteNumber(count) then
			return
		end
		withSession(player, function(p, data, s)
			progress(p, data, s, {
				perches = function()
					return "set", count
				end,
			})
		end)
	end)
	Signals.AtlasEntry:Connect(function(player: Player)
		withSession(player, function(p, data, s)
			progress(p, data, s, { atlasNew = add(1) })
		end)
	end)
	Signals.Fused:Connect(function(player: Player)
		withSession(player, function(p, data, s)
			addStat(p, data, "fusions", 1)
			progress(p, data, s, { fusions = add(1) })
		end)
	end)
	Signals.CometParticipation:Connect(function(player: Player)
		withSession(player, function(p, data, s)
			progress(p, data, s, { cometParticipate = add(1), weatherOrComet = add(1) })
		end)
	end)
	Signals.CometHeld:Connect(function(player: Player, seconds: number)
		if not Validate.finiteNumber(seconds) then
			return
		end
		withSession(player, function(p, data, s)
			addStat(p, data, "cometsHeld", 1)
			progress(p, data, s, { cometHold = add(seconds) })
		end)
	end)
	Signals.CometEvent:Connect(function(sig: Types.CometSignal)
		if type(sig) == "table" and sig.kind == "bank" and sig.player ~= nil then
			withSession(sig.player, function(p, data)
				addStat(p, data, "cometsBanked", 1)
			end)
		end
	end)
	Signals.WispPopped:Connect(function(player: Player)
		withSession(player, function(p, data, s)
			addStat(p, data, "wispsPopped", 1)
			progress(p, data, s, { wispPop = add(1) })
		end)
	end)
	Signals.BeaconResult:Connect(function(success: boolean, contributors: { Player })
		if success ~= true or type(contributors) ~= "table" then
			return
		end
		for _, player in contributors do
			withSession(player, function(p, data, s)
				addStat(p, data, "beaconWins", 1)
				progress(p, data, s, { beaconWin = add(1) })
			end)
		end
	end)
	Signals.Cheered:Connect(function(cheerer: Player, hero: Player)
		withSession(cheerer, function(p, data, s)
			addStat(p, data, "cheersGiven", 1)
			progress(p, data, s, { cheers = add(1) })
		end)
		withSession(hero, function(p, data)
			addStat(p, data, "cheersReceived", 1)
		end)
	end)
	Signals.CrewChanged:Connect(function(players: { Player })
		if type(players) ~= "table" then
			return
		end
		for _, player in players do
			withSession(player, function(p, data)
				if Safe.value(TAG .. ".crewOf", 0, CrewService.crewOf, p) ~= 0 then
					local today = Clock.day()
					if num(data.stats.lastCrewDay, 0) ~= today then
						data.stats.lastCrewDay = today
						DataService.markDirty(p, "stats")
					end
				end
			end)
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------------

local function claimDailyQuest(player: Player, data: { [string]: any }, slot: number)
	local quests = data.quests
	local entry = quests.list[slot]
	local q = if type(entry) == "table" then QuestLogic.dailyById[entry.id] else nil
	if q == nil then
		return
	end
	if entry.claimed == true then
		Notify.feedback(player, "feedback.alreadyClaimed", nil, "info")
		return
	end
	if entry.done ~= true then
		Notify.feedback(player, "feedback.questNotDone", nil, "info")
		return
	end
	entry.claimed = true
	DataService.markDirty(player, "quests")
	local reward = Quests.DailyTiers[q.tier] or {}
	local granted = grantReward(player, reward :: any, "Quest_" .. tostring(q.id), nil, "quest")
	Notify.celebrate(player, "questClaimed", {
		kind = "daily",
		slot = slot,
		glow = granted.glow,
		stardust = granted.stardust,
	})
	-- « Étoile du jour » : les 3 quêtes réclamées
	if quests.starClaimed ~= true and #quests.list >= DAILY_SLOTS then
		for _, other in quests.list do
			if type(other) ~= "table" or other.claimed ~= true then
				return
			end
		end
		quests.starClaimed = true
		DataService.markDirty(player, "quests")
		grantReward(player, Quests.DailyStar :: any, "Quest_DailyStar", nil, "quest")
	end
end

local function claimWeekly(player: Player, data: { [string]: any })
	local weekly = data.weekly
	if weekly.claimed == true then
		Notify.feedback(player, "feedback.alreadyClaimed", nil, "info")
		return
	end
	if num(weekly.banked, 0) < Quests.Weekly.goal.n then
		Notify.feedback(player, "feedback.questNotDone", nil, "info")
		return
	end
	weekly.claimed = true
	DataService.markDirty(player, "weekly")
	local granted =
		grantReward(player, Quests.Weekly.reward :: any, "Quest_" .. Quests.Weekly.id, nil, "quest")
	Notify.celebrate(player, "questClaimed", {
		kind = "weekly",
		slot = 1,
		glow = granted.glow,
		stardust = granted.stardust,
		code = granted.code,
	})
end

local function onClaimQuest(player: Player, kind: unknown, slot: unknown)
	if not RateLimit.allow(player, "ClaimQuest", RATE.claimQuest.n, RATE.claimQuest.per) then
		return
	end
	if kind ~= "daily" and kind ~= "weekly" and kind ~= "onboarding" then
		return
	end
	local maxSlot = if kind == "daily" then DAILY_SLOTS else 1
	if not Validate.integer(slot, 1, maxSlot) then
		return
	end
	local s, data = ensureSession(player)
	if s == nil or data == nil then
		return
	end
	local now = Clock.now()
	refreshDay(player, data, Clock.day(now))
	refreshWeek(player, data, Clock.week(now))
	if kind == "daily" then
		claimDailyQuest(player, data, slot :: number)
	elseif kind == "weekly" then
		claimWeekly(player, data)
	else
		-- récompenses d'accueil automatiques : rien n'est jamais dû (docs §16.4)
		local step = data.onboarding.step
		Notify.feedback(
			player,
			if step > 1 then "feedback.alreadyClaimed" else "feedback.questNotDone",
			nil,
			"info"
		)
	end
end

local function onRerollQuest(player: Player, slot: unknown)
	if not RateLimit.allow(player, "RerollQuest", RATE.reroll.n, RATE.reroll.per) then
		return
	end
	if not Validate.integer(slot, 1, DAILY_SLOTS) then
		return
	end
	local s, data = ensureSession(player)
	if s == nil or data == nil then
		return
	end
	local day = Clock.day()
	refreshDay(player, data, day)
	local quests = data.quests
	local index = slot :: number
	local entry = quests.list[index]
	local q = if type(entry) == "table" then QuestLogic.dailyById[entry.id] else nil
	if q == nil or entry.done == true then
		return
	end
	local allowed = Quests.Rerolls.Free
	if Safe.value(TAG .. ".ownsPass", false, MonetizationService.ownsPass, player, "VIPStar") then
		allowed += Quests.Rerolls.VIP
	end
	if quests.rerolls >= allowed then
		Notify.feedback(player, "feedback.noReroll", nil, "info")
		return
	end
	local exclude: { [number]: boolean } = {}
	for _, other in quests.list do
		if type(other) == "table" then
			exclude[other.id] = true
		end
	end
	local id = QuestLogic.reroll(
		player.UserId,
		day,
		quests.rerolls,
		index,
		q.tier,
		exclude,
		isZen(player),
		crewRecentFor(data, day)
	)
	if id == nil then
		Notify.feedback(player, "feedback.noReroll", nil, "info")
		return
	end
	quests.rerolls += 1
	quests.list[index] = { id = id, p = 0, done = false, claimed = false }
	DataService.markDirty(player, "quests")
end

local function onClaimDaily(player: Player)
	if not RateLimit.allow(player, "ClaimDaily", RATE.claimDaily.n, RATE.claimDaily.per) then
		return
	end
	local s, data = ensureSession(player)
	if s == nil or data == nil then
		return
	end
	local today = Clock.day()
	local daily = data.daily
	if daily.day == today then
		Notify.feedback(player, "feedback.dailyAlready", nil, "info")
		return
	end
	local step = math.clamp(math.floor(num(daily.step, 1)), 1, #Quests.Calendar)
	-- mutation d'abord (jamais de double réclamation, même si une récompense échoue)
	daily.day = today
	daily.step = step % #Quests.Calendar + 1
	DataService.markDirty(player, "daily")
	-- boost annoncé par la célébration (un seul toast « Glow ×2 », pas deux)
	local granted =
		grantReward(player, Quests.Calendar[step] :: any, "Login_D" .. tostring(step), nil, "login", true)
	Notify.celebrate(player, "dailyClaimed", {
		day = step,
		glow = if granted.glow > 0 then granted.glow else nil,
		stardust = if granted.stardust > 0 then granted.stardust else nil,
		boostSeconds = granted.boostSeconds,
		code = granted.code,
	})
end

local function onRedeemCode(player: Player, code: unknown): string
	if not RateLimit.allow(player, "RedeemCode", RATE.redeem.n, RATE.redeem.per) then
		return "busy"
	end
	if not RateLimit.allow(player, "RedeemCodeHour", RATE.redeemHour.n, RATE.redeemHour.per) then
		return "busy"
	end
	if type(code) ~= "string" then
		return "invalid"
	end
	return QuestService.redeem(player, code)
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

local function onLoaded(player: Player)
	ensureSession(player)
end

local function closeSession(player: Player)
	local s = sessions[player]
	pendingDirty[player] = nil
	if s == nil then
		return
	end
	sessions[player] = nil
	s.playAcc += math.clamp(Clock.now() - s.lastTick, 0, Tuning.MaxStepGap)
	flushPlay(player, s.data, s)
	Analytics.event(player, "SessionLength", math.floor((Clock.now() - s.joinedAt) / 60))
end

local function onPlayerRemoving(player: Player)
	departed[player] = true
	-- Nettoyage différé : Roblox ne garantit pas l'ordre des connexions PlayerRemoving ; les autres
	-- (sauvegarde de départ de DataService et ses crochets, CongaService, EventService) trouvent
	-- encore la session et leur progression de départ est écrite, sans session fantôme
	if sessions[player] ~= nil then
		task.defer(closeSession, player)
	else
		pendingDirty[player] = nil
	end
end

-- Registre du cadeau Starfall Saturday (clé stats, dont ce service est propriétaire) : marque le
-- profil AVANT la remise ; false si ce compte a déjà reçu le Starborn garanti de ce show
local function claimStarfallGift(player: Player, showId: number): boolean
	local data = DataService.get(player)
	if data == nil or not Validate.finiteNumber(showId) then
		return false
	end
	local stats = data.stats
	if type(stats) ~= "table" then
		return false
	end
	if num(stats.starfallGift, 0) >= showId then
		return false
	end
	stats.starfallGift = showId
	DataService.markDirty(player, "stats")
	return true
end

function QuestService.Init()
	EventService.setStarfallClaim(claimStarfallGift)
	-- La sauvegarde de départ (DataService, branché avant nous) copie le profil AVANT notre propre
	-- PlayerRemoving : le temps écoulé depuis le dernier passage de step est donc compté ici
	DataService.onBeforeSave(function(player: Player, data: { [string]: any })
		local s = sessions[player]
		if s ~= nil and s.data == data then
			local now = Clock.now()
			s.playAcc += math.clamp(now - s.lastTick, 0, Tuning.MaxStepGap)
			s.lastTick = now
			flushPlay(player, data, s)
		end
	end)
end

function QuestService.Start()
	DataService.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	connectSignals()
	-- PlayerReady a pu partir pendant le Start() d'un service précédent (NestService : profil chargé
	-- sans yield, ex. magasin en mémoire de Studio) : rattrapage des joueurs déjà prêts
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) and NestService.slotOf(player) ~= 0 then
			task.spawn(onPlayerReady, player)
		end
	end
	Net.event("ClaimDaily").OnServerEvent:Connect(onClaimDaily)
	Net.event("ClaimQuest").OnServerEvent:Connect(onClaimQuest)
	Net.event("RerollQuest").OnServerEvent:Connect(onRerollQuest)
	Net.func("RedeemCode").OnServerInvoke = onRedeemCode
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Temps de jeu, fin de bouclier différée, changement de jour UTC (travail une fois par seconde)
function QuestService.step(now: number)
	if not Validate.finiteNumber(now) then
		return
	end
	if lastSlowAt > 0 and now - lastSlowAt < Tuning.SlowStepInterval then
		return
	end
	lastSlowAt = now
	local day = Clock.day(now)
	local week = Clock.week(now)
	for player, s in sessions do
		local data = DataService.get(player)
		if player.Parent ~= nil and data ~= nil and data == s.data then
			s.playAcc += math.clamp(now - s.lastTick, 0, Tuning.MaxStepGap)
			s.lastTick = now
			if now - s.lastFlush >= Tuning.PlayFlushInterval then
				s.lastFlush = now
				flushPlay(player, data, s)
			end
			if s.day ~= day then
				s.day = day
				refreshDay(player, data, day)
			end
			if s.week ~= week then
				s.week = week
				refreshWeek(player, data, week)
			end
			checkRookie(player, data, s)
			flushPending(player)
		end
	end
	-- joueurs partis entre-temps : rien à répliquer
	for player in pendingDirty do
		if sessions[player] == nil then
			pendingDirty[player] = nil
		end
	end
end

-- Bouclier débutant actif (file incoupable, coupes sans Stardust)
function QuestService.isRookie(player: Player): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	local rookie = data.rookie
	return type(rookie) == "table" and rookie.done ~= true
end

-- Moment sûr (parade ou file vide) : termine le bouclier si sa fin est due
function QuestService.onSafeMoment(player: Player)
	local s = sessions[player]
	local data = DataService.get(player)
	if s == nil or data == nil or data ~= s.data or data.rookie.done then
		return
	end
	if s.rookieDue or not eligibleNow(data, s) then
		endShield(player, data, s)
	end
end

-- Étape d'accueil courante (0 pas commencé, 1-7, 8 terminé)
function QuestService.onboardingStep(player: Player): number
	local data = DataService.get(player)
	if data == nil or type(data.onboarding) ~= "table" then
		return 0
	end
	return math.clamp(math.floor(num(data.onboarding.step, 0)), 0, ONBOARDING_DONE)
end

-- Ids des 3 quêtes du jour (tirage déterministe, avant relances)
function QuestService.drawDaily(userId: number, day: number, zen: boolean, crewRecent: boolean): { number }
	return QuestLogic.drawDaily(userId, day, zen == true, crewRecent == true)
end

-- Applique un code ; retourne le statut "ok" | "invalid" | "expired" | "used" | "busy"
function QuestService.redeem(player: Player, code: string): string
	if type(code) ~= "string" or #code == 0 or #code > Tuning.CodeMaxLength then
		return "invalid"
	end
	local key = string.upper(code)
	if string.match(key, "^[A-Z0-9]+$") == nil then
		return "invalid"
	end
	local data = DataService.get(player)
	if data == nil or player.Parent == nil then
		return "busy"
	end
	normalize(data)
	local def = Codes[key]
	if def == nil then
		return "invalid"
	end
	if Clock.unix() > def.expires then
		return "expired"
	end
	if data.codes[key] == true then
		return "used"
	end
	data.codes[key] = true -- une fois par compte (mutation avant les récompenses)
	DataService.markDirty(player, "codes")
	grantReward(player, def.reward :: any, "Code_" .. key, nil, "code")
	return "ok"
end

return QuestService
