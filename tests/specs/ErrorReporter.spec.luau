--!nocheck
-- ErrorReporter (paquet meta, docs/04 §13.7, §18.2) : normalisation, 1 par clé et par minute, 30 par
-- session, file bornée (10) vidée au débit de ReportError (une cascade au démarrage n'est pas perdue),
-- interrupteur du serveur (EventState.features.diagnostics), entries, stats, Celebrate testError (erreur
-- volontaire qui suit le chemin normal), attach sans double compte, SetInputType, zéro trace.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	local function setup(opts)
		local h = Harness.new({ mode = "client", console = (opts or {}).console ~= false })
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:createRemotes()
		local E = h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.ErrorReporter")
		E.attach()
		E.Init()
		E.Start()
		h:settle(2)
		return h, E, Clock
	end

	local function sent(h, name)
		local out = {}
		for _, e in h.log.serverEvents do
			if e.remote == name then
				table.insert(out, e.args)
			end
		end
		return out
	end

	-- avance l'horloge de `seconds` par pas de 0,5 s, une image par pas
	local function run(h, Clock, seconds)
		for _ = 1, math.ceil(seconds / 0.5) do
			Clock.advance(0.5)
			h:step(0.5, 1)
		end
	end

	describe("ErrorReporter", function()
		it(
			"normalisation (joueur local, nombres), entries par clé, 1 envoi par clé et par minute",
			function()
				local h, E, Clock = setup()
				E.report(1, "LocalTester a perdu 42 pièces", "Players.LocalTester.PlayerScripts.X:12: f")
				E.report(1, "LocalTester a perdu 43 pièces", "Players.LocalTester.PlayerScripts.X:13: f")
				local entries = E.entries()
				expect(#entries).toBe(1)
				expect(entries[1].count).toBe(2)
				expect(entries[1].text:find("LocalTester", 1, true)).toBeNil()
				expect(entries[1].text).toContain("#")
				run(h, Clock, 10)
				local reports = sent(h, "ReportError")
				expect(#reports).toBe(1)
				expect(reports[1][1]).toBe(1)
				expect(reports[1][3]:find("LocalTester", 1, true)).toBeNil()
				expect(reports[1][4]:find("LocalTester", 1, true)).toBeNil()
				expect(type(reports[1][5])).toBe("string")
				expect(E.sent()).toBe(1)
			end
		)

		it(
			"cascade au démarrage : file bornée à 10, vidée au débit (≥ 2,2 s entre deux envois), rien de perdu",
			function()
				local h, E, Clock = setup()
				for i = 1, 14 do
					E.report(2, "erreur différente " .. string.rep("q", i), "")
				end
				expect(E._queued()).toBe(10)
				run(h, Clock, 1)
				expect(#sent(h, "ReportError")).toBe(1)
				run(h, Clock, 30)
				expect(#sent(h, "ReportError")).toBe(10)
				expect(#E.entries()).toBe(14) -- toutes comptées
			end
		)

		it("30 rapports par session au plus", function()
			local h, E, Clock = setup()
			for i = 1, 45 do
				E.report(1, "erreur unique " .. string.rep("z", i), "")
				run(h, Clock, 2.5)
			end
			expect(#sent(h, "ReportError")).toBe(30)
			expect(#E.entries()).toBe(45)
		end)

		it(
			"interrupteur du serveur : features.diagnostics faux → aucun envoi, entries continue de compter",
			function()
				local h, E, Clock = setup()
				h:fireClient("ReplicatedStorage.Remotes.EventState", { features = { diagnostics = false } })
				expect(E._enabled()).toBe(false)
				E.report(1, "coupé", "")
				run(h, Clock, 10)
				expect(#sent(h, "ReportError")).toBe(0)
				expect(#E.entries()).toBe(1)
				h:fireClient("ReplicatedStorage.Remotes.EventState", { features = { diagnostics = true } })
				run(h, Clock, 3)
				expect(#sent(h, "ReportError")).toBe(1)
			end
		)

		it(
			"Celebrate testError : erreur volontaire dans un thread du client, comptée et envoyée par le chemin normal",
			function()
				local h, E, Clock = setup()
				T.expectWarning("erreur volontaire du client")
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "testError", data = {} })
				h:settle(2)
				expect(#h.errors).toBe(1)
				local entries = E.entries()
				expect(#entries).toBe(1) -- ScriptContext.Error et MessageOut : une seule fois
				expect(entries[1].count).toBe(1)
				expect(entries[1].kind).toBe(1)
				run(h, Clock, 3)
				expect(#sent(h, "ReportError")).toBe(1)
			end
		)

		it(
			"avertissement du client compté (kind 2) ; contexte noté (fenêtre) envoyé avec le rapport",
			function()
				local h, E, Clock = setup()
				T.expectWarning("avertissement du client")
				E.noteContext("window", "Shop")
				h.globals.warn("avertissement du client")
				h:settle(1)
				local entries = E.entries()
				expect(#entries).toBe(1)
				expect(entries[1].kind).toBe(2)
				run(h, Clock, 3)
				local reports = sent(h, "ReportError")
				expect(reports[1][1]).toBe(2)
				expect(reports[1][5]).toContain("win=Shop")
			end
		)

		it(
			"stats : mesures numériques ; qualité réduite par la sonde d'un contrôleur plus tardif ; SetInputType",
			function()
				local h, E, Clock = setup()
				run(h, Clock, 2)
				local st = E.stats()
				for _, key in { "fps", "memoryMb", "pingMs", "instances", "connections" } do
					expect(type(st[key])).toBe("number")
					expect(st[key] == st[key]).toBe(true)
				end
				expect(st.reduced).toBe(false)
				E.setProbe("reduced", function()
					return true
				end)
				E.setProbe("connections", function()
					error("sonde en panne")
				end)
				expect(E.stats().reduced).toBe(true)
				expect(E.stats().connections).toBe(0)
				local inputs = sent(h, "SetInputType")
				expect(#inputs).toBe(1)
				expect(inputs[1][1]).toBe(3)
				expect(inputs[1][2]).toBe(true)
			end
		)
	end)
end
