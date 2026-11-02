--!nocheck
-- Validation de la version (docs/04 §22.2, §23) : notes d'intégration appliquées par le validateur.
--   * INT-LR10 : le portage a un délai de sûreté (consigne du propriétaire : chaque état a un délai et
--     une sortie). Après Balance.Carry.SafetySeconds, le squishy retourne à sa place ; avant, rien ne
--     change ; le contrôle du robot de longue durée (StateTimeouts « carry ») ne voit jamais d'état échu.
--   * §23 : plus aucune marque de stub du contrat dans src (tous les paquets sont livrés).
--   * INT-CWR-3 : l'invite du Bassin sans jumeau est « Poser dans le Bassin » (GDD §4.9), en EN et FR.
--   * Note croisée client n° 3 : chaque message central vit 2,5 s (GDD §10.2), un seul à la fois.
--   * Bannières du BOOP RUSH en mode « events » : seulement pendant la Jelly Moon ou une fête
--     d'administrateur, comme le serveur (RushService) et le ciel (LightingController).
local fs = require("@lune/fs")
local Bots = require("../harness/Bots")
local TvAudit = require("../harness/TvAudit")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function boot(before)
		local caught = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				if before then
					before(w)
				end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		w.Squishy = w.h:require(S .. "SquishyService")
		w.MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.StateTimeouts = w.h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		return w
	end

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 0, z = 10, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	-- Un tick du serveur pour p (acteur à sa position validée), puis contrôle des délais des états
	local function tick(w, p, seconds)
		w.Clock.advance(seconds)
		local pos = w.MoveCheck.lastValid(p)
		local actors = {
			[p] = {
				player = p,
				slot = w.Ranch.slotOf(p),
				pos = pos,
				canAct = true,
				riding = false,
				rootOffset = 0,
			},
		}
		w.Squishy.step(w.Clock.now(), actors)
		for _, s in w.Squishy.openStates() do
			assert(
				not w.StateTimeouts.expired(s.name, s.startedAt, w.Clock.now()),
				"état ouvert au-delà de son délai : " .. s.name
			)
		end
	end

	describe("Validation de la version", function()
		it(
			"INT-LR10 : portage fermé par son délai de sûreté, squishy à sa place, aucune trace",
			function()
				local w = boot(function(w)
					local d = Bots.profile(w, {
						onboarding = { step = 11, done = true, demoDone = true },
						squishies = { ["1"] = rec(), ["2"] = rec({ z = 20 }) },
						nextUid = 3,
					})
					d.stats.playSeconds = 10000
					Bots.saveProfile(w, 1, d)
				end)
				local p = Bots.join(1)
				local safety = w.Balance.Carry.SafetySeconds
				expect(safety).toBe(300)
				-- le contrôle des délais garde 1 s de grâce au-delà de la fermeture par le service
				expect(w.StateTimeouts.seconds("carry")).toBe(safety + 1)
				local c = w.Squishy.placeOf(p, "1")
				w.MoveCheck.reset(p, w.V3.new(c.X, 3, c.Z), w.Clock.now())
				w.RateLimit.clear(p)
				w.h:fireServer(R .. "PickUp", p, "1")
				expect(w.Squishy.carried(p)).toBe("1")
				expect(w.Ranch.publicOf(1).carry).toBe("1")
				-- 299,9 s de portage (ticks de 10 s, puis le dernier) : toujours porté
				for _ = 1, 29 do
					tick(w, p, 10)
				end
				tick(w, p, 9.9)
				expect(w.Squishy.carried(p)).toBe("1")
				-- 300 s : le squishy retourne à sa place (comme « Poser »), rien d'autre ne change
				tick(w, p, 0.1)
				expect(w.Squishy.carried(p)).toBeNil()
				expect(w.Ranch.publicOf(1).carry).toBe("")
				local data = w.DS.get(p)
				expect(data.squishies["1"].at).toBe("pen")
				expect(data.squishies["2"].at).toBe("pen")
				-- le joueur peut le reprendre aussitôt
				w.RateLimit.clear(p)
				w.h:fireServer(R .. "PickUp", p, "1")
				expect(w.Squishy.carried(p)).toBe("1")
				tick(w, p, 0.1)
				expect(w.Squishy.carried(p)).toBe("1")
				expect(table.concat(w.caught, "\n")).toBe("")
				expect(table.concat(w.h.errors, "\n")).toBe("")
				expect(table.concat(w.h:warnings(), "\n")).toBe("")
			end
		)

		it("§23 : aucune marque de stub du contrat dans src (tous les paquets livrés)", function()
			local mark = "TODO" .. "("
			local found = {}
			local function scan(dir)
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(name, -5) == ".luau" then
						local source = fs.readFile(path)
						if string.find(source, mark, 1, true) then
							table.insert(found, path)
						end
					end
				end
			end
			scan("src")
			expect(table.concat(found, "\n")).toBe("")
		end)

		it("INT-CWR-3 : texte de l'invite « Poser dans le Bassin » en EN et FR (GDD §4.9)", function()
			local h = Harness.new()
			local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
			expect(Strings.en["prompt.putInPool"]).toBe("Put in Pool")
			expect(Strings.fr["prompt.putInPool"]).toBe("Poser dans le Bassin")
		end)

		it("GDD §10.2 : messages de 2,5 s chacun, un seul à la fois, le suivant ensuite", function()
			local h =
				TvAudit.client({ profile = { onboarding = { step = 11, done = true, demoDone = true } } })
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			local Toast = TvAudit.mod(h, "UI.Toast")
			expect(Toast.Lifetime).toBe(2.5)
			M._reset()
			local shown = {}
			Toast.show = function(text)
				table.insert(shown, text)
			end
			M.push("One", "info")
			M.push("Two", "info")
			M.step(Clock.now())
			expect(#shown).toBe(1)
			expect(M.busy(Clock.now())).toBe(true)
			Clock.advance(2.6)
			M.step(Clock.now())
			expect(#shown).toBe(1)
			Clock.advance(0.15)
			M.step(Clock.now())
			expect(shown).toEqual({ "One", "Two" })
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)

		it(
			"bannières du Rush en mode « events » : pendant une fête d'administrateur seulement",
			function()
				local RUSH_START = 1800000300 -- prochain BOOP RUSH après 1800000000 (EventClock)
				local h =
					TvAudit.client({ profile = { onboarding = { step = 11, done = true, demoDone = true } } })
				local B = TvAudit.mod(h, "UI.Banners")
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
				local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
				local boost = { kind = "", untilT = 0, byName = "" }
				local f = {
					boopRush = "events",
					megaSquish = false,
					golden = true,
					jellyMoon = false,
					gauge = true,
					clips = true,
					costume = "",
					diagnostics = true,
				}
				WSC.event = function()
					return { features = f, boost = boost }
				end
				-- sans fête : aucune bannière du Rush
				Clock.freeze(RUSH_START + 0.5)
				expect(EventClock.rush(Clock.now()).startsAt).toBe(RUSH_START)
				B._step()
				expect(B.current()).toBeNil()
				-- Rush suivant pendant une fête d'administrateur : la bannière passe
				local nextStart = EventClock.rush(EventClock.rush(RUSH_START + 1).endsAt).startsAt
				expect(nextStart > RUSH_START).toBe(true)
				boost = { kind = "admin", untilT = nextStart + 600, byName = "Admin" }
				Clock.freeze(nextStart + 0.5)
				B._step()
				expect(B.current() ~= nil and B.current().kind).toBe("rushStart")
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
