--!nocheck
-- ZeroLog (paquet meta, docs/04 §17.1 h, note INT-HARNESS) : règle « zéro trace » de chaque spec.
--   T = ZeroLog.wrap(T)                -- idempotent : un T déjà enveloppé est rendu tel quel
--   T.expectWarning("motif")           -- dans un test : une trace attendue (texte simple) DOIT arriver
--   ZeroLog.forSpec(chemin, T)         -- T tel quel pour les specs du socle (ZeroLog.SOCLE), wrap sinon
-- Après chaque `it` enveloppé, le test échoue si un harnais de Harness.live() a reçu pendant le test :
--   * une erreur (h.errors : erreurs des threads lancés par le code monté, handlers de signaux compris) ;
--   * un avertissement (h:warnings() : warn, « Infinite yield possible ») ;
--   * une erreur ATTRAPÉE comptée par le vrai DiagnosticsService du harnais (reportCaught : lignes
--     « [caught] … », sinon silencieuses une fois Diagnostics livré).
-- Un harnais créé pendant le test est vérifié en entier ; un harnais créé avant (dans un describe) ne
-- l'est que sur ce qui est arrivé pendant le test. Une trace qui contient le motif d'un expectWarning
-- est permise ; un motif jamais vu fait échouer le test. Une trace provoquée par une panne INJECTÉE par
-- le harnais (DataStore « [panne simulée] », « [quota simulé] », Chaos « [Chaos] », services « … simulé) »)
-- est voulue par la spec qui l'injecte : permise (ZeroLog.INJECTED). Une vraie faute détectée par le
-- harnais (« [DataStore simulé] valeur non sérialisable », tableau à trous…) reste une trace imprévue.
-- tests/run.luau l'applique automatiquement.

local Harness = require("./Harness")

local ZeroLog = {}

-- Specs du socle (reprises de Comet Conga) : gardées telles quelles (leurs propres règles de traces)
ZeroLog.SOCLE = {
	"tests/specs/harness/Harness.spec.luau",
	"tests/specs/harness/Wire.spec.luau",
	"tests/specs/harness/Bots.spec.luau",
	"tests/specs/harness/Sim.spec.luau",
	"tests/specs/Analytics.spec.luau",
	"tests/specs/ClientBoot.spec.luau",
	"tests/specs/Clock.spec.luau",
	"tests/specs/Console.spec.luau",
	"tests/specs/Console_loading.spec.luau",
	"tests/specs/Contract.spec.luau",
	"tests/specs/DataService.spec.luau",
	"tests/specs/Fix_client_socle.spec.luau",
	"tests/specs/Fix_conga_movecheck.spec.luau",
	"tests/specs/Fix_divers_r1_server.spec.luau",
	"tests/specs/Fix_divers_r2.spec.luau",
	"tests/specs/Fix_final_data_lock.spec.luau",
	"tests/specs/Fix_r3_partage_2.spec.luau",
	"tests/specs/Fix_r3_release_data.spec.luau",
	"tests/specs/Fix_r3_serveur_3_data.spec.luau",
	"tests/specs/Fix_r3_serveur_4_movecheck.spec.luau",
	"tests/specs/Fix_r4_partage_4.spec.luau",
	"tests/specs/Fix_r4_ui_1_root.spec.luau",
	"tests/specs/Fix_r5_audio.spec.luau",
	"tests/specs/Fix_r5_partage_2.spec.luau",
	"tests/specs/Fix_r5_serveur_data.spec.luau",
	"tests/specs/Fix_r6_serveur_2_data.spec.luau",
	"tests/specs/Fix_r6_serveur_2_movecheck.spec.luau",
	"tests/specs/Fix_restes_server_data_replication.spec.luau",
	"tests/specs/Loading.spec.luau",
	"tests/specs/MonetizationService.spec.luau",
	"tests/specs/MoveCheck.spec.luau",
	"tests/specs/MoveCheck_budget.spec.luau",
	"tests/specs/MoveCheck_config.spec.luau",
	"tests/specs/Prepublish.spec.luau",
	"tests/specs/RateLimit.spec.luau",
}

local SOCLE_SET = {}
for _, path in ZeroLog.SOCLE do
	SOCLE_SET[path] = true
end

-- Marques des pannes injectées par le harnais (tests/harness/Services, Chaos)
ZeroLog.INJECTED = { "[panne simulée]", "[quota simulé]", "[Chaos]", "simulé)" }

local function injected(line)
	for _, mark in ZeroLog.INJECTED do
		if string.find(line, mark, 1, true) then
			return true
		end
	end
	return false
end

local DIAG_PATH = "ServerScriptService.Server.Services.DiagnosticsService"

-- Vrai DiagnosticsService déjà chargé dans ce harnais (jamais chargé ici : aucun effet de bord)
local function diagnosticsOf(h)
	local ok, node = pcall(function()
		local cur = h.game
		for part in string.gmatch(DIAG_PATH, "[^%.]+") do
			cur = cur:FindFirstChild(part)
			if cur == nil then
				return nil
			end
		end
		return cur
	end)
	if not ok or node == nil or h.cache == nil then
		return nil
	end
	local entry = h.cache[node]
	local module = entry and entry.value
	if type(module) ~= "table" or type(module.caught) ~= "function" then
		return nil -- stub ou doublure : pas de compte réel
	end
	return module
end

-- Erreurs attrapées comptées par Diagnostics : { [clé] = { count, text } }
local function caughtOf(h)
	local diag = diagnosticsOf(h)
	if diag == nil then
		return {}
	end
	local ok, list = pcall(diag.caught)
	return if ok and type(list) == "table" then list else {}
end

local function snapshot(h)
	local warns = 0
	for _, line in h.log.output do
		if line:sub(1, 5) == "WARN " then
			warns += 1
		end
	end
	return { errors = #h.errors, output = #h.log.output, warns = warns, caught = caughtOf(h) }
end

-- Traces arrivées pendant le test (un harnais connu avant : seulement la différence)
local function collect(h, before)
	local out = {}
	if before == nil then
		for _, e in h.errors do
			table.insert(out, "[erreur] " .. tostring(e))
		end
		for _, w in h:warnings() do
			table.insert(out, "[avertissement] " .. tostring(w))
		end
		for _, c in caughtOf(h) do
			table.insert(out, "[attrapée ×" .. tostring(c.count) .. "] " .. c.text)
		end
		return out
	end
	for i = before.errors + 1, #h.errors do
		table.insert(out, "[erreur] " .. tostring(h.errors[i]))
	end
	for i = before.output + 1, #h.log.output do
		local line = h.log.output[i]
		if line:sub(1, 5) == "WARN " then
			table.insert(out, "[avertissement] " .. line)
		end
	end
	for key, c in caughtOf(h) do
		local had = before.caught[key]
		local more = c.count - (if had then had.count else 0)
		if more > 0 then
			table.insert(out, "[attrapée ×" .. tostring(more) .. "] " .. c.text)
		end
	end
	return out
end

function ZeroLog.wrap(T)
	if type(T) ~= "table" then
		return T
	end
	if T.__zeroLog == true then
		return T
	end
	local W = table.clone(T)
	W.__zeroLog = true
	local expected = nil -- motifs du test en cours

	function W.expectWarning(pattern)
		assert(type(pattern) == "string" and pattern ~= "", "expectWarning : motif (texte) attendu")
		if expected == nil then
			error("expectWarning : à appeler dans un test (it)", 2)
		end
		table.insert(expected, { pattern = pattern, hit = false })
	end

	function W.it(name, fn)
		T.it(name, function()
			local before = {}
			for _, h in Harness.live() do
				before[h] = snapshot(h)
			end
			local saved = expected
			expected = {}
			local ok, err = xpcall(fn, function(e)
				return tostring(e) .. "\n" .. debug.traceback(nil, 2)
			end)
			local mine = expected
			expected = saved
			if not ok then
				error(err, 0)
			end
			local problems = {}
			local seen = {}
			for _, h in Harness.live() do
				for _, line in collect(h, before[h]) do
					if not seen[line] then
						seen[line] = true
						local allowed = injected(line)
						for _, e in mine do
							if string.find(line, e.pattern, 1, true) then
								e.hit = true
								allowed = true
							end
						end
						if not allowed then
							table.insert(problems, line)
						end
					end
				end
			end
			for _, e in mine do
				if not e.hit then
					table.insert(problems, "[attendue mais jamais vue] " .. e.pattern)
				end
			end
			if #problems > 0 then
				local shown = {}
				for i = 1, math.min(#problems, 8) do
					table.insert(shown, (string.gsub(problems[i], "\n", "\n      ")))
				end
				if #problems > 8 then
					table.insert(shown, "… et " .. tostring(#problems - 8) .. " autre(s)")
				end
				error("zéro trace (ZeroLog) :\n    " .. table.concat(shown, "\n    "), 0)
			end
		end)
	end

	return W
end

-- Chemin normalisé (« tests/specs/… ») : une spec du socle reçoit T tel quel
function ZeroLog.forSpec(path, T)
	local p = string.gsub(tostring(path), "\\", "/")
	p = string.gsub(p, "^%./", "")
	if SOCLE_SET[p] then
		return T
	end
	return ZeroLog.wrap(T)
end

function ZeroLog.isSocle(path)
	return SOCLE_SET[(string.gsub(tostring(path), "^%./", ""))] == true
end

return ZeroLog
