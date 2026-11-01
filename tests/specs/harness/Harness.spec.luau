--!nocheck
-- Auto-test du harnais sur un mini-projet témoin (tests/fixtures/miniproject).
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local ROOT = "tests/fixtures/miniproject"

	describe("Harnais", function()
		it("résout require(script.Parent.Parent.X)", function()
			local h = Harness.new({ root = ROOT })
			local M = h:require("ReplicatedStorage.Shared.Util.Math")
			expect(M.double(4)).toBe(8)
		end)

		it("échoue sur un enfant inexistant d'un dossier de scripts", function()
			local h = Harness.new({ root = ROOT })
			expect(function()
				return h.game.ReplicatedStorage.Shared.Confg
			end).toThrow("is not a valid member")
		end)

		it("démarre le serveur, gère achat, refus et sauvegarde", function()
			local h = Harness.new({ root = ROOT })
			h:boot()
			local p = h:addPlayer({ userId = 7, name = "Alice" })
			h:fireServer("ReplicatedStorage.Remotes.Buy", p, "sword")
			local sent = h:sentTo(p, "Result")
			expect(#sent).toBe(1)
			expect(sent[1][1]).toBe(true)
			expect(sent[1][2]).toBe(5)
			h:fireServer("ReplicatedStorage.Remotes.Buy", p, "sword")
			h:fireServer("ReplicatedStorage.Remotes.Buy", p, "sword")
			sent = h:sentTo(p, "Result")
			expect(sent[3][1]).toBe(false)
			-- charge utile invalide ignorée
			h:fireServer("ReplicatedStorage.Remotes.Buy", p, { evil = true })
			expect(#h:sentTo(p, "Result")).toBe(3)
			h:removePlayer(p)
			task.wait()
			local data = h.dataStores["Test/global"]
			expect(data ~= nil).toBeTruthy()
		end)

		it("démarre le client et construit l'UI", function()
			local h = Harness.new({ root = ROOT, mode = "client", touch = true })
			h:boot()
			local gui = h.localPlayer.PlayerGui:FindFirstChild("HUD")
			expect(gui ~= nil).toBeTruthy()
			expect(gui.TextLabel.TextTransparency).toBe(1)
			expect(#h:warnings()).toBe(0)
		end)

		it("détecte les données non sérialisables", function()
			local h = Harness.new({ root = ROOT })
			local store = h.game.DataStoreService:GetDataStore("X")
			expect(function()
				store:SetAsync("k", { pos = h.globals.Vector3.new(1, 2, 3) })
			end).toThrow("non sérialisable")
			expect(function()
				store:SetAsync("k", { 1, 2, a = 3 })
			end).toThrow("table mixte")
		end)

		it("capture les erreurs des connexions sans bloquer l'émetteur", function()
			local Signal = require("../../harness/Signal")
			local sig = Signal.new()
			local before = #Signal.errors
			local reached = false
			sig:Connect(function()
				error("boom")
			end)
			sig:Connect(function()
				reached = true
			end)
			sig:Fire()
			expect(reached).toBe(true)
			expect(#Signal.errors).toBe(before + 1)
			table.remove(Signal.errors) -- erreur volontaire : on la retire
		end)

		it("un handler qui yield ne bloque pas Fire", function()
			local Signal = require("../../harness/Signal")
			local sig = Signal.new()
			local done = false
			sig:Connect(function()
				task.wait(0.05)
				done = true
			end)
			sig:Fire()
			expect(done).toBe(false)
			task.wait(0.1)
			expect(done).toBe(true)
		end)

		it("dispose annule les threads en attente du code monté (boucles sans fin, task.delay)", function()
			local h = Harness.new({ root = ROOT })
			local g = h.globals
			local fired = false
			local delayed = g.task.delay(100, function()
				fired = true
			end)
			local loop = g.task.spawn(function()
				while true do
					g.task.wait(10)
				end
			end)
			-- thread lancé hors du task du harnais mais qui attend via task.wait du code monté
			local waiter = task.spawn(function()
				g.task.wait(10)
			end)
			expect(coroutine.status(delayed)).toBe("suspended")
			expect(coroutine.status(loop)).toBe("suspended")
			expect(coroutine.status(waiter)).toBe("suspended")
			h:dispose()
			expect(coroutine.status(delayed)).toBe("dead")
			expect(coroutine.status(loop)).toBe("dead")
			expect(coroutine.status(waiter)).toBe("dead")
			expect(fired).toBe(false)
			-- idempotent ; disposeAll ne touche pas au thread courant
			h:dispose()
			local h2 = Harness.new({ root = ROOT })
			h2.globals.task.wait()
			Harness.disposeAll()
			expect(coroutine.status(coroutine.running())).toBe("running")
		end)

		it("état des instances privé : itération vide, is/state fiables", function()
			local MockInstance = require("../../harness/MockInstance")
			local h = Harness.new({ root = ROOT })
			local part = h.globals.Instance.new("Part", h.game.Workspace)
			part.Name = "Bloc"
			local n = 0
			for _ in part do
				n += 1
			end
			expect(n).toBe(0)
			expect(MockInstance.is(part)).toBe(true)
			expect(MockInstance.state(part).Name).toBe("Bloc")
			expect(part.Parent).toBe(h.game.Workspace)
			for _, v in { {}, "Bloc", 5, true, h.globals.Vector3.new(1, 2, 3) } do
				expect(MockInstance.is(v)).toBe(false)
				expect(MockInstance.state(v)).toBeNil()
			end
			expect(function()
				part.Parent = "pas une instance"
			end).toThrow("Parent doit être une Instance")
		end)

		it("simule les pannes DataStore", function()
			local h = Harness.new({ root = ROOT })
			local store = h.game.DataStoreService:GetDataStore("Y")
			h.dataStoreFailures = 1
			expect(function()
				store:GetAsync("k")
			end).toThrow("502")
			expect(function()
				store:GetAsync("k")
			end).notToThrow()
		end)
	end)

	-- Couche « zéro trace » (docs/04 §17.1 h, note INT-HARNESS appliquée par le contrat) : une erreur
	-- dans un thread lancé par le code monté n'est jamais silencieuse
	describe("Harnais › zéro trace (INT-HARNESS)", function()
		it("erreur d'un handler de Shared/Util/Signal : h.errors, ScriptContext.Error, MessageOut", function()
			local h = Harness.new({ mode = "server" })
			local Signal = h:require("ReplicatedStorage.Shared.Util.Signal")
			local seen, logs = {}, {}
			h.game:GetService("ScriptContext").Error:Connect(function(message, trace)
				table.insert(seen, { message = message, trace = trace })
			end)
			h.game:GetService("LogService").MessageOut:Connect(function(message, kind)
				table.insert(logs, { message = message, kind = kind })
			end)
			local s = Signal.new()
			local after = false
			s:Connect(function()
				error("panne volontaire du handler")
			end)
			s:Connect(function()
				after = true
			end)
			s:Fire()
			task.wait()
			expect(after).toBe(true) -- l'émetteur et les autres handlers continuent
			expect(#h.errors).toBe(1)
			expect(string.find(h.errors[1], "panne volontaire du handler", 1, true) ~= nil).toBe(true)
			expect(#seen).toBe(1)
			expect(string.find(seen[1].message, "panne volontaire", 1, true) ~= nil).toBe(true)
			expect(#logs).toBe(1)
			expect(logs[1].kind).toBe(h.globals.Enum.MessageType.MessageError)
		end)

		it(
			"task.spawn, task.defer et task.delay du code monté sont surveillés ; un thread repris ne l'est pas",
			function()
				local h = Harness.new({ root = ROOT })
				local g = h.globals
				g.task.spawn(function()
					error("spawn")
				end)
				g.task.defer(function()
					error("defer")
				end)
				g.task.delay(0, function()
					error("delay")
				end)
				task.wait(0.05)
				expect(#h.errors).toBe(3)
				-- reprise d'une coroutine (Signal:Wait) : passée telle quelle, sans erreur
				local co = coroutine.create(function()
					coroutine.yield()
				end)
				coroutine.resume(co)
				g.task.spawn(co)
				expect(#h.errors).toBe(3)
			end
		)

		it("warn et print vont dans LogService (MessageOut, GetLogHistory)", function()
			local h = Harness.new({ root = ROOT })
			local kinds = {}
			h.game.LogService.MessageOut:Connect(function(_, kind)
				table.insert(kinds, kind)
			end)
			h.globals.warn("attention")
			h.globals.print("bonjour")
			task.wait()
			local Enum = h.globals.Enum
			expect(kinds).toEqual({ Enum.MessageType.MessageWarning, Enum.MessageType.MessageOutput })
			local history = h.game.LogService:GetLogHistory()
			expect(#history).toBe(2)
			expect(history[1].message).toBe("attention")
			expect(#h:warnings()).toBe(1)
		end)

		it(
			"services du moteur simulés : ScriptContext, LogService, Stats, CaptureService, UserService",
			function()
				local h = Harness.new({ root = ROOT })
				local game = h.game
				for _, name in { "ScriptContext", "LogService", "Stats", "CaptureService", "UserService" } do
					expect(function()
						game:GetService(name)
					end).notToThrow()
				end
				expect(game.Stats:GetTotalMemoryUsageMb() > 0).toBe(true)
				expect(game.Stats.InstanceCount > 0).toBe(true)
				-- capture vidéo indisponible par défaut (pas de case « Filmer »)
				local Enum = h.globals.Enum
				expect(game.CaptureService:StartVideoCaptureAsync(function() end, {})).toBe(
					Enum.VideoCaptureStartedResult.NoDeviceSupport
				)
				h.captureAvailable = true
				expect(game.CaptureService:StartVideoCaptureAsync(function() end, {})).toBe(
					Enum.VideoCaptureStartedResult.Success
				)
				local infos = game.UserService:GetUserInfosByUserIdsAsync({ 7, 9 })
				expect(#infos).toBe(2)
				expect(infos[1].Id).toBe(7)
				h.userInfoFails = true
				expect(function()
					game.UserService:GetUserInfosByUserIdsAsync({ 7 })
				end).toThrow("503")
			end
		)

		it("DataStore simulé : un tableau à trous est refusé (docs/04 §8.5)", function()
			local h = Harness.new({ root = ROOT })
			local store = h.game.DataStoreService:GetDataStore("Z")
			expect(function()
				store:SetAsync("k", { mut = { [1] = 0, [3] = 1 } })
			end).toThrow("tableau à trous")
			expect(function()
				store:SetAsync("k", { mut = { [5] = 1 } })
			end).toThrow("tableau à trous")
			expect(function()
				store:SetAsync("k", { mut = { 0, 0, 1 }, dict = { a = 1 } })
			end).notToThrow()
		end)

		it("Harness.live() et h:counts() : harnais vivants, instances, connexions, threads", function()
			local before = #Harness.live()
			local h = Harness.new({ root = ROOT })
			expect(#Harness.live()).toBe(before + 1)
			local c0 = h:counts()
			expect(c0.instances > 0).toBe(true)
			local part = h.globals.Instance.new("Part", h.game.Workspace)
			local conn = part.Changed:Connect(function() end)
			local c1 = h:counts()
			expect(c1.instances).toBe(c0.instances + 1)
			expect(c1.connections).toBe(c0.connections + 1)
			conn:Disconnect()
			part:Destroy()
			local c2 = h:counts()
			expect(c2.instances).toBe(c0.instances)
			expect(c2.connections).toBe(c0.connections)
		end)
	end)
end
