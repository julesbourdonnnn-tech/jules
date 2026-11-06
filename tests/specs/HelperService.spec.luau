--!nocheck
-- HelperService (lot A3 ; GDD v2.0 §4.28, docs/04 §27.7, §27.10, §27.13 N23, §27.14) : les Plopettes
-- côté serveur, stépées par le tick de 10 Hz de ChaseService.
--   * interrupteur coupé (lancement) : rien (aucune pression, aucun HelperPress, aucun état suivi) ;
--   * nombre : Record R (Pip 2, Pop 4, Pim 6, Pom 8, Puff 12) + Plume (Atelier) ; profil v1 : aucune ;
--   * aucune récompense avant tPress ; récompense = pressReward(revenu, PERFECT non, série 0, Kitty,
--     Gants) par EconomyService (source « Helper ») ; jamais Signals.Pressed (jauge, objectifs) ;
--   * règle des 12 studs au choix ET à tPress (position validée) ; égalité : la pression du joueur
--     gagne ; squishy vendu, porté, en attente ou à la clôture : jamais pressé ;
--   * sieste après 5 min sans intention ACCEPTÉE (Activity.lastIntent, N23) : un stick calé ne la
--     retarde pas ; réveil à la première intention acceptée ;
--   * pauses : file et spectacle du Grand Splorch, animation du Petit Splorch, BOOP RUSH à sa clôture,
--     fuite, pause(player) ; reprise ;
--   * HelperPress : UN message par tick et par ranch (au propriétaire et aux voisins proches) ;
--   * départ et retour, interrupteur coupé puis rouvert en direct : aucune fuite, aucune cible périmée,
--     aucune récompense après ;
--   * coût : < 0,5 ms par tick à 16 joueurs × 6 Plopettes (os.clock réel, horloge du jeu figée).
-- Interrupteur Helpers ouvert DANS le test (Features.set) ; SchemaV2 (figé) ouvert dans le harnais
-- avant le premier require du schéma (recette de DataChaos).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~4 min
	local L = "ReplicatedStorage.Shared."
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : v1 (serveur v1), off (Helpers coupé), flags (autres interrupteurs ouverts), t0
	local function boot(opts)
		opts = opts or {}
		local w = Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = opts.t0 or T0 })
		w.Helper = w.h:require(S .. "HelperService")
		w.Upgrades = w.h:require(L .. "Config.Upgrades")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.QuestRules = w.h:require(L .. "Logic.QuestRules")
		w.Rules = w.h:require("ServerScriptService.Server.Helpers.Rules")
		w.Places = w.h:require("ServerScriptService.Server.Ranch.Places")
		if not opts.off then
			assert(w.Features.set("Helpers", true))
		end
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		w.pressed = {}
		w.Signals.HelperPressed:Connect(function(p, helper, uid, coins)
			-- récompense attendue, calculée au même instant (revenu, Kitty, Gants du propriétaire)
			local data = w.DS.get(p)
			local gloves = w.Economy.pressBonus(p)
			local expected = w.Formulas.pressReward(
				w.Economy.squishyIncome(p, uid),
				false,
				0,
				w.QuestRules.familyEarned(data.dex, "kitty"),
				gloves,
				nil
			) * w.Balance.Helpers.RewardShare
			table.insert(w.pressed, {
				p = p,
				helper = helper,
				uid = uid,
				coins = coins,
				expected = expected,
				t = w.Clock.now(),
			})
		end)
		w.playerPresses = 0
		w.Signals.Pressed:Connect(function()
			w.playerPresses += 1
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- n squishies d'enclos (places 1 à n), même espèce : revenu croissant avec l'uid
	local function pen(n)
		local out = {}
		for k = 1, n or 8 do
			table.insert(out, { s = 2, z = 100 * k })
		end
		return out
	end

	-- profil v2 : Record R 12 (5 Plopettes) + Plume (6e) par défaut
	local function owner(w, opts)
		opts = opts or {}
		return Brains.profile(w, {
			R = opts.R or 12,
			squishies = opts.squishies or pen(opts.n),
			rush = opts.rush,
			edit = function(d)
				d.bestR = opts.bestR or 12
				if opts.plume ~= false and type(d.atelier) == "table" then
					d.atelier[w.Upgrades.WorkshopIndex.plume] = 1
				end
				if opts.school then
					d.tiles.school = opts.school
				end
				if opts.big then
					-- le dernier squishy atteint l'objectif du Grand Splorch de r
					d.squishies[tostring(opts.n or 8)].z = w.Prestige.target(opts.R or 12) * 1.5
				end
				if opts.edit then
					opts.edit(d)
				end
			end,
		})
	end

	-- position monde (au sol) du point local (x, z) du ranch de p
	local function at(w, p, x, z)
		return Brains.atRanch(w, p, x, z)
	end

	-- centre (monde) de la place d'un squishy
	local function placeOf(w, p, uid)
		return w.Squishy.placeOf(p, uid)
	end

	-- joueur placé à `d` studs à plat de la place de `uid` (vers +Z local)
	local function nearPlace(w, p, uid, d)
		local c = w.WL.toLocal(w.Ranch.slotOf(p), placeOf(w, p, uid))
		return at(w, p, c.X, c.Z + d)
	end

	local function wake(w, p)
		w.Activity.note(p, w.Clock.now())
	end

	-- monde : propriétaire (userId 1) loin de son enclos (Z = 60 local), réveillé
	local function world(opts)
		opts = opts or {}
		local w = boot(opts)
		local p = Brains.join(w, 1, { profile = (opts.profile or owner)(w, opts) })
		Bots.place(p, at(w, p, 0, 60))
		Brains.frames(w, 2)
		if opts.awake ~= false then
			wake(w, p)
		end
		return w, p
	end

	local function messages(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "HelperPress") do
			table.insert(out, args[1])
		end
		return out
	end

	local function pressesOf(w, p)
		local out = {}
		for _, e in w.pressed do
			if e.p == p then
				table.insert(out, e)
			end
		end
		return out
	end

	local function coins(w, p)
		return w.DS.get(p).coins
	end

	-- joue n ticks en notant l'heure (Clock.now() du tick) de chaque nouveau message HelperPress
	local function framesNoting(w, p, n, out, brain)
		for _ = 1, n do
			local before = #messages(w, p)
			Brains.frames(w, 1, brain)
			local msgs = messages(w, p)
			for i = before + 1, #msgs do
				table.insert(out, { t = w.Clock.now(), msg = msgs[i] })
			end
		end
		return out
	end

	-- avance jusqu'à ce que `cond()` soit vrai (au plus n ticks) ; rend le nombre de ticks joués
	local function until_(w, n, cond)
		for i = 1, n do
			if cond() then
				return i - 1
			end
			Brains.frames(w, 1)
		end
		return n
	end

	describe("HelperService › interrupteur coupé (lancement) : le jeu de base tel quel", function()
		it(
			"Helpers coupé : aucune pression, aucun HelperPress, aucun état suivi, step sans coût",
			function()
				local w, p = world({ off = true })
				local before = coins(w, p)
				Brains.frames(w, 600)
				expect(#w.pressed).toBe(0)
				expect(#messages(w, p)).toBe(0)
				expect(Bots.countAll("HelperPress")).toBe(0)
				expect(coins(w, p)).toBe(before)
				expect(w.Helper.state(p)).toBe("idle")
				local c = w.Helper.counters()
				expect({ c.Owners, c.Chosen, c.Pressed, c.Abandoned }).toEqual({ 0, 0, 0, 0 })
				-- coût de step coupé : un test d'interrupteur, rien d'autre
				local t0 = os.clock()
				for _ = 1, 10000 do
					w.Helper.step(w.Clock.now(), w.Chase.actors())
				end
				expect((os.clock() - t0) / 10000 * 1000 < 0.01).toBe(true)
				clean(w)
			end
		)

		it("profil v1 (serveur v1) : aucune Plopette même interrupteur ouvert", function()
			local w = boot({ v1 = true })
			local d = Brains.profile(w, { R = 12, squishies = pen() })
			local p = Brains.join(w, 1, { profile = d })
			Bots.place(p, at(w, p, 0, 60))
			wake(w, p)
			Brains.frames(w, 300)
			expect(#w.pressed).toBe(0)
			expect(#messages(w, p)).toBe(0)
			expect(w.Helper.counters().Owners).toBe(0)
			clean(w)
		end)
	end)

	describe("HelperService › nombre de Plopettes (Record R et Plume)", function()
		it("Record R 0, 2, 4, 8, 12 et Plume : 0, 1, 2, 4, 5, 6 ; numéros 1 … 5 puis 6", function()
			for _, case in
				{
					{ best = 0, plume = false, n = 0 },
					{ best = 2, plume = false, n = 1 },
					{ best = 4, plume = false, n = 2 },
					{ best = 8, plume = false, n = 4 },
					{ best = 12, plume = false, n = 5 },
					{ best = 12, plume = true, n = 6 },
				}
			do
				local w, p = world({ R = math.min(case.best, 4), bestR = case.best, plume = case.plume })
				Brains.frames(w, 2)
				local list = w.Helper.helpers(p)
				expect({ best = case.best, n = #list }).toEqual({ best = case.best, n = case.n })
				for k, h in list do
					local want = if k <= math.min(case.n, 5) and not (case.plume and k == 6) then k else 6
					expect(h.index).toBe(want)
				end
				clean(w)
			end
		end)

		it("École : intervalle 12 − 0,3 × niveau (12 s sans École, 6 s à l'École 20)", function()
			local w = boot()
			expect(w.Rules.interval(0)).toBe(12)
			expect(math.abs(w.Rules.interval(10) - 9) < 1e-9).toBe(true)
			expect(math.abs(w.Rules.interval(20) - 6) < 1e-9).toBe(true)
			-- trajet : fonction pure des deux positions, 3 s au plus
			expect(w.Rules.travel(0, 0, 0, 1000)).toBe(3)
			expect(w.Rules.travel(0, 0, 0, 0)).toBe(w.Rules.MIN_TRAVEL)
			expect(w.Rules.travel(0 / 0, 0, 1, 1)).toBe(3)
		end)

		it(
			"rythme : une pression par Plopette toutes les 12 s sans École, toutes les 6 s à l'École 20",
			function()
				for _, case in { { school = 0, every = 12 }, { school = 20, every = 6 } } do
					-- Pip seule, 6 squishies : toujours une cible prête
					local w, p = world({ school = case.school, plume = false, bestR = 2, R = 2, n = 6 })
					local sends = framesNoting(w, p, 600, {}) -- 60 s
					expect(#sends >= 4).toBe(true)
					for i = 2, #sends do
						local gap = sends[i].t - sends[i - 1].t
						expect({ school = case.school, gap = math.abs(gap - case.every) < 0.15 }).toEqual({
							school = case.school,
							gap = true,
						})
					end
					local list = pressesOf(w, p)
					expect(math.abs(#list - 60 / case.every) <= 1).toBe(true)
					clean(w)
				end
			end
		)
	end)

	describe("HelperService › cible, tPress et récompense", function()
		it(
			"aucune récompense avant tPress ; à tPress, pressReward sans PERFECT ni série × Gants",
			function()
				local w, p = world({
					flags = { "Gloves" },
					edit = function(d)
						d.tiles.gloves = 10
					end,
				})
				local before = coins(w, p)
				until_(w, 50, function()
					return #messages(w, p) > 0
				end)
				local msg = messages(w, p)[1]
				expect(msg.ownerId).toBe(p.UserId)
				expect(#msg.presses).toBe(6) -- six Plopettes, un seul message
				local sentAt = w.Clock.now()
				local firstT = math.huge
				for _, e in msg.presses do
					expect(e.tPress > sentAt - 0.11).toBe(true)
					expect(e.tPress - sentAt <= w.Balance.Helpers.MaxTravel + 0.11).toBe(true)
					firstT = math.min(firstT, e.tPress)
				end
				-- jusqu'à la veille de tPress : rien
				while w.Clock.now() + 0.1 < firstT - 1e-6 do
					Brains.frames(w, 1)
					expect(coins(w, p)).toBe(before)
					expect(#w.pressed).toBe(0)
				end
				Brains.frames(w, 5)
				local list = pressesOf(w, p)
				expect(#list).toBe(6)
				local total = 0
				for _, e in list do
					expect(e.t >= firstT - 1e-6).toBe(true)
					expect(e.coins).toBe(e.expected)
					expect(e.coins > 0).toBe(true)
					total += e.coins
				end
				expect(coins(w, p)).toBe(before + total)
				-- les Gants comptent (même chemin que la pression : pressBonus du propriétaire)
				local gloves = w.Economy.pressBonus(p)
				expect(gloves).toBe(10)
				-- jamais une pression du joueur (jauge, objectifs, classements)
				expect(w.playerPresses).toBe(0)
				clean(w)
			end
		)

		it("cibles : les plus gros revenus d'abord, jamais deux Plopettes sur le même squishy", function()
			local w, p = world({ n = 8 })
			until_(w, 50, function()
				return #messages(w, p) > 0
			end)
			local msg = messages(w, p)[1]
			local seen = {}
			local incomes = {}
			for _, e in msg.presses do
				expect(seen[e.uid]).toBeNil()
				seen[e.uid] = true
				table.insert(incomes, w.Economy.squishyIncome(p, e.uid))
			end
			-- les 2 squishies laissés ont un revenu ≤ à tous ceux choisis
			for _, uid in { "1", "2", "3", "4", "5", "6", "7", "8" } do
				if not seen[uid] then
					for _, inc in incomes do
						expect(w.Economy.squishyIncome(p, uid) <= inc).toBe(true)
					end
				end
			end
			clean(w)
		end)

		it("règle des 12 studs au choix : à 11,95 studs jamais visé, à 12,05 visé", function()
			local w, p = world({ n = 8, awake = false })
			-- le squishy 8 a le plus gros revenu : visé s'il est permis
			Bots.place(p, nearPlace(w, p, "8", 11.95))
			Brains.frames(w, 2)
			wake(w, p)
			Brains.frames(w, 40)
			for _, m in messages(w, p) do
				for _, e in m.presses do
					expect(e.uid ~= "8").toBe(true)
				end
			end
			local w2, p2 = world({ n = 8, awake = false })
			Bots.place(p2, nearPlace(w2, p2, "8", 12.05))
			Brains.frames(w2, 2)
			wake(w2, p2)
			Brains.frames(w2, 40)
			local targeted = false
			for _, m in messages(w2, p2) do
				for _, e in m.presses do
					targeted = targeted or e.uid == "8"
				end
			end
			expect(targeted).toBe(true)
			Brains.frames(w2, 40)
			local got = false
			for _, e in pressesOf(w2, p2) do
				got = got or e.uid == "8"
			end
			expect(got).toBe(true)
			clean(w)
			clean(w2)
		end)

		it(
			"règle des 12 studs revérifiée à tPress : le joueur arrive près de la cible → abandon, rien",
			function()
				local w, p = world({ n = 8 })
				until_(w, 50, function()
					return #messages(w, p) > 0
				end)
				local msg = messages(w, p)[1]
				local target = msg.presses[1].uid
				-- le joueur rejoint la place de la cible (placement validé) avant tPress
				local pos = nearPlace(w, p, target, 6)
				Bots.place(p, pos)
				local allowed = {}
				local nAllowed = 0
				for _, e in msg.presses do
					local c = placeOf(w, p, e.uid)
					if w.Rules.farEnough(pos.X, pos.Z, c.X, c.Z) then
						allowed[e.uid] = true
						nAllowed += 1
					end
				end
				expect(allowed[target]).toBeNil()
				Brains.frames(w, 40)
				local got = 0
				for _, e in pressesOf(w, p) do
					expect(allowed[e.uid]).toBe(true)
					got += 1
				end
				expect(got).toBe(nAllowed)
				expect(w.Helper.counters().Abandoned).toBe(#msg.presses - nAllowed)
				clean(w)
			end
		)

		it("égalité : la pression du joueur au tick de tPress gagne, la Plopette n'a rien", function()
			local w, p = world({ n = 8 })
			until_(w, 50, function()
				return #messages(w, p) > 0
			end)
			local e1 = messages(w, p)[1].presses[1]
			-- jusqu'au tick qui résout tPress (exclu)
			while w.Clock.now() + 0.1 < e1.tPress - 1e-6 do
				Brains.frames(w, 1)
			end
			-- même instant serveur : le joueur est là (placement validé) et presse le premier
			Bots.place(p, nearPlace(w, p, e1.uid, 3))
			local before = coins(w, p)
			w.h:fireServer(R .. "Press", p, e1.uid, w.Clock.now())
			expect(w.playerPresses).toBe(1)
			expect(coins(w, p) > before).toBe(true)
			-- puis il repart loin : seule la recharge posée par SA pression fait abandonner la Plopette
			Bots.place(p, at(w, p, 0, 60))
			Brains.frames(w, 30)
			for _, e in pressesOf(w, p) do
				expect(e.uid ~= e1.uid).toBe(true)
			end
			clean(w)
		end)

		it(
			"squishy pressé par le joueur : prêt depuis 3 s exigé (recharge + 3 s) avant d'être visé",
			function()
				local w, p = world({ n = 1, plume = false, bestR = 2, R = 2, awake = false })
				Bots.place(p, nearPlace(w, p, "1", 3))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "Press", p, "1", w.Clock.now()) -- intention acceptée : réveil aussi
				expect(w.playerPresses).toBe(1)
				local readyAt = w.Squishy.readyAt(p, "1")
				expect(readyAt > w.Clock.now()).toBe(true)
				Bots.place(p, at(w, p, 0, 60))
				local sends = framesNoting(w, p, 200, {})
				expect(#sends >= 1).toBe(true)
				expect(sends[1].msg.presses[1].uid).toBe("1")
				-- choisi au premier tick où la recharge est finie depuis ReadyFor s, pas avant
				local earliest = readyAt + w.Balance.Helpers.ReadyFor
				expect(sends[1].t >= earliest - 1e-6).toBe(true)
				expect(sends[1].t < earliest + 0.11 + w.Rules.RETRY).toBe(true)
				clean(w)
			end
		)

		it("une Plopette ne represse jamais un squishy dans sa recharge (posée à sa pression)", function()
			local w, p = world({ n = 1, plume = true })
			Brains.frames(w, 400)
			-- par squishy (la Cuve peut en faire éclore d'autres pendant le test)
			local last = {}
			local again = 0
			for _, e in pressesOf(w, p) do
				if last[e.uid] then
					again += 1
					local gap = e.t - last[e.uid]
					expect(gap >= w.Balance.Press.Cooldown + w.Balance.Helpers.ReadyFor - 0.11).toBe(true)
				end
				last[e.uid] = e.t
			end
			expect(again >= 2).toBe(true)
			clean(w)
		end)

		it(
			"la cible change de place pendant le saut (place libérée devant elle) : abandon, puis nouvelle cible",
			function()
				local w, p = world({ n = 8 })
				until_(w, 50, function()
					return #messages(w, p) > 0
				end)
				local first = messages(w, p)[1]
				local inFirst = {}
				for _, e in first.presses do
					inFirst[e.uid] = true
				end
				expect(inFirst["1"]).toBeNil() -- le plus petit revenu n'est pas visé
				-- vendre « 1 » décale d'une place tous les squishies créés après lui
				w.h:fireServer(R .. "Sell", p, { "1" }, true)
				expect(w.Squishy.get(p, "1")).toBeNil()
				Brains.frames(w, 40)
				-- aucun saut du premier envoi n'est payé (chaque cible a changé de place) ; d'autres l'ont été
				local firstPaid = 0
				for _, e in w.pressed do
					if e.t < first.presses[1].tPress + 0.2 then
						firstPaid += 1
					end
				end
				expect(firstPaid).toBe(0)
				expect(w.Helper.counters().Abandoned).toBe(#first.presses)
				expect(#messages(w, p) >= 2).toBe(true)
				Brains.frames(w, 40)
				expect(#w.pressed > 0).toBe(true)
				clean(w)
			end
		)

		it("squishy vendu ou mis à la clôture pendant le saut : jamais pressé", function()
			local w, p = world({ n = 8 })
			until_(w, 50, function()
				return #messages(w, p) > 0
			end)
			local first = #messages(w, p)
			local presses = messages(w, p)[1].presses
			local sold = presses[1].uid
			-- vendu pendant le saut
			w.h:fireServer(R .. "Sell", p, { sold }, true)
			expect(w.Squishy.get(p, sold)).toBeNil()
			-- à la clôture (pet-sitting) pendant le saut
			local fenced = presses[2].uid
			w.Ranch.setFence(w.Ranch.slotOf(p), { fenced }, "petsit")
			Brains.frames(w, 40)
			for _, e in pressesOf(w, p) do
				expect(e.uid ~= sold and e.uid ~= fenced).toBe(true)
			end
			-- la clôture reste : jamais visé ensuite
			Brains.frames(w, 200)
			local msgs = messages(w, p)
			expect(#msgs > first).toBe(true)
			for i = first + 1, #msgs do
				for _, e in msgs[i].presses do
					expect(e.uid ~= fenced and e.uid ~= sold).toBe(true)
				end
			end
			w.Ranch.setFence(w.Ranch.slotOf(p), {}, "")
			clean(w)
		end)
	end)

	describe("HelperService › sieste (N23 : 5 min sans intention ACCEPTÉE)", function()
		it("aucune intention depuis l'arrivée : sieste, rien du tout", function()
			local w, p = world({ awake = false })
			Brains.frames(w, 300)
			expect(w.Helper.state(p)).toBe("nap")
			expect(#messages(w, p)).toBe(0)
			expect(#w.pressed).toBe(0)
			clean(w)
		end)

		it(
			"sieste à 5 min pile malgré un stick calé (déplacements) ; réveil à la 1re intention acceptée",
			function()
				local w, p = world({ awake = false })
				-- intention acceptée réelle (Guard → Activity.note) : SetLock d'un squishy existant
				w.h:fireServer(R .. "SetLock", p, "1", true)
				local t0 = w.Activity.lastIntent(p)
				expect(math.abs(t0 - w.Clock.now()) < 1e-6).toBe(true)
				-- stick calé : le joueur marche sans fin entre deux points (activité de la v1.3, pas une intention)
				local a, b = at(w, p, -10, 60), at(w, p, 10, 60)
				local goingB = true
				local brain = function()
					if Bots.stepToward(p, if goingB then b else a) then
						goingB = not goingB
					end
				end
				Brains.frames(w, 2990, brain) -- 299 s
				expect(w.Helper.state(p) ~= "nap").toBe(true)
				expect(w.Activity.lastActive(p) > t0 + 290).toBe(true)
				expect(w.Activity.lastIntent(p)).toBe(t0)
				Brains.frames(w, 20, brain)
				expect(w.Helper.state(p)).toBe("nap")
				local n = #pressesOf(w, p)
				expect(n > 0).toBe(true)
				-- sieste : plus rien, même en marchant encore 2 min
				local msgs = #messages(w, p)
				Brains.frames(w, 1200, brain)
				expect(#pressesOf(w, p)).toBe(n)
				expect(#messages(w, p)).toBe(msgs)
				for _, h in w.Helper.helpers(p) do
					expect(h.moving).toBe(false)
				end
				-- intention refusée (uid inconnu) : toujours la sieste
				w.h:fireServer(R .. "SetLock", p, "999", true)
				Brains.frames(w, 10)
				expect(w.Helper.state(p)).toBe("nap")
				-- intention acceptée : réveil, pressions reprises
				w.h:fireServer(R .. "SetLock", p, "1", false)
				Brains.frames(w, 50)
				expect(w.Helper.state(p) ~= "nap").toBe(true)
				Brains.frames(w, 40)
				expect(#pressesOf(w, p) > n).toBe(true)
				clean(w)
			end
		)

		it("un saut en cours à l'heure de la sieste est abandonné (aucune récompense)", function()
			local w, p = world({ n = 8, awake = false })
			w.Activity.note(p, w.Clock.now() - 299) -- dernière intention il y a 299 s
			until_(w, 20, function()
				return #messages(w, p) > 0
			end)
			expect(#messages(w, p)).toBe(1)
			Brains.frames(w, 40) -- tPress ≈ + 3 s : après l'heure de la sieste
			expect(w.Helper.state(p)).toBe("nap")
			expect(#w.pressed).toBe(0)
			clean(w)
		end)
	end)

	describe("HelperService › pauses (prestige, Rush à sa clôture, fuite, pause)", function()
		it("Grand Splorch en file puis en spectacle : pause (queuedKind) ; reprise ensuite", function()
			local w, p = world({ R = 4, n = 8, big = true })
			until_(w, 50, function()
				return #messages(w, p) > 0
			end)
			local inFlight = #messages(w, p)
			-- le joueur rentre dans son ranch et lance son Grand Splorch pendant les sauts
			Bots.place(p, at(w, p, 0, 50))
			Brains.frames(w, 1)
			w.h:fireServer(R .. "GrandSplorch", p, false, "8")
			Brains.frames(w, 1)
			expect(w.Splorch.queuedKind(p) ~= nil or not w.Splorch.canPrestige(p)).toBe(true)
			expect(w.Helper.state(p)).toBe("paused")
			expect(w.Helper.pauseReason(p)).toBe("prestige")
			Brains.frames(w, 50) -- tPress passé pendant la pause
			expect(#w.pressed).toBe(0)
			expect(#messages(w, p)).toBe(inFlight)
			-- fin du spectacle et de l'éclatement : reprise
			until_(w, 600, function()
				return w.Splorch.canPrestige(p) and w.Splorch.queuedKind(p) == nil
			end)
			wake(w, p)
			Brains.frames(w, 3)
			expect(w.Helper.state(p) ~= "paused").toBe(true)
			clean(w)
		end)

		it("Jelly Ascend en file puis en spectacle : pause (queuedKind « ascend »)", function()
			local w, p =
				world({ R = 15, bestR = 15, n = 8, flags = { "RecordR", "Confetti", "JellyAscend" } })
			Bots.place(p, at(w, p, 0, 50))
			Brains.frames(w, 2)
			w.h:fireServer(R .. "JellyAscend", p, true)
			Brains.frames(w, 1)
			expect(w.Splorch.queuedKind(p)).toBe("ascend")
			expect(w.Helper.state(p)).toBe("paused")
			expect(w.Helper.pauseReason(p)).toBe("prestige")
			local n = #w.pressed
			until_(w, 400, function()
				return w.Splorch.queuedKind(p) == nil and w.Splorch.canPrestige(p)
			end)
			expect(#w.pressed).toBe(n)
			wake(w, p)
			Brains.frames(w, 3)
			expect(w.Helper.state(p) ~= "paused").toBe(true)
			clean(w)
		end)

		it("Petit Splorch : pause pendant l'animation (canPrestige faux)", function()
			local w, p = world({
				R = 4,
				bestR = 12,
				n = 8,
				big = true,
				flags = { "RecordR", "Confetti", "PetitSplorch" },
			})
			Bots.place(p, at(w, p, 0, 50))
			Brains.frames(w, 2)
			w.h:fireServer(R .. "GrandSplorch", p, false, "8")
			Brains.frames(w, 1)
			expect(w.Splorch.canPrestige(p)).toBe(false)
			expect(w.Helper.state(p)).toBe("paused")
			until_(w, 100, function()
				return w.Splorch.canPrestige(p)
			end)
			Brains.frames(w, 2)
			expect(w.Helper.state(p) ~= "paused").toBe(true)
			clean(w)
		end)

		it("BOOP RUSH pendant que son ranch est en mode Rush : pause ; en mode Cozy : rien", function()
			local phase = Harness.new():require(L .. "Logic.EventClock").rush(T0 + 600)
			local w, p = world({ rush = true, t0 = phase.startsAt - 30 })
			local w2, q = world({ rush = false, t0 = phase.startsAt - 30 })
			Brains.frames(w, 300)
			Brains.frames(w2, 300)
			expect(w.Event.rushActive()).toBe(true)
			wake(w, p)
			wake(w2, q)
			Brains.frames(w, 2)
			Brains.frames(w2, 2)
			expect(w.Helper.state(p)).toBe("paused")
			expect(w.Helper.pauseReason(p)).toBe("rush")
			expect(w2.Helper.state(q) ~= "paused").toBe(true)
			local n = #pressesOf(w, p)
			Brains.frames(w, 100)
			expect(#pressesOf(w, p)).toBe(n)
			-- fin du Rush : reprise
			until_(w, 1200, function()
				return not w.Event.rushActive()
			end)
			wake(w, p)
			Brains.frames(w, 60)
			expect(w.Helper.state(p) ~= "paused").toBe(true)
			expect(#pressesOf(w, p) > n).toBe(true)
			clean(w)
			clean(w2)
		end)

		it("fuite d'un de ses squishies : pause ; pause(player) et resume(player)", function()
			local w, p = world({ n = 8 })
			w.Squishy.setEscaping(p, "1", true)
			Brains.frames(w, 2)
			expect(w.Helper.pauseReason(p)).toBe("rush")
			w.Squishy.setEscaping(p, "1", false)
			Brains.frames(w, 2)
			expect(w.Helper.state(p) ~= "paused").toBe(true)
			w.Helper.pause(p, "test")
			Brains.frames(w, 2)
			expect(w.Helper.state(p)).toBe("paused")
			expect(w.Helper.pauseReason(p)).toBe("test")
			local n = #pressesOf(w, p)
			Brains.frames(w, 100)
			expect(#pressesOf(w, p)).toBe(n)
			w.Helper.resume(p)
			Brains.frames(w, 60)
			expect(#pressesOf(w, p) > n).toBe(true)
			clean(w)
		end)
	end)

	describe("HelperService › HelperPress regroupé, départ, interrupteur en direct", function()
		it(
			"un message par tick et par ranch ; au propriétaire et aux voisins proches, pas aux lointains",
			function()
				local w = boot()
				local p = Brains.join(w, 1, { profile = owner(w, { n = 8 }) })
				local near =
					Brains.join(w, 2, { profile = owner(w, { n = 2, bestR = 0, R = 0, plume = false }) })
				local far =
					Brains.join(w, 3, { profile = owner(w, { n = 2, bestR = 0, R = 0, plume = false }) })
				Bots.place(p, at(w, p, 0, 60))
				Bots.place(near, at(w, p, 0, -10)) -- dans la rue, devant le portail du propriétaire
				Bots.place(far, w.WL.plaza("center") + w.V3.new(0, 3, 0))
				Brains.frames(w, 2)
				wake(w, p)
				-- jamais deux messages au même joueur pour le même ranch dans le même tick
				for _ = 1, 600 do
					local before = #w.h.log.clientEvents
					Brains.frames(w, 1)
					local seen = {}
					for i = before + 1, #w.h.log.clientEvents do
						local e = w.h.log.clientEvents[i]
						if e.remote == "HelperPress" then
							local key = e.player.UserId .. ":" .. e.args[1].ownerId
							expect(seen[key]).toBeNil()
							seen[key] = true
						end
					end
				end
				local byTick = messages(w, p)
				expect(#byTick > 3).toBe(true)
				expect(#messages(w, near)).toBe(#messages(w, p))
				expect(#messages(w, far)).toBe(0)
				-- un message porte plusieurs sauts (6 Plopettes ensemble)
				local most = 0
				for _, m in byTick do
					most = math.max(most, #m.presses)
				end
				expect(most).toBe(6)
				clean(w)
			end
		)

		it(
			"départ pendant les sauts : aucune récompense après, état oublié ; retour : sieste puis reprise",
			function()
				local w, p = world({ n = 8 })
				until_(w, 50, function()
					return #messages(w, p) > 0
				end)
				local coinsAtLeave = coins(w, p)
				Bots.leave(p)
				w.h:settle(2)
				Brains.frames(w, 60)
				expect(#w.pressed).toBe(0)
				expect(w.Helper.counters().Owners).toBe(0)
				-- profil sauvegardé au départ : pièces d'avant le départ
				local back = Brains.join(w, 1)
				expect(coins(w, back)).toBe(coinsAtLeave)
				Bots.place(back, at(w, back, 0, 60))
				Brains.frames(w, 30)
				expect(w.Helper.state(back)).toBe("nap") -- aucune intention dans cette séance
				wake(w, back)
				Brains.frames(w, 60)
				expect(#pressesOf(w, back) > 0).toBe(true)
				clean(w)
			end
		)

		it(
			"interrupteur coupé en direct pendant les sauts : rien après ; rouvert : départ de la maisonnette",
			function()
				local w, p = world({ n = 8 })
				until_(w, 50, function()
					return #messages(w, p) > 0
				end)
				local sent = #messages(w, p)
				assert(w.Features.set("Helpers", false))
				Brains.frames(w, 100)
				expect(#w.pressed).toBe(0)
				expect(#messages(w, p)).toBe(sent)
				expect(w.Helper.counters().Owners).toBe(0)
				expect(w.Helper.state(p)).toBe("idle")
				assert(w.Features.set("Helpers", true))
				wake(w, p)
				Brains.frames(w, 60)
				expect(#messages(w, p) > sent).toBe(true)
				expect(#w.pressed > 0).toBe(true)
				-- aucune cible périmée : chaque récompense suit un message envoyé APRÈS la réouverture
				local reopenedMsgs = messages(w, p)
				local after = {}
				for i = sent + 1, #reopenedMsgs do
					for _, e in reopenedMsgs[i].presses do
						after[e.uid] = true
					end
				end
				for _, e in w.pressed do
					expect(after[e.uid]).toBe(true)
				end
				clean(w)
			end
		)
	end)

	describe("HelperService › coût du tick", function()
		it("16 joueurs × 6 Plopettes : < 0,5 ms par tick en moyenne (os.clock réel)", function()
			local w = boot()
			local players = {}
			for i = 1, 16 do
				local p = Brains.join(w, i, { profile = owner(w, { n = 8 }) })
				Bots.place(p, at(w, p, 0, 60))
				table.insert(players, p)
			end
			Brains.frames(w, 2)
			for _, p in players do
				wake(w, p)
			end
			Brains.frames(w, 50) -- mise en route
			local spent, n, worst = 0, 0, 0
			local step = w.Helper.step
			w.Helper.step = function(now, acting)
				local t0 = os.clock()
				step(now, acting)
				local dt = os.clock() - t0
				spent += dt
				worst = math.max(worst, dt)
				n += 1
			end
			for k = 1, 6 do
				Brains.frames(w, 100)
				for _, p in players do
					wake(w, p)
				end
			end
			w.Helper.step = step
			local ms = spent / n * 1000
			print(
				string.format(
					"  HelperService.step : %.3f ms par tick en moyenne (pire %.3f ms), %d ticks, %d pressions",
					ms,
					worst * 1000,
					n,
					#w.pressed
				)
			)
			expect(n >= 600).toBe(true)
			expect(#w.pressed > 16 * 6 * 3).toBe(true)
			expect(ms < 0.5).toBe(true)
			clean(w)
		end)
	end)
end
