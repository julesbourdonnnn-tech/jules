--!nocheck
-- Météo et place en fête dessinées par le client (lot B5, étape 5 ; GDD v2.0 §5.6, §7.5, §11.5 ; docs/04
-- §27.5 EventState.weather / fete ; plan B5 W1, W2, D22, D23, D29) :
--   * World/WeatherFx : 4 sortes (sunny rien, sprinkles et bubbles un seul émetteur qui suit la caméra,
--     rainbow 7 pièces Neon au-dessus de la place) ; débit ≤ 60 par seconde avec les flocons d'hiver et
--     × la qualité ; fin à endsAt sans message ; clé retirée = fin ; son une fois par fenêtre, jamais
--     au chargement ; budget « weather » ;
--   * World/Fete : niveaux 0-5 cumulés et retour à 0 ; emprises (dessin réel dedans, hors du point
--     d'apparition neutre, du kiosque, du MEGA pad, de la boutique, de l'autel et des nœuds des rues) ;
--     feux d'artifice toutes les 6 s au niveau 4 ; Toast et son seulement quand le niveau monte en
--     partie, jamais au chargement ; budget « fete » ;
--   * interrupteurs coupés (clés absentes, charges hostiles) : aucune instance, aucune boucle ;
--   * aucune fuite après 120 cycles sur l'horloge figée.
-- Aucune écriture de Lighting : prouvé par Static_LightingWriter (seul AmbienceDirector nomme Lighting).
-- Tout est en 3D : ces cas prouvent la structure ; personne n'a pu regarder les particules ni le décor.

local roblox = require("@lune/roblox")
local UpgradeScreen = require("../harness/UpgradeScreen")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local T0 = 1796724120
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local REMOTES = "ReplicatedStorage.Remotes."

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- Client : miroir et VFXController (qui démarre WeatherFx et Fete) ; `opts.ev` : EventState reçu
	-- AVANT le démarrage (chargement) ; `c.snow` : débit des flocons d'hiver ; `c.quality` : facteur
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:require(CLIENT .. "Util.Prefs").Init()
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local c = {
			h = h,
			Clock = Clock,
			WSC = WSC,
			WX = h:require(CLIENT .. "World.WeatherFx"),
			FE = h:require(CLIENT .. "World.Fete"),
			VB = h:require(CLIENT .. "Render.VisualBudget"),
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			sounds = {},
			toasts = {},
			snow = 0,
			quality = 1,
		}
		c.WX._configure({
			play = function(name)
				table.insert(c.sounds, name)
			end,
			snowRate = function()
				return c.snow
			end,
			quality = function()
				return c.quality
			end,
		})
		c.FE._configure({
			play = function(name)
				table.insert(c.sounds, name)
			end,
			toast = function(text)
				table.insert(c.toasts, text)
			end,
		})
		function c.event(over)
			local ev = UpgradeScreen.eventState(nil)
			for key, value in over or {} do
				ev[key] = value
			end
			h:fireClient(REMOTES .. "EventState", ev)
			h:settle(1)
		end
		if opts.ev then
			c.event(opts.ev)
		end
		local VFX = h:require(CLIENT .. "Controllers.VFXController")
		VFX.Init()
		VFX.Start()
		c.VFX = VFX
		function c.frame(dt)
			Clock.advance(dt)
			h.game.RunService.RenderStepped:Fire(dt)
		end
		function c.play(seconds)
			local dt = 1 / 30
			for _ = 1, math.floor(seconds / dt + 0.5) do
				c.frame(dt)
			end
			h:settle(1)
		end
		function c.frozen(seconds)
			local dt = 1 / 30
			for _ = 1, math.floor(seconds / dt + 0.5) do
				h.game.RunService.RenderStepped:Fire(dt)
			end
			h:settle(1)
		end
		function c.world(name)
			local root = h.workspace:FindFirstChild("ClientWorld")
			return root and root:FindFirstChild(name)
		end
		function c.count()
			local root = h.workspace:FindFirstChild("ClientWorld")
			return if root then #root:GetDescendants() else 0
		end
		-- une NOUVELLE fenêtre (endsAt distinct, comme deux fenêtres réelles du serveur) ; jamais plus de
		-- 300 s devant (AmbienceRules.fromEvent refuse un endsAt plus loin que la plus longue fenêtre)
		local windows = 0
		function c.weather(kind, seconds)
			windows += 1
			c.event({ weather = { kind = kind, endsAt = Clock.unix() + (seconds or 290) - windows % 2 } })
		end
		return c
	end

	local KIND = { sunny = 1, sprinkles = 2, bubbles = 3, rainbow = 4 }

	-- =============================================================================================
	-- Météo
	-- =============================================================================================

	describe("WeatherFx (lot B5, étape 5)", function()
		it(
			"4 sortes : sunny rien ; sprinkles et bubbles UN émetteur ancré et invisible qui suit la caméra ; rainbow 7 pièces Neon au-dessus de la place ; son WeatherStart → Whoosh une fois par fenêtre, jamais au chargement",
			function()
				-- fenêtre déjà en cours au chargement : dessinée, mais aucun son
				local c = client({ ev = { weather = { kind = KIND.sprinkles, endsAt = T0 + 200 } } })
				expect(c.WX.kind()).toBe("sprinkles")
				expect(#c.sounds).toBe(0)
				c.event({}) -- clé retirée
				expect(c.world("Weather")).toBeNil()

				c.weather(KIND.sunny)
				expect(c.WX.kind()).toBe("sunny")
				expect(c.world("Weather")).toBeNil()
				expect(c.WX.stats().looping).toBe(0)
				expect(c.sounds[1]).toBe("Whoosh")

				local cam = c.h.workspace.CurrentCamera
				cam.CFrame = CFrame.new(100, 30, -50)
				for _, kind in { "sprinkles", "bubbles" } do
					c.event({})
					c.weather(KIND[kind])
					local s = c.WX._state()
					expect(#s.folder:GetChildren()).toBe(1)
					local part = s.emitterPart
					expect(part.Anchored).toBe(true)
					expect(part.Transparency).toBe(1)
					expect(part.CanCollide).toBe(false)
					local emitters = {}
					for _, d in s.folder:GetDescendants() do
						if d:IsA("ParticleEmitter") then
							table.insert(emitters, d)
						end
					end
					expect(#emitters).toBe(1)
					expect(emitters[1].Rate).toBe(60)
					expect(emitters[1].Enabled).toBe(true)
					expect(emitters[1].EmissionDirection).toBe(
						if kind == "bubbles" then Enum.NormalId.Top else Enum.NormalId.Bottom
					)
					-- la pièce suit la caméra (au-dessus pour les vermicelles, vers le sol pour les bulles)
					cam.CFrame = CFrame.new(-40, 30, 90)
					c.play(0.1)
					local p = part.CFrame.Position
					expect(p.X).toBeNear(-40, 1e-6)
					expect(p.Z).toBeNear(90, 1e-6)
					expect(p.Y).toBeNear(if kind == "bubbles" then 12 else 55, 1e-6)
					expect(c.VB.used("weather")).toBe(1)
					expect(c.VB.used("weather", "particles")).toBe(60)
				end

				c.event({})
				c.weather(KIND.rainbow)
				local arc = c.WX._state().arc
				expect(#arc).toBe(7)
				local colors = {}
				for _, p in arc do
					expect(p.Material).toBe(Enum.Material.Neon)
					expect(p.Anchored).toBe(true)
					expect(p.CanCollide).toBe(false)
					colors[tostring(p.Color)] = true
					local pos = p.CFrame.Position
					expect(math.sqrt(pos.X ^ 2 + pos.Z ^ 2)).toBeLessThanOrEqual(62)
					expect(pos.Y).toBeLessThanOrEqual(51)
				end
				local n = 0
				for _ in colors do
					n += 1
				end
				expect(n).toBe(7)
				expect(c.VB.used("weather")).toBe(7)
				-- un son par fenêtre : sunny, sprinkles, bubbles, rainbow ; le même message rejoué : rien
				expect(#c.sounds).toBe(4)
				c.event({ weather = { kind = KIND.rainbow, endsAt = c.WX._state().endsAt } })
				expect(#c.sounds).toBe(4)
				for _, s in c.sounds do
					expect(s).toBe("Whoosh")
				end
				clean(c.h)
			end
		)

		it(
			"débit : 60 par seconde au plus × qualité (× 0,3 en Graphismes légers), abaissé pendant les flocons d'hiver pour que les deux restent à 60 ou moins",
			function()
				local c = client()
				c.weather(KIND.sprinkles)
				local e = c.WX._state().emitter
				for _, case in
					{
						{ snow = 0, quality = 1, rate = 60 },
						{ snow = 10, quality = 1, rate = 50 },
						{ snow = 10, quality = 0.3, rate = 18 },
						{ snow = 50, quality = 1, rate = 10 },
						{ snow = 60, quality = 1, rate = 0 },
						{ snow = 0, quality = 0.3, rate = 18 },
					}
				do
					c.snow = case.snow
					c.quality = case.quality
					c.play(1.1)
					expect(e.Rate).toBeNear(case.rate, 1e-6)
					expect(e.Enabled).toBe(case.rate > 0)
					expect(e.Rate + c.snow).toBeLessThanOrEqual(60)
				end
				clean(c.h)
			end
		)

		it(
			"fin : à endsAt sur l'horloge sans aucun message (instances, boucle et budget rendus) ; clé retirée (séance de Lune, interrupteur coupé en direct) : fin tout de suite",
			function()
				for _, kind in { KIND.sprinkles, KIND.rainbow } do
					local c = client()
					c.weather(kind, 20)
					expect(c.world("Weather")).toBeTruthy()
					c.play(19)
					expect(c.world("Weather")).toBeTruthy()
					c.play(1.5)
					expect(c.world("Weather")).toBeNil()
					expect(c.WX.kind()).toBeNil()
					expect(c.WX.stats().looping).toBe(0)
					expect(c.VB.used("weather")).toBe(0)
					expect(c.VB.used("weather", "particles")).toBe(0)
					-- clé retirée
					c.weather(kind, 300)
					expect(c.world("Weather")).toBeTruthy()
					c.event({})
					expect(c.world("Weather")).toBeNil()
					expect(c.WX.stats().looping).toBe(0)
					clean(c.h)
				end
				-- sunny : aucune boucle, et kind() suit l'horloge
				local c = client()
				c.weather(KIND.sunny, 10)
				expect(c.WX.kind()).toBe("sunny")
				c.Clock.advance(11)
				expect(c.WX.kind()).toBeNil()
				clean(c.h)
			end
		)

		it(
			"interrupteur coupé (clé absente) et charges hostiles : aucune instance, aucune boucle, une seule écoute, aucune trace",
			function()
				local c = client()
				expect(c.WX.stats().connections).toBe(1)
				for _, w in
					{
						"x",
						42,
						{},
						{ kind = "storm", endsAt = T0 + 60 },
						{ kind = 2 },
						{ kind = 2, endsAt = 0 / 0 },
						{ kind = 2, endsAt = math.huge },
						{ kind = 2, endsAt = T0 + 1e9 },
						{ kind = 99, endsAt = T0 + 60 },
						{ kind = -1, endsAt = T0 + 60 },
					}
				do
					c.event({ weather = w })
					c.play(0.2)
					expect(c.world("Weather")).toBeNil()
					expect(c.WX.stats().looping).toBe(0)
					expect(c.WX.stats().connections).toBe(1)
				end
				expect(#c.sounds).toBe(0)
				clean(c.h)
			end
		)
	end)

	-- =============================================================================================
	-- Place en fête
	-- =============================================================================================

	-- Points du dessin réel d'une pièce (coins d'un bloc, bords d'un cylindre, extrêmes d'une boule)
	local function samples(p)
		local cf, s = p.CFrame, p.Size
		local out = {}
		if p.Shape == Enum.PartType.Ball then
			local r = s.X / 2
			for _, d in
				{
					Vector3.new(r, 0, 0),
					Vector3.new(-r, 0, 0),
					Vector3.new(0, r, 0),
					Vector3.new(0, -r, 0),
					Vector3.new(0, 0, r),
					Vector3.new(0, 0, -r),
				}
			do
				table.insert(out, cf.Position + d)
			end
		elseif p.Shape == Enum.PartType.Cylinder then
			local r = math.min(s.Y, s.Z) / 2
			for _, x in { -s.X / 2, s.X / 2 } do
				for k = 0, 15 do
					local a = k * math.pi / 8
					table.insert(out, (cf * CFrame.new(x, r * math.cos(a), r * math.sin(a))).Position)
				end
			end
		else
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						table.insert(out, (cf * CFrame.new(x * s.X / 2, y * s.Y / 2, z * s.Z / 2)).Position)
					end
				end
			end
		end
		return out
	end

	local ELEVATED = 8 -- WorldLayout.Const.V2Elevated : un décor dont le bas est à ≥ 8 studs est en hauteur

	describe("Fete (lot B5, étape 5)", function()
		it(
			"niveaux 0 → 5 cumulés puis retour à 0 : pièces de chaque niveau, budget « fete » (40 pièces, 20 particules) jamais dépassé, rien à 0",
			function()
				local c = client()
				local total = 0
				for level = 1, 5 do
					c.event({ fete = { level = level } })
					total += c.FE.planCount(level)
					expect(c.FE.level()).toBe(level)
					expect(c.FE.stats().parts).toBe(total)
					expect(c.VB.used("fete")).toBe(total)
					local folder = c.world("Fete")
					for l = 1, 5 do
						expect(folder:FindFirstChild("Level" .. l) ~= nil).toBe(l <= level)
					end
				end
				expect(total).toBeLessThanOrEqual(40)
				expect(c.FE.planCount(1)).toBe(8)
				expect(c.FE.planCount(2)).toBe(8)
				expect(c.FE.planCount(3)).toBe(10)
				expect(c.FE.planCount(4)).toBe(0)
				expect(c.FE.planCount(5)).toBe(7)
				expect(c.VB.used("fete", "particles")).toBe(20)
				-- descente (nouveau serveur) : tout part, sans annonce
				local toasts = #c.toasts
				c.event({ fete = { level = 2 } })
				expect(c.FE.stats().parts).toBe(16)
				expect(c.FE.stats().looping).toBe(0)
				expect(c.VB.used("fete", "particles")).toBe(0)
				c.event({ fete = { level = 0 } })
				expect(c.world("Fete")).toBeNil()
				expect(c.VB.used("fete")).toBe(0)
				expect(#c.toasts).toBe(toasts)
				clean(c.h)
			end
		)

		it(
			"emprises : chaque pièce dans son emprise ; au sol, hors du point d'apparition neutre, du disque du kiosque, du MEGA pad, de la boutique, de l'autel, du socle de la statue, de la jarre et des nœuds des rues",
			function()
				local c = client()
				c.event({ fete = { level = 5 } })
				local feet = {}
				for _, f in c.FE.footprints() do
					feet[f.name] = f
				end
				local checked = 0
				for _, d in c.world("Fete"):GetDescendants() do
					if d:IsA("BasePart") then
						local f = feet[d:GetAttribute("Footprint")]
						expect(f).toBeTruthy()
						for _, q in samples(d) do
							local flat = math.sqrt((q.X - f.x) ^ 2 + (q.Z - f.z) ^ 2)
							expect(flat).toBeLessThanOrEqual(f.r + 1e-6)
							expect(q.Y).toBeGreaterThanOrEqual(f.bottom - 1e-6)
							expect(q.Y).toBeLessThanOrEqual(f.top + 1e-6)
						end
						checked += 1
					end
				end
				expect(checked).toBe(33)
				local WL = c.WL
				local K = WL.Const
				local discs = {
					{ "kiosque", WL.plaza("kiosk"), K.KioskRadius },
					{ "MEGA pad", WL.plaza("megaPad"), 15.75 },
					{ "boutique", WL.plaza("shop"), 5 },
					{ "autel", WL.plaza("altar"), 6.5 },
					{ "statue", WL.plaza("statue"), 5 },
					{ "jarre", WL.plaza("gauge"), 4.5 },
					{ "fontaine dorée", WL.plaza("goldenFountain"), 4 },
				}
				local nodes = WL.graph().nodes
				local ground = 0
				for _, f in c.FE.footprints() do
					if f.bottom < ELEVATED then
						ground += 1
						for _, z in discs do
							local dist = math.sqrt((f.x - z[2].X) ^ 2 + (f.z - z[2].Z) ^ 2)
							if dist < f.r + z[3] then
								error(f.name .. " empiète sur " .. z[1])
							end
						end
						-- point d'apparition neutre : carré 6 × 6 en (−24, 24)
						local nx = math.clamp(f.x, -27, -21)
						local nz = math.clamp(f.z, 21, 27)
						expect(math.sqrt((f.x - nx) ^ 2 + (f.z - nz) ^ 2)).toBeGreaterThan(f.r)
						for i, n in nodes do
							if math.sqrt((f.x - n.X) ^ 2 + (f.z - n.Z) ^ 2) <= f.r + 1 then
								error(f.name .. " sur le nœud de rue " .. i)
							end
						end
						-- jamais sur une rue radiale (10 studs de large, r 50 → 160)
						local r = math.sqrt(f.x ^ 2 + f.z ^ 2)
						if r > 45 and r < 165 then
							local a = math.atan2(f.z, f.x)
							local best = math.huge
							for k = 0, 7 do
								local da = math.abs((a - k * math.pi / 4 + math.pi) % (2 * math.pi) - math.pi)
								best = math.min(best, r * math.sin(math.min(da, math.pi / 2)))
							end
							expect(best - f.r).toBeGreaterThan(5)
						end
					end
				end
				expect(ground).toBe(6) -- ballons, 4 piliers, statue
				clean(c.h)
			end
		)

		it(
			"feux d'artifice (niveau 4) : une gerbe toutes les 6 s au-dessus de la place, par le quota des effets, 0 pièce ; la boucle s'arrête sous le niveau 4",
			function()
				local c = client()
				c.event({ fete = { level = 3 } })
				expect(c.FE.stats().looping).toBe(0)
				c.event({ fete = { level = 4 } })
				expect(c.FE.stats().looping).toBe(1)
				c.play(12.1)
				expect(c.FE.stats().bursts).toBe(2)
				expect(c.FE.stats().parts).toBe(26)
				c.event({ fete = { level = 3 } })
				expect(c.FE.stats().looping).toBe(0)
				c.play(7)
				expect(c.FE.stats().bursts).toBe(2)
				clean(c.h)
			end
		)

		it(
			"annonce : Toast « Square party: level n » et FeteLevel → LevelUp quand le niveau MONTE en partie ; jamais au chargement, rien quand il baisse",
			function()
				local c = client({ ev = { fete = { level = 3 } } })
				expect(c.FE.level()).toBe(3)
				expect(#c.toasts).toBe(0)
				expect(#c.sounds).toBe(0)
				c.event({ fete = { level = 3 } })
				expect(#c.toasts).toBe(0)
				c.event({ fete = { level = 4 } })
				expect(c.toasts[1]).toBe("Square party: level 4")
				expect(c.sounds[1]).toBe("LevelUp")
				c.event({ fete = { level = 1 } })
				c.event({ fete = { level = 0 } })
				expect(#c.toasts).toBe(1)
				clean(c.h)
			end
		)

		it(
			"interrupteur coupé (clé absente) et charges hostiles : aucune instance, aucune boucle, une seule écoute",
			function()
				local c = client()
				expect(c.FE.stats().connections).toBe(1)
				for _, f in { "x", 3, {}, { level = "5" }, { level = 0 / 0 }, { level = -2 } } do
					c.event({ fete = f })
					expect(c.world("Fete")).toBeNil()
					expect(c.FE.stats().looping).toBe(0)
				end
				-- niveau trop grand : borné à 5
				c.event({ fete = { level = 99 } })
				expect(c.FE.level()).toBe(5)
				expect(#c.toasts).toBe(1)
				clean(c.h)
			end
		)
	end)

	describe("météo et fête : aucune fuite (lot B5, étape 5)", function()
		it(
			"120 cycles tirés au hasard (graine fixe) de fenêtres, sortes, niveaux et coupures, images sur l'horloge figée : instances, connexions et budgets revenus à zéro",
			function()
				local c = client()
				local base = c.count()
				-- tirage à graine fixe (générateur congruentiel : Random n'existe pas sous Lune)
				local seed = 5112026
				local rng = {}
				function rng:NextNumber()
					seed = (seed * 1103515245 + 12345) % 2147483648
					return seed / 2147483648
				end
				function rng:NextInteger(a, b)
					return a + math.floor(self:NextNumber() * (b - a + 1))
				end
				for _ = 1, 120 do
					local over = {}
					if rng:NextNumber() < 0.7 then
						over.weather =
							{ kind = rng:NextInteger(1, 4), endsAt = c.Clock.unix() + rng:NextInteger(1, 30) }
					end
					if rng:NextNumber() < 0.7 then
						over.fete = { level = rng:NextInteger(0, 5) }
					end
					c.event(over)
					if rng:NextNumber() < 0.5 then
						c.frozen(rng:NextNumber() * 2)
					else
						c.play(rng:NextNumber() * 8)
					end
				end
				c.event({})
				c.play(1)
				expect(c.count()).toBe(base)
				expect(c.WX.stats().connections).toBe(1)
				expect(c.FE.stats().connections).toBe(1)
				expect(c.VB.used("weather")).toBe(0)
				expect(c.VB.used("weather", "particles")).toBe(0)
				expect(c.VB.used("fete")).toBe(0)
				expect(c.VB.used("fete", "particles")).toBe(0)
				clean(c.h)
			end
		)
	end)
end
