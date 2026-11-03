--!strict
-- Charte graphique de l'interface (couleurs, polices, rayons). Une seule source de vérité.
-- Socle : couleurs de base de Comet Conga (contrastes vérifiés sur téléviseur). La
-- direction artistique du jeu (pastel de Wobbleton, couleurs des 7 raretés, couleur ET forme pour
-- les daltoniens) les remplacera ici, sans changer les noms des champs.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(28, 24, 48),
	Panel = Color3.fromRGB(44, 38, 74),
	PanelLight = Color3.fromRGB(62, 54, 102),
	Stroke = Color3.fromRGB(16, 12, 30),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 184, 220),
	Primary = Color3.fromRGB(88, 196, 255),
	Success = Color3.fromRGB(92, 220, 120),
	Warning = Color3.fromRGB(255, 196, 64),
	Danger = Color3.fromRGB(255, 92, 104),
	Gold = Color3.fromRGB(255, 208, 72),
	Premium = Color3.fromRGB(196, 120, 255),
}

-- Polices (GDD v2.0 §10.1) : FredokaOne pour tout le texte, LuckiestGuy pour les tampons (fichiers
-- rangés dans assets/fonts, table cmap vérifiée par Contract_glyphs). Lot B1 (INT-V2-GLYPHS a) : le
-- texte courant (messages, cartes) passe de GothamBold à FredokaOne.
Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.FredokaOne),
	Number = Font.fromEnum(Enum.Font.FredokaOne),
	Stamp = Font.fromEnum(Enum.Font.LuckiestGuy),
}

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 8)
Theme.StrokeThickness = 3

-- =============================================================================================
-- Styles récents du moteur (lot B1 ; GDD v2.0 §10.1, critique m21) : ombre `UIShadow` (6 px vers le
-- bas, douce, 50 %) seulement sur les panneaux et les cartes, dégradé radial pour les révélations et le
-- titre du Grand Splorch. Un appareil qui ne les a pas (ou un nom de propriété qui y diffère) : REPLI
-- AUTOMATIQUE SUR L'APLAT, sous pcall, compté (Theme.styleFallbacks, puis Diagnostics), jamais une
-- erreur. L'ombre de repli est un Frame frère, décalé de 6 px vers le bas, à 50 % (1 objet par
-- panneau ou carte) ; c'est aussi le style des captures de référence hors ligne.
-- =============================================================================================

Theme.Shadow = {
	Offset = 6, -- px TV vers le bas
	Transparency = 0.5,
	Blur = 8,
	Color = Color3.fromRGB(0, 0, 0),
}

local fallbacks = 0
-- Rappel posé par Diagnostics (compteur StyleFallback, lot A4) : (sorte : "shadow" | "radial")
Theme.onStyleFallback = nil :: ((kind: string) -> ())?

local function noteFallback(kind: string)
	fallbacks += 1
	local fn = Theme.onStyleFallback
	if fn then
		pcall(fn, kind)
	end
end

-- Replis comptés depuis le démarrage (specs, Diagnostics)
function Theme.styleFallbacks(): number
	return fallbacks
end

-- Ombre de repli : Frame frère derrière la cible, même taille et même ancrage, 6 px plus bas ; suit
-- sa taille, sa place, sa visibilité, son parent et ses coins
local function fallbackShadow(target: GuiObject): Frame
	local shadow = Instance.new("Frame")
	shadow.Name = target.Name .. "_Shadow"
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = Theme.Shadow.Transparency
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.Selectable = false
	shadow:SetAttribute("Decorative", true)
	local corner = Instance.new("UICorner")
	local source = target:FindFirstChildOfClass("UICorner")
	corner.CornerRadius = if source then source.CornerRadius else Theme.Corner
	corner.Parent = shadow
	local function follow()
		shadow.Size = target.Size
		shadow.AnchorPoint = target.AnchorPoint
		shadow.Position = target.Position + UDim2.fromOffset(0, Theme.Shadow.Offset)
		shadow.Visible = target.Visible
		shadow.ZIndex = math.max(0, target.ZIndex - 1)
		shadow.LayoutOrder = target.LayoutOrder
		if shadow.Parent ~= target.Parent then
			shadow.Parent = target.Parent
		end
	end
	follow()
	for _, prop in { "Size", "Position", "AnchorPoint", "Visible", "ZIndex", "Parent" } do
		target:GetPropertyChangedSignal(prop):Connect(follow)
	end
	target.Destroying:Connect(function()
		shadow:Destroy()
	end)
	return shadow
end

-- Ombre d'un panneau ou d'une carte : UIShadow du moteur, sinon l'ombre de repli. Rend l'objet posé
-- et vrai si c'est la vraie ombre du moteur.
function Theme.shadow(target: GuiObject): (Instance?, boolean)
	if typeof(target) ~= "Instance" or not target:IsA("GuiObject") then
		return nil, false
	end
	local ok, shadow = pcall(function()
		local s: any = Instance.new("UIShadow" :: any)
		s.Color = Theme.Shadow.Color
		s.Transparency = Theme.Shadow.Transparency
		s.Offset = Vector2.new(0, Theme.Shadow.Offset)
		s.BlurRadius = Theme.Shadow.Blur
		s.Parent = target
		return s
	end)
	if ok and shadow then
		return shadow, true
	end
	noteFallback("shadow")
	-- parent rangé par un UI*Layout : l'ombre de repli deviendrait un élément de la liste ; aucune
	-- ombre (aplat), la carte reste entière (note INT-B1-SHADOW : poser la carte dans un support)
	local parent = target.Parent
	if parent ~= nil then
		for _, child in parent:GetChildren() do
			if child:IsA("UIGridStyleLayout") or child:IsA("UITableLayout") then
				return nil, false
			end
		end
	end
	local made, frame = pcall(fallbackShadow, target)
	return if made then frame else nil, false
end

-- Dégradé radial (révélations, titre du Grand Splorch) ; faux : le dégradé reste linéaire (aplat)
function Theme.radial(gradient: UIGradient): boolean
	if typeof(gradient) ~= "Instance" or not gradient:IsA("UIGradient") then
		return false
	end
	local ok = pcall(function()
		(gradient :: any).Type = "Radial"
	end)
	if not ok then
		noteFallback("radial")
	end
	return ok
end

-- Tailles minimales (px TV d'un écran 1920 × 1080, mis à l'échelle par UIScale ; console d'abord :
-- aucune cible tactile, note INT-TV)
Theme.ButtonHeight = 80 -- = Config/Layout.Button.MinHeight
Theme.MinTextSize = 28 -- = Config/Console.MinTextSize (lisible à 3 m sur téléviseur)

return Theme
