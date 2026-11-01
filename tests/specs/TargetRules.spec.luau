--!nocheck
-- TargetRules (paquet logic, docs/04 §12.1, GDD §10.4) : score, prêts d'abord, hystérésis (1,5 stud
-- ou 0,25 s), cycle L1 / R1 de gauche à droite, prochain prêt après une pression, clic à l'écran.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local roblox = require("@lune/roblox")
	local Vector3, Vector2 = roblox.Vector3, roblox.Vector2

	local h = Harness.new()
	local TR = h:require("ReplicatedStorage.Shared.Logic.TargetRules")

	local origin = Vector3.new(0, 3, 0)
	local look = Vector3.new(0, 0, -1) -- regard vers −Z
	local function c(id, x, z, ready)
		return { id = id, pos = Vector3.new(x, 0, z), ready = ready ~= false }
	end

	describe("TargetRules", function()
		it("score = distance + 6 × (angle ÷ 90°)", function()
			expect(TR.score(origin, look, Vector3.new(0, 0, -5))).toBeNear(5, 1e-9)
			expect(TR.score(origin, look, Vector3.new(5, 0, 0))).toBeNear(5 + 6, 1e-9)
			expect(TR.score(origin, look, Vector3.new(0, 0, 5))).toBeNear(5 + 12, 1e-9)
			expect(TR.score(origin, look, nil)).toBe(math.huge)
			expect(TR.score(origin, Vector3.zero, Vector3.new(3, 0, 4))).toBeNear(5, 1e-9)
		end)

		it("pick : le plus petit score ; les prêts passent avant ceux en recharge", function()
			local list = { c("near", 0, -2, false), c("far", 0, -8, true) }
			expect(TR.pick(origin, look, list, nil, 0, 0)).toBe("far")
			list[2].ready = false
			expect(TR.pick(origin, look, list, nil, 0, 0)).toBe("near")
			expect(TR.pick(origin, look, {}, nil, 0, 0)).toBeNil()
		end)

		it("hystérésis : garde la cible sauf meilleure de 1,5 stud ou 0,25 s écoulées", function()
			local list = { c("a", 0, -5), c("b", 0, -4) }
			-- b est meilleure d'1 stud seulement : a reste pendant 0,25 s
			expect(TR.pick(origin, look, list, "a", 10.1, 10)).toBe("a")
			expect(TR.pick(origin, look, list, "a", 10.25, 10)).toBe("b")
			-- meilleure de plus de 1,5 stud : change tout de suite
			local list2 = { c("a", 0, -5), c("b", 0, -3) }
			expect(TR.pick(origin, look, list2, "a", 10.1, 10)).toBe("b")
			-- cible actuelle en recharge alors qu'un autre est prêt : change
			local list3 = { c("a", 0, -2, false), c("b", 0, -9) }
			expect(TR.pick(origin, look, list3, "a", 10, 10)).toBe("b")
		end)

		it("cycle : par angle de gauche à droite, en boucle", function()
			local list = { c("right", 5, -5), c("left", -5, -5), c("center", 0, -5) }
			expect(TR.cycle(origin, look, list, "left", 1)).toBe("center")
			expect(TR.cycle(origin, look, list, "center", 1)).toBe("right")
			expect(TR.cycle(origin, look, list, "right", 1)).toBe("left")
			expect(TR.cycle(origin, look, list, "left", -1)).toBe("right")
			expect(TR.cycle(origin, look, list, nil, 1)).toBe("center")
			expect(TR.cycle(origin, look, {}, nil, 1)).toBeNil()
		end)

		it("après une pression : le prochain squishy prêt (jamais celui qu'on vient de presser)", function()
			local list = { c("a", 0, -3), c("b", 0, -6), c("c", 0, -4, false) }
			expect(TR.afterPress(origin, look, list, "a")).toBe("b")
			expect(TR.afterPress(origin, look, { c("a", 0, -3) }, "a")).toBeNil()
		end)

		it(
			"clic : le plus proche du pointeur dans max(32 px TV × échelle, rayon projeté × 1,2)",
			function()
				local projected = {
					{ id = "a", screen = Vector2.new(100, 100), radius = 10, depth = 20 },
					{ id = "b", screen = Vector2.new(200, 100), radius = 100, depth = 30 },
					{ id = "behind", screen = Vector2.new(400, 400), radius = 50, depth = -5 },
				}
				expect(TR.screenPick(Vector2.new(120, 100), projected, 1)).toBe("a")
				expect(TR.screenPick(Vector2.new(140, 100), projected, 1)).toBe("b") -- hors des 32 px de a, dans les 120 de b
				expect(TR.screenPick(Vector2.new(140, 100), projected, 2)).toBe("a") -- 64 px à l'échelle 2
				expect(TR.screenPick(Vector2.new(400, 400), projected, 1)).toBeNil() -- derrière la caméra
				expect(TR.screenPick(Vector2.new(0 / 0, 0), projected, 1)).toBeNil()
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
