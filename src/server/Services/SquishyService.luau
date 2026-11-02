--!strict
-- SquishyService (paquet ranch, docs/04 §11.6 ; GDD §4.3, §4.7, §4.9, §4.10, §4.12-§4.16, §4.21.3).
-- Collection et gestes du ranch : squishies (uid base 36, espèce, taille paresseuse z + (G − zg),
-- étoiles, mutation, Meilleur Ami, verrou, tenue, lieu), presser SPLORCH (recharge 8 s par squishy,
-- PERFECT, série, 12 / s ; portée à plat ≤ 10 + 2 du centre de la place du squishy, pieds), Cuve à
-- Gelée (minuteur du serveur, Odds ; naissance en enclos, sinon dans la Boîte à dodo ; goutte en
-- attente seulement si enclos ET Dodo sont pleins ; accueil scripté), Bassin et combos (échéances
-- 0,4 / 0,6 s fermées par step), Tout fusionner (une paire par échéance), bonus de croissance du Rush
-- une fois par squishy et par jour (growFor, champ gd), portage (état du serveur, fin dans 6 cas),
-- Dodo, Lettres, vendre / ranger / relâcher (12 derniers dans la Prairie), verrou automatique,
-- Meilleurs Amis (1 / 2 / 3 selon R), monture (selle gagnée par le record ; WalkSpeed, JumpHeight,
-- HipHeight fixes ; MoveCheck.setRootOffset(player, hausse, hauteur de saut) à chaque montée et
-- descente), tenues (portées gardées dans rec.o seulement : porteurs ≤ owned), trophées et record.
-- Un squishy qui quitte l'enclos (portage, lancer, Dodo, fusion, attente, vente, relâche) est retiré
-- AUSSITÔT de sa clôture (RanchService.setFence). Aucun minuteur par task.delay : chaque échéance est
-- fermée par step (docs/04 §1 règle 4) ; chaque état a son délai (openStates).
-- Émet Pressed, SquishyObtained, Hatched, Fused, SquishyRemoved. Remotes : Press, PickUp, PutDown,
-- Throw, FuseMenu, FuseAll, MoveSquishy, ClaimMail, Sell, Release, SetLock, SetBestFriend, SetMount,
-- Ride, EquipOutfit. Clés : squishies, nextUid, mount, vat, released, trophies, outfits, biggestEver.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Trove = require(Shared.Util.Trove)
local Balance = require(Shared.Config.Balance)
local Species = require(Shared.Config.Species)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Cosmetics = require(Shared.Config.Cosmetics)
local Pads = require(Shared.Config.Pads)
local Quests = require(Shared.Config.Quests)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Logic.Formulas)
local FusionRules = require(Shared.Logic.FusionRules)
local Odds = require(Shared.Logic.Odds)
local Hash = require(Shared.Logic.Hash)
local PressTiming = require(Shared.Logic.PressTiming)
local QuestRules = require(Shared.Logic.QuestRules)
local RushRules = require(Shared.Logic.RushRules)
local EventClock = require(Shared.Logic.EventClock)
local WorldLayout = require(Shared.Logic.WorldLayout)
local ZoneRules = require(Shared.Logic.ZoneRules)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local Signals = require(script.Parent.Parent.Signals)
local Notify = require(script.Parent.Parent.Util.Notify)
local MoveCheck = require(script.Parent.Parent.Util.MoveCheck)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Ranch.Guard)
local Places = require(script.Parent.Parent.Ranch.Places)

-- Analytique du GDD §16.3 (HatchRarity, MutationGot, ComboLength, RideStart) : budgétée par
-- Util/Analytics, jamais une erreur (pcall)
local rideTracked: { [Player]: boolean } = setmetatable({} :: any, { __mode = "k" })
local function track(player: Player, name: string, value: number, fields: { [string]: any }?)
	local ok, err = pcall(Analytics.custom, player, name, value, fields)
	if not ok then
		Guard.caught("squishy:analytics", err)
	end
end
local DiagnosticsService = require(script.Parent.DiagnosticsService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)

export type Counts = {
	pen: number,
	pool: number,
	dodo: number,
	mail: number,
	penCapacity: number,
	poolSlots: number,
}
export type GiveSpec = { s: number, m: number, st: number, z: number }

local SquishyService = {}

local MAX = Balance.Numbers.Max
local MAX_BF = #Balance.Splorch.BestFriendSlotsAt
local PRESS_RANGE = Balance.Press.Range + Balance.Press.RangeTolerance
local PICK_RANGE = Balance.Carry.PickRange + Balance.Press.RangeTolerance
local POOL_ZONE = WorldLayout.Const.PoolSlotRadius + 2 -- entrer dans le Bassin : descente de monture
local BEST_EVERY = 1 -- s : silhouette du ranch republiée au plus une fois par seconde
-- attente du Grand Splorch jamais plus longue que la file (coupure dure) + le spectacle : au-delà,
-- SplorchService a manqué la fin, l'attente est fermée (jamais un squishy bloqué pour la session)
local WAITING_EXTRA = StateTimeouts.seconds("spectacle")

-- tenues connues (Config/Cosmetics, kind "outfit")
local OUTFITS: { [string]: boolean } = {}
for _, def in Cosmetics.List do
	if def.kind == "outfit" then
		OUTFITS[def.id] = true
	end
end

type Hatch = { at: number, startedAt: number, kind: "vat" | "twin" | "firstPull" }
-- échéance de fusion : paire (a, b), étape du combo ; auto = étape de « Tout fusionner »
type FuseJob = {
	at: number,
	startedAt: number,
	name: "fusion" | "combo",
	a: string,
	b: string,
	step: number,
	auto: boolean,
}

-- =============================================================================================
-- État de session (nettoyé à PlayerRemoving ; jamais sauvegardé)
-- =============================================================================================

local troves: { [Player]: Trove.Trove } = {}
local diedConns: { [Player]: RBXScriptConnection } = {}
local carried: { [Player]: { uid: string, since: number } } = {}
local riding: { [Player]: string } = {} -- uid de la monture montée
local waitingOf: { [Player]: string } = {}
local waitingSince: { [Player]: number } = {} -- début de l'attente (filet de sûreté : délai de la file)
local escapingOf: { [Player]: { [string]: boolean } } = {}
local readyAt: { [Player]: { [string]: number } } = {}
local streakOf: { [Player]: { n: number, last: number } } = {}
local hatches: { [Player]: { Hatch } } = {}
local fuseJobs: { [Player]: { FuseJob } } = {}
local mergePlans: { [Player]: { pairs: { { string } }, steps: { number }, index: number } } = {}
local fusing: { [Player]: { [string]: boolean } } = {}
local scriptedDone: { [Player]: { [string]: boolean } } = {}
local lastBest: { [Player]: { uid: string, z: number, zg: number, s: number, m: number, at: number } } = {}
local loadedPlayers: { [Player]: boolean } = {}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function toBase36(n: number): string
	local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
	local out = ""
	local v = math.floor(n)
	repeat
		local d = v % 36
		out = string.sub(digits, d + 1, d + 1) .. out
		v = v // 36
	until v == 0
	return out
end

local function profile(player: Player): { [string]: any }?
	return DataService.get(player)
end

local function recordOf(player: Player, uid: any): (Types.SquishyRecord?, { [string]: any }?)
	local data = profile(player)
	if data == nil or type(uid) ~= "string" then
		return nil, data
	end
	local rec = data.squishies[uid]
	if type(rec) ~= "table" then
		return nil, data
	end
	return rec, data
end

local function feedback(player: Player, key: string, vars: { [string]: any }?)
	Notify.feedback(player, key, vars or {}, "info")
end

local function displayName(player: Player): string
	local data = profile(player)
	local hidden = data ~= nil and type(data.settings) == "table" and data.settings.hideName == true
	return if hidden then "" else player.DisplayName
end

local function isEscaping(player: Player, uid: string): boolean
	local set = escapingOf[player]
	return set ~= nil and set[uid] == true
end

local function isFusing(player: Player, uid: string): boolean
	local set = fusing[player]
	return set ~= nil and set[uid] == true
end

local function isCarried(player: Player, uid: string): boolean
	local c = carried[player]
	return c ~= nil and c.uid == uid
end

-- Le squishy est-il occupé (porté, en fuite, en attente de Grand Splorch, en fusion) ?
local function busySquishy(player: Player, uid: string): string?
	if isCarried(player, uid) then
		return "feedback.carrying"
	elseif isEscaping(player, uid) then
		return "feedback.notReady"
	elseif waitingOf[player] == uid then
		return "feedback.waitingSplorch"
	elseif isFusing(player, uid) then
		return "feedback.inPool"
	end
	return nil
end

local function G(player: Player): number
	return EconomyService.G(player)
end

local function publicOf(player: Player, uid: string, rec: Types.SquishyRecord): Types.PublicSquishy
	local ready = (readyAt[player] or {})[uid] or 0
	return {
		s = rec.s,
		m = rec.m,
		st = rec.st,
		z = rec.z,
		zg = rec.zg,
		at = rec.at,
		bf = rec.bf,
		o = rec.o,
		ready = if ready > Clock.now() then ready else 0,
	}
end

-- Réplication d'un squishy : profil (entrée seule) et état public du ranch (enclos et Bassin)
local function changed(player: Player, uid: string, wasVisible: boolean)
	DataService.markDirtyEntry(player, "squishies", uid)
	local rec = recordOf(player, uid)
	local visible = rec ~= nil and (rec.at == "pen" or rec.at == "pool")
	if visible and rec ~= nil then
		RanchService.squishyOp(
			player,
			if wasVisible then "update" else "add",
			uid,
			publicOf(player, uid, rec)
		)
	elseif wasVisible then
		RanchService.squishyOp(player, "remove", uid, nil)
	end
end

local function visibleAt(at: any): boolean
	return at == "pen" or at == "pool"
end

-- Retire aussitôt un squishy de la clôture de son ranch (docs/04 §11.6 « clôture toujours vraie »)
local function leaveFence(player: Player, uid: string)
	local slot = RanchService.slotOf(player)
	if slot == 0 then
		return
	end
	local uids, reason = RanchService.fenceOf(slot)
	local index = table.find(uids, uid)
	if index == nil or reason == "" then
		return
	end
	table.remove(uids, index)
	RanchService.setFence(slot, uids, reason :: any)
end

local function autoLock(s: number, m: number): boolean
	local def = Species.ById[s]
	local rarity = if def then Rarities.List[def.rarity] else nil
	local mutation = Mutations.ById[m]
	return (rarity ~= nil and rarity.autoLock) or (mutation ~= nil and mutation.autoLock)
end

local function needsConfirm(rec: Types.SquishyRecord): boolean
	local def = Species.ById[rec.s]
	local rarity = if def then Rarities.List[def.rarity] else nil
	local mutation = Mutations.ById[rec.m]
	return (rarity ~= nil and rarity.sellConfirm) or (mutation ~= nil and mutation.sellConfirm)
end

local function rarityOf(s: number): number
	local def = Species.ById[s]
	return if def then def.rarity else 1
end

local function stamped(data: { [string]: any }, s: number): boolean
	local mut = if type(data.dex) == "table" then data.dex.mut else nil
	local mask = if type(mut) == "table" then mut[s] else nil
	return type(mask) == "number" and bit32.band(math.floor(mask) % 4294967296, 1) ~= 0
end

local function poolRecords(data: { [string]: any }): { [string]: Types.SquishyRecord }
	local pool = {}
	for uid, rec in data.squishies do
		if type(rec) == "table" and rec.at == "pool" then
			pool[uid] = rec
		end
	end
	return pool
end

-- Hausse de la racine en monture (pieds = racine − hauteur debout − hausse, ZoneRules.feetY)
local function rootOffset(player: Player): number
	local api = MoveCheck :: any
	if type(api.rootOffset) == "function" then
		local ok, value = pcall(api.rootOffset, player)
		if ok and finite(value) then
			return value
		end
	end
	if riding[player] ~= nil then
		local data = profile(player)
		local stats = Formulas.rideStats(Formulas.saddleLevel(if data then data.biggestEver else 0))
		return math.max(0, stats.hipHeight - Balance.Ride.BaseHipHeight)
	end
	return 0
end

-- Position validée et droit d'agir (jamais la racine brute du client, docs/04 §15)
local function validated(player: Player): Vector3?
	local pos = MoveCheck.lastValid(player)
	if pos == nil or not MoveCheck.canAct(player, Clock.now()) then
		return nil
	end
	return pos
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function setRootOffset(player: Player, studs: number, jumpHeight: number)
	local api = MoveCheck :: any
	if type(api.setRootOffset) == "function" then
		Guard.try("squishy:setRootOffset", api.setRootOffset, player, studs, jumpHeight)
	end
end

-- =============================================================================================
-- Silhouette, selle, trophées
-- =============================================================================================

local function publishBest(player: Player, force: boolean)
	local data = profile(player)
	if data == nil then
		return
	end
	local now = Clock.now()
	local g = G(player)
	local bestUid, bestSize = nil, 0
	for uid, rec in data.squishies do
		if type(rec) == "table" and visibleAt(rec.at) and not isEscaping(player, uid) then
			local size = Formulas.sizeAt(rec, g)
			if size > bestSize or (size == bestSize and bestUid ~= nil and Places.before(uid, bestUid)) then
				bestUid, bestSize = uid, size
			end
		end
	end
	local rec = if bestUid then data.squishies[bestUid] else nil
	local last = lastBest[player]
	local s = if rec then rec.s else 0
	local m = if rec then rec.m else 0
	local z = if rec then rec.z else 0
	local zg = if rec then rec.zg else 0
	if
		not force
		and last ~= nil
		and last.s == s
		and last.m == m
		and last.z == z
		and last.zg == zg
		and last.uid == (bestUid or "")
	then
		return
	end
	if not force and last ~= nil and now - last.at < BEST_EVERY then
		return
	end
	lastBest[player] = { uid = bestUid or "", s = s, m = m, z = z, zg = zg, at = now }
	RanchService.setPublic(player, { best = { s = s, m = m, z = z, zg = zg } })
end

-- Crochet EconomyService.onSettle : records par espèce (tableau dense) et record de taille (selles)
local function onSettle(player: Player, g: number)
	local data = profile(player)
	if data == nil or not loadedPlayers[player] then
		return
	end
	local trophies = data.trophies
	local tierChanged = false
	local trophyDirty = false
	local best = finite(data.biggestEver) and data.biggestEver or 0
	for _, rec in data.squishies do
		if type(rec) == "table" and visibleAt(rec.at) then
			local size = Formulas.sizeAt(rec, g)
			local s = rec.s
			-- jamais de trou : une case existante, ou la suivante du tableau dense
			if type(s) == "number" and s >= 1 and s % 1 == 0 and s <= #trophies + 1 then
				local old = trophies[s] or 0
				if size > old then
					if Formulas.trophyTier(size) ~= Formulas.trophyTier(old) then
						tierChanged = true
					end
					trophies[s] = size
					trophyDirty = true
				end
			end
			if size > best then
				best = size
			end
		end
	end
	if trophyDirty then
		DataService.markDirty(player, "trophies")
	end
	if best > (data.biggestEver or 0) then
		local before = Formulas.saddleLevel(data.biggestEver or 0)
		DataService.set(player, "biggestEver", math.min(best, MAX))
		local after = Formulas.saddleLevel(best)
		if after > before then
			RanchService.setPublic(player, { saddle = after })
			Notify.celebrate(player, "saddle", { saddle = after })
		end
	end
	if tierChanged then
		-- palier de l'Étagère franchi : A change (refresh après ce règlement, jamais dedans)
		task.defer(function()
			Guard.try("squishy:trophyRefresh", EconomyService.refresh, player)
		end)
	end
end

-- =============================================================================================
-- Ajout d'un squishy
-- =============================================================================================

local function newRecord(
	data: { [string]: any },
	player: Player,
	spec: GiveSpec,
	at: Types.SquishyLocation
): (string, Types.SquishyRecord)
	local n = math.max(1, math.floor(finite(data.nextUid) and data.nextUid or 1))
	local uid = toBase36(n)
	while data.squishies[uid] ~= nil do
		n += 1
		uid = toBase36(n)
	end
	local s = if Species.ById[spec.s] then spec.s else Species.PLOP
	local m = if finite(spec.m) and Mutations.ById[spec.m] then spec.m else 0
	local st = math.clamp(math.floor(finite(spec.st) and spec.st or 0), 0, Balance.Fusion.MaxStars)
	local z = Formulas.clampSize(spec.z)
	local rec: Types.SquishyRecord = {
		s = s,
		m = m,
		st = st,
		z = z,
		zg = if visibleAt(at) then G(player) else 0,
		bf = if n == 1 then 1 else 0, -- le tout premier squishy du compte : Meilleur Ami n° 1
		lk = autoLock(s, m),
		o = "",
		at = at,
		b = Clock.unix(),
		gd = 0,
	}
	data.squishies[uid] = rec
	DataService.set(player, "nextUid", n + 1)
	return uid, rec
end

-- =============================================================================================
-- Monture
-- =============================================================================================

local function mountUid(player: Player, data: { [string]: any }): string?
	local chosen = data.mount
	if type(chosen) == "string" and chosen ~= "" then
		local rec = data.squishies[chosen]
		if type(rec) == "table" and visibleAt(rec.at) and busySquishy(player, chosen) == nil then
			return chosen
		end
	end
	local uid = SquishyService.biggest(player)
	if uid ~= nil and busySquishy(player, uid) == nil then
		return uid
	end
	return nil
end

local function applyStats(player: Player, stats: Formulas.RideStats)
	local humanoid = humanoidOf(player)
	if humanoid == nil then
		return
	end
	Guard.try("squishy:rideStats", function()
		humanoid.WalkSpeed = stats.walkSpeed
		humanoid.JumpHeight = stats.jumpHeight
		humanoid.HipHeight = stats.hipHeight
	end)
end

-- =============================================================================================
-- Cuve
-- =============================================================================================

local function vatBuilt(data: { [string]: any }): boolean
	local onboarding = data.onboarding
	return onboarding.done == true or (onboarding.step or 0) >= Pads.FreeBuilds.vat.atStep
end

local function vatNatural(data: { [string]: any }): boolean
	local playSeconds = if type(data.stats) == "table" then data.stats.playSeconds else 0
	return data.onboarding.done == true
		or (finite(playSeconds) and playSeconds >= Quests.Onboarding.ScriptUntil)
end

local function publishVat(player: Player, data: { [string]: any })
	local fillAt = if finite(data.vat.fillAt) then data.vat.fillAt else 0
	RanchService.setPublic(player, { vatFill = if data.vat.pending then 0 else fillAt })
end

local function vatRoom(player: Player): boolean
	local c = SquishyService.counts(player)
	return c.pen + c.pool < c.penCapacity or c.dodo < Balance.Pens.Dodo
end

local function scheduleHatch(player: Player, kind: "vat" | "twin" | "firstPull")
	local now = Clock.now()
	local list = hatches[player]
	if list == nil then
		list = {}
		hatches[player] = list
	end
	table.insert(list, { at = now + Balance.Vat.HatchTime, startedAt = now, kind = kind })
end

local function vatInterval(data: { [string]: any }): number
	return Formulas.vatInterval(data.R, QuestRules.familyEarned(data.dex, "bunny"))
end

local function rollPull(player: Player, data: { [string]: any }): Odds.RollResult
	local vat = data.vat
	local level = Formulas.vatLevel(data.R)
	local now = Clock.now()
	local owned: { [number]: boolean } = {}
	for s = 1, #Species.List do
		if stamped(data, s) then
			owned[s] = true
		end
	end
	local moon = Features.get("JellyMoon") == true and EventClock.moon(now).active == true
	local roll = Odds.roll(Hash.stream(Odds.seed(player.UserId, vat.pulls)), {
		quality = level.quality,
		nozzles = level.nozzles,
		moon = moon,
		unix = Clock.unix(),
		families = Odds.unlockedFamilies(data.R),
		owned = owned,
		newPull = (vat.newPulls or 0) > 0,
		pityRare = vat.pityRare,
		pityEpic = vat.pityEpic,
	})
	vat.pulls = (vat.pulls or 0) + 1
	vat.pityRare = roll.pityRare
	vat.pityEpic = roll.pityEpic
	if roll.usedNewPull then
		vat.newPulls = math.max(0, (vat.newPulls or 0) - 1)
	end
	DataService.markDirty(player, "vat")
	return roll
end

local function hatchBanner(
	player: Player,
	uid: string,
	species: number,
	rarity: number,
	mutation: number,
	oneIn: number
)
	local kind: string? = nil
	if rarity >= Rarities.SECRET then
		kind = "secretHatch"
	elseif rarity >= Rarities.MYTHIC then
		kind = "mythicHatch"
	elseif Mutations.ById[mutation] ~= nil and Mutations.ById[mutation].rareHatch then
		kind = "rareMutation"
	elseif rarity >= Rarities.LEGENDARY then
		kind = "legendHatch"
	end
	if kind ~= nil then
		Notify.banner(kind, {
			userId = player.UserId,
			name = displayName(player),
			species = species,
			mutation = mutation,
			odds = oneIn,
			uid = uid,
		}, player)
	end
end

local function executeHatch(player: Player, entry: Hatch)
	local data = profile(player)
	if data == nil then
		return
	end
	local spec: GiveSpec
	local rarity, oneIn, source = 1, 0, "vat"
	local scripted = entry.kind ~= "vat"
	if entry.kind == "twin" then
		spec = { s = Species.PLOP, m = 0, st = 0, z = 1 }
		source = "twin"
		rarity = rarityOf(Species.PLOP)
	else
		local roll = rollPull(player, data)
		spec = { s = roll.species, m = roll.mutation, st = 0, z = 1 }
		rarity, oneIn = roll.rarity, roll.oneIn
	end
	local isNew = not stamped(data, spec.s)
	local uid, at = SquishyService.give(player, spec, source)
	if entry.kind == "vat" then
		data.vat.fillAt = 0 -- le minuteur repart au tick suivant
		DataService.markDirty(player, "vat")
	end
	if uid == nil then
		return
	end
	Signals.Hatched:Fire(player, uid, rarity)
	track(player, "HatchRarity", rarity)
	if spec.m ~= 0 then
		track(player, "MutationGot", spec.m)
	end
	Notify.celebrate(player, "hatch", {
		uid = uid,
		species = spec.s,
		rarity = rarity,
		mutation = spec.m,
		oneIn = oneIn,
		isNew = isNew,
		scripted = scripted,
		at = at,
	})
	hatchBanner(player, uid, spec.s, rarity, spec.m, oneIn)
end

local function stepVat(player: Player, data: { [string]: any })
	if not vatBuilt(data) or not vatNatural(data) then
		return
	end
	local list = hatches[player]
	if list ~= nil then
		for _, entry in list do
			if entry.kind == "vat" then
				return -- une goutte éclot déjà
			end
		end
	end
	local vat = data.vat
	local unix = Clock.unix()
	if vat.pending then
		if vatRoom(player) then
			-- une place s'est libérée : la goutte qui attendait éclot (échéance « due » gardée jusqu'à
			-- l'éclosion, comme ci-dessous)
			vat.pending = false
			vat.fillAt = unix
			DataService.markDirty(player, "vat")
			scheduleHatch(player, "vat")
			publishVat(player, data)
		end
		return
	end
	if not finite(vat.fillAt) or vat.fillAt <= 0 then
		vat.fillAt = math.floor(Clock.now() + vatInterval(data) + 0.5)
		DataService.markDirty(player, "vat")
		publishVat(player, data)
		return
	end
	if unix >= vat.fillAt then
		if vatRoom(player) then
			-- vat.fillAt reste l'échéance (passée) jusqu'à l'éclosion (executeHatch le remet à 0) : un
			-- départ pendant les 2 s ne perd jamais la goutte (elle éclot au retour)
			scheduleHatch(player, "vat")
			return
		else
			-- enclos ET Dodo pleins : la goutte attend (« Plein ! »), minuteur arrêté
			vat.pending = true
			vat.fillAt = 0
		end
		DataService.markDirty(player, "vat")
		publishVat(player, data)
	end
end

-- =============================================================================================
-- Fusions et combos
-- =============================================================================================

local function lockFusing(player: Player, uid: string, on: boolean)
	local set = fusing[player]
	if set == nil then
		set = {}
		fusing[player] = set
	end
	set[uid] = if on then true else nil
end

local function scheduleFuse(player: Player, a: string, b: string, step: number, delay: number, auto: boolean)
	local now = Clock.now()
	local list = fuseJobs[player]
	if list == nil then
		list = {}
		fuseJobs[player] = list
	end
	table.insert(list, {
		at = now + delay,
		startedAt = now,
		name = if delay <= Balance.Fusion.FuseDelay then "fusion" else "combo",
		a = a,
		b = b,
		step = step,
		auto = auto,
	})
	lockFusing(player, a, true)
	lockFusing(player, b, true)
end

-- Place du résultat d'une fusion : Bassin pour un combo, sinon enclos s'il y a de la place, sinon Dodo.
-- Les deux parents libèrent leurs places (enclos, Dodo ou Lettres) : deux jumeaux d'un Dodo plein
-- donnent un résultat au Dodo, jamais aux Lettres (revue : Lettres à 21 quand elles étaient pleines)
local function resultPlace(
	player: Player,
	data: { [string]: any },
	keep: string,
	other: string,
	wanted: string
): string
	local c = SquishyService.counts(player)
	local freed = { visible = 0, dodo = 0, mail = 0 }
	for _, uid in { keep, other } do
		local rec = data.squishies[uid]
		if type(rec) == "table" then
			if visibleAt(rec.at) then
				freed.visible += 1
			elseif rec.at == "dodo" then
				freed.dodo += 1
			elseif rec.at == "mail" then
				freed.mail += 1
			end
		end
	end
	local penRoom = c.pen + c.pool - freed.visible < c.penCapacity
	if wanted == "pool" and penRoom then
		local poolOthers = 0
		for uid, rec in data.squishies do
			if type(rec) == "table" and rec.at == "pool" and uid ~= keep and uid ~= other then
				poolOthers += 1
			end
		end
		if poolOthers < c.poolSlots then
			return "pool"
		end
	end
	if penRoom then
		return "pen"
	end
	if c.dodo - freed.dodo < Balance.Pens.Dodo then
		return "dodo"
	end
	-- jamais atteint (deux parents des Lettres sont refusés par FuseMenu et Tout fusionner) : place
	-- libérée aux Lettres
	return "mail"
end

local function executeFuse(player: Player, job: FuseJob): string?
	lockFusing(player, job.a, false)
	lockFusing(player, job.b, false)
	local data = profile(player)
	if data == nil then
		return nil
	end
	local ra, rb = data.squishies[job.a], data.squishies[job.b]
	if type(ra) ~= "table" or type(rb) ~= "table" or not FusionRules.areTwins(ra, rb) then
		return nil -- l'un a disparu ou a changé : rien
	end
	for _, uid in { job.a, job.b } do
		if isCarried(player, uid) or isEscaping(player, uid) or waitingOf[player] == uid then
			return nil
		end
	end
	-- règlement AVANT le changement de la collection : l'intervalle passé garde les deux parents
	EconomyService.settle(player)
	local g = G(player)
	local keep = FusionRules.keepUid(job.a, job.b, ra, rb)
	local other = if keep == job.a then job.b else job.a
	local wasVisible = { [job.a] = visibleAt(ra.at), [job.b] = visibleAt(rb.at) }
	local result = FusionRules.fuse(ra, rb, g, Clock.unix())
	-- lancer et FuseMenu : les deux sautent dans le Bassin (combo possible) ; Tout fusionner : enclos
	local wanted = if job.auto then "pen" else "pool"
	result.at = resultPlace(player, data, keep, other, wanted) :: any
	if not visibleAt(result.at) then
		result.z = Formulas.sizeAt(result, g)
	end
	data.squishies[other] = nil
	data.squishies[keep] = result
	if data.mount == other then
		data.mount = keep
	end
	if riding[player] == other then
		riding[player] = keep
		RanchService.setPublic(player, { ride = keep })
	end
	local slots = readyAt[player]
	if slots then
		slots[other] = nil
	end
	leaveFence(player, other)
	leaveFence(player, keep)
	DataService.markDirty(player, "mount")
	changed(player, other, wasVisible[other])
	changed(player, keep, wasVisible[keep])
	Signals.SquishyRemoved:Fire(player, other, "fusion")
	EconomyService.refresh(player)
	local coins = EconomyService.addCoins(
		player,
		Formulas.comboReward(job.step, EconomyService.squishyIncome(player, keep)),
		"Combo",
		"Gameplay"
	)
	Signals.Fused:Fire(player, keep, job.step)
	Signals.SquishyObtained:Fire(player, keep, "fusion")
	Notify.celebrate(player, "fusion", { uid = keep, step = job.step, stars = result.st, coins = coins })
	if job.step >= Balance.Fusion.BannerFrom then
		Notify.banner(if job.step >= Balance.Fusion.StampFrom then "combo5" else "combo4", {
			userId = player.UserId,
			name = displayName(player),
			n = job.step,
		}, player)
	end
	if job.auto and mergePlans[player] ~= nil then
		lockFusing(player, keep, true) -- le résultat reste réservé pour la paire suivante du plan
	end
	-- combo en chaîne : un jumeau du résultat attend dans le Bassin
	local chained = false
	if not job.auto and result.at == "pool" then
		local nextUid = FusionRules.nextInChain(poolRecords(data), keep)
		if nextUid ~= nil and busySquishy(player, nextUid) == nil then
			scheduleFuse(player, keep, nextUid, job.step + 1, Balance.Fusion.ComboDelay, false)
			chained = true
		end
	end
	if not job.auto and not chained then
		track(player, "ComboLength", job.step, { all = 0 }) -- fin d'une chaîne
	end
	publishBest(player, false)
	return keep
end

local function stepMerge(player: Player)
	local plan = mergePlans[player]
	if plan == nil then
		return
	end
	local jobs = fuseJobs[player]
	if jobs ~= nil and #jobs > 0 then
		return -- une paire est déjà programmée
	end
	local pair = plan.pairs[plan.index]
	if pair == nil then
		mergePlans[player] = nil
		track(player, "ComboLength", #plan.pairs, { all = 1 }) -- « Tout fusionner » terminé
		local set = fusing[player]
		if set then
			table.clear(set)
		end
		return
	end
	local step = plan.steps[plan.index] or 1
	plan.index += 1
	local delay = if plan.index == 2 then Balance.Fusion.FuseDelay else Balance.Fusion.ComboDelay
	scheduleFuse(player, pair[1], pair[2], step, delay, true)
end

-- =============================================================================================
-- Gestes (intentions)
-- =============================================================================================

-- Le squishy est-il dans le Bassin en cours de fusion, ou attendu par un plan ?
local function inMergePlan(player: Player): boolean
	return mergePlans[player] ~= nil
end

local function onPress(player: Player, uid: string, tClient: number): boolean
	return SquishyService.press(player, uid, tClient, nil)
end

local function onPickUp(player: Player, uid: string): boolean
	local rec, data = recordOf(player, uid)
	if rec == nil or data == nil or rec.at ~= "pen" then
		return false
	end
	if carried[player] ~= nil then
		feedback(player, "feedback.carrying")
		return false
	end
	local busy = busySquishy(player, uid)
	if busy ~= nil then
		feedback(player, busy)
		return false
	end
	local slot = RanchService.slotOf(player)
	local pos = validated(player)
	local center = Places.center(slot, data.squishies, uid)
	if slot == 0 or pos == nil or center == nil or not WorldLayout.inRanch(slot, pos) then
		return false
	end
	if not ZoneRules.withinReach(pos, rootOffset(player), center, PICK_RANGE) then
		feedback(player, "feedback.tooFar")
		return false
	end
	-- on descend tout seul pour « Prendre » (GDD §4.12)
	SquishyService.dismount(player, "pickup")
	carried[player] = { uid = uid, since = Clock.now() }
	leaveFence(player, uid)
	RanchService.setPublic(player, { carry = uid })
	return true
end

local function onPutDown(player: Player): boolean
	if carried[player] == nil then
		return false
	end
	SquishyService.endCarry(player, "putDown")
	return true
end

local function onThrow(player: Player): boolean
	local c = carried[player]
	local data = profile(player)
	if c == nil or data == nil then
		return false
	end
	local rec = data.squishies[c.uid]
	if type(rec) ~= "table" then
		SquishyService.endCarry(player, "gone")
		return false
	end
	local slot = RanchService.slotOf(player)
	local pos = validated(player)
	if slot == 0 or pos == nil then
		return false
	end
	if
		not ZoneRules.withinReach(
			pos,
			rootOffset(player),
			WorldLayout.anchor(slot, "pool"),
			Balance.Fusion.ThrowRange
		)
	then
		feedback(player, "feedback.tooFar")
		return false
	end
	if inMergePlan(player) then
		return false
	end
	local counts = SquishyService.counts(player)
	local uid = c.uid
	local pool = poolRecords(data)
	local outcome = FusionRules.throwOutcome(pool, rec, counts.poolSlots)
	-- jumeau LIBRE qui attend dans le Bassin (le plus ancien, ordre déterministe) ; un jumeau déjà pris
	-- par une fusion ne compte pas : le lancer devient une simple pose (revue)
	local twin: string? = nil
	if outcome == "fuse" then
		local free: { [string]: Types.SquishyRecord } = { [uid] = rec }
		for other, r in pool do
			if other ~= uid and busySquishy(player, other) == nil then
				free[other] = r
			end
		end
		twin = FusionRules.nextInChain(free, uid)
	end
	local others = 0
	for other in pool do
		if other ~= uid then
			others += 1
		end
	end
	local room = others < counts.poolSlots
	if twin == nil and not room then
		feedback(player, "feedback.poolFull")
		return false -- le squishy reste porté
	end
	carried[player] = nil
	RanchService.setPublic(player, { carry = "" })
	-- le Bassin ne dépasse jamais ses places (invariant n° 3), même pendant les 0,4 s d'une fusion :
	-- Bassin plein, le jumeau lancé garde sa place d'enclos (réservé par la fusion) jusqu'à la fusion,
	-- comme FuseMenu ; le résultat prend la place du jumeau dans le Bassin
	if room then
		local wasVisible = visibleAt(rec.at)
		rec.at = "pool"
		changed(player, uid, wasVisible)
	end
	if twin ~= nil then
		scheduleFuse(player, uid, twin, 1, Balance.Fusion.FuseDelay, false)
	end
	return true
end

local function onFuseMenu(player: Player, uidA: string, uidB: string): boolean
	if uidA == uidB or inMergePlan(player) then
		return false
	end
	local ra, data = recordOf(player, uidA)
	local rb = recordOf(player, uidB)
	if ra == nil or rb == nil or data == nil then
		return false
	end
	if ra.at == "mail" or rb.at == "mail" then
		return false
	end
	if not FusionRules.areTwins(ra, rb) then
		feedback(player, "feedback.noTwin")
		return false
	end
	for _, uid in { uidA, uidB } do
		local busy = busySquishy(player, uid)
		if busy ~= nil then
			feedback(player, busy)
			return false
		end
	end
	-- les deux sautent dans le Bassin : leur lieu reste celui d'avant jusqu'à la fusion (capacités
	-- jamais dépassées, même pendant 0,4 s) ; le résultat va au Bassin s'il y a une place
	leaveFence(player, uidA)
	leaveFence(player, uidB)
	if isCarried(player, uidA) or isCarried(player, uidB) then
		SquishyService.endCarry(player, "fuse")
	end
	scheduleFuse(player, uidA, uidB, 1, Balance.Fusion.FuseDelay, false)
	return true
end

local function onFuseAll(player: Player): boolean
	local data = profile(player)
	if data == nil or inMergePlan(player) then
		return false
	end
	local jobs = fuseJobs[player]
	if jobs ~= nil and #jobs > 0 then
		return false
	end
	local records = {}
	for uid, rec in data.squishies do
		if type(rec) == "table" and busySquishy(player, uid) == nil then
			records[uid] = rec
		end
	end
	local counts = SquishyService.counts(player)
	local plan = FusionRules.planMergeAll(records, counts.poolSlots)
	if #plan == 0 then
		feedback(player, "feedback.nothingToFuse")
		return false
	end
	local steps = FusionRules.comboSteps(plan, records)
	mergePlans[player] = { pairs = plan, steps = steps, index = 1 }
	for _, pair in plan do
		lockFusing(player, pair[1], true)
		lockFusing(player, pair[2], true)
		leaveFence(player, pair[1])
		leaveFence(player, pair[2])
	end
	stepMerge(player)
	return true
end

local function onMoveSquishy(player: Player, uid: string, to: string): boolean
	local rec, data = recordOf(player, uid)
	if rec == nil or data == nil then
		return false
	end
	local busy = busySquishy(player, uid)
	if busy ~= nil then
		feedback(player, busy)
		return false
	end
	local counts = SquishyService.counts(player)
	local wasVisible = visibleAt(rec.at)
	if to == "pen" then
		if rec.at == "pen" or rec.at == "mail" then
			return false
		end
		if rec.at == "dodo" then
			if counts.pen + counts.pool >= counts.penCapacity then
				feedback(player, "feedback.penFull")
				return false
			end
			-- règlement AVANT le changement : l'intervalle passé ne compte pas le dormeur
			EconomyService.settle(player)
			rec.zg = G(player) -- la taille repart de z, qui grandit de nouveau
		end
		rec.at = "pen"
	elseif to == "dodo" then
		if not visibleAt(rec.at) then
			return false
		end
		if counts.dodo >= Balance.Pens.Dodo then
			feedback(player, "feedback.dodoFull")
			return false
		end
		-- règlement AVANT le changement : l'intervalle passé compte encore ce squishy
		EconomyService.settle(player)
		rec.z = Formulas.sizeAt(rec, G(player)) -- taille figée en Dodo
		rec.zg = 0
		rec.at = "dodo"
		leaveFence(player, uid)
		if riding[player] == uid then
			SquishyService.dismount(player, "dodo")
		end
	else
		return false
	end
	changed(player, uid, wasVisible)
	EconomyService.refresh(player)
	publishBest(player, true)
	return true
end

local function onClaimMail(player: Player, uid: string): boolean
	local rec, data = recordOf(player, uid)
	if rec == nil or data == nil or rec.at ~= "mail" then
		return false
	end
	local counts = SquishyService.counts(player)
	if counts.pen + counts.pool < counts.penCapacity then
		-- règlement AVANT le changement : l'intervalle passé ne compte pas le nouveau venu
		EconomyService.settle(player)
		rec.zg = G(player)
		rec.at = "pen"
	elseif counts.dodo < Balance.Pens.Dodo then
		rec.at = "dodo"
	else
		feedback(player, "feedback.dodoFull")
		return false
	end
	changed(player, uid, false)
	EconomyService.refresh(player)
	publishBest(player, true)
	return true
end

-- Capacité d'enclos réduite pendant la session (pass Grand Ranch retiré par MonetizationService après
-- un remboursement) : le surplus de l'enclos et du Bassin (les plus récents d'abord, jamais un Meilleur
-- Ami ni un squishy occupé) va dormir au Dodo avec sa taille du moment (sinon aux Lettres) ; les
-- capacités ne sont jamais dépassées et aucune taille n'est perdue (revue)
local function fitCapacity(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	local c = SquishyService.counts(player)
	local over = c.pen + c.pool - c.penCapacity
	if over <= 0 then
		return
	end
	local list = {}
	for uid, rec in data.squishies do
		if type(rec) == "table" and visibleAt(rec.at) and rec.bf == 0 and busySquishy(player, uid) == nil then
			table.insert(list, uid)
		end
	end
	table.sort(list, function(a: string, b: string): boolean
		return Places.before(b, a) -- plus récents d'abord
	end)
	-- règlement AVANT le changement : l'intervalle passé compte encore ces squishies
	EconomyService.settle(player)
	local g = G(player)
	local dodo, mail = c.dodo, c.mail
	for _, uid in list do
		if over <= 0 then
			break
		end
		local at: Types.SquishyLocation
		if dodo < Balance.Pens.Dodo then
			at = "dodo"
			dodo += 1
		elseif mail < Balance.Pens.Mail then
			at = "mail"
			mail += 1
		else
			break
		end
		local rec = data.squishies[uid]
		rec.z = Formulas.sizeAt(rec, g) -- taille figée au Dodo
		rec.zg = 0
		rec.at = at
		leaveFence(player, uid)
		if riding[player] == uid then
			SquishyService.dismount(player, "capacity")
		end
		changed(player, uid, true)
		over -= 1
	end
	EconomyService.refresh(player)
	publishBest(player, true)
end

-- Vérifie un lot à vendre ou relâcher : rend la clé du premier refus, ou nil
local function checkBatch(
	player: Player,
	data: { [string]: any },
	uids: { string },
	confirmed: boolean
): string?
	local confirmNeeded = false
	for _, uid in uids do
		local rec = data.squishies[uid]
		if type(rec) ~= "table" then
			return "feedback.notOwned"
		end
		if rec.bf > 0 then
			return "feedback.bestFriendNoSell"
		end
		if rec.lk then
			return "feedback.locked"
		end
		local busy = busySquishy(player, uid)
		if busy ~= nil then
			return busy
		end
		if needsConfirm(rec) then
			confirmNeeded = true
		end
	end
	if confirmNeeded and not confirmed then
		return "" -- confirmation en 2 étapes exigée (le client l'a sautée) : refus muet
	end
	return nil
end

local function removeRecord(player: Player, data: { [string]: any }, uid: string, reason: string)
	local rec = data.squishies[uid]
	local wasVisible = rec ~= nil and visibleAt(rec.at)
	leaveFence(player, uid)
	if riding[player] == uid then
		SquishyService.dismount(player, reason)
	end
	data.squishies[uid] = nil
	if data.mount == uid then
		data.mount = ""
		DataService.markDirty(player, "mount")
	end
	local slots = readyAt[player]
	if slots then
		slots[uid] = nil
	end
	changed(player, uid, wasVisible)
	Signals.SquishyRemoved:Fire(player, uid, reason)
end

local function onSell(player: Player, uids: { string }, confirmed: boolean): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local refusal = checkBatch(player, data, uids, confirmed)
	if refusal ~= nil then
		if refusal ~= "" then
			feedback(player, refusal)
		end
		return false
	end
	-- règlement AVANT le départ : l'intervalle passé compte encore les squishies vendus
	EconomyService.settle(player)
	local total = 0
	for _, uid in uids do
		total += Formulas.sellValue(EconomyService.squishyIncome(player, uid))
	end
	for _, uid in uids do
		removeRecord(player, data, uid, "sell")
	end
	EconomyService.refresh(player)
	local coins = EconomyService.addCoins(player, total, "Sell", "Gameplay")
	if #uids > 1 then
		Notify.feedback(player, "feedback.tidyDone", { n = #uids, coins = coins }, "reward")
	else
		Notify.feedback(player, "feedback.sellDone", { coins = coins }, "reward")
	end
	publishBest(player, true)
	return true
end

local function onRelease(player: Player, uids: { string }, confirmed: boolean): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local refusal = checkBatch(player, data, uids, confirmed)
	if refusal ~= nil then
		if refusal ~= "" then
			feedback(player, refusal)
		end
		return false
	end
	-- règlement AVANT le départ : l'intervalle passé compte encore les squishies relâchés
	EconomyService.settle(player)
	local released = data.released
	for _, uid in uids do
		local rec = data.squishies[uid]
		table.insert(released, { s = rec.s, m = rec.m })
		removeRecord(player, data, uid, "release")
	end
	while #released > Balance.Release.MeadowKeep do
		table.remove(released, 1)
	end
	DataService.markDirty(player, "released")
	EconomyService.refresh(player)
	EconomyService.addFame(player, Balance.Fame.Release * #uids, "release")
	Notify.feedback(player, "feedback.releaseDone", {}, "reward")
	publishBest(player, true)
	return true
end

local function onSetLock(player: Player, uid: string, locked: boolean): boolean
	local rec = recordOf(player, uid)
	if rec == nil then
		return false
	end
	rec.lk = locked
	DataService.markDirtyEntry(player, "squishies", uid)
	return true
end

local function onSetBestFriend(player: Player, uid: string, slot: number): boolean
	local rec, data = recordOf(player, uid)
	if rec == nil or data == nil or slot < 1 or slot > MAX_BF then
		return false
	end
	if (data.R or 0) < Balance.Splorch.BestFriendSlotsAt[slot] then
		return false -- emplacement pas encore débloqué
	end
	if rec.bf == slot then
		return true
	end
	-- l'ancien titulaire perd son emplacement
	for other, r in data.squishies do
		if type(r) == "table" and r.bf == slot and other ~= uid then
			r.bf = 0
			changed(player, other, visibleAt(r.at))
		end
	end
	rec.bf = slot
	leaveFence(player, uid) -- un Meilleur Ami ne vient jamais à la clôture
	changed(player, uid, visibleAt(rec.at))
	return true
end

local function onSetMount(player: Player, uid: string): boolean
	local rec, data = recordOf(player, uid)
	if rec == nil or data == nil or rec.at ~= "pen" then
		return false
	end
	if SquishyService.saddle(player) < 1 then
		feedback(player, "feedback.noMount")
		return false
	end
	DataService.set(player, "mount", uid)
	if riding[player] ~= nil then
		riding[player] = uid
		RanchService.setPublic(player, { ride = uid })
	end
	return true
end

local function onRide(player: Player, on: boolean): boolean
	if not on then
		if riding[player] == nil then
			return false
		end
		SquishyService.dismount(player, "ride")
		return true
	end
	local data = profile(player)
	if data == nil or riding[player] ~= nil then
		return false
	end
	local saddle = SquishyService.saddle(player)
	if saddle < 1 then
		feedback(player, "feedback.noMount")
		return false
	end
	if carried[player] ~= nil then
		return false -- pendant le portage, Monter est ignoré (son Bump côté client)
	end
	local humanoid = humanoidOf(player)
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	local slot = RanchService.slotOf(player)
	local pos = MoveCheck.lastValid(player)
	if slot ~= 0 and pos ~= nil and ZoneRules.distXZ(pos, WorldLayout.anchor(slot, "pool")) <= POOL_ZONE then
		return false -- pas dans le Bassin
	end
	local uid = mountUid(player, data)
	if uid == nil then
		feedback(player, "feedback.noMount")
		return false
	end
	local stats = Formulas.rideStats(saddle)
	applyStats(player, stats)
	riding[player] = uid
	setRootOffset(player, stats.hipHeight - Balance.Ride.BaseHipHeight, stats.jumpHeight)
	RanchService.setPublic(player, { ride = uid, saddle = saddle })
	if not rideTracked[player] then
		-- première balade de la session : secondes de jeu (la monture est-elle trouvée ?)
		rideTracked[player] = true
		local played = if type(data.stats) == "table" then data.stats.playSeconds else 0
		track(player, "RideStart", if type(played) == "number" then math.floor(played) else 0)
	end
	return true
end

local function onEquipOutfit(player: Player, outfit: string, uid: string?): boolean
	local data = profile(player)
	if data == nil or not OUTFITS[outfit] then
		return false
	end
	local owned = data.outfits.owned[outfit]
	if type(owned) ~= "number" or owned < 1 then
		feedback(player, "feedback.notOwned")
		return false
	end
	if uid == nil then
		-- retirer : la tenue revient à la garde-robe (tous ses porteurs)
		local any = false
		for other, rec in data.squishies do
			if type(rec) == "table" and rec.o == outfit then
				rec.o = ""
				changed(player, other, visibleAt(rec.at))
				any = true
			end
		end
		return any
	end
	local rec = data.squishies[uid]
	if type(rec) ~= "table" then
		return false
	end
	if rec.o == outfit then
		return true
	end
	-- porteurs comptés dans les squishies (o == id) ; outfits.worn n'est jamais lu ni écrit
	local wearers = 0
	for _, r in data.squishies do
		if type(r) == "table" and r.o == outfit then
			wearers += 1
		end
	end
	if wearers >= owned then
		feedback(player, "feedback.notOwned")
		return false
	end
	rec.o = outfit
	changed(player, uid, visibleAt(rec.at))
	feedback(player, "feedback.outfitEquipped")
	return true
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

local function onCharacterReset(player: Player)
	SquishyService.endCarry(player, "respawn")
	SquishyService.dismount(player, "respawn")
end

local function watchCharacter(player: Player, character: Model)
	local trove = troves[player]
	if trove == nil then
		return
	end
	-- une seule connexion par joueur : celle du personnage précédent est coupée (aucune fuite)
	local previous = diedConns[player]
	if previous then
		previous:Disconnect()
		diedConns[player] = nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		diedConns[player] = humanoid.Died:Connect(function()
			onCharacterReset(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	if troves[player] ~= nil then
		return
	end
	local trove = Trove.new()
	troves[player] = trove
	trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterReset(player)
		watchCharacter(player, character)
	end)
	local character = player.Character
	if character ~= nil then
		watchCharacter(player, character)
	end
end

-- État public du ranch tiré de la collection : squishies visibles des autres (enclos et Bassin),
-- selle, Cuve, silhouette. Appelé par RanchService (onPublish) dès que le profil est chargé ET le
-- ranch attribué, dans n'importe quel ordre (aucune publication perdue)
local function publishAll(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	for uid, rec in data.squishies do
		if type(rec) == "table" and visibleAt(rec.at) and not isEscaping(player, uid) then
			RanchService.squishyOp(player, "add", uid, publicOf(player, uid, rec))
		end
	end
	local c = carried[player]
	RanchService.setPublic(player, {
		saddle = SquishyService.saddle(player),
		waiting = waitingOf[player] or "",
		carry = if c then c.uid else "",
		ride = riding[player] or "",
	})
	publishVat(player, data)
	publishBest(player, true)
end

local function onLoaded(player: Player, data: { [string]: any })
	if loadedPlayers[player] then
		return
	end
	loadedPlayers[player] = true
	readyAt[player] = readyAt[player] or {}
	-- la Cuve ne tourne que joueur présent (GDD §4.9) : le minuteur était en PAUSE pendant l'absence,
	-- il reprend avec le temps qui restait à la dernière présence (lastOnline, écrit à chaque
	-- sauvegarde) ; une goutte déjà due (départ pendant l'éclosion) tombe aussitôt
	local vat = data.vat
	if finite(vat.fillAt) and vat.fillAt > 0 then
		local interval = vatInterval(data)
		local last = data.lastOnline
		local remaining = if finite(last) and last > 0
			then math.clamp(vat.fillAt - last, 0, interval)
			else interval
		vat.fillAt = math.floor(Clock.now() + remaining + 0.5)
		DataService.markDirty(player, "vat")
	end
	publishAll(player)
end

local function onPlayerRemoving(player: Player)
	local trove = troves[player]
	if trove then
		trove:Clean()
	end
	troves[player] = nil
	local died = diedConns[player]
	if died then
		died:Disconnect()
	end
	diedConns[player] = nil
	carried[player] = nil
	riding[player] = nil
	waitingOf[player] = nil
	waitingSince[player] = nil
	escapingOf[player] = nil
	readyAt[player] = nil
	streakOf[player] = nil
	hatches[player] = nil
	fuseJobs[player] = nil
	mergePlans[player] = nil
	fusing[player] = nil
	scriptedDone[player] = nil
	lastBest[player] = nil
	loadedPlayers[player] = nil
end

-- Ordre d'envoi de la collection (DataService.setStreamOrder) : enclos et Bassin, puis Dodo, puis Lettres
local function streamOrder(data: { [string]: any }): { string }
	local rank = { pen = 1, pool = 1, dodo = 2, mail = 3 }
	local list = {}
	if type(data.squishies) == "table" then
		for uid in data.squishies do
			table.insert(list, uid)
		end
	end
	table.sort(list, function(a: string, b: string): boolean
		local ra = data.squishies[a]
		local rb = data.squishies[b]
		local ka = if type(ra) == "table" then rank[ra.at] or 4 else 4
		local kb = if type(rb) == "table" then rank[rb.at] or 4 else 4
		if ka ~= kb then
			return ka < kb
		end
		return Places.before(a, b)
	end)
	return list
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function SquishyService.Init()
	DataService.setStreamOrder("squishies", streamOrder)
	Guard.connect("Press", onPress)
	Guard.connect("PickUp", onPickUp)
	Guard.connect("PutDown", onPutDown)
	Guard.connect("Throw", onThrow)
	Guard.connect("FuseMenu", onFuseMenu)
	Guard.connect("FuseAll", onFuseAll)
	Guard.connect("MoveSquishy", onMoveSquishy)
	Guard.connect("ClaimMail", onClaimMail)
	Guard.connect("Sell", onSell)
	Guard.connect("Release", onRelease)
	Guard.connect("SetLock", onSetLock)
	Guard.connect("SetBestFriend", onSetBestFriend)
	Guard.connect("SetMount", onSetMount)
	Guard.connect("Ride", onRide)
	Guard.connect("EquipOutfit", onEquipOutfit)
end

-- Connexions et boucles
function SquishyService.Start()
	EconomyService.onSettle(onSettle)
	RanchService.onPublish(publishAll)
	-- un portage en cours est un maintien : l'attente sur une dalle est annulée (GDD §4.6)
	RanchService.setHoldCheck("carry", function(player: Player): boolean
		return carried[player] ~= nil
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.Loaded:Connect(function(player: Player, data: { [string]: any })
		Guard.try("squishy:loaded", onLoaded, player, data)
	end)
	-- pass Grand Ranch retiré (remboursement) : capacité relue, surplus rangé au Dodo
	MonetizationService.PassRevoked:Connect(function(player: Player, passKey: string)
		if passKey == "BigRanch" then
			Guard.try("squishy:capacity", fitCapacity, player)
		end
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		local data = DataService.get(player)
		if data ~= nil then
			task.spawn(Guard.try, "squishy:loaded", onLoaded, player, data)
		end
	end
end

local function stepPlayer(player: Player, data: { [string]: any }, actor: Types.TickActor?, now: number)
	-- éclosions dues
	local list = hatches[player]
	if list ~= nil and #list > 0 then
		local due = {}
		for i = #list, 1, -1 do
			if now >= list[i].at then
				table.insert(due, 1, table.remove(list, i))
			end
		end
		for _, entry in due do
			Guard.try("squishy:hatch", executeHatch, player, entry)
		end
	end
	-- fusions et combos dus (dans l'ordre de leur échéance)
	local jobs = fuseJobs[player]
	if jobs ~= nil and #jobs > 0 then
		table.sort(jobs, function(a: FuseJob, b: FuseJob): boolean
			return a.at < b.at
		end)
		while #jobs > 0 and now >= jobs[1].at do
			local job = table.remove(jobs, 1) :: FuseJob
			Guard.try("squishy:fuse", executeFuse, player, job)
		end
	end
	stepMerge(player)
	-- Cuve naturelle
	stepVat(player, data)
	-- portage : fini à la sortie du ranch (position validée), ou sans acteur (mort, réapparition), ou
	-- après le délai de sûreté (Balance.Carry.SafetySeconds, note INT-LR10 : le squishy retourne à sa place)
	local c = carried[player]
	if c ~= nil then
		local slot = RanchService.slotOf(player)
		if
			actor == nil
			or slot == 0
			or not WorldLayout.inRanch(slot, actor.pos)
			or data.squishies[c.uid] == nil
		then
			SquishyService.endCarry(player, "leftRanch")
		elseif not (now - c.since < Balance.Carry.SafetySeconds) then
			SquishyService.endCarry(player, "timeout")
		end
	end
	-- monture : descente sans personnage vivant ou en entrant dans le Bassin
	if riding[player] ~= nil then
		local humanoid = humanoidOf(player)
		local slot = RanchService.slotOf(player)
		if humanoid == nil or humanoid.Health <= 0 then
			SquishyService.dismount(player, "dead")
		elseif
			actor ~= nil
			and slot ~= 0
			and ZoneRules.distXZ(actor.pos, WorldLayout.anchor(slot, "pool")) <= POOL_ZONE
			and WorldLayout.inRanch(slot, actor.pos)
		then
			SquishyService.dismount(player, "pool")
		end
	end
	-- attente du Grand Splorch : filet de sûreté (file + spectacle dépassés)
	local since = waitingSince[player]
	if since ~= nil and StateTimeouts.expired("splorchQueue", since, now, WAITING_EXTRA) then
		SquishyService.setWaiting(player, nil)
		Guard.try("squishy:stateTimedOut", DiagnosticsService.stateTimedOut, "splorchQueue", player)
	end
	publishBest(player, false)
end

-- Tick : gouttes dues, fusions et combos dus, portage hors du ranch terminé
function SquishyService.step(now: number, actors: { [Player]: Types.TickActor })
	for player in loadedPlayers do
		local data = profile(player)
		if data ~= nil and player.Parent ~= nil then
			Guard.try("squishy:step", stepPlayer, player, data, actors[player], now)
		end
	end
end

-- Collection (lecture seule)
function SquishyService.records(player: Player): { [string]: Types.SquishyRecord }
	local data = profile(player)
	return if data then data.squishies else {}
end

-- Une ligne (lecture seule)
function SquishyService.get(player: Player, uid: string): Types.SquishyRecord?
	return (recordOf(player, uid))
end

-- Taille actuelle
function SquishyService.sizeOf(player: Player, uid: string, t: number?): number
	local rec = recordOf(player, uid)
	if rec == nil then
		return 0
	end
	return Formulas.sizeAt(rec, EconomyService.G(player, t))
end

-- Plus gros squishy (enclos et Bassin) et sa taille
function SquishyService.biggest(player: Player): (string?, number)
	local data = profile(player)
	if data == nil then
		return nil, 0
	end
	local g = G(player)
	local bestUid, best = nil, 0
	for uid, rec in data.squishies do
		if type(rec) == "table" and visibleAt(rec.at) then
			local size = Formulas.sizeAt(rec, g)
			if size > best or (size == best and bestUid ~= nil and Places.before(uid, bestUid)) then
				bestUid, best = uid, size
			end
		end
	end
	return bestUid, best
end

-- Places occupées et capacités
function SquishyService.counts(player: Player): Counts
	local data = profile(player)
	local out: Counts = { pen = 0, pool = 0, dodo = 0, mail = 0, penCapacity = 0, poolSlots = 0 }
	if data == nil then
		return out
	end
	for _, rec in data.squishies do
		if type(rec) == "table" and (out :: any)[rec.at] ~= nil then
			(out :: any)[rec.at] += 1
		end
	end
	local ok, bigRanch = pcall(MonetizationService.ownsPass, player, "BigRanch")
	out.penCapacity = Formulas.penCapacity(data.tiles.pens, ok and bigRanch == true)
	out.poolSlots = Formulas.poolSlots(QuestRules.familyEarned(data.dex, "axolo"))
	return out
end

-- Ajoute un squishy (enclos → Dodo → Lettres → pièces) ; rend (uid, lieu ou "coins")
function SquishyService.give(player: Player, spec: GiveSpec, source: string): (string?, string)
	local data = profile(player)
	if data == nil or type(spec) ~= "table" then
		return nil, "coins"
	end
	local c = SquishyService.counts(player)
	local at: Types.SquishyLocation
	if c.pen + c.pool < c.penCapacity then
		at = "pen"
	elseif c.dodo < Balance.Pens.Dodo then
		at = "dodo"
	elseif c.mail < Balance.Pens.Mail then
		at = "mail"
	else
		-- tout est plein : le bébé devient 60 s de revenu, avec un message (jamais une perte silencieuse)
		local coins = EconomyService.addIncomeSeconds(player, Balance.Babies.FallbackSeconds, "BabyFallback")
		Notify.feedback(player, "feedback.babyAsCoins", { coins = coins }, "reward")
		return nil, "coins"
	end
	if visibleAt(at) then
		-- règlement AVANT l'arrivée : l'intervalle passé ne compte pas le nouveau venu
		EconomyService.settle(player)
	end
	local uid, rec = newRecord(data, player, spec, at)
	changed(player, uid, false)
	Signals.SquishyObtained:Fire(player, uid, if type(source) == "string" then source else "gift")
	if visibleAt(rec.at) then
		EconomyService.refresh(player)
		publishBest(player, true)
	end
	return uid, at
end

-- Naissance scriptée de l'accueil (jumeau de Plop, premier vrai tirage) : une seule fois par session
-- et par sorte (QuestService ne la rejoue jamais au retour) ; éclosion 2 s plus tard, comme la Cuve
function SquishyService.hatchScripted(player: Player, kind: "twin" | "firstPull")
	local data = profile(player)
	if data == nil or (kind ~= "twin" and kind ~= "firstPull") then
		return
	end
	local done = scriptedDone[player]
	if done == nil then
		done = {}
		scriptedDone[player] = done
	end
	if done[kind] then
		return
	end
	done[kind] = true
	if kind == "twin" then
		-- leçon de fusion : Big Plop pose ton Plop (Meilleur Ami n° 1) dans le Bassin, où son jumeau le
		-- rejoindra (GDD §3, ~1:00)
		for uid, rec in data.squishies do
			if type(rec) == "table" and rec.bf == 1 and rec.at == "pen" and rec.s == Species.PLOP then
				local counts = SquishyService.counts(player)
				if counts.pool < counts.poolSlots and busySquishy(player, uid) == nil then
					rec.at = "pool"
					changed(player, uid, true)
				end
				break
			end
		end
	end
	scheduleHatch(player, kind)
end

-- Pression (chez soi, ou pet-sitting par visitor) ; récompenses et Signals.Pressed
function SquishyService.press(owner: Player, uid: string, tClient: number, visitor: Player?): boolean
	local rec, data = recordOf(owner, uid)
	if rec == nil or data == nil or not visibleAt(rec.at) then
		return false
	end
	if isCarried(owner, uid) or isEscaping(owner, uid) then
		return false
	end
	local slot = RanchService.slotOf(owner)
	if slot == 0 then
		return false
	end
	local presser = visitor or owner
	local pos = validated(presser)
	if pos == nil then
		return false
	end
	local center: Vector3?
	if visitor ~= nil then
		-- pet-sitting : squishy à la clôture (raison « petsit »), mesuré au centre de sa place à la clôture
		local uids, reason = RanchService.fenceOf(slot)
		local index = table.find(uids, uid)
		if index == nil or reason ~= "petsit" then
			return false
		end
		-- côté rue seulement (docs/04 §10.1 PetPress) : jamais depuis l'intérieur du ranch de l'ami
		if not ZoneRules.streetSideOfFence(slot, pos, PRESS_RANGE) then
			return false
		end
		center = WorldLayout.fencePoint(slot, index)
	else
		center = Places.center(slot, data.squishies, uid)
	end
	if center == nil or not ZoneRules.withinReach(pos, rootOffset(presser), center, PRESS_RANGE) then
		return false
	end
	local now = Clock.now()
	local ready = readyAt[owner]
	if ready == nil then
		ready = {}
		readyAt[owner] = ready
	end
	if (ready[uid] or 0) > now then
		return false -- recharge (refus muet : 12 / s au plus)
	end
	local t = PressTiming.clampClientTime(tClient, now)
	local perfect = PressTiming.isPerfect(t, PressTiming.offset(owner.UserId, uid))
	local kitty = QuestRules.familyEarned(data.dex, "kitty")
	local income = EconomyService.squishyIncome(owner, uid)
	local streak = 0
	local reward: number
	if visitor == nil then
		local s = streakOf[owner]
		local n = if s ~= nil and now - s.last <= Balance.Press.StreakTimeout then s.n else 0
		n = if perfect then math.min(n + 1, Balance.Press.StreakMax) else 0
		streakOf[owner] = { n = n, last = now }
		streak = n
		reward = Formulas.pressReward(income, perfect, streak, kitty)
	else
		-- le propriétaire reçoit la pression normale, SANS PERFECT (pet-sitting, GDD §6.4)
		reward = Formulas.pressReward(income, false, 0, kitty)
	end
	ready[uid] = now + Balance.Press.Cooldown
	local coins = EconomyService.addCoins(owner, reward, "Press", "Gameplay")
	RanchService.squishyOp(owner, "update", uid, publicOf(owner, uid, rec))
	local info: Signals.PressInfo = { uid = uid, perfect = perfect, streak = streak, visitor = visitor }
	Signals.Pressed:Fire(owner, info)
	if visitor == nil then
		Notify.celebrate(
			owner,
			"press",
			{ uid = uid, coins = coins, perfect = perfect, streak = streak, petsit = false }
		)
	else
		Notify.celebrate(
			visitor,
			"press",
			{ uid = uid, coins = 0, perfect = perfect, streak = 0, petsit = true }
		)
	end
	return true
end

-- uid porté
function SquishyService.carried(player: Player): string?
	local c = carried[player]
	return if c then c.uid else nil
end

-- Le squishy porté retourne à sa place
function SquishyService.endCarry(player: Player, reason: string)
	local _ = reason
	if carried[player] == nil then
		return
	end
	carried[player] = nil
	RanchService.setPublic(player, { carry = "" })
end

-- Sur sa monture
function SquishyService.riding(player: Player): boolean
	return riding[player] ~= nil
end

-- Descend (mort, Bassin, prise, panneau)
function SquishyService.dismount(player: Player, reason: string)
	local _ = reason
	if riding[player] == nil then
		return
	end
	riding[player] = nil
	applyStats(player, Formulas.rideStats(0))
	setRootOffset(player, 0, Balance.Ride.BaseJumpHeight)
	RanchService.setPublic(player, { ride = "" })
end

-- Grand Splorch : chaque squishy repasse à la taille 1 (z = 1, zg = 0)
function SquishyService.resetSizes(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	-- règlement AVANT le changement : l'intervalle passé garde les anciennes tailles
	EconomyService.settle(player)
	for uid, rec in data.squishies do
		if type(rec) == "table" then
			rec.z = 1
			rec.zg = 0
			changed(player, uid, visibleAt(rec.at))
		end
	end
	EconomyService.refresh(player)
	publishBest(player, true)
end

-- Squishy en attente de Grand Splorch (ni boopable, ni vendable, ni fusionnable)
function SquishyService.setWaiting(player: Player, uid: string?)
	if uid ~= nil then
		local rec = recordOf(player, uid)
		if rec == nil then
			return
		end
		if waitingOf[player] ~= uid or waitingSince[player] == nil then
			waitingSince[player] = Clock.now()
		end
		waitingOf[player] = uid
		if isCarried(player, uid) then
			SquishyService.endCarry(player, "waiting")
		end
		-- le squishy qui va s'envoler ne porte plus son cavalier
		if riding[player] == uid then
			SquishyService.dismount(player, "waiting")
		end
		-- pendant l'attente, aucun squishy de ce joueur à la clôture (GDD v1.3 §4.15)
		local slot = RanchService.slotOf(player)
		if slot ~= 0 then
			local _, reason = RanchService.fenceOf(slot)
			if reason == "rush" then
				RanchService.setFence(slot, {}, "rush")
			else
				leaveFence(player, uid)
			end
		end
		RanchService.setPublic(player, { waiting = uid })
	else
		waitingOf[player] = nil
		waitingSince[player] = nil
		RanchService.setPublic(player, { waiting = "" })
	end
end

-- Bonus de croissance du Rush : z += EconomyService.gNoBoost × seconds (Héros 3 600 s, retour seul
-- 1 800 s : Balance.RushSize), au plus une fois par squishy et par jour UTC (rec.gd = Clock.day()) ;
-- rend false si déjà accordé aujourd'hui (les pièces et la Fame restent dues)
function SquishyService.growFor(player: Player, uid: string, seconds: number): boolean
	local rec = recordOf(player, uid)
	if rec == nil or not finite(seconds) or seconds <= 0 then
		return false
	end
	local today = Clock.day()
	if rec.gd == today then
		return false
	end
	EconomyService.settle(player) -- l'intervalle passé garde l'ancienne taille
	rec.z = Formulas.clampSize(rec.z + EconomyService.gNoBoost(player) * seconds)
	rec.gd = today
	changed(player, uid, visibleAt(rec.at))
	EconomyService.refresh(player)
	publishBest(player, false)
	return true
end

-- uid en attente de Grand Splorch (nil = aucun) : RushService n'amène aucun squishy de ce joueur à la clôture
function SquishyService.waiting(player: Player): string?
	return waitingOf[player]
end

-- uid d'un squishy du joueur en fuite (setEscaping), nil = aucun : SplorchService refuse l'entrée dans la
-- file du Grand Splorch (Feedback waitEscape ; ChaseService, plus tardif, n'est jamais appelé)
function SquishyService.anyEscaping(player: Player): string?
	local set = escapingOf[player]
	if set == nil then
		return nil
	end
	local first: string? = nil
	for uid in set do
		if first == nil or Places.before(uid, first) then
			first = uid
		end
	end
	return first
end

-- En fuite (exclu du portage, de la vente, de la fusion)
function SquishyService.setEscaping(player: Player, uid: string, escaping: boolean)
	if type(uid) ~= "string" then
		return
	end
	local set = escapingOf[player]
	if set == nil then
		set = {}
		escapingOf[player] = set
	end
	if escaping then
		if recordOf(player, uid) == nil then
			return
		end
		set[uid] = true
		if isCarried(player, uid) then
			SquishyService.endCarry(player, "escape")
		end
		if riding[player] == uid then
			SquishyService.dismount(player, "escape")
		end
		leaveFence(player, uid)
	else
		set[uid] = nil
	end
	publishBest(player, true)
end

-- uid du Meilleur Ami n° slot
function SquishyService.bestFriend(player: Player, slot: number): string?
	local data = profile(player)
	if data == nil then
		return nil
	end
	for uid, rec in data.squishies do
		if type(rec) == "table" and rec.bf == slot then
			return uid
		end
	end
	return nil
end

-- Squishies prêts à venir à la clôture (aucun pendant l'attente du Grand Splorch)
function SquishyService.fenceCandidates(player: Player, ctx: RushRules.FenceCtx): { string }
	local data = profile(player)
	if data == nil or waitingOf[player] ~= nil then
		return {}
	end
	local c = carried[player]
	local fenceCtx: RushRules.FenceCtx = {
		now = if type(ctx) == "table" and finite(ctx.now) then ctx.now else Clock.unix(),
		carried = if c then c.uid else "",
		waiting = "",
		returnedThisRush = if type(ctx) == "table" and type(ctx.returnedThisRush) == "table"
			then ctx.returnedThisRush
			else {},
		moonBoopable = type(ctx) == "table" and ctx.moonBoopable == true,
	}
	local out = {}
	for uid, rec in data.squishies do
		if
			type(rec) == "table"
			and not isEscaping(player, uid)
			and not isFusing(player, uid)
			and riding[player] ~= uid
			and RushRules.fenceEligible(rec, fenceCtx, uid)
		then
			table.insert(out, uid)
		end
	end
	table.sort(out, Places.before)
	return out
end

-- Clock.now() où la recharge de pression finit
function SquishyService.readyAt(player: Player, uid: string): number
	local ready = readyAt[player]
	return if ready and ready[uid] then ready[uid] else 0
end

-- Selle gagnée 0 … 3
function SquishyService.saddle(player: Player): number
	local data = profile(player)
	return if data then Formulas.saddleLevel(data.biggestEver) else 0
end

-- Fonction ajoutée : ajoute `count` exemplaires d'une tenue à la garde-robe (outfits.owned[id]) ;
-- appelée par ProductService (tenues achetées) et QuestService (bavoir de Plop, jour 7) ; rend le
-- nombre possédé
function SquishyService.grantOutfit(player: Player, outfit: string, count: number?): number
	local data = profile(player)
	if data == nil or not OUTFITS[outfit] then
		return 0
	end
	local n = if finite(count) then math.max(0, math.floor(count :: number)) else 1
	local owned = data.outfits.owned
	owned[outfit] = (if type(owned[outfit]) == "number" then owned[outfit] else 0) + n
	DataService.markDirty(player, "outfits")
	return owned[outfit]
end

-- Fonction ajoutée : centre de la place d'un squishy d'enclos ou du Bassin (règle de Ranch/Places)
function SquishyService.placeOf(player: Player, uid: string): Vector3?
	local data = profile(player)
	local slot = RanchService.slotOf(player)
	if data == nil or slot == 0 then
		return nil
	end
	return Places.center(slot, data.squishies, uid)
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « carry » (porté),
-- « fusion », « combo », « hatch » (échéances dues) ; startedAt en Clock.now()
function SquishyService.openStates(): { Types.OpenState }
	local out: { Types.OpenState } = {}
	for player, c in carried do
		table.insert(out, { name = "carry", startedAt = c.since, player = player })
	end
	for player, list in hatches do
		for _, entry in list do
			table.insert(out, { name = "hatch", startedAt = entry.startedAt, player = player })
		end
	end
	for player, list in fuseJobs do
		for _, job in list do
			table.insert(out, { name = job.name, startedAt = job.startedAt, player = player })
		end
	end
	return out
end

return SquishyService
