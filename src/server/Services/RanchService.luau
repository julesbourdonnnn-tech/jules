--!strict
-- RanchService (paquet ranch, docs/04 §5.4, §11.4 ; GDD §6.1, §6.3, §4.6, §4.8, §12.5).
-- Ranchs 1-16 : attribution à l'arrivée (ranch libre le plus proche d'un ami Roblox présent,
-- IsFriendsWith sous pcall et en cache), placement du personnage à chaque apparition
-- (HumanoidRootPart attendu 10 s, PivotTo sur WorldLayout.spawnCFrame, repli sur la SpawnLocation
-- neutre de la place), serveur plein (message puis renvoi après 30 s sauf ranch libéré), poussée des
-- intrus à chaque tick (6 studs devant le portail, « C'est le ranch de … »), Pot encaissé à l'entrée
-- (≤ 5 studs à plat, pieds), dalles : entrée (ZoneRules.padStep, hystérésis 2,5 / 3,5 à plat) puis
-- Balance.Tiles.DwellSeconds dessus sans porter ni autre maintien = UN achat par entrée (HoldState
-- « tile » pour l'anneau ; pièces insuffisantes : achat au premier tick où elles suffisent, toujours une
-- fois par entrée, remarque A24), état public des ranchs (RanchSnapshot à l'arrivée, RanchPatch groupé
-- et numéroté par destinataire), clôtures (Fence : « rush » passe avant « petsit », chacun n'efface que
-- sa raison, "" réservé au ranch libéré, remarque A25). PlayerReady au premier placement réussi et au
-- plus tard 15 s après le chargement (StateTimeouts « playerReady »), même si le placement échoue.
-- Robustesse (docs/04 §17.3) : aucune règle ne lit la physique (positions validées du tick seulement) ;
-- chaque état minuté a son délai (openStates) et sa sortie ; aucun minuteur par task.delay (le tick
-- ferme les échéances).
-- Attribut Player « RanchSlot ». Émet PlayerReady, ServerMoved, WorldRequested. Remotes : RequestWorld
-- (handler) ; RanchSnapshot, RanchPatch, Fence, HoldState (« tile ») (envoi). Clés : aucune.
-- v2.0 (lot A2, docs/04 §27.5, §27.7, §27.14) : attributs Types.RanchAttributesV2 posés sur le modèle
-- du ranch (Ranches/<k>, répliqué à tous) par setV2Attributes, chacun derrière son interrupteur
-- (coupés : aucun attribut posé) ; RanchService calcule lui-même BestR [RecordR], Monuments
-- [Monuments], TapisTier, GloveTier, ApronTier [RanchTiers] au chargement et sur UpgradeBought,
-- Splorched, PrestigeApplied, RecordReached ; SplorchReady vient d'EconomyService (croissance) ; les
-- autres (Ascend, AscendReady, PetitSplorchAt, DecoPerso, HaloOn) des services qui les possèdent.
-- Place d'enclos offerte (N7) : offeredPlace (ranch reconstruit ; enclos déjà plein : Feedback
-- « +25 Confettis »), appelée après Prestige.apply. Dalle du Tapis au-delà du Tapis 12 (N21) : même
-- règle que PadRules (Tapis Étoilé [StarMat]). Pot encaissé dans le rayon de l'Aimant [Workshop].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Trove = require(Shared.Util.Trove)
local Balance = require(Shared.Config.Balance)
local Pads = require(Shared.Config.Pads)
local Cosmetics = require(Shared.Config.Cosmetics)
local Localization = require(Shared.Localization)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Logic.Formulas)
local Prestige = require(Shared.Logic.Prestige)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local TierRules = require(Shared.Logic.TierRules)
local WorldLayout = require(Shared.Logic.WorldLayout)
local ZoneRules = require(Shared.Logic.ZoneRules)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local Signals = require(script.Parent.Parent.Signals)
local Notify = require(script.Parent.Parent.Util.Notify)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Ranch.Guard)
local PadRules = require(script.Parent.Parent.Ranch.PadRules)
local DiagnosticsService = require(script.Parent.DiagnosticsService)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local RanchService = {}

local SLOTS = WorldLayout.Const.Ranches
local CHARACTER_WAIT = StateTimeouts.seconds("characterPlace")
local READY_DEADLINE = StateTimeouts.seconds("playerReady")
local FULL_DEADLINE = StateTimeouts.seconds("serverFull")
local INTRUDER_FEEDBACK_GAP = 2 -- s entre deux messages « C'est le ranch de … » au même joueur
-- un achat voulu (□ ou panneau) d'une dalle compte pour l'entrée en cours sur elle, ou pour l'entrée vue
-- par le serveur juste après (le client se voit sur la dalle un peu avant le serveur) : même délai que
-- l'attente (DwellSeconds + grâce)
local PAD_PURCHASE_GRACE = StateTimeouts.seconds("tileDwell")
local FENCE_MAX = 4 -- places à la clôture (WorldLayout.fencePoint 1 … 4)
local COLLISION_GROUP = "Characters"

-- Champs de RanchPublic (seuls champs acceptés par setPublic : aucun champ optionnel, docs/04 §10.6)
local PUBLIC_FIELDS: { [string]: boolean } = {
	slot = true,
	userId = true,
	name = true,
	hidden = true,
	R = true,
	fame = true,
	day = true,
	mode = true,
	shield = true,
	boopable = true,
	tiles = true,
	vat = true,
	pool = true,
	vatFill = true,
	growth = true,
	carry = true,
	ride = true,
	saddle = true,
	waiting = true,
	theme = true,
	flag = true,
	title = true,
	saddleColor = true,
	trail = true,
	best = true,
}

type Dwell = {
	tile: string, -- dalle de l'entrée en cours
	startedAt: number,
	endsAt: number,
	state: "dwell" | "retry" | "done", -- attente de 0,6 s ; pièces insuffisantes (rappel) ; entrée dépensée
}

type Fence = { uids: { string }, reason: "rush" | "petsit" | "" }

-- état de session
local slotOf: { [Player]: number } = {}
local ownerAt: { [number]: Player } = {}
local troves: { [Player]: Trove.Trove } = {}
local readyFired: { [Player]: boolean } = {}
local loaded: { [Player]: boolean } = {}
local readySince: { [Player]: number } = {} -- profil chargé ET ranch attribué : début du délai de 15 s
local placedOnce: { [Player]: boolean } = {}
local placingSince: { [Player]: number } = {}
local placeToken: { [Player]: number } = {}
local charConns: { [Player]: RBXScriptConnection } = {}
local fullSince: { [Player]: number } = {}
local fullSeq: { [Player]: number } = {} -- ordre d'arrivée des joueurs en attente (égalités d'horloge)
local fullCounter = 0
local friendCache: { [string]: boolean } = {}
local lastIntruderFeedback: { [Player]: number } = {}

local publics: { [number]: Types.RanchPublic } = {}
local mirror: { [number]: { [string]: Types.PublicSquishy } } = {}
local pendingFields: { [number]: { [string]: any } } = {}
local pendingOps: { Types.SquishyOp } = {}
local opIndex: { [string]: number } = {} -- "<slot>:<uid>" → index dans pendingOps (fusion des ops du tick)
local seqs: { [Player]: number } = {}
local fences: { [number]: Fence } = {}

local padInside: { [Player]: { [number]: boolean } } = {}
local potInside: { [Player]: boolean } = {}
local dwells: { [Player]: Dwell } = {}
local padBought: { [Player]: { tile: string, at: number } } = {} -- dernier achat voulu (□, panneau)

-- Attributs v2.0 du ranch (Types.RanchAttributesV2) : sorte de chaque attribut permis
local V2_ATTRIBUTES: { [string]: string } = {
	BestR = "number",
	Ascend = "number",
	SplorchReady = "boolean",
	AscendReady = "boolean",
	PetitSplorchAt = "number",
	Monuments = "number",
	DecoPerso = "string",
	HaloOn = "boolean",
	TapisTier = "number",
	GloveTier = "number",
	ApronTier = "number",
}
local DECO_PERSO_MAX = 64 -- caractères de l'attribut DecoPerso (12 identifiants séparés par des virgules)
-- attributs calculés ici (le reste est posé par son service) et leur interrupteur
local OWN_ATTRIBUTES: { [string]: string } = {
	BestR = "RecordR",
	Monuments = "Monuments",
	TapisTier = "RanchTiers",
	GloveTier = "RanchTiers",
	ApronTier = "RanchTiers",
}
-- interrupteurs de ces attributs (ordre fixe) : un changement en direct (LiveOps) les fait revoir au
-- tick suivant pour chaque joueur (relecture du lot A2 : sans lui, posés ou effacés seulement au
-- prochain achat ou prestige)
local OWN_FLAGS = { "RecordR", "Monuments", "RanchTiers" }
local ownPrint = 0 -- empreinte des OWN_FLAGS au dernier tick
local v2Values: { [Player]: { [string]: any } } = {} -- valeurs voulues (gardées jusqu'au ranch attribué)
local modelAttrs: { [number]: { [string]: boolean } } = {} -- attributs posés sur chaque modèle

local zoneHandlers: { [string]: (Player, string) -> () } = {}
local publishHooks: { (Player) -> () } = {}
local holdChecks: { [string]: (Player) -> boolean } = {}

local snapshotRemote: RemoteEvent
local patchRemote: RemoteEvent
local fenceRemote: RemoteEvent
local holdRemote: RemoteEvent

-- =============================================================================================
-- Outils
-- =============================================================================================

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

local function validSlot(slot: any): boolean
	return type(slot) == "number" and slot >= 1 and slot <= SLOTS and slot % 1 == 0
end

local function emptyTiles(): Types.Tiles
	return { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 }
end

-- État public d'un ranch libre (chaque champ a sa valeur « vide » : rien d'optionnel, remarque A27)
local function freePublic(slot: number): Types.RanchPublic
	return {
		slot = slot,
		userId = 0,
		name = "",
		hidden = false,
		R = 0,
		fame = 0,
		day = 0,
		mode = "cozy",
		shield = false,
		boopable = false,
		tiles = emptyTiles(),
		vat = false,
		pool = false,
		vatFill = 0,
		growth = { G = 0, g = 0, t = 0 },
		carry = "",
		ride = "",
		saddle = 0,
		waiting = "",
		theme = "",
		flag = "",
		title = "",
		saddleColor = "",
		trail = "",
		best = { s = 0, m = 0, z = 0, zg = 0 },
	}
end

-- Tous les champs d'un ranch partent dans le prochain patch
local function markAll(slot: number)
	local fields = {}
	for key, value in publics[slot] :: any do
		fields[key] = copy(value)
	end
	pendingFields[slot] = fields
end

local function setFields(slot: number, fields: { [string]: any })
	local pub = publics[slot] :: any
	local pending = pendingFields[slot]
	if pending == nil then
		pending = {}
		pendingFields[slot] = pending
	end
	for key, value in fields do
		if PUBLIC_FIELDS[key] and value ~= nil and key ~= "slot" then
			pub[key] = copy(value)
			pending[key] = copy(value)
		end
	end
end

-- Nom public : "" quand le joueur a caché son nom (le client écrit l'alias)
local function nameFields(player: Player): (string, boolean)
	local data = DataService.get(player)
	local hidden = data ~= nil and type(data.settings) == "table" and data.settings.hideName == true
	return if hidden then "" else player.DisplayName, hidden
end

local function languageOf(player: Player): any
	local data = DataService.get(player)
	local lang = data and type(data.settings) == "table" and data.settings.lang
	if lang == "en" or lang == "fr" then
		return lang
	end
	return Localization.languageFor(player.LocaleId)
end

local function stateTimedOut(name: string, player: Player?)
	Guard.try("ranch:stateTimedOut", DiagnosticsService.stateTimedOut, name, player)
end

-- Le joueur est-il dans un autre maintien (portage, boop, bol, Grand Splorch) ?
local function busy(player: Player): boolean
	for kind, check in holdChecks do
		local ok, result = Guard.try("ranch:holdCheck:" .. kind, check, player)
		if ok and result == true then
			return true
		end
	end
	return false
end

local function sendHold(player: Player, tile: string, endsAt: number, active: boolean)
	if player.Parent == nil then
		return
	end
	local payload: Types.HoldStatePayload = { kind = "tile", endsAt = endsAt, active = active, tile = tile }
	holdRemote:FireClient(player, payload)
end

-- =============================================================================================
-- PlayerReady, instantanés, clôtures
-- =============================================================================================

local function fenceTo(player: Player)
	for slot, fence in fences do
		if #fence.uids > 0 then
			local payload: Types.FencePayload =
				{ slot = slot, uids = table.clone(fence.uids), reason = fence.reason }
			fenceRemote:FireClient(player, payload)
		end
	end
end

local function fireReady(player: Player)
	if readyFired[player] or player.Parent == nil then
		return
	end
	local slot = slotOf[player]
	if slot == nil or not loaded[player] then
		return
	end
	readyFired[player] = true
	readySince[player] = nil
	RanchService.sendSnapshot(player)
	fenceTo(player)
	Signals.PlayerReady:Fire(player, slot)
end

-- Profil chargé ET ranch attribué : le délai de 15 s commence ; prêt tout de suite si déjà placé
local function checkReady(player: Player)
	if readyFired[player] or slotOf[player] == nil or not loaded[player] then
		return
	end
	if placedOnce[player] then
		fireReady(player)
	elseif readySince[player] == nil then
		readySince[player] = Clock.now()
	end
end

-- =============================================================================================
-- Placement du personnage
-- =============================================================================================

local function setCollision(part: Instance)
	if part:IsA("BasePart") then
		pcall(function()
			(part :: BasePart).CollisionGroup = COLLISION_GROUP
		end)
	end
end

local function onCharacter(player: Player, character: Model)
	local trove = troves[player]
	if trove == nil then
		return
	end
	for _, d in character:GetDescendants() do
		setCollision(d)
	end
	-- une seule connexion par joueur : celle du personnage précédent est coupée (aucune fuite)
	local previous = charConns[player]
	if previous then
		previous:Disconnect()
	end
	charConns[player] = character.DescendantAdded:Connect(setCollision)
	local token = (placeToken[player] or 0) + 1
	placeToken[player] = token
	placingSince[player] = Clock.now()
	task.spawn(function()
		local ok, root = pcall(function()
			return character:WaitForChild("HumanoidRootPart", CHARACTER_WAIT)
		end)
		if placeToken[player] ~= token or player.Parent == nil then
			return -- autre apparition entre-temps, ou départ
		end
		placingSince[player] = nil
		if ok and root ~= nil and slotOf[player] ~= nil and player.Character == character then
			RanchService.place(player)
		end
		-- échec : repli sur la SpawnLocation neutre de la place, nouvel essai à la prochaine apparition
	end)
end

-- =============================================================================================
-- Attribution, départ
-- =============================================================================================

local function friends(a: Player, b: Player): boolean
	local lo, hi = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = `{lo}:{hi}`
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local value = ok and result == true
	if ok then
		friendCache[key] = value
	end
	return value
end

local function ringDistance(a: number, b: number): number
	local d = math.abs(a - b)
	return math.min(d, SLOTS - d)
end

-- Ranch libre choisi pour ce joueur (0 = aucun) ; friendSlots = ranchs des amis présents
local function chooseSlot(friendSlots: { number }): number
	local best, bestDistance = 0, math.huge
	for slot = 1, SLOTS do
		if ownerAt[slot] == nil then
			if #friendSlots == 0 then
				return slot
			end
			for _, fs in friendSlots do
				local d = ringDistance(slot, fs)
				if d < bestDistance then
					best, bestDistance = slot, d
				end
			end
		end
	end
	return best
end

-- Champs publics lus dans le profil (lecture seule) : nom, jours de Plop, cosmétiques équipés
local function publishProfile(player: Player)
	local slot = slotOf[player]
	local data = DataService.get(player)
	if slot == nil or data == nil then
		return
	end
	local name, hidden = nameFields(player)
	local cosmetics = if type(data.cosmetics) == "table" then data.cosmetics else {}
	local function str(v: any): string
		return if type(v) == "string" then v else ""
	end
	local growth = if type(data.growth) == "table" then data.growth else {}
	local function num(v: any): number
		return if type(v) == "number" and v == v and math.abs(v) ~= math.huge then v else 0
	end
	setFields(slot, {
		name = name,
		hidden = hidden,
		R = num(data.R),
		fame = num(data.fame),
		growth = { G = num(growth.G), g = num(growth.g), t = num(growth.t) },
		day = num(data.plopDays),
		theme = str(cosmetics.theme),
		flag = str(cosmetics.flag),
		title = str(cosmetics.title),
		saddleColor = str(cosmetics.saddle),
		trail = str(cosmetics.trail),
	})
	RanchService.refreshBuild(player)
	-- services plus tardifs (SquishyService : squishies visibles, silhouette, selle, Cuve) : leur
	-- publication part même si le ranch est attribué APRÈS le chargement du profil (amis vérifiés)
	for _, hook in publishHooks do
		Guard.try("ranch:publishHook", hook, player)
	end
end

-- Pose sur le modèle du ranch les attributs v2.0 voulus (nil : effacé)
local function applyV2(slot: number, values: { [string]: any }?)
	if values == nil then
		return
	end
	local model = WorldService.ranchModel(slot)
	if model == nil then
		return
	end
	local set = modelAttrs[slot] or {}
	modelAttrs[slot] = set
	for name in V2_ATTRIBUTES do
		local value = values[name]
		if value ~= nil and model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
		if value ~= nil then
			set[name] = true
		end
	end
end

-- Ranch libéré : aucun attribut v2.0 du propriétaire précédent ne reste
local function clearV2(slot: number)
	local set = modelAttrs[slot]
	modelAttrs[slot] = nil
	local model = if set then WorldService.ranchModel(slot) else nil
	if set == nil or model == nil then
		return
	end
	for name in set do
		model:SetAttribute(name, nil)
	end
end

local function assign(player: Player, slot: number)
	slotOf[player] = slot
	ownerAt[slot] = player
	fullSince[player] = nil
	fullSeq[player] = nil
	player:SetAttribute("RanchSlot", slot)
	local pub = freePublic(slot)
	pub.userId = player.UserId
	-- protection de l'enfant (GDD §6.9, §13) : tant que le profil (réglage hideName) n'est pas lu, le
	-- nom reste vide et caché (le client écrit l'alias) ; publishProfile pose les vraies valeurs
	pub.name = ""
	pub.hidden = true
	publics[slot] = pub
	mirror[slot] = mirror[slot] or {}
	markAll(slot)
	Guard.try(
		"ranch:setRanchOwner",
		WorldService.setRanchOwner,
		slot,
		player.UserId,
		Cosmetics.RanchColors[slot]
	)
	if loaded[player] then
		publishProfile(player)
	end
	applyV2(slot, v2Values[player])
	local character = player.Character
	if character ~= nil then
		onCharacter(player, character)
	end
	checkReady(player)
end

local function onPlayerAdded(player: Player)
	if troves[player] ~= nil then
		return
	end
	local trove = Trove.new()
	troves[player] = trove
	trove:Connect(player.CharacterAdded, function(character: Model)
		if slotOf[player] ~= nil then
			onCharacter(player, character)
		end
	end)
	-- amis présents (IsFriendsWith peut céder : vérifié AVANT de choisir, le choix reste sans yield).
	-- Revue : la liste des autres joueurs est copiée avant les appels qui cèdent (jamais de parcours
	-- d'une table modifiée par une autre arrivée pendant le yield), et les ranchs des amis sont relus
	-- APRÈS (un ranch libéré puis repris par un inconnu pendant l'attente ne compte plus)
	local others: { Player } = {}
	for other in slotOf do
		if other ~= player then
			table.insert(others, other)
		end
	end
	local friendList: { Player } = {}
	for _, other in others do
		if other.Parent ~= nil and friends(player, other) then
			table.insert(friendList, other)
		end
	end
	if player.Parent == nil or troves[player] ~= trove or slotOf[player] ~= nil then
		return
	end
	local live: { number } = {}
	for _, friend in friendList do
		local slot = slotOf[friend]
		if slot ~= nil and ownerAt[slot] == friend then
			table.insert(live, slot)
		end
	end
	local slot = chooseSlot(live)
	if slot == 0 then
		fullSince[player] = Clock.now()
		fullCounter += 1
		fullSeq[player] = fullCounter
		Notify.feedback(player, "feedback.serverFull", {}, "warning")
		return
	end
	assign(player, slot)
end

local function onLoaded(player: Player)
	if troves[player] == nil or loaded[player] then
		return
	end
	loaded[player] = true
	if slotOf[player] ~= nil then
		publishProfile(player)
	end
	RanchService.refreshV2(player)
	checkReady(player)
end

local function releaseSlot(slot: number)
	ownerAt[slot] = nil
	publics[slot] = freePublic(slot)
	markAll(slot)
	local old = mirror[slot]
	mirror[slot] = {}
	if old then
		for uid in old do
			RanchService.squishyOpSlot(slot, "remove", uid, nil)
		end
	end
	RanchService.setFence(slot, {}, "")
	Guard.try("ranch:clearV2", clearV2, slot)
	Guard.try("ranch:setRanchOwner", WorldService.setRanchOwner, slot, 0, nil)
	Guard.try("ranch:setRanchBuild", WorldService.setRanchBuild, slot, emptyTiles(), false, false)
end

local function onPlayerRemoving(player: Player)
	local trove = troves[player]
	if trove then
		trove:Clean()
	end
	troves[player] = nil
	local charConn = charConns[player]
	if charConn then
		charConn:Disconnect()
	end
	charConns[player] = nil
	local slot = slotOf[player]
	slotOf[player] = nil
	-- cache d'amitié : les paires de ce joueur sont oubliées (jamais de croissance sans fin)
	local id = tostring(player.UserId)
	for key in friendCache do
		local lo, hi = string.match(key, "^(%-?%d+):(%-?%d+)$")
		if lo == id or hi == id then
			friendCache[key] = nil
		end
	end
	readyFired[player] = nil
	loaded[player] = nil
	readySince[player] = nil
	placedOnce[player] = nil
	placingSince[player] = nil
	placeToken[player] = nil
	fullSince[player] = nil
	fullSeq[player] = nil
	lastIntruderFeedback[player] = nil
	seqs[player] = nil
	padInside[player] = nil
	potInside[player] = nil
	dwells[player] = nil
	padBought[player] = nil
	v2Values[player] = nil
	if slot ~= nil and ownerAt[slot] == player then
		releaseSlot(slot)
		-- un joueur en attente de renvoi (serveur plein) reçoit le ranch libéré, plus ancien d'abord
		local waiting, order = nil, math.huge
		for other in fullSince do
			local seq = fullSeq[other] or math.huge
			if other.Parent ~= nil and seq < order then
				waiting, order = other, seq
			end
		end
		if waiting ~= nil then
			assign(waiting, slot)
		end
	end
end

-- =============================================================================================
-- Tick : intrus, Pot, dalles
-- =============================================================================================

local function pushIntruder(player: Player, k: number, now: number)
	local character = player.Character
	if character ~= nil then
		local out = WorldLayout.gateOutside(k)
		local gate = WorldLayout.anchor(k, "gate")
		local away = Vector3.new(out.X - gate.X, 0, out.Z - gate.Z)
		local look = if away.Magnitude > 1e-3 then out + away.Unit else out + Vector3.new(0, 0, 1)
		Guard.try("ranch:push", function()
			character:PivotTo(CFrame.lookAt(out, Vector3.new(look.X, out.Y, look.Z)))
		end)
		Signals.ServerMoved:Fire(player)
	end
	if now - (lastIntruderFeedback[player] or -math.huge) >= INTRUDER_FEEDBACK_GAP then
		lastIntruderFeedback[player] = now
		local pub = publics[k]
		if pub ~= nil and pub.name ~= "" and not pub.hidden then
			Notify.feedback(player, "feedback.ranchOf", { name = pub.name }, "info")
		else
			Notify.feedback(player, "feedback.ranchN", { n = k }, "info")
		end
	end
end

-- Fin d'une attente sur une dalle (sortie, portage, maintien, plus d'acteur)
local function cancelDwell(player: Player)
	local dwell = dwells[player]
	if dwell ~= nil and dwell.state == "dwell" then
		sendHold(player, dwell.tile, dwell.endsAt, false)
	end
	if dwell ~= nil then
		dwell.state = "done"
	end
end

local function callZone(kind: string, player: Player, key: string)
	local handler = zoneHandlers[kind]
	if handler ~= nil then
		Guard.try("ranch:zone:" .. kind, handler, player, key)
	end
end

-- Appelle le crochet « pad » ; rend true si la dalle a vraiment monté de niveau
local function firePad(player: Player, tile: string): boolean
	local data = DataService.get(player)
	local before = if data then PadRules.progress(data, tile) else 0
	callZone("pad", player, tile)
	local after = if data then PadRules.progress(data, tile) else 0
	return after > before
end

-- La dalle reste-t-elle achetable plus tard (pièces seulement) ?
local function stillBuyable(player: Player, tile: string): boolean
	local data = DataService.get(player)
	return data ~= nil and PadRules.visible(data, tile)
end

local function coinsEnough(player: Player, tile: string): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	-- prix de la ligne achetée par la dalle (Tapis Étoilé au-delà du Tapis 12, N21) ; A [JellyAscend]
	local id, level = PadRules.target(data, tile)
	local price = if id == tile
		then Formulas.tileCost(tile, PadRules.level(data, tile), data.R, Prestige.ascend(data))
		else UpgradeMath.price(id, level, Prestige.r(data), Prestige.ascend(data), Prestige.bestR(data))
	return type(data.coins) == "number" and price < math.huge and data.coins >= price
end

local function stepPads(player: Player, slot: number, actor: Types.TickActor, now: number)
	local inside = padInside[player]
	if inside == nil then
		inside = {}
		padInside[player] = inside
	end
	local feet = ZoneRules.feetY(actor.pos.Y, actor.rootOffset)
	local current: string? = nil
	local entered = false
	for _, key in Pads.Order do
		local def = Pads.Defs[key]
		local center = WorldLayout.padSocket(slot, def.socket)
		local distance = ZoneRules.distXZ(actor.pos, center)
		if math.abs(feet - center.Y) > Balance.Catch.MaxDY then
			distance = math.huge
		end
		local now_, justEntered = ZoneRules.padStep(inside[def.socket] == true, distance)
		inside[def.socket] = now_
		if now_ then
			current = key
			entered = entered or justEntered
		end
	end

	local dwell = dwells[player]
	if dwell ~= nil and dwell.tile ~= current then
		cancelDwell(player) -- sortie (ou passage direct sur une autre dalle)
		dwells[player] = nil
		dwell = nil
	end
	if current == nil then
		return
	end
	if entered or dwell == nil then
		if not entered then
			return -- déjà dedans sans entrée connue (après une coupure de canAct) : rien
		end
		-- nouvelle entrée : une attente seulement sur une dalle allumée, sans portage ni maintien, et
		-- pas juste après un achat voulu de cette dalle (□ reçu avant que le serveur voie l'entrée)
		local tile = current :: string
		local bought = padBought[player]
		local justBought = bought ~= nil and bought.tile == tile and now - bought.at <= PAD_PURCHASE_GRACE
		if stillBuyable(player, tile) and not busy(player) and not justBought then
			local endsAt = now + Balance.Tiles.DwellSeconds
			dwells[player] = { tile = tile, startedAt = now, endsAt = endsAt, state = "dwell" }
			sendHold(player, tile, endsAt, true)
		else
			dwells[player] = { tile = tile, startedAt = now, endsAt = now, state = "done" }
		end
		return
	end
	if dwell.state == "done" then
		return
	end
	if busy(player) then
		cancelDwell(player) -- portage ou autre maintien : annulé sans rien dépenser
		return
	end
	if dwell.state == "dwell" then
		if now >= dwell.endsAt then
			local bought = firePad(player, dwell.tile)
			if not bought and stillBuyable(player, dwell.tile) and not coinsEnough(player, dwell.tile) then
				dwell.state = "retry" -- pièces insuffisantes : rappel au premier tick où elles suffisent
			else
				dwell.state = "done"
			end
		end
	elseif dwell.state == "retry" then
		if not stillBuyable(player, dwell.tile) then
			dwell.state = "done"
		elseif coinsEnough(player, dwell.tile) then
			firePad(player, dwell.tile)
			dwell.state = "done" -- une seule fois par entrée
		end
	end
end

-- Rayon d'encaissement du Pot : Balance.Pot.Radius (v1.3) ; v2.0 [Workshop] : Aimant de l'Atelier
-- (Balance.PotV2.MagnetRadii, 5 / 8 / 11 / 14 studs) dans un profil v2
local function potRadius(player: Player): number
	if Features.get("Workshop") ~= true then
		return Balance.Pot.Radius
	end
	local data = DataService.get(player)
	if data == nil or not PadRules.v2Profile(data) then
		return Balance.Pot.Radius
	end
	return Balance.PotV2.MagnetRadii[UpgradeMath.level("magnet", data) + 1] or Balance.Pot.Radius
end

local function stepActor(player: Player, actor: Types.TickActor, now: number)
	local slot = slotOf[player]
	if slot == nil then
		return
	end
	local pos = actor.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	-- intrus : repoussé à chaque tick, même sans canAct ; aucune exception, même pour un ami
	local k = ZoneRules.intruder(slot, pos)
	if k ~= 0 and ownerAt[k] ~= nil then
		pushIntruder(player, k, now)
		potInside[player] = false
		padInside[player] = {}
		cancelDwell(player)
		dwells[player] = nil
		return
	end
	if not actor.canAct then
		-- n'achète ni n'encaisse rien ce tick : l'attente en cours est dépensée (annulée sans rien
		-- dépenser), mais l'état « dedans » est gardé : une coupure de canAct ne crée jamais une nouvelle
		-- entrée (aucun achat en double après un à-coup du réseau)
		cancelDwell(player)
		return
	end
	-- Pot : à l'entrée seulement (à plat ≤ rayon, pieds) ; rayon de l'Aimant de l'Atelier [Workshop]
	local pot = WorldLayout.anchor(slot, "pot")
	local onPot = ZoneRules.withinReach(pos, actor.rootOffset, pot, potRadius(player))
	if onPot and not potInside[player] then
		potInside[player] = true
		callZone("pot", player, "")
	elseif not onPot then
		potInside[player] = false
	end
	stepPads(player, slot, actor, now)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function RanchService.Init()
	snapshotRemote = Net.event("RanchSnapshot")
	patchRemote = Net.event("RanchPatch")
	fenceRemote = Net.event("Fence")
	holdRemote = Net.event("HoldState")
	for slot = 1, SLOTS do
		publics[slot] = freePublic(slot)
		mirror[slot] = {}
		fences[slot] = { uids = {}, reason = "" }
	end
	-- RequestWorld : renvoie l'instantané (seulement à un joueur déjà prêt) et émet WorldRequested
	Guard.connect("RequestWorld", function(player: Player): boolean
		if not readyFired[player] then
			return false
		end
		RanchService.sendSnapshot(player)
		fenceTo(player)
		Signals.WorldRequested:Fire(player)
		return true
	end)
end

-- Connexions et boucles
function RanchService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.Loaded:Connect(function(player: Player)
		onLoaded(player)
	end)
	-- v2.0 : attributs du ranch recalculés après tout achat et tout prestige (interrupteurs coupés :
	-- rien n'est posé)
	local function v2Changed(player: Player)
		Guard.try("ranch:refreshV2", RanchService.refreshV2, player)
	end
	Signals.UpgradeBought:Connect(v2Changed)
	Signals.Splorched:Connect(v2Changed)
	Signals.PrestigeApplied:Connect(v2Changed)
	Signals.RecordReached:Connect(v2Changed)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			onPlayerAdded(player)
			if DataService.isLoaded(player) then
				onLoaded(player)
			end
		end)
	end
end

-- Ranch du joueur (0 = aucun)
function RanchService.slotOf(player: Player): number
	return slotOf[player] or 0
end

-- Propriétaire présent du ranch
function RanchService.playerAt(slot: number): Player?
	if not validSlot(slot) then
		return nil
	end
	return ownerAt[slot]
end

-- PlayerReady déjà émis pour ce joueur dans cette session
function RanchService.isReady(player: Player): boolean
	return readyFired[player] == true
end

-- Replace le personnage à son point d'apparition (PivotTo + Signals.ServerMoved)
function RanchService.place(player: Player)
	local slot = slotOf[player]
	local character = player.Character
	if slot == nil or character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local ok = Guard.try("ranch:place", function()
		character:PivotTo(WorldLayout.spawnCFrame(slot))
	end)
	if not ok then
		return
	end
	Signals.ServerMoved:Fire(player)
	placedOnce[player] = true
	-- une réapparition remet la zone à zéro (nouvelle entrée nécessaire)
	potInside[player] = false
	padInside[player] = {}
	cancelDwell(player)
	dwells[player] = nil
	checkReady(player)
end

-- Empreinte des interrupteurs des attributs calculés ici (un bit par interrupteur ouvert)
local function ownFingerprint(): number
	local print = 0
	for i, key in OWN_FLAGS do
		if Features.get(key) == true then
			print = bit32.bor(print, bit32.lshift(1, i - 1))
		end
	end
	return print
end

-- Tick : intrus repoussés, Pot, entrées sur les dalles et attente de DwellSeconds (positions validées, canAct)
function RanchService.step(now: number, actors: { [Player]: Types.TickActor })
	-- v2.0 : interrupteur des attributs du ranch changé en direct → attributs revus pour chacun
	-- (coupés de bout en bout : jamais vrai, rien de fait)
	local print = ownFingerprint()
	if print ~= ownPrint then
		ownPrint = print
		for player in loaded do
			Guard.try("ranch:refreshV2", RanchService.refreshV2, player)
		end
	end
	-- états minutés de tous les joueurs (même sans acteur) : renvoi, arrivée, placement
	for player, since in fullSince do
		if player.Parent == nil then
			fullSince[player] = nil
			fullSeq[player] = nil
		elseif now >= since + FULL_DEADLINE then
			fullSince[player] = nil
			fullSeq[player] = nil
			Guard.try("ranch:serverFullKick", function()
				Analytics.event(player, "ServerFullKick", 1)
				player:Kick(Localization.get(languageOf(player), "kick.serverFull"))
			end)
		end
	end
	for player, since in readySince do
		if now >= since + READY_DEADLINE then
			stateTimedOut("playerReady", player)
			fireReady(player)
			readySince[player] = nil
		end
	end
	for player, since in placingSince do
		if StateTimeouts.expired("characterPlace", since, now) then
			placingSince[player] = nil -- le fil d'attente se termine seul ; état fermé ici
		end
	end
	-- dalles sans acteur (mort, non prêt) : attente annulée
	for player in dwells do
		if actors[player] == nil then
			cancelDwell(player)
			dwells[player] = nil
			padInside[player] = nil
			potInside[player] = nil
		end
	end
	for player, actor in actors do
		if slotOf[player] ~= nil and type(actor) == "table" then
			Guard.try("ranch:step:actor", stepActor, player, actor, now)
		end
	end
end

-- Clé de la dalle sur laquelle le joueur se tient (état « dedans » du tick), "" sinon : BuyTile choisit
-- source = "pad" (refus doux, aucun Feedback) ou "panel" (remarque A24)
function RanchService.onPad(player: Player): string
	local inside = padInside[player]
	if inside == nil then
		return ""
	end
	for _, key in Pads.Order do
		if inside[Pads.Defs[key].socket] then
			return key
		end
	end
	return ""
end

-- Fonction ajoutée (revue) : achat VOULU d'une dalle (BuyTile : □ « Acheter » sur la dalle, ou panneau)
-- appelé par EconomyService après un achat réussi. Il compte pour l'entrée en cours sur cette dalle
-- (l'anneau s'arrête, aucun 2e niveau à la fin des 0,6 s) et pour une entrée vue par le serveur juste
-- après (course réseau) : « un achat par entrée » (GDD §4.6), jamais un niveau acheté sans le vouloir.
function RanchService.notePadPurchase(player: Player, tile: string)
	if type(tile) ~= "string" then
		return
	end
	padBought[player] = { tile = tile, at = Clock.now() }
	local dwell = dwells[player]
	if dwell ~= nil and dwell.tile == tile and dwell.state ~= "done" then
		if dwell.state == "dwell" then
			sendHold(player, tile, dwell.endsAt, false)
		end
		dwell.state = "done"
	end
end

-- Champs de RanchPublic changés (fusionnés dans le prochain RanchPatch)
function RanchService.setPublic(player: Player, fields: { [string]: any })
	local slot = slotOf[player]
	if slot == nil or type(fields) ~= "table" then
		return
	end
	setFields(slot, fields)
end

-- Op d'un squishy visible sur un ranch donné (fusion des ops du même squishy dans le tick)
function RanchService.squishyOpSlot(
	slot: number,
	op: "add" | "remove" | "update",
	uid: string,
	rec: Types.PublicSquishy?
)
	if not validSlot(slot) or type(uid) ~= "string" then
		return
	end
	local list = mirror[slot]
	if op == "remove" then
		list[uid] = nil
	elseif rec ~= nil then
		list[uid] = copy(rec)
	else
		return
	end
	local key = `{slot}:{uid}`
	local entry: Types.SquishyOp =
		{ op = op, slot = slot, uid = uid, rec = if op == "remove" then nil else copy(rec) }
	local index = opIndex[key]
	if index ~= nil then
		local previous = pendingOps[index]
		if previous.op == "add" and op == "update" then
			entry.op = "add" -- ajouté puis changé dans le même tick : un seul ajout
		elseif previous.op == "add" and op == "remove" then
			entry.op = "remove"
		end
		pendingOps[index] = entry
	else
		table.insert(pendingOps, entry)
		opIndex[key] = #pendingOps
	end
end

-- Changement d'un squishy visible (enclos ou Bassin)
function RanchService.squishyOp(
	player: Player,
	op: "add" | "remove" | "update",
	uid: string,
	rec: Types.PublicSquishy?
)
	local slot = slotOf[player]
	if slot == nil then
		return
	end
	RanchService.squishyOpSlot(slot, op, uid, rec)
end

-- Squishies posés à la clôture ("rush" passe avant "petsit") ; effacer = setFence(slot, {}, maRaison),
-- sans effet si la raison actuelle est une autre ; "" réservé à RanchService (ranch libéré)
function RanchService.setFence(slot: number, uids: { string }, reason: "rush" | "petsit" | "")
	if not validSlot(slot) or type(uids) ~= "table" then
		return
	end
	if reason ~= "rush" and reason ~= "petsit" and reason ~= "" then
		return
	end
	local clean: { string } = {}
	for _, uid in uids do
		if type(uid) == "string" and #clean < FENCE_MAX and not table.find(clean, uid) then
			table.insert(clean, uid)
		end
	end
	local current = fences[slot]
	local nextFence: Fence
	if #clean == 0 then
		if reason ~= "" and current.reason ~= reason then
			return -- la fin d'une raison n'efface jamais la clôture d'une autre (remarque A25)
		end
		nextFence = { uids = {}, reason = "" }
	else
		if reason == "" then
			return -- "" n'efface que (ranch libéré) : jamais de squishies sans raison
		end
		if reason == "petsit" and current.reason == "rush" and #current.uids > 0 then
			return -- le Rush passe avant le pet-sitting
		end
		nextFence = { uids = clean, reason = reason }
	end
	local same = nextFence.reason == current.reason and #nextFence.uids == #current.uids
	if same then
		for i, uid in nextFence.uids do
			if current.uids[i] ~= uid then
				same = false
				break
			end
		end
	end
	if same then
		return
	end
	fences[slot] = nextFence
	local payload: Types.FencePayload =
		{ slot = slot, uids = table.clone(nextFence.uids), reason = nextFence.reason }
	for _, player in Players:GetPlayers() do
		if readyFired[player] then
			fenceRemote:FireClient(player, payload)
		end
	end
end

-- (uids à la clôture, raison)
function RanchService.fenceOf(slot: number): ({ string }, string)
	local fence = if validSlot(slot) then fences[slot] else nil
	if fence == nil then
		return {}, ""
	end
	return table.clone(fence.uids), fence.reason
end

-- État public d'un ranch (lecture seule)
function RanchService.publicOf(slot: number): Types.RanchPublic?
	if not validSlot(slot) then
		return nil
	end
	return publics[slot]
end

-- Crochet du service plus tardif (EconomyService) : step l'appelle quand le joueur entre sur le Pot
-- ("pot", "") ou au bout de l'attente sur une dalle ("pad", clé de la dalle)
function RanchService.setZoneHandler(kind: "pot" | "pad", handler: (Player, string) -> ())
	if (kind == "pot" or kind == "pad") and type(handler) == "function" then
		zoneHandlers[kind] = handler
	end
end

-- Fonction ajoutée : crochet « autre maintien » d'un service plus tardif (portage de SquishyService,
-- boop de RushService, bol de QuestService, Grand Splorch) ; un maintien en cours annule l'attente sur
-- une dalle sans rien dépenser (GDD §4.6). nil retire le crochet.
function RanchService.setHoldCheck(kind: string, check: ((Player) -> boolean)?)
	if type(kind) == "string" then
		holdChecks[kind] = check
	end
end

-- Fonction ajoutée : crochet de publication d'un service plus tardif, appelé quand le ranch d'un
-- joueur au profil chargé devient public (profil chargé ET ranch attribué, dans n'importe quel ordre)
function RanchService.onPublish(fn: (Player) -> ())
	if type(fn) == "function" then
		table.insert(publishHooks, fn)
	end
end

-- Relit le profil (dalles, accueil) et met à jour le ranch construit (WorldService.setRanchBuild) et l'état public
function RanchService.refreshBuild(player: Player)
	local slot = slotOf[player]
	local data = DataService.get(player)
	if slot == nil or data == nil then
		return
	end
	local tiles = if type(data.tiles) == "table" then data.tiles else emptyTiles()
	local onboarding = if type(data.onboarding) == "table" then data.onboarding else {}
	local done = onboarding.done == true
	local step = if type(onboarding.step) == "number" then onboarding.step else 0
	local vat = done or step >= Pads.FreeBuilds.vat.atStep
	local pool = done or step >= Pads.FreeBuilds.pool.atStep
	local snapshot: Types.Tiles = {
		snack = tiles.snack or 0,
		decor = tiles.decor or 0,
		pens = tiles.pens or 0,
		cozyBed = tiles.cozyBed == true,
		seen = tiles.seen or 0,
	}
	Guard.try("ranch:setRanchBuild", WorldService.setRanchBuild, slot, snapshot, vat, pool)
	setFields(slot, { tiles = snapshot, vat = vat, pool = pool })
end

-- Envoie le RanchPatch groupé du tick (appelé par ChaseService à la fin du tick)
function RanchService.flush()
	local ranches: { [string]: { [string]: any } } = {}
	local any = false
	for slot, fields in pendingFields do
		if next(fields) ~= nil then
			ranches[tostring(slot)] = fields
			any = true
		end
	end
	table.clear(pendingFields)
	local ops = pendingOps
	pendingOps = {}
	table.clear(opIndex)
	if not any and #ops == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		if readyFired[player] then
			local seq = (seqs[player] or 0) + 1
			seqs[player] = seq
			local payload: Types.RanchPatchPayload = { seq = seq, ranches = ranches, ops = ops }
			patchRemote:FireClient(player, payload)
		end
	end
end

-- RanchSnapshot complet à ce joueur (arrivée, RequestWorld, trou de suite)
function RanchService.sendSnapshot(player: Player)
	if player.Parent == nil then
		return
	end
	local ranches: { [string]: Types.RanchPublic } = {}
	local squishies: { [string]: { [string]: Types.PublicSquishy } } = {}
	for slot = 1, SLOTS do
		ranches[tostring(slot)] = copy(publics[slot])
		squishies[tostring(slot)] = copy(mirror[slot] or {})
	end
	local seq = (seqs[player] or 0) + 1
	seqs[player] = seq
	local payload: Types.RanchSnapshotPayload = { seq = seq, ranches = ranches, squishies = squishies }
	snapshotRemote:FireClient(player, payload)
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « playerReady »
-- (profil chargé et ranch attribué, PlayerReady pas encore émis), « serverFull » (renvoi en attente),
-- « characterPlace » (HumanoidRootPart attendu), « tileDwell » (attente de 0,6 s sur une dalle)
function RanchService.openStates(): { Types.OpenState }
	local out: { Types.OpenState } = {}
	for player, since in readySince do
		table.insert(out, { name = "playerReady", startedAt = since, player = player })
	end
	for player, since in fullSince do
		table.insert(out, { name = "serverFull", startedAt = since, player = player })
	end
	for player, since in placingSince do
		table.insert(out, { name = "characterPlace", startedAt = since, player = player })
	end
	for player, dwell in dwells do
		if dwell.state == "dwell" then
			table.insert(out, { name = "tileDwell", startedAt = dwell.startedAt, player = player })
		end
	end
	return out
end

-- =============================================================================================
-- v2.0 (lot A2) : attributs du ranch, place offerte
-- =============================================================================================

-- Attributs v2.0 du ranch du joueur (docs/04 §27.7 : Types.RanchAttributesV2, partiel permis) : seuls
-- les noms connus, de la bonne sorte (nombre fini, booléen, chaîne courte) ; `clear` : noms à effacer.
-- Valeurs gardées si le ranch n'est pas encore attribué ; seul ce qui change est posé
function RanchService.setV2Attributes(player: Player, attrs: { [string]: any }, clear: { string }?)
	if typeof(player) ~= "Instance" or type(attrs) ~= "table" then
		return
	end
	local values = v2Values[player]
	if values == nil then
		values = {}
		v2Values[player] = values
	end
	local changed: { [string]: any } = {}
	local cleared: { string } = {}
	for name, value in attrs do
		local kind = if type(name) == "string" then V2_ATTRIBUTES[name] else nil
		local ok = kind ~= nil
			and typeof(value) == kind
			and (kind ~= "number" or (value == value and value ~= math.huge and value ~= -math.huge))
			and (kind ~= "string" or #value <= DECO_PERSO_MAX)
		if ok and values[name] ~= value then
			values[name] = value
			changed[name] = value
		end
	end
	for _, name in if type(clear) == "table" then clear else {} do
		if type(name) == "string" and V2_ATTRIBUTES[name] ~= nil and values[name] ~= nil then
			values[name] = nil
			table.insert(cleared, name)
		end
	end
	local slot = slotOf[player]
	if slot == nil or ownerAt[slot] ~= player then
		return
	end
	applyV2(slot, changed)
	local model = if #cleared > 0 then WorldService.ranchModel(slot) else nil
	if model ~= nil then
		for _, name in cleared do
			model:SetAttribute(name, nil)
			local set = modelAttrs[slot]
			if set then
				set[name] = nil
			end
		end
	end
end

-- Attributs v2.0 calculés par RanchService depuis le profil : Record R [RecordR], Monuments
-- [Monuments], paliers du Tapis, des Gants et des tabliers de l'École [RanchTiers] ; un interrupteur
-- coupé efface ce qu'il avait posé (rien de posé tant que tout est coupé)
function RanchService.refreshV2(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local values = v2Values[player]
	local attrs: { [string]: any } = {}
	local clear: { string } = {}
	local on: { [string]: boolean } = {}
	for name, flag in OWN_ATTRIBUTES do
		on[name] = Features.get(flag) == true
		if not on[name] and values ~= nil and values[name] ~= nil then
			table.insert(clear, name)
		end
	end
	if on.BestR then
		attrs.BestR = Prestige.bestR(data)
	end
	if on.Monuments then
		attrs.Monuments = UpgradeMath.level("monument", data)
	end
	if on.TapisTier then
		local star = UpgradeMath.level("star", data)
		attrs.TapisTier = if star > 0
			then TierRules.of("star", star)
			else TierRules.of("snack", UpgradeMath.level("snack", data))
		attrs.GloveTier = TierRules.of("gloves", UpgradeMath.level("gloves", data))
		attrs.ApronTier = TierRules.of("school", UpgradeMath.level("school", data))
	end
	if next(attrs) == nil and #clear == 0 then
		return
	end
	RanchService.setV2Attributes(player, attrs, clear)
end

-- Place d'enclos offerte (N7, GDD §4.6 : Record R 2, 6, 11, 16), appelée après Prestige.apply : le
-- ranch construit montre la place de plus ; enclos déjà plein (14 niveaux) : Feedback
-- « Enclos déjà plein : +n Confettis » (n versés par EconomyService.addConfetti, source "fullPen")
function RanchService.offeredPlace(player: Player, fullPen: boolean, confetti: number)
	if DataService.get(player) == nil then
		return
	end
	RanchService.refreshBuild(player)
	if fullPen == true and type(confetti) == "number" and confetti == confetti and confetti >= 1 then
		Notify.feedback(player, "confetti.fullPen", { n = math.floor(confetti) }, "success")
	end
end

return RanchService
