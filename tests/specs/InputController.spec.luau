--!nocheck
-- InputController (paquet client-hud) : Dash (prédiction de recharge, refus porteur de Comète,
-- synchronisation DashReadyAt), roue de pings (Q, 1-6, stick + A, débit 1 / 1,5 s, emotes),
-- raccourcis de panneaux (arguments de l'accueil, garde du HUD), minicarte, rail, acclamation, type
-- d'entrée (SetInputType 1 / 5 s), entrées hors jeu ignorées (docs §13.11, GDD §6.3, §10.4).
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local BEGIN = Enum.UserInputState.Begin

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", touch = opts.touch })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			dashes = 0,
			signals = {},
			panelCalls = {},
			open = nil,
			events = nil,
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function()
			c.dashes += 1
		end
		c.WSC.events = function()
			return c.events
		end
		c.Panels.open = function(name, args)
			table.insert(c.panelCalls, { "open", name, args })
			c.open = name
		end
		c.Panels.close = function()
			table.insert(c.panelCalls, { "close" })
			c.open = nil
		end
		c.Panels.current = function()
			return c.open
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.FX.Start()
		for _, name in
			{
				"Dashed",
				"InputTypeChanged",
				"CheerRequested",
				"MinimapToggled",
				"DashRefused",
				"RailRequested",
			}
		do
			c.Input[name]:Connect(function(...)
				table.insert(c.signals, { name = name, args = table.pack(...) })
			end)
		end
		c.Input.Init()
		c.Input.Start()
		return c
	end

	local function sent(c, remote)
		local out = {}
		for _, e in c.h.log.serverEvents do
			if e.remote == remote then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function count(c, name)
		local n = 0
		for _, s in c.signals do
			if s.name == name then
				n += 1
			end
		end
		return n
	end

	local function press(c, action, keyCode, state)
		local fn = c.h.actions[action]
		assert(fn, "action non liée : " .. action)
		return fn(action, state or BEGIN, { KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard })
	end

	local function toasts(c)
		local out = {}
		local gui = c.h.localPlayer.PlayerGui:FindFirstChild("Toasts")
		if gui then
			for _, t in gui.Safe.Stack:GetChildren() do
				if t.Name == "Toast" then
					table.insert(out, t.Label.Text)
				end
			end
		end
		return out
	end

	describe("InputController › Dash", function()
		it("Maj / E / X : remote, VFX, signal et recharge prédite (Formulas.dashCooldown)", function()
			local c = setup()
			expect(press(c, "CC_Dash", Enum.KeyCode.E)).toBe(Enum.ContextActionResult.Sink)
			expect(#sent(c, "Dash")).toBe(1)
			expect(c.dashes).toBe(1)
			expect(count(c, "Dashed")).toBe(1)
			expect(c.Input.dashReadyAt()).toBe(T0 + c.Formulas.dashCooldown(0))
			expect(c.Input.dashProgress(T0)).toBe(0)
			-- recharge : refus local, aucun envoi
			expect(c.Input.dash()).toBe(false)
			expect(#sent(c, "Dash")).toBe(1)
			expect(c.signals[#c.signals].args[1]).toBe("cooldown")
			c.Clock.advance(c.Formulas.dashCooldown(0) / 2)
			expect(c.Input.dashProgress()).toBeNear(0.5, 1e-6)
			c.Clock.advance(c.Formulas.dashCooldown(0) / 2)
			expect(c.Input.dashProgress()).toBe(1)
			expect(press(c, "CC_Dash", Enum.KeyCode.LeftShift)).toBe(Enum.ContextActionResult.Sink)
			expect(#sent(c, "Dash")).toBe(2)
			-- relâchement : ignoré
			expect(press(c, "CC_Dash", Enum.KeyCode.E, Enum.UserInputState.End)).toBe(
				Enum.ContextActionResult.Pass
			)
		end)

		it("recharge plus courte après des Supernovas ; l'attribut serveur DashReadyAt fait foi", function()
			local c = setup()
			c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { supernovas = 8 })
			expect(c.Input.dash()).toBe(true)
			expect(c.Input.dashReadyAt()).toBe(T0 + c.Formulas.dashCooldown(8))
			c.h.localPlayer:SetAttribute("DashReadyAt", T0 + 2)
			c.h:settle(1)
			expect(c.Input.dashReadyAt()).toBe(T0 + 2)
			c.Clock.advance(2)
			expect(c.Input.dash()).toBe(true)
		end)

		it("porteur de la Comète : refus local, toast, rien n'est envoyé", function()
			local c = setup()
			c.events = {
				t = T0,
				comet = { id = 1, phase = "carried", carrierId = c.h.localPlayer.UserId, x = 0, z = 0 },
				wisps = {},
			}
			expect(c.Input.dash()).toBe(false)
			expect(#sent(c, "Dash")).toBe(0)
			expect(c.signals[#c.signals].args[1]).toBe("comet")
			expect(toasts(c)[1]).toBe("No Dash while carrying the Comet")
			-- un autre porteur : Dash permis
			c.events.comet.carrierId = 99
			expect(c.Input.dash()).toBe(true)
		end)

		it("personnage absent ou mort : refus ; réapparition : Dash de nouveau possible", function()
			local c = setup()
			local character = c.h.localPlayer.Character
			c.h.localPlayer.Character = nil
			expect(c.Input.dash()).toBe(false)
			c.h.localPlayer.Character = character
			character.Humanoid.Health = 0
			expect(c.Input.dash()).toBe(false)
			c.h:respawn(c.h.localPlayer)
			expect(c.Input.dash()).toBe(true)
			expect(#sent(c, "Dash")).toBe(1)
		end)

		it("le serveur refuse (Feedback cometNoDash) : la recharge revient à la valeur serveur", function()
			local c = setup()
			expect(c.Input.dash()).toBe(true)
			expect(c.Input.dashReadyAt() > T0).toBe(true)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Feedback",
				{ key = "feedback.cometNoDash", vars = {}, tone = "warning" }
			)
			c.h:settle(1)
			expect(c.Input.dashReadyAt() > T0).toBe(true) -- aucun attribut serveur : prédiction gardée
			c.h.localPlayer:SetAttribute("DashReadyAt", T0 - 1)
			c.h:settle(1)
			expect(c.Input.dashProgress()).toBe(1)
		end)
	end)

	describe("InputController › roue de pings", function()
		it("Q ouvre la roue, 3 envoie Ping(3), la roue se ferme ; débit 1 / 1,5 s", function()
			local c = setup()
			press(c, "CC_PingWheel", Enum.KeyCode.Q)
			expect(c.Input.isPingWheelOpen()).toBe(true)
			local wheel = c.h.localPlayer.PlayerGui.PingWheel.Safe.Wheel
			expect(wheel.Visible).toBe(true)
			expect(wheel.Sector1.Button.Label.Text).toBe("Help!")
			expect(press(c, "CC_PingKey", Enum.KeyCode.Three)).toBe(Enum.ContextActionResult.Sink)
			expect(sent(c, "Ping")[1][1]).toBe(3)
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(wheel.Visible).toBe(false)
			expect(c.h.actions.CC_PingKey).toBeNil()
			expect(c.Input.ping(4)).toBe(false)
			c.Clock.advance(1.5)
			expect(c.Input.ping(4)).toBe(true)
			expect(#sent(c, "Ping")).toBe(2)
		end)

		it("manette : stick vers le haut choisit le secteur 1, A confirme ; B ferme", function()
			local c = setup()
			press(c, "CC_PingWheel", Enum.KeyCode.DPadUp)
			c.h.actions.CC_PingStick("CC_PingStick", Enum.UserInputState.Change, {
				KeyCode = Enum.KeyCode.Thumbstick1,
				Position = Vector3.new(0, 1, 0),
			})
			local wheel = c.h.localPlayer.PlayerGui.PingWheel.Safe.Wheel
			expect(wheel.Sector1.Button:FindFirstChildOfClass("UIStroke").Thickness).toBe(4)
			-- stick vers la droite : secteur 2 ou 3 (entre les deux)
			c.h.actions.CC_PingStick("CC_PingStick", Enum.UserInputState.Change, {
				KeyCode = Enum.KeyCode.Thumbstick1,
				Position = Vector3.new(0.9, 0.5, 0),
			})
			expect(wheel.Sector2.Button:FindFirstChildOfClass("UIStroke").Thickness).toBe(4)
			press(c, "CC_PingConfirm", Enum.KeyCode.ButtonA)
			expect(sent(c, "Ping")[1][1]).toBe(2)
			press(c, "CC_PingWheel", Enum.KeyCode.Q)
			expect(press(c, "CC_Close", Enum.KeyCode.ButtonB)).toBe(Enum.ContextActionResult.Sink)
			expect(c.Input.isPingWheelOpen()).toBe(false)
			-- roue fermée : B / Échap laissés aux autres (PanelController)
			expect(press(c, "CC_Close", Enum.KeyCode.Escape)).toBe(Enum.ContextActionResult.Pass)
		end)

		it("emote locale : Suis-moi → point, Bravo → cheer, Merci → wave", function()
			local c = setup()
			local played = {}
			local humanoid = c.h.localPlayer.Character.Humanoid
			humanoid.PlayEmote = function(_, name)
				table.insert(played, name)
				return true
			end
			c.Input.ping(2)
			c.Clock.advance(2)
			c.Input.ping(1)
			c.Clock.advance(2)
			c.Input.ping(6)
			c.h:settle(1)
			expect(played[1]).toBe("point")
			expect(played[2]).toBe("wave")
			expect(#played).toBe(2)
		end)

		it("valeurs invalides : aucun envoi", function()
			local c = setup()
			for _, kind in { 0, 7, 2.5, 0 / 0, math.huge, -1, "1", {} } do
				expect(c.Input.ping(kind)).toBe(false)
			end
			expect(#sent(c, "Ping")).toBe(0)
		end)
	end)

	describe("InputController › raccourcis", function()
		it("U / C / J / B / G ouvrent les panneaux ; second appui ferme ; arguments de l'accueil", function()
			local c = setup()
			press(c, "CC_Panels", Enum.KeyCode.U)
			expect(c.panelCalls[1][1]).toBe("open")
			expect(c.panelCalls[1][2]).toBe("Upgrades")
			press(c, "CC_Panels", Enum.KeyCode.U)
			expect(c.panelCalls[2][1]).toBe("close")
			c.Input.setPanelArgs("Upgrades", { focus = "conga" })
			press(c, "CC_Panels", Enum.KeyCode.U)
			expect(c.panelCalls[3][3].focus).toBe("conga")
			press(c, "CC_Panels", Enum.KeyCode.G)
			expect(c.panelCalls[4][2]).toBe("Crew")
			-- garde du HUD : la Boutique n'est pas encore affichée
			c.Input.setPanelGate(function(name)
				return name ~= "Shop"
			end)
			press(c, "CC_Panels", Enum.KeyCode.B)
			expect(#c.panelCalls).toBe(4)
			expect(press(c, "CC_Panels", Enum.KeyCode.Z)).toBe(Enum.ContextActionResult.Pass)
		end)

		it("M → minicarte, Y → rail, F → acclamer seulement si une fenêtre est ouverte", function()
			local c = setup()
			press(c, "CC_Minimap", Enum.KeyCode.M)
			expect(count(c, "MinimapToggled")).toBe(1)
			press(c, "CC_Rail", Enum.KeyCode.ButtonY)
			expect(count(c, "RailRequested")).toBe(1)
			expect(press(c, "CC_Cheer", Enum.KeyCode.F)).toBe(Enum.ContextActionResult.Pass)
			expect(count(c, "CheerRequested")).toBe(0)
			c.Input.setCheerAvailable(true)
			expect(press(c, "CC_Cheer", Enum.KeyCode.DPadRight)).toBe(Enum.ContextActionResult.Sink)
			expect(count(c, "CheerRequested")).toBe(1)
			-- une seule acclamation par Supernova
			expect(c.Input.requestCheer()).toBe(false)
		end)

		it("pendant la saisie de texte, les raccourcis sont ignorés", function()
			local c = setup()
			MockInstance.classMethods.UserInputService.GetFocusedTextBox = function()
				return {}
			end
			expect(press(c, "CC_Dash", Enum.KeyCode.E)).toBe(Enum.ContextActionResult.Pass)
			expect(press(c, "CC_Panels", Enum.KeyCode.U)).toBe(Enum.ContextActionResult.Pass)
			expect(#sent(c, "Dash")).toBe(0)
			expect(#c.panelCalls).toBe(0)
		end)
	end)

	describe("InputController › type d'entrée", function()
		it("clavier-souris au départ, puis tactile et manette ; SetInputType au plus 1 / 5 s", function()
			local c = setup()
			expect(c.Input.inputType()).toBe(2)
			expect(#sent(c, "SetInputType")).toBe(1)
			expect(sent(c, "SetInputType")[1][1]).toBe(2)
			local uis = c.h.game.UserInputService
			uis.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
			c.h:settle(1)
			expect(c.Input.inputType()).toBe(1)
			expect(count(c, "InputTypeChanged")).toBe(1)
			expect(#sent(c, "SetInputType")).toBe(1) -- trop tôt : envoi différé
			uis.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
			c.h:settle(1)
			expect(c.Input.inputType()).toBe(3)
			uis.LastInputTypeChanged:Fire(Enum.UserInputType.Focus) -- ignoré
			c.h:settle(1)
			expect(c.Input.inputType()).toBe(3)
			c.Clock.advance(5)
			c.h:step(1 / 60, 1)
			expect(#sent(c, "SetInputType")).toBe(2)
			expect(sent(c, "SetInputType")[2][1]).toBe(3) -- seulement le dernier type
			c.Clock.advance(10)
			c.h:step(1 / 60, 3)
			expect(#sent(c, "SetInputType")).toBe(2) -- inchangé : rien de plus
		end)

		it("appareil tactile : type 1 dès le démarrage", function()
			local c = setup({ touch = true })
			expect(c.Input.inputType()).toBe(1)
			expect(sent(c, "SetInputType")[1][1]).toBe(1)
		end)
	end)

	describe("InputController › revue (bogues corrigés)", function()
		it(
			"SetInputType ignoré par le serveur (gigue au bord du 1 / 5 s) : renvoyé jusqu'à confirmation",
			function()
				local c = setup()
				local player = c.h.localPlayer
				player:SetAttribute("InputType", 2) -- valeur serveur (CongaService)
				expect(#sent(c, "SetInputType")).toBe(1)
				c.h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
				c.h:settle(1)
				c.Clock.advance(5)
				c.h:step(1 / 60, 1)
				expect(#sent(c, "SetInputType")).toBe(2)
				expect(sent(c, "SetInputType")[2][1]).toBe(1)
				-- le serveur a jeté l'envoi (l'attribut reste à 2) : nouvel envoi à l'intervalle suivant
				c.Clock.advance(2)
				c.h:step(1 / 60, 1)
				expect(#sent(c, "SetInputType")).toBe(2) -- jamais plus d'un envoi / 5 s
				c.Clock.advance(3)
				c.h:step(1 / 60, 1)
				expect(#sent(c, "SetInputType")).toBe(3)
				expect(sent(c, "SetInputType")[3][1]).toBe(1)
				-- confirmé : plus rien
				player:SetAttribute("InputType", 1)
				c.Clock.advance(30)
				c.h:step(1 / 60, 3)
				expect(#sent(c, "SetInputType")).toBe(3)
			end
		)

		it(
			"roue ouverte : stick relâché laissé au module de contrôle (pas de marche fantôme)",
			function()
				local c = setup()
				press(c, "CC_PingWheel", Enum.KeyCode.DPadUp)
				local stick = c.h.actions.CC_PingStick
				local function move(x, y, state)
					return stick("CC_PingStick", state or Enum.UserInputState.Change, {
						KeyCode = Enum.KeyCode.Thumbstick1,
						Position = Vector3.new(x, y, 0),
					})
				end
				-- sélection : absorbée (le personnage ne bouge pas en visant un secteur)
				expect(move(0, 1)).toBe(Enum.ContextActionResult.Sink)
				-- retour au centre / fin : transmis, le vecteur de marche retombe à zéro
				expect(move(0.05, 0.02)).toBe(Enum.ContextActionResult.Pass)
				expect(move(0, 0, Enum.UserInputState.End)).toBe(Enum.ContextActionResult.Pass)
				-- la sélection faite avant le relâchement est conservée
				press(c, "CC_PingConfirm", Enum.KeyCode.ButtonA)
				expect(sent(c, "Ping")[1][1]).toBe(1)
			end
		)

		it("playEmote : personnage vivant seulement, nom invalide ignoré", function()
			local c = setup()
			local played = {}
			local humanoid = c.h.localPlayer.Character.Humanoid
			humanoid.PlayEmote = function(_, name)
				table.insert(played, name)
				return true
			end
			c.Input.playEmote("cheer")
			c.Input.playEmote(nil)
			c.h:settle(1)
			humanoid.Health = 0
			c.Input.playEmote("wave")
			c.h:settle(1)
			expect(#played).toBe(1)
			expect(played[1]).toBe("cheer")
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)
end
