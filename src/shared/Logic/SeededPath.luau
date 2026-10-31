--!strict
-- SeededPath — paquet « logic » (STUB du contrat : docs/04-architecture.md §12.1).
-- Trajectoires déterministes : serveur et clients calculent la MÊME position à partir d'une graine
-- et de Clock.now() ; rien de physique n'est répliqué.
-- Responsabilités :
--   * wander(seed, dt) : décalage XZ (Y = 0) d'un Nebby sauvage autour de son ancre, courbe de
--     Lissajous d'amplitude Balance.Spawn.WanderAmplitude (1,6), fréquences tirées dans
--     [WanderFreqMin ; WanderFreqMax] rad/s, phases tirées (Hash) ; |x|, |z| ≤ 1,6
--   * chordAt(seed, t0, t) : Gloomwisp sur des cordes entre points du cercle r = Wisps.PathRadius
--     (165) à Wisps.Speed (7 studs/s), pause Wisps.Pause (4 s) à l'arrivée, corde suivante partant
--     du point d'arrivée (angle k tiré par Hash(seed, k)) ; retourne (position, direction unitaire)
--   * newChordCursor : même calcul, incrémental (t croissant) en O(1) amorti
--   * cometSky : courbe de Bézier de la Comète dans le ciel (alpha 0 → 1 en Comet.SkySeconds),
--     départ haut dans le ciel tiré de Hash(id, Events.Salts.CometSky), arrivée = impact
--   * scatterPoint : point de dispersion à ScatterMin-ScatterMax studs (NON borné à l'île :
--     l'appelant applique WorldLayout.clampToIsland)
-- GDD : §4.3 (flânerie), §4.15.4 (cordes), §9.4 (arc de la Comète), §4.7 (dispersion),
-- §12.9 (SeededPath.spec : déterminisme, amplitude ≤ 1,6, cordes dans l'île).
-- Dépendances : Config/Balance, Config/Events, Logic/Hash.

local SeededPath = {}

export type ChordCursor = {
	-- position et direction à t (t non décroissant d'un appel à l'autre)
	at: (self: ChordCursor, t: number) -> (Vector3, Vector3),
	-- `count` points espacés le long du trajet sur les `studs` prochains studs (Beam d'aperçu)
	ahead: (self: ChordCursor, t: number, studs: number, count: number) -> { Vector3 },
}

function SeededPath.wander(_seed: number, _dt: number): Vector3
	error("TODO(logic): SeededPath.wander")
end

function SeededPath.chordAt(_seed: number, _t0: number, _t: number): (Vector3, Vector3)
	error("TODO(logic): SeededPath.chordAt")
end

function SeededPath.newChordCursor(_seed: number, _t0: number): ChordCursor
	error("TODO(logic): SeededPath.newChordCursor")
end

function SeededPath.cometSky(_id: number, _impact: Vector3, _alpha: number): Vector3
	error("TODO(logic): SeededPath.cometSky")
end

-- Point de dispersion du `index`-ième Nebby détaché (graine = id de coupe)
function SeededPath.scatterPoint(_seed: number, _index: number, _origin: Vector3): Vector3
	error("TODO(logic): SeededPath.scatterPoint")
end

return SeededPath
