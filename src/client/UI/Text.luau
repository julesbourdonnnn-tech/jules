--!strict
-- UI/Text (lot B1, docs/04 §27.7, N10 ; GDD v2.0 §10.1, §10.8 règles 8 et 9) : la politique de texte
-- UNIQUE du client, et le SEUL écrivain de `.Text` côté client (Static_TextSet.spec).
--
--   Text.set(label, "panel.ranch.title", { n = 3 })  -- texte par clé (retraduit si la langue change)
--   Text.raw(label, nom)                              -- texte déjà prêt (nom propre, nombre formaté)
--   Text.style(label, "label", 40)                    -- politique de taille (une fois, à la création)
--   Text.factor()                                     -- facteur RÉEL du moteur (PreferredTextSize)
--   Text.compensate(label)                            -- réapplique la politique à ce libellé
--
-- Politique (jamais `TextScaled` : un texte en TextScaled n'est pas agrandi par la taille de texte
-- choisie par le joueur, `GuiService.PreferredTextSize`, et ses bornes dépendent de l'ordre
-- TextScaled / UIScale du moteur, jamais mesuré) : `TextSize` FIXE, `UITextSizeConstraint` posée
-- par ce module. Trois sortes de texte :
--   * "label" (noms, nombres, libellés de boutons, de cases, de lignes) : dessiné à sa taille
--     (MaxTextSize = taille dessinée) quelle que soit la taille choisie par le joueur ; si le moteur
--     les agrandit quand même (contrainte ignorée, mesurée par le témoin borné), TextSize = taille ÷ f ;
--   * "sentence" (phrases des bandeaux et des cartes, boîtes prévues pour Largest) : TextSize = taille
--     dessinée, agrandie par le moteur jusqu'à Text.MaxFactor (pire cas 1,5, GDD §10.1) ;
--   * "fit" (exception fermée : textes de longueur libre faits du nom d'un joueur, d'une espèce ou
--     d'une mutation — bannières, titres des cartes de côté, grands tampons — et deux libellés que
--     la police tranche au pixel) : la plus grande taille ENTIÈRE de [min, taille] où le texte tient
--     dans sa boîte, mesurée ici (TextService, valeurs ramenées à Medium), puis traitée comme un
--     "label". C'est la règle de l'ancien TextScaled, calculée par le jeu : même image à Medium.
-- Option `words` (libellés des panneaux, Widgets) : la taille est aussi bornée pour que le mot le
-- plus long tienne sur une ligne (le moteur coupe entre deux lettres un mot plus large que la boîte).
-- Le facteur f vient de deux étiquettes témoins cachées (texte connu, TextSize 48, dans un ScreenGui
-- sans UIScale) : libre (f = TextBounds.Y ÷ 48) et bornée par une contrainte MaxTextSize = 48
-- (facteur appliqué malgré la contrainte) ; mesuré au premier usage, à chaque changement de
-- `GuiService.PreferredTextSize` et de `TextBounds` des témoins. Les vrais facteurs de la PS5 sont
-- photographiés avec le panneau TextProbe (Diagnostics, administrateurs).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)

local Text = {}

export type Kind = "label" | "sentence" | "fit"
export type TextObject = TextLabel | TextButton | TextBox
export type StyleOptions = {
	min: number?, -- plus petite taille d'un "fit" et de la borne des mots (px TV ; défaut Layout.Text.Min)
	words: boolean?, -- borne du mot le plus long (aucun mot coupé entre deux lettres)
	wrapped: boolean?, -- retours à la ligne (défaut : vrai, comme l'ancien TextScaled)
}
export type Measurements = {
	factor: number, -- facteur du moteur sur un texte libre (1 à Medium)
	bound: number, -- facteur du moteur sur un texte borné par MaxTextSize (1 si la contrainte borne)
	compensation: number, -- diviseur appliqué aux "label" et "fit" (= bound)
	preferred: string, -- nom de GuiService.PreferredTextSize
	freeY: number, -- TextBounds.Y du témoin libre (px)
	boundY: number, -- TextBounds.Y du témoin borné (px)
	valid: boolean, -- vrai quand les témoins ont été dessinés
}

-- Pire cas en attendant les photos de la PS5 (GDD §10.1 (3)) : facteur maximal d'une phrase
Text.MaxFactor = 1.5
Text.WitnessSize = 48
Text.WitnessText = "Hg 0123456789"
-- écart sous lequel un facteur mesuré vaut 1 (arrondi des TextBounds au pixel ; les réglages de
-- Roblox agrandissent bien plus qu'un pixel sur 48)
Text.Tolerance = 0.05

type Entry = {
	kind: Kind,
	size: number, -- taille dessinée (px TV)
	min: number,
	words: boolean,
	wrapped: boolean,
	watching: boolean, -- AbsoluteSize suivie (fit, words)
	applied: number, -- dernière taille posée (TextSize)
	display: number, -- taille voulue à l'écran (px TV, avant le facteur du moteur et la compensation)
}
type Binding = { key: string, args: { [string]: any }? }

local styles: { [Instance]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local bound: { [Instance]: Binding } = setmetatable({}, { __mode = "k" }) :: any

local measured: Measurements = {
	factor = 1,
	bound = 1,
	compensation = 1,
	preferred = "Medium",
	freeY = 0,
	boundY = 0,
	valid = false,
}
local witnessGui: ScreenGui? = nil
local witnessFree: TextLabel? = nil
local witnessBound: TextLabel? = nil
local hooked = false

-- =============================================================================================
-- Mesure du moteur
-- =============================================================================================

local function preferredName(): string
	local ok, value = pcall(function()
		return (GuiService :: any).PreferredTextSize
	end)
	if ok and typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	return "Medium"
end

-- Facteur d'un témoin : TextBounds.Y ÷ taille ; 1 si le témoin n'est pas encore dessiné (0) ou si la
-- mesure est absurde (le moteur n'agrandit jamais en dessous de Medium) ; 2 au plus
local function factorOf(label: TextLabel?): (number, number, boolean)
	if label == nil then
		return 1, 0, false
	end
	local ok, bounds = pcall(function()
		return label.TextBounds
	end)
	if not ok or typeof(bounds) ~= "Vector2" then
		return 1, 0, false
	end
	local y = (bounds :: Vector2).Y
	if y ~= y or y <= 0 then
		return 1, 0, false
	end
	local f = y / Text.WitnessSize
	-- TextBounds arrondis au pixel (±1 px sur 48 : ±2 %) : sous Text.Tolerance, c'est Medium
	if f < 1 + Text.Tolerance then
		return 1, y, true
	end
	return math.min(math.floor(f * 100 + 0.5) / 100, 2), y, true
end

local reapplyAll: () -> () = function() end
local listeners: { () -> () } = {} -- Text.onMeasured

local function measure()
	local f, freeY, okFree = factorOf(witnessFree)
	local g, boundY, okBound = factorOf(witnessBound)
	local compensation = if g > 1 then g else 1
	local changed = math.abs(compensation - measured.compensation) > 1e-6
		or math.abs(f - measured.factor) > 1e-6
	measured.factor = f
	measured.bound = g
	measured.compensation = compensation
	measured.preferred = preferredName()
	measured.freeY = freeY
	measured.boundY = boundY
	measured.valid = okFree and okBound
	if changed then
		reapplyAll()
	end
	for _, fn in listeners do
		task.spawn(fn)
	end
end

local function makeWitness(parent: Instance, name: string, constrained: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.Size = UDim2.fromOffset(16 * Text.WitnessSize, 3 * Text.WitnessSize)
	-- hors de l'écran (au-dessus à gauche) : jamais dessiné sous un panneau ni dans la zone sûre ; la
	-- mise en page du texte (TextBounds) ne dépend pas de la position
	label.Position = UDim2.fromOffset(-20 * Text.WitnessSize, -6 * Text.WitnessSize)
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = Text.WitnessSize
	label.Text = Text.WitnessText
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.AutoLocalize = false
	label.Selectable = false
	label.Active = false
	label:SetAttribute("Decorative", true)
	if constrained then
		local c = Instance.new("UITextSizeConstraint")
		c.MinTextSize = 1
		c.MaxTextSize = Text.WitnessSize
		c.Parent = label
	end
	label.Parent = parent
	label:GetPropertyChangedSignal("TextBounds"):Connect(measure)
	return label
end

-- Témoins cachés (créés une fois, dès que PlayerGui existe) ; aucune attente
local function ensureWitness()
	if witnessGui ~= nil and witnessGui.Parent ~= nil then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TextWitness"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("Decorative", true)
	witnessFree = makeWitness(gui, "Free", false)
	witnessBound = makeWitness(gui, "Bound", true)
	gui.Parent = playerGui
	witnessGui = gui
	if not hooked then
		hooked = true
		pcall(function()
			GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(measure)
		end)
	end
	measure()
end

-- Facteur réel du moteur sur un texte libre (1 à Medium ; pire cas attendu à Largest : 1,5)
function Text.factor(): number
	ensureWitness()
	return measured.factor
end

-- Diviseur appliqué aux libellés : 1 si la contrainte MaxTextSize borne le moteur
function Text.compensation(): number
	ensureWitness()
	return measured.compensation
end

-- Dernière mesure (panneau TextProbe, Diagnostics)
function Text.measurements(): Measurements
	ensureWitness()
	return table.clone(measured)
end

-- Remesure (changement de réglage, specs)
function Text.remeasure()
	ensureWitness()
	measure()
end

-- Signal du réglage du joueur : `fn()` après chaque nouvelle mesure (panneau TextProbe)
function Text.onMeasured(fn: () -> ())
	table.insert(listeners, fn)
end

-- Étiquette témoin VISIBLE du panneau TextProbe (Diagnostics) : texte connu, TextSize fixe `size`,
-- contrainte MaxTextSize = `size` si `bound` ; jamais stylée ni compensée (elle montre ce que fait
-- vraiment le moteur, photographiée sur la PS5). Le seul autre créateur d'étiquettes de taille fixe.
function Text.witness(parent: Instance, name: string, size: number, bound: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = Text.WitnessText
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.AutoLocalize = false
	label:SetAttribute("TextProbe", true)
	if bound then
		local c = Instance.new("UITextSizeConstraint")
		c.MinTextSize = 1
		c.MaxTextSize = size
		c.Parent = label
	end
	label.Parent = parent
	return label
end

-- =============================================================================================
-- Mesure d'un texte (tailles de "fit" et borne des mots), en px TV à Medium
-- =============================================================================================

local function enumFont(label: TextObject): Enum.Font
	local ok, family = pcall(function()
		return label.FontFace.Family
	end)
	if ok and type(family) == "string" then
		if string.find(family, "LuckiestGuy", 1, true) then
			return Enum.Font.LuckiestGuy
		elseif string.find(family, "Gotham", 1, true) then
			return Enum.Font.GothamBold
		end
	end
	return Enum.Font.FredokaOne
end

-- Taille d'un texte (px TV à Medium) : TextService honore PreferredTextSize (documentation
-- Roblox) ; ramenée à Medium par le facteur mesuré, boîte de retour à la ligne comprise
local function textSize(text: string, size: number, font: Enum.Font, wrapWidth: number?): Vector2
	local f = measured.factor
	local frame = Vector2.new(if wrapWidth then wrapWidth * f else 1e5, 1e5)
	local ok, result = pcall(function()
		return TextService:GetTextSize(text, size, font, frame)
	end)
	if ok and typeof(result) == "Vector2" then
		return (result :: Vector2) / f
	end
	-- repli (jamais attendu) : largeur moyenne d'un caractère de FredokaOne
	return Vector2.new((utf8.len(text) or #text) * size * 0.55, size)
end

-- Échelle cumulée (UIScale du libellé et de ses ancêtres : Root, pressions des boutons) :
-- AbsoluteSize ÷ échelle = taille en px TV
local function scaleOf(label: Instance): number
	local s = 1
	local cur: Instance? = label
	while cur ~= nil do
		for _, child in cur:GetChildren() do
			if child:IsA("UIScale") then
				s *= (child :: UIScale).Scale
			end
		end
		cur = cur.Parent
	end
	return math.max(s, 1e-3)
end

local function boxOf(label: TextObject): Vector2?
	local ok, abs = pcall(function()
		return label.AbsoluteSize
	end)
	if not ok or typeof(abs) ~= "Vector2" then
		return nil
	end
	local s = scaleOf(label)
	local w, h = (abs :: Vector2).X / s, (abs :: Vector2).Y / s
	local pad = label:FindFirstChildOfClass("UIPadding")
	if pad then
		w -= pad.PaddingLeft.Offset + pad.PaddingRight.Offset + w * (pad.PaddingLeft.Scale + pad.PaddingRight.Scale)
		h -= pad.PaddingTop.Offset + pad.PaddingBottom.Offset + h * (pad.PaddingTop.Scale + pad.PaddingBottom.Scale)
	end
	if w <= 1 or h <= 1 then
		return nil
	end
	return Vector2.new(w, h)
end

local function plainText(label: TextObject): string
	local text = label.Text
	if label.RichText then
		text = string.gsub(text, "<[^<>]->", "")
	end
	return text
end

local WORD_REF = 100
local wordCache: { [string]: number } = {}
local wordCacheSize = 0

-- Largeur (px TV à Medium, taille 100) du mot le plus long ; espaces ordinaires seulement (le moteur
-- ne coupe jamais à l'espace insécable)
local function longestWord(text: string, font: Enum.Font): number
	local best = 0
	for word in string.gmatch(text, "[^ \t\n]+") do
		local cacheKey = font.Name .. "|" .. word
		local w = wordCache[cacheKey]
		if w == nil then
			w = textSize(word, WORD_REF, font, nil).X
			if wordCacheSize > 2000 then
				table.clear(wordCache)
				wordCacheSize = 0
			end
			wordCache[cacheKey] = w
			wordCacheSize += 1
		end
		best = math.max(best, w)
	end
	return best
end

-- Plus grande taille entière de [lo, hi] où le texte tient dans la boîte (règle de l'ancien
-- TextScaled) ; lo s'il ne tient nulle part
local function fitSize(label: TextObject, box: Vector2, lo: number, hi: number, wrapped: boolean): number
	local text = plainText(label)
	if text == "" then
		return hi
	end
	local font = enumFont(label)
	local function fits(size: number): boolean
		local s = textSize(text, size, font, if wrapped then box.X else nil)
		local lines = if wrapped then 1 else select(2, string.gsub(text, "\n", "")) + 1
		local height = if wrapped then s.Y else size * lines
		return s.X <= box.X + 0.01 and height <= box.Y + 0.01
	end
	local top = math.floor(hi)
	local bottom = math.max(1, math.ceil(math.min(lo, top)))
	if not fits(bottom) then
		return bottom
	end
	local a, b = bottom, top
	while a < b do
		local mid = math.ceil((a + b) / 2)
		if fits(mid) then
			a = mid
		else
			b = mid - 1
		end
	end
	return a
end

-- =============================================================================================
-- Politique de taille
-- =============================================================================================

local function constraintOf(label: TextObject): UITextSizeConstraint
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if c == nil then
		c = Instance.new("UITextSizeConstraint")
		c.Parent = label
	end
	return c :: UITextSizeConstraint
end

local function apply(label: TextObject, e: Entry)
	local base = e.size
	local floorSize = math.min(e.min, e.size)
	if e.words or e.kind == "fit" then
		local box = boxOf(label)
		if box then
			if e.words then
				local wordW = longestWord(plainText(label), enumFont(label))
				if wordW > 0 then
					base = math.min(base, math.floor(box.X * WORD_REF / wordW))
				end
			end
			if e.kind == "fit" then
				base = fitSize(label, box, floorSize, base, e.wrapped)
			end
		end
	end
	base = math.max(base, floorSize)
	local size, maxSize
	if e.kind == "sentence" then
		size = base
		maxSize = math.ceil(base * Text.MaxFactor)
	else
		size = math.max(1, math.floor(base / measured.compensation + 0.5))
		maxSize = base
	end
	local c = constraintOf(label)
	local minSize = math.max(1, math.min(size, maxSize))
	-- jamais MinTextSize > MaxTextSize, même un instant : le maximum monte d'abord s'il le faut
	local currentMax = c.MaxTextSize
	if type(currentMax) ~= "number" or currentMax < minSize then
		c.MaxTextSize = maxSize
	end
	if c.MinTextSize ~= minSize then
		c.MinTextSize = minSize
	end
	if c.MaxTextSize ~= maxSize then
		c.MaxTextSize = maxSize
	end
	if label.TextScaled then
		label.TextScaled = false
	end
	if label.TextWrapped ~= e.wrapped then
		label.TextWrapped = e.wrapped
	end
	if label.TextSize ~= size then
		label.TextSize = size
	end
	-- bornes d'un "fit" lisibles par l'outil d'écrans (il mesure toute autre clé dans la boîte avec
	-- la même règle que le jeu) ; aucune sur les autres sortes
	local fitMin = if e.kind == "fit" then floorSize else nil
	local fitMax = if e.kind == "fit" then e.size else nil
	if label:GetAttribute("TextFitMin") ~= fitMin then
		label:SetAttribute("TextFitMin", fitMin)
	end
	if label:GetAttribute("TextFitMax") ~= fitMax then
		label:SetAttribute("TextFitMax", fitMax)
	end
	e.applied = size
	e.display = base
end

reapplyAll = function()
	for label, e in styles do
		if label.Parent ~= nil then
			apply(label :: TextObject, e)
		end
	end
end

-- Déclare (ou change) la politique de taille d'un texte : sorte, taille dessinée (px TV), options.
-- Peut être rappelé (taille du monde qui change avec l'échelle, borne d'un libellé) : rien d'autre
-- n'écrit TextSize, TextScaled ni la contrainte d'un texte stylé.
function Text.style(label: TextObject, kind: Kind, size: number, opts: StyleOptions?)
	ensureWitness()
	local o: StyleOptions = opts or {}
	local drawn = if type(size) == "number" and size == size and size > 0 then size else Layout.Text.Body
	local e = styles[label]
	if e == nil then
		e = {
			kind = kind,
			size = drawn,
			min = o.min or Layout.Text.Min,
			words = o.words == true,
			wrapped = o.wrapped ~= false,
			watching = false,
			applied = 0,
			display = drawn,
		}
		styles[label] = e
	else
		e.kind = kind
		e.size = drawn
		e.min = o.min or e.min
		if o.words ~= nil then
			e.words = o.words
		end
		if o.wrapped ~= nil then
			e.wrapped = o.wrapped
		end
	end
	local entry = e :: Entry
	if (entry.words or entry.kind == "fit") and not entry.watching then
		entry.watching = true
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local cur = styles[label]
			if cur then
				apply(label, cur)
			end
		end)
	end
	apply(label, entry)
end

-- Taille dessinée d'un texte stylé (nil sinon)
function Text.drawnSize(label: Instance): number?
	local e = styles[label]
	return if e then e.size else nil
end

-- Sorte d'un texte stylé (nil sinon)
function Text.kind(label: Instance): Kind?
	local e = styles[label]
	return if e then e.kind else nil
end

-- Taille posée par la politique (TextSize), avant le facteur du moteur
function Text.appliedSize(label: Instance): number?
	local e = styles[label]
	return if e then e.applied else nil
end

-- Taille voulue à l'écran (px TV) : taille dessinée, bornée par le mot le plus long ou ajustée par
-- "fit" ; un "label" y est dessiné quelle que soit la taille de texte du joueur, une "sentence" en
-- est le point de départ (agrandie par le moteur)
function Text.displaySize(label: Instance): number?
	local e = styles[label]
	return if e then e.display else nil
end

-- Réapplique la politique à ce libellé (compensation comprise) ; sans effet sur un texte non stylé
function Text.compensate(label: TextObject)
	local e = styles[label]
	if e then
		apply(label, e)
	end
end

-- =============================================================================================
-- Écriture du texte (seul écrivain de .Text côté client)
-- =============================================================================================

local languageHooked = false

local function write(label: TextObject, text: string)
	if label.Text ~= text then
		label.Text = text
		local e = styles[label]
		if e and (e.words or e.kind == "fit") then
			apply(label, e)
		end
	end
end

local function hookLanguage()
	if languageHooked then
		return
	end
	languageHooked = true
	Prefs.LanguageChanged:Connect(function()
		for label, b in bound do
			if label.Parent ~= nil then
				write(label :: TextObject, Prefs.t(b.key, b.args))
			end
		end
	end)
end

-- Texte traduit posé par clé (retraduit tout seul quand la langue change)
function Text.set(label: TextObject, key: string, args: { [string]: any }?)
	hookLanguage()
	bound[label] = { key = key, args = args }
	write(label, Prefs.t(key, args))
end

-- Texte brut (nom propre, nombre déjà formaté par UI/Format ou Logic/BigNumber) : plus de
-- retraduction automatique ; une valeur qui n'est pas une chaîne devient « »
function Text.raw(label: TextObject, text: string)
	bound[label] = nil
	write(label, if type(text) == "string" then text else "")
end

-- Clé posée sur ce texte (nil si texte brut)
function Text.keyOf(label: Instance): string?
	local b = bound[label]
	return if b then b.key else nil
end

return Text
