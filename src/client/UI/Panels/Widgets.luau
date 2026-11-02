--!strict
-- Widgets (paquet client-panels, module d'aide de src/client/UI/Panels) : briques communes du menu,
-- des panneaux et de l'écran de retour, toutes en px TV (référence 1920 × 1080, mises à l'échelle
-- par l'UIScale de UI/Root) :
--   * textes : TextScaled + UITextSizeConstraint (minimum 28 px TV, Config/Layout.Text.Min),
--     FredokaOne, AutoLocalize coupé (le jeu traduit lui-même par Prefs.t) ; les textes posés par
--     clé (Widgets.setText) sont retraduits tout seuls quand la langue change ;
--   * boutons : sélectionnables, curseur commun (Root.selectionImage), Juice.press, son Click,
--     refus (secousse, contour rouge 0,25 s, son Error, vibration refuse : GDD §9.2, §10.5) ;
--   * interrupteur 120 × 64, barre d'onglets (soulignement qui glisse en 0,15 s), bouton à maintenir
--     (✕ à la manette, clic maintenu à la souris, Entrée au clavier ; progression sur l'horloge du jeu,
--     jamais sur la fin d'une animation ; annulé dès que la sélection part) ;
--   * liste virtualisée (Widgets.rows) : un réservoir de rangées réutilisées en anneau, la sélection
--     suit l'index, la liste défile pour garder une rangée de marge (GDD §10.6 règle 7) ;
--   * envoi des intentions avec le débit de Config/Intents (anti-rafale côté client ; le serveur
--     revalide tout) et appels protégés vers les modules des autres paquets (Widgets.safe).
-- Une seule connexion Heartbeat pour tout le module (maintiens et boutons qui attirent l'attention).

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Layout = require(Shared.Config.Layout)
local Intents = require(Shared.Config.Intents)
local Species = require(Shared.Config.Species)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local BigNumber = require(Shared.Logic.BigNumber)
local Clock = require(Shared.Util.Clock)
local Net = require(Shared.Net)
local Localization = require(Shared.Localization)

local Client = script.Parent.Parent.Parent
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)
local Prefs = require(Client.Util.Prefs)
local Haptics = require(Client.Util.Haptics)
local AudioController = require(Client.Controllers.AudioController)
local State = require(Client.Controllers.StateController)
local FocusGuard = require(Client.UI.FocusGuard)

local Widgets = {}

-- Couleurs de la charte des panneaux (GDD §10.1 : contour bleu nuit 3 px, dégradés pastel)
Widgets.Colors = {
	Stroke = Color3.fromRGB(30, 25, 60),
	Panel = Theme.Colors.Panel,
	PanelLight = Theme.Colors.PanelLight,
	Card = Color3.fromRGB(58, 50, 96),
	CardLight = Color3.fromRGB(80, 70, 130),
	Text = Theme.Colors.Text,
	TextDim = Theme.Colors.TextDim,
	Accent = Theme.Colors.Primary,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Danger = Theme.Colors.Danger,
	Gold = Theme.Colors.Gold,
	Pink = Color3.fromRGB(255, 130, 180),
	Locked = Color3.fromRGB(90, 86, 110),
	Silhouette = Color3.fromRGB(70, 68, 84),
}

Widgets.Text = Layout.Text
Widgets.MIN_TEXT = Layout.Text.Min
Widgets.CORNER = UDim.new(0, Layout.Corner.Min)
Widgets.CORNER_LARGE = UDim.new(0, Layout.Corner.Max)

-- Priorité des liaisons des fenêtres (ContextActionService) : au-dessus des contrôles du jeu
Widgets.BIND_PRIORITY = Enum.ContextActionPriority.High.Value + 100

-- =============================================================================================
-- Textes et nombres
-- =============================================================================================

-- Textes posés par clé : retraduits quand la langue change (clés faibles : un texte détruit part seul)
local bound: { [TextLabel | TextButton]: { key: string, vars: { [string]: any }? } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
local languageHooked = false
Widgets.LanguageChanged = Prefs.LanguageChanged

local function hookLanguage()
	if languageHooked then
		return
	end
	languageHooked = true
	Prefs.LanguageChanged:Connect(function()
		for label, b in bound do
			if label.Parent ~= nil then
				label.Text = Prefs.t(b.key, b.vars)
			end
		end
	end)
end

function Widgets.t(key: string, vars: { [string]: any }?): string
	return Prefs.t(key, vars)
end

-- Nombre du jeu dans la langue du joueur (règles du GDD §4.2 : Logic/BigNumber seulement)
function Widgets.num(n: number?): string
	local v = if type(n) == "number" and n == n then n else 0
	return BigNumber.abbreviate(v, Prefs.language())
end

-- Texte traduit posé par clé (retraduit au changement de langue)
function Widgets.setText(label: TextLabel | TextButton, key: string, vars: { [string]: any }?)
	hookLanguage()
	bound[label] = { key = key, vars = vars }
	local text = Prefs.t(key, vars)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Texte brut (nom propre, nombre déjà formaté) : plus de retraduction automatique
function Widgets.setRaw(label: TextLabel | TextButton, text: string)
	bound[label] = nil
	if label.Text ~= text then
		label.Text = text
	end
end

-- Texte coupé à maxBytes octets sur une frontière de caractère UTF-8 (jamais un caractère coupé en
-- deux, qui s'afficherait en carré) ; un texte déjà invalide devient vide
function Widgets.clip(text: string, maxBytes: number): string
	if type(text) ~= "string" then
		return ""
	end
	local out = if #text > maxBytes then string.sub(text, 1, maxBytes) else text
	while #out > 0 and utf8.len(out) == nil do
		out = string.sub(out, 1, #out - 1)
	end
	return out
end

-- Nom d'une espèce (EN = FR, GDD §15) ; « ??? » pour une espèce inconnue
function Widgets.speciesName(species: number?): string
	local def = if type(species) == "number" then Species.ById[species] else nil
	if def == nil then
		return Prefs.t("panel.dex.unknown")
	end
	return Prefs.t("species." .. def.key)
end

function Widgets.rarityOf(species: number?): number
	local def = if type(species) == "number" then Species.ById[species] else nil
	return if def then def.rarity else Rarities.COMMON
end

function Widgets.rarityColor(rarity: number?): Color3
	local def = if type(rarity) == "number" then Rarities.List[rarity] else nil
	return if def then def.color else Widgets.Colors.Card
end

function Widgets.mutationKey(mutation: number?): string
	local def = if type(mutation) == "number" then Mutations.ById[mutation] else nil
	return if def then "mutation." .. def.key else "mutation.none"
end

-- =============================================================================================
-- Appels protégés vers les autres paquets
-- =============================================================================================

local reported: { [string]: boolean } = {}

-- Appelle fn sous pcall ; un stub du contrat (« TODO(… ) ») rend simplement le repli. Une autre
-- erreur (un vrai bug) est relancée une fois par clé dans un fil à part : ScriptContext.Error la voit
-- (ErrorReporter → Diagnostics en ligne ; h.errors dans les specs, règle zéro trace), et l'interface
-- continue avec le repli : jamais un plantage de l'UI, jamais une erreur avalée en silence.
function Widgets.safe<T>(where: string, fallback: T, fn: (...any) -> T, ...: any): T
	if type(fn) ~= "function" then
		return fallback
	end
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	local text = tostring(result)
	if not string.find(text, "TODO(", 1, true) and not reported[where] then
		reported[where] = true
		Widgets.raise(where, text)
	end
	return fallback
end

-- Relance une erreur attrapée dans un fil à part (visible par ScriptContext.Error, sans interrompre
-- l'appelant)
function Widgets.raise(where: string, text: string)
	task.spawn(error, "[panels] " .. where .. " : " .. text, 0)
end

-- =============================================================================================
-- Intentions (débit de Config/Intents, côté client)
-- =============================================================================================

local buckets: { [string]: { tokens: number, at: number } } = {}

-- Vrai si l'intention `name` peut partir maintenant (seau à jetons au débit client de Config/Intents)
local function allow(name: string): boolean
	local spec = Intents[name]
	if spec == nil then
		return false
	end
	local rate = spec.clientRate or spec.rate
	local calls, per = rate[1], rate[2]
	local now = Clock.now()
	local b = buckets[name]
	if b == nil then
		b = { tokens = calls, at = now }
		buckets[name] = b
	end
	local elapsed = math.max(0, now - b.at)
	b.tokens = math.min(calls, b.tokens + elapsed * calls / per)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Envoie une intention (jamais une valeur de jeu) ; faux si le débit client la retient ou si le
-- remote est indisponible
function Widgets.send(name: string, ...: any): boolean
	if not allow(name) then
		return false
	end
	local args = table.pack(...)
	local ok = pcall(function()
		Net.event(name):FireServer(table.unpack(args, 1, args.n))
	end)
	return ok
end

-- Remise à zéro des seaux (specs)
function Widgets._resetBuckets()
	table.clear(buckets)
end

-- Achat Robux (pass ou produit) : invite de Roblox sous pcall ; la sélection est tenue pendant la
-- fenêtre de Roblox (FocusGuard.hold, 60 s au plus) et rendue à sa fermeture. Faux si l'article est
-- désactivé (id ≤ 0) ou si l'invite échoue.
local purchaseHooked = false
function Widgets.promptPurchase(kind: "pass" | "product", id: number): boolean
	if type(id) ~= "number" or id <= 0 then
		return false
	end
	local player = Players.LocalPlayer
	if player == nil then
		return false
	end
	if not purchaseHooked then
		purchaseHooked = true
		pcall(function()
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
				FocusGuard.release()
			end)
			MarketplaceService.PromptProductPurchaseFinished:Connect(function()
				FocusGuard.release()
			end)
		end)
	end
	FocusGuard.hold(Layout.Focus.HoldMax)
	local ok = pcall(function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then
		FocusGuard.release()
	end
	return ok
end

-- UiSeen(écran) une fois par session (Config/Intents.UiSeen.set). Un écran n'est « vu » qu'une fois
-- l'intention partie : retenue par le débit du client (panneaux ouverts d'affilée par L2 / R2), elle
-- attend et repart dès que le seau le permet (boucle Heartbeat du module) ; UiSeen("objectives") est
-- l'étape 10 de l'accueil, jamais perdue pour la session.
local seen: { [string]: boolean } = {}
local seenPending: { [string]: boolean } = {}
local ensureLoops: () -> () -- défini plus bas (boucle Heartbeat du module)

local function trySeen(screen: string): boolean
	if not allow("UiSeen") then
		return false
	end
	seenPending[screen] = nil
	seen[screen] = true
	pcall(function()
		Net.event("UiSeen"):FireServer(screen)
	end)
	return true
end

local function flushSeen()
	for screen in seenPending do
		if not trySeen(screen) then
			return
		end
	end
end

function Widgets.seen(screen: string)
	if type(screen) ~= "string" or seen[screen] or seenPending[screen] then
		return
	end
	if not trySeen(screen) then
		seenPending[screen] = true
		ensureLoops()
	end
end

-- =============================================================================================
-- Construction
-- =============================================================================================

export type LabelProps = {
	parent: Instance?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	key: string?,
	vars: { [string]: any }?,
	text: string?,
	textSize: number?, -- taille habituelle (MaxTextSize), px TV
	minSize: number?,
	color: Color3?,
	xAlign: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	wrapped: boolean?,
	zIndex: number?,
	order: number?,
	stroke: boolean?,
	background: Color3?,
	backgroundTransparency: number?,
}

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or Widgets.CORNER
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3?, thickness: number?, contextual: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Widgets.Colors.Stroke
	s.Thickness = thickness or Layout.Stroke
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
Widgets.corner = corner
Widgets.stroke = stroke

local function applyLabel(label: TextLabel | TextButton, p: LabelProps)
	label.BackgroundTransparency = p.backgroundTransparency or (if p.background then 0.2 else 1)
	if p.background then
		label.BackgroundColor3 = p.background
	end
	label.BorderSizePixel = 0
	label.Size = p.size or UDim2.fromScale(1, 1)
	label.Position = p.position or UDim2.new()
	label.AnchorPoint = p.anchor or Vector2.zero
	label.FontFace = Theme.Fonts.Title
	label.TextColor3 = p.color or Widgets.Colors.Text
	label.TextScaled = true
	label.TextWrapped = p.wrapped == true
	label.TextXAlignment = p.xAlign or Enum.TextXAlignment.Center
	label.TextYAlignment = p.yAlign or Enum.TextYAlignment.Center
	label.AutoLocalize = false
	label.ZIndex = p.zIndex or 2
	label.LayoutOrder = p.order or 0
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = p.minSize or Widgets.MIN_TEXT
	c.MaxTextSize = math.max(p.textSize or Layout.Text.Body, c.MinTextSize)
	c.Parent = label
	if p.stroke then
		local s = stroke(label, Widgets.Colors.Stroke, 2, true)
		s.Name = "TextStroke"
	end
	if p.key then
		Widgets.setText(label, p.key, p.vars)
	else
		label.Text = p.text or ""
	end
end

-- Texte lisible (≥ 28 px TV)
function Widgets.label(p: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = p.name or "Label"
	applyLabel(label, p)
	if p.parent then
		label.Parent = p.parent
	end
	return label
end

export type FrameProps = {
	parent: Instance?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	transparency: number?,
	corner: UDim?,
	stroke: boolean?,
	gradient: boolean?,
	zIndex: number?,
	order: number?,
	clips: boolean?,
}

-- Cadre arrondi (UICorner, contour 3 px, dégradé pastel léger)
function Widgets.frame(p: FrameProps): Frame
	local f = Instance.new("Frame")
	f.Name = p.name or "Frame"
	f.Size = p.size or UDim2.fromScale(1, 1)
	f.Position = p.position or UDim2.new()
	f.AnchorPoint = p.anchor or Vector2.zero
	f.BackgroundColor3 = p.color or Widgets.Colors.Card
	f.BackgroundTransparency = p.transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = p.zIndex or 1
	f.LayoutOrder = p.order or 0
	f.ClipsDescendants = p.clips == true
	if p.corner ~= nil or p.stroke ~= false then
		corner(f, p.corner)
	end
	if p.stroke ~= false then
		stroke(f)
	end
	if p.gradient then
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new(0, 0.12)
		g.Parent = f
	end
	if p.parent then
		f.Parent = p.parent
	end
	return f
end

-- Cadre transparent sans décor
function Widgets.group(parent: Instance?, name: string, size: UDim2?, position: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = size or UDim2.fromScale(1, 1)
	f.Position = position or UDim2.new()
	if parent then
		f.Parent = parent
	end
	return f
end

-- =============================================================================================
-- Boutons
-- =============================================================================================

export type ButtonProps = {
	parent: Instance?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	key: string?,
	vars: { [string]: any }?,
	text: string?,
	textSize: number?,
	color: Color3?,
	textColor: Color3?,
	zIndex: number?,
	order: number?,
	selectable: boolean?,
	nav: boolean?, -- ouvre un autre écran (parcours du robot TvAudit)
	tab: boolean?, -- bouton d'onglet (parcours du robot TvAudit)
	onActivate: (() -> ())?,
	sound: string?, -- son de validation (défaut "Click" ; "" : aucun)
}

local disabledState: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local refuseHandlers: { [GuiButton]: () -> () } = setmetatable({}, { __mode = "k" }) :: any
local refuseToken: { [UIStroke]: number } = setmetatable({}, { __mode = "k" }) :: any
local refuseColor: { [UIStroke]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

-- Refus d'un bouton de menu (GDD §9.2) : secousse ±6 px × 3, contour rouge 0,25 s, son Error,
-- vibration refuse. Rien n'est envoyé au serveur.
function Widgets.refuse(gui: GuiObject?)
	AudioController.play("Error")
	Haptics.play("refuse")
	if gui == nil or gui.Parent == nil then
		return
	end
	Juice.shake(gui)
	-- un seul UIStroke par objet compte dans Roblox : le contour existant passe au rouge 0,25 s
	local border: UIStroke? = nil
	for _, child in gui:GetChildren() do
		if child:IsA("UIStroke") and child.Name ~= "TextStroke" then
			border = child
			break
		end
	end
	if border == nil then
		border = stroke(gui)
	end
	local s = border :: UIStroke
	if refuseToken[s] == nil then
		refuseColor[s] = s.Color
	end
	local token = (refuseToken[s] or 0) + 1
	refuseToken[s] = token
	s.Color = Widgets.Colors.Danger
	task.delay(0.25, function()
		if refuseToken[s] == token then
			refuseToken[s] = nil
			if s.Parent ~= nil then
				s.Color = refuseColor[s] or Widgets.Colors.Stroke
			end
		end
	end)
end

-- Bouton grisé : ✕ le refuse (Widgets.refuse) au lieu de l'activer ; il reste sélectionnable
function Widgets.setDisabled(button: GuiButton, disabled: boolean, onRefuse: (() -> ())?)
	disabledState[button] = disabled
	refuseHandlers[button] = onRefuse :: any
	local label = button:FindFirstChild("Label")
	local alpha = if disabled then 0.45 else 0
	if label and (label:IsA("TextLabel")) then
		label.TextTransparency = alpha
	end
	button.BackgroundTransparency = if disabled then 0.35 else 0
end

function Widgets.isDisabled(button: GuiButton): boolean
	return disabledState[button] == true
end

-- Réaction d'un bouton (GDD §9.2) : appui 1 → 0,92 en 0,06 s (Quad Out) ; relâchement 0,92 → 1,05 →
-- 1 en 0,18 s (Back Out) ; le bouton sélectionné grossit à 1,05 (curseur commun de UI/Root autour).
-- 1,05 et non 1,06 : avec 24 px entre deux boutons de 432 px, un bouton sélectionné ne touche
-- jamais son voisin. Mouvement réduit : aucune mise à l'échelle.
local SELECT_GROW = Layout.Focus.Grow -- 1,05
local selectedButtons: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local pressedButtons: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any
-- boutons qui pulsent (Widgets.attention) : leur UIScale est piloté par la boucle d'attention
local attention: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function rest(button: GuiButton): number
	return if selectedButtons[button] then SELECT_GROW else 1
end

local function pressFx(button: GuiButton)
	local scale = Juice.scaleOf(button)
	button.MouseButton1Down:Connect(function()
		pressedButtons[button] = true
		if not Juice.reducedMotion() then
			Juice.tween(scale, 0.06, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)
	local function release()
		pressedButtons[button] = nil
		if Juice.reducedMotion() then
			scale.Scale = 1
			return
		end
		Juice.tween(scale, 0.18, { Scale = rest(button) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.SelectionGained:Connect(function()
		selectedButtons[button] = true
		if not Juice.reducedMotion() then
			Juice.tween(scale, 0.12, { Scale = SELECT_GROW })
		end
	end)
	button.SelectionLost:Connect(function()
		selectedButtons[button] = nil
		if attention[button] then
			return -- la pulsation d'attention reprend la main dès l'image suivante
		end
		if Juice.reducedMotion() then
			scale.Scale = 1
		else
			Juice.tween(scale, 0.12, { Scale = 1 })
		end
	end)
end

-- Petit rebond de validation (✕ à la manette : 0,92 puis retour, Back Out)
local function activateFx(button: GuiButton)
	if Juice.reducedMotion() then
		return
	end
	local scale = Juice.scaleOf(button)
	local down = Juice.tween(scale, 0.06, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	down.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			Juice.tween(
				scale,
				0.18,
				{ Scale = rest(button) },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end
	end)
end

-- Bouton (TextButton vide + texte enfant « Label ») ; ✕ ou clic → onActivate (son Click)
function Widgets.button(p: ButtonProps): TextButton
	local b = Instance.new("TextButton")
	b.Name = p.name or "Button"
	b.Text = ""
	b.AutoButtonColor = false
	b.AutoLocalize = false
	b.Size = p.size or UDim2.fromOffset(320, Layout.Button.MinHeight)
	b.Position = p.position or UDim2.new()
	b.AnchorPoint = p.anchor or Vector2.zero
	b.BackgroundColor3 = p.color or Widgets.Colors.CardLight
	b.BorderSizePixel = 0
	b.ZIndex = p.zIndex or 3
	b.LayoutOrder = p.order or 0
	b.Selectable = p.selectable ~= false
	b.SelectionImageObject = Root.selectionImage()
	corner(b)
	stroke(b)
	if p.nav then
		b:SetAttribute("TvNav", true)
	end
	if p.tab then
		b:SetAttribute("TvTab", true)
	end
	if p.key ~= nil or p.text ~= nil then
		Widgets.label({
			parent = b,
			name = "Label",
			size = UDim2.new(1, -24, 1, -12),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			key = p.key,
			vars = p.vars,
			text = p.text,
			textSize = p.textSize or Layout.Text.Button,
			color = p.textColor,
			zIndex = b.ZIndex + 1,
		})
	end
	pressFx(b)
	b.Activated:Connect(function()
		if disabledState[b] then
			Widgets.refuse(b)
			local onRefuse = refuseHandlers[b]
			if onRefuse then
				onRefuse()
			end
			return
		end
		local sound = p.sound or "Click"
		if sound ~= "" then
			AudioController.play(sound)
		end
		activateFx(b)
		if p.onActivate then
			p.onActivate()
		end
	end)
	if p.parent then
		b.Parent = p.parent
	end
	return b
end

-- Texte d'un bouton créé par Widgets.button
function Widgets.buttonLabel(button: GuiButton): TextLabel?
	local label = button:FindFirstChild("Label")
	return if label and label:IsA("TextLabel") then label else nil
end

-- Glyphe d'une touche (PlayStation sur PlayStation, Xbox sur Xbox, texte au clavier ; UI/Glyph)
function Widgets.glyph(
	parent: Instance,
	gamepad: Enum.KeyCode,
	keyboard: Enum.KeyCode?,
	size: number?,
	position: UDim2?,
	anchor: Vector2?
): any
	return Glyph.new(parent, { gamepad = gamepad, keyboard = keyboard }, {
		size = size or Layout.Glyph.Min,
		position = position,
		anchor = anchor,
		zIndex = 6,
	})
end

-- Le libellé d'un bouton suit la largeur RÉELLE de son glyphe : une touche longue du clavier
-- (« Enter », « Shift ») élargit la pastille (UI/Glyph) et ne recouvre jamais le texte. `left` : marge
-- avant le glyphe, `gap` : espace glyphe → texte, `right` : marge à droite du texte (px TV)
function Widgets.followGlyph(label: GuiObject, glyph: GuiObject, left: number, gap: number, right: number)
	local function place()
		local w = glyph.Size.X.Offset
		local x = left + w + gap
		label.Position = UDim2.new(0, x, label.Position.Y.Scale, label.Position.Y.Offset)
		label.Size = UDim2.new(1, -(x + right), label.Size.Y.Scale, label.Size.Y.Offset)
	end
	place()
	glyph:GetPropertyChangedSignal("Size"):Connect(place)
end

-- Petit squishy dessiné en formes (aucune image téléversée) : corps rond aux couleurs de l'espèce,
-- ventre clair, deux yeux ; gris pour une silhouette inconnue
function Widgets.blob(parent: Instance, name: string?): Frame
	local body = Instance.new("Frame")
	body.Name = name or "Blob"
	body.BackgroundColor3 = Widgets.Colors.Silhouette
	body.BorderSizePixel = 0
	body.Size = UDim2.fromOffset(96, 84)
	body.ZIndex = 3
	corner(body, UDim.new(0.5, 0))
	local belly = Instance.new("Frame")
	belly.Name = "Belly"
	belly.BackgroundColor3 = Color3.new(1, 1, 1)
	belly.BackgroundTransparency = 0.55
	belly.BorderSizePixel = 0
	belly.AnchorPoint = Vector2.new(0.5, 1)
	belly.Position = UDim2.fromScale(0.5, 0.95)
	belly.Size = UDim2.fromScale(0.6, 0.42)
	belly.ZIndex = 4
	corner(belly, UDim.new(0.5, 0))
	belly.Parent = body
	for i, x in { 0.34, 0.66 } do
		local eye = Instance.new("Frame")
		eye.Name = "Eye" .. i
		eye.BackgroundColor3 = Color3.fromRGB(30, 25, 40)
		eye.BorderSizePixel = 0
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.13, 0.17)
		eye.ZIndex = 5
		corner(eye, UDim.new(0.5, 0))
		eye.Parent = body
	end
	body.Parent = parent
	return body
end

-- Couleurs d'un squishy dessiné (silhouette grise si inconnu)
function Widgets.paintBlob(blob: Frame, species: number?, known: boolean)
	local def = if type(species) == "number" then Species.ById[species] else nil
	local main = if def and known then def.colors.main else Widgets.Colors.Silhouette
	blob.BackgroundColor3 = main
	local belly = blob:FindFirstChild("Belly")
	if belly and belly:IsA("Frame") then
		belly.BackgroundColor3 = if def and known then def.colors.second else Widgets.Colors.Silhouette
		belly.BackgroundTransparency = if known then 0.15 else 0.6
	end
	for _, name in { "Eye1", "Eye2" } do
		local eye = blob:FindFirstChild(name)
		if eye and eye:IsA("Frame") then
			eye.Visible = known
		end
	end
end

-- =============================================================================================
-- Interrupteur (GDD §10.3 : 120 × 64 px TV)
-- =============================================================================================

export type Toggle = {
	button: TextButton,
	set: (value: boolean) -> (),
	get: () -> boolean,
}

function Widgets.toggle(
	parent: Instance,
	name: string,
	position: UDim2?,
	anchor: Vector2?,
	onToggle: (boolean) -> ()
): Toggle
	local size = Layout.Panel.toggle
	local value = false
	local b = Widgets.button({
		parent = parent,
		name = name,
		size = UDim2.fromOffset(size.w, size.h),
		position = position,
		anchor = anchor,
		color = Widgets.Colors.Locked,
		sound = "Click",
	})
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(size.h - 16, size.h - 16)
	knob.Position = UDim2.new(0, 8, 0.5, 0)
	knob.ZIndex = b.ZIndex + 1
	corner(knob, UDim.new(0.5, 0))
	knob.Parent = b
	local function render(animate: boolean)
		local goal = if value then UDim2.new(1, -(size.h - 8), 0.5, 0) else UDim2.new(0, 8, 0.5, 0)
		b.BackgroundColor3 = if value then Widgets.Colors.Success else Widgets.Colors.Locked
		if animate and not Juice.reducedMotion() then
			Juice.tween(knob, 0.15, { Position = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else
			knob.Position = goal
		end
		b:SetAttribute("On", value)
	end
	b.Activated:Connect(function()
		if disabledState[b] then
			return
		end
		value = not value
		render(true)
		onToggle(value)
	end)
	render(false)
	return {
		button = b,
		set = function(v: boolean)
			if v ~= value then
				value = v
				render(false)
			end
		end,
		get = function(): boolean
			return value
		end,
	}
end

-- =============================================================================================
-- Barre d'onglets (72 px de haut, libellés de 32 px ; soulignement qui glisse en 0,15 s)
-- =============================================================================================

export type TabSpec = { id: string, key: string }
export type TabBar = {
	frame: Frame,
	buttons: { [string]: TextButton },
	order: { string },
	setActive: (id: string) -> (),
	setVisible: (id: string, visible: boolean) -> (),
	first: () -> TextButton?,
	active: () -> string,
}

-- Largeur estimée d'un texte en em (FredokaOne, par classe de caractère : étroits « i l t r . , »,
-- larges « m w M W », capitales, chiffres, autres minuscules ; hors ASCII un peu plus large). Même
-- approximation que l'audit des specs (tests/harness/Gamepad) : sert à donner à chaque onglet la
-- largeur de son libellé le plus long (anglais ou français) à 28 px TV au moins.
local NARROW = "iljtfrI!.,:;'|()[]"
local WIDE = "mwMW@%"
function Widgets.textEm(text: string): number
	local em = 0
	local ok = pcall(function()
		for _, code in utf8.codes(text) do
			if code > 127 then
				em += 0.6
			else
				local ch = string.char(code)
				if ch == " " then
					em += 0.28
				elseif string.find(NARROW, ch, 1, true) then
					em += 0.3
				elseif string.find(WIDE, ch, 1, true) then
					em += 0.78
				elseif ch >= "A" and ch <= "Z" then
					em += 0.64
				elseif ch >= "0" and ch <= "9" then
					em += 0.56
				else
					em += 0.52
				end
			end
		end
	end)
	return if ok then em else #text * 0.6
end

-- Plus grande largeur du libellé d'une clé dans les deux langues (em)
function Widgets.keyEm(key: string): number
	return math.max(Widgets.textEm(Localization.get("en", key)), Widgets.textEm(Localization.get("fr", key)))
end

function Widgets.tabBar(parent: Instance, tabs: { TabSpec }, onSelect: (id: string) -> ()): TabBar
	local height = Layout.Panel.tabHeight
	local glyph = Layout.Glyph.Min
	local frame = Widgets.group(parent, "Tabs", UDim2.new(1, -48, 0, height + 8), UDim2.fromOffset(24, 4))
	local strip =
		Widgets.group(frame, "Strip", UDim2.new(1, -2 * (glyph + 16), 1, 0), UDim2.fromOffset(glyph + 16, 0))
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, Layout.Spacing.Min)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = strip
	-- L1 / R1 (raccourcis, en boucle) aux deux bouts
	Widgets.glyph(frame, Enum.KeyCode.ButtonL1, nil, glyph, UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5))
	Widgets.glyph(frame, Enum.KeyCode.ButtonR1, nil, glyph, UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))
	local buttons: { [string]: TextButton } = {}
	local order: { string } = {}
	local visibleIds: { [string]: boolean } = {}
	local current = ""
	local count = #tabs
	-- largeur de chaque onglet : son libellé le plus long à 32 px, ramenée dans la place disponible
	-- (jamais sous 28 px TV) ; marge intérieure de 24 px
	local available = 1440 - 48 - 2 * (glyph + 16) - (count - 1) * Layout.Spacing.Min
	local wants: { number } = {}
	local total = 0
	for i, spec in tabs do
		wants[i] = Widgets.keyEm(spec.key)
		total += wants[i] * Layout.Panel.tabText + 32
	end
	local shrink = if total > available then available / total else 1
	for i, spec in tabs do
		local width = math.floor(math.min(320, (wants[i] * Layout.Panel.tabText + 32) * shrink))
		table.insert(order, spec.id)
		visibleIds[spec.id] = true
		local b = Widgets.button({
			parent = strip,
			name = "Tab_" .. spec.id,
			size = UDim2.fromOffset(width, height),
			key = spec.key,
			textSize = Layout.Panel.tabText,
			color = Widgets.Colors.Card,
			order = i,
			tab = true,
			sound = "Tab",
			onActivate = function()
				onSelect(spec.id)
			end,
		})
		local underline = Instance.new("Frame")
		underline.Name = "Underline"
		underline.BackgroundColor3 = Widgets.Colors.Accent
		underline.BorderSizePixel = 0
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, -4)
		underline.Size = UDim2.new(0, 0, 0, 6)
		underline.ZIndex = b.ZIndex + 2
		corner(underline, UDim.new(0.5, 0))
		underline.Parent = b
		buttons[spec.id] = b
	end
	local bar: TabBar
	bar = {
		frame = frame,
		buttons = buttons,
		order = order,
		setActive = function(id: string)
			current = id
			for tabId, b in buttons do
				local active = tabId == id
				b.BackgroundColor3 = if active then Widgets.Colors.Accent else Widgets.Colors.Card
				b:SetAttribute("Active", active)
				local underline = b:FindFirstChild("Underline")
				if underline and underline:IsA("Frame") then
					local goal = if active then UDim2.new(0.7, 0, 0, 6) else UDim2.new(0, 0, 0, 6)
					if Juice.reducedMotion() then
						underline.Size = goal
					else
						Juice.tween(underline, 0.15, { Size = goal })
					end
				end
			end
		end,
		setVisible = function(id: string, visible: boolean)
			local b = buttons[id]
			if b then
				b.Visible = visible
				visibleIds[id] = visible
			end
		end,
		first = function(): TextButton?
			for _, id in order do
				if visibleIds[id] then
					return buttons[id]
				end
			end
			return nil
		end,
		active = function(): string
			return current
		end,
	}
	return bar
end

-- =============================================================================================
-- Bouton à maintenir (✕ maintenu, clic maintenu, Entrée maintenue) : progression sur Clock.now()
-- =============================================================================================

export type Hold = {
	button: TextButton,
	fill: Frame,
	duration: number,
	holding: () -> boolean,
	cancel: () -> (),
	setEnabled: (enabled: boolean) -> (),
}

type HoldState = {
	hold: Hold,
	startedAt: number?,
	enabled: boolean,
	onComplete: () -> (),
	canStart: (() -> boolean)?,
}

local holds: { [TextButton]: HoldState } = setmetatable({}, { __mode = "k" }) :: any
local activeHold: HoldState? = nil

local function stopHold(state: HoldState)
	state.startedAt = nil
	if activeHold == state then
		activeHold = nil
	end
	local fill = state.hold.fill
	if fill.Parent ~= nil then
		fill.Size = UDim2.fromScale(0, 1)
	end
end

local function beginHold(state: HoldState)
	if not state.enabled or state.startedAt ~= nil then
		return
	end
	-- bouton grisé : Activated joue le refus (un seul refus, jamais deux sons Error)
	if disabledState[state.hold.button] then
		return
	end
	if state.canStart and not state.canStart() then
		Widgets.refuse(state.hold.button)
		return
	end
	if activeHold and activeHold ~= state then
		stopHold(activeHold)
	end
	state.startedAt = Clock.now()
	activeHold = state
	Haptics.play("holdStart")
end

local function stepHolds()
	local state = activeHold
	if state == nil then
		return
	end
	local started = state.startedAt
	local button = state.hold.button
	if started == nil or button.Parent == nil then
		stopHold(state)
		return
	end
	local elapsed = Clock.now() - started
	local duration = state.hold.duration
	if elapsed < 0 or elapsed > duration + 60 then
		-- horloge recalée ou maintien orphelin (fin d'appui perdue) : sortie sûre, sans action
		stopHold(state)
		return
	end
	local alpha = math.clamp(elapsed / duration, 0, 1)
	state.hold.fill.Size = UDim2.fromScale(alpha, 1)
	if elapsed >= duration then
		stopHold(state)
		Haptics.play("holdDone")
		AudioController.play("Click")
		state.onComplete()
	end
end

-- Boutons qui attirent l'attention (pulsation 1 → 1,08, sinus de 0,8 s ; GDD §9.2). La pulsation
-- passe par le MÊME UIScale que l'appui et la sélection (Juice.scaleOf : « JuiceScale ») : Roblox
-- n'applique qu'un UIScale par objet. Elle s'arrête tant que le bouton est sélectionné (il grossit à
-- 1,05) ou enfoncé (0,92).
local attentionTime = 0

local function stepAttention(dt: number)
	attentionTime = (attentionTime + dt) % 0.8
	local reduced = Juice.reducedMotion()
	local s = if reduced then 1 else 1 + 0.04 * (1 - math.cos(2 * math.pi * attentionTime / 0.8))
	for gui in attention do
		if
			gui.Parent ~= nil
			and gui.Visible
			and GuiService.SelectedObject ~= gui
			and not pressedButtons[gui :: any]
		then
			local scale = gui:FindFirstChild("JuiceScale")
			if scale and scale:IsA("UIScale") then
				scale.Scale = s
			end
		end
	end
end

local heartbeat: RBXScriptConnection? = nil
local inputHooked = false

ensureLoops = function()
	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(function(dt: number)
			stepHolds()
			stepAttention(dt)
			if next(seenPending) ~= nil then
				flushSeen()
			end
		end)
	end
	if not inputHooked then
		inputHooked = true
		-- ✕ (ou Entrée) maintenu sur le bouton sélectionné ; relâché : annulé s'il n'est pas fini
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode ~= Enum.KeyCode.ButtonA and input.KeyCode ~= Enum.KeyCode.Return then
				return
			end
			local selected = GuiService.SelectedObject
			local state = if selected and selected:IsA("TextButton") then holds[selected] else nil
			if state then
				beginHold(state)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				input.KeyCode == Enum.KeyCode.ButtonA
				or input.KeyCode == Enum.KeyCode.Return
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				local state = activeHold
				if state then
					stopHold(state)
				end
			end
		end)
		pcall(function()
			UserInputService.WindowFocusReleased:Connect(function()
				local state = activeHold
				if state then
					stopHold(state)
				end
			end)
		end)
	end
end

-- Pulsation d'attention (boutons « Réclamer », Grand Splorch prêt) ; respecte Mouvement réduit
function Widgets.attention(gui: GuiObject, on: boolean)
	ensureLoops()
	if on then
		Juice.scaleOf(gui)
		attention[gui] = true
	elseif attention[gui] then
		attention[gui] = nil
		if GuiService.SelectedObject ~= gui and not pressedButtons[gui :: any] then
			local scale = gui:FindFirstChild("JuiceScale")
			if scale and scale:IsA("UIScale") then
				scale.Scale = 1
			end
		end
	end
end

export type HoldProps = {
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	key: string,
	vars: { [string]: any }?,
	duration: number,
	color: Color3?,
	textSize: number?,
	onComplete: () -> (),
	canStart: (() -> boolean)?, -- faux : refus (son Error, vibration refuse), aucun maintien
}

function Widgets.hold(p: HoldProps): Hold
	ensureLoops()
	local b = Widgets.button({
		parent = p.parent,
		name = p.name,
		size = p.size,
		position = p.position,
		anchor = p.anchor,
		color = p.color or Widgets.Colors.Pink,
		sound = "",
	})
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = b.ZIndex + 1
	corner(fill)
	fill.Parent = b
	local glyphSize = Layout.Glyph.Min
	local g = Widgets.glyph(
		b,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.Return,
		glyphSize,
		UDim2.new(0, 16, 0.5, 0),
		Vector2.new(0, 0.5)
	)
	g.frame.ZIndex = b.ZIndex + 3
	local holdLabel = Widgets.label({
		parent = b,
		name = "Label",
		size = UDim2.new(1, -(glyphSize + 48), 1, -12),
		position = UDim2.new(0, glyphSize + 32, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		key = p.key,
		vars = p.vars,
		textSize = p.textSize or Layout.Text.Button,
		zIndex = b.ZIndex + 2,
	})
	Widgets.followGlyph(holdLabel, g.frame, 16, 16, 16)
	local hold: Hold
	local state: HoldState
	hold = {
		button = b,
		fill = fill,
		duration = p.duration,
		holding = function(): boolean
			return state.startedAt ~= nil
		end,
		cancel = function()
			stopHold(state)
		end,
		setEnabled = function(enabled: boolean)
			state.enabled = enabled
			Widgets.setDisabled(b, not enabled)
			if not enabled then
				stopHold(state)
			end
		end,
	}
	state = { hold = hold, enabled = true, onComplete = p.onComplete, canStart = p.canStart }
	holds[b] = state
	-- souris : clic maintenu sur le bouton
	b.MouseButton1Down:Connect(function()
		beginHold(state)
	end)
	b.MouseLeave:Connect(function()
		stopHold(state)
	end)
	-- la sélection part (croix, fenêtre fermée) : maintien annulé
	b.SelectionLost:Connect(function()
		stopHold(state)
	end)
	return hold
end

-- Annule le maintien en cours (fenêtre fermée)
function Widgets.cancelHolds()
	local state = activeHold
	if state then
		stopHold(state)
	end
end

-- =============================================================================================
-- Liste virtualisée (rangées réutilisées en anneau, la sélection suit l'index)
-- =============================================================================================

export type RowsProps = {
	parent: Instance,
	name: string,
	size: Vector2, -- px TV de la fenêtre visible
	position: UDim2?,
	rowHeight: number,
	gap: number,
	visibleRows: number?, -- défaut : hauteur / (rangée + écart)
	makeRow: (frame: Frame, slot: number) -> any,
	bindRow: (row: any, frame: Frame, index: number) -> (),
	selectables: (row: any) -> { GuiObject },
}

export type Rows = {
	frame: Frame,
	holder: Frame,
	count: () -> number,
	setCount: (n: number) -> (),
	refresh: () -> (),
	ensureVisible: (index: number) -> (),
	scrollRow: () -> number,
	firstSelectable: () -> GuiObject?,
	selectableAt: (index: number, column: number?) -> GuiObject?,
	indexOf: (obj: GuiObject) -> number?,
	page: (dir: number) -> (),
}

-- Place du curseur de sélection autour des cases (px TV) : le cadre de la liste coupe ce qui dépasse
-- (ClipsDescendants), et le curseur de UI/Root déborde de 4 px + trait de 6 px + liseré de 2 px,
-- plus le grossissement 1,05 de la case sélectionnée (≈ 10 px sur une case de 208, autour de son
-- ancrage en haut à gauche). Le cadre est donc plus large de ROW_ROOM de chaque côté, et la 1re et la
-- dernière rangée gardent ROW_ROOM au-dessus et au-dessous d'elles.
local ROW_ROOM = Layout.Spacing.Normal -- 24

function Widgets.rows(p: RowsProps): Rows
	local stride = p.rowHeight + p.gap
	local visible = p.visibleRows or (p.size.Y + p.gap) / stride
	local room = ROW_ROOM / stride -- en rangées
	local poolSize = math.ceil(visible) + 2
	local frame = Widgets.group(
		p.parent,
		p.name,
		UDim2.fromOffset(p.size.X + 2 * ROW_ROOM, p.size.Y),
		(p.position or UDim2.new()) - UDim2.fromOffset(ROW_ROOM, 0)
	)
	frame.ClipsDescendants = true
	local holder =
		Widgets.group(frame, "Holder", UDim2.fromOffset(p.size.X, p.size.Y), UDim2.fromOffset(ROW_ROOM, 0))
	holder:SetAttribute("BumpTarget", true)
	holder:SetAttribute("RestPosition", holder.Position)
	local slots: { { frame: Frame, row: any, index: number, cells: { GuiObject } } } = {}
	local n = 0
	local scroll = 0 -- rangées défilées (peut être fractionnaire : demi-rangée visible)
	local rows: Rows

	local function maxScroll(): number
		if n <= 0 then
			return 0
		end
		return math.max(0, n - visible + 2 * room)
	end

	local function placeAll()
		local first = math.clamp(math.floor(scroll) + 1 - 1, 1, math.max(1, n - poolSize + 1))
		local used: { [number]: boolean } = {}
		for i = first, math.min(n, first + poolSize - 1) do
			local slotIndex = ((i - 1) % poolSize) + 1
			local slot = slots[slotIndex]
			used[slotIndex] = true
			if slot.index ~= i then
				slot.index = i
				p.bindRow(slot.row, slot.frame, i)
				for column, cell in slot.cells do
					cell:SetAttribute("RowIndex", i)
					cell:SetAttribute("Column", column)
				end
			end
			slot.frame.Position = UDim2.fromOffset(0, (i - 1) * stride + ROW_ROOM)
			slot.frame.Visible = true
		end
		for slotIndex, slot in slots do
			if not used[slotIndex] then
				slot.frame.Visible = false
				slot.index = 0
			end
		end
	end

	local function applyScroll(animate: boolean)
		local goal = UDim2.fromOffset(ROW_ROOM, -scroll * stride)
		-- position de repos lue par le rebond de bout de liste (Widgets.bump)
		holder:SetAttribute("RestPosition", goal)
		if animate and not Juice.reducedMotion() then
			Juice.tween(holder, 0.15, { Position = goal })
		else
			holder.Position = goal
		end
		placeAll()
	end

	for s = 1, poolSize do
		local rowFrame =
			Widgets.group(holder, "Row" .. s, UDim2.fromOffset(p.size.X, p.rowHeight), UDim2.new())
		rowFrame.Visible = false
		local row = p.makeRow(rowFrame, s)
		local cells = p.selectables(row)
		local entry = { frame = rowFrame, row = row, index = 0, cells = cells }
		slots[s] = entry
		for _, cell in cells do
			cell.SelectionGained:Connect(function()
				local idx = cell:GetAttribute("RowIndex")
				if type(idx) == "number" and idx >= 1 then
					rows.ensureVisible(idx)
				end
			end)
		end
	end

	rows = {
		frame = frame,
		holder = holder,
		count = function(): number
			return n
		end,
		setCount = function(count: number)
			n = math.max(0, math.floor(count))
			scroll = math.clamp(scroll, 0, maxScroll())
			for _, slot in slots do
				slot.index = 0 -- tout est relié de nouveau (données changées)
			end
			applyScroll(false)
		end,
		refresh = function()
			for _, slot in slots do
				slot.index = 0
			end
			placeAll()
		end,
		ensureVisible = function(index: number)
			-- une rangée de marge au-dessus et en dessous (en rangées depuis le haut du contenu, qui
			-- commence ROW_ROOM plus bas)
			local top = (index - 1) - 1 + room
			local bottom = index + 1 + room
			local target = scroll
			if target > top then
				target = top
			end
			if target + visible < bottom then
				target = bottom - visible
			end
			target = math.clamp(target, 0, maxScroll())
			if math.abs(target - scroll) > 1e-6 then
				scroll = target
				applyScroll(true)
			end
		end,
		scrollRow = function(): number
			return scroll
		end,
		firstSelectable = function(): GuiObject?
			return rows.selectableAt(1, 1)
		end,
		selectableAt = function(index: number, column: number?): GuiObject?
			if index < 1 or index > n then
				return nil
			end
			rows.ensureVisible(index)
			placeAll()
			local slot = slots[((index - 1) % poolSize) + 1]
			if slot.index ~= index then
				return nil
			end
			local want = column or 1
			local best: GuiObject? = nil
			for c, cell in slot.cells do
				if cell.Visible and cell.Selectable then
					if c == want then
						return cell
					end
					if best == nil or c < want then
						best = cell
					end
				end
			end
			return best
		end,
		indexOf = function(obj: GuiObject): number?
			local idx = obj:GetAttribute("RowIndex")
			return if type(idx) == "number" and idx >= 1 then idx else nil
		end,
		page = function(dir: number)
			local selected = GuiService.SelectedObject
			local idx = if selected then rows.indexOf(selected) else nil
			local column = if selected then selected:GetAttribute("Column") else nil
			local step = math.max(1, math.floor(visible))
			if idx == nil or not selected or not selected:IsDescendantOf(frame) then
				scroll = math.clamp(scroll + dir * step, 0, maxScroll())
				applyScroll(true)
				return
			end
			local target = math.clamp(idx + dir * step, 1, n)
			local cell = rows.selectableAt(target, if type(column) == "number" then column else 1)
			if cell then
				GuiService.SelectedObject = cell
			end
		end,
	}
	return rows
end

-- =============================================================================================
-- Rebond de bout de liste (8 px en 0,15 s, GDD §9.2)
-- =============================================================================================

local bumping: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

function Widgets.bump(from: GuiObject?, direction: string)
	if from == nil or Juice.reducedMotion() then
		return
	end
	local target: GuiObject = from
	local cur: Instance? = from.Parent
	while cur ~= nil and cur:IsA("GuiObject") do
		if cur:GetAttribute("BumpTarget") == true then
			target = cur
			break
		end
		cur = cur.Parent
	end
	-- position de repos : celle que vise le défilement en cours (liste virtualisée, rail qui glisse),
	-- jamais une position intermédiaire de tween (la liste resterait décalée après le rebond)
	local restAttr = target:GetAttribute("RestPosition")
	local origin = if typeof(restAttr) == "UDim2" then restAttr else (bumping[target] or target.Position)
	bumping[target] = origin
	local dx = if direction == "Left" then -8 elseif direction == "Right" then 8 else 0
	local dy = if direction == "Up" then -8 elseif direction == "Down" then 8 else 0
	local out = Juice.tween(target, 0.07, { Position = origin + UDim2.fromOffset(dx, dy) })
	out.Completed:Once(function()
		local back = Juice.tween(target, 0.08, { Position = origin })
		back.Completed:Once(function()
			if bumping[target] == origin then
				bumping[target] = nil
			end
		end)
	end)
end

-- Bout de liste (GDD §9.2, §10.5) : son Bump, vibration listEnd, rebond de 8 px en 0,15 s
function Widgets.listEnd(from: GuiObject?, direction: string)
	AudioController.play("Bump")
	Haptics.play("listEnd")
	Widgets.bump(from, direction)
end

-- Premier objet sélectionnable visible sous root (ordre stable : GetDescendants)
function Widgets.firstSelectable(root: Instance): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and Widgets.shown(d) then
			return d
		end
	end
	return nil
end

-- Objet affiché : lui et ses ancêtres visibles jusqu'à un ScreenGui activé
function Widgets.shown(obj: Instance?): boolean
	local cur = obj
	while cur ~= nil do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			return cur.Enabled
		end
		cur = cur.Parent
	end
	return false
end

-- Échelle d'interface courante (px réels par px TV)
function Widgets.scale(): number
	return Root.scale()
end

-- Hauteur utile de Root.safe (px TV) : écran moins la barre de Roblox (GuiService:GetGuiInset, que
-- ScreenInsets = CoreUISafeInsets retire du ScreenGui) et les deux marges de la zone sûre. 972 en
-- théorie ; ≈ 885 en 1280 × 720 avec la barre de 58 px réels : panneaux et rail s'y ajustent.
function Widgets.safeHeight(): number
	local camera = workspace.CurrentCamera
	local viewport = if camera
		then camera.ViewportSize
		else Vector2.new(Layout.Reference.X, Layout.Reference.Y)
	local inset = 0
	pcall(function()
		local topLeft = GuiService:GetGuiInset()
		inset = topLeft.Y
	end)
	local s = Root.scale()
	local pad = Root.padding()
	if s <= 0 or viewport.Y <= 1 then
		return Layout.Safe.h
	end
	return math.max(0, (viewport.Y - inset) / s - 2 * pad.Y)
end

-- =============================================================================================
-- Profil répliqué (StateController, lecture seule)
-- =============================================================================================

function Widgets.state(key: string): any
	return State.get(key)
end

-- Table du profil sur les clés demandées (formules partagées : Logic/Formulas, QuestRules…)
function Widgets.profile(keys: { string }): { [string]: any }
	local out = {}
	for _, key in keys do
		out[key] = State.get(key)
	end
	return out
end

-- fn() une fois par vague de changements des clés (regroupés par task.defer)
function Widgets.watch(keys: { string }, fn: () -> ())
	local wanted: { [string]: boolean } = {}
	for _, key in keys do
		wanted[key] = true
	end
	local pending = false
	State.Changed:Connect(function(key: string)
		if not wanted[key] or pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			fn()
			-- liste rechargée, bouton caché (fête qui commence, squishy vendu) : la sélection perdue est
			-- rendue tout de suite, sans compter un sauvetage (FocusGuard.refocus)
			FocusGuard.refocus()
		end)
	end)
end

-- Table du profil : valeur si c'est une table, sinon une table vide (charges abîmées tolérées)
function Widgets.tbl(value: any): { [any]: any }
	return if type(value) == "table" then value else {}
end

-- Nombre fini, sinon le repli
function Widgets.n(value: any, fallback: number?): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return fallback or 0
end

return Widgets
