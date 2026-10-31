--!nocheck
-- Fil réseau simulé (tests/harness/Wire) : règles de sérialisation des remotes Roblox, copie
-- profonde, enregistrement des envois d'un serveur et contexte du harnais.
local roblox = require("@lune/roblox")
local Wire = require("../../harness/Wire")
local MockInstance = require("../../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function problems(...)
		local out = {}
		local args = Wire.copyArgs("X", out, ...)
		return out, args
	end

	describe("Wire › sérialisation des remotes", function()
		it(
			"accepte tableaux, dictionnaires à clés chaînes, Vector3, buffer, booléens, chaînes",
			function()
				local buf = buffer.create(4)
				buffer.writeu32(buf, 0, 1234)
				local list, args = problems(
					{ 1, 2, 3 },
					{ a = 1, b = { c = "x" } },
					roblox.Vector3.new(1, 2, 3),
					buf,
					true,
					"texte",
					{},
					nil
				)
				expect(#list).toBe(0)
				expect(args.n).toBe(8)
				expect(args[1][3]).toBe(3)
				expect(args[2].b.c).toBe("x")
				-- copie : le buffer et les tables ne sont pas partagés
				expect(args[4] ~= buf).toBe(true)
				expect(buffer.readu32(args[4], 0)).toBe(1234)
				buffer.writeu32(buf, 0, 1)
				expect(buffer.readu32(args[4], 0)).toBe(1234)
			end
		)

		it(
			"signale tables mixtes, à trous, clés numériques éparses, NaN, ±inf, fonctions, Instances",
			function()
				expect(#problems({ 1, 2, x = 3 })).toBe(1)
				expect(#problems({ [1] = "a", [3] = "c" })).toBe(1)
				expect(#problems({ [1001] = true, [1002] = true })).toBe(1)
				expect(#problems({ v = 0 / 0 })).toBe(1)
				expect(#problems({ math.huge })).toBe(1)
				expect(#problems({ f = function() end })).toBe(1)
				expect(#problems({ i = MockInstance.new("Part") })).toBe(1)
				expect(#problems(setmetatable({}, {}))).toBe(1)
				local cyclic = {}
				cyclic.self = cyclic
				expect(#problems(cyclic)).toBe(1)
				-- une même table partagée à deux endroits (sans cycle) est copiée deux fois, sans alerte
				local shared = { 1 }
				expect(#problems({ a = shared, b = shared })).toBe(0)
			end
		)
	end)

	describe("Wire › enregistrement et contexte", function()
		it("enregistre les envois au joueur observé et à tous, avec l'instant de l'horloge", function()
			local h = Harness.new()
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(1000)
			local remote = MockInstance.new("RemoteEvent")
			remote.Name = "Test"
			local a = h:addPlayer({ userId = 1, spawn = false })
			local b = h:addPlayer({ userId = 2, spawn = false })
			local rec = Wire.record(h, { userId = 1, Clock = Clock, remotes = { "Test" } })
			remote:FireClient(a, { x = 1 })
			Clock.advance(0.5)
			remote:FireClient(b, { x = 2 })
			remote:FireAllClients({ 1, 2, mixed = true })
			a:SetAttribute("Slot", 3)
			rec:stop()
			remote:FireClient(a, { x = 3 }) -- après l'arrêt : ignoré
			expect(rec:count("Test")).toBe(2)
			expect(#rec.sent.Test).toBe(3)
			expect(#rec.problems).toBe(1)
			local remotes, attrs = {}, {}
			for _, e in rec.events do
				if e.kind == "remote" then
					table.insert(remotes, e)
				elseif e.kind == "attr" and e.name == "Slot" then
					table.insert(attrs, e)
				end
			end
			expect(remotes[1].t).toBe(1000)
			expect(remotes[1].args[1].x).toBe(1)
			expect(remotes[2].t).toBe(1000.5)
			expect(#attrs).toBe(1)
			expect(attrs[1].value).toBe(3)
			-- le journal du harnais reste alimenté
			expect(#h:sentTo(a, "Test")).toBe(2)
		end)

		it("sauvegarde et restaure les crochets globaux d'un harnais", function()
			local h1 = Harness.new()
			local ctx = Wire.saveContext()
			local hook = MockInstance.onFireClient
			local h2 = Harness.new({ mode = "client" })
			expect(MockInstance.onFireClient ~= hook).toBe(true)
			expect(MockInstance.localPlayer).toBe(h2.localPlayer)
			Wire.restoreContext(ctx)
			expect(MockInstance.onFireClient).toBe(hook)
			expect(MockInstance.localPlayer).toBeNil()
			local p = h1:addPlayer({ userId = 7 })
			expect(p.Character ~= nil and p.Character.Parent == h1.workspace).toBe(true)
		end)
	end)
end
