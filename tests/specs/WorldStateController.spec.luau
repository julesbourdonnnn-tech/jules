--!nocheck
-- WorldStateController (paquet client-world) : miroir client du monde (GDD §12.4, docs §10.4-§10.6,
-- §13.6). Instantané d'arrivée, ordre strict des versions (LineEvent + SnipEvent), tampon de 1 s
-- puis RequestWorld, miettes PathStream / PathSnapshot (trous, paquets en retard), sauvages (ids
-- retirés 5 s, expiration locale), positions déterministes (flânerie, cordes, Comète), charges
-- malveillantes ignorées sans erreur.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	local function setup()
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WSC = WSC,
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			SeededPath = h:require("ReplicatedStorage.Shared.Logic.SeededPath"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			log = {},
		}
		for _, name in
			{
				"Ready",
				"LineOp",
				"Caught",
				"Banked",
				"Snipped",
				"Cleared",
				"OwnerChanged",
				"WildAdded",
				"WildRemoved",
				"EventChanged",
				"CrewsChanged",
				"PingShown",
			}
		do
			WSC[name]:Connect(function(...)
				table.insert(c.log, { name = name, args = table.pack(...) })
			end)
		end
		WSC.Init()
		WSC.Start()
		return c
	end

	local function count(c, name)
		local n = 0
		for _, e in c.log do
			if e.name == name then
				n += 1
			end
		end
		return n
	end

	local function events(c, name)
		local out = {}
		for _, e in c.log do
			if e.name == name then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function requests(c, remote)
		local out = {}
		for _, e in c.h.log.serverEvents do
			if e.remote == remote then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function V(x, y, z)
		return Vector3.new(x, y, z)
	end

	-- miettes en ligne droite (un point par stud) le long de +X à partir de x0
	local function straight(n, x0, z)
		local points = {}
		for i = 1, n do
			points[i] = V((x0 or 0) + i, 3, z or 0)
		end
		return points
	end

	local function encode(c, tick, slot, firstSeq, points)
		return c.PathCodec.encode(tick, c.PathCodec.split(slot, firstSeq, points))
	end

	local function emptyEvents(t)
		return { t = t or T0, wisps = {}, snipsDisabled = false, activePlayers = 1 }
	end

	local function snapshot(c, over)
		local snap = {
			serverTime = T0,
			tick = 10,
			lines = {},
			paths = c.PathCodec.encode(10, {}),
			wild = {},
			events = emptyEvents(),
			crews = { crews = {} },
		}
		for k, v in over or {} do
			snap[k] = v
		end
		return snap
	end

	local function fire(c, remote, ...)
		c.h:fireClient(REMOTES .. remote, ...)
	end

	local function wild(id, t0, extra)
		local w = { id = id, code = 1, x = 100, z = 20, seed = 7, t0 = t0 or T0, life = 30 }
		for k, v in extra or {} do
			w[k] = v
		end
		return w
	end

	local CODE_A = 1 -- Puffkin
	local CODE_B = 9 -- Bluebell Puff

	describe("WorldStateController › instantané d'arrivée", function()
		it(
			"applique files, miettes, sauvages, événements et équipages puis émet Ready une fois",
			function()
				local c = setup()
				expect(c.WSC.isReady()).toBe(false)
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, {
						lines = {
							{ slot = 3, userId = 1, ver = 4, codes = { CODE_A, CODE_B } },
							{ slot = 7, userId = 22, ver = 9, codes = { CODE_B } },
						},
						paths = c.PathCodec.encode(10, c.PathCodec.split(7, 500, straight(20))),
						wild = { wild(5), wild(6, T0, { personal = true }) },
						crews = { crews = { { id = 2, userIds = { 1, 22 } } } },
					})
				)
				expect(c.WSC.isReady()).toBe(true)
				expect(count(c, "Ready")).toBe(1)
				expect(c.WSC.localSlot()).toBe(3)
				expect(c.WSC.slotOf(22)).toBe(7)
				expect(c.WSC.userAt(7)).toBe(22)
				expect(c.WSC.userAt(5)).toBe(0)
				expect(c.WSC.lineLength(3)).toBe(2)
				expect(c.WSC.line(7).ver).toBe(9)
				local trail = c.WSC.trail(7)
				expect(trail:lastSeq()).toBe(519)
				expect(#trail.points).toBe(20)
				expect(c.WSC.wilds()[5] ~= nil).toBe(true)
				expect(c.WSC.wilds()[6].personal).toBe(true)
				expect(c.WSC.crewOf(22)).toBe(2)
				expect(c.WSC.isCrewmate(22)).toBe(true)
				expect(c.WSC.isCrewmate(1)).toBe(false)
				expect(c.WSC.events().activePlayers).toBe(1)
				-- un second instantané remplace tout sans réémettre Ready
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 3, userId = 1, ver = 6, codes = {} } } })
				)
				expect(count(c, "Ready")).toBe(1)
				expect(c.WSC.line(7)).toBeNil()
				expect(c.WSC.lineLength(3)).toBe(0)
				expect(c.WSC.wilds()[5]).toBeNil()
				expect(#c.h:warnings()).toBe(0)
			end
		)

		it("sans instantané au bout de 5 s, redemande le monde (au plus 1 / 2 s)", function()
			local c = setup()
			c.h:step(1 / 60, 2)
			expect(#requests(c, "RequestWorld")).toBe(0)
			c.Clock.advance(5.1)
			c.h:step(1 / 60, 2)
			expect(#requests(c, "RequestWorld")).toBe(1)
			c.WSC.requestWorld()
			expect(#requests(c, "RequestWorld")).toBe(1)
			c.Clock.advance(2.1)
			c.WSC.requestWorld()
			expect(#requests(c, "RequestWorld")).toBe(2)
		end)
	end)

	describe("WorldStateController › ordre des versions (LineEvent + SnipEvent)", function()
		it(
			"applique dans l'ordre strict de ver, met en attente les ops en avance et ignore les doublons",
			function()
				local c = setup()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 2, userId = 9, ver = 0, codes = {} } } })
				)
				fire(c, "LineEvent", {
					{ op = "add", slot = 2, ver = 1, codes = { CODE_A }, ids = { 0 } },
					{ op = "add", slot = 2, ver = 3, codes = { CODE_B, CODE_B }, ids = { 0, 0 } },
				})
				expect(c.WSC.lineLength(2)).toBe(1)
				expect(c.WSC.line(2).ver).toBe(1)
				-- la coupe (ver 2) arrive par SnipEvent : elle débloque l'op 3
				fire(c, "SnipEvent", {
					snipperSlot = 4,
					victimSlot = 2,
					ver = 2,
					cutIndex = 1,
					count = 1,
					looseIds = { 40 },
					loose = {
						wild(40, T0, { fromX = 90, fromZ = 10, prioritySlot = 2, dizzyUntil = T0 + 1.2 }),
					},
					byWisp = false,
					x = 90,
					y = 3,
					z = 10,
					dust = 5,
				})
				expect(c.WSC.line(2).ver).toBe(3)
				expect(c.WSC.line(2).codes).toEqual({ CODE_B, CODE_B })
				local order = {}
				for _, e in c.log do
					if e.name == "LineOp" then
						table.insert(order, e.args[2].ver)
					elseif e.name == "Snipped" then
						table.insert(order, "snip" .. e.args[1].ver)
					end
				end
				expect(order).toEqual({ 1, "snip2", 3 })
				-- doublon et op ancienne ignorés
				fire(c, "LineEvent", { { op = "add", slot = 2, ver = 3, codes = { CODE_A }, ids = { 0 } } })
				expect(c.WSC.lineLength(2)).toBe(2)
				-- le libre de la coupe est un sauvage avec arc de dispersion et priorité
				local w = c.WSC.wilds()[40]
				expect(w.prioritySlot).toBe(2)
				expect(w.from ~= nil).toBe(true)
				expect(w.dizzyUntil).toBe(T0 + 1.2)
				expect(#requests(c, "RequestWorld")).toBe(0)
			end
		)

		it(
			"trou persistant plus de 1 s → RequestWorld ; l'instantané rejoue les ops plus récentes",
			function()
				local c = setup()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 5, userId = 9, ver = 2, codes = { CODE_A } } } })
				)
				fire(c, "LineEvent", { { op = "add", slot = 5, ver = 5, codes = { CODE_B }, ids = { 0 } } })
				expect(c.WSC.line(5).ver).toBe(2)
				c.Clock.advance(0.5)
				c.h:step(1 / 60, 2)
				expect(#requests(c, "RequestWorld")).toBe(0)
				c.Clock.advance(0.6)
				c.h:step(1 / 60, 2)
				expect(#requests(c, "RequestWorld")).toBe(1)
				-- instantané à ver 4 : l'op 5 en attente s'applique ensuite
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 5, userId = 9, ver = 4, codes = { CODE_A, CODE_A } } } })
				)
				expect(c.WSC.line(5).ver).toBe(5)
				expect(c.WSC.line(5).codes).toEqual({ CODE_A, CODE_A, CODE_B })
				c.Clock.advance(3)
				c.h:step(1 / 60, 2)
				expect(#requests(c, "RequestWorld")).toBe(1)
			end
		)

		it(
			"op owner : nouvelle vie (file et miettes vidées, numérotation continue), 0 = Nid libre",
			function()
				local c = setup()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, {
						lines = { { slot = 4, userId = 9, ver = 7, codes = { CODE_A } } },
						paths = c.PathCodec.encode(10, c.PathCodec.split(4, 100, straight(10))),
					})
				)
				expect(c.WSC.trail(4):lastSeq()).toBe(109)
				fire(c, "LineEvent", {
					{ op = "clear", slot = 4, ver = 8, reason = "leave", loose = {} },
					{ op = "owner", slot = 4, ver = 0, userId = 0 },
				})
				expect(c.WSC.line(4)).toBeNil()
				expect(c.WSC.userAt(4)).toBe(0)
				expect(c.WSC.previousCodes(4)).toEqual({})
				fire(c, "LineEvent", { { op = "owner", slot = 4, ver = 0, userId = 31 } })
				expect(c.WSC.line(4).ver).toBe(0)
				expect(c.WSC.slotOf(31)).toBe(4)
				local trail = c.WSC.trail(4)
				expect(#trail.points).toBe(0)
				expect(trail:lastSeq()).toBe(109)
				-- le nouveau propriétaire reprend à 110 : aucun trou
				fire(c, "PathStream", encode(c, 11, 4, 110, straight(3, 50)))
				expect(#requests(c, "RequestPath")).toBe(0)
				expect(trail:lastSeq()).toBe(112)
				local owners = events(c, "OwnerChanged")
				expect(owners[#owners][1]).toBe(4)
				expect(owners[#owners][2]).toBe(31)
				fire(c, "LineEvent", { { op = "add", slot = 4, ver = 1, codes = { CODE_B }, ids = { 0 } } })
				expect(c.WSC.lineLength(4)).toBe(1)
			end
		)

		it("parade, vidange et capture : signaux, codes précédents, sauvages retirés", function()
			local c = setup()
			fire(
				c,
				"WorldSnapshot",
				snapshot(c, {
					lines = { { slot = 1, userId = 1, ver = 0, codes = {} } },
					wild = { wild(12), wild(13) },
				})
			)
			fire(
				c,
				"LineEvent",
				{ { op = "add", slot = 1, ver = 1, codes = { CODE_A, CODE_B }, ids = { 12, 99 } } }
			)
			local caught = events(c, "Caught")
			expect(#caught).toBe(2)
			expect(caught[1][1]).toBe(1)
			expect(caught[1][3]).toBe(12)
			local expected = c.WSC.wildPosition(
				{ anchor = V(100, c.WorldLayout.groundY(100, 20), 20), seed = 7, t0 = T0, from = nil },
				T0
			)
			expect((caught[1][4] - expected).Magnitude < 1e-6).toBe(true)
			expect(caught[2][4]).toBeNil() -- sauvage 99 jamais reçu
			expect(c.WSC.wilds()[12]).toBeNil()
			local removed = events(c, "WildRemoved")
			expect(removed[1][1]).toBe(12)
			expect(removed[1][2]).toBe("caught")
			expect(removed[1][3]).toBe(1)
			-- apparition tardive de 12 et de 99 ignorée (ids retirés 5 s)
			fire(c, "WildEvent", { spawns = { wild(12), wild(99) }, despawns = {} })
			expect(c.WSC.wilds()[12]).toBeNil()
			expect(c.WSC.wilds()[99]).toBeNil()
			-- parade
			fire(c, "LineEvent", {
				{
					op = "bank",
					slot = 1,
					ver = 2,
					count = 2,
					glow = 120,
					bonus = 1.08,
					atBeacon = false,
					newEntries = 1,
				},
			})
			expect(c.WSC.lineLength(1)).toBe(0)
			expect(c.WSC.previousCodes(1)).toEqual({ CODE_A, CODE_B })
			local banked = events(c, "Banked")
			expect(banked[1][2].glow).toBe(120)
			-- vidange à la mort : libres prioritaires pour le propriétaire
			fire(c, "LineEvent", { { op = "add", slot = 1, ver = 3, codes = { CODE_A }, ids = { 0 } } })
			fire(c, "LineEvent", {
				{
					op = "clear",
					slot = 1,
					ver = 4,
					reason = "death",
					loose = { wild(70, T0, { prioritySlot = 1 }) },
				},
			})
			expect(c.WSC.lineLength(1)).toBe(0)
			expect(c.WSC.wilds()[70].prioritySlot).toBe(1)
			local cleared = events(c, "Cleared")
			expect(cleared[1][2]).toBe("death")
			-- après 5 s, l'id 12 peut renaître (nouvelle apparition plus récente)
			c.Clock.advance(5.5)
			c.h:step(1 / 60, 2)
			fire(c, "WildEvent", { spawns = { wild(12, T0 + 5.5) }, despawns = {} })
			expect(c.WSC.wilds()[12] ~= nil).toBe(true)
		end)
	end)

	describe("WorldStateController › miettes (PathStream, PathSnapshot)", function()
		it(
			"ignore les points connus, détecte un trou (RequestPath ≤ 1 / s) et ignore les paquets en retard",
			function()
				local c = setup()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 6, userId = 9, ver = 0, codes = {} } } })
				)
				fire(c, "PathStream", encode(c, 20, 6, 1, straight(5)))
				local trail = c.WSC.trail(6)
				expect(trail:lastSeq()).toBe(5)
				-- répétition des 2 derniers points + 2 nouveaux
				fire(c, "PathStream", encode(c, 21, 6, 4, straight(4, 3)))
				expect(trail:lastSeq()).toBe(7)
				expect(#trail.points).toBe(7)
				expect(#requests(c, "RequestPath")).toBe(0)
				-- trou : seq 8-9 perdus
				fire(c, "PathStream", encode(c, 23, 6, 10, straight(2, 9)))
				local req = requests(c, "RequestPath")
				expect(#req).toBe(1)
				expect(req[1][1]).toBe(6)
				-- la numérotation reste celle du serveur (trou comblé)
				expect(trail:lastSeq()).toBe(11)
				fire(c, "PathStream", encode(c, 24, 6, 13, straight(1, 20)))
				expect(#requests(c, "RequestPath")).toBe(1) -- au plus 1 / s par slot
				c.Clock.advance(1.1)
				fire(c, "PathStream", encode(c, 25, 6, 16, straight(1, 30)))
				expect(#requests(c, "RequestPath")).toBe(2)
				-- paquet en retard (tick plus ancien) ignoré
				local before = trail:lastSeq()
				fire(c, "PathStream", encode(c, 22, 6, 17, straight(3, 40)))
				expect(c.WSC.trail(6):lastSeq()).toBe(before)
				-- le compteur de ticks avance puis reboucle (65535 → 0) : paquets acceptés
				fire(c, "PathStream", encode(c, 30000, 6, before + 1, straight(1, 50)))
				fire(c, "PathStream", encode(c, 62000, 6, before + 2, straight(1, 51)))
				fire(c, "PathStream", encode(c, 65535, 6, before + 3, straight(1, 52)))
				fire(c, "PathStream", encode(c, 0, 6, before + 4, straight(1, 53)))
				expect(c.WSC.trail(6):lastSeq()).toBe(before + 4)
			end
		)

		it("PathSnapshot remplace le miroir et rejoue les points plus récents déjà reçus", function()
			local c = setup()
			fire(
				c,
				"WorldSnapshot",
				snapshot(c, { lines = { { slot = 8, userId = 9, ver = 0, codes = {} } } })
			)
			fire(c, "PathStream", encode(c, 30, 8, 300, straight(3, 0)))
			fire(c, "PathStream", encode(c, 31, 8, 310, straight(3, 10))) -- trou 303-309
			expect(#requests(c, "RequestPath")).toBe(1)
			-- l'instantané couvre 250-311 ; 312 est déjà connu par le flux
			local snapPoints = straight(62, -61)
			fire(c, "PathSnapshot", 8, encode(c, 31, 8, 250, snapPoints))
			local trail = c.WSC.trail(8)
			expect(trail.firstSeq).toBe(250)
			expect(trail:lastSeq()).toBe(312)
			expect(#trail.points).toBe(63)
			-- les runs d'un autre slot et un slot invalide sont ignorés
			fire(c, "PathSnapshot", 9, encode(c, 31, 8, 1, straight(2)))
			fire(c, "PathSnapshot", 0, encode(c, 31, 8, 1, straight(2)))
			expect(c.WSC.trail(9)).toBeNil()
			expect(c.WSC.trail(8):lastSeq()).toBe(312)
		end)
	end)

	describe("WorldStateController › sauvages, positions et événements", function()
		it("expire localement, suit la flânerie et l'arc de dispersion du serveur", function()
			local c = setup()
			fire(c, "WorldSnapshot", snapshot(c))
			fire(c, "WildEvent", {
				spawns = { wild(3, T0, { life = 2 }), wild(4, T0, { fromX = 80, fromZ = 0 }) },
				despawns = {},
			})
			expect(count(c, "WildAdded")).toBe(2)
			local w4 = c.WSC.wilds()[4]
			local mid = c.WSC.wildPosition(w4, T0 + c.Balance.Snip.ScatterTime / 2)
			local from = V(80, c.WorldLayout.groundY(80, 0), 0)
			local anchor = w4.anchor
			expect((mid - (from + (anchor - from) * 0.5)).Magnitude < 1e-3).toBe(true)
			local later = c.WSC.wildPosition(w4, T0 + 10)
			expect((later - (anchor + c.SeededPath.wander(7, 10))).Magnitude < 1e-3).toBe(true)
			c.Clock.advance(2.5)
			c.h:step(1 / 60, 2)
			expect(c.WSC.wilds()[3]).toBeNil()
			local removed = events(c, "WildRemoved")
			expect(removed[1][1]).toBe(3)
			expect(removed[1][2]).toBe("expired")
			-- disparition annoncée par le serveur
			fire(c, "WildEvent", { spawns = {}, despawns = { { id = 4, reason = "cleared" } } })
			expect(c.WSC.wilds()[4]).toBeNil()
			-- apparition déjà expirée à la réception : ignorée
			fire(c, "WildEvent", { spawns = { wild(5, T0 - 100) }, despawns = {} })
			expect(c.WSC.wilds()[5]).toBeNil()
		end)

		it(
			"Gloomwisps (cordes déterministes), Comète (ciel, sol, porteur) et EventChanged(nouveau, ancien)",
			function()
				local c = setup()
				fire(c, "WorldSnapshot", snapshot(c))
				local ev = emptyEvents()
				ev.wisps =
					{ { id = 1, seed = 1234, t0 = T0 - 30 }, { id = 2, seed = 99, t0 = T0, poppedAt = T0 } }
				ev.comet = {
					id = T0 + 8,
					phase = "warn",
					x = 40,
					z = -30,
					code = 1700,
					warnAt = T0,
					impactAt = T0 + 8,
					burstAt = T0 + 83,
				}
				fire(c, "EventState", ev)
				local changed = events(c, "EventChanged")
				expect(changed[#changed][1]).toBe(ev)
				local p = c.WSC.wispPosition(1, T0 + 5)
				local ref = c.SeededPath.chordAt(1234, T0 - 30, T0 + 5)
				expect(math.abs(p.X - ref.X) < 1e-6 and math.abs(p.Z - ref.Z) < 1e-6).toBe(true)
				expect(p.Y).toBe(c.WorldLayout.groundY(p.X, p.Z))
				expect(c.WSC.wispPosition(2, T0)).toBeNil() -- éclaté
				expect(c.WSC.wispPosition(3, T0)).toBeNil() -- inconnu
				local impact = V(40, c.WorldLayout.groundY(40, -30), -30)
				local skyPos = c.WSC.cometPosition(T0 + 5)
				local alpha = (5 - (8 - c.Balance.Comet.SkySeconds)) / c.Balance.Comet.SkySeconds
				expect((skyPos - c.SeededPath.cometSky(T0 + 8, impact, alpha)).Magnitude < 1e-6).toBe(true)
				-- au sol
				local ground = table.clone(ev)
				ground.comet = table.clone(ev.comet)
				ground.comet.phase = "ground"
				fire(c, "EventState", ground)
				changed = events(c, "EventChanged")
				expect(changed[#changed][2]).toBe(ev)
				expect(c.WSC.cometPosition(T0 + 9)).toEqual(impact)
				-- portée par le joueur local : au-dessus de sa HumanoidRootPart
				local carried = table.clone(ground)
				carried.comet = table.clone(ground.comet)
				carried.comet.phase = "carried"
				carried.comet.carrierId = 1
				fire(c, "EventState", carried)
				local root = c.h.localPlayer.Character.HumanoidRootPart
				expect(c.WSC.cometPosition(T0 + 10)).toEqual(root.Position + V(0, 5, 0))
				local banked = table.clone(carried)
				banked.comet = table.clone(carried.comet)
				banked.comet.phase = "banked"
				fire(c, "EventState", banked)
				expect(c.WSC.cometPosition(T0 + 11)).toBeNil()
			end
		)

		it("pings : PingShown pour un kind 1-6 seulement", function()
			local c = setup()
			fire(c, "PingShow", { userId = 22, kind = 3 })
			fire(c, "PingShow", { userId = 22, kind = 7 })
			fire(c, "PingShow", { userId = 22, kind = 2.5 })
			fire(c, "PingShow", "ping")
			local shown = events(c, "PingShown")
			expect(#shown).toBe(1)
			expect(shown[1][1]).toBe(22)
			expect(shown[1][2]).toBe(3)
		end)
	end)

	describe("WorldStateController › charges malveillantes ou corrompues", function()
		it(
			"chaque remote ignore types faux, NaN, ±inf, tables mixtes ou énormes, sans erreur ni mutation",
			function()
				local c = setup()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 2, userId = 9, ver = 1, codes = { CODE_A } } } })
				)
				local nan = 0 / 0
				local huge = {}
				for i = 1, 5000 do
					huge[i] = { op = "add", slot = 2, ver = 2, codes = { CODE_A }, ids = { 0 } }
				end
				local mixed =
					{ { op = "add", slot = 2, ver = 2, codes = { CODE_A }, ids = { 0 } }, foo = "bar" }
				local bad = {
					{ "LineEvent", "x" },
					{ "LineEvent", huge },
					{ "LineEvent", mixed },
					{ "LineEvent", { { op = "add", slot = 2, ver = nan, codes = { CODE_A }, ids = { 0 } } } },
					{ "LineEvent", { { op = "add", slot = 13, ver = 2, codes = { CODE_A }, ids = { 0 } } } },
					{ "LineEvent", { { op = "add", slot = 2, ver = 2, codes = { 99999 }, ids = { 0 } } } },
					{
						"LineEvent",
						{ { op = "add", slot = 2, ver = 2, codes = { CODE_A }, ids = { math.huge } } },
					},
					{
						"LineEvent",
						{
							{
								op = "bank",
								slot = 2,
								ver = 2,
								count = 1,
								glow = nan,
								bonus = 1,
								atBeacon = false,
								newEntries = 0,
							},
						},
					},
					{ "LineEvent", { { op = "clear", slot = 2, ver = 2, reason = "boom", loose = {} } } },
					{ "LineEvent", { { op = "owner", slot = 2, ver = 3, userId = 5 } } },
					{ "LineEvent", { { op = "hack", slot = 2, ver = 2 } } },
					{ "SnipEvent", { victimSlot = 2, ver = 2 } },
					{
						"SnipEvent",
						{
							snipperSlot = 1,
							victimSlot = 2,
							ver = 2,
							cutIndex = 1,
							count = 1,
							looseIds = {},
							loose = {},
							byWisp = false,
							x = nan,
							y = 0,
							z = 0,
							dust = 0,
						},
					},
					{ "WildEvent", 42 },
					{
						"WildEvent",
						{
							spawns = { { id = 1, code = 1, x = nan, z = 0, seed = 1, t0 = T0, life = 9 } },
							despawns = {},
						},
					},
					{
						"WildEvent",
						{ spawns = { { id = 70000, code = 1, x = 0, z = 0, seed = 1, t0 = T0, life = 9 } } },
					},
					{
						"WildEvent",
						{ spawns = { { id = 3, code = 1, x = 0, z = 0, seed = 1, t0 = T0, life = -1 } } },
					},
					{ "WildEvent", { despawns = { { id = 3, reason = "nuked" } } } },
					{ "EventState", { t = nan, wisps = {} } },
					{ "EventState", { t = T0, wisps = { { id = 1, seed = math.huge, t0 = T0 } } } },
					{
						"EventState",
						{
							t = T0,
							wisps = {},
							comet = { id = 1, phase = "warn", x = nan, z = 0, impactAt = 0, warnAt = 0 },
						},
					},
					{ "CrewState", { crews = "all" } },
					{ "CrewState", { crews = { { id = nan, userIds = { 1 } } } } },
					{ "PathStream", "not a buffer" },
					{ "PathStream", buffer.create(2) },
					{ "PathSnapshot", 2, buffer.create(5) },
					{ "PathSnapshot", nan, buffer.create(3) },
					{ "WorldSnapshot", "snapshot" },
				}
				local evBefore = c.WSC.events()
				for _, case in bad do
					fire(c, case[1], table.unpack(case, 2))
				end
				c.h:step(1 / 60, 3)
				expect(c.WSC.lineLength(2)).toBe(1)
				expect(c.WSC.line(2).ver).toBe(1)
				expect(c.WSC.userAt(2)).toBe(9)
				expect(next(c.WSC.wilds())).toBeNil()
				expect(c.WSC.events()).toBe(evBefore)
				expect(#c.WSC.crews().crews).toBe(0)
				expect(c.WSC.trail(2)).toBeNil()
				expect(count(c, "Snipped")).toBe(0)
				expect(count(c, "Banked")).toBe(0)
				expect(#c.h:warnings()).toBe(0)
				-- les ops légitimes passent toujours
				fire(c, "LineEvent", { { op = "add", slot = 2, ver = 2, codes = { CODE_B }, ids = { 0 } } })
				expect(c.WSC.lineLength(2)).toBe(2)
			end
		)
	end)

	describe("WorldStateController › cycle de vie", function()
		it(
			"ops reçues avant l'instantané : mises en attente puis rejouées ; slot local par l'attribut",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 11)
				expect(c.WSC.localSlot()).toBe(11)
				fire(c, "LineEvent", { { op = "add", slot = 11, ver = 3, codes = { CODE_A }, ids = { 0 } } })
				expect(c.WSC.line(11)).toBeNil()
				fire(
					c,
					"WorldSnapshot",
					snapshot(c, { lines = { { slot = 11, userId = 1, ver = 2, codes = {} } } })
				)
				expect(c.WSC.lineLength(11)).toBe(1)
				expect(c.WSC.line(11).ver).toBe(3)
				expect(c.WSC.localSlot()).toBe(11)
				expect(c.WSC.slotOf(424242)).toBe(0)
				-- démarrage idempotent : aucun double abonnement
				c.WSC.Start()
				fire(c, "LineEvent", { { op = "add", slot = 11, ver = 4, codes = { CODE_B }, ids = { 0 } } })
				expect(c.WSC.lineLength(11)).toBe(2)
			end
		)
	end)

	-- Revue du paquet : chaque test reproduit un bogue corrigé
	describe("WorldStateController › revue (bogues corrigés)", function()
		it(
			"ops en attente d'un slot que l'instantané déclare libre : abandonnées, pas de RequestWorld sans fin",
			function()
				local c = setup()
				fire(c, "LineEvent", { { op = "add", slot = 9, ver = 3, codes = { CODE_A }, ids = { 0 } } })
				fire(c, "WorldSnapshot", snapshot(c, { lines = {} }))
				for _ = 1, 4 do
					c.Clock.advance(1.1)
					c.h:step(1 / 60, 2)
				end
				expect(#requests(c, "RequestWorld")).toBe(0)
				-- un propriétaire arrive ensuite : aucune op fantôme rejouée
				fire(c, "LineEvent", { { op = "owner", slot = 9, ver = 0, userId = 44 } })
				fire(c, "LineEvent", { { op = "add", slot = 9, ver = 1, codes = { CODE_B }, ids = { 0 } } })
				expect(c.WSC.line(9).codes).toEqual({ CODE_B })
			end
		)

		it("instantané sans liste de files lisible : ignoré, aucune file effacée", function()
			local c = setup()
			fire(
				c,
				"WorldSnapshot",
				snapshot(c, { lines = { { slot = 2, userId = 9, ver = 1, codes = { CODE_A } } } })
			)
			for _, bad in { "x", 42, { foo = 1 } } do
				fire(c, "WorldSnapshot", snapshot(c, { lines = bad }))
			end
			local missing = snapshot(c)
			missing.lines = nil
			fire(c, "WorldSnapshot", missing)
			expect(c.WSC.userAt(2)).toBe(9)
			expect(c.WSC.lineLength(2)).toBe(1)
			expect(count(c, "OwnerChanged")).toBe(1)
		end)

		it("UserId négatifs (serveur de test « Local Server » de Studio) acceptés partout", function()
			local c = setup()
			fire(c, "LineEvent", { { op = "owner", slot = 3, ver = 0, userId = -2 } })
			expect(c.WSC.userAt(3)).toBe(-2)
			expect(c.WSC.slotOf(-2)).toBe(3)
			fire(
				c,
				"WorldSnapshot",
				snapshot(c, {
					lines = {
						{ slot = 3, userId = -2, ver = 0, codes = {} },
						{ slot = 4, userId = -1, ver = 2, codes = { CODE_A } },
					},
					crews = { crews = { { id = 1, userIds = { -1, -2 } } } },
				})
			)
			expect(c.WSC.userAt(4)).toBe(-1)
			expect(c.WSC.lineLength(4)).toBe(1)
			expect(c.WSC.crewOf(-1)).toBe(1)
			expect(c.WSC.crewOf(-2)).toBe(1)
			fire(c, "PingShow", { userId = -1, kind = 2 })
			expect(count(c, "PingShown")).toBe(1)
			local ev = emptyEvents()
			ev.comet = {
				id = 600,
				phase = "carried",
				x = 0,
				z = 0,
				code = 1,
				warnAt = T0 - 8,
				impactAt = T0,
				burstAt = T0 + 75,
				carrierId = -1,
				carrierSince = T0,
			}
			fire(c, "EventState", ev)
			expect(c.WSC.events()).toBe(ev)
		end)

		it("EventState aux champs lus chaque image mal typés : ignoré (le rendu ne casse pas)", function()
			local c = setup()
			local good = emptyEvents()
			fire(c, "EventState", good)
			expect(c.WSC.events()).toBe(good)
			local function comet(extra)
				local cm = {
					id = 600,
					phase = "carried",
					x = 0,
					z = 0,
					code = 1,
					warnAt = T0 - 8,
					impactAt = T0,
					burstAt = T0 + 75,
				}
				for k, v in extra do
					cm[k] = v
				end
				return cm
			end
			local beacon = {
				phase = "active",
				warnAt = T0 - 15,
				startsAt = T0,
				endsAt = T0 + 180,
				points = 3,
				goal = 50,
			}
			local cases = {
				{ comet = comet({ carrierId = "abc" }) },
				{ comet = comet({ carrierId = 0.5 }) },
				{ comet = comet({ burstAt = 0 / 0 }) },
				{
					beacon = {
						phase = "active",
						warnAt = T0,
						startsAt = "now",
						endsAt = T0 + 180,
						points = 0,
						goal = 1,
					},
				},
				{
					beacon = {
						phase = 3,
						warnAt = T0,
						startsAt = T0,
						endsAt = T0 + 180,
						points = 0,
						goal = 1,
					},
				},
				{ weather = { key = "rain", startsAt = T0 } },
				{ frenzy = { endsAt = math.huge } },
				{ serverBoost = "yes" },
				{ starfall = { startsAt = T0, endsAt = {} } },
			}
			for _, extra in cases do
				local ev = emptyEvents()
				for k, v in extra do
					ev[k] = v
				end
				fire(c, "EventState", ev)
			end
			expect(c.WSC.events()).toBe(good)
			-- un état complet et bien formé passe
			local full = emptyEvents()
			full.beacon = beacon
			full.weather = { key = "rain", startsAt = T0, endsAt = T0 + 150 }
			full.frenzy = { endsAt = T0 + 60 }
			full.serverBoost = { endsAt = T0 + 60, source = "liveOps" }
			full.starfall = { startsAt = T0, endsAt = T0 + 1200, featured = 3 }
			full.comet = comet({ carrierId = 5, carrierSince = T0, prevCarrierId = 4 })
			fire(c, "EventState", full)
			expect(c.WSC.events()).toBe(full)
			expect(#c.h.errors).toBe(0)
		end)

		it("position d'un Gloomwisp : curseurs monotones malgré la sonde t + 0,2 s du rendu", function()
			local c = setup()
			local SP = c.SeededPath
			local original = SP.newChordCursor
			local backwards = 0
			SP.newChordCursor = function(seed, t0)
				local inner = original(seed, t0)
				local last = -math.huge
				return {
					at = function(_, t)
						if t < last then
							backwards += 1 -- le curseur repartirait du début de la trajectoire
						end
						last = t
						return inner:at(t)
					end,
					ahead = function(_, ...)
						return inner:ahead(...)
					end,
				}
			end
			local born = T0 - 6 * 3600 -- Gloomwisp vivant depuis 6 h
			local ev = emptyEvents()
			ev.wisps = { { id = 1, seed = 77, t0 = born } }
			fire(c, "EventState", ev)
			local t = T0
			for _ = 1, 600 do -- 10 s d'images à 60 Hz (au moins une fin de corde)
				t += 1 / 60
				c.WSC.wispPosition(1, t)
				c.WSC.wispPosition(1, t + 0.2)
			end
			expect(backwards).toBe(0)
			-- exactitude : identique au calcul direct, y compris en revenant en arrière
			for _, at in { t, t + 0.2, t - 30, T0 } do
				local p = c.WSC.wispPosition(1, at)
				local ref = original(77, born):at(at)
				expect(math.abs(p.X - ref.X) < 1e-6 and math.abs(p.Z - ref.Z) < 1e-6).toBe(true)
			end
			expect(c.WSC.wispPosition(1, 0 / 0)).toBeNil()
		end)
	end)
end
