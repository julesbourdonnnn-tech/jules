--!nocheck
-- Client complet piloté par un VRAI serveur (intégration client ↔ serveur).
--
-- 1. Partie serveur (tous les vrais services) : le joueur observé (UserId 1, nouveau joueur,
--    bouclier débutant) et 5 autres jouent : arrivée, Puffkins de bienvenue, chasse, parades,
--    amélioration, Supernova d'un vétéran (bouton ACCLAMER), ping et invitation d'équipage, coupe
--    mise en scène entre deux vétérans, Grande Comète (le joueur observé la ramasse et l'encaisse),
--    météo, Nuit de la Balise, Supernova du joueur observé, Starfall Saturday (changement de jour),
--    mort et réapparition, départ d'un joueur. Tout ce que le serveur envoie au joueur observé
--    (remotes, attributs répliqués, perchoirs, position de son personnage) est enregistré avec les
--    règles de sérialisation des remotes Roblox (tests/harness/Wire).
-- 2. Le vrai client (Main.client, 16 modules) rejoue ce flux au même instant de l'horloge
--    partagée. À des points de contrôle, son miroir est comparé à l'état du serveur : files (codes,
--    propriétaires), têtes des miettes, sauvages visibles, événements, équipages, profil. Le rendu
--    crée des pièces et réutilise ses rigs ; aucune erreur, aucun avertissement, aucun texte non
--    traduit ; aucune redemande d'instantané (RequestWorld) ni de miettes (RequestPath).
-- 3. Chaque panneau, onglet et bouton visible est pressé (HUD et panneaux), en anglais puis en
--    français ; les intentions envoyées par le client sont ensuite livrées au vrai serveur
--    (contexte du harnais restauré) : améliorations, Starforge, calendrier acceptés, sans erreur.
-- 4. Arrivée en cours de partie (Comète portée, files pleines), client tactile en français.
-- 5. Pendant toute la spec, l'API Roblox utilisée (classes, propriétés, types, droits d'écriture,
--    objectifs des tweens) est confrontée à la base de réflexion de Roblox (tests/harness/ApiAudit).
local Bots = require("../harness/Bots")
local Wire = require("../harness/Wire")
local ApiAudit = require("../harness/ApiAudit")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000 + 300 -- vendredi 15 janvier 2027, 08:05 UTC
	local ME = 1 -- UserId du joueur local du harnais client

	local S = nil -- session serveur enregistrée (étape 1)
	local C = nil -- client (étapes 2 et 3)

	local function fail(msg)
		error(msg, 2)
	end

	local function problemsOf(h)
		local out = table.clone(h.errors)
		for _, line in h:warnings() do
			table.insert(out, line)
		end
		return out
	end

	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- -----------------------------------------------------------------------------------------
	-- Étape 1 : partie serveur enregistrée
	-- -----------------------------------------------------------------------------------------

	-- instantané de l'état serveur, comparé au miroir du client au même instant du rejeu
	local function checkpoint(w, rec, label)
		local now = Bots.now()
		-- les apparitions sont groupées à 4 Hz : envoi immédiat (urgent) pour comparer à l'instant
		w.Spawn.flush(now, true)
		local me = w.h.game.Players:GetPlayerByUserId(ME)
		local data = { label = label, lines = {}, heads = {}, wild = {}, crews = {} }
		for _, p in w.h.game.Players:GetPlayers() do
			local slot = w.Nest.slotOf(p)
			if slot > 0 then
				data.lines[slot] = { userId = p.UserId, codes = table.clone(w.Conga.lineCodes(p)) }
				local root = Bots.rootOf(p)
				if root then
					data.heads[slot] = root.Position
				end
			end
		end
		if me then
			for _, s in w.Spawn.snapshotFor(me) do
				data.wild[s.id] = s.t0 + s.life
			end
		end
		local ev = w.Event.snapshot()
		data.events = {
			weather = ev.weather and ev.weather.key,
			comet = ev.comet and ev.comet.phase,
			carrier = ev.comet and ev.comet.carrierId,
			beacon = ev.beacon and ev.beacon.phase,
			frenzy = ev.frenzy ~= nil,
			boost = ev.serverBoost and ev.serverBoost.source,
			starfall = ev.starfall ~= nil,
			wisps = #ev.wisps,
		}
		for _, crew in w.Crew.snapshot().crews do
			local ids = table.clone(crew.userIds)
			table.sort(ids)
			table.insert(data.crews, table.concat(ids, ","))
		end
		table.sort(data.crews)
		local d = me and w.DS.get(me)
		if d then
			data.profile = {
				glow = d.glow,
				stardust = d.stardust,
				conga = d.upgrades.conga,
				supernovas = d.supernovas,
				nebbies = count(d.nebbies),
				step = d.onboarding.step,
			}
		end
		table.insert(rec.events, { kind = "check", t = now, data = data })
		return data
	end

	local function runServer()
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				for i = 3, 6 do
					Bots.saveProfile(w, i, Bots.veteranProfile(w, T0, if i == 3 then 450000 else 3000))
				end
			end,
		})
		Bots.use(w)
		local h = w.h
		local rec = Wire.record(h, {
			userId = ME,
			Clock = w.Clock,
			remotes = { "Feedback", "Banner", "Celebrate" },
		})
		w.onFrame = function()
			rec:frame()
		end
		h:makeFriends(ME, 2)
		local me = h:addPlayer({ userId = ME, name = "Observed", locale = "en-us" })
		table.insert(w.players, me)
		for i = 2, 6 do
			local p =
				h:addPlayer({ userId = i, name = "P" .. i, locale = if i % 2 == 0 then "fr-fr" else "en-us" })
			table.insert(w.players, p)
		end
		h:settle(10)
		for i, p in w.players do
			Bots.hunt(p, if i <= 2 then 4 else 8, if i <= 2 then 140 else 70, (i % 3 - 1) * 0.4)
		end
		Bots.frames(3, Bots.brains)
		checkpoint(w, rec, "arrivée")
		-- chasse et parades
		local paraded = false
		for t = 1, 900 do
			Bots.frame(Bots.brains)
			if w.brains[me].parades >= 2 and t >= 300 then
				paraded = true
				break
			end
		end
		assert(paraded, "le joueur observé n'a pas paradé deux fois")
		checkpoint(w, rec, "chasse")
		-- amélioration (le joueur observé), refus (pas assez de Glow) compris
		Bots.fire("BuyUpgrade", me, "conga")
		Bots.fire("BuyUpgrade", me, "perches")
		Bots.frames(5, Bots.brains)
		-- Supernova du vétéran 3 au port sûr : CheerPrompt au joueur observé, qui acclame
		local hero = w.players[3]
		w.brains[hero].paused = true
		Bots.walkAll({ [hero] = Bots.harborPoint(hero) }, 500, Bots.brains)
		Bots.fire("Supernova", hero)
		assert(w.DS.get(hero).supernovas == 1, "Supernova refusée")
		Bots.frames(2, Bots.brains)
		Bots.fire("Cheer", me, hero.UserId)
		w.brains[hero].paused = false
		-- social : ping de l'ami (équipier automatique), invitation d'un autre joueur
		Bots.fire("Ping", w.players[2], 2)
		Bots.fire("CrewInvite", w.players[4], ME)
		Bots.fire("ClaimDaily", me)
		Bots.frames(30, Bots.brains)
		checkpoint(w, rec, "social")
		-- coupe mise en scène entre deux vétérans (le joueur observé la voit)
		local staged = Bots.stageSnip(w.players[5], w.players[6], 6)
		assert(staged.count == 1, "coupe mise en scène ratée")
		Bots.frames(10, Bots.brains)
		checkpoint(w, rec, "coupe")
		-- Grande Comète : le joueur observé la ramasse et l'encaisse à sa porte
		local slot = w.EC.nextComet(Bots.now())
		local impact = w.EC.cometImpact(slot.id)
		w.brains[me].paused = true
		Bots.travelTo(slot.impactAt - 45)
		-- scène réservée : les autres rentrent à leur port sûr (pas de vol imprévu)
		local targets = Bots.sendHome({ [me] = true })
		targets[me] = impact
		Bots.walkAll(targets, 420)
		while Bots.now() < slot.impactAt + 0.25 do
			Bots.frame()
		end
		Bots.stepToward(me, impact + w.V3.new(0.5, 0, 0))
		Bots.frames(2)
		assert(w.Event.isCarrier(me), "le joueur observé n'a pas ramassé la Comète")
		checkpoint(w, rec, "porteur")
		Bots.walkAll({ [me] = Bots.gateOf(me) }, 700)
		Bots.frames(3)
		assert(w.Event.snapshot().comet.phase == "banked", "Comète non encaissée")
		Bots.resume()
		checkpoint(w, rec, "comète")
		-- météo
		local weather = w.EC.nextWeather(Bots.now())
		Bots.travelTo(weather.startsAt - 1)
		Bots.frames(60, Bots.brains)
		checkpoint(w, rec, "météo")
		-- Nuit de la Balise : alerte, trêve, puis fin (résultat)
		local beacon = w.EC.nextBeacon(Bots.now())
		Bots.travelTo(beacon.warnAt - 2)
		while Bots.now() < beacon.startsAt + 25 do
			Bots.frame(Bots.brains)
		end
		checkpoint(w, rec, "balise")
		Bots.travelTo(beacon.endsAt - 3)
		Bots.frames(60, Bots.brains)
		checkpoint(w, rec, "fin de balise")
		-- Supernova du joueur observé (célébration, constellation de son Nid, acclamations)
		local targets = Bots.sendHome({})
		Bots.walkAll(targets, 600)
		assert(w.Nest.inOwnHarbor(me), "le joueur observé n'est pas à son port sûr")
		assert(w.DS.get(me).glow >= w.F.supernovaCost(0), "pas assez de Glow pour la Supernova")
		Bots.fire("Supernova", me)
		assert(w.DS.get(me).supernovas == 1, "Supernova du joueur observé refusée")
		Bots.fire("Cheer", w.players[2], ME)
		Bots.resume()
		Bots.frames(40, Bots.brains)
		checkpoint(w, rec, "supernova")
		-- Starfall Saturday (saut d'un jour et demi : changement de jour UTC compris)
		local starfall = w.EC.nextStarfall(Bots.now())
		Bots.travelTo(starfall.startsAt - 10)
		Bots.frames(150, Bots.brains)
		checkpoint(w, rec, "starfall")
		-- mort puis réapparition du joueur observé ; départ d'un autre joueur
		me.Character.Humanoid.Health = 0
		Bots.frames(3, Bots.brains)
		h:respawn(me)
		Bots.frames(20, Bots.brains)
		local leaver = w.players[6]
		table.remove(w.players, 6)
		h:removePlayer(leaver)
		h:settle(5)
		Bots.frames(30, Bots.brains)
		checkpoint(w, rec, "fin")
		rec:stop()
		w.onFrame = nil
		return { w = w, rec = rec, me = me, problems = Bots.problems() }
	end

	-- Arrivée en cours de partie (docs §10.6) : 5 joueurs jouent déjà (files pleines, sauvages,
	-- Comète portée) quand le joueur observé (vétéran, profil sauvegardé avec une collection)
	-- arrive ; son client ne connaît le monde que par le WorldSnapshot puis le flux normal.
	local function runLateJoin()
		local t0 = T0 + 7 * 86400 + 1800
		local w = Bots.boot(Harness, {
			t0 = t0,
			before = function(w)
				for i = 1, 6 do
					local d = Bots.veteranProfile(w, t0, 5000)
					if i == ME then
						-- collection : Nebbies perchés (revenu passif, Nid décoré à l'arrivée)
						for k = 1, 12 do
							d.nebbies["u" .. k] = { s = 1 + (k % 6), f = k % 3, v = 0, st = 1 + (k % 2) }
						end
						d.nextUid = 13
					end
					Bots.saveProfile(w, i, d)
				end
			end,
		})
		Bots.use(w)
		local h = w.h
		for i = 2, 6 do
			local p = h:addPlayer({ userId = i, name = "P" .. i })
			table.insert(w.players, p)
		end
		h:settle(10)
		for i, p in w.players do
			Bots.hunt(p, 8, 60 + i * 12, (i % 3 - 1) * 0.4)
		end
		Bots.frames(250, Bots.brains)
		-- Comète : le joueur 3 la ramasse, le joueur observé arrive pendant qu'elle est portée
		local slot = w.EC.nextComet(Bots.now())
		local impact = w.EC.cometImpact(slot.id)
		local carrier = w.players[2]
		Bots.travelTo(slot.impactAt - 40)
		local targets = Bots.sendHome({ [carrier] = true })
		targets[carrier] = impact
		Bots.walkAll(targets, 380)
		while Bots.now() < slot.impactAt + 0.25 do
			Bots.frame()
		end
		Bots.stepToward(carrier, impact + w.V3.new(0.5, 0, 0))
		Bots.frames(2)
		assert(w.Event.isCarrier(carrier), "Comète non ramassée")
		Bots.resume()
		w.brains[carrier].paused = true
		Bots.frames(20, Bots.brains)
		local rec = Wire.record(h, {
			userId = ME,
			Clock = w.Clock,
			remotes = { "Feedback", "Banner", "Celebrate" },
		})
		w.onFrame = function()
			rec:frame()
		end
		local me = h:addPlayer({ userId = ME, name = "Observed", locale = "fr-fr" })
		table.insert(w.players, me)
		h:settle(10)
		Bots.hunt(me, 8, 90, 0)
		Bots.frames(3, Bots.brains)
		checkpoint(w, rec, "arrivée tardive")
		-- le porteur rentre encaisser pendant que les autres jouent
		Bots.walkAll({ [carrier] = Bots.gateOf(carrier) }, 700, Bots.brains)
		Bots.frames(3, Bots.brains)
		assert(w.Event.snapshot().comet.phase == "banked", "Comète non encaissée")
		w.brains[carrier].paused = false
		checkpoint(w, rec, "comète encaissée")
		Bots.frames(300, Bots.brains)
		checkpoint(w, rec, "jeu")
		rec:stop()
		w.onFrame = nil
		return { w = w, rec = rec, me = me, problems = Bots.problems() }
	end

	-- -----------------------------------------------------------------------------------------
	-- Étape 2 : client complet qui rejoue le flux
	-- -----------------------------------------------------------------------------------------

	local function bootClient(rec, locale, touch)
		local c = Harness.new({ mode = "client", touch = touch == true })
		c.localPlayer.LocaleId = locale or "en-us"
		c:createRemotes()
		local Clock = c:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(rec.events[1].t - 0.5)
		-- compteurs de rigs : construits (NebbyBuilder) contre acquis (RigPool)
		local NebbyBuilder = c:require("ReplicatedStorage.Shared.Render.NebbyBuilder")
		local RigPool = c:require(CLIENT .. "World.RigPool")
		local stats = { built = 0, acquired = 0, maxParts = 0 }
		local build = NebbyBuilder.build
		NebbyBuilder.build = function(...)
			stats.built += 1
			return build(...)
		end
		local acquire = RigPool.acquire
		RigPool.acquire = function(...)
			stats.acquired += 1
			return acquire(...)
		end
		-- produits et passes activés (les IDs réels sont posés au Creator Hub) : boutons d'achat
		local Mon = c:require("ReplicatedStorage.Shared.Config.Monetization")
		local nextId = 9000
		for _, group in { Mon.Products, Mon.Passes } do
			for _, def in group do
				nextId += 1
				def.id = nextId
			end
		end
		Wire.installWorld(rec, c)
		c:boot()
		local m = {
			h = c,
			Clock = Clock,
			stats = stats,
			WSC = c:require(CLIENT .. "Controllers.WorldStateController"),
			CR = c:require(CLIENT .. "Controllers.CongaRenderer"),
			State = c:require(CLIENT .. "Controllers.StateController"),
			Panels = c:require(CLIENT .. "Controllers.PanelController"),
			HUD = c:require(CLIENT .. "UI.HUD"),
			FX = c:require(CLIENT .. "UI.ScreenFX"),
			Banners = c:require(CLIENT .. "UI.Banners"),
			Prefs = c:require(CLIENT .. "Util.Prefs"),
			received = { feedback = 0, celebrate = 0, banner = 0, snipped = 0, banked = 0, caught = 0 },
		}
		m.FX.FeedbackReceived:Connect(function()
			m.received.feedback += 1
		end)
		m.FX.Celebrated:Connect(function()
			m.received.celebrate += 1
		end)
		m.Banners.Shown:Connect(function()
			m.received.banner += 1
		end)
		m.WSC.Snipped:Connect(function()
			m.received.snipped += 1
		end)
		m.WSC.Banked:Connect(function()
			m.received.banked += 1
		end)
		m.WSC.Caught:Connect(function()
			m.received.caught += 1
		end)
		return m
	end

	-- textes visibles non traduits : variable {x} restée, clé brute ("feedback.snipped")
	local function untranslated(c)
		local out = {}
		for _, d in c.localPlayer.PlayerGui:GetDescendants() do
			if d.ClassName == "TextLabel" or d.ClassName == "TextButton" or d.ClassName == "TextBox" then
				local text = d.Text
				if type(text) == "string" and text ~= "" then
					if string.find(text, "{%a+}") or string.match(text, "^%l+%.%a[%w%.]*$") then
						table.insert(out, d:GetFullName() .. " = " .. text)
					end
				end
			end
		end
		return out
	end

	local function verify(m, data)
		local label = "[" .. data.label .. "] "
		local now = m.Clock.now()
		-- files : codes identiques, slot par slot
		for slot = 1, 12 do
			local server = data.lines[slot]
			local mirror = m.WSC.line(slot)
			if server then
				if mirror == nil then
					fail(label .. "file du slot " .. slot .. " absente du miroir")
				end
				if mirror.userId ~= server.userId then
					fail(
						label
							.. "propriétaire du slot "
							.. slot
							.. " : "
							.. mirror.userId
							.. " ≠ "
							.. server.userId
					)
				end
				if table.concat(mirror.codes, ",") ~= table.concat(server.codes, ",") then
					fail(
						`{label}file du slot {slot} : client [{table.concat(mirror.codes, ",")}] ≠ serveur [{table.concat(
							server.codes,
							","
						)}]`
					)
				end
			elseif mirror ~= nil then
				fail(label .. "slot " .. slot .. " libre côté serveur, occupé côté client")
			end
			-- tête des miettes ≈ position serveur du personnage (pas réseau de 1 stud, 1/8 stud)
			local head = data.heads[slot]
			local trail = m.WSC.trail(slot)
			if head and trail and trail:head() then
				local d = (trail:head() - head).Magnitude
				if d > 2.5 then
					fail(`{label}miettes du slot {slot} : tête à {d} studs de la position serveur`)
				end
			end
		end
		-- sauvages visibles par ce joueur (hors expirations à ±0,3 s)
		local wilds = m.WSC.wilds()
		for id, expiresAt in data.wild do
			if math.abs(expiresAt - now) > 0.3 and wilds[id] == nil then
				fail(`{label}sauvage {id} absent du miroir`)
			end
		end
		for id, w in wilds do
			if data.wild[id] == nil and math.abs(w.expiresAt - now) > 0.3 then
				fail(`{label}sauvage {id} en trop dans le miroir`)
			end
		end
		-- événements
		local ev = m.WSC.events()
		if ev == nil then
			fail(label .. "aucun EventState")
		end
		local e = data.events
		local got = {
			weather = ev.weather and ev.weather.key,
			comet = ev.comet and ev.comet.phase,
			carrier = ev.comet and ev.comet.carrierId,
			beacon = ev.beacon and ev.beacon.phase,
			frenzy = ev.frenzy ~= nil,
			boost = ev.serverBoost and ev.serverBoost.source,
			starfall = ev.starfall ~= nil,
			wisps = #ev.wisps,
		}
		for k, v in e do
			if got[k] ~= v then
				fail(`{label}événements.{k} : client {tostring(got[k])} ≠ serveur {tostring(v)}`)
			end
		end
		-- équipages
		local crews = {}
		for _, crew in m.WSC.crews().crews do
			local ids = table.clone(crew.userIds)
			table.sort(ids)
			table.insert(crews, table.concat(ids, ","))
		end
		table.sort(crews)
		if table.concat(crews, ";") ~= table.concat(data.crews, ";") then
			fail(
				`{label}équipages : client {table.concat(crews, ";")} ≠ serveur {table.concat(
					data.crews,
					";"
				)}`
			)
		end
		-- profil (DataSnapshot + DataPatch)
		local p = data.profile
		if p then
			local upgrades = m.State.get("upgrades")
			local nebbies = m.State.get("nebbies")
			local onboarding = m.State.get("onboarding")
			local got2 = {
				glow = m.State.get("glow"),
				stardust = m.State.get("stardust"),
				conga = upgrades and upgrades.conga,
				supernovas = m.State.get("supernovas"),
				nebbies = nebbies and count(nebbies),
				step = onboarding and onboarding.step,
			}
			for k, v in p do
				if got2[k] ~= v then
					fail(`{label}profil.{k} : client {tostring(got2[k])} ≠ serveur {tostring(v)}`)
				end
			end
		end
		-- localisation
		local bad = untranslated(m.h)
		if #bad > 0 then
			fail(label .. "textes non traduits :\n" .. table.concat(bad, "\n"))
		end
		m.checks = (m.checks or 0) + 1
	end

	local function replay(m, rec)
		local maxParts = 0
		Wire.replay(rec, m.h, {
			Clock = m.Clock,
			frameDt = 0.1,
			onFrame = function()
				maxParts = math.max(maxParts, m.CR.renderedParts())
			end,
			onEvent = function(e)
				if e.kind == "check" then
					verify(m, e.data)
				end
			end,
		})
		m.stats.maxParts = maxParts
	end

	local function sentByClient(m, remote)
		local out = {}
		for _, e in m.h.log.serverEvents do
			if remote == nil or e.remote == remote then
				table.insert(out, e)
			end
		end
		return out
	end

	-- -----------------------------------------------------------------------------------------

	describe("Client complet piloté par un vrai serveur", function()
		it(
			"partie serveur enregistrée : 6 joueurs, événements, aucune charge utile mal formée",
			function()
				-- audit de l'API Roblox pendant toute la spec (serveur, client, interface)
				ApiAudit.start()
				S = runServer()
				if #S.problems > 0 then
					fail("serveur :\n" .. table.concat(S.problems, "\n"))
				end
				if #S.rec.problems > 0 then
					fail(
						"charges utiles non conformes aux remotes Roblox :\n"
							.. table.concat(S.rec.problems, "\n")
					)
				end
				local rec = S.rec
				for _, remote in
					{
						"DataSnapshot",
						"DataPatch",
						"WorldSnapshot",
						"PathStream",
						"LineEvent",
						"WildEvent",
						"SnipEvent",
						"EventState",
						"CrewState",
						"Banner",
						"Feedback",
						"Celebrate",
						"CheerPrompt",
						"CrewInvitePrompt",
						"PingShow",
					}
				do
					if rec:count(remote) == 0 then
						fail("aucun " .. remote .. " reçu par le joueur observé")
					end
				end
				print(`événements enregistrés : {#rec.events}`)
			end
		)

		it("le client rejoue la partie : miroir identique au serveur, rendu, aucune redemande", function()
			assert(S, "étape serveur en échec")
			local server = Wire.saveContext()
			C = bootClient(S.rec, "en-us")
			replay(C, S.rec)
			local m = C
			expect(m.checks).toBe(S.rec.events and (function()
				local n = 0
				for _, e in S.rec.events do
					if e.kind == "check" then
						n += 1
					end
				end
				return n
			end)())
			-- le flux suffit : aucun trou de version ni de miettes
			expect(#sentByClient(m, "RequestWorld")).toBe(0)
			expect(#sentByClient(m, "RequestPath")).toBe(0)
			-- chaque Feedback / Celebrate livré a été accepté par ScreenFX
			expect(m.received.feedback).toBe(S.rec:count("Feedback"))
			expect(m.received.celebrate).toBe(S.rec:count("Celebrate"))
			expect(m.received.banner > 0).toBe(true)
			expect(m.received.snipped >= 1).toBe(true)
			expect(m.received.banked >= 2).toBe(true)
			expect(m.received.caught >= 4).toBe(true)
			-- rendu : des pièces, des rigs réutilisés, budget respecté
			expect(m.stats.maxParts > 0).toBe(true)
			expect(m.stats.maxParts <= 1500).toBe(true)
			expect(m.stats.acquired > m.stats.built).toBe(true)
			local world = m.h.workspace:FindFirstChild("ClientWorld")
			expect(world ~= nil).toBe(true)
			local mySlot = m.WSC.localSlot()
			expect(mySlot >= 1).toBe(true)
			local problems = problemsOf(m.h)
			if #problems > 0 then
				fail("client :\n" .. table.concat(problems, "\n"))
			end
			print(
				`rigs construits {m.stats.built}, acquis {m.stats.acquired}, pièces max {m.stats.maxParts}, contrôles {m.checks}`
			)
			C.server = server
		end)

		-- bouton visible dans sa hiérarchie (ScreenGui activé, ancêtres visibles)
		local function shown(gui)
			local cur = gui
			while cur do
				if cur.ClassName == "ScreenGui" then
					return cur.Enabled ~= false
				end
				if cur:IsA("GuiObject") and cur.Visible == false then
					return false
				end
				cur = cur.Parent
			end
			return false
		end

		local function visibleButtons(root)
			local out = {}
			for _, d in root:GetDescendants() do
				if (d.ClassName == "TextButton" or d.ClassName == "ImageButton") and shown(d) then
					table.insert(out, d)
				end
			end
			return out
		end

		-- rang d'un bouton : contenu d'abord, puis onglets, puis en-tête (Retour, Fermer)
		local function rank(b)
			local cur = b
			while cur do
				if cur.Name == "Tabs" then
					return 2
				elseif cur.Name == "Header" then
					return 3
				end
				cur = cur.Parent
			end
			return 1
		end

		-- presse chaque bouton visible de `root` une fois, en profondeur : après chaque pression on
		-- recherche (un onglet révèle son contenu, qui passe avant les onglets suivants) ;
		-- `reopen()` remet le panneau si un bouton l'a fermé ou en a ouvert un autre
		local function pressAll(m, root, reopen, pressed)
			local presses = 0
			for _ = 1, 400 do
				local best, bestRank = nil, math.huge
				for _, b in visibleButtons(root) do
					if not pressed[b] then
						local r = rank(b)
						if r < bestRank then
							best, bestRank = b, r
						end
					end
				end
				if best == nil then
					break
				end
				pressed[best] = true
				presses += 1
				best.Activated:Fire()
				-- le temps passe entre deux pressions (gardes anti double appui des boutons)
				m.Clock.advance(0.5)
				m.h:step(1 / 30, 2)
				if reopen then
					reopen()
				end
			end
			return presses
		end

		local function uiRound(m, label)
			local c = m.h
			local P = m.Panels
			local gui = c.localPlayer.PlayerGui
			m.HUD.revealAll()
			c:step(1 / 30, 10)
			-- HUD : chaque bouton (rail, Dash, ping, pastille d'événement, ACCLAMER…)
			local pressedHud = {}
			local hud = gui:FindFirstChild("HUD")
			expect(hud ~= nil).toBe(true)
			local hudPresses = pressAll(m, hud, function()
				if P.current() ~= nil then
					P.close()
					c:step(1 / 30, 10)
				end
			end, pressedHud)
			expect(hudPresses >= 5).toBe(true)
			-- panneaux : ouverture, chaque onglet et chaque bouton, fermeture
			local opened = {}
			P.Opened:Connect(function(name)
				opened[name] = true
			end)
			local args = {
				ReturnScreen = { data = { glow = 123456, seconds = 7200, nightShift = false } },
				Collection = { tab = "atlas" },
				Upgrades = { focus = "conga" },
			}
			local total = 0
			local rounds = table.clone(P.NAMES)
			table.insert(rounds, "Upgrades") -- sans focus d'accueil : les 5 cartes
			for i, name in rounds do
				if i > #P.NAMES then
					args[name] = nil
				end
				P.open(name, args[name])
				c:step(1 / 30, 10)
				expect(P.current()).toBe(name)
				local page = P.page(name)
				expect(page ~= nil).toBe(true)
				local pressed = {}
				total += pressAll(m, page, function()
					if P.current() ~= name then
						P.open(name, args[name])
						c:step(1 / 30, 5)
					end
				end, pressed)
				-- navigation clavier / manette entre onglets
				P.nextTab(1)
				P.nextTab(-1)
				c:step(1 / 30, 5)
				P.close()
				c:step(1 / 30, 15)
				expect(P.current()).toBeNil()
			end
			for _, name in P.NAMES do
				if not opened[name] then
					fail(label .. " : panneau jamais ouvert : " .. name)
				end
			end
			expect(total >= 30).toBe(true)
			c:step(1 / 30, 60)
			local bad = untranslated(c)
			if #bad > 0 then
				fail(label .. " : textes non traduits :\n" .. table.concat(bad, "\n"))
			end
			return total
		end

		it("chaque panneau, chaque onglet et chaque bouton du HUD, en anglais puis en français", function()
			assert(C, "rejeu en échec")
			local m = C
			local c = m.h
			-- RedeemCode (RemoteFunction) : le client attend une réponse ; journalisée ici
			local invoked = {}
			local MockInstance = require("../harness/MockInstance")
			MockInstance.onInvokeServer = function(remote, ...)
				table.insert(invoked, { remote = remote.Name, args = table.pack(...) })
				return "invalid"
			end
			local en = uiRound(m, "anglais")
			-- passage en français : réponse du serveur au réglage de langue (DataPatch des réglages)
			local settings = table.clone(m.State.get("settings"))
			settings.lang = "fr"
			c:fireClient("ReplicatedStorage.Remotes.DataPatch", { settings = settings }, {})
			c:step(1 / 30, 5)
			expect(m.Prefs.language()).toBe("fr")
			local fr = uiRound(m, "français")
			print(`boutons pressés : {en} (EN), {fr} (FR) ; intentions envoyées : {#c.log.serverEvents}`)
			-- intentions du client : charges utiles transmissibles
			local problems = {}
			for _, e in c.log.serverEvents do
				Wire.copyArgs(e.remote, problems, table.unpack(e.args, 1, e.args.n))
			end
			if #problems > 0 then
				fail("intentions mal formées :\n" .. table.concat(problems, "\n"))
			end
			local kinds = {}
			for _, e in c.log.serverEvents do
				kinds[e.remote] = true
			end
			for _, remote in
				{
					"BuyUpgrade",
					"SetSetting",
					"Fuse",
					"FuseAll",
					"RerollQuest",
					"ClaimDaily",
					"EquipCosmetic",
				}
			do
				if not kinds[remote] then
					fail("aucune intention " .. remote .. " envoyée par l'interface")
				end
			end
			-- boutiques : 6 passes et 6 produits proposés (MarketplaceService), deux langues
			expect(#c.log.prompts >= 12).toBe(true)
			local problems2 = problemsOf(c)
			if #problems2 > 0 then
				fail("client :\n" .. table.concat(problems2, "\n"))
			end
			C.invoked = invoked
		end)

		it("les intentions envoyées par l'interface sont acceptées par le vrai serveur", function()
			assert(C and S and C.server, "étapes précédentes en échec")
			local intents = table.clone(C.h.log.serverEvents)
			local invoked = C.invoked or {}
			-- retour au DataModel du serveur
			Wire.restoreContext(C.server)
			local w = S.w
			Bots.use(w)
			local me = S.me
			local before = table.clone(w.DS.get(me).upgrades)
			local function starred()
				local n = 0
				for _, rec in w.DS.get(me).nebbies do
					if rec.st >= 2 then
						n += 1
					end
				end
				return n
			end
			local starsBefore = starred()
			local dailyBefore = w.DS.get(me).daily.day
			local counts = {}
			for _, e in intents do
				counts[e.remote] = (counts[e.remote] or 0) + 1
				w.h:fireServer(
					"ReplicatedStorage.Remotes." .. e.remote,
					me,
					table.unpack(e.args, 1, e.args.n)
				)
			end
			for _, e in invoked do
				local status = w.h:invokeServer(
					"ReplicatedStorage.Remotes." .. e.remote,
					me,
					table.unpack(e.args, 1, e.args.n)
				)
				expect(type(status)).toBe("string")
			end
			Bots.frames(10)
			-- au moins une amélioration achetée depuis le panneau (le joueur a largement de quoi)
			local after = w.DS.get(me).upgrades
			local bought = 0
			for track, level in after do
				bought += level - (before[track] or 0)
			end
			expect(bought >= 1).toBe(true)
			-- Starforge depuis la Forge, calendrier du jour depuis les Objectifs
			expect(starred() > starsBefore).toBe(true)
			expect(dailyBefore ~= w.Clock.day()).toBe(true)
			expect(w.DS.get(me).daily.day).toBe(w.Clock.day())
			local problems = Bots.problems()
			if #problems > 0 then
				fail("serveur :\n" .. table.concat(problems, "\n"))
			end
			local list = {}
			for remote, n in counts do
				table.insert(list, remote .. "×" .. n)
			end
			table.sort(list)
			print("intentions livrées : " .. table.concat(list, ", "))
		end)

		it(
			"arrivée en cours de partie (tactile, français) : instantané puis flux, miroir identique",
			function()
				local L = runLateJoin()
				if #L.problems > 0 then
					fail("serveur :\n" .. table.concat(L.problems, "\n"))
				end
				if #L.rec.problems > 0 then
					fail("charges utiles non conformes :\n" .. table.concat(L.rec.problems, "\n"))
				end
				expect(L.rec:count("WorldSnapshot")).toBe(1)
				local m = bootClient(L.rec, "fr-fr", true)
				replay(m, L.rec)
				expect(m.checks).toBe(3)
				expect(#sentByClient(m, "RequestWorld")).toBe(0)
				expect(#sentByClient(m, "RequestPath")).toBe(0)
				expect(m.received.feedback).toBe(L.rec:count("Feedback"))
				expect(m.received.celebrate).toBe(L.rec:count("Celebrate"))
				expect(m.received.banked >= 1).toBe(true)
				expect(m.Prefs.language()).toBe("fr")
				-- tactile : type d'entrée annoncé au serveur
				local inputs = sentByClient(m, "SetInputType")
				expect(#inputs >= 1).toBe(true)
				expect(inputs[#inputs].args[1]).toBe(1)
				-- Nid du joueur observé décoré dès l'arrivée (perchés du profil sauvegardé)
				local slot = m.WSC.localSlot()
				expect(slot >= 1).toBe(true)
				expect(m.CR.perchCount(slot) >= 1).toBe(true)
				local problems = problemsOf(m.h)
				if #problems > 0 then
					fail("client :\n" .. table.concat(problems, "\n"))
				end
			end
		)

		it(
			"API Roblox : classes, propriétés, types et droits d'écriture réels (serveur et client)",
			function()
				local issues = ApiAudit.stop()
				local nw, nr, nc = ApiAudit.counts()
				print(
					`API auditée : {nw} propriétés écrites, {nr} lectures inconnues du harnais, {nc} classes`
				)
				if #issues > 0 then
					fail("écarts avec l'API Roblox :\n" .. table.concat(issues, "\n"))
				end
			end
		)
	end)
end
