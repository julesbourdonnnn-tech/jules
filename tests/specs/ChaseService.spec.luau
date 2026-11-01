--!nocheck
-- ChaseService (paquet chase, docs/04 §6, §11.14, §15, §18.2) : tick (acteurs, MoveCheck avec le sol
-- WorldLayout.supportY, Activity.noteMove), créatures (fuite personnelle, Golden, Wild, fuites du Rush,
-- démonstration), captures à l'instant tClient (file, ordre d'arrivée, première arrivée gagne), bonds
-- (recharge, crédit MoveCheck.grant, capture à l'atterrissage), récompenses (Héros + 1 h une fois par
-- jour, bébé du Rush ≤ 0,5 × le plus gros, mutation > ×5 tirée, retours), anti-triche (retours,
-- Unstable, strikes, exclusion), ChaseEvent groupé à 4 Hz, départ (MoveCheck.clear), délais des états,
-- zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- :01:00 d'une heure (vendredi) : Golden à :10:30, Rush à :05:00, MEGA à :20:00, pas de Lune
	local T0 = 1800000000 + 60

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function boot(opts)
		opts = opts or {}
		opts.t0 = opts.t0 or T0
		return Brains.boot(Harness, opts)
	end

	local function chaseEvents(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "ChaseEvent") do
			table.insert(out, args[1])
		end
		return out
	end

	local function spawnsSeen(w, p, kind)
		local out = {}
		for _, payload in chaseEvents(w, p) do
			for _, s in payload.spawns do
				if kind == nil or s.kind == kind then
					table.insert(out, s)
				end
			end
		end
		return out
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- Attraper : le joueur se pose sur la créature (placement serveur : position validée) et envoie Catch
	local function catchNow(w, p, spawn, offset)
		local now = w.Clock.now()
		local target = Brains.creaturePos(w, spawn, now)
		local o = offset or w.V3.zero
		Bots.place(p, Bots.ground(target.X + o.X, target.Z + o.Z))
		w.h:fireServer("ReplicatedStorage.Remotes.Catch", p, spawn.id, now)
		Brains.frames(w, 1)
	end

	local rushProfile = function(w, squishies)
		return Brains.profile(
			w,
			{ rush = true, squishies = squishies or { { s = 2, z = 1000 }, { s = 3, z = 500 } } }
		)
	end

	-- =========================================================================================
	describe("ChaseService › tick et acteurs", function()
		it(
			"acteurs : position validée, canAct, rootOffset, slot ; sol = WorldLayout.supportY ; activité",
			function()
				local grounds = {}
				local w = boot({
					before = function(w)
						local MC = w.h:require("ServerScriptService.Server.Util.MoveCheck")
						local step = MC.step
						MC.step = function(player, pos, dt, now, groundY)
							table.insert(grounds, { pos = pos, ground = groundY })
							return step(player, pos, dt, now, groundY)
						end
					end,
				})
				local a = Brains.join(w, 1)
				Brains.frames(w, 5)
				local actor = w.Chase.actors()[a]
				expect(actor ~= nil).toBe(true)
				expect(actor.slot).toBe(w.Ranch.slotOf(a))
				expect(actor.canAct).toBe(true)
				expect(actor.rootOffset).toBe(0)
				expect((actor.pos - a.Character.HumanoidRootPart.Position).Magnitude < 1e-6).toBe(true)
				expect(#grounds >= 5).toBe(true)
				for _, g in grounds do
					expect(g.ground).toBe(w.WL.supportY(g.pos))
				end
				-- déplacement validé ≥ 4 studs : actif (Activity.noteMove)
				local before = w.Activity.lastActive(a)
				local start = a.Character.HumanoidRootPart.Position
				Bots.setBrain(a, function(p)
					Bots.stepToward(p, start + w.V3.new(10, 0, 0))
				end)
				Brains.frames(w, 10)
				expect(w.Activity.lastActive(a) > before).toBe(true)
				expect(w.Event.isActive(a, w.Clock.now())).toBe(true)
				clean(w)
			end
		)

		it(
			"un seul Heartbeat : chaque image du serveur fait au plus un tick ; tick(now) direct possible",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				local calls = 0
				local tick = w.Chase.tick
				-- compte les ticks par le Heartbeat (la fonction est relue à chaque image)
				w.Chase.tick = function(now)
					calls += 1
					return tick(now)
				end
				w.Clock.advance(0.1)
				w.h:step(0.1)
				expect(calls).toBe(1)
				w.Clock.advance(1)
				w.h:step(1) -- image très en retard : un seul tick (durée bornée)
				expect(calls).toBe(2)
				w.Chase.tick = tick
				w.Chase.tick(w.Clock.now() + 0.1)
				expect(w.Chase.actors()[a] ~= nil).toBe(true)
				clean(w)
			end
		)

		it(
			"une étape du tick en panne est comptée par Diagnostics et n'arrête ni les autres ni les joueurs",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				local Economy = w.Economy
				local stepped = 0
				local step = Economy.step
				Economy.step = function()
					error("panne volontaire")
				end
				local rushStep = w.Rush.step
				w.Rush.step = function(...)
					stepped += 1
					return rushStep(...)
				end
				Brains.frames(w, 3)
				expect(stepped).toBe(3)
				expect(#w.meta.caught >= 3).toBe(true)
				expect(string.find(w.meta.caught[1], "tick:economy", 1, true) ~= nil).toBe(true)
				expect(w.Chase.actors()[a] ~= nil).toBe(true)
				Economy.step = step
				w.Rush.step = rushStep
				table.clear(w.meta.caught)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › fuite personnelle", function()
		it(
			"60 s après l'arrivée, envoyée au seul propriétaire ; 20 s puis la suivante 60 s après la fin",
			function()
				local w = boot()
				local a =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 400 } } }) })
				local b = Brains.join(w, 2)
				Brains.frames(w, 590)
				expect(#Brains.creatures(w, "runaway")).toBe(0)
				Brains.frames(w, 20)
				local list = Brains.creatures(w, "runaway")
				expect(#list >= 1).toBe(true)
				local mine = nil
				for _, s in list do
					if s.ownerSlot == w.Ranch.slotOf(a) then
						mine = s
					end
				end
				expect(mine ~= nil).toBe(true)
				expect(mine.personal).toBe(true)
				expect(mine.path).toBe("hop")
				expect(mine.duration).toBe(w.Balance.Runaway.Duration)
				-- taille : 5 % du plus gros (400 au départ, qui a grandi depuis)
				local _, biggest = w.Squishy.biggest(a)
				expect(math.abs(mine.size - 0.05 * biggest) <= 0.05 * biggest * 0.01).toBe(true)
				-- seul le propriétaire la reçoit
				local seenByB = false
				for _, s in spawnsSeen(w, b, "runaway") do
					if s.id == mine.id then
						seenByB = true
					end
				end
				expect(seenByB).toBe(false)
				local seenByA = false
				for _, s in spawnsSeen(w, a, "runaway") do
					if s.id == mine.id then
						seenByA = true
					end
				end
				expect(seenByA).toBe(true)
				-- personne ne l'attrape : fin à 20 s, la suivante 60 s plus tard
				Brains.frames(w, 205)
				local still = false
				for _, s in Brains.creatures(w, "runaway") do
					if s.id == mine.id then
						still = true
					end
				end
				expect(still).toBe(false)
				Brains.frames(w, 570)
				local again = 0
				for _, s in Brains.creatures(w, "runaway") do
					if s.ownerSlot == w.Ranch.slotOf(a) then
						again += 1
					end
				end
				expect(again).toBe(0)
				Brains.frames(w, 30)
				again = 0
				for _, s in Brains.creatures(w, "runaway") do
					if s.ownerSlot == w.Ranch.slotOf(a) then
						again += 1
					end
				end
				expect(again).toBe(1)
				clean(w)
			end
		)

		it(
			"attrapée à l'instant tClient : bébé donné, Celebrate catch, Caught ; un autre joueur ne peut pas",
			function()
				local w = boot()
				local a =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 400 } } }) })
				local b = Brains.join(w, 2)
				local caught = {}
				w.Signals.Caught:Connect(function(p, info)
					table.insert(caught, { p = p, info = info })
				end)
				Brains.frames(w, 605)
				local mine = Brains.creatures(w, "runaway")[1]
				expect(mine ~= nil).toBe(true)
				if mine.ownerSlot ~= w.Ranch.slotOf(a) then
					mine = Brains.creatures(w, "runaway")[2]
				end
				-- B (pas le propriétaire) : refusé
				catchNow(w, b, mine)
				expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
				-- A : accepté
				local before = count(w.Squishy.records(a))
				catchNow(w, a, mine)
				expect(w.Chase.active()[mine.id]).toBeNil()
				expect(count(w.Squishy.records(a))).toBe(before + 1)
				local cel = Bots.celebrations(a, "catch")
				expect(#cel).toBe(1)
				expect(cel[1].kind).toBe("runaway")
				expect(cel[1].byLeap).toBe(false)
				expect(#caught).toBe(1)
				expect(caught[1].p).toBe(a)
				expect(caught[1].info.kind).toBe("runaway")
				-- fin envoyée au propriétaire
				Brains.frames(w, 3)
				local finished = false
				for _, payload in chaseEvents(w, a) do
					for _, f in payload.finishes do
						if f.id == mine.id and f.reason == "caught" then
							finished = true
						end
					end
				end
				expect(finished).toBe(true)
				clean(w)
			end
		)

		it("hors de portée (7 studs à plat) ou pieds trop hauts (9 studs) : refusée", function()
			local w = boot()
			local a =
				Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 400 } } }) })
			Brains.frames(w, 605)
			local mine = Brains.creatures(w, "runaway")[1]
			catchNow(w, a, mine, w.V3.new(7, 0, 0))
			expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
			-- pieds à 9 studs au-dessus du sol de la créature
			local now = w.Clock.now()
			local c = Brains.creaturePos(w, mine, now)
			Bots.place(a, w.V3.new(c.X, c.Y + 3 + 9, c.Z))
			w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, mine.id, now)
			Brains.frames(w, 1)
			expect(w.Chase.active()[mine.id] ~= nil).toBe(true)
			-- à 6 studs : acceptée (rayon 5 + tolérance 1,5)
			catchNow(w, a, mine, w.V3.new(6, 0, 0))
			expect(w.Chase.active()[mine.id]).toBeNil()
			clean(w)
		end)

		it(
			"en pause pendant un Rush et quand enclos, Dodo et Lettres sont pleins ; Froggy : toutes les 50 s",
			function()
				local w = boot({ t0 = 1800000000 + 300 - 30 })
				local a = Brains.join(w, 1)
				-- Rush de :05 à :06:30 : aucune fuite personnelle pendant le Rush
				Brains.frames(w, 1000)
				for _, s in Brains.creatures(w, "runaway") do
					local rush = w.EventClock.rush(s.t0)
					expect(rush.active).toBe(false)
				end
				-- Froggy complète (dex.fam) : 50 s
				local w2 = boot()
				local froggyIndex = table.find(w2.Species.FamilyOrder, "froggy")
				local prof = Brains.profile(w2, {
					edit = function(d)
						d.dex.fam[froggyIndex] = 1
					end,
				})
				local b = Brains.join(w2, 1, { profile = prof })
				Brains.frames(w2, 605)
				local first = Brains.creatures(w2, "runaway")[1]
				expect(first ~= nil).toBe(true)
				Brains.frames(w2, 200 + 500 + 5)
				local second = Brains.creatures(w2, "runaway")[1]
				expect(second ~= nil).toBe(true)
				expect(math.abs(second.t0 - (first.t0 + 20 + 50)) < 0.25).toBe(true)
				local _ = b
				clean(w)
				clean(w2)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › Golden Wobbler", function()
		it(
			"lâché à :00:30 pour tous ; premier arrivé gagne (Doré), « de près » 60 s ; recharge de 20 min",
			function()
				local w = boot({ t0 = 1800000000 + 20 })
				local a = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { squishies = { { s = 2, z = 1000 } } }) }
				)
				local b = Brains.join(
					w,
					2,
					{ profile = Brains.profile(w, { squishies = { { s = 2, z = 1000 } } }) }
				)
				local c = Brains.join(
					w,
					3,
					{ profile = Brains.profile(w, { squishies = { { s = 2, z = 1000 } } }) }
				)
				local near = {}
				w.Signals.NearCatch:Connect(function(p, kind)
					table.insert(near, { p = p, kind = kind })
				end)
				Brains.frames(w, 110)
				local golden = Brains.creatures(w, "golden")[1]
				expect(golden ~= nil).toBe(true)
				expect(golden.personal).toBe(false)
				expect(golden.t0).toBe(1800000000 + 30)
				-- A et B appuient au même tick : A arrive le premier et gagne ; C est à 20 studs (de près)
				local now = w.Clock.now()
				local pos = Brains.creaturePos(w, golden, now)
				Bots.place(a, Bots.ground(pos.X, pos.Z))
				Bots.place(b, Bots.ground(pos.X + 1, pos.Z))
				Bots.place(c, Bots.ground(pos.X + 20, pos.Z))
				Brains.frames(w, 1)
				now = w.Clock.now()
				pos = Brains.creaturePos(w, golden, now)
				w.h:moveTo(a, Bots.ground(pos.X, pos.Z))
				w.h:moveTo(b, Bots.ground(pos.X + 1, pos.Z))
				Brains.frames(w, 1)
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, golden.id, w.Clock.now())
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", b, golden.id, w.Clock.now())
				Brains.frames(w, 1)
				expect(w.Chase.active()[golden.id]).toBeNil()
				local cel = Bots.celebrations(a, "catch")
				expect(#cel).toBe(1)
				expect(cel[1].kind).toBe("golden")
				expect(cel[1].mutation).toBe(w.Mutations.GOLDEN)
				expect(#Bots.celebrations(b, "catch")).toBe(0)
				local data = w.DS.get(a)
				expect(data.golden.lastWinAt).toBe(w.Clock.unix())
				-- B et C de près (≤ 30 studs) : NearCatch "golden"
				local nearPlayers = {}
				for _, e in near do
					expect(e.kind).toBe("golden")
					nearPlayers[e.p] = true
				end
				expect(nearPlayers[b]).toBe(true)
				expect(nearPlayers[c]).toBe(true)
				expect(nearPlayers[a]).toBeNil()
				-- recharge de 20 min : au Golden suivant (:10:30), A ne peut pas gagner
				Bots.travelTo(1800000000 + 631)
				Brains.frames(w, 2)
				local g2 = Brains.creatures(w, "golden")[1]
				expect(g2 ~= nil).toBe(true)
				local p2 = Brains.creaturePos(w, g2, w.Clock.now())
				Bots.place(a, Bots.ground(p2.X, p2.Z))
				w.h:fireServer("ReplicatedStorage.Remotes.Catch", a, g2.id, w.Clock.now())
				Brains.frames(w, 1)
				expect(w.Chase.active()[g2.id] ~= nil).toBe(true)
				expect(table.find(Bots.feedbackKeys(a), "feedback.letOthersWin") ~= nil).toBe(true)
				clean(w)
			end
		)

		it(
			"personne ne l'attrape : 30 s de revenu aux joueurs de près ; interrupteur coupé : aucun Golden",
			function()
				local w = boot({ t0 = 1800000000 + 20 })
				local a = Brains.join(
					w,
					1,
					{ profile = Brains.profile(w, { squishies = { { s = 2, z = 1000 } } }) }
				)
				Brains.frames(w, 110)
				local golden = Brains.creatures(w, "golden")[1]
				local endPos = Brains.creaturePos(w, golden, golden.t0 + golden.duration)
				Bots.place(a, Bots.ground(endPos.X + 5, endPos.Z))
				local coins = w.Economy.coins(a)
				Bots.travelTo(golden.t0 + golden.duration - 0.05)
				Brains.frames(w, 3)
				expect(w.Chase.active()[golden.id]).toBeNil()
				expect(w.Economy.coins(a) > coins).toBe(true)
				local w2 = boot({ t0 = 1800000000 + 20 })
				w2.Features.set("GoldenWobbler", false)
				Brains.join(w2, 1)
				Brains.frames(w2, 110)
				expect(#Brains.creatures(w2, "golden")).toBe(0)
				clean(w)
				clean(w2)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › Wild Wobblers", function()
		it(
			"au début du Rush : 3 + 2 × max(0, 6 − N) partagés (un tiers d'abord, puis toutes les 15 s), un personnel à +15 s",
			function()
				local w = boot({ t0 = 1800000000 + 300 - 2 })
				local a = Brains.join(w, 1)
				local b = Brains.join(w, 2)
				Brains.frames(w, 25)
				-- N = 2 : 3 + 2 × 4 = 11 partagés ; un tiers (4) au début
				local shared = Brains.creatures(w, "wild")
				expect(#shared).toBe(4)
				Brains.frames(w, 150)
				local personal = Brains.creatures(w, "wildPersonal")
				expect(#personal).toBe(2)
				for _, s in personal do
					expect(s.personal).toBe(true)
				end
				Brains.frames(w, 300)
				-- toutes les vagues sorties pendant le Rush : 11 au total
				local ids = {}
				for _, payload in chaseEvents(w, a) do
					for _, s in payload.spawns do
						if s.kind == "wild" then
							ids[s.id .. ":" .. s.t0] = true
						end
					end
				end
				expect(count(ids)).toBe(11)
				local _ = b
				clean(w)
			end
		)

		it(
			"2 partagés au plus par joueur et par Rush ; +1 Fame du Rush par capture ; Cozy compris",
			function()
				local w = boot({ t0 = 1800000000 + 300 - 2 })
				local a =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 100 } } }) })
				Brains.frames(w, 25)
				local shared = Brains.creatures(w, "wild")
				expect(#shared >= 3).toBe(true)
				local fame = w.DS.get(a).fame
				for i = 1, 3 do
					catchNow(w, a, shared[i])
				end
				local remaining = 0
				for i = 1, 3 do
					if w.Chase.active()[shared[i].id] then
						remaining += 1
					end
				end
				expect(remaining).toBe(1)
				expect(w.DS.get(a).fame).toBe(fame + 2)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › fuites du Rush", function()
		local function rushWorld()
			local w = boot({ t0 = 1800000000 + 300 + 1 })
			local owner = Brains.join(w, 1, { profile = rushProfile(w) })
			local booper = Brains.join(w, 2, { profile = rushProfile(w) })
			local other = Brains.join(w, 3, { profile = rushProfile(w, { { s = 2, z = 50 } }) })
			local cozy = Brains.join(w, 4, { profile = Brains.profile(w, { rush = false }) })
			Brains.frames(w, 2)
			return w, owner, booper, other, cozy
		end

		local function boop(w, booper, owner, uid)
			w.Signals.Booped:Fire(booper, owner, uid, 0)
			Brains.frames(w, 1)
			for _, s in Brains.creatures(w, "escape") do
				if s.uid == uid then
					return s
				end
			end
			return nil
		end

		it(
			"Booped → fuite visible par tous ; setEscaping ; le boopeur ne peut pas l'attraper avant 6 s ; Cozy jamais",
			function()
				local w, owner, booper, other, cozy = rushWorld()
				local esc = boop(w, booper, owner, "1")
				expect(esc ~= nil).toBe(true)
				expect(esc.personal).toBe(false)
				expect(esc.ownerSlot).toBe(w.Ranch.slotOf(owner))
				expect(esc.booperSlot).toBe(w.Ranch.slotOf(booper))
				expect(esc.duration).toBe(w.Events.Rush.EscapeDuration)
				expect(w.Squishy.anyEscaping(owner)).toBe("1")
				expect(w.Chase.isEscaping(owner, "1")).toBe(true)
				catchNow(w, booper, esc)
				expect(w.Chase.active()[esc.id] ~= nil).toBe(true)
				catchNow(w, cozy, esc)
				expect(w.Chase.active()[esc.id] ~= nil).toBe(true)
				local _ = other
				clean(w)
			end
		)

		it(
			"Héros : + 1 h de croissance une fois par jour, 120 s de revenu, +2 Fame ; EscapeEnded « hero »",
			function()
				local w, owner, booper = rushWorld()
				local ended = {}
				w.Signals.EscapeEnded:Connect(function(o, uid, outcome, catcher)
					table.insert(ended, { o = o, uid = uid, outcome = outcome, catcher = catcher })
				end)
				local g = w.Economy.gNoBoost(owner)
				local z0 = w.Squishy.get(owner, "1").z
				local fame = w.DS.get(owner).fame
				local coins = w.Economy.coins(owner)
				local esc = boop(w, booper, owner, "1")
				catchNow(w, owner, esc, w.V3.new(8, 0, 0)) -- rayon du propriétaire : 8 + 1,5
				expect(w.Chase.active()[esc.id]).toBeNil()
				expect(math.abs(w.Squishy.get(owner, "1").z - (z0 + g * 3600)) < 1e-6 * (z0 + g * 3600)).toBe(
					true
				)
				expect(w.DS.get(owner).fame).toBe(fame + 2)
				expect(w.Economy.coins(owner) > coins).toBe(true)
				expect(#ended).toBe(1)
				expect(ended[1].outcome).toBe("hero")
				expect(w.Squishy.anyEscaping(owner)).toBeNil()
				local cel = Bots.celebrations(owner, "catch")
				expect(cel[#cel].hero).toBe(true)
				-- deuxième Héros le même jour : pas de croissance en plus
				local z1 = w.Squishy.get(owner, "1").z
				Brains.frames(w, 210)
				local esc2 = boop(w, booper, owner, "1")
				catchNow(w, owner, esc2)
				expect(w.Squishy.get(owner, "1").z).toBe(z1)
				clean(w)
			end
		)

		it(
			"un autre joueur Rush : bébé ≤ 0,5 × son plus gros, plafond rushBabies ; propriétaire +1 Fame, ownerReturn",
			function()
				local w, owner, booper, other = rushWorld()
				local esc = boop(w, booper, owner, "1")
				local before = count(w.Squishy.records(other))
				local fame = w.DS.get(owner).fame
				catchNow(w, other, esc)
				expect(w.Chase.active()[esc.id]).toBeNil()
				expect(count(w.Squishy.records(other))).toBe(before + 1)
				local babyUid = Bots.celebrations(other, "catch")[1].uid
				local baby = w.Squishy.get(other, babyUid)
				expect(baby.s).toBe(2)
				-- min(10 % de l'original ≈ 100, 0,5 × son plus gros ≈ 25) : jamais plus de 0,5 × le plus gros
				local _, biggest = w.Squishy.biggest(other)
				expect(baby.z <= 0.5 * biggest + 1e-9).toBe(true)
				expect(baby.z >= 24 and baby.z <= 26).toBe(true)
				expect(w.DS.get(owner).fame).toBe(fame + 1)
				local ret = Bots.celebrations(owner, "ownerReturn")
				expect(#ret).toBe(1)
				expect(ret[1].catcherId).toBe(other.UserId)
				expect(ret[1].firstBoop).toBe(true)
				-- plafond du jour atteint : 60 s de revenu à la place du bébé
				w.DS.get(other).caps.rushBabies = w.Balance.Caps.rushBabies
				w.DS.get(other).caps.day = w.Clock.day()
				Brains.frames(w, 210)
				local esc2 = boop(w, booper, owner, "2")
				local n = count(w.Squishy.records(other))
				catchNow(w, other, esc2)
				expect(w.Chase.active()[esc2.id]).toBeNil()
				expect(count(w.Squishy.records(other))).toBe(n)
				clean(w)
			end
		)

		it("mutation de l'original > ×5 (Galaxie) : jamais copiée, tirée", function()
			local w = boot({ t0 = 1800000000 + 301 })
			local owner = Brains.join(w, 1, { profile = rushProfile(w, { { s = 2, m = 5, z = 1000 } }) })
			local booper = Brains.join(w, 2, { profile = rushProfile(w) })
			local other = Brains.join(w, 3, { profile = rushProfile(w, { { s = 2, z = 5000 } }) })
			Brains.frames(w, 2)
			local galaxy = w.Mutations.ById[5]
			expect(galaxy.mult > w.Balance.Babies.RushMutationMaxMult).toBe(true)
			local esc = boop(w, booper, owner, "1")
			catchNow(w, other, esc)
			local babyUid = Bots.celebrations(other, "catch")[1].uid
			-- la graine de ce test ne tire pas la Galaxie : la mutation n'est jamais recopiée d'office
			expect(w.Squishy.get(other, babyUid).m ~= 5).toBe(true)
			clean(w)
		end)

		it(
			"personne ne l'attrape : rentre à 25 s avec + 30 min de croissance (une fois par jour)",
			function()
				local w, owner, booper = rushWorld()
				local g = w.Economy.gNoBoost(owner)
				local z0 = w.Squishy.get(owner, "1").z
				local esc = boop(w, booper, owner, "1")
				Brains.frames(w, 252)
				expect(w.Chase.active()[esc.id]).toBeNil()
				expect(math.abs(w.Squishy.get(owner, "1").z - (z0 + g * 1800)) < 1e-6 * z0).toBe(true)
				expect(#Bots.celebrations(owner, "returnedBigger")).toBe(1)
				expect(w.Squishy.anyEscaping(owner)).toBeNil()
				clean(w)
			end
		)

		it(
			"propriétaire passé en Cozy ou parti : retour immédiat sans bonus ; boopeur parti : la fuite continue",
			function()
				local w, owner, booper, other = rushWorld()
				local ended = {}
				w.Signals.EscapeEnded:Connect(function(o, uid, outcome)
					table.insert(ended, outcome)
				end)
				local esc = boop(w, booper, owner, "1")
				local fame = w.DS.get(owner).fame
				w.Signals.ModeChanged:Fire(owner, false)
				Brains.frames(w, 1)
				expect(w.Chase.active()[esc.id]).toBeNil()
				expect(ended[1]).toBe("cozy")
				expect(w.DS.get(owner).fame).toBe(fame)
				local esc2 = boop(w, booper, other, "1")
				Bots.leave(booper)
				Brains.frames(w, 2)
				expect(w.Chase.active()[esc2.id] ~= nil).toBe(true)
				Bots.leave(other)
				Brains.frames(w, 2)
				expect(w.Chase.active()[esc2.id]).toBeNil()
				expect(ended[#ended]).toBe("left")
				clean(w)
			end
		)

		it("joueurs Rush à ≤ 30 studs d'une capture : 20 s de revenu et NearCatch « rush »", function()
			local w, owner, booper, other = rushWorld()
			local near = {}
			w.Signals.NearCatch:Connect(function(p, kind)
				table.insert(near, { p = p, kind = kind })
			end)
			local esc = boop(w, booper, owner, "1")
			Brains.frames(w, 61)
			local now = w.Clock.now()
			local pos = Brains.creaturePos(w, esc, now)
			Bots.place(booper, Bots.ground(pos.X + 15, pos.Z))
			catchNow(w, other, esc)
			expect(w.Chase.active()[esc.id]).toBeNil()
			local found = false
			for _, e in near do
				if e.p == booper and e.kind == "rush" then
					found = true
				end
			end
			expect(found).toBe(true)
			clean(w)
		end)
	end)

	-- =========================================================================================
	describe("ChaseService › bond", function()
		it(
			"crédit accordé, recharge de 4 s (horloge du serveur), refusé en portant ou sans canAct, direction bornée",
			function()
				local w = boot()
				local a =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 100 } } }) })
				Brains.frames(w, 5)
				local grants = 0
				local grant = w.MC.grant
				w.MC.grant = function(...)
					local ok = grant(...)
					if ok then
						grants += 1
					end
					return ok
				end
				w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 0, 1, w.Clock.now())
				expect(grants).toBe(1)
				expect(w.Chase.leapCooldownLeft(a, w.Clock.now())).toBe(4)
				w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 0, 1, w.Clock.now())
				expect(grants).toBe(1)
				Brains.frames(w, 41)
				-- direction hors bornes (norme 3) : refusée
				w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 3, 0, w.Clock.now())
				expect(grants).toBe(1)
				-- en portant : refusé
				w.h:fireServer("ReplicatedStorage.Remotes.PickUp", a, "1")
				if w.Squishy.carried(a) ~= nil then
					w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 1, 0, w.Clock.now())
					expect(grants).toBe(1)
					w.h:fireServer("ReplicatedStorage.Remotes.PutDown", a)
				end
				w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, 1, 0, w.Clock.now())
				expect(grants).toBe(2)
				w.MC.grant = grant
				clean(w)
			end
		)

		it(
			"capture à l'atterrissage (tClient + 0,35 s) au point de LeapRules.landing, sans exiger canAct à l'arrivée",
			function()
				local w = boot()
				local a =
					Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 400 } } }) })
				Brains.frames(w, 605)
				local mine = Brains.creatures(w, "runaway")[1]
				expect(mine ~= nil).toBe(true)
				-- se poser à 12 studs de la position future de la créature (atterrissage dans 0,35 s)
				local now = w.Clock.now()
				local future = Brains.creaturePos(w, mine, now + 0.35)
				local from = Bots.ground(future.X - 12, future.Z)
				Bots.place(a, from)
				Brains.frames(w, 1)
				now = w.Clock.now()
				future = Brains.creaturePos(w, mine, now + 0.35)
				local root = a.Character.HumanoidRootPart.Position
				local d = w.V3.new(future.X - root.X, 0, future.Z - root.Z)
				w.h:fireServer("ReplicatedStorage.Remotes.Leap", a, d.Unit.X, d.Unit.Z, now)
				Brains.frames(w, 5)
				expect(w.Chase.active()[mine.id]).toBeNil()
				local cel = Bots.celebrations(a, "catch")
				expect(#cel).toBe(1)
				expect(cel[1].byLeap).toBe(true)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › anti-triche", function()
		it(
			"téléportations : retour (PivotTo), Unstable 3 s, flags.strikes, MoveViolation ; 10 retours en 10 min → exclusion jusqu'à la fin de la semaine suivante",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				local violations = 0
				w.Signals.MoveViolation:Connect(function()
					violations += 1
				end)
				Brains.frames(w, 40) -- exemption de l'apparition terminée
				local home = a.Character.HumanoidRootPart.Position
				local rewinds = 0
				for _ = 1, 10 do
					for _ = 1, 3 do
						w.h:moveTo(a, home + w.V3.new(80, 0, 0))
						Brains.frames(w, 1)
					end
					if (a.Character.HumanoidRootPart.Position - home).Magnitude < 1 then
						rewinds += 1
					end
					expect(a:GetAttribute("Unstable")).toBe(true)
					Brains.frames(w, 32) -- restriction de 3 s finie
					expect(a:GetAttribute("Unstable")).toBe(false)
				end
				expect(rewinds).toBe(10)
				expect(violations).toBe(10)
				local flags = w.DS.get(a).flags
				expect(flags.strikes).toBe(10)
				local expected = w.Clock.unix() + w.Clock.untilNextWeek() + 7 * 86400
				expect(math.abs(flags.lbBanUntil - expected) <= 400).toBe(true)
				expect(flags.lbBanned).toBe(false)
				clean(w)
			end
		)

		it(
			"départ : MoveCheck.clear (aucune trace en mémoire), fuites rentrées, file des captures vidée",
			function()
				local w = boot()
				local a = Brains.join(w, 1)
				Brains.frames(w, 5)
				expect(w.MC.lastValid(a) ~= nil).toBe(true)
				w.MC.setRootOffset(a, 4, 8.6)
				Bots.leave(a)
				Brains.frames(w, 2)
				expect(w.MC.lastValid(a)).toBeNil()
				expect(w.MC.rootOffset(a)).toBe(0)
				expect(w.MC.positionAt(a, w.Clock.now())).toBeNil()
				expect(w.Chase.actors()[a]).toBeNil()
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › diffusion et arrivée", function()
		it(
			"ChaseEvent groupé à 4 Hz ; arrivée en cours : créatures actives envoyées une fois (personnelles au seul concerné)",
			function()
				local w = boot({ t0 = 1800000000 + 300 - 2 })
				local a = Brains.join(w, 1)
				Brains.frames(w, 40)
				local sends = #w.h:sentTo(a, "ChaseEvent")
				-- 4 s : au plus 16 envois
				expect(sends <= 17).toBe(true)
				local b = Brains.join(w, 2)
				local first = w.h:sentTo(b, "ChaseEvent")[1]
				expect(first ~= nil).toBe(true)
				local wild = 0
				for _, s in first[1].spawns do
					if s.kind == "wild" then
						wild += 1
					end
					expect(s.personal == false or s.ownerSlot == w.Ranch.slotOf(b)).toBe(true)
				end
				expect(wild >= 1).toBe(true)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › démonstration de Big Plop", function()
		it(
			"à demoAt (jeu cumulé) : 20 s, 8 studs/s, personnelle ; attrapée → bébé Plop (≥ 10) ; jamais rejouée",
			function()
				local w = boot()
				local prof = Brains.profile(w, {
					squishies = { { s = 1, z = 50, bf = 1 } },
					edit = function(d)
						d.onboarding = { step = 8, done = false, demoDone = false }
					end,
				})
				local a = Brains.join(w, 1, { profile = prof })
				w.meta.scripts[1] = { active = true, demoAt = 180, runawayPaused = true, vatScripted = false }
				w.meta.playSeconds[1] = 170
				Brains.frames(w, 5)
				expect(#Brains.creatures(w, "demo")).toBe(0)
				w.meta.playSeconds[1] = 181
				Brains.frames(w, 2)
				local demo = Brains.creatures(w, "demo")[1]
				expect(demo ~= nil).toBe(true)
				expect(demo.personal).toBe(true)
				expect(demo.duration).toBe(20)
				catchNow(w, a, demo)
				expect(w.Chase.active()[demo.id]).toBeNil()
				local babyUid = Bots.celebrations(a, "catch")[1].uid
				local baby = w.Squishy.get(a, babyUid)
				expect(baby.s).toBe(w.Species.PLOP)
				expect(baby.z).toBe(10)
				Brains.frames(w, 300)
				expect(#Brains.creatures(w, "demo")).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("ChaseService › délais des états", function()
		it(
			"10 min de jeu avec Rush, Golden, fuites, bonds : aucun état ouvert au-delà de son délai",
			function()
				local w = boot({ t0 = 1800000000 + 20 })
				local players = {}
				for i = 1, 4 do
					table.insert(
						players,
						Brains.join(
							w,
							i,
							{ profile = rushProfile(w, { { s = 2, z = 500 }, { s = 3, z = 300 } }) }
						)
					)
				end
				for i, p in players do
					Bots.setBrain(p, Brains.player(w, i))
				end
				local worst = {}
				Bots.use(w)
				for _ = 1, 6000 do
					Bots.frame(Bots.brains)
					for _, line in Brains.expiredStates(w, w.Clock.now()) do
						table.insert(worst, line)
					end
					if #worst > 0 then
						break
					end
				end
				expect(table.concat(worst, "\n")).toBe("")
				clean(w)
			end
		)
	end)
end
