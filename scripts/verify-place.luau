--!nocheck
-- Ouvre la place construite par Rojo et vérifie sa structure :
-- chaque script a une source, les points d'entrée existent, aucun script vide.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/Game.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local problems = {}
local counts = { Script = 0, LocalScript = 0, ModuleScript = 0 }
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
		local source = inst.Source
		if source == nil or #source < 10 then
			table.insert(problems, "script vide : " .. inst:GetFullName())
		end
		if inst.ClassName == "Script" and inst.RunContext ~= nil and inst.RunContext == roblox.Enum.RunContext.Client then
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

print(string.format("Place %s : %d Script, %d LocalScript, %d ModuleScript", path, counts.Script, counts.LocalScript, counts.ModuleScript))
if #problems > 0 then
	for _, p in problems do
		print("  ✗ " .. p)
	end
	process.exit(1)
end
print("  ✓ structure valide")
