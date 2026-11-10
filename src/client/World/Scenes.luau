--!strict
-- Scenes (lot B5, étape 2 ; GDD §5.6 « Des squishies qui ont du caractère », §11.5 « Trois versions de
-- chaque effet », Annexe B.7 ; plan B5 D4) : les 18 saynètes des 6 personnalités et les 5 tours appris,
-- en données pures (aucune instance, aucun service : testable sans monde).
--
--   Scenes.sample(id, t, D, ctx) → dx, dy, dz, yaw, pitch, roll, pivot
--       pose de la saynète `id` à `t` secondes de son début, pour un corps de diamètre `D` (studs) :
--       un déplacement (studs) et trois angles (radians) à composer sur la pose de repos, dans SON
--       repère (−Z = devant, vers la caméra ; +X = sa droite ; lacet positif = vers sa gauche ;
--       tangage NÉGATIF = penché en avant ; roulis = penché de côté) ; pivot 0 = la rotation tourne
--       autour du dessous du corps (il reste posé), 1 = autour de son centre (salto). Hors de
--       [0 ; durée], saynète inconnue ou valeurs illisibles : tout à 0 (la pose de repos).
--   Scenes.duration(id)        durée en secondes (0 : inconnue)
--   Scenes.of(perso)           les 3 saynètes d'une personnalité (Config/Species.Personalities)
--   Scenes.face(id, t)         visage de la saynète à `t` (Config/Visuals.Faces), nil = « happy »
--   Scenes.adorn(id)           ornement : sorte ("hearts" | "stars" | "sparks" | "z" | "what"), nombre
--                              de particules (0 pour une étiquette), début et fin en secondes ; nil sinon
--   Scenes.LIST, Scenes.TRICKS identifiants des 18 saynètes, des 5 tours (ordre des seuils du GDD)
--
-- ctx (table réutilisée par l'appelant, aucun champ obligatoire) :
--   reduced  Mouvement réduit : amplitudes × 0,5, aucune rotation au-delà de 45° (les tours complets
--            deviennent un balancement) ;
--   look     lacet (rad) vers le point regardé (le joueur, le voisin, la dernière décoration) ;
--   home     lacet (rad) de la direction libre, vers la place : les saynètes qui avancent (Tour de
--            place, Défilé) partent de ce côté, donc s'éloignent le moins possible de la place.
--
-- Règles (GDD §5.6) : une saynète ne touche JAMAIS à Size (« s'aplatir » = s'enfoncer et pencher) ;
-- elle part de la pose de repos et y revient (à un tour complet près) ; son déplacement à plat reste
-- petit (1,5 stud au plus) et World/Personality borne de toute façon l'écart à la place à 2 studs.

local Scenes = {}

export type Ctx = { reduced: boolean?, look: number?, home: number? }

local PI = math.pi
local TAU = 2 * math.pi
local DEG = math.pi / 180
local MAX_REDUCED = math.pi / 4 -- Mouvement réduit : aucune rotation au-delà de 45°

-- =============================================================================================
-- Courbes
-- =============================================================================================

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

-- 0 → 1, départ et arrivée en douceur
local function smooth(u: number): number
	local x = clamp01(u)
	return x * x * (3 - 2 * x)
end

-- 0 → 1 → 0 (demi-sinus)
local function bump(u: number): number
	return math.sin(PI * clamp01(u))
end

-- 0 → 1 → 0 (parabole d'un saut)
local function arc(u: number): number
	local x = clamp01(u)
	return 4 * x * (1 - x)
end

-- Monte en `a` secondes, tient, redescend en `b` secondes ; 0 hors de ]0 ; T[
local function plateau(t: number, T: number, a: number, b: number): number
	if t <= 0 or t >= T then
		return 0
	end
	if t < a then
		return smooth(t / a)
	end
	if t > T - b then
		return smooth((T - t) / b)
	end
	return 1
end

-- =============================================================================================
-- Saynètes : fn(t, T, D, k, reduced, look, home) → dx, dy, dz, yaw, pitch, roll, pivot
-- (k = 1, ou 0,5 en Mouvement réduit)
-- =============================================================================================

type Fn = (
	number,
	number,
	number,
	number,
	boolean,
	number,
	number
) -> (number, number, number, number, number, number, number)

-- Curieux 1, « Coucou » (1,5 s) : se penche vers le joueur
local function hello(t: number, T: number, D: number, k: number, _reduced: boolean, look: number)
	local e = plateau(t, T, 0.4, 0.4)
	local yaw = look * e
	local s = 0.15 * D * k * e
	return -s * math.sin(yaw), 0, -s * math.cos(yaw), yaw, -22 * DEG * k * e, 0, 0
end

-- Curieux 2, « Tour de place » (3 s) : petit cercle de 1,5 stud de diamètre, du côté libre
local function circle(
	t: number,
	T: number,
	D: number,
	k: number,
	reduced: boolean,
	_look: number,
	home: number
)
	local u = t / T
	local a = TAU * smooth(u)
	local r = 0.75 * k
	-- e2 : vers le centre du cercle (côté libre) ; e1 : départ, un quart de tour avant e2
	local e1x, e1z = math.cos(home), -math.sin(home)
	local e2x, e2z = -math.sin(home), -math.cos(home)
	local s, c = math.sin(a), 1 - math.cos(a)
	local dx = r * (s * e1x + c * e2x)
	local dz = r * (s * e1z + c * e2z)
	local dy = 0.1 * D * k * math.abs(math.sin(6 * PI * u))
	if reduced then
		return dx, dy, dz, 0, 0, 0, 0
	end
	-- regarde où il va : un tour complet, raccordé à la pose de repos aux deux bouts
	return dx, dy, dz, a + (home - PI / 2) * plateau(t, T, 0.45, 0.45), 0, 0, 0
end

-- Curieux 3, « C'est quoi ? » (2 s) : regarde la dernière décoration construite, tête penchée
local function what(t: number, T: number, _D: number, k: number, _reduced: boolean, look: number)
	local e = plateau(t, T, 0.35, 0.35)
	return 0, 0, 0, look * e, 0, 9 * DEG * k * e, 0
end

-- Dormeur 1, « Bâillement » (2 s) : s'étire en arrière
local function yawn(t: number, T: number, D: number, k: number)
	local e = bump(t / T)
	return 0, 0.1 * D * k * e, 0, 0, 14 * DEG * k * e, 0, 0
end

-- Dormeur 2, « Mini-sieste » (3 s) : s'affaisse, penche, respire
local function nap(t: number, T: number, D: number, k: number)
	local e = plateau(t, T, 0.6, 0.5)
	local breath = 0.02 * D * math.sin(TAU * 0.6 * t)
	return 0, (-0.1 * D + breath) * k * e, 0, 0, 0, 16 * DEG * k * e, 0
end

-- Dormeur 3, « Réveil en sursaut » (1 s) : petit bond et frisson
local function startle(t: number, T: number, D: number, k: number)
	local u = t / T
	local hop = if u < 0.5 then arc(u / 0.5) else 0
	local shake = math.sin(TAU * 7 * t) * (1 - u) * plateau(t, T, 0.05, 0.3)
	return 0, 0.35 * D * k * hop, 0, 0, 0, 6 * DEG * k * shake, 0
end

-- Rebondi 1, « Triple saut » (1,8 s) : trois sauts de 1,5 stud
local function tripleHop(t: number, T: number, _D: number, k: number)
	local u = clamp01(t / T) * 3
	return 0, 1.5 * k * arc(u - math.floor(u)), 0, 0, 0, 0, 0
end

-- Rebondi 2, « Toupie » (1 s) : 2 tours (Mouvement réduit : un balancement de 45°)
local function twirl(t: number, T: number, D: number, k: number, reduced: boolean)
	local u = t / T
	if reduced then
		return 0, 0.16 * D * k * bump(u), 0, MAX_REDUCED * math.sin(TAU * u), 0, 0, 0
	end
	return 0, 0.16 * D * bump(u), 0, 2 * TAU * smooth(u), 0, 0, 0
end

-- Rebondi 3, « Plat ! » (1,5 s) : saut de 3 studs, atterrissage penché de 20°
local function flat(t: number, T: number, D: number, k: number)
	local JUMP, HOLD = 0.9, 1.2
	local tilt = -20 * DEG * k
	if t < JUMP then
		local u = t / JUMP
		return 0, 3 * k * arc(u), 0, 0, tilt * smooth(u), 0, 0
	elseif t < HOLD then
		return 0, -0.08 * D * k * smooth((t - JUMP) / 0.1), 0, 0, tilt, 0, 0
	end
	local e = 1 - smooth((t - HOLD) / (T - HOLD))
	return 0, -0.08 * D * k * e, 0, 0, tilt * e, 0, 0
end

-- Câlin 1, « Cœurs » (2 s) : se trémousse (3 cœurs si le joueur est à 8 studs ou moins)
local function hearts(t: number, T: number, D: number, k: number)
	local e = plateau(t, T, 0.25, 0.25)
	local w = TAU * 1.5 * t
	return 0, 0.14 * D * k * e * math.abs(math.sin(w)), 0, 0, 0, 8 * DEG * k * e * math.sin(w), 0
end

-- Câlin 2, « Bisou au voisin » (2 s) : se tourne vers le voisin et se penche vers lui
local function kiss(t: number, T: number, D: number, k: number, _reduced: boolean, look: number)
	local yaw = look * plateau(t, T, 0.45, 0.45)
	local b = bump((t - 0.6) / 0.8)
	local s = math.min(0.25 * D, 0.6) * k * b
	return -s * math.sin(yaw), 0, -s * math.cos(yaw), yaw, -12 * DEG * k * b, 0, 0
end

-- Câlin 3, « Dandinement » (2 s) : ± 10° à 2 Hz
local function waddle(t: number, T: number, _D: number, k: number)
	return 0, 0, 0, 0, 0, 10 * DEG * k * plateau(t, T, 0.2, 0.2) * math.sin(TAU * 2 * t), 0
end

-- Farceur 1, « Langue » (1,5 s) : tête penchée, clin d'œil
local function tongue(t: number, T: number, D: number, k: number)
	local e = plateau(t, T, 0.25, 0.3)
	local bob = 0.08 * D * k * e * math.abs(math.sin(TAU * 2 * t))
	return 0, bob, 0, 0, -6 * DEG * k * e, 14 * DEG * k * e, 0
end

-- Farceur 2, « Faux éternuement » (2,5 s) : inspire… rien, puis rit (jamais le texte du Rush)
local function fakeSneeze(t: number, T: number, D: number, k: number)
	local IN, HOLD, DROP = 1.3, 1.6, 1.75
	local rise, back = 0.12 * D * k, 18 * DEG * k
	if t < IN then
		local s = smooth(t / IN)
		return 0, rise * s, 0, 0, back * s, 0, 0
	elseif t < HOLD then
		return 0, rise, 0, 0, back, 0, 0
	elseif t < DROP then
		local s = 1 - smooth((t - HOLD) / (DROP - HOLD))
		return 0, rise * s, 0, 0, back * s, 0, 0
	end
	local tau = t - DROP
	local fade = plateau(tau, T - DROP, 0.05, 0.25)
	local w = TAU * 4 * tau
	return 0, 0.1 * D * k * fade * math.abs(math.sin(w)), 0, 0, 0, 5 * DEG * k * fade * math.sin(w), 0
end

-- Farceur 3, « Cache-cache » (2 s) : s'aplatit (s'enfonce) puis ressort d'un bond
local function hide(t: number, T: number, D: number, k: number)
	local DOWN, HOLD, UP = 0.4, 1.2, 1.6
	local depth, tilt = 0.7 * D * k, -8 * DEG * k
	if t < DOWN then
		local s = smooth(t / DOWN)
		return 0, -depth * s, 0, 0, tilt * s, 0, 0
	elseif t < HOLD then
		return 0, -depth, 0, 0, tilt, 0, 0
	elseif t < UP then
		local s = smooth((t - HOLD) / (UP - HOLD))
		return 0, -depth * (1 - s) + 0.5 * k * arc(s), 0, 0, tilt * (1 - s), 0, 0
	end
	return 0, 0.15 * k * arc((t - UP) / (T - UP)), 0, 0, 0, 0, 0
end

-- Fier 1, « Pose » (2 s) : petit saut sur place, puis torse bombé (2 étoiles)
local function proudPose(t: number, T: number, D: number, k: number)
	local HOP = 0.5
	if t < HOP then
		return 0, 0.8 * k * arc(t / HOP), 0, 0, 0, 0, 0
	end
	local e = plateau(t - HOP, T - HOP, 0.2, 0.3)
	return 0, 0.06 * D * k * e, 0, 0, 10 * DEG * k * e, 0, 0
end

-- Fier 2, « Révérence » (1,5 s)
local function bow(t: number, T: number, D: number, k: number)
	local e = bump(t / T)
	return 0, -0.05 * D * k * e, 0, 0, -35 * DEG * k * e, 0, 0
end

-- Fier 3, « Défilé » (3 s) : avance de 1,5 stud du côté libre, demi-tour, revient
local function parade(
	t: number,
	T: number,
	D: number,
	k: number,
	reduced: boolean,
	_look: number,
	home: number
)
	local A, B, C, E = 0.3, 1.3, 1.7, 2.7
	local dist = 1.5 * k
	local s, walk = 0, 0
	if t >= A and t < B then
		s = dist * smooth((t - A) / (B - A))
		walk = plateau(t - A, B - A, 0.1, 0.1)
	elseif t >= B and t < C then
		s = dist
	elseif t >= C and t < E then
		s = dist * (1 - smooth((t - C) / (E - C)))
		walk = plateau(t - C, E - C, 0.1, 0.1)
	end
	local dy = 0.08 * D * k * walk * math.abs(math.sin(TAU * 3 * t))
	local dx, dz = -s * math.sin(home), -s * math.cos(home)
	if reduced then
		return dx, dy, dz, 0, 0, 0, 0
	end
	local back = home + PI
	local yaw: number
	if t < A then
		yaw = home * smooth(t / A)
	elseif t < B then
		yaw = home
	elseif t < C then
		yaw = home + PI * smooth((t - B) / (C - B))
	elseif t < E then
		yaw = back
	else
		-- retour à la pose de repos par le plus court (le tour complet le plus proche)
		local final = TAU * math.floor(back / TAU + 0.5)
		yaw = back + (final - back) * smooth((t - E) / (T - E))
	end
	return dx, dy, dz, yaw, 0, 0, 0
end

-- Tour 1, « Coucou » / Peekaboo (2 s) : se cache, ressort d'un bond, tête penchée
local function peekaboo(t: number, T: number, D: number, k: number)
	local DOWN, HOLD, UP, STAY = 0.35, 0.75, 1.15, 1.65
	local depth, tilt = 0.75 * D * k, 18 * DEG * k
	if t < DOWN then
		return 0, -depth * smooth(t / DOWN), 0, 0, 0, 0, 0
	elseif t < HOLD then
		return 0, -depth, 0, 0, 0, 0, 0
	elseif t < UP then
		local s = smooth((t - HOLD) / (UP - HOLD))
		return 0, -depth * (1 - s) + 0.6 * k * arc(s), 0, 0, 0, tilt * s, 0
	elseif t < STAY then
		return 0, 0.1 * D * k * math.abs(math.sin(TAU * 2 * (t - UP))), 0, 0, 0, tilt, 0
	end
	return 0, 0, 0, 0, 0, tilt * (1 - smooth((t - STAY) / (T - STAY))), 0
end

-- Tour 2, « Toupie » / Spin (1,5 s) : 3 tours en s'élevant (Mouvement réduit : balancement)
local function spin(t: number, T: number, _D: number, _k: number, reduced: boolean)
	local u = t / T
	if reduced then
		return 0, 0.3 * bump(u), 0, MAX_REDUCED * math.sin(TAU * 2 * u), 0, 0, 0
	end
	return 0, 0.6 * bump(u), 0, 3 * TAU * smooth(u), 0, 0, 0
end

-- Tour 3, « Salto » / Flip (1,2 s) : saut de 2,5 studs et tour complet en arrière, autour du centre
local function flip(t: number, T: number, _D: number, _k: number, reduced: boolean)
	local u = t / T
	if reduced then
		return 0, 1.25 * arc(u), 0, 0, MAX_REDUCED * bump(u), 0, 1
	end
	return 0, 2.5 * arc(u), 0, 0, TAU * smooth(u), 0, 1
end

-- Tour 4, « Danse » / Dance (3 s) : pas de côté, balancement, petits sauts
local function dance(t: number, T: number, _D: number, k: number)
	local e = plateau(t, T, 0.3, 0.3)
	local w = TAU * t
	return 0.5 * k * e * math.sin(w),
		0.2 * k * e * math.abs(math.sin(2 * w)),
		0,
		30 * DEG * k * e * math.sin(w / 2),
		0,
		-12 * DEG * k * e * math.sin(w),
		0
end

-- Tour 5, « Feu d'artifice » / Fireworks (3 s) : s'accroupit, grand saut en vrille, gerbe au sommet
local function fireworks(t: number, T: number, D: number, k: number, reduced: boolean)
	local CROUCH, LAND, SETTLE = 0.5, 1.7, 2.2
	if t < CROUCH then
		return 0, -0.25 * D * k * bump(t / CROUCH), 0, 0, 0, 0, 0
	elseif t < LAND then
		local u = (t - CROUCH) / (LAND - CROUCH)
		return 0, 3 * k * arc(u), 0, if reduced then 0 else 2 * TAU * smooth(u), 0, 0, 0
	elseif t < SETTLE then
		return 0, 0.3 * k * arc((t - LAND) / (SETTLE - LAND)), 0, 0, 0, 0, 0
	end
	local e = plateau(t - SETTLE, T - SETTLE, 0.15, 0.3)
	return 0, 0.05 * D * k * e, 0, 0, 8 * DEG * k * e, 0, 0
end

-- =============================================================================================
-- Table des saynètes (durées du GDD §5.6)
-- =============================================================================================

type Adorn = { kind: string, n: number, from: number, to: number }
type Def = {
	duration: number,
	fn: Fn,
	face: string?, -- visage du début (nil : « happy »)
	faceAt: number?, -- instant où `face2` le remplace
	face2: string?,
	adorn: Adorn?,
}

local DEFS: { [string]: Def } = {
	-- Curieux / Curious
	hello = { duration = 1.5, fn = hello :: any },
	circle = { duration = 3, fn = circle :: any },
	what = {
		duration = 2,
		fn = what :: any,
		adorn = { kind = "what", n = 0, from = 0.3, to = 1.8 },
	},
	-- Dormeur / Sleepy
	yawn = { duration = 2, fn = yawn :: any, face = "sleepy" },
	nap = {
		duration = 3,
		fn = nap :: any,
		face = "sleepy",
		adorn = { kind = "z", n = 0, from = 0.4, to = 2.8 },
	},
	startle = { duration = 1, fn = startle :: any, face = "surprised" },
	-- Rebondi / Bouncy
	tripleHop = { duration = 1.8, fn = tripleHop :: any, face = "delighted" },
	twirl = { duration = 1, fn = twirl :: any },
	flat = { duration = 1.5, fn = flat :: any, face = "surprised", faceAt = 0.9, face2 = "delighted" },
	-- Câlin / Cuddly
	hearts = {
		duration = 2,
		fn = hearts :: any,
		face = "delighted",
		adorn = { kind = "hearts", n = 3, from = 0.3, to = 0.3 },
	},
	kiss = {
		duration = 2,
		fn = kiss :: any,
		face = "delighted",
		adorn = { kind = "hearts", n = 1, from = 1, to = 1 },
	},
	waddle = { duration = 2, fn = waddle :: any },
	-- Farceur / Prankster
	tongue = { duration = 1.5, fn = tongue :: any, face = "delighted" },
	fakeSneeze = {
		duration = 2.5,
		fn = fakeSneeze :: any,
		face = "surprised",
		faceAt = 1.75,
		face2 = "delighted",
	},
	hide = { duration = 2, fn = hide :: any },
	-- Fier / Proud
	pose = {
		duration = 2,
		fn = proudPose :: any,
		face = "starry",
		adorn = { kind = "stars", n = 2, from = 0.5, to = 0.5 },
	},
	bow = { duration = 1.5, fn = bow :: any },
	parade = { duration = 3, fn = parade :: any },
	-- Tours appris (GDD §5.6, Annexe B.7)
	peekaboo = { duration = 2, fn = peekaboo :: any, faceAt = 0.75, face2 = "surprised" },
	spin = { duration = 1.5, fn = spin :: any },
	flip = { duration = 1.2, fn = flip :: any, face = "delighted" },
	dance = { duration = 3, fn = dance :: any, face = "delighted" },
	fireworks = {
		duration = 3,
		fn = fireworks :: any,
		face = "starry",
		adorn = { kind = "sparks", n = 12, from = 1.1, to = 1.1 },
	},
}

-- Les 3 saynètes de chaque personnalité, dans l'ordre du tableau du GDD
local BY_PERSO: { [string]: { string } } = {
	curious = table.freeze({ "hello", "circle", "what" }),
	sleepy = table.freeze({ "yawn", "nap", "startle" }),
	bouncy = table.freeze({ "tripleHop", "twirl", "flat" }),
	cuddly = table.freeze({ "hearts", "kiss", "waddle" }),
	prankster = table.freeze({ "tongue", "fakeSneeze", "hide" }),
	proud = table.freeze({ "pose", "bow", "parade" }),
}

local EMPTY: { string } = table.freeze({})

-- Les 18 saynètes (6 personnalités × 3) et les 5 tours appris (ordre des seuils : 100, 1 200, 1e6,
-- 1e9, 1e12 ; mêmes identifiants que les clés « trick.<id> » de Config/Quests.Mastery.Tricks)
Scenes.LIST = table.freeze({
	"hello",
	"circle",
	"what",
	"yawn",
	"nap",
	"startle",
	"tripleHop",
	"twirl",
	"flat",
	"hearts",
	"kiss",
	"waddle",
	"tongue",
	"fakeSneeze",
	"hide",
	"pose",
	"bow",
	"parade",
})
Scenes.TRICKS = table.freeze({ "peekaboo", "spin", "flip", "dance", "fireworks" })
Scenes.MAX_REDUCED_ANGLE = MAX_REDUCED

-- =============================================================================================
-- API
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Angle lisible ramené dans ]−π ; π] (0 sinon)
local function angle(x: any): number
	if not finite(x) then
		return 0
	end
	local a = (x :: number) % TAU
	return if a > PI then a - TAU else a
end

-- Durée d'une saynète ou d'un tour (0 : inconnu)
function Scenes.duration(id: string): number
	local def = if type(id) == "string" then DEFS[id] else nil
	return if def then def.duration else 0
end

-- Les 3 saynètes d'une personnalité (liste vide : personnalité inconnue)
function Scenes.of(perso: string): { string }
	return (if type(perso) == "string" then BY_PERSO[perso] else nil) or EMPTY
end

-- Visage de la saynète à `t` secondes (nil : le visage de repos)
function Scenes.face(id: string, t: number): string?
	local def = if type(id) == "string" then DEFS[id] else nil
	if def == nil then
		return nil
	end
	local at = def.faceAt
	if at and finite(t) and t >= at then
		return def.face2
	end
	return def.face
end

-- Ornement de la saynète : sorte, nombre de particules, début et fin (s) ; nil sinon
function Scenes.adorn(id: string): (string?, number, number, number)
	local def = if type(id) == "string" then DEFS[id] else nil
	local a = if def then def.adorn else nil
	if a == nil then
		return nil, 0, 0, 0
	end
	return a.kind, a.n, a.from, a.to
end

-- Pose de la saynète `id` à `t` secondes de son début (voir l'en-tête)
function Scenes.sample(
	id: string,
	t: number,
	D: number,
	ctx: Ctx?
): (number, number, number, number, number, number, number)
	local def = if type(id) == "string" then DEFS[id] else nil
	if def == nil or not finite(t) then
		return 0, 0, 0, 0, 0, 0, 0
	end
	local T = def.duration
	if t <= 0 or t >= T then
		return 0, 0, 0, 0, 0, 0, 0
	end
	local d = if finite(D) then math.clamp(D, 0.1, 100) else 2
	local c: any = if type(ctx) == "table" then ctx else nil
	local reduced = c ~= nil and c.reduced == true
	local look = angle(if c then c.look else nil)
	local home = angle(if c then c.home else nil)
	if reduced then
		look = math.clamp(look, -MAX_REDUCED, MAX_REDUCED)
	end
	local dx, dy, dz, yaw, pitch, roll, pivot =
		def.fn(t, T, d, if reduced then 0.5 else 1, reduced, look, home)
	if reduced then
		yaw = math.clamp(yaw, -MAX_REDUCED, MAX_REDUCED)
		pitch = math.clamp(pitch, -MAX_REDUCED, MAX_REDUCED)
		roll = math.clamp(roll, -MAX_REDUCED, MAX_REDUCED)
	end
	return dx, dy, dz, yaw, pitch, roll, pivot
end

return Scenes
