--!nocheck
-- Correctifs r3, serveur 4 (NestService, QuestService, MoveCheck) : chaque test reproduit un défaut.
--   1. MoveCheck : 1 s d'immobilité, Dash, puis un bond de 42 studs en UN tick était accepté et
--      agissait (coupe, vol de Comète) ; la position reste acceptée (gels réseau tolérés), mais le
--      tick est signalé « rafale » (règle du GDD §12.7 pour un tick : vmax × dt × 1,5 + 4).
--   2. Zen : « attraper en Zen, se réinitialiser, couper le Zen, tout reprendre » contournait le
--      plafond Zen du Conga Bonus ; quitter le Zen est refusé tant que la file lâchée gît au sol.
--   3. Quêtes : reprendre SES propres Nebbies lâchés (coupe, mort) ne compte plus comme de
--      nouvelles captures (statistiques, quêtes du jour).
--   4. Q4 « Déblocage de l'Atlas » : Celebrate « atlasUnlocked » { count, total } après la quête.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- ---------------------------------------------------------------------------------------------
	-- 1. MoveCheck : rafale
	-- ---------------------------------------------------------------------------------------------

	local DT = 0.1
	local T0 = 1000

	local function moveCheck()
		local h = Harness.new()
		local MoveCheck = h:require("ServerScriptService.Server.Util.MoveCheck")
		return MoveCheck, h.globals.Vector3
	end

	-- Joueur simulé (clé seulement) : apparu, exemption terminée à T0, un premier pas normal à T0
	local function newPlayer(MC, V3, pos, speed)
		local player = { Name = "Blinker" }
		MC.noteSpeed(player, speed or 16, T0 - 10)
		MC.reset(player, pos, T0 - MC.Config.Exemption)
		local p = { player = player, pos = pos + V3.new(0, 0, 0.5), now = T0 }
		assert(MC.step(player, p.pos, DT, T0, 0) == "ok")
		return p
	end

	local function move(MC, p, delta)
		p.now += DT
		p.pos = p.pos + delta
		return MC.step(p.player, p.pos, DT, p.now, 0)
	end

	describe("Fix r3 serveur 4 › MoveCheck : bond après immobilité", function()
		it(
			"immobile 1,2 s, Dash, bond de 42 studs en un tick : accepté, 0 infraction, mais rafale",
			function()
				local MC, V3 = moveCheck()
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 16)
				for _ = 1, 12 do
					local verdict, _, burst = move(MC, p, V3.new(0, 0, 0))
					expect(verdict).toBe("ok")
					expect(burst).toBe(false)
				end
				MC.noteSpeed(p.player, 26, p.now) -- Dash
				local verdict, back, burst = move(MC, p, V3.new(42, 0, 0))
				-- tolérance inchangée : la position est acceptée, aucune infraction, aucun retour
				expect(verdict).toBe("ok")
				expect(back).toBe(nil)
				expect(MC.violations(p.player)).toBe(0)
				expect((MC.lastValid(p.player) - p.pos).Magnitude < 1e-6).toBe(true)
				-- … mais ce tick ne doit agir sur rien
				expect(burst).toBe(true)
				expect(MC.lastWasBurst(p.player)).toBe(true)
				-- tick suivant : plus de rafale
				local v2, _, b2 = move(MC, p, V3.new(0, 0, 0))
				expect(v2).toBe("ok")
				expect(b2).toBe(false)
				expect(MC.lastWasBurst(p.player)).toBe(false)
			end
		)

		it(
			"la règle d'un tick : 7,9 studs à 26 passent, 8,5 sont une rafale ; à 16, 6,4 passent",
			function()
				local MC, V3 = moveCheck()
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 26)
				for _ = 1, 12 do
					move(MC, p, V3.new(0, 0, 0))
				end
				local _, _, ok79 = move(MC, p, V3.new(7.8, 0, 0))
				expect(ok79).toBe(false)
				for _ = 1, 12 do
					move(MC, p, V3.new(0, 0, 0))
				end
				local verdict, _, b85 = move(MC, p, V3.new(8.5, 0, 0))
				expect(verdict).toBe("ok")
				expect(b85).toBe(true)
				local q = newPlayer(MC, V3, V3.new(-100, 3, 0), 16)
				for _ = 1, 12 do
					move(MC, q, V3.new(0, 0, 0))
				end
				local _, _, b64 = move(MC, q, V3.new(6.3, 0, 0))
				expect(b64).toBe(false)
				expect(MC.violations(p.player) + MC.violations(q.player)).toBe(0)
			end
		)

		it("marche honnête (16, 26, Dash, paquets groupés par deux) : jamais de rafale", function()
			local MC, V3 = moveCheck()
			for _, speed in { 16, 26 } do
				local radius = 120
				local p = newPlayer(MC, V3, V3.new(radius, 3, -0.5), speed)
				local angle = 0
				for i = 1, 300 do
					-- un tick sur deux sans nouvelle position, puis deux pas d'un coup (gigue réseau)
					local ticks = if i % 2 == 0 then 2 else 0
					if i % 50 == 0 then
						MC.noteSpeed(p.player, speed + 10, p.now) -- Dash
					end
					angle += ticks * DT * speed / radius
					local target = V3.new(radius * math.cos(angle), 3, radius * math.sin(angle))
					local verdict, _, burst = move(MC, p, target - p.pos)
					expect(verdict).toBe("ok")
					expect(burst).toBe(false)
				end
				expect(MC.violations(p.player)).toBe(0)
			end
		end)

		it(
			"rattrapage du serveur (3 pas au même instant après un accroc de 0,3 s) : pas de rafale",
			function()
				local MC, V3 = moveCheck()
				local p = newPlayer(MC, V3, V3.new(100, 3, 0), 26)
				for _ = 1, 5 do
					move(MC, p, V3.new(2.6, 0, 0))
				end
				-- image de 0,3 s : le joueur a parcouru 7,8 studs ; le serveur joue 3 pas au même instant
				p.now += 0.3
				p.pos = p.pos + V3.new(7.8, 0, 0)
				for _ = 1, 3 do
					local verdict, _, burst = MC.step(p.player, p.pos, DT, p.now, 0)
					expect(verdict).toBe("ok")
					expect(burst).toBe(false)
				end
				-- un trou plus long sans appel (personnage absent, sans réinitialisation) n'est jamais un
				-- crédit de bond : borné à MaxCatchUp pas (20 studs : dans la fenêtre soutenue)
				p.now += 1.2
				p.pos = p.pos + V3.new(20, 0, 0)
				local verdict, _, burst = MC.step(p.player, p.pos, DT, p.now, 0)
				expect(verdict).toBe("ok")
				expect(burst).toBe(true)
				expect(MC.violations(p.player)).toBe(0)
			end
		)

		it("signalé, réinitialisé ou inconnu : jamais « rafale » ; clear oublie tout", function()
			local MC, V3 = moveCheck()
			local p = newPlayer(MC, V3, V3.new(100, 3, 0), 16)
			for _ = 1, 12 do
				move(MC, p, V3.new(0, 0, 0))
			end
			MC.noteSpeed(p.player, 26, p.now)
			local _, _, burst = move(MC, p, V3.new(42, 0, 0))
			expect(burst).toBe(true)
			-- téléportation (dans l'île) : signalée, pas une rafale
			local verdict, _, b2 = move(MC, p, V3.new(0, 0, 50))
			expect(verdict).toBe("flag")
			expect(b2).toBe(false)
			expect(MC.lastWasBurst(p.player)).toBe(false)
			-- position invalide
			local v3, _, b3 = MC.step(p.player, V3.new(0 / 0, 3, 0), DT, p.now + DT, 0)
			expect(v3).toBe("flag")
			expect(b3).toBe(false)
			-- nouvelle référence (apparition)
			move(MC, p, V3.new(0, 0, -50))
			MC.reset(p.player, p.pos, p.now)
			expect(MC.lastWasBurst(p.player)).toBe(false)
			expect(MC.lastWasBurst({ Name = "Nobody" })).toBe(false)
			MC.clear(p.player)
			expect(MC.lastWasBurst(p.player)).toBe(false)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Serveur complet sans tick (services réels)
	-- ---------------------------------------------------------------------------------------------

	local TB = 1800000000

	local function boot(before)
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(TB)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			N = h:require("ServerScriptService.Server.Services.NestService"),
			Q = h:require("ServerScriptService.Server.Services.QuestService"),
			Atlas = h:require("ServerScriptService.Server.Services.AtlasService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			Signals = h:require("ServerScriptService.Server.Signals"),
			Schema = h:require("ServerScriptService.Server.Data.Schema"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			B = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		if before then
			before(ctx)
		end
		h:boot()
		ctx.Spawn.spawnWelcome = function()
			return {}
		end
		ctx.Spawn.setDirected = function() end
		ctx.Spawn.spawnGuaranteedRare = function()
			return 1
		end
		return ctx
	end

	local function seed(ctx, userId, fields)
		local profile = ctx.Schema.defaults()
		for k, v in fields do
			profile[k] = v
		end
		local store = ctx.h.game.DataStoreService:GetDataStore(ctx.Schema.STORE_NAME)
		store:SetAsync("player_" .. userId, { data = profile })
	end

	local function join(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		local data = ctx.DS.get(p) or ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p, data
	end

	local function lastFeedback(h, p)
		local fb = h:sentTo(p, "Feedback")
		return fb[#fb] and fb[#fb][1]
	end

	local function paradeInfo(count)
		return {
			count = count,
			codes = {},
			uids = {},
			glow = 0,
			bonus = 1,
			atBeacon = false,
			idleSeconds = 0,
			newEntries = 0,
			forced = false,
		}
	end

	-- ---------------------------------------------------------------------------------------------
	-- 2. Zen : file lâchée sans parade
	-- ---------------------------------------------------------------------------------------------

	describe("Fix r3 serveur 4 › Zen : file Zen lâchée puis reprise", function()
		it("file attrapée en Zen, vidée sans parade : quitter le Zen refusé pendant 20,55 s", function()
			local ctx = boot()
			local p, data = join(ctx, 1)
			expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
			ctx.Clock.advance(61) -- recharge du Zen écoulée
			ctx.Signals.LineChanged:Fire(p, 3)
			ctx.Signals.LineChanged:Fire(p, 25)
			-- réinitialisation du personnage : la file tombe en Nebbies libres (priorité au joueur)
			ctx.Signals.LineChanged:Fire(p, 0)
			local ok, reason = ctx.N.applySetting(p, "zen", false)
			expect(ok).toBe(false)
			expect(reason).toBe("feedback.zenLooseWait")
			local fb = lastFeedback(ctx.h, p)
			expect(fb.key).toBe("feedback.zenLooseWait")
			expect(fb.vars.seconds).toBe(math.ceil(ctx.B.Snip.LooseLifetime + ctx.B.Snip.ScatterTime))
			expect(data.settings.zen).toBe(true)
			expect(p:GetAttribute("Zen")).toBe(true)
			-- par le remote aussi
			ctx.h:fireServer("ReplicatedStorage.Remotes.SetSetting", p, "zen", false)
			expect(ctx.N.isZen(p)).toBe(true)
			ctx.Clock.advance(20)
			expect(ctx.N.applySetting(p, "zen", false)).toBe(false)
			expect(lastFeedback(ctx.h, p).vars.seconds).toBe(1)
			-- les Nebbies libres ont disparu : le Zen se quitte (le refus n'a pas consommé la recharge)
			ctx.Clock.advance(0.6)
			expect(ctx.N.applySetting(p, "zen", false)).toBe(true)
			expect(ctx.N.isZen(p)).toBe(false)
			expect(lastFeedback(ctx.h, p).key).toBe("feedback.zenOff")
			expect(#ctx.h.errors).toBe(0)
		end)

		it("file Zen encaissée (Parade puis file vide) : le Zen se quitte tout de suite", function()
			local ctx = boot()
			local p = join(ctx, 1)
			expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
			ctx.Clock.advance(61)
			ctx.Signals.LineChanged:Fire(p, 12)
			ctx.Signals.Parade:Fire(p, paradeInfo(12))
			ctx.Signals.LineChanged:Fire(p, 0)
			expect(ctx.N.applySetting(p, "zen", false)).toBe(true)
			expect(ctx.N.isZen(p)).toBe(false)
		end)

		it(
			"file attrapée AVANT le Zen puis lâchée : rien à reprendre sous plafond, Zen quitté",
			function()
				local ctx = boot()
				local p = join(ctx, 1)
				ctx.Signals.LineChanged:Fire(p, 8)
				expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
				ctx.Clock.advance(61)
				ctx.Signals.LineChanged:Fire(p, 0)
				expect(ctx.N.applySetting(p, "zen", false)).toBe(true)
			end
		)

		it("reprise partielle puis parade : le reste gît encore au sol, refus jusqu'à la fin", function()
			local ctx = boot()
			local p = join(ctx, 1)
			expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
			ctx.Clock.advance(61)
			ctx.Signals.LineChanged:Fire(p, 10)
			ctx.Signals.LineChanged:Fire(p, 0) -- lâchée
			ctx.Clock.advance(5)
			ctx.Signals.LineChanged:Fire(p, 6) -- 6 repris
			expect(select(2, ctx.N.applySetting(p, "zen", false))).toBe("feedback.zenBankFirst")
			ctx.Signals.Parade:Fire(p, paradeInfo(6))
			ctx.Signals.LineChanged:Fire(p, 0)
			expect(select(2, ctx.N.applySetting(p, "zen", false))).toBe("feedback.zenLooseWait")
			ctx.Clock.advance(16)
			expect(ctx.N.applySetting(p, "zen", false)).toBe(true)
		end)

		it("départ : aucun état gardé, un signal tardif ne recrée rien", function()
			local ctx = boot()
			local p = join(ctx, 1)
			expect(ctx.N.applySetting(p, "zen", true)).toBe(true)
			ctx.Signals.LineChanged:Fire(p, 4)
			ctx.Signals.Parade:Fire(p, paradeInfo(4))
			ctx.Signals.LineChanged:Fire(p, 9)
			ctx.Signals.LineChanged:Fire(p, 0)
			ctx.h:removePlayer(p)
			ctx.h:settle(2)
			ctx.Signals.Parade:Fire(p, paradeInfo(3))
			ctx.Signals.LineChanged:Fire(p, 5)
			ctx.Signals.LineChanged:Fire(p, 0)
			ctx.h:settle(1)
			expect(ctx.N.debugTracked(p)).toBe(false)
			expect(#ctx.h.errors).toBe(0)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- 3. Quêtes : Nebbies repris
	-- ---------------------------------------------------------------------------------------------

	local function setList(ctx, data, ids)
		local list = {}
		for _, id in ids do
			table.insert(list, { id = id, p = 0, done = false, claimed = false })
		end
		data.quests.list = list
		data.quests.rerolls = 0
		data.quests.starClaimed = false
		data.quests.day = ctx.Clock.day()
	end

	local function catchInfo(ctx, s, extra)
		local info = {
			code = ctx.Nebbies.pack(s, 0, 0),
			rarity = ctx.Nebbies.rarityOf(s),
			zone = "meadow",
			loose = false,
			recovered = false,
			personal = false,
			n = 1,
		}
		for k, v in extra or {} do
			info[k] = v
		end
		return info
	end

	describe("Fix r3 serveur 4 › quêtes : reprendre ses Nebbies n'est pas une capture", function()
		it(
			"Épiques et Légendaires repris : ni statistique, ni quête ; ceux d'un autre comptent",
			function()
				local ctx = boot()
				local p, data = join(ctx, 1)
				setList(ctx, data, { 1, 19, 20 }) -- 40 captures, 3 Épiques+, 1 Légendaire+
				local catches = data.stats.catches or 0
				local epic = ctx.Nebbies.speciesOfRarity(4)[1]
				local legendary = ctx.Nebbies.speciesOfRarity(5)[1]
				for _ = 1, 5 do
					ctx.Signals.Caught:Fire(p, catchInfo(ctx, epic, { loose = true, recovered = true }))
					ctx.Signals.Caught:Fire(p, catchInfo(ctx, legendary, { loose = true, recovered = true }))
				end
				ctx.h:settle(1)
				expect(data.quests.list[1].p).toBe(0)
				expect(data.quests.list[2].p).toBe(0)
				expect(data.quests.list[3].p).toBe(0)
				expect(data.quests.list[3].done).toBe(false)
				expect(data.stats.catches or 0).toBe(catches)
				-- Nebby libre d'un AUTRE joueur (sans priorité pour soi) : une vraie capture
				ctx.Signals.Caught:Fire(p, catchInfo(ctx, epic, { loose = true, recovered = false }))
				expect(data.quests.list[1].p).toBe(1)
				expect(data.quests.list[2].p).toBe(1)
				expect(data.stats.catches).toBe(catches + 1)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- 4. Q4 : déblocage de l'Atlas
	-- ---------------------------------------------------------------------------------------------

	describe("Fix r3 serveur 4 › Q4 : le moment du déblocage de l'Atlas", function()
		it("Q4 terminée : Celebrate atlasUnlocked { count, total } après questClaimed", function()
			local ctx = boot()
			seed(ctx, 2, {
				onboarding = { step = 4, p = 0 },
				rookie = { sessions = 1, playSeconds = 200, done = false },
			})
			local p, data = join(ctx, 2)
			expect(data.onboarding.step).toBe(4)
			local rare = ctx.Nebbies.speciesOfRarity(3)[1]
			local codes = {
				ctx.Nebbies.pack(rare, 0, 0),
				ctx.Nebbies.pack(1, 0, 0),
				ctx.Nebbies.pack(2, 0, 0),
			}
			-- CongaService : les Nebbies entrent dans l'Atlas AVANT Signals.Parade
			ctx.Atlas.addNebbies(p, codes, "parade")
			local info = paradeInfo(#codes)
			info.codes = codes
			ctx.Signals.Parade:Fire(p, info)
			ctx.h:settle(1)
			expect(data.onboarding.step).toBe(5)
			local kinds, unlocked = {}, {}
			for _, args in ctx.h:sentTo(p, "Celebrate") do
				table.insert(kinds, args[1].kind)
				if args[1].kind == "atlasUnlocked" then
					table.insert(unlocked, args[1].data)
				end
			end
			expect(#unlocked).toBe(1)
			expect(unlocked[1].count).toBe(ctx.Atlas.atlasCount(p))
			expect(unlocked[1].count >= 1).toBe(true)
			expect(unlocked[1].total).toBe(ctx.Nebbies.atlasTotal())
			-- après « Quête terminée ! » et la récompense
			local claimedAt, unlockedAt
			for i, kind in kinds do
				if kind == "questClaimed" then
					claimedAt = i
				elseif kind == "atlasUnlocked" then
					unlockedAt = i
				end
			end
			expect(claimedAt ~= nil and unlockedAt > claimedAt).toBe(true)
		end)

		it("les autres quêtes d'accueil n'annoncent aucun déblocage", function()
			local ctx = boot()
			local p, data = join(ctx, 3)
			expect(data.onboarding.step).toBe(1)
			ctx.Signals.Parade:Fire(p, paradeInfo(4)) -- Q1
			ctx.h:settle(1)
			expect(data.onboarding.step).toBe(2)
			for _, args in ctx.h:sentTo(p, "Celebrate") do
				expect(args[1].kind ~= "atlasUnlocked").toBe(true)
			end
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Monde complet (Bots) : réinitialisation du personnage puis reprise de la file
	-- ---------------------------------------------------------------------------------------------

	-- hors de toute fenêtre d'événement (Comète, Balise)
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
		local p = w.h:addPlayer({ userId = 1, name = "Resetter" })
		table.insert(w.players, p)
		w.h:settle(10)
		Bots.frames(5)
		return w, p
	end

	local function catchCommons(w, p, n)
		local root = Bots.rootOf(p)
		for i = 1, n do
			local offset = w.V3.new((i % 5) * 0.2, -3, (i // 5) * 0.2)
			w.Spawn.spawnPersonal(p, w.Neb.pack(1, 0, 0), root.Position + offset, 120)
		end
		Bots.frames(5)
	end

	-- réinitialisation du personnage (mort : la file tombe en Nebbies libres, priorité au joueur) puis
	-- réapparition au Nid, sans tick depuis ; rend la position de la mort
	local function resetCharacter(w, p)
		local at = Bots.rootOf(p).Position
		p.Character:FindFirstChildOfClass("Humanoid").Health = 0
		Bots.frames(2)
		expect(w.Conga.lineLength(p)).toBe(0)
		w.h:respawn(p)
		w.h:settle(3)
		return at
	end

	local function lastKey(p)
		local keys = Bots.feedbackKeys(p)
		return keys[#keys]
	end

	-- Nebby libre le plus proche prioritaire pour le joueur (SA file lâchée)
	local function ownLoose(w, p)
		local root = Bots.rootOf(p)
		if not root then
			return nil
		end
		local t = Bots.now()
		local slot = w.Nest.slotOf(p)
		local best, bestD = nil, math.huge
		for _, wild in w.Spawn.query(root.Position, 150, t, p) do
			if wild.loose and wild.prioritySlot == slot then
				local pos = w.Spawn.positionOf(wild, t)
				local d = (pos - root.Position).Magnitude
				if d < bestD then
					best, bestD = pos, d
				end
			end
		end
		return best
	end

	-- retourne là où la file est tombée (en suivant le chemin de l'aller) et ramasse ses Nebbies
	local function recoverOwn(w, p, deathAt)
		expect(Bots.walkAll({ [p] = Bots.harborPoint(p) }, 200)).toBe(true)
		expect(Bots.walkAll({ [p] = deathAt }, 400)).toBe(true)
		for _ = 1, 60 do
			local target = ownLoose(w, p)
			if target == nil then
				break
			end
			Bots.walkAll({ [p] = target }, 100)
			Bots.frames(2)
		end
	end

	describe("Fix r3 serveur 4 › bout en bout (Bots)", function()
		it("Zen : file lâchée par réinitialisation, Zen gardé, reprise et parade au plafond", function()
			local w, p = world(100, function(d)
				d.upgrades.conga = 30
			end)
			expect(Bots.walkAll({ [p] = Bots.harborPoint(p) }, 200)).toBe(true)
			Bots.fire("SetSetting", p, "zen", true)
			expect(w.Nest.isZen(p)).toBe(true)
			-- loin du Nid (90 studs) : aucun Nebby de la file ne retombe à portée de la réapparition
			expect(Bots.walkAll({ [p] = Bots.zonePoint(p, 60, 0.05) }, 800)).toBe(true)
			catchCommons(w, p, 25)
			local n = w.Conga.lineLength(p)
			expect(n >= 21).toBe(true) -- au-delà du plafond Zen (×2,5)
			Bots.travelTo(Bots.now() + 61) -- recharge du Zen écoulée
			local deathAt = resetCharacter(w, p)
			-- réapparu au Nid : couper le Zen est refusé tant que la file gît au sol
			expect(w.Nest.inOwnHarbor(p)).toBe(true)
			Bots.fire("SetSetting", p, "zen", false)
			expect(w.Nest.isZen(p)).toBe(true)
			expect(lastKey(p)).toBe("feedback.zenLooseWait")
			local parades = {}
			w.Signals.Parade:Connect(function(pl, info)
				if pl == p then
					table.insert(parades, info)
				end
			end)
			-- reprise de la file (priorité du propriétaire), toujours en Zen, puis parade
			recoverOwn(w, p, deathAt)
			expect(w.Nest.isZen(p)).toBe(true)
			expect(Bots.walkAll({ [p] = Bots.gateOf(p) }, 400)).toBe(true)
			Bots.frames(2)
			expect(#parades >= 1).toBe(true)
			local total = 0
			for _, info in parades do
				total += info.count
				expect(info.bonus).toBe(w.F.congaBonus(info.count, true))
			end
			expect(total >= n).toBe(true)
			local last = parades[#parades]
			expect(last.count >= 21).toBe(true)
			expect(last.bonus < w.F.congaBonus(last.count, false)).toBe(true)
			expect(#Bots.problems()).toBe(0)
		end)

		it("quêtes : se réinitialiser puis reprendre sa file ne compte aucune capture", function()
			local w, p = world(100)
			local data = w.DS.get(p)
			setList({ Clock = w.Clock }, data, { 1, 19, 20 }) -- 40 captures, 3 Épiques+, 1 Légendaire+
			local spot = Bots.zonePoint(p, 60, 0.05)
			expect(Bots.walkAll({ [p] = spot }, 800)).toBe(true)
			catchCommons(w, p, 6)
			local n = w.Conga.lineLength(p)
			expect(n >= 6).toBe(true)
			local catches = data.stats.catches
			local progress = data.quests.list[1].p
			expect(progress >= n).toBe(true)
			-- captures et parades après la réinitialisation : seules les nouvelles captures comptent
			local fresh, recovered, paraded = 0, 0, 0
			w.Signals.Caught:Connect(function(pl, info)
				if pl == p then
					if info.recovered then
						recovered += 1
					else
						fresh += 1
					end
				end
			end)
			w.Signals.Parade:Connect(function(pl, info)
				if pl == p then
					paraded += info.count
				end
			end)
			local deathAt = resetCharacter(w, p)
			recoverOwn(w, p, deathAt)
			expect(recovered >= n).toBe(true)
			expect(w.Conga.lineLength(p) + paraded).toBe(recovered + fresh)
			expect(data.stats.catches).toBe(catches + fresh)
			expect(data.quests.list[1].p).toBe(progress + fresh)
			expect(#Bots.problems()).toBe(0)
		end)
	end)
end
