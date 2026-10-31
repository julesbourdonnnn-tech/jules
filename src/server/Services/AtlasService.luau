--!strict
-- AtlasService — paquet « economy » (docs/04-architecture.md §11.6).
-- Propriétaire de la collection : nebbies, nextUid, perchIncome, atlas, badges, atlasRewards.
-- Responsabilités :
--   * addNebbies : uids "u<n>", tri automatique des perchoirs (Economy/Collection.rank : revenu
--     passif décroissant, puis rareté, puis uid), réserve 300/600 ; débordement : libération auto
--     des non verrouillés les moins rentables (Commun → Rare seulement) contre Stardust + Feedback
--     récapitulatif, sinon libération des nouveaux arrivants excédentaires (leur Glow est payé)
--   * entrées d'Atlas (bit (s − 1) × 6 + f) et badges Golden/Huge/Starborn validés à l'encaissement ;
--     Celebrate "atlasNew" ; jalons (Config/Quests.Atlas) réclamés automatiquement (perchoirs, titre,
--     style, thème via NestService.unlock, Celebrate "atlasMilestone", bannière personnelle) ;
--     espèce complète : +100 Stardust, Celebrate "speciesComplete" ; Signals.AtlasEntry
--   * perchoirs : Formulas.perchCount(niveau, entrées, pass Extra Perches) ; recalcul sur
--     Signals.UpgradeBought (perches), PassGranted, jalons ; Signals.PerchesChanged ;
--     NestService.setPerchCount / setPerchDisplay ; RÈGLE : EconomyService.settle AVANT de changer
--     perchIncome, puis EconomyService.refreshRate
--   * remotes Fuse(uid) 6/s, FuseAll() 1/2 s, Release(uids) 2/s, SetLock(uid, locked) 6/s ;
--     Starforge déterministe : 3 identiques (s, f, v, st), les verrouillés jamais consommés (sauf le
--     choisi, qui reçoit l'étoile) ; « Tout fusionner » : la fusion qui augmente le plus le revenu
--     perché d'abord, tant que la Stardust suffit ; Signals.Fused ; Celebrate "starforge"
--   * libération (tout ou rien) : Stardust = Formulas.releaseDust ; jamais un Cosmique ni un verrouillé
--   * réplication de « nebbies » (DataService envoie la clé ENTIÈRE, 11-22 Ko avec 300-600 Nebbies) :
--     les changements du jeu (parade, débordement) partent tout de suite ; ceux demandés par
--     l'interface (verrou, fusion, libération, jusqu'à 6 / s) au plus une fois par
--     Settings.NebbiesPatchInterval (le premier tout de suite, les suivants regroupés en fin de
--     fenêtre). La sauvegarde écrit le profil entier : rien n'est différé pour elle.
-- GDD : §4.9, §4.13, §4.14, §5.4, §14.2 (Release_<rareté>, Starforge_<★>).
-- Dépendances : DataService, MonetizationService (via Economy/PassEffects), NestService,
-- EconomyService, Logic/Formulas, Config/{Nebbies,Quests,Balance}, Signals, Util/Notify,
-- Util/RateLimit, Economy/Collection (analytique Release_* et Starforge_* via EconomyService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Nebbies = require(Shared.Config.Nebbies)
local Quests = require(Shared.Config.Quests)
local Formulas = require(Shared.Logic.Formulas)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local RateLimit = require(Server.Util.RateLimit)
local Collection = require(Server.Economy.Collection)
local PassEffects = require(Server.Economy.PassEffects)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)
local EconomyService = require(script.Parent.EconomyService)

local AtlasService = {}

-- Réglages techniques (modifiables par les tests)
AtlasService.Settings = {
	-- intervalle minimal (s) entre deux envois de « nebbies » dus à l'interface (≈ 2 Hz)
	NebbiesPatchInterval = 0.5,
}

-- Longueur maximale d'un uid ("u" + 11 chiffres) et taille maximale d'une libération en lot
local UID_MAX_LENGTH = 12
local RELEASE_MAX = 50
-- Garde-fou de « Tout fusionner » (chaque fusion retire 2 Nebbies : jamais atteint en pratique)
local FUSE_ALL_MAX = 2000

-- État de session par joueur (vidé au départ)
local perchedCache: { [Player]: { string } } = {}
local atlasCache: { [Player]: number } = {}
local lastPerchCount: { [Player]: number } = {}
-- Réplication de « nebbies » limitée : fenêtre ouverte, changement en attente de fin de fenêtre
local patchHold: { [Player]: boolean } = {}
local patchPending: { [Player]: boolean } = {}
-- Joueurs partis (faible) : DataService garde le profil pendant la sauvegarde de départ, un appel
-- tardif ne doit pas recréer d'état par joueur (il ne serait plus jamais vidé)
local gone: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- Profils déjà réparés (faible, par table de profil) : la réparation a lieu au PREMIER accès, même si
-- un autre service (reçu, pass, remote) passe avant le handler Loaded d'AtlasService
local prepared: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

type Profile = { [string]: any }

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

-- Changement de la collection dû au jeu (parade, débordement) : répliqué tout de suite (le patch
-- part en fin d'image avec la table à jour, l'envoi en attente devient inutile)
local function collectionChanged(player: Player)
	patchPending[player] = nil
	DataService.markDirty(player, "nebbies")
end

-- Fin de fenêtre : envoie le changement en attente (et rouvre une fenêtre), sinon la ferme
local function releasePatchHold(player: Player)
	if gone[player] or player.Parent == nil then
		patchHold[player] = nil
		patchPending[player] = nil
		return
	end
	if patchPending[player] then
		patchPending[player] = nil
		DataService.markDirty(player, "nebbies")
		task.delay(AtlasService.Settings.NebbiesPatchInterval, releasePatchHold, player)
	else
		patchHold[player] = nil
	end
end

-- Changement demandé par l'interface (verrou, fusion, libération) : au plus un envoi par fenêtre
local function collectionChangedByRequest(player: Player)
	if gone[player] then
		return
	end
	if patchHold[player] then
		patchPending[player] = true
		return
	end
	patchHold[player] = true
	DataService.markDirty(player, "nebbies")
	task.delay(AtlasService.Settings.NebbiesPatchInterval, releasePatchHold, player)
end

local function rarityKey(rarity: number): string
	local def = Nebbies.Rarities[rarity]
	return if def then def.key else tostring(rarity)
end

-- Répare les clés de collection d'un profil (anciennes sauvegardes, valeurs inattendues)
local function sanitize(data: Profile)
	if type(data.nebbies) ~= "table" then
		data.nebbies = {}
	end
	for uid, rec in data.nebbies do
		if type(uid) ~= "string" or not Collection.isValidRecord(rec) then
			warn(`[AtlasService] enregistrement invalide ignoré : {tostring(uid)}`)
			data.nebbies[uid] = nil
		end
	end
	if type(data.nextUid) ~= "number" or data.nextUid ~= data.nextUid or data.nextUid < 1 then
		data.nextUid = 1
	end
	data.nextUid = math.floor(data.nextUid)
	-- jamais de collision d'uid, même avec une sauvegarde incohérente
	for uid in data.nebbies do
		local n = Collection.uidNumber(uid)
		if n ~= math.huge and n >= data.nextUid then
			data.nextUid = n + 1
		end
	end
	for _, key in { "atlas", "badges" } do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end
	local atlasWords = math.ceil(Nebbies.SPECIES_COUNT * Nebbies.FORM_COUNT / 32)
	for i = 1, atlasWords do
		if type(data.atlas[i]) ~= "number" then
			data.atlas[i] = 0
		end
	end
	for i = 1, math.ceil(3 * Nebbies.SPECIES_COUNT / 32) do
		if type(data.badges[i]) ~= "number" then
			data.badges[i] = 0
		end
	end
	if type(data.atlasRewards) ~= "number" or data.atlasRewards ~= data.atlasRewards then
		data.atlasRewards = 0
	end
	if type(data.perchIncome) ~= "number" or data.perchIncome ~= data.perchIncome then
		data.perchIncome = 0
	end
end

-- Profil chargé, réparé au premier accès ; nil si absent
local function profileOf(player: Player): Profile?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	if not prepared[data] then
		prepared[data] = true
		sanitize(data)
	end
	return data
end

local function atlasCountOf(player: Player, data: Profile): number
	local cached = atlasCache[player]
	if cached == nil then
		cached = Collection.atlasCount(data.atlas)
		if not gone[player] then
			atlasCache[player] = cached
		end
	end
	return cached
end

local function perchCountOf(player: Player, data: Profile): number
	local level = if type(data.upgrades) == "table" then data.upgrades.perches else 0
	return Formulas.perchCount(level, atlasCountOf(player, data), PassEffects.extraPerches(player))
end

local function stashCapOf(player: Player): number
	return Formulas.stashCap(PassEffects.stashPlus(player))
end

-- Tri, revenu perché, affichage du Nid, signal ; règle le Glow avant tout changement de taux.
-- Retourne les uids perchés (meilleur d'abord).
local function refresh(player: Player, data: Profile): { string }
	local count = perchCountOf(player, data)
	local ranked = Collection.rank(data.nebbies)
	local perched: { string } = {}
	local entries: { { code: number, stars: number } } = {}
	local income = 0
	for i = 1, math.min(count, #ranked.uids) do
		local uid = ranked.uids[i]
		local rec = data.nebbies[uid]
		perched[i] = uid
		income += ranked.income[uid]
		entries[i] = { code = Collection.codeOf(rec), stars = rec.st }
	end
	if not gone[player] then
		perchedCache[player] = perched
	end
	if income ~= data.perchIncome then
		EconomyService.settle(player)
		data.perchIncome = income
		DataService.markDirty(player, "perchIncome")
		EconomyService.refreshRate(player)
	end
	if gone[player] then
		return perched -- parti : le Nid est déjà libéré, aucun signal
	end
	NestService.setPerchCount(player, count)
	NestService.setPerchDisplay(player, entries)
	if lastPerchCount[player] ~= count then
		lastPerchCount[player] = count
		Signals.PerchesChanged:Fire(player, count)
	end
	return perched
end

-- Libère des uids (déjà validés) : Stardust par rareté, retourne (nombre, Stardust)
local function releaseUids(player: Player, data: Profile, uids: { string }): (number, number)
	local byRarity: { [number]: number } = {}
	local total, count = 0, 0
	for _, uid in uids do
		local rec = data.nebbies[uid]
		if rec then
			local rarity = Nebbies.rarityOf(rec.s)
			local dust = Formulas.releaseDust(rarity, rec.st)
			if dust ~= nil then
				data.nebbies[uid] = nil
				byRarity[rarity] = (byRarity[rarity] or 0) + dust
				total += dust
				count += 1
			end
		end
	end
	for rarity, dust in byRarity do
		EconomyService.addStardust(player, dust, `Release_{rarityKey(rarity)}`, "Gameplay")
	end
	return count, total
end

-- Débordement de la réserve (§4.9) : d'abord les C/U/R non verrouillés les moins rentables de la
-- réserve, puis les nouveaux arrivants excédentaires (jamais un Cosmique ni un verrouillé)
local function enforceStash(player: Player, data: Profile, arrivals: { string })
	local perches = perchCountOf(player, data)
	local total = 0
	for _ in data.nebbies do
		total += 1
	end
	if total - perches - stashCapOf(player) <= 0 then
		return -- cas courant : pas de tri inutile
	end
	local ranked = Collection.rank(data.nebbies)
	local excess = #ranked.uids - perches - stashCapOf(player)
	if excess <= 0 then
		return
	end
	local victims: { string } = {}
	-- la réserve = tout ce qui n'est pas perché ; ranked est trié du meilleur au moins bon
	for i = #ranked.uids, perches + 1, -1 do
		if #victims >= excess then
			break
		end
		local uid = ranked.uids[i]
		local rec = data.nebbies[uid]
		if not rec.lk and Nebbies.rarityOf(rec.s) <= Balance.Stash.AutoReleaseMaxRarity then
			table.insert(victims, uid)
		end
	end
	if #victims < excess then
		local chosen: { [string]: boolean } = {}
		for _, uid in victims do
			chosen[uid] = true
		end
		local isArrival: { [string]: boolean } = {}
		for _, uid in arrivals do
			isArrival[uid] = true
		end
		for i = #ranked.uids, perches + 1, -1 do
			if #victims >= excess then
				break
			end
			local uid = ranked.uids[i]
			local rec = data.nebbies[uid]
			if isArrival[uid] and not chosen[uid] and not rec.lk then
				if Formulas.releaseDust(Nebbies.rarityOf(rec.s), rec.st) ~= nil then
					table.insert(victims, uid)
				end
			end
		end
	end
	local count, dust = releaseUids(player, data, victims)
	if count > 0 then
		collectionChanged(player)
		Notify.feedback(player, "feedback.autoRelease", { count = count, dust = dust }, "info")
	end
end

-- Jalons d'Atlas atteints et pas encore réclamés (récompenses automatiques)
local function claimMilestones(player: Player, data: Profile)
	local total = atlasCountOf(player, data)
	for _, milestone in Quests.Atlas.Milestones do
		if milestone.entries > data.atlasRewards and milestone.entries <= total then
			data.atlasRewards = milestone.entries
			DataService.markDirty(player, "atlasRewards")
			if milestone.title then
				NestService.unlock(player, "titles", milestone.title)
			end
			if milestone.style then
				NestService.unlock(player, "styles", milestone.style)
			end
			if milestone.theme then
				NestService.unlock(player, "themes", milestone.theme)
			end
			Notify.celebrate(player, "atlasMilestone", {
				count = milestone.entries,
				perch = milestone.perch,
				title = milestone.title,
				style = milestone.style,
				theme = milestone.theme,
			})
			Notify.personalBanner(player, "atlasMilestone", { count = milestone.entries })
		end
	end
end

local function onLoaded(player: Player)
	if player.Parent == nil or gone[player] then
		return
	end
	local data = profileOf(player)
	if not data then
		return
	end
	atlasCache[player] = nil
	claimMilestones(player, data)
	refresh(player, data)
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function AtlasService.Init() end

function AtlasService.Start()
	DataService.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(function(player: Player)
		gone[player] = true
		perchedCache[player] = nil
		atlasCache[player] = nil
		lastPerchCount[player] = nil
		patchHold[player] = nil
		patchPending[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end

	Signals.UpgradeBought:Connect(function(player: Player, track: string)
		if track == "perches" then
			AtlasService.refreshPerches(player)
		end
	end)
	MonetizationService.PassGranted:Connect(function(player: Player, passKey: string)
		if PassEffects.passHas(passKey, "extraPerches") or PassEffects.passHas(passKey, "stashSize") then
			AtlasService.refreshPerches(player)
		end
	end)

	Net.event("Fuse").OnServerEvent:Connect(function(player: Player, uid: unknown)
		if not RateLimit.allow(player, "Fuse", 6, 1) then
			return
		end
		if not Validate.string(uid, UID_MAX_LENGTH) then
			return
		end
		local data = profileOf(player)
		if not data or data.nebbies[uid :: string] == nil then
			return
		end
		local ok, reason, vars = AtlasService.fuseDetailed(player, uid :: string)
		if not ok and reason then
			Notify.feedback(player, reason, vars, "warning")
		end
	end)

	Net.event("FuseAll").OnServerEvent:Connect(function(player: Player)
		if not RateLimit.allow(player, "FuseAll", 1, 2) then
			return
		end
		if not profileOf(player) then
			return
		end
		local count, reason, vars = AtlasService.fuseAllDetailed(player)
		if count == 0 and reason then
			Notify.feedback(player, reason, vars, "warning")
		end
	end)

	Net.event("Release").OnServerEvent:Connect(function(player: Player, uids: unknown)
		if not RateLimit.allow(player, "Release", 2, 1) then
			return
		end
		local list = Collection.validUidList(uids, RELEASE_MAX, UID_MAX_LENGTH)
		if not list or not profileOf(player) then
			return
		end
		local _, reason = AtlasService.releaseDetailed(player, list)
		if reason then
			Notify.feedback(player, reason, {}, "warning")
		end
	end)

	Net.event("SetLock").OnServerEvent:Connect(function(player: Player, uid: unknown, locked: unknown)
		if not RateLimit.allow(player, "SetLock", 6, 1) then
			return
		end
		if not Validate.string(uid, UID_MAX_LENGTH) or not Validate.boolean(locked) then
			return
		end
		AtlasService.setLock(player, uid :: string, locked :: boolean)
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Collection
-- ---------------------------------------------------------------------------------------------

-- Ajoute des Nebbies (★1 sauf `stars`) ; retourne les uids créés encore présents (vide si profil
-- absent ; un nouvel arrivant libéré par une réserve pleine n'y figure pas).
-- source : "parade" | "comet" | "quest" | "calendar" | "product" | "starfall" | "code"
function AtlasService.addNebbies(
	player: Player,
	codes: { Types.NebbyCode },
	source: string,
	stars: number?
): { Types.Uid }
	local data = profileOf(player)
	if not data or type(codes) ~= "table" then
		return {}
	end
	local st = 1
	if type(stars) == "number" and stars == stars then
		st = math.clamp(math.floor(stars), 1, Nebbies.MAX_STARS)
	end
	EconomyService.settle(player)

	local entriesBefore = atlasCountOf(player, data)
	local created: { string } = {}
	local newEntries: { { s: number, f: number } } = {}
	local touchedSpecies: { [number]: boolean } = {}
	local badgesChanged = false
	for _, code in ipairs(codes) do
		if Nebbies.isValidCode(code) then
			local s, f, v = Nebbies.unpack(code)
			local uid = "u" .. tostring(data.nextUid)
			data.nextUid += 1
			data.nebbies[uid] = { s = s, f = f, v = v, st = st }
			table.insert(created, uid)
			if Nebbies.setBit(data.atlas, Nebbies.atlasIndex(s, f)) then
				table.insert(newEntries, { s = s, f = f })
				touchedSpecies[s] = true
			end
			for _, key in Nebbies.VARIANT_ORDER do
				local variant = Nebbies.Variants[key]
				if variant and bit32.btest(v, variant.bit) then
					if Nebbies.setBit(data.badges, Nebbies.badgeIndex(key, s)) then
						badgesChanged = true
					end
				end
			end
		end
	end
	if #created == 0 then
		return {}
	end
	collectionChanged(player)
	DataService.markDirty(player, "nextUid")
	if badgesChanged then
		DataService.markDirty(player, "badges")
	end

	if #newEntries > 0 then
		DataService.markDirty(player, "atlas")
		if not gone[player] then
			atlasCache[player] = entriesBefore + #newEntries
		end
		Notify.celebrate(player, "atlasNew", { entries = newEntries, source = source })
		local running = entriesBefore
		for _, entry in newEntries do
			running += 1
			Signals.AtlasEntry:Fire(player, entry.s, entry.f, running)
		end
		for s in touchedSpecies do
			if Collection.isSpeciesComplete(data.atlas, s) then
				local dust = Quests.Atlas.SpeciesComplete.stardust or 0
				if dust > 0 then
					EconomyService.addStardust(player, dust, "AtlasSpecies", "Gameplay")
				end
				Notify.celebrate(player, "speciesComplete", { s = s, dust = dust })
			end
		end
		claimMilestones(player, data)
	end

	enforceStash(player, data, created)
	refresh(player, data)

	local kept: { string } = {}
	for _, uid in created do
		if data.nebbies[uid] ~= nil then
			table.insert(kept, uid)
		end
	end
	return kept
end

function AtlasService.record(player: Player, uid: Types.Uid): Types.NebbyRecord?
	local data = profileOf(player)
	if not data or type(uid) ~= "string" then
		return nil
	end
	local rec = data.nebbies[uid]
	if not rec then
		return nil
	end
	return { s = rec.s, f = rec.f, v = rec.v, st = rec.st, lk = rec.lk }
end

-- uids perchés, du plus rentable au moins rentable
function AtlasService.perched(player: Player): { Types.Uid }
	local cached = perchedCache[player]
	if cached == nil then
		local data = profileOf(player)
		if not data then
			return {}
		end
		cached = refresh(player, data)
	end
	return table.clone(cached)
end

function AtlasService.perchCount(player: Player): number
	local data = profileOf(player)
	if not data then
		return Formulas.perchCount(0, 0, false)
	end
	return perchCountOf(player, data)
end

function AtlasService.stashCap(player: Player): number
	return stashCapOf(player)
end

function AtlasService.atlasCount(player: Player): number
	local data = profileOf(player)
	return if data then atlasCountOf(player, data) else 0
end

function AtlasService.hasEntry(player: Player, s: number, f: number): boolean
	local data = profileOf(player)
	if
		not data
		or not Validate.integer(s, 1, Nebbies.SPECIES_COUNT)
		or not Validate.integer(f, 0, Nebbies.FORM_COUNT - 1)
	then
		return false
	end
	return Nebbies.testBit(data.atlas, Nebbies.atlasIndex(s, f))
end

-- Re-trie les perchoirs (après un changement du nombre de perchoirs ou de la collection)
function AtlasService.refreshPerches(player: Player)
	local data = profileOf(player)
	if not data then
		return
	end
	refresh(player, data)
end

-- ---------------------------------------------------------------------------------------------
-- Starforge
-- ---------------------------------------------------------------------------------------------

-- Deux copies consommables (identiques, non verrouillées, ≠ chosen), les plus récentes d'abord
local function findCopies(data: Profile, chosen: string, rec: Types.NebbyRecord): { string }
	local key = Collection.groupKey(rec)
	local copies: { string } = {}
	for uid, other in data.nebbies do
		if uid ~= chosen and not other.lk and Collection.groupKey(other) == key then
			table.insert(copies, uid)
		end
	end
	table.sort(copies, function(a: string, b: string): boolean
		return Collection.uidNumber(a) > Collection.uidNumber(b)
	end)
	return { copies[1], copies[2] }
end

-- Fusion déjà validée (copies trouvées, Stardust suffisante) : ne trie pas les perchoirs
local function doFuse(player: Player, data: Profile, uid: string, copies: { string }, cost: number): number
	local rec = data.nebbies[uid]
	local stars = rec.st + 1
	if not EconomyService.trySpendStardust(player, cost, `Starforge_{stars}`) then
		return 0
	end
	for _, copy in copies do
		data.nebbies[copy] = nil
	end
	rec.st = stars
	collectionChangedByRequest(player)
	Signals.Fused:Fire(player, stars)
	return stars
end

-- Fusion avec la raison détaillée du refus : (réussi, clé de Feedback, variables)
function AtlasService.fuseDetailed(player: Player, uid: Types.Uid): (boolean, string?, { [string]: any })
	local data = profileOf(player)
	if not data or type(uid) ~= "string" then
		return false, nil, {}
	end
	local rec = data.nebbies[uid]
	if not rec then
		return false, nil, {}
	end
	local cost = Formulas.fuseCost(rec.st)
	if cost == nil then
		return false, "feedback.fuseMaxStars", {}
	end
	local copies = findCopies(data, uid, rec)
	if #copies < Balance.Starforge.Copies - 1 then
		return false, "feedback.fuseNeedCopies", {}
	end
	if data.stardust < cost then
		return false, "feedback.notEnoughStardust", { missing = cost - data.stardust }
	end
	local stars = doFuse(player, data, uid, copies, cost)
	if stars == 0 then
		return false, nil, {}
	end
	Notify.celebrate(player, "starforge", { uid = uid, s = rec.s, f = rec.f, v = rec.v, stars = stars })
	refresh(player, data)
	return true, nil, {}
end

-- (ok, raison) — raison : clé "feedback.*"
function AtlasService.fuse(player: Player, uid: Types.Uid): (boolean, string?)
	local ok, reason = AtlasService.fuseDetailed(player, uid)
	return ok, reason
end

-- Groupe Starforge : Nebbies identiques (s, f, v, ★), du plus ancien au plus récent
type Group = { key: number, stars: number, unlocked: { string }, locked: { string } }

type Candidate = {
	group: Group,
	chosen: string,
	cost: number,
	before: number, -- revenu d'un exemplaire avant fusion
	after: number, -- revenu du résultat
	gain: number, -- hausse du revenu perché
	key: number,
}

-- Étape d'un plan de « Tout fusionner » (appliqué seulement une fois la Stardust payée)
type Step = { chosen: string, copies: { string }, stars: number, cost: number }

-- Ordre de « Tout fusionner » : hausse du revenu perché, puis gain propre de la fusion (résultat
-- contre les exemplaires consommés), puis coût le plus bas, puis clé (déterministe)
local function better(c: Candidate, pick: Candidate): boolean
	if c.gain ~= pick.gain then
		return c.gain > pick.gain
	end
	local copies = Balance.Starforge.Copies
	local own, other = c.after - copies * c.before, pick.after - copies * pick.before
	if own ~= other then
		return own > other
	end
	if c.cost ~= pick.cost then
		return c.cost < pick.cost
	end
	return c.key < pick.key
end

-- Groupes Starforge de la collection (★ < max), chaque Nebby examiné UNE fois
local function buildGroups(data: Profile): { [number]: Group }
	local groups: { [number]: Group } = {}
	for uid, rec in data.nebbies do
		if rec.st < Balance.Starforge.MaxStars then
			local key = Collection.groupKey(rec)
			local group = groups[key]
			if not group then
				group = { key = key, stars = rec.st, unlocked = {}, locked = {} }
				groups[key] = group
			end
			table.insert(if rec.lk then group.locked else group.unlocked, uid)
		end
	end
	for _, group in groups do
		table.sort(group.unlocked, Collection.olderFirst)
		table.sort(group.locked, Collection.olderFirst)
	end
	return groups
end

-- Planifie « Tout fusionner » sur des copies locales (aucune mutation du profil) :
-- (étapes, raison du refus si aucune, variables). Coût par fusion : O(perchoirs + groupes × log n),
-- la collection n'est jamais regroupée ni retriée entre deux fusions.
local function planFuseAll(player: Player, data: Profile): ({ Step }, string?, { [string]: any })
	local copiesNeeded = Balance.Starforge.Copies
	local need = copiesNeeded - 1
	local maxStars = Balance.Starforge.MaxStars
	local perches = perchCountOf(player, data)
	local ranked = Collection.rank(data.nebbies)
	local values: { number } = {}
	for i, uid in ranked.uids do
		values[i] = ranked.income[uid]
	end
	local groups = buildGroups(data)
	local budget = if type(data.stardust) == "number" then data.stardust else 0
	local plan: { Step } = {}
	for _ = 1, FUSE_ALL_MAX do
		local prefix = Collection.prefixSums(values, perches + copiesNeeded)
		local base = Collection.topSum(values, perches)
		local pick: Candidate? = nil
		local cheapest = math.huge
		for key, group in groups do
			local unlocked = group.unlocked
			if #unlocked >= need and #unlocked + #group.locked >= copiesNeeded then
				local cost = Formulas.fuseCost(group.stars)
				if cost ~= nil then
					cheapest = math.min(cheapest, cost)
					if cost <= budget then
						-- un verrouillé reçoit l'étoile (il n'est jamais consommé) ; sinon le plus ancien
						local chosen = group.locked[1] or unlocked[1]
						local rec = data.nebbies[chosen]
						local before =
							Formulas.passiveIncome({ s = rec.s, f = rec.f, v = rec.v, st = group.stars })
						local after =
							Formulas.passiveIncome({ s = rec.s, f = rec.f, v = rec.v, st = group.stars + 1 })
						local total =
							Collection.fusionTopSum(values, prefix, perches, before, copiesNeeded, after)
						local c: Candidate = {
							group = group,
							chosen = chosen,
							cost = cost,
							before = before,
							after = after,
							gain = total - base,
							key = key,
						}
						if pick == nil or better(c, pick) then
							pick = c
						end
					end
				end
			end
		end
		if pick == nil then
			if #plan == 0 then
				if cheapest == math.huge then
					return plan, "feedback.fuseNeedCopies", {}
				end
				return plan, "feedback.notEnoughStardust", { missing = cheapest - budget }
			end
			break
		end
		-- copies : les plus récents non verrouillés (≠ choisi), retirés du groupe
		local group = pick.group
		local copies: { string } = {}
		for i = #group.unlocked, 1, -1 do
			local uid = group.unlocked[i]
			if uid ~= pick.chosen then
				table.insert(copies, uid)
				table.remove(group.unlocked, i)
				if #copies == need then
					break
				end
			end
		end
		local list = if group.locked[1] == pick.chosen then group.locked else group.unlocked
		local at = table.find(list, pick.chosen)
		if at then
			table.remove(list, at)
		end
		local stars = group.stars + 1
		if stars < maxStars then
			-- le résultat rejoint le groupe de l'étoile suivante (clé = code × 8 + ★)
			local nextGroup = groups[group.key + 1]
			if not nextGroup then
				nextGroup = { key = group.key + 1, stars = stars, unlocked = {}, locked = {} }
				groups[group.key + 1] = nextGroup
			end
			local rec = data.nebbies[pick.chosen]
			Collection.insertByAge(if rec.lk then nextGroup.locked else nextGroup.unlocked, pick.chosen)
		end
		budget -= pick.cost
		table.insert(plan, { chosen = pick.chosen, copies = copies, stars = stars, cost = pick.cost })
		Collection.applyFusion(values, pick.before, copiesNeeded, pick.after)
	end
	return plan, nil, {}
end

-- « Tout fusionner » avec la raison du refus si rien n'a pu être fusionné :
-- (fusions, clé de Feedback, variables). Le plan est calculé d'abord, la Stardust payée en UNE
-- dépense par niveau d'étoiles (analytique Starforge_<★>), puis les fusions sont appliquées.
function AtlasService.fuseAllDetailed(player: Player): (number, string?, { [string]: any })
	local data = profileOf(player)
	if not data then
		return 0, nil, {}
	end
	local plan, reason, vars = planFuseAll(player, data)
	if #plan == 0 then
		return 0, reason, vars
	end
	local spend: { [number]: number } = {}
	local levels: { number } = {}
	for _, step in plan do
		if spend[step.stars] == nil then
			spend[step.stars] = 0
			table.insert(levels, step.stars)
		end
		spend[step.stars] += step.cost
	end
	table.sort(levels)
	-- une fusion ★k ne consomme que des résultats de niveaux inférieurs : si un niveau n'a pas pu
	-- être payé (impossible sans yield), seuls les niveaux inférieurs payés sont appliqués
	local paidBelow = math.huge
	for _, stars in levels do
		if not EconomyService.trySpendStardust(player, spend[stars], `Starforge_{stars}`) then
			warn(
				`[AtlasService] Tout fusionner : paiement des ★{stars} refusé, fusions suivantes annulées`
			)
			paidBelow = stars
			break
		end
	end
	local fused = 0
	local best: { uid: string, stars: number, s: number, f: number, v: number }? = nil
	for _, step in plan do
		if step.stars < paidBelow then
			for _, copy in step.copies do
				data.nebbies[copy] = nil
			end
			local rec = data.nebbies[step.chosen]
			rec.st = step.stars
			fused += 1
			Signals.Fused:Fire(player, step.stars)
			if best == nil or step.stars > best.stars then
				best = { uid = step.chosen, stars = step.stars, s = rec.s, f = rec.f, v = rec.v }
			end
		end
	end
	if fused > 0 and best then
		collectionChangedByRequest(player)
		Notify.celebrate(player, "starforge", {
			uid = best.uid,
			s = best.s,
			f = best.f,
			v = best.v,
			stars = best.stars,
			count = fused,
		})
		refresh(player, data)
	end
	return fused, nil, {}
end

-- Nombre de fusions effectuées
function AtlasService.fuseAll(player: Player): number
	local count = AtlasService.fuseAllDetailed(player)
	return count
end

-- ---------------------------------------------------------------------------------------------
-- Libération et verrous
-- ---------------------------------------------------------------------------------------------

-- Libération tout ou rien : (Stardust gagnée, clé de Feedback du refus)
function AtlasService.releaseDetailed(player: Player, uids: { Types.Uid }): (number, string?)
	local data = profileOf(player)
	if not data then
		return 0, nil
	end
	local list = Collection.validUidList(uids, RELEASE_MAX, UID_MAX_LENGTH)
	if not list then
		return 0, nil
	end
	for _, uid in list do
		local rec = data.nebbies[uid]
		if not rec then
			return 0, nil -- pas à lui : refus silencieux
		end
		if rec.lk then
			return 0, "feedback.nebbyLocked"
		end
		if Formulas.releaseDust(Nebbies.rarityOf(rec.s), rec.st) == nil then
			return 0, "feedback.cannotRelease"
		end
	end
	EconomyService.settle(player)
	local count, dust = releaseUids(player, data, list)
	if count > 0 then
		collectionChangedByRequest(player)
		Notify.feedback(player, "feedback.released", { count = count, dust = dust }, "reward")
		Notify.celebrate(player, "release", { count = count, dust = dust })
		refresh(player, data)
	end
	return dust, nil
end

-- Stardust gagnée (0 si rien de libérable)
function AtlasService.release(player: Player, uids: { Types.Uid }): number
	local dust = AtlasService.releaseDetailed(player, uids)
	return dust
end

function AtlasService.setLock(player: Player, uid: Types.Uid, locked: boolean): boolean
	local data = profileOf(player)
	if not data or type(uid) ~= "string" or type(locked) ~= "boolean" then
		return false
	end
	local rec = data.nebbies[uid]
	if not rec then
		return false
	end
	local value = if locked then true else nil
	if rec.lk ~= value then
		rec.lk = value
		collectionChangedByRequest(player)
	end
	return true
end

-- Diagnostic (tests de fuite) : un état par joueur est-il encore gardé pour `player` ?
function AtlasService.debugTracked(player: Player): boolean
	return perchedCache[player] ~= nil
		or atlasCache[player] ~= nil
		or lastPerchCount[player] ~= nil
		or patchHold[player] ~= nil
		or patchPending[player] ~= nil
end

return AtlasService
