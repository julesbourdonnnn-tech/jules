--!nocheck
-- Correctifs r3 « serveur 3 » — DataService :
--   * une écriture n'a lieu que si CETTE session détient encore le verrou (même JobId ET même jeton) :
--     une sauvegarde de départ retardée qui arrive après qu'un autre serveur a repris, joué puis
--     libéré la session (verrou absent) n'écrase plus jamais ses données (achats acquittés compris)
--   * arrivée d'un vétéran (640 Nebbies) sous le budget réseau GDD §12.8 : l'instantané ne porte
--     qu'une avance de « nebbies » (les perchés d'abord), le reste suit en flux d'entrées DataPatch ;
--     le vrai StateController reconstruit exactement la collection du serveur (Wire)

local Wire = require("../harness/Wire")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local STORE = "PlayerData_v1"
	local DT = 0.1

	local function boot()
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
		}
		h:boot()
		return ctx
	end

	local function store(ctx)
		return ctx.h.game.DataStoreService:GetDataStore(STORE)
	end

	local function stored(ctx, userId)
		return store(ctx):GetAsync("player_" .. userId)
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- -------------------------------------------------------------------------------------------
	describe("Fix r3 serveur 3 › écriture seulement par la session qui détient le verrou", function()
		it("verrou absent (repris puis libéré ailleurs) : ni saveNow ni départ n'écrasent", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			data.glow = 10
			expect(ctx.DS.saveNow(p)).toBe(true)
			-- serveur B : a repris la session, joué, acquitté un achat, puis libéré le verrou
			local rec = stored(ctx, 1)
			rec.lock = nil
			rec.data.glow = 999
			rec.data.receipts = { ["achat-b"] = true }
			store(ctx):SetAsync("player_1", rec)
			-- l'autosave / saveNow tardif de A : refusé, rien d'écrit
			data.glow = 11
			expect(ctx.DS.saveNow(p)).toBe(false)
			expect(stored(ctx, 1).data.glow).toBe(999)
			expect(stored(ctx, 1).lock).toBeNil()
			-- la sauvegarde de départ retardée de A : refusée aussi (et jamais de verrou repris)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			local after = stored(ctx, 1)
			expect(after.data.glow).toBe(999)
			expect(after.data.receipts["achat-b"]).toBe(true)
			expect(after.lock).toBeNil()
		end)

		it("même serveur, autre session (autre jeton) : jamais d'écriture", function()
			local ctx = boot()
			local p, data = join(ctx, 2)
			expect(ctx.DS.saveNow(p)).toBe(true)
			local rec = stored(ctx, 2)
			expect(rec.lock.jobId).toBe(ctx.h.game.JobId)
			rec.lock.session = "session-plus-recente"
			rec.data.glow = 4242
			store(ctx):SetAsync("player_2", rec)
			data.glow = 1
			expect(ctx.DS.saveNow(p)).toBe(false)
			expect(stored(ctx, 2).data.glow).toBe(4242)
			expect(stored(ctx, 2).lock.session).toBe("session-plus-recente")
		end)

		it("session intacte : autosave, saveNow et départ écrivent normalement", function()
			local ctx = boot()
			local p, data = join(ctx, 3)
			data.glow = 77
			expect(ctx.DS.saveNow(p)).toBe(true)
			expect(stored(ctx, 3).data.glow).toBe(77)
			expect(stored(ctx, 3).lock ~= nil).toBe(true)
			data.glow = 78
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			expect(stored(ctx, 3).data.glow).toBe(78)
			expect(stored(ctx, 3).lock).toBeNil()
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	-- Taille d'une charge utile avec l'encodage des remotes Roblox (estimation : nombre 9 o, chaîne
	-- longueur + 2, table 3 o + clés et valeurs)
	local function bytes(v)
		local t = typeof(v)
		if t == "nil" then
			return 1
		elseif t == "boolean" then
			return 2
		elseif t == "number" then
			return 9
		elseif t == "string" then
			return 2 + #v
		elseif t == "buffer" then
			return 3 + buffer.len(v)
		elseif t == "table" then
			local n = 3
			for k, x in v do
				if k ~= "n" then
					n += (if type(k) == "number" then 0 else bytes(k)) + bytes(x)
				end
			end
			return n
		end
		return 13
	end

	local function seedVeteran(ctx, userId, n)
		local profile = ctx.Schema.defaults()
		profile.nebbies = {}
		for i = 1, n do
			profile.nebbies["u" .. i] = { s = 1 + (i % 30), f = i % 6, v = 0, st = 1 + (i % 3) }
		end
		profile.nextUid = n + 1
		store(ctx):SetAsync("player_" .. userId, { data = profile })
	end

	describe("Fix r3 serveur 3 › arrivée d'un vétéran sous le budget réseau (§12.8)", function()
		it(
			"640 Nebbies : instantané léger, flux étalé, collection reconstruite à l'identique",
			function()
				local ctx = boot()
				seedVeteran(ctx, 1, 640)
				local rec = Wire.record(ctx.h, { userId = 1, Clock = ctx.Clock })
				local p, data = join(ctx, 1)
				local t0 = ctx.Clock.now()
				for _ = 1, 80 do -- 8 s de jeu
					ctx.Clock.advance(DT)
					ctx.h:step(DT, 1)
				end
				ctx.h:settle(2)
				rec:stop()
				expect(#rec.problems).toBe(0)
				-- octets du profil (DataSnapshot + DataPatch) par seconde depuis l'arrivée
				local perSecond = {}
				local snapshots = 0
				for _, e in rec.events do
					if e.kind == "remote" and (e.remote == "DataSnapshot" or e.remote == "DataPatch") then
						local second = math.floor(e.t - t0)
						local size = 0
						for i = 1, e.args.n do
							size += bytes(e.args[i])
						end
						perSecond[second] = (perSecond[second] or 0) + size
						if e.remote == "DataSnapshot" then
							snapshots += 1
							-- les perchés partent dans l'instantané
							for _, uid in ctx.A.perched(p) do
								expect(e.args[1].nebbies[uid] ~= nil).toBe(true)
							end
						end
					end
				end
				expect(snapshots).toBe(1)
				-- seconde d'arrivée : le profil laisse la place au WorldSnapshot (≤ 8 Ko au lieu de ≈ 40)
				expect((perSecond[0] or 0) <= 8 * 1024).toBe(true)
				for _, b in perSecond do
					expect(b <= 16 * 1024).toBe(true)
				end
				-- collection reconstruite par le VRAI StateController à partir de ce qui a été envoyé
				local expected = {}
				for uid, r in data.nebbies do
					expected[uid] = table.clone(r)
				end
				expect(count(expected)).toBe(640)
				local server = Wire.saveContext()
				local c = Harness.new({ mode = "client" })
				c:createRemotes()
				local State =
					c:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")
				State.Init()
				for _, e in rec.events do
					if e.kind == "remote" and (e.remote == "DataSnapshot" or e.remote == "DataPatch") then
						c:fireClient(
							"ReplicatedStorage.Remotes." .. e.remote,
							table.unpack(e.args, 1, e.args.n)
						)
					end
				end
				c:settle(2)
				local got = State.get("nebbies")
				expect(count(got)).toBe(640)
				for uid, r in expected do
					expect(got[uid]).toEqual(r)
				end
				expect(#c.errors).toBe(0)
				Wire.restoreContext(server)
			end
		)

		it("une entrée modifiée ou supprimée pendant le flux part à jour, jamais ressuscitée", function()
			local ctx = boot()
			seedVeteran(ctx, 2, 300)
			local p, data = join(ctx, 2)
			local snap = ctx.h:sentTo(p, "DataSnapshot")[1][1]
			expect(count(snap.nebbies) < 300).toBe(true)
			-- une entrée pas encore envoyée est libérée, une autre verrouillée
			local missing = {}
			for uid in data.nebbies do
				if snap.nebbies[uid] == nil then
					table.insert(missing, uid)
				end
			end
			table.sort(missing)
			local gone, locked = missing[1], missing[2]
			ctx.h:fireServer("ReplicatedStorage.Remotes.Release", p, { gone })
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, locked, true)
			ctx.h:settle(2)
			expect(data.nebbies[gone]).toBeNil()
			for _ = 1, 60 do
				ctx.Clock.advance(DT)
				ctx.h:step(DT, 1)
			end
			ctx.h:settle(2)
			-- vue client reconstruite : instantané puis patchs dans l'ordre
			local view = table.clone(snap.nebbies)
			for _, args in ctx.h:sentTo(p, "DataPatch") do
				local entries = args[3]
				if type(entries) == "table" and entries.nebbies then
					for uid, r in entries.nebbies.set or {} do
						view[uid] = r
					end
					for _, uid in entries.nebbies.del or {} do
						view[uid] = nil
					end
				end
			end
			expect(view[gone]).toBeNil()
			expect(view[locked].lk).toBe(true)
			expect(count(view)).toBe(count(data.nebbies))
		end)

		it("petite collection : instantané complet, aucun flux", function()
			local ctx = boot()
			seedVeteran(ctx, 3, 30)
			local p = join(ctx, 3)
			local base = #ctx.h:sentTo(p, "DataPatch")
			for _ = 1, 30 do
				ctx.Clock.advance(DT)
				ctx.h:step(DT, 1)
			end
			ctx.h:settle(2)
			expect(count(ctx.h:sentTo(p, "DataSnapshot")[1][1].nebbies)).toBe(30)
			for i = base + 1, #ctx.h:sentTo(p, "DataPatch") do
				local entries = ctx.h:sentTo(p, "DataPatch")[i][3]
				expect(type(entries) ~= "table" or entries.nebbies == nil).toBe(true)
			end
		end)
	end)
end
