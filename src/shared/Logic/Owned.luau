--!strict
-- Owned (lot A4, décision D17 ; GDD v2.0 §4.17, §5.4, §7.5, §11.5, Annexe B ; docs/04 §27.7) : ce que
-- le profil a GAGNÉ, lu dans le profil SEUL. Une seule règle pour le serveur (CommunityService :
-- équipement, emote de la croix, Déco perso ; QuestService : maîtrise, jalons géants) et pour le client
-- (onglet « Mon style » du lot B3) : jamais deux réponses différentes. Module pur : aucun service,
-- aucun état, aucune écriture.
--   * Owned.cosmetic(profile, kind, id, flags) : cosmétique possédé.
--       Sources de la v1.3 (Cosmetics.List), réponses d'aujourd'hui : gratuit, jours de Plop, jalon du
--       Squishydex réclamé (dex.rewards), Record R (« rebirth » : Prestige.bestR, égal à R pour un
--       profil v1). « pass », « product » et « weekly » (classements) ne sont PAS dans le profil :
--       faux ici, CommunityService garde ces trois branches.
--       Sources de la v2.0 : profil v2 seulement, chacune derrière son interrupteur (`flags`) : recordR
--       [RecordR], ascend [JellyAscend], atelier = bit de « Pour le plaisir » (atelierCosmetics)
--       [Workshop], carnet = stats.upgradesBought [Carnet], cosmétique de la semaine = bit de
--       weeklyTrack.won [WeeklyTrack], size = biggestEver [Mastery], season = season.frostDays ≥
--       FROST_DAYS (sans interrupteur : gagnée pour toujours). Un habillage de la v2.0 (sorte « theme »,
--       since = 2 dans Cosmetics.List) demande AUSSI RanchSkins. Palettes du spectacle du Grand Splorch :
--       « Pour le plaisir » (bits de la ligne « palettes »), table des Record R (« palette.fireworks »
--       au Record R 9), palette de la semaine (« peachPalette ») ; coussins : ceux de la semaine.
--   * Owned.deco(profile, n, flags) : objet n de Déco perso gagné [DecoPerso], profil v2 : jeu cumulé,
--     tampons du Squishydex (QuestRules.stampCount), jours de Plop, objectifs réclamés, Jelly Moon
--     jouées, pistes finies, Carnet (stats.upgradesBought), ligne decoShop de l'Atelier (niveau ≥ rang).
--   * Owned.kindOpen(kind, flags) : la sorte peut être équipée (sorte de la v1.3 : toujours ; palette
--     et coussins : au moins une de leurs sources ouverte).
--   * Owned.mastery(profile, s) : les 3 cases de la fiche de maîtrise de l'espèce s (★5, page dorée,
--     Trophée Cristal) ; Owned.giantTier(profile) : jalons géants atteints (0 à 4).
-- `flags` : table de booléens construite par l'appelant depuis Features.get (Owned.flags(Features.get)).
-- Lit Cosmetics.List (fusionnée au lot I, D6 : une entrée since = 2 est de la v2.0, profil v2 seulement)
-- et Cosmetics.DecoPerso.

local Shared = script.Parent.Parent
local Cosmetics = require(Shared.Config.Cosmetics)
local Upgrades = require(Shared.Config.Upgrades)
local Visuals = require(Shared.Config.Visuals)
local Balance = require(Shared.Config.Balance)
local Mutations = require(Shared.Config.Mutations)
local Prestige = require(script.Parent.Prestige)
local Bitset = require(script.Parent.Bitset)
local QuestRules = require(script.Parent.QuestRules)
local UpgradeMath = require(script.Parent.UpgradeMath)

export type Flags = { [string]: boolean }

local Owned = {}

-- Jours de Plop nourri pendant le costume d'hiver pour la selle « Sucre glace » (GDD §11.5, D33)
Owned.FROST_DAYS = 5
-- Jalons géants (plus grande taille jamais atteinte, GDD §4.17) : selle « Cosmique », traînée « Étoiles
-- filantes », Squishy-Soleil (dessiné à partir de 3, aucun cosmétique), titre « Gardien du Soleil »
Owned.GIANT_SIZES = { 1e15, 1e18, 1e21, 1e24 }
-- Interrupteurs lus par ce module (Owned.flags les recopie depuis Features.get)
Owned.FLAGS =
	{ "RecordR", "JellyAscend", "Workshop", "Carnet", "WeeklyTrack", "Mastery", "RanchSkins", "DecoPerso" }

type Source = { kind: string, value: number }

-- Interrupteur de chaque source de la v2.0 (« season » : aucun, gagnée pour toujours)
local FLAG_OF: { [string]: string } = {
	recordR = "RecordR",
	ascend = "JellyAscend",
	atelier = "Workshop",
	carnet = "Carnet",
	won = "WeeklyTrack", -- bit de weeklyTrack.won (cosmétiques de la semaine)
	size = "Mastery",
}

local STAR5 = bit32.lshift(1, 4) -- dex.stars[s] : bit k − 1 = badge ★k
local MASK_RANGE = 4294967296

-- Mutations d'une page dorée : les 8 hors Lunaire (même règle que QuestRules.goldenPages)
local GOLDEN_NEED = 0
for _, def in Mutations.List do
	if not Mutations.GoldenPageExcludes[def.id] then
		GOLDEN_NEED = bit32.bor(GOLDEN_NEED, bit32.lshift(1, def.id))
	end
end

-- Trophée Cristal : palier « crystal » de l'Étagère (Balance.Trophies)
local CRYSTAL = math.huge
for _, tier in Balance.Trophies do
	if tier.tier == "crystal" then
		CRYSTAL = tier.min
	end
end

-- Sources de la v2.0 par « <sorte>:<id> » ; sortes de la v1.3 (toujours ouvertes) ; interrupteurs
-- qui ouvrent au moins une source d'une sorte v2.0 (palette, coussins)
local V2: { [string]: Source } = {}
local V1_KIND: { [string]: boolean } = {}
local KIND_FLAGS: { [string]: { [string]: boolean } } = {}

for _, def in Cosmetics.List do
	if def.since == nil then
		V1_KIND[def.kind] = true
	end
end

local function add(kind: string, id: string, sourceKind: string, value: number)
	local key = kind .. ":" .. id
	-- la v1.3 d'abord (réponses inchangées), puis la première source déclarée
	local def = Cosmetics.ByKindId[key]
	if (def ~= nil and def.since == nil) or V2[key] ~= nil then
		return
	end
	V2[key] = { kind = sourceKind, value = value }
	local flag = FLAG_OF[sourceKind]
	if flag ~= nil then
		local set = KIND_FLAGS[kind] or {}
		KIND_FLAGS[kind] = set
		set[flag] = true
	end
end

-- entrées de la v2.0 de la liste (cosmétiques de la semaine compris : source won i)
for _, def in Cosmetics.List do
	if def.since ~= nil then
		add(def.kind, def.id, def.source.kind, def.source.value or 0)
	end
end
for _, line in Upgrades.Fun do
	if line.store == "bits" then
		for j, grant in line.grants do
			local id = string.match(grant, "^palette%.(.+)$")
			if id ~= nil then
				add("palette", id, "atelier", (line.firstBit or 1) + j - 1)
			end
		end
	end
end
for r, row in Visuals.RecordTable do
	for _, tile in row.unlocks do
		local name = if tile.vars then tile.vars.name else nil
		local id = if type(name) == "string" then string.match(name, "^palette%.(.+)$") else nil
		if id ~= nil then
			add("palette", id, "recordR", r)
		end
	end
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

local function field(t: any, key: string): any
	return if type(t) == "table" then t[key] else nil
end

-- Masque entier sûr dans [0 ; 2^32[
local function mask(x: any): number
	local v = num(x, 0)
	if v < 0 then
		return 0
	end
	return math.floor(v) % MASK_RANGE
end

local function isV2(profile: any): boolean
	return type(profile) == "table" and type(profile.version) == "number" and profile.version >= 2
end

-- Source de la v1.3 (réponses d'aujourd'hui)
local function v1Owned(profile: any, source: any): boolean
	local kind = source.kind
	if kind == "free" then
		return true
	end
	if type(profile) ~= "table" then
		return false
	end
	local need = num(source.value, math.huge)
	if kind == "plopDay" then
		return num(profile.plopDays, 0) >= need
	elseif kind == "dex" then
		return type(profile.dex) == "table" and num(profile.dex.rewards, 0) >= need
	elseif kind == "rebirth" then
		return Prestige.bestR(profile) >= need
	end
	return false -- pass, product, weekly : hors du profil (CommunityService)
end

-- Recopie les interrupteurs lus par Owned depuis `get` (Features.get) ; `into` réutilisée si donnée
function Owned.flags(get: (string) -> any, into: Flags?): Flags
	local out: Flags = into or {}
	for _, key in Owned.FLAGS do
		out[key] = get(key) == true
	end
	return out
end

-- Cosmétique `kind` / `id` gagné par ce profil (voir l'en-tête)
function Owned.cosmetic(profile: any, kind: string, id: string, flags: Flags?): boolean
	if type(kind) ~= "string" or type(id) ~= "string" then
		return false
	end
	local key = kind .. ":" .. id
	local def = Cosmetics.ByKindId[key]
	if def ~= nil and def.since == nil then
		return v1Owned(profile, def.source)
	end
	local source = V2[key]
	if source == nil or not isV2(profile) or type(flags) ~= "table" then
		return false
	end
	if kind == "theme" and flags.RanchSkins ~= true then
		return false
	end
	local flag = FLAG_OF[source.kind]
	if flag ~= nil and flags[flag] ~= true then
		return false
	end
	local need = source.value
	local s = source.kind
	if s == "recordR" then
		return Prestige.bestR(profile) >= need
	elseif s == "ascend" then
		return Prestige.ascend(profile) >= need
	elseif s == "atelier" then
		return Bitset.has(profile.atelierCosmetics, need)
	elseif s == "carnet" then
		return num(field(profile.stats, "upgradesBought"), 0) >= need
	elseif s == "won" then
		return Bitset.has(field(profile.weeklyTrack, "won"), need)
	elseif s == "size" then
		return num(profile.biggestEver, 0) >= need
	elseif s == "season" then
		return num(field(profile.season, "frostDays"), 0) >= Owned.FROST_DAYS
	end
	return false
end

-- Objet n (1 … 40) de Déco perso gagné [DecoPerso], profil v2 (voir l'en-tête)
function Owned.deco(profile: any, n: number, flags: Flags?): boolean
	if type(flags) ~= "table" or flags.DecoPerso ~= true or not isV2(profile) then
		return false
	end
	if type(n) ~= "number" or n ~= n or n % 1 ~= 0 then
		return false
	end
	local item = Cosmetics.DecoPerso[n]
	if item == nil or item.n ~= n then
		return false
	end
	local need = num(item.source.value, math.huge)
	local s = item.source.kind
	local stats = profile.stats
	if s == "play" then
		return num(field(stats, "playSeconds"), 0) >= need
	elseif s == "dex" then
		return type(profile.dex) == "table" and QuestRules.stampCount(profile.dex) >= need
	elseif s == "plopDay" then
		return num(profile.plopDays, 0) >= need
	elseif s == "objectives" then
		return num(field(stats, "objectivesClaimed"), 0) >= need
	elseif s == "moon" then
		return num(field(profile.moon, "sessions"), 0) >= need
	elseif s == "track" then
		return num(field(stats, "tracksDone"), 0) >= need
	elseif s == "carnet" then
		return num(field(stats, "upgradesBought"), 0) >= need
	elseif s == "atelier" then
		return UpgradeMath.level("decoShop", profile) >= need
	end
	return false
end

-- La sorte peut-elle être équipée avec ces interrupteurs ? (sorte de la v1.3 : toujours ; sorte de la
-- v2.0 : au moins une de ses sources ouverte ; inconnue : jamais)
function Owned.kindOpen(kind: string, flags: Flags?): boolean
	if type(kind) ~= "string" then
		return false
	end
	if V1_KIND[kind] then
		return true
	end
	local set = KIND_FLAGS[kind]
	if set == nil or type(flags) ~= "table" then
		return false
	end
	for flag in set do
		if flags[flag] == true then
			return true
		end
	end
	return false
end

-- Les 3 cases de la maîtrise de l'espèce s (GDD §4.17) : badge ★5, page dorée (les 8 mutations hors
-- Lunaire), Trophée Cristal (taille record ≥ palier « crystal » de Balance.Trophies)
function Owned.mastery(profile: any, s: number): (boolean, boolean, boolean)
	local dex = field(profile, "dex")
	local stars = field(dex, "stars")
	local mut = field(dex, "mut")
	local trophies = field(profile, "trophies")
	local star = mask(if type(stars) == "table" then stars[s] else nil)
	local page = mask(if type(mut) == "table" then mut[s] else nil)
	local size = num(if type(trophies) == "table" then trophies[s] else nil, 0)
	return bit32.btest(star, STAR5), bit32.band(page, GOLDEN_NEED) == GOLDEN_NEED, size >= CRYSTAL
end

-- Jalons géants atteints par la plus grande taille jamais vue (0 à #GIANT_SIZES)
function Owned.giantTier(profile: any): number
	local big = num(field(profile, "biggestEver"), 0)
	local n = 0
	for _, at in Owned.GIANT_SIZES do
		if big >= at then
			n += 1
		end
	end
	return n
end

return Owned
