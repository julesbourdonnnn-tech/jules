--!strict
-- Invariants (paquet logic, docs/04 §8.5, §12.1, §17.2). Invariants d'un profil, purs (zéro bug,
-- couche c du GDD §12.10) : vérifiés à chaque tick du robot de longue durée (tests/harness/Soak),
-- après chaque mutation en Studio, et dans les specs. Rendent la liste des violations (vide = sain),
-- chacune nommée comme un chemin du profil (« coins », « squishies.<uid>.z », « capacity.pen »…) ;
-- ne réparent jamais (c'est le rôle de Server/Data/ProfileRepair).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, string, table = type, math, string, table

local Balance = require(script.Parent.Parent.Config.Balance)
local Species = require(script.Parent.Parent.Config.Species)
local Mutations = require(script.Parent.Parent.Config.Mutations)
local Quests = require(script.Parent.Parent.Config.Quests)

local Invariants = {}

local MAX = Balance.Numbers.Max
local LOCATIONS = { pen = true, pool = true, dodo = true, mail = true }
local MAX_POOL = Balance.Fusion.PoolSlots + 1 -- famille Axolo comprise
local MAX_BF = #Balance.Splorch.BestFriendSlotsAt

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
-- emplacement de Meilleur Ami ; tenues portées par des uid existants ; tableaux denses ; niveaux bornés
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
	if not int(d.R, 0, 1e6) then
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
		for key, cap in Balance.Caps do
			if not Invariants.number(d.caps[key], 0, cap) then
				bad("caps." .. key)
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
	end
	if counts.pen + counts.pool > Balance.Pens.Max then
		bad("capacity.pen")
	end
	if counts.pool > MAX_POOL then
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

	-- tenues : chaque uid porté existe et porte cette tenue ; jamais plus de portées que possédées ;
	-- chaque squishy habillé est dans la liste de sa tenue
	local outfits = d.outfits
	if type(outfits) ~= "table" or type(outfits.owned) ~= "table" or type(outfits.worn) ~= "table" then
		bad("outfits")
	else
		local wornBy: { [string]: string } = {}
		for id, list in outfits.worn do
			local path = "outfits.worn." .. tostring(id)
			if not Invariants.dense(list) then
				bad(path)
				continue
			end
			if #list > (if Invariants.number(outfits.owned[id], 0, 1e9) then outfits.owned[id] else 0) then
				bad(path .. ".count")
			end
			for _, uid in list do
				local rec = squishies[uid]
				if type(rec) ~= "table" or rec.o ~= id then
					bad(path .. "." .. tostring(uid))
				end
				if type(uid) == "string" then
					wornBy[uid] = tostring(id)
				end
			end
		end
		for uid, rec in squishies do
			if type(rec) == "table" and type(rec.o) == "string" and rec.o ~= "" and wornBy[uid] ~= rec.o then
				bad("squishies." .. tostring(uid) .. ".o.worn")
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
	return out
end

return Invariants
