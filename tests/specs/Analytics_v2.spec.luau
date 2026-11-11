--!nocheck
-- Analytics_v2 (lot A4, étape 6, décision D30 du plan ; GDD v2.0 §16.2-§16.4, docs/04 §27.14) :
-- l'analytique v2.0 sur un serveur de 16 joueurs (vrais services, profils v2, interrupteurs ouverts
-- dans le test), une heure de jeu v2.0 chargée :
--   * débit : jamais plus de 10 requêtes par joueur sur 60 s glissantes, rien de jeté (dropped = 0),
--     aucun nom hors catalogue ;
--   * chaque événement v2.0 présent avec sa valeur cumulée attendue : Upgrade_<famille> (niveaux),
--     WorkshopBuy_<ligne> (niveaux, champ level), ConfettiEarned (par source), RanchTierReached ;
--   * économie « Confetti » en unités brutes (sources et puits par ligne, solde = profile.confetti) ;
--   * HelperCoinsShare de chaque tranche = part des pièces « Helper » dans les pièces Gameplay ;
--   * NextGoalGap : secondes de jeu passées plus de 180 s après le dernier achat ou but ;
--   * interrupteurs coupés : mêmes noms et mêmes nombres que le jeu de base (MetaAnalytics retiré).
-- Les gestes de jeu passent par les vraies API (EconomyService.addCoins, buyUpgrade, addConfetti,
-- Activity.note) ; l'horloge avance d'une seconde à la fois et DiagnosticsService.step fait le reste.
local Brains = require("../harness/Brains")
local Bots = require("../harness/Bots")
local Flags = require("../harness/Flags")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 30 -- 30 s après le début d'une tranche de 5 min
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local FLAGS = {
		"UpgradesScreen",
		"Confetti",
		"Workshop",
		"Gloves",
		"StarMat",
		"Monuments",
		"RecordR",
		"RanchTiers",
		"Helpers",
		"DecoPerso",
	}
	-- sources de pièces de la partie (pièces par appel) : « Helper » une seconde sur 8
	local SOURCES = {
		{ "Press", 50 },
		{ "Pot", 400 },
		{ "Combo", 120 },
		{ "Helper", 80 },
		{ "Sell", 900 },
		{ "Golden", 2500 },
		{ "PetSit", 60 },
		{ "Mega", 1500 },
	}
	local FAMILIES = { "gloves", "school", "decor", "pens", "snack", "star", "monument" }
	local WORKSHOP = {
		"gift",
		"magnet",
		"nightBag",
		"fun.palettes",
		"startMat",
		"superStreak",
		"fun.saddle",
		"keptDecor",
		"decoShop",
		"nightPot",
		"fun.trail",
		"fun.palettes",
	}
	local CONFETTI = { "splorch", "petit", "track", "record" }
	local RARE =
		{ [600] = "fullPen", [1500] = "skipped", [2100] = "ascend", [2700] = "regain", [3300] = "mastery" }
	local SKU = {
		splorch = "GrandSplorch",
		petit = "PetitSplorch",
		skipped = "Skipped",
		ascend = "Ascend",
		regain = "Regain",
		record = "RecordBonus",
		fullPen = "FullPen",
		track = "WeeklyTrack",
		mastery = "Mastery",
	}

	local function world(harness, opts)
		opts = opts or {}
		local w = Brains.boot(harness, { t0 = T0, stubMeta = false, before = opts.before })
		w.D = w.h:require(S .. "DiagnosticsService")
		w.A = w.h:require("ServerScriptService.Server.Util.Analytics")
		w.Meta = w.h:require("ServerScriptService.Server.Meta.MetaAnalytics")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		w.ps = {}
		for i = 1, opts.n or 16 do
			local p = Brains.join(w, i, {
				profile = Brains.profile(w, {
					coins = 1e14, -- pièces exactes (sous Balance.Numbers.ExactBelow) : chaque gain compte
					R = opts.R or 2,
					squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 5000 }, { s = 3, z = 300 } },
					edit = function(d)
						if opts.R then
							return
						end
						d.bestR = 10
						d.confetti = opts.confetti or 0
						d.confettiTotal = opts.confetti or 0
					end,
				}),
			})
			table.insert(w.ps, p)
		end
		w.h:settle(2)
		return w
	end

	-- requêtes de chaque joueur, seconde par seconde (fenêtre glissante de 60 s)
	local function harvester(w)
		local perSecond, seen = {}, 0
		return function(second)
			local log = w.h.log.analytics
			for i = seen + 1, #log do
				local player = log[i].args[1]
				local id = player.UserId
				perSecond[id] = perSecond[id] or {}
				perSecond[id][second] = (perSecond[id][second] or 0) + 1
			end
			seen = #log
		end, function(last)
			local worst = 0
			for _, bySecond in perSecond do
				for start = 0, last do
					local n = 0
					for s = start, math.min(last, start + 59) do
						n += bySecond[s] or 0
					end
					worst = math.max(worst, n)
				end
			end
			return worst
		end
	end

	local function fieldsOf(w, args)
		local Keys = w.h.globals.Enum.AnalyticsCustomFieldKeys
		local f = args[4]
		local out = {}
		if f then
			for i = 1, 3 do
				local text = f[Keys["CustomField0" .. i]]
				if text then
					local k, v = string.match(text, "^([^:]+):(.*)$")
					out[k] = v
				end
			end
		end
		return out
	end

	describe("Analytics_v2 › une heure de jeu v2.0 chargée, 16 joueurs", function()
		it(
			"débit ≤ 10 par minute et par joueur, rien de jeté ; valeurs cumulées, Confettis, HelperCoinsShare et NextGoalGap exacts",
			function()
				-- départ « cut » (lot I, étape 3, I-24) : la case ouvre exactement FLAGS ; la piste de la
				-- semaine ouverte au lancement donnerait ses propres Confettis (paliers), hors du compte de la case
				local w = world(Flags.harness(Harness, "cut"), { flags = FLAGS })
				local A, D, Meta, E, Activity = w.A, w.D, w.Meta, w.Economy, w.Activity
				-- pièces créditées par joueur et par tranche (enveloppe de EconomyService.addCoins)
				local credited = {} -- [userId][tranche] = { helper, gameplay }
				local addCoins = E.addCoins
				E.addCoins = function(p, amount, sku, txType)
					local c = addCoins(p, amount, sku, txType)
					if c > 0 and (txType or "Gameplay") == "Gameplay" then
						local b = math.floor(w.Clock.now() / A.BucketSeconds)
						local byPlayer = credited[p.UserId] or {}
						credited[p.UserId] = byPlayer
						local e = byPlayer[b] or { helper = 0, gameplay = 0 }
						byPlayer[b] = e
						e.gameplay += c
						if sku == "Helper" then
							e.helper += c
						end
					end
					return c
				end
				-- comptes attendus
				local want = {} -- [userId] = { up = {fam = n}, ws = {line = n}, wsLevel = {}, earned = {sku = n}, spent = {sku = n} }
				local gap = {} -- [userId] = { since = nil | s, total = s }
				local lastGoal = {}
				for _, p in w.ps do
					want[p.UserId] = { up = {}, ws = {}, wsLevel = {}, earned = {}, spent = {} }
					gap[p.UserId] = { since = nil, total = 0 }
				end
				local function goal(p)
					lastGoal[p.UserId] = true
				end
				local function buy(p, id, mode)
					local data = w.DS.get(p)
					local UpgradeMath = w.h:require(L .. "Logic.UpgradeMath")
					local level = UpgradeMath.level(UpgradeMath.canonical(id), data)
					local r = E.buyUpgrade(p, id, mode, level)
					if r and r.reason == nil and r.to > r.from then
						local x = want[p.UserId]
						goal(p)
						if r.currency == "coins" then
							x.up[r.id] = (x.up[r.id] or 0) + (r.to - r.from)
						else
							local line = if string.sub(r.id, 1, 4) == "fun."
								then string.sub(r.id, 5)
								else r.id
							x.ws[line] = (x.ws[line] or 0) + (r.to - r.from)
							x.wsLevel[line] = math.max(x.wsLevel[line] or 0, r.to)
							local sku = (
								if string.sub(r.id, 1, 4) == "fun." or line == "decoShop"
									then "Fun_"
									else "Workshop_"
							) .. line
							x.spent[sku] = (x.spent[sku] or 0) + r.spent
						end
					end
				end
				local harvest, worstOf = harvester(w)
				local NAP = w.Balance.Helpers.NapAfter
				-- suivi de NextGoalGap attendu (même règle que la spec du GDD : temps de JEU depuis le but)
				local function expectGap(now)
					for _, p in w.ps do
						local g = gap[p.UserId]
						if lastGoal[p.UserId] and g.since ~= nil then
							g.since = 0
						end
						lastGoal[p.UserId] = nil
						if g.since == nil then
							g.since = 0
						elseif now - Activity.lastIntent(p) <= NAP then
							g.since += 1
							local over = math.min(1, g.since - Meta.GoalGap)
							if over > 0 then
								g.total += over
							end
						end
					end
				end
				-- l'heure : une seconde à la fois
				local HOUR = 3600
				for t = 1, HOUR + 1200 do
					w.Clock.advance(1)
					local now = w.Clock.now()
					if t <= HOUR then
						for i, p in w.ps do
							local src = SOURCES[(t + i) % #SOURCES + 1]
							E.addCoins(p, src[2], src[1], "Gameplay")
							if t % 20 == i % 20 then
								Activity.note(p, now)
							end
							local idle = i > 12 and t >= 1200 and t < 2400 -- 4 joueurs sans but 20 min
							if not idle and t % 45 == i % 45 then
								local k = t // 45
								buy(p, FAMILIES[(k + i) % #FAMILIES + 1], if k % 4 == 0 then 10 else 1)
							end
							if t % 75 == i % 75 then
								local source = CONFETTI[(t // 75 + i) % #CONFETTI + 1]
								local c = E.addConfetti(p, 3, source)
								local x = want[p.UserId]
								x.earned[SKU[source]] = (x.earned[SKU[source]] or 0) + c
							end
							if RARE[t] then
								local c = E.addConfetti(p, 2, RARE[t])
								local x = want[p.UserId]
								x.earned[SKU[RARE[t]]] = (x.earned[SKU[RARE[t]]] or 0) + c
							end
							if not idle and t % 300 == (i * 7) % 300 then
								buy(p, WORKSHOP[(t // 300 + i) % #WORKSHOP + 1], 1)
							end
							if t % 60 == i % 60 then
								A.custom(p, "BoopDone", 1)
							end
							if t % 150 == i % 150 then
								A.custom(p, "ComboLength", 3)
							end
						end
						if t == 600 then
							for _, p in w.ps do
								w.Signals.RecordReached:Fire(p, 14) -- aucun palier
								w.Signals.RecordReached:Fire(p, 15) -- palier de ranch n° 5
							end
						end
						-- la même ligne de l'Atelier deux fois dans une tranche : champ level = le plus haut
						if t == 1805 or t == 1810 then
							local c = w.Economy.addConfetti(w.ps[1], 20, "record")
							local x = want[w.ps[1].UserId]
							x.earned.RecordBonus = (x.earned.RecordBonus or 0) + c
							buy(w.ps[1], "nightBag", 1)
						end
					end
					D.step(now)
					expectGap(now)
					if t % 10 == 0 then
						w.h:settle(1)
					end
					harvest(t)
				end
				w.h:settle(2)
				harvest(HOUR + 1201)
				-- débit et pertes
				local stats = A.stats()
				expect(worstOf(HOUR + 1201)).toBeLessThanOrEqual(10)
				expect(stats.dropped).toBe(0)
				expect(stats.unknown).toBe(0)
				for _, p in w.ps do
					expect({ id = p.UserId, pending = A.stats(p).pending }).toEqual({
						id = p.UserId,
						pending = 0,
					})
				end
				-- relevé par joueur
				local got = {}
				for _, p in w.ps do
					got[p.UserId] = {
						up = {},
						ws = {},
						wsLevel = {},
						earned = {},
						ecoEarned = {},
						ecoSpent = {},
						share = {},
						gap = 0,
						tiers = {},
						lastBalance = nil,
					}
				end
				local Flow = w.h.globals.Enum.AnalyticsEconomyFlowType
				for _, c in w.h.log.analytics do
					local p, x = c.args[1], nil
					x = got[p.UserId]
					if c.method == "LogCustomEvent" then
						local name, value = c.args[2], c.args[3]
						local f = fieldsOf(w, c.args)
						if string.sub(name, 1, 8) == "Upgrade_" then
							local fam = string.sub(name, 9)
							x.up[fam] = (x.up[fam] or 0) + value
						elseif string.sub(name, 1, 12) == "WorkshopBuy_" then
							local line = string.sub(name, 13)
							x.ws[line] = (x.ws[line] or 0) + value
							x.wsLevel[line] = math.max(x.wsLevel[line] or 0, tonumber(f.level) or 0)
						elseif name == "ConfettiEarned" then
							x.earned[f.source] = (x.earned[f.source] or 0) + value
						elseif name == "HelperCoinsShare" then
							table.insert(x.share, value)
						elseif name == "NextGoalGap" then
							x.gap += value
						elseif name == "RanchTierReached" then
							table.insert(x.tiers, { value, f.bestR })
						end
					elseif c.method == "LogEconomyEvent" and c.args[3] == "Confetti" then
						local amount, balance, sku = c.args[4], c.args[5], c.args[7]
						expect(amount % 1).toBe(0)
						if c.args[2] == Flow.Source then
							x.ecoEarned[sku] = (x.ecoEarned[sku] or 0) + amount
						else
							x.ecoSpent[sku] = (x.ecoSpent[sku] or 0) + amount
							expect(c.args[6]).toBe("Shop")
						end
						x.lastBalance = balance
					end
				end
				local totals = { up = 0, ws = 0, earned = 0, spent = 0, shares = 0, gapPlayers = 0 }
				for _, p in w.ps do
					local id = p.UserId
					local x, y = want[id], got[id]
					expect({ id = id, up = y.up }).toEqual({ id = id, up = x.up })
					expect({ id = id, ws = y.ws }).toEqual({ id = id, ws = x.ws })
					expect({ id = id, level = y.wsLevel }).toEqual({ id = id, level = x.wsLevel })
					expect({ id = id, earned = y.earned }).toEqual({ id = id, earned = x.earned })
					expect({ id = id, eco = y.ecoEarned }).toEqual({ id = id, eco = x.earned })
					expect({ id = id, spent = y.ecoSpent }).toEqual({ id = id, spent = x.spent })
					-- solde du dernier mouvement = Confettis en poche à la fin
					expect({ id = id, balance = y.lastBalance }).toEqual({
						id = id,
						balance = w.DS.get(p).confetti,
					})
					expect({ id = id, tiers = y.tiers }).toEqual({ id = id, tiers = { { 5, "15" } } })
					-- HelperCoinsShare : une valeur par tranche où les Plopettes ont rapporté, dans l'ordre
					local slices = {}
					for b in credited[id] or {} do
						table.insert(slices, b)
					end
					table.sort(slices)
					local shares = {}
					for _, b in slices do
						local e = credited[id][b]
						if e.helper > 0 then
							table.insert(shares, math.floor(1000 * e.helper / e.gameplay + 0.5) / 10)
						end
					end
					expect({ id = id, share = y.share }).toEqual({ id = id, share = shares })
					-- NextGoalGap : total exact (arrondi par tranche : ± 1 s par tranche envoyée)
					local slack = 12
					expect({ id = id, gapOk = math.abs(y.gap - gap[id].total) <= slack }).toEqual({
						id = id,
						gapOk = true,
					})
					for _, n in x.up do
						totals.up += n
					end
					for _, n in x.ws do
						totals.ws += n
					end
					for _, n in x.earned do
						totals.earned += n
					end
					for _, n in x.spent do
						totals.spent += n
					end
					totals.shares += #shares
					if id > 12 then
						-- 20 min sans but (achats coupés) : au moins 1 000 s comptées
						expect({ id = id, idle = y.gap >= 1000 }).toEqual({ id = id, idle = true })
						totals.gapPlayers += 1
					end
				end
				-- la partie a vraiment tout exercé
				expect(totals.up > 16 * 40).toBe(true)
				expect(totals.ws >= 16 * 3).toBe(true)
				expect(totals.earned > 16 * 100).toBe(true)
				expect(totals.spent > 0).toBe(true)
				expect(totals.shares >= 16 * 12).toBe(true)
				-- toutes les sources de Confettis du GDD §16.2 sont passées
				local sources = {}
				for _, p in w.ps do
					for sku in got[p.UserId].ecoEarned do
						sources[sku] = true
					end
				end
				for _, sku in SKU do
					expect({ sku = sku, seen = sources[sku] == true }).toEqual({ sku = sku, seen = true })
				end
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)
	end)

	describe("Analytics_v2 › interrupteurs coupés", function()
		-- jeu de base (profils v1, interrupteurs coupés : serveur de la v1.3, préréglage « v13 », lot I D2 a ;
		-- le chemin du lancement est couvert par « une heure de jeu v2.0 » plus haut) : mêmes gestes, 30 min ;
		-- rend le relevé { "méthode|nom|sku|monnaie" = nombre } et la liste des noms
		local function baseRun(withMeta)
			local w = world(Flags.harness(Harness, "v13"), {
				n = 6,
				R = 2,
				before = if withMeta
					then nil
					else function(ww)
						local M = ww.h:require("ServerScriptService.Server.Meta.MetaAnalytics")
						M.start = function() end
						M.step = function() end
					end,
			})
			local A, D, E = w.A, w.D, w.Economy
			local tiles = { "snack", "decor", "pens" }
			for t = 1, 1800 do
				w.Clock.advance(1)
				local now = w.Clock.now()
				for i, p in w.ps do
					local src = SOURCES[(t + i) % #SOURCES + 1]
					if src[1] ~= "Helper" then
						E.addCoins(p, src[2], src[1], "Gameplay")
					end
					if t % 45 == i % 45 then
						E.buyTile(p, tiles[(t // 45 + i) % #tiles + 1], "panel")
					end
					if t % 60 == i % 60 then
						A.custom(p, "BoopDone", 1)
					end
					if t % 20 == i % 20 then
						w.Activity.note(p, now)
					end
				end
				D.step(now)
				if t % 10 == 0 then
					w.h:settle(1)
				end
			end
			for _ = 1, 600 do
				w.Clock.advance(1)
				D.step(w.Clock.now())
			end
			w.h:settle(2)
			local counts, names = {}, {}
			for _, c in w.h.log.analytics do
				local key
				if c.method == "LogCustomEvent" then
					key = "custom|" .. c.args[2]
					names[c.args[2]] = true
				elseif c.method == "LogEconomyEvent" then
					key = "eco|" .. tostring(c.args[7]) .. "|" .. tostring(c.args[3])
				else
					key = c.method
				end
				counts[key] = (counts[key] or 0) + 1
			end
			expect(table.concat(Brains.problems(w), "\n")).toBe("")
			return counts, names, w
		end

		it(
			"mêmes noms et mêmes nombres que le jeu de base (MetaAnalytics retiré) ; aucun nom ni aucune monnaie v2.0",
			function()
				local withMeta, names, w = baseRun(true)
				local without = baseRun(false)
				expect(withMeta).toEqual(without)
				-- aucun nom v2.0, aucune monnaie Confetti, aucune famille Upgrade_ / WorkshopBuy_
				local V2 = {
					"UpgradeMode",
					"ConfettiEarned",
					"UpgradeTimeout",
					"UpgradeStale",
					"NextGoalGap",
					"HelperCoinsShare",
					"RanchTierReached",
					"AscendPreview",
					"AscendDone",
					"AscendDeclined",
					"TextScaleMeasured",
					"PetitSplorch",
					"WeeklyTrackTier",
					"PhotoMode",
				}
				for _, name in V2 do
					expect({ name = name, sent = names[name] == true }).toEqual({ name = name, sent = false })
				end
				for key in withMeta do
					expect({
						key = key,
						v2 = string.find(key, "|Confetti", 1, true) ~= nil
							or string.find(key, "custom|Upgrade_", 1, true) ~= nil
							or string.find(key, "custom|WorkshopBuy_", 1, true) ~= nil,
					}).toEqual({ key = key, v2 = false })
				end
				-- la partie de base a bien envoyé de l'économie et des événements
				expect((withMeta["custom|BoopDone"] or 0) > 0).toBe(true)
				expect((withMeta["eco|Tile_snack|Coins"] or 0) > 0).toBe(true)
				expect(w.A.stats().unknown).toBe(0)
			end
		)

		it(
			"profils v2, interrupteurs coupés un par un : chaque événement v2.0 se tait (achat, Confettis, palier, compteur transmis, temps sans but)",
			function()
				-- tout ouvert sauf l'interrupteur de l'événement observé
				local cases = {
					{ off = "UpgradesScreen", names = { "Upgrade_gloves", "NextGoalGap", "UpgradeStale" } },
					{ off = "Confetti", names = { "ConfettiEarned" }, currency = "Confetti" },
					{ off = "Workshop", names = { "WorkshopBuy_gift" } },
					{ off = "RanchTiers", names = { "RanchTierReached" } },
				}
				for _, case in cases do
					local flags = {}
					for _, key in FLAGS do
						if key ~= case.off then
							table.insert(flags, key)
						end
					end
					-- Confettis en poche dès l'arrivée : un achat de l'Atelier reste possible Confetti coupé
					-- départ « coupure d'urgence » (préréglage « cut » : SchemaV2 seul ; lot I, étape 2) puis
					-- tout ouvert en direct sauf l'interrupteur observé
					local w = world(Flags.harness(Harness, "cut"), { flags = flags, n = 2, confetti = 200 })
					local E = w.Economy
					local UpgradeMath = w.h:require(L .. "Logic.UpgradeMath")
					for t = 1, 900 do
						w.Clock.advance(1)
						local now = w.Clock.now()
						for i, p in w.ps do
							E.addCoins(p, 100, "Press", "Gameplay")
							w.Activity.note(p, now)
							if t == 10 * i then
								local d = w.DS.get(p)
								E.addConfetti(p, 30, "splorch")
								E.buyUpgrade(p, "gloves", 1, UpgradeMath.level("gloves", d))
								E.buyUpgrade(p, "gift", 1, UpgradeMath.level("gift", d))
								E.buyUpgrade(p, "gloves", 1, 99) -- périmé : UpgradeStale compté
								w.Signals.RecordReached:Fire(p, 3)
							end
						end
						w.D.step(now)
					end
					w.h:settle(2)
					for _, c in w.h.log.analytics do
						if c.method == "LogCustomEvent" then
							for _, name in case.names do
								expect({ off = case.off, name = c.args[2] == name }).toEqual({
									off = case.off,
									name = false,
								})
							end
						elseif c.method == "LogEconomyEvent" and case.currency then
							expect({ off = case.off, currency = c.args[3] }).toEqual({
								off = case.off,
								currency = "Coins",
							})
						end
					end
					-- l'interrupteur rouvert : l'événement revient (le test voit bien l'événement)
					assert(w.Features.set(case.off, true))
					w.Clock.advance(1)
					for _, p in w.ps do
						local d = w.DS.get(p)
						E.addConfetti(p, 30, "splorch")
						E.buyUpgrade(p, "gloves", 1, UpgradeMath.level("gloves", d))
						E.buyUpgrade(p, "gift", 1, UpgradeMath.level("gift", d))
						E.buyUpgrade(p, "gloves", 1, 99)
						w.Signals.RecordReached:Fire(p, 5)
					end
					for _ = 1, 900 do
						w.Clock.advance(1)
						for _, p in w.ps do
							w.Activity.note(p, w.Clock.now())
						end
						w.D.step(w.Clock.now())
					end
					w.h:settle(2)
					local seen = {}
					for _, c in w.h.log.analytics do
						if c.method == "LogCustomEvent" then
							seen[c.args[2]] = true
						elseif c.method == "LogEconomyEvent" then
							seen[c.args[3]] = true
						end
					end
					for _, name in case.names do
						expect({ off = case.off, name = name, back = seen[name] == true }).toEqual({
							off = case.off,
							name = name,
							back = true,
						})
					end
					expect(table.concat(Brains.problems(w), "\n")).toBe("")
				end
			end
		)
	end)

	-- Lot I, étape 2 (D5, plan I M2, journal I-17) : AscendDone(A, r, jours depuis la précédente) ; la
	-- première Ascension compte depuis la première arrivée (firstJoin) ; horloge reculée : 0
	describe("Analytics_v2 › AscendDone et ses jours (lot I, D5)", function()
		local DAY = 86400
		local function ascendOnce(edit)
			local w = Brains.boot(HarnessV2, { t0 = T0, stubMeta = false })
			for _, key in { "RecordR", "Confetti", "JellyAscend", "PetitSplorch" } do
				assert(w.Features.set(key, true), key)
			end
			local hero = Brains.join(w, 1, {
				profile = Brains.profile(w, {
					coins = 5000,
					R = 15,
					squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 }, { s = 3, z = 300 } },
					tiles = { snack = 12, decor = 10 },
					edit = function(d)
						d.bestR = 15
						edit(d)
					end,
				}),
			})
			Bots.place(hero, Brains.atRanch(w, hero, 0, 30))
			Brains.frames(w, 2)
			w.h:fireServer("ReplicatedStorage.Remotes.JellyAscend", hero, true)
			Brains.frames(w, 200)
			local found = {}
			for _, c in w.h.log.analytics do
				if c.method == "LogCustomEvent" and c.args[2] == "AscendDone" then
					table.insert(found, { value = c.args[3], f = fieldsOf(w, c.args) })
				end
			end
			local data = w.DS.get(hero)
			expect(table.concat(Brains.problems(w), "\n")).toBe("")
			return found, data, w
		end

		it(
			"première Ascension : jours depuis firstJoin ; suivante : depuis ascendDay ; horloge reculée : 0 ; ascendDay = jour de l'Ascension",
			function()
				local today = math.floor(T0 / DAY)
				for _, case in
					{
						{
							edit = function(d)
								d.firstJoin = T0 - 10 * DAY
								d.ascendDay = 0
							end,
							days = 10,
						},
						{
							edit = function(d)
								d.firstJoin = T0 - 40 * DAY
								d.ascendDay = today - 4
							end,
							days = 4,
						},
						{
							edit = function(d)
								d.firstJoin = T0 - 40 * DAY
								d.ascendDay = today + 3
							end,
							days = 0,
						},
						{
							edit = function(d)
								d.firstJoin = 0
								d.ascendDay = 0
							end,
							days = 0,
						},
					}
				do
					local found, data = ascendOnce(case.edit)
					expect(#found).toBe(1)
					expect(found[1].value).toBe(1) -- A après l'Ascension
					expect(found[1].f).toEqual({ bestR = "15", days = tostring(case.days), r = "15" })
					expect(data.ascendDay).toBe(today)
				end
			end
		)
	end)
end
