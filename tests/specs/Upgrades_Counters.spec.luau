--!nocheck
-- Upgrades_Counters (lot B2, étape 2 ; docs/04 §27.8 règles 3 et 4 ; GDD v2.0 §10.8) : un compteur
-- ne repart jamais de 0 et sa valeur finale est toujours posée.
--   * 50 changements d'onglet (L1 / R1 et ✕ sur un onglet), pendant que les pièces montent (un
--     instantané tous les 5 changements) : à aucune image un nombre montré ne vaut 0 alors que sa
--     valeur stable n'est pas 0 (en-tête, niveaux, prix, avant → après) ;
--   * les pièces de l'en-tête ne descendent jamais pendant qu'elles montent ; à la fin, la valeur
--     exacte de l'instantané est écrite (BigNumber) ;
--   * à l'ouverture, le compteur part de la vraie valeur (jamais de 0).
-- Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	-- Textes visibles de l'écran (chemin → texte)
	local function texts(c)
		local out = {}
		local win = c.PC.window("Upgrades")
		for _, d in win:GetDescendants() do
			if d:IsA("TextLabel") and d.Text ~= "" then
				local shown = true
				local cur = d
				while cur and cur ~= win do
					if cur:IsA("GuiObject") and not cur.Visible then
						shown = false
						break
					end
					cur = cur.Parent
				end
				if shown then
					out[d:GetFullName()] = d.Text
				end
			end
		end
		return out
	end

	local function isZero(text)
		return string.match(text, "^%s*0%s*$") ~= nil or string.match(text, "^0/") ~= nil
	end

	describe("Upgrades_Counters › jamais 0 en passant, valeur finale posée", function()
		it(
			"50 changements d'onglet pendant que les pièces montent : aucun nombre à 0 en passant",
			function()
				local coins = 1234567
				local c = S.client({
					snap = S.snap(1, function(p)
						p.coins = coins
					end),
				})
				S.open(c, "suggested")
				local BN = c.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
				local coinsLabel = c.PC.window("Upgrades").Body.Coins
				-- ouverture : la vraie valeur tout de suite (jamais un départ de 0)
				expect(coinsLabel.Text).toBe(BN.abbreviate(coins, "en"))
				-- valeurs stables de chaque onglet (référence : un nombre stable à 0 est permis)
				local steady = {}
				for _, tab in { "suggested", "ranch", "helpers", "workshop" } do
					c.Up.setTab(tab)
					TvAudit.tick(c.h, 1)
					for path, text in texts(c) do
						steady[path] = text
					end
				end
				c.Up.setTab("suggested")
				TvAudit.tick(c.h, 1)
				local version = 1
				local lastCoins = coins
				local problems = {}
				for i = 1, 50 do
					if i % 5 == 0 then
						version += 1
						coins = coins * 1.5
						S.patch(
							c,
							S.snap(version, function(p)
								p.coins = coins
							end)
						)
					end
					if i % 2 == 0 then
						Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
					else
						c.Up.setTab(({ "suggested", "ranch", "helpers", "workshop" })[i % 4 + 1])
					end
					for _ = 1, 4 do
						c.Clock.advance(0.05)
						c.h:step(0.05, 1)
						for path, text in texts(c) do
							if isZero(text) and steady[path] ~= nil and not isZero(steady[path]) then
								table.insert(problems, string.format("%d : %s = « %s »", i, path, text))
							end
						end
						local shown = c.Up._counter("coins")
						if shown == nil or shown <= 0 then
							table.insert(problems, string.format("%d : compteur des pièces vide ou à 0", i))
						elseif shown < lastCoins then
							table.insert(
								problems,
								string.format("%d : pièces en baisse (%s)", i, coinsLabel.Text)
							)
						else
							lastCoins = shown
						end
					end
				end
				-- valeur finale exacte
				TvAudit.tick(c.h, 1)
				expect(coinsLabel.Text).toBe(BN.abbreviate(coins, "en"))
				expect(table.concat(problems, "\n")).toBe("")
				S.clean(c, expect)
			end
		)

		it("compteur interrompu (fermeture en cours) : la valeur finale est posée, jamais 0", function()
			local c = S.client({
				snap = S.snap(1, function(p)
					p.coins = 1000
				end),
			})
			S.open(c, "ranch")
			local BN = c.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
			local label = c.PC.window("Upgrades").Body.Coins
			S.patch(
				c,
				S.snap(2, function(p)
					p.coins = 5e9
				end)
			)
			c.Clock.advance(0.1)
			c.h:step(0.1, 1)
			-- fermé en plein compte : écrit tout de suite à sa valeur finale
			c.PC.closeAll()
			expect(label.Text).toBe(BN.abbreviate(5e9, "en"))
			TvAudit.tick(c.h, 1)
			S.open(c, "ranch")
			expect(label.Text).toBe(BN.abbreviate(5e9, "en"))
			S.clean(c, expect)
		end)
	end)
end
