--!nocheck
-- DiagnosticsService (paquet meta, docs/04 §11.2, GDD §12.11, §17.1 j) : nettoyage des noms, plafonds
-- (30 par session, 1 par clé et par minute), fusion des clés, 200 clés puis « autres », silence pour un
-- non-administrateur, « bonjour » aux seuls administrateurs, taille du paquet ≤ 20 Ko, écriture groupée
-- des totaux du jour (deltas seulement), ClientEvent analytique seulement (20 par session), attach
-- (ScriptContext.Error et MessageOut sans double compte), interrupteur Diagnostics, reportCaught,
-- stateTimedOut, analytique ServerError une fois par clé et par 5 min, zéro trace.
-- v2.0 (lot A4, étape 6, D29) : ClientMetric (compteurs UpgradeTimeout, TextScaleMeasured:<v>,
-- StyleFallback:<v>, VisualBudgetExceeded et analytique ; 20 par session ; chaque sorte derrière son
-- interrupteur et un profil v2 ; jamais un changement du jeu).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function world(opts)
		opts = opts or {}
		local w = Brains.boot(Harness, {
			t0 = T0,
			stubMeta = false,
			preset = opts.preset, -- préréglage des interrupteurs (tests/harness/Flags, lot I)
			before = function(w)
				local Admins = w.h:require("ServerScriptService.Server.Data.Admins")
				for _, id in opts.admins or {} do
					Admins[id] = true
				end
			end,
		})
		w.D = w.h:require(S .. "DiagnosticsService")
		return w
	end

	local function join(w, id, name)
		return Brains.join(w, id, { profile = Brains.profile(w, {}), name = name })
	end

	local function analytics(w, name)
		local out = {}
		for _, c in w.h.log.analytics do
			if c.method == "LogCustomEvent" and c.args[2] == name then
				table.insert(out, c.args)
			end
		end
		return out
	end

	local function report(w, p, msg, key)
		w.h:fireServer(R .. "ReportError", p, 1, key or "k", msg, "Players.X.PlayerScripts:10: f", "dev=pc")
		w.osClock.advance(2.1)
	end

	describe("Diagnostics › rapports des clients", function()
		it("noms et nombres nettoyés (envoyeur et joueurs présents) ; clé et exemple gardés", function()
			local w = world()
			local p = join(w, 1, "Mira")
			join(w, 2, "Noah")
			report(w, p, "Players.Mira.PlayerGui: Noah a 42 pièces et Mira 7")
			local snap = w.D.snapshot(1)
			expect(#snap.entries).toBe(1)
			local text = snap.entries[1].text
			expect(text:find("Mira", 1, true)).toBeNil()
			expect(text:find("Noah", 1, true)).toBeNil()
			expect(text:find("42", 1, true)).toBeNil()
			expect(text).toContain("<joueur>")
			expect(text).toContain("#")
			expect(snap.entries[1].source).toBe("client")
			expect(#snap.samples).toBe(1)
			expect(snap.samples[1].key).toBe(snap.entries[1].key)
		end)

		it(
			"30 rapports par joueur et par session, 1 par clé et par minute ; au-delà ignoré sans réponse",
			function()
				local w = world()
				local p = join(w, 1)
				for i = 1, 40 do
					report(w, p, "erreur différente " .. string.rep("x", i))
				end
				local total = 0
				for _, e in w.D.snapshot(1).entries do
					total += e.count
				end
				expect(total).toBe(30)
				-- même clé dans la minute : une seule fois
				local q = join(w, 2)
				report(w, q, "même erreur")
				report(w, q, "même erreur")
				w.Clock.advance(61)
				report(w, q, "même erreur")
				local same = 0
				for _, e in w.D.snapshot(1).entries do
					if e.text == "même erreur" then
						same = e.count
					end
				end
				expect(same).toBe(2)
				expect(#w.h:sentTo(p, "DiagnosticsSnapshot")).toBe(0)
			end
		)

		it(
			"fusion des clés : même erreur chez deux joueurs = une ligne, 2 joueurs touchés, 3 exemples au plus",
			function()
				local w = world()
				local ps = { join(w, 1), join(w, 2), join(w, 3), join(w, 4) }
				for _, p in ps do
					report(w, p, "nil index sur Health")
				end
				local snap = w.D.snapshot(1)
				expect(#snap.entries).toBe(1)
				expect(snap.entries[1].count).toBe(4)
				expect(snap.entries[1].players).toBe(4)
				expect(#snap.samples).toBe(3)
			end
		)

		it("200 clés au plus par serveur, puis un compteur « autres »", function()
			local w = world()
			for i = 1, 230 do
				w.D.report("server", 1, "erreur unique " .. string.rep("y", i), "", "", nil)
			end
			expect(w.D.counts().keys).toBe(200)
			expect(w.D.debugState().others).toBe(30)
			expect(w.D.counts().errors).toBe(230)
		end)

		it(
			"interrupteur Diagnostics coupé : rapports des clients ignorés, ceux du serveur gardés",
			function()
				local w = world()
				local p = join(w, 1)
				local Features = w.h:require("ReplicatedStorage.Shared.Config.Features")
				Features.set("Diagnostics", false)
				report(w, p, "client coupé")
				w.D.report("server", 2, "serveur gardé", "", "", nil)
				local snap = w.D.snapshot(1)
				expect(#snap.entries).toBe(1)
				expect(snap.entries[1].text).toBe("serveur gardé")
				Features.reset()
			end
		)
	end)

	describe("Diagnostics › panneau des administrateurs", function()
		it("« bonjour » (tab 0, vide) aux seuls administrateurs, à PlayerReady", function()
			local w = world({ admins = { 1 } })
			local admin = join(w, 1)
			local other = join(w, 2)
			local hello = w.h:sentTo(admin, "DiagnosticsSnapshot")
			expect(#hello).toBe(1)
			expect(hello[1][1].tab).toBe(0)
			expect(#hello[1][1].entries).toBe(0)
			expect(#w.h:sentTo(other, "DiagnosticsSnapshot")).toBe(0)
		end)

		it(
			"RequestDiagnostics : un non-administrateur n'obtient aucune réponse ; isAdmin revérifié à chaque demande",
			function()
				local w = world({ admins = { 1 } })
				local admin = join(w, 1)
				local other = join(w, 2)
				w.h:fireServer(R .. "RequestDiagnostics", other, 1)
				expect(#w.h:sentTo(other, "DiagnosticsSnapshot")).toBe(0)
				w.h:fireServer(R .. "RequestDiagnostics", admin, 1)
				local got = w.h:sentTo(admin, "DiagnosticsSnapshot")
				expect(got[#got][1].tab).toBe(1)
				expect(got[#got][1].server.players).toBe(2)
				-- retiré de la liste : plus rien
				w.h:require("ServerScriptService.Server.Data.Admins")[1] = nil
				w.osClock.advance(3)
				w.h:fireServer(R .. "RequestDiagnostics", admin, 3)
				expect(#w.h:sentTo(admin, "DiagnosticsSnapshot")).toBe(#got)
			end
		)

		it("paquet ≤ 20 Ko : les exemples sont tronqués d'abord", function()
			local w = world()
			for i = 1, 200 do
				w.D.report(
					"server",
					1,
					string.rep("erreur longue " .. string.char(65 + i % 26), 20) .. string.rep("z", i),
					string.rep("Script:1: trace très longue\n", 30),
					string.rep("ctx", 40),
					nil
				)
			end
			local HttpService = w.h.game:GetService("HttpService")
			local snap = w.D.snapshot(1)
			expect(#HttpService:JSONEncode(snap)).toBeLessThanOrEqual(20000)
			expect(#snap.entries).toBeGreaterThan(0)
		end)
	end)

	describe("Diagnostics › totaux du jour et analytique", function()
		it(
			"toutes les 5 min : UpdateAsync groupé (task.spawn), deltas seulement, jamais de double compte",
			function()
				local w = world()
				w.D.report("server", 1, "panne A", "", "", nil)
				w.D.report("server", 1, "panne A", "", "", nil)
				w.D.step(w.Clock.now() + 10) -- trop tôt : rien
				expect(w.h.dataStores["Diagnostics_v1/global"]).toBeNil()
				w.Clock.advance(301)
				w.D.step(w.Clock.now())
				w.h:settle(3)
				local store = w.h.dataStores["Diagnostics_v1/global"]
				expect(store ~= nil).toBe(true)
				local Clock = w.Clock
				local MockInstance = require("../harness/MockInstance")
				local saved = MockInstance.state(store).data["Diagnostics_" .. tostring(Clock.day())]
				expect(saved.entries[1].count).toBe(2)
				w.D.report("server", 1, "panne A", "", "", nil)
				w.Clock.advance(301)
				w.D.step(w.Clock.now())
				w.h:settle(3)
				saved = MockInstance.state(store).data["Diagnostics_" .. tostring(Clock.day())]
				expect(saved.entries[1].count).toBe(3)
				-- onglet « Aujourd'hui » : totaux de tous les serveurs
				expect(w.D.snapshot(3).today[1].count).toBe(3)
			end
		)

		it("panne du DataStore pendant l'écriture : rien n'est perdu, réessayé au lot suivant", function()
			local w = world()
			w.D.report("server", 1, "panne B", "", "", nil)
			w.h.dataStoreFailures = 1
			w.Clock.advance(301)
			w.D.step(w.Clock.now())
			w.h:settle(3)
			w.Clock.advance(301)
			w.D.step(w.Clock.now())
			w.h:settle(3)
			local MockInstance = require("../harness/MockInstance")
			local store = w.h.dataStores["Diagnostics_v1/global"]
			local saved = MockInstance.state(store).data["Diagnostics_" .. tostring(w.Clock.day())]
			expect(saved.entries[1].count).toBe(1)
		end)

		it("ServerError une fois par clé et par 5 min, avec le nombre d'occurrences", function()
			local w = world()
			join(w, 1)
			for _ = 1, 5 do
				w.D.report("server", 1, "panne C", "", "", nil)
			end
			w.h:settle(2)
			expect(#analytics(w, "ServerError")).toBe(1)
			w.Clock.advance(301)
			w.D.step(w.Clock.now())
			w.h:settle(2)
			local sent = analytics(w, "ServerError")
			expect(#sent).toBe(2)
			expect(sent[2][3]).toBe(4)
		end)

		it(
			"reportCaught : compté sous la clé de « où » ; stateTimedOut : compté et analytique StateTimedOut",
			function()
				local w = world()
				local p = join(w, 1)
				T.expectWarning("[caught] tick:quest")
				w.D.reportCaught("tick:quest", "attempt to index nil 12")
				w.D.reportCaught("tick:quest", "autre message 13")
				local caught = 0
				for _, e in w.D.snapshot(1).entries do
					if e.text:find("[caught] tick:quest", 1, true) then
						caught += e.count
					end
				end
				expect(caught).toBe(2)
				w.D.stateTimedOut("feedHold", p)
				w.h:settle(2)
				expect(w.D.counts().timedOut).toBe(1)
				expect(#analytics(w, "StateTimedOut")).toBe(1)
			end
		)

		-- Lot A4 (D29, note INT-A2-DIAG) : compteurs nommés des services v2.0
		it(
			"count : compté par clé, montré aux administrateurs (« Count:<clé> »), jamais un avertissement ni un ServerError ; 64 clés puis « others »",
			function()
				local w = world({ admins = { 1 } })
				local admin = join(w, 1)
				local before = w.D.counts()
				for _ = 1, 3 do
					w.D.count("UpgradeStale", admin)
				end
				w.D.count("ConfigRefused")
				expect(w.D.counters()).toEqual({ UpgradeStale = 3, ConfigRefused = 1 })
				-- panneau des administrateurs : lignes « Count:<clé> » (comme StateTimedOut)
				w.h:fireServer(R .. "RequestDiagnostics", admin, 1)
				local got = w.h:sentTo(admin, "DiagnosticsSnapshot")
				local rows = {}
				for _, e in got[#got][1].entries do
					rows[e.text] = { e.count, e.kind, e.players }
				end
				expect(rows["Count:UpgradeStale"]).toEqual({ 3, 2, 1 })
				expect(rows["Count:ConfigRefused"]).toEqual({ 1, 2, 0 })
				-- jamais un avertissement ni une erreur du moteur ; jamais d'analytique ServerError, même
				-- à l'envoi groupé des 5 minutes ; totaux du jour écrits comme les autres lignes
				local after = w.D.counts()
				expect({ after.errors, after.warnings }).toEqual({ before.errors, before.warnings })
				w.h:settle(2)
				expect(#analytics(w, "ServerError")).toBe(0)
				w.Clock.advance(301)
				w.D.count("UpgradeStale")
				w.D.step(w.Clock.now())
				w.h:settle(2)
				expect(#analytics(w, "ServerError")).toBe(0)
				w.osClock.advance(3) -- débit de RequestDiagnostics
				w.h:fireServer(R .. "RequestDiagnostics", admin, 3)
				got = w.h:sentTo(admin, "DiagnosticsSnapshot")
				expect(got[#got][1].tab).toBe(3)
				local today = {}
				for _, e in got[#got][1].today do
					today[e.text] = e.count
				end
				expect(today["Count:UpgradeStale"]).toBe(4)
				-- arguments illisibles : rien compté, aucune erreur ; joueur illisible : compté sans joueur
				w.D.count(nil)
				w.D.count("")
				w.D.count(5)
				w.D.count("Bad", "pas un joueur")
				expect(w.D.counters().Bad).toBe(1)
				-- 64 clés au plus (3 déjà vues), puis « others »
				for i = 1, 70 do
					w.D.count("k" .. i)
				end
				local c = w.D.counters()
				local keys = 0
				for key in c do
					if key ~= "others" then
						keys += 1
					end
				end
				expect(keys).toBe(w.D.CounterKeys)
				expect(c.others).toBe(70 - (w.D.CounterKeys - 3))
				expect(c.k61).toBe(1)
				expect(c.k62).toBeNil()
				expect(w.D.debugState().internal).toBe(0)
			end
		)

		it(
			"ClientEvent : analytique seulement (QualityReduced avec l'appareil, ShopOpened), 20 par session, profil inchangé",
			function()
				local w = world()
				local p = join(w, 1)
				w.h:fireServer(R .. "SetInputType", p, 3, true)
				local DS = w.h:require(S .. "DataService")
				local before = w.h.globals.game:GetService("HttpService"):JSONEncode(DS.get(p).coins)
				for i = 1, 30 do
					w.h:fireServer(
						R .. "ClientEvent",
						p,
						if i % 2 == 0 then "shopOpened" else "qualityReduced"
					)
					w.osClock.advance(5.1)
					w.Clock.advance(7) -- sous le débit d'analytique (10 par minute et par joueur)
				end
				w.h:settle(2)
				local q = analytics(w, "QualityReduced")
				local s = analytics(w, "ShopOpened")
				expect(#q + #s).toBe(20)
				expect(q[1][4] ~= nil).toBe(true)
				expect(w.D.device(p).kind).toBe(3)
				expect(w.D.device(p).tenFoot).toBe(true)
				expect(w.h.globals.game:GetService("HttpService"):JSONEncode(DS.get(p).coins)).toBe(before)
			end
		)
	end)

	-- =========================================================================================
	-- v2.0 (lot A4, étape 6, D29) : ClientMetric
	-- =========================================================================================
	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require("ReplicatedStorage.Shared.Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- serveur v2 (schéma v2 figé), interrupteurs `flags` ouverts
	local function worldV2(flags)
		local w = Brains.boot(HarnessV2, { t0 = T0, stubMeta = false })
		w.D = w.h:require(S .. "DiagnosticsService")
		w.A = w.h:require("ServerScriptService.Server.Util.Analytics")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function metric(w, p, kind, value)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. "ClientMetric", p, kind, value)
	end

	-- événements personnalisés envoyés, par nom : { valeur, champs }
	local function customs(w, name)
		local out = {}
		for _, c in w.h.log.analytics do
			if c.method == "LogCustomEvent" and c.args[2] == name then
				table.insert(out, { c.args[3], c.args[4] })
			end
		end
		return out
	end

	local function fieldOf(w, entry, i)
		local Keys = w.h.globals.Enum.AnalyticsCustomFieldKeys
		local f = entry[2]
		return f and f[Keys["CustomField0" .. i]]
	end

	describe("Diagnostics › ClientMetric (v2.0, D29)", function()
		it(
			"interrupteurs ouverts, profil v2 : chaque sorte comptée (Diagnostics) et envoyée (analytique) ; profil jamais changé",
			function()
				local w = worldV2({ "UpgradesScreen", "JellyAscend" })
				local p = join(w, 1)
				local same, diffAt = Fuzz.profileUnchanged(w.h, p, function()
					metric(w, p, "upgradeTimeout", 0)
					metric(w, p, "upgradeTimeout", 7)
					metric(w, p, "upgradeMode", 10)
					metric(w, p, "upgradeMode", 0)
					metric(w, p, "upgradeMode", 10)
					metric(w, p, "ascendPreview", 0)
					metric(w, p, "ascendPreview", 2)
					metric(w, p, "ascendDeclined", 3)
					metric(w, p, "textScale", 125)
					metric(w, p, "styleFallback", 1)
					metric(w, p, "visualBudget", 0)
					w.h:settle(2)
				end)
				expect({ same = same, at = diffAt }).toEqual({ same = true, at = nil })
				local c = w.D.counters()
				expect(c.UpgradeTimeout).toBe(2)
				expect(c["TextScaleMeasured:125"]).toBe(1)
				expect(c["StyleFallback:1"]).toBe(1)
				expect(c.VisualBudgetExceeded).toBe(1)
				expect(c.UpgradeMode).toBeNil() -- analytique seulement
				-- immédiats : AscendDeclined (jours), TextScaleMeasured (facteur × 100)
				expect(customs(w, "AscendDeclined")[1][1]).toBe(3)
				expect(customs(w, "TextScaleMeasured")[1][1]).toBe(125)
				-- cumulés par tranche de 5 min : rien avant la fermeture de la tranche
				expect(#customs(w, "UpgradeTimeout")).toBe(0)
				w.Clock.advance(301)
				w.D.step(w.Clock.now())
				w.h:settle(2)
				expect(customs(w, "UpgradeTimeout")[1][1]).toBe(2)
				local modes = {}
				for _, e in customs(w, "UpgradeMode") do
					modes[fieldOf(w, e, 1)] = e[1]
				end
				expect(modes).toEqual({ ["mode:x10"] = 2, ["mode:max"] = 1 })
				local steps = {}
				for _, e in customs(w, "AscendPreview") do
					steps[fieldOf(w, e, 1)] = e[1]
				end
				expect(steps).toEqual({ ["step:opened"] = 1, ["step:confirmed"] = 1 })
				-- jamais une trace, jamais un avertissement de Diagnostics
				expect(w.D.counts().errors).toBe(0)
				expect(w.D.counts().warnings).toBe(0)
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)

		it(
			"20 par session au plus ; valeurs hors liste refusées ; « <clé>:<valeur> » : 8 valeurs par serveur puis « other »",
			function()
				local w = worldV2({ "UpgradesScreen" })
				local p = join(w, 1)
				local q = join(w, 2)
				-- mode et étape hors liste : refusés, rien compté (la place de la session reste)
				metric(w, p, "upgradeMode", 5)
				metric(w, p, "upgradeMode", 1000)
				metric(w, p, "ascendPreview", 1) -- JellyAscend coupé
				expect(w.D.counters().UpgradeTimeout).toBeNil()
				for _ = 1, 30 do
					metric(w, p, "upgradeTimeout", 1)
				end
				expect(w.D.counters().UpgradeTimeout).toBe(w.D.ClientMetricsPerSession)
				expect(w.D.ClientMetricsPerSession).toBe(20)
				-- 12 valeurs distinctes de textScale (deux joueurs) : 8 clés puis « other »
				for i = 1, 6 do
					metric(w, q, "textScale", 100 + i)
				end
				for i = 7, 12 do
					metric(w, q, "textScale", 100 + i)
				end
				local c = w.D.counters()
				local named = 0
				for key in c do
					if string.find(key, "TextScaleMeasured:1", 1, true) == 1 then
						named += 1
					end
				end
				expect(named).toBe(8)
				expect(c["TextScaleMeasured:other"]).toBe(4)
				expect(w.D.debugState().internal).toBe(0)
			end
		)

		it(
			"interrupteurs coupés ou profil v1 : sortes liées refusées (rien compté ni envoyé) ; diagnostics de base toujours acceptés",
			function()
				-- serveur v1 (préréglage « v13 », lot I D2 a) : profil v1, interrupteurs coupés ; le chemin
				-- du lancement (profil v2) : cas suivants (worldV2)
				local w = world({ preset = "v13" })
				w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				local p = join(w, 1)
				local before = #w.h.log.analytics
				metric(w, p, "upgradeTimeout", 1)
				metric(w, p, "upgradeMode", 1)
				metric(w, p, "ascendPreview", 0)
				metric(w, p, "ascendDeclined", 2)
				w.h:settle(2)
				expect(w.D.counters()).toEqual({})
				w.Clock.advance(301)
				w.D.step(w.Clock.now())
				w.h:settle(2)
				expect(#w.h.log.analytics).toBe(before)
				-- UpgradesScreen ouvert mais profil v1 (schéma v2 coupé) : toujours refusé
				assert(w.Features.set("UpgradesScreen", true))
				metric(w, p, "upgradeTimeout", 1)
				expect(w.D.counters().UpgradeTimeout).toBeNil()
				-- diagnostics de base (B1, B4) : acceptés pour tous
				metric(w, p, "visualBudget", 3)
				metric(w, p, "styleFallback", 2)
				expect(w.D.counters().VisualBudgetExceeded).toBe(1)
				expect(w.D.counters()["StyleFallback:2"]).toBe(1)
			end
		)
	end)

	describe("Diagnostics › attach", function()
		it(
			"ScriptContext.Error et MessageOut : une erreur comptée une fois, un avertissement compté",
			function()
				local w = world()
				T.expectWarning("panne volontaire du thread")
				T.expectWarning("avertissement volontaire")
				w.h.globals.task.spawn(function()
					error("panne volontaire du thread")
				end)
				w.h.globals.warn("avertissement volontaire")
				w.h:settle(2)
				local counts = w.D.counts()
				expect(counts.errors).toBe(1)
				expect(counts.warnings).toBe(1)
			end
		)

		it("une panne de Diagnostics ne se rapporte jamais elle-même (garde de réentrance)", function()
			local w = world()
			local DiagRules = w.h:require("ReplicatedStorage.Shared.Logic.DiagRules")
			local original = DiagRules.normalize
			DiagRules.normalize = function()
				error("normalize en panne")
			end
			w.D.report("server", 1, "x", "", "", nil)
			DiagRules.normalize = original
			expect(w.D.debugState().internal).toBe(1)
			expect(w.D.counts().errors).toBe(0)
			local _ = Bots
		end)
	end)
end
