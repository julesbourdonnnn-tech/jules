--!strict
-- EconomyService (paquet ranch, docs/04 §11.5 ; GDD §4.1-§4.8, §4.16-§4.19, §4.25, §12.3, §16.2).
-- Pièces, Pot, croissance cumulée, dalles, multiplicateurs, boosts, Fame, plafonds, hors ligne.
-- Calcul paresseux : settle() règle le Pot (intégrale exacte sur [growth.t ; now], deux Clock.now() :
-- jamais deux fois la même seconde, aucun `lastSettle`) et avance growth.G ; refresh() = settle puis
-- nouveau g et nouveau contexte (A, P, B) gardé pour l'intervalle suivant : chaque intervalle est
-- intégré avec UN contexte, celui de son début. refresh est appelé à chaque événement qui change g, A,
-- P ou B (dalle, naissance, fusion, vente, relâche, Dodo, boost qui commence ou finit, ami, Grand
-- Splorch, pass ×2 Pièces, palier de trophée, page dorée, bonus de famille, Fame), avant chaque
-- sauvegarde et toutes les 30 s (décalé par joueur).
-- Hors ligne : rebase pur et synchrone dans DataService.onPrepare (avant l'instantané et Loaded) :
-- G += Formulas.offlineGrowth(g sans boost, s, R, plus gros) (30 %, arrêt à 90 % de l'objectif),
-- Pot += Formulas.offlinePot(revenu de départ sans boost, s), growth.t = Clock.now() ; écran de retour
-- (Celebrate "return") sur Loaded si s ≥ Offline.ReturnScreenMin.
-- Départ : onBeforeSave règle à chaque écriture et pose lastOnline (dernière présence) ; boost
-- personnel décompté puis écrit. Dalles : achat sur la dalle (crochet "pad" de RanchService, refus doux)
-- ou par □ / panneau (BuyTile ; source "pad" si RanchService.onPad(player) == dalle, sinon "panel").
-- Grand Splorch appliqué d'un bloc (applySplorch). Analytique de l'économie par l'API INT-ANALYTICS
-- (Analytics.earnIncome / spendIncome, cumul par joueur, tranche de 5 min et itemSku) dès qu'elle
-- existe ; aucune source Product_.
-- Émet TileBought, PotCollected. Remote : BuyTile. Clés : lastOnline, coins, pot, R, growth, tiles,
-- fame, boosts, caps.
--
-- v2.0 (lot A2, docs/04 §27.4, §27.5, §27.7, §27.14 ; GDD v2.0 §4.6, §4.26, §10.7, §10.8 règles 6,
-- 12, 13). Chaque chemin nouveau est derrière son interrupteur Config/Features, lu à chaque appel ;
-- tous coupés, le jeu de base joue EXACTEMENT comme la version de test (mêmes données, mêmes envois) :
--   * buyUpgrade (intention BuyUpgrade [UpgradesScreen]) : même chemin que BuyTile ; ordre débit →
--     types (mode ∈ { 0, 1, 10 } AVANT UpgradeMath.plan) → existence → état (profil chargé, session
--     pas en fin, niveau attendu = niveau actuel, sinon refus « périmé » muet compté UpgradeStale) →
--     règles (UpgradeMath.cap, aucun prestige en cours, configuration valide) → règlement du Pot →
--     somme exacte UpgradeMath.plan (jamais un prix recalculé) → UN bloc (monnaie, niveaux, signaux)
--     → UpgradeResult TOUJOURS (le refus périmé y est muet : from = to, spent = 0, reason = nil) ;
--   * BuyTile [UpgradesScreen] : la même fonction (mode 1, niveau actuel) ; « snack » achète le Tapis
--     Étoilé au-delà du Tapis 12 (N21) [StarMat], même écran coupé ; UpgradeResult en plus
--     [UpgradesScreen] ; les 4 dalles écran coupé : chemin de la v1.3 (prix Formulas.tileCost) ;
--   * addConfetti : SEUL écrivain des gains de Confettis [Confetti] (buyUpgrade : seul puits) ;
--   * instantané versionné (snapshot) : version + 1 à chaque contenu changé, envoyé dans UpgradeResult
--     et dans DataPatch (DataService.setPatchExtra « upgradeSnapshot ») [UpgradesScreen] ;
--   * Prestige.validateConfig au chargement et à chaque changement de configuration en direct ;
--   * contextes d'A1 : A, bestR, firstRecordLoop, star (croissance), monuments (revenu), Gants et
--     Super Série (pressBonus, lus par SquishyService), Sac et Pot de nuit, croissance maximale
--     (hors ligne), A (tileCost) — Formulas ne les lit qu'interrupteur ouvert ;
--   * prestiges v2.0 (étape 3) : prestigeV2 (profil v2, RecordR, configuration acceptée) et
--     applyPrestige (Prestige.apply d'un bloc, cadeau du Splorch dans le Pot), appelés par
--     SplorchService ; plafonds Balance.CapsV2 (Fame des Grands Splorch, Pluies d'étoiles) remis à
--     zéro chaque jour avec les autres.
-- Émet aussi UpgradeBought, ConfettiChanged. Remotes : BuyUpgrade ; UpgradeResult (envoi). Clés v2 :
-- confetti, confettiTotal, tiles.{star, gloves, school, monuments}, atelier, atelierCosmetics, bestR
-- (au Grand Splorch d'un profil v2 : Record R jamais sous r), decorBuilds (décorations dorées : une
-- boucle de plus par décoration construite à chaque prestige v2.0, relecture du lot A2).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Pads = require(Shared.Config.Pads)
local Features = require(Shared.Config.Features)
local Upgrades = require(Shared.Config.Upgrades)
local Formulas = require(Shared.Logic.Formulas)
local QuestRules = require(Shared.Logic.QuestRules)
local Prestige = require(Shared.Logic.Prestige)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local Bitset = require(Shared.Logic.Bitset)
local Signals = require(script.Parent.Parent.Signals)
local Notify = require(script.Parent.Parent.Util.Notify)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Ranch.Guard)
local PadRules = require(script.Parent.Parent.Ranch.PadRules)
local DataService = require(script.Parent.DataService)
local DiagnosticsService = require(script.Parent.DiagnosticsService)
local MonetizationService = require(script.Parent.MonetizationService)
local RanchService = require(script.Parent.RanchService)

local EconomyService = {}

local MAX = Balance.Numbers.Max
local REFRESH_EVERY = 30 -- s : règlement périodique (décalé par joueur)

type OfflineInfo = { seconds: number, grew: number, pot: number, readyBefore: boolean }

-- état de session (clés faibles : rien ne survit au Player, même si un nettoyage manquait)
local function weak(): any
	return setmetatable({}, { __mode = "k" })
end
local ctxCache: { [Player]: Formulas.IncomeCtx } = weak()
local friendsPresent: { [Player]: number } = weak()
local nextRefresh: { [Player]: number } = weak()
local nextAutoPot: { [Player]: number } = weak()
local runningSince: { [Player]: number } = weak() -- boost personnel en cours (Clock.now() du dernier point)
local offlineInfo: { [Player]: OfflineInfo } = weak()
local settleHooks: { (Player, number) -> () } = {}
local serverBoost = { kind = "", untilT = 0 }

-- v2.0 (lot A2)
local MODES: { [number]: boolean } = { [0] = true, [1] = true, [10] = true } -- 0 = Max (§27.5)
local V1_TILES: { [string]: boolean } = { snack = true, decor = true, pens = true, cozyBed = true }
local CONFETTI_MAX = Balance.Confetti.Max
-- sources des gains (Signals.ConfettiChanged, docs/04 §27.4) ; « spend » est le puits de buyUpgrade
local CONFETTI_SOURCES: { [string]: boolean } = {
	splorch = true,
	petit = true,
	skipped = true,
	ascend = true,
	regain = true,
	record = true,
	fullPen = true,
	track = true,
	mastery = true,
}
-- clés du profil lues par l'instantané de l'écran Améliorations (un patch qui en touche une le porte)
local SNAPSHOT_KEYS: { [string]: boolean } = {
	coins = true,
	confetti = true,
	tiles = true,
	atelier = true,
	atelierCosmetics = true,
	R = true,
	bestR = true,
	ascend = true,
}
local REFUSED = {
	coins = "upgrades.refused.coins",
	confetti = "upgrades.refused.confetti",
	locked = "upgrades.refused.locked",
	maxed = "upgrades.refused.maxed",
	loopCap = "upgrades.refused.loopCap",
	busy = "upgrades.refused.busy",
}
local READY_CHECK_EVERY = 1 -- s : attribut SplorchReady du ranch [RecordR]
-- décorations dorées (champ decorBuilds, docs/04 §27.2 ; GDD §11.5 « construite dans 10 boucles ») :
-- une case par décoration (18), bornée à 10 (mêmes nombres que Logic/Invariants et ProfileRepair)
local DECOR_BUILDS = Balance.Tiles.decor.Levels
local DECOR_BUILDS_MAX = 10
-- interrupteurs dont un changement en direct relance Prestige.validateConfig
local CONFIG_FLAGS = {
	"UpgradesScreen",
	"Confetti",
	"Workshop",
	"StarMat",
	"Gloves",
	"Monuments",
	"RecordR",
	"PetitSplorch",
	"JellyAscend",
}
local snapVersion: { [Player]: number } = weak()
local snapLast: { [Player]: Types.UpgradeSnapshot } = weak()
local nextReadyCheck: { [Player]: number } = weak()
local busyProbe: ((Player) -> boolean)? = nil
local counters: { [string]: number } = {}
local configOk = true
local configWhy: string? = nil
local flagPrint = ""

-- =============================================================================================
-- Outils
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clampReal(x: any, lo: number, hi: number): number
	if not finite(x) then
		return lo
	end
	return math.clamp(x, lo, hi)
end

local function familyEarned(data: { [string]: any }, family: string): boolean
	return QuestRules.familyEarned(data.dex, family)
end

local function serverBoostActive(now: number): boolean
	return serverBoost.kind ~= "" and now < serverBoost.untilT
end

-- Secondes restantes du boost personnel à l'instant now
local function personalRemaining(player: Player, data: { [string]: any }, now: number): number
	local left = clampReal(data.boosts.personalLeft, 0, MAX)
	local since = runningSince[player]
	if since ~= nil then
		left -= math.max(0, now - since)
	end
	return math.max(0, left)
end

-- Écrit le décompte du boost personnel dans le profil (pause, reprise, sauvegarde)
local function checkpoint(player: Player, data: { [string]: any }, now: number)
	local since = runningSince[player]
	if since == nil then
		return
	end
	local left = personalRemaining(player, data, now)
	data.boosts.personalLeft = left
	runningSince[player] = if left > 0 then now else nil
	DataService.markDirty(player, "boosts")
end

local function boostOn(player: Player, data: { [string]: any }, now: number): boolean
	return serverBoostActive(now) or personalRemaining(player, data, now) > 0
end

-- Contexte des multiplicateurs calculé depuis le profil (A, P, B)
-- Monuments construits [Monuments] : multiplicateur à part du revenu (N4). Interrupteur coupé :
-- le champ n'est pas dans le contexte (contexte identique à la v1.3)
local function withMonuments(ctx: Formulas.IncomeCtx, data: { [string]: any }): Formulas.IncomeCtx
	if Features.get("Monuments") == true then
		ctx.monuments = UpgradeMath.level("monument", data)
	end
	return ctx
end

local function computeCtx(player: Player, data: { [string]: any }, boost: boolean): Formulas.IncomeCtx
	local doubleCoins = false
	local ok, owns = pcall(MonetizationService.ownsPass, player, "DoubleCoins")
	if ok and owns == true then
		doubleCoins = true
	end
	return withMonuments({
		decor = clampReal(data.tiles.decor, 0, Balance.Tiles.decor.Levels),
		friends = friendsPresent[player] or 0,
		fame = clampReal(data.fame, 0, MAX),
		trophyBonus = Formulas.trophyBonus(data.trophies),
		goldenPages = QuestRules.goldenPages(data.dex),
		doubleCoins = doubleCoins,
		boost = boost,
	}, data)
end

-- Contexte de croissance. v2.0 (A1, N2) : Tapis Étoilé, A, Record R et 1re boucle record, lus par
-- Formulas seulement quand StarMat / la Jelly Ascend sont ouverts (coupés : g de la v1.3, au bit près)
local function growthCtx(data: { [string]: any }, boost: boolean): Formulas.GrowthCtx
	return {
		R = clampReal(data.R, 0, 1e6),
		snack = clampReal(data.tiles.snack, 0, Balance.Tiles.snack.Levels),
		jellyFamily = familyEarned(data, "jelly"),
		boost = boost,
		star = UpgradeMath.level("star", data),
		A = Prestige.ascend(data),
		bestR = Prestige.bestR(data),
		firstRecordLoop = Prestige.firstRecordLoop(data),
	}
end

-- Le contexte gardé ne correspond plus au profil (A, P, B ou g) : un refresh est dû. Filet de sûreté :
-- chaque déclencheur de refresh (palier de trophée, page dorée, bonus de famille gagné, Fame, dalle,
-- amis, pass) est aussi rattrapé au tick suivant même si son service oublie d'appeler refresh.
local function stale(
	player: Player,
	data: { [string]: any },
	ctx: Formulas.IncomeCtx,
	boost: boolean
): boolean
	local fresh = computeCtx(player, data, boost)
	for key, value in fresh :: any do
		if (ctx :: any)[key] ~= value then
			return true
		end
	end
	return Formulas.growthRate(growthCtx(data, boost)) ~= data.growth.g
end

local function ctxOf(player: Player, data: { [string]: any }): Formulas.IncomeCtx
	local ctx = ctxCache[player]
	if ctx == nil then
		ctx = computeCtx(player, data, boostOn(player, data, Clock.now()))
		ctxCache[player] = ctx
	end
	return ctx
end

-- Revenu du ranch à l'instant now (enclos + Bassin, multiplicateurs du contexte en vigueur)
local function incomeAt(player: Player, data: { [string]: any }, now: number): number
	local G = Formulas.G(data.growth, now)
	local K, S1 = Formulas.ranchIncome(data.squishies, G, ctxOf(player, data))
	return clampReal(S1 + K * G, 0, MAX)
end

-- Analytique de l'économie (note INT-ANALYTICS, paquet meta) : cumul par joueur, tranche de 5 min et
-- itemSku, en secondes de revenu. Sans l'API cumulée, rien n'est envoyé (jamais un appel par pression).
local function analytics(kind: "earn" | "spend", player: Player, sku: string, coins: number, txType: string)
	local api = Analytics :: any
	local fn = if kind == "earn" then api.earnIncome else api.spendIncome
	if type(fn) ~= "function" or coins <= 0 then
		return
	end
	local data = DataService.get(player)
	local income = if data then incomeAt(player, data, Clock.now()) else 0
	Guard.try("economy:analytics", fn, player, sku, coins, income, txType)
end

local function publishGrowth(player: Player, data: { [string]: any })
	local growth = data.growth
	RanchService.setPublic(player, { growth = { G = growth.G, g = growth.g, t = growth.t } })
end

-- Remise à zéro des plafonds au changement de jour UTC (petSitBy compris ; v2.0 : compteurs de
-- Balance.CapsV2 d'un profil v2, « remis à zéro au changement de jour avec les autres », Data/Schema)
local function capsToday(player: Player, data: { [string]: any }): { [string]: any }
	local caps = data.caps
	local today = Clock.day()
	if caps.day ~= today then
		for key in Balance.Caps do
			caps[key] = 0
		end
		if PadRules.v2Profile(data) then
			for key in Balance.CapsV2 do
				caps[key] = 0
			end
		end
		caps.petSitBy = {}
		caps.day = today
		DataService.markDirty(player, "caps")
	end
	return caps
end

-- Taille du plus gros squishy d'enclos ou du Bassin à la croissance G
local function biggestAt(data: { [string]: any }, G: number): (string?, number)
	local bestUid, best = nil, 0
	if type(data.squishies) == "table" then
		for uid, rec in data.squishies do
			if type(rec) == "table" and (rec.at == "pen" or rec.at == "pool") then
				local size = Formulas.sizeAt(rec, G)
				if size > best or (size == best and bestUid ~= nil and uid < bestUid) then
					bestUid, best = uid, size
				end
			end
		end
	end
	return bestUid, best
end

-- =============================================================================================
-- v2.0 (lot A2) : outils des achats, des Confettis et de l'instantané
-- =============================================================================================

-- Compte un événement de Diagnostics (docs/04 §27.14 : UpgradeStale, ConfigRefused…) : compteur du
-- service (EconomyService.counters), transmis à DiagnosticsService.count quand le lot A4 l'ajoute
-- (note INT-A2-DIAG) ; jamais une trace
local function diag(key: string, player: Player?)
	counters[key] = (counters[key] or 0) + 1
	local count = (DiagnosticsService :: any).count
	if type(count) == "function" then
		Guard.try("economy:diag", count, key, player)
	end
end

-- Niveau entier de [0 ; hi] (illisible → 0)
local function int(x: any, hi: number): number
	if not finite(x) then
		return 0
	end
	return math.clamp(math.floor(x), 0, hi)
end

-- Confettis en poche (entier 0 … Max)
local function confettiOf(data: { [string]: any }): number
	return int(data.confetti, CONFETTI_MAX)
end

-- La ligne peut-elle être notée dans CE profil ? Les 4 dalles de la v1.3 toujours ; les champs v2.0
-- (Tapis Étoilé, Gants, École, Monuments, Atelier, « Pour le plaisir ») dans un profil v2 seulement
-- (SchemaV2 coupé : jamais un champ v2 écrit dans une sauvegarde v1)
local function storable(data: { [string]: any }, id: string): boolean
	return V1_TILES[id] == true or PadRules.v2Profile(data)
end

-- Niveau maximal achetable maintenant (0 = fermé) : UpgradeMath.cap (ouverture, plafond de la boucle,
-- interrupteurs), et 0 pour une ligne que ce profil ne peut pas noter
local function capOf(data: { [string]: any }, id: string): number
	if not storable(data, id) then
		return 0
	end
	return UpgradeMath.cap(id, data, Features)
end

-- Raison d'un refus « pas ouvert » (niveau ≥ plafond)
local function capReason(data: { [string]: any }, id: string, level: number): string
	if level >= UpgradeMath.maxLevel(id) then
		return REFUSED.maxed
	end
	local def = Upgrades.ById[id]
	if
		def ~= nil
		and def.open.loopCapByR ~= nil
		and storable(data, id)
		and Features.get(def.feature) == true
		and UpgradeMath.level("snack", data) >= UpgradeMath.maxLevel("snack")
	then
		return REFUSED.loopCap -- Tapis Étoilé : niveau suivant dans une boucle plus haute
	end
	return REFUSED.locked
end

-- Deux instantanés montrent-ils la même chose (hors version) ?
local function sameSnapshot(a: Types.UpgradeSnapshot, b: Types.UpgradeSnapshot): boolean
	if a.coins ~= b.coins or a.confetti ~= b.confetti or a.r ~= b.r or a.bestR ~= b.bestR then
		return false
	end
	if a.ascend ~= b.ascend then
		return false
	end
	for id, level in a.levels do
		if b.levels[id] ~= level or b.caps[id] ~= a.caps[id] then
			return false
		end
	end
	for id in b.levels do
		if a.levels[id] == nil then
			return false
		end
	end
	return true
end

-- Instantané versionné de l'écran (règle 6 du GDD §10.8) : la version croît de 1 dès que le contenu
-- change (achat, règlement qui change les pièces, prestige, Confettis, plafond qui s'ouvre), jamais
-- sinon : UpgradeResult et le DataPatch de la même image portent la MÊME version
local function snapshotOf(player: Player, data: { [string]: any }): Types.UpgradeSnapshot
	local snap = UpgradeMath.snapshot(data, Features, 0)
	for id in snap.caps do
		if not storable(data, id) then
			snap.caps[id] = 0
		end
	end
	local last = snapLast[player]
	local version = snapVersion[player] or 0
	if last == nil or not sameSnapshot(last, snap) then
		version += 1
		snapVersion[player] = version
		snapLast[player] = snap
	else
		snap = last
	end
	snap.version = version
	return snap
end

-- Un prestige est-il en cours d'application pour ce joueur (sonde posée par SplorchService) ? Une
-- sonde en erreur compte comme « oui » (refus sûr, jamais un achat pendant un spectacle)
local function prestigeBusy(player: Player): boolean
	local probe = busyProbe
	if probe == nil then
		return false
	end
	local ok, busy = Guard.try("economy:busyProbe", probe, player)
	return not ok or busy == true
end

-- Réponse UpgradeResult (le joueur seulement) [UpgradesScreen]
local function sendResult(player: Player, payload: Types.UpgradeResultPayload)
	if Features.get("UpgradesScreen") ~= true or player.Parent == nil then
		return
	end
	Net.event("UpgradeResult"):FireClient(player, payload)
end

-- Écrit le niveau `to` d'une ligne dans le profil (marque la clé) ; rend false si le champ est illisible
local function writeLevel(
	player: Player,
	data: { [string]: any },
	id: string,
	from: number,
	to: number
): boolean
	local def = Upgrades.ById[id]
	if def ~= nil then
		local tiles = data.tiles
		local field = string.match(def.profileKey, "^tiles%.(%w+)$")
		if type(tiles) ~= "table" or field == nil then
			return false
		end
		if id == "cozyBed" then
			tiles.cozyBed = to >= 1
		else
			tiles[field] = to
		end
		local pad = (Pads.Defs :: any)[id]
		if type(pad) == "table" then
			-- dalle de la v1.3 achetée (écran ou sol) : découverte, comme BuyTile
			tiles.seen = bit32.bor(math.floor(clampReal(tiles.seen, 0, 4294967295)), pad.seenBit)
		end
		DataService.markDirty(player, "tiles")
		return true
	end
	local index = Upgrades.WorkshopIndex[id]
	if index ~= nil then
		local atelier = data.atelier
		if type(atelier) ~= "table" then
			return false
		end
		-- tableau dense (jamais un trou : JSON du DataStore)
		for i = #atelier + 1, index - 1 do
			atelier[i] = 0
		end
		atelier[index] = to
		DataService.markDirty(player, "atelier")
		return true
	end
	-- « Pour le plaisir » : les objets suivants de la ligne, dans l'ordre (premiers bits libres)
	local canonical = UpgradeMath.canonical(id)
	local line = nil
	for _, l in Upgrades.Fun do
		if canonical == "fun." .. l.id and l.store == "bits" then
			line = l
		end
	end
	local bits = data.atelierCosmetics
	if line == nil or type(bits) ~= "table" then
		return false
	end
	local first = line.firstBit or 1
	local left = to - from
	for i = first, first + #line.costs - 1 do
		if left <= 0 then
			break
		end
		if not Bitset.has(bits, i) then
			Bitset.set(bits, i)
			left -= 1
		end
	end
	DataService.markDirty(player, "atelierCosmetics")
	return left == 0
end

-- Le champ de la ligne est-il écrivable (vérifié AVANT toute écriture : un bloc ou rien) ?
local function writable(data: { [string]: any }, id: string): boolean
	if Upgrades.ById[id] ~= nil then
		return type(data.tiles) == "table"
	elseif Upgrades.WorkshopIndex[id] ~= nil then
		return type(data.atelier) == "table"
	end
	return type(data.atelierCosmetics) == "table"
end

-- Achat appliqué D'UN SEUL BLOC, sans yield : monnaie, niveaux, ranch, contexte du revenu, signaux.
-- Rend false sans rien écrire si la somme n'est plus payable ou le champ illisible
local function applyPurchase(
	player: Player,
	data: { [string]: any },
	id: string,
	from: number,
	n: number,
	total: number,
	currency: Types.UpgradeCurrency
): boolean
	local to = from + n
	if not writable(data, id) then
		return false
	end
	if currency == "coins" then
		local coins = Formulas.clampCoins(data.coins)
		if total > coins then
			return false
		end
		DataService.set(player, "coins", Formulas.clampCoins(math.max(0, coins - total)))
	else
		local confetti = confettiOf(data)
		if total > confetti or total % 1 ~= 0 then
			return false
		end
		DataService.set(player, "confetti", confetti - total)
	end
	writeLevel(player, data, id, from, to)
	if Upgrades.ById[id] ~= nil then
		-- famille en pièces : ranch construit, croissance (Tapis), revenu (décorations, Monuments)
		RanchService.refreshBuild(player)
		EconomyService.refresh(player)
	end
	-- TileBought (v1.3) : un par niveau des 4 dalles (étape 3 de l'accueil, objectifs) ; UpgradeBought
	-- en plus pour tout achat (docs/04 §27.4)
	if V1_TILES[id] then
		for lv = from + 1, to do
			Signals.TileBought:Fire(player, id, lv)
		end
	end
	Signals.UpgradeBought:Fire(player, id, from, to, currency)
	if currency == "confetti" then
		Signals.ConfettiChanged:Fire(player, -total, "spend")
	else
		analytics("spend", player, if V1_TILES[id] then "Tile_" .. id else "Upgrade_" .. id, total, "Shop")
	end
	return true
end

-- Cœur de BuyUpgrade et de BuyTile (même chemin, docs/04 §27.5) ; rend (réponse, niveaux achetés).
-- Réponse nil : rien à envoyer (profil absent, joueur parti, ligne inconnue). Ordre : état (session,
-- niveau attendu) → règles (plafond, prestige, configuration) → règlement du Pot → somme exacte → bloc
local function purchase(
	player: Player,
	id: string,
	mode: number,
	expectedLevel: number
): (Types.UpgradeResultPayload?, number)
	local data = DataService.get(player)
	local canonical = UpgradeMath.canonical(id)
	if data == nil or player.Parent == nil or canonical == nil then
		return nil, 0
	end
	local currency: Types.UpgradeCurrency = UpgradeMath.currency(canonical) or "coins"
	local level = UpgradeMath.level(canonical, data)
	local function answer(to: number, spent: number, reason: string?): Types.UpgradeResultPayload
		return {
			id = canonical,
			from = level,
			to = to,
			spent = spent,
			currency = currency,
			reason = reason,
			snapshot = snapshotOf(player, data),
		}
	end
	-- sauvegarde de départ commencée : l'achat serait perdu
	if DataService.isClosing(player) then
		return answer(level, 0, REFUSED.busy), 0
	end
	-- périmé (le niveau a changé depuis l'instantané du client) : muet, compté
	if expectedLevel ~= level then
		diag("UpgradeStale", player)
		return answer(level, 0, nil), 0
	end
	local cap = capOf(data, canonical)
	if level >= cap then
		return answer(level, 0, capReason(data, canonical, level)), 0
	end
	if not configOk or prestigeBusy(player) then
		return answer(level, 0, REFUSED.busy), 0
	end
	EconomyService.settle(player)
	local cash = if currency == "coins" then Formulas.clampCoins(data.coins) else confettiOf(data)
	local n, total = UpgradeMath.plan(
		canonical,
		level,
		mode,
		cash,
		cap,
		Prestige.r(data),
		Prestige.ascend(data),
		Prestige.bestR(data)
	)
	if
		n < 1
		or not finite(total)
		or total > cash
		or not applyPurchase(player, data, canonical, level, n, total, currency)
	then
		return answer(level, 0, if currency == "coins" then REFUSED.coins else REFUSED.confetti), 0
	end
	return answer(level + n, total, nil), n
end

-- Empreinte des interrupteurs de la progression (changement en direct : configuration revérifiée)
local function flagFingerprint(): number
	local print = 0
	for i, key in CONFIG_FLAGS do
		if Features.get(key) == true then
			print = bit32.bor(print, bit32.lshift(1, i - 1))
		end
	end
	return print
end

-- =============================================================================================
-- Hors ligne (DataService.onPrepare) et écran de retour (Loaded)
-- =============================================================================================

local function offlineRebase(player: Player, data: { [string]: any })
	local nowUnix = Clock.unix()
	local now = Clock.now()
	local growth = data.growth
	local seconds = Formulas.offlineSeconds(
		nowUnix,
		data.lastOnline,
		data.tiles.cozyBed == true,
		familyEarned(data, "spiky"),
		UpgradeMath.level("nightBag", data) -- Sac de nuit [Workshop] (N6)
	)
	local G0 = clampReal(growth.G, 0, MAX)
	local R = clampReal(data.R, 0, 1e6)
	local _, biggest = biggestAt(data, G0)
	local target = Formulas.splorchTarget(R)
	local gNoBoost = Formulas.growthRate(growthCtx(data, false))
	local grew = 0
	local potAdd = 0
	if seconds > 0 then
		-- arrêt à 120 s de croissance maximale de la boucle avant l'objectif [RecordR] (N6)
		grew = Formulas.offlineGrowth(
			gNoBoost,
			seconds,
			R,
			biggest,
			Formulas.maxGrowthRate(growthCtx(data, false))
		)
		-- revenu de départ sans boost (P compris : un pass est permanent ; amis absents)
		local ctx: Formulas.IncomeCtx = withMonuments({
			decor = clampReal(data.tiles.decor, 0, Balance.Tiles.decor.Levels),
			friends = 0,
			fame = clampReal(data.fame, 0, MAX),
			trophyBonus = Formulas.trophyBonus(data.trophies),
			goldenPages = QuestRules.goldenPages(data.dex),
			doubleCoins = type(data.passes) == "table" and data.passes.DoubleCoins == true,
			boost = false,
		}, data)
		local K, S1 = Formulas.ranchIncome(data.squishies, G0, ctx)
		-- Pot de nuit [Workshop] (N6)
		potAdd =
			Formulas.offlinePot(clampReal(S1 + K * G0, 0, MAX), seconds, UpgradeMath.level("nightPot", data))
		data.pot = clampReal(clampReal(data.pot, 0, MAX) + potAdd, 0, MAX)
	end
	growth.G = clampReal(G0 + grew, 0, MAX)
	growth.g = gNoBoost
	-- plafonds du jour remis à zéro avant l'instantané (aucun patch juste après le chargement)
	capsToday(player, data)
	-- l'ancien growth.t d'une autre session n'est JAMAIS intégré au tarif plein
	growth.t = now
	offlineInfo[player] = { seconds = seconds, grew = grew, pot = potAdd, readyBefore = biggest >= target }
end

local function returnScreen(player: Player, data: { [string]: any })
	local info = offlineInfo[player]
	offlineInfo[player] = nil
	if info == nil or info.seconds < Balance.Offline.ReturnScreenMin then
		return
	end
	local G = Formulas.G(data.growth, Clock.now())
	-- squishy montré : Meilleur Ami n° 1, sinon le plus gros
	local uid: string? = nil
	for id, rec in data.squishies do
		if type(rec) == "table" and rec.bf == 1 then
			uid = id
			break
		end
	end
	local biggestUid, biggest = biggestAt(data, G)
	if uid == nil then
		uid = biggestUid
	end
	local rec = if uid then data.squishies[uid] else nil
	local target = Formulas.splorchTarget(clampReal(data.R, 0, 1e6))
	local payload: Types.ReturnScreenData = {
		seconds = info.seconds,
		uid = uid or "",
		species = if rec then rec.s else 0,
		grew = info.grew,
		pot = math.floor(info.pot),
		splorchReady = info.readyBefore,
		nearlyReady = biggest >= Balance.Offline.StopAt * target,
	}
	Notify.celebrate(player, "return", payload :: any)
end

local function onLoaded(player: Player, data: { [string]: any })
	local now = Clock.now()
	nextRefresh[player] = now + REFRESH_EVERY * ((player.UserId % 97) / 97)
	nextAutoPot[player] = now + Balance.Pot.AutoInterval
	-- boost personnel restant : repart (en pause pendant un boost de serveur)
	if clampReal(data.boosts.personalLeft, 0, MAX) > 0 and not serverBoostActive(now) then
		runningSince[player] = now
	end
	-- contexte du revenu de la session ; le profil n'est réécrit (patch) que si g change vraiment
	-- (boost personnel restant) : rien d'autre ne part juste après l'instantané
	local boost = boostOn(player, data, now)
	ctxCache[player] = computeCtx(player, data, boost)
	if Formulas.growthRate(growthCtx(data, boost)) ~= data.growth.g then
		EconomyService.refresh(player)
	else
		publishGrowth(player, data)
	end
	RanchService.setPublic(player, { R = data.R, fame = data.fame })
	returnScreen(player, data)
end

local function onBeforeSave(player: Player, data: { [string]: any }, release: boolean?)
	if DataService.get(player) == data then
		EconomyService.settle(player)
	end
	checkpoint(player, data, Clock.now())
	-- dernière présence (Clock.unix()) : à chaque écriture, le joueur est là ; au départ, c'est la
	-- base de l'absence suivante (jamais dans PlayerRemoving, docs/04 §1 règle 15)
	data.lastOnline = Clock.unix()
	if release then
		runningSince[player] = nil
		-- contexte du dernier intervalle gardé jusqu'ici (voir cleanup) : la session est finie
		if player.Parent == nil then
			ctxCache[player] = nil
			friendsPresent[player] = nil
		end
	end
end

local function cleanup(player: Player)
	nextRefresh[player] = nil
	nextAutoPot[player] = nil
	offlineInfo[player] = nil
	nextReadyCheck[player] = nil
	-- revue : le contexte du revenu (amis présents, A, P, B) et runningSince sont gardés tant que la
	-- sauvegarde de départ n'a pas réglé le dernier intervalle (elle peut attendre une sauvegarde
	-- automatique en cours et passer APRÈS ce nettoyage) ; tables à clés faibles : rien ne survit au
	-- Player. Sans profil (jamais chargé, ou déjà sauvegardé), tout est vidé tout de suite.
	if DataService.get(player) == nil then
		ctxCache[player] = nil
		friendsPresent[player] = nil
	end
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Création des remotes et des états ; aucun yield long
function EconomyService.Init()
	DataService.onPrepare(function(player: Player, data: { [string]: any })
		offlineRebase(player, data)
	end)
	DataService.onBeforeSave(onBeforeSave)
	-- BuyTile : □ sur la dalle (source "pad", refus doux) ou panneau (source "panel")
	Guard.connect("BuyTile", function(player: Player, tile: string): boolean
		if DataService.get(player) == nil then
			return false
		end
		local source: "pad" | "panel" = if RanchService.onPad(player) == tile then "pad" else "panel"
		local bought = EconomyService.buyTile(player, tile, source, true)
		if bought then
			-- achat voulu : il compte pour l'entrée sur cette dalle (aucun 2e niveau à la fin de l'anneau)
			RanchService.notePadPurchase(player, tile)
		end
		return bought
	end)
	-- v2.0 : BuyUpgrade (écran Améliorations) ; interrupteur UpgradesScreen coupé : aucune réponse,
	-- aucune mutation (comme sans handler ; l'interrupteur peut s'ouvrir en direct)
	Guard.connect(
		"BuyUpgrade",
		function(player: Player, id: string, mode: number, expectedLevel: number): boolean
			local payload = EconomyService.buyUpgrade(player, id, mode, expectedLevel)
			return payload ~= nil and payload.to > payload.from
		end
	)
	-- instantané versionné porté par l'instantané d'arrivée et par chaque patch qui touche ce qu'il
	-- montre [UpgradesScreen] (coupé : rien n'est ajouté, aucun patch de plus)
	DataService.setPatchExtra(
		"upgradeSnapshot",
		function(player: Player, data: { [string]: any }, keys: { [string]: boolean }?): any
			if Features.get("UpgradesScreen") ~= true then
				return nil
			end
			if keys ~= nil then
				local touched = false
				for key in keys do
					if SNAPSHOT_KEYS[key] then
						touched = true
						break
					end
				end
				if not touched then
					return nil
				end
			end
			return snapshotOf(player, data)
		end
	)
	-- invariant de stabilité de la configuration (refus compté par Diagnostics)
	EconomyService.validateConfig(Balance)
	flagPrint = flagFingerprint()
end

-- Connexions et boucles
function EconomyService.Start()
	RanchService.setZoneHandler("pot", function(player: Player, _key: string)
		EconomyService.collectPot(player, false)
	end)
	RanchService.setZoneHandler("pad", function(player: Player, tile: string)
		EconomyService.buyTile(player, tile, "pad")
	end)
	DataService.Loaded:Connect(function(player: Player, data: { [string]: any })
		Guard.try("economy:loaded", onLoaded, player, data)
	end)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and nextRefresh[player] == nil then
			task.spawn(Guard.try, "economy:loaded", onLoaded, player, data)
		end
	end
	Players.PlayerRemoving:Connect(cleanup)
	MonetizationService.PassGranted:Connect(function(player: Player, passKey: string)
		if passKey == "DoubleCoins" then
			EconomyService.refresh(player)
		end
	end)
	MonetizationService.PassRevoked:Connect(function(player: Player, passKey: string)
		if passKey == "DoubleCoins" then
			EconomyService.refresh(player)
		end
	end)
end

-- Tick : règlements échelonnés (30 s), fins de boost, Pot automatique (pass, 5 s)
function EconomyService.step(now: number)
	if serverBoost.kind ~= "" and now >= serverBoost.untilT then
		serverBoost = { kind = "", untilT = 0 }
	end
	-- configuration changée en direct (interrupteurs LiveOps) : invariant de stabilité revérifié
	local print = flagFingerprint()
	if print ~= flagPrint then
		flagPrint = print
		EconomyService.validateConfig(Balance)
	end
	local recordOn = Features.get("RecordR") == true
	local serverOn = serverBoostActive(now)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and nextRefresh[player] ~= nil then
			Guard.try("economy:step", function()
				-- boost personnel : en pause pendant un boost de serveur, sinon il s'écoule
				if serverOn then
					checkpoint(player, data, now)
					runningSince[player] = nil
				elseif runningSince[player] == nil and clampReal(data.boosts.personalLeft, 0, MAX) > 0 then
					runningSince[player] = now
				elseif runningSince[player] ~= nil and personalRemaining(player, data, now) <= 0 then
					data.boosts.personalLeft = 0
					runningSince[player] = nil
					DataService.markDirty(player, "boosts")
				end
				-- B a changé (boost qui commence ou finit), contexte périmé (palier de trophée, page dorée,
				-- bonus de famille, Fame, amis, pass, dalle) ou règlement périodique : refresh
				local ctx = ctxCache[player]
				local boost = boostOn(player, data, now)
				if ctx == nil or stale(player, data, ctx, boost) or now >= (nextRefresh[player] or 0) then
					nextRefresh[player] = now + REFRESH_EVERY
					checkpoint(player, data, now)
					EconomyService.refresh(player)
				end
				-- Pot automatique (pass), toutes les 5 s
				if now >= (nextAutoPot[player] or math.huge) then
					nextAutoPot[player] = now + Balance.Pot.AutoInterval
					local ok, owns = pcall(MonetizationService.ownsPass, player, "AutoPot")
					if ok and owns == true then
						EconomyService.collectPot(player, true)
					end
				end
				-- attribut SplorchReady du ranch [RecordR] (toutes les secondes ; coupé : effacé)
				if recordOn and now >= (nextReadyCheck[player] or 0) then
					nextReadyCheck[player] = now + READY_CHECK_EVERY
					local _, biggest = biggestAt(data, Formulas.G(data.growth, now))
					local target = Formulas.splorchTarget(EconomyService.R(player))
					-- Record absolu (r = MaxR, profil v2) : jamais « prêt », le Grand Splorch y est refusé
					local absolute = PadRules.v2Profile(data) and Prestige.r(data) >= Balance.Prestige.MaxR
					RanchService.setV2Attributes(
						player,
						{ SplorchReady = biggest >= target and not absolute }
					)
				elseif not recordOn and nextReadyCheck[player] ~= nil then
					nextReadyCheck[player] = nil
					RanchService.setV2Attributes(player, {}, { "SplorchReady" })
				end
			end)
		end
	end
end

-- Règle le Pot et la croissance cumulée jusqu'à maintenant
function EconomyService.settle(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local now = Clock.now()
	local growth = data.growth
	if finite(growth.t) and now > growth.t then
		local ctx = ctxOf(player, data)
		local K, S1 = Formulas.ranchIncome(data.squishies, clampReal(growth.G, 0, MAX), ctx)
		local gain = Formulas.potGain(K, S1, growth, growth.t, now)
		if gain > 0 then
			data.pot = clampReal(clampReal(data.pot, 0, MAX) + gain, 0, MAX)
			DataService.markDirty(player, "pot")
		end
		growth.G = Formulas.G(growth, now)
		growth.t = now
		DataService.markDirty(player, "growth")
	elseif not finite(growth.t) then
		growth.t = now
	end
	local G = growth.G
	for _, fn in settleHooks do
		Guard.try("economy:onSettle", fn, player, G)
	end
end

-- settle puis recalcule g, A, P, B (après un changement) et publie growth (RanchService.setPublic)
function EconomyService.refresh(player: Player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	EconomyService.settle(player)
	local now = Clock.now()
	local boost = boostOn(player, data, now)
	ctxCache[player] = computeCtx(player, data, boost)
	local g = Formulas.growthRate(growthCtx(data, boost))
	if g ~= data.growth.g then
		data.growth.g = g
		DataService.markDirty(player, "growth")
	end
	publishGrowth(player, data)
end

-- Pièces actuelles (après settle : le règlement ne verse qu'au Pot, jamais aux pièces)
function EconomyService.coins(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return Formulas.clampCoins(data.coins)
end

-- Crédite (borné, entier) ; rend le montant crédité ; analytics source
function EconomyService.addCoins(player: Player, amount: number, sku: string, txType: string?): number
	local data = DataService.get(player)
	local credit = Formulas.clampCoins(amount)
	if data == nil or credit <= 0 then
		return 0
	end
	local before = Formulas.clampCoins(data.coins)
	local after = Formulas.clampCoins(before + credit)
	local credited = after - before
	if credited <= 0 then
		return 0
	end
	DataService.set(player, "coins", after)
	analytics(
		"earn",
		player,
		if type(sku) == "string" then sku else "Unknown",
		credited,
		txType or "Gameplay"
	)
	return credited
end

-- Débite si assez (après settle) ; analytics puits
function EconomyService.trySpend(player: Player, amount: number, sku: string): boolean
	local data = DataService.get(player)
	if data == nil or not finite(amount) or amount < 0 then
		return false
	end
	local cost = if amount < Balance.Numbers.ExactBelow then math.ceil(amount) else amount
	EconomyService.settle(player)
	local coins = Formulas.clampCoins(data.coins)
	if coins < cost then
		return false
	end
	DataService.set(player, "coins", Formulas.clampCoins(coins - cost))
	analytics("spend", player, if type(sku) == "string" then sku else "Unknown", cost, "Shop")
	return true
end

-- Revenu actuel du joueur (enclos + Bassin, multiplicateurs compris)
function EconomyService.income(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return incomeAt(player, data, Clock.now())
end

-- Revenu actuel d'un squishy (k × taille du moment). Dodo et Lettres : revenu qu'il aurait dans un
-- enclos (taille figée à z), pour la vente (« 60 s de son revenu », GDD §4.13)
function EconomyService.squishyIncome(player: Player, uid: string): number
	local data = DataService.get(player)
	local rec = if data and type(data.squishies) == "table" then data.squishies[uid] else nil
	if data == nil or type(rec) ~= "table" then
		return 0
	end
	local G = Formulas.G(data.growth, Clock.now())
	return Formulas.income(Formulas.sizeAt(rec, G), rec.s, rec.m, rec.st, ctxOf(player, data))
end

-- Récompense « en secondes de revenu » : revenu du moment, P et B compris UNE seule fois (ils sont dans
-- le contexte du revenu, jamais remultipliés) ; rend le montant
function EconomyService.addIncomeSeconds(
	player: Player,
	seconds: number,
	sku: string,
	minimum: number?
): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	local amount = Formulas.secondsOfIncome(incomeAt(player, data, Clock.now()), seconds, minimum)
	return EconomyService.addCoins(player, amount, sku, "Gameplay")
end

-- Croissance cumulée du ranch (lecture)
function EconomyService.growth(player: Player): Types.Growth
	local data = DataService.get(player)
	if data == nil then
		return { G = 0, g = 0, t = Clock.now() }
	end
	local growth = data.growth
	return { G = growth.G, g = growth.g, t = growth.t }
end

-- G(t) du ranch
function EconomyService.G(player: Player, t: number?): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return Formulas.G(data.growth, if finite(t) then t :: number else Clock.now())
end

-- BuyTile v2.0 [UpgradesScreen, ou Tapis Étoilé par la dalle] : même fonction que BuyUpgrade(dalle, ×1,
-- niveau actuel) ;
-- « snack » achète le Tapis Étoilé au-delà du Tapis 12 (N21) ; Feedback de la v1.3 gardés (panneau) ;
-- UpgradeResult [UpgradesScreen] à chaque intention (reply) et à chaque achat sur la dalle
local function buyTileV2(
	player: Player,
	data: { [string]: any },
	tile: string,
	def: { [string]: any },
	source: "pad" | "panel",
	reply: boolean
): boolean
	local id, level = PadRules.target(data, tile)
	local function refuse(reason: string): boolean
		if reply then
			sendResult(player, {
				id = id,
				from = level,
				to = level,
				spent = 0,
				currency = "coins",
				reason = reason,
				snapshot = snapshotOf(player, data),
			})
		end
		return false
	end
	if level >= UpgradeMath.maxLevel(id) then
		if source == "panel" then
			Notify.feedback(player, "feedback.maxLevel", {}, "info")
		end
		return refuse(REFUSED.maxed)
	end
	if not PadRules.visible(data, tile) then
		-- dalle éteinte ; Tapis 12 sans Tapis Étoilé ouvert dans cette boucle : « niveau maximal » (v1.3)
		if source == "panel" and PadRules.level(data, tile) >= def.Levels then
			Notify.feedback(player, "feedback.maxLevel", {}, "info")
		end
		return refuse(capReason(data, id, level))
	end
	local payload, n = purchase(player, id, 1, level)
	if payload == nil then
		return false
	end
	if n < 1 then
		if source == "panel" and payload.reason == REFUSED.coins then
			local price =
				UpgradeMath.price(id, level, Prestige.r(data), Prestige.ascend(data), Prestige.bestR(data))
			local missing = math.max(1, price - EconomyService.coins(player))
			Notify.feedback(player, "feedback.notEnoughCoins", { missing = missing }, "warning")
		end
		if reply then
			sendResult(player, payload)
		end
		return false
	end
	-- célébration de la dalle (v1.3) ; le Tapis Étoilé continue la numérotation du Tapis (13 … 20)
	Notify.celebrate(player, "tile", { tile = tile, level = PadRules.progress(data, tile) })
	sendResult(player, payload)
	return true
end

-- Achète le niveau suivant (condition R, prix × Tiles.RScale^R si la dalle suit R) ; refus doux sur une
-- dalle (anneau, aucun Feedback) ; depuis le panneau : Feedback notEnoughCoins { missing }. reply :
-- intention BuyTile (v2.0 : UpgradeResult même sur un refus)
function EconomyService.buyTile(
	player: Player,
	tile: string,
	source: "pad" | "panel",
	reply: boolean?
): boolean
	local data = DataService.get(player)
	if data == nil or type(tile) ~= "string" then
		return false
	end
	local def = (Balance.Tiles :: any)[tile]
	local pad = (Pads.Defs :: any)[tile]
	if type(def) ~= "table" or type(pad) ~= "table" then
		return false
	end
	-- écran ouvert : le même chemin que BuyUpgrade ; Tapis Étoilé par la dalle (N21) même écran coupé.
	-- Sinon la v1.3 au bit près (prix Formulas.tileCost, le nombre que montre l'étiquette de la dalle)
	if Features.get("UpgradesScreen") == true or PadRules.target(data, tile) ~= tile then
		return buyTileV2(player, data, tile, def, source, reply == true)
	end
	local level = PadRules.level(data, tile)
	if level >= def.Levels then
		if source == "panel" then
			Notify.feedback(player, "feedback.maxLevel", {}, "info")
		end
		return false
	end
	if not PadRules.visible(data, tile) then
		return false -- dalle éteinte (R minimal, découverte, accueil)
	end
	local price = Formulas.tileCost(tile, level, data.R, Prestige.ascend(data))
	if price >= math.huge then
		return false
	end
	if not EconomyService.trySpend(player, price, "Tile_" .. tile) then
		if source == "panel" then
			local missing = math.max(1, price - EconomyService.coins(player))
			Notify.feedback(player, "feedback.notEnoughCoins", { missing = missing }, "warning")
		end
		return false
	end
	local newLevel = level + 1
	local tiles = data.tiles
	if tile == "cozyBed" then
		tiles.cozyBed = true
	else
		tiles[tile] = newLevel
	end
	tiles.seen = bit32.bor(math.floor(clampReal(tiles.seen, 0, 4294967295)), pad.seenBit)
	DataService.markDirty(player, "tiles")
	RanchService.refreshBuild(player)
	EconomyService.refresh(player)
	Signals.TileBought:Fire(player, tile, newLevel)
	-- v2.0 (docs/04 §27.4, relecture du lot A2) : UpgradeBought « en plus pour tout achat, dalles
	-- comprises », aussi sur ce chemin (écran coupé) : paliers du ranch [RanchTiers], Carnet. Signal
	-- interne seulement : interrupteurs coupés, aucun abonné n'envoie ni n'écrit rien
	Signals.UpgradeBought:Fire(player, tile, level, newLevel, "coins")
	Notify.celebrate(player, "tile", { tile = tile, level = newLevel })
	return true
end

-- Encaisse le Pot ; rend le montant (la fraction de pièce reste dans le Pot : rien ne se perd)
function EconomyService.collectPot(player: Player, auto: boolean): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	EconomyService.settle(player)
	local pot = clampReal(data.pot, 0, MAX)
	local whole = Formulas.clampCoins(pot)
	if whole < 1 then
		return 0
	end
	data.pot = clampReal(pot - whole, 0, MAX)
	DataService.markDirty(player, "pot")
	local credited = EconomyService.addCoins(player, whole, "Pot", "Gameplay")
	Signals.PotCollected:Fire(player, credited, auto == true)
	Notify.celebrate(player, "pot", { coins = credited, auto = auto == true })
	return credited
end

-- Niveau de Grand Splorch
function EconomyService.R(player: Player): number
	local data = DataService.get(player)
	return if data then clampReal(data.R, 0, 1e6) else 0
end

-- Fame bornée par les plafonds du jour (Rush 30, relâche 20 ; Grand Splorch et MEGA sans plafond) ;
-- rend la Fame accordée
function EconomyService.addFame(
	player: Player,
	amount: number,
	source: "rush" | "release" | "splorch" | "mega"
): number
	local data = DataService.get(player)
	if data == nil or not finite(amount) or amount <= 0 then
		return 0
	end
	local wanted = math.floor(amount)
	local granted = wanted
	if source == "rush" then
		granted = EconomyService.consumeCap(player, "fameRush", wanted)
	elseif source == "release" then
		granted = EconomyService.consumeCap(player, "fameRelease", wanted)
	elseif source ~= "splorch" and source ~= "mega" then
		return 0
	end
	if granted <= 0 then
		return 0
	end
	-- règlement AVANT le changement de Fame (A change) : l'intervalle passé garde l'ancien contexte
	EconomyService.settle(player)
	DataService.set(player, "fame", clampReal(clampReal(data.fame, 0, MAX) + granted, 0, MAX))
	EconomyService.refresh(player)
	RanchService.setPublic(player, { fame = data.fame })
	return granted
end

-- Plafond journalier (Balance.Caps ; v2.0 : Balance.CapsV2 dans un profil v2 seulement, Fame des
-- Grands Splorch et Pluies d'étoiles) : rend la part accordée (0 = plafond atteint)
function EconomyService.consumeCap(player: Player, capKey: string, wanted: number): number
	local data = DataService.get(player)
	local cap = (Balance.Caps :: any)[capKey]
	if cap == nil and data ~= nil and PadRules.v2Profile(data) then
		cap = (Balance.CapsV2 :: any)[capKey]
	end
	if data == nil or type(cap) ~= "number" or not finite(wanted) or wanted <= 0 then
		return 0
	end
	local caps = capsToday(player, data)
	local used = clampReal(caps[capKey], 0, cap)
	local granted = math.max(0, math.min(math.floor(wanted), cap - used))
	if granted > 0 then
		caps[capKey] = used + granted
		DataService.markDirty(player, "caps")
	end
	return granted
end

-- Plafond journalier PAR AMI (caps.petSitBy[tostring(friendUserId)], Balance.CapsPerFriend[capKey]) :
-- rend la part accordée (0 = plafond atteint) ; remis à zéro avec caps au changement de jour UTC
function EconomyService.consumeFriendCap(
	player: Player,
	capKey: string,
	friendUserId: number,
	wanted: number
): number
	local data = DataService.get(player)
	local cap = (Balance.CapsPerFriend :: any)[capKey]
	if data == nil or type(cap) ~= "number" or capKey ~= "petSit" then
		return 0
	end
	if not finite(friendUserId) or friendUserId % 1 ~= 0 or not finite(wanted) or wanted <= 0 then
		return 0
	end
	local caps = capsToday(player, data)
	local key = string.format("%d", friendUserId)
	local used = clampReal(caps.petSitBy[key], 0, cap)
	local granted = math.max(0, math.min(math.floor(wanted), cap - used))
	if granted > 0 then
		caps.petSitBy[key] = used + granted
		DataService.markDirty(player, "caps")
	end
	return granted
end

-- Croissance par seconde SANS boost (Formulas.growthRate avec boost = false) : bonus du Rush
-- (SquishyService.growFor), hors ligne
function EconomyService.gNoBoost(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	return Formulas.growthRate(growthCtx(data, false))
end

-- Boost personnel ×2 (secondes ajoutées, en pause pendant un boost de serveur)
function EconomyService.grantPersonalBoost(player: Player, seconds: number)
	local data = DataService.get(player)
	if data == nil or not finite(seconds) or seconds <= 0 then
		return
	end
	local now = Clock.now()
	checkpoint(player, data, now)
	local left = clampReal(data.boosts.personalLeft, 0, MAX)
	data.boosts.personalLeft = clampReal(left + seconds, 0, MAX)
	DataService.markDirty(player, "boosts")
	if not serverBoostActive(now) and runningSince[player] == nil then
		runningSince[player] = now
	end
	local ctx = ctxCache[player]
	if ctx ~= nil and not ctx.boost then
		EconomyService.refresh(player)
	end
end

-- Boost de serveur poussé par EventService ("wobble", "squish", "admin", "" = fin)
function EconomyService.setServerBoost(kind: string, untilT: number)
	if type(kind) ~= "string" then
		return
	end
	if kind == "" or not finite(untilT) then
		serverBoost = { kind = "", untilT = 0 }
	else
		serverBoost = { kind = kind, untilT = untilT }
	end
	local now = Clock.now()
	local serverOn = serverBoostActive(now)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data ~= nil and nextRefresh[player] ~= nil then
			Guard.try("economy:serverBoost", function()
				if serverOn then
					checkpoint(player, data, now)
					runningSince[player] = nil
				elseif clampReal(data.boosts.personalLeft, 0, MAX) > 0 and runningSince[player] == nil then
					runningSince[player] = now
				end
				local ctx = ctxCache[player]
				if ctx == nil or ctx.boost ~= boostOn(player, data, now) then
					EconomyService.refresh(player)
				end
			end)
		end
	end
end

-- B = 2 pour ce joueur (boost de serveur ou personnel, jamais cumulés)
function EconomyService.boostActive(player: Player): boolean
	local data = DataService.get(player)
	if data == nil then
		return serverBoostActive(Clock.now())
	end
	return boostOn(player, data, Clock.now())
end

-- Amis Roblox présents (poussé par CommunityService)
function EconomyService.setFriendsPresent(player: Player, count: number)
	local n = if finite(count) then math.max(0, math.floor(count)) else 0
	if friendsPresent[player] == n then
		return
	end
	friendsPresent[player] = n
	EconomyService.refresh(player)
end

-- Grand Splorch d'un bloc (sans yield) : pièces, Pot, Tapis, décorations à 0, R + 1, Fame + 5, G = 0 ;
-- rend les pièces perdues (pièces + Pot)
function EconomyService.applySplorch(player: Player): number
	local data = DataService.get(player)
	if data == nil then
		return 0
	end
	EconomyService.settle(player)
	local lost = Formulas.clampCoins(clampReal(data.coins, 0, MAX) + clampReal(data.pot, 0, MAX))
	data.coins = 0
	data.pot = 0
	for key, def in Balance.Tiles :: any do
		if type(def) == "table" and def.ResetOnSplorch == true and type(data.tiles[key]) == "number" then
			data.tiles[key] = 0
		end
	end
	data.R = math.floor(clampReal(data.R, 0, 1e6)) + 1
	data.fame = clampReal(clampReal(data.fame, 0, MAX) + Balance.Splorch.Fame, 0, MAX)
	local now = Clock.now()
	data.growth = { G = 0, g = data.growth.g, t = now }
	for _, key in { "coins", "pot", "tiles", "R", "fame", "growth" } do
		DataService.markDirty(player, key)
	end
	-- profil v2 dont la progression v2.0 est coupée (RecordR coupé ou configuration refusée :
	-- applyPrestige ne s'applique pas, journal A2-24) : le Record R n'est jamais sous r (invariant v2,
	-- docs/04 §27.2 ; note du lot A2, étape 1) ; les familles nouvelles de la boucle (Tapis Étoilé,
	-- Gants, École : kept = false) repartent de zéro comme le Tapis, dans le même bloc
	if PadRules.v2Profile(data) then
		if data.bestR ~= Prestige.bestR(data) then
			data.bestR = Prestige.bestR(data)
			DataService.markDirty(player, "bestR")
		end
		for _, def in Upgrades.Families do
			local field = string.match(def.profileKey, "^tiles%.(%w+)$")
			if
				not def.kept
				and not V1_TILES[def.id]
				and field ~= nil
				and type(data.tiles[field]) == "number"
			then
				data.tiles[field] = 0
			end
		end
	end
	RanchService.refreshBuild(player)
	EconomyService.refresh(player)
	RanchService.setPublic(player, { R = data.R, fame = data.fame })
	return lost
end

-- Progression v2.0 en vigueur pour ce joueur (lot A2, journal A2-24) : profil v2, interrupteur RecordR
-- ouvert et configuration en vigueur acceptée (Prestige.validateConfig) ; sinon le Grand Splorch reste
-- celui de la v1.3 (applySplorch) et ni Petit Splorch ni Jelly Ascend n'existent
function EconomyService.prestigeV2(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and PadRules.v2Profile(data) and Features.get("RecordR") == true and configOk
end

-- Lot A4 (D6) : un prestige du joueur est-il en cours d'application (spectacle, animation du Petit
-- Splorch : sonde de SplorchService ; sonde en erreur = oui) ? Avec prestigeV2, SquishyService refuse
-- alors vente, relâche et fusions de ce joueur (héros protégé pendant son spectacle)
function EconomyService.prestigeBusy(player: Player): boolean
	return prestigeBusy(player)
end

-- Lot A4 (D7, N1) : Record R du profil (Prestige.bestR ; 0 sans profil) : ce qui est « débloqué »
-- suit le Record R ; profil v1 : R, comme EconomyService.R
function EconomyService.recordR(player: Player): number
	local data = DataService.get(player)
	return if data then Prestige.bestR(data) else 0
end

-- Prestige v2.0 d'un bloc, sans yield (docs/04 §27.7, appelé par SplorchService) : règlement, puis
-- Prestige.apply (SEUL écrivain des champs gardés et remis à zéro : pièces, Pot, dalles de la boucle,
-- tailles, croissance, r, Record R, A, regainBonusA, memoryR, place offerte), cadeau du Splorch dans le
-- Pot (prix des niveaux offerts du Tapis dans la boucle neuve, UpgradeMath.giftCoins), clés marquées,
-- ranch reconstruit, contexte rafraîchi. Rend (clés changées, rapport) ; rapport nil si la progression
-- v2.0 n'est pas en vigueur (prestigeV2). Les gains du rapport (Confettis, Fame) sont versés par
-- l'appelant (addConfetti, addFame) ; la réplication des tailles par SquishyService.resetSizes (la clé
-- squishies n'est pas renvoyée entière)
function EconomyService.applyPrestige(
	player: Player,
	kind: Types.PrestigeKind
): ({ [string]: any }, Prestige.ApplyReport?)
	local data = DataService.get(player)
	if data == nil or not EconomyService.prestigeV2(player) then
		return {}, nil
	end
	-- règlement AVANT : l'intervalle passé garde l'ancien contexte (Pot, trophées et records à jour)
	EconomyService.settle(player)
	local changed, report = Prestige.apply(data, kind, Clock.now())
	if not report.applied then
		return changed, report
	end
	local gift = UpgradeMath.giftCoins(data, report.giftLevels)
	if finite(gift) and gift > 0 then
		data.pot = Formulas.clampCoins(gift)
		changed.pot = true
	end
	-- décorations dorées (docs/04 §27.2, §27.14 : EconomyService, au Grand Splorch ; relecture du lot
	-- A2) : chaque prestige appliqué (Grand, Petit, Ascension) finit une boucle ; chaque décoration
	-- construite à sa fin (n° k ≤ niveau d'avant la remise à zéro) y compte une fois, jusqu'à 10
	local builds = data.decorBuilds
	if type(builds) == "table" then
		local built = math.min(int(report.decorBefore, DECOR_BUILDS), DECOR_BUILDS)
		for k = 1, built do
			-- tableau dense (jamais un trou : JSON du DataStore)
			for i = #builds + 1, k - 1 do
				builds[i] = 0
			end
			local n = int(builds[k], DECOR_BUILDS_MAX)
			if n < DECOR_BUILDS_MAX then
				builds[k] = n + 1
				changed.decorBuilds = true
			end
		end
	end
	for key in changed do
		if key ~= "squishies" then
			DataService.markDirty(player, key)
		end
	end
	RanchService.refreshBuild(player)
	EconomyService.refresh(player)
	RanchService.setPublic(player, { R = Prestige.r(data), fame = data.fame })
	return changed, report
end

-- Crochet appelé après chaque settle avec G (SquishyService : trophées, record)
function EconomyService.onSettle(fn: (Player, number) -> ())
	if type(fn) == "function" then
		table.insert(settleHooks, fn)
	end
end

-- Contexte des multiplicateurs (lecture)
function EconomyService.incomeCtx(player: Player): Formulas.IncomeCtx
	local data = DataService.get(player)
	if data == nil then
		return {
			decor = 0,
			friends = 0,
			fame = 0,
			trophyBonus = 0,
			goldenPages = 0,
			doubleCoins = false,
			boost = false,
		}
	end
	return table.clone(ctxOf(player, data))
end

-- =============================================================================================
-- v2.0 (lot A2) : achats de l'écran Améliorations, Confettis, instantané, configuration
-- =============================================================================================

-- Achat de l'écran Améliorations (handler de BuyUpgrade ; BuyTile passe par le même cœur). Types
-- revérifiés (appel du serveur) : mode ∈ { 0, 1, 10 } AVANT UpgradeMath.plan (qui accepte 0-40),
-- niveau attendu entier ≥ 0, id ≤ 24 caractères ; refus de type ou id inconnu : nil, rien d'envoyé.
-- Sinon UpgradeResult envoyé (et rendu) : achat, refus avec sa raison, ou périmé muet (reason nil,
-- from = to, spent = 0). Interrupteur UpgradesScreen coupé : nil, rien d'envoyé, rien de changé.
function EconomyService.buyUpgrade(
	player: Player,
	id: string,
	mode: number,
	expectedLevel: number
): Types.UpgradeResultPayload?
	if Features.get("UpgradesScreen") ~= true then
		return nil
	end
	if typeof(player) ~= "Instance" or type(id) ~= "string" or #id > 24 then
		return nil
	end
	if not finite(mode) or not MODES[mode] then
		return nil
	end
	if not finite(expectedLevel) or expectedLevel % 1 ~= 0 or expectedLevel < 0 then
		return nil
	end
	local payload = purchase(player, id, mode, expectedLevel)
	if payload ~= nil then
		sendResult(player, payload)
	end
	return payload
end

-- Gain de Confettis : SEUL point d'entrée des gains (GDD v2.0 §4.26, critique m2 ; buyUpgrade est le
-- seul puits). n entier ≥ 1 (réel : partie entière), source connue (Signals.ConfettiChanged) ; borné
-- pour que confetti ≤ confettiTotal ≤ Balance.Confetti.Max. Rend le nombre crédité (0 : interrupteur
-- Confetti coupé, profil absent ou v1, source inconnue, montant illisible, plafond atteint ; refus
-- comptés : ConfettiRefused, ConfettiCapped)
function EconomyService.addConfetti(player: Player, n: number, source: string): number
	if Features.get("Confetti") ~= true then
		return 0
	end
	local data = DataService.get(player)
	if data == nil or not PadRules.v2Profile(data) then
		return 0
	end
	if type(source) ~= "string" or CONFETTI_SOURCES[source] ~= true or not finite(n) or n < 1 then
		diag("ConfettiRefused", player)
		return 0
	end
	local pocket = confettiOf(data)
	local total = math.max(pocket, int(data.confettiTotal, CONFETTI_MAX))
	local credit = math.min(math.floor(n), CONFETTI_MAX - total)
	if credit <= 0 then
		diag("ConfettiCapped", player)
		return 0
	end
	DataService.set(player, "confetti", pocket + credit)
	DataService.set(player, "confettiTotal", total + credit)
	Signals.ConfettiChanged:Fire(player, credit, source)
	return credit
end

-- Confettis en poche (lecture)
function EconomyService.confetti(player: Player): number
	local data = DataService.get(player)
	return if data then confettiOf(data) else 0
end

-- Instantané versionné de l'écran Améliorations (Types.UpgradeSnapshot ; version + 1 à chaque
-- contenu changé)
function EconomyService.snapshot(player: Player): Types.UpgradeSnapshot
	local data = DataService.get(player)
	if data == nil then
		return UpgradeMath.snapshot({}, Features, snapVersion[player] or 0)
	end
	return snapshotOf(player, data)
end

-- Sonde « un prestige est en cours d'application pour ce joueur » (SplorchService) : achats refusés
-- (upgrades.refused.busy) tant qu'elle répond vrai
function EconomyService.setBusyProbe(fn: (Player) -> boolean)
	if type(fn) == "function" then
		busyProbe = fn
	end
end

-- Invariant de stabilité d'une configuration (Prestige.validateConfig) : au chargement, et pour toute
-- configuration en direct ; un refus est compté (ConfigRefused, Diagnostics). La configuration en
-- vigueur (Config/Balance) refusée : achats v2.0 refusés (« busy ») tant qu'elle l'est (un prix lu
-- dans une table illisible n'est jamais débité)
function EconomyService.validateConfig(balance: any): (boolean, string?)
	local ok, why = Prestige.validateConfig(balance)
	if not ok then
		diag("ConfigRefused")
		Guard.try(
			"economy:configRefused",
			DiagnosticsService.report,
			"server",
			2,
			"ConfigRefused:" .. tostring(why),
			"",
			"",
			nil
		)
	end
	if rawequal(balance, Balance) then
		configOk, configWhy = ok, why
	end
	return ok, why
end

-- Configuration en vigueur acceptée (et la raison du refus sinon)
function EconomyService.configOk(): (boolean, string?)
	return configOk, configWhy
end

-- Compteurs du service (Diagnostics : UpgradeStale, ConfigRefused, ConfettiRefused, ConfettiCapped)
function EconomyService.counters(): { [string]: number }
	return table.clone(counters)
end

-- Bonus de pression v2.0 (N5, lus par SquishyService) : niveau des Gants [Gloves] et de la Super
-- Série de l'Atelier [Workshop] ; nil si l'interrupteur est coupé ou le profil v1 (pression v1.3)
function EconomyService.pressBonus(player: Player): (number?, number?)
	local data = DataService.get(player)
	if data == nil or not PadRules.v2Profile(data) then
		return nil, nil
	end
	local gloves = if Features.get("Gloves") == true then UpgradeMath.level("gloves", data) else nil
	local superStreak = if Features.get("Workshop") == true
		then UpgradeMath.level("superStreak", data)
		else nil
	return gloves, superStreak
end

return EconomyService
