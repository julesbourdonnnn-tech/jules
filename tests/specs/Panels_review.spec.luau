--!nocheck
-- Panneaux (paquet client-panels) : défauts trouvés à la relecture dans Ranch, Settings,
-- OutfitPreview, Squishydex et Leaderboards, chacun reproduit avant sa correction. Zéro trace.
--   * Ranch : Celebrate « unlock » (titres de la semaine) écouté seulement après la première
--     ouverture du panneau (construction paresseuse) : un titre débloqué à l'arrivée restait verrouillé ;
--   * Ranch › Style : la sélection par défaut doit être l'objet équipé de la 1re sous-liste (Selle,
--     GDD §10.6, docs/04 §14.2), pas celle visitée en dernier ;
--   * Settings : un interrupteur dont l'envoi est retenu par le débit du client restait affiché dans
--     l'état contraire au profil (aucun DataPatch ne venait le recaler) ;
--   * OutfitPreview : squishy choisi parti de l'enclos pendant l'aperçu : « Mettre » envoyait encore
--     EquipOutfit pour lui ;
--   * Squishydex : la fiche d'une espèce ouverte ne suivait pas le profil (mutation trouvée pendant
--     qu'on la regarde) ;
--   * Leaderboards : nom coupé à 40 octets au milieu d'un caractère UTF-8 (texte invalide à l'écran).
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function press(h, obj)
		TvAudit.tick(h, 0.5)
		h.game.GuiService.SelectedObject = obj
		h:settle(1)
		Gamepad.tap(h, Enum.KeyCode.ButtonA)
		h:settle(1)
	end

	local function patch(h, values)
		h:fireClient("ReplicatedStorage.Remotes.DataPatch", values, {})
		h:settle(3)
	end

	describe("Panels/Ranch (relecture)", function()
		it(
			"titre de la semaine débloqué AVANT la première ouverture du panneau : équipable dans Style",
			function()
				local h = TvAudit.client({})
				h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "unlock", data = { kind = "title", id = "stamp_hunter" } }
				)
				h:settle(2)
				local PC = TvAudit.mod(h, "UI.PanelController")
				local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
				PC.open("Ranch", "style")
				TvAudit.tick(h, 0.5)
				press(h, Ranch._styleKindButton("title"))
				local cell = Ranch._styleCell("title", "stamp_hunter")
				expect(cell ~= nil).toBe(true)
				expect(cell:GetAttribute("Locked")).toBe(false)
				press(h, cell)
				local sent = TvAudit.sent(h, "EquipCosmetic")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe("title")
				expect(sent[1][2]).toBe("stamp_hunter")
				clean(h)
			end
		)

		it(
			"Style : la sélection par défaut est l'objet équipé de la Selle, même après une autre sous-liste",
			function()
				local h = TvAudit.client({})
				local PC = TvAudit.mod(h, "UI.PanelController")
				local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
				PC.open("Ranch", "style")
				TvAudit.tick(h, 0.5)
				expect(h.game.GuiService.SelectedObject).toBe(Ranch._styleCell("saddle", "classic"))
				press(h, Ranch._styleKindButton("trail"))
				expect(Ranch._state().styleKind).toBe("trail")
				PC.closeAll()
				TvAudit.tick(h, 0.5)
				PC.open("Ranch", "style")
				TvAudit.tick(h, 0.5)
				expect(Ranch._state().styleKind).toBe("saddle")
				expect(h.game.GuiService.SelectedObject).toBe(Ranch._styleCell("saddle", "classic"))
				-- L1 / R1 vers Style : idem
				TvAudit.tick(h, 0.5)
				press(h, Ranch._styleKindButton("flag"))
				Ranch.setTab("pads")
				Ranch.setTab("style")
				expect(Ranch._state().styleKind).toBe("saddle")
				clean(h)
			end
		)
	end)

	describe("Panels/Settings (relecture)", function()
		it(
			"interrupteur martelé : l'envoi retenu par le débit est refusé et l'interrupteur revient",
			function()
				local h = TvAudit.client({})
				local PC = TvAudit.mod(h, "UI.PanelController")
				local Settings = TvAudit.mod(h, "UI.Panels.Settings")
				local Prefs = TvAudit.mod(h, "Util.Prefs")
				local sounds = {}
				local Audio = TvAudit.mod(h, "Controllers.AudioController")
				local play = Audio.play
				Audio.play = function(name, ...)
					table.insert(sounds, name)
					return play(name, ...)
				end
				PC.open("Settings")
				TvAudit.tick(h, 0.5)
				local toggle = Settings._controlFor("music")
				expect(toggle:GetAttribute("On")).toBe(true)
				h.game.GuiService.SelectedObject = toggle
				h:settle(1)
				table.clear(sounds)
				-- 5 appuis dans la même seconde : le seau du client (4 par seconde) retient le 5e
				for _ = 1, 5 do
					Gamepad.tap(h, Enum.KeyCode.ButtonA)
				end
				h:settle(2)
				expect(#TvAudit.sent(h, "SetSetting")).toBe(4)
				-- 4 bascules envoyées : l'interrupteur montre l'état qu'elles donnent (celui du départ)
				expect(toggle:GetAttribute("On")).toBe(true)
				expect(Prefs.get("music")).toBe(true)
				expect(table.find(sounds, "Error") ~= nil).toBe(true)
				clean(h)
			end
		)
	end)

	describe("Panels/OutfitPreview (relecture)", function()
		it("le squishy choisi part au Dodo pendant l'aperçu : « Mettre » vise le suivant", function()
			local h = TvAudit.client({
				profile = {
					squishies = {
						big = TvAudit.squishy(5, { z = 900 }),
						small = TvAudit.squishy(2, { z = 10 }),
					},
					outfits = { owned = { sweater = 1 }, worn = {} },
				},
			})
			local PC = TvAudit.mod(h, "UI.PanelController")
			local OP = TvAudit.mod(h, "UI.Panels.OutfitPreview")
			local State = TvAudit.mod(h, "Controllers.StateController")
			PC.open("Ranch", "style")
			PC.open("OutfitPreview", "sweater")
			TvAudit.tick(h, 0.5)
			expect(OP._state().uid).toBe("big")
			local sq = table.clone(State.get("squishies"))
			local moved = table.clone(sq.big)
			moved.at = "dodo"
			sq.big = moved
			patch(h, { squishies = sq })
			expect(OP._state().uid).toBe("small")
			expect(OP._state().model).toBe(true)
			press(h, PC.window("OutfitPreview").Body.Wear)
			local sent = TvAudit.sent(h, "EquipOutfit")
			expect(#sent).toBe(1)
			expect(sent[1][2]).toBe("small")
			clean(h)
		end)
	end)

	describe("Panels/Squishydex (relecture)", function()
		it("fiche ouverte : une mutation trouvée pendant qu'on la regarde apparaît aussitôt", function()
			local mut = table.create(26, 0)
			mut[1] = 1
			local h = TvAudit.client({
				profile = {
					dex = { mut = mut, stars = table.create(26, 0), fam = table.create(7, 0), rewards = 0 },
				},
			})
			local PC = TvAudit.mod(h, "UI.PanelController")
			local Dex = TvAudit.mod(h, "UI.Panels.Squishydex")
			local Prefs = TvAudit.mod(h, "Util.Prefs")
			PC.open("Squishydex")
			TvAudit.tick(h, 0.5)
			press(h, h.game.GuiService.SelectedObject) -- ✕ sur la 1re espèce : sa fiche
			expect(Dex._sheet().open).toBe(true)
			local sheet = PC.window("Squishydex").Body.Sheet
			expect(sheet.Mutation1.Label.Text).toBe(Prefs.t("panel.dex.unknown"))
			local mut2 = table.clone(mut)
			mut2[1] = 1 + 2 -- page + mutation 1
			patch(
				h,
				{ dex = { mut = mut2, stars = table.create(26, 0), fam = table.create(7, 0), rewards = 0 } }
			)
			expect(Dex._sheet().open).toBe(true)
			expect(sheet.Mutation1.Label.Text ~= Prefs.t("panel.dex.unknown")).toBe(true)
			expect(sheet.Found.Text).toBe(Prefs.t("panel.dex.sheet.found", { n = 1, max = 9 }))
			clean(h)
		end)
	end)

	describe("Panels/Shop (relecture)", function()
		it(
			"Squish Party : une fête qui commence ou finit pendant que la Boutique est ouverte cache / remontre le bouton",
			function()
				local h = TvAudit.client({
					before = TvAudit.enableShop,
					profile = {
						stats = (function()
							local st = TvAudit.defaults().stats
							st.playSeconds = 9999
							return st
						end)(),
					},
				})
				local PC = TvAudit.mod(h, "UI.PanelController")
				local Shop = TvAudit.mod(h, "UI.Panels.Shop")
				local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				local boost = { kind = "", untilT = 0, byName = "" }
				WSC.event = function()
					return { boost = boost }
				end
				PC.open("Shop", "party")
				TvAudit.tick(h, 0.5)
				local buy = Shop._buyButton("SquishParty")
				expect(buy.Visible).toBe(true)
				expect(h.game.GuiService.SelectedObject).toBe(buy)
				-- un autre joueur lance une fête : EventState (WorldStateController.EventChanged)
				boost = { kind = "squish", untilT = Clock.now() + 60, byName = "" }
				WSC.EventChanged:Fire({ boost = boost })
				h:settle(2)
				expect(buy.Visible).toBe(false)
				-- la sélection ne reste pas sur le bouton caché, sans sauvetage compté
				local sel = h.game.GuiService.SelectedObject
				expect(sel ~= nil and sel ~= buy).toBe(true)
				-- la fête finit à son heure (même sans nouvel EventState)
				Clock.advance(61)
				h:step(1 / 60, 2)
				h:settle(2)
				expect(buy.Visible).toBe(true)
				TvAudit.tick(h, 0.5)
				expect(TvAudit.mod(h, "UI.FocusGuard").rescues()).toBe(0)
				clean(h)
			end
		)
	end)

	describe("Panels/Leaderboards (relecture)", function()
		it("nom long en UTF-8 : coupé sur une frontière de caractère (texte toujours valide)", function()
			local h = TvAudit.client({})
			local PC = TvAudit.mod(h, "UI.PanelController")
			local name = "a" .. string.rep("é", 30) -- 61 octets ; l'octet 40 est au milieu d'un « é »
			h:fireClient("ReplicatedStorage.Remotes.LeaderboardState", {
				week = 1,
				boards = {
					stamps = {
						top = { { rank = 1, userId = 99, name = name, value = 10 } },
						server = {},
						mine = 0,
						minePrev = 0,
						myServerRank = 0,
					},
				},
			})
			h:settle(2)
			PC.open("Leaderboards")
			TvAudit.tick(h, 0.5)
			local row = PC.window("Leaderboards").Body.Row1
			expect(row.Visible).toBe(true)
			local text = row:FindFirstChild("Name").Text
			expect(utf8.len(text) ~= nil).toBe(true)
			expect(#text <= 40).toBe(true)
			expect(string.sub(text, 1, 1)).toBe("a")
			clean(h)
		end)
	end)
end
