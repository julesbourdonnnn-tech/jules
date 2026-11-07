--!nocheck
-- Relecture des écrans et de la manette du lot B2 (écran Améliorations et HUD v2.0) : défauts trouvés
-- en regardant les captures de l'outil d'écrans (tools/screens, tv1080, tv720, tv2160, FR et EN) et
-- en jouant l'écran à la manette ; chaque cas montré rouge avant sa correction (docs/04 §27.12,
-- lignes B2-71 et suivantes). Vrai client console, interrupteurs v2.0 ouverts DANS le test. Zéro trace.
local Screens = require("../harness/Screens")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function group(id)
		for _, g in Screens.groups() do
			if g.id == id then
				return g
			end
		end
		error("groupe d'écrans inconnu : " .. id)
	end

	describe(
		"Review_B2_screens › outil d'écrans : chaque état de l'écran Améliorations est capturé",
		function()
			-- Défaut 1 : depuis B2-66 (écran fermé quand r, Record R ou A changent), les réponses fabriquées des
			-- scénarios « upgrades.buy.card » et « upgrades.buy.card.refused » portaient l'instantané du profil
			-- témoin (r = 12) alors que l'écran s'ouvrait à r = 5 : l'écran se fermait, la capture montrait le
			-- HUD seul (retour « +1 niveau » sur une carte et refus sur une carte jamais vus, jamais mesurés
			-- dans leur vraie boîte). Chaque écran du groupe « upgrades » doit montrer l'écran ouvert.
			it(
				"chaque écran du groupe « upgrades » montre l'écran Améliorations ouvert, sans trace",
				function()
					local profile = Screens.profileById("tv1080")
					local g = group("upgrades")
					local c = Screens.boot(Harness, profile, "fr", g.state)
					local closed = {}
					for _, screen in Screens.expand(c, g) do
						local ok, err = Screens.show(c, screen)
						if not ok then
							table.insert(closed, screen.id .. " : " .. tostring(err))
						elseif not c.PC.isOpen("Upgrades") then
							table.insert(
								closed,
								screen.id .. " : écran fermé (panneau " .. tostring(c.PC.current()) .. ")"
							)
						end
					end
					expect(table.concat(closed, "\n")).toBe("")
					expect(table.concat(c.h.errors, "\n")).toBe("")
					Harness.disposeAll()
				end
			)
		end
	)

	-- Défaut 2 : une ligne (ou une carte) au maximum mettait toujours « Tout est acheté : bravo ! » /
	-- « Everything is bought: well done! » dans le bandeau, même quand les autres lignes de l'onglet
	-- montrent « Prêt » ou « Il manque » (captures upgrades.ranch, upgrades.ranch.max,
	-- upgrades.card.max, upgrades.workshop, upgrades.ref.r10.mat) : la phrase est fausse. Elle reste
	-- quand tout l'onglet est au maximum ; sinon le bandeau dit ce que devient la ligne au Grand Splorch,
	-- comme pour ses autres états
	describe("Review_B2_screens › bandeau d'une ligne au maximum (GDD §10.7.6)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local TvAudit = require("../harness/TvAudit")
		local S = UpgradeScreen.new(Harness)
		local ALL_MAX = {
			snack = 12,
			star = 8,
			decor = 18,
			pens = 14,
			cozyBed = true,
			gloves = 40,
			school = 20,
			monuments = 10,
		}
		local function bannerKey(c)
			return TvAudit.mod(c.h, "UI.Text").keyOf(c.Up._banner())
		end

		it(
			"Enclos au maximum, Tapis et Décorations encore à acheter : « Gardé pour toujours »",
			function()
				local c = S.client({
					snap = S.snap(1, function(p)
						p.tiles.pens = 14
						p.coins = 10
					end),
				})
				S.open(c, "ranch")
				S.select(c, c.Up._row("pens"))
				expect(c.Up._view(c.Up._row("pens")).state).toBe("max")
				expect(c.Up._view(c.Up._row("snack")).state).toBe("need")
				expect(bannerKey(c)).toBe("upgrades.detail.kept")
				-- une ligne qui repart de zéro : « Repart de zéro au Grand Splorch »
				S.patch(
					c,
					S.snap(2, function(p)
						p.tiles.pens = 14
						p.tiles.gloves = 40
						p.coins = 10
					end)
				)
				S.open(c, "ranch")
				S.select(c, c.Up._row("gloves"))
				expect(c.Up._view(c.Up._row("gloves")).state).toBe("max")
				expect(bannerKey(c)).toBe("upgrades.detail.resets")
				S.clean(c, expect)
			end
		)

		it("tout l'onglet au maximum : « Tout est acheté : bravo ! » reste", function()
			local c = S.client({
				snap = S.snap(1, function(p)
					for k, v in ALL_MAX do
						p.tiles[k] = v
					end
					p.ascend = 1
					p.R = 20
					p.bestR = 24
					p.coins = 9.87e30
				end),
			})
			S.open(c, "ranch")
			S.select(c, c.Up._row("gloves"))
			expect(bannerKey(c)).toBe("upgrades.detail.allMax")
			S.clean(c, expect)
		end)

		it(
			"carte du Conseillé passée au maximum, les deux autres encore à acheter : ce que devient la ligne",
			function()
				-- profil de l'écran upgrades.card.max : dernier niveau de chaque ligne, Lit douillet à acheter
				local function lastLevels(cozyBed)
					return function(p)
						for k, v in { snack = 11, star = 0, decor = 18, pens = 14, gloves = 39, school = 20 } do
							p.tiles[k] = v
						end
						p.tiles.cozyBed = cozyBed
						p.R = 5
						p.bestR = 5
						p.coins = 9.99e30
					end
				end
				local c = S.client({ snap = S.snap(1, lastLevels(false)) })
				S.open(c, "suggested")
				local index = table.find(c.Up._cards(), "cozyBed")
				expect(index ~= nil).toBe(true)
				local card = c.Up._card(index)
				-- la carte garde sa famille après l'achat (GDD §10.7.4) : elle passe au maximum
				S.hold(c, card, 0.7)
				local sent = S.sent(c, "BuyUpgrade")
				expect(#sent).toBe(1)
				S.answer(c, sent[1], { to = 1, spent = 1, snap = S.snap(2, lastLevels(true)) })
				S.run(c, 2)
				expect(c.Up._view(card).state).toBe("max")
				local others = 0
				for i = 1, #c.Up._cards() do
					local v = c.Up._view(c.Up._card(i))
					if i ~= index and v and v.state == "ready" then
						others += 1
					end
				end
				expect(others > 0).toBe(true)
				expect(bannerKey(c)).toBe("upgrades.detail.kept")
				S.clean(c, expect)
			end
		)
	end)

	-- Partie à la manette seule (PS5 sur un canapé), sur le vrai client, aux 3 résolutions et dans les
	-- 2 langues : △ ↓ ✕ jusqu'à l'écran ; cartes ← → ; ↑ onglets puis bouton de mode ; ✕ et □ font
	-- tourner le mode ; R1 / L1 en boucle ; chaque ligne de chaque onglet atteinte à la croix, ENTIÈRE
	-- dans la liste (jamais sous les onglets ni sous le bandeau), rebond aux deux bouts ; stick droit :
	-- une page ; maintien de ✕ 0,7 s sur une carte Prête : un seul BuyUpgrade valide ; ○ ramène au rail
	-- sur « Améliorations » puis au jeu. Zéro trace
	describe("Review_B2_screens › partie à la manette seule (3 résolutions, FR et EN)", function()
		local roblox = require("@lune/roblox")
		local Enum, Vector2 = roblox.Enum, roblox.Vector2
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local TvAudit = require("../harness/TvAudit")
		local Gamepad = require("../harness/Gamepad")
		local Layout = require("../harness/Layout")
		local S = UpgradeScreen.new(Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		local function play(c, label)
			local h, PC, Up = c.h, c.PC, c.Up
			local issues = {}
			local function fail(msg)
				table.insert(issues, label .. msg)
			end
			local function sel()
				return h.game.GuiService.SelectedObject
			end
			local function tap(key, dt)
				Gamepad.tap(h, key)
				TvAudit.tick(h, dt or 0.2)
			end
			-- rangée entière dans la partie visible de sa liste (px d'écran)
			local function inside(obj, list)
				Layout.apply(h)
				local r, l = Layout.rect(obj), Layout.rect(list)
				if r == nil or l == nil then
					return false
				end
				return r.y >= l.y - 0.5 and r.y + r.h <= l.y + l.h + 0.5
			end
			if not TvAudit.toGame(h) then
				fail("○ ne rend pas la main au jeu au départ")
			end
			tap(Enum.KeyCode.ButtonY, 0.5)
			if not PC.menuOpen() then
				fail("△ n'ouvre pas le menu")
				return issues
			end
			for _ = 1, 9 do
				if sel() == PC.entryButton("Upgrades") then
					break
				end
				tap(Enum.KeyCode.DPadDown)
			end
			if sel() ~= PC.entryButton("Upgrades") then
				fail("l'entrée Améliorations n'est pas atteinte à la croix")
				return issues
			end
			TvAudit.tick(h, 0.5)
			tap(Enum.KeyCode.ButtonA, 0.6)
			if PC.current() ~= "Upgrades" or Up.currentTab() ~= "suggested" or sel() ~= Up._card(1) then
				fail("✕ sur Améliorations n'ouvre pas le Conseillé, sélection sur la carte 1")
				return issues
			end
			-- cartes ← → (rebond aux bouts)
			local n = #Up._cards()
			for i = 2, n do
				tap(Enum.KeyCode.DPadRight)
				if sel() ~= Up._card(i) then
					fail("→ ne va pas à la carte " .. i)
				end
			end
			tap(Enum.KeyCode.DPadRight)
			if sel() ~= Up._card(n) then
				fail("→ au bout ne rebondit pas")
			end
			for i = n - 1, 1, -1 do
				tap(Enum.KeyCode.DPadLeft)
				if sel() ~= Up._card(i) then
					fail("← ne va pas à la carte " .. i)
				end
			end
			-- ↑ onglet, ↑ bouton de mode ; ✕ puis □ font tourner le mode ×1 → ×10 → Max → ×1
			tap(Enum.KeyCode.DPadUp)
			if sel() ~= Up._tab("suggested") then
				fail("↑ depuis une carte ne va pas à l'onglet")
			end
			tap(Enum.KeyCode.DPadUp, 0.5)
			if sel() ~= Up._modeButton() then
				fail("↑ depuis l'onglet ne va pas au bouton de mode")
			end
			tap(Enum.KeyCode.ButtonA, 0.3)
			if Up.mode() ~= 10 then
				fail("✕ sur le bouton de mode ne passe pas à ×10")
			end
			tap(Enum.KeyCode.ButtonX, 0.3)
			if Up.mode() ~= 0 then
				fail("□ ne passe pas à Max")
			end
			tap(Enum.KeyCode.ButtonX, 0.3)
			if Up.mode() ~= 1 then
				fail("□ ne revient pas à ×1")
			end
			tap(Enum.KeyCode.DPadDown)
			tap(Enum.KeyCode.DPadDown)
			if sel() ~= Up._card(1) then
				fail("↓ ↓ depuis le bouton de mode ne revient pas à la carte 1")
			end
			-- R1 : Ranch, Plopettes, Atelier ; chaque ligne à la croix, entière dans la liste
			for _, tab in { "ranch", "helpers", "workshop" } do
				tap(Enum.KeyCode.ButtonR1, 0.5)
				if Up.currentTab() ~= tab then
					fail("R1 ne va pas à l'onglet " .. tab)
				end
				local list, shown = Up._list(tab), Up._shown(tab)
				if sel() ~= Up._row(shown[1]) then
					fail(tab .. " : sélection hors de la première ligne")
				end
				for i = 2, #shown do
					tap(Enum.KeyCode.DPadDown)
					if sel() ~= Up._row(shown[i]) then
						fail(tab .. " : ↓ ne va pas à la ligne " .. shown[i])
					elseif not inside(sel(), list) then
						fail(tab .. " : ligne " .. shown[i] .. " choisie mais coupée par la liste")
					end
				end
				tap(Enum.KeyCode.DPadDown)
				if sel() ~= Up._row(shown[#shown]) then
					fail(tab .. " : ↓ au bout ne rebondit pas")
				end
				for i = #shown - 1, 1, -1 do
					tap(Enum.KeyCode.DPadUp)
					if sel() ~= Up._row(shown[i]) then
						fail(tab .. " : ↑ ne va pas à la ligne " .. shown[i])
					elseif not inside(sel(), list) then
						fail(tab .. " : ligne " .. shown[i] .. " choisie mais coupée par la liste (↑)")
					end
				end
				-- stick droit : une page (4 lignes) plus bas, entière dans la liste
				if #shown > 5 then
					Gamepad.stick(h, Enum.KeyCode.Thumbstick2, Vector2.new(0, -1))
					Gamepad.stick(h, Enum.KeyCode.Thumbstick2, Vector2.new(0, 0))
					TvAudit.tick(h, 0.4)
					if sel() ~= Up._row(shown[5]) then
						fail(tab .. " : le stick droit ne descend pas d'une page")
					elseif not inside(sel(), list) then
						fail(tab .. " : page suivante choisie mais coupée par la liste")
					end
				end
			end
			-- R1 en boucle : Conseillé ; L1 : Atelier ; R1 : Conseillé
			tap(Enum.KeyCode.ButtonR1, 0.5)
			if Up.currentTab() ~= "suggested" then
				fail("R1 depuis l'Atelier ne revient pas au Conseillé")
			end
			tap(Enum.KeyCode.ButtonL1, 0.5)
			if Up.currentTab() ~= "workshop" then
				fail("L1 depuis le Conseillé ne va pas à l'Atelier")
			end
			tap(Enum.KeyCode.ButtonR1, 0.5)
			-- maintien de ✕ 0,7 s sur la carte 1 (Prête) : un seul BuyUpgrade, id canonique et niveau attendu
			local before = #TvAudit.sent(h, "BuyUpgrade")
			if sel() == Up._card(1) then
				TvAudit.tick(h, 0.5)
				Gamepad.press(h, Enum.KeyCode.ButtonA)
				S.run(c, 0.7)
				Gamepad.release(h, Enum.KeyCode.ButtonA)
				S.run(c, 0.2)
				local sent = TvAudit.sent(h, "BuyUpgrade")
				if #sent ~= before + 1 then
					fail(`maintien de ✕ 0,7 s : {#sent - before} BuyUpgrade au lieu de 1`)
				else
					local args = sent[#sent]
					local view = Up._view(Up._card(1))
					if args[1] ~= view.sendId or args[2] ~= 1 or type(args[3]) ~= "number" then
						fail("BuyUpgrade invalide : " .. tostring(args[1]) .. " " .. tostring(args[2]))
					end
				end
			else
				fail("R1 depuis l'Atelier : sélection hors de la carte 1")
			end
			-- ○ : rail sur « Améliorations », puis le jeu
			tap(Enum.KeyCode.ButtonB, 0.5)
			if PC.current() ~= nil or not PC.menuOpen() or sel() ~= PC.entryButton("Upgrades") then
				fail("○ ne revient pas au rail sur « Améliorations »")
			end
			if not TvAudit.toGame(h) then
				fail("○ répété ne rend pas la main au jeu")
			end
			return issues
		end

		it(
			"△ ↓ ✕, cartes, mode, onglets, lignes, stick, maintien, ○ : sans faute ni trace",
			function()
				local c = S.client({
					snap = S.snap(1, function(p)
						p.coins = 9.99e30
						p.confetti = 5000
					end),
					profile = { onboarding = DONE },
					ranch = { HelperMode = "active", Helpers = 0 },
				})
				local all = {}
				for _, res in { Vector2.new(1920, 1080), Vector2.new(1280, 720), Vector2.new(3840, 2160) } do
					for _, lang in { "fr", "en" } do
						TvAudit.setResolution(c.h, res)
						TvAudit.setLanguage(c.h, lang)
						for _, issue in play(c, `[{res.X}x{res.Y} {lang}] `) do
							table.insert(all, issue)
						end
					end
				end
				expect(table.concat(all, "\n")).toBe("")
				S.clean(c, expect)
			end
		)
	end)

	describe("fin des écrans", function()
		Screens.finish()
	end)
end
