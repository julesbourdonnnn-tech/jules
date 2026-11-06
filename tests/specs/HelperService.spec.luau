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
				-- compteurs transmis à Diagnostics (lot A4, D29) : « Count:Helper<nom> », sans trace
				local diag = w.h:require(S .. "DiagnosticsService").counters()
				local own = w.Helper.counters()
				expect({ diag.HelperPressed, diag.HelperChosen }).toEqual({ own.Pressed, own.Chosen })
				expect(own.Pressed).toBe(6)
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
				-- sauts du premier envoi : seuls ceux encore à plus de 12 studs sont payés ; une Plopette
				-- qui abandonne repart tout de suite DE LA CIBLE (A3-21) et peut presser une autre cible
				-- dans la fenêtre : jamais un squishy du premier envoi (en vol ou en recharge), toujours à
				-- plus de 12 studs du joueur (immobile à pos)
				local inFirst = {}
				for _, e in msg.presses do
					inFirst[e.uid] = true
				end
				local got = 0
				for _, e in pressesOf(w, p) do
					local c = placeOf(w, p, e.uid)
					expect(w.Rules.farEnough(pos.X, pos.Z, c.X, c.Z)).toBe(true)
					if inFirst[e.uid] then
						expect(allowed[e.uid]).toBe(true)
						got += 1
					end
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

		-- A3-21 (rouge d'abord) : le client a dessiné le saut jusqu'à la cible (aucun message pour un
		-- abandon) ; le trajet suivant part donc de la cible, pas de l'ancienne place de la Plopette
		it(
			"saut abandonné à tPress : la Plopette reste où elle a atterri, le saut suivant part de la cible",
			function()
				-- Pip seule : un saut à la fois
				local w, p = world({ n = 8, bestR = 2, R = 2, plume = false })
				local sends = {}
				for _ = 1, 50 do
					framesNoting(w, p, 1, sends)
					if #sends > 0 then
						break
					end
				end
				expect(#sends).toBe(1)
				local first = sends[1].msg.presses[1]
				-- la cible part à la clôture pendant le saut : abandon à tPress (le joueur reste loin : les
				-- autres squishies, voisins de la cible, restent visables)
				local slot = w.Ranch.slotOf(p)
				w.Ranch.setFence(slot, { first.uid }, "petsit")
				for _ = 1, 40 do
					framesNoting(w, p, 1, sends)
					if #sends > 1 then
						break
					end
				end
				expect(#sends).toBe(2)
				expect(#w.pressed).toBe(0)
				expect(w.Helper.counters().Abandoned).toBe(1)
				local second = sends[2].msg.presses[1]
				expect(second.uid ~= first.uid).toBe(true)
				-- places d'enclos (la cible reste « pen » à la clôture : sa place compte encore)
				local records = w.DS.get(p).squishies
				local a = w.Places.center(slot, records, first.uid)
				local b = w.Places.center(slot, records, second.uid)
				local hx, hz = w.Rules.houseLocal()
				local home = w.WL.toWorld(slot, w.V3.new(hx, 0, hz))
				local fromTarget = w.Rules.travel(a.X, a.Z, b.X, b.Z)
				local fromHome = w.Rules.travel(home.X, home.Z, b.X, b.Z)
				expect(math.abs(fromTarget - fromHome) > 0.3).toBe(true) -- le cas distingue les deux départs
				expect(math.abs((second.tPress - sends[2].t) - fromTarget) < 1e-6).toBe(true)
				w.Ranch.setFence(slot, {}, "")
				clean(w)
			end
		)
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

		-- A3-23 (rouge d'abord) : pause(player) demandée par un autre service pour un joueur déjà parti
		-- (PlayerRemoving déjà passé) : rien n'est gardé (aucune référence au Player)
		it("pause() d'un joueur parti ou en partance : aucune pause gardée après son départ", function()
			local w, p = world({ n = 8 })
			local q = Brains.join(w, 2, { profile = owner(w, { n = 2 }) })
			w.Helper.pause(q, "photo")
			expect(w.Helper.counters().Manual).toBe(1)
			Bots.leave(q)
			Bots.leave(p)
			w.h:settle(2)
			-- appel tardif (après PlayerRemoving) : ignoré
			w.Helper.pause(p, "photo")
			Brains.frames(w, 2)
			expect(w.Helper.counters().Manual).toBe(0)
			expect(w.Helper.counters().Owners).toBe(0)
			clean(w)
		end)

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

	-- =========================================================================================
	-- Lot A4 (étape 2) : restes du serveur (notes d'A3 du 6 novembre, 0 h 40 et 1 h 10 ; D1, D2 du plan)
	-- =========================================================================================
	describe("HelperService › lot A4 : recharge du joueur, jumeau en fusion", function()
		it("pression du joueur juste après celle d'une Plopette : refusée (recharge)", function()
			local w, p = world({ n = 8 })
			until_(w, 100, function()
				return #w.pressed > 0
			end)
			local e = w.pressed[1]
			-- recharge posée par SquishyService.helperPressed : celle d'une pression du joueur
			expect(w.Squishy.readyAt(p, e.uid)).toBe(e.t + w.Balance.Press.Cooldown)
			-- le joueur arrive tout de suite sur le squishy et presse : refusé (recharge), rien de payé
			Bots.place(p, nearPlace(w, p, e.uid, 3))
			Brains.frames(w, 2)
			expect(w.Clock.now() < e.t + w.Balance.Press.Cooldown).toBe(true)
			w.h:fireServer(R .. "Press", p, e.uid, w.Clock.now())
			expect(w.playerPresses).toBe(0)
			-- la recharge finie, la même pression passe
			while w.Clock.now() < e.t + w.Balance.Press.Cooldown do
				Brains.frames(w, 1)
			end
			w.RateLimit = w.RateLimit or w.h:require("ServerScriptService.Server.Util.RateLimit")
			w.RateLimit.clear(p)
			w.h:fireServer(R .. "Press", p, e.uid, w.Clock.now())
			expect(w.playerPresses).toBe(1)
			clean(w)
		end)

		it(
			"jumeau en fusion jamais visé ; visé puis mis en fusion pendant le saut : abandonné, rien payé",
			function()
				-- 6 jumeaux (espèce 2) et 2 seuls : « Tout fusionner » réserve les 6 pendant tout le plan
				local squishies = pen(6)
				table.insert(squishies, { s = 3, z = 900 })
				table.insert(squishies, { s = 4, z = 950 })
				local w, p = world({ squishies = squishies })
				-- une pression d'aide payée : jamais pour un squishy réservé à cet instant (revu à tPress)
				local busyPaid = 0
				w.Signals.HelperPressed:Connect(function(owner, _, uid)
					if w.Squishy.busy(owner, uid) then
						busyPaid += 1
					end
				end)
				w.h:fireServer(R .. "FuseAll", p)
				expect(w.Squishy.busy(p, "1")).toBe(true)
				-- chaque cible choisie pendant le plan : jamais un squishy réservé à cet instant
				local chosen, duringPlan = 0, 0
				for _ = 1, 80 do
					local before = #messages(w, p)
					local planOn = w.Squishy.busy(p, "1") or w.Squishy.busy(p, "2")
					Brains.frames(w, 1)
					local msgs = messages(w, p)
					for i = before + 1, #msgs do
						for _, entry in msgs[i].presses do
							chosen += 1
							if planOn then
								duringPlan += 1
							end
							expect({ uid = entry.uid, busy = w.Squishy.busy(p, entry.uid) }).toEqual({
								uid = entry.uid,
								busy = false,
							})
						end
					end
				end
				expect(chosen > 0).toBe(true)
				expect(duringPlan > 0).toBe(true) -- les deux seuls (7, 8) visés pendant le plan
				expect(busyPaid).toBe(0)
				clean(w)

				-- visé, puis mis en fusion 0,2 s avant tPress (le jumeau disparaît 0,4 s plus tard) : abandon
				local w2, p2 = world({ n = 8 })
				until_(w2, 50, function()
					return #messages(w2, p2) > 0
				end)
				local first = messages(w2, p2)[1].presses
				table.sort(first, function(a, b)
					return a.tPress < b.tPress
				end)
				local target = first[1]
				local partner = nil
				local aimed = {}
				for _, entry in first do
					aimed[entry.uid] = true
				end
				for k = 1, 8 do
					if not aimed[tostring(k)] then
						partner = tostring(k)
						break
					end
				end
				expect(partner ~= nil).toBe(true)
				while w2.Clock.now() + 0.1 < target.tPress - 0.2 - 1e-6 do
					Brains.frames(w2, 1)
				end
				w2.h:fireServer(R .. "FuseMenu", p2, target.uid, partner)
				expect(w2.Squishy.busy(p2, target.uid)).toBe(true)
				local abandoned = w2.Helper.counters().Abandoned
				Brains.frames(w2, 5)
				for _, e in w2.pressed do
					expect(e.uid ~= target.uid and e.uid ~= partner).toBe(true)
				end
				expect(w2.Helper.counters().Abandoned > abandoned).toBe(true)
				clean(w2)
			end
		)
	end)

	describe("HelperService › lot A4 : attributs du ranch HelperMode et Helpers (D2)", function()
		-- appels de RanchService.setV2Attributes qui touchent HelperMode ou Helpers
		-- appels de RanchService.setV2Attributes qui ne portent que HelperMode et Helpers (appels VIDES
		-- compris : un appel à chaque tick sans rien de changé est aussi compté ; les autres services
		-- posent d'autres noms et RanchService.refreshV2 n'appelle jamais sans rien)
		local function watchAttrs(w)
			local calls = {}
			local original = w.Ranch.setV2Attributes
			local mine = { HelperMode = true, Helpers = true }
			w.Ranch.setV2Attributes = function(player, attrs, clear)
				local only = true
				for name in if type(attrs) == "table" then attrs else {} do
					only = only and mine[name] == true
				end
				for _, name in if type(clear) == "table" then clear else {} do
					only = only and mine[name] == true
				end
				if only then
					table.insert(calls, { player = player, attrs = attrs, clear = clear })
				end
				return original(player, attrs, clear)
			end
			return calls
		end

		local function attr(w, p, name)
			local World = w.h:require(S .. "WorldService")
			local model = World.ranchModel(w.Ranch.slotOf(p))
			return model and model:GetAttribute(name)
		end

		it(
			"HelperMode posé une fois par changement (active, nap, paused), jamais à chaque tick ; Helpers = nombre de Plopettes",
			function()
				local w = boot()
				local calls = watchAttrs(w)
				local p = Brains.join(w, 1, { profile = owner(w, { plume = false }) })
				Bots.place(p, at(w, p, 0, 60))
				Brains.frames(w, 2)
				-- aucune intention depuis l'arrivée : sieste, 5 Plopettes (Record R 12, sans Plume)
				expect(attr(w, p, "HelperMode")).toBe("nap")
				expect(attr(w, p, "Helpers")).toBe(5)
				expect(#calls).toBe(1)
				Brains.frames(w, 100)
				expect(#calls).toBe(1) -- rien à chaque tick
				wake(w, p)
				Brains.frames(w, 2)
				expect(attr(w, p, "HelperMode")).toBe("active")
				expect(#calls).toBe(2)
				Brains.frames(w, 300)
				expect(#calls).toBe(2)
				w.Helper.pause(p, "photo")
				Brains.frames(w, 2)
				expect(attr(w, p, "HelperMode")).toBe("paused")
				expect(w.Helper.pauseReason(p)).toBe("photo")
				w.Helper.resume(p)
				Brains.frames(w, 2)
				expect(attr(w, p, "HelperMode")).toBe("active")
				expect(#calls).toBe(4)
				-- Plume achetée : une Plopette de plus, Helpers republié au tick suivant (UpgradeBought)
				local data = w.DS.get(p)
				data.atelier[w.Upgrades.WorkshopIndex.plume] = 1
				w.Signals.UpgradeBought:Fire(p, "plume", 0, 1, "confetti")
				Brains.frames(w, 1)
				expect(attr(w, p, "Helpers")).toBe(6)
				expect(#calls).toBe(5)
				-- nouveau Record R (Pip … Puff déjà là) : rien ne change, rien n'est republié
				w.Signals.RecordReached:Fire(p, 13)
				Brains.frames(w, 20)
				expect(attr(w, p, "Helpers")).toBe(6)
				expect(#calls).toBe(5)
				-- sieste 5 min plus tard (aucune intention) : une fois
				Brains.frames(w, 3010)
				expect(attr(w, p, "HelperMode")).toBe("nap")
				expect(#calls).toBe(6)
				clean(w)
			end
		)

		it(
			"Record R 0 (aucune Plopette) : Helpers = 0, HelperMode absent ; Record R 2 atteint : Helpers = 1 et HelperMode",
			function()
				local w = boot()
				local p = Brains.join(w, 1, { profile = owner(w, { bestR = 0, R = 0, plume = false }) })
				Bots.place(p, at(w, p, 0, 60))
				Brains.frames(w, 2)
				expect(attr(w, p, "Helpers")).toBe(0)
				expect(attr(w, p, "HelperMode")).toBeNil()
				local data = w.DS.get(p)
				data.R = 2
				data.bestR = 2
				w.Signals.RecordReached:Fire(p, 2)
				Brains.frames(w, 2)
				expect(attr(w, p, "Helpers")).toBe(1)
				expect(attr(w, p, "HelperMode")).toBe("nap")
				clean(w)
			end
		)

		it(
			"absents interrupteur coupé et pour un profil v1 ; effacés quand l'interrupteur est coupé en direct et au départ",
			function()
				local w, p = world({ off = true })
				Brains.frames(w, 20)
				expect(attr(w, p, "HelperMode")).toBeNil()
				expect(attr(w, p, "Helpers")).toBeNil()
				-- ouvert en direct : posés ; coupé en direct : effacés au tick suivant
				assert(w.Features.set("Helpers", true))
				wake(w, p)
				Brains.frames(w, 2)
				expect(attr(w, p, "HelperMode")).toBe("active")
				expect(attr(w, p, "Helpers")).toBe(6)
				assert(w.Features.set("Helpers", false))
				Brains.frames(w, 1)
				expect(attr(w, p, "HelperMode")).toBeNil()
				expect(attr(w, p, "Helpers")).toBeNil()
				-- rouvert : reposés ; départ : effacés avec le ranch, rien de gardé
				assert(w.Features.set("Helpers", true))
				Brains.frames(w, 2)
				expect(attr(w, p, "Helpers")).toBe(6)
				local World = w.h:require(S .. "WorldService")
				local model = World.ranchModel(w.Ranch.slotOf(p))
				Bots.leave(p)
				w.h:settle(2)
				Brains.frames(w, 2)
				expect(model:GetAttribute("HelperMode")).toBeNil()
				expect(model:GetAttribute("Helpers")).toBeNil()
				expect(w.Helper.counters().Owners).toBe(0)
				clean(w)
				-- profil v1 (serveur v1), interrupteur ouvert : jamais posés
				local w1 = boot({ v1 = true })
				local q = Brains.join(w1, 1, { profile = Brains.profile(w1, { R = 12, squishies = pen() }) })
				Bots.place(q, at(w1, q, 0, 60))
				wake(w1, q)
				Brains.frames(w1, 30)
				expect(attr(w1, q, "HelperMode")).toBeNil()
				expect(attr(w1, q, "Helpers")).toBeNil()
				clean(w1)
			end
		)
	end)

	describe(
		"HelperService › lot A4 : MenuActivity (N23, décision du propriétaire du 6 novembre)",
		function()
			it(
				"MenuActivity réveille la sieste sans marquer lastActive ; jamais une récompense (profil, Feedback, DataPatch inchangés)",
				function()
					local w, p = world({ awake = false })
					Brains.frames(w, 2)
					expect(w.Helper.state(p)).toBe("nap")
					local active = w.Activity.lastActive(p)
					local data = w.DS.get(p)
					local Tables = w.h:require(L .. "Util.Tables")
					local copy = Tables.deepCopy(data)
					local sent = { "DataPatch", "Feedback", "Celebrate", "Banner" }
					local counts = {}
					for _, name in sent do
						counts[name] = #w.h:sentTo(p, name)
					end
					w.h:fireServer(R .. "MenuActivity", p)
					w.h:settle(1)
					expect(w.Activity.lastIntent(p)).toBe(w.Clock.now())
					expect(w.Activity.lastActive(p)).toBe(active)
					expect(Tables.deepEqual(data, copy)).toBe(true)
					for _, name in sent do
						expect({ remote = name, n = #w.h:sentTo(p, name) }).toEqual({
							remote = name,
							n = counts[name],
						})
					end
					-- réveil : les Plopettes repartent
					Brains.frames(w, 60)
					expect(w.Helper.state(p) ~= "nap").toBe(true)
					expect(#pressesOf(w, p) > 0).toBe(true)
					clean(w)
				end
			)

			it(
				"MenuActivity refusée : interrupteur coupé, profil v1, joueur pas prêt, sans vie, parti",
				function()
					-- interrupteur coupé
					local w, p = world({ off = true, awake = false })
					w.h:fireServer(R .. "MenuActivity", p)
					w.h:settle(1)
					expect(w.Activity.lastIntent(p)).toBe(-math.huge)
					clean(w)
					-- profil v1 (serveur v1)
					local w1 = boot({ v1 = true })
					local q =
						Brains.join(w1, 1, { profile = Brains.profile(w1, { R = 12, squishies = pen() }) })
					Brains.frames(w1, 2)
					w1.h:fireServer(R .. "MenuActivity", q)
					w1.h:settle(1)
					expect(w1.Activity.lastIntent(q)).toBe(-math.huge)
					clean(w1)
					-- joueur pas prêt (PlayerReady pas encore émis), puis sans vie, puis parti
					local w2, r = world({ awake = false })
					local RateLimit = w2.h:require("ServerScriptService.Server.Util.RateLimit")
					local isReady = w2.Ranch.isReady
					w2.Ranch.isReady = function()
						return false
					end
					w2.h:fireServer(R .. "MenuActivity", r)
					w2.h:settle(1)
					w2.Ranch.isReady = isReady
					expect(w2.Activity.lastIntent(r)).toBe(-math.huge)
					local humanoid = r.Character:FindFirstChildOfClass("Humanoid")
					local health = humanoid.Health
					humanoid.Health = 0
					RateLimit.clear(r)
					w2.h:fireServer(R .. "MenuActivity", r)
					w2.h:settle(1)
					expect(w2.Activity.lastIntent(r)).toBe(-math.huge)
					humanoid.Health = health
					RateLimit.clear(r)
					w2.h:fireServer(R .. "MenuActivity", r)
					w2.h:settle(1)
					local t = w2.Activity.lastIntent(r)
					expect(t).toBe(w2.Clock.now())
					Bots.leave(r)
					w2.h:settle(2)
					RateLimit.clear(r)
					w2.h:fireServer(R .. "MenuActivity", r)
					w2.h:settle(1)
					expect(w2.Activity.lastIntent(r)).toBe(-math.huge)
					clean(w2)
				end
			)
		end
	)

	describe("HelperService › coût du tick", function()
		-- A3-22 (rouge d'abord) : le budget de passes de choix du tick (Rules.CHOOSE_PER_TICK) ne sert
		-- pas toujours les mêmes ranchs en premier (ordre de Players:GetPlayers) : tour de rôle
		it(
			"budget de choix épuisé à chaque tick par un ranch sans cible : les autres ranchs choisissent quand même",
			function()
				local w = boot()
				-- 1 passe de choix par tick ; sans cible, nouvel essai au tick suivant : le 1er arrivé
				-- (aucun squishy) redemande une passe à chaque tick
				w.Rules.CHOOSE_PER_TICK = 1
				w.Rules.RETRY = 0.05
				local hog = Brains.join(w, 1, { profile = owner(w, { squishies = {} }) })
				local p = Brains.join(w, 2, { profile = owner(w, { n = 8 }) })
				Bots.place(hog, at(w, hog, 0, 60))
				Bots.place(p, at(w, p, 0, 60))
				Brains.frames(w, 2)
				wake(w, hog)
				wake(w, p)
				Brains.frames(w, 100) -- 10 s
				expect(#pressesOf(w, hog)).toBe(0)
				expect(w.Helper.counters().NoTarget > 50).toBe(true) -- le ranch vide a bien redemandé
				expect(#pressesOf(w, p) >= 6).toBe(true) -- les 6 Plopettes de l'autre ranch ont pressé
				clean(w)
			end
		)

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
