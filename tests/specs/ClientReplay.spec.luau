--!nocheck
-- ClientReplay (intégration client, docs/04 §18.3, §17.1 a-j) : un VRAI serveur (services du jeu,
-- paquet meta réel) joue une partie de 4 joueurs ; tout ce qu'il envoie au joueur 1 (remotes, attributs,
-- position, monde construit) est enregistré par tests/harness/Wire puis rejoué dans le VRAI client
-- complet (Main.client, profil console : PS5, manette seule, télé 1920 × 1080) au même instant.
-- Partie : arrivée d'un vétéran après 4 h d'absence (écran de retour), carte du choix Rush / Cozy à
-- 15:00 de jeu (le joueur choisit Rush), pressions, dalles, fusions, BOOP RUSH (sirène, clôtures,
-- un autre joueur boope un squishy du joueur 1 : carte « booped », fuite, poursuite), MEGA SQUISH
-- (alerte, atterrissage, pressions), Jelly Moon, Feedback, bannières, célébrations.
-- Vérifié :
--   * charges utiles conformes aux règles de sérialisation de Roblox (Wire), débit moyen ≤ 8 Ko/s et pic
--     < 40 Ko/s (remarque A23) ; serveur sans aucune trace ;
--   * aux points de contrôle, le miroir du client (ranchs, squishies, créatures, pièces) égale l'état
--     du serveur, sans RequestWorld ;
--   * le client affiche l'écran de retour, la carte du choix, la carte « booped » ; un robot joue le
--     joueur à la manette (✕ sur « Super ! », ✕ sur Rush) ; les intentions du client sont livrées au
--     vrai serveur sans trace ;
--   * puis, sur cet état réel, le parcours à 3 touches (TvAudit.run : croix, ✕, ○) en 1920 × 1080,
--     3840 × 2160 et 1280 × 720, en anglais puis en français : aucune faute ; puis le même client au
--     clavier et à la souris (M, raccourcis, clic, Retour arrière) ;
--   * budgets : objets d'interface ≤ 3 000 après le rejeu, ≤ 4 150 après le parcours de chaque panneau
--     (garde de la séance normale, lot I, I-35), réserves des rendus (RanchRenderer, ChaseRenderer,
--     VFXController, UI/WorldText) dans leurs quotas ;
--   * lot I, étape 6 : le jeu de lancement à la manette seule (écran Améliorations et achat au maintien,
--     mode photo et ses filtres, jumelles), 3 résolutions × 2 langues ;
--   * zéro trace côté client (aucune erreur, aucun avertissement).
local roblox = require("@lune/roblox")
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Wire = require("../harness/Wire")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000
	local RUSH_START = H0 + 300 -- un BOOP RUSH commence ici (EventClock, comme RushService.spec)
	local T0 = RUSH_START - 130 -- la carte du choix ne s'ouvre qu'au calme : ≥ 60 s avant un Rush
	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local HERO = 1

	-- =========================================================================================
	-- Outils
	-- =========================================================================================

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

	-- Taille approchée d'une valeur sur le fil (octets)
	local function bytes(v)
		local t = typeof(v)
		if t == "string" then
			return #v + 2
		elseif t == "number" then
			return 8
		elseif t == "boolean" or t == "nil" then
			return 1
		elseif t == "Vector3" then
			return 12
		elseif t == "table" then
			local n = 2
			for k, x in v do
				n += bytes(k) + bytes(x)
			end
			return n
		end
		return 8
	end

	local function sortedKeys(t)
		local out = {}
		for k in t or {} do
			table.insert(out, tostring(k))
		end
		table.sort(out)
		return out
	end

	-- =========================================================================================
	-- Partie du serveur (enregistrée une seule fois pour toute la spec)
	-- =========================================================================================

	local cached = nil

	local function squishies(n)
		local out = { { s = 1, z = 120, bf = 1 } }
		for i = 1, n do
			table.insert(out, { s = 2 + (i % 4), z = 40 + i * 3 })
		end
		return out
	end

	-- Le joueur observé : vétéran, mode pas encore choisi, 14:50 de jeu (carte du choix à 15:00),
	-- absent depuis 4 h (écran de retour)
	local function heroProfile(w)
		return Brains.profile(w, {
			coins = 4000,
			R = 1,
			squishies = squishies(7),
			playSeconds = 890,
			cardShown = false,
			edit = function(d)
				d.lastOnline = w.Clock.unix() - 4 * 3600
				d.mode.rush = false
				d.mode.chosen = false
				d.squishies["3"].s = d.squishies["2"].s -- une paire de jumeaux (fusion possible)
			end,
		})
	end

	-- Cerveau du joueur observé : presse ses squishies (debout à leur place), achète, fusionne, poursuit
	-- les créatures qu'il peut attraper (sa fuite du Rush), monte ; scripté et déterministe
	local function heroBrain(w)
		local nextAt = 0
		local n = 0
		local target = nil
		local pressUid = nil
		return function(p)
			local now = w.Clock.now()
			local slot = w.Ranch.slotOf(p)
			if slot == 0 then
				return
			end
			local root = Bots.rootOf(p)
			if root == nil then
				return
			end
			-- poursuite d'une créature proche qu'il peut attraper
			for _, spawn in w.Chase.active() do
				if not spawn.personal or spawn.ownerSlot == slot then
					local c = Brains.creaturePos(w, spawn, now)
					local d = (c - root.Position).Magnitude
					if d < 50 then
						Bots.stepToward(p, Bots.ground(c.X, c.Z))
						if d < 5 then
							Bots.fire("Catch", p, spawn.id, now)
						end
						return
					end
				end
			end
			if target and not Bots.stepToward(p, target) then
				return
			end
			target = nil
			if pressUid then
				-- arrivé à la place du squishy choisi : □
				Bots.fire("Press", p, pressUid, now)
				pressUid = nil
				nextAt = now + 0.6
				return
			end
			if now < nextAt then
				return
			end
			nextAt = now + 0.6
			n += 1
			local pens = Brains.uidsAt(w, p, "pen")
			table.sort(pens, function(a, b)
				if #a ~= #b then
					return #a < #b
				end
				return a < b
			end)
			local k = n % 7
			if k <= 3 and #pens > 0 then
				-- va presser le squishy n° i (place d'enclos de rang i)
				local i = (n % #pens) + 1
				local place = w.WL.penSlot(slot, i)
				target = Bots.ground(place.X + 3, place.Z)
				pressUid = pens[i]
			elseif k == 4 then
				Bots.fire("BuyTile", p, ({ "snack", "decor", "pens", "cozyBed" })[(n % 4) + 1])
			elseif k == 5 then
				Bots.fire("FuseAll", p)
			else
				Bots.fire("ClaimObjective", p, 1)
			end
		end
	end

	local function session()
		if cached then
			return cached
		end
		local w = Brains.boot(Harness, { t0 = T0, stubMeta = false })
		local EventClock = w.EventClock
		-- deux joueurs déjà là ; le boopeur en mode Rush
		local booper = Brains.join(w, 2, {
			name = "Mira",
			profile = Brains.profile(w, { rush = true, squishies = squishies(3), coins = 900 }),
		})
		local other = Brains.join(w, 3, {
			name = "Noa",
			profile = Brains.profile(w, { rush = false, squishies = squishies(4), coins = 200 }),
		})
		Brains.frames(w, 10)
		local rec = Wire.record(w.h, {
			userId = HERO,
			Clock = w.Clock,
			world = "Wobbleton",
			remotes = { "Feedback", "Banner", "Celebrate" },
		})
		local baseFrame = w.onFrame
		w.onFrame = function()
			baseFrame()
			rec:frame()
		end
		local hero = Brains.join(w, HERO, { name = "Hero", profile = heroProfile(w) })
		local fourth = Brains.join(w, 4, {
			name = "Zed",
			profile = Brains.profile(w, { rush = true, squishies = squishies(2) }),
		})
		Bots.setBrain(hero, heroBrain(w))
		Bots.setBrain(other, Brains.player(w, 3))
		Bots.setBrain(fourth, Brains.player(w, 4))
		local heroSlot = w.Ranch.slotOf(hero)

		-- Point de contrôle : état du serveur vu par le joueur observé (comparé au miroir du client)
		local function checkpoint(label)
			Brains.frames(w, 1)
			w.h:settle(2)
			local cp = {
				kind = "check",
				t = w.Clock.now(),
				label = label,
				ranches = {},
				squishies = {},
				creatures = {},
				coins = w.DS.get(hero).coins,
			}
			for slot = 1, 16 do
				local pub = w.Ranch.publicOf(slot)
				local owner = w.Ranch.playerAt(slot)
				if pub and owner then
					cp.ranches[slot] = deepCopy(pub)
					local set = {}
					for uid, r in w.DS.get(owner).squishies do
						if r.at == "pen" or r.at == "pool" then
							set[uid] = { s = r.s, at = r.at }
						end
					end
					cp.squishies[slot] = set
				end
			end
			for _, spawn in w.Chase.active() do
				if (not spawn.personal or spawn.ownerSlot == heroSlot) and cp.t - spawn.t0 >= 0.6 then
					cp.creatures[spawn.id] = spawn.kind
				end
			end
			table.insert(rec.events, cp)
		end

		local stats = { heroSlot = heroSlot, t0 = w.Clock.now() }
		-- arrivée, écran de retour, carte du choix (15:00 de jeu) ; le joueur choisit Rush
		Brains.frames(w, 40, Bots.brains)
		checkpoint("arrivée")
		for _ = 1, 30 do
			if #w.h:sentTo(hero, "ModePrompt") > 0 then
				break
			end
			Brains.frames(w, 10, Bots.brains)
		end
		stats.modePrompt = #w.h:sentTo(hero, "ModePrompt")
		-- la carte attend le calme (immobile dans son ranch, aucun Rush dans la minute) : le joueur
		-- s'arrête, lit la carte puis choisit Rush (le client rejoué fait de même à la manette)
		Bots.setBrain(hero, nil)
		Brains.frames(w, 100, Bots.brains)
		Bots.setBrain(hero, heroBrain(w))
		w.h:fireServer(REMOTES .. "UiSeen", hero, "modeCard")
		w.h:fireServer(REMOTES .. "SetMode", hero, true)
		Brains.frames(w, 20, Bots.brains)
		-- quelques refus (Feedback) : achat trop cher depuis le panneau, rien à fusionner
		w.h:fireServer(REMOTES .. "BuyTile", hero, "pens")
		w.h:fireServer(REMOTES .. "FuseAll", hero)
		w.h:fireServer(REMOTES .. "Emote", hero, 1)
		-- jusqu'au BOOP RUSH (sirène 10 s avant)
		while w.Clock.now() < RUSH_START + 1 do
			Brains.frames(w, 10, Bots.brains)
		end
		checkpoint("rush")
		-- le boopeur se poste devant la clôture du joueur observé et boope le premier squishy montré
		local uids, reason = w.Ranch.fenceOf(heroSlot)
		stats.fence = #uids
		stats.fenceReason = reason
		if #uids > 0 then
			local lp = w.WL.fencePointsLocal()[1]
			local q = w.WL.toWorld(heroSlot, w.V3.new(lp.X, 0, -2))
			Bots.setBrain(booper, nil)
			Bots.place(booper, Bots.ground(q.X, q.Z))
			-- le propriétaire s'éloigne de sa clôture (sinon le maintien dure 5 s)
			Bots.setBrain(hero, nil)
			Bots.place(hero, Brains.atRanch(w, hero, 0, 60))
			Brains.frames(w, 2)
			w.h:fireServer(REMOTES .. "BoopHold", booper, HERO, uids[1], true)
			Brains.frames(w, 35, Bots.brains)
			Bots.setBrain(hero, heroBrain(w))
		end
		Brains.frames(w, 150, Bots.brains)
		checkpoint("poursuite")
		while w.Clock.now() < EventClock.rush(RUSH_START).endsAt + 2 do
			Brains.frames(w, 10, Bots.brains)
		end
		checkpoint("fin du Rush")
		-- MEGA SQUISH : alerte, atterrissage, pressions de tous près du pad
		local mega = EventClock.mega(w.Clock.now())
		Bots.travelTo(mega.warnAt - 1)
		Brains.frames(w, 20, Bots.brains)
		Bots.travelTo(mega.landsAt - 1)
		Bots.setBrain(hero, nil)
		local pad = w.WL.plaza("megaPad")
		for i, p in { hero, booper, other, fourth } do
			Bots.setBrain(p, nil)
			Bots.place(p, Bots.ground(pad.X + 4 * i - 10, pad.Z + 6))
		end
		while w.Clock.now() < mega.endsAt do
			for _, p in { hero, booper, other, fourth } do
				Bots.fire("MegaPress", p, w.Clock.now())
			end
			Brains.frames(w, 5)
		end
		while w.Clock.now() < mega.burstEndsAt + 1 do
			Brains.frames(w, 10)
		end
		checkpoint("MEGA")
		-- Jelly Moon
		Bots.setBrain(hero, heroBrain(w))
		Bots.setBrain(other, Brains.player(w, 3))
		local moon = EventClock.moon(w.Clock.now())
		if moon.startsAt > w.Clock.now() then
			Bots.travelTo(moon.startsAt - 1)
		end
		Brains.frames(w, 40, Bots.brains)
		checkpoint("Jelly Moon")
		rec:stop()
		stats.t1 = w.Clock.now()
		stats.serverProblems = Brains.problems(w)
		stats.celebrations = {}
		for _, e in rec.events do
			if e.kind == "remote" and e.remote == "Celebrate" then
				local kind = e.args[1] and e.args[1].kind
				stats.celebrations[kind] = (stats.celebrations[kind] or 0) + 1
			end
		end
		cached = { w = w, rec = rec, stats = stats, server = Wire.saveContext() }
		return cached
	end

	-- =========================================================================================
	-- Client
	-- =========================================================================================

	local function mod(c, path)
		return c:require(CLIENT .. path)
	end

	-- Robot du joueur à la manette pendant le rejeu : ✕ sur « Super ! » de l'écran de retour, ✕ sur
	-- Rush sur la carte du choix ; carte « booped » : ✕ (Continuer)
	local function padBot(c, seen)
		local FocusGuard = mod(c, "UI.FocusGuard")
		local Cards = mod(c, "UI.Cards")
		local openedAt = {}
		return function(now)
			local top = FocusGuard.top()
			local name = if top then top.name else ""
			if name ~= "" and openedAt[name] == nil then
				openedAt[name] = now
				seen.windows[name] = true
			end
			for key in openedAt do
				if key ~= name and not FocusGuard.isOpen(key) then
					openedAt[key] = nil
				end
			end
			local card = Cards.current()
			if card then
				seen.cards[card.kind] = true
			end
			for _, pc in Cards.pending() do
				seen.pending[pc.kind] = true
			end
			seen.maxQueued = math.max(seen.maxQueued, Cards.queued())
			if name == "" or now - openedAt[name] < 1.5 then
				return
			end
			if name == "return" then
				Gamepad.tap(c, Enum.KeyCode.ButtonA)
			elseif card and card.kind == "mode" then
				local buttons = Cards.buttons()
				if buttons[1] then
					c.game.GuiService.SelectedObject = buttons[1] -- croix → Rush
					c:settle(1)
					Gamepad.tap(c, Enum.KeyCode.ButtonA)
				end
			elseif string.sub(name, 1, 5) == "card:" then
				Gamepad.tap(c, Enum.KeyCode.ButtonA)
			end
			openedAt[name] = now
		end
	end

	-- Compare le miroir du client à un point de contrôle du serveur ; rend la liste des écarts
	local compared = { ranches = 0, creatures = 0 }
	local function compare(c, cp)
		local issues = {}
		local WSC = mod(c, "Controllers.WorldStateController")
		local State = mod(c, "Controllers.StateController")
		local tag = `[{cp.label}] `
		if State.get("coins") ~= cp.coins then
			table.insert(issues, tag .. `pièces {tostring(State.get("coins"))} ≠ {tostring(cp.coins)}`)
		end
		for slot, pub in cp.ranches do
			compared.ranches += 1
			local mine = WSC.ranch(slot)
			if mine == nil then
				table.insert(issues, tag .. `ranch {slot} absent du miroir`)
			else
				for k, v in pub do
					local got = mine[k]
					local same = if type(v) == "table"
						then table.concat(sortedKeys(v), ",") == table.concat(sortedKeys(got), ",")
						else got == v
					if not same then
						table.insert(issues, tag .. `ranch {slot}.{k} : {tostring(got)} ≠ {tostring(v)}`)
					end
				end
			end
			local list = WSC.squishies(slot) or {}
			local want = cp.squishies[slot] or {}
			local a, b = table.concat(sortedKeys(list), ","), table.concat(sortedKeys(want), ",")
			if a ~= b then
				table.insert(issues, tag .. `squishies du ranch {slot} : [{a}] ≠ [{b}]`)
			else
				for uid, r in want do
					if list[uid].s ~= r.s or list[uid].at ~= r.at then
						table.insert(issues, tag .. `squishy {slot}/{uid} : s/at différents`)
					end
				end
			end
		end
		local mirror = WSC.creatures()
		for id in cp.creatures do
			compared.creatures += 1
			if mirror[id] == nil then
				table.insert(issues, tag .. `créature {id} absente du miroir`)
			end
		end
		return issues
	end

	-- Rejoue la partie enregistrée dans un client complet ; rend le client et ce qui a été vu
	local function replayed(opts)
		opts = opts or {}
		local s = opts.session or session()
		local c = Harness.new({ mode = "client", console = opts.console ~= false })
		c:createRemotes()
		Wire.installWorld(s.rec, c)
		local Clock = c:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(s.rec.events[1].t - 0.1)
		c:boot()
		c:settle(3)
		local seen = {
			windows = {},
			cards = {},
			pending = {},
			maxQueued = 0,
			issues = {},
			requestWorld = 0,
			checks = 0,
		}
		local bot = padBot(c, seen)
		Wire.replay(s.rec, c, {
			Clock = Clock,
			frameDt = 0.1,
			onFrame = function(now)
				if opts.bot ~= false then
					bot(now)
				end
				if opts.watch then
					opts.watch(c, now)
				end
			end,
			onEvent = function(e)
				if e.kind == "check" then
					seen.checks += 1
					c:settle(2)
					for _, issue in compare(c, e) do
						table.insert(seen.issues, issue)
					end
				end
			end,
		})
		c:step(0.1, 5)
		c:settle(3)
		for _, ev in c.log.serverEvents do
			if ev.remote == "RequestWorld" then
				seen.requestWorld += 1
			end
		end
		return c, seen, s
	end

	local function clean(c)
		expect(table.concat(c.errors, "\n")).toBe("")
		expect(table.concat(c:warnings(), "\n")).toBe("")
	end

	-- =========================================================================================
	describe("ClientReplay › partie du vrai serveur", function()
		it(
			"charges conformes, débit ≤ 8 Ko/s (pic < 40 Ko/s), serveur sans trace, moments couverts",
			function()
				local s = session()
				expect(table.concat(s.rec.problems, "\n")).toBe("")
				expect(table.concat(s.stats.serverProblems, "\n")).toBe("")
				-- débit des charges enregistrées pour le joueur observé
				local perSecond, total = {}, 0
				for _, e in s.rec.events do
					if e.kind == "remote" then
						local size = 0
						for i = 1, e.args.n do
							size += bytes(e.args[i])
						end
						local sec = math.floor(e.t - s.stats.t0)
						perSecond[sec] = (perSecond[sec] or 0) + size
						total += size
					end
				end
				local seconds, peak = 0, 0
				for _, b in perSecond do
					seconds += 1
					peak = math.max(peak, b)
				end
				local avg = total / math.max(1, s.stats.t1 - s.stats.t0)
				expect({ avg = avg <= 8 * 1024, peak = peak < 40 * 1024 }).toEqual({ avg = true, peak = true })
				-- tous les moments de la partie ont bien été joués par le serveur
				for _, remote in
					{
						"DataSnapshot",
						"DataPatch",
						"RanchSnapshot",
						"RanchPatch",
						"EventState",
						"ChaseEvent",
						"Fence",
						"BoopState",
						"ModePrompt",
						"Feedback",
						"Celebrate",
						"MegaBeat",
					}
				do
					expect({ remote = remote, sent = s.rec:count(remote) > 0 }).toEqual({
						remote = remote,
						sent = true,
					})
				end
				for _, kind in { "return", "press", "booped" } do
					expect({ kind = kind, sent = (s.stats.celebrations[kind] or 0) > 0 }).toEqual({
						kind = kind,
						sent = true,
					})
				end
				expect(s.stats.fenceReason).toBe("rush")
			end
		)
	end)

	describe("ClientReplay › rejeu dans le client console", function()
		it(
			"miroir = serveur aux points de contrôle, sans RequestWorld ; écran de retour et cartes ; zéro trace",
			function()
				local c, seen = replayed()
				expect(seen.checks >= 5).toBe(true)
				-- les points de contrôle comparent vraiment quelque chose (4 ranchs, des créatures)
				expect(compared.ranches >= 4 * 5).toBe(true)
				expect(compared.creatures >= 1).toBe(true)
				expect(table.concat(seen.issues, "\n")).toBe("")
				expect(seen.requestWorld).toBe(0)
				expect(seen.windows["return"]).toBe(true)
				expect(seen.cards.mode).toBe(true)
				expect(seen.cards.booped).toBe(true)
				-- le choix fait à la manette part au serveur
				local modes = TvAudit.sent(c, "SetMode")
				expect(#modes >= 1).toBe(true)
				expect(modes[#modes][1]).toBe(true)
				-- budgets (remarque A23, INT-CW-10)
				expect(TvAudit.guiObjects(c) <= 3000).toBe(true)
				local Q = mod(c, "Controllers.QualityController").budgets()
				local rr = mod(c, "Controllers.RanchRenderer").stats()
				expect(rr.parts <= 2500).toBe(true)
				expect(rr.fullRate <= Q.animated).toBe(true)
				expect(rr.lights <= Q.lightQuota.squishies).toBe(true)
				local cr = mod(c, "Controllers.ChaseRenderer").stats()
				expect(cr.highlights <= Q.highlightQuota.chase).toBe(true)
				expect(cr.particles <= Q.particleQuota.chase).toBe(true)
				local vfx = mod(c, "Controllers.VFXController").stats()
				expect(vfx.particles <= Q.particleQuota.vfx).toBe(true)
				expect(vfx.blobs <= 120).toBe(true)
				expect(vfx.texts <= 20).toBe(true)
				local wt = mod(c, "UI.WorldText").stats()
				expect(type(wt) == "table").toBe(true)
				-- sans fenêtre : la main est au jeu
				expect(TvAudit.toGame(c)).toBe(true)
				clean(c)
			end
		)

		it("les intentions produites par le client sont livrées au vrai serveur sans trace", function()
			local c, _, s = replayed()
			local sent = {}
			for _, ev in c.log.serverEvents do
				table.insert(sent, ev)
			end
			expect(#sent > 0).toBe(true)
			local clientCtx = Wire.saveContext()
			Wire.restoreContext(s.server)
			local w = s.w
			local hero = w.h.game.Players:GetPlayerByUserId(HERO)
			for _, ev in sent do
				w.h:fireServer(REMOTES .. ev.remote, hero, table.unpack(ev.args, 1, ev.args.n))
				w.h:settle(1)
			end
			Brains.frames(w, 20)
			expect(table.concat(Brains.problems(w), "\n")).toBe("")
			Wire.restoreContext(clientCtx)
			clean(c)
		end)
	end)

	-- Variante : arrivée en plein BOOP RUSH, puis interrupteur MegaSquish coupé en direct avant
	-- l'alerte du MEGA suivant (docs/04 §18.3, §10.4)
	local function lateSession()
		local w = Brains.boot(Harness, { t0 = RUSH_START + 20, stubMeta = false })
		local booper = Brains.join(w, 2, {
			name = "Mira",
			profile = Brains.profile(w, { rush = true, squishies = squishies(3) }),
		})
		Bots.setBrain(booper, Brains.player(w, 2))
		Brains.frames(w, 10, Bots.brains)
		local rec = Wire.record(w.h, { userId = HERO, Clock = w.Clock, world = "Wobbleton" })
		local baseFrame = w.onFrame
		w.onFrame = function()
			baseFrame()
			rec:frame()
		end
		local hero = Brains.join(w, HERO, {
			name = "Hero",
			profile = Brains.profile(w, { rush = true, squishies = squishies(5), coins = 1000 }),
		})
		Bots.setBrain(hero, heroBrain(w))
		Brains.frames(w, 80, Bots.brains)
		local stats = { rushAtJoin = w.Event.rushActive() }
		-- interrupteur coupé en direct (LiveOps) ; puis le MEGA suivant passe sans rien montrer
		w.Features.set("MegaSquish", false)
		Brains.frames(w, 20, Bots.brains)
		local mega = w.EventClock.mega(w.Clock.now() + 60)
		if mega.warnAt - 2 > w.Clock.now() then
			Bots.travelTo(mega.warnAt - 2)
		end
		Brains.frames(w, 30, Bots.brains)
		if mega.landsAt - 1 > w.Clock.now() then
			Bots.travelTo(mega.landsAt - 1)
		end
		Brains.frames(w, 40, Bots.brains)
		rec:stop()
		stats.problems = Brains.problems(w)
		stats.featureOff = false
		for _, e in rec.events do
			if e.kind == "remote" and e.remote == "EventState" then
				local f = e.args[1] and e.args[1].features
				if f and f.megaSquish == false then
					stats.featureOff = true
				end
			end
		end
		local out = { w = w, rec = rec, stats = stats, server = Wire.saveContext() }
		w.Features.reset()
		return out
	end

	describe("ClientReplay › arrivée en cours de partie et interrupteur coupé en direct", function()
		it(
			"arrivée en plein Rush : ciel du Rush ; MegaSquish coupé : ni bannière ni jauge MEGA",
			function()
				local late = lateSession()
				expect(table.concat(late.rec.problems, "\n")).toBe("")
				expect(table.concat(late.stats.problems, "\n")).toBe("")
				expect(late.stats.rushAtJoin).toBe(true)
				expect(late.stats.featureOff).toBe(true)
				local saw = { rushSky = false, megaBanner = false, megaBar = false }
				local c = replayed({
					session = late,
					watch = function(c2)
						local LC = mod(c2, "Controllers.LightingController")
						local Banners = mod(c2, "UI.Banners")
						local HUD = mod(c2, "UI.HUD")
						local ev = mod(c2, "Controllers.WorldStateController").event()
						local off = ev ~= nil and ev.features ~= nil and ev.features.megaSquish == false
						if LC.current() == "rush" then
							saw.rushSky = true
						end
						local b = Banners.current()
						if off and b and b.kind == "megaWarn" then
							saw.megaBanner = true
						end
						if off and HUD.visible("megaBar") then
							saw.megaBar = true
						end
					end,
				})
				expect(saw).toEqual({ rushSky = true, megaBanner = false, megaBar = false })
				clean(c)
			end
		)
	end)

	describe("ClientReplay › parcours à 3 touches sur la partie rejouée", function()
		it("1080p, 4K, 720p × EN, FR : aucune faute ; ○ rend toujours la main au jeu", function()
			local c = replayed()
			c:fireClient(REMOTES .. "DiagnosticsSnapshot", { tab = 0 })
			c:settle(1)
			local report = TvAudit.run(c, {
				resolutions = { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) },
				langs = { "en", "fr" },
			})
			expect(table.concat(report.issues, "\n")).toBe("")
			for _, id in { "menu", "panel:Ranch", "panel:Squishydex", "panel:Objectives", "panel:Settings" } do
				local reached = false
				for screen in report.screens do
					if screen == id or string.sub(screen, 1, #id + 1) == id .. "/" then
						reached = true
					end
				end
				expect({ screen = id, reached = reached }).toEqual({ screen = id, reached = true })
			end
			expect(TvAudit.screenId(c)).toBe("game")
			-- chaque panneau du rail ouvert une fois : garde de la séance normale (lot I, étape 4, I-35 :
			-- 4 150, GDD §12.9, la même que Layout_panels › SESSION_GUARD ; 3 000 avant la décision)
			expect(TvAudit.guiObjects(c) <= 4150).toBe(true)
			clean(c)
		end)
	end)

	-- Lot I, étape 6 (plan I T4) : le jeu de lancement (les 23 interrupteurs v2.0 ouverts) à la manette
	-- seule, sur l'état réel rejoué : écran Améliorations (△, croix jusqu'à l'entrée, ✕ ; achat au
	-- maintien de ✕ 0,6 s sur la carte choisie), mode photo (Réglages → « Mode photo », □ change le
	-- filtre, ○ sort), jumelles (□ devant le portail d'un voisin, △ ouvre le menu par-dessus, ○ le ferme,
	-- ○ ferme les jumelles) ; 1080p, 4K, 720p × EN, FR ; chaque écran audité (sélection, chevauchements,
	-- textes, glyphes PlayStation, zone sûre) ; ○ rend toujours la main au jeu ; zéro trace.
	describe(
		"ClientReplay › jeu de lancement à la manette (Améliorations, mode photo, jumelles)",
		function()
			it(
				"1080p, 4K, 720p × EN, FR : achat au maintien, filtres du mode photo, jumelles ; aucune faute",
				function()
					local c = replayed()
					local PC = mod(c, "UI.PanelController")
					local FG = mod(c, "UI.FocusGuard")
					local Up = mod(c, "UI.Panels.Upgrades")
					local Cam = mod(c, "Controllers.CameraController")
					local Hud = mod(c, "UI.PhotoHud")
					local Bino = mod(c, "UI.Binoculars")
					local WSC = mod(c, "Controllers.WorldStateController")
					local WL = c:require("ReplicatedStorage.Shared.Logic.WorldLayout")
					local K = Enum.KeyCode
					local issues = {}
					local function sel()
						return c.game.GuiService.SelectedObject
					end
					local function tap(key)
						TvAudit.tick(c, 0.5)
						Gamepad.tap(c, key)
						TvAudit.tick(c, 0.5)
					end
					local function audit(label)
						Layout.apply(c)
						for _, issue in TvAudit.check(c, label, nil) do
							table.insert(issues, issue)
						end
					end
					local function toEntry(name)
						local target = PC.entryButton(name)
						if target == nil then
							return false
						end
						for _, key in { K.DPadDown, K.DPadUp } do
							for _ = 1, 12 do
								if sel() == target then
									return true
								end
								tap(key)
							end
						end
						return sel() == target
					end
					-- portail d'un voisin dont le ranch porte la preuve v2 (BestR) : vue des jumelles
					local function neighbourSlot()
						local mine = WSC.mySlot()
						for slot = 1, 16 do
							if slot ~= mine and WSC.ranch(slot) ~= nil then
								return slot
							end
						end
						return nil
					end
					expect(PC.available("Upgrades")).toBe(true)
					local bought, filters, binoculars = 0, 0, 0
					for _, res in { Vector2.new(1920, 1080), Vector2.new(3840, 2160), Vector2.new(1280, 720) } do
						TvAudit.setResolution(c, res)
						for _, lang in { "en", "fr" } do
							TvAudit.setLanguage(c, lang)
							local label = `[manette {res.X}x{res.Y} {lang}] `
							expect(TvAudit.toGame(c)).toBe(true)
							-- ------------------------------------------------ écran Améliorations
							tap(K.ButtonY)
							expect(PC.menuOpen()).toBe(true)
							expect({ label = label, entry = toEntry("Upgrades") }).toEqual({
								label = label,
								entry = true,
							})
							tap(K.ButtonA)
							expect({ label = label, open = Up.isOpen() }).toEqual({
								label = label,
								open = true,
							})
							audit(label .. "[Upgrades] ")
							local card = sel()
							local before = #TvAudit.sent(c, "BuyUpgrade")
							local ready = card ~= nil and card:GetAttribute("State") == "ready"
							Gamepad.press(c, K.ButtonA)
							TvAudit.tick(c, 0.7)
							Gamepad.release(c, K.ButtonA)
							TvAudit.tick(c, 0.5)
							local after = #TvAudit.sent(c, "BuyUpgrade")
							if ready then
								expect({ label = label, sent = after - before }).toEqual({
									label = label,
									sent = 1,
								})
								bought += 1
							else
								expect({ label = label, sent = after - before }).toEqual({
									label = label,
									sent = 0,
								})
							end
							-- les onglets à L1 / R1 (Plopettes verrouillées comprises), chacun audité
							for _ = 1, #Up.tabs() do
								tap(K.ButtonR1)
								audit(label .. `[Upgrades/{Up.currentTab()}] `)
							end
							expect(TvAudit.toGame(c)).toBe(true)
							expect(Up.isOpen()).toBe(false)
							-- ------------------------------------------------ mode photo
							tap(K.ButtonY)
							expect(toEntry("Settings")).toBe(true)
							tap(K.ButtonA)
							expect(PC.current()).toBe("Settings")
							local function onPhoto()
								local cur = sel()
								local row = cur and cur.Parent
								local title = row and row:FindFirstChild("Title")
								return cur ~= nil
									and cur.Name == "Choice"
									and title ~= nil
									and title.Text
										== (if lang == "fr" then "Mode photo" else "Photo mode")
							end
							for _ = 1, 24 do
								if onPhoto() then
									break
								end
								tap(K.DPadDown)
							end
							expect({ label = label, row = onPhoto() }).toEqual({ label = label, row = true })
							tap(K.ButtonA)
							expect({ label = label, photo = Cam.photoOn() }).toEqual({
								label = label,
								photo = true,
							})
							audit(label .. "[photo] ")
							local seenFilters = { [Hud.filter()] = true }
							for _ = 1, 4 do
								tap(K.ButtonX)
								seenFilters[Hud.filter()] = true
								expect(Cam.photoOn()).toBe(true)
							end
							local n = 0
							for _ in seenFilters do
								n += 1
							end
							expect({ label = label, filters = n }).toEqual({ label = label, filters = 4 })
							filters += n
							tap(K.ButtonB)
							TvAudit.tick(c, 1)
							expect({ label = label, photo = Cam.photoOn() }).toEqual({
								label = label,
								photo = false,
							})
							-- commandes du mode photo déliées à la sortie (actions de sa fenêtre seulement)
							for _, name in { "PhotoMove", "PhotoTurn", "PhotoZoom", "PhotoFilter" } do
								expect({ label = label, bound = c.actionBindings[name] ~= nil }).toEqual({
									label = label,
									bound = false,
								})
							end
							expect(TvAudit.toGame(c)).toBe(true)
							-- ------------------------------------------------ jumelles
							local slot = neighbourSlot()
							expect(slot ~= nil).toBe(true)
							c:moveTo(c.localPlayer, WL.gateOutside(slot))
							TvAudit.tick(c, 0.5)
							tap(K.ButtonX)
							expect({ label = label, open = Bino.isOpen() }).toEqual({
								label = label,
								open = true,
							})
							audit(label .. "[binoculars] ")
							tap(K.ButtonY)
							expect(PC.menuOpen()).toBe(true)
							expect(FG.names()).toEqual({ "binoculars", "menu" })
							tap(K.ButtonB)
							expect(PC.menuOpen()).toBe(false)
							expect(Bino.isOpen()).toBe(true)
							tap(K.ButtonB)
							expect(Bino.isOpen()).toBe(false)
							expect(FG.anyOpen()).toBe(false)
							binoculars += 1
							-- retour dans son ranch pour la suite
							c:moveTo(c.localPlayer, WL.toWorld(WSC.mySlot(), Vector3.new(0, 0, 30)))
							TvAudit.tick(c, 0.5)
						end
					end
					expect(table.concat(issues, "\n")).toBe("")
					expect(binoculars).toBe(6)
					expect(filters).toBe(24)
					expect(TvAudit.screenId(c)).toBe("game")
					print(
						`  ClientReplay manette v2.0 : {bought} achats au maintien, {filters} filtres vus, {binoculars} vues des jumelles`
					)
					clean(c)
				end
			)
		end
	)

	describe("ClientReplay › clavier et souris (PC, second)", function()
		-- Touche du clavier : InputBegan / InputEnded (dernier type d'entrée : clavier), puis CAS
		local function key(c, keyCode)
			local uis = c.game.UserInputService
			if c.lastInputType ~= Enum.UserInputType.Keyboard then
				c.lastInputType = Enum.UserInputType.Keyboard
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
			end
			for _, state in { Enum.UserInputState.Begin, Enum.UserInputState.End } do
				local input = {
					KeyCode = keyCode,
					UserInputType = Enum.UserInputType.Keyboard,
					UserInputState = state,
					Position = Vector3.zero,
					Delta = Vector3.zero,
				}
				if state == Enum.UserInputState.Begin then
					uis.InputBegan:Fire(input, false)
				else
					uis.InputEnded:Fire(input, false)
				end
				Gamepad.dispatch(c, keyCode, state, input)
				c:settle(1)
			end
			TvAudit.tick(c, 0.5)
		end
		-- Clic de souris sur un bouton visible
		local function click(c, button)
			local uis = c.game.UserInputService
			if c.lastInputType ~= Enum.UserInputType.MouseButton1 then
				c.lastInputType = Enum.UserInputType.MouseButton1
				uis.LastInputTypeChanged:Fire(Enum.UserInputType.MouseButton1)
			end
			button.Activated:Fire({
				UserInputType = Enum.UserInputType.MouseButton1,
				UserInputState = Enum.UserInputState.End,
				Position = Vector3.zero,
				Delta = Vector3.zero,
			}, 1)
			c:settle(1)
			TvAudit.tick(c, 0.5)
		end

		local function audit(c, label, issues)
			Layout.apply(c)
			for _, issue in TvAudit.check(c, label, nil) do
				-- à la souris, aucune sélection n'est exigée (curseur libre)
				if not string.find(issue, "sélection vide", 1, true) then
					table.insert(issues, issue)
				end
			end
		end

		it(
			"M ouvre le menu, clic sur chaque entrée, Retour arrière revient ; raccourcis G C J L P ; aucune faute",
			function()
				local c = replayed({ console = false })
				local FocusGuard = mod(c, "UI.FocusGuard")
				local PanelController = mod(c, "UI.PanelController")
				local issues = {}
				for _, res in { Vector2.new(1920, 1080), Vector2.new(1280, 720) } do
					TvAudit.setResolution(c, res)
					for _, lang in { "en", "fr" } do
						TvAudit.setLanguage(c, lang)
						local label = `[KBM {res.X}x{res.Y} {lang}] `
						expect(TvAudit.toGame(c)).toBe(true)
						key(c, Enum.KeyCode.M)
						expect(FocusGuard.isOpen("menu")).toBe(true)
						audit(c, label .. "[menu] ", issues)
						local menu = FocusGuard.top()
						local entries = {}
						for _, d in menu.root:GetDescendants() do
							if
								d:IsA("GuiButton")
								and d:GetAttribute("TvNav") == true
								and Layout.visible(d)
							then
								table.insert(entries, d)
							end
						end
						table.sort(entries, function(a, b)
							return Layout.name(a) < Layout.name(b)
						end)
						expect(#entries >= 5).toBe(true)
						for _, entry in entries do
							if not FocusGuard.isOpen("menu") then
								key(c, Enum.KeyCode.M)
							end
							click(c, entry)
							local top = FocusGuard.top()
							local name = if top then top.name else "game"
							audit(c, label .. `[{name}] `, issues)
							key(c, Enum.KeyCode.Backspace)
							if FocusGuard.top() and FocusGuard.top().name == name then
								table.insert(issues, label .. `Retour arrière ne ferme pas {name}`)
							end
						end
						expect(TvAudit.toGame(c)).toBe(true)
						-- raccourcis du clavier depuis le jeu
						for _, k in
							{ Enum.KeyCode.G, Enum.KeyCode.C, Enum.KeyCode.J, Enum.KeyCode.L, Enum.KeyCode.P }
						do
							key(c, k)
							local top = FocusGuard.top()
							if top == nil then
								table.insert(issues, label .. `raccourci {k.Name} sans effet`)
							else
								audit(c, label .. `[{top.name}] `, issues)
							end
							expect(TvAudit.toGame(c)).toBe(true)
						end
					end
				end
				expect(table.concat(issues, "\n")).toBe("")
				expect(PanelController.menuOpen()).toBe(false)
				clean(c)
			end
		)
	end)
end
