--!nocheck
-- Remotes_Ranch (paquet ranch, docs/04 §17.1 couche b, §18.2) : chaque intention du paquet attaquée
-- (Config/Intents : Press, PickUp, PutDown, Throw, FuseMenu, FuseAll, BuyTile, MoveSquishy, ClaimMail,
-- Sell, Release, SetLock, SetBestFriend, SetMount, Ride, EquipOutfit, RequestWorld) : mauvais types,
-- nil, NaN, ±inf, nombres énormes, chaînes de 100 000 caractères, UTF-8 invalide, tables profondes,
-- mixtes ou à trous, Vector3, uid d'un autre joueur → AUCUNE mutation du profil, aucune erreur, aucun
-- avertissement, au plus un Feedback neutre par message ; rafales de 1 000 messages : seau à jetons au
-- débit de Config/Intents. (tests/harness/Fuzz du paquet meta n'existe pas encore : générateur local
-- par sorte d'argument, même catalogue.)
local roblox = require("@lune/roblox")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."
	local RANCH_INTENTS = {
		"Press",
		"PickUp",
		"PutDown",
		"Throw",
		"FuseMenu",
		"FuseAll",
		"BuyTile",
		"MoveSquishy",
		"ClaimMail",
		"Sell",
		"Release",
		"SetLock",
		"SetBestFriend",
		"SetMount",
		"Ride",
		"EquipOutfit",
		"RequestWorld",
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

	-- Valeurs hostiles communes (toutes sortes d'arguments)
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
			{ v = -0.0 },
			{ v = 2 ^ 53 + 1 },
			{ v = 3.5 },
			{ v = -1 },
			{ v = true },
			{ v = "" },
			{ v = string.rep("a", 100000) },
			{ v = "\255\254\253" },
			{ v = "ZZ!" },
			{ v = "123456789" },
			{ v = deep },
			{ v = { 1, 2, nil, 4 } },
			{ v = { 1, 2, x = "y" } },
			{ v = { [1.5] = true } },
			{ v = roblox.Vector3.new(1, 2, 3) },
		}
	end

	-- Squishies d'un autre joueur (uid absents du profil de l'attaquant)
	local OTHER_UIDS = { "5", "6", "7", "8" }

	local function boot()
		local caught = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				local function rec(extra)
					local r = {
						s = 1,
						m = 0,
						st = 0,
						z = 10,
						zg = 0,
						bf = 0,
						lk = false,
						o = "",
						at = "pen",
						b = 1,
						gd = 0,
					}
					for k, v in extra do
						r[k] = v
					end
					return r
				end
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = { ["1"] = rec({ bf = 1 }), ["2"] = rec({ s = 2, at = "dodo" }) },
					nextUid = 3,
					coins = 5,
				})
				Bots.saveProfile(w, 1, d)
				local other = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = {},
					nextUid = 9,
				})
				for _, uid in OTHER_UIDS do
					other.squishies[uid] = rec({ s = 3 })
				end
				other.squishies["5"].bf = 1
				Bots.saveProfile(w, 2, other)
			end,
		})
		w.caught = caught
		w.Intents = w.h:require("ReplicatedStorage.Shared.Config.Intents")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	-- Charges : pour chaque argument, chaque valeur hostile (les autres arguments restent plausibles),
	-- plus les uids d'un autre joueur et des arguments en trop
	local function payloads(spec)
		local plausible = {
			uid = "1",
			uidOpt = "1",
			uids = { "1" },
			time = T0,
			dir = 1,
			bool = true,
			int = 1,
			userId = 2,
			userIds = { 2 },
			key = nil,
			str = "sweater",
			setting = true,
		}
		local function base()
			local out = {}
			for i, arg in spec.args do
				local v = plausible[arg.kind]
				if arg.kind == "key" then
					v = arg.set[1]
				end
				out[i] = v
			end
			return out
		end
		local list = {}
		for i, arg in spec.args do
			for _, h in hostile() do
				-- une valeur valide pour cette sorte (un booléen pour « bool ») n'est pas hostile
				if not (arg.kind == "bool" and type(h.v) == "boolean") then
					local p = base()
					p[i] = h.v
					table.insert(list, p)
				end
			end
			if arg.kind == "uid" or arg.kind == "uidOpt" then
				for _, uid in OTHER_UIDS do
					local p = base()
					p[i] = uid
					table.insert(list, p)
				end
			elseif arg.kind == "uids" then
				local p = base()
				p[i] = OTHER_UIDS
				table.insert(list, p)
				local dup = base()
				dup[i] = { "1", "1" }
				table.insert(list, dup)
				local big = {}
				for n = 1, 85 do
					big[n] = tostring(n)
				end
				local over = base()
				over[i] = big
				table.insert(list, over)
			end
		end
		-- arguments en trop (jamais lus), squishy d'un autre joueur : refusé
		local extra = base()
		for i, arg in spec.args do
			if arg.kind == "uid" or arg.kind == "uidOpt" then
				extra[i] = OTHER_UIDS[2]
			elseif arg.kind == "uids" then
				extra[i] = { OTHER_UIDS[2] }
			end
		end
		table.insert(extra, string.rep("x", 1000))
		table.insert(list, extra)
		return list
	end

	describe("Remotes_Ranch › charges hostiles", function()
		for _, name in RANCH_INTENTS do
			it(
				name .. " : aucune mutation du profil, aucune erreur, au plus un Feedback neutre par message",
				function()
					local w = boot()
					local p = Bots.join(1)
					local q = Bots.join(2)
					w.h:settle(2)
					local data = w.DS.get(p)
					local other = w.DS.get(q)
					-- état dérivé à jour (records de l'Étagère, plus gros squishy : premier règlement)
					local Economy = w.h:require(S .. "EconomyService")
					Economy.settle(p)
					Economy.settle(q)
					local spec = w.Intents[name]
					local before = deepCopy(data)
					local otherBefore = deepCopy(other)
					local list = payloads(spec)
					local fbBefore = #w.h:sentTo(p, "Feedback")
					for _, args in list do
						w.RateLimit.clear(p)
						w.h
							:find(R .. name).OnServerEvent
							:Fire(p, table.unpack(args, 1, math.max(#spec.args, #args)))
					end
					w.h:settle(3)
					-- uid d'un autre joueur, valeurs bizarres : rien n'a changé (ni chez lui, ni chez l'autre)
					expect(deepEqual(data, before)).toBe(true)
					expect(deepEqual(other, otherBefore)).toBe(true)
					expect(#w.h:sentTo(p, "Feedback") - fbBefore <= #list).toBe(true)
					clean(w)
				end
			)
		end
	end)

	describe("Remotes_Ranch › débit (seau à jetons de Config/Intents)", function()
		it("rafale de 1 000 SetLock en une image : au plus 6 acceptés (6 / 1 s)", function()
			local w = boot()
			local p = Bots.join(1)
			local accepted = 0
			local original = w.DS.markDirtyEntry
			w.DS.markDirtyEntry = function(player, key, sub)
				if player == p and key == "squishies" then
					accepted += 1
				end
				return original(player, key, sub)
			end
			local remote = w.h:find(R .. "SetLock")
			for i = 1, 1000 do
				remote.OnServerEvent:Fire(p, "1", i % 2 == 0)
			end
			w.h:settle(2)
			expect(accepted <= w.Intents.SetLock.rate[1]).toBe(true)
			expect(accepted >= 1).toBe(true)
			clean(w)
		end)

		it("rafale de 1 000 BuyTile : au plus 10 traités (10 / 1 s), aucune pièce créée", function()
			local w = boot()
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local Economy = w.h:require(S .. "EconomyService")
			local calls = 0
			local original = Economy.buyTile
			Economy.buyTile = function(...)
				calls += 1
				return original(...)
			end
			local remote = w.h:find(R .. "BuyTile")
			for _ = 1, 1000 do
				remote.OnServerEvent:Fire(p, "pens")
			end
			w.h:settle(2)
			expect(calls <= w.Intents.BuyTile.rate[1]).toBe(true)
			expect(data.coins).toBe(5)
			clean(w)
		end)

		it("rafale de 1 000 Press : au plus 12 traités ; recharge de 8 s : une seule récompense", function()
			local w = boot()
			local p = Bots.join(1)
			local data = w.DS.get(p)
			local Squishy = w.h:require(S .. "SquishyService")
			local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
			local c = Squishy.placeOf(p, "1")
			MoveCheck.reset(p, w.V3.new(c.X, 3, c.Z), w.Clock.now())
			local remote = w.h:find(R .. "Press")
			for _ = 1, 1000 do
				remote.OnServerEvent:Fire(p, "1", T0)
			end
			w.h:settle(2)
			local presses = 0
			for _, args in w.h:sentTo(p, "Celebrate") do
				if args[1].kind == "press" then
					presses += 1
				end
			end
			expect(presses).toBe(1)
			expect(data.coins > 5).toBe(true)
			clean(w)
		end)
	end)
end
