--!nocheck
-- Démarrage du client avec des données simulées venant du serveur, et utilitaires partagés (repris
-- de Comet Conga ; complété : nombres géants d'un tycoon, Signal, Validate, Tables, Trove).
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

	describe("Prix lus en direct (Util/Prices)", function()
		it(
			"repli tout de suite, puis prix réel ; id ≤ 0 : repli seul ; une seule requête par article",
			function()
				local h = Harness.new({ mode = "client" })
				local MockInstance = require("../harness/MockInstance")
				local requests = 0
				MockInstance.classMethods.MarketplaceService.GetProductInfo = function(_, id)
					requests += 1
					task.wait() -- requête web : la réponse arrive plus tard
					return { PriceInRobux = 149, Name = "P" .. id }
				end
				local Prices = h:require("StarterPlayer.StarterPlayerScripts.Client.Util.Prices")
				local seen, seen2, disabled = {}, {}, {}
				Prices.observe("pass", 42, 99, function(price)
					table.insert(seen, price)
				end)
				Prices.observe("pass", 42, 99, function(price)
					table.insert(seen2, price)
				end)
				Prices.observe("product", 0, 25, function(price)
					table.insert(disabled, price)
				end)
				h:settle(3)
				expect(seen).toEqual({ 99, 149 })
				expect(seen2).toEqual({ 99, 149 })
				expect(disabled).toEqual({ 25 })
				expect(requests).toBe(1)
				-- déjà connu : prix réel tout de suite
				local cached = {}
				Prices.observe("pass", 42, 99, function(price)
					table.insert(cached, price)
				end)
				expect(cached).toEqual({ 149 })
				-- réponse en erreur : le repli reste affiché, aucune erreur
				MockInstance.classMethods.MarketplaceService.GetProductInfo = function()
					error("HTTP 503 (simulé)")
				end
				local failed = {}
				Prices.observe("product", 7, 49, function(price)
					table.insert(failed, price)
				end)
				h:settle(3)
				expect(failed).toEqual({ 49 })
				expect(#h.errors).toBe(0)
			end
		)
	end)

	describe("Localisation", function()
		it("toutes les clés anglaises existent en français", function()
			local h = Harness.new()
			local L = h:require("ReplicatedStorage.Shared.Localization")
			expect(#L.missingKeys("fr")).toBe(0)
			expect(L.languageFor("fr-fr")).toBe("fr")
			expect(L.languageFor("en-us")).toBe("en")
			expect(L.get("fr", "common.robux", { price = 49 })).toBe("49 R$")
			expect(L.get("en", "common.robux", { price = 49 })).toBe("R$ 49")
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

		it(
			"Format : nombres géants d'un tycoon, infinis et NaN (jamais d'erreur ni de valeur absurde)",
			function()
				local h = Harness.new()
				local F = h:require("ReplicatedStorage.Shared.Util.Format")
				expect(F.abbreviate(1e12)).toBe("1T")
				expect(F.abbreviate(1.5e15)).toBe("1.5Qa")
				expect(F.abbreviate(1e33)).toBe("1Dc")
				expect(F.abbreviate(2.5e35)).toBe("250Dc")
				-- au-delà de 1e36 : notation scientifique courte (avant : « -9223372036854775808Dc »)
				expect(F.abbreviate(1.234e45)).toBe("1.23e45")
				expect(F.abbreviate(1.234e45, "fr")).toBe("1,23e45")
				expect(F.abbreviate(-1e40)).toBe("-1.00e40")
				expect(F.abbreviate(math.huge)).toBe("∞")
				expect(F.abbreviate(-math.huge)).toBe("-∞")
				for _, n in { 1e16, 1e20, 1e30, 1e300 } do
					local text = F.abbreviate(n)
					expect({ n = n, ok = string.find(text, "-", 1, true) == nil and #text <= 8 }).toEqual({
						n = n,
						ok = true,
					})
				end
				-- commas : au-delà de 1e15, abréviation (tostring passerait en 1e+16)
				expect(F.commas(999999999999999)).toBe("999,999,999,999,999")
				expect(F.commas(1e18)).toBe(F.abbreviate(1e18))
				expect(F.commas(0 / 0)).toBe("0")
				-- durées absurdes : 0
				expect(F.clock(0 / 0)).toBe("0:00")
				expect(F.clock(math.huge)).toBe("0:00")
				expect(F.duration(-math.huge)).toBe("0s")
				expect(F.percent(0.256)).toBe("26%")
			end
		)

		it("Signal : chaque handler dans son propre thread, Once, Wait, Disconnect, DisconnectAll", function()
			local h = Harness.new()
			local Signal = h:require("ReplicatedStorage.Shared.Util.Signal")
			local task = require("@lune/task")
			local s = Signal.new()
			local got = {}
			local c1 = s:Connect(function(x)
				table.insert(got, "a" .. x)
			end)
			s:Once(function(x)
				table.insert(got, "once" .. x)
			end)
			s:Connect(function()
				task.wait(0.01) -- un handler qui attend ne bloque pas les autres
			end)
			s:Fire(1)
			s:Fire(2)
			expect(got).toEqual({ "a1", "once1", "a2" })
			c1:Disconnect()
			c1:Disconnect() -- idempotent
			expect(c1.Connected).toBe(false)
			s:Fire(3)
			expect(#got).toBe(3)
			local waited = nil
			task.spawn(function()
				waited = s:Wait()
			end)
			s:Fire(42)
			task.wait()
			expect(waited).toBe(42)
			s:DisconnectAll()
			s:Fire(5)
			expect(#got).toBe(3)
		end)

		it("Tables : deepCopy indépendante, deepEqual, count, keys", function()
			local h = Harness.new()
			local Tb = h:require("ReplicatedStorage.Shared.Util.Tables")
			local src = { a = { b = { 1, 2 } }, c = "x" }
			local copy = Tb.deepCopy(src)
			copy.a.b[1] = 9
			expect(src.a.b[1]).toBe(1)
			expect(Tb.deepEqual({ a = { 1 } }, { a = { 1 } })).toBe(true)
			expect(Tb.deepEqual({ a = { 1 } }, { a = { 1 }, b = 2 })).toBe(false)
			expect(Tb.count({ a = 1, b = 2, 3 })).toBe(3)
			local keys = Tb.keys({ x = 1, y = 2 })
			table.sort(keys)
			expect(keys).toEqual({ "x", "y" })
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
			expect(V.key("", { [""] = true })).toBe(false) -- chaîne vide refusée
			expect(V.numberInRange(5, 0, 10)).toBe(true)
			expect(V.numberInRange(0 / 0, 0, 10)).toBe(false)
			expect(V.numberInRange(11, 0, 10)).toBe(false)
			expect(V.boolean(false)).toBe(true)
			expect(V.boolean(0)).toBe(false)
			local V3 = h.globals.Vector3
			expect(V.vector3(V3.new(1, 2, 3))).toBe(true)
			expect(V.vector3(V3.new(0 / 0, 0, 0))).toBe(false)
			expect(V.vector3(V3.new(1e7, 0, 0))).toBe(false)
			expect(V.vector3({ X = 1, Y = 2, Z = 3 })).toBe(false) -- table déguisée en Vector3
			local part = h.globals.Instance.new("Part")
			expect(V.instanceOf(part, "BasePart")).toBe(true)
			expect(V.instanceOf(part, "Model")).toBe(false)
			expect(V.instanceOf({ ClassName = "Part" }, "Part")).toBe(false)
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
			-- un élément qui lève n'arrête pas le nettoyage ; ajout pendant le nettoyage : nettoyé aussitôt
			local tr2 = Trove.new()
			local cleaned = 0
			tr2:Add(function()
				cleaned += 1
			end)
			tr2:Add(function()
				error("nettoyage en panne")
			end)
			tr2:Add(function()
				tr2:Add(function()
					cleaned += 10
				end)
			end)
			tr2:Clean()
			expect(cleaned).toBe(11)
			tr2:Destroy() -- alias de Clean, sans effet une 2e fois
			expect(cleaned).toBe(11)
		end)
	end)
end
