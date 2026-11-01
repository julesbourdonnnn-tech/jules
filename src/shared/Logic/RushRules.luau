--!strict
-- RushRules (paquet logic, docs/04 §12.1). Règles du BOOP RUSH, testées règle par règle (GDD
-- §4.21.4) : ordre exact de vérification d'un boop et d'une capture de fuite, durée du maintien,
-- clôture, Wild Wobblers partagés, taille des bébés. Chaque refus rend un code stable (clé
-- « feedback.<code> » quand il est montré au joueur).
-- Robustesse : toute valeur bizarre (NaN, nil, ±inf) fait REFUSER, jamais accepter (les
-- comparaisons sont écrites « not (x <= limite) » pour qu'un NaN tombe du côté du refus).
-- Codes de checkBoop, dans l'ordre : feature, notRush, notRushMode, self, shieldOn, refused,
-- blocked, cooldown, notAtFence (atFence faux, puis eligible faux), bestFriend, moonOnly,
-- tooManyEscapes, tooFar (distance > 8 ou pas canAct).
-- Codes de checkCatch, dans l'ordre : notRushMode, booperLock, tooFar (distance ou écart vertical),
-- unstable (pas canAct).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math = type, math

local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Balance = require(script.Parent.Parent.Config.Balance)
local Events = require(script.Parent.Parent.Config.Events)
local Species = require(script.Parent.Parent.Config.Species)
local Rarities = require(script.Parent.Parent.Config.Rarities)

export type BoopCtx = {
	feature: string, -- Features.BoopRush
	eventActive: boolean, -- Lune ou fête d'administrateur (mode "events")
	rushActive: boolean,
	booperRush: boolean,
	ownerRush: boolean,
	sameUser: boolean,
	ownerShield: boolean,
	refused: boolean, -- « Pas ce joueur »
	blocked: boolean, -- liste de blocage souple
	booperCooldownLeft: number,
	pairCooldownLeft: number,
	atFence: boolean,
	-- toujours éligible à la clôture (RushRules.fenceEligible avec le lieu actuel : ni porté, ni
	-- Bassin, ni Dodo, ni en attente…) ; faux → refus "notAtFence", vérifié au début et à chaque tick
	eligible: boolean,
	bestFriend: boolean,
	rarity: number,
	moonBoopable: boolean,
	ranchThisRush: number,
	ranchThisHour: number,
	serverEscapes: number,
	distance: number, -- studs (position validée du boopeur → squishy à la clôture)
	canAct: boolean,
}

export type CatchCtx = {
	catcherRush: boolean,
	isBooper: boolean,
	age: number, -- s depuis le début de la fuite
	isOwner: boolean,
	distance: number,
	dy: number,
	canAct: boolean,
}

export type FenceCtx = {
	now: number, -- Clock.unix()
	carried: string, -- uid porté ("" = aucun)
	waiting: string, -- uid en attente de Grand Splorch
	returnedThisRush: { [string]: boolean },
	moonBoopable: boolean,
}

local RushRules = {}

local RUSH = Events.Rush
local CATCH = Balance.Catch

local function yes(x: any): boolean
	return x == true
end

-- x ≤ limite, faux pour NaN, nil ou une valeur qui n'est pas un nombre
local function atMost(x: any, limit: number): boolean
	return type(x) == "number" and x <= limit
end

-- x < limite, faux pour NaN ou nil
local function below(x: any, limit: number): boolean
	return type(x) == "number" and x < limit
end

-- Ordre du GDD §4.21.4 ; (true) ou (false, code du premier refus)
function RushRules.checkBoop(ctx: BoopCtx): (boolean, string?)
	local c: any = if type(ctx) == "table" then ctx else {}
	local feature = c.feature
	if feature ~= "on" and not (feature == "events" and yes(c.eventActive)) then
		return false, "feature"
	end
	if not yes(c.rushActive) then
		return false, "notRush"
	end
	if not yes(c.booperRush) or not yes(c.ownerRush) then
		return false, "notRushMode"
	end
	if c.sameUser ~= false then
		return false, "self"
	end
	if c.ownerShield ~= false then
		return false, "shieldOn"
	end
	if c.refused ~= false then
		return false, "refused"
	end
	if c.blocked ~= false then
		return false, "blocked"
	end
	if not atMost(c.booperCooldownLeft, 0) or not atMost(c.pairCooldownLeft, 0) then
		return false, "cooldown"
	end
	if not yes(c.atFence) or not yes(c.eligible) then
		return false, "notAtFence"
	end
	if c.bestFriend ~= false then
		return false, "bestFriend"
	end
	local rarity = c.rarity
	if
		type(rarity) ~= "number"
		or rarity ~= rarity
		or rarity % 1 ~= 0
		or rarity < 1
		or rarity > Rarities.Count
	then
		return false, "moonOnly" -- rareté illisible ou inconnue : jamais boopable
	end
	if RUSH.MoonOnlyRarities[rarity] and not yes(c.moonBoopable) then
		return false, "moonOnly"
	end
	if
		not below(c.ranchThisRush, RUSH.PerRanchPerRush)
		or not below(c.ranchThisHour, RUSH.PerRanchPerHour)
		or not below(c.serverEscapes, RUSH.ServerMax)
	then
		return false, "tooManyEscapes"
	end
	if not atMost(c.distance, RUSH.BoopRadius) or not yes(c.canAct) then
		return false, "tooFar"
	end
	return true, nil
end

-- 2,5 s, ou 5 s si le propriétaire est à 25 studs de sa clôture
function RushRules.holdTime(ownerNear: boolean): number
	return if yes(ownerNear) then RUSH.HoldTimeOwnerNear else RUSH.HoldTime
end

-- Le propriétaire arrive pendant le maintien : le temps restant double. Appliqué UNE SEULE FOIS par
-- maintien (le service le mémorise) : la durée totale ne dépasse jamais StateTimeouts boopHold.
-- Garde-fous : un reste plus long que HoldTime n'est jamais doublé ; avec `startedAt` (paramètre
-- ajouté, facultatif : début du maintien), la fin ne dépasse jamais startedAt + HoldTimeOwnerNear
-- (5 s), même si le service l'appelait deux fois ou sur un maintien déjà long.
function RushRules.extendHold(endsAt: number, now: number, startedAt: number?): number
	local finiteNow = type(now) == "number" and now == now and math.abs(now) ~= math.huge
	local finiteEnd = type(endsAt) == "number" and endsAt == endsAt and math.abs(endsAt) ~= math.huge
	if not finiteEnd then
		return if finiteNow then now else 0
	end
	if not finiteNow then
		return endsAt
	end
	local remaining = endsAt - now
	if remaining <= 0 then
		return now -- déjà fini
	end
	if remaining > RUSH.HoldTime then
		return endsAt -- maintien déjà long (propriétaire proche dès le début) : rien à doubler
	end
	local extended = now + 2 * remaining
	if type(startedAt) == "number" and startedAt == startedAt and math.abs(startedAt) ~= math.huge then
		extended = math.max(endsAt, math.min(extended, startedAt + RUSH.HoldTimeOwnerNear))
	end
	return extended
end

-- Ordre de vérification d'une capture de fuite du Rush
function RushRules.checkCatch(ctx: CatchCtx): (boolean, string?)
	local c: any = if type(ctx) == "table" then ctx else {}
	if not yes(c.catcherRush) then
		return false, "notRushMode"
	end
	if c.isBooper ~= false and not (type(c.age) == "number" and c.age >= RUSH.BooperLock) then
		return false, "booperLock"
	end
	local radius = RushRules.catchRadius(yes(c.isOwner))
	if not atMost(c.distance, radius) then
		return false, "tooFar"
	end
	if not (type(c.dy) == "number" and math.abs(c.dy) <= CATCH.MaxDY) then
		return false, "tooFar"
	end
	if not yes(c.canAct) then
		return false, "unstable"
	end
	return true, nil
end

-- Rayon serveur (5 + 1,5 ; 8 + 1,5 pour le propriétaire)
function RushRules.catchRadius(isOwner: boolean): number
	return (if yes(isOwner) then CATCH.OwnerRadius else CATCH.Radius) + CATCH.Tolerance
end

-- Squishies curieux à la clôture (4, ou 2)
function RushRules.fenceCount(boopedLastRush: boolean): number
	return if yes(boopedLastRush) then RUSH.FenceAfterBooped else RUSH.FenceMax
end

-- Le squishy peut venir à la clôture (ni Meilleur Ami, ni porté, ni Bassin, ni Dodo, ni en attente,
-- ni né il y a < 60 s, ni rentré ce Rush ; Mythique/Secret seulement pendant la Lune).
-- `uid` (paramètre ajouté, facultatif) : uid de la ligne, comparé à ctx.carried, ctx.waiting et
-- ctx.returnedThisRush. Les appelants le passent toujours ; sans lui, la ligne est supposée être
-- celle qui est portée, en attente ou rentrée dès que l'une de ces listes n'est pas vide (refus :
-- le côté sûr).
function RushRules.fenceEligible(rec: Types.SquishyRecord, ctx: FenceCtx, uid: string?): boolean
	if type(rec) ~= "table" or type(ctx) ~= "table" then
		return false
	end
	local r: any = rec
	local c: any = ctx
	if r.at ~= "pen" then
		return false -- Bassin, Dodo, Lettres
	end
	if r.bf ~= 0 then
		return false -- Meilleur Ami (ou valeur illisible : refus, le côté sûr)
	end
	local def = Species.ById[r.s]
	if def == nil then
		return false
	end
	if RUSH.MoonOnlyRarities[def.rarity] and not yes(c.moonBoopable) then
		return false
	end
	-- né il y a moins de 60 s (horodatage illisible : refusé)
	if not (type(r.b) == "number" and type(c.now) == "number" and c.now - r.b >= RUSH.FenceNewbornMin) then
		return false
	end
	local carried = if type(c.carried) == "string" then c.carried else ""
	local waiting = if type(c.waiting) == "string" then c.waiting else ""
	local returned = if type(c.returnedThisRush) == "table" then c.returnedThisRush else {}
	local key = if type(uid) == "string" then uid else (if type(r.uid) == "string" then r.uid else nil)
	if key == nil then
		return carried == "" and waiting == "" and next(returned) == nil
	end
	if key == carried or key == waiting or returned[key] == true then
		return false
	end
	return true
end

-- Wild Wobblers partagés : 3 + 2 × max(0, 6 − N)
function RushRules.wildShared(players: number): number
	local wild = Events.Wild
	local n = if type(players) == "number" and players == players then math.floor(players) else 1
	n = math.max(1, n)
	return wild.SharedBase + wild.SharedPerMissing * math.max(0, wild.SharedFullServer - n)
end

-- min(10 % de l'original, 2 × plus gros du receveur), minimum 1
function RushRules.babySize(original: number, receiverBiggest: number): number
	local babies = Balance.Babies
	return Formulas.babySize(babies.RushShare, babies.RushMin, receiverBiggest, Formulas.clampSize(original))
end

return RushRules
