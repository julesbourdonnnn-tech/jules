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
end
