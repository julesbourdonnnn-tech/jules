--!strict
-- Charte graphique de l'interface (couleurs, polices, rayons). Une seule source de vérité.

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

-- Couleurs de rareté (commun → mythique)
Theme.Rarity = {
	Common = Color3.fromRGB(200, 200, 210),
	Uncommon = Color3.fromRGB(110, 220, 120),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 60),
	Mythic = Color3.fromRGB(255, 90, 150),
}

Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.GothamBold),
	Number = Font.fromEnum(Enum.Font.FredokaOne),
}

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 8)
Theme.StrokeThickness = 3

-- Tailles minimales (pixels de référence 1280×720, mis à l'échelle par UIScale)
Theme.MinTouch = 48
Theme.ButtonHeight = 64

return Theme
