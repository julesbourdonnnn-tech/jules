--!nocheck
-- LeapRules (paquet logic, docs/04 §12.1, GDD §4.12) : direction bornée, atterrissage raccourci par
-- le premier solide (jamais à travers un mur de clôture), arc fixe, visée sur la position future,
-- capture à l'atterrissage.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local Vector3 = require("@lune/roblox").Vector3

	local h = Harness.new()
	local L = h:require("ReplicatedStorage.Shared.Logic.LeapRules")
	local W = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")

	local function flat(a, b)
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	describe("LeapRules", function()
		it("validDir : composantes finies, norme dans [0,5 ; 1,5], rendue unitaire", function()
			local d = L.validDir(1, 0)
			expect(d).toEqual(Vector3.new(1, 0, 0))
			expect(L.validDir(0.3, 0.4) ~= nil).toBe(true) -- norme 0,5
			expect(L.validDir(0.3, 0.3)).toBeNil()
			expect(L.validDir(1.2, 1.2)).toBeNil()
			expect(L.validDir(0 / 0, 1)).toBeNil()
			expect(L.validDir(math.huge, 0)).toBeNil()
			expect(L.validDir("1", 0)).toBeNil()
		end)

		it("atterrissage libre : 12 studs dans la direction, même hauteur", function()
			local from = Vector3.new(0, 3, 0)
			local land = L.landing(from, Vector3.new(0, 0, 1))
			expect(flat(land, from)).toBeNear(12, 1e-3)
			expect(land.Y).toBe(3)
		end)

		it("devant un mur de clôture : raccourci à 1,5 stud du mur, jamais au travers", function()
			local slot = 6
			-- dans la rue, 5 studs devant le mur de devant, bond vers le ranch (hors portail)
			local from = W.toWorld(slot, Vector3.new(15, 3, -5))
			local dir = (W.toWorld(slot, Vector3.new(15, 3, 10)) - from).Unit
			local land = L.landing(from, dir)
			local l = W.toLocal(slot, land)
			expect(l.Z).toBeNear(-1.5, 1e-2)
			expect(W.ranchAt(land)).toBe(0)
			-- par le portail (non solide) : le bond passe, la poussée du serveur s'en charge
			local gateFrom = W.toWorld(slot, Vector3.new(0, 3, -5))
			local gateLand = L.landing(gateFrom, (W.toWorld(slot, Vector3.new(0, 3, 10)) - gateFrom).Unit)
			expect(W.toLocal(slot, gateLand).Z).toBeNear(7, 1e-2)
		end)

		it("collé à un mur : aucun déplacement vers le mur", function()
			local slot = 2
			local from = W.toWorld(slot, Vector3.new(15, 3, -1))
			local land = L.landing(from, (W.toWorld(slot, Vector3.new(15, 3, 10)) - from).Unit)
			expect(flat(land, from) < 1e-2).toBe(true)
		end)

		it("arc : départ, arrivée, sommet de 2,5 studs au milieu", function()
			local a, b = Vector3.new(0, 3, 0), Vector3.new(12, 3, 0)
			expect(L.arc(a, b, 0)).toEqual(a)
			expect(L.arc(a, b, 1)).toEqual(b)
			expect(L.arc(a, b, 0.5).Y).toBeNear(5.5, 1e-5)
			expect(L.arc(a, b, 2)).toEqual(b)
			expect(L.arc(a, b, 0 / 0)).toEqual(a)
		end)

		it("visée : position à l'atterrissage, 16 studs, ±40°, jamais selon la caméra", function()
			local origin = Vector3.new(0, 3, 0)
			local stick = Vector3.new(1, 0, 0)
			local function at(x, z)
				return function(_t)
					return Vector3.new(x, 0, z)
				end
			end
			local candidates = {
				{ id = 1, posAt = at(10, 0) },
				{ id = 2, posAt = at(8, 8) }, -- 45° : hors du cône
				{ id = 3, posAt = at(20, 0) }, -- trop loin
				{ id = 4, posAt = at(-5, 0) }, -- derrière
			}
			expect(L.aim(origin, stick, candidates, 0, nil)).toBe(1)
			-- la position future compte : la créature 5 sera à portée dans 0,35 s
			local moving = {
				{
					id = 5,
					posAt = function(t)
						return Vector3.new(30 - t * 50, 0, 0)
					end,
				},
			}
			expect(L.aim(origin, stick, moving, 0, nil)).toBe(5)
			expect(L.aim(origin, Vector3.zero, candidates, 0, nil)).toBeNil()
			expect(L.aim(origin, stick, {}, 0, nil)).toBeNil()
		end)

		it("visée : hystérésis de 20 % (la cible ne change que pour une 20 % plus proche)", function()
			local origin = Vector3.new(0, 3, 0)
			local stick = Vector3.new(1, 0, 0)
			local function at(x)
				return function(_t)
					return Vector3.new(x, 0, 0)
				end
			end
			local list = { { id = 1, posAt = at(10) }, { id = 2, posAt = at(9) } }
			expect(L.aim(origin, stick, list, 0, 1)).toBe(1) -- 9 > 0,8 × 10
			local list2 = { { id = 1, posAt = at(10) }, { id = 2, posAt = at(7.9) } }
			expect(L.aim(origin, stick, list2, 0, 1)).toBe(2)
			-- candidat qui lève une erreur : ignoré
			local bad = {
				{
					id = 9,
					posAt = function()
						error("boom")
					end,
				},
				{
					id = 1,
					posAt = at(10),
				},
			}
			expect(L.aim(origin, stick, bad, 0, nil)).toBe(1)
		end)

		it(
			"capture à l'atterrissage : 5 studs (8 pour le propriétaire), + tolérance du serveur",
			function()
				local land = Vector3.new(0, 3, 0)
				expect(L.catchesOnLanding(land, Vector3.new(5, 0, 0), false)).toBe(true)
				expect(L.catchesOnLanding(land, Vector3.new(5.1, 0, 0), false)).toBe(false)
				expect(L.catchesOnLanding(land, Vector3.new(6.4, 0, 0), false, 1.5)).toBe(true)
				expect(L.catchesOnLanding(land, Vector3.new(8, 0, 0), true)).toBe(true)
				expect(L.catchesOnLanding(land, Vector3.new(9.4, 0, 0), true, 1.5)).toBe(true)
				expect(L.catchesOnLanding(land, Vector3.new(0, 12, 0), false, 1.5)).toBe(false) -- écart vertical > 8
				expect(L.catchesOnLanding(land, nil, false)).toBe(false)
			end
		)

		it(
			"capture à l'atterrissage en monture (règle 17) : écart vertical mesuré depuis les PIEDS",
			function()
				local Z = h:require("ReplicatedStorage.Shared.Logic.ZoneRules")
				-- selle géante : racine 3 + 6 = 9 au-dessus du sol ; la créature court au sol (Y = 0)
				local rider = Vector3.new(0, 9, 0)
				expect(L.catchesOnLanding(rider, Vector3.new(4, 0, 0), false, 1.5, 6)).toBe(true)
				expect(L.catchesOnLanding(rider, Vector3.new(6.4, 0, 0), false, 1.5, 6)).toBe(true)
				expect(L.catchesOnLanding(rider, Vector3.new(6.6, 0, 0), false, 1.5, 6)).toBe(false)
				-- petite et grande selles (+4,275 et +5,25)
				expect(L.catchesOnLanding(Vector3.new(0, 7.275, 0), Vector3.new(3, 0, 0), false, 1.5, 4.275)).toBe(
					true
				)
				expect(L.catchesOnLanding(Vector3.new(0, 8.25, 0), Vector3.new(3, 0, 0), false, 1.5, 5.25)).toBe(
					true
				)
				-- même règle que ZoneRules.feetY : pieds à 0, une créature à 8 studs au-dessus passe, 8,1 non
				expect(Z.feetY(9, 6)).toBe(0)
				expect(L.catchesOnLanding(rider, Vector3.new(0, 8, 0), false, 0, 6)).toBe(true)
				expect(L.catchesOnLanding(rider, Vector3.new(0, 8.1, 0), false, 0, 6)).toBe(false)
				-- décalage illisible : 0 (à pied)
				expect(L.catchesOnLanding(Vector3.new(0, 3, 0), Vector3.new(1, 0, 0), false, 0, 0 / 0)).toBe(
					true
				)
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
