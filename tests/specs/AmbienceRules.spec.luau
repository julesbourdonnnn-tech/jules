--!nocheck
-- AmbienceRules (lot B4, étape 1 ; décisions D4 et D5 du plan B4 ; GDD v2.0 §11.3, §5.6) : règles
-- pures du directeur d'ambiance.
--   * preset : la couche la plus haute gagne, sur TOUTES les combinaisons de couches (Jelly Moon >
--     BOOP RUSH / Rush adouci > MEGA > Party > météo > costume > jour) ;
--   * weather(unix) = Server/Meta/Weather.at(unix, false) sur plus de 20 000 instants tirés et à chaque
--     borne de fenêtre ± 1 s (même sel) ; nil hors des fenêtres ;
--   * fromEvent : la sorte d'EventState.weather tant que la fenêtre dure ;
--   * entrées hostiles : jamais d'erreur ; zéro trace.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local L = "ReplicatedStorage.Shared."
	local h = Harness.new()
	local AmbienceRules = h:require(L .. "Logic.AmbienceRules")
	local Events = h:require(L .. "Config.Events")
	local Hash = h:require(L .. "Logic.Hash")
	local Weather = h:require("ServerScriptService.Server.Meta.Weather")

	local H0 = 1800000000 -- vendredi 08:00:00 UTC (début d'heure)
	local KINDS = Events.Weather.Kinds
	local HOSTILE = { 0 / 0, math.huge, -math.huge, "1800000000", {}, true }

	-- Référence écrite à part : ordre du GDD §11.3
	local function reference(s)
		if s.moon then
			return "moon"
		end
		if s.rush then
			return if s.quietRush then "rush.quiet" else "rush"
		end
		if s.mega then
			return "mega"
		end
		if s.party then
			return "party"
		end
		local w = s.weather
		if type(w) == "number" and KINDS[w] then
			return "weather." .. KINDS[w]
		elseif type(w) == "string" and table.find(KINDS, w) then
			return "weather." .. w
		end
		if s.costume == "winter" then
			return "costume.winter"
		end
		return "day"
	end

	local function same(a, b)
		if a == nil or b == nil then
			return a == nil and b == nil
		end
		return a.kind == b.kind and a.endsAt == b.endsAt
	end

	describe("AmbienceRules › pile à priorités", function()
		it("toutes les combinaisons de couches : la plus haute gagne", function()
			local weathers = { false, "sunny", "rainbow", 2, 4, "storm", 0, 5 }
			local costumes = { false, "winter", "bad id!", "" }
			local count = 0
			for mask = 0, 31 do
				for _, w in weathers do
					for _, c in costumes do
						local s = {
							moon = bit32.btest(mask, 1),
							rush = bit32.btest(mask, 2),
							quietRush = bit32.btest(mask, 4),
							mega = bit32.btest(mask, 8),
							party = bit32.btest(mask, 16),
							weather = if w == false then nil else w,
							costume = if c == false then nil else c,
						}
						expect({ s = s, preset = AmbienceRules.preset(s) }).toEqual({
							s = s,
							preset = reference(s),
						})
						count += 1
					end
				end
			end
			expect(count).toBe(32 * 8 * 4)
		end)

		it(
			"cas écrits : jour, costume, météo, Party, MEGA, Rush adouci, Lune au-dessus du Rush",
			function()
				local P = AmbienceRules.preset
				expect(P({})).toBe("day")
				expect(P({ costume = "winter" })).toBe("costume.winter")
				expect(P({ weather = "rainbow", costume = "winter" })).toBe("weather.rainbow")
				expect(P({ weather = 1 })).toBe("weather." .. KINDS[1])
				expect(P({ party = true, weather = "sunny" })).toBe("party")
				expect(P({ mega = true, party = true })).toBe("mega")
				expect(P({ rush = true, mega = true })).toBe("rush")
				expect(P({ rush = true, quietRush = true })).toBe("rush.quiet")
				expect(P({ quietRush = true })).toBe("day") -- pas de Rush : rien à adoucir
				expect(P({ moon = true, rush = true, mega = true, party = true })).toBe("moon")
				expect(AmbienceRules.ORDER).toEqual({
					"moon",
					"rush",
					"mega",
					"party",
					"weather",
					"costume",
					"day",
				})
			end
		)

		it(
			"valeurs hostiles : « day », jamais d'erreur ; une couche non booléenne ne compte pas",
			function()
				expect(AmbienceRules.preset(nil)).toBe("day")
				for _, v in HOSTILE do
					expect(AmbienceRules.preset(v)).toBe("day")
				end
				expect(AmbienceRules.preset({ moon = 1, rush = "yes", mega = {}, party = 0 / 0 })).toBe("day")
				expect(AmbienceRules.preset({ costume = string.rep("a", 33) })).toBe("day")
				expect(AmbienceRules.preset({ costume = "1winter" })).toBe("day")
				expect(AmbienceRules.preset({ weather = 0 / 0, costume = 5 })).toBe("day")
			end
		)
	end)

	describe("AmbienceRules › météo (copie de Meta/Weather.at(unix, false))", function()
		it("même sel que le serveur", function()
			expect(AmbienceRules.SALT).toBe(Weather.SALT)
		end)

		it("20 000 instants tirés (heures, jours, années) : résultat identique", function()
			local s = Hash.stream(20261107)
			local present = 0
			for i = 1, 20000 do
				local unix
				if i % 4 == 0 then
					unix = H0 + s:range(0, 30 * 86400) -- un mois, secondes fractionnaires
				elseif i % 4 == 1 then
					unix = math.floor(s:range(0, 4e9)) -- 1970 … 2096, secondes entières
				elseif i % 4 == 2 then
					unix = H0 + s:int(0, 2000) * 3600 + s:int(7 * 60, 14 * 60) -- autour de la 1re fenêtre
				else
					unix = H0 + s:int(0, 2000) * 3600 + s:int(37 * 60, 44 * 60) -- autour de la 2e
				end
				local a, b = AmbienceRules.weather(unix), Weather.at(unix, false)
				expect({ i = i, same = same(a, b) }).toEqual({ i = i, same = true })
				if a then
					present += 1
					expect(a.kind >= 1 and a.kind <= #KINDS).toBe(true)
				end
			end
			-- les deux cas sont parcourus
			expect(present > 2000 and present < 18000).toBe(true)
		end)

		it("chaque borne de fenêtre ± 1 s (et ± 1 ms) sur 300 heures : résultat identique", function()
			local checked = 0
			for hour = 0, 299 do
				local base = H0 + hour * 3600
				for _, window in Events.Weather.Windows do
					for _, edge in { window[1], window[2] } do
						local t = base + edge * 60
						for _, d in { -1, -0.001, 0, 0.001, 1 } do
							local a, b = AmbienceRules.weather(t + d), Weather.at(t + d, false)
							expect({ t = t + d, same = same(a, b) }).toEqual({ t = t + d, same = true })
							checked += 1
						end
					end
				end
			end
			expect(checked).toBe(300 * #Events.Weather.Windows * 2 * 5)
		end)

		it("fenêtres :08:00-:13:00 et :38:00-:43:00 (fin exclue) ; nil hors des fenêtres", function()
			local function at(minute, second)
				return AmbienceRules.weather(H0 + minute * 60 + second)
			end
			expect(at(7, 59.999)).toBe(nil)
			expect(at(8, 0) ~= nil).toBe(true)
			expect(at(12, 59.999) ~= nil).toBe(true)
			expect(at(13, 0)).toBe(nil)
			expect(at(25, 0)).toBe(nil)
			expect(at(38, 0) ~= nil).toBe(true)
			expect(at(43, 0)).toBe(nil)
			expect(at(59, 59)).toBe(nil)
			-- fin de fenêtre exacte, même sorte pendant toute la fenêtre
			local w = at(9, 30)
			expect(w.endsAt).toBe(H0 + 13 * 60)
			expect(at(12, 59).kind).toBe(w.kind)
			expect(AmbienceRules.weather(nil)).toBe(nil)
			for _, v in HOSTILE do
				expect(AmbienceRules.weather(v)).toBe(nil)
			end
		end)

		it(
			"fromEvent : la sorte tant que la fenêtre dure ; fin passée, fin trop lointaine ou sorte inconnue → nil",
			function()
				local now = H0 + 9 * 60
				local live = Weather.at(now, false)
				expect(AmbienceRules.fromEvent(live, now)).toBe(KINDS[live.kind])
				expect(AmbienceRules.fromEvent({ kind = 2, endsAt = now + 1 }, now)).toBe(KINDS[2])
				expect(AmbienceRules.fromEvent({ kind = "rainbow", endsAt = now + 1 }, now)).toBe("rainbow")
				expect(AmbienceRules.fromEvent({ kind = 2, endsAt = now }, now)).toBe(nil)
				expect(AmbienceRules.fromEvent({ kind = 2, endsAt = now - 30 }, now)).toBe(nil)
				expect(AmbienceRules.fromEvent({ kind = 2, endsAt = now + 3600 }, now)).toBe(nil)
				for _, kind in { 0, 5, 1.5, "storm", 0 / 0 } do
					expect(AmbienceRules.fromEvent({ kind = kind, endsAt = now + 10 }, now)).toBe(nil)
				end
				expect(AmbienceRules.fromEvent(nil, now)).toBe(nil)
				expect(AmbienceRules.fromEvent(live, nil)).toBe(nil)
				for _, v in HOSTILE do
					expect(AmbienceRules.fromEvent(v, now)).toBe(nil)
					expect(AmbienceRules.fromEvent({ kind = 1, endsAt = v }, now)).toBe(nil)
					expect(AmbienceRules.fromEvent(live, v)).toBe(nil)
				end
			end
		)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
