--!nocheck
-- Relecture des écrans et de la manette du lot B2 (écran Améliorations et HUD v2.0) : défauts trouvés
-- en regardant les captures de l'outil d'écrans (tools/screens, tv1080, tv720, tv2160, FR et EN) et
-- en jouant l'écran à la manette ; chaque cas montré rouge avant sa correction (docs/04 §27.12,
-- lignes B2-71 et suivantes). Vrai client console, interrupteurs v2.0 ouverts DANS le test. Zéro trace.
local Screens = require("../harness/Screens")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function group(id)
		for _, g in Screens.groups() do
			if g.id == id then
				return g
			end
		end
		error("groupe d'écrans inconnu : " .. id)
	end

	describe(
		"Review_B2_screens › outil d'écrans : chaque état de l'écran Améliorations est capturé",
		function()
			-- Défaut 1 : depuis B2-66 (écran fermé quand r, Record R ou A changent), les réponses fabriquées des
			-- scénarios « upgrades.buy.card » et « upgrades.buy.card.refused » portaient l'instantané du profil
			-- témoin (r = 12) alors que l'écran s'ouvrait à r = 5 : l'écran se fermait, la capture montrait le
			-- HUD seul (retour « +1 niveau » sur une carte et refus sur une carte jamais vus, jamais mesurés
			-- dans leur vraie boîte). Chaque écran du groupe « upgrades » doit montrer l'écran ouvert.
			it(
				"chaque écran du groupe « upgrades » montre l'écran Améliorations ouvert, sans trace",
				function()
					local profile = Screens.profileById("tv1080")
					local g = group("upgrades")
					local c = Screens.boot(Harness, profile, "fr", g.state)
					local closed = {}
					for _, screen in Screens.expand(c, g) do
						local ok, err = Screens.show(c, screen)
						if not ok then
							table.insert(closed, screen.id .. " : " .. tostring(err))
						elseif not c.PC.isOpen("Upgrades") then
							table.insert(
								closed,
								screen.id .. " : écran fermé (panneau " .. tostring(c.PC.current()) .. ")"
							)
						end
					end
					expect(table.concat(closed, "\n")).toBe("")
					expect(table.concat(c.h.errors, "\n")).toBe("")
					Harness.disposeAll()
				end
			)
		end
	)

	describe("fin des écrans", function()
		Screens.finish()
	end)
end
