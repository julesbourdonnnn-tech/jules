--!nocheck
-- Soak_queue (lot A2, étape 3 ; docs/04 §27.10, §27.13 « Specs nouvelles nées de la critique » ; GDD
-- v2.0 §2.4, §4.24.1 clé queueWaitNewcomer, §4.27 Petit Splorch) : robot de longue durée de la file des
-- grands spectacles avec la progression v2.0 ouverte. 16 robots sur un serveur v2 :
--   * 8 vétérans après une Ascension (Record R 60) qui enchaînent les Petits Splorch HORS file (une
--     boucle de 30 à 60 s, bien plus court que les 4 à 9 min mesurées : charge maximale) ; l'un d'eux
--     fait d'abord sa Jelly Ascend DANS la file, puis remonte en Petits Splorch ;
--   * 8 nouveaux remplacés un par un (environ un Grand Splorch par minute, GDD §4.15), chacun lance son
--     premier Grand Splorch dès qu'il est prêt.
-- Contrôles : attente médiane du premier Grand Splorch d'un nouveau ≤ 40 s (queueWaitNewcomer) ; aucun
-- Petit Splorch dans la file (ni place, ni attente) ; file équitable (départs dans l'ordre d'arrivée) ;
-- Invariants.profile toutes les secondes ; Record R jamais en baisse, Confettis jamais négatifs, A jamais
-- deux fois ; aucun état au-delà de son délai ; instances, connexions, threads et handlers stables ;
-- fermeture (BindToClose) à pleine charge ; zéro trace. SOAK_HOURS (0,5 h par défaut).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Soak = require("../harness/Soak")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local L = "ReplicatedStorage.Shared."
	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local VETERANS = 8
	local NEWCOMERS = 8
	local ASCENDER = 1 -- le vétéran n° 1 fait sa Jelly Ascend dans la file, puis remonte

	local function signalHandlers(w)
		local n = 0
		for _, signal in w.Signals do
			if type(signal) == "table" and type(signal._handlers) == "table" then
				n += #signal._handlers
			end
		end
		return n
	end

	local function median(list)
		local sorted = table.clone(list)
		table.sort(sorted)
		local n = #sorted
		if n == 0 then
			return math.huge
		end
		if n % 2 == 1 then
			return sorted[(n + 1) / 2]
		end
		return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
	end

	describe("Soak_queue › 16 robots, vétérans en Petits Splorch, nouveaux en file", function()
		it(
			`{Soak.hours()} h de temps simulé : attente médiane du 1er Grand Splorch d'un nouveau ≤ 40 s, aucun Petit Splorch en file, file équitable, rien qui fuit, zéro trace`,
			function()
				local hours = Soak.hours()
				local t0 = 1800000000 + 3600 * 24 * 2 + 50
				local w = Brains.boot(HarnessV2, { t0 = t0 })
				for _, key in { "RecordR", "Confetti", "JellyAscend", "PetitSplorch" } do
					assert(w.Features.set(key, true), key)
				end
				w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				local Invariants = w.h:require(L .. "Logic.Invariants")
				local Prestige = w.h:require(L .. "Logic.Prestige")
				local rng = Brains.rng(4242)
				local problems = {}
				local function problem(line)
					if #problems < 30 then
						table.insert(problems, string.format("t+%.1f : %s", w.Clock.now() - t0, line))
					end
				end

				-- profils
				local function veteranProfile(i)
					local ascender = i == ASCENDER
					return Brains.profile(w, {
						coins = math.floor(rng:NextNumber(0, 1e6)),
						R = if ascender then 15 else rng:NextInteger(0, 8),
						squishies = {
							{ s = 1, z = 100, bf = 1 },
							{ s = 2 + (i % 10), z = 50 },
							{ s = 3, z = 40 },
							{ s = 5, z = 30, at = "dodo" },
						},
						edit = function(d)
							d.bestR = if ascender then 15 else 60
							d.ascend = if ascender then 0 else 3
							d.regainBonusA = 0
						end,
					})
				end
				local function newcomerProfile()
					return Brains.profile(w, {
						coins = 200,
						squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 16000 }, { s = 9, z = 20 } },
					})
				end

				-- état des robots
				local veterans = {} -- [Player] = { next = Clock.now() du prochain Petit Splorch, petits = n }
				local newcomers = {} -- [Player] = { enqueuedAt?, startedAt?, leaveAt? }
				local newcomerById = {} -- [userId] = même table (départ du spectacle par Signals)
				local waits = {}
				local entries = {} -- { userId, enqueuedAt, startedAt? } de chaque entrée de la file
				local bestSeen = {}
				local confettiSeen = {}
				local ascendSeen = {}
				local nextUserId = 100
				local function place(p)
					Bots.place(p, Brains.atRanch(w, p, 0, 30))
				end
				for i = 1, VETERANS do
					local p = Brains.join(w, i, { profile = veteranProfile(i) })
					place(p)
					veterans[p] = { next = w.Clock.now() + rng:NextNumber(5, 40), petits = 0, index = i }
				end
				local function addNewcomer()
					nextUserId += 1
					local p = Brains.join(w, nextUserId, { profile = newcomerProfile() })
					place(p)
					local n = {}
					newcomers[p] = n
					newcomerById[p.UserId] = n
					return p
				end
				for _ = 1, NEWCOMERS do
					addNewcomer()
				end
				w.Signals.SpectacleStarted:Connect(function(kind, userId, t)
					if kind ~= "splorch" then
						return
					end
					for _, e in entries do
						if e.userId == userId and e.startedAt == nil then
							e.startedAt = t
							break
						end
					end
					local n = newcomerById[userId]
					if n ~= nil and n.enqueuedAt ~= nil and n.startedAt == nil then
						n.startedAt = t
						n.leaveAt = t + 20
						table.insert(waits, t - n.enqueuedAt)
					end
				end)
				Brains.frames(w, 50)
				local base = w.h:counts()
				local baseHandlers = signalHandlers(w)
				local nextNewcomer = w.Clock.now() + rng:NextNumber(5, 20)
				local pending = nil -- nouveau qui lance son premier Grand Splorch maintenant
				local ascended = false
				local totalTicks = math.floor(hours * 3600 / Bots.DT)
				Bots.use(w)
				for tick = 1, totalTicks do
					local now = w.Clock.now()
					-- vétérans : la boucle finit (plus gros à l'objectif de r), puis le Petit Splorch
					for p, v in veterans do
						if p.Parent ~= nil and w.DS.isLoaded(p) then
							local data = w.DS.get(p)
							if v.index == ASCENDER and not ascended and now >= t0 + 60 then
								Bots.fire("JellyAscend", p, true)
								if w.Splorch.queuedKind(p) == "ascend" then
									ascended = true
									table.insert(
										entries,
										{ userId = p.UserId, enqueuedAt = now, ascend = true }
									)
								end
							elseif
								now >= v.next
								and now >= (v.recordDue or now)
								and w.Splorch.canPrestige(p)
								and data.ascend >= 1
							then
								-- remontée : boucles de 30 à 60 s ; boucle record (Grand Splorch dans la file) : 5 à
								-- 10 min (33 à 108 min mesurées, GDD §4.27)
								local record = Prestige.nextKind(data) == "splorch"
								if record and v.recordDue == nil then
									v.recordDue = now + rng:NextNumber(300, 600)
									continue
								end
								v.recordDue = nil
								v.next = now + rng:NextNumber(30, 60)
								local target = Prestige.target(Prestige.r(data))
								local uid = "2"
								if data.squishies[uid] then
									w.Economy.settle(p)
									data.squishies[uid].z = math.max(data.squishies[uid].z, target * 1.05)
									w.Economy.refresh(p)
									local R0 = data.R
									w.RateLimit.clear(p)
									Bots.fire("GrandSplorch", p, false, uid)
									if data.R == R0 + 1 then
										v.petits += 1
									elseif w.Splorch.queuedKind(p) == "splorch" then
										-- Grand Splorch record (retour au record dépassé) : file normale
										table.insert(entries, { userId = p.UserId, enqueuedAt = now })
									end
								end
							end
							-- jamais de Petit Splorch dans la file
							if
								w.Splorch.queuedKind(p) == "splorch"
								and not Prestige.isRecord(Prestige.r(data) + 1, Prestige.bestR(data))
							then
								problem("Petit Splorch en file : " .. p.UserId)
							end
						end
					end
					-- nouveaux : un premier Grand Splorch de nouveau environ toutes les minutes (GDD §4.15 : « sur un
					-- serveur de nouveaux joueurs, il y a environ un Grand Splorch par minute ») ; un nouveau qui n'a
					-- pas encore lancé le sien, sinon le plus ancien qui a fini (parti 20 s après son spectacle)
					-- est remplacé par un nouveau qui le lance
					if pending ~= nil and (pending.Parent == nil or newcomers[pending] == nil) then
						pending = nil
					end
					if pending == nil and now >= nextNewcomer then
						for p, n in newcomers do
							if n.enqueuedAt == nil and (pending == nil or p.UserId < pending.UserId) then
								pending = p
							end
						end
						if pending == nil then
							local oldest, oldestAt = nil, math.huge
							for p, n in newcomers do
								if n.leaveAt ~= nil and now >= n.leaveAt and n.leaveAt < oldestAt then
									oldest, oldestAt = p, n.leaveAt
								end
							end
							if oldest ~= nil then
								newcomers[oldest] = nil
								newcomerById[oldest.UserId] = nil
								Bots.leave(oldest)
								w.h:settle(2)
								pending = addNewcomer()
							end
						end
						nextNewcomer = now + rng:NextNumber(45, 75)
					end
					if pending ~= nil and w.DS.isLoaded(pending) then
						local n = newcomers[pending]
						w.RateLimit.clear(pending)
						Bots.fire("GrandSplorch", pending, false, "2")
						if w.Splorch.queued(pending) ~= nil then
							n.enqueuedAt = now
							table.insert(entries, { userId = pending.UserId, enqueuedAt = now })
							pending = nil
						end
					end
					Bots.frame(Bots.brains)
					-- contrôles
					now = w.Clock.now()
					for _, line in Brains.expiredStates(w, now) do
						problem("état expiré : " .. line)
					end
					if tick % 10 == 0 then
						for _, p in w.players do
							if p.Parent ~= nil and w.DS.isLoaded(p) then
								local data = w.DS.get(p)
								for _, v in Invariants.profile(data) do
									problem("profil " .. p.UserId .. " : " .. v)
								end
								local id = p.UserId
								local best, conf, A =
									Prestige.bestR(data), data.confetti, Prestige.ascend(data)
								if bestSeen[id] and best < bestSeen[id] then
									problem("Record R en baisse " .. id)
								end
								if confettiSeen[id] and (conf < 0 or conf < confettiSeen[id]) then
									problem("Confettis en baisse " .. id)
								end
								if ascendSeen[id] and A > ascendSeen[id] + 1 then
									problem("deux Ascensions " .. id)
								end
								bestSeen[id], confettiSeen[id], ascendSeen[id] = best, conf, A
							end
						end
					end
					if tick % 100 == 0 then
						local c = w.h:counts()
						local handlers = signalHandlers(w)
						local function stable(name, value, ref)
							if value > ref * 1.05 + 200 then
								problem(string.format("%s en hausse : %d → %d", name, ref, value))
							end
						end
						stable("instances", c.instances, base.instances)
						stable("connexions", c.connections, base.connections)
						stable("threads", c.threads, base.threads + 50)
						stable("handlers des Signals", handlers, baseHandlers)
					end
					if #problems >= 30 then
						break
					end
				end
				-- file équitable : départs dans l'ordre d'arrivée
				local started = {}
				for _, e in entries do
					if e.startedAt ~= nil then
						table.insert(started, e)
					end
				end
				table.sort(started, function(a, b)
					return a.enqueuedAt < b.enqueuedAt
				end)
				for i = 2, #started do
					if started[i].startedAt < started[i - 1].startedAt then
						problem(
							string.format(
								"file inéquitable : %d arrivé avant %d, parti après",
								started[i - 1].userId,
								started[i].userId
							)
						)
					end
				end
				-- l'Ascension est passée par la file, une seule fois ; les vétérans ont enchaîné les Petits Splorch
				local ascender = nil
				local petits = 0
				for p, v in veterans do
					petits += v.petits
					if v.index == ASCENDER then
						ascender = p
					end
				end
				expect(ascended).toBe(true)
				expect(w.DS.get(ascender).ascend).toBe(1)
				local queuedAscend = 0
				for _, e in entries do
					if e.ascend and e.startedAt ~= nil then
						queuedAscend += 1
					end
				end
				expect(queuedAscend).toBe(1)
				expect(petits >= math.floor(VETERANS * hours * 3600 / 60 * 0.6)).toBe(true)
				-- attente médiane du premier Grand Splorch d'un nouveau
				local m = median(waits)
				print(
					string.format(
						"  Soak_queue : %.2f h, %d Petits Splorch, %d premiers Grands Splorch, attente médiane %.1f s (max %.1f s)",
						hours,
						petits,
						#waits,
						m,
						if #waits > 0 then math.max(table.unpack(waits)) else 0
					)
				)
				expect(#waits >= math.floor(hours * 3600 / 75 * 0.6)).toBe(true)
				expect(m <= 40).toBe(true)
				-- fermeture à pleine charge
				w.h:close()
				w.h:settle(3)
				for _, line in Brains.problems(w) do
					problem("trace : " .. line)
				end
				expect(table.concat(problems, "\n")).toBe("")
			end
		)
	end)
end
