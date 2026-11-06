--!strict
-- Hud/Icons (lot B2, décision D3 ; docs/04 §27.7 ; GDD v2.0 §10.7.5, §10.7.6, §10.8 règle 18 « aucun
-- symbole hors police ») : icônes DESSINÉES en cadres (Frame, UICorner, UIStroke, Rotation), sans
-- image téléversée ni caractère. Toutes recolorables.
--
--   local icon = Icons.new("lock", 48, color, parent)     -- icône seule (l'étoile : UI/Glyph.star)
--   local c = Icons.canvas(parent, 48, { "check", "lock" }) -- toile qui dessine chacune de ces sortes
--   Icons.draw(c, "lock", color)                           -- AUCUNE instance créée (rien : kind = nil)
--   Icons.paint(c, color)                                  -- recolore le dessin courant
--   Icons.cost({ "check", "lock" })                        -- instances d'une toile (budget, règle 20)
--
-- Une toile a un réservoir fixe de pièces, calculé à sa création pour les sortes qu'elle doit savoir
-- dessiner : « pièces » (Frame + UICorner : barre, disque, losange, capsule) et « anneaux » (Frame +
-- UICorner + UIStroke). Dessiner ne fait que placer, tourner, colorer, montrer ou cacher ces pièces :
-- une ligne ou une carte de l'écran Améliorations change d'état sans jamais créer d'instance (règles 2
-- et 20). Coordonnées en fractions d'un carré (la toile suit sa taille sans être redessinée) ; épaisseur
-- d'un anneau en fraction de la taille dessinée (px TV, sous l'UIScale de UI/Root).
-- L'étoile d'une toile est le pentagramme de UI/Glyph.star (mêmes 5 traits arrondis, même épaisseur,
-- même disque central), sans son liseré ; une étoile seule (Icons.new("star")) EST Glyph.star.
-- Teintes : "fill" = couleur de l'icône, "dark" et "light" = cette couleur assombrie ou éclaircie,
-- "edge" = bleu nuit des contours ; quelques sortes gardent leurs couleurs propres (confettis, palette,
-- traînée), sauf si on les recolore.

local Client = script.Parent.Parent.Parent
local Theme = require(Client.UI.Theme)
local Glyph = require(Client.UI.Glyph)

local Icons = {}

type Shade = "fill" | "dark" | "light" | "edge" | "pink" | "blue" | "gold" | "mint"
type Prim = {
	t: "part" | "ring",
	x: number, -- centre (fraction)
	y: number,
	w: number, -- taille (fraction)
	h: number,
	rot: number?, -- degrés
	r: number?, -- arrondi (UDim.Scale : 0.5 = capsule ou disque ; 0 = angles vifs)
	stroke: number?, -- anneau : épaisseur (fraction de la taille)
	fill: Shade?, -- anneau : fond (nil = transparent)
	shade: Shade, -- couleur de la pièce (anneau : couleur du trait)
}
type KindDef = { color: Color3, prims: { Prim } }

local EDGE = Color3.fromRGB(30, 25, 60)
local TINTS: { [string]: Color3 } = {
	pink = Color3.fromRGB(255, 130, 180),
	blue = Color3.fromRGB(88, 196, 255),
	gold = Theme.Colors.Gold,
	mint = Color3.fromRGB(120, 230, 170),
}

-- =============================================================================================
-- Primitives
-- =============================================================================================

-- Trait de (x1, y1) à (x2, y2), épaisseur t (bouts arrondis si round)
local function seg(
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	t: number,
	shade: Shade,
	round: boolean?
): Prim
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return {
		t = "part",
		x = (x1 + x2) / 2,
		y = (y1 + y2) / 2,
		w = len + (if round then t else 0),
		h = t,
		rot = math.deg(math.atan2(dy, dx)),
		r = if round then 0.5 else 0,
		shade = shade,
	}
end

local function disc(x: number, y: number, d: number, shade: Shade): Prim
	return { t = "part", x = x, y = y, w = d, h = d, r = 0.5, shade = shade }
end

local function box(x: number, y: number, w: number, h: number, shade: Shade, r: number?, rot: number?): Prim
	return { t = "part", x = x, y = y, w = w, h = h, r = r or 0, rot = rot, shade = shade }
end

local function ring(
	x: number,
	y: number,
	w: number,
	h: number,
	stroke: number,
	shade: Shade,
	fill: Shade?
): Prim
	return { t = "ring", x = x, y = y, w = w, h = h, r = 0.5, stroke = stroke, shade = shade, fill = fill }
end

-- Pentagramme de UI/Glyph.star (5 traits arrondis d'épaisseur 0,2, disque central de rayon 0,4 du
-- rayon, centre visuel un peu bas), dans le carré [x0 ; x0 + s] × [y0 ; y0 + s]
local STAR_THICKNESS = 0.2
local STAR_CORE = 0.4
local function star(x0: number, y0: number, s: number, shade: Shade): { Prim }
	local thick = s * STAR_THICKNESS
	local r = s / 2 - thick / 2
	local cx, cy = x0 + s / 2, y0 + s / 2 + s * 0.04
	local pts = {}
	for k = 0, 4 do
		local a = math.rad(-90 + 72 * k)
		pts[k] = { cx + r * math.cos(a), cy + r * math.sin(a) }
	end
	local out: { Prim } = {}
	for k = 0, 4 do
		local a, b = pts[k], pts[(k + 2) % 5]
		table.insert(out, seg(a[1], a[2], b[1], b[2], thick, shade, true))
	end
	-- disque central : un anneau plein (fond et trait de la même couleur) — une pièce de moins dans les
	-- toiles qui savent aussi dessiner un cadenas ou une boucle (même dessin que le disque de Glyph.star)
	local core = 2 * (s / 2) * STAR_CORE
	table.insert(out, ring(cx, cy, core, core, 0.01, shade, shade))
	return out
end

local function concat(...: { Prim }): { Prim }
	local out: { Prim } = {}
	for _, list in { ... } do
		for _, p in list do
			table.insert(out, p)
		end
	end
	return out
end

-- Tête de flèche en chevron (deux traits) au point (x, y), pointant dans la direction `deg` ; traits à
-- angles vifs si `sharp` (flèches entre deux valeurs : une toile sans UICorner, 2 instances de moins)
local function chevron(
	x: number,
	y: number,
	deg: number,
	len: number,
	t: number,
	shade: Shade,
	sharp: boolean?
): { Prim }
	local out: { Prim } = {}
	for _, side in { 135, -135 } do
		local a = math.rad(deg + side)
		table.insert(out, seg(x, y, x + len * math.cos(a), y + len * math.sin(a), t, shade, not sharp))
	end
	return out
end

-- =============================================================================================
-- Dessins (une liste de primitives par sorte ; l'ordre est l'ordre d'empilement)
-- =============================================================================================

local KINDS: { [string]: KindDef } = {
	-- états et repères (GDD §10.7.6)
	check = {
		color = Theme.Colors.Success,
		prims = {
			seg(0.16, 0.54, 0.4, 0.78, 0.16, "fill", true),
			seg(0.4, 0.78, 0.86, 0.26, 0.16, "fill", true),
		},
	},
	hourglass = {
		color = Theme.Colors.Warning,
		prims = {
			seg(0.3, 0.2, 0.7, 0.8, 0.14, "fill"),
			seg(0.7, 0.2, 0.3, 0.8, 0.14, "fill"),
			box(0.5, 0.14, 0.64, 0.12, "fill", 0.3),
			box(0.5, 0.86, 0.64, 0.12, "fill", 0.3),
		},
	},
	star = { color = Theme.Colors.Gold, prims = star(0.04, 0.04, 0.92, "fill") },
	lock = {
		color = Color3.fromRGB(200, 196, 225),
		prims = {
			ring(0.5, 0.36, 0.42, 0.5, 0.1, "fill"),
			box(0.5, 0.66, 0.66, 0.46, "fill", 0.2),
			box(0.5, 0.66, 0.1, 0.2, "dark", 0.5),
		},
	},
	loop = {
		color = Theme.Colors.Primary,
		prims = concat({ ring(0.5, 0.52, 0.7, 0.7, 0.12, "fill") }, chevron(0.5, 0.17, 0, 0.2, 0.12, "fill")),
	},
	retry = {
		color = Theme.Colors.Warning,
		prims = concat(
			{ ring(0.5, 0.52, 0.66, 0.66, 0.12, "fill") },
			chevron(0.17, 0.52, -90, 0.2, 0.12, "fill")
		),
	},
	infinity = {
		color = Theme.Colors.Primary,
		prims = { ring(0.31, 0.5, 0.42, 0.42, 0.12, "fill"), ring(0.69, 0.5, 0.42, 0.42, 0.12, "fill") },
	},
	heart = {
		color = TINTS.pink,
		prims = {
			box(0.5, 0.58, 0.5, 0.5, "fill", 0.08, 45),
			disc(0.323, 0.403, 0.5, "fill"),
			disc(0.677, 0.403, 0.5, "fill"),
		},
	},
	gear = {
		color = Color3.fromRGB(200, 196, 225),
		prims = {
			box(0.5, 0.5, 0.9, 0.2, "fill", 0.1),
			box(0.5, 0.5, 0.9, 0.2, "fill", 0.1, 45),
			box(0.5, 0.5, 0.9, 0.2, "fill", 0.1, 90),
			box(0.5, 0.5, 0.9, 0.2, "fill", 0.1, 135),
			disc(0.5, 0.5, 0.64, "fill"),
			disc(0.5, 0.5, 0.26, "dark"),
		},
	},
	arrowUp = {
		color = Theme.Colors.Text,
		prims = concat(
			{ seg(0.5, 0.88, 0.5, 0.2, 0.16, "fill") },
			chevron(0.5, 0.14, -90, 0.38, 0.16, "fill", true)
		),
	},
	arrowRight = {
		color = Theme.Colors.Text,
		prims = concat(
			{ seg(0.12, 0.5, 0.8, 0.5, 0.16, "fill") },
			chevron(0.86, 0.5, 0, 0.38, 0.16, "fill", true)
		),
	},
	drop = {
		color = Theme.Colors.Primary,
		prims = { box(0.5, 0.44, 0.42, 0.42, "fill", 0.08, 45), disc(0.5, 0.62, 0.58, "fill") },
	},
	coin = {
		color = Theme.Colors.Gold,
		prims = { ring(0.5, 0.5, 0.84, 0.84, 0.08, "dark", "fill"), box(0.5, 0.5, 0.16, 0.46, "light", 0.5) },
	},
	confetti = {
		color = Theme.Colors.Gold,
		prims = {
			box(0.3, 0.3, 0.26, 0.14, "pink", 0.2, 30),
			box(0.7, 0.28, 0.26, 0.14, "blue", 0.2, -25),
			box(0.34, 0.72, 0.26, 0.14, "gold", 0.2, -40),
			box(0.72, 0.68, 0.26, 0.14, "mint", 0.2, 50),
		},
	},
	prime = { color = Theme.Colors.Text, prims = { seg(0.62, 0.16, 0.42, 0.62, 0.16, "fill", true) } },

	-- familles et lignes de l'écran Améliorations (Config/Upgrades.icon)
	mat = {
		color = TINTS.pink,
		prims = {
			box(0.5, 0.64, 0.86, 0.36, "fill", 0.3),
			box(0.3, 0.64, 0.1, 0.36, "light"),
			box(0.7, 0.64, 0.1, 0.36, "light"),
			disc(0.5, 0.36, 0.3, "gold"),
		},
	},
	starMat = {
		color = Theme.Colors.Gold,
		prims = {
			box(0.5, 0.64, 0.86, 0.36, "fill", 0.3),
			box(0.3, 0.64, 0.1, 0.36, "light"),
			box(0.7, 0.64, 0.1, 0.36, "light"),
			box(0.5, 0.3, 0.26, 0.26, "light", 0.1, 45),
		},
	},
	decor = {
		color = TINTS.blue,
		prims = {
			seg(0.5, 0.66, 0.44, 0.94, 0.05, "dark"),
			disc(0.5, 0.4, 0.56, "fill"),
			box(0.5, 0.68, 0.1, 0.1, "fill", 0, 45),
			disc(0.38, 0.3, 0.12, "light"),
		},
	},
	pen = {
		color = Color3.fromRGB(214, 164, 112),
		prims = {
			box(0.24, 0.56, 0.14, 0.62, "fill", 0.2),
			box(0.76, 0.56, 0.14, 0.62, "fill", 0.2),
			box(0.5, 0.44, 0.86, 0.1, "dark"),
			box(0.5, 0.7, 0.86, 0.1, "dark"),
		},
	},
	bed = {
		color = Color3.fromRGB(160, 150, 255),
		prims = {
			box(0.18, 0.56, 0.12, 0.6, "dark", 0.3),
			box(0.56, 0.7, 0.8, 0.24, "fill", 0.3),
			box(0.36, 0.53, 0.26, 0.16, "light", 0.4),
		},
	},
	glove = {
		color = Color3.fromRGB(240, 236, 255),
		prims = {
			seg(0.28, 0.5, 0.16, 0.3, 0.17, "fill", true),
			disc(0.54, 0.48, 0.56, "fill"),
			box(0.54, 0.82, 0.48, 0.16, "pink", 0.3),
		},
	},
	monument = {
		color = Color3.fromRGB(205, 205, 228),
		prims = {
			box(0.5, 0.5, 0.26, 0.6, "fill", 0.15),
			box(0.5, 0.86, 0.6, 0.12, "dark", 0.2),
			box(0.5, 0.16, 0.18, 0.18, "gold", 0, 45),
		},
	},
	school = {
		color = Theme.Colors.Warning,
		prims = {
			box(0.5, 0.42, 0.5, 0.5, "light", 0.05, 45),
			box(0.5, 0.68, 0.56, 0.42, "fill", 0.08),
			box(0.5, 0.78, 0.14, 0.22, "dark", 0.2),
		},
	},
	helper = {
		color = TINTS.mint,
		prims = {
			box(0.5, 0.17, 0.14, 0.14, "light", 0, 45),
			disc(0.5, 0.58, 0.68, "fill"),
			box(0.38, 0.54, 0.08, 0.14, "dark", 0.5),
			box(0.62, 0.54, 0.08, 0.14, "dark", 0.5),
		},
	},
	gift = {
		color = Theme.Colors.Danger,
		prims = {
			box(0.5, 0.64, 0.7, 0.48, "fill", 0.1),
			box(0.5, 0.38, 0.8, 0.14, "light", 0.2),
			box(0.5, 0.58, 0.12, 0.62, "gold"),
			box(0.5, 0.22, 0.18, 0.18, "gold", 0, 45),
		},
	},
	magnet = {
		color = Theme.Colors.Danger,
		prims = {
			box(0.28, 0.46, 0.18, 0.52, "fill"),
			box(0.72, 0.46, 0.18, 0.52, "fill"),
			box(0.5, 0.72, 0.62, 0.18, "fill", 0.3),
			box(0.5, 0.24, 0.62, 0.1, "light"),
		},
	},
	streak = {
		color = Theme.Colors.Gold,
		prims = {
			seg(0.62, 0.08, 0.36, 0.52, 0.14, "fill", true),
			seg(0.36, 0.52, 0.66, 0.48, 0.14, "fill", true),
			seg(0.66, 0.48, 0.4, 0.92, 0.14, "fill", true),
		},
	},
	bag = {
		color = Color3.fromRGB(120, 120, 210),
		prims = {
			ring(0.5, 0.32, 0.36, 0.3, 0.08, "dark"),
			box(0.5, 0.64, 0.7, 0.52, "fill", 0.3),
			disc(0.62, 0.56, 0.16, "gold"),
		},
	},
	pot = {
		color = Color3.fromRGB(170, 130, 95),
		prims = {
			disc(0.5, 0.62, 0.66, "fill"),
			box(0.5, 0.32, 0.62, 0.1, "dark", 0.3),
			disc(0.5, 0.22, 0.12, "gold"),
		},
	},
	springboard = {
		color = TINTS.blue,
		prims = {
			ring(0.6, 0.68, 0.2, 0.26, 0.06, "dark"),
			box(0.5, 0.86, 0.8, 0.1, "dark", 0.3),
			seg(0.16, 0.58, 0.86, 0.36, 0.12, "fill", true),
		},
	},
	deco = {
		color = TINTS.pink,
		prims = {
			seg(0.5, 0.56, 0.5, 0.3, 0.06, "dark"),
			box(0.5, 0.74, 0.4, 0.34, "light", 0.2),
			disc(0.5, 0.26, 0.3, "fill"),
		},
	},
	palette = {
		color = Color3.fromRGB(250, 235, 215),
		prims = {
			disc(0.5, 0.52, 0.82, "fill"),
			disc(0.32, 0.42, 0.16, "pink"),
			disc(0.56, 0.32, 0.16, "blue"),
			disc(0.68, 0.56, 0.16, "gold"),
		},
	},
	saddle = {
		color = Color3.fromRGB(196, 128, 86),
		prims = {
			box(0.5, 0.74, 0.1, 0.3, "dark"),
			box(0.5, 0.5, 0.74, 0.36, "fill", 0.45),
			box(0.24, 0.36, 0.14, 0.2, "dark", 0.4),
		},
	},
	trail = {
		color = TINTS.pink,
		prims = {
			seg(0.14, 0.3, 0.62, 0.2, 0.1, "pink", true),
			seg(0.14, 0.52, 0.8, 0.44, 0.1, "blue", true),
			seg(0.14, 0.74, 0.68, 0.72, 0.1, "gold", true),
		},
	},
	emote = {
		color = Theme.Colors.Gold,
		prims = {
			disc(0.5, 0.5, 0.74, "fill"),
			box(0.38, 0.44, 0.08, 0.14, "dark", 0.5),
			box(0.62, 0.44, 0.08, 0.14, "dark", 0.5),
			box(0.5, 0.66, 0.28, 0.08, "dark", 0.5),
		},
	},
	pennant = {
		color = Theme.Colors.Gold,
		prims = {
			box(0.24, 0.52, 0.06, 0.82, "dark", 0.5),
			box(0.5, 0.3, 0.46, 0.28, "fill", 0.1),
			box(0.5, 0.62, 0.36, 0.22, "light", 0.1),
		},
	},
	title = {
		color = Color3.fromRGB(196, 120, 255),
		prims = {
			box(0.16, 0.6, 0.18, 0.22, "dark", 0.1, 20),
			box(0.84, 0.6, 0.18, 0.22, "dark", 0.1, -20),
			box(0.5, 0.5, 0.8, 0.3, "fill", 0.2),
		},
	},
	vat = {
		color = Color3.fromRGB(176, 128, 255),
		prims = {
			seg(0.62, 0.1, 0.5, 0.46, 0.07, "light", true),
			box(0.5, 0.62, 0.66, 0.54, "fill", 0.3),
			box(0.5, 0.34, 0.76, 0.1, "dark", 0.3),
			disc(0.4, 0.64, 0.14, "light"),
		},
	},
}

-- Sortes connues (ordre alphabétique)
Icons.KINDS = {} :: { string }
for kind in KINDS do
	table.insert(Icons.KINDS, kind)
end
table.sort(Icons.KINDS)
table.freeze(Icons.KINDS)

function Icons.has(kind: any): boolean
	return type(kind) == "string" and KINDS[kind] ~= nil
end

-- Couleur propre d'une sorte (blanc pour une sorte inconnue)
function Icons.color(kind: string): Color3
	local def = KINDS[kind]
	return if def then def.color else Theme.Colors.Text
end

-- Pièces et anneaux nécessaires pour dessiner chacune de ces sortes sur une même toile, et si une
-- pièce doit pouvoir être arrondie (sinon : pièces sans UICorner)
local function poolOf(kinds: { string }): (number, number, boolean)
	local parts, rings, rounded = 0, 0, false
	for _, kind in kinds do
		local def = KINDS[kind]
		if def then
			local p, r = 0, 0
			for _, prim in def.prims do
				if prim.t == "ring" then
					r += 1
				else
					p += 1
					if (prim.r or 0) > 0 then
						rounded = true
					end
				end
			end
			parts = math.max(parts, p)
			rings = math.max(rings, r)
		end
	end
	return parts, rings, rounded
end

-- Instances d'une toile qui sait dessiner ces sortes (cadre + pièces + anneaux)
function Icons.cost(kinds: { string }): number
	local parts, rings, rounded = poolOf(kinds)
	return 1 + (if rounded then 2 else 1) * parts + 3 * rings
end

-- =============================================================================================
-- Toiles
-- =============================================================================================

type CanvasState = {
	size: number,
	parts: { Frame },
	rings: { Frame },
	rounded: boolean, -- pièces arrondissables (UICorner)
	kind: string?,
	color: Color3?,
}
local canvases: { [Instance]: CanvasState } = setmetatable({}, { __mode = "k" }) :: any

local function shadeOf(shade: Shade?, color: Color3, recolored: boolean): Color3
	if shade == nil or shade == "fill" then
		return color
	elseif shade == "dark" then
		return color:Lerp(Color3.new(0, 0, 0), 0.45)
	elseif shade == "light" then
		return color:Lerp(Color3.new(1, 1, 1), 0.55)
	elseif shade == "edge" then
		return EDGE
	end
	-- teinte propre (confettis, palette, traînée) ; recolorée : une nuance de la couleur demandée
	if recolored then
		return color:Lerp(Color3.new(1, 1, 1), 0.25)
	end
	return TINTS[shade] or color
end

local function newPart(holder: Frame, name: string, ring: boolean, rounded: boolean): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Active = false
	f.Selectable = false
	f.Visible = false
	if ring or rounded then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 0)
		corner.Parent = f
	end
	if ring then
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 0
		stroke.Parent = f
	end
	f.Parent = holder
	return f
end

-- Toile de `size` px TV qui sait dessiner chacune des sortes `kinds` (rien de dessiné au départ)
function Icons.canvas(parent: Instance?, size: number, kinds: { string }, name: string?): Frame
	local s = if type(size) == "number" and size == size and size > 0 then size else 48
	local holder = Instance.new("Frame")
	holder.Name = name or "Icon"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(s, s)
	holder.Active = false
	holder.Selectable = false
	holder:SetAttribute("Icon", "")
	local nParts, nRings, rounded = poolOf(kinds)
	local state: CanvasState = { size = s, parts = {}, rings = {}, rounded = rounded }
	for i = 1, nParts do
		table.insert(state.parts, newPart(holder, "P" .. i, false, rounded))
	end
	for i = 1, nRings do
		table.insert(state.rings, newPart(holder, "R" .. i, true, true))
	end
	canvases[holder] = state
	if parent then
		holder.Parent = parent
	end
	return holder
end

-- Dessine `kind` sur la toile (couleur propre de la sorte si `color` est nil) ; nil ou une sorte que la
-- toile ne sait pas dessiner : tout caché. Aucune instance créée.
function Icons.draw(canvas: Frame, kind: string?, color: Color3?)
	local state = canvases[canvas]
	if state == nil then
		return
	end
	local def = if kind then KINDS[kind] else nil
	local usedParts, usedRings = 0, 0
	if def then
		local nParts, nRings, rounded = poolOf({ kind :: string })
		if nParts > #state.parts or nRings > #state.rings or (rounded and not state.rounded) then
			def = nil
		end
	end
	if def then
		local base = color or def.color
		local recolored = color ~= nil
		local z = canvas.ZIndex
		for order, prim in def.prims do
			local f: Frame
			if prim.t == "ring" then
				usedRings += 1
				f = state.rings[usedRings]
			else
				usedParts += 1
				f = state.parts[usedParts]
			end
			f.Position = UDim2.fromScale(prim.x, prim.y)
			f.Size = UDim2.fromScale(prim.w, prim.h)
			f.Rotation = prim.rot or 0
			f.ZIndex = z + order
			local corner = f:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(prim.r or 0, 0)
			end
			if prim.t == "ring" then
				local stroke = f:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = shadeOf(prim.shade, base, recolored)
					stroke.Thickness = math.max(1, (prim.stroke or 0.1) * state.size)
				end
				if prim.fill then
					f.BackgroundColor3 = shadeOf(prim.fill, base, recolored)
					f.BackgroundTransparency = 0
				else
					f.BackgroundTransparency = 1
				end
			else
				f.BackgroundColor3 = shadeOf(prim.shade, base, recolored)
				f.BackgroundTransparency = 0
			end
			f.Visible = true
		end
		state.kind = kind
		state.color = color
	else
		state.kind = nil
		state.color = nil
	end
	for i = usedParts + 1, #state.parts do
		state.parts[i].Visible = false
	end
	for i = usedRings + 1, #state.rings do
		state.rings[i].Visible = false
	end
	local shown = state.kind or ""
	if canvas:GetAttribute("Icon") ~= shown then
		canvas:SetAttribute("Icon", shown)
	end
end

-- Recolore le dessin courant d'une toile (ou d'une étoile de Glyph.star)
function Icons.paint(icon: Frame, color: Color3)
	local state = canvases[icon]
	if state ~= nil then
		Icons.draw(icon, state.kind, color)
		return
	end
	if icon:GetAttribute("Icon") == "star" then
		Glyph.paintStar(icon, color)
	end
end

-- Sorte dessinée sur une toile (nil : rien)
function Icons.kindOf(icon: Instance): string?
	local state = canvases[icon]
	if state then
		return state.kind
	end
	local attr = icon:GetAttribute("Icon")
	return if type(attr) == "string" and attr ~= "" then attr else nil
end

-- Icône seule de `size` px TV (l'étoile : UI/Glyph.star, avec son liseré)
function Icons.new(kind: string, size: number, color: Color3?, parent: Instance?): Frame
	if kind == "star" then
		return Glyph.star(parent, size, color)
	end
	local c = Icons.canvas(nil, size, { kind })
	Icons.draw(c, kind, color)
	if parent then
		c.Parent = parent
	end
	return c
end

return Icons
