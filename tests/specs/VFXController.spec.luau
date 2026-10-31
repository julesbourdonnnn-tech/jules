--!nocheck
-- VFXController (paquet client-world) : effets 3D du GDD §9 — fonctions communes (§9.1 : textes
-- flottants en réserve, anneaux, particules sous budget, colonnes, focale, vibration, feux),
-- réactions aux signaux de WorldStateController (capture, coupe, parade, Comète, Gloomwisp,
-- pings), Supernova sur l'attribut des Nids, Dash, amélioration, marques de joueurs (Zen,
-- équipier, immunité), Mouvement réduit et Graphismes légers.
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	local function fakeNest(h, slot, attrs)
		local g = h.globals
		local model = g.Instance.new("Model")
		model.Name = string.format("Nest_%02d", slot)
		model:SetAttribute("Slot", slot)
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("Supernovas", 0)
		model:SetAttribute("PerchCount", 0)
		model:SetAttribute("PerchData", "")
		for k, v in attrs or {} do
			model:SetAttribute(k, v)
		end
		local perches = g.Instance.new("Folder")
		perches.Name = "Perches"
		perches.Parent = model
		model.Parent = h.workspace
		h.game.CollectionService:AddTag(model, "Nest")
		return model
	end

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			FloatText = h:require(CLIENT .. "World.FloatText"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
		}
		if opts.nests then
			for slot, attrs in opts.nests do
				fakeNest(h, slot, attrs)
			end
		end
		if opts.settings then
			c.Prefs._onSettings(opts.settings)
		end
		c.State.Init()
		c.WSC.Init()
		c.CR.Init()
		c.VFX.Init()
		c.WSC.Start()
		c.CR.Start()
		c.VFX.Start()
		return c
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.05)
			c.h:step(dt or 0.05, 1)
		end
	end

	local function fire(c, remote, ...)
		c.h:fireClient(REMOTES .. remote, ...)
	end

	local function vfxFolder(c)
		return c.h.workspace.ClientWorld.VFX
	end

	local function childrenNamed(parent, name)
		local n = 0
		for _, child in parent:GetChildren() do
			if child.Name == name then
				n += 1
			end
		end
		return n
	end

	-- textes flottants actuellement affichés
	local function floatTexts(c)
		local out = {}
		local folder = c.h.workspace.ClientWorld:FindFirstChild("FloatText")
		if folder == nil then
			return out
		end
		for _, attachment in folder.FloatAnchor:GetChildren() do
			local gui = attachment:FindFirstChild("Text")
			if gui and gui.Enabled then
				table.insert(out, gui.Label.Text)
			end
		end
		return out
	end

	local function contains(list, text)
		return table.find(list, text) ~= nil
	end

	local function root(c)
		return c.h.localPlayer.Character.HumanoidRootPart
	end

	local function snapshot(c, lines, extra)
		local snap = {
			serverTime = T0,
			tick = 1,
			lines = lines or {},
			paths = c.PathCodec.encode(1, {}),
			wild = {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 1 },
			crews = { crews = {} },
		}
		for k, v in extra or {} do
			snap[k] = v
		end
		fire(c, "WorldSnapshot", snap)
	end

	describe("VFXController › fonctions communes (§9.1)", function()
		it(
			"textes flottants : réserve de 20 BillboardGui réutilisés, aucune création en rafale",
			function()
				local c = setup()
				for i = 1, 50 do
					c.VFX.floatText(Vector3.new(i, 3, 0), "+" .. i, c.g.Color3.new(1, 1, 1), 1)
				end
				expect(c.FloatText.poolSize()).toBe(c.Balance.Render.FloatTextPool)
				expect(c.FloatText.activeCount() <= 20).toBe(true)
				expect(contains(floatTexts(c), "+50")).toBe(true)
				-- NaN : ignoré
				c.VFX.floatText(Vector3.new(0 / 0, 0, 0), "x", c.g.Color3.new(1, 1, 1))
				c.h:settle(2)
				c.Clock.advance(2)
				task.wait(1.2)
				c.h:settle(2)
				expect(c.FloatText.activeCount()).toBe(0)
			end
		)

		it(
			"anneau, colonne et particules : pièces en réserve rendues, budget ≤ 300, × 0,3 en Graphismes légers",
			function()
				local c = setup()
				c.VFX.ring(Vector3.new(0, 0, 0), 12, c.g.Color3.new(1, 0, 0), 0.05)
				c.VFX.pillar(Vector3.new(5, 0, 0), c.g.Color3.new(0, 1, 0), 0.05, 30)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(2)
				local ring
				for _, child in vfxFolder(c):GetChildren() do
					if child.Name == "FxRing" and child.Size.Y > 20 then
						ring = child
					end
				end
				expect(ring ~= nil).toBe(true) -- 0 → 12 studs de rayon (tween)
				task.wait(0.1)
				c.h:settle(2)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0)
				for _ = 1, 40 do
					c.VFX.burst(Vector3.new(0, 0, 0), c.g.Color3.new(1, 1, 1), 30)
				end
				expect(c.VFX.particlesAlive() <= c.Balance.Render.MaxParticles).toBe(true)
				expect(c.VFX.particlesAlive()).toBe(c.Balance.Render.MaxParticles)
				c.Clock.advance(1.5)
				c.Prefs._onSettings({ lowGraphics = true })
				c.VFX.burst(Vector3.new(0, 0, 0), c.g.Color3.new(1, 1, 1), 10)
				expect(c.VFX.particlesAlive()).toBe(3)
				-- valeurs absurdes ignorées
				c.VFX.burst(Vector3.new(0, 0, 0), c.g.Color3.new(1, 1, 1), 0 / 0)
				c.VFX.ring(Vector3.new(0, 0, 0), -1, c.g.Color3.new(1, 1, 1), 1)
				c.VFX.haptic(0.5, 0.1)
				c.VFX.fireworks(Vector3.new(0, 0, 0), 3)
				task.wait(0.6)
				c.h:settle(3)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("coup de focale 70 → 78 → 70 ; ignoré en Mouvement réduit", function()
			local c = setup()
			local camera = c.h.workspace.CurrentCamera
			c.VFX.fovPunch(8, 0.12, 0.5)
			expect(camera.FieldOfView).toBe(78)
			c.h:settle(3)
			expect(camera.FieldOfView).toBe(70)
			c.Prefs._onSettings({ reducedMotion = true })
			c.VFX.fovPunch(8, 0.12, 0.5)
			expect(camera.FieldOfView).toBe(70)
		end)
	end)

	describe("VFXController › Dash, amélioration, Supernova", function()
		it("Dash : Trail aux pieds pendant 1 s et focale ; pas de Trail en Graphismes légers", function()
			local c = setup()
			c.VFX.playDash()
			expect(root(c):FindFirstChild("DashTrail") ~= nil).toBe(true)
			expect(c.h.workspace.CurrentCamera.FieldOfView).toBe(78)
			task.wait(1.1)
			c.h:settle(2)
			expect(root(c):FindFirstChild("DashTrail")).toBeNil()
			c.Prefs._onSettings({ lowGraphics = true })
			c.VFX.playDash()
			expect(root(c):FindFirstChild("DashTrail")).toBeNil()
		end)

		it("amélioration : anneau au sol, fantôme au bout de la file (Conga)", function()
			local c = setup()
			c.VFX.playUpgrade("conga", 4)
			expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(1)
			expect(childrenNamed(vfxFolder(c), "FxBall")).toBe(1)
			c.VFX.playUpgrade("perches", 2)
			c.VFX.playUpgrade("unknown", 1)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"une hausse de l'attribut Supernovas d'un Nid occupé lance la séquence (pas une arrivée)",
			function()
				local c = setup({ nests = { [3] = { OwnerUserId = 1, Supernovas = 2 } } })
				c.h.localPlayer:SetAttribute("Slot", 3)
				local calls = {}
				local original = c.VFX.playSupernova
				c.VFX.playSupernova = function(slot, level)
					table.insert(calls, { slot, level })
					original(slot, level)
				end
				local model = c.CR.NestDisplay.model(3)
				model:SetAttribute("Supernovas", 3)
				expect(#calls).toBe(1)
				expect(calls[1][1]).toBe(3)
				expect(calls[1][2]).toBe(3)
				-- nouveau propriétaire avec un R plus grand : pas de séquence
				model:SetAttribute("OwnerUserId", 0)
				model:SetAttribute("OwnerUserId", 9)
				model:SetAttribute("Supernovas", 7)
				expect(#calls).toBe(1)
				-- séquence : éclairage (héros, effet sur la caméra), faisceau, sphère, étoile qui pousse
				local camera = c.h.workspace.CurrentCamera
				expect(camera:FindFirstChild("VFXSupernova") ~= nil).toBe(true)
				expect(c.h.game.Lighting:FindFirstChildOfClass("ColorCorrectionEffect")).toBeNil()
				task.wait(0.7)
				c.h:settle(2)
				frames(c, 3)
				local star = c.CR.constellationStar(3, 3)
				expect(star ~= nil).toBe(true)
				task.wait(2.2)
				c.h:settle(3)
				expect(camera.VFXSupernova.Brightness).toBe(0)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("Mouvement réduit : pas de flash d'éclairage de Supernova", function()
			local c = setup({ settings = { reducedMotion = true } })
			c.h.localPlayer:SetAttribute("Slot", 2)
			c.VFX.playSupernova(2, 1)
			expect(c.h.workspace.CurrentCamera:FindFirstChild("VFXSupernova")).toBeNil()
			c.VFX.playSupernova(99, 1) -- slot invalide : ignoré
			expect(#c.h.errors).toBe(0)
		end)
	end)

	describe("VFXController › réactions aux signaux du monde", function()
		it(
			"capture locale : « +1 Puffkin », « ? » doré si l'entrée d'Atlas est nouvelle, colonne Rare+",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				fire(c, "DataSnapshot", { atlas = { 0, 0, 0, 0, 0, 0, 0 } })
				snapshot(c, { { slot = 2, userId = 1, ver = 0, codes = {} } }, {
					wild = {
						{ id = 4, code = 1, x = 2, z = 2, seed = 1, t0 = T0, life = 30 },
						{ id = 5, code = 17, x = 3, z = 2, seed = 2, t0 = T0, life = 30 },
					},
				})
				fire(c, "LineEvent", { { op = "add", slot = 2, ver = 1, codes = { 1, 17 }, ids = { 4, 5 } } })
				local texts = floatTexts(c)
				expect(contains(texts, "+1 Puffkin")).toBe(true)
				expect(contains(texts, "+1 Prismpaw")).toBe(true)
				expect(contains(texts, "?")).toBe(true)
				expect(childrenNamed(vfxFolder(c), "FxRing") >= 1).toBe(true) -- colonne du Rare
				expect(c.h.workspace.CurrentCamera.FieldOfView).toBe(70) -- pas d'Épique : pas de focale
			end
		)

		it(
			"capture Légendaire lointaine d'un autre joueur : colonne de 4 s visible de tout le serveur",
			function()
				local c = setup()
				snapshot(c, { { slot = 8, userId = 80, ver = 0, codes = {} } }, {
					wild = { { id = 9, code = 29, x = -150, z = -60, seed = 1, t0 = T0, life = 30 } },
				})
				fire(c, "LineEvent", { { op = "add", slot = 8, ver = 1, codes = { 29 }, ids = { 9 } } })
				local tall = 0
				for _, child in vfxFolder(c):GetChildren() do
					if child.Name == "FxRing" and child.Size.X >= 100 then
						tall += 1
					end
				end
				expect(tall).toBe(1)
				expect(#floatTexts(c)).toBe(0) -- pas de texte pour la capture d'un autre
			end
		)

		it(
			"coupe : « SNIP ! », anneau Snip Rush du coupeur local, traînées de la victime locale",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("Slot", 2)
				snapshot(c, {
					{ slot = 2, userId = 1, ver = 0, codes = {} },
					{ slot = 6, userId = 60, ver = 0, codes = {} },
				})
				fire(
					c,
					"LineEvent",
					{ { op = "add", slot = 6, ver = 1, codes = { 1, 1, 1 }, ids = { 0, 0, 0 } } }
				)
				fire(c, "SnipEvent", {
					snipperSlot = 2,
					victimSlot = 6,
					ver = 2,
					cutIndex = 2,
					count = 2,
					looseIds = {},
					loose = {},
					byWisp = false,
					x = 3,
					y = 3,
					z = 3,
					dust = 10,
				})
				expect(contains(floatTexts(c), "SNIP!")).toBe(true)
				frames(c, 2)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(1) -- anneau Snip Rush aux pieds
				frames(c, 70)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0) -- fini après 3 s
				-- coupe subie par le joueur local
				fire(c, "LineEvent", { { op = "add", slot = 2, ver = 1, codes = { 1, 1 }, ids = { 0, 0 } } })
				fire(c, "SnipEvent", {
					snipperSlot = 0,
					victimSlot = 2,
					ver = 2,
					cutIndex = 1,
					count = 2,
					looseIds = {},
					loose = {},
					byWisp = true,
					wispId = 1,
					x = 1,
					y = 3,
					z = 1,
					dust = 0,
				})
				expect(root(c):FindFirstChild("SecondWind") ~= nil).toBe(true)
				expect(contains(floatTexts(c), "nom!")).toBe(true)
			end
		)

		it("parade locale : « +valeur » des premiers Nebbies, total, feux d'artifice dès 15", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 1)
			snapshot(c, { { slot = 1, userId = 1, ver = 0, codes = {} } })
			local list, ids = {}, {}
			for i = 1, 16 do
				list[i] = 1
				ids[i] = 0
			end
			fire(c, "LineEvent", { { op = "add", slot = 1, ver = 1, codes = list, ids = ids } })
			fire(c, "LineEvent", {
				{
					op = "bank",
					slot = 1,
					ver = 2,
					count = 16,
					glow = 1600,
					bonus = 2.2,
					atBeacon = false,
					newEntries = 0,
				},
			})
			task.wait(1.4)
			c.h:settle(2)
			local texts = floatTexts(c)
			expect(contains(texts, "+1.6K")).toBe(true)
			expect(contains(texts, "+100")).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"Comète : traversée du ciel, impact, porteur (Highlight + 8 boules), encaissement, nettoyage",
			function()
				local c = setup()
				snapshot(c)
				local comet = {
					id = T0 + 8,
					phase = "warn",
					x = 20,
					z = 10,
					code = 1700,
					warnAt = T0,
					impactAt = T0 + 8,
					burstAt = T0 + 83,
				}
				local function state(phase, extra)
					local cm = table.clone(comet)
					cm.phase = phase
					for k, v in extra or {} do
						cm[k] = v
					end
					return { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 1, comet = cm }
				end
				fire(c, "EventState", state("warn"))
				frames(c, 60) -- t = T0 + 3 : la Comète est dans le ciel
				expect(vfxFolder(c):FindFirstChild("CometSky") ~= nil).toBe(true)
				frames(c, 101) -- t > impactAt
				fire(c, "EventState", state("ground"))
				frames(c, 2)
				expect(vfxFolder(c):FindFirstChild("CometSky")).toBeNil()
				expect(vfxFolder(c):FindFirstChild("CometFlash") ~= nil).toBe(true)
				expect(c.h.workspace.ClientWorld.VFX.VFXAnchor:FindFirstChild("CometPillar") ~= nil).toBe(
					true
				)
				fire(c, "EventState", state("carried", { carrierId = 1, carrierSince = T0 + 9 }))
				frames(c, 2)
				local hl = vfxFolder(c):FindFirstChild("CometCarrier")
				expect(hl ~= nil).toBe(true)
				expect(hl.Adornee).toBe(c.h.localPlayer.Character)
				expect(childrenNamed(vfxFolder(c), "FxBall")).toBe(8)
				expect(c.h.workspace.ClientWorld.VFX.VFXAnchor:FindFirstChild("CometPillar")).toBeNil()
				fire(c, "EventState", state("banked", { endedAt = T0 + 20 }))
				frames(c, 2)
				expect(vfxFolder(c):FindFirstChild("CometCarrier")).toBeNil()
				fire(c, "EventState", { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 1 })
				frames(c, 2)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("arrivée pendant une Comète au sol : pas d'impact rejoué", function()
			local c = setup()
			snapshot(c, nil, {
				events = {
					t = T0,
					wisps = {},
					snipsDisabled = false,
					activePlayers = 1,
					comet = {
						id = T0 - 30,
						phase = "ground",
						x = 0,
						z = 0,
						code = 1700,
						warnAt = T0 - 38,
						impactAt = T0 - 30,
						burstAt = T0 + 45,
					},
				},
			})
			frames(c, 2)
			expect(vfxFolder(c):FindFirstChild("CometFlash")).toBeNil()
		end)

		it("Gloomwisp éclaté : bouffée sombre et étincelles à sa position", function()
			local c = setup()
			local ev = {
				t = T0,
				wisps = { { id = 3, seed = 5, t0 = T0 - 20 } },
				snipsDisabled = false,
				activePlayers = 1,
			}
			snapshot(c, nil, { events = ev })
			frames(c, 2)
			local model = c.CR.wispModel(3)
			root(c).CFrame = CFrame.new(model.PrimaryPart.Position)
			fire(c, "EventState", {
				t = T0,
				wisps = { { id = 3, seed = 5, t0 = T0 - 20, poppedAt = T0 + 0.1, poppedBy = 1 } },
				snipsDisabled = false,
				activePlayers = 1,
			})
			expect(childrenNamed(vfxFolder(c), "WispPuff")).toBe(1) -- bouffée écrasée
			expect(childrenNamed(vfxFolder(c), "FxBall")).toBe(1) -- lueur qui s'envole
			expect(c.VFX.particlesAlive()).toBeGreaterThan(0)
		end)

		it("pings : bulle au-dessus du joueur pendant 2,5 s", function()
			local c = setup()
			snapshot(c)
			fire(c, "PingShow", { userId = 1, kind = 3 })
			local anchor = vfxFolder(c).VFXAnchor
			local shown
			for _, a in anchor:GetChildren() do
				local gui = a:FindFirstChild("Ping")
				if gui and gui.Enabled then
					shown = gui
				end
			end
			expect(shown ~= nil).toBe(true)
			expect(shown.Bubble.Text.Text).toBe("Comet!")
			task.wait(2.8)
			c.h:settle(3)
			expect(shown.Enabled).toBe(false)
			-- joueur inconnu : rien
			fire(c, "PingShow", { userId = 999, kind = 1 })
			expect(#c.h.errors).toBe(0)
		end)
	end)

	describe("VFXController › marques de joueurs et cycle de vie", function()
		it("anneau Zen, étoile d'équipier, étincelles d'immunité ; nettoyés au départ", function()
			local c = setup()
			snapshot(c)
			local other = c.h:addPlayer({ userId = 44, name = "Noah" })
			other:SetAttribute("Zen", true)
			frames(c, 1)
			local zen = 0
			for _, child in vfxFolder(c):GetChildren() do
				if child.Name == "FxRing" then
					zen += 1
				end
			end
			expect(zen).toBe(1)
			fire(c, "CrewState", { crews = { { id = 1, userIds = { 1, 44 } } } })
			expect(vfxFolder(c):FindFirstChild("CrewStar") ~= nil).toBe(true)
			other:SetAttribute("ImmuneUntil", T0 + 8)
			frames(c, 3)
			expect(other.Character.HumanoidRootPart:FindFirstChild("Immunity") ~= nil).toBe(true)
			frames(c, 200)
			expect(other.Character.HumanoidRootPart:FindFirstChild("Immunity")).toBeNil()
			c.h:removePlayer(other)
			c.h:settle(2)
			task.wait(0.4)
			c.h:settle(2)
			expect(vfxFolder(c):FindFirstChild("CrewStar")).toBeNil()
			expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0)
		end)

		it("fin du bouclier débutant : les bulles éclatent une à une, sans erreur", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 2)
			c.h.localPlayer:SetAttribute("Rookie", true)
			snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = { 1, 1, 1 } } })
			frames(c, 3)
			c.h.localPlayer:SetAttribute("Rookie", false)
			task.wait(0.3)
			c.h:settle(2)
			expect(c.VFX.particlesAlive()).toBeGreaterThan(0)
			expect(#c.h.errors).toBe(0)
			expect(#c.h:warnings()).toBe(0)
		end)
	end)

	-- Revue du paquet : chaque test reproduit un bogue corrigé
	describe("VFXController › revue (bogues corrigés)", function()
		it(
			"arrivée d'un joueur avec R = 1 : pas de fausse Supernova (Supernovas posé au chargement du profil)",
			function()
				local c = setup({ nests = { [3] = { OwnerUserId = 0, Supernovas = 0 } } })
				local calls = {}
				c.VFX.playSupernova = function(slot, level)
					table.insert(calls, { slot, level })
				end
				local model = c.CR.NestDisplay.model(3)
				-- NestService : OwnerUserId dès PlayerAdded, Supernovas au chargement du profil
				model:SetAttribute("OwnerUserId", 9)
				c.Clock.advance(2)
				model:SetAttribute("Supernovas", 1)
				expect(#calls).toBe(0)
				-- vraie Supernova, bien plus tard
				c.Clock.advance(1500)
				model:SetAttribute("Supernovas", 2)
				expect(#calls).toBe(1)
				expect(calls[1][2]).toBe(2)
				-- Nid libéré puis repris par un profil à R = 0 (aucun changement au chargement) :
				-- sa première Supernova compte
				model:SetAttribute("OwnerUserId", 0)
				model:SetAttribute("Supernovas", 0)
				model:SetAttribute("OwnerUserId", 12)
				c.Clock.advance(1500)
				model:SetAttribute("Supernovas", 1)
				expect(#calls).toBe(2)
			end
		)

		it(
			"Nid du joueur local au démarrage, profil pas encore chargé : pas de fausse Supernova",
			function()
				local c = setup({ nests = { [4] = { OwnerUserId = 1, Supernovas = 0 } } })
				local calls = 0
				c.VFX.playSupernova = function()
					calls += 1
				end
				c.h.localPlayer:SetAttribute("Slot", 4)
				local model = c.CR.NestDisplay.model(4)
				c.Clock.advance(1)
				c.h.localPlayer:SetAttribute("Supernovas", 1)
				model:SetAttribute("Supernovas", 1)
				expect(calls).toBe(0)
				c.Clock.advance(1800)
				c.h.localPlayer:SetAttribute("Supernovas", 2)
				model:SetAttribute("Supernovas", 2)
				expect(calls).toBe(1)
			end
		)

		it(
			"parade à la Balise d'un autre joueur : feux d'artifice à la Balise, pas au-dessus de son Nid",
			function()
				local c = setup()
				root(c).CFrame = CFrame.new(10, 3, 0)
				snapshot(c, { { slot = 4, userId = 40, ver = 0, codes = {} } })
				local list, ids = {}, {}
				for i = 1, 16 do
					list[i] = 1
					ids[i] = 0
				end
				fire(c, "LineEvent", { { op = "add", slot = 4, ver = 1, codes = list, ids = ids } })
				fire(
					c,
					"PathStream",
					c.PathCodec.encode(
						2,
						c.PathCodec.split(4, 1, { Vector3.new(12, 3, 2), Vector3.new(12, 3, 3) })
					)
				)
				local shots = {}
				c.VFX.fireworks = function(pos, n)
					table.insert(shots, { pos = pos, n = n })
				end
				fire(c, "LineEvent", {
					{
						op = "bank",
						slot = 4,
						ver = 2,
						count = 16,
						glow = 1600,
						bonus = 2.2,
						atBeacon = true,
						newEntries = 0,
					},
				})
				expect(#shots).toBe(1)
				local p = shots[1].pos
				expect(Vector3.new(p.X, 0, p.Z).Magnitude < 5).toBe(true)
				expect(p.Y >= c.h:require("ReplicatedStorage.Shared.Config.Zones").Beacon.StarY).toBe(true)
			end
		)

		it("Rookie nil → faux au chargement d'un joueur confirmé : aucune bulle ne saute", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 2)
			snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = { 1, 1, 1 } } })
			frames(c, 3)
			c.h.localPlayer:SetAttribute("Rookie", false)
			task.wait(0.3)
			c.h:settle(2)
			expect(c.VFX.particlesAlive()).toBe(0)
		end)

		it("joueur parti : ses attributs ne recréent pas d'anneau Zen (connexions coupées)", function()
			local c = setup()
			snapshot(c)
			local other = c.h:addPlayer({ userId = 44, name = "Noah" })
			c.h:removePlayer(other)
			c.h:settle(2)
			other:SetAttribute("Zen", true)
			c.h:settle(2)
			frames(c, 2)
			expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"étoile d'équipier : apparaît quand la tête du personnage arrive en retard (streaming)",
			function()
				local c = setup()
				snapshot(c)
				local other = c.h:addPlayer({ userId = 44, name = "Noah" })
				local head = other.Character.Head
				head.Parent = nil
				fire(c, "CrewState", { crews = { { id = 1, userIds = { 1, 44 } } } })
				frames(c, 3)
				expect(vfxFolder(c):FindFirstChild("CrewStar")).toBeNil()
				head.Parent = other.Character
				frames(c, 3)
				local star = vfxFolder(c):FindFirstChild("CrewStar")
				expect(star ~= nil).toBe(true)
				expect(star.Adornee).toBe(head)
			end
		)

		it(
			"bulle de texte reprise par le tourniquet : les tweens de l'affichage précédent sont annulés",
			function()
				local c = setup()
				local TS = MockInstance.classMethods.TweenService
				local originalCreate = TS.Create
				local created = {}
				TS.Create = function(self, inst, info, goals)
					local tween = originalCreate(self, inst, info, goals)
					table.insert(created, { inst = inst, tween = tween })
					return tween
				end
				local white = c.g.Color3.new(1, 1, 1)
				for i = 1, 20 do
					c.VFX.floatText(Vector3.new(i, 3, 0), "+" .. i, white, 1)
				end
				local first = c.h.workspace.ClientWorld.FloatText.FloatAnchor.Float1.Text
				local previous = {}
				for _, e in created do
					if e.inst == first then
						table.insert(previous, e.tween) -- montée (StudsOffset) du 1er affichage
					end
				end
				expect(#previous).toBe(1)
				expect(previous[1].PlaybackState).toBe(roblox.Enum.PlaybackState.Playing)
				-- Mouvement réduit : la bulle reprise ne relance pas de montée ; l'ancienne doit s'arrêter
				c.Prefs._onSettings({ reducedMotion = true })
				c.VFX.floatText(Vector3.new(0, 3, 0), "+21", white, 1)
				expect(previous[1].PlaybackState).toBe(roblox.Enum.PlaybackState.Cancelled)
				expect(first.StudsOffset).toBe(Vector3.zero)
				expect(first.Label.Text).toBe("+21")
				TS.Create = originalCreate
			end
		)

		it("deux parades rapprochées : l'arche reprend sa couleur au lieu de rester blanche", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 1)
			local red = c.g.Color3.fromRGB(255, 0, 0)
			local arch = c.g.Instance.new("Part")
			arch.Name = "Arch1"
			arch.Color = red
			arch:SetAttribute("slot", 1)
			arch.Parent = c.h.workspace
			c.h.game.CollectionService:AddTag(arch, "NestArch")
			snapshot(c, { { slot = 1, userId = 1, ver = 0, codes = {} } })
			local function parade(ver)
				fire(c, "LineEvent", { { op = "add", slot = 1, ver = ver, codes = { 1 }, ids = { 0 } } })
				fire(c, "LineEvent", {
					{
						op = "bank",
						slot = 1,
						ver = ver + 1,
						count = 1,
						glow = 10,
						bonus = 1,
						atBeacon = false,
						newEntries = 0,
					},
				})
			end
			parade(1)
			expect(arch.Color.G > 0.99).toBe(true) -- flash blanc
			parade(3)
			task.wait(0.6)
			c.h:settle(3)
			expect(arch.Color.R > 0.99 and arch.Color.G < 0.01 and arch.Color.B < 0.01).toBe(true)
		end)

		it(
			"anneau Zen d'un joueur sans personnage chargé : masqué, pas figé à l'origine du monde",
			function()
				local c = setup()
				snapshot(c)
				local other = c.h:addPlayer({ userId = 45, name = "Lea", spawn = false })
				other:SetAttribute("Zen", true)
				frames(c, 2)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0)
				c.h:respawn(other)
				other.Character.HumanoidRootPart.CFrame = CFrame.new(30, 3, 30)
				frames(c, 2)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(1)
				local ring = vfxFolder(c):FindFirstChild("FxRing")
				expect((ring.Position - Vector3.new(30, 0.1, 30)).Magnitude < 0.5).toBe(true)
				-- personnage retiré (streaming, mort) : l'anneau disparaît au lieu de rester figé
				other.Character:Destroy()
				other.Character = nil
				frames(c, 2)
				expect(childrenNamed(vfxFolder(c), "FxRing")).toBe(0)
			end
		)

		it("vibration : mobile (Touch) essayé avant la manette, moteur coupé ensuite", function()
			local c = setup()
			local calls = {}
			local Touch = roblox.Enum.UserInputType.Touch
			MockInstance.classMethods.HapticService = {
				IsVibrationSupported = function(_, input)
					return input == Touch
				end,
				IsMotorSupported = function()
					return true
				end,
				SetMotor = function(_, input, _motor, power)
					table.insert(calls, { input, power })
				end,
			}
			c.VFX.haptic(0.4, 0.05)
			expect(#calls).toBe(1)
			expect(calls[1][1]).toBe(Touch)
			expect(calls[1][2]).toBe(0.4)
			task.wait(0.1)
			c.h:settle(2)
			expect(#calls).toBe(2)
			expect(calls[2][2]).toBe(0)
			MockInstance.classMethods.HapticService = nil
		end)
	end)
end
