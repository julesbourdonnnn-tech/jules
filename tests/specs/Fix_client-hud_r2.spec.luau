--!nocheck
-- QA ronde 2, paquet « client-hud » :
--   * OnboardingController : les règles de la ronde 1 (Hud/OnboardingPlan) reçoivent enfin leurs faits
--     depuis le terrain (gather) — Rare de Q4 déjà dans la file → retour au Nid ; Q6 sans météo →
--     « Météo bientôt » et pastille d'événement qui pulse ; Nebby météo → pilier + flèche ; Comète au
--     sol → « Rejoins la Comète » + flèche ; Puffkins disparus → Nebbies sauvages ; première parade
--     maigre → Nebbies jusqu'au prix de Conga +1 (GDD §3 : instruction toujours réalisable)
--   * HUD : sur les téléphones de 360-390 dp de haut, le Dash (au-dessus du bouton de saut) ne
--     recouvre plus le suivi de quête ni les indicateurs d'état (colonne à gauche de la minicarte),
--     positions du GDD rétablies quand la place revient (GDD §10.1, §10.2)
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- =========================================================================================
	-- OnboardingController : faits observés
	-- =========================================================================================

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
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
			codes = {},
			wilds = {},
			events = nil,
			cometPos = nil,
			open = nil,
		}
		-- isolation : paquets client-world et client-panels remplacés
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return c.slot
		end
		c.WSC.lineLength = function(slot)
			return if slot == c.slot then #c.codes else 0
		end
		c.WSC.line = function(slot)
			if slot ~= c.slot then
				return nil
			end
			return { slot = slot, userId = 1, ver = #c.codes, codes = c.codes }
		end
		c.WSC.wilds = function()
			return c.wilds
		end
		c.WSC.wildPosition = function(w)
			return w.anchor
		end
		c.WSC.events = function()
			return c.events
		end
		c.WSC.cometPosition = function()
			return c.cometPos
		end
		c.Panels.open = function(name)
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
		if opts.reduced ~= false then
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

	local function load(c, over)
		local p = Schema.defaults()
		for k, v in over or {} do
			p[k] = v
		end
		c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", p)
		c.h:settle(1)
	end

	local function patch(c, data)
		c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", data, {})
		c.h:settle(1)
	end

	-- images de 1/30 s ; 15 images = 0,5 s (> réévaluation périodique de 0,4 s)
	local function run(c, n)
		for _ = 1, n or 3 do
			c.h:step(1 / 30, 1)
			c.h:settle(1)
		end
	end

	local function wild(c, id, code, pos, personal)
		c.wilds[id] = {
			id = id,
			code = code,
			anchor = pos,
			seed = 1,
			t0 = T0,
			expiresAt = T0 + 600,
			dizzyUntil = 0,
			prioritySlot = 0,
			personal = personal == true,
		}
		c.WSC.WildAdded:Fire(c.wilds[id])
	end

	local function unwild(c, id, reason)
		c.wilds[id] = nil
		c.WSC.WildRemoved:Fire(id, reason or "expired", 0)
	end

	local function lineOp(c)
		c.WSC.LineOp:Fire(c.slot, { op = "add", slot = c.slot, ver = #c.codes, codes = {}, ids = {} })
	end

	local function placePlayer(c, pos)
		c.h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	end

	local function rareSpecies(c)
		return c.Nebbies.speciesOfRarity(3)[1]
	end

	local function commonSpecies(c)
		return c.Nebbies.speciesOfRarity(1)[1]
	end

	-- direction au sol de la flèche (fût) comparée à la direction attendue
	local function arrowToward(c, target)
		local st = c.Onboarding._state()
		local shaft = st.arrowParts[1]
		if shaft == nil or shaft.Transparency >= 1 then
			return false
		end
		local root = c.h.localPlayer.Character.HumanoidRootPart.Position
		local want = Vector3.new(target.X - root.X, 0, target.Z - root.Z).Unit
		local look = shaft.CFrame.LookVector
		local got = Vector3.new(look.X, 0, look.Z).Unit
		return want:Dot(got) > 0.97
	end

	local function hudAttention(c, element)
		local e = c.HUD._state().elements[element]
		return e ~= nil and e.attention == true
	end

	local Q6 = {
		onboarding = { step = 6, p = 0 },
		stats = { parades = 6, catches = 30 },
		upgrades = { conga = 2, stride = 1, lure = 0, perches = 0, guard = 0 },
	}

	local function eventState(over)
		local ev = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 3 }
		for k, v in over or {} do
			ev[k] = v
		end
		return ev
	end

	describe("Fix client-hud r2 › Onboarding Q4 : le Rare déjà dans la file", function()
		it(
			"Rare attrapé (file 2/5) → « Rentre au Nid » et flèche vers la porte, pas vers un autre Rare",
			function()
				local c = setup()
				load(c, { onboarding = { step = 1, p = 0 } })
				run(c, 1)
				patch(c, {
					onboarding = { step = 4, p = 0 },
					stats = { parades = 3, catches = 12 },
					upgrades = { conga = 2, stride = 0, lure = 0, perches = 0, guard = 0 },
				})
				local gate = c.WorldLayout.gateCFrame(1).Position
				local player = gate + Vector3.new(40, 0, 0)
				placePlayer(c, player)
				local rare = rareSpecies(c)
				local mine = player + Vector3.new(20, 0, 20)
				local public = player + Vector3.new(-60, 0, 60) -- autre Rare public, ~85 studs
				wild(c, 12, c.Nebbies.pack(rare, 0, 0), mine, true)
				wild(c, 14, c.Nebbies.pack(rare, 0, 0), public, false)
				c.codes = { c.Nebbies.pack(commonSpecies(c), 0, 0) }
				lineOp(c)
				run(c, 2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catchRare")
				expect(c.Onboarding.guide()).toBe("toRare")
				local pillar = c.Onboarding._state().pillar
				expect(pillar.Position.X).toBeNear(mine.X, 1e-3)
				-- le Rare personnel est attrapé : il est DANS la file (2/5, pas pleine)
				c.codes = { c.Nebbies.pack(commonSpecies(c), 0, 0), c.Nebbies.pack(rare, 0, 0) }
				unwild(c, 12, "caught")
				lineOp(c)
				run(c, 2)
				expect(c.Onboarding._state().facts.goalInLine).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.goHome")
				expect(c.Onboarding.guide()).toBe("toGate")
				expect(c.Onboarding._state().pillar.Transparency).toBe(1)
				expect(arrowToward(c, gate)).toBe(true)
				expect(arrowToward(c, public)).toBe(false)
				-- la file est coupée / vidée sans parade : on repart chercher un Rare (le public)
				c.codes = {}
				lineOp(c)
				run(c, 2)
				expect(c.Onboarding._state().facts.goalInLine).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catchRare")
				expect(c.Onboarding.guide()).toBe("toRare")
				expect(c.Onboarding._state().pillar.Position.X).toBeNear(public.X, 1e-3)
			end
		)

		it("Commun, Peu commun dans la file : pas encore l'objectif ; codes illisibles ignorés", function()
			local c = setup()
			load(c, {
				onboarding = { step = 4, p = 0 },
				stats = { parades = 3, catches = 12 },
				upgrades = { conga = 2, stride = 0, lure = 0, perches = 0, guard = 0 },
				rookie = { sessions = 1, playSeconds = 100, done = false },
			})
			run(c, 2)
			c.codes = {
				c.Nebbies.pack(commonSpecies(c), 0, 0),
				c.Nebbies.pack(c.Nebbies.speciesOfRarity(2)[1], 0, 0),
				"x",
				0 / 0,
				-5,
				math.huge,
			}
			c.WSC.lineLength = function()
				return 2
			end
			lineOp(c)
			run(c, 2)
			expect(c.Onboarding._state().facts.goalInLine).toBe(false)
			expect(c.Onboarding.currentHint()).toBe("onboarding.catchRare")
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("Fix client-hud r2 › Onboarding Q6 : météo ou Comète", function()
		it(
			"ni météo ni Comète → « Météo bientôt », pastille d'événement qui pulse, aucun guidage",
			function()
				local c = setup()
				load(c, Q6)
				c.events = eventState()
				run(c, 15)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				expect(c.Onboarding.guide()).toBeNil()
				expect(c.Onboarding._state().attention.eventPill).toBe(true)
				expect(hudAttention(c, "eventPill")).toBe(true)
				expect(c.HUD.isRevealed("eventPill")).toBe(true)
				local hint = c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint
				expect(hint.Text.Text).toBe("☁ Weather soon!")
				expect(hint.Icon.Text ~= "★").toBe(true)
				-- aucune pièce de guidage visible
				for _, part in c.Onboarding._state().arrowParts do
					expect(part.Transparency).toBe(1)
				end
			end
		)

		it(
			"fenêtre météo (Aurora) → consigne d'origine, la pastille cesse de pulser ; Nebby météo → pilier + flèche",
			function()
				local c = setup()
				load(c, Q6)
				c.events = eventState()
				run(c, 15)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				c.events = eventState({
					weather = { key = "aurora", form = 1, startsAt = T0 - 5, endsAt = T0 + 145 },
				})
				run(c, 15)
				expect(c.Onboarding._state().facts.weatherActive).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.weather")
				expect(c.Onboarding.guide()).toBe("toNebbies")
				expect(c.Onboarding._state().attention.eventPill).toBe(false)
				expect(hudAttention(c, "eventPill")).toBe(false)
				-- un Nebby météo (forme 1) apparaît, plus loin qu'un Commun ordinaire
				local gate = c.WorldLayout.gateCFrame(1).Position
				local plain = gate + Vector3.new(12, 0, 0)
				local storm = gate + Vector3.new(-30, 0, 25)
				wild(c, 30, c.Nebbies.pack(commonSpecies(c), 0, 0), plain, false)
				wild(c, 31, c.Nebbies.pack(commonSpecies(c), 1, 0), storm, false)
				run(c, 2)
				expect(c.Onboarding._state().facts.weatherTarget).toBe(true)
				expect(c.Onboarding.guide()).toBe("toWeather")
				local pillar = c.Onboarding._state().pillar
				expect(pillar.Transparency < 1).toBe(true)
				expect(pillar.Position.X).toBeNear(storm.X, 1e-3)
				expect(pillar.Position.Z).toBeNear(storm.Z, 1e-3)
				expect(arrowToward(c, storm)).toBe(true)
				-- attrapé : plus de cible ; la fenêtre est encore ouverte → Nebbies
				unwild(c, 31, "caught")
				run(c, 2)
				expect(c.Onboarding.guide()).toBe("toNebbies")
				expect(c.Onboarding._state().pillar.Transparency).toBe(1)
				-- fenêtre terminée : on attend la suivante
				c.Clock.advance(150)
				run(c, 15)
				expect(c.Onboarding._state().facts.weatherActive).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
			end
		)

		it(
			"Pluie de météores (sans forme) : « Météo bientôt » ; un Nebby météo qui traîne reste une cible",
			function()
				local c = setup()
				load(c, Q6)
				c.events = eventState({ weather = { key = "meteor", startsAt = T0 - 5, endsAt = T0 + 145 } })
				run(c, 15)
				expect(c.Onboarding._state().facts.weatherActive).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				-- Nebby de forme Frost resté de la fenêtre précédente : il compte encore pour Q6
				local spot = c.WorldLayout.gateCFrame(1).Position + Vector3.new(25, 0, -20)
				wild(c, 40, c.Nebbies.pack(commonSpecies(c), 2, 0), spot, false)
				run(c, 2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.weather")
				expect(c.Onboarding.guide()).toBe("toWeather")
				expect(c.Onboarding._state().attention.eventPill).toBe(false)
			end
		)

		it(
			"Comète au sol puis portée → « Rejoins la Comète » et flèche ; encaissée → attente",
			function()
				local c = setup()
				load(c, Q6)
				local gate = c.WorldLayout.gateCFrame(1).Position
				local impact = Vector3.new(20, 0, -30)
				local comet = {
					id = 3,
					phase = "warn",
					x = impact.X,
					z = impact.Z,
					code = 1,
					warnAt = T0 - 2,
					impactAt = T0 + 6,
					burstAt = T0 + 81,
				}
				c.events = eventState({ comet = comet })
				c.cometPos = impact + Vector3.new(0, 200, 0)
				run(c, 15)
				-- alerte (Comète encore dans le ciel) : rien à rejoindre pour l'instant
				expect(c.Onboarding._state().facts.cometActive).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				comet.phase = "ground"
				c.cometPos = impact
				run(c, 15)
				expect(c.Onboarding._state().facts.cometActive).toBe(true)
				expect(c.Onboarding.currentHint()).toBe("onboarding.joinComet")
				expect(c.Onboarding.guide()).toBe("toComet")
				expect(c.h.localPlayer.PlayerGui.Onboarding.Safe.Hint.Icon.Text ~= "★").toBe(true)
				expect(arrowToward(c, impact)).toBe(true)
				expect(c.Onboarding._state().attention.eventPill).toBe(false)
				-- portée par un autre joueur : la flèche suit le porteur
				comet.phase = "carried"
				comet.carrierId = 77
				local carrier = gate + Vector3.new(-40, 0, 10)
				c.cometPos = carrier + Vector3.new(0, 6, 0)
				run(c, 2)
				expect(c.Onboarding.guide()).toBe("toComet")
				expect(arrowToward(c, carrier)).toBe(true)
				-- réapparition : la flèche suit le nouveau personnage
				c.h:respawn(c.h.localPlayer)
				placePlayer(c, gate + Vector3.new(30, 0, 30))
				run(c, 2)
				expect(arrowToward(c, carrier)).toBe(true)
				-- encaissée : plus de Comète
				comet.phase = "banked"
				c.cometPos = nil
				run(c, 15)
				expect(c.Onboarding._state().facts.cometActive).toBe(false)
				expect(c.Onboarding.currentHint()).toBe("onboarding.waitWeather")
				for _, part in c.Onboarding._state().arrowParts do
					expect(part.Transparency).toBe(1)
				end
			end
		)

		it(
			"états d'événement limites (clé inconnue, fenêtre passée ou inversée, phase inconnue)",
			function()
				local c = setup()
				load(c, Q6)
				local function comet(phase, carrier)
					return {
						id = 9,
						phase = phase,
						x = 10,
						z = 10,
						code = 1,
						warnAt = T0 - 20,
						impactAt = T0 - 12,
						burstAt = T0 + 60,
						carrierId = carrier,
					}
				end
				local cases = {
					-- météo d'une version future : forme annoncée → fenêtre active
					{
						ev = { weather = { key = "zzz", form = 3, startsAt = T0 - 1, endsAt = T0 + 10 } },
						hint = "onboarding.weather",
					},
					{
						ev = { weather = { key = "zzz", startsAt = T0 - 1, endsAt = T0 + 10 } },
						hint = "onboarding.waitWeather",
					},
					{
						ev = { weather = { key = "aurora", form = 1, startsAt = T0 + 50, endsAt = T0 + 200 } },
						hint = "onboarding.waitWeather",
					},
					{
						ev = { weather = { key = "aurora", form = 1, startsAt = T0 + 5, endsAt = T0 - 5 } },
						hint = "onboarding.waitWeather",
					},
					{
						ev = { weather = { key = "frost", form = 2, startsAt = T0 - 150, endsAt = T0 } },
						hint = "onboarding.waitWeather",
					},
					{ ev = { comet = comet("burst") }, hint = "onboarding.waitWeather" },
					{ ev = { comet = comet("zzz") }, hint = "onboarding.waitWeather" },
					-- porteur inconnu (parti) : la Comète reste à rejoindre, flèche masquée sans position
					{ ev = { comet = comet("carried", 4242) }, hint = "onboarding.joinComet" },
				}
				for i, case in cases do
					c.events = eventState(case.ev)
					c.cometPos = nil
					run(c, 15)
					expect({ case = i, hint = c.Onboarding.currentHint() }).toEqual({
						case = i,
						hint = case.hint,
					})
				end
				for _, part in c.Onboarding._state().arrowParts do
					expect(part.Transparency).toBe(1)
				end
				expect(#c.h:signalErrors()).toBe(0)
			end
		)
	end)

	describe("Fix client-hud r2 › Onboarding Q1 : Puffkins de bienvenue réels", function()
		local function firstSession(c)
			load(c, { onboarding = { step = 0, p = 0 } })
			run(c, 1)
			patch(c, {
				onboarding = { step = 1, p = 0 },
				rookie = { sessions = 1, playSeconds = 0, done = false },
				stats = { sessions = 1, parades = 0, catches = 0, playSeconds = 0 },
			})
			run(c, 1)
		end

		local function spawnPuffkins(c)
			local code = c.Nebbies.pack(c.Nebbies.Named.Welcome, 0, 0)
			local points = c.WorldLayout.welcomePoints(1, 3)
			for i, p in points do
				wild(c, 100 + i, code, p, true)
			end
			return points
		end

		it(
			"Puffkins disparus (réinitialisation, durée de vie) → « Trouve des Nebbies » et flèche",
			function()
				local c = setup()
				firstSession(c)
				spawnPuffkins(c)
				run(c, 2)
				expect(c.Onboarding._state().facts.puffkinsLeft).toBe(3)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
				expect(c.Onboarding._state().footMode).toBe("toPuffkins")
				-- un Puffkin attrapé, les deux autres perdus (réinitialisation : file perdue puis délai)
				c.codes = { c.Nebbies.pack(c.Nebbies.Named.Welcome, 0, 0) }
				unwild(c, 101, "caught")
				lineOp(c)
				run(c, 2)
				expect(c.Onboarding._state().facts.puffkinsLeft).toBe(2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
				c.codes = {}
				lineOp(c)
				unwild(c, 102, "expired")
				unwild(c, 103, "expired")
				local gate = c.WorldLayout.gateCFrame(1).Position
				local spot = gate + Vector3.new(-25, 0, 18)
				wild(c, 200, c.Nebbies.pack(commonSpecies(c), 0, 0), spot, false)
				run(c, 2)
				expect(c.Onboarding._state().facts.puffkinsLeft).toBe(0)
				expect(c.Onboarding.currentHint()).toBe("onboarding.findNebbies")
				expect(c.Onboarding.guide()).toBe("toNebbies")
				-- plus d'empreintes vers la place vide : flèche vers le Nebby sauvage
				expect(c.Onboarding._state().footMode).toBeNil()
				for _, part in c.Onboarding._state().footprints do
					expect(part.Transparency).toBe(1)
				end
				expect(arrowToward(c, spot)).toBe(true)
				-- 3 sauvages attrapés : retour à la porte (empreintes inversées, arche)
				c.codes = { 1, 1, 1 }
				lineOp(c)
				run(c, 2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.goHome")
				expect(c.Onboarding.guide()).toBe("toGate")
			end
		)

		it("Puffkins jamais reçus : consigne d'origine pendant l'attente, puis Nebbies sauvages", function()
			local c = setup()
			firstSession(c)
			run(c, 2)
			-- les Puffkins arrivent souvent après l'étape 1 : pas de « Trouve des Nebbies » prématuré
			expect(c.Onboarding._state().facts.puffkinsLeft).toBeNil()
			expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
			c.Clock.advance(1)
			run(c, 15)
			expect(c.Onboarding.currentHint()).toBe("onboarding.catch")
			c.Clock.advance(10)
			run(c, 15)
			expect(c.Onboarding._state().facts.puffkinsLeft).toBe(0)
			expect(c.Onboarding.currentHint()).toBe("onboarding.findNebbies")
			expect(c.Onboarding.guide()).toBe("toNebbies")
		end)

		it("empreintes vers les Puffkins réels (déplacés), pas vers la place théorique", function()
			local c = setup()
			firstSession(c)
			local code = c.Nebbies.pack(c.Nebbies.Named.Welcome, 0, 0)
			local gate = c.WorldLayout.gateCFrame(1).Position
			local target = gate + Vector3.new(-14, 0, 6)
			wild(c, 101, code, target, true)
			run(c, 2)
			local st = c.Onboarding._state()
			expect(st.footMode).toBe("toPuffkins")
			local last = st.footprints[#st.footprints].Position
			local dir = Vector3.new(target.X - gate.X, 0, target.Z - gate.Z).Unit
			local got = Vector3.new(last.X - gate.X, 0, last.Z - gate.Z).Unit
			expect(dir:Dot(got) > 0.95).toBe(true)
		end)

		it(
			"première parade maigre (1 Puffkin, Conga +1 pas payable) → Nebbies, puis Améliorer à 50 Glow",
			function()
				local c = setup()
				firstSession(c)
				spawnPuffkins(c)
				run(c, 2)
				-- 1 Puffkin paradé, les autres perdus : 23 Glow < 50
				for i = 1, 3 do
					unwild(c, 100 + i, "expired")
				end
				patch(c, { stats = { sessions = 1, parades = 1, catches = 1, playSeconds = 20 }, glow = 23 })
				run(c, 2)
				expect(c.Onboarding.currentHint()).toBe("onboarding.findNebbies")
				expect(c.Onboarding.guide()).toBe("toNebbies")
				expect(c.Onboarding._state().attention["rail.Upgrades"]).toBe(false)
				-- le Glow n'est pas observé : réévaluation périodique (0,4 s)
				patch(c, { glow = c.Formulas.upgradeCost("conga", 0) })
				run(c, 15)
				expect(c.Onboarding.currentHint()).toBe("onboarding.tapUpgrade")
				expect(c.Onboarding._state().attention["rail.Upgrades"]).toBe(true)
			end
		)
	end)

	-- =========================================================================================
	-- HUD : Dash et colonne de droite sur petit écran tactile
	-- =========================================================================================

	local function hudSetup()
		local h = Harness.new({ mode = "client", touch = true })
		h.localPlayer.LocaleId = "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Panels = h:require(CLIENT .. "Controllers.PanelController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Input = h:require(CLIENT .. "Controllers.InputController"),
			HUD = h:require(CLIENT .. "UI.HUD"),
		}
		c.VFX.playDash = function() end
		c.WSC.localSlot = function()
			return 1
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.Input.Init()
		c.HUD.Init()
		c.FX.Start()
		c.Input.Start()
		c.HUD.Start()
		c.HUD.revealAll()
		return c
	end

	local function hud(c)
		return c.h.localPlayer.PlayerGui.HUD.Safe
	end

	-- écran simulé : le moteur calcule AbsoluteSize (zone sous la barre Roblox) ; le bouton de saut
	-- tactile de Roblox fait 70 px à (1, −95, 1, −90) sur petit écran, 120 px à (1, −170, 1, −210) sinon
	local function screen(c, width, height, topbar)
		c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(width, height)
		local gui = c.h.localPlayer.PlayerGui.HUD
		gui.AbsoluteSize = Vector2.new(width, height - topbar)
		hud(c).AbsoluteSize = gui.AbsoluteSize
		local playerGui = c.h.localPlayer.PlayerGui
		local touchGui = playerGui:FindFirstChild("TouchGui")
		if touchGui == nil then
			touchGui = c.g.Instance.new("ScreenGui")
			touchGui.Name = "TouchGui"
			local frame = c.g.Instance.new("Frame")
			frame.Name = "TouchControlFrame"
			frame.Parent = touchGui
			local jump = c.g.Instance.new("ImageButton")
			jump.Name = "JumpButton"
			jump.Parent = frame
			touchGui.Parent = playerGui
		end
		local jump = touchGui.TouchControlFrame.JumpButton
		local small = math.min(width, height) < 500
		local size = if small then 70 else 120
		local offset = if small then Vector2.new(-95, -90) else Vector2.new(-170, -210)
		jump.AbsoluteSize = Vector2.new(size, size)
		jump.AbsolutePosition = Vector2.new(width, height - topbar) + offset
		c.HUD._layoutActions()
		c.h:settle(1)
	end

	-- rectangle d'un élément en px de référence du HUD (zone intérieure W × H)
	local function rect(c, holder)
		local gui = c.h.localPlayer.PlayerGui.HUD
		local k = c.Root.scale()
		local W = gui.AbsoluteSize.X / k - 24
		local H = gui.AbsoluteSize.Y / k - 16
		local p, s, a = holder.Position, holder.Size, holder.AnchorPoint
		local x = p.X.Scale * W + p.X.Offset - a.X * s.X.Offset
		local y = p.Y.Scale * H + p.Y.Offset - a.Y * s.Y.Offset
		return { x0 = x, y0 = y, x1 = x + s.X.Offset, y1 = y + s.Y.Offset, W = W, H = H }
	end

	local function overlap(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end

	local function inside(r)
		return r.x0 >= 0 and r.y0 >= 0 and r.x1 <= r.W + 1e-6 and r.y1 <= r.H + 1e-6
	end

	local function checkLayout(c, label)
		local dash = rect(c, hud(c).Dash)
		local ping = rect(c, hud(c).Ping)
		local tracker = rect(c, hud(c).QuestTracker)
		local status = rect(c, hud(c).Status)
		local pill = rect(c, hud(c).EventPill)
		local W = dash.W
		-- minicarte (écran Minimap, même échelle) : 150 × 150 en (−16, 16)
		local minimap = { x0 = W - 166, y0 = 16, x1 = W - 16, y1 = 166, W = W, H = dash.H }
		local named = {
			dash = dash,
			ping = ping,
			tracker = tracker,
			status = status,
			pill = pill,
			minimap = minimap,
		}
		local order = { "dash", "ping", "tracker", "status", "pill", "minimap" }
		for i, a in order do
			for j = i + 1, #order do
				local b = order[j]
				if not (a == "dash" and b == "ping") then
					expect({ screen = label, a = a, b = b, overlap = overlap(named[a], named[b]) }).toEqual({
						screen = label,
						a = a,
						b = b,
						overlap = false,
					})
				end
			end
		end
		for name, r in named do
			expect({ screen = label, name = name, inside = inside(r) }).toEqual({
				screen = label,
				name = name,
				inside = true,
			})
		end
		return named
	end

	describe("Fix client-hud r2 › HUD : le Dash ne recouvre plus la colonne de droite", function()
		it("800 × 360 (barre de 36 px) : suivi de quête et état hors du Dash et du Ping", function()
			local c = hudSetup()
			screen(c, 800, 360, 36)
			expect(c.Root.scale()).toBe(0.6)
			local r = checkLayout(c, "800x360")
			-- Dash placé comme le GDD l'exige (16 px au-dessus à gauche du bouton de saut ; décalages
			-- UDim entiers)
			expect(r.dash.x1).toBeNear(705 / 0.6 - 12 - 16, 1)
			expect(r.dash.y1).toBeNear(234 / 0.6 - 8 - 16, 1)
			-- le suivi de quête reste lisible : à droite de l'écran, à gauche de la minicarte
			expect(r.tracker.x1 <= r.minimap.x0 - 8 + 1e-6).toBe(true)
			expect(r.tracker.y0).toBe(16)
		end)

		it("800 × 360 avec la barre de 58 px : les indicateurs d'état quittent aussi le Dash", function()
			local c = hudSetup()
			screen(c, 800, 360, 58)
			local r = checkLayout(c, "800x360/58")
			expect(r.status.y1 <= r.dash.y0).toBe(true)
		end)

		it("autres téléphones (844 × 390, 780 × 360, 640 × 360) : aucun chevauchement", function()
			local c = hudSetup()
			for _, size in
				{ { 844, 390, 36 }, { 780, 360, 36 }, { 640, 360, 36 }, { 667, 375, 36 }, { 844, 390, 58 } }
			do
				screen(c, size[1], size[2], size[3])
				checkLayout(c, size[1] .. "x" .. size[2] .. "/" .. size[3])
			end
		end)

		it("place retrouvée (tablette, PC) : positions du GDD rétablies", function()
			local c = hudSetup()
			local tracker, status = hud(c).QuestTracker, hud(c).Status
			local trackerHome, statusHome = tracker.Position, status.Position
			expect(trackerHome).toEqual(UDim2.new(1, -16, 0, 16 + 150 + 8 + 48 + 30))
			expect(statusHome).toEqual(UDim2.new(1, -16, 0, 16 + 150 + 8))
			screen(c, 800, 360, 36)
			expect(tracker.Position ~= trackerHome).toBe(true)
			-- tablette 1024 × 768 : grand bouton de saut, colonne du GDD
			screen(c, 1024, 768, 36)
			expect(tracker.Position).toEqual(trackerHome)
			expect(status.Position).toEqual(statusHome)
			checkLayout(c, "1024x768")
			-- retour au téléphone puis clavier (Dash en bas à droite) sur un écran de PC
			screen(c, 800, 360, 36)
			expect(tracker.Position ~= trackerHome).toBe(true)
			c.h.game.UserInputService.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Keyboard)
			c.h:settle(1)
			c.h.workspace.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
			c.h.localPlayer.PlayerGui.HUD.AbsoluteSize = Vector2.new(1280, 684)
			c.HUD._layoutActions()
			expect(tracker.Position).toEqual(trackerHome)
			expect(status.Position).toEqual(statusHome)
		end)

		it("révélation après déplacement : le suivi glisse jusqu'à sa nouvelle place", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			local c = {
				h = h,
				g = h.globals,
				Root = h:require(CLIENT .. "UI.Root"),
				State = h:require(CLIENT .. "Controllers.StateController"),
				Prefs = h:require(CLIENT .. "Util.Prefs"),
				WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
				FX = h:require(CLIENT .. "UI.ScreenFX"),
				Input = h:require(CLIENT .. "Controllers.InputController"),
				HUD = h:require(CLIENT .. "UI.HUD"),
			}
			c.WSC.localSlot = function()
				return 1
			end
			c.Root.Init()
			c.State.Init()
			c.Prefs.Init()
			c.Prefs.Start()
			c.FX.Init()
			c.Input.Init()
			c.HUD.Init()
			c.FX.Start()
			c.Input.Start()
			c.HUD.Start()
			c.HUD.reveal("dash", false)
			screen(c, 800, 360, 36)
			local tracker = hud(c).QuestTracker
			local home = tracker.Position
			expect(tracker.Visible).toBe(false)
			c.HUD.reveal("questTracker", true)
			c.h:settle(2)
			expect(tracker.Visible).toBe(true)
			expect(tracker.Position).toEqual(home)
			checkLayout(c, "reveal")
			-- réévaluation périodique (1 s) : la place ne bouge pas tant que l'écran ne change pas
			c.h:step(1 / 10, 15)
			expect(tracker.Position).toEqual(home)
		end)
	end)
end
