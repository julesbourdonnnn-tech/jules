--!nocheck
-- Loading_game (paquet world, note INT-TV partie Loading, docs/04 §14.1, §18.2, §22.2) : l'écran de
-- chargement est dessiné en px TV (plus de facteur DRAWN_UNIT), suit LA règle télé de tous les écrans
-- (= Platform.uiScale) et n'a plus de mise en page de téléphone. Aux 3 résolutions télé (720p, 1080p,
-- 4K), EN et FR : textes ≥ 28 px TV (UITextSizeConstraint), « Réessayer » ≥ 80 px TV, icône ✕ ≥ 48 px
-- TV, tout dans la zone sûre de 5 %, glyphe PlayStation ; mêmes tailles réelles qu'avant la note en
-- 1080p (aucun changement visible) ; zéro trace ; API Roblox valide.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local SOURCE = "src/first/Loading.client.luau"
	local RESOLUTIONS = { Vector2.new(1280, 720), Vector2.new(1920, 1080), Vector2.new(3840, 2160) }

	local function run(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.console, viewport = opts.viewport })
		h.localPlayer.LocaleId = opts.locale or "en-us"
		MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
		h:run("ReplicatedFirst.Loading")
		MockInstance.classMethods.ReplicatedFirst = nil
		return h, h.localPlayer.PlayerGui:FindFirstChild("Loading")
	end

	local function zeroLog(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function stageScale(loading)
		return loading:FindFirstChild("Stage", true):FindFirstChildOfClass("UIScale").Scale
	end

	describe("Loading_game › px TV, sans téléphone", function()
		it("le code n'a plus de facteur DRAWN_UNIT ni de mise en page « écran bas »", function()
			local code = string.gsub(fs.readFile(SOURCE), "%-%-[^\n]*", "") -- code seul
			for _, word in
				{
					"DRAWN_UNIT",
					"FAIL_MARGIN",
					"FAIL_GAP",
					"MIN_RETRY_HEIGHT",
					"isLargeDisplay",
					"DisplaySize",
				}
			do
				expect({ word = word, found = string.find(code, word, 1, true) ~= nil }).toEqual({
					word = word,
					found = false,
				})
			end
		end)

		it(
			"échelle = Platform.uiScale sur tous les écrans (console comme PC), écran et bloc d'échec",
			function()
				local h0 = Harness.new({ mode = "client" })
				local Platform = h0:require("StarterPlayer.StarterPlayerScripts.Client.Util.Platform")
				for _, viewport in
					{
						Vector2.new(1280, 720),
						Vector2.new(1920, 1080),
						Vector2.new(3840, 2160),
						Vector2.new(2560, 1080),
						Vector2.new(1920, 1200),
						Vector2.new(800, 600),
					}
				do
					for _, console in { true, false } do
						local h, loading = run({ console = console, viewport = viewport })
						local expected = Platform.uiScale(viewport)
						expect(math.abs(stageScale(loading) - expected) < 1e-9).toBe(true)
						h:step(1, 21)
						expect(
							math.abs(loading:FindFirstChild("Fail", true).FailScale.Scale - expected) < 1e-9
						).toBe(true)
						zeroLog(h)
					end
				end
			end
		)

		it(
			"mêmes tailles réelles qu'avant la note en 1080p console : scène 390 × 450, bloc de 630",
			function()
				local h, loading = run({ console = true })
				h:step(1, 21)
				Layout.apply(h)
				local stage = Layout.rect(loading:FindFirstChild("Stage", true))
				expect(math.abs(stage.w - 390) < 1e-3 and math.abs(stage.h - 450) < 1e-3).toBe(true)
				local fail = Layout.rect(loading:FindFirstChild("Fail", true))
				expect(math.abs(fail.w - 630) < 1e-3).toBe(true)
				zeroLog(h)
			end
		)
	end)

	describe("Loading_game › disposition télé aux 3 résolutions, EN et FR", function()
		it(
			"textes ≥ 28 px TV, « Réessayer » ≥ 80 px TV, icône ≥ 48 px TV, zone sûre, glyphe PlayStation",
			function()
				for _, viewport in RESOLUTIONS do
					for _, locale in { "en-us", "fr-fr" } do
						local h, loading = run({ console = true, viewport = viewport, locale = locale })
						h:step(1, 21)
						local label = `{viewport.X}x{viewport.Y} {locale}`
						local fail = loading:FindFirstChild("Fail", true)
						local button = fail.RetryButton
						expect(button.Visible).toBe(true)
						expect(button.Size.Y.Offset >= 80).toBe(true)
						expect(fail.PadGlyph.Size.Y.Offset >= 48).toBe(true)
						for _, text in { fail.Message, button } do
							local c = text:FindFirstChildOfClass("UITextSizeConstraint")
							expect({ label = label, name = text.Name, min = c and c.MinTextSize }).toEqual({
								label = label,
								name = text.Name,
								min = 28,
							})
						end
						local issues = Gamepad.audit(h)
						expect({ label = label, issues = table.concat(issues, "\n") }).toEqual({
							label = label,
							issues = "",
						})
						-- la gelée et ses points restent dans la zone sûre, au-dessus du message
						Layout.apply(h)
						local blob = Layout.rect(loading:FindFirstChild("Blob", true))
						local dots = Layout.rect(loading:FindFirstChild("Dots", true))
						local message = Layout.rect(fail.Message)
						local x0, y0 = viewport.X * 0.05, viewport.Y * 0.05
						local x1, y1 = viewport.X * 0.95, viewport.Y * 0.95
						for _, r in { blob, dots, message } do
							expect(
								r.x >= x0 - 1e-3
									and r.y >= y0 - 1e-3
									and r.x + r.w <= x1 + 1e-3
									and r.y + r.h <= y1 + 1e-3
							).toBe(true)
						end
						expect(dots.y + dots.h <= message.y + 1e-3).toBe(true)
						zeroLog(h)
					end
				end
			end
		)

		it(
			"pendant le chargement : aucun texte (un enfant qui ne lit pas comprend), rien de sélectionné",
			function()
				for _, viewport in RESOLUTIONS do
					local h, loading = run({ console = true, viewport = viewport })
					h:step(1, 5)
					for _, d in loading:GetDescendants() do
						if
							(d.ClassName == "TextLabel" or d.ClassName == "TextButton")
							and d:FindFirstAncestor("Fail") == nil
						then
							error("texte pendant le chargement : " .. d.Name)
						end
					end
					expect(loading:FindFirstChild("Fail", true).Visible).toBe(false)
					expect(Gamepad.selected(h)).toBeNil()
					zeroLog(h)
				end
			end
		)

		it("API Roblox valide (ApiAudit) aux 3 résolutions, échec puis fermeture", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				for _, viewport in RESOLUTIONS do
					local h = run({ console = true, viewport = viewport })
					h:step(1, 21)
					h.localPlayer:SetAttribute("ClientReady", true)
					h:settle(3)
					expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
					zeroLog(h)
				end
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)

	-- Revue adversariale (paquet world) : robustesse par construction de l'écran de chargement
	describe("Loading_game › robustesse (revue)", function()
		it(
			"caméra absente au lancement, puis créée et remplacée : l'échelle télé suit l'écran réel",
			function()
				local h = Harness.new({ mode = "client", console = true, viewport = Vector2.new(1920, 1080) })
				local workspace = h.game.Workspace
				workspace.CurrentCamera = nil
				MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
				h:run("ReplicatedFirst.Loading")
				MockInstance.classMethods.ReplicatedFirst = nil
				local loading = h.localPlayer.PlayerGui:FindFirstChild("Loading")
				expect(stageScale(loading)).toBe(1) -- repli : écran de référence
				-- la caméra arrive (télé 4K) : échelle 2 dès l'image suivante
				local camera = MockInstance.new("Camera")
				camera.ViewportSize = Vector2.new(3840, 2160)
				camera.Parent = workspace
				workspace.CurrentCamera = camera
				h:step(1 / 60, 2)
				expect(stageScale(loading)).toBe(2)
				-- caméra remplacée (720p) : suivie aussi
				local other = MockInstance.new("Camera")
				other.ViewportSize = Vector2.new(1280, 720)
				other.Parent = workspace
				workspace.CurrentCamera = other
				h:step(1 / 60, 2)
				expect(math.abs(stageScale(loading) - 2 / 3) < 1e-9).toBe(true)
				-- taille d'écran pas encore connue (1 × 1) : jamais d'échelle absurde
				other.ViewportSize = Vector2.new(1, 1)
				h:step(1 / 60, 2)
				expect(stageScale(loading)).toBe(1)
				zeroLog(h)
			end
		)

		it(
			"fondu de fermeture jamais terminé (Completed jamais reçu) : l'écran est détruit quand même",
			function()
				local h, loading = run({ console = true })
				h:step(1 / 10, 5)
				local methods = MockInstance.classMethods.Tween
				local original = methods.Play
				methods.Play = function() end -- le moteur ne joue jamais le fondu
				local ok, err = pcall(function()
					h.localPlayer:SetAttribute("ClientReady", true)
					h:settle(2)
					expect(loading.Parent ~= nil).toBe(true) -- le fondu « tourne » encore
					h:step(1 / 30, 30) -- 1 s d'images : la fermeture ne dépend pas d'une fin d'animation
				end)
				methods.Play = original
				expect(ok and true or err).toBe(true)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
				zeroLog(h)
			end
		)
	end)
end
