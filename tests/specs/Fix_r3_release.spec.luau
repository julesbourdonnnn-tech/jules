--!nocheck
-- Validation de publication r3 — notes croisées des correcteurs :
--   * DataService : attribut répliqué Player « ProfileLoading » (numéro d'essai > 0) pendant toute
--     l'attente du chargement (verrou d'un autre serveur, retries), nil dès la réponse connue
--     (chargé, échec définitif) ; contrat lu par src/first/Loading.client (Fix_r3_partage_2)
--   * HUD (docs/07 §6.2) : mode menu (sélection dans le HUD ou la minicarte, ex. après ○ depuis un
--     panneau ouvert par le rail) : l'icône du rail passe à ○ avec « Play » / « Jouer » à côté ;
--     sélection effacée (○, CC_Close) → △ revient, libellé masqué
--   * InputController / HUD.selectRail : écran de chargement encore là (ScreenGui « Loading ») :
--     △, ○, croix et raccourcis passent sans rien faire (aucun bouton caché sélectionné)
--   * EventService : Starborn réellement limités (Events.starbornAllowed) : hors semaine Starborn,
--     ni tirage StarbornChance ni cadeau Starborn (cadeau ordinaire, « feedback.starfallGiftPlain »)

local task = require("@lune/task")
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local K = Enum.KeyCode

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local STORE = "PlayerData_v1"

	local function boot()
		local h = Harness.new()
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		DS.Settings.RETRY_BASE_DELAY = 0.001
		h:boot()
		return h, DS
	end

	-- Valeurs successives de l'attribut ProfileLoading du prochain joueur, dès son entrée dans
	-- Players (avant PlayerAdded) ; snapshots = nombre d'instantanés déjà envoyés à chaque valeur
	local function watchNextPlayer(h)
		local seen, snapshots = {}, {}
		local conn
		conn = h.game.Players.ChildAdded:Connect(function(p)
			conn:Disconnect()
			p:GetAttributeChangedSignal("ProfileLoading"):Connect(function()
				table.insert(seen, p:GetAttribute("ProfileLoading") or "nil")
				table.insert(snapshots, #h:sentTo(p, "DataSnapshot"))
			end)
		end)
		return seen, snapshots
	end

	describe("Fix r3 release › DataService : attribut ProfileLoading", function()
		it("verrou d'un autre serveur : essais 1 à 5 en attente, puis nil avant l'instantané", function()
			local h, DS = boot()
			local store = h.game.DataStoreService:GetDataStore(STORE)
			store:SetAsync("player_31", {
				data = { version = 1, glow = 42, receipts = {} },
				lock = { jobId = "autre-serveur", time = os.time() },
			})
			local seen, snapshots = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 31, name = "P31" })
			local data = DS.waitFor(p, 3)
			h:settle(2)
			expect(data ~= nil).toBe(true)
			expect(data.glow).toBe(42)
			-- 1 (arrivée), puis un numéro par essai : les essais 1 à 5 attendent le verrou, le 6e le vole
			expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
			-- effacé AVANT l'instantané (l'écran de chargement ne retient plus Réessayer)
			expect(snapshots).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
			expect(#h:sentTo(p, "DataSnapshot")).toBe(1)
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
		end)

		it("chargement normal : posé puis effacé, jamais resté sur le joueur", function()
			local h, DS = boot()
			local seen = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 32, name = "P32" })
			DS.waitFor(p, 2)
			h:settle(2)
			expect(seen).toEqual({ 1, "nil" })
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
		end)

		it("échec définitif : effacé avant le renvoi", function()
			local h, DS = boot()
			h.dataStoreFailures = 100
			local seen = watchNextPlayer(h)
			local p = h:addPlayer({ userId = 33, name = "P33" })
			h:settle(30)
			local waited = os.clock()
			while #h.log.kicks == 0 and os.clock() - waited < 2 do
				task.wait(0.02)
			end
			expect(DS.get(p)).toBeNil()
			expect(#h.log.kicks).toBe(1)
			expect(seen).toEqual({ 1, 2, 3, 4, 5, 6, "nil" })
			expect(p:GetAttribute("ProfileLoading")).toBeNil()
			h.dataStoreFailures = 0
		end)
	end)
	-- =============================================================================================
	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	-- Client console complet (Main.client) avec un instantané de profil ; sons journalisés
	local function consoleClient(lang)
		local h = Harness.new({ mode = "client", console = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = { h = h, Clock = Clock, sounds = {} }
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		local play = Audio.play
		Audio.play = function(name, ...)
			table.insert(c.sounds, name)
			return play(name, ...)
		end
		h:boot()
		h:fireClient(REMOTES .. "DataSnapshot", {
			glow = 5000,
			onboarding = { step = 8, p = 0 },
			settings = { lang = lang or "en" },
		})
		h:step(1 / 60, 30)
		h:settle(3)
		c.PC = h:require(CLIENT .. "Controllers.PanelController")
		c.Input = h:require(CLIENT .. "Controllers.InputController")
		c.HUD = h:require(CLIENT .. "UI.HUD")
		table.clear(c.sounds)
		return c
	end

	local function frames(c, n)
		for _ = 1, n or 3 do
			c.Clock.advance(1 / 30)
			c.h:step(1 / 30, 1)
		end
		c.h:settle(1)
	end

	local function railGlyph(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe.RailGlyph
	end

	local function cue(c)
		local holder = railGlyph(c)
		Layout.apply(c.h)
		return {
			key = holder.PadGlyph:GetAttribute("GlyphKey"),
			hint = Layout.visible(holder.RailHint),
			text = holder.RailHint.Text,
		}
	end

	local function count(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	describe("Fix r3 release › HUD : repère « retour au jeu » en mode menu (manette)", function()
		it(
			"○ depuis un panneau ouvert par le rail : ○ + « Play » ; ○ encore : △ revient",
			function()
				local c = consoleClient()
				expect(cue(c)).toEqual({ key = "ButtonY", hint = false, text = "Play" })
				local railUpgrades = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Upgrades.Button
				-- △ : menu du HUD, sélection sur le rail → déjà le mode menu
				Gamepad.tap(c.h, K.ButtonY)
				c.h.game.GuiService.SelectedObject = railUpgrades
				frames(c, 2)
				expect(cue(c)).toEqual({ key = "ButtonB", hint = true, text = "Play" })
				-- ✕ ouvre Améliorer : la sélection est dans la fenêtre (autre écran) → △ (ferme tout)
				Gamepad.tap(c.h, K.ButtonA)
				frames(c, 8)
				expect(c.PC.current()).toBe("Upgrades")
				expect(cue(c)).toEqual({ key = "ButtonY", hint = false, text = "Play" })
				-- ○ : fermeture, sélection rendue au bouton du rail → ○ + « Play »
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("PanelBack")
				frames(c, 8)
				expect(c.PC.current()).toBeNil()
				expect(Gamepad.selected(c.h)).toBe(railUpgrades)
				expect(cue(c)).toEqual({ key = "ButtonB", hint = true, text = "Play" })
				-- libellé lisible : ≥ 18 px de référence, dans la zone sûre, sans chevauchement d'audit
				expect(table.concat(Gamepad.audit(c.h, { root = railGlyph(c) }), "\n")).toBe("")
				-- ○ encore (CC_Close) : la main revient au jeu, △ et libellé masqué
				expect(Gamepad.tap(c.h, K.ButtonB)).toBe("CC_Close")
				frames(c, 2)
				expect(Gamepad.selected(c.h)).toBeNil()
				expect(cue(c)).toEqual({ key = "ButtonY", hint = false, text = "Play" })
				expect(table.concat(c.h.errors, "\n")).toBe("")
			end
		)

		it("en français : « Jouer » ; sélection effacée : △ revient", function()
			local c = consoleClient("fr")
			local railUpgrades = c.h.localPlayer.PlayerGui.HUD.Safe.Rail.Upgrades.Button
			c.h.game.GuiService.SelectedObject = railUpgrades
			frames(c, 2)
			expect(cue(c)).toEqual({ key = "ButtonB", hint = true, text = "Jouer" })
			-- sélection effacée : △ revient
			c.h.game.GuiService.SelectedObject = nil
			frames(c, 2)
			expect(cue(c)).toEqual({ key = "ButtonY", hint = false, text = "Jouer" })
		end)
	end)

	describe("Fix r3 release › écran de chargement encore là : les touches du jeu passent", function()
		it("△ ne sélectionne aucun bouton caché, ○ garde la sélection, sans son « Back »", function()
			local c = consoleClient()
			local playerGui = c.h.localPlayer.PlayerGui
			local loading = MockInstance.new("ScreenGui")
			loading.Name = "Loading"
			local retry = MockInstance.new("TextButton")
			retry.Name = "RetryButton"
			retry.Parent = loading
			loading.Parent = playerGui
			local rails = 0
			c.Input.RailRequested:Connect(function()
				rails += 1
			end)
			local maps = 0
			c.Input.MinimapToggled:Connect(function()
				maps += 1
			end)
			-- △ sans sélection : rien (ni RailRequested, ni rail sélectionné derrière l'écran)
			c.h.game.GuiService.SelectedObject = nil
			expect(Gamepad.tap(c.h, K.ButtonY)).toBeNil()
			expect(Gamepad.selected(c.h)).toBeNil()
			expect(rails).toBe(0)
			expect(c.HUD.selectRail()).toBe(false)
			expect(Gamepad.selected(c.h)).toBeNil()
			-- ○ et △ avec « Réessayer » sélectionné : la sélection reste
			c.h.game.GuiService.SelectedObject = retry
			expect(Gamepad.tap(c.h, K.ButtonB)).toBeNil()
			expect(Gamepad.selected(c.h)).toBe(retry)
			expect(Gamepad.tap(c.h, K.ButtonY)).toBeNil()
			expect(Gamepad.selected(c.h)).toBe(retry)
			-- croix ↓ (minicarte) et raccourcis : rien
			c.h.game.GuiService.SelectedObject = nil
			Gamepad.tap(c.h, K.DPadDown)
			expect(maps).toBe(0)
			Gamepad.tap(c.h, K.ButtonR1)
			frames(c, 4)
			expect(c.PC.current()).toBeNil()
			expect(count(c.sounds, "Back")).toBe(0)
			-- l'écran parti : △ entre de nouveau dans le menu du HUD
			loading:Destroy()
			frames(c, 2)
			expect(Gamepad.tap(c.h, K.ButtonY)).toBe("CC_Rail")
			expect(rails).toBe(1)
			local sel = Gamepad.selected(c.h)
			expect(sel ~= nil and sel:IsDescendantOf(playerGui.HUD)).toBe(true)
			expect(table.concat(c.h.errors, "\n")).toBe("")
		end)
	end)
	-- =============================================================================================
	local SAT = 1800115200 -- samedi 16/01/2027 16:00:00 UTC : semaine 2975, Starborn (2966-2977)
	local WEEK = 604800

	local function bootEvents(t)
		local h = Harness.new()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(t)
		local DS = h:require("ServerScriptService.Server.Services.DataService")
		DS.Settings.RETRY_BASE_DELAY = 0.001
		DS.Settings.LOCKED_RETRY_DELAY = 0.01
		local ctx = {
			h = h,
			Clock = Clock,
			DS = DS,
			E = h:require("ServerScriptService.Server.Services.EventService"),
			Atlas = h:require("ServerScriptService.Server.Services.AtlasService"),
			Spawn = h:require("ServerScriptService.Server.Services.SpawnService"),
			Events = h:require("ReplicatedStorage.Shared.Config.Events"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock"),
			mods = {},
			gifts = {},
		}
		h:boot()
		local setModifiers = ctx.Spawn.setModifiers
		ctx.Spawn.setModifiers = function(m)
			table.insert(ctx.mods, m)
			return setModifiers(m)
		end
		local addNebbies = ctx.Atlas.addNebbies
		ctx.Atlas.addNebbies = function(p, codes, source, stars)
			if source == "starfall" then
				table.insert(ctx.gifts, { player = p, codes = codes })
			end
			return addNebbies(p, codes, source, stars)
		end
		return ctx
	end

	local function joinServer(ctx, userId)
		local p = ctx.h:addPlayer({ userId = userId, name = "P" .. userId })
		ctx.h:settle(3)
		ctx.DS.waitFor(p, 2)
		ctx.h:settle(2)
		return p
	end

	-- Show complet de `sat` avec un joueur présent du début à la fin
	local function runShow(sat)
		local ctx = bootEvents(sat - 50)
		local p = joinServer(ctx, 1)
		local t = sat
		ctx.Clock.freeze(t)
		ctx.E.step(t)
		local mods = ctx.mods[#ctx.mods]
		while t < sat + ctx.Events.Starfall.Duration do
			t += 5
			ctx.Clock.freeze(t)
			ctx.E.step(t)
		end
		local keys = {}
		for _, args in ctx.h:sentTo(p, "Feedback") do
			table.insert(keys, args[1].key)
		end
		return ctx, p, mods, keys
	end

	describe("Fix r3 release › Starfall : Starborn les semaines Starborn seulement", function()
		it("semaine de 1re apparition : tirage Starborn et cadeau Starborn", function()
			local ctx, p, mods, keys = runShow(SAT)
			expect(ctx.Events.starbornAllowed(ctx.EventClock.week(SAT))).toBe(true)
			local featured = ctx.EventClock.featuredSpecies(ctx.EventClock.week(SAT))
			expect(mods.featured).toBe(featured)
			expect(mods.starbornChance).toBe(ctx.Events.Starfall.StarbornChance)
			expect(#ctx.gifts).toBe(1)
			expect(ctx.gifts[1].player).toBe(p)
			expect(ctx.gifts[1].codes[1]).toBe(
				ctx.Nebbies.pack(featured, 0, ctx.Nebbies.Variants.starborn.bit)
			)
			expect(table.find(keys, "feedback.starfallGift") ~= nil).toBe(true)
			expect(table.find(keys, "feedback.starfallGiftPlain")).toBeNil()
		end)

		it("12 semaines plus tard (même vedette) : ni tirage Starborn, ni cadeau Starborn", function()
			local sat = SAT + 12 * WEEK
			local ctx, p, mods, keys = runShow(sat)
			local week = ctx.EventClock.week(sat)
			expect(ctx.Events.starbornAllowed(week)).toBe(false)
			local featured = ctx.EventClock.featuredSpecies(week)
			expect(featured).toBe(ctx.EventClock.featuredSpecies(ctx.EventClock.week(SAT)))
			-- le show garde sa vedette, sans variante Starborn
			expect(mods.featured).toBe(featured)
			expect(mods.featuredChance).toBe(ctx.Events.Starfall.FeaturedChance)
			expect(mods.starbornChance).toBe(0)
			expect(#ctx.gifts).toBe(1)
			expect(ctx.gifts[1].player).toBe(p)
			expect(ctx.gifts[1].codes[1]).toBe(ctx.Nebbies.pack(featured, 0, 0))
			expect(table.find(keys, "feedback.starfallGiftPlain") ~= nil).toBe(true)
			expect(table.find(keys, "feedback.starfallGift")).toBeNil()
			expect(#ctx.h.errors).toBe(0)
		end)
	end)
end
