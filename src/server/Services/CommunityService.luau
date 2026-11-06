--!strict
-- CommunityService (paquet meta, docs/04 §11.8) — social sans chat (GDD §6).
--   * Amis : à chaque arrivée et départ, amis Roblox présents de chaque joueur (IsFriendsWith sous
--     pcall, hors du tick, en cache pour la session) → EconomyService.setFriendsPresent et
--     Signals.FriendsChanged quand le nombre change.
--   * Pet-sitting (step, hors Rush) : un ami côté rue à ≤ 10 studs de la clôture → jusqu'à 3 squishies
--     prêts à la clôture (RanchService.setFence(slot, uids, "petsit"), liste stable) ; libérés quand
--     l'ami s'en va (setFence(slot, {}, "petsit") : sans effet sur une clôture du Rush) ; réappliqués au
--     step qui suit la fin du Rush. PetPress : plafonds vérifiés SANS consommer (caps.petSit du visiteur
--     < 100, caps.petSitIn du propriétaire < 100), puis SquishyService.press(propriétaire, uid, tClient,
--     visiteur) (portée à plat 10 + 2 de la place à la clôture, pieds) ; réussie : consumeCap des deux,
--     Rewards.PetSitVisitor s de revenu au visiteur (× 2 si PERFECT), helpful = consumeFriendCap(…) > 0,
--     Signals.PetSitRewarded(visiteur, propriétaire, helpful).
--   * Emotes (EmoteShow à tous, Signals.Emoted), applaudissements (openClapWindow : ClapPrompt aux seuls
--     spectateurs ; Clap seulement d'eux, une fois, 10 s de revenu dans caps.claps, Celebrate
--     « clapCount » au héros), file des bannières (3 au plus, 3 s, priorité, 10 s par joueur source,
--     nouveaux avant l'étape 9 : mises en attente, jetées après 30 s), réglages (SetSetting), nom caché,
--     cosmétiques (EquipCosmetic, hasCosmetic, déblocages de session), liste de blocage souple.
-- Remplit Notify.BANNER_PRIORITY depuis Config/Events à Init. Émet Emoted, SettingChanged,
-- FriendsChanged, PetSitRewarded. Remotes : PetPress, SetSetting, EquipCosmetic, Emote, Clap,
-- ReportBlocked ; EmoteShow, ClapPrompt, Banner. Clés : settings, cosmetics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Settings = require(Shared.Config.Settings)
local Cosmetics = require(Shared.Config.Cosmetics)
local Features = require(Shared.Config.Features)
local ZoneRules = require(Shared.Logic.ZoneRules)
local StateTimeouts = require(Shared.Logic.StateTimeouts)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Analytics = require(Server.Util.Analytics)
local Guard = require(Server.Meta.Guard)
local DataService = require(Server.Services.DataService)
local MonetizationService = require(Server.Services.MonetizationService)
local RanchService = require(Server.Services.RanchService)
local EconomyService = require(Server.Services.EconomyService)
local SquishyService = require(Server.Services.SquishyService)
local QuestService = require(Server.Services.QuestService)

local CommunityService = {}

local BANNERS = Events.Banners
local PETSIT_RADIUS = Balance.Press.Range -- ami côté rue à ≤ 10 studs de la clôture (GDD §6.4)
local PETSIT_MAX = 3
local PETSIT_EVERY = 0.5 -- s : clôtures de pet-sitting réévaluées deux fois par seconde
local CLAP_SECONDS = StateTimeouts.seconds("clapWindow")
local ANALYTICS_EVERY = 300 -- s : PetSitPress cumulé (une requête par 5 min au plus)

type ClapWindow = {
	hero: Player,
	startedAt: number,
	endsAt: number,
	viewers: { [Player]: boolean }?, -- nil = tous les autres joueurs
	clapped: { [Player]: boolean },
	count: number,
}

type Banner = { kind: string, args: { [string]: any }, priority: number, at: number, seq: number }

local friendCache: { [string]: boolean } = {} -- "<petit id>:<grand id>" → amis
local friendCount: { [Player]: number } = {}
local blocked: { [Player]: { [number]: boolean } } = {}
local unlocks: { [Player]: { [string]: boolean } } = {}
local clapWindows: { [Player]: ClapWindow } = {}
local queue: { Banner } = {}
local bannerSeq = 0
local currentUntil = 0
local lastBySource: { [number]: number } = {}
local pendingNew: { [Player]: { Banner } } = {}
local lastPending: { [Player]: number } = {}
local rushActive = false
local petsitAt = -math.huge
local petsitDirty = false
local lastPerfect: { [Player]: boolean } = {}
local petSitPresses: { [Player]: { n: number, since: number } } = {}
local allowRush = false
local started = false

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

local function profile(player: Player): { [string]: any }?
	local ok, data = pcall(DataService.get, player)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function pairKey(a: number, b: number): string
	if a < b then
		return tostring(a) .. ":" .. tostring(b)
	end
	return tostring(b) .. ":" .. tostring(a)
end

local function present(player: Player): boolean
	return player.Parent ~= nil
end

-- =============================================================================================
-- Amis
-- =============================================================================================

local function recount(player: Player)
	if not present(player) then
		return
	end
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and friendCache[pairKey(player.UserId, other.UserId)] == true then
			n += 1
		end
	end
	local before = friendCount[player]
	if before == n then
		return
	end
	friendCount[player] = n
	if before == nil and n == 0 then
		return -- aucun ami à l'arrivée : rien n'a changé (EconomyService compte 0 par défaut)
	end
	Guard.try("community:setFriends", EconomyService.setFriendsPresent, player, n)
	Signals.FriendsChanged:Fire(player, n)
	if before ~= nil or n > 0 then
		Analytics.custom(player, "FriendsOnServer", n)
	end
end

local function recountAll()
	for _, p in Players:GetPlayers() do
		recount(p)
	end
end

-- Vérifie les amitiés d'un arrivant avec chaque joueur présent (hors du tick : IsFriendsWith attend)
local function checkFriends(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local key = pairKey(player.UserId, other.UserId)
			if friendCache[key] == nil then
				local ok, result = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				-- l'un des deux est parti pendant l'appel : rien n'est gardé (cache oublié à son départ)
				if present(player) and present(other) then
					friendCache[key] = ok and result == true
				end
			end
		end
	end
	recountAll()
end

-- =============================================================================================
-- Réglages, cosmétiques
-- =============================================================================================

local function privateOwner(player: Player): boolean
	local ok, ownerId = pcall(function()
		return (game :: any).PrivateServerOwnerId
	end)
	return ok and finite(ownerId) and ownerId ~= 0 and ownerId == player.UserId
end

local function settingsOf(data: { [string]: any }): { [string]: any }
	return if type(data.settings) == "table" then data.settings else {}
end

local function cosmeticsOf(data: { [string]: any }): { [string]: any }?
	return if type(data.cosmetics) == "table" then data.cosmetics else nil
end

local PUBLIC_FIELD =
	{ saddle = "saddleColor", trail = "trail", title = "title", theme = "theme", flag = "flag" }
-- cosmétiques qu'on peut retirer (id "") : leur valeur par défaut est vide
local CLEARABLE = { trail = true, title = true, flag = true }

-- =============================================================================================
-- Bannières
-- =============================================================================================

local function quiet(player: Player): boolean
	return Guard.call("community:quiet", QuestService.isNewcomerQuiet, false, player) == true
end

local function bannerPayload(b: Banner): Types.BannerPayload
	return { kind = b.kind, args = b.args, priority = b.priority, personal = false }
end

local function broadcast(b: Banner, now: number)
	local payload = bannerPayload(b)
	local remote = Net.event("Banner")
	for _, player in Players:GetPlayers() do
		if quiet(player) then
			-- nouveau avant l'étape 9 : mise en attente (jetée si elle a plus de 30 s)
			local list = pendingNew[player]
			if list == nil then
				list = {}
				pendingNew[player] = list
			end
			table.insert(list, { kind = b.kind, args = b.args, priority = b.priority, at = now, seq = b.seq })
			while #list > BANNERS.QueueMax do
				table.remove(list, 1)
			end
		else
			remote:FireClient(player, payload)
		end
	end
end

local function enqueue(kind: string, args: { [string]: any }, source: Player?)
	local now = Clock.now()
	if source ~= nil then
		local last = lastBySource[source.UserId]
		if last ~= nil and now - last < BANNERS.PerSourceCooldown then
			return -- un même joueur : une bannière toutes les 10 s au plus
		end
		lastBySource[source.UserId] = now
	end
	local clean: { [string]: any } = {}
	for k, v in args do
		if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
			if type(v) ~= "number" or finite(v) then
				clean[k] = v
			end
		end
	end
	if source ~= nil then
		clean.userId = source.UserId
		clean.name = CommunityService.displayName(source)
	end
	if type(clean.userId) ~= "number" then
		clean.userId = 0
	end
	if type(clean.name) ~= "string" then
		clean.name = ""
	end
	bannerSeq += 1
	local b: Banner = {
		kind = kind,
		args = clean,
		priority = Notify.BANNER_PRIORITY[kind] or Notify.DEFAULT_PRIORITY,
		at = now,
		seq = bannerSeq,
	}
	if #queue >= BANNERS.QueueMax then
		-- file pleine : la moins prioritaire (la plus récente à égalité) cède sa place, ou la nouvelle part
		local worst = 1
		for i, q in queue do
			local w = queue[worst]
			if q.priority > w.priority or (q.priority == w.priority and q.seq > w.seq) then
				worst = i
			end
		end
		if b.priority >= queue[worst].priority then
			return
		end
		table.remove(queue, worst)
	end
	table.insert(queue, b)
end

local function stepBanners(now: number)
	if now >= currentUntil and #queue > 0 then
		local best = 1
		for i, q in queue do
			local b = queue[best]
			if q.priority < b.priority or (q.priority == b.priority and q.seq < b.seq) then
				best = i
			end
		end
		local b = table.remove(queue, best) :: Banner
		currentUntil = now + BANNERS.Duration
		broadcast(b, now)
	end
	-- nouveaux sortis de l'accueil discret : bannières encore fraîches, une par durée
	for player, list in pendingNew do
		if not present(player) then
			pendingNew[player] = nil
		elseif
			#list > 0
			and not quiet(player)
			and now - (lastPending[player] or -math.huge) >= BANNERS.Duration
		then
			local b = table.remove(list, 1) :: Banner
			if now - b.at <= BANNERS.StaleAfter then
				lastPending[player] = now
				Net.event("Banner"):FireClient(player, bannerPayload(b))
			end
		end
	end
end

-- =============================================================================================
-- Pet-sitting
-- =============================================================================================

local function capsUsed(data: { [string]: any }, key: string): number
	local caps = data.caps
	if type(caps) ~= "table" or caps.day ~= Clock.day() then
		return 0
	end
	return num(caps[key], 0)
end

-- Joueur ami côté rue à ≤ 10 studs de la clôture du ranch `slot` (position validée du tick)
local function friendAtFence(owner: Player, slot: number, actors: { [Player]: Types.TickActor }): boolean
	for player, actor in actors do
		if
			player ~= owner
			and type(actor) == "table"
			and typeof(actor.pos) == "Vector3"
			and friendCache[pairKey(owner.UserId, player.UserId)] == true
			and not CommunityService.isBlocked(owner, player)
			and ZoneRules.streetSideOfFence(slot, actor.pos, PETSIT_RADIUS)
		then
			return true
		end
	end
	return false
end

local function petsitFor(owner: Player, slot: number, wanted: boolean)
	local current, reason = RanchService.fenceOf(slot)
	if not wanted then
		if reason == "petsit" and #current > 0 then
			RanchService.setFence(slot, {}, "petsit")
		end
		return
	end
	if reason == "rush" and #current > 0 then
		return -- le Rush passe avant
	end
	local candidates = SquishyService.fenceCandidates(owner, {
		now = Clock.unix(),
		carried = "",
		waiting = "",
		returnedThisRush = {},
		moonBoopable = false,
	})
	local eligible: { [string]: boolean } = {}
	for _, uid in candidates do
		eligible[uid] = true
	end
	-- liste stable : ceux déjà à la clôture restent à leur place, les places libres se remplissent
	local list: { string } = {}
	if reason == "petsit" then
		for _, uid in current do
			if eligible[uid] and #list < PETSIT_MAX then
				table.insert(list, uid)
			end
		end
	end
	local now = Clock.now()
	-- prêts d'abord (recharge finie), puis les autres
	local ready, later = {}, {}
	for _, uid in candidates do
		if not table.find(list, uid) then
			local okReady, at = pcall(SquishyService.readyAt, owner, uid)
			if okReady and finite(at) and at > now then
				table.insert(later, uid)
			else
				table.insert(ready, uid)
			end
		end
	end
	for _, group in { ready, later } do
		for _, uid in group do
			if #list >= PETSIT_MAX then
				break
			end
			table.insert(list, uid)
		end
	end
	if #list == 0 then
		if reason == "petsit" and #current > 0 then
			RanchService.setFence(slot, {}, "petsit")
		end
		return
	end
	RanchService.setFence(slot, list, "petsit")
end

local function stepPetsit(now: number, actors: { [Player]: Types.TickActor })
	if not petsitDirty and now - petsitAt < PETSIT_EVERY then
		return
	end
	petsitAt = now
	petsitDirty = false
	for _, owner in Players:GetPlayers() do
		local slot = RanchService.slotOf(owner)
		if slot ~= 0 and RanchService.playerAt(slot) == owner then
			if rushActive then
				-- pendant le Rush : la clôture du pet-sitting s'efface (le Rush la remplace) ; réappliquée après
				petsitFor(owner, slot, false)
			else
				local waiting = Guard.call("community:waiting", SquishyService.waiting, nil, owner)
				local wanted = waiting == nil and friendAtFence(owner, slot, actors)
				Guard.try("community:petsit", petsitFor, owner, slot, wanted)
			end
		end
	end
end

local function flushPetSit(player: Player)
	local entry = petSitPresses[player]
	if entry ~= nil and entry.n > 0 then
		Analytics.custom(player, "PetSitPress", entry.n)
		entry.n = 0
	end
end

-- =============================================================================================
-- Handlers des intentions
-- =============================================================================================

local function onPetPress(visitor: Player, ownerId: number, uid: string, tClient: number): boolean
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner == nil or owner == visitor then
		return false
	end
	if not CommunityService.areFriends(visitor, owner) or CommunityService.isBlocked(visitor, owner) then
		return false
	end
	local vData, oData = profile(visitor), profile(owner)
	if vData == nil or oData == nil then
		return false
	end
	-- plafonds vérifiés d'abord, SANS consommer
	if
		capsUsed(vData, "petSit") >= Balance.Caps.petSit
		or capsUsed(oData, "petSitIn") >= Balance.Caps.petSitIn
	then
		Notify.feedback(visitor, "feedback.capReached", {}, "info")
		return false
	end
	lastPerfect[visitor] = false
	local ok, pressed = pcall(SquishyService.press, owner, uid, tClient, visitor)
	if not ok then
		Guard.caught("community:petPress", pressed)
		return false
	end
	if pressed ~= true then
		return false
	end
	EconomyService.consumeCap(visitor, "petSit", 1)
	EconomyService.consumeCap(owner, "petSitIn", 1)
	local seconds = Balance.Rewards.PetSitVisitor * (if lastPerfect[visitor] then 2 else 1)
	local coins = EconomyService.addIncomeSeconds(visitor, seconds, "PetSit")
	if finite(coins) and coins > 0 then
		Notify.feedback(visitor, "feedback.coinsGained", { coins = coins }, "reward")
	end
	local helpful = EconomyService.consumeFriendCap(visitor, "petSit", owner.UserId, 1) > 0
	Signals.PetSitRewarded:Fire(visitor, owner, helpful)
	local entry = petSitPresses[visitor]
	if entry == nil then
		entry = { n = 0, since = Clock.now() }
		petSitPresses[visitor] = entry
	end
	entry.n += 1
	return true
end

local function onSetSetting(player: Player, key: string, value: any): boolean
	local def = Settings[key]
	if def == nil then
		return false
	end
	if def.kind == "boolean" then
		if type(value) ~= "boolean" then
			return false
		end
	elseif def.kind == "string" then
		if type(value) ~= "string" or def.values == nil or def.values[value] ~= true then
			return false
		end
	else
		return false
	end
	-- v2.0 (lot A4, D24) : « Montrer mon halo » seulement quand RanchSkins est ouvert (le jeu de base
	-- ne l'écrit jamais) ; un réglage `since = N` n'est jamais écrit dans un profil de version < N
	if key == "haloOn" and Features.get("RanchSkins") ~= true then
		return false
	end
	if def.since ~= nil then
		local data = profile(player)
		if data == nil or type(data.version) ~= "number" or data.version < def.since then
			return false
		end
	end
	if key == "emoteLeft" and not CommunityService.hasCosmetic(player, "emote", value) then
		return false
	end
	if def.ownerOnly then
		if not privateOwner(player) then
			return false
		end
	end
	if not def.saved then
		if key == "allowRush" then
			allowRush = value == true
		end
		Signals.SettingChanged:Fire(player, key, value)
		return true
	end
	local data = profile(player)
	if data == nil then
		return false
	end
	local settings = settingsOf(data)
	if settings[key] == value then
		return false
	end
	settings[key] = value
	DataService.markDirty(player, "settings")
	Signals.SettingChanged:Fire(player, key, value)
	if key == "hideName" then
		Guard.try(
			"community:hideName",
			RanchService.setPublic,
			player,
			{ name = CommunityService.displayName(player), hidden = value == true }
		)
	end
	return true
end

local function onEquipCosmetic(player: Player, kind: string, id: string): boolean
	local data = profile(player)
	if data == nil or PUBLIC_FIELD[kind] == nil then
		return false
	end
	if not (id == "" and CLEARABLE[kind]) and not CommunityService.hasCosmetic(player, kind, id) then
		return false
	end
	local cosmetics = cosmeticsOf(data)
	if cosmetics == nil or cosmetics[kind] == id then
		return false
	end
	cosmetics[kind] = id
	DataService.markDirty(player, "cosmetics")
	Guard.try("community:cosmetic", RanchService.setPublic, player, { [PUBLIC_FIELD[kind]] = id })
	return true
end

local function emoteName(player: Player, kind: number): string
	local def = Cosmetics.EmoteSignals[kind]
	if def == nil then
		return "wave"
	end
	if kind == 3 then
		local left = CommunityService.setting(player, "emoteLeft")
		if
			type(left) == "string"
			and left ~= "bravo"
			and CommunityService.hasCosmetic(player, "emote", left)
		then
			return left
		end
	end
	return def.emote
end

local function onEmote(player: Player, kind: number): boolean
	if Cosmetics.EmoteSignals[kind] == nil then
		return false
	end
	local payload: Types.EmoteShowPayload =
		{ userId = player.UserId, kind = kind, emote = emoteName(player, kind) }
	Net.event("EmoteShow"):FireAllClients(payload)
	Signals.Emoted:Fire(player, kind)
	return true
end

local function onClap(player: Player, heroId: number): boolean
	local hero = Players:GetPlayerByUserId(heroId)
	if hero == nil or hero == player then
		return false
	end
	local window = clapWindows[hero]
	local now = Clock.now()
	if window == nil or now >= window.endsAt then
		return false
	end
	if window.viewers ~= nil and not window.viewers[player] then
		return false -- seulement les spectateurs du spectacle complet
	end
	if window.clapped[player] then
		return false
	end
	window.clapped[player] = true
	window.count += 1
	if EconomyService.consumeCap(player, "claps", 1) > 0 then
		EconomyService.addIncomeSeconds(player, Balance.Rewards.Clap, "Clap")
	end
	local payload: Types.EmoteShowPayload = { userId = player.UserId, kind = 2, emote = "cheer" }
	Net.event("EmoteShow"):FireAllClients(payload)
	Notify.celebrate(hero, "clapCount", { n = window.count })
	return true
end

local function onReportBlocked(player: Player, userIds: { number }): boolean
	local set: { [number]: boolean } = {}
	for _, id in userIds do
		set[id] = true
	end
	blocked[player] = set
	return true
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

local function onReady(player: Player)
	-- déblocages de session déjà accordés (titres de la semaine) : renvoyés au client
	local list = unlocks[player]
	if list ~= nil then
		for key in list do
			local kind, id = string.match(key, "^([^:]+):(.*)$")
			if kind ~= nil and id ~= nil then
				Notify.celebrate(player, "unlock", { kind = kind, id = id })
			end
		end
	end
	recount(player)
end

local function onRemoving(player: Player)
	flushPetSit(player)
	-- cache d'amitié oublié pour ce joueur : une amitié retirée pendant son absence se voit à son retour,
	-- et le cache ne grossit pas avec chaque couple passé sur le serveur
	for _, other in Players:GetPlayers() do
		if other ~= player then
			friendCache[pairKey(player.UserId, other.UserId)] = nil
		end
	end
	lastBySource[player.UserId] = nil
	friendCount[player] = nil
	blocked[player] = nil
	unlocks[player] = nil
	clapWindows[player] = nil
	pendingNew[player] = nil
	lastPending[player] = nil
	lastPerfect[player] = nil
	petSitPresses[player] = nil
	for _, window in clapWindows do
		if window.viewers ~= nil then
			window.viewers[player] = nil
		end
		window.clapped[player] = nil
	end
	-- recompte des autres après le départ (le partant n'est plus dans Players au thread suivant)
	task.defer(function()
		Guard.try("community:recount", recountAll)
	end)
	petsitDirty = true
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function CommunityService.Init()
	for kind, priority in BANNERS.Priority do
		Notify.BANNER_PRIORITY[kind] = priority
	end
	-- v2.0 (lot A4, D5) : bannières v2.0 (« ascend »), jamais envoyées tant que leur interrupteur est coupé
	for kind, priority in BANNERS.PriorityV2 do
		Notify.BANNER_PRIORITY[kind] = priority
	end
	Guard.connect("PetPress", onPetPress)
	Guard.connect("SetSetting", onSetSetting)
	Guard.connect("EquipCosmetic", onEquipCosmetic)
	Guard.connect("Emote", onEmote)
	Guard.connect("Clap", onClap)
	Guard.connect("ReportBlocked", onReportBlocked)
end

-- Connexions et boucles
function CommunityService.Start()
	if started then
		return
	end
	started = true
	Signals.BannerRequested:Connect(function(kind: any, args: any, source: any)
		if type(kind) ~= "string" then
			return
		end
		Guard.try("community:banner", enqueue, kind, if type(args) == "table" then args else {}, source)
	end)
	Signals.Pressed:Connect(function(_owner: Player, info: any)
		if type(info) == "table" and typeof(info.visitor) == "Instance" then
			lastPerfect[info.visitor] = info.perfect == true
		end
	end)
	Signals.EventPhase:Connect(function(kind: any, phase: any)
		if kind == "rush" then
			if phase == "start" then
				rushActive = true
			elseif phase == "end" then
				rushActive = false
				petsitDirty = true -- réappliqué au step qui suit la fin du Rush
			end
		end
	end)
	Signals.SquishyRemoved:Connect(function()
		petsitDirty = true
	end)
	Signals.PlayerReady:Connect(function(player: Player)
		Guard.try("community:ready", onReady, player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			Guard.try("community:friends", checkFriends, player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("community:removing", onRemoving, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			Guard.try("community:friends", checkFriends, player)
		end)
	end
end

-- Tick : clôtures de pet-sitting, fenêtres d'applaudissement, file des bannières
function CommunityService.step(now: number, actors: { [Player]: Types.TickActor })
	local t = if finite(now) then now else Clock.now()
	for hero, window in clapWindows do
		if t >= window.endsAt or not present(hero) then
			clapWindows[hero] = nil
		end
	end
	Guard.try("community:banners", stepBanners, t)
	Guard.try("community:petsitStep", stepPetsit, t, if type(actors) == "table" then actors else {})
	for player, entry in petSitPresses do
		if entry.n > 0 and t - entry.since >= ANALYTICS_EVERY then
			flushPetSit(player)
			entry.since = t
		end
	end
end

-- Nom d'affichage, ou "" si caché (le client écrit l'alias « Squishy Fan #NNNN »)
function CommunityService.displayName(player: Player): string
	if CommunityService.setting(player, "hideName") == true then
		return ""
	end
	local ok, name = pcall(function()
		return player.DisplayName
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return player.Name
end

-- Amis Roblox présents (mis en cache)
function CommunityService.friendsPresent(player: Player): number
	return friendCount[player] or 0
end

-- Amis Roblox (cache de session ; un couple encore inconnu est vérifié sous pcall, hors du tick)
function CommunityService.areFriends(a: Player, b: Player): boolean
	if a == b or typeof(a) ~= "Instance" or typeof(b) ~= "Instance" then
		return false
	end
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached == nil then
		local ok, result = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		cached = ok and result == true
		if present(a) and present(b) then
			friendCache[key] = cached
		end
	end
	return cached == true
end

-- L'un a bloqué l'autre (liste souple fournie par le client)
function CommunityService.isBlocked(a: Player, b: Player): boolean
	local la, lb = blocked[a], blocked[b]
	return (la ~= nil and la[b.UserId] == true) or (lb ~= nil and lb[a.UserId] == true)
end

-- Réglage du joueur (Config/Settings) ou du serveur (allowRush)
function CommunityService.setting(player: Player, key: string): any
	local def = Settings[key]
	if def == nil then
		return nil
	end
	if not def.saved then
		if key == "allowRush" then
			return allowRush
		end
		return def.default
	end
	local data = profile(player)
	if data == nil then
		return def.default
	end
	local value = settingsOf(data)[key]
	if typeof(value) ~= def.kind then
		return def.default
	end
	return value
end

-- Fenêtre APPLAUDIR de 8 s : ClapPrompt aux seuls `viewers` (spectateurs du spectacle complet, choisis
-- par SplorchService ; nil = tous les autres joueurs) ; le client la cache pendant une poursuite, un
-- maintien ou une fenêtre ouverte
function CommunityService.openClapWindow(hero: Player, endsAt: number, viewers: { Player }?)
	if typeof(hero) ~= "Instance" or not present(hero) then
		return
	end
	local now = Clock.now()
	local ends = if finite(endsAt) then math.min(endsAt, now + CLAP_SECONDS) else now + CLAP_SECONDS
	if ends <= now then
		return
	end
	local set: { [Player]: boolean }? = nil
	if type(viewers) == "table" then
		local s: { [Player]: boolean } = {}
		for _, p in viewers do
			if typeof(p) == "Instance" and p ~= hero then
				s[p] = true
			end
		end
		set = s
	end
	clapWindows[hero] = {
		hero = hero,
		startedAt = now,
		endsAt = ends,
		viewers = set,
		clapped = {},
		count = 0,
	}
	local payload: Types.ClapPromptPayload = { heroId = hero.UserId, endsAt = ends }
	local remote = Net.event("ClapPrompt")
	for _, p in Players:GetPlayers() do
		if p ~= hero and (set == nil or set[p]) then
			remote:FireClient(p, payload)
		end
	end
end

-- Cosmétique débloqué (source de Config/Cosmetics)
function CommunityService.hasCosmetic(player: Player, kind: string, id: string): boolean
	if type(kind) ~= "string" or type(id) ~= "string" then
		return false
	end
	local def = Cosmetics.ByKindId[kind .. ":" .. id]
	if def == nil then
		return false
	end
	local source = def.source
	if source.kind == "free" then
		return true
	end
	local data = profile(player)
	if data == nil then
		return false
	end
	if source.kind == "plopDay" then
		return num(data.plopDays, 0) >= num(source.value, math.huge)
	elseif source.kind == "dex" then
		return type(data.dex) == "table" and num(data.dex.rewards, 0) >= num(source.value, math.huge)
	elseif source.kind == "rebirth" then
		return num(data.R, 0) >= num(source.value, math.huge)
	elseif source.kind == "pass" then
		local ok, owns = pcall(MonetizationService.ownsPass, player, source.key or "")
		return ok and owns == true
	elseif source.kind == "product" then
		local owned = type(data.outfits) == "table"
				and type(data.outfits.owned) == "table"
				and data.outfits.owned
			or {}
		return num((owned :: any)[id], 0) > 0
	elseif source.kind == "weekly" then
		local list = unlocks[player]
		return list ~= nil and list[kind .. ":" .. id] == true
	end
	return false
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « clapWindow » (fenêtres d'applaudissement) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function CommunityService.openStates(): { Types.OpenState }
	local out: { Types.OpenState } = {}
	for hero, window in clapWindows do
		table.insert(out, { name = "clapWindow", startedAt = window.startedAt, player = hero })
	end
	return out
end

-- Déblocage d'un cosmétique pour la session (titres du top 10 de la semaine, source "weekly") :
-- appelé par LeaderboardService au changement de semaine et à l'arrivée ; hasCosmetic le voit aussitôt
function CommunityService.unlockSession(player: Player, kind: string, id: string)
	if typeof(player) ~= "Instance" or type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	if Cosmetics.ByKindId[kind .. ":" .. id] == nil then
		return
	end
	local list = unlocks[player]
	if list == nil then
		list = {}
		unlocks[player] = list
	end
	local key = kind .. ":" .. id
	if list[key] then
		return
	end
	list[key] = true
	Notify.celebrate(player, "unlock", { kind = kind, id = id })
end

return CommunityService
