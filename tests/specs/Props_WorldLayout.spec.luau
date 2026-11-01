--!nocheck
-- Props_WorldLayout (paquet logic, docs/04 §17.1 couche a) : repères cohérents, un point est dans au
-- plus un ranch, sol borné, entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")
	local Vector3 = require("@lune/roblox").Vector3

	local h = Harness.new()
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")

	local slots = Props.int(1, 16)
	local worldPoint = Props.vector3(-340, 340, true)
	local localPoint = Props.vector3(-40, 80, true)

	describe("Props › WorldLayout", function()
		it("toLocal(toWorld(p)) = p (flottants 32 bits)", function()
			Props.check(5000, Props.tuple(slots, localPoint), function(v)
				local back = W.toLocal(v[1], W.toWorld(v[1], v[2]))
				return (back - v[2]).Magnitude < 1e-3
			end)
		end)

		it("ranchAt et inRanch d'accord ; jamais deux ranchs pour un point", function()
			Props.check(5000, worldPoint, function(p)
				local slot = W.ranchAt(p)
				local count = 0
				for k = 1, 16 do
					if W.inRanch(k, p) then
						count += 1
						if k ~= slot then
							return false
						end
					end
				end
				return count == (if slot == 0 then 0 else 1)
			end)
		end)

		it("ranchNear(p, 0) ≠ 0 ⇔ ranchAt(p) ≠ 0 (à la frontière près)", function()
			Props.check(5000, worldPoint, function(p)
				local a, b = W.ranchAt(p), W.ranchNear(p, 0)
				if a == b then
					return true
				end
				-- désaccord seulement sur la frontière d'un rectangle
				return W.ranchNear(p, 1e-3) ~= 0
			end)
		end)

		it("supportY ∈ [groundY ; 30], blocked ⇒ supportY = 30 sous l'emprise", function()
			Props.check(5000, worldPoint, function(p)
				local y = W.supportY(p)
				local g = W.groundY(p.X, p.Z)
				if not (y >= g and y <= 30) then
					return false
				end
				if W.blocked(p.X, p.Z, 0) then
					return y == 30
				end
				return true
			end)
		end)

		it("nearestNode : le nœud le plus proche (à égalité près)", function()
			local g = W.graph()
			Props.check(2000, worldPoint, function(p)
				local n = W.nearestNode(p)
				local best = math.huge
				for _, node in g.nodes do
					best =
						math.min(best, (Vector3.new(node.X, 0, node.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude)
				end
				local d = (Vector3.new(g.nodes[n].X, 0, g.nodes[n].Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
				return d <= best + 1e-3
			end)
		end)

		it("entrées bizarres (slot, index, position) : jamais d'erreur, valeurs finies", function()
			Props.check(
				3000,
				Props.tuple(Props.any(), Props.any(), Props.anyNumber(), Props.anyNumber()),
				function(v)
					local p = W.anchor(v[1], v[2])
					local q = W.penSlot(v[1], v[3])
					local r = W.decorSlot(v[1], v[4]).Position
					local s = W.fencePoint(v[1], v[3])
					local y = W.groundY(v[3], v[4])
					local function finite(vec)
						return vec.X == vec.X
							and vec.Z == vec.Z
							and math.abs(vec.X) < 1e6
							and math.abs(vec.Z) < 1e6
					end
					return finite(p)
						and finite(q)
						and finite(r)
						and finite(s)
						and y == y
						and type(W.ranchAt(v[2])) == "number"
				end
			)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
