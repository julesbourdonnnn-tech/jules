--!nocheck
-- TEMPORAIRE (étape 6 du lot B3) : ne lance qu'un describe d'une autre spec ; jamais validé
local spec = require("./Layout_panels.spec")
return function(T)
	local T2 = table.clone(T)
	T2.describe = function(name, fn)
		if string.find(name, "méta", 1, true) then
			T.describe(name, fn)
		end
	end
	spec(T2)
end
