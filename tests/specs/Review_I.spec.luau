--!nocheck
-- Review_I (lot I, relecture indépendante et équipe rouge) : défauts trouvés par la relecture du lot I,
-- chacun écrit ici d'abord en rouge, puis corrigé. Serveur au préréglage du lancement (« launch » :
-- les 23 interrupteurs v2.0 ouverts, SchemaV2 compris) sauf mention contraire.
local Bots = require("../harness/Bots")
local Flags = require("../harness/Flags")
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."

	local Launch = Flags.harness(Harness, "launch")

	local function rec(extra)
		local r = {
			s = 1,
			m = 0,
			st = 1,
			z = 1000,
			zg = 0,
			bf = 0,
			lk = false,
			o = "",
			at = "pen",
			b = 100,
			gd = 0,
		}
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function boot(edit)
		local caught = {}
		local w = Bots.boot(Launch, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				w.F = w.h:require(L .. "Config.Features")
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = { ["1"] = rec({ bf = 1 }) },
					nextUid = 2,
				})
				d.coins = 1e9
				d.R = 3
				d.bestR = 3
				if edit then
					edit(d)
				end
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function snapshotsSince(w, p, from)
		local n = 0
		for i, args in w.h:sentTo(p, "DataPatch") do
			if i > from and type(args[1]) == "table" and args[1].upgradeSnapshot ~= nil then
				n += 1
			end
		end
		return n
	end

	describe("Review_I › écran Améliorations rouvert en direct", function()
		it(
			"UpgradesScreen rouvert en direct : l'instantané revient aussitôt chez chaque joueur chargé, sans attendre un changement de pièces (sinon l'écran, la touche U et la puce restent absents)",
			function()
				local w = boot()
				local p = Bots.join(1)
				w.h:settle(3)
				Bots.frames(20)
				expect(w.F.set("UpgradesScreen", false)).toBe(true)
				Bots.frames(20)
				local from = #w.h:sentTo(p, "DataPatch")
				expect(w.F.set("UpgradesScreen", true)).toBe(true)
				-- aucune pièce ne bouge (rien n'est acheté ni encaissé) : 2 s de jeu
				Bots.frames(20)
				expect(snapshotsSince(w, p, from)).toBe(1)
				clean(w)
			end
		)
	end)
	-- Équipe rouge, configuration du lancement entière (les 23 interrupteurs, pas un sous-ensemble ouvert à
	-- la main comme RedTeam_Meta et RedTeam_Upgrade) : chaque intention de la v2.0 rendue joignable par le
	-- lot I, 1 000 messages dans la même image, deux fois (seau plein puis seau vidé une seconde plus tard)
	describe("Review_I › rafales sous la configuration du lancement", function()
		it(
			"BuyUpgrade, JellyAscend, PlaceDeco, GiveHeart, SetPhotoMode, MenuActivity, ClientMetric (HelperPress, hors de Config/Intents : RedTeam_Helpers) : au plus le débit de Config/Intents, profils toujours valides, aucune trace",
			function()
				local w = Brains.boot(Launch, { t0 = T0 + 60, stubMeta = false })
				w.Diag = w.h:require(S .. "DiagnosticsService")
				local Intents = w.h:require(L .. "Config.Intents")
				local Invariants = w.h:require(L .. "Logic.Invariants")
				local F = w.h:require(L .. "Config.Features")
				for _, key in Flags.V2_KEYS do
					expect({ key = key, on = F.get(key) }).toEqual({ key = key, on = true })
				end
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, { squishies = { { s = 1, z = 100, bf = 1 } } }),
				})
				local q = Brains.join(w, 2, {
					profile = Brains.profile(w, { squishies = { { s = 2, z = 50, bf = 1 } } }),
				})
				w.h:settle(2)
				local names = {
					"BuyUpgrade",
					"JellyAscend",
					"PlaceDeco",
					"GiveHeart",
					"SetPhotoMode",
					"MenuActivity",
					"ClientMetric",
				}
				for _, name in names do
					for round = 1, 2 do
						w.osClock.advance(60)
						local passed = Fuzz.rate(w.h, p, name, 1000, { userId = q.UserId, uid = "1" })
						local capacity = Intents[name].rate[1]
						expect({ name = name, round = round, over = passed > capacity }).toEqual({
							name = name,
							round = round,
							over = false,
						})
					end
				end
				w.h:settle(3)
				for _, player in { p, q } do
					local d = w.DS.get(player)
					expect({ user = player.UserId, version = d.version }).toEqual({
						user = player.UserId,
						version = 2,
					})
					expect({ user = player.UserId, bad = Invariants.profile(d) }).toEqual({
						user = player.UserId,
						bad = {},
					})
				end
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
				expect(w.Diag.counts().errors).toBe(0)
			end
		)
	end)
end
