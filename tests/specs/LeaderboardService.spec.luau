--!nocheck
-- LeaderboardService (paquet meta, docs/04 §11.13, §18.2) : valeur codée (égalités au premier arrivé,
-- valeur maximale ≈ 1,05e12, décodage exact, drapeau caché), valeurs de la semaine par les signaux
-- (« Plus serviable » seulement si le 3e argument de PetSitRewarded est vrai), écritures groupées (60 s,
-- record seulement), bannis jamais écrits, top 10 (120 s) et noms (caché d'un autre serveur → "", panne
-- de UserService → "", aucun avertissement), changement de semaine (prev, titres), statue et fanfare,
-- LeaderboardState, zéro trace.
-- v2.0 (lot A4, étape 6, D28) : aucun nouveau classement ; un Petit Splorch ajoute 0 à « Plus
-- généreux » ; le Livre des records (confettiTotal, bestR, ascend, hearts.receivedTotal,
-- stats.upgradesBought) arrive au seul propriétaire par DataSnapshot / DataPatch, jamais aux autres.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local MockInstance = require("../harness/MockInstance")
local task = require("@lune/task")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local MONDAY = 345600 + 604800 * 2976 -- un lundi 00:00 UTC (semaine 2976)
	local T0 = MONDAY + 3 * 86400 + 60
	local S = "ServerScriptService.Server.Services."

	local function world()
		local w = Brains.boot(Harness, { t0 = T0, stubMeta = false })
		w.L = w.h:require(S .. "LeaderboardService")
		w.C = w.h:require(S .. "CommunityService")
		return w
	end

	local function join(w, id, edit)
		return Brains.join(
			w,
			id,
			{ profile = Brains.profile(w, { squishies = { { s = 1, z = 100 } }, edit = edit }) }
		)
	end

	local function storeData(w, category, week)
		local store = w.h.dataStores["ordered:Weekly_" .. category .. "_" .. tostring(week) .. "/global"]
		return if store then MockInstance.state(store).data else nil
	end

	local function week(w)
		return math.floor((w.Clock.unix() - 345600) / 604800)
	end

	local function flush(w)
		w.Clock.advance(61)
		w.L.step(w.Clock.now())
		w.h:settle(3)
	end

	describe("LeaderboardService › valeur codée", function()
		it("décodage exact, drapeau caché, valeur maximale ≈ 1,05e12 sous 2^53", function()
			local w = world()
			for _, case in { { 0, 0, false }, { 1, 604799, true }, { 37, 12345, false }, { 500000, 0, true } } do
				local v = w.L.encode(case[1], case[2], case[3])
				expect(v % 1).toBe(0)
				local score, s, hidden = w.L.decode(v)
				expect(score).toBe(case[1])
				expect(s).toBe(case[2])
				expect(hidden).toBe(case[3])
			end
			local max = w.L.encode(500000, 0, true)
			expect(max).toBeLessThan(2 ^ 53)
			expect(max).toBeGreaterThan(1.04e12)
			expect(max).toBeLessThan(1.06e12)
			-- au-delà du plus grand score : borné, jamais d'arrondi
			expect(w.L.decode(w.L.encode(1e9, 0, false))).toBe(500000)
		end)

		it(
			"égalités : à score égal, le premier arrivé passe devant ; un score plus haut passe toujours devant",
			function()
				local w = world()
				local early = w.L.encode(10, 100, false)
				local late = w.L.encode(10, 5000, false)
				expect(early > late).toBe(true)
				expect(w.L.encode(11, 600000, true) > w.L.encode(10, 0, false)).toBe(true)
				-- le drapeau caché ne change jamais l'ordre de deux scores différents
				expect(w.L.encode(10, 100, true) > w.L.encode(9, 0, false)).toBe(true)
			end
		)
	end)

	describe("LeaderboardService › valeurs de la semaine", function()
		it(
			"signaux : tampons cumulés, meilleur combo, meilleure capture, serviable (3e argument vrai seulement), généreux",
			function()
				local w = world()
				local p = join(w, 1)
				local q = join(w, 2)
				w.Signals.Stamped:Fire(p, 3)
				w.Signals.Stamped:Fire(p, 2)
				w.Signals.Fused:Fire(p, "1", 3)
				w.Signals.Fused:Fire(p, "1", 2)
				w.Signals.Caught:Fire(p, {
					kind = "golden",
					species = 9,
					rarity = 5,
					mutation = 3,
					ownerId = 0,
					hero = false,
					byLeap = false,
					babyUid = "x",
				})
				w.Signals.PetSitRewarded:Fire(p, q, true)
				w.Signals.PetSitRewarded:Fire(p, q, false)
				w.Signals.Splorched:Fire(p, 1, 4)
				-- q attrape la fuite de p et reçoit un bébé : p « généreux » + 1
				w.Signals.Caught:Fire(q, {
					kind = "escape",
					species = 2,
					rarity = 2,
					mutation = 0,
					ownerId = 1,
					hero = false,
					byLeap = false,
					babyUid = "9",
				})
				local wk = w.DS.get(p).weekly
				expect(wk.stamps).toBe(5)
				expect(wk.combo).toBe(3)
				expect(wk.catchScore).toBe(200 * 3)
				expect(wk.helpful).toBe(1)
				expect(wk.generous).toBe(5)
			end
		)

		it("écritures groupées toutes les 60 s, record seulement ; banni jamais écrit", function()
			local w = world()
			local p = join(w, 1)
			local banned = join(w, 2, function(d)
				d.flags.lbBanUntil = 1800000000 * 2
			end)
			w.Signals.Stamped:Fire(p, 4)
			w.Signals.Stamped:Fire(banned, 4)
			w.L.step(w.Clock.now())
			w.h:settle(2)
			flush(w)
			local data = storeData(w, "stamps", week(w))
			expect(data ~= nil).toBe(true)
			local score, _, hidden = w.L.decode(data["1"])
			expect(score).toBe(4)
			expect(hidden).toBe(false)
			expect(data["2"]).toBeNil()
			expect(w.L.isBanned(banned)).toBe(true)
			-- un autre serveur a déjà écrit un meilleur score : jamais abaissé
			data["1"] = w.L.encode(50, 10, false)
			w.Signals.Stamped:Fire(p, 1)
			flush(w)
			expect(w.L.decode(data["1"])).toBe(50)
		end)

		it("nom caché : drapeau réécrit au lot suivant, l'heure d'arrivée gardée", function()
			local w = world()
			local p = join(w, 1)
			w.Signals.Stamped:Fire(p, 2)
			flush(w)
			local data = storeData(w, "stamps", week(w))
			local _, s0 = w.L.decode(data["1"])
			w.Clock.advance(500)
			w.h:fireServer("ReplicatedStorage.Remotes.SetSetting", p, "hideName", true)
			flush(w)
			local score, s1, hidden = w.L.decode(data["1"])
			expect(score).toBe(2)
			expect(hidden).toBe(true)
			expect(s1).toBe(s0)
		end)
	end)

	describe("LeaderboardService › top 10 et noms", function()
		it(
			"top 10 lu toutes les 120 s ; caché d'un autre serveur → name vide ; LeaderboardState envoyé",
			function()
				local w = world()
				local p = join(w, 1)
				w.L.step(w.Clock.now())
				w.h:settle(3)
				local store =
					w.h.game.DataStoreService:GetOrderedDataStore("Weekly_combo_" .. tostring(week(w)))
				store:SetAsync("77", w.L.encode(5, 10, false))
				store:SetAsync("88", w.L.encode(5, 20, true)) -- caché, sur un autre serveur
				w.Clock.advance(121)
				w.L.step(w.Clock.now())
				w.h:settle(5)
				local states = w.h:sentTo(p, "LeaderboardState")
				local top = states[#states][1].boards.combo.top
				expect(#top).toBe(2)
				expect(top[1].userId).toBe(77) -- arrivé le premier
				expect(top[1].name).toBe("User77")
				expect(top[2].userId).toBe(88)
				expect(top[2].name).toBe("")
				expect(top[2].value).toBe(5)
			end
		)

		it("panne de UserService : name vide, aucun avertissement ; tableau du serveur en direct", function()
			local w = world()
			local p = join(w, 1)
			local q = join(w, 2)
			w.h.userInfoFails = true
			local store = w.h.game.DataStoreService:GetOrderedDataStore("Weekly_stamps_" .. tostring(week(w)))
			store:SetAsync("55", w.L.encode(9, 10, false))
			w.Signals.Stamped:Fire(p, 2)
			w.Signals.Stamped:Fire(q, 3)
			w.Clock.advance(121)
			w.L.step(w.Clock.now())
			w.h:settle(5)
			local states = w.h:sentTo(p, "LeaderboardState")
			local board = states[#states][1].boards.stamps
			expect(board.top[1].name).toBe("")
			expect(board.server[1].userId).toBe(2)
			expect(board.server[2].userId).toBe(1)
			expect(board.myServerRank).toBe(2)
			expect(board.mine).toBe(2)
		end)
	end)

	describe("LeaderboardService › semaine, statue, fanfare", function()
		it(
			"changement de semaine : prev, valeurs à 0 ; titres du top 10 de la semaine passée par unlockSession",
			function()
				local w = world()
				local p = join(w, 1)
				w.Signals.Stamped:Fire(p, 7)
				flush(w)
				w.Clock.advance(w.Clock.untilNextWeek() + 5)
				Brains.frames(w, 1)
				w.h:settle(5)
				local wk = w.DS.get(p).weekly
				expect(wk.stamps).toBe(0)
				expect(wk.prev.stamps).toBe(7)
				expect(wk.week).toBe(week(w))
				expect(w.C.hasCosmetic(p, "title", "stamp_hunter")).toBe(true)
			end
		)

		it("arrivée la semaine suivante : prev rempli, titre accordé à l'arrivée", function()
			local last
			local w = Brains.boot(Harness, {
				t0 = T0,
				stubMeta = false,
				before = function(w0)
					-- top 10 de la semaine passée déjà écrit (avant le démarrage de ce serveur)
					last = math.floor((w0.Clock.unix() - 345600) / 604800) - 1
					local L0 = w0.h:require(S .. "LeaderboardService")
					local store =
						w0.h.game.DataStoreService:GetOrderedDataStore("Weekly_combo_" .. tostring(last))
					store:SetAsync("1", L0.encode(4, 10, false))
				end,
			})
			w.L = w.h:require(S .. "LeaderboardService")
			w.C = w.h:require(S .. "CommunityService")
			w.h:settle(3)
			local p = join(w, 1, function(d)
				d.weekly.week = last
				d.weekly.combo = 4
			end)
			w.h:settle(5)
			expect(w.DS.get(p).weekly.prev.combo).toBe(4)
			expect(w.DS.get(p).weekly.combo).toBe(0)
			expect(w.C.hasCosmetic(p, "title", "combo_star")).toBe(true)
		end)

		it(
			"statue : plus gros squishy du serveur (nom vide si caché) ; fanfare du premier à 1e6",
			function()
				local w = world()
				local small = join(w, 1)
				local big = Brains.join(w, 2, {
					profile = Brains.profile(w, { squishies = { { s = 3, m = 2, z = 2e6 } } }),
				})
				w.DS.get(big).settings.hideName = true
				Brains.frames(w, 25)
				local statue = w.h.game.Workspace:FindFirstChild("Statue", true)
				expect(statue ~= nil).toBe(true)
				expect(statue:GetAttribute("StatueSpecies")).toBe(3)
				expect(statue:GetAttribute("StatueName")).toBe("")
				expect(statue:GetAttribute("StatueSize") >= 2e6).toBe(true)
				expect(#Bots.celebrations(big, "fanfare")).toBe(1)
				expect(#Bots.celebrations(small, "fanfare")).toBe(0)
				Brains.frames(w, 25)
				expect(#Bots.celebrations(big, "fanfare")).toBe(1) -- une fois par seuil et par serveur
			end
		)
	end)

	describe("LeaderboardService › revue", function()
		it(
			"deux records dans le même lot : l'heure d'arrivée est celle du DERNIER record (égalités justes)",
			function()
				local w = world()
				local p = join(w, 1)
				w.Signals.Stamped:Fire(p, 2)
				w.Clock.advance(30)
				w.Signals.Stamped:Fire(p, 1) -- 3 tampons atteints 30 s plus tard
				local expected = math.floor(w.Clock.unix() - (week(w) * 604800 + 345600))
				flush(w)
				local data = storeData(w, "stamps", week(w))
				local score, s = w.L.decode(data["1"])
				expect(score).toBe(3)
				expect(s).toBe(expected)
			end
		)

		it("fermeture du serveur : le lot en attente est écrit (BindToClose), rien n'est perdu", function()
			local w = world()
			local p = join(w, 1)
			w.L.step(w.Clock.now()) -- premier lot (vide) : le suivant n'est dû que dans 60 s
			w.Signals.Stamped:Fire(p, 4)
			w.h:close()
			w.h:settle(3)
			local data = storeData(w, "stamps", week(w))
			expect(data ~= nil and data["1"] ~= nil).toBe(true)
			expect(w.L.decode(data["1"])).toBe(4)
		end)

		it(
			"lot encore en vol au changement de semaine : les records de la semaine finie vont dans SON magasin",
			function()
				local w = world()
				local p = join(w, 1)
				local q = join(w, 2)
				local wk0 = week(w)
				local cm = MockInstance.classMethods.OrderedDataStore
				local original = cm.UpdateAsync
				local gate = { open = false, waiting = {} }
				cm.UpdateAsync = function(self, key, fn)
					if not gate.open then
						table.insert(gate.waiting, coroutine.running())
						coroutine.yield()
					end
					return original(self, key, fn)
				end
				local function open()
					gate.open = true
					for _, thread in gate.waiting do
						task.spawn(thread)
					end
					table.clear(gate.waiting)
				end
				local ok, err = pcall(function()
					w.Signals.Stamped:Fire(p, 2)
					flush(w) -- lot de p bloqué en vol
					w.Clock.advance(w.Clock.untilNextWeek() - 30)
					w.Signals.Stamped:Fire(q, 5) -- record de q, semaine finie
					w.Clock.advance(31) -- lundi 00:00 : nouvelle semaine pendant que le lot est en vol
					w.L.step(w.Clock.now())
					w.Clock.advance(61)
					w.L.step(w.Clock.now())
					open()
					w.h:settle(5)
					w.Clock.advance(61)
					w.L.step(w.Clock.now())
					w.h:settle(5)
				end)
				cm.UpdateAsync = original
				open()
				expect(ok, tostring(err)).toBe(true)
				local old = storeData(w, "stamps", wk0)
				local new = storeData(w, "stamps", wk0 + 1)
				expect(old ~= nil and old["2"] ~= nil).toBe(true)
				expect(w.L.decode(old["2"])).toBe(5)
				expect(new == nil or new["2"] == nil).toBe(true)
			end
		)
	end)

	-- =========================================================================================
	-- v2.0 (lot A4, étape 6, D28 ; journal A4-46)
	-- =========================================================================================
	describe("LeaderboardService › v2.0 : Livre des records et « Plus généreux » (D28)", function()
		local HarnessV2 = setmetatable({
			new = function(options)
				local hh = Harness.new(options)
				hh:require("ReplicatedStorage.Shared.Config.Features").Defaults.SchemaV2 = true
				return hh
			end,
		}, { __index = Harness })
		local FLAGS =
			{ "RecordR", "Confetti", "JellyAscend", "PetitSplorch", "Hearts", "Carnet", "UpgradesScreen" }
		-- valeurs repères du Livre des records de p (introuvables ailleurs)
		local CONFETTI_TOTAL, HEARTS, BOUGHT = 777001, 77701, 77801

		-- une valeur repère dans une charge utile (tables imbriquées comprises)
		local function carries(value, marks, depth)
			depth = depth or 0
			if type(value) == "number" then
				return marks[value] == true
			end
			if type(value) ~= "table" or depth > 12 then
				return false
			end
			for k, v in value do
				if carries(k, marks, depth + 1) or carries(v, marks, depth + 1) then
					return true
				end
			end
			return false
		end

		-- valeur d'une clé dans une charge utile, la moins profonde d'abord (parcours en largeur)
		local function keyOf(value, key)
			local queue = { value }
			local i = 1
			while i <= #queue and i < 5000 do
				local t = queue[i]
				i += 1
				if type(t) == "table" then
					if t[key] ~= nil then
						return t[key]
					end
					for _, v in t do
						if type(v) == "table" then
							table.insert(queue, v)
						end
					end
				end
			end
			return nil
		end

		it(
			"Petit Splorch : « Plus généreux » + 0 ; Livre des records au seul propriétaire (DataSnapshot puis DataPatch), jamais à un autre joueur",
			function()
				local w = Brains.boot(HarnessV2, { t0 = 1800000000 + 60, stubMeta = false })
				w.L = w.h:require(S .. "LeaderboardService")
				for _, key in FLAGS do
					assert(w.Features.set(key, true), key)
				end
				-- p : après une Ascension (A = 1, Record R 15), remonte à r = 3 : prochain prestige = Petit Splorch
				local p = Brains.join(w, 1, {
					profile = Brains.profile(w, {
						coins = 1e12,
						R = 3,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 300000 }, { s = 3, z = 300 } },
						tiles = { snack = 6, decor = 4 },
						edit = function(d)
							d.bestR = 15
							d.ascend = 1
							d.confettiTotal = CONFETTI_TOTAL
							d.hearts.receivedTotal = HEARTS
							d.stats.upgradesBought = BOUGHT
						end,
					}),
				})
				local q = Brains.join(w, 2, {
					profile = Brains.profile(w, { squishies = { { s = 2, z = 500 }, { s = 5, z = 400 } } }),
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 30))
				Brains.frames(w, 2)
				-- 1) l'instantané du propriétaire porte les 5 champs du Livre des records
				local snaps = w.h:sentTo(p, "DataSnapshot")
				expect(#snaps >= 1).toBe(true)
				local snap = snaps[#snaps][1]
				expect(keyOf(snap, "confettiTotal")).toBe(CONFETTI_TOTAL)
				expect(keyOf(snap, "bestR")).toBe(15)
				expect(keyOf(snap, "ascend")).toBe(1)
				expect(keyOf(snap, "receivedTotal")).toBe(HEARTS)
				expect(keyOf(snap, "upgradesBought")).toBe(BOUGHT)
				-- 2) niveau acheté et cœur reçu, puis Petit Splorch (hors file) : « Plus généreux » inchangé,
				-- aucun Splorched
				local patches0 = #w.h:sentTo(p, "DataPatch")
				local level = w.DS.get(p).tiles.snack
				local bought = w.Economy.buyUpgrade(p, "snack", 1, level)
				expect({ to = bought and bought.to, reason = bought and bought.reason }).toEqual({
					to = level + 1,
					reason = nil,
				})
				w.h:fireServer("ReplicatedStorage.Remotes.GiveHeart", q, p.UserId)
				Brains.frames(w, 3)
				expect(w.DS.get(p).hearts.receivedTotal).toBe(HEARTS + 1)
				expect(w.DS.get(p).stats.upgradesBought).toBe(BOUGHT + 1)
				local splorched = 0
				w.Signals.Splorched:Connect(function()
					splorched += 1
				end)
				local generous0 = w.DS.get(p).weekly.generous
				w.h:fireServer("ReplicatedStorage.Remotes.GrandSplorch", p, false, "2")
				Brains.frames(w, 5)
				expect(w.DS.get(p).R).toBe(4)
				expect(splorched).toBe(0)
				expect(w.DS.get(p).weekly.generous).toBe(generous0)
				expect(w.DS.get(q).weekly.generous).toBe(0)
				-- 3) Confettis du Petit Splorch, cœur reçu, niveau acheté : DataPatch au propriétaire
				local total1 = w.DS.get(p).confettiTotal
				expect(total1 > CONFETTI_TOTAL).toBe(true)
				local after = {}
				for i, args in w.h:sentTo(p, "DataPatch") do
					if i > patches0 then
						table.insert(after, args)
					end
				end
				local newMarks = { [total1] = true, [HEARTS + 1] = true, [BOUGHT + 1] = true }
				for mark in newMarks do
					expect({ mark = mark, sent = carries(after, { [mark] = true }) }).toEqual({
						mark = mark,
						sent = true,
					})
				end
				-- 4) jamais à un autre joueur : aucun message à q (ni à tous) ne porte une valeur repère de p
				local marks = {
					[CONFETTI_TOTAL] = true,
					[HEARTS] = true,
					[BOUGHT] = true,
					[total1] = true,
					[HEARTS + 1] = true,
					[BOUGHT + 1] = true,
				}
				for _, e in w.h.log.clientEvents do
					if e.player ~= p then
						expect({ remote = e.remote, leak = carries(e.args, marks) }).toEqual({
							remote = e.remote,
							leak = false,
						})
					end
				end
				for _, e in w.h.log.allClientEvents do
					expect({ remote = e.remote, leak = carries(e.args, marks) }).toEqual({
						remote = e.remote,
						leak = false,
					})
				end
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)
	end)
end
