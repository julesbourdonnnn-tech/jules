--!strict
-- NestService — paquet « economy » (docs/04-architecture.md §11.4).
-- Le Nid est la maison du joueur et son identité visible : attribution, couleur, perchoirs affichés,
-- constellation, réglages et cosmétiques. Clés de profil : settings, cosmetics, unlocks.
-- Responsabilités :
--   * attribution du Nid 1-12 dès PlayerAdded (joueurs déjà présents compris) : le Nid libre le
--     plus proche (distance entre centres) de celui d'un ami Roblox présent (Player:IsFriendsWith en
--     pcall, EN PARALLÈLE, attente bornée par Settings.FriendLookupDeadline, réponses mises en cache
--     et partagées : friendsCached), sinon le plus petit libre ; plus de Nid : slot 0 + Feedback
--     d'information (un Nid libéré plus tard lui est attribué) ; player.RespawnLocation = Spawn du
--     Nid ; personnage placé sur son Nid tourné vers le centre (PivotTo → Signals.ServerMoved) à
--     chaque apparition
--   * port sûr (inOwnHarbor) : jamais la seule position du client (il possède son personnage) ;
--     la position de confiance est la dernière validée par MoveCheck (tick de CongaService), ou le
--     placement serveur tant qu'aucun tick ne l'a remplacé ; refus pendant une restriction MoveCheck
--   * attributs de Nest_XX (OwnerUserId, OwnerName, Color, Supernovas, PerchCount, PerchData, Title,
--     NestTheme, LineStyle) et du Player (Slot, Zen, VIP, Title, LineStyle, NestTheme, Supernovas) —
--     docs §3.2 et §3.3 ; couleur du propriétaire (Cosmetics.NestColors[slot]) ou thème, via
--     WorldService.setNestAppearance ; Nid libéré (gris) au départ
--   * perchoirs : setPerchCount (WorldService) et PerchData "code.étoiles,…" (meilleurs d'abord,
--     poussés par AtlasService) ; mémorisés si le Nid n'est pas encore attribué
--   * constellation : attribut Supernovas mis à jour sur Signals.Supernova (rendu client) ;
--     l'anneau de progression vers la Supernova est calculé par le client (glow, supernovas répliqués)
--   * Signals.PlayerReady(player, slot) une fois, quand le profil est chargé ET le Nid attribué
--   * réglages : remote SetSetting — clés de Config/Settings, type attendu, valeurs ; zen : dans son
--     port sûr, recharge 60 s, Feedback zenOn/zenOff, Analytics ZenToggled ; quitter le Zen exige
--     une file VIDE (Feedback zenBankFirst) : une file attrapée sans risque garde le plafond Zen du
--     Conga Bonus jusqu'à son encaissement (longueur suivie par Signals.LineChanged) ; privateNoSnip :
--     propriétaire du serveur privé (réglage de serveur en mémoire) ; Signals.SettingChanged
--   * cosmétiques : remote EquipCosmetic, unlock() (stocké + Celebrate "unlock"), grantTemporary()
--     (session), hasUnlock() (gratuit, stocké, temporaire, pass, R atteint, statistique, Atlas)
-- GDD : §3 (0,0 s), §4.16 (Zen, serveurs privés), §5.3, §6.1, §6.6, §10.3, §11.3.
-- Dépendances : DataService, MonetizationService (via Economy/PassEffects), WorldService,
-- Logic/WorldLayout, Config/{Settings,Cosmetics,Zones,Balance}, Signals, Util/Notify,
-- Util/RateLimit, Util/Analytics, Util/MoveCheck (lecture seule), Shared/Util/Clock,
-- Economy/Collection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local SettingsConfig = require(Shared.Config.Settings)
local Zones = require(Shared.Config.Zones)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local Analytics = require(Server.Util.Analytics)
local MoveCheck = require(Server.Util.MoveCheck)
local Collection = require(Server.Economy.Collection)
local PassEffects = require(Server.Economy.PassEffects)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local WorldService = require(script.Parent.WorldService)

local NestService = {}

-- Réglages techniques (modifiables par les tests avant l'arrivée des joueurs)
NestService.Settings = {
	-- attente maximale (s) des réponses d'amitié avant de choisir un Nid : au-delà, plus petit libre
	FriendLookupDeadline = 1,
}

-- Hauteur du personnage au-dessus du repère du Nid au sol (placement, studs)
local SPAWN_LIFT = 3
-- Longueur maximale d'un id de cosmétique ou d'une clé de réglage venant du client
local ID_MAX_LENGTH = 32
local VALUE_MAX_LENGTH = 16

-- Genres de cosmétiques : nom du remote (singulier) → genre stocké (pluriel), table de config,
-- champ de profile.cosmetics, attribut
type KindInfo = { kind: string, defs: { [string]: any }, field: string, attribute: string, default: string }

local KINDS: { [string]: KindInfo } = {
	styles = {
		kind = "styles",
		defs = Cosmetics.Styles,
		field = "style",
		attribute = "LineStyle",
		default = "default",
	},
	titles = { kind = "titles", defs = Cosmetics.Titles, field = "title", attribute = "Title", default = "" },
	themes = {
		kind = "themes",
		defs = Cosmetics.Themes,
		field = "nestTheme",
		attribute = "NestTheme",
		default = "default",
	},
}
local REMOTE_KINDS: { [string]: string } = { style = "styles", title = "titles", theme = "themes" }

local slotOwner: { [number]: Player } = {}
local playerSlot: { [Player]: number } = {}
local assigning: { [Player]: boolean } = {}
local friendCache: { [Player]: { [number]: boolean } } = {}
local zenChangedAt: { [Player]: number } = {}
local temporary: { [Player]: { [string]: { [string]: boolean } } } = {}
local perchCountOf: { [Player]: number } = {}
local perchDataOf: { [Player]: string } = {}
local readyFired: { [Player]: boolean } = {}
local charConns: { [Player]: RBXScriptConnection } = {}
-- Dernier placement serveur : position du personnage `character` juste après PivotTo, et dernière
-- position validée de MoveCheck à ce moment (`before`) ; le placement fait foi tant que MoveCheck
-- n'a pas changé de référence (aucun tick depuis)
type Placement = { character: Model, pos: Vector3, before: Vector3? }
local placed: { [Player]: Placement } = {}
-- Longueur de la file (Signals.LineChanged) ; absente = file vide
local lineLength: { [Player]: number } = {}
-- joueurs partis (faible) : un thread d'attribution qui reprend après un yield s'arrête
local gone: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local privateNoSnip = false

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function kindInfo(kind: string): KindInfo?
	return KINDS[kind] or KINDS[REMOTE_KINDS[kind] or ""]
end

local function ownerColor(slot: number): Color3
	return Cosmetics.NestColors[slot] or Cosmetics.FreeNestColor
end

-- Amitié déjà connue (dans un sens ou dans l'autre) ; nil si jamais vérifiée
local function cachedFriendship(a: Player, b: Player): boolean?
	local cache = friendCache[a]
	local known = if cache then cache[b.UserId] else nil
	if known == nil then
		local other = friendCache[b]
		known = if other then other[a.UserId] else nil
	end
	return known
end

-- Amitié Roblox (yield : appel web) ; un échec compte comme « pas amis » sans être mémorisé
local function isFriend(player: Player, other: Player): boolean
	local known = cachedFriendship(player, other)
	if known ~= nil then
		return known
	end
	local ok, result = pcall(function()
		return player:IsFriendsWith(other.UserId)
	end)
	if not ok then
		warn(`[NestService] IsFriendsWith impossible pour {player.Name} :`, result)
		return false
	end
	local friends = result == true
	-- l'appel yield : rien n'est mémorisé si l'un des deux est parti entre-temps (fuite)
	if gone[player] or gone[other] then
		return friends
	end
	local cache = friendCache[player]
	if not cache then
		cache = {}
		friendCache[player] = cache
	end
	cache[other.UserId] = friends
	local otherCache = friendCache[other]
	if otherCache then
		otherCache[player.UserId] = friends
	end
	return friends
end

-- Cosmétiques réellement portés (un cosmétique équipé mais plus possédé est affiché par défaut)
local function effective(player: Player, data: { [string]: any }, info: KindInfo): string
	local cosmetics = data.cosmetics
	local id = if type(cosmetics) == "table" then cosmetics[info.field] else nil
	if type(id) ~= "string" or id == "" then
		return info.default
	end
	if NestService.hasUnlock(player, info.kind, id) then
		return id
	end
	return info.default
end

-- Pose les attributs du joueur et de son Nid (identité, cosmétiques, constellation, perchoirs)
local function applyIdentity(player: Player)
	if player.Parent == nil then
		return
	end
	local slot = playerSlot[player] or 0
	local data = DataService.get(player)
	player:SetAttribute("Slot", slot)
	local nest = if slot > 0 then WorldService.nest(slot) else nil
	if nest then
		nest:SetAttribute("OwnerUserId", player.UserId)
		nest:SetAttribute("OwnerName", player.DisplayName)
		nest:SetAttribute("Color", ownerColor(slot))
		local count = perchCountOf[player]
		if count ~= nil then
			WorldService.setPerchCount(slot, count)
			nest:SetAttribute("PerchCount", count)
		end
		local perchData = perchDataOf[player]
		if perchData ~= nil then
			nest:SetAttribute("PerchData", perchData)
		end
	end
	if not data then
		if nest then
			WorldService.setNestAppearance(slot, ownerColor(slot), nil)
		end
		return
	end
	local settings = if type(data.settings) == "table" then data.settings else {}
	player:SetAttribute("Zen", settings.zen == true)
	player:SetAttribute("VIP", PassEffects.vip(player))
	local supernovas = if type(data.supernovas) == "number" then data.supernovas else 0
	player:SetAttribute("Supernovas", supernovas)
	for _, info in KINDS do
		local id = effective(player, data, info)
		player:SetAttribute(info.attribute, id)
		if nest then
			nest:SetAttribute(info.attribute, id)
		end
	end
	if nest then
		nest:SetAttribute("Supernovas", supernovas)
		local theme = Cosmetics.Themes[effective(player, data, KINDS.themes)]
		local platform = if theme and theme.platform then theme.platform else ownerColor(slot)
		local arch = if theme and theme.platform then theme.arch else nil
		WorldService.setNestAppearance(slot, platform, arch)
	end
end

local function checkReady(player: Player)
	local slot = playerSlot[player] or 0
	if readyFired[player] or slot == 0 or player.Parent == nil or not DataService.get(player) then
		return
	end
	readyFired[player] = true
	Signals.PlayerReady:Fire(player, slot)
end

local function placeCharacter(player: Player, character: Model?)
	local slot = playerSlot[player] or 0
	if slot == 0 or character == nil or character.Parent == nil then
		return
	end
	local cf = WorldLayout.nestCFrame(slot) + Vector3.new(0, SPAWN_LIFT, 0)
	character:PivotTo(cf)
	local root = character:FindFirstChild("HumanoidRootPart")
	placed[player] = {
		character = character,
		pos = if root and root:IsA("BasePart") then root.Position else cf.Position,
		before = MoveCheck.lastValid(player),
	}
	Signals.ServerMoved:Fire(player)
end

-- Position de confiance du joueur : la dernière validée par MoveCheck (CongaService la fait avancer
-- à chaque tick), ou le placement serveur tant que MoveCheck n'a pas encore pris le relais ; nil
-- pendant une restriction (retour forcé récent) ou sans aucune référence.
local function trustedPosition(player: Player): Vector3?
	if MoveCheck.isRestricted(player, Clock.now()) then
		return nil
	end
	local valid = MoveCheck.lastValid(player)
	local mark = placed[player]
	if mark then
		if mark.character == player.Character and valid == mark.before then
			return mark.pos
		end
		placed[player] = nil -- MoveCheck a une référence plus récente (ou nouveau personnage)
	end
	return valid
end

-- Slot libre le plus proche d'un ami présent, sinon le plus petit libre ; 0 si tout est pris
local function chooseSlot(friendSlots: { number }): number
	local best, bestDistance = 0, math.huge
	for slot = 1, Zones.Nests.Count do
		if slotOwner[slot] == nil then
			if #friendSlots == 0 then
				return slot
			end
			local center = WorldLayout.nestCenter(slot)
			for _, friendSlot in friendSlots do
				local d = (WorldLayout.nestCenter(friendSlot) - center).Magnitude
				if d < bestDistance - 1e-6 then
					best, bestDistance = slot, d
				end
			end
		end
	end
	return best
end

-- Nids des amis présents. Chaque vérification (IsFriendsWith, appel web qui yield) part dans son
-- propre thread : les appels se font en parallèle et l'attente est bornée par
-- Settings.FriendLookupDeadline (une API d'amis lente ou en panne ne retarde jamais l'arrivée sur
-- son Nid). Une réponse tardive est quand même mise en cache, mais ignorée pour ce choix.
type FriendSlot = { slot: number, owner: Player }

local function lookupFriendSlots(player: Player): { FriendSlot }
	local found: { FriendSlot } = {}
	local pending = 0
	local closed = false
	for slot, owner in slotOwner do
		if owner ~= player then
			local known = cachedFriendship(player, owner)
			if known == true then
				table.insert(found, { slot = slot, owner = owner })
			elseif known == nil then
				pending += 1
				task.spawn(function()
					local friends = isFriend(player, owner)
					pending -= 1
					if friends and not closed then
						table.insert(found, { slot = slot, owner = owner })
					end
				end)
			end
		end
	end
	local elapsed = 0
	local deadline = NestService.Settings.FriendLookupDeadline
	while pending > 0 and elapsed < deadline and not gone[player] do
		elapsed += task.wait()
	end
	closed = true
	return found
end

local function assign(player: Player)
	if playerSlot[player] ~= nil or assigning[player] or gone[player] then
		return
	end
	assigning[player] = true
	-- amitiés d'abord (peut yield) : le choix du slot se fait ensuite d'un seul tenant
	local friends = lookupFriendSlots(player)
	assigning[player] = nil
	if gone[player] or player.Parent == nil or playerSlot[player] ~= nil then
		return
	end
	-- un ami parti (ou remplacé) pendant l'attente ne compte plus
	local present: { number } = {}
	for _, entry in friends do
		if slotOwner[entry.slot] == entry.owner then
			table.insert(present, entry.slot)
		end
	end
	table.sort(present)
	local slot = chooseSlot(present)
	playerSlot[player] = slot
	if slot == 0 then
		player:SetAttribute("Slot", 0)
		Notify.feedback(player, "feedback.noNest", {}, "info")
		return
	end
	slotOwner[slot] = player
	player.RespawnLocation = WorldService.spawnLocation(slot)
	applyIdentity(player)
	placeCharacter(player, player.Character)
	checkReady(player)
end

local function resetNest(slot: number)
	local nest = WorldService.nest(slot)
	nest:SetAttribute("OwnerUserId", 0)
	nest:SetAttribute("OwnerName", "")
	nest:SetAttribute("Color", Cosmetics.FreeNestColor)
	nest:SetAttribute("Supernovas", 0)
	nest:SetAttribute("PerchCount", 0)
	nest:SetAttribute("PerchData", "")
	nest:SetAttribute("Title", "")
	nest:SetAttribute("NestTheme", "default")
	nest:SetAttribute("LineStyle", "default")
	WorldService.setPerchCount(slot, 0)
	WorldService.setNestAppearance(slot, nil, nil)
end

local function onPlayerAdded(player: Player)
	if charConns[player] == nil then
		charConns[player] = player.CharacterAdded:Connect(function(character: Model)
			placeCharacter(player, character)
		end)
	end
	assign(player)
end

local function onPlayerRemoving(player: Player)
	gone[player] = true
	local slot = playerSlot[player] or 0
	if slot > 0 and slotOwner[slot] == player then
		slotOwner[slot] = nil
		resetNest(slot)
	end
	local conn = charConns[player]
	if conn then
		conn:Disconnect()
	end
	charConns[player] = nil
	playerSlot[player] = nil
	assigning[player] = nil
	friendCache[player] = nil
	zenChangedAt[player] = nil
	temporary[player] = nil
	perchCountOf[player] = nil
	perchDataOf[player] = nil
	readyFired[player] = nil
	placed[player] = nil
	lineLength[player] = nil
	for _, cache in friendCache do
		cache[player.UserId] = nil
	end
	-- un joueur resté sans Nid récupère celui qui vient de se libérer
	if slot > 0 then
		for _, other in Players:GetPlayers() do
			if other ~= player and playerSlot[other] == 0 then
				playerSlot[other] = nil
				task.spawn(assign, other)
				break
			end
		end
	end
end

local function onLoaded(player: Player)
	if player.Parent == nil then
		return
	end
	applyIdentity(player)
	checkReady(player)
end

-- ---------------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------------

local function onSetSetting(player: Player, key: unknown, value: unknown)
	if not RateLimit.allow(player, "SetSetting", 4, 1) then
		return
	end
	if not Validate.key(key, SettingsConfig, ID_MAX_LENGTH) then
		return
	end
	local name = key :: string
	local def = SettingsConfig[name]
	if def.kind == "boolean" then
		if type(value) ~= "boolean" then
			return
		end
	elseif def.kind == "string" then
		if not Validate.string(value, VALUE_MAX_LENGTH) then
			return
		end
		if def.values and not def.values[value :: string] then
			return
		end
	else
		return
	end
	NestService.applySetting(player, name, value)
end

local function onEquipCosmetic(player: Player, kind: unknown, id: unknown)
	if not RateLimit.allow(player, "EquipCosmetic", 2, 1) then
		return
	end
	if type(kind) ~= "string" or REMOTE_KINDS[kind] == nil then
		return
	end
	if type(id) ~= "string" or #id > ID_MAX_LENGTH then
		return
	end
	NestService.equip(player, kind, id)
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function NestService.Init() end

function NestService.Start()
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

	Signals.Supernova:Connect(function(player: Player)
		applyIdentity(player)
	end)
	MonetizationService.PassGranted:Connect(function(player: Player)
		-- VIP, thème « Or Royal », styles de pass : possession lue dynamiquement
		applyIdentity(player)
	end)
	-- longueur de la file (règle du Zen) ; le signal du départ arrive parfois après le nettoyage
	Signals.LineChanged:Connect(function(player: Player, n: number)
		if gone[player] or player.Parent == nil or type(n) ~= "number" or not (n > 0) then
			lineLength[player] = nil
			return
		end
		lineLength[player] = n
	end)

	Net.event("SetSetting").OnServerEvent:Connect(onSetSetting)
	Net.event("EquipCosmetic").OnServerEvent:Connect(onEquipCosmetic)
end

-- ---------------------------------------------------------------------------------------------
-- Nids
-- ---------------------------------------------------------------------------------------------

-- Slot 1-12 du joueur (0 si aucun Nid)
function NestService.slotOf(player: Player): number
	return playerSlot[player] or 0
end

function NestService.playerAt(slot: number): Player?
	return slotOwner[slot]
end

-- Le joueur est-il dans le port sûr de SON Nid ? Avec `pos` (position fournie par un service) :
-- ce point. Sans `pos` (remotes Supernova, Zen) : le personnage vivant ET sa position de confiance
-- (dernière validée par MoveCheck, ou placement serveur) y sont tous deux ; la position du client
-- seule ne suffit jamais (il la contrôle : téléportation au Nid le temps d'un remote).
function NestService.inOwnHarbor(player: Player, pos: Vector3?): boolean
	local slot = playerSlot[player] or 0
	if slot == 0 then
		return false
	end
	if pos ~= nil then
		return typeof(pos) == "Vector3" and WorldLayout.inOwnHarbor(slot, pos)
	end
	local character = player.Character
	if character == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	local trusted = trustedPosition(player)
	if trusted == nil or not WorldLayout.inOwnHarbor(slot, trusted) then
		return false
	end
	return WorldLayout.inOwnHarbor(slot, root.Position)
end

-- Amitié Roblox déjà vérifiée par une attribution de Nid : true / false, nil si inconnue (sans
-- yield ; CrewService peut la relire au lieu de refaire l'appel web)
function NestService.friendsCached(a: Player, b: Player): boolean?
	return cachedFriendship(a, b)
end

-- Ramène le personnage sur son Nid (PivotTo + Signals.ServerMoved)
function NestService.teleportHome(player: Player)
	placeCharacter(player, player.Character)
end

-- Perchés affichés (ordre des perchoirs) : liste de { code, stars } → "code.étoiles,…"
function NestService.setPerchDisplay(player: Player, entries: { { code: number, stars: number } })
	if type(entries) ~= "table" then
		return
	end
	local parts: { string } = {}
	for i, entry in ipairs(entries) do
		if i > Balance.Perches.Max then
			break
		end
		local code, stars = entry.code, entry.stars
		if Validate.integer(code, 0, 4095) and Validate.integer(stars, 1, 5) then
			table.insert(parts, string.format("%d.%d", code, stars))
		end
	end
	if gone[player] then
		return -- parti : Nid déjà libéré, rien à mémoriser
	end
	local text = table.concat(parts, ",")
	perchDataOf[player] = text
	local slot = playerSlot[player] or 0
	if slot > 0 then
		WorldService.nest(slot):SetAttribute("PerchData", text)
	end
end

-- Nombre de perchoirs construits (pièces) pour ce joueur
function NestService.setPerchCount(player: Player, count: number)
	if not Validate.finiteNumber(count) or gone[player] then
		return
	end
	local n = math.clamp(math.floor(count), 0, Balance.Perches.Max)
	perchCountOf[player] = n
	local slot = playerSlot[player] or 0
	if slot > 0 then
		WorldService.setPerchCount(slot, n)
		WorldService.nest(slot):SetAttribute("PerchCount", n)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------------------------------

function NestService.setting(player: Player, key: string): any
	if key == "privateNoSnip" then
		return privateNoSnip
	end
	local def = SettingsConfig[key]
	local data = DataService.get(player)
	local settings = if data and type(data.settings) == "table" then data.settings else nil
	if settings and settings[key] ~= nil then
		return settings[key]
	end
	return if def then def.default else nil
end

function NestService.isZen(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and type(data.settings) == "table" and data.settings.zen == true
end

-- Serveur privé dont le propriétaire a activé « Coupes désactivées »
function NestService.snipsDisabled(): boolean
	return privateNoSnip
end

-- Applique un réglage déjà validé en type (handler de SetSetting, exposé pour les tests).
-- (réussi, clé de Feedback du refus)
function NestService.applySetting(player: Player, key: string, value: any): (boolean, string?)
	local def = SettingsConfig[key]
	if def == nil then
		return false, nil
	end
	if def.ownerOnly then
		-- 0 hors serveur privé ; lecture protégée (propriété absente des environnements simulés)
		local readOk, ownerId = pcall(function(): any
			return (game :: any).PrivateServerOwnerId
		end)
		if not readOk or type(ownerId) ~= "number" or ownerId == 0 or ownerId ~= player.UserId then
			Notify.feedback(player, "feedback.ownerOnly", {}, "warning")
			return false, "feedback.ownerOnly"
		end
		if privateNoSnip ~= value then
			privateNoSnip = value == true
			Signals.SettingChanged:Fire(player, key, privateNoSnip)
		end
		return true, nil
	end
	local data = DataService.get(player)
	if not data or not def.saved then
		return false, nil
	end
	if type(data.settings) ~= "table" then
		data.settings = {}
	end
	if data.settings[key] == value then
		return true, nil
	end
	if def.harborOnly and not NestService.inOwnHarbor(player) then
		Notify.feedback(player, "feedback.notInHarbor", {}, "warning")
		return false, "feedback.notInHarbor"
	end
	if key == "zen" and value ~= true and (lineLength[player] or 0) > 0 then
		-- une file attrapée en Zen (sans risque de coupe) s'encaisse avec le plafond Zen (GDD §4.16 :
		-- « le plafond garde la poursuite plus rentable ») : on ne quitte pas le Zen à la porte
		Notify.feedback(player, "feedback.zenBankFirst", {}, "warning")
		return false, "feedback.zenBankFirst"
	end
	local now = Clock.now()
	if def.cooldown then
		local last = zenChangedAt[player]
		if last ~= nil and now - last < def.cooldown then
			Notify.feedback(
				player,
				"feedback.zenCooldown",
				{ seconds = math.ceil(def.cooldown - (now - last)) },
				"warning"
			)
			return false, "feedback.zenCooldown"
		end
		zenChangedAt[player] = now
	end
	data.settings[key] = value
	DataService.markDirty(player, "settings")
	if key == "zen" then
		player:SetAttribute("Zen", value == true)
		Notify.feedback(player, if value then "feedback.zenOn" else "feedback.zenOff", {}, "info")
		Analytics.event(player, "ZenToggled", if value then 1 else 0)
	end
	Signals.SettingChanged:Fire(player, key, value)
	return true, nil
end

-- ---------------------------------------------------------------------------------------------
-- Cosmétiques
-- ---------------------------------------------------------------------------------------------

-- kind : "styles" | "titles" | "themes" ; stocké dans profile.unlocks
function NestService.unlock(player: Player, kind: string, id: string)
	local info = kindInfo(kind)
	if not info or type(id) ~= "string" or info.defs[id] == nil then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	if type(data.unlocks) ~= "table" then
		data.unlocks = {}
	end
	local stored = data.unlocks[info.kind]
	if type(stored) ~= "table" then
		stored = {}
		data.unlocks[info.kind] = stored
	end
	if stored[id] then
		return
	end
	stored[id] = true
	DataService.markDirty(player, "unlocks")
	Notify.celebrate(player, "unlock", { kind = info.kind, id = id })
	applyIdentity(player)
end

-- Déblocage pour la session seulement (titre « Roi / Reine de la Conga »)
function NestService.grantTemporary(player: Player, kind: string, id: string)
	local info = kindInfo(kind)
	if not info or type(id) ~= "string" or info.defs[id] == nil or player.Parent == nil or gone[player] then
		return
	end
	local mine = temporary[player]
	if not mine then
		mine = {}
		temporary[player] = mine
	end
	local list = mine[info.kind]
	if not list then
		list = {}
		mine[info.kind] = list
	end
	if list[id] then
		return
	end
	list[id] = true
	Notify.celebrate(player, "unlock", { kind = info.kind, id = id, temporary = true })
	applyIdentity(player)
end

function NestService.hasUnlock(player: Player, kind: string, id: string): boolean
	local info = kindInfo(kind)
	if not info or type(id) ~= "string" then
		return false
	end
	local def = info.defs[id]
	if def == nil then
		return false
	end
	local source = def.source
	if source.kind == "free" then
		return true
	end
	local mine = temporary[player]
	if mine and mine[info.kind] and mine[info.kind][id] then
		return true
	end
	local data = DataService.get(player)
	if not data then
		return false
	end
	local unlocks = data.unlocks
	if
		type(unlocks) == "table"
		and type(unlocks[info.kind]) == "table"
		and unlocks[info.kind][id] == true
	then
		return true
	end
	if source.kind == "pass" then
		return source.pass ~= nil and MonetizationService.ownsPass(player, source.pass)
	elseif source.kind == "supernova" then
		return type(data.supernovas) == "number" and data.supernovas >= (source.supernovas or math.huge)
	elseif source.kind == "stat" then
		local stats = data.stats
		local value = if type(stats) == "table" and source.stat then stats[source.stat] else nil
		return type(value) == "number" and value >= (source.n or math.huge)
	elseif source.kind == "atlas" then
		return Collection.atlasCount(data.atlas) >= (source.entries or math.huge)
	end
	return false
end

-- Équipe un cosmétique (handler d'EquipCosmetic, exposé pour les tests) ; kind singulier ou
-- pluriel ; titre "" = aucun. (réussi, clé de Feedback du refus)
function NestService.equip(player: Player, kind: string, id: string): (boolean, string?)
	local info = kindInfo(kind)
	local data = DataService.get(player)
	if not info or not data or type(id) ~= "string" then
		return false, nil
	end
	if id == "" then
		if info.default ~= "" then
			return false, nil
		end
	elseif info.defs[id] == nil then
		return false, nil
	elseif not NestService.hasUnlock(player, info.kind, id) then
		Notify.feedback(player, "feedback.notOwned", {}, "warning")
		return false, "feedback.notOwned"
	end
	if type(data.cosmetics) ~= "table" then
		data.cosmetics = {}
	end
	if data.cosmetics[info.field] ~= id then
		data.cosmetics[info.field] = id
		DataService.markDirty(player, "cosmetics")
	end
	applyIdentity(player)
	Notify.feedback(player, "feedback.styleEquipped", {}, "success")
	return true, nil
end

-- Diagnostic (tests de fuite) : un état par joueur est-il encore gardé pour `player` ?
function NestService.debugTracked(player: Player): boolean
	if
		playerSlot[player] ~= nil
		or assigning[player] ~= nil
		or friendCache[player] ~= nil
		or zenChangedAt[player] ~= nil
		or temporary[player] ~= nil
		or perchCountOf[player] ~= nil
		or perchDataOf[player] ~= nil
		or readyFired[player] ~= nil
		or charConns[player] ~= nil
		or placed[player] ~= nil
		or lineLength[player] ~= nil
	then
		return true
	end
	for _, cache in friendCache do
		if cache[player.UserId] ~= nil then
			return true
		end
	end
	return false
end

return NestService
