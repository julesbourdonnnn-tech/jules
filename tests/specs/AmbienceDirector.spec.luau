--!nocheck
-- AmbienceDirector (lot B4, étape 2 ; docs/04 §27.7, N12 ; GDD v2.0 §11.3 ; décisions D2, D3, D4, D27 du
-- plan B4) : Render/AmbienceDirector, seul écrivain de Lighting, conduit par LightingController.
--   * interrupteur Ambience coupé (la version livrée) : EXACTEMENT les écritures de Lighting de la v1.3,
--     dans le même ordre (trace enregistrée sur le code de la v1.3, commit 0954692, avant le déplacement :
--     jour, sirène du Rush, Lune, fête, hiver, Rush discret d'un nouveau, Mouvement réduit), aucune
--     écriture de LightingStyle ni de PrioritizeLightingQuality, aucune pile, aucun travail par image ;
--   * Ambience ouvert (EventState.features.ambience) : chaque paire de couches (Lune > Rush > alerte et
--     MEGA > fêtes > météo > costume > jour), météo seulement depuis EventState.weather valide et pas
--     finie, transitions de 2 s et 4 s, Mouvement réduit en fondu de 4 s sans saut de propriété, Soft et
--     false tant qu'il est ouvert, valeurs de la place rendues et v1.3 exacte quand il est coupé en direct ;
--   * EventState hostile : jour, sans trace ; vrai WorldStateController : la clé passe telle quelle ;
--   * serveur (INT-B4-AMBIENCE) : features.ambience présent seulement interrupteur ouvert, charge sinon
--     identique à celle d'un serveur témoin.
local roblox = require("@lune/roblox")
local ApiAudit = require("../harness/ApiAudit")
local Brains = require("../harness/Brains")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum

-- Trace de la v1.3 (Ambience coupé) : enregistrée par la sonde du lot B4 sur le code d'avant le
-- déplacement ; « set » = écriture directe, « tween » = tween créé (instance, durée, style, objectifs
-- triés), « new » = effet créé dans Lighting, « -- » = étape du scénario
local V13_TRACE = [[
-- init
new Atmosphere SquishyAtmosphere
set SquishyAtmosphere.Density=0.25
set SquishyAtmosphere.Haze=1.2
set SquishyAtmosphere.Decay=(170,200,255)
new BloomEffect SquishyBloom
set SquishyBloom.Size=20
set SquishyBloom.Threshold=1.3
new ColorCorrectionEffect SquishyColor
set SquishyColor.Saturation=0.2
set SquishyColor.Contrast=0.05
new Sky SquishySky
set Lighting.ClockTime=14.5
set Lighting.Brightness=2.5
set Lighting.Ambient=(150,140,170)
set Lighting.OutdoorAmbient=(190,180,210)
set SquishyAtmosphere.Color=(255,220,240)
set SquishyColor.TintColor=(255,255,255)
set SquishyBloom.Intensity=0.6
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- start
set Lighting.ClockTime=14.5
set Lighting.Brightness=2.5
set Lighting.Ambient=(150,140,170)
set Lighting.OutdoorAmbient=(190,180,210)
set SquishyAtmosphere.Color=(255,220,240)
set SquishyColor.TintColor=(255,255,255)
set SquishyBloom.Intensity=0.6
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- siren
tween Lighting 2 Sine/InOut Ambient=(150,140,170) Brightness=2.5 ClockTime=14.5 OutdoorAmbient=(190,180,210)
tween SquishyAtmosphere 2 Sine/InOut Color=(255,190,220)
tween SquishyColor 2 Sine/InOut TintColor=(255,200,225)
tween SquishyBloom 2 Sine/InOut Intensity=0.6
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- moon
tween Lighting 4 Sine/InOut Ambient=(120,110,175) Brightness=1.6 ClockTime=24 OutdoorAmbient=(130,120,200)
tween SquishyAtmosphere 4 Sine/InOut Color=(150,120,220)
tween SquishyColor 4 Sine/InOut TintColor=(200,190,255)
tween SquishyBloom 4 Sine/InOut Intensity=0.7
set SquishySky.StarCount=4000
set SquishySky.MoonAngularSize=30
-- party
tween Lighting 4 Sine/InOut Ambient=(120,110,175) Brightness=1.6 ClockTime=0 OutdoorAmbient=(130,120,200)
tween SquishyAtmosphere 4 Sine/InOut Color=(150,120,220)
tween SquishyColor 4 Sine/InOut TintColor=(255,240,210)
tween SquishyBloom 4 Sine/InOut Intensity=0.8
set SquishySky.StarCount=4000
set SquishySky.MoonAngularSize=30
-- moon-winter
tween Lighting 4 Sine/InOut Ambient=(120,110,175) Brightness=1.6 ClockTime=0 OutdoorAmbient=(130,120,200)
tween SquishyAtmosphere 4 Sine/InOut Color=(150,120,220)
tween SquishyColor 4 Sine/InOut TintColor=(200,190,255)
tween SquishyBloom 4 Sine/InOut Intensity=0.7
set SquishySky.StarCount=4000
set SquishySky.MoonAngularSize=30
-- winter
tween Lighting 4 Sine/InOut Ambient=(150,150,180) Brightness=2.6 ClockTime=14.5 OutdoorAmbient=(195,195,225)
tween SquishyAtmosphere 4 Sine/InOut Color=(230,235,255)
tween SquishyColor 4 Sine/InOut TintColor=(240,247,255)
tween SquishyBloom 4 Sine/InOut Intensity=0.65
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- quiet-rush-winter
tween Lighting 2 Sine/InOut Ambient=(150,150,180) Brightness=2.6 ClockTime=14.5 OutdoorAmbient=(195,195,225)
tween SquishyAtmosphere 2 Sine/InOut Color=(238,221,245)
tween SquishyColor 2 Sine/InOut TintColor=(245,233,246)
tween SquishyBloom 2 Sine/InOut Intensity=0.65
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- rush-winter
tween Lighting 2 Sine/InOut Ambient=(150,150,180) Brightness=2.6 ClockTime=14.5 OutdoorAmbient=(195,195,225)
tween SquishyAtmosphere 2 Sine/InOut Color=(255,190,220)
tween SquishyColor 2 Sine/InOut TintColor=(255,200,225)
tween SquishyBloom 2 Sine/InOut Intensity=0.65
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- reduced-day
tween Lighting 0.5 Sine/InOut Ambient=(150,140,170) Brightness=2.5 ClockTime=14.5 OutdoorAmbient=(190,180,210)
tween SquishyAtmosphere 0.5 Sine/InOut Color=(255,190,220)
tween SquishyColor 0.5 Sine/InOut TintColor=(255,200,225)
tween SquishyBloom 0.5 Sine/InOut Intensity=0.6
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
tween Lighting 0.5 Sine/InOut Ambient=(150,140,170) Brightness=2.5 ClockTime=14.5 OutdoorAmbient=(190,180,210)
tween SquishyAtmosphere 0.5 Sine/InOut Color=(255,220,240)
tween SquishyColor 0.5 Sine/InOut TintColor=(255,255,255)
tween SquishyBloom 0.5 Sine/InOut Intensity=0.6
set SquishySky.StarCount=3000
set SquishySky.MoonAngularSize=11
-- reduced-moon
tween Lighting 0.5 Sine/InOut Ambient=(120,110,175) Brightness=1.6 ClockTime=24 OutdoorAmbient=(130,120,200)
tween SquishyAtmosphere 0.5 Sine/InOut Color=(150,120,220)
tween SquishyColor 0.5 Sine/InOut TintColor=(200,190,255)
tween SquishyBloom 0.5 Sine/InOut Intensity=0.7
set SquishySky.StarCount=4000
set SquishySky.MoonAngularSize=30
-- steady
]]

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Instants (UTC) : mardi 8/12/2026 10:02 (rien), sirène 10:04:55, samedi 12/12 16:02 (Lune, costume
	-- d'hiver en vigueur), dimanche 13/12 10:02 (hiver seul) ; T0 : dimanche 10:04:55, sirène du Rush et
	-- costume d'hiver en vigueur (toutes les couches réglables par la charge)
	local T_DAY = 1796724120
	local T_SIREN = T_DAY + 175
	local T_MOON = 1797091320
	local T_WINTER = 1797156120
	local T0 = T_WINTER + 175

	local base = "StarterPlayer.StarterPlayerScripts.Client."
	local MT = getmetatable(MockInstance.new("Folder"))
	local NEWCOMER = { coins = 0, onboarding = { step = 3, done = false, demoDone = false } }

	local function rgb(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end

	local function features(over)
		local f = {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
		for k, v in over or {} do
			f[k] = v
		end
		return f
	end

	local function mega(phase, endsAt)
		return {
			phase = phase,
			index = 0,
			landsAt = 0,
			endsAt = endsAt,
			target = 0,
			points = 0,
			species = 1,
			moon = false,
			result = "",
		}
	end

	local function payload(over)
		local p = {
			rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
			mega = mega("idle", 0),
			golden = { active = false, id = 0, endsAt = 0 },
			moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
			gauge = { points = 0, target = 1000, partyUntil = 0, restUntil = 0 },
			boost = { kind = "", untilT = 0, byName = "" },
			spectacle = { queue = {} },
			features = features(),
			offset = 0,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	-- EventState à l'instant t (T0 par défaut) avec les couches demandées : moon, rush, mega, party,
	-- weather (true = sorte 2, ou le rang), costume ; Ambience ouvert sauf v13 = true
	local function layered(on, t, v13)
		t = t or T0
		local unix = math.floor(t)
		local kind = if on.weather == true then 2 else on.weather
		return payload({
			moon = if on.moon
				then { active = true, session = 1, endsAt = t + 600, nextAt = 0 }
				else { active = false, session = 0, endsAt = 0, nextAt = 0 },
			mega = if on.mega then mega("press", t + 30) else mega("idle", 0),
			boost = if on.party
				then { kind = "wobble", untilT = t + 600, byName = "" }
				else { kind = "", untilT = 0, byName = "" },
			weather = if kind then { kind = kind, endsAt = unix + 100 } else nil,
			features = features({
				ambience = if v13 then nil else true,
				boopRush = if on.rush then "on" else "off",
				costume = if on.costume then "winter2026" else "",
			}),
		})
	end

	local function zeroLog(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- Écritures de Lighting et de ses effets ------------------------------------------------------

	local function fmt(v)
		local t = typeof(v)
		if t == "number" then
			local s = string.format("%.4f", v)
			s = string.gsub(s, "0+$", "")
			s = string.gsub(s, "%.$", "")
			return s
		elseif t == "Color3" then
			local c = rgb(v)
			return string.format("(%d,%d,%d)", c[1], c[2], c[3])
		elseif t == "EnumItem" then
			return (string.gsub(tostring(v), "^Enum%.%w+%.", ""))
		end
		return tostring(v)
	end

	local function inLighting(self)
		local st = MockInstance.state(self)
		if st.ClassName == "Lighting" then
			return true
		end
		local parent = st.Parent
		return parent ~= nil and MockInstance.state(parent).ClassName == "Lighting"
	end

	local function nameOf(self)
		return MockInstance.state(self).Name
	end

	-- Enregistreur : tweens créés (instance, durée, style, objectifs triés), écritures directes et effets
	-- créés ; les valeurs posées par le Play d'un tween simulé ne sont pas des écritures du jeu
	local function recorder()
		local log, tweens = {}, {}
		local origNew = MT.__newindex
		local origCreate = MockInstance.classMethods.TweenService.Create
		MT.__newindex = function(self, key, value)
			if type(key) == "string" then
				local source, fname = debug.info(2, "sn")
				local fromPlay = type(source) == "string"
					and string.find(source, "harness/Services", 1, true) ~= nil
					and fname == "Play"
				if not fromPlay then
					if
						key == "Parent"
						and MockInstance.is(value)
						and MockInstance.state(value).ClassName == "Lighting"
					then
						table.insert(log, "new " .. MockInstance.state(self).ClassName .. " " .. nameOf(self))
					elseif key ~= "Parent" and key ~= "Name" and inLighting(self) then
						table.insert(log, "set " .. nameOf(self) .. "." .. key .. "=" .. fmt(value))
					end
				end
			end
			return origNew(self, key, value)
		end
		MockInstance.classMethods.TweenService.Create = function(svc, inst, info, goals)
			local tween = origCreate(svc, inst, info, goals)
			if inLighting(inst) then
				local keys = {}
				for k in goals do
					table.insert(keys, k)
				end
				table.sort(keys)
				local parts = {}
				for _, k in keys do
					table.insert(parts, k .. "=" .. fmt(goals[k]))
				end
				table.insert(
					log,
					"tween "
						.. nameOf(inst)
						.. " "
						.. fmt(info.Time)
						.. " "
						.. fmt(info.EasingStyle)
						.. "/"
						.. fmt(info.EasingDirection)
						.. " "
						.. table.concat(parts, " ")
				)
				table.insert(tweens, { name = nameOf(inst), time = info.Time, tween = tween, goals = goals })
			end
			return tween
		end
		return log,
			tweens,
			function()
				MT.__newindex = origNew
				MockInstance.classMethods.TweenService.Create = origCreate
			end
	end

	-- Ordre sans importance à l'intérieur d'un même lot d'écritures immédiates d'une instance (ordre
	-- d'une table) : chaque suite de « set X.… » de la même instance X est triée
	local function normalize(lines)
		local out, run, runName = {}, {}, nil
		local function flush()
			table.sort(run)
			for _, l in run do
				table.insert(out, l)
			end
			table.clear(run)
			runName = nil
		end
		for _, line in lines do
			local name = string.match(line, "^set ([%w_]+)%.")
			if name and name == runName then
				table.insert(run, line)
			else
				flush()
				if name then
					runName = name
					table.insert(run, line)
				else
					table.insert(out, line)
				end
			end
		end
		flush()
		return out
	end

	local function lines(text)
		local out = {}
		for line in string.gmatch(text, "[^\n]+") do
			table.insert(out, line)
		end
		return out
	end

	-- Client avec LightingController démarré ; `event` = EventState de WorldStateController (doublure) ;
	-- `place` : LightingStyle / PrioritizeLightingQuality de la place ; `record` : enregistreur posé
	-- avant Init
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T_DAY)
		local WSC = h:require(base .. "Controllers.WorldStateController")
		local Prefs = h:require(base .. "Util.Prefs")
		local current = opts.event
		WSC.event = function()
			return current
		end
		Prefs.Init()
		local State = h:require(base .. "Controllers.StateController")
		State.Init()
		if opts.profile then
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", opts.profile)
			h:settle(1)
		end
		local L = h.game.Lighting
		if opts.place then
			L.LightingStyle = opts.place.style
			L.PrioritizeLightingQuality = opts.place.quality
		end
		local LC = h:require(base .. "Controllers.LightingController")
		local AD = h:require(base .. "Render.AmbienceDirector")
		local c = { h = h, LC = LC, AD = AD, Clock = Clock, WSC = WSC, Prefs = Prefs, L = L }
		if opts.record then
			c.log, c.tweens, c.stop = recorder()
		end
		LC.Init()
		LC.Start()
		-- nouvel EventState (signal de WorldStateController, puis une image)
		c.setEvent = function(p)
			current = p
			WSC.EventChanged:Fire(p)
			h:settle(1)
		end
		-- EventState changé sans signal ni image (les tweens simulés restent « en cours »)
		c.setRaw = function(p)
			current = p
		end
		return c
	end

	-- Éclairage visible : Lighting et ses 4 effets
	local function snapshot(c)
		local L = c.L
		return {
			clock = L.ClockTime % 24,
			ambient = rgb(L.Ambient),
			outdoor = rgb(L.OutdoorAmbient),
			brightness = L.Brightness,
			atmosphere = rgb(L.SquishyAtmosphere.Color),
			density = L.SquishyAtmosphere.Density,
			haze = L.SquishyAtmosphere.Haze,
			decay = rgb(L.SquishyAtmosphere.Decay),
			bloom = L.SquishyBloom.Intensity,
			bloomSize = L.SquishyBloom.Size,
			threshold = L.SquishyBloom.Threshold,
			tint = rgb(L.SquishyColor.TintColor),
			saturation = L.SquishyColor.Saturation,
			contrast = L.SquishyColor.Contrast,
			stars = L.SquishySky.StarCount,
			moon = L.SquishySky.MoonAngularSize,
			style = tostring(L.LightingStyle),
			quality = tostring(L.PrioritizeLightingQuality),
		}
	end

	-- Lighting à l'aspect d'un préréglage de la pile
	local function expectLook(c, name)
		local l = c.AD.look(name)
		local L = c.L
		expect({
			name = name,
			clock = L.ClockTime % 24,
			ambient = rgb(L.Ambient),
			outdoor = rgb(L.OutdoorAmbient),
			brightness = L.Brightness,
			atmosphere = rgb(L.SquishyAtmosphere.Color),
			bloom = L.SquishyBloom.Intensity,
			tint = rgb(L.SquishyColor.TintColor),
			saturation = L.SquishyColor.Saturation,
			stars = L.SquishySky.StarCount,
			moon = L.SquishySky.MoonAngularSize,
		}).toEqual({
			name = name,
			clock = l.clockTime % 24,
			ambient = rgb(l.ambient),
			outdoor = rgb(l.outdoorAmbient),
			brightness = l.brightness,
			atmosphere = rgb(l.atmosphereColor),
			bloom = l.bloom,
			tint = rgb(l.tint),
			saturation = l.saturation,
			stars = l.starCount,
			moon = l.moonSize,
		})
	end

	-- =========================================================================================
	describe("AmbienceDirector › interrupteur coupé (v1.3)", function()
		it(
			"mêmes écritures de Lighting que la v1.3, dans le même ordre (jour, sirène, Lune, fête, hiver, Rush discret, Mouvement réduit) ; LightingStyle et PrioritizeLightingQuality jamais écrits",
			function()
				local c = client({
					t = T_DAY,
					event = payload(),
					place = { style = Enum.LightingStyle.Realistic, quality = true },
					record = true,
				})
				local log = c.log
				local ok, err = pcall(function()
					-- même scénario que la sonde qui a enregistré V13_TRACE (Init et Start déjà faits)
					local function mark(s)
						table.insert(log, "-- " .. s)
					end
					table.insert(log, 1, "-- init")
					local startAt = table.find(log, "new Sky SquishySky")
					-- Init = 4 effets + jour immédiat (9 écritures) ; Start = jour forcé (9 écritures)
					table.insert(log, startAt + 10, "-- start")
					mark("siren")
					c.Clock.freeze(T_SIREN)
					c.LC.refresh()
					mark("moon")
					c.Clock.freeze(T_MOON)
					c.LC.refresh()
					mark("party")
					c.setEvent(payload({ boost = { kind = "wobble", untilT = T_MOON + 600, byName = "" } }))
					mark("moon-winter")
					c.setEvent(payload({ features = features({ costume = "winter2026" }) }))
					mark("winter")
					c.Clock.freeze(T_WINTER)
					c.LC.refresh()
					mark("quiet-rush-winter")
					c.LC.setQuiet(true)
					c.Clock.freeze(T_WINTER + 175)
					c.LC.refresh()
					mark("rush-winter")
					c.LC.setQuiet(false)
					c.LC.refresh()
					mark("reduced-day")
					c.Prefs._onSettings({ reducedMotion = true })
					c.setEvent(payload())
					c.Clock.freeze(T_DAY)
					c.LC.refresh()
					mark("reduced-moon")
					c.Clock.freeze(T_MOON)
					c.LC.refresh()
					mark("steady")
					c.LC.refresh()
					c.h:step(0.5, 4)
				end)
				c.stop()
				expect(ok and true or err).toBe(true)
				expect(table.concat(normalize(log), "\n")).toBe(
					table.concat(normalize(lines(V13_TRACE)), "\n")
				)
				for _, line in log do
					expect(string.find(line, "LightingStyle", 1, true) == nil).toBe(true)
					expect(string.find(line, "PrioritizeLightingQuality", 1, true) == nil).toBe(true)
				end
				expect(c.L.LightingStyle).toBe(Enum.LightingStyle.Realistic)
				expect(c.L.PrioritizeLightingQuality).toBe(true)
				local s = c.AD.stats()
				expect({ v2 = s.v2, style = s.style, changes = s.changes, current = s.current }).toEqual({
					v2 = false,
					style = false,
					changes = 0,
					current = "moon",
				})
				zeroLog(c.h)
			end
		)

		it("état égal : aucune écriture ni tween de Lighting sur 120 images, aucune pile", function()
			local c = client({ t = T_DAY, event = payload() })
			c.h:step(1 / 60, 10)
			local before = c.AD.stats()
			c.h:step(1 / 60, 120)
			local after = c.AD.stats()
			expect({ writes = after.writes, tweens = after.tweens, changes = after.changes }).toEqual({
				writes = before.writes,
				tweens = before.tweens,
				changes = 0,
			})
			expect(after.v2).toBe(false)
			zeroLog(c.h)
		end)
	end)

	-- =========================================================================================
	describe("AmbienceDirector › Ambience ouvert (pile à priorités)", function()
		it(
			"préréglages complets : v1.3 tirée de Palette, alerte et MEGA, une météo par sorte, costume d'hiver ; nom inconnu → jour",
			function()
				local c = client({ t = T_DAY, event = payload() })
				local h = c.h
				local Palette = h:require("ReplicatedStorage.Shared.Render.Palette")
				local Events = h:require("ReplicatedStorage.Shared.Config.Events")
				local AD = c.AD
				local function same(look, preset, saturation)
					expect({
						clock = look.clockTime,
						ambient = rgb(look.ambient),
						outdoor = rgb(look.outdoorAmbient),
						brightness = look.brightness,
						tint = rgb(look.tint),
						atmosphere = rgb(look.atmosphereColor),
						bloom = look.bloom,
						stars = look.starCount,
						moon = look.moonSize,
						saturation = look.saturation,
					}).toEqual({
						clock = preset.clockTime,
						ambient = rgb(preset.ambient),
						outdoor = rgb(preset.outdoorAmbient),
						brightness = preset.brightness,
						tint = rgb(preset.tint),
						atmosphere = rgb(preset.atmosphereColor),
						bloom = preset.bloom,
						stars = preset.starCount,
						moon = preset.moonSize,
						saturation = saturation or Palette.Effects.saturation,
					})
				end
				for _, name in { "day", "moon", "rush", "party" } do
					same(AD.look(name), Palette.preset(name))
				end
				same(AD.look("rush.quiet"), Palette.overlay(Palette.preset("day"), "rush", Palette.QuietRush))
				same(AD.look("costume.winter2026"), Palette.preset("winter"))
				local day = Palette.preset("day")
				-- alerte et MEGA : Tint (255, 235, 220), Bloom 0,7
				expect(rgb(AD.look("mega").tint)).toEqual({ 255, 235, 220 })
				expect(AD.look("mega").bloom).toBe(0.7)
				-- météos : touches légères sur le jour, une par sorte de Events.Weather.Kinds
				expect(AD.look("weather.sunny").brightness).toBe(day.brightness + 0.3)
				expect(rgb(AD.look("weather.sprinkles").tint)).toEqual({ 255, 240, 250 })
				expect(rgb(AD.look("weather.bubbles").atmosphereColor)).toEqual({ 220, 240, 255 })
				expect(AD.look("weather.rainbow").saturation).toBe(0.3)
				local dayLook = AD.look("day")
				for _, kind in Events.Weather.Kinds do
					local look = AD.look("weather." .. kind)
					local differs = false
					for key, value in look do
						if value ~= dayLook[key] then
							differs = true
						end
					end
					expect({ kind = kind, differs = differs, clock = look.clockTime }).toEqual({
						kind = kind,
						differs = true,
						clock = day.clockTime,
					})
				end
				for _, bad in { "weather.storm", "costume.halloween", "costume.", "night", "", 5, nil } do
					expect(AD.look(bad)).toBe(AD.look("day"))
				end
				zeroLog(h)
			end
		)

		it(
			"chaque paire de couches : la plus haute gagne (Lune > Rush > alerte et MEGA > fêtes > météo > costume > jour), Lighting à l'aspect du gagnant",
			function()
				local c = client({ t = T0, event = layered({}) })
				local ORDER = { "moon", "rush", "mega", "party", "weather", "costume" }
				local NAMES = {
					moon = "moon",
					rush = "rush",
					mega = "mega",
					party = "party",
					weather = "weather.sprinkles",
					costume = "costume.winter2026",
				}
				local function check(on, expected)
					c.setEvent(layered(on))
					c.LC.refresh()
					local keys = {}
					for k in on do
						table.insert(keys, k)
					end
					table.sort(keys)
					local label = table.concat(keys, "+")
					expect({ layers = label, shown = c.LC.current() }).toEqual({
						layers = label,
						shown = expected,
					})
					expectLook(c, expected)
				end
				check({}, "day")
				for i, a in ORDER do
					check({ [a] = true }, NAMES[a])
					for j = i + 1, #ORDER do
						local b = ORDER[j]
						check({ [a] = true, [b] = true }, NAMES[a])
					end
				end
				-- toutes les couches : la Lune
				check(
					{ moon = true, rush = true, mega = true, party = true, weather = true, costume = true },
					"moon"
				)
				expect(c.AD.stats().v2).toBe(true)
				expect(c.AD.stats().style).toBe(true)
				zeroLog(c.h)
			end
		)

		it("nouveau venu avant l'étape 9 : Rush discret (30 %) ; la Lune passe devant", function()
			local c = client({ t = T0, event = layered({ rush = true }), profile = NEWCOMER })
			c.LC.refresh()
			expect(c.LC.current()).toBe("rush.quiet")
			expectLook(c, "rush.quiet")
			c.setEvent(layered({ rush = true, moon = true }))
			expect(c.LC.current()).toBe("moon")
			zeroLog(c.h)
		end)

		it(
			"météo seulement depuis EventState.weather valide et pas finie ; finie à son heure sans message ; jamais en v1.3",
			function()
				local c = client({ t = T0, event = layered({}) })
				local unix = math.floor(T0)
				local KINDS = { "sunny", "sprinkles", "bubbles", "rainbow" }
				for kind, name in KINDS do
					c.setEvent(layered({ weather = kind }))
					expect(c.LC.current()).toBe("weather." .. name)
					expectLook(c, "weather." .. name)
				end
				for i, bad in
					{
						"sunny",
						5,
						{},
						{ kind = 0, endsAt = unix + 60 },
						{ kind = 5, endsAt = unix + 60 },
						{ kind = 2.5, endsAt = unix + 60 },
						{ kind = 0 / 0, endsAt = unix + 60 },
						{ kind = "storm", endsAt = unix + 60 },
						{ kind = 1, endsAt = unix },
						{ kind = 1, endsAt = unix - 1 },
						{ kind = 1, endsAt = unix + 100000 },
						{ kind = 1, endsAt = 0 / 0 },
						{ kind = 1, endsAt = math.huge },
						{ kind = 1, endsAt = "soon" },
					}
				do
					local p = layered({})
					p.weather = bad
					c.setEvent(p)
					expect({ case = i, shown = c.LC.current() }).toEqual({ case = i, shown = "day" })
				end
				-- fenêtre qui finit dans 10 s : la météo s'arrête à son heure, sans nouveau message
				local p = layered({})
				p.weather = { kind = 3, endsAt = unix + 10 }
				c.setEvent(p)
				expect(c.LC.current()).toBe("weather.bubbles")
				c.Clock.freeze(T0 + 10)
				c.LC.refresh()
				expect(c.LC.current()).toBe("day")
				-- Ambience coupé : la météo n'existe pas en v1.3
				c.setEvent(layered({ weather = 1 }, T0 + 10, true))
				expect(c.LC.current()).toBe("day")
				expect(c.AD.stats().v2).toBe(false)
				zeroLog(c.h)
			end
		)

		it(
			"transitions : 2 s, 4 s vers ou depuis la Lune et une météo ; Mouvement réduit : 4 s, tout interpolé (ciel compris), aucune écriture directe",
			function()
				local c = client({ t = T0, event = layered({}), record = true })
				local start = #c.tweens
				local function lightingTimes(from)
					local out = {}
					for i = from + 1, #c.tweens do
						if c.tweens[i].name == "Lighting" then
							table.insert(out, c.tweens[i].time)
						end
					end
					return out
				end
				c.setEvent(layered({ rush = true }))
				c.setEvent(layered({ rush = true, moon = true }))
				expect(c.L.ClockTime).toBe(24) -- 14,5 → 24 (minuit) : jamais à reculons
				c.setEvent(layered({}))
				c.setEvent(layered({ weather = true }))
				c.setEvent(layered({ weather = true, mega = true }))
				c.setEvent(layered({ party = true }))
				c.setEvent(layered({}))
				expect(lightingTimes(start)).toEqual({ 2, 4, 4, 4, 4, 2, 2 })
				-- Mouvement réduit : fondu de 4 s, chaque propriété interpolée (ciel compris), aucune
				-- écriture directe
				c.Prefs._onSettings({ reducedMotion = true })
				local mark = #c.tweens
				local writes = c.AD.stats().writes
				c.setEvent(layered({ rush = true }))
				c.setEvent(layered({ rush = true, moon = true }))
				c.setEvent(layered({}))
				c.stop()
				expect(lightingTimes(mark)).toEqual({ 4, 4, 4 })
				expect(c.AD.stats().writes).toBe(writes)
				local per = {}
				for i = mark + 1, #c.tweens do
					local t = c.tweens[i]
					per[t.name] = (per[t.name] or 0) + 1
					expect({ name = t.name, time = t.time }).toEqual({ name = t.name, time = 4 })
				end
				expect(per).toEqual({
					Lighting = 3,
					SquishyAtmosphere = 3,
					SquishyColor = 3,
					SquishyBloom = 3,
					SquishySky = 3,
				})
				zeroLog(c.h)
			end
		)

		it(
			"éclairage unifié : Soft et false tant qu'Ambience est ouvert ; valeurs de la place rendues quand il est coupé en direct, reprises quand il revient ; place déjà en Soft : rien écrit",
			function()
				local Soft, Realistic = Enum.LightingStyle.Soft, Enum.LightingStyle.Realistic
				local c =
					client({ t = T_DAY, event = payload(), place = { style = Realistic, quality = true } })
				expect(c.L.LightingStyle).toBe(Realistic)
				expect(c.L.PrioritizeLightingQuality).toBe(true)
				c.setEvent(payload({ features = features({ ambience = true }) }))
				expect(c.L.LightingStyle).toBe(Soft)
				expect(c.L.PrioritizeLightingQuality).toBe(false)
				expect(c.AD.stats().style).toBe(true)
				c.setEvent(payload())
				expect(c.L.LightingStyle).toBe(Realistic)
				expect(c.L.PrioritizeLightingQuality).toBe(true)
				expect(c.AD.stats().style).toBe(false)
				c.setEvent(payload({ features = features({ ambience = true }) }))
				expect(c.L.LightingStyle).toBe(Soft)
				expect(c.L.PrioritizeLightingQuality).toBe(false)
				zeroLog(c.h)
				-- place réglée à l'étape I (Soft, false) : le directeur n'écrit ni l'un ni l'autre
				local c2 = client({
					t = T_DAY,
					event = payload(),
					place = { style = Soft, quality = false },
					record = true,
				})
				c2.setEvent(payload({ features = features({ ambience = true }) }))
				c2.setEvent(payload())
				c2.stop()
				for _, line in c2.log do
					expect(string.find(line, "LightingStyle", 1, true) == nil).toBe(true)
					expect(string.find(line, "PrioritizeLightingQuality", 1, true) == nil).toBe(true)
				end
				expect(c2.L.LightingStyle).toBe(Soft)
				expect(c2.L.PrioritizeLightingQuality).toBe(false)
				zeroLog(c2.h)
			end
		)

		it(
			"coupé en direct : v1.3 exacte (même éclairage qu'un client resté en v1.3), tween du ciel de la pile arrêté ; rouvert : la pile revient",
			function()
				local place = { style = Enum.LightingStyle.Realistic, quality = true }
				local layers = { weather = 4, costume = true }
				-- A : client resté en v1.3 (hiver ; la météo n'existe pas en v1.3)
				local a = client({ t = T0, event = layered(layers, T0, true), place = place })
				expect(a.LC.current()).toBe("winter")
				-- B : pile ouverte (costume), puis météo arc-en-ciel (tweens en cours), puis coupée
				local b =
					client({ t = T0, event = layered({ costume = true }), place = place, record = true })
				expect(b.LC.current()).toBe("costume.winter2026")
				b.setRaw(layered(layers))
				b.LC.refresh()
				expect(b.LC.current()).toBe("weather.rainbow")
				expect(b.L.SquishyColor.Saturation).toBe(0.3)
				local skyTween
				for _, t in b.tweens do
					if t.name == "SquishySky" then
						skyTween = t.tween
					end
				end
				expect(skyTween ~= nil).toBe(true)
				expect(skyTween.PlaybackState).toBe(Enum.PlaybackState.Playing)
				b.setRaw(layered(layers, T0, true))
				b.LC.refresh()
				b.stop()
				expect(b.LC.current()).toBe("winter")
				expect(skyTween.PlaybackState).toBe(Enum.PlaybackState.Cancelled)
				b.h:settle(2)
				expect(snapshot(b)).toEqual(snapshot(a))
				expect(b.AD.stats().v2).toBe(false)
				expect(b.AD.stats().style).toBe(false)
				-- rouvert en direct : la pile revient
				b.setEvent(layered(layers))
				expect(b.LC.current()).toBe("weather.rainbow")
				expect(b.AD.stats().v2).toBe(true)
				expect(b.L.LightingStyle).toBe(Enum.LightingStyle.Soft)
				zeroLog(a.h)
				zeroLog(b.h)
			end
		)

		it("pile égale : aucune écriture ni tween sur 120 images (aucun travail par image)", function()
			local c = client({ t = T0, event = layered({ weather = true, costume = true }) })
			c.h:step(1 / 60, 10)
			local before = c.AD.stats()
			expect(before.current).toBe("weather.sprinkles")
			c.h:step(1 / 60, 120)
			c.LC.refresh()
			local after = c.AD.stats()
			expect({ writes = after.writes, tweens = after.tweens, changes = after.changes }).toEqual({
				writes = before.writes,
				tweens = before.tweens,
				changes = before.changes,
			})
			zeroLog(c.h)
		end)

		it("EventState hostile avec Ambience : jour, sans trace ; ambience non booléen : v1.3", function()
			local c = client({ t = T_DAY, event = payload({ features = features({ ambience = true }) }) })
			for i, bad in
				{
					{ features = { ambience = true } },
					{
						features = {
							ambience = true,
							megaSquish = "yes",
							jellyMoon = 1,
							boopRush = {},
							costume = 5,
						},
					},
					{
						features = features({ ambience = true, boopRush = "off" }),
						mega = "x",
						weather = "sunny",
						boost = 7,
						moon = { active = "yes" },
					},
					{
						features = features({ ambience = true, boopRush = "off" }),
						mega = { phase = "press", endsAt = 0 / 0 },
						weather = { kind = 0 / 0, endsAt = math.huge },
					},
					{
						features = features({ ambience = true, boopRush = "off" }),
						mega = { phase = "burst", endsAt = -math.huge },
						weather = { kind = "storm", endsAt = T_DAY + 60 },
						gauge = { partyUntil = "soon" },
					},
					{
						features = features({ ambience = true, boopRush = "off" }),
						mega = { phase = 5, endsAt = T_DAY + 60 },
						weather = { kind = 9, endsAt = T_DAY + 60 },
						boost = { kind = 5, untilT = math.huge },
					},
					{
						features = features({ ambience = true, boopRush = "off", megaSquish = false }),
						mega = mega("press", T_DAY + 30),
					},
					{
						features = features({ ambience = true, boopRush = "off" }),
						mega = mega("warn", T_DAY - 10),
					},
				}
			do
				c.setEvent(bad)
				c.LC.refresh()
				expect({ case = i, shown = c.LC.current() }).toEqual({ case = i, shown = "day" })
			end
			c.WSC.EventChanged:Fire(nil)
			c.WSC.EventChanged:Fire("garbage")
			c.h:settle(1)
			local c2 = client({ t = T_DAY, event = payload({ features = features({ ambience = "yes" }) }) })
			c2.LC.refresh()
			expect(c2.AD.stats().v2).toBe(false)
			expect(c2.AD.stats().style).toBe(false)
			zeroLog(c.h)
			zeroLog(c2.h)
		end)

		it(
			"vrai client (Main.client) : EventState reçu par le réseau, la clé ambience passe telle quelle",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				h:boot()
				local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
				h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", Schema.defaults())
				h:step(1 / 60, 20)
				local WSC = h:require(base .. "Controllers.WorldStateController")
				local LC = h:require(base .. "Controllers.LightingController")
				local AD = h:require(base .. "Render.AmbienceDirector")
				h:fireClient("ReplicatedStorage.Remotes.EventState", layered({ party = true }))
				h:step(1 / 60, 40)
				expect(WSC.event().features.ambience).toBe(true)
				expect(LC.current()).toBe("party")
				expect(AD.stats().v2).toBe(true)
				-- interrupteur recoupé : la clé disparaît, la v1.3 reprend
				h:fireClient("ReplicatedStorage.Remotes.EventState", layered({ party = true }, T0, true))
				h:step(1 / 60, 40)
				expect(WSC.event().features.ambience).toBeNil()
				expect(LC.current()).toBe("party")
				expect(AD.stats().v2).toBe(false)
				zeroLog(h)
			end
		)

		it("API Roblox valide (ApiAudit) : éclairage unifié, tweens du ciel et de la saturation", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = client({ t = T0, event = layered({ costume = true }) })
				c.setEvent(layered({ weather = 4 }))
				c.setEvent(layered({ moon = true }))
				c.Prefs._onSettings({ reducedMotion = true })
				c.setEvent(layered({ mega = true }))
				c.setEvent(layered({}, T0, true))
				c.h:step(0.5, 4)
				zeroLog(c.h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)

	-- =========================================================================================
	describe("AmbienceDirector › serveur (INT-B4-AMBIENCE)", function()
		local V13_FEATURES = "boopRush,clips,costume,diagnostics,gauge,golden,jellyMoon,megaSquish"

		-- clés triées ; `features.v2` (liste des interrupteurs v2.0 vus par le client, présente dès qu'un
		-- interrupteur v2.0 est ouvert : lot I, étape 2, journal I-19) est mise à part et vérifiée seule
		-- (leçon B3-82)
		local function keysOf(t)
			local keys = {}
			for k in t do
				if k ~= "v2" then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
			return table.concat(keys, ",")
		end

		local function deepEqual(x, y)
			if x == y or (x ~= x and y ~= y) then
				return true
			end
			if type(x) ~= "table" or type(y) ~= "table" then
				return false
			end
			for k, v in x do
				if not deepEqual(v, y[k]) then
					return false
				end
			end
			for k in y do
				if x[k] == nil then
					return false
				end
			end
			return true
		end

		local function lastState(w, p)
			local list = w.h:sentTo(p, "EventState")
			return list[#list] and list[#list][1]
		end

		it(
			"features.ambience présent seulement interrupteur ouvert ; renvoyé à tous après « feature Ambience=… » d'un administrateur ; recoupé : charge égale à celle d'un serveur témoin",
			function()
				local t0 = 1800000000 + 120
				-- lot I, étape 5 : Ambience est ouvert au lancement ; ce cas prouve le chemin coupé puis
				-- rouvert en direct (LiveOps), donc les deux serveurs partent avec Ambience coupé (le chemin
				-- de lancement est couvert par les cas « client » de ce fichier et par Arrival_quiet)
				local CUT = { Ambience = false }
				local wA = Brains.boot(Harness, { t0 = t0, preset = CUT })
				Brains.join(wA, 1)
				local wB = Brains.boot(Harness, { t0 = t0, preset = CUT })
				local pB = Brains.join(wB, 1)
				local qB = Brains.join(wB, 2)
				wB.meta.admins[1] = true
				Brains.frames(wA, 2)
				Brains.frames(wB, 2)
				expect(wB.Features.get("Ambience")).toBe(false)
				expect(keysOf(lastState(wB, pB).features)).toBe(V13_FEATURES)
				expect(lastState(wB, pB).features.ambience).toBeNil()
				local before = #wB.h:sentTo(qB, "EventState")
				wB.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", pB, "feature", "Ambience=true")
				expect(#wB.h:sentTo(qB, "EventState")).toBe(before + 1)
				expect(lastState(wB, qB).features.ambience).toBe(true)
				expect(lastState(wB, pB).features.ambience).toBe(true)
				expect(keysOf(lastState(wB, qB).features)).toBe("ambience," .. V13_FEATURES)
				wB.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", pB, "feature", "Ambience=false")
				expect(#wB.h:sentTo(qB, "EventState")).toBe(before + 2)
				expect(lastState(wB, qB).features.ambience).toBeNil()
				expect(keysOf(lastState(wB, qB).features)).toBe(V13_FEATURES)
				-- même charge que le témoin (même instant)
				Brains.frames(wA, 1)
				Brains.frames(wB, 1)
				expect(wA.Clock.now()).toBe(wB.Clock.now())
				local sA, sB = wA.Event.state(), wB.Event.state()
				expect(keysOf(sA.features)).toBe(V13_FEATURES)
				expect(deepEqual(sA.features, sB.features)).toBe(true)
				-- features.v2 : la même chez le témoin et chez B (Ambience n'y change rien d'autre)
				expect(deepEqual(sA.features.v2, sB.features.v2)).toBe(true)
				expect(keysOf(sA)).toBe(keysOf(sB))
				expect(table.concat(Brains.problems(wA), "\n")).toBe("")
				expect(table.concat(Brains.problems(wB), "\n")).toBe("")
			end
		)
	end)
end
