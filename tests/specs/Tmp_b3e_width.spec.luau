--!nocheck
-- SONDE JETABLE (jamais validée) : largeurs mesurées de libellés candidats
local roblox = require("@lune/roblox")
local TextFit = require("../harness/TextFit")
return function(T)
	T.describe("largeurs", function()
		T.it("mesure", function()
			local font = roblox.Font.new("rbxasset://fonts/families/FredokaOne.json")
			for _, s in { "Couleurs du Splorch", "Couleurs", "Palettes", "Couleurs Splorch", "Splorch colors", "Thème du ranch", "Ranch theme", "Dragon de gelée", "Selle « Biscuit »" } do
				for _, size in { 36, 32, 28 } do
					print(string.format("%-24s %d px : %.1f", s, size, TextFit.width(s, font, size)))
				end
			end
		end)
	end)
end
