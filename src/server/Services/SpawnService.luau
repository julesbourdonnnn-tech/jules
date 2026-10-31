--!strict
-- SpawnService — paquet « conga » (docs/04-architecture.md §11.7).
-- Propriétaire des Nebbies sauvages, libres et personnels (mémoire uniquement, rien de sauvegardé).
-- Responsabilités :
--   * apparitions par zone (Config/Zones) : à chaque intervalle (÷ SpawnModifiers.intervalDiv), si
--     la zone est sous son plafond effectif (Formulas.effectiveCap × capMult), rareté tirée selon les
--     probabilités, espèce uniforme parmi Nebbies.speciesOfRarity ; forme météo (formChance),
--     Golden 1 %, Huge 0,5 %, espèce vedette et Starborn pendant Starfall (SpawnModifiers) ; point
--     de la grille WorldLayout.spawnPoints à ≥ 6 studs de tout sauvage (10 essais, sinon on saute
--     ce tour) ; rattrapage borné après un pas en retard (jamais de rafale)
--   * flânerie SeededPath.wander(seed, now − t0) : position serveur = ancre + décalage (même calcul
--     côté client) ; un Nebby libre suit d'abord l'arc de dispersion (Snip.ScatterTime) de son
--     point de départ vers son ancre ; expiration à t0 + durée de vie
--   * grille spatiale de Balance.Tick.GridCell (16 studs), indexée par l'ancre, pour query()
--   * Nebbies libres (coupe, mort, départ, explosion de Comète) : étourdis Balance.Snip.Dizzy pour
--     tous sauf le slot prioritaire, durée Snip.LooseLifetime ; groupes plafonnés par joueur
--     (explosion : 1 Épique par joueur) ; « silent » = transmis par l'appelant (LineEvent clear,
--     SnipEvent), sinon envoyés par WildEvent en urgence
--   * apparitions personnelles (onlyFor) : Puffkins de bienvenue (3, à 12 studs devant la porte,
--     dans le port sûr), Rare garanti de Q4 (60-90 studs du centre, une fois par compte : décidé
--     par QuestService), apparitions dirigées de l'accueil (≥ 6 Communs à < 40 studs du Nid,
--     vérifiées une fois par seconde) ; hors plafonds ; envoyées au seul client concerné ;
--     nettoyées au départ du joueur
--   * WildEvent groupé à 4 Hz (flush) : spawns publics à tous, personnels au seul joueur ;
--     despawns "expired" / "cleared" (les capturés ne sont PAS listés : LineEvent "add" porte
--     l'id ; un sauvage capturé avant son premier envoi n'est jamais envoyé)
--   * ids 1-65535 attribués en tourniquet (un id n'est réutilisé qu'après un tour complet : le
--     client ignore 5 s une apparition tardive d'un id retiré)
-- GDD : §3 (Puffkins, Q4), §4.3, §4.4, §4.5 (étourdissement, priorité), §4.15.2 (explosion),
-- §4.15.5, §12.4 (WildEvent).
-- Dépendances : NestService (Nids), Logic/WorldLayout, Logic/SeededPath, Logic/Formulas,
-- Config/*, Shared/Util/Clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Nebbies = require(Shared.Config.Nebbies)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Logic.Formulas)
local SeededPath = require(Shared.Logic.SeededPath)
local WorldLayout = require(Shared.Logic.WorldLayout)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)

local NestService = require(script.Parent.NestService)

local SpawnService = {}

export type LooseOptions = {
	prioritySlot: number?, -- slot de la victime (0 s d'étourdissement pour elle)
	dizzy: number?, -- défaut Balance.Snip.Dizzy
	life: number?, -- défaut Balance.Snip.LooseLifetime
	group: string?, -- plafond par joueur (ex. "burst:<id>")
	groupCap: number?,
	silent: boolean?, -- true : pas d'envoi par WildEvent (l'appelant les envoie lui-même dans
	-- LineEvent "clear" ou SnipEvent, champ loose)
}

local Spawn = Balance.Spawn
local Snip = Balance.Snip

local MAX_ID = 65535
local SEED_MAX = 2147483646
local GRID = Balance.Tick.GridCell
local GRID_OFFSET = 4096 -- décalage des index de cellule (clé numérique positive)
local GRID_SPAN = 8192
-- Rattrapage borné : au plus N apparitions par zone et par pas (un serveur en retard ne crée pas
-- de rafale), le retard au-delà est abandonné
local MAX_SPAWNS_PER_STEP = 8
local MIN_INTERVAL_DIV = 0.05
-- Écart maximal entre la position d'un sauvage et son ancre : flânerie (2 × amplitude) et arc de
-- dispersion (jusqu'à 2 × ScatterMax en tenant compte du retour dans l'île)
local QUERY_MARGIN = Spawn.WanderAmplitude * 2 + Snip.ScatterMax * 2
local DIRECTED_CHECK_INTERVAL = 1 -- s entre deux vérifications de l'accueil dirigé

-- Raretés nommées (clés de Config/Nebbies, pas de nombres magiques)
local function rarityId(key: string): number
	for id, def in Nebbies.Rarities do
		if def.key == key then
			return id
		end
	end
	error(`[SpawnService] rareté inconnue : {key}`)
end
local COMMON = rarityId("common")
local RARE = rarityId("rare")

-- ---------------------------------------------------------------------------------------------
-- État
-- ---------------------------------------------------------------------------------------------

local rng = Random.new()
local wilds: { [number]: Types.WildNebby } = {}
local grid: { [number]: { [number]: boolean } } = {}
local zoneAlive: { [string]: number } = {}
local zoneNext: { [string]: number } = {}
local totalAlive = 0
local lastId = 0

local DEFAULT_MODS: Types.SpawnModifiers = {
	form = nil,
	formChance = 0,
	intervalDiv = 1,
	capMult = 1,
	featured = nil,
	featuredChance = 0,
	starbornChance = 0,
}
local mods: Types.SpawnModifiers = table.clone(DEFAULT_MODS)
local modsChanged = false
local activePlayers = 0

-- plafonds de groupe : [groupe][UserId] = captures ; oubliés avec le dernier Nebby vivant du
-- groupe (une explosion de Comète toutes les 10 min ne doit pas faire grossir la table sans fin)
local groupCounts: { [string]: { [number]: number } } = {}
local groupAlive: { [string]: number } = {}
-- accueil dirigé : joueur → prochaine vérification
local directed: { [Player]: number } = {}
local directedPoints: { [number]: { Vector3 } } = {}

-- envoi groupé
local pendingSpawns: { Types.WildSpawn } = {}
local pendingDespawns: { Types.WildDespawn } = {}
local personalSpawns: { [number]: { Types.WildSpawn } } = {} -- par UserId
local personalDespawns: { [number]: { Types.WildDespawn } } = {}
local unsent: { [number]: boolean } = {} -- ids créés mais pas encore envoyés
local urgentPending = false
local lastFlush = -math.huge
local wildRemote: RemoteEvent? = nil

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

local function finiteVector(v: any): boolean
	return typeof(v) == "Vector3" and isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

local function clamp01(x: any, default: number): number
	if type(x) ~= "number" or not isFinite(x) then
		return default
	end
	return math.clamp(x, 0, 1)
end

local function cellKey(ix: number, iz: number): number
	return (ix + GRID_OFFSET) * GRID_SPAN + (iz + GRID_OFFSET)
end

local function cellOf(x: number, z: number): (number, number)
	return math.floor(x / GRID), math.floor(z / GRID)
end

local function gridInsert(w: Types.WildNebby)
	local ix, iz = cellOf(w.anchor.X, w.anchor.Z)
	local key = cellKey(ix, iz)
	local cell = grid[key]
	if cell == nil then
		cell = {}
		grid[key] = cell
	end
	cell[w.id] = true
end

local function gridRemove(w: Types.WildNebby)
	local ix, iz = cellOf(w.anchor.X, w.anchor.Z)
	local key = cellKey(ix, iz)
	local cell = grid[key]
	if cell then
		cell[w.id] = nil
		if next(cell) == nil then
			grid[key] = nil
		end
	end
end

-- Parcourt les sauvages dont l'ancre est dans les cellules couvrant [x ± reach] × [z ± reach]
local function forEachNear(x: number, z: number, reach: number, fn: (Types.WildNebby) -> boolean?)
	local minX, minZ = cellOf(x - reach, z - reach)
	local maxX, maxZ = cellOf(x + reach, z + reach)
	for ix = minX, maxX do
		for iz = minZ, maxZ do
			local cell = grid[cellKey(ix, iz)]
			if cell then
				for id in cell do
					local w = wilds[id]
					if w and fn(w) then
						return
					end
				end
			end
		end
	end
end

local function allocId(): number?
	for _ = 1, MAX_ID do
		lastId = lastId % MAX_ID + 1
		if wilds[lastId] == nil and not unsent[lastId] then
			return lastId
		end
	end
	return nil
end

local function addWild(w: Types.WildNebby)
	wilds[w.id] = w
	gridInsert(w)
	totalAlive += 1
	local zone = w.zone
	if zone then
		zoneAlive[zone] = (zoneAlive[zone] or 0) + 1
	end
	local group = w.group
	if group then
		groupAlive[group] = (groupAlive[group] or 0) + 1
	end
end

local function removeWild(w: Types.WildNebby)
	if wilds[w.id] ~= w then
		return
	end
	wilds[w.id] = nil
	gridRemove(w)
	totalAlive -= 1
	local zone = w.zone
	if zone then
		zoneAlive[zone] = math.max(0, (zoneAlive[zone] or 0) - 1)
	end
	local group = w.group
	if group then
		local left = (groupAlive[group] or 1) - 1
		if left <= 0 then
			-- plus aucun Nebby du groupe : son plafond ne sert plus à rien
			groupAlive[group] = nil
			groupCounts[group] = nil
		else
			groupAlive[group] = left
		end
	end
end

local function removeFromList(list: { Types.WildSpawn }?, id: number)
	if list == nil then
		return
	end
	for i = #list, 1, -1 do
		if list[i].id == id then
			table.remove(list, i)
		end
	end
end

-- Retire une apparition pas encore envoyée (le client n'en saura jamais rien)
local function dropUnsent(w: Types.WildNebby): boolean
	if not unsent[w.id] then
		return false
	end
	unsent[w.id] = nil
	if w.onlyFor ~= 0 then
		removeFromList(personalSpawns[w.onlyFor], w.id)
	else
		removeFromList(pendingSpawns, w.id)
	end
	return true
end

local function queueSpawn(w: Types.WildNebby, urgent: boolean)
	local spawn = SpawnService.toSpawn(w)
	if w.onlyFor ~= 0 then
		local list = personalSpawns[w.onlyFor]
		if list == nil then
			list = {}
			personalSpawns[w.onlyFor] = list
		end
		table.insert(list, spawn)
	else
		table.insert(pendingSpawns, spawn)
	end
	unsent[w.id] = true
	if urgent then
		urgentPending = true
	end
end

local function queueDespawn(w: Types.WildNebby, reason: "expired" | "caught" | "cleared")
	if dropUnsent(w) then
		return -- jamais envoyé : rien à retirer chez les clients
	end
	local d: Types.WildDespawn = { id = w.id, reason = reason }
	if w.onlyFor ~= 0 then
		local list = personalDespawns[w.onlyFor]
		if list == nil then
			list = {}
			personalDespawns[w.onlyFor] = list
		end
		table.insert(list, d)
	else
		table.insert(pendingDespawns, d)
	end
end

-- Un autre sauvage a-t-il son ancre à moins de `minDist` (XZ) de `p` ?
local function crowded(p: Vector3, minDist: number): boolean
	local found = false
	local d2 = minDist * minDist
	forEachNear(p.X, p.Z, minDist, function(w)
		local dx, dz = w.anchor.X - p.X, w.anchor.Z - p.Z
		if dx * dx + dz * dz < d2 then
			found = true
			return true
		end
		return false
	end)
	return found
end

local function newWild(id: number, code: number, anchor: Vector3, now: number, life: number): Types.WildNebby
	return {
		id = id,
		code = code,
		zone = nil,
		anchor = Vector3.new(anchor.X, WorldLayout.groundY(anchor.X, anchor.Z), anchor.Z),
		seed = rng:NextInteger(0, SEED_MAX),
		t0 = now,
		expiresAt = now + life,
		dizzyUntil = 0,
		prioritySlot = 0,
		onlyFor = 0,
		group = nil,
		groupCap = nil,
		loose = false,
		from = nil,
	}
end

local function pickWeighted(odds: { Zones.Odds }): number?
	local total = 0
	for _, o in odds do
		total += math.max(0, o.weight)
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber() * total
	for _, o in odds do
		r -= math.max(0, o.weight)
		if r < 0 then
			return o.rarity
		end
	end
	return odds[#odds].rarity
end

local function uniformSpecies(rarity: number): number?
	local list = Nebbies.speciesOfRarity(rarity)
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Tire le code d'une apparition de zone (rareté, espèce, forme météo, variantes, vedette)
local function rollCode(def: Zones.ZoneDef): number?
	local s: number? = nil
	local starborn = false
	local featured = mods.featured
	if featured ~= nil and Nebbies.isSpeciesEnabled(featured) and rng:NextNumber() < mods.featuredChance then
		s = featured
		starborn = rng:NextNumber() < mods.starbornChance
	else
		local rarity = pickWeighted(def.odds)
		if rarity == nil then
			return nil
		end
		s = uniformSpecies(rarity)
	end
	if s == nil then
		return nil
	end
	local f = 0
	local form = mods.form
	if form ~= nil and Nebbies.isFormEnabled(form) and rng:NextNumber() < mods.formChance then
		f = form
	end
	local v = 0
	local variants = Nebbies.Variants
	if rng:NextNumber() < (variants.golden.chance or 0) then
		v = bit32.bor(v, variants.golden.bit)
	end
	if rng:NextNumber() < (variants.huge.chance or 0) then
		v = bit32.bor(v, variants.huge.bit)
	end
	if starborn then
		v = bit32.bor(v, variants.starborn.bit)
	end
	return Nebbies.pack(s, f, v)
end

local function spawnInZone(def: Zones.ZoneDef, now: number)
	local points = WorldLayout.spawnPoints(def.key)
	if #points == 0 then
		return
	end
	local anchor: Vector3? = nil
	for _ = 1, Spawn.PlaceAttempts do
		local p = points[rng:NextInteger(1, #points)]
		if not crowded(p, Spawn.MinSeparation) then
			anchor = p
			break
		end
	end
	if anchor == nil then
		return -- 10 essais sans place : on saute ce tour
	end
	local code = rollCode(def)
	local id = allocId()
	if code == nil or id == nil then
		return
	end
	local w = newWild(id, code, anchor, now, def.lifetime)
	w.zone = def.key
	addWild(w)
	queueSpawn(w, false)
end

local function playerSlot(player: Player): number
	local ok, slot = pcall(NestService.slotOf, player)
	if ok and type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= Zones.Nests.Count then
		return slot
	end
	return 0
end

-- Points de la zone du Nid à moins de DirectedRadius de son centre (mis en cache par slot)
local function directedCandidates(slot: number): { Vector3 }
	local cached = directedPoints[slot]
	if cached then
		return cached
	end
	local center = WorldLayout.nestCenter(slot)
	local zone = WorldLayout.zoneAt(center) or Zones.List[1].key
	local out = {}
	local r2 = Spawn.DirectedRadius * Spawn.DirectedRadius
	for _, p in WorldLayout.spawnPoints(zone) do
		local dx, dz = p.X - center.X, p.Z - center.Z
		if dx * dx + dz * dz < r2 then
			table.insert(out, p)
		end
	end
	directedPoints[slot] = out
	return out
end

-- Accueil : au moins DirectedCommons Communs visibles par le joueur près de son Nid
local function ensureDirected(player: Player, now: number)
	local slot = playerSlot(player)
	if slot == 0 then
		return
	end
	local center = WorldLayout.nestCenter(slot)
	local uid = player.UserId
	local radius = Spawn.DirectedRadius
	local count = 0
	forEachNear(center.X, center.Z, radius, function(w)
		if w.expiresAt > now and (w.onlyFor == 0 or w.onlyFor == uid) then
			local s = Nebbies.unpack(w.code)
			local dx, dz = w.anchor.X - center.X, w.anchor.Z - center.Z
			if Nebbies.rarityOf(s) == COMMON and dx * dx + dz * dz < radius * radius then
				count += 1
			end
		end
		return false
	end)
	local missing = Spawn.DirectedCommons - count
	if missing <= 0 then
		return
	end
	local candidates = directedCandidates(slot)
	if #candidates == 0 then
		return
	end
	local zoneDef = Zones.byKey[WorldLayout.zoneAt(center) or ""]
	local life = if zoneDef then zoneDef.lifetime else Spawn.PersonalLifetime
	for _ = 1, missing do
		local point: Vector3? = nil
		for _ = 1, Spawn.PlaceAttempts do
			local p = candidates[rng:NextInteger(1, #candidates)]
			if not crowded(p, Spawn.MinSeparation) then
				point = p
				break
			end
		end
		local s = uniformSpecies(COMMON)
		if point == nil or s == nil then
			return
		end
		SpawnService.spawnPersonal(player, Nebbies.pack(s, 0, 0), point, life)
	end
end

local function remote(): RemoteEvent
	local r = wildRemote
	if r == nil then
		r = Net.event("WildEvent")
		wildRemote = r
	end
	return r
end

-- ---------------------------------------------------------------------------------------------
-- Cycle de vie
-- ---------------------------------------------------------------------------------------------

function SpawnService.Init()
	wildRemote = Net.event("WildEvent")
end

function SpawnService.Start()
	Players.PlayerRemoving:Connect(SpawnService.clearPlayer)
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Apparitions dues et expirations (tick de CongaService, étape 4)
function SpawnService.step(now: number)
	if not isFinite(now) then
		return
	end
	-- expirations
	for _, w in wilds do
		if w.expiresAt <= now then
			removeWild(w)
			queueDespawn(w, "expired")
		end
	end
	-- apparitions par zone
	local div = math.max(mods.intervalDiv, MIN_INTERVAL_DIV)
	for _, def in Zones.List do
		local interval = def.interval / div
		local nextAt = zoneNext[def.key] or now
		if modsChanged then
			nextAt = math.min(nextAt, now + interval)
		end
		local cap = Formulas.effectiveCap(def.cap, activePlayers, mods.capMult)
		local count = 0
		while now >= nextAt and count < MAX_SPAWNS_PER_STEP do
			if (zoneAlive[def.key] or 0) < cap then
				spawnInZone(def, now)
			end
			nextAt += interval
			count += 1
		end
		if now >= nextAt then
			nextAt = now + interval -- retard abandonné
		end
		zoneNext[def.key] = nextAt
	end
	modsChanged = false
	-- accueil dirigé
	for player, checkAt in directed do
		if player.Parent == nil then
			directed[player] = nil
		elseif now >= checkAt then
			directed[player] = now + DIRECTED_CHECK_INTERVAL
			ensureDirected(player, now)
		end
	end
end

-- Poussé par EventService à chaque changement de phase (météo, Frenzy, Starfall)
function SpawnService.setModifiers(newMods: Types.SpawnModifiers)
	if type(newMods) ~= "table" then
		return
	end
	local m: Types.SpawnModifiers = table.clone(DEFAULT_MODS)
	local form = newMods.form
	if type(form) == "number" and form % 1 == 0 and form >= 1 and Nebbies.isFormEnabled(form) then
		m.form = form
	end
	m.formChance = clamp01(newMods.formChance, 0)
	local div = newMods.intervalDiv
	if type(div) == "number" and isFinite(div) and div > 0 then
		m.intervalDiv = math.max(div, MIN_INTERVAL_DIV)
	end
	local capMult = newMods.capMult
	if type(capMult) == "number" and isFinite(capMult) and capMult >= 0 then
		m.capMult = capMult
	end
	local featured = newMods.featured
	if type(featured) == "number" and featured % 1 == 0 and Nebbies.isSpeciesEnabled(featured) then
		m.featured = featured
	end
	m.featuredChance = clamp01(newMods.featuredChance, 0)
	m.starbornChance = clamp01(newMods.starbornChance, 0)
	mods = m
	modsChanged = true
end

-- Poussé par CongaService (joueurs actifs, §4.3) au plus une fois par seconde
function SpawnService.setActivePlayers(n: number)
	if type(n) == "number" and isFinite(n) then
		activePlayers = math.max(0, math.floor(n))
	end
end

-- Position serveur d'un sauvage à `now` (ancre + flânerie ; arc de dispersion terminé)
function SpawnService.positionOf(wild: Types.WildNebby, now: number): Vector3
	local anchor = wild.anchor
	local from = wild.from
	if wild.loose and from ~= nil and now < wild.t0 + Snip.ScatterTime then
		local a = math.clamp((now - wild.t0) / Snip.ScatterTime, 0, 1)
		return from + (anchor - from) * a
	end
	return anchor + SeededPath.wander(wild.seed, now - wild.t0)
end

-- Sauvages dont la position à `now` est à ≤ radius (XZ) de pos et visibles pour `player`
function SpawnService.query(pos: Vector3, radius: number, now: number, player: Player?): { Types.WildNebby }
	local out: { Types.WildNebby } = {}
	if not finiteVector(pos) or type(radius) ~= "number" or not isFinite(radius) or radius < 0 then
		return out
	end
	local uid = if player then player.UserId else 0
	local r2 = radius * radius
	forEachNear(pos.X, pos.Z, radius + QUERY_MARGIN, function(w)
		if w.expiresAt > now and (w.onlyFor == 0 or w.onlyFor == uid) then
			local p = SpawnService.positionOf(w, now)
			local dx, dz = p.X - pos.X, p.Z - pos.Z
			if dx * dx + dz * dz <= r2 then
				table.insert(out, w)
			end
		end
		return false
	end)
	return out
end

-- Le joueur peut-il l'attraper maintenant ? (étourdi, priorité, onlyFor, plafond de groupe)
function SpawnService.canCatch(player: Player, slot: number, wild: Types.WildNebby, now: number): boolean
	if wilds[wild.id] ~= wild or wild.expiresAt <= now then
		return false
	end
	if wild.onlyFor ~= 0 and wild.onlyFor ~= player.UserId then
		return false
	end
	if now < wild.dizzyUntil and not (wild.prioritySlot ~= 0 and wild.prioritySlot == slot) then
		return false
	end
	local group, cap = wild.group, wild.groupCap
	if group ~= nil and cap ~= nil then
		local counts = groupCounts[group]
		if counts and (counts[player.UserId] or 0) >= cap then
			return false
		end
	end
	return true
end

-- Retire le sauvage (capturé) ; retourne son enregistrement, nil s'il n'existe plus
function SpawnService.consume(id: number, player: Player): Types.WildNebby?
	local w = wilds[id]
	if w == nil then
		return nil
	end
	-- compté AVANT le retrait : retirer le dernier Nebby du groupe oublie son plafond
	local group, cap = w.group, w.groupCap
	if group ~= nil and cap ~= nil then
		local counts = groupCounts[group]
		if counts == nil then
			counts = {}
			groupCounts[group] = counts
		end
		counts[player.UserId] = (counts[player.UserId] or 0) + 1
	end
	removeWild(w)
	dropUnsent(w)
	return w
end

-- Crée des Nebbies libres (un par code, départ `from[i]`, atterrissage dispersé et borné à l'île) ;
-- retourne les apparitions (ids dans l'ordre)
function SpawnService.spawnLoose(
	codes: { Types.NebbyCode },
	from: { Vector3 },
	now: number,
	opts: LooseOptions?
): { Types.WildSpawn }
	local out: { Types.WildSpawn } = {}
	if type(codes) ~= "table" or type(from) ~= "table" or not isFinite(now) then
		return out
	end
	local o: LooseOptions = opts or {}
	local dizzy = if type(o.dizzy) == "number" and isFinite(o.dizzy) then math.max(0, o.dizzy) else Snip.Dizzy
	local life = if type(o.life) == "number"
			and isFinite(o.life)
			and o.life > 0
		then o.life
		else Snip.LooseLifetime
	local prioritySlot = if type(o.prioritySlot) == "number" then o.prioritySlot else 0
	local scatterSeed = rng:NextInteger(0, SEED_MAX)
	local fallback = from[#from]
	for i, code in codes do
		if Nebbies.isValidCode(code) then
			local origin = from[i] or fallback
			if not finiteVector(origin) then
				origin = Vector3.new(0, 0, 0)
			end
			local id = allocId()
			if id == nil then
				break
			end
			local landing = WorldLayout.clampToIsland(SeededPath.scatterPoint(scatterSeed, i, origin))
			local w = newWild(id, code, landing, now, life)
			w.loose = true
			w.from = origin
			w.dizzyUntil = now + dizzy
			w.prioritySlot = prioritySlot
			w.group = o.group
			w.groupCap = o.groupCap
			addWild(w)
			table.insert(out, SpawnService.toSpawn(w))
			if not o.silent then
				queueSpawn(w, true)
			end
		end
	end
	return out
end

-- Apparition personnelle (onlyFor = player) ; retourne l'id (0 si impossible)
function SpawnService.spawnPersonal(
	player: Player,
	code: Types.NebbyCode,
	pos: Vector3,
	life: number?
): number
	if not Nebbies.isValidCode(code) or not finiteVector(pos) then
		return 0
	end
	local id = allocId()
	if id == nil then
		return 0
	end
	local duration = if type(life) == "number"
			and isFinite(life)
			and life > 0
		then life
		else Spawn.PersonalLifetime
	local w = newWild(id, code, pos, Clock.now(), duration)
	w.onlyFor = player.UserId
	addWild(w)
	queueSpawn(w, false)
	return id
end

-- 3 Puffkins de bienvenue devant la porte du Nid (accueil, §3)
function SpawnService.spawnWelcome(player: Player): { number }
	local ids: { number } = {}
	local slot = playerSlot(player)
	if slot == 0 then
		return ids
	end
	local code = Nebbies.pack(Nebbies.Named.Welcome, 0, 0)
	for _, p in WorldLayout.welcomePoints(slot, Spawn.WelcomeCount) do
		local id = SpawnService.spawnPersonal(player, code, p, Spawn.PersonalLifetime)
		if id ~= 0 then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Rare personnel de Q4 (60-90 studs du centre) ; nil s'il existe déjà un Rare public dans la Clairière
function SpawnService.spawnGuaranteedRare(player: Player): number?
	local now = Clock.now()
	local zone =
		WorldLayout.zoneAt(Vector3.new((Spawn.GuaranteedRareMin + Spawn.GuaranteedRareMax) / 2, 0, 0))
	for _, w in wilds do
		if w.zone ~= nil and w.zone == zone and w.onlyFor == 0 and w.expiresAt > now then
			local s = Nebbies.unpack(w.code)
			if Nebbies.rarityOf(s) == RARE then
				return nil -- le pilier bleu montrera ce Rare public
			end
		end
	end
	-- point de la grille dans l'anneau 60-90, le plus proche du joueur (ou de son Nid)
	local ref: Vector3 = Vector3.new(0, 0, 0)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local slot = playerSlot(player)
	if root and root:IsA("BasePart") then
		ref = root.Position
	elseif slot ~= 0 then
		ref = WorldLayout.nestCenter(slot)
	end
	local best: Vector3? = nil
	local bestFree = false
	local bestD = math.huge
	for _, p in WorldLayout.spawnPoints(zone or "") do
		local r = WorldLayout.radiusXZ(p)
		if r >= Spawn.GuaranteedRareMin and r <= Spawn.GuaranteedRareMax then
			local free = not crowded(p, Spawn.MinSeparation)
			local d = (p - ref).Magnitude
			if (free and not bestFree) or (free == bestFree and d < bestD) then
				best, bestFree, bestD = p, free, d
			end
		end
	end
	local s = uniformSpecies(RARE)
	if best == nil or s == nil then
		return nil
	end
	local id = SpawnService.spawnPersonal(player, Nebbies.pack(s, 0, 0), best, Spawn.PersonalLifetime)
	return if id ~= 0 then id else nil
end

-- Accueil : garantir ≥ 6 Communs à < 40 studs du Nid du joueur (true = actif)
function SpawnService.setDirected(player: Player, enabled: boolean)
	if enabled == true then
		if directed[player] == nil and player.Parent ~= nil then
			directed[player] = -math.huge -- vérification au prochain pas
		end
	else
		directed[player] = nil
	end
end

-- Envoie le WildEvent groupé si ≥ 0,25 s depuis le dernier (ou `urgent`)
function SpawnService.flush(now: number, urgent: boolean?)
	if not (urgent or urgentPending) and now - lastFlush < Spawn.WildEventInterval then
		return
	end
	lastFlush = now
	urgentPending = false
	local r = remote()
	if #pendingSpawns > 0 or #pendingDespawns > 0 then
		local payload: Types.WildEventPayload = { spawns = pendingSpawns, despawns = pendingDespawns }
		pendingSpawns = {}
		pendingDespawns = {}
		r:FireAllClients(payload)
	end
	local users: { [number]: boolean } = {}
	for uid in personalSpawns do
		users[uid] = true
	end
	for uid in personalDespawns do
		users[uid] = true
	end
	for uid in users do
		local spawns = personalSpawns[uid] or {}
		local despawns = personalDespawns[uid] or {}
		personalSpawns[uid] = nil
		personalDespawns[uid] = nil
		local player = Players:GetPlayerByUserId(uid)
		if player and (#spawns > 0 or #despawns > 0) then
			local payload: Types.WildEventPayload = { spawns = spawns, despawns = despawns }
			r:FireClient(player, payload)
		end
	end
	table.clear(unsent)
end

-- Apparitions visibles par ce joueur (WorldSnapshot)
function SpawnService.snapshotFor(player: Player): { Types.WildSpawn }
	local out: { Types.WildSpawn } = {}
	local uid = player.UserId
	local now = Clock.now()
	for _, w in wilds do
		if w.expiresAt > now and (w.onlyFor == 0 or w.onlyFor == uid) then
			table.insert(out, SpawnService.toSpawn(w))
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Retire les apparitions personnelles et les plafonds de groupe du joueur (départ)
function SpawnService.clearPlayer(player: Player)
	local uid = player.UserId
	for _, w in wilds do
		if w.onlyFor == uid then
			removeWild(w)
			unsent[w.id] = nil
		end
	end
	personalSpawns[uid] = nil
	personalDespawns[uid] = nil
	directed[player] = nil
	for _, counts in groupCounts do
		counts[uid] = nil
	end
end

-- Groupes de plafond encore suivis (diagnostic : un groupe disparaît avec son dernier Nebby)
function SpawnService.groupCount(): number
	local n = 0
	for _ in groupCounts do
		n += 1
	end
	return n
end

function SpawnService.aliveCount(zoneKey: string?): number
	if zoneKey == nil then
		return totalAlive
	end
	return zoneAlive[zoneKey] or 0
end

-- Convertit un enregistrement serveur en charge utile réseau
function SpawnService.toSpawn(wild: Types.WildNebby): Types.WildSpawn
	local spawn: Types.WildSpawn = {
		id = wild.id,
		code = wild.code,
		x = wild.anchor.X,
		z = wild.anchor.Z,
		seed = wild.seed,
		t0 = wild.t0,
		life = wild.expiresAt - wild.t0,
	}
	if wild.dizzyUntil > wild.t0 then
		spawn.dizzyUntil = wild.dizzyUntil
	end
	if wild.prioritySlot ~= 0 then
		spawn.prioritySlot = wild.prioritySlot
	end
	local from = wild.from
	if from ~= nil then
		spawn.fromX = from.X
		spawn.fromZ = from.Z
	end
	if wild.onlyFor ~= 0 then
		spawn.personal = true
	end
	return spawn
end

return SpawnService
