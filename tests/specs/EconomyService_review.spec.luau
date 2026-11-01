--!nocheck
-- EconomyService : défauts trouvés par la revue adverse du paquet ranch (chaque test a d'abord échoué).
--   1. Départ pendant une sauvegarde automatique en cours : la sauvegarde de départ attend, et le
--      nettoyage de session (PlayerRemoving) passe avant son règlement. Le dernier intervalle est quand
--      même réglé avec le contexte qui l'a vécu (amis présents compris), jamais avec un contexte vidé.
local Bots = require("../harness/Bots")
local Chaos = require("../harness/Chaos")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

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

	local function near(a, b, rel)
		local scale = math.max(1, math.abs(a), math.abs(b))
		return math.abs(a - b) <= (rel or 1e-9) * scale
	end

	describe("EconomyService (revue) › règlement de départ", function()
		it(
			"départ pendant une sauvegarde automatique : dernier intervalle réglé avec les amis présents",
			function()
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
						local d = Bots.profile(w, {
							onboarding = { step = 11, done = true, demoDone = true },
							squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 5, z = 400 }) },
							nextUid = 3,
						})
						for s = 1, #d.trophies do
							d.trophies[s] = 1e9
						end
						Chaos.seed(shared, 1, d)
					end,
				})
				local Economy = w.h:require(S .. "EconomyService")
				local Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
				local task = require("@lune/task")
				local p = Bots.join(1)
				w.h:settle(2)
				local data = w.DS.get(p)
				Economy.setFriendsPresent(p, 3)
				-- sauvegarde automatique lente en cours (0,3 s) : son règlement est fait à T0
				shared.latency = 0.3
				task.spawn(w.DS.saveNow, p)
				task.wait(0.05)
				local growth0 = table.clone(data.growth)
				local pot0 = data.pot
				local ctx = Economy.incomeCtx(p)
				expect(ctx.friends).toBe(3)
				local K, S1 = Formulas.ranchIncome(data.squishies, growth0.G, ctx)
				-- 20 s de jeu, puis départ pendant l'écriture
				w.Clock.advance(20)
				local t1 = w.Clock.now()
				Bots.leave(p)
				task.wait(1.5)
				w.h:settle(3)
				local saved = Chaos.record(shared, 1)
				local expected = pot0 + Formulas.potGain(K, S1, growth0, growth0.t, t1)
				expect(near(saved.pot, expected)).toBe(true)
				expect(table.concat(caught, "\n")).toBe("")
				expect(table.concat(w.h.errors, "\n")).toBe("")
				expect(table.concat(w.h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
