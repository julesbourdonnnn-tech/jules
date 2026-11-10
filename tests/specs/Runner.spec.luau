--!nocheck
-- Lanceur de tests (tests/run.luau ; journal docs/04 B3-83 et B3-84). La suite entière tourne un
-- processus Lune par fichier de specs, et le lanceur additionne les comptes lus dans la sortie de
-- chaque fils. Cette spec relance le lanceur sur les specs jouets de tests/fixtures/runner (option
-- `--dir`) et prouve que le résultat n'est jamais vert quand un cas échoue, quand un fichier ne se
-- charge pas, quand un processus s'arrête avant sa ligne de comptes ou quand le texte d'un échec
-- imite cette ligne ; et que les comptes sont ceux du mode à un seul processus.
local process = require("@lune/process")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local DIR = "tests/fixtures/runner"

	-- même recherche que tests/run.luau : « lune » du PATH, sinon ~/.cargo/bin ou ~/.rokit/bin
	local function luneProgram(): string
		local home = process.env.HOME or ""
		for _, program in { "lune", home .. "/.cargo/bin/lune", home .. "/.rokit/bin/lune" } do
			local ok, res = pcall(process.exec, program, { "--version" })
			if ok and res.ok then
				return program
			end
		end
		error("lune introuvable pour relancer le lanceur")
	end
	local program = luneProgram()

	-- Relance le lanceur sur les specs jouets : son code de sortie, sa ligne de comptes (la dernière
	-- de sa sortie) et sa sortie sans couleurs
	local function run(...: string): (number, string?, string)
		local res = process.exec(program, { "run", "tests/run", "--", "--dir", DIR, ... })
		local out = string.gsub(res.stdout, "\27%[[%d;]*m", "")
		local counts = nil
		for line in string.gmatch(out, "%d+ réussis, %d+ échoués, %d+ specs non chargées") do
			counts = line
		end
		return res.code, counts, out
	end

	local function has(out: string, text: string, init: number?): boolean
		return string.find(out, text, init or 1, true) ~= nil
	end

	describe("Lanceur de tests › un processus par fichier de specs", function()
		it("tout est vert : code 0 et comptes du fichier", function()
			local code, counts = run("--isolate", "ok")
			expect(counts).toBe("2 réussis, 0 échoués, 0 specs non chargées")
			expect(code).toBe(0)
		end)

		it("un cas en échec : code 1, l'échec est compté, puis détaillé après les comptes", function()
			local code, counts, out = run("--isolate", "fail")
			expect(counts).toBe("1 réussis, 1 échoués, 0 specs non chargées")
			expect(code).toBe(1)
			local at = string.find(out, "\n1 réussis, 1 échoués, 0 specs non chargées", 1, true)
			expect(at ~= nil and has(out, "✗ jouet en échec › échoue", at)).toBe(true)
		end)

		it("un fichier qui ne se charge pas : code 1, une spec non chargée", function()
			local code, counts, out = run("--isolate", "load")
			expect(counts).toBe("0 réussis, 0 échoués, 1 specs non chargées")
			expect(code).toBe(1)
			expect(has(out, "plantage au chargement de la spec jouet")).toBe(true)
		end)

		it("un processus arrêté avant sa ligne de comptes : code 1, une spec non chargée", function()
			local code, counts, out = run("--isolate", "exit")
			expect(counts).toBe("0 réussis, 0 échoués, 1 specs non chargées")
			expect(code).toBe(1)
			expect(has(out, "exit.spec.luau : processus arrêté sans résultat (code 0)")).toBe(true)
		end)

		it("le texte d'un échec imite la ligne de comptes : code 1, jamais vert", function()
			local code, counts, out = run("--isolate", "fake")
			expect(counts).toBe("0 réussis, 0 échoués, 1 specs non chargées")
			expect(code).toBe(1)
			expect(has(out, "fake.spec.luau : sorti en erreur (code 1)")).toBe(true)
		end)

		it("aucun filtre : chaque fichier dans son processus, comptes additionnés, code 1", function()
			local code, counts = run()
			expect(counts).toBe("3 réussis, 1 échoués, 3 specs non chargées")
			expect(code).toBe(1)
		end)

		it("mêmes comptes et même code qu'à un seul processus", function()
			for _, name in { "ok", "fail" } do
				local code1, counts1 = run("--single-process", name)
				local codeN, countsN = run("--isolate", name)
				expect(counts1 ~= nil).toBe(true)
				expect(countsN).toBe(counts1)
				expect(codeN).toBe(code1)
			end
		end)

		it("un chemin complet ne désigne que ce fichier", function()
			local code, counts = run(DIR .. "/ok.spec.luau")
			expect(counts).toBe("2 réussis, 0 échoués, 0 specs non chargées")
			expect(code).toBe(0)
		end)
	end)
end
