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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Pads = require(Shared.Config.Pads)
local Formulas = require(Shared.Logic.Formulas)
local QuestRules = require(Shared.Logic.QuestRules)
local Signals = require(script.Parent.Parent.Signals)
local Notify = require(script.Parent.Parent.Util.Notify)
local Analytics = require(script.Parent.Parent.Util.Analytics)
local Guard = require(script.Parent.Parent.Ranch.Guard)
local PadRules = require(script.Parent.Parent.Ranch.PadRules)
local DataService = require(script.Parent.DataService)
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
local function computeCtx(player: Player, data: { [string]: any }, boost: boolean): Formulas.IncomeCtx
	local doubleCoins = false
	local ok, owns = pcall(MonetizationService.ownsPass, player, "DoubleCoins")
	if ok and owns == true then
		doubleCoins = true
	end
	return {
		decor = clampReal(data.tiles.decor, 0, Balance.Tiles.decor.Levels),
		friends = friendsPresent[player] or 0,
		fame = clampReal(data.fame, 0, MAX),
		trophyBonus = Formulas.trophyBonus(data.trophies),
		goldenPages = QuestRules.goldenPages(data.dex),
		doubleCoins = doubleCoins,
		boost = boost,
	}
end

local function growthCtx(data: { [string]: any }, boost: boolean): Formulas.GrowthCtx
	return {
		R = clampReal(data.R, 0, 1e6),
		snack = clampReal(data.tiles.snack, 0, Balance.Tiles.snack.Levels),
		jellyFamily = familyEarned(data, "jelly"),
		boost = boost,
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

-- Remise à zéro des plafonds au changement de jour UTC (petSitBy compris)
local function capsToday(player: Player, data: { [string]: any }): { [string]: any }
	local caps = data.caps
	local today = Clock.day()
	if caps.day ~= today then
		for key in Balance.Caps do
			caps[key] = 0
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
		familyEarned(data, "spiky")
	)
	local G0 = clampReal(growth.G, 0, MAX)
	local R = clampReal(data.R, 0, 1e6)
	local _, biggest = biggestAt(data, G0)
	local target = Formulas.splorchTarget(R)
	local gNoBoost = Formulas.growthRate(growthCtx(data, false))
	local grew = 0
	local potAdd = 0
	if seconds > 0 then
		grew = Formulas.offlineGrowth(gNoBoost, seconds, R, biggest)
		-- revenu de départ sans boost (P compris : un pass est permanent ; amis absents)
		local ctx: Formulas.IncomeCtx = {
			decor = clampReal(data.tiles.decor, 0, Balance.Tiles.decor.Levels),
			friends = 0,
			fame = clampReal(data.fame, 0, MAX),
			trophyBonus = Formulas.trophyBonus(data.trophies),
			goldenPages = QuestRules.goldenPages(data.dex),
			doubleCoins = type(data.passes) == "table" and data.passes.DoubleCoins == true,
			boost = false,
		}
		local K, S1 = Formulas.ranchIncome(data.squishies, G0, ctx)
		potAdd = Formulas.offlinePot(clampReal(S1 + K * G0, 0, MAX), seconds)
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
		local bought = EconomyService.buyTile(player, tile, source)
		if bought then
			-- achat voulu : il compte pour l'entrée sur cette dalle (aucun 2e niveau à la fin de l'anneau)
			RanchService.notePadPurchase(player, tile)
		end
		return bought
	end)
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

-- Achète le niveau suivant (condition R, prix × Tiles.RScale^R si la dalle suit R) ; refus doux sur une
-- dalle (anneau, aucun Feedback) ; depuis le panneau : Feedback notEnoughCoins { missing }
function EconomyService.buyTile(player: Player, tile: string, source: "pad" | "panel"): boolean
	local data = DataService.get(player)
	if data == nil or type(tile) ~= "string" then
		return false
	end
	local def = (Balance.Tiles :: any)[tile]
	local pad = (Pads.Defs :: any)[tile]
	if type(def) ~= "table" or type(pad) ~= "table" then
		return false
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
	local price = Formulas.tileCost(tile, level, data.R)
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

-- Plafond journalier (Balance.Caps) : rend la part accordée (0 = plafond atteint)
function EconomyService.consumeCap(player: Player, capKey: string, wanted: number): number
	local data = DataService.get(player)
	local cap = (Balance.Caps :: any)[capKey]
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
	RanchService.refreshBuild(player)
	EconomyService.refresh(player)
	RanchService.setPublic(player, { R = data.R, fame = data.fame })
	return lost
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

return EconomyService
