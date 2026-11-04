--!nocheck
-- Review_B1 (lot B1, étape 3 : relecture indépendante ; docs/04 §27.12 B1-15 à B1-23) : chaque cas
-- est un défaut trouvé à la relecture de B1, écrit AVANT sa correction (il échouait sur 519ac44).
--   1. UI/Text supposait que TextService:GetTextSize honore la taille de texte du joueur
--      (PreferredTextSize) : jamais mesuré. S'il ne l'honore pas, toute mesure était divisée par le
--      facteur sans raison : au réglage Largest, les textes "fit" (bannières, cartes de côté,
--      tampons, messages, puce MENU) et la borne des mots grandissaient de 50 % et débordaient. Le
--      facteur de TextService est maintenant MESURÉ (même texte témoin), les deux moteurs sont joués ;
--   2. une phrase ("sentence") est agrandie par le moteur : ses mots tenus ensemble (« {_} ») et
--      ses étoiles dessinées (« {*} ») étaient placés à la taille de Medium (lignes trop longues au
--      pire cas, que le moteur recoupait n'importe où ; étoile trop petite et mal placée) ;
--   3. Widgets.holdOn : Entrée maintenait le bouton SURVOLÉ même caché (fenêtre fermée sous la
--      souris, puis Entrée tenue dans le jeu : achat ou vente invisible) ; un maintien remplacé
--      gardait ses connexions (le clic démarrait encore l'ANCIEN onComplete) ; un maintien continuait
--      quand le contenu changeait sous le focus (FocusId, guard) ; le relâchement d'un maintien fini
--      était encore un clic (son Error d'un bouton que l'achat venait de griser) ;
--   4. Format.confetti : au-delà de 99 999, le GDD §4.2 dit « puis avec BigNumber.abbreviate » ;
--      le formateur écrivait « 100 K » (espace ordinaire sécable en français, quand BigNumber écrit
--      « 100K », A1-18) et restait bloqué à « 999 K » de 1 000 000 à 1e9 (borne du schéma) : un
--      nombre FAUX montré au joueur ;
--   5. panneau TextProbe : si le moteur rend les TextBounds en pixels de l'écran, la télé 4K aurait
--      affiché « ×2,00 » à Medium (l'échelle de l'écran, pas le réglage du joueur) ;
--   6. « 1{_}sur {odds} » collé en français, « 1 in {odds} » pas en anglais (« · 1 » / « in … ») ;
--   7. un « fit » à mots tenus ensemble prenait la taille des lignes coupées à la taille précédente
--      (texte deux fois trop petit, ou ligne plus large que la boîte que le moteur recoupait).
-- Zéro trace : aucune erreur ni avertissement.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local TvAudit = require("../harness/TvAudit")
local TextMetrics = require("../harness/TextMetrics")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

local MEDIUM = Enum.PreferredTextSize.Medium
local LARGEST = Enum.PreferredTextSize.Largest
local WORST = TextMetrics.preferredTextSize.Largest

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function reset()
		MockInstance.textEngine.factor = 1
		MockInstance.textEngine.constraint = "respected"
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- TextService du harnais (0,5 × taille par octet, une ligne) ; `honours` : le moteur simulé
	-- agrandit aussi ses mesures du facteur du joueur (hypothèse de 519ac44, jamais mesurée)
	local function textService(honours: boolean)
		local cm = MockInstance.classMethods.TextService
		local base = cm.GetTextSize
		if honours then
			cm.GetTextSize = function(self, text, size, font, frame)
				local f = MockInstance.textEngine.factor or 1
				local wrap = if typeof(frame) == "Vector2" and frame.X < 1e4
					then Vector2.new(frame.X / f, frame.Y)
					else frame
				return base(self, text, size, font, wrap) * f
			end
		end
		return base
	end

	local function setPreferred(h, Text, factor, mode)
		MockInstance.textEngine.factor = factor
		MockInstance.textEngine.constraint = mode
		h.game.GuiService.PreferredTextSize = if factor > 1 then LARGEST else MEDIUM
		h:settle(1)
		Text.remeasure()
	end

	local function sandbox(honours: boolean)
		reset()
		local h = TvAudit.client()
		local measureAt = textService(honours)
		local Text = TvAudit.mod(h, "UI.Text")
		local gui = h.globals.Instance.new("ScreenGui")
		gui.Name = "ReviewSandbox"
		gui.Parent = h.localPlayer.PlayerGui
		local function make(name, w, hh)
			local l = h.globals.Instance.new("TextLabel")
			l.Name = name
			l.Size = UDim2.fromOffset(w, hh)
			l.AbsoluteSize = Vector2.new(w, hh)
			l.Parent = gui
			return l
		end
		-- largeur à l'écran d'un texte dessiné à `size` px (mesure de Medium du harnais)
		local function width(text, size)
			return measureAt(nil, text, size, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5)).X
		end
		return h, Text, make, width
	end

	local function lines(text)
		local out = {}
		for l in string.gmatch(text .. "\n", "([^\n]*)\n") do
			table.insert(out, l)
		end
		return out
	end

	describe("Review_B1 › 1. facteur de TextService mesuré, jamais supposé", function()
		for _, honours in { false, true } do
			for _, mode in { "respected", "ignored" } do
				local tag = (if honours then "TextService agrandit" else "TextService n'agrandit pas")
					.. ", contrainte « "
					.. mode
					.. " »"
				it(tag .. " : un « fit » garde sa taille au pire cas et tient dans sa boîte", function()
					local h, Text, make, width = sandbox(honours)
					-- 60 caractères dans 952 px : 31 px à Medium (réduit, comme l'ancien TextScaled)
					local text = string.rep("Wilhelmina", 6)
					local fit = make("Banner", 952, 60)
					Text.style(fit, "fit", 48, { min = 28, wrapped = false })
					Text.raw(fit, text)
					local medium = Text.displaySize(fit)
					expect(medium).toBe(31)
					setPreferred(h, Text, WORST, mode)
					expect(Text.displaySize(fit)).toBe(medium)
					-- à l'écran (taille rendue par le moteur simulé) : dans la boîte
					local shown = MockInstance.renderedTextSize(fit)
					expect(math.abs(shown - medium) <= 1).toBe(true)
					expect(width(text, math.floor(shown)) <= 952 + 0.5).toBe(true)
					setPreferred(h, Text, 1, mode)
					expect(Text.displaySize(fit)).toBe(medium)
					reset()
					clean(h)
				end)

				it(tag .. " : borne du mot le plus long inchangée au pire cas (aucun mot coupé)", function()
					local h, Text, make, width = sandbox(honours)
					local label = make("Rail", 140, 60)
					Text.style(label, "label", 40, { words = true, min = 28 })
					Text.raw(label, "Squishydex")
					local medium = Text.displaySize(label)
					expect(medium).toBe(28)
					setPreferred(h, Text, WORST, mode)
					expect(Text.displaySize(label)).toBe(medium)
					local shown = MockInstance.renderedTextSize(label)
					expect(math.abs(shown - medium) <= 1).toBe(true)
					expect(width("Squishydex", math.floor(shown)) <= 140 + 0.5).toBe(true)
					reset()
					clean(h)
				end)
			end
		end

		for _, honours in { false, true } do
			it(
				"réglage Largest dès le démarrage ("
					.. (if honours then "TextService agrandit" else "TextService n'agrandit pas")
					.. ") : mêmes tailles qu'à Medium",
				function()
					local h, Text, make = sandbox(honours)
					setPreferred(h, Text, WORST, "respected")
					local fit = make("Banner", 952, 60)
					Text.style(fit, "fit", 48, { min = 28, wrapped = false })
					Text.raw(fit, string.rep("Wilhelmina", 6))
					local label = make("Rail", 140, 60)
					Text.style(label, "label", 40, { words = true, min = 28 })
					Text.raw(label, "Squishydex")
					expect(Text.displaySize(fit)).toBe(31)
					expect(Text.displaySize(label)).toBe(28)
					setPreferred(h, Text, 1, "respected")
					expect(Text.displaySize(fit)).toBe(31)
					expect(Text.displaySize(label)).toBe(28)
					reset()
					clean(h)
				end
			)
		end

		it("mesures : facteur de TextService lisible (1 s'il n'agrandit pas, f sinon)", function()
			for _, honours in { false, true } do
				local h, Text = sandbox(honours)
				expect(Text.measurements().service).toBe(1)
				setPreferred(h, Text, WORST, "respected")
				expect(Text.measurements().service).toBe(if honours then WORST else 1)
				setPreferred(h, Text, 1, "respected")
				expect(Text.measurements().service).toBe(1)
				reset()
				clean(h)
			end
		end)
	end)

	describe(
		"Review_B1 › 2. phrases agrandies : mots tenus ensemble et étoiles à la taille rendue",
		function()
			for _, honours in { false, true } do
				for _, mode in { "respected", "ignored" } do
					local tag = (if honours then "TextService agrandit" else "TextService n'agrandit pas")
						.. ", contrainte « "
						.. mode
						.. " »"
					it(
						tag .. " : chaque ligne écrite tient au pire cas, « Hold{_}to » jamais coupé",
						function()
							local h, Text, make, width = sandbox(honours)
							local sentence = make("Banner", 600, 140)
							Text.style(sentence, "sentence", 28)
							local raw = "Keep holding the cross to buy ten more levels: Hold{_}to buy now"
							Text.raw(sentence, raw)
							local function check()
								local shown = MockInstance.renderedTextSize(sentence)
								for _, l in lines(sentence.Text) do
									expect(width(l, shown) <= 600 + 0.5).toBe(true)
									expect(string.match(l, "Hold$") == nil).toBe(true)
									expect(string.match(l, "^to ") == nil).toBe(true)
								end
								expect((string.gsub(sentence.Text, "\n", " "))).toBe(
									"Keep holding the cross to buy ten more levels: Hold to buy now"
								)
							end
							check()
							setPreferred(h, Text, WORST, mode)
							expect(MockInstance.renderedTextSize(sentence)).toBe(28 * WORST)
							check()
							setPreferred(h, Text, 1, mode)
							check()
							reset()
							clean(h)
						end
					)

					it(tag .. " : étoile dessinée à la taille rendue de la phrase", function()
						local h, Text, make = sandbox(honours)
						local sentence = make("Reward", 600, 140)
						Text.style(sentence, "sentence", 28)
						Text.raw(sentence, "Bravo 5{*} !")
						local star = Text.icons(sentence)[1]
						expect(star ~= nil).toBe(true)
						expect(math.abs(star.Size.X.Offset - 28 * 0.9) < 1).toBe(true)
						setPreferred(h, Text, WORST, mode)
						local shown = MockInstance.renderedTextSize(sentence)
						expect(shown).toBe(28 * WORST)
						star = Text.icons(sentence)[1]
						expect(math.abs(star.Size.X.Offset - shown * 0.9) < 1).toBe(true)
						-- dessin de l'étoile (traits, disque) à la taille de son cadre, jamais à l'ancienne
						local core = star:FindFirstChild("Fill"):FindFirstChild("Core")
						local side = star.Size.X.Offset
						local cx = core.Position.X.Scale * side + core.Position.X.Offset
						local cw = core.Size.X.Scale * side + core.Size.X.Offset
						expect(math.abs(cx - side / 2) < 1).toBe(true)
						expect(math.abs(cw - side * 0.4) < 1).toBe(true)
						setPreferred(h, Text, 1, mode)
						star = Text.icons(sentence)[1]
						expect(math.abs(star.Size.X.Offset - 28 * 0.9) < 1).toBe(true)
						reset()
						clean(h)
					end)
				end
			end
		end
	)

	describe(
		"Review_B1 › 3. maintiens : jamais sur un bouton caché ni par un maintien remplacé",
		function()
			local function setup()
				local h = TvAudit.client({})
				local c = {
					h = h,
					FG = TvAudit.mod(h, "UI.FocusGuard"),
					Root = TvAudit.mod(h, "UI.Root"),
					Widgets = TvAudit.mod(h, "UI.Panels.Widgets"),
					Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
				}
				TvAudit.toGame(h)
				TvAudit.tick(h, 1)
				return c
			end

			local function run(c, dt)
				local steps = math.max(1, math.floor(dt * 30 + 0.5))
				for _ = 1, steps do
					c.Clock.advance(dt / steps)
					c.h:step(dt / steps, 1)
				end
				c.h:settle(1)
			end

			local function input(keyCode, state, kind)
				return {
					KeyCode = keyCode,
					UserInputType = kind or Enum.UserInputType.Keyboard,
					UserInputState = state,
					Position = Vector3.zero,
					Delta = Vector3.zero,
				}
			end

			local function window(c, name)
				local safe = c.Root.safe("Review_" .. name, 30)
				local root = c.h.globals.Instance.new("Frame")
				root.Name = name
				root.Size = UDim2.fromOffset(900, 500)
				root.Position = UDim2.fromOffset(400, 200)
				root.Parent = safe
				local button = c.Widgets.button({
					parent = root,
					name = "Buy",
					size = UDim2.fromOffset(360, 112),
					position = UDim2.fromOffset(40, 40),
					key = "common.ok",
				})
				local w = {
					name = name,
					root = root,
					blocking = false,
					default = function()
						return button
					end,
					onBack = function()
						return false
					end,
				}
				return w, root, button, safe
			end

			for _, how in { "Visible = false", "ScreenGui coupé", "fenêtre détruite" } do
				it(
					"souris sur le bouton, fenêtre fermée ("
						.. how
						.. "), Entrée tenue 1 s dans le jeu : rien",
					function()
						local c = setup()
						local w, root, button, safe = window(c, "H1")
						local bought = 0
						c.Widgets.holdOn(button, {
							onComplete = function()
								bought += 1
							end,
						})
						c.FG.open(w)
						run(c, 0.5)
						button.MouseEnter:Fire(0, 0)
						-- la fenêtre se ferme sous la souris (○ ou Retour arrière) : MouseLeave ne vient jamais
						c.FG.closeNow(w.name)
						if how == "Visible = false" then
							root.Visible = false
						elseif how == "ScreenGui coupé" then
							safe:FindFirstAncestorOfClass("ScreenGui").Enabled = false
						else
							root:Destroy()
						end
						run(c, 0.5)
						expect(c.h.game.GuiService.SelectedObject).toBe(nil)
						local uis = c.h.game.UserInputService
						uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), false)
						run(c, 1)
						uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), false)
						run(c, 0.1)
						expect(bought).toBe(0)
						clean(c.h)
					end
				)
			end

			it(
				"bouton survolé AFFICHÉ (sans fenêtre, clavier-souris) : Entrée tenue 0,6 s l'achète encore",
				function()
					local c = setup()
					local _, _, button = window(c, "H2")
					local bought = 0
					c.Widgets.holdOn(button, {
						onComplete = function()
							bought += 1
						end,
					})
					run(c, 0.5)
					button.MouseEnter:Fire(0, 0)
					local uis = c.h.game.UserInputService
					uis.InputBegan:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.Begin), false)
					run(c, 0.7)
					uis.InputEnded:Fire(input(Enum.KeyCode.Return, Enum.UserInputState.End), false)
					run(c, 0.1)
					expect(bought).toBe(1)
					clean(c.h)
				end
			)

			it(
				"maintien fini : son relâchement n'est jamais un clic (ni refus après un achat, ni double action)",
				function()
					local c = setup()
					local w, _, button = window(c, "H4")
					local refused, clicked, bought = 0, 0, 0
					local baseRefuse = c.Widgets.refuse
					c.Widgets.refuse = function(...)
						refused += 1
						return baseRefuse(...)
					end
					-- bouton ordinaire qui a AUSSI une action au clic (ligne de l'écran Améliorations : ✕ choisit,
					-- maintien achète) ; l'achat le grise (plus assez de pièces, ou MAX)
					local hold
					button.Activated:Connect(function()
						if c.Widgets.confirmed() and not c.Widgets.isDisabled(button) then
							clicked += 1
						end
					end)
					hold = c.Widgets.holdOn(button, {
						onComplete = function()
							bought += 1
							hold.setEnabled(false)
						end,
					})
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = button
					run(c, 0.5)
					local Gamepad = require("../harness/Gamepad")
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.7)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(bought).toBe(1)
					expect(refused).toBe(0) -- jamais le son Error et la secousse juste après un achat réussi
					-- de nouveau actif : un maintien fini ne déclenche pas non plus l'action du clic
					hold.setEnabled(true)
					run(c, 0.5)
					hold = c.Widgets.holdOn(button, {
						onComplete = function()
							bought += 1
						end,
					})
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.7)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(bought).toBe(2)
					expect(clicked).toBe(0)
					-- un simple appui (sans maintien fini) reste un clic
					run(c, 0.5)
					Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(clicked).toBe(1)
					c.Widgets.refuse = baseRefuse
					c.FG.closeNow(w.name)
					clean(c.h)
				end
			)

			it(
				"élément sous le focus changé PENDANT le maintien (FocusId, garde posée) : rien n'est acheté",
				function()
					local c = setup()
					local w, _, button = window(c, "H5")
					local bought, early = 0, 0
					local hold = c.Widgets.holdOn(button, {
						onComplete = function()
							bought += 1
						end,
						onEarly = function()
							early += 1
						end,
					})
					c.FG.open(w)
					c.h.game.GuiService.SelectedObject = button
					button:SetAttribute("FocusId", "snack")
					run(c, 0.5)
					local Gamepad = require("../harness/Gamepad")
					-- carte 1 du Conseillé recalculée pendant le maintien : autre famille sous le focus
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.3)
					expect(hold.holding()).toBe(true)
					button:SetAttribute("FocusId", "pens")
					run(c, 1)
					expect(hold.holding()).toBe(false)
					expect(bought).toBe(0)
					expect(early).toBe(1) -- l'anneau se vide, la consigne « Maintiens ✕ » peut s'afficher
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.5)
					-- contenu changé par le code (FocusGuard.guard) : même règle
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.3)
					c.FG.guard()
					run(c, 1)
					expect(bought).toBe(0)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.5)
					-- appui suivant, rien de changé : un achat
					Gamepad.press(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.7)
					Gamepad.release(c.h, Enum.KeyCode.ButtonA)
					run(c, 0.1)
					expect(bought).toBe(1)
					c.FG.closeNow(w.name)
					clean(c.h)
				end
			)

			it(
				"maintien remplacé (holdOn deux fois) : le clic ne lance jamais l'ancien onComplete",
				function()
					local c = setup()
					local w, _, button = window(c, "H3")
					local old, new, refused = 0, 0, 0
					c.Widgets.holdOn(button, {
						onComplete = function()
							old += 1
						end,
					})
					-- la ligne passe à MAX : nouveau maintien qui refuse de démarrer
					local hold = c.Widgets.holdOn(button, {
						onComplete = function()
							new += 1
						end,
						canStart = function()
							refused += 1
							return false
						end,
					})
					c.FG.open(w)
					run(c, 0.5)
					local uis = c.h.game.UserInputService
					local mouse = Enum.UserInputType.MouseButton1
					uis.InputBegan:Fire(input(nil, Enum.UserInputState.Begin, mouse), false)
					button.MouseButton1Down:Fire(0, 0)
					run(c, 1)
					uis.InputEnded:Fire(input(nil, Enum.UserInputState.End, mouse), false)
					button.MouseButton1Up:Fire(0, 0)
					run(c, 0.1)
					expect(old).toBe(0)
					expect(new).toBe(0)
					expect(refused).toBe(1)
					expect(hold.holding()).toBe(false)
					-- ✕ tenu (bouton sélectionné) : même règle
					c.h.game.GuiService.SelectedObject = button
					c.h:settle(1)
					uis.InputBegan:Fire(
						input(Enum.KeyCode.ButtonA, Enum.UserInputState.Begin, Enum.UserInputType.Gamepad1),
						true
					)
					run(c, 1)
					uis.InputEnded:Fire(
						input(Enum.KeyCode.ButtonA, Enum.UserInputState.End, Enum.UserInputType.Gamepad1),
						true
					)
					run(c, 0.1)
					expect(old).toBe(0)
					expect(new).toBe(0)
					expect(refused).toBe(2)
					c.FG.closeNow(w.name)
					clean(c.h)
				end
			)
		end
	)

	describe(
		"Review_B1 › 5. panneau TextProbe sur la télé 4K : le facteur du joueur, jamais l'échelle",
		function()
			local function uiScaleOf(inst)
				local s = 1
				local cur = inst
				while cur ~= nil do
					for _, child in cur:GetChildren() do
						if child.ClassName == "UIScale" then
							s *= child.Scale
						end
					end
					cur = cur.Parent
				end
				return s
			end

			for _, screenPx in { false, true } do
				local tag = if screenPx
					then "TextBounds en pixels de l'écran (UIScale compris)"
					else "TextBounds en px TV"
				it(tag .. " : ×1,00 à Medium, ×1,50 au pire cas (libres), ×1,00 (bornés)", function()
					reset()
					local base = MockInstance.renderedTextSize
					if screenPx then
						MockInstance.renderedTextSize = function(inst)
							return base(inst) * uiScaleOf(inst)
						end
					end
					local ok, err = pcall(function()
						local h = TvAudit.client({ viewport = Vector2.new(3840, 2160) })
						local Text = TvAudit.mod(h, "UI.Text")
						local Root = TvAudit.mod(h, "UI.Root")
						local PC = TvAudit.mod(h, "UI.PanelController")
						expect(Root.scale()).toBe(2)
						h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
						h:settle(1)
						PC.open("Diagnostics", "probe")
						h:settle(2)
						local page = h.localPlayer.PlayerGui:FindFirstChild("Page_probe", true)
						expect(page ~= nil).toBe(true)
						local function factors()
							local out = {}
							for _, d in page:GetDescendants() do
								if d:GetAttribute("TextProbe") == true then
									local cell = d.Parent
									out[cell.Name] = cell:FindFirstChild("Factor").Text
								end
							end
							return out
						end
						Text.remeasure()
						h:settle(1)
						for name, text in factors() do
							expect(name .. " " .. text).toBe(name .. " ×1.00")
						end
						setPreferred(h, Text, WORST, "respected")
						h:settle(1)
						for name, text in factors() do
							local want = if string.sub(name, 1, 5) == "Bound" then "×1.00" else "×1.50"
							expect(name .. " " .. text).toBe(name .. " " .. want)
						end
						setPreferred(h, Text, 1, "respected")
						PC.closeAll()
						reset()
						clean(h)
					end)
					MockInstance.renderedTextSize = base
					reset()
					if not ok then
						error(err, 0)
					end
				end)
			end
		end
	)

	describe(
		"Review_B1 › 7. texte « fit » à mots tenus ensemble : sa taille, pas celle des lignes d'avant",
		function()
			-- vraie mesure des polices (TextFit, retours à la ligne compris), comme l'outil d'écrans
			local Screens = require("../harness/Screens")
			for _, case in
				{
					{ "FLOP ! LE PLUS RARE · 1{_}sur 1,00M", "FLOP ! LE PLUS RARE · 1 sur 1,00M" },
					{ "SECRET Prickle Puff · 1{_}in 1.00B", "SECRET Prickle Puff · 1 in 1.00B" },
				}
			do
				it(
					"« "
						.. case[1]
						.. " » : même taille qu'avec des espaces ordinaires, lignes dans la boîte",
					function()
						reset()
						local h = TvAudit.client()
						Screens.realTextService()
						local Text = TvAudit.mod(h, "UI.Text")
						local gui = h.globals.Instance.new("ScreenGui")
						gui.Parent = h.localPlayer.PlayerGui
						local function stamp(name)
							local l = h.globals.Instance.new("TextLabel")
							l.Name = name
							l.Size = UDim2.fromOffset(680, 150)
							l.AbsoluteSize = Vector2.new(680, 150)
							l.FontFace = roblox.Font.fromEnum(Enum.Font.FredokaOne)
							l.Parent = gui
							-- tampon des effets (VFXController.stamp) : sorte "fit", 96 px au plus, 28 au moins
							Text.style(l, "fit", 96, { min = 28, wrapped = true })
							return l
						end
						local glued = stamp("Glued")
						Text.raw(glued, case[1])
						local plain = stamp("Plain")
						Text.raw(plain, case[2])
						local want = Text.displaySize(plain)
						expect(want > 40).toBe(true)
						-- l'ancien calcul mesurait les lignes coupées à 96 px (4 lignes) : 37 px au lieu de ~60
						expect(math.abs(Text.displaySize(glued) - want) <= 1).toBe(true)
						local size = Text.displaySize(glued)
						local TextService = h.game.TextService
						local n = 0
						for line in string.gmatch(glued.Text .. "\n", "([^\n]*)\n") do
							n += 1
							local w = TextService:GetTextSize(
								line,
								size,
								Enum.Font.FredokaOne,
								Vector2.new(1e5, 1e5)
							).X
							expect(w <= 680 + 0.5).toBe(true)
						end
						expect(n * size <= 150 + 0.5).toBe(true)
						clean(h)
					end
				)
			end
		end
	)

	describe("Review_B1 › 6. « 1 sur N » / « 1 in N » tenus ensemble dans les deux langues", function()
		it(
			"chaque clé où « 1 » précède sa cote est collée par le repère {_}, en EN comme en FR",
			function()
				local h = TvAudit.client()
				local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
				local bad = {}
				for _, lang in { "en", "fr" } do
					local word = if lang == "en" then "in" else "sur"
					for key, text in Strings[lang] do
						-- « 1 in {odds} » sans repère : le moteur peut couper « · 1 » / « in 1.00B »
						if
							type(text) == "string" and string.find(text, "1 " .. word .. " {odds}", 1, true)
						then
							table.insert(bad, lang .. " " .. key .. " : « " .. text .. " »")
						end
					end
				end
				table.sort(bad)
				expect(table.concat(bad, "\n")).toBe("")
				clean(h)
			end
		)
	end)

	describe(
		"Review_B1 › 4. Confettis : entier brut jusqu'à 99 999, puis BigNumber (GDD §4.2)",
		function()
			it("même texte que BigNumber.abbreviate au-delà de 99 999, jamais un nombre faux", function()
				local h = TvAudit.client()
				local Format = TvAudit.mod(h, "UI.Format")
				local BigNumber = h:require("ReplicatedStorage.Shared.Logic.BigNumber")
				for _, lang in { "en", "fr" } do
					for _, n in { 100000, 123456.7, 999999, 1000000, 1500000, 45678901, 999999999, 1e9 } do
						expect(Format.confetti(n, lang)).toBe(BigNumber.abbreviate(math.floor(n), lang))
					end
				end
				expect(Format.confetti(100000, "fr")).toBe("100K")
				expect(Format.confetti(1500000, "fr")).toBe("1,50M")
				expect(Format.confetti(1500000, "en")).toBe("1.50M")
				-- borne du schéma (confetti de 0 à 1e9) : au-delà, valeur hostile, le plafond
				expect(Format.confetti(1e12, "en")).toBe("1.00B")
				expect(Format.confetti(math.huge, "en")).toBe("1.00B")
				-- 10 000 tirages (graine fixe) de 100 000 à 1e9 : texte identique à BigNumber, EN et FR
				local seed = 20261103
				local function nextInt(lo, hi)
					seed = (seed * 1103515245 + 12345) % 2147483648
					return lo + seed % (hi - lo + 1)
				end
				local mismatch = {}
				for i = 1, 10000 do
					local exp = nextInt(5, 8)
					local n = nextInt(10 ^ exp, math.min(10 ^ (exp + 1) - 1, 1e9))
					local lang = if i % 2 == 0 then "fr" else "en"
					if Format.confetti(n, lang) ~= BigNumber.abbreviate(n, lang) and #mismatch < 5 then
						table.insert(mismatch, lang .. " " .. n .. " : " .. Format.confetti(n, lang))
					end
				end
				expect(table.concat(mismatch, "\n")).toBe("")
				-- jusqu'à 99 999 : inchangé (entier brut groupé)
				expect(Format.confetti(99999, "fr")).toBe("99 999")
				expect(Format.confetti(99999, "en")).toBe("99,999")
				clean(h)
			end)
		end
	)
end
