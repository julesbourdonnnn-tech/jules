--!strict
-- BuildCascade (lot B4, étape 3 ; docs/04 §27.7 ; GDD v2.0 §9.4 « Un achat », « Achat groupé »,
-- « Achats faits depuis l'écran Améliorations », « Socle → décoration », §10.7.8 ; décision D12 du plan
-- B4). Cascade de construction des décors v2.0, conduite par l'unique RenderStepped de RanchRenderer
-- (step(now), now = Clock.now(), la même horloge que push) :
--   * push(job) : job = { slot, id, parts, finals, sizes?, sound } ; les pièces attendent sous le sol
--     (rien ne se montre avant son tour) ; file de Balance.Upgrades.BuildQueueMax (10) au plus : un 11e
--     job pose tout de suite l'état final du plus ancien ; un job qui attend plus de BuildQueueSeconds
--     (10 s) est posé final ;
--   * tant que l'écran Améliorations est ouvert (PanelController.Changed, panneau du dessus
--     « Upgrades », ou Panels.Upgrades.isOpen(), les deux sous pcall), les jobs attendent, puis se
--     jouent ensemble en UNE cascade de 1,2 s ; les cascades se suivent ;
--   * un job dont le ranch n'est pas en détail complet, ou dont toutes les pièces sont derrière la
--     caméra ou à plus de 150 studs, est posé final sans animation ;
--   * chaque pièce part de 8 studs sous sa place, monte en 0,30 s (Back Out) jusqu'à l'échelle 1,15,
--     puis revient à 1 en 0,15 s ; 0,04 s entre deux pièces ; 1,2 s au plus par cascade (l'écart se
--     resserre) ; Mouvement réduit : 4 studs, sans dépassement ni changement d'échelle ;
--   * finish / flush posent toujours les CFrame (et tailles) finaux exacts ; une pièce détruite entre
--     temps est sautée sans trace ; l'état au chargement ou après un changement de ranch est posé
--     final par l'appelant (rien n'est poussé), flush(slot) termine ce qui jouait ;
--   * son TileBuild (DecoPlace pour un socle qui devient décoration, repli TileBuild sans son) pour MON
--     ranch seulement : +3 % de hauteur par pièce (+36 % au plus, 13 sons au plus par cascade) et +2 %
--     par achat de suite dans les 3 s (+24 % au plus) ; muet pendant un Rush, un MEGA, un Grand Splorch,
--     une Ascension ou la danse de Big Plop (un seul grand spectacle à la fois, D29) ;
--   * signal Piece(slot, position, index) à chaque pièce qui sort (B5 : vermicelles, squishies qui se
--     tournent vers l'objet).
-- Aucun travail par image quand la file est vide (busy() faux : RanchRenderer n'appelle pas step).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Sounds = require(Shared.Config.Sounds)
local Clock = require(Shared.Util.Clock)
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local WorldStateController = require(Client.Controllers.WorldStateController)
local AudioController = require(Client.Controllers.AudioController)

local BuildCascade = {}

export type Job = {
	slot: number,
	id: string,
	parts: { BasePart },
	finals: { CFrame },
	sizes: { Vector3 }?,
	sound: string?, -- "TileBuild" (défaut) ou "DecoPlace"
}

export type Sources = {
	now: (() -> number)?, -- horloge de push (défaut Clock.now, celle que RanchRenderer passe à step)
	detail: ((number) -> string)?, -- niveau de détail d'un ranch ("full" | "reduced")
	mySlot: (() -> number)?,
	upgradesOpen: (() -> boolean)?,
	bigShow: (() -> boolean)?,
	camera: (() -> CFrame?)?,
	reducedMotion: (() -> boolean)?,
	play: ((string, number) -> ())?,
	panelController: any, -- module PanelController (specs : faux module)
	upgradesPanel: any, -- module Panels.Upgrades (specs : faux module)
}

-- Temps de la cascade (GDD §9.4)
local RISE = 8 -- studs sous la place au départ
local RISE_REDUCED = 4 -- Mouvement réduit
local T_UP = 0.30 -- montée (Back Out) jusqu'à l'échelle 1,15
local T_SETTLE = 0.15 -- retour à 1
local PART_TIME = T_UP + T_SETTLE
local OVERSHOOT = 1.15
local START_SCALE = 0.6 -- échelle au départ (la pièce grandit en montant)
local SPACING = 0.04 -- s entre deux pièces
local MAX_RUN = 1.2 -- s au plus par cascade (achat seul ou groupé)
local QUEUE_MAX = Balance.Upgrades.BuildQueueMax
local WAIT_MAX = Balance.Upgrades.BuildQueueSeconds
local FAR = 150 -- studs : au-delà, aucune animation
local PARTS_MAX = 64 -- pièces au plus par job (au-delà : ignorées)
local RANCHES = 16
-- Sons (GDD §9.4) : +3 % par pièce (+36 % au plus), +2 % par achat de suite dans les 3 s (+24 %)
local PITCH_PART, PITCH_PART_MAX = 0.03, 0.36
local PITCH_BUY, PITCH_BUY_MAX = 0.02, 0.24
local BUY_WINDOW = 3
local SOUNDS_MAX = 13 -- sons au plus par cascade (hauteurs 0 … +36 %)
local PARK = 8 -- marge de plus sous le sol tant que la pièce attend son tour

type Live = {
	job: Job,
	n: number, -- pièces
	pushedAt: number, -- instant du push (horloge de step)
	playing: boolean,
	startAt: number,
	spacing: number,
	base: number, -- rang de sa première pièce dans la cascade
	rise: number,
	overshoot: boolean,
	mine: boolean,
	buyPitch: number,
	launched: { boolean },
	done: { boolean },
	left: number, -- pièces pas encore finies
}

-- Signal des pièces qui sortent (B5)
BuildCascade.Piece = Signal.new() :: Signal.Signal<number, Vector3, number>

local jobs: { Live } = {}
local owner: { [BasePart]: Live } = {} -- pièce → job qui l'anime
local buys: { number } = {} -- instants des achats de MON ranch (fenêtre de 3 s)
local stats = { pushed = 0, played = 0, finished = 0, maxQueue = 0, sounds = 0, pieces = 0 }

local sources: Sources = {}

-- =============================================================================================
-- Sources (défauts du vrai client ; RanchRenderer et les specs les remplacent par configure)
-- =============================================================================================

local panelWired = false
local topPanel: string? = nil
local upgradesModule: any = nil
local panelConnection: any = nil

-- Branche une fois l'écoute du panneau du dessus (PanelController.Changed) et Panels.Upgrades,
-- requis à la demande sous pcall (aucune dépendance de l'interface tant que la file est vide)
local function wirePanels()
	if panelWired then
		return
	end
	panelWired = true
	local pc: any = sources.panelController
	if pc == false then
		pc = nil
	elseif pc == nil then
		local ok, found = pcall(function(): any
			return require(Client.UI.PanelController) :: any
		end)
		pc = if ok then found else nil
	end
	if type(pc) == "table" then
		pcall(function()
			panelConnection = pc.Changed:Connect(function(top: any)
				topPanel = if type(top) == "string" then top else nil
			end)
		end)
		local ok, current = pcall(function(): any
			return pc.current()
		end)
		if ok and type(current) == "string" then
			topPanel = current
		end
	end
	local up: any = sources.upgradesPanel
	if up == false then
		up = nil
	elseif up == nil then
		local ok, found = pcall(function(): any
			return require(Client.UI.Panels.Upgrades) :: any
		end)
		up = if ok then found else nil
	end
	upgradesModule = if type(up) == "table" then up else nil
end

local function upgradesOpen(): boolean
	local fn = sources.upgradesOpen
	if fn then
		local ok, open = pcall(fn)
		return ok and open == true
	end
	wirePanels()
	if topPanel == "Upgrades" then
		return true
	end
	local up = upgradesModule
	if up ~= nil then
		local ok, open = pcall(function(): any
			return up.isOpen()
		end)
		if ok and open == true then
			return true
		end
	end
	return false
end

local function nowOf(): number
	local fn = sources.now or Clock.now
	local ok, t = pcall(fn)
	return if ok and type(t) == "number" and t == t then t else 0
end

local function detailOf(slot: number): string
	local fn = sources.detail
	if fn == nil then
		return "full"
	end
	local ok, d = pcall(fn, slot)
	if not ok then
		return "reduced"
	end
	return if d == "reduced" then "reduced" else "full"
end

local function mySlot(): number
	local fn = sources.mySlot or WorldStateController.mySlot
	local ok, s = pcall(fn)
	return if ok and type(s) == "number" then s else 0
end

-- Un grand spectacle est en cours (Rush, alerte ou MEGA, Grand Splorch, Ascension, danse de Big Plop)
local function defaultBigShow(): boolean
	local ok, ev = pcall(WorldStateController.event)
	if not ok or type(ev) ~= "table" then
		return false
	end
	local e: any = ev
	if type(e.rush) == "table" and e.rush.active == true then
		return true
	end
	local mega = e.mega
	if type(mega) == "table" and (mega.phase == "warn" or mega.phase == "press" or mega.phase == "burst") then
		return true
	end
	local spectacle = e.spectacle
	local current = if type(spectacle) == "table" then spectacle.current else nil
	if type(current) == "table" then
		local endsAt = current.endsAt
		local live = type(endsAt) ~= "number" or endsAt ~= endsAt or Clock.now() < endsAt
		if live and (current.kind == "splorch" or current.kind == "dance" or current.kind == "ascend") then
			return true
		end
	end
	return false
end

local function bigShow(): boolean
	local fn = sources.bigShow or defaultBigShow
	local ok, on = pcall(fn)
	return ok and on == true
end

local function cameraFrame(): CFrame?
	local fn = sources.camera
	if fn then
		local ok, cf = pcall(fn)
		return if ok and typeof(cf) == "CFrame" then cf else nil
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame else nil
end

local function reducedMotion(): boolean
	local fn = sources.reducedMotion or Prefs.reducedMotion
	local ok, on = pcall(fn)
	return ok and on == true
end

local function play(name: string, pitch: number)
	local fn = sources.play
	if fn then
		pcall(fn, name, pitch)
		return
	end
	pcall(AudioController.play, name, 0, pitch)
end

-- =============================================================================================
-- Outils
-- =============================================================================================

local function alive(part: BasePart): boolean
	return part.Parent ~= nil
end

local function backOut(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local y = x - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

local function quadOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

-- Son d'une cascade : DecoPlace s'il a un son, sinon TileBuild (repli du GDD §9.4)
local function soundName(job: Job): string
	local name = job.sound
	if name == "DecoPlace" then
		local def: any = (Sounds :: any).DecoPlace
		if type(def) == "table" and type(def.id) == "string" and def.id ~= "" then
			return "DecoPlace"
		end
	end
	return "TileBuild"
end

-- Pose finale exacte d'une pièce (sautée si détruite)
local function setFinal(live: Live, i: number)
	if live.done[i] then
		return
	end
	live.done[i] = true
	live.left -= 1
	local job = live.job
	local part = job.parts[i]
	if owner[part] == live then
		owner[part] = nil
	end
	if not alive(part) then
		return
	end
	local final = job.finals[i]
	if part.CFrame ~= final then
		part.CFrame = final
	end
	local sizes = job.sizes
	if sizes and part.Size ~= sizes[i] then
		part.Size = sizes[i]
	end
end

local function removeLive(live: Live)
	local i = table.find(jobs, live)
	if i then
		table.remove(jobs, i)
	end
end

-- Termine un job : toutes ses pièces à leur pose finale exacte (idempotent)
local function finishLive(live: Live)
	for i = 1, live.n do
		setFinal(live, i)
	end
	removeLive(live)
	stats.finished += 1
end

-- Gare une pièce sous le sol en attendant son tour (aucun saut visible avant la cascade)
local function park(live: Live, i: number)
	local part = live.job.parts[i]
	if not alive(part) then
		return
	end
	local sizes = live.job.sizes
	local height = if sizes then sizes[i].Y else part.Size.Y
	part.CFrame = CFrame.new(0, -(RISE + PARK + height), 0) * live.job.finals[i]
end

-- Au moins une pièce devant la caméra et à 150 studs au plus
local function visible(live: Live): boolean
	local cf = cameraFrame()
	if cf == nil then
		return false
	end
	local eye = cf.Position
	local look = cf.LookVector
	for i = 1, live.n do
		local p = live.job.finals[i].Position
		local v = p - eye
		if v.Magnitude <= FAR and v:Dot(look) > 0 then
			return true
		end
	end
	return false
end

-- Job propre (copie validée) ; nil s'il est illisible
local function clean(job: any): Job?
	if type(job) ~= "table" then
		return nil
	end
	local slot = job.slot
	if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > RANCHES then
		return nil
	end
	local parts, finals, sizesIn = job.parts, job.finals, job.sizes
	if type(parts) ~= "table" or type(finals) ~= "table" then
		return nil
	end
	local withSizes = type(sizesIn) == "table"
	local outParts: { BasePart } = {}
	local outFinals: { CFrame } = {}
	local outSizes: { Vector3 } = {}
	for i = 1, math.min(#parts, PARTS_MAX) do
		local part, final = parts[i], finals[i]
		local size = if withSizes then sizesIn[i] else nil
		if
			typeof(part) == "Instance"
			and (part :: Instance):IsA("BasePart")
			and typeof(final) == "CFrame"
			and (not withSizes or typeof(size) == "Vector3")
		then
			table.insert(outParts, part :: BasePart)
			table.insert(outFinals, final :: CFrame)
			if withSizes then
				table.insert(outSizes, size :: Vector3)
			end
		end
	end
	if #outParts == 0 then
		return nil
	end
	return {
		slot = slot,
		id = if type(job.id) == "string" then string.sub(job.id, 1, 64) else "",
		parts = outParts,
		finals = outFinals,
		sizes = if withSizes then outSizes else nil,
		sound = if job.sound == "DecoPlace" then "DecoPlace" else "TileBuild",
	}
end

-- =============================================================================================
-- Lecture d'une pièce en cours
-- =============================================================================================

-- Pose finale d'une pièce qu'une cascade anime (nil sinon) : l'appelant qui recalcule un décor lit
-- ici la vraie place d'une pièce garée ou en train de monter
function BuildCascade.finalOf(part: BasePart): CFrame?
	local live = owner[part]
	if live == nil then
		return nil
	end
	local i = table.find(live.job.parts, part)
	return if i then live.job.finals[i] else nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Remplace des sources (RanchRenderer : detail ; specs : toutes) ; les champs absents gardent les
-- valeurs déjà données
function BuildCascade.configure(options: Sources?)
	if type(options) ~= "table" then
		return
	end
	for key, value in options :: any do
		if key == "panelController" or key == "upgradesPanel" then
			(sources :: any)[key] = value -- false : module introuvable (écran compté fermé)
		elseif type(value) == "function" then
			(sources :: any)[key] = value
		elseif value == false then
			(sources :: any)[key] = nil -- false : retour à la source par défaut
		end
	end
	if options.panelController ~= nil or options.upgradesPanel ~= nil then
		if panelConnection then
			pcall(function()
				panelConnection:Disconnect()
			end)
			panelConnection = nil
		end
		panelWired = false
		topPanel = nil
		upgradesModule = nil
	end
end

-- Ajoute un job ; faux s'il est illisible (rien ne bouge). Un job hors du détail complet est posé
-- final tout de suite.
function BuildCascade.push(job: Job): boolean
	local j = clean(job)
	if j == nil then
		return false
	end
	stats.pushed += 1
	-- une pièce déjà animée : son ancien job se termine d'abord (pose finale exacte)
	for _, part in j.parts do
		local prev = owner[part]
		if prev then
			finishLive(prev)
		end
	end
	local t = nowOf()
	local live: Live = {
		job = j,
		n = #j.parts,
		pushedAt = t,
		playing = false,
		startAt = 0,
		spacing = SPACING,
		base = 0,
		rise = RISE,
		overshoot = true,
		mine = j.slot == mySlot(),
		buyPitch = 0,
		launched = {},
		done = {},
		left = #j.parts,
	}
	if detailOf(j.slot) ~= "full" then
		finishLive(live)
		return true
	end
	if live.mine then
		local recent = 0
		for i = #buys, 1, -1 do
			if t - buys[i] > BUY_WINDOW then
				table.remove(buys, i)
			else
				recent += 1
			end
		end
		live.buyPitch = math.min(PITCH_BUY_MAX, PITCH_BUY * recent)
		table.insert(buys, t)
	end
	while #jobs >= QUEUE_MAX do
		finishLive(jobs[1])
	end
	table.insert(jobs, live)
	for i, part in j.parts do
		owner[part] = live
		park(live, i)
	end
	stats.maxQueue = math.max(stats.maxQueue, #jobs)
	return true
end

-- Démarre une cascade avec tous les jobs en attente (posés finals s'ils ne sont pas visibles)
local function startGroup(now: number)
	local group: { Live } = {}
	local total = 0
	for _, live in table.clone(jobs) do
		if not live.playing then
			if detailOf(live.job.slot) ~= "full" or not visible(live) then
				finishLive(live)
			else
				table.insert(group, live)
				total += live.n
			end
		end
	end
	if #group == 0 then
		return
	end
	local spacing = if total > 1 then math.min(SPACING, (MAX_RUN - PART_TIME) / (total - 1)) else SPACING
	local reduced = reducedMotion()
	local base = 0
	for _, live in group do
		live.playing = true
		live.startAt = now
		live.spacing = spacing
		live.base = base
		live.rise = if reduced then RISE_REDUCED else RISE
		live.overshoot = not reduced
		base += live.n
	end
	stats.played += 1
end

-- Pose d'une pièce à t secondes de son départ
local function pose(live: Live, i: number, t: number)
	local job = live.job
	local part = job.parts[i]
	if not alive(part) then
		return
	end
	local final = job.finals[i]
	local sizes = job.sizes
	if t < T_UP then
		local x = t / T_UP
		local a = if live.overshoot then backOut(x) else quadOut(x)
		part.CFrame = CFrame.new(0, -live.rise * (1 - a), 0) * final
		if sizes and live.overshoot then
			part.Size = sizes[i] * (START_SCALE + (OVERSHOOT - START_SCALE) * a)
		end
	else
		part.CFrame = final
		if sizes and live.overshoot then
			local b = quadOut((t - T_UP) / T_SETTLE)
			part.Size = sizes[i] * (OVERSHOOT + (1 - OVERSHOOT) * b)
		end
	end
end

-- Une image de la cascade ; vrai s'il reste du travail (RanchRenderer n'appelle plus step sinon)
function BuildCascade.step(now: number): boolean
	if type(now) ~= "number" or now ~= now then
		return #jobs > 0
	end
	if #jobs == 0 then
		return false
	end
	for _, live in jobs do
		if live.pushedAt > now then
			live.pushedAt = now -- horloge recalée en arrière : l'attente repart de maintenant
		end
	end
	-- 10 s au plus d'attente : pose finale sans animation
	for _, live in table.clone(jobs) do
		if not live.playing and now - live.pushedAt > WAIT_MAX then
			finishLive(live)
		end
	end
	local anyPlaying = false
	for _, live in jobs do
		if live.playing then
			anyPlaying = true
			break
		end
	end
	if not anyPlaying and #jobs > 0 and not upgradesOpen() then
		startGroup(now)
	end
	local muted: boolean? = nil
	for _, live in table.clone(jobs) do
		if live.playing then
			for i = 1, live.n do
				if not live.done[i] then
					local rank = live.base + i - 1
					local t = now - (live.startAt + rank * live.spacing)
					if t >= 0 then
						if not live.launched[i] then
							live.launched[i] = true
							local part = live.job.parts[i]
							stats.pieces += 1
							BuildCascade.Piece:Fire(live.job.slot, live.job.finals[i].Position, i)
							if live.mine and rank < SOUNDS_MAX and alive(part) then
								if muted == nil then
									muted = bigShow()
								end
								if not muted then
									local pitch = 1
										+ math.min(PITCH_PART_MAX, PITCH_PART * rank)
										+ live.buyPitch
									stats.sounds += 1
									play(soundName(live.job), pitch)
								end
							end
						end
						if t >= PART_TIME then
							setFinal(live, i)
						else
							pose(live, i, t)
						end
					end
				end
			end
			if live.left <= 0 then
				removeLive(live)
			end
		end
	end
	return #jobs > 0
end

-- Termine tout de suite les jobs d'un ranch (tous sans argument) : poses finales exactes
function BuildCascade.flush(slot: number?)
	for _, live in table.clone(jobs) do
		if slot == nil or live.job.slot == slot then
			finishLive(live)
		end
	end
end

-- Termine tout de suite le job `id` d'un ranch (pose finale exacte) ; rien s'il n'existe pas
function BuildCascade.finish(slot: number, id: string)
	for _, live in table.clone(jobs) do
		if live.job.slot == slot and live.job.id == id then
			finishLive(live)
		end
	end
end

-- Il reste des jobs (en attente ou en train de jouer)
function BuildCascade.busy(): boolean
	return #jobs > 0
end

-- Compteurs (specs, Diagnostics) : jobs en file, poussés, cascades jouées, jobs terminés, plus
-- grande file vue, sons joués, pièces sorties
function BuildCascade.stats(): { [string]: number }
	return {
		queued = #jobs,
		pushed = stats.pushed,
		played = stats.played,
		finished = stats.finished,
		maxQueue = stats.maxQueue,
		sounds = stats.sounds,
		pieces = stats.pieces,
	}
end

-- Remise à zéro (specs, fin de séance) : tout ce qui jouait est posé final
function BuildCascade._reset()
	BuildCascade.flush(nil)
	table.clear(jobs)
	table.clear(owner)
	table.clear(buys)
	for key in stats do
		stats[key] = 0
	end
	if panelConnection then
		pcall(function()
			panelConnection:Disconnect()
		end)
		panelConnection = nil
	end
	panelWired = false
	topPanel = nil
	upgradesModule = nil
	sources = {}
end

return BuildCascade
