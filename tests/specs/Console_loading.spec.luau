--!nocheck
-- Écran de chargement sur console et téléviseur (Comet Conga, Console_hud, partie « écran de
-- chargement », reprise telle quelle) : échelle « 10 pieds », « Réessayer » sélectionné d'office à la
-- manette avec l'icône ✕ PlayStation, audit console propre, sélection rendue au stick à la fermeture,
-- constantes d'échelle recopiées de Config/Console (écran autonome, non répliqué) ; API Roblox
-- auditée (ApiAudit).
-- Note INT-TV, partie Loading (paquet world, étape 0, docs/04 §22.2) : l'écran est désormais dessiné
-- en px TV (facteur DRAWN_UNIT de 1,5 retiré, dimensions × 1,5) et suit LA règle télé de tous les
-- écrans (Platform.uiScale). Mêmes tailles réelles à l'écran : l'échelle attendue passe de 1,5 à 1
-- en 1080p et de 3 à 2 en 4K ; sur PC, la règle d'origine « × 1,2 bornée » (écran ordinaire et
-- téléphone) disparaît au profit de la règle télé (0,667 en 1280 × 720).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local PS = Gamepad.PS_GLYPHS

	local function expectEmpty(list, label)
		expect({ label = label, issues = table.concat(list, "\n") }).toEqual({ label = label, issues = "" })
	end

	local function glyphOf(frame)
		return {
			key = frame:GetAttribute("GlyphKey"),
			mode = frame:GetAttribute("GlyphMode"),
			image = frame.Image.Image,
			visible = Layout.visible(frame),
		}
	end

	local function psGlyph(key)
		local ps = ({
			ButtonA = "ButtonCross",
			ButtonY = "ButtonTriangle",
		})[key] or key
		return { key = key, mode = "image", image = PS .. ps .. "@2x.png", visible = true }
	end

	describe("Console › écran de chargement", function()
		local SOURCE = "src/first/Loading.client.luau"

		local function run(opts)
			opts = opts or {}
			local h = Harness.new({ mode = "client", console = opts.console, viewport = opts.viewport })
			MockInstance.classMethods.ReplicatedFirst = {
				RemoveDefaultLoadingScreen = function() end,
			}
			h:run("ReplicatedFirst.Loading")
			MockInstance.classMethods.ReplicatedFirst = nil
			return h, h.localPlayer.PlayerGui:FindFirstChild("Loading")
		end

		local function stageScale(loading)
			return loading:FindFirstChild("Stage", true):FindFirstChildOfClass("UIScale").Scale
		end

		it(
			"console 1080p : échelle 1 (px TV), « Réessayer » sélectionné avec l'icône ✕ PlayStation",
			function()
				local h, loading = run({ console = true })
				expect(stageScale(loading)).toBe(1)
				expect(Gamepad.selected(h)).toBeNil()
				h:step(1, 21)
				local fail = loading:FindFirstChild("Fail", true)
				expect(fail.Visible).toBe(true)
				expect(fail.FailScale.Scale).toBe(1)
				local button = fail.RetryButton
				expect(Gamepad.selected(h)).toBe(button)
				expect(button.SelectionImageObject ~= nil).toBe(true)
				expect(glyphOf(fail.PadGlyph)).toEqual(psGlyph("ButtonA"))
				Layout.apply(h)
				local g, b = Layout.rect(fail.PadGlyph), Layout.rect(button)
				expect(g.x + g.w <= b.x).toBe(true)
				expect(math.abs((g.y + g.h / 2) - (b.y + b.h / 2)) < 1).toBe(true)
				expectEmpty(Gamepad.audit(h), "audit chargement")
				-- ✕ sur « Réessayer » : téléportation demandée
				local teleports = 0
				MockInstance.classMethods.TeleportService.Teleport = function()
					teleports += 1
				end
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(teleports).toBe(1)
				-- le client finit par être prêt : l'écran se ferme et rend la main au stick
				h.localPlayer:SetAttribute("ClientReady", true)
				h:settle(3)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
				expect(Gamepad.selected(h)).toBeNil()
			end
		)

		it(
			"téléviseur 4K : sans plafond (2) ; PC 1280 × 720 : même règle télé (0,667), rien de sélectionné",
			function()
				local _, tv = run({ console = true, viewport = Vector2.new(3840, 2160) })
				expect(stageScale(tv)).toBe(2)
				local h, pc = run()
				expect(math.abs(stageScale(pc) - 2 / 3) < 1e-9).toBe(true)
				h:step(1, 21)
				local fail = pc:FindFirstChild("Fail", true)
				expect(fail.Visible).toBe(true)
				expect(math.abs(fail.FailScale.Scale - 2 / 3) < 1e-9).toBe(true)
				expect(fail:FindFirstChild("PadGlyph")).toBeNil()
				expect(Gamepad.selected(h)).toBeNil()
				-- manette prise en main pendant l'écran d'échec : « Réessayer » sélectionné, icône ✕
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				expect(Gamepad.selected(h)).toBe(fail.RetryButton)
				expect(fail:FindFirstChild("PadGlyph") ~= nil).toBe(true)
				-- manette branchée sur PC : « Réessayer » sélectionné aussi
				local h2 = Harness.new({ mode = "client" })
				h2.game.UserInputService.GamepadEnabled = true
				MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
				h2:run("ReplicatedFirst.Loading")
				MockInstance.classMethods.ReplicatedFirst = nil
				h2:step(1, 21)
				expect(Gamepad.selected(h2)).toBe(
					h2.localPlayer.PlayerGui.Loading:FindFirstChild("RetryButton", true)
				)
			end
		)

		it("constantes d'échelle égales à Config/Console (écran autonome, non répliqué)", function()
			local h = Harness.new({ mode = "client" })
			local Console = h:require("ReplicatedStorage.Shared.Config.Console")
			local source = fs.readFile(SOURCE)
			local refX, refY = string.match(source, "local REFERENCE = Vector2%.new%((%d+), (%d+)%)")
			expect(tonumber(refX)).toBe(Console.Reference.X)
			expect(tonumber(refY)).toBe(Console.Reference.Y)
			local tvMin = string.match(source, "local TV_SCALE_MIN = ([%d%.]+)")
			expect(tonumber(tvMin)).toBe(Console.TvScale.Min)
		end)
	end)

	describe("Console › « Réessayer » : curseur de UI/Root.selectionImage (release r4)", function()
		it("trait blanc de 6 px, liseré sombre de 2 px, débord 4 px, coins 16 / 22", function()
			local h = Harness.new({ mode = "client", console = true })
			MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
			h:run("ReplicatedFirst.Loading")
			MockInstance.classMethods.ReplicatedFirst = nil
			local loading = h.localPlayer.PlayerGui:FindFirstChild("Loading")
			h:step(1, 21)
			local button = loading:FindFirstChild("Fail", true).RetryButton
			expect(Gamepad.selected(h)).toBe(button)
			local image = button.SelectionImageObject
			local ref = Harness.new({ mode = "client", console = true })
				:require("StarterPlayer.StarterPlayerScripts.Client.UI.Root")
				.selectionImage()
			local function shape(frame)
				local stroke = frame:FindFirstChildOfClass("UIStroke")
				local corner = frame:FindFirstChildOfClass("UICorner")
				local edge = frame:FindFirstChild("Edge")
				local edgeStroke = edge and edge:FindFirstChildOfClass("UIStroke")
				local edgeCorner = edge and edge:FindFirstChildOfClass("UICorner")
				return {
					size = tostring(frame.Size),
					anchor = tostring(frame.AnchorPoint),
					color = tostring(stroke.Color),
					thickness = stroke.Thickness,
					mode = stroke.ApplyStrokeMode.Name,
					corner = tostring(corner.CornerRadius),
					edgeSize = edge and tostring(edge.Size),
					edgeAnchor = edge and tostring(edge.AnchorPoint),
					edgeColor = edgeStroke and tostring(edgeStroke.Color),
					edgeThickness = edgeStroke and edgeStroke.Thickness,
					edgeMode = edgeStroke and edgeStroke.ApplyStrokeMode.Name,
					edgeCorner = edgeCorner and tostring(edgeCorner.CornerRadius),
				}
			end
			expect(shape(image)).toEqual(shape(ref))
			expect(shape(image).thickness).toBe(6)
			expect(shape(image).edgeThickness).toBe(2)
			h.localPlayer:SetAttribute("ClientReady", true)
			h:settle(3)
			expect(#h.errors).toBe(0)
		end)
	end)

	describe("Console › écran de chargement : API Roblox", function()
		it("console, échec puis manette : API valide (ApiAudit), aucune erreur", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h = Harness.new({ mode = "client", console = true })
				MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
				h:run("ReplicatedFirst.Loading")
				MockInstance.classMethods.ReplicatedFirst = nil
				h:step(1, 21)
				Gamepad.tap(h, Enum.KeyCode.DPadDown)
				h.localPlayer:SetAttribute("ClientReady", true)
				h:settle(3)
				expect(#h.errors).toBe(0)
				expect(table.concat(h:warnings(), "\n")).toBe("")
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
