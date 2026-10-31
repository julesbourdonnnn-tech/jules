--!strict
-- PathCodec — paquet « conga » (STUB du contrat : docs/04-architecture.md §10.4).
-- Codec binaire du flux de miettes PathStream (UnreliableRemoteEvent, 10 Hz), aussi utilisé par
-- PathSnapshot et WorldSnapshot.paths. Pur (buffer + Vector3), testé aller-retour sous Lune.
--
-- FORMAT (little-endian, module `buffer`) :
--   u16 tick                      compteur de ticks serveur modulo 65536 (ordre des paquets)
--   u8  runCount                  nombre de runs (≤ 255)
--   puis pour chaque run :
--     u8  slot                    index du Nid 1-12
--     u32 firstSeq                numéro de séquence du premier point du run
--     u8  n                       nombre de points (1-255)
--     i16 x×8, i16 y×8, i16 z×8   premier point absolu (arrondi au 1/8 de stud)
--     (n − 1) × [i8 dx×16, i8 dy×16, i8 dz×16]   deltas depuis le point QUANTIFIÉ précédent
-- Un même slot peut apparaître dans plusieurs runs consécutifs (seq contigus) : un delta hors de
-- [−127, 127] (déplacement > 7,9 studs sur un axe entre deux miettes) ouvre un nouveau run absolu.
-- Les positions décodées sont les positions quantifiées (pas de dérive : chaque delta est calculé
-- contre la reconstruction du point précédent, pas contre le point exact).
-- Responsabilités : encode/decode, split (découpe en runs encodables), taille estimée.
-- GDD : §12.4 (≈ 25 octets par joueur en mouvement), §12.9.
-- Dépendances : Shared/Types.

local Types = require(script.Parent.Parent.Types)

local PathCodec = {}

PathCodec.MAX_POINTS = 255
PathCodec.MAX_RUNS = 255
PathCodec.ABS_SCALE = 8
PathCodec.DELTA_SCALE = 16
PathCodec.HEADER_BYTES = 3 -- u16 tick + u8 runCount
PathCodec.RUN_HEADER_BYTES = 12 -- u8 slot + u32 firstSeq + u8 n + 3 × i16
PathCodec.DELTA_BYTES = 3

-- Encode des runs (déjà découpés par split) dans un buffer
function PathCodec.encode(_tick: number, _runs: { Types.PathEntry }): buffer
	error("TODO(conga): PathCodec.encode")
end

-- Décode un buffer → (tick, runs). Un buffer tronqué ou incohérent lève une erreur
-- (l'appelant protège par pcall : les données client/serveur ne sont jamais crues aveuglément).
function PathCodec.decode(_buf: buffer): (number, { Types.PathEntry })
	error("TODO(conga): PathCodec.decode")
end

-- Découpe une suite de points (numérotés à partir de firstSeq) en runs encodables
-- (≤ MAX_POINTS points, deltas dans [−127, 127] après quantification)
function PathCodec.split(_slot: number, _firstSeq: number, _points: { Vector3 }): { Types.PathEntry }
	error("TODO(conga): PathCodec.split")
end

-- Taille en octets du buffer qu'encode() produirait
function PathCodec.size(_runs: { Types.PathEntry }): number
	error("TODO(conga): PathCodec.size")
end

return PathCodec
