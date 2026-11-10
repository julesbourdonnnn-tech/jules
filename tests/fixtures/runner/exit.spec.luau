--!nocheck
-- Spec jouet du lanceur de tests (tests/specs/Runner.spec.luau) : le processus s'arrête en plein
-- cas avec le code 0, avant sa ligne de comptes (comme un processus tué, sans le code d'erreur).
local process = require("@lune/process")

return function(T)
	T.describe("jouet arrêté", function()
		T.it("passe puis quitte le processus", function()
			T.expect(1).toBe(1)
			process.exit(0)
		end)
	end)
end
