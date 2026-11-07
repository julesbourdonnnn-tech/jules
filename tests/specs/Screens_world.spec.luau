--!nocheck
-- Screens_world (lot B4, étape 5 ; D20, D16 ; GDD v2.0 §10.8 règle 18) : textes du monde du groupe
-- « world » de l'outil d'écrans, à 1920 × 1080 (FR) et 1280 × 720 (EN) :
--   * la couronne dessinée du panneau des ranchs et la goutte du halo de la plaque du titre (icônes de
--     UI/Text) sont posées DANS leur plaque, centrées sur la ligne du texte (l'outil donnait aux textes
--     du monde une boîte de 100 × 100 : icône hors de la plaque sur les captures, défaut du harnais) ;
--   * le panneau le plus long (nom de 20 caractères, Record R 400, « Jour 9999 », badge, « PRÊT ! »)
--     tient dans la largeur sûre d'un écran 1280 × 720 (90 %) : « PRÊT ! » au bout du panneau (D20).
-- Zéro trace.

local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function worldGroup()
		for _, g in Screens.groups() do
			if g.id == "world" then
				return g
			end
		end
		return nil
	end

	local function screenOf(c, group, id)
		for _, s in Screens.expand(c, group) do
			if s.id == id then
				return s
			end
		end
		return nil
	end

	for _, case in { { "tv1080", "fr" }, { "tv720", "en" } } do
		describe("Screens_world › " .. case[1] .. " › " .. case[2], function()
			it(
				"couronne et goutte dessinées dans leur plaque, centrées sur le texte ; panneau dans la largeur sûre",
				function()
					local group = worldGroup()
					local profile = Screens.profileById(case[1])
					local c = Screens.boot(Harness, profile, case[2], group.state)
					local Text = c.h:require(Screens.CLIENT .. "UI.Text")
					local seen = { crown = 0, drop = 0 }
					for _, id in { "world.sign.ready", "world.title.halo" } do
						local ok, err = Screens.show(c, screenOf(c, group, id))
						expect(ok and true or err).toBe(true)
						Screens.layout(c)
						for _, label in Screens.billboardTexts(c) do
							local lr = Layout.rect(label)
							for _, icon in Text.icons(label) do
								local kind = icon:GetAttribute("Icon")
								seen[kind] = (seen[kind] or 0) + 1
								local r = Layout.rect(icon)
								local inside = r ~= nil
									and r.x >= lr.x - 0.5
									and r.y >= lr.y - 0.5
									and r.x + r.w <= lr.x + lr.w + 0.5
									and r.y + r.h <= lr.y + lr.h + 0.5
								local centered = r ~= nil
									and math.abs((r.y + r.h / 2) - (lr.y + lr.h / 2)) <= 3
								expect({
									id = id,
									label = label.Text,
									kind = kind,
									inside = inside,
									centered = centered,
								}).toEqual({
									id = id,
									label = label.Text,
									kind = kind,
									inside = true,
									centered = true,
								})
							end
							-- panneau le plus long : la plaque tient dans 90 % de la largeur de l'écran
							if label:GetFullName():find("Sign1", 1, true) then
								local plate = label.Parent
								local pr = Layout.rect(plate)
								expect(pr.w <= 0.9 * profile.w).toBe(true)
							end
						end
					end
					expect(seen.crown >= 3).toBe(true)
					expect(seen.drop >= 1).toBe(true)
					expect(table.concat(c.h.errors, "\n")).toBe("")
					expect(table.concat(c.h:warnings(), "\n")).toBe("")
					Screens.finish()
				end
			)
		end)
	end
end
