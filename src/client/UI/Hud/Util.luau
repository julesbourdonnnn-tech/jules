--!strict
-- Outils communs du paquet client-hud (dossier d'aide src/client/UI/Hud, docs/04 §2) :
--   * appels protégés vers les modules des autres paquets (un stub « TODO (…) » du contrat rend le
--     repli sans bruit ; une vraie erreur est relancée une fois par appelant dans un fil à part, pour
--     que ScriptContext.Error la voie : jamais une erreur avalée, jamais une interface plantée) ;
--   * intentions envoyées au débit CLIENT de Config/Intents (seau à jetons, horloge Clock) ;
--   * lecture sûre des charges utiles (nombres finis, chaînes bornées, tables) ;
--   * textes : clés de Strings vérifiées avant traduction (une clé inconnue venue du réseau ne fait
--     jamais d'avertissement), variables mises en forme (nombres par Logic/BigNumber, espèces,
--     mutations, alias d'un nom caché) ;
--   * placement des rectangles de Config/Layout dans Root.safe (ancrage à un bord de la zone sûre) ;
--   * projection d'un point du monde à l'écran (calcul pur, sans dépendre du moteur).
-- Ne dépend que du socle et de Shared : utilisable par tous les modules du paquet, à tout rang.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)
local Intents = require(Shared.Config.Intents)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Strings = require(Shared.Localization.Strings)
local BigNumber = require(Shared.Logic.BigNumber)
local Hash = require(Shared.Logic.Hash)

local Client = script.Parent.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Glyph = require(Client.UI.Glyph)

local Util = {}

-- Marque d'une erreur de stub du contrat (« TODO » suivi du paquet entre parenthèses). Tous les paquets
-- sont livrés : la marque ne sert plus qu'au rapport d'intégration (liste vide attendue par Boot et Soak).
local STUB_MARK = "TODO" .. "("

local MAX_NUMBER = 1e300

-- =============================================================================================
-- Appels protégés
-- =============================================================================================

local reported: { [string]: boolean } = {}

-- Relance une erreur attrapée dans un fil à part (ScriptContext.Error la voit ; l'appelant continue)
function Util.raise(where: string, text: string)
	task.spawn(error, "[hud] " .. where .. " : " .. text, 0)
end

-- Appelle fn(...) sous pcall : un stub du contrat rend `fallback` ; une autre erreur est signalée
-- une fois par `where` puis rend aussi `fallback`
function Util.safe<T>(where: string, fallback: T, fn: any, ...: any): T
	if type(fn) ~= "function" then
		return fallback
	end
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	local text = tostring(result)
	if not string.find(text, STUB_MARK, 1, true) and not reported[where] then
		reported[where] = true
		Util.raise(where, text)
	end
	return fallback
end

-- Remise à zéro des erreurs déjà signalées (specs)
function Util._resetReported()
	table.clear(reported)
end

-- =============================================================================================
-- Intentions (débit client de Config/Intents)
-- =============================================================================================

local buckets: { [string]: { tokens: number, at: number } } = {}

-- Vrai si l'intention `name` peut partir maintenant (seau à jetons au débit client)
function Util.allow(name: string): boolean
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
	if now < b.at then
		b.at = now -- horloge revenue en arrière (specs) : jamais de jetons négatifs
	end
	b.tokens = math.min(calls, b.tokens + (now - b.at) * calls / per)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Envoie une intention (jamais une valeur de jeu) ; faux si le débit client la retient ou si le
-- remote est indisponible
function Util.send(name: string, ...: any): boolean
	if not Util.allow(name) then
		return false
	end
	local args = table.pack(...)
	local ok = pcall(function()
		Net.event(name):FireServer(table.unpack(args, 1, args.n))
	end)
	return ok
end

-- Remise à zéro des seaux (specs)
function Util._resetBuckets()
	table.clear(buckets)
end

-- =============================================================================================
-- Lecture sûre
-- =============================================================================================

-- Nombre fini dans [min ; max], sinon `default`
function Util.num(value: any, default: number, min: number?, max: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	local lo = min or -MAX_NUMBER
	local hi = max or MAX_NUMBER
	return math.clamp(value, lo, hi)
end

-- Chaîne UTF-8 valide d'au plus `maxLen` octets, sinon `default`
function Util.str(value: any, default: string, maxLen: number?): string
	if type(value) ~= "string" then
		return default
	end
	local limit = maxLen or 200
	if #value > limit or utf8.len(value) == nil then
		return default
	end
	return value
end

function Util.tbl(value: any): { [any]: any }
	return if type(value) == "table" then value else {}
end

-- =============================================================================================
-- Textes
-- =============================================================================================

-- La clé existe-t-elle (anglais ET français) ? Une clé venue du réseau est vérifiée avant Prefs.t
function Util.has(key: any): boolean
	return type(key) == "string" and Strings.en[key] ~= nil and Strings.fr[key] ~= nil
end

-- Texte traduit d'une clé connue ; `fallback` (déjà traduit) sinon
function Util.t(key: string, vars: { [string]: any }?, fallback: string?): string
	if not Util.has(key) then
		return fallback or ""
	end
	return Prefs.t(key, vars)
end

-- Nombre du jeu dans la langue du joueur (« 1,2 K »)
function Util.big(n: number): string
	return BigNumber.abbreviate(Util.num(n, 0), Prefs.language())
end

-- "m:ss" (ou "h:mm:ss") d'une durée en secondes, jamais négative
function Util.clock(seconds: number): string
	local s = math.max(0, math.ceil(Util.num(seconds, 0, 0, 359999)))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

-- Nom d'une espèce (EN = FR, GDD §15) ; "" pour une espèce inconnue
function Util.speciesName(species: any): string
	local def = if type(species) == "number" then Species.ById[species] else nil
	if def == nil then
		return ""
	end
	return Util.t("species." .. def.key, nil, def.name)
end

-- Nom d'une mutation ("" pour aucune ou inconnue)
function Util.mutationName(mutation: any): string
	local def = if type(mutation) == "number" then Mutations.ById[mutation] else nil
	if def == nil then
		return ""
	end
	return Util.t("mutation." .. def.key, nil, "")
end

-- Nom affiché d'un joueur : son nom, ou l'alias « Squishy Fan #NNNN » s'il est caché ("")
function Util.displayName(userId: any, name: any): string
	local n = Util.str(name, "", 100)
	if n ~= "" then
		return n
	end
	local id = Util.num(userId, 0, 0, 2 ^ 53)
	if id <= 0 then
		return ""
	end
	local ok, alias = pcall(Hash.alias, id)
	return Util.t("name.alias", { n = if ok then alias else 0 })
end

-- Variables d'un texte venu du serveur, mises en forme pour l'affichage : nombres de jeu abrégés,
-- espèce et mutation par leur nom, nom caché remplacé par l'alias, chaînes bornées
local NUMBER_VARS: { [string]: boolean } = {
	coins = true,
	missing = true,
	have = true,
	need = true,
	odds = true,
	points = true,
	target = true,
	size = true,
}
function Util.vars(raw: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(raw) ~= "table" then
		return out
	end
	local count = 0
	for key, value in raw do
		count += 1
		if count > 32 then
			break
		end
		if type(key) == "string" and #key <= 32 then
			if key == "species" then
				out.species = Util.speciesName(value)
			elseif key == "mutation" then
				out.mutation = Util.mutationName(value)
			elseif type(value) == "number" then
				local v = Util.num(value, 0)
				out[key] = if NUMBER_VARS[key] then Util.big(v) else tostring(math.floor(v + 0.5))
			elseif type(value) == "string" then
				out[key] = Util.str(value, "", 120)
			elseif type(value) == "boolean" then
				out[key] = tostring(value)
			end
		end
	end
	if type(raw.name) == "string" or type(raw.userId) == "number" then
		out.name = Util.displayName(raw.userId, raw.name)
	end
	return out
end

-- =============================================================================================
-- Interface
-- =============================================================================================

-- Place un cadre au rectangle d'un élément de Config/Layout.Hud, dans Root.safe : ancré au bord de
-- la zone sûre de son ancrage (x − 96, y − 54 depuis le coin ; colonnes écartées sur écran large)
function Util.place(frame: GuiObject, slot: Layout.HudSlot)
	local r = slot.rect
	local safe = Layout.Safe
	local left = r.x - safe.x
	local top = r.y - safe.y
	local right = (safe.x + safe.w) - (r.x + r.w)
	local bottom = (safe.y + safe.h) - (r.y + r.h)
	local centerX = (r.x + r.w / 2) - (safe.x + safe.w / 2)
	frame.Size = UDim2.fromOffset(r.w, r.h)
	local anchor = slot.anchor
	if anchor == "topLeft" then
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.fromOffset(left, top)
	elseif anchor == "topCenter" then
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, centerX, 0, top)
	elseif anchor == "topRight" or anchor == "right" then
		frame.AnchorPoint = Vector2.new(1, 0)
		frame.Position = UDim2.new(1, -right, 0, top)
	elseif anchor == "bottomCenter" then
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, centerX, 1, -bottom)
	else -- bottomRight
		frame.AnchorPoint = Vector2.new(1, 1)
		frame.Position = UDim2.new(1, -right, 1, -bottom)
	end
end

export type LabelProps = {
	name: string,
	parent: Instance?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	text: string?,
	textSize: number, -- px TV visés (taille maximale du TextScaled)
	color: Color3?,
	font: Font?,
	align: Enum.TextXAlignment?,
	wrapped: boolean?,
	zIndex: number?,
}

-- Texte lisible à 3 m : TextScaled borné par UITextSizeConstraint (minimum Layout.Text.Min = 28 px TV),
-- contour sombre de 3 px (jamais de texte posé sur le décor sans contraste)
function Util.label(p: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = p.name
	label.BackgroundTransparency = 1
	label.Size = p.size or UDim2.fromScale(1, 1)
	label.Position = p.position or UDim2.new()
	label.AnchorPoint = p.anchor or Vector2.zero
	label.Text = p.text or ""
	label.TextColor3 = p.color or Theme.Colors.Text
	label.FontFace = p.font or Theme.Fonts.Title
	label.TextScaled = true
	label.TextWrapped = p.wrapped == true
	label.TextXAlignment = p.align or Enum.TextXAlignment.Center
	label.AutoLocalize = false
	label.ZIndex = p.zIndex or 2
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = Layout.Text.Min
	constraint.MaxTextSize = math.max(Layout.Text.Min, math.floor(p.textSize))
	constraint.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Stroke
	stroke.Thickness = Layout.Stroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	if p.parent then
		label.Parent = p.parent
	end
	return label
end

-- Coins arrondis et contour bleu nuit des pastilles du HUD (GDD §10.1)
function Util.chrome(frame: GuiObject, radius: number?, strokeColor: Color3?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Layout.Corner.Max)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or Color3.fromRGB(30, 25, 60)
	stroke.Thickness = Layout.Stroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

export type ButtonProps = {
	name: string,
	parent: Instance?,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	textSize: number,
	color: Color3?,
	glyph: Glyph.Binding?, -- glyphe de touche à gauche du libellé
	zIndex: number?,
	onActivate: () -> (),
}

local buttonGlyphs: { [Instance]: Glyph.Handle } = setmetatable({}, { __mode = "k" }) :: any

-- Bouton de fenêtre (cartes) : sélectionnable à la manette (cadre de sélection commun de UI/Root),
-- retour d'appui du GDD §9.2 (0,92 à l'appui, 1,05 puis 1 au relâchement, 1,05 sélectionné ; un seul
-- UIScale « JuiceScale » par objet), libellé ≥ 28 px TV, glyphe facultatif
function Util.button(p: ButtonProps): TextButton
	local b = Instance.new("TextButton")
	b.Name = p.name
	b.Text = ""
	b.AutoButtonColor = false
	b.Selectable = true
	b.Size = p.size
	b.Position = p.position or UDim2.new()
	b.AnchorPoint = p.anchor or Vector2.zero
	b.BackgroundColor3 = p.color or Theme.Colors.PanelLight
	b.ZIndex = p.zIndex or 3
	pcall(function()
		b.SelectionImageObject = Root.selectionImage()
	end)
	Util.chrome(b, Layout.Corner.Min)
	local glyphW = 0
	if p.glyph then
		local size = Layout.Glyph.Min
		buttonGlyphs[b] = Glyph.new(b, p.glyph, {
			name = "Glyph",
			size = size,
			position = UDim2.new(0, 14, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			zIndex = b.ZIndex + 1,
		})
		glyphW = size + 14
	end
	Util.label({
		name = "Label",
		parent = b,
		size = UDim2.new(1, -(glyphW + 24), 1, -12),
		position = UDim2.new(0, glyphW + 12, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		text = p.text,
		textSize = p.textSize,
		zIndex = b.ZIndex + 1,
	})
	local scale = Juice.scaleOf(b)
	local grow = Layout.Focus.Grow
	b.MouseButton1Down:Connect(function()
		Juice.tween(scale, 0.06, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	b.MouseButton1Up:Connect(function()
		Juice.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	b.SelectionGained:Connect(function()
		Juice.tween(scale, 0.12, { Scale = grow }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	b.SelectionLost:Connect(function()
		Juice.tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	b.Activated:Connect(function()
		p.onActivate()
	end)
	if p.parent then
		b.Parent = p.parent
	end
	return b
end

-- Touche du menu à montrer au clavier (Config/Layout.Keyboard.Menu) : celle des deux (KeyCode.M,
-- KeyCode.Semicolon) dont le texte, selon la disposition du joueur, est « M » (AZERTY : Semicolon) ;
-- KeyCode.M par défaut
function Util.menuKey(): Enum.KeyCode
	for _, name in Layout.Keyboard.Menu do
		local ok, key = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and typeof(key) == "EnumItem" then
			local okText, text = pcall(function()
				return UserInputService:GetStringForKeyCode(key)
			end)
			if okText and type(text) == "string" and string.upper(text) == "M" then
				return key :: Enum.KeyCode
			end
		end
	end
	return Enum.KeyCode.M
end

-- Glyphe d'un bouton créé avec `glyph` (nil sinon)
function Util.buttonGlyph(b: Instance): Glyph.Handle?
	return buttonGlyphs[b]
end

-- Libellé d'un bouton (specs)
function Util.buttonLabel(b: GuiObject): TextLabel?
	local label = b:FindFirstChild("Label")
	return if label and label:IsA("TextLabel") then label else nil
end

-- Largeur estimée d'un texte en em (même approximation que l'audit des specs, tests/harness/Gamepad)
local NARROW = "iljtfrI!.,:;'|()[]"
local WIDE = "mwMW@%"
function Util.textEm(text: string): number
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

-- =============================================================================================
-- Monde
-- =============================================================================================

-- Position de la racine du personnage local (nil : pas de personnage, mort ou en réapparition)
function Util.rootPos(): Vector3?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Projection d'un point du monde à l'écran (calcul pur, comme Camera:WorldToViewportPoint) :
-- position en pixels de l'écran, devant la caméra ?, dans l'écran ?
function Util.project(
	cf: CFrame,
	fovDeg: number,
	viewport: Vector2,
	point: Vector3
): (Vector2, boolean, boolean)
	local rel = cf:PointToObjectSpace(point)
	local depth = -rel.Z
	local w = math.max(viewport.X, 1)
	local h = math.max(viewport.Y, 1)
	local tanHalf = math.tan(math.rad(math.clamp(Util.num(fovDeg, 70), 1, 120)) / 2)
	local aspect = w / h
	local z = if depth > 1e-3 then depth else 1e-3
	local nx = rel.X / (z * tanHalf * aspect)
	local ny = rel.Y / (z * tanHalf)
	if depth <= 1e-3 then
		-- derrière la caméra : direction retournée, poussée hors de l'écran
		nx, ny = -rel.X, -rel.Y
		local m = math.max(math.abs(nx), math.abs(ny), 1e-6)
		nx, ny = nx / m * 2, ny / m * 2
	end
	local screen = Vector2.new((nx + 1) / 2 * w, (1 - ny) / 2 * h)
	local inFront = depth > 1e-3
	local onScreen = inFront and nx >= -1 and nx <= 1 and ny >= -1 and ny <= 1
	return screen, inFront, onScreen
end

-- Caméra courante (CFrame, champ vertical, taille de l'écran) ou nil
function Util.camera(): (CFrame?, number, Vector2)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil, 70, Vector2.new(Layout.Reference.X, Layout.Reference.Y)
	end
	return camera.CFrame, camera.FieldOfView, camera.ViewportSize
end

return Util
