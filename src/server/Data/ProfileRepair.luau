--!strict
-- ProfileRepair (paquet ranch, docs/04 §8.5, §11.15, GDD §12.6). Données lues = données à revalider :
-- après migrate + reconcile, revérifie chaque champ du profil (types, bornes, NaN, tableaux denses
-- allongés à Species.List, uids, lieux, emplacements de Meilleur Ami uniques, tenues, capacités) et
-- répare EN PLACE avec une valeur sûre. Rend la liste des réparations, chacune nommée comme un chemin
-- du profil (« squishies.<uid>.z », « dex.mut »…), comptées par DiagnosticsService
-- (Signals.ProfileRepaired, note INT-REPAIR).
-- Règles :
--   * pur et déterministe (aucun service Roblox, aucune horloge) : même profil → mêmes réparations ;
--   * jamais d'erreur, quel que soit le profil (une vieille sauvegarde ou un bug passé ne peut jamais
--     faire planter le chargement) ;
--   * on ne perd jamais une donnée valide : un tableau dense plus long que Species.List (espèces
--     ajoutées plus tard, 64 dans le test) n'est JAMAIS tronqué ; un squishy d'une espèce future
--     (identifiant entier ≥ 1 encore inconnu de ce serveur) est gardé tel quel ; une clé héritée
--     inconnue (ex. `coinBuy` de la v1.1) n'est ni lue ni effacée ;
--   * idempotent : réparer un profil déjà réparé ne change plus rien (liste vide).
-- Contrat v1.2 : squishies[uid].gd (entier ≥ 0) ; dex.fam (0 / 1, dense, allongé à
-- #Species.FamilyOrder) ; outfits.worn vidé (la tenue portée vit dans rec.o ; porteurs au-delà de
-- owned retirés) ; caps.petSitIn et caps.splorchCoins (nombres) ; caps.petSitBy (clés chaînes d'UserId
-- → entiers bornés) ; moon.lastSession.
-- Schéma v2 (lot A2, docs/04 §27.2) : un profil de version ≥ 2 (et lui seul) est réparé sur
-- Schema.defaultsFor(2) avec les bornes de chaque champ v2 (R ≤ bestR ≤ MaxR, A, regainBonusA ≤ A,
-- memoryR ≤ bestR, Confettis, familles nouvelles, Atelier, ensembles de bits, décorations dorées,
-- piste, Déco perso, cœurs, plafonds v2, habillage gagné), chaque niveau ramené à son plafond
-- (UpgradeMath.cap, tous interrupteurs ouverts : même règle que Logic/Invariants). Un profil v1 est
-- réparé EXACTEMENT comme dans la version de test (aucun champ v2 lu ni écrit) : tant que
-- l'interrupteur figé SchemaV2 est coupé, DataService ne lui passe jamais de profil v2 (refusé,
-- « schéma plus récent »). Règle d'une valeur illisible : la valeur sûre ne donne jamais rien
-- deux fois (bonus de retour déjà donné, × 1,25 refusé, bit non possédé, carte déjà vue).
-- Lot A4 (docs/04 §27.2) : compteurs de la méta (stats.objectivesClaimed, stats.tracksDone,
-- moon.sessions), cosmétiques de la semaine gagnés et jeu des 7 derniers jours (weeklyTrack.won,
-- play, playDay), palette et coussins choisis (identifiant inconnu → ""), réglage « Montrer mon halo »
-- (booléen, sinon vrai ; profil v2 seulement), objet de Déco perso posé sur un emplacement d'une autre
-- taille (Cosmetics.DecoSlots) → emplacement vidé.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Cosmetics = require(Shared.Config.Cosmetics)
local Quests = require(Shared.Config.Quests)
local SettingsConfig = require(Shared.Config.Settings)
local Upgrades = require(Shared.Config.Upgrades)
local Visuals = require(Shared.Config.Visuals)
local Formulas = require(Shared.Logic.Formulas)
local QuestRules = require(Shared.Logic.QuestRules)
local Prestige = require(Shared.Logic.Prestige)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local Bitset = require(Shared.Logic.Bitset)
local Schema = require(script.Parent.Schema)

local ProfileRepair = {}

local MAX = Balance.Numbers.Max
-- au-delà, un index de tableau dense est une donnée abîmée (jamais 4 096 espèces)
local MAX_DENSE = 4096
local MAX_INT = 2 ^ 53
local MAX_UID = 2 ^ 41 -- 8 caractères en base 36
local MAX_BF = #Balance.Splorch.BestFriendSlotsAt
local MAX_STEP = #Quests.Onboarding.Steps
local LOCATIONS = { pen = true, pool = true, dodo = true, mail = true }

-- tenues connues (Config/Cosmetics, kind "outfit")
local OUTFITS: { [string]: boolean } = {}
for _, def in Cosmetics.List do
	if def.kind == "outfit" then
		OUTFITS[def.id] = true
	end
end
-- lot A4 (D21) : tenues v2.0 (Cosmetics.ListV2, rotation de la semaine), connues d'un profil v2 seulement
-- (mêmes listes que SquishyService : portées, jamais retirées au chargement)
local OUTFITS_V2: { [string]: boolean } = {}
for _, list in { Cosmetics.ListV2 :: { any }, Cosmetics.WeeklyRotation :: { any } } do
	for _, def in list do
		if def.kind == "outfit" then
			OUTFITS_V2[def.id] = true
		end
	end
end

-- Bornes du schéma v2 (docs/04 §27.2 ; mêmes nombres que Logic/Invariants)
local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local CONFETTI_MAX = Balance.Confetti.Max
local WORD_MAX = 4294967295 -- mot de 32 bits (Logic/Bitset)
local BITSET_MAX_WORDS = Bitset.MaxBits // Bitset.WordBits
local DECOR_BUILDS = Balance.Tiles.decor.Levels -- une case par décoration (18)
local DECOR_BUILDS_MAX = 10
local DECO_OWNED_BITS = 64
local DECO_SLOTS = 12
local DECO_ITEMS = #Cosmetics.DecoPerso
local HEARTS_GIVEN_MAX = Balance.Hearts.PerDay
local CHALLENGES_MAX = Quests.WeeklyTrack.ChallengesPerWeek
local TRACK_TIERS = #Quests.WeeklyTrack.Tiers
local CARNET_TIERS = #Quests.Carnet.Tiers
-- lot A4 : cosmétiques de la semaine (un bit chacun), jeu des 7 derniers jours (secondes par jour UTC)
local WEEKLY_COSMETICS = #Cosmetics.WeeklyRotation
local PLAY_DAYS = 7
local DAY_SECONDS = 86400
-- familles nouvelles : champ de tiles et nombre de niveaux (ordre fixe : réparations déterministes)
local NEW_TILES = {
	{ "star", Balance.UpgradePrices.star.Levels },
	{ "gloves", Balance.UpgradePrices.gloves.Levels },
	{ "school", Balance.UpgradePrices.school.Levels },
	{ "monuments", Balance.UpgradePrices.monument.Levels },
}
-- plafonds du jour v2 (ordre fixe)
local CAPS_V2: { string } = {}
for key in Balance.CapsV2 do
	table.insert(CAPS_V2, key)
end
table.sort(CAPS_V2)
-- plafonds des niveaux : tous les interrupteurs ouverts (structure du profil, pas l'état du jour)
local ALL_FLAGS = {
	get = function(_key: string): boolean
		return true
	end,
}
-- où vit le niveau de chaque ligne achetable (UpgradeMath.ids) : champ de tiles, case de l'Atelier
-- ou bits de « Pour le plaisir »
type LevelSlot = { tile: string?, row: number?, firstBit: number?, bits: number? }
local LEVEL_SLOTS: { [string]: LevelSlot } = {}
for _, def in Upgrades.Families do
	local tile = string.match(def.profileKey, "^tiles%.(%w+)$")
	if tile then
		LEVEL_SLOTS[def.id] = { tile = tile }
	end
end
for i, row in Upgrades.WorkshopRows do
	LEVEL_SLOTS[row.id] = { row = i }
end
for _, line in Upgrades.Fun do
	if line.store == "bits" then
		LEVEL_SLOTS["fun." .. line.id] = { firstBit = line.firstBit or 1, bits = #line.costs }
	end
end
-- habillages connus (cosmetics.theme : 3 de la v1.3 et 11 de la v2.0) → condition pour l'avoir
local THEMES: { [string]: any } = {}
for _, list in { Cosmetics.List, Cosmetics.ListV2 } do
	for _, def in list :: { any } do
		if def.kind == "theme" then
			THEMES[def.id] = def.source
		end
	end
end
-- lot A4 : palettes du spectacle connues (cosmetics.palette : ligne « palettes » de « Pour le
-- plaisir », objets « palette.* » de la table des Record R, palette de la semaine) et coussins
-- (cosmetics.cushions : coussins de la semaine) ; mêmes listes que Logic/Invariants
local PALETTES: { [string]: boolean } = {}
local CUSHIONS: { [string]: boolean } = {}
for _, line in Upgrades.Fun do
	for _, grant in line.grants do
		local id = string.match(grant, "^palette%.(.+)$")
		if id then
			PALETTES[id] = true
		end
	end
end
for _, row in Visuals.RecordTable do
	for _, tile in row.unlocks do
		local name = if tile.vars then tile.vars.name else nil
		local id = if type(name) == "string" then string.match(name, "^palette%.(.+)$") else nil
		if id then
			PALETTES[id] = true
		end
	end
end
for _, item in Cosmetics.WeeklyRotation do
	if item.kind == "palette" then
		PALETTES[item.id] = true
	elseif item.kind == "cushions" then
		CUSHIONS[item.id] = true
	end
end

-- =============================================================================================
-- Petits outils purs
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Réel fini dans [lo ; hi] ? sinon (false, valeur sûre)
local function realIn(x: any, lo: number, hi: number, default: number): (boolean, number)
	if not finite(x) then
		return false, default
	end
	if x < lo then
		return false, lo
	end
	if x > hi then
		return false, hi
	end
	return true, x
end

-- Entier dans [lo ; hi] ? sinon (false, valeur sûre : bornée et arrondie vers le bas)
local function intIn(x: any, lo: number, hi: number, default: number): (boolean, number)
	if not finite(x) then
		return false, default
	end
	local v = math.clamp(math.floor(x), lo, hi)
	return v == x, v
end

local function validUid(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= 8 and string.match(x, "^[0-9a-z]+$") ~= nil
end

-- Ordre de création d'un uid base 36 (plus court puis alphabétique) : déterministe
local function uidBefore(a: string, b: string): boolean
	if #a ~= #b then
		return #a < #b
	end
	return a < b
end

local function sortedUids(squishies: { [string]: any }): { string }
	local list = {}
	for uid in squishies do
		table.insert(list, uid)
	end
	table.sort(list, uidBefore)
	return list
end

-- Tableau séquentiel sans trou ni clé étrangère
local function isDense(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		n += 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

-- =============================================================================================
-- Réparation
-- =============================================================================================

type Ctx = { fixes: { string }, seen: { [string]: boolean } }

local function fix(ctx: Ctx, path: string)
	if not ctx.seen[path] then
		ctx.seen[path] = true
		table.insert(ctx.fixes, path)
	end
end

-- Copie profonde (aucune table partagée entre profils)
local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, vv in v do
		out[k] = deepCopy(vv)
	end
	return out
end

-- Forme : chaque clé d'un dictionnaire par défaut garde le TYPE de sa valeur par défaut (récursif sur
-- les dictionnaires non vides) ; nombres NaN / infinis remplacés. Les listes et les maps vides du
-- modèle (squishies, passes…) ne sont pas parcourues ici (règles propres plus bas).
local function shape(ctx: Ctx, target: { [any]: any }, template: { [any]: any }, path: string)
	-- un dictionnaire n'a que des clés chaînes (une table mixte perd des données dans un DataStore)
	local foreign = {}
	for k in target do
		if type(k) ~= "string" then
			table.insert(foreign, k)
		end
	end
	for _, k in foreign do
		target[k] = nil
		fix(ctx, if path == "" then "profile.keys" else path .. ".keys")
	end
	for k, def in template do
		local cur = target[k]
		local p = if path == "" then tostring(k) else path .. "." .. tostring(k)
		if type(cur) ~= type(def) then
			target[k] = deepCopy(def)
			fix(ctx, p)
		elseif type(def) == "number" and not finite(cur) then
			target[k] = def
			fix(ctx, p)
		elseif type(def) == "table" and next(def) ~= nil and #def == 0 then
			shape(ctx, cur, def, p)
		end
	end
end

-- Tableau dense de nombres : allongé à `minLen` (valeur `fill`), jamais tronqué ; chaque case
-- ramenée par `clean`. Une table à trous ou mixte est reconstruite à partir de ses index entiers
-- valides (les clés étrangères et les index aberrants sont retirés).
local function denseNumbers(
	ctx: Ctx,
	value: any,
	minLen: number,
	fill: number,
	clean: (any) -> (boolean, number),
	path: string
): { number }
	local out: { number } = {}
	local changed = false
	if type(value) ~= "table" then
		changed = true
		value = {}
	end
	local maxIndex = 0
	if isDense(value) then
		maxIndex = #value
	else
		changed = true
		for k in value do
			if type(k) == "number" and k >= 1 and k % 1 == 0 and k <= MAX_DENSE and k > maxIndex then
				maxIndex = k
			end
		end
	end
	local len = math.max(maxIndex, minLen)
	for i = 1, len do
		local raw = value[i]
		if raw == nil then
			if i <= maxIndex then
				changed = true -- trou
			end
			out[i] = fill
		else
			local ok, v = clean(raw)
			if not ok then
				changed = true
			end
			out[i] = v
		end
	end
	if #out ~= maxIndex then
		changed = true -- allongé
	end
	if changed then
		fix(ctx, path)
	end
	return out
end

local function cleanSize(x: any): (boolean, number)
	return realIn(x, 0, MAX, 0)
end

local function cleanMask(x: any): (boolean, number)
	return intIn(x, 0, 4294967295, 0)
end

local function cleanFam(x: any): (boolean, number)
	if x == 0 or x == 1 then
		return true, x
	end
	return false, if x == true or (finite(x) and x >= 1) then 1 else 0
end

-- Champ entier d'un dictionnaire (réparé en place)
local function intField(ctx: Ctx, t: { [string]: any }, key: string, lo: number, hi: number, path: string)
	local ok, v = intIn(t[key], lo, hi, if lo > 0 then lo else 0)
	if not ok then
		t[key] = v
		fix(ctx, path)
	end
end

local function realField(ctx: Ctx, t: { [string]: any }, key: string, lo: number, hi: number, path: string)
	local ok, v = realIn(t[key], lo, hi, lo)
	if not ok then
		t[key] = v
		fix(ctx, path)
	end
end

local function boolField(ctx: Ctx, t: { [string]: any }, key: string, default: boolean, path: string)
	if type(t[key]) ~= "boolean" then
		t[key] = default
		fix(ctx, path)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Économie
-- ---------------------------------------------------------------------------------------------

local function repairEconomy(ctx: Ctx, d: { [string]: any }, v2: boolean)
	-- pièces : finies, ≥ 0, ≤ Max, entières sous ExactBelow
	local coins = d.coins
	local safeCoins = Formulas.clampCoins(coins)
	if not finite(coins) or coins ~= safeCoins then
		d.coins = safeCoins
		fix(ctx, "coins")
	end
	realField(ctx, d, "pot", 0, MAX, "pot")
	realField(ctx, d, "fame", 0, MAX, "fame")
	-- r de la boucle (v2 : borné à MaxR, comme Logic/Invariants)
	intField(ctx, d, "R", 0, if v2 then MAX_R else 1e6, "R")
	intField(ctx, d, "lastOnline", 0, MAX_INT, "lastOnline")
	intField(ctx, d, "firstJoin", 0, MAX_INT, "firstJoin")
	realField(ctx, d, "biggestEver", 0, MAX, "biggestEver")

	local growth = d.growth
	realField(ctx, growth, "G", 0, MAX, "growth.G")
	realField(ctx, growth, "g", 0, MAX, "growth.g")
	if not finite(growth.t) then
		growth.t = 0
		fix(ctx, "growth.t")
	end

	local tiles = d.tiles
	for _, key in { "snack", "decor", "pens" } do
		intField(ctx, tiles, key, 0, (Balance.Tiles :: any)[key].Levels, "tiles." .. key)
	end
	boolField(ctx, tiles, "cozyBed", false, "tiles.cozyBed")
	intField(ctx, tiles, "seen", 0, 4294967295, "tiles.seen")

	realField(ctx, d.boosts, "personalLeft", 0, MAX, "boosts.personalLeft")

	local caps = d.caps
	intField(ctx, caps, "day", 0, MAX_INT, "caps.day")
	for key, cap in Balance.Caps do
		-- compteur scalaire : nombre entier dans [0 ; plafond] (petSitIn, splorchCoins compris)
		local ok, v = intIn(caps[key], 0, cap, 0)
		if not ok then
			caps[key] = v
			fix(ctx, "caps." .. key)
		end
	end
	-- plafond par ami : clés chaînes d'UserId → entiers dans [0 ; CapsPerFriend.petSit]
	local by = caps.petSitBy
	if type(by) ~= "table" then
		caps.petSitBy = {}
		fix(ctx, "caps.petSitBy")
	else
		local clean = {}
		local changed = false
		for key, count in by do
			if type(key) == "string" and string.match(key, "^%-?%d+$") ~= nil and #key <= 20 then
				local ok, v = intIn(count, 0, Balance.CapsPerFriend.petSit, 0)
				if not ok then
					changed = true
				end
				clean[key] = v
			else
				changed = true
			end
		end
		if changed then
			caps.petSitBy = clean
			fix(ctx, "caps.petSitBy")
		end
	end
	-- caps.coinBuy (v1.1) : clé héritée ignorée, ni lue ni effacée
end

-- ---------------------------------------------------------------------------------------------
-- Collection
-- ---------------------------------------------------------------------------------------------

local function repairSquishies(ctx: Ctx, d: { [string]: any }, v2: boolean)
	local squishies = d.squishies
	-- lignes illisibles retirées (uid abîmé, ligne qui n'est pas une table, espèce illisible)
	for _, uid in sortedUids(squishies :: any) do
		local rec = squishies[uid]
		local path = "squishies." .. tostring(uid)
		if not validUid(uid) or type(rec) ~= "table" then
			squishies[uid] = nil
			fix(ctx, path)
			continue
		end
		-- espèce : entier ≥ 1 ; une espèce FUTURE (entier encore inconnu ici) est gardée
		if not finite(rec.s) or rec.s < 1 or rec.s % 1 ~= 0 or rec.s > 1e6 then
			squishies[uid] = nil
			fix(ctx, path)
			continue
		end
		local ok, v = intIn(rec.m, 0, Mutations.Count, 0)
		if not ok then
			rec.m = v
			fix(ctx, path .. ".m")
		end
		ok, v = intIn(rec.st, 0, Balance.Fusion.MaxStars, 0)
		if not ok then
			rec.st = v
			fix(ctx, path .. ".st")
		end
		ok, v = realIn(rec.z, 1, MAX, 1)
		if not ok then
			rec.z = v
			fix(ctx, path .. ".z")
		end
		ok, v = realIn(rec.zg, 0, MAX, 0)
		if not ok then
			rec.zg = v
			fix(ctx, path .. ".zg")
		end
		ok, v = intIn(rec.bf, 0, MAX_BF, 0)
		if not ok then
			rec.bf = v
			fix(ctx, path .. ".bf")
		end
		if type(rec.lk) ~= "boolean" then
			rec.lk = false
			fix(ctx, path .. ".lk")
		end
		if
			type(rec.o) ~= "string" or (rec.o ~= "" and not OUTFITS[rec.o] and not (v2 and OUTFITS_V2[rec.o]))
		then
			rec.o = ""
			fix(ctx, path .. ".o")
		end
		if not LOCATIONS[rec.at] then
			rec.at = "pen" -- ramené par la règle des capacités plus bas si l'enclos est plein
			fix(ctx, path .. ".at")
		end
		ok, v = realIn(rec.b, 0, MAX, 0)
		if not ok then
			rec.b = math.floor(v)
			fix(ctx, path .. ".b")
		end
		-- jour UTC du dernier bonus de croissance du Rush : entier ≥ 0 (contrat v1.2)
		ok, v = intIn(rec.gd, 0, 1e9, 0)
		if not ok then
			rec.gd = v
			fix(ctx, path .. ".gd")
		end
	end

	local order = sortedUids(squishies :: any)

	-- nextUid : entier, toujours au-delà du plus grand uid existant (jamais deux squishies au même uid)
	local maxUid = 0
	for _, uid in order do
		local n = tonumber(uid, 36)
		if n and n > maxUid then
			maxUid = n
		end
	end
	local okNext, nextUid = intIn(d.nextUid, 1, MAX_UID, 1)
	if nextUid <= maxUid then
		nextUid = maxUid + 1
		okNext = false
	end
	if not okNext then
		d.nextUid = nextUid
		fix(ctx, "nextUid")
	end

	-- un seul squishy par emplacement de Meilleur Ami (le plus ancien garde la place)
	local bfTaken: { [number]: boolean } = {}
	for _, uid in order do
		local rec = squishies[uid]
		if rec.bf > 0 then
			if bfTaken[rec.bf] then
				rec.bf = 0
				fix(ctx, "squishies." .. uid .. ".bf")
			else
				bfTaken[rec.bf] = true
			end
		end
	end

	-- capacités : Bassin ≤ poolSlots (surplus → enclos), enclos + Bassin ≤ penCapacity (surplus →
	-- Dodo), Dodo ≤ 60 (surplus → Lettres), Lettres ≤ 20 ; au-delà de toutes les places (profil abîmé
	-- seulement : jamais atteint en jeu), les plus récents sont retirés
	local passes = d.passes
	local bigRanch = type(passes) == "table" and passes.BigRanch == true
	local penCap = math.min(Balance.Pens.Max, Formulas.penCapacity(d.tiles.pens, bigRanch))
	local poolCap = Formulas.poolSlots(QuestRules.familyEarned(d.dex, "axolo"))
	local count = { pen = 0, pool = 0, dodo = 0, mail = 0 }
	for _, uid in order do
		local rec = squishies[uid]
		local at = rec.at
		if at == "pool" and count.pool >= poolCap then
			at = "pen"
		end
		if (at == "pen" or at == "pool") and count.pen + count.pool >= penCap then
			at = "dodo"
		end
		if at == "dodo" and count.dodo >= Balance.Pens.Dodo then
			at = "mail"
		end
		if at == "mail" and count.mail >= Balance.Pens.Mail then
			-- les autres lieux ont-ils encore une place ?
			if count.pen + count.pool < penCap then
				at = "pen"
			elseif count.dodo < Balance.Pens.Dodo then
				at = "dodo"
			else
				squishies[uid] = nil
				fix(ctx, "squishies." .. uid .. ".overflow")
				continue
			end
		end
		if at ~= rec.at then
			-- capacité réduite (pass Grand Ranch remboursé) ou profil abîmé : le squishy change de lieu
			-- SANS perdre ni gagner de taille (revue) : vers le Dodo ou les Lettres, sa taille du moment
			-- z + (G − zg) est figée dans z (zg = 0, comme MoveSquishy) ; vers l'enclos, zg = G (sa
			-- taille reste z puis grandit de nouveau, comme ClaimMail)
			local wasVisible = rec.at == "pen" or rec.at == "pool"
			local nowVisible = at == "pen" or at == "pool"
			if wasVisible and not nowVisible then
				rec.z = Formulas.sizeAt(rec, d.growth.G)
				rec.zg = 0
			elseif nowVisible and not wasVisible then
				rec.zg = d.growth.G
			end
			rec.at = at
			fix(ctx, "squishies." .. uid .. ".at")
		end
		count[at] += 1
	end

	-- monture : uid existant ou ""
	if d.mount ~= "" and type(squishies[d.mount]) ~= "table" then
		d.mount = ""
		fix(ctx, "mount")
	end

	-- tenues (contrat v1.2) : owned = { [id] = entier ≥ 0 } ; la tenue portée vit dans rec.o
	-- seulement ; porteurs au-delà de owned retirés (les plus récents d'abord) ; worn vidé
	local outfits = d.outfits
	if type(outfits.owned) ~= "table" then
		outfits.owned = {}
		fix(ctx, "outfits.owned")
	else
		local clean = {}
		local changed = false
		for id, n in outfits.owned do
			if type(id) == "string" and #id <= 64 then
				local ok, v = intIn(n, 0, 1e9, 0)
				if not ok then
					changed = true
				end
				clean[id] = v
			else
				changed = true
			end
		end
		if changed then
			outfits.owned = clean
			fix(ctx, "outfits.owned")
		end
	end
	if outfits.worn == nil or type(outfits.worn) ~= "table" or next(outfits.worn) ~= nil then
		outfits.worn = {}
		fix(ctx, "outfits.worn")
	end
	local wearers: { [string]: number } = {}
	for _, uid in order do
		local rec = squishies[uid]
		if rec and rec.o ~= "" then
			local n = (wearers[rec.o] or 0) + 1
			if n > (outfits.owned[rec.o] or 0) then
				rec.o = ""
				fix(ctx, "squishies." .. uid .. ".o")
			else
				wearers[rec.o] = n
			end
		end
	end

	-- Cuve
	local vat = d.vat
	realField(ctx, vat, "fillAt", 0, MAX_INT, "vat.fillAt")
	boolField(ctx, vat, "pending", false, "vat.pending")
	intField(ctx, vat, "pityRare", 0, 1e9, "vat.pityRare")
	intField(ctx, vat, "pityEpic", 0, 1e9, "vat.pityEpic")
	intField(ctx, vat, "newPulls", 0, Balance.Vat.NewPulls, "vat.newPulls")
	intField(ctx, vat, "pulls", 0, 1e12, "vat.pulls")

	-- 12 derniers relâchés : liste dense de { s, m } valides, le plus récent à la fin
	local released = d.released
	local keep: { any } = {}
	local changed = not isDense(released)
	local list = {}
	if isDense(released) then
		list = released
	else
		local idx = {}
		for k in released do
			if type(k) == "number" and k >= 1 and k % 1 == 0 then
				table.insert(idx, k)
			end
		end
		table.sort(idx)
		for _, k in idx do
			table.insert(list, released[k])
		end
	end
	for _, entry in list do
		if
			type(entry) == "table"
			and finite(entry.s)
			and entry.s >= 1
			and entry.s % 1 == 0
			and finite(entry.m)
			and entry.m >= 0
			and entry.m <= Mutations.Count
			and entry.m % 1 == 0
		then
			table.insert(keep, { s = entry.s, m = entry.m })
		else
			changed = true
		end
	end
	while #keep > Balance.Release.MeadowKeep do
		table.remove(keep, 1)
		changed = true
	end
	if changed then
		d.released = keep
		fix(ctx, "released")
	end

	-- records par espèce : dense, allongé à Species.List, jamais tronqué
	d.trophies = denseNumbers(ctx, d.trophies, #Species.List, 0, cleanSize, "trophies")
end

-- ---------------------------------------------------------------------------------------------
-- Squishydex, accueil, objectifs, autres clés
-- ---------------------------------------------------------------------------------------------

local function repairQuest(ctx: Ctx, d: { [string]: any })
	local dex = d.dex
	dex.mut = denseNumbers(ctx, dex.mut, #Species.List, 0, cleanMask, "dex.mut")
	dex.stars = denseNumbers(ctx, dex.stars, #Species.List, 0, function(x: any): (boolean, number)
		return intIn(x, 0, 31, 0)
	end, "dex.stars")
	-- bonus de famille gagnés pour toujours (contrat v1.2) : 0 / 1, une case par famille
	dex.fam = denseNumbers(ctx, dex.fam, #Species.FamilyOrder, 0, cleanFam, "dex.fam")
	intField(ctx, dex, "rewards", 0, 1e9, "dex.rewards")

	intField(ctx, d, "plopDays", 0, 1e9, "plopDays")
	intField(ctx, d, "lastFeedDay", 0, 1e9, "lastFeedDay")

	local onboarding = d.onboarding
	intField(ctx, onboarding, "step", 0, MAX_STEP, "onboarding.step")
	boolField(ctx, onboarding, "done", false, "onboarding.done")
	boolField(ctx, onboarding, "demoDone", false, "onboarding.demoDone")

	-- objectifs du jour : liste dense d'au plus PerDay entrées lisibles ; sinon redessinés (day = 0)
	local objectives = d.objectives
	local list = objectives.list
	local okList = type(list) == "table" and isDense(list) and #list <= Quests.ObjectiveRules.PerDay
	if okList then
		for _, e in list do
			if
				type(e) ~= "table"
				or not finite(e.id)
				or not finite(e.p)
				or type(e.done) ~= "boolean"
				or type(e.claimed) ~= "boolean"
			then
				okList = false
				break
			end
		end
	end
	if not okList then
		objectives.list = {}
		objectives.day = 0
		fix(ctx, "objectives.list")
	end
	intField(ctx, objectives, "day", 0, 1e9, "objectives.day")
	intField(ctx, objectives, "rerolls", 0, 1e9, "objectives.rerolls")

	for key, value in d.stats do
		if type(value) == "number" and (not finite(value) or value < 0) then
			d.stats[key] = 0
			fix(ctx, "stats." .. tostring(key))
		end
	end
end

local function repairOthers(ctx: Ctx, d: { [string]: any }, version: number)
	-- séance de Jelly Moon de la dernière Goutte de Lune (contrat v1.2)
	intField(ctx, d.moon, "lastSession", 0, MAX_INT, "moon.lastSession")
	intField(ctx, d.golden, "lastWinAt", 0, MAX_INT, "golden.lastWinAt")
	intField(ctx, d.mode, "changedAt", 0, MAX_INT, "mode.changedAt")
	intField(ctx, d.flags, "strikes", 0, 1e9, "flags.strikes")
	intField(ctx, d.flags, "lbBanUntil", 0, MAX_INT, "flags.lbBanUntil")
	if d.flags.lbBanned ~= false then
		d.flags.lbBanned = false -- champ du socle, jamais vrai
		fix(ctx, "flags.lbBanned")
	end
	-- réglages : valeur d'une chaîne dans sa liste (réglage de cette version du profil seulement :
	-- `since` ≤ version, lot A4 ; jamais un réglage v2 écrit dans un profil v1)
	for key, def in SettingsConfig do
		if def.saved and def.kind == "string" and def.values and (def.since or 1) <= version then
			local v = d.settings[key]
			if type(v) ~= "string" or not def.values[v] then
				d.settings[key] = def.default
				fix(ctx, "settings." .. key)
			end
		end
	end
	-- passes : seulement des clés chaînes à true (MonetizationService revérifie à l'arrivée)
	local changed = false
	local clean = {}
	for key, owned in d.passes do
		if type(key) == "string" and owned == true then
			clean[key] = true
		else
			changed = true
		end
	end
	if changed then
		d.passes = clean
		fix(ctx, "passes")
	end
	for key, value in d.weekly do
		if type(value) == "number" and (not finite(value) or value < 0) then
			d.weekly[key] = 0
			fix(ctx, "weekly." .. tostring(key))
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Schéma v2 (docs/04 §27.2) : profils de version ≥ 2 seulement
-- ---------------------------------------------------------------------------------------------

-- Entrées d'une liste dans l'ordre de ses index entiers valides (une liste à trous ou mixte, écrite
-- par un vieux bug, garde ses entrées lisibles ; les clés étrangères sont laissées de côté)
local function listEntries(list: any): { any }
	if type(list) ~= "table" then
		return {}
	end
	if isDense(list) then
		return list
	end
	local idx = {}
	for k in list do
		if type(k) == "number" and k >= 1 and k % 1 == 0 and k <= MAX_DENSE then
			table.insert(idx, k)
		end
	end
	table.sort(idx)
	local out = {}
	for _, k in idx do
		table.insert(out, list[k])
	end
	return out
end

-- Mot d'un ensemble de bits : entier de [0 ; 2^32[, sinon 0 (même règle que Logic/Bitset : un mot
-- abîmé ne donne jamais un bit)
local function cleanWord(x: any): (boolean, number)
	if type(x) == "number" and x == x and x >= 0 and x <= WORD_MAX and x % 1 == 0 then
		return true, x
	end
	return false, 0
end

-- Ensemble de bits de n éléments : dense, allongé à ceil(n / 32) mots (au moins 1), jamais tronqué
-- en deçà de Bitset.MaxBits (un bit au-delà de n peut être celui d'une espèce ou d'une ligne future)
local function bitsetField(ctx: Ctx, value: any, n: number, path: string): { number }
	local out = denseNumbers(ctx, value, math.max(1, math.ceil(n / 32)), 0, cleanWord, path)
	if #out > BITSET_MAX_WORDS then
		for i = #out, BITSET_MAX_WORDS + 1, -1 do
			out[i] = nil
		end
		fix(ctx, path)
	end
	return out
end

-- Tableau dense de EXACTEMENT n entiers de [0 ; hi] (Atelier : une case par ligne ; décorations
-- dorées : une par décoration ; emplacements de Déco perso : 12)
local function fixedInts(ctx: Ctx, value: any, n: number, hi: number, path: string): { number }
	local out = denseNumbers(ctx, value, n, 0, function(x: any): (boolean, number)
		return intIn(x, 0, hi, 0)
	end, path)
	if #out > n then
		for i = #out, n + 1, -1 do
			out[i] = nil
		end
		fix(ctx, path)
	end
	return out
end

-- Pose le niveau d'une ligne achetable (plafond dépassé) ; « Pour le plaisir » : bits au-delà retirés
local function setLevel(d: { [string]: any }, id: string, level: number)
	local slot = LEVEL_SLOTS[id]
	if slot == nil then
		return
	end
	if slot.tile then
		local tiles = d.tiles
		tiles[slot.tile] = if type(tiles[slot.tile]) == "boolean" then level >= 1 else level
	elseif slot.row then
		d.atelier[slot.row] = level
	elseif slot.firstBit and slot.bits then
		local kept = 0
		for i = slot.firstBit, slot.firstBit + slot.bits - 1 do
			if Bitset.has(d.atelierCosmetics, i) then
				kept += 1
				if kept > level then
					Bitset.clear(d.atelierCosmetics, i)
				end
			end
		end
	end
end

-- Valeurs lues AVANT la forme (qui remplace une valeur illisible par sa valeur par défaut, 0) : pour
-- ces champs, la valeur sûre d'une valeur illisible n'est pas 0
type RawV2 = { regainBonusA: any, unlocksSeen: any }

-- Progression, Confettis, familles nouvelles, Atelier : avant les règles de la v1 qui en dépendent
local function repairProgressionV2(ctx: Ctx, d: { [string]: any }, raw: RawV2)
	-- version : entier ≥ 2 (2,5 n'est ni v2 ni v3 : Logic/Invariants le lirait comme une v1)
	intField(ctx, d, "version", 2, MAX_INT, "version")
	local R = Prestige.r(d) -- déjà réparé : entier de [0 ; MaxR]
	-- Record R : entier de [r ; MaxR] (bestR = max(bestR, r)) ; illisible → r
	local okBest, best = intIn(d.bestR, R, MAX_R, R)
	if not okBest then
		d.bestR = best
		fix(ctx, "bestR")
	end
	intField(ctx, d, "ascend", 0, MAX_A, "ascend")
	local A = Prestige.ascend(d)
	-- bonus de retour au record déjà donné pour A : ≤ A ; illisible → A (jamais donné deux fois)
	local okRegain, regain = intIn(if finite(raw.regainBonusA) then d.regainBonusA else nil, 0, A, A)
	if not okRegain then
		d.regainBonusA = regain
		fix(ctx, "regainBonusA")
	end
	-- Record R du dernier retour (décision INT-A1-MEMORY) : entier de [0 ; bestR] ; illisible,
	-- négatif ou au-delà du Record R → 0 (une valeur ramenée à bestR donnerait un × 1,25 de trop)
	local memoryR = d.memoryR
	if not finite(memoryR) or memoryR < 0 or memoryR > best then
		d.memoryR = 0
		fix(ctx, "memoryR")
	elseif memoryR % 1 ~= 0 then
		d.memoryR = math.floor(memoryR)
		fix(ctx, "memoryR")
	end
	-- Confettis : entiers de 0 à 1e9 ; en poche ≤ total gagné (le total, compteur qui ne baisse
	-- jamais, est relevé : jamais un Confetti de poche perdu)
	intField(ctx, d, "confetti", 0, CONFETTI_MAX, "confetti")
	intField(ctx, d, "confettiTotal", 0, CONFETTI_MAX, "confettiTotal")
	if d.confettiTotal < d.confetti then
		d.confettiTotal = d.confetti
		fix(ctx, "confettiTotal")
	end
	-- familles nouvelles
	local tiles = d.tiles
	for _, pair in NEW_TILES do
		intField(ctx, tiles, pair[1], 0, pair[2], "tiles." .. pair[1])
	end
	-- Atelier : une case par ligne (ordre définitif), allongé ou raccourci, chaque case ≤ #costs
	local rows = Upgrades.WorkshopRows
	local atelier = fixedInts(ctx, d.atelier, #rows, 1e9, "atelier")
	for i, row in rows do
		local ok, v = intIn(atelier[i], 0, #row.costs, 0)
		if not ok then
			atelier[i] = v
			fix(ctx, "atelier." .. row.id)
		end
	end
	d.atelier = atelier
	d.atelierCosmetics = bitsetField(ctx, d.atelierCosmetics, Upgrades.CosmeticBits, "atelierCosmetics")
	-- chaque niveau ≤ son plafond (ouverture par le Record R ou A, plafond de la boucle) : un niveau
	-- au-delà n'a jamais pu être acheté (Record R et A ne baissent jamais)
	for _, id in UpgradeMath.ids() do
		local cap = UpgradeMath.cap(id, d, ALL_FLAGS)
		if UpgradeMath.level(id, d) > cap then
			setLevel(d, id, cap)
			fix(ctx, id .. ".cap")
		end
	end
	-- décorations dorées : 18 entiers de 0 à 10
	d.decorBuilds = fixedInts(ctx, d.decorBuilds, DECOR_BUILDS, DECOR_BUILDS_MAX, "decorBuilds")
end

-- Piste, Carnet, maîtrise, Déco perso, cœurs, plafonds v2, habillage
local function repairOthersV2(ctx: Ctx, d: { [string]: any }, raw: RawV2)
	local best = Prestige.bestR(d)
	intField(ctx, d.stats, "upgradesBought", 0, 1e12, "stats.upgradesBought")
	intField(ctx, d.stats, "petitSplorches", 0, 1e12, "stats.petitSplorches")
	-- lot A4 : objectifs du jour réclamés, pistes de la semaine finies, Jelly Moon jouées
	intField(ctx, d.stats, "objectivesClaimed", 0, 1e12, "stats.objectivesClaimed")
	intField(ctx, d.stats, "tracksDone", 0, 1e12, "stats.tracksDone")
	intField(ctx, d.moon, "sessions", 0, 1e9, "moon.sessions")
	-- cartes « Nouveau » déjà vues : ≤ Record R ; illisible ou négatif → Record R (jamais une pluie
	-- de cartes déjà montrées)
	local seen = if finite(raw.unlocksSeen) then d.unlocksSeen else nil
	if not finite(seen) or seen < 0 then
		d.unlocksSeen = best
		fix(ctx, "unlocksSeen")
	else
		intField(ctx, d, "unlocksSeen", 0, best, "unlocksSeen")
	end
	d.carnet = bitsetField(ctx, d.carnet, CARNET_TIERS, "carnet")
	d.mastery = bitsetField(ctx, d.mastery, #Species.List, "mastery")

	-- piste de la semaine
	local track = d.weeklyTrack
	intField(ctx, track, "period", 0, 1e9, "weeklyTrack.period")
	intField(ctx, track, "points", 0, 1e6, "weeklyTrack.points")
	intField(ctx, track, "firstPeriodEnd", 0, MAX_INT, "weeklyTrack.firstPeriodEnd")
	track.claimed = bitsetField(ctx, track.claimed, TRACK_TIERS, "weeklyTrack.claimed")
	-- lot A4 : cosmétiques de la semaine gagnés (bit i = Cosmetics.WeeklyRotation[i]) ; secondes de jeu
	-- des 7 derniers jours UTC (exactement 7 cases de 0 à 86 400) et jour de la dernière case écrite
	track.won = bitsetField(ctx, track.won, WEEKLY_COSMETICS, "weeklyTrack.won")
	track.play = fixedInts(ctx, track.play, PLAY_DAYS, DAY_SECONDS, "weeklyTrack.play")
	intField(ctx, track, "playDay", 0, 1e9, "weeklyTrack.playDay")
	-- Défis : liste dense d'au plus 3 entrées { id, p, done }, chaque Défi une fois ; une entrée
	-- illisible (id inconnu, doublon) est retirée, p et done réparés en place
	local list = track.challenges
	local entries = listEntries(list)
	local changed = not isDense(list)
	local keep: { any } = {}
	local ids: { [number]: boolean } = {}
	for _, entry in entries do
		local id = if type(entry) == "table" then entry.id else nil
		if
			#keep >= CHALLENGES_MAX
			or not finite(id)
			or id < 1
			or id > #Quests.Challenges
			or id % 1 ~= 0
			or ids[id]
		then
			changed = true
			continue
		end
		ids[id] = true
		local okP, p = intIn(entry.p, 0, 1e9, 0)
		if not okP then
			entry.p = p
			changed = true
		end
		if type(entry.done) ~= "boolean" then
			entry.done = false
			changed = true
		end
		table.insert(keep, entry)
	end
	if changed then
		track.challenges = keep
		fix(ctx, "weeklyTrack.challenges")
	end

	-- accueil, saison, plafonds du jour v2
	boolField(ctx, d.onboarding, "nextBuyShown", false, "onboarding.nextBuyShown")
	boolField(ctx, d.onboarding, "welcomeV2Pending", false, "onboarding.welcomeV2Pending")
	intField(ctx, d.season, "frostDays", 0, 1e9, "season.frostDays")
	for _, key in CAPS_V2 do
		intField(ctx, d.caps, key, 0, (Balance.CapsV2 :: any)[key], "caps." .. key)
	end

	-- Déco perso : objets possédés (64 bits) ; 12 emplacements vers un objet possédé, chacun une fois
	local deco = d.decoPerso
	deco.owned = bitsetField(ctx, deco.owned, DECO_OWNED_BITS, "decoPerso.owned")
	local slots = fixedInts(ctx, deco.slots, DECO_SLOTS, 1e9, "decoPerso.slots")
	local placed: { [number]: boolean } = {}
	for i = 1, DECO_SLOTS do
		local item = slots[i]
		if item > 0 then
			-- objet inconnu, non possédé, déjà posé ou d'une autre taille que l'emplacement (lot A4)
			if
				item > DECO_ITEMS
				or not Bitset.has(deco.owned, item)
				or placed[item]
				or Cosmetics.DecoPerso[item].size ~= Cosmetics.DecoSlots[i]
			then
				slots[i] = 0
				fix(ctx, "decoPerso.slots." .. i)
			else
				placed[item] = true
			end
		end
	end
	deco.slots = slots

	-- cœurs : jour UTC, total reçu ; receveurs du jour : UserIds entiers, chacun une fois, 20 au plus
	local hearts = d.hearts
	intField(ctx, hearts, "givenDay", 0, 1e9, "hearts.givenDay")
	intField(ctx, hearts, "receivedTotal", 0, 1e12, "hearts.receivedTotal")
	local given = hearts.givenTo
	local okGiven = isDense(given)
	local cleanGiven: { number } = {}
	local seenIds: { [number]: boolean } = {}
	for _, userId in listEntries(given) do
		if
			#cleanGiven < HEARTS_GIVEN_MAX
			and finite(userId)
			and userId % 1 == 0
			and userId >= -1e15
			and userId <= 1e15
			and not seenIds[userId]
		then
			seenIds[userId] = true
			table.insert(cleanGiven, userId)
		else
			okGiven = false
		end
	end
	if not okGiven then
		hearts.givenTo = cleanGiven
		fix(ctx, "hearts.givenTo")
	end

	-- habillage du ranch (cosmetics.theme) : connu et gagné, sinon « color » (le seul gratuit).
	-- Conditions lisibles dans le profil seulement (Record R, A, Squishydex, jours de Plop) ; une
	-- autre source n'est jamais retirée ici (MonetizationService et CommunityService revérifient)
	local cosmetics = d.cosmetics
	local source = THEMES[cosmetics.theme]
	local earned = source ~= nil
	if source ~= nil and type(source) == "table" then
		local value = if finite(source.value) then source.value else math.huge
		if source.kind == "recordR" then
			earned = best >= value
		elseif source.kind == "ascend" then
			earned = Prestige.ascend(d) >= value
		elseif source.kind == "dex" then
			earned = finite(d.dex.rewards) and d.dex.rewards >= value
		elseif source.kind == "plopDay" then
			earned = finite(d.plopDays) and d.plopDays >= value
		end
	end
	if not earned then
		cosmetics.theme = "color"
		fix(ctx, "cosmetics.theme")
	end
	-- lot A4 : palette et coussins choisis : identifiant connu ou "" (ceux du ranch) ; la possession
	-- est revérifiée par CommunityService à l'équipement
	if cosmetics.palette ~= "" and not PALETTES[cosmetics.palette] then
		cosmetics.palette = ""
		fix(ctx, "cosmetics.palette")
	end
	if cosmetics.cushions ~= "" and not CUSHIONS[cosmetics.cushions] then
		cosmetics.cushions = ""
		fix(ctx, "cosmetics.cushions")
	end
	-- réglage « Montrer mon halo » (Config/Settings since = 2) : booléen, sinon vrai (la forme du
	-- modèle v2 l'a déjà remis ; règle redite pour un modèle enveloppé par les specs)
	boolField(ctx, d.settings, "haloOn", true, "settings.haloOn")
end

-- Répare en place ; rend la liste des champs réparés (vide = sain)
function ProfileRepair.repair(data: { [string]: any }): { string }
	local ctx: Ctx = { fixes = {}, seen = {} }
	if type(data) ~= "table" then
		return { "profile" }
	end
	local d: { [string]: any } = data
	-- version du profil (pas celle du serveur) : v2 seulement pour un profil v2 ; un profil v1 garde
	-- le modèle d'aujourd'hui (Schema.defaults, que Bots.extendSchema peut envelopper)
	local v2 = type(d.version) == "number" and d.version >= 2
	local template = if v2 == (Schema.VERSION >= 2)
		then Schema.defaults()
		else Schema.defaultsFor(if v2 then 2 else 1)
	local raw: RawV2 = { regainBonusA = d.regainBonusA, unlocksSeen = d.unlocksSeen }
	-- forme : types de chaque clé du schéma (clés héritées inconnues ignorées)
	shape(ctx, d, template, "")
	repairEconomy(ctx, d, v2)
	if v2 then
		repairProgressionV2(ctx, d, raw)
	end
	repairQuest(ctx, d)
	repairSquishies(ctx, d, v2)
	repairOthers(ctx, d, if v2 then d.version else 1)
	if v2 then
		repairOthersV2(ctx, d, raw)
	end
	return ctx.fixes
end

return ProfileRepair
