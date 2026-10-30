--!strict
-- Point d'entrée client : Init() de tous les contrôleurs dans l'ordre, puis Start().

local Client = script.Parent

-- Ordre explicite : un contrôleur ne dépend que de ceux listés avant lui.
local ORDER: { ModuleScript } = {
	Client.UI.Root,
	Client.Controllers.StateController,
	Client.Controllers.AudioController,
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
