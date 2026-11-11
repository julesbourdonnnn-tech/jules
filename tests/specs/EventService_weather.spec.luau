--!nocheck
-- EventService_weather (lot A4, étape 3 ; décisions D8, D25, D26 du plan ; docs/04 §27.5, §27.7, §27.12
-- A4-17 et suivantes ; GDD v2.0 §5.6, §7.5) : météo de Wobbleton (purement visuelle) et place en fête.
--   * Meta/Weather : fenêtres exactes :08:00-:13:00 et :38:00-:43:00 UTC (fin exclue), une sorte par
--     fenêtre, la même sur deux serveurs au même instant, aucune pendant une séance de Jelly Moon ;
--   * EventState.weather renvoyé au début et à la fin de chaque fenêtre (rien entre) ; interrupteurs
--     coupés : ni clé weather ni clé fete, charge égale à celle d'un serveur témoin ;
--   * aucun effet sur le jeu : même graine, mêmes naissances, mutations et pièces sur 1 h, météo et fête
--     ouvertes ou coupées ; seul EventService lit Meta/Weather ;
--   * place en fête : niveaux 0 à 5 selon les seuils, EventState renvoyé au changement de niveau et au
--     changement d'interrupteur en direct, points comptés interrupteur ouvert seulement, Wobble Party + 2 ;
--   * moon.sessions + 1 à chaque Goutte de Lune d'un profil v2 ; profil v1 : rien d'écrit.
local fs = require("@lune/fs")
local Flags = require("../harness/Flags")
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local LuauScan = require("../harness/LuauScan")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local H0 = 1800000000 -- vendredi 08:00:00 UTC (début d'heure)
	local MOON = H0 + 32 * 3600 -- samedi 16:00 UTC (séance de Jelly Moon de 20 min)
	local L = "ReplicatedStorage.Shared."
	local WEATHER = "ServerScriptService.Server.Meta.Weather"
	-- clés d'EventState de la v1.3 (charge inchangée interrupteurs coupés)
	local V13_KEYS = "boost,features,gauge,golden,mega,moon,offset,rush,spectacle"

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : t0, flags (ouverts dans le test), v2 (serveur au schéma v2)
	local function boot(opts)
		opts = opts or {}
		-- opts.v13 : serveur de la v1.3 (préréglage « v13 », lot I D2 a)
		local w = Brains.boot(
			if opts.v2 then HarnessV2 elseif opts.v13 then Flags.harness(Harness, "v13") else Harness,
			{ t0 = opts.t0 or (H0 + 120) }
		)
		w.Weather = w.h:require(WEATHER)
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function lastState(w, p)
		local list = w.h:sentTo(p, "EventState")
		return list[#list] and list[#list][1]
	end

	local function keysOf(t)
		local keys = {}
		for k in t do
			table.insert(keys, k)
		end
		table.sort(keys)
		return table.concat(keys, ",")
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

	-- =========================================================================================
	describe("EventService_weather › Meta/Weather (module pur)", function()
		it(
			"fenêtres exactes :08:00-:13:00 et :38:00-:43:00 UTC (fin exclue), 600 s par heure, une sorte par fenêtre ; prochaine borne ; instants illisibles",
			function()
				local h = Harness.new()
				local Weather = h:require(WEATHER)
				local E = h:require(L .. "Config.Events")
				expect(E.Weather.Windows).toEqual({ { 8, 13 }, { 38, 43 } })
				expect(E.Weather.visualOnly).toBe(true)
				local H = H0 + 5 * 3600
				expect(Weather.at(H + 480 - 0.001, false)).toBeNil()
				local a = Weather.at(H + 480, false)
				expect(a ~= nil).toBe(true)
				expect(a.endsAt).toBe(H + 780)
				expect(a.kind >= 1 and a.kind <= #E.Weather.Kinds and a.kind == math.floor(a.kind)).toBe(true)
				expect(Weather.at(H + 779.999, false).kind).toBe(a.kind)
				expect(Weather.at(H + 780, false)).toBeNil()
				expect(Weather.at(H + 2280 - 0.001, false)).toBeNil()
				local b = Weather.at(H + 2280, false)
				expect(b.endsAt).toBe(H + 2580)
				expect(Weather.at(H + 2579.999, false).kind).toBe(b.kind)
				expect(Weather.at(H + 2580, false)).toBeNil()
				-- l'heure seconde par seconde : 2 × 300 s, la même sorte pendant toute une fenêtre
				local n = 0
				for s = 0, 3599 do
					local x = Weather.at(H + s, false)
					if x then
						n += 1
						expect(x.kind).toBe(if s < 1800 then a.kind else b.kind)
					end
				end
				expect(n).toBe(600)
				-- Jelly Moon : aucune
				expect(Weather.at(H + 500, true)).toBeNil()
				-- prochaine borne (début ou fin), strictement après
				expect(Weather.nextChange(H)).toBe(H + 480)
				expect(Weather.nextChange(H + 480)).toBe(H + 780)
				expect(Weather.nextChange(H + 600.5)).toBe(H + 780)
				expect(Weather.nextChange(H + 780)).toBe(H + 2280)
				expect(Weather.nextChange(H + 2280)).toBe(H + 2580)
				expect(Weather.nextChange(H + 2580)).toBe(H + 3600 + 480)
				expect(Weather.nextChange(H + 3599.9)).toBe(H + 3600 + 480)
				-- illisibles : jamais d'erreur
				expect(Weather.at(0 / 0, false)).toBeNil()
				expect(Weather.at(math.huge, false)).toBeNil()
				expect(Weather.nextChange(0 / 0)).toBe(math.huge)
				expect(Weather.nextChange(-math.huge)).toBe(math.huge)
				-- sur une semaine : les 4 sortes sortent, aucune ne prend tout
				local counts = {}
				for hour = 0, 167 do
					for _, minute in { 8, 38 } do
						local x = Weather.at(H0 + hour * 3600 + minute * 60 + 1, false)
						counts[x.kind] = (counts[x.kind] or 0) + 1
					end
				end
				for k = 1, #E.Weather.Kinds do
					expect({ k = k, some = (counts[k] or 0) > 0 }).toEqual({ k = k, some = true })
					expect(counts[k] < 336).toBe(true)
				end
			end
		)

		it(
			"même sorte sur deux serveurs au même instant (sel figé, aucun message entre serveurs)",
			function()
				local a = Harness.new():require(WEATHER)
				local b = Harness.new():require(WEATHER)
				expect(a.SALT).toBe(b.SALT)
				for i = 0, 499 do
					local t = H0 + i * 1800 + 8 * 60 + (i % 300)
					expect(deepEqual(a.at(t, false), b.at(t, false))).toBe(true)
				end
				-- deux serveurs qui tournent : même EventState.weather au même instant
				local t0 = H0 + 7 * 3600 + 38 * 60 + 10
				local wA = boot({ t0 = t0, flags = { "Weather" } })
				local pA = Brains.join(wA, 1)
				Brains.frames(wA, 3)
				local wB = boot({ t0 = t0, flags = { "Weather" } })
				local pB = Brains.join(wB, 1)
				Brains.frames(wB, 3)
				local sA, sB = lastState(wA, pA).weather, lastState(wB, pB).weather
				expect(sA ~= nil).toBe(true)
				expect(sA).toEqual(sB)
				expect(sA.endsAt).toBe(H0 + 7 * 3600 + 43 * 60)
				clean(wA)
				clean(wB)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_weather › EventState.weather", function()
		it(
			"renvoyé au début (:08:00) et à la fin (:13:00) de la fenêtre, au tick de la borne ; rien entre ; jamais à chaque tick",
			function()
				local w = boot({ t0 = H0 + 470, flags = { "Weather" } })
				local a = Brains.join(w, 1)
				Brains.frames(w, 2)
				expect(lastState(w, a).weather).toBeNil()
				local seen = {}
				local count = #w.h:sentTo(a, "EventState")
				for _ = 1, 3400 do
					Brains.frames(w, 1)
					local list = w.h:sentTo(a, "EventState")
					for i = count + 1, #list do
						table.insert(seen, { t = w.Clock.now(), weather = list[i][1].weather })
					end
					count = #list
					if w.Clock.now() > H0 + 800 then
						break
					end
				end
				local expected = w.Weather.at(H0 + 480, false)
				local startAt, endAt = nil, nil
				for _, s in seen do
					if s.t < H0 + 480 then
						expect(s.weather).toBeNil()
					elseif s.t < H0 + 780 then
						expect(s.weather).toEqual(expected)
						startAt = startAt or s.t
					else
						expect(s.weather).toBeNil()
						endAt = endAt or s.t
					end
				end
				-- au premier tick ≥ la borne (10 ticks par seconde)
				expect(startAt ~= nil and startAt - (H0 + 480) < 0.1 + 1e-6).toBe(true)
				expect(endAt ~= nil and endAt - (H0 + 780) < 0.1 + 1e-6).toBe(true)
				-- quelques envois seulement (bornes, Golden de :10:30) : jamais un par tick
				expect(#seen <= 8).toBe(true)
				clean(w)
			end
		)

		it(
			"suspendue pendant une séance de Jelly Moon (:08 de 16:00) ; Jelly Moon coupée : la météo revient ; à :38 (séance finie) : météo",
			function()
				local w = boot({ t0 = MOON + 470, flags = { "Weather" } })
				local a = Brains.join(w, 1)
				Brains.frames(w, 200)
				local st = w.Event.state()
				expect(st.moon.active).toBe(true)
				expect(st.weather).toBeNil()
				expect(lastState(w, a).weather).toBeNil()
				w.Features.set("JellyMoon", false)
				expect(w.Event.state().weather).toEqual(w.Weather.at(w.Clock.now(), false))
				expect(w.Event.state().weather ~= nil).toBe(true)
				w.Features.set("JellyMoon", true)
				Bots.use(w)
				Bots.travelTo(MOON + 38 * 60 + 5)
				Brains.frames(w, 2)
				expect(w.Event.state().moon.active).toBe(false)
				expect(lastState(w, a).weather).toEqual(w.Weather.at(MOON + 38 * 60, false))
				clean(w)
			end
		)

		it(
			"interrupteurs coupés : EventState sans clé weather ni fete, égal à celui d'un serveur témoin (météo et fête ouvertes puis coupées)",
			function()
				-- deux serveurs au même instant, dans une fenêtre de météo, mêmes joueurs, mêmes faits
				local t0 = H0 + 3 * 3600 + 8 * 60 + 5
				local wA = boot({ t0 = t0 })
				local pA = Brains.join(wA, 1)
				local wB = boot({ t0 = t0 })
				local pB = Brains.join(wB, 1)
				Brains.frames(wA, 3)
				Brains.frames(wB, 3)
				expect(keysOf(lastState(wA, pA))).toBe(V13_KEYS)
				expect(keysOf(lastState(wB, pB))).toBe(V13_KEYS)
				-- B : météo et fête ouvertes en direct (renvoyé avec les deux clés), puis des points de fête
				wB.Features.set("Weather", true)
				wB.Features.set("Fete", true)
				Brains.frames(wA, 1)
				Brains.frames(wB, 1)
				local on = lastState(wB, pB)
				expect(on.weather ~= nil).toBe(true)
				expect(on.fete).toEqual({ level = 0 })
				for _ = 1, 6 do
					wA.Signals.Splorched:Fire(pA, 1, 0)
					wB.Signals.Splorched:Fire(pB, 1, 0)
				end
				Brains.frames(wA, 20)
				Brains.frames(wB, 20)
				expect(lastState(wB, pB).fete).toEqual({ level = 1 })
				-- B : tout recoupé en direct : renvoyé sans les clés
				wB.Features.set("Weather", false)
				wB.Features.set("Fete", false)
				Brains.frames(wA, 1)
				Brains.frames(wB, 1)
				expect(keysOf(lastState(wB, pB))).toBe(V13_KEYS)
				expect(lastState(wB, pB).weather).toBeNil()
				expect(lastState(wB, pB).fete).toBeNil()
				-- même charge que le témoin, construite au même instant
				expect(wA.Clock.now()).toBe(wB.Clock.now())
				local sA, sB = wA.Event.state(), wB.Event.state()
				expect(keysOf(sA)).toBe(V13_KEYS)
				expect(deepEqual(sA, sB)).toBe(true)
				clean(wA)
				clean(wB)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_weather › aucun effet sur le jeu", function()
		-- 1 h de jeu complet à `n` joueurs (cerveaux à graine fixe) ; rend naissances, mutations et pièces
		local function hour(flagsOn, n)
			local w = boot({ t0 = H0 + 30 })
			if flagsOn then
				w.Features.set("Weather", true)
				w.Features.set("Fete", true)
			end
			local players = {}
			for i = 1, n do
				local p = Brains.join(w, i, {
					profile = Brains.profile(w, {
						coins = 2000,
						squishies = { { s = 1, z = 50 }, { s = 2, z = 40 }, { s = 3, z = 30 } },
					}),
				})
				Bots.place(p, Brains.atRanch(w, p, 0, 30))
				Bots.setBrain(p, Brains.player(w, 100 + i))
				table.insert(players, p)
			end
			local hatches = {}
			w.Signals.SquishyObtained:Connect(function(p, uid, source)
				local rec = w.Squishy.get(p, uid)
				table.insert(
					hatches,
					string.format(
						"%d:%s:%s:%d:%d",
						p.UserId,
						tostring(uid),
						tostring(source),
						rec and rec.s or -1,
						rec and rec.m or -1
					)
				)
			end)
			local weatherSends = 0
			Brains.frames(w, 36000)
			-- liste triée : l'ordre de deux joueurs servis dans le même tick suit l'ordre de parcours d'une
			-- table indexée par joueur (deux serveurs témoins coupés ont la même liste triée, pas forcément
			-- le même ordre) ; chaque entrée garde le joueur, l'uid, la source, l'espèce et la mutation
			table.sort(hatches)
			local out = { hatches = hatches, coins = {}, squishies = {} }
			for _, p in players do
				local data = w.DS.get(p)
				out.coins[p.UserId] = data.coins
				local list = {}
				for uid, rec in data.squishies do
					table.insert(list, string.format("%s:%d:%d:%d:%.6g", uid, rec.s, rec.m, rec.st, rec.z))
				end
				table.sort(list)
				out.squishies[p.UserId] = table.concat(list, ",")
				for _, args in w.h:sentTo(p, "EventState") do
					if args[1].weather ~= nil then
						weatherSends += 1
					end
				end
			end
			out.weatherSends = weatherSends
			out.fete = w.Event.fetePoints()
			clean(w)
			return out
		end

		it(
			"même graine : mêmes naissances, mutations et pièces sur 1 h, météo et fête ouvertes ou coupées",
			function()
				-- 1 joueur : la partie est déterministe. À 3 joueurs, deux serveurs témoins coupés TOUS DEUX
				-- divergent déjà (ordre de parcours des tables indexées par joueur : qui est servi le premier
				-- quand deux joueurs visent la même chose dans le même tick ; lot A4, étape 5, A4-42) : la
				-- comparaison à l'identique se fait à 1 joueur, la partie à 3 joueurs reste jouée plus bas
				local off = hour(false, 1)
				local on = hour(true, 1)
				-- la météo a bien tourné d'un côté seulement (2 fenêtres par heure)
				expect(off.weatherSends).toBe(0)
				expect(on.weatherSends >= 2).toBe(true)
				expect(off.fete).toBe(0)
				-- des naissances ont eu lieu (le test n'est pas vide) ; tout est identique
				expect(#off.hatches > 0).toBe(true)
				expect(table.concat(on.hatches, "\n")).toBe(table.concat(off.hatches, "\n"))
				expect(on.coins).toEqual(off.coins)
				expect(on.squishies).toEqual(off.squishies)
			end
		)

		it(
			"à 3 joueurs, météo et fête ouvertes : 1 h de jeu complet sans trace, la météo envoyée à chacun",
			function()
				local three = hour(true, 3)
				expect(three.weatherSends >= 2 * 3).toBe(true)
				expect(#three.hatches > 0).toBe(true)
			end
		)

		it(
			"seul EventService requiert Meta/Weather, et seulement pour EventState (aucune récompense, chance ni prix)",
			function()
				local users = {}
				for _, path in LuauScan.files(fs, "src") do
					local code = LuauScan.strip(fs.readFile(path))
					if
						string.find(code, "Meta.Weather", 1, true) or string.find(code, "Weather)", 1, true)
					then
						table.insert(users, path)
					end
				end
				expect(table.concat(users, ",")).toBe("src/server/Services/EventService.luau")
				local code = LuauScan.strip(fs.readFile("src/server/Services/EventService.luau"))
				local uses = {}
				for name in string.gmatch(code, "Weather%.(%a+)") do
					table.insert(uses, name)
				end
				table.sort(uses)
				expect(table.concat(uses, ",")).toBe("at,nextChange")
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_weather › place en fête", function()
		it(
			"niveaux 0 à 5 selon les seuils (5, 15, 30, 50, 80), EventState renvoyé au changement de niveau seulement",
			function()
				local w = boot({ flags = { "Fete" } })
				-- jauge coupée : les Splorched ne changent que la fête (aucun autre renvoi)
				w.Features.set("ServerGauge", false)
				local a = Brains.join(w, 1)
				Brains.frames(w, 3)
				expect(lastState(w, a).fete).toEqual({ level = 0 })
				local levels = w.Events.Fete.Levels
				expect(levels).toEqual({ 5, 15, 30, 50, 80 })
				local points = 0
				local function add(n)
					for _ = 1, n do
						w.Signals.Splorched:Fire(a, 1, 0)
					end
					points += n
				end
				local function sends()
					return #w.h:sentTo(a, "EventState")
				end
				-- sous le seuil : aucun renvoi
				add(4)
				local n = sends()
				Brains.frames(w, 2)
				expect(sends()).toBe(n)
				expect(w.Event.fetePoints()).toBe(4)
				for level, threshold in levels do
					add(threshold - points - 1)
					n = sends()
					Brains.frames(w, 2)
					expect({ level = level, sends = sends() - n }).toEqual({ level = level, sends = 0 })
					expect(lastState(w, a).fete).toEqual({ level = level - 1 })
					add(1)
					Brains.frames(w, 1)
					expect({ level = level, sends = sends() - n }).toEqual({ level = level, sends = 1 })
					expect(lastState(w, a).fete).toEqual({ level = level })
				end
				-- au-delà de 80 : niveau 5, plus aucun renvoi
				n = sends()
				add(100)
				Brains.frames(w, 2)
				expect(sends()).toBe(n)
				expect(w.Event.state().fete).toEqual({ level = 5 })
				expect(w.Event.fetePoints()).toBe(180)
				clean(w)
			end
		)

		it(
			"interrupteur changé en direct : renvoyé sans puis avec la clé ; points comptés interrupteur ouvert seulement ; Wobble Party + 2",
			function()
				local w = boot({ flags = { "Fete" } })
				local a = Brains.join(w, 1)
				Brains.frames(w, 3)
				for _ = 1, 5 do
					w.Signals.Splorched:Fire(a, 1, 0)
				end
				Brains.frames(w, 12)
				expect(lastState(w, a).fete).toEqual({ level = 1 })
				local n = #w.h:sentTo(a, "EventState")
				w.Features.set("Fete", false)
				Brains.frames(w, 1)
				expect(#w.h:sentTo(a, "EventState")).toBe(n + 1)
				expect(lastState(w, a).fete).toBeNil()
				-- coupé : rien ne compte
				for _ = 1, 20 do
					w.Signals.Splorched:Fire(a, 1, 0)
				end
				w.Signals.PrestigeApplied:Fire(a, "ascend", 15, 3, 1)
				expect(w.Event.fetePoints()).toBe(5)
				Brains.frames(w, 12)
				-- rouvert : points gardés (repart de 0 seulement avec le serveur)
				n = #w.h:sentTo(a, "EventState")
				w.Features.set("Fete", true)
				Brains.frames(w, 1)
				expect(#w.h:sentTo(a, "EventState")).toBe(n + 1)
				expect(lastState(w, a).fete).toEqual({ level = 1 })
				-- Wobble Party : + 2 à son début (danse de la jauge pleine, puis la fête)
				w.Event.addGauge(1e6)
				for _ = 1, 400 do
					Brains.frames(w, 1)
					if w.Event.state().boost.kind == "wobble" then
						break
					end
				end
				expect(w.Event.state().boost.kind).toBe("wobble")
				expect(w.Event.fetePoints()).toBe(5 + w.Events.Fete.Points.party)
				expect(w.Events.Fete.Points.party).toBe(2)
				clean(w)
			end
		)
	end)

	-- =========================================================================================
	describe("EventService_weather › moon.sessions (D8)", function()
		local function moonDrop(v2)
			local w = boot({ t0 = MOON - 5, v2 = v2, v13 = not v2 })
			local p = Brains.join(w, 1)
			local altar = w.WL.plaza("altar")
			Bots.place(p, Bots.ground(altar.X, altar.Z))
			Brains.frames(w, 3200)
			Bots.use(w)
			Bots.travelTo(w.EventClock.moon(MOON).endsAt + 0.05)
			Brains.frames(w, 3)
			expect(#Bots.celebrations(p, "lunarDrop")).toBe(1)
			return w, p
		end

		it(
			"profil v2 : + 1 à chaque Goutte de Lune (séance suivante : 2) ; profil v1 : moon.sessions jamais écrit",
			function()
				local w, p = moonDrop(true)
				local data = w.DS.get(p)
				expect(data.version >= 2).toBe(true)
				expect(data.moon.sessions).toBe(1)
				-- séance de 18:00 : une 2e Goutte, + 1
				local altar = w.WL.plaza("altar")
				Bots.use(w)
				Bots.travelTo(MOON + 2 * 3600 - 5)
				Bots.place(p, Bots.ground(altar.X, altar.Z))
				Brains.frames(w, 3200)
				Bots.use(w)
				Bots.travelTo(w.EventClock.moon(MOON + 2 * 3600).endsAt + 0.05)
				Brains.frames(w, 3)
				expect(#Bots.celebrations(p, "lunarDrop")).toBe(2)
				expect(w.DS.get(p).moon.sessions).toBe(2)
				clean(w)
				-- serveur v1 : aucune clé de plus dans le profil
				local w1, p1 = moonDrop(false)
				local d1 = w1.DS.get(p1)
				expect(d1.version == nil or d1.version < 2).toBe(true)
				expect(d1.moon.sessions).toBeNil()
				expect(d1.moon.lastSession > 0).toBe(true)
				clean(w1)
			end
		)
	end)
end
