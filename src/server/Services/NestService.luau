--!strict
-- NestService — paquet « economy » (STUB du contrat : docs/04-architecture.md §11.4).
-- Le Nid est la maison du joueur et son identité visible : attribution, couleur, perchoirs affichés,
-- constellation, réglages et cosmétiques.
-- Responsabilités :
--   * attribution du Nid 1-12 dès PlayerAdded (joueurs déjà présents compris) : le Nid libre le
--     plus proche de celui d'un ami Roblox présent (Player:IsFriendsWith en pcall), sinon le plus
--     petit libre ; player.RespawnLocation = Spawn du Nid ; personnage déplacé sur son Nid tourné
--     vers le centre (PivotTo → Signals.ServerMoved) à chaque apparition
--   * attributs de Nest_XX (OwnerUserId, OwnerName, Supernovas, PerchCount, PerchData, Title,
--     NestTheme, Color) et du Player (Slot, Zen, Title, LineStyle, NestTheme) — voir docs §3.2 et §3.3
--   * couleur du propriétaire (Cosmetics.NestColors[slot]) ou thème, via WorldService.setNestAppearance ;
--     libération du Nid au départ (gris)
--   * perchoirs : setPerchCount (WorldService) et PerchData (meilleurs d'abord, poussés par AtlasService)
--   * constellation : attribut Supernovas mis à jour sur Signals.Supernova (rendu client)
--   * Signals.PlayerReady(player, slot) quand le profil est chargé ET le Nid attribué
--   * réglages (clé de profil « settings ») : remote SetSetting — clés de Config/Settings, type
--     attendu ; zen : dans son port sûr, recharge 60 s ; lang ∈ {auto, en, fr} ; privateNoSnip :
--     game.PrivateServerOwnerId == player.UserId (réglage de serveur en mémoire) ;
--     Signals.SettingChanged ; Analytics ZenToggled
--   * cosmétiques (clés « cosmetics », « unlocks ») : remote EquipCosmetic, unlock(), hasUnlock()
--     (stocké, pass possédé, R atteint, statistique, déblocage temporaire de la semaine)
-- GDD : §3 (0,0 s), §4.16 (Zen), §5.3, §6.1 (Nids voisins), §6.6 (constellation), §10.3, §11.3.
-- Dépendances : DataService, MonetizationService, WorldService, Logic/WorldLayout, Config/*, Signals,
-- Util/Notify, Util/RateLimit, Util/Analytics.

local NestService = {}

function NestService.Init() end

function NestService.Start() end

-- Slot 1-12 du joueur (0 si aucun Nid)
function NestService.slotOf(_player: Player): number
	error("TODO(economy): NestService.slotOf")
end

function NestService.playerAt(_slot: number): Player?
	error("TODO(economy): NestService.playerAt")
end

-- Le joueur (position serveur actuelle ou `pos`) est-il dans le port sûr de SON Nid ?
function NestService.inOwnHarbor(_player: Player, _pos: Vector3?): boolean
	error("TODO(economy): NestService.inOwnHarbor")
end

-- Ramène le personnage sur son Nid (PivotTo + Signals.ServerMoved)
function NestService.teleportHome(_player: Player)
	error("TODO(economy): NestService.teleportHome")
end

-- Perchés affichés (ordre des perchoirs) : liste de { code, stars }
function NestService.setPerchDisplay(_player: Player, _entries: { { code: number, stars: number } })
	error("TODO(economy): NestService.setPerchDisplay")
end

-- Nombre de perchoirs construits (pièces) pour ce joueur
function NestService.setPerchCount(_player: Player, _count: number)
	error("TODO(economy): NestService.setPerchCount")
end

function NestService.setting(_player: Player, _key: string): any
	error("TODO(economy): NestService.setting")
end

function NestService.isZen(_player: Player): boolean
	error("TODO(economy): NestService.isZen")
end

-- Serveur privé dont le propriétaire a activé « Coupes désactivées »
function NestService.snipsDisabled(): boolean
	error("TODO(economy): NestService.snipsDisabled")
end

-- kind : "styles" | "titles" | "themes" ; stocké dans profile.unlocks
function NestService.unlock(_player: Player, _kind: string, _id: string)
	error("TODO(economy): NestService.unlock")
end

-- Déblocage pour la session seulement (titre « Roi / Reine de la Conga »)
function NestService.grantTemporary(_player: Player, _kind: string, _id: string)
	error("TODO(economy): NestService.grantTemporary")
end

function NestService.hasUnlock(_player: Player, _kind: string, _id: string): boolean
	error("TODO(economy): NestService.hasUnlock")
end

return NestService
