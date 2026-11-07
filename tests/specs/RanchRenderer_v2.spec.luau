--!nocheck
-- RanchRenderer_v2 (lot B4 ; décisions D1, D11 du plan B4 ; GDD v2.0 §4.6, §11.5) : rendu v2.0 du
-- ranch, interrupteurs ouverts DANS le test (le client ne lit jamais Config/Features : il suit ce que le
-- serveur montre). Étape 1 : étiquette de la dalle du Tapis Étoilé (au-delà du Tapis 12, dalle que le
-- serveur laisse allumée avec StarMat : nom de la ligne de l'écran Améliorations, niveau 13 … 20 et prix
-- calculés sur MON profil) ; interrupteur coupé (dalle cachée par le serveur) ou profil v1 : rien de plus
-- que la v1.3. Les étapes suivantes du lot complètent ce fichier.
-- Étape 3 (partie 1 ; D1, D6, D12-D14, D18, D18b, D19, D19b) : cadre v2.0 du ranch sur 16 ranchs
-- fabriqués (modèles Wobbleton/Ranches/<k> comme ceux du serveur) :
--   * interrupteurs coupés : aucune instance v2.0, aucune image v2.0, aucune pièce du serveur
--     repeinte, compteurs de RanchRenderer identiques à ceux de la v1.3 (mêmes clés, mêmes valeurs) ;
--   * chaque élément de l'étape dessiné depuis ses attributs (paliers du Tapis, coussins, lit,
--     socles, décorations dorées, fanions, Pot, tas, anneau de l'aimant, habillages), puis retiré :
--     l'aspect de la v1.3 revient exactement ;
--   * idempotence : un second rendu ne crée aucune instance, n'écrit aucune propriété, même hachage
--     des CFrame ; cascade seulement sur un vrai changement (jamais au chargement, au changement de
--     détail ou de propriétaire), socle → décoration ;
--   * « un robot qui traverse son ranch ne change aucun détail » ; ranch voisin après 10 studs ;
--   * voisins en détail complet, les autres réduits ; 16 ranchs au maximum de l'étape : chaque
--     système dans son budget.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local MockInstance = require("../harness/MockInstance")
local ApiAudit = require("../harness/ApiAudit")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 7,
			fame = 0,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function find(root, name)
		for _, d in root:GetDescendants() do
			if d.Name == name and not (d.ClassName == "BillboardGui" and d.Enabled == false) then
				return d
			end
		end
		return nil
	end

	local function textOf(gui)
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextLabel" and d.Text ~= "" then
				return d.Text
			end
		end
		return ""
	end

	local function part(parent, name, props)
		local p = MockInstance.new("Part")
		p.Name = name
		for k, v in props or {} do
			p[k] = v
		end
		p.Parent = parent
		return p
	end

	local function folder(parent, name, class)
		local f = MockInstance.new(class or "Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	-- Client complet de RanchRenderer ; le ranch 3 est le mien (joueur 1), sa dalle du Tapis (prise 1)
	-- est allumée par le serveur (Transparency 0, Maxed = false) ou non (opts.pad)
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		if opts.language then
			Prefs._onSettings({ lang = opts.language })
		end
		h:require(base .. "Controllers.StateController").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local pad
		do
			local w = folder(h.workspace, "Wobbleton")
			local r3 = folder(folder(w, "Ranches"), "3", "Model")
			pad = part(folder(r3, "Pads"), "1", opts.pad or { Transparency = 0 })
			pad:SetAttribute("Maxed", opts.maxed == true)
		end
		local RR = h:require(base .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local c = { h = h, RR = RR, pad = pad, Clock = Clock }
		function c.profile(data)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", data)
			h:settle(1)
		end
		function c.snapshot(ranches)
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = 1, ranches = ranches, squishies = {} }
			)
			h:settle(1)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				RR._step(dt)
			end
			h:settle(1)
		end
		function c.label()
			local gui = find(h.workspace, "PadLabel1")
			return if gui then textOf(gui) else nil
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return c
	end

	-- Profil v2 au Tapis 12 (MON profil, DataSnapshot)
	local function profileV2(R, star, A)
		return {
			version = 2,
			R = R,
			bestR = R,
			ascend = A or 0,
			coins = 0,
			tiles = { snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15, star = star },
		}
	end

	describe("RanchRenderer_v2 › dalle du Tapis Étoilé (étape 1, D11)", function()
		it(
			"dalle allumée au-delà du Tapis 12 : « Star Mat Lv. 13 · prix » de MON profil, puis Lv. 14",
			function()
				local c = client()
				local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
				local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
				c.profile(profileV2(7, 0, 2))
				c.snapshot({ ["3"] = ranch(3, 1) })
				c.run(0.6)
				local price = UpgradeMath.price("star", 0, 7, 2, 7)
				expect(price < math.huge).toBe(true)
				expect(c.label()).toBe("Star Mat Lv. 13 · " .. Util.number(price))
				-- un niveau acheté : le profil change, l'étiquette suit
				c.profile(profileV2(7, 1, 2))
				c.run(0.6)
				expect(c.label()).toBe(
					"Star Mat Lv. 14 · " .. Util.number(UpgradeMath.price("star", 1, 7, 2, 7))
				)
				c.clean()
			end
		)

		it("en français : « Tapis Étoilé Niv. 13 · prix »", function()
			local c = client({ language = "fr" })
			local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
			local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
			c.profile(profileV2(10, 3))
			c.snapshot({ ["3"] = ranch(3, 1, { R = 10 }) })
			c.run(0.6)
			expect(c.label()).toBe(
				"Tapis Étoilé Niv. 16 · " .. Util.number(UpgradeMath.price("star", 3, 10, 0, 10))
			)
			c.clean()
		end)

		it(
			"interrupteur coupé (dalle cachée, Maxed = true), profil v1, plafond de la boucle : aucune étiquette",
			function()
				-- StarMat coupé : le serveur cache la dalle au Tapis 12 (v1.3)
				local off = client({ pad = { Transparency = 1 }, maxed = true })
				off.profile(profileV2(7, 0))
				off.snapshot({ ["3"] = ranch(3, 1) })
				off.run(0.6)
				expect(off.label()).toBe(nil)
				off.clean()
				-- profil v1 (le serveur ne l'allumerait pas) : le client ne montre rien non plus
				local v1 = client()
				local d = profileV2(7, 0)
				d.version = 1
				v1.profile(d)
				v1.snapshot({ ["3"] = ranch(3, 1) })
				v1.run(0.6)
				expect(v1.label()).toBe(nil)
				v1.clean()
				-- plafond de la boucle atteint (r = 7 : 2 niveaux) : aucun niveau ouvert, aucune étiquette
				local capped = client()
				capped.profile(profileV2(7, 2))
				capped.snapshot({ ["3"] = ranch(3, 1) })
				capped.run(0.6)
				expect(capped.label()).toBe(nil)
				capped.clean()
			end
		)

		it("en dessous du Tapis 12 : l'étiquette de la v1.3, inchangée", function()
			local c = client()
			local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
			local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
			c.profile(profileV2(7, 0))
			c.snapshot({
				["3"] = ranch(
					3,
					1,
					{ tiles = { snack = 5, decor = 0, pens = 0, cozyBed = false, seen = 15 } }
				),
			})
			c.run(0.6)
			expect(c.label()).toBe("Snack Mat Lv. 6 · " .. Util.number(Formulas.tileCost("snack", 5, 7)))
			c.clean()
		end)
	end)

	-- =========================================================================================
	-- Étape 3 : cadre v2.0 du ranch (16 ranchs fabriqués)
	-- =========================================================================================

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local WITNESS = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))

	local function deepCopy(t)
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in t do
			out[k] = deepCopy(v)
		end
		return out
	end

	-- Un ranch du serveur (mêmes noms que World/Ranch) : tapis et 8 biscuits, 18 décorations, Pot,
	-- clôture, portail, sol des enclos, coussin du Meilleur Ami
	local function buildRanch(h, ranches, slot)
		local WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local P = h:require("ReplicatedStorage.Shared.Render.Palette")
		local F = WL.ranchCFrame(slot)
		local r = folder(ranches, tostring(slot), "Model")
		r:SetAttribute("Slot", slot)
		local snack = folder(r, "SnackMat", "Model")
		local look = P.snackLook(0)
		part(snack, "Mat", {
			Color = look.mat,
			Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new(54, 0.1, 32),
			CFrame = F * CFrame.new(0, 0.02, 28),
		})
		for i = 1, 8 do
			part(snack, "Dot" .. i, { Color = look.dots, Material = Enum.Material.SmoothPlastic })
		end
		local decor = folder(r, "Decor")
		for k = 1, 18 do
			local m = folder(decor, tostring(k), "Model")
			local cf = WL.decorSlot(slot, k)
			part(m, "Base", {
				Color = Color3.fromRGB(200, 120, 180),
				Material = Enum.Material.SmoothPlastic,
				Size = Vector3.new(2, 1, 2),
				CFrame = cf * CFrame.new(0, 0.5, 0),
			})
			part(m, "Glow", {
				Color = Color3.fromRGB(120, 230, 255),
				Material = Enum.Material.Neon,
				Size = Vector3.new(1, 1, 1),
				CFrame = cf * CFrame.new(0, 1.5, 0),
			})
		end
		local pot = folder(r, "Pot", "Model")
		part(pot, "Body", { Color = P.World.pot, Material = Enum.Material.Foil })
		part(pot, "Rim", { Color = P.World.pot, Material = Enum.Material.SmoothPlastic })
		part(pot, "Lid", { Color = P.World.potLid, Material = Enum.Material.SmoothPlastic })
		local fence = folder(r, "Fence")
		part(fence, "LeftPost0", { Color = Color3.fromRGB(255, 130, 120) })
		part(fence, "LeftRail1", { Color = P.World.sign })
		local gate = folder(r, "Gate", "Model")
		part(gate, "Membrane", { CanCollide = false, Transparency = 0.45 })
		part(gate, "PostL", { Color = Color3.fromRGB(255, 130, 120) })
		part(gate, "PostR", { Color = Color3.fromRGB(255, 130, 120) })
		part(gate, "Arch", { Color = Color3.fromRGB(255, 130, 120) })
		part(gate, "LanternL", { Material = Enum.Material.Neon })
		part(r, "PenFloor", { Color = P.World.penFloor, Material = Enum.Material.SmoothPlastic })
		part(r, "Cushion", {})
		-- étape 4 : Cuve, Bassin, étagère (pièces que la v2.0 peint ou habille)
		local vat = folder(r, "Vat", "Model")
		part(vat, "Base", { Color = P.World.vatBase, Material = Enum.Material.SmoothPlastic })
		part(vat, "Glass", { Color = P.World.glass, Material = Enum.Material.Glass, Transparency = 0.5 })
		part(vat, "Jelly", { Color = P.World.vatJelly, Material = Enum.Material.Neon })
		part(vat, "Lid", { Color = P.World.vatBase, Material = Enum.Material.SmoothPlastic })
		part(vat, "Pipe", { Color = P.World.vatBase, Material = Enum.Material.SmoothPlastic })
		local shelf = folder(r, "Shelf", "Model")
		for _, name in { "Back", "Plank1", "Plank2", "Plank3", "SideL", "SideR" } do
			part(shelf, name, { Color = P.World.shelf, Material = Enum.Material.SmoothPlastic })
		end
		return r
	end

	-- Ranch public complet (le mien : ranch 3, joueur 1 ; les autres : joueurs 100 + k)
	local function ranchV2(slot, over)
		local r = ranch(slot, if slot == 3 then 1 else 100 + slot, {
			R = 4,
			tiles = { snack = 5, decor = 4, pens = 3, cozyBed = true, seen = 15 },
		})
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	-- Client complet de RanchRenderer sur 16 ranchs fabriqués ; opts.low (Graphismes légers),
	-- opts.reduced (Mouvement réduit), opts.attrs { [slot] = { attributs } } posés avant le démarrage
	local function clientV2(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(opts.t or T0)
		local Prefs = h:require(CLIENT .. "Util.Prefs")
		Prefs.Init()
		local flags = { low = opts.low == true, reduced = opts.reduced == true }
		Prefs.lowGraphics = function()
			return flags.low
		end
		Prefs.reducedMotion = function()
			return flags.reduced
		end
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local models = {}
		do
			local w = folder(h.workspace, "Wobbleton")
			local ranches = folder(w, "Ranches")
			for slot = 1, 16 do
				models[slot] = buildRanch(h, ranches, slot)
				for k, v in (opts.attrs or {})[slot] or {} do
					models[slot]:SetAttribute(k, v)
				end
			end
		end
		local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
		local V2 = h:require(CLIENT .. "Render.RanchV2")
		local BC = h:require(CLIENT .. "Render.BuildCascade")
		local VB = h:require(CLIENT .. "Render.VisualBudget")
		local steps = 0
		local realStep = V2.step
		V2.step = function(...)
			steps += 1
			return realStep(...)
		end
		RR.Init()
		RR.Start()
		-- étape 5 : opts.lighting démarre LightingController (monde v2.0, étiquettes) avec un EventState
		-- fabriqué (c.setEvent) et l'écoute de l'instantané de l'écran Améliorations (kiosque)
		local LC, event = nil, opts.event
		if opts.lighting then
			WSC.event = function()
				return event
			end
			h:require(CLIENT .. "UI.UpgradeSnapshot").start()
			LC = h:require(CLIENT .. "Controllers.LightingController")
			LC.Init()
			LC.Start()
		end
		local c = {
			h = h,
			RR = RR,
			LC = LC,
			V2 = V2,
			BC = BC,
			VB = VB,
			models = models,
			flags = flags,
			Clock = Clock,
			seq = 1,
			open = false,
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Look = h:require("ReplicatedStorage.Shared.Logic.RanchLook"),
			Kit = h:require(CLIENT .. "Render.RanchKit"),
		}
		BC.configure({
			upgradesOpen = function()
				return c.open
			end,
		})
		function c.steps()
			return steps
		end
		function c.setEvent(p)
			event = p
			WSC.EventChanged:Fire(p)
			h:settle(1)
		end
		function c.snapshot(ranches, squishies)
			c.seq = 1
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = 1, ranches = ranches, squishies = squishies or {} }
			)
			h:settle(1)
		end
		function c.patch(slot, fields)
			c.seq += 1
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchPatch",
				{ seq = c.seq, ranches = { [tostring(slot)] = fields }, ops = {} }
			)
			h:settle(1)
		end
		function c.attrs(slot, attrs)
			for k, v in attrs do
				models[slot]:SetAttribute(k, v)
			end
			h:settle(1)
		end
		-- retire des attributs (une table Lua ne garde pas les clés à nil)
		function c.unset(slot, names)
			for _, k in names do
				models[slot]:SetAttribute(k, nil)
			end
			h:settle(1)
		end
		function c.profile(data)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", data)
			h:settle(1)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				RR._step(dt)
			end
			h:settle(1)
		end
		-- personnage à la position locale `p` du ranch `slot` (caméra derrière lui)
		function c.at(slot, p)
			local root = h.localPlayer.Character.HumanoidRootPart
			local world = c.WL.toWorld(slot, p)
			root.CFrame = CFrame.new(world + Vector3.new(0, 3, 0))
			h.workspace.CurrentCamera.CFrame = CFrame.lookAt(
				world
					+ Vector3.new(0, 14, 0)
					- c.WL.toWorld(slot, Vector3.new(0, 0, 20))
					+ c.WL.toWorld(slot, Vector3.zero),
				world
			)
		end
		-- dossier v2.0 d'un ranch et ses pièces
		function c.folder(slot)
			local world = h.workspace:FindFirstChild("ClientWorld")
			local root = world and world:FindFirstChild("RanchesV2")
			return root and root:FindFirstChild(tostring(slot))
		end
		function c.parts(slot)
			local f = c.folder(slot)
			local out = {}
			if f then
				for _, d in f:GetChildren() do
					out[d.Name] = d
				end
			end
			return out
		end
		function c.count(slot, prefix)
			local n = 0
			for name in c.parts(slot) do
				if string.sub(name, 1, #prefix) == prefix then
					n += 1
				end
			end
			return n
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return c
	end

	local function all16(over)
		local out = {}
		for slot = 1, 16 do
			out[tostring(slot)] = ranchV2(slot, over and over(slot))
		end
		return out
	end

	-- Aspect des pièces du serveur d'un ranch (couleur et matériau), pour comparer avec la v1.3
	local function serverLook(model)
		local out = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == "Part" then
				out[d:GetFullName()] = tostring(d.Color)
					.. "|"
					.. tostring(d.Material)
					.. "|"
					.. tostring(d.CFrame)
			end
		end
		return out
	end

	local function sameLook(a, b)
		for k, v in a do
			if b[k] ~= v then
				return k .. " : " .. tostring(b[k]) .. " ≠ " .. v
			end
		end
		return "ok"
	end

	local function instanceCount(h)
		return #h.workspace:GetDescendants()
	end

	-- Intentions ClientMetric envoyées
	local function metrics(h)
		local out = {}
		for _, e in h.log.serverEvents do
			if e.remote == "ClientMetric" then
				table.insert(out, e.args)
			end
		end
		return out
	end

	local function emitters(h)
		local n = 0
		for _, d in h.workspace:GetDescendants() do
			if d.ClassName == "ParticleEmitter" then
				n += 1
			end
		end
		return n
	end

	describe("RanchRenderer_v2 › étape 3 : interrupteurs coupés", function()
		it(
			"aucune instance v2.0, aucune image v2.0, pièces du serveur intactes, compteurs de la v1.3",
			function()
				local c = clientV2()
				local before = {}
				for slot = 1, 16 do
					before[slot] = serverLook(c.models[slot])
				end
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				c.run(2)
				-- aucun ranch ne porte TapisTier : rien de la v2.0
				expect(c.V2.on).toBe(false)
				expect(c.steps()).toBe(0)
				expect(c.folder(3)).toBe(nil)
				expect(
					c.h.workspace:FindFirstChild("ClientWorld") == nil
						or c.h.workspace.ClientWorld:FindFirstChild("RanchesV2") == nil
				).toBe(true)
				expect(emitters(c.h)).toBe(0)
				expect(next(c.VB.stats())).toBe(nil)
				expect(c.BC.stats().pushed).toBe(0)
				expect(#metrics(c.h)).toBe(0)
				for slot = 1, 16 do
					expect(sameLook(before[slot], serverLook(c.models[slot]))).toBe("ok")
				end
				-- compteurs de RanchRenderer : exactement les clés de la v1.3
				local keys = {}
				for k in c.RR.stats() do
					table.insert(keys, k)
				end
				table.sort(keys)
				expect(table.concat(keys, ",")).toBe(
					"animated,fullRate,highlights,labels,lights,models,parts,silhouettes"
				)
				-- un attribut d'un autre lot (HaloOn sans habillage v2.0, OwnerUserId) ne réveille rien
				c.attrs(5, { HaloOn = true, OwnerUserId = 105 })
				c.run(1)
				expect(c.V2.on).toBe(false)
				expect(c.steps()).toBe(0)
				c.clean()
			end
		)
	end)

	-- Ranch 3 (le mien) avec tous les éléments de l'étape : Biscuit sablé (Tapis 5), Record R 17
	-- (coussins étoilés, 6 fanions, Pot cristal), décorations 1 … 4 construites (1 dorée), lit,
	-- coussins « Nuage rose », habillage Royal
	local FULL3 = {
		TapisTier = 2,
		BestR = 17,
		DecorGold = 1,
		GoldPennants = true,
		Cushions = "pinkCushions",
		HaloOn = true,
	}

	describe("RanchRenderer_v2 › étape 3 : éléments dessinés depuis leurs attributs", function()
		it(
			"Tapis, coussins, lit, socles, dorures, fanions, Pot, habillage ; retirés : la v1.3 exacte",
			function()
				local c = clientV2()
				local before = serverLook(c.models[3])
				c.snapshot(all16(function(slot)
					return if slot == 3 then { theme = "royal" } else nil
				end))
				c.at(3, Vector3.new(0, 0, 30))
				c.run(0.5)
				c.attrs(3, FULL3)
				c.run(1)
				local Look, Kit = c.Look, c.Kit
				local m = c.models[3]
				-- Tapis : Biscuit sablé, 8 % par niveau au-dessus du Tapis 4 (Tapis 5 : +8 %)
				local look = Look.tapisLook(2)
				local matColor = Kit.lighten(look.mat, Look.tapisShade(5))
				expect(m.SnackMat.Mat.Color).toBe(matColor)
				expect(m.SnackMat.Dot3.Color).toBe(matColor)
				expect(c.count(3, "hole")).toBe(8)
				expect(c.count(3, "scallop")).toBe(12)
				-- coussins : 3 places achetées, « Nuage rose » teinté d'or (étoilés au Record R 11), Foil
				expect(c.count(3, "cushion")).toBe(3)
				local cushion = c.parts(3).cushion1
				expect(cushion.Color).toBe(
					Kit.mix(Look.cushionStyle("pinkCushions"), Look.STAR_CUSHION.gold, 0.45)
				)
				expect(cushion.Material).toBe(Enum.Material.Foil)
				-- lit douillet : 10 pièces, hors des enclos (Z < 12) et à 6 studs au moins des dalles
				expect(c.count(3, "bed")).toBe(10)
				for name, p in c.parts(3) do
					if string.sub(name, 1, 3) == "bed" then
						local l = c.WL.toLocal(3, p.Position)
						expect(l.Z < 12).toBe(true)
						for socket = 1, 5 do
							local pad = c.WL.toLocal(3, c.WL.padSocket(3, socket))
							expect((Vector3.new(l.X, 0, l.Z) - Vector3.new(pad.X, 0, pad.Z)).Magnitude >= 8).toBe(
								true
							)
						end
					end
				end
				-- socles : décorations 5 … 18 pas construites (Record R ≥ 1) : 14 socles de 2 pièces
				expect(c.count(3, "plinthIcon")).toBe(14)
				expect(c.count(3, "plinth")).toBe(28)
				-- décoration 1 dorée : Foil doré, le Neon reste en Neon
				expect(m.Decor["1"].Base.Color).toBe(Look.GOLD)
				expect(m.Decor["1"].Base.Material).toBe(Enum.Material.Foil)
				expect(m.Decor["1"].Glow.Material).toBe(Enum.Material.Neon)
				expect(m.Decor["2"].Base.Material).toBe(Enum.Material.SmoothPlastic)
				-- fanions : 6 au Record R 14, sur les décorations gardées construites (1 … 4), dorés
				expect(c.count(3, "flag")).toBe(4)
				expect(c.parts(3).flag1.Material).toBe(Enum.Material.Foil)
				-- Pot cristal (Record R 16) : Ice, sans transparence
				expect(m.Pot.Body.Material).toBe(Enum.Material.Ice)
				expect(m.Pot.Body.Transparency).toBe(0)
				expect(m.Pot.Lid.Material).toBe(Enum.Material.SmoothPlastic)
				-- habillage Royal (HaloOn) : clôture Foil dorée, sol, poteaux et arche du portail
				local royal = Look.skin("royal")
				expect(m.Fence.LeftPost0.Color).toBe(royal.fence)
				expect(m.Fence.LeftPost0.Material).toBe(Enum.Material.Foil)
				expect(m.PenFloor.Color).toBe(royal.floor)
				expect(m.Gate.PostL.Color).toBe(royal.gate)
				expect(m.Gate.Membrane.Transparency).toBe(0.45)
				-- règles des pièces v2.0 : ancrées, non solides, sans ombre, opaques, matériaux permis
				local allowed = { SmoothPlastic = true, Neon = true, Foil = true, Ice = true }
				for _, p in c.parts(3) do
					expect(p.Anchored).toBe(true)
					expect(p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow).toBe(false)
					expect(p.Transparency).toBe(0)
					expect(allowed[p.Material.Name]).toBe(true)
				end
				-- tout retiré (interrupteurs coupés en direct) : la v1.3 exacte, aucune instance v2.0
				c.unset(3, { "TapisTier", "BestR", "DecorGold", "GoldPennants", "Cushions", "HaloOn" })
				c.run(1)
				expect(c.folder(3)).toBe(nil)
				expect(
					c.h.workspace:FindFirstChild("ClientWorld") == nil
						or c.h.workspace.ClientWorld:FindFirstChild("RanchesV2") == nil
				).toBe(true)
				-- l'habillage v1.3 « royal » n'existe pas : thème par défaut, clôture d'origine
				expect(sameLook(before, serverLook(m))).toBe("ok")
				expect(c.V2.on).toBe(false)
				c.clean()
			end
		)

		it(
			"chaque attribut retiré seul rend son aspect de la v1.3 ; identifiants inconnus : repli",
			function()
				local c = clientV2()
				local m = c.models[3]
				local before = serverLook(m)
				c.snapshot(all16(function(slot)
					return if slot == 3 then { theme = "royal" } else nil
				end))
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, FULL3)
				c.run(1)
				-- DecorGold retiré : la décoration reprend sa couleur et son matériau
				c.unset(3, { "DecorGold" })
				c.run(0.6)
				expect(before[m.Decor["1"].Base:GetFullName()]).toBe(
					tostring(m.Decor["1"].Base.Color)
						.. "|"
						.. tostring(m.Decor["1"].Base.Material)
						.. "|"
						.. tostring(m.Decor["1"].Base.CFrame)
				)
				-- GoldPennants retiré : fanions à la couleur du ranch
				c.unset(3, { "GoldPennants" })
				c.run(0.6)
				expect(c.parts(3).flag1.Material).toBe(Enum.Material.SmoothPlastic)
				-- Cushions inconnu : couleur du ranch (teintée d'or, Record R 17)
				c.attrs(3, { Cushions = "nimporte" })
				c.run(0.6)
				expect(c.parts(3).cushion1.Color).toBe(
					c.Kit.mix(
						c.h:require("ReplicatedStorage.Shared.Config.Cosmetics").RanchColors[3],
						c.Look.STAR_CUSHION.gold,
						0.45
					)
				)
				-- HaloOn retiré : habillage v2.0 ôté (clôture, sol, portail d'origine)
				c.unset(3, { "HaloOn" })
				c.run(0.6)
				expect(before[m.PenFloor:GetFullName()]).toBe(
					tostring(m.PenFloor.Color)
						.. "|"
						.. tostring(m.PenFloor.Material)
						.. "|"
						.. tostring(m.PenFloor.CFrame)
				)
				expect(before[m.Fence.LeftPost0:GetFullName()]).toBe(
					tostring(m.Fence.LeftPost0.Color)
						.. "|"
						.. tostring(m.Fence.LeftPost0.Material)
						.. "|"
						.. tostring(m.Fence.LeftPost0.CFrame)
				)
				-- BestR retiré (RecordR coupé) : le r public (4) : ni étoiles, ni fanions, Pot cuivre → argent (R2)
				c.unset(3, { "BestR" })
				c.run(0.6)
				expect(c.count(3, "flag")).toBe(0)
				expect(c.parts(3).cushion1.Material).toBe(Enum.Material.SmoothPlastic)
				expect(m.Pot.Body.Color).toBe(c.Look.potLook("silver").color)
				-- TapisTier illisible : palier 0 (aucun palier), sans trace
				c.attrs(3, { TapisTier = "beaucoup" })
				c.run(0.6)
				expect(c.count(3, "hole")).toBe(0)
				c.clean()
			end
		)

		it("selles, traînées et drapeaux v2.0 en couleur ; inconnus : le repli d'aujourd'hui", function()
			local c = clientV2()
			c.snapshot(all16(function(slot)
				return if slot == 3
					then { flag = "splorchRoyal" }
					elseif slot == 4 then { flag = "nope" }
					else nil
			end))
			c.run(0.6)
			local function cloth(slot)
				for _, d in c.h.workspace.ClientWorld:GetDescendants() do
					if d.Name == "Flag" .. slot then
						return d.Cloth
					end
				end
				return nil
			end
			expect(cloth(3).Color).toBe(Color3.fromRGB(200, 60, 125))
			expect(cloth(4).Color).toBe(Color3.fromRGB(255, 255, 255))
			c.clean()
		end)

		it(
			"selle et traînée v2.0 sur la monture ; inconnues : couleur du ranch, rose par défaut",
			function()
				local c = clientV2()
				local SB = c.h:require("ReplicatedStorage.Shared.Render.SquishyBuilder")
				local saddles = {}
				local real = SB.setSaddleColor
				SB.setSaddleColor = function(handle, color)
					table.insert(saddles, color)
					return real(handle, color)
				end
				local mount = { s = 1, m = 0, st = 0, z = 50, zg = 0, at = "pen", bf = 0, o = "", ready = 0 }
				c.snapshot(
					all16(function(slot)
						return if slot == 3
							then { ride = "a", saddle = 1, saddleColor = "goldenJelly", trail = "jellyArc" }
							else nil
					end),
					{ ["3"] = { a = mount } }
				)
				c.at(3, Vector3.new(0, 0, 30))
				c.run(0.6)
				local function trail()
					for _, d in c.h.workspace:GetDescendants() do
						if d.Name == "MountTrail" then
							return d
						end
					end
					return nil
				end
				expect(saddles[#saddles]).toBe(Color3.fromRGB(255, 205, 80))
				expect(trail().Color).toBe(roblox.ColorSequence.new(Color3.fromRGB(140, 220, 255)))
				c.patch(3, { saddleColor = "nope", trail = "nope2" })
				c.run(0.6)
				local Cosmetics = c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				expect(saddles[#saddles]).toBe(Cosmetics.RanchColors[3])
				expect(trail().Color).toBe(roblox.ColorSequence.new(Color3.fromRGB(255, 220, 240)))
				SB.setSaddleColor = real
				c.clean()
			end
		)

		it("tas du Pot et anneau de l'aimant : MON ranch seulement, anneau près du Pot", function()
			local c = clientV2()
			local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
			local Features = c.h:require("ReplicatedStorage.Shared.Config.Features")
			local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
			local ON = {}
			for k, v in Features.Defaults do
				ON[k] = if type(v) == "boolean" then true else v
			end
			local sq = {
				s = 1,
				m = 0,
				st = 0,
				z = 50,
				zg = 0,
				bf = 0,
				lk = false,
				o = "",
				at = "pen",
				b = 0,
				gd = 0,
			}
			local growth = { G = 0, g = 0, t = T0 }
			local K, S1 = Formulas.ranchIncome({ a = sq }, 0, {
				decor = 4,
				friends = 0,
				fame = 0,
				trophyBonus = 0,
				goldenPages = 0,
				doubleCoins = false,
				boost = false,
			})
			local income = S1 + K * 0
			expect(income > 0).toBe(true)
			c.profile({ version = 2, pot = income * 5000, squishies = { a = sq }, growth = growth, fame = 0 })
			c.snapshot(all16())
			for slot = 1, 16 do
				c.models[slot]:SetAttribute("TapisTier", 1)
			end
			c.at(3, Vector3.new(0, 0, 30))
			c.run(1)
			-- 5 000 s de revenu dans le Pot : il déborde (8 pièces, 3 sautillent) ; personne d'autre
			expect(c.count(3, "mound") + c.count(3, "coin") + c.count(3, "hop")).toBe(8)
			expect(c.count(4, "mound")).toBe(0)
			expect(c.count(3, "ring")).toBe(0) -- pas d'instantané : pas d'anneau
			-- ligne « Aimant » ouverte au niveau 2 : 12 points à 11 studs, seulement près du Pot
			local snap = UpgradeMath.snapshot(deepCopy(WITNESS), ON, 1)
			snap.levels.magnet = 2
			snap.caps.magnet = 3
			local US = c.h:require(CLIENT .. "UI.UpgradeSnapshot")
			expect(US.apply(snap)).toBe(true)
			local pot = c.WL.toLocal(3, c.WL.anchor(3, "pot"))
			c.at(3, pot + Vector3.new(15, 0, 6))
			c.run(1)
			expect(c.count(3, "ring")).toBe(12)
			local dot = c.parts(3).ring1
			local d = c.WL.toLocal(3, dot.Position) - pot
			expect(math.abs(Vector3.new(d.X, 0, d.Z).Magnitude - 11) < 1e-3).toBe(true)
			c.at(3, Vector3.new(20, 0, 60)) -- loin du Pot (> 11 + 8)
			c.run(1)
			expect(c.count(3, "ring")).toBe(0)
			-- Pot vide : plus de tas
			c.profile({ version = 2, pot = 0, squishies = { a = sq }, growth = growth, fame = 0 })
			c.run(1)
			expect(c.count(3, "mound")).toBe(0)
			c.clean()
		end)

		it(
			"paliers du Tapis 1 … 6 : pièces du GDD §11.5, étincelles du Tapis doré dans le quota",
			function()
				local c = clientV2()
				c.snapshot(all16(function(slot)
					return if slot == 3
						then { tiles = { snack = 12, decor = 18, pens = 0, cozyBed = false, seen = 15 } }
						else nil
				end))
				c.at(3, Vector3.new(0, 0, 30))
				local expected = { "picnic", "hole", "band", "", "star", "galaxy" }
				local counts = { 6, 8, 7, 0, 12, 12 }
				for tier = 1, 6 do
					c.attrs(3, { TapisTier = tier })
					c.run(0.5)
					if expected[tier] ~= "" then
						expect(c.count(3, expected[tier])).toBe(counts[tier])
					end
					-- étape 4 (B4-38) : paliers et éléments du Record R (r public 4) se dessinent aussi ;
					-- le système « tapis » compte exactement les pièces du palier (ni coussin ni lit ici)
					local st = c.V2.stats()
					expect(st.tapis).toBe(c.Kit.tapisCount(tier))
					expect(
						c.count(3, "picnic")
							+ c.count(3, "hole")
							+ c.count(3, "scallop")
							+ c.count(3, "band")
							+ c.count(3, "star")
							+ c.count(3, "galaxy")
							+ c.count(3, "shoot")
					).toBe(c.Kit.tapisCount(tier))
					expect(emitters(c.h)).toBe(if tier == 4 then 1 else 0)
					local mat = c.models[3].SnackMat.Mat
					expect(mat.Material).toBe(
						if tier == 4 then Enum.Material.Foil else Enum.Material.SmoothPlastic
					)
				end
				expect(c.count(3, "shoot")).toBe(2)
				-- Graphismes légers : pas d'étincelles
				c.attrs(3, { TapisTier = 4 })
				c.flags.low = true
				c.h:require(CLIENT .. "Controllers.QualityController").Changed:Fire(true)
				c.run(0.6)
				expect(emitters(c.h)).toBe(0)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 3 : idempotence et cascades", function()
		it(
			"second rendu : aucune instance créée, aucune propriété écrite, même hachage des CFrame",
			function()
				local c = clientV2()
				c.snapshot(all16(function(slot)
					return if slot == 3 then { theme = "royal" } else nil
				end))
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, FULL3)
				c.run(1.5)
				-- étape 4 (B4-38) : les pièces animées à 15 Hz (lanterne du phare, agitateur, goutte du
				-- geyser) n'écrivent que leur pose ou leur couleur d'animation ; tout le reste : rien
				local function hash()
					local list = {}
					for name, p in c.parts(3) do
						if not c.V2.isAnimated(p) then
							table.insert(
								list,
								name .. "=" .. tostring(p.CFrame) .. tostring(p.Size) .. tostring(p.Color)
							)
						end
					end
					table.sort(list)
					return table.concat(list, ";")
				end
				local h0 = hash()
				local n0 = instanceCount(c.h)
				local writes = 0
				local watched = {}
				for _, d in c.h.workspace:GetDescendants() do
					if d.ClassName == "Part" then
						table.insert(
							watched,
							d.Changed:Connect(function(prop)
								local animation = c.V2.isAnimated(d) and (prop == "CFrame" or prop == "Color")
								if not animation then
									writes += 1
								end
							end)
						)
					end
				end
				local renders = c.V2.stats().renders
				-- même état revu : patch identique, rafraîchissement forcé, attribut réécrit à l'identique
				c.patch(3, { tiles = { snack = 5, decor = 4, pens = 3, cozyBed = true, seen = 15 } })
				c.V2.onRanchChanged(3, { "tiles" })
				c.V2.onQualityChanged()
				c.attrs(3, { TapisTier = 2 })
				c.run(1)
				expect(instanceCount(c.h)).toBe(n0)
				expect(writes).toBe(0)
				expect(hash()).toBe(h0)
				expect(c.V2.stats().renders).toBe(renders)
				expect(c.BC.stats().pushed).toBe(0) -- rien au chargement
				for _, conn in watched do
					conn:Disconnect()
				end
				c.clean()
			end
		)

		it(
			"cascade sur un vrai changement seulement ; socle → décoration : rétrécit, puis cascade",
			function()
				local c = clientV2()
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 2, BestR = 5 })
				c.run(1)
				expect(c.BC.stats().pushed).toBe(0) -- chargement : posé sans animation
				-- une place d'enclos achetée : le coussin 4 sort en cascade (une pièce)
				c.patch(3, { tiles = { snack = 5, decor = 4, pens = 4, cozyBed = true, seen = 15 } })
				c.run(0.1)
				expect(c.BC.stats().pushed).toBe(1)
				c.run(1.5)
				expect(c.parts(3).cushion4.CFrame).toBe(
					c.Kit.cushions(3, 4, Color3.new(), Enum.Material.SmoothPlastic)[4].cf
				)
				-- changement de détail (je vais au ranch 6, puis je reviens) : rien ne joue
				c.at(6, Vector3.new(0, 0, 36))
				c.run(1)
				c.at(3, Vector3.new(0, 0, 36))
				c.run(1)
				expect(c.BC.stats().pushed).toBe(1)
				-- socle 5 → décoration 5 : le socle rétrécit (0,2 s) puis disparaît, la décoration sort
				local deco = c.models[3].Decor["5"].Base
				local final = deco.CFrame
				c.patch(3, { tiles = { snack = 5, decor = 5, pens = 4, cozyBed = true, seen = 15 } })
				c.run(0.1)
				expect(c.parts(3).plinth5 ~= nil).toBe(true) -- encore là, en train de rétrécir
				expect(c.BC.stats().pushed).toBe(2)
				c.run(1.5)
				expect(c.parts(3).plinth5).toBe(nil)
				expect(c.parts(3).plinthIcon5).toBe(nil)
				expect(deco.CFrame).toBe(final)
				-- nouveau propriétaire du ranch : rien ne joue, l'état est posé tel quel
				c.snapshot(all16(function(slot)
					return if slot == 3
						then {
							userId = 1,
							tiles = { snack = 5, decor = 0, pens = 9, cozyBed = true, seen = 15 },
						}
						else nil
				end))
				c.patch(3, { userId = 0 })
				c.run(0.3)
				c.patch(
					3,
					{ userId = 1, tiles = { snack = 5, decor = 0, pens = 9, cozyBed = true, seen = 15 } }
				)
				c.run(1)
				expect(c.BC.stats().pushed).toBe(2)
				expect(c.count(3, "cushion")).toBe(9)
				c.clean()
			end
		)

		it("API Roblox valide (ApiAudit) : pièces, émetteur, peintures, cascade", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = clientV2()
				c.snapshot(all16(function(slot)
					return if slot == 3 then { theme = "neon" } else nil
				end))
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, FULL3)
				c.attrs(4, { TapisTier = 6 })
				c.attrs(2, { TapisTier = 4 })
				c.run(1)
				c.patch(3, { tiles = { snack = 5, decor = 5, pens = 5, cozyBed = true, seen = 15 } })
				c.run(1.5)
				c.clean()
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)

	describe("RanchRenderer_v2 › étape 3 : détail par ranch", function()
		-- 16 ranchs v2.0 : nombre de pièces v2.0 par ranch (0 = couleur seulement)
		-- étape 4 (B4-38) : les pièces du détail réduit des paliers (« far… » : tour, phare, couronne)
		-- sont comptées à part (reducedPerSlot) ; perSlot compte les pièces du détail complet
		local function perSlot(c)
			local out = {}
			for slot = 1, 16 do
				local n = 0
				for name in c.parts(slot) do
					if string.sub(name, 1, 3) ~= "far" then
						n += 1
					end
				end
				out[slot] = n
			end
			return out
		end
		local function reducedPerSlot(c)
			local out = {}
			for slot = 1, 16 do
				out[slot] = c.count(slot, "far")
			end
			return out
		end

		it("un robot qui traverse son ranch ne change aucun détail ; le voisin après 10 studs", function()
			local c = clientV2()
			c.snapshot(all16())
			for slot = 1, 16 do
				c.models[slot]:SetAttribute("TapisTier", 2)
				c.models[slot]:SetAttribute("BestR", 5)
			end
			c.at(3, Vector3.new(0, 0, 30))
			c.run(1)
			local ref = perSlot(c)
			local far = reducedPerSlot(c)
			expect(ref[2] > 0 and ref[3] > 0 and ref[4] > 0).toBe(true)
			for slot = 5, 16 do
				expect(ref[slot]).toBe(0)
				expect(far[slot]).toBe(3) -- Record R 5 (palier 3) : la tour réduite seulement
			end
			expect(ref[1]).toBe(0)
			expect(far[1]).toBe(3)
			expect(far[2] + far[3] + far[4]).toBe(0)
			local renders = c.V2.stats().renders
			-- dans tous les sens, le long des clôtures, par le portail, dans la rue
			local path = {}
			for _, z in { 2, 10, 20, 36, 50, 64, 71 } do
				for _, x in { -31, -20, 0, 20, 31 } do
					table.insert(path, Vector3.new(x, 0, z))
				end
			end
			for _, p in
				{
					Vector3.new(0, 0, 0.5),
					Vector3.new(0, 0, -6),
					Vector3.new(-20, 0, -12),
					Vector3.new(25, 0, -3),
				}
			do
				table.insert(path, p)
			end
			for _, p in path do
				c.at(3, p)
				c.run(0.2)
				expect(c.V2.current()).toBe(3)
				local now = perSlot(c)
				local nowFar = reducedPerSlot(c)
				for slot = 1, 16 do
					expect(now[slot]).toBe(ref[slot])
					expect(nowFar[slot]).toBe(far[slot])
				end
			end
			expect(c.V2.stats().renders).toBe(renders)
			-- chez le voisin (ranch 4) : à 5 studs du bord, rien ne change ; à 10 studs, il devient courant
			c.at(4, Vector3.new(-32 + 5, 0, 30))
			c.run(0.3)
			expect(c.V2.current()).toBe(3)
			c.at(4, Vector3.new(-32 + 10.5, 0, 30))
			c.run(0.3)
			expect(c.V2.current()).toBe(4)
			local after = perSlot(c)
			expect(after[2]).toBe(0)
			expect(after[3] > 0 and after[4] > 0 and after[5] > 0).toBe(true)
			expect(c.BC.stats().pushed).toBe(0)
			c.clean()
		end)

		it(
			"voisins en détail complet, les autres réduits ; Graphismes légers : mon ranch et le courant",
			function()
				local c = clientV2({ low = true })
				c.snapshot(all16())
				for slot = 1, 16 do
					c.models[slot]:SetAttribute("TapisTier", 2)
				end
				c.at(7, Vector3.new(0, 0, 36))
				c.run(1)
				expect(c.V2.current()).toBe(7)
				local n = perSlot(c)
				local far = reducedPerSlot(c)
				for slot = 1, 16 do
					expect(n[slot] > 0).toBe(slot == 3 or slot == 7)
					expect(c.V2.detail(slot)).toBe(if slot == 3 or slot == 7 then "full" else "reduced")
					-- r public 4 (palier 2) : la tour réduite (3 pièces) sur les ranchs réduits
					expect(far[slot]).toBe(if slot == 3 or slot == 7 then 0 else 3)
				end
				-- qualité normale : le courant et ses 2 voisins
				c.flags.low = false
				c.h:require(CLIENT .. "Controllers.QualityController").Changed:Fire(false)
				c.run(1)
				n = perSlot(c)
				for slot = 1, 16 do
					expect(n[slot] > 0).toBe(slot >= 6 and slot <= 8)
				end
				-- les ranchs réduits gardent la couleur de leur palier (aucune pièce)
				local look = c.Look.tapisLook(2)
				expect(c.models[12].SnackMat.Mat.Color).toBe(c.Kit.lighten(look.mat, c.Look.tapisShade(5)))
				c.clean()
			end
		)

		it(
			"16 ranchs au maximum de l'étape : chaque système dans son budget, aucun dépassement",
			function()
				for _, decor in { 0, 6 } do
					local c = clientV2()
					c.snapshot(all16(function()
						return { tiles = { snack = 6, decor = decor, pens = 14, cozyBed = true, seen = 15 } }
					end))
					for slot = 1, 16 do
						c.attrs(slot, FULL3)
					end
					c.at(3, Vector3.new(0, 0, 30))
					local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
					local Features = c.h:require("ReplicatedStorage.Shared.Config.Features")
					local ON = {}
					for k, v in Features.Defaults do
						ON[k] = if type(v) == "boolean" then true else v
					end
					local snap = UpgradeMath.snapshot(deepCopy(WITNESS), ON, 1)
					snap.levels.magnet = 3
					snap.caps.magnet = 3
					c.h:require(CLIENT .. "UI.UpgradeSnapshot").apply(snap)
					-- Pot plein (tas qui déborde) et personnage près du Pot (anneau de 14 studs)
					local sq = {
						s = 1,
						m = 0,
						st = 0,
						z = 50,
						zg = 0,
						bf = 0,
						lk = false,
						o = "",
						at = "pen",
						b = 0,
						gd = 0,
					}
					c.profile({
						version = 2,
						pot = 1e12,
						squishies = { a = sq },
						growth = { G = 0, g = 0, t = T0 },
						fame = 0,
					})
					local pot = c.WL.toLocal(3, c.WL.anchor(3, "pot"))
					c.at(3, pot + Vector3.new(15, 0, 6))
					c.run(2)
					local st = c.VB.stats()
					for _, sys in { "tapis", "record", "plinths", "pot" } do
						expect(st[sys].used <= st[sys].parts).toBe(true)
						expect(st[sys].refused).toBe(0)
					end
					local v2 = c.V2.stats()
					expect(v2.tapis <= c.VB.LIMITS.tapis.parts).toBe(true)
					expect(v2.plinths <= c.VB.LIMITS.plinths.parts).toBe(true)
					expect(v2.record <= c.VB.LIMITS.record.parts).toBe(true)
					expect(v2.pot <= c.VB.LIMITS.pot.parts).toBe(true)
					-- étape 4 (B4-38) : toutes les pièces v2.0 sont dans un système ; fanions ★ comptés avec
					-- les socles (une décoration gardée porte un fanion OU est un socle : 18 × 2 par ranch)
					local sum = 0
					for _, sys in
						{
							"tapis",
							"plinths",
							"record",
							"pot",
							"tiers",
							"house",
							"silhouette",
							"monuments",
							"decoPerso",
						}
					do
						sum += v2[sys]
						expect(v2[sys] <= c.VB.LIMITS[sys].parts).toBe(true)
					end
					expect(v2.parts).toBe(sum)
					expect(c.VB.exceeded()).toBe(0)
					expect(#metrics(c.h)).toBe(0) -- aucune métrique visualBudget
					expect(v2.pot).toBe(8 + 12)
					expect(v2.tapis).toBe((20 + 14 + 10) * 3)
					expect(v2.plinths).toBe(18 * 2 * 3)
					if decor == 6 then
						expect(c.count(3, "flag")).toBe(6)
					end
					-- budget réduit : les ranchs les plus lointains se dégradent d'abord, le mien en dernier
					c.VB.declare("tapis", { parts = 60 })
					c.V2.onQualityChanged()
					c.run(0.5)
					expect(c.count(3, "cushion") > 0).toBe(true)
					expect(c.count(2, "cushion") + c.count(4, "cushion")).toBe(0)
					c.clean()
				end
			end
		)
	end)
	-- =========================================================================================
	-- Étape 4 : paliers, éléments du Record R, accessoires, Monuments, Déco perso (partie 2)
	-- =========================================================================================

	-- Ranch public au meilleur squishy présent (silhouette), Cuve et Bassin construits
	local BEST = { s = 1, m = 0, z = 60, zg = 0 }
	local function ranch4(slot, over)
		local r = ranchV2(slot, { best = BEST, vat = true, pool = true })
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end
	local function all16b(over)
		local out = {}
		for slot = 1, 16 do
			out[tostring(slot)] = ranch4(slot, over and over(slot))
		end
		return out
	end
	-- 12 objets de Déco perso valides : 8 petits (emplacements 1 … 8) puis 4 grands (9 … 12)
	local DECO12 = "1,2,3,4,5,7,9,10,6,8,12,14"
	local FULL4 = {
		TapisTier = 6,
		BestR = 50,
		SplorchReady = true,
		Monuments = 10,
		DecoPerso = DECO12,
		GiantTier = 3,
	}
	local SYSTEMS4 =
		{ "tapis", "plinths", "record", "pot", "tiers", "house", "silhouette", "monuments", "decoPerso" }

	describe(
		"RanchRenderer_v2 › étape 4 : défaut de l'étape 3 (quota de particules du Tapis doré)",
		function()
			it(
				"Tapis doré retiré puis remis 4 fois : les étincelles reviennent, leur quota est rendu",
				function()
					local c = clientV2()
					c.snapshot(all16())
					c.at(3, Vector3.new(0, 0, 30))
					for _ = 1, 4 do
						c.attrs(3, { TapisTier = 4 })
						c.run(0.6)
						expect(emitters(c.h)).toBe(1)
						expect(c.VB.used("tapis", "particles")).toBe(2)
						c.unset(3, { "TapisTier" })
						c.run(0.6)
						expect(emitters(c.h)).toBe(0)
						expect(c.VB.used("tapis", "particles")).toBe(0)
					end
					c.clean()
				end
			)
		end
	)

	describe("RanchRenderer_v2 › étape 4 : éléments à leur Record R ou à leur attribut", function()
		it(
			"chaque élément apparaît exactement à son Record R, jamais avant (R 0 … 20, 25 … 50)",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				local Visuals = c.h:require("ReplicatedStorage.Shared.Config.Visuals")
				local Format = c.h:require(CLIENT .. "UI.Format")
				local m = c.models[3]
				local base = { Base = m.Vat.Base.Color, Back = m.Shelf.Back.Color, Pot = m.Pot.Body.Color }
				local rs = {}
				for r = 0, 20 do
					table.insert(rs, r)
				end
				for _, r in { 24, 25, 30, 35, 40, 49, 50 } do
					table.insert(rs, r)
				end
				for _, r in rs do
					c.attrs(3, { TapisTier = 1, BestR = r })
					c.run(0.6)
					local tier = 0
					for _, at in Visuals.RanchTiersAt do
						if r >= at then
							tier += 1
						end
					end
					local function has(prefix)
						return c.count(3, prefix) > 0
					end
					expect(has("archSeg")).toBe(tier >= 1)
					expect(has("tower")).toBe(tier >= 2)
					expect(has("balcony")).toBe(tier >= 3)
					expect(has("lh")).toBe(tier >= 4)
					expect(has("dome")).toBe(tier >= 5)
					expect(has("crownBand")).toBe(tier >= 6)
					local stars = 0
					for _, at in Visuals.CrownStarsAt do
						if r >= at then
							stars += 1
						end
					end
					expect(c.count(3, "crownStar")).toBe(if tier >= 6 then stars else 0)
					if tier >= 6 then
						expect(c.parts(3).crownBand1.Material).toBe(
							if r >= Visuals.RainbowCrownAt then Enum.Material.Neon else Enum.Material.Foil
						)
					end
					-- Cuve : anneaux 1 … 8, agitateur arc-en-ciel au R4, buses 0 … 5, dorée au R7
					local vat = c.Look.vat(r)
					expect(c.count(3, "vatRing")).toBe(vat.rings)
					expect(c.count(3, "vatNozzle")).toBe(vat.nozzles)
					expect(c.count(3, "vatBlade")).toBe(3)
					expect(c.parts(3).vatBlade1.Material).toBe(
						if r >= 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic
					)
					expect(m.Vat.Base.Color).toBe(if r >= 7 then c.Look.GOLD else base.Base)
					expect(m.Vat.Glass.Material).toBe(Enum.Material.Glass) -- le verre n'est jamais peint
					-- Pot : cuivre, argent (R2), doré (R6), cristal (R16)
					local pot = c.Look.potLook(c.Look.potMaterial(r))
					expect(m.Pot.Body.Color).toBe(if pot then pot.color else base.Pot) -- doré : l'aspect de la v1.3
					expect(has("house")).toBe(r >= 2)
					expect(c.count(3, "fountainJet")).toBe(if r >= 9 then 3 else 0)
					expect(c.count(3, "lantern")).toBe(if r >= 12 then 8 else 0)
					expect(c.count(3, "gateBand")).toBe(if r >= 13 then 7 else 0)
					expect(c.count(3, "geyser")).toBe(if r >= 17 then 3 else 0)
					expect(c.count(3, "frame")).toBe(if r >= 18 then 8 else 0)
					expect(m.Shelf.Back.Color).toBe(if r >= 19 then c.Look.GOLD else base.Back)
					-- chiffre romain du Record R sur la plaque de l'arche (sorte « fit », jamais TextScaled)
					if tier >= 1 then
						local label = c.parts(3).archPlate.Numeral.Roman
						expect(label.Text).toBe(Format.roman(r))
						expect(label.TextScaled).toBe(false)
					end
				end
				c.clean()
			end
		)

		it(
			"attributs : prêt (anneau rose + lanterne), Squishy-Soleil (GiantTier ≥ 3), Monuments n, Déco perso",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				local Tiers = c.h:require(CLIENT .. "Render.RanchTiers")
				c.attrs(3, { TapisTier = 1, BestR = 10 })
				c.run(0.6)
				expect(c.count(3, "readyRing")).toBe(0)
				expect(c.parts(3).lhLantern.Color).toBe(Tiers.LANTERN)
				c.attrs(3, { SplorchReady = true })
				c.run(0.6)
				expect(c.count(3, "readyRing")).toBe(8)
				expect(c.parts(3).lhLantern.Color).toBe(Tiers.READY)
				c.attrs(3, { SplorchReady = false })
				c.run(0.6)
				expect(c.count(3, "readyRing")).toBe(0)
				expect(c.parts(3).lhLantern.Color).toBe(Tiers.LANTERN)
				for _, g in { 0, 1, 2, 3, 7 } do
					c.attrs(3, { GiantTier = g })
					c.run(0.6)
					expect(c.count(3, "sun")).toBe(if g >= 3 then 9 else 0)
				end
				for _, n in { 0, 1, 4, 10, 11, -3, "x" } do
					c.attrs(3, { Monuments = n })
					c.run(0.6)
					local want = if type(n) == "number" then math.clamp(n, 0, 10) else 0
					local total = 0
					for k = 1, want do
						total += c.h:require(CLIENT .. "Render.MonumentKit").count(k, "full")
					end
					expect(c.count(3, "mon")).toBe(total)
				end
				-- sans silhouette (best.s = 0) : ni cadre, ni anneau, ni soleil (rien à entourer)
				c.attrs(3, { BestR = 20, SplorchReady = true, GiantTier = 3 })
				c.patch(3, { best = { s = 0, m = 0, z = 0, zg = 0 } })
				c.run(0.6)
				expect(c.count(3, "frame") + c.count(3, "readyRing") + c.count(3, "sun")).toBe(0)
				c.clean()
			end
		)
	end)
	describe("RanchRenderer_v2 › étape 4 : retour à la v1.3, interrupteurs séparés", function()
		it(
			"tout retiré en direct : aucune instance v2.0, Cuve, étagère et Pot de la v1.3 exacts",
			function()
				local c = clientV2()
				local before = serverLook(c.models[3])
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, FULL4)
				c.run(1)
				expect(c.count(3, "tower") > 0 and c.count(3, "mon") > 0 and c.count(3, "deco") > 0).toBe(
					true
				)
				expect(c.models[3].Shelf.Back.Color).toBe(c.Look.GOLD)
				c.unset(3, { "TapisTier", "BestR", "SplorchReady", "Monuments", "DecoPerso", "GiantTier" })
				c.run(1)
				expect(c.folder(3)).toBe(nil)
				expect(
					c.h.workspace:FindFirstChild("ClientWorld") == nil
						or c.h.workspace.ClientWorld:FindFirstChild("RanchesV2") == nil
				).toBe(true)
				expect(sameLook(before, serverLook(c.models[3]))).toBe("ok")
				expect(emitters(c.h)).toBe(0)
				expect(c.V2.on).toBe(false)
				c.clean()
			end
		)

		it(
			"interrupteurs séparés : Monuments ou Déco perso seuls, sans palier ; GiantTier ou SplorchReady seuls : rien",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				-- attributs d'autres lots sans interrupteur de dessin : rien de la v2.0
				c.attrs(3, { GiantTier = 4, SplorchReady = true, BestR = 30 })
				c.run(1)
				expect(c.V2.on).toBe(false)
				expect(c.steps()).toBe(0) -- pas même une image v2.0
				expect(c.folder(3)).toBe(nil)
				-- Monuments seul (RanchTiers coupé) : les Monuments, aucun palier ni élément du Record R
				c.attrs(3, { Monuments = 3 })
				c.run(1)
				expect(c.count(3, "mon") > 0).toBe(true)
				expect(c.count(3, "tower") + c.count(3, "vat") + c.count(3, "readyRing") + c.count(3, "sun")).toBe(
					0
				)
				-- Déco perso seule
				c.unset(3, { "Monuments" })
				c.attrs(3, { DecoPerso = DECO12 })
				c.run(1)
				expect(c.count(3, "deco") > 0).toBe(true)
				expect(c.count(3, "mon") + c.count(3, "tower")).toBe(0)
				c.unset(3, { "DecoPerso" })
				c.run(1)
				expect(c.folder(3)).toBe(nil)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 4 : lampions, signal « prêt », lumière du phare", function()
		it("lampions (R12) en Neon seulement pendant la Jelly Moon (interrupteur jellyMoon)", function()
			local c = clientV2()
			local WSC = c.h:require(CLIENT .. "Controllers.WorldStateController")
			local event = nil
			WSC.event = function()
				return event
			end
			c.snapshot(all16b())
			c.at(3, Vector3.new(0, 0, 30))
			c.attrs(3, { TapisTier = 1, BestR = 12 })
			c.run(1)
			local Tiers = c.h:require(CLIENT .. "Render.RanchTiers")
			local function lit()
				local n = 0
				for i = 1, 8 do
					local p = c.parts(3)["lantern" .. i]
					if p.Material == Enum.Material.Neon then
						expect(p.Color).toBe(Tiers.LIT)
						n += 1
					else
						expect(p.Color).toBe(Tiers.UNLIT)
					end
				end
				return n
			end
			expect(lit()).toBe(0)
			local now = c.Clock.now()
			event = { features = { jellyMoon = true }, moon = { active = true, endsAt = now + 300 } }
			c.run(1)
			expect(lit()).toBe(8)
			-- interrupteur coupé en direct : éteints, même si la séance court encore
			event = { features = { jellyMoon = false }, moon = { active = true, endsAt = now + 300 } }
			c.run(1)
			expect(lit()).toBe(0)
			-- fin de la séance : éteints
			event = { features = { jellyMoon = true }, moon = { active = true, endsAt = c.Clock.now() - 1 } }
			c.run(1)
			expect(lit()).toBe(c.Look.moonLit(event, c.Clock.now()) and 8 or 0)
			expect(c.count(3, "lantern")).toBe(8) -- aucune pièce recréée, seulement repeinte
			c.clean()
		end)

		it(
			"anneau « prêt » : au plus 3 changements de couleur par seconde ; rose fixe en Mouvement réduit",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 1, BestR = 10, SplorchReady = true })
				c.run(1)
				local Tiers = c.h:require(CLIENT .. "Render.RanchTiers")
				local ring = c.parts(3).readyRing1
				local changes = 0
				local conn = ring:GetPropertyChangedSignal("Color"):Connect(function()
					changes += 1
				end)
				c.run(4)
				expect(changes >= 4 and changes <= 3 * 4 + 1).toBe(true)
				-- Mouvement réduit : rose fixe, plus aucun changement
				c.flags.reduced = true
				c.run(0.5)
				expect(ring.Color).toBe(Tiers.READY)
				changes = 0
				c.run(3)
				expect(changes).toBe(0)
				-- la lanterne du phare : rose, immobile en Mouvement réduit
				local lantern = c.parts(3).lhLantern
				local cf = lantern.CFrame
				c.run(1)
				expect(lantern.CFrame).toBe(cf)
				expect(lantern.Color).toBe(Tiers.READY)
				conn:Disconnect()
				c.clean()
			end
		)

		it(
			"lanterne du phare (D23) : celle de MON ranch en détail complet au palier 4, rien sinon",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 1, BestR = 9 })
				c.attrs(4, { TapisTier = 1, BestR = 15 })
				c.run(1)
				expect(c.V2.lanternPart(3)).toBe(nil) -- palier 3 seulement
				expect(c.V2.lanternPart(4)).toBe(c.parts(4).lhLantern) -- voisin : Neon, sans lumière (LightingController ne prend que le mien)
				c.attrs(3, { BestR = 10 })
				c.run(1)
				expect(c.V2.lanternPart(3)).toBe(c.parts(3).lhLantern)
				-- je pars loin (ranch 10) : mon ranch passe en détail réduit, plus de lanterne complète
				c.at(10, Vector3.new(0, 0, 36))
				c.run(1)
				expect(c.V2.lanternPart(3)).toBe(nil)
				c.at(3, Vector3.new(0, 0, 36))
				c.run(1)
				expect(c.V2.lanternPart(3) ~= nil).toBe(true)
				c.unset(3, { "TapisTier" })
				c.run(1)
				expect(c.V2.lanternPart(3)).toBe(nil)
				expect(c.V2.lanternPart(0 / 0)).toBe(nil)
				c.clean()
			end
		)

		it(
			"étincelles des buses (≤ 5) sur une naissance mutée de MON ranch, rendues après 0,8 s",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 1, BestR = 5 }) -- 5 buses au Record R 5
				c.run(1)
				expect(emitters(c.h)).toBe(0) -- aucun émetteur permanent
				local function hatch(m)
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
						kind = "hatch",
						data = {
							uid = "u",
							species = 1,
							rarity = 1,
							mutation = m,
							oneIn = 1,
							isNew = false,
							scripted = false,
							at = "pen",
						},
					})
					c.h:settle(1)
				end
				hatch(0)
				expect(emitters(c.h)).toBe(0) -- naissance sans mutation : rien
				hatch(3)
				expect(emitters(c.h)).toBe(5)
				expect(c.VB.used("record", "particles")).toBe(5)
				hatch(4) -- quota plein : pas d'étincelle de plus, jamais d'erreur
				expect(emitters(c.h)).toBe(5)
				c.run(1)
				expect(emitters(c.h)).toBe(0)
				expect(c.VB.used("record", "particles")).toBe(0)
				-- Graphismes légers : aucune étincelle
				c.flags.low = true
				c.h:require(CLIENT .. "Controllers.QualityController").Changed:Fire(true)
				c.run(0.5)
				hatch(3)
				expect(emitters(c.h)).toBe(0)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 4 : Déco perso hostile, cascades, crochets de B5", function()
		it("chaînes DecoPerso hostiles : seuls les objets valides sont dessinés, sans trace", function()
			local c = clientV2()
			c.snapshot(all16b())
			c.at(3, Vector3.new(0, 0, 30))
			local Deco = c.h:require(CLIENT .. "Render.DecoKit")
			local cases = {
				"",
				"x",
				DECO12 .. ",15",
				"-1,2,-3",
				"1e9",
				"1000000000,2",
				"1,1,1,1",
				"6",
				"1,,3,,,,,,6",
				",,,,,,,,6,8",
				string.rep("9", 200),
				"0,0,0,0,0,0,0,0,0,0,0,0",
				DECO12,
			}
			for _, attr in cases do
				c.attrs(3, { DecoPerso = attr })
				c.run(0.6)
				local want = 0
				for _, n in c.Look.decoPerso(attr) do
					if n ~= 0 then
						want += Deco.count(n, "full")
					end
				end
				expect(c.count(3, "deco")).toBe(want)
			end
			-- un attribut d'un autre type : aucun objet
			c.attrs(3, { DecoPerso = 12 })
			c.run(0.6)
			expect(c.count(3, "deco")).toBe(0)
			c.clean()
		end)

		it(
			"premier passage : cascade et ElementBuilt ; chargement, retour au ranch, nouveau propriétaire : rien",
			function()
				local built = {}
				local c = clientV2({
					attrs = { [3] = { TapisTier = 1, BestR = 9, Monuments = 0, DecoPerso = "" } },
				})
				c.RR.ElementBuilt:Connect(function(slot, id)
					table.insert(built, slot .. ":" .. id)
				end)
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.run(1)
				expect(c.BC.stats().pushed).toBe(0) -- chargement : posé sans animation
				expect(#built).toBe(0)
				c.attrs(3, { BestR = 10 }) -- le phare se construit
				c.run(0.2)
				expect(c.BC.stats().pushed).toBe(1)
				expect(table.concat(built, ",")).toBe("3:tier4.jellyLighthouse")
				c.run(2)
				expect(c.parts(3).lh1.CFrame).toBe(
					c.h
						:require(CLIENT .. "Render.RanchTiers")
						.tier(3, 4, { color = Color3.new(), ready = false, stars = 0, rainbow = false })[1].cf
				)
				c.attrs(3, { Monuments = 1 })
				c.run(0.2)
				expect(built[2]).toBe("3:monument.1")
				c.attrs(3, { DecoPerso = "1" })
				c.run(0.2)
				expect(built[3]).toBe("3:deco.1")
				c.run(2)
				local pushed = c.BC.stats().pushed
				-- je pars au ranch 10 puis je reviens : détail changé, aucune cascade
				c.at(10, Vector3.new(0, 0, 36))
				c.run(1)
				c.at(3, Vector3.new(0, 0, 36))
				c.run(1)
				expect(c.BC.stats().pushed).toBe(pushed)
				-- nouveau propriétaire : posé tel quel
				c.patch(3, { userId = 0 })
				c.run(0.5)
				c.patch(3, { userId = 1 })
				c.run(1)
				expect(c.BC.stats().pushed).toBe(pushed)
				expect(#built).toBe(3)
				-- crochets de B5 : détail et repère des éléments dessinés
				expect(c.RR.detail(3)).toBe("full")
				expect(c.RR.elementCFrame(3, "tier4.jellyLighthouse")).toBe(c.WL.v2Anchor(3, "lighthouse"))
				expect(c.RR.elementCFrame(3, "monument.1")).toBe(c.WL.monumentSlot(3, 1))
				expect(c.RR.elementCFrame(3, "monument.2")).toBe(nil)
				expect(c.RR.elementCFrame(3, "tier6.floatingCrown")).toBe(nil)
				expect(c.RR.elementCFrame(3, "nope")).toBe(nil)
				c.clean()
			end
		)

		it(
			"chiffre romain : sorte « fit » qui tient dans la plaque jusqu'au Record R 400 (MaxR)",
			function()
				local Screens = require("../harness/Screens")
				local c = clientV2()
				Screens.realTextService()
				c.snapshot(all16b())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 1, BestR = 1 })
				c.run(1)
				local Text = c.h:require(CLIENT .. "UI.Text")
				local Format = c.h:require(CLIENT .. "UI.Format")
				local Balance = c.h:require("ReplicatedStorage.Shared.Config.Balance")
				local gui = c.parts(3).archPlate.Numeral
				local label = gui.Roman
				expect(gui.SizingMode).toBe(Enum.SurfaceGuiSizingMode.FixedSize)
				expect(gui.Face).toBe(Enum.NormalId.Front)
				expect(Text.kind(label)).toBe("fit")
				-- le moteur donne au libellé la taille de la toile (SizingMode FixedSize)
				label.AbsoluteSize = gui.CanvasSize
				c.h:settle(1)
				local box = Vector2.new(gui.CanvasSize.X - 16, gui.CanvasSize.Y - 16)
				local TextService = c.h.game.TextService
				local worst = ""
				for r = 1, Balance.Prestige.MaxR do
					local text = Format.roman(r)
					if #text > #worst then
						worst = text
					end
					Text.raw(label, text)
					local size = Text.displaySize(label)
					expect(size >= 28).toBe(true)
					local w = TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(1e5, 1e5))
					expect(w.X <= box.X + 0.5 and w.Y <= box.Y + 0.5).toBe(true)
					expect(label.TextScaled).toBe(false)
				end
				expect(worst).toBe("CCCLXXXVIII")
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 4 : idempotence, robot, 16 ranchs au maximum", function()
		it(
			"second rendu : rien de créé ni d'écrit (hors animations) ; un robot qui traverse ne change rien",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				for slot = 1, 16 do
					c.attrs(slot, FULL4)
				end
				c.at(3, Vector3.new(0, 0, 30))
				c.run(1.5)
				local function counts()
					local out = {}
					for slot = 1, 16 do
						local n = 0
						for _ in c.parts(slot) do
							n += 1
						end
						out[slot] = n
					end
					return out
				end
				local ref = counts()
				local n0 = instanceCount(c.h)
				local renders = c.V2.stats().renders
				local writes = 0
				local watched = {}
				-- pièces du serveur (Wobbleton) et décors v2.0 (ClientWorld) ; le personnage bouge, lui
				local clientWorld = c.h.workspace:FindFirstChild("ClientWorld")
				for _, d in c.h.workspace:GetDescendants() do
					local world = d:IsDescendantOf(c.h.workspace.Wobbleton)
						or (clientWorld ~= nil and d:IsDescendantOf(clientWorld))
					if d.ClassName == "Part" and world then
						table.insert(
							watched,
							d.Changed:Connect(function(prop)
								if not (c.V2.isAnimated(d) and (prop == "CFrame" or prop == "Color")) then
									writes += 1
								end
							end)
						)
					end
				end
				-- même état revu, puis un robot qui traverse son ranch dans tous les sens
				c.patch(3, { tiles = { snack = 5, decor = 4, pens = 3, cozyBed = true, seen = 15 } })
				c.V2.onQualityChanged()
				c.attrs(3, { Monuments = 10, DecoPerso = DECO12 })
				for _, z in { 2, 20, 50, 71 } do
					for _, x in { -31, 0, 31 } do
						c.at(3, Vector3.new(x, 0, z))
						c.run(0.2)
						expect(c.V2.current()).toBe(3)
					end
				end
				c.at(3, Vector3.new(0, 0, -6))
				c.run(0.5)
				local now = counts()
				for slot = 1, 16 do
					expect(now[slot]).toBe(ref[slot])
				end
				expect(instanceCount(c.h)).toBe(n0)
				expect(writes).toBe(0)
				expect(c.V2.stats().renders).toBe(renders)
				expect(c.BC.stats().pushed).toBe(0)
				for _, conn in watched do
					conn:Disconnect()
				end
				c.clean()
			end
		)

		it(
			"16 ranchs au maximum (Record R 50, Monuments 10, 12 Déco perso) : chaque système dans son budget",
			function()
				local c = clientV2()
				c.snapshot(all16b())
				for slot = 1, 16 do
					c.attrs(slot, FULL4)
				end
				c.at(3, Vector3.new(0, 0, 30))
				c.run(2)
				local Deco = c.h:require(CLIENT .. "Render.DecoKit")
				local st = c.VB.stats()
				local v2 = c.V2.stats()
				local sum = 0
				for _, sys in SYSTEMS4 do
					expect(st[sys].used <= st[sys].parts).toBe(true)
					expect(st[sys].refused).toBe(0)
					expect(v2[sys] <= c.VB.LIMITS[sys].parts).toBe(true)
					sum += v2[sys]
				end
				expect(v2.parts).toBe(sum)
				expect(c.VB.exceeded()).toBe(0)
				expect(#metrics(c.h)).toBe(0)
				-- détail : complet (2, 3, 4), réduit (les 13 autres)
				expect(v2.tiers).toBe(3 * (86 + 4) + 13 * 9)
				expect(v2.record).toBe(3 * (8 + 4 + 5 + 3 + 8 + 7 + 3))
				expect(v2.house).toBe(3 * 6)
				expect(v2.silhouette).toBe(3 * (8 + 8 + 9))
				expect(v2.monuments).toBe(10 * 20 + 2 * 10 * 6 + 13 * 10)
				local decoFull = 0
				for _, n in c.Look.decoPerso(DECO12) do
					decoFull += Deco.count(n, "full")
				end
				expect(v2.decoPerso).toBe(3 * decoFull + 13 * 4)
				expect(v2.plinths).toBe(3 * 18 * 2)
				-- les ranchs réduits : tour, phare, couronne réduits, silhouettes des Monuments et des grands objets
				for slot = 5, 16 do
					for name in c.parts(slot) do
						local reduced = string.sub(name, 1, 3) == "far"
							or string.sub(name, 1, 4) == "monF"
							or string.match(name, "^deco%d+_%d+_far$") ~= nil
						expect(reduced and name or "ok").toBe(name)
					end
					expect(c.count(slot, "far")).toBe(9)
					expect(c.count(slot, "monF")).toBe(10)
				end
				-- voisins : Monuments à 6 pièces ; ranch courant : 20
				expect(c.count(2, "monN")).toBe(60)
				expect(c.count(3, "mon1_")).toBe(20)
				c.clean()
			end
		)

		it(
			"API Roblox valide (ApiAudit) : paliers, plaque et chiffre, Monuments, Déco perso, étincelles",
			function()
				ApiAudit.start()
				local ok, err = pcall(function()
					local c = clientV2()
					c.snapshot(all16b())
					c.at(3, Vector3.new(0, 0, 30))
					c.attrs(3, FULL4)
					c.attrs(4, FULL4)
					c.run(1)
					c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
						kind = "hatch",
						data = {
							uid = "u",
							species = 1,
							rarity = 1,
							mutation = 2,
							oneIn = 1,
							isNew = false,
							scripted = false,
							at = "pen",
						},
					})
					c.h:settle(1)
					c.attrs(3, { BestR = 49 })
					c.run(1)
					c.attrs(3, { BestR = 50, Monuments = 9 })
					c.run(1.5)
					c.clean()
				end)
				local issues = ApiAudit.stop()
				expect(ok and true or err).toBe(true)
				expect(table.concat(issues, "\n")).toBe("")
			end
		)
	end)

	-- =========================================================================================
	-- Étape 5 (partie 3 ; D9, D10, D16, D20-D22, D25, D30) : halo, ciel, Observatoire, kiosque,
	-- Prairie v2, glaçons du costume d'hiver ; interrupteurs coupés : rien de tout cela
	-- =========================================================================================

	local T_WINTER = 1797156120 -- dimanche 13/12/2026 10:02 UTC : costume d'hiver en vigueur

	local function eventState(over)
		local p = {
			features = {
				boopRush = "on",
				megaSquish = true,
				golden = true,
				jellyMoon = true,
				gauge = true,
				clips = true,
				costume = "",
				diagnostics = true,
			},
			mega = { phase = "idle", points = 0, target = 0 },
			rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
			golden = { active = false, id = 0, endsAt = 0 },
			moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
			gauge = { points = 0, target = 1000, partyUntil = 0, restUntil = 0 },
			boost = { kind = "", untilT = 0, byName = "" },
			spectacle = { queue = {} },
			offset = 0,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	-- Instantané v2.0 de l'écran Améliorations (profil témoin v2, interrupteurs ouverts ; `edit` peut
	-- couper des interrupteurs : flags.Workshop = false cache toutes les lignes de l'Atelier)
	local snapVersion = 0
	local function upgradeSnap(h, edit)
		local UM = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
		local Features = h:require("ReplicatedStorage.Shared.Config.Features")
		local flags = {}
		for k, v in Features.Defaults do
			flags[k] = if type(v) == "boolean" then true else v
		end
		local p = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
		if edit then
			edit(p, flags)
		end
		snapVersion += 1
		return UM.snapshot(p, flags, snapVersion)
	end

	local function worldV2(c)
		local world = c.h.workspace:FindFirstChild("ClientWorld")
		return world and world:FindFirstChild("WorldV2")
	end

	local function partsOf(folder)
		local out = {}
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(out, d)
				end
			end
		end
		return out
	end

	-- toutes les pièces v2.0 du monde : ancrées, non solides, sans ombre, opaques, matériaux permis
	local function checkParts(list)
		local allowed = {
			[Enum.Material.SmoothPlastic] = true,
			[Enum.Material.Neon] = true,
			[Enum.Material.Foil] = true,
			[Enum.Material.Ice] = true,
		}
		for _, p in list do
			expect({
				name = p.Name,
				ok = p.Anchored
					and not p.CanCollide
					and not p.CanQuery
					and not p.CanTouch
					and not p.CastShadow
					and p.Transparency == 0
					and allowed[p.Material] == true,
			}).toEqual({ name = p.Name, ok = true })
		end
	end

	local function labelOf(c, key)
		local out = {}
		local world = c.h.workspace:FindFirstChild("ClientWorld")
		local holder = world and world:FindFirstChild("Labels")
		for _, gui in (if holder then holder:GetChildren() else {}) do
			if gui.Name == "Label_" .. key then
				table.insert(out, gui)
			end
		end
		return out
	end

	describe("RanchRenderer_v2 › étape 5 : interrupteurs coupés", function()
		it(
			"aucun halo, aucun ciel, aucun monde v2.0 ; le panneau garde la couronne dessinée et le r public",
			function()
				local c = clientV2({ lighting = true, event = eventState() })
				for slot = 1, 16 do
					part(c.models[slot], "Sign", { Size = Vector3.new(6, 2, 0.4) })
				end
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				c.run(2)
				c.LC.refresh()
				c.run(1)
				local Halo = c.h:require(CLIENT .. "Render.Halo")
				local WV = c.h:require(CLIENT .. "Render.WorldV2")
				expect(Halo.on).toBe(false)
				expect(c.h.workspace.ClientWorld:FindFirstChild("Halos")).toBeNil()
				expect(worldV2(c)).toBeNil()
				expect(WV.stats()).toEqual({
					observatory = 0,
					kiosk = 0,
					meadow = 0,
					icicles = 0,
					icicleRanches = 0,
					hidden = 0,
				})
				expect(WV.kioskOpen()).toBe(false)
				expect(c.V2.stats().sky).toBe(0)
				expect(c.V2.on).toBe(false)
				-- panneau de la v1.3 : « P3 · ♛4 · Jour 4 », couronne DESSINÉE (D20, les deux états)
				local Text = c.h:require(CLIENT .. "UI.Text")
				local gui = find(c.h.workspace, "Sign3")
				local label = gui.Plate.Text
				expect(string.find(label.Text, "{^}", 1, true)).toBeNil()
				expect(string.find(label.Text, "♛", 1, true)).toBeNil()
				expect(string.match(label.Text, "^P3 ·  +4 · Day 4$") ~= nil).toBe(true)
				local icons = Text.icons(label)
				expect(#icons).toBe(1)
				expect(icons[1]:GetAttribute("Icon")).toBe("crown")
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : halo et plaque du titre (D16)", function()
		it(
			"min(A, 5) gouttes autour de la tête, 15 Hz ; Mouvement réduit : immobiles ; plaque : goutte et A",
			function()
				local c = clientV2()
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				-- la tête suit le corps (le personnage du harnais ne la déplace pas tout seul)
				local character = c.h.localPlayer.Character
				character.Head.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 1.5, 0)
				c.attrs(3, { HaloOn = true, Ascend = 3 })
				c.run(0.6)
				local Halo = c.h:require(CLIENT .. "Render.Halo")
				local Visuals = c.h:require("ReplicatedStorage.Shared.Config.Visuals")
				local drops = Halo.drops(3)
				expect(#drops).toBe(3)
				local head = c.h.localPlayer.Character.Head
				for i, d in drops do
					expect(d.Shape).toBe(Enum.PartType.Ball)
					expect(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CastShadow).toBe(true)
					local off = d.Position - head.Position
					expect(math.abs(math.sqrt(off.X * off.X + off.Z * off.Z) - 1.7) < 0.05).toBe(true)
					expect(Visuals.Halo[i] ~= nil).toBe(true)
				end
				-- en orbite : les gouttes tournent
				local before = drops[1].Position
				c.run(0.5)
				expect((drops[1].Position - before).Magnitude > 0.1).toBe(true)
				-- plaque du titre : goutte dessinée et « 3 » (aucun titre, nom visible : la goutte seule)
				local Text = c.h:require(CLIENT .. "UI.Text")
				local plate = find(c.h.workspace, "Title3").Plate.Text
				expect(string.match(plate.Text, "^ +3$") ~= nil).toBe(true)
				expect(Text.icons(plate)[1]:GetAttribute("Icon")).toBe("drop")
				-- A = 60 : 5 gouttes (arc-en-ciel la 5e) et « 60 » sur la plaque
				c.attrs(3, { Ascend = 60 })
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(5)
				expect(string.match(plate.Text, "^ +60$") ~= nil).toBe(true)
				-- Mouvement réduit : immobiles autour de la tête
				c.flags.reduced = true
				c.run(0.2)
				local still = Halo.drops(3)[2].Position
				c.run(0.6)
				expect((Halo.drops(3)[2].Position - still).Magnitude < 1e-6).toBe(true)
				-- 15 Hz au plus : 2 s d'images à 60 Hz donnent au plus 30 placements par goutte
				c.flags.reduced = false
				local moves = 0
				local d1 = Halo.drops(3)[1]
				d1:GetPropertyChangedSignal("CFrame"):Connect(function()
					moves += 1
				end)
				for _ = 1, 120 do
					c.Clock.advance(1 / 60)
					c.RR._step(1 / 60)
				end
				c.h:settle(1)
				expect(moves <= 31).toBe(true)
				-- halo éteint par le joueur (HaloOn = false) : plus rien, plaque sans goutte
				c.attrs(3, { HaloOn = false })
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(0)
				expect(Halo.on).toBe(false)
				c.clean()
			end
		)

		it(
			"sans personnage : rien, sans trace ; personnage revenu : le halo revient ; ranch libéré : retiré",
			function()
				local c = clientV2()
				c.snapshot(all16())
				c.attrs(3, { HaloOn = true, Ascend = 2 })
				c.run(0.6)
				local Halo = c.h:require(CLIENT .. "Render.Halo")
				expect(#Halo.drops(3)).toBe(2)
				local character = c.h.localPlayer.Character
				c.h.localPlayer.Character = nil
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(0)
				c.h.localPlayer.Character = character
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(2)
				-- attributs illisibles : aucun halo
				c.attrs(3, { Ascend = 0 / 0 })
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(0)
				c.attrs(3, { Ascend = "5" })
				c.run(0.6)
				expect(#Halo.drops(3)).toBe(0)
				c.unset(3, { HaloOn, "Ascend" })
				c.run(0.6)
				expect(Halo.stats().total).toBe(0)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : ciel des Ascensions (D25)", function()
		it(
			"dessin de A au-dessus de la clôture du fond, hors de la colonne du centre ; niveaux par ranch",
			function()
				local c = clientV2()
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				local SkyKit = c.h:require(CLIENT .. "Render.SkyKit")
				for a = 1, 20 do
					c.attrs(3, { TapisTier = 1, Ascend = a })
					c.run(1.6) -- cascade finie (1,2 s au plus) : poses finales
					local n = c.count(3, "sky")
					expect({ a = a, n = n }).toEqual({ a = a, n = SkyKit.count(a, "near") })
					expect(n <= SkyKit.NEAR_MAX).toBe(true)
					-- emprise « sky » du plan (D8) : disque de rayon 12 autour de (0, 84), Y de 34 à 48
					for name, p in c.parts(3) do
						if string.sub(name, 1, 3) == "sky" then
							local l = c.WL.toLocal(3, p.Position)
							local r = math.sqrt(l.X * l.X + (l.Z - 84) ^ 2)
							expect({ name = name, inside = r <= 12.5 and l.Y >= 33 and l.Y <= 49 }).toEqual({
								name = name,
								inside = true,
							})
							-- jamais dans la colonne du centre (silhouette)
							local col = c.WL.centerColumn()
							local dc = math.sqrt((l.X - col.center.X) ^ 2 + (l.Z - col.center.Z) ^ 2)
							expect(dc > col.radius).toBe(true)
						end
					end
				end
				checkParts((function()
					local out = {}
					for name, p in c.parts(3) do
						if string.sub(name, 1, 3) == "sky" then
							table.insert(out, p)
						end
					end
					return out
				end)())
				-- voisin (détail complet) : ≤ 10 pièces ; ranch lointain : 3 pièces
				c.attrs(4, { TapisTier = 1, Ascend = 5 })
				c.attrs(10, { TapisTier = 1, Ascend = 10 })
				c.run(0.6)
				expect(c.count(4, "sky")).toBe(SkyKit.count(5, "mid"))
				expect(c.count(4, "sky") <= SkyKit.MID_MAX).toBe(true)
				expect(c.count(10, "sky")).toBe(SkyKit.FAR)
				-- sans TapisTier (RanchTiers coupé) : aucun ciel, même avec Ascend
				c.unset(4, { "TapisTier" })
				c.run(0.6)
				expect(c.count(4, "sky")).toBe(0)
				c.clean()
			end
		)

		it(
			"une Ascension de plus construit le nouvel élément pièce par pièce (cascade, ElementBuilt) ; étoiles A11-A20",
			function()
				local c = clientV2()
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				c.attrs(3, { TapisTier = 1, Ascend = 1 })
				c.run(0.6)
				local built = {}
				c.V2.ElementBuilt:Connect(function(slot, id)
					table.insert(built, slot .. ":" .. id)
				end)
				local cascades = c.V2.stats().cascades
				c.attrs(3, { Ascend = 2 })
				c.run(0.1)
				expect(c.V2.stats().cascades).toBe(cascades + 1)
				expect(table.find(built, "3:sky") ~= nil).toBe(true)
				c.run(2)
				-- étoiles de la Constellation : une Ascension de plus = une étoile et son trait (2 pièces neuves)
				c.attrs(3, { Ascend = 11 })
				c.run(2)
				local created = c.V2.stats().created
				c.attrs(3, { Ascend = 12 })
				c.run(2)
				expect(c.V2.stats().created - created).toBe(2)
				expect(c.count(3, "sky10near.s")).toBe(12)
				-- au-delà de A20 : 20 étoiles, rien de plus
				c.attrs(3, { Ascend = 60 })
				c.run(2)
				expect(c.count(3, "sky10near.s")).toBe(20)
				-- second rendu identique : rien de créé
				local after = c.V2.stats().created
				c.run(2)
				expect(c.V2.stats().created).toBe(after)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : Observatoire et faisceau (D10, D25)", function()
		it(
			"construit tant que MON ranch porte TapisTier ; faisceau : AscendReady (le mien d'abord), puis le héros d'une Ascension",
			function()
				local c = clientV2({ lighting = true, event = eventState() })
				c.snapshot(all16())
				c.run(1)
				local WV = c.h:require(CLIENT .. "Render.WorldV2")
				c.attrs(7, { TapisTier = 1 }) -- un autre ranch seul : rien
				c.LC.refresh()
				expect(WV.stats().observatory).toBe(0)
				c.attrs(3, { TapisTier = 1 })
				c.LC.refresh()
				expect(WV.stats().observatory).toBe(24)
				expect(WV.beamTarget()).toBe(0)
				local obs = worldV2(c).Observatory
				checkParts(partsOf(obs))
				-- loin de la place, au-delà du mur du bord (r ≈ 340) : inaccessible
				local base = c.WL.observatory().Position
				expect(math.abs(math.sqrt(base.X ^ 2 + base.Z ^ 2) - 340) < 1).toBe(true)
				c.attrs(7, { AscendReady = true })
				c.LC.refresh()
				expect(WV.beamTarget()).toBe(7)
				local beam = obs:FindFirstChild("Beam")
				expect(beam.Material).toBe(Enum.Material.Neon)
				expect(WV.stats().observatory).toBe(25)
				-- le faisceau va du bout de la lunette au ranch visé
				local target = c.WL.toWorld(7, Vector3.new(0, 2, 36))
				local tip = beam.CFrame * Vector3.new(beam.Size.X / 2, 0, 0)
				expect((tip - target).Magnitude < 1).toBe(true)
				-- le mien d'abord
				c.attrs(3, { AscendReady = true })
				c.LC.refresh()
				expect(WV.beamTarget()).toBe(3)
				-- Jelly Ascend en cours : le ranch du héros (joueur 109, ranch 9)
				local now = c.Clock.now()
				c.setEvent(eventState({
					spectacle = {
						queue = {},
						current = {
							kind = "ascend",
							userId = 109,
							startedAt = now - 1,
							burstAt = now + 3,
							endsAt = now + 9,
							level = 3,
						},
					},
				}))
				expect(WV.beamTarget()).toBe(9)
				-- spectacle fini : de nouveau le mien ; plus rien de prêt : aucun faisceau
				c.setEvent(eventState())
				expect(WV.beamTarget()).toBe(3)
				c.unset(3, { "AscendReady" })
				c.unset(7, { "AscendReady" })
				c.LC.refresh()
				expect(WV.beamTarget()).toBe(0)
				expect(obs:FindFirstChild("Beam")).toBeNil()
				-- TapisTier coupé en direct : plus d'Observatoire, budget rendu
				c.unset(3, { "TapisTier" })
				c.LC.refresh()
				expect(WV.stats().observatory).toBe(0)
				expect(worldV2(c)).toBeNil()
				expect(c.VB.used("world")).toBe(0)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : kiosque de Big Plop (D21)", function()
		it(
			"seulement avec l'instantané de l'écran Améliorations et une ligne de l'Atelier visible ; étiquette world.kiosk",
			function()
				local c = clientV2({ lighting = true, event = eventState() })
				c.snapshot(all16())
				c.run(1)
				local WV = c.h:require(CLIENT .. "Render.WorldV2")
				c.LC.refresh()
				expect(WV.kioskOpen()).toBe(false)
				-- instantané où l'Atelier est coupé (interrupteur Workshop) : toutes ses lignes cachées
				c.profile({
					coins = 0,
					upgradeSnapshot = upgradeSnap(c.h, function(p, flags)
						-- toutes les règles d'ouverture remplies : une ligne fermée est alors coupée (cachée)
						p.bestR, p.ascend = 400, 60
						flags.Workshop = false
					end),
				})
				c.LC.refresh()
				expect(WV.kioskOpen()).toBe(false)
				expect(#labelOf(c, "world.kiosk")).toBe(0)
				-- instantané complet : le kiosque (15 pièces rayées menthe) et son étiquette
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { upgradeSnapshot = upgradeSnap(c.h) })
				c.h:settle(1)
				c.LC.refresh()
				expect(WV.kioskOpen()).toBe(true)
				expect(WV.stats().kiosk).toBe(15)
				local kiosk = worldV2(c).Kiosk
				checkParts(partsOf(kiosk))
				local center = Vector3.new(0, 0, 0)
				for _, p in partsOf(kiosk) do
					local d = Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(-30, 0, 24)
					expect(d.Magnitude < 5).toBe(true)
				end
				local labels = labelOf(c, "world.kiosk")
				expect(#labels).toBe(1)
				expect(labels[1].Text.Text).toBe("Big Plop's Workshop")
				expect(labels[1].Adornee.Parent).toBe(kiosk)
				-- même état : rien de recréé ni de réécrit
				local same = kiosk.Kiosk1
				c.LC.refresh()
				expect(worldV2(c).Kiosk.Kiosk1).toBe(same)
				expect(#labelOf(c, "world.kiosk")).toBe(1)
				-- instantané retiré (UpgradesScreen coupé en direct) : kiosque et étiquette retirés
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", {}, { "upgradeSnapshot" })
				c.h:settle(1)
				c.LC.refresh()
				expect(WV.kioskOpen()).toBe(false)
				expect(#labelOf(c, "world.kiosk")).toBe(0)
				expect(worldV2(c)).toBeNil()
				expect(center).toBe(Vector3.new(0, 0, 0))
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : Prairie v2 (D9)", function()
		it(
			"MON ranch porte Monuments : Prairie du serveur cachée (et son étiquette), Prairie v2 ; coupé : tout revient exactement",
			function()
				local c = clientV2({ lighting = true, event = eventState() })
				-- Prairie du serveur (World/Town.meadow) : sol, fleurs, poteau, panneau étiqueté
				local meadow = folder(c.h.workspace.Wobbleton, "Meadow")
				local field = part(meadow, "Field", { Transparency = 0 })
				local flower = part(meadow, "Flower1", { Transparency = 0.25 })
				local post = part(meadow, "SignPost", { Transparency = 0 })
				local sign = part(meadow, "Sign", { Transparency = 0 })
				sign:SetAttribute("LabelKey", "world.meadow")
				sign:SetAttribute("LabelHeight", 2)
				c.LC.refresh()
				-- monde déjà trouvé au démarrage : l'étiquette de la v1.3 est posée par la recherche du monde
				c.h.workspace.ClientWorld.Labels:Destroy()
				c.h:require(CLIENT .. "Controllers.LightingController")
				c.snapshot(all16())
				c.run(1)
				local WV = c.h:require(CLIENT .. "Render.WorldV2")
				c.attrs(3, { Monuments = 2 })
				c.LC.refresh()
				expect(WV.meadowV2()).toBe(true)
				expect(WV.stats().meadow).toBe(32)
				for _, p in { field, flower, post, sign } do
					expect(p.Transparency).toBe(1)
				end
				checkParts(partsOf(worldV2(c).Meadow))
				-- Prairie v2 dans son jardin (r ≈ 145, D9), panneau world.meadow
				local center = c.WL.meadowCenter(true)
				for _, p in partsOf(worldV2(c).Meadow) do
					local d = Vector3.new(p.Position.X - center.X, 0, p.Position.Z - center.Z)
					expect(d.Magnitude <= 12.5).toBe(true)
				end
				local v2Labels = {}
				for _, gui in labelOf(c, "world.meadow") do
					if gui.Adornee and gui.Adornee:IsDescendantOf(worldV2(c)) then
						table.insert(v2Labels, gui)
					end
				end
				expect(#v2Labels).toBe(1)
				expect(v2Labels[1].Enabled).toBe(true)
				-- coupé en direct : la Prairie du serveur revient exactement (0,25 reste 0,25)
				c.unset(3, { "Monuments" })
				c.LC.refresh()
				expect(WV.meadowV2()).toBe(false)
				expect(field.Transparency).toBe(0)
				expect(flower.Transparency).toBe(0.25)
				expect(post.Transparency).toBe(0)
				expect(sign.Transparency).toBe(0)
				expect(worldV2(c)).toBeNil()
				for _, gui in labelOf(c, "world.meadow") do
					expect(gui.Adornee and gui.Adornee:IsDescendantOf(c.h.workspace.Wobbleton.Meadow)).toBe(
						true
					)
					expect(gui.Enabled).toBe(true)
				end
				expect(c.VB.used("meadow")).toBe(0)
				c.clean()
			end
		)
	end)

	describe("RanchRenderer_v2 › étape 5 : glaçons du costume d'hiver (D30)", function()
		local function winter(on)
			local p = eventState()
			p.features.costume = "winter2026"
			if on then
				p.features.ambience = true
			end
			return p
		end

		it(
			"seulement avec Ambience ET le costume d'hiver : ranch courant et ses 2 voisins, 12 pièces chacun",
			function()
				local c = clientV2({ lighting = true, t = T_WINTER, event = winter(false) })
				c.snapshot(all16())
				c.at(3, Vector3.new(0, 0, 30))
				c.run(1)
				local WV = c.h:require(CLIENT .. "Render.WorldV2")
				c.LC.refresh()
				-- costume sans Ambience : le costume de la v1.3, aucun glaçon
				expect(c.LC.current()).toBe("winter")
				expect(WV.stats().icicles).toBe(0)
				-- Ambience ouvert, sans costume : rien
				local noCostume = eventState()
				noCostume.features.ambience = true
				c.setEvent(noCostume)
				expect(WV.stats().icicles).toBe(0)
				-- les deux : ranchs 2, 3, 4
				c.setEvent(winter(true))
				expect(WV.icicleSlots()).toEqual({ 2, 3, 4 })
				expect(WV.stats().icicles).toBe(3 * WV.ICICLES_PER_RANCH)
				checkParts(partsOf(worldV2(c)))
				-- sous la lisse haute de la clôture de devant, hors du portail
				for _, p in partsOf(worldV2(c).Icicles3) do
					local l = c.WL.toLocal(3, p.Position)
					expect(math.abs(l.Z - 0.5) < 0.01 and math.abs(l.X) > 5 and l.Y > 1.6 and l.Y < 3.2).toBe(
						true
					)
				end
				-- décor du costume ≤ 300 pièces avec le sucre glace et les guirlandes
				expect(c.LC.stats().winterParts + WV.stats().icicles <= 300).toBe(true)
				-- le joueur va chez le voisin (≥ 10 studs dedans) : les glaçons suivent
				c.at(5, Vector3.new(0, 0, 30))
				c.LC.refresh()
				expect(WV.icicleSlots()).toEqual({ 4, 5, 6 })
				-- Ambience coupé en direct : plus aucun glaçon
				c.setEvent(winter(false))
				expect(WV.stats().icicles).toBe(0)
				expect(worldV2(c)).toBeNil()
				c.clean()
			end
		)
	end)
end
