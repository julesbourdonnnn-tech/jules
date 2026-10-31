--!strict
-- SpawnService — paquet « conga » (STUB du contrat : docs/04-architecture.md §11.7).
-- Propriétaire des Nebbies sauvages, libres et personnels (mémoire uniquement, rien de sauvegardé).
-- Responsabilités :
--   * apparitions par zone (Config/Zones) : à chaque intervalle (÷ SpawnModifiers.intervalDiv), si
--     la zone est sous son plafond effectif (Formulas.effectiveCap × capMult), rareté tirée selon les
--     probabilités, espèce uniforme parmi Nebbies.speciesOfRarity ; forme météo (40 %), Golden 1 %,
--     Huge 0,5 %, espèce vedette et Starborn pendant Starfall (SpawnModifiers) ; point de la grille
--     WorldLayout.spawnPoints à ≥ 6 studs de tout sauvage (10 essais, sinon on saute ce tour)
--   * flânerie SeededPath.wander(seed, now − t0) : position serveur = ancre + décalage (même calcul
--     côté client) ; expiration à t0 + durée de vie
--   * grille spatiale de Balance.Tick.GridCell (16 studs) pour query()
--   * Nebbies libres (coupe, mort, départ, explosion de Comète) : étourdis Balance.Snip.Dizzy pour
--     tous sauf le slot prioritaire, durée Snip.LooseLifetime ; groupes plafonnés par joueur
--     (explosion : 1 Épique par joueur)
--   * apparitions personnelles (onlyFor) : Puffkins de bienvenue (3, à 12 studs devant la porte,
--     dans le port sûr), Rare garanti de Q4 (60-90 studs du centre, une fois par compte),
--     apparitions dirigées de l'accueil (≥ 6 Communs à < 40 studs du Nid) ; hors plafonds ;
--     envoyées au seul client concerné ; nettoyées au départ du joueur
--   * WildEvent groupé à 4 Hz (flush) : spawns publics à tous, personnels au seul joueur ;
--     despawns "expired" / "cleared" (les capturés ne sont PAS listés : LineEvent "add" porte l'id)
-- GDD : §3 (Puffkins, Q4), §4.3, §4.4, §4.5 (étourdissement, priorité), §4.15.2 (explosion),
-- §4.15.5, §12.4 (WildEvent).
-- Dépendances : NestService (portes), Logic/WorldLayout, Logic/SeededPath, Logic/Formulas,
-- Logic/Hash, Config/*, Shared/Util/Clock.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local SpawnService = {}

export type LooseOptions = {
	prioritySlot: number?, -- slot de la victime (0 s d'étourdissement pour elle)
	dizzy: number?, -- défaut Balance.Snip.Dizzy
	life: number?, -- défaut Balance.Snip.LooseLifetime
	group: string?, -- plafond par joueur (ex. "burst:<id>")
	groupCap: number?,
	silent: boolean?, -- true : pas d'envoi par WildEvent (l'appelant les envoie lui-même dans
	-- LineEvent "clear" ou SnipEvent, champ loose)
}

function SpawnService.Init() end

function SpawnService.Start() end

-- Apparitions dues et expirations (tick de CongaService, étape 4)
function SpawnService.step(_now: number)
	error("TODO(conga): SpawnService.step")
end

-- Poussé par EventService à chaque changement de phase (météo, Frenzy, Starfall)
function SpawnService.setModifiers(_mods: Types.SpawnModifiers)
	error("TODO(conga): SpawnService.setModifiers")
end

-- Poussé par CongaService (joueurs actifs, §4.3) au plus une fois par seconde
function SpawnService.setActivePlayers(_n: number)
	error("TODO(conga): SpawnService.setActivePlayers")
end

-- Sauvages dont la position à `now` est à ≤ radius (XZ) de pos et visibles pour `player`
function SpawnService.query(_pos: Vector3, _radius: number, _now: number, _player: Player?): { Types.WildNebby }
	error("TODO(conga): SpawnService.query")
end

-- Position serveur d'un sauvage à `now` (ancre + flânerie ; arc de dispersion terminé)
function SpawnService.positionOf(_wild: Types.WildNebby, _now: number): Vector3
	error("TODO(conga): SpawnService.positionOf")
end

-- Le joueur peut-il l'attraper maintenant ? (étourdi, priorité, onlyFor, plafond de groupe)
function SpawnService.canCatch(_player: Player, _slot: number, _wild: Types.WildNebby, _now: number): boolean
	error("TODO(conga): SpawnService.canCatch")
end

-- Retire le sauvage (capturé) ; retourne son enregistrement, nil s'il n'existe plus
function SpawnService.consume(_id: number, _player: Player): Types.WildNebby?
	error("TODO(conga): SpawnService.consume")
end

-- Crée des Nebbies libres (un par code, départ `from[i]`, atterrissage dispersé et borné à l'île) ;
-- retourne les apparitions (ids dans l'ordre)
function SpawnService.spawnLoose(
	_codes: { Types.NebbyCode },
	_from: { Vector3 },
	_now: number,
	_opts: LooseOptions?
): { Types.WildSpawn }
	error("TODO(conga): SpawnService.spawnLoose")
end

-- Apparition personnelle (onlyFor = player) ; retourne l'id
function SpawnService.spawnPersonal(_player: Player, _code: Types.NebbyCode, _pos: Vector3, _life: number?): number
	error("TODO(conga): SpawnService.spawnPersonal")
end

-- 3 Puffkins de bienvenue devant la porte du Nid (accueil, §3)
function SpawnService.spawnWelcome(_player: Player): { number }
	error("TODO(conga): SpawnService.spawnWelcome")
end

-- Rare personnel de Q4 (60-90 studs du centre) ; nil s'il existe déjà un Rare public dans la Clairière
function SpawnService.spawnGuaranteedRare(_player: Player): number?
	error("TODO(conga): SpawnService.spawnGuaranteedRare")
end

-- Accueil : garantir ≥ 6 Communs à < 40 studs du Nid du joueur (true = actif)
function SpawnService.setDirected(_player: Player, _enabled: boolean)
	error("TODO(conga): SpawnService.setDirected")
end

-- Envoie le WildEvent groupé si ≥ 0,25 s depuis le dernier (ou `urgent`)
function SpawnService.flush(_now: number, _urgent: boolean?)
	error("TODO(conga): SpawnService.flush")
end

-- Apparitions visibles par ce joueur (WorldSnapshot)
function SpawnService.snapshotFor(_player: Player): { Types.WildSpawn }
	error("TODO(conga): SpawnService.snapshotFor")
end

-- Retire les apparitions personnelles et les plafonds de groupe du joueur (départ)
function SpawnService.clearPlayer(_player: Player)
	error("TODO(conga): SpawnService.clearPlayer")
end

function SpawnService.aliveCount(_zoneKey: string?): number
	error("TODO(conga): SpawnService.aliveCount")
end

-- Convertit un enregistrement serveur en charge utile réseau
function SpawnService.toSpawn(_wild: Types.WildNebby): Types.WildSpawn
	error("TODO(conga): SpawnService.toSpawn")
end

return SpawnService
