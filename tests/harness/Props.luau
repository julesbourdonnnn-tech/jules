--!nocheck
-- Props (paquet logic, docs/04 §17.1 couche a) : tests de propriétés à graine fixe.
-- Un générateur est une table { gen = function(rng) → valeur, shrink = function(valeur) → { plus
-- petites } } ; Props.check(n, générateur, prédicat, options?) tire n valeurs, et à la première qui
-- fait échouer le prédicat (faux, nil ou erreur), cherche un contre-exemple plus petit (réduction)
-- puis lève une erreur lisible avec la graine, le numéro du cas et la valeur réduite.
--
--   local Props = require("../harness/Props")
--   Props.check(2000, Props.tuple(Props.anyNumber(), Props.bool()), function(v)
--       local x = Formulas.clampCoins(v[1]) ; return x >= 0 and x == x
--   end)
--
-- Générateurs fournis : weird (NaN, ±inf, 1e308, −0…), number(a, b), anyNumber, int(a, b), bool,
-- oneOf(liste), constant(v), utf8(n) (UTF-8 valide), bytes(n) (souvent invalide), string(n),
-- weirdTable (mixte, à trous, profonde, cyclique), any (n'importe quelle valeur), tuple(…),
-- array(g, n), map(g, fn), vector3(a, b), maybe(g) (nil parfois).
-- Déterministe : jamais math.random ; même graine = mêmes cas sur toutes les machines.

local roblox = require("@lune/roblox")

local Props = {}

Props.DEFAULT_SEED = 20261101

-- =============================================================================================
-- Générateur pseudo-aléatoire (congruentiel, exact en double)
-- =============================================================================================

function Props.rng(seed: number)
	local state = (math.floor(seed or Props.DEFAULT_SEED) * 2654435761 + 12345) % 4294967296
	local self = {}
	function self.next(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
	function self.int(a: number, b: number): number
		return math.min(b, a + math.floor((b - a + 1) * self.next()))
	end
	function self.range(a: number, b: number): number
		return a + (b - a) * self.next()
	end
	function self.chance(p: number): boolean
		return self.next() < p
	end
	function self.pick(list)
		return list[self.int(1, #list)]
	end
	return self
end

-- =============================================================================================
-- Affichage d'un contre-exemple
-- =============================================================================================

function Props.format(v, depth: number?, seen): string
	depth = depth or 0
	seen = seen or {}
	local t = typeof(v)
	if t == "number" then
		if v ~= v then
			return "NaN"
		elseif v == math.huge then
			return "inf"
		elseif v == -math.huge then
			return "-inf"
		elseif v == 0 and 1 / v < 0 then
			return "-0"
		end
		return string.format("%.17g", v)
	elseif t == "string" then
		if #v > 80 then
			return string.format("%q", string.sub(v, 1, 80)) .. "…(" .. #v .. " octets)"
		end
		return string.format("%q", v)
	elseif t == "table" then
		if seen[v] then
			return "<cycle>"
		end
		if depth > 3 then
			return "{…}"
		end
		seen[v] = true
		local parts = {}
		local count = 0
		for k, x in v do
			count += 1
			if count > 12 then
				table.insert(parts, "…")
				break
			end
			table.insert(
				parts,
				"[" .. Props.format(k, depth + 1, seen) .. "]=" .. Props.format(x, depth + 1, seen)
			)
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

-- =============================================================================================
-- Générateurs
-- =============================================================================================

local function noShrink(_v)
	return {}
end

function Props.gen(fn, shrink)
	return { gen = fn, shrink = shrink or noShrink }
end

-- Réduction d'un nombre : vers 0, entiers, moitiés
local function shrinkNumber(x)
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge or x == 0 then
		return {}
	end
	local out = { 0 }
	if x < 0 then
		table.insert(out, -x)
	end
	if x % 1 ~= 0 then
		table.insert(out, math.floor(x))
	end
	if math.abs(x) > 1 then
		table.insert(out, x / 2)
		table.insert(out, if x > 0 then 1 else -1)
	end
	return out
end

local WEIRD = {
	0 / 0,
	math.huge,
	-math.huge,
	1e308,
	-1e308,
	-0.0,
	0,
	1,
	-1,
	0.5,
	-0.5,
	2 ^ 53,
	-(2 ^ 53),
	2 ^ 31,
	-(2 ^ 31),
	4294967296,
	1e-308,
	1e300,
	1e15,
	math.pi,
}

-- Nombres limites
function Props.weird()
	return Props.gen(function(rng)
		return rng.pick(WEIRD)
	end, shrinkNumber)
end

-- Réel uniforme dans [a ; b] (bornes et milieu tirés plus souvent)
function Props.number(a: number, b: number)
	return Props.gen(function(rng)
		local r = rng.next()
		if r < 0.05 then
			return a
		elseif r < 0.1 then
			return b
		end
		return rng.range(a, b)
	end, function(x)
		local out = {}
		for _, c in shrinkNumber(x) do
			if c >= a and c <= b then
				table.insert(out, c)
			end
		end
		if x ~= a then
			table.insert(out, a)
		end
		return out
	end)
end

-- N'importe quel nombre : limites, petits, grands (magnitude log-uniforme), entiers, négatifs
function Props.anyNumber()
	return Props.gen(function(rng)
		local r = rng.next()
		if r < 0.25 then
			return rng.pick(WEIRD)
		elseif r < 0.5 then
			return rng.int(-1000, 1000)
		elseif r < 0.75 then
			local mag = 10 ^ rng.range(-6, 306)
			return if rng.chance(0.2) then -mag else mag
		end
		return rng.range(-100, 100)
	end, shrinkNumber)
end

-- Entier uniforme dans [a ; b]
function Props.int(a: number, b: number)
	return Props.gen(function(rng)
		return rng.int(a, b)
	end, function(x)
		local out = {}
		for _, c in shrinkNumber(x) do
			c = math.floor(c)
			if c >= a and c <= b and c ~= x then
				table.insert(out, c)
			end
		end
		if x ~= a then
			table.insert(out, a)
		end
		return out
	end)
end

function Props.bool()
	return Props.gen(function(rng)
		return rng.chance(0.5)
	end, function(b)
		return if b then { false } else {}
	end)
end

function Props.constant(v)
	return Props.gen(function()
		return v
	end)
end

-- Une valeur d'une liste (réduction vers les premières)
function Props.oneOf(list)
	return Props.gen(function(rng)
		return rng.pick(list)
	end, function(v)
		local i = table.find(list, v)
		local out = {}
		if i and i > 1 then
			table.insert(out, list[1])
		end
		return out
	end)
end

-- Caractères UTF-8 valides variés (1 à 4 octets)
local CHARS = {
	"a",
	"Z",
	"0",
	"9",
	" ",
	".",
	"é",
	"ü",
	"€",
	"→",
	"日",
	"本",
	"😀",
	"🍮",
	"\n",
	"\t",
	'"',
	"%",
	"<",
	"#",
}

local function shrinkString(s)
	if type(s) ~= "string" or #s == 0 then
		return {}
	end
	local out = { "" }
	if #s > 1 then
		table.insert(out, string.sub(s, 1, #s // 2))
		table.insert(out, string.sub(s, 2))
	end
	return out
end

-- Chaîne UTF-8 valide de 0 à n caractères
function Props.utf8(n: number)
	return Props.gen(function(rng)
		local len = rng.int(0, n)
		local parts = table.create(len)
		for i = 1, len do
			parts[i] = rng.pick(CHARS)
		end
		return table.concat(parts)
	end, shrinkString)
end

-- Suite d'octets quelconques (souvent de l'UTF-8 invalide) de 0 à n octets
function Props.bytes(n: number)
	return Props.gen(function(rng)
		local len = rng.int(0, n)
		local parts = table.create(len)
		for i = 1, len do
			parts[i] = string.char(rng.int(0, 255))
		end
		return table.concat(parts)
	end, shrinkString)
end

-- Chaîne quelconque : vide, valide, invalide, très longue
function Props.string(n: number)
	local valid, raw = Props.utf8(n), Props.bytes(n)
	return Props.gen(function(rng)
		local r = rng.next()
		if r < 0.1 then
			return ""
		elseif r < 0.15 then
			return string.rep("x", 100000)
		elseif r < 0.6 then
			return valid.gen(rng)
		end
		return raw.gen(rng)
	end, shrinkString)
end

-- Tables hostiles : mixtes, à trous, profondes, cycliques, vides
function Props.weirdTable()
	return Props.gen(function(rng)
		local r = rng.int(1, 7)
		if r == 1 then
			return {}
		elseif r == 2 then
			return { 1, 2, nil, 4 }
		elseif r == 3 then
			return { 1, 2, x = "y" }
		elseif r == 4 then
			local t = {}
			local cur = t
			for _ = 1, 50 do
				cur.next = {}
				cur = cur.next
			end
			return t
		elseif r == 5 then
			local t = {}
			t.self = t
			return t
		elseif r == 6 then
			return { [0 / 0 == 0 / 0 and 1 or 2] = 0 / 0, [1.5] = true, [-1] = "a" }
		end
		return { "a", "b", "c" }
	end)
end

-- N'importe quelle valeur (nil compris)
function Props.any()
	local num, str, tbl = Props.anyNumber(), Props.string(20), Props.weirdTable()
	return Props.gen(function(rng)
		local r = rng.int(1, 6)
		if r == 1 then
			return nil
		elseif r == 2 then
			return rng.chance(0.5)
		elseif r == 3 then
			return num.gen(rng)
		elseif r == 4 then
			return str.gen(rng)
		elseif r == 5 then
			return tbl.gen(rng)
		end
		return roblox.Vector3.new(rng.range(-10, 10), 0, rng.range(-10, 10))
	end)
end

-- nil parfois (20 %), sinon une valeur du générateur
function Props.maybe(g)
	return Props.gen(function(rng)
		if rng.chance(0.2) then
			return nil
		end
		return g.gen(rng)
	end, function(v)
		if v == nil then
			return {}
		end
		return g.shrink(v)
	end)
end

-- Transformation d'une valeur générée (pas de réduction après transformation)
function Props.map(g, fn)
	return Props.gen(function(rng)
		return fn(g.gen(rng), rng)
	end)
end

-- Tuple { v1, v2, … } : chaque élément se réduit à son tour
function Props.tuple(...)
	local gens = { ... }
	local count = select("#", ...)
	return Props.gen(function(rng)
		local out = {}
		for i = 1, count do
			out[i] = gens[i].gen(rng)
		end
		return out
	end, function(v)
		local out = {}
		for i = 1, count do
			for _, smaller in gens[i].shrink(v[i]) do
				local copy = table.clone(v)
				copy[i] = smaller
				table.insert(out, copy)
			end
		end
		return out
	end)
end

-- Tableau de 0 à n éléments
function Props.array(g, n: number)
	return Props.gen(function(rng)
		local len = rng.int(0, n)
		local out = table.create(len)
		for i = 1, len do
			out[i] = g.gen(rng)
		end
		return out
	end, function(list)
		local out = {}
		if #list > 0 then
			table.insert(out, {})
			local half = {}
			for i = 1, #list // 2 do
				half[i] = list[i]
			end
			table.insert(out, half)
		end
		return out
	end)
end

-- Vector3 aux composantes dans [a ; b] (Y = 0 si flat)
function Props.vector3(a: number, b: number, flat: boolean?)
	return Props.gen(function(rng)
		return roblox.Vector3.new(rng.range(a, b), if flat then 0 else rng.range(a, b), rng.range(a, b))
	end)
end

-- =============================================================================================
-- Vérification
-- =============================================================================================

-- Le prédicat échoue : faux, nil ou erreur ; rend (échec, message). Un prédicat peut rendre une
-- raison en second résultat (« return false, "pourquoi" ») : elle est affichée avec le cas.
local function failing(predicate, value): (boolean, string?)
	local ok, result, reason = pcall(predicate, value)
	if not ok then
		return true, "erreur : " .. tostring(result)
	end
	if result ~= true then
		if reason ~= nil then
			return true, tostring(reason)
		end
		return true, if result == false or result == nil then nil else tostring(result)
	end
	return false, nil
end

-- Lance n cas ; lève une erreur lisible au premier échec (après réduction)
function Props.check(n: number, g, predicate, opts)
	opts = opts or {}
	local seed = opts.seed or Props.DEFAULT_SEED
	local rng = Props.rng(seed)
	for i = 1, n do
		local value = g.gen(rng)
		local bad, why = failing(predicate, value)
		if bad then
			-- réduction : on garde la plus petite valeur qui échoue encore
			local steps = 0
			local improved = true
			while improved and steps < (opts.shrinkSteps or 200) do
				improved = false
				for _, candidate in g.shrink(value) do
					steps += 1
					local stillBad, candidateWhy = failing(predicate, candidate)
					if stillBad then
						value, why = candidate, candidateWhy
						improved = true
						break
					end
				end
			end
			error(
				string.format(
					"propriété fausse (graine %d, cas %d/%d) : %s%s",
					seed,
					i,
					n,
					Props.format(value),
					if why then " — " .. why else ""
				),
				2
			)
		end
	end
	return true
end

return Props
