--!nocheck
-- LightingController (paquet world) : cycle de 12 min sur Clock.now(), préréglages météo et
-- événements (tween 3 s Sine InOut), effets de ciel dans workspace.ClientSky, Balise, alerte
-- Comète, Nuit d'Or, Graphismes légers, Mouvement réduit, sources défaillantes (GDD §11.5, §9.4).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 720 * 2500000 -- début d'un cycle : ClockTime = 17,6

	-- Client isolé : sources d'événements contrôlées par le test, cibles Lighting présentes
	local function setup()
		local h = Harness.new({ mode = "client" })
		local g = h.globals
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		local Events = h:require("ReplicatedStorage.Shared.Config.Events")
		local Zones = h:require("ReplicatedStorage.Shared.Config.Zones")
		local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		local Prefs = h:require(CLIENT .. "Util.Prefs")
		local LC = h:require(CLIENT .. "Controllers.LightingController")
		local env = { ev = nil, weather = nil, beacon = nil, comet = nil }
		EventClock.weather = function()
			return env.weather
		end
		EventClock.beacon = function()
			return env.beacon
		end
		EventClock.comet = function()
			return env.comet
		end
		for className, name in
			{
				Atmosphere = "Atmosphere",
				Sky = "Sky",
				BloomEffect = "Bloom",
				ColorCorrectionEffect = "ColorCorrection",
				SunRaysEffect = "SunRays",
			}
		do
			local inst = g.Instance.new(className)
			inst.Name = name
			inst.Parent = h.game.Lighting
		end
		Clock.freeze(T0)
		return {
			h = h,
			g = g,
			Clock = Clock,
			Events = Events,
			Zones = Zones,
			LC = LC,
			WSC = WSC,
			Prefs = Prefs,
			env = env,
			L = h.game.Lighting,
		}
	end

	-- Balise côté client (comme répliquée par WorldService) : faisceau, 3 anneaux, dépôt
	local function fakeBeacon(c)
		local g, cs = c.g, c.h.game.CollectionService
		local model = g.Instance.new("Model")
		model.Name = "Beacon"
		model.Parent = c.h.workspace
		cs:AddTag(model, "Beacon")
		local carrier = g.Instance.new("Part")
		carrier.Name = "SkyBeam"
		carrier.Parent = model
		local beam = g.Instance.new("Beam")
		beam.Name = "Beam"
		beam.Width0 = c.Zones.Beacon.BeamWidth
		beam.Width1 = c.Zones.Beacon.BeamWidth
		beam.Parent = carrier
		local rings = {}
		for i = 3, 1, -1 do -- ordre de création inversé : le tri se fait par hauteur
			local ring = g.Instance.new("Part")
			ring.Name = "Ring" .. i
			ring.CFrame = g.CFrame.new(0, i * 6, 0)
			ring.Material = g.Enum.Material.Neon
			ring.Color = c.Zones.Beacon.RingColor
			ring.Parent = model
			cs:AddTag(ring, "BeaconRing")
			rings[i] = ring
		end
		local deposit = g.Instance.new("Part")
		deposit.Name = "Deposit"
		deposit.Size = g.Vector3.new(0.2, 28, 28)
		deposit.Transparency = 1
		deposit.Parent = model
		cs:AddTag(deposit, "BeaconDeposit")
		return { beam = beam, rings = rings, deposit = deposit }
	end

	-- EventState reçu par WorldStateController : (nouvel état, ancien état)
	local function changed(c)
		c.WSC.EventChanged:Fire(c.env.ev, c.prev)
		c.prev = c.env.ev
	end

	-- Init + Start, puis l'instantané d'arrivée (premier EventChanged, ancien état nil)
	local function start(c)
		c.LC.Init()
		c.LC.Start()
		c.prev = nil
		changed(c)
	end

	local function lit(ring)
		return ring.Material.Name == "Neon"
	end

	describe("LightingController › cycle de 12 min", function()
		it("cycleClockTime : 17,6 → 20,5 → 17,6 sur 720 s, valeurs invalides → minimum", function()
			local c = setup()
			local LC = c.LC
			local cycle = c.Events.Lighting.Cycle
			expect(LC.cycleClockTime(0)).toBeNear(17.6, 1e-9)
			expect(LC.cycleClockTime(360)).toBeNear(20.5, 1e-9)
			expect(LC.cycleClockTime(720)).toBeNear(17.6, 1e-9)
			expect(LC.cycleClockTime(180)).toBeNear(17.6 + 1.45, 1e-9)
			expect(LC.cycleClockTime(T0 + 360)).toBeNear(20.5, 1e-6)
			for t = 0, 720, 37 do
				local expected = cycle.Min
					+ cycle.Amplitude * (0.5 - 0.5 * math.cos(2 * math.pi * t / cycle.Period))
				expect(LC.cycleClockTime(t)).toBeNear(expected, 1e-9)
			end
			for _, bad in { 0 / 0, math.huge, -math.huge, "x", nil } do
				expect(LC.cycleClockTime(bad)).toBe(cycle.Min)
			end
		end)

		it(
			"Start : une seule connexion RenderStepped ; ClockTime suit Clock.now() ; ClientSky créé",
			function()
				local c = setup()
				local rs = c.h.game.RunService
				local before = #rs.RenderStepped._handlers
				start(c)
				expect(#rs.RenderStepped._handlers).toBe(before + 1)
				expect(c.h.workspace:FindFirstChild("ClientSky") ~= nil).toBe(true)
				expect(c.L.ClockTime).toBeNear(17.6, 1e-3)
				c.Clock.advance(360)
				c.h:step(1 / 60, 2)
				expect(c.L.ClockTime).toBeNear(20.5, 1e-3)
				c.Clock.advance(180)
				c.h:step(1 / 60, 1)
				expect(c.L.ClockTime).toBeNear(19.05, 1e-3)
				-- les valeurs de base sont posées localement
				local base = c.Events.Lighting.Base
				expect(c.L.Brightness).toBe(base.Brightness)
				expect(c.L.Atmosphere.Density).toBe(base.AtmosphereDensity)
				expect(c.L.Sky.StarCount).toBe(base.StarCount)
				expect(c.L.ColorCorrection.TintColor).toEqual(c.g.Color3.new(1, 1, 1))
				expect(c.LC.currentPreset()).toBeNil()
				start(c) -- deuxième Start : rien de plus
				expect(#rs.RenderStepped._handlers).toBe(before + 1)
				c.LC._stop()
			end
		)
	end)

	describe("LightingController › préréglages météo", function()
		it("Aurora : fondu Sine InOut de 3 s à l'aller et au retour, 6 rideaux dans ClientSky", function()
			local c = setup()
			start(c)
			local aurora = c.Events.Lighting.Presets.aurora
			c.env.ev = { weather = { key = "aurora", startsAt = T0 - 1, endsAt = T0 + 150 }, wisps = {} }
			changed(c)
			expect(c.LC.currentPreset()).toBe("aurora")
			c.LC._update(1.5) -- mi-chemin : Sine InOut(0,5) = 0,5
			local white = c.g.Color3.new(1, 1, 1)
			local half = white:Lerp(aurora.Tint, 0.5)
			local tint = c.L.ColorCorrection.TintColor
			expect(math.abs(tint.R - half.R) + math.abs(tint.G - half.G) + math.abs(tint.B - half.B)).toBeLessThan(
				0.01
			)
			c.LC._update(1.5)
			expect(c.L.ColorCorrection.TintColor).toEqual(aurora.Tint)
			expect(c.L.Atmosphere.Color).toEqual(aurora.AtmosphereColor)
			expect(c.L.Atmosphere.Decay).toEqual(aurora.AtmosphereDecay)
			local fx = c.h.workspace.ClientSky:FindFirstChild("auroraCurtains")
			expect(fx ~= nil).toBe(true)
			local beams = 0
			for _, d in fx:GetDescendants() do
				if d.ClassName == "Beam" then
					beams += 1
				end
			end
			expect(beams).toBe(6)
			-- fin de la fenêtre : retour en 3 s, effet retiré
			c.env.ev = { wisps = {} }
			changed(c)
			expect(c.LC.currentPreset()).toBeNil()
			c.LC._update(1)
			expect(c.h.workspace.ClientSky:FindFirstChild("auroraCurtains") ~= nil).toBe(true)
			c.LC._update(2.1)
			expect(c.L.ColorCorrection.TintColor).toEqual(white)
			expect(c.h.workspace.ClientSky:FindFirstChild("auroraCurtains")).toBeNil()
			c.LC._stop()
		end)

		it(
			"la météo déterministe d'EventClock suffit sans WorldStateController ; LiveOps l'emporte",
			function()
				local c = setup()
				start(c)
				c.env.weather =
					{ slot = 1, key = "solar", startsAt = T0 - 5, endsAt = T0 + 100, starfall = false }
				c.LC._update(0.3)
				expect(c.LC.currentPreset()).toBe("solar")
				c.LC._update(3)
				expect(c.L.Bloom.Intensity).toBeNear(c.Events.Lighting.Presets.solar.Bloom, 1e-6)
				c.env.ev = {
					weather = { key = "frost", startsAt = T0 - 1, endsAt = T0 + 150, forced = true },
					wisps = {},
				}
				changed(c)
				expect(c.LC.currentPreset()).toBe("frost")
				c.LC._stop()
			end
		)

		it("Frostfall : neige qui suit la caméra (60 / s) ; Graphismes légers : × 0,3", function()
			local c = setup()
			c.env.weather =
				{ slot = 1, key = "frost", startsAt = T0 - 5, endsAt = T0 + 100, starfall = false }
			start(c) -- arrivée pendant la fenêtre : posé d'emblée
			c.h.workspace.CurrentCamera.CFrame = c.g.CFrame.new(50, 10, -40)
			c.LC._update(1 / 60)
			local carrier = c.h.workspace.ClientSky.snow.SnowEmitter
			expect(carrier.Position.X).toBeNear(50, 1e-6)
			expect(carrier.Position.Z).toBeNear(-40, 1e-6)
			expect(carrier.Position.Y).toBeGreaterThan(10)
			local emitter = carrier:FindFirstChildOfClass("ParticleEmitter")
			expect(emitter.Rate).toBeNear(60, 1e-6)
			expect(emitter.Lifetime.Min).toBeNear(6)
			expect(c.L.Atmosphere.Haze).toBeNear(c.Events.Lighting.Presets.frost.Haze, 1e-6)
			c.Prefs._onSettings({ lowGraphics = true })
			c.h:settle(1)
			c.LC._update(1 / 60)
			local low = c.h.workspace.ClientSky.snow.SnowEmitter:FindFirstChildOfClass("ParticleEmitter")
			expect(low.Rate).toBeNear(60 * 0.3, 1e-6)
			c.LC._stop()
		end)

		it("Meteor Shower : réserve de 10 traits Néon, un toutes les 0,4 s, jamais plus de 10", function()
			local c = setup()
			c.env.weather =
				{ slot = 1, key = "meteor", startsAt = T0 - 5, endsAt = T0 + 100, starfall = false }
			start(c)
			local folder = c.h.workspace.ClientSky.meteorStreaks
			expect(#folder:GetChildren()).toBe(10)
			local maxVisible = 0
			for _ = 1, 40 do
				c.LC._update(0.1)
				local visible = 0
				for _, p in folder:GetChildren() do
					if p.Transparency == 0 then
						visible += 1
					end
				end
				maxVisible = math.max(maxVisible, visible)
			end
			expect(maxVisible).toBeGreaterThan(0)
			expect(maxVisible).toBeLessThanOrEqual(10)
			expect(#folder:GetChildren()).toBe(10)
			c.LC._stop()
		end)

		it("Rainbow Comet : teinte HSV qui cycle sur 8 s, 5 arcs", function()
			local c = setup()
			c.env.ev = { weather = { key = "rainbow", startsAt = T0 - 1, endsAt = T0 + 150 }, wisps = {} }
			start(c)
			local fx = c.h.workspace.ClientSky.rainbowArcs
			local arcs = 0
			for _, d in fx:GetDescendants() do
				if d.ClassName == "Beam" then
					arcs += 1
				end
			end
			expect(arcs).toBe(5)
			local a = c.L.ColorCorrection.TintColor
			c.Clock.advance(2)
			c.LC._update(1 / 60)
			local b = c.L.ColorCorrection.TintColor
			expect(a ~= b).toBe(true)
			local _, sat = b:ToHSV()
			expect(sat).toBeNear(0.12, 0.02)
			c.LC._stop()
		end)
	end)

	describe("LightingController › événements", function()
		it(
			"Nuit de la Balise : 21,5 en 4 s, 5000 étoiles, anneaux un à un, faisceau × 3, dépôt allumé puis éteint",
			function()
				local c = setup()
				local beacon = fakeBeacon(c)
				start(c)
				-- hors Balise : anneaux éteints, dépôt invisible
				for _, ring in beacon.rings do
					expect(lit(ring)).toBe(false)
				end
				expect(beacon.deposit.Transparency).toBe(1)
				c.env.ev = {
					beacon = {
						phase = "active",
						warnAt = T0 - 16,
						startsAt = T0 - 1,
						endsAt = T0 + 179,
						points = 0,
						goal = 20,
					},
					wisps = {},
				}
				changed(c)
				expect(c.LC.currentPreset()).toBe("beacon")
				c.LC._update(0.05)
				expect({ lit(beacon.rings[1]), lit(beacon.rings[2]), lit(beacon.rings[3]) }).toEqual({
					true,
					false,
					false,
				})
				c.LC._update(0.1)
				expect({ lit(beacon.rings[1]), lit(beacon.rings[2]), lit(beacon.rings[3]) }).toEqual({
					true,
					true,
					false,
				})
				c.LC._update(0.1)
				expect({ lit(beacon.rings[1]), lit(beacon.rings[2]), lit(beacon.rings[3]) }).toEqual({
					true,
					true,
					true,
				})
				expect(beacon.deposit.Transparency).toBe(0)
				expect(beacon.deposit.Size).toEqual(c.g.Vector3.new(0.2, 28, 28))
				c.LC._update(2) -- 2,25 s : pas encore à 21,5
				expect(c.L.ClockTime).toBeLessThan(21.4)
				c.LC._update(1.8) -- 4 s
				expect(c.L.ClockTime).toBeNear(21.5, 1e-6)
				expect(c.L.Sky.StarCount).toBe(5000)
				expect(beacon.beam.Width0).toBeNear(c.Zones.Beacon.BeamWidth * 3, 1e-6)
				-- fin de la nuit
				c.env.ev = { wisps = {} }
				changed(c)
				c.LC._update(4)
				c.h:settle(2)
				expect(c.L.ClockTime).toBeNear(17.6, 1e-3)
				expect(beacon.beam.Width0).toBeNear(c.Zones.Beacon.BeamWidth, 1e-6)
				for _, ring in beacon.rings do
					expect(lit(ring)).toBe(false)
				end
				expect(beacon.deposit.Transparency).toBe(1)
				c.LC._stop()
			end
		)

		it(
			"réussite : flash des anneaux (sauf Mouvement réduit) ; échec : bouffée bleue d'1 s",
			function()
				local c = setup()
				local beacon = fakeBeacon(c)
				c.env.ev = {
					beacon = {
						phase = "active",
						warnAt = T0 - 16,
						startsAt = T0 - 1,
						endsAt = T0 + 179,
						points = 10,
						goal = 20,
					},
					wisps = {},
				}
				start(c)
				c.LC._update(0.5)
				local old = c.env.ev
				local before = c.h.stats.tweens
				c.env.ev = { beacon = table.clone(old.beacon), wisps = {} }
				c.env.ev.beacon.phase = "success"
				c.WSC.EventChanged:Fire(c.env.ev, old)
				expect(c.h.stats.tweens - before).toBe(3)
				-- Mouvement réduit : aucun flash
				c.Prefs._onSettings({ reducedMotion = true })
				local again = c.env.ev
				c.env.ev = { beacon = table.clone(old.beacon), wisps = {} }
				c.WSC.EventChanged:Fire(c.env.ev, again) -- retour à "active"
				before = c.h.stats.tweens
				local success = { beacon = table.clone(old.beacon), wisps = {} }
				success.beacon.phase = "success"
				c.env.ev = success
				c.WSC.EventChanged:Fire(success, again)
				expect(c.h.stats.tweens - before).toBe(0)
				-- échec en fin de fenêtre : bleu, puis anneaux éteints après la bouffée
				local fail = { beacon = table.clone(old.beacon), wisps = {} }
				fail.beacon.phase = "fail"
				fail.beacon.endsAt = T0
				c.env.ev = fail
				c.WSC.EventChanged:Fire(fail, success)
				expect(lit(beacon.rings[1])).toBe(true) -- encore Néon pendant la bouffée
				c.LC._update(0.5)
				expect(lit(beacon.rings[1])).toBe(true)
				c.LC._update(0.6)
				expect(lit(beacon.rings[1])).toBe(false)
				c.LC._stop()
			end
		)

		it(
			"alerte Comète : OutdoorAmbient −30 % en 2 s ; Nuit d'Or dorée ; Glow Party sans effet",
			function()
				local c = setup()
				start(c)
				local base = c.Events.Lighting.Base.OutdoorAmbient
				c.env.ev = {
					comet = {
						id = T0 + 7,
						phase = "warn",
						x = 0,
						z = 20,
						code = 1,
						warnAt = T0 - 1,
						impactAt = T0 + 7,
						burstAt = T0 + 82,
					},
					wisps = {},
				}
				changed(c)
				expect(c.LC.currentPreset()).toBe("cometWarn")
				c.LC._update(2)
				local amb = c.L.OutdoorAmbient
				expect(amb.R).toBeNear(base.R * 0.7, 1e-3)
				expect(amb.B).toBeNear(base.B * 0.7, 1e-3)
				-- impact : l'alerte s'arrête
				c.env.ev.comet.phase = "ground"
				changed(c)
				c.LC._update(2)
				expect(c.L.OutdoorAmbient.R).toBeNear(base.R, 1e-3)
				-- Nuit d'Or
				c.env.ev = { serverBoost = { endsAt = T0 + 300, source = "goldenNight" }, wisps = {} }
				changed(c)
				expect(c.LC.currentPreset()).toBe("goldenNight")
				c.LC._update(3)
				expect(c.L.ColorCorrection.TintColor).toEqual(c.Events.Lighting.Presets.goldenNight.Tint)
				-- Glow Party : boost sans éclairage doré
				c.env.ev =
					{ serverBoost = { endsAt = T0 + 300, source = "glowParty", buyerId = 9 }, wisps = {} }
				changed(c)
				expect(c.LC.currentPreset()).toBeNil()
				-- boost expiré
				c.env.ev = { serverBoost = { endsAt = T0 - 1, source = "goldenNight" }, wisps = {} }
				changed(c)
				expect(c.LC.currentPreset()).toBeNil()
				c.LC._stop()
			end
		)

		it("superposition : météo + alerte + Balise ; priorité de currentPreset", function()
			local c = setup()
			start(c)
			c.env.ev = {
				weather = { key = "aurora", startsAt = T0 - 1, endsAt = T0 + 150 },
				comet = {
					id = T0 + 7,
					phase = "warn",
					x = 0,
					z = 20,
					code = 1,
					warnAt = T0 - 1,
					impactAt = T0 + 7,
					burstAt = T0 + 82,
				},
				wisps = {},
			}
			changed(c)
			expect(c.LC.currentPreset()).toBe("cometWarn")
			c.LC._update(3)
			expect(c.L.ColorCorrection.TintColor).toEqual(c.Events.Lighting.Presets.aurora.Tint)
			expect(c.L.OutdoorAmbient.R).toBeNear(c.Events.Lighting.Base.OutdoorAmbient.R * 0.7, 1e-3)
			c.env.beacon = { id = T0, warnAt = T0 - 15, startsAt = T0 - 1, endsAt = T0 + 179 }
			c.LC._update(0.3)
			expect(c.LC.currentPreset()).toBe("beacon")
			c.LC._stop()
		end)

		it(
			"setPreset force un préréglage, nil rend la main aux événements, clé inconnue ignorée",
			function()
				local c = setup()
				start(c)
				c.LC.setPreset("eclipse")
				expect(c.LC.currentPreset()).toBe("eclipse")
				c.LC._update(3)
				expect(c.L.Brightness).toBeNear(1.2, 1e-6)
				expect(c.L.Sky.MoonAngularSize).toBeNear(20, 1e-6)
				c.env.ev = { serverBoost = { endsAt = T0 + 300, source = "goldenNight" }, wisps = {} }
				changed(c)
				expect(c.LC.currentPreset()).toBe("eclipse") -- le forçage l'emporte
				local warnings = #c.h:warnings()
				c.LC.setPreset("bogus")
				c.LC.setPreset(42)
				expect(c.LC.currentPreset()).toBe("eclipse")
				expect(#c.h:warnings()).toBe(warnings + 2)
				c.LC.setPreset(nil)
				expect(c.LC.currentPreset()).toBe("goldenNight")
				c.LC._update(3)
				expect(c.L.Brightness).toBeNear(c.Events.Lighting.Base.Brightness, 1e-6)
				c.LC._stop()
			end
		)

		it("arrivée pendant un événement : préréglage posé sans fondu", function()
			local c = setup()
			c.env.ev = {
				beacon = {
					phase = "active",
					warnAt = T0 - 30,
					startsAt = T0 - 15,
					endsAt = T0 + 165,
					points = 4,
					goal = 20,
				},
				wisps = {},
			}
			start(c)
			expect(c.L.ClockTime).toBeNear(21.5, 1e-6)
			expect(c.L.Sky.StarCount).toBe(5000)
			c.LC._stop()
		end)
	end)

	describe("LightingController › réglages et robustesse", function()
		it(
			"Graphismes légers : lumières des lanternes et cristaux coupées au-delà de 60 studs",
			function()
				local c = setup()
				local g, cs = c.g, c.h.game.CollectionService
				local function lantern(z, tag)
					local bulb = g.Instance.new("Part")
					bulb.CFrame = g.CFrame.new(0, 6, z)
					bulb.Parent = c.h.workspace
					local light = g.Instance.new("PointLight")
					light.Enabled = true
					light.Parent = bulb
					cs:AddTag(bulb, tag)
					return light
				end
				local near = lantern(30, "Lantern")
				local far = lantern(200, "Lantern")
				local crystal = lantern(-150, "Crystal")
				c.h.workspace.CurrentCamera.CFrame = g.CFrame.new(0, 10, 20)
				start(c)
				c.LC._update(0.6)
				expect(near.Enabled and far.Enabled and crystal.Enabled).toBe(true)
				c.Prefs._onSettings({ lowGraphics = true })
				c.h:settle(1)
				c.LC._update(0.6)
				expect(near.Enabled).toBe(true)
				expect(far.Enabled).toBe(false)
				expect(crystal.Enabled).toBe(false)
				c.Prefs._onSettings({ lowGraphics = false })
				c.h:settle(1)
				c.LC._update(0.6)
				expect(far.Enabled and crystal.Enabled).toBe(true)
				c.LC._stop()
			end
		)

		it(
			"sources défaillantes (stub, panne, états malformés) : aucune erreur, un avertissement par étape et par 10 s",
			function()
				local c = setup()
				local EventClock = c.h:require("ReplicatedStorage.Shared.Logic.EventClock")
				EventClock.weather = function()
					error("TODO(logic): EventClock.weather")
				end
				EventClock.comet = function()
					error("panne simulée")
				end
				start(c)
				for _ = 1, 20 do
					c.LC._update(0.3)
				end
				expect(#c.h:warnings()).toBe(2) -- une fois par étape malgré 20 évaluations
				c.LC._update(0 / 0) -- dt invalide
				c.LC._update(-5)
				c.LC._update(math.huge)
				-- états d'événements incomplets, mal typés, ou d'une clé inconnue
				for _, ev in
					{
						{ weather = { key = "unknown", startsAt = T0 - 1, endsAt = T0 + 10 }, wisps = {} },
						{ weather = { key = "aurora", startsAt = "hier", endsAt = T0 + 10 }, wisps = {} },
						{ beacon = 5, comet = { phase = "warn" }, serverBoost = { source = "goldenNight" } },
						{ beacon = { phase = "success" }, comet = "x", weather = true },
						"n'importe quoi",
						42,
					}
				do
					c.env.ev = ev
					changed(c)
					c.LC._update(0.3)
				end
				expect(c.LC.currentPreset()).toBeNil()
				expect(c.L.ClockTime == c.L.ClockTime).toBe(true) -- jamais NaN
				expect(#c.h.errors).toBe(0)
				c.LC._stop()
			end
		)

		it("avec la vraie EventClock (paquet logic) : Balise de :25 et météo déterministes", function()
			local h = Harness.new({ mode = "client" })
			local EventClock = h:require("ReplicatedStorage.Shared.Logic.EventClock")
			local ok = pcall(EventClock.beacon, 0)
			if not ok then
				return -- EventClock pas encore livrée : couvert par les doubles ci-dessus
			end
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			local LC = h:require(CLIENT .. "Controllers.LightingController")
			-- mardi, :25:30 (aucun Starfall le mardi)
			local tuesday = 1800000000 - (1800000000 % 604800) + 345600 + 86400 -- lundi + 1 jour
			local t = tuesday + 1500 + 30
			Clock.freeze(t)
			LC.Init()
			LC.Start()
			expect(LC.currentPreset()).toBe("beacon")
			local window = EventClock.weather(t)
			expect(window == nil or window.key ~= nil).toBe(true)
			LC._stop()
		end)
	end)
end
