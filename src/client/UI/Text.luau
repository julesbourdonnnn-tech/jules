--!strict
-- UI/Text (lot B1, docs/04 §27.7, N10 ; GDD v2.0 §10.1, §10.8 règles 8 et 9) : la politique de texte
-- UNIQUE du client, et le SEUL écrivain de `.Text` côté client (Static_TextSet.spec).
--
--   Text.set(label, "panel.ranch.title", { n = 3 })  -- texte par clé (retraduit si la langue change)
--   Text.raw(label, nom)                              -- texte déjà prêt (nom propre, nombre formaté)
--   Text.style(label, "label", 40)                    -- politique de taille (une fois, à la création)
--   Text.factor()                                     -- facteur RÉEL du moteur (PreferredTextSize)
--   Text.compensate(label)                            -- réapplique la politique à ce libellé
--   Text.STAR (« {*} »), Text.GLUE (« {_} »)          -- repères des clés (lot B1, étape 2) : étoile
--                                                     -- dessinée ; espace qui ne coupe jamais la ligne
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
-- photographiés avec le panneau TextProbe (Diagnostics, administrateurs). Relecture B1 (B1-15) : le
-- facteur que TextService:GetTextSize applique LUI-MÊME est mesuré aussi (même texte témoin) ; les
-- mesures des "fit", de la borne des mots et des lignes ne supposent plus qu'il honore la taille du
-- joueur. Une phrase est mise en lignes et ses étoiles posées à sa taille À L'ÉCRAN (agrandie).

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
	-- facteur que TextService:GetTextSize applique lui-même (relecture B1, B1-15) : 1 s'il ignore la
	-- taille de texte du joueur, `factor` s'il l'honore ; mesuré sur le même texte témoin, jamais supposé
	service: number,
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
	service = 1,
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
local clearWordCache: () -> () = function() end
local listeners: { () -> () } = {} -- Text.onMeasured

-- Facteur que TextService:GetTextSize applique lui-même (relecture B1, B1-15). La documentation ne
-- tranche pas et rien n'a été mesuré sur la PS5 : il est MESURÉ, sur le texte du témoin libre (même
-- texte, même taille, même police), = f × (hauteur rendue par TextService ÷ hauteur dessinée par le
-- moteur) : 1 si TextService ignore la taille du joueur, f s'il l'honore ; 1 tant que le témoin
-- n'est pas dessiné (la mesure reprend au premier dessin)
local function serviceFactor(f: number, freeY: number): number
	if freeY <= 0 then
		return 1
	end
	local ok, result = pcall(function()
		return TextService:GetTextSize(
			Text.WitnessText,
			Text.WitnessSize,
			Enum.Font.FredokaOne,
			Vector2.new(1e5, 1e5)
		)
	end)
	if not ok or typeof(result) ~= "Vector2" then
		return 1
	end
	local y = (result :: Vector2).Y
	if y ~= y or y <= 0 then
		return 1
	end
	local s = f * y / freeY
	if s < 1 + Text.Tolerance then
		return 1
	end
	return math.min(math.floor(s * 100 + 0.5) / 100, 2)
end

local function measure()
	local f, freeY, okFree = factorOf(witnessFree)
	local g, boundY, okBound = factorOf(witnessBound)
	local compensation = if g > 1 then g else 1
	local service = serviceFactor(f, freeY)
	local changed = math.abs(compensation - measured.compensation) > 1e-6
		or math.abs(f - measured.factor) > 1e-6
		or math.abs(g - measured.bound) > 1e-6
		or math.abs(service - measured.service) > 1e-6
	if math.abs(service - measured.service) > 1e-6 then
		-- largeurs de mots mises en cache sous l'ancien facteur de TextService : à remesurer
		clearWordCache()
	end
	measured.factor = f
	measured.bound = g
	measured.compensation = compensation
	measured.service = service
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

-- Taille d'un texte (px TV à Medium) : ramenée à Medium par le facteur que TextService applique
-- LUI-MÊME (measured.service, mesuré : 1 s'il ignore PreferredTextSize, le facteur du joueur s'il
-- l'honore ; relecture B1, B1-15), boîte de retour à la ligne comprise
local function textSize(text: string, size: number, font: Enum.Font, wrapWidth: number?): Vector2
	local f = measured.service
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
clearWordCache = function()
	table.clear(wordCache)
	wordCacheSize = 0
end

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

-- Plus grande taille entière de [lo, hi] où `fits` est vrai ; lo s'il ne l'est nulle part
local function largest(lo: number, hi: number, fits: (size: number) -> boolean): number
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
	return largest(lo, hi, fits)
end

-- Taille "fit" d'un texte à mots tenus ensemble (défini plus bas, avec les repères) : calculée sur
-- son texte d'origine coupé à CHAQUE taille essayée, jamais sur les lignes d'une écriture précédente
-- (relecture B1, B1-23) ; nil si le libellé n'en porte pas
local gluedFit: (label: TextObject, box: Vector2, lo: number, hi: number) -> number? = function()
	return nil
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
				base = gluedFit(label, box, floorSize, base)
					or fitSize(label, box, floorSize, base, e.wrapped)
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

-- Mots tenus ensemble et étoiles dessinées d'un libellé, refaits à sa taille à l'écran (définie plus
-- bas) : une phrase agrandie par le moteur ne change ni son TextSize ni sa boîte, aucun signal ne
-- les refait (relecture B1, B1-16)
local redecorate: (label: TextObject) -> () = function() end

reapplyAll = function()
	for label, e in styles do
		if label.Parent ~= nil then
			apply(label :: TextObject, e)
			redecorate(label :: TextObject)
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
-- Icônes dessinées dans le texte (lot B1 ; règle 18 du GDD v2.0 §10.8 « aucun symbole hors police »,
-- INT-V2-GLYPHS a) : le repère Text.STAR (« {*} ») d'une clé (common.stars, celebrate.star) devient une
-- étoile DESSINÉE (UI/Glyph.star). Le texte porte à sa place des espaces ordinaires (U+0020, dans la
-- police) de la largeur de l'étoile ; l'étoile est posée par-dessus, enfant du libellé, à la place
-- mesurée (TextService, retours à la ligne et alignements compris), à la couleur du texte. Replacée
-- quand la taille, la boîte, l'alignement ou la couleur changent. Un repère n'est jamais montré tel quel.
-- =============================================================================================

Text.STAR = "{*}"
-- lot B4, étape 5 (D16, D20, INT-B1-GLYPHS2) : même mécanisme pour la couronne du Record R (panneau des
-- ranchs, « ♛ » hors des polices) et la goutte du halo (plaque du titre) : UI/Glyph.crown, Glyph.drop
Text.CROWN = "{^}"
Text.DROP = "{~}"
-- Place réservée (en tailles du texte) : l'étoile (lot B1) garde l'arrondi au plus proche de ICON_EM ;
-- la couronne et la goutte réservent AU MOINS `atLeast` (arrondi au-dessus, quelle que soit la police) :
-- leur dessin liseré compris (couronne 1,01, pointes à 45° ; goutte 0,69) plus 0,1 d'air de chaque
-- côté. Captures du lot B4 : avec 5 espaces de Fredoka One (1,05), la couronne touchait « 400 ».
type IconDef = { marker: string, icon: string, atLeast: number? }
local ICONS: { IconDef } = {
	{ marker = Text.STAR, icon = "star" },
	{ marker = Text.CROWN, icon = "crown", atLeast = 1.21 },
	{ marker = Text.DROP, icon = "drop", atLeast = 0.9 },
}
local ICON_EM = 1.1 -- largeur réservée à l'étoile (em) : un peu d'air de chaque côté
local ICON_SIZE = 0.9 -- taille de l'icône (em)

type Mark = { prefix: string, count: number, icon: string }
type IconState = { marks: { Mark }, stars: { Frame }, hooked: boolean }
local iconStates: { [Instance]: IconState } = setmetatable({}, { __mode = "k" }) :: any
local GlyphModule: any = nil

local function glyph(): any
	if GlyphModule == nil then
		GlyphModule = require(script.Parent.Glyph) :: any -- requis tard (Glyph requiert Text)
	end
	return GlyphModule
end

-- Taille du texte À L'ÉCRAN (px TV) : taille voulue du style ; une phrase ("sentence") est agrandie
-- par le moteur du facteur du joueur (borné par sa contrainte, Text.MaxFactor, quand le moteur la
-- respecte) : ses lignes et ses étoiles se calculent à cette taille-là (relecture B1, B1-16) ; un
-- "label" ou un "fit" est dessiné à sa taille voulue (compensation). Sans style : TextSize.
local function shownSize(label: TextObject): number
	local e = styles[label]
	if e and e.display > 0 then
		if e.kind == "sentence" and measured.factor > 1 then
			local grown = e.display * measured.factor
			if measured.bound <= 1 then
				grown = math.min(grown, math.ceil(e.display * Text.MaxFactor))
			end
			return grown
		end
		return e.display
	end
	return math.max(1, label.TextSize)
end

local function spaceWidth(size: number, font: Enum.Font): number
	-- avance d'une espace : « a a » − « aa » (une espace seule peut mesurer 0)
	local w = textSize("a a", size, font).X - textSize("aa", size, font).X
	return if w > 0.5 then w else size * 0.25
end

-- Premier repère d'icône de `text` à partir de l'octet 1 : position et définition de l'icône
local function nextIcon(text: string): (number?, IconDef?)
	local best: number? = nil
	local found: IconDef? = nil
	for _, def in ICONS do
		local i = string.find(text, def.marker, 1, true)
		if i ~= nil and (best == nil or i < best) then
			best, found = i, def
		end
	end
	return best, found
end

-- Nombre d'espaces réservés à l'icône `def` (avance d'une espace `sw` à la taille `size`)
local function iconSpaces(def: IconDef, size: number, sw: number): number
	local atLeast = def.atLeast
	if atLeast ~= nil then
		return math.max(1, math.ceil(atLeast * size / sw - 1e-6))
	end
	return math.max(1, math.floor(ICON_EM * size / sw + 0.5))
end

-- Remplace chaque repère par des espaces de la largeur de l'icône ; rend le texte et les repères
local function expandIcons(label: TextObject, text: string): (string, { Mark }?)
	if nextIcon(text) == nil then
		return text, nil
	end
	local size = shownSize(label)
	local sw = spaceWidth(size, enumFont(label))
	local out: { string } = {}
	local marks: { Mark } = {}
	local rest = text
	while true do
		local i, def = nextIcon(rest)
		if i == nil or def == nil then
			table.insert(out, rest)
			break
		end
		local count = iconSpaces(def, size, sw)
		table.insert(out, string.sub(rest, 1, i - 1))
		table.insert(marks, { prefix = table.concat(out), count = count, icon = def.icon })
		table.insert(out, string.rep(" ", count))
		rest = string.sub(rest, i + #def.marker)
	end
	return table.concat(out), marks
end

-- Lignes d'un texte coupé à `width` (mots entiers, comme le moteur) : rend la liste des lignes
local function wrapLines(text: string, size: number, font: Enum.Font, width: number): { string }
	local lines: { string } = {}
	local line = ""
	for word, gap in string.gmatch(text, "([^ ]*)( *)") do
		if word == "" and gap == "" then
			break
		end
		local candidate = line .. word
		if line ~= "" and word ~= "" and textSize(candidate, size, font).X > width + 0.5 then
			table.insert(lines, line)
			line = word .. gap
		else
			line = candidate .. gap
		end
	end
	table.insert(lines, line)
	return lines
end

-- Lignes affichées d'un texte (retours voulus « \n », puis coupure aux espaces si la boîte est
-- trop étroite) avec la position de leur premier octet dans le texte
type Line = { text: string, start: number }
local function layoutLines(text: string, size: number, font: Enum.Font, width: number?): { Line }
	local out: { Line } = {}
	local offset = 0
	for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local parts = if width then wrapLines(paragraph, size, font, width) else { paragraph }
		local inner = 0
		for _, l in parts do
			table.insert(out, { text = l, start = offset + inner })
			inner += #l
		end
		offset += #paragraph + 1
	end
	return out
end

local function placeIcons(label: TextObject)
	local st = iconStates[label]
	if st == nil then
		return
	end
	local box = boxOf(label)
	local size = shownSize(label)
	local font = enumFont(label)
	local text = label.Text
	local pad = label:FindFirstChildOfClass("UIPadding")
	local padL = if pad then pad.PaddingLeft.Offset else 0
	local padT = if pad then pad.PaddingTop.Offset else 0
	local sw = spaceWidth(size, font)
	local lh = label.LineHeight
	local lineH = size * (if type(lh) == "number" and lh > 0 then lh else 1)
	local lines = layoutLines(text, size, font, if box and label.TextWrapped then box.X else nil)
	local blockH = #lines * lineH
	for i, mark in st.marks do
		local star: Frame
		local existing: Frame? = st.stars[i]
		if existing ~= nil and existing:GetAttribute("Icon") == mark.icon then
			star = existing
		else
			-- première icône à cette place, ou autre sorte d'icône (texte changé) : redessinée
			if existing ~= nil then
				existing:Destroy()
			end
			local draw = glyph()[mark.icon] or glyph().star
			star = draw(nil, size * ICON_SIZE)
			star.Name = "TextIcon" .. i
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Parent = label
			st.stars[i] = star
		end
		-- ligne du repère : la dernière qui commence avant lui
		local at = #mark.prefix
		local lineIndex = 1
		for li, l in lines do
			if l.start <= at then
				lineIndex = li
			end
		end
		local line = lines[lineIndex] or { text = text, start = 0 }
		local inLine = string.sub(text, line.start + 1, at)
		local boxW = if box then box.X else textSize(text, size, font).X
		local boxH = if box then box.Y else blockH
		local lineW = textSize((string.gsub(line.text, " +$", "")), size, font).X
		local x0 = 0
		if label.TextXAlignment == Enum.TextXAlignment.Center then
			x0 = (boxW - lineW) / 2
		elseif label.TextXAlignment == Enum.TextXAlignment.Right then
			x0 = boxW - lineW
		end
		local y0 = (boxH - blockH) / 2
		if label.TextYAlignment == Enum.TextYAlignment.Top then
			y0 = 0
		elseif label.TextYAlignment == Enum.TextYAlignment.Bottom then
			y0 = boxH - blockH
		end
		local x = padL + x0 + textSize(inLine, size, font).X + mark.count * sw / 2
		local y = padT + y0 + (lineIndex - 0.5) * lineH
		star.Size = UDim2.fromOffset(size * ICON_SIZE, size * ICON_SIZE)
		star.Position = UDim2.fromOffset(x, y)
		star.ZIndex = label.ZIndex + 1
		local stroke = label:FindFirstChildOfClass("UIStroke")
		glyph().paintStar(
			star,
			label.TextColor3,
			if stroke then stroke.Color else nil,
			label.TextTransparency
		)
		star.Visible = box ~= nil
	end
	for i = #st.marks + 1, #st.stars do
		st.stars[i]:Destroy()
		st.stars[i] = nil
	end
end

local function setIcons(label: TextObject, marks: { Mark }?)
	local st = iconStates[label]
	if marks == nil then
		if st then
			for _, star in st.stars do
				star:Destroy()
			end
			table.clear(st.stars)
			table.clear(st.marks)
		end
		return
	end
	if st == nil then
		st = { marks = marks, stars = {}, hooked = false }
		iconStates[label] = st
	else
		st.marks = marks
	end
	local state = st :: IconState
	if not state.hooked then
		state.hooked = true
		for _, prop in
			{
				"AbsoluteSize",
				"TextSize",
				"TextXAlignment",
				"TextYAlignment",
				"TextColor3",
				"TextTransparency",
			}
		do
			label:GetPropertyChangedSignal(prop):Connect(function()
				if #state.marks > 0 then
					pcall(placeIcons, label)
				end
			end)
		end
	end
	pcall(placeIcons, label)
end

-- Étoiles dessinées d'un libellé (specs, outil d'écrans)
function Text.icons(label: Instance): { Frame }
	local st = iconStates[label]
	return if st then table.clone(st.stars) else {}
end

-- =============================================================================================
-- Écriture du texte (seul écrivain de .Text côté client)
-- =============================================================================================

local languageHooked = false

-- =============================================================================================
-- Mots tenus ensemble (lot B1, INT-V2-GLYPHS a) : l'espace insécable U+00A0 n'est pas dans FredokaOne ;
-- le repère Text.GLUE (« {_} ») d'une clé (« Jour{_}1 », « BOOP{_}RUSH », « 1{_}sur ») est une espace
-- ORDINAIRE qui ne coupe jamais la ligne : quand le texte ne tient pas sur une ligne, UI/Text coupe
-- lui-même aux autres espaces (mesure TextService, comme le moteur) et écrit des retours « \n » ;
-- chaque ligne tient dans la boîte, le moteur n'a plus rien à couper. Recalculé quand la boîte ou la
-- taille changent.
-- =============================================================================================

Text.GLUE = "{_}"
local glued: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local glueHooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function unglue(text: string): string
	return (string.gsub(text, "{_}", " "))
end

-- Lignes d'un paragraphe (repères compris) coupé à `width` px TV à la taille `size`, aux espaces
-- ordinaires seulement ; vrai si chaque ligne tient (un mot tenu ensemble plus large que la boîte : non)
local function glueLines(
	paragraph: string,
	size: number,
	font: Enum.Font,
	width: number
): ({ string }, boolean)
	if textSize(unglue(paragraph), size, font).X <= width + 0.5 then
		return { paragraph }, true
	end
	local out: { string } = {}
	local line = ""
	for word in string.gmatch(paragraph, "[^ ]+") do
		local candidate = if line == "" then word else line .. " " .. word
		if line ~= "" and textSize(unglue(candidate), size, font).X > width + 0.5 then
			table.insert(out, line)
			line = word
		else
			line = candidate
		end
	end
	table.insert(out, line)
	for _, l in out do
		if textSize(unglue(l), size, font).X > width + 0.5 then
			return out, false
		end
	end
	return out, true
end

-- Texte à écrire : repères remplacés par des espaces, retours posés aux espaces ordinaires si besoin
local function glue(label: TextObject, text: string): string
	if string.find(text, Text.GLUE, 1, true) == nil then
		return text
	end
	local flat = unglue(text)
	local box = boxOf(label)
	if not label.TextWrapped or box == nil then
		return flat
	end
	local size = shownSize(label)
	local font = enumFont(label)
	local out: { string } = {}
	for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local lines = glueLines(paragraph, size, font, box.X)
		for _, l in lines do
			table.insert(out, unglue(l))
		end
	end
	return table.concat(out, "\n")
end

-- Taille "fit" d'un texte à mots tenus ensemble (relecture B1, B1-23) : plus grande taille entière de
-- [lo, hi] où le texte d'origine, coupé à cette taille comme glue() le coupera, tient dans la boîte
-- (chaque ligne en largeur, toutes les lignes en hauteur). L'ancien calcul mesurait les lignes coupées à
-- la taille précédente (« FLOP ! LE / PLUS RARE · / 1 sur 1,00M » coupé à 96 px) : texte deux fois trop
-- petit, ou une ligne trop large que le moteur recoupait au repère.
gluedFit = function(label: TextObject, box: Vector2, lo: number, hi: number): number?
	local raw = glued[label]
	if raw == nil or not label.TextWrapped then
		return nil
	end
	local font = enumFont(label)
	local function fits(size: number): boolean
		local n = 0
		for paragraph in string.gmatch(raw .. "\n", "([^\n]*)\n") do
			local lines, ok = glueLines(paragraph, size, font, box.X)
			if not ok then
				return false
			end
			n += #lines
		end
		return n * size <= box.Y + 0.01
	end
	return largest(lo, hi, fits)
end

local writeRaw: (label: TextObject, raw: string) -> ()
-- libellés en cours d'écriture : un changement de taille posé par l'écriture elle-même ne relance
-- jamais l'écriture (aucune boucle, que les signaux du moteur soient immédiats ou différés)
local writing: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hookGlue(label: TextObject)
	if glueHooked[label] then
		return
	end
	glueHooked[label] = true
	for _, prop in { "AbsoluteSize", "TextSize", "TextWrapped" } do
		label:GetPropertyChangedSignal(prop):Connect(function()
			local raw = glued[label]
			if raw ~= nil and not writing[label] then
				pcall(writeRaw, label, raw)
			end
		end)
	end
end

local function write(label: TextObject, raw: string)
	if string.find(raw, Text.GLUE, 1, true) ~= nil then
		glued[label] = raw
		hookGlue(label)
	else
		glued[label] = nil
	end
	writeRaw(label, raw)
end

local writeOnce: (label: TextObject, raw: string) -> ()

writeRaw = function(label: TextObject, raw: string)
	writing[label] = true
	local ok, err = pcall(writeOnce, label, raw)
	writing[label] = nil
	if not ok then
		error(err, 0)
	end
end

writeOnce = function(label: TextObject, raw: string)
	local text, marks = expandIcons(label, glue(label, raw))
	-- texte d'origine (repères compris) lisible par l'outil d'écrans, qui relie un texte affiché à sa
	-- clé (tests/harness/Screens.keyBoxes) ; aucun attribut sans repère
	local source = if text ~= raw then raw else nil
	if label:GetAttribute("TextSource") ~= source then
		label:SetAttribute("TextSource", source)
	end
	-- 2 passes au plus : la taille d'un "fit" posée, les coupures des mots tenus ensemble sont
	-- refaites à cette taille
	for _ = 1, 2 do
		if label.Text == text then
			break
		end
		label.Text = text
		local e = styles[label]
		if e == nil or not (e.words or e.kind == "fit") then
			break
		end
		apply(label, e)
		if glued[label] == nil then
			break
		end
		text, marks = expandIcons(label, glue(label, raw))
	end
	if marks ~= nil or iconStates[label] ~= nil then
		setIcons(label, marks)
	end
end

redecorate = function(label: TextObject)
	local raw = glued[label]
	if raw ~= nil then
		-- réécrit les lignes à la taille à l'écran (et replace les étoiles du même texte)
		if not writing[label] then
			pcall(writeRaw, label, raw)
		end
		return
	end
	local st = iconStates[label]
	if st and #st.marks > 0 then
		pcall(placeIcons, label)
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
