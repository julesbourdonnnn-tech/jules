--!nocheck
-- QA ronde 1, paquet « divers » (socle client et aides) :
--   * Root : le conteneur Safe couvre tout l'écran APRÈS la mise à l'échelle (UIScale autour du
--     coin haut gauche), à toutes les résolutions ; échelle bornée 0,6–1,25 (GDD §10.1)
--   * Toast : la pile commence sous les bannières, la pastille d'événement et la barre de la Balise
--   * OnboardingPlan : rentrer dès que la file contient l'objectif, Puffkins disparus, Glow
--     insuffisant après la première parade, Q6 sans météo (attente / Comète)
--   * NestDisplay : anneau de progression vers la Supernova autour du Nid local (GDD §3)
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000
	local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")

	-- Root / Toast ------------------------------------------------------------------------------

	local function uiSetup()
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Root = h:require(CLIENT .. "UI.Root")
		Root.Init()
		return h, Root
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	local function expectCovers(safe, s)
		expect(safe.AnchorPoint.X).toBe(0)
		expect(safe.AnchorPoint.Y).toBe(0)
		expect(safe.Position.X.Scale).toBe(0)
		expect(safe.Position.Y.Scale).toBe(0)
		-- taille × échelle = tout l'écran (UIScale appliqué autour du coin haut gauche)
		expect(near(safe.Size.X.Scale * s, 1)).toBe(true)
		expect(near(safe.Size.Y.Scale * s, 1)).toBe(true)
		expect(safe.Size.X.Offset).toBe(0)
		expect(safe.Size.Y.Offset).toBe(0)
		expect(near(safe.RootScale.Scale, s)).toBe(true)
	end

	describe("Fix divers r1 › Root : Safe plein écran à toutes les résolutions", function()
		it("1280×720 : échelle 1, Safe = écran", function()
			local h, Root = uiSetup()
			local safe = Root.safe("TestA", 5)
			expect(Root.scale()).toBe(1)
			expectCovers(safe, 1)
			expect(h.localPlayer.PlayerGui.TestA.ResetOnSpawn).toBe(false)
		end)

		it("téléphone 844×390 : échelle 0,6 et Safe agrandi de 1/0,6", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390)
			local safe = Root.safe("TestB", 5)
			expect(Root.scale()).toBe(0.6)
			expectCovers(safe, 0.6)
		end)

		it("PC 1920×1080 : échelle plafonnée à 1,25 (GDD §10.1), Safe réduit d'autant", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
			local safe = Root.safe("TestC", 5)
			expect(Root.scale()).toBe(1.25)
			expectCovers(safe, 1.25)
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(3840, 2160)
			expect(Root.scale()).toBe(1.25)
		end)

		it("écran 4:3 : le cadre de référence 1280 de large tient (rapport de largeur)", function()
			local h, Root = uiSetup()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1024, 768)
			expect(near(Root.scale(), 0.8)).toBe(true)
			expectCovers(Root.safe("TestD", 5), 0.8)
		end)

		it("rotation / redimensionnement : tous les écrans suivent, écrans détruits oubliés", function()
			local h, Root = uiSetup()
			local a = Root.safe("TestE", 5)
			local b = Root.safe("TestF", 6)
			local gone = Root.screen("TestG", 7)
			gone:Destroy()
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390)
			h:settle(1)
			expectCovers(a, 0.6)
			expectCovers(b, 0.6)
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1280, 720)
			h:settle(1)
			expectCovers(a, 1)
			expectCovers(b, 1)
			-- viewport dégénéré (caméra pas prête) : échelle 1, jamais de division par zéro
			h.workspace.CurrentCamera.ViewportSize = Vector2.new(1, 1)
			h:settle(1)
			expectCovers(a, 1)
		end)

		it(
			"un élément ancré à droite (1, −16) reste dans l'écran quelle que soit l'échelle",
			function()
				local h, Root = uiSetup()
				for _, size in { Vector2.new(844, 390), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
					h.workspace.CurrentCamera.ViewportSize = size
					h:settle(1)
					local safe = Root.safe("TestH", 5)
					local s = Root.scale()
					-- position écran du bord droit d'un enfant en (1, −16) : (Safe.X.Scale × W − 16) × s
					local right = (safe.Size.X.Scale * size.X - 16) * s
					expect(right <= size.X).toBe(true)
					expect(right >= size.X - 16 * 1.25 - 1e-6).toBe(true)
				end
			end
		)
	end)

	describe("Fix divers r1 › Toast : sous les bannières", function()
		it("la pile commence sous la zone des bannières (y ≥ 72 + 72 + 34)", function()
			local h = uiSetup()
			local Toast = h:require(CLIENT .. "UI.Toast")
			Toast.show("Quest complete!", "success")
			local stack = h.localPlayer.PlayerGui.Toasts.Safe.Stack
			-- bannière (Banners : TOP_Y 72, 72 de haut) décalée de 34 pendant la barre de la Balise
			expect(stack.Position.Y.Scale).toBe(0)
			expect(stack.Position.Y.Offset >= 72 + 72 + 34).toBe(true)
			expect(stack.Position.X.Scale).toBe(0.5)
			expect(stack.AnchorPoint.X).toBe(0.5)
			-- 3 toasts au plus, toujours dans la pile
			for i = 1, 5 do
				Toast.show("t" .. i)
			end
			local n = 0
			for _, child in stack:GetChildren() do
				if child.Name == "Toast" then
					n += 1
				end
			end
			expect(n <= 3).toBe(true)
		end)
	end)

	-- OnboardingPlan (règles pures) -------------------------------------------------------------

	describe("Fix divers r1 › OnboardingPlan : une instruction toujours réalisable", function()
		local h = Harness.new({ mode = "client" })
		local Plan = h:require(CLIENT .. "UI.Hud.OnboardingPlan")

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

		it("Q4 : Rare attrapé mais pas encaissé → retour au Nid (pas le Rare suivant)", function()
			local f = facts({
				step = 4,
				parades = 3,
				conga = 2,
				lineCount = 2,
				rareTarget = true,
				goalInLine = true,
			})
			expect(Plan.hint(f)).toBe("onboarding.goHome")
			expect(Plan.guide(f)).toBe("toGate")
			-- pas encore de Rare dans la file : pilier bleu et consigne d'origine
			f.goalInLine = false
			expect(Plan.hint(f)).toBe("onboarding.catchRare")
			expect(Plan.guide(f)).toBe("toRare")
		end)

		it("Q1 / Q3 : taille de parade atteinte sous le plafond → retour au Nid", function()
			-- Q1 « Parade de 4 » avec un niveau de Conga de plus (plafond 5) et 4 dans la file
			local q1 = facts({ step = 1, parades = 1, conga = 2, lineCount = 4 })
			expect(Plan.hint(q1)).toBe("onboarding.goHome")
			expect(Plan.guide(q1)).toBe("toGate")
			q1.lineCount = 3
			expect(Plan.hint(q1)).toBe("onboarding.findNebbies")
			expect(Plan.guide(q1)).toBe("toNebbies")
			-- Q3 « Parade de 6 » avec un plafond de 7
			local q3 = facts({ step = 3, parades = 4, conga = 3, lineCount = 6 })
			expect(Plan.hint(q3)).toBe("onboarding.goHome")
			expect(Plan.guide(q3)).toBe("toGate")
			q3.lineCount = 5
			expect(Plan.hint(q3)).toBe("onboarding.findNebbies")
		end)

		it("quêtes sans lien avec la file : goalInLine ignoré", function()
			local q5 = facts({
				step = 5,
				parades = 5,
				conga = 2,
				lineCount = 9,
				goalInLine = true,
				canBuyStride = true,
			})
			expect(Plan.hint(q5)).toBe("onboarding.buyStride")
		end)

		it("Puffkins disparus avant la première parade → chercher des Nebbies sauvages", function()
			local gone = facts({ puffkinsLeft = 0 })
			expect(Plan.hint(gone)).toBe("onboarding.findNebbies")
			expect(Plan.guide(gone)).toBe("toNebbies")
			-- 1 ou 2 dans la file, les autres perdus : on complète avec des sauvages
			gone.lineCount = 2
			expect(Plan.hint(gone)).toBe("onboarding.findNebbies")
			gone.lineCount = 3
			expect(Plan.hint(gone)).toBe("onboarding.goHome")
			expect(Plan.guide(gone)).toBe("toGate")
			-- Puffkins encore là : consigne d'origine
			local here = facts({ puffkinsLeft = 2, lineCount = 1 })
			expect(Plan.hint(here)).toBe("onboarding.catch")
			expect(Plan.guide(here)).toBe("toPuffkins")
		end)

		it(
			"première parade maigre (Conga +1 pas payable) → Nebbies jusqu'à 50 Glow, puis Améliorer",
			function()
				local short = facts({ parades = 1, canBuyConga = false, puffkinsLeft = 1 })
				expect(Plan.hint(short)).toBe("onboarding.findNebbies")
				expect(Plan.guide(short)).toBe("toNebbies")
				expect(Plan.attention(short)["rail.Upgrades"]).toBeNil()
				short.lineCount, short.lineFull = 3, true
				expect(Plan.hint(short)).toBe("onboarding.goHome")
				expect(Plan.guide(short)).toBe("toGate")
				-- Glow prédit suffisant : invitation à acheter, avec la main
				local rich = facts({ parades = 1, canBuyConga = true, puffkinsLeft = 0 })
				expect(Plan.hint(rich)).toBe("onboarding.tapUpgrade")
				expect(Plan.guide(rich)).toBeNil()
				expect(Plan.attention(rich)["rail.Upgrades"]).toBe(true)
				rich.upgradesOpen = true
				expect(Plan.hint(rich)).toBe("onboarding.buyConga")
			end
		)

		it("faits de terrain absents (appelant d'origine) : règles d'origine inchangées", function()
			expect(Plan.hint(facts())).toBe("onboarding.catch")
			expect(Plan.hint(facts({ parades = 1 }))).toBe("onboarding.tapUpgrade")
			expect(Plan.guide(facts({ parades = 1 }))).toBeNil()
			expect(Plan.hint(facts({ step = 6 }))).toBe("onboarding.weather")
			expect(Plan.guide(facts({ step = 6 }))).toBeNil()
			expect(Plan.hint(facts({ step = 4 }))).toBe("onboarding.catchRare")
		end)

		it("Q6 : Nebby météo connu → pilier/flèche ; fenêtre ouverte → Nebbies", function()
			local f = facts({ step = 6, parades = 6, conga = 2, weatherActive = true, weatherTarget = true })
			expect(Plan.hint(f)).toBe("onboarding.weather")
			expect(Plan.guide(f)).toBe("toWeather")
			f.weatherTarget = false
			expect(Plan.hint(f)).toBe("onboarding.weather")
			expect(Plan.guide(f)).toBe("toNebbies")
		end)

		it("Q6 : Comète au sol ou portée sans météo → « Rejoins la Comète » et guidage", function()
			local f = facts({
				step = 6,
				parades = 6,
				conga = 2,
				weatherActive = false,
				weatherTarget = false,
				cometActive = true,
			})
			expect(Plan.hint(f)).toBe("onboarding.joinComet")
			expect(Plan.guide(f)).toBe("toComet")
			-- météo ET Comète : le Nebby météo (sûr) passe d'abord
			f.weatherTarget = true
			expect(Plan.guide(f)).toBe("toWeather")
		end)

		it(
			"Q6 : ni météo ni Comète → « Météo bientôt » et la pastille d'événement pulse",
			function()
				local f = facts({
					step = 6,
					parades = 6,
					conga = 2,
					weatherActive = false,
					weatherTarget = false,
					cometActive = false,
				})
				expect(Plan.hint(f)).toBe("onboarding.waitWeather")
				expect(Plan.guide(f)).toBeNil()
				expect(Plan.attention(f).eventPill).toBe(true)
				-- file pleine : rentrer passe avant l'attente
				f.lineFull = true
				expect(Plan.hint(f)).toBe("onboarding.goHome")
			end
		)

		it("nouvelles clés traduites (anglais et français, ≤ 4 mots)", function()
			local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
			for _, key in { "onboarding.waitWeather", "onboarding.joinComet" } do
				for _, lang in { "en", "fr" } do
					local text = Strings[lang][key]
					expect(type(text)).toBe("string")
					local words = 0
					for _ in string.gmatch(text, "[^%s☁!]+") do
						words += 1
					end
					expect(words <= 4).toBe(true)
				end
			end
		end)
	end)

	-- NestDisplay : anneau de la Supernova ------------------------------------------------------

	local function ringSetup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			State = h:require(CLIENT .. "Controllers.StateController"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Formulas = h:require("ReplicatedStorage.Shared.Logic.Formulas"),
			Schema = Schema,
		}
		if opts.reduced then
			h.game.GuiService.ReducedMotionEnabled = true
		end
		c.State.Init()
		c.WSC.Init()
		c.CR.Init()
		c.WSC.Start()
		c.CR.Start()
		return c
	end

	local function fakeNest(c, slot, owner)
		local g = c.g
		local model = g.Instance.new("Model")
		model.Name = string.format("Nest_%02d", slot)
		model:SetAttribute("Slot", slot)
		model:SetAttribute("OwnerUserId", owner or 0)
		model:SetAttribute("OwnerName", "")
		model:SetAttribute("PerchCount", 0)
		model:SetAttribute("PerchData", "")
		model:SetAttribute("Supernovas", 0)
		local perches = g.Instance.new("Folder")
		perches.Name = "Perches"
		perches.Parent = model
		model.Parent = c.h.workspace
		c.h.game.CollectionService:AddTag(model, "Nest")
		return model
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.1)
			c.h:step(dt or 0.1, 1)
		end
		c.h:settle(1)
	end

	local function load(c, over)
		local p = c.Schema.defaults()
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

	local function ring(c)
		return c.CR.NestDisplay.supernovaRing()
	end

	local function placeLocal(c, slot)
		c.h.localPlayer:SetAttribute("Slot", slot)
		c.h.localPlayer.Character.HumanoidRootPart.CFrame =
			CFrame.new(c.WorldLayout.nestCenter(slot) + Vector3.new(0, 3, 0))
	end

	describe("Fix divers r1 › NestDisplay : anneau de progression vers la Supernova", function()
		it("caché pendant Q1-Q4, affiché à Q5 autour du Nid local, rempli selon Glow / coût", function()
			local c = ringSetup()
			fakeNest(c, 3, 1)
			placeLocal(c, 3)
			load(c, { onboarding = { step = 4, p = 0 }, glow = 0, supernovas = 0 })
			frames(c, 5)
			expect(ring(c).shown).toBe(false)
			local cost = c.Formulas.supernovaCost(0)
			patch(c, { onboarding = { step = 5, p = 0 }, glow = math.floor(cost / 4) })
			frames(c, 5)
			local r = ring(c)
			expect(r.shown).toBe(true)
			expect(r.slot).toBe(3)
			expect(r.lit).toBe(math.floor(r.segments / 4))
			expect(r.label).toBe("✺ Supernova 25%")
			-- segments autour du Nid 3, au ras de la plateforme, ancrés et sans collision
			local center = c.WorldLayout.nestCenter(3)
			for _, part in r.parts do
				local d = Vector3.new(part.Position.X - center.X, 0, part.Position.Z - center.Z).Magnitude
				expect(d > 14.1 and d < 17).toBe(true)
				expect(part.Position.Y > 0.2 and part.Position.Y < 0.5).toBe(true)
				expect(part.Anchored).toBe(true)
				expect(part.CanCollide).toBe(false)
				expect(part.CanQuery).toBe(false)
			end
			-- premiers segments allumés (dorés, opaques), les autres en veille
			expect(r.parts[1].Transparency).toBe(0)
			expect(r.parts[r.segments].Transparency > 0).toBe(true)
		end)

		it("joueur qui revient (accueil fini) : affiché d'emblée ; suit le Glow et la langue", function()
			local c = ringSetup()
			fakeNest(c, 5, 1)
			placeLocal(c, 5)
			local cost = c.Formulas.supernovaCost(2)
			load(c, { onboarding = { step = 8, p = 0 }, glow = math.floor(cost / 2), supernovas = 2 })
			frames(c, 3)
			expect(ring(c).shown).toBe(true)
			expect(ring(c).lit).toBe(ring(c).segments / 2)
			expect(ring(c).label).toBe("✺ Supernova 50%")
			c.Prefs._onSettings({ lang = "fr" })
			frames(c, 4)
			expect(ring(c).label).toBe("✺ Supernova 50 %")
			-- achat : le Glow baisse, l'anneau aussi
			patch(c, { glow = math.floor(cost / 10) })
			frames(c, 4)
			expect(ring(c).lit).toBe(math.floor(ring(c).segments / 10))
		end)

		it("Supernova payable : anneau complet, étiquette « prête » et pulsation", function()
			local c = ringSetup()
			fakeNest(c, 2, 1)
			placeLocal(c, 2)
			local cost = c.Formulas.supernovaCost(0)
			load(c, { onboarding = { step = 8, p = 0 }, glow = cost, supernovas = 0 })
			frames(c, 3)
			local r = ring(c)
			expect(r.ready).toBe(true)
			expect(r.lit).toBe(r.segments)
			expect(r.label).toBe("✺ Supernova ready!")
			local seen = {}
			for _ = 1, 14 do
				frames(c, 1)
				seen[r.parts[1].Transparency] = true
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			expect(n >= 2).toBe(true) -- la transparence varie : ça pulse
			-- Supernova faite : R + 1, Glow remis à zéro → anneau vide, plus de pulsation
			patch(c, { glow = 0, supernovas = 1 })
			frames(c, 4)
			expect(ring(c).ready).toBe(false)
			expect(ring(c).lit).toBe(0)
		end)

		it("Mouvement réduit : pas de pulsation (anneau stable)", function()
			local c = ringSetup({ reduced = true })
			fakeNest(c, 2, 1)
			placeLocal(c, 2)
			load(c, { onboarding = { step = 8, p = 0 }, glow = c.Formulas.supernovaCost(0), supernovas = 0 })
			frames(c, 3)
			local r = ring(c)
			local first = r.parts[1].Transparency
			for _ = 1, 14 do
				frames(c, 1)
				expect(r.parts[1].Transparency).toBe(first)
			end
		end)

		it("Nid local inconnu ou perdu : anneau caché ; nouveau Nid : anneau déplacé", function()
			local c = ringSetup()
			fakeNest(c, 4, 1)
			fakeNest(c, 9, 1)
			load(c, { onboarding = { step = 8, p = 0 }, glow = 1000, supernovas = 0 })
			frames(c, 3)
			expect(ring(c).shown).toBe(false) -- pas encore de Nid attribué
			placeLocal(c, 4)
			frames(c, 3)
			expect(ring(c).shown).toBe(true)
			expect(ring(c).slot).toBe(4)
			c.h.localPlayer:SetAttribute("Slot", 9)
			frames(c, 3)
			expect(ring(c).slot).toBe(9)
			local center = c.WorldLayout.nestCenter(9)
			local p = ring(c).parts[1].Position
			expect(Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude < 17).toBe(true)
			c.h.localPlayer:SetAttribute("Slot", 0)
			frames(c, 3)
			expect(ring(c).shown).toBe(false)
			for _, part in ring(c).parts do
				expect(part.Transparency).toBe(1)
			end
		end)

		it("profil hostile (valeurs non finies) : aucune erreur, anneau borné", function()
			local c = ringSetup()
			fakeNest(c, 6, 1)
			placeLocal(c, 6)
			load(c, { onboarding = { step = 0 / 0 }, glow = math.huge, supernovas = -5 })
			frames(c, 3)
			expect(ring(c).shown).toBe(false)
			patch(c, { onboarding = { step = 8 }, glow = 0 / 0, supernovas = 0 / 0 })
			frames(c, 3)
			expect(ring(c).shown).toBe(true)
			expect(ring(c).lit >= 0 and ring(c).lit <= ring(c).segments).toBe(true)
			patch(c, { onboarding = "x", glow = "y" })
			frames(c, 3)
			expect(ring(c).shown).toBe(false)
			expect(#c.h.errors).toBe(0)
		end)
	end)
end
