--!strict
-- QuestRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Objectifs du jour faisables (« Proposé si », GDD §7.4), tirage déterministe Hash(jour, UserId),
-- relance, progression, remise à zéro de minuit en pleine session (terminés réclamés seuls, en cours
-- gardés jusqu'à la fin de la session), paliers de Nourrir Plop et du Squishydex, bonus de famille et
-- pages dorées (lus aussi par EconomyService et SquishyService, qui précèdent QuestService).

local Types = require(script.Parent.Parent.Types)
local Quests = require(script.Parent.Parent.Config.Quests)

export type QuestCtx = {
	R: number,
	tilesLeft: number, -- achats de dalle encore possibles dans la boucle
	megaIn: number, -- s avant le prochain MEGA
	friendOnServer: boolean,
	splorchEta: number, -- s estimées jusqu'à l'objectif (taille qui manque ÷ croissance)
	stamps: number,
}

local QuestRules = {}

-- Règle « Proposé si » de l'objectif dans la situation du joueur
function QuestRules.eligible(def: Quests.ObjectiveDef, ctx: QuestCtx): boolean
	local _ = { def, ctx }
	error("TODO(logic): QuestRules.eligible")
end

-- 3 objectifs (facile, moyen, difficile) ; jour 1 : Quests.ObjectiveRules.Day1
function QuestRules.draw(userId: number, day: number, ctx: QuestCtx, firstDay: boolean): { number }
	local _ = { userId, day, ctx, firstDay }
	error("TODO(logic): QuestRules.draw")
end

-- Nouvel objectif du même niveau pour cette case, différent des 3 actuels
function QuestRules.reroll(
	userId: number,
	day: number,
	current: { number },
	slot: number,
	ctx: QuestCtx,
	salt: number
): number
	local _ = { userId, day, current, slot, ctx, salt }
	error("TODO(logic): QuestRules.reroll")
end

-- Progression d'un objectif par un événement (série PERFECT remise à 0 par une pression ratée)
function QuestRules.apply(
	entry: Types.ObjectiveEntry,
	stat: string,
	amount: number,
	perfect: boolean?
): Types.ObjectiveEntry
	local _ = { entry, stat, amount, perfect }
	error("TODO(logic): QuestRules.apply")
end

-- Minuit en session : (liste gardée, ids terminés à réclamer d'office)
function QuestRules.rollover(
	list: { Types.ObjectiveEntry },
	autoClaim: boolean
): ({ Types.ObjectiveEntry }, { number })
	local _ = { list, autoClaim }
	error("TODO(logic): QuestRules.rollover")
end

-- Palier de Nourrir Plop atteint à ce total de jours
function QuestRules.plopReward(days: number): Quests.PlopReward?
	local _ = { days }
	error("TODO(logic): QuestRules.plopReward")
end

-- Jalons atteints et non réclamés
function QuestRules.dexMilestones(stamps: number, lastClaimed: number): { Quests.DexMilestone }
	local _ = { stamps, lastClaimed }
	error("TODO(logic): QuestRules.dexMilestones")
end

-- Tampons d'espèces + de mutations
function QuestRules.stampCount(dex: { [string]: any }): number
	local _ = { dex }
	error("TODO(logic): QuestRules.stampCount")
end

-- Badges d'étoiles (★1 à ★5 par espèce)
function QuestRules.starBadges(dex: { [string]: any }): number
	local _ = { dex }
	error("TODO(logic): QuestRules.starBadges")
end

-- Les 4 espèces de la famille tamponnées (Secrets : jamais)
function QuestRules.familyComplete(dex: { [string]: any }, family: string): boolean
	local _ = { dex, family }
	error("TODO(logic): QuestRules.familyComplete")
end

-- Espèces dont les 8 mutations hors Lunaire sont trouvées
function QuestRules.goldenPages(dex: { [string]: any }): number
	local _ = { dex }
	error("TODO(logic): QuestRules.goldenPages")
end

-- La naissance remplit une entrée encore vide (espèce, mutation ou badge d'étoiles)
function QuestRules.isNewStamp(
	dex: { [string]: any },
	species: number,
	mutation: number,
	stars: number
): boolean
	local _ = { dex, species, mutation, stars }
	error("TODO(logic): QuestRules.isNewStamp")
end

return QuestRules
