--!strict
-- PassEffects — aide du paquet « economy » : effets des game passes lus DYNAMIQUEMENT
-- (jamais stockés). Un pass est reconnu par son EFFET dans Config/Monetization (glowBonus,
-- glowMult, offlineRate, extraPerches, stashSize) et non par son nom : ajouter ou renommer un
-- pass ne demande aucun code. La possession vient de MonetizationService.ownsPass (profil).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local MonetizationService = require(script.Parent.Parent.Services.MonetizationService)

local PassEffects = {}

-- Clés de passes ayant un champ d'effet donné (calculé une fois)
local byEffect: { [string]: { string } } = {}
for key, def in Monetization.Passes do
	for field in def :: any do
		local list = byEffect[field]
		if not list then
			list = {}
			byEffect[field] = list
		end
		table.insert(list, key)
	end
end

local function ownsEffect(player: Player, field: string): boolean
	local keys = byEffect[field]
	if not keys then
		return false
	end
	for _, key in keys do
		if MonetizationService.ownsPass(player, key) then
			return true
		end
	end
	return false
end

-- +25 % additif dans M, badge « ★ VIP » (VIP Star)
function PassEffects.vip(player: Player): boolean
	return ownsEffect(player, "glowBonus")
end

-- ×2 sur le revenu passif et les parades (Double Glow)
function PassEffects.doubleGlow(player: Player): boolean
	return ownsEffect(player, "glowMult")
end

-- Hors ligne 75 % pendant 12 h (Night Shift)
function PassEffects.nightShift(player: Player): boolean
	return ownsEffect(player, "offlineRate")
end

-- +6 perchoirs (Extra Perches)
function PassEffects.extraPerches(player: Player): boolean
	return ownsEffect(player, "extraPerches")
end

-- Réserve 600 places (Stash Plus)
function PassEffects.stashPlus(player: Player): boolean
	return ownsEffect(player, "stashSize")
end

-- Le pass `passKey` agit-il sur le champ `field` ? (ProductService : quels effets recalculer)
function PassEffects.passHas(passKey: string, field: string): boolean
	local keys = byEffect[field]
	return keys ~= nil and table.find(keys, passKey) ~= nil
end

return PassEffects
