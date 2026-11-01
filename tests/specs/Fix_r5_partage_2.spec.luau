--!nocheck
-- Correctif r5-partage-2 : écran d'échec du chargement (src/first/Loading.client.luau) sur un
-- téléphone à l'horizontale (GDD §10.3, docs/07-console-ps5.md §3)
--   * avant : bloc « Ton Nid se réveille… » + « Réessayer » posé à 68 % de la hauteur, taille fixe
--     (420 × 150) et non mis à l'échelle hors téléviseur : en 640 × 360, « Réessayer » couvrait
--     y 306,8-370,8 (10,8 px hors de l'écran), en 667 × 375 y 317-381 (6 px hors de l'écran), et le
--     bas touchait la barre d'accueil de l'iPhone (IgnoreGuiInset)
--   * après : sur un écran bas, le bloc rétrécit jusqu'à tenir sous les points de chargement
--     (« Réessayer » ≥ 48 px réels) et se colle en bas avec une marge ; « Réessayer » et son curseur
--     de sélection restent entiers ; la scène remonte si même la taille minimale ne tient pas
--   * PC et téléviseur : placement et échelle inchangés (68 %, échelle 1 ou « 10 pieds »)
-- Géométrie : tests/harness/Layout (UIScale autour de l'ancre, comme Roblox).
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- curseur de sélection de « Réessayer » : débord 4 + trait blanc 6 + liseré sombre 2 (px du bouton)
	local CURSOR = 12
	local MARGIN = 8 -- px réels au moins entre le bas du curseur et le bas de l'écran
	local MIN_RETRY = 48 -- px réels : bouton secondaire du GDD §10 (80 px × 0,6)
	local EPS = 1e-3 -- UDim2 garde des float32

	-- Le vrai script Loading, en français, sur l'écran `viewport` ; ClientReady jamais posé
	local function run(opts)
		local h = Harness.new({
			mode = "client",
			touch = opts.touch,
			console = opts.console,
			viewport = opts.viewport,
		})
		h.localPlayer.LocaleId = opts.locale or "fr-fr"
		if opts.reducedMotion then
			h.game.GuiService.ReducedMotionEnabled = true
		end
		MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
		h:run("ReplicatedFirst.Loading")
		MockInstance.classMethods.ReplicatedFirst = nil
		return h, h.localPlayer.PlayerGui:FindFirstChild("Loading")
	end

	local function parts(loading)
		local fail = loading:FindFirstChild("Fail", true)
		return {
			fail = fail,
			button = fail:FindFirstChild("RetryButton"),
			message = fail:FindFirstChild("Message"),
			dots = loading:FindFirstChild("Dots", true),
			stage = loading:FindFirstChild("Stage", true),
			nebby = loading:FindFirstChild("Nebby", true),
		}
	end

	-- Rectangles d'écran (px) après mise en page
	local function rects(h, loading)
		Layout.apply(h)
		local p = parts(loading)
		return {
			fail = Layout.rect(p.fail),
			button = Layout.rect(p.button),
			message = Layout.rect(p.message),
			dots = Layout.rect(p.dots),
			stage = Layout.rect(p.stage),
		},
			p
	end

	local function bottom(r)
		return r.y + r.h
	end

	-- Écran d'échec affiché : tout tient, rien ne chevauche le Puffkin ni ses points
	local function expectFits(h, loading, viewport, label)
		local r, p = rects(h, loading)
		expect({ label = label, fail = p.fail.Visible, button = p.button.Visible }).toEqual({
			label = label,
			fail = true,
			button = true,
		})
		local b = r.button
		local W, H = viewport.X, viewport.Y
		local report = {
			label = label,
			-- « Réessayer » et son curseur entiers, à MARGIN px au moins du bas
			retryOnScreen = bottom(b) + CURSOR * b.k <= H - MARGIN + EPS and b.y >= 0,
			-- cible tactile
			retryTall = b.h >= MIN_RETRY - EPS,
			-- bloc dans la largeur
			blockInWidth = r.fail.x >= -EPS and r.fail.x + r.fail.w <= W + EPS,
			-- message sous les points de chargement, jamais par-dessus
			messageBelowDots = r.message.y >= bottom(r.dots) - EPS,
			-- message au-dessus du bouton
			messageAboveRetry = bottom(r.message) <= b.y + EPS,
			-- scène entière à l'écran
			stageOnScreen = r.stage.y >= -EPS,
		}
		expect(report).toEqual({
			label = label,
			retryOnScreen = true,
			retryTall = true,
			blockInWidth = true,
			messageBelowDots = true,
			messageAboveRetry = true,
			stageOnScreen = true,
		})
		return r, p
	end

	describe("Fix r5-partage-2 › Chargement : « Réessayer » entier sur un téléphone", function()
		it("640 × 360 et 667 × 375 (cas du rapport) : « Réessayer » à 8 px au moins du bas", function()
			for _, viewport in { Vector2.new(640, 360), Vector2.new(667, 375) } do
				local h, loading = run({ touch = true, viewport = viewport })
				h:step(1, 45)
				local label = `{viewport.X}x{viewport.Y}`
				local r = expectFits(h, loading, viewport, label)
				expect({ label = label, bottomOk = bottom(r.button) <= viewport.Y - MARGIN }).toEqual({
					label = label,
					bottomOk = true,
				})
				expect(#h.errors).toBe(0)
			end
		end)

		it("autres téléphones et tablette à l'horizontale, FR et EN : tout tient", function()
			for _, viewport in
				{
					Vector2.new(568, 320), -- 4 pouces : taille minimale, la scène remonte
					Vector2.new(740, 360),
					Vector2.new(812, 375),
					Vector2.new(844, 390),
					Vector2.new(932, 430),
					Vector2.new(1024, 768),
					Vector2.new(360, 640), -- portrait
				}
			do
				for _, locale in { "fr-fr", "en-us" } do
					local h, loading = run({ touch = true, viewport = viewport, locale = locale })
					h:step(1, 45)
					expectFits(h, loading, viewport, `{viewport.X}x{viewport.Y} {locale}`)
					expect(#h.errors).toBe(0)
				end
			end
		end)

		it("animation d'entrée (rebond) : « Réessayer » ne sort jamais de l'écran", function()
			local viewport = Vector2.new(640, 360)
			local h, loading = run({ touch = true, viewport = viewport })
			h:step(1, 19)
			h:step(0.5, 1)
			local worst, frames = -math.huge, 0
			for _ = 1, 60 do -- 19,5 s → 20,5 s : apparition (0,3 s, Back Out) image par image
				h:step(1 / 60, 1)
				local p = parts(loading)
				if p.button.Visible then
					frames += 1
					Layout.apply(h)
					worst = math.max(worst, bottom(Layout.rect(p.button)))
				end
			end
			expect(frames).toBeGreaterThan(18)
			expect(worst <= viewport.Y - MARGIN + EPS).toBe(true)
		end)

		it("Mouvement réduit : même placement, sans animation", function()
			local viewport = Vector2.new(667, 375)
			local h, loading = run({ touch = true, viewport = viewport, reducedMotion = true })
			h:step(1, 21)
			expectFits(h, loading, viewport, "réduit")
		end)

		it("écran tourné ou redimensionné pendant l'échec : replacé à chaque fois", function()
			local h, loading = run({ viewport = Vector2.new(1280, 720) })
			h:step(1, 21)
			local camera = h.game.Workspace.CurrentCamera
			local r0, p = rects(h, loading)
			local stageY0 = r0.stage.y
			for _, viewport in { Vector2.new(640, 360), Vector2.new(568, 320), Vector2.new(1280, 720) } do
				camera.ViewportSize = viewport
				h:step(1 / 60, 2)
				expectFits(h, loading, viewport, `redimensionné {viewport.X}x{viewport.Y}`)
			end
			-- retour au PC : placement d'origine
			local r = rects(h, loading)
			expect(r.fail.y).toBeNear(0.68 * 720, EPS)
			expect(p.fail.FailScale.Scale).toBe(1)
			expect(r.stage.y).toBeNear(stageY0, EPS)
			expect(#h.errors).toBe(0)
		end)
	end)

	describe("Fix r5-partage-2 › Chargement : PC et téléviseur inchangés", function()
		it("PC 1280 × 720 et 1920 × 1080 : haut du bloc à 68 %, échelle 1, scène centrée", function()
			for _, viewport in { Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
				local h, loading = run({ viewport = viewport })
				h:step(1, 21)
				local r, p = expectFits(h, loading, viewport, `PC {viewport.X}x{viewport.Y}`)
				expect(p.fail.FailScale.Scale).toBe(1)
				expect(r.fail.y).toBeNear(0.68 * viewport.Y, EPS)
				expect(r.stage.y + r.stage.h / 2).toBeNear(viewport.Y / 2, EPS)
			end
		end)

		it("console 1080p et 4K : échelle « 10 pieds » (1,5 ; 3), haut du bloc à 68 %", function()
			for _, case in { { Vector2.new(1920, 1080), 1.5 }, { Vector2.new(3840, 2160), 3 } } do
				local viewport = case[1]
				local h, loading = run({ console = true, viewport = viewport })
				h:step(1, 21)
				local r, p = expectFits(h, loading, viewport, `console {viewport.X}x{viewport.Y}`)
				expect(p.fail.FailScale.Scale).toBe(case[2])
				expect(r.fail.y).toBeNear(0.68 * viewport.Y, EPS)
				expect(r.stage.y + r.stage.h / 2).toBeNear(viewport.Y / 2, EPS)
				expect(p.button:FindFirstChildOfClass("UIScale").Scale).toBe(1)
			end
		end)

		it("API Roblox valide (ApiAudit) : téléphone tourné, manette prise en main", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, loading = run({ touch = true, viewport = Vector2.new(640, 360) })
				h:step(1, 21)
				h.game.Workspace.CurrentCamera.ViewportSize = Vector2.new(360, 640)
				h:step(1 / 60, 2)
				h.game.UserInputService.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Gamepad1)
				h:step(1 / 60, 2)
				expect(#h.errors).toBe(0)
				expect(loading ~= nil).toBe(true)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
