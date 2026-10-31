--!strict
-- Palette — paquet « world » : constantes graphiques NOMMÉES des recettes du décor de Lumora
-- (GDD §11.1-§11.5). Positions, rayons, nombres d'objets et couleurs de gameplay viennent de
-- Config/Zones ; ici ne vivent que les détails purement visuels internes aux recettes (tolérés par
-- le contrat, docs/04-architecture.md §1.5).

local Palette = {}

-- Matériaux (§11.5) et couleurs de base
Palette.Wood = Color3.fromRGB(110, 80, 60)
Palette.Marble = Color3.fromRGB(235, 230, 250)
Palette.Slate = Color3.fromRGB(90, 95, 120)
Palette.FreeArch = Color3.fromRGB(150, 150, 162) -- arche d'un Nid libre (gris, sans Néon)

-- Île et sols
Palette.GladeThickness = 0.2
Palette.CraterThickness = 0.4
Palette.CliffTopGap = 0.2 -- la falaise s'arrête sous le dessus de l'île (pas de z-fighting)
Palette.CliffOverlap = 1.08 -- recouvrement tangentiel des WedgeParts de la falaise
Palette.WallBottomY = -1
Palette.CrackHeight = 0.05
Palette.CrackWidth = 0.2

-- Chemins et lanternes
Palette.StoneTopLift = 0.05 -- dessus des pas japonais au-dessus du sol
Palette.LanternPoleDiameter = 0.6
Palette.LanternBulbDiameter = 1.4

-- Balise (§11.2)
Palette.BeaconRingThickness = 0.6
Palette.BeaconRingOverhang = 2 -- diamètre de l'anneau = étage supérieur + 2
Palette.StarArm = Vector3.new(8, 1, 1)
Palette.StarCore = 3
Palette.StarSpinSpeed = 0.8
Palette.StarPulseAmount = 0.12
Palette.StarPulsePeriod = 2
Palette.StarLightRange = 24
Palette.StarLightBrightness = 2
Palette.RingLightRange = 18
Palette.RingLightBrightness = 1.2
Palette.DepositThickness = 0.2
Palette.DepositLift = 0.12 -- au-dessus du sol du Cratère
Palette.BeamTransparencyTop = 0.85
Palette.BoardSize = Vector3.new(10, 6, 0.8)
Palette.BoardColor = Color3.fromRGB(70, 60, 110)

-- Nids (§11.3)
Palette.ArchThickness = 0.8
Palette.DomeDiameter = 7
Palette.DomeColor = Color3.fromRGB(170, 200, 255)
Palette.TelescopeDiameter = 1.4
Palette.TelescopeLength = 6
Palette.TelescopeTilt = 35 -- degrés
Palette.TelescopeColor = Color3.fromRGB(110, 100, 150)
Palette.SpawnSize = Vector3.new(6, 1, 6)
Palette.PerchRingThickness = 0.15
Palette.PerchRingOverhang = 0.3
Palette.FloatingPerchThickness = 0.3

-- Décor de la Prairie (§11.4)
Palette.PuffStem = Color3.fromRGB(110, 170, 125)
Palette.PuffStemSize = Vector3.new(3, 0.3, 0.3) -- Cylinder : longueur × diamètre
Palette.PuffBloomDiameter = 1.2
Palette.PuffPastels = {
	Color3.fromRGB(255, 170, 210),
	Color3.fromRGB(170, 240, 210),
	Color3.fromRGB(200, 180, 255),
	Color3.fromRGB(255, 210, 160),
	Color3.fromRGB(160, 215, 255),
} :: { Color3 }
Palette.MushStem = Color3.fromRGB(245, 235, 220)
Palette.MushStemSize = Vector3.new(2, 1, 1)
Palette.MushCapDiameter = 3
Palette.MushCapSink = 0.8 -- centre du chapeau = haut du pied + rayon − enfoncement (« enfoncé »)
Palette.MushDotDiameter = 0.45
Palette.MushCaps = {
	Color3.fromRGB(235, 90, 120),
	Color3.fromRGB(200, 110, 230),
	Color3.fromRGB(255, 140, 90),
	Color3.fromRGB(120, 140, 240),
} :: { Color3 }
Palette.MushDot = Color3.fromRGB(255, 255, 255)
Palette.FencePost = Vector3.new(0.4, 2, 0.4)
Palette.FenceRail = Vector3.new(0.25, 0.3, 4.2)
Palette.FenceSpan = 1.9 -- demi-écart entre les deux poteaux

-- Décor de la Clairière
Palette.CrystalMin = 3
Palette.CrystalMax = 5
Palette.CrystalLightRange = 10
Palette.CrystalLightBrightness = 1
Palette.FloatingStoneSize = Vector3.new(1.6, 1.2, 1.4)
Palette.FloatingStoneColor = Color3.fromRGB(150, 150, 178)

-- Îlots et nuages
Palette.IsletRockDiameter = 14
Palette.IsletTopSize = Vector3.new(2, 16, 16) -- Cylinder : épaisseur × diamètre
Palette.IsletTopLift = 5
Palette.CloudScaleMin = 3
Palette.CloudScaleMax = 4.5

return Palette
