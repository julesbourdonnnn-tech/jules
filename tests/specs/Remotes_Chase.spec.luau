--!nocheck
-- Remotes_Chase (paquet chase, docs/04 §17.1 couche b, §18.2) : chaque intention du paquet attaquée
-- (Config/Intents : Leap, Catch, BoopHold, SetMode, RefuseBooper, MegaPress, AdminCommand,
-- GrandSplorch ; JellyAscend depuis le lot A2, note INT-V2-INTENTS : interrupteur coupé, puis ouvert avec
-- un attaquant prêt pour l'Ascension) : mauvais types, nil, NaN, ±inf, nombres énormes, chaînes de 100 000 caractères, UTF-8
-- invalide, tables profondes, mixtes ou à trous, Vector3, uid d'un autre joueur → AUCUNE mutation des
-- profils (attaquant et autres), aucune créature, aucun spectacle, aucun point, aucune erreur, aucun
-- avertissement, au plus un Feedback neutre par message ; rafales de 1 000 messages : seau à jetons au
-- débit de Config/Intents. (tests/harness/Fuzz du paquet meta n'existe pas encore : générateur local par
-- sorte d'argument, même catalogue que Remotes_Ranch.)
local roblox = require("@lune/roblox")
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 1205 -- MEGA en pression, Rush de :25 plus tard
	local R = "ReplicatedStorage.Remotes."
	local CHASE_INTENTS = {
		"Leap",
		"Catch",
		"BoopHold",
		"SetMode",
		"RefuseBooper",
		"MegaPress",
		"AdminCommand",
		"GrandSplorch",
		"JellyAscend", -- lot A2 (note INT-V2-INTENTS, journal A2-23)
	}

	local function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	local function deepEqual(a, b)
		if a == b then
			return true
		end
		if a ~= a and b ~= b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	local function hostile()
		local deep = {}
		local cur = deep
		for _ = 1, 60 do
			cur.next = {}
			cur = cur.next
		end
		return {
			{ v = nil },
			{ v = 0 / 0 },
			{ v = math.huge },
			{ v = -math.huge },
			{ v = 1e308 },
			{ v = -1e308 },
			{ v = 2 ^ 53 + 1 },
			{ v = 3.5 },
			{ v = -1 },
			{ v = 0 },
			{ v = 70000 },
			{ v = true },
			{ v = "" },
			{ v = string.rep("a", 100000) },
			{ v = "\255\254\253" },
			{ v = "ZZ!" },
			{ v = deep },
			{ v = { 1, 2, nil, 4 } },
			{ v = { 1, 2, x = "y" } },
			{ v = roblox.Vector3.new(1, 2, 3) },
		}
	end

	local OTHER_UIDS = { "2", "3", "4" }

	local function payloads(spec)
		local plausible = {
			uid = "1",
			time = T0,
			dir = 0.1, -- composante plausible, norme trop petite avec l'autre à 0,1 : refusée
			bool = true,
			int = 1,
			userId = 2,
			str = "nothing",
		}
		local function base()
			local out = {}
			for i, arg in spec.args do
				out[i] = plausible[arg.kind]
			end
			return out
		end
		local list = {}
		for i, arg in spec.args do
			for _, h in hostile() do
				if not (arg.kind == "bool" and type(h.v) == "boolean") then
					local p = base()
					p[i] = h.v
					table.insert(list, p)
				end
			end
			if arg.kind == "uid" then
				for _, uid in OTHER_UIDS do
					local p = base()
					p[i] = uid
					table.insert(list, p)
				end
			end
		end
		return list
	end

	local function boot()
		local w = Brains.boot(Harness, { t0 = T0 })
		-- attaquant : petit squishy (jamais prêt pour le Grand Splorch), loin du MEGA ; victime en mode Rush
		local attacker =
			Brains.join(w, 1, { profile = Brains.profile(w, { squishies = { { s = 2, z = 10 } } }) })
		local victim = Brains.join(w, 2, {
			profile = Brains.profile(w, {
				rush = true,
				squishies = {
					{ s = 1, z = 30000, bf = 1 },
					{ s = 2, z = 40 },
					{ s = 3, z = 40 },
					{ s = 4, z = 40 },
				},
			}),
		})
		Bots.place(attacker, Brains.atRanch(w, attacker, 0, 30))
		Brains.frames(w, 2)
		w.Intents = w.h:require("ReplicatedStorage.Shared.Config.Intents")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w, attacker, victim
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function snapshot(w)
		local st = w.Event.state()
		return {
			creatures = #Brains.creatures(w),
			megaPoints = st.mega.points,
			queue = #st.spectacle.queue,
			current = st.spectacle.current ~= nil,
			features = deepCopy(st.features),
			offset = st.offset,
			boost = st.boost.kind,
			holds = #w.Rush.openStates(),
		}
	end

	describe("Remotes_Chase › charges hostiles", function()
		for _, name in CHASE_INTENTS do
			it(
				name
					.. " : aucune mutation des profils ni de l'état du jeu, aucune erreur, au plus un Feedback par message",
				function()
					local w, attacker, victim = boot()
					w.Economy.settle(attacker)
					w.Economy.settle(victim)
					local a0 = deepCopy(w.DS.get(attacker))
					local v0 = deepCopy(w.DS.get(victim))
					local s0 = snapshot(w)
					local spec = w.Intents[name]
					local list = payloads(spec)
					local fb0 = #w.h:sentTo(attacker, "Feedback")
					for _, args in list do
						w.RateLimit.clear(attacker)
						w.h:find(R .. name).OnServerEvent:Fire(attacker, table.unpack(args, 1, #spec.args))
					end
					w.h:settle(3)
					expect(deepEqual(w.DS.get(attacker), a0)).toBe(true)
					expect(deepEqual(w.DS.get(victim), v0)).toBe(true)
					expect(deepEqual(snapshot(w), s0)).toBe(true)
					expect(#w.h:sentTo(attacker, "Feedback") - fb0 <= #list).toBe(true)
					Brains.frames(w, 3)
					expect(deepEqual(snapshot(w).creatures, s0.creatures)).toBe(true)
					clean(w)
				end
			)
		end

		it("arguments en trop : jamais lus (SetMode accepté une fois, le reste ignoré)", function()
			local w, attacker = boot()
			w.h
				:find(R .. "SetMode").OnServerEvent
				:Fire(attacker, true, string.rep("x", 1000), { 1, 2 }, 0 / 0)
			w.h:settle(2)
			expect(w.Rush.isRush(attacker)).toBe(true)
			clean(w)
		end)
	end)

	describe("Remotes_Chase › débit (seau à jetons de Config/Intents)", function()
		it(
			"rafale de 1 000 Leap en une image : un seul crédit de bond (recharge 4 s), au plus 3 traités",
			function()
				local w, attacker = boot()
				local grants, calls = 0, 0
				local grant = w.MC.grant
				w.MC.grant = function(...)
					calls += 1
					local ok = grant(...)
					if ok then
						grants += 1
					end
					return ok
				end
				local remote = w.h:find(R .. "Leap")
				for _ = 1, 1000 do
					remote.OnServerEvent:Fire(attacker, 1, 0, w.Clock.now())
				end
				w.h:settle(2)
				expect(grants).toBe(1)
				expect(calls <= w.Intents.Leap.rate[1]).toBe(true)
				w.MC.grant = grant
				clean(w)
			end
		)

		it("rafale de 1 000 Catch / MegaPress / AdminCommand : débit respecté, aucune erreur", function()
			local w, attacker = boot()
			local pad = w.WL.plaza("megaPad")
			Bots.place(attacker, Bots.ground(pad.X + 3, pad.Z))
			Brains.frames(w, 2)
			local before = w.Event.state().mega.points
			local remote = w.h:find(R .. "MegaPress")
			for _ = 1, 1000 do
				remote.OnServerEvent:Fire(attacker, w.Clock.now())
			end
			w.h:settle(2)
			local gained = w.Event.state().mega.points - before
			expect(gained <= 3).toBe(true)
			expect(gained >= 1).toBe(true)
			local catch = w.h:find(R .. "Catch")
			local admin = w.h:find(R .. "AdminCommand")
			for i = 1, 1000 do
				catch.OnServerEvent:Fire(attacker, (i % 65535) + 1, w.Clock.now())
				admin.OnServerEvent:Fire(attacker, "party", "")
			end
			w.h:settle(2)
			Brains.frames(w, 2)
			expect(w.Event.state().boost.kind).toBe("")
			clean(w)
		end)
	end)
	-- Jelly Ascend ouverte (lot A2, étape 3) : serveur v2, interrupteurs ouverts, attaquant PRÊT pour sa
	-- 1re Ascension (r = Record R = 15) : seule une confirmation booléenne vraie peut l'accepter
	describe("Remotes_Chase › JellyAscend ouverte (lot A2)", function()
		local L = "ReplicatedStorage.Shared."
		local HarnessV2 = setmetatable({
			new = function(options)
				local hh = Harness.new(options)
				hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
				return hh
			end,
		}, { __index = Harness })

		local function bootV2()
			-- loin de tout Rush ou MEGA : le spectacle de l'Ascension part tout de suite
			local w = Brains.boot(HarnessV2, { t0 = 1800000000 + 60 })
			for _, key in { "RecordR", "Confetti", "JellyAscend", "PetitSplorch" } do
				assert(w.Features.set(key, true), key)
			end
			local attacker = Brains.join(w, 1, {
				profile = Brains.profile(w, {
					R = 15,
					squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 }, { s = 3, z = 300 } },
					edit = function(d)
						d.bestR = 15
					end,
				}),
			})
			local victim =
				Brains.join(w, 2, { profile = Brains.profile(w, { squishies = { { s = 2, z = 40 } } }) })
			Bots.place(attacker, Brains.atRanch(w, attacker, 0, 30))
			Brains.frames(w, 2)
			w.Intents = w.h:require(L .. "Config.Intents")
			w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
			return w, attacker, victim
		end

		it(
			"JellyAscend [JellyAscend] : charges hostiles → aucune mutation, aucun spectacle, aucune réponse, aucune erreur",
			function()
				local w, attacker, victim = bootV2()
				w.Economy.settle(attacker)
				w.Economy.settle(victim)
				local a0 = deepCopy(w.DS.get(attacker))
				local v0 = deepCopy(w.DS.get(victim))
				local s0 = snapshot(w)
				local spec = w.Intents.JellyAscend
				local list = payloads(spec)
				expect(#list > 10).toBe(true)
				local fb0 = #w.h:sentTo(attacker, "Feedback")
				for _, args in list do
					w.RateLimit.clear(attacker)
					w.h
						:find(R .. "JellyAscend").OnServerEvent
						:Fire(attacker, table.unpack(args, 1, #spec.args))
				end
				-- confirmation fausse : rien non plus
				w.RateLimit.clear(attacker)
				w.h:find(R .. "JellyAscend").OnServerEvent:Fire(attacker, false)
				w.h:settle(3)
				expect(deepEqual(w.DS.get(attacker), a0)).toBe(true)
				expect(deepEqual(w.DS.get(victim), v0)).toBe(true)
				expect(deepEqual(snapshot(w), s0)).toBe(true)
				expect(#w.h:sentTo(attacker, "Feedback")).toBe(fb0)
				expect(w.Splorch.queued(attacker)).toBeNil()
				clean(w)
			end
		)

		it(
			"rafale de 1 000 JellyAscend(true) en une image : une seule entrée dans la file, une seule Ascension",
			function()
				local w, attacker = bootV2()
				local remote = w.h:find(R .. "JellyAscend")
				for _ = 1, 1000 do
					remote.OnServerEvent:Fire(attacker, true)
				end
				w.h:settle(2)
				local entries = 0
				for _, entry in w.Event.state().spectacle.queue do
					if entry.userId == attacker.UserId then
						entries += 1
					end
				end
				local current = w.Event.state().spectacle.current
				if current and current.userId == attacker.UserId then
					entries += 1
				end
				expect(entries).toBe(1)
				Brains.frames(w, 150)
				for _ = 1, 1000 do
					remote.OnServerEvent:Fire(attacker, true)
				end
				w.h:settle(2)
				Brains.frames(w, 60)
				local data = w.DS.get(attacker)
				expect(data.ascend).toBe(1)
				expect(data.confetti).toBe(w.Balance.Confetti.PerAscend)
				expect(w.Splorch.queued(attacker)).toBeNil()
				clean(w)
			end
		)
	end)
end
