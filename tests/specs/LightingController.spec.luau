--!nocheck
-- LightingController (paquet world, docs/04 §13.4, §10.4, GDD §11.3, §9.4) : préréglages (jour,
-- BOOP RUSH dès la sirène, Jelly Moon, fêtes, hiver), version discrète pour un nouveau (30 %, sans
-- vibration), AUCUN ciel de Lune ni costume si l'interrupteur du serveur est coupé (même en direct),
-- transitions (2 s, 4 s, fondu court en Mouvement réduit), flocons dans le quota de particules,
-- Graphismes légers, lumières de MON ranch et lampadaires dans leurs quotas, étiquettes du monde
-- traduites (EN / FR) en px TV, charges hostiles, stub de WorldStateController toléré, zéro trace.
local roblox = require("@lune/roblox")
local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Instants (UTC) : mardi 8/12/2026 10:02 (rien), sirène 10:04:55, samedi 12/12 16:02 (Lune,
	-- costume d'hiver en vigueur), dimanche 13/12 10:02 (hiver seul)
	local T_DAY = 1796724120
	local T_SIREN = T_DAY + 175
	local T_MOON = 1797091320
	local T_WINTER = 1797156120

	local function rgb(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end

	local function features(over)
		local f = {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
		for k, v in over or {} do
			f[k] = v
		end
		return f
	end

	local function payload(over)
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

	-- Client avec LightingController démarré ; `event` = EventState renvoyé par WorldStateController
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.console ~= false })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T_DAY)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local WSC = h:require(base .. "Controllers.WorldStateController")
		local QC = h:require(base .. "Controllers.QualityController")
		local Prefs = h:require(base .. "Util.Prefs")
		local Haptics = h:require(base .. "Util.Haptics")
		local current = opts.event
		if opts.stubEvent ~= false then
			WSC.event = function()
				return current
			end
		end
		if opts.budgets then
			QC.budgets = function()
				return opts.budgets
			end
		end
		Prefs.Init()
		-- profil du joueur (miroir StateController, DataSnapshot) : étape de l'accueil
		local State = h:require(base .. "Controllers.StateController")
		State.Init()
		if opts.profile then
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", opts.profile)
			h:settle(1)
		end
		local LC = h:require(base .. "Controllers.LightingController")
		local played = {}
		Haptics.Played:Connect(function(name)
			table.insert(played, name)
		end)
		if opts.before then
			opts.before(h)
		end
		LC.Init()
		if opts.quiet then
			LC.setQuiet(true) -- avant Start, comme OnboardingController dans la même image
		end
		LC.Start()
		local c = {
			h = h,
			LC = LC,
			Clock = Clock,
			WSC = WSC,
			Prefs = Prefs,
			played = played,
			setEvent = function(p)
				current = p
				WSC.EventChanged:Fire(p)
				h:settle(1)
			end,
			-- nouvelle étape de l'accueil (DataPatch du profil)
			setStep = function(step, done)
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", {
					onboarding = { step = step, done = done == true, demoDone = false },
				})
				h:settle(1)
			end,
		}
		return c
	end

	-- profils : un ancien (accueil fini) et un nouveau avant l'étape 9 de l'accueil
	local VETERAN = { coins = 0, onboarding = { step = 11, done = true, demoDone = true } }
	local NEWCOMER = { coins = 0, onboarding = { step = 3, done = false, demoDone = false } }

	local function zeroLog(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function lighting(h)
		return h.game.Lighting
	end

	-- Petit monde serveur répliqué (fixture) : 2 ranchs (le mien : n° 3), 20 lampadaires, une étiquette
	local function fixture(h)
		local CS = h.game.CollectionService
		local world = MockInstance.new("Folder")
		world.Name = "Wobbleton"
		local ranches = MockInstance.new("Folder")
		ranches.Name = "Ranches"
		ranches.Parent = world
		for _, slot in { 3, 4 } do
			local m = MockInstance.new("Model")
			m.Name = tostring(slot)
			m:SetAttribute("Slot", slot)
			m:SetAttribute("OwnerUserId", if slot == 3 then h.localPlayer.UserId else 999)
			for i = 1, 4 do
				local p = MockInstance.new("Part")
				p.Name = "Lantern" .. i
				p.Position = Vector3.new(slot * 100, 5, i)
				p.CFrame = CFrame.new(slot * 100, 5, i)
				local light = MockInstance.new("PointLight")
				light.Enabled = false
				CS:AddTag(light, "RanchLight")
				light.Parent = p
				p.Parent = m
			end
			m.Parent = ranches
		end
		local lamps = MockInstance.new("Folder")
		lamps.Name = "Lamps"
		lamps.Parent = world
		for i = 1, 20 do
			local bulb = MockInstance.new("Part")
			bulb.Name = "Bulb" .. i
			bulb.Position = Vector3.new(i * 10, 9, 0)
			bulb.CFrame = CFrame.new(i * 10, 9, 0)
			local light = MockInstance.new("PointLight")
			light.Enabled = true
			CS:AddTag(light, "LampLight")
			light.Parent = bulb
			bulb.Parent = lamps
		end
		local sign = MockInstance.new("Part")
		sign.Name = "Sign"
		sign:SetAttribute("LabelKey", "world.shop")
		sign:SetAttribute("LabelHeight", 2)
		sign.Parent = world
		world.Parent = h.game.Workspace
		h.localPlayer:SetAttribute("RanchSlot", 3)
		return world
	end

	describe("LightingController › préréglages", function()
		it("Init : effets dans Lighting, jour pastel du GDD (ClockTime 14,5, Brightness 2,5)", function()
			local c = client()
			local L = lighting(c.h)
			expect(c.LC.current()).toBe("day")
			expect(L.ClockTime).toBe(14.5)
			expect(L.Brightness).toBe(2.5)
			expect(rgb(L.Ambient)).toEqual({ 150, 140, 170 })
			expect(rgb(L.OutdoorAmbient)).toEqual({ 190, 180, 210 })
			expect(L.SquishyAtmosphere.ClassName).toBe("Atmosphere")
			expect(L.SquishyAtmosphere.Density).toBe(0.25)
			expect(L.SquishyBloom.Intensity).toBe(0.6)
			expect(L.SquishyColor.Saturation).toBe(0.2)
			expect(L.SquishySky.ClassName).toBe("Sky")
			zeroLog(c.h)
		end)

		it(
			"WorldStateController encore en stub (TODO) : jour simple, zéro erreur, zéro avertissement",
			function()
				local c = client({ stubEvent = false, t = T_MOON })
				c.LC.refresh()
				expect(c.LC.current()).toBe("day")
				zeroLog(c.h)
			end
		)

		it(
			"Jelly Moon : nuit, lune de 30, 4 000 étoiles, teinte violette ; interrupteur coupé → aucun ciel de Lune",
			function()
				local c = client({ t = T_MOON, event = payload() })
				c.LC.refresh()
				expect(c.LC.current()).toBe("moon")
				local L = lighting(c.h)
				expect(L.SquishySky.MoonAngularSize).toBe(30)
				expect(L.SquishySky.StarCount).toBe(4000)
				expect(rgb(L.SquishyColor.TintColor)).toEqual({ 200, 190, 255 })
				expect(L.ClockTime % 24).toBe(0)
				-- l'interrupteur est coupé en direct : retour au jour, sans ciel fantôme
				c.setEvent(payload({ features = features({ jellyMoon = false }) }))
				expect(c.LC.current()).toBe("day")
				expect(L.ClockTime).toBe(14.5)
				expect(L.SquishySky.MoonAngularSize).toBe(11)
				-- séance annoncée par le serveur (Lune forcée) mais interrupteur coupé : rien
				c.setEvent(payload({
					moon = { active = true, session = 1, endsAt = T_MOON + 600, nextAt = 0 },
					features = features({ jellyMoon = false }),
				}))
				expect(c.LC.current()).toBe("day")
				zeroLog(c.h)
			end
		)

		it(
			"BOOP RUSH : ciel rose dès la sirène (« on ») ; « off » : rien ; « events » : seulement avec la Lune",
			function()
				local c = client({ t = T_SIREN, event = payload() })
				c.LC.refresh()
				expect(c.LC.current()).toBe("rush")
				expect(rgb(lighting(c.h).SquishyColor.TintColor)).toEqual({ 255, 200, 225 })
				expect(rgb(lighting(c.h).SquishyAtmosphere.Color)).toEqual({ 255, 190, 220 })
				c.setEvent(payload({ features = features({ boopRush = "off" }) }))
				expect(c.LC.current()).toBe("day")
				c.setEvent(payload({ features = features({ boopRush = "events" }) }))
				expect(c.LC.current()).toBe("day")
				-- Rush forcé par un administrateur (EventState actif) en mode « on »
				c.Clock.freeze(T_DAY)
				c.setEvent(payload({
					rush = {
						active = true,
						index = 7,
						endsAt = T_DAY + 60,
						nextAt = 0,
						moonBoopable = false,
					},
				}))
				expect(c.LC.current()).toBe("rush")
				c.Clock.freeze(T_DAY + 61) -- fin du Rush sans message : retour au jour
				c.LC.refresh()
				expect(c.LC.current()).toBe("day")
				zeroLog(c.h)
			end
		)

		it(
			"version discrète (nouveau avant l'étape 9) : teinte à 30 %, aucune vibration de sirène",
			function()
				local c = client({ t = T_SIREN, event = payload(), quiet = true })
				c.LC.setQuiet(true)
				c.LC.refresh()
				c.h:step(0.5, 3)
				expect(c.LC.current()).toBe("rush")
				local tint = rgb(lighting(c.h).SquishyColor.TintColor)
				expect(tint).toEqual({
					255,
					math.floor(255 - 55 * 0.3 + 0.5),
					math.floor(255 - 30 * 0.3 + 0.5),
				})
				expect(#c.played).toBe(0)
				c.LC.setQuiet(false)
				expect(rgb(lighting(c.h).SquishyColor.TintColor)).toEqual({ 255, 200, 225 })
				zeroLog(c.h)
			end
		)

		it(
			"sirène : une vibration « rushSiren » par Rush (jamais deux), seulement pendant la sirène",
			function()
				local c = client({ t = T_SIREN, event = payload(), profile = VETERAN })
				c.LC.refresh()
				c.LC.refresh()
				c.h:step(0.1, 10)
				local n = 0
				for _, name in c.played do
					if name == "rushSiren" then
						n += 1
					end
				end
				expect(n).toBe(1)
				-- pendant le Rush lui-même (après la sirène) : plus de vibration
				c.Clock.freeze(T_SIREN + 30)
				c.LC.refresh()
				expect(#c.played).toBe(1)
				zeroLog(c.h)
			end
		)

		it(
			"nouveau d'après son profil (étape < 9), sans setQuiet : teinte à 30 %, aucune vibration de sirène",
			function()
				-- OnboardingController n'a pas (encore) appelé setQuiet : le profil suffit (GDD §3)
				local c = client({ t = T_SIREN, event = payload(), profile = NEWCOMER })
				c.LC.refresh()
				c.h:step(0.5, 4)
				expect(c.LC.current()).toBe("rush")
				expect(rgb(lighting(c.h).SquishyColor.TintColor)).toEqual({
					255,
					math.floor(255 - 55 * 0.3 + 0.5),
					math.floor(255 - 30 * 0.3 + 0.5),
				})
				expect(#c.played).toBe(0)
				-- étape 9 atteinte pendant cette sirène : ciel rose plein, mais aucune vibration tardive
				c.setStep(9, false)
				c.LC.refresh()
				c.h:step(0.5, 4)
				expect(rgb(lighting(c.h).SquishyColor.TintColor)).toEqual({ 255, 200, 225 })
				expect(#c.played).toBe(0)
				-- sirène suivante (1 h plus tard) : la vibration revient
				c.Clock.freeze(T_SIREN + 3600)
				c.LC.refresh()
				expect(c.played).toEqual({ "rushSiren" })
				zeroLog(c.h)
			end
		)

		it(
			"profil pas encore arrivé : aucune vibration ; un ancien dont le profil arrive pendant la sirène : une seule",
			function()
				local c = client({ t = T_SIREN, event = payload() })
				c.LC.refresh()
				c.h:step(0.5, 4)
				expect(#c.played).toBe(0)
				c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", VETERAN)
				c.h:settle(1)
				c.LC.refresh()
				c.h:step(0.5, 4)
				c.LC.refresh()
				expect(c.played).toEqual({ "rushSiren" })
				zeroLog(c.h)
			end
		)

		it(
			"profil abîmé (onboarding absent, étape NaN, mauvais types) : prudence, jamais d'erreur",
			function()
				for _, profile in
					{
						{ coins = 0 },
						{ onboarding = "x" },
						{ onboarding = { step = 0 / 0, done = "yes" } },
						{ onboarding = { step = math.huge } },
					}
				do
					local c = client({ t = T_SIREN, event = payload(), profile = profile })
					c.LC.refresh()
					c.h:step(0.5, 2)
					expect(c.LC.current()).toBe("rush")
					zeroLog(c.h)
				end
			end
		)

		it("fêtes (Wobble, Squish, administrateur) : lueur dorée (Bloom 0,8) jusqu'à leur fin", function()
			local c = client({
				event = payload({ boost = { kind = "squish", untilT = T_DAY + 600, byName = "Mia" } }),
			})
			c.LC.refresh()
			expect(c.LC.current()).toBe("party")
			expect(lighting(c.h).SquishyBloom.Intensity).toBe(0.8)
			expect(rgb(lighting(c.h).SquishyColor.TintColor)).toEqual({ 255, 240, 210 })
			c.Clock.freeze(T_DAY + 601)
			c.LC.refresh()
			expect(c.LC.current()).toBe("day")
			expect(lighting(c.h).SquishyBloom.Intensity).toBe(0.6)
			zeroLog(c.h)
		end)
	end)

	describe("LightingController › costume d'hiver", function()
		it(
			"interrupteur + calendrier : sucre glace, guirlandes, flocons dans le quota ; coupé en direct → plus rien",
			function()
				local c = client({
					t = T_WINTER,
					event = payload({ features = features({ costume = "winter2026" }) }),
				})
				c.LC.refresh()
				expect(c.LC.current()).toBe("winter")
				local winter = c.h.game.Workspace.ClientWorld:FindFirstChild("Winter")
				expect(winter ~= nil).toBe(true)
				local stats = c.LC.stats()
				expect(stats.winterParts).toBe(24 + 64 + 1)
				expect(stats.snow).toBe(true)
				expect(stats.snowRate * 3 <= 30 + 1e-9).toBe(true) -- quota « lighting » : 30 particules
				for _, p in winter:GetDescendants() do
					if p:IsA("BasePart") then
						expect(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch).toBe(
							true
						)
					end
				end
				-- les flocons suivent la caméra
				c.h.game.Workspace.CurrentCamera.CFrame = CFrame.new(100, 20, -50)
				c.h:step(1 / 60, 1)
				local snow = winter:FindFirstChild("Snow")
				expect(snow.CFrame.Position).toBe(Vector3.new(100, 45, -50))
				-- interrupteur coupé en direct : aucun costume fantôme
				c.setEvent(payload({ features = features({ costume = "" }) }))
				expect(c.LC.current()).toBe("day")
				expect(c.h.game.Workspace.ClientWorld:FindFirstChild("Winter")).toBeNil()
				zeroLog(c.h)
			end
		)

		it("hors calendrier, ou costume inconnu : aucun costume", function()
			local c =
				client({ t = T_DAY, event = payload({ features = features({ costume = "winter2026" }) }) })
			c.LC.refresh()
			expect(c.LC.current()).toBe("day")
			expect(
				c.h.game.Workspace:FindFirstChild("ClientWorld") == nil
					or c.h.game.Workspace.ClientWorld:FindFirstChild("Winter") == nil
			).toBe(true)
			c.Clock.freeze(T_WINTER)
			c.setEvent(payload({ features = features({ costume = "kings2027" }) }))
			expect(c.LC.current()).toBe("day")
			zeroLog(c.h)
		end)

		it("Graphismes légers ou qualité réduite : flocons coupés ou réduits au quota", function()
			local c = client({
				t = T_WINTER,
				event = payload({ features = features({ costume = "winter2026" }) }),
				budgets = {
					lightRange = 60,
					particles = 0.3,
					particleQuota = { vfx = 36, chase = 15, lighting = 9 },
					lightQuota = { world = 16, ranch = 4, squishies = 4 },
				},
			})
			c.LC.refresh()
			expect(c.LC.stats().snowRate * 3 <= 9 + 1e-9).toBe(true)
			c.Prefs._onSettings({ lowGraphics = true })
			c.h:settle(1)
			c.LC.refresh()
			expect(c.LC.stats().snow).toBe(false)
			expect(c.LC.stats().snowRate).toBe(0)
			zeroLog(c.h)
		end)
	end)

	describe("LightingController › transitions", function()
		local function capture(c)
			local times = {}
			local original = MockInstance.classMethods.TweenService.Create
			MockInstance.classMethods.TweenService.Create = function(self, inst, info, goals)
				if inst.ClassName == "Lighting" then
					table.insert(times, info.Time)
				end
				return original(self, inst, info, goals)
			end
			return times, function()
				MockInstance.classMethods.TweenService.Create = original
			end
		end

		it(
			"Rush 2 s, Lune 4 s ; Mouvement réduit : fondu court (0,5 s) ; ClockTime n'avance jamais à reculons",
			function()
				local c = client({ t = T_DAY, event = payload() })
				local times, restore = capture(c)
				c.Clock.freeze(T_SIREN)
				c.LC.refresh() -- jour → Rush
				c.Clock.freeze(T_MOON)
				c.LC.refresh() -- Rush → Lune
				expect(lighting(c.h).ClockTime).toBe(24) -- 14,5 → 24 (= minuit), jamais 14,5 → 0
				c.Prefs._onSettings({ reducedMotion = true })
				c.Clock.freeze(T_DAY)
				c.LC.refresh() -- Lune → jour, fondu court
				restore()
				expect(times).toEqual({ 2, 4, 0.5 })
				zeroLog(c.h)
			end
		)
	end)

	describe("LightingController › lumières et étiquettes", function()
		it(
			"mes 4 lumières de ranch allumées, celles des autres éteintes ; lampadaires ≤ quota (16)",
			function()
				local c = client({ before = fixture })
				c.LC.refresh()
				local stats = c.LC.stats()
				expect(stats.ranchLightsOn).toBe(4)
				expect(stats.lampsOn).toBe(16)
				expect(stats.lightsOn <= 20).toBe(true)
				local ranches = c.h.game.Workspace.Wobbleton.Ranches
				for _, p in ranches["4"]:GetChildren() do
					expect(p:FindFirstChildOfClass("PointLight").Enabled).toBe(false)
				end
				-- je perds mon ranch : mes lumières s'éteignent
				c.h.localPlayer:SetAttribute("RanchSlot", 0)
				c.LC.refresh()
				expect(c.LC.stats().ranchLightsOn).toBe(0)
				zeroLog(c.h)
			end
		)

		it(
			"phare de MON ranch (lot B4, D23) : une de mes 4 lumières dans la lanterne, quota inchangé, rendue",
			function()
				local c = client({ before = fixture })
				local V2 = c.h:require("StarterPlayer.StarterPlayerScripts.Client.Render.RanchV2")
				local lantern = MockInstance.new("Part")
				lantern.Name = "lhLantern"
				lantern.Position = Vector3.new(330, 22, 80)
				lantern.CFrame = CFrame.new(330, 22, 80)
				local lanternOf = {}
				V2.lanternPart = function(slot)
					return lanternOf[slot]
				end
				c.LC.refresh()
				local ranches = c.h.game.Workspace.Wobbleton.Ranches
				local function lights(slot)
					local out = {}
					for _, d in ranches[tostring(slot)]:GetDescendants() do
						if d.ClassName == "PointLight" then
							table.insert(out, d)
						end
					end
					return out
				end
				expect(#lights(3)).toBe(4)
				-- interrupteurs coupés (aucun phare) : rien ne bouge
				for _, light in lights(3) do
					expect(light.Parent.ClassName).toBe("Part")
				end
				-- phare dessiné sur le ranch voisin (4) : jamais sa lumière (Neon seulement)
				lanternOf[4] = lantern
				c.LC.refresh()
				for _, light in lights(4) do
					expect(light.Parent.ClassName).toBe("Part")
					expect(light.Enabled).toBe(false)
				end
				-- mon phare (palier 4, détail complet) : une lumière de mon ranch placée dans la lanterne
				lanternOf[3] = lantern
				c.LC.refresh()
				local moved = {}
				for _, light in lights(3) do
					if light.Parent.ClassName == "Attachment" then
						table.insert(moved, light)
					end
				end
				expect(#moved).toBe(1)
				local attachment = moved[1].Parent
				expect(attachment.Name).toBe("LighthouseLight")
				local holder = attachment.Parent
				expect(holder.ClassName).toBe("Part")
				expect(((holder.CFrame * attachment.Position) - lantern.Position).Magnitude < 1e-3).toBe(true)
				-- aucune lumière de plus, quota des 4 lumières du ranch inchangé
				local total = 0
				for _, d in c.h.game.Workspace:GetDescendants() do
					if d.ClassName == "PointLight" then
						total += 1
					end
				end
				expect(total).toBe(4 + 4 + 20)
				expect(c.LC.stats().ranchLightsOn).toBe(4)
				-- deuxième évaluation : rien ne change (même lumière, même attache)
				c.LC.refresh()
				expect(moved[1].Parent).toBe(attachment)
				-- le phare s'en va (palier perdu, interrupteur coupé, détail réduit) : lumière rendue
				lanternOf[3] = nil
				c.LC.refresh()
				expect(moved[1].Parent).toBe(holder)
				expect(attachment.Parent).toBe(nil)
				expect(c.LC.stats().ranchLightsOn).toBe(4)
				-- je perds mon ranch avec le phare dessiné : rendue aussi
				lanternOf[3] = lantern
				c.LC.refresh()
				expect(moved[1].Parent.ClassName).toBe("Attachment")
				c.h.localPlayer:SetAttribute("RanchSlot", 0)
				c.LC.refresh()
				expect(moved[1].Parent).toBe(holder)
				expect(c.LC.stats().ranchLightsOn).toBe(0)
				zeroLog(c.h)
			end
		)

		it("qualité réduite : lumières coupées au-delà de 60 studs de la caméra", function()
			local c = client({
				before = fixture,
				budgets = {
					lightRange = 60,
					particles = 0.3,
					particleQuota = { vfx = 36, chase = 15, lighting = 9 },
					lightQuota = { world = 16, ranch = 4, squishies = 4 },
				},
			})
			c.h.game.Workspace.CurrentCamera.CFrame = CFrame.new(0, 9, 0)
			c.LC.refresh()
			local stats = c.LC.stats()
			expect(stats.lampsOn).toBe(6) -- lampadaires à 10, 20 … 60 studs
			expect(stats.ranchLightsOn).toBe(0) -- mon ranch est à 300 studs
			zeroLog(c.h)
		end)

		it(
			"étiquette du monde : clé traduite (EN puis FR), px TV × échelle, LightInfluence 0, fond foncé",
			function()
				local c = client({ before = fixture })
				c.LC.refresh()
				local labels = c.h.game.Workspace.ClientWorld:FindFirstChild("Labels")
				local gui = labels:FindFirstChild("Label_world.shop")
				expect(gui.ClassName).toBe("BillboardGui")
				expect(gui.Adornee).toBe(c.h.game.Workspace.Wobbleton.Sign)
				expect(gui.LightInfluence).toBe(0)
				expect(gui.Text.Text).toBe("Shop")
				expect(gui.Text.TextSize >= 28).toBe(true)
				expect(gui.Text.BackgroundTransparency <= 0.4).toBe(true)
				c.Prefs._onSettings({ lang = "fr" })
				c.h:settle(1)
				expect(gui.Text.Text).toBe("Boutique")
				expect(c.LC.stats().labels).toBe(1)
				zeroLog(c.h)
			end
		)

		it(
			"monde absent : recherche bornée, sans WaitForChild ni erreur ; repris s'il arrive plus tard",
			function()
				local c = client()
				c.h:step(1, 70) -- 70 s sans workspace.Wobbleton
				expect(c.LC.stats().labels).toBe(0)
				fixture(c.h)
				c.h:settle(1)
				c.LC.refresh()
				expect(c.LC.stats().labels).toBe(1)
				expect(c.LC.stats().ranchLightsOn).toBe(4)
				zeroLog(c.h)
			end
		)
	end)

	-- Revue adversariale (paquet world) : habillage de la place selon les événements (GDD §11.1,
	-- §4.22, §4.23) et étiquettes reconstruites sans doublon. Chaque défaut est reproduit ici.
	describe("LightingController › place et étiquettes (revue)", function()
		-- Place répliquée (fixture) : anneau du MEGA pad, jarre de la jauge, poutre de l'Autel
		local function plazaFixture(h)
			local world = MockInstance.new("Folder")
			world.Name = "Wobbleton"
			local plaza = MockInstance.new("Folder")
			plaza.Name = "Plaza"
			plaza.Parent = world
			local function part(parent, name, material, color)
				local p = MockInstance.new("Part")
				p.Name = name
				p.Material = material
				p.Color = color
				p.Parent = parent
				return p
			end
			local mega = MockInstance.new("Model")
			mega.Name = "MegaPad"
			mega.Parent = plaza
			part(mega, "Ring", roblox.Enum.Material.Neon, roblox.Color3.fromRGB(255, 120, 190))
			local jar = MockInstance.new("Model")
			jar.Name = "GaugeJar"
			jar.Parent = plaza
			part(jar, "Jelly", roblox.Enum.Material.Neon, roblox.Color3.fromRGB(255, 120, 200))
			local altar = MockInstance.new("Model")
			altar.Name = "Altar"
			altar.Parent = plaza
			local beam = part(altar, "Beam", roblox.Enum.Material.Marble, roblox.Color3.new(1, 1, 1))
			beam:SetAttribute("LabelKey", "event.altarCountdown")
			beam:SetAttribute("LabelHeight", 4)
			beam:SetAttribute("LabelTimer", "moon")
			world.Parent = h.game.Workspace
			return world
		end

		local function altarLabel(c)
			return c.h.game.Workspace.ClientWorld.Labels:FindFirstChild("Label_event.altarCountdown")
		end

		it("monde remplacé : étiquettes reconstruites sans doublon, les anciennes détruites", function()
			local c = client({ before = fixture })
			c.LC.refresh()
			expect(c.LC.stats().labels).toBe(1)
			c.h.game.Workspace.Wobbleton:Destroy()
			fixture(c.h)
			c.h:settle(1)
			c.LC.refresh()
			expect(c.LC.stats().labels).toBe(1)
			local holders = 0
			for _, child in c.h.game.Workspace.ClientWorld:GetChildren() do
				if child.Name == "Labels" then
					holders += 1
					expect(#child:GetChildren()).toBe(1)
				end
			end
			expect(holders).toBe(1)
			zeroLog(c.h)
		end)

		it(
			"Autel de la Lune : compte à rebours du samedi (px TV, EN/FR), « reste 5 min » pendant la Lune, caché si l'interrupteur est coupé",
			function()
				local c = client({ before = plazaFixture, event = payload() })
				local EventClock = c.h:require("ReplicatedStorage.Shared.Logic.EventClock")
				local Format = c.h:require("ReplicatedStorage.Shared.Util.Format")
				c.LC.refresh()
				local gui = altarLabel(c)
				expect(gui.ClassName).toBe("BillboardGui")
				expect(gui.Enabled).toBe(true)
				expect(gui.LightInfluence).toBe(0)
				local left = EventClock.moon(T_DAY).startsAt - T_DAY
				expect(gui.Text.Text).toBe("Next Jelly Moon " .. Format.duration(left, "en"))
				expect(gui.Text.TextSize >= 28).toBe(true)
				-- le temps passe : le texte suit (et la plaque s'ajuste au texte)
				c.Clock.freeze(T_DAY + 3600)
				c.LC.refresh()
				expect(gui.Text.Text).toBe("Next Jelly Moon " .. Format.duration(left - 3600, "en"))
				c.Prefs._onSettings({ lang = "fr" })
				c.h:settle(1)
				c.LC.refresh()
				expect(gui.Text.Text).toBe("Prochaine Jelly Moon " .. Format.duration(left - 3600, "fr"))
				-- pendant une séance : la consigne de l'Autel
				c.Clock.freeze(T_MOON)
				c.LC.refresh()
				expect(gui.Text.Text).toBe("Reste 5 min pour une Goutte de Lune")
				-- interrupteur coupé en direct : aucun compte à rebours fantôme
				c.setEvent(payload({ features = features({ jellyMoon = false }) }))
				c.LC.refresh()
				expect(gui.Enabled).toBe(false)
				zeroLog(c.h)
			end
		)

		it(
			"Autel : sans EventState reçu, le compte à rebours reste caché (interrupteur inconnu)",
			function()
				local c = client({ before = plazaFixture })
				c.LC.refresh()
				expect(altarLabel(c).Enabled).toBe(false)
				zeroLog(c.h)
			end
		)

		it("jarre grise pendant la sieste de Big Plop (restUntil), gelée Neon rendue à la fin", function()
			local c = client({
				before = plazaFixture,
				event = payload({
					gauge = { points = 10, target = 1200, partyUntil = 0, restUntil = T_DAY + 600 },
				}),
			})
			local Palette = c.h:require("ReplicatedStorage.Shared.Render.Palette")
			c.LC.refresh()
			local jelly = c.h.game.Workspace.Wobbleton.Plaza.GaugeJar.Jelly
			expect(jelly.Material).toBe(roblox.Enum.Material.SmoothPlastic)
			expect(jelly.Color).toBe(Palette.World.jellyRest)
			c.Clock.freeze(T_DAY + 601) -- fin de la sieste sans message : la jarre se rallume seule
			c.LC.refresh()
			expect(jelly.Material).toBe(roblox.Enum.Material.Neon)
			expect(jelly.Color).toBe(roblox.Color3.fromRGB(255, 120, 200))
			zeroLog(c.h)
		end)

		it(
			"anneau du MEGA pad : éteint au calme, Neon de l'alerte à la fin des pressions ; interrupteur coupé → éteint",
			function()
				local c = client({ before = plazaFixture, event = payload() })
				local EventClock = c.h:require("ReplicatedStorage.Shared.Logic.EventClock")
				local Palette = c.h:require("ReplicatedStorage.Shared.Render.Palette")
				c.LC.refresh()
				local ring = c.h.game.Workspace.Wobbleton.Plaza.MegaPad.Ring
				expect(ring.Material).toBe(roblox.Enum.Material.SmoothPlastic)
				expect(ring.Color).toBe(Palette.World.megaRingOff)
				local m = EventClock.mega(T_DAY)
				c.Clock.freeze(m.warnAt + 1)
				c.LC.refresh()
				expect(ring.Material).toBe(roblox.Enum.Material.Neon)
				expect(ring.Color).toBe(roblox.Color3.fromRGB(255, 120, 190))
				c.Clock.freeze(m.endsAt - 1)
				c.LC.refresh()
				expect(ring.Material).toBe(roblox.Enum.Material.Neon)
				c.Clock.freeze(m.endsAt + 1)
				c.LC.refresh()
				expect(ring.Material).toBe(roblox.Enum.Material.SmoothPlastic)
				-- MEGA coupé par l'interrupteur : jamais d'anneau allumé
				c.setEvent(payload({ features = features({ megaSquish = false }) }))
				c.Clock.freeze(m.warnAt + 1)
				c.LC.refresh()
				expect(ring.Material).toBe(roblox.Enum.Material.SmoothPlastic)
				zeroLog(c.h)
			end
		)

		it("API Roblox valide (ApiAudit) : anneau, jarre, compte à rebours de l'Autel", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = client({
					before = plazaFixture,
					event = payload({
						gauge = { points = 0, target = 1200, partyUntil = 0, restUntil = T_DAY + 60 },
					}),
				})
				local EventClock = c.h:require("ReplicatedStorage.Shared.Logic.EventClock")
				c.LC.refresh()
				c.Clock.freeze(EventClock.mega(T_DAY).warnAt + 1)
				c.LC.refresh()
				c.Clock.freeze(T_MOON)
				c.LC.refresh()
				c.Prefs._onSettings({ lang = "fr" })
				c.h:settle(1)
				zeroLog(c.h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)

	describe("LightingController › robustesse", function()
		it("charges hostiles dans EventState : jamais d'erreur, jour par défaut", function()
			local c = client({ t = T_MOON, event = payload() })
			for _, bad in
				{
					{},
					{ features = "x" },
					{ features = { jellyMoon = "yes", boopRush = 5, costume = 7, gauge = {} } },
					{
						moon = 5,
						rush = { active = true, endsAt = 0 / 0 },
						boost = { kind = 5, untilT = math.huge },
					},
					{
						boost = { kind = "admin", untilT = 0 / 0 },
						gauge = { partyUntil = "soon" },
						features = features(),
					},
				}
			do
				c.setEvent(bad)
				c.LC.refresh()
				local name = c.LC.current()
				expect(name == "day" or name == "moon" or name == "party" or name == "rush").toBe(true)
			end
			c.setEvent({ features = { jellyMoon = "yes" } })
			expect(c.LC.current()).toBe("day")
			c.WSC.EventChanged:Fire(nil)
			c.WSC.EventChanged:Fire("garbage")
			c.h:settle(1)
			zeroLog(c.h)
		end)

		it("resolve (pur) : interrupteurs, horaires, priorités Lune > Rush > fête > base", function()
			local c = client()
			local R = c.LC.resolve
			expect(R(nil, T_MOON, false, T_MOON).name).toBe("day")
			expect(R(payload(), T_MOON, false, T_MOON).name).toBe("moon")
			local both = R(
				payload({ boost = { kind = "wobble", untilT = T_MOON + 10, byName = "" } }),
				T_MOON,
				false,
				T_MOON
			)
			expect(both.name).toBe("moon")
			expect(both.party).toBe(true)
			expect(both.preset.clockTime).toBe(0)
			local winterMoon =
				R(payload({ features = features({ costume = "winter2026" }) }), T_MOON, false, T_MOON)
			expect(winterMoon.name).toBe("moon")
			expect(winterMoon.winter).toBe(true)
			expect(R(payload(), T_SIREN, true, T_SIREN).rush).toBe(true)
			expect(R(payload({ features = features({ boopRush = "off" }) }), T_SIREN, false, T_SIREN).rush).toBe(
				false
			)
			for _, t in { 0 / 0, math.huge, -1 } do
				local r = R(payload(), t, false, t)
				expect(type(r.name)).toBe("string")
			end
			zeroLog(c.h)
		end)

		it(
			"démarrage complet du client (Main.client, console) : zéro erreur, zéro avertissement",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				h:boot()
				local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
				h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", Schema.defaults())
				h:step(1 / 60, 40)
				zeroLog(h)
			end
		)

		it("API Roblox valide (ApiAudit) : effets, transitions, hiver, lumières, étiquettes", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = client({
					t = T_WINTER,
					event = payload({ features = features({ costume = "winter2026" }) }),
					before = fixture,
				})
				c.LC.refresh()
				c.Clock.freeze(T_MOON)
				c.LC.refresh()
				c.h:step(0.5, 4)
				zeroLog(c.h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
