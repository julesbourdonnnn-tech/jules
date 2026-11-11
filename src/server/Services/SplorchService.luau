--!strict
-- SplorchService (paquet chase) : Grand Splorch (GDD §4.15, §6.7, §9.4).
--   * Entrée dans la file (GrandSplorch(film, flyer)) : plus gros ≥ objectif, dans son ranch (position
--     validée), rien de porté, AUCUN de ses squishies en fuite (Feedback waitEscape { species }), flyer
--     possédé et en enclos, pas déjà en file. Vérifié UNE seule fois, puis garanti :
--     SquishyService.setWaiting(flyer) (pendant l'attente, aucun squishy du joueur à la clôture),
--     EventService.enqueueSpectacle("splorch"), Feedback splorchQueued { time }.
--   * Départ (Signals.SpectacleStarted) : spectacle de 7,5 s, Celebrate "splorch" à tous (version courte
--     pour un spectateur qui a vu un spectacle complet il y a moins de FullShowGap s ; le héros a
--     toujours le spectacle complet) ; le squishy porté par le héros est posé.
--   * Éclatement (BurstAt = 3,2 s, minuteur du serveur), D'UN SEUL BLOC SANS YIELD :
--     EconomyService.applySplorch, SquishyService.resetSizes, setWaiting(nil), puis DataService.saveNow
--     (task.spawn) ; cadeaux aux autres (60 s de revenu 10 fois par jour puis 10 s, + 1 bébé sous le
--     plafond, réglage « Recevoir les cadeaux ») ; Signals.Splorched(héros, R, bébés) APRÈS les cadeaux ;
--     CommunityService.openClapWindow(héros, t + 8, spectateurs du spectacle complet) ; bannière ;
--     analytique SplorchReached (readyAtLogin), SplorchCoinsLost (multiples du Tapis 12), TileLevelAtSplorch.
--   * Départ du héros avant son tour ou avant l'éclatement : place rendue, rien remis à zéro, aucune pluie
--     de cadeaux (EventService efface le spectacle en cours, remarque A26).
-- Émet Splorched (Grand Splorch seulement : jamais pour un Petit Splorch, lot A4 D3) ; jamais
-- EventService.addGauge (la jauge vient de Splorched et de PrestigeApplied). Remote : GrandSplorch.
--
-- v2.0 (lot A2, étape 3 ; docs/04 §27.4, §27.5, §27.7, §27.14 ; GDD v2.0 §4.15, §4.26, §4.27).
-- Progression v2.0 en vigueur = EconomyService.prestigeV2 (profil v2, RecordR ouvert, configuration
-- acceptée) ; sinon tout ce qui suit est absent et le Grand Splorch reste celui de la v1.3 au bit près :
--   * Grand Splorch : EconomyService.applyPrestige (Prestige.apply, seul écrivain des champs gardés et
--     remis à zéro ; cadeau du Splorch dans le Pot) au lieu d'applySplorch ; Confettis versés par
--     EconomyService.addConfetti, une source par part (splorch, record, petit, ascend, skipped, regain,
--     fullPen) ; Fame + 5 dans le plafond du jour (CapsV2.fameSplorch = 50) ; une bannière par joueur
--     au plus toutes les SplorchV2.BannerGap s ; place offerte (RanchService.offeredPlace) ; signaux
--     PrestigeApplied et RecordReached ; préparation revérifiée au départ du spectacle (squishy vendu
--     pendant l'attente : place rendue, rien remis à zéro) ;
--   * Petit Splorch [PetitSplorch] (r après la renaissance ≤ Record R) : mêmes conditions d'entrée,
--     HORS de la file, appliqué tout de suite d'un seul bloc ; Celebrate « petitSplorch » au joueur,
--     attribut PetitSplorchAt ; ni bannière, ni cadeaux aux autres, ni Fame ; retour au record : + 10
--     Confettis et Celebrate « regainDone » ; PrestigeApplied(« petit ») seulement, jamais Splorched
--     (GDD m9 : ni stats.splorches, ni objectif du jour ; jauge 5 par EventService, fête 0 ; lot A4 D3) ;
--   * Jelly Ascend [JellyAscend] (intention JellyAscend(confirm)) : Prestige.ascendReady et les
--     conditions d'entrée vérifiés une seule fois, à l'entrée dans la MÊME file que le Grand Splorch
--     (EventService, sorte « ascend » depuis le lot A4 : 10 s, coupure 12 s, place effacée avant 4,0 s) ;
--     un seul prestige par joueur dans la file (« Ton Grand Splorch
--     passe d'abord ! ») ; spectacle de Balance.Ascend.Duration s (Celebrate « ascend » à tous, copie
--     de la taille du Meilleur Ami n° 1) ; Prestige.apply à BurstAt (4,0 s) d'un seul bloc, puis
--     sauvegarde ; Pluie d'étoiles pour les autres (StarRainSeconds de revenu, CapsV2.starRain par jour,
--     un bébé dans les 10 cadeaux du jour) ; Banner « ascend » ; Fame + 20 hors plafond ;
--   * Record absolu (r = MaxR) : Grand Splorch refusé pour tout profil v2, progression v2.0 coupée
--     comprise (relecture du lot A2 : r jamais au-delà de MaxR) ;
--   * idempotence : un prestige par joueur à la fois (canPrestige) ; Prestige.apply ne fait rien deux
--     fois ; rien n'est appliqué si le joueur est parti, si la session se termine (départ, BindToClose :
--     DataService.isClosing) ou si la configuration est refusée ; aucun yield entre Prestige.apply et le
--     dernier versement (une sauvegarde voit tout le prestige ou rien) ;
--   * sonde « occupé » d'EconomyService : spectacle du joueur (Grand Splorch, Ascension) et animation
--     du Petit Splorch ; attributs Ascend et AscendReady [JellyAscend] posés toutes les secondes.
-- Émet aussi PrestigeApplied, RecordReached. Remote : JellyAscend.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Features = require(Shared.Config.Features)
local Hash = require(Shared.Logic.Hash)
local Formulas = require(Shared.Logic.Formulas)
local Prestige = require(Shared.Logic.Prestige)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local WorldLayout = require(Shared.Logic.WorldLayout)
local StateTimeouts = require(Shared.Logic.StateTimeouts)

local Server = script.Parent.Parent
local Signals = require(Server.Signals)
local Notify = require(Server.Util.Notify)
local MoveCheck = require(Server.Util.MoveCheck)
local Guard = require(Server.Chase.Guard)
local Babies = require(Server.Chase.Babies)
local PadRules = require(Server.Ranch.PadRules)

local DataService = require(script.Parent.DataService)
local RanchService = require(script.Parent.RanchService)
local EconomyService = require(script.Parent.EconomyService)
local SquishyService = require(script.Parent.SquishyService)
local CommunityService = require(script.Parent.CommunityService)
local EventService = require(script.Parent.EventService)
local DiagnosticsService = require(script.Parent.DiagnosticsService)

local SplorchService = {}

-- =============================================================================================
-- État
-- =============================================================================================

local SPLORCH = Balance.Splorch
local CLAP_WINDOW = StateTimeouts.seconds("clapWindow")
local HARD_CUT = Events.Spectacles.splorch.hardCut
local SNACK_LOOP_LEVEL = Balance.Tiles.snack.Levels - 1 -- Tapis 12 (niveau 11 → 12)
-- Borne absolue d'une attente tenue par EventService : coupure dure de la tête de file, puis un grand
-- spectacle par place (16 Grands Splorch et une danse, écart compris) et le dernier spectacle
local MAX_SPECTACLES = 17
local QUEUE_LIMIT = Events.SplorchQueueHardCut
	+ MAX_SPECTACLES * (Events.SpectacleGap + StateTimeouts.seconds("spectacle"))
	+ StateTimeouts.seconds("spectacle")

-- v2.0 (lot A2)
local ASCEND = Balance.Ascend
local CONFETTI = Balance.Confetti
local SPLORCH_V2 = Balance.SplorchV2
local MAX_R = Balance.Prestige.MaxR
local PETIT_SHOW = SPLORCH_V2.PetitShow.Duration
local ATTR_EVERY = 1 -- s : attributs Ascend et AscendReady du ranch [JellyAscend]

-- sorte d'une entrée de la file et d'un spectacle : Grand Splorch ou Jelly Ascend (même file)
type ShowKind = "splorch" | "ascend"
type Queued = { flyer: string, at: number, film: boolean, kind: ShowKind }
type Show = {
	kind: ShowKind,
	hero: Player,
	startedAt: number,
	burstAt: number,
	endsAt: number,
	cutAt: number, -- coupure dure (Grand Splorch 10 s, Ascension 12 s)
	flyer: { s: number, m: number, st: number, z: number },
	flyerUid: string,
	level: number,
	short: { [Player]: boolean }, -- version courte par spectateur (décidée au départ)
	full: { Player }, -- spectateurs du spectacle complet (APPLAUDIR)
	burst: boolean,
}

local queued: { [Player]: Queued } = {}
local shows: { [Player]: Show } = {}
local lastFull: { [Player]: number } = {} -- dernier spectacle complet vu (mémoire de session)
local readyAtLogin: { [Player]: boolean } = {}
local lastSplorchAt: { [Player]: number } = {}
local petitUntil: { [Player]: number } = {} -- fin de l'animation du Petit Splorch (Clock.now())
local nextAttrs: { [Player]: number } = {}
local attrsSet: { [Player]: { [string]: boolean } } = {} -- attributs v2.0 posés par ce service
-- dernière bannière de Grand Splorch par joueur (userId → Clock.now(), progression v2.0) : gardée au
-- retour sur le même serveur, élaguée au-delà de BannerGap
local lastBanner: { [number]: number } = {}
local counters: { [string]: number } = {} -- prestiges refusés (filets), compteurs de Diagnostics

-- =============================================================================================
-- Aides
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function profile(player: Player): { [string]: any }?
	if not DataService.isLoaded(player) then
		return nil
	end
	return DataService.get(player)
end

local function displayName(player: Player): string
	local value = Guard.call("splorch:displayName", CommunityService.displayName, "", player)
	return if type(value) == "string" then value else ""
end

local function receivesGifts(player: Player): boolean
	local data = profile(player)
	local stored = not (data and type(data.settings) == "table" and data.settings.receiveGifts == false)
	local value = Guard.call("splorch:receiveGifts", CommunityService.setting, stored, player, "receiveGifts")
	return value ~= false
end

local function ready(player: Player): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local _, biggest = SquishyService.biggest(player)
	return finite(biggest) and biggest >= Formulas.splorchTarget(EconomyService.R(player))
end

-- =============================================================================================
-- v2.0 (lot A2) : progression, prestige en cours, versements
-- =============================================================================================

-- Compte un prestige refusé par un filet (Diagnostics : DiagnosticsService.count quand le lot A4
-- l'ajoute, note INT-A2-DIAG ; SplorchService.counters d'ici là) ; jamais une trace
local function diag(key: string, player: Player?)
	counters[key] = (counters[key] or 0) + 1
	local count = (DiagnosticsService :: any).count
	if type(count) == "function" then
		Guard.try("splorch:diag", count, key, player)
	end
end

-- Progression v2.0 en vigueur pour ce joueur (EconomyService.prestigeV2)
local function v2(player: Player): boolean
	return Guard.call("splorch:prestigeV2", EconomyService.prestigeV2, false, player) == true
end

-- Petit Splorch hors file [PetitSplorch]
local function petitOn(player: Player): boolean
	return Features.get("PetitSplorch") == true and v2(player)
end

-- Jelly Ascend [JellyAscend]
local function ascendOn(player: Player): boolean
	return Features.get("JellyAscend") == true and v2(player)
end

-- Animation du Petit Splorch en cours (2,5 s après son application)
local function petitBusy(player: Player, now: number): boolean
	local untilT = petitUntil[player]
	return untilT ~= nil and now < untilT
end

-- Un prestige est-il en cours pour ce joueur (file, spectacle, attente, animation du Petit Splorch) ?
local function prestigeInProgress(player: Player, now: number): boolean
	return queued[player] ~= nil
		or shows[player] ~= nil
		or SquishyService.waiting(player) ~= nil
		or petitBusy(player, now)
end

-- Conditions d'entrée communes (GDD §4.15 : dans son ranch, rien porté, aucun squishy en fuite),
-- vérifiées une seule fois ; refus = Feedback neutre
local function entryOk(player: Player): boolean
	local slot = RanchService.slotOf(player)
	local pos = MoveCheck.lastValid(player)
	if slot == 0 or pos == nil or not WorldLayout.inRanch(slot, pos) then
		Notify.feedback(player, "feedback.onlyOwnRanch", {}, "info")
		return false
	end
	if SquishyService.carried(player) ~= nil then
		Notify.feedback(player, "feedback.carrying", {}, "info")
		return false
	end
	local escaping = SquishyService.anyEscaping(player)
	if escaping ~= nil then
		local rec = SquishyService.get(player, escaping)
		Notify.feedback(player, "feedback.waitEscape", { species = if rec then rec.s else 0 }, "info")
		return false
	end
	return true
end

-- Squishy qui monte dans le faisceau de la Jelly Ascend : Meilleur Ami n° 1 (puis 2, 3), sinon le plus
-- gros de l'enclos ou du Bassin
local function ascendFlyer(player: Player): string?
	for slot = 1, 3 do
		local uid = SquishyService.bestFriend(player, slot)
		if uid ~= nil and SquishyService.get(player, uid) ~= nil then
			return uid
		end
	end
	local uid = SquishyService.biggest(player)
	return uid
end

-- Confettis d'une part (0 : rien), par EconomyService.addConfetti (seul point d'entrée des gains)
local function pay(player: Player, n: number, source: string): number
	if not finite(n) or n < 1 then
		return 0
	end
	local credited = Guard.call("splorch:confetti", EconomyService.addConfetti, 0, player, n, source)
	return if finite(credited) then credited else 0
end

-- Versements d'un prestige appliqué, dans le même bloc : Confettis par source (le gain du prestige
-- séparé de la prime de record et des Grands Splorch sautés grâce au Tremplin ; retour au record ;
-- enclos plein), Fame (Grand Splorch dans le plafond du jour CapsV2.fameSplorch, Ascension hors
-- plafond, Petit Splorch : aucune). Rend (Confettis du retour au record, Confettis de l'enclos plein)
local function payout(player: Player, report: Prestige.ApplyReport): (number, number)
	local base = report.confettiBase
	if report.kind == "splorch" then
		local record = if report.toR >= CONFETTI.RecordBonusFrom then CONFETTI.RecordBonus else 0
		if record > base then
			record = 0
		end
		pay(player, base - record, "splorch")
		pay(player, record, "record")
	elseif report.kind == "petit" then
		pay(player, base, "petit")
	elseif report.kind == "ascend" then
		local skipped = math.min(base, CONFETTI.PerSkipped * report.skipped)
		pay(player, base - skipped, "ascend")
		pay(player, skipped, "skipped")
	end
	local regain = if report.regain then pay(player, CONFETTI.RegainBonus, "regain") else 0
	local fullPen = if report.fullPen then pay(player, CONFETTI.FullPenBonus, "fullPen") else 0
	local fame = if finite(report.fame) then math.floor(report.fame) else 0
	if fame > 0 and report.kind ~= "ascend" then
		fame = EconomyService.consumeCap(player, "fameSplorch", fame)
	end
	if fame > 0 then
		EconomyService.addFame(player, fame, "splorch")
	end
	return regain, fullPen
end

-- Attributs Ascend et AscendReady du ranch [JellyAscend] ; PetitSplorchAt effacé quand PetitSplorch est
-- coupé ; un interrupteur coupé efface ce que ce service avait posé (rien de posé tant que tout est coupé)
local function refreshAttrs(player: Player)
	local data = profile(player)
	if data == nil then
		return
	end
	local set = attrsSet[player]
	local attrs: { [string]: any } = {}
	local clear: { string } = {}
	if ascendOn(player) then
		attrs.Ascend = Prestige.ascend(data)
		attrs.AscendReady = Prestige.ascendReady(data)
	elseif set ~= nil and set.Ascend then
		table.insert(clear, "Ascend")
		table.insert(clear, "AscendReady")
	end
	if set ~= nil and set.PetitSplorchAt and not petitOn(player) then
		table.insert(clear, "PetitSplorchAt")
	end
	if next(attrs) == nil and #clear == 0 then
		return
	end
	if set == nil then
		set = {}
		attrsSet[player] = set
	end
	for name in attrs do
		set[name] = true
	end
	for _, name in clear do
		set[name] = nil
	end
	RanchService.setV2Attributes(player, attrs, clear)
end

-- Suites d'un prestige appliqué (même bloc) : place offerte, carte du retour au record, attributs,
-- signaux de la v2.0
local function after(
	player: Player,
	report: Prestige.ApplyReport,
	fromR: number,
	regain: number,
	fullPen: number
)
	if report.offeredPen or report.fullPen then
		RanchService.offeredPlace(player, report.fullPen, fullPen)
	end
	if report.regain then
		Notify.celebrate(player, "regainDone", { bestR = report.bestR, confetti = regain })
	end
	refreshAttrs(player)
	Signals.PrestigeApplied:Fire(player, report.kind, fromR, report.toR, report.ascend)
	if report.record then
		Signals.RecordReached:Fire(player, report.bestR)
	end
end

-- Sauvegarde tout de suite après un prestige (jamais de yield dans le bloc)
local function saveSoon(player: Player)
	task.spawn(function()
		Guard.try("splorch:save", DataService.saveNow, player)
	end)
end

-- Bannière « GRAND SPLORCH » du héros : au plus une toutes les BannerGap s (progression v2.0)
local function bannerAllowed(player: Player, now: number): boolean
	local last = lastBanner[player.UserId]
	if last ~= nil and now - last < SPLORCH_V2.BannerGap then
		return false
	end
	for userId, at in lastBanner do
		if now - at >= SPLORCH_V2.BannerGap then
			lastBanner[userId] = nil
		end
	end
	lastBanner[player.UserId] = now
	return true
end

-- =============================================================================================
-- Petit Splorch (hors file, appliqué tout de suite)
-- =============================================================================================

-- Petit Splorch d'un bloc (entrée déjà vérifiée) : Prestige.apply, tailles répliquées, sauvegarde,
-- 1 Confetti (+ 10 au retour au record), Celebrate « petitSplorch » au joueur, PetitSplorchAt ; rien
-- pour les autres (ni bannière, ni cadeaux, ni Fame). Rend true si le Petit Splorch est appliqué
local function applyPetit(player: Player): boolean
	local data = profile(player)
	if data == nil or DataService.isClosing(player) then
		return false
	end
	local now = Clock.now()
	local fromR = Prestige.r(data)
	local _, report = EconomyService.applyPrestige(player, "petit")
	if report == nil or not report.applied then
		diag("PrestigeRefused", player)
		Notify.feedback(player, "feedback.splorchNotReady", {}, "info")
		return false
	end
	SquishyService.resetSizes(player)
	local regain, fullPen = payout(player, report)
	petitUntil[player] = now + PETIT_SHOW
	RanchService.setV2Attributes(player, { PetitSplorchAt = now })
	local set = attrsSet[player] or {}
	set.PetitSplorchAt = true
	attrsSet[player] = set
	Notify.celebrate(
		player,
		"petitSplorch",
		{
			userId = player.UserId,
			level = report.toR,
			startedAt = now,
			endsAt = now + PETIT_SHOW,
		} :: Types.CelebratePetitSplorch
	)
	after(player, report, fromR, regain, fullPen)
	-- sauvegarde APRÈS le dernier versement : l'instantané écrit tout le prestige (Confettis compris).
	-- Aucun Splorched (= Grand Splorch seulement, lot A4 D3, GDD m9) : PrestigeApplied(« petit ») dans after
	saveSoon(player)
	Guard.analytics(player, "PetitSplorch", report.toR, { bestR = report.bestR, ascend = report.ascend })
	lastSplorchAt[player] = now
	readyAtLogin[player] = false
	return true
end

-- =============================================================================================
-- Entrée dans la file (vérifiée une seule fois)
-- =============================================================================================

local function onGrandSplorch(player: Player, film: boolean, flyer: string): boolean
	local data = profile(player)
	if data == nil then
		return false
	end
	local now = Clock.now()
	if prestigeInProgress(player, now) then
		Notify.feedback(player, "feedback.waitingSplorch", {}, "info")
		return false
	end
	local progression = v2(player)
	-- Record absolu (r = MaxR) : refusé pour tout profil v2, progression v2.0 coupée comprise (le
	-- Grand Splorch de la v1.3 passerait r à MaxR + 1 : invariant v2 cassé, relecture du lot A2)
	if (progression or PadRules.v2Profile(data)) and Prestige.r(data) >= MAX_R then
		Notify.feedback(player, "splorch.recordAbsolute", {}, "info")
		return false
	end
	if not ready(player) then
		Notify.feedback(player, "feedback.splorchNotReady", {}, "info")
		return false
	end
	if not entryOk(player) then
		return false
	end
	local rec = SquishyService.get(player, flyer)
	if rec == nil or rec.at ~= "pen" then
		Notify.feedback(player, "feedback.notOwned", {}, "info")
		return false
	end
	-- Petit Splorch (r après la renaissance ≤ Record R) [PetitSplorch] : hors file, tout de suite
	if progression and petitOn(player) and Prestige.nextKind(data) == "petit" then
		return applyPetit(player)
	end
	-- garanti à partir d'ici
	SquishyService.setWaiting(player, flyer)
	queued[player] = { flyer = flyer, at = now, film = film == true, kind = "splorch" }
	local startAt = EventService.enqueueSpectacle("splorch", player.UserId)
	Notify.feedback(
		player,
		"feedback.splorchQueued",
		{ time = math.max(0, math.ceil(startAt - now)) },
		"success"
	)
	return true
end

-- Jelly Ascend (intention JellyAscend(confirm)) [JellyAscend] : confirm = true exigé ; Prestige.ascendReady
-- et les conditions d'entrée vérifiés une seule fois ; place dans la MÊME file que le Grand Splorch ;
-- un seul prestige par joueur. Interrupteur coupé, profil v1, confirmation absente, condition fausse :
-- rien (aucune réponse) ; rend true si l'Ascension entre dans la file
local function onJellyAscend(player: Player, confirm: boolean): boolean
	if confirm ~= true or not ascendOn(player) then
		return false
	end
	local data = profile(player)
	if data == nil or DataService.isClosing(player) then
		return false
	end
	local now = Clock.now()
	local entry = queued[player]
	local show = shows[player]
	if (entry ~= nil and entry.kind == "ascend") or (show ~= nil and show.kind == "ascend") then
		return false -- déjà en file ou en spectacle : la même Ascension, rien de plus (idempotent)
	end
	if entry ~= nil or show ~= nil then
		Notify.feedback(player, "ascend.queued", {}, "info") -- « Ton Grand Splorch passe d'abord ! »
		return false
	end
	if prestigeInProgress(player, now) then
		Notify.feedback(player, "feedback.waitingSplorch", {}, "info")
		return false
	end
	local ok = EconomyService.configOk()
	if not ok then
		diag("AscendConfigRefused", player)
		Notify.feedback(player, "upgrades.refused.busy", {}, "info")
		return false
	end
	if not Prestige.ascendReady(data) then
		return false
	end
	if not entryOk(player) then
		return false
	end
	local flyer = ascendFlyer(player)
	if flyer == nil then
		Notify.feedback(player, "feedback.notOwned", {}, "info")
		return false
	end
	-- garanti à partir d'ici (rien n'est revérifié au départ, sauf ce qui rendrait Prestige.apply sans
	-- effet : interrupteur, configuration, condition, fin de session)
	SquishyService.setWaiting(player, flyer)
	queued[player] = { flyer = flyer, at = now, film = false, kind = "ascend" }
	EventService.enqueueSpectacle("ascend", player.UserId)
	return true
end

-- =============================================================================================
-- Spectacle
-- =============================================================================================

-- Place rendue au départ du spectacle (filet) : rien n'est remis à zéro
local function giveBack(hero: Player, reason: string)
	EventService.cancelSpectacle(hero.UserId)
	Guard.try("splorch:waiting", SquishyService.setWaiting, hero, nil)
	diag(reason, hero)
end

-- Départ d'une Jelly Ascend : spectacle de Balance.Ascend.Duration s, Celebrate « ascend » à tous
-- (Types.CelebrateAscend : taille du Meilleur Ami copiée au début, départ et Record R prévus)
local function startAscend(hero: Player, entry: Queued, t: number)
	local data = profile(hero)
	local rec = SquishyService.get(hero, entry.flyer)
	local ok = data ~= nil
		and rec ~= nil
		and ascendOn(hero)
		and EconomyService.configOk()
		and not DataService.isClosing(hero)
		and Prestige.ascendReady(data :: any)
	if not ok or data == nil or rec == nil then
		giveBack(hero, "AscendCancelled")
		return
	end
	if SquishyService.carried(hero) ~= nil then
		SquishyService.endCarry(hero, "splorch")
	end
	local A = Prestige.ascend(data) + 1
	local startR = Prestige.startR(A, UpgradeMath.level("springboard", data))
	local flyer = { s = rec.s, m = rec.m, st = rec.st, z = SquishyService.sizeOf(hero, entry.flyer) }
	local show: Show = {
		kind = "ascend",
		hero = hero,
		startedAt = t,
		burstAt = t + ASCEND.BurstAt,
		endsAt = t + ASCEND.Duration,
		cutAt = t + ASCEND.HardCut,
		flyer = flyer,
		flyerUid = entry.flyer,
		level = startR,
		short = {},
		full = {},
		burst = false,
	}
	shows[hero] = show
	EventService.describeSpectacle(hero.UserId, flyer, startR)
	local payload: Types.CelebrateAscend = {
		userId = hero.UserId,
		ascend = A,
		startR = startR,
		bestR = Prestige.bestR(data),
		startedAt = t,
		burstAt = show.burstAt,
		endsAt = show.endsAt,
		flyer = flyer,
	}
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			Notify.celebrate(player, "ascend", payload :: any)
		end
	end
end

-- Départ d'un grand spectacle d'EventService : sorte « splorch » (Grand Splorch) ou « ascend » (Jelly
-- Ascend, lot A4) ; la sorte du spectacle et celle de l'entrée du joueur vont ensemble (filet sinon :
-- place rendue, rien n'est appliqué, le joueur peut recommencer)
local function onSpectacleStarted(kind: string, userId: number, t: number)
	if kind ~= "splorch" and kind ~= "ascend" then
		return
	end
	local hero = Players:GetPlayerByUserId(userId)
	if hero == nil then
		return
	end
	local entry = queued[hero]
	queued[hero] = nil
	if kind == "ascend" or (entry ~= nil and entry.kind == "ascend") then
		if kind == "ascend" and entry ~= nil and entry.kind == "ascend" then
			startAscend(hero, entry, t)
		else
			giveBack(hero, "AscendCancelled")
		end
		return
	end
	local flyerUid = (entry and entry.flyer) or SquishyService.waiting(hero)
	local rec = if flyerUid then SquishyService.get(hero, flyerUid) else nil
	if flyerUid == nil or rec == nil then
		-- squishy introuvable (filet) : la place est rendue, rien n'est remis à zéro
		EventService.cancelSpectacle(userId)
		Guard.try("splorch:waiting", SquishyService.setWaiting, hero, nil)
		return
	end
	-- progression v2.0 : Prestige.apply n'appliquerait rien (plus gros vendu ou relâché pendant
	-- l'attente) : place rendue avant tout spectacle, rien n'est remis à zéro
	local data = profile(hero)
	if data ~= nil and v2(hero) and not Prestige.splorchReady(data, t) then
		giveBack(hero, "SplorchNotReadyAtStart")
		return
	end
	if SquishyService.carried(hero) ~= nil then
		SquishyService.endCarry(hero, "splorch")
	end
	local level = EconomyService.R(hero) + 1
	local flyer = { s = rec.s, m = rec.m, st = rec.st, z = SquishyService.sizeOf(hero, flyerUid) }
	local show: Show = {
		kind = "splorch",
		hero = hero,
		startedAt = t,
		burstAt = t + SPLORCH.BurstAt,
		endsAt = t + SPLORCH.Duration,
		cutAt = t + HARD_CUT,
		flyer = flyer,
		flyerUid = flyerUid,
		level = level,
		short = {},
		full = {},
		burst = false,
	}
	shows[hero] = show
	EventService.describeSpectacle(userId, flyer, level)
	for _, player in Players:GetPlayers() do
		if RanchService.isReady(player) then
			local short = false
			if player ~= hero then
				local last = lastFull[player]
				short = last ~= nil and t - last < SPLORCH.FullShowGap
				if not short then
					lastFull[player] = t
					table.insert(show.full, player)
				end
			end
			show.short[player] = short
			Notify.celebrate(player, "splorch", {
				userId = userId,
				level = level,
				flyer = flyer,
				startedAt = t,
				burstAt = show.burstAt,
				endsAt = show.endsAt,
				short = short,
			})
		end
	end
end

-- Cadeaux à un autre joueur : pièces (10 par jour, ensuite 10 s), + 1 bébé sous le plafond
local function gift(show: Show, player: Player): number
	if player.Parent == nil or profile(player) == nil or not receivesGifts(player) then
		return 0
	end
	local seconds = if EconomyService.consumeCap(player, "splorchCoins", 1) > 0
		then SPLORCH.GiftSeconds
		else Balance.Rewards.GiftSecondsAfterCap
	local coins = EconomyService.addIncomeSeconds(player, seconds, "SplorchGift")
	local babyUid, species, given = "", 0, 0
	if EconomyService.consumeCap(player, "splorchGifts", 1) > 0 then
		local _, biggest = SquishyService.biggest(player)
		local rng = Hash.stream(Hash.u32(show.hero.UserId, player.UserId, math.floor(show.startedAt * 10)))
		local baby = Babies.gift(rng, show.flyer.s, show.flyer.m, biggest)
		local uid = SquishyService.give(player, Babies.spec(baby), "gift")
		babyUid = uid or ""
		species = baby.s
		given = 1
	end
	local short = show.short[player]
	Notify.celebrate(player, "giftRain", {
		heroId = show.hero.UserId,
		heroName = displayName(show.hero),
		coins = coins,
		uid = babyUid,
		species = species,
		short = short == true,
	})
	return given
end

-- Pluie d'étoiles d'une Jelly Ascend pour un autre joueur (GDD §4.27, étape 6) : StarRainSeconds de son
-- revenu (CapsV2.starRain par jour, ensuite rien), + 1 bébé de l'espèce du Meilleur Ami dans les
-- 10 bébés de cadeau du jour ; réglage « Recevoir les cadeaux ». Envoyée comme un Celebrate « giftRain »
-- (charge du jeu de base) dont heroId est le héros du Celebrate « ascend » en cours
local function starRain(show: Show, player: Player): number
	if player.Parent == nil or profile(player) == nil or not receivesGifts(player) then
		return 0
	end
	local coins = 0
	if EconomyService.consumeCap(player, "starRain", 1) > 0 then
		coins = EconomyService.addIncomeSeconds(player, ASCEND.StarRainSeconds, "StarRain")
	end
	local babyUid, species, given = "", 0, 0
	if EconomyService.consumeCap(player, "splorchGifts", 1) > 0 then
		local _, biggest = SquishyService.biggest(player)
		local rng =
			Hash.stream(Hash.u32(show.hero.UserId, player.UserId, math.floor(show.startedAt * 10) + 7))
		local baby = Babies.gift(rng, show.flyer.s, show.flyer.m, biggest)
		local uid = SquishyService.give(player, Babies.spec(baby), "gift")
		babyUid = uid or ""
		species = baby.s
		given = 1
	end
	if coins <= 0 and given == 0 then
		return 0
	end
	Notify.celebrate(player, "giftRain", {
		heroId = show.hero.UserId,
		heroName = displayName(show.hero),
		coins = coins,
		uid = babyUid,
		species = species,
		short = false,
	})
	return given
end

-- Les autres joueurs, dans l'ordre des userId (cadeaux reproductibles)
local function othersOf(hero: Player): { Player }
	local others = {}
	for _, player in Players:GetPlayers() do
		if player ~= hero then
			table.insert(others, player)
		end
	end
	table.sort(others, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	return others
end

-- Éclatement d'une Jelly Ascend (Balance.Ascend.BurstAt) : Prestige.apply d'un seul bloc, sans yield,
-- puis sauvegarde, versements, Pluie d'étoiles, bannière. Rien n'est appliqué si la session se termine
-- (départ, BindToClose), si l'interrupteur ou la configuration ne le permettent plus : l'Ascension
-- reste possible à la session suivante, jamais à moitié faite
local function burstAscend(show: Show, now: number)
	show.burst = true
	local hero = show.hero
	local data = profile(hero)
	if data == nil or hero.Parent == nil then
		return
	end
	if DataService.isClosing(hero) or not ascendOn(hero) or not EconomyService.configOk() then
		SquishyService.setWaiting(hero, nil)
		diag("AscendCancelled", hero)
		return
	end
	local fromR = Prestige.r(data)
	local _, report = EconomyService.applyPrestige(hero, "ascend")
	if report == nil or not report.applied then
		SquishyService.setWaiting(hero, nil)
		diag("PrestigeRefused", hero)
		return
	end
	-- jours depuis la précédente (lot I, D5 ; GDD §16 « A, r, jours depuis la précédente ») : depuis la
	-- dernière Ascension (ascendDay) ; la première : depuis la première arrivée (firstJoin) ; 0 si aucun
	-- des deux n'est lisible ; jamais négatif (horloge reculée)
	local today = Clock.day()
	local since = 0
	local last = data.ascendDay
	local first = data.firstJoin
	if type(last) == "number" and last == last and last > 0 and last ~= math.huge then
		since = math.max(0, today - math.floor(last))
	elseif type(first) == "number" and first == first and first > 0 and first ~= math.huge then
		since = math.max(0, today - Clock.day(first))
	end
	-- jour de cette Ascension (lu à la suivante)
	data.ascendDay = today
	DataService.markDirty(hero, "ascendDay")
	SquishyService.resetSizes(hero)
	SquishyService.setWaiting(hero, nil)
	local regain, fullPen = payout(hero, report)
	after(hero, report, fromR, regain, fullPen)
	-- sauvegarde APRÈS le dernier versement : l'instantané écrit tout le prestige (Confettis compris)
	saveSoon(hero)
	for _, player in othersOf(hero) do
		Guard.try("splorch:starRain", starRain, show, player)
	end
	Notify.banner("ascend", { userId = hero.UserId, name = displayName(hero), ascend = report.ascend }, hero)
	Guard.analytics(hero, "AscendDone", report.ascend, { r = fromR, bestR = report.bestR, days = since })
	lastSplorchAt[hero] = now
	readyAtLogin[hero] = false
end

-- Éclatement : application au profil d'un seul bloc, sans yield
local function burst(show: Show, now: number)
	if show.kind == "ascend" then
		burstAscend(show, now)
		return
	end
	show.burst = true
	local hero = show.hero
	local data = profile(hero)
	if data == nil or hero.Parent == nil then
		return
	end
	local R0 = EconomyService.R(hero)
	local tiles = type(data.tiles) == "table" and data.tiles or {}
	local snackBefore = if finite(tiles.snack) then tiles.snack else 0
	local decorBefore = if finite(tiles.decor) then tiles.decor else 0
	local progression = v2(hero)
	local report: Prestige.ApplyReport? = nil
	local lost: number
	if progression then
		-- progression v2.0 : Prestige.apply (session qui se termine : rien, la place est rendue)
		if DataService.isClosing(hero) then
			SquishyService.setWaiting(hero, nil)
			diag("SplorchCancelled", hero)
			return
		end
		local _, applied = EconomyService.applyPrestige(hero, "splorch")
		if applied == nil or not applied.applied then
			SquishyService.setWaiting(hero, nil)
			diag("PrestigeRefused", hero)
			return
		end
		report = applied
		lost = applied.lost
	else
		lost = EconomyService.applySplorch(hero)
	end
	SquishyService.resetSizes(hero)
	SquishyService.setWaiting(hero, nil)
	if report ~= nil then
		-- progression v2.0 : versements et suites dans le même bloc, puis la sauvegarde (l'instantané
		-- écrit tout le prestige, Confettis compris)
		local regain, fullPen = payout(hero, report)
		after(hero, report, R0, regain, fullPen)
	end
	saveSoon(hero)
	-- cadeaux pour chaque autre joueur (payés par le jeu, jamais pris au héros)
	local given = 0
	for _, player in othersOf(hero) do
		local ok, n = Guard.try("splorch:gift", gift, show, player)
		if ok and finite(n) then
			given += n
		end
	end
	local newR = EconomyService.R(hero)
	Signals.Splorched:Fire(hero, newR, given)
	Guard.call(
		"splorch:clap",
		CommunityService.openClapWindow,
		nil,
		hero,
		show.startedAt + CLAP_WINDOW,
		show.full
	)
	-- bannière : au plus une toutes les BannerGap s par joueur avec la progression v2.0
	if report == nil or bannerAllowed(hero, now) then
		Notify.banner("splorch", { userId = hero.UserId, name = displayName(hero), level = show.level }, hero)
	end
	-- analytique
	local previous = lastSplorchAt[hero]
	lastSplorchAt[hero] = now
	Guard.analytics(hero, "SplorchReached", newR, {
		minutes = if previous then (now - previous) / 60 else 0,
		readyAtLogin = if readyAtLogin[hero] then 1 else 0,
	})
	readyAtLogin[hero] = false
	-- prix du Tapis 12 de la boucle quittée (A : prix × F(A) quand la Jelly Ascend est ouverte, N3)
	local price = Formulas.tileCost("snack", SNACK_LOOP_LEVEL, R0, Prestige.ascend(data))
	Guard.analytics(hero, "SplorchCoinsLost", if price > 0 then (lost or 0) / price else 0)
	Guard.analytics(hero, "TileLevelAtSplorch", snackBefore, { decor = decorBefore })
end

-- =============================================================================================
-- Cycle de vie
-- =============================================================================================

local function onPlayerRemoving(player: Player)
	-- départ avant son tour ou avant l'éclatement : place rendue, rien n'est remis à zéro
	if queued[player] ~= nil or (shows[player] ~= nil and not shows[player].burst) then
		EventService.cancelSpectacle(player.UserId)
		Guard.try("splorch:waiting", SquishyService.setWaiting, player, nil)
	end
	queued[player] = nil
	shows[player] = nil
	lastFull[player] = nil
	readyAtLogin[player] = nil
	lastSplorchAt[player] = nil
	petitUntil[player] = nil
	nextAttrs[player] = nil
	attrsSet[player] = nil
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function SplorchService.Init()
	Guard.connect("GrandSplorch", onGrandSplorch)
	Guard.connect("JellyAscend", onJellyAscend)
	-- v2.0 (lot A2) : aucun achat de l'écran Améliorations pendant un prestige du joueur : spectacle
	-- de son Grand Splorch ou de sa Jelly Ascend (du départ à la fin, application comprise) et
	-- animation de son Petit Splorch (upgrades.refused.busy « Attends la fin du spectacle »)
	EconomyService.setBusyProbe(function(player: Player): boolean
		return shows[player] ~= nil or petitBusy(player, Clock.now())
	end)
end

-- Connexions et boucles
function SplorchService.Start()
	Signals.SpectacleStarted:Connect(function(kind: string, userId: number, t: number)
		Guard.try("splorch:start", onSpectacleStarted, kind, userId, t)
	end)
	DataService.Loaded:Connect(function(player: Player)
		readyAtLogin[player] = Guard.call("splorch:ready", ready, false, player) == true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Guard.try("splorch:leave", onPlayerRemoving, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			readyAtLogin[player] = Guard.call("splorch:ready", ready, false, player) == true
		end
	end
end

-- Tick : éclatement dû, fin du spectacle (coupure dure), file sans spectacle (filet), attributs v2.0
function SplorchService.step(now: number)
	if not finite(now) then
		return
	end
	local list = {}
	for hero in shows do
		table.insert(list, hero)
	end
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	for _, hero in list do
		local show = shows[hero]
		if show then
			if not show.burst and now >= show.burstAt then
				local ok = Guard.try("splorch:burst", burst, show, now)
				show.burst = true
				-- éclatement en erreur (attrapée) : l'attente du flyer est levée quand même, jamais un
				-- squishy bloqué « en attente » pour la session
				if not ok and SquishyService.waiting(hero) ~= nil then
					Guard.try("splorch:waiting", SquishyService.setWaiting, hero, nil)
				end
			end
			if now >= math.min(show.endsAt, show.cutAt) then
				shows[hero] = nil
			end
		end
	end
	-- filet : place perdue par EventService (coupure, panne : plus dans sa file, spectacle jamais lancé)
	-- ou attente au-delà de la borne absolue → attente rendue, place annulée, rien remis à zéro. Une
	-- place encore tenue par EventService n'est jamais annulée ici (sa coupure dure la fait partir)
	for player, entry in queued do
		local held = Guard.call("splorch:queuedStartAt", EventService.queuedStartAt, nil, player.UserId)
			~= nil
		if (not held and now > entry.at) or now - entry.at > QUEUE_LIMIT then
			queued[player] = nil
			Guard.try("splorch:waiting", SquishyService.setWaiting, player, nil)
			EventService.cancelSpectacle(player.UserId)
		end
	end
	-- animations du Petit Splorch finies ; attributs Ascend et AscendReady (toutes les secondes)
	for player, untilT in petitUntil do
		if now >= untilT then
			petitUntil[player] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		if now >= (nextAttrs[player] or 0) and DataService.isLoaded(player) then
			nextAttrs[player] = now + ATTR_EVERY
			Guard.try("splorch:attrs", refreshAttrs, player)
		end
	end
end

-- Clock.now() de départ prévu si le joueur est dans la file (Grand Splorch ou Jelly Ascend)
function SplorchService.queued(player: Player): number?
	local entry = queued[player]
	if entry == nil then
		return nil
	end
	local startAt = EventService.queuedStartAt(player.UserId)
	return if startAt ~= nil then startAt else entry.at
end

-- Sorte du prestige du joueur dans la file ou en spectacle ("splorch", "ascend"), nil sinon
function SplorchService.queuedKind(player: Player): ShowKind?
	local entry = queued[player]
	if entry ~= nil then
		return entry.kind
	end
	local show = shows[player]
	return if show ~= nil then show.kind else nil
end

-- Ce squishy attend son Grand Splorch (ou sa Jelly Ascend)
function SplorchService.isWaiting(player: Player, uid: string): boolean
	return SquishyService.waiting(player) == uid
end

-- Aucun prestige en cours pour ce joueur (docs/04 §27.7 : un seul prestige par joueur) : profil
-- chargé, ni file, ni spectacle, ni attente, ni animation du Petit Splorch
function SplorchService.canPrestige(player: Player): boolean
	return profile(player) ~= nil and not prestigeInProgress(player, Clock.now())
end

-- Petit Splorch (docs/04 §27.7) [PetitSplorch] : mêmes conditions que l'intention GrandSplorch
-- (plus gros ≥ objectif, ranch, rien porté, aucune fuite), r après la renaissance ≤ Record R ; hors
-- file, appliqué tout de suite. flyer : squishy d'enclos qui fait le « pouf » (défaut : le plus gros)
function SplorchService.petitSplorch(player: Player, flyer: string?): boolean
	local data = profile(player)
	if data == nil or not petitOn(player) or Prestige.nextKind(data) ~= "petit" then
		return false
	end
	local uid = flyer or SquishyService.biggest(player)
	if type(uid) ~= "string" then
		return false
	end
	return onGrandSplorch(player, false, uid)
end

-- Jelly Ascend (docs/04 §27.7) [JellyAscend] : même chemin que l'intention JellyAscend(true)
function SplorchService.ascend(player: Player): boolean
	return onJellyAscend(player, true)
end

-- Compteurs du service (prestiges refusés par un filet : PrestigeRefused, AscendCancelled…)
function SplorchService.counters(): { [string]: number }
	return table.clone(counters)
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « splorchQueue »
-- (en file, Grand Splorch ou Jelly Ascend), « splorchBurst » (éclatement dû du Grand Splorch),
-- « spectacle » (application due d'une Jelly Ascend, à 4,0 s : sous le délai de 10 s de l'état) ;
-- startedAt en Clock.now()
function SplorchService.openStates(): { { name: string, startedAt: number, player: Player? } }
	local out = {}
	for player, entry in queued do
		table.insert(out, { name = "splorchQueue", startedAt = entry.at, player = player })
	end
	for hero, show in shows do
		if not show.burst then
			table.insert(out, {
				name = if show.kind == "ascend" then "spectacle" else "splorchBurst",
				startedAt = show.startedAt,
				player = hero,
			})
		end
	end
	return out
end

return SplorchService
