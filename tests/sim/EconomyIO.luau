--!nocheck
-- EconomyIO (paquet A1, docs/04 §27.9) : une configuration de la porte d'économie, jouée dans ce
-- processus ou dans un processus fils (tests/sim/economy-worker.luau), et le codage de ses joueurs en
-- JSON (sans perte : ±inf, NaN, tableaux à trous). EconomyPacing.spec joue ses configurations dans
-- plusieurs fils à la fois (une par cœur) : mêmes graines, même code, mêmes joueurs au bit près
-- (EconomyPacing › « un fils rend les mêmes joueurs que le calcul en place »).
--
--   local L = EconomyIO.load(harness)                 -- modules du jeu requis par le harnais
--   local players = EconomyIO.run(L, job)             -- job : { flags, size, players, days, seed,
--                                                      --         v2 = { … }, spender }
--   local text = EconomyIO.encode(players) ; EconomyIO.decode(text)

local serde = require("@lune/serde")
local Sim = require("./Sim")
local EconomyModel = require("./EconomyModel")

local EconomyIO = {}

-- Modules du jeu lus par EconomyModel (vraies formules, vraies tables), requis par le harnais
function EconomyIO.load(h)
	local function logic(name)
		return h:require("ReplicatedStorage.Shared.Logic." .. name)
	end
	local function config(name)
		return h:require("ReplicatedStorage.Shared.Config." .. name)
	end
	return {
		Formulas = logic("Formulas"),
		Odds = logic("Odds"),
		FusionRules = logic("FusionRules"),
		QuestRules = logic("QuestRules"),
		RushRules = logic("RushRules"),
		EventClock = logic("EventClock"),
		Hash = logic("Hash"),
		Prestige = logic("Prestige"),
		UpgradeMath = logic("UpgradeMath"),
		UpgradeAdvisor = logic("UpgradeAdvisor"),
		Bitset = logic("Bitset"),
		Balance = config("Balance"),
		Species = config("Species"),
		Rarities = config("Rarities"),
		Mutations = config("Mutations"),
		Quests = config("Quests"),
		Events = config("Events"),
		Features = config("Features"),
		Upgrades = config("Upgrades"),
	}
end

-- Joue une configuration : interrupteurs de l'économie tous coupés (flags = false, jeu de base) ou
-- tous ouverts (v2.0), remis à zéro ensuite, même en cas d'erreur. Rend la liste des joueurs
function EconomyIO.run(L, job)
	local Features = L.Features
	Features.reset()
	-- chaque interrupteur de l'économie posé explicitement (tous ouverts ou tous coupés) : la
	-- configuration livrée en ouvre une partie depuis le lot I (étape 2, journal I-19)
	for _, key in EconomyModel.ECON_FLAGS do
		assert(Features.set(key, job.flags == true), "interrupteur refusé : " .. key)
	end
	local out = table.pack(pcall(function()
		local model = EconomyModel.new(L)
		local simulate = model.simulateFor({ players = job.size, v2 = job.v2, spender = job.spender == true })
		local players = {}
		for i = 1, job.players do
			players[i] = simulate(Sim.newRng(job.seed * 1000003 + i), i, job.days)
		end
		return players
	end))
	Features.reset()
	if not out[1] then
		error(out[2], 0)
	end
	return out[2]
end

-- Codage JSON sans perte : un tableau 1 … n sans autre clé reste un tableau ; toute autre table devient
-- { "~t" = { "n:<clé>" | "s:<clé>" = valeur } } ; un entier exact (|v| < 2^53) reste un nombre JSON ;
-- tout autre nombre devient { "~" = "%.17g" } (17 chiffres : relu au bit près par tonumber ; le lecteur
-- JSON, lui, peut se tromper d'un ulp sur un réel), ±inf et NaN { "~" = "inf" | "-inf" | "nan" }
local EXACT = 2 ^ 53
local function pack(v)
	local t = type(v)
	if t == "number" then
		if v ~= v then
			return { ["~"] = "nan" }
		elseif v == math.huge then
			return { ["~"] = "inf" }
		elseif v == -math.huge then
			return { ["~"] = "-inf" }
		elseif v == math.floor(v) and math.abs(v) < EXACT then
			return v
		end
		return { ["~"] = string.format("%.17g", v) }
	elseif t == "table" then
		local n, count = #v, 0
		for _ in v do
			count += 1
		end
		if count == n then
			local out = table.create(n)
			for i = 1, n do
				out[i] = pack(v[i])
			end
			return out
		end
		local out = {}
		for k, x in v do
			local key = if type(k) == "number" then "n:" .. string.format("%.17g", k) else "s:" .. tostring(k)
			out[key] = pack(x)
		end
		return { ["~t"] = out }
	elseif t == "string" or t == "boolean" then
		return v
	end
	error("EconomyIO : valeur non codable (" .. t .. ")")
end

local function unpackValue(v)
	if type(v) ~= "table" then
		return v
	end
	local special = v["~"]
	if special ~= nil then
		if special == "nan" then
			return 0 / 0
		elseif special == "inf" then
			return math.huge
		elseif special == "-inf" then
			return -math.huge
		end
		local n = tonumber(special)
		if n == nil then
			error("EconomyIO : nombre inconnu " .. tostring(special))
		end
		return n
	end
	local typed = v["~t"]
	if typed ~= nil then
		local out = {}
		for key, x in typed do
			local kind, rest = string.sub(key, 1, 2), string.sub(key, 3)
			out[if kind == "n:" then tonumber(rest) else rest] = unpackValue(x)
		end
		return out
	end
	local out = table.create(#v)
	for i = 1, #v do
		out[i] = unpackValue(v[i])
	end
	return out
end

function EconomyIO.encode(value)
	return serde.encode("json", pack(value))
end

function EconomyIO.decode(text)
	return unpackValue(serde.decode("json", text))
end

-- Marque qui précède le JSON dans la sortie d'un fils (le reste de la sortie est ignoré)
EconomyIO.MARK = "<<<ECON-JSON>>>"

return EconomyIO
