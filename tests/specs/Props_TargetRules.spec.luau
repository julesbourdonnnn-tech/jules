--!nocheck
-- Props_TargetRules (paquet logic, docs/04 §17.1 couche a) : la cible est toujours un candidat, prêt
-- s'il en existe un ; le cycle visite tous les candidats ; entrées bizarres sûres.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Props = require("../harness/Props")
	local roblox = require("@lune/roblox")
	local Vector3, Vector2 = roblox.Vector3, roblox.Vector2

	local h = Harness.new()
	local TR = h:require("ReplicatedStorage.Shared.Logic.TargetRules")

	local candGen = Props.map(
		Props.tuple(Props.number(-12, 12), Props.number(-12, 12), Props.bool()),
		function(v, rng)
			return { id = "c" .. rng.int(1, 1e6), pos = Vector3.new(v[1], 0, v[2]), ready = v[3] }
		end
	)
	local origin = Vector3.new(0, 3, 0)

	describe("Props › TargetRules", function()
		it("pick : un candidat, prêt dès qu'il en existe un", function()
			Props.check(
				4000,
				Props.tuple(
					Props.array(candGen, 10),
					Props.number(-1, 1),
					Props.number(-1, 1),
					Props.number(0, 1)
				),
				function(v)
					local list = v[1]
					local look = Vector3.new(v[2], 0, v[3])
					local current = if #list > 0 then list[1].id else nil
					local id = TR.pick(origin, look, list, current, v[4], 0)
					if #list == 0 then
						return id == nil
					end
					local chosen, anyReady = nil, false
					for _, cand in list do
						if cand.id == id then
							chosen = cand
						end
						anyReady = anyReady or cand.ready
					end
					return chosen ~= nil and (not anyReady or chosen.ready)
				end
			)
		end)

		it("cycle : dir = 1 répété visite chaque candidat une fois", function()
			Props.check(2000, Props.array(candGen, 8), function(list)
				if #list == 0 then
					return TR.cycle(origin, Vector3.new(0, 0, -1), list, nil, 1) == nil
				end
				local seen, count = {}, 0
				local id = TR.cycle(origin, Vector3.new(0, 0, -1), list, nil, 1)
				for _ = 1, #list do
					if not seen[id] then
						seen[id] = true
						count += 1
					end
					id = TR.cycle(origin, Vector3.new(0, 0, -1), list, id, 1)
				end
				local distinct = {}
				local n = 0
				for _, cand in list do
					if not distinct[cand.id] then
						distinct[cand.id] = true
						n += 1
					end
				end
				return count == n
			end)
		end)

		it("afterPress : un candidat prêt différent de celui pressé, ou nil", function()
			Props.check(3000, Props.array(candGen, 10), function(list)
				local pressed = if #list > 0 then list[1].id else "x"
				local id = TR.afterPress(origin, Vector3.new(1, 0, 0), list, pressed)
				if id == nil then
					for _, cand in list do
						if cand.ready and cand.id ~= pressed then
							return false
						end
					end
					return true
				end
				for _, cand in list do
					if cand.id == id then
						return cand.ready and id ~= pressed
					end
				end
				return false
			end)
		end)

		it("screenPick : seulement dans le rayon de clic, jamais derrière la caméra", function()
			local projGen = Props.map(
				Props.tuple(
					Props.number(0, 1920),
					Props.number(0, 1080),
					Props.number(0, 200),
					Props.number(-50, 100)
				),
				function(v, rng)
					return {
						id = "p" .. rng.int(1, 1e6),
						screen = Vector2.new(v[1], v[2]),
						radius = v[3],
						depth = v[4],
					}
				end
			)
			Props.check(
				3000,
				Props.tuple(
					Props.array(projGen, 8),
					Props.number(0, 1920),
					Props.number(0, 1080),
					Props.number(0.5, 2)
				),
				function(v)
					local pointer = Vector2.new(v[2], v[3])
					local id = TR.screenPick(pointer, v[1], v[4])
					if id == nil then
						return true
					end
					for _, p in v[1] do
						if p.id == id then
							local d = (p.screen - pointer).Magnitude
							return p.depth > 0 and d <= math.max(32 * v[4], p.radius * 1.2) + 1e-4
						end
					end
					return false
				end
			)
		end)

		it("entrées bizarres : jamais d'erreur", function()
			Props.check(3000, Props.tuple(Props.any(), Props.any(), Props.any(), Props.any()), function(v)
				local a = TR.score(v[1], v[2], v[3])
				local b = TR.pick(v[1], v[2], v[3], v[4], v[1], v[2])
				local c = TR.cycle(v[1], v[2], v[3], v[4], v[1])
				local d = TR.afterPress(v[1], v[2], v[3], v[4])
				local e = TR.screenPick(v[1], v[2], v[3])
				return type(a) == "number"
					and (b == nil or type(b) == "string")
					and (c == nil or type(c) == "string")
					and (d == nil or type(d) == "string")
					and (e == nil or type(e) == "string")
			end)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
