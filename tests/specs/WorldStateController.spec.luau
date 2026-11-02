--!nocheck
-- WorldStateController (paquet client-world, docs/04 §13.3, §10.2, §10.5, §18.2) : instantané et
-- patchs numérotés, trous de suite (patchs ignorés, RequestWorld renvoyé toutes les 3 s, deux trous en
-- moins d'1 s convergent), aucun instantané au départ → renvois, créatures (doublon ignoré, fin sans
-- message), boops (fin sans message), EventState (offset appliqué, restUntil, file des spectacles),
-- ReportBlocked UNE fois (liste vide si GetCore lève, 200 au plus), best.s = 0, charges hostiles,
-- zéro trace.

local T0 = 1796724120 -- mardi 8/12/2026 10:02 UTC

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 1,
			fame = 0,
			day = 3,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 1, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 10, g = 1, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function squishy(over)
		local s = { s = 1, m = 0, st = 0, z = 5, zg = 10, at = "pen", bf = 0, o = "", ready = 0 }
		for k, v in over or {} do
			s[k] = v
		end
		return s
	end

	local function eventState(over)
		local p = {
			rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
			mega = {
				phase = "idle",
				index = 0,
				landsAt = 0,
				endsAt = 0,
				target = 0,
				points = 0,
				species = 1,
				moon = false,
				result = "",
			},
			golden = { active = false, id = 0, endsAt = 0 },
			moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
			gauge = { points = 0, target = 1000, partyUntil = 0, restUntil = 0 },
			boost = { kind = "", untilT = 0, byName = "" },
			spectacle = { queue = {} },
			features = {
				boopRush = "on",
				megaSquish = true,
				golden = true,
				jellyMoon = true,
				gauge = true,
				clips = true,
				costume = "",
				diagnostics = true,
			},
			offset = 0,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		if opts.blocked ~= nil then
			h:setBlocked(h.localPlayer, opts.blocked)
		end
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		h:settle(1)
		local c = { h = h, WSC = WSC, Clock = Clock }
		function c.fire(name, payload)
			h:fireClient("ReplicatedStorage.Remotes." .. name, payload)
			h:settle(1)
		end
		function c.sent(name)
			local out = {}
			for _, e in h.log.serverEvents do
				if e.remote == name then
					table.insert(out, e.args)
				end
			end
			return out
		end
		-- avance l'horloge du jeu et fait tourner les images (ménage à 4 Hz)
		function c.advance(seconds)
			local steps = math.max(1, math.ceil(seconds / 0.25))
			for _ = 1, steps do
				Clock.advance(seconds / steps)
				h:step(seconds / steps)
			end
		end
		function c.snapshot(seq, ranches, squishies)
			c.fire("RanchSnapshot", { seq = seq, ranches = ranches or {}, squishies = squishies or {} })
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	describe("WorldStateController", function()
		it("instantané : prêt, mon ranch, squishies, taille z + G(t) − zg, best.s = 0 gardé", function()
			local c = client()
			expect(c.WSC.ready()).toBe(false)
			expect(c.WSC.mySlot()).toBe(0)
			c.snapshot(1, { ["3"] = ranch(3, 1), ["5"] = ranch(5, 2) }, { ["3"] = { a = squishy() } })
			expect(c.WSC.ready()).toBe(true)
			expect(c.WSC.mySlot()).toBe(3)
			expect(c.WSC.ranch(5).userId).toBe(2)
			expect(c.WSC.ranch(3).best.s).toBe(0)
			expect(c.WSC.squishies(3).a.z).toBe(5)
			-- G(T0 + 10) = 10 + 1 × 10 = 20 → 5 + (20 − 10) = 15
			expect(c.WSC.sizeOf(3, "a", T0 + 10)).toBe(15)
			expect(c.WSC.sizeOf(3, "zz")).toBe(0)
			expect(c.WSC.ranch(99)).toBe(nil)
			c.clean()
		end)

		it("patchs dans l'ordre : champs et opérations appliqués, signaux émis", function()
			local c = client()
			c.snapshot(1, { ["3"] = ranch(3, 1) }, { ["3"] = {} })
			local fields, ops = {}, {}
			c.WSC.RanchChanged:Connect(function(slot, f)
				table.insert(fields, { slot, f })
			end)
			c.WSC.SquishyChanged:Connect(function(slot, uid, op)
				table.insert(ops, slot .. ":" .. uid .. ":" .. op)
			end)
			c.fire("RanchPatch", {
				seq = 2,
				ranches = { ["3"] = { R = 2, best = { s = 4, m = 0, z = 50, zg = 0 } } },
				ops = { { op = "add", slot = 3, uid = "b", rec = squishy({ s = 2 }) } },
			})
			expect(c.WSC.ranch(3).R).toBe(2)
			expect(c.WSC.ranch(3).best.s).toBe(4)
			expect(c.WSC.squishies(3).b.s).toBe(2)
			expect(#fields).toBe(1)
			expect(ops[1]).toBe("3:b:add")
			c.fire("RanchPatch", { seq = 3, ranches = {}, ops = { { op = "remove", slot = 3, uid = "b" } } })
			expect(c.WSC.squishies(3).b).toBe(nil)
			-- doublon (seq déjà vu) : ignoré, aucun RequestWorld
			c.fire("RanchPatch", { seq = 3, ranches = { ["3"] = { R = 9 } }, ops = {} })
			expect(c.WSC.ranch(3).R).toBe(2)
			expect(#c.sent("RequestWorld")).toBe(0)
			c.clean()
		end)

		it(
			"trou de suite : patchs ignorés, RequestWorld tout de suite puis toutes les 3 s jusqu'à l'instantané",
			function()
				local c = client()
				c.snapshot(1, { ["3"] = ranch(3, 1) })
				c.fire("RanchPatch", { seq = 3, ranches = { ["3"] = { R = 7 } }, ops = {} })
				expect(c.WSC.ranch(3).R).toBe(1)
				expect(#c.sent("RequestWorld")).toBe(1)
				-- le patch suivant (4) est aussi ignoré
				c.fire("RanchPatch", { seq = 4, ranches = { ["3"] = { R = 8 } }, ops = {} })
				expect(c.WSC.ranch(3).R).toBe(1)
				c.advance(2)
				expect(#c.sent("RequestWorld")).toBe(1) -- jamais plus vite que 3 s
				c.advance(1.25)
				expect(#c.sent("RequestWorld")).toBe(2)
				c.advance(3.25)
				expect(#c.sent("RequestWorld")).toBe(3)
				c.snapshot(5, { ["3"] = ranch(3, 1, { R = 8 }) })
				expect(c.WSC.ranch(3).R).toBe(8)
				c.advance(10)
				expect(#c.sent("RequestWorld")).toBe(3)
				c.fire("RanchPatch", { seq = 6, ranches = { ["3"] = { R = 9 } }, ops = {} })
				expect(c.WSC.ranch(3).R).toBe(9)
				c.clean()
			end
		)

		it("deux trous en moins d'1 s convergent (la 2e demande part 3 s après la 1re)", function()
			local c = client()
			c.snapshot(1, { ["3"] = ranch(3, 1) })
			c.fire("RanchPatch", { seq = 3, ranches = {}, ops = {} }) -- trou n° 1
			expect(#c.sent("RequestWorld")).toBe(1)
			c.advance(0.25)
			c.snapshot(10, { ["3"] = ranch(3, 1, { R = 2 }) })
			c.advance(0.5)
			c.fire("RanchPatch", { seq = 12, ranches = {}, ops = {} }) -- trou n° 2, 0,75 s plus tard
			expect(#c.sent("RequestWorld")).toBe(1) -- débit respecté : pas tout de suite
			c.advance(2.5)
			expect(#c.sent("RequestWorld")).toBe(2)
			c.snapshot(20, { ["3"] = ranch(3, 1, { R = 3 }) })
			c.fire("RanchPatch", { seq = 21, ranches = { ["3"] = { R = 4 } }, ops = {} })
			expect(c.WSC.ranch(3).R).toBe(4)
			expect(c.WSC.stats().resyncing).toBe(0)
			c.clean()
		end)

		it(
			"aucun instantané 15 s après le départ : RequestWorld toutes les 3 s, plus rien après",
			function()
				local c = client()
				c.advance(14)
				expect(#c.sent("RequestWorld")).toBe(0)
				c.advance(1.5)
				expect(#c.sent("RequestWorld")).toBe(1)
				c.advance(3.25)
				expect(#c.sent("RequestWorld")).toBe(2)
				c.snapshot(1, { ["3"] = ranch(3, 1) })
				c.advance(9)
				expect(#c.sent("RequestWorld")).toBe(2)
				c.clean()
			end
		)

		it("créatures : doublon ignoré, fin par message, fin SANS message à t0 + duration", function()
			local c = client()
			local spawned, finished = 0, {}
			c.WSC.CreatureSpawned:Connect(function()
				spawned += 1
			end)
			c.WSC.CreatureFinished:Connect(function(f)
				table.insert(finished, f)
			end)
			local function sp(id, over)
				local s = {
					id = id,
					kind = "wild",
					species = 1,
					mutation = 0,
					size = 3,
					stars = 0,
					ownerSlot = 0,
					booperSlot = 0,
					uid = "",
					path = "escape",
					seed = 42,
					t0 = T0,
					startNode = 1,
					awayAngle = 0,
					center = { x = 0, z = 0 },
					speed = 16,
					duration = 25,
					personal = false,
				}
				for k, v in over or {} do
					s[k] = v
				end
				return s
			end
			c.fire("ChaseEvent", {
				spawns = { sp(1), sp(2, { kind = "runaway", path = "hop", duration = 20 }) },
				finishes = {},
			})
			c.fire("ChaseEvent", { spawns = { sp(1) }, finishes = {} })
			expect(spawned).toBe(2)
			expect(c.WSC.creaturePos(1) ~= nil).toBe(true)
			c.fire(
				"ChaseEvent",
				{ spawns = {}, finishes = { { id = 2, reason = "caught", bySlot = 3, t = T0 } } }
			)
			expect(c.WSC.creatures()[2]).toBe(nil)
			expect(finished[1].reason).toBe("caught")
			-- fin sans message
			c.advance(25.5)
			expect(c.WSC.creatures()[1]).toBe(nil)
			expect(c.WSC.creaturePos(1)).toBe(nil)
			expect(finished[2].reason).toBe("expired")
			-- créature déjà finie à l'arrivée : ignorée
			c.fire("ChaseEvent", { spawns = { sp(3, { t0 = T0 - 100 }) }, finishes = {} })
			expect(c.WSC.creatures()[3]).toBe(nil)
			c.clean()
		end)

		it("boops : maintien gardé, fini par message ou à endsAt + 0,5 s sans message", function()
			local c = client()
			local events = {}
			c.WSC.BoopChanged:Connect(function(b)
				table.insert(events, b.state)
			end)
			c.fire("BoopState", { booperId = 7, ownerId = 1, uid = "a", endsAt = T0 + 2.5, state = "hold" })
			expect(c.WSC.boops()["7:1:a"].endsAt).toBe(T0 + 2.5)
			c.fire("BoopState", { booperId = 8, ownerId = 1, uid = "b", endsAt = T0 + 2.5, state = "hold" })
			c.fire("BoopState", { booperId = 8, ownerId = 1, uid = "b", endsAt = T0 + 2.5, state = "done" })
			expect(c.WSC.boops()["8:1:b"]).toBe(nil)
			c.advance(3.25)
			expect(c.WSC.boops()["7:1:a"]).toBe(nil)
			expect(events[#events]).toBe("cancel")
			c.clean()
		end)

		it(
			"EventState : à chaque message, offset appliqué, restUntil et file (slot, position, eta) gardés",
			function()
				local c = client()
				local n = 0
				c.WSC.EventChanged:Connect(function()
					n += 1
				end)
				local queue =
					{ { kind = "splorch", userId = 2, startAt = T0 + 40, slot = 5, position = 1, eta = 40 } }
				c.fire("EventState", eventState({ offset = 120, spectacle = { queue = queue } }))
				c.fire(
					"EventState",
					eventState({
						offset = 120,
						gauge = { points = 5, target = 900, partyUntil = 0, restUntil = T0 + 600 },
						spectacle = { queue = queue },
					})
				)
				expect(n).toBe(2)
				expect(c.Clock.getOffset()).toBe(120)
				local ev = c.WSC.event()
				expect(ev.gauge.restUntil).toBe(T0 + 600)
				expect(ev.spectacle.queue[1].slot).toBe(5)
				expect(ev.spectacle.queue[1].position).toBe(1)
				expect(ev.spectacle.queue[1].eta).toBe(40)
				c.clean()
			end
		)

		it("ReportBlocked envoyé UNE fois au Start avec la liste de blocage (200 au plus)", function()
			local list = {}
			for i = 1, 250 do
				list[i] = 1000 + i
			end
			local c = client({ blocked = list })
			local sent = c.sent("ReportBlocked")
			expect(#sent).toBe(1)
			expect(#sent[1][1]).toBe(200)
			expect(sent[1][1][1]).toBe(1001)
			c.WSC.Start()
			c.advance(20)
			expect(#c.sent("ReportBlocked")).toBe(1)
			c.clean()
		end)

		it("GetCore lève (CoreScripts pas prêts) : liste vide, aucune erreur ni avertissement", function()
			local c = client({ blocked = false })
			local sent = c.sent("ReportBlocked")
			expect(#sent).toBe(1)
			expect(#sent[1][1]).toBe(0)
			c.clean()
		end)

		it("charges hostiles : aucune erreur, aucun état faux", function()
			local c = client()
			c.snapshot(1, { ["3"] = ranch(3, 1) }, { ["3"] = { a = squishy() } })
			local nan = 0 / 0
			local deep = {}
			local cur = deep
			for _ = 1, 50 do
				cur.x = {}
				cur = cur.x
			end
			local hostile = {
				nil,
				1,
				"x",
				true,
				{},
				deep,
				{ seq = nan },
				{ seq = math.huge },
				{ seq = 2, ranches = "x", ops = "y" },
				{
					seq = 2,
					ranches = { [1] = { R = 5 }, ["99"] = { R = 5 }, ["-1"] = {} },
					ops = { { op = "add", slot = 99, uid = "a", rec = {} } },
				},
				{
					seq = 2,
					ranches = {
						["3"] = { R = nan, name = string.rep("a", 100000), userId = "x", growth = 5 },
					},
					ops = { 1, "z", { op = "add", slot = 3, uid = "BAD!" } },
				},
			}
			for _, p in hostile do
				for _, name in
					{
						"RanchPatch",
						"RanchSnapshot",
						"Fence",
						"ChaseEvent",
						"EventState",
						"BoopState",
						"EmoteShow",
					}
				do
					c.fire(name, p)
				end
			end
			c.h:fireClient("ReplicatedStorage.Remotes.MegaBeat", { points = nan, target = 1, t = 0 })
			c.h:settle(1)
			expect(c.WSC.ranch(3) ~= nil).toBe(true)
			expect(c.WSC.ranch(3).R == c.WSC.ranch(3).R).toBe(true)
			expect(#c.WSC.ranch(3).name <= 64).toBe(true)
			-- le dernier instantané (abîmé mais bien formé) a été nettoyé ; le patch suivant s'applique
			c.fire("RanchPatch", { seq = 3, ranches = { ["3"] = { R = 4 } }, ops = {} })
			expect(c.WSC.ranch(3).R).toBe(4)
			c.clean()
		end)

		it("clôture : uids validés (4 au plus), raison inconnue → libérée", function()
			local c = client()
			local seen = 0
			c.WSC.FenceChanged:Connect(function()
				seen += 1
			end)
			c.fire("Fence", { slot = 4, uids = { "a", "b", "c", "d", "e" }, reason = "rush" })
			local uids, reason = c.WSC.fence(4)
			expect(#uids).toBe(4)
			expect(reason).toBe("rush")
			c.fire("Fence", { slot = 4, uids = {}, reason = "weird" })
			uids, reason = c.WSC.fence(4)
			expect(#uids).toBe(0)
			expect(reason).toBe("")
			expect(seen).toBe(2)
			c.clean()
		end)
		-- Revue client-world : GetCore lève au Start (CoreScripts pas encore prêts, cas réel) → la
		-- liste vide part tout de suite, puis GetCore est réessayé ; dès qu'il répond, la vraie liste
		-- part UNE fois, au débit du serveur (1 / 10 s) ; une liste encore vide ne repart jamais
		it(
			"GetCore lève au Start puis répond : la vraie liste repart une fois (≥ 10 s après)",
			function()
				local c = client({ blocked = false })
				expect(#c.sent("ReportBlocked")).toBe(1)
				c.advance(3)
				c.h:setBlocked(c.h.localPlayer, { 4242, 77 })
				c.advance(4)
				expect(#c.sent("ReportBlocked")).toBe(1) -- jamais avant 10 s (débit du serveur)
				c.advance(6)
				local sent = c.sent("ReportBlocked")
				expect(#sent).toBe(2)
				expect(sent[2][1][1]).toBe(4242)
				expect(#sent[2][1]).toBe(2)
				c.advance(60)
				expect(#c.sent("ReportBlocked")).toBe(2)
				-- GetCore qui lève toujours : un seul envoi (la liste vide), plus aucun essai après 30 s
				local c2 = client({ blocked = false })
				c2.advance(45)
				expect(#c2.sent("ReportBlocked")).toBe(1)
				c.clean()
				c2.clean()
			end
		)
	end)
end
