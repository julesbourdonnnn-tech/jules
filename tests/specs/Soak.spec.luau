--!nocheck
-- Robot de longue durée (intégration, docs/04 §17.1 c, §17.2, §18.3) : serveur complet avec les vrais
-- services du paquet meta, 16 robots (joueurs complets, cavaliers, tricheurs bornés ; gigue et gels
-- réseau ; départs, retours et réapparitions), SOAK_HOURS heures de temps simulé (0,5 h par défaut,
-- 6 h dans scripts/soak.sh). Tous les invariants du §17.2 sont vérifiés À CHAQUE TICK par
-- tests/harness/Soak.luau (profils, uids, capacités, états minutés, plafonds, fuites du Rush, sieste de
-- Big Plop, clôture pendant l'attente du Grand Splorch ; instances, connexions, threads et handlers
-- stables), puis ici : temps du tick du serveur < 10 ms en moyenne sous Lune, fermeture (BindToClose)
-- à pleine charge, DiagnosticsService.counts() à zéro (invariant 9), zéro trace. v2.0 (lot A3) : les
-- mêmes robots avec 6 Plopettes chacun (interrupteur Helpers ouvert, serveur v2). Lot I, étape 6 (plan I
-- T3, D11) : le Soak principal joue la configuration de lancement (les 23 interrupteurs v2.0 ouverts)
-- avec des Ascensions (2 héros : Jelly Ascend puis Petits Splorch ; Record R jamais en baisse, aucun
-- squishy d'un héros perdu, Confettis jamais négatifs, à chaque tick) ; un Soak court joue la coupure
-- d'urgence (SchemaV2 ouvert, les 22 autres coupés : aucune intention v2.0 répondue, aucun champ v2
-- écrit).
local Soak = require("../harness/Soak")
local Brains = require("../harness/Brains")
local Flags = require("../harness/Flags")
local MockInstance = require("../harness/MockInstance")

-- Taille approchée d'une valeur sur le fil (octets ; même estimation que ClientReplay)
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

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("Soak › 16 robots, invariants à chaque tick", function()
		it(
			`{Soak.hours()} h de temps simulé, configuration de lancement, Ascensions : aucun invariant violé, tick < 10 ms, zéro trace`,
			function()
				local hours = Soak.hours()
				-- héros des Ascensions (robots 1 et 9, aussi à leur retour) : Record R 15, prêts pour la
				-- Jelly Ascend ; leur cerveau ne fusionne ni ne lance jamais (aucun squishy ne part par son
				-- propre geste : tout uid perdu est un défaut du serveur)
				local HEROES = { [1] = true, [9] = true }
				local best, confettiBad, kept = {}, {}, {}
				local ascended, petit, lastR, lastA = {}, 0, {}, {}
				local Prestige, startR = nil, nil
				-- M8 (plan I) : poids de l'instantané des améliorations dans les DataPatch, 16 joueurs, les
				-- 10 premières minutes (hors du temps mesuré du tick ensuite)
				local wire = { patches = 0, withSnap = 0, snapBytes = 0, patchBytes = 0, hooked = false }
				local prevFire = MockInstance.onFireClient
				local function unhook()
					if wire.hooked then
						MockInstance.onFireClient = prevFire
						wire.hooked = false
					end
				end
				local function bestOf(d)
					return Prestige.bestR(d)
				end
				local report = Soak.run(Harness, {
					players = 16,
					hours = hours,
					seed = 42,
					edit = function(d, i, w)
						if HEROES[i] then
							Prestige = Prestige or w.h:require("ReplicatedStorage.Shared.Logic.Prestige")
							startR = startR or Prestige.startR(1, 0)
							d.R = 15
							d.bestR = 15
							d.tiles.snack = math.max(d.tiles.snack or 0, 12)
							d.tiles.decor = math.max(d.tiles.decor or 0, 10)
							-- après l'Ascension : chaque squishy de l'enclos vaut un Petit Splorch
							local target = w.Formulas.splorchTarget(startR + 2)
							for _, rec in d.squishies do
								rec.z = math.max(rec.z, math.ceil(target * 1.05))
							end
						end
					end,
					brainFor = function(w, i, seed)
						if HEROES[i] then
							return Brains.player(w, seed, { keepAll = true })
						end
						return nil
					end,
					check = function(w, _now)
						local out = {}
						Prestige = Prestige or w.h:require("ReplicatedStorage.Shared.Logic.Prestige")
						w.ascendTick = (w.ascendTick or 0) + 1
						if w.ascendTick == 1 then
							wire.hooked = true
							MockInstance.onFireClient = function(remote, player, ...)
								if prevFire then
									prevFire(remote, player, ...)
								end
								if remote.Name == "DataPatch" then
									local patch = ...
									wire.patches += 1
									wire.patchBytes += bytes(patch) + bytes(select(2, ...)) + bytes(
										select(3, ...)
									)
									if type(patch) == "table" and patch.upgradeSnapshot ~= nil then
										wire.withSnap += 1
										wire.snapBytes += bytes(patch.upgradeSnapshot)
									end
								end
							end
						elseif w.ascendTick == 6000 then
							unhook()
						end
						for _, p in w.players do
							if p.Parent ~= nil and w.DS.isLoaded(p) then
								local id = p.UserId
								local d = w.DS.get(p)
								local b = bestOf(d)
								if b < (best[id] or 0) then
									table.insert(out, `Record R en baisse {id} : {best[id]} → {b}`)
								end
								best[id] = math.max(best[id] or 0, b)
								if
									not (type(d.confetti) == "number" and d.confetti >= 0)
									and not confettiBad[id]
								then
									confettiBad[id] = true
									table.insert(out, `Confettis négatifs {id} : {tostring(d.confetti)}`)
								end
								if HEROES[id] then
									-- aucun squishy du héros perdu (renaissances comprises)
									local now = {}
									for uid in d.squishies do
										now[uid] = true
									end
									for uid in kept[id] or {} do
										if not now[uid] then
											table.insert(out, `squishy perdu {id} : {uid}`)
										end
									end
									kept[id] = now
									-- Ascensions et Petits Splorch comptés
									if (d.ascend or 0) > (lastA[id] or 0) and lastA[id] ~= nil then
										ascended[id] = (ascended[id] or 0) + 1
									end
									if lastR[id] ~= nil and d.R == lastR[id] + 1 and (d.ascend or 0) >= 1 then
										petit += 1
									end
									lastA[id], lastR[id] = d.ascend or 0, d.R
									-- toutes les 5 min (et dès 10 s) : la Jelly Ascend demandée (refus muet sinon) ;
									-- avant la première du héros, toutes les 10 s (relecture du lot I, I-59 : le serveur
									-- la refuse en silence quand le robot porte un squishy ou n'est pas dans son ranch ;
									-- 6 essais en 0,5 h ne suffisaient pas toujours, cas rouge 3 fois sur 4)
									local every = if (ascended[id] or 0) >= 1 then 3000 else 100
									if w.ascendTick % every == 100 % every then
										w.h:fireServer("ReplicatedStorage.Remotes.JellyAscend", p, true)
									end
								end
							end
						end
						return out
					end,
				})
				unhook()
				local w = report.world
				-- toute la durée a été jouée (aucun arrêt anticipé sur 50 problèmes)
				expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
				expect(report.serverTicks >= report.ticks).toBe(true)
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.msPerTick < 10).toBe(true)
				-- M8 : l'instantané part dans des patchs (écran ouvert ou non : le serveur ne le sait pas) ;
				-- débit par joueur sous le budget du réseau (8 Ko/s en moyenne, docs/04 §18.3)
				local seconds = math.min(report.ticks, 6000) * 0.1
				expect(wire.withSnap > 0).toBe(true)
				local perPlayer = (wire.patchBytes / seconds) / 16
				expect(perPlayer < 8 * 1024).toBe(true)
				print(
					string.format(
						"  Soak M8 : %d DataPatch en %.0f s (16 joueurs), %d avec l'instantané (%.0f o en moyenne), instantané %.0f o/s par joueur, DataPatch %.0f o/s par joueur",
						wire.patches,
						seconds,
						wire.withSnap,
						wire.snapBytes / math.max(1, wire.withSnap),
						wire.snapBytes / seconds / 16,
						perPlayer
					)
				)
				-- configuration de lancement : les 23 clés v2.0 ouvertes, profils v2
				for _, key in Flags.V2_KEYS do
					expect({ key = key, on = w.Features.get(key) }).toEqual({ key = key, on = true })
				end
				expect(w.Schema.VERSION).toBe(2)
				-- les deux héros sont montés (Jelly Ascend) ; des Petits Splorch ont suivi
				local heroes = 0
				for id in HEROES do
					expect({ hero = id, ascended = (ascended[id] or 0) >= 1 }).toEqual({
						hero = id,
						ascended = true,
					})
					heroes += 1
				end
				expect(petit >= heroes).toBe(true)
				-- invariant 9 (docs/04 §17.2) : aucune erreur attrapée ni avertissement compté en ligne
				local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				local counts = D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(#D.caught()).toBe(0)
				local chaseGuard = w.h:require("ServerScriptService.Server.Chase.Guard")
				local metaGuard = w.h:require("ServerScriptService.Server.Meta.Guard")
				local stubs = {}
				for where, err in chaseGuard.stubbed do
					table.insert(stubs, where .. " : " .. err)
				end
				for where, err in metaGuard.stubbed do
					table.insert(stubs, where .. " : " .. err)
				end
				expect(table.concat(stubs, "\n")).toBe("")
				print(
					string.format(
						"  Soak : %.2f h, %d ticks, %.2f ms par tick du serveur, %d joueurs à la fin, instances %d → %d, %d Ascensions, %d Petits Splorch des héros",
						hours,
						report.ticks,
						report.msPerTick,
						report.players,
						report.counts.start.instances,
						report.counts.finish.instances,
						(ascended[1] or 0) + (ascended[9] or 0),
						petit
					)
				)
			end
		)
	end)

	-- v2.0 (lot A3) : les mêmes 16 robots avec 6 Plopettes chacun (Record R 12 + Plume), serveur v2
	-- (SchemaV2 ouvert dans le harnais avant le premier require du schéma, recette de DataChaos),
	-- interrupteur Helpers ouvert ; la moitié de la durée du Soak (0,25 h par défaut)
	describe("Soak › 16 robots × 6 Plopettes (lot A3)", function()
		it(
			`{Soak.hours() / 2} h : invariants, sauts ≤ 3 s, aucune fuite d'état, zéro trace, coût du tick`,
			function()
				local L = "ReplicatedStorage.Shared."
				local HarnessV2 = setmetatable({
					new = function(options)
						local hh = Harness.new(options)
						hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
						return hh
					end,
				}, { __index = Harness })
				local hours = Soak.hours() / 2
				local helperStep = { spent = 0, n = 0 }
				local MaxTravel = nil
				local report = Soak.run(HarnessV2, {
					players = 16,
					hours = hours,
					seed = 7,
					flags = { "Helpers" },
					edit = function(d, _i)
						d.bestR = 12
						d.atelier[8] = 1 -- Plume (Config/Upgrades.WorkshopIndex.plume)
					end,
					check = function(w, now)
						local out = {}
						local Helper = w.h:require("ServerScriptService.Server.Services.HelperService")
						if MaxTravel == nil then
							MaxTravel = w.Balance.Helpers.MaxTravel
							-- coût du step des Plopettes (os.clock réel), mesuré dans le tick
							local step = Helper.step
							Helper.step = function(t, acting)
								local t0 = os.clock()
								step(t, acting)
								helperStep.spent += os.clock() - t0
								helperStep.n += 1
							end
						end
						local present = 0
						for _, p in w.players do
							if p.Parent ~= nil then
								present += 1
								for _, h in Helper.helpers(p) do
									if h.moving then
										if h.tPress - now > MaxTravel + 1e-6 then
											table.insert(out, "saut de plus de 3 s : " .. p.UserId)
										end
										if now - h.tPress > 0.11 + 1e-6 then
											table.insert(out, "saut non résolu à tPress : " .. p.UserId)
										end
									end
								end
							end
						end
						if Helper.counters().Owners > present then
							table.insert(out, "état d'un propriétaire parti gardé")
						end
						return out
					end,
				})
				local w = report.world
				expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.msPerTick < 10).toBe(true)
				local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				local counts = D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(#D.caught()).toBe(0)
				local Helper = w.h:require("ServerScriptService.Server.Services.HelperService")
				local c = Helper.counters()
				expect(c.Pressed > 100).toBe(true)
				expect(c.Owners <= report.players).toBe(true) -- aucun état d'un joueur parti
				local ms = helperStep.spent / math.max(1, helperStep.n) * 1000
				expect(ms < 0.5).toBe(true)
				print(
					string.format(
						"  Soak Plopettes : %.2f h, %.2f ms par tick du serveur, %.3f ms par step des Plopettes, %d pressions d'aide, %d abandons, instances %d → %d",
						hours,
						report.msPerTick,
						ms,
						c.Pressed,
						c.Abandoned,
						report.counts.start.instances,
						report.counts.finish.instances
					)
				)
			end
		)
	end)

	-- Lot I, étape 6 (plan I D11) : la coupure d'urgence. SchemaV2 ne se coupe jamais ; LiveOps peut
	-- couper tout le reste : profils v2, chaque système v2.0 coupé. 16 robots, le quart de la durée
	-- (0,125 h par défaut), avec des intentions v2.0 envoyées par les robots (valides et hostiles) :
	-- invariants à chaque tick, zéro trace, aucune intention v2.0 répondue (aucun UpgradeResult, aucune
	-- célébration v2.0, aucun champ v2 dans un DataPatch, aucune clé features.v2), aucun champ v2 du
	-- profil changé entre le début et la fin pour les joueurs restés.
	describe("Soak › coupure d'urgence (SchemaV2 ouvert, le reste coupé)", function()
		it(
			`{Soak.hours() / 4} h : invariants, zéro trace, aucune intention v2.0 répondue, aucun champ v2 écrit`,
			function()
				local hours = Soak.hours() / 4
				local V2_KINDS = {
					petitSplorch = true,
					ascend = true,
					tier = true,
					unlock2 = true,
					confetti = true,
					trackTier = true,
					carnet = true,
					mastery = true,
					regainDone = true,
					recordStep = true,
					welcomeV2 = true,
				}
				local seen = { intents = 0, results = 0, celebrations = {}, patchKeys = {}, v2Features = 0 }
				local v2Keys, before, after = nil, {}, {}
				local totalTicks = math.floor(hours * 3600 / 0.1)
				local prevFire, prevAll = MockInstance.onFireClient, MockInstance.onFireAllClients
				local hooked = false
				local function unhook()
					if hooked then
						MockInstance.onFireClient, MockInstance.onFireAllClients = prevFire, prevAll
						hooked = false
					end
				end
				-- copie profonde par JSON (comme le DataStore) : comparée par toEqual, sans ordre de clés
				local function copyOf(w, t)
					local Http = w.h.game.HttpService
					return Http:JSONDecode(Http:JSONEncode(t))
				end
				local function snapshotV2(d)
					local out = {}
					for key in v2Keys do
						out[key] = d[key]
					end
					return out
				end
				local crng = Brains.rng(77)
				local INTENTS = {
					{ "BuyUpgrade", "snack", 1, 0 },
					{ "BuyUpgrade", "nope", 1e9, -1 },
					{ "JellyAscend", true },
					{ "PlaceDeco", 1, 1 },
					{ "GiveHeart", 2 },
					{ "SetPhotoMode", true },
					{ "SetPhotoMode", false },
					{ "MenuActivity" },
					{ "ClientMetric", "upgradeMode", 1 },
					{ "UiSeen", "nextBuy" },
					{ "EquipCosmetic", "palette", "peachPalette" },
					{ "SetSetting", "haloOn", true },
				}
				local report = Soak.run(Harness, {
					preset = "cut",
					players = 16,
					hours = hours,
					seed = 5,
					check = function(w, _now)
						w.cutTick = (w.cutTick or 0) + 1
						if w.cutTick == 1 then
							local Schema = w.Schema
							v2Keys = {}
							local v1 = Schema.defaultsFor(1)
							for key in Schema.defaultsFor(2) do
								-- bestR exclu : invariant v2 « Record R jamais sous r » tenu même RecordR coupé
								-- (EconomyService.applySplorch, journal A2-24, docs/04 §27.2) ; vérifié à part
								if v1[key] == nil and key ~= "version" and key ~= "bestR" then
									v2Keys[key] = true
								end
							end
							for _, p in w.players do
								if p.Parent ~= nil and w.DS.isLoaded(p) then
									before[p.UserId] = copyOf(w, snapshotV2(w.DS.get(p)))
								end
							end
							hooked = true
							local function watch(remote, payload)
								local name = remote.Name
								if name == "UpgradeResult" then
									seen.results += 1
								elseif
									name == "Celebrate"
									and type(payload) == "table"
									and V2_KINDS[payload.kind]
								then
									seen.celebrations[payload.kind] = true
								elseif name == "DataPatch" and type(payload) == "table" then
									for key in payload do
										if v2Keys[key] or key == "upgradeSnapshot" then
											seen.patchKeys[key] = true
										end
									end
								elseif name == "EventState" and type(payload) == "table" then
									if type(payload.features) == "table" and payload.features.v2 ~= nil then
										seen.v2Features += 1
									end
								end
							end
							MockInstance.onFireClient = function(remote, player, ...)
								if prevFire then
									prevFire(remote, player, ...)
								end
								watch(remote, (...))
							end
							MockInstance.onFireAllClients = function(remote, ...)
								if prevAll then
									prevAll(remote, ...)
								end
								watch(remote, (...))
							end
						end
						-- dernière image : champs v2 des joueurs présents (avant la fermeture)
						if w.cutTick == totalTicks then
							for _, p in w.players do
								if p.Parent ~= nil and w.DS.isLoaded(p) and before[p.UserId] then
									local d = w.DS.get(p)
									after[p.UserId] = {
										version = d.version,
										json = copyOf(w, snapshotV2(d)),
									}
								end
							end
						end
						-- une intention v2.0 toutes les 5 images, par un robot présent au hasard
						if w.cutTick % 5 == 0 then
							local present = {}
							for _, p in w.players do
								if p.Parent ~= nil and w.DS.isLoaded(p) then
									table.insert(present, p)
								end
							end
							if #present > 0 then
								local p = present[crng:NextInteger(1, #present)]
								local intent = INTENTS[crng:NextInteger(1, #INTENTS)]
								w.h:fireServer(
									"ReplicatedStorage.Remotes." .. intent[1],
									p,
									table.unpack(intent, 2)
								)
								seen.intents += 1
							end
						end
						return {}
					end,
				})
				unhook()
				local w = report.world
				expect(report.ticks).toBe(math.floor(hours * 3600 / 0.1))
				expect(table.concat(report.problems, "\n")).toBe("")
				expect(report.msPerTick < 10).toBe(true)
				-- coupure réelle : profils v2, chaque autre clé v2.0 coupée
				expect(w.Schema.VERSION).toBe(2)
				for _, key in Flags.V2_KEYS do
					expect({ key = key, on = w.Features.get(key) }).toEqual({
						key = key,
						on = key == "SchemaV2",
					})
				end
				local D = w.h:require("ServerScriptService.Server.Services.DiagnosticsService")
				local counts = D.counts()
				expect({ errors = counts.errors, warnings = counts.warnings }).toEqual({
					errors = 0,
					warnings = 0,
				})
				expect(#D.caught()).toBe(0)
				-- aucune intention v2.0 répondue
				expect(seen.intents > 100).toBe(true)
				expect(seen.results).toBe(0)
				expect(seen.celebrations).toEqual({})
				expect(seen.patchKeys).toEqual({})
				expect(seen.v2Features).toBe(0)
				-- aucun champ v2 écrit : champs v2 des joueurs présents au début et à la fin égaux (départs
				-- et retours compris : profil persisté puis relu)
				local compared = 0
				for userId, json in before do
					local a = after[userId]
					if a ~= nil then
						expect(a.version).toBe(2)
						expect({ id = userId, v2 = a.json }).toEqual({ id = userId, v2 = json })
						compared += 1
					end
				end
				expect(compared > 0).toBe(true)
				print(
					string.format(
						"  Soak coupé : %.2f h, %.2f ms par tick du serveur, %d intentions v2.0 envoyées, %d profils v2 comparés, instances %d → %d",
						hours,
						report.msPerTick,
						seen.intents,
						compared,
						report.counts.start.instances,
						report.counts.finish.instances
					)
				)
			end
		)
	end)
end
