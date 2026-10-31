--!nocheck
-- Correctifs « restes serveur : données et réplication » (DataService, AtlasService, StateController) :
--   1. profil écrit par un schéma PLUS RÉCENT : jamais réparé ni réécrit par un serveur plus ancien,
--      le joueur est renvoyé (message bilingue), aucun verrou laissé derrière
--   2. crochets onBeforeSave : drapeau `release` transmis (cadeau Starfall et dernier port de Comète
--      écrits par la sauvegarde de BindToClose)
--   3. réplication de « nebbies » par entrées (set / del) dans DataPatch : jamais la table entière
--      après une parade, un verrou, une fusion ou une libération
--   4. après la sauvegarde de libération, save() ne prétend plus avoir écrit
--   5. verrou de session marqué par un jeton de chargement : une session partie pendant son
--      chargement n'efface pas le verrou d'une reconnexion sur le même serveur
--   6. Starforge : exactement Copies − 1 copies consommées, quel que soit le réglage §17

local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC (Starfall Saturday)
	local STORE = "PlayerData_v1"

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local Tuning = h:require("ServerScriptService.Server.Events.Tuning")
		Tuning.DataStoreRetryDelay = 0.001
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			E = h:require("ServerScriptService.Server.Services.EventService"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
		}
		if opts.before then
			opts.before(ctx)
		end
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

	local function waitUntil(fn, timeout)
		local start = os.clock()
		while not fn() and os.clock() - start < timeout do
			task.wait(0.02)
		end
		return fn()
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	local function seedCollection(ctx, userId, n, rec)
		local profile = ctx.Schema.defaults()
		profile.nebbies = {}
		for i = 1, n do
			profile.nebbies["u" .. i] = if rec
				then table.clone(rec)
				else { s = 1 + (i % 6), f = 0, v = 0, st = 1 }
		end
		profile.nextUid = n + 1
		profile.stardust = 100000
		store(ctx):SetAsync("player_" .. userId, { data = profile })
	end

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › profil d'un schéma plus récent", function()
		local function newerRecord(ctx, lock)
			local profile = ctx.Schema.defaults()
			profile.version = ctx.Schema.VERSION + 1
			profile.glow = 777
			profile.stardust = 55
			-- données « v2 » qu'un serveur v1 jugerait invalides (sanitize les supprimerait)
			profile.nebbies = {
				u1 = { s = 1, f = 0, v = 0, st = 1 },
				u2 = { s = 99, f = 9, v = 64, st = 8, aura = "nova" },
			}
			profile.nextUid = 3
			profile.futureKey = { a = 1, b = { "x", "y" } }
			return { data = profile, lock = lock, meta = { created = 1, lastSave = 2, saves = 41 } }
		end

		it("ni réparé ni sauvegardé, aucun verrou pris, joueur renvoyé (EN/FR)", function()
			local ctx = boot()
			local record = newerRecord(ctx, nil)
			store(ctx):SetAsync("player_1", record)
			local before = stored(ctx, 1)
			local p = ctx.h:addPlayer({ userId = 1, name = "P1" })
			ctx.h:settle(5)
			task.wait(0.1)
			ctx.h:settle(3)
			expect(ctx.DS.get(p)).toBeNil()
			expect(ctx.DS.isLoaded(p)).toBe(false)
			expect(#ctx.h.log.kicks).toBe(1)
			local message = ctx.h.log.kicks[1].message
			expect(string.find(message, "out of date", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "pas à jour", 1, true) ~= nil).toBe(true)
			-- aucun instantané (jamais un profil « réparé » envoyé au client)
			expect(#ctx.h:sentTo(p, "DataSnapshot")).toBe(0)
			-- départ, saveNow et fermeture : rien n'est jamais écrit
			expect(ctx.DS.saveNow(p)).toBe(false)
			ctx.h:removePlayer(p)
			ctx.h:settle(5)
			ctx.h:close()
			ctx.h:settle(3)
			local after = stored(ctx, 1)
			expect(after.lock).toBeNil()
			expect(after).toEqual(before)
			expect(after.data.nebbies.u2.aura).toBe("nova")
			expect(after.data.version).toBe(ctx.Schema.VERSION + 1)
			expect(after.meta.saves).toBe(41)
		end)

		it("verrou tenu par le serveur récent : refus immédiat, verrou intact", function()
			local ctx = boot()
			local lock = { jobId = "serveur-v2", time = os.time() }
			store(ctx):SetAsync("player_2", newerRecord(ctx, lock))
			local before = stored(ctx, 2)
			local p = ctx.h:addPlayer({ userId = 2, name = "P2" })
			-- refus sans attendre l'expiration du verrou (LOAD_ATTEMPTS × LOCKED_RETRY_DELAY)
			expect(waitUntil(function()
				return #ctx.h.log.kicks == 1
			end, 1)).toBe(true)
			ctx.h:settle(3)
			expect(ctx.DS.get(p)).toBeNil()
			local after = stored(ctx, 2)
			expect(after.lock.jobId).toBe("serveur-v2")
			expect(after).toEqual(before)
		end)

		it("même version ou plus ancienne : chargé normalement", function()
			local ctx = boot()
			local profile = ctx.Schema.defaults()
			profile.glow = 12
			store(ctx):SetAsync("player_3", { data = profile })
			local p, data = join(ctx, 3)
			expect(data ~= nil).toBe(true)
			expect(data.glow).toBe(12)
			expect(#ctx.h.log.kicks).toBe(0)
			expect(#ctx.h:sentTo(p, "DataSnapshot")).toBe(1)
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › onBeforeSave reçoit le drapeau release", function()
		it("saveNow : false ; départ et BindToClose : true", function()
			local ctx = boot()
			local seen = {}
			ctx.DS.onBeforeSave(function(player, data, release)
				table.insert(seen, { player = player, data = data, release = release })
			end)
			local a = join(ctx, 1)
			local b = join(ctx, 2)
			table.clear(seen)
			expect(ctx.DS.saveNow(a)).toBe(true)
			expect(#seen).toBe(1)
			expect(seen[1].release).toBe(false)
			ctx.h:removePlayer(b)
			ctx.h:settle(5)
			expect(#seen).toBe(2)
			expect(seen[2].player).toBe(b)
			expect(seen[2].release).toBe(true)
			ctx.h:close()
			ctx.h:settle(3)
			expect(#seen).toBe(3)
			expect(seen[3].player).toBe(a)
			expect(seen[3].release).toBe(true)
		end)

		it("BindToClose pendant un Starfall : cadeau Starborn et stats.starfallGift sauvegardés", function()
			local ctx = boot({ t = SAT - 50 })
			local SF = ctx.Events.Starfall
			local a = join(ctx, 1)
			local function at(t)
				ctx.Clock.freeze(t)
				ctx.E.step(t)
			end
			at(SAT)
			local t = SAT
			while t < SAT + SF.PresenceSeconds + 10 do
				t = math.min(t + 5, SAT + SF.PresenceSeconds + 10)
				at(t)
			end
			expect(ctx.E.snapshot().starfall ~= nil).toBe(true)
			-- le joueur est qualifié, le show continue : le serveur ferme (mise à jour)
			ctx.h:close()
			ctx.h:settle(3)
			local saved = stored(ctx, 1).data
			local featured = ctx.EventClock.featuredSpecies(ctx.Clock.week(SAT))
			local bit = ctx.Nebbies.Variants.starborn.bit
			local starborn = 0
			for _, rec in saved.nebbies do
				if rec.s == featured and rec.v == bit then
					starborn += 1
				end
			end
			expect(starborn).toBe(1)
			expect(saved.stats.starfallGift).toBe(SAT)
			expect(stored(ctx, 1).lock).toBeNil()
			-- puis PlayerRemoving pendant l'arrêt : rien de plus, aucune erreur
			ctx.h:removePlayer(a)
			ctx.h:settle(3)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › réplication de « nebbies » par entrées", function()
		local function nebbiesPatches(ctx, p, from)
			local out = {}
			local all = ctx.h:sentTo(p, "DataPatch")
			for i = (from or 0) + 1, #all do
				local args = all[i]
				if
					(type(args[1]) == "table" and args[1].nebbies ~= nil)
					or (type(args[3]) == "table" and args[3].nebbies ~= nil)
				then
					table.insert(out, args)
				end
			end
			return out
		end

		it("parade de 60 Nebbies sur une collection de 600 : seuls les 60 nouveaux partent", function()
			local ctx = boot()
			-- réserve agrandie : isole la réplication du débordement (testé plus bas)
			ctx.Balance.Stash.Base = 1000
			seedCollection(ctx, 1, 600)
			local p, data = join(ctx, 1)
			local snaps = ctx.h:sentTo(p, "DataSnapshot")
			expect(count(snaps[#snaps][1].nebbies)).toBe(600)
			local base = #ctx.h:sentTo(p, "DataPatch")
			local codes = {}
			for i = 1, 60 do
				table.insert(codes, ctx.Nebbies.pack(1 + (i % 6), 0, 0))
			end
			local created = ctx.A.addNebbies(p, codes, "parade")
			expect(#created).toBe(60)
			ctx.h:settle(2)
			local sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local args = sent[1]
			-- jamais la table entière
			expect(args[1].nebbies).toBeNil()
			local ops = args[3].nebbies
			expect(count(ops.set)).toBe(60)
			for _, uid in created do
				expect(ops.set[uid]).toEqual(data.nebbies[uid])
			end
			expect(#(ops.del or {})).toBe(0)
			-- même message que les clés liées (ordre : perchoirs, Atlas, nextUid)
			expect(args[1].nextUid).toBe(data.nextUid)
			expect(count(data.nebbies)).toBe(660)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("débordement de la réserve : les libérés partent dans `del`", function()
			local ctx = boot()
			seedCollection(ctx, 1, 300)
			local p, data = join(ctx, 1)
			local base = #ctx.h:sentTo(p, "DataPatch")
			local codes = {}
			for i = 1, 40 do
				table.insert(codes, ctx.Nebbies.pack(1 + (i % 6), 0, 0))
			end
			ctx.A.addNebbies(p, codes, "parade")
			ctx.h:settle(2)
			local sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local ops = sent[1][3].nebbies
			expect(sent[1][1].nebbies).toBeNil()
			expect(#(ops.del or {}) > 0).toBe(true)
			for _, uid in ops.del do
				expect(data.nebbies[uid]).toBeNil()
				expect(ops.set[uid]).toBeNil()
			end
			for uid, rec in ops.set do
				expect(data.nebbies[uid]).toEqual(rec)
			end
		end)

		it("verrou, fusion, libération : seules les entrées touchées partent", function()
			local ctx = boot()
			seedCollection(ctx, 1, 200, { s = 2, f = 0, v = 0, st = 1 })
			local p, data = join(ctx, 1)
			local window = ctx.A.Settings.NebbiesPatchInterval + 0.15
			local base = #ctx.h:sentTo(p, "DataPatch")
			-- verrou
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u5", true)
			ctx.h:settle(2)
			local sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(1)
			expect(sent[1][1].nebbies).toBeNil()
			expect(count(sent[1][3].nebbies.set)).toBe(1)
			expect(sent[1][3].nebbies.set.u5.lk).toBe(true)
			task.wait(window)
			ctx.h:settle(2)
			-- fusion : l'élu (★2) et ses deux copies supprimées
			base = #ctx.h:sentTo(p, "DataPatch")
			ctx.h:fireServer("ReplicatedStorage.Remotes.Fuse", p, "u1")
			ctx.h:settle(2)
			sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local ops = sent[1][3].nebbies
			expect(sent[1][1].nebbies).toBeNil()
			expect(count(ops.set)).toBe(1)
			expect(ops.set.u1.st).toBe(2)
			expect(#ops.del).toBe(ctx.Balance.Starforge.Copies - 1)
			for _, uid in ops.del do
				expect(data.nebbies[uid]).toBeNil()
			end
			task.wait(window)
			ctx.h:settle(2)
			-- libération
			base = #ctx.h:sentTo(p, "DataPatch")
			ctx.h:fireServer("ReplicatedStorage.Remotes.Release", p, { "u10", "u11" })
			ctx.h:settle(2)
			sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(1)
			ops = sent[1][3].nebbies
			expect(count(ops.set or {})).toBe(0)
			table.sort(ops.del)
			expect(ops.del).toEqual({ "u10", "u11" })
		end)

		it("rafale de verrous : entrées regroupées en fin de fenêtre (2 Hz)", function()
			local ctx = boot()
			seedCollection(ctx, 1, 50)
			local p = join(ctx, 1)
			local base = #ctx.h:sentTo(p, "DataPatch")
			for i = 1, 6 do
				ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u" .. i, true)
			end
			ctx.h:settle(2)
			expect(#nebbiesPatches(ctx, p, base)).toBe(1)
			task.wait(ctx.A.Settings.NebbiesPatchInterval + 0.15)
			ctx.h:settle(2)
			local sent = nebbiesPatches(ctx, p, base)
			expect(#sent).toBe(2)
			local set = sent[2][3].nebbies.set
			expect(count(set)).toBe(5)
			for i = 2, 6 do
				expect(set["u" .. i].lk).toBe(true)
			end
		end)

		it("instantané (chargement, RequestSnapshot) : table entière", function()
			local ctx = boot()
			seedCollection(ctx, 1, 30)
			local p = join(ctx, 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.RequestSnapshot", p)
			ctx.h:settle(2)
			local snaps = ctx.h:sentTo(p, "DataSnapshot")
			expect(#snaps).toBe(2)
			expect(count(snaps[2][1].nebbies)).toBe(30)
		end)

		it(
			"markDirty de la clé entière et entrées dans la même image : la table entière gagne",
			function()
				local ctx = boot()
				seedCollection(ctx, 1, 10)
				local p, data = join(ctx, 1)
				local base = #ctx.h:sentTo(p, "DataPatch")
				ctx.DS.markDirtyEntry(p, "nebbies", "u1")
				ctx.DS.markDirty(p, "nebbies")
				ctx.h:settle(2)
				local sent = nebbiesPatches(ctx, p, base)
				expect(#sent).toBe(1)
				expect(count(sent[1][1].nebbies)).toBe(count(data.nebbies))
				expect(sent[1][3] == nil or sent[1][3].nebbies == nil).toBe(true)
				-- clé privée : jamais envoyée
				ctx.DS.markDirtyEntry(p, "receipts", "1")
				ctx.h:settle(2)
				for _, args in ctx.h:sentTo(p, "DataPatch") do
					expect(args[1].receipts).toBeNil()
					expect(type(args[3]) ~= "table" or args[3].receipts == nil).toBe(true)
				end
			end
		)

		it("client : entrées appliquées sur une copie, Changed émis une fois", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			h:boot()
			local State = h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")
			local u1 = { s = 1, f = 0, v = 0, st = 1 }
			local u2 = { s = 2, f = 0, v = 0, st = 1 }
			h:fireClient(
				"ReplicatedStorage.Remotes.DataSnapshot",
				{ glow = 1, nebbies = { u1 = u1, u2 = u2 } }
			)
			local before = State.get("nebbies")
			local changes = {}
			State.Changed:Connect(function(key, value, old)
				table.insert(changes, { key = key, value = value, old = old })
			end)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", { glow = 2 }, {}, {
				nebbies = {
					set = { u3 = { s = 3, f = 0, v = 0, st = 1 }, u2 = { s = 2, f = 0, v = 0, st = 2 } },
					del = { "u1" },
				},
			})
			h:settle(2)
			local after = State.get("nebbies")
			expect(after.u1).toBeNil()
			expect(after.u2.st).toBe(2)
			expect(after.u3.s).toBe(3)
			expect(State.get("glow")).toBe(2)
			local nebbyChanges = {}
			for _, c in changes do
				if c.key == "nebbies" then
					table.insert(nebbyChanges, c)
				end
			end
			expect(#nebbyChanges).toBe(1)
			expect(nebbyChanges[1].old).toBe(before)
			expect(nebbyChanges[1].value).toBe(after)
			-- l'ancienne table n'est jamais modifiée
			expect(before.u1).toBe(u1)
			expect(before.u3).toBeNil()
			-- charges invalides : ignorées sans erreur
			h:fireClient(
				"ReplicatedStorage.Remotes.DataPatch",
				{},
				{},
				{ nebbies = "x", other = { set = 5, del = 3 } }
			)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", {}, {}, 42)
			h:settle(2)
			expect(State.get("nebbies")).toBe(after)
			expect(#h.errors).toBe(0)
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › save() honnête après la libération", function()
		it("sauvegarde de BindToClose réussie : saveNow répond false et n'écrit rien", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.DS.set(p, "glow", 5)
			ctx.h:close()
			ctx.h:settle(3)
			local rec = stored(ctx, 1)
			expect(rec.data.glow).toBe(5)
			expect(rec.lock).toBeNil()
			local saves = rec.meta.saves
			data.glow = 9
			expect(ctx.DS.saveNow(p)).toBe(false)
			ctx.h:settle(2)
			expect(stored(ctx, 1).meta.saves).toBe(saves)
			expect(stored(ctx, 1).lock).toBeNil()
		end)

		it("sauvegarde de BindToClose en échec : saveNow répond false", function()
			local ctx = boot()
			local p = join(ctx, 1)
			expect(ctx.DS.saveNow(p)).toBe(true) -- glow = 0 écrit
			ctx.DS.set(p, "glow", 5)
			ctx.h.dataStoreFailures = 1000
			ctx.h:close()
			ctx.h:settle(3)
			ctx.h.dataStoreFailures = 0
			expect(ctx.DS.saveNow(p)).toBe(false)
			expect(stored(ctx, 1).data.glow).toBe(0)
			-- départ ensuite : aucune erreur, état vidé (reconnexion possible)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(ctx.DS.get(p)).toBeNil()
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › verrou de session à jeton", function()
		it("session partie pendant son chargement : le verrou de la reconnexion reste", function()
			local ctx = boot()
			local h = ctx.h
			local Players = h.game.Players
			-- 1re session : arrive puis part pendant son chargement (même image)
			local p1 = h:_newPlayer({ userId = 7, name = "Twin" })
			p1.Parent = Players
			Players.PlayerAdded:Fire(p1)
			Players.PlayerRemoving:Fire(p1)
			p1.Parent = nil
			-- 2e session du même UserId sur le même serveur, chargée en parallèle
			local p2 = h:_newPlayer({ userId = 7, name = "Twin" })
			p2.Parent = Players
			Players.PlayerAdded:Fire(p2)
			expect(waitUntil(function()
				return ctx.DS.get(p2) ~= nil
			end, 2)).toBe(true)
			h:settle(5)
			task.wait(0.05)
			h:settle(3)
			expect(ctx.DS.get(p1)).toBeNil()
			local rec = stored(ctx, 7)
			expect(rec.lock ~= nil).toBe(true)
			expect(rec.lock.jobId).toBe(h.game.JobId)
			-- un autre serveur ne peut donc pas charger le profil pendant cette session
			expect(#h.log.kicks).toBe(0)
			-- la sauvegarde de la session vivante reste acceptée et garde le verrou
			expect(ctx.DS.saveNow(p2)).toBe(true)
			expect(stored(ctx, 7).lock ~= nil).toBe(true)
			-- départ : verrou libéré
			h:removePlayer(p2)
			h:settle(5)
			expect(stored(ctx, 7).lock).toBeNil()
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › Starforge : Copies − 1 copies", function()
		for _, case in { { copies = 4, have = 5 }, { copies = 2, have = 3 }, { copies = 3, have = 4 } } do
			it(`Copies = {case.copies} : {case.copies - 1} copies consommées`, function()
				local ctx = boot()
				ctx.Balance.Starforge.Copies = case.copies
				seedCollection(ctx, 1, case.have, { s = 3, f = 0, v = 0, st = 1 })
				local p, data = join(ctx, 1)
				local ok, reason = ctx.A.fuse(p, "u1")
				expect(reason).toBeNil()
				expect(ok).toBe(true)
				expect(data.nebbies.u1.st).toBe(2)
				expect(count(data.nebbies)).toBe(case.have - (case.copies - 1))
				-- les plus récents sont consommés d'abord
				for i = case.have - case.copies + 2, case.have do
					expect(data.nebbies["u" .. i]).toBeNil()
				end
			end)
		end

		it("Copies = 4 avec seulement 2 copies : refus « copies manquantes »", function()
			local ctx = boot()
			ctx.Balance.Starforge.Copies = 4
			seedCollection(ctx, 1, 3, { s = 3, f = 0, v = 0, st = 1 })
			local p, data = join(ctx, 1)
			local ok, reason = ctx.A.fuse(p, "u1")
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.fuseNeedCopies")
			expect(count(data.nebbies)).toBe(3)
		end)
	end)
end
