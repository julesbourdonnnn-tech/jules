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

Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.fromEnum(Enum.Font.GothamBold),
	Number = Font.fromEnum(Enum.Font.FredokaOne),
}

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 8)
Theme.StrokeThickness = 3

-- Tailles minimales (px TV d'un écran 1920 × 1080, mis à l'échelle par UIScale ; console d'abord :
-- aucune cible tactile, note INT-TV)
Theme.ButtonHeight = 80 -- = Config/Layout.Button.MinHeight
Theme.MinTextSize = 28 -- = Config/Console.MinTextSize (lisible à 3 m sur téléviseur)

return Theme
