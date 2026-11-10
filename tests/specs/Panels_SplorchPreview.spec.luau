--!nocheck
-- Panels/SplorchPreview (paquet client-panels ; GDD §4.15, §10.3 ; docs/04 §13.6, contrat v1.2) :
-- visible seulement quand le Grand Splorch est prêt, 3 tuiles « Tu gagnes », pièces perdues en rouge
-- et « Dépenser d'abord » (Ranch › Dalles, gardées d'abord), choix du squishy qui s'envole (défaut :
-- le plus gros qui n'est pas Meilleur Ami), case Filmer (cachée sans capture), maintien de 1,5 s puis
-- GrandSplorch une seule fois, PLUS de 2e confirmation (recentBuy ignoré), feedback.waitEscape
-- pendant une fuite, « Rentre dans ton ranch » hors du ranch, Détails et ○. Zéro trace.
-- Lot B3, étape 2 (plan B3, D6 à D9, D17) : flèches DESSINÉES du choix de l'envol dans les deux chemins
-- (attente de la v1.3 changée : le bouton n'a plus de libellé « ◀ » / « ▶ », il porte une toile
-- « Arrow » de Hud/Icons) ; bloc « v2.0 (lot B3) » : tuiles UpgradeCard, « Dépenser d'abord » seulement
-- avec une ligne gardée payable, Petit Splorch, page Détails, onglets, file, entrées hostiles,
-- interrupteurs coupés = arbre de la v1.3.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function readyProfile(extra)
		local p = {
			squishies = {
				best = TvAudit.squishy(1, { z = 30000, bf = 1 }), -- Meilleur Ami : pas l'envol par défaut
				flyer = TvAudit.squishy(5, { z = 20000 }),
				small = TvAudit.squishy(2, { z = 10 }),
			},
			growth = { G = 0, g = 1, t = NOW },
			coins = 4000,
			pot = 1000,
			R = 0,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
		}
		for k, v in extra or {} do
			p[k] = v
		end
		return p
	end

	local function setup(profile)
		local h = TvAudit.client({ profile = profile, now = NOW })
		local c = {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			SP = TvAudit.mod(h, "UI.Panels.SplorchPreview"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
		}
		return c
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function main(c)
		return c.PC.window("SplorchPreview").Body.Main
	end

	local function holdButton(c)
		return main(c).Hold
	end

	local function hold(c, seconds)
		TvAudit.tick(c.h, 0.5)
		c.h.game.GuiService.SelectedObject = holdButton(c)
		c.h:settle(1)
		Gamepad.press(c.h, Enum.KeyCode.ButtonA)
		c.Clock.advance(seconds)
		c.h:step(1 / 60, 2)
		Gamepad.release(c.h, Enum.KeyCode.ButtonA)
		c.h:settle(2)
	end

	describe("Panels/SplorchPreview", function()
		it(
			"invisible tant que le plus gros n'atteint pas l'objectif ; entrée du rail quand c'est prêt",
			function()
				local c = setup({
					squishies = { a = TvAudit.squishy(1, { z = 100 }) },
					growth = { G = 0, g = 1, t = NOW },
				})
				expect(c.SP.visible()).toBe(false)
				local c2 = setup(readyProfile())
				expect(c2.SP.visible()).toBe(true)
				expect(c2.PC.entries()[1]).toBe("SplorchPreview")
				clean(c)
				clean(c2)
			end
		)

		it(
			"tuiles, pièces perdues, envol par défaut, maintien 1,5 s → GrandSplorch(film, flyer), sans 2e confirmation",
			function()
				local c = setup(readyProfile())
				c.PC.open("SplorchPreview")
				local m = main(c)
				expect(c.h.game.GuiService.SelectedObject).toBe(holdButton(c))
				expect(m.Tile1.Text.Text).toBe("Growth ×2 forever")
				expect(m.Tile2.Text.Text).toBe("Axolo family") -- déblocage de R = 1
				expect(m.Tile3.Text.Text).toBe("+5 Fame")
				expect(m.Lose.Visible).toBe(true)
				expect(m.Lose.Text).toContain("5,000") -- pièces + Pot
				expect(m.SpendFirst.Visible).toBe(true)
				expect(c.SP._state().flyer).toBe("flyer")
				expect(m.FlyerName.Text).toBe("Mochi Mew")
				-- relâché avant 1,5 s : rien
				hold(c, 1.0)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				hold(c, 1.6)
				local sent = TvAudit.sent(c.h, "GrandSplorch")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe(true) -- Filmer (réglage clips par défaut)
				expect(sent[1][2]).toBe("flyer")
				-- l'aperçu se ferme aussitôt (aucune 2e confirmation)
				expect(c.PC.current()).toBeNil()
				clean(c)
			end
		)

		it("choix du squishy qui s'envole ; case Filmer décochée ; Filmer caché sans capture", function()
			local c = setup(readyProfile())
			c.PC.open("SplorchPreview")
			local m = main(c)
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = m.NextFlyer
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.SP._state().flyer).toBe("best")
			c.h.game.GuiService.SelectedObject = m.Film.Toggle
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(c.SP._state().film).toBe(false)
			hold(c, 1.6)
			local sent = TvAudit.sent(c.h, "GrandSplorch")[1]
			expect(sent[1]).toBe(false)
			expect(sent[2]).toBe("best")
			-- appareil sans capture (VFXController pose ClipsUnavailable) : plus de case
			local c2 = setup(readyProfile())
			c2.h.localPlayer:SetAttribute("ClipsUnavailable", true)
			c2.PC.open("SplorchPreview")
			expect(main(c2).Film.Visible).toBe(false)
			hold(c2, 1.6)
			expect(TvAudit.sent(c2.h, "GrandSplorch")[1][1]).toBe(false)
			clean(c)
			clean(c2)
		end)

		it(
			"squishy en fuite : feedback.waitEscape et maintien refusé ; hors du ranch : « Rentre dans ton ranch »",
			function()
				local c = setup(readyProfile())
				local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
				WSC.mySlot = function()
					return 4
				end
				WSC.creatures = function()
					return {
						[9] = {
							id = 9,
							kind = "escape",
							species = 5,
							ownerSlot = 4,
							t0 = NOW - 2,
							duration = 20,
						},
					}
				end
				c.PC.open("SplorchPreview")
				local m = main(c)
				expect(m.Status.Visible).toBe(true)
				expect(m.Status.Text).toBe("Wait for Mochi Mew to come home!")
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				-- la fuite finit (t0 + duration passé) ; le personnage est sur la place, hors de son ranch
				-- (position du personnage, Logic/WorldLayout) : « Rentre dans ton ranch », maintien refusé
				c.Clock.advance(30)
				c.h:step(1 / 60, 2)
				expect(m.Status.Text).toBe("Go back to your ranch")
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				-- de retour dans son ranch : plus de message, le maintien part
				local WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = c.h.globals.CFrame.new(WorldLayout.toWorld(4, Vector3.new(0, 3, 36)))
				c.h:step(1 / 60, 2)
				expect(m.Status.Visible).toBe(false)
				hold(c, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(1)
				clean(c)
			end
		)

		it(
			"« Dépenser d'abord » : Ranch › Dalles, gardées d'abord ; Détails puis ○ ; ○ au menu",
			function()
				local c = setup(readyProfile())
				c.PC.open("SplorchPreview")
				local m = main(c)
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = m.Details
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.SP._state().details).toBe(true)
				local d = c.PC.window("SplorchPreview").Body.DetailsPage
				expect(d.Next.Text).toContain("39")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.SP._state().details).toBe(false)
				expect(c.h.game.GuiService.SelectedObject).toBe(m.Details)
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = m.SpendFirst
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.PC.current()).toBe("Ranch")
				local Ranch = TvAudit.mod(c.h, "UI.Panels.Ranch")
				expect(Ranch.currentTab()).toBe("pads")
				expect(Ranch._state().keptFirst).toBe(true)
				-- 4 000 pièces : l'Enclos (1 200) est la moins chère des dalles gardées payables
				expect(c.h.game.GuiService.SelectedObject).toBe(Ranch._tileButton("pens"))
				clean(c)
			end
		)

		it(
			"flèches du choix de l'envol dessinées (règle 18) : toile Arrow, celle de gauche tournée de 180°",
			function()
				local c = setup(readyProfile())
				c.PC.open("SplorchPreview")
				local m = main(c)
				for name, rot in { PrevFlyer = 180, NextFlyer = 0 } do
					local b = m[name]
					expect(b:FindFirstChild("Label")).toBeNil()
					local arrow = b:FindFirstChild("Arrow")
					expect(arrow ~= nil).toBe(true)
					expect(arrow.Rotation).toBe(rot)
					expect(arrow:GetAttribute("Icon")).toBe("arrowRight")
					expect(b.Text).toBe("")
				end
				clean(c)
			end
		)

		it("recentBuy ignoré : aucune 2e étape même si l'aperçu le signale", function()
			local c = setup(readyProfile())
			local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
			local preview = Formulas.splorchPreview
			Formulas.splorchPreview = function(data, ctx)
				local p = preview(data, ctx)
				p.recentBuy = true
				return p
			end
			c.PC.open("SplorchPreview")
			hold(c, 1.6)
			expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(1)
			clean(c)
		end)
	end)

	-- =========================================================================================
	-- Lot B3, étape 2 (plan B3, D6 à D9) : aperçus de la v2.0, interrupteurs ouverts DANS le test (client
	-- v2.0 du harnais UpgradeScreen : instantané du serveur, profil v2, EventState.features.v2)
	describe("Panels/SplorchPreview › v2.0 (lot B3)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local V2 = UpgradeScreen.V2_ALL
		local ME = 1 -- joueur local du harnais client
		local BIG = {
			best = TvAudit.squishy(1, { z = 3e15, bf = 1 }),
			flyer = TvAudit.squishy(5, { z = 2e15 }),
		}
		local SMALL = { a = TvAudit.squishy(1, { z = 10 }) }
		local FROZEN = { G = 0, g = 0, t = NOW }

		local function except(flag)
			local out = {}
			for k, v in V2 do
				if k ~= flag then
					out[k] = v
				end
			end
			return out
		end

		-- client v2.0 : instantané du profil témoin (r, Record R, A ; opts.edit), profil répliqué v2 (plus
		-- gros squishy prêt pour la boucle sauf opts.squishies), attributs de MON ranch, interrupteurs
		local function v2client(opts)
			opts = opts or {}
			local r = opts.r or 5
			local snap = S.snap(1, function(p)
				p.R = r
				p.bestR = opts.bestR or r
				p.ascend = opts.A or 0
				if opts.edit then
					opts.edit(p)
				end
			end)
			local c = S.client({
				snap = snap,
				profile = {
					version = 2,
					squishies = opts.squishies or BIG,
					growth = FROZEN,
					coins = opts.coins or 4000,
					pot = 0,
					R = r,
				},
				ranch = opts.ranch or {},
				lang = opts.lang,
			})
			if opts.flags ~= false then
				S.event(c, opts.flags or V2)
			end
			-- le personnage dans SON ranch (slot 1 du harnais), sauf opts.outside
			if not opts.outside then
				local WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = c.h.globals.CFrame.new(WorldLayout.toWorld(1, Vector3.new(0, 3, 36)))
				S.run(c, 0.1)
			end
			c.SP = TvAudit.mod(c.h, "UI.Panels.SplorchPreview")
			return c
		end

		local function tileTexts(c)
			local parts = c.SP._v2()
			local out = {}
			for _, t in parts.tiles do
				local title = t:FindFirstChild("Title")
				local value = t:FindFirstChild("Value")
				local text = if title and title.Visible then title.Text else ""
				if value and value.Visible and value.Text ~= "" then
					text ..= " | " .. value.Text
				end
				table.insert(out, text)
			end
			return out
		end

		local function title(c)
			return c.PC.window("SplorchPreview").Header.Title.Text
		end

		local function openPreview(c, tab)
			c.PC.closeAll()
			S.run(c, 0.5)
			c.PC.open("SplorchPreview", tab)
			S.run(c, 0.5)
		end

		local function queued(kind, userId)
			return {
				queue = {
					{ kind = kind, userId = userId, startAt = NOW + 20, slot = 1, position = 1, eta = 20 },
				},
			}
		end
		local function show(kind, userId)
			return {
				current = {
					kind = kind,
					userId = userId,
					startedAt = NOW,
					burstAt = NOW + 4,
					endsAt = NOW + 10,
					level = 16,
				},
				queue = {},
			}
		end

		it(
			"tuiles UpgradeCard : nouveau record R5 → 6, record regagné (cadeau), Petit Splorch, Jelly Ascend ; titre de la fenêtre",
			function()
				local c = v2client({ r = 5 })
				openPreview(c)
				expect(c.SP._state().path).toBe("v2")
				expect(tileTexts(c)).toEqual({ "Growth ×2", "Free pen spot", "+9 Confetti" })
				expect(title(c)).toBe("Grand Splorch")
				expect(c.SP._v2().hold.Label.Text).toBe("Hold to SPLORCH")
				expect(c.h.game.GuiService.SelectedObject).toBe(c.SP._v2().hold)
				S.clean(c, expect)
				-- record regagné, Petit Splorch coupé : Grand Splorch avec le cadeau du Splorch
				local g = v2client({ r = 5, bestR = 10, A = 1, flags = except("PetitSplorch") })
				openPreview(g)
				expect(tileTexts(g)).toEqual({ "Growth ×2", "Splorch Gift", "+1 Confetti" })
				expect(title(g)).toBe("Grand Splorch")
				S.clean(g, expect)
				-- Petit Splorch (remontée) : ses tuiles, son titre, son maintien
				local p = v2client({ r = 4, bestR = 12, A = 1 })
				openPreview(p)
				expect(tileTexts(p)).toEqual({ "Growth ×2", "Splorch Gift", "Petit Splorch: +1 Confetti" })
				expect(title(p)).toBe("Petit Splorch")
				expect(p.SP._v2().hold.Label.Text).toBe("Hold for the Petit Splorch")
				S.clean(p, expect)
				-- Jelly Ascend seule prête (boucle pas prête) : onglet ascend d'office
				local a = v2client({ r = 15, A = 0, squishies = SMALL, ranch = { AscendReady = true } })
				openPreview(a)
				expect(a.SP.currentTab()).toBe("ascend")
				expect(a.SP.tabs()).toEqual({ "ascend" })
				expect(tileTexts(a)).toEqual({
					"×3 every loop, forever",
					"Halo and sky: Cushion Cloud",
					"+20 Confetti",
				})
				expect(title(a)).toBe("Jelly Ascend")
				local parts = a.SP._v2()
				expect(parts.restart.Text).toBe(
					"You start again at Grand Splorch 0 (your record: 15). Everything else is kept."
				)
				expect(parts.speed.Text).toBe(
					"Until your record, your squishies grow 9 times faster than before."
				)
				expect(parts.condition.Text).toBe("Grand Splorch 15 / 15")
				expect(parts.check.Visible).toBe(true)
				expect(a.h.game.GuiService.SelectedObject).toBe(parts.ascendHold)
				S.clean(a, expect)
			end
		)

		it("aucun bouton Dépenser d'abord sans ligne gardée payable", function()
			-- pièces à perdre, mais aucune ligne gardée payable (Enclos au maximum, Lit douillet acheté) :
			-- la phrase neutre, aucun bouton
			local c = v2client({ r = 5, coins = 4000 })
			openPreview(c)
			local parts = c.SP._v2()
			expect(parts.line.Text).toBe("Your coins become the Splorch gift.")
			expect(parts.spend.Visible).toBe(false)
			S.clean(c, expect)
			-- Enclos payable : la ligne rouge et « Dépenser d'abord » → Améliorations PAR-DESSUS l'aperçu
			local d = v2client({
				r = 5,
				coins = 4000,
				edit = function(p)
					p.coins = 1e30
					p.tiles.pens = 3
				end,
			})
			openPreview(d)
			local pd = d.SP._v2()
			expect(pd.line.Text).toBe("You will lose 4,000 coins")
			expect(pd.spend.Visible).toBe(true)
			S.select(d, pd.spend)
			Gamepad.tap(d.h, Enum.KeyCode.ButtonA)
			S.run(d, 0.5)
			expect(d.PC.current()).toBe("Upgrades")
			expect(d.PC.isOpen("SplorchPreview")).toBe(true)
			expect(d.Up.currentTab()).toBe("ranch")
			expect(S.selected(d)).toBe(d.Up._row("pens"))
			-- ○ : retour à l'aperçu, sur « Dépenser d'abord »
			S.run(d, 0.5)
			Gamepad.tap(d.h, Enum.KeyCode.ButtonB)
			S.run(d, 0.5)
			expect(d.PC.current()).toBe("SplorchPreview")
			expect(S.selected(d)).toBe(pd.spend)
			expect(#TvAudit.sent(d.h, "BuyUpgrade")).toBe(0)
			S.clean(d, expect)
		end)

		it(
			"premier Petit Splorch par l'aperçu : « Maintiens pour le Petit Splorch », pas de « Filmer », GrandSplorch(false, envol)",
			function()
				local c = v2client({ r = 4, bestR = 12, A = 1 })
				expect(c.PC.rebirth()).toBe("petit")
				openPreview(c)
				local parts = c.SP._v2()
				-- Détails : pas de case « Filmer » pour un Petit Splorch
				S.select(c, parts.details)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.5)
				expect(c.SP._state().details).toBe(true)
				expect(parts.film.Visible).toBe(false)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(c.SP._state().details).toBe(false)
				S.hold(c, parts.hold, 1.6)
				local sent = TvAudit.sent(c.h, "GrandSplorch")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe(false)
				expect(sent[1][2]).toBe("flyer")
				expect(c.PC.current()).toBeNil()
				S.clean(c, expect)
			end
		)

		it(
			"Détails : deux colonnes, prochain objectif, choix de l'envol (flèches dessinées) et « Filmer »",
			function()
				local c = v2client({ r = 5 })
				openPreview(c)
				local parts = c.SP._v2()
				S.select(c, parts.details)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.5)
				expect(parts.page.Visible).toBe(true)
				expect(S.selected(c)).toBe(parts.ok)
				expect(parts.page.Column1.Title.Text).toBe("You keep")
				expect(parts.page.Column2.Title.Text).toBe("Starts over")
				expect(parts.page.Next.Text).toContain("Next goal")
				expect(parts.film.Visible).toBe(true)
				for name, rot in { PrevFlyer = 180, NextFlyer = 0 } do
					local arrow = parts.page[name]:FindFirstChild("Arrow")
					expect(arrow ~= nil and arrow.Rotation == rot).toBe(true)
				end
				expect(c.SP._state().flyer).toBe("flyer")
				S.select(c, parts.nextFlyer)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.2)
				expect(c.SP._state().flyer).toBe("best")
				S.select(c, parts.film.Toggle)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				S.run(c, 0.2)
				expect(c.SP._state().film).toBe(false)
				-- ○ : retour à la page principale, sur « Détails »
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(parts.page.Visible).toBe(false)
				expect(S.selected(c)).toBe(parts.details)
				S.hold(c, parts.hold, 1.6)
				local sent = TvAudit.sent(c.h, "GrandSplorch")[1]
				expect(sent[1]).toBe(false)
				expect(sent[2]).toBe("best")
				S.clean(c, expect)
			end
		)

		it(
			"onglets quand la boucle et la Jelly Ascend sont prêtes : R1 / L1, titre et tuiles suivent ; open('ascend')",
			function()
				local c = v2client({ r = 15, A = 0, ranch = { AscendReady = true } })
				openPreview(c)
				expect(c.SP.tabs()).toEqual({ "splorch", "ascend" })
				expect(c.SP.currentTab()).toBe("splorch")
				local parts = c.SP._v2()
				expect(parts.tabs ~= nil and parts.tabs.Visible).toBe(true)
				expect(title(c)).toBe("Grand Splorch")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				S.run(c, 0.5)
				expect(c.SP.currentTab()).toBe("ascend")
				expect(title(c)).toBe("Jelly Ascend")
				expect(tileTexts(c)[1]).toBe("×3 every loop, forever")
				expect(S.selected(c)).toBe(parts.ascendHold)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonL1)
				S.run(c, 0.5)
				expect(c.SP.currentTab()).toBe("splorch")
				expect(S.selected(c)).toBe(parts.hold)
				-- puce du HUD / carte Conseillé : open("SplorchPreview", "ascend")
				openPreview(c, "ascend")
				expect(c.SP.currentTab()).toBe("ascend")
				-- ○ : retour au menu
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(c.PC.current()).toBeNil()
				expect(c.PC.menuOpen()).toBe(true)
				expect(#TvAudit.sent(c.h, "JellyAscend")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"MON prestige dans la file : maintien refusé avec son texte ; MON spectacle commence : l'aperçu se ferme",
			function()
				local c = v2client({ r = 5 })
				openPreview(c)
				local parts = c.SP._v2()
				S.event(c, V2, queued("splorch", ME))
				expect(c.SP._state().blocker).toBe("queued")
				expect(parts.refusalBox.Visible).toBe(true)
				expect(parts.refusal.Text).toBe("It's getting ready to fly")
				S.hold(c, parts.hold, 1.6)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				-- celle d'un autre joueur ne bloque rien
				S.event(c, V2, queued("splorch", 77))
				expect(c.SP._state().blocker).toBe("")
				expect(parts.refusalBox.Visible).toBe(false)
				-- MON spectacle : fermé
				S.event(c, V2, show("splorch", ME))
				expect(c.PC.isOpen("SplorchPreview")).toBe(false)
				S.clean(c, expect)
				-- onglet ascend : MON Grand Splorch dans la file → « Ton Grand Splorch passe d'abord ! »
				local a = v2client({ r = 15, A = 0, squishies = SMALL, ranch = { AscendReady = true } })
				openPreview(a)
				S.event(a, V2, queued("splorch", ME))
				expect(a.SP._state().ascend).toBe("queuedSplorch")
				expect(a.SP._v2().ascendRefusal.Text).toBe("Your Grand Splorch goes first!")
				S.hold(a, a.SP._v2().ascendHold, 3.3)
				expect(a.SP._state().card).toBe(false)
				expect(#TvAudit.sent(a.h, "JellyAscend")).toBe(0)
				S.clean(a, expect)
			end
		)

		it(
			"instantané, attributs et interrupteurs hostiles : aucune trace, aucun onglet ascend inventé",
			function()
				for _, bad in { "yes", 1, false, -1 } do
					local c = v2client({ r = 15, A = 0, ranch = { AscendReady = bad } })
					openPreview(c)
					expect(c.SP.tabs()).toEqual({ "splorch" })
					expect(c.SP._v2().ascend).toBeNil()
					S.clean(c, expect)
				end
				-- features.v2 hostile : tout coupé (tuiles de repli de la v1.3, aucun onglet ascend)
				local h = v2client({
					r = 15,
					A = 0,
					ranch = { AscendReady = true },
					flags = { JellyAscend = "yes" },
				})
				openPreview(h)
				expect(h.SP.tabs()).toEqual({ "splorch" })
				-- instantané abîmé reçu écran ouvert : refusé par UpgradeSnapshot, l'écran ne bouge pas
				local before = tileTexts(h)
				S.patch(h, { r = 0 / 0, bestR = "x", ascend = -1, coins = math.huge, levels = 3 })
				expect(tileTexts(h)).toEqual(before)
				S.clean(h, expect)
			end
		)

		it(
			"interrupteurs coupés : arbre de la v1.3 (noms et nombres), aucune partie v2.0, aucune intention v2.0",
			function()
				-- client sans instantané (UpgradesScreen coupé) mais profil v2 et EventState complet
				local c = v2client({ r = 5, flags = false })
				local US = TvAudit.mod(c.h, "UI.UpgradeSnapshot")
				-- l'instantané d'arrivée est retiré : chemin de la v1.3
				S.patch(c, nil, { "upgradeSnapshot" })
				expect(US.available()).toBe(false)
				openPreview(c)
				expect(c.SP._state().path).toBe("v13")
				expect(c.SP._v2()).toBeNil()
				local body = c.PC.window("SplorchPreview").Body
				local names = {}
				for _, child in body:GetChildren() do
					table.insert(names, child.Name)
				end
				table.sort(names)
				expect(table.concat(names, ",")).toBe("DetailsPage,Main")
				local mainNames = {}
				for _, child in body.Main:GetChildren() do
					table.insert(mainNames, child.Name)
				end
				table.sort(mainNames)
				expect(table.concat(mainNames, ",")).toBe(
					"Details,Film,FlyerName,FlyerTitle,Hold,Lose,NextFlyer,PrevFlyer,SpendFirst,Stage,Status,Tile1,Tile2,Tile3,Win"
				)
				expect(c.PC.window("SplorchPreview"):FindFirstChild("AscendConfirm")).toBeNil()
				expect(c.SP.tabs()).toEqual({})
				expect(c.SP.currentTab()).toBe("")
				expect(title(c)).toBe("Grand Splorch")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)
	end)
end
