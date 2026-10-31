--!strict
-- Point d'entrée client : Init() de tous les contrôleurs dans l'ordre, puis Start().

local Client = script.Parent

-- Ordre explicite (docs/04-architecture.md §13.1) : un module n'appelle directement que ceux
-- listés avant lui ; vers le haut, il écoute leurs signaux.
local ORDER: { ModuleScript } = {
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

local modules = {}
for i, moduleScript in ORDER do
	modules[i] = require(moduleScript) :: any
end
for _, m in modules do
	if m.Init then
		m.Init()
	end
end
for _, m in modules do
	if m.Start then
		m.Start()
	end
end
