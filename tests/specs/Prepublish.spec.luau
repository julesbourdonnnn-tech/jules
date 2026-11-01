--!nocheck
-- scripts/prepublish.luau (Comet Conga, finition « data-publish ») : contrôle du propriétaire avant
-- publication. Boutique vide (modèle du socle) : code 0 ; un article à id 0 : code 1, l'article est
-- nommé, avec la marche à suivre (Creator Hub) ; un id en double ou invalide : code 1.
local fs = require("@lune/fs")
local process = require("@lune/process")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	-- même exécutable que la suite (PATH de scripts/check.sh : ~/.cargo/bin, ~/.rokit/bin)
	local function lune(args)
		local home = process.env.HOME
		local candidates = { "lune" }
		if home then
			table.insert(candidates, 1, home .. "/.rokit/bin/lune")
			table.insert(candidates, 1, home .. "/.cargo/bin/lune")
		end
		for _, program in candidates do
			local ok, r = pcall(process.exec, program, args)
			if ok then
				return r
			end
		end
		return nil
	end

	-- Copie du script dans un dossier temporaire avec une configuration de boutique donnée
	local function runWith(monetizationSource)
		local dir = "build/prepublish-test-" .. tostring(math.random(1, 1e9))
		fs.writeDir(dir .. "/scripts")
		fs.writeDir(dir .. "/src/shared/Config")
		fs.writeDir(dir .. "/src/shared/Localization")
		fs.writeFile(dir .. "/scripts/prepublish.luau", fs.readFile("scripts/prepublish.luau"))
		fs.writeFile(dir .. "/src/shared/Config/Monetization.luau", monetizationSource)
		fs.writeFile(
			dir .. "/src/shared/Localization/Strings.luau",
			fs.readFile("src/shared/Localization/Strings.luau")
		)
		local result = lune({ "run", dir .. "/scripts/prepublish" })
		fs.removeDir(dir)
		return result
	end

	describe("scripts/prepublish.luau", function()
		it("boutique du dépôt : le script tourne et répond selon les ids", function()
			local Monetization = require("../../src/shared/Config/Monetization")
			local zero = {}
			for key, def in Monetization.Passes do
				if def.id == 0 then
					table.insert(zero, key)
				end
			end
			for key, def in Monetization.Products do
				if def.id == 0 then
					table.insert(zero, key)
				end
			end
			local result = lune({ "run", "scripts/prepublish" })
			expect(result ~= nil).toBe(true)
			if #zero == 0 then
				expect(result.code).toBe(0)
			else
				expect(result.code ~= 0).toBe(true)
				local out = result.stdout .. result.stderr
				for _, key in zero do
					expect({ key = key, listed = string.find(out, key, 1, true) ~= nil }).toEqual({
						key = key,
						listed = true,
					})
				end
			end
		end)

		it("article à id 0 : refus qui le nomme ; id en double : refus ; tout rempli : prêt", function()
			local missing = runWith([[
local M = {}
M.Passes = { AutoPot = { id = 0, price = 149, nameKey = "x", descKey = "x", order = 1 } }
M.Products = { CoinPack = { id = 555, price = 49, nameKey = "x", descKey = "x", order = 1 } }
return M
]])
			expect(missing ~= nil).toBe(true)
			expect(missing.code ~= 0).toBe(true)
			local out = missing.stdout .. missing.stderr
			expect(string.find(out, "AutoPot", 1, true) ~= nil).toBe(true)
			expect(string.find(out, "Creator Hub", 1, true) ~= nil).toBe(true)
			local dup = runWith([[
local M = {}
M.Passes = { A = { id = 7, price = 1, nameKey = "x", descKey = "x", order = 1 } }
M.Products = { B = { id = 7, price = 1, nameKey = "x", descKey = "x", order = 1 } }
return M
]])
			expect(dup.code ~= 0).toBe(true)
			expect(string.find(dup.stdout .. dup.stderr, "déjà utilisé", 1, true) ~= nil).toBe(true)
			local ready = runWith([[
local M = {}
M.Passes = { A = { id = 7, price = 1, nameKey = "x", descKey = "x", order = 1 } }
M.Products = { B = { id = 8, price = 1, nameKey = "x", descKey = "x", order = 1 } }
return M
]])
			expect(ready.code).toBe(0)
		end)
	end)
end
