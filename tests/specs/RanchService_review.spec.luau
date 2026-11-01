--!nocheck
-- RanchService : défauts trouvés par la revue adverse du paquet ranch (chaque test a d'abord échoué).
--   1. Protection de l'enfant (GDD §6.9, §13) : un ranch attribué AVANT le chargement du profil ne
--      publie jamais le nom d'un joueur qui l'a caché (nom vide et caché jusqu'au profil).
--   2. Arrivées simultanées pendant la vérification des amis (IsFriendsWith cède) : aucune erreur,
--      chaque joueur reçoit un ranch différent.
local Bots = require("../harness/Bots")
local Chaos = require("../harness/Chaos")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	local function boot(before)
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
				if before then
					before(w)
				end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	describe("RanchService (revue) › nom caché", function()
		it(
			"ranch attribué avant le chargement du profil : aucun nom publié tant que le profil n'est pas lu",
			function()
				-- DataStore lent (Chaos : 0,2 s par appel) : le chargement cède
				local shared = Chaos.store()
				local caught = {}
				local w = Chaos.boot(Harness, Bots, shared, "A", {
					t0 = T0,
					before = function(w)
						w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
						local Diag = w.h:require(S .. "DiagnosticsService")
						Diag.reportCaught = function(where, err)
							table.insert(caught, where .. " : " .. tostring(err))
						end
						Diag.stateTimedOut = function() end
						local d =
							Bots.profile(w, { onboarding = { step = 11, done = true, demoDone = true } })
						d.settings.hideName = true
						Chaos.seed(shared, 7, d)
					end,
				})
				w.caught = caught
				w.Ranch = w.h:require(S .. "RanchService")
				shared.latency = 0.2
				-- premier joueur (aucune vérification d'amis) : ranch attribué AVANT la fin du chargement
				local hidden = Bots.join(7, { wait = false, name = "SecretKid" })
				local slot = w.Ranch.slotOf(hidden)
				expect(slot > 0).toBe(true)
				expect(w.DS.isLoaded(hidden)).toBe(false)
				-- avant le chargement : rien du nom (ni dans l'état public, ni dans un patch envoyé)
				expect(w.Ranch.publicOf(slot).name).toBe("")
				w.Ranch.flush()
				w.DS.waitFor(hidden, 5)
				expect(w.DS.isLoaded(hidden)).toBe(true)
				shared.latency = 0
				local watcher = Bots.join(1)
				w.h:settle(2)
				w.Ranch.sendSnapshot(watcher)
				local snaps = w.h:sentTo(watcher, "RanchSnapshot")
				expect(snaps[#snaps][1].ranches[tostring(slot)].name).toBe("")
				w.h:settle(2)
				w.Ranch.flush()
				expect(w.Ranch.publicOf(slot).name).toBe("")
				expect(w.Ranch.publicOf(slot).hidden).toBe(true)
				for _, args in w.h:sentTo(watcher, "RanchPatch") do
					local fields = args[1].ranches[tostring(slot)]
					if fields ~= nil and fields.name ~= nil then
						expect(fields.name).toBe("")
					end
				end
				clean(w)
			end
		)
	end)

	describe("RanchService (revue) › □ « Acheter » pendant l'attente sur une dalle", function()
		local function setup()
			local w = boot(function(w)
				Bots.saveProfile(
					w,
					1,
					Bots.profile(w, {
						coins = 1e6,
						onboarding = { step = 11, done = true, demoDone = true },
						lastOnline = 0,
					})
				)
			end)
			w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
			w.Pads = w.h:require("ReplicatedStorage.Shared.Config.Pads")
			w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
			local p = Bots.join(1)
			local c = w.W.padSocket(w.Ranch.slotOf(p), w.Pads.Defs.snack.socket)
			local mat = w.V3.new(c.X, 3, c.Z)
			local function tick()
				w.Ranch.step(w.Clock.now(), {
					[p] = {
						player = p,
						slot = w.Ranch.slotOf(p),
						pos = mat,
						canAct = true,
						riding = false,
						rootOffset = 0,
					},
				})
				w.Ranch.flush()
			end
			local function buy()
				w.RateLimit.clear(p)
				w.h:fireServer("ReplicatedStorage.Remotes.BuyTile", p, "snack")
			end
			return w, p, tick, buy
		end

		it(
			"□ pendant l'anneau : un seul achat pour cette entrée (jamais un 2e niveau à 0,6 s)",
			function()
				local w, p, tick, buy = setup()
				local data = w.DS.get(p)
				tick() -- entrée : l'anneau commence
				w.Clock.advance(0.2)
				buy() -- □ « Acheter » : achat tout de suite (geste voulu)
				expect(data.tiles.snack).toBe(1)
				for _ = 1, 10 do
					w.Clock.advance(0.1)
					tick()
				end
				expect(data.tiles.snack).toBe(1)
				-- l'anneau a été arrêté (HoldState active = false)
				local hs = w.h:sentTo(p, "HoldState")
				expect(hs[#hs][1].active).toBe(false)
				clean(w)
			end
		)

		it(
			"□ reçu juste AVANT l'entrée vue par le serveur (course réseau) : pas de 2e achat à 0,6 s",
			function()
				local w, p, tick, buy = setup()
				local data = w.DS.get(p)
				buy() -- le client se voit déjà sur la dalle ; le serveur pas encore
				expect(data.tiles.snack).toBe(1)
				w.Clock.advance(0.1)
				tick() -- entrée vue par le serveur
				for _ = 1, 10 do
					w.Clock.advance(0.1)
					tick()
				end
				expect(data.tiles.snack).toBe(1)
				clean(w)
			end
		)
	end)

	describe("RanchService (revue) › arrivées simultanées", function()
		it(
			"trois arrivées pendant des vérifications d'amis lentes : ranchs distincts, aucune erreur",
			function()
				local w = boot()
				local a = Bots.join(1)
				local MockInstance = require("../harness/MockInstance")
				local task = require("@lune/task")
				local original = MockInstance.areFriends
				MockInstance.areFriends = function()
					task.wait(0.05) -- appel web lent
					return false
				end
				local b = w.h:addPlayer({ userId = 2 })
				local c = w.h:addPlayer({ userId = 3 })
				local d = w.h:addPlayer({ userId = 4 })
				task.wait(0.5)
				w.h:settle(3)
				MockInstance.areFriends = original
				local seen = {}
				for _, p in { a, b, c, d } do
					local slot = w.Ranch.slotOf(p)
					expect(slot > 0).toBe(true)
					expect(seen[slot]).toBeNil()
					seen[slot] = true
				end
				clean(w)
			end
		)
	end)
end
