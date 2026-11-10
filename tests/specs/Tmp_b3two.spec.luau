--!nocheck
-- TEMPORAIRE (étape 6 du lot B3) : ne lance qu'un describe d'une autre spec ; jamais validé
local spec = require("./Console_panels.spec")
return function(T)
	local T2 = table.clone(T)
	T2.describe = function(name, fn)
		if string.find(name, "promenade", 1, true) or string.find(name, "onglet vide", 1, true) then
			T.describe(name, fn)
		end
	end
	spec(T2)
end
