--!nocheck
-- QuestService (paquet meta, docs/04 §11.7, §18.2) : accueil sans blocage (étapes, Plop de départ,
-- naissances scriptées jamais rejouées, consigne fermée à 90 s, étape 10 par UiSeen), objectifs (jour 1,
-- progression, réclamation sans boost, relance, Goutte chanceuse, minuit en session), bol en 2 s
-- (HoldState, une fois par jour, sortie de zone, boost de 5 min), Squishydex (tampons, dex.fam pour
-- toujours, espèce future ignorée), FriendsChanged, carte « Plop a sommeil », départ (compteurs de session
-- dans la sauvegarde), états minutés jamais au-delà de leur délai, zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function world()
		local w = Brains.boot(Harness, { t0 = T0, stubMeta = false })
		w.Q = w.h:require(S .. "QuestService")
		w.WL = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Quests = w.h:require("ReplicatedStorage.Shared.Config.Quests")
		return w
	end

	local function newcomer(w, id)
		return Brains.join(w, id or 1, { profile = Bots.profile(w, {}) })
	end

	local function veteran(w, id, edit)
		return Brains.join(w, id or 1, {
			profile = Brains.profile(
				w,
				{ squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 } }, edit = edit }
			),
		})
	end

	local function data(w, p)
		return w.DS.get(p)
	end

	local function celebrations(w, p, kind)
		return Bots.celebrations(p, kind)
	end

	local function setPlay(w, p, seconds)
		data(w, p).stats.playSeconds = seconds
	end

	local function bowl(w, p)
		local slot = w.Ranch.slotOf(p)
		local b = w.WL.anchor(slot, "bowl")
		return Bots.ground(b.X + 2, b.Z)
	end

	local function holds(w, p)
		return w.h:sentTo(p, "HoldState")
	end

	describe("QuestService › accueil", function()
		it(
			"nouveau : étape 1 dans l'instantané (aucune célébration à la seconde 0), Plop de départ au premier tick",
			function()
				local w = world()
				local p = newcomer(w)
				local snap = w.h:sentTo(p, "DataSnapshot")[1][1]
				expect(snap.onboarding.step).toBe(1)
				expect(snap.firstJoin > 0).toBe(true)
				expect(#snap.objectives.list).toBe(3)
				expect(snap.objectives.list[1].id).toBe(1)
				expect(snap.objectives.list[2].id).toBe(3)
				expect(snap.objectives.list[3].id).toBe(7)
				expect(#celebrations(w, p, "onboarding")).toBe(0)
				Brains.frames(w, 2)
				local d = data(w, p)
				local plop = d.squishies["1"]
				expect(plop ~= nil).toBe(true)
				expect(plop.s).toBe(1)
				expect(plop.bf).toBe(1)
				-- tamponné sans carte « Nouveau ! »
				expect(d.dex.mut[1] % 2).toBe(1)
				expect(#celebrations(w, p, "dexNew")).toBe(0)
				expect(w.Q.stage(p)).toBe(1)
				-- entonnoir : étape 1
				local funnel = 0
				for _, c in w.h.log.analytics do
					if c.method == "LogOnboardingFunnelStepEvent" and c.args[2] == 1 then
						funnel += 1
					end
				end
				expect(funnel).toBe(1)
			end
		)

		it(
			"étapes par les signaux et le temps de jeu ; jumeau à 0:40, premier tirage à 2:45, carte des objectifs à 5:00",
			function()
				local w = world()
				local p = newcomer(w)
				Brains.frames(w, 2)
				w.Signals.Pressed:Fire(p, { uid = "1", perfect = false, streak = 0 })
				expect(w.Q.stage(p)).toBe(2)
				w.Signals.TileBought:Fire(p, "snack", 1)
				expect(w.Q.stage(p)).toBe(3)
				setPlay(w, p, 40)
				Brains.frames(w, 1)
				expect(w.Q.stage(p)).toBe(4)
				expect(data(w, p).squishies["1"].at).toBe("pool") -- Plop posé dans le Bassin (leçon de fusion)
				Brains.frames(w, 25) -- éclosion du jumeau (2 s)
				local hatched = 0
				for _ in data(w, p).squishies do
					hatched += 1
				end
				expect(hatched).toBe(2)
				w.Signals.Fused:Fire(p, "1", 1)
				expect(w.Q.stage(p)).toBe(5)
				w.Signals.PotCollected:Fire(p, 240, false)
				expect(w.Q.stage(p)).toBe(6)
				w.Signals.Caught:Fire(p, {
					kind = "runaway",
					species = 5,
					rarity = 1,
					mutation = 0,
					ownerId = 0,
					hero = false,
					byLeap = false,
					babyUid = "",
				})
				expect(w.Q.stage(p)).toBe(7)
				setPlay(w, p, 165)
				Brains.frames(w, 1)
				expect(w.Q.stage(p)).toBe(8)
				setPlay(w, p, 300)
				Brains.frames(w, 1)
				expect(#celebrations(w, p, "objectivesCard")).toBe(1)
				-- étape 9 (balade) pas faite : l'accueil continue quand même ; étape 10 par UiSeen
				w.h:fireServer(R .. "UiSeen", p, "objectives")
				expect(w.Q.stage(p)).toBe(10)
				Brains.frames(w, 1)
				expect(data(w, p).onboarding.done).toBe(true)
				expect(w.Q.isNewcomerQuiet(p)).toBe(false)
				w.Signals.Splorched:Fire(p, 1, 0)
				expect(w.Q.stage(p)).toBe(11)
				local steps = celebrations(w, p, "onboarding")
				expect(steps[#steps].step).toBe(11)
			end
		)

		it(
			"aucune étape ne bloque : la consigne se ferme à 90 s ; discret avant l'étape 9, jamais au-delà de 8 min",
			function()
				local w = world()
				local p = Brains.join(w, 1, {
					profile = Bots.profile(w, {
						onboarding = { step = 8, done = false, demoDone = true },
						stats = { playSeconds = 200, sessions = 1 },
					}),
				})
				Brains.frames(w, 2)
				expect(w.Q.isNewcomerQuiet(p)).toBe(true)
				local open = w.Q.openStates()
				expect(#open).toBe(1)
				expect(open[1].name).toBe("onboardingStep")
				w.Clock.advance(91)
				w.Q.step(w.Clock.now())
				expect(#w.Q.openStates()).toBe(0)
				setPlay(w, p, 481)
				Brains.frames(w, 1)
				expect(w.Q.isNewcomerQuiet(p)).toBe(false)
				expect(data(w, p).onboarding.done).toBe(true)
			end
		)

		it(
			"retour : étape gardée, naissances scriptées jamais rejouées ; script() pour ChaseService",
			function()
				local w = world()
				local p = Brains.join(w, 1, {
					profile = Bots.profile(w, {
						onboarding = { step = 8, done = false, demoDone = false },
						stats = { playSeconds = 200, sessions = 1 },
						nextUid = 3,
						squishies = {
							["1"] = {
								s = 1,
								m = 0,
								st = 1,
								z = 171,
								zg = 0,
								bf = 1,
								lk = false,
								o = "",
								at = "pen",
								b = 0,
								gd = 0,
							},
						},
					}),
				})
				Brains.frames(w, 3)
				expect(w.Q.stage(p)).toBe(8)
				local n = 0
				for _ in data(w, p).squishies do
					n += 1
				end
				expect(n).toBe(1) -- ni Plop de départ, ni jumeau
				local script = w.Q.script(p)
				expect(script.active).toBe(true)
				expect(script.runawayAt).toBeNil() -- première fuite déjà faite (étape 7 passée)
				expect(script.demoAt).toBe(180)
				expect(script.runawayPaused).toBe(true)
				expect(w.Q.playSeconds(p) >= 200).toBe(true)
			end
		)

		it("UiSeen : une fois par écran et par session, Signals.UiSeen, ne donne rien", function()
			local w = world()
			local p = veteran(w)
			local seen = {}
			w.Signals.UiSeen:Connect(function(_, screen)
				table.insert(seen, screen)
			end)
			local coins = data(w, p).coins
			w.h:fireServer(R .. "UiSeen", p, "shop")
			w.osClock.advance(1)
			w.h:fireServer(R .. "UiSeen", p, "shop")
			w.osClock.advance(1)
			w.h:fireServer(R .. "UiSeen", p, "modeCard")
			expect(seen).toEqual({ "shop", "modeCard" })
			expect(data(w, p).coins).toBe(coins)
		end)
	end)

	describe("QuestService › objectifs", function()
		it(
			"progression par les signaux, réclamation en secondes de revenu sans boost, les 3 : Goutte chanceuse",
			function()
				local w = world()
				local p = veteran(w)
				local d = data(w, p)
				d.objectives = {
					day = w.Clock.day(),
					list = {
						{ id = 1, p = 29, done = false, claimed = false },
						{ id = 7, p = 1, done = false, claimed = false },
						{ id = 14, p = 0, done = false, claimed = false },
					},
					rerolls = 0,
					allClaimed = false,
				}
				w.Signals.Pressed:Fire(p, { uid = "1", perfect = false, streak = 0 })
				expect(d.objectives.list[1].done).toBe(true)
				expect(#celebrations(w, p, "objectiveDone")).toBe(1)
				w.Signals.Fused:Fire(p, "1", 2) -- fusion + combo ×2
				expect(d.objectives.list[2].done).toBe(true)
				expect(d.objectives.list[3].done).toBe(true)
				local boost = d.boosts.personalLeft
				local before = d.coins
				for slot = 1, 3 do
					w.h:fireServer(R .. "ClaimObjective", p, slot)
					w.osClock.advance(0.3)
				end
				expect(d.coins > before).toBe(true)
				expect(d.boosts.personalLeft).toBe(boost) -- aucun boost
				expect(d.objectives.allClaimed).toBe(true)
				expect(#celebrations(w, p, "luckyDrop")).toBe(1)
				-- déjà réclamé : refusé
				local coins = d.coins
				w.h:fireServer(R .. "ClaimObjective", p, 1)
				expect(d.coins).toBe(coins)
				-- itemSku Objective_<niveau> (analytique cumulée)
				local A = w.h:require("ServerScriptService.Server.Util.Analytics")
				expect(A.stats(p).pending > 0).toBe(true)
			end
		)

		it("relance : une par jour ; l'objectif 12 sans ami présent se relance gratuitement", function()
			local w = world()
			local p = veteran(w)
			local d = data(w, p)
			d.objectives = {
				day = w.Clock.day(),
				list = {
					{ id = 1, p = 0, done = false, claimed = false },
					{ id = 12, p = 0, done = false, claimed = false },
					{ id = 17, p = 0, done = false, claimed = false },
				},
				rerolls = 0,
				allClaimed = false,
			}
			w.h:fireServer(R .. "RerollObjective", p, 2)
			expect(d.objectives.list[2].id ~= 12).toBe(true)
			expect(d.objectives.rerolls).toBe(0) -- gratuite
			w.osClock.advance(0.3)
			w.h:fireServer(R .. "RerollObjective", p, 1)
			expect(d.objectives.rerolls).toBe(1)
			local id = d.objectives.list[3].id
			w.osClock.advance(0.3)
			w.h:fireServer(R .. "RerollObjective", p, 3)
			expect(d.objectives.list[3].id).toBe(id) -- plus de relance aujourd'hui
		end)

		it(
			"minuit en session : terminés réclamés seuls, en cours gardés ; nouveaux à la connexion suivante",
			function()
				local w = world()
				local p = veteran(w)
				local d = data(w, p)
				d.objectives = {
					day = w.Clock.day(),
					list = {
						{ id = 1, p = 30, done = true, claimed = false },
						{ id = 7, p = 1, done = false, claimed = false },
						{ id = 14, p = 0, done = false, claimed = false },
					},
					rerolls = 0,
					allClaimed = false,
				}
				local coins = d.coins
				w.Clock.advance(w.Clock.untilNextDay() + 1)
				Brains.frames(w, 1)
				expect(d.coins > coins).toBe(true)
				expect(#d.objectives.list).toBe(2)
				expect(d.objectives.list[1].id).toBe(7)
				-- la progression des objectifs gardés continue
				w.Signals.Fused:Fire(p, "1", 1)
				expect(d.objectives.list[1].done).toBe(true)
				-- départ puis retour : nouveaux objectifs, carte « Nouveaux objectifs ! »
				Bots.leave(p)
				w.h:settle(5)
				local q = Brains.join(w, 1)
				local again = data(w, q)
				expect(again.objectives.day).toBe(w.Clock.day())
				expect(#again.objectives.list).toBe(3)
				expect(#celebrations(w, q, "newObjectives") >= 1).toBe(true)
			end
		)
	end)

	describe("QuestService › Nourrir Plop", function()
		it(
			"maintien de 2 s mesuré par le serveur : HoldState, jour + 1, boost de 5 min, Fed, plopDay ; une fois par jour",
			function()
				local w = world()
				local p = veteran(w)
				Bots.place(p, bowl(w, p))
				Brains.frames(w, 3)
				local fed = nil
				w.Signals.Fed:Connect(function(_, days)
					fed = days
				end)
				w.h:fireServer(R .. "FeedPlop", p, true)
				local hs = holds(w, p)
				expect(#hs).toBe(1)
				expect(hs[1][1].kind).toBe("feed")
				expect(hs[1][1].active).toBe(true)
				expect(hs[1][1].endsAt - w.Clock.now()).toBeNear(2, 0.01)
				expect(w.Q.openStates()[1].name).toBe("feedHold")
				Brains.frames(w, 21)
				local d = data(w, p)
				expect(d.plopDays).toBe(1)
				expect(d.lastFeedDay).toBe(w.Clock.day())
				expect(fed).toBe(1)
				expect(d.boosts.personalLeft > 0).toBe(true)
				expect(#celebrations(w, p, "plopDay")).toBe(1)
				expect(#w.Q.openStates()).toBe(0)
				-- deux fois le même jour : refusé
				w.osClock.advance(1)
				w.h:fireServer(R .. "FeedPlop", p, true)
				Brains.frames(w, 25)
				expect(d.plopDays).toBe(1)
				expect(table.find(Bots.feedbackKeys(p), "feedback.alreadyFed") ~= nil).toBe(true)
			end
		)

		it("FeedPlop(false) ou sortie de zone : annulé, rien gagné", function()
			local w = world()
			local p = veteran(w)
			Bots.place(p, bowl(w, p))
			Brains.frames(w, 3)
			w.h:fireServer(R .. "FeedPlop", p, true)
			Brains.frames(w, 5)
			w.osClock.advance(1)
			w.h:fireServer(R .. "FeedPlop", p, false)
			Brains.frames(w, 20)
			expect(data(w, p).plopDays).toBe(0)
			local hs = holds(w, p)
			expect(hs[#hs][1].active).toBe(false)
			w.osClock.advance(1)
			w.h:fireServer(R .. "FeedPlop", p, true)
			Brains.frames(w, 5)
			local slot = w.Ranch.slotOf(p)
			Bots.place(p, Brains.atRanch(w, p, 0, 70))
			Brains.frames(w, 20)
			expect(data(w, p).plopDays).toBe(0)
			local _ = slot
		end)
	end)

	describe("QuestService › Squishydex", function()
		it(
			"nouvelle entrée : dexNew, Stamped, étoiles ; doublon : faux ; espèce future au-delà de la case libre : ignorée",
			function()
				local w = world()
				local p = veteran(w)
				local stamped = 0
				w.Signals.Stamped:Connect(function(_, n)
					stamped += n
				end)
				expect(w.Q.stamp(p, 3, 2, 2)).toBe(true)
				expect(stamped).toBe(4) -- page + mutation + ★1 + ★2
				expect(w.Q.stamp(p, 3, 2, 2)).toBe(false)
				expect(#celebrations(w, p, "dexNew")).toBe(1)
				local d = data(w, p)
				local n = #d.dex.mut
				expect(w.Q.stamp(p, n + 5, 0, 0)).toBe(false)
				expect(#d.dex.mut).toBe(n)
			end
		)

		it("famille complète : dex.fam posé pour toujours, au tampon qui la complète", function()
			local w = world()
			local p = veteran(w)
			local Species = w.h:require("ReplicatedStorage.Shared.Config.Species")
			local fam = Species.Families.jelly.species
			local index = table.find(Species.FamilyOrder, "jelly")
			for i, s in fam do
				w.Q.stamp(p, s, 0, 0)
				if i < #fam then
					expect(data(w, p).dex.fam[index]).toBe(0)
				end
			end
			expect(data(w, p).dex.fam[index]).toBe(1)
		end)

		it(
			"SquishyObtained : tamponne ; Rare+ d'une naissance, capture ou bébé : objectif « Grande éclosion »",
			function()
				local w = world()
				local p = veteran(w)
				local d = data(w, p)
				d.objectives = {
					day = w.Clock.day(),
					list = {
						{ id = 1, p = 0, done = false, claimed = false },
						{ id = 7, p = 0, done = false, claimed = false },
						{ id = 15, p = 0, done = false, claimed = false },
					},
					rerolls = 0,
					allClaimed = false,
				}
				local Species = w.h:require("ReplicatedStorage.Shared.Config.Species")
				local rare
				for _, def in Species.List do
					if def.rarity == 3 then
						rare = def.id
						break
					end
				end
				w.Squishy.give(p, { s = rare, m = 0, st = 0, z = 5 }, "runaway")
				expect(d.objectives.list[3].done).toBe(true)
				expect(d.dex.mut[rare] % 2).toBe(1)
			end
		)
	end)

	describe("QuestService › session", function()
		it(
			"FriendsChanged : stats.lastFriendDay ; carte « Plop a sommeil » à 60 et 120 min de session",
			function()
				local w = world()
				local p = veteran(w)
				w.Signals.FriendsChanged:Fire(p, 1)
				expect(data(w, p).stats.lastFriendDay).toBe(w.Clock.day())
				for _ = 1, 125 do
					w.Clock.advance(59)
					w.Q.step(w.Clock.now())
				end
				local cards = celebrations(w, p, "sleepy")
				expect(#cards).toBe(2)
				expect(cards[1].minutes).toBe(60)
				expect(cards[2].minutes).toBe(120)
			end
		)

		it("départ : sessions + 1 dans la sauvegarde de départ ; SessionLength et BoostShare", function()
			local w = world()
			local p = veteran(w)
			local sessions = data(w, p).stats.sessions
			Brains.frames(w, 5)
			Bots.leave(p)
			w.h:settle(5)
			local MockInstance = require("../harness/MockInstance")
			local store = w.h.dataStores["PlayerData_v1/global"]
			local saved = MockInstance.state(store).data["player_1"]
			expect(saved.data.stats.sessions).toBe(sessions + 1)
			local names = {}
			for _, c in w.h.log.analytics do
				if c.method == "LogCustomEvent" then
					names[c.args[2]] = true
				end
			end
			expect(names.SessionLength).toBe(true)
			expect(names.BoostShare).toBe(true)
		end)

		it(
			"états minutés : jamais au-delà de leur délai pendant 60 s de jeu (16 joueurs nouveaux)",
			function()
				local w = world()
				local StateTimeouts = w.h:require("ReplicatedStorage.Shared.Logic.StateTimeouts")
				for i = 1, 16 do
					newcomer(w, i)
				end
				for _ = 1, 600 do
					Brains.frames(w, 1)
					for _, st in w.Q.openStates() do
						expect(StateTimeouts.expired(st.name, st.startedAt, w.Clock.now())).toBe(false)
					end
				end
				expect(w.h:require(S .. "DiagnosticsService").counts().errors).toBe(0)
			end
		)
	end)

	describe("QuestService › revue (cycle de vie)", function()
		it(
			"départ : sessions + 1 même si QuestService voit PlayerRemoving AVANT DataService (ordre non garanti par Roblox)",
			function()
				local w = world()
				local p = veteran(w)
				local sessions = data(w, p).stats.sessions
				Brains.frames(w, 5)
				-- Roblox ne garantit pas l'ordre des connexions : le PlayerRemoving de QuestService passe d'abord
				local handlers = w.h.game.Players.PlayerRemoving._handlers
				for i = 1, math.floor(#handlers / 2) do
					handlers[i], handlers[#handlers - i + 1] = handlers[#handlers - i + 1], handlers[i]
				end
				Bots.leave(p)
				w.h:settle(5)
				local MockInstance = require("../harness/MockInstance")
				local store = w.h.dataStores["PlayerData_v1/global"]
				local saved = MockInstance.state(store).data["player_1"]
				expect(saved.data.stats.sessions).toBe(sessions + 1)
			end
		)
	end)
end
