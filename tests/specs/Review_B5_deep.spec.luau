--!nocheck
-- Relecture approfondie du lot B5 avant l'intégration (docs/04 §27.12, journal B5-66 et suivants) :
-- défauts trouvés en relisant ligne par ligne le code du client du lot B5, chacun vu ROUGE sur 3636608
-- avant sa correction, puis vert. Clients légers du harnais, horloge figée, zéro trace.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local T0 = 1796724120
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local REMOTES = "ReplicatedStorage.Remotes."

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 12,
			fame = 0,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 1, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
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

	local function folder(parent, name, class)
		local f = parent:FindFirstChild(name)
		if f == nil then
			f = MockInstance.new(class or "Folder")
			f.Name = name
			f.Parent = parent
		end
		return f
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- =========================================================================================
	-- B5-66 : caméra laissée scriptée quand un Grand Splorch arrive pendant MA Jelly Ascend
	-- =========================================================================================
	describe("Review_B5_deep › bail de caméra « show » partagé", function()
		it(
			"B5-66 : un travelling du Grand Splorch qui arrive pendant le travelling de MA Jelly Ascend ne laisse jamais la caméra scriptée (un seul travelling, le plus récent ; caméra rendue à la fin)",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				local Prefs = h:require(CLIENT .. "Util.Prefs")
				Prefs.Init()
				Prefs.reducedMotion = function()
					return false
				end
				local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
				local me = h.localPlayer.UserId
				local ev = { features = { v2 = { JellyAscend = true } } }
				WSC.event = function()
					return ev
				end
				WSC.mySlot = function()
					return 3
				end
				WSC.ranch = function(slot)
					return if slot == 3 then { userId = me } else nil
				end
				local Cam = h:require(CLIENT .. "Controllers.CameraController")
				Cam.Init()
				Cam.Start()
				local camera = h.workspace.CurrentCamera
				camera.CameraType = Enum.CameraType.Custom
				local start = CFrame.new(1, 20, 3)
				camera.CFrame = start
				local function run(seconds)
					local dt = 1 / 30
					for _ = 1, math.floor(seconds / dt + 0.5) do
						Clock.advance(dt)
						Cam._step(dt)
					end
				end
				-- MA Jelly Ascend (10 s), puis un Grand Splorch à moi 2 s plus tard (charge en retard ou
				-- dans le désordre : le serveur n'en montre qu'un, le client ne doit jamais rester coincé)
				Cam.ascend(T0, T0 + 4, T0 + 10)
				run(2)
				expect(Cam.leaseHolder()).toBe("show")
				expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
				Cam.splorch(Clock.now(), Clock.now() + 3.2, Clock.now() + 5)
				-- les deux finissent (le Splorch à +7 s, l'Ascension à +10 s), puis encore 15 s
				run(25)
				expect(Cam.busy()).toBe(false)
				expect(Cam.leaseHolder()).toBeNil()
				expect(camera.CameraType).toBe(Enum.CameraType.Custom)
				-- la caméra n'est plus écrite par un travelling : le joueur la reprend
				camera.CFrame = CFrame.new(9, 9, 9)
				run(1)
				expect(camera.CFrame.Position).toEqual(Vector3.new(9, 9, 9))
				clean(h)
			end
		)
	end)

	-- =========================================================================================
	-- B5-67 : pièce de Big Plop reprise de la réserve encore invisible
	-- =========================================================================================
	describe("Review_B5_deep › réserve des pièces de Big Plop", function()
		it(
			"B5-67 : un geste coupé tôt (points encore invisibles) ne rend pas le casque et le maillet du Chantier suivant invisibles (Transparency remise à 0 à la reprise)",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				h:require(CLIENT .. "Util.Prefs").Init()
				h:require(CLIENT .. "Controllers.StateController").Init()
				local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
				WSC.Init()
				WSC.Start()
				local list = folder(folder(h.workspace, "Wobbleton"), "Ranches")
				for slot = 1, 16 do
					folder(list, tostring(slot), "Model")
				end
				local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
				RR.Init()
				RR.Start()
				local VFX = h:require(CLIENT .. "Controllers.VFXController")
				VFX.Init()
				VFX.Start()
				local BP = h:require(CLIENT .. "World.BigPlop")
				local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
				local snap = nil
				-- minuterie de la condition du geste (1 Hz, lot I étape 5, I-40 : plus de lecture par image) :
				-- menée par l'horloge figée du cas, échue avant chaque image
				local timers = {}
				BP._configure({
					after = function(seconds, fn, gen)
						table.insert(timers, { at = Clock.now() + seconds, fn = fn, gen = gen })
					end,
					play = function() end,
					haptic = function() end,
					snapshot = function()
						return snap
					end,
					payable = function()
						return false
					end,
					attr = function(name)
						return if name == "AscendReady" then true else nil
					end,
					winter = function()
						return false
					end,
				})
				local elements = {}
				RR.elementCFrame = function(slot, id)
					return elements[slot .. ":" .. id]
				end
				-- mon ranch 3 (joueur 1 = moi)
				h.localPlayer.UserId = 1
				local ranches = {}
				for slot = 1, 16 do
					ranches[tostring(slot)] = ranch(slot, if slot == 3 then 1 else 100 + slot)
				end
				h:fireClient(REMOTES .. "RanchSnapshot", { seq = 1, ranches = ranches, squishies = {} })
				h:settle(1)
				local function event(over)
					local e = UpgradeScreen.eventState({ JellyAscend = true })
					for k, v in over or {} do
						e[k] = v
					end
					h:fireClient(REMOTES .. "EventState", e)
					h:settle(1)
				end
				event()
				if h.localPlayer.Character == nil then
					h:respawn(h.localPlayer)
				end
				h:moveTo(h.localPlayer, WL.penSlot(3, 5) + Vector3.new(0, 3, 0))
				local function play(seconds, fps)
					local dt = 1 / (fps or 60)
					for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
						Clock.advance(dt)
						for i = #timers, 1, -1 do
							if timers[i].at <= Clock.now() + 1e-9 then
								local t = table.remove(timers, i)
								t.fn(t.gen)
							end
						end
						h.game.RunService.RenderStepped:Fire(dt)
					end
					h:settle(1)
				end
				-- le geste commence (rien de payable depuis 300 s, Ascension prête)
				snap = {}
				play(298, 4)
				local guard = 0
				while BP._state() == nil and guard < 600 do
					guard += 1
					play(1 / 60)
				end
				local st = BP._state()
				expect(st and st.kind).toBe("gesture")
				-- 0,2 s plus tard (les 3 points encore invisibles), un Rush coupe le geste
				play(0.2)
				event({ rush = { active = true, endsAt = T0 + 9999 } })
				play(0.1)
				expect(BP._state()).toBeNil()
				-- le Rush finit ; un élément est construit dans mon ranch : Chantier casqué
				event()
				elements["3:helper.house"] = CFrame.new(WL.helperHouse(3))
				RR.ElementBuilt:Fire(3, "helper.house")
				h:settle(1)
				play(0.1)
				st = BP._state()
				expect(st and st.kind).toBe("chantier")
				expect(st.head.Name).toBe("Helmet")
				expect({ st.head.Transparency, st.mallet.Transparency }).toEqual({ 0, 0 })
				play(4.5)
				expect(BP._state()).toBeNil()
				clean(h)
			end
		)
	end)

	-- =========================================================================================
	-- B5-68 : Plopette figée en plein saut quand l'horloge du jeu recule
	-- =========================================================================================
	describe("Review_B5_deep › horloge qui recule pendant un saut de Plopette", function()
		it(
			"B5-68 : l'horloge recule d'une heure en plein saut (décalage du serveur) : la Plopette se pose sur sa cible tout de suite au lieu de rester figée au départ jusqu'à ce que l'horloge revienne",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(T0)
				h:require(CLIENT .. "Util.Prefs").Init()
				h:require(CLIENT .. "Controllers.StateController").Init()
				local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
				WSC.Init()
				WSC.Start()
				local models = {}
				local list = folder(folder(h.workspace, "Wobbleton"), "Ranches")
				for slot = 1, 16 do
					models[slot] = folder(list, tostring(slot), "Model")
					models[slot]:SetAttribute("Slot", slot)
				end
				local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
				RR.Init()
				RR.Start()
				local HR = h:require(CLIENT .. "Controllers.HelperRenderer")
				HR.Init()
				HR.Start()
				HR._configure({ play = function() end, drops = function() end, press = function() end })
				h.localPlayer.UserId = 1
				local ranches, squishies = {}, {}
				for slot = 1, 16 do
					ranches[tostring(slot)] = ranch(slot, if slot == 3 then 1 else 100 + slot)
					squishies[tostring(slot)] = {
						a = { s = 1, m = 0, st = 0, z = 50, zg = 0, at = "pen", bf = 0, o = "", ready = 0 },
					}
				end
				h:fireClient(
					REMOTES .. "RanchSnapshot",
					{ seq = 1, ranches = ranches, squishies = squishies }
				)
				h:settle(1)
				local function play(seconds)
					local dt = 1 / 60
					for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
						Clock.advance(dt)
						h.game.RunService.RenderStepped:Fire(dt)
					end
					h:settle(1)
				end
				models[3]:SetAttribute("Helpers", 1)
				models[3]:SetAttribute("HelperMode", "active")
				h:settle(1)
				play(0.5)
				expect(HR._state(3, 1).drawn).toBe(true)
				h:fireClient(REMOTES .. "HelperPress", {
					ownerId = 1,
					presses = { { helper = 1, uid = "a", tPress = Clock.now() + 2 } },
				})
				h:settle(1)
				play(0.5)
				local st = HR._state(3, 1)
				expect(st.state).toBe("jump")
				-- l'horloge du jeu recule d'une heure (Clock.setOffset du serveur, commandes de développement)
				Clock.freeze(Clock.now() - 3600)
				play(0.5)
				st = HR._state(3, 1)
				expect(st.state).toBe("idle")
				expect(st.pos).toEqual(st.target)
				clean(h)
			end
		)
	end)
end
