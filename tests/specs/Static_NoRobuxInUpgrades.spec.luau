--!nocheck
-- Static_NoRobuxInUpgrades (lot B2, étape 2 ; GDD v2.0 §10.8 règle 16 « aucun Robux dans l'écran
-- Améliorations », docs/04 §27.8) : l'écran, sa carte unique, son instantané et les aides du HUD
-- qui le servent (Hud/Upgrade*) ne parlent jamais d'argent réel. Interdits hors des commentaires et
-- des chaînes : un require de Config/Monetization, les tables Passes ou Products, promptPurchase,
-- MarketplaceService, et le mot Robux (ou « R$ ») — y compris dans une clé de texte citée. Le
-- lecteur statique (tests/harness/LuauScan) est vérifié ici sur des exemples. Zéro trace.
local fs = require("@lune/fs")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local LuauScan = require("../harness/LuauScan")

	-- Fichiers de l'écran (lot B2) : l'écran, la carte, l'instantané, et chaque Hud/Upgrade*
	local function files(): { string }
		local out = {
			"src/client/UI/Panels/Upgrades.luau",
			"src/client/UI/UpgradeCard.luau",
			"src/client/UI/UpgradeSnapshot.luau",
		}
		for _, name in fs.readDir("src/client/UI/Hud") do
			if string.match(name, "^Upgrade.*%.luau$") then
				table.insert(out, "src/client/UI/Hud/" .. name)
			end
		end
		table.sort(out)
		return out
	end

	-- Interdits du code (commentaires et chaînes retirés)
	local CODE = {
		"Monetization",
		"%f[%w_]Passes%f[^%w_]",
		"%f[%w_]Products%f[^%w_]",
		"[Pp]romptPurchase",
		"MarketplaceService",
		"[Rr]obux",
	}
	-- Interdits des chaînes (clés citées : « common.robux », « R$ »)
	local STRINGS = { "[Rr]obux", "R%$", "[Mm]onetization", "MarketplaceService", "[Pp]romptPurchase" }

	local function forbidden(src)
		local found = {}
		local code = LuauScan.strip(src, false)
		for _, pattern in CODE do
			local s = string.find(code, pattern)
			if s ~= nil then
				table.insert(found, LuauScan.lineOf(code, s) .. " : " .. pattern)
			end
		end
		-- les chaînes seulement (commentaires retirés, chaînes gardées)
		local withStrings = LuauScan.strip(src, true)
		for _, pattern in STRINGS do
			local s = string.find(withStrings, pattern)
			if s ~= nil then
				table.insert(found, LuauScan.lineOf(withStrings, s) .. " : " .. pattern)
			end
		end
		return found
	end

	describe("Static_NoRobuxInUpgrades", function()
		it("le lecteur trouve chaque forme interdite et ignore les commentaires", function()
			local clean = table.concat({
				"-- aucun Robux, ni promptPurchase, ni MarketplaceService (commentaire)",
				"--[[ Monetization.Passes ]]",
				"local x = 1",
			}, "\n")
			expect(#forbidden(clean)).toBe(0)
			for _, bad in
				{
					"local M = require(Shared.Config.Monetization)",
					"local p = M.Passes.DoubleCoins",
					"local q = M.Products.CoinsBig",
					'Widgets.promptPurchase("pass", 1)',
					'local MS = game:GetService("MarketplaceService")',
					'Text.set(l, "common.robux", { price = 99 })',
					'local s = "R$ 99"',
				}
			do
				expect(#forbidden(bad) > 0).toBe(true)
			end
		end)

		it("aucun Robux dans Panels/Upgrades, UpgradeCard, UpgradeSnapshot ni Hud/Upgrade*", function()
			local list = files()
			expect(#list >= 4).toBe(true)
			local problems = {}
			for _, path in list do
				for _, f in forbidden(fs.readFile(path)) do
					table.insert(problems, path .. ":" .. f)
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end)
	end)
end
