--!nocheck
-- SnipRules (paquet logic) : chaque règle du §4.7 isolément puis combinée (ordre exact du contrat),
-- Gloomwisps, immunités et plafond par minute, plafond par coupe, test balayé (Dash, saut, escorte,
-- port sûr, Guard Links, élagage).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local SR = h:require("ReplicatedStorage.Shared.Logic.SnipRules")
	local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local V3 = h.globals.Vector3

	local ORDER = {
		"truce",
		"disabled",
		"self",
		"crew",
		"zen",
		"rookie",
		"immune",
		"perMinute",
		"snipperCooldown",
		"pairCooldown",
		"flagged",
	}

	local NOW = 1000

	-- Entrée de base : coupe autorisée
	local function pair(over)
		local input = {
			now = NOW,
			truce = false,
			snipsDisabled = false,
			isWisp = false,
			snipper = { userId = 1, crewId = 0, zen = false, rookie = false },
			victim = { userId = 2, crewId = 0, zen = false, rookie = false },
			snipperCooldownUntil = 0,
			pairCooldownUntil = 0,
			victimImmuneUntil = 0,
			victimRecent = {},
			snipperFlagged = false,
		}
		for k, v in over or {} do
			input[k] = v
		end
		return input
	end

	-- Active la condition `reason` sur une entrée
	local function apply(input, reason)
		if reason == "truce" then
			input.truce = true
		elseif reason == "disabled" then
			input.snipsDisabled = true
		elseif reason == "self" then
			input.victim.userId = input.snipper and input.snipper.userId or 1
		elseif reason == "crew" then
			if input.snipper then
				input.snipper.crewId = 7
			end
			input.victim.crewId = 7
		elseif reason == "zen" then
			input.victim.zen = true
		elseif reason == "rookie" then
			input.victim.rookie = true
		elseif reason == "immune" then
			input.victimImmuneUntil = NOW + 3
		elseif reason == "perMinute" then
			input.victimRecent = { NOW - 50, NOW - 10 }
		elseif reason == "snipperCooldown" then
			input.snipperCooldownUntil = NOW + 1
		elseif reason == "pairCooldown" then
			input.pairCooldownUntil = NOW + 10
		elseif reason == "flagged" then
			input.snipperFlagged = true
		end
	end

	describe("SnipRules.blockReason (§4.7)", function()
		it("autorise une coupe ordinaire", function()
			expect(SR.blockReason(pair())).toBeNil()
		end)

		it("chaque règle isolément", function()
			for _, reason in ORDER do
				local input = pair()
				apply(input, reason)
				expect(SR.blockReason(input)).toBe(reason)
			end
		end)

		it("toutes les combinaisons (2^11) : la première raison dans l'ordre du contrat", function()
			for mask = 1, 2 ^ #ORDER - 1 do
				local input = pair()
				local expected = nil
				for i, reason in ORDER do
					if bit32.btest(mask, 2 ^ (i - 1)) then
						apply(input, reason)
						expected = expected or reason
					end
				end
				expect(SR.blockReason(input)).toBe(expected)
			end
		end)

		it("détails : Zen du coupeur, bouclier du coupeur, équipage 0, bornes des recharges", function()
			local input = pair()
			input.snipper.zen = true
			expect(SR.blockReason(input)).toBe("zen")
			-- un joueur sous bouclier peut couper les autres
			input = pair()
			input.snipper.rookie = true
			expect(SR.blockReason(input)).toBeNil()
			-- crewId 0 = aucun équipage (deux joueurs sans équipage ne sont pas équipiers)
			expect(SR.blockReason(pair())).toBeNil()
			-- immunité terminée pile à now ; recharges terminées pile à now
			expect(SR.blockReason(pair({ victimImmuneUntil = NOW }))).toBeNil()
			expect(SR.blockReason(pair({ snipperCooldownUntil = NOW }))).toBeNil()
			expect(SR.blockReason(pair({ pairCooldownUntil = NOW }))).toBeNil()
			-- plafond par minute : une coupe trop ancienne ne compte plus
			expect(SR.blockReason(pair({ victimRecent = { NOW - 61, NOW - 10 } }))).toBeNil()
			expect(SR.blockReason(pair({ victimRecent = { NOW - 59, NOW - 1 } }))).toBe("perMinute")
		end)

		it(
			"Gloomwisp : ni self, ni crew, ni recharge du coupeur, ni infraction ; le reste s'applique",
			function()
				local function wisp(over)
					local input = pair(over)
					input.isWisp = true
					input.snipper = nil
					return input
				end
				expect(SR.blockReason(wisp())).toBeNil()
				local w = wisp({ snipperCooldownUntil = NOW + 5, snipperFlagged = true })
				w.victim.crewId = 3
				expect(SR.blockReason(w)).toBeNil()
				w = wisp()
				w.victim.zen = true
				expect(SR.blockReason(w)).toBe("zen")
				w = wisp()
				w.victim.rookie = true
				expect(SR.blockReason(w)).toBe("rookie")
				expect(SR.blockReason(wisp({ victimImmuneUntil = NOW + 1 }))).toBe("immune")
				expect(SR.blockReason(wisp({ victimRecent = { NOW - 5, NOW - 2 } }))).toBe("perMinute")
				expect(SR.blockReason(wisp({ truce = true }))).toBe("truce")
				expect(SR.blockReason(wisp({ snipsDisabled = true }))).toBe("disabled")
			end
		)

		it("entrée malformée : une coupe de joueur sans coupeur est refusée", function()
			local input = pair()
			input.snipper = nil
			expect(SR.blockReason(input)).toBe("self")
		end)
	end)

	describe("SnipRules — immunités, plafonds, rayon", function()
		it("isImmune : 8 s ou plafond par minute", function()
			expect(SR.isImmune(NOW, NOW + 1, {})).toBe(true)
			expect(SR.isImmune(NOW, NOW, {})).toBe(false)
			expect(SR.isImmune(NOW, 0, { NOW - 30 })).toBe(false)
			expect(SR.isImmune(NOW, 0, { NOW - 30, NOW - 20 })).toBe(true)
			expect(SR.isImmune(NOW, 0, { NOW - 90, NOW - 20 })).toBe(false)
		end)

		it("applyCut : 8 s d'immunité, puis jusqu'à 60 s après la 1re coupe au plafond", function()
			local immune, recent = SR.applyCut(NOW, 0, {})
			expect(immune).toBe(NOW + Balance.Snip.VictimImmunity)
			expect(recent).toEqual({ NOW })
			-- 2e coupe 20 s plus tard : plafond atteint → immunité jusqu'à NOW + 60
			immune, recent = SR.applyCut(NOW + 20, immune, recent)
			expect(immune).toBe(NOW + 60)
			expect(recent).toEqual({ NOW, NOW + 20 })
			expect(SR.isImmune(NOW + 59, immune, recent)).toBe(true)
			expect(SR.isImmune(NOW + 60, immune, recent)).toBe(false) -- 60 s après la 1re : fin
			expect(SR.isImmune(NOW + 80, immune, recent)).toBe(false)
			-- les coupes trop anciennes sont purgées
			immune, recent = SR.applyCut(NOW + 200, immune, recent)
			expect(recent).toEqual({ NOW + 200 })
			expect(immune).toBe(NOW + 208)
			-- l'immunité ne recule jamais
			immune = SR.applyCut(NOW, NOW + 500, {})
			expect(immune).toBe(NOW + 500)
			-- entrées hostiles
			immune, recent = SR.applyCut(NOW, 0 / 0, { "x", NOW + 999, NOW - 1 })
			expect(immune).toBe(NOW + 59) -- NOW − 1 et NOW : plafond atteint, 60 s après NOW − 1
			expect(recent).toEqual({ NOW - 1, NOW })
		end)

		it("rayon : 2,8 (+0,3 tactile), 2,5 pour un Gloomwisp", function()
			expect(SR.radius(false, false)).toBe(2.8)
			expect(SR.radius(true, false)).toBeNear(3.1, 1e-12)
			expect(SR.radius(false, true)).toBe(2.5)
			expect(SR.radius(true, true)).toBe(2.5)
		end)

		it("plafond par coupe max(6, floor(0,35 n)) et recul du point de coupe", function()
			expect(SR.lossCap(0)).toBe(6)
			expect(SR.lossCap(10)).toBe(6)
			expect(SR.lossCap(20)).toBe(7)
			expect(SR.lossCap(60)).toBe(21)
			expect(SR.lossCap(0 / 0)).toBe(6)
			expect(SR.cutFrom(5, 10)).toBe(5) -- 6 détachés : sous le plafond
			expect(SR.cutFrom(4, 20)).toBe(14) -- 17 détachés → 7 au plus
			expect(SR.cutFrom(18, 20)).toBe(18)
			expect(SR.cutFrom(4, 60)).toBe(40)
			for n = 1, 60 do
				for k = 1, n do
					local c = SR.cutFrom(k, n)
					expect(c >= k).toBe(true)
					expect(n - c + 1 <= SR.lossCap(n)).toBe(true)
				end
			end
		end)
	end)

	describe("SnipRules.findCut (test balayé)", function()
		-- File droite le long de −Z : tête en (0, 3, 0), nœud i à HeadGap + (i − 1) × Spacing
		local function line(n, origin)
			origin = origin or V3.new(0, 3, 0)
			local nodes = {}
			for i = 1, n do
				nodes[i] = origin + V3.new(0, 0, -(3 + (i - 1) * 2.6))
			end
			return nodes, origin
		end

		local function cut(over)
			local nodes, head = line(12)
			local input = {
				nodes = nodes,
				head = head,
				from = V3.new(-6, 3, -20),
				to = V3.new(6, 3, -20),
				radius = 2.8,
				maxDy = 4,
				guard = 3,
			}
			for k, v in over or {} do
				input[k] = v
			end
			return SR.findCut(input)
		end

		it("premier segment touché le plus près de la tête, point touché sur la file", function()
			-- z = −20 : nœud 7 à −18,6, nœud 8 à −21,2 → segment 7 = [nœud 6 (−16), nœud 7] à 1,4
			local k, point = cut()
			expect(k).toBe(7)
			expect(point.X).toBeNear(0, 1e-4)
			expect(point.Z).toBeNear(-18.6, 1e-4)
			-- loin de la file : rien
			expect((cut({ from = V3.new(-6, 3, -80), to = V3.new(6, 3, -80) }))).toBeNil()
		end)

		it("Guard Links : les G premiers segments ne sont jamais coupables", function()
			-- z = −4 : segment 2 = [nœud 1 (−3), nœud 2 (−5,6)] traversé, segment 4 à 4,2 studs
			local across = { from = V3.new(-6, 3, -4), to = V3.new(6, 3, -4) }
			expect((cut(across))).toBeNil()
			across.guard = 1
			expect((cut(across))).toBe(2)
			across.guard = 0
			expect((cut(across))).toBe(1) -- segment 1 [tête, nœud 1] à 1 stud
			across.from, across.to = V3.new(-6, 3, -1.5), V3.new(6, 3, -1.5)
			expect((cut(across))).toBe(1)
			across.guard = 8
			across.from, across.to = V3.new(-6, 3, -20), V3.new(6, 3, -20)
			expect((cut(across))).toBe(9) -- segments 1-8 protégés, segment 9 = [nœud 8, nœud 9]
			across.guard = 12
			expect((cut(across))).toBeNil()
		end)

		it("Dash à 3,6 studs par tick : traverser la file entre deux ticks la coupe quand même", function()
			-- positions avant / après à 3,6 studs de la file (hors rayon) : seul le balayage la voit
			local k = cut({ from = V3.new(-3.6, 3, -25), to = V3.new(3.6, 3, -25) })
			expect(k).toBe(9)
		end)

		it("sauter au-dessus de la file (|Δy| > 4) ne la coupe pas", function()
			expect((cut({ from = V3.new(-6, 9, -20), to = V3.new(6, 9, -20) }))).toBeNil()
			expect((cut({ from = V3.new(-6, 6.9, -20), to = V3.new(6, 6.9, -20) }))).toBe(7)
		end)

		it("escorte : un nœud protégé par un équipier est ignoré, la coupe passe au suivant", function()
			local escorted = function(k)
				return k == 7
			end
			expect((cut({ isEscorted = escorted }))).toBe(8)
			local all = function()
				return true
			end
			expect((cut({ isEscorted = all }))).toBeNil()
		end)

		it("port sûr : un point touché à < 25 studs d'une porte ne compte pas", function()
			-- file couchée devant la porte du Nid 1 (r = 131)
			local g = WL.gateCFrame(1).Position
			local nodes, head = line(12, V3.new(g.X - 4, 3, g.Z + 20))
			local input = {
				nodes = nodes,
				head = head,
				from = V3.new(g.X - 10, 3, g.Z + 2),
				to = V3.new(g.X + 2, 3, g.Z + 2),
				radius = 2.8,
				maxDy = 4,
				guard = 3,
				inHarbor = WL.inHarbor,
			}
			expect((SR.findCut(input))).toBeNil()
			input.inHarbor = nil
			expect((SR.findCut(input))).toBeTruthy()
		end)

		it("Gloomwisp : rayon 2,5", function()
			local nodes, head = line(12)
			-- balayage parallèle à la file, à 2,6 studs : hors du rayon d'un Gloomwisp, dans celui d'un joueur
			local input = {
				nodes = nodes,
				head = head,
				from = V3.new(2.6, 3, -10),
				to = V3.new(2.6, 3, -30),
				radius = SR.radius(false, true),
				maxDy = 4,
				guard = 3,
			}
			expect((SR.findCut(input))).toBeNil()
			input.radius = SR.radius(false, false)
			expect((SR.findCut(input))).toBe(4)
		end)

		it("élagage par boîtes englobantes cohérent avec le test complet", function()
			local nodes = line(12)
			expect(SR.boundsOverlap(V3.new(-6, 3, -20), V3.new(6, 3, -20), 2.8, nodes, 3)).toBe(true)
			expect(SR.boundsOverlap(V3.new(10, 3, -20), V3.new(20, 3, -20), 2.8, nodes, 3)).toBe(false)
			expect(SR.boundsOverlap(V3.new(2.5, 3, -20), V3.new(20, 3, -20), 2.8, nodes, 3)).toBe(true)
			expect(SR.boundsOverlap(V3.new(2.9, 3, -20), V3.new(20, 3, -20), 2.8, nodes, 3)).toBe(false)
			expect(SR.boundsOverlap(V3.new(0, 3, 0), V3.new(0, 3, 1), 2.8, nodes, 13)).toBe(false)
			-- file vide ou trop courte
			expect((SR.findCut({
				nodes = {},
				head = V3.zero,
				from = V3.zero,
				to = V3.one,
				radius = 3,
				maxDy = 4,
				guard = 0,
			}))).toBeNil()
			local short = line(3)
			expect((SR.findCut({
				nodes = short,
				head = V3.new(0, 3, 0),
				from = V3.new(-5, 3, -8),
				to = V3.new(5, 3, -8),
				radius = 3,
				maxDy = 4,
				guard = 3,
			}))).toBeNil()
		end)

		it("balayages aléatoires : findCut est d'accord avec un échantillonnage dense", function()
			local rng = h.globals.Random.new(7)
			for _ = 1, 400 do
				-- file sinueuse de 15 nœuds
				local nodes = {}
				local p = V3.new(0, 3, 0)
				local heading = rng:NextNumber() * math.pi * 2
				for i = 1, 15 do
					heading += (rng:NextNumber() - 0.5) * 0.8
					p += V3.new(math.cos(heading), 0, math.sin(heading)) * 2.6
					nodes[i] = p
				end
				local from = V3.new(rng:NextNumber() * 40 - 20, 3, rng:NextNumber() * 40 - 20)
				local a = rng:NextNumber() * math.pi * 2
				local to = from + V3.new(math.cos(a), 0, math.sin(a)) * 3.6
				local k = SR.findCut({
					nodes = nodes,
					head = V3.new(0, 3, 0),
					from = from,
					to = to,
					radius = 2.8,
					maxDy = 4,
					guard = 3,
				})
				-- référence : distance point-segment exacte sur 150 échantillons du balayage
				local best = nil
				for seg = 4, 15 do
					local s0, s1 = nodes[seg - 1], nodes[seg]
					local dx, dz = s1.X - s0.X, s1.Z - s0.Z
					local len2 = dx * dx + dz * dz
					for j = 0, 150 do
						local u = j / 150
						local qx = from.X + (to.X - from.X) * u
						local qz = from.Z + (to.Z - from.Z) * u
						local t = math.clamp(((qx - s0.X) * dx + (qz - s0.Z) * dz) / len2, 0, 1)
						local cx, cz = s0.X + dx * t - qx, s0.Z + dz * t - qz
						if math.sqrt(cx * cx + cz * cz) <= 2.8 - 1e-3 then
							best = seg
							break
						end
					end
					if best then
						break
					end
				end
				if best then
					expect(k ~= nil and k <= best).toBe(true)
				end
				if k then
					expect(k >= 4).toBe(true)
				end
			end
		end)
	end)
end
