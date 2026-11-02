--!nocheck
-- Contre-audit social (paquet meta, docs/04 §17.1 g, remarque A22) : chaque menace écrite comme une
-- attaque. Pet-sitting (second compte, plafonds 100 / 100 / 20 par ami, pression de l'intérieur du ranch,
-- de loin, sans amitié), applaudissements (non-spectateur, deux fois, après la fenêtre, soi-même),
-- rapports (rafale de ReportError, noms, panneau d'un non-administrateur), FeedPlop de loin, en hauteur,
-- deux fois le même jour, ClientEvent en rafale.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local function world()
		local w = Brains.boot(Harness, { t0 = T0, stubMeta = false })
		w.WL = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		return w
	end

	local function join(w, id, n)
		local list = {}
		for i = 1, n or 1 do
			table.insert(list, { s = 2, z = 40 + i })
		end
		return Brains.join(w, id, { profile = Brains.profile(w, { squishies = list }) })
	end

	local function rewardedCount(w)
		local box = { n = 0, helpful = 0 }
		w.Signals.PetSitRewarded:Connect(function(_, _, helpful)
			box.n += 1
			if helpful then
				box.helpful += 1
			end
		end)
		return box
	end

	describe("RedTeam_Social › pet-sitting", function()
		it(
			"second compte qui presse en boucle : « Plus serviable » jamais au-delà de 20 par ami et par jour",
			function()
				local w = world()
				w.h:makeFriends(1, 2)
				local owner = join(w, 1, 4)
				local alt = join(w, 2, 1)
				w.h:settle(3)
				Bots.place(owner, Brains.atRanch(w, owner, 0, 30))
				Bots.place(alt, Brains.atRanch(w, owner, -19.5, -1))
				Brains.frames(w, 8)
				local box = rewardedCount(w)
				for _ = 1, 14 do
					local uids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
					for i = 1, math.min(2, #uids) do
						w.h:fireServer(R .. "PetPress", alt, owner.UserId, uids[i], w.Clock.now())
						w.osClock.advance(0.2)
					end
					w.Clock.advance(8.1)
					Brains.frames(w, 1)
				end
				expect(box.n).toBe(28)
				expect(box.helpful).toBe(20)
				expect(w.DS.get(alt).weekly.helpful).toBe(20)
				expect(w.DS.get(alt).caps.petSitBy[tostring(owner.UserId)]).toBe(20)
			end
		)

		it(
			"plafonds du jour : 100 récompensées par visiteur, 100 reçues par propriétaire (plusieurs comptes)",
			function()
				local w = world()
				for id = 2, 3 do
					w.h:makeFriends(1, id)
				end
				local owner = join(w, 1, 4)
				local a = join(w, 2, 1)
				local b = join(w, 3, 1)
				w.h:settle(3)
				Bots.place(owner, Brains.atRanch(w, owner, 0, 30))
				Bots.place(a, Brains.atRanch(w, owner, -19.5, -1))
				Bots.place(b, Brains.atRanch(w, owner, -19.5, -2))
				Brains.frames(w, 8)
				local box = rewardedCount(w)
				local day = w.Clock.day()
				local oc = w.DS.get(owner).caps
				oc.day = day
				oc.petSitIn = 99
				local uids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
				w.h:fireServer(R .. "PetPress", a, owner.UserId, uids[1], w.Clock.now())
				w.h:fireServer(R .. "PetPress", b, owner.UserId, uids[2], w.Clock.now())
				expect(box.n).toBe(1) -- le 100e reçu passe, le 101e est refusé avant toute pression
				expect(oc.petSitIn).toBe(100)
				local ac = w.DS.get(a).caps
				oc.petSitIn = 0
				ac.petSit = 100
				w.Clock.advance(8.1)
				Brains.frames(w, 1)
				w.osClock.advance(1)
				w.h:fireServer(R .. "PetPress", a, owner.UserId, uids[2], w.Clock.now())
				expect(box.n).toBe(1)
				expect(ac.petSit).toBe(100)
			end
		)

		it(
			"pression de l'intérieur du ranch de l'ami, de trop loin, sans amitié, tClient truqué : refusées",
			function()
				local w = world()
				w.h:makeFriends(1, 2)
				local owner = join(w, 1, 4)
				local friend = join(w, 2, 1)
				local stranger = join(w, 3, 1)
				w.h:settle(3)
				Bots.place(owner, Brains.atRanch(w, owner, 0, 30))
				Bots.place(friend, Brains.atRanch(w, owner, -19.5, -1))
				Bots.place(stranger, Brains.atRanch(w, owner, -19.5, -2))
				Brains.frames(w, 8)
				local box = rewardedCount(w)
				local uids = w.Ranch.fenceOf(w.Ranch.slotOf(owner))
				expect(#uids).toBe(3)
				w.h:fireServer(R .. "PetPress", stranger, owner.UserId, uids[1], w.Clock.now())
				w.h:fireServer(R .. "PetPress", friend, owner.UserId, uids[3], w.Clock.now()) -- place n° 3 à 32 studs
				for _, t in { 0 / 0, math.huge, "0", {} } do
					w.osClock.advance(1)
					w.h:fireServer(R .. "PetPress", friend, owner.UserId, uids[1], t)
				end
				-- de trop loin (15 studs de la rue)
				Bots.place(friend, Brains.atRanch(w, owner, -19.5, -16))
				Brains.frames(w, 3)
				w.osClock.advance(1)
				w.h:fireServer(R .. "PetPress", friend, owner.UserId, uids[1], w.Clock.now())
				expect(box.n).toBe(0)
			end
		)
	end)

	describe("RedTeam_Social › applaudissements", function()
		it(
			"non-spectateur, deux fois, après la fenêtre, soi-même, héros sans fenêtre : jamais récompensé",
			function()
				local w = world()
				local C = w.h:require(S .. "CommunityService")
				local hero = join(w, 1)
				local viewer = join(w, 2)
				local other = join(w, 3)
				C.openClapWindow(hero, w.Clock.now() + 8, { viewer })
				w.h:fireServer(R .. "Clap", other, hero.UserId)
				w.h:fireServer(R .. "Clap", hero, hero.UserId)
				w.h:fireServer(R .. "Clap", viewer, other.UserId)
				w.h:fireServer(R .. "Clap", viewer, hero.UserId)
				w.osClock.advance(1)
				w.h:fireServer(R .. "Clap", viewer, hero.UserId)
				expect(w.DS.get(viewer).caps.claps).toBe(1)
				expect(w.DS.get(other).caps.claps).toBe(0)
				expect(w.DS.get(hero).caps.claps).toBe(0)
				w.Clock.advance(9)
				C.step(w.Clock.now(), {})
				C.openClapWindow(other, w.Clock.now() - 1, nil) -- fin déjà passée : aucune fenêtre
				w.osClock.advance(1)
				w.h:fireServer(R .. "Clap", viewer, other.UserId)
				expect(w.DS.get(viewer).caps.claps).toBe(1)
			end
		)
	end)

	describe("RedTeam_Social › rapports", function()
		it(
			"rafale de 1 000 ReportError avec des noms : au plus 30 comptés, noms jamais gardés, aucune réponse",
			function()
				local w = world()
				local D = w.h:require(S .. "DiagnosticsService")
				local p = Brains.join(w, 1, { profile = Brains.profile(w, {}), name = "Attaquant" })
				for i = 1, 1000 do
					w.h:fireServer(
						R .. "ReportError",
						p,
						1,
						"k",
						"Attaquant spam " .. string.rep("w", i % 200),
						"",
						""
					)
					w.osClock.advance(2.1)
				end
				local total = 0
				for _, e in D.snapshot(1).entries do
					total += e.count
					expect(e.text:find("Attaquant", 1, true)).toBeNil()
				end
				expect(total).toBe(30)
				w.h:fireServer(R .. "RequestDiagnostics", p, 1)
				expect(#w.h:sentTo(p, "DiagnosticsSnapshot")).toBe(0)
			end
		)
	end)

	describe("RedTeam_Social › Nourrir Plop (A22)", function()
		it(
			"FeedPlop de loin : aucun maintien ; deux fois le même jour (même en rafale) : un seul repas",
			function()
				local w = world()
				local p = join(w, 1)
				local bowl = w.WL.anchor(w.Ranch.slotOf(p), "bowl")
				-- de loin (15 studs à plat)
				Bots.place(p, Bots.ground(bowl.X + 15, bowl.Z))
				Brains.frames(w, 3)
				w.h:fireServer(R .. "FeedPlop", p, true)
				Brains.frames(w, 25)
				expect(#w.h:sentTo(p, "HoldState")).toBe(0)
				-- au bol : un repas, puis plus rien le même jour (même en rafale)
				Bots.place(p, Bots.ground(bowl.X + 2, bowl.Z))
				Brains.frames(w, 3)
				w.osClock.advance(1)
				w.h:fireServer(R .. "FeedPlop", p, true)
				Brains.frames(w, 25)
				expect(w.DS.get(p).plopDays).toBe(1)
				for _ = 1, 20 do
					w.osClock.advance(0.6)
					w.h:fireServer(R .. "FeedPlop", p, true)
					Brains.frames(w, 1)
				end
				Brains.frames(w, 25)
				expect(w.DS.get(p).plopDays).toBe(1)
				-- le lendemain : de nouveau possible
				w.Clock.advance(w.Clock.untilNextDay() + 1)
				Brains.frames(w, 2)
				w.osClock.advance(1)
				w.h:fireServer(R .. "FeedPlop", p, true)
				Brains.frames(w, 25)
				expect(w.DS.get(p).plopDays).toBe(2)
			end
		)

		it("en hauteur : à plat sur le bol mais pieds 12 studs au-dessus du sol : aucun maintien", function()
			local w = world()
			local p = join(w, 1)
			local bowl = w.WL.anchor(w.Ranch.slotOf(p), "bowl")
			local Q = w.h:require(S .. "QuestService")
			local MoveCheck = w.h:require("ServerScriptService.Server.Util.MoveCheck")
			-- position validée en hauteur (comme un joueur debout sur un toit), droit d'agir accordé
			local high = w.V3.new(bowl.X + 1, Bots.ground(bowl.X + 1, bowl.Z).Y + 12, bowl.Z)
			local lastValid, canAct = MoveCheck.lastValid, MoveCheck.canAct
			MoveCheck.lastValid = function()
				return high
			end
			MoveCheck.canAct = function()
				return true
			end
			w.h:fireServer(R .. "FeedPlop", p, true)
			for _ = 1, 25 do
				w.Clock.advance(0.1)
				Q.step(w.Clock.now())
			end
			MoveCheck.lastValid, MoveCheck.canAct = lastValid, canAct
			expect(#w.h:sentTo(p, "HoldState")).toBe(0)
			expect(w.DS.get(p).plopDays).toBe(0)
		end)

		it("maintien commencé puis téléporté loin du bol : annulé, rien gagné", function()
			local w = world()
			local p = join(w, 1)
			local bowl = w.WL.anchor(w.Ranch.slotOf(p), "bowl")
			Bots.place(p, Bots.ground(bowl.X + 2, bowl.Z))
			Brains.frames(w, 3)
			w.h:fireServer(R .. "FeedPlop", p, true)
			Brains.frames(w, 5)
			Bots.place(p, Bots.ground(bowl.X + 40, bowl.Z))
			Brains.frames(w, 25)
			expect(w.DS.get(p).plopDays).toBe(0)
		end)
	end)

	describe("RedTeam_Social › ClientEvent (A21, A22)", function()
		it(
			"rafale de 1 000 ClientEvent : analytique seulement, 20 par session au plus, profil inchangé",
			function()
				local w = world()
				local p = join(w, 1)
				local ok, path = Fuzz.profileUnchanged(w.h, p, function()
					for i = 1, 1000 do
						w.h:fireServer(
							R .. "ClientEvent",
							p,
							if i % 2 == 0 then "shopOpened" else "qualityReduced"
						)
						w.osClock.advance(5.1)
						w.Clock.advance(7)
						if i % 50 == 0 then
							w.h:require("ServerScriptService.Server.Util.Analytics").step(w.Clock.now())
						end
					end
					w.h:settle(2)
				end, { "stats" })
				expect(ok).toBe(true)
				local _ = path
				local n = 0
				for _, c in w.h.log.analytics do
					if
						c.method == "LogCustomEvent"
						and (c.args[2] == "ShopOpened" or c.args[2] == "QualityReduced")
					then
						n += 1
					end
				end
				expect(n).toBe(20)
			end
		)
	end)

	describe("RedTeam_Social › joueur parti (revue)", function()
		it(
			"intentions arrivées APRÈS le départ (paquets en vol) : ignorées, aucun état par joueur recréé (fuite, blocage fantôme)",
			function()
				local w = world()
				local p = join(w, 1)
				local q = join(w, 2)
				local C = w.h:require(S .. "CommunityService")
				local D = w.h:require(S .. "DiagnosticsService")
				Bots.leave(p)
				w.h:settle(2)
				w.h:fireServer(R .. "ReportBlocked", p, { q.UserId })
				w.h:fireServer(R .. "SetInputType", p, 2, false)
				w.h:fireServer(R .. "ClientEvent", p, "shopOpened")
				w.h:settle(2)
				expect(C.isBlocked(q, p)).toBe(false)
				expect(D.device(p).kind).toBe(0)
			end
		)
	end)
end
