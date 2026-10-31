--!strict
-- CrewService — paquet « events » (docs/04-architecture.md §11.9).
-- Équipages (mémoire), escorte, pings, acclamations, file des bannières de serveur, cadeau Duo.
-- Responsabilités :
--   * équipages de 4 max : formation automatique des amis Roblox présents (réglage autoCrew des
--     DEUX joueurs, Player:IsFriendsWith en pcall, résultat en cache) ; remotes CrewInvite(userId)
--     1/3 s et 5/min, CrewRespond(inviterId, accept) 2/s (invitation de 20 s), CrewLeave() 1/5 s ;
--     refus si refuseInvites ; départ du serveur = départ de l'équipage ; un équipage d'un seul
--     membre est dissous ; CrewState à tous à chaque changement (et à l'arrivée) ; attribut Player
--     « CrewId » ; Signals.CrewChanged ; EconomyService.setCrewPresent pour chaque membre
--     (équipiers présents ET actifs, ≤ 3) ; Analytics CrewFormed
--   * escorte : API escortersOf(victim) utilisée par CongaService (le calcul géométrique et le temps
--     d'escorte sont faits par CongaService, qui possède les nœuds)
--   * pings : remote Ping(kind 1-6) 1/1,5 s → PingShow à tous
--   * acclamations : sur Signals.Supernova, CheerPrompt à tous sauf le héros (fenêtre 10 s) ;
--     remote Cheer(heroId) 2/s : une fois par héros et par Supernova ; +5 Stardust plafonnée
--     (cheers, 10/jour) ; Signals.Cheered ; Feedback « N joueurs t'acclament » au héros à la fermeture
--   * bannières : écoute Signals.BannerRequested ; une même source au plus 1 / 10 s ; file de 3 max
--     triée par priorité (Notify.BANNER_PRIORITY) ; une bannière diffusée toutes les 3 s (step)
--   * cadeau Duo : 10 min cumulées sur le même serveur qu'un ami Roblox → 50 Stardust aux deux
--     (plafond caps.duo, une fois par jour UTC)
--   * activité des joueurs (≥ 4 studs en 60 s, mesurée ici chaque seconde) pour le bonus d'équipage
-- GDD : §6.1-§6.3, §6.5, §6.6, §14.3.
-- Dépendances : DataService, NestService (réglages, slot), EconomyService, Signals, Util/Notify,
-- Util/RateLimit, Util/Analytics, Config/Balance, Shared/Util/Clock, Events/Safe, Events/Tuning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Analytics = require(Server.Util.Analytics)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local Safe = require(Server.Events.Safe)
local Tuning = require(Server.Events.Tuning)

local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)
local EconomyService = require(script.Parent.EconomyService)

local CrewService = {}

local CrewCfg = Balance.Crew
local TAG = "CrewService"

-- Débits des remotes (docs §10.1)
local RATE = {
	invite = { n = 1, per = CrewCfg.InviteCooldown },
	inviteMinute = { n = CrewCfg.InvitesPerMinute, per = 60 },
	respond = { n = 2, per = 1 },
	leave = { n = 1, per = CrewCfg.LeaveCooldown },
	ping = { n = 1, per = Balance.Ping.Cooldown },
	cheer = { n = 2, per = 1 },
}

-- ---------------------------------------------------------------------------------------------
-- État (mémoire)
-- ---------------------------------------------------------------------------------------------

type Crew = { id: number, members: { Player } }

type CheerWindow = {
	hero: Player,
	level: number,
	expiresAt: number,
	cheered: { [Player]: boolean },
	count: number,
}

type QueuedBanner = {
	kind: Types.BannerKind,
	args: { [string]: any },
	priority: number,
	seq: number,
	source: Player?, -- joueur à l'origine (limite de 1 bannière / 10 s), nil = événement
}

-- Dernière bannière acceptée d'un joueur source (instant, priorité)
type SourceMark = { at: number, priority: number }

type DuoPair = { a: number, b: number, seconds: number, given: boolean, day: number }

type Activity = { anchor: Vector3?, movedAt: number }

local remotes: { [string]: RemoteEvent } = {}

local crews: { [number]: Crew } = {}
local crewOfPlayer: { [Player]: number } = {}
local nextCrewId = 1

local invites: { [Player]: { [number]: number } } = {} -- cible → { [UserId de l'inviteur] = expiresAt }
local friendCache: { [string]: boolean } = {}
local duoPairs: { [string]: DuoPair } = {}
local cheers: { [number]: CheerWindow } = {} -- UserId du héros → fenêtre

local bannerQueue: { QueuedBanner } = {}
local bannerSeq = 0
local lastBannerAt = -math.huge
local lastBySource: { [Player]: SourceMark } = {}

-- UserIds acceptés par les remotes (GetPlayerByUserId convertit en int64 : un nombre hors de cette
-- plage ferait échouer le handler)
local MAX_USER_ID = 2 ^ 53

local activity: { [Player]: Activity } = {}
local crewPresentSent: { [Player]: number } = {}
local lastSlowAt = 0 -- dernier passage lent de step (0 = jamais)

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function remote(name: string): RemoteEvent
	local r = remotes[name]
	if r == nil then
		r = Net.event(name)
		remotes[name] = r
	end
	return r
end

local function pairKey(a: number, b: number): string
	if a < b then
		return `{a}:{b}`
	end
	return `{b}:{a}`
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

local function loaded(player: Player): boolean
	return player.Parent ~= nil and DataService.isLoaded(player)
end

local function settingOn(player: Player, key: string): boolean
	return Safe.value(TAG .. ".setting", false, NestService.setting, player, key) == true
end

local function crewOf(player: Player): Crew?
	local id = crewOfPlayer[player]
	return if id then crews[id] else nil
end

local function isActive(player: Player, now: number): boolean
	local act = activity[player]
	return act ~= nil and now - act.movedAt <= Balance.Spawn.ActiveWindow
end

-- Bonus d'équipage : équipiers présents et actifs (≤ BonusMaxMates), poussé à EconomyService
local function refreshBonus(player: Player, now: number)
	if player.Parent == nil then
		return
	end
	local n = 0
	local crew = crewOf(player)
	if crew then
		for _, m in crew.members do
			if m ~= player and m.Parent ~= nil and isActive(m, now) then
				n += 1
			end
		end
	end
	n = math.min(n, CrewCfg.BonusMaxMates)
	if crewPresentSent[player] ~= n then
		crewPresentSent[player] = n
		Safe.call(TAG .. ".setCrewPresent", EconomyService.setCrewPresent, player, n)
	end
end

local function refreshAllBonuses(now: number)
	for _, player in Players:GetPlayers() do
		refreshBonus(player, now)
	end
end

-- Diffuse un changement d'équipage : attributs, signal, bonus, CrewState à tous
local function publish(changed: { Player })
	local now = Clock.now()
	local seen: { [Player]: boolean } = {}
	local list: { Player } = {}
	for _, p in changed do
		if not seen[p] then
			seen[p] = true
			table.insert(list, p)
			if p.Parent ~= nil then
				p:SetAttribute("CrewId", crewOfPlayer[p] or 0)
			end
		end
	end
	Signals.CrewChanged:Fire(list)
	refreshAllBonuses(now)
	remote("CrewState"):FireAllClients(CrewService.snapshot())
end

-- Retire un joueur de son équipage ; dissout un équipage réduit à un membre.
-- Retourne les joueurs touchés (vide si le joueur n'avait pas d'équipage).
local function removeFromCrew(player: Player): { Player }
	local id = crewOfPlayer[player]
	if id == nil then
		return {}
	end
	crewOfPlayer[player] = nil
	local affected = { player }
	local crew = crews[id]
	if crew then
		local index = table.find(crew.members, player)
		if index then
			table.remove(crew.members, index)
		end
		for _, m in crew.members do
			table.insert(affected, m)
		end
		if #crew.members <= 1 then
			for _, m in crew.members do
				crewOfPlayer[m] = nil
			end
			crews[id] = nil
		end
	end
	return affected
end

-- `guest` rejoint l'équipage de `host` (créé s'il n'existe pas). Faux si plein ou déjà ensemble.
local function joinTogether(host: Player, guest: Player): boolean
	if host == guest or host.Parent == nil or guest.Parent == nil then
		return false
	end
	local hostId = crewOfPlayer[host]
	if hostId ~= nil and crewOfPlayer[guest] == hostId then
		return false
	end
	local hostCrew = if hostId then crews[hostId] else nil
	if hostCrew and #hostCrew.members >= CrewCfg.MaxSize then
		return false
	end
	local affected = removeFromCrew(guest)
	-- l'équipage de l'hôte a pu être dissous si l'invité en faisait partie (impossible ici) :
	-- on relit l'état après le retrait
	hostId = crewOfPlayer[host]
	hostCrew = if hostId then crews[hostId] else nil
	if hostCrew == nil then
		local id = nextCrewId
		nextCrewId += 1
		hostCrew = { id = id, members = { host } }
		crews[id] = hostCrew :: Crew
		crewOfPlayer[host] = id
	end
	local crew = hostCrew :: Crew
	table.insert(crew.members, guest)
	crewOfPlayer[guest] = crew.id
	for _, m in crew.members do
		table.insert(affected, m)
	end
	publish(affected)
	Analytics.event(guest, "CrewFormed", #crew.members)
	-- « Équipage formé » (GDD §9.4) : un toast avec les deux noms, pour une invitation acceptée
	-- comme pour un équipage automatique d'amis
	for _, m in crew.members do
		if m ~= guest then
			Notify.feedback(m, "feedback.crewJoined", { name = guest.DisplayName }, "success")
		end
	end
	Notify.feedback(guest, "feedback.crewWelcome", { name = host.DisplayName }, "success")
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Amis Roblox : équipages automatiques et cadeau Duo
-- ---------------------------------------------------------------------------------------------

-- Amitié (yield : IsFriendsWith en pcall ; le résultat est mis en cache, pas les échecs)
local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	if not ok then
		warn("[CrewService] IsFriendsWith :", result)
		return false
	end
	local friends = result == true
	friendCache[key] = friends
	return friends
end

local function registerDuo(a: Player, b: Player)
	local key = pairKey(a.UserId, b.UserId)
	if duoPairs[key] == nil then
		duoPairs[key] = {
			a = math.min(a.UserId, b.UserId),
			b = math.max(a.UserId, b.UserId),
			seconds = 0,
			given = false,
			day = Clock.day(),
		}
	end
end

-- Équipage automatique entre deux amis qui ont tous deux « Équipage auto » activé
local function autoJoin(player: Player, friend: Player)
	if not (loaded(player) and loaded(friend)) then
		return
	end
	if not (settingOn(player, "autoCrew") and settingOn(friend, "autoCrew")) then
		return
	end
	if CrewService.areCrewmates(player, friend) then
		return
	end
	local mine = crewOf(player)
	local theirs = crewOf(friend)
	if mine == nil then
		-- rejoint l'équipage de l'ami s'il a de la place, sinon en crée un avec lui
		if theirs == nil or #theirs.members < CrewCfg.MaxSize then
			joinTogether(friend, player)
		end
	elseif theirs == nil and #mine.members < CrewCfg.MaxSize then
		joinTogether(player, friend)
	end
end

local function checkFriends(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player and player.Parent ~= nil and other.Parent ~= nil then
			if areFriends(player, other) and player.Parent ~= nil and other.Parent ~= nil then
				registerDuo(player, other)
				autoJoin(player, other)
			end
		end
	end
end

local function stepDuo(now: number, dt: number)
	local today = Clock.day(now)
	for _, pair in duoPairs do
		if pair.day ~= today then
			pair.day = today
			pair.seconds = 0
			pair.given = false
		end
		local a = Players:GetPlayerByUserId(pair.a)
		local b = Players:GetPlayerByUserId(pair.b)
		if a and b and loaded(a) and loaded(b) then
			pair.seconds += dt
			if not pair.given and pair.seconds >= CrewCfg.DuoSeconds then
				pair.given = true
				for _, entry in { { a, b }, { b, a } } do
					local me, other = entry[1], entry[2]
					local dust = Safe.value(
						TAG .. ".duo",
						0,
						EconomyService.addStardustCapped,
						me,
						CrewCfg.DuoDust,
						"duo",
						"Duo"
					)
					if dust > 0 then
						Notify.feedback(
							me,
							"feedback.duoGift",
							{ name = other.DisplayName, dust = dust },
							"reward"
						)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Bannières de serveur (GDD §6.5, docs §10.3)
-- ---------------------------------------------------------------------------------------------

-- Copie sûre des arguments (clés chaînes, valeurs simples) : charge utile toujours valide
local function cleanArgs(args: unknown): { [string]: any }
	local out: { [string]: any } = {}
	if type(args) ~= "table" then
		return out
	end
	for k, v in args :: { [any]: any } do
		local t = type(v)
		if type(k) == "string" and (t == "string" or t == "boolean" or (t == "number" and v == v)) then
			if t ~= "number" or (v ~= math.huge and v ~= -math.huge) then
				out[k] = v
			end
		end
	end
	return out
end

local function pumpBanners(now: number)
	if #bannerQueue == 0 or now - lastBannerAt < Tuning.BannerInterval then
		return
	end
	local entry = table.remove(bannerQueue, 1) :: QueuedBanner
	lastBannerAt = now
	local payload: Types.BannerPayload = { kind = entry.kind, args = entry.args, priority = entry.priority }
	remote("Banner"):FireAllClients(payload)
end

local function enqueueBanner(kind: unknown, args: unknown, source: unknown)
	if type(kind) ~= "string" then
		return
	end
	local priority = Notify.BANNER_PRIORITY[kind]
	if priority == nil then
		return
	end
	local now = Clock.now()
	local sourcePlayer: Player? = nil
	if typeof(source) == "Instance" and (source :: Instance):IsA("Player") then
		local player = source :: Player
		local last = lastBySource[player]
		-- un même joueur : au plus une bannière toutes les 10 s… sauf une PLUS prioritaire, qui
		-- n'est jamais avalée par une moins importante (Supernova dont la parade forcée vient de
		-- déclencher « Méga Parade » ou « record du serveur », GDD §6.5)
		if last ~= nil and now - last.at < Tuning.BannerSourceCooldown and priority >= last.priority then
			return
		end
		if player.Parent ~= nil then
			lastBySource[player] = { at = now, priority = priority }
		end
		sourcePlayer = player
		-- une bannière moins prioritaire du même joueur encore en attente cède sa place
		for i = #bannerQueue, 1, -1 do
			local queued = bannerQueue[i]
			if queued.source == player and queued.priority > priority then
				table.remove(bannerQueue, i)
			end
		end
	end
	bannerSeq += 1
	table.insert(bannerQueue, {
		kind = kind :: Types.BannerKind,
		args = cleanArgs(args),
		priority = priority,
		seq = bannerSeq,
		source = sourcePlayer,
	})
	table.sort(bannerQueue, function(x, y)
		if x.priority ~= y.priority then
			return x.priority < y.priority
		end
		return x.seq < y.seq
	end)
	while #bannerQueue > Tuning.BannerQueueMax do
		table.remove(bannerQueue) -- la moins prioritaire (et la plus récente à priorité égale)
	end
	pumpBanners(now)
end

-- ---------------------------------------------------------------------------------------------
-- Acclamations (GDD §6.6)
-- ---------------------------------------------------------------------------------------------

local function closeCheers(heroId: number)
	local window = cheers[heroId]
	if window == nil then
		return
	end
	cheers[heroId] = nil
	if window.count > 0 and window.hero.Parent ~= nil then
		Notify.feedback(window.hero, "feedback.cheersReceived", { n = window.count }, "reward")
	end
end

local function onSupernova(hero: Player, level: number)
	if hero.Parent == nil or not Validate.finiteNumber(level) then
		return
	end
	closeCheers(hero.UserId)
	local now = Clock.now()
	local window: CheerWindow = {
		hero = hero,
		level = level,
		expiresAt = now + Balance.Cheer.Window,
		cheered = {},
		count = 0,
	}
	cheers[hero.UserId] = window
	local payload: Types.CheerPromptPayload =
		{ heroId = hero.UserId, level = level, expiresAt = window.expiresAt }
	local prompt = remote("CheerPrompt")
	for _, other in Players:GetPlayers() do
		if other ~= hero then
			prompt:FireClient(other, payload)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------------

local function onCrewInvite(player: Player, userId: unknown)
	if not RateLimit.allow(player, "CrewInvite", RATE.invite.n, RATE.invite.per) then
		return
	end
	if not RateLimit.allow(player, "CrewInviteMinute", RATE.inviteMinute.n, RATE.inviteMinute.per) then
		return
	end
	if not Validate.integer(userId, -MAX_USER_ID, MAX_USER_ID) then
		return
	end
	if not loaded(player) then
		return
	end
	local target = Players:GetPlayerByUserId(userId :: number)
	if target == nil or target == player or not loaded(target) then
		return
	end
	if CrewService.areCrewmates(player, target) then
		Notify.feedback(player, "feedback.crewAlready", nil, "info")
		return
	end
	local mine = crewOf(player)
	if mine and #mine.members >= CrewCfg.MaxSize then
		Notify.feedback(player, "feedback.crewFull", nil, "warning")
		return
	end
	if settingOn(target, "refuseInvites") then
		Notify.feedback(player, "feedback.crewRefuses", { name = target.DisplayName }, "info")
		return
	end
	local expiresAt = Clock.now() + CrewCfg.InviteTTL
	local pending = invites[target]
	if pending == nil then
		pending = {}
		invites[target] = pending
	end
	pending[player.UserId] = expiresAt
	local payload: Types.CrewInvitePayload = { inviterId = player.UserId, expiresAt = expiresAt }
	remote("CrewInvitePrompt"):FireClient(target, payload)
	Notify.feedback(player, "feedback.crewInviteSent", { name = target.DisplayName }, "success")
end

local function onCrewRespond(player: Player, inviterId: unknown, accept: unknown)
	if not RateLimit.allow(player, "CrewRespond", RATE.respond.n, RATE.respond.per) then
		return
	end
	if not Validate.integer(inviterId, -MAX_USER_ID, MAX_USER_ID) or not Validate.boolean(accept) then
		return
	end
	local pending = invites[player]
	local id = inviterId :: number
	local expiresAt = if pending then pending[id] else nil
	if pending == nil or expiresAt == nil then
		return -- aucune invitation de ce joueur : charge ignorée
	end
	pending[id] = nil
	if next(pending) == nil then
		invites[player] = nil
	end
	if not loaded(player) then
		return
	end
	local inviter = Players:GetPlayerByUserId(id)
	if expiresAt <= Clock.now() or inviter == nil or not loaded(inviter) then
		Notify.feedback(player, "feedback.crewExpired", nil, "info")
		return
	end
	if accept ~= true then
		Notify.feedback(inviter, "feedback.crewDeclined", { name = player.DisplayName }, "info")
		return
	end
	if CrewService.areCrewmates(player, inviter) then
		return
	end
	-- toasts « équipage formé » envoyés par joinTogether
	if not joinTogether(inviter, player) then
		Notify.feedback(player, "feedback.crewFull", nil, "warning")
	end
end

local function onCrewLeave(player: Player)
	if not RateLimit.allow(player, "CrewLeave", RATE.leave.n, RATE.leave.per) then
		return
	end
	if crewOfPlayer[player] == nil then
		return
	end
	local affected = removeFromCrew(player)
	publish(affected)
	Notify.feedback(player, "feedback.crewLeft", nil, "info")
end

local function onPing(player: Player, kind: unknown)
	if not RateLimit.allow(player, "Ping", RATE.ping.n, RATE.ping.per) then
		return
	end
	if not Validate.integer(kind, 1, Balance.Ping.Count) then
		return
	end
	if not loaded(player) then
		return
	end
	local payload: Types.PingPayload = { userId = player.UserId, kind = kind :: number }
	remote("PingShow"):FireAllClients(payload)
end

local function onCheer(player: Player, heroId: unknown)
	if not RateLimit.allow(player, "Cheer", RATE.cheer.n, RATE.cheer.per) then
		return
	end
	if not Validate.integer(heroId, -MAX_USER_ID, MAX_USER_ID) then
		return
	end
	local id = heroId :: number
	if id == player.UserId or not loaded(player) then
		return
	end
	local window = cheers[id]
	if window == nil or Clock.now() >= window.expiresAt or window.cheered[player] then
		return
	end
	window.cheered[player] = true
	window.count += 1
	local dust = Safe.value(
		TAG .. ".cheerDust",
		0,
		EconomyService.addStardustCapped,
		player,
		Balance.Cheer.Dust,
		"cheers",
		"Cheer"
	)
	if dust > 0 then
		Notify.feedback(player, "feedback.cheerReward", { dust = dust }, "reward")
	else
		Notify.feedback(player, "feedback.capReached", nil, "info")
	end
	Signals.Cheered:Fire(player, window.hero)
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if crewOfPlayer[player] == nil then
		player:SetAttribute("CrewId", 0)
	end
	remote("CrewState"):FireClient(player, CrewService.snapshot())
end

local function onLoaded(player: Player)
	if player.Parent == nil then
		return
	end
	task.spawn(checkFriends, player)
end

local function onPlayerRemoving(player: Player)
	local affected = removeFromCrew(player)
	if #affected > 0 then
		publish(affected)
	end
	invites[player] = nil
	for target, pending in invites do
		pending[player.UserId] = nil
		if next(pending) == nil then
			invites[target] = nil
		end
	end
	cheers[player.UserId] = nil
	lastBySource[player] = nil
	activity[player] = nil
	crewPresentSent[player] = nil
	-- caches par paire : sans nettoyage, ils grossiraient à chaque arrivée pendant toute la vie du
	-- serveur. Une paire Duo reste tant que l'autre ami est là (temps cumulé du jour).
	local userId = player.UserId
	for key, pair in duoPairs do
		if pair.a == userId or pair.b == userId then
			local other = if pair.a == userId then pair.b else pair.a
			local present = Players:GetPlayerByUserId(other)
			if present == nil or present == player then
				duoPairs[key] = nil
			end
		end
	end
	for key in friendCache do
		local a, b = string.match(key, "^(-?%d+):(-?%d+)$")
		if tonumber(a) == userId or tonumber(b) == userId then
			friendCache[key] = nil
		end
	end
end

function CrewService.Init()
	for _, name in { "CrewState", "CrewInvitePrompt", "CheerPrompt", "PingShow", "Banner" } do
		remotes[name] = Net.event(name)
	end
end

function CrewService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.Loaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			onPlayerAdded(player)
			if DataService.isLoaded(player) then
				onLoaded(player)
			end
		end)
	end

	Signals.BannerRequested:Connect(enqueueBanner)
	Signals.Supernova:Connect(onSupernova)
	Signals.SettingChanged:Connect(function(player: Player, key: string, value: any)
		if key == "autoCrew" and value == true then
			task.spawn(checkFriends, player)
		end
	end)

	remote("CrewInvite").OnServerEvent:Connect(onCrewInvite)
	remote("CrewRespond").OnServerEvent:Connect(onCrewRespond)
	remote("CrewLeave").OnServerEvent:Connect(onCrewLeave)
	remote("Ping").OnServerEvent:Connect(onPing)
	remote("Cheer").OnServerEvent:Connect(onCheer)
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Expirations des invitations et des fenêtres d'acclamation, file des bannières, temps Duo,
-- activité et bonus d'équipage (travail lent une fois par seconde)
function CrewService.step(now: number)
	if not Validate.finiteNumber(now) then
		return
	end
	pumpBanners(now)
	if lastSlowAt > 0 and now - lastSlowAt < Tuning.SlowStepInterval then
		return
	end
	local dt = if lastSlowAt > 0 then math.clamp(now - lastSlowAt, 0, Tuning.MaxStepGap) else 0
	lastSlowAt = now

	for heroId, window in cheers do
		if now >= window.expiresAt then
			closeCheers(heroId)
		end
	end
	for target, pending in invites do
		for inviterId, expiresAt in pending do
			if now >= expiresAt then
				pending[inviterId] = nil
			end
		end
		if next(pending) == nil then
			invites[target] = nil
		end
	end
	-- activité : ≥ ActiveDistance studs parcourus dans la fenêtre ActiveWindow
	for _, player in Players:GetPlayers() do
		local pos = rootPosition(player)
		local act = activity[player]
		if act == nil then
			act = { anchor = pos, movedAt = -math.huge }
			activity[player] = act
		end
		local a = act :: Activity
		if pos ~= nil then
			local anchor = a.anchor
			if anchor == nil then
				a.anchor = pos
			elseif (pos - anchor).Magnitude >= Balance.Spawn.ActiveDistance then
				a.anchor = pos
				a.movedAt = now
			end
		end
	end
	refreshAllBonuses(now)
	stepDuo(now, dt)
end

-- Identifiant d'équipage (0 = aucun)
function CrewService.crewOf(player: Player): number
	return crewOfPlayer[player] or 0
end

function CrewService.areCrewmates(a: Player, b: Player): boolean
	if a == b then
		return false
	end
	local id = crewOfPlayer[a]
	return id ~= nil and crewOfPlayer[b] == id
end

-- Équipiers présents (sans le joueur lui-même)
function CrewService.crewmates(player: Player): { Player }
	local out: { Player } = {}
	local crew = crewOf(player)
	if crew then
		for _, m in crew.members do
			if m ~= player and m.Parent ~= nil then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- Équipiers de la victime qui peuvent escorter sa file (présents ; la distance de 7 studs et le
-- temps d'escorte sont calculés par CongaService)
function CrewService.escortersOf(victim: Player): { Player }
	return CrewService.crewmates(victim)
end

-- Diffuse une bannière (même chemin que Signals.BannerRequested)
function CrewService.banner(kind: Types.BannerKind, args: { [string]: any }, source: Player?)
	enqueueBanner(kind, args, source)
end

function CrewService.snapshot(): Types.CrewStatePayload
	local ids: { number } = {}
	for id in crews do
		table.insert(ids, id)
	end
	table.sort(ids)
	local list: { Types.CrewEntry } = {}
	for _, id in ids do
		local userIds: { number } = {}
		for _, m in crews[id].members do
			table.insert(userIds, m.UserId)
		end
		table.insert(list, { id = id, userIds = userIds })
	end
	return { crews = list }
end

-- File de bannières en attente (tests, diagnostic)
-- Taille des caches par paire (tests, diagnostic : ils ne doivent pas croître sans fin)
function CrewService.debugCounts(): { friendCache: number, duoPairs: number }
	local friends, duos = 0, 0
	for _ in friendCache do
		friends += 1
	end
	for _ in duoPairs do
		duos += 1
	end
	return { friendCache = friends, duoPairs = duos }
end

function CrewService.queuedBanners(): { Types.BannerPayload }
	local out: { Types.BannerPayload } = {}
	for _, b in bannerQueue do
		table.insert(out, { kind = b.kind, args = b.args, priority = b.priority })
	end
	return out
end

return CrewService
