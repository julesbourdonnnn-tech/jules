--!strict
-- HelperService (lot A3 ; GDD v2.0 §4.28, docs/04 §27.7, §27.13 N23, §27.14) : les Plopettes, côté
-- serveur, derrière l'interrupteur Helpers (coupé : rien n'est fait, rien n'est envoyé).
--   * Tick : step(now, acting?) appelé par le tick de 10 Hz de ChaseService (aucun Heartbeat ici) ;
--     acting = acteurs du tick (positions VALIDÉES) ; sans lui (specs), MoveCheck.lastValid.
--   * Nombre : une Plopette par Record R de Balance.Helpers.ByRecordR (Pip 2, Pop 4, Pim 6, Pom 8,
--     Puff 12) + la Plume (ligne de l'Atelier, atelier[8]) ; profil v2 seulement (Helpers/Rules).
--   * Cible et heure : le SERVEUR choisit un squishy de l'enclos ou du Bassin prêt depuis ReadyFor s (fin
--     de sa recharge ET arrivée à sa place : éclos, fusionné, lancé, posé, descendu de monture, revenu de
--     la clôture ; relecture A3), ni porté, ni monté (dessiné sous le joueur), ni en attente de Grand
--     Splorch, ni à la clôture, ni visé par une autre Plopette, à PLUS de
--     MinDistance studs à plat de la position validée du propriétaire (le plus gros revenu d'abord, comme
--     le modèle d'économie) ; tPress = maintenant + trajet (fonction pure des deux positions, 3 s au
--     plus). Rien n'est donné avant tPress : au premier tick ≥ tPress, TOUT est revérifié (propriétaire
--     présent et chargé, Plopettes éveillées et sans pause, squishy encore à sa place et libre, prêt depuis
--     ReadyFor s, règle des 12 studs avec la position validée de cet instant) ; sinon abandon et nouvelle
--     cible. Égalité avec la pression du joueur : sa pression (traitée avant le tick, recharge posée)
--     rend le squishy « pas prêt » : le joueur gagne.
--   * Récompense : Formulas.pressReward(revenu, PERFECT = non, série = 0, Kitty, Gants) × RewardShare,
--     créditée par EconomyService.addCoins (source « Helper ») ; Signals.HelperPressed ensuite, jamais
--     Signals.Pressed : ni jauge, ni objectif, ni quête, ni classement.
--   * Rythme : une pression toutes les IntervalBase − IntervalStep × École secondes par Plopette.
--   * Sieste : plus de NapAfter s sans intention ACCEPTÉE (Activity.lastIntent, N23 ; un stick calé ou
--     un déplacement ne comptent pas ; aucune avant la première intention de la séance) ; réveil à la
--     première intention acceptée. Pause : prestige du joueur (SplorchService.queuedKind ≠ nil : file
--     et spectacle ; canPrestige faux : file, spectacle, attente, Petit Splorch), BOOP RUSH à sa
--     clôture (Rush en cours et ranch en mode Rush, ou fuite de ses squishies), pause(player, reason).
--     Sieste et pause abandonnent les sauts en cours (aucune récompense) ; à la reprise, une Plopette
--     payée juste avant attend la fin de son intervalle (relecture A3 : pas de pression de plus).
--   * Réseau : HelperPress (non fiable) regroupé par tick : UN message par ranch et par destinataire
--     ({ ownerId, presses = { { helper, uid, tPress } } }), au propriétaire et aux joueurs qui dessinent
--     ce ranch en détail complet ; l'issue arrive par DataPatch (pièces).
--   * Départ, ranch changé, interrupteur coupé en direct : état oublié d'un coup (aucune récompense
--     après) ; rallumé : Plopettes reparties de la maisonnette.
--   * Coût : Rules.CHOOSE_PER_TICK passes de choix au plus par tick, premier ranch servi à tour de
--     rôle (aucun ranch affamé) ; un saut abandonné à tPress laisse la Plopette sur la cible (le
--     client y a dessiné le saut), le suivant part de là.
-- Maisonnette : WorldLayout.helperHouse (lot B4) si elle existe, sinon Z = 60, X = −28 (docs/04 §27.14).
-- Recharge de pression posée par une Plopette : SquishyService.helperPressed(owner, uid, now) quand ce
-- crochet existe (note d'intégration) ; d'ici là, recharge tenue ici (une Plopette ne represse jamais
-- un squishy dans sa recharge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Logic.Formulas)
local Prestige = require(Shared.Logic.Prestige)
local QuestRules = require(Shared.Logic.QuestRules)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local WorldLayout = require(Shared.Logic.WorldLayout)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Activity = require(Server.Util.Activity)
local MoveCheck = require(Server.Util.MoveCheck)
local Guard = require(Server.Chase.Guard)
local Places = require(Server.Ranch.Places)
local PadRules = require(Server.Ranch.PadRules)
local Rules = require(Server.Helpers.Rules)

local DataService = require(script.Parent.DataService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local EventService = require(script.Parent.EventService)
local RushService = require(script.Parent.RushService)
local SplorchService = require(script.Parent.SplorchService)

local HelperService = {}

-- =============================================================================================
-- État
-- =============================================================================================

local H = Balance.Helpers
local COOLDOWN = Balance.Press.Cooldown

type Helper = {
	index: number, -- 1 … 6 (Pip … Puff, Plume)
	moving: boolean,
	uid: string?,
	tPress: number,
	chosenAt: number,
	nextAt: number, -- plus tôt pour choisir une cible
	x: number,
	z: number,
	tx: number, -- place de la cible au choix (le saut y atterrit)
	tz: number,
}

type Owner = {
	slot: number,
	count: number,
	byRecord: number,
	interval: number,
	helpers: { Helper },
	refreshAt: number,
	mode: "active" | "nap" | "paused" | "none",
	reason: string?,
	homeX: number,
	homeZ: number,
	centerX: number,
	centerZ: number,
	done: { [string]: number }, -- uid → fin de la recharge posée par une Plopette
	-- relecture A3 (R-2) : arrivée de chaque squishy à son état actuel (enclos, Bassin, porté, monté,
	-- clôture, attente, ailleurs) : « prêt depuis ReadyFor s » compte aussi depuis cette arrivée
	seenKind: { [string]: string },
	since: { [string]: number },
}

local owners: { [Player]: Owner } = {}
local manual: { [Player]: string } = {}
local outbox: { [Player]: { Types.HelperPressEntry } } = {}
local counters: { [string]: number } = { Pressed = 0, Abandoned = 0, NoTarget = 0, Chosen = 0 }
local started = false
local chooseBudget = 0 -- passes de choix restantes dans ce tick (Rules.CHOOSE_PER_TICK)
-- tour de rôle : le joueur servi le premier change à chaque tick (le budget de choix n'affame jamais
-- les derniers de Players:GetPlayers)
local rotation = 0

-- tampons réutilisés (aucune allocation par tick pour la sélection)
local penUids: { string } = {}
local poolUids: { string } = {}
local candUids: { string } = {}
local candIncome: { [string]: number } = {}
local candX: { [string]: number } = {}
local candZ: { [string]: number } = {}
local fenceSet: { [string]: boolean } = {}
-- relecture A3 (R-1) : squishy monté par le propriétaire (dessiné sous lui, RanchPublic.ride), chargé
-- avec la clôture (loadFence)
local rideUid = ""
local targeted: { [string]: boolean } = {}
local due: { Helper } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function count(name: string)
	counters[name] = (counters[name] or 0) + 1
end

local function enabled(): boolean
	return Features.get("Helpers") == true
end

-- =============================================================================================
-- Lieux du ranch
-- =============================================================================================

-- Maisonnette (monde, à plat) : WorldLayout.helperHouse du lot B4 s'il existe (fonction du slot ou
-- point local), sinon la position écrite au contrat (docs/04 §27.14)
local function housePos(slot: number): (number, number)
	local wl: any = WorldLayout
	local accessor = wl.helperHouse
	if type(accessor) == "function" then
		local ok, p = pcall(accessor, slot)
		if ok and typeof(p) == "Vector3" and finite(p.X) and finite(p.Z) then
			return p.X, p.Z
		end
	elseif typeof(accessor) == "Vector3" then
		local p = WorldLayout.toWorld(slot, accessor)
		return p.X, p.Z
	end
	local lx, lz = Rules.houseLocal()
	local p = WorldLayout.toWorld(slot, Vector3.new(lx, 0, lz))
	return p.X, p.Z
end

local function ranchCenter(slot: number): (number, number)
	local p = WorldLayout.toWorld(slot, Vector3.new(0, 0, Rules.RANCH_CENTER_Z))
	return p.X, p.Z
end

-- =============================================================================================
-- Propriétaires
-- =============================================================================================

local function newHelper(index: number, x: number, z: number, nextAt: number): Helper
	return {
		index = index,
		moving = false,
		uid = nil,
		tPress = 0,
		chosenAt = 0,
		nextAt = nextAt,
		x = x,
		z = z,
		tx = x,
		tz = z,
	}
end

-- Abandonne le saut en cours (aucune récompense) ; la Plopette pourra choisir à `nextAt`
local function abandon(h: Helper, nextAt: number)
	if h.moving then
		h.moving = false
		h.uid = nil
		count("Abandoned")
	end
	h.nextAt = nextAt
end

-- Relit le nombre de Plopettes et l'intervalle (profil v2) ; ajoute ou retire des Plopettes
local function refresh(o: Owner, data: { [string]: any }, now: number)
	o.refreshAt = now + Rules.REFRESH
	local byRecord = Rules.byRecord(Prestige.bestR(data))
	local plume = UpgradeMath.level("plume", data)
	local n = Rules.count(Prestige.bestR(data), plume)
	o.byRecord = byRecord
	o.interval = Rules.interval(UpgradeMath.level("school", data))
	if n == o.count then
		return
	end
	local list: { Helper } = {}
	for k = 1, n do
		local index = Rules.index(k, byRecord)
		local kept: Helper? = nil
		for _, h in o.helpers do
			if h.index == index then
				kept = h
				break
			end
		end
		table.insert(
			list,
			kept or newHelper(index, o.homeX, o.homeZ, now + Rules.WAKE_DELAY + (k - 1) * Rules.WAKE_STAGGER)
		)
	end
	o.helpers = list
	o.count = n
end

local function newOwner(slot: number, data: { [string]: any }, now: number): Owner
	local hx, hz = housePos(slot)
	local cx, cz = ranchCenter(slot)
	local o: Owner = {
		slot = slot,
		count = 0,
		byRecord = 0,
		interval = H.IntervalBase,
		helpers = {},
		refreshAt = 0,
		mode = "none",
		reason = nil,
		homeX = hx,
		homeZ = hz,
		centerX = cx,
		centerZ = cz,
		done = {},
		seenKind = {},
		since = {},
	}
	refresh(o, data, now)
	return o
end

-- Raison de la pause du propriétaire (nil = aucune) ; rush = Rush en cours (calculé une fois par tick)
local function pauseReason(player: Player, rush: boolean): string?
	local m = manual[player]
	if m ~= nil then
		return m
	end
	if SplorchService.queuedKind(player) ~= nil or not SplorchService.canPrestige(player) then
		return "prestige"
	end
	if rush and RushService.isRush(player) then
		return "rush"
	end
	if SquishyService.anyEscaping(player) ~= nil then
		return "rush"
	end
	return nil
end

-- Change le mode d'un propriétaire : sieste et pause abandonnent les sauts ; la sieste ramène les
-- Plopettes à la maisonnette ; au réveil elles ressortent WAKE_DELAY s après, et jamais avant la fin
-- de leur intervalle (relecture A3, R-3 : une pause plus courte que l'intervalle ne rend aucune
-- pression de plus ; un saut abandonné, jamais payé, garde son heure d'avant le choix)
local function setMode(o: Owner, mode: "active" | "nap" | "paused", reason: string?, now: number)
	o.reason = reason
	if o.mode == mode then
		return
	end
	o.mode = mode
	if mode == "active" then
		for k, h in o.helpers do
			h.nextAt = math.max(h.nextAt, now + Rules.WAKE_DELAY + (k - 1) * Rules.WAKE_STAGGER)
		end
		return
	end
	for _, h in o.helpers do
		if h.moving then
			-- le client finit le saut coupé jusqu'à sa cible (aucun message pour un abandon) : la Plopette
			-- y est, le saut suivant part de là (relecture A3, R-4 ; même règle que A3-21)
			h.x, h.z = h.tx, h.tz
		end
		abandon(h, h.nextAt) -- sans choix pendant la pause (stepOwner) : l'heure reste celle d'avant
		if mode == "nap" then
			h.x, h.z = o.homeX, o.homeZ
		end
	end
end

-- =============================================================================================
-- Cible, vérification, récompense
-- =============================================================================================

-- Fin de la recharge vue par les Plopettes : celle de SquishyService (pression du joueur) ou celle
-- posée par une Plopette (tant que SquishyService ne la tient pas lui-même)
local function readyAt(player: Player, o: Owner, uid: string): number
	local a = SquishyService.readyAt(player, uid)
	local b = o.done[uid]
	if b ~= nil and b > a then
		a = b
	end
	-- relecture A3 (R-2) : arrivé à sa place (éclos, fusionné, lancé au Bassin, posé, descendu de
	-- monture, revenu de la clôture ou du Dodo) à `since` : « prêt » au plus tôt depuis cette arrivée
	local c = o.since[uid]
	if c ~= nil and c > a then
		a = c
	end
	return a
end

-- Clôture (fenceSet) et monture (rideUid) du ranch, lues une fois par passe
local function loadFence(slot: number)
	table.clear(fenceSet)
	local uids = RanchService.fenceOf(slot)
	for _, uid in uids do
		fenceSet[uid] = true
	end
	local pub = RanchService.publicOf(slot)
	local ride = if pub ~= nil then (pub :: any).ride else nil
	rideUid = if type(ride) == "string" then ride else ""
end

-- Squishy libre pour une Plopette (hors règle des 12 studs) : enclos ou Bassin, ni porté, ni monté
-- (relecture A3, R-1 : dessiné sous le joueur, sa place est vide), ni en attente, ni à la clôture
-- (fenceSet et rideUid chargés), prêt depuis ReadyFor s
local function free(player: Player, o: Owner, data: { [string]: any }, uid: string, now: number): boolean
	local rec = data.squishies[uid]
	if type(rec) ~= "table" or (rec.at ~= "pen" and rec.at ~= "pool") then
		return false
	end
	if SquishyService.carried(player) == uid or SquishyService.waiting(player) == uid then
		return false
	end
	if fenceSet[uid] or (rideUid ~= "" and rideUid == uid) then
		return false
	end
	return Rules.readyFor(readyAt(player, o, uid), now)
end

-- Revérification complète à tPress ; rend la place (x, z) si tout est encore vrai (le squishy est
-- encore à la place où le saut atterrit : à PLACE_MOVED studs près)
local PLACE_MOVED = 0.5
local function stillValid(
	player: Player,
	o: Owner,
	data: { [string]: any },
	h: Helper,
	uid: string,
	pos: Vector3,
	now: number
): (boolean, number, number)
	if player.Parent == nil or not DataService.isLoaded(player) or DataService.isClosing(player) then
		return false, 0, 0
	end
	if RanchService.slotOf(player) ~= o.slot then
		return false, 0, 0
	end
	loadFence(o.slot)
	if not free(player, o, data, uid, now) then
		return false, 0, 0
	end
	local center = Places.center(o.slot, data.squishies, uid)
	if center == nil then
		return false, 0, 0
	end
	local mx, mz = center.X - h.tx, center.Z - h.tz
	if mx * mx + mz * mz > PLACE_MOVED * PLACE_MOVED then
		return false, 0, 0 -- rangé ailleurs (Bassin ↔ enclos, places décalées) : le saut tombe à côté
	end
	if not Rules.farEnough(pos.X, pos.Z, center.X, center.Z) then
		return false, 0, 0
	end
	return true, center.X, center.Z
end

-- Pression accordée : récompense par le même chemin qu'une pression (EconomyService), recharge posée
local function grant(player: Player, o: Owner, data: { [string]: any }, h: Helper, uid: string, now: number)
	local income = EconomyService.squishyIncome(player, uid)
	local kitty = QuestRules.familyEarned(data.dex, "kitty")
	local gloves = EconomyService.pressBonus(player)
	local reward = Formulas.pressReward(income, false, 0, kitty, gloves, nil) * H.RewardShare
	o.done[uid] = now + COOLDOWN
	local hook = (SquishyService :: any).helperPressed
	if type(hook) == "function" then
		Guard.try("helpers:cooldown", hook, player, uid, now)
	end
	local coins = EconomyService.addCoins(player, reward, "Helper", "Gameplay")
	count("Pressed")
	Signals.HelperPressed:Fire(player, h.index, uid, coins)
end

-- Sauts arrivés (tPress atteint) : revérification, récompense ou abandon
local function resolve(player: Player, o: Owner, data: { [string]: any }, pos: Vector3?, now: number)
	for _, h in o.helpers do
		if h.moving and now >= h.tPress then
			local uid = h.uid :: string
			h.moving = false
			h.uid = nil
			local ok, x, z = false, 0, 0
			if pos ~= nil then
				ok, x, z = stillValid(player, o, data, h, uid, pos, now)
			end
			if ok then
				h.x, h.z = x, z
				h.nextAt = math.max(now, h.chosenAt + o.interval)
				grant(player, o, data, h, uid, now)
			else
				-- abandon : le client a dessiné le saut jusqu'à la cible (aucun message pour un abandon) :
				-- la Plopette y est, le saut suivant part de là ; nouvelle cible tout de suite
				count("Abandoned")
				h.x, h.z = h.tx, h.tz
				h.nextAt = now
			end
		end
	end
end

local function byIncome(a: string, b: string): boolean
	local ia, ib = candIncome[a], candIncome[b]
	if ia ~= ib then
		return ia > ib
	end
	return Places.before(a, b)
end

-- Places d'une liste d'uids (même règle que Places.center : rang par ordre de création)
local function placeAll(slot: number, uids: { string }, pool: boolean)
	table.sort(uids, Places.before)
	for k, uid in uids do
		local p = if pool then WorldLayout.poolSlot(slot, k) else WorldLayout.penSlot(slot, k)
		candX[uid], candZ[uid] = p.X, p.Z
	end
end

-- Clôture, monture et places de tous les squishies d'enclos et du Bassin (candX, candZ)
local function scan(o: Owner, data: { [string]: any })
	loadFence(o.slot)
	table.clear(penUids)
	table.clear(poolUids)
	for uid, rec in data.squishies do
		if type(rec) == "table" then
			if rec.at == "pen" then
				table.insert(penUids, uid)
			elseif rec.at == "pool" then
				table.insert(poolUids, uid)
			end
		end
	end
	table.clear(candX)
	table.clear(candZ)
	placeAll(o.slot, penUids, false)
	placeAll(o.slot, poolUids, true)
end

-- Relecture A3 (R-2) : note l'arrivée de chaque squishy à son état actuel (après scan) : enclos,
-- Bassin, porté, monté, à la clôture, en attente ou ailleurs (Dodo, Lettres) ; un changement d'état =
-- arrivée maintenant (« prêt depuis ReadyFor s » repart de là). Une place décalée dans le même lieu
-- (vente d'un squishy plus ancien) n'en est pas une : le squishy était prêt, il le reste. Première
-- observation du propriétaire (first) : tout est déjà là. Squishies disparus : oubliés.
local function observe(player: Player, o: Owner, data: { [string]: any }, now: number, first: boolean)
	local carried = SquishyService.carried(player)
	local waiting = SquishyService.waiting(player)
	for uid, rec in data.squishies do
		if type(rec) == "table" then
			local kind: string = if type(rec.at) == "string" then rec.at else "?"
			if carried == uid then
				kind = "carry"
			elseif rideUid ~= "" and rideUid == uid then
				kind = "ride"
			elseif waiting == uid then
				kind = "wait"
			elseif fenceSet[uid] then
				kind = "fence"
			end
			if o.seenKind[uid] ~= kind then
				o.seenKind[uid] = kind
				o.since[uid] = if first then -math.huge else now
			end
		end
	end
	for uid in o.seenKind do
		if type(data.squishies[uid]) ~= "table" then
			o.seenKind[uid] = nil
			o.since[uid] = nil
		end
	end
end

-- Relecture A3 (R-2) : à chaque tick, quel que soit le mode (sieste, pause, toutes en vol : aucun
-- choix), les états brefs du propriétaire (porté, monté, en attente) sont notés sur le squishy déjà
-- observé : posé ou descendu entre deux choix, son retour compte comme une arrivée. Trois lectures,
-- aucune allocation.
local function markBusy(player: Player, o: Owner)
	local carried = SquishyService.carried(player)
	if carried ~= nil and o.seenKind[carried] ~= nil then
		o.seenKind[carried] = "carry"
	end
	local pub = RanchService.publicOf(o.slot)
	local ride = if pub ~= nil then (pub :: any).ride else nil
	if type(ride) == "string" and ride ~= "" and o.seenKind[ride] ~= nil then
		o.seenKind[ride] = "ride"
	end
	local waiting = SquishyService.waiting(player)
	if waiting ~= nil and o.seenKind[waiting] ~= nil then
		o.seenKind[waiting] = "wait"
	end
end

-- Cibles des Plopettes dues (une passe par propriétaire et par tick)
local function choose(player: Player, o: Owner, data: { [string]: any }, pos: Vector3, now: number)
	table.clear(due)
	for _, h in o.helpers do
		if not h.moving and now >= h.nextAt then
			table.insert(due, h)
		end
	end
	if #due == 0 or chooseBudget <= 0 then
		return -- rien à choisir, ou budget du tick épuisé : au tick suivant
	end
	chooseBudget -= 1
	table.clear(targeted)
	for _, h in o.helpers do
		if h.moving and h.uid ~= nil then
			targeted[h.uid :: string] = true
		end
	end
	-- recharges des Plopettes finies depuis longtemps : oubliées (aucune table qui grossit)
	for uid, untilT in o.done do
		if untilT <= now - H.ReadyFor then
			o.done[uid] = nil
		end
	end
	scan(o, data)
	observe(player, o, data, now, false)
	table.clear(candUids)
	table.clear(candIncome)
	local px, pz = pos.X, pos.Z
	for uid, x in candX do
		if
			not targeted[uid]
			and Rules.farEnough(px, pz, x, candZ[uid])
			and free(player, o, data, uid, now)
		then
			table.insert(candUids, uid)
			candIncome[uid] = EconomyService.squishyIncome(player, uid)
		end
	end
	table.sort(candUids, byIncome)
	local entries = outbox[player]
	for k, h in due do
		local uid = candUids[k]
		if uid == nil then
			count("NoTarget")
			h.nextAt = now + Rules.RETRY
		else
			local x, z = candX[uid], candZ[uid]
			h.moving = true
			h.uid = uid
			h.tx, h.tz = x, z
			h.chosenAt = now
			h.tPress = now + Rules.travel(h.x, h.z, x, z)
			count("Chosen")
			if entries == nil then
				entries = {}
				outbox[player] = entries
			end
			table.insert(
				entries :: { Types.HelperPressEntry },
				{ helper = h.index, uid = uid, tPress = h.tPress }
			)
		end
	end
end

-- Oublie un propriétaire (départ, ranch changé, profil illisible)
local function drop(player: Player)
	owners[player] = nil
	outbox[player] = nil
end

local function stepOwner(player: Player, now: number, pos: Vector3?, rush: boolean)
	local data = DataService.get(player)
	if
		player.Parent == nil
		or data == nil
		or not PadRules.v2Profile(data)
		or type(data.squishies) ~= "table"
		or not RanchService.isReady(player)
	then
		drop(player)
		return
	end
	local slot = RanchService.slotOf(player)
	if slot == 0 then
		drop(player)
		return
	end
	local o = owners[player]
	if o == nil or o.slot ~= slot then
		o = newOwner(slot, data, now)
		owners[player] = o
		-- relecture A3 (R-2) : état de départ des squishies (déjà là, prêts selon leur recharge)
		scan(o :: Owner, data)
		observe(player, o :: Owner, data, now, true)
	end
	local owner = o :: Owner
	if now >= owner.refreshAt then
		refresh(owner, data, now)
	end
	if owner.count == 0 then
		return
	end
	markBusy(player, owner)
	if Rules.napping(Activity.lastIntent(player), now) then
		setMode(owner, "nap", nil, now)
		return
	end
	local reason = pauseReason(player, rush)
	if reason ~= nil then
		setMode(owner, "paused", reason, now)
		return
	end
	setMode(owner, "active", nil, now)
	resolve(player, owner, data, pos, now)
	if pos ~= nil then
		choose(player, owner, data, pos, now)
	else
		-- position inconnue (pas de personnage) : aucune cible ; les Plopettes réessaient plus tard
		for _, h in owner.helpers do
			if not h.moving and now >= h.nextAt then
				h.nextAt = now + Rules.RETRY
			end
		end
	end
end

-- HelperPress : un message par ranch et par destinataire, au propriétaire et aux joueurs proches
local function flush(acting: { [Player]: Types.TickActor }?, list: { Player })
	if next(outbox) == nil then
		return
	end
	local remote = Net.unreliable("HelperPress")
	local r2 = Rules.DETAIL_RADIUS * Rules.DETAIL_RADIUS
	for owner, entries in outbox do
		local o = owners[owner]
		if o ~= nil and owner.Parent ~= nil and #entries > 0 then
			local payload: Types.HelperPressPayload = { ownerId = owner.UserId, presses = entries }
			remote:FireClient(owner, payload)
			for _, other in list do
				if other ~= owner then
					local pos: Vector3? = nil
					if acting ~= nil then
						local a = acting[other]
						pos = if a ~= nil then a.pos else nil
					else
						pos = MoveCheck.lastValid(other)
					end
					if pos ~= nil then
						local dx, dz = pos.X - o.centerX, pos.Z - o.centerZ
						if dx * dx + dz * dz <= r2 then
							remote:FireClient(other, payload)
						end
					end
				end
			end
		end
	end
	table.clear(outbox)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des états ; aucun yield
function HelperService.Init() end

-- Connexions
function HelperService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player: Player)
		drop(player)
		manual[player] = nil
	end)
	Signals.SquishyRemoved:Connect(function(player: Player, uid: string)
		local o = owners[player]
		if o ~= nil and type(uid) == "string" then
			o.done[uid] = nil
		end
	end)
	-- reprise après un prestige ou un nouveau Record R : nombre de Plopettes relu au tick suivant
	local function reread(player: Player)
		local o = owners[player]
		if o ~= nil then
			o.refreshAt = 0
		end
	end
	Signals.PrestigeApplied:Connect(reread)
	Signals.RecordReached:Connect(reread)
end

-- Tick de 10 Hz (ChaseService) : rien du tout tant que l'interrupteur Helpers est coupé ; coupé en
-- direct, tout l'état est oublié d'un coup (aucune récompense, aucun message après)
function HelperService.step(now: number, acting: { [Player]: Types.TickActor }?)
	if not enabled() then
		if next(owners) ~= nil or next(outbox) ~= nil then
			table.clear(owners)
			table.clear(outbox)
		end
		return
	end
	if not finite(now) then
		return
	end
	local rush = Guard.call("helpers:rush", EventService.rushActive, false) == true
	chooseBudget = Rules.CHOOSE_PER_TICK
	local list = Players:GetPlayers()
	local n = #list
	rotation = if n > 0 then rotation % n + 1 else 0
	for k = 0, n - 1 do
		local player = list[(rotation + k - 1) % n + 1]
		local pos: Vector3? = nil
		if acting ~= nil then
			local a = acting[player]
			pos = if a ~= nil then a.pos else nil
		else
			pos = MoveCheck.lastValid(player)
		end
		-- pcall direct (sans table.pack de Guard.try) : une erreur est comptée, les autres ranchs continuent
		local ok, err = pcall(stepOwner, player, now, pos, rush)
		if not ok then
			Guard.caught("helpers:owner", err)
		end
	end
	for player in owners do
		if player.Parent == nil then
			drop(player)
		end
	end
	for player in manual do
		if player.Parent == nil then
			manual[player] = nil
		end
	end
	Guard.try("helpers:flush", flush, acting, list)
end

-- État des Plopettes du joueur : "nap" (sieste), "paused" (prestige, Rush, pause), "moving" (au moins
-- une en route), "idle" sinon (et sans Plopette, interrupteur coupé)
function HelperService.state(player: Player): Types.HelperState
	local o = if enabled() then owners[player] else nil
	if o == nil or o.count == 0 then
		return "idle"
	end
	if o.mode == "nap" then
		return "nap"
	elseif o.mode == "paused" then
		return "paused"
	end
	for _, h in o.helpers do
		if h.moving then
			return "moving"
		end
	end
	return "idle"
end

-- Pause demandée par un autre service (raison courte) jusqu'à resume(player)
function HelperService.pause(player: Player, reason: string)
	-- joueur déjà parti (PlayerRemoving passé) : rien de gardé
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return
	end
	manual[player] = if type(reason) == "string" and reason ~= "" then reason else "manual"
end

-- Fin de la pause demandée (les pauses de prestige et de Rush restent jugées au tick)
function HelperService.resume(player: Player)
	manual[player] = nil
end

-- Débogage et specs : Plopettes du joueur { index, moving, uid, tPress }
function HelperService.helpers(
	player: Player
): { { index: number, moving: boolean, uid: string?, tPress: number } }
	local out = {}
	local o = owners[player]
	if o == nil then
		return out
	end
	for _, h in o.helpers do
		table.insert(out, { index = h.index, moving = h.moving, uid = h.uid, tPress = h.tPress })
	end
	return out
end

-- Raison de la pause en cours (nil sans pause)
function HelperService.pauseReason(player: Player): string?
	local o = owners[player]
	return if o ~= nil and o.mode == "paused" then o.reason else nil
end

-- Compteurs (Pressed, Abandoned, NoTarget, Chosen) ; propriétaires suivis et pauses demandées (fuites :
-- specs)
function HelperService.counters(): { [string]: number }
	local out = table.clone(counters)
	local n = 0
	for _ in owners do
		n += 1
	end
	out.Owners = n
	local m = 0
	for _ in manual do
		m += 1
	end
	out.Manual = m
	return out
end

return HelperService
