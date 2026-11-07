--!nocheck
-- InputController (paquet client-hud ; docs/04 §3.4, §13.5, §14.2, §14.6 ; GDD §10.4) : liaisons
-- ContextActionService (manette puis clavier) ; seul module qui lie △ / croix ↓ / M (KeyCode.M ET
-- Semicolon), jamais Tab ; touches du jeu déliées derrière une fenêtre, rien derrière une fenêtre
-- bloquante ; jamais Échap, Options, ButtonSelect, L3, R3 ; croix → = Clap pendant la fenêtre ;
-- G C J L B P → panneaux ; sac à objets coupé sous pcall avec nouveaux essais ; ○ en portant ferme
-- d'abord le menu puis pose ; maintiens Begin / End ; Bump en portant (R2, L2) et avant la leçon du
-- menu ; débit client des emotes. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000
	local DONE = { step = 11, done = true, demoDone = true }

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local h = TvAudit.client({
			profile = { onboarding = opts.onboarding or DONE },
			console = opts.console,
			before = opts.before,
		})
		local IC = TvAudit.mod(h, "Controllers.InputController")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		local PromptC = TvAudit.mod(h, "Controllers.PromptController")
		local world = {
			target = nil,
			ranches = { [1] = { slot = 1, userId = 1, mode = "cozy", carry = "", ride = "", saddle = 1 } },
			calls = {},
		}
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return world.ranches[slot]
		end
		PromptC.current = function()
			return world.target
		end
		for _, fn in { "lock", "unlock", "afterPress", "cycle" } do
			PromptC[fn] = function(...)
				table.insert(world.calls, fn .. ":" .. tostring((...)))
			end
		end
		return h, IC, Clock, world
	end

	local function keysOf(h, name)
		local b = h.actionBindings[name]
		if b == nil then
			return nil
		end
		local out = {}
		for _, k in b.keys do
			table.insert(out, k.Name)
		end
		table.sort(out)
		return out
	end

	local function bump(h)
		local played = {}
		local Audio = TvAudit.mod(h, "Controllers.AudioController")
		local orig = Audio.play
		Audio.play = function(name, ...)
			table.insert(played, name)
			return orig(name, ...)
		end
		return played
	end

	describe("InputController › liaisons", function()
		it("touches du jeu, du menu et des panneaux, au-dessus des contrôles par défaut", function()
			local h, IC = setup()
			expect(IC.gameBound()).toBe(true)
			expect(keysOf(h, "HudPrimary")).toEqual({ "ButtonX", "E" })
			expect(keysOf(h, "HudSecondary")).toEqual({ "ButtonB", "Q" })
			expect(keysOf(h, "HudLeap")).toEqual({ "ButtonR2", "LeftShift" })
			expect(keysOf(h, "HudRide")).toEqual({ "ButtonL2", "R" })
			expect(keysOf(h, "HudCycle")).toEqual({ "ButtonL1", "ButtonR1" })
			expect(keysOf(h, "HudEmote")).toEqual({
				"DPadLeft",
				"DPadRight",
				"DPadUp",
				"F",
				"One",
				"Three",
				"Two",
			})
			expect(keysOf(h, "HudMenu")).toEqual({ "ButtonY", "DPadDown", "M", "Semicolon" })
			expect(keysOf(h, "HudPanels")).toEqual({ "B", "C", "G", "J", "L", "P" })
			for _, name in { "HudPrimary", "HudMenu", "HudPanels" } do
				expect(h.actionBindings[name].priority >= Enum.ContextActionPriority.High.Value).toBe(true)
			end
			clean(h)
		end)

		it(
			"seul module à lier △ / croix ↓ / M ; personne ne lie Tab, Échap, Options, Select, L3, R3",
			function()
				local h = setup()
				local MENU = { ButtonY = true, DPadDown = true, M = true, Semicolon = true }
				local NEVER = {
					Tab = true,
					Escape = true,
					ButtonStart = true,
					ButtonSelect = true,
					ButtonL3 = true,
					ButtonR3 = true,
				}
				for name, b in h.actionBindings do
					for _, k in b.keys do
						if MENU[k.Name] then
							expect({ key = k.Name, by = name }).toEqual({ key = k.Name, by = "HudMenu" })
						end
						expect({ key = k.Name, never = NEVER[k.Name] == true }).toEqual({
							key = k.Name,
							never = false,
						})
					end
				end
				-- rien non plus dans le code : aucune liaison de Tab
				local src = require("@lune/fs").readFile("src/client/Controllers/InputController.luau")
				expect(string.find(src, "KeyCode.Tab", 1, true)).toBeNil()
				clean(h)
			end
		)

		it(
			"fenêtre ouverte : touches du jeu déliées, △ et M seuls ; fenêtre bloquante : plus rien",
			function()
				local h, IC = setup()
				local PC = TvAudit.mod(h, "UI.PanelController")
				PC.toggleMenu()
				h:settle(1)
				expect(IC.gameBound()).toBe(false)
				expect(table.concat(TvAudit.boundBehindWindow(h), "\n")).toBe("")
				expect(keysOf(h, "HudMenu")).toEqual({ "ButtonY", "M", "Semicolon" })
				-- croix ↓ dans le menu : navigation (aucune action), △ ferme tout
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonY)
				expect(PC.menuOpen()).toBe(false)
				expect(IC.gameBound()).toBe(true)
				-- écran de retour (bloquant)
				TvAudit.mod(h, "UI.ReturnScreen").show({
					seconds = 900,
					uid = "u1",
					species = 1,
					grew = 0,
					pot = 0,
					splorchReady = false,
					nearlyReady = false,
				})
				h:settle(1)
				expect(keysOf(h, "HudMenu")).toBeNil()
				expect(keysOf(h, "HudPanels")).toBeNil()
				expect(IC.gameBound()).toBe(false)
				clean(h)
			end
		)

		it("△ et croix ↓ ouvrent le menu ; avant la leçon du menu, seulement un son Bump", function()
			local h = setup()
			local PC = TvAudit.mod(h, "UI.PanelController")
			Gamepad.tap(h, Enum.KeyCode.DPadDown)
			expect(PC.menuOpen()).toBe(true)
			local h2 = setup({ onboarding = { step = 3, done = false, demoDone = false } })
			local played = bump(h2)
			Gamepad.tap(h2, Enum.KeyCode.ButtonY)
			Gamepad.tap(h2, Enum.KeyCode.M)
			Gamepad.tap(h2, Enum.KeyCode.G)
			expect(TvAudit.mod(h2, "UI.PanelController").menuOpen()).toBe(false)
			expect(TvAudit.mod(h2, "UI.FocusGuard").anyOpen()).toBe(false)
			local bumps = 0
			for _, name in played do
				if name == "Bump" then
					bumps += 1
				end
			end
			expect(bumps).toBe(3)
			clean(h)
			clean(h2)
		end)

		it(
			"clavier : M et Semicolon (AZERTY) ouvrent et ferment le menu ; G C J L B P ouvrent leur panneau",
			function()
				local h = setup({ console = false })
				local PC = TvAudit.mod(h, "UI.PanelController")
				Gamepad.dispatch(h, Enum.KeyCode.Semicolon, Enum.UserInputState.Begin)
				expect(PC.menuOpen()).toBe(true)
				TvAudit.tick(h, 0.5)
				Gamepad.dispatch(h, Enum.KeyCode.M, Enum.UserInputState.Begin)
				expect(PC.menuOpen()).toBe(false)
				local opened = {}
				PC.open = function(panel)
					table.insert(opened, panel)
				end
				for _, key in { "G", "C", "J", "L", "B", "P" } do
					Gamepad.dispatch(h, Enum.KeyCode[key], Enum.UserInputState.Begin)
				end
				expect(opened).toEqual({
					"Ranch",
					"Squishydex",
					"Objectives",
					"Leaderboards",
					"Shop",
					"Settings",
				})
				clean(h)
			end
		)

		it(
			"sac à objets coupé sous pcall, nouveaux essais pendant 10 s (CoreGui pas encore prêt)",
			function()
				local calls = {}
				local h, IC, Clock = setup({
					before = function()
						MockInstance.classMethods.StarterGui.SetCoreGuiEnabled = function(_, kind, on)
							if kind ~= Enum.CoreGuiType.Backpack then
								return -- fenêtre de chat (règle console de Platform)
							end
							table.insert(calls, tostring(kind) .. ":" .. tostring(on))
							if #calls < 3 then
								error("SetCore: CoreGui not registered yet")
							end
						end
					end,
				})
				expect(calls[1]).toBe("Enum.CoreGuiType.Backpack:false")
				expect(IC.backpackDisabled()).toBe(false)
				for _ = 1, 4 do
					Clock.advance(1.01)
					h:step(1 / 60, 1)
				end
				expect(#calls).toBe(3)
				expect(IC.backpackDisabled()).toBe(true)
				-- toujours en panne : abandon silencieux après 10 s (aucun avertissement)
				local fails = 0
				local h2, IC2, Clock2 = setup({
					before = function()
						MockInstance.classMethods.StarterGui.SetCoreGuiEnabled = function(_, kind)
							if kind ~= Enum.CoreGuiType.Backpack then
								return
							end
							fails += 1
							error("SetCore: CoreGui not registered yet")
						end
					end,
				})
				for _ = 1, 15 do
					Clock2.advance(1.01)
					h2:step(1 / 60, 1)
				end
				expect(IC2.backpackDisabled()).toBe(false)
				expect(fails >= 10 and fails <= 12).toBe(true)
				clean(h)
				clean(h2)
			end
		)
	end)

	describe("InputController › actions", function()
		-- lot B4, étape 5 (D21, INT-B4-KIOSK) : □ sur le kiosque de Big Plop ouvre l'écran Améliorations sur
		-- l'onglet Atelier, et rien d'autre (aucune intention envoyée au serveur)
		it(
			'□ sur le kiosque : PanelController.open("Upgrades", "workshop") seulement, aucune intention',
			function()
				local h, _, _, world = setup()
				local PC = TvAudit.mod(h, "UI.PanelController")
				local opened = {}
				local realOpen = PC.open
				PC.open = function(panel, tab, ...)
					table.insert(opened, tostring(panel) .. ":" .. tostring(tab))
					return realOpen(panel, tab, ...)
				end
				world.target = {
					kind = "kiosk",
					slot = 0,
					uid = "",
					id = 0,
					tile = "",
					ready = true,
					primary = "workshop",
					secondary = "",
					position = Vector3.new(-30, 0, 24),
				}
				local before = #h.log.serverEvents
				Gamepad.tap(h, Enum.KeyCode.ButtonX)
				expect(opened).toEqual({ "Upgrades:workshop" })
				expect(#h.log.serverEvents).toBe(before)
				-- ○ sur le kiosque : rien (aucune seconde action)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				expect(#opened).toBe(1)
				expect(#h.log.serverEvents).toBe(before)
				clean(h)
			end
		)

		it("□ presse la cible prête (Press uid, tClient) ; en recharge : Bump, rien d'envoyé", function()
			local h, _, _, world = setup()
			world.target = {
				kind = "squishy",
				slot = 1,
				uid = "u3",
				ready = true,
				primary = "press",
				secondary = "pickup",
				position = Vector3.new(0, 2, -6),
			}
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			local sent = TvAudit.sent(h, "Press")
			expect(#sent).toBe(1)
			expect(sent[1][1]).toBe("u3")
			expect(sent[1][2]).toBe(NOW)
			expect(table.find(world.calls, "afterPress:nil") ~= nil).toBe(true)
			world.target.ready = false
			local played = bump(h)
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			expect(#TvAudit.sent(h, "Press")).toBe(1)
			expect(table.find(played, "Bump") ~= nil).toBe(true)
			clean(h)
		end)

		it(
			"boop maintenu : BoopHold(true) à l'appui, (false) au relâchement ; une fenêtre l'arrête",
			function()
				local h, IC, _, world = setup()
				world.ranches[2] = { slot = 2, userId = 99, mode = "rush", carry = "", ride = "", saddle = 0 }
				world.target = {
					kind = "squishy",
					slot = 2,
					uid = "u8",
					ready = true,
					primary = "boop",
					secondary = "",
					position = Vector3.new(0, 2, -6),
				}
				Gamepad.press(h, Enum.KeyCode.ButtonX)
				local sent = TvAudit.sent(h, "BoopHold")
				expect(sent[1][1]).toBe(99)
				expect(sent[1][2]).toBe("u8")
				expect(sent[1][3]).toBe(true)
				expect(IC.holding()).toBe("boop")
				expect(table.find(world.calls, "lock:boop") ~= nil).toBe(true)
				Gamepad.release(h, Enum.KeyCode.ButtonX)
				sent = TvAudit.sent(h, "BoopHold")
				expect(sent[2][3]).toBe(false)
				expect(IC.holding()).toBeNil()
				-- bol : FeedPlop(true), puis le menu s'ouvre pendant le maintien → FeedPlop(false) aussitôt
				world.target = {
					kind = "bowl",
					slot = 1,
					uid = "",
					ready = true,
					primary = "feed",
					secondary = "",
					position = Vector3.new(0, 2, -6),
				}
				h:require("ReplicatedStorage.Shared.Util.Clock").advance(1)
				Gamepad.press(h, Enum.KeyCode.ButtonX)
				expect(TvAudit.sent(h, "FeedPlop")[1][1]).toBe(true)
				TvAudit.mod(h, "UI.PanelController").toggleMenu()
				h:settle(1)
				expect(TvAudit.sent(h, "FeedPlop")[2][1]).toBe(false)
				expect(IC.holding()).toBeNil()
				clean(h)
			end
		)

		it("○ en portant : le menu ouvert se ferme d'abord, puis ○ pose (PutDown)", function()
			local h, _, _, world = setup()
			world.ranches[1].carry = "u1"
			local PC = TvAudit.mod(h, "UI.PanelController")
			PC.toggleMenu()
			TvAudit.tick(h, 0.5)
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(PC.menuOpen()).toBe(false)
			expect(#TvAudit.sent(h, "PutDown")).toBe(0) -- ouvrir le menu ne termine pas le portage
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(#TvAudit.sent(h, "PutDown")).toBe(1)
			clean(h)
		end)

		it("en portant, R2 et L2 jouent Bump et ne font rien ; sinon Bondir et Monter", function()
			local h, _, _, world = setup()
			local CC = TvAudit.mod(h, "Controllers.ChaseController")
			local leaps = 0
			CC.leap = function()
				leaps += 1
				return true
			end
			world.ranches[1].carry = "u1"
			local played = bump(h)
			Gamepad.tap(h, Enum.KeyCode.ButtonR2)
			Gamepad.tap(h, Enum.KeyCode.ButtonL2)
			expect(leaps).toBe(0)
			expect(#TvAudit.sent(h, "Ride")).toBe(0)
			local bumps = 0
			for _, n in played do
				if n == "Bump" then
					bumps += 1
				end
			end
			expect(bumps).toBe(2)
			world.ranches[1].carry = ""
			Gamepad.tap(h, Enum.KeyCode.ButtonR2)
			Gamepad.tap(h, Enum.KeyCode.ButtonL2)
			expect(leaps).toBe(1)
			expect(TvAudit.sent(h, "Ride")[1][1]).toBe(true)
			clean(h)
		end)

		it(
			"croix → = Applaudir pendant la fenêtre du Grand Splorch d'un autre ; sinon « merci »",
			function()
				local h, _, Clock = setup()
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				expect(TvAudit.sent(h, "Emote")[1][1]).toBe(2)
				h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = 5, endsAt = NOW + 8 })
				h:settle(1)
				Clock.advance(2)
				Gamepad.tap(h, Enum.KeyCode.DPadRight)
				expect(TvAudit.sent(h, "Clap")[1][1]).toBe(5)
				expect(#TvAudit.sent(h, "Emote")).toBe(1)
				clean(h)
			end
		)

		it("emotes : croix ↑ ← et 1 2 3, débit client 1 / 1,5 s ; L1 / R1 changent de cible", function()
			local h, _, Clock, world = setup()
			Gamepad.tap(h, Enum.KeyCode.DPadUp)
			Gamepad.tap(h, Enum.KeyCode.DPadLeft) -- trop tôt : retenu par le débit client
			expect(#TvAudit.sent(h, "Emote")).toBe(1)
			Clock.advance(1.6)
			Gamepad.tap(h, Enum.KeyCode.DPadLeft)
			local sent = TvAudit.sent(h, "Emote")
			expect(sent[2][1]).toBe(3)
			Gamepad.tap(h, Enum.KeyCode.ButtonL1)
			Gamepad.tap(h, Enum.KeyCode.ButtonR1)
			expect(table.find(world.calls, "cycle:-1") ~= nil).toBe(true)
			expect(table.find(world.calls, "cycle:1") ~= nil).toBe(true)
			clean(h)
		end)

		it(
			"clic gauche sur un squishy : cible fixée (clickAt) puis action ; aucun clic derrière une fenêtre",
			function()
				local h, _, _, world = setup({ console = false })
				local PromptC = TvAudit.mod(h, "Controllers.PromptController")
				local clicks = {}
				PromptC.clickAt = function(p)
					table.insert(clicks, p)
					return true
				end
				world.target = {
					kind = "squishy",
					slot = 1,
					uid = "u3",
					ready = true,
					primary = "press",
					secondary = "",
					position = Vector3.new(0, 2, -6),
				}
				local input =
					{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(900, 500, 0) }
				h.game.UserInputService.InputBegan:Fire(input, false)
				h:settle(1)
				expect(#clicks).toBe(1)
				expect(clicks[1]).toEqual(roblox.Vector2.new(900, 500))
				expect(#TvAudit.sent(h, "Press")).toBe(1)
				-- clic sur l'interface (traité par le moteur) ou derrière une fenêtre : rien
				h.game.UserInputService.InputBegan:Fire(input, true)
				TvAudit.mod(h, "UI.PanelController").toggleMenu()
				h:settle(1)
				h.game.UserInputService.InputBegan:Fire(input, false)
				h:settle(1)
				expect(#clicks).toBe(1)
				clean(h)
			end
		)

		it("cible absente ou bizarre : aucune erreur, rien d'envoyé de faux", function()
			local h, _, _, world = setup()
			world.target = { kind = "squishy", primary = "press", uid = 42, ready = true }
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			world.target = { kind = "pad", primary = "buy", tile = {} }
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			world.target = { primary = "boop", slot = "x", uid = "u1" }
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			world.target = nil
			Gamepad.tap(h, Enum.KeyCode.ButtonX)
			Gamepad.tap(h, Enum.KeyCode.ButtonB)
			expect(#TvAudit.sent(h, "Press") + #TvAudit.sent(h, "BuyTile") + #TvAudit.sent(h, "BoopHold")).toBe(
				0
			)
			clean(h)
		end)
	end)
end
