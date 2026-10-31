--!strict
-- Panels/Model — paquet « client-panels » : calculs PURS des panneaux, côté client.
-- Aucune Instance, aucune lecture d'horloge (le temps `now` est un paramètre), aucun remote :
-- le profil répliqué (StateController) entre, des valeurs d'affichage sortent. Le serveur reste
-- seul juge ; ces calculs reproduisent ses règles pour afficher juste et éviter les envois inutiles.
--   * Glow prédit (glow + idleRate × (now − lastSettle) + glowCarry, jamais sous la valeur serveur)
--   * améliorations (coût, plafond, effet actuel → suivant), aperçu de Supernova (mêmes règles que
--     EconomyService.supernovaPreview)
--   * collection : tri des perchoirs identique à Server/Economy/Collection.rank, groupes Starforge,
--     Atlas (bits), réserve
--   * objectifs : calendrier, quêtes du jour, Grand Défilé, chaîne d'accueil
--   * boutique : montants « ≈ » des produits Glow, visibilité (id 0, Starter Kit, Glow Party)
--   * cosmétiques possédés (miroir de NestService.hasUnlock, hors déblocages temporaires)
-- GDD : §4.9-§4.14, §7.3-§7.5, §8, §5.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Monetization = require(Shared.Config.Monetization)
local Nebbies = require(Shared.Config.Nebbies)
local Quests = require(Shared.Config.Quests)
local SettingsConfig = require(Shared.Config.Settings)
local EventClock = require(Shared.Logic.EventClock)
local Formulas = require(Shared.Logic.Formulas)
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)

local Model = {}

export type Profile = { [string]: any }

-- Prédiction bornée : au-delà, le serveur aurait déjà réglé (toutes les 30 s) et répliqué
local MAX_PREDICT_SECONDS = Balance.Idle.SettleInterval * 2 + 5
local ATLAS_BITS = Nebbies.SPECIES_COUNT * Nebbies.FORM_COUNT
local CODE_MAX_LENGTH = 20

-- ---------------------------------------------------------------------------------------------
-- Nombres sûrs
-- ---------------------------------------------------------------------------------------------

-- Nombre fini, sinon `default`
function Model.num(x: any, default: number): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return default
	end
	return x
end
local num = Model.num

-- Entier ≥ 0 (niveaux, compteurs)
local function count(x: any): number
	local v = num(x, 0)
	if v <= 0 then
		return 0
	end
	return math.floor(v)
end
Model.count = count

-- Vue du profil répliqué : p.glow lit get("glow") à chaque accès (aucune copie)
function Model.view(get: (string) -> any): Profile
	return setmetatable({}, {
		__index = function(_, key: string): any
			return get(key)
		end,
	}) :: any
end

local function sub(p: Profile, key: string): { [string]: any }
	local v = p[key]
	if type(v) == "table" then
		return v
	end
	return {}
end

-- ---------------------------------------------------------------------------------------------
-- Monnaies, passes
-- ---------------------------------------------------------------------------------------------

function Model.predictedGlow(p: Profile, now: number): number
	local glow = count(p.glow)
	local rate = math.max(0, num(p.idleRate, 0))
	local last = num(p.lastSettle, now)
	local dt = math.clamp(num(now, 0) - last, 0, MAX_PREDICT_SECONDS)
	local carry = math.clamp(num(p.glowCarry, 0), 0, 1)
	return math.max(glow, math.floor(glow + rate * dt + carry))
end

function Model.ownsPass(p: Profile, key: string): boolean
	return sub(p, "passes")[key] == true
end

function Model.supernovas(p: Profile): number
	return count(p.supernovas)
end

-- ---------------------------------------------------------------------------------------------
-- Améliorations (§4.11)
-- ---------------------------------------------------------------------------------------------

function Model.upgradeLevel(p: Profile, track: string): number
	return count(sub(p, "upgrades")[track])
end

-- Nombre d'entrées d'Atlas (mêmes bits que le serveur : 36 espèces × 6 formes)
function Model.atlasCount(p: Profile): number
	local words = p.atlas
	if type(words) ~= "table" then
		return 0
	end
	local n = 0
	for index = 0, ATLAS_BITS - 1 do
		local word = words[index // 32 + 1]
		if type(word) == "number" and word == word and bit32.btest(word, bit32.lshift(1, index % 32)) then
			n += 1
		end
	end
	return n
end

-- Valeur de l'effet d'une piste au niveau `level` (affichage « actuel → suivant »)
function Model.effect(p: Profile, track: string, level: number): number
	if track == "conga" then
		return Formulas.congaCapacity(level)
	elseif track == "stride" then
		return Formulas.baseWalkSpeed(level)
	elseif track == "lure" then
		return Formulas.lureRadius(level)
	elseif track == "perches" then
		return Formulas.perchCount(level, Model.atlasCount(p), Model.ownsPass(p, "ExtraPerches"))
	elseif track == "guard" then
		return Formulas.guardLinks(level)
	end
	return 0
end

export type UpgradeInfo = {
	track: string,
	level: number,
	max: number,
	maxed: boolean,
	cost: number,
	from: number,
	to: number,
}

function Model.upgradeInfo(p: Profile, track: string): UpgradeInfo
	local level = Model.upgradeLevel(p, track)
	local max = Formulas.upgradeMaxLevel(track :: Types.UpgradeTrack, Model.supernovas(p))
	local maxed = level >= max
	return {
		track = track,
		level = level,
		max = max,
		maxed = maxed,
		cost = if maxed then math.huge else Formulas.upgradeCost(track :: Types.UpgradeTrack, level),
		from = Model.effect(p, track, level),
		to = Model.effect(p, track, if maxed then level else level + 1),
	}
end

-- Pistes achetables avec le Glow prédit, dans l'ordre de Balance.UpgradeOrder
function Model.affordableUpgrades(p: Profile, now: number): { string }
	local glow = Model.predictedGlow(p, now)
	local out = {}
	for _, track in Balance.UpgradeOrder do
		local info = Model.upgradeInfo(p, track)
		if not info.maxed and info.cost <= glow then
			table.insert(out, track)
		end
	end
	return out
end

-- Piste achetable la moins chère (la carte qui pulse), sinon nil
function Model.cheapestAffordable(p: Profile, now: number): string?
	local best: string? = nil
	local bestCost = math.huge
	for _, track in Model.affordableUpgrades(p, now) do
		local cost = Model.upgradeInfo(p, track).cost
		if cost < bestCost then
			best, bestCost = track, cost
		end
	end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- Supernova (§4.12) — mêmes règles que EconomyService.supernovaPreview
-- ---------------------------------------------------------------------------------------------

function Model.supernovaPreview(p: Profile, now: number, inHarbor: boolean): Types.SupernovaPreview
	local R = Model.supernovas(p)
	local glow = Model.predictedGlow(p, now)
	local cost = Formulas.supernovaCost(R)
	local per = Balance.Multiplier.PerSupernova
	local auraNow, auraNext = Formulas.auraFor(R), Formulas.auraFor(R + 1)
	local resets = { "glow" }
	local keeps = { "nebbies" }
	for _, track in Balance.UpgradeOrder do
		local def = Balance.Upgrades[track]
		if def and def.ResetOnSupernova then
			table.insert(resets, track)
		elseif def then
			table.insert(keeps, track)
		end
	end
	for _, key in { "stardust", "atlas", "cosmetics", "quests", "stats" } do
		table.insert(keeps, key)
	end
	return {
		level = R,
		cost = cost,
		glow = glow,
		canAfford = glow >= cost,
		inHarbor = inHarbor,
		incomeNow = per * R,
		incomeNext = per * (R + 1),
		congaCapNow = Formulas.upgradeMaxLevel("conga", R),
		congaCapNext = Formulas.upgradeMaxLevel("conga", R + 1),
		dashNow = Formulas.dashCooldown(R),
		dashNext = Formulas.dashCooldown(R + 1),
		auraNext = if auraNext ~= auraNow then auraNext else nil,
		resets = resets,
		keeps = keeps,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Collection (§4.9, §4.13, §4.14)
-- ---------------------------------------------------------------------------------------------

function Model.uidNumber(uid: string): number
	local n = tonumber(string.sub(uid, 2))
	if string.sub(uid, 1, 1) ~= "u" or n == nil or n ~= n then
		return math.huge
	end
	return n
end

local function isInt(x: any, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and x % 1 == 0 and x >= lo and x <= hi
end

function Model.validRecord(rec: any): boolean
	return type(rec) == "table"
		and isInt(rec.s, 1, Nebbies.SPECIES_COUNT)
		and isInt(rec.f, 0, Nebbies.FORM_COUNT - 1)
		and isInt(rec.v, 0, 7)
		and isInt(rec.st, 1, Nebbies.MAX_STARS)
end

export type Ranked = {
	uids: { string },
	income: { [string]: number },
}

-- Tri des perchoirs (identique à Server/Economy/Collection.rank) : revenu passif décroissant,
-- rareté décroissante, puis uid le plus ancien
function Model.rank(nebbies: any): Ranked
	local uids: { string } = {}
	local income: { [string]: number } = {}
	if type(nebbies) ~= "table" then
		return { uids = uids, income = income }
	end
	local rarity: { [string]: number } = {}
	local number: { [string]: number } = {}
	for uid, rec in nebbies do
		if type(uid) == "string" and Model.validRecord(rec) then
			table.insert(uids, uid)
			income[uid] = Formulas.passiveIncome(rec)
			rarity[uid] = Nebbies.rarityOf(rec.s)
			number[uid] = Model.uidNumber(uid)
		end
	end
	table.sort(uids, function(a: string, b: string): boolean
		local ia, ib = income[a], income[b]
		if ia ~= ib then
			return ia > ib
		end
		local ra, rb = rarity[a], rarity[b]
		if ra ~= rb then
			return ra > rb
		end
		local na, nb = number[a], number[b]
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return { uids = uids, income = income }
end

function Model.perchCount(p: Profile): number
	return Formulas.perchCount(
		Model.upgradeLevel(p, "perches"),
		Model.atlasCount(p),
		Model.ownsPass(p, "ExtraPerches")
	)
end

function Model.stashCap(p: Profile): number
	return Formulas.stashCap(Model.ownsPass(p, "StashPlus"))
end

-- M actuel estimé (revenu répliqué / revenu des perchés), sinon M sans boost ni équipage
function Model.multiplier(p: Profile): number
	local perch = num(p.perchIncome, 0)
	local rate = num(p.idleRate, 0)
	if perch > 0 and rate > 0 then
		return rate / perch
	end
	return Formulas.multiplier({
		supernovas = Model.supernovas(p),
		vip = Model.ownsPass(p, "VIPStar"),
		crewPresent = 0,
		doubleGlow = Model.ownsPass(p, "DoubleGlow"),
		boost = false,
	})
end

export type SortMode = "income" | "rarity" | "recent"

-- Uids valides de la réserve triés pour l'affichage
function Model.sorted(nebbies: any, mode: SortMode): { string }
	local ranked = Model.rank(nebbies)
	if mode == "income" then
		return ranked.uids
	end
	local list = table.clone(ranked.uids)
	if mode == "recent" then
		table.sort(list, function(a: string, b: string): boolean
			local na, nb = Model.uidNumber(a), Model.uidNumber(b)
			if na ~= nb then
				return na > nb
			end
			return a > b
		end)
	else
		local rarity: { [string]: number } = {}
		for _, uid in list do
			rarity[uid] = Nebbies.rarityOf(nebbies[uid].s)
		end
		local order: { [string]: number } = {}
		for i, uid in ranked.uids do
			order[uid] = i
		end
		table.sort(list, function(a: string, b: string): boolean
			if rarity[a] ~= rarity[b] then
				return rarity[a] > rarity[b]
			end
			return order[a] < order[b]
		end)
	end
	return list
end

-- Stardust rendue par la libération d'un Nebby (nil = non libérable : Cosmique)
function Model.releaseDust(rec: any): number?
	if not Model.validRecord(rec) then
		return nil
	end
	return Formulas.releaseDust(Nebbies.rarityOf(rec.s), rec.st)
end

function Model.canRelease(rec: any): boolean
	return Model.validRecord(rec) and rec.lk ~= true and Model.releaseDust(rec) ~= nil
end

export type FuseGroup = {
	key: number, -- code × 8 + étoiles (Collection.groupKey)
	s: number,
	f: number,
	v: number,
	stars: number,
	uids: { string }, -- du plus ancien au plus récent
	locked: number,
	chosen: string, -- uid envoyé à Fuse (un verrouillé s'il y en a : il reste le résultat)
	cost: number,
	fusable: boolean, -- assez de copies non verrouillées (hors Stardust)
	affordable: boolean,
	gain: number, -- revenu passif du résultat − celui des 3 matières
}

-- Groupes de 3+ Nebbies identiques (espèce, forme, variantes, étoiles < 5)
function Model.fuseGroups(p: Profile): { FuseGroup }
	local nebbies = p.nebbies
	local stardust = count(p.stardust)
	local byKey: { [number]: { string } } = {}
	local keys: { number } = {}
	if type(nebbies) == "table" then
		for uid, rec in nebbies do
			if type(uid) == "string" and Model.validRecord(rec) and rec.st < Balance.Starforge.MaxStars then
				local key = Nebbies.pack(rec.s, rec.f, rec.v) * 8 + rec.st
				local list = byKey[key]
				if not list then
					list = {}
					byKey[key] = list
					table.insert(keys, key)
				end
				table.insert(list, uid)
			end
		end
	end
	local out: { FuseGroup } = {}
	for _, key in keys do
		local uids = byKey[key]
		if #uids >= Balance.Starforge.Copies then
			table.sort(uids, function(a: string, b: string): boolean
				return Model.uidNumber(a) < Model.uidNumber(b)
			end)
			local rec = nebbies[uids[1]]
			local locked = 0
			local chosen = uids[1]
			for _, uid in uids do
				if nebbies[uid].lk == true then
					if locked == 0 then
						chosen = uid
					end
					locked += 1
				end
			end
			local unlocked = #uids - locked
			-- matières : 2 copies non verrouillées en plus du choisi
			local needed = Balance.Starforge.Copies - 1
			local fusable = if locked > 0 then unlocked >= needed else unlocked >= needed + 1
			local cost = Formulas.fuseCost(rec.st) or math.huge
			local base = Formulas.passiveIncome(rec)
			local result = Formulas.passiveIncome({ s = rec.s, f = rec.f, v = rec.v, st = rec.st + 1 })
			table.insert(out, {
				key = key,
				s = rec.s,
				f = rec.f,
				v = rec.v,
				stars = rec.st,
				uids = uids,
				locked = locked,
				chosen = chosen,
				cost = cost,
				fusable = fusable,
				affordable = fusable and stardust >= cost,
				gain = result - base * Balance.Starforge.Copies,
			})
		end
	end
	table.sort(out, function(a: FuseGroup, b: FuseGroup): boolean
		if a.affordable ~= b.affordable then
			return a.affordable
		end
		if a.fusable ~= b.fusable then
			return a.fusable
		end
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.key < b.key
	end)
	return out
end

function Model.canFuseAny(p: Profile): boolean
	for _, group in Model.fuseGroups(p) do
		if group.affordable then
			return true
		end
	end
	return false
end

function Model.hasAtlasEntry(p: Profile, s: number, f: number): boolean
	local words = p.atlas
	if type(words) ~= "table" then
		return false
	end
	return Nebbies.testBit(words, Nebbies.atlasIndex(s, f))
end

function Model.hasBadge(p: Profile, variantKey: string, s: number): boolean
	local words = p.badges
	if type(words) ~= "table" then
		return false
	end
	return Nebbies.testBit(words, Nebbies.badgeIndex(variantKey, s))
end

-- Espèces activées de l'Atlas, par rareté puis id
function Model.atlasSpecies(): { number }
	local out = {}
	for _, def in Nebbies.Species do
		if Nebbies.isVersionEnabled(def.version) then
			table.insert(out, def.id)
		end
	end
	table.sort(out, function(a: number, b: number): boolean
		local ra, rb = Nebbies.rarityOf(a), Nebbies.rarityOf(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return out
end

function Model.speciesComplete(p: Profile, s: number): boolean
	for _, f in Nebbies.enabledForms() do
		if not Model.hasAtlasEntry(p, s, f) then
			return false
		end
	end
	return true
end

-- Prochain jalon d'Atlas non atteint (nil si tous atteints)
function Model.nextAtlasMilestone(entries: number): Quests.AtlasMilestone?
	for _, milestone in Quests.Atlas.Milestones do
		if milestone.entries > entries then
			return milestone
		end
	end
	return nil
end

-- Atlas verrouillé tant que Q4 n'est pas faite (sauf collection déjà commencée)
function Model.atlasLocked(p: Profile): boolean
	local step = count(sub(p, "onboarding").step)
	return step < 5 and Model.atlasCount(p) == 0
end

-- ---------------------------------------------------------------------------------------------
-- Objectifs (§7.3, §7.4, §7.5)
-- ---------------------------------------------------------------------------------------------

function Model.dailyClaimable(p: Profile, today: number): boolean
	local daily = sub(p, "daily")
	return num(daily.day, 0) ~= today
end

export type CalendarCard = { index: number, state: "claimed" | "today" | "next" | "upcoming" }

-- États des 7 cartes : « today » = réclamable maintenant ; « next » = réclamable demain
function Model.calendar(p: Profile, today: number): { CalendarCard }
	local daily = sub(p, "daily")
	local total = #Quests.Calendar
	local step = math.clamp(count(daily.step), 1, total)
	local claimedToday = num(daily.day, 0) == today
	local out: { CalendarCard } = {}
	for i = 1, total do
		local state: "claimed" | "today" | "next" | "upcoming"
		-- step == 1 réclamé aujourd'hui : le 7e jour vient d'être pris, la semaine entière est faite
		if i < step or (claimedToday and step == 1) then
			state = "claimed"
		elseif i == step then
			state = if claimedToday then "next" else "today"
		else
			state = "upcoming"
		end
		out[i] = { index = i, state = state }
	end
	return out
end

-- Quêtes du jour valides pour `today` (liste périmée = vide en attendant le serveur)
function Model.dailyQuests(p: Profile, today: number): { Types.QuestSlot }
	local quests = sub(p, "quests")
	if num(quests.day, -1) ~= today or type(quests.list) ~= "table" then
		return {}
	end
	local out = {}
	for i, entry in quests.list do
		if type(entry) == "table" and type(entry.id) == "number" and Quests.Daily[entry.id] then
			out[i] = entry
		end
	end
	return out
end

function Model.questDef(id: number): Quests.DailyQuest?
	return Quests.Daily[id]
end

function Model.rerollsLeft(p: Profile, today: number): number
	local quests = sub(p, "quests")
	local allowed = Quests.Rerolls.Free + (if Model.ownsPass(p, "VIPStar") then Quests.Rerolls.VIP else 0)
	local used = if num(quests.day, -1) == today then count(quests.rerolls) else 0
	return math.max(0, allowed - used)
end

function Model.questClaimable(entry: any): boolean
	return type(entry) == "table" and entry.done == true and entry.claimed ~= true
end

export type WeeklyState = {
	banked: number,
	goal: number,
	claimed: boolean,
	claimable: boolean,
	species: number,
}

function Model.weekly(p: Profile, week: number): WeeklyState
	local weekly = sub(p, "weekly")
	local current = num(weekly.week, -1) == week
	local banked = if current then count(weekly.banked) else 0
	local claimed = current and weekly.claimed == true
	local goal = Quests.Weekly.goal.n
	return {
		banked = banked,
		goal = goal,
		claimed = claimed,
		claimable = banked >= goal and not claimed,
		species = EventClock.rotation(Quests.Weekly.reward.rotation or "GrandParadeLegendary", week),
	}
end

-- Étape d'accueil : 0 pas commencé, 1-7 quête en cours, ≥ 8 fini
function Model.onboardingStep(p: Profile): number
	return count(sub(p, "onboarding").step)
end

function Model.onboardingDone(p: Profile): boolean
	return Model.onboardingStep(p) > #Quests.Onboarding
end

function Model.goalsHasAction(p: Profile, now: number): boolean
	local today = Clock.day(now)
	if Model.dailyClaimable(p, today) then
		return true
	end
	for _, entry in Model.dailyQuests(p, today) do
		if Model.questClaimable(entry) then
			return true
		end
	end
	return Model.weekly(p, Clock.week(now)).claimable
end

-- Glow d'une récompense « N secondes de revenu passif » (même formule que le serveur)
function Model.idleGlow(p: Profile, seconds: number?, minGlow: number?): number
	if seconds == nil then
		return 0
	end
	return Formulas.glowForSeconds(num(p.idleRate, 0), seconds, minGlow)
end

-- ---------------------------------------------------------------------------------------------
-- Boutique (§8)
-- ---------------------------------------------------------------------------------------------

-- Montant « ≈ » d'un produit Glow (nil si le produit ne donne pas de Glow)
function Model.productGlow(p: Profile, def: Monetization.ProductDef): number?
	if def.idleSeconds == nil then
		return nil
	end
	return Formulas.glowForSeconds(num(p.idleRate, 0), def.idleSeconds, def.minGlow)
end

-- Secondes restantes de la file de boost ×2 de serveur (0 si aucune). Comme
-- EventService.glowPartyRemaining : TOUT boost de serveur compte (Nuit d'Or, Starfall, LiveOps),
-- car une Glow Party achetée s'ajoute après lui (max(now, fin actuelle) + 10 min)
function Model.glowPartyRemaining(events: Types.EventStatePayload?, now: number): number
	local boost = if type(events) == "table" then events.serverBoost else nil
	if type(boost) ~= "table" then
		return 0
	end
	return math.max(0, num(boost.endsAt, 0) - num(now, 0))
end

-- Source du boost ×2 de serveur en cours (nil si aucun)
function Model.serverBoostSource(events: Types.EventStatePayload?, now: number): string?
	if Model.glowPartyRemaining(events, now) <= 0 then
		return nil
	end
	local boost = (events :: any).serverBoost
	return if type(boost.source) == "string" then boost.source else nil
end

function Model.productVisible(
	key: string,
	def: Monetization.ProductDef,
	p: Profile,
	events: Types.EventStatePayload?,
	now: number
): boolean
	if def.id <= 0 then
		return false
	end
	if def.oncePerAccount and key == "StarterKit" and p.starterKit == true then
		return false
	end
	if
		def.serverBoostSeconds ~= nil
		and Model.glowPartyRemaining(events, now) > Balance.GlowParty.HideAbove
	then
		return false
	end
	return true
end

function Model.passVisible(def: Monetization.PassDef): boolean
	return def.id > 0
end

-- Clés triées par `order`
function Model.ordered(defs: { [string]: any }): { string }
	local keys = {}
	for key in defs do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: string, b: string): boolean
		local oa, ob = num(defs[a].order, 0), num(defs[b].order, 0)
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return keys
end

-- Code promo saisi → forme envoyée au serveur (majuscules, sans espaces), nil si invalide
function Model.normalizeCode(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local code = string.upper((string.gsub(text, "%s+", "")))
	if #code == 0 or #code > CODE_MAX_LENGTH or not string.match(code, "^[A-Z0-9]+$") then
		return nil
	end
	return code
end

-- ---------------------------------------------------------------------------------------------
-- Cosmétiques (§5.3) — miroir de NestService.hasUnlock (sans les déblocages temporaires)
-- ---------------------------------------------------------------------------------------------

Model.CosmeticKinds = {
	{ kind = "style", plural = "styles", defs = Cosmetics.Styles :: { [string]: any }, equipped = "style" },
	{ kind = "title", plural = "titles", defs = Cosmetics.Titles :: { [string]: any }, equipped = "title" },
	{
		kind = "theme",
		plural = "themes",
		defs = Cosmetics.Themes :: { [string]: any },
		equipped = "nestTheme",
	},
}

function Model.ownsCosmetic(p: Profile, plural: string, defs: { [string]: any }, id: string): boolean
	local def = defs[id]
	if def == nil then
		return false
	end
	local source = def.source
	if source.kind == "free" then
		return true
	end
	local unlocks = sub(p, "unlocks")
	if type(unlocks[plural]) == "table" and unlocks[plural][id] == true then
		return true
	end
	if source.kind == "pass" then
		return source.pass ~= nil and Model.ownsPass(p, source.pass)
	elseif source.kind == "supernova" then
		return Model.supernovas(p) >= (source.supernovas or math.huge)
	elseif source.kind == "stat" then
		local value = if source.stat then sub(p, "stats")[source.stat] else nil
		return num(value, -1) >= (source.n or math.huge)
	elseif source.kind == "atlas" then
		return Model.atlasCount(p) >= (source.entries or math.huge)
	end
	return false
end

-- ---------------------------------------------------------------------------------------------
-- Réglages (§10.3)
-- ---------------------------------------------------------------------------------------------

function Model.settingsOrder(): { string }
	return Model.ordered(SettingsConfig :: any)
end

-- Valeurs d'un réglage chaîne : « auto » d'abord, puis ordre alphabétique
function Model.settingValues(key: string): { string }
	local def = SettingsConfig[key]
	local out = {}
	if def and def.values then
		for value in def.values do
			table.insert(out, value)
		end
	end
	table.sort(out, function(a: string, b: string): boolean
		if a == "auto" or b == "auto" then
			return a == "auto" and b ~= "auto"
		end
		return a < b
	end)
	return out
end

return Model
