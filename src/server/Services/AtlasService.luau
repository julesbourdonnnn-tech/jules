--!strict
-- AtlasService — paquet « economy » (STUB du contrat : docs/04-architecture.md §11.6).
-- Propriétaire de la collection : nebbies, nextUid, perchIncome, atlas, badges, atlasRewards.
-- Responsabilités :
--   * addNebbies : uids "u<n>", tri automatique (revenu passif décroissant → N premiers perchés),
--     réserve 300/600 ; débordement : libération auto des non verrouillés les moins rentables
--     (Commun → Rare seulement) contre Stardust + Feedback récapitulatif, sinon libération des
--     nouveaux arrivants excédentaires (leur Glow est déjà payé)
--   * entrées d'Atlas (bit (s − 1) × 6 + f) et badges Golden/Huge/Starborn validés à l'encaissement ;
--     Celebrate "atlasNew" ; jalons toutes les 12 entrées réclamés automatiquement (perchoirs,
--     titre + style à 132, thème à 144 via NestService.unlock) ; espèce complète : +100 Stardust ;
--     Signals.AtlasEntry
--   * perchoirs : nombre = Formulas.perchCount(niveau, entrées, pass Extra Perches) ;
--     recalcul sur Signals.UpgradeBought (perches), PassGranted, jalons ; Signals.PerchesChanged ;
--     NestService.setPerchCount / setPerchDisplay ; RÈGLE : EconomyService.settle AVANT de changer
--     perchIncome, puis EconomyService.refreshRate
--   * remotes Fuse(uid) 6/s, FuseAll() 1/2 s, Release(uids) 2/s, SetLock(uid, locked) 6/s
--     (validation §10.2) ; Starforge déterministe : 3 identiques (s, f, v, st) non verrouillés
--     sauf celui choisi → ★+1, coûts Balance.Starforge ; « Tout fusionner » en commençant par les
--     fusions qui augmentent le plus le revenu perché ; Signals.Fused ; Celebrate "starforge"
--   * libération : Stardust = Formulas.releaseDust ; jamais un Cosmique ni un verrouillé
-- GDD : §4.9, §4.13, §4.14, §5.4, §14.2 (Release_<rareté>, Starforge_<★>).
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, Logic/Formulas,
-- Config/Nebbies, Config/Quests (jalons), Config/Balance, Signals, Util/Notify, Util/RateLimit,
-- Util/Analytics.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local AtlasService = {}

function AtlasService.Init() end

function AtlasService.Start() end

-- Ajoute des Nebbies (★1 sauf `stars`) ; retourne les uids créés (vide si profil absent).
-- source : "parade" | "comet" | "quest" | "calendar" | "product" | "starfall" | "code"
function AtlasService.addNebbies(
	_player: Player,
	_codes: { Types.NebbyCode },
	_source: string,
	_stars: number?
): { Types.Uid }
	error("TODO(economy): AtlasService.addNebbies")
end

function AtlasService.record(_player: Player, _uid: Types.Uid): Types.NebbyRecord?
	error("TODO(economy): AtlasService.record")
end

-- uids perchés, du plus rentable au moins rentable
function AtlasService.perched(_player: Player): { Types.Uid }
	error("TODO(economy): AtlasService.perched")
end

function AtlasService.perchCount(_player: Player): number
	error("TODO(economy): AtlasService.perchCount")
end

function AtlasService.stashCap(_player: Player): number
	error("TODO(economy): AtlasService.stashCap")
end

function AtlasService.atlasCount(_player: Player): number
	error("TODO(economy): AtlasService.atlasCount")
end

function AtlasService.hasEntry(_player: Player, _s: number, _f: number): boolean
	error("TODO(economy): AtlasService.hasEntry")
end

-- Re-trie les perchoirs (après un changement du nombre de perchoirs ou de la collection)
function AtlasService.refreshPerches(_player: Player)
	error("TODO(economy): AtlasService.refreshPerches")
end

-- (ok, raison) — raison : clé "feedback.*"
function AtlasService.fuse(_player: Player, _uid: Types.Uid): (boolean, string?)
	error("TODO(economy): AtlasService.fuse")
end

-- Nombre de fusions effectuées
function AtlasService.fuseAll(_player: Player): number
	error("TODO(economy): AtlasService.fuseAll")
end

-- Stardust gagnée (0 si rien de libérable)
function AtlasService.release(_player: Player, _uids: { Types.Uid }): number
	error("TODO(economy): AtlasService.release")
end

function AtlasService.setLock(_player: Player, _uid: Types.Uid, _locked: boolean): boolean
	error("TODO(economy): AtlasService.setLock")
end

return AtlasService
