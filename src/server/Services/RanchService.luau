--!strict
-- RanchService (paquet ranch) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Ranchs 1-16 (GDD §6.1, §6.3, §4.6, §4.8, §12.5) : attribution à l'arrivée (ranch libre le plus
-- proche d'un ami Roblox présent, IsFriendsWith sous pcall et en cache), placement du personnage à
-- chaque apparition (HumanoidRootPart attendu 10 s, PivotTo sur WorldLayout.spawnCFrame, repli sur la
-- place), serveur plein (message puis renvoi après 30 s sauf ranch libéré), poussée des intrus à
-- chaque tick (6 studs devant le portail, message « C'est le ranch de … »), Pot encaissé à ≤ 5 studs,
-- entrée sur une dalle = un achat (ZoneRules, hystérésis), état public des ranchs (RanchSnapshot à
-- l'arrivée, RanchPatch groupé et numéroté par destinataire), clôtures (Fence, pour RushService et
-- CommunityService). PlayerReady au premier placement et au plus tard 15 s après le chargement
-- (StateTimeouts playerReady), même si le placement échoue. Attribut Player « RanchSlot ». Émet
-- PlayerReady, ServerMoved, WorldRequested.
-- Remotes : RequestWorld (handler) ; RanchSnapshot, RanchPatch, Fence (envoi). Clés : aucune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local RanchService = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function RanchService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function RanchService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Ranch du joueur (0 = aucun)
function RanchService.slotOf(player: Player): number
	local _ = { player }
	error("TODO(ranch): RanchService.slotOf")
end

-- Propriétaire présent du ranch
function RanchService.playerAt(slot: number): Player?
	local _ = { slot }
	error("TODO(ranch): RanchService.playerAt")
end

-- PlayerReady déjà émis pour ce joueur dans cette session
function RanchService.isReady(player: Player): boolean
	local _ = { player }
	error("TODO(ranch): RanchService.isReady")
end

-- Replace le personnage à son point d'apparition (PivotTo + Signals.ServerMoved)
function RanchService.place(player: Player)
	local _ = { player }
	error("TODO(ranch): RanchService.place")
end

-- Tick : intrus repoussés, Pot, entrées sur les dalles (positions validées, canAct)
function RanchService.step(now: number, actors: { [Player]: Types.TickActor })
	local _ = { now, actors }
	error("TODO(ranch): RanchService.step")
end

-- Champs de RanchPublic changés (fusionnés dans le prochain RanchPatch)
function RanchService.setPublic(player: Player, fields: { [string]: any })
	local _ = { player, fields }
	error("TODO(ranch): RanchService.setPublic")
end

-- Changement d'un squishy visible (enclos ou Bassin)
function RanchService.squishyOp(
	player: Player,
	op: "add" | "remove" | "update",
	uid: string,
	rec: Types.PublicSquishy?
)
	local _ = { player, op, uid, rec }
	error("TODO(ranch): RanchService.squishyOp")
end

-- Squishies posés à la clôture ("rush" passe avant "petsit")
function RanchService.setFence(slot: number, uids: { string }, reason: "rush" | "petsit" | "")
	local _ = { slot, uids, reason }
	error("TODO(ranch): RanchService.setFence")
end

-- (uids à la clôture, raison)
function RanchService.fenceOf(slot: number): ({ string }, string)
	local _ = { slot }
	error("TODO(ranch): RanchService.fenceOf")
end

-- État public d'un ranch
function RanchService.publicOf(slot: number): Types.RanchPublic?
	local _ = { slot }
	error("TODO(ranch): RanchService.publicOf")
end

-- Crochet du service plus tardif (EconomyService) : step l'appelle quand le joueur entre sur le Pot ("pot", "") ou sur une dalle ("pad", clé de la dalle)
function RanchService.setZoneHandler(kind: "pot" | "pad", handler: (Player, string) -> ())
	local _ = { kind, handler }
	error("TODO(ranch): RanchService.setZoneHandler")
end

-- Relit le profil (dalles, accueil) et met à jour le ranch construit (WorldService.setRanchBuild) et l'état public
function RanchService.refreshBuild(player: Player)
	local _ = { player }
	error("TODO(ranch): RanchService.refreshBuild")
end

-- Envoie le RanchPatch groupé du tick (appelé par ChaseService à la fin du tick)
function RanchService.flush()
	error("TODO(ranch): RanchService.flush")
end

-- RanchSnapshot complet à ce joueur (arrivée, RequestWorld, trou de suite)
function RanchService.sendSnapshot(player: Player)
	local _ = { player }
	error("TODO(ranch): RanchService.sendSnapshot")
end

-- États minutés ouverts (débogage, robot de longue durée : docs/04 §17.2 invariant 6) : « playerReady » (profil chargé, PlayerReady pas encore émis), « serverFull » (renvoi en attente), « characterPlace » ;
-- noms de StateTimeouts.names(), startedAt en Clock.now()
function RanchService.openStates(): { Types.OpenState }
	error("TODO(ranch): RanchService.openStates")
end

return RanchService
