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

	describe("Panels/Ranch › glyphes dessinés (règle 18, lot B3)", function()
		it(
			"cœur des jumeaux, pastille du Meilleur Ami (cœur + nombre) et coche de la case choisie dessinés ; aucun « ♥ » ni « ✓ » écrit",
			function()
				local c = setup({
					squishies = {
						a = sq(1, { z = 50 }),
						b = sq(1, { z = 40 }),
						best = sq(2, { z = 900, bf = 1 }),
					},
				})
				c.PC.open("Ranch", "pens")
				TvAudit.tick(c.h, 0.5)
				local cellA = c.Ranch._cellFor("a")
				expect(cellA.Mark:GetAttribute("Icon")).toBe("heart")
				local cellBest = c.Ranch._cellFor("best")
				expect(cellBest.Mark:GetAttribute("Icon")).toBe("")
				expect(cellBest.BestFriend.Visible).toBe(true)
				expect(cellBest.BestFriend.Text).toBe("1")
				expect(cellBest.BestFriend.Heart:GetAttribute("Icon")).toBe("heart")
				-- le cœur est dans le retrait de la pastille, jamais sur le nombre (les enfants d'un libellé
				-- à UIPadding sont posés dans la zone du texte : captures de l'étape 3, cœur sur le « 1 »)
				local Layout = require("../harness/Layout")
				Layout.apply(c.h)
				local pill = Layout.rect(cellBest.BestFriend)
				local heart = Layout.rect(cellBest.BestFriend.Heart)
				local textLeft = pill.x + cellBest.BestFriend.UIPadding.PaddingLeft.Offset
				expect(heart.x >= pill.x and heart.x + heart.w <= textLeft).toBe(true)
				-- Vendre : la case choisie porte la coche (même toile, plus grande, à gauche)
				c.Ranch.setTab("sell")
				TvAudit.tick(c.h, 0.5)
				press(c, c.Ranch._cellFor("a"))
				expect(c.Ranch._cellFor("a").Mark:GetAttribute("Icon")).toBe("check")
				expect(c.Ranch._cellFor("b").Mark:GetAttribute("Icon")).toBe("heart")
				for _, d in c.PC.window("Ranch"):GetDescendants() do
					if d:IsA("TextLabel") or d:IsA("TextButton") then
						expect(
							string.find(d.Text, "♥", 1, true) == nil
								and string.find(d.Text, "✓", 1, true) == nil
						).toBe(true)
					end
				end
				clean(c)
			end
		)
	end)

	describe("Panels/Ranch › v2.0 (lot B3)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local Layout = require("../harness/Layout")
		local S = UpgradeScreen.new(T.Harness)
		local V2 = UpgradeScreen.V2_ALL
		local Cosmetics = T.Harness.new():require("ReplicatedStorage.Shared.Config.Cosmetics")
		local DECO = "1,0,0,0,0,0,0,0,0,0,0,0" -- Fanion à ton nom posé sur l'emplacement 1 (petit)

		-- profil v2 riche : Record R 30, A = 3, palettes Bonbon et Menthe (Atelier), selle Biscuit
		-- (piste), 600 niveaux (Carnet), géant 2e15, Fanion (5 min de jeu), Gamelle (8 jours de Plop)…
		local function richProfile(edit)
			local p = {
				version = 2,
				R = 30,
				bestR = 30,
				ascend = 3,
				cosmetics = {
					saddle = "classic",
					trail = "",
					title = "",
					theme = "color",
					flag = "",
					palette = "candy",
					cushions = "",
				},
				outfits = { owned = { plopBib = 1, partyHat = 1 }, worn = {} },
				atelierCosmetics = { 3 },
				stats = { upgradesBought = 600, playSeconds = 400, objectivesClaimed = 30, tracksDone = 1 },
				weeklyTrack = { won = { 1 } },
				biggestEver = 2e15,
				season = { frostDays = 0 },
				plopDays = 8,
				moon = { sessions = 1 },
				decoPerso = { owned = { 0, 0 }, slots = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
				squishies = { a = sq(1) },
			}
			if edit then
				edit(p)
			end
			return p
		end

		local function v2client(opts)
			opts = opts or {}
			local c = S.client({
				snap = if opts.snap == false then nil else S.snap(1),
				profile = richProfile(opts.edit),
				ranch = opts.ranch or { DecoPerso = DECO },
			})
			if opts.flags ~= false then
				S.event(c, opts.flags or V2)
			end
			c.Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
			c.OP = TvAudit.mod(c.h, "UI.Panels.OutfitPreview")
			c.sounds, c.haptics = {}, {}
			local Audio = TvAudit.mod(c.h, "Controllers.AudioController")
			local play = Audio.play
			Audio.play = function(name, ...)
				table.insert(c.sounds, name)
				return play(name, ...)
			end
			TvAudit.mod(c.h, "Util.Haptics").Played:Connect(function(name)
				table.insert(c.haptics, name)
			end)
			return c
		end

		-- arguments du i-ème envoi de `remote` (sans le champ n de table.pack)
		local function args(c, remote, i)
			local a = TvAudit.sent(c.h, remote)[i]
			if a == nil then
				return nil
			end
			local out = {}
			for k = 1, a.n or #a do
				out[k] = a[k]
			end
			return out
		end

		local function entryOf(c, kind, id)
			for _, e in c.Ranch._styleEntries() do
				if e.kind == kind and e.id == id then
					return e
				end
			end
			return nil
		end

		local function stylePage(c)
			return c.PC.window("Ranch").Body.Page_style
		end

		it(
			"N8 : Dalles absentes (page jamais construite) tant que l'écran Améliorations est disponible ; instantané retiré → Dalles à l'ouverture suivante",
			function()
				local c = v2client()
				c.PC.open("Ranch", "pens")
				TvAudit.tick(c.h, 0.5)
				local body = c.PC.window("Ranch").Body
				expect(c.Ranch.tabs()).toEqual({ "pens", "dodo", "mail", "fuse", "sell", "style" })
				expect(body:FindFirstChild("Page_pads")).toBeNil()
				expect(c.Ranch._state().padsBuilt).toBe(false)
				expect(body.Tabs.Strip.Tab_pads.Visible).toBe(false)
				c.Ranch.setTab("pads")
				expect(c.Ranch.currentTab()).toBe("pens")
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Ranch", "padsKept")
				expect(c.Ranch.currentTab()).toBe("pens")
				expect(c.Ranch._state().keptFirst).toBe(false)
				-- interrupteur coupé à chaud : DataPatch qui retire l'instantané
				c.PC.closeAll()
				TvAudit.tick(c.h, 0.5)
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", {}, { "upgradeSnapshot" })
				c.h:settle(1)
				c.PC.open("Ranch", "pads")
				TvAudit.tick(c.h, 0.5)
				expect(c.Ranch.tabs()).toEqual({ "pens", "dodo", "mail", "fuse", "sell", "pads", "style" })
				expect(c.Ranch.currentTab()).toBe("pads")
				expect(body:FindFirstChild("Page_pads") ~= nil).toBe(true)
				expect(body.Tabs.Strip.Tab_pads.Visible).toBe(true)
				expect(c.Ranch._tileButton("snack") ~= nil).toBe(true)
				expect(#TvAudit.sent(c.h, "PlaceDeco")).toBe(0)
				expect(#TvAudit.sent(c.h, "EquipCosmetic")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"Mon style : sortes, nombre d'objets par sorte, possédé / verrouillé / équipé (14 habillages, 8 tenues, 66 titres)",
			function()
				local c = v2client()
				c.PC.open("Ranch", "style")
				TvAudit.tick(c.h, 0.5)
				local st = c.Ranch._state()
				expect(st.styleMode).toBe("v2")
				expect(st.v13Built).toBe(false)
				expect(st.kinds).toEqual({
					"theme",
					"deco",
					"saddle",
					"trail",
					"title",
					"flag",
					"outfits",
					"palette",
					"cushions",
				})
				expect(c.PC.window("Ranch").Body.Tabs.Strip.Tab_style.Label.Text).toBe("My style")
				expect(stylePage(c):FindFirstChild("Kinds")).toBeNil()
				expect(stylePage(c):FindFirstChild("Items")).toBeNil()
				-- 1re sorte : l'habillage, sélection sur l'habillage équipé
				expect(st.styleKind).toBe("theme")
				expect(sel(c)).toBe(c.Ranch._styleCell("theme", "color"))
				local want = {
					theme = 14,
					saddle = 20,
					trail = 17,
					title = 67,
					flag = 7,
					outfits = 8,
					palette = 9,
					cushions = 2,
				}
				for _, kind in
					{ "theme", "saddle", "trail", "title", "flag", "outfits", "palette", "cushions" }
				do
					press(c, c.Ranch._styleKindButton(kind))
					expect({ kind = kind, n = #c.Ranch._styleEntries() }).toEqual({
						kind = kind,
						n = want[kind],
					})
				end
				local function state(kind, id)
					press(c, c.Ranch._styleKindButton(kind))
					local e = entryOf(c, if kind == "outfits" then "outfit" else kind, id)
					return { id = id, unlocked = e.unlocked, equipped = e.equipped }
				end
				expect(state("theme", "color")).toEqual({ id = "color", unlocked = true, equipped = true })
				expect(state("theme", "marshmallow")).toEqual({
					id = "marshmallow",
					unlocked = true,
					equipped = false,
				})
				expect(state("theme", "aurora")).toEqual({ id = "aurora", unlocked = true, equipped = false })
				expect(state("theme", "celestial")).toEqual({
					id = "celestial",
					unlocked = false,
					equipped = false,
				})
				expect(state("saddle", "cookieSaddle")).toEqual({
					id = "cookieSaddle",
					unlocked = true,
					equipped = false,
				})
				expect(state("saddle", "cosmic")).toEqual({ id = "cosmic", unlocked = true, equipped = false })
				expect(state("saddle", "icingSugar")).toEqual({
					id = "icingSugar",
					unlocked = false,
					equipped = false,
				})
				expect(state("saddle", "partyPopper")).toEqual({
					id = "partyPopper",
					unlocked = false,
					equipped = false,
				})
				expect(state("saddle", "royal")).toEqual({ id = "royal", unlocked = false, equipped = false })
				expect(state("palette", "candy")).toEqual({ id = "candy", unlocked = true, equipped = true })
				expect(state("palette", "lavender")).toEqual({
					id = "lavender",
					unlocked = false,
					equipped = false,
				})
				expect(state("palette", "fireworks")).toEqual({
					id = "fireworks",
					unlocked = true,
					equipped = false,
				})
				expect(state("outfits", "partyHat")).toEqual({
					id = "partyHat",
					unlocked = true,
					equipped = false,
				})
				expect(state("outfits", "starGlasses")).toEqual({
					id = "starGlasses",
					unlocked = false,
					equipped = false,
				})
				expect(state("title", "r400")).toEqual({ id = "r400", unlocked = false, equipped = false })
				S.clean(c, expect)
			end
		)

		it(
			'EquipCosmetic : habillage v2 ; palette « Aucun » → "" ; verrouillé refusé sans envoi ; tenue v2 → OutfitPreview',
			function()
				local c = v2client()
				c.PC.open("Ranch", "style")
				TvAudit.tick(c.h, 0.5)
				press(c, c.Ranch._styleCell("theme", "marshmallow"))
				expect(args(c, "EquipCosmetic", 1)).toEqual({ "theme", "marshmallow" })
				press(c, c.Ranch._styleCell("theme", "celestial"))
				expect(#TvAudit.sent(c.h, "EquipCosmetic")).toBe(1)
				expect(refused(c)).toBe(true)
				press(c, c.Ranch._styleKindButton("palette"))
				press(c, c.Ranch._styleCell("palette", "candy")) -- déjà équipée : rien
				expect(#TvAudit.sent(c.h, "EquipCosmetic")).toBe(1)
				press(c, c.Ranch._styleCell("palette", ""))
				expect(args(c, "EquipCosmetic", 2)).toEqual({ "palette", "" })
				press(c, c.Ranch._styleKindButton("outfits"))
				press(c, c.Ranch._styleCell("outfit", "partyHat"))
				expect(c.PC.current()).toBe("OutfitPreview")
				expect(c.OP._state().outfit).toBe("partyHat")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Ranch")
				S.clean(c, expect)
			end
		)

		it(
			"Déco perso : 12 emplacements P / G ; choix filtré par la taille, sans l'objet posé ailleurs ; PlaceDeco ; ○ par niveaux",
			function()
				local c = v2client()
				c.PC.open("Ranch", "style")
				TvAudit.tick(c.h, 0.5)
				press(c, c.Ranch._styleKindButton("deco"))
				expect(sel(c)).toBe(c.Ranch._decoSlot(1))
				for i = 1, 12 do
					local b = c.Ranch._decoSlot(i)
					expect(b:GetAttribute("SlotSize")).toBe(Cosmetics.DecoSlots[i])
					expect(b:GetAttribute("DecoItem")).toBe(if i == 1 then 1 else 0)
				end
				expect(c.Ranch._decoSlot(1).Label.Text).toBe("Name Pennant")
				expect(c.Ranch._decoSlot(2).Label.Text).toBe("Empty spot")
				-- la croix atteint chaque emplacement du plan
				Layout.apply(c.h)
				expect(#Layout.unreachable(c.h, c.Ranch._decoSlot(1).Parent, c.Ranch._decoSlot(1))).toBe(0)
				-- emplacement 2 (petit) : « Aucun », puis les petits possédés, puis les petits verrouillés
				press(c, c.Ranch._decoSlot(2))
				expect(c.Ranch._state().pickerSlot).toBe(2)
				local entries = c.Ranch._styleEntries()
				expect(#entries).toBe(24) -- « Aucun » + 23 petits (le Fanion est posé en 1)
				expect(entries[1]).toEqual({ kind = "deco", id = "", n = 0, unlocked = true, equipped = true })
				local lockedSeen = false
				for i, e in entries do
					if i > 1 then
						expect(Cosmetics.DecoPerso[e.n].size).toBe("P")
						expect(e.n ~= 1).toBe(true)
						if not e.unlocked then
							lockedSeen = true
						else
							expect(lockedSeen).toBe(false) -- possédés d'abord
						end
					end
				end
				expect(entryOf(c, "deco", "plopBowl").unlocked).toBe(true)
				expect(entryOf(c, "deco", "workbench").unlocked).toBe(false)
				expect(sel(c)).toBe(c.Ranch._styleCell("deco", ""))
				-- verrouillé : refusé, rien n'est envoyé
				press(c, c.Ranch._styleCell("deco", "workbench"))
				expect(#TvAudit.sent(c.h, "PlaceDeco")).toBe(0)
				expect(refused(c)).toBe(true)
				-- « Aucun » sur un emplacement vide : rien
				press(c, c.Ranch._styleCell("deco", ""))
				expect(#TvAudit.sent(c.h, "PlaceDeco")).toBe(0)
				expect(sel(c)).toBe(c.Ranch._decoSlot(2))
				press(c, c.Ranch._decoSlot(2))
				press(c, c.Ranch._styleCell("deco", "plopBowl"))
				expect(args(c, "PlaceDeco", 1)).toEqual({ 7, 2 })
				expect(c.Ranch._state().pickerSlot).toBe(0)
				expect(sel(c)).toBe(c.Ranch._decoSlot(2))
				-- emplacement 9 (grand) : « Aucun » + les 16 grands
				press(c, c.Ranch._decoSlot(9))
				expect(#c.Ranch._styleEntries()).toBe(17)
				for i, e in c.Ranch._styleEntries() do
					if i > 1 then
						expect(Cosmetics.DecoPerso[e.n].size).toBe("G")
					end
				end
				-- ○ : choix → son emplacement ; plan → liste des sortes ; liste → menu
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(sel(c)).toBe(c.Ranch._decoSlot(9))
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(sel(c)).toBe(c.Ranch._styleKindButton("deco"))
				-- « Aucun » sur l'emplacement 1 occupé : PlaceDeco(0, 1)
				press(c, c.Ranch._styleKindButton("deco"))
				press(c, c.Ranch._decoSlot(1))
				press(c, c.Ranch._styleCell("deco", ""))
				expect(args(c, "PlaceDeco", 2)).toEqual({ 0, 1 })
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBeNil()
				S.clean(c, expect)
			end
		)

		it(
			"l'attribut DecoPerso change : le plan suit sans créer d'instance ; attribut hostile : emplacements vides, sans trace",
			function()
				local c = v2client()
				c.PC.open("Ranch", "style")
				TvAudit.tick(c.h, 0.5)
				press(c, c.Ranch._styleKindButton("deco"))
				local win = c.PC.window("Ranch")
				local before = #win:GetDescendants()
				c.model:SetAttribute("DecoPerso", "1,7,0,0,0,0,0,0,6,0,0,0")
				c.h:settle(1)
				expect(c.Ranch._decoSlot(2):GetAttribute("DecoItem")).toBe(7)
				expect(c.Ranch._decoSlot(9):GetAttribute("DecoItem")).toBe(6)
				expect(c.Ranch._decoSlot(2).Label.Text).toBe("Plop's Bowl")
				expect(#win:GetDescendants()).toBe(before)
				-- chaîne hostile : chaque jeton vérifié (taille de l'emplacement, numéro connu, une seule fois)
				c.model:SetAttribute("DecoPerso", "6,1,abc,,,-3,99,1e9,7,7,7,7")
				c.h:settle(1)
				for i = 1, 12 do
					expect({ i = i, n = c.Ranch._decoSlot(i):GetAttribute("DecoItem") }).toEqual({
						i = i,
						n = if i == 2 then 1 else 0,
					})
				end
				-- trop longue : tout vide
				c.model:SetAttribute("DecoPerso", string.rep("9,", 200))
				c.h:settle(1)
				for i = 1, 12 do
					expect(c.Ranch._decoSlot(i):GetAttribute("DecoItem")).toBe(0)
				end
				expect(#win:GetDescendants()).toBe(before)
				-- pas une chaîne, puis retiré : plus de sorte Déco perso (retour à la 1re sorte), sans trace
				for _, hostile in { 42, true } do
					c.model:SetAttribute("DecoPerso", hostile)
					c.h:settle(1)
					expect(table.find(c.Ranch._state().kinds, "deco")).toBeNil()
					expect(c.Ranch._state().styleKind).toBe("theme")
				end
				c.model:SetAttribute("DecoPerso", nil)
				c.h:settle(1)
				expect(table.find(c.Ranch._state().kinds, "deco")).toBeNil()
				expect(#win:GetDescendants()).toBe(before)
				expect(#TvAudit.sent(c.h, "PlaceDeco")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"interrupteurs coupés (profil v2, rien d'annoncé) : onglet Style de la v1.3 identique (instances, textes, intentions)",
			function()
				local function styleTree(c)
					local out = {}
					for _, d in stylePage(c):GetDescendants() do
						if d:IsA("GuiObject") then
							table.insert(out, d.Name)
						end
					end
					table.sort(out)
					return out
				end
				local base = setup({ plopDays = 8 })
				base.PC.open("Ranch", "style")
				TvAudit.tick(base.h, 0.5)
				local c = v2client({ flags = false, snap = false })
				c.PC.open("Ranch", "style")
				TvAudit.tick(c.h, 0.5)
				expect(c.Ranch._state().styleMode).toBe("v13")
				expect(c.Ranch._state().v2Built).toBe(false)
				expect(c.Ranch.tabs()).toEqual({ "pens", "dodo", "mail", "fuse", "sell", "pads", "style" })
				expect(c.PC.window("Ranch").Body.Tabs.Strip.Tab_style.Label.Text).toBe("Style")
				expect(styleTree(c)).toEqual(styleTree(base))
				expect(stylePage(c):FindFirstChild("KindsV2")).toBeNil()
				expect(stylePage(c):FindFirstChild("Plan")).toBeNil()
				press(c, c.Ranch._styleCell("saddle", "peach"))
				expect(args(c, "EquipCosmetic", 1)).toEqual({ "saddle", "peach" })
				press(c, c.Ranch._styleKindButton("theme"))
				expect(c.Ranch._styleCell("theme", "marshmallow")).toBeNil()
				expect(#TvAudit.sent(c.h, "PlaceDeco")).toBe(0)
				-- instantané présent mais aucun interrupteur méta : Dalles retirées, Style de la v1.3
				local d = v2client({ flags = false })
				d.PC.open("Ranch", "style")
				TvAudit.tick(d.h, 0.5)
				expect(d.Ranch._state().styleMode).toBe("v13")
				expect(d.Ranch.tabs()).toEqual({ "pens", "dodo", "mail", "fuse", "sell", "style" })
				clean(base)
				S.clean(c, expect)
				S.clean(d, expect)
			end
		)
	end)
end
