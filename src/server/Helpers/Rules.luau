--!strict
-- Règles des Plopettes (lot A3, GDD v2.0 §4.28, docs/04 §27.7, §27.14) : fonctions PURES lues par
-- HelperService (aucun état, aucun service). Valeurs de jeu dans Balance.Helpers (réglées par A1 seul) ;
-- les constantes de ce module ne règlent que le trajet et la diffusion (rien de l'économie) :
--   * count(bestR, plume)        : Plopettes du Record R (Balance.Helpers.ByRecordR) + Plume de l'Atelier ;
--   * index(k, count, plume)     : numéro de la k-ième Plopette (1 = Pip … 5 = Puff, 6 = Plume : ordre des
--                                  lignes en lecture seule de Config/Upgrades) ;
--   * interval(school)           : IntervalBase − IntervalStep × niveau de l'École (12 s → 6 s) ;
--   * travel(ax, az, bx, bz)     : durée du saut (fonction pure des deux positions, MaxTravel au plus) ;
--   * farEnough(px, pz, cx, cz)  : règle des 12 studs (STRICTEMENT plus de MinDistance à plat de la
--                                  position validée du joueur : sa portée de pression est 10 + 2 studs) ;
--   * readyFor(readyAt, now)     : prête depuis au moins ReadyFor s (readyAt = fin de la recharge) ;
--   * houseLocal()               : maisonnette des Plopettes dans le repère du ranch (Z = 60, X = −28,
--                                  docs/04 §27.14) tant que WorldLayout.helperHouse (B4) n'existe pas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Rules = {}

local H = Balance.Helpers

-- Numéro de la Plume (6e ligne en lecture seule « helper.plume » de Config/Upgrades)
Rules.PLUME = #H.ByRecordR + 1
-- Plopettes au plus (5 du Record R + Plume)
Rules.MAX = Rules.PLUME
-- Vitesse du saut (studs par seconde) et durée minimale d'un saut : visuel seulement (le client règle
-- le saut pour atterrir à tPress), jamais une valeur d'économie
Rules.HOP_SPEED = 12
Rules.MIN_TRAVEL = 0.5
-- Nouvel essai d'une Plopette sans cible (s) : borne le coût du tick quand rien n'est prêt
Rules.RETRY = 1
-- Réveil ou fin de pause : les Plopettes sortent ensemble WAKE_DELAY s après (même tick : leurs sauts
-- partent dans UN message HelperPress) ; WAKE_STAGGER s de plus par Plopette (0 : toutes ensemble)
Rules.WAKE_DELAY = 0.5
Rules.WAKE_STAGGER = 0
-- Diffusion de HelperPress : le propriétaire et les joueurs à moins de DETAIL_RADIUS studs à plat du
-- centre du ranch (le client dessine en détail complet jusqu'à 60 studs × qualité : ChaseRenderer)
Rules.DETAIL_RADIUS = 110
Rules.RANCH_CENTER_Z = 36
-- Nombre de Plopettes, profil relu au plus une fois par REFRESH secondes
Rules.REFRESH = 1
-- Passes de choix de cibles par tick (une par ranch) : au-delà, le ranch attend le tick suivant (0,1 s)
-- (16 ranchs réveillés au même tick ne font jamais un tick long)
Rules.CHOOSE_PER_TICK = 4

local HOUSE_X, HOUSE_Z = -28, 60

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function int(x: any, lo: number, hi: number): number
	if not finite(x) then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

-- Plopettes du Record R (Pip, Pop, Pim, Pom, Puff)
function Rules.byRecord(bestR: number): number
	local best = if finite(bestR) then bestR else 0
	local n = 0
	for _, at in H.ByRecordR do
		if best >= at then
			n += 1
		end
	end
	return n
end

-- Plopettes possédées : celles du Record R + la Plume (niveau 1 de la ligne de l'Atelier)
function Rules.count(bestR: number, plume: number): number
	return Rules.byRecord(bestR) + (if int(plume, 0, 1) >= 1 then 1 else 0)
end

-- Numéro (1 … 6) de la k-ième Plopette possédée : Pip … Puff dans l'ordre, puis la Plume
function Rules.index(k: number, byRecord: number): number
	if k <= byRecord then
		return k
	end
	return Rules.PLUME
end

-- Intervalle entre deux pressions d'une Plopette (s) : 12 − 0,3 × École, jamais sous 1 s
function Rules.interval(school: number): number
	return math.max(1, H.IntervalBase - H.IntervalStep * int(school, 0, 1e3))
end

-- Durée du saut d'une Plopette de (ax, az) à (bx, bz), à plat : MIN_TRAVEL … MaxTravel
function Rules.travel(ax: number, az: number, bx: number, bz: number): number
	if not (finite(ax) and finite(az) and finite(bx) and finite(bz)) then
		return H.MaxTravel
	end
	local dx, dz = bx - ax, bz - az
	local t = math.sqrt(dx * dx + dz * dz) / Rules.HOP_SPEED
	return math.clamp(t, Rules.MIN_TRAVEL, H.MaxTravel)
end

-- Règle des 12 studs : la place du squishy est à PLUS de MinDistance studs à plat du joueur
function Rules.farEnough(px: number, pz: number, cx: number, cz: number): boolean
	if not (finite(px) and finite(pz) and finite(cx) and finite(cz)) then
		return false
	end
	local dx, dz = cx - px, cz - pz
	local d2 = dx * dx + dz * dz
	return d2 > H.MinDistance * H.MinDistance
end

-- Prête depuis au moins ReadyFor s : la recharge (readyAt) a fini à now − ReadyFor ou avant
function Rules.readyFor(readyAt: number, now: number): boolean
	if not finite(now) then
		return false
	end
	local at = if finite(readyAt) then readyAt else 0
	return at <= now - H.ReadyFor
end

-- Sieste : aucune intention acceptée depuis plus de NapAfter s (lastIntent = -math.huge : jamais)
function Rules.napping(lastIntent: number, now: number): boolean
	if not finite(now) then
		return true
	end
	if type(lastIntent) ~= "number" or lastIntent ~= lastIntent then
		return true
	end
	return now - lastIntent > H.NapAfter
end

-- Maisonnette des Plopettes, repère local du ranch
function Rules.houseLocal(): (number, number)
	return HOUSE_X, HOUSE_Z
end

return Rules
