--!nocheck
-- Validation de release r5 (notes inter-fichiers des correcteurs du tour 5), sur le VRAI client démarré
-- (Main.client : HUD.Init pose ses crochets, aucun setPingGate appelé par le test) :
--   1. Roue de pings gardée par le HUD lui-même : HUD.Init pose InputController.setPingGate
--      (HUD.isRevealed("ping")) ; à l'étape 1 de l'accueil, croix ↑ / Q passent sans ouvrir la roue ;
--      dès que le bouton Ping est présenté (étape 3), la roue s'ouvre.
--   2. Jalon d'Atlas : Celebrate « atlasMilestone » (ScreenFX : confettis + LevelUp, GDD §9.4) et la
--      bannière personnelle du même envoi (UI/Banners) : un seul jingle, LevelUp (la bannière du
--      jalon est muette ; « rookieEnd » garde son Reward).
--   3. Amélioration achetée sans panneau ouvert qui termine une quête (serveur : Signals.UpgradeBought
--      puis Celebrate « upgrade ») : le Reward de la quête répond seul, VFXController.playUpgrade
--      reste muet ; une amélioration seule garde son LevelUp.
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
	local STINGERS = { Reward = true, LevelUp = true }

	-- Client complet démarré (console PS5 par défaut, clavier-souris avec opts.pc) ; sons joués
	-- journalisés avec leur image (c.sounds) ; profil à l'accueil terminé sauf opts.snapshot
	local function boot(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.pc ~= true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = { h = h, Clock = Clock, frame = 0, sounds = {} }
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, { frame = c.frame, name = name })
			return play(name, ...)
		end
		ApiAudit.start()
		h:boot()
		h:fireClient(
			REMOTES .. "DataSnapshot",
			opts.snapshot or { glow = 5, onboarding = { step = 8, p = 0 } }
		)
		h:step(1 / 60, 30)
		h:settle(3)
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.HUD = h:require(CLIENT .. "UI.HUD")
		c.Panels = h:require(CLIENT .. "Controllers.PanelController")
		return c
	end

	local function finish(c)
		expect(table.concat(ApiAudit.stop(), "\n")).toBe("")
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function frames(c, n)
		for _ = 1, n do
			c.frame += 1
			c.Clock.advance(1 / 30)
			c.h:step(1 / 30, 1)
		end
		c.h:settle(1)
	end

	-- jingles joués, « image:nom » dans l'ordre
	local function stingers(c)
		local out = {}
		for _, s in c.sounds do
			if STINGERS[s.name] then
				table.insert(out, `{s.frame}:{s.name}`)
			end
		end
		return table.concat(out, ", ")
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

	describe("Release r5 › roue de pings gardée par HUD.Init (sans setPingGate du test)", function()
		it("manette, accueil étape 1 : croix ↑ passe, la roue reste fermée", function()
			local c = boot({
				snapshot = { glow = 0, onboarding = { step = 1, p = 0 }, stats = { sessions = 0 } },
			})
			expect(c.Input.inputType()).toBe(3)
			expect(c.HUD.isRevealed("ping")).toBe(false)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBeNil()
			frames(c, 4)
			expect(c.Input.isPingWheelOpen()).toBe(false)
			expect(sent(c, "Ping")).toBe(0)
			finish(c)
		end)

		it("clavier, accueil étape 1 : Q passe, 1 n'envoie aucun Ping", function()
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

		it("accueil étape 3 (bouton Ping présenté) : croix ↑ ouvre puis referme la roue", function()
			local c = boot({
				snapshot = { glow = 0, onboarding = { step = 3, p = 0 }, stats = { sessions = 0 } },
			})
			frames(c, 4)
			expect(c.HUD.isRevealed("ping")).toBe(true)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(true)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(false)
			finish(c)
		end)

		it("accueil terminé : la roue s'ouvre comme avant", function()
			local c = boot()
			expect(c.HUD.isRevealed("ping")).toBe(true)
			expect(Gamepad.tap(c.h, K.DPadUp)).toBe("CC_PingWheel")
			expect(c.Input.isPingWheelOpen()).toBe(true)
			c.Input.closePingWheel()
			finish(c)
		end)
	end)

	describe("Release r5 › un seul jingle par moment (client complet)", function()
		it("jalon d'Atlas : Celebrate + bannière personnelle du même envoi → LevelUp seul", function()
			local c = boot({ pc = true })
			frames(c, 30)
			table.clear(c.sounds)
			c.h:fireClient(
				REMOTES .. "Celebrate",
				{ kind = "atlasMilestone", data = { count = 12, perch = 1 } }
			)
			c.h:fireClient(
				REMOTES .. "Banner",
				{ kind = "atlasMilestone", args = { count = 12 }, priority = 7, personal = true }
			)
			c.h:settle(1)
			frames(c, 120)
			expect(stingers(c)).toBe("30:LevelUp")
			finish(c)
		end)

		it("fin de l'accueil (bannière personnelle « rookieEnd ») : Reward conservé", function()
			local c = boot({ pc = true })
			frames(c, 30)
			table.clear(c.sounds)
			c.h:fireClient(
				REMOTES .. "Banner",
				{ kind = "rookieEnd", args = {}, priority = 7, personal = true }
			)
			c.h:settle(1)
			frames(c, 30)
			expect(stingers(c)).toBe("30:Reward")
			finish(c)
		end)

		it(
			"amélioration sans panneau qui termine une quête (même envoi) : Reward seul ; seule : LevelUp",
			function()
				local c = boot({ pc = true })
				frames(c, 30)
				expect(c.Panels.current()).toBeNil()
				table.clear(c.sounds)
				-- ordre du serveur : Signals.UpgradeBought (quête terminée) avant le Celebrate « upgrade »
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "questDone", data = { kind = "daily", slot = 1, id = "d_parade3" } }
				)
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "upgrade", data = { track = "conga", level = 2 } }
				)
				c.h:settle(1)
				frames(c, 60)
				expect(stingers(c)).toBe("30:Reward")
				-- amélioration seule, plus tard : son LevelUp (VFXController), une fois
				c.h:fireClient(
					REMOTES .. "Celebrate",
					{ kind = "upgrade", data = { track = "conga", level = 3 } }
				)
				c.h:settle(1)
				frames(c, 30)
				expect(stingers(c)).toBe("30:Reward, 90:LevelUp")
				finish(c)
			end
		)
	end)
end
