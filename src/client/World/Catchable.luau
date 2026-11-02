--!strict
-- Créatures attrapables par le joueur local (paquet client-world), mêmes règles que le serveur
-- (docs/04 §10.1 « Catch », GDD §4.11, §4.21) :
--   * Golden Wobbler : interrupteur du serveur vrai et recharge de victoire finie
--     (Balance.Golden.WinCooldown depuis golden.lastWinAt du profil) ;
--   * fuite du Rush (« escape ») : la mienne (propriétaire, capture Héros) toujours ; celle d'un autre
--     seulement en mode Rush, et pas la mienne de boopeur avant Events.Rush.BooperLock ;
--   * fuite personnelle, Wild Wobbler personnel, démonstration : personnelles (envoyées à moi seul) ;
--   * Wild Wobbler partagé : à tous.
-- Pur hors des lectures passées en paramètre : `ctx` porte mon ranch, mon mode, les interrupteurs et la
-- date de ma dernière victoire Golden. Sert à ChaseController (capture, visée du bond), ChaseRenderer
-- (contours) et PromptController (cible « creature »).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)

export type Ctx = {
	mySlot: number,
	rush: boolean, -- mon ranch est en mode Rush
	features: { [string]: any },
	goldenLastWin: number, -- Clock.unix() de ma dernière victoire Golden (0 = jamais)
	unixNow: number,
}

local Catchable = {}

local function num(x: any, default: number): number
	if type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge then
		return x
	end
	return default
end

-- Vrai si la créature `spawn` est attrapable par moi à l'instant `now` (Clock.now())
function Catchable.check(spawn: any, now: number, ctx: Ctx): boolean
	if type(spawn) ~= "table" or type(ctx) ~= "table" then
		return false
	end
	local kind = spawn.kind
	local owner = num(spawn.ownerSlot, 0)
	local mySlot = num(ctx.mySlot, 0)
	if kind == "golden" then
		if type(ctx.features) == "table" and ctx.features.golden == false then
			return false
		end
		local last = num(ctx.goldenLastWin, 0)
		return last <= 0 or num(ctx.unixNow, 0) - last >= Balance.Golden.WinCooldown
	elseif kind == "escape" then
		if mySlot > 0 and owner == mySlot then
			return true
		end
		if not ctx.rush then
			return false
		end
		local booper = num(spawn.booperSlot, 0)
		local age = num(now, 0) - num(spawn.t0, num(now, 0))
		if mySlot > 0 and booper == mySlot and age < Events.Rush.BooperLock then
			return false
		end
		return true
	elseif kind == "runaway" or kind == "wildPersonal" or kind == "demo" then
		return not (owner ~= 0 and mySlot > 0 and owner ~= mySlot)
	elseif kind == "wild" then
		return true
	end
	return false
end

-- Rayon de capture de la créature pour moi (8 pour le propriétaire de sa fuite du Rush, sinon 5)
function Catchable.radius(spawn: any, mySlot: number): number
	if
		type(spawn) == "table"
		and spawn.kind == "escape"
		and mySlot > 0
		and num(spawn.ownerSlot, 0) == mySlot
	then
		return Balance.Catch.OwnerRadius
	end
	return Balance.Catch.Radius
end

return Catchable
