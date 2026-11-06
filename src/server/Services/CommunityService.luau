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
-- v2.0 (lot A4, étape 5 ; décisions D17-D24 ; docs/04 §27.5, §27.7), profils v2 seulement, chaque
-- système derrière son interrupteur (tout coupé : réponses, données et envois de la v1.3) :
--   * possession : hasCosmetic garde les branches pass / product / weekly (classements) et lit le reste
--     par Logic/Owned (sources de la v1.3 inchangées ; Record R par Prestige.bestR) ; EquipCosmetic
--     accepte les habillages et cosmétiques v2.0, la palette du spectacle et les coussins
--     (cosmetics.palette / cosmetics.cushions, attributs Palette / Cushions, "" = ceux du ranch) ;
--     emote de la croix ← des v2.0 (SetSetting emoteLeft, possession par Owned).
--   * Déco perso [DecoPerso] : seul écrivain de decoPerso ; bits possédés revus depuis Owned à
--     l'arrivée, aux signaux qui changent une source (UpgradeBought, Stamped, Fed, Goutte de Lune,
--     compteurs à vie de QuestService) et toutes les 30 s (fanion des 5 min) ; objet gagné (1-16) →
--     Celebrate("unlock", { kind = "deco", id }) ; PlaceDeco (objet possédé, taille de l'emplacement,
--     jamais posé deux fois, 0 = retirer) ; attribut DecoPerso (12 numéros séparés par des virgules).
--   * cœurs [Hearts] : GiveHeart (présent, pas soi, pas bloqué, 1 par ranch et 20 par jour UTC) ;
--     Feedback hearts.given / hearts.received (privé) / hearts.limit ; aucun compteur public.
--   * halo [RanchSkins] : attribut HaloOn = settings.haloOn ; mode photo [PhotoMode] : état en mémoire
--     et analytique (PhotoMode), le personnage n'est jamais touché ; effacé au départ.
--   * attributs v2 (DecoPerso, HaloOn, Palette, Cushions) posés à l'arrivée et à chaque changement,
--     revus quand un interrupteur change en direct, absents sinon (RanchService les efface au départ).

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
local Bitset = require(Shared.Logic.Bitset)
local Owned = require(Shared.Logic.Owned)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local Analytics = require(Server.Util.Analytics)
local Guard = require(Server.Meta.Guard)
local PadRules = require(Server.Ranch.PadRules)
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
local ANALYTICS_EVERY = 300 -- s : PetSitPress et PhotoMode cumulés (une requête par 5 min au plus)
-- v2.0 (lot A4)
local V2_FLAGS_EVERY = 1 -- s : interrupteurs des attributs v2 relus (changement en direct)
local DECO_EVERY = 30 -- s : Déco perso revue (fanion offert à 5:00 de jeu, aucun signal)
local DECO_SLOTS = #Cosmetics.DecoSlots
local DECO_ITEMS = #Cosmetics.DecoPerso
-- interrupteurs des attributs v2 posés ici (ordre fixe : bit i − 1 du masque)
local ATTR_FLAGS = { "DecoPerso", "RanchSkins", "Workshop", "RecordR", "WeeklyTrack" }

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
-- v2.0 (lot A4)
local readyPlayers: { [Player]: boolean } = {} -- PlayerReady vu (Déco perso, attributs v2)
local attrsOn: { [Player]: { [string]: any } } = {} -- attributs v2 posés par ce service (valeurs)
local photo: { [Player]: boolean } = {} -- mode photo ouvert (mémoire seulement)
local photoEntries: { [Player]: { n: number, since: number } } = {} -- entrées en mode photo (analytique)
local flagsNow: Owned.Flags = {} -- interrupteurs lus par Owned (table réutilisée, aucune allocation)
local attrMaskSeen = 0
local v2FlagsAt = -math.huge
local decoAt = -math.huge

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
-- v2.0 (lot A4, D20) : sortes gardées dans le profil v2 seulement et montrées par un attribut du ranch
local V2_KINDS = { palette = "Palette", cushions = "Cushions" }
-- cosmétiques qu'on peut retirer (id "") : leur valeur par défaut est vide
local CLEARABLE = { trail = true, title = true, flag = true, palette = true, cushions = true }

-- Interrupteurs lus par Owned, recopiés à chaque usage dans une table gardée (aucune allocation)
local function currentFlags(): Owned.Flags
	return Owned.flags(Features.get, flagsNow)
end

local function v2Profile(data: { [string]: any }): boolean
	return PadRules.v2Profile(data)
end

-- Attribut DecoPerso : les 12 emplacements, numéro de l'objet (0 = vide), séparés par des virgules
local function decoString(data: { [string]: any }): string
	local deco = data.decoPerso
	local slots = if type(deco) == "table" and type(deco.slots) == "table" then deco.slots else nil
	local parts = table.create(DECO_SLOTS, "0")
	for i = 1, DECO_SLOTS do
		local item = if slots ~= nil then slots[i] else nil
		if finite(item) and item % 1 == 0 and item >= 1 and item <= DECO_ITEMS then
			parts[i] = tostring(item)
		end
	end
	return table.concat(parts, ",")
end

-- Attributs v2 de ce service voulus pour ce profil (profil v1 ou interrupteurs coupés : aucun)
local function wantedAttrs(data: { [string]: any }, flags: Owned.Flags): { [string]: any }
	local out: { [string]: any } = {}
	if not v2Profile(data) then
		return out
	end
	if flags.DecoPerso then
		out.DecoPerso = decoString(data)
	end
	if flags.RanchSkins then
		out.HaloOn = settingsOf(data).haloOn ~= false
	end
	local cosmetics = cosmeticsOf(data)
	if cosmetics ~= nil then
		for kind, name in V2_KINDS do
			local value = cosmetics[kind]
			if type(value) == "string" and Owned.kindOpen(kind, flags) then
				out[name] = value
			end
		end
	end
	return out
end

-- Pose les attributs v2 qui ont changé et efface ceux qui ne sont plus voulus (RanchService garde les
-- valeurs tant que le ranch n'est pas attribué)
local function refreshAttrs(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	local had = attrsOn[player]
	local want = wantedAttrs(data, currentFlags())
	if had == nil and next(want) == nil then
		return
	end
	local changed: { [string]: any } = {}
	local clear: { string } = {}
	for name, value in want do
		if had == nil or had[name] ~= value then
			changed[name] = value
		end
	end
	if had ~= nil then
		for name in had do
			if want[name] == nil then
				table.insert(clear, name)
			end
		end
	end
	if next(changed) ~= nil or #clear > 0 then
		Guard.try("community:attrs", RanchService.setV2Attributes, player, changed, clear)
	end
	attrsOn[player] = if next(want) ~= nil then want else nil
end

-- Déco perso [DecoPerso] (D19) : bits de decoPerso.owned revus depuis Owned (jamais retirés : une
-- source ne recule pas). Objet gagné (sources hors Atelier, 1-16) → carte « unlock », sauf `silent`
-- (premier chargement v2 d'un ancien joueur : objets déjà gagnés posés sans carte, comme le Carnet).
-- `prepared` : appelé avant l'instantané (rien à répliquer). Rend vrai si un bit a été posé.
local function syncDeco(player: Player, data: { [string]: any }, silent: boolean, prepared: boolean?): boolean
	if Features.get("DecoPerso") ~= true or not v2Profile(data) then
		return false
	end
	local deco = data.decoPerso
	if type(deco) ~= "table" or type(deco.owned) ~= "table" then
		return false
	end
	local flags = currentFlags()
	local gained: { number }? = nil
	for n = 1, DECO_ITEMS do
		if not Bitset.has(deco.owned, n) and Owned.deco(data, n, flags) then
			Bitset.set(deco.owned, n)
			local list = gained or {}
			gained = list
			table.insert(list, n)
		end
	end
	if gained == nil then
		return false
	end
	if prepared ~= true then
		DataService.markDirty(player, "decoPerso")
	end
	if not silent then
		for _, n in gained do
			local item = Cosmetics.DecoPerso[n]
			if item.source.kind ~= "atelier" then
				Notify.celebrate(player, "unlock", { kind = "deco", id = item.id })
			end
		end
	end
	return true
end

-- Déco perso revue pour un joueur prêt (signal d'une source, compteur à vie, tick des 30 s)
local function syncDecoOf(player: Player)
	if Features.get("DecoPerso") ~= true or not readyPlayers[player] then
		return
	end
	local data = profile(player)
	if data ~= nil then
		syncDeco(player, data, false)
	end
end

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
	elseif key == "haloOn" then
		refreshAttrs(player) -- attribut HaloOn [RanchSkins] (D24)
	end
	return true
end

local function onEquipCosmetic(player: Player, kind: string, id: string): boolean
	local data = profile(player)
	if data == nil or (PUBLIC_FIELD[kind] == nil and V2_KINDS[kind] == nil) then
		return false
	end
	-- palette et coussins (v2.0, D20) : profil v2 et au moins une de leurs sources ouverte, même pour
	-- les retirer (le jeu de base n'écrit jamais ces clés)
	if V2_KINDS[kind] ~= nil and (not v2Profile(data) or not Owned.kindOpen(kind, currentFlags())) then
		return false
	end
	if not (id == "" and CLEARABLE[kind]) and not CommunityService.hasCosmetic(player, kind, id) then
		return false
	end
	local cosmetics = cosmeticsOf(data)
	if cosmetics == nil or cosmetics[kind] == id then
		return false
	end
	if V2_KINDS[kind] ~= nil and type(cosmetics[kind]) ~= "string" then
		return false -- clé absente d'un profil abîmé : jamais créée ici (ProfileRepair la remet)
	end
	cosmetics[kind] = id
	DataService.markDirty(player, "cosmetics")
	if V2_KINDS[kind] ~= nil then
		refreshAttrs(player) -- attribut Palette ou Cushions
	else
		Guard.try("community:cosmetic", RanchService.setPublic, player, { [PUBLIC_FIELD[kind]] = id })
	end
	return true
end

-- =============================================================================================
-- v2.0 (lot A4) : Déco perso, cœurs, mode photo
-- =============================================================================================

-- PlaceDeco(item 0-64, slot 1-12) [DecoPerso] (D18, D19) : objet possédé (bit, ou source gagnée depuis
-- la dernière revue), de la taille de l'emplacement (Cosmetics.DecoSlots), jamais posé dans un autre
-- emplacement ; 0 vide l'emplacement. Accepté : bits revus (cartes), emplacement écrit, attribut DecoPerso
local function onPlaceDeco(player: Player, item: number, slot: number): boolean
	if Features.get("DecoPerso") ~= true then
		return false
	end
	local data = profile(player)
	if data == nil or not v2Profile(data) then
		return false
	end
	local deco = data.decoPerso
	if type(deco) ~= "table" or type(deco.slots) ~= "table" or type(deco.owned) ~= "table" then
		return false
	end
	local size = Cosmetics.DecoSlots[slot]
	if size == nil then
		return false
	end
	local slots = deco.slots
	local current = num(slots[slot], 0)
	if item == 0 then
		if current == 0 then
			return false -- déjà vide
		end
		slots[slot] = 0
	else
		local def = Cosmetics.DecoPerso[item]
		if def == nil or def.n ~= item or def.size ~= size or current == item then
			return false
		end
		if not Bitset.has(deco.owned, item) and not Owned.deco(data, item, currentFlags()) then
			return false
		end
		for i = 1, DECO_SLOTS do
			if i ~= slot and slots[i] == item then
				return false -- déjà posé ailleurs (contrat : jamais deux fois)
			end
		end
		-- accepté : possession revue (le bit de l'objet posé compris : ProfileRepair vide un emplacement
		-- dont le bit manque), puis l'emplacement
		syncDeco(player, data, false)
		if not Bitset.has(deco.owned, item) then
			return false -- garde : jamais un objet posé sans son bit
		end
		slots[slot] = item
	end
	DataService.markDirty(player, "decoPerso")
	refreshAttrs(player)
	return true
end

-- GiveHeart(ownerId) [Hearts] (D22) : propriétaire présent sur ce serveur, pas soi, pas bloqué (dans un
-- sens ou l'autre : refus muet), deux profils v2, 1 cœur par ranch et Balance.Hearts.PerDay par jour UTC
-- (hearts.limit au plafond) ; donneur : givenDay / givenTo, receveur : receivedTotal + 1 ; Feedback
-- privé aux deux, aucun compteur public
local function onGiveHeart(giver: Player, ownerId: number): boolean
	if Features.get("Hearts") ~= true then
		return false
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner == nil or owner == giver or not present(owner) or not present(giver) then
		return false
	end
	if CommunityService.isBlocked(giver, owner) then
		return false
	end
	local gData, oData = profile(giver), profile(owner)
	if gData == nil or oData == nil or not v2Profile(gData) or not v2Profile(oData) then
		return false
	end
	local given, received = gData.hearts, oData.hearts
	if type(given) ~= "table" or type(received) ~= "table" or type(given.givenTo) ~= "table" then
		return false
	end
	local today = Clock.day()
	local list: { number } = if given.givenDay == today then given.givenTo else {}
	if table.find(list, owner.UserId) ~= nil then
		return false -- déjà donné à ce ranch aujourd'hui
	end
	if #list >= Balance.Hearts.PerDay then
		Notify.feedback(giver, "hearts.limit", {}, "info")
		return false
	end
	if given.givenDay ~= today then
		given.givenDay = today
		given.givenTo = list
	end
	table.insert(list, owner.UserId)
	received.receivedTotal = math.min(1e12, math.max(0, math.floor(num(received.receivedTotal, 0))) + 1)
	DataService.markDirty(giver, "hearts")
	DataService.markDirty(owner, "hearts")
	Notify.feedback(giver, "hearts.given", {}, "reward")
	Notify.feedback(owner, "hearts.received", { name = CommunityService.displayName(giver) }, "reward")
	return true
end

local function flushPhoto(player: Player)
	local entry = photoEntries[player]
	if entry ~= nil and entry.n > 0 then
		Analytics.custom(player, "PhotoMode", entry.n)
		entry.n = 0
	end
end

-- SetPhotoMode(on) [PhotoMode] (D23, N22) : état en mémoire et analytique seulement ; le personnage
-- n'est jamais ancré, caché, déplacé dans l'arbre ni rendu transparent (toujours visible des autres :
-- le client fige ses propres commandes) ; aucun avantage
local function onSetPhotoMode(player: Player, on: boolean): boolean
	if Features.get("PhotoMode") ~= true or profile(player) == nil then
		return false
	end
	if (photo[player] == true) == on then
		return false
	end
	if on then
		photo[player] = true
		local entry = photoEntries[player]
		if entry == nil then
			entry = { n = 0, since = Clock.now() }
			photoEntries[player] = entry
		end
		entry.n += 1
	else
		photo[player] = nil
	end
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

-- v2.0 (lot A4) : Déco perso revue (cartes des objets gagnés depuis la dernière session) et attributs
-- v2 du ranch posés ; profil v1 : rien
local function onReadyV2(player: Player)
	readyPlayers[player] = true
	local data = profile(player)
	if data == nil or not v2Profile(data) then
		return
	end
	syncDeco(player, data, false)
	refreshAttrs(player)
end

-- Tick v2 (une fois par seconde) : un interrupteur des attributs v2 changé en direct → attributs revus
-- pour chaque joueur prêt (posés ou effacés) ; Déco perso revue toutes les 30 s (fanion offert à 5:00
-- de jeu, aucun signal). Tout coupé : 6 lectures d'interrupteur, rien d'autre
local function stepV2(now: number)
	local mask = 0
	for i, key in ATTR_FLAGS do
		if Features.get(key) == true then
			mask = bit32.bor(mask, bit32.lshift(1, i - 1))
		end
	end
	local flagsChanged = mask ~= attrMaskSeen
	attrMaskSeen = mask
	local decoDue = Features.get("DecoPerso") == true and now - decoAt >= DECO_EVERY
	if decoDue then
		decoAt = now
	end
	if not flagsChanged and not decoDue then
		return
	end
	for player in readyPlayers do
		if present(player) then
			Guard.try("community:decoTick", syncDecoOf, player)
			if flagsChanged then
				Guard.try("community:attrsTick", refreshAttrs, player)
			end
		end
	end
end

-- Avant l'instantané (DataService.onPrepare) : premier chargement v2 d'un ancien joueur (carte
-- « Bienvenue dans la v2 ! » en attente) → objets de Déco perso déjà gagnés posés sans carte
local function prepareV2(player: Player, data: { [string]: any })
	local onboarding = data.onboarding
	if type(onboarding) == "table" and onboarding.welcomeV2Pending == true then
		syncDeco(player, data, true, true)
	end
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
	-- v2.0 (lot A4) : mode photo effacé (analytique envoyée), attributs oubliés (RanchService les efface
	-- du ranch libéré)
	flushPhoto(player)
	photo[player] = nil
	photoEntries[player] = nil
	readyPlayers[player] = nil
	attrsOn[player] = nil
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
	-- v2.0 (lot A4, note INT-V2-INTENTS : intentions venues de Config/IntentsV2 avec leur handler)
	Guard.connect("PlaceDeco", onPlaceDeco)
	Guard.connect("GiveHeart", onGiveHeart)
	Guard.connect("SetPhotoMode", onSetPhotoMode)
	-- Déco perso : objectifs réclamés, pistes finies, niveaux achetés (compteurs à vie de QuestService)
	Guard.try("community:lifetimeHook", QuestService.onLifetime, function(player: Player)
		syncDecoOf(player)
	end)
	if type((DataService :: any).onPrepare) == "function" then
		DataService.onPrepare(function(player, data)
			Guard.try("community:prepare", prepareV2, player, data)
		end)
	end
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
		Guard.try("community:readyV2", onReadyV2, player)
	end)
	-- v2.0 (lot A4) : signaux qui changent une source de Déco perso (rien à faire interrupteur coupé :
	-- syncDecoOf lit DecoPerso d'abord) : ligne decoShop de l'Atelier et Carnet, tampons, jours de
	-- Plop, Goutte de Lune (moon.sessions compté juste avant par EventService)
	Signals.UpgradeBought:Connect(function(player: Player)
		Guard.try("community:decoUpgrade", syncDecoOf, player)
	end)
	Signals.Stamped:Connect(function(player: Player)
		Guard.try("community:decoStamp", syncDecoOf, player)
	end)
	Signals.Fed:Connect(function(player: Player)
		Guard.try("community:decoFed", syncDecoOf, player)
	end)
	Signals.SquishyObtained:Connect(function(player: Player, _uid: string, source: string)
		if source == "lunar" then
			Guard.try("community:decoMoon", syncDecoOf, player)
		end
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
	-- v2.0 (lot A4) : interrupteurs coupés, une comparaison par tick et 5 lectures par seconde
	if t - v2FlagsAt >= V2_FLAGS_EVERY then
		v2FlagsAt = t
		Guard.try("community:v2", stepV2, t)
	end
	for player, entry in photoEntries do
		if entry.n > 0 and t - entry.since >= ANALYTICS_EVERY then
			flushPhoto(player)
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

-- Cosmétique débloqué. Branches hors du profil gardées ici : pass « Pour toujours », produit Robux
-- (tenue achetée), titre du top 10 de la semaine (session) ; tout le reste (gratuit, jours de Plop,
-- Squishydex, Record R, sources de la v2.0 derrière leurs interrupteurs) : Logic/Owned (lot A4, D17)
function CommunityService.hasCosmetic(player: Player, kind: string, id: string): boolean
	if type(kind) ~= "string" or type(id) ~= "string" then
		return false
	end
	local def = Cosmetics.ByKindId[kind .. ":" .. id]
	if def ~= nil and def.source.kind == "free" then
		return true
	end
	local data = profile(player)
	if data == nil then
		return false
	end
	if def ~= nil then
		local source = def.source
		if source.kind == "pass" then
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
	end
	return Owned.cosmetic(data, kind, id, currentFlags())
end

-- Mode photo ouvert pour ce joueur [PhotoMode] (mémoire seulement, effacé au départ)
function CommunityService.inPhotoMode(player: Player): boolean
	return photo[player] == true and Features.get("PhotoMode") == true
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
