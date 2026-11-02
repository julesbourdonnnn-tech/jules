--!strict
-- RushService (paquet chase) : BOOP RUSH côté serveur (GDD §4.21).
--   * Mode : Cozy d'office ; passage en Cozy immédiat (clôture vidée, fuites rentrées par ChaseService
--     sur Signals.ModeChanged, plus de boop jusqu'à la fin du Rush) ; passage en Rush après 60 s depuis
--     le dernier changement, appliqué à la fin du Rush en cours ; serveur privé : Cozy sauf autorisation.
--   * Carte du choix : ModePrompt une fois dès 15:00 de jeu ; délai de 20 s (+ 0,5 s de grâce) ouvert
--     par UiSeen("modeCard") ; sans réponse : Cozy, analytique RushModeChosen = −1.
--   * Bouclier débutant : 15 min de jeu cumulé.
--   * Clôtures : au début du Rush puis toutes les 20 s, 4 squishies (2 si boopé au Rush précédent) parmi
--     SquishyService.fenceCandidates, tirés par Hash ; AUCUNE clôture pour un joueur en file de Grand
--     Splorch (SquishyService.waiting) ; fin du Rush : setFence(slot, {}, "rush") (jamais le pet-sitting).
--   * Maintien de boop mesuré par le serveur (2,5 s ; 5 s propriétaire proche ; extendHold une seule fois),
--     TOUTES les règles revérifiées à chaque tick (RushRules.checkBoop, dont BoopCtx.eligible : un squishy
--     pris, lancé, rangé ou mis en attente annule le maintien), portée à plat et pieds ≤ 8, canAct.
--   * Protections : paires 30 min, 1 boop / 20 s, 2 par ranch et par Rush, 4 par heure, 10 sur le serveur,
--     « Pas ce joueur », liste de blocage souple.
-- Émet Booped, ModeChanged. Remotes : BoopHold, SetMode, RefuseBooper ; BoopState, ModePrompt. Clé : mode.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Features = require(Shared.Config.Features)
local Species = require(Shared.Config.Species)
local Hash = require(Shared.Logic.Hash)
local RushRules = require(Shared.Logic.RushRules)
local ZoneRules = require(Shared.Logic.ZoneRules)
local EventClock = require(Shared.Logic.EventClock)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local MoveCheck = require(Server.Util.MoveCheck)
local Guard = require(Server.Chase.Guard)

local DataService = require(script.Parent.DataService)
local RanchService = require(script.Parent.RanchService)
local SquishyService = require(script.Parent.SquishyService)
local QuestService = require(script.Parent.QuestService)
local CommunityService = require(script.Parent.CommunityService)
local EventService = require(script.Parent.EventService)

local RushService = {}

-- =============================================================================================
-- Constantes et état
-- =============================================================================================

local RUSH = Events.Rush
local MAX_SLOT = 16
local HOUR = 3600
-- Codes de refus montrés au joueur (clé feedback.<code>) ; les autres sont muets (GDD §4.21.4)
local SHOWN = { shieldOn = true, cooldown = true, tooManyEscapes = true, tooFar = true }

type Hold = {
	owner: Player,
	uid: string,
	slot: number,
	startedAt: number,
	endsAt: number,
	extended: boolean,
}

local holds: { [Player]: Hold } = {} -- boopeur → maintien en cours
local lastBoopAt: { [Player]: number } = {}
local pairAt: { [Player]: { [number]: number } } = {} -- boopeur → UserId du propriétaire → instant
local escapesThisRush: { [Player]: number } = {}
local escapesHour: { [Player]: { number } } = {}
local boopedThisRush: { [Player]: boolean } = {}
local boopedLastRush: { [Player]: boolean } = {}
local returnedThisRush: { [Player]: { [string]: boolean } } = {}
local activeEscapes: { [string]: boolean } = {} -- "UserId:uid"
local refused: { [Player]: { [number]: boolean } } = {} -- propriétaire → boopeurs refusés
local boopedBy: { [Player]: { [number]: boolean } } = {} -- propriétaire → boopeurs de la session
local pendingRush: { [Player]: boolean } = {}
local cozyThisRush: { [Player]: boolean } = {}
local cardOpenAt: { [Player]: number } = {}
local published: { [Player]: string } = {}

local fenceRush: number? = nil -- index du Rush dont les clôtures sont posées
local fenceRushStartedAt = 0
local nextFenceAt = 0
local renewal = 0

-- =============================================================================================
-- Aides
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function profile(player: Player): { [string]: any }?
	if not DataService.isLoaded(player) then
		return nil
	end
	return DataService.get(player)
end

local function modeOf(player: Player): { [string]: any }?
	local data = profile(player)
	if data == nil or type(data.mode) ~= "table" then
		return nil
	end
	return data.mode
end

local function playSeconds(player: Player): number
	local data = profile(player)
	local stored = if data
			and type(data.stats) == "table"
			and finite(data.stats.playSeconds)
		then data.stats.playSeconds
		else 0
	local value = Guard.call("rush:playSeconds", QuestService.playSeconds, stored, player)
	return if finite(value) then value else stored
end

local function privateServer(): boolean
	local ok, id = pcall(function()
		return (game :: any).PrivateServerId
	end)
	return ok and type(id) == "string" and id ~= ""
end

local function escapeKey(owner: Player, uid: string): string
	return tostring(owner.UserId) .. ":" .. uid
end

local function countEscapes(): number
	local n = 0
	for _ in activeEscapes do
		n += 1
	end
	return n
end

local function hourCount(owner: Player, now: number): number
	local list = escapesHour[owner]
	if list == nil then
		return 0
	end
	local n = 0
	for i = #list, 1, -1 do
		if now - list[i] < HOUR then
			n += 1
		else
			table.remove(list, i)
		end
	end
	return n
end

local function featureOn(): boolean
	local mode = Features.get("BoopRush")
	if mode == "on" then
		return true
	end
	return mode == "events" and Guard.call("rush:eventBoop", EventService.eventBoopActive, false) == true
end

local function publish(player: Player)
	local mode = modeOf(player)
	if mode == nil or RanchService.slotOf(player) == 0 then
		return
	end
	local rush = RushService.isRush(player)
	local shield = rush and RushService.isShielded(player)
	local boopable = rush and not shield
	local key = (if rush then "r" else "c")
		.. (if shield then "s" else "-")
		.. (if boopable then "b" else "-")
	if published[player] == key then
		return
	end
	published[player] = key
	RanchService.setPublic(
		player,
		{ mode = if rush then "rush" else "cozy", shield = shield, boopable = boopable }
	)
end

local function setMode(player: Player, rush: boolean, stampChange: boolean)
	local mode = modeOf(player)
	if mode == nil then
		return
	end
	local was = RushService.isRush(player)
	mode.rush = rush
	mode.chosen = true
	if stampChange then
		mode.changedAt = Clock.unix()
	end
	DataService.markDirty(player, "mode")
	publish(player)
	local now = RushService.isRush(player)
	if was ~= now then
		Signals.ModeChanged:Fire(player, now)
	end
end

local function clearFence(owner: Player)
	local slot = RanchService.slotOf(owner)
	if slot ~= 0 then
		RanchService.setFence(slot, {}, "rush")
	end
end

-- =============================================================================================
-- Clôtures
-- =============================================================================================

local function fenceCtx(owner: Player): RushRules.FenceCtx
	return {
		now = Clock.unix(),
		carried = SquishyService.carried(owner) or "",
		waiting = SquishyService.waiting(owner) or "",
		returnedThisRush = returnedThisRush[owner] or {},
		moonBoopable = EventClock.rushMoonBoopable(Clock.now()),
	}
end

local function placeFence(owner: Player, index: number)
	local slot = RanchService.slotOf(owner)
	if slot == 0 then
		return
	end
	if not RushService.canBeBooped(owner) or SquishyService.waiting(owner) ~= nil then
		RanchService.setFence(slot, {}, "rush")
		return
	end
	local candidates = SquishyService.fenceCandidates(owner, fenceCtx(owner))
	local count = math.min(RushRules.fenceCount(boopedLastRush[owner] == true), #candidates)
	local rng = Hash.stream(Hash.u32(EventClock.seed("rush", index), slot, renewal))
	local picked = {}
	for i = 1, count do
		local j = rng:int(i, #candidates)
		candidates[i], candidates[j] = candidates[j], candidates[i]
		table.insert(picked, candidates[i])
	end
	RanchService.setFence(slot, picked, "rush")
end

local function endRush()
	for slot = 1, MAX_SLOT do
		RanchService.setFence(slot, {}, "rush")
	end
	boopedLastRush = boopedThisRush
	boopedThisRush = {}
	escapesThisRush = {}
	returnedThisRush = {}
	cozyThisRush = {}
	fenceRush = nil
	-- passages en Rush demandés pendant le Rush : appliqués maintenant
	local pending = {}
	for player in pendingRush do
		table.insert(pending, player)
	end
	table.clear(pendingRush)
	for _, player in pending do
		if player.Parent ~= nil then
			setMode(player, true, true)
		end
	end
end

local function stepFences(now: number)
	local phase = Guard.call("rush:phase", EventService.rushPhase, nil)
	local active = type(phase) == "table" and phase.active == true
	if not active then
		if fenceRush ~= nil then
			endRush()
		end
		return
	end
	if fenceRush ~= phase.index then
		if fenceRush ~= nil then
			endRush()
		end
		fenceRush = phase.index
		fenceRushStartedAt = phase.startsAt
		renewal = 0
		nextFenceAt = now
	end
	if not featureOn() then
		for slot = 1, MAX_SLOT do
			RanchService.setFence(slot, {}, "rush")
		end
		return
	end
	if now >= nextFenceAt then
		renewal += 1
		nextFenceAt = now + RUSH.FenceRenew
		for _, owner in Players:GetPlayers() do
			if RanchService.isReady(owner) then
				Guard.try("rush:fence", placeFence, owner, phase.index)
			end
		end
	else
		-- à chaque tick : un ranch qui n'est plus boopable ou dont le joueur attend son Grand Splorch
		-- n'a aucun squishy à la clôture
		for _, owner in Players:GetPlayers() do
			local slot = RanchService.slotOf(owner)
			if slot ~= 0 and (not RushService.canBeBooped(owner) or SquishyService.waiting(owner) ~= nil) then
				local uids, reason = RanchService.fenceOf(slot)
				if reason == "rush" and #uids > 0 then
					RanchService.setFence(slot, {}, "rush")
				end
			end
		end
	end
end

-- =============================================================================================
-- Boop : contexte et règles (revérifiées à chaque tick du maintien)
-- =============================================================================================

local function boopCtx(booper: Player, owner: Player, uid: string, now: number): (RushRules.BoopCtx, number)
	local slot = RanchService.slotOf(owner)
	local uids, reason = RanchService.fenceOf(slot)
	local index = table.find(uids, uid)
	local rec = SquishyService.get(owner, uid)
	local def = if rec then Species.ById[rec.s] else nil
	local atFence = slot ~= 0 and reason == "rush" and index ~= nil
	local eligible = rec ~= nil
		and not activeEscapes[escapeKey(owner, uid)]
		and RushRules.fenceEligible(rec, fenceCtx(owner), uid)
	local distance = math.huge
	local pos = MoveCheck.lastValid(booper)
	if pos and index then
		local point = WorldLayout.fencePoint(slot, index)
		local feet = ZoneRules.feetY(pos.Y, MoveCheck.rootOffset(booper))
		if math.abs(feet - WorldLayout.groundY(point.X, point.Z)) <= Balance.Catch.MaxDY then
			distance = ZoneRules.distXZ(pos, point)
		end
	end
	local pairs = pairAt[booper]
	local pairLast = if pairs then pairs[owner.UserId] else nil
	local ctx: RushRules.BoopCtx = {
		feature = tostring(Features.get("BoopRush")),
		eventActive = Guard.call("rush:eventBoop", EventService.eventBoopActive, false) == true,
		rushActive = Guard.call("rush:active", EventService.rushActive, false) == true,
		booperRush = RushService.isRush(booper) and not cozyThisRush[booper],
		ownerRush = RushService.isRush(owner),
		sameUser = booper == owner,
		ownerShield = RushService.isShielded(owner),
		refused = refused[owner] ~= nil and refused[owner][booper.UserId] == true,
		blocked = Guard.call("rush:blocked", CommunityService.isBlocked, false, booper, owner) == true,
		booperCooldownLeft = (lastBoopAt[booper] or -math.huge) + RUSH.BooperCooldown - now,
		pairCooldownLeft = (pairLast or -math.huge) + RUSH.PairCooldown - now,
		atFence = atFence,
		eligible = eligible,
		bestFriend = rec ~= nil and finite(rec.bf) and rec.bf > 0,
		rarity = if def then def.rarity else 0,
		moonBoopable = EventClock.rushMoonBoopable(Clock.now()),
		ranchThisRush = escapesThisRush[owner] or 0,
		ranchThisHour = hourCount(owner, now),
		serverEscapes = countEscapes(),
		distance = distance,
		canAct = MoveCheck.canAct(booper, now) and pos ~= nil,
	}
	return ctx, index or 0
end

local function sendBoopState(booper: Player, hold: Hold, state: "hold" | "done" | "cancel")
	local payload: Types.BoopStatePayload = {
		booperId = booper.UserId,
		ownerId = hold.owner.UserId,
		uid = hold.uid,
		endsAt = hold.endsAt,
		state = state,
	}
	local remote = Net.event("BoopState")
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			remote:FireClient(player, payload)
		end
	end
end

local function cancelHold(booper: Player, feedback: boolean)
	local hold = holds[booper]
	if hold == nil then
		return
	end
	holds[booper] = nil
	sendBoopState(booper, hold, "cancel")
	if feedback then
		Notify.feedback(booper, "feedback.boopCancelled", {}, "info")
	end
end

local function ownerNear(owner: Player, slot: number): boolean
	local pos = MoveCheck.lastValid(owner)
	return pos ~= nil and ZoneRules.ownerNearFence(slot, pos)
end

local function boopSucceeded(booper: Player, hold: Hold, now: number)
	holds[booper] = nil
	local owner = hold.owner
	local _, index = boopCtx(booper, owner, hold.uid, now)
	lastBoopAt[booper] = now
	local pairs = pairAt[booper]
	if pairs == nil then
		pairs = {}
		pairAt[booper] = pairs
	end
	pairs[owner.UserId] = now
	escapesThisRush[owner] = (escapesThisRush[owner] or 0) + 1
	local list = escapesHour[owner]
	if list == nil then
		list = {}
		escapesHour[owner] = list
	end
	table.insert(list, now)
	boopedThisRush[owner] = true
	local by = boopedBy[owner]
	if by == nil then
		by = {}
		boopedBy[owner] = by
	end
	by[booper.UserId] = true
	activeEscapes[escapeKey(owner, hold.uid)] = true
	-- premier bond à l'opposé du boopeur : direction boopeur → squishy à la clôture
	local angle = 0
	local pos = MoveCheck.lastValid(booper)
	if pos and index > 0 then
		local point = WorldLayout.fencePoint(hold.slot, index)
		angle = math.atan2(point.Z - pos.Z, point.X - pos.X)
	end
	local rec = SquishyService.get(owner, hold.uid)
	sendBoopState(booper, hold, "done")
	Notify.celebrate(booper, "boopDone", { ownerId = owner.UserId, uid = hold.uid })
	Notify.celebrate(
		owner,
		"booped",
		{ uid = hold.uid, species = if rec then rec.s else 0, booperId = booper.UserId }
	)
	Guard.analytics(booper, "BoopDone", 1)
	Signals.Booped:Fire(booper, owner, hold.uid, angle)
end

local function stepHolds(now: number)
	local list = {}
	for booper in holds do
		table.insert(list, booper)
	end
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, booper in list do
		local hold = holds[booper]
		if hold then
			Guard.try("rush:hold", function()
				local owner = hold.owner
				if booper.Parent == nil or owner.Parent == nil then
					cancelHold(booper, false)
					return
				end
				local ctx = boopCtx(booper, owner, hold.uid, now)
				-- recharges : évaluées au début du maintien (aucun boop ne réussit pendant le maintien)
				ctx.booperCooldownLeft = 0
				ctx.pairCooldownLeft = 0
				local ok = RushRules.checkBoop(ctx)
				if not ok then
					cancelHold(booper, true)
					return
				end
				if not hold.extended and ownerNear(owner, hold.slot) then
					hold.extended = true
					local endsAt = RushRules.extendHold(hold.endsAt, now, hold.startedAt)
					if endsAt ~= hold.endsAt then
						hold.endsAt = endsAt
						sendBoopState(booper, hold, "hold")
					end
				end
				if now >= hold.endsAt then
					boopSucceeded(booper, hold, now)
				end
			end)
		end
	end
end

-- =============================================================================================
-- Carte du choix, modes
-- =============================================================================================

local function stepCards(now: number)
	for _, player in Players:GetPlayers() do
		local mode = modeOf(player)
		if mode and RanchService.isReady(player) then
			if mode.cardShown ~= true and playSeconds(player) >= RUSH.CardPlaySeconds then
				mode.cardShown = true
				DataService.markDirty(player, "mode")
				-- déjà choisi dans les Réglages : la carte n'a plus rien à demander
				if mode.chosen ~= true then
					Net.event("ModePrompt"):FireClient(player)
				end
			end
			local opened = cardOpenAt[player]
			if opened and now >= opened + RUSH.CardTimeout + RUSH.HoldGrace then
				-- sans réponse : Cozy, le choix le plus sûr (sans recharge : le joueur peut passer en
				-- Rush dans les Réglages quand il veut)
				cardOpenAt[player] = nil
				setMode(player, false, false)
				Guard.analytics(player, "RushModeChosen", -1)
			end
			publish(player)
		end
	end
end

-- =============================================================================================
-- Intentions
-- =============================================================================================

local function onBoopHold(booper: Player, ownerId: number, uid: string, holding: boolean): boolean
	local now = Clock.now()
	local current = holds[booper]
	if not holding then
		if current and current.owner.UserId == ownerId and current.uid == uid then
			cancelHold(booper, false)
		end
		return false
	end
	if current then
		return false -- un seul maintien à la fois (le même message répété ne change rien)
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner == nil or profile(booper) == nil or profile(owner) == nil then
		return false
	end
	for _, other in holds do
		if other.owner == owner and other.uid == uid then
			return false -- ce squishy est déjà boopé par un autre
		end
	end
	local ctx = boopCtx(booper, owner, uid, now)
	local ok, code = RushRules.checkBoop(ctx)
	if not ok then
		if code and SHOWN[code] then
			Notify.feedback(booper, "feedback." .. code, {}, "info")
		end
		return false
	end
	local slot = RanchService.slotOf(owner)
	local near = ownerNear(owner, slot)
	local hold: Hold = {
		owner = owner,
		uid = uid,
		slot = slot,
		startedAt = now,
		endsAt = now + RushRules.holdTime(near),
		extended = near,
	}
	holds[booper] = hold
	sendBoopState(booper, hold, "hold")
	if near then
		Notify.feedback(booper, "feedback.ownerNear", {}, "info")
	end
	return true
end

local function onSetMode(player: Player, rush: boolean): boolean
	local mode = modeOf(player)
	if mode == nil then
		return false
	end
	local answering = cardOpenAt[player] ~= nil
	if not rush then
		pendingRush[player] = nil
		local wasRush = RushService.isRush(player)
		setMode(player, false, true)
		clearFence(player)
		for booper, hold in holds do
			if hold.owner == player then
				cancelHold(booper, true)
			end
		end
		if Guard.call("rush:active", EventService.rushActive, false) == true then
			cozyThisRush[player] = true
		end
		if wasRush then
			Notify.feedback(player, "feedback.modeCozy", {}, "info")
		end
	else
		if privateServer() and not RushService.allowRush() then
			Notify.feedback(player, "feedback.privateNoRush", {}, "info")
			return false
		end
		local since = Clock.unix() - (if finite(mode.changedAt) then mode.changedAt else 0)
		if mode.chosen == true and since < RUSH.RushSwitchCooldown and not answering then
			Notify.feedback(
				player,
				"feedback.modeRushCooldown",
				{ time = RUSH.RushSwitchCooldown - since },
				"info"
			)
			return false
		end
		if Guard.call("rush:active", EventService.rushActive, false) == true then
			pendingRush[player] = true
			mode.chosen = true
			DataService.markDirty(player, "mode")
			Notify.feedback(player, "feedback.modeRushLater", {}, "info")
		else
			setMode(player, true, true)
		end
	end
	if answering then
		cardOpenAt[player] = nil
		Guard.analytics(player, "RushModeChosen", if rush then 1 else 0)
	end
	return false
end

local function onRefuseBooper(player: Player, userId: number): boolean
	local by = boopedBy[player]
	if by == nil or by[userId] ~= true then
		return false
	end
	local list = refused[player]
	if list == nil then
		list = {}
		refused[player] = list
	end
	list[userId] = true
	-- un maintien en cours de ce boopeur sur ce joueur est annulé (le boopeur n'en sait rien)
	for booper, hold in holds do
		if booper.UserId == userId and hold.owner == player then
			cancelHold(booper, false)
		end
	end
	Notify.feedback(player, "feedback.refused", {}, "success")
	return false
end

local function onPlayerRemoving(player: Player)
	cancelHold(player, false)
	for booper, hold in holds do
		if hold.owner == player then
			cancelHold(booper, false)
		end
	end
	for _, list in refused do
		list[player.UserId] = nil
	end
	for _, list in boopedBy do
		list[player.UserId] = nil
	end
	for _, list in pairAt do
		list[player.UserId] = nil
	end
	refused[player] = nil
	boopedBy[player] = nil
	pairAt[player] = nil
	lastBoopAt[player] = nil
	escapesThisRush[player] = nil
	escapesHour[player] = nil
	boopedThisRush[player] = nil
	boopedLastRush[player] = nil
	returnedThisRush[player] = nil
	pendingRush[player] = nil
	cozyThisRush[player] = nil
	cardOpenAt[player] = nil
	published[player] = nil
	local prefix = tostring(player.UserId) .. ":"
	for key in activeEscapes do
		if string.sub(key, 1, #prefix) == prefix then
			activeEscapes[key] = nil
		end
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function RushService.Init()
	Guard.connect("BoopHold", onBoopHold)
	Guard.connect("SetMode", onSetMode)
	Guard.connect("RefuseBooper", onRefuseBooper)
end

-- Connexions et boucles
function RushService.Start()
	-- un maintien de boop annule l'attente sur une dalle (GDD §4.6, note ranch n° 4)
	RanchService.setHoldCheck("boop", function(player: Player): boolean
		return holds[player] ~= nil
	end)
	Signals.UiSeen:Connect(function(player: Player, screen: string)
		if screen == "modeCard" then
			local mode = modeOf(player)
			if mode and mode.cardShown == true and cardOpenAt[player] == nil then
				cardOpenAt[player] = Clock.now()
			end
		end
	end)
	Signals.EscapeEnded:Connect(function(owner: Player, uid: string, outcome: string)
		activeEscapes[escapeKey(owner, uid)] = nil
		local returned = returnedThisRush[owner]
		if returned == nil then
			returned = {}
			returnedThisRush[owner] = returned
		end
		returned[uid] = true
		if outcome ~= "left" then
			local mode = modeOf(owner)
			if mode and mode.postBoopCardShown ~= true then
				mode.postBoopCardShown = true
				DataService.markDirty(owner, "mode")
			end
		end
	end)
	Signals.Splorched:Connect(function(player: Player)
		published[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("rush:leave", onPlayerRemoving, player)
	end)
end

-- Tick : clôtures, maintiens de boop finis ou rompus, carte du choix au calme
function RushService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = actors
	if not finite(now) then
		return
	end
	Guard.try("rush:fences", stepFences, now)
	Guard.try("rush:holds", stepHolds, now)
	Guard.try("rush:cards", stepCards, now)
end

-- Mode effectif Rush (choisi, et BOOP RUSH autorisé sur ce serveur)
function RushService.isRush(player: Player): boolean
	local mode = modeOf(player)
	if mode == nil or mode.chosen ~= true or mode.rush ~= true then
		return false
	end
	return RushService.allowRush()
end

-- Bouclier débutant actif (moins de 15 min de jeu cumulé)
function RushService.isShielded(player: Player): boolean
	return playSeconds(player) < RUSH.ShieldPlaySeconds
end

-- Ranch boopable maintenant (badge rose) : mode Rush, hors bouclier, interrupteur actif
function RushService.canBeBooped(owner: Player): boolean
	return featureOn() and RushService.isRush(owner) and not RushService.isShielded(owner)
end

-- BOOP RUSH autorisé sur ce serveur (serveur privé : réglage du propriétaire)
function RushService.allowRush(): boolean
	if not privateServer() then
		return true
	end
	for _, player in Players:GetPlayers() do
		if Guard.call("rush:allowRush", CommunityService.setting, false, player, "allowRush") == true then
			return true
		end
	end
	return false
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « boopHold »,
-- « modeCard » (délai ouvert par UiSeen, grâce comprise), « rush »
function RushService.openStates(): { Types.OpenState }
	local out: { Types.OpenState } = {}
	for booper, hold in holds do
		table.insert(out, { name = "boopHold", startedAt = hold.startedAt, player = booper })
	end
	for player, opened in cardOpenAt do
		table.insert(out, { name = "modeCard", startedAt = opened + RUSH.HoldGrace, player = player })
	end
	if fenceRush ~= nil then
		table.insert(out, { name = "rush", startedAt = fenceRushStartedAt, player = nil })
	end
	return out
end

return RushService
