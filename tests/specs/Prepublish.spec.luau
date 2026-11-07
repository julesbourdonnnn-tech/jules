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
	local function runWith(monetizationSource, balanceSource)
		local dir = "build/prepublish-test-" .. tostring(math.random(1, 1e9))
		fs.writeDir(dir .. "/scripts")
		fs.writeDir(dir .. "/src/shared/Config")
		fs.writeDir(dir .. "/src/shared/Localization")
		fs.writeFile(dir .. "/scripts/prepublish.luau", fs.readFile("scripts/prepublish.luau"))
		fs.writeFile(dir .. "/src/shared/Config/Monetization.luau", monetizationSource)
		fs.writeFile(
			dir .. "/src/shared/Config/Balance.luau",
			balanceSource or fs.readFile("src/shared/Config/Balance.luau")
		)
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
			-- INT-PREPUBLISH : un article caché (hidden = true) n'est jamais vendu, il est ignoré
			for key, def in Monetization.Passes do
				if def.id == 0 and def.hidden ~= true then
					table.insert(zero, key)
				end
			end
			for key, def in Monetization.Products do
				if def.id == 0 and def.hidden ~= true then
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

		it("INT-PREPUBLISH : articles cachés ignorés (passes et produits)", function()
			local result = runWith([[
local M = {}
M.Passes = {
	A = { id = 7, price = 1, nameKey = "x", descKey = "x", order = 1 },
	SeasonPass = { id = 0, price = 1, nameKey = "x", descKey = "x", order = 2, hidden = true },
}
M.Products = {
	B = { id = 8, price = 1, nameKey = "x", descKey = "x", order = 1 },
	CoinsSmall = { id = 0, price = 1, nameKey = "x", descKey = "x", order = 2, hidden = true },
}
return M
]])
			expect(result.code).toBe(0)
			local out = result.stdout .. result.stderr
			expect(string.find(out, "SeasonPass", 1, true)).toBe(nil)
			expect(string.find(out, "CoinsSmall", 1, true)).toBe(nil)
		end)

		it("INT-PREPUBLISH : publication refusée si Balance.GddValues ~= « 1.3 »", function()
			local shop = [[
local M = {}
M.Passes = { A = { id = 7, price = 1, nameKey = "x", descKey = "x", order = 1 } }
M.Products = {}
return M
]]
			local old = runWith(shop, 'return { GddValues = "1.2" }')
			expect(old.code ~= 0).toBe(true)
			expect(string.find(old.stdout .. old.stderr, "GddValues", 1, true) ~= nil).toBe(true)
			local missing = runWith(shop, "return {}")
			expect(missing.code ~= 0).toBe(true)
			local ok = runWith(shop, 'return { GddValues = "1.3" }')
			expect(ok.code).toBe(0)
		end)
	end)

	describe("scripts/verify-place.luau (INT-PREPUBLISH)", function()
		it("place construite : streaming coupé, curseur virtuel désactivé, ShadowMap", function()
			local roblox = require("@lune/roblox")
			local function placeWith(streaming, cursor, tech)
				local game = roblox.Instance.new("DataModel")
				local ws = game:GetService("Workspace")
				ws.StreamingEnabled = streaming
				game:GetService("StarterGui").VirtualCursorMode = cursor
				game:GetService("Lighting").Technology = tech
				local path = "build/verify-place-test-" .. tostring(math.random(1, 1e9)) .. ".rbxl"
				fs.writeFile(path, roblox.serializePlace(game))
				local r = lune({ "run", "scripts/verify-place", path })
				fs.removeFile(path)
				return r
			end
			local E = roblox.Enum
			local bad = placeWith(true, E.VirtualCursorMode.Enabled, E.Technology.Future)
			expect(bad ~= nil).toBe(true)
			expect(bad.code ~= 0).toBe(true)
			local out = bad.stdout .. bad.stderr
			expect(string.find(out, "StreamingEnabled", 1, true) ~= nil).toBe(true)
			expect(string.find(out, "VirtualCursorMode", 1, true) ~= nil).toBe(true)
			expect(string.find(out, "Technology", 1, true) ~= nil).toBe(true)
			-- réglages justes : plus aucune ligne sur ces trois propriétés (le reste de la structure
			-- manque dans cette place vide)
			local good = placeWith(false, E.VirtualCursorMode.Disabled, E.Technology.ShadowMap)
			local goodOut = good.stdout .. good.stderr
			expect(string.find(goodOut, "StreamingEnabled =", 1, true)).toBe(nil)
			expect(string.find(goodOut, "VirtualCursorMode =", 1, true)).toBe(nil)
			expect(string.find(goodOut, "Technology =", 1, true)).toBe(nil)
		end)

		-- Lot B4 (décision D2, N12, INT-V2-LIGHT) : cible d'éclairage « v2.0 » (--lighting v2.0) : éclairage
		-- unifié réglé explicitement ; Technology n'est plus vérifié. La cible par défaut reste « v1.3 »
		-- (cas ci-dessus) jusqu'à l'étape d'intégration I.
		it(
			"--lighting v2.0 : LightingStyle Soft et PrioritizeLightingQuality false acceptés ; Realistic ou true refusés",
			function()
				local roblox = require("@lune/roblox")
				local E = roblox.Enum
				local function placeWith(style, prioritize, tech, extra)
					local game = roblox.Instance.new("DataModel")
					game:GetService("Workspace").StreamingEnabled = false
					game:GetService("StarterGui").VirtualCursorMode = E.VirtualCursorMode.Disabled
					local lighting = game:GetService("Lighting")
					lighting.LightingStyle = style
					lighting.PrioritizeLightingQuality = prioritize
					lighting.Technology = tech
					local path = "build/verify-place-test-" .. tostring(math.random(1, 1e9)) .. ".rbxl"
					fs.writeFile(path, roblox.serializePlace(game))
					local args = { "run", "scripts/verify-place", path }
					for _, a in extra or { "--lighting", "v2.0" } do
						table.insert(args, a)
					end
					local r = lune(args)
					fs.removeFile(path)
					return r.stdout .. r.stderr
				end
				-- réglages justes (Technology quelconque : plus vérifié en v2.0)
				local good = placeWith(E.LightingStyle.Soft, false, E.Technology.Future)
				expect(string.find(good, "LightingStyle =", 1, true)).toBe(nil)
				expect(string.find(good, "PrioritizeLightingQuality =", 1, true)).toBe(nil)
				expect(string.find(good, "Technology =", 1, true)).toBe(nil)
				expect(string.find(good, "éclairage v2.0", 1, true) ~= nil).toBe(true)
				-- Realistic : refusé ; qualité prioritaire : refusée
				local realistic = placeWith(E.LightingStyle.Realistic, false, E.Technology.ShadowMap)
				expect(
					string.find(
						realistic,
						"LightingStyle = Enum.LightingStyle.Realistic (attendu Soft)",
						1,
						true
					) ~= nil
				).toBe(true)
				local quality = placeWith(E.LightingStyle.Soft, true, E.Technology.ShadowMap)
				expect(
					string.find(quality, "PrioritizeLightingQuality = true (attendu false)", 1, true) ~= nil
				).toBe(true)
				-- l'option peut précéder le chemin ; une cible inconnue est refusée et nommée
				local before = placeWith(E.LightingStyle.Realistic, false, E.Technology.ShadowMap, {})
				expect(string.find(before, "LightingStyle =", 1, true)).toBe(nil) -- sans option : la cible v1.3
				local unknown =
					placeWith(E.LightingStyle.Soft, false, E.Technology.ShadowMap, { "--lighting", "v9" })
				expect(string.find(unknown, "--lighting v9 inconnu", 1, true) ~= nil).toBe(true)
			end
		)
	end)
end
