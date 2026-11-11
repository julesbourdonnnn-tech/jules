--!strict
-- QuestService (paquet meta, docs/04 §11.7) — accueil, objectifs, Nourrir Plop, Squishydex,
-- statistiques (GDD §3, §4.17, §4.20, §7.3, §7.4, §16.1).
--   * Accueil : étapes de Config/Quests.Onboarding.Steps (la plus haute atteinte est gardée,
--     onboarding.step ; aucune étape ne bloque) ; chaque étape → Signals.OnboardingStep, Celebrate
--     « onboarding » { step, hint de la suivante }, Analytics.funnel ; consigne ouverte 90 s au plus
--     (état « onboardingStep ») ; naissances scriptées (Plop de départ à l'étape 1, jumeau à 0:40, premier
--     tirage à 2:45) jamais rejouées au retour ; étape 9 à la première balade, étape 10 à
--     UiSeen("objectives") (carte des objectifs envoyée à 5:00 de jeu).
--   * Temps de jeu : stats.playSeconds += dt dans step (lu par le bouclier, la carte du choix, la Cuve).
--   * Objectifs du jour : tirage à la première connexion du jour (QuestRules.draw), progression par les
--     signaux (QuestRules.apply), réclamation en secondes de revenu (aucun boost, itemSku
--     Objective_<niveau>), relance (1 par jour ; gratuite pour l'objectif 12 si l'ami est parti), les 3
--     réclamés : Goutte chanceuse ; minuit en session : terminés réclamés seuls, en cours gardés jusqu'à
--     la fin de la session, nouveaux objectifs à la connexion suivante (Celebrate « newObjectives »).
--   * Nourrir Plop : FeedPlop(true) à plat ≤ 8 studs du bol (pieds) → maintien de 2 s mesuré ici
--     (HoldState « feed »), annulé par FeedPlop(false) ou la sortie de zone ; une fois par jour UTC :
--     plopDays + 1, palier, boost personnel de 5 min, Signals.Fed, Celebrate « plopDay ».
--   * Squishydex : SquishyObtained → stamp ; nouvelle entrée → Celebrate « dexNew », Signals.Stamped,
--     dex.fam posé (pour toujours) quand une famille est complète, EconomyService.refresh ; jalons
--     réclamés par ClaimDexReward.
--   * Carte « Plop a sommeil » à 60 et 120 min de jeu dans la session ; analytique SessionLength,
--     BoostShare (part de la session en ×2), ObjectivesAllDone, SleepyCardShown, FirstBoopReceived.
--   * v2.0 (lot A4, N23) : MenuActivity (navigation dans un menu) réveille les Plopettes
--     (Activity.noteMenu), interrupteur Helpers ouvert et profil v2 seulement ; ne donne jamais rien.
--   * v2.0 (lot A4, étape 4 ; GDD v2.0 §7.5, §4.27, §4.29 ; docs/04 §27.2, §27.7) — profil v2 seulement,
--     chaque système derrière son interrupteur (coupé : aucun champ lu ni écrit, aucune carte, aucun envoi) :
--     statistiques à vie (stats.upgradesBought sur UpgradeBought, stats.petitSplorches sur
--     PrestigeApplied("petit"), stats.objectivesClaimed à chaque objectif réclamé) ; piste de la semaine
--     [WeeklyTrack] (jeu des 7 derniers jours, période vérifiée au début de la session seulement, 3 Défis
--     tirés par QuestRules.drawChallenges et Meta/ChallengeCtx, 2 points par objectif terminé, 5 par Défi,
--     paliers livrés tout seuls dans l'ordre, chacun réclamé après sa récompense) ; Carnet du Ranch
--     [Carnet] ; cartes « Bienvenue dans la v2 ! » et « Nouveau » et tenues du Record R [RecordR] ; étapes
--     du record à 25 / 50 / 75 % [RecordR] ; jours de givre (season.frostDays) ; puce « Prochain achat »
--     vue (UiSeen("nextBuy") [UpgradesScreen]). N1 : ce qui est débloqué suit le Record R (Prestige.bestR).
--   * v2.0 (lot A4, étape 5 ; GDD v2.0 §4.17 ; D13, D16) [Mastery], profil v2, vue toutes les 10 s et à
--     l'arrivée : maîtrise d'espèce (★5, page dorée, Trophée Cristal : Logic/Owned.mastery) donnée toute
--     seule, +25 Confettis par EconomyService.addConfetti(…, "mastery") ; bit de `mastery` posé seulement
--     si les Confettis sont crédités (sinon nouvel essai), carte Celebrate("mastery", { species }) ;
--     jalons géants : attribut GiantTier du ranch (Owned.giantTier), carte « unlock » quand un
--     cosmétique de taille devient possédé pendant la session. QuestService.onLifetime : crochet des
--     compteurs à vie (CommunityService y revoit la Déco perso).
-- Remotes : FeedPlop, ClaimObjective, RerollObjective, ClaimDexReward, UiSeen, MenuActivity ; HoldState.
-- Clés : firstJoin, codes, dex, plopDays, lastFeedDay, onboarding, objectives, stats ; v2 : carnet,
-- weeklyTrack, unlocksSeen, season (frostDays), mastery.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Quests = require(Shared.Config.Quests)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Features = require(Shared.Config.Features)
local Cosmetics = require(Shared.Config.Cosmetics)
local QuestRules = require(Shared.Logic.QuestRules)
local Prestige = require(Shared.Logic.Prestige)
local Bitset = require(Shared.Logic.Bitset)
local Owned = require(Shared.Logic.Owned)
local Odds = require(Shared.Logic.Odds)
local Hash = require(Shared.Logic.Hash)
local Formulas = require(Shared.Logic.Formulas)
local EventClock = require(Shared.Logic.EventClock)
local ZoneRules = require(Shared.Logic.ZoneRules)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Analytics = require(Server.Util.Analytics)
local MoveCheck = require(Server.Util.MoveCheck)
local Activity = require(Server.Util.Activity)
local Guard = require(Server.Meta.Guard)
local ChallengeCtx = require(Server.Meta.ChallengeCtx)
local MetaAnalytics = require(Server.Meta.MetaAnalytics)
local PadRules = require(Server.Ranch.PadRules)
local DiagnosticsService = require(Server.Services.DiagnosticsService)
local DataService = require(Server.Services.DataService)
local RanchService = require(Server.Services.RanchService)
local EconomyService = require(Server.Services.EconomyService)
local SquishyService = require(Server.Services.SquishyService)

export type OnboardingScript = {
	active: boolean, -- accueil en cours (avant Quests.Onboarding.ScriptUntil)
	runawayAt: number?, -- s de jeu de la première créature en fuite (Mochi Mew)
	demoAt: number?, -- s de jeu de la démonstration de Big Plop
	runawayPaused: boolean, -- fuites en pause (2:45 → 5:00)
	vatScripted: boolean, -- la Cuve suit le script (une goutte toutes les 90 s)
}

local QuestService = {}

local ONB = Quests.Onboarding
local RULES = Quests.ObjectiveRules
local FEED = Quests.Feed
local QUIET_SAFETY = ONB.ScriptUntil + 2 * ONB.StepTimeout -- s de jeu : plus jamais « discret » au-delà
local STATS_DIRTY_EVERY = 10 -- s de jeu : stats.playSeconds répliqué au plus toutes les 10 s
local BOOST_SAMPLE = 1 -- s : échantillonnage du ×2 (BoostShare)
local MAX_DT = 60 -- s : un tick ne compte jamais plus d'une minute de jeu

type Feed = { startedAt: number, endsAt: number }
type Session = {
	ready: boolean,
	readyAt: number,
	last: number,
	play: number, -- s de jeu dans la session
	dirtyAcc: number,
	boostAcc: number,
	boostSeconds: number,
	day: number, -- Clock.day() vu au dernier tick (minuit en session)
	kept: boolean, -- objectifs d'un jour passé gardés jusqu'à la fin de la session
	seen: { [string]: boolean },
	sleepy: { [number]: boolean },
	stepAt: number?, -- consigne en cours ouverte à (état « onboardingStep »)
	feed: Feed?,
	friends: number,
	allDoneLogged: boolean,
	cardSent: boolean,
	starterDue: boolean, -- Plop de départ posé au premier tick (Big Plop arrive, GDD §3 0:00-0:10)
	released: boolean, -- compteurs de session écrits (sauvegarde de départ ou fermeture)
	-- v2.0 (lot A4, étape 4)
	v2: boolean, -- profil v2 (fixé à l'arrivée : la migration n'a lieu qu'au chargement)
	trackReady: boolean, -- période de la piste vérifiée dans cette session (D10)
	trackPending: boolean, -- un palier attend sa récompense (Confettis refusés, D35)
	delivering: boolean, -- livraison des paliers en cours (jamais réentrante)
	deliverAgain: boolean, -- points gagnés pendant une livraison : la liste est reprise après
	trackRetryAcc: number, -- s depuis le dernier essai d'un palier en attente
	trackDirtyAcc: number, -- s depuis la dernière réplication de weeklyTrack.play
	playAcc: number, -- fraction de seconde de jeu pas encore écrite dans weeklyTrack.play
	stepAcc: number, -- s depuis la dernière vue des étapes du record
	stepKey: number?, -- boucle vue (r × 128 + A) ; nil = pas encore vue dans la session ; −1 = prestige
	stepShown: number, -- étapes du record déjà passées dans cette boucle (bits 1, 2, 4 : 25, 50, 75 %)
	-- v2.0 (lot A4, étape 5) [Mastery]
	masteryAcc: number, -- s depuis la dernière vue de la maîtrise et des jalons géants
	giantTier: number?, -- attribut GiantTier posé (nil = absent)
	giantBig: number?, -- biggestEver à la dernière vue (nil = pas encore vue : rien de nouveau à montrer)
}

local sessions: { [Player]: Session } = {}
-- sessions des partants, gardées pour la sauvegarde de départ (onBeforeSave release) : Roblox ne garantit
-- pas l'ordre des connexions de PlayerRemoving, et DataService peut attendre une autosave en cours avant
-- d'appeler ses crochets. Clés faibles : rien ne reste après le départ.
local departing: { [Player]: Session } = setmetatable({}, { __mode = "k" }) :: any
local started = false

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

-- Profil du jeu chargé (les clés de QuestService existent : ProfileRepair les garantit) ; un profil
-- d'un autre schéma (specs du socle) n'est jamais touché
local function profile(player: Player): { [string]: any }?
	local ok, data = pcall(DataService.get, player)
	if
		ok
		and type(data) == "table"
		and type(data.onboarding) == "table"
		and type(data.stats) == "table"
		and type(data.objectives) == "table"
		and type(data.dex) == "table"
	then
		return data
	end
	return nil
end

local function onboardingOf(data: { [string]: any }): { [string]: any }
	if type(data.onboarding) ~= "table" then
		data.onboarding = { step = 0, done = false, demoDone = false }
	end
	return data.onboarding
end

local function statsOf(data: { [string]: any }): { [string]: any }
	if type(data.stats) ~= "table" then
		data.stats = {}
	end
	return data.stats
end

local function playOf(data: { [string]: any }): number
	return math.max(0, num(statsOf(data).playSeconds, 0))
end

local function addStat(player: Player, data: { [string]: any }, key: string, amount: number)
	local stats = statsOf(data)
	stats[key] = num(stats[key], 0) + amount
	DataService.markDirty(player, "stats")
end

local function sessionOf(player: Player): Session?
	return sessions[player]
end

local function stepDef(n: number): Quests.OnboardingStep?
	for _, def in ONB.Steps do
		if def.step == n then
			return def
		end
	end
	return nil
end

local function funnelName(key: string): string
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function nextHint(n: number): string
	local def = stepDef(n + 1)
	return if def and def.hint then def.hint else ""
end

-- =============================================================================================
-- Accueil
-- =============================================================================================

local function refreshBuild(player: Player)
	Guard.try("quest:refreshBuild", RanchService.refreshBuild, player)
end

-- Étape n atteinte (la plus haute est gardée ; une étape plus basse arrivée plus tard ne fait rien)
local function reach(player: Player, n: number, silent: boolean?)
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil or not s.ready then
		return
	end
	local onboarding = onboardingOf(data)
	local step = num(onboarding.step, 0)
	if n <= step then
		return
	end
	onboarding.step = n
	DataService.markDirty(player, "onboarding")
	local def = stepDef(n)
	Signals.OnboardingStep:Fire(player, n)
	if not silent then
		-- à l'arrivée (étape 1), le profil répliqué suffit : aucune célébration à la seconde 0
		Notify.celebrate(player, "onboarding", { step = n, hint = nextHint(n) })
	end
	Analytics.funnel(player, n, funnelName(if def then def.key else tostring(n)))
	-- consigne suivante ouverte (90 s au plus), aucune après la dernière étape
	s.stepAt = if stepDef(n + 1) ~= nil and onboarding.done ~= true then Clock.now() else nil
	if n == 4 or n == 5 then
		refreshBuild(player)
	end
end

local function resumeOnboarding(data: { [string]: any }, s: Session)
	local onboarding = onboardingOf(data)
	if onboarding.done == true then
		return
	end
	local step = num(onboarding.step, 0)
	if step > 0 then
		-- retour : la consigne en cours se réaffiche (le client lit l'étape du profil répliqué)
		s.stepAt = if stepDef(step + 1) ~= nil then Clock.now() else nil
	end
end

local function giveStarter(player: Player, data: { [string]: any })
	-- premier squishy du compte (jamais redonné : un compte qui a déjà eu un squishy a nextUid > 1)
	if num(data.nextUid, 1) ~= 1 or next(data.squishies or {}) ~= nil then
		return
	end
	Guard.try(
		"quest:starter",
		SquishyService.give,
		player,
		{ s = Species.PLOP, m = 0, st = 0, z = 1 },
		"starter"
	)
end

-- =============================================================================================
-- Objectifs
-- =============================================================================================

local function tilesLeft(data: { [string]: any }): number
	local tiles = if type(data.tiles) == "table" then data.tiles else {}
	local left = 0
	for _, key in { "snack", "decor", "pens" } do
		local def = (Balance.Tiles :: any)[key]
		if def then
			left += math.max(0, def.Levels - num(tiles[key], 0))
		end
	end
	-- N1 (lot A4, D7) : le Lit douillet s'ouvre au Record R (profil v1 : R)
	if tiles.cozyBed ~= true and Prestige.bestR(data) >= Balance.Tiles.cozyBed.MinR then
		left += 1
	end
	return left
end

local function ctxOf(player: Player, data: { [string]: any }): QuestRules.QuestCtx
	local now = Clock.now()
	local s = sessionOf(player)
	local megaIn = math.huge
	local okMega, nextMega = pcall(EventClock.nextEventOf, now, { mega = true })
	if okMega and type(nextMega) == "table" and finite(nextMega.at) then
		megaIn = math.max(0, nextMega.at - now)
	end
	-- N1 (lot A4, D7) : conditions « Record R ≥ 1 / 3 » (combo ×2, Rare) au Record R ; l'objectif de
	-- taille est celui de la boucle en cours (r). Une boucle qui finit par un Petit Splorch (remontée
	-- après une Ascension) ne propose jamais « Fais un Grand Splorch » (GDD §7.5 m9 : il ne compte pas).
	-- Profil v1 : bestR = r = R, prochain prestige toujours un Grand Splorch (comme avant)
	local recordR = Prestige.bestR(data)
	local eta = math.huge
	if Prestige.nextKind(data) == "splorch" then
		local okBig, _, biggest = pcall(SquishyService.biggest, player)
		local target = Formulas.splorchTarget(Prestige.r(data))
		local g = num(type(data.growth) == "table" and data.growth.g, 0)
		if okBig and finite(biggest) then
			if biggest >= target then
				eta = 0
			elseif g > 0 then
				eta = (target - biggest) / g
			end
		end
	end
	return {
		R = recordR,
		tilesLeft = tilesLeft(data),
		megaIn = megaIn,
		friendOnServer = s ~= nil and s.friends > 0,
		splorchEta = eta,
		stamps = QuestRules.stampCount(data.dex),
	}
end

local function objectivesOf(data: { [string]: any }): { [string]: any }
	if type(data.objectives) ~= "table" then
		data.objectives = { day = 0, list = {}, rerolls = 0, allClaimed = false }
	end
	local o = data.objectives
	if type(o.list) ~= "table" then
		o.list = {}
	end
	return o
end

local function tierOf(id: number): string
	local def = Quests.Objectives[id]
	return if def and def.id == id then def.tier else "easy"
end

local function claimReward(player: Player, entry: Types.ObjectiveEntry)
	local tier = tierOf(entry.id)
	local reward = (RULES.Rewards :: any)[tier]
	local seconds = if reward then reward.incomeSeconds else 0
	if seconds > 0 then
		Guard.try(
			"quest:objectiveReward",
			EconomyService.addIncomeSeconds,
			player,
			seconds,
			"Objective_" .. tier
		)
	end
end

-- Goutte chanceuse (les 3 objectifs du jour réclamés ; paliers 4 et 8 de la piste) : naissance de
-- qualité + 1, mutations × 2 ; seed : graine du tirage (déterministe). N1 (lot A4, D7) : Cuve et familles
-- au Record R (profil v1 : R)
local function luckyDrop(player: Player, data: { [string]: any }, seed: number)
	local R = Prestige.bestR(data)
	local vat = Formulas.vatLevel(R)
	local rng = Hash.stream(seed)
	local roll = Odds.roll(rng, {
		quality = math.min(Balance.Vat.QualityMax, vat.quality + Balance.Babies.LuckyQualityBonus),
		nozzles = vat.nozzles,
		moon = false,
		unix = Clock.unix(),
		families = Odds.unlockedFamilies(R),
		mutationMult = Balance.Babies.LuckyMutationMult,
	})
	local ok, uid = Guard.try(
		"quest:luckyDrop",
		SquishyService.give,
		player,
		{ s = roll.species, m = roll.mutation, st = 0, z = 1 },
		"lucky"
	)
	Notify.celebrate(player, "luckyDrop", {
		uid = if ok and type(uid) == "string" then uid else "",
		species = roll.species,
		mutation = roll.mutation,
	})
end

-- =============================================================================================
-- v2.0 (lot A4, étape 4) : statistiques à vie, piste de la semaine, Défis de Splorch, Carnet du Ranch,
-- cartes du Record R, étapes du record, jours de givre. Profil v2 seulement ; chaque système derrière
-- son interrupteur (coupé : aucun champ lu ni écrit, aucune carte, aucun envoi)
-- =============================================================================================

local TRACK = Quests.WeeklyTrack
local CARNET = Quests.Carnet
local TRACK_TIERS = #TRACK.Tiers
local WEEKLY = Cosmetics.WeeklyRotation
local STAT_MAX = 1e12 -- borne des compteurs à vie (ProfileRepair v2)
local POINTS_MAX = 1e6 -- borne de weeklyTrack.points (ProfileRepair v2)
local DAY_SECONDS = 86400
local PLAY_DAYS = 7 -- cases de weeklyTrack.play (jour UTC % 7 + 1)
local TRACK_DIRTY_EVERY = 60 -- s de jeu : weeklyTrack.play répliqué au plus toutes les 60 s
local TRACK_RETRY_EVERY = 10 -- s : nouvel essai d'un palier dont la récompense a été refusée
local TRACK_DROP_SALT = 0x7A4C -- sel figé des Gouttes chanceuses de la piste (paliers 4 et 8)
local RECORD_STEPS = { 0.25, 0.5, 0.75 } -- étapes du record : part de l'objectif de la boucle (D14)
local RECORD_STEP_EVERY = 2 -- s entre deux vues des étapes du record
local FROST_COSTUME = "winter2026" -- costume d'hiver : jours de givre (selle « Sucre glace », D33)
local MASTERY_EVERY = 10 -- s entre deux vues de la maîtrise et des jalons géants (D13, D16)
-- tenues gagnées au Record R (Cosmetics.ListV2 : chapeau de fête au R7, lunettes étoiles au R16)
local RECORD_OUTFITS: { { id: string, at: number } } = {}
-- cosmétiques des jalons géants (Cosmetics.ListV2, source « size » : selle 1e15, traînée 1e18, titre 1e24)
local SIZE_COSMETICS: { { kind: string, id: string, at: number } } = {}
for _, def in Cosmetics.ListV2 :: { any } do
	if def.kind == "outfit" and type(def.source) == "table" and def.source.kind == "recordR" then
		table.insert(RECORD_OUTFITS, { id = def.id, at = def.source.value })
	end
	if type(def.source) == "table" and def.source.kind == "size" then
		table.insert(SIZE_COSMETICS, { kind = def.kind, id = def.id, at = def.source.value })
	end
end
-- crochets des compteurs à vie (QuestService.onLifetime)
local lifetimeHooks: { (Player, string) -> () } = {}

local function isV2(data: { [string]: any }): boolean
	return PadRules.v2Profile(data)
end

-- Compteur à vie d'un profil v2 (D34) : stats[key] += n (entier, borné) ; rend vrai si écrit
local function bumpStat(data: { [string]: any }, key: string, n: number): boolean
	if not isV2(data) or not finite(n) or n < 1 then
		return false
	end
	local stats = statsOf(data)
	stats[key] = math.min(STAT_MAX, math.max(0, math.floor(num(stats[key], 0))) + math.floor(n))
	return true
end

local function addLifetime(player: Player, data: { [string]: any }, key: string, n: number)
	if bumpStat(data, key, n) then
		DataService.markDirty(player, "stats")
		for _, hook in lifetimeHooks do
			Guard.try("quest:lifetimeHook", hook, player, key)
		end
	end
end

local function trackOf(data: { [string]: any }): { [string]: any }?
	local track = data.weeklyTrack
	return if type(track) == "table" then track else nil
end

-- 3 Défis de la période (QuestRules.drawChallenges, situation par Meta/ChallengeCtx, D11)
local function drawChallenges(
	player: Player,
	data: { [string]: any },
	period: number
): { Types.ChallengeEntry }
	local okBig, _, biggest = pcall(SquishyService.biggest, player)
	local ctx = ChallengeCtx.build(data, {
		now = Clock.now(),
		biggest = if okBig and finite(biggest) then biggest else 0,
		recordR = Features.get("RecordR") == true,
		mega = Features.get("MegaSquish") == true,
		confetti = Features.get("Confetti") == true,
	})
	local list: { Types.ChallengeEntry } = {}
	for _, id in QuestRules.drawChallenges(player.UserId, period, ctx) do
		table.insert(list, { id = id, p = 0, done = false })
	end
	return list
end

-- Récompense d'un palier de la piste : (livrée, texte de la carte). Confettis (source "track") refusés
-- (interrupteur Confetti coupé, plafond) : non livrée, le palier attend (D35). Goutte chanceuse : graine
-- (joueur, période, palier). Cosmétique de la semaine : Cosmetics.WeeklyRotation[période % 8 + 1], bit
-- de weeklyTrack.won ; déjà gagné : rien de plus (D9) ; tenue (nœud à pois) aussi dans outfits.owned
local function deliverTier(
	player: Player,
	data: { [string]: any },
	track: { [string]: any },
	tier: number
): (boolean, string)
	local reward = TRACK.Tiers[tier]
	local period = math.max(0, math.floor(num(track.period, 0)))
	if type(reward) == "number" then
		local ok, credited =
			Guard.try("quest:trackConfetti", EconomyService.addConfetti, player, reward, "track")
		if ok and finite(credited) and credited > 0 then
			return true, "confetti"
		end
		return false, ""
	elseif reward == "drop" then
		luckyDrop(player, data, Hash.u32(player.UserId, period, tier, TRACK_DROP_SALT))
		return true, "drop"
	elseif reward == "cosmetic" then
		local index = period % #WEEKLY + 1
		local def = WEEKLY[index]
		if type(track.won) ~= "table" then
			track.won = Bitset.new(#WEEKLY)
		end
		if def == nil or Bitset.has(track.won, index) then
			return true, ""
		end
		Bitset.set(track.won, index)
		if def.kind == "outfit" then
			Guard.try("quest:trackOutfit", SquishyService.grantOutfit, player, def.id, 1)
		end
		return true, def.kind .. "." .. def.id
	end
	return true, ""
end

-- Paliers atteints livrés tout seuls, dans l'ordre, chacun réclamé APRÈS sa récompense (D35) ; un palier
-- refusé arrête la livraison (le suivant attend aussi) et sera repris
local function deliverOnce(player: Player, data: { [string]: any }, s: Session, track: { [string]: any })
	local reached = QuestRules.trackTier(track.points)
	if type(track.claimed) ~= "table" then
		track.claimed = Bitset.new(TRACK_TIERS)
	end
	s.trackPending = false
	for tier = 1, reached do
		if not Bitset.has(track.claimed, tier) then
			local delivered, reward = deliverTier(player, data, track, tier)
			if not delivered then
				s.trackPending = true
				return
			end
			Bitset.set(track.claimed, tier)
			DataService.markDirty(player, "weeklyTrack")
			Notify.celebrate(player, "trackTier", { tier = tier, reward = reward })
			Analytics.custom(player, "WeeklyTrackTier", tier)
			if tier == TRACK_TIERS then
				addLifetime(player, data, "tracksDone", 1)
			end
		end
	end
end

-- Une récompense peut en faire gagner d'autres PENDANT sa livraison (Goutte chanceuse → nouveau tampon →
-- Défi fini → points) : la livraison n'est jamais réentrante (un palier serait livré deux fois) ; l'appel
-- du dedans est noté et la livraison en cours reprend la liste quand elle a fini
local function deliverTiers(player: Player, data: { [string]: any }, s: Session, track: { [string]: any })
	if s.delivering then
		s.deliverAgain = true
		return
	end
	s.delivering = true
	local ok, err = pcall(function()
		repeat
			s.deliverAgain = false
			deliverOnce(player, data, s, track)
		until not s.deliverAgain or s.trackPending
	end)
	s.delivering = false
	if not ok then
		error(err, 0)
	end
end

-- Piste du joueur [WeeklyTrack], période vérifiée UNE fois par session (D10 : au début de la session, ou
-- au premier usage si l'interrupteur s'ouvre en session ; une session qui passe le lundi 00:00 garde sa
-- période, ses Défis et ses points) : 1re période fixée (QuestRules.trackPeriod), nouvelle période =
-- points à 0, paliers vides, 3 Défis tirés ; un palier en attente est repris. nil si coupée
local function ensureTrack(player: Player, data: { [string]: any }, s: Session): { [string]: any }?
	if not s.ready or Features.get("WeeklyTrack") ~= true or not isV2(data) then
		return nil
	end
	local track = trackOf(data)
	if track == nil then
		return nil
	end
	if s.trackReady then
		return track
	end
	s.trackReady = true
	local period = QuestRules.trackPeriod(data, Clock.unix())
	local changed = false
	if num(track.firstPeriodEnd, -1) ~= period.firstPeriodEnd then
		track.firstPeriodEnd = period.firstPeriodEnd
		changed = true
	end
	if num(track.period, -1) ~= period.period then
		track.period = period.period
		track.points = 0
		track.claimed = Bitset.new(TRACK_TIERS)
		track.challenges = drawChallenges(player, data, period.period)
		changed = true
	end
	if changed then
		DataService.markDirty(player, "weeklyTrack")
	end
	deliverTiers(player, data, s, track)
	return track
end

-- Points de la piste (2 par objectif du jour terminé, 5 par Défi : D12) puis paliers
local function addPoints(player: Player, data: { [string]: any }, s: Session, n: number)
	if n < 1 then
		return
	end
	local track = ensureTrack(player, data, s)
	if track == nil then
		return
	end
	track.points = math.min(POINTS_MAX, math.max(0, math.floor(num(track.points, 0))) + math.floor(n))
	DataService.markDirty(player, "weeklyTrack")
	deliverTiers(player, data, s, track)
end

-- Progression des Défis de la période (statistique de Quests.Challenges) ; Défi fini : + 5 points
local function challengeProgress(player: Player, stat: string, amount: number)
	if not finite(amount) or amount < 1 then
		return
	end
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil then
		return
	end
	local track = ensureTrack(player, data, s)
	if track == nil or type(track.challenges) ~= "table" then
		return
	end
	local n = math.floor(amount)
	local changed = false
	local done = 0
	for _, entry in track.challenges do
		if type(entry) == "table" and entry.done ~= true then
			local def = (Quests.Challenges :: { any })[entry.id]
			if type(def) == "table" and def.id == entry.id and def.stat == stat then
				local p = math.min(def.target, math.max(0, math.floor(num(entry.p, 0))) + n)
				if p ~= entry.p then
					entry.p = p
					changed = true
				end
				if p >= def.target then
					entry.done = true
					changed = true
					done += 1
				end
			end
		end
	end
	if changed then
		DataService.markDirty(player, "weeklyTrack")
	end
	if done > 0 then
		addPoints(player, data, s, done * TRACK.PointsPerChallenge)
		MetaAnalytics.goal(player) -- but atteint (NextGoalGap, lot A4 étape 6)
	end
end

-- Jeu des 7 derniers jours [WeeklyTrack] (médiane et jours joués des Défis) : secondes entières dans la
-- case Clock.day() % 7 + 1 ; les cases des jours sautés depuis weeklyTrack.playDay sont vidées
local function addPlay(player: Player, data: { [string]: any }, s: Session, dt: number)
	local track = trackOf(data)
	if track == nil or type(track.play) ~= "table" then
		return
	end
	local play = track.play
	local today = Clock.day()
	local last = num(track.playDay, 0)
	if last ~= today then
		if last <= 0 or last > today or today - last >= PLAY_DAYS then
			for i = 1, PLAY_DAYS do
				play[i] = 0
			end
		else
			for d = last + 1, today do
				play[d % PLAY_DAYS + 1] = 0
			end
		end
		track.playDay = today
	end
	s.playAcc += dt
	local whole = math.floor(s.playAcc)
	if whole >= 1 then
		s.playAcc -= whole
		local slot = today % PLAY_DAYS + 1
		play[slot] = math.min(DAY_SECONDS, math.max(0, math.floor(num(play[slot], 0))) + whole)
	end
	s.trackDirtyAcc += dt
	if s.trackDirtyAcc >= TRACK_DIRTY_EVERY then
		s.trackDirtyAcc = 0
		DataService.markDirty(player, "weeklyTrack")
	end
end

-- Carnet du Ranch [Carnet] : paliers atteints (QuestRules.carnetTier de stats.upgradesBought) sans leur
-- bit → bit posé, carte « carnet » (silent : migration, carte « Bienvenue » en attente) ; la couronne de
-- chantier (10 000) va aussi dans outfits.owned, une fois (au moment où son bit est posé)
local function carnetCheck(player: Player, data: { [string]: any }, silent: boolean)
	if Features.get("Carnet") ~= true or not isV2(data) then
		return
	end
	local tier = QuestRules.carnetTier(statsOf(data).upgradesBought)
	if tier < 1 then
		return
	end
	if type(data.carnet) ~= "table" then
		data.carnet = Bitset.new(#CARNET.Tiers)
	end
	local changed = false
	for i = 1, tier do
		if not Bitset.has(data.carnet, i) then
			Bitset.set(data.carnet, i)
			changed = true
			local reward = CARNET.Rewards[CARNET.Tiers[i]] or ""
			if string.sub(reward, 1, 7) == "outfit." then
				Guard.try("quest:carnetOutfit", SquishyService.grantOutfit, player, string.sub(reward, 8), 1)
			end
			if not silent then
				Notify.celebrate(player, "carnet", { tier = i, reward = reward })
			end
		end
	end
	if changed then
		DataService.markDirty(player, "carnet")
	end
end

local function setSeen(player: Player, data: { [string]: any }, best: number)
	if num(data.unlocksSeen, -1) ~= best then
		DataService.set(player, "unlocksSeen", best)
	end
end

-- 3 déblocages les plus hauts déjà gagnés (clés de Prestige.unlocksFor, du Record R vers 1, sans doublon)
local function highlights(best: number): { string }
	local out: { string } = {}
	for r = best, 1, -1 do
		for _, key in Prestige.unlocksFor(r) do
			if table.find(out, key) == nil then
				table.insert(out, key)
				if #out >= 3 then
					return out
				end
			end
		end
	end
	return out
end

-- Tenues du Record R (chapeau de fête R7, lunettes étoiles R16) : données une fois (rattrapage si aucune)
local function recordOutfits(player: Player, data: { [string]: any }, best: number)
	local outfits = data.outfits
	local owned = if type(outfits) == "table" and type(outfits.owned) == "table" then outfits.owned else nil
	if owned == nil then
		return
	end
	for _, def in RECORD_OUTFITS do
		local n = owned[def.id]
		if best >= def.at and not (type(n) == "number" and n >= 1) then
			Guard.try("quest:recordOutfit", SquishyService.grantOutfit, player, def.id, 1)
		end
	end
end

-- Cartes du Record R [RecordR] (D15) : à la connexion, « Bienvenue dans la v2 ! » une fois (migration
-- d'un joueur qui avait R ≥ 1 ; jamais pour un nouveau), sinon UNE carte « Nouveau » pour le Record R
-- s'il n'a pas été montré ; à chaque RecordReached, la carte « Nouveau » du nouveau Record R ; unlocksSeen
-- = Record R ; tenues du Record R
local function recordCards(player: Player, data: { [string]: any }, atLogin: boolean)
	if Features.get("RecordR") ~= true or not isV2(data) then
		return
	end
	local best = Prestige.bestR(data)
	local onboarding = onboardingOf(data)
	if atLogin and onboarding.welcomeV2Pending == true then
		onboarding.welcomeV2Pending = false
		DataService.markDirty(player, "onboarding")
		Notify.celebrate(player, "welcomeV2", { highlights = highlights(best) })
		setSeen(player, data, best)
	elseif num(data.unlocksSeen, 0) < best then
		Notify.celebrate(player, "unlock2", { recordR = best, keys = Prestige.unlocksFor(best) })
		setSeen(player, data, best)
	end
	recordOutfits(player, data, best)
end

-- Étapes du record [RecordR] (D14) : boucle record (r = Record R ≥ 1 : jamais la boucle de l'accueil ni
-- une remontée), plus gros squishy d'enclos ou du Bassin à 25, 50, 75 % de Prestige.target(r), une fois
-- chacune par boucle (mémoire de session ; la première vue d'une session pose sans carte les étapes déjà
-- passées), jamais pendant la file ou le spectacle du joueur ; plusieurs étapes passées d'un coup : une
-- seule carte (la plus haute)
local function recordSteps(player: Player, data: { [string]: any }, s: Session)
	local r = Prestige.r(data)
	local best = Prestige.bestR(data)
	local key = r * 128 + Prestige.ascend(data)
	local first = s.stepKey == nil
	if key ~= s.stepKey then
		s.stepKey = key
		s.stepShown = 0
	end
	if r ~= best or best < 1 then
		return
	end
	if SquishyService.waiting(player) ~= nil or EconomyService.prestigeBusy(player) then
		return
	end
	local okBig, _, biggest = pcall(SquishyService.biggest, player)
	if not okBig or not finite(biggest) then
		return
	end
	local share = biggest / Prestige.target(r)
	local top = 0
	for i, at in RECORD_STEPS do
		local bit = bit32.lshift(1, i - 1)
		if share >= at and bit32.band(s.stepShown, bit) == 0 then
			s.stepShown = bit32.bor(s.stepShown, bit)
			top = i
		end
	end
	if top > 0 and not first then
		Notify.celebrate(player, "recordStep", { share = RECORD_STEPS[top] })
	end
end

-- Jour de givre (D33) : + 1 season.frostDays par jour où Plop est nourri pendant le costume d'hiver
-- (interrupteur Costumes ET ses dates, Events.Costumes), profil v2
local function frostDay(player: Player, data: { [string]: any })
	if
		not isV2(data)
		or Features.get("Costumes") ~= FROST_COSTUME
		or EventClock.costume(Clock.unix()) ~= FROST_COSTUME
	then
		return
	end
	local season = data.season
	if type(season) ~= "table" then
		return
	end
	season.frostDays = math.min(1e9, math.max(0, math.floor(num(season.frostDays, 0))) + 1)
	DataService.markDirty(player, "season")
end

-- Puce « Prochain achat » vue (D32, UiSeen("nextBuy")) [UpgradesScreen] : onboarding.nextBuyShown, une fois
local function nextBuySeen(player: Player)
	if Features.get("UpgradesScreen") ~= true then
		return
	end
	local data = profile(player)
	if data == nil or not isV2(data) then
		return
	end
	local onboarding = onboardingOf(data)
	if onboarding.nextBuyShown ~= true then
		onboarding.nextBuyShown = true
		DataService.markDirty(player, "onboarding")
	end
end

-- Jalons géants [Mastery] (D16) : attribut GiantTier du ranch (0-4, Owned.giantTier) posé quand il
-- change ; cosmétique de taille devenu possédé PENDANT la session → Celebrate("unlock", { kind, id }) (la
-- première vue de la session ne montre rien : ce qui était déjà gagné l'a été avant)
local function giantCheck(player: Player, data: { [string]: any }, s: Session)
	local tier = Owned.giantTier(data)
	if s.giantTier ~= tier then
		s.giantTier = tier
		Guard.try("quest:giantTier", RanchService.setV2Attributes, player, { GiantTier = tier })
	end
	local big = num(data.biggestEver, 0)
	local before = s.giantBig
	s.giantBig = big
	if before == nil or big <= before then
		return
	end
	for _, def in SIZE_COSMETICS do
		if before < def.at and big >= def.at then
			Notify.celebrate(player, "unlock", { kind = def.kind, id = def.id })
		end
	end
end

-- Maîtrise d'espèce [Mastery] (D13) : ★5, page dorée et Trophée Cristal faits (Owned.mastery) sans bit
-- de `mastery` → + Balance.Confetti.Mastery par EconomyService.addConfetti(…, "mastery") ; bit, patch et
-- carte SEULEMENT si les Confettis sont crédités (Confettis coupés : rien d'écrit, nouvel essai à la vue
-- suivante) ; `silent` : première vue d'un ancien joueur à sa migration (Confettis donnés sans carte,
-- comme les paliers du Carnet)
local function masteryCheck(player: Player, data: { [string]: any }, silent: boolean)
	local bits = data.mastery
	if type(bits) ~= "table" then
		return
	end
	for species = 1, #Species.List do
		if not Bitset.has(bits, species) then
			local star, golden, crystal = Owned.mastery(data, species)
			if star and golden and crystal then
				local credited = Guard.call(
					"quest:mastery",
					EconomyService.addConfetti,
					0,
					player,
					Balance.Confetti.Mastery,
					"mastery"
				)
				if not (finite(credited) and credited > 0) then
					return
				end
				Bitset.set(bits, species)
				DataService.markDirty(player, "mastery")
				if not silent then
					Notify.celebrate(player, "mastery", { species = species })
				end
			end
		end
	end
end

-- Vue de la maîtrise et des jalons géants d'un profil v2 [Mastery] ; interrupteur coupé : attribut
-- GiantTier effacé s'il avait été posé, rien d'autre (aucune lecture du profil)
local function masteryStep(player: Player, data: { [string]: any }, s: Session, silent: boolean)
	if Features.get("Mastery") ~= true then
		if s.giantTier ~= nil then
			s.giantTier = nil
			s.giantBig = nil
			Guard.try("quest:giantClear", RanchService.setV2Attributes, player, {}, { "GiantTier" })
		end
		return
	end
	giantCheck(player, data, s)
	masteryCheck(player, data, silent)
end

-- Tick v2 d'un profil v2 : jeu des 7 jours et palier en attente [WeeklyTrack], étapes du record
-- [RecordR] toutes les 2 s, maîtrise et jalons géants [Mastery] toutes les 10 s ; interrupteurs coupés :
-- une lecture chacun, rien d'alloué
local function stepV2(player: Player, data: { [string]: any }, s: Session, dt: number)
	if Features.get("WeeklyTrack") == true then
		addPlay(player, data, s, dt)
		if s.trackPending then
			s.trackRetryAcc += dt
			if s.trackRetryAcc >= TRACK_RETRY_EVERY then
				s.trackRetryAcc = 0
				local track = ensureTrack(player, data, s)
				if track ~= nil and s.trackPending then
					deliverTiers(player, data, s, track)
				end
			end
		end
	end
	s.stepAcc += dt
	if s.stepAcc >= RECORD_STEP_EVERY then
		s.stepAcc = 0
		if Features.get("RecordR") == true then
			recordSteps(player, data, s)
		end
	end
	s.masteryAcc += dt
	if s.masteryAcc >= MASTERY_EVERY then
		s.masteryAcc = 0
		masteryStep(player, data, s, false)
	end
end

local function allClaimed(o: { [string]: any }): boolean
	if #o.list < RULES.PerDay then
		return false
	end
	for _, entry in o.list do
		if entry.claimed ~= true then
			return false
		end
	end
	return true
end

-- Réclame une case (déjà vérifiée) ; les 3 réclamées : Goutte chanceuse (une fois par jour d'objectifs)
local function claimEntry(player: Player, data: { [string]: any }, entry: Types.ObjectiveEntry)
	entry.claimed = true
	claimReward(player, entry)
	addLifetime(player, data, "objectivesClaimed", 1)
	local o = objectivesOf(data)
	if not o.allClaimed and allClaimed(o) then
		o.allClaimed = true
		luckyDrop(player, data, Hash.u32(player.UserId, num(o.day, Clock.day()), 0x1C4E))
	end
	DataService.markDirty(player, "objectives")
end

local function newObjectives(
	player: Player,
	data: { [string]: any },
	today: number,
	firstDay: boolean,
	card: boolean?
)
	local o = objectivesOf(data)
	local ids = QuestRules.draw(player.UserId, today, ctxOf(player, data), firstDay)
	local list = {}
	for _, id in ids do
		table.insert(list, { id = id, p = 0, done = false, claimed = false })
	end
	o.day = today
	o.list = list
	o.rerolls = 0
	o.allClaimed = false
	DataService.markDirty(player, "objectives")
	if not firstDay and card ~= false then
		Notify.celebrate(player, "newObjectives", { day = today })
	end
end

-- Connexion (DataService.onPrepare, avant l'instantané : aucun patch à l'arrivée) : nouveaux objectifs
-- si c'est un nouveau jour ; les terminés non réclamés d'avant sont rendus pour être payés à PlayerReady
-- (le profil n'est pas encore lisible par EconomyService pendant onPrepare)
local function objectivesAtLogin(player: Player, data: { [string]: any }): ({ number }, boolean)
	local o = objectivesOf(data)
	local today = Clock.day()
	if num(o.day, 0) == today and #o.list > 0 then
		return {}, false
	end
	local firstDay = num(o.day, 0) == 0
	local claim: { number } = {}
	if not firstDay then
		local _, done = QuestRules.rollover(o.list, true)
		claim = done
	end
	newObjectives(player, data, today, firstDay, false)
	return claim, not firstDay
end

-- Minuit en session : terminés réclamés seuls, en cours gardés pour la session
local function midnight(player: Player, data: { [string]: any }, s: Session)
	local o = objectivesOf(data)
	local kept, claim = QuestRules.rollover(o.list, true)
	for _, id in claim do
		claimReward(player, { id = id, p = 0, done = true, claimed = true })
	end
	addLifetime(player, data, "objectivesClaimed", #claim)
	o.list = kept
	s.kept = true
	DataService.markDirty(player, "objectives")
end

-- Progression des objectifs par un événement
local function progress(player: Player, stat: string, amount: number, perfect: boolean?)
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil or not s.ready then
		return
	end
	local o = objectivesOf(data)
	local changed = false
	local newlyDone = 0
	local allDone = #o.list >= RULES.PerDay
	for slot, entry in o.list do
		if type(entry) == "table" and entry.claimed ~= true then
			local wasDone = entry.done == true
			local nextEntry = QuestRules.apply(entry, stat, amount, perfect)
			if nextEntry.p ~= entry.p or nextEntry.done ~= entry.done then
				entry.p = nextEntry.p
				entry.done = nextEntry.done
				changed = true
				if entry.done and not wasDone then
					newlyDone += 1
					Notify.celebrate(player, "objectiveDone", { slot = slot, id = entry.id })
				end
			end
		end
		if type(entry) ~= "table" or entry.done ~= true then
			allDone = false
		end
	end
	if changed then
		DataService.markDirty(player, "objectives")
		if allDone and not s.allDoneLogged then
			s.allDoneLogged = true
			Analytics.custom(player, "ObjectivesAllDone", math.floor(s.play / 60))
		end
	end
	-- piste de la semaine [WeeklyTrack] : 2 points par objectif terminé (D12 ; 6 par jour d'objectifs)
	if newlyDone > 0 and s.v2 then
		addPoints(player, data, s, newlyDone * TRACK.PointsPerObjective)
	end
	-- but atteint (NextGoalGap [UpgradesScreen], lot A4 étape 6 : rien interrupteur coupé)
	if newlyDone > 0 then
		MetaAnalytics.goal(player)
	end
end

-- =============================================================================================
-- Nourrir Plop
-- =============================================================================================

local function bestFriendName(player: Player): string
	local ok, uid = pcall(SquishyService.bestFriend, player, 1)
	if ok and type(uid) == "string" then
		local okRec, rec = pcall(SquishyService.get, player, uid)
		if okRec and type(rec) == "table" then
			local def = Species.ById[rec.s]
			if def then
				return def.name
			end
		end
	end
	return Species.ById[Species.PLOP].name
end

local function holdPayload(kind: "feed", endsAt: number, active: boolean): Types.HoldStatePayload
	return { kind = kind, endsAt = endsAt, active = active, tile = "" }
end

local function sendHold(player: Player, endsAt: number, active: boolean)
	if player.Parent ~= nil then
		Net.event("HoldState"):FireClient(player, holdPayload("feed", endsAt, active))
	end
end

-- Position validée et droit d'agir (règle 17 : à plat, écart depuis les pieds)
local function nearBowl(player: Player): boolean
	local slot = RanchService.slotOf(player)
	if slot == 0 then
		return false
	end
	local pos = MoveCheck.lastValid(player)
	if pos == nil or not MoveCheck.canAct(player, Clock.now()) then
		return false
	end
	local offset = 0
	local okOffset, value = pcall(MoveCheck.rootOffset, player)
	if okOffset and finite(value) then
		offset = value
	end
	return ZoneRules.withinReach(pos, offset, WorldLayout.anchor(slot, "bowl"), FEED.Radius)
end

local function cancelFeed(player: Player, s: Session)
	local feed = s.feed
	if feed ~= nil then
		s.feed = nil
		sendHold(player, feed.endsAt, false)
	end
end

local function grantPlopReward(player: Player, reward: Quests.PlopReward)
	if reward.kind == "coins" then
		Guard.try(
			"quest:plopCoins",
			EconomyService.addIncomeSeconds,
			player,
			Balance.Rewards.PlopDay2,
			"PlopDay"
		)
	elseif reward.kind == "outfit" then
		Guard.try("quest:plopOutfit", SquishyService.grantOutfit, player, reward.id, 1)
		Notify.celebrate(player, "unlock", { kind = reward.kind, id = reward.id })
	else
		-- cosmétique débloqué par plopDays (CommunityService.hasCosmetic le voit aussitôt)
		Notify.celebrate(player, "unlock", { kind = reward.kind, id = reward.id })
	end
end

local function completeFeed(player: Player, data: { [string]: any }, s: Session)
	local feed = s.feed :: Feed
	s.feed = nil
	local today = Clock.day()
	if num(data.lastFeedDay, 0) == today then
		sendHold(player, feed.endsAt, false)
		return
	end
	local days = math.max(0, math.floor(num(data.plopDays, 0))) + 1
	DataService.set(player, "plopDays", days)
	DataService.set(player, "lastFeedDay", today)
	local reward = QuestRules.plopReward(days)
	if reward ~= nil then
		grantPlopReward(player, reward)
	end
	local boost = if reward ~= nil then Balance.Boosts.FeedMilestone else Balance.Boosts.FeedDay
	Guard.try("quest:feedBoost", EconomyService.grantPersonalBoost, player, boost)
	Guard.try("quest:feedDay", RanchService.setPublic, player, { day = days })
	sendHold(player, feed.endsAt, false)
	frostDay(player, data)
	Signals.Fed:Fire(player, days)
	Notify.celebrate(player, "plopDay", { day = days, reward = if reward then reward.key else "" })
end

-- =============================================================================================
-- Squishydex
-- =============================================================================================

local function denseTo(list: { number }, n: number)
	for i = #list + 1, n do
		list[i] = 0
	end
end

local function familyOf(species: number): string?
	local def = Species.ById[species]
	return if def then def.family else nil
end

-- =============================================================================================
-- Handlers des intentions
-- =============================================================================================

local function onFeedPlop(player: Player, holding: boolean): boolean
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil or not s.ready then
		return false
	end
	if not holding then
		if s.feed ~= nil then
			cancelFeed(player, s)
			return true
		end
		return false
	end
	if s.feed ~= nil then
		return false
	end
	if num(data.lastFeedDay, 0) == Clock.day() then
		Notify.feedback(player, "feedback.alreadyFed", { name = bestFriendName(player) }, "info")
		return false
	end
	if not nearBowl(player) then
		return false -- refus muet (de loin : rien ne commence)
	end
	local now = Clock.now()
	s.feed = { startedAt = now, endsAt = now + FEED.Hold }
	sendHold(player, now + FEED.Hold, true)
	return true
end

local function onClaimObjective(player: Player, slot: number): boolean
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil or not s.ready then
		return false
	end
	local o = objectivesOf(data)
	local entry = o.list[slot]
	if type(entry) ~= "table" or entry.done ~= true or entry.claimed == true then
		return false
	end
	claimEntry(player, data, entry)
	return true
end

local function onRerollObjective(player: Player, slot: number): boolean
	local data = profile(player)
	local s = sessionOf(player)
	if data == nil or s == nil or not s.ready or s.kept then
		return false
	end
	local o = objectivesOf(data)
	local entry = o.list[slot]
	if type(entry) ~= "table" or entry.done == true or entry.claimed == true then
		return false
	end
	-- objectif 12 (ami sur le serveur) alors que l'ami est parti : relance gratuite
	local def = Quests.Objectives[entry.id]
	local free = def ~= nil and def.condition == "friendOnServer" and s.friends == 0
	local used = math.max(0, math.floor(num(o.rerolls, 0)))
	if not free and used >= RULES.RerollsPerDay then
		Notify.feedback(player, "feedback.capReached", {}, "info")
		return false
	end
	local ids = {}
	for i, e in o.list do
		ids[i] = if type(e) == "table" then e.id else 0
	end
	local newId =
		QuestRules.reroll(player.UserId, num(o.day, Clock.day()), ids, slot, ctxOf(player, data), used + 1)
	if newId == entry.id then
		return false
	end
	o.list[slot] = { id = newId, p = 0, done = false, claimed = false }
	if not free then
		o.rerolls = used + 1
	end
	DataService.markDirty(player, "objectives")
	return true
end

local function onClaimDexReward(player: Player): boolean
	local data = profile(player)
	if data == nil or type(data.dex) ~= "table" then
		return false
	end
	local dex = data.dex
	local list = QuestRules.dexMilestones(QuestRules.stampCount(dex), num(dex.rewards, 0))
	local milestone = list[1]
	if milestone == nil then
		return false
	end
	dex.rewards = milestone.stamps
	DataService.markDirty(player, "dex")
	Notify.celebrate(player, "unlock", { kind = milestone.kind, id = milestone.id })
	return true
end

local function onUiSeen(player: Player, screen: string): boolean
	local s = sessionOf(player)
	if s == nil or s.seen[screen] then
		return false -- une fois par écran et par session
	end
	s.seen[screen] = true
	Signals.UiSeen:Fire(player, screen)
	if screen == "objectives" then
		reach(player, 10)
	elseif screen == "nextBuy" then
		nextBuySeen(player)
	end
	return false -- un écran vu ne donne jamais rien (et ne compte pas comme une activité de jeu)
end

-- v2.0 (lot A4, N23, décision du propriétaire du 6 novembre) : navigation dans un menu (MenuActivity,
-- au plus une toutes les 20 s côté client, débit du serveur dans Config/Intents) : acceptée seulement
-- interrupteur Helpers ouvert, profil v2, joueur prêt, présent et vivant ; Activity.noteMenu (sieste des
-- Plopettes) et RIEN d'autre : aucune récompense, statistique, objectif ni DataPatch (refus muet)
local function onMenuActivity(player: Player): boolean
	if Features.get("Helpers") ~= true or player.Parent == nil then
		return false
	end
	local data = DataService.get(player)
	if data == nil or not PadRules.v2Profile(data) or not RanchService.isReady(player) then
		return false
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	Activity.noteMenu(player, Clock.now())
	return true
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

local function sessionBand(sessionsDone: number): string
	local n = sessionsDone + 1
	return if n <= 1 then "first" elseif n <= 5 then "2-5" else "6+"
end

type Prepared = { fresh: boolean, claims: { number }, card: boolean }
-- clés faibles : un joueur parti pendant son chargement (onPrepare après son PlayerRemoving) ne reste pas
local prepared: { [Player]: Prepared } = setmetatable({}, { __mode = "k" }) :: any

-- Chargement (DataService.onPrepare, synchrone, avant l'instantané et Loaded) : première arrivée,
-- étape 1 de l'accueil, objectifs du jour ; tout part dans l'instantané (aucun patch à l'arrivée)
local function prepare(player: Player, data: { [string]: any })
	if
		type(data.onboarding) ~= "table"
		or type(data.stats) ~= "table"
		or type(data.objectives) ~= "table"
		or type(data.dex) ~= "table"
	then
		return
	end
	if num(data.firstJoin, 0) <= 0 then
		data.firstJoin = Clock.unix()
	end
	if type(data.codes) ~= "table" then
		data.codes = {}
	end
	local fresh = false
	if num(data.onboarding.step, 0) < 1 then
		data.onboarding.step = 1
		fresh = true
	end
	local claims, card = objectivesAtLogin(player, data)
	-- objectifs terminés d'un jour passé, réclamés à la connexion : comptés (profil v2, dans l'instantané)
	bumpStat(data, "objectivesClaimed", #claims)
	prepared[player] = { fresh = fresh, claims = claims, card = card }
end

local function onReady(player: Player)
	if sessions[player] ~= nil and sessions[player].ready then
		return
	end
	local data = profile(player)
	if data == nil then
		return
	end
	local now = Clock.now()
	local s: Session = {
		ready = true,
		readyAt = now,
		last = now,
		play = 0,
		dirtyAcc = 0,
		boostAcc = 0,
		boostSeconds = 0,
		day = Clock.day(),
		kept = false,
		seen = {},
		sleepy = {},
		stepAt = nil,
		feed = nil,
		friends = 0,
		allDoneLogged = false,
		cardSent = false,
		starterDue = num(data.nextUid, 1) == 1 and next(data.squishies or {}) == nil,
		released = false,
		v2 = isV2(data),
		trackReady = false,
		trackPending = false,
		delivering = false,
		deliverAgain = false,
		trackRetryAcc = 0,
		trackDirtyAcc = 0,
		playAcc = 0,
		stepAcc = 0,
		stepKey = nil,
		stepShown = 0,
		masteryAcc = 0,
		giantTier = nil,
		giantBig = nil,
	}
	sessions[player] = s
	Analytics.setSegment(player, "sessionBand", sessionBand(math.max(0, num(statsOf(data).sessions, 0))))
	local prep = prepared[player]
	prepared[player] = nil
	if prep == nil then
		-- profil préparé avant le branchement du crochet (ne devrait pas arriver) : même règles ici
		prepare(player, data)
		prep = prepared[player] or { fresh = false, claims = {}, card = false }
		prepared[player] = nil
	end
	if prep.fresh then
		Signals.OnboardingStep:Fire(player, 1)
		Analytics.funnel(player, 1, funnelName(ONB.Steps[1].key))
		s.stepAt = now
	else
		resumeOnboarding(data, s)
	end
	for _, id in prep.claims do
		claimReward(player, { id = id, p = 0, done = true, claimed = true })
	end
	if prep.card then
		Notify.celebrate(player, "newObjectives", { day = num(objectivesOf(data).day, Clock.day()) })
	end
	if s.v2 then
		-- Carnet (paliers déjà atteints posés sans carte tant que la carte « Bienvenue » attend), cartes du
		-- Record R, puis la période de la piste (D10 : vérifiée au début de la session seulement) ; maîtrise
		-- et jalons géants (GiantTier posé à l'arrivée ; maîtrises déjà faites d'un ancien joueur à sa
		-- migration : Confettis sans carte)
		local welcome = onboardingOf(data).welcomeV2Pending == true
		carnetCheck(player, data, welcome)
		recordCards(player, data, true)
		ensureTrack(player, data, s)
		masteryStep(player, data, s, welcome)
	end
end

local function onRemoving(player: Player)
	local s = sessions[player]
	sessions[player] = nil
	prepared[player] = nil
	if s == nil or not s.ready then
		return
	end
	if not s.released then
		departing[player] = s
	end
	local elapsed = math.max(0, Clock.now() - s.readyAt)
	Analytics.custom(player, "SessionLength", math.floor(elapsed / 60))
	if elapsed > 0 then
		Analytics.custom(player, "BoostShare", math.floor(100 * math.min(1, s.boostSeconds / elapsed) + 0.5))
	end
end

-- Départ ou fermeture (release) : compteurs de session écrits dans la sauvegarde de départ
local function beforeSave(player: Player, data: { [string]: any }, release: boolean?)
	if release ~= true then
		return
	end
	local s = sessions[player] or departing[player]
	departing[player] = nil
	if s == nil or not s.ready or s.released then
		return
	end
	local stats = statsOf(data)
	stats.sessions = math.max(0, math.floor(num(stats.sessions, 0))) + 1
	stats.playSeconds = math.max(0, num(stats.playSeconds, 0))
	s.released = true -- une seule fois (départ puis fermeture)
	s.feed = nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function QuestService.Init()
	Guard.connect("FeedPlop", onFeedPlop)
	Guard.connect("ClaimObjective", onClaimObjective)
	Guard.connect("RerollObjective", onRerollObjective)
	Guard.connect("ClaimDexReward", onClaimDexReward)
	Guard.connect("UiSeen", onUiSeen)
	Guard.connect("MenuActivity", onMenuActivity)
	DataService.onBeforeSave(function(player, data, release)
		Guard.try("quest:beforeSave", beforeSave, player, data, release)
	end)
	if type((DataService :: any).onPrepare) == "function" then
		DataService.onPrepare(function(player, data)
			Guard.try("quest:prepare", prepare, player, data)
		end)
	end
end

-- Connexions et boucles
function QuestService.Start()
	if started then
		return
	end
	started = true
	local function on(signal: any, where: string, fn: (...any) -> ())
		signal:Connect(function(...)
			Guard.try(where, fn, ...)
		end)
	end
	on(Signals.PlayerReady, "quest:ready", onReady)
	on(Signals.Pressed, "quest:pressed", function(owner: Player, info: any)
		if type(info) ~= "table" or info.visitor ~= nil then
			return -- pet-sitting : compté chez le visiteur par PetSitRewarded
		end
		local data = profile(owner)
		if data == nil then
			return
		end
		local perfect = info.perfect == true
		addStat(owner, data, "presses", 1)
		if perfect then
			addStat(owner, data, "perfects", 1)
			progress(owner, "perfect", 1, true)
			challengeProgress(owner, "perfects", 1)
		end
		progress(owner, "press", 1, perfect)
		reach(owner, 2)
	end)
	on(Signals.TileBought, "quest:tile", function(player: Player)
		progress(player, "tileBuy", 1)
		reach(player, 3)
	end)
	on(Signals.PotCollected, "quest:pot", function(player: Player)
		progress(player, "potCollect", 1)
		reach(player, 6)
	end)
	on(Signals.Emoted, "quest:emote", function(player: Player)
		progress(player, "emote", 1)
	end)
	on(Signals.Fused, "quest:fused", function(player: Player, _uid: string, k: number)
		local data = profile(player)
		if data == nil then
			return
		end
		addStat(player, data, "fusions", 1)
		local stats = statsOf(data)
		if finite(k) and k > num(stats.bestCombo, 0) then
			stats.bestCombo = k
		end
		progress(player, "fusion", 1)
		if finite(k) and k >= 2 then
			progress(player, "combo2", 1)
		end
		if finite(k) and k >= 3 then
			challengeProgress(player, "combo3", 1)
		end
		reach(player, 5)
	end)
	on(Signals.Hatched, "quest:hatched", function(player: Player, _uid: string, rarity: number)
		local data = profile(player)
		if data ~= nil then
			addStat(player, data, "hatches", 1)
		end
		progress(player, "vatHatch", 1)
		if finite(rarity) and rarity >= Rarities.RARE then
			challengeProgress(player, "rareHatches", 1)
		end
	end)
	on(Signals.SquishyObtained, "quest:obtained", function(player: Player, uid: string, source: string)
		local ok, rec = pcall(SquishyService.get, player, uid)
		if not ok or type(rec) ~= "table" then
			return
		end
		-- Plop de départ (cadeau scripté de la seconde 0) : tamponné sans carte « Nouveau ! »
		QuestService.stamp(player, rec.s, rec.m, rec.st, source == "starter")
		local def = Species.ById[rec.s]
		if def and def.rarity >= Rarities.RARE and source ~= "fusion" then
			progress(player, "rareGet", 1)
		end
	end)
	on(Signals.Caught, "quest:caught", function(player: Player, info: any)
		if type(info) ~= "table" then
			return
		end
		local data = profile(player)
		if data == nil then
			return
		end
		addStat(player, data, "catches", 1)
		if info.hero == true then
			addStat(player, data, "heroCatches", 1)
		end
		local kind = info.kind
		if kind == "runaway" or kind == "escape" then
			progress(player, "runawayCatch", 1)
			challengeProgress(player, "catches", 1)
		end
		if kind == "wild" or kind == "wildPersonal" then
			progress(player, "wildCatch", 1)
		end
		if kind == "escape" or kind == "wild" or kind == "wildPersonal" then
			progress(player, "rushCatchOrBoop", 1)
		end
		if kind == "golden" then
			progress(player, "goldenRace", 1)
		end
		if kind == "demo" then
			local onboarding = onboardingOf(data)
			if onboarding.demoDone ~= true then
				onboarding.demoDone = true
				DataService.markDirty(player, "onboarding")
			end
		end
		reach(player, 7)
	end)
	on(Signals.NearCatch, "quest:near", function(player: Player, kind: string)
		if kind == "golden" then
			progress(player, "goldenRace", 1)
		end
	end)
	on(Signals.Booped, "quest:booped", function(booper: Player, owner: Player)
		local data = profile(booper)
		if data ~= nil then
			addStat(booper, data, "boops", 1)
		end
		progress(booper, "rushCatchOrBoop", 1)
		local ownerData = profile(owner)
		if ownerData ~= nil then
			local stats = statsOf(ownerData)
			addStat(owner, ownerData, "booped", 1)
			if num(stats.firstBoopReceivedAt, 0) <= 0 then
				stats.firstBoopReceivedAt = math.max(1, math.floor(playOf(ownerData)))
				Analytics.custom(owner, "FirstBoopReceived", stats.firstBoopReceivedAt)
			end
		end
	end)
	on(Signals.MegaJoined, "quest:mega", function(player: Player, points: number)
		if finite(points) and points >= Events.Mega.MinPoints then
			local data = profile(player)
			if data ~= nil then
				addStat(player, data, "megas", 1)
			end
			progress(player, "megaJoin", 1)
			challengeProgress(player, "megas", 1)
		end
	end)
	on(Signals.Splorched, "quest:splorched", function(player: Player)
		local data = profile(player)
		if data ~= nil then
			addStat(player, data, "splorches", 1)
		end
		progress(player, "splorch", 1)
		-- Défi « Fais 2 Grands Splorch » : Splorched = Grand Splorch seulement (lot A4, D3), donc un Grand
		-- Splorch qui bat le Record R (chemin de la v1.3 comme de la v2.0)
		challengeProgress(player, "splorches", 1)
		reach(player, 11)
	end)
	on(Signals.FriendsChanged, "quest:friends", function(player: Player, n: number)
		local s = sessionOf(player)
		local count = if finite(n) then math.max(0, math.floor(n)) else 0
		if s ~= nil then
			s.friends = count
		end
		local data = profile(player)
		if data ~= nil and count > 0 then
			local stats = statsOf(data)
			local today = Clock.day()
			if stats.lastFriendDay ~= today then
				stats.lastFriendDay = today
				DataService.markDirty(player, "stats")
			end
		end
	end)
	on(Signals.PetSitRewarded, "quest:petSit", function(visitor: Player)
		progress(visitor, "petSitPress", 1)
	end)
	-- v2.0 (lot A4, étape 4) : signaux du contrat v2 (jamais émis tant que leurs interrupteurs sont coupés,
	-- sauf UpgradeBought, aussi émis par BuyTile : profil v1 jamais écrit)
	on(Signals.Stamped, "quest:stamped", function(player: Player, gained: number)
		challengeProgress(player, "newStamps", gained)
	end)
	on(Signals.Fed, "quest:fed", function(player: Player)
		challengeProgress(player, "feedDays", 1)
	end)
	on(Signals.UpgradeBought, "quest:upgrade", function(player: Player, _id: string, from: number, to: number)
		local data = profile(player)
		if data == nil or not isV2(data) or not finite(from) or not finite(to) then
			return
		end
		local n = math.floor(to) - math.floor(from)
		if n < 1 then
			return
		end
		-- Carnet du Ranch (D34) : niveaux achetés à vie, × 10 et Max compris
		addLifetime(player, data, "upgradesBought", n)
		carnetCheck(player, data, false)
		challengeProgress(player, "upgradesBought", n)
	end)
	on(Signals.PrestigeApplied, "quest:prestige", function(player: Player, kind: string)
		local data = profile(player)
		if data == nil then
			return
		end
		if kind == "petit" then
			-- un Petit Splorch ne compte nulle part ailleurs (GDD §7.5 m9)
			addLifetime(player, data, "petitSplorches", 1)
		elseif kind == "ascend" then
			challengeProgress(player, "ascends", 1)
		end
		local s = sessionOf(player)
		if s ~= nil then
			-- nouvelle boucle : étapes du record remises à zéro (D14)
			s.stepKey = -1
			s.stepShown = 0
		end
	end)
	on(Signals.RecordReached, "quest:record", function(player: Player)
		local data = profile(player)
		if data == nil then
			return
		end
		challengeProgress(player, "recordBeaten", 1)
		recordCards(player, data, false)
	end)
	on(Signals.ConfettiChanged, "quest:confetti", function(player: Player, delta: number, source: string)
		-- Défi « Gagne 20 Confettis » : gains seulement, jamais ceux de la piste (aucune boucle sur soi)
		if finite(delta) and delta > 0 and source ~= "track" then
			challengeProgress(player, "confettiEarned", delta)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("quest:removing", onRemoving, player)
	end)
	-- un maintien du bol annule l'attente sur une dalle (RanchService, rang plus précoce)
	if type((RanchService :: any).setHoldCheck) == "function" then
		Guard.try("quest:holdCheck", RanchService.setHoldCheck, "feed", function(player: Player): boolean
			local s = sessions[player]
			return s ~= nil and s.feed ~= nil
		end)
	end
	-- joueurs déjà prêts avant le branchement
	for _, player in Players:GetPlayers() do
		local ok, ready = pcall(RanchService.isReady, player)
		if ok and ready == true then
			Guard.try("quest:ready", onReady, player)
		end
	end
end

local function stepPlayer(player: Player, s: Session, now: number)
	local data = profile(player)
	if data == nil or not s.ready then
		return
	end
	local dt = math.clamp(now - s.last, 0, MAX_DT)
	s.last = now
	local stats = statsOf(data)
	local play = math.max(0, num(stats.playSeconds, 0)) + dt
	stats.playSeconds = play
	s.play += dt
	s.dirtyAcc += dt
	if s.dirtyAcc >= STATS_DIRTY_EVERY then
		s.dirtyAcc = 0
		DataService.markDirty(player, "stats")
	end
	-- part de la session en ×2 (échantillonnée une fois par seconde)
	s.boostAcc += dt
	if s.boostAcc >= BOOST_SAMPLE then
		local ok, on = pcall(EconomyService.boostActive, player)
		if ok and on == true then
			s.boostSeconds += s.boostAcc
		end
		s.boostAcc = 0
	end
	-- v2.0 (lot A4) : profil v1 = une lecture, rien d'autre
	if s.v2 then
		stepV2(player, data, s, dt)
	end

	-- Plop de départ (premier squishy du compte, jamais redonné)
	if s.starterDue then
		s.starterDue = false
		giveStarter(player, data)
	end

	-- accueil
	local onboarding = onboardingOf(data)
	local step = num(onboarding.step, 0)
	if onboarding.done ~= true then
		if step < 4 and play >= ONB.TwinAt then
			Guard.try("quest:twin", SquishyService.hatchScripted, player, "twin")
			reach(player, 4)
		end
		if num(onboarding.step, 0) < 8 and play >= ONB.FirstPullAt then
			Guard.try("quest:firstPull", SquishyService.hatchScripted, player, "firstPull")
			reach(player, 8)
		end
		if num(onboarding.step, 0) < 9 then
			local ok, riding = pcall(SquishyService.riding, player)
			if ok and riding == true then
				reach(player, 9)
			end
		end
		if not s.cardSent and num(onboarding.step, 0) < 10 and play >= ONB.ObjectivesAt then
			s.cardSent = true
			Notify.celebrate(player, "objectivesCard", { day = num(objectivesOf(data).day, Clock.day()) })
		end
		local stepNow = num(onboarding.step, 0)
		if (stepNow >= 10 and play >= ONB.ScriptUntil) or play >= QUIET_SAFETY then
			onboarding.done = true
			s.stepAt = nil
			DataService.markDirty(player, "onboarding")
			refreshBuild(player)
		end
	end
	if onboarding.demoDone ~= true and play >= ONB.DemoAt + Events.Demo.Duration + ONB.StepTimeout then
		-- démonstration jouée (ou manquée) : jamais rejouée
		onboarding.demoDone = true
		DataService.markDirty(player, "onboarding")
	end
	-- consigne rangée après 90 s (le client la remontre ; l'accueil continue)
	local stepAt = s.stepAt
	if stepAt ~= nil and now - stepAt >= ONB.StepTimeout then
		s.stepAt = nil
	end

	-- carte « Plop a sommeil »
	for _, at in Quests.Sleepy.At do
		if s.play >= at and not s.sleepy[at] then
			s.sleepy[at] = true
			Notify.celebrate(player, "sleepy", { minutes = math.floor(at / 60) })
			Analytics.custom(player, "SleepyCardShown", math.floor(at / 60))
		end
	end

	-- minuit en session
	local today = Clock.day()
	if today ~= s.day then
		s.day = today
		if num(objectivesOf(data).day, 0) ~= today then
			midnight(player, data, s)
		end
	end

	-- maintien du bol
	local feed = s.feed
	if feed ~= nil then
		if not finite(feed.endsAt) or not finite(feed.startedAt) then
			-- état illisible : fermé par son délai (aurait dû finir seul)
			s.feed = nil
			sendHold(player, 0, false)
			Guard.try("quest:timedOut", DiagnosticsService.stateTimedOut, "feedHold", player)
		elseif not nearBowl(player) then
			cancelFeed(player, s) -- sortie de zone : annulé
		elseif now >= feed.endsAt then
			completeFeed(player, data, s)
		end
	end
end

-- Tick : temps de jeu, délais de l'accueil, script (jumeau, premier tirage), minuit, carte sommeil, maintien du bol
function QuestService.step(now: number)
	local t = if finite(now) then now else Clock.now()
	for player, s in sessions do
		Guard.try("quest:step", stepPlayer, player, s, t)
	end
end

-- v2.0 (lot A4, étape 5) : crochet appelé après chaque compteur à vie écrit d'un profil v2
-- (stats.upgradesBought, petitSplorches, objectivesClaimed, tracksDone) : fn(player, clé). CommunityService
-- y revoit la Déco perso (objets « 25 / 100 objectifs », « 1 / 4 pistes », Carnet 750 / 7 500)
function QuestService.onLifetime(fn: (Player, string) -> ())
	if type(fn) == "function" then
		table.insert(lifetimeHooks, fn)
	end
end

-- Étape d'accueil atteinte (0 … 11)
function QuestService.stage(player: Player): number
	local data = profile(player)
	if data == nil then
		return 0
	end
	return math.clamp(math.floor(num(onboardingOf(data).step, 0)), 0, #ONB.Steps)
end

-- Événements discrets pour ce nouveau (avant l'étape 9)
function QuestService.isNewcomerQuiet(player: Player): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local onboarding = onboardingOf(data)
	if onboarding.done == true then
		return false
	end
	return num(onboarding.step, 0) < ONB.EventsQuietUntilStep and playOf(data) < QUIET_SAFETY
end

-- Jeu cumulé
function QuestService.playSeconds(player: Player): number
	local data = profile(player)
	if data == nil then
		return 0
	end
	return playOf(data)
end

-- Horaires scriptés de l'accueil pour ChaseService et SquishyService
function QuestService.script(player: Player): OnboardingScript
	local data = profile(player)
	if data == nil then
		return { active = false, runawayAt = nil, demoAt = nil, runawayPaused = false, vatScripted = false }
	end
	local onboarding = onboardingOf(data)
	local play = playOf(data)
	local step = num(onboarding.step, 0)
	local active = onboarding.done ~= true and play < ONB.ScriptUntil
	return {
		active = active,
		runawayAt = if active and step < 7 then ONB.RunawayAt else nil,
		demoAt = if onboarding.demoDone ~= true then ONB.DemoAt else nil,
		runawayPaused = active and play >= ONB.VatPauseFrom and play < ONB.VatPauseUntil,
		vatScripted = active,
	}
end

-- Tamponne le Squishydex (vrai si nouvelle entrée) ; Celebrate "dexNew"
function QuestService.stamp(
	player: Player,
	species: number,
	mutation: number,
	stars: number,
	silent: boolean?
): boolean
	local data = profile(player)
	if data == nil or type(data.dex) ~= "table" then
		return false
	end
	if not finite(species) or species % 1 ~= 0 or Species.ById[species] == nil then
		return false
	end
	local dex = data.dex
	if type(dex.mut) ~= "table" or type(dex.stars) ~= "table" then
		return false
	end
	-- jamais un trou : une espèce au-delà de la première case libre est ignorée
	if species > #dex.mut + 1 or species > #dex.stars + 1 then
		return false
	end
	local m = if finite(mutation) and Mutations.ById[mutation] then mutation else 0
	local st = math.clamp(math.floor(num(stars, 0)), 0, Quests.Dex.StarBadges)
	if not QuestRules.isNewStamp(dex, species, m, st) then
		return false
	end
	denseTo(dex.mut, species)
	denseTo(dex.stars, species)
	local before = QuestRules.stampCount(dex) + QuestRules.starBadges(dex)
	local bits = 1
	if m > 0 then
		bits = bit32.bor(bits, bit32.lshift(1, m))
	end
	dex.mut[species] = bit32.bor(math.floor(num(dex.mut[species], 0)) % 4294967296, bits)
	if st > 0 then
		dex.stars[species] =
			bit32.bor(math.floor(num(dex.stars[species], 0)) % 4294967296, bit32.lshift(1, st) - 1)
	end
	local gained = math.max(0, QuestRules.stampCount(dex) + QuestRules.starBadges(dex) - before)
	-- bonus de famille gagné pour toujours
	local family = familyOf(species)
	if family ~= nil and QuestRules.familyComplete(dex, family) then
		local index = table.find(Species.FamilyOrder, family :: any)
		if index ~= nil then
			if type(dex.fam) ~= "table" then
				dex.fam = {}
			end
			denseTo(dex.fam, #Species.FamilyOrder)
			if dex.fam[index] ~= 1 then
				dex.fam[index] = 1
			end
		end
	end
	DataService.markDirty(player, "dex")
	if not silent then
		Notify.celebrate(player, "dexNew", { species = species, mutation = m, star = st })
	end
	if gained > 0 then
		Signals.Stamped:Fire(player, gained)
		progress(player, "stamps", gained)
	end
	Guard.try("quest:refresh", EconomyService.refresh, player)
	return true
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « feedHold » (maintien du bol), « onboardingStep » (consigne en cours) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function QuestService.openStates(): { { name: string, startedAt: number, player: Player? } }
	local out = {}
	for player, s in sessions do
		if s.feed ~= nil then
			table.insert(out, { name = "feedHold", startedAt = s.feed.startedAt, player = player })
		end
		if s.stepAt ~= nil then
			table.insert(out, { name = "onboardingStep", startedAt = s.stepAt, player = player })
		end
	end
	return out
end

return QuestService
