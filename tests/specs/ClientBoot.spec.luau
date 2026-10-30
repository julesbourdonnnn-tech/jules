--!nocheck
-- Démarrage du client avec des données simulées venant du serveur.
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function bootClient()
		local h = Harness.new({ mode = "client", touch = true })
		h:createRemotes()
		h:boot()
		return h
	end

	describe("Client", function()
		it("démarre sans erreur et reflète l'état serveur", function()
			local h = bootClient()
			local State = h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")
			expect(State.ready).toBe(false)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { coins = 5 })
			expect(State.ready).toBe(true)
			expect(State.get("coins")).toBe(5)
			local seen = {}
			State.observe("coins", function(v)
				table.insert(seen, v)
			end)
			h:settle(1)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", { coins = 9 }, {})
			h:settle(1)
			expect(State.get("coins")).toBe(9)
			expect(seen[#seen]).toBe(9)
			expect(#h:warnings()).toBe(0)
		end)

		it("les effets UI fonctionnent (toast, juice)", function()
			local h = bootClient()
			local Toast = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.Toast")
			local Juice = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.Juice")
			for i = 1, 5 do
				Toast.show("Hello " .. i, "success")
			end
			local stack = h.localPlayer.PlayerGui.Toasts.Safe.Stack
			local count = 0
			for _, c in stack:GetChildren() do
				if c.Name == "Toast" then
					count += 1
				end
			end
			expect(count).toBe(3)
			local label = h.globals.Instance.new("TextLabel")
			Juice.countTo(label, 0, 100, 0.05)
			task.wait(0.1)
			h:step(1 / 60, 3)
			expect(label.Text).toBe("100")
			Juice.cameraShake(0.3, 0.05)
			Juice.flash()
			h:step(1 / 60, 5)
		end)
	end)

	describe("Localisation", function()
		it("toutes les clés anglaises existent en français", function()
			local h = Harness.new()
			local L = h:require("ReplicatedStorage.Shared.Localization")
			expect(#L.missingKeys("fr")).toBe(0)
			expect(L.languageFor("fr-fr")).toBe("fr")
			expect(L.languageFor("en-us")).toBe("en")
			expect(L.get("fr", "common.notEnough", { currency = "pièces" })).toBe("Pas assez de pièces !")
		end)
	end)

	describe("Utilitaires", function()
		it("Format.abbreviate", function()
			local h = Harness.new()
			local F = h:require("ReplicatedStorage.Shared.Util.Format")
			expect(F.abbreviate(999)).toBe("999")
			expect(F.abbreviate(1000)).toBe("1K")
			expect(F.abbreviate(1234)).toBe("1.23K")
			expect(F.abbreviate(15300000)).toBe("15.3M")
			expect(F.abbreviate(-2500)).toBe("-2.5K")
			expect(F.abbreviate(0 / 0)).toBe("0")
			expect(F.commas(1234567)).toBe("1,234,567")
			expect(F.clock(75)).toBe("1:15")
			expect(F.duration(90)).toBe("1m 30s")
		end)

		it("Tables.reconcile n'écrase rien", function()
			local h = Harness.new()
			local Tb = h:require("ReplicatedStorage.Shared.Util.Tables")
			local t = { a = 1, nested = { x = 5 } }
			Tb.reconcile(t, { a = 9, b = 2, nested = { x = 0, y = 3 }, list = {} })
			expect(t.a).toBe(1)
			expect(t.b).toBe(2)
			expect(t.nested.x).toBe(5)
			expect(t.nested.y).toBe(3)
			expect(type(t.list)).toBe("table")
		end)

		it("Validate rejette NaN, inf, tables et chaînes trop longues", function()
			local h = Harness.new()
			local V = h:require("ReplicatedStorage.Shared.Util.Validate")
			expect(V.finiteNumber(0 / 0)).toBe(false)
			expect(V.finiteNumber(math.huge)).toBe(false)
			expect(V.integer(3.5)).toBe(false)
			expect(V.integer(3, 1, 5)).toBe(true)
			expect(V.string(string.rep("a", 100), 64)).toBe(false)
			expect(V.key("a", { a = true })).toBe(true)
			expect(V.key({}, { a = true })).toBe(false)
		end)

		it("Trove nettoie connexions, instances et fonctions", function()
			local h = Harness.new()
			local Trove = h:require("ReplicatedStorage.Shared.Util.Trove")
			local tr = Trove.new()
			local part = h.globals.Instance.new("Part")
			part.Parent = h.workspace
			local called = false
			tr:Add(part)
			tr:Add(function()
				called = true
			end)
			local fired = 0
			tr:Connect(part.Touched, function()
				fired += 1
			end)
			tr:Clean()
			expect(part.Parent).toBeNil()
			expect(called).toBe(true)
		end)
	end)
end
