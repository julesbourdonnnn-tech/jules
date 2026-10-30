--!strict
-- Accès centralisé aux remotes. Tous les noms sont déclarés dans Shared/Remotes.luau :
-- une faute de frappe dans un nom provoque une erreur claire dès le démarrage.
--
-- Serveur : Net.setup() (une fois, en premier) crée ReplicatedStorage.Remotes et tous les remotes.
-- Partout : Net.event("Nom"), Net.unreliable("Nom"), Net.func("Nom").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)

local FOLDER_NAME = "Remotes"
local CLIENT_TIMEOUT = 30

local Net = {}

local CLASS_FOR_KIND = {
	event = "RemoteEvent",
	unreliable = "UnreliableRemoteEvent",
	func = "RemoteFunction",
}

function Net.setup()
	assert(RunService:IsServer(), "Net.setup() est réservé au serveur")
	if ReplicatedStorage:FindFirstChild(FOLDER_NAME) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, kind in Remotes do
		local className = CLASS_FOR_KIND[kind]
		assert(className, `Remotes.{name} : type inconnu « {kind} »`)
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function get(name: string, kind: string): Instance
	local declared = Remotes[name]
	if declared == nil then
		error(`[Net] remote non déclaré : « {name} » (ajoutez-le dans Shared/Remotes.luau)`, 3)
	end
	if declared ~= kind then
		error(`[Net] « {name} » est déclaré comme {declared}, pas comme {kind}`, 3)
	end
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		assert(folder, "[Net] Net.setup() doit être appelé avant d'utiliser les remotes")
		local remote = folder:FindFirstChild(name)
		assert(remote, `[Net] remote manquant : {name}`)
		return remote
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT)
	assert(folder, "[Net] dossier Remotes introuvable (serveur non démarré ?)")
	local remote = folder:WaitForChild(name, CLIENT_TIMEOUT)
	assert(remote, `[Net] remote introuvable côté client : {name}`)
	return remote
end

function Net.event(name: string): RemoteEvent
	return get(name, "event") :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name, "unreliable") :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return get(name, "func") :: RemoteFunction
end

return Net
