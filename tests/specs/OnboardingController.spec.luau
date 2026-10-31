--!nocheck
-- OnboardingController (paquet client-hud) : règles pures (Hud/OnboardingPlan), travelling d'arrivée,
-- affichage progressif du HUD piloté par profile.onboarding, une instruction à la fois, guidage au
-- sol (empreintes, arche, faisceau, flèche, pilier du Rare), main sur Améliorer et carte unique,
-- joueur qui revient, message des 10 minutes, profil illisible, réapparition (docs §13.14, GDD §3).
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
			Minimap = h:require(CLIENT .. "UI.Minimap"),
			Onboarding = h:require(CLIENT .. "Controllers.OnboardingController"),
			slot = 1,
			length = 0,
			wilds = {},
			panelCalls = {},
			open = nil,
		}
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return c.slot
		end
		c.WSC.lineLength = function()
			return c.length
		end
		c.WSC.wilds = function()
			return c.wilds
		end
		c.WSC.wildPosition = function(w)
			return w.anchor
		end
		c.Panels.open = function(name, args)
			table.insert(c.panelCalls, { name = name, args = args })
			c.open = name
			c.Panels.Opened:Fire(name)
		end
		c.Panels.close = function()
			local name = c.open
			c.open = nil
			if name then
				c.Panels.Closed:Fire(name)
			end
		end
		c.Panels.current = function()
			return c.open
		end
		if opts.reduced then
			h.game.GuiService.ReducedMotionEnabled = true
		end
		c.h.localPlayer.Character.HumanoidRootPart.CFrame =
			CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
		local order = { "Root", "State", "Prefs", "FX", "Input", "HUD", "Minimap", "Onboarding" }
		for _, name in order do
			if c[name].Init then
				c[name].Init()
			end
		end
		for _, name in order do
			if c[name].Start and name ~= "Root" and name ~= "State" then
				c[name].Start()
			end
		end
		return c
	end

	local function profile(over)
		local p = Schema.defaults()
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local function load(c, over)
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", profile(over))
		c.h:settle(1)
	end

	local function patch(c, data)
		c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", data, {})
		c.h:settle(1)
	end

	-- quelques images : évaluation (Heartbeat), fin des tweens différés du harnais
	local function run(c, n)
		for _ = 1, n or 3 do
			c.h:step(1 / 30, 1)
			c.h:settle(1)
		end
	end

	local function wild(c, id, species, pos, personal)
		c.wilds[id] = {
			id = id,
			code = c.Nebbies.pack(species, 0, 0),
			anchor = pos,
			seed = 1,
			t0 = T0,
			expiresAt = T0 + 60,
			dizzyUntil = 0,
			prioritySlot = 0,
			personal = personal == true,
		}
	end

	local function speciesOfRarity(c, rarity)
		return c.Nebbies.speciesOfRarity(rarity)[1]
	end

	describe("Onboarding › règles pures (OnboardingPlan)", function()
		local function facts(over)
			local f = {
				step = 1,
				returning = false,
				parades = 0,
				conga = 0,
				stardust = 0,
				lineCount = 0,
				lineFull = false,
				upgradesOpen = false,
				canBuyConga = false,
				canBuyStride = false,
				canBuyPerches = false,
				rareTarget = false,
			}
			for k, v in over or {} do
				f[k] = v
			end
			return f
		end

		it("affichage progressif croissant ; tout pour un joueur qui revient", function()
			local h = Harness.new({ mode = "client" })
			local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")
			local function has(list, e)
				return table.find(list, e) ~= nil
			end
			local base = Plan.reveals(facts())
			expect(#base).toBe(3)
			expect(has(base, "glow") and has(base, "line") and has(base, "dash")).toBe(true)
			local afterParade = Plan.reveals(facts({ parades = 1 }))
			expect(has(afterParade, "rail.Upgrades")).toBe(true)
			expect(has(afterParade, "questTracker")).toBe(false)
			expect(has(Plan.reveals(facts({ parades = 1, conga = 1 })), "questTracker")).toBe(true)
			local q4 = Plan.reveals(facts({ step = 4 }))
			expect(has(q4, "stardust") and has(q4, "minimap") and has(q4, "status")).toBe(true)
			expect(has(q4, "rail.Collection")).toBe(false)
			expect(has(Plan.reveals(facts({ step = 5 })), "rail.Collection")).toBe(true)
			expect(#Plan.reveals(facts({ step = 8 }))).toBe(#Plan.ALL)
			expect(#Plan.reveals(facts({ step = 2, returning = true }))).toBe(#Plan.ALL)
			-- monotone : chaque étape contient la précédente
			for step = 1, 7 do
				local before = Plan.reveals(facts({ step = step, parades = 1, conga = 1 }))
				local after = Plan.reveals(facts({ step = step + 1, parades = 1, conga = 1 }))
				for _, e in before do
					expect({ step = step, e = e, kept = has(after, e) }).toEqual({
						step = step,
						e = e,
						kept = true,
					})
				end
			end
		end)

		it(
			"une instruction : Puffkins → porte → Améliorer → acheter → Nebbies ; achat seulement si possible",
			function()
				local h = Harness.new({ mode = "client" })
				local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")
				expect(Plan.hint(facts({ step = 0 }))).toBeNil()
				expect(Plan.hint(facts())).toBe("onboarding.catch")
				expect(Plan.hint(facts({ lineCount = 3, lineFull = true }))).toBe("onboarding.goHome")
				expect(Plan.hint(facts({ parades = 1 }))).toBe("onboarding.tapUpgrade")
				expect(Plan.hint(facts({ parades = 1, upgradesOpen = true }))).toBe("onboarding.buyConga")
				expect(Plan.hint(facts({ parades = 1, conga = 1 }))).toBe("onboarding.findNebbies")
				expect(Plan.hint(facts({ step = 2, parades = 1, conga = 1 }))).toBe("onboarding.findNebbies")
				expect(Plan.hint(facts({ step = 2, conga = 1, canBuyConga = true }))).toBe(
					"onboarding.buyConga"
				)
				expect(Plan.hint(facts({ step = 4 }))).toBe("onboarding.catchRare")
				expect(Plan.hint(facts({ step = 4, lineFull = true }))).toBe("onboarding.goHome")
				expect(Plan.hint(facts({ step = 5, canBuyStride = true }))).toBe("onboarding.buyStride")
				expect(Plan.hint(facts({ step = 6 }))).toBe("onboarding.weather")
				expect(Plan.hint(facts({ step = 7 }))).toBe("onboarding.findNebbies")
				expect(Plan.hint(facts({ step = 7, canBuyPerches = true }))).toBe("onboarding.perches")
				expect(Plan.hint(facts({ step = 8 }))).toBeNil()
				-- ≤ 4 mots (GDD §3) en anglais et en français
				local L = h:require("ReplicatedStorage.Shared.Localization")
				for _, key in
					{
						"onboarding.catch",
						"onboarding.goHome",
						"onboarding.tapUpgrade",
						"onboarding.buyConga",
						"onboarding.findNebbies",
						"onboarding.catchRare",
						"onboarding.buyStride",
						"onboarding.weather",
						"onboarding.perches",
					}
				do
					for _, lang in { "en", "fr" } do
						local _, words = string.gsub(L.get(lang, key), "%S+", "")
						expect({ key = key, lang = lang, short = words <= 5 }).toEqual({
							key = key,
							lang = lang,
							short = true,
						})
					end
				end
			end
		)

		it("guidage et attention", function()
			local h = Harness.new({ mode = "client" })
			local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")
			expect(Plan.guide(facts())).toBe("toPuffkins")
			expect(Plan.guide(facts({ lineCount = 3 }))).toBe("toGate")
			expect(Plan.guide(facts({ parades = 1 }))).toBeNil()
			expect(Plan.guide(facts({ parades = 1, conga = 1 }))).toBe("toNebbies")
			expect(Plan.guide(facts({ step = 4, rareTarget = true }))).toBe("toRare")
			expect(Plan.guide(facts({ step = 4 }))).toBe("toNebbies")
			expect(Plan.guide(facts({ step = 6, lineFull = true }))).toBe("toGate")
			expect(Plan.guide(facts({ step = 6 }))).toBeNil()
			expect(Plan.attention(facts({ parades = 1 }))["rail.Upgrades"]).toBe(true)
			expect(Plan.attention(facts({ parades = 1, upgradesOpen = true }))["rail.Upgrades"]).toBeNil()
			expect(Plan.attention(facts({ parades = 1, conga = 1 }))["rail.Upgrades"]).toBeNil()
		end)

		it("retour en Q1 sans parade : pas de Puffkins (bienvenue = première session seulement)", function()
			local h = Harness.new({ mode = "client" })
			local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")
			expect(Plan.hint(facts({ returning = true }))).toBe("onboarding.findNebbies")
			expect(Plan.guide(facts({ returning = true }))).toBe("toNebbies")
			expect(Plan.hint(facts({ returning = true, lineCount = 3, lineFull = true }))).toBe(
				"onboarding.goHome"
			)
			expect(Plan.guide(facts({ returning = true, lineCount = 3 }))).toBe("toGate")
			-- première session : inchangé
			expect(Plan.hint(facts())).toBe("onboarding.catch")
			expect(Plan.guide(facts())).toBe("toPuffkins")
		end)
	end)

	describe("Onboarding › première session", function()
		it(
			"travelling de 1,5 s puis HUD de base (Glow, file, Dash) et empreintes vers les Puffkins",
			function()
				local c = setup()
				local camera = c.h.workspace.CurrentCamera
				local types = {}
				camera:GetPropertyChangedSignal("CameraType"):Connect(function()
					table.insert(types, camera.CameraType)
				end)
				load(c)
				expect(c.HUD.isRevealed("glow")).toBe(false)
				run(c, 4)
				expect(types[1]).toBe(Enum.CameraType.Scriptable)
				expect(types[#types]).toBe(Enum.CameraType.Custom)
				expect(camera.CameraType).toBe(Enum.CameraType.Custom)
				expect(c.HUD.isRevealed("glow")).toBe(true)
				expect(c.HUD.isRevealed("line")).toBe(true)
				expect(c.HUD.isRevealed("dash")).toBe(true)
				expect(c.HUD.isRevealed("rail.Upgrades")).toBe(false)
				expect(c.HUD.isRevealed("minimap")).toBe(false)
				-- le serveur démarre la chaîne d'accueil
				patch(c, { onboarding = { step = 1, p = 0 } })
				run(c, 2)
				expect(c.Onboarding.step()).toBe(1)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
				local hint = c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint
				expect(hint.Visible).toBe(true)
				expect(hint.Text.Text).toBe("Catch the Puffkins")
				local st = c.Onboarding._state()
				expect(st.footMode).toBe("toPuffkins")
				expect(#st.footprints).toBe(6)
				for _, part in st.footprints do
					expect(part.Transparency).toBe(0)
					expect(part.Anchored and not part.CanCollide).toBe(true)
				end
				expect(st.folder.Name).toBe("ClientOnboarding")
			end
		)

		it("Mouvement réduit : pas de travelling, HUD tout de suite", function()
			local c = setup({ reduced = true })
			local camera = c.h.workspace.CurrentCamera
			load(c, { onboarding = { step = 1, p = 0 } })
			run(c, 1)
			expect(camera.CameraType).toBe(Enum.CameraType.Custom)
			expect(c.HUD.isRevealed("glow")).toBe(true)
		end)

		it(
			"file pleine → retour à la porte (empreintes inversées, arche, faisceau) ; parade → Améliorer",
			function()
				local c = setup({ reduced = true })
				load(c, { onboarding = { step = 1, p = 0 } })
				run(c, 1)
				c.length = 3
				c.WSC.LineOp:Fire(1, { op = "add", slot = 1, ver = 3, codes = { 1 }, ids = { 0 } })
				run(c, 1)
				expect(c.Onboarding.currentHint()).toBe("onboarding.goHome")
				local st = c.Onboarding._state()
				expect(st.footMode).toBe("toGate")
				expect(#st.archBalls).toBe(7)
				expect(st.archBalls[1].Transparency).toBe(0)
				expect(st.beam.Enabled).toBe(true)
				expect(st.beam.Attachment0.Parent).toBe(c.h.localPlayer.Character.HumanoidRootPart)
				-- réapparition : le faisceau suit le nouveau personnage
				c.h:respawn(c.h.localPlayer)
				c.h.localPlayer.Character.HumanoidRootPart.CFrame =
					CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
				run(c, 1)
				expect(st.beam.Attachment0.Parent).toBe(c.h.localPlayer.Character.HumanoidRootPart)
				-- première parade : file vide, icône Améliorer avec la main, carte unique
				c.length = 0
				patch(c, { stats = { parades = 1, catches = 3 } })
				run(c, 1)
				expect(c.HUD.isRevealed("rail.Upgrades")).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.tapUpgrade")
				expect(c.Onboarding._state().attention["rail.Upgrades"]).toBe(true)
				expect(c.Onboarding._state().footMode).toBeNil()
				expect(c.Onboarding._state().beam.Enabled).toBe(false)
				c.Input.togglePanel("Upgrades")
				run(c, 1)
				expect(c.panelCalls[1].args.focus).toBe("conga")
				expect(c.Onboarding.currentHint()).toBe("onboarding.buyConga")
				expect(c.Onboarding._state().attention["rail.Upgrades"]).toBe(false)
				-- achat : suivi de quête, plus de carte unique, flèche vers le Nebby le plus proche
				c.Panels.close()
				wild(c, 9, 1, Vector3.new(0, 0, 0))
				wild(c, 10, 1, c.WorldLayout.gateCFrame(1).Position + Vector3.new(20, 0, 0))
				patch(c, { upgrades = { conga = 1, stride = 0, lure = 0, perches = 0, guard = 0 } })
				run(c, 2)
				expect(c.HUD.isRevealed("questTracker")).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.findNebbies")
				expect(c.Onboarding.guide()).toBe("toNebbies")
				local arrow = c.Onboarding._state().arrowParts
				expect(#arrow).toBe(3)
				expect(arrow[1].Transparency).toBe(0)
				c.Input.togglePanel("Upgrades")
				expect(c.panelCalls[2].args).toBeNil()
			end
		)

		it(
			"Q4 : pilier bleu sur le Rare, Stardust affichée ; Q5 : Collection et le Dash pulse une fois",
			function()
				local c = setup({ reduced = true })
				load(c, { onboarding = { step = 1, p = 0 } })
				run(c, 1)
				patch(c, {
					onboarding = { step = 4, p = 0 },
					stats = { parades = 3, catches = 12 },
					upgrades = { conga = 2, stride = 0, lure = 0, perches = 0, guard = 0 },
				})
				local rare = speciesOfRarity(c, 3)
				local spot = c.WorldLayout.gateCFrame(1).Position + Vector3.new(30, 0, 30)
				wild(c, 12, rare, spot, true)
				wild(c, 13, 1, c.WorldLayout.gateCFrame(1).Position + Vector3.new(10, 0, 0))
				run(c, 2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catchRare")
				expect(c.Onboarding.guide()).toBe("toRare")
				local pillar = c.Onboarding._state().pillar
				expect(pillar.Transparency < 1).toBe(true)
				expect(pillar.Position.X).toBeNear(spot.X, 1e-3)
				expect(pillar.Position.Z).toBeNear(spot.Z, 1e-3)
				expect(c.HUD.isRevealed("stardust")).toBe(true)
				expect(c.HUD.isRevealed("rail.Collection")).toBe(false)
				c.wilds[12] = nil
				c.WSC.WildRemoved:Fire(12, "caught", 1)
				run(c, 2)
				expect(c.Onboarding.guide()).toBe("toNebbies")
				expect(c.Onboarding._state().pillar.Transparency).toBe(1)
				patch(c, { onboarding = { step = 5, p = 0 } })
				run(c, 1)
				expect(c.HUD.isRevealed("rail.Collection")).toBe(true)
				expect(c.Onboarding._state().attention.dash).toBe(true)
				for _ = 1, 30 do
					c.h:step(1 / 15, 1)
				end
				expect(c.Onboarding._state().attention.dash).toBe(false)
			end
		)
	end)

	describe("Onboarding › joueur qui revient, fin, robustesse", function()
		it("accueil terminé : tout le HUD sans animation ni travelling, aucune instruction", function()
			local c = setup()
			local camera = c.h.workspace.CurrentCamera
			load(c, { onboarding = { step = 8, p = 0 }, stats = { parades = 40 } })
			run(c, 2)
			expect(camera.CameraType).toBe(Enum.CameraType.Custom)
			for _, e in c.Plan.ALL do
				expect({ e = e, shown = c.HUD.isRevealed(e) }).toEqual({ e = e, shown = true })
			end
			expect(c.Onboarding.currentHint()).toBeNil()
			expect(c.Onboarding.guide()).toBeNil()
		end)

		it("pas la première session : HUD complet, l'accueil continue", function()
			local c = setup({ reduced = true })
			-- l'instantané d'arrivée est envoyé AVANT le +1 de la session courante (QuestService, sur
			-- DataService.Loaded) : sessions = 1 dans l'instantané = une session déjà jouée
			load(c, {
				onboarding = { step = 1, p = 0 },
				rookie = { sessions = 1, playSeconds = 100, done = false },
			})
			run(c, 1)
			expect(c.HUD.isRevealed("rail.Shop")).toBe(true)
			patch(c, { rookie = { sessions = 2, playSeconds = 100, done = false } })
			run(c, 1)
			expect(c.HUD.isRevealed("rail.Shop")).toBe(true)
			-- pas de Puffkins de bienvenue hors première session : guidé vers les Nebbies sauvages
			expect(c.Onboarding.currentHint()).toBe("onboarding.findNebbies")
			expect(c.Onboarding._state().footMode).toBeNil()
		end)

		it(
			"première session : le +1 de session reçu après l'instantané ne la change pas en retour",
			function()
				local c = setup({ reduced = true })
				load(c, { onboarding = { step = 0, p = 0 } })
				run(c, 1)
				patch(c, {
					onboarding = { step = 1, p = 0 },
					rookie = { sessions = 1, playSeconds = 0, done = false },
					stats = { sessions = 1, parades = 0, catches = 0, playSeconds = 0 },
				})
				run(c, 2)
				expect(c.HUD.isRevealed("rail.Shop")).toBe(false)
				expect(c.HUD.isRevealed("glow")).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
				expect(c.Onboarding._state().footMode).toBe("toPuffkins")
			end
		)

		it(
			"profil reçu avant le personnage : le travelling attend le personnage (attente bornée)",
			function()
				local c = setup()
				local camera = c.h.workspace.CurrentCamera
				local types = {}
				camera:GetPropertyChangedSignal("CameraType"):Connect(function()
					table.insert(types, camera.CameraType)
				end)
				c.h.localPlayer.Character = nil
				load(c)
				run(c, 10) -- 0,33 s sans personnage : ni travelling, ni HUD
				expect(#types).toBe(0)
				expect(c.HUD.isRevealed("glow")).toBe(false)
				c.h:respawn(c.h.localPlayer)
				c.h.localPlayer.Character.HumanoidRootPart.CFrame =
					CFrame.new(c.WorldLayout.gateCFrame(1).Position + Vector3.new(0, 3, 0))
				run(c, 4)
				expect(types[1]).toBe(Enum.CameraType.Scriptable)
				expect(camera.CameraType).toBe(Enum.CameraType.Custom)
				expect(c.HUD.isRevealed("glow")).toBe(true)
				expect(c.HUD.isRevealed("dash")).toBe(true)
			end
		)

		it("personnage jamais apparu : HUD de base après l'attente, sans travelling", function()
			local c = setup()
			local camera = c.h.workspace.CurrentCamera
			c.h.localPlayer.Character = nil
			load(c)
			run(c, 30) -- 1 s
			expect(c.HUD.isRevealed("glow")).toBe(false)
			run(c, 60) -- 3 s au total (> 2,5 s)
			expect(c.HUD.isRevealed("glow")).toBe(true)
			expect(camera.CameraType).toBe(Enum.CameraType.Custom)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it(
			"filet de sécurité du travelling : le tween de caméra est annulé avant de rendre la main",
			function()
				local c = setup()
				local Juice = c.h:require(CLIENT .. "UI.Juice")
				local camera = c.h.workspace.CurrentCamera
				-- tweens de caméra qui ne se terminent jamais (appareil qui rame)
				local stuck = {}
				local original = Juice.tween
				Juice.tween = function(inst, duration, props, ...)
					if inst == camera then
						table.insert(stuck, "started")
						local never = {
							Once = function() end,
							Connect = function() end,
						}
						return {
							Completed = never,
							PlaybackState = Enum.PlaybackState.Playing,
							Cancel = function(self)
								self.PlaybackState = Enum.PlaybackState.Cancelled
								table.insert(stuck, "cancelled")
							end,
						}
					end
					return original(inst, duration, props, ...)
				end
				load(c)
				run(c, 2)
				expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
				expect(c.HUD.isRevealed("glow")).toBe(false)
				run(c, 100) -- > 3 s : filet de sécurité
				expect(camera.CameraType).toBe(Enum.CameraType.Custom)
				expect(table.find(stuck, "cancelled") ~= nil).toBe(true)
				expect(c.HUD.isRevealed("glow")).toBe(true)
			end
		)

		it(
			"10 min de jeu : « Ton Nid travaille même quand tu dors » pendant 6 s, une seule fois",
			function()
				local c = setup({ reduced = true })
				load(c, { onboarding = { step = 8, p = 0 } })
				run(c, 1)
				c.Clock.advance(600)
				run(c, 1)
				expect(c.Onboarding.currentHint()).toBe("onboarding.nestWorks")
				c.Clock.advance(7)
				run(c, 1)
				expect(c.Onboarding.currentHint()).toBeNil()
				c.Clock.advance(600)
				run(c, 1)
				expect(c.Onboarding.currentHint()).toBeNil()
			end
		)

		it("profil illisible, Nid inconnu, personnage absent : aucune erreur", function()
			local c = setup({ reduced = true })
			c.slot = 0
			c.h.localPlayer.Character = nil
			load(c, { onboarding = "x", stats = 5, upgrades = { conga = 0 / 0 }, rookie = false })
			run(c, 3)
			expect(c.Onboarding.step()).toBe(0)
			patch(c, { onboarding = { step = 1, p = 0 } })
			c.length = 5
			run(c, 3)
			expect(c.Onboarding.currentHint() ~= nil).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)

		it("langue : l'instruction est retraduite", function()
			local c = setup({ reduced = true })
			load(c, { onboarding = { step = 1, p = 0 } })
			run(c, 1)
			c.Prefs._onSettings({ lang = "fr" })
			c.h:settle(1)
			local L = c.h:require("ReplicatedStorage.Shared.Localization")
			expect(c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint.Text.Text).toBe(
				L.get("fr", "onboarding.catch")
			)
		end)
	end)
end
