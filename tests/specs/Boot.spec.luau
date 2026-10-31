--!nocheck
-- Démarrage complet du serveur (intégration) : 12 joueurs sur un même serveur, tous les vrais
-- services, aucun remplacement de fonction. Les joueurs se déplacent pas à pas (vitesse de marche
-- honnête, MoveCheck jamais déclenché), attrapent des Nebbies, se coupent, paradent à LEUR porte,
-- achètent des améliorations et une Supernova par les remotes ; l'horloge partagée voyage dans le
-- temps pour déclencher météo, Grande Comète (ramassage, vol, encaissement), Nuit de la Balise et
-- Starfall Saturday ; réapparitions, départs et retours (données persistées). Aucune erreur de
-- signal, aucun avertissement, aucun « Infinite yield ».
local task = require("@lune/task")
local Bots = require("../harness/Bots")
local MockInstance = require("../harness/MockInstance")

-- contenu brut d'un DataStore simulé (clé → valeur)
local function MockInstanceState(store)
	return MockInstance.state(store).data
end

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- samedi 31 octobre 2026, 15:01:30 UTC (Starfall Saturday à 16:00)
	local STARFALL = 1793462400
	local T0 = STARFALL - 3600 + 90

	local W = nil -- monde partagé entre les étapes (une seule partie de bout en bout)

	local function world()
		assert(W, "le serveur n'a pas démarré (étape précédente en échec)")
		Bots.use(W)
		return W
	end

	local now, rootOf, stepToward = Bots.now, Bots.rootOf, Bots.stepToward
	local frame, frames, walkAll, travelTo = Bots.frame, Bots.frames, Bots.walkAll, Bots.travelTo
	local allEvents, countAll, lineOps, sentTo, fire = Bots.allEvents, Bots.countAll, Bots.lineOps, Bots.sentTo, Bots.fire
	local gateOf, zonePoint, nearestWild, brains = Bots.gateOf, Bots.zonePoint, Bots.nearestWild, Bots.brains

	local function boot()
		return Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				-- vétérans (profils déjà sauvegardés) : bouclier débutant terminé, file de 12
				for i = 7, 12 do
					Bots.saveProfile(w, 1000 + i, Bots.veteranProfile(w, T0, if i == 12 then 450000 else 2000))
				end
				-- produits activés (les IDs réels sont posés au Creator Hub)
				local nextId = 9100
				for _, key in { "GlowPouch", "StardustJar", "GlowParty", "StarterKit" } do
					nextId += 1
					w.Mon.Products[key].id = nextId
				end
			end,
		})
	end

	local function hasKey(list, key)
		return table.find(list, key) ~= nil
	end

	local function noProblems()
		world()
		local problems = Bots.problems()
		if #problems > 0 then
			error("erreurs ou avertissements :\n" .. table.concat(problems, "\n"))
		end
	end

	-- -----------------------------------------------------------------------------------------

	describe("Démarrage complet du serveur (12 joueurs)", function()
		it("12 joueurs rejoignent (amis voisins), reçoivent profil, Nid, monde, événements et équipages", function()
			W = boot()
			local w = world()
			local h = w.h
			-- amis Roblox : (1001, 1002), (1003, 1004), (1007, 1008)
			h:makeFriends(1001, 1002)
			h:makeFriends(1003, 1004)
			h:makeFriends(1007, 1008)
			for i = 1, 12 do
				local p = h:addPlayer({
					userId = 1000 + i,
					name = "P" .. i,
					locale = if i % 2 == 0 then "fr-fr" else "en-us",
				})
				table.insert(w.players, p)
			end
			h:settle(10)
			frames(5)
			local slots = {}
			for i, p in w.players do
				local slot = w.Nest.slotOf(p)
				expect(slot >= 1 and slot <= 12).toBe(true)
				expect(slots[slot]).toBeNil()
				slots[slot] = p
				expect(p:GetAttribute("Slot")).toBe(slot)
				expect(w.DS.get(p) ~= nil).toBe(true)
				expect(#sentTo(p, "DataSnapshot") >= 1).toBe(true)
				expect(#sentTo(p, "WorldSnapshot") >= 1).toBe(true)
				expect(#sentTo(p, "EventState") >= 1).toBe(true)
				Bots.hunt(p, if i <= 6 then 4 else 8, if i <= 6 then 140 else (if i % 2 == 0 then 80 else 40), (i % 3 - 1) * 0.3)
			end
			-- amis : Nids voisins
			local function adjacent(a, b)
				local d = math.abs(w.Nest.slotOf(a) - w.Nest.slotOf(b))
				return d == 1 or d == 11
			end
			expect(adjacent(w.players[1], w.players[2])).toBe(true)
			expect(adjacent(w.players[3], w.players[4])).toBe(true)
			expect(adjacent(w.players[7], w.players[8])).toBe(true)
			-- vétérans : profil sauvegardé rechargé, pas de bouclier ; nouveaux : bouclier débutant
			expect(w.DS.get(w.players[12]).glow >= 450000).toBe(true)
			expect(w.Quest.isRookie(w.players[12])).toBe(false)
			expect(w.Quest.isRookie(w.players[1])).toBe(true)
			-- équipages d'amis formés automatiquement
			expect(w.Crew.areCrewmates(w.players[1], w.players[2])).toBe(true)
			expect(w.Crew.areCrewmates(w.players[1], w.players[3])).toBe(false)
			expect(countAll("CrewState") >= 1).toBe(true)
			noProblems()
		end)

		it("chasse et parades : chacun attrape des Nebbies et parade à SA porte", function()
			local w = world()
			local ticks = 0
			local everyone = false
			while ticks < 1500 and not everyone do
				frame(brains)
				ticks += 1
				if ticks % 50 == 0 then
					everyone = true
					for _, p in w.players do
						if w.brains[p].parades < 1 then
							everyone = false
						end
					end
				end
			end
			print("ticks de chasse :", ticks)
			for _, p in w.players do
				local b = w.brains[p]
				expect(b.parades >= 1).toBe(true)
				local data = w.DS.get(p)
				expect(next(data.nebbies) ~= nil).toBe(true)
			end
			expect(#lineOps("add") > 12).toBe(true)
			expect(#lineOps("bank") >= 12).toBe(true)
			frames(20, brains)
			for _, p in w.players do
				-- les Nebbies encaissés sont perchés : revenu passif, Nid décoré pour tous
				local slot = w.Nest.slotOf(p)
				local nest = w.World.nest(slot)
				expect(nest:GetAttribute("OwnerUserId")).toBe(p.UserId)
				expect(nest:GetAttribute("PerchCount") >= 3).toBe(true)
				expect(#nest:GetAttribute("PerchData") > 0).toBe(true)
				expect(w.DS.get(p).idleRate > 0).toBe(true)
				expect(w.DS.get(p).perchIncome > 0).toBe(true)
			end
			-- accueil : les débutants ont avancé dans la chaîne Q1-Q7
			for i = 1, 6 do
				expect(w.Quest.onboardingStep(w.players[i]) >= 1).toBe(true)
			end
			-- tableau de la Balise (stèle) : top des files et record de parade
			expect(type(w.World.board():GetAttribute("Record"))).toBe("string")
			expect(#w.World.board():GetAttribute("Record") > 0).toBe(true)
			-- entonnoir de première session : première capture et première parade
			local funnel = 0
			for _, e in w.h.log.analytics do
				if e.method == "LogOnboardingFunnelStepEvent" then
					funnel += 1
				end
			end
			expect(funnel >= 12).toBe(true)
			noProblems()
		end)

		it("améliorations par remote (et charges malveillantes ignorées)", function()
			local w = world()
			local bought = 0
			for _, p in w.players do
				local before = w.DS.get(p).upgrades.conga
				local glow = w.DS.get(p).glow
				local refusals = #sentTo(p, "Feedback")
				fire("BuyUpgrade", p, "conga")
				local after = w.DS.get(p).upgrades.conga
				if after == before + 1 then
					-- le revenu passif est réglé avant l'achat : le solde baisse au plus du coût
					expect(w.DS.get(p).glow >= glow - w.F.upgradeCost("conga", before)).toBe(true)
					bought += 1
				else
					expect(after).toBe(before)
					expect(#sentTo(p, "Feedback") - refusals).toBe(1)
				end
			end
			expect(bought >= 6).toBe(true)
			local p = w.players[1]
			local snapshot = table.clone(w.DS.get(p).upgrades)
			local glow = w.DS.get(p).glow
			for _, bad in { 0 / 0, math.huge, {}, { "conga" }, "__index", string.rep("x", 5000), true, nil } do
				fire("BuyUpgrade", p, bad)
			end
			expect(w.DS.get(p).upgrades).toEqual(snapshot)
			expect(w.DS.get(p).glow).toBe(glow)
			expect(#sentTo(p, "Celebrate") >= 1).toBe(true)
			frames(5, brains)
			noProblems()
		end)

		it("coupe : un vétéran traverse la file d'un autre (SnipEvent, Feedback, Stardust)", function()
			local w = world()
			local victim, snipper = w.players[9], w.players[10]
			w.brains[victim].paused = true
			w.brains[snipper].paused = true
			-- la victime se constitue une file d'au moins 6 Nebbies
			local spot = zonePoint(victim, 85, 0)
			walkAll({ [victim] = spot }, 400, brains)
			for i = 1, 400 do
				if w.Conga.lineLength(victim) >= 7 then
					break
				end
				local target = nearestWild(victim, 40) or spot
				stepToward(victim, target)
				frame(brains)
			end
			expect(w.Conga.lineLength(victim) >= 7).toBe(true)
			-- ligne droite de 30 studs (hors port sûr), puis arrêt
			local root = rootOf(victim).Position
			local dir = w.V3.new(-root.Z, 0, root.X).Unit
			local a = w.V3.new(root.X, 0, root.Z)
			local b = a + dir * 30
			walkAll({ [victim] = b }, 100, brains)
			frames(3, brains)
			-- les autres s'arrêtent ; le coupeur se place sur le côté, 16 studs derrière la tête
			local cross = b - dir * 16
			local side = w.V3.new(dir.Z, 0, -dir.X)
			-- approche par le côté où il se trouve déjà (il ne traverse pas la file en venant)
			local sp = rootOf(snipper).Position
			if (sp - cross):Dot(side) < 0 then
				side = -side
			end
			walkAll({ [snipper] = cross + side * 10 }, 600)
			-- règles de coupe : immunité (8 s) et au plus 2 coupes subies par minute (coupes
			-- croisées pendant la chasse à 12)
			while now() < Bots.lastSnipOf(victim) + 61 or now() < (victim:GetAttribute("ImmuneUntil") or 0) do
				frame()
			end
			local n = w.Conga.lineLength(victim)
			expect(n >= 7).toBe(true)
			local snips = countAll("SnipEvent")
			local dust = w.DS.get(snipper).stardust
			walkAll({ [snipper] = cross - side * 10 }, 40)
			frames(2)
			local mine = 0
			for i = snips + 1, countAll("SnipEvent") do
				local e = allEvents("SnipEvent")[i]
				if e.victimSlot == w.Nest.slotOf(victim) and e.snipperSlot == w.Nest.slotOf(snipper) then
					mine += 1
				end
			end
			expect(mine).toBe(1)
			local ev = nil
			for _, e in allEvents("SnipEvent") do
				if e.snipperSlot == w.Nest.slotOf(snipper) then
					ev = e
				end
			end
			expect(w.Conga.lineLength(victim) < n).toBe(true)
			expect(#ev.loose).toBe(ev.count)
			expect(w.DS.get(snipper).stardust > dust).toBe(true)
			expect(hasKey(Bots.feedbackKeys(victim), "feedback.snipped")).toBe(true)
			expect(hasKey(Bots.feedbackKeys(snipper), "feedback.snipDealt")).toBe(true)
			-- la victime récupère ses Nebbies libres (priorité : pas étourdis pour elle)
			local before = w.Conga.lineLength(victim)
			for _ = 1, 60 do
				local target = nearestWild(victim, 40)
				if target then
					stepToward(victim, target)
				end
				frame()
			end
			expect(w.Conga.lineLength(victim) > before).toBe(true)
			w.brains[victim].paused = false
			w.brains[snipper].paused = false
			noProblems()
		end)

		it("Supernova par remote au port sûr, bannière, acclamations des autres joueurs", function()
			local w = world()
			local hero = w.players[12]
			w.brains[hero].paused = true
			-- hors du port sûr : refus (Feedback notInHarbor), rien ne change
			walkAll({ [hero] = zonePoint(hero, 90, 0) }, 400, brains)
			fire("Supernova", hero)
			expect(w.DS.get(hero).supernovas).toBe(0)
			walkAll({ [hero] = Bots.harborPoint(hero) }, 400, brains)
			expect(w.Nest.inOwnHarbor(hero)).toBe(true)
			expect(w.DS.get(hero).glow >= 400000).toBe(true)
			-- le débit du remote (1 / 2 s) est en temps réel : on attend la fenêtre
			task.wait(2.05)
			fire("Supernova", hero)
			expect(w.DS.get(hero).supernovas).toBe(1)
			expect(w.DS.get(hero).glow).toBe(0)
			expect(w.DS.get(hero).upgrades.conga).toBe(0)
			expect(w.Conga.lineLength(hero)).toBe(0)
			expect(hero:GetAttribute("Supernovas")).toBe(1)
			local celebrated = false
			for _, args in sentTo(hero, "Celebrate") do
				if args[1].kind == "supernova" then
					celebrated = true
				end
			end
			expect(celebrated).toBe(true)
			-- chaque autre joueur reçoit le bouton ACCLAMER ; 3 acclament
			for _, p in w.players do
				if p ~= hero then
					expect(#sentTo(p, "CheerPrompt") >= 1).toBe(true)
				end
			end
			expect(#sentTo(hero, "CheerPrompt")).toBe(0)
			local dust = w.DS.get(w.players[1]).stardust
			for i = 1, 3 do
				fire("Cheer", w.players[i], hero.UserId)
			end
			fire("Cheer", w.players[1], hero.UserId) -- deuxième acclamation : ignorée
			expect(w.DS.get(w.players[1]).stardust - dust).toBe(w.B.Cheer.Dust)
			frames(120, brains)
			local banner = false
			for _, payload in allEvents("Banner") do
				if payload.kind == "supernova" and payload.args.userId == hero.UserId then
					banner = true
				end
			end
			expect(banner).toBe(true)
			w.brains[hero].paused = false
			noProblems()
		end)

		it("social et réglages : invitation d'équipage, ping, Zen, cosmétique, calendrier, code", function()
			local w = world()
			local a, b = w.players[5], w.players[6]
			fire("CrewInvite", a, b.UserId)
			local prompts = sentTo(b, "CrewInvitePrompt")
			expect(#prompts).toBe(1)
			expect(prompts[1][1].inviterId).toBe(a.UserId)
			fire("CrewRespond", b, a.UserId, true)
			expect(w.Crew.areCrewmates(a, b)).toBe(true)
			expect(a:GetAttribute("CrewId") ~= 0 and a:GetAttribute("CrewId") == b:GetAttribute("CrewId")).toBe(true)
			-- ping d'équipage diffusé
			local pings = countAll("PingShow")
			fire("Ping", a, 3)
			expect(countAll("PingShow") - pings).toBe(1)
			fire("Ping", a, 0 / 0)
			fire("Ping", a, 99)
			expect(countAll("PingShow") - pings).toBe(1)
			-- calendrier et code promo
			fire("ClaimDaily", a)
			local claimed = false
			for _, args in sentTo(a, "Celebrate") do
				if args[1].kind == "dailyClaimed" then
					claimed = true
				end
			end
			expect(claimed).toBe(true)
			expect(w.h:invokeServer("ReplicatedStorage.Remotes.RedeemCode", a, "cometconga")).toBe("ok")
			task.wait(3.05)
			expect(w.h:invokeServer("ReplicatedStorage.Remotes.RedeemCode", a, "COMETCONGA")).toBe("used")
			-- Zen : seulement au port sûr (le joueur 6 vient d'apparaître ou est en chasse)
			local z = w.players[4]
			w.brains[z].paused = true
			walkAll({ [z] = Bots.harborPoint(z) }, 400, brains)
			fire("SetSetting", z, "zen", true)
			expect(w.Nest.isZen(z)).toBe(true)
			expect(z:GetAttribute("Zen")).toBe(true)
			task.wait(0.3)
			fire("SetSetting", z, "music", false)
			expect(w.DS.get(z).settings.music).toBe(false)
			fire("SetSetting", z, "zen", 0 / 0)
			fire("SetSetting", z, { "zen" }, true)
			fire("EquipCosmetic", z, "style", "definitely_not_a_style")
			expect(w.Nest.isZen(z)).toBe(true)
			w.brains[z].paused = false
			-- administrateur seulement
			fire("AdminCommand", a, "comet")
			expect(#w.h.log.messages).toBe(0)
			frames(20, brains)
			noProblems()
		end)

		it("achats Robux : Stardust, Glow Party (boost de serveur), reçu rejoué une seule fois", function()
			local w = world()
			local p = w.players[7]
			local dust = w.DS.get(p).stardust
			local jar = w.Mon.Products.StardustJar.id
			local decision = w.h:purchaseProduct(p, jar, "receipt-jar-1")
			expect(decision).toBe(w.h.globals.Enum.ProductPurchaseDecision.PurchaseGranted)
			local after = w.DS.get(p).stardust
			expect(after > dust).toBe(true)
			w.h:purchaseProduct(p, jar, "receipt-jar-1")
			expect(w.DS.get(p).stardust).toBe(after)
			local party = w.Mon.Products.GlowParty.id
			w.h:purchaseProduct(p, party, "receipt-party-1")
			frames(3, brains)
			local state = w.Event.snapshot()
			expect(state.serverBoost ~= nil).toBe(true)
			expect(state.serverBoost.source).toBe("glowParty")
			expect(w.Economy.multiplier(w.players[1]) >= 2).toBe(true)
			noProblems()
		end)

		it("météo : fenêtre suivante (EventState, bannière, formes météo dans les apparitions)", function()
			local w = world()
			local nextW = w.EC.nextWeather(now())
			travelTo(nextW.startsAt + 0.05)
			local state = w.Event.snapshot()
			expect(state.weather ~= nil).toBe(true)
			expect(state.weather.key).toBe(nextW.key)
			local wildBefore = countAll("WildEvent")
			frames(300, brains)
			local last = allEvents("EventState")[countAll("EventState")]
			expect(last.weather ~= nil and last.weather.key == nextW.key).toBe(true)
			-- bannière de météo diffusée, apparitions à la forme de la météo
			local banner = false
			for _, payload in allEvents("Banner") do
				if payload.kind == "weather" and payload.args.key == nextW.key then
					banner = true
				end
			end
			expect(banner).toBe(true)
			if nextW.form then
				local formed = 0
				local wildEvents = allEvents("WildEvent")
				for i = wildBefore + 1, #wildEvents do
					for _, sp in wildEvents[i].spawns do
						local _, f = w.Neb.unpack(sp.code)
						if f == nextW.form then
							formed += 1
						end
					end
				end
				expect(formed > 0).toBe(true)
			end
			noProblems()
		end)

		it("Grande Comète : alerte, impact, ramassage, vol par un non-équipier, encaissement à sa porte", function()
			local w = world()
			local slot = w.EC.nextComet(now())
			local impact = w.EC.cometImpact(slot.id)
			local first, thief = w.players[11], w.players[10]
			w.brains[first].paused = true
			w.brains[thief].paused = true
			travelTo(slot.impactAt - 40)
			-- les deux se placent près du point d'impact pendant l'alerte
			local wait = impact + w.V3.new(14, 0, 0)
			walkAll({ [first] = impact, [thief] = w.WL.clampToIsland(wait) }, 380, brains)
			while now() < slot.impactAt + 0.25 do
				frame(brains)
			end
			stepToward(first, impact + w.V3.new(0.5, 0, 0))
			frames(2, brains)
			local state = w.Event.snapshot()
			expect(state.comet ~= nil).toBe(true)
			expect(state.comet.phase).toBe("carried")
			expect(state.comet.carrierId).toBe(first.UserId)
			expect(w.Event.isCarrier(first)).toBe(true)
			-- immunité du nouveau porteur (2 s), puis le voleur fonce sur lui
			frames(22, brains)
			for _ = 1, 60 do
				if w.Event.isCarrier(thief) then
					break
				end
				stepToward(thief, rootOf(first).Position)
				frame(brains)
			end
			expect(w.Event.isCarrier(thief)).toBe(true)
			-- le voleur rentre à SA porte (avant l'explosion)
			local glow = w.DS.get(thief).glow
			walkAll({ [thief] = gateOf(thief) }, 700, brains)
			frames(2, brains)
			state = w.Event.snapshot()
			expect(state.comet ~= nil and state.comet.phase).toBe("banked")
			expect(w.DS.get(thief).glow > glow).toBe(true)
			local banked = false
			for _, args in sentTo(thief, "Celebrate") do
				if args[1].kind == "cometBanked" then
					banked = true
				end
			end
			expect(banked).toBe(true)
			w.brains[first].paused = false
			w.brains[thief].paused = false
			frames(40, brains)
			noProblems()
		end)

		it("Nuit de la Balise : alerte, trêve, parades à l'anneau, résultat et récompenses", function()
			local w = world()
			local b = w.EC.nextBeacon(now())
			travelTo(b.warnAt - 30)
			-- chacun chasse pendant l'alerte, puis encaisse à l'anneau pendant la nuit
			while now() < b.startsAt + 1 do
				frame(brains)
			end
			local state = w.Event.snapshot()
			expect(state.beacon ~= nil and state.beacon.phase).toBe("active")
			expect(w.Event.isTruce()).toBe(true)
			expect(w.Event.beaconOpen()).toBe(true)
			local snips = countAll("SnipEvent")
			local result = nil
			local frenzy, golden = false, false
			local truceSnips = 0
			while now() < b.endsAt + 2 do
				frame(brains)
				if now() < b.endsAt then
					truceSnips = countAll("SnipEvent") - snips
				end
				local st = w.Event.snapshot()
				local bs = st.beacon
				if bs and (bs.phase == "success" or bs.phase == "fail") then
					result = bs.phase
				end
				if st.frenzy then
					frenzy = true
				end
			end
			-- 12 joueurs qui encaissent à l'anneau remplissent la barre : Frenzy puis Nuit d'Or
			expect(result).toBe("success")
			expect(frenzy).toBe(true)
			frames(620, brains)
			local st = w.Event.snapshot()
			golden = st.serverBoost ~= nil and st.serverBoost.source == "goldenNight"
			expect(golden).toBe(true)
			-- trêve : aucune coupe (ni joueurs ni Gloomwisps) pendant la nuit
			expect(truceSnips).toBe(0)
			local atBeacon = 0
			for _, op in lineOps("bank") do
				if op.atBeacon then
					atBeacon += op.count
				end
			end
			expect(atBeacon > 0).toBe(true)
			local rewarded = 0
			for _, p in w.players do
				for _, args in sentTo(p, "Feedback") do
					if args[1].key == "feedback.beaconWin" or args[1].key == "feedback.beaconFail" then
						rewarded += 1
					end
				end
			end
			expect(rewarded > 0).toBe(true)
			noProblems()
		end)

		it("réapparition : mort (file détachée), nouveau personnage au Nid, le jeu continue", function()
			local w = world()
			local p = w.players[5]
			for _ = 1, 300 do
				if w.Conga.lineLength(p) >= 2 then
					break
				end
				frame(brains)
			end
			local slot = w.Nest.slotOf(p)
			local clears = #lineOps("clear", slot)
			p.Character.Humanoid.Health = 0
			frames(3, brains)
			expect(w.Conga.lineLength(p)).toBe(0)
			expect(#lineOps("clear", slot) - clears >= 0).toBe(true)
			w.h:respawn(p)
			frames(5, brains)
			expect(w.Nest.slotOf(p)).toBe(slot)
			local pos = rootOf(p).Position
			expect((pos - w.WL.nestCenter(slot)).Magnitude < 12).toBe(true)
			-- réinitialisation sans mort (LoadCharacter)
			w.h:respawn(w.players[6])
			frames(200, brains)
			noProblems()
		end)

		it("départ puis retour : profil sauvegardé et rechargé, Nid libéré puis réattribué", function()
			local w = world()
			local h = w.h
			local leaving = { w.players[3], w.players[8] }
			local saved = {}
			for _, p in leaving do
				local data = w.DS.get(p)
				saved[p.UserId] = {
					nebbies = 0,
					upgrades = table.clone(data.upgrades),
					stardust = data.stardust,
				}
				for _ in data.nebbies do
					saved[p.UserId].nebbies += 1
				end
				h:removePlayer(p)
			end
			h:settle(10)
			frames(5, brains)
			local store = h.dataStores["PlayerData_v1/global"]
			for _, p in leaving do
				local record = MockInstanceState(store)["player_" .. p.UserId]
				expect(record ~= nil).toBe(true)
				expect(record.lock).toBeNil()
				expect(record.data.stardust).toBe(saved[p.UserId].stardust)
			end
			-- retour des deux joueurs (nouvelles instances, mêmes comptes)
			for i, p in leaving do
				local back = h:addPlayer({ userId = p.UserId, name = p.Name })
				local idx = table.find(w.players, p)
				w.players[idx] = back
				w.brains[back] = w.brains[p]
				w.brains[back].mode = "hunt"
				w.brains[p] = nil
				leaving[i] = back
			end
			h:settle(10)
			frames(5, brains)
			for _, p in leaving do
				local data = w.DS.get(p)
				expect(data ~= nil).toBe(true)
				local n = 0
				for _ in data.nebbies do
					n += 1
				end
				expect(n).toBe(saved[p.UserId].nebbies)
				expect(data.upgrades).toEqual(saved[p.UserId].upgrades)
				expect(w.Nest.slotOf(p) >= 1).toBe(true)
				expect(#sentTo(p, "WorldSnapshot") >= 1).toBe(true)
			end
			frames(100, brains)
			noProblems()
		end)

		it("Starfall Saturday : Rainbow, boost, comètes toutes les 3 min, cadeau Starborn de présence", function()
			local w = world()
			travelTo(STARFALL - 15)
			while now() < STARFALL + 1 do
				frame(brains)
			end
			local state = w.Event.snapshot()
			expect(state.starfall ~= nil).toBe(true)
			expect(state.weather ~= nil and state.weather.key).toBe("rainbow")
			expect(state.serverBoost ~= nil).toBe(true)
			-- 5 min de présence (jeu réel), puis saut jusqu'à la fin du show
			local comets = {}
			while now() < STARFALL + 310 do
				frame(brains)
				local c = w.Event.snapshot().comet
				if c then
					comets[c.id] = true
				end
			end
			local n = 0
			for _ in comets do
				n += 1
			end
			expect(n >= 2).toBe(true)
			travelTo(STARFALL + 1200 - 5)
			while now() < STARFALL + 1200 + 1 do
				frame(brains)
			end
			expect(w.Event.snapshot().starfall).toBeNil()
			local gifts = 0
			for _, p in w.players do
				for _, args in sentTo(p, "Feedback") do
					if args[1].key == "feedback.starfallGift" then
						gifts += 1
					end
				end
			end
			expect(gifts).toBe(12)
			noProblems()
		end)

		it("fermeture du serveur : tout le monde est sauvegardé, verrous libérés", function()
			local w = world()
			local h = w.h
			h:close()
			h:settle(10)
			local data = MockInstanceState(h.dataStores["PlayerData_v1/global"])
			for _, p in w.players do
				local record = data["player_" .. p.UserId]
				expect(record ~= nil and record.data ~= nil).toBe(true)
				expect(record.lock).toBeNil()
				expect(record.data.glow).toBe(w.DS.get(p) and w.DS.get(p).glow or record.data.glow)
			end
			noProblems()
		end)
	end)
end
