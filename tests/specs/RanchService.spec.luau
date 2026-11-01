--!nocheck
-- RanchService (paquet ranch, docs/04 §5.4, §11.4, §18.2) : attribution (amis voisins), placement,
-- PlayerReady (au premier placement, au plus tard 15 s après), serveur plein (renvoi à 30 s, annulé si
-- un ranch se libère), intrus repoussés, Pot à l'entrée, dalles (attente de 0,6 s, une fois par entrée,
-- annulée en portant ou dans un autre maintien, HoldState « tile », onPad, achat au premier tick où les
-- pièces suffisent : A24), clôtures dans les deux ordres Rush / pet-sitting (A25), best.s = 0 (A27),
-- patchs numérotés par destinataire, RequestWorld, départ, délais des états, zéro trace.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	-- Serveur complet ; Diagnostics compté (erreurs attrapées = échec du test)
	local function boot(before)
		local caught, timedOut = {}, {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function(name)
					table.insert(timedOut, name)
				end
				if before then
					before(w)
				end
			end,
		})
		w.caught, w.timedOut = caught, timedOut
		w.Ranch = w.h:require(S .. "RanchService")
		w.Economy = w.h:require(S .. "EconomyService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		w.Pads = w.h:require("ReplicatedStorage.Shared.Config.Pads")
		w.Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function actor(w, p, pos, canAct)
		return {
			player = p,
			slot = w.Ranch.slotOf(p),
			pos = pos,
			canAct = canAct ~= false,
			riding = false,
			rootOffset = 0,
		}
	end

	-- Position d'un joueur debout au point local (x, z) de son ranch
	local function at(w, p, x, z)
		local q = w.W.toWorld(w.Ranch.slotOf(p), w.V3.new(x, 0, z))
		return w.V3.new(q.X, 3, q.Z)
	end

	local function padPos(w, p, tile)
		local c = w.W.padSocket(w.Ranch.slotOf(p), w.Pads.Defs[tile].socket)
		return w.V3.new(c.X, 3, c.Z)
	end

	-- Un tick du ranch à l'instant now (+ flush)
	local function tick(w, actors)
		w.Ranch.step(w.Clock.now(), actors)
		w.Ranch.flush()
	end

	local function holds(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "HoldState") do
			table.insert(out, args[1])
		end
		return out
	end

	-- Profil prêt pour les dalles : accueil fini (toutes les dalles allumées selon leurs règles)
	local function richProfile(w, coins)
		return Bots.profile(w, {
			coins = coins or 0,
			onboarding = { step = 11, done = true, demoDone = true },
			lastOnline = 0,
		})
	end

	describe("RanchService › attribution et placement", function()
		it(
			"plus petit numéro libre ; RanchSlot ; propriétaire posé dans le monde ; placé face au Pot",
			function()
				local w = boot()
				local a = Bots.join(1)
				local b = Bots.join(2)
				w.h:settle(3)
				expect(w.Ranch.slotOf(a)).toBe(1)
				expect(w.Ranch.slotOf(b)).toBe(2)
				expect(a:GetAttribute("RanchSlot")).toBe(1)
				expect(w.Ranch.playerAt(2)).toBe(b)
				expect(w.Ranch.playerAt(3)).toBeNil()
				expect(w.Ranch.playerAt(0 / 0)).toBeNil()
				local model = w.h.game.Workspace.Wobbleton.Ranches["1"]
				expect(model:GetAttribute("OwnerUserId")).toBe(1)
				local root = a.Character.HumanoidRootPart
				local spawn = w.W.spawnCFrame(1).Position
				expect((root.Position - spawn).Magnitude < 1e-3).toBe(true)
				clean(w)
			end
		)

		it("ami Roblox présent : ranch libre le plus proche du sien (IsFriendsWith en cache)", function()
			local w = boot()
			local players = {}
			for i = 1, 5 do
				players[i] = Bots.join(10 + i)
			end
			-- libère le ranch 3, puis un ami du joueur du ranch 5 arrive : 6 (voisin) plutôt que 3
			Bots.leave(players[3])
			w.h:makeFriends(15, 99)
			local friend = Bots.join(99)
			w.h:settle(3)
			expect(w.Ranch.slotOf(friend)).toBe(6)
			-- sans ami : le plus petit libre
			local stranger = Bots.join(77)
			expect(w.Ranch.slotOf(stranger)).toBe(3)
			clean(w)
		end)

		it(
			"PlayerReady une seule fois, au premier placement après le chargement ; instantané envoyé",
			function()
				local w = boot()
				local ready = {}
				w.Signals.PlayerReady:Connect(function(p, slot)
					table.insert(ready, { p = p, slot = slot })
				end)
				local p = Bots.join(1)
				w.h:settle(3)
				expect(#ready).toBe(1)
				expect(ready[1].slot).toBe(1)
				expect(w.Ranch.isReady(p)).toBe(true)
				local snaps = w.h:sentTo(p, "RanchSnapshot")
				expect(#snaps).toBe(1)
				local snap = snaps[1][1]
				expect(snap.ranches["1"].userId).toBe(1)
				expect(snap.ranches["2"].userId).toBe(0)
				-- best toujours présent, s = 0 = aucune silhouette (remarque A27)
				expect(snap.ranches["2"].best).toEqual({ s = 0, m = 0, z = 0, zg = 0 })
				-- réapparition : replacé, PlayerReady n'est pas réémis
				w.h:respawn(p)
				w.h:settle(2)
				expect(#ready).toBe(1)
				clean(w)
			end
		)

		it(
			"sans HumanoidRootPart : PlayerReady au plus tard 15 s après le chargement (repli neutre)",
			function()
				local w = boot()
				local ready = 0
				w.Signals.PlayerReady:Connect(function()
					ready += 1
				end)
				local p = Bots.join(1, { spawn = false })
				w.h:settle(3)
				expect(ready).toBe(0)
				local open = w.Ranch.openStates()
				expect(#open).toBe(1)
				expect(open[1].name).toBe("playerReady")
				w.Clock.advance(14.9)
				tick(w, {})
				expect(ready).toBe(0)
				w.Clock.advance(0.2)
				tick(w, {})
				w.h:settle(1)
				expect(ready).toBe(1)
				expect(w.timedOut).toEqual({ "playerReady" })
				expect(#w.Ranch.openStates()).toBe(0)
				expect(#w.h:sentTo(p, "RanchSnapshot")).toBe(1)
				clean(w)
			end
		)

		it(
			"serveur plein : message, renvoi après 30 s dans sa langue ; annulé si un ranch se libère",
			function()
				local w = boot()
				local players = {}
				for i = 1, 16 do
					players[i] = Bots.join(i)
				end
				local late = Bots.join(100, { locale = "fr-fr" })
				local late2 = Bots.join(101)
				w.h:settle(3)
				expect(w.Ranch.slotOf(late)).toBe(0)
				local fb = w.h:sentTo(late, "Feedback")
				expect(fb[#fb][1].key).toBe("feedback.serverFull")
				local names = {}
				for _, s in w.Ranch.openStates() do
					names[s.name] = (names[s.name] or 0) + 1
				end
				expect(names.serverFull).toBe(2)
				-- un ranch se libère : le plus ancien en attente le reçoit, plus de renvoi pour lui
				w.Clock.advance(10)
				Bots.leave(players[4])
				w.h:settle(3)
				expect(w.Ranch.slotOf(late)).toBe(4)
				w.Clock.advance(20.5)
				tick(w, {})
				w.h:settle(1)
				expect(#w.h.log.kicks).toBe(1)
				expect(w.h.log.kicks[1].player).toBe(late2)
				expect(w.h.log.kicks[1].message).toBe("Wobbleton is full! Join another server.")
				clean(w)
			end
		)

		it("renvoi en français pour un joueur fr", function()
			local w = boot()
			for i = 1, 16 do
				Bots.join(i)
			end
			local late = Bots.join(100, { locale = "fr-fr" })
			w.Clock.advance(30.1)
			tick(w, {})
			w.h:settle(1)
			expect(w.h.log.kicks[1].player).toBe(late)
			expect(w.h.log.kicks[1].message).toBe("Wobbleton est pleine ! Rejoins un autre serveur.")
			clean(w)
		end)
	end)

	describe("RanchService › cycle de vie", function()
		it("joueur présent avant le démarrage : ranch attribué, placé, prêt", function()
			local caught = {}
			local h = Harness.new()
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(T0)
			local DS = h:require(S .. "DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			DS.Settings.AUTOSAVE_INTERVAL = 1e6
			local Diag = h:require(S .. "DiagnosticsService")
			Diag.reportCaught = function(where, err)
				table.insert(caught, where .. " : " .. tostring(err))
			end
			local early = h:addPlayer({ userId = 5, name = "Early" })
			h:boot()
			DS.waitFor(early, 2)
			h:settle(3)
			local Ranch = h:require(S .. "RanchService")
			expect(Ranch.slotOf(early)).toBe(1)
			expect(Ranch.isReady(early)).toBe(true)
			expect(table.concat(caught, "\n")).toBe("")
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)

		it(
			"personnage sans HumanoidRootPart : état « characterPlace » fermé par son délai (10 s), repli neutre",
			function()
				local w = boot()
				local p = Bots.join(1, { spawn = false })
				local char = w.h.makeCharacter(p)
				char.HumanoidRootPart:Destroy()
				p.Character = char
				char.Parent = w.h.game.Workspace
				p.CharacterAdded:Fire(char)
				w.h:settle(1)
				local names = {}
				for _, st in w.Ranch.openStates() do
					names[st.name] = true
				end
				expect(names.characterPlace).toBe(true)
				w.Clock.advance(10.1)
				tick(w, {})
				names = {}
				for _, st in w.Ranch.openStates() do
					names[st.name] = true
				end
				expect(names.characterPlace).toBeNil()
				-- PlayerReady arrive quand même au plus tard 15 s après le chargement
				w.Clock.advance(5)
				tick(w, {})
				expect(w.Ranch.isReady(p)).toBe(true)
				clean(w)
			end
		)

		it(
			"profil chargé AVANT l'attribution (IsFriendsWith lent) : squishies, silhouette et selle publiés quand même",
			function()
				local w = boot(function(w)
					local d = richProfile(w, 0)
					d.squishies = {
						["1"] = {
							s = 1,
							m = 0,
							st = 0,
							z = 2000,
							zg = 0,
							bf = 1,
							lk = false,
							o = "",
							at = "pen",
							b = 1,
							gd = 0,
						},
					}
					d.nextUid = 2
					d.biggestEver = 2000
					Bots.saveProfile(w, 2, d)
				end)
				local a = Bots.join(1)
				local MockInstance = require("../harness/MockInstance")
				local task = require("@lune/task")
				local original = MockInstance.areFriends
				MockInstance.areFriends = function()
					task.wait(0.3) -- appel web lent : le profil arrive avant
					return false
				end
				local late = Bots.join(2, { wait = false })
				w.DS.waitFor(late, 2)
				expect(w.Ranch.slotOf(late)).toBe(0)
				task.wait(0.5)
				w.h:settle(3)
				MockInstance.areFriends = original
				local slot = w.Ranch.slotOf(late)
				expect(slot).toBe(2)
				w.Ranch.flush()
				w.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", a)
				local snaps = w.h:sentTo(a, "RanchSnapshot")
				local snap = snaps[#snaps][1]
				expect(snap.squishies["2"]["1"] ~= nil).toBe(true)
				expect(snap.ranches["2"].best.s).toBe(1)
				expect(snap.ranches["2"].saddle).toBe(1)
				expect(snap.ranches["2"].userId).toBe(2)
				clean(w)
			end
		)

		it("départ pendant la vérification des amis : aucun ranch attribué, rien ne reste", function()
			local w = boot()
			local a = Bots.join(1)
			local MockInstance = require("../harness/MockInstance")
			local task = require("@lune/task")
			local original = MockInstance.areFriends
			local leaving = nil
			MockInstance.areFriends = function(x, y)
				task.wait() -- IsFriendsWith cède (appel web)
				return original and original(x, y) or false
			end
			leaving = w.h:addPlayer({ userId = 2, spawn = false })
			w.h:removePlayer(leaving)
			w.h:settle(3)
			MockInstance.areFriends = original
			expect(w.Ranch.slotOf(leaving)).toBe(0)
			expect(w.Ranch.playerAt(2)).toBeNil()
			expect(w.Ranch.slotOf(a)).toBe(1)
			clean(w)
		end)
	end)

	describe("RanchService › tick : intrus et Pot", function()
		it(
			"intrus repoussé devant le portail (même sans canAct), « C'est le ranch de … » ; nom caché → n°",
			function()
				local w = boot(function(w)
					local d = Bots.profile(w, {})
					d.settings.hideName = true
					Bots.saveProfile(w, 2, d)
				end)
				local a = Bots.join(1, { name = "Mira" })
				local b = Bots.join(2, { name = "Noah" })
				local moved = {}
				w.Signals.ServerMoved:Connect(function(p)
					table.insert(moved, p)
				end)
				-- b dans le ranch de a, sans droit d'agir : repoussé quand même
				local inside = at(w, a, 0, 30)
				tick(w, { [b] = actor(w, b, inside, false) })
				w.h:settle(1)
				local out = w.W.gateOutside(1)
				expect((b.Character.HumanoidRootPart.Position - out).Magnitude < 1e-3).toBe(true)
				expect(moved[#moved]).toBe(b)
				local fb = w.h:sentTo(b, "Feedback")
				expect(fb[#fb][1]).toEqual({
					key = "feedback.ranchOf",
					vars = { name = "Mira" },
					tone = "info",
				})
				-- a chez b (nom caché) : « C'est le ranch 2 ! »
				tick(w, { [a] = actor(w, a, at(w, b, 5, 40)) })
				local fa = w.h:sentTo(a, "Feedback")
				expect(fa[#fa][1].key).toBe("feedback.ranchN")
				expect(fa[#fa][1].vars.n).toBe(2)
				-- chez soi : jamais repoussé
				local before = #moved
				tick(w, { [a] = actor(w, a, at(w, a, 5, 40)) })
				expect(#moved).toBe(before)
				clean(w)
			end
		)

		it("Pot : encaissé à l'entrée seulement (à plat, pieds) ; rien sans canAct", function()
			local w = boot()
			local p = Bots.join(1)
			local calls = {}
			w.Ranch.setZoneHandler("pot", function(player, key)
				table.insert(calls, { player, key })
			end)
			local pot = w.W.anchor(1, "pot")
			local on = w.V3.new(pot.X + 2, 3, pot.Z)
			local off = at(w, p, 0, 30)
			tick(w, { [p] = actor(w, p, on) })
			tick(w, { [p] = actor(w, p, on) })
			expect(#calls).toBe(1)
			expect(calls[1][2]).toBe("")
			tick(w, { [p] = actor(w, p, off) })
			tick(w, { [p] = actor(w, p, on, false) })
			expect(#calls).toBe(1)
			tick(w, { [p] = actor(w, p, on) })
			expect(#calls).toBe(2)
			-- trop haut (pieds à 9 studs du sol) : hors portée
			tick(w, { [p] = actor(w, p, off) })
			tick(w, { [p] = actor(w, p, w.V3.new(pot.X, 12.5, pot.Z)) })
			expect(#calls).toBe(2)
			-- monture : la hausse de la racine ne réduit jamais la portée
			tick(w, { [p] = actor(w, p, off) })
			local riding = actor(w, p, w.V3.new(pot.X, 3 + 6, pot.Z))
			riding.rootOffset = 6
			tick(w, { [p] = riding })
			expect(#calls).toBe(3)
			clean(w)
		end)
	end)

	describe("RanchService › dalles (attente de 0,6 s, remarque A24)", function()
		it(
			"entrée → anneau (HoldState « tile ») → achat à 0,6 s, une seule fois par entrée",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, richProfile(w, 1e6))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local mat = padPos(w, p, "snack")
				local off = at(w, p, 0, 30)
				tick(w, { [p] = actor(w, p, mat) })
				expect(w.Ranch.onPad(p)).toBe("snack")
				local h1 = holds(w, p)
				expect(#h1).toBe(1)
				expect(h1[1]).toEqual({ kind = "tile", endsAt = T0 + 0.6, active = true, tile = "snack" })
				local open = w.Ranch.openStates()
				expect(open[1].name).toBe("tileDwell")
				w.Clock.advance(0.5)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(0)
				w.Clock.advance(0.1)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(1)
				expect(#w.Ranch.openStates()).toBe(0)
				-- rester dessus : aucun autre achat
				for _ = 1, 20 do
					w.Clock.advance(0.1)
					tick(w, { [p] = actor(w, p, mat) })
				end
				expect(data.tiles.snack).toBe(1)
				-- sortir puis revenir : nouvel achat 0,6 s plus tard
				tick(w, { [p] = actor(w, p, off) })
				expect(w.Ranch.onPad(p)).toBe("")
				tick(w, { [p] = actor(w, p, mat) })
				w.Clock.advance(0.6)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(2)
				clean(w)
			end
		)

		it(
			"hystérésis : 3 studs (entre 2,5 et 3,5) n'est pas une entrée ; on en sort au-delà de 3,5",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, richProfile(w, 1e6))
				end)
				local p = Bots.join(1)
				local mat = padPos(w, p, "snack")
				local edge = w.V3.new(mat.X + 3, 3, mat.Z)
				tick(w, { [p] = actor(w, p, edge) })
				expect(w.Ranch.onPad(p)).toBe("")
				tick(w, { [p] = actor(w, p, mat) })
				tick(w, { [p] = actor(w, p, edge) })
				expect(w.Ranch.onPad(p)).toBe("snack")
				tick(w, { [p] = actor(w, p, w.V3.new(mat.X + 3.6, 3, mat.Z)) })
				expect(w.Ranch.onPad(p)).toBe("")
				clean(w)
			end
		)

		it(
			"sortie, portage ou autre maintien : annulé sans rien dépenser (HoldState active = false)",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, richProfile(w, 1e6))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local mat = padPos(w, p, "snack")
				local off = at(w, p, 0, 30)
				-- sortie avant la fin
				tick(w, { [p] = actor(w, p, mat) })
				w.Clock.advance(0.3)
				tick(w, { [p] = actor(w, p, off) })
				local hs = holds(w, p)
				expect(hs[#hs].active).toBe(false)
				w.Clock.advance(1)
				tick(w, { [p] = actor(w, p, off) })
				expect(data.tiles.snack).toBe(0)
				-- autre maintien (boop, bol, Grand Splorch) pendant l'attente : annulé, entrée dépensée
				local busy = false
				w.Ranch.setHoldCheck("test", function()
					return busy
				end)
				tick(w, { [p] = actor(w, p, mat) })
				w.Clock.advance(0.2)
				busy = true
				tick(w, { [p] = actor(w, p, mat) })
				hs = holds(w, p)
				expect(hs[#hs].active).toBe(false)
				busy = false
				for _ = 1, 10 do
					w.Clock.advance(0.1)
					tick(w, { [p] = actor(w, p, mat) })
				end
				expect(data.tiles.snack).toBe(0)
				-- entrée pendant un maintien : aucune attente du tout
				tick(w, { [p] = actor(w, p, off) })
				busy = true
				local n = #holds(w, p)
				tick(w, { [p] = actor(w, p, mat) })
				expect(#holds(w, p)).toBe(n)
				busy = false
				w.Ranch.setHoldCheck("test", nil)
				clean(w)
			end
		)

		it("portage d'un squishy (SquishyService) : l'attente est annulée", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, richProfile(w, 1e6))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local uid = w.Squishy.give(p, { s = 1, m = 0, st = 0, z = 5 }, "test")
			local mat = padPos(w, p, "snack")
			tick(w, { [p] = actor(w, p, mat) })
			-- portage simulé : la garde de SquishyService voit un uid porté
			local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
			local place = w.Squishy.placeOf(p, uid)
			MoveCheck.reset(p, w.V3.new(place.X, 3, place.Z), w.Clock.now())
			w.h:fireServer("ReplicatedStorage.Remotes.PickUp", p, uid)
			expect(w.Squishy.carried(p)).toBe(uid)
			w.Clock.advance(0.7)
			tick(w, { [p] = actor(w, p, mat) })
			expect(data.tiles.snack).toBe(0)
			clean(w)
		end)

		it(
			"dalle trop chère : aucun refus ; achat au premier tick où les pièces suffisent, une fois",
			function()
				local w = boot(function(w)
					Bots.saveProfile(w, 1, richProfile(w, 5))
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local mat = padPos(w, p, "snack")
				tick(w, { [p] = actor(w, p, mat) })
				w.Clock.advance(0.6)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(0)
				-- aucun Feedback « pièces manquantes » sur une dalle (refus doux)
				for _, args in w.h:sentTo(p, "Feedback") do
					expect(args[1].key ~= "feedback.notEnoughCoins").toBe(true)
				end
				w.Clock.advance(1)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(0)
				-- les pièces arrivent (pression, Pot…) : achat au tick suivant
				w.Economy.addCoins(p, 100, "Test")
				w.Clock.advance(0.1)
				tick(w, { [p] = actor(w, p, mat) })
				expect(data.tiles.snack).toBe(1)
				-- encore assez pour le niveau 2 : jamais un second achat dans la même entrée
				w.Economy.addCoins(p, 1e6, "Test")
				for _ = 1, 10 do
					w.Clock.advance(0.1)
					tick(w, { [p] = actor(w, p, mat) })
				end
				expect(data.tiles.snack).toBe(1)
				clean(w)
			end
		)

		it("une coupure de canAct ne crée jamais une nouvelle entrée (aucun achat en double)", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, richProfile(w, 1e6))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local mat = padPos(w, p, "snack")
			tick(w, { [p] = actor(w, p, mat) })
			w.Clock.advance(0.6)
			tick(w, { [p] = actor(w, p, mat) })
			expect(data.tiles.snack).toBe(1)
			tick(w, { [p] = actor(w, p, mat, false) })
			for _ = 1, 10 do
				w.Clock.advance(0.1)
				tick(w, { [p] = actor(w, p, mat) })
			end
			expect(data.tiles.snack).toBe(1)
			-- coupure pendant l'attente : entrée dépensée, rien n'est acheté
			tick(w, { [p] = actor(w, p, at(w, p, 0, 30)) })
			tick(w, { [p] = actor(w, p, mat) })
			tick(w, { [p] = actor(w, p, mat, false) })
			w.Clock.advance(1)
			tick(w, { [p] = actor(w, p, mat) })
			expect(data.tiles.snack).toBe(1)
			clean(w)
		end)

		it("dalle éteinte (Lit douillet avant R = 3, accueil) : aucune attente, aucun achat", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, richProfile(w, 1e9))
			end)
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local bed = padPos(w, p, "cozyBed")
			tick(w, { [p] = actor(w, p, bed) })
			expect(w.Ranch.onPad(p)).toBe("cozyBed")
			expect(#holds(w, p)).toBe(0)
			w.Clock.advance(1)
			tick(w, { [p] = actor(w, p, bed) })
			expect(data.tiles.cozyBed).toBe(false)
			clean(w)
		end)

		it("sans acteur (mort) : l'attente est fermée ; openStates jamais au-delà du délai", function()
			local w = boot(function(w)
				Bots.saveProfile(w, 1, richProfile(w, 1e6))
			end)
			local p = Bots.join(1)
			local StateTimeouts = w.h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
			local mat = padPos(w, p, "snack")
			tick(w, { [p] = actor(w, p, mat) })
			tick(w, {})
			local hs = holds(w, p)
			expect(hs[#hs].active).toBe(false)
			expect(#w.Ranch.openStates()).toBe(0)
			-- à chaque tick d'une longue attente, aucun état n'a dépassé son délai
			for _ = 1, 30 do
				tick(w, { [p] = actor(w, p, mat) })
				for _, s in w.Ranch.openStates() do
					expect(StateTimeouts.expired(s.name, s.startedAt, w.Clock.now())).toBe(false)
				end
				w.Clock.advance(0.1)
			end
			clean(w)
		end)
	end)

	describe("RanchService › clôtures (remarque A25)", function()
		local function fences(w, p)
			local out = {}
			for _, args in w.h:sentTo(p, "Fence") do
				table.insert(out, args[1])
			end
			return out
		end

		it(
			"Rush puis pet-sitting : le pet-sitting n'écrase pas le Rush ; la fin du pet-sitting n'efface rien",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.Ranch.setFence(1, { "a", "b" }, "rush")
				w.Ranch.setFence(1, { "c" }, "petsit")
				local uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "a", "b" })
				expect(reason).toBe("rush")
				w.Ranch.setFence(1, {}, "petsit")
				uids, reason = w.Ranch.fenceOf(1)
				expect(reason).toBe("rush")
				w.Ranch.setFence(1, {}, "rush")
				uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({})
				expect(reason).toBe("")
				local f = fences(w, p)
				expect(f[1]).toEqual({ slot = 1, uids = { "a", "b" }, reason = "rush" })
				expect(f[#f]).toEqual({ slot = 1, uids = {}, reason = "" })
				clean(w)
			end
		)

		it(
			"pet-sitting puis Rush : le Rush passe devant ; la fin du Rush n'efface jamais un pet-sitting",
			function()
				local w = boot()
				Bots.join(1)
				w.Ranch.setFence(1, { "c" }, "petsit")
				w.Ranch.setFence(1, { "a" }, "rush")
				local uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "a" })
				expect(reason).toBe("rush")
				-- CommunityService réapplique le pet-sitting au step qui suit la fin du Rush
				w.Ranch.setFence(1, {}, "rush")
				w.Ranch.setFence(1, { "c" }, "petsit")
				uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "c" })
				expect(reason).toBe("petsit")
				w.Ranch.setFence(1, {}, "rush") -- sans effet sur le pet-sitting
				uids, reason = w.Ranch.fenceOf(1)
				expect(reason).toBe("petsit")
				clean(w)
			end
		)

		it(
			"arguments hostiles ignorés ; 4 places au plus ; doublons retirés ; départ du propriétaire : clôture effacée",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.Ranch.setFence(0, { "a" }, "rush")
				w.Ranch.setFence(17, { "a" }, "rush")
				w.Ranch.setFence(1 / 0, { "a" }, "rush")
				w.Ranch.setFence(1, "abc", "rush")
				w.Ranch.setFence(1, { "a" }, "boop")
				w.Ranch.setFence(1, { "a" }, "")
				local uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({})
				expect(reason).toBe("")
				w.Ranch.setFence(1, { "a", "a", "b", "c", "d", "e" }, "rush")
				uids = w.Ranch.fenceOf(1)
				expect(uids).toEqual({ "a", "b", "c", "d" })
				Bots.leave(p)
				uids, reason = w.Ranch.fenceOf(1)
				expect(uids).toEqual({})
				expect(reason).toBe("")
				clean(w)
			end
		)
	end)

	describe("RanchService › état public, patchs, RequestWorld, départ", function()
		it(
			"setPublic et squishyOp : un RanchPatch par tick et par destinataire, numéroté ; ops fusionnées",
			function()
				local w = boot()
				local a = Bots.join(1)
				local b = Bots.join(2)
				w.Ranch.flush()
				local seqA = #w.h:sentTo(a, "RanchPatch")
				w.Ranch.setPublic(a, { R = 3, unknown = 5, mode = nil })
				w.Ranch.squishyOp(
					a,
					"add",
					"z1",
					{ s = 1, m = 0, st = 0, z = 1, zg = 0, at = "pen", bf = 0, o = "", ready = 0 }
				)
				w.Ranch.squishyOp(
					a,
					"update",
					"z1",
					{ s = 1, m = 0, st = 1, z = 1, zg = 0, at = "pen", bf = 0, o = "", ready = 0 }
				)
				w.Ranch.flush()
				local pa = w.h:sentTo(a, "RanchPatch")
				local pb = w.h:sentTo(b, "RanchPatch")
				expect(#pa).toBe(seqA + 1)
				local last = pa[#pa][1]
				expect(last.ranches["1"]).toEqual({ R = 3 })
				expect(#last.ops).toBe(1)
				expect(last.ops[1].op).toBe("add")
				expect(last.ops[1].rec.st).toBe(1)
				expect(pb[#pb][1].ranches["1"].R).toBe(3)
				-- suite par destinataire : instantané puis patchs consécutifs
				local snapA = w.h:sentTo(a, "RanchSnapshot")[1][1].seq
				expect(pa[1][1].seq).toBe(snapA + 1)
				expect(last.seq).toBe(snapA + #pa)
				-- rien de changé : rien d'envoyé
				w.Ranch.flush()
				expect(#w.h:sentTo(a, "RanchPatch")).toBe(#pa)
				expect(w.Ranch.publicOf(1).R).toBe(3)
				clean(w)
			end
		)

		it(
			"RequestWorld : instantané renvoyé et WorldRequested (débit 1 / 2 s, arguments ignorés)",
			function()
				local w = boot()
				local RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				local p = Bots.join(1)
				local asked = 0
				w.Signals.WorldRequested:Connect(function()
					asked += 1
				end)
				local before = #w.h:sentTo(p, "RanchSnapshot")
				w.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", p, { junk = true }, 0 / 0)
				w.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", p)
				expect(#w.h:sentTo(p, "RanchSnapshot")).toBe(before + 1)
				expect(asked).toBe(1)
				RateLimit.clear(p) -- 2 s plus tard (seau à jetons rempli)
				w.h:fireServer("ReplicatedStorage.Remotes.RequestWorld", p)
				expect(asked).toBe(2)
				clean(w)
			end
		)

		it(
			"départ : ranch libéré (état public vide, squishies retirés), propriétaire effacé dans le monde",
			function()
				local w = boot()
				local a = Bots.join(1)
				local b = Bots.join(2)
				w.Squishy.give(a, { s = 1, m = 0, st = 0, z = 3 }, "test")
				w.Ranch.flush()
				Bots.leave(a)
				w.Ranch.flush()
				local pub = w.Ranch.publicOf(1)
				expect(pub.userId).toBe(0)
				expect(pub.best).toEqual({ s = 0, m = 0, z = 0, zg = 0 })
				local pb = w.h:sentTo(b, "RanchPatch")
				local last = pb[#pb][1]
				expect(last.ranches["1"].userId).toBe(0)
				local removed = false
				for _, op in last.ops do
					if op.slot == 1 and op.op == "remove" then
						removed = true
					end
				end
				expect(removed).toBe(true)
				expect(w.h.game.Workspace.Wobbleton.Ranches["1"]:GetAttribute("OwnerUserId")).toBe(0)
				expect(w.Ranch.slotOf(a)).toBe(0)
				clean(w)
			end
		)
	end)
end
