--!nocheck
-- SplorchService_ascend (lot A2, étape 3 ; docs/04 §27.4, §27.5, §27.7, §27.10, §27.14 ; GDD v2.0
-- §4.15, §4.26, §4.27) : Petit Splorch hors file et Jelly Ascend dans la file, côté serveur.
--   * interrupteurs coupés (et profil v1, et RecordR coupé) : JellyAscend ne fait rien, le Grand Splorch
--     reste celui de la v1.3 (applySplorch : ni Confettis, ni cadeau du Splorch) ;
--   * Ascension complète : file du Grand Splorch, Celebrate « ascend » à tous (taille du Meilleur Ami
--     copiée au départ), Prestige.apply d'un seul bloc à 4,0 s, sauvegarde, Confettis par source, Fame
--     + 20 hors plafond, Pluie d'étoiles (3 par jour), bannière, attributs, PrestigeApplied ;
--   * chaque refus (confirmation, condition, ranch, portage, fuite, configuration refusée, session en
--     fin) sans mutation ; un seul prestige par joueur (Grand Splorch en file : « Ton Grand Splorch passe
--     d'abord ! ») ; JellyAscend deux fois dans la même image ;
--   * départ à 3,9 s (rien appliqué, place rendue) et à 4,1 s (appliqué et sauvegardé une fois), retour ;
--     sauvegarde en échec (la suivante écrit l'Ascension entière, jamais deux) ; fermeture (BindToClose)
--     avec 16 joueurs en file (rien appliqué pendant la fermeture, chaque profil entier) ;
--   * Petit Splorch : hors file, tout de suite, 1 Confetti, PetitSplorchAt, ni bannière ni cadeaux ni
--     Fame ; retour au record (+ 10, regainDone, memoryR) ; PetitSplorch coupé : dans la file ;
--   * Grand Splorch v2.0 : Prestige.apply (Record R, 3 + r Confettis, place offerte, cadeau du Splorch),
--     Fame dans le plafond de 50 par jour (remis à zéro le lendemain), bannière au plus toutes les 180 s,
--     plus gros vendu pendant l'attente (place rendue, rien remis à zéro) ;
--   * sonde « occupé » : aucun achat pendant le spectacle de l'Ascension ni l'animation du Petit Splorch.
-- Les interrupteurs v2.0 sont ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais avant
-- le premier require du schéma (recette de DataChaos).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~4 min
	local L = "ReplicatedStorage.Shared."
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local FLAGS = { "RecordR", "Confetti", "JellyAscend", "PetitSplorch" }

	-- opts : v1 (serveur v1), flags (liste ouverte, défaut FLAGS)
	local function boot(opts)
		opts = opts or {}
		local w = Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = opts.t0 or T0 })
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Invariants = w.h:require(L .. "Logic.Invariants")
		w.UM = w.h:require(L .. "Logic.UpgradeMath")
		w.World = w.h:require(S .. "WorldService")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in opts.flags or FLAGS do
			assert(w.Features.set(key, true), key)
		end
		w.banners = {}
		w.Signals.BannerRequested:Connect(function(kind, args, source)
			table.insert(w.banners, { kind = kind, args = args, source = source })
		end)
		w.prestiges = {}
		w.Signals.PrestigeApplied:Connect(function(p, kind, fromR, toR, A)
			table.insert(w.prestiges, { p = p, kind = kind, fromR = fromR, toR = toR, A = A })
		end)
		w.records = {}
		w.Signals.RecordReached:Connect(function(p, best)
			table.insert(w.records, { p = p, bestR = best })
		end)
		w.confetti = {}
		w.Signals.ConfettiChanged:Connect(function(p, delta, source)
			table.insert(w.confetti, { p = p, delta = delta, source = source })
		end)
		return w
	end

	-- zéro trace (doublures meta comprises) ; `allow` : motif d'une trace voulue par la spec
	local function clean(w, allow)
		local out = {}
		for _, line in Brains.problems(w) do
			if allow == nil or string.find(line, allow, 1, true) == nil then
				table.insert(out, line)
			end
		end
		expect(table.concat(out, "\n")).toBe("")
	end

	-- Joueur prêt pour sa 1re Jelly Ascend (r = Record R = 15) ; Meilleur Ami n° 1 = uid "1"
	local function veteran(w, edit)
		return Brains.profile(w, {
			coins = 5000,
			R = 15,
			squishies = {
				{ s = 1, z = 100, bf = 1 },
				{ s = 2, z = 20000 },
				{ s = 3, z = 300 },
				{ s = 4, z = 50, at = "dodo" },
			},
			tiles = { snack = 12, decor = 10 },
			edit = function(d)
				d.bestR = 15
				if edit then
					edit(d)
				end
			end,
		})
	end

	local function spectator(w)
		return Brains.profile(w, { squishies = { { s = 2, z = 500 }, { s = 5, z = 400 } } })
	end

	-- monde : héros (userId 1) chez lui, `n - 1` spectateurs
	local function world(opts)
		opts = opts or {}
		local w = boot(opts)
		local hero = Brains.join(w, 1, { profile = (opts.profile or veteran)(w) })
		local others = {}
		for i = 2, opts.n or 3 do
			table.insert(others, Brains.join(w, i, { profile = spectator(w) }))
		end
		Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
		Brains.frames(w, 2)
		return w, hero, others
	end

	local function ascend(w, p, confirm)
		w.h:fireServer(R .. "JellyAscend", p, if confirm == nil then true else confirm)
	end

	local function splorch(w, p, flyer)
		w.h:fireServer(R .. "GrandSplorch", p, false, flyer or "2")
	end

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

	local function deepEqual(a, b)
		if a == b or (a ~= a and b ~= b) then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in a do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	-- profil écrit dans le DataStore simulé (sans appel au magasin : aucune panne consommée)
	local function saved(w, userId)
		local store = w.h.dataStores[w.Schema.STORE_NAME .. "/global"]
		local record = store and MockInstance.state(store).data["player_" .. tostring(userId)]
		return record and record.data
	end

	local function attrs(w, p)
		local model = w.World.ranchModel(w.Ranch.slotOf(p))
		local out = {}
		for _, name in { "Ascend", "AscendReady", "PetitSplorchAt", "BestR" } do
			out[name] = model and model:GetAttribute(name)
		end
		return out
	end

	-- images jusqu'au départ du spectacle du héros (Celebrate « ascend » ou « splorch ») ; rend sa charge
	-- (`seen` : spectacles déjà vus, défaut 0 : attend le suivant)
	local function untilStart(w, hero, kind, max, seen)
		for _ = 1, max or 400 do
			local shows = Bots.celebrations(hero, kind)
			if #shows > (seen or 0) then
				return shows[#shows]
			end
			Brains.frames(w, 1)
		end
		return nil
	end

	-- images jusqu'à Clock.now() ≥ t
	local function untilTime(w, t)
		for _ = 1, 2000 do
			if w.Clock.now() >= t then
				return
			end
			Brains.frames(w, 1)
		end
	end

	local function sum(list, p, source)
		local n = 0
		for _, e in list do
			if e.p == p and (source == nil or e.source == source) then
				n += e.delta
			end
		end
		return n
	end

	-- =========================================================================================
	describe("SplorchService_ascend › interrupteurs coupés", function()
		it(
			"tout coupé (serveur v2), profil v1 tout ouvert, RecordR coupé : JellyAscend ne fait rien, aucune réponse",
			function()
				for _, case in
					{
						{ flags = {} },
						{ v1 = true },
						{ flags = { "Confetti", "JellyAscend", "PetitSplorch" } },
					}
				do
					local w, hero, others = world({ flags = case.flags, v1 = case.v1 })
					w.Economy.settle(hero)
					local before = deepCopy(w.DS.get(hero))
					local fb = #w.h:sentTo(hero, "Feedback")
					ascend(w, hero)
					Brains.frames(w, 80)
					w.Economy.settle(hero)
					local data = w.DS.get(hero)
					expect(data.R).toBe(before.R)
					expect(data.ascend).toBe(before.ascend)
					expect(data.coins).toBe(before.coins)
					expect(w.Splorch.queued(hero)).toBeNil()
					expect(w.Squishy.waiting(hero)).toBeNil()
					expect(#w.h:sentTo(hero, "Feedback")).toBe(fb)
					expect(#Bots.celebrations(hero, "ascend")).toBe(0)
					expect(#Bots.celebrations(others[1], "ascend")).toBe(0)
					expect(#w.prestiges).toBe(0)
					expect(attrs(w, hero).Ascend).toBeNil()
					expect(attrs(w, hero).AscendReady).toBeNil()
					clean(w)
				end
			end
		)

		it(
			"profil v2, RecordR coupé : le Grand Splorch reste celui de la v1.3 (Fame + 5, ni Confettis, ni cadeau du Splorch), Record R jamais sous r",
			function()
				local w, hero = world({
					flags = { "Confetti", "PetitSplorch", "JellyAscend" },
					profile = function(ww)
						return Brains.profile(ww, {
							coins = 5000,
							R = 1,
							squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 40000 } },
							edit = function(d)
								d.bestR = 1
							end,
						})
					end,
				})
				local fame = w.DS.get(hero).fame
				splorch(w, hero)
				untilStart(w, hero, "splorch")
				Brains.frames(w, 40)
				local data = w.DS.get(hero)
				expect(data.R).toBe(2)
				expect(data.bestR).toBe(2)
				expect(data.confetti).toBe(0)
				expect(data.pot).toBe(0)
				expect(data.fame).toBe(fame + w.Balance.Splorch.Fame)
				expect(#w.prestiges).toBe(0)
				expect(#w.confetti).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › Jelly Ascend complète", function()
		it(
			"file, Celebrate « ascend » à tous, Prestige.apply d'un bloc à 4,0 s, sauvegarde, Confettis, Fame, Pluie d'étoiles, bannière, attributs",
			function()
				local w, hero, others = world()
				local saves = 0
				local saveNow = w.DS.saveNow
				w.DS.saveNow = function(...)
					saves += 1
					return saveNow(...)
				end
				expect(attrs(w, hero).Ascend).toBe(0)
				expect(attrs(w, hero).AscendReady).toBe(true)
				local fame0 = w.DS.get(hero).fame
				local coins0 = { w.Economy.coins(others[1]), w.Economy.coins(others[2]) }
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				expect(w.Squishy.waiting(hero)).toBe("1") -- Meilleur Ami n° 1
				expect(#w.Event.state().spectacle.queue >= 1 or w.Event.state().spectacle.current ~= nil).toBe(
					true
				)
				local show = untilStart(w, hero, "ascend")
				expect(show ~= nil).toBe(true)
				expect(show.userId).toBe(hero.UserId)
				expect(show.ascend).toBe(1)
				expect(show.startR).toBe(w.Prestige.startR(1, 0))
				expect(show.bestR).toBe(15)
				expect(math.abs(show.burstAt - show.startedAt - w.Balance.Ascend.BurstAt) < 1e-9).toBe(true)
				expect(math.abs(show.endsAt - show.startedAt - w.Balance.Ascend.Duration) < 1e-9).toBe(true)
				expect(math.abs(show.flyer.z - w.Squishy.sizeOf(hero, "1", show.startedAt)) < 1e-6).toBe(true)
				for _, p in others do
					local seen = Bots.celebrations(p, "ascend")
					expect(#seen).toBe(1)
					expect(seen[1].userId).toBe(hero.UserId)
				end
				-- avant 4,0 s : rien n'a changé
				untilTime(w, show.startedAt + 3.85)
				expect(w.DS.get(hero).ascend).toBe(0)
				expect(w.DS.get(hero).R).toBe(15)
				untilTime(w, show.startedAt + 4.05)
				local data = w.DS.get(hero)
				expect(data.ascend).toBe(1)
				expect(data.R).toBe(w.Prestige.startR(1, 0))
				expect(data.bestR).toBe(15)
				expect(data.coins).toBe(0)
				-- cadeau du Splorch : prix du 1er niveau du Tapis de la boucle neuve, dans le Pot
				expect(data.pot).toBe(w.UM.giftCoins(data, 1))
				expect(data.pot > 0).toBe(true)
				expect(data.tiles.snack).toBe(0)
				-- décorations gardées au Record R 15 : 3 au Record R 8, 3 de plus au 14
				expect(data.tiles.decor).toBe(math.min(10, w.Prestige.keptDecor(15, data.atelier)))
				expect(data.tiles.decor).toBe(6)
				expect(w.Squishy.waiting(hero)).toBeNil()
				-- toutes les tailles à 1 (Dodo compris) juste après
				local fresh = deepCopy(data)
				fresh.growth.G = 0
				expect(table.concat(w.Invariants.afterPrestige(fresh), ",")).toBe("")
				-- Confettis : 20, source « ascend » ; Fame + 20 hors du plafond du jour
				expect(data.confetti).toBe(w.Balance.Confetti.PerAscend)
				expect(data.confettiTotal).toBe(w.Balance.Confetti.PerAscend)
				expect(sum(w.confetti, hero, "ascend")).toBe(w.Balance.Confetti.PerAscend)
				expect(data.fame).toBe(fame0 + w.Balance.Ascend.Fame)
				expect(data.caps.fameSplorch).toBe(0)
				-- signaux, attributs, bannière
				expect(#w.prestiges).toBe(1)
				expect(w.prestiges[1].kind).toBe("ascend")
				expect(w.prestiges[1].fromR).toBe(15)
				expect(w.prestiges[1].A).toBe(1)
				expect(#w.records).toBe(0)
				expect(attrs(w, hero).Ascend).toBe(1)
				expect(attrs(w, hero).AscendReady).toBe(false)
				local ascBanners = 0
				for _, b in w.banners do
					if b.kind == "ascend" then
						ascBanners += 1
						expect(b.args.ascend).toBe(1)
						expect(b.source).toBe(hero)
					end
					expect(b.kind ~= "splorch").toBe(true)
				end
				expect(ascBanners).toBe(1)
				-- Pluie d'étoiles : 120 s de revenu et un bébé de l'espèce du Meilleur Ami pour chaque autre
				for i, p in others do
					local rains = Bots.celebrations(p, "giftRain")
					expect(#rains).toBe(1)
					expect(rains[1].heroId).toBe(hero.UserId)
					expect(rains[1].coins > 0).toBe(true)
					expect(w.Economy.coins(p) >= coins0[i] + rains[1].coins).toBe(true)
					local baby = w.Squishy.get(p, rains[1].uid)
					expect(baby ~= nil and baby.s).toBe(1)
					expect(w.DS.get(p).caps.starRain).toBe(1)
				end
				-- sauvegardée tout de suite
				w.h:settle(3)
				expect(saves >= 1).toBe(true)
				-- la sauvegarde immédiate écrit TOUT le prestige (A, r, Confettis, Fame, Pot)
				local written = saved(w, hero.UserId)
				expect(written.ascend).toBe(1)
				expect(written.R).toBe(data.R)
				expect(written.confetti).toBe(w.Balance.Confetti.PerAscend)
				expect(written.fame).toBe(fame0 + w.Balance.Ascend.Fame)
				expect(written.pot >= data.pot).toBe(true)
				-- fin du spectacle (10 s), plus rien d'ouvert ; une seconde Ascension n'est pas prête
				Brains.frames(w, 80)
				expect(#w.Splorch.openStates()).toBe(0)
				w.RateLimit.clear(hero)
				ascend(w, hero)
				Brains.frames(w, 5)
				expect(w.Splorch.queued(hero)).toBeNil()
				expect(w.DS.get(hero).ascend).toBe(1)
				w.DS.saveNow = saveNow
				clean(w)
			end
		)

		it(
			"Tremplin (Atelier) : départ plus haut, 1 Confetti par Grand Splorch sauté grâce à lui (source « skipped »)",
			function()
				-- 2e Ascension (la ligne Tremplin s'ouvre après la 1re) : r = Record R = 20
				local w, hero = world({
					profile = function(ww)
						return veteran(ww, function(d)
							d.R, d.bestR, d.ascend, d.regainBonusA = 20, 20, 1, 1
							d.atelier[ww.h:require(L .. "Config.Upgrades").WorkshopIndex.springboard] = 2
						end)
					end,
				})
				expect(w.UM.level("springboard", w.DS.get(hero))).toBe(2)
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				expect(show.ascend).toBe(2)
				expect(show.startR).toBe(w.Prestige.startR(2, 2))
				untilTime(w, show.startedAt + 4.05)
				local data = w.DS.get(hero)
				local skipped = w.Prestige.startR(2, 2) - w.Prestige.startR(2, 0)
				expect(skipped).toBe(2)
				expect(data.ascend).toBe(2)
				expect(data.R).toBe(w.Prestige.startR(2, 2))
				expect(sum(w.confetti, hero, "ascend")).toBe(w.Balance.Confetti.PerAscend)
				expect(sum(w.confetti, hero, "skipped")).toBe(skipped)
				expect(data.confetti).toBe(w.Balance.Confetti.PerAscend + skipped)
				clean(w)
			end
		)

		it(
			"Pluie d'étoiles au plafond du jour (3) : plus de pièces ; « Recevoir les cadeaux » coupé : rien",
			function()
				local w, hero, others = world()
				local capped = w.DS.get(others[1])
				capped.caps.day = w.Clock.day()
				capped.caps.starRain = w.Balance.CapsV2.starRain
				capped.caps.splorchGifts = w.Balance.Caps.splorchGifts
				w.meta.settings[others[2].UserId] = { receiveGifts = false }
				local coins = { w.Economy.coins(others[1]), w.Economy.coins(others[2]) }
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 4.05)
				expect(w.DS.get(hero).ascend).toBe(1)
				expect(#Bots.celebrations(others[1], "giftRain")).toBe(0)
				expect(#Bots.celebrations(others[2], "giftRain")).toBe(0)
				expect(w.DS.get(others[1]).caps.starRain).toBe(w.Balance.CapsV2.starRain)
				expect(w.Economy.coins(others[1]) <= coins[1] + 1e-6 + w.Economy.income(others[1]) * 1).toBe(
					true
				)
				expect(w.DS.get(others[2]).caps.starRain).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › refus et un seul prestige par joueur", function()
		it(
			"refus : confirmation absente, condition fausse, hors du ranch, en portant, fuite en cours, configuration refusée, session en fin",
			function()
				local w, hero = world()
				local function refused(label)
					expect({ label = label, queued = w.Splorch.queued(hero) }).toEqual({
						label = label,
						queued = nil,
					})
					expect({ label = label, waiting = w.Squishy.waiting(hero) }).toEqual({
						label = label,
						waiting = nil,
					})
					w.RateLimit.clear(hero)
				end
				local before = deepCopy(w.DS.get(hero))
				-- confirmation absente ou fausse : rien, aucune réponse
				local fb = #w.h:sentTo(hero, "Feedback")
				ascend(w, hero, false)
				w.h:fireServer(R .. "JellyAscend", hero)
				w.h:fireServer(R .. "JellyAscend", hero, "true")
				Brains.frames(w, 2)
				expect(#w.h:sentTo(hero, "Feedback")).toBe(fb)
				refused("confirm")
				-- hors du ranch
				Bots.place(hero, Bots.ground(0, 40))
				Brains.frames(w, 2)
				ascend(w, hero)
				expect(Bots.feedbackKeys(hero)[#Bots.feedbackKeys(hero)]).toBe("feedback.onlyOwnRanch")
				refused("ranch")
				Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
				Brains.frames(w, 2)
				-- en portant
				w.h:fireServer(R .. "PickUp", hero, "3")
				if w.Squishy.carried(hero) ~= nil then
					Brains.frames(w, 2)
					ascend(w, hero)
					expect(Bots.feedbackKeys(hero)[#Bots.feedbackKeys(hero)]).toBe("feedback.carrying")
					refused("carry")
					w.h:fireServer(R .. "PutDown", hero)
					Brains.frames(w, 2)
				end
				-- fuite en cours
				w.Squishy.setEscaping(hero, "3", true)
				ascend(w, hero)
				local fbs = w.h:sentTo(hero, "Feedback")
				expect(fbs[#fbs][1].key).toBe("feedback.waitEscape")
				expect(fbs[#fbs][1].vars.species).toBe(3)
				refused("escape")
				w.Squishy.setEscaping(hero, "3", false)
				-- configuration refusée (Prestige.validateConfig) : « busy »
				local configOk = w.Economy.configOk
				w.Economy.configOk = function()
					return false, "test"
				end
				ascend(w, hero)
				expect(Bots.feedbackKeys(hero)[#Bots.feedbackKeys(hero)]).toBe("upgrades.refused.busy")
				refused("config")
				w.Economy.configOk = configOk
				-- session en fin (sauvegarde de départ commencée, BindToClose) : rien
				local isClosing = w.DS.isClosing
				w.DS.isClosing = function()
					return true
				end
				ascend(w, hero)
				refused("closing")
				w.DS.isClosing = isClosing
				-- condition fausse (r sous la condition) : rien, aucune réponse
				w.DS.get(hero).R = 14
				fb = #w.h:sentTo(hero, "Feedback")
				ascend(w, hero)
				expect(#w.h:sentTo(hero, "Feedback")).toBe(fb)
				refused("reqR")
				w.DS.get(hero).R = 15
				-- A au maximum : jamais prête
				w.DS.get(hero).ascend = w.Balance.Prestige.MaxA
				ascend(w, hero)
				refused("maxA")
				w.DS.get(hero).ascend = 0
				-- rien n'a changé (ni pièces, ni r, ni A, ni tailles)
				local data = w.DS.get(hero)
				expect(data.R).toBe(before.R)
				expect(data.ascend).toBe(before.ascend)
				expect(data.coins >= before.coins).toBe(true)
				expect(#w.prestiges).toBe(0)
				-- accepté ensuite
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				clean(w)
			end
		)

		it(
			"un seul prestige par joueur : JellyAscend pendant son Grand Splorch en file (« Ton Grand Splorch passe d'abord ! »), Grand Splorch pendant son Ascension en file",
			function()
				local w, hero = world({
					profile = function(ww)
						return veteran(ww, function(d)
							-- prêt aussi pour le Grand Splorch 16 (record)
							d.squishies["2"].z = 3e10
						end)
					end,
				})
				-- une place d'absent devant lui : son entrée attend dans la file
				w.Event.enqueueSpectacle("splorch", 900001)
				splorch(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("splorch")
				w.RateLimit.clear(hero)
				ascend(w, hero)
				expect(Bots.feedbackKeys(hero)[#Bots.feedbackKeys(hero)]).toBe("ascend.queued")
				expect(w.Splorch.queuedKind(hero)).toBe("splorch")
				-- le Grand Splorch passe : r = 16, A = 0
				local show = untilStart(w, hero, "splorch", 600)
				untilTime(w, show.startedAt + 3.3)
				expect(w.DS.get(hero).R).toBe(16)
				expect(w.DS.get(hero).ascend).toBe(0)
				-- l'Ascension, puis un Grand Splorch pendant qu'elle attend
				untilTime(w, show.startedAt + 8)
				w.Event.enqueueSpectacle("splorch", 900002)
				w.RateLimit.clear(hero)
				ascend(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				w.DS.get(hero).squishies["2"].z = 1e12
				w.RateLimit.clear(hero)
				splorch(w, hero)
				expect(Bots.feedbackKeys(hero)[#Bots.feedbackKeys(hero)]).toBe("feedback.waitingSplorch")
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				expect(w.Splorch.canPrestige(hero)).toBe(false)
				local a = untilStart(w, hero, "ascend", 800, 0)
				untilTime(w, a.startedAt + 4.05)
				expect(w.DS.get(hero).ascend).toBe(1)
				expect(w.DS.get(hero).R).toBe(w.Prestige.startR(1, 0))
				expect(#w.prestiges).toBe(2)
				clean(w)
			end
		)

		it(
			"JellyAscend deux fois dans la même image (seau à jetons, puis sans lui) et rejouée pendant le spectacle : une seule entrée, une seule Ascension",
			function()
				local w, hero = world()
				local remote = w.h:find(R .. "JellyAscend")
				remote.OnServerEvent:Fire(hero, true)
				remote.OnServerEvent:Fire(hero, true)
				w.h:settle(1)
				expect(w.Splorch.queuedKind(hero)).toBe("ascend")
				-- sans le seau à jetons : la même Ascension (idempotent, aucune réponse)
				local fb = #w.h:sentTo(hero, "Feedback")
				for _ = 1, 5 do
					w.RateLimit.clear(hero)
					remote.OnServerEvent:Fire(hero, true)
				end
				w.h:settle(1)
				expect(#w.h:sentTo(hero, "Feedback")).toBe(fb)
				local n = 0
				for _, entry in w.Event.state().spectacle.queue do
					if entry.userId == hero.UserId then
						n += 1
					end
				end
				local current = w.Event.state().spectacle.current
				if current and current.userId == hero.UserId then
					n += 1
				end
				expect(n).toBe(1)
				local show = untilStart(w, hero, "ascend")
				-- rejouée pendant le spectacle, avant et après l'application
				for _, at in { 1, 4.05, 6 } do
					untilTime(w, show.startedAt + at)
					w.RateLimit.clear(hero)
					remote.OnServerEvent:Fire(hero, true)
					w.h:settle(1)
				end
				Brains.frames(w, 100)
				expect(w.DS.get(hero).ascend).toBe(1)
				expect(#w.prestiges).toBe(1)
				expect(#Bots.celebrations(hero, "ascend")).toBe(1)
				expect(sum(w.confetti, hero)).toBe(w.Balance.Confetti.PerAscend)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › départs, sauvegarde, fermeture", function()
		it(
			"départ à 3,9 s : rien appliqué, place rendue, profil sauvegardé entier ; retour : l'Ascension est de nouveau possible",
			function()
				local w, hero, others = world()
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 3.85)
				expect(w.DS.get(hero).ascend).toBe(0)
				Bots.leave(hero)
				w.h:settle(3)
				Brains.frames(w, 60)
				expect(#Bots.celebrations(others[1], "giftRain")).toBe(0)
				expect(#w.prestiges).toBe(0)
				local data = saved(w, 1)
				expect(data.ascend).toBe(0)
				expect(data.R).toBe(15)
				expect(data.coins >= 5000).toBe(true)
				expect(data.squishies["2"].z >= 20000).toBe(true)
				-- retour sur le même serveur : prêt, l'Ascension se refait une fois
				local back = Brains.join(w, 1)
				Bots.place(back, Brains.atRanch(w, back, 0, 30))
				Brains.frames(w, 2)
				expect(w.DS.get(back).ascend).toBe(0)
				ascend(w, back)
				local again = untilStart(w, back, "ascend")
				untilTime(w, again.startedAt + 4.05)
				expect(w.DS.get(back).ascend).toBe(1)
				clean(w)
			end
		)

		it(
			"départ à 4,1 s : appliquée et sauvegardée une fois ; retour : A = 1, r de départ, rien à refaire",
			function()
				local w, hero = world()
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 4.05)
				expect(w.DS.get(hero).ascend).toBe(1)
				Bots.leave(hero)
				w.h:settle(3)
				local data = saved(w, 1)
				expect(data.ascend).toBe(1)
				expect(data.R).toBe(w.Prestige.startR(1, 0))
				expect(data.confetti).toBe(w.Balance.Confetti.PerAscend)
				local back = Brains.join(w, 1)
				Bots.place(back, Brains.atRanch(w, back, 0, 30))
				Brains.frames(w, 2)
				local d = w.DS.get(back)
				expect(d.ascend).toBe(1)
				expect(d.bestR).toBe(15)
				expect(d.R).toBe(w.Prestige.startR(1, 0))
				expect(d.confetti).toBe(w.Balance.Confetti.PerAscend)
				ascend(w, back)
				Brains.frames(w, 60)
				expect(w.Splorch.queued(back)).toBeNil()
				expect(w.DS.get(back).ascend).toBe(1)
				clean(w)
			end
		)

		it(
			"sauvegarde en échec pendant l'Ascension : le magasin garde le profil d'avant, entier ; la sauvegarde suivante écrit l'Ascension entière, une seule fois",
			function()
				T.expectWarning("échec de sauvegarde pour")
				local w, hero = world()
				w.h:settle(3)
				ascend(w, hero)
				local show = untilStart(w, hero, "ascend")
				untilTime(w, show.startedAt + 3.85)
				w.h.dataStoreFailures = 1000
				untilTime(w, show.startedAt + 4.05)
				w.h:settle(5)
				expect(w.DS.get(hero).ascend).toBe(1)
				-- rien d'écrit : le profil d'avant (A = 0, r = 15), entier
				local before = saved(w, 1)
				expect(before == nil or (before.ascend == 0 and before.R == 15)).toBe(true)
				-- rejouée pendant la panne : refusée (déjà faite en mémoire)
				w.RateLimit.clear(hero)
				ascend(w, hero)
				Brains.frames(w, 20)
				expect(w.Splorch.queued(hero)).toBeNil()
				-- le DataStore revient : la sauvegarde suivante écrit tout le prestige
				w.h.dataStoreFailures = 0
				expect(w.DS.saveNow(hero)).toBe(true)
				local after = saved(w, 1)
				expect(after.ascend).toBe(1)
				expect(after.R).toBe(w.Prestige.startR(1, 0))
				expect(after.bestR).toBe(15)
				expect(after.confetti).toBe(w.Balance.Confetti.PerAscend)
				expect(after.coins).toBe(w.DS.get(hero).coins)
				expect(table.concat(w.Invariants.profile(after), ",")).toBe("")
				Bots.leave(hero)
				w.h:settle(3)
				expect(saved(w, 1).ascend).toBe(1)
				clean(w, "[panne simulée]")
			end
		)

		it(
			"fermeture (BindToClose) avec 16 joueurs en file : celle déjà appliquée sauvegardée, aucune appliquée pendant la fermeture, chaque profil entier",
			function()
				local w = boot()
				local players = {}
				for i = 1, 16 do
					local p = Brains.join(w, i, { profile = veteran(w) })
					table.insert(players, p)
				end
				for _, p in players do
					Bots.place(p, Brains.atRanch(w, p, 0, 30))
				end
				Brains.frames(w, 2)
				for _, p in players do
					ascend(w, p)
				end
				local queuedCount = 0
				for _, p in players do
					if w.Splorch.queuedKind(p) == "ascend" then
						queuedCount += 1
					end
				end
				expect(queuedCount).toBe(16)
				-- la 1re passe (appliquée à 4,0 s), la 2e commence
				local first = untilStart(w, players[1], "ascend")
				untilTime(w, first.startedAt + 4.05)
				expect(w.DS.get(players[1]).ascend).toBe(1)
				local second = nil
				for _ = 1, 400 do
					for _, p in players do
						if p ~= players[1] and #Bots.celebrations(p, "ascend") >= 2 then
							second = Bots.celebrations(p, "ascend")[2]
						end
					end
					if second then
						break
					end
					Brains.frames(w, 1)
				end
				expect(second ~= nil).toBe(true)
				untilTime(w, second.startedAt + 2)
				-- fermeture pendant le 2e spectacle, avant son application
				w.h:close()
				w.h:settle(3)
				Brains.frames(w, 300)
				w.h:settle(3)
				local applied = 0
				for i, p in players do
					local data = saved(w, i)
					expect({ i = i, problems = table.concat(w.Invariants.profile(data), ",") }).toEqual({
						i = i,
						problems = "",
					})
					expect(data.ascend == 0 or data.ascend == 1).toBe(true)
					if data.ascend == 1 then
						applied += 1
						expect(data.R).toBe(w.Prestige.startR(1, 0))
						expect(data.confetti).toBe(w.Balance.Confetti.PerAscend)
					else
						expect(data.R).toBe(15)
						expect(data.confetti).toBe(0)
					end
					if p ~= players[1] then
						expect(w.DS.get(p) == nil or w.DS.get(p).ascend == 0).toBe(true)
					end
				end
				expect(applied).toBe(1)
				expect(saved(w, 1).ascend).toBe(1)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › Petit Splorch hors file", function()
		-- après une Ascension : A = 1, Record R 15, r = 3, plus gros prêt (objectif de r = 3)
		local function climber(R0, z)
			return function(w)
				return Brains.profile(w, {
					coins = 7000,
					R = R0,
					squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = z }, { s = 3, z = 300 } },
					tiles = { snack = 6, decor = 4 },
					edit = function(d)
						d.bestR = 15
						d.ascend = 1
					end,
				})
			end
		end

		it(
			"appliqué tout de suite, hors file : 1 Confetti, cadeau du Splorch, PetitSplorchAt, Celebrate au joueur seul ; ni bannière, ni cadeaux aux autres, ni Fame",
			function()
				local w, hero, others = world({ profile = climber(3, 300000) })
				local fame = w.DS.get(hero).fame
				local splorched = {}
				w.Signals.Splorched:Connect(function(p, r, gifts)
					table.insert(splorched, { p = p, r = r, gifts = gifts })
				end)
				-- une file pleine devant lui ne le retarde pas
				for i = 1, 5 do
					w.Event.enqueueSpectacle("splorch", 900000 + i)
				end
				local t = w.Clock.now()
				splorch(w, hero)
				local data = w.DS.get(hero)
				expect(data.R).toBe(4)
				expect(data.bestR).toBe(15)
				expect(data.ascend).toBe(1)
				expect(data.coins).toBe(0)
				expect(data.pot).toBe(w.UM.giftCoins(data, 1))
				expect(data.squishies["2"].z).toBe(1)
				expect(data.confetti).toBe(w.Balance.Confetti.PerPetitSplorch)
				expect(sum(w.confetti, hero, "petit")).toBe(w.Balance.Confetti.PerPetitSplorch)
				expect(data.fame).toBe(fame)
				expect(w.Splorch.queued(hero)).toBeNil()
				expect(w.Squishy.waiting(hero)).toBeNil()
				local petit = Bots.celebrations(hero, "petitSplorch")
				expect(#petit).toBe(1)
				expect(petit[1].level).toBe(4)
				expect(math.abs(petit[1].startedAt - t) < 1e-6).toBe(true)
				expect(
					math.abs(petit[1].endsAt - petit[1].startedAt - w.Balance.SplorchV2.PetitShow.Duration)
						< 1e-9
				).toBe(true)
				expect(attrs(w, hero).PetitSplorchAt).toBe(petit[1].startedAt)
				Brains.frames(w, 30)
				for _, p in others do
					expect(#Bots.celebrations(p, "petitSplorch")).toBe(0)
					expect(#Bots.celebrations(p, "splorch")).toBe(0)
					expect(#Bots.celebrations(p, "giftRain")).toBe(0)
				end
				expect(#w.banners).toBe(0)
				expect(#w.prestiges).toBe(1)
				expect(w.prestiges[1].kind).toBe("petit")
				expect(#splorched).toBe(1)
				expect(splorched[1].gifts).toBe(0)
				-- pas deux de suite : il n'est plus prêt (tailles à 1)
				w.RateLimit.clear(hero)
				splorch(w, hero)
				expect(w.DS.get(hero).R).toBe(4)
				-- PetitSplorch coupé : PetitSplorchAt effacé
				w.Features.set("PetitSplorch", false)
				Brains.frames(w, 12)
				expect(attrs(w, hero).PetitSplorchAt).toBeNil()
				clean(w)
			end
		)

		it(
			"retour au record après une Ascension : + 1 et + 10 Confettis (regain), regainDone, memoryR ; une fois par Ascension",
			function()
				local w, hero = world({ profile = climber(14, 1e11) })
				splorch(w, hero)
				local data = w.DS.get(hero)
				expect(data.R).toBe(15)
				expect(data.regainBonusA).toBe(1)
				expect(data.memoryR).toBe(15)
				expect(sum(w.confetti, hero, "petit")).toBe(1)
				expect(sum(w.confetti, hero, "regain")).toBe(w.Balance.Confetti.RegainBonus)
				local cards = Bots.celebrations(hero, "regainDone")
				expect(#cards).toBe(1)
				expect(cards[1].bestR).toBe(15)
				expect(cards[1].confetti).toBe(w.Balance.Confetti.RegainBonus)
				expect(#w.records).toBe(0)
				clean(w)
			end
		)

		it(
			"PetitSplorch coupé : le Grand Splorch qui ne bat pas le record passe par la file (1 Confetti, aucune Fame)",
			function()
				local w, hero = world({
					flags = { "RecordR", "Confetti", "JellyAscend" },
					profile = climber(3, 300000),
				})
				local fame = w.DS.get(hero).fame
				splorch(w, hero)
				expect(w.Splorch.queuedKind(hero)).toBe("splorch")
				expect(w.DS.get(hero).R).toBe(3)
				local show = untilStart(w, hero, "splorch")
				untilTime(w, show.startedAt + 3.3)
				local data = w.DS.get(hero)
				expect(data.R).toBe(4)
				expect(data.confetti).toBe(1)
				expect(data.fame).toBe(fame)
				expect(#Bots.celebrations(hero, "petitSplorch")).toBe(0)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › Grand Splorch v2.0", function()
		local function rookie(w, edit)
			return Brains.profile(w, {
				coins = 5000,
				R = 1,
				squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 40000 }, { s = 3, z = 300 } },
				edit = function(d)
					d.bestR = 1
					if edit then
						edit(d)
					end
				end,
			})
		end

		it(
			"Prestige.apply : Record R, 3 + r Confettis, place offerte, cadeau du Splorch, Fame dans le plafond, RecordReached",
			function()
				local w, hero = world({ profile = rookie })
				local data0 = w.DS.get(hero)
				local pens0, fame0 = data0.tiles.pens, data0.fame
				splorch(w, hero)
				local show = untilStart(w, hero, "splorch")
				untilTime(w, show.startedAt + 3.3)
				local data = w.DS.get(hero)
				expect(data.R).toBe(2)
				expect(data.bestR).toBe(2)
				expect(data.confetti).toBe(w.Balance.Confetti.PerGrandSplorchBase + 2)
				expect(sum(w.confetti, hero, "splorch")).toBe(w.Balance.Confetti.PerGrandSplorchBase + 2)
				expect(data.tiles.pens).toBe(pens0 + 1)
				expect(data.pot).toBe(w.UM.giftCoins(data, 1))
				expect(data.fame).toBe(fame0 + w.Balance.Splorch.Fame)
				expect(data.caps.fameSplorch).toBe(w.Balance.Splorch.Fame)
				expect(#w.records).toBe(1)
				expect(w.records[1].bestR).toBe(2)
				expect(w.prestiges[1].kind).toBe("splorch")
				local banners = 0
				for _, b in w.banners do
					if b.kind == "splorch" then
						banners += 1
					end
				end
				expect(banners).toBe(1)
				clean(w)
			end
		)

		it(
			"Fame des Grands Splorch : 50 par jour au plus, remis à zéro le lendemain ; prime de record au-delà de 20 (source « record »)",
			function()
				local w, hero = world({
					profile = function(ww)
						return rookie(ww, function(d)
							d.R, d.bestR = 21, 21
							d.squishies["2"].z = 1e15
							d.caps.day = 0
							d.caps.fameSplorch = 50 -- d'un autre jour
						end)
					end,
				})
				local fame0 = w.DS.get(hero).fame
				splorch(w, hero)
				local show = untilStart(w, hero, "splorch")
				untilTime(w, show.startedAt + 3.3)
				local data = w.DS.get(hero)
				expect(data.R).toBe(22)
				-- jour nouveau : compteur remis à zéro, + 5
				expect(data.caps.fameSplorch).toBe(5)
				expect(data.fame).toBe(fame0 + 5)
				-- 3 + min(22, 20) + prime de record 10
				expect(sum(w.confetti, hero, "splorch")).toBe(3 + 20)
				expect(sum(w.confetti, hero, "record")).toBe(w.Balance.Confetti.RecordBonus)
				-- plafond du jour : 48 → + 2 seulement
				data.caps.fameSplorch = 48
				data.squishies["2"].z = 1e16
				untilTime(w, show.startedAt + 25)
				w.RateLimit.clear(hero)
				splorch(w, hero)
				local second = untilStart(w, hero, "splorch", 400, 1)
				expect(second.startedAt > show.startedAt).toBe(true)
				untilTime(w, second.startedAt + 3.3)
				expect(w.DS.get(hero).R).toBe(23)
				expect(w.DS.get(hero).caps.fameSplorch).toBe(50)
				expect(w.DS.get(hero).fame).toBe(fame0 + 7)
				-- 2e Grand Splorch moins de 180 s après le 1er : aucune bannière de plus
				local banners = 0
				for _, b in w.banners do
					if b.kind == "splorch" then
						banners += 1
					end
				end
				expect(banners).toBe(1)
				clean(w)
			end
		)

		it(
			"plus gros vendu pendant l'attente : place rendue au départ, rien remis à zéro, aucun spectacle ni cadeau",
			function()
				local w, hero, others = world({ profile = rookie })
				-- une place d'absent devant lui
				w.Event.enqueueSpectacle("splorch", 900001)
				splorch(w, hero, "3")
				expect(w.Splorch.queuedKind(hero)).toBe("splorch")
				w.h:fireServer(R .. "Sell", hero, { "2" }, true)
				w.h:settle(1)
				expect(w.Squishy.get(hero, "2")).toBeNil()
				Brains.frames(w, 400)
				local data = w.DS.get(hero)
				expect(data.R).toBe(1)
				expect(#Bots.celebrations(hero, "splorch")).toBe(0)
				expect(#Bots.celebrations(others[1], "giftRain")).toBe(0)
				expect(w.Squishy.waiting(hero)).toBeNil()
				expect(w.Splorch.queued(hero)).toBeNil()
				expect(w.Splorch.counters().SplorchNotReadyAtStart).toBe(1)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("SplorchService_ascend › sonde « occupé » des achats", function()
		it("aucun achat pendant le spectacle de l'Ascension ni l'animation du Petit Splorch", function()
			local flags = table.clone(FLAGS)
			table.insert(flags, "UpgradesScreen")
			local w, hero = world({ flags = flags })
			ascend(w, hero)
			local show = untilStart(w, hero, "ascend")
			untilTime(w, show.startedAt + 1)
			local level = w.UM.level("decor", w.DS.get(hero))
			local r = w.Economy.buyUpgrade(hero, "decor", 1, level)
			expect(r.reason).toBe("upgrades.refused.busy")
			untilTime(w, show.startedAt + 6)
			r = w.Economy.buyUpgrade(hero, "decor", 1, w.UM.level("decor", w.DS.get(hero)))
			expect(r.reason).toBe("upgrades.refused.busy")
			Brains.frames(w, 60)
			expect(w.Splorch.canPrestige(hero)).toBe(true)
			-- Petit Splorch : occupé pendant son animation (2,5 s), puis libre
			local data = w.DS.get(hero)
			data.squishies["2"].z = 1e6
			data.coins = 1e9
			w.RateLimit.clear(hero)
			splorch(w, hero)
			expect(w.DS.get(hero).R).toBe(w.Prestige.startR(1, 0) + 1)
			expect(w.Splorch.canPrestige(hero)).toBe(false)
			w.DS.get(hero).coins = 1e9
			local decor = w.UM.level("decor", w.DS.get(hero))
			r = w.Economy.buyUpgrade(hero, "decor", 1, decor)
			expect(r.reason).toBe("upgrades.refused.busy")
			Brains.frames(w, 30)
			r = w.Economy.buyUpgrade(hero, "decor", 1, decor)
			expect(r.reason).toBeNil()
			expect(r.to).toBe(decor + 1)
			clean(w)
		end)
	end)
end
