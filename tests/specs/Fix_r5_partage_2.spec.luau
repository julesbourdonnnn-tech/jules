--!nocheck
-- Correctif r5-partage-2 de Comet Conga : écran d'échec du chargement (src/first/Loading.client.luau)
-- sur un téléphone à l'horizontale (repris tel quel ; la gelée neutre remplace le Nebby)
--   * avant : bloc « message » + « Réessayer » posé à 68 % de la hauteur, taille fixe
--     (420 × 150) et non mis à l'échelle hors téléviseur : en 640 × 360, « Réessayer » couvrait
--     y 306,8-370,8 (10,8 px hors de l'écran), en 667 × 375 y 317-381 (6 px hors de l'écran), et le
--     bas touchait la barre d'accueil de l'iPhone (IgnoreGuiInset)
--   * après : sur un écran bas, le bloc rétrécit jusqu'à tenir sous les points de chargement
--     (« Réessayer » ≥ 48 px réels) et se colle en bas avec une marge ; « Réessayer » et son curseur
--     de sélection restent entiers ; la scène remonte si même la taille minimale ne tient pas
--   * PC et téléviseur : placement et échelle inchangés (68 %, échelle 1 ou « 10 pieds »)
-- Géométrie : tests/harness/Layout (UIScale autour de l'ancre, comme Roblox).
-- Note INT-TV, partie Loading (paquet world, étape 0, docs/04 §22.2) : aucun téléphone au lancement
-- (console d'abord). La mise en page « écran bas » est retirée et l'écran suit LA règle télé de tous
-- les écrans (px TV × max(0,5 ; min(L / 1920 ; H / 1080))). Les cas de téléphone deviennent les
-- écrans réels du jeu (consoles 720p / 1080p / 4K, télés 16:10 et 21:9, fenêtres de PC) avec les
-- MÊMES exigences (Réessayer et son curseur entiers, message sous les points, bloc dans la largeur,
-- scène entière) et deux de plus : tout dans la zone sûre TV de 5 %, Réessayer ≥ 80 px TV de haut.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- curseur de sélection de « Réessayer » : débord 4 + trait blanc 6 + liseré sombre 2 (px du bouton)
	local CURSOR = 12
	local SAFE = 0.05 -- zone sûre TV : 5 % de chaque côté (docs/04 §14.1)
	local MIN_RETRY = 48 -- px réels au plus petit écran du jeu (720p : 96 px TV × 0,667 = 64)
	local MIN_RETRY_TV = 80 -- px TV : hauteur minimale d'un bouton (docs/04 §14.1)
	local EPS = 1e-3 -- UDim2 garde des float32

	-- Le vrai script Loading, en français, sur l'écran `viewport` ; ClientReady jamais posé
	local function run(opts)
		local h = Harness.new({
			mode = "client",
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
			blob = loading:FindFirstChild("Blob", true),
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

	-- Écran d'échec affiché : tout tient, rien ne chevauche la gelée ni ses points
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
			-- « Réessayer » et son curseur entiers, dans la zone sûre TV (5 % de chaque côté)
			retryOnScreen = bottom(b) + CURSOR * b.k <= H * (1 - SAFE) + EPS
				and b.y - CURSOR * b.k >= H * SAFE - EPS
				and b.x - CURSOR * b.k >= W * SAFE - EPS
				and b.x + b.w + CURSOR * b.k <= W * (1 - SAFE) + EPS,
			-- bouton télé : ≥ 80 px TV, et assez grand en px réels au plus petit écran
			retryTall = b.h >= MIN_RETRY - EPS and b.h / b.k >= MIN_RETRY_TV - EPS,
			-- bloc (message compris) dans la largeur de la zone sûre
			blockInWidth = r.fail.x >= W * SAFE - EPS and r.fail.x + r.fail.w <= W * (1 - SAFE) + EPS,
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

	describe("Fix r5-partage-2 › Chargement : « Réessayer » entier sur chaque écran du jeu", function()
		it(
			"consoles 720p, 1080p et 4K : « Réessayer » et son curseur entiers, dans la zone sûre",
			function()
				for _, viewport in
					{ Vector2.new(1280, 720), Vector2.new(1920, 1080), Vector2.new(3840, 2160) }
				do
					local h, loading = run({ console = true, viewport = viewport })
					h:step(1, 45)
					local label = `{viewport.X}x{viewport.Y}`
					expectFits(h, loading, viewport, label)
					expect(#h.errors).toBe(0)
				end
			end
		)

		it("télés 16:10 et 21:9, fenêtres de PC, FR et EN : tout tient", function()
			for _, viewport in
				{
					Vector2.new(1920, 1200), -- 16:10
					Vector2.new(2560, 1080), -- 21:9
					Vector2.new(3440, 1440), -- 21:9 1440p
					Vector2.new(1600, 900),
					Vector2.new(1366, 768),
					Vector2.new(1280, 1024), -- 5:4
					Vector2.new(1024, 768),
					Vector2.new(800, 600), -- plus petite fenêtre : plancher d'échelle 0,5
				}
			do
				for _, locale in { "fr-fr", "en-us" } do
					local h, loading = run({ viewport = viewport, locale = locale })
					h:step(1, 45)
					expectFits(h, loading, viewport, `{viewport.X}x{viewport.Y} {locale}`)
					expect(#h.errors).toBe(0)
				end
			end
		end)

		it(
			"animation d'entrée (rebond) : « Réessayer » ne sort jamais de la zone sûre (720p)",
			function()
				local viewport = Vector2.new(1280, 720)
				local h, loading = run({ console = true, viewport = viewport })
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
				expect(worst <= viewport.Y * (1 - SAFE) + EPS).toBe(true)
			end
		)

		it("Mouvement réduit : même placement, sans animation", function()
			local viewport = Vector2.new(1280, 720)
			local h, loading = run({ console = true, viewport = viewport, reducedMotion = true })
			h:step(1, 21)
			expectFits(h, loading, viewport, "réduit")
		end)

		it(
			"résolution changée pendant l'échec (télé, fenêtre de PC) : replacé à chaque fois",
			function()
				local h, loading = run({ viewport = Vector2.new(1920, 1080) })
				h:step(1, 21)
				local camera = h.game.Workspace.CurrentCamera
				local r0, p = rects(h, loading)
				local stageY0 = r0.stage.y
				for _, viewport in
					{ Vector2.new(1280, 720), Vector2.new(3840, 2160), Vector2.new(1920, 1080) }
				do
					camera.ViewportSize = viewport
					h:step(1 / 60, 2)
					expectFits(h, loading, viewport, `redimensionné {viewport.X}x{viewport.Y}`)
				end
				-- retour à 1080p : placement d'origine
				local r = rects(h, loading)
				expect(r.fail.y).toBeNear(0.68 * 1080, EPS)
				expect(p.fail.FailScale.Scale).toBe(1)
				expect(r.stage.y).toBeNear(stageY0, EPS)
				expect(#h.errors).toBe(0)
			end
		)
	end)

	describe("Fix r5-partage-2 › Chargement : PC et téléviseur inchangés", function()
		it(
			"PC 1280 × 720 et 1920 × 1080 : haut du bloc à 68 %, échelle télé (0,667 ; 1), scène centrée",
			function()
				for _, case in { { Vector2.new(1280, 720), 2 / 3 }, { Vector2.new(1920, 1080), 1 } } do
					local viewport = case[1]
					local h, loading = run({ viewport = viewport })
					h:step(1, 21)
					local r, p = expectFits(h, loading, viewport, `PC {viewport.X}x{viewport.Y}`)
					expect(p.fail.FailScale.Scale).toBeNear(case[2], 1e-9)
					expect(r.fail.y).toBeNear(0.68 * viewport.Y, EPS)
					expect(r.stage.y + r.stage.h / 2).toBeNear(viewport.Y / 2, EPS)
				end
			end
		)

		it("console 1080p et 4K : échelle télé (1 ; 2), haut du bloc à 68 %", function()
			for _, case in { { Vector2.new(1920, 1080), 1 }, { Vector2.new(3840, 2160), 2 } } do
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

		it("API Roblox valide (ApiAudit) : fenêtre redimensionnée, manette prise en main", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, loading = run({ viewport = Vector2.new(1280, 720) })
				h:step(1, 21)
				h.game.Workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
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
