--!nocheck
-- Finition r5 (fixer r5-ui-1) : un seul jingle (Reward / LevelUp) par moment (src/client/UI/ScreenFX.luau).
--   Avant : fin de Q4 (QuestService.completeOnboarding : Celebrate questDone, questClaimed puis
--   atlasUnlocked dans le même envoi), ScreenFX jouait Reward pour questDone et la carte « Star Atlas
--   débloqué ! », entrée tout de suite, son LevelUp : deux musiques (2,5 s et 2 s, volume 0,5) l'une
--   sur l'autre au moment phare de l'accueil. Même chose pour un jalon d'Atlas encaissé avec une
--   quête terminée.
--   Maintenant : un jingle secondaire (quête terminée, jalon d'Atlas, carte « Atlas débloqué ») moins
--   de 1,5 s après un autre est omis (la carte joue alors Pop) ; une carte « Atlas débloqué » qui
--   attend sa place garde son LevelUp quand elle entre (moment distinct) ; les jingles d'un geste du
--   joueur (achat, calendrier, amélioration) jouent toujours.
--   (La bannière personnelle du jalon qui rejoue Reward vit dans UI/Banners : note inter-fichiers.)
local roblox = require("@lune/roblox")
local Layout = require("../harness/Layout")

local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local STINGERS = { Reward = true, LevelUp = true }

	-- schéma chargé une fois, AVANT les harnais clients
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- ScreenFX seul (sans HUD : pile historique de 3 cartes), sons enregistrés avec leur image
	local function fxSetup()
		local h = Harness.new({ mode = "client" })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			frame = 0,
			sounds = {},
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Audio = h:require(CLIENT .. "Controllers.AudioController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
		}
		c.VFX.playUpgrade = function() end
		c.Audio.play = function(name)
			table.insert(c.sounds, { frame = c.frame, name = name })
		end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.FX.Start()
		return c
	end

	local function celebrate(c, kind, data)
		c.h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = data })
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.frame += 1
			c.Clock.advance(dt or 1 / 30)
			c.h:step(dt or 1 / 30, 1)
		end
		c.h:settle(1)
	end

	-- jingles joués (dans l'ordre), avec leur image
	local function stingers(c)
		local out = {}
		for _, s in c.sounds do
			if STINGERS[s.name] then
				table.insert(out, s)
			end
		end
		return out
	end

	local function names(list)
		local out = {}
		for _, s in list do
			table.insert(out, `{s.frame}:{s.name}`)
		end
		return table.concat(out, ", ")
	end

	-- au plus un jingle par image, et deux jingles toujours à ≥ `gap` images d'écart
	local function expectOnePerMoment(c, gap)
		local list = stingers(c)
		for i = 2, #list do
			local apart = list[i].frame - list[i - 1].frame
			expect({ sounds = names(list), apart = apart >= gap }).toEqual({
				sounds = names(list),
				apart = true,
			})
		end
	end

	local function count(c, name)
		local n = 0
		for _, s in c.sounds do
			if s.name == name then
				n += 1
			end
		end
		return n
	end

	local function cardTexts(c)
		local out = {}
		for _, card in c.FX._state().cardList do
			table.insert(out, card.frame.Text.Text)
		end
		return out
	end

	-- Q4 : premier Rare encaissé (NOUVEAU !), quête terminée, récompense, Atlas débloqué
	local function q4(c)
		celebrate(c, "atlasNew", { entries = { { s = 7, f = 0 } } })
		celebrate(c, "questDone", { kind = "onboarding", slot = 1, id = "q4" })
		celebrate(c, "questClaimed", { kind = "onboarding", slot = 1, glow = 0, stardust = 100 })
		celebrate(c, "atlasUnlocked", { count = 5, total = 150 })
		c.h:settle(1)
	end

	describe("Fix r5 ui-1 › un jingle par moment : fin de Q4 (Atlas débloqué)", function()
		it("carte « Atlas débloqué » entrée tout de suite : Reward seul, la carte joue Pop", function()
			local c = fxSetup()
			q4(c)
			-- la carte est bien à l'écran tout de suite (le moment visuel ne change pas)
			expect(table.find(cardTexts(c), "Star Atlas unlocked! 5/150") ~= nil).toBe(true)
			expect(names(stingers(c))).toBe("0:Reward")
			expect(count(c, "LevelUp")).toBe(0)
			-- son de la carte : Pop (avec celui de la carte « NOUVEAU ! »)
			expect(count(c, "Pop")).toBe(2)
			frames(c, 120) -- 4 s : rien d'autre ne sonne plus tard
			expect(names(stingers(c))).toBe("0:Reward")
			expectOnePerMoment(c, 45)
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)

		it("pile pleine : la carte attend, son LevelUp sonne quand elle entre (≈ 3 s après)", function()
			local c = fxSetup()
			local entries = {}
			for s = 1, 3 do
				table.insert(entries, { s = s, f = 0 })
			end
			celebrate(c, "atlasNew", { entries = entries })
			c.h:settle(1)
			expect(c.FX._state().cards).toBe(3)
			q4(c)
			expect(names(stingers(c))).toBe("0:Reward")
			frames(c, 120)
			local list = stingers(c)
			expect(#list).toBe(2)
			expect(list[2].name).toBe("LevelUp")
			expect(list[2].frame >= 45).toBe(true)
			expectOnePerMoment(c, 45)
		end)

		it("Atlas débloqué seul (sans quête juste avant) : LevelUp comme avant", function()
			local c = fxSetup()
			frames(c, 3)
			celebrate(c, "atlasUnlocked", { count = 5, total = 150 })
			c.h:settle(1)
			expect(names(stingers(c))).toBe("3:LevelUp")
		end)
	end)

	describe("Fix r5 ui-1 › un jingle par moment : jalon d'Atlas et quêtes", function()
		it("jalon d'Atlas seul : confettis + LevelUp (GDD §9.4)", function()
			local c = fxSetup()
			frames(c, 2)
			celebrate(c, "atlasMilestone", { count = 12, perch = 1 })
			c.h:settle(1)
			expect(names(stingers(c))).toBe("2:LevelUp")
		end)

		it("quête terminée et jalon d'Atlas du même encaissement : un seul jingle", function()
			local c = fxSetup()
			frames(c, 2)
			celebrate(c, "questDone", { kind = "daily", slot = 1, id = "d_parade3" })
			celebrate(c, "atlasMilestone", { count = 12, perch = 1 })
			c.h:settle(1)
			expect(names(stingers(c))).toBe("2:Reward")
			-- et dans l'autre ordre
			frames(c, 60)
			celebrate(c, "atlasMilestone", { count = 24, perch = 1 })
			celebrate(c, "questDone", { kind = "daily", slot = 2, id = "d_parade3" })
			c.h:settle(1)
			expect(names(stingers(c))).toBe("2:Reward, 62:LevelUp")
			expectOnePerMoment(c, 45)
		end)

		it("moments distincts (> 1,5 s) : chacun garde son jingle", function()
			local c = fxSetup()
			celebrate(c, "questDone", { kind = "daily", slot = 1, id = "d_parade3" })
			c.h:settle(1)
			frames(c, 50) -- 1,67 s
			celebrate(c, "questDone", { kind = "daily", slot = 2, id = "d_parade3" })
			c.h:settle(1)
			expect(names(stingers(c))).toBe("0:Reward, 50:Reward")
		end)

		it(
			"geste du joueur (achat Robux) : son jingle joue toujours, la quête du même envoi se tait",
			function()
				local c = fxSetup()
				frames(c, 1)
				celebrate(c, "purchase", {})
				celebrate(c, "questDone", { kind = "daily", slot = 1, id = "d_parade3" })
				c.h:settle(1)
				expect(names(stingers(c))).toBe("1:Reward")
				-- deux achats coup sur coup : deux réponses (jamais d'achat muet)
				frames(c, 2)
				celebrate(c, "purchase", {})
				c.h:settle(1)
				expect(names(stingers(c))).toBe("1:Reward, 3:Reward")
			end
		)
	end)

	describe(
		"Fix r5 ui-1 › un jingle par moment : amélioration qui termine une quête d'accueil",
		function()
			it("Q2 : questDone puis upgrade (panneau ouvert) dans le même envoi : Reward seul", function()
				local c = fxSetup()
				c.FX.setPanelResolver(function()
					return "Upgrades"
				end)
				frames(c, 2)
				-- ordre du serveur : Signals.UpgradeBought (quête terminée) avant le Celebrate « upgrade »
				celebrate(c, "questDone", { kind = "onboarding", slot = 1, id = "q2" })
				celebrate(c, "questClaimed", { kind = "onboarding", slot = 1, glow = 150 })
				celebrate(c, "upgrade", { track = "conga", level = 2 })
				c.h:settle(1)
				expect(names(stingers(c))).toBe("2:Reward")
				-- achat suivant (autre image) : son LevelUp, comme à chaque achat
				frames(c, 3)
				celebrate(c, "upgrade", { track = "conga", level = 3 })
				c.h:settle(1)
				expect(names(stingers(c))).toBe("2:Reward, 5:LevelUp")
			end)

			it("achats coup sur coup dans la même image : un LevelUp chacun (inchangé)", function()
				local c = fxSetup()
				c.FX.setPanelResolver(function()
					return "Upgrades"
				end)
				celebrate(c, "upgrade", { track = "conga", level = 2 })
				celebrate(c, "upgrade", { track = "stride", level = 1 })
				c.h:settle(1)
				expect(count(c, "LevelUp")).toBe(2)
			end)
		end
	)

	-- =============================================================================================
	-- Client complet (Main.client, vrai AudioController) : la fin de Q4 telle que le serveur l'envoie
	-- =============================================================================================
	describe("Fix r5 ui-1 › client complet : fin de Q4, un seul jingle à la fois", function()
		it("PC 1280 × 720 : Reward puis rien d'autre pendant la carte « Atlas débloqué »", function()
			local h = Harness.new({ mode = "client" })
			h.localPlayer.LocaleId = "en-us"
			h:createRemotes()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(T0)
			local Audio = h:require(CLIENT .. "Controllers.AudioController")
			local c = { h = h, Clock = Clock, frame = 0, sounds = {} }
			local play = Audio.play
			Audio.play = function(name, ...)
				table.insert(c.sounds, { frame = c.frame, name = name })
				return play(name, ...)
			end
			h:boot()
			local p = Schema.defaults()
			p.lastSettle = T0
			p.lastOnline = T0
			p.settings.lang = "en"
			p.onboarding = { step = 4, p = 0 }
			h:fireClient(REMOTES .. "DataSnapshot", p)
			h:step(1 / 60, 30)
			h:settle(3)
			for _ = 1, 3 do
				Layout.apply(h)
				frames(c, 40)
			end
			table.clear(c.sounds)
			c.frame = 0
			c.FX = h:require(CLIENT .. "UI.ScreenFX")
			q4(c)
			expect(table.find(cardTexts(c), "Star Atlas unlocked! 5/150") ~= nil).toBe(true)
			frames(c, 150)
			expect(names(stingers(c))).toBe("0:Reward")
			expect(table.concat(h.errors, "\n")).toBe("")
		end)
	end)
end
