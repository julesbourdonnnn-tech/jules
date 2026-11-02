--!nocheck
-- Fix_integration_client (intégration client) : notes d'intégration appliquées côté client, chacune
-- avec son test.
--   * INT-AUDIO : AudioController.setMusic (Music, MusicMoon, MusicRush, fondu croisé), volume en dB,
--     réglage « Musique » coupé = silence ; LightingController choisit la piste (Rush après la sirène,
--     −12 dB pour un nouveau avant l'étape 9) ; Banners joue RushSiren / MegaWarn / MoonStart.
--   * note client-hud n° 1 : Toast.message passe par la file du message central (Toast.router), un
--     message à la fois ; Toast.show reste immédiat.
--   * INT-CW-1 : □ sur le MEGA → VFXController.megaPress(tClient) ; INT-CW-2 : attribut SplorchFilm ;
--     INT-CW-3 : flèche vers le spectacle en Mouvement réduit ; note meta n° 5 : sonde « reduced » ;
--     INT-CWR-5 : fenêtre ouverte avant PromptController.Start connue ; libellés qui suivent la largeur
--     de la touche du clavier (« Enter »).
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T_DAY = 1796724120 -- mardi 8/12/2026 10:02 UTC (rien) ; sirène à T_DAY + 175
	local DONE = { step = 11, done = true, demoDone = true }

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function features()
		return {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
	end

	local function eventState(over)
		local p = {
			rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
			mega = {
				phase = "idle",
				index = 0,
				landsAt = 0,
				endsAt = 0,
				target = 0,
				points = 0,
				species = 1,
				moon = false,
				result = "",
			},
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

	-- Pistes de musique avec un ID (le jeu les a vides : muettes) et un fondu court
	local function musicSounds(h)
		local S = h:require("ReplicatedStorage.Shared.Config.Sounds")
		for key, id in
			{ Music = "rbxassetid://1837849285", MusicMoon = "rbxassetid://1", MusicRush = "rbxassetid://2" }
		do
			S[key] = {
				id = id,
				volume = 0.3,
				fade = 0.05,
				maxLength = 4,
				perFrame = 3,
				concurrent = 4,
			}
		end
	end

	local function tick(h, Clock, seconds)
		local n = math.ceil(seconds / 0.1)
		for _ = 1, n do
			Clock.advance(0.1)
			h:step(0.1, 1)
		end
		h:settle(2)
	end

	-- =========================================================================================
	describe("INT-AUDIO › AudioController.setMusic et LightingController", function()
		it(
			"une seule piste à la fois, fondu croisé, dB, réglage coupé ; play() ne joue jamais une musique",
			function()
				local h =
					TvAudit.client({ profile = { onboarding = DONE }, before = musicSounds, now = T_DAY })
				local Audio = TvAudit.mod(h, "Controllers.AudioController")
				local folder = h.game:GetService("SoundService").GameSounds
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				tick(h, Clock, 1)
				expect(folder.Music.Playing).toBe(true)
				expect(folder.MusicRush.Playing).toBe(false)
				expect(folder.Music.Looped and folder.MusicRush.Looped and folder.MusicMoon.Looped).toBe(true)
				Audio.setMusic("MusicRush")
				tick(h, Clock, 0.5)
				task.wait(0.15) -- fin du fondu de sortie (task.delay)
				h:settle(2)
				expect(folder.MusicRush.Playing).toBe(true)
				expect(folder.Music.Playing).toBe(false)
				-- −12 dB
				Audio.setMusicVolumeDb(-12)
				h:settle(2)
				expect(folder.MusicRush.Volume).toBeNear(0.3 * 10 ^ (-12 / 20), 1e-3)
				local key, gain = Audio.music()
				expect(key).toBe("MusicRush")
				expect(gain).toBeNear(10 ^ (-12 / 20), 1e-6)
				-- valeurs absurdes : 0 dB ; clé inconnue : musique de jour
				Audio.setMusicVolumeDb(0 / 0)
				Audio.setMusic("Nope")
				h:settle(2)
				expect(select(1, Audio.music())).toBe("Music")
				expect(select(2, Audio.music())).toBe(1)
				-- effets : jamais une musique
				local before = #h.game:GetService("SoundService"):GetChildren()
				Audio.play("MusicRush")
				Audio.play("MusicMoon")
				expect(#h.game:GetService("SoundService"):GetChildren()).toBe(before)
				-- réglage « Musique » coupé : silence tout de suite, même en pleine transition
				Audio.setMusic("MusicMoon")
				Audio.setMusicEnabled(false)
				h:settle(2)
				for _, name in { "Music", "MusicMoon", "MusicRush" } do
					expect({ name = name, playing = folder[name].Playing }).toEqual({
						name = name,
						playing = false,
					})
				end
				Audio.setMusicEnabled(true)
				h:settle(2)
				expect(folder.MusicMoon.Playing).toBe(true)
				clean(h)
			end
		)

		it(
			"LightingController : Music → (sirène : Music) → MusicRush pendant le Rush ; nouveau : −12 dB",
			function()
				for _, case in
					{
						{ step = DONE, db = 0 },
						{ step = { step = 3, done = false, demoDone = false }, db = -12 },
					}
				do
					local h = TvAudit.client({
						profile = { onboarding = case.step },
						before = musicSounds,
						now = T_DAY,
					})
					local Audio = TvAudit.mod(h, "Controllers.AudioController")
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					h:fireClient(REMOTES .. "EventState", eventState())
					tick(h, Clock, 1)
					expect(select(1, Audio.music())).toBe("Music")
					Clock.freeze(T_DAY + 176) -- sirène
					tick(h, Clock, 1)
					expect(select(1, Audio.music())).toBe("Music")
					Clock.freeze(T_DAY + 190) -- Rush en cours
					tick(h, Clock, 1)
					local key, gain = Audio.music()
					expect(key).toBe("MusicRush")
					expect(gain).toBeNear(10 ^ (case.db / 20), 1e-6)
					-- interrupteur coupé en direct : plus de musique du Rush
					local ev = eventState()
					ev.features.boopRush = "off"
					h:fireClient(REMOTES .. "EventState", ev)
					tick(h, Clock, 1)
					expect(select(1, Audio.music())).toBe("Music")
					clean(h)
				end
			end
		)

		it(
			"Banners : RushSiren à la sirène, MegaWarn à l'alerte ; rien pour un nouveau avant l'étape 9",
			function()
				for _, case in
					{
						{ step = DONE, want = true },
						{ step = { step = 3, done = false, demoDone = false }, want = false },
					}
				do
					local h = TvAudit.client({ profile = { onboarding = case.step }, now = T_DAY })
					local Audio = TvAudit.mod(h, "Controllers.AudioController")
					local played = {}
					local orig = Audio.play
					Audio.play = function(name, ...)
						played[name] = true
						return orig(name, ...)
					end
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
					h:fireClient(REMOTES .. "EventState", eventState())
					h:settle(2)
					Clock.freeze(EventClock.rush(T_DAY).sirenAt + 0.5)
					tick(h, Clock, 1)
					local mega = EventClock.mega(Clock.now())
					Clock.freeze(mega.warnAt + 0.5)
					tick(h, Clock, 1)
					expect({ siren = played.RushSiren == true, mega = played.MegaWarn == true }).toEqual({
						siren = case.want,
						mega = case.want,
					})
					clean(h)
				end
			end
		)
	end)

	-- =========================================================================================
	describe("Note client-hud n° 1 › Toast.message passe par la file du HUD", function()
		it(
			"deux messages d'un panneau : un seul à l'écran, le second attend ; Toast.show reste immédiat",
			function()
				local h = TvAudit.client({ profile = { onboarding = DONE } })
				local Toast = TvAudit.mod(h, "UI.Toast")
				local Messages = TvAudit.mod(h, "UI.Hud.Messages")
				expect(Toast.router ~= nil).toBe(true)
				Messages._reset()
				Toast.message("Pens full!", "warning")
				Toast.message("Nothing to fuse!", "info")
				local stack = h.localPlayer.PlayerGui.Toasts.Safe.Stack
				local function count()
					local n = 0
					for _, c in stack:GetChildren() do
						if c.Name == "Toast" then
							n += 1
						end
					end
					return n
				end
				expect(count()).toBe(1)
				expect(Messages.pending()).toBe(1)
				expect(Messages.last().text).toBe("Pens full!")
				-- un routeur qui lève : le message s'affiche quand même
				Toast.router = function()
					error("panne")
				end
				Toast.message("Fallback", "info")
				expect(count()).toBe(2)
				Toast.router = Messages.push
				clean(h)
			end
		)
	end)

	-- =========================================================================================
	describe("Notes client-world", function()
		it(
			"INT-CW-1 : □ sur le MEGA envoie MegaPress puis appelle VFXController.megaPress(tClient)",
			function()
				local h = TvAudit.client({ profile = { onboarding = DONE } })
				local PromptC = TvAudit.mod(h, "Controllers.PromptController")
				local VFX = TvAudit.mod(h, "Controllers.VFXController")
				PromptC.current = function()
					return { kind = "mega", primary = "press", ready = true, position = Vector3.new(0, 3, 0) }
				end
				local calls = {}
				VFX.megaPress = function(t)
					table.insert(calls, t)
					return false
				end
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonX)
				h:settle(2)
				local sent = TvAudit.sent(h, "MegaPress")
				expect(#sent).toBe(1)
				expect(#calls).toBe(1)
				expect(calls[1]).toBe(sent[1][1])
				clean(h)
			end
		)

		it(
			"INT-CW-3 : mon Grand Splorch en Mouvement réduit → flèche « splorch » jusqu'à endsAt",
			function()
				local h = TvAudit.client({
					profile = { onboarding = DONE, settings = { reducedMotion = true, lang = "en" } },
				})
				local Prefs = TvAudit.mod(h, "Util.Prefs")
				Prefs.reducedMotion = function()
					return true
				end
				local FX = TvAudit.mod(h, "UI.ScreenFX")
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				local requests = {}
				local orig = FX.arrow
				FX.arrow = function(id, pos, kind)
					if id == "splorch" then
						table.insert(requests, pos ~= nil)
					end
					return orig(id, pos, kind)
				end
				local now = Clock.now()
				local data = {
					userId = 1,
					level = 1,
					flyer = "1",
					startedAt = now,
					burstAt = now + 5,
					endsAt = now + 8,
					short = false,
				}
				-- celui d'un autre, ou en version courte : rien
				local short = table.clone(data)
				short.short = true
				h:fireClient(REMOTES .. "Celebrate", { kind = "splorch", data = short })
				local other = table.clone(data)
				other.userId = 2
				h:fireClient(REMOTES .. "Celebrate", { kind = "splorch", data = other })
				h:settle(2)
				expect(#requests).toBe(0)
				h:fireClient(REMOTES .. "Celebrate", { kind = "splorch", data = data })
				h:settle(2)
				expect(requests).toEqual({ true })
				Clock.advance(9)
				h:step(1 / 60, 2)
				h:settle(2)
				expect(requests).toEqual({ true, false })
				clean(h)
			end
		)

		it("note meta n° 5 : QualityController pose la sonde « reduced » d'ErrorReporter", function()
			local h = TvAudit.client({ profile = { onboarding = DONE } })
			local ER = TvAudit.mod(h, "Controllers.ErrorReporter")
			local QC = TvAudit.mod(h, "Controllers.QualityController")
			local probes = {}
			local orig = ER.setProbe
			ER.setProbe = function(name, fn)
				probes[name] = fn
				return orig(name, fn)
			end
			QC._stop()
			QC._reset()
			QC.Start()
			expect(probes.reduced).toBe(QC.reduced)
			clean(h)
		end)

		it(
			"INT-CWR-5 : une fenêtre ouverte avant PromptController.Start est connue (aucune invite)",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local PromptC = h:require(CLIENT .. "Controllers.PromptController")
				local FocusGuard = h:require(CLIENT .. "UI.FocusGuard")
				local names = { "return" }
				FocusGuard.names = function()
					return names
				end
				PromptC.Start()
				expect(PromptC.current()).toBeNil()
				clean(h)
			end
		)

		it("INT-CW-2 : le choix « Filmer » part avec GrandSplorch dans l'attribut SplorchFilm", function()
			local NOW = 1800000000
			local h = TvAudit.client({
				now = NOW,
				profile = {
					onboarding = DONE,
					squishies = {
						best = TvAudit.squishy(1, { z = 30000, bf = 1 }),
						flyer = TvAudit.squishy(5, { z = 20000 }),
					},
					growth = { G = 0, g = 1, t = NOW },
					R = 0,
				},
			})
			local PC = TvAudit.mod(h, "UI.PanelController")
			local SP = TvAudit.mod(h, "UI.Panels.SplorchPreview")
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			local function holdFor(seconds)
				TvAudit.tick(h, 0.5)
				h.game.GuiService.SelectedObject = PC.window("SplorchPreview").Body.Main.Hold
				h:settle(1)
				Gamepad.press(h, Enum.KeyCode.ButtonA)
				Clock.advance(seconds)
				h:step(1 / 60, 2)
				Gamepad.release(h, Enum.KeyCode.ButtonA)
				h:settle(2)
			end
			PC.open("SplorchPreview")
			expect(h.localPlayer:GetAttribute("SplorchFilm")).toBeNil()
			-- case Filmer décochée
			local m = PC.window("SplorchPreview").Body.Main
			TvAudit.tick(h, 0.5)
			h.game.GuiService.SelectedObject = m.Film.Toggle
			Gamepad.tap(h, Enum.KeyCode.ButtonA)
			expect(SP._state().film).toBe(false)
			holdFor(1.6)
			local sent = TvAudit.sent(h, "GrandSplorch")
			expect(#sent).toBe(1)
			expect(sent[1][1]).toBe(false)
			expect(h.localPlayer:GetAttribute("SplorchFilm")).toBe(false)
			clean(h)
		end)
	end)

	-- =========================================================================================
	describe("Clavier : une touche longue (« Enter ») ne recouvre jamais le libellé", function()
		it("bouton maintenu (Widgets.hold) et « Super ! » de l'écran de retour", function()
			local h = TvAudit.client({ profile = { onboarding = DONE }, console = false })
			h.lastInputType = Enum.UserInputType.Keyboard
			h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
			h:settle(2)
			local Widgets = TvAudit.mod(h, "UI.Panels.Widgets")
			local screen = h.globals.Instance.new("ScreenGui")
			screen.Parent = h.localPlayer.PlayerGui
			local hold = Widgets.hold({
				parent = screen,
				name = "HoldTest",
				size = roblox.UDim2.fromOffset(640, 96),
				position = roblox.UDim2.fromOffset(200, 200),
				key = "panel.splorch.hold",
				duration = 1.5,
				onComplete = function() end,
			})
			h:settle(2)
			local b = hold.button
			local glyph, label = nil, b:FindFirstChild("Label")
			for _, d in b:GetChildren() do
				if d:GetAttribute("GlyphMode") ~= nil then
					glyph = d
				end
			end
			expect(glyph ~= nil and label ~= nil).toBe(true)
			expect(glyph:GetAttribute("GlyphMode")).toBe("text")
			Layout.apply(h)
			local gr = Layout.rect(glyph)
			local lr = Layout.rect(label)
			expect(lr.x >= gr.x + gr.w).toBe(true)
			clean(h)
		end)
	end)
end
