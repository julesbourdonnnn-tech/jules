--!strict
-- RushRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Règles du BOOP RUSH, testées règle par règle (GDD §4.21.4) : ordre exact de vérification d'un boop
-- et d'une capture de fuite, durée du maintien, clôture, Wild Wobblers partagés, taille des bébés.
-- Chaque refus rend un code stable (clé « feedback.<code> » quand il est montré au joueur).

local Types = require(script.Parent.Parent.Types)

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

-- Ordre du GDD §4.21.4 ; (true) ou (false, code du premier refus)
function RushRules.checkBoop(ctx: BoopCtx): (boolean, string?)
	local _ = { ctx }
	error("TODO(logic): RushRules.checkBoop")
end

-- 2,5 s, ou 5 s si le propriétaire est à 25 studs de sa clôture
function RushRules.holdTime(ownerNear: boolean): number
	local _ = { ownerNear }
	error("TODO(logic): RushRules.holdTime")
end

-- Le propriétaire arrive pendant le maintien : le temps restant double. Appliqué UNE SEULE FOIS par
-- maintien (le service le mémorise) : la durée totale ne dépasse jamais StateTimeouts boopHold.
function RushRules.extendHold(endsAt: number, now: number): number
	local _ = { endsAt, now }
	error("TODO(logic): RushRules.extendHold")
end

-- Ordre de vérification d'une capture de fuite du Rush
function RushRules.checkCatch(ctx: CatchCtx): (boolean, string?)
	local _ = { ctx }
	error("TODO(logic): RushRules.checkCatch")
end

-- Rayon serveur (5 + 1,5 ; 8 + 1,5 pour le propriétaire)
function RushRules.catchRadius(isOwner: boolean): number
	local _ = { isOwner }
	error("TODO(logic): RushRules.catchRadius")
end

-- Squishies curieux à la clôture (4, ou 2)
function RushRules.fenceCount(boopedLastRush: boolean): number
	local _ = { boopedLastRush }
	error("TODO(logic): RushRules.fenceCount")
end

-- Le squishy peut venir à la clôture (ni Meilleur Ami, ni porté, ni Bassin, ni Dodo, ni en attente, ni né il y a < 60 s, ni rentré ce Rush ; Mythique/Secret seulement pendant la Lune)
function RushRules.fenceEligible(rec: Types.SquishyRecord, ctx: FenceCtx): boolean
	local _ = { rec, ctx }
	error("TODO(logic): RushRules.fenceEligible")
end

-- Wild Wobblers partagés : 3 + 2 × max(0, 6 − N)
function RushRules.wildShared(players: number): number
	local _ = { players }
	error("TODO(logic): RushRules.wildShared")
end

-- min(10 % de l'original, 2 × plus gros du receveur), minimum 1
function RushRules.babySize(original: number, receiverBiggest: number): number
	local _ = { original, receiverBiggest }
	error("TODO(logic): RushRules.babySize")
end

return RushRules
