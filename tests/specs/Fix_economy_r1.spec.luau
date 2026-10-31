--!nocheck
-- Corrections du paquet economy, revue QA n° 1 : chaque test reproduit un défaut corrigé.
--   1. Supernova / Zen par téléportation au Nid : le port sûr se juge sur la position VALIDÉE
--      (MoveCheck), jamais sur la seule position envoyée par le client.
--   2. Zen désactivé à la porte : une file attrapée en Zen s'encaisse avec le plafond Zen.
--   3. Attribution du Nid : vérifications d'amitié en parallèle, attente bornée, cache partagé.
--   4. Réplication de « nebbies » : les changements demandés par l'interface sont regroupés.

local task = require("@lune/task")
local Bots = require("../harness/Bots")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	-- Serveur complet sans tick (tests unitaires des services) ------------------------------------

	local function boot(before)
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		if before then
			before(h)
		end
		h:boot()
		return {
			h = h,
			Clock = Clock,
			DS = DS,
			N = h:require("ServerScriptService.Server.Services.NestService"),
			E = h:require("ServerScriptService.Server.Services.EconomyService"),
			A = h:require("ServerScriptService.Server.Services.AtlasService"),
			WS = h:require("ServerScriptService.Server.Services.WorldService"),
			MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			V3 = h.globals.Vector3,
		}
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function feedbackKeys(h, p)
		local out = {}
		for _, args in h:sentTo(p, "Feedback") do
			table.insert(out, args[1].key)
		end
		return out
	end

	local function lastFeedback(h, p)
		local fb = h:sentTo(p, "Feedback")
		return fb[#fb] and fb[#fb][1]
	end

	local function has(list, value)
		return table.find(list, value) ~= nil
	end

	-- Monde complet avec ticks (Bots) -------------------------------------------------------------

	-- hors de toute fenêtre d'événement (Comète, Balise) : rien ne vient perturber la scène
	local TW = 1800000000 + 37 + 3600 * 5

	local function world(glow, tweak)
		local w = Bots.boot(Harness, {
			t0 = TW,
			before = function(w)
				local d = Bots.veteranProfile(w, TW, glow)
				if tweak then
					tweak(d)
				end
				Bots.saveProfile(w, 1, d)
			end,
		})
		Bots.use(w)
		local p = w.h:addPlayer({ userId = 1, name = "Hunter" })
		table.insert(w.players, p)
		w.h:settle(10)
		Bots.frames(5)
		return w, p
	end

	-- donne `n` Communs personnels sous les pieds du joueur et les laisse s'accrocher à la file
	local function catchCommons(w, p, n)
		local root = Bots.rootOf(p)
		for i = 1, n do
			local offset = w.V3.new((i % 5) * 0.2, -3, (i // 5) * 0.2)
			w.Spawn.spawnPersonal(p, w.Neb.pack(1, 0, 0), root.Position + offset, 120)
		end
		Bots.frames(5)
	end

	local function harborGround(p)
		local h = Bots.harborPoint(p)
		return Bots.ground(h.X, h.Z)
	end

	describe("Fix economy r1 › port sûr jugé sur la position validée", function()
		it(
			"téléportation au Nid + Supernova : la file n'est PAS encaissée, puis retour honnête",
			function()
				local w, p = world(100)
				local slot = w.Nest.slotOf(p)
				-- marche honnête vers r = 120 (hors du port sûr), file de 5 Communs
				expect(Bots.walkAll({ [p] = Bots.zonePoint(p, 120, 0.3) }, 400)).toBe(true)
				catchCommons(w, p, 5)
				local n = w.Conga.lineLength(p)
				expect(n >= 5).toBe(true)
				expect(w.Nest.inOwnHarbor(p)).toBe(false)
				local data = w.DS.get(p)
				local glow = data.glow
				local banks = #Bots.lineOps("bank", slot)
				-- le client place sa racine dans son port sûr et tire le remote dans la même image
				w.h:moveTo(p, harborGround(p))
				expect(w.Nest.inOwnHarbor(p)).toBe(false)
				expect(w.Economy.supernovaPreview(p).inHarbor).toBe(false)
				Bots.fire("Supernova", p)
				expect(w.Conga.lineLength(p)).toBe(n)
				expect(data.glow).toBe(glow)
				expect(data.supernovas).toBe(0)
				expect(Bots.feedbackKeys(p)[#Bots.feedbackKeys(p)]).toBe("feedback.notInHarbor")
				Bots.frames(1) -- diffusion du tick : aucune op « bank »
				expect(#Bots.lineOps("bank", slot)).toBe(banks)
				expect(w.Conga.lineLength(p) >= n).toBe(true)
				-- le Zen non plus
				Bots.fire("SetSetting", p, "zen", true)
				expect(w.Nest.isZen(p)).toBe(false)
				expect(Bots.feedbackKeys(p)[#Bots.feedbackKeys(p)]).toBe("feedback.notInHarbor")
				-- MoveCheck ramène le joueur ; la restriction passe ; il rentre en marchant
				Bots.frames(45)
				expect(w.WL.inOwnHarbor(slot, Bots.rootOf(p).Position)).toBe(false)
				expect(Bots.walkAll({ [p] = Bots.harborPoint(p) }, 400)).toBe(true)
				expect(w.Nest.inOwnHarbor(p)).toBe(true)
				expect(w.Conga.lineLength(p) >= n).toBe(true)
				task.wait(2.05) -- débit réel du remote : 1 / 2 s
				Bots.fire("Supernova", p)
				-- au port sûr, la file est encaissée (parade forcée) puis la Supernova refusée (coût)
				expect(w.Conga.lineLength(p)).toBe(0)
				expect(data.glow > glow).toBe(true)
				Bots.frames(1)
				expect(#Bots.lineOps("bank", slot)).toBe(banks + 1)
				expect(data.supernovas).toBe(0)
				expect(has(Bots.feedbackKeys(p), "feedback.notEnoughGlow")).toBe(true)
				expect(#Bots.problems()).toBe(0)
			end
		)

		it("au port sûr honnête : Zen activable, téléportation aller-retour refusée", function()
			local w, p = world(2000)
			-- apparition sur son Nid (placement serveur) : port sûr reconnu dès l'arrivée
			expect(w.Nest.inOwnHarbor(p)).toBe(true)
			expect(Bots.walkAll({ [p] = Bots.harborPoint(p) }, 200)).toBe(true)
			Bots.fire("SetSetting", p, "zen", true)
			expect(w.Nest.isZen(p)).toBe(true)
			-- loin du Nid, téléportation au Nid le temps du remote (après la recharge du Zen)
			expect(Bots.walkAll({ [p] = Bots.zonePoint(p, 95, 0.4) }, 400)).toBe(true)
			Bots.travelTo(Bots.now() + 61)
			local back = Bots.rootOf(p).Position
			w.h:moveTo(p, harborGround(p))
			Bots.fire("SetSetting", p, "zen", false)
			w.h:moveTo(p, back)
			expect(w.Nest.isZen(p)).toBe(true)
			expect(Bots.feedbackKeys(p)[#Bots.feedbackKeys(p)]).toBe("feedback.notInHarbor")
		end)

		it("restriction MoveCheck, personnage mort, réapparition", function()
			local ctx = boot()
			local p = join(ctx, 1)
			local home = p.Character.HumanoidRootPart.Position
			expect(ctx.N.inOwnHarbor(p)).toBe(true) -- placement serveur
			-- MoveCheck prend le relais : sa référence fait foi
			ctx.MoveCheck.reset(p, home, ctx.Clock.now())
			expect(ctx.N.inOwnHarbor(p)).toBe(true)
			-- trois téléportations signalées après l'exemption → retour forcé puis restriction
			ctx.Clock.advance(4)
			local far = ctx.V3.new(0, 5, 0)
			local verdict
			for _ = 1, 3 do
				verdict = ctx.MoveCheck.step(p, far, 0.1, ctx.Clock.now(), 2)
				ctx.Clock.advance(0.1)
			end
			expect(verdict).toBe("rewind")
			expect(ctx.MoveCheck.isRestricted(p, ctx.Clock.now())).toBe(true)
			expect(ctx.N.inOwnHarbor(p)).toBe(false) -- au Nid, mais sous restriction
			ctx.Clock.advance(4)
			expect(ctx.N.inOwnHarbor(p)).toBe(true)
			-- référence validée loin du Nid : la racine posée au Nid ne suffit pas
			ctx.MoveCheck.reset(p, far, ctx.Clock.now())
			expect(ctx.N.inOwnHarbor(p)).toBe(false)
			-- mort : jamais au port sûr ; réapparition : replacé au Nid, reconnu tout de suite
			p.Character.Humanoid.Health = 0
			expect(ctx.N.inOwnHarbor(p)).toBe(false)
			ctx.h:respawn(p)
			expect(ctx.N.inOwnHarbor(p)).toBe(true)
			-- position explicite : inchangée (fournie par un service)
			expect(ctx.N.inOwnHarbor(p, ctx.WorldLayout.nestCenter(1))).toBe(true)
			expect(ctx.N.inOwnHarbor(p, far)).toBe(false)
			expect(ctx.N.inOwnHarbor(p, 0 / 0)).toBe(false)
			-- départ : rien n'est gardé
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			expect(ctx.N.debugTracked(p)).toBe(false)
		end)
	end)

	describe("Fix economy r1 › Zen et file en cours", function()
		it("quitter le Zen exige une file vide ; l'activer avec une file reste permis", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			-- file en cours (signal du tick de CongaService) : activer le Zen reste permis
			ctx.Signals.LineChanged:Fire(p, 3)
			expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
			ctx.Clock.advance(61)
			local ok, reason = ctx.N.applySetting(p, "zen", false)
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.zenBankFirst")
			expect(lastFeedback(ctx.h, p).key).toBe("feedback.zenBankFirst")
			expect(data.settings.zen).toBe(true)
			expect(p:GetAttribute("Zen")).toBe(true)
			-- par le remote aussi
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", p, "zen", false)
			expect(ctx.N.isZen(p)).toBe(true)
			-- un refus ne consomme pas la recharge : file encaissée → Zen désactivé tout de suite
			ctx.Signals.LineChanged:Fire(p, 0)
			expect(ctx.N.applySetting(p, "zen", false)).toBe(true)
			expect(ctx.N.isZen(p)).toBe(false)
			expect(lastFeedback(ctx.h, p).key).toBe("feedback.zenOff")
			-- valeurs étranges du signal : ignorées sans erreur
			ctx.Signals.LineChanged:Fire(p, 0 / 0)
			ctx.Signals.LineChanged:Fire(p, -4)
			ctx.Signals.LineChanged:Fire(p, "x")
			ctx.h:settle(1)
			expect(ctx.N.debugTracked(p)).toBe(true) -- Nid, etc. (joueur présent)
			-- départ : la longueur de file n'est jamais recréée par un signal tardif
			ctx.h:removePlayer(p)
			ctx.h:settle(2)
			ctx.Signals.LineChanged:Fire(p, 5)
			ctx.h:settle(1)
			expect(ctx.N.debugTracked(p)).toBe(false)
			expect(#ctx.h.errors).toBe(0)
		end)

		it("chasse en Zen, Zen coupé à la porte refusé : la parade garde le plafond Zen", function()
			local w, p = world(100, function(d)
				d.upgrades.conga = 30
			end)
			expect(Bots.walkAll({ [p] = Bots.harborPoint(p) }, 200)).toBe(true)
			Bots.fire("SetSetting", p, "zen", true)
			expect(w.Nest.isZen(p)).toBe(true)
			expect(Bots.walkAll({ [p] = Bots.zonePoint(p, 90, 0.2) }, 600)).toBe(true)
			catchCommons(w, p, 30)
			local n = w.Conga.lineLength(p)
			expect(n >= 20).toBe(true)
			Bots.travelTo(Bots.now() + 61) -- recharge du Zen écoulée
			-- au port sûr, juste avant la porte
			expect(Bots.walkAll({ [p] = Bots.zonePoint(p, 121, 0) }, 600)).toBe(true)
			expect(w.Nest.inOwnHarbor(p)).toBe(true)
			expect(w.Conga.lineLength(p) >= n).toBe(true)
			Bots.fire("SetSetting", p, "zen", false)
			expect(w.Nest.isZen(p)).toBe(true)
			expect(Bots.feedbackKeys(p)[#Bots.feedbackKeys(p)]).toBe("feedback.zenBankFirst")
			local parades = {}
			w.Signals.Parade:Connect(function(pl, info)
				if pl == p then
					table.insert(parades, info)
				end
			end)
			local M = w.Economy.multiplier(p)
			expect(Bots.walkAll({ [p] = Bots.gateOf(p) }, 100)).toBe(true)
			expect(w.Conga.lineLength(p)).toBe(0)
			expect(#parades).toBe(1)
			local info = parades[1]
			expect(info.count >= n).toBe(true)
			local capped = w.F.paradeGlow(info.codes, M, true, false)
			local uncapped = w.F.paradeGlow(info.codes, M, false, false)
			expect(uncapped > capped).toBe(true)
			expect(info.glow).toBe(capped)
			-- file encaissée : le Zen se quitte normalement
			Bots.frames(1)
			Bots.fire("SetSetting", p, "zen", false)
			expect(w.Nest.isZen(p)).toBe(false)
			expect(Bots.feedbackKeys(p)[#Bots.feedbackKeys(p)]).toBe("feedback.zenOff")
			expect(#Bots.problems()).toBe(0)
		end)
	end)

	describe("Fix economy r1 › attribution du Nid sans attente des appels d'amitié", function()
		it("appels d'amitié en parallèle : l'ami est respecté sans attendre leur somme", function()
			local ctx = boot()
			for id = 1, 4 do
				join(ctx, id)
			end
			ctx.h:makeFriends(50, 3)
			local real = MockInstance.areFriends
			local calls = 0
			MockInstance.areFriends = function(a, b)
				calls += 1
				task.wait(0.3) -- appel web lent
				return real(a, b)
			end
			local started = os.clock()
			local p = ctx.h:addPlayer({ userId = 50, name = "Friend" })
			while ctx.N.slotOf(p) == 0 and os.clock() - started < 3 do
				task.wait()
			end
			local elapsed = os.clock() - started
			MockInstance.areFriends = real
			ctx.h:settle(3)
			expect(calls >= 4).toBe(true) -- 4 propriétaires (CrewService vérifie aussi de son côté)
			-- séquentiel : 4 × 0,3 s ; en parallèle : une seule attente
			expect(elapsed < 0.9).toBe(true)
			-- Nid libre le plus proche de l'ami (Nid 3) : 2 et 4 sont pris → 5
			expect(ctx.N.slotOf(p)).toBe(5)
			expect(p.RespawnLocation).toBe(ctx.WS.spawnLocation(5))
			expect(ctx.N.inOwnHarbor(p)).toBe(true)
			-- réponses partagées (CrewService n'a pas à refaire l'appel web)
			local players = ctx.h.game.Players
			local owner3 = players:GetPlayerByUserId(3)
			local owner1 = players:GetPlayerByUserId(1)
			expect(ctx.N.friendsCached(p, owner3)).toBe(true)
			expect(ctx.N.friendsCached(owner3, p)).toBe(true)
			expect(ctx.N.friendsCached(owner1, p)).toBe(false)
		end)

		it(
			"API d'amitié bloquée : plus petit Nid libre à l'échéance ; échecs non mémorisés",
			function()
				local ctx = boot()
				for id = 1, 5 do
					join(ctx, id)
				end
				ctx.N.Settings.FriendLookupDeadline = 0.15
				ctx.h:makeFriends(60, 1)
				local real = MockInstance.areFriends
				MockInstance.areFriends = function(a, b)
					task.wait(0.6) -- bien au-delà de l'échéance
					return real(a, b)
				end
				local started = os.clock()
				local p = ctx.h:addPlayer({ userId = 60, name = "Late" })
				while ctx.N.slotOf(p) == 0 and os.clock() - started < 5 do
					task.wait()
				end
				local elapsed = os.clock() - started
				-- avant : 5 appels de 0,6 s l'un après l'autre (3 s) ; maintenant : l'échéance
				expect(elapsed < 0.5).toBe(true)
				expect(ctx.N.slotOf(p)).toBe(6)
				expect(p:GetAttribute("Slot")).toBe(6)
				expect(ctx.N.inOwnHarbor(p)).toBe(true)
				-- les réponses tardives arrivent quand même dans le cache (pas de déplacement)
				task.wait(0.7)
				ctx.h:settle(2)
				MockInstance.areFriends = real
				local owner1 = ctx.h.game.Players:GetPlayerByUserId(1)
				expect(ctx.N.friendsCached(p, owner1)).toBe(true)
				expect(ctx.N.slotOf(p)).toBe(6)
				-- un appel en échec n'est pas mémorisé comme « pas amis »
				ctx.N.Settings.FriendLookupDeadline = 1
				MockInstance.areFriends = function()
					error("Friends API down")
				end
				local q = ctx.h:addPlayer({ userId = 61, name = "Down" })
				ctx.h:settle(3)
				MockInstance.areFriends = real
				expect(ctx.N.slotOf(q)).toBe(7)
				expect(ctx.N.friendsCached(q, owner1)).toBeNil()
				expect(#ctx.h:warnings() >= 1).toBe(true)
				-- départ pendant l'attente : aucun Nid pris, rien de gardé
				MockInstance.areFriends = function(a, b)
					task.wait(0.3)
					return real(a, b)
				end
				local r = ctx.h:addPlayer({ userId = 62, name = "Gone" })
				ctx.h:removePlayer(r)
				task.wait(0.5)
				ctx.h:settle(3)
				MockInstance.areFriends = real
				expect(ctx.N.slotOf(r)).toBe(0)
				expect(ctx.WS.nest(8):GetAttribute("OwnerUserId")).toBe(0)
				expect(ctx.N.debugTracked(r)).toBe(false)
				expect(#ctx.h.errors).toBe(0)
			end
		)
	end)

	describe("Fix economy r1 › réplication de la collection", function()
		local function nebbiesPatches(h, p)
			local n = 0
			for _, args in h:sentTo(p, "DataPatch") do
				if type(args[1]) == "table" and args[1].nebbies ~= nil then
					n += 1
				end
			end
			return n
		end

		local function seedCollection(ctx, userId, count)
			local profile = ctx.Schema.defaults()
			profile.nebbies = {}
			for i = 1, count do
				profile.nebbies["u" .. i] = { s = 1 + (i % 6), f = 0, v = 0, st = 1 }
			end
			profile.nextUid = count + 1
			local store = ctx.h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_" .. userId, { data = profile })
		end

		it("verrous en rafale : un envoi immédiat, un seul envoi groupé ensuite", function()
			local ctx = boot()
			seedCollection(ctx, 1, 300)
			local p, data = join(ctx, 1)
			local base = nebbiesPatches(ctx.h, p)
			for i = 1, 6 do
				ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u" .. i, true)
			end
			ctx.h:settle(2)
			-- avant : 6 tables entières (≈ 11 Ko chacune) ; maintenant : la première tout de suite
			expect(nebbiesPatches(ctx.h, p) - base).toBe(1)
			for i = 1, 6 do
				expect(data.nebbies["u" .. i].lk).toBe(true)
			end
			-- fin de fenêtre : les 5 autres changements partent ensemble
			task.wait(ctx.A.Settings.NebbiesPatchInterval + 0.15)
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(2)
			-- fenêtre suivante sans changement : plus rien
			task.wait(ctx.A.Settings.NebbiesPatchInterval + 0.15)
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(2)
			expect(ctx.A.debugTracked(p)).toBe(true) -- caches de perchoirs (joueur présent)
			-- un verrou isolé, plus tard, part tout de suite
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u7", true)
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(3)
		end)

		it("une parade pendant la fenêtre part tout de suite ; départ pendant la fenêtre", function()
			local ctx = boot()
			seedCollection(ctx, 1, 20)
			local p = join(ctx, 1)
			local base = nebbiesPatches(ctx.h, p)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u1", true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u2", true)
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(1)
			-- changement du jeu (parade) : immédiat, et il emporte le verrou en attente
			ctx.A.addNebbies(p, { ctx.Nebbies.pack(1, 0, 0) }, "parade")
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(2)
			task.wait(ctx.A.Settings.NebbiesPatchInterval + 0.15)
			ctx.h:settle(2)
			expect(nebbiesPatches(ctx.h, p) - base).toBe(2)
			-- départ avec un changement en attente : aucun état gardé, aucune erreur
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u3", true)
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetLock", p, "u4", true)
			ctx.h:removePlayer(p)
			ctx.h:settle(3)
			task.wait(ctx.A.Settings.NebbiesPatchInterval + 0.15)
			ctx.h:settle(3)
			expect(ctx.A.debugTracked(p)).toBe(false)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)
end
