--!nocheck
-- ReturnScreen (paquet client-panels) : écran de retour (GDD §7.2, §4.19 ; docs/04 §13.6) sur
-- Celebrate "return" : fenêtre bloquante de FocusGuard, « Super ! » sélectionné d'office, ✕ ou ○
-- ferment (✕ martelé dans les 0,35 s ignoré), textes EN / FR, charges hostiles, disposition télé aux
-- 3 résolutions. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local DATA = {
		seconds = 5 * 3600 + 12 * 60,
		uid = "u1",
		species = 5,
		grew = 123456,
		pot = 7800,
		splorchReady = false,
		nearlyReady = true,
	}

	local function celebrate(h, data)
		h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "return", data = data })
		h:settle(2)
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function card(h)
		return h.localPlayer.PlayerGui.Return.Safe.Card
	end

	describe("ReturnScreen", function()
		it(
			"Celebrate return : fenêtre bloquante, « Super ! » sélectionné, textes de l'absence",
			function()
				local h = TvAudit.client({})
				local RS = TvAudit.mod(h, "UI.ReturnScreen")
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				expect(RS.isOpen()).toBe(false)
				celebrate(h, DATA)
				expect(RS.isOpen()).toBe(true)
				expect(FG.top().name).toBe("return")
				expect(FG.top().blocking).toBe(true)
				local c = card(h)
				expect(h.game.GuiService.SelectedObject).toBe(c.Super)
				expect(c.Away.Text).toContain("5 h 12")
				expect(c.Grew.Text).toContain("Mochi Mew")
				expect(c.Grew.Text).toContain("123")
				expect(c.Pot.Text).toContain("7,800")
				expect(c.Splorch.Visible).toBe(true)
				expect(c.Splorch.Text).toBe("Almost ready for the Grand Splorch!")
				-- les touches du jeu restent déliées (aucune liaison du jeu derrière la fenêtre)
				expect(#TvAudit.boundBehindWindow(h)).toBe(0)
				clean(h)
			end
		)

		it("✕ martelé (moins de 0,35 s) ignoré, puis ✕ ferme ; ○ ferme aussi", function()
			local h = TvAudit.client({})
			local RS = TvAudit.mod(h, "UI.ReturnScreen")
			celebrate(h, DATA)
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			expect(RS.isOpen()).toBe(true)
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			expect(RS.isOpen()).toBe(false)
			expect(h.localPlayer.PlayerGui.Return.Enabled).toBe(false)
			expect(h.game.GuiService.SelectedObject).toBeNil()
			-- de nouveau, fermé par ○
			celebrate(h, DATA)
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(RS.isOpen()).toBe(false)
			clean(h)
		end)

		it(
			"Grand Splorch prêt l'emporte sur « presque prêt » ; rien à dire : lignes cachées",
			function()
				local h = TvAudit.client({})
				celebrate(h, {
					seconds = 900,
					uid = "u",
					species = 1,
					grew = 0,
					pot = 0,
					splorchReady = true,
					nearlyReady = true,
				})
				local c = card(h)
				expect(c.Splorch.Text).toBe("Grand Splorch ready!")
				expect(c.Grew.Visible).toBe(false)
				expect(c.Pot.Visible).toBe(false)
				expect(c.Away.Text).toContain("15 min")
				clean(h)
			end
		)

		it("charges hostiles (NaN, infini, chaînes, tables) : écran sobre, aucune erreur", function()
			local h = TvAudit.client({})
			local RS = TvAudit.mod(h, "UI.ReturnScreen")
			celebrate(h, { seconds = 0 / 0, species = "x", grew = math.huge, pot = -5, splorchReady = "oui" })
			expect(RS.isOpen()).toBe(true)
			local c = card(h)
			expect(c.Pot.Visible).toBe(false)
			expect(c.Splorch.Visible).toBe(false)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", "pas une table")
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "return", data = 5 })
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "autre", data = {} })
			RS.show(nil)
			clean(h)
		end)

		it(
			"disposition télé : 1080p, 4K, 720p, anglais et français — ni chevauchement, ni texte coupé",
			function()
				local h = TvAudit.client({})
				celebrate(h, DATA)
				local issues = {}
				for _, res in { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) } do
					TvAudit.setResolution(h, res)
					for _, lang in { "en", "fr" } do
						TvAudit.setLanguage(h, lang)
						for _, issue in TvAudit.check(h, `[{res.X} {lang}] `) do
							table.insert(issues, issue)
						end
					end
				end
				expect(table.concat(issues, "\n")).toBe("")
				expect(card(h).Super.Label.Text).toBe("Super !")
				clean(h)
			end
		)
	end)
	-- Lot B3, étape 5 (D21) : pendant une remontée vers le record, le prestige de la boucle est un Petit
	-- Splorch : l'écran de retour le nomme (GDD v2.0 §4.27 « Des textes vrais »)
	describe("ReturnScreen › v2.0 (lot B3, étape 5)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }
		local function regainSnap(version)
			return S.snap(version or 1, function(p)
				p.ascend = 1
				p.R = 3
				p.bestR = 10
			end)
		end
		local function client(opts)
			local c =
				S.client({ profile = { version = 2, onboarding = DONE }, snap = opts.snap, lang = opts.lang })
			if opts.flags ~= false then
				S.event(c, opts.flags or UpgradeScreen.V2_ALL)
			end
			return c
		end
		local function show(c, ready, nearly)
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "return",
				data = {
					seconds = 3600,
					uid = "",
					species = 1,
					grew = 10,
					pot = 5,
					splorchReady = ready,
					nearlyReady = nearly,
				},
			})
			c.h:settle(2)
			return card(c.h)
		end

		it(
			"remontée (A ≥ 1, r < Record R) et PetitSplorch ouvert : « Petit Splorch prêt ! » / « Presque prêt… »",
			function()
				local c = client({ snap = regainSnap() })
				local f = show(c, true, false)
				expect(f.Splorch.Text).toBe("Petit Splorch ready!")
				local RS = TvAudit.mod(c.h, "UI.ReturnScreen")
				S.run(c, 0.5)
				RS._close()
				S.run(c, 0.5)
				f = show(c, false, true)
				expect(f.Splorch.Text).toBe("Almost ready for the Petit Splorch!")
				S.clean(c, expect)
				local fr = client({ snap = regainSnap(), lang = "fr" })
				expect(show(fr, true, false).Splorch.Text).toBe("Petit Splorch prêt !")
				S.clean(fr, expect)
			end
		)

		it(
			"PetitSplorch coupé, hors remontée ou sans instantané : les textes de la v1.3 ; la ligne suit l'instantané arrivé après l'écran",
			function()
				local flags = table.clone(UpgradeScreen.V2_ALL)
				flags.PetitSplorch = nil
				local c = client({ snap = regainSnap(), flags = flags })
				expect(show(c, true, false).Splorch.Text).toBe("Grand Splorch ready!")
				S.clean(c, expect)
				local loop = client({ snap = S.snap(1) })
				expect(show(loop, true, false).Splorch.Text).toBe("Grand Splorch ready!")
				S.clean(loop, expect)
				-- v1.3 : aucun instantané, aucun features.v2
				local v13 = client({ flags = false })
				local f = show(v13, false, true)
				expect(f.Splorch.Text).toBe("Almost ready for the Grand Splorch!")
				-- l'instantané de la remontée et les interrupteurs arrivent écran ouvert : la ligne suit
				S.event(v13, UpgradeScreen.V2_ALL)
				S.patch(v13, regainSnap(2))
				expect(f.Splorch.Text).toBe("Almost ready for the Petit Splorch!")
				S.clean(v13, expect)
			end
		)
	end)
end
