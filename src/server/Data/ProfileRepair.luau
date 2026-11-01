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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Cosmetics = require(Shared.Config.Cosmetics)
local Quests = require(Shared.Config.Quests)
local SettingsConfig = require(Shared.Config.Settings)
local Formulas = require(Shared.Logic.Formulas)
local QuestRules = require(Shared.Logic.QuestRules)
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

local function repairEconomy(ctx: Ctx, d: { [string]: any })
	-- pièces : finies, ≥ 0, ≤ Max, entières sous ExactBelow
	local coins = d.coins
	local safeCoins = Formulas.clampCoins(coins)
	if not finite(coins) or coins ~= safeCoins then
		d.coins = safeCoins
		fix(ctx, "coins")
	end
	realField(ctx, d, "pot", 0, MAX, "pot")
	realField(ctx, d, "fame", 0, MAX, "fame")
	intField(ctx, d, "R", 0, 1e6, "R")
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

local function repairSquishies(ctx: Ctx, d: { [string]: any })
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
		if type(rec.o) ~= "string" or (rec.o ~= "" and not OUTFITS[rec.o]) then
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

local function repairOthers(ctx: Ctx, d: { [string]: any })
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
	-- réglages : valeur d'une chaîne dans sa liste
	for key, def in SettingsConfig do
		if def.saved and def.kind == "string" and def.values then
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

-- Répare en place ; rend la liste des champs réparés (vide = sain)
function ProfileRepair.repair(data: { [string]: any }): { string }
	local ctx: Ctx = { fixes = {}, seen = {} }
	if type(data) ~= "table" then
		return { "profile" }
	end
	local d: { [string]: any } = data
	-- forme : types de chaque clé du schéma (clés héritées inconnues ignorées)
	shape(ctx, d, Schema.defaults(), "")
	repairEconomy(ctx, d)
	repairQuest(ctx, d)
	repairSquishies(ctx, d)
	repairOthers(ctx, d)
	return ctx.fixes
end

return ProfileRepair
