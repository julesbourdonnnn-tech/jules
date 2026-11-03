--!strict
-- Invariants (paquet logic, docs/04 §8.5, §12.1, §17.2). Invariants d'un profil, purs (zéro bug,
-- couche c du GDD §12.10) : vérifiés à chaque tick du robot de longue durée (tests/harness/Soak),
-- après chaque mutation en Studio, et dans les specs. Rendent la liste des violations (vide = sain),
-- chacune nommée comme un chemin du profil (« coins », « squishies.<uid>.z », « capacity.pen »…) ;
-- ne réparent jamais (c'est le rôle de Server/Data/ProfileRepair).
-- Profil v2 (lot A1, docs/04 §27.2 ; version ≥ 2, schéma derrière l'interrupteur figé SchemaV2) :
-- en plus, bornes de chaque champ v2 (R ≤ bestR ≤ MaxR, A ≤ MaxA, Confettis, niveaux, Atelier,
-- ensembles de bits, piste, Déco perso, cœurs, plafonds v2), chaque niveau ≤ son plafond
-- (UpgradeMath.cap, tous interrupteurs ouverts : un niveau acheté reste valable si LiveOps coupe sa
-- famille), Tapis Étoilé ≤ plafond de la boucle. Juste après un prestige : afterPrestige (toutes
-- les tailles à 1, décorations gardées ≤ 12, dalles de la boucle à zéro). Un profil v1 garde
-- EXACTEMENT les invariants de la v1.3.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table, bit32 = type, math, string, table, bit32

local Balance = require(script.Parent.Parent.Config.Balance)
local Species = require(script.Parent.Parent.Config.Species)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Quests = require(script.Parent.Parent.Config.Quests)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
local Formulas = require(script.Parent.Formulas)
local QuestRules = require(script.Parent.QuestRules)
local Prestige = require(script.Parent.Prestige)
local UpgradeMath = require(script.Parent.UpgradeMath)

local Invariants = {}

local MAX = Balance.Numbers.Max
local LOCATIONS = { pen = true, pool = true, dodo = true, mail = true }
local MAX_POOL = Balance.Fusion.PoolSlots + 1 -- famille Axolo comprise
local MAX_BF = #Balance.Splorch.BestFriendSlotsAt

-- Bornes du schéma v2 (docs/04 §27.2 ; mêmes nombres que Data/Schema.defaultsFor(2))
local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local CONFETTI_MAX = Balance.Confetti.Max
local WORD_MAX = 4294967295 -- mot de 32 bits (Logic/Bitset)
local BITSET_MAX_WORDS = 128 -- Logic/Bitset.MaxBits (4 096) ÷ 32
local DECOR_BUILDS = Balance.Tiles.decor.Levels -- une case par décoration (18)
local DECOR_BUILDS_MAX = 10 -- constructions dorées par décoration
local DECO_OWNED_BITS = 64
local DECO_SLOTS = 12
local DECO_ITEMS = #Cosmetics.DecoPerso
local HEARTS_GIVEN_MAX = Balance.Hearts.PerDay
local CHALLENGES_MAX = Quests.WeeklyTrack.ChallengesPerWeek
local TRACK_TIERS = #Quests.WeeklyTrack.Tiers
local CARNET_TIERS = #Quests.Carnet.Tiers
-- Plafonds des niveaux : tous les interrupteurs ouverts (structure du profil, pas l'état du jour)
local ALL_FLAGS = {
	get = function(_key: string): boolean
		return true
	end,
}

-- Nombre fini dans [min ; max]
function Invariants.number(x: any, min: number, max: number): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge and x >= min and x <= max
end

local function int(x: any, min: number, max: number): boolean
	return Invariants.number(x, min, max) and x % 1 == 0
end

-- Tableau séquentiel sans trou
function Invariants.dense(t: any): boolean
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

-- uid valide (base 36, 1 à 8 caractères)
function Invariants.uid(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= 8 and string.match(x, "^[0-9a-z]+$") ~= nil
end

-- Pièces, Pot, Fame, tailles finies et bornées ; places ≤ capacités (24 / 60 / 20) ; un squishy par
-- emplacement de Meilleur Ami ; tenues portées (dérivées de squishies[uid].o) ≤ possédées ; tableaux
-- denses ; niveaux bornés. Contrat v1.2 (docs/04 §17.2) : outfits.worn absent ou vide (obsolète),
-- dex.fam dense en 0 / 1, caps.petSitBy[UserId] entier dans [0 ; CapsPerFriend.petSit], gd entier ≥ 0.
function Invariants.profile(data: { [string]: any }): { string }
	local out: { string } = {}
	local function bad(path: string)
		table.insert(out, path)
	end
	if type(data) ~= "table" then
		bad("profile")
		return out
	end
	local d: any = data

	-- économie
	if not Invariants.number(d.coins, 0, MAX) then
		bad("coins")
	elseif d.coins < Balance.Numbers.ExactBelow and d.coins % 1 ~= 0 then
		bad("coins.integer")
	end
	if not Invariants.number(d.pot, 0, MAX) then
		bad("pot")
	end
	if not Invariants.number(d.fame, 0, MAX) then
		bad("fame")
	end
	-- r de la boucle : la SEULE lecture du champ (Static_PrestigeOnly) ; v2 : borné à MaxR
	local v2 = int(d.version, 2, math.huge)
	local R = d.R
	if not int(R, 0, if v2 then MAX_R else 1e6) then
		bad("R")
	end
	if type(d.growth) ~= "table" then
		bad("growth")
	else
		if not Invariants.number(d.growth.G, 0, MAX) then
			bad("growth.G")
		end
		if not Invariants.number(d.growth.g, 0, MAX) then
			bad("growth.g")
		end
		if not Invariants.number(d.growth.t, -MAX, MAX) then
			bad("growth.t")
		end
	end
	if type(d.tiles) ~= "table" then
		bad("tiles")
	else
		for _, key in { "snack", "decor", "pens" } do
			if not int(d.tiles[key], 0, Balance.Tiles[key].Levels) then
				bad("tiles." .. key)
			end
		end
		if type(d.tiles.cozyBed) ~= "boolean" then
			bad("tiles.cozyBed")
		end
		if not int(d.tiles.seen, 0, 4294967295) then
			bad("tiles.seen")
		end
	end
	if type(d.boosts) ~= "table" or not Invariants.number(d.boosts.personalLeft, 0, MAX) then
		bad("boosts.personalLeft")
	end
	if type(d.caps) ~= "table" then
		bad("caps")
	else
		-- chaque compteur scalaire de Balance.Caps (petSitIn et splorchCoins compris, contrat v1.2)
		for key, cap in Balance.Caps do
			if not Invariants.number(d.caps[key], 0, cap) then
				bad("caps." .. key)
			end
		end
		-- plafond par ami : petSitBy[tostring(UserId du propriétaire)] = entier dans [0 ; CapsPerFriend]
		local by = d.caps.petSitBy
		if type(by) ~= "table" then
			bad("caps.petSitBy")
		else
			for key, count in by do
				local okKey = type(key) == "string" and string.match(key, "^%-?%d+$") ~= nil
				if not okKey or not int(count, 0, Balance.CapsPerFriend.petSit) then
					bad("caps.petSitBy." .. tostring(key))
				end
			end
		end
	end
	if not Invariants.number(d.biggestEver, 0, MAX) then
		bad("biggestEver")
	end
	if not int(d.plopDays, 0, 1e9) then
		bad("plopDays")
	end

	-- collection
	local squishies = d.squishies
	local counts = { pen = 0, pool = 0, dodo = 0, mail = 0 }
	local bfSlots: { [number]: string } = {}
	if type(squishies) ~= "table" then
		bad("squishies")
		squishies = {}
	end
	local nextUid = d.nextUid
	if not int(nextUid, 1, 2 ^ 41) then
		bad("nextUid")
		nextUid = math.huge
	end
	for uid, rec in squishies do
		local path = "squishies." .. tostring(uid)
		if not Invariants.uid(uid) then
			bad(path .. ".uid")
		elseif (tonumber(uid, 36) or math.huge) >= nextUid then
			bad(path .. ".nextUid")
		end
		if type(rec) ~= "table" then
			bad(path)
			continue
		end
		if Species.ById[rec.s] == nil then
			bad(path .. ".s")
		end
		if not int(rec.m, 0, Mutations.Count) then
			bad(path .. ".m")
		end
		if not int(rec.st, 0, Balance.Fusion.MaxStars) then
			bad(path .. ".st")
		end
		if not Invariants.number(rec.z, 1, MAX) then
			bad(path .. ".z")
		end
		if not Invariants.number(rec.zg, 0, MAX) then
			bad(path .. ".zg")
		end
		if not int(rec.bf, 0, MAX_BF) then
			bad(path .. ".bf")
		elseif rec.bf > 0 then
			if bfSlots[rec.bf] ~= nil then
				bad("bestFriend." .. tostring(rec.bf))
			end
			bfSlots[rec.bf] = tostring(uid)
		end
		if type(rec.lk) ~= "boolean" then
			bad(path .. ".lk")
		end
		if type(rec.o) ~= "string" then
			bad(path .. ".o")
		end
		if not LOCATIONS[rec.at] then
			bad(path .. ".at")
		else
			counts[rec.at] += 1
		end
		if not Invariants.number(rec.b, 0, MAX) then
			bad(path .. ".b")
		end
		-- jour UTC du dernier bonus de croissance du Rush (0 = jamais, contrat v1.2)
		if not int(rec.gd, 0, 1e9) then
			bad(path .. ".gd")
		end
	end
	-- capacités DU JOUEUR (§17.2 n° 3) : enclos + Bassin ≤ penCapacity(dalle Enclos, Grand Ranch), Bassin
	-- ≤ poolSlots(bonus Axolo gagné) ; jamais au-delà des plafonds absolus (24, 6)
	local pensLevel = if type(d.tiles) == "table" then d.tiles.pens else 0
	local bigRanch = type(d.passes) == "table" and d.passes.BigRanch == true
	local penCap = math.min(Balance.Pens.Max, Formulas.penCapacity(pensLevel, bigRanch))
	local poolCap = math.min(MAX_POOL, Formulas.poolSlots(QuestRules.familyEarned(d.dex, "axolo")))
	if counts.pen + counts.pool > penCap then
		bad("capacity.pen")
	end
	if counts.pool > poolCap then
		bad("capacity.pool")
	end
	if counts.dodo > Balance.Pens.Dodo then
		bad("capacity.dodo")
	end
	if counts.mail > Balance.Pens.Mail then
		bad("capacity.mail")
	end
	if type(d.mount) ~= "string" or (d.mount ~= "" and type(squishies[d.mount]) ~= "table") then
		bad("mount")
	end

	-- tenues (contrat v1.2, GDD §12.6) : la tenue portée n'est gardée QUE dans squishies[uid].o ;
	-- porteurs d'une tenue (squishies dont o == id) ≤ owned[id] ; outfits.worn est obsolète : absent ou
	-- vide (Schema le garde à {}, ProfileRepair le vide)
	local outfits = d.outfits
	if type(outfits) ~= "table" or type(outfits.owned) ~= "table" then
		bad("outfits")
	else
		for id, count in outfits.owned do
			if type(id) ~= "string" or not int(count, 0, 1e9) then
				bad("outfits.owned." .. tostring(id))
			end
		end
		if outfits.worn ~= nil and (type(outfits.worn) ~= "table" or next(outfits.worn) ~= nil) then
			bad("outfits.worn")
		end
		local wearers: { [string]: number } = {}
		for _, rec in squishies do
			if type(rec) == "table" and type(rec.o) == "string" and rec.o ~= "" then
				wearers[rec.o] = (wearers[rec.o] or 0) + 1
			end
		end
		for id, n in wearers do
			local owned = outfits.owned[id]
			if n > (if int(owned, 0, 1e9) then owned else 0) then
				bad("outfits.owned." .. id .. ".count")
			end
		end
	end

	-- tableaux denses, une case par espèce
	local function denseSpecies(t: any, path: string)
		if not Invariants.dense(t) or #t < #Species.List then
			bad(path)
		end
	end
	denseSpecies(d.trophies, "trophies")
	if type(d.dex) ~= "table" then
		bad("dex")
	else
		denseSpecies(d.dex.mut, "dex.mut")
		denseSpecies(d.dex.stars, "dex.stars")
		-- bonus de famille gagnés pour toujours (contrat v1.2) : une case 0 / 1 par famille de FamilyOrder
		local fam = d.dex.fam
		local okFam = Invariants.dense(fam) and #fam >= #Species.FamilyOrder
		if okFam then
			for _, v in fam do
				if v ~= 0 and v ~= 1 then
					okFam = false
					break
				end
			end
		end
		if not okFam then
			bad("dex.fam")
		end
	end
	if
		type(d.released) ~= "table"
		or not Invariants.dense(d.released)
		or #d.released > Balance.Release.MeadowKeep
	then
		bad("released")
	end
	if type(d.vat) ~= "table" then
		bad("vat")
	else
		if not int(d.vat.pityRare, 0, 1e9) then
			bad("vat.pityRare")
		end
		if not int(d.vat.pityEpic, 0, 1e9) then
			bad("vat.pityEpic")
		end
		if not int(d.vat.newPulls, 0, Balance.Vat.NewPulls) then
			bad("vat.newPulls")
		end
	end
	if type(d.objectives) == "table" then
		local list = d.objectives.list
		if not Invariants.dense(list) or #list > Quests.ObjectiveRules.PerDay then
			bad("objectives.list")
		end
	end
	if v2 then
		Invariants.profileV2(d, if int(R, 0, MAX_R) then R else 0, bad)
	end
	return out
end

-- Ensemble de bits sain (Logic/Bitset) : tableau dense de mots entiers de 32 bits, au moins
-- ceil(n / 32) mots (et au moins 1), jamais plus que Bitset.MaxBits
function Invariants.bitset(t: any, n: number): boolean
	if not Invariants.dense(t) or #t < math.max(1, math.ceil(n / 32)) or #t > BITSET_MAX_WORDS then
		return false
	end
	for _, w in t do
		if not int(w, 0, WORD_MAX) then
			return false
		end
	end
	return true
end

-- Bit i (à partir de 1) d'un ensemble déjà vérifié
local function bitOf(t: { number }, i: number): boolean
	local w = t[(i - 1) // 32 + 1]
	return type(w) == "number" and bit32.btest(w, bit32.lshift(1, (i - 1) % 32))
end

-- Champs du schéma v2 (docs/04 §27.2) ; R = r déjà vérifié (0 si illisible)
function Invariants.profileV2(d: any, R: number, bad: (string) -> ())
	-- progression : R ≤ bestR ≤ MaxR, 0 ≤ ascend ≤ MaxA, bonus de retour ≤ A
	local bestR = d.bestR
	if not int(bestR, R, MAX_R) then
		bad("bestR")
		bestR = R
	end
	local A = d.ascend
	if not int(A, 0, MAX_A) then
		bad("ascend")
		A = 0
	end
	if not int(d.regainBonusA, 0, A) then
		bad("regainBonusA")
	end
	-- Confettis : entiers de 0 à 1e9, en poche ≤ total gagné
	local okConf = int(d.confetti, 0, CONFETTI_MAX)
	local okTotal = int(d.confettiTotal, 0, CONFETTI_MAX)
	if not okConf then
		bad("confetti")
	end
	if not okTotal then
		bad("confettiTotal")
	end
	if okConf and okTotal and d.confetti > d.confettiTotal then
		bad("confetti.total")
	end
	-- familles nouvelles : bornes, Tapis Étoilé seulement après le Tapis 12 et sous le plafond de r
	local tiles = d.tiles
	if type(tiles) == "table" then
		local bounds = {
			star = Balance.UpgradePrices.star.Levels,
			gloves = Balance.UpgradePrices.gloves.Levels,
			school = Balance.UpgradePrices.school.Levels,
			monuments = Balance.UpgradePrices.monument.Levels,
		}
		for key, max in bounds do
			if not int(tiles[key], 0, max) then
				bad("tiles." .. key)
			end
		end
		if int(tiles.star, 1, math.huge) then
			if tiles.snack ~= Balance.Tiles.snack.Levels then
				bad("tiles.star.snack")
			end
			if tiles.star > Prestige.starCap(R) then
				bad("tiles.star.loopCap")
			end
		end
	end
	-- Atelier : une case par ligne de WorkshopRows, chacune ≤ son nombre de niveaux
	local atelier = d.atelier
	if not Invariants.dense(atelier) or #atelier ~= #Upgrades.WorkshopRows then
		bad("atelier")
	else
		for i, row in Upgrades.WorkshopRows do
			if not int(atelier[i], 0, #row.costs) then
				bad("atelier." .. row.id)
			end
		end
	end
	-- chaque niveau ≤ son plafond (ouverture par le Record R ou A, plafond de la boucle)
	if
		type(tiles) == "table"
		and Invariants.dense(atelier)
		and Invariants.bitset(d.atelierCosmetics, Upgrades.CosmeticBits)
	then
		for _, id in UpgradeMath.ids() do
			if UpgradeMath.level(id, d) > UpgradeMath.cap(id, d, ALL_FLAGS) then
				-- « <id>.cap » (jamais un préfixe de clé de texte : TextFitKeys lit src/shared/Logic)
				bad(id .. ".cap")
			end
		end
	end
	-- ensembles de bits
	if not Invariants.bitset(d.atelierCosmetics, Upgrades.CosmeticBits) then
		bad("atelierCosmetics")
	end
	if not Invariants.bitset(d.carnet, CARNET_TIERS) then
		bad("carnet")
	end
	if not Invariants.bitset(d.mastery, #Species.List) then
		bad("mastery")
	end
	-- décorations dorées : 18 entiers de 0 à 10
	local builds = d.decorBuilds
	if not Invariants.dense(builds) or #builds ~= DECOR_BUILDS then
		bad("decorBuilds")
	else
		for i = 1, DECOR_BUILDS do
			if not int(builds[i], 0, DECOR_BUILDS_MAX) then
				bad("decorBuilds." .. i)
			end
		end
	end
	-- statistiques, Carnet, cartes « Nouveau » (≤ Record R)
	local stats = d.stats
	if type(stats) ~= "table" then
		bad("stats")
	else
		if not int(stats.upgradesBought, 0, 1e12) then
			bad("stats.upgradesBought")
		end
		if not int(stats.petitSplorches, 0, 1e12) then
			bad("stats.petitSplorches")
		end
	end
	if not int(d.unlocksSeen, 0, bestR) then
		bad("unlocksSeen")
	end
	-- piste de la semaine : période, points, paliers réclamés (12), 3 Défis au plus, fin de la 1re
	local track = d.weeklyTrack
	if type(track) ~= "table" then
		bad("weeklyTrack")
	else
		if not int(track.period, 0, 1e9) then
			bad("weeklyTrack.period")
		end
		if not int(track.points, 0, 1e6) then
			bad("weeklyTrack.points")
		end
		if not Invariants.bitset(track.claimed, TRACK_TIERS) then
			bad("weeklyTrack.claimed")
		end
		if not int(track.firstPeriodEnd, 0, 2 ^ 53) then
			bad("weeklyTrack.firstPeriodEnd")
		end
		local list = track.challenges
		if not Invariants.dense(list) or #list > CHALLENGES_MAX then
			bad("weeklyTrack.challenges")
		else
			local ids: { [number]: boolean } = {}
			for i, entry in list do
				local okEntry = type(entry) == "table"
					and int(entry.id, 1, #Quests.Challenges)
					and int(entry.p, 0, 1e9)
					and type(entry.done) == "boolean"
					and not ids[entry.id]
				if not okEntry then
					bad("weeklyTrack.challenges." .. i)
				else
					ids[entry.id] = true
				end
			end
		end
	end
	-- accueil, saison, plafonds du jour v2
	local onboarding = d.onboarding
	if
		type(onboarding) ~= "table"
		or type(onboarding.nextBuyShown) ~= "boolean"
		or type(onboarding.welcomeV2Pending) ~= "boolean"
	then
		bad("onboarding.v2")
	end
	if type(d.season) ~= "table" or not int(d.season.frostDays, 0, 1e9) then
		bad("season.frostDays")
	end
	if type(d.caps) == "table" then
		for key, cap in Balance.CapsV2 do
			if not int(d.caps[key], 0, cap) then
				bad("caps." .. key)
			end
		end
	end
	-- Déco perso : objets possédés (64 bits), 12 emplacements vers un objet possédé, jamais deux fois
	local deco = d.decoPerso
	if type(deco) ~= "table" or not Invariants.bitset(deco.owned, DECO_OWNED_BITS) then
		bad("decoPerso.owned")
	elseif not Invariants.dense(deco.slots) or #deco.slots ~= DECO_SLOTS then
		bad("decoPerso.slots")
	else
		local placed: { [number]: boolean } = {}
		for i, item in deco.slots do
			if not int(item, 0, DECO_ITEMS) then
				bad("decoPerso.slots." .. i)
			elseif item > 0 then
				if not bitOf(deco.owned, item) or placed[item] then
					bad("decoPerso.slots." .. i)
				end
				placed[item] = true
			end
		end
	end
	-- cœurs : jour UTC, 20 receveurs au plus (UserIds entiers, chacun une fois), total reçu
	local hearts = d.hearts
	if type(hearts) ~= "table" then
		bad("hearts")
	else
		if not int(hearts.givenDay, 0, 1e9) then
			bad("hearts.givenDay")
		end
		if not int(hearts.receivedTotal, 0, 1e12) then
			bad("hearts.receivedTotal")
		end
		local given = hearts.givenTo
		if not Invariants.dense(given) or #given > HEARTS_GIVEN_MAX then
			bad("hearts.givenTo")
		else
			local seen: { [number]: boolean } = {}
			for _, userId in given do
				if not int(userId, -1e15, 1e15) or seen[userId] then
					bad("hearts.givenTo")
					break
				end
				seen[userId] = true
			end
		end
	end
end

-- Invariants juste après un prestige (Prestige.apply, docs/04 §27.2) : profil v2 sain, TOUTES les
-- tailles à 1 (enclos, Bassin, Dodo, Lettres, porté), décorations gardées ≤ Prestige.keptDecor
-- (12 au plus), Tapis Étoilé, Gants et École à zéro, Tapis ≤ les niveaux offerts (6 au plus)
function Invariants.afterPrestige(data: { [string]: any }): { string }
	local out = Invariants.profile(data)
	local function bad(path: string)
		table.insert(out, path)
	end
	if type(data) ~= "table" then
		return out
	end
	local d: any = data
	local G = if type(d.growth) == "table" then d.growth.G else nil
	if G ~= 0 then
		bad("prestige.growth.G")
	end
	if type(d.squishies) == "table" then
		for uid, rec in d.squishies do
			if type(rec) == "table" and Formulas.sizeAt(rec, 0) ~= 1 then
				bad("prestige.squishies." .. tostring(uid) .. ".size")
			end
		end
	end
	local tiles = d.tiles
	if type(tiles) == "table" then
		local kept = Prestige.keptDecor(Prestige.bestR(d), d.atelier)
		if not int(tiles.decor, 0, math.min(kept, Balance.SplorchV2.KeptDecorMax)) then
			bad("prestige.tiles.decor")
		end
		for _, key in { "star", "gloves", "school" } do
			if tiles[key] ~= 0 then
				bad("prestige.tiles." .. key)
			end
		end
		if not int(tiles.snack, 0, Balance.SplorchV2.FreeSnackMax) then
			bad("prestige.tiles.snack")
		end
	end
	return out
end

return Invariants
