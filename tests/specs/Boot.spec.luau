--!nocheck
-- Boot (intégration serveur, docs/04 §18.3) : serveur complet (Main.server, tous les services réels,
-- paquet meta compris), 16 joueurs (Bots + Brains), dont des amis, pilotés par les remotes pendant des
-- centaines de ticks : presser et attraper, acheter une dalle en marchant, nourrir Plop, fusionner,
-- vendre et relâcher, monter, choisir Rush / Cozy, booper, poursuivre, garder le ranch d'un ami,
-- applaudir, objectifs. Voyages dans le temps (Clock) vers chaque événement du GDD : BOOP RUSH, Golden,
-- MEGA SQUISH, file du Grand Splorch, Jelly Moon, minuit UTC (objectifs du jour), lundi 00:00 UTC
-- (classements de la semaine). Réapparitions, départs et retours (profil persisté), joueur présent
-- avant le démarrage, départ pendant le chargement, fermeture (BindToClose) à 16 joueurs avec un
-- DataStore lent.
-- À CHAQUE TICK : Invariants.profile de chaque profil, uids du portage / de l'attente, aucun état
-- ouvert au-delà de son délai (openStates des 8 services). À la fin : zéro erreur, zéro avertissement
-- (ZeroLog + DiagnosticsService.counts()), aucun « Infinite yield », aucun stub « TODO(… ) » avalé,
-- chaque envoi conforme aux règles de sérialisation des remotes (Wire), chaque Feedback et chaque
-- bannière ont leur texte EN et FR sans variable manquante, API Roblox auditée (ApiAudit).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Wire = require("../harness/Wire")
local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")
local task = require("@lune/task")
local Flags = require("../harness/Flags")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC (début d'heure)
	local DAY = 86400
	local S = Brains.S
	local R = "ReplicatedStorage.Remotes."
	local STORE = "PlayerData_v1/global"

	local SERVICES = {
		"RanchService",
		"SquishyService",
		"QuestService",
		"CommunityService",
		"EventService",
		"RushService",
		"SplorchService",
		"ChaseService",
	}

	-- ------------------------------------------------------------------------------------------
	-- Monde et contrôles
	-- ------------------------------------------------------------------------------------------

	local function world(opts)
		opts = opts or {}
		local w = Brains.boot(
			opts.harness or Harness,
			{ t0 = opts.t0 or (H0 + 60), stubMeta = false, before = opts.before }
		)
		w.Q = w.h:require(S .. "QuestService")
		w.C = w.h:require(S .. "CommunityService")
		w.L = w.h:require(S .. "LeaderboardService")
		w.D = w.h:require(S .. "DiagnosticsService")
		w.Invariants = w.h:require("ReplicatedStorage.Shared.Logic.Invariants")
		w.Strings = w.h:require("ReplicatedStorage.Shared.Localization.Strings")
		w.MetaGuard = w.h:require("ServerScriptService.Server.Meta.Guard")
		w.problems = {}
		w.checks = 0
		return w
	end

	local function problem(w, line)
		if #w.problems < 40 then
			table.insert(w.problems, string.format("t=%.1f %s", w.Clock.now() - H0, line))
		end
	end

	-- Contrôles d'un tick (docs/04 §17.2 n° 1 à 7)
	local function checkTick(w)
		w.checks += 1
		local now = w.Clock.now()
		for _, p in w.players do
			if p.Parent ~= nil and w.DS.isLoaded(p) then
				local data = w.DS.get(p)
				for _, v in w.Invariants.profile(data) do
					problem(w, "profil " .. p.UserId .. " : " .. v)
				end
				local carried = w.Squishy.carried(p)
				if carried and data.squishies[carried] == nil then
					problem(w, "portage d'un uid absent " .. tostring(carried))
				end
				local waiting = w.Squishy.waiting(p)
				if waiting and data.squishies[waiting] == nil then
					problem(w, "attente d'un uid absent " .. tostring(waiting))
				end
			end
		end
		for _, name in SERVICES do
			for _, st in w.h:require(S .. name).openStates() do
				local ok, expired = pcall(w.StateTimeouts.expired, st.name, st.startedAt, now)
				if not ok then
					problem(w, name .. ":" .. tostring(st.name) .. " (état inconnu)")
				elseif expired then
					problem(w, string.format("%s:%s ouvert depuis %.1f s", name, st.name, now - st.startedAt))
				end
			end
		end
		local escapes = 0
		for _, spawn in w.Chase.active() do
			if spawn.kind == "escape" then
				escapes += 1
			end
		end
		if escapes > w.Events.Rush.ServerMax then
			problem(w, "plus de " .. w.Events.Rush.ServerMax .. " fuites du Rush")
		end
	end

	-- n ticks complets (cerveaux compris), contrôles à chaque tick
	local function play(w, n)
		Bots.use(w)
		for _ = 1, n do
			Bots.frame(Bots.brains)
			checkTick(w)
		end
	end

	-- saut dans le temps puis un tick contrôlé (personne ne bouge pendant le saut)
	local function travel(w, t)
		Bots.use(w)
		Bots.travelTo(t)
		play(w, 1)
	end

	-- Profil de vétéran varié (mode, R, collection, pièces), comme le robot de longue durée
	local function veteran(w, i, extra)
		local squishies = { { s = 1, z = 80 + i, bf = 1 } }
		for k = 1, 3 + (i % 5) do
			table.insert(squishies, { s = 2 + ((i + k) % 18), m = (i * k) % 3, z = 20 + 7 * k + i })
		end
		for _, spec in extra or {} do
			table.insert(squishies, spec)
		end
		return Brains.profile(w, {
			rush = i % 3 ~= 0,
			coins = 20000 + 1000 * i,
			R = i % 4,
			squishies = squishies,
			edit = function(d)
				-- record de taille d'un vétéran : selle débloquée (Formulas.saddleLevel)
				d.biggestEver = math.max(tonumber(d.biggestEver) or 0, 2000)
			end,
		})
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	local function stored(w, userId)
		local store = w.h.dataStores[STORE]
		local rec = store and MockInstance.state(store).data["player_" .. userId]
		return rec
	end

	-- Texte EN et FR d'une clé, variables comprises (aucune « {nom} » restante)
	local function textProblems(w, key, vars, where)
		local out = {}
		for _, lang in { "en", "fr" } do
			local text = w.Strings[lang][key]
			if type(text) ~= "string" then
				table.insert(out, `{where} : clé {key} absente ({lang})`)
			else
				local filled = string.gsub(text, "{(%w+)}", function(name)
					if type(vars) == "table" and vars[name] ~= nil then
						return tostring(vars[name])
					end
					return "{" .. name .. "}"
				end)
				local missing = string.match(filled, "{(%w+)}")
				if missing then
					table.insert(out, `{where} : {key} sans la variable {missing} ({lang})`)
				end
			end
		end
		return out
	end

	-- Chaque Feedback et chaque bannière envoyés pendant la partie
	local function allTexts(w, rec)
		local out = {}
		for _, sent in rec.sent.Feedback or {} do
			local payload = sent.args[1]
			for _, line in textProblems(w, payload.key, payload.vars, "Feedback") do
				table.insert(out, line)
			end
		end
		local BigNumber = w.h:require("ReplicatedStorage.Shared.Logic.BigNumber")
		for _, sent in rec.sent.Banner or {} do
			local payload = sent.args[1]
			local vars = table.clone(payload.args or {})
			-- « Premier à 1 MILLIARD » : le client écrit le mot entier du jalon (UI/Banners.serverText)
			local n = if type(vars.threshold) == "number" then vars.threshold else vars.n
			if vars.word == nil and type(n) == "number" then
				local wordKey = BigNumber.milestoneKey(n)
				if wordKey then
					for _, line in textProblems(w, wordKey, {}, "Banner (mot du jalon)") do
						table.insert(out, line)
					end
					vars.word = w.Strings.en[wordKey]
				end
			end
			for _, line in textProblems(w, "banner." .. tostring(payload.kind), vars, "Banner") do
				table.insert(out, line)
			end
		end
		local seen, unique = {}, {}
		for _, line in out do
			if not seen[line] then
				seen[line] = true
				table.insert(unique, line)
			end
		end
		return unique
	end

	-- Zéro trace et aucun stub avalé
	local function zeroTrace(w)
		local lines = {}
		for _, line in Brains.problems(w) do
			table.insert(lines, line)
		end
		for _, line in w.D.caught() do
			table.insert(lines, "[caught] " .. tostring(line))
		end
		for where, err in w.Guard.stubbed do
			table.insert(lines, "stub chase " .. where .. " : " .. err)
		end
		for where, err in w.MetaGuard.stubbed do
			table.insert(lines, "stub meta " .. where .. " : " .. err)
		end
		for _, line in w.h:warnings() do
			if string.find(line, "Infinite yield", 1, true) then
				table.insert(lines, line)
			end
		end
		return lines
	end

	-- Marche honnête d'un joueur (son cerveau coupé) jusqu'à la cible ; vrai si arrivé
	-- Le joueur reprend la main : il descend de sa monture (les robots ne relèvent pas leur racine en
	-- selle : un cavalier simulé aurait les pieds sous le sol pour les portées « pieds »)
	local function takeOver(w, p)
		Bots.setBrain(p, nil)
		-- Ride est limité à 2 / s : un ordre perdu derrière un ordre du cerveau est renvoyé
		for _ = 1, 10 do
			if not w.Squishy.riding(p) then
				break
			end
			Bots.fire("Ride", p, false)
			play(w, 6)
		end
	end

	local function walk(w, p, target, maxTicks)
		local brain = w.brains[p]
		takeOver(w, p)
		local arrived = false
		for _ = 1, maxTicks or 200 do
			if Bots.stepToward(p, target) then
				arrived = true
				break
			end
			play(w, 1)
		end
		play(w, 1)
		Bots.setBrain(p, brain)
		return arrived
	end

	local function uidsAt(w, p, at)
		return Brains.uidsAt(w, p, at)
	end

	-- ------------------------------------------------------------------------------------------
	describe("Boot › serveur complet, 16 joueurs", function()
		it(
			"une partie complète par les remotes, tous les événements du GDD par voyage dans le temps",
			function()
				local rec
				local w = world({
					before = function(w0)
						ApiAudit.start()
						-- amis Roblox (pet-sitting, bonus d'amis)
						w0.h:makeFriends(1, 2)
						w0.h:makeFriends(3, 4)
						w0.h:makeFriends(1, 5)
					end,
				})
				rec = Wire.record(w.h, { Clock = w.Clock, remotes = { "Feedback", "Banner", "Celebrate" } })
				local seed = 7
				local players = {}
				-- 14 vétérans (variés, deux prêts pour le Grand Splorch, jumeaux pour la fusion)
				for i = 1, 14 do
					local extra = {}
					if i == 6 or i == 7 then
						-- prêt pour le Grand Splorch : au-delà de l'objectif de son R (i % 4)
						table.insert(extra, { s = 3, z = math.ceil(w.Formulas.splorchTarget(i % 4) * 1.05) })
					end
					if i == 8 then
						table.insert(extra, { s = 4, z = 30 })
						table.insert(extra, { s = 4, z = 31 })
					end
					local p = Brains.join(w, i, { profile = veteran(w, i, extra) })
					players[i] = p
				end
				-- 2 nouveaux (profil vierge : accueil)
				for i = 15, 16 do
					players[i] = Brains.join(w, i, { profile = Bots.profile(w, {}) })
				end
				expect(#w.players).toBe(16)
				for i, p in players do
					expect({ i = i, ready = w.Ranch.isReady(p), slot = w.Ranch.slotOf(p) ~= 0 }).toEqual({
						i = i,
						ready = true,
						slot = true,
					})
				end
				-- cerveaux : joueurs complets, un cavalier, un tricheur borné ; gigue réseau honnête
				for i = 1, 12 do
					-- 6 et 7 (héros du Grand Splorch scripté plus bas) restent chez eux jusque-là
					Bots.setBrain(players[i], if i == 6 or i == 7 then nil else Brains.player(w, seed + i))
					if i % 4 == 0 then
						Bots.jitter(players[i], 2 + (i % 2))
					end
				end
				Bots.setBrain(players[13], Brains.rider(w, seed + 13))
				Bots.setBrain(players[14], Brains.rider(w, seed + 14))
				-- le second nouveau est un tricheur borné (faux bonds, captures lointaines, MEGA en rafale)
				Bots.setBrain(players[16], Brains.spammer(w, seed + 16))

				-- ---------------------------------------------------------------- accueil (nouveau)
				local newbie = players[15]
				play(w, 2)
				local plop = w.DS.get(newbie).squishies["1"]
				expect(plop ~= nil and plop.s).toBe(1)
				-- il marche jusqu'à Plop (portée mesurée depuis sa place, docs/04 §11.5) puis presse □
				local spot = w.WL.penSlot(w.Ranch.slotOf(newbie), 1)
				walk(w, newbie, Bots.ground(spot.X, spot.Z - 3))
				Bots.fire("Press", newbie, "1", w.Clock.now())
				play(w, 1)
				expect({ stage = w.Q.stage(newbie), feedback = Bots.feedbackKeys(newbie) }).toEqual({
					stage = 2,
					feedback = {},
				})

				-- ---------------------------------------------------------------- dalle en marchant
				local buyer = players[9]
				takeOver(w, buyer)
				local slot9 = w.Ranch.slotOf(buyer)
				local before = w.DS.get(buyer).tiles.snack or 0
				local pad = w.WL.padSocket(slot9, 1)
				-- devant la dalle, puis dessus
				walk(w, buyer, Bots.ground(pad.X, pad.Z + 8))
				walk(w, buyer, Bots.ground(pad.X, pad.Z))
				play(w, math.ceil(w.Balance.Tiles.DwellSeconds * 10) + 15)
				expect((w.DS.get(buyer).tiles.snack or 0) > before).toBe(true)
				expect(#Bots.celebrations(buyer, "tile") >= 1).toBe(true)
				walk(w, buyer, Brains.atRanch(w, buyer, 0, 30))

				-- ---------------------------------------------------------------- nourrir Plop
				local feeder = players[10]
				takeOver(w, feeder)
				local bowl = w.WL.anchor(w.Ranch.slotOf(feeder), "bowl")
				walk(w, feeder, Bots.ground(bowl.X + 2, bowl.Z))
				local days = w.DS.get(feeder).plopDays or 0
				Bots.fire("FeedPlop", feeder, true)
				play(w, 30)
				expect((w.DS.get(feeder).plopDays or 0)).toBe(days + 1)
				Bots.fire("FeedPlop", feeder, false)

				-- ---------------------------------------------------------------- fusion, vente, relâche
				local fuser = players[8]
				local nBefore = count(w.DS.get(fuser).squishies)
				Bots.fire("FuseAll", fuser)
				play(w, 30)
				expect(count(w.DS.get(fuser).squishies) < nBefore).toBe(true)
				expect(#Bots.celebrations(fuser, "fusion") >= 1).toBe(true)
				local seller = players[11]
				takeOver(w, seller)
				local pens = uidsAt(w, seller, "pen")
				local sold = pens[#pens]
				local coins0 = w.Economy.coins(seller)
				Bots.fire("Sell", seller, { sold }, true)
				play(w, 2)
				expect(w.DS.get(seller).squishies[sold]).toBeNil()
				expect(w.Economy.coins(seller) > coins0).toBe(true)
				pens = uidsAt(w, seller, "pen")
				local released = pens[#pens]
				Bots.fire("Release", seller, { released }, true)
				play(w, 2)
				expect(w.DS.get(seller).squishies[released]).toBeNil()
				Bots.setBrain(seller, Brains.player(w, seed + 11))

				-- ---------------------------------------------------------------- monture
				local rider = players[12]
				takeOver(w, rider)
				walk(w, rider, Brains.atRanch(w, rider, 0, 40))
				Bots.fire("Ride", rider, true)
				play(w, 5)
				expect(w.Squishy.riding(rider)).toBe(true)
				Bots.fire("Ride", rider, false)
				play(w, 2)
				expect(w.Squishy.riding(rider)).toBe(false)
				Bots.setBrain(rider, Brains.player(w, seed + 12))

				-- ---------------------------------------------------------------- pet-sitting (amis 3 et 4)
				local owner, visitor = players[3], players[4]
				takeOver(w, owner)
				takeOver(w, visitor)
				Bots.place(owner, Brains.atRanch(w, owner, 0, 30))
				Bots.place(visitor, Brains.atRanch(w, owner, -19.5, -1))
				play(w, 10)
				local fenceUids, reason = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
				expect(reason).toBe("petsit")
				-- une pression par squishy prêt de la clôture (les autres peuvent être en recharge de 8 s)
				local sitRewards = 0
				w.Signals.PetSitRewarded:Connect(function(v)
					if v == visitor then
						sitRewards += 1
					end
				end)
				play(w, 90)
				fenceUids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
				for _, uid in fenceUids do
					Bots.fire("PetPress", visitor, owner.UserId, uid, w.Clock.now())
					play(w, 3)
				end
				expect({ rewards = sitRewards > 0, feedback = Bots.feedbackKeys(visitor) }).toEqual({
					rewards = true,
					feedback = Bots.feedbackKeys(visitor),
				})
				Bots.setBrain(owner, Brains.player(w, seed + 3))
				Bots.setBrain(visitor, Brains.player(w, seed + 4))

				-- ---------------------------------------------------------------- BOOP RUSH (H0 + 300)
				local booped = 0
				w.Signals.Booped:Connect(function()
					booped += 1
				end)
				local caught = 0
				w.Signals.Caught:Connect(function()
					caught += 1
				end)
				local rushStart = w.EventClock.rush(w.Clock.now()).startsAt
				travel(w, rushStart - 12)
				-- propriétaire 13 (Rush) au fond de son ranch, boopeur 14 (Rush) devant sa clôture : leurs
				-- cerveaux (cavaliers) ne changent jamais de mode
				local bOwner, booper = players[13], players[14]
				takeOver(w, bOwner)
				takeOver(w, booper)
				Bots.place(bOwner, Brains.atRanch(w, bOwner, 0, 45))
				local lp = w.WL.fencePointsLocal()[1]
				local q = w.WL.toWorld(w.Ranch.slotOf(bOwner), w.V3.new(lp.X, 0, -2))
				Bots.place(booper, Bots.ground(q.X, q.Z))
				play(w, 140)
				expect(w.Event.rushActive()).toBe(true)
				local rushUids, rushReason = w.Ranch.fenceOf(w.Ranch.slotOf(bOwner))
				expect(rushReason).toBe("rush")
				expect(#rushUids > 0).toBe(true)
				Bots.fire("BoopHold", booper, bOwner.UserId, rushUids[1], true)
				play(w, 30)
				expect(booped >= 1).toBe(true)
				expect(#Bots.celebrations(bOwner, "booped") >= 1).toBe(true)
				-- le propriétaire refuse ce boopeur, puis passe en Cozy (choix immédiat)
				Bots.fire("RefuseBooper", bOwner, booper.UserId)
				Bots.fire("SetMode", bOwner, false)
				play(w, 2)
				expect(w.Rush.isRush(bOwner)).toBe(false)
				Bots.setBrain(bOwner, Brains.rider(w, seed + 13))
				Bots.setBrain(booper, Brains.rider(w, seed + 14))
				-- fin du Rush, puis retour au calme
				play(w, 900)
				expect(w.Event.rushActive()).toBe(false)

				-- ---------------------------------------------------------------- Golden et MEGA
				local mega = w.EventClock.mega(w.Clock.now())
				travel(w, mega.warnAt - 50)
				local presser = players[5]
				takeOver(w, presser)
				local megaPad = w.WL.plaza("megaPad")
				-- les robots n'ont pas de recherche de chemin (murs du ranch) : placé par le serveur sur la
				-- place, puis quelques pas honnêtes jusqu'à la zone du géant
				Bots.place(presser, Bots.ground(megaPad.X + 12, megaPad.Z))
				expect(walk(w, presser, Bots.ground(megaPad.X + 3, megaPad.Z), 100)).toBe(true)
				expect(w.ZoneRules.inMegaZone(w.MC.lastValid(presser))).toBe(true)
				local landsAt = mega.landsAt
				expect(w.Clock.now() < landsAt).toBe(true)
				play(w, math.max(1, math.ceil((landsAt - w.Clock.now()) * 10) + 2))
				for _ = 1, 20 do
					Bots.fire("MegaPress", presser, w.Clock.now())
					play(w, 5)
				end
				expect(w.Event.state().mega.points > 0).toBe(true)
				play(w, 700)
				Bots.setBrain(presser, Brains.player(w, seed + 5))

				-- ---------------------------------------------------------------- file du Grand Splorch
				local heroA, heroB = players[6], players[7]
				takeOver(w, heroA)
				takeOver(w, heroB)
				walk(w, heroA, Brains.atRanch(w, heroA, 0, 30))
				walk(w, heroB, Brains.atRanch(w, heroB, 0, 30))
				local rA, rB = w.DS.get(heroA).R, w.DS.get(heroB).R
				local function readyUid(p)
					local target = w.Formulas.splorchTarget(w.DS.get(p).R)
					for uid, r in w.Squishy.records(p) do
						if r.at == "pen" and w.Squishy.sizeOf(p, uid) >= target then
							return uid
						end
					end
					return nil
				end
				local flyerA, flyerB = readyUid(heroA), readyUid(heroB)
				expect(flyerA ~= nil and flyerB ~= nil).toBe(true)
				Bots.fire("GrandSplorch", heroA, false, flyerA)
				Bots.fire("GrandSplorch", heroB, false, flyerB)
				play(w, 1)
				-- deux héros : le second attend son tour dans la file (un seul spectacle à la fois)
				expect(w.Splorch.isWaiting(heroA, flyerA)).toBe(true)
				expect(w.Splorch.isWaiting(heroB, flyerB)).toBe(true)
				expect(w.Event.queuedStartAt(heroB.UserId) ~= nil).toBe(true)
				-- applaudissements des spectateurs pendant la fenêtre
				local clapped = false
				for _ = 1, 1200 do
					play(w, 1)
					for _, p in w.players do
						if p ~= heroA and #w.h:sentTo(p, "ClapPrompt") > 0 and not clapped then
							Bots.fire("Clap", p, w.h:sentTo(p, "ClapPrompt")[1][1].heroId)
							clapped = true
						end
					end
					if w.DS.get(heroA).R == rA + 1 and w.DS.get(heroB).R == rB + 1 then
						break
					end
				end
				expect(w.DS.get(heroA).R).toBe(rA + 1)
				expect(w.DS.get(heroB).R).toBe(rB + 1)
				expect(clapped).toBe(true)
				Bots.setBrain(heroA, Brains.player(w, seed + 6))
				Bots.setBrain(heroB, Brains.player(w, seed + 7))
				play(w, 100)

				-- ---------------------------------------------------------------- objectifs
				local claimer = players[12]
				local o = w.DS.get(claimer).objectives
				expect(#o.list).toBe(3)
				-- réclamer un objectif non fini : rien (aucune erreur)
				Bots.fire("ClaimObjective", claimer, 1)
				play(w, 1)

				-- ---------------------------------------------------------------- réapparitions, départs, retours
				Bots.respawn(players[13])
				Bots.respawn(players[1])
				play(w, 30)
				local leavers = { players[9], players[10] }
				local kept = {}
				for _, p in leavers do
					local d = w.DS.get(p)
					kept[p.UserId] =
						{ R = d.R, n = count(d.squishies), snack = d.tiles.snack, days = d.plopDays }
					Bots.leave(p)
				end
				w.h:settle(3)
				play(w, 20)
				for userId, k in kept do
					local saved = stored(w, userId)
					expect(saved ~= nil).toBe(true)
					expect(saved.lock).toBeNil()
					expect(saved.data.R).toBe(k.R)
					expect(count(saved.data.squishies)).toBe(k.n)
					local back = Brains.join(w, userId)
					local d = w.DS.get(back)
					expect({ R = d.R, n = count(d.squishies), snack = d.tiles.snack, days = d.plopDays }).toEqual(
						k
					)
					Bots.setBrain(back, Brains.player(w, seed + userId))
				end
				play(w, 50)

				-- ---------------------------------------------------------------- Golden (heure suivante)
				local golden = w.EventClock.golden(w.Clock.now())
				if golden.spawnAt > w.Clock.now() + 1 then
					travel(w, golden.spawnAt - 1)
				end
				local sawGolden = false
				for _ = 1, 60 do
					play(w, 1)
					sawGolden = sawGolden or #Brains.creatures(w, "golden") > 0
				end
				expect(sawGolden).toBe(true)

				-- ---------------------------------------------------------------- minuit UTC : objectifs du jour
				local day0 = w.Clock.day()
				local midnight = (math.floor(w.Clock.now() / DAY) + 1) * DAY
				travel(w, midnight - 5)
				play(w, 100)
				expect(w.Clock.day()).toBe(day0 + 1)
				-- minuit en session (GDD §7.4) : objectifs en cours gardés jusqu'à la fin de la session ;
				-- nouveaux objectifs à la connexion suivante
				local nightOwl = players[12]
				expect(w.DS.get(nightOwl).objectives.day).toBe(day0)
				local owlId = nightOwl.UserId
				Bots.leave(nightOwl)
				w.h:settle(3)
				play(w, 5)
				local owl = Brains.join(w, owlId)
				players[12] = owl
				play(w, 5)
				expect(w.DS.get(owl).objectives.day).toBe(day0 + 1)
				expect(#w.DS.get(owl).objectives.list).toBe(3)
				Bots.setBrain(owl, Brains.player(w, seed + 12))

				-- ---------------------------------------------------------------- Jelly Moon (samedi 16:00 UTC)
				local moon = w.EventClock.moon(w.Clock.now())
				travel(w, moon.startsAt - 5)
				play(w, 100)
				expect(w.Event.moonActive()).toBe(true)
				expect(w.Event.state().moon.active).toBe(true)
				travel(w, moon.endsAt - 5)
				play(w, 100)
				expect(w.Event.moonActive()).toBe(false)

				-- ---------------------------------------------------------------- lundi 00:00 UTC : semaine
				local week0 = w.Clock.week()
				local monday = H0 + 2 * DAY + 16 * 3600 -- lundi 18/01/2027 00:00 UTC
				expect(monday > w.Clock.now()).toBe(true)
				travel(w, monday - 5)
				play(w, 100)
				expect(w.Clock.week()).toBe(week0 + 1)
				for _, p in w.players do
					if w.DS.isLoaded(p) then
						expect({ id = p.UserId, week = w.DS.get(p).weekly.week }).toEqual({
							id = p.UserId,
							week = week0 + 1,
						})
					end
				end
				play(w, 200)

				-- ---------------------------------------------------------------- bilan
				expect(caught >= 1).toBe(true)
				expect(w.checks > 3000).toBe(true)
				rec:stop()
				local apiIssues = ApiAudit.stop()
				expect(table.concat(w.problems, "\n")).toBe("")
				expect(table.concat(rec.problems, "\n")).toBe("")
				expect(table.concat(allTexts(w, rec), "\n")).toBe("")
				expect(table.concat(apiIssues, "\n")).toBe("")
				expect(#w.h.log.kicks).toBe(0)
				local counts = w.D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(table.concat(zeroTrace(w), "\n")).toBe("")
			end
		)

		-- Lot I, étape 2 (plan I T2, D13 ; journal I-18) : la progression v2.0 ouverte (interrupteurs de
		-- l'étape 2, même dans le test : le cas ne dépend pas de l'ordre d'ouverture), 16 joueurs, des
		-- Ascensions par voyage dans le temps : Grand Splorch → Jelly Ascend → Petit Splorch. À chaque
		-- tick (en plus de checkTick) : Record R de chaque joueur jamais en baisse, Confettis jamais
		-- négatifs, squishies des héros tous gardés par chaque renaissance
		it(
			"progression v2.0 ouverte, 16 joueurs : Grand Splorch, Jelly Ascend puis Petit Splorch par voyage dans le temps ; Record R jamais en baisse, squishies gardés, Confettis ≥ 0",
			function()
				local PROGRESSION = {
					"UpgradesScreen",
					"Confetti",
					"Workshop",
					"StarMat",
					"Gloves",
					"Monuments",
					"RecordR",
					"JellyAscend",
					"PetitSplorch",
					"Helpers",
				}
				local preset = {}
				for _, key in PROGRESSION do
					preset[key] = true
				end
				local w = world({ harness = Flags.harness(Harness, preset) })
				local Prestige = w.h:require("ReplicatedStorage.Shared.Logic.Prestige")
				for _, key in PROGRESSION do
					expect({ key = key, on = w.Features.get(key) }).toEqual({ key = key, on = true })
				end
				local seed = 11
				local players = {}
				-- 1-4 : prêts pour le Grand Splorch (R 2, Record R 2) ; 5-6 : prêts pour la Jelly Ascend
				-- (R = Record R = 15) ; 7-16 : vétérans pilotés par leur cerveau
				for i = 1, 16 do
					local profile
					if i <= 4 then
						profile = Brains.profile(w, {
							coins = 5000,
							R = 2,
							squishies = {
								{ s = 1, z = 100, bf = 1 },
								{ s = 2 + i, z = math.ceil(w.Formulas.splorchTarget(2) * 1.05) },
								{ s = 9, z = 300 },
							},
							edit = function(d)
								d.bestR = 2
							end,
						})
					elseif i <= 6 then
						profile = Brains.profile(w, {
							coins = 5000,
							R = 15,
							squishies = {
								{ s = 1, z = 100, bf = 1 },
								{ s = 2, z = 20000 },
								{ s = 3, z = 300 },
							},
							tiles = { snack = 12, decor = 10 },
							edit = function(d)
								d.bestR = 15
							end,
						})
					else
						profile = veteran(w, i)
					end
					players[i] = Brains.join(w, i, { profile = profile })
				end
				expect(#w.players).toBe(16)
				for i = 7, 16 do
					Bots.setBrain(players[i], Brains.player(w, seed + i))
				end
				local heroes = { players[1], players[2], players[3], players[4], players[5], players[6] }
				for _, p in heroes do
					takeOver(w, p)
					walk(w, p, Brains.atRanch(w, p, 0, 30))
				end
				-- contrôles v2.0 de chaque tick
				local best, uids = {}, {}
				local function keysOf(t)
					local out = {}
					for k in t do
						out[k] = true
					end
					return out
				end
				for _, p in heroes do
					uids[p] = keysOf(w.DS.get(p).squishies)
				end
				local function playV2(n)
					for _ = 1, n do
						play(w, 1)
						for _, p in w.players do
							if p.Parent ~= nil and w.DS.isLoaded(p) then
								local data = w.DS.get(p)
								local b = Prestige.bestR(data)
								if b < (best[p] or 0) then
									problem(
										w,
										"Record R en baisse " .. p.UserId .. " : " .. best[p] .. " → " .. b
									)
								end
								best[p] = math.max(best[p] or 0, b)
								if not (type(data.confetti) == "number" and data.confetti >= 0) then
									problem(
										w,
										"Confettis négatifs " .. p.UserId .. " : " .. tostring(data.confetti)
									)
								end
								local kept = uids[p]
								if kept then
									for uid in kept do
										if data.squishies[uid] == nil then
											problem(w, "squishy perdu " .. p.UserId .. " : " .. uid)
										end
									end
								end
							end
						end
					end
				end
				local function readyUid(p)
					local target = w.Formulas.splorchTarget(w.DS.get(p).R)
					for uid, r in w.Squishy.records(p) do
						if r.at == "pen" and w.Squishy.sizeOf(p, uid) >= target then
							return uid
						end
					end
					return nil
				end
				playV2(5)

				-- ---------------------------------------------------------------- Grand Splorch (4 héros, file)
				for i = 1, 4 do
					local flyer = readyUid(players[i])
					expect({ i = i, ready = flyer ~= nil }).toEqual({ i = i, ready = true })
					Bots.fire("GrandSplorch", players[i], false, flyer)
				end
				for _ = 1, 3000 do
					playV2(1)
					local done = true
					for i = 1, 4 do
						done = done and w.DS.get(players[i]).R == 3
					end
					if done then
						break
					end
				end
				for i = 1, 4 do
					local data = w.DS.get(players[i])
					expect({ i = i, R = data.R, bestR = data.bestR }).toEqual({ i = i, R = 3, bestR = 3 })
					expect(data.confetti > 0).toBe(true)
				end

				-- ---------------------------------------------------------------- voyage : le lendemain, Jelly Ascend
				travel(w, w.Clock.now() + DAY)
				playV2(20)
				for i = 5, 6 do
					Bots.fire("JellyAscend", players[i], true)
				end
				for _ = 1, 3000 do
					playV2(1)
					if w.DS.get(players[5]).ascend == 1 and w.DS.get(players[6]).ascend == 1 then
						break
					end
				end
				local startR = Prestige.startR(1, 0)
				for i = 5, 6 do
					local data = w.DS.get(players[i])
					expect({ i = i, A = data.ascend, R = data.R, bestR = data.bestR }).toEqual({
						i = i,
						A = 1,
						R = startR,
						bestR = 15,
					})
					expect(data.ascendDay).toBe(w.Clock.day())
				end
				playV2(50)

				-- ---------------------------------------------------------------- voyage : Petit Splorch (r ≤ Record R)
				-- les squishies grandissent avec le temps : sauts d'une heure jusqu'à l'objectif de r
				local petitFlyer = {}
				for _ = 1, 72 do
					travel(w, w.Clock.now() + 3600)
					playV2(5)
					local ready = true
					for i = 5, 6 do
						petitFlyer[i] = readyUid(players[i])
						ready = ready and petitFlyer[i] ~= nil
					end
					if ready then
						break
					end
				end
				for i = 5, 6 do
					expect({ i = i, ready = petitFlyer[i] ~= nil }).toEqual({ i = i, ready = true })
					local before = w.DS.get(players[i]).confetti
					Bots.fire("GrandSplorch", players[i], false, petitFlyer[i])
					playV2(5)
					local data = w.DS.get(players[i])
					expect({ i = i, R = data.R, bestR = data.bestR }).toEqual({
						i = i,
						R = startR + 1,
						bestR = 15,
					})
					expect(data.confetti > before).toBe(true)
				end
				for _, p in heroes do
					Bots.setBrain(p, Brains.player(w, seed + p.UserId))
				end
				playV2(300)

				-- ---------------------------------------------------------------- bilan
				expect(table.concat(w.problems, "\n")).toBe("")
				expect(#w.h.log.kicks).toBe(0)
				local counts = w.D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(table.concat(zeroTrace(w), "\n")).toBe("")
			end
		)

		it("fermeture (BindToClose) à 16 joueurs avec un DataStore lent : tout est sauvegardé", function()
			local w = world()
			local players = {}
			for i = 1, 16 do
				players[i] = Brains.join(w, i, { profile = veteran(w, i) })
				Bots.setBrain(players[i], Brains.player(w, 100 + i))
			end
			play(w, 200)
			local live = {}
			for _, p in players do
				local d = w.DS.get(p)
				live[p.UserId] = { coins = d.coins, R = d.R, n = count(d.squishies) }
			end
			-- DataStore lent : 0,1 s de vraie attente par écriture
			local cm = MockInstance.classMethods.DataStore
			local update, set = cm.UpdateAsync, cm.SetAsync
			cm.UpdateAsync = function(self, ...)
				task.wait(0.1)
				return update(self, ...)
			end
			cm.SetAsync = function(self, ...)
				task.wait(0.1)
				return set(self, ...)
			end
			local start = os.clock()
			local ok, err = pcall(function()
				w.h:close()
				w.h:settle(3)
			end)
			cm.UpdateAsync, cm.SetAsync = update, set
			expect(ok and true or err).toBe(true)
			expect(os.clock() - start < 30).toBe(true)
			for userId, k in live do
				local saved = stored(w, userId)
				expect(saved ~= nil).toBe(true)
				expect({ id = userId, unlocked = saved.lock == nil }).toEqual({ id = userId, unlocked = true })
				expect({ id = userId, R = saved.data.R, n = count(saved.data.squishies) }).toEqual({
					id = userId,
					R = k.R,
					n = k.n,
				})
				expect(saved.data.coins >= k.coins).toBe(true)
			end
			expect(table.concat(w.problems, "\n")).toBe("")
			expect(table.concat(zeroTrace(w), "\n")).toBe("")
		end)

		it("joueur présent avant le démarrage ; départ pendant le chargement : rien ne reste", function()
			local early
			local w = world({
				before = function(w0)
					-- arrivé avant que Main.server ne connecte PlayerAdded (course au démarrage)
					early = w0.h:addPlayer({ userId = 50, name = "Early" })
				end,
			})
			w.h:settle(5)
			for _ = 1, 20 do
				if w.Ranch.isReady(early) then
					break
				end
				w.h:settle(1)
			end
			expect(w.DS.isLoaded(early)).toBe(true)
			expect(w.Ranch.slotOf(early) ~= 0).toBe(true)
			-- chargement lent, départ avant la fin
			local cm = MockInstance.classMethods.DataStore
			local update, get = cm.UpdateAsync, cm.GetAsync
			cm.UpdateAsync = function(self, ...)
				task.wait(0.2)
				return update(self, ...)
			end
			cm.GetAsync = function(self, ...)
				task.wait(0.2)
				return get(self, ...)
			end
			local quick = Bots.join(51, { wait = false })
			w.h:settle(1)
			Bots.leave(quick)
			w.h:settle(1)
			cm.UpdateAsync, cm.GetAsync = update, get
			w.h:settle(10)
			play(w, 30)
			expect(w.Ranch.slotOf(quick)).toBe(0)
			local saved = stored(w, 51)
			expect(saved == nil or saved.lock == nil).toBe(true)
			-- il revient : chargé normalement
			local back = Brains.join(w, 51)
			expect(w.DS.isLoaded(back)).toBe(true)
			play(w, 30)
			expect(table.concat(w.problems, "\n")).toBe("")
			expect(table.concat(zeroTrace(w), "\n")).toBe("")
		end)
	end)
end
