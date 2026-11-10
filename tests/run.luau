--!nocheck
-- Lance tous les tests : `lune run tests/run` depuis la racine du projet.
-- Filtrer : `lune run tests/run -- Economy` (exécute les specs dont le nom contient « Economy » ; un
-- chemin complet `tests/specs/….spec.luau` ne désigne que ce fichier).
-- Suite entière (aucun filtre) : chaque fichier de specs tourne dans son propre processus Lune (le
-- lanceur se relance avec le chemin du fichier) et les comptes sont additionnés ; la mémoire d'un
-- fichier est rendue au système avant le suivant (porte du lot B3, journal docs/04 B3-83 : les 246
-- fichiers dans un seul processus montaient à 14 Go de mémoire résidente et le processus était tué
-- faute de mémoire). `-- --isolate <filtre>` isole aussi une partie ; `-- --single-process` garde
-- l'ancien mode (tous les fichiers dans ce processus).

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Test = require("./harness/Test")
local Harness = require("./harness/Harness")

local filter = nil
local single, isolate = false, false
for _, arg in process.args do
	if arg == "--single-process" then
		single = true
	elseif arg == "--isolate" then
		isolate = true
	elseif arg ~= "--" then
		filter = arg
	end
end

-- un chemin complet de spec ne désigne que ce fichier ; sinon, sous-chaîne du chemin
local function selected(path: string): boolean
	if filter == nil then
		return true
	end
	if string.match(filter, "^tests/specs/.+%.spec%.luau$") then
		return path == filter
	end
	return string.find(path, filter, 1, true) ~= nil
end

local specs = {}
local function collect(dir: string)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			collect(full)
		elseif entry:match("%.spec%.luau$") then
			table.insert(specs, full)
		end
	end
end
collect("tests/specs")
table.sort(specs)

-- Programme Lune des processus fils : « lune » du PATH, sinon ~/.cargo/bin/lune ou ~/.rokit/bin/lune
local function luneProgram(): string?
	local home = process.env.HOME or ""
	for _, program in { "lune", home .. "/.cargo/bin/lune", home .. "/.rokit/bin/lune" } do
		local ok, res = pcall(process.exec, program, { "--version" })
		if ok and res.ok then
			return program
		end
	end
	return nil
end

-- Un processus par fichier de specs : sortie du fils recopiée, comptes additionnés, échecs détaillés
-- rassemblés à la fin (même forme que le mode à un seul processus) ; un fils arrêté sans sa ligne de
-- comptes (mémoire, plantage) compte comme une spec non chargée
local SUMMARY = "(%d+) réussis, (%d+) échoués, (%d+) specs non chargées"

local function runIsolated(program: string)
	local passed, failed, notLoaded = 0, 0, 0
	local details = {}
	for _, path in specs do
		if selected(path) then
			local ok, res = pcall(process.exec, program, { "run", "tests/run", "--", path })
			local out = if ok then res.stdout else ""
			if ok and res.stderr ~= "" then
				stdio.ewrite(res.stderr)
			end
			local at, p, f, l = nil, 0, 0, 0
			local init = 1
			while true do
				local s, e, a, b, c = string.find(out, SUMMARY, init)
				if s == nil then
					break
				end
				at, p, f, l = s, tonumber(a), tonumber(b), tonumber(c)
				init = e + 1
			end
			if at == nil then
				stdio.write(out)
				notLoaded += 1
				local why = if ok then "code " .. tostring(res.code) else tostring(res)
				local errTail = if ok then string.sub(res.stderr, -2000) else ""
				table.insert(
					details,
					"\n\27[31m✗ "
						.. path
						.. " : processus arrêté sans résultat ("
						.. why
						.. ")\27[0m\n"
						.. errTail
				)
			else
				stdio.write((string.gsub(string.sub(out, 1, at - 1), "%s+$", "")) .. "\n")
				passed += p
				failed += f
				notLoaded += l
				local rest = string.gsub(string.sub(out, at), "^[^\n]*\n?", "")
				if string.find(rest, "%S") then
					table.insert(details, rest)
				end
			end
		end
	end
	print(string.format("\n%d réussis, %d échoués, %d specs non chargées", passed, failed, notLoaded))
	for _, d in details do
		stdio.write(d)
	end
	process.exit(if failed == 0 and notLoaded == 0 then 0 else 1)
end

if not single and (filter == nil or isolate) then
	local program = luneProgram()
	if program then
		runIsolated(program)
	end
	print("lune introuvable pour les processus fils : tous les fichiers dans ce processus")
end

local T = {
	describe = Test.describe,
	it = Test.it,
	expect = Test.expect,
	Harness = Harness,
}

-- Couche « zéro trace » (docs/04 §17.1 h, note INT-HARNESS) : dès que tests/harness/ZeroLog.luau
-- existe (paquet meta), chaque spec reçoit ZeroLog.forSpec(chemin, T) : un T dont chaque `it` échoue
-- sur toute erreur ou tout avertissement imprévu des harnais créés pendant le test ; les specs du
-- socle listées par ZeroLog reçoivent T tel quel.
local ZeroLog = nil
if fs.isFile("tests/harness/ZeroLog.luau") then
	ZeroLog = require("./harness/ZeroLog")
end

local loadErrors = {}
for _, path in specs do
	if selected(path) then
		print("\n\27[1m" .. path .. "\27[0m")
		-- require relatif à ce fichier : tests/specs/... → ./specs/...
		local rel = "./" .. path:gsub("^tests/", ""):gsub("%.luau$", "")
		local ok, err = pcall(function()
			local spec = require(rel)
			spec(if ZeroLog then ZeroLog.forSpec(path, T) else T)
		end)
		if not ok then
			table.insert(loadErrors, path .. " : " .. tostring(err))
			print("  \27[31m✗ échec de chargement : " .. tostring(err) .. "\27[0m")
		end
		-- threads restants des harnais de cette spec : annulés (aucune fuite vers la spec suivante,
		-- mémoire libérée)
		Harness.disposeAll()
	end
end

local r = Test.results()
print(string.format("\n%d réussis, %d échoués, %d specs non chargées", r.passed, r.failed, #loadErrors))
for _, f in r.failures do
	print("\n\27[31m✗ " .. f .. "\27[0m")
end
for _, f in loadErrors do
	print("\n\27[31m✗ " .. f .. "\27[0m")
end
process.exit(if r.failed == 0 and #loadErrors == 0 then 0 else 1)
