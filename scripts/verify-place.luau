--!nocheck
-- Ouvre la place construite par Rojo et vérifie sa structure :
-- chaque script a une source, les points d'entrée existent, aucun script vide.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- Cible d'éclairage de la place (N12, INT-V2-LIGHT ; lot B4, décision D2) : « v1.3 » vérifie
-- Technology = ShadowMap (place d'aujourd'hui) ; « v2.0 » vérifie l'éclairage unifié réglé explicitement
-- (LightingStyle = Soft, PrioritizeLightingQuality = false) et ne regarde plus Technology. La place
-- reste en v1.3 tant que l'interrupteur Ambience est coupé : l'étape d'intégration I passe cette valeur
-- à « v2.0 » dans le même commit que default.project.json et Ambience = true. En ligne de commande :
--   lune run scripts/verify-place build/Game.rbxl --lighting v2.0
local LIGHTING = "v1.3"

local problems = {}

local path = nil
local i = 1
while i <= #process.args do
	local arg = process.args[i]
	if arg == "--lighting" then
		local value = process.args[i + 1]
		if value == "v1.3" or value == "v2.0" then
			LIGHTING = value
		else
			table.insert(problems, `--lighting {tostring(value)} inconnu (attendu v1.3 ou v2.0)`)
		end
		i += 2
	else
		path = path or arg
		i += 1
	end
end
path = path or "build/Game.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))
local counts = { Script = 0, LocalScript = 0, ModuleScript = 0 }
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
		local source = inst.Source
		if source == nil or #source < 10 then
			table.insert(problems, "script vide : " .. inst:GetFullName())
		end
		if
			inst.ClassName == "Script"
			and inst.RunContext ~= nil
			and inst.RunContext == roblox.Enum.RunContext.Client
		then
			table.insert(problems, "Script en RunContext Client : " .. inst:GetFullName())
		end
	end
end

local function expect(fullPath: string, class: string)
	local cur = game
	for part in string.gmatch(fullPath, "[^%.]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	if not cur or cur.ClassName ~= class then
		table.insert(problems, `manquant : {fullPath} ({class})`)
	end
end
expect("ServerScriptService.Server.Main", "Script")
expect("StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript")
expect("ReplicatedStorage.Shared.Net", "ModuleScript")
expect("ReplicatedStorage.Shared.Remotes", "ModuleScript")
expect("ReplicatedFirst.Loading", "LocalScript")
-- seuils de l'anti-triche : serveur seulement (jamais répliqués)
expect("ServerScriptService.Server.Movement.Tuning", "ModuleScript")
if game:FindFirstChild("ReplicatedStorage") and game.ReplicatedStorage:FindFirstChild("Tuning", true) then
	table.insert(
		problems,
		"Tuning répliqué dans ReplicatedStorage (seuils anti-triche lisibles par le client)"
	)
end

-- Taille du serveur : 16 joueurs (concept du jeu, budgets réseau et DataStore calculés pour 16)
local players = game:FindFirstChildOfClass("Players")
if players == nil or players.MaxPlayers ~= 16 then
	table.insert(problems, `Players.MaxPlayers = {players and players.MaxPlayers} (attendu 16)`)
end

-- Chat : TextChatService explicite (règle console reprise de Comet Conga ; la base de réflexion par
-- défaut donnerait LegacyChatService, l'ancien chat que Platform ne sait pas couper sur console)
local tcs = game:FindFirstChildOfClass("TextChatService")
if tcs == nil then
	table.insert(problems, "manquant : TextChatService")
elseif tcs.ChatVersion ~= roblox.Enum.ChatVersion.TextChatService then
	table.insert(problems, `TextChatService.ChatVersion = {tcs.ChatVersion} (attendu TextChatService)`)
end

-- Note INT-PREPUBLISH (docs/04 §17.3, remarque A28) : la place CONSTRUITE garde les réglages de
-- robustesse (aucun streaming : les clients ne supposent jamais une pièce absente ; pas de curseur
-- virtuel sur console ; éclairage ShadowMap, budget PS4 / Xbox One)
local function setting(serviceName: string, prop: string, expected: any, label: string)
	local service = game:FindFirstChildOfClass(serviceName)
	if service == nil then
		table.insert(problems, `manquant : {serviceName}`)
		return
	end
	local ok, value = pcall(function()
		return service[prop]
	end)
	if not ok or value ~= expected then
		table.insert(problems, `{serviceName}.{prop} = {tostring(value)} (attendu {label})`)
	end
end
setting("Workspace", "StreamingEnabled", false, "false")
setting("StarterGui", "VirtualCursorMode", roblox.Enum.VirtualCursorMode.Disabled, "Disabled")
if LIGHTING == "v2.0" then
	setting("Lighting", "LightingStyle", roblox.Enum.LightingStyle.Soft, "Soft")
	setting("Lighting", "PrioritizeLightingQuality", false, "false")
else
	setting("Lighting", "Technology", roblox.Enum.Technology.ShadowMap, "ShadowMap")
end

print(
	string.format(
		"Place %s : %d Script, %d LocalScript, %d ModuleScript (éclairage %s)",
		path,
		counts.Script,
		counts.LocalScript,
		counts.ModuleScript,
		LIGHTING
	)
)
if #problems > 0 then
	for _, p in problems do
		print("  ✗ " .. p)
	end
	process.exit(1)
end
print("  ✓ structure valide")
