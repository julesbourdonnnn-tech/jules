--!nocheck
-- Relecture indépendante du lot A4 (méta v2.0 : piste, Défis, Carnet, maîtrise, social, météo, analytique,
-- restes du serveur) : défauts réels trouvés par la relecture, chacun montré rouge sur le code du lot
-- avant sa correction (docs/04 §27.12, lignes A4-51 et suivantes), et robot de longue durée avec TOUS les
-- interrupteurs v2.0 ouverts (le lot n'avait de Soak qu'interrupteurs coupés et Plopettes seules).
-- Interrupteurs ouverts DANS le test ; SchemaV2 (figé) dans le harnais avant le premier require du schéma
-- (recette de DataChaos). Zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Soak = require("../harness/Soak")
local TvAudit = require("../harness/TvAudit")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- tous les interrupteurs v2.0 qu'on peut changer en direct (SchemaV2, figé, est ouvert par le harnais)
	local ALL_V2 = {
		"UpgradesScreen",
		"Confetti",
		"Workshop",
		"StarMat",
		"Gloves",
		"Monuments",
		"RecordR",
		"PetitSplorch",
		"JellyAscend",
		"Helpers",
		"WeeklyTrack",
		"Carnet",
		"Mastery",
		"RanchTiers",
		"RanchSkins",
		"DecoPerso",
		"Hearts",
		"PhotoMode",
		"Weather",
		"Fete",
	}

	local function boot(opts)
		opts = opts or {}
		local w = Brains.boot(HarnessV2, { t0 = opts.t0 or T0, stubMeta = false })
		w.C = w.h:require(S .. "CommunityService")
		w.Q = w.h:require(S .. "QuestService")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.Diag = w.h:require(S .. "DiagnosticsService")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
		expect(w.Diag.counts().errors).toBe(0)
	end

	local function join(w, id)
		return Brains.join(w, id, {
			profile = Brains.profile(w, { squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 } } }),
		})
	end

	-- intention envoyée (seau à jetons vidé : la règle du serveur seule décide)
	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
		w.h:settle(1)
	end

	-- ---------------------------------------------------------------------------------------------
	-- R4-1 (A4-51) : cœur d'un joueur au nom caché. Le serveur envoyait hearts.received { name = "" }
	-- sans userId : le client (Hud/Util.vars) ne peut écrire l'alias « Squishy Fan #NNNN » qu'avec le
	-- userId, et le message lu était « ␣gave you a heart! » (nom vide). Même règle que les autres textes
	-- qui portent un nom (prises de ChaseService : { userId, name }).
	describe("Review_A4 › cœur d'un joueur au nom caché", function()
		it(
			"hearts.received porte le userId du donneur : le client écrit l'alias, jamais un nom vide",
			function()
				local w = boot({ flags = { "Hearts" } })
				local a = join(w, 1)
				local b = join(w, 2)
				fire(w, "SetSetting", a, "hideName", true)
				fire(w, "GiveHeart", a, b.UserId)
				expect(w.DS.get(b).hearts.receivedTotal).toBe(1)
				local list = w.h:sentTo(b, "Feedback")
				local payload = list[#list][1]
				expect(payload.key).toBe("hearts.received")
				expect(payload.vars.name).toBe("")
				expect(payload.vars.userId).toBe(a.UserId)
				-- nom montré : le nom, et le userId
				fire(w, "SetSetting", a, "hideName", false)
				w.Clock.advance(86400)
				fire(w, "GiveHeart", a, b.UserId)
				expect(w.DS.get(b).hearts.receivedTotal).toBe(2)
				local list2 = w.h:sentTo(b, "Feedback")
				local shown = list2[#list2][1]
				expect(shown.key).toBe("hearts.received")
				expect(shown.vars.userId).toBe(a.UserId)
				expect(shown.vars.name).toBe(w.C.displayName(a))
				expect(shown.vars.name ~= "").toBe(true)
				clean(w)
				-- le client (autre harnais, créé après les envois du serveur) montre l'alias du donneur caché
				local h =
					TvAudit.client({ profile = { onboarding = { step = 11, done = true, demoDone = true } } })
				local M = TvAudit.mod(h, "UI.Hud.Messages")
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				h:fireClient(R .. "Feedback", payload)
				h:settle(1)
				M.step(Clock.now())
				local last = M.last()
				expect(last ~= nil).toBe(true)
				expect(string.find(last.text, "Squishy Fan #", 1, true) == 1).toBe(true)
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Robot de longue durée avec TOUS les interrupteurs v2.0 ouverts (relecture du lot A4) : 16 robots
	-- sur un serveur v2, profils variés (boucle record, remontée après une Ascension, Confettis, Atelier,
	-- Record R haut), invariants de chaque profil À CHAQUE TICK (Soak : Invariants.profile, donc
	-- profileV2), aucune trace, aucun compteur d'erreur. Durée : Soak.hours() / 5 (0,1 h par défaut).
	describe("Review_A4 › Soak, tous les interrupteurs v2.0 ouverts", function()
		it(
			`{Soak.hours() / 5} h, 16 robots : invariants v2 à chaque tick, zéro trace, systèmes du lot actifs`,
			function()
				local hours = Soak.hours() / 5
				local report = Soak.run(HarnessV2, {
					players = 16,
					hours = hours,
					seed = 11,
					flags = ALL_V2,
					edit = function(d, i)
						d.confetti = 200 + 10 * i
						d.confettiTotal = d.confetti
						if i % 4 == 1 then
							-- remontée après une Ascension : prochain prestige = Petit Splorch
							d.bestR = 16
							d.ascend = 1
						elseif i % 4 == 2 then
							-- Record R haut : Plopettes, cartes, tenues du Record R
							d.bestR = math.max(d.R or 0, 12)
							d.atelier[8] = 1 -- Plume
						end
					end,
				})
				local w = report.world
				expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.msPerTick < 10).toBe(true)
				local D = w.h:require(S .. "DiagnosticsService")
				local counts = D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(#D.caught()).toBe(0)
				-- les systèmes du lot ont tourné : piste de la période, 3 Défis, jeu du jour compté
				local tracked = 0
				for _, p in w.players do
					if p.Parent ~= nil and w.DS.isLoaded(p) then
						local d = w.DS.get(p)
						expect(d.version).toBe(2)
						expect(#d.weeklyTrack.challenges).toBe(3)
						expect(d.weeklyTrack.period > 0).toBe(true)
						local played = 0
						for _, v in d.weeklyTrack.play do
							played += v
						end
						if played > 0 then
							tracked += 1
						end
					end
				end
				expect(tracked > 0).toBe(true)
				print(
					string.format(
						"  Soak v2 (tous les interrupteurs) : %.2f h, %.2f ms par tick du serveur, %d joueurs à la fin, instances %d → %d",
						hours,
						report.msPerTick,
						report.players,
						report.counts.start.instances,
						report.counts.finish.instances
					)
				)
			end
		)
	end)

	local _ = Bots
end
