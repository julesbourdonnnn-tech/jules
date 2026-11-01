--!nocheck
-- RedTeam_Press (paquet ranch, docs/04 §15, §17.1 couche g, §18.2) : presser écrit comme une attaque.
-- Portée à plat (10 + 2 du centre de la place) et écart vertical depuis les PIEDS (≤ 8) ; monture
-- (racine plus haute de 4,3 à 6 studs) jamais pénalisée ; position validée et canAct obligatoires
-- (jamais la racine brute du client) ; squishy d'un autre, au Dodo, porté, en fuite : refusé ;
-- tClient truqué ramené à maintenant ; recharge de 8 s ; pet-sitting seulement à sa place de la
-- clôture (raison « petsit »), côté rue, et le propriétaire n'a jamais le PERFECT.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 100, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 1, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function boot()
		local caught = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				for userId = 1, 2 do
					local d = Bots.profile(w, {
						onboarding = { step = 11, done = true, demoDone = true },
						squishies = {
							["1"] = rec({ bf = 1 }),
							["2"] = rec({ s = 2 }),
							["3"] = rec({ s = 3, at = "dodo" }),
						},
						nextUid = 4,
						biggestEver = 2e12, -- selle géante
					})
					Bots.saveProfile(w, userId, d)
				end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
		w.PressTiming = w.h:require("ReplicatedStorage.Shared.Logic.PressTiming")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function stand(w, p, pos)
		w.MoveCheck.reset(p, pos, w.Clock.now())
	end

	local function fresh(w)
		w.Clock.advance(8.01) -- recharge écoulée
	end

	describe("RedTeam_Press › portée et position", function()
		it(
			"de loin (12,5 studs à plat) : refusé ; à 11,9 : accepté ; la hauteur ne rallonge jamais la portée",
			function()
				local w = boot()
				local p = Bots.join(1)
				local c = w.Squishy.placeOf(p, "1")
				stand(w, p, w.V3.new(c.X + 12.5, 3, c.Z))
				expect(w.Squishy.press(p, "1", T0, nil)).toBe(false)
				stand(w, p, w.V3.new(c.X + 8.42, 3, c.Z + 8.42)) -- 11,9 en diagonale
				expect(w.Squishy.press(p, "1", T0, nil)).toBe(true)
				fresh(w)
				-- téléporté au-dessus (pieds à 20 studs) : refusé, même juste au-dessus de la place
				stand(w, p, w.V3.new(c.X, 23, c.Z))
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(false)
				clean(w)
			end
		)

		it(
			"monture (selle géante, racine + 6) : portée intacte, pieds mesurés depuis la monture",
			function()
				local w = boot()
				local p = Bots.join(1)
				local c = w.Squishy.placeOf(p, "1")
				stand(w, p, w.V3.new(c.X + 11, 3, c.Z))
				w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				w.h:fireServer("ReplicatedStorage.Remotes.Ride", p, true)
				expect(w.Squishy.riding(p)).toBe(true)
				local stats = w.Formulas.rideStats(3)
				local rise = stats.hipHeight - w.Balance.Ride.BaseHipHeight
				stand(w, p, w.V3.new(c.X + 11, 3 + rise, c.Z))
				expect(w.Squishy.press(p, "1", w.Clock.now(), nil)).toBe(true)
				clean(w)
			end
		)

		it("sans position validée ou sans canAct (rafale, retour récent) : refusé", function()
			local w = boot()
			local p = Bots.join(1)
			w.MoveCheck.clear(p)
			expect(w.Squishy.press(p, "1", T0, nil)).toBe(false)
			local c = w.Squishy.placeOf(p, "1")
			stand(w, p, w.V3.new(c.X, 3, c.Z))
			local canAct = w.MoveCheck.canAct
			w.MoveCheck.canAct = function()
				return false
			end
			expect(w.Squishy.press(p, "1", T0, nil)).toBe(false)
			w.MoveCheck.canAct = canAct
			expect(w.Squishy.press(p, "1", T0, nil)).toBe(true)
			clean(w)
		end)
	end)

	describe("RedTeam_Press › cibles interdites, temps truqué, recharge", function()
		it(
			"squishy au Dodo, porté, en fuite, uid inconnu : refusé ; recharge de 8 s par squishy",
			function()
				local w = boot()
				local p = Bots.join(1)
				local c = w.Squishy.placeOf(p, "2")
				stand(w, p, w.V3.new(c.X, 3, c.Z))
				expect(w.Squishy.press(p, "3", T0, nil)).toBe(false) -- Dodo
				expect(w.Squishy.press(p, "zz", T0, nil)).toBe(false)
				expect(w.Squishy.press(p, "", T0, nil)).toBe(false)
				w.Squishy.setEscaping(p, "2", true)
				expect(w.Squishy.press(p, "2", T0, nil)).toBe(false)
				w.Squishy.setEscaping(p, "2", false)
				expect(w.Squishy.press(p, "2", T0, nil)).toBe(true)
				for _ = 1, 20 do
					expect(w.Squishy.press(p, "2", T0, nil)).toBe(false)
				end
				w.Clock.advance(7.9)
				expect(w.Squishy.press(p, "2", w.Clock.now(), nil)).toBe(false)
				w.Clock.advance(0.2)
				stand(w, p, w.V3.new(c.X, 3, c.Z))
				expect(w.Squishy.press(p, "2", w.Clock.now(), nil)).toBe(true)
				clean(w)
			end
		)

		it(
			"tClient truqué (NaN, futur, trop ancien) : ramené à maintenant, jamais un PERFECT choisi",
			function()
				local w = boot()
				local p = Bots.join(1)
				local pressed = {}
				w.Signals.Pressed:Connect(function(_, info)
					table.insert(pressed, info)
				end)
				local c = w.Squishy.placeOf(p, "1")
				local offset = w.PressTiming.offset(1, "1")
				-- maintenant : hors de la fenêtre PERFECT ; les tClient truqués visent le sommet
				local now = w.PressTiming.nextApex(T0 + 2, offset) + 0.6
				for _, t in { 0 / 0, now + 50, now - 5, w.PressTiming.nextApex(now, offset) } do
					w.Clock.freeze(now)
					stand(w, p, w.V3.new(c.X, 3, c.Z))
					expect(w.Squishy.press(p, "1", t, nil)).toBe(true)
					now += 8.01
					now = w.PressTiming.nextApex(now, offset) + 0.6
				end
				w.h:settle(1)
				for _, info in pressed do
					expect(info.perfect).toBe(false)
				end
				clean(w)
			end
		)

		it(
			"squishy d'un autre joueur (même uid dans son profil) : jamais pressé par l'intention Press",
			function()
				local w = boot()
				local p = Bots.join(1)
				local q = Bots.join(2)
				local theirs = w.Squishy.placeOf(q, "1")
				stand(w, p, w.V3.new(theirs.X, 3, theirs.Z))
				local coinsQ = w.DS.get(q).coins
				w.h:fireServer("ReplicatedStorage.Remotes.Press", p, "1", T0)
				expect(w.DS.get(q).coins).toBe(coinsQ)
				expect(w.Squishy.readyAt(q, "1")).toBe(0)
				clean(w)
			end
		)
	end)

	describe("RedTeam_Press › pet-sitting", function()
		it(
			"seulement à sa place de la clôture (raison « petsit ») ; propriétaire sans PERFECT",
			function()
				local w = boot()
				local owner = Bots.join(1)
				local visitor = Bots.join(2)
				local slot = w.Ranch.slotOf(owner)
				local pressed = {}
				w.Signals.Pressed:Connect(function(who, info)
					table.insert(pressed, { who = who, info = info })
				end)
				local fence = w.W.fencePoint(slot, 1)
				-- côté rue de la clôture (repère local du ranch : Z < 0) ; revue : l'ancienne position
				-- (fence.Z − 3 dans le repère du MONDE) était DANS le ranch de l'ami (Z local = 4,4)
				local fenceLocal = w.W.toLocal(slot, fence)
				local function street(dz)
					local q = w.W.toWorld(slot, w.V3.new(fenceLocal.X, 0, -dz))
					return w.V3.new(q.X, 3, q.Z)
				end
				stand(w, visitor, street(3))
				-- pas à la clôture : refusé
				expect(w.Squishy.press(owner, "2", T0, visitor)).toBe(false)
				-- clôture du Rush (pas du pet-sitting) : refusé
				w.Ranch.setFence(slot, { "2" }, "rush")
				expect(w.Squishy.press(owner, "2", T0, visitor)).toBe(false)
				w.Ranch.setFence(slot, {}, "rush")
				w.Ranch.setFence(slot, { "2" }, "petsit")
				-- trop loin de la place de la clôture : refusé
				stand(w, visitor, street(8)) -- 13 studs à plat de la place de la clôture
				expect(w.Squishy.press(owner, "2", T0, visitor)).toBe(false)
				-- dans le ranch de l'ami, à 3 studs de la place : refusé (côté rue seulement)
				stand(w, visitor, w.V3.new(fence.X, 3, fence.Z - 3))
				expect(w.Squishy.press(owner, "2", T0, visitor)).toBe(false)
				stand(w, visitor, street(3))
				local offset = w.PressTiming.offset(1, "2")
				local apex = w.PressTiming.nextApex(T0 + 1, offset)
				w.Clock.freeze(apex)
				stand(w, visitor, street(3))
				local income = w.h:require(S .. "EconomyService").squishyIncome(owner, "2")
				local coins0 = w.DS.get(owner).coins
				expect(w.Squishy.press(owner, "2", apex, visitor)).toBe(true)
				w.h:settle(1)
				expect(pressed[1].who).toBe(owner)
				expect(pressed[1].info.visitor).toBe(visitor)
				expect(pressed[1].info.perfect).toBe(true) -- PERFECT du visiteur (sa récompense, CommunityService)
				-- le propriétaire reçoit la pression normale SANS PERFECT
				expect(w.DS.get(owner).coins - coins0).toBe(w.Formulas.pressReward(income, false, 0, false))
				clean(w)
			end
		)
	end)
end
