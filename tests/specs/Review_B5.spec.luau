--!nocheck
-- Relecture indépendante du lot B5 (docs/04 §27.12, journal B5-62 et suivants) : défauts trouvés par la
-- relecture, chacun vu ROUGE sur le code du lot avant sa correction, puis vert. Client complet console
-- (harnais TvAudit / UpgradeScreen), horloge figée, zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local DONE = { step = 11, done = true, demoDone = true }

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local FLAGS = {}
	for k, v in UpgradeScreen.V2_ALL do
		FLAGS[k] = v
	end
	FLAGS.PhotoMode = true
	FLAGS.Personalities = true

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "",
			hidden = true,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = 1800000000 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
	end

	local function sq(species)
		return { s = species, m = 0, st = 0, z = 50, zg = 0, at = "pen", bf = 0, o = "", ready = 0 }
	end

	-- Client console, profil v2, mon ranch 1 avec trois squishies dans l'enclos, moi à côté d'eux
	local function client()
		local c = S.client({ profile = { version = 2, onboarding = DONE } })
		local me = c.h.localPlayer.UserId
		c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = { ["1"] = ranch(1, me) },
			squishies = { ["1"] = { a = sq(1), b = sq(2), c = sq(5) } },
		})
		c.h:settle(1)
		S.event(c, FLAGS)
		c.Cam = TvAudit.mod(c.h, "Controllers.CameraController")
		c.P = TvAudit.mod(c.h, "World.Personality")
		c.WL = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		c.camera = c.h.workspace.CurrentCamera
		local pen = c.WL.penSlot(1, 1)
		c.h:moveTo(c.h.localPlayer, pen + Vector3.new(0, 3, 4))
		c.camera.CameraType = Enum.CameraType.Custom
		c.camera.CFrame = CFrame.lookAt(pen + Vector3.new(0, 10, -12), pen)
		S.run(c, 0.5)
		return c
	end

	local function play(c, seconds, dt)
		dt = dt or 0.25
		for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
			c.Clock.advance(dt)
			c.h:step(dt, 1)
		end
		c.h:settle(1)
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	describe("Review_B5 › mode photo et personnalités", function()
		it(
			"B5-62 : le mode photo n'est pas « joueur immobile » : les squishies ne s'endorment pas pendant une photo (témoin : hors mode photo, ils s'endorment après 60 s)",
			function()
				-- témoin : immobile 65 s hors mode photo, ceux à 15 studs s'endorment
				local w = client()
				expect(w.P.active()).toBe(true)
				play(w, 65)
				expect(w.P.stats().sleepers > 0).toBe(true)
				clean(w)
				-- mode photo : le personnage ne bouge pas (sticks pris par la caméra), le joueur joue
				local c = client()
				expect(c.Cam.photo(true)).toBe(true)
				play(c, 65)
				expect(c.Cam.photoOn()).toBe(true)
				expect(c.P.stats().sleepers).toBe(0)
				-- après la photo, l'horloge d'inactivité repart de la sortie (pas d'endormissement immédiat)
				c.Cam.photo(false)
				play(c, 30)
				expect(c.P.stats().sleepers).toBe(0)
				play(c, 35)
				expect(c.P.stats().sleepers > 0).toBe(true)
				clean(c)
			end
		)
	end)
	-- Client léger : miroir puis VFXController (qui démarre WeatherFx et Fete) AVANT tout EventState,
	-- comme sur un vrai serveur (le profil se charge après le démarrage du client)
	local T0 = 1796724120
	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local function lightClient()
		local h = T.Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:require(CLIENT .. "Util.Prefs").Init()
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local c = {
			h = h,
			Clock = Clock,
			WX = h:require(CLIENT .. "World.WeatherFx"),
			FE = h:require(CLIENT .. "World.Fete"),
			sounds = {},
			toasts = {},
		}
		c.WX._configure({
			play = function(name)
				table.insert(c.sounds, name)
			end,
		})
		c.FE._configure({
			play = function(name)
				table.insert(c.sounds, name)
			end,
			toast = function(text)
				table.insert(c.toasts, text)
			end,
		})
		local VFX = h:require(CLIENT .. "Controllers.VFXController")
		VFX.Init()
		VFX.Start()
		function c.event(over)
			local ev = UpgradeScreen.eventState(nil)
			for key, value in over or {} do
				ev[key] = value
			end
			h:fireClient("ReplicatedStorage.Remotes.EventState", ev)
			h:settle(1)
		end
		return c
	end

	describe("Review_B5 › arrivée pendant une fête ou une météo", function()
		it(
			"B5-63 : le premier EventState reçu APRÈS le démarrage (cas réel) ne joue ni le message « Place en fête » ni FeteLevel ni WeatherStart ; une montée ensuite les joue",
			function()
				local c = lightClient()
				expect(c.FE.level()).toBe(0)
				-- arrivée : fête au niveau 3 et fenêtre de météo déjà en cours
				c.event({ fete = { level = 3 }, weather = { kind = 2, endsAt = T0 + 200 } })
				expect(c.FE.level()).toBe(3)
				expect(c.WX.kind()).toBe("sprinkles")
				expect(c.toasts).toEqual({})
				expect(c.sounds).toEqual({})
				-- en partie : le niveau monte, une nouvelle fenêtre commence
				c.event({ fete = { level = 4 }, weather = { kind = 3, endsAt = T0 + 250 } })
				expect(#c.toasts).toBe(1)
				expect(table.find(c.sounds, "FeteLevel") ~= nil or table.find(c.sounds, "LevelUp") ~= nil).toBe(
					true
				)
				expect(table.find(c.sounds, "WeatherStart") ~= nil or table.find(c.sounds, "Whoosh") ~= nil).toBe(
					true
				)
				expect(table.concat(c.h.errors, "\n")).toBe("")
				expect(table.concat(c.h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
