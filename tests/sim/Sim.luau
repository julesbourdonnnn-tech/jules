--!nocheck
-- Socle de simulation de progression (repris du cadre de tests/sim/Pacing de Comet Conga, sans son
-- économie). La simulation d'économie du jeu (croissance, fusions, bébés, Grand Splorch, premier
-- rebirth vers 12-15 min) est OBLIGATOIRE avant le lancement : elle s'écrit au-dessus de ce module,
-- avec les VRAIES tables (Shared/Config) et les VRAIES formules du jeu ; seules les hypothèses de
-- COMPORTEMENT du joueur appartiennent au modèle.
--
--   local Sim = require("../sim/Sim")
--   local result = Sim.run({
--       players = 200, days = 28, seed = 1,
--       simulate = function(rng, index, days) → { [clé] = nombre } end,   -- un joueur
--       gates = { { key = "firstRebirth", label = "Premier rebirth (min)", min = 12, max = 15 } },
--       reported = { { key = "finalCoins", label = "Pièces au jour final" } },
--   })
--   print(Sim.report(result)) ; expect(#Sim.failures(result)).toBe(0)
--
-- Déterministe : chaque joueur a son propre générateur, graine dérivée de (seed, index) ; une valeur
-- « jamais atteinte » vaut math.huge (affichée « jamais »).

local Sim = {}

Sim.DAY = 86400

-- Générateur congruentiel (produits < 2^53 : exact en double), déterministe. rng() ∈ [0 ; 1[ ;
-- rng.range(a, b) réel ; rng.int(a, b) entier inclus ; rng.chance(p) booléen
function Sim.newRng(seed: number)
	local state = (math.floor(seed) * 2654435761 + 12345) % 4294967296
	local function nextValue(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
	return setmetatable({
		range = function(a: number, b: number): number
			return a + (b - a) * nextValue()
		end,
		int = function(a: number, b: number): number
			return math.min(b, a + math.floor((b - a + 1) * nextValue()))
		end,
		chance = function(p: number): boolean
			return nextValue() < p
		end,
	}, {
		__call = function()
			return nextValue()
		end,
	})
end

-- Quantile q ∈ [0 ; 1] (interpolation linéaire) ; liste vide : math.huge ; une valeur infinie dans
-- l'interpolation reste infinie (« jamais »)
function Sim.quantile(values: { number }, q: number): number
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return math.huge
	end
	local pos = 1 + (n - 1) * math.clamp(q, 0, 1)
	local lo = math.floor(pos)
	local hi = math.min(n, lo + 1)
	local a, b = sorted[lo], sorted[hi]
	if a == math.huge or b == math.huge then
		return if pos == lo then a else math.huge
	end
	return a + (b - a) * (pos - lo)
end

function Sim.median(values: { number }): number
	return Sim.quantile(values, 0.5)
end

-- Lance la simulation ; rend { medians, p10, p90, players, gates, reported }
function Sim.run(opts)
	assert(type(opts.simulate) == "function", "Sim.run : simulate(rng, index, days) attendu")
	local players = opts.players or 100
	local days = opts.days or 28
	local seed = opts.seed or 1
	local results = {}
	for i = 1, players do
		local rng = Sim.newRng(seed * 1000003 + i)
		results[i] = opts.simulate(rng, i, days)
	end
	return Sim.aggregate(results, opts.gates, opts.reported)
end

-- Résultat d'une liste de joueurs déjà simulés (même forme que Sim.run : médianes, p10, p90 des clés
-- des portes et des clés rapportées) ; sert aussi aux joueurs simulés dans un autre processus
function Sim.aggregate(results, gates, reported)
	local opts = { gates = gates, reported = reported }
	local keys = {}
	for _, g in opts.gates or {} do
		table.insert(keys, g.key)
	end
	for _, r in opts.reported or {} do
		table.insert(keys, r.key)
	end
	local medians, p10, p90 = {}, {}, {}
	for _, key in keys do
		local values = {}
		for _, r in results do
			local v = r[key]
			table.insert(values, if type(v) == "number" and v == v then v else math.huge)
		end
		medians[key] = Sim.median(values)
		p10[key] = Sim.quantile(values, 0.1)
		p90[key] = Sim.quantile(values, 0.9)
	end
	return {
		medians = medians,
		p10 = p10,
		p90 = p90,
		players = results,
		gates = opts.gates or {},
		reported = opts.reported or {},
	}
end

local function inside(g, m: number): boolean
	return (g.min == nil or m >= g.min) and (g.max == nil or m <= g.max)
end

-- Portes dont la médiane sort de sa tolérance (liste de libellés)
function Sim.failures(result): { string }
	local out = {}
	for _, g in result.gates do
		if not inside(g, result.medians[g.key]) then
			table.insert(out, g.label)
		end
	end
	return out
end

-- Rapport lisible (affiché par la spec qui lance la simulation)
function Sim.report(result): string
	local lines = {}
	local function fmt(x)
		if x == math.huge then
			return "jamais"
		end
		return string.format("%.1f", x)
	end
	for _, g in result.gates do
		local m = result.medians[g.key]
		table.insert(
			lines,
			string.format(
				"  %-34s médiane %8s (p10 %s, p90 %s)   tolérance [%s ; %s]   %s",
				g.label,
				fmt(m),
				fmt(result.p10[g.key]),
				fmt(result.p90[g.key]),
				tostring(g.min or "—"),
				tostring(g.max or "—"),
				if inside(g, m) then "OK" else "HORS"
			)
		)
	end
	for _, r in result.reported do
		table.insert(lines, string.format("  %-34s médiane %8s", r.label, fmt(result.medians[r.key])))
	end
	return table.concat(lines, "\n")
end

return Sim
