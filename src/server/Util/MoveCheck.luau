--!strict
-- MoveCheck — paquet « conga » (docs/04-architecture.md §11.14).
-- Contrôle de déplacement serveur (GDD §12.7), état par joueur en mémoire, SANS service Roblox :
-- CongaService lui fournit positions, vitesses et hauteur du sol ; testable sous Lune.
-- Règles (Config/Balance.MoveCheck) :
--   * déplacement XZ autorisé = vmax × Δt × 1,5 + 4, vmax = WalkSpeed serveur maximal des 0,5 s
--     précédant la position de référence jusqu'à maintenant (noteSpeed) ; montée verticale
--     ≤ 12 studs/s (même marge : un saut normal passe) ; chute libre ignorée
--   * deux mesures, la règle s'appliquant à chacune :
--       - par tick, depuis la DERNIÈRE POSITION VALIDE (et non la position du tick précédent) : une
--         téléportation reste signalée tick après tick, elle ne « passe » jamais au tick suivant ;
--         Δt = temps écoulé depuis cette position : un pas de serveur en retard ou une rafale après
--         un gel réseau ne sont pas des infractions (à l'arrêt, le crédit de temps s'accumule au
--         plus STILL_CREDIT s : pas de « banque » de téléportation)
--       - soutenue, sur SUSTAIN_WINDOW (1 s) de positions valides : la marge fixe de 4 studs n'est
--         comptée qu'une fois sur la fenêtre (appliquée à chaque tick de 0,1 s, elle laisserait
--         passer une vitesse ×4)
--   * altitude > sol + 14 pendant plus de 1,5 s, r > 182 ou Y < −5 → retour immédiat
--   * vol bas prolongé : racine à plus de RootHeight + Snip.MaxDy (3 + 4) au-dessus du sol pendant
--     plus de HoverTime (1 s, Conga/Tuning) → chaque tick est une INFRACTION (signalée, comptée,
--     3 en 5 s → retour) et la position n'est pas acceptée. Hors de portée verticale des coupes, un
--     joueur ne doit jamais pouvoir rester (HipHeight relevé, CFrame décalé) ; un vrai saut
--     (JumpHeight 7,2) n'y passe qu'≈ 0,36 s. CongaService ramène de toute façon les miettes au sol.
--   * une infraction SIGNALE seulement (verdict "flag" : ce tick ne peut ni attraper, ni couper, ni
--     encaisser, ni voler la Comète) ; 3 infractions en 5 s → "rewind" vers la dernière position
--     valide, puis 3 s de restriction (isRestricted)
--   * période de grâce (exemption de 3 s après reset, ou restriction après un retour) : les
--     positions encore « en vol » ne déclenchent pas de nouveau retour par infractions et aucun
--     retour n'y compte comme récidive (recentRewinds) — un joueur honnête qui décroche n'est jamais
--     exclu des classements ; les bornes absolues (r, Y, altitude) restent appliquées
--   * exemption de 3 s après reset (apparition, PivotTo serveur) : les infractions n'y sont NI
--     comptées NI suivies d'un retour (paquets du client d'avant le déplacement serveur), mais une
--     position incohérente avec la nouvelle référence reste signalée ("flag" : aucune action) et
--     n'est jamais acceptée comme référence. Sinon une réapparition (réinitialisation volontaire du
--     personnage) offrirait 3 s de téléportation libre : captures, coupes et parades à distance.
--     Si le client reste loin de la référence après l'exemption, les infractions comptent et le
--     retour le ramène là où le serveur l'a placé.
--   * jamais d'accusation : l'interface affiche « connexion instable » (ton neutre)
-- GDD : §12.7, §14.3 (MoveViolation), §14.4 (marges réglables).
-- Dépendances : Config/Balance, Conga/Tuning.

local Balance = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Balance)
local Tuning = require(script.Parent.Parent.Conga.Tuning)

local MoveCheck = {}

export type Verdict = "ok" | "flag" | "rewind"

local Cfg = Balance.MoveCheck

-- Crédit de temps maximal accumulé à l'arrêt (s) : tolère un gel réseau sans permettre de
-- « stocker » une téléportation
local STILL_CREDIT = 1.5
-- Fenêtre de la mesure soutenue (s)
local SUSTAIN_WINDOW = 1
-- Δt maximal pris en compte par la mesure par tick, MÊME si aucune position n'a été acceptée depuis
-- la référence (apparition, PivotTo, retour suivis de positions incohérentes) : sinon le crédit
-- grandirait pendant l'exemption ou la restriction et un bond de 100 studs passerait au bout de 3 s.
-- Un client honnête renvoie une position proche de la référence en un ping, bien avant.
local MAX_ELAPSED = STILL_CREDIT
-- Déplacement en dessous duquel le joueur est considéré à l'arrêt (studs)
local STILL_EPSILON = 0.05
-- Vitesse supposée tant qu'aucun WalkSpeed n'a été noté : le maximum atteignable en jeu
local DEFAULT_VMAX = Balance.Speed.Base
	+ Balance.Speed.PerStride * (Balance.Upgrades.stride.Max or 0)
	+ Balance.Dash.Boost
	+ Balance.Speed.SecondWindBoost
-- Hauteur de la racine au-dessus du sol au-delà de laquelle le joueur est hors de portée
-- verticale des coupes (un coupeur au sol ne l'atteindrait plus), et durée tolérée (saut)
local HOVER_ABOVE = Tuning.RootHeight + Balance.Snip.MaxDy
local HOVER_TIME = Tuning.HoverTime
-- Historique de vitesses conservé au-delà de la fenêtre utile (s)
local SPEED_HISTORY = Cfg.SpeedWindow + MAX_ELAPSED + SUSTAIN_WINDOW

type SpeedNote = { t: number, v: number }
type Sample = { t: number, pos: Vector3 }

type State = {
	lastValid: Vector3, -- dernière position acceptée (référence du contrôle et point de retour)
	validAt: number, -- instant depuis lequel le déplacement autorisé s'accumule (crédit d'arrêt)
	acceptedAt: number, -- instant de la dernière position acceptée (montée verticale)
	history: { Sample }, -- positions acceptées de la fenêtre soutenue
	exemptUntil: number,
	restrictedUntil: number,
	highSince: number?, -- début d'un vol prolongé au-dessus du sol
	hoverSince: number?, -- début d'un vol bas, hors de portée verticale des coupes
	flags: { number }, -- instants des infractions (fenêtre FlagWindow)
	rewinds: { number }, -- instants des retours comptés (fenêtre StrikeWindow)
	violations: number, -- infractions de la session
}

local states: { [Player]: State } = {}
local speeds: { [Player]: { SpeedNote } } = {}

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

local function finiteVector(v: Vector3): boolean
	return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Nouvelle référence : position acceptée et historique repartant de ce point
local function anchor(st: State, pos: Vector3, now: number)
	st.lastValid = pos
	st.validAt = now
	st.acceptedAt = now
	st.history = { { t = now, pos = pos } }
end

local function newState(pos: Vector3, now: number): State
	local st: State = {
		lastValid = pos,
		validAt = now,
		acceptedAt = now,
		history = {},
		exemptUntil = -math.huge,
		restrictedUntil = -math.huge,
		highSince = nil,
		hoverSince = nil,
		flags = {},
		rewinds = {},
		violations = 0,
	}
	anchor(st, pos, now)
	return st
end

-- Retire de `list` (triée) les instants ≤ `cutoff`
local function prune(list: { number }, cutoff: number)
	local keep = #list + 1
	for i, t in list do
		if t > cutoff then
			keep = i
			break
		end
	end
	if keep > 1 then
		table.move(list, keep, #list + keep - 1, 1)
	end
end

-- WalkSpeed maximal en vigueur sur [from ; to] : la dernière note antérieure à `from` (la vitesse
-- en cours au début de l'intervalle) et toutes les notes de l'intervalle
local function maxSpeed(player: Player, from: number, to: number): number
	local notes = speeds[player]
	if notes == nil or #notes == 0 then
		return DEFAULT_VMAX
	end
	local best = -math.huge
	local before: number? = nil
	for _, note in notes do
		if note.t <= from then
			before = note.v
		elseif note.t <= to then
			best = math.max(best, note.v)
		end
	end
	if before ~= nil then
		best = math.max(best, before)
	end
	if best == -math.huge then
		-- seulement des notes postérieures à `to` (horloge incohérente) : la plus ancienne
		best = notes[1].v
	end
	return best
end

local function accept(st: State, pos: Vector3, now: number)
	local moved = (pos - st.lastValid).Magnitude > STILL_EPSILON
	st.lastValid = pos
	st.acceptedAt = now
	if moved then
		st.validAt = now
	else
		st.validAt = math.max(st.validAt, now - STILL_CREDIT)
	end
	local history = st.history
	table.insert(history, { t = now, pos = pos })
	local cutoff = now - SUSTAIN_WINDOW
	local first = 1
	while first < #history and history[first].t < cutoff do
		first += 1
	end
	if first > 1 then
		table.move(history, first, #history + first - 1, 1)
	end
end

local function rewind(st: State, now: number, grace: boolean): (Verdict, Vector3?)
	table.clear(st.flags)
	st.highSince = nil
	st.hoverSince = nil
	st.restrictedUntil = math.max(st.restrictedUntil, now + Cfg.RewindLockout)
	anchor(st, st.lastValid, now)
	if not grace then
		prune(st.rewinds, now - Cfg.StrikeWindow)
		table.insert(st.rewinds, now)
	end
	return "rewind", st.lastValid
end

-- Le déplacement de `from` (à l'instant `since`) jusqu'à `pos` est-il plausible ? (Δt pris en
-- compte borné à `maxElapsed`)
local function plausible(
	player: Player,
	from: Vector3,
	since: number,
	pos: Vector3,
	now: number,
	step: number,
	maxElapsed: number
): boolean
	local elapsed = math.clamp(now - since, step, math.max(step, maxElapsed))
	local vmax = maxSpeed(player, since - Cfg.SpeedWindow, now)
	return distXZ(pos, from) <= vmax * elapsed * Cfg.Margin + Cfg.Slack
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Nouvelle référence de position (apparition, PivotTo serveur) : exemption de Balance.MoveCheck.Exemption s
function MoveCheck.reset(player: Player, pos: Vector3, now: number)
	if not finiteVector(pos) or not isFinite(now) then
		return
	end
	local st = states[player]
	if st == nil then
		st = newState(pos, now)
		states[player] = st
	end
	anchor(st, pos, now)
	st.exemptUntil = now + Cfg.Exemption
	st.highSince = nil
	st.hoverSince = nil
	table.clear(st.flags)
end

-- WalkSpeed serveur appliqué à `now` (historique de SpeedWindow s)
function MoveCheck.noteSpeed(player: Player, walkSpeed: number, now: number)
	if not isFinite(walkSpeed) or walkSpeed < 0 or not isFinite(now) then
		return
	end
	local notes = speeds[player]
	if notes == nil then
		notes = {}
		speeds[player] = notes
	end
	table.insert(notes, { t = now, v = walkSpeed })
	-- on garde la dernière note antérieure à l'horizon (vitesse en vigueur à ce moment-là)
	local horizon = now - SPEED_HISTORY
	local firstKept = 1
	while firstKept < #notes and notes[firstKept + 1].t <= horizon do
		firstKept += 1
	end
	if firstKept > 1 then
		table.move(notes, firstKept, #notes + firstKept - 1, 1)
	end
end

-- Vérifie le déplacement du tick ; "rewind" fournit la position de retour
function MoveCheck.step(
	player: Player,
	pos: Vector3,
	dt: number,
	now: number,
	groundY: number
): (Verdict, Vector3?)
	local st = states[player]
	if not finiteVector(pos) or not isFinite(now) then
		if st then
			st.violations += 1
		end
		return "flag", nil
	end
	if st == nil then
		-- jamais vu (pas de reset) : la première position devient la référence, sans exemption
		st = newState(pos, now)
		states[player] = st
	end
	local grace = now < st.exemptUntil or now < st.restrictedUntil

	-- 1) bornes absolues : hors de l'île, sous le monde, vol prolongé
	local outOfBounds = math.sqrt(pos.X * pos.X + pos.Z * pos.Z) > Cfg.MaxRadius or pos.Y < Cfg.MinY
	local ground = if isFinite(groundY) then groundY else pos.Y
	if pos.Y > ground + Cfg.MaxAltitude then
		local since = st.highSince
		if since == nil then
			st.highSince = now
		elseif now - since > Cfg.AltitudeTime then
			outOfBounds = true
		end
	else
		st.highSince = nil
	end
	if outOfBounds then
		st.violations += 1
		return rewind(st, now, grace)
	end
	-- vol bas prolongé, hors de portée verticale des coupes (infraction à l'étape 4)
	local hovering = false
	if pos.Y > ground + HOVER_ABOVE then
		local since = st.hoverSince
		if since == nil then
			st.hoverSince = now
		elseif now - since > HOVER_TIME then
			hovering = true
		end
	else
		st.hoverSince = nil
	end

	-- 2) déplacement par tick (depuis la dernière position valide), montée, puis vitesse soutenue ;
	-- appliqué AUSSI pendant l'exemption (seule la sanction en est levée, étape 3)
	local step = if isFinite(dt) then math.max(0, dt) else 0
	local ok = plausible(player, st.lastValid, st.validAt, pos, now, step, MAX_ELAPSED)
	if ok then
		local climb = math.clamp(now - st.acceptedAt, step, math.max(step, MAX_ELAPSED))
		ok = pos.Y - st.lastValid.Y <= Cfg.MaxClimbSpeed * climb * Cfg.Margin + Cfg.Slack
	end
	if ok then
		-- fenêtre soutenue : depuis la plus ancienne position valide de la dernière seconde (le
		-- crédit d'arrêt de la mesure par tick ne dépasse jamais ce que permet cette fenêtre, même
		-- quand cette position est plus ancienne : référence sans position acceptée depuis)
		local oldest = st.history[1]
		if oldest then
			ok = plausible(player, oldest.pos, oldest.t, pos, now, step, SUSTAIN_WINDOW)
		end
	end
	if ok and not hovering then
		accept(st, pos, now)
		return "ok", nil
	end

	-- 3) exemption après une apparition ou un déplacement imposé par le serveur : position
	-- incohérente signalée (aucune action ce tick), jamais comptée, référence inchangée
	if now < st.exemptUntil then
		return "flag", nil
	end

	-- 4) infraction : signalée ; 3 en 5 s (hors grâce) → retour
	st.violations += 1
	if not grace then
		prune(st.flags, now - Cfg.FlagWindow)
		table.insert(st.flags, now)
		if #st.flags >= Cfg.FlagsToRewind then
			return rewind(st, now, false)
		end
	end
	return "flag", nil
end

-- Captures, coupes et parades interdites (3 s après un retour)
function MoveCheck.isRestricted(player: Player, now: number): boolean
	local st = states[player]
	return st ~= nil and now < st.restrictedUntil
end

function MoveCheck.lastValid(player: Player): Vector3?
	local st = states[player]
	return if st then st.lastValid else nil
end

-- Infractions de la session (analytique MoveViolation)
function MoveCheck.violations(player: Player): number
	local st = states[player]
	return if st then st.violations else 0
end

-- Retours forcés dans la fenêtre StrikeWindow (exclusion des classements à StrikesForBan)
function MoveCheck.recentRewinds(player: Player, now: number): number
	local st = states[player]
	if st == nil then
		return 0
	end
	local n = 0
	for _, t in st.rewinds do
		if t > now - Cfg.StrikeWindow and t <= now then
			n += 1
		end
	end
	return n
end

function MoveCheck.clear(player: Player)
	states[player] = nil
	speeds[player] = nil
end

return MoveCheck
