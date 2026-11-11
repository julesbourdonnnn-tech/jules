--!nocheck
-- EconomyPacing (paquet A1, docs/04 §27.9 ; GDD §4.24, §4.24.1) : PORTE BLOQUANTE du rythme de
-- l'économie, jouée par tests/sim/EconomyModel (vraies formules, vraies tables, vrais modules de la
-- progression), graine fixe, aux 3 tailles de serveur.
--  1. Jeu de base (interrupteurs v2.0 COUPÉS, comme la version de test) : la porte v1.3 telle quelle
--     (docs/04 §16 v1.2) : 50 joueurs de référence × 28 jours × 4, 8 et 16 joueurs, gros acheteur.
--  2. Jeu complet v2.0 (interrupteurs de l'économie OUVERTS dans le modèle seulement ; le jeu les
--     garde coupés) : chaque clé du §27.9 pour check.sh — 20 joueurs par taille de serveur, joueur de
--     référence 84 jours, joueur assidu (2 h par jour) 28 jours, et la référence sans Ascension
--     (28 jours, serveur de 16) pour recordRDay28. Toutes les clés de la v1.3 sont gardées. Les 11
--     clés de QUEUE (bruit à 20 joueurs plus large que leur marge, table TAIL) n'y sont qu'en alarme
--     rapide (limite élargie de 2 écarts types mesurés) : leur vraie limite est affirmée la nuit.
--     Les 11 configurations des parties 1 et 2 sont jouées par ECON_WORKERS (4) processus fils à la
--     fois (tests/sim/economy-worker.luau ; mêmes graines, mêmes joueurs au bit près).
--  3. La nuit (scripts/economy-nightly.sh) : ECON_NIGHT=<cas> joue un cas du jeu de nuit (80 joueurs
--     au moins, ECON_NIGHT_PLAYERS ; 400 pour les configurations de check.sh, cas tails*, et les 140
--     jours, ECON_TAIL_PLAYERS ; profils de la critique, gros acheteur, profils forcés) au lieu des
--     parties 1 et 2. ECON_NIGHT=custom ECON_PROFILE=ref|assidu ECON_SIZE=16 ECON_DAYS=84
--     ECON_NIGHT_PLAYERS=200 : lancement manuel d'une configuration (mêmes clés que check.sh) ;
--     ECON_NIGHT=spread (mêmes variables, ECON_BLOCK=20) : mesure du bruit de chaque clé.
-- ECON_PLAYERS : joueurs de la porte v1.3 (50) ; ECON_V2_PLAYERS : joueurs de la porte v2.0 (20).
-- Chaque clé est imprimée (valeur, limites, OK/HORS) ; un test par groupe du §27.9 et par
-- configuration échoue dès qu'une clé du groupe sort de ses limites, et les nomme toutes.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local process = require("@lune/process")
	local task = require("@lune/task")
	local Sim = require("../sim/Sim")
	local EconomyModel = require("../sim/EconomyModel")
	local EconomyIO = require("../sim/EconomyIO")

	local h = Harness.new()
	local L = EconomyIO.load(h)
	local Features, Balance, Prestige = L.Features, L.Balance, L.Prestige

	local PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_PLAYERS) or 50))
	local V2_PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_V2_PLAYERS) or 20))
	local NIGHT = process.env.ECON_NIGHT
	local SPENDERS = math.min(PLAYERS, 20)
	local DAYS, SEED = 28, 20261212
	-- check.sh : configurations jouées dans ECON_WORKERS processus fils à la fois (tests/sim/
	-- economy-worker, un par cœur) ; ECON_WORKERS=1 : toutes dans ce processus (mêmes joueurs)
	local WORKERS = math.max(1, math.floor(tonumber(process.env.ECON_WORKERS) or 4))

	-- Joue des configurations { { name, job } } (job : EconomyIO.run) ; rend { [name] = joueurs } et la
	-- liste des fils en échec (raison et fin de leur sortie d'erreur)
	local function runJobs(jobs)
		local out, failed = {}, {}
		if WORKERS <= 1 then
			for _, j in jobs do
				out[j.name] = EconomyIO.run(L, j.job)
			end
			return out, failed
		end
		local lune = process.env.ECON_LUNE or "lune"
		local nextJob, running = 1, 0
		local function launch(j)
			running += 1
			task.spawn(function()
				local ok, r =
					pcall(process.exec, lune, { "run", "tests/sim/economy-worker", EconomyIO.encode(j.job) })
				local at = if ok and r.ok then string.find(r.stdout, EconomyIO.MARK, 1, true) else nil
				if at then
					out[j.name] = EconomyIO.decode(string.sub(r.stdout, at + #EconomyIO.MARK))
				else
					local why = if ok then string.sub(r.stderr or "", -2000) else tostring(r)
					table.insert(failed, `{j.name} : {why}`)
				end
				running -= 1
			end)
		end
		while nextJob <= #jobs or running > 0 do
			while running < WORKERS and nextJob <= #jobs do
				launch(jobs[nextJob])
				nextJob += 1
			end
			task.wait(0.05)
		end
		return out, failed
	end

	-- =============================================================================================
	-- Interrupteurs : coupés (jeu de base) ou tous ceux de l'économie ouverts (v2.0, dans le modèle)
	-- =============================================================================================
	local function withFlags(on, fn)
		Features.reset()
		-- chaque interrupteur de l'économie posé explicitement (lot I, étape 2, journal I-19 : la
		-- configuration livrée en ouvre une partie)
		for _, key in EconomyModel.ECON_FLAGS do
			assert(Features.set(key, on == true), "interrupteur refusé : " .. key)
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
	local function baseGate(runs)
		describe("EconomyPacing v1.3 (jeu de base, interrupteurs v2.0 coupés, GDD §4.24)", function()
			local model = EconomyModel.new(L)
			local results = {}
			do
				for _, size in EconomyModel.SIZES do
					local result =
						Sim.aggregate(runs["v13." .. size], EconomyModel.GATES, EconomyModel.REPORTED)
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
			end

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
					local spender = Sim.aggregate(runs["v13.spender"], {}, {
						{ key = "rDay28", label = "R en fin de jour 28" },
						{ key = "firstSplorch", label = "x" },
					})
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

			-- témoin : valeurs rendues par le modèle v1.3 d'avant l'extension v2.0 (commit 533e02e) pour ce
			-- joueur ; le modèle étendu, interrupteurs coupés, doit les rendre au bit près (une dérive du
			-- jeu de base dans le modèle fait échouer ce cas avant de déplacer une médiane). Le joueur 1 du
			-- serveur de 8 de la porte ci-dessus (graine SEED × 1000003 + 1, 28 jours) : pris dans ses
			-- résultats, jamais rejoué
			it(
				"interrupteurs coupés : un joueur témoin rend exactement les jalons du modèle v1.3",
				function()
					local m = results[8].players[1]
					expect(DAYS).toBe(28)
					expect(m.v2).toBeNil()
					expect({
						firstSplorch = m.firstSplorch,
						r30 = m.r30,
						stamps30 = m.stamps30,
						rDay1 = m.rDay1,
						rDay7 = m.rDay7,
						rDay14 = m.rDay14,
						rDay28 = m.rDay28,
						stampsDay7 = m.stampsDay7,
						stampsDay28 = m.stampsDay28,
						biggestDay7 = m.biggestDay7,
						boostShare = m.boostShare,
						snack12Share = m.snack12Share,
						coinsLostRatio = m.coinsLostRatio,
						pressShareDay7 = m.pressShareDay7,
						first1e12Day = m.first1e12Day,
					}).toEqual({
						firstSplorch = 11.283333333333333,
						r30 = 2,
						stamps30 = 20,
						rDay1 = 2,
						rDay7 = 10,
						rDay14 = 15,
						rDay28 = 20,
						stampsDay7 = 103,
						stampsDay28 = 138,
						biggestDay7 = 112475034.21464916,
						boostShare = 35.967672619829045,
						snack12Share = 0.66967680608365021,
						coinsLostRatio = 4.0199619294054294,
						pressShareDay7 = 0.6048687476233966,
						first1e12Day = 26,
					})
				end
			)
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
	-- « refuse la 1re Ascension pendant 3 jours » : limites du tableau des profils du GDD §4.24.1
	-- (référence ≤ 20 %, assidu ≤ 30 % dans chaque bande ; le GDD est la source du design, journal
	-- A1-30) ; le trou p90 de l'assidu, dont le GDD ne dit rien pour ce profil, garde la limite du §27.9
	STARVED.refuse3 = {
		ref = { 0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.20 },
		assidu = { 0.30, 0.30, 0.30, 0.30, 0.30, 0.30, 0.30 },
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
						-- fusion → cible atteinte (décision du chef, A2-7 : ni le geste du Petit
						-- Splorch, ni la file, ni l'attente de la pression qui la voit)
						if l.reachSinceFuse > 10 then
							after.unfused += 1
						end
					end
				end
				-- familles ouvertes dans la boucle (r de la boucle ; Tapis Étoilé : Tapis 12 atteint avant la fin)
				-- Gants et École s'ouvrent au RECORD R 1 et 2 (Config/Upgrades) : avant toute Ascension
				-- le Record R vaut r au début de la boucle ; après une Ascension il vaut 15 au moins
				-- (relecture A1, A1-40 : les boucles r = 0 et 1 d'après une Ascension étaient oubliées)
				local open = {
					snack = true,
					star = l.r >= 6 and l.share12 < 0.999,
					decor = true,
					gloves = l.r >= 1 or l.afterAscend,
					school = l.r >= 2 or l.afterAscend,
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

	-- Clés de QUEUE (docs/04 §27.9, journal A1-28) : à 20 joueurs, leur bruit d'échantillon est plus
	-- large que leur marge (marge < 2 écarts types). sigma = écart type à 20 joueurs MESURÉ
	-- (ECON_NIGHT=spread, 20 blocs disjoints de 20 joueurs sur 400, le pire des 3 tailles de serveur).
	-- Leur vraie limite est affirmée la nuit sur TAIL_PLAYERS joueurs (cas tails4, tails8, tails16) ;
	-- check.sh les garde en « alarme rapide » : même clé, limite élargie de 2 sigma (un tirage de 20
	-- joueurs n'en sort pas par le bruit seul quand la vraie valeur tient). Toute autre clé bloque
	-- check.sh à sa vraie limite.
	-- (mesure du 5 novembre 2026, Balance du lot A1 3/4 ; σ = le pire des serveurs de 4, 8 et 16, arrondi
	-- vers le haut ; marge / σ entre parenthèses, au pire serveur, valeur sur 400 joueurs)
	-- side : le côté de queue (« lo » : limite basse, « hi » : limite haute), le SEUL élargi ; l'autre
	-- limite d'une clé à deux bornes garde sa vraie valeur dans check.sh (marge ≥ 5 σ mesurée ; relecture
	-- A1, A1-39 : les deux côtés étaient élargis, la borne basse des pertes de l'assidu valait −0,56)
	local TAIL = {
		ref = {
			{ label = "Premier Grand Splorch (min)", sigma = 0.69, side = "lo" }, -- 12,16 min (1,69 σ)
			{ label = "Plus gros, fin du jour 7", sigma = 1.2e7, side = "lo" }, -- bimodal : un bloc à 3,97e7 < 4e7
			{ label = "loopMaxGap r12 médiane", sigma = 0.28, side = "hi" }, -- 2,53 min (1,68 σ)
			{ label = "loopMaxGap r13 médiane", sigma = 0.47, side = "hi" }, -- 2,80 min (0,43 σ)
			{ label = "loopMaxGap r13 p90", sigma = 0.41, side = "hi" }, -- 4,93 min (0,17 σ)
			{ label = "ascendGapDays A6→A7", sigma = 0.5, side = "lo" }, -- 10 jours, à la limite (blocs : 10 à 11)
			{ label = "tapis12RecordLoopByA A7", sigma = 0.075, side = "hi" }, -- 0,83 (1,97 σ)
			{ label = "purchasesPerRecordLoopByA A7", sigma = 0.77, side = "lo" }, -- 11,5 (1,98 σ)
		},
		assidu = {
			{ label = "longestGapAssiduP90 Day8to14", sigma = 1.35, side = "hi" }, -- 14,07 min (0,71 σ)
			{ label = "longestGapAssiduP90 Day15to28", sigma = 1.13, side = "hi" }, -- 13,90 min (0,97 σ)
			{ label = "coinsLostRatioGrand Day8to14", sigma = 0.38, side = "hi" }, -- 2,66 T12 (0,92 σ)
		},
	}
	local function tailOf(profile, label)
		for _, t in TAIL[profile] or {} do
			if string.sub(label, 1, #t.label) == t.label then
				return t
			end
		end
		return nil
	end
	local function within(k)
		return type(k.value) == "number"
			and k.value == k.value
			and (k.lo == nil or k.value >= k.lo)
			and (k.hi == nil or k.value <= k.hi)
	end
	-- check.sh : clés de queue en alarme rapide (limite du côté de queue élargie de 2 sigma, libellé
	-- marqué) ; l'autre limite reste la vraie
	local function applyAlarm(keys, profile)
		for _, k in keys do
			local t = if k.reported then nil else tailOf(profile, k.label)
			if t then
				if t.side == "lo" and k.lo ~= nil then
					k.lo -= 2 * t.sigma
				elseif t.side == "hi" and k.hi ~= nil then
					k.hi += 2 * t.sigma
				end
				k.label ..= string.format(
					" [alarme rapide %s2σ, σ = %s ; vraie limite : nuit]",
					if t.side == "lo" then "−" else "+",
					tostring(t.sigma)
				)
				k.ok = within(k)
			end
		end
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
		local starvedLimits = opts.starved or STARVED[profile] or STARVED.ref
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
			add("Boucles", "shortestLoopSec : sous 45 s, cible > 10 s après une fusion", after.unfused, 0, 0)
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
		if opts.alarm then
			applyAlarm(keys, profile)
		end
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

	local function v2Gate(runs)
		describe(
			"EconomyPacing v2.0 (interrupteurs de l'économie ouverts dans le modèle, docs/04 §27.9)",
			function()
				local model = EconomyModel.new(L)
				local noAscend = v2Stats({ players = runs["v2.noAscend"] })
				for _, size in EconomyModel.SIZES do
					local ref = { players = runs["v2.ref." .. size] }
					local keys = v2Keys(ref, "ref", {
						v13 = true,
						ascend = true,
						atelier = true,
						loopGap = true,
						days = 84,
						noAscend = if size == 16 then noAscend else nil,
						alarm = true,
					})
					itKeys(`référence, serveur de {size} ({V2_PLAYERS} joueurs, 84 jours)`, keys)
				end
				for _, size in EconomyModel.SIZES do
					local assidu = { players = runs["v2.assidu." .. size] }
					local keys =
						v2Keys(assidu, "assidu", { ascend = true, atelier = true, days = 28, alarm = true })
					itKeys(`assidu 2 h par jour, serveur de {size} ({V2_PLAYERS} joueurs, 28 jours)`, keys)
				end

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
					"v2.0 câblé au vrai code : chaque Jelly Ascend part de reqR(A) et repart à startR(A, Tremplin)",
					function()
						local m = withFlags(true, function()
							return model.simulateFor({ players = 16, v2 = { assidu = true } })(
								Sim.newRng(SEED * 1000003 + 3),
								3,
								12
							)
						end)
						local ascends = m.v2.ascends
						expect(#ascends >= 1).toBe(true)
						for k, e in ascends do
							expect({ k = k, A = e.A }).toEqual({ k = k, A = k })
							expect({ k = k, ready = e.fromR >= Prestige.reqR(k) }).toEqual({
								k = k,
								ready = true,
							})
							local lo, hi = Prestige.startR(k, 0), Prestige.startR(k, 3)
							expect({ k = k, start = e.R >= lo and e.R <= hi }).toEqual({ k = k, start = true })
							expect({ k = k, record = e.best >= e.fromR }).toEqual({ k = k, record = true })
						end
						-- après la 1re Ascension : des Petits Splorch (remontée), puis des Grands Splorch
						local petit, grandAfter = 0, 0
						for _, l in m.v2.loops do
							if l.afterAscend then
								if l.petit then
									petit += 1
								else
									grandAfter += 1
								end
							end
						end
						expect(petit > 0).toBe(true)
						expect(grandAfter > 0).toBe(true)
						expect(m.applyRefused).toBe(0)
						expect(m.maxA).toBe(#ascends)
					end
				)

				it(
					"le modèle refuse des interrupteurs v2.0 mélangés (aucun état hybride simulé)",
					function()
						-- mélange explicite (lot I, I-24 : au lancement tous les interrupteurs de l'économie sont
						-- ouverts, la remise à zéro seule ne fait plus de mélange) : tout coupé sauf RecordR
						Features.reset()
						for _, key in EconomyModel.ECON_FLAGS do
							Features.set(key, false)
						end
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
	-- joueurs par configuration de la nuit (80 au moins : docs/04 §27.9) ; TAIL_PLAYERS : configurations
	-- de check.sh rejouées pour leurs clés de queue (cas tailsRef* et tailsAssidu*)
	local NIGHT_PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_NIGHT_PLAYERS) or 80))
	local TAIL_PLAYERS = math.max(1, math.floor(tonumber(process.env.ECON_TAIL_PLAYERS) or 400))
	local function weekend(d)
		return ((d - 1) % 7) < 2
	end
	local NIGHT_CASES = {}
	-- Bruit d'échantillon d'une configuration (docs/04 §27.9) : les mêmes clés que check.sh sur tous les
	-- joueurs, puis sur chaque bloc disjoint de `block` joueurs (le 1er bloc = les graines de check.sh) ;
	-- imprime pour chaque clé la valeur sur tous, la moyenne, l'écart type et l'étendue des blocs, la
	-- marge à la limite en écarts types, et les valeurs des 20 et des 80 premiers joueurs. Rend le
	-- nombre de blocs. Lancement manuel : ECON_NIGHT=spread ECON_PROFILE=ref|assidu ECON_SIZE=16
	-- ECON_DAYS=84 ECON_NIGHT_PLAYERS=400 ECON_BLOCK=20 ; les cas tails* l'impriment aussi (rapporté)
	local function spreadReport(res, noAscendRes, profile, size, days, block)
		local total = #res.players
		local function keysOf(from, to)
			local sub = { players = table.move(res.players, from, to, 1, {}) }
			local noAscend = if noAscendRes
				then v2Stats({ players = table.move(noAscendRes.players, from, to, 1, {}) })
				else nil
			return v2Keys(sub, profile, {
				v13 = profile == "ref",
				ascend = true,
				atelier = true,
				loopGap = profile == "ref",
				days = days,
				noAscend = noAscend,
			})
		end
		local function name(k)
			return (string.gsub(k.label, " %(sans Ascension : [^)]*%)", ""))
		end
		local all = keysOf(1, total)
		-- valeurs sur les 20 premiers joueurs (check.sh) et les 80 premiers (taille de la nuit)
		local firstOf = {}
		for _, n in { 20, 80 } do
			firstOf[n] = {}
			if total >= n then
				for _, k in keysOf(1, n) do
					firstOf[n][name(k)] = k.value
				end
			end
		end
		local values = {}
		local blocks = math.floor(total / block)
		for b = 1, blocks do
			for _, k in keysOf((b - 1) * block + 1, b * block) do
				local key = name(k)
				values[key] = values[key] or {}
				if type(k.value) == "number" and k.value == k.value and math.abs(k.value) < math.huge then
					table.insert(values[key], k.value)
				end
			end
		end
		print(
			string.format(
				"\n  — bruit : %s, serveur de %d, %d jours, %d joueurs, %d blocs de %d —",
				profile,
				size,
				days,
				total,
				blocks,
				block
			)
		)
		for _, k in all do
			local list = values[name(k)] or {}
			local n, sum, sq, lo, hi = #list, 0, 0, math.huge, -math.huge
			for _, v in list do
				sum += v
				lo, hi = math.min(lo, v), math.max(hi, v)
			end
			local mean = if n > 0 then sum / n else 0 / 0
			for _, v in list do
				sq += (v - mean) * (v - mean)
			end
			local sd = if n > 1 then math.sqrt(sq / (n - 1)) else 0 / 0
			local margin = math.huge
			if type(k.value) == "number" then
				if k.hi ~= nil then
					margin = math.min(margin, k.hi - k.value)
				end
				if k.lo ~= nil then
					margin = math.min(margin, k.value - k.lo)
				end
			end
			-- ligne lisible par un script :
			-- SPREAD|groupe|clé|tous|moyenne|écart type|min|max|lo|hi|blocs|marge/σ|20 premiers|80 premiers
			print(
				string.format(
					"SPREAD|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s",
					k.group,
					name(k),
					fmt(k.value),
					fmt(mean),
					fmt(sd),
					fmt(lo),
					fmt(hi),
					if k.lo == nil then "—" else fmt(k.lo),
					if k.hi == nil then "—" else fmt(k.hi),
					n,
					if k.reported
							or margin == math.huge
							or sd ~= sd
							or sd == 0
						then "—"
						else fmt(margin / sd),
					fmt(firstOf[20][name(k)]),
					fmt(firstOf[80][name(k)])
				)
			)
		end
		return blocks
	end
	-- les configurations de check.sh sur TAIL_PLAYERS joueurs (mêmes graines : les 20 premiers sont ceux
	-- de check.sh), chaque clé à sa VRAIE limite ; un processus par profil et par taille (le jeu de nuit
	-- en joue plusieurs à la fois). L'assidu du serveur de 16 est dans assidu140 (mêmes graines, mêmes
	-- 28 premiers jours : ses clés de queue sont des clés de bandes de jours, identiques) ; la référence
	-- du serveur de 16 garde son cas (les clés « A7 » de 84 jours ne comptent pas les mêmes boucles que
	-- celles de 140 jours)
	for _, size in EconomyModel.SIZES do
		NIGHT_CASES["tailsRef" .. size] = function(model)
			local noAscendRes = if size == 16
				then runV2(model, 16, TAIL_PLAYERS, 28, { ascend = false })
				else nil
			local ref = runV2(model, size, TAIL_PLAYERS, 84, {})
			spreadReport(ref, noAscendRes, "ref", size, 84, 20)
			local keys = v2Keys(ref, "ref", {
				v13 = true,
				ascend = true,
				atelier = true,
				loopGap = true,
				days = 84,
				noAscend = if noAscendRes then v2Stats(noAscendRes) else nil,
			})
			itKeys(`nuit : référence, serveur de {size}, {TAIL_PLAYERS} joueurs, 84 jours`, keys)
		end
		if size ~= 16 then
			NIGHT_CASES["tailsAssidu" .. size] = function(model)
				local assidu = runV2(model, size, TAIL_PLAYERS, 28, { assidu = true })
				spreadReport(assidu, nil, "assidu", size, 28, 20)
				local keys = v2Keys(assidu, "assidu", { ascend = true, atelier = true, days = 28 })
				itKeys(
					`nuit : assidu 2 h par jour, serveur de {size}, {TAIL_PLAYERS} joueurs, 28 jours`,
					keys
				)
			end
		end
	end
	-- 140 jours au serveur de 16 sur TAIL_PLAYERS joueurs : les clés tardives (trou p90 des jours 85-140,
	-- écarts des Ascensions en jours entiers, boucles record par A) sont des clés de queue elles aussi
	-- (journal A1-33) ; la référence sans Ascension (recordRDay28, marge de plusieurs R) sur NIGHT_PLAYERS
	NIGHT_CASES.ref140 = function(model)
		local noAscend = v2Stats(runV2(model, 16, NIGHT_PLAYERS, 28, { ascend = false }))
		local res = runV2(model, 16, TAIL_PLAYERS, 140, {})
		spreadReport(res, nil, "ref", 16, 140, 20)
		local keys = v2Keys(res, "ref", {
			v13 = true,
			ascend = true,
			atelier = true,
			loopGap = true,
			days = 140,
			noAscend = noAscend,
		})
		itKeys(`nuit : référence, {TAIL_PLAYERS} joueurs, 140 jours`, keys)
	end
	NIGHT_CASES.assidu140 = function(model)
		local noAscend = v2Stats(runV2(model, 16, NIGHT_PLAYERS, 28, { assidu = true, ascend = false }))
		local res = runV2(model, 16, TAIL_PLAYERS, 140, { assidu = true })
		spreadReport(res, nil, "assidu", 16, 140, 20)
		local keys = v2Keys(res, "assidu", { ascend = true, atelier = true, days = 140, noAscend = noAscend })
		itKeys(`nuit : assidu 2 h par jour, {TAIL_PLAYERS} joueurs, 140 jours`, keys)
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
	NIGHT_CASES.spread = function(model)
		local profile = if process.env.ECON_PROFILE == "assidu" then "assidu" else "ref"
		local size = math.floor(tonumber(process.env.ECON_SIZE) or 16)
		local days = math.floor(tonumber(process.env.ECON_DAYS) or (if profile == "assidu" then 28 else 84))
		local block = math.max(2, math.floor(tonumber(process.env.ECON_BLOCK) or 20))
		local res = runV2(model, size, NIGHT_PLAYERS, days, { assidu = profile == "assidu" })
		local noAscendRes = if profile == "ref" and size == 16
			then runV2(model, 16, NIGHT_PLAYERS, 28, { ascend = false })
			else nil
		local blocks = spreadReport(res, noAscendRes, profile, size, days, block)
		it("mesure du bruit : au moins 2 blocs", function()
			expect(blocks >= 2).toBe(true)
		end)
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
			`nuit : assidu sans Atelier, {NIGHT_PLAYERS} joueurs, 84 jours`,
			"assidu",
			{ assidu = true, atelier = false },
			NIGHT_PLAYERS,
			84
		)(model)
	end
	NIGHT_CASES.refuse3 = function(model)
		local ref = runV2(model, 16, NIGHT_PLAYERS, 84, { ascendDelayDays = 3 })
		itKeys(
			`nuit : référence qui refuse 3 jours, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(ref, "ref", { days = 84, starved = STARVED.refuse3.ref })
		)
		local assidu = runV2(model, 16, NIGHT_PLAYERS, 84, { assidu = true, ascendDelayDays = 3 })
		itKeys(
			`nuit : assidu qui refuse 3 jours, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(assidu, "assidu", { days = 84, starved = STARVED.refuse3.assidu })
		)
	end
	NIGHT_CASES.advisor = function(model)
		local ref = runV2(model, 16, NIGHT_PLAYERS, 84, { policy = "advisor" })
		itKeys(
			`nuit : politique « Conseillé », référence, {NIGHT_PLAYERS} joueurs, 84 jours`,
			v2Keys(ref, "ref", { ascend = true, atelier = true, days = 84 })
		)
		local assidu = runV2(model, 16, NIGHT_PLAYERS, 84, { assidu = true, policy = "advisor" })
		itKeys(
			`nuit : politique « Conseillé », assidu, {NIGHT_PLAYERS} joueurs, 84 jours`,
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
		local assidu = runV2(model, 16, NIGHT_PLAYERS, 28, { assidu = true, fullAtelier = true })
		itKeys(
			`nuit : Atelier complet dès le début, assidu, {NIGHT_PLAYERS} joueurs, 28 jours`,
			v2Keys(assidu, "assidu", { days = 28 })
		)
	end

	-- =============================================================================================
	-- Règles de la porte elle-même (relecture A1, docs/04 §27.12 A1-39, A1-40) : jouées sans
	-- simulation, dans check.sh comme la nuit
	-- =============================================================================================
	describe("EconomyPacing : règles de la porte (relecture A1)", function()
		it(
			"alarme rapide : seul le côté de queue est élargi de 2σ ; l'autre limite reste la vraie (§27.9)",
			function()
				-- { profil, libellé, valeur, lo, hi, côté de queue attendu }
				local cases = {
					{ "ref", "Premier Grand Splorch (min)", 12, 11, 16, "lo" },
					{ "ref", "Plus gros, fin du jour 7", 8e7, 4e7, 4e8, "lo" },
					{ "ref", "loopMaxGap r12 médiane (min)", 2.5, nil, 3, "hi" },
					{ "ref", "loopMaxGap r13 médiane (min)", 2.5, nil, 3, "hi" },
					{ "ref", "loopMaxGap r13 p90 (min)", 4.5, nil, 5, "hi" },
					{ "ref", "ascendGapDays A6→A7", 11, 10, 16, "lo" },
					{ "ref", "tapis12RecordLoopByA A7 (médiane)", 0.8, 0.45, 0.95, "hi" },
					{ "ref", "purchasesPerRecordLoopByA A7", 11, 10, nil, "lo" },
					{ "assidu", "longestGapAssiduP90 Day8to14 (min)", 14, nil, 15, "hi" },
					{ "assidu", "longestGapAssiduP90 Day15to28 (min)", 14, nil, 15, "hi" },
					{ "assidu", "coinsLostRatioGrand Day8to14 (T12)", 2.5, 0.2, 3, "hi" },
				}
				for _, c in cases do
					local profile, label, value, lo, hi, side = table.unpack(c, 1, 6)
					local t = tailOf(profile, label)
					expect({ label = label, tail = t ~= nil }).toEqual({ label = label, tail = true })
					local keys, add = newKeys()
					add("g", label, value, lo, hi)
					applyAlarm(keys, profile)
					local k = keys[1]
					expect({
						label = label,
						lo = k.lo,
						hi = k.hi,
					}).toEqual({
						label = label,
						lo = if lo ~= nil and side == "lo" then lo - 2 * t.sigma else lo,
						hi = if hi ~= nil and side == "hi" then hi + 2 * t.sigma else hi,
					})
					-- une valeur hors de la vraie limite du côté qui n'est PAS de queue échoue dans check.sh
					if side == "hi" and lo ~= nil then
						local bad, addBad = newKeys()
						addBad("g", label, lo - 0.01, lo, hi)
						applyAlarm(bad, profile)
						expect({ label = label, ok = bad[1].ok }).toEqual({ label = label, ok = false })
					elseif side == "lo" and hi ~= nil then
						local bad, addBad = newKeys()
						addBad("g", label, hi + 0.01, lo, hi)
						applyAlarm(bad, profile)
						expect({ label = label, ok = bad[1].ok }).toEqual({ label = label, ok = false })
					end
				end
			end
		)

		it(
			"everyFamilyBought : Gants et École ouverts par le Record R (aussi aux boucles r = 0 et 1 d'après une Ascension)",
			function()
				local function player(loops)
					local bands = {}
					for bi in EconomyModel.BANDS do
						bands[bi] = { tot = 0, over = 0, maxGap = 0 }
					end
					return {
						v2 = {
							bands = bands,
							daily = {},
							zeroGap = 0,
							nonFinite = 0,
							regain = {},
							cliff = {},
							offPot = {},
							loops = loops,
							ascendDays = {},
						},
						nonFinite = 0,
						applyRefused = 0,
						maxR = 0,
						maxBestR = 0,
						maxA = 0,
					}
				end
				local function loop(r, afterAscend, gloves, school)
					return {
						d = 20,
						petit = afterAscend,
						A = if afterAscend then 1 else 0,
						r = r,
						lost = 1,
						share12 = 0.5,
						len = 300,
						sinceFuse = 300,
						reachSinceFuse = 300,
						maxBuyGap = 30,
						afterAscend = afterAscend,
						snack = 3,
						star = 0,
						decor = 2,
						gloves = gloves,
						school = school,
					}
				end
				local st = v2Stats({
					players = {
						player({
							loop(0, false, 0, 0), -- 1re boucle du jeu : Record R 0, ni Gants ni École
							loop(1, false, 1, 0), -- Record R 1 : Gants seulement
							loop(0, true, 0, 0), -- après la 1re Ascension (Record R 15) : tout est ouvert
							loop(1, true, 1, 1),
							loop(4, true, 1, 1),
						}),
					},
				})
				expect({ open = st.fam.gloves.open, bought = st.fam.gloves.bought }).toEqual({
					open = 4,
					bought = 3,
				})
				expect({ open = st.fam.school.open, bought = st.fam.school.bought }).toEqual({
					open = 3,
					bought = 2,
				})
			end
		)
	end)

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
		-- check.sh : les 11 configurations des deux portes, jouées à la fois (les plus longues d'abord)
		local jobs = {}
		local function job(name, j)
			j.seed = SEED
			table.insert(jobs, { name = name, job = j })
		end
		for _, size in { 4, 8, 16 } do
			job(
				"v2.assidu." .. size,
				{ flags = true, size = size, players = V2_PLAYERS, days = 28, v2 = { assidu = true } }
			)
			job("v2.ref." .. size, { flags = true, size = size, players = V2_PLAYERS, days = 84, v2 = {} })
		end
		for _, size in EconomyModel.SIZES do
			job("v13." .. size, { flags = false, size = size, players = PLAYERS, days = DAYS })
		end
		job("v13.spender", { flags = false, size = 16, players = SPENDERS, days = DAYS, spender = true })
		job(
			"v2.noAscend",
			{ flags = true, size = 16, players = V2_PLAYERS, days = 28, v2 = { ascend = false } }
		)
		local started = os.time()
		local runs, failed = runJobs(jobs)
		print(
			string.format(
				"\n  Portes v1.3 et v2.0 : %d configurations, %d à la fois, %d s",
				#jobs,
				WORKERS,
				os.time() - started
			)
		)
		describe("EconomyPacing : configurations jouées", function()
			it("chaque configuration a rendu ses joueurs (fils sans erreur ni trace)", function()
				expect(table.concat(failed, "\n")).toBe("")
				for _, j in jobs do
					expect({ name = j.name, players = runs[j.name] and #runs[j.name] or 0 }).toEqual({
						name = j.name,
						players = j.job.players,
					})
				end
			end)
			-- un fils rend les mêmes joueurs, au bit près, que le calcul en place (même graine, même code)
			it("un fils rend les mêmes joueurs que le calcul en place", function()
				local small = {
					{
						name = "v2",
						job = {
							flags = true,
							size = 8,
							players = 2,
							days = 3,
							seed = SEED,
							v2 = { assidu = true },
						},
					},
					{ name = "v13", job = { flags = false, size = 4, players = 2, days = 2, seed = SEED } },
				}
				local child = runJobs(small)
				-- égalité profonde au bit près (NaN égal à NaN), chemin de la première différence
				local function diff(a, b, path)
					if type(a) == "number" and type(b) == "number" then
						return if a == b or (a ~= a and b ~= b) then nil else path
					elseif type(a) ~= "table" or type(b) ~= "table" then
						return if a == b then nil else path
					end
					for k, v in a do
						local d = diff(v, b[k], path .. "." .. tostring(k))
						if d then
							return d
						end
					end
					for k in b do
						if a[k] == nil then
							return path .. "." .. tostring(k)
						end
					end
					return nil
				end
				for _, j in small do
					expect(diff(child[j.name], EconomyIO.run(L, j.job), j.name)).toBeNil()
				end
			end)
		end)
		if #failed == 0 then
			baseGate(runs)
			v2Gate(runs)
		end
	end

	describe("EconomyPacing : zéro trace", function()
		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
