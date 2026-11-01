--!nocheck
-- Panels/Shop (paquet client-panels ; GDD §8, §10.3 ; docs/04 §13.6, contrat v1.2) : onglets Passes /
-- Fête / Tenues, articles `hidden` ou à l'id 0 absents (CoinsSmall, CoinsBig, SeasonPass), onglet
-- absent sans article, cachée < 10 min, bouton Squish Party caché pendant une fête, aucune règle
-- PolicyService, ClientEvent("shopOpened") à CHAQUE ouverture, UiSeen("shop") une fois, invite d'achat
-- sous pcall avec la sélection tenue pendant la fenêtre de Roblox, aperçu 3D d'une tenue. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function playStats(seconds)
		local stats = TvAudit.defaults().stats
		stats.playSeconds = seconds
		return stats
	end

	local function setup(opts)
		opts = opts or {}
		local h = TvAudit.client({
			before = opts.before or TvAudit.enableShop,
			profile = opts.profile or { stats = playStats(700) },
		})
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Shop = TvAudit.mod(h, "UI.Panels.Shop"),
			FG = TvAudit.mod(h, "UI.FocusGuard"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	describe("Panels/Shop", function()
		it("onglets Passes / Fête / Tenues ; articles cachés absents même avec un identifiant", function()
			local c = setup()
			expect(c.Shop.tabs()).toEqual({ "passes", "party", "outfits" })
			expect(c.Shop._itemKeys("passes")).toEqual({
				"AutoPot",
				"DoubleCoins",
				"BigRanch",
				"SaddlesTrails",
			})
			expect(c.Shop._itemKeys("party")).toEqual({ "SquishParty" })
			expect(c.Shop._itemKeys("outfits")).toEqual({ "OutfitSweater", "OutfitCrown", "OutfitWinter" })
			c.PC.open("Shop", "party")
			local strip = c.PC.window("Shop").Body.Tabs.Strip
			expect(strip.Tab_party.Label.Text).toBe("Party")
			TvAudit.setLanguage(c.h, "fr")
			expect(strip.Tab_party.Label.Text).toBe("Fête")
			expect(c.Shop._buyButton("CoinsSmall")).toBeNil()
			expect(c.Shop._buyButton("CoinsBig")).toBeNil()
			expect(c.Shop._buyButton("SeasonPass")).toBeNil()
			clean(c)
		end)

		it(
			"cachée les 10 premières minutes ; sans aucun article vendu (ids à 0), jamais visible",
			function()
				local c = setup({ profile = { stats = playStats(599) } })
				expect(c.Shop.visible()).toBe(false)
				local c2 = setup({
					before = function() end,
					profile = { stats = playStats(5000) },
				})
				expect(c2.Shop.visible()).toBe(false)
				expect(c2.Shop.tabs()).toEqual({})
				-- un seul article vendu : seul son onglet existe
				local c3 = setup({
					before = function(h)
						h:require("ReplicatedStorage.Shared.Config.Monetization").Products.OutfitCrown.id = 77
					end,
					profile = { stats = playStats(5000) },
				})
				expect(c3.Shop.visible()).toBe(true)
				expect(c3.Shop.tabs()).toEqual({ "outfits" })
				clean(c)
				clean(c2)
				clean(c3)
			end
		)

		it('ClientEvent("shopOpened") à chaque ouverture ; UiSeen("shop") une seule fois', function()
			local c = setup()
			for _ = 1, 3 do
				c.PC.open("Shop")
				TvAudit.tick(c.h, 0.5)
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
			end
			local opened = 0
			for _, args in TvAudit.sent(c.h, "ClientEvent") do
				if args[1] == "shopOpened" then
					opened += 1
				end
			end
			-- débit client de ClientEvent : 1 / 5 s (Config/Intents) ; l'horloge avance de 1 s par tour
			expect(opened >= 1).toBe(true)
			local seen = 0
			for _, args in TvAudit.sent(c.h, "UiSeen") do
				if args[1] == "shop" then
					seen += 1
				end
			end
			expect(seen).toBe(1)
			-- ouvertures espacées de plus de 5 s : chacune envoie son ClientEvent
			local c2 = setup()
			for _ = 1, 3 do
				c2.PC.open("Shop")
				TvAudit.tick(c2.h, 6)
				c2.PC.closeAll()
				TvAudit.tick(c2.h, 0.5)
			end
			local n = 0
			for _, args in TvAudit.sent(c2.h, "ClientEvent") do
				if args[1] == "shopOpened" then
					n += 1
				end
			end
			expect(n).toBe(3)
			clean(c)
			clean(c2)
		end)

		it(
			"1er « Acheter » sélectionné ; invite de Roblox, sélection tenue puis rendue à la fermeture",
			function()
				local c = setup()
				c.PC.open("Shop", "passes")
				local buy = c.Shop._buyButton("AutoPot")
				expect(sel(c)).toBe(buy)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(#c.h.log.prompts).toBe(1)
				expect(c.h.log.prompts[1].kind).toBe("pass")
				expect(c.FG.held()).toBe(true)
				c.h.game.GuiService.SelectedObject = nil
				c.h.game.MarketplaceService.PromptGamePassPurchaseFinished:Fire(c.h.localPlayer, 1001, false)
				c.h:settle(2)
				expect(c.FG.held()).toBe(false)
				expect(sel(c)).toBe(buy)
				-- pass possédé : « Possédé », refusé sans invite
				local c2 = setup({ profile = { stats = playStats(700), passes = { AutoPot = true } } })
				c2.PC.open("Shop", "passes")
				local owned = c2.Shop._buyButton("AutoPot")
				expect(owned.Label.Text).toBe("Owned")
				TvAudit.tick(c2.h, 0.5)
				c2.h.game.GuiService.SelectedObject = owned
				Gamepad.tap(c2.h, Enum.KeyCode.ButtonA)
				expect(#c2.h.log.prompts).toBe(0)
				clean(c)
				clean(c2)
			end
		)

		it(
			"Squish Party : bouton caché pendant une fête, « n sur 3 aujourd'hui », case Montrer mon nom",
			function()
				local c = setup()
				local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
				local Clock = c.h:require("ReplicatedStorage.Shared.Util.Clock")
				local party = false
				WSC.event = function()
					return {
						boost = {
							kind = if party then "squish" else "",
							untilT = Clock.now() + 300,
							byName = "",
						},
					}
				end
				c.PC.open("Shop", "party")
				local buy = c.Shop._buyButton("SquishParty")
				expect(buy.Visible).toBe(true)
				local card = buy.Parent
				expect(card.State.Text).toBe("3 of 3 today")
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				party = true
				c.PC.open("Shop", "party")
				expect(buy.Visible).toBe(false)
				expect(card.State.Text).toBe("Party in progress")
				-- Montrer mon nom : SetSetting partyShowName
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = card.ShowName.Toggle
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				local args = TvAudit.sent(c.h, "SetSetting")[1]
				expect(args[1]).toBe("partyShowName")
				expect(args[2]).toBe(true)
				clean(c)
			end
		)

		it("Tenues : « Aperçu » ouvre l'aperçu 3D (empilé) ; ○ revient à la Boutique", function()
			local c = setup({ profile = { stats = playStats(700), squishies = { a = TvAudit.squishy(1) } } })
			c.PC.open("Shop", "outfits")
			local preview = c.Shop._buyButton("OutfitSweater").Parent.Preview
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = preview
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.PC.current()).toBe("OutfitPreview")
			expect(TvAudit.mod(c.h, "UI.Panels.OutfitPreview")._state().outfit).toBe("sweater")
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
			expect(c.PC.current()).toBe("Shop")
			expect(sel(c)).toBe(preview)
			clean(c)
		end)
	end)
end
