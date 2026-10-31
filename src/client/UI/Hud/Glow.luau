--!strict
-- Hud/Glow — prédiction du Glow côté client (docs/04-architecture.md §13.12, GDD §4.9, §12.1).
-- Le serveur règle le revenu passif paresseusement (EconomyService.settle) ; entre deux règlements
-- le client affiche glow + idleRate × (Clock.now() − lastSettle) + glowCarry, arrondi vers le bas
-- (même arrondi que Formulas.settle) et jamais en dessous de la valeur serveur.
-- Utilisable par les panneaux (prix « achetables » calculés sur le Glow PRÉDIT) :
--   local Glow = require(Client.UI.Hud.Glow); Glow.predicted()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)

local Glow = {}

-- Au-delà, l'instantané est jugé périmé (le serveur règle toutes les SettleInterval secondes) :
-- la prédiction cesse d'avancer plutôt que d'afficher un montant que le serveur n'a pas accordé
Glow.MAX_SECONDS = Balance.Idle.SettleInterval * 4

local function finite(x: any, default: number): number
	if type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge then
		return x
	end
	return default
end

-- Valeur prédite (pure) : entier ≥ glow serveur
function Glow.predict(glow: number, carry: number, rate: number, lastSettle: number, now: number): number
	local base = math.max(0, math.floor(finite(glow, 0)))
	local r = math.max(0, finite(rate, 0))
	local settled = finite(lastSettle, 0)
	local t = finite(now, settled)
	if r == 0 or settled <= 0 then
		return base
	end
	local dt = math.clamp(t - settled, 0, Glow.MAX_SECONDS)
	local c = math.clamp(finite(carry, 0), 0, 1)
	return math.max(base, math.floor(base + c + r * dt))
end

-- Valeur prédite depuis le miroir du profil (StateController) à l'instant `now` (Clock par défaut)
function Glow.predicted(now: number?): number
	return Glow.predict(
		finite(State.get("glow"), 0),
		finite(State.get("glowCarry"), 0),
		finite(State.get("idleRate"), 0),
		finite(State.get("lastSettle"), 0),
		now or Clock.now()
	)
end

-- Revenu passif affiché (Glow/s, multiplicateurs compris : clé répliquée idleRate)
function Glow.rate(): number
	return math.max(0, finite(State.get("idleRate"), 0))
end

return Glow
