--!nocheck
-- Correctifs « restes serveur : données et réplication » de Comet Conga (DataService, StateController) :
--   1. profil écrit par un schéma PLUS RÉCENT : jamais réparé ni réécrit par un serveur plus ancien,
--      le joueur est renvoyé (message bilingue), aucun verrou laissé derrière
--   2. crochets onBeforeSave : drapeau `release` transmis (travail « de départ » écrit par la
--      sauvegarde de départ et par celle de BindToClose)
--   3. réplication d'une grande table par entrées (set / del) dans DataPatch : jamais la table
--      entière quand seules quelques entrées changent
--   4. après la sauvegarde de libération, save() ne prétend plus avoir écrit
--   5. verrou de session marqué par un jeton de chargement : une session partie pendant son
--      chargement n'efface pas le verrou d'une reconnexion sur le même serveur
-- Adaptation : table neutre « items » modifiée par un propriétaire simulé (mutation du profil +
-- DataService.markDirtyEntry) au lieu des Nebbies d'AtlasService. Retirés (gameplay de Comet
-- Conga) : cadeau Starfall à la fermeture, regroupement des verrous à 2 Hz d'AtlasService, Starforge.

local task = require("@lune/task")
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC
	local STORE = "PlayerData_v1"

	local function boot(opts)
		opts = opts or {}
		local h = Harness.new()
		local Schema = Bots.extendSchema(h, { coins = 0, gems = 0, items = {} })
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = { h = h, Clock = Clock, DS = DS, Schema = Schema }
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
		profile.items = {}
		for i = 1, n do
			profile.items["u" .. i] = if rec then table.clone(rec) else { kind = 1 + (i % 6), level = 1 }
		end
		profile.gems = 100000
		store(ctx):SetAsync("player_" .. userId, { data = profile })
	end

	-- Propriétaire simulé de « items » : ajoute, modifie ou supprime des entrées puis les marque
	local function setItem(ctx, p, uid, rec)
		local data = ctx.DS.get(p)
		data.items[uid] = rec
		ctx.DS.markDirtyEntry(p, "items", uid)
	end

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › profil d'un schéma plus récent", function()
		local function newerRecord(ctx, lock)
			local profile = ctx.Schema.defaults()
			profile.version = ctx.Schema.VERSION + 1
			profile.coins = 777
			profile.gems = 55
			-- données « v2 » qu'un serveur v1 jugerait invalides (un nettoyage les supprimerait)
			profile.items = {
				u1 = { kind = 1, level = 1 },
				u2 = { kind = 99, level = 8, aura = "nova" },
			}
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
			expect(after.data.items.u2.aura).toBe("nova")
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
			profile.coins = 12
			store(ctx):SetAsync("player_3", { data = profile })
			local p, data = join(ctx, 3)
			expect(data ~= nil).toBe(true)
			expect(data.coins).toBe(12)
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
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › réplication d'une grande table par entrées", function()
		local function itemPatches(ctx, p, from)
			local out = {}
			local all = ctx.h:sentTo(p, "DataPatch")
			for i = (from or 0) + 1, #all do
				local args = all[i]
				if
					(type(args[1]) == "table" and args[1].items ~= nil)
					or (type(args[3]) == "table" and args[3].items ~= nil)
				then
					table.insert(out, args)
				end
			end
			return out
		end

		it("60 entrées ajoutées à une table de 600 : seules les 60 nouvelles partent", function()
			local ctx = boot()
			ctx.DS.Settings.SNAPSHOT_INLINE = 1000 -- instantané complet : isole le flux d'arrivée
			seedCollection(ctx, 1, 600)
			local p, data = join(ctx, 1)
			local snaps = ctx.h:sentTo(p, "DataSnapshot")
			expect(count(snaps[#snaps][1].items)).toBe(600)
			local base = #ctx.h:sentTo(p, "DataPatch")
			local created = {}
			for i = 601, 660 do
				local uid = "u" .. i
				setItem(ctx, p, uid, { kind = 1 + (i % 6), level = 1 })
				table.insert(created, uid)
			end
			ctx.DS.increment(p, "gems", -60) -- clé liée, même image
			ctx.h:settle(2)
			local sent = itemPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local args = sent[1]
			-- jamais la table entière
			expect(args[1].items).toBeNil()
			local ops = args[3].items
			expect(count(ops.set)).toBe(60)
			for _, uid in created do
				expect(ops.set[uid]).toEqual(data.items[uid])
			end
			expect(#(ops.del or {})).toBe(0)
			-- même message que les clés liées
			expect(args[1].gems).toBe(data.gems)
			expect(count(data.items)).toBe(660)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("entrées supprimées : elles partent dans `del`, jamais dans `set`", function()
			local ctx = boot()
			seedCollection(ctx, 1, 300)
			local p, data = join(ctx, 1)
			local base = #ctx.h:sentTo(p, "DataPatch")
			for i = 1, 40 do
				setItem(ctx, p, "u" .. i, nil)
			end
			setItem(ctx, p, "u301", { kind = 1, level = 1 })
			ctx.h:settle(2)
			local sent = itemPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local ops = sent[1][3].items
			expect(sent[1][1].items).toBeNil()
			expect(#ops.del).toBe(40)
			for _, uid in ops.del do
				expect(data.items[uid]).toBeNil()
				expect(ops.set[uid]).toBeNil()
			end
			for uid, rec in ops.set do
				expect(data.items[uid]).toEqual(rec)
			end
		end)

		it("modification, ajout et suppression : seules les entrées touchées partent", function()
			local ctx = boot()
			seedCollection(ctx, 1, 200, { kind = 2, level = 1 })
			local p, data = join(ctx, 1)
			local base = #ctx.h:sentTo(p, "DataPatch")
			-- modification d'une entrée
			local rec = table.clone(data.items.u5)
			rec.lk = true
			setItem(ctx, p, "u5", rec)
			ctx.h:settle(2)
			local sent = itemPatches(ctx, p, base)
			expect(#sent).toBe(1)
			expect(sent[1][1].items).toBeNil()
			expect(count(sent[1][3].items.set)).toBe(1)
			expect(sent[1][3].items.set.u5.lk).toBe(true)
			-- fusion simulée : une entrée améliorée, deux supprimées, dans la même image
			base = #ctx.h:sentTo(p, "DataPatch")
			local up = table.clone(data.items.u1)
			up.level = 2
			setItem(ctx, p, "u1", up)
			setItem(ctx, p, "u2", nil)
			setItem(ctx, p, "u3", nil)
			ctx.h:settle(2)
			sent = itemPatches(ctx, p, base)
			expect(#sent).toBe(1)
			local ops = sent[1][3].items
			expect(sent[1][1].items).toBeNil()
			expect(count(ops.set)).toBe(1)
			expect(ops.set.u1.level).toBe(2)
			table.sort(ops.del)
			expect(ops.del).toEqual({ "u2", "u3" })
			-- plusieurs marques d'une même entrée dans l'image : une seule entrée envoyée
			base = #ctx.h:sentTo(p, "DataPatch")
			for level = 3, 6 do
				local r = table.clone(data.items.u10)
				r.level = level
				setItem(ctx, p, "u10", r)
			end
			ctx.h:settle(2)
			sent = itemPatches(ctx, p, base)
			expect(#sent).toBe(1)
			expect(count(sent[1][3].items.set)).toBe(1)
			expect(sent[1][3].items.set.u10.level).toBe(6)
		end)

		it("instantané (chargement, RequestSnapshot) : table entière", function()
			local ctx = boot()
			seedCollection(ctx, 1, 30)
			local p = join(ctx, 1)
			ctx.h:fireServer("ReplicatedStorage.Remotes.RequestSnapshot", p)
			ctx.h:settle(2)
			local snaps = ctx.h:sentTo(p, "DataSnapshot")
			expect(#snaps).toBe(2)
			expect(count(snaps[2][1].items)).toBe(30)
		end)

		it(
			"markDirty de la clé entière et entrées dans la même image : la table entière gagne",
			function()
				local ctx = boot()
				seedCollection(ctx, 1, 10)
				local p, data = join(ctx, 1)
				local base = #ctx.h:sentTo(p, "DataPatch")
				ctx.DS.markDirtyEntry(p, "items", "u1")
				ctx.DS.markDirty(p, "items")
				ctx.h:settle(2)
				local sent = itemPatches(ctx, p, base)
				expect(#sent).toBe(1)
				expect(count(sent[1][1].items)).toBe(count(data.items))
				expect(sent[1][3] == nil or sent[1][3].items == nil).toBe(true)
				-- clé privée : jamais envoyée
				ctx.DS.markDirtyEntry(p, "receipts", "1")
				ctx.DS.markDirty(p, "flags")
				ctx.h:settle(2)
				for _, args in ctx.h:sentTo(p, "DataPatch") do
					expect(args[1].receipts).toBeNil()
					expect(args[1].flags).toBeNil()
					expect(type(args[3]) ~= "table" or args[3].receipts == nil).toBe(true)
				end
			end
		)

		it("client : entrées appliquées sur une copie, Changed émis une fois", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			h:boot()
			local State = h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController")
			local u1 = { kind = 1, level = 1 }
			local u2 = { kind = 2, level = 1 }
			h:fireClient(
				"ReplicatedStorage.Remotes.DataSnapshot",
				{ coins = 1, items = { u1 = u1, u2 = u2 } }
			)
			local before = State.get("items")
			local changes = {}
			State.Changed:Connect(function(key, value, old)
				table.insert(changes, { key = key, value = value, old = old })
			end)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", { coins = 2 }, {}, {
				items = {
					set = { u3 = { kind = 3, level = 1 }, u2 = { kind = 2, level = 2 } },
					del = { "u1" },
				},
			})
			h:settle(2)
			local after = State.get("items")
			expect(after.u1).toBeNil()
			expect(after.u2.level).toBe(2)
			expect(after.u3.kind).toBe(3)
			expect(State.get("coins")).toBe(2)
			local itemChanges = {}
			for _, c in changes do
				if c.key == "items" then
					table.insert(itemChanges, c)
				end
			end
			expect(#itemChanges).toBe(1)
			expect(itemChanges[1].old).toBe(before)
			expect(itemChanges[1].value).toBe(after)
			-- l'ancienne table n'est jamais modifiée
			expect(before.u1).toBe(u1)
			expect(before.u3).toBeNil()
			-- charges invalides : ignorées sans erreur
			h:fireClient(
				"ReplicatedStorage.Remotes.DataPatch",
				{},
				{},
				{ items = "x", other = { set = 5, del = 3 } }
			)
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", {}, {}, 42)
			h:settle(2)
			expect(State.get("items")).toBe(after)
			expect(#h.errors).toBe(0)
		end)
	end)

	-- -------------------------------------------------------------------------------------------
	describe("Fix restes data › save() honnête après la libération", function()
		it("sauvegarde de BindToClose réussie : saveNow répond false et n'écrit rien", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			ctx.DS.set(p, "coins", 5)
			ctx.h:close()
			ctx.h:settle(3)
			local rec = stored(ctx, 1)
			expect(rec.data.coins).toBe(5)
			expect(rec.lock).toBeNil()
			local saves = rec.meta.saves
			data.coins = 9
			expect(ctx.DS.saveNow(p)).toBe(false)
			ctx.h:settle(2)
			expect(stored(ctx, 1).meta.saves).toBe(saves)
			expect(stored(ctx, 1).lock).toBeNil()
		end)

		it("sauvegarde de BindToClose en échec : saveNow répond false", function()
			local ctx = boot()
			local p = join(ctx, 1)
			expect(ctx.DS.saveNow(p)).toBe(true) -- coins = 0 écrit
			ctx.DS.set(p, "coins", 5)
			ctx.h.dataStoreFailures = 1000
			ctx.h:close()
			ctx.h:settle(3)
			ctx.h.dataStoreFailures = 0
			expect(ctx.DS.saveNow(p)).toBe(false)
			expect(stored(ctx, 1).data.coins).toBe(0)
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
end
