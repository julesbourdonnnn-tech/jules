--!strict
-- Créatures attrapables par le joueur local (paquet client-hud) : lecture seule du miroir du monde
-- (WorldStateController) et du profil répliqué (StateController), mêmes règles que le serveur
-- (GDD §4.11, §4.21, v1.3 §10.2) :
--   * Golden Wobbler : attrapable si l'interrupteur du serveur est vrai et si ma recharge de victoire
--     (Balance.Golden.WinCooldown depuis golden.lastWinAt) est finie ;
--   * fuite du Rush (« escape ») : la mienne (propriétaire, capture Héros) toujours ; celle d'un autre
--     seulement en mode Rush, et pas la mienne de boopeur avant Events.Rush.BooperLock ;
--   * fuite personnelle, Wild Wobbler personnel, démonstration : personnelles (envoyées à moi seul) ;
--   * Wild Wobbler partagé : à tous (Rush ou Cozy).
-- Sert aux flèches de bord d'écran (HUD : 2 au plus, priorité Golden puis la plus proche par sorte),
-- à « en poursuite » (une créature attrapable à Balance.Catch.NearRadius studs au plus : puce
-- APPLAUDIR cachée, carte du choix retenue) et au calme de la carte du choix (Cards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)

local Client = script.Parent.Parent.Parent
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Util = require(Client.UI.Hud.Util)

local Chase = {}

-- Sorte de flèche de chaque sorte de créature et priorité (plus petit = plus prioritaire)
local PRIORITY: { [string]: number } = { golden = 1, booped = 2, personal = 3, wild = 4, rush = 5 }

export type Target = {
	id: number,
	pos: Vector3,
	dist: number, -- studs depuis le personnage local
	arrow: string, -- "golden" | "booped" | "personal" | "wild" | "rush"
	priority: number,
}

local function features(): { [string]: any }
	local ev = Util.safe("WorldStateController.event", nil, WorldStateController.event)
	if type(ev) == "table" and type(ev.features) == "table" then
		return ev.features
	end
	return {}
end

local function goldenReady(): boolean
	local golden = State.get("golden")
	local last = if type(golden) == "table" then Util.num(golden.lastWinAt, 0, 0) else 0
	return last <= 0 or Clock.unix() - last >= Balance.Golden.WinCooldown
end

-- Sorte de flèche d'une créature attrapable par moi, ou nil
function Chase.arrowKind(
	spawn: any,
	mySlot: number,
	rushMode: boolean,
	now: number,
	feats: { [string]: any }
): string?
	if type(spawn) ~= "table" then
		return nil
	end
	local kind = spawn.kind
	local owner = Util.num(spawn.ownerSlot, 0)
	if kind == "golden" then
		if feats.golden == false then
			return nil
		end
		return if goldenReady() then "golden" else nil
	elseif kind == "escape" then
		if mySlot > 0 and owner == mySlot then
			return "booped"
		end
		if not rushMode then
			return nil
		end
		local booper = Util.num(spawn.booperSlot, 0)
		local age = now - Util.num(spawn.t0, now)
		if mySlot > 0 and booper == mySlot and age < Events.Rush.BooperLock then
			return nil
		end
		return "rush"
	elseif kind == "runaway" or kind == "wildPersonal" or kind == "demo" then
		if owner ~= 0 and mySlot > 0 and owner ~= mySlot then
			return nil
		end
		return "personal"
	elseif kind == "wild" then
		return "wild"
	end
	return nil
end

-- Créatures attrapables par moi, de la plus prioritaire à la moins, puis de la plus proche
function Chase.targets(now: number): { Target }
	local out: { Target } = {}
	local me = Util.rootPos()
	if me == nil then
		return out
	end
	local list = Util.safe("WorldStateController.creatures", nil, WorldStateController.creatures)
	if type(list) ~= "table" then
		return out
	end
	local mySlot = Util.num(Util.safe("WorldStateController.mySlot", 0, WorldStateController.mySlot), 0)
	local rushMode = false
	if mySlot > 0 then
		local ranch = Util.safe("WorldStateController.ranch", nil, WorldStateController.ranch, mySlot)
		rushMode = type(ranch) == "table" and ranch.mode == "rush"
	end
	local feats = features()
	local count = 0
	for _, spawn in list do
		count += 1
		if count > 64 then
			break
		end
		local arrow = Chase.arrowKind(spawn, mySlot, rushMode, now, feats)
		if arrow ~= nil then
			local id = Util.num((spawn :: any).id, 0)
			local t0 = Util.num((spawn :: any).t0, now)
			local duration = Util.num((spawn :: any).duration, 0, 0, 3600)
			if now <= t0 + duration then
				local pos = Util.safe(
					"WorldStateController.creaturePos",
					nil,
					WorldStateController.creaturePos,
					id,
					now
				)
				if typeof(pos) == "Vector3" then
					table.insert(out, {
						id = id,
						pos = pos,
						dist = ((pos :: Vector3) - me).Magnitude,
						arrow = arrow,
						priority = PRIORITY[arrow] or 9,
					})
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.id < b.id
	end)
	return out
end

-- En poursuite : une créature attrapable par moi à Balance.Catch.NearRadius studs au plus
function Chase.inChase(now: number): boolean
	for _, t in Chase.targets(now) do
		if t.dist <= Balance.Catch.NearRadius then
			return true
		end
	end
	return false
end

return Chase
