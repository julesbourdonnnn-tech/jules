--!nocheck
-- EconomyPacing (paquet A1, docs/04 §27.9 ; GDD §4.24, §4.24.1) : PORTE BLOQUANTE du rythme de
-- l'économie, jouée par tests/sim/EconomyModel (vraies formules, vraies tables, vrais modules de la
-- progression), graine fixe, aux 3 tailles de serveur.
--  1. Jeu de base (interrupteurs v2.0 COUPÉS, comme la version de test) : la porte v1.3 telle quelle
--     (docs/04 §16 v1.2) : 50 joueurs de référence × 28 jours × 4, 8 et 16 joueurs, gros acheteur.
--  2. Jeu complet v2.0 (interrupteurs de l'économie OUVERTS dans le modèle seulement ; le jeu les
--     garde coupés) : chaque clé du §27.9 pour check.sh — 20 joueurs par taille de serveur, joueur de
--     référence 84 jours, joueur assidu (2 h par jour) 28 jours, et la référence sans Ascension
--     (28 jours, serveur de 16) pour recordRDay28. Toutes les clés de la v1.3 sont gardées.
--  3. La nuit (scripts/economy-nightly.sh) : ECON_NIGHT=<cas> joue un cas du jeu de nuit (50 joueurs,
--     140 jours, profils de la critique, gros acheteur, profils forcés) au lieu des parties 1 et 2.
--     ECON_NIGHT=custom ECON_PROFILE=ref|assidu ECON_SIZE=16 ECON_DAYS=84 ECON_NIGHT_PLAYERS=200 :
--     lancement manuel d'une configuration (mêmes clés que check.sh).
-- ECON_PLAYERS : joueurs de la porte v1.3 (50) ; ECON_V2_PLAYERS : joueurs de la porte v2.0 (20).
-- Chaque clé est imprimée (valeur, limites, OK/HORS) ; un test par groupe du §27.9 et par
-- configuration échoue dès qu'une clé du groupe sort de ses limites, et les nomme toutes.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local process = require("@lune/process")
	local Sim = require("../sim/Sim")
	local EconomyModel = require("../sim/EconomyModel")

	local h = Harness.new()
	local function logic(name)
		return h:require("ReplicatedStorage.Shared.Logic." .. name)
	end
	local function config(name)
		return h:require("ReplicatedStorage.Shared.Config." .. name)
	end
	local L = {
		Formulas = logic("Formulas"),
		Odds = logic("Odds"),
		FusionRules = logic("FusionRules"),
		QuestRules = logic("QuestRules"),
		RushRules = logic("RushRules"),
		EventClock = logic("EventClock"),
		Hash = logic("Hash"),
		Prestige = logic("Prestige"),
		UpgradeMath = logic("UpgradeMath"),
		UpgradeAdvisor = logic("UpgradeAdvisor"),
		Bitset = logic("Bitset"),
		Balance = config("Balance"),
		Species = config("Species"),
		Rarities = config("Rarities"),
		Mutations = config("Mutations"),
		Quests = config("Quests"),
		Events = config("Events"),
		Features = config("Features"),
		Upgrades = config("Upgrades"),
	}
	local Features, Balance, Prestige = L.Features, L.Balance, L.Prestige

	local PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_PLAYERS) or 50))
	local V2_PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_V2_PLAYERS) or 20))
	local NIGHT = process.env.ECON_NIGHT
	local SPENDERS = math.min(PLAYERS, 20)
	local DAYS, SEED = 28, 20261212

	-- =============================================================================================
	-- Interrupteurs : coupés (jeu de base) ou tous ceux de l'économie ouverts (v2.0, dans le modèle)
	-- =============================================================================================
	local function withFlags(on, fn)
		Features.reset()
		if on then
			for _, key in EconomyModel.ECON_FLAGS do
				assert(Features.set(key, true), "interrupteur refusé : " .. key)
			end
		end
		local out = table.pack(pcall(fn))
		Features.reset()
		if not out[1] then
			error(out[2], 0)
		end
		return table.unpack(out, 2, out.n)
	end

	-- =============================================================================================
	-- Partie 1 : porte v1.3 (jeu de base, interrupteurs coupés)
	-- =============================================================================================
	local function baseGate()
		describe("EconomyPacing v1.3 (jeu de base, interrupteurs v2.0 coupés, GDD §4.24)", function()
			local model = EconomyModel.new(L)
			local results = {}
			withFlags(false, function()
				for _, size in EconomyModel.SIZES do
					local result = Sim.run({
						players = PLAYERS,
						days = DAYS,
						seed = SEED,
						simulate = model.simulateFor({ players = size }),
						gates = EconomyModel.GATES,
						reported = EconomyModel.REPORTED,
					})
					results[size] = result
					print(
						string.format(
							"\n  — Jeu de base, serveur de %d joueurs (%d joueurs de référence, %d jours) —",
							size,
							PLAYERS,
							DAYS
						)
					)
					print(Sim.report(result))
				end
			end)

			for _, size in EconomyModel.SIZES do
				it(`serveur de {size} : chaque médiane (rythme et santé) est dans sa tolérance`, function()
					expect(table.concat(Sim.failures(results[size]), ", ")).toBe("")
				end)

				it(`serveur de {size} : les parts de joueurs sont tenues`, function()
					local failures = {}
					for _, share in EconomyModel.SHARES do
						local hits = 0
						for _, player in results[size].players do
							hits += player[share.key] or 0
						end
						local ratio = hits / #results[size].players
						print(
							string.format(
								"  [%2d] %-36s %5.1f %%   (au moins %d %%)",
								size,
								share.label,
								ratio * 100,
								share.min * 100
							)
						)
						if ratio < share.min then
							table.insert(failures, share.label)
						end
					end
					expect(table.concat(failures, ", ")).toBe("")
				end)
			end

			it(
				"gros acheteur (×2 Pièces, Grand Ranch, Squish Party la moitié du temps) : ≤ 2 R d'avance au jour 28",
				function()
					local spender = withFlags(false, function()
						return Sim.run({
							players = SPENDERS,
							days = DAYS,
							seed = SEED,
							simulate = model.simulateFor({ players = 16, spender = true }),
							gates = {},
							reported = {
								{ key = "rDay28", label = "R en fin de jour 28" },
								{ key = "firstSplorch", label = "x" },
							},
						})
					end)
					local reference = {}
					for i = 1, SPENDERS do
						table.insert(reference, results[16].players[i].rDay28)
					end
					local lead = spender.medians.rDay28 - Sim.median(reference)
					print(
						string.format(
							"  Gros acheteur : R jour 28 médiane %.1f (référence %.1f, avance %.1f R) ; premier Grand Splorch %.1f min",
							spender.medians.rDay28,
							Sim.median(reference),
							lead,
							spender.medians.firstSplorch
						)
					)
					expect(lead <= EconomyModel.SPENDER_MAX_LEAD).toBe(true)
					expect(lead >= 0).toBe(true) -- « plus tôt, pas plus haut », mais jamais moins
				end
			)

			it("déterministe : même graine, même joueur, mêmes jalons", function()
				local a, b = withFlags(false, function()
					local simulate = model.simulateFor({ players = 8 })
					return simulate(Sim.newRng(SEED * 1000003 + 1), 1, 3),
						simulate(Sim.newRng(SEED * 1000003 + 1), 1, 3)
				end)
				expect(a.firstSplorch).toBe(b.firstSplorch)
				expect(a.rDay1).toBe(b.rDay1)
				expect(a.stamps30).toBe(b.stamps30)
				expect(a.boostShare).toBe(b.boostShare)
			end)
		end)
	end

	-- =============================================================================================
	-- Partie 2 : clés de la porte v2.0 (docs/04 §27.9, GDD §4.24.1)
	-- =============================================================================================

	-- Jalons de la v1.3 sur la v2.0 : Record R aux jours 7, 14 et 28 (r redescend après une Ascension)
	local V13_KEYS = {}
	local RECORD_OF = { rDay7 = 7, rDay14 = 14, rDay28 = 28 }
	for _, g in EconomyModel.GATES do
		local day = RECORD_OF[g.key]
		local key = if day then "recordDay" .. day else g.key
		local label = if day then `Record R en fin de jour {day}` else g.label
		table.insert(V13_KEYS, { key = key, label = label, min = g.min, max = g.max })
	end

	-- Limites du temps « sans but » par bande (EconomyModel.BANDS) et par profil
	local STARVED = {
		ref = { 0.01, 0.05, 0.15, 0.20, 0.20, 0.20, 0.20 },
		assidu = { 0.01, 0.15, 0.30, 0.30, 0.30, 0.30, 0.30 },
		allday = { 0.30, 0.30, 0.30, 0.30, 0.30, 0.30, 0.30 },
	}
	local GAP_P90_MAX = 15 -- min : plus long trou d'un joueur de 2 h par jour, p90, dans chaque bande
	local ASCEND = {
		ref = { first = { 12, 16 }, gap = { 10, 16 } },
		assidu = { first = { 5, 9 }, gap = { 4, 8 } },
	}
	local FAMILIES = { "snack", "star", "decor", "gloves", "school" }

	local function quant(list, q)
		if #list == 0 then
			return 0 / 0
		end
		return Sim.quantile(list, q)
	end
	local function median(list)
		return quant(list, 0.5)
	end

	-- Agrégats v2.0 d'une configuration (tous ses joueurs)
	local function v2Stats(result)
		local players = result.players
		local st = { players = #players }
		-- temps « sans but » (somme des dépassements de 3 min ÷ temps de jeu de la bande, tous joueurs)
		st.bands = {}
		for bi in EconomyModel.BANDS do
			local tot, over, gaps = 0, 0, {}
			for _, m in players do
				local b = m.v2.bands[bi]
				tot += b.tot
				over += b.over
				if b.tot > 0 then
					table.insert(gaps, b.maxGap / 60)
				end
			end
			st.bands[bi] =
				{ tot = tot, starved = if tot > 0 then over / tot else nil, gapP90 = quant(gaps, 0.9) }
		end
		-- boucles
		local loopGapByR, lostByBand, after =
			{}, {}, { n = 0, under45 = 0, unfused = 0, zero = 0, shortest = math.huge }
		local shareByA, buysByA, allRecordShare = {}, {}, {}
		local fam = {}
		for _, f in FAMILIES do
			fam[f] = { open = 0, bought = 0 }
		end
		local zeroGap, nonFinite, applyRefused = 0, 0, 0
		local maxR, maxBestR, maxA = 0, 0, 0
		local regain, cliff, offPot = {}, {}, {}
		local recordDrops, confettiNegative = 0, 0
		for _, m in players do
			local x = m.v2
			-- Record R jamais en baisse, Confettis jamais négatifs, total gagné jamais en baisse
			local prev = nil
			for d = 1, #x.daily do
				local day = x.daily[d]
				if day then
					if prev and (day.best < prev.best or day.confTotal < prev.confTotal) then
						recordDrops += 1
					end
					if day.conf < 0 or day.conf > day.confTotal then
						confettiNegative += 1
					end
					prev = day
				end
			end
			zeroGap += x.zeroGap
			nonFinite += x.nonFinite + m.nonFinite
			applyRefused += m.applyRefused
			maxR, maxBestR, maxA =
				math.max(maxR, m.maxR), math.max(maxBestR, m.maxBestR), math.max(maxA, m.maxA)
			for _, v in x.regain do
				table.insert(regain, v)
			end
			for _, v in x.cliff do
				table.insert(cliff, v)
			end
			for _, v in x.offPot do
				table.insert(offPot, v)
			end
			for _, l in x.loops do
				if not l.afterAscend and not l.petit and l.r <= 13 then
					loopGapByR[l.r] = loopGapByR[l.r] or {}
					table.insert(loopGapByR[l.r], l.maxBuyGap / 60)
				end
				if not l.petit then
					local bi = nil
					for i, b in EconomyModel.BANDS do
						if l.d >= b.from and l.d <= b.to then
							bi = i
						end
					end
					if bi and bi >= 2 then
						lostByBand[bi] = lostByBand[bi] or {}
						table.insert(lostByBand[bi], l.lost)
					end
					if l.A >= 1 then
						shareByA[l.A] = shareByA[l.A] or {}
						table.insert(shareByA[l.A], l.share12)
						buysByA[l.A] = buysByA[l.A] or {}
						table.insert(buysByA[l.A], l.snack + l.star)
						table.insert(allRecordShare, l.share12)
					end
				end
				if l.afterAscend then
					after.n += 1
					after.shortest = math.min(after.shortest, l.len)
					if l.len <= 0 then
						after.zero += 1
					end
					if l.len < 45 then
						after.under45 += 1
						if l.sinceFuse > 10 then
							after.unfused += 1
						end
					end
				end
				-- familles ouvertes dans la boucle (r de la boucle ; Tapis Étoilé : Tapis 12 atteint avant la fin)
				local open = {
					snack = true,
					star = l.r >= 6 and l.share12 < 0.999,
					decor = true,
					gloves = l.r >= 1,
					school = l.r >= 2,
				}
				for _, f in FAMILIES do
					if open[f] then
						fam[f].open += 1
						if l[f] > 0 then
							fam[f].bought += 1
						end
					end
				end
			end
		end
		st.loopGapByR, st.lostByBand, st.after = loopGapByR, lostByBand, after
		st.shareByA, st.buysByA, st.allRecordShare, st.fam = shareByA, buysByA, allRecordShare, fam
		st.zeroGap, st.nonFinite, st.applyRefused = zeroGap, nonFinite, applyRefused
		st.recordDrops, st.confettiNegative = recordDrops, confettiNegative
		st.maxR, st.maxBestR, st.maxA = maxR, maxBestR, maxA
		st.regain, st.cliff, st.offPot = regain, cliff, offPot
		-- Ascensions : jour médian de la k-ième (joueurs qui ne l'ont pas : jamais), écart médian
		st.ascendDay, st.ascendGap, st.ascendReached = {}, {}, {}
		for k = 1, Balance.Prestige.MaxA do
			local days, gaps, reached = {}, {}, 0
			for _, m in players do
				local d = m.v2.ascendDays[k]
				table.insert(days, d or math.huge)
				if d then
					reached += 1
					local prev = m.v2.ascendDays[k - 1]
					if prev then
						table.insert(gaps, d - prev)
					end
				end
			end
			if reached == 0 then
				break
			end
			st.ascendDay[k] = Sim.median(days)
			st.ascendGap[k] = quant(gaps, 0.5)
			st.ascendReached[k] = reached
		end
		-- état de fin de journée (médianes)
		st.daily = function(d, field)
			local list = {}
			for _, m in players do
				local x = m.v2.daily[d]
				if x then
					table.insert(list, x[field])
				end
			end
			return median(list)
		end
		st.metric = function(key)
			local list = {}
			for _, m in players do
				local v = m[key]
				table.insert(list, if type(v) == "number" and v == v then v else math.huge)
			end
			return median(list)
		end
		return st
	end

	-- Liste de clés : { group, label, value, lo, hi, ok, reported }
	local function newKeys()
		local keys = {}
		local function add(group, label, value, lo, hi, reported)
			local ok = type(value) == "number"
				and value == value
				and (lo == nil or value >= lo)
				and (hi == nil or value <= hi)
			table.insert(keys, {
				group = group,
				label = label,
				value = value,
				lo = lo,
				hi = hi,
				ok = ok or reported == true,
				reported = reported == true,
			})
		end
		return keys, add
	end
	local function fmt(v)
		if type(v) ~= "number" then
			return tostring(v)
		elseif v == math.huge then
			return "jamais"
		elseif v ~= v then
			return "—"
		elseif math.abs(v) >= 1e4 or (v ~= 0 and math.abs(v) < 0.01) then
			return string.format("%.3g", v)
		end
		local text = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
		return text
	end
	local function printKeys(title, keys)
		print("\n  — " .. title .. " —")
		for _, k in keys do
			local limits = if k.lo == nil and k.hi == nil
				then ""
				else string.format(
					"[%s ; %s]",
					if k.lo == nil then "—" else fmt(k.lo),
					if k.hi == nil then "—" else fmt(k.hi)
				)
			print(
				string.format(
					"  %-15s %-58s %12s  %-18s %s",
					k.group,
					k.label,
					fmt(k.value),
					limits,
					if k.reported then "(rapporté)" elseif k.ok then "OK" else "HORS"
				)
			)
		end
	end
	local function failuresOf(keys, group)
		local out = {}
		for _, k in keys do
			if (group == nil or k.group == group) and not k.ok then
				table.insert(out, k.label .. " = " .. fmt(k.value))
			end
		end
		return out
	end

	-- Clés du §27.9 d'une configuration. profile : "ref" | "assidu" | "allday" | "other" (10 et 20 min,
	-- week-end : limites de la référence pour le temps « sans but » seulement). opts : { v13 = bool
	-- (jalons de la v1.3 et parts), ascend = bool (clés de la Jelly Ascend), atelier = bool (clés de
	-- l'Atelier), loopGap = bool (loopMaxGap bloquant), noAscend = stats sans Ascension (recordRDay28) }
	local function v2Keys(result, profile, opts)
		local st = v2Stats(result)
		local keys, add = newKeys()
		local starvedLimits = STARVED[profile] or STARVED.ref
		-- jalons de la v1.3
		if opts.v13 then
			for _, g in V13_KEYS do
				add("Jalons v1.3", g.label, st.metric(g.key), g.min, g.max)
			end
			for _, share in EconomyModel.SHARES do
				local hits = 0
				for _, m in result.players do
					hits += m[share.key] or 0
				end
				add("Jalons v1.3", share.label .. " (part)", hits / #result.players, share.min, nil)
			end
		end
		-- temps « sans but »
		for bi, b in EconomyModel.BANDS do
			local band = st.bands[bi]
			if band.starved ~= nil then
				add("Sans but", "starved" .. b.key, band.starved, nil, starvedLimits[bi])
				if profile == "assidu" then
					add(
						"Sans but",
						"longestGapAssiduP90 " .. b.key .. " (min)",
						band.gapP90,
						nil,
						GAP_P90_MAX
					)
				else
					add("Sans but", "plus long trou p90 " .. b.key .. " (min)", band.gapP90, nil, nil, true)
				end
			end
		end
		-- boucles
		for r = 0, 13 do
			local list = st.loopGapByR[r]
			if list and #list >= 3 then
				local reported = not opts.loopGap
				add("Boucles", `loopMaxGap r{r} médiane (min)`, median(list), nil, 3, reported)
				add("Boucles", `loopMaxGap r{r} p90 (min)`, quant(list, 0.9), nil, 5, reported)
			end
		end
		for bi, b in EconomyModel.BANDS do
			local list = st.lostByBand[bi]
			if list and #list >= 5 then
				add(
					"Boucles",
					"coinsLostRatioGrand " .. b.key .. " (T12)",
					median(list),
					0.2,
					3,
					profile == "other"
				)
			end
		end
		local after = st.after
		if after.n > 0 then
			add("Boucles", "shortestLoopSec : part sous 45 s", after.under45 / after.n, nil, 0.003)
			add("Boucles", "shortestLoopSec : sous 45 s à plus de 10 s d'une fusion", after.unfused, 0, 0)
			add("Boucles", "shortestLoopSec : boucles de 0 s", after.zero, 0, 0)
			add("Boucles", "shortestLoopSec : plus courte (s)", after.shortest, nil, nil, true)
		end
		add("Boucles", "zeroGapRenaissances", st.zeroGap, 0, 0)
		-- Jelly Ascend
		if opts.ascend then
			local lim = ASCEND[profile]
			add(
				"Jelly Ascend",
				"ascend1Day (médiane)",
				st.ascendDay[1] or math.huge,
				lim.first[1],
				lim.first[2]
			)
			for k = 2, #st.ascendDay do
				-- écart de la k-ième Ascension, si au moins la moitié des joueurs l'ont faite
				if st.ascendReached[k] * 2 >= st.players then
					add(
						"Jelly Ascend",
						`ascendGapDays A{k - 1}→A{k}`,
						st.ascendGap[k],
						lim.gap[1],
						lim.gap[2]
					)
				end
			end
			add("Jelly Ascend", "regainRatio (médiane)", median(st.regain), 0.10, 0.40)
			add("Jelly Ascend", "regainCliff médiane", median(st.cliff), nil, 4)
			add("Jelly Ascend", "regainCliff p90", quant(st.cliff, 0.9), nil, 4)
			if opts.noAscend then
				local without = opts.noAscend.metric("recordDay28")
				add(
					"Jelly Ascend",
					`recordRDay28 (sans Ascension : {fmt(without)})`,
					st.metric("recordDay28"),
					without - 1
				)
			end
			for a = 1, 30 do
				local list = st.shareByA[a]
				if list and #list >= 3 then
					add("Jelly Ascend", `tapis12RecordLoopByA A{a} (médiane)`, median(list), 0.45, 0.95)
					local buys = 0
					for _, v in st.buysByA[a] do
						buys += v
					end
					add("Jelly Ascend", `purchasesPerRecordLoopByA A{a}`, buys / #st.buysByA[a], 10)
				end
			end
			if #st.allRecordShare > 0 then
				add(
					"Jelly Ascend",
					"tapis12RecordLoop, toutes les boucles record",
					median(st.allRecordShare),
					0.5,
					0.9
				)
			end
		end
		-- Confettis et Atelier
		if opts.atelier then
			local worst = 0
			for d = 1, math.min(84, opts.days) do
				worst = math.max(worst, st.daily(d, "conf"))
			end
			add("Atelier", "confettiUnspent (pire médiane, jours 1-84)", worst, nil, 300)
			add("Atelier", "workshopAllDay (médiane)", st.metric("workshopAllDay"), 35)
			add("Atelier", "firstWorkshopBuy (min, médiane)", st.metric("firstWorkshopBuy"), nil, 35)
			add(
				"Atelier",
				"Atelier et « Pour le plaisir » complets (jour)",
				st.metric("atelierCompleteDay"),
				nil,
				nil,
				true
			)
		end
		-- familles
		for _, f in FAMILIES do
			local x = st.fam[f]
			if x.open > 0 then
				add("Familles", "everyFamilyBought " .. f, x.bought / x.open, 0.8)
			end
		end
		if profile == "ref" or profile == "assidu" then
			if opts.days >= 7 then
				add(
					"Familles",
					"monumentsDay7",
					st.daily(7, "mon"),
					if profile == "ref" then 1 else nil,
					if profile == "ref" then 3 else nil,
					profile ~= "ref"
				)
			end
			if opts.days >= 28 then
				add("Familles", "monumentsDay28", st.daily(28, "mon"), 4)
			end
			add("Familles", "helperShareDay7", st.metric("helperShareDay7"), 0.05, 0.15)
		end
		-- hors ligne, bornes
		add("Bornes", "offlinePotShare (médiane)", median(st.offPot), nil, 2)
		add("Bornes", "offlinePotShare p90", quant(st.offPot, 0.9), nil, nil, true)
		add("Bornes", "nonFinite", st.nonFinite, 0, 0)
		add(
			"Bornes",
			"MaxR jamais dépassé (r, Record R)",
			math.max(st.maxR, st.maxBestR),
			0,
			Balance.Prestige.MaxR
		)
		add("Bornes", "MaxA jamais dépassé", st.maxA, 0, Balance.Prestige.MaxA)
		add("Bornes", "Prestige.apply refusé par le jeu (défaut du modèle)", st.applyRefused, 0, 0)
		add("Bornes", "Record R ou Confettis gagnés en baisse (jours)", st.recordDrops, 0, 0)
		add("Bornes", "Confettis négatifs ou au-dessus du total (jours)", st.confettiNegative, 0, 0)
		-- rapporté
		add(
			"Rapporté",
			"Record R jour 84 (médiane)",
			if opts.days >= 84 then st.daily(84, "best") else 0 / 0,
			nil,
			nil,
			true
		)
		add(
			"Rapporté",
			"A jour 84 (médiane)",
			if opts.days >= 84 then st.daily(84, "A") else 0 / 0,
			nil,
			nil,
			true
		)
		add(
			"Rapporté",
			"Confettis gagnés jour 28 (médiane)",
			if opts.days >= 28 then st.daily(28, "confTotal") else 0 / 0,
			nil,
			nil,
			true
		)
		add("Rapporté", "temps en ×2 (%)", st.metric("boostShare"), nil, nil, true)
		return keys, st
	end

	-- Une configuration v2.0 : simulation avec les interrupteurs ouverts
	local function runV2(model, size, players, days, v2opts, spender)
		return withFlags(true, function()
			return Sim.run({
				players = players,
				days = days,
				seed = SEED,
				simulate = model.simulateFor({ players = size, v2 = v2opts, spender = spender }),
				gates = {},
				reported = {},
			})
		end)
	end

	-- tests d'une configuration : un par groupe de clés
	local GROUPS = { "Jalons v1.3", "Sans but", "Boucles", "Jelly Ascend", "Atelier", "Familles", "Bornes" }
	local function itKeys(title, keys)
		printKeys(title, keys)
		for _, group in GROUPS do
			local any = false
			for _, k in keys do
				if k.group == group and not k.reported then
					any = true
				end
			end
			if any then
				it(`{title} : {group}`, function()
					expect(table.concat(failuresOf(keys, group), " ; ")).toBe("")
				end)
			end
		end
	end

	local function v2Gate()
		describe(
			"EconomyPacing v2.0 (interrupteurs de l'économie ouverts dans le modèle, docs/04 §27.9)",
			function()
				local model = EconomyModel.new(L)
				local t0 = os.clock()
				local noAscend = v2Stats(runV2(model, 16, V2_PLAYERS, 28, { ascend = false }))
				for _, size in EconomyModel.SIZES do
					local ref = runV2(model, size, V2_PLAYERS, 84, {})
					local keys = v2Keys(ref, "ref", {
						v13 = true,
						ascend = true,
						atelier = true,
						loopGap = true,
						days = 84,
						noAscend = if size == 16 then noAscend else nil,
					})
					itKeys(`référence, serveur de {size} ({V2_PLAYERS} joueurs, 84 jours)`, keys)
				end
				for _, size in EconomyModel.SIZES do
					local assidu = runV2(model, size, V2_PLAYERS, 28, { assidu = true })
					local keys = v2Keys(assidu, "assidu", { ascend = true, atelier = true, days = 28 })
					itKeys(`assidu 2 h par jour, serveur de {size} ({V2_PLAYERS} joueurs, 28 jours)`, keys)
				end
				print(string.format("\n  Porte v2.0 : %.0f s de calcul", os.clock() - t0))

				it(
					"invariant de stabilité : Prestige.validateConfig(Balance) (GDD §4.27, critique M13)",
					function()
						local ok, why = Prestige.validateConfig(Balance)
						expect(why).toBe(nil)
						expect(ok).toBe(true)
					end
				)

				it(
					"v2.0 déterministe : même graine, même joueur, mêmes jalons et mêmes boucles",
					function()
						local a, b = withFlags(true, function()
							local simulate = model.simulateFor({ players = 8, v2 = { assidu = true } })
							return simulate(Sim.newRng(SEED * 1000003 + 2), 2, 8),
								simulate(Sim.newRng(SEED * 1000003 + 2), 2, 8)
						end)
						expect(#a.v2.loops > 0).toBe(true)
						expect(#a.v2.loops).toBe(#b.v2.loops)
						expect(a.v2.ascendDays[1]).toBe(b.v2.ascendDays[1])
						expect(a.recordDay7).toBe(b.recordDay7)
						expect(a.v2.daily[8].confTotal).toBe(b.v2.daily[8].confTotal)
						expect(a.v2.bands[2].over).toBe(b.v2.bands[2].over)
					end
				)

				it(
					"le modèle refuse des interrupteurs v2.0 mélangés (aucun état hybride simulé)",
					function()
						Features.reset()
						Features.set("RecordR", true)
						local ok, err = pcall(function()
							model.simulateFor({ players = 16 })(Sim.newRng(1), 1, 1)
						end)
						Features.reset()
						expect(ok).toBe(false)
						expect(string.find(tostring(err), "mélangés", 1, true) ~= nil).toBe(true)
					end
				)
			end
		)
	end

	-- =============================================================================================
	-- Partie 3 : la nuit (scripts/economy-nightly.sh), un cas par processus
	-- =============================================================================================
	local NIGHT_PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_NIGHT_PLAYERS) or 50))
	local function weekend(d)
		return ((d - 1) % 7) < 2
	end
	local NIGHT_CASES = {}
	NIGHT_CASES.ref140 = function(model)
		local noAscend = v2Stats(runV2(model, 16, NIGHT_PLAYERS, 28, { ascend = false }))
		local res = runV2(model, 16, NIGHT_PLAYERS, 140, {})
		local keys = v2Keys(res, "ref", {
			v13 = true,
			ascend = true,
			atelier = true,
			loopGap = true,
			days = 140,
			noAscend = noAscend,
		})
		itKeys(`nuit : référence, {NIGHT_PLAYERS} joueurs, 140 jours`, keys)
	end
	NIGHT_CASES.assidu140 = function(model)
		local noAscend = v2Stats(runV2(model, 16, NIGHT_PLAYERS, 28, { assidu = true, ascend = false }))
		local res = runV2(model, 16, NIGHT_PLAYERS, 140, { assidu = true })
		local keys = v2Keys(res, "assidu", { ascend = true, atelier = true, days = 140, noAscend = noAscend })
		itKeys(`nuit : assidu 2 h par jour, {NIGHT_PLAYERS} joueurs, 140 jours`, keys)
	end
	-- lancement manuel : ECON_NIGHT=custom ECON_PROFILE=ref|assidu ECON_SIZE=4|8|16 ECON_DAYS=84
	-- ECON_NIGHT_PLAYERS=200 (mêmes clés que check.sh pour ce profil)
	NIGHT_CASES.custom = function(model)
		local profile = if process.env.ECON_PROFILE == "assidu" then "assidu" else "ref"
		local size = math.floor(tonumber(process.env.ECON_SIZE) or 16)
		local days = math.floor(tonumber(process.env.ECON_DAYS) or (if profile == "assidu" then 28 else 84))
		local res = runV2(model, size, NIGHT_PLAYERS, days, { assidu = profile == "assidu" })
		local keys = v2Keys(res, profile, {
			v13 = profile == "ref",
			ascend = true,
			atelier = true,
			loopGap = profile == "ref",
			days = days,
		})
		itKeys(`manuel : {profile}, serveur de {size}, {NIGHT_PLAYERS} joueurs, {days} jours`, keys)
	end
	NIGHT_CASES.min10 = function(model)
		local res = runV2(model, 16, NIGHT_PLAYERS, 84, { firstMin = 15, dailyMin = 10 })
		itKeys(
			`nuit : 10 min par jour, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(res, "other", { days = 84 })
		)
	end
	NIGHT_CASES.min20 = function(model)
		local res = runV2(model, 16, NIGHT_PLAYERS, 84, { firstMin = 20, dailyMin = 20 })
		itKeys(
			`nuit : 20 min par jour, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(res, "other", { days = 84 })
		)
	end
	NIGHT_CASES.weekend = function(model)
		local res = runV2(model, 16, NIGHT_PLAYERS, 140, { firstMin = 90, dailyMin = 90, playDay = weekend })
		itKeys(
			`nuit : week-end (90 min samedi et dimanche), {NIGHT_PLAYERS} joueurs, 140 jours`,
			v2Keys(res, "other", { days = 140 })
		)
	end
	NIGHT_CASES.allday = function(model)
		local res = runV2(model, 4, NIGHT_PLAYERS, 28, { firstMin = 360, dailyMin = 360 })
		itKeys(
			`nuit : 6 h par jour, serveur de 4, {NIGHT_PLAYERS} joueurs, 28 jours`,
			v2Keys(res, "allday", { days = 28 })
		)
	end
	-- jamais l'Atelier (et atelierEffect : écart avec le même profil qui l'ouvre)
	local function atelierEffect(title, profile, v2opts, players, days)
		return function(model)
			local without = runV2(model, 16, players, days, table.freeze(table.clone(v2opts)))
			local withOpts = table.clone(v2opts)
			withOpts.atelier = nil
			local with = runV2(model, 16, players, days, withOpts)
			local keys, st = v2Keys(without, profile, { ascend = true, days = days })
			local _, stWith = v2Keys(with, profile, { ascend = true, days = days })
			local function report(group, label, value)
				table.insert(
					keys,
					{ group = group, label = label, value = value, ok = true, reported = true }
				)
			end
			for bi, b in EconomyModel.BANDS do
				if st.bands[bi].starved and stWith.bands[bi].starved then
					report(
						"Rapporté",
						"atelierEffect starved" .. b.key .. " (points)",
						100 * (st.bands[bi].starved - stWith.bands[bi].starved)
					)
				end
			end
			report(
				"Rapporté",
				"atelierEffect Record R jour " .. days,
				stWith.daily(days, "best") - st.daily(days, "best")
			)
			itKeys(title, keys)
		end
	end
	NIGHT_CASES.noatelier = function(model)
		atelierEffect(
			`nuit : référence sans Atelier, {NIGHT_PLAYERS} joueurs, 84 jours`,
			"ref",
			{ atelier = false },
			NIGHT_PLAYERS,
			84
		)(model)
		atelierEffect(
			"nuit : assidu sans Atelier, 20 joueurs, 84 jours",
			"assidu",
			{ assidu = true, atelier = false },
			math.min(NIGHT_PLAYERS, 20),
			84
		)(model)
	end
	NIGHT_CASES.refuse3 = function(model)
		local ref = runV2(model, 16, NIGHT_PLAYERS, 84, { ascendDelayDays = 3 })
		itKeys(
			`nuit : référence qui refuse 3 jours, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(ref, "ref", { days = 84 })
		)
		local assidu =
			runV2(model, 16, math.min(NIGHT_PLAYERS, 20), 84, { assidu = true, ascendDelayDays = 3 })
		itKeys(
			"nuit : assidu qui refuse 3 jours, 20 joueurs, 84 jours",
			v2Keys(assidu, "assidu", { days = 84 })
		)
	end
	NIGHT_CASES.advisor = function(model)
		local ref = runV2(model, 16, NIGHT_PLAYERS, 84, { policy = "advisor" })
		itKeys(
			`nuit : politique « Conseillé », référence, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(ref, "ref", { ascend = true, atelier = true, days = 84 })
		)
		local assidu =
			runV2(model, 16, math.min(NIGHT_PLAYERS, 20), 84, { assidu = true, policy = "advisor" })
		itKeys(
			"nuit : politique « Conseillé », assidu, 20 joueurs, 84 jours",
			v2Keys(assidu, "assidu", { ascend = true, atelier = true, days = 84 })
		)
	end
	NIGHT_CASES.spender = function(model)
		local spenders = math.max(NIGHT_PLAYERS, math.floor(tonumber(process.env.ECON_SPENDERS) or 200))
		local ref = v2Stats(runV2(model, 16, NIGHT_PLAYERS, 84, {}))
		local sp = v2Stats(runV2(model, 16, spenders, 84, {}, true))
		local keys, add = newKeys()
		for k = 1, 7 do
			local refDay, spDay = ref.ascendDay[k] or math.huge, sp.ascendDay[k] or math.huge
			local lead = if refDay < math.huge and refDay > 0 then (refDay - spDay) / refDay else 0 / 0
			add(
				"Bornes",
				`spenderLeadTimeShare A{k} (jour {fmt(spDay)} contre {fmt(refDay)})`,
				lead,
				nil,
				0.25
			)
		end
		add("Bornes", "nonFinite (gros acheteur)", sp.nonFinite, 0, 0)
		add("Bornes", "MaxA jamais dépassé (gros acheteur)", sp.maxA, 0, Balance.Prestige.MaxA)
		itKeys(`nuit : gros acheteur, {spenders} joueurs, 84 jours`, keys)
	end
	-- profils de départ forcés à A Ascensions (Prestige.apply répété), joueur de 2 h par jour
	for _, A in { 10, 20, 30, 60 } do
		NIGHT_CASES["forcedA" .. A] = function(model)
			local players = math.min(NIGHT_PLAYERS, 20)
			local res = runV2(model, 16, players, 14, { assidu = true, forcedA = A })
			local keys = v2Keys(res, "assidu", { days = 14 })
			-- un profil forcé n'a ni collection ni historique : seules les bornes et la santé des
			-- renaissances bloquent (nombres finis, MaxR, MaxA, Record R, Confettis, aucune boucle vide)
			for _, k in keys do
				local robust = k.group == "Bornes"
					or string.find(k.label, "zeroGap", 1, true) ~= nil
					or string.find(k.label, "shortestLoopSec", 1, true) ~= nil
				if not robust then
					k.reported, k.ok = true, true
				end
			end
			local startA = math.huge
			for _, m in res.players do
				startA = math.min(startA, m.startA or 0)
			end
			local wanted = math.min(A, Balance.Prestige.MaxA)
			table.insert(keys, {
				group = "Bornes",
				label = "A de départ construit par Prestige.apply",
				value = startA,
				lo = wanted,
				hi = wanted,
				ok = startA == wanted,
			})
			itKeys(`nuit : profil forcé A = {A}, assidu, {players} joueurs, 14 jours`, keys)
		end
	end
	NIGHT_CASES.fullAtelier = function(model)
		local ref = runV2(model, 16, NIGHT_PLAYERS, 84, { fullAtelier = true })
		itKeys(
			`nuit : Atelier complet dès le début, référence, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(ref, "ref", { days = 84 })
		)
		local assidu =
			runV2(model, 16, math.min(NIGHT_PLAYERS, 20), 28, { assidu = true, fullAtelier = true })
		itKeys(
			"nuit : Atelier complet dès le début, assidu, 20 joueurs, 28 jours",
			v2Keys(assidu, "assidu", { days = 28 })
		)
	end

	-- =============================================================================================
	if NIGHT then
		describe(`EconomyPacing, jeu de nuit : {NIGHT}`, function()
			local case = NIGHT_CASES[NIGHT]
			if case == nil then
				local names = {}
				for name in NIGHT_CASES do
					table.insert(names, name)
				end
				table.sort(names)
				it("cas de nuit connu", function()
					error(`cas inconnu « {NIGHT} » ; cas : {table.concat(names, ", ")}`)
				end)
				return
			end
			local t0 = os.clock()
			case(EconomyModel.new(L))
			print(string.format("\n  Cas %s : %.0f s de calcul", NIGHT, os.clock() - t0))
		end)
	else
		baseGate()
		v2Gate()
	end

	describe("EconomyPacing : zéro trace", function()
		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
