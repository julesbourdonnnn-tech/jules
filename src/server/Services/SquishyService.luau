--!strict
-- SquishyService (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Collection et gestes du ranch (GDD §4.3, §4.7, §4.9, §4.10, §4.12-§4.16) : squishies (uid base 36,
-- espèce, taille paresseuse, étoiles, mutation, Meilleur Ami, verrou, tenue, lieu), presser SPLORCH
-- (recharge 8 s par squishy, PERFECT, série, 12 / s ; portée à plat ≤ 10 + 2 du centre de la place du
-- squishy, pieds), Cuve à Gelée (minuteur du serveur, Odds ; naissance en enclos, sinon dans la Boîte à
-- dodo ; goutte en attente seulement si enclos ET Dodo sont pleins ; accueil scripté), Bassin et combos
-- (minuteurs 0,4 / 0,6 s dans step), bonus de croissance du Rush une fois par squishy et par jour
-- (growFor, champ gd), portage
-- (état du serveur, fin dans 6 cas), Tout fusionner, Dodo, Lettres, vendre / ranger / relâcher (12
-- derniers dans la Prairie), verrou automatique, Meilleurs Amis (1 / 2 / 3 selon R), monture (selle
-- gagnée par le record, WalkSpeed / JumpHeight / HipHeight fixes, MoveCheck.setRootOffset(player,
-- hausse, hauteur de saut) à chaque montée et descente), tenues (portées gardées dans rec.o seulement),
-- trophées. Un squishy qui quitte l'enclos (portage, lancer, Dodo,
-- fusion, attente, vente, relâche) est retiré AUSSITÔT de sa clôture (RanchService.setFence). Émet Pressed,
-- SquishyObtained, Hatched, Fused, SquishyRemoved. Remotes : Press, PickUp, PutDown, Throw, FuseMenu,
-- FuseAll, MoveSquishy, ClaimMail, Sell, Release, SetLock, SetBestFriend, SetMount, Ride, EquipOutfit.
-- Clés : squishies, nextUid, mount, vat, released, trophies, outfits, biggestEver.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local RushRules = require(Shared.Logic.RushRules)

export type Counts = {
	pen: number,
	pool: number,
	dodo: number,
	mail: number,
	penCapacity: number,
	poolSlots: number,
}
export type GiveSpec = { s: number, m: number, st: number, z: number }

local SquishyService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function SquishyService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function SquishyService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : gouttes dues, fusions et combos dus, portage hors du ranch terminé
function SquishyService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = { now, actors }
	error("TODO(ranch): SquishyService.step")
end

-- Collection (lecture seule)
function SquishyService.records(player: Player): { [string]: Types.SquishyRecord }
	local _ = { player }
	error("TODO(ranch): SquishyService.records")
end

-- Une ligne (lecture seule)
function SquishyService.get(player: Player, uid: string): Types.SquishyRecord?
	local _ = { player, uid }
	error("TODO(ranch): SquishyService.get")
end

-- Taille actuelle
function SquishyService.sizeOf(player: Player, uid: string, t: number?): number
	local _ = { player, uid, t }
	error("TODO(ranch): SquishyService.sizeOf")
end

-- Plus gros squishy (enclos et Bassin) et sa taille
function SquishyService.biggest(player: Player): (string?, number)
	local _ = { player }
	error("TODO(ranch): SquishyService.biggest")
end

-- Places occupées et capacités
function SquishyService.counts(player: Player): Counts
	local _ = { player }
	error("TODO(ranch): SquishyService.counts")
end

-- Ajoute un squishy (enclos → Dodo → Lettres → pièces) ; rend (uid, lieu ou "coins")
function SquishyService.give(player: Player, spec: GiveSpec, source: string): (string?, string)
	local _ = { player, spec, source }
	error("TODO(ranch): SquishyService.give")
end

-- Naissance scriptée de l'accueil (jumeau de Plop, premier vrai tirage)
function SquishyService.hatchScripted(player: Player, kind: "twin" | "firstPull")
	local _ = { player, kind }
	error("TODO(ranch): SquishyService.hatchScripted")
end

-- Pression (chez soi, ou pet-sitting par visitor) ; récompenses et Signals.Pressed
function SquishyService.press(owner: Player, uid: string, tClient: number, visitor: Player?): boolean
	local _ = { owner, uid, tClient, visitor }
	error("TODO(ranch): SquishyService.press")
end

-- uid porté
function SquishyService.carried(player: Player): string?
	local _ = { player }
	error("TODO(ranch): SquishyService.carried")
end

-- Le squishy porté retourne à sa place
function SquishyService.endCarry(player: Player, reason: string)
	local _ = { player, reason }
	error("TODO(ranch): SquishyService.endCarry")
end

-- Sur sa monture
function SquishyService.riding(player: Player): boolean
	local _ = { player }
	error("TODO(ranch): SquishyService.riding")
end

-- Descend (mort, Bassin, prise, panneau)
function SquishyService.dismount(player: Player, reason: string)
	local _ = { player, reason }
	error("TODO(ranch): SquishyService.dismount")
end

-- Grand Splorch : chaque squishy repasse à la taille 1 (z = 1, zg = 0)
function SquishyService.resetSizes(player: Player)
	local _ = { player }
	error("TODO(ranch): SquishyService.resetSizes")
end

-- Squishy en attente de Grand Splorch (ni boopable, ni vendable, ni fusionnable)
function SquishyService.setWaiting(player: Player, uid: string?)
	local _ = { player, uid }
	error("TODO(ranch): SquishyService.setWaiting")
end

-- Bonus de croissance du Rush : z += EconomyService.gNoBoost × seconds (Héros 3 600 s, retour seul
-- 1 800 s : Balance.RushSize), au plus une fois par squishy et par jour UTC (rec.gd = Clock.day()) ;
-- rend false si déjà accordé aujourd'hui (les pièces et la Fame restent dues)
function SquishyService.growFor(player: Player, uid: string, seconds: number): boolean
	local _ = { player, uid, seconds }
	error("TODO(ranch): SquishyService.growFor")
end

-- uid en attente de Grand Splorch (nil = aucun) : RushService n'amène aucun squishy de ce joueur à la clôture
function SquishyService.waiting(player: Player): string?
	local _ = { player }
	error("TODO(ranch): SquishyService.waiting")
end

-- uid d'un squishy du joueur en fuite (setEscaping), nil = aucun : SplorchService refuse l'entrée dans la
-- file du Grand Splorch (Feedback waitEscape ; ChaseService, plus tardif, n'est jamais appelé)
function SquishyService.anyEscaping(player: Player): string?
	local _ = { player }
	error("TODO(ranch): SquishyService.anyEscaping")
end

-- En fuite (exclu du portage, de la vente, de la fusion)
function SquishyService.setEscaping(player: Player, uid: string, escaping: boolean)
	local _ = { player, uid, escaping }
	error("TODO(ranch): SquishyService.setEscaping")
end

-- uid du Meilleur Ami n° slot
function SquishyService.bestFriend(player: Player, slot: number): string?
	local _ = { player, slot }
	error("TODO(ranch): SquishyService.bestFriend")
end

-- Squishies prêts à venir à la clôture
function SquishyService.fenceCandidates(player: Player, ctx: RushRules.FenceCtx): { string }
	local _ = { player, ctx }
	error("TODO(ranch): SquishyService.fenceCandidates")
end

-- Clock.now() où la recharge de pression finit
function SquishyService.readyAt(player: Player, uid: string): number
	local _ = { player, uid }
	error("TODO(ranch): SquishyService.readyAt")
end

-- Selle gagnée 0 … 3
function SquishyService.saddle(player: Player): number
	local _ = { player }
	error("TODO(ranch): SquishyService.saddle")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « carry » (porté), « fusion », « combo », « hatch » (échéances dues) ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function SquishyService.openStates(): { Types.OpenState }
	error("TODO(ranch): SquishyService.openStates")
end

return SquishyService
