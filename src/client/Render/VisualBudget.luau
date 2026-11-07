--!strict
-- VisualBudget (lot B4, étape 3 ; docs/04 §27.7 ; GDD v2.0 §11.5 « Budget visuel en direct », §12.9 ;
-- décision D13 du plan B4). Grand livre des décors v2.0 dessinés par le client :
--   * chaque système déclare ses pièces, particules et lumières (declare, nombres du tableau
--     « Budgets ajoutés » du GDD §11.5 gardés ici en constantes, aucune Config) ; take / release
--     réservent et rendent ; l'usage ne dépasse JAMAIS ce qui est déclaré (un take qui dépasserait
--     est refusé : l'appelant dégrade) ;
--   * allocate : répartit le budget d'un système entre les ranchs dans l'ordre fixe de dégradation
--     (order : mon ranch d'abord, puis le ranch courant, ses 2 voisins, puis les autres du plus proche
--     au plus lointain) ; un ranch qui ne tient pas passe en détail réduit, puis à rien, et tous ceux
--     qui le suivent aussi : les ranchs les plus lointains se dégradent en premier, le mien en dernier ;
--   * un dépassement n'est jamais une erreur : un compteur (exceeded) et, au plus une fois par 60 s et
--     5 fois par séance, ClientMetric("visualBudget", n) par Widgets.send (le seau partagé de 1 / 5 s ;
--     n = pièces au-delà du budget, bornées à 1 … 1000). Interrupteurs coupés : aucun système n'est
--     déclaré (les décors v2.0 déclarent au premier ranch v2), donc rien n'est jamais envoyé.
-- Jamais d'erreur : une entrée illisible (nom, nombre, ordre, demandes) est ignorée sans trace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent

local VisualBudget = {}

export type Limits = { parts: number, particles: number, lights: number }
export type Kind = "parts" | "particles" | "lights"
export type Want = { full: number, reduced: number }
export type SystemStats = {
	parts: number, -- pièces déclarées
	particles: number,
	lights: number,
	used: number, -- pièces réservées
	usedParticles: number,
	usedLights: number,
	peak: number, -- plus haut usage de pièces vu
	refused: number, -- réservations refusées (dépassements)
}

-- Budgets ajoutés (GDD §11.5, pire cas sur un client ; ranch courant + 2 voisins en détail complet)
VisualBudget.LIMITS = table.freeze({
	-- Tapis, coussins, lit : (20 + 24 + 10) × 3 ; étincelles du Tapis doré ≤ 6
	tapis = table.freeze({ parts = 162, particles = 6, lights = 0 }),
	-- changements par Record R (Cuve, Bassin, lampions, portail, geyser) : 40 × 3 ; étincelles des 5
	-- buses de MA Cuve (une par buse et par naissance mutée, lot B4 étape 4)
	record = table.freeze({ parts = 120, particles = 5, lights = 0 }),
	-- 6 paliers : 3 × 96 + 13 × 9
	tiers = table.freeze({ parts = 405, particles = 0, lights = 0 }),
	-- socles de souvenir : 18 × 2 × 3
	plinths = table.freeze({ parts = 108, particles = 0, lights = 0 }),
	-- Monuments : 200 + 120 + 130
	monuments = table.freeze({ parts = 450, particles = 0, lights = 0 }),
	-- maisonnette des Plopettes (part de B4 de « Plopettes et maisonnette ») : 6 × 3
	house = table.freeze({ parts = 18, particles = 0, lights = 0 }),
	-- halo et ciel : 80 près + 2 × 10 + 13 × 3
	sky = table.freeze({ parts = 139, particles = 0, lights = 0 }),
	-- Déco perso : 3 × 120 + 13 × 4
	decoPerso = table.freeze({ parts = 412, particles = 0, lights = 0 }),
	-- Observatoire et kiosque (D10)
	world = table.freeze({ parts = 40, particles = 0, lights = 0 }),
	-- lot B4, étape 5 : halo (D16), 5 gouttes au plus par joueur (16 joueurs), compté à part du ciel : il
	-- suit le personnage, pas le ranch (B4-55)
	halo = table.freeze({ parts = 16 * 5, particles = 0, lights = 0 }),
	-- lot B4, étape 5 : Prairie v2 (D9), qui remplace la Prairie du serveur cachée sur ce client
	meadow = table.freeze({ parts = 40, particles = 0, lights = 0 }),
	-- tas de pièces du Pot (8) et anneau de l'aimant (12) : MON ranch seulement (D18)
	pot = table.freeze({ parts = 20, particles = 0, lights = 0 }),
	-- accessoires de la silhouette (lot B4 étape 4, D18b) : cadre doré 8, anneau « prêt » 8, anneau-soleil
	-- 9 ; détail complet seulement : 25 × 3
	silhouette = table.freeze({ parts = 75, particles = 0, lights = 0 }),
})

local METRIC_GAP = 60 -- s entre deux envois au plus
local METRIC_MAX = 5 -- envois au plus par séance
local OVER_MIN, OVER_MAX = 1, 1000 -- valeur de ClientMetric (int 0-1000 du contrat)
local NAME_MAX = 32
local COUNT_MAX = 100000 -- plus grand nombre de pièces lu (au-delà : illisible)
local RANCHES = 16

type System = {
	limits: Limits,
	used: { parts: number, particles: number, lights: number },
	peak: number,
	refused: number,
}

local systems: { [string]: System } = {}
local refusedTotal = 0
local metric = { sent = 0, lastAt = -math.huge }

-- Dépendances (les specs les remplacent par _configure) : horloge et envoi d'une intention
local deps: { now: (() -> number)?, send: ((string, string, number) -> boolean)? } = {}

-- =============================================================================================
-- Outils
-- =============================================================================================

local function validName(name: any): boolean
	return type(name) == "string" and #name >= 1 and #name <= NAME_MAX
end

-- Entier ≥ 0 lisible (NaN, ±inf, négatif, trop grand, mauvais type → nil)
local function count(n: any): number?
	if type(n) ~= "number" or n ~= n or n < 0 or n > COUNT_MAX then
		return nil
	end
	return math.floor(n)
end

local function kindOf(kind: any): Kind
	if kind == "particles" or kind == "lights" then
		return kind
	end
	return "parts"
end

local function now(): number
	local fn = deps.now
	if fn then
		local ok, t = pcall(fn)
		if ok and type(t) == "number" and t == t then
			return t
		end
		return 0
	end
	return Clock.now()
end

-- Envoi par défaut : Widgets.send (seau partagé de l'intention ClientMetric), requis à la demande
-- (aucune dépendance de l'interface tant qu'aucun dépassement n'arrive)
local function defaultSend(name: string, kind: string, value: number): boolean
	local ok, widgets = pcall(function(): any
		return require(Client.UI.Panels.Widgets) :: any
	end)
	if not ok or type(widgets) ~= "table" or type(widgets.send) ~= "function" then
		return false
	end
	local sentOk, sent = pcall(widgets.send, name, kind, value)
	return sentOk and sent == true
end

-- Un dépassement de `over` pièces : compteur, puis métrique au débit voulu (60 s, 5 par séance)
local function noteExcess(over: number)
	refusedTotal += 1
	if metric.sent >= METRIC_MAX then
		return
	end
	local t = now()
	if t - metric.lastAt < METRIC_GAP then
		return
	end
	local value = math.clamp(math.floor(over), OVER_MIN, OVER_MAX)
	local send = deps.send or defaultSend
	local ok, sent = pcall(send, "ClientMetric", "visualBudget", value)
	if ok and sent == true then
		metric.sent += 1
		metric.lastAt = t
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Déclare (ou redéclare) le budget d'un système ; champs absents ou illisibles : 0. Une redéclaration
-- garde l'usage (les réservations suivantes suivent le nouveau budget). Faux si le nom est illisible.
function VisualBudget.declare(name: string, limits: any): boolean
	if not validName(name) or type(limits) ~= "table" then
		return false
	end
	local l: Limits = {
		parts = count(limits.parts) or 0,
		particles = count(limits.particles) or 0,
		lights = count(limits.lights) or 0,
	}
	local sys = systems[name]
	if sys then
		sys.limits = l
	else
		systems[name] = { limits = l, used = { parts = 0, particles = 0, lights = 0 }, peak = 0, refused = 0 }
	end
	return true
end

-- Le système est déclaré
function VisualBudget.declared(name: string): boolean
	return validName(name) and systems[name] ~= nil
end

-- Réserve `n` pièces (ou particules, lumières) ; faux si le système n'est pas déclaré, si `n` est
-- illisible, ou si l'usage dépasserait le budget (rien n'est réservé : l'appelant dégrade)
function VisualBudget.take(name: string, n: number, kind: Kind?): boolean
	local sys = if validName(name) then systems[name] else nil
	local amount = count(n)
	if sys == nil or amount == nil then
		return false
	end
	if amount == 0 then
		return true
	end
	local k = kindOf(kind)
	local used = sys.used[k]
	local limit = sys.limits[k]
	if used + amount > limit then
		sys.refused += 1
		noteExcess(used + amount - limit)
		return false
	end
	sys.used[k] = used + amount
	if k == "parts" and sys.used.parts > sys.peak then
		sys.peak = sys.used.parts
	end
	return true
end

-- Rend `n` pièces (ou particules, lumières) ; jamais sous 0
function VisualBudget.release(name: string, n: number, kind: Kind?)
	local sys = if validName(name) then systems[name] else nil
	local amount = count(n)
	if sys == nil or amount == nil then
		return
	end
	local k = kindOf(kind)
	sys.used[k] = math.max(0, sys.used[k] - amount)
end

-- Usage réservé d'un système (0 s'il n'est pas déclaré)
function VisualBudget.used(name: string, kind: Kind?): number
	local sys = if validName(name) then systems[name] else nil
	if sys == nil then
		return 0
	end
	return sys.used[kindOf(kind)]
end

-- Ordre fixe de dégradation (priorité décroissante) : mon ranch, le ranch courant, ses 2 voisins (le
-- suivant puis le précédent), puis les autres du plus proche au plus lointain du ranch courant ;
-- les ranchs sont 1 … 16, `mySlot` ou `current` illisibles sont ignorés
function VisualBudget.order(mySlot: number?, current: number?): { number }
	local function valid(s: any): boolean
		return type(s) == "number" and s == s and s % 1 == 0 and s >= 1 and s <= RANCHES
	end
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	local function add(s: number)
		if not seen[s] then
			seen[s] = true
			table.insert(out, s)
		end
	end
	if valid(mySlot) then
		add(mySlot :: number)
	end
	local c = if valid(current) then current :: number elseif valid(mySlot) then mySlot :: number else 1
	add(c)
	for d = 1, RANCHES // 2 do
		add((c - 1 + d) % RANCHES + 1)
		add((c - 1 - d) % RANCHES + 1)
	end
	return out
end

-- Répartit les pièces d'un système entre les ranchs (remplace tout son usage de pièces) : dans
-- l'ordre `order`, chaque ranch de `wants` reçoit « full » (wants.full pièces) s'il tient, sinon
-- « reduced » (wants.reduced), sinon « none » ; dès qu'un ranch est dégradé, ceux qui le suivent ne
-- reçoivent pas mieux (les plus lointains d'abord, le mien en dernier). Un manque compte comme un
-- dépassement (n = pièces demandées en détail complet et non accordées). Rend { [slot] = niveau }.
-- Un système réparti par allocate ne prend pas de pièces par take (allocate remplace son usage).
function VisualBudget.allocate(
	name: string,
	order: { number },
	wants: { [number]: Want }
): { [number]: string }
	local out: { [number]: string } = {}
	local sys = if validName(name) then systems[name] else nil
	if sys == nil or type(order) ~= "table" or type(wants) ~= "table" then
		return out
	end
	sys.used.parts = 0
	local cap = 2 -- 2 : complet permis, 1 : réduit au mieux, 0 : rien
	local wanted, granted = 0, 0
	local seen: { [number]: boolean } = {}
	for _, slot in order do
		local w = if type(slot) == "number" and not seen[slot] then wants[slot] else nil
		if type(w) == "table" then
			seen[slot] = true
			local full = count(w.full) or 0
			local reduced = math.min(count(w.reduced) or 0, full)
			wanted += full
			local level = "none"
			if cap >= 2 and sys.used.parts + full <= sys.limits.parts then
				level = "full"
				sys.used.parts += full
				granted += full
			else
				cap = math.min(cap, 1)
				if cap >= 1 and sys.used.parts + reduced <= sys.limits.parts then
					level = "reduced"
					sys.used.parts += reduced
					granted += reduced
				else
					cap = 0
				end
			end
			out[slot] = level
		end
	end
	if sys.used.parts > sys.peak then
		sys.peak = sys.used.parts
	end
	if granted < wanted then
		sys.refused += 1
		noteExcess(wanted - granted)
	end
	return out
end

-- Compteurs par système (copies)
function VisualBudget.stats(): { [string]: SystemStats }
	local out: { [string]: SystemStats } = {}
	for name, sys in systems do
		out[name] = {
			parts = sys.limits.parts,
			particles = sys.limits.particles,
			lights = sys.limits.lights,
			used = sys.used.parts,
			usedParticles = sys.used.particles,
			usedLights = sys.used.lights,
			peak = sys.peak,
			refused = sys.refused,
		}
	end
	return out
end

-- Dépassements vus dans la séance (réservations refusées et répartitions incomplètes)
function VisualBudget.exceeded(): number
	return refusedTotal
end

-- Métriques envoyées dans la séance (specs, Diagnostics)
function VisualBudget.metricsSent(): number
	return metric.sent
end

-- Remplace l'horloge et l'envoi (specs) ; nil rend la valeur par défaut
function VisualBudget._configure(
	options: { now: (() -> number)?, send: ((string, string, number) -> boolean)? }?
)
	deps = {}
	if type(options) == "table" then
		deps.now = if type(options.now) == "function" then options.now else nil
		deps.send = if type(options.send) == "function" then options.send else nil
	end
end

-- Remise à zéro (specs, fin de séance)
function VisualBudget._reset()
	table.clear(systems)
	refusedTotal = 0
	metric.sent = 0
	metric.lastAt = -math.huge
end

return VisualBudget
