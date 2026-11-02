--!strict
-- MoveCheck : contrôle de déplacement serveur (anti-triche), état par joueur en mémoire, SANS service
-- Roblox : le service du tick de jeu lui fournit positions, vitesses et hauteur du sol ; testable
-- sous Lune. Repris de Comet Conga avec tous ses correctifs (budget d'action de la passe de
-- finition, fenêtres conscientes des gels réseau, règles de montée et de vol bas du tour 6).
-- Seuils : Server/Movement/Tuning (serveur seulement, exposés en MoveCheck.Config).
-- Utilisation (par tick, 10 Hz, dans un pcall) :
--   MoveCheck.noteSpeed(player, humanoid.WalkSpeed, now)   -- à chaque changement de vitesse serveur
--   MoveCheck.reset(player, pos, now)                      -- apparition, PivotTo du serveur
--   local verdict, back, burst = MoveCheck.step(player, root.Position, dt, now, groundY)
--   "rewind" → PivotTo(back) ; "flag" → ce tick n'agit sur rien ; burst → ce tick n'agit sur rien
--   MoveCheck.canAct(player, now)                          -- lectures hors tick (actions par remote)
--   MoveCheck.clear(player)                                -- PlayerRemoving
-- Règles :
--   * déplacement XZ autorisé = vmax × Δt × 1,5 + 4, vmax = WalkSpeed serveur maximal des 0,5 s
--     précédant la position de référence jusqu'à maintenant (noteSpeed) ; montée verticale
--     ≤ 12 studs/s (même marge, même crédit d'arrêt que la mesure XZ : un saut normal passe, même
--     quand ses premiers paquets arrivent groupés ou à la fin d'un gel) ; chute libre ignorée
--   * deux mesures, la règle s'appliquant à chacune :
--       - par tick, depuis la DERNIÈRE POSITION VALIDE (et non la position du tick précédent) : une
--         téléportation reste signalée tick après tick, elle ne « passe » jamais au tick suivant ;
--         Δt = temps écoulé depuis cette position : un pas de serveur en retard ou une rafale après
--         un gel réseau ne sont pas des infractions (à l'arrêt, le crédit de temps s'accumule au
--         plus STILL_CREDIT s : pas de « banque » de téléportation)
--       - soutenue, sur SUSTAIN_WINDOW (1 s) de positions valides : la marge fixe de 4 studs n'est
--         comptée qu'une fois sur la fenêtre (appliquée à chaque tick de 0,1 s, elle laisserait
--         passer une vitesse ×4). Arrêt (gel réseau) : pendant un gel, le serveur reçoit encore la
--         position figée avec des instants frais ; une fois le joueur reparti, la fenêtre se mesure
--         depuis le DÉBUT de cet arrêt (Sample.since) et s'allonge du temps écoulé depuis le départ
--         (SUSTAIN_WINDOW + (now − départ)). Au tick du départ elle vaut exactement SUSTAIN_WINDOW :
--         le crédit d'arrêt reste borné par la fenêtre soutenue (un bond de 40 studs après 2 s
--         d'arrêt reste signalé), mais un joueur honnête qui court après un gel de 0,7 à 1,5 s n'est
--         plus ramené, restreint, signalé « instable » ni compté pour l'exclusion des classements
--   * altitude > sol + MaxAltitude (14) pendant plus de AltitudeTime (1,5 s), distance XZ au centre
--     du monde > MaxRadius, Y < MinY ou racine à plus de MaxBelowGround (2) sous la surface
--     (passe-muraille) → retour immédiat ; une racine sous la surface pendant l'exemption est
--     seulement refusée ("flag", sans retour ni restriction : personnage pas encore posé)
--   * hors de portée verticale des actions, prolongé : racine à plus de ActionReachY (4) au-dessus
--     (vol bas : > sol + RootHeight + ActionReachY = sol + 7) ou au-dessous (racine enfouie :
--     < surface + RootHeight − ActionReachY = surface − 1) de la hauteur debout pendant plus de
--     HoverTime (1 s) → chaque tick est une INFRACTION (signalée, comptée, 3 en 5 s → retour) et la
--     position n'est pas acceptée. Un joueur ne doit jamais pouvoir y rester (HipHeight relevé,
--     CFrame décalé vers le haut ou sous le sol) ; un vrai saut (JumpHeight 7,2) ne passe qu'≈ 0,36 s
--     au-dessus. Gel réseau (position figée, le serveur garde la racine reçue en haut d'un saut) :
--     les ticks figés ne font pas avancer ce chronomètre, au plus 1,5 s par écart (un gel de 0,7 à
--     1,5 s n'est jamais compté ; planer immobile finit signalé)
--   * « sol » (groundY) = hauteur fournie par l'appelant : ce qui porte vraiment le personnage (sonde
--     Blockcast dans le groupe de collision des personnages : jamais un autre joueur) ; un joueur
--     honnête debout sur un appui n'est jamais en vol bas. Les règles de racine enfouie se mesurent
--     à la SURFACE : min(sol fourni, surface analytique du jeu) si le jeu en a installé une
--     (MoveCheck.setSurface), sinon le sol fourni ; sol inconnu (NaN) : seules les bornes absolues
--   * une infraction SIGNALE seulement (verdict "flag" : ce tick n'agit sur rien) ; 3 infractions en
--     5 s → "rewind" vers la dernière position valide, puis 3 s de restriction (isRestricted)
--   * rafale (troisième valeur de step, lastWasBurst, canAct) : position ACCEPTÉE ("ok", tolérance
--     des gels réseau inchangée) mais le joueur est « en dette » de BUDGET D'ACTION. Le budget (seau
--     à jetons, en studs, par joueur) a pour plafond la règle pour UN tick (vmax × dt × 1,5 + 4,
--     dt = durée réelle du tick, depuis l'appel précédent, bornée à BURST_MAX_TICK), se remplit à
--     vmax × 1,5 studs/s et chaque position acceptée en retire sa distance XZ depuis la position
--     valide précédente ; budget < 0 → rafale. Le budget a de la MÉMOIRE d'un tick à l'autre : un bond
--     (1 s d'arrêt puis 19 à 58 studs) laisse une dette que seuls la marche lente ou l'arrêt
--     remboursent ; le tick SUIVANT le bond est donc toujours une rafale, de même qu'une chaîne de
--     petits pas trop longs (4 × 6,25 studs en 0,4 s) : le joueur ne ré-agit qu'une fois la dette
--     remboursée. Le crédit d'arrêt (jusqu'à STILL_CREDIT s) et la fenêtre soutenue ne sont plus que
--     des tolérances de position. Un tick en rafale ne doit AGIR sur rien (aucune capture, aucun
--     boop, aucun ramassage, aucune zone de jeu) : l'appelant peut seulement mettre à jour ce qui
--     suit le joueur. Jamais une infraction, jamais de retour. Coût honnête : après un gel réseau de
--     f s à la vitesse v, ≈ (v × (f + 0,1) − plafond) / (0,05 × v) ticks sans action en continuant
--     de courir à pleine vitesse (à 16 : gel de 0,7 s → ≈ 0,9 s ; 1 s → ≈ 1,5 s ; 1,5 s → ≈ 2,5 s),
--     moins d'une seconde en s'arrêtant (remplissage trois fois plus rapide)
--   * période de grâce (exemption de 3 s après reset, ou restriction après un retour) : les
--     positions encore « en vol » ne déclenchent pas de nouveau retour par infractions et aucun
--     retour n'y compte comme récidive (recentRewinds) — un joueur honnête qui décroche n'est jamais
--     exclu des classements ; les bornes absolues (r, Y, altitude) restent appliquées
--   * exemption de 3 s après reset (apparition, PivotTo serveur) : les infractions n'y sont NI
--     comptées NI suivies d'un retour (paquets du client d'avant le déplacement serveur), mais une
--     position incohérente avec la nouvelle référence reste signalée ("flag" : aucune action) et
--     n'est jamais acceptée comme référence. Sinon une réapparition (réinitialisation volontaire du
--     personnage) offrirait 3 s de téléportation libre. Si le client reste loin de la référence
--     après l'exemption, les infractions comptent et le retour le ramène là où le serveur l'a placé.
--   * jamais d'accusation : l'interface affiche « connexion instable » (ton neutre)
-- Accepté par conception (Comet Conga, contre-audit) : courir jusqu'à ≈ 1,5 × la vitesse normale
-- n'est jamais signalé (marge des réseaux lents).
-- Note INT-MOVE (contrat v1.2, paquet chase) :
--   MoveCheck.setRootOffset(player, studs, jumpHeight)   -- monture : hausse de la racine debout et
--     hauteur de saut de la selle. Les règles de vol bas, de racine enfouie et d'altitude se mesurent
--     depuis la racine debout RELEVÉE ; montée permise par tick = max(MaxClimbSpeed, √(2 g jumpHeight))
--     × Δt × Margin + Slack ; une HAUSSE du décalage accorde une marge verticale ponctuelle égale au
--     changement (un seul pas qui monte, au plus STILL_CREDIT s), sans remise à zéro de l'historique ni
--     exemption (monter et descendre en boucle ne permet aucun vol : vol bas et altitude restent mesurés)
--   MoveCheck.rootOffset(player)                         -- hausse en vigueur (0 à pied)
--   MoveCheck.grant(player, studs, duration, tStart)     -- bond : crédit de `studs` sur la fenêtre
--     [tStart ; tStart + duration] (+ GRANT_TAIL pour les positions en retard) ajouté au plafond par
--     tick, à la fenêtre soutenue et au budget d'action (dette remboursée aussitôt) ; tStart ramené dans
--     [réception − GrantRetro ; réception] ; refusé si le crédit précédent a moins de GrantMinGap s
--     (horloge du serveur) : une rafale de faux bonds n'apporte jamais plus de `studs` par GrantMinGap
--   MoveCheck.positionAt(player, t)                      -- position acceptée à l'instant t, interpolée
--     dans un anneau de PositionHistory s (captures vérifiées à l'instant tClient du client) ; nil hors
--     de l'anneau ; effacée par clear (départ)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Clock"))
local Tuning = require(script.Parent.Parent.Movement.Tuning)

local MoveCheck = {}

export type Verdict = "ok" | "flag" | "rewind"

-- Seuils de l'anti-triche : configuration serveur (Movement/Tuning), exposée aux tests en lecture
local Cfg = Tuning.MoveCheck
MoveCheck.Config = Cfg

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
-- Durée maximale d'un tick pour la règle de rafale (s) : le serveur rattrape au plus MaxCatchUp
-- pas d'une image en retard (même instant) ; au-delà, le retard est abandonné. Un accroc du serveur
-- n'est donc jamais une rafale ; un trou plus long (personnage absent sans réinitialisation) ne
-- devient jamais un crédit de bond.
local BURST_MAX_TICK = Tuning.TickStep * Tuning.MaxCatchUp
-- Vitesse supposée tant qu'aucun WalkSpeed n'a été noté : le maximum atteignable en jeu
local DEFAULT_VMAX = Tuning.DefaultMaxSpeed
-- Hauteurs de la racine par rapport au sol au-delà desquelles le joueur est hors de portée
-- verticale des actions (un joueur debout ne l'atteindrait plus), et durée tolérée (saut)
local HOVER_ABOVE = Tuning.RootHeight + Tuning.ActionReachY
local BURIED_BELOW = Tuning.RootHeight - Tuning.ActionReachY
local HOVER_TIME = Tuning.HoverTime
-- Temps de gel réseau (position figée) qui ne fait pas avancer le chronomètre de vol bas, par écart
-- (s) : la même tolérance que le crédit d'arrêt de la mesure XZ
local HOVER_FREEZE_CREDIT = STILL_CREDIT
-- Profondeur de la racine sous la surface du sol au-delà de laquelle elle est hors du monde
local MAX_BELOW_GROUND = Tuning.MaxBelowGround
-- Historique de vitesses conservé au-delà de la fenêtre utile (s)
local SPEED_HISTORY = Cfg.SpeedWindow + MAX_ELAPSED + SUSTAIN_WINDOW
-- Monture (INT-MOVE) : bornes de la hausse de la racine et de la hauteur de saut acceptées, gravité
local MAX_ROOT_OFFSET = Tuning.MaxRootOffset
local MAX_JUMP_HEIGHT = Tuning.MaxJumpHeight
local GRAVITY = Tuning.Gravity
-- Durée de validité de la marge verticale ponctuelle d'une hausse du décalage (s) : la position
-- relevée arrive un ping plus tard ; jamais plus longtemps que le crédit d'arrêt
local OFFSET_BONUS_TIME = STILL_CREDIT
-- Bond accordé (INT-MOVE) : fenêtre du crédit prolongée de GRANT_TAIL s (positions du bond qui
-- arrivent un ping et un tick après la fin du bond sur le client)
local GRANT_RETRO = Tuning.GrantRetro
local GRANT_MIN_GAP = Tuning.GrantMinGap
local GRANT_TAIL = Tuning.GrantRetro + Tuning.TickStep
-- Historique des positions acceptées (s) : MoveCheck.positionAt
local POSITION_HISTORY = Tuning.PositionHistory
-- Tolérance d'horloge de positionAt aux bords de l'anneau (s)
local POSITION_EPSILON = 1e-6

type SpeedNote = { t: number, v: number }
type PositionSample = { t: number, pos: Vector3 }
-- Monture du joueur (setRootOffset) : gardée à part de l'état de position (la montée peut précéder le
-- premier tick) ; bonus = marge verticale ponctuelle d'une hausse, valable jusqu'à bonusUntil
type Ride = { offset: number, jumpHeight: number?, bonus: number, bonusUntil: number }
-- since : début de l'arrêt dont fait partie cet échantillon (= t pour une position qui a bougé)
type Sample = { t: number, pos: Vector3, since: number }

type State = {
	lastValid: Vector3, -- dernière position acceptée (référence du contrôle et point de retour)
	validAt: number, -- instant depuis lequel le déplacement autorisé s'accumule (crédit d'arrêt :
	-- mesure XZ par tick ET montée verticale)
	steppedAt: number, -- instant du dernier appel de step (ou de la dernière référence) : durée du tick
	burst: boolean, -- dernier tick accepté en dette de budget d'action (rafale : n'agit pas)
	budget: number, -- budget d'action (studs) après le dernier tick accepté ; < 0 : en dette
	budgetAt: number, -- instant de la dernière mise à jour du budget (remplissage)
	leftStillAt: number, -- instant du dernier départ d'un arrêt (fenêtre soutenue après un gel)
	history: { Sample }, -- positions acceptées de la fenêtre soutenue
	validAirborne: boolean, -- lastValid acceptée hors de portée verticale (vol bas, racine enfouie)
	validHigh: boolean, -- lastValid acceptée au-dessus de l'altitude maximale
	exemptUntil: number,
	restrictedUntil: number,
	highSince: number?, -- début d'un vol prolongé au-dessus du sol
	hoverSince: number?, -- début d'un écart hors de portée verticale des actions (vol bas ou racine enfouie)
	hoverFrozen: number, -- temps de gel réseau (position figée) déjà décalé de hoverSince dans cet écart
	flags: { number }, -- instants des infractions (fenêtre FlagWindow)
	rewinds: { number }, -- instants des retours comptés (fenêtre StrikeWindow)
	violations: number, -- infractions de la session
	positions: { PositionSample }, -- positions acceptées des PositionHistory dernières secondes
	grantAt: number, -- instant (serveur) de réception du dernier bond accordé
	grantStart: number, -- fenêtre du crédit de bond [grantStart ; grantEnd]
	grantEnd: number,
	grantStuds: number,
	memo: { now: number, pos: Vector3, verdict: Verdict, back: Vector3?, burst: boolean }?, -- verdict de l'instant
}

local states: { [Player]: State } = {}
local speeds: { [Player]: { SpeedNote } } = {}
local rides: { [Player]: Ride } = {}
-- Surface analytique du jeu (pure, sans yield) : MoveCheck.setSurface ; nil = sol fourni seulement
local surfaceAt: ((number, number) -> number)? = nil

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

-- Surface sous (x, z) : min(sol fourni, surface analytique) ; une surface en erreur ou non finie est
-- ignorée (jamais d'erreur dans le tick : seul le sol fourni compte alors)
local function surfaceUnder(ground: number, x: number, z: number): number
	local fn = surfaceAt
	if fn == nil then
		return ground
	end
	local ok, y = pcall(fn, x, z)
	if ok and type(y) == "number" and isFinite(y) then
		return math.min(ground, y)
	end
	return ground
end

-- Position acceptée à l'instant `now` dans l'anneau de positionAt (instants croissants ; un instant
-- répété remplace l'échantillon) ; les échantillons plus vieux que POSITION_HISTORY sont oubliés, sauf
-- le dernier d'avant la limite (interpolation au bord de l'anneau)
local function recordPosition(st: State, pos: Vector3, now: number)
	local list = st.positions
	local last = list[#list]
	if last and now < last.t then
		-- horloge revenue en arrière (specs) : l'anneau repart de ce point
		table.clear(list)
	elseif last and now == last.t then
		list[#list] = nil
	end
	table.insert(list, { t = now, pos = pos })
	local cutoff = now - POSITION_HISTORY
	local first = 1
	while first < #list and list[first + 1].t <= cutoff do
		first += 1
	end
	if first > 1 then
		table.move(list, first, #list + first - 1, 1)
	end
end

-- Nouvelle référence : position acceptée et historique repartant de ce point
local function anchor(st: State, pos: Vector3, now: number)
	st.lastValid = pos
	st.validAt = now
	st.steppedAt = now
	st.burst = false
	-- budget plein (borné au plafond du premier tick) : un déplacement imposé par le serveur ne
	-- laisse jamais de dette
	st.budget = math.huge
	st.budgetAt = now
	st.leftStillAt = -math.huge
	st.history = { { t = now, pos = pos, since = now } }
	st.validAirborne = false
	st.validHigh = false
	st.memo = nil
	recordPosition(st, pos, now)
end

local function newState(pos: Vector3, now: number): State
	local st: State = {
		lastValid = pos,
		validAt = now,
		steppedAt = now,
		burst = false,
		budget = math.huge,
		budgetAt = now,
		leftStillAt = -math.huge,
		history = {},
		validAirborne = false,
		validHigh = false,
		exemptUntil = -math.huge,
		restrictedUntil = -math.huge,
		highSince = nil,
		hoverSince = nil,
		hoverFrozen = 0,
		flags = {},
		rewinds = {},
		violations = 0,
		positions = {},
		grantAt = -math.huge,
		grantStart = -math.huge,
		grantEnd = -math.huge,
		grantStuds = 0,
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
	if moved then
		st.validAt = now
	else
		st.validAt = math.max(st.validAt, now - STILL_CREDIT)
	end
	local history = st.history
	-- arrêt : l'échantillon garde le début de l'arrêt en cours, tant que le serveur l'a observé sans
	-- trou (au plus BURST_MAX_TICK entre deux positions acceptées : un trou d'observation repart de
	-- zéro, comme la fenêtre soutenue) ; départ d'un arrêt noté
	local last = history[#history]
	local still = last ~= nil
		and (pos - last.pos).Magnitude <= STILL_EPSILON
		and now - last.t <= BURST_MAX_TICK + 1e-6
	local since = if still and last then last.since else now
	if last and since == now and last.since < last.t then
		st.leftStillAt = now
	end
	table.insert(history, { t = now, pos = pos, since = since })
	local cutoff = now - SUSTAIN_WINDOW
	local first = 1
	while first < #history and history[first].t < cutoff do
		first += 1
	end
	if first > 1 then
		table.move(history, first, #history + first - 1, 1)
	end
	recordPosition(st, pos, now)
end

-- Retour forcé vers la dernière position valide. Si cette position a elle-même été acceptée en l'air
-- (pendant la tolérance de vol bas ou d'altitude), les chronomètres de vol en cours sont GARDÉS : sinon
-- chaque retour les remettait à zéro sur une position déjà haute, et un tricheur qui monte sans cesse
-- gagnait ≈ 15 studs par retour (échelle vers le ciel, trouvée par la spec INT-MOVE « monter et
-- descendre en boucle »). Ses positions en l'air sont alors refusées tout de suite ; redescendre à
-- portée verticale remet les chronomètres à zéro comme avant.
local function rewind(st: State, now: number, grace: boolean): (Verdict, Vector3?, boolean)
	local hoverSince = if st.validAirborne then st.hoverSince else nil
	local hoverFrozen = st.hoverFrozen
	local highSince = if st.validHigh then st.highSince else nil
	local airborne, high = st.validAirborne, st.validHigh
	table.clear(st.flags)
	st.restrictedUntil = math.max(st.restrictedUntil, now + Cfg.RewindLockout)
	anchor(st, st.lastValid, now)
	st.hoverSince = hoverSince
	st.hoverFrozen = if hoverSince then hoverFrozen else 0
	st.highSince = highSince
	st.validAirborne = airborne
	st.validHigh = high
	if not grace then
		prune(st.rewinds, now - Cfg.StrikeWindow)
		table.insert(st.rewinds, now)
	end
	return "rewind", st.lastValid, false
end

-- Crédit de bond (studs) applicable à une mesure sur [from ; to] : la fenêtre du dernier bond accordé
-- [grantStart ; grantEnd + GRANT_TAIL] recoupe l'intervalle mesuré
local function grantExtra(st: State, from: number, to: number): number
	if st.grantStuds <= 0 or to < st.grantStart or from > st.grantEnd + GRANT_TAIL then
		return 0
	end
	return st.grantStuds
end

-- Le déplacement de `from` (à l'instant `since`) jusqu'à `pos` est-il plausible ? (Δt pris en
-- compte borné à `maxElapsed` ; `extra` : crédit de bond en studs)
local function plausible(
	player: Player,
	from: Vector3,
	since: number,
	pos: Vector3,
	now: number,
	step: number,
	maxElapsed: number,
	extra: number
): boolean
	local elapsed = math.clamp(now - since, step, math.max(step, maxElapsed))
	local vmax = maxSpeed(player, since - Cfg.SpeedWindow, now)
	return distXZ(pos, from) <= vmax * elapsed * Cfg.Margin + Cfg.Slack + extra
end

-- Vitesse verticale maximale permise (studs/s) : MaxClimbSpeed, ou la vitesse de départ d'un saut de
-- la hauteur connue (monture, INT-MOVE) si elle est plus grande
local function climbSpeed(ride: Ride?): number
	local jump = ride and ride.jumpHeight
	if jump == nil then
		return Cfg.MaxClimbSpeed
	end
	return math.max(Cfg.MaxClimbSpeed, math.sqrt(2 * GRAVITY * jump))
end

-- ---------------------------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------------------------

-- Surface analytique du terrain (fonction pure (x, z) → Y, sans yield), ou nil pour l'oublier.
-- Sert aux règles de racine enfouie : surface = min(sol fourni, fn(x, z)).
function MoveCheck.setSurface(fn: ((number, number) -> number)?)
	surfaceAt = fn
end

-- Nouvelle référence de position (apparition, PivotTo serveur) : exemption de Config.Exemption s
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

-- Vérifie le déplacement du tick ; "rewind" fournit la position de retour. Troisième valeur :
-- rafale (seulement avec "ok") — position acceptée, mais le tick ne doit agir sur rien (en-tête)
local function stepOnce(
	player: Player,
	pos: Vector3,
	dt: number,
	now: number,
	groundY: number
): (Verdict, Vector3?, boolean)
	local st = states[player]
	if not finiteVector(pos) or not isFinite(now) then
		if st then
			st.violations += 1
			st.burst = false
			if isFinite(now) then
				st.steppedAt = now
			end
		end
		return "flag", nil, false
	end
	if st == nil then
		-- jamais vu (pas de reset) : la première position devient la référence, sans exemption
		st = newState(pos, now)
		states[player] = st
	end
	local grace = now < st.exemptUntil or now < st.restrictedUntil
	-- début de ce tick (appel précédent ou dernière référence) : durée réelle pour la rafale
	local tickStart = st.steppedAt
	st.steppedAt = now
	st.burst = false

	-- Sol fourni (relevé par l'appui réel : altitude, vol bas) et surface analytique sous la racine
	-- (racine enfouie) : la plus basse des deux, un appui ne fait jamais paraître « enfouie » une
	-- racine debout sur le terrain ; sol inconnu (NaN) : aucune règle de hauteur relative
	local known = isFinite(groundY)
	local ground = if known then groundY else pos.Y
	local surface = if known then surfaceUnder(ground, pos.X, pos.Z) else ground
	-- racine sous la surface (passe-muraille) : hors du monde ; pendant l'exemption (personnage
	-- pas encore posé par le serveur), seulement refusée (étape 3), sans retour ni restriction
	local underground = pos.Y < surface - MAX_BELOW_GROUND

	-- Monture (INT-MOVE) : la racine debout est relevée de `offset` (vol bas, racine enfouie, altitude)
	local ride = rides[player]
	local offset = if ride then ride.offset else 0

	-- 1) bornes absolues : hors du monde, sous le monde, vol prolongé
	local dx, dz = pos.X - Cfg.CenterX, pos.Z - Cfg.CenterZ
	local outOfBounds = math.sqrt(dx * dx + dz * dz) > Cfg.MaxRadius
		or pos.Y < Cfg.MinY
		or (underground and now >= st.exemptUntil)
	if pos.Y > ground + Cfg.MaxAltitude + offset then
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
	-- vol bas ou racine enfouie prolongés, hors de portée verticale des actions (infraction à
	-- l'étape 4)
	local hovering = false
	local airborne = pos.Y > ground + HOVER_ABOVE + offset or pos.Y < surface + BURIED_BELOW + offset
	if airborne then
		local since = st.hoverSince
		if since == nil then
			st.hoverSince = now
			st.hoverFrozen = 0
		else
			-- gel réseau : position figée (aucun nouveau paquet), le serveur garde la racine reçue en
			-- haut d'un saut. Le chronomètre est décalé de la durée du tick au lieu d'avancer, au plus
			-- HOVER_FREEZE_CREDIT par écart : un gel de 0,7 à 1,5 s n'est jamais une infraction, mais
			-- planer immobile finit signalé (et planer en bougeant l'est toujours après HoverTime)
			if (pos - st.lastValid).Magnitude <= STILL_EPSILON and st.hoverFrozen < HOVER_FREEZE_CREDIT then
				local shift = math.min(math.max(0, now - tickStart), HOVER_FREEZE_CREDIT - st.hoverFrozen)
				st.hoverFrozen += shift
				since += shift
				st.hoverSince = since
			end
			if now - since > HOVER_TIME then
				hovering = true
			end
		end
	else
		st.hoverSince = nil
	end

	-- 2) déplacement par tick (depuis la dernière position valide), montée, puis vitesse soutenue ;
	-- appliqué AUSSI pendant l'exemption (seule la sanction en est levée, étape 3)
	local step = if isFinite(dt) then math.max(0, dt) else 0
	local ok = plausible(
		player,
		st.lastValid,
		st.validAt,
		pos,
		now,
		step,
		MAX_ELAPSED,
		grantExtra(st, st.validAt, now)
	)
	local usedBonus = false
	if ok then
		-- montée : même crédit d'arrêt que la mesure XZ (validAt, au plus STILL_CREDIT à l'arrêt). Un
		-- saut dont les premiers paquets arrivent groupés (gigue, fin de gel) monte de 6,7 à 7,1
		-- studs en un tick ; le vol soutenu reste borné par les règles de vol bas et d'altitude.
		-- Monture (INT-MOVE) : vitesse de départ du saut de la selle, et marge ponctuelle d'une hausse
		-- du décalage (consommée par le premier pas qui en a besoin)
		local climb = math.clamp(now - st.validAt, step, math.max(step, MAX_ELAPSED))
		local rise = pos.Y - st.lastValid.Y
		local allowed = climbSpeed(ride) * climb * Cfg.Margin + Cfg.Slack
		ok = rise <= allowed
		if not ok and ride and ride.bonus > 0 and now <= ride.bonusUntil then
			ok = rise <= allowed + ride.bonus
			usedBonus = ok
		end
	end
	if ok then
		-- fenêtre soutenue : depuis la plus ancienne position valide de la dernière seconde (le
		-- crédit d'arrêt de la mesure par tick ne dépasse jamais ce que permet cette fenêtre, même
		-- quand cette position est plus ancienne : référence sans position acceptée depuis)
		local oldest = st.history[1]
		if oldest then
			-- gel réseau : si cette position fait partie d'un arrêt QUITTÉ depuis, la fenêtre part du
			-- début de l'arrêt et s'allonge du temps écoulé depuis le départ ; au tick du départ elle
			-- vaut exactement SUSTAIN_WINDOW (crédit d'arrêt toujours borné par la fenêtre)
			local last = st.history[#st.history]
			local departing = (pos - st.lastValid).Magnitude > STILL_EPSILON and last.since < last.t
			local left = if departing then now else st.leftStillAt
			local from, window = oldest.t, SUSTAIN_WINDOW
			if oldest.since < oldest.t and oldest.since < left then
				from = oldest.since
				window = SUSTAIN_WINDOW + math.max(0, now - left)
			end
			ok = plausible(player, oldest.pos, from, pos, now, step, window, grantExtra(st, from, now))
		end
	end
	if ok and not hovering and not underground then
		-- rafale : budget d'action (seau à jetons, en-tête). Plafond = la règle pour UN tick
		-- (vmax × dt × 1,5 + 4, dt = durée réelle du tick) ; remplissage à vmax × 1,5 studs/s ;
		-- chaque position acceptée en retire sa distance depuis la dernière position valide (le
		-- balayage prev → pos des services). La dette survit au tick : bond puis action, ou chaîne
		-- de petits pas trop longs, restent des rafales jusqu'au remboursement. Le crédit d'arrêt
		-- reste une tolérance (position acceptée), jamais un bond qui agit.
		local tick = math.clamp(now - tickStart, step, math.max(step, BURST_MAX_TICK))
		local vmax = maxSpeed(player, now - tick - Cfg.SpeedWindow, now)
		local cap = vmax * tick * Cfg.Margin + Cfg.Slack
		-- bond accordé (INT-MOVE) : pendant sa fenêtre, le plafond est relevé du crédit (versé au budget
		-- par grant) ; après, l'excédent est rogné
		local ceiling = cap + grantExtra(st, now, now)
		local refill = vmax * Cfg.Margin * math.max(0, now - st.budgetAt)
		st.budget = math.min(ceiling, st.budget + refill) - distXZ(pos, st.lastValid)
		st.budgetAt = now
		local burst = st.budget < 0
		accept(st, pos, now)
		st.validAirborne = airborne
		st.validHigh = st.highSince ~= nil
		st.burst = burst
		if usedBonus and ride then
			ride.bonus = 0
		end
		return "ok", nil, burst
	end

	-- 3) exemption après une apparition ou un déplacement imposé par le serveur : position
	-- incohérente signalée (aucune action ce tick), jamais comptée, référence inchangée
	if now < st.exemptUntil then
		return "flag", nil, false
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
	return "flag", nil, false
end

-- Vérifie le déplacement du tick (voir stepOnce). Un même instant n'est jugé qu'UNE fois : un second
-- appel au même `now` avec la même position, ou avec la position de retour que le premier a imposée,
-- rend le même verdict sans rien recompter (deux appelants dans le même tick, rattrapage au même
-- instant). Toute nouvelle référence (reset, retour) oublie ce verdict.
function MoveCheck.step(
	player: Player,
	pos: Vector3,
	dt: number,
	now: number,
	groundY: number
): (Verdict, Vector3?, boolean)
	local st = states[player]
	local memo = st and st.memo
	if memo and memo.now == now and typeof(pos) == "Vector3" and finiteVector(pos) then
		local back = memo.back
		if
			(pos - memo.pos).Magnitude <= STILL_EPSILON
			or (back ~= nil and (pos - back).Magnitude <= STILL_EPSILON)
		then
			return memo.verdict, back, memo.burst
		end
	end
	local verdict, back, burst = stepOnce(player, pos, dt, now, groundY)
	local after = states[player]
	if after and finiteVector(pos) and isFinite(now) then
		after.memo = { now = now, pos = pos, verdict = verdict, back = back, burst = burst }
	end
	return verdict, back, burst
end

-- Monture (INT-MOVE) : la racine debout du joueur est relevée de `studs` (hausse de la monture,
-- bornée à [0 ; MaxRootOffset]) et sa hauteur de saut vaut `jumpHeight` (bornée à
-- [0 ; MaxJumpHeight]). Une HAUSSE accorde une marge verticale ponctuelle égale au changement, pour le
-- premier pas qui monte dans les OFFSET_BONUS_TIME s (la racine relevée arrive un ping plus tard) ; ni
-- remise à zéro de l'historique ni exemption. Valeurs non finies ignorées.
function MoveCheck.setRootOffset(player: Player, studs: number, jumpHeight: number?, now: number?)
	if type(studs) ~= "number" or not isFinite(studs) then
		return
	end
	local jump: number? = nil
	if type(jumpHeight) == "number" and isFinite(jumpHeight) then
		jump = math.clamp(jumpHeight, 0, MAX_JUMP_HEIGHT)
	end
	local t = if type(now) == "number" and isFinite(now) then now else Clock.now()
	local offset = math.clamp(studs, 0, MAX_ROOT_OFFSET)
	local ride = rides[player]
	if ride == nil then
		ride = { offset = 0, jumpHeight = nil, bonus = 0, bonusUntil = -math.huge }
		rides[player] = ride
	end
	local delta = offset - ride.offset
	ride.offset = offset
	if jump ~= nil then
		ride.jumpHeight = jump
	end
	if delta > 0 then
		ride.bonus = delta
		ride.bonusUntil = t + OFFSET_BONUS_TIME
	end
end

-- Hausse de la racine en vigueur (0 à pied) : TickActor.rootOffset, pieds = ZoneRules.feetY
function MoveCheck.rootOffset(player: Player): number
	local ride = rides[player]
	return if ride then ride.offset else 0
end

-- Bond accordé (INT-MOVE) : crédit de `studs` (12) sur `duration` (0,35 s) à partir de `tStart`
-- (instant du client, ramené dans [réception − GrantRetro ; réception]) au plafond par tick, à la
-- fenêtre soutenue et au budget d'action (une dette en cours est remboursée aussitôt : crédit
-- rétroactif). Refusé (false) si le crédit précédent a été reçu il y a moins de GrantMinGap s (horloge
-- du serveur `now`, Clock.now() par défaut) ou si le joueur n'a pas encore de position suivie.
function MoveCheck.grant(
	player: Player,
	studs: number?,
	duration: number?,
	tStart: number?,
	now: number?
): boolean
	local st = states[player]
	if st == nil then
		return false
	end
	local t = if type(now) == "number" and isFinite(now) then now else Clock.now()
	if t - st.grantAt < GRANT_MIN_GAP then
		return false
	end
	local amount = if type(studs) == "number" and isFinite(studs)
		then math.clamp(studs, 0, Tuning.GrantStuds)
		else Tuning.GrantStuds
	local length = if type(duration) == "number" and isFinite(duration)
		then math.clamp(duration, 0, Tuning.GrantDuration)
		else Tuning.GrantDuration
	local start = if type(tStart) == "number" and isFinite(tStart) then tStart else t
	start = math.clamp(start, t - GRANT_RETRO, t)
	st.grantAt = t
	st.grantStart = start
	st.grantEnd = start + length
	st.grantStuds = amount
	st.budget += amount
	return true
end

-- Position acceptée à l'instant `t` (Vector3), interpolée entre les deux échantillons de l'anneau qui
-- l'encadrent (PositionHistory s de positions acceptées) ; nil hors de l'anneau ou joueur inconnu
function MoveCheck.positionAt(player: Player, t: number): Vector3?
	local st = states[player]
	if st == nil or type(t) ~= "number" or not isFinite(t) then
		return nil
	end
	local list = st.positions
	local n = #list
	if n == 0 then
		return nil
	end
	local first, last = list[1], list[n]
	if t < first.t - POSITION_EPSILON or t > last.t + POSITION_EPSILON then
		return nil
	end
	if t >= last.t then
		return last.pos
	end
	if t <= first.t then
		return first.pos
	end
	for i = n - 1, 1, -1 do
		local a = list[i]
		if a.t <= t then
			local b = list[i + 1]
			local span = b.t - a.t
			if span <= 0 then
				return b.pos
			end
			return a.pos:Lerp(b.pos, (t - a.t) / span)
		end
	end
	return first.pos
end

-- Actions interdites (3 s après un retour)
function MoveCheck.isRestricted(player: Player, now: number): boolean
	local st = states[player]
	return st ~= nil and now < st.restrictedUntil
end

-- Le dernier tick était-il une rafale : position acceptée ("ok") mais budget d'action en dette ?
-- Un tel tick n'agit sur rien (aucune capture, aucun boop, aucun ramassage, aucune zone de jeu)
function MoveCheck.lastWasBurst(player: Player): boolean
	local st = states[player]
	return st ~= nil and st.burst
end

-- Le joueur peut-il agir depuis sa dernière position valide (lastValid) : ni restreint (retour
-- récent), ni en dette de budget d'action (rafale) ? Même règle que les actions du tick, pour les
-- lectures hors tick (remote qui exige d'être à un endroit). Joueur inconnu : rien à lui reprocher
-- (true) ; il n'a de toute façon pas de lastValid.
function MoveCheck.canAct(player: Player, now: number): boolean
	local st = states[player]
	if st == nil then
		return true
	end
	return not (now < st.restrictedUntil) and st.budget >= 0
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
	rides[player] = nil
end

return MoveCheck
