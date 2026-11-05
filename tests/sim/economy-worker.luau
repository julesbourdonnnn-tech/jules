--!nocheck
-- Fils de la porte d'économie (docs/04 §27.9) : `lune run tests/sim/economy-worker <job en JSON>`
-- joue UNE configuration (tests/sim/EconomyIO.run) et écrit ses joueurs en JSON sur la sortie, après
-- EconomyIO.MARK. Code de sortie 0 seulement si la simulation a réussi SANS aucune trace du harnais
-- (zéro erreur, zéro avertissement : la règle zéro trace vaut dans le fils comme dans la spec) ; sinon
-- 1, et la raison sur la sortie d'erreur.
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Harness = require("../harness/Harness")
local EconomyIO = require("./EconomyIO")

local text = process.args[1]
if type(text) ~= "string" then
	stdio.ewrite("economy-worker : job JSON attendu en argument\n")
	process.exit(1)
end
local h = Harness.new()
local ok, result = pcall(function()
	local job = EconomyIO.decode(text)
	return EconomyIO.run(EconomyIO.load(h), job)
end)
if not ok then
	stdio.ewrite("economy-worker : " .. tostring(result) .. "\n")
	process.exit(1)
end
local errors, warnings = #h.errors, #h:warnings()
if errors > 0 or warnings > 0 then
	stdio.ewrite(
		string.format("economy-worker : %d erreur(s), %d avertissement(s) du harnais\n", errors, warnings)
	)
	for _, e in h.errors do
		stdio.ewrite("  " .. tostring(e) .. "\n")
	end
	process.exit(1)
end
stdio.write(EconomyIO.MARK .. EconomyIO.encode(result))
process.exit(0)
