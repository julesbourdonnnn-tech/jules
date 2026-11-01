--!nocheck
-- Correctifs r5 « client-0 » (InputController, roue de pings) sur le VRAI client démarré :
--   1. Garde de la roue (InputController.setPingGate, posée par le HUD : HUD.isRevealed("ping")) :
--      tant que le bouton Ping n'est pas présenté par l'accueil (Q3, GDD §3), Q / croix ↑ passent
--      (Pass) sans ouvrir la roue ni lier le stick, ✕ ou 1-6 ; une roue déjà ouverte se referme
--      encore ; sans garde posée, la roue s'ouvre (comme setPanelGate).
--   2. Panneau ouvert ⇒ roue fermée : PanelController.Opened referme la roue (raccourcis U/C/J/B/G,
--      boutons du rail, panneau qui s'ouvre seul comme ReturnScreen) et délie ses actions de
--      haute priorité (1-6, stick, ✕, croix ← / →) ; openPingWheel ne fait rien tant qu'un panneau
--      est ouvert (bouton Ping du HUD cliqué derrière la fenêtre) ; l'écran « PingWheel » a son
--      propre plan, entre le HUD et les panneaux (jamais d'égalité de DisplayOrder).
local roblox = require("@lune/roblox")
local Gamepad = require("../harness/Gamepad")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local K = Enum.KeyCode
	local BEGIN = Enum.UserInputState.Begin

	-- Actions liées par la roue ouverte (haute priorité)
	local WHEEL_ACTIONS = { "CC_PingKey", "CC_PingStick", "CC_PingConfirm", "CC_PingNav" }

	-- Client complet démarré (console PS5 par défaut, clavier-souris avec opts.pc) ; profil à l'accueil
	-- terminé (étape 8) sauf opts.snapshot. opts.gate : garde de la roue posée comme le fait le HUD.
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.pc ~= true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = { h = h, Clock = Clock }
		ApiAudit.start()
		h:boot()
		h:fireClient(
			REMOTES .. "DataSnapshot",
			opts.snapshot or { glow = 5, onboarding = { step = 8, p = 0 } }
		)
		h:step(1 / 60, 30)
		h:settle(3)
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.Panels = h:require(CLIENT .. "Controllers.PanelController")
		c.HUD = h:require(CLIENT .. "UI.HUD")
		if opts.gate ~= false then
			-- câblage du HUD (HUD.Init) : la roue suit la présentation du bouton Ping
			c.Input.setPingGate(function(): boolean
				return c.HUD.isRevealed("ping")
			end)
		end
		return c
	end

	local function finish(c)
		expect(table.concat(ApiAudit.stop(), "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function sent(c, remote)
		local n = 0
		for _, e in c.h.log.serverEvents do
			if e.remote == remote then
				n += 1
			end
		end
		return n
	end

	local function gui(c, name)
		return c.h.localPlayer.PlayerGui:FindFirstChild(name)
	end

	local function wheelFrame(c)
		local g = gui(c, "PingWheel")
		return if g then g.Safe.Wheel else nil
	end

	-- Actions de la roue encore liées (noms), vide si aucune
	local function wheelBindings(c)
		local out = {}
		for _, name in WHEEL_ACTIONS do
			if c.h.actionBindings[name] ~= nil then
				table.insert(out, name)
			end
		end
		return out
	end

	-- Actions liées à une touche (noms, ordre de traitement)
	local function boundTo(c, key)
		local out = {}
		for _, entry in Gamepad.bindingsFor(c.h, key) do
			table.insert(out, entry.name)
		end
		return out
	end

	local function has(list, value)
		return table.find(list, value) ~= nil
	end

	local function frames(c, n)
		c.h:step(1 / 30, n)
		c.h:settle(1)
	end

	-- =============================================================================================
	-- 1. Garde de la roue : pas de roue avant la présentation du bouton Ping
	-- =============================================================================================

	describe("Fix r5 client-0 › roue de pings gardée par la présentation du bouton Ping", function()
		it("API : setPingGate exposée (posée par le HUD)", function()
			local h = Harness.new({ mode = "client" })
			local Input = h:require(CLIENT .. "Controllers.InputController")
			expect(type(Input.setPingGate)).toBe("function")
		end)

		it(
			"manette, accueil étape 1 (0 session) : croix ↑ passe, ni roue ni stick lié ; ✕ et le stick restent au jeu",
			function()
				local c = boot({
					snapshot = { glow = 0, onboarding = { step = 1, p = 0 }, stats = { sessions = 0 } },
				})
				expect(c.Input.inputType()).toBe(3)
				expect(c.HUD.isRevealed("ping")).toBe(false)
				expect(Gamepad.tap(c.h, K.DPadUp)).toBeNil()
				frames(c, 4)
				expect(c.Input.isPingWheelOpen()).toBe(false)
				local w = wheelFrame(c)
				expect(w == nil or w.Visible == false).toBe(true)
				expect(wheelBindings(c)).toEqual({})
				expect(has(boundTo(c, K.Thumbstick1), "CC_PingStick")).toBe(false)
				expect(has(boundTo(c, K.ButtonA), "CC_PingConfirm")).toBe(false)
				-- un 2e appui ne l'ouvre pas davantage
				expect(Gamepad.tap(c.h, K.DPadUp)).toBeNil()
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(sent(c, "Ping")).toBe(0)
				finish(c)
			end
		)

		it("clavier, accueil étape 1 : Q passe sans ouvrir la roue, 1 n'envoie aucun Ping", function()
			local c = boot({
				pc = true,
				snapshot = { glow = 0, onboarding = { step = 1, p = 0 }, stats = { sessions = 0 } },
			})
			expect(c.HUD.isRevealed("ping")).toBe(false)
			expect(Gamepad.dispatch(c.h, K.Q, BEGIN)).toBeNil()
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(Gamepad.dispatch(c.h, K.One, BEGIN)).toBeNil()
			expect(sent(c, "Ping")).toBe(0)
			finish(c)
		end)

		it("accueil étape 3 (bouton Ping présenté) : croix ↑ ouvre la roue et lie le stick", function()
			local c = boot({
				snapshot = { glow = 0, onboarding = { step = 3, p = 0 }, stats = { sessions = 0 } },
			})
			frames(c, 4)
			expect(c.HUD.isRevealed("ping")).toBe(true)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(true)
			expect(wheelFrame(c).Visible).toBe(true)
			expect(boundTo(c, K.Thumbstick1)[1]).toBe("CC_PingStick")
			-- et la referme
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(wheelBindings(c)).toEqual({})
			finish(c)
		end)

		it("garde fermée mais roue déjà ouverte : croix ↑ la referme encore", function()
			local c = boot()
			c.Input.openPingWheel()
			expect(c.Input.isPingWheelOpen()).toBe(true)
			c.Input.setPingGate(function()
				return false
			end)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(wheelBindings(c)).toEqual({})
			-- puis ne la rouvre pas
			expect(Gamepad.tap(c.h, K.DPadUp)).toBeNil()
			expect(c.Input.isPingWheelOpen()).toBe(false)
			finish(c)
		end)

		it("garde en erreur : roue refusée (comme setPanelGate) ; garde retirée : roue permise", function()
			local c = boot({ gate = false })
			c.Input.setPingGate(function()
				error("garde cassée")
			end)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBeNil()
			expect(c.Input.isPingWheelOpen()).toBe(false)
			c.Input.setPingGate(nil)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(true)
			c.Input.closePingWheel()
			finish(c)
		end)
	end)

	-- =============================================================================================
	-- 2. Panneau ouvert ⇒ roue fermée et déliée
	-- =============================================================================================

	describe("Fix r5 client-0 › un panneau qui s'ouvre referme la roue de pings", function()
		it(
			"clavier : Q puis U → Améliorer ouvert, roue fermée et déliée ; 1 n'envoie aucun Ping",
			function()
				local c = boot({ pc = true, gate = false })
				local actions = c.Input._actions
				expect(Gamepad.dispatch(c.h, K.Q, BEGIN)).toBe(actions.wheel)
				expect(c.Input.isPingWheelOpen()).toBe(true)
				expect(Gamepad.dispatch(c.h, K.U, BEGIN)).toBe(actions.panels)
				frames(c, 4)
				expect(c.Panels.current()).toBe("Upgrades")
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(wheelFrame(c).Visible).toBe(false)
				expect(wheelBindings(c)).toEqual({})
				expect(Gamepad.dispatch(c.h, K.One, BEGIN) == actions.pingKey).toBe(false)
				expect(sent(c, "Ping")).toBe(0)
				finish(c)
			end
		)

		it("bouton du rail du HUD (toucher / souris) : la roue se ferme à l'ouverture du panneau", function()
			local c = boot({ pc = true, gate = false })
			c.Input.openPingWheel()
			expect(c.Input.isPingWheelOpen()).toBe(true)
			gui(c, "HUD").Safe.Rail.Upgrades.Button.Activated:Fire()
			c.h:settle(1)
			frames(c, 4)
			expect(c.Panels.current()).toBe("Upgrades")
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(wheelBindings(c)).toEqual({})
			finish(c)
		end)

		it(
			"manette : panneau qui s'ouvre seul roue ouverte → roue fermée, ✕ revient à la sélection du panneau",
			function()
				local c = boot({ gate = false })
				expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
				expect(c.Input.isPingWheelOpen()).toBe(true)
				-- ouverture hors raccourci (comme ReturnScreen à l'arrivée, ou Supernova)
				c.Panels.open("Upgrades")
				frames(c, 8)
				expect(c.Input.isPingWheelOpen()).toBe(false)
				expect(wheelBindings(c)).toEqual({})
				expect(has(boundTo(c, K.ButtonA), "CC_PingConfirm")).toBe(false)
				expect(has(boundTo(c, K.Thumbstick1), "CC_PingStick")).toBe(false)
				-- ✕ : la sélection du panneau (pas la roue)
				local selected = Gamepad.selected(c.h)
				expect(selected ~= nil and selected:IsDescendantOf(gui(c, "Panels"))).toBe(true)
				expect(Gamepad.tap(c.h, K.ButtonA)).toBeNil()
				expect(sent(c, "Ping")).toBe(0)
				finish(c)
			end
		)

		it("bouton Ping du HUD cliqué derrière un panneau ouvert : la roue ne s'ouvre pas", function()
			local c = boot({ pc = true, gate = false })
			expect(c.Input.openPanel("Upgrades")).toBe(true)
			frames(c, 4)
			c.Input.openPingWheel()
			expect(c.Input.isPingWheelOpen()).toBe(false)
			gui(c, "HUD").Safe.Ping.Button.Activated:Fire()
			c.h:settle(1)
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(wheelBindings(c)).toEqual({})
			-- panneau fermé : la roue s'ouvre de nouveau
			c.Panels.close()
			frames(c, 8)
			c.Input.openPingWheel()
			expect(c.Input.isPingWheelOpen()).toBe(true)
			c.Input.closePingWheel()
			finish(c)
		end)

		it(
			"écran « PingWheel » : au-dessus du HUD, sous les panneaux (aucune égalité de DisplayOrder)",
			function()
				local c = boot({ pc = true, gate = false })
				c.Input.openPingWheel()
				c.Input.closePingWheel()
				expect(c.Input.openPanel("Upgrades")).toBe(true)
				frames(c, 4)
				local wheel = gui(c, "PingWheel").DisplayOrder
				expect(wheel < gui(c, "Panels").DisplayOrder).toBe(true)
				expect(wheel > gui(c, "HUD").DisplayOrder).toBe(true)
				expect(wheel > gui(c, "Minimap").DisplayOrder).toBe(true)
				-- l'instruction d'accueil ne passe pas devant la roue (inchangé)
				local onboarding = gui(c, "Onboarding")
				if onboarding then
					expect(wheel > onboarding.DisplayOrder).toBe(true)
				end
				finish(c)
			end
		)
	end)
end
