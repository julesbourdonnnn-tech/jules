--!strict
-- Point d'entrée client : Init() de tous les contrôleurs dans l'ordre, puis Start().
-- Isolation des pannes (Q11) : chaque require, Init et Start passe par xpcall ; une erreur est
-- signalée par warn (nom du module, phase, pile) et le module suivant démarre quand même.
-- L'écran de chargement (src/first/Loading.client.luau) se ferme sur l'attribut LOCAL
-- « ClientReady », posé par le HUD une fois construit ; filet de sécurité indépendant du HUD :
-- l'attribut est aussi posé dès l'instantané du profil (StateController), sinon un contrôleur en
-- panne avant le HUD laissait l'écran de chargement à vie (et « Réessayer » ramenait à la même panne).

local Players = game:GetService("Players")

local Client = script.Parent

-- Ordre explicite (docs/04-architecture.md §13.1) : un module n'appelle directement que ceux
-- listés avant lui ; vers le haut, il écoute leurs signaux.
local ORDER: { ModuleScript } = {
	Client.Util.Platform, -- console, écran, entrée préférée, règle du chat (docs/07-console-ps5.md)
	Client.UI.Root,
	Client.Controllers.StateController,
	Client.Controllers.AudioController,
	Client.Util.Prefs,
	Client.Controllers.WorldFXController,
	Client.Controllers.WorldStateController,
	Client.Controllers.LightingController,
	Client.Controllers.CongaRenderer,
	Client.Controllers.VFXController,
	Client.UI.ScreenFX,
	Client.UI.Banners,
	Client.Controllers.PanelController,
	Client.Controllers.InputController,
	Client.UI.HUD,
	Client.UI.Minimap,
	Client.Controllers.OnboardingController,
}

-- Exécute fn ; une erreur est signalée (module, phase, pile) sans interrompre le démarrage
local function run(name: string, phase: string, fn: () -> ()): boolean
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn(`[Client] {name}.{phase} a échoué :`, err)
	end
	return ok
end

type Entry = { name: string, module: any }

local entries: { Entry } = {}
for _, moduleScript in ORDER do
	local name = moduleScript.Name
	run(name, "require", function()
		local module = require(moduleScript) :: any
		table.insert(entries, { name = name, module = module })
	end)
end

for _, phase in { "Init", "Start" } do
	for _, entry in entries do
		local m = entry.module
		local fn = if type(m) == "table" then m[phase] else nil
		if type(fn) == "function" then
			run(entry.name, phase, fn)
		end
	end
end

-- Filet de sécurité de l'écran de chargement : ClientReady dès l'instantané du profil, même si le
-- HUD (qui le pose normalement) est en panne. Attribut LOCAL et idempotent.
local function markReady()
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ClientReady") ~= true then
		player:SetAttribute("ClientReady", true)
	end
end

local state: any = nil
for _, entry in entries do
	if entry.name == "StateController" then
		state = entry.module
	end
end
if type(state) == "table" then
	run("Main", "ClientReady", function()
		if state.ready == true then
			markReady()
		else
			state.ReadySignal:Once(markReady)
		end
	end)
end
