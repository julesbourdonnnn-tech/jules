--!nocheck
-- ZoneRules (paquet logic, docs/04 §12.1, GDD §4.6, §4.8, §6.3, §4.22) : zones sur la position
-- validée, hystérésis des dalles, clôture côté rue, intrus, MEGA, Autel.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Vector3 = require("@lune/roblox").Vector3

	local h = Harness.new()
	local Z = h:require("ReplicatedStorage.Shared.Logic.ZoneRules")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")

	describe("ZoneRules", function()
		it(
			"dalles : entrée à 2,5 studs, sortie au-delà de 3,5, un « vient d'entrer » par entrée",
			function()
				expect({ Z.padStep(false, 2.5) }).toEqual({ true, true })
				expect({ Z.padStep(false, 2.6) }).toEqual({ false, false })
				expect({ Z.padStep(true, 3.5) }).toEqual({ true, false })
				expect({ Z.padStep(true, 3.6) }).toEqual({ false, false })
				expect({ Z.padStep(false, 0 / 0) }).toEqual({ false, false })
				-- marcher sur le bord (3 studs) ne rachète jamais
				local inside, entries = false, 0
				for _, d in { 5, 2, 3, 3.4, 2.9, 3.2, 3.5, 3.4, 2.4, 6, 2 } do
					local entered
					inside, entered = Z.padStep(inside, d)
					if entered then
						entries += 1
					end
				end
				expect(entries).toBe(2)
			end
		)

		it("près d'un objet du ranch (distance à plat)", function()
			local pot = W.anchor(3, "pot")
			expect(Z.near(3, "pot", pot + Vector3.new(4.9, 3, 0), 5)).toBe(true)
			expect(Z.near(3, "pot", pot + Vector3.new(5.1, 0, 0), 5)).toBe(false)
			expect(Z.near(4, "pot", pot, 5)).toBe(false)
			expect(Z.near(0, "pot", pot, 5)).toBe(false)
			expect(Z.near(3, "pot", Vector3.new(0 / 0, 0, 0), 5)).toBe(false)
			expect(Z.near(3, "pot", pot, -1)).toBe(false)
		end)

		it("objet du ranch inconnu (faute de frappe d'un service) : jamais vrai, même au portail", function()
			local gate = W.anchor(3, "gate")
			expect(Z.near(3, "gate", gate, 5)).toBe(true)
			-- WorldLayout.anchor rend le portail pour un nom inconnu : near ne doit pas s'en servir
			expect(Z.near(3, "pott", gate, 5)).toBe(false)
			expect(Z.near(3, nil, gate, 5)).toBe(false)
			expect(Z.near(3, 12, gate, 5)).toBe(false)
			expect(W.hasAnchor("pot")).toBe(true)
			expect(W.hasAnchor("pott")).toBe(false)
			expect(W.hasAnchor(nil)).toBe(false)
		end)

		it("MEGA : à 20 studs du centre du pad", function()
			expect(Z.inMegaZone(Vector3.new(19.9, 3, 0))).toBe(true)
			expect(Z.inMegaZone(Vector3.new(14, 0, 14.5))).toBe(false)
			expect(Z.inMegaZone(nil)).toBe(false)
		end)

		it(
			"clôture côté rue : devant le mur, à `radius` d'une place de clôture ; jamais dedans",
			function()
				local slot = 9
				local fp = W.fencePoint(slot, 2) -- (−12, 5) local
				local street = W.toWorld(slot, Vector3.new(-12, 3, -1.5))
				expect(Z.streetSideOfFence(slot, street, 8)).toBe(true)
				expect(Z.streetSideOfFence(slot, W.toWorld(slot, Vector3.new(-12, 3, -9)), 8)).toBe(false)
				-- dans le ranch, même tout près : jamais « côté rue »
				expect(Z.streetSideOfFence(slot, W.toWorld(slot, Vector3.new(-12, 3, 3)), 8)).toBe(false)
				expect(Z.streetSideOfFence(slot, fp, 8)).toBe(false)
				expect(Z.streetSideOfFence(slot + 1, street, 8)).toBe(false)
				-- pet-sitting : 10 studs
				expect(Z.streetSideOfFence(slot, W.toWorld(slot, Vector3.new(-12, 3, -4.5)), 10)).toBe(true)
			end
		)

		it("propriétaire proche : à 25 studs de sa clôture de devant", function()
			local slot = 2
			expect(Z.ownerNearFence(slot, W.toWorld(slot, Vector3.new(0, 3, 24)))).toBe(true)
			expect(Z.ownerNearFence(slot, W.toWorld(slot, Vector3.new(0, 3, 26)))).toBe(false)
			expect(Z.ownerNearFence(slot, W.toWorld(slot, Vector3.new(0, 3, -20)))).toBe(true)
			expect(Z.ownerNearFence(slot, W.toWorld(slot, Vector3.new(50, 3, 0)))).toBe(true) -- 18 studs du coin
			expect(Z.ownerNearFence(slot, W.toWorld(slot, Vector3.new(60, 3, 0)))).toBe(false)
		end)

		it("intrus : ranch d'un autre, jamais le sien ni la rue", function()
			local inside3 = W.toWorld(3, Vector3.new(0, 3, 20))
			expect(Z.intruder(5, inside3)).toBe(3)
			expect(Z.intruder(3, inside3)).toBe(0)
			expect(Z.intruder(0, inside3)).toBe(3) -- sans ranch : tous les ranchs sont à d'autres
			expect(Z.intruder(5, W.gateOutside(3))).toBe(0)
			-- debout dans la membrane du portail d'un autre : intrus
			expect(Z.intruder(5, W.toWorld(3, Vector3.new(0, 3, 0.2)))).toBe(3)
		end)

		it("Autel de la Lune : présence près de l'autel", function()
			local altar = W.plaza("altar")
			expect(Z.atAltar(altar + Vector3.new(0, 3, 11))).toBe(true)
			expect(Z.atAltar(altar + Vector3.new(0, 3, 13))).toBe(false)
		end)

		it("distXZ (contrat v1.2) : distance à plat, la hauteur ne compte jamais", function()
			expect(Z.distXZ(Vector3.new(0, 0, 0), Vector3.new(3, 100, 4))).toBe(5)
			expect(Z.distXZ(Vector3.new(1, -50, 1), Vector3.new(1, 50, 1))).toBe(0)
			-- entrées bizarres : infiniment loin (aucune portée ne passe), jamais NaN ni erreur
			expect(Z.distXZ(Vector3.new(0 / 0, 0, 0), Vector3.zero)).toBe(math.huge)
			expect(Z.distXZ(Vector3.zero, Vector3.new(math.huge, 0, 0))).toBe(math.huge)
			expect(Z.distXZ(nil, Vector3.zero)).toBe(math.huge)
			expect(Z.distXZ(Vector3.zero, "x")).toBe(math.huge)
		end)

		it("feetY (contrat v1.2) : racine − hauteur debout − hausse de la monture", function()
			local root = W.Const.RootHeight
			expect(root).toBe(3)
			-- à pied, debout sur le sol (Y = 0) : racine à 3, pieds à 0
			expect(Z.feetY(3, 0)).toBe(0)
			-- en monture (selle géante : racine + 6) : pieds toujours au sol
			expect(Z.feetY(9, 6)).toBe(0)
			expect(Z.feetY(7.275, 4.275)).toBeNear(0, 1e-9)
			-- décalage illisible ou négatif : 0 ; racine illisible : infiniment loin
			expect(Z.feetY(3, 0 / 0)).toBe(0)
			expect(Z.feetY(3, -5)).toBe(0)
			expect(Z.feetY(3, nil)).toBe(0)
			expect(Z.feetY(0 / 0, 0)).toBe(math.huge)
			expect(Z.feetY(math.huge, 0)).toBe(math.huge)
		end)

		it("feetY : hauteur debout identique à Server/Movement/Tuning.RootHeight (MoveCheck)", function()
			local hs = Harness.new({ mode = "server" })
			local Tuning = hs:require("ServerScriptService.Server.Movement.Tuning")
			expect(W.Const.RootHeight).toBe(Tuning.RootHeight)
			expect(#hs.errors).toBe(0)
		end)

		it(
			"withinReach : portée à plat + écart vertical depuis les pieds ≤ Catch.MaxDY (règle 17)",
			function()
				local B = h:require("ReplicatedStorage.Shared.Config.Balance")
				local pot = W.anchor(5, "pot")
				-- à pied, à 4,9 studs à plat
				expect(Z.withinReach(pot + Vector3.new(4.9, 3, 0), 0, pot, 5)).toBe(true)
				expect(Z.withinReach(pot + Vector3.new(5.1, 3, 0), 0, pot, 5)).toBe(false)
				-- en monture géante (racine + 6) : la portée ne diminue jamais
				expect(Z.withinReach(pot + Vector3.new(4.9, 9, 0), 6, pot, 5)).toBe(true)
				-- sans le décalage, la même racine compterait 6 studs de plus (toujours ≤ 8 ici)
				expect(Z.withinReach(pot + Vector3.new(0, 3 + B.Catch.MaxDY, 0), 0, pot, 5)).toBe(true)
				expect(Z.withinReach(pot + Vector3.new(0, 3 + B.Catch.MaxDY + 0.1, 0), 0, pot, 5)).toBe(false)
				expect(Z.withinReach(pot + Vector3.new(0, 3 - B.Catch.MaxDY - 0.1, 0), 0, pot, 5)).toBe(false)
				-- entrées bizarres : jamais vrai
				expect(Z.withinReach(Vector3.new(0 / 0, 3, 0), 0, pot, 5)).toBe(false)
				expect(Z.withinReach(pot, 0, nil, 5)).toBe(false)
				expect(Z.withinReach(pot, 0, pot, 0 / 0)).toBe(false)
				expect(Z.withinReach(pot, 0, pot, -1)).toBe(false)
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
