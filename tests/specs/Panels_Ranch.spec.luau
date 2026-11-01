--!nocheck
-- Panels/Ranch (paquet client-panels) : onglets Enclos, Dodo, Lettres, Fusionner, Vendre, Dalles,
-- Style (GDD §10.3, §4.10, §4.13, §4.14, §5.4 ; docs/04 §13.6, contrat v1.2). Intentions envoyées
-- (SetLock, MoveSquishy, ClaimMail, FuseMenu, FuseAll, Sell, Release, BuyTile, EquipCosmetic), refus
-- sans envoi (son Error, vibration refuse), ○ qui vide d'abord la sélection multiple, Style atteint à
-- la croix, textes EN / FR à 28 px TV. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(profile)
		local h = TvAudit.client({ profile = profile })
		local c = {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Ranch = TvAudit.mod(h, "UI.Panels.Ranch"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
			sounds = {},
			haptics = {},
		}
		local Audio = TvAudit.mod(h, "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		TvAudit.mod(h, "Util.Haptics").Played:Connect(function(name)
			table.insert(c.haptics, name)
		end)
		return c
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sel(c)
		return c.h.game.GuiService.SelectedObject
	end

	local function press(c, obj)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = obj
		c.h:settle(1)
		Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
		c.h:settle(1)
	end

	-- maintien de ✕ sur un bouton à maintenir (horloge du jeu avancée de `seconds`)
	local function hold(c, obj, seconds)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = obj
		c.h:settle(1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		c.Clock.advance(seconds)
		c.h:step(1 / 60, 2)
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		c.h:settle(1)
	end

	local function refused(c)
		return table.find(c.sounds, "Error") ~= nil and table.find(c.haptics, "refuse") ~= nil
	end

	local function sq(s, opts)
		return TvAudit.squishy(s, opts)
	end

	describe("Panels/Ranch › onglets et Enclos", function()
		it(
			"onglets dans l'ordre du contrat ; la fiche d'un squishy : verrou, ○ revient à la case",
			function()
				local c = setup({ squishies = { a = sq(1, { z = 500 }), b = sq(2, { z = 900 }) } })
				expect(c.Ranch.tabs()).toEqual({ "pens", "dodo", "mail", "fuse", "sell", "pads", "style" })
				c.PC.open("Ranch", "pens")
				local cellB = c.Ranch._cellFor("b") -- le plus gros d'abord (tri par taille)
				expect(sel(c)).toBe(cellB)
				press(c, cellB)
				expect(c.Ranch._state().detail).toBe(true)
				press(c, c.Ranch._button("lock"))
				expect(TvAudit.sent(c.h, "SetLock")[1][1]).toBe("b")
				expect(TvAudit.sent(c.h, "SetLock")[1][2]).toBe(true)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.Ranch._state().detail).toBe(false)
				expect(sel(c)).toBe(cellB)
				expect(c.PC.current()).toBe("Ranch")
				clean(c)
			end
		)

		it(
			"Monture refusée sans selle (rien n'est envoyé) ; Meilleur Ami selon les places débloquées",
			function()
				local c = setup({ squishies = { a = sq(1) }, R = 3, biggestEver = 0 })
				c.PC.open("Ranch", "pens")
				press(c, c.Ranch._cellFor("a"))
				press(c, c.Ranch._button("mount"))
				expect(#TvAudit.sent(c.h, "SetMount")).toBe(0)
				expect(refused(c)).toBe(true)
				expect(c.Ranch._button("bf2").Visible).toBe(true) -- R = 3 : 2 places
				expect(c.Ranch._button("bf3").Visible).toBe(false)
				press(c, c.Ranch._button("bf2"))
				local args = TvAudit.sent(c.h, "SetBestFriend")[1]
				expect(args[1]).toBe("a")
				expect(args[2]).toBe(2)
				clean(c)
			end
		)
	end)

	describe("Panels/Ranch › Dodo, Lettres", function()
		it("Dodo : ✕ ramène dans l'enclos ; enclos pleins : refusé sans envoi", function()
			local squishies = { d = sq(3, { at = "dodo" }) }
			local c = setup({ squishies = squishies })
			c.PC.open("Ranch", "dodo")
			press(c, c.Ranch._cellFor("d"))
			local args = TvAudit.sent(c.h, "MoveSquishy")[1]
			expect(args[1]).toBe("d")
			expect(args[2]).toBe("pen")
			-- 4 places d'enclos au départ : pleines
			local full = { d = sq(3, { at = "dodo" }) }
			for i = 1, 4 do
				full["p" .. i] = sq(1)
			end
			local c2 = setup({ squishies = full })
			c2.PC.open("Ranch", "dodo")
			press(c2, c2.Ranch._cellFor("d"))
			expect(#TvAudit.sent(c2.h, "MoveSquishy")).toBe(0)
			expect(refused(c2)).toBe(true)
			clean(c)
			clean(c2)
		end)

		it("Lettres : ✕ prend le cadeau (ClaimMail)", function()
			local c = setup({ squishies = { m = sq(4, { at = "mail" }) } })
			c.PC.open("Ranch", "mail")
			press(c, c.Ranch._cellFor("m"))
			expect(TvAudit.sent(c.h, "ClaimMail")[1][1]).toBe("m")
			clean(c)
		end)
	end)

	describe("Panels/Ranch › Fusionner", function()
		it(
			"« Choisir A » par défaut ; B seulement parmi les jumeaux de A ; ○ efface le choix de A",
			function()
				local c = setup({
					squishies = {
						a = sq(1, { st = 1, z = 300 }),
						b = sq(1, { st = 1, z = 200 }),
						x = sq(2, { z = 100 }),
					},
				})
				c.PC.open("Ranch", "fuse")
				expect(sel(c)).toBe(c.Ranch._button("chooseA"))
				press(c, c.Ranch._cellFor("a"))
				expect(c.Ranch._state().fuseA).toBe("a")
				press(c, c.Ranch._cellFor("x")) -- pas un jumeau : refusé
				expect(#TvAudit.sent(c.h, "FuseMenu")).toBe(0)
				expect(refused(c)).toBe(true)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.Ranch._state().fuseA).toBe("")
				expect(c.PC.current()).toBe("Ranch")
				press(c, c.Ranch._cellFor("a"))
				press(c, c.Ranch._cellFor("b"))
				local args = TvAudit.sent(c.h, "FuseMenu")[1]
				expect(args[1]).toBe("a")
				expect(args[2]).toBe("b")
				press(c, c.Ranch._button("fuseAll"))
				expect(#TvAudit.sent(c.h, "FuseAll")).toBe(1)
				clean(c)
			end
		)

		it("Tout fusionner sans aucune paire de jumeaux : refusé sans envoi", function()
			local c = setup({ squishies = { a = sq(1), b = sq(2) } })
			c.PC.open("Ranch", "pens")
			press(c, c.Ranch._button("mergeAll"))
			expect(#TvAudit.sent(c.h, "FuseAll")).toBe(0)
			expect(refused(c)).toBe(true)
			clean(c)
		end)
	end)

	describe("Panels/Ranch › Vendre / Relâcher", function()
		it("sélection multiple ; ○ vide d'abord la sélection, puis remonte au menu", function()
			local c = setup({ squishies = { a = sq(1, { z = 300 }), b = sq(2, { z = 200 }) } })
			c.PC.open("Ranch", "sell")
			press(c, c.Ranch._cellFor("a"))
			press(c, c.Ranch._cellFor("b"))
			expect(#c.Ranch._state().selected).toBe(2)
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
			expect(#c.Ranch._state().selected).toBe(0)
			expect(c.PC.current()).toBe("Ranch") -- le premier ○ n'a fait que vider la sélection
			TvAudit.tick(c.h, 0.5)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
			expect(c.PC.current()).toBeNil()
			expect(#TvAudit.sent(c.h, "Sell")).toBe(0)
			clean(c)
		end)

		it("Communs : vendus d'un appui ; Meilleur Ami et verrouillé : refusés à la sélection", function()
			local c = setup({
				squishies = {
					a = sq(1, { z = 300 }),
					f = sq(1, { bf = 1, z = 200 }),
					l = sq(2, { lk = true, z = 100 }),
				},
			})
			c.PC.open("Ranch", "sell")
			press(c, c.Ranch._cellFor("f"))
			press(c, c.Ranch._cellFor("l"))
			expect(#c.Ranch._state().selected).toBe(0)
			expect(refused(c)).toBe(true)
			press(c, c.Ranch._cellFor("a"))
			hold(c, c.Ranch._button("sell"), 0.1)
			local args = TvAudit.sent(c.h, "Sell")[1]
			expect(args[1]).toEqual({ "a" })
			expect(args[2]).toBe(false)
			clean(c)
		end)

		it(
			"Épique ou mutation Doré : maintien 0,6 s puis 2e étape « 1 sur X », envoi confirmé",
			function()
				-- espèce 13 : Épique (Config/Species) ; mutation 4 : Doré (×5)
				local c = setup({ squishies = { e = sq(13, { z = 300 }), g = sq(1, { m = 4, z = 200 }) } })
				c.PC.open("Ranch", "sell")
				press(c, c.Ranch._cellFor("e"))
				press(c, c.Ranch._cellFor("g"))
				-- relâché trop tôt : rien
				hold(c, c.Ranch._button("sell"), 0.3)
				expect(c.Ranch._state().overlay).toBe("")
				hold(c, c.Ranch._button("sell"), 0.7)
				expect(c.Ranch._state().overlay).toBe("confirm")
				expect(#TvAudit.sent(c.h, "Sell")).toBe(0)
				-- ○ annule la 2e étape
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.Ranch._state().overlay).toBe("")
				expect(#c.Ranch._state().selected).toBe(2)
				hold(c, c.Ranch._button("release"), 0.7)
				expect(c.Ranch._state().overlay).toBe("confirm")
				hold(c, c.Ranch._button("overlay"), 0.7)
				local args = TvAudit.sent(c.h, "Release")[1]
				table.sort(args[1])
				expect(args[1]).toEqual({ "e", "g" })
				expect(args[2]).toBe(true)
				clean(c)
			end
		)

		it("Ranger : aperçu des Communs en double (le plus gros gardé), maintien, puis Sell", function()
			local mut = table.create(26, 0)
			mut[1] = 1 -- espèce 1 tamponnée
			local c = setup({
				squishies = {
					big = sq(1, { z = 900 }),
					small = sq(1, { z = 100 }),
					star = sq(1, { z = 50, st = 1 }),
					other = sq(2, { z = 10 }), -- espèce 2 non tamponnée : gardée
				},
				dex = { mut = mut, stars = table.create(26, 0), fam = table.create(7, 0), rewards = 0 },
			})
			c.PC.open("Ranch", "pens")
			press(c, c.Ranch._button("tidy"))
			expect(c.Ranch._state().overlay).toBe("tidy")
			hold(c, c.Ranch._button("overlay"), 0.7)
			local args = TvAudit.sent(c.h, "Sell")[1]
			expect(args[1]).toEqual({ "small" })
			expect(args[2]).toBe(false)
			clean(c)
		end)
	end)

	describe("Panels/Ranch › Dalles", function()
		it(
			"la moins chère achetable par défaut ; trop chère : refusée sans envoi ; gardées d'abord",
			function()
				local c = setup({ coins = 100, R = 0 })
				c.PC.open("Ranch", "pads")
				-- Tapis à Goûter niveau 0 : 20 pièces (Balance.Tiles.snack)
				expect(sel(c)).toBe(c.Ranch._tileButton("snack"))
				press(c, c.Ranch._tileButton("snack"))
				expect(TvAudit.sent(c.h, "BuyTile")[1][1]).toBe("snack")
				press(c, c.Ranch._tileButton("pens")) -- 1 200 pièces
				expect(#TvAudit.sent(c.h, "BuyTile")).toBe(1)
				expect(refused(c)).toBe(true)
				press(c, c.Ranch._tileButton("cozyBed")) -- R minimal 3 : verrouillé
				expect(#TvAudit.sent(c.h, "BuyTile")).toBe(1)
				-- depuis l'aperçu du Grand Splorch : Enclos et Lit douillet d'abord
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Ranch", "padsKept")
				expect(c.Ranch._state().keptFirst).toBe(true)
				expect(c.Ranch._tileButton("pens").LayoutOrder < c.Ranch._tileButton("snack").LayoutOrder).toBe(
					true
				)
				expect(c.Ranch._tileButton("cozyBed").LayoutOrder < c.Ranch._tileButton("decor").LayoutOrder).toBe(
					true
				)
				clean(c)
			end
		)
	end)

	describe("Panels/Ranch › Style", function()
		it(
			"Style atteint à la croix ; équiper ; « Aucun » pour retirer ; verrouillé refusé sans envoi",
			function()
				local c = setup({
					cosmetics = {
						saddle = "classic",
						trail = "pinkBubbles",
						title = "",
						theme = "color",
						flag = "",
					},
					plopDays = 5,
				})
				c.PC.open("Ranch", "pens")
				-- croix ↑ vers les onglets, → jusqu'à Style, ✕
				local tabs = c.PC.window("Ranch").Body.Tabs.Strip
				local guard = 0
				while sel(c) ~= tabs.Tab_style and guard < 12 do
					guard += 1
					if sel(c):IsDescendantOf(tabs) then
						Gamepad.tap(c.h, Enum.KeyCode.DPadRight)
					else
						Gamepad.tap(c.h, Enum.KeyCode.DPadUp)
					end
				end
				expect(sel(c)).toBe(tabs.Tab_style)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.Ranch.currentTab()).toBe("style")
				-- par défaut (rouvert) : l'objet équipé de la 1re sous-liste (Selle)
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Ranch", "style")
				expect(sel(c)).toBe(c.Ranch._styleCell("saddle", "classic"))
				press(c, c.Ranch._styleCell("saddle", "peach")) -- Plop jour 3 : débloquée
				local args = TvAudit.sent(c.h, "EquipCosmetic")[1]
				expect(args[1]).toBe("saddle")
				expect(args[2]).toBe("peach")
				press(c, c.Ranch._styleCell("saddle", "royal")) -- pass Selles et Traînées : verrouillée
				expect(#TvAudit.sent(c.h, "EquipCosmetic")).toBe(1)
				expect(refused(c)).toBe(true)
				press(c, c.Ranch._styleKindButton("trail"))
				press(c, c.Ranch._styleCell("trail", ""))
				args = TvAudit.sent(c.h, "EquipCosmetic")[2]
				expect(args[1]).toBe("trail")
				expect(args[2]).toBe("")
				-- ○ : des objets à la liste des sous-listes, puis au menu
				press(c, c.Ranch._styleCell("trail", "pinkBubbles"))
				c.h.game.GuiService.SelectedObject = c.Ranch._styleCell("trail", "pinkBubbles")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(sel(c)).toBe(c.Ranch._styleKindButton("trail"))
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBeNil()
				clean(c)
			end
		)

		it(
			"tenue possédée → OutfitPreview (empilé) ; textes EN / FR à 28 px TV, ni chevauchement",
			function()
				local c =
					setup({ outfits = { owned = { plopBib = 1 }, worn = {} }, squishies = { a = sq(1) } })
				c.PC.open("Ranch", "style")
				press(c, c.Ranch._styleKindButton("outfits"))
				press(c, c.Ranch._styleCell("outfit", "plopBib"))
				expect(c.PC.current()).toBe("OutfitPreview")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Ranch")
				local issues = {}
				for _, lang in { "en", "fr" } do
					TvAudit.setLanguage(c.h, lang)
					for _, kind in { "saddle", "trail", "title", "theme", "flag", "outfits" } do
						press(c, c.Ranch._styleKindButton(kind))
						for _, issue in TvAudit.check(c.h, `[{lang} {kind}] `) do
							table.insert(issues, issue)
						end
					end
				end
				expect(table.concat(issues, "\n")).toBe("")
				clean(c)
			end
		)
	end)

	describe("Panels/Ranch › données abîmées", function()
		it(
			"squishies invalides (types, NaN, lieux inconnus) : aucun plantage, rien d'affiché pour eux",
			function()
				local c = setup({
					squishies = {
						ok = sq(1),
						bad1 = "chaîne",
						bad2 = { s = "x", z = 0 / 0, at = "pen" },
						bad3 = { s = 999, at = "lune" },
						[5] = sq(2),
					},
					tiles = "rien",
					passes = 7,
				})
				for _, tab in c.Ranch.tabs() do
					c.PC.open("Ranch", tab)
					TvAudit.tick(c.h, 0.5)
				end
				clean(c)
			end
		)
	end)
end
