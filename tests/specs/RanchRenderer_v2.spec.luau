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
		Clock.freeze(T0)
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
		local c = {
			h = h,
			RR = RR,
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
					local total = 0
					for _ in c.parts(3) do
						total += 1
					end
					expect(total).toBe(c.Kit.tapisCount(tier))
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
				local function hash()
					local list = {}
					for name, p in c.parts(3) do
						table.insert(
							list,
							name .. "=" .. tostring(p.CFrame) .. tostring(p.Size) .. tostring(p.Color)
						)
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
							d.Changed:Connect(function()
								writes += 1
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
		local function perSlot(c)
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
			expect(ref[2] > 0 and ref[3] > 0 and ref[4] > 0).toBe(true)
			for slot = 5, 16 do
				expect(ref[slot]).toBe(0)
			end
			expect(ref[1]).toBe(0)
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
				for slot = 1, 16 do
					expect(now[slot]).toBe(ref[slot])
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
				for slot = 1, 16 do
					expect(n[slot] > 0).toBe(slot == 3 or slot == 7)
					expect(c.V2.detail(slot)).toBe(if slot == 3 or slot == 7 then "full" else "reduced")
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
					expect(v2.parts).toBe(v2.tapis + v2.plinths + v2.record + v2.pot)
					expect(c.VB.exceeded()).toBe(0)
					expect(#metrics(c.h)).toBe(0) -- aucune métrique visualBudget
					expect(v2.pot).toBe(8 + 12)
					expect(v2.tapis).toBe((20 + 14 + 10) * 3)
					if decor == 0 then
						expect(v2.plinths).toBe(18 * 2 * 3)
					else
						expect(v2.record).toBe(6 * 2 * 3)
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
end
