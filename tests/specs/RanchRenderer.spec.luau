--!nocheck
-- RanchRenderer (paquet client-world, docs/04 §13.3, §18.2, GDD §5.2, §6.6, §9.3, §12.9) : niveaux de
-- détail et budget d'animation, ranch lointain en silhouette (best.s = 0 : aucune), personnage absent
-- toléré (porté ou monture), titre au-dessus de la tête (150 studs, alias si le nom est caché),
-- étiquettes des dalles par UI/WorldText (≤ 20 studs, dalle éteinte : rien), bulle « Boîte à dodo ! »,
-- cosmétiques publics (selle, traînée, thème, drapeau), portails des autres solides, contours et
-- lumières dans leurs quotas (A23), statue de la place, zéro trace.

local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local ApiAudit = require("../harness/ApiAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 2,
			fame = 0,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 1, decor = 0, pens = 0, cozyBed = false, seen = 0 },
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

	local function sq(species, at)
		return { s = species or 1, m = 0, st = 0, z = 50, zg = 0, at = at or "pen", bf = 0, o = "", ready = 0 }
	end

	-- objet vivant par son nom (une étiquette rendue à la réserve de WorldText est désactivée)
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

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		local low = opts.low == true
		Prefs.lowGraphics = function()
			return low
		end
		h:require(base .. "Controllers.StateController").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local QC = h:require(base .. "Controllers.QualityController")
		if opts.budgets then
			local real = QC.budgets
			QC.budgets = function()
				local b = real()
				for k, v in opts.budgets do
					b[k] = v
				end
				return b
			end
		end
		if opts.world then
			opts.world(h)
		end
		local RR = h:require(base .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local c = { h = h, RR = RR, WSC = WSC, Clock = Clock, WorldLayout = WorldLayout }
		function c.snapshot(ranches, squishies)
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = 1, ranches = ranches, squishies = squishies or {} }
			)
			h:settle(1)
		end
		function c.camera(pos)
			h.workspace.CurrentCamera.CFrame = CFrame.new(pos)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				RR._step(dt)
			end
			h:settle(1)
		end
		function c.gui(name)
			return find(h.workspace, name)
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	local function speciesOfRarity(h, rarity, n)
		local Species = h:require("ReplicatedStorage.Shared.Config.Species")
		local out = {}
		for _, def in Species.List do
			if def.rarity == rarity then
				table.insert(out, def.id)
			end
		end
		local list = {}
		for i = 1, n do
			list[i] = out[(i - 1) % #out + 1]
		end
		return list
	end

	describe("RanchRenderer", function()
		it(
			"niveaux de détail : modèles dessinés, animés à pleine cadence ≤ budgets().animated, ≤ 12 pièces",
			function()
				local c = client({ budgets = { animated = 2 } })
				local list = {}
				for i, uid in { "a", "b", "c", "d", "e", "f" } do
					list[uid] = sq(1 + (i % 3))
				end
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = list })
				c.camera(c.WorldLayout.penSlot(3, 2) + Vector3.new(0, 8, -10))
				c.run(0.5)
				local st = c.RR.stats()
				expect(st.models).toBe(6)
				expect(st.fullRate <= 2).toBe(true)
				expect(st.parts <= 12 * 6).toBe(true)
				-- position dessinée à 2 studs au plus de la place (le serveur mesure depuis la place)
				for i = 1, 6 do
					local uid = ({ "a", "b", "c", "d", "e", "f" })[i]
					local p = c.RR.positionOf(3, uid)
					local best = math.huge
					for k = 1, 6 do
						local place = c.WorldLayout.penSlot(3, k)
						best = math.min(best, math.sqrt((p.X - place.X) ^ 2 + (p.Z - place.Z) ^ 2))
					end
					expect(best <= 2.01).toBe(true)
				end
				c.clean()
			end
		)

		it("ranch à plus de 220 studs : silhouette seule ; best.s = 0 : aucune silhouette", function()
			local c = client()
			c.snapshot(
				{ ["3"] = ranch(3, 1, { best = { s = 2, m = 0, z = 50, zg = 0 } }), ["5"] = ranch(5, 2) },
				{ ["3"] = { a = sq(1), b = sq(2) }, ["5"] = { c = sq(1) } }
			)
			c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
			c.run(0.6)
			expect(c.RR.stats().models >= 2).toBe(true)
			-- loin des deux ranchs
			local far = c.WorldLayout.anchor(3, "silhouette")
			c.camera(Vector3.new(-far.X, 300, -far.Z) * 3)
			c.run(0.6)
			local st = c.RR.stats()
			expect(st.models).toBe(0)
			expect(st.silhouettes).toBe(1)
			expect(c.gui("Silhouette3") ~= nil).toBe(true)
			expect(c.gui("Silhouette5")).toBe(nil)
			expect(string.find(textOf(c.gui("Silhouette3")), "×2", 1, true) ~= nil).toBe(true)
			c.clean()
		end)

		it(
			"squishy porté et monture : dessinés sur le personnage ; personnage absent : rien, sans erreur",
			function()
				local c = client()
				c.snapshot({ ["3"] = ranch(3, 1, { carry = "a" }) }, { ["3"] = { a = sq(1), b = sq(2) } })
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = CFrame.new(c.WorldLayout.penSlot(3, 3) + Vector3.new(0, 3, 0))
				c.camera(root.Position + Vector3.new(0, 6, -12))
				c.run(0.5)
				expect(c.RR.stats().models).toBe(2)
				local p = c.RR.positionOf(3, "a")
				expect(p.Y > root.Position.Y).toBe(true)
				c.h.localPlayer.Character:Destroy()
				c.h.localPlayer.Character = nil
				c.run(0.5)
				expect(c.RR.stats().models).toBe(1)
				c.clean()
			end
		)

		it(
			"titre au-dessus de la tête : 150 studs, alias si le nom est caché ; sans titre : rien",
			function()
				local c = client()
				local other = c.h:addPlayer({ userId = 2, name = "Bob" })
				c.snapshot({
					["3"] = ranch(3, 1),
					["4"] = ranch(4, 2, { title = "squishologist", hidden = true, name = "" }),
				})
				c.run(0.6)
				local gui = c.gui("Title4")
				expect(gui ~= nil).toBe(true)
				expect(gui.MaxDistance).toBe(150)
				local text = textOf(gui)
				expect(string.find(text, "Squishologist", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "Squishy Fan", 1, true) ~= nil).toBe(true)
				expect(c.gui("Title3")).toBe(nil)
				c.h:fireClient("ReplicatedStorage.Remotes.RanchPatch", {
					seq = 2,
					ranches = { ["4"] = { title = "", hidden = false, name = "Bob" } },
					ops = {},
				})
				c.h:settle(1)
				c.run(0.6)
				expect(c.gui("Title4")).toBe(nil)
				local _ = other
				c.clean()
			end
		)

		it(
			"dalles : prix et niveau par UI/WorldText (≤ 20 studs) ; dalle éteinte : aucune étiquette",
			function()
				local c = client({
					world = function(h)
						local w = folder(h.workspace, "Wobbleton")
						local ranches = folder(w, "Ranches")
						local r3 = folder(ranches, "3", "Model")
						local pads = folder(r3, "Pads")
						part(pads, "1", { Transparency = 0 })
						part(pads, "2", { Transparency = 1 })
					end,
				})
				c.snapshot({ ["3"] = ranch(3, 1) })
				c.run(0.6)
				local gui = c.gui("PadLabel1")
				expect(gui ~= nil).toBe(true)
				expect(gui.ClassName).toBe("BillboardGui")
				expect(gui.MaxDistance).toBe(20)
				local text = textOf(gui)
				expect(string.find(text, "Snack Mat", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "Lv. 2", 1, true) ~= nil).toBe(true)
				expect(c.gui("PadLabel2")).toBe(nil)
				c.clean()
			end
		)

		it("naissance au Dodo : bulle « Dodo Box! » sur la Cuve pendant 3 s", function()
			local c = client({
				world = function(h)
					local w = folder(h.workspace, "Wobbleton")
					local ranches = folder(w, "Ranches")
					local r3 = folder(ranches, "3", "Model")
					local vat = folder(r3, "Vat", "Model")
					part(vat, "Lid")
				end,
			})
			c.snapshot({ ["3"] = ranch(3, 1) })
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "hatch",
				data = {
					uid = "z",
					species = 1,
					rarity = 1,
					mutation = 0,
					oneIn = 2,
					isNew = false,
					scripted = false,
					at = "dodo",
				},
			})
			c.h:settle(1)
			c.run(0.1)
			local gui = c.gui("VatDodo")
			expect(gui ~= nil).toBe(true)
			expect(textOf(gui)).toBe("Dodo Box!")
			c.run(3.2)
			expect(c.gui("VatDodo")).toBe(nil)
			c.clean()
		end)

		it(
			"cosmétiques publics : selle et traînée sur la monture, thème, drapeau ; portails des autres solides",
			function()
				local c = client({
					world = function(h)
						local w = folder(h.workspace, "Wobbleton")
						local ranches = folder(w, "Ranches")
						for _, k in { "3", "4" } do
							local r = folder(ranches, k, "Model")
							local gate = folder(r, "Gate", "Model")
							part(gate, "Membrane", { CanCollide = false })
							local fence = folder(r, "Fence")
							part(fence, "Post1", { Color = roblox.Color3.fromRGB(255, 0, 0) })
						end
					end,
				})
				c.snapshot({
					["3"] = ranch(3, 1, {
						ride = "a",
						saddle = 1,
						saddleColor = "royal",
						trail = "stars",
						theme = "moonlit",
						flag = "day14",
					}),
					["4"] = ranch(4, 2),
				}, { ["3"] = { a = sq(1) } })
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = CFrame.new(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, 0))
				c.camera(root.Position + Vector3.new(0, 6, -12))
				c.run(0.6)
				expect(c.gui("MountTrail") ~= nil).toBe(true)
				expect(c.gui("Flag3") ~= nil).toBe(true)
				local w = c.h.workspace.Wobbleton.Ranches
				expect(w["3"].Fence.Post1.Color ~= roblox.Color3.fromRGB(255, 0, 0)).toBe(true)
				expect(w["4"].Fence.Post1.Color).toBe(roblox.Color3.fromRGB(255, 0, 0))
				expect(w["4"].Gate.Membrane.CanCollide).toBe(true)
				expect(w["3"].Gate.Membrane.CanCollide).toBe(false)
				-- thème rendu : couleur d'origine
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 2, ranches = { ["3"] = { theme = "color", flag = "" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.6)
				expect(w["3"].Fence.Post1.Color).toBe(roblox.Color3.fromRGB(255, 0, 0))
				expect(c.gui("Flag3")).toBe(nil)
				c.clean()
			end
		)

		it(
			"contours ≤ highlightQuota.ranch (+ cible) et lumières ≤ lightQuota.squishies ; qualité réduite : 0",
			function()
				local c = client()
				local list = {}
				local mythics = speciesOfRarity(c.h, 6, 5)
				local legends = speciesOfRarity(c.h, 5, 6)
				for i, s in mythics do
					list["m" .. i] = sq(s)
				end
				for i, s in legends do
					list["l" .. i] = sq(s)
				end
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = list })
				c.camera(c.WorldLayout.penSlot(3, 8) + Vector3.new(0, 10, -8))
				c.RR.highlightTarget(3, "l1")
				c.run(1)
				local st = c.RR.stats()
				expect(st.models).toBe(11)
				expect(st.highlights <= 3 + 1).toBe(true)
				expect(st.highlights >= 3).toBe(true)
				expect(st.lights <= 4).toBe(true)
				local c2 = client({ budgets = { highlightQuota = { target = 1, chase = 6, ranch = 0 } } })
				c2.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = list })
				c2.camera(c2.WorldLayout.penSlot(3, 8) + Vector3.new(0, 10, -8))
				c2.run(1)
				expect(c2.RR.stats().highlights).toBe(0)
				c.clean()
				c2.clean()
			end
		)

		it("API Roblox valide (ApiAudit) : squishies, monture, titres, contours, lumières", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = client()
				c.h:addPlayer({ userId = 2, name = "Bob" })
				local list = {}
				for i, s in speciesOfRarity(c.h, 6, 3) do
					list["m" .. i] = sq(s)
				end
				for i, s in speciesOfRarity(c.h, 5, 3) do
					list["l" .. i] = sq(s)
				end
				list.a = sq(1)
				c.snapshot({
					["3"] = ranch(3, 1, {
						ride = "a",
						saddle = 2,
						saddleColor = "royal",
						trail = "stars",
						flag = "day14",
						best = { s = 1, m = 0, z = 900, zg = 0 },
					}),
					["4"] = ranch(4, 2, { title = "dex_master" }),
				}, { ["3"] = list })
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = CFrame.new(c.WorldLayout.penSlot(3, 4) + Vector3.new(0, 8, 0))
				c.camera(root.Position + Vector3.new(0, 6, -12))
				c.RR.highlightTarget(3, "m1")
				c.RR.pulseTwins("m1")
				c.RR.play(3, "l1", "perfect")
				c.run(1)
				c.clean()
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)

		it("statue de la place : modèle et étiquette depuis les attributs du serveur", function()
			local c = client({
				world = function(h)
					local w = folder(h.workspace, "Wobbleton")
					local plaza = folder(w, "Plaza")
					local statue = part(plaza, "Statue", { Size = Vector3.new(6, 6, 6) })
					statue:SetAttribute("StatueSpecies", 2)
					statue:SetAttribute("StatueMutation", 0)
					statue:SetAttribute("StatueSize", 1500)
					statue:SetAttribute("StatueName", "Mira")
				end,
			})
			c.snapshot({ ["3"] = ranch(3, 1) })
			c.run(0.6)
			local gui = c.gui("StatueLabel")
			expect(gui ~= nil).toBe(true)
			expect(string.find(textOf(gui), "Mira", 1, true) ~= nil).toBe(true)
			c.clean()
		end)

		-- lot B4, étape 5 (bug trouvé par les captures du groupe « world ») : la pièce de la statue
		-- remplacée (place reconstruite) rendait son étiquette à la réserve de WorldText ; RanchRenderer
		-- gardait cette étiquette morte (setText sans effet, ou pire : écrit sur l'étiquette d'un autre
		-- objet qui l'avait reprise) et la nouvelle statue n'avait plus de texte
		it(
			"statue remplacée : la nouvelle pièce a son étiquette, aucune étiquette d'un autre n'est écrite",
			function()
				local c = client({
					world = function(h)
						local w = folder(h.workspace, "Wobbleton")
						local plaza = folder(w, "Plaza")
						local statue = part(plaza, "Statue", { Size = Vector3.new(6, 6, 6) })
						statue:SetAttribute("StatueSpecies", 2)
						statue:SetAttribute("StatueSize", 1500)
						statue:SetAttribute("StatueName", "Mira")
					end,
				})
				c.snapshot({ ["3"] = ranch(3, 1) })
				c.run(0.6)
				expect(c.gui("StatueLabel") ~= nil).toBe(true)
				local plaza = c.h.workspace.Wobbleton.Plaza
				plaza.Statue:Destroy()
				c.run(0.6)
				-- une autre étiquette du monde reprend l'étiquette rendue à la réserve
				local WorldText = c.h:require("StarterPlayer.StarterPlayerScripts.Client.UI.WorldText")
				local other = WorldText.create(
					part(c.h.workspace, "Other"),
					{ kind = "text", maxDistance = 50, name = "OtherLabel" }
				)
				WorldText.setText(other, "Autre")
				local statue = part(plaza, "Statue", { Size = Vector3.new(6, 6, 6) })
				statue:SetAttribute("StatueSpecies", 0)
				c.run(0.6)
				local gui = c.gui("StatueLabel")
				expect(gui ~= nil).toBe(true)
				expect(gui.Adornee).toBe(statue)
				expect(textOf(gui)).toBe("Biggest squishy")
				expect(textOf(other)).toBe("Autre")
				c.clean()
			end
		)
		-- Lot B4, étape 6 (trouvé par les 6 h de robots de RanchRenderer_v2) : même défaut que la statue
		-- (B4-62) pour le titre d'un joueur qui part (sa tête détruite rend l'étiquette à la réserve de
		-- WorldText) et pour l'étiquette d'une silhouette dont le meilleur squishy change d'espèce
		it(
			"titre d'un joueur parti : l'étiquette reprise par un autre objet n'est ni rendue ni écrite ; au retour, un titre neuf",
			function()
				local c = client()
				local bob = c.h:addPlayer({ userId = 2, name = "Bob" })
				c.snapshot({ ["3"] = ranch(3, 1), ["4"] = ranch(4, 2, { title = "squishologist" }) })
				c.run(0.6)
				expect(c.gui("Title4") ~= nil).toBe(true)
				-- Bob part : sa tête est détruite, son étiquette revient à la réserve ; une autre étiquette
				-- du monde la reprend aussitôt
				c.h:removePlayer(bob)
				local WorldText = c.h:require("StarterPlayer.StarterPlayerScripts.Client.UI.WorldText")
				local other = WorldText.create(
					part(c.h.workspace, "Other"),
					{ kind = "text", maxDistance = 50, name = "OtherLabel" }
				)
				WorldText.setText(other, "Autre")
				c.run(0.6)
				expect(other.Enabled).toBe(true)
				expect(other.Name).toBe("OtherLabel")
				expect(other.Adornee).toBe(c.h.workspace.Other)
				expect(textOf(other)).toBe("Autre")
				-- Bob revient : un titre neuf sur sa nouvelle tête, l'autre étiquette intacte
				local back = c.h:addPlayer({ userId = 2, name = "Bob" })
				c.run(0.6)
				local gui = c.gui("Title4")
				expect(gui ~= nil and gui ~= other).toBe(true)
				expect(gui.Adornee).toBe(back.Character.Head)
				expect(string.find(textOf(gui), "Squishologist", 1, true) ~= nil).toBe(true)
				expect(textOf(other)).toBe("Autre")
				c.clean()
			end
		)

		it(
			"silhouette : le meilleur squishy change d'espèce, l'étiquette suit le nouveau modèle ; jamais celle d'un autre",
			function()
				local c = client()
				c.snapshot({ ["3"] = ranch(3, 1, { best = { s = 2, m = 0, z = 50, zg = 0 } }) })
				local far = c.WorldLayout.anchor(3, "silhouette")
				c.camera(Vector3.new(-far.X, 300, -far.Z) * 3)
				c.run(0.6)
				local first = c.gui("Silhouette3")
				expect(first ~= nil).toBe(true)
				local oldBody = first.Adornee
				expect(oldBody ~= nil).toBe(true)
				-- nouveau meilleur squishy d'une autre espèce : nouveau modèle
				c.h:fireClient("ReplicatedStorage.Remotes.RanchPatch", {
					seq = 2,
					ranches = { ["3"] = { best = { s = 5, m = 0, z = 80, zg = 0 } } },
					ops = {},
				})
				c.h:settle(1)
				c.run(0.6)
				local labels = {}
				for _, d in c.h.workspace:GetDescendants() do
					if d.ClassName == "BillboardGui" and d.Name == "Silhouette3" and d.Enabled then
						table.insert(labels, d)
					end
				end
				expect(#labels).toBe(1)
				local body = labels[1].Adornee
				expect(body ~= nil and body ~= oldBody).toBe(true)
				expect(body:IsDescendantOf(c.h.workspace)).toBe(true)
				c.clean()
			end
		)

		-- Revue client-world : la pression de pet-sitting (Celebrate press, petsit = true) écrase le
		-- squishy de l'AMI (à sa clôture), pas un squishy de mon ranch
		it("pression de pet-sitting : le squishy de l'ami à sa clôture joue son écrasement", function()
			local c = client()
			c.snapshot(
				{ ["3"] = ranch(3, 1), ["5"] = ranch(5, 2) },
				{ ["3"] = { a = sq(1) }, ["5"] = { f1 = sq(2) } }
			)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Fence",
				{ slot = 5, uids = { "f1" }, reason = "petsit" }
			)
			c.h:settle(1)
			c.camera(c.WorldLayout.fencePoint(5, 1) + Vector3.new(0, 6, -8))
			c.run(0.5)
			local Squash = c.h:require("ReplicatedStorage.Shared.Render.Squash")
			local real = Squash.sample
			local seen = {}
			Squash.sample = function(profile, ...)
				seen[profile] = true
				return real(profile, ...)
			end
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "press",
				data = { uid = "f1", coins = 3, perfect = false, streak = 0, petsit = true },
			})
			c.h:settle(1)
			c.run(0.1)
			expect(seen.press).toBe(true)
			c.clean()
		end)

		-- Revue client-world (budget PS4) : un ranch lointain (silhouette seule) ne calcule plus la place
		-- ni la taille de ses squishies à chaque image
		it("ranch lointain : aucune taille ni place calculée pour ses squishies à chaque image", function()
			local c = client()
			local list = {}
			for i = 1, 20 do
				list["p" .. i] = sq(1)
			end
			c.snapshot(
				{ ["3"] = ranch(3, 1), ["11"] = ranch(11, 2) },
				{ ["3"] = { a = sq(1) }, ["11"] = list }
			)
			c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
			c.run(0.5)
			local far = (c.WorldLayout.anchor(11, "silhouette") - c.WorldLayout.penSlot(3, 1)).Magnitude
			expect(far > 260).toBe(true)
			local real = c.WSC.sizeOf
			local calls = 0
			c.WSC.sizeOf = function(slot, uid, t)
				if slot == 11 then
					calls += 1
				end
				return real(slot, uid, t)
			end
			for _ = 1, 10 do
				c.RR._step(1 / 60)
			end
			expect(calls).toBe(0)
			c.WSC.sizeOf = real
			c.clean()
		end)
		-- Revue client-world : une donnée abîmée dans UN ranch ne fige pas tout le monde (le pas de
		-- chaque ranch est isolé ; l'image se termine, BulkMoveTo et stats compris)
		it("un ranch qui lève ne fige pas les autres : l'image se termine", function()
			local c = client()
			c.snapshot(
				{ ["3"] = ranch(3, 1), ["5"] = ranch(5, 2) },
				{ ["3"] = { a = sq(1) }, ["5"] = { x = sq(1) } }
			)
			c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
			local real = c.WSC.sizeOf
			c.WSC.sizeOf = function(slot, uid, t)
				if slot == 5 then
					error("donnée abîmée (simulée)")
				end
				return real(slot, uid, t)
			end
			c.run(0.5)
			c.WSC.sizeOf = real
			expect(c.RR.stats().models >= 1).toBe(true)
			local p = c.RR.positionOf(3, "a")
			expect(p ~= nil).toBe(true)
			expect(
				(Vector3.new(p.X, 0, p.Z) - Vector3.new(
					c.WorldLayout.penSlot(3, 1).X,
					0,
					c.WorldLayout.penSlot(3, 1).Z
				)).Magnitude <= 2.01
			).toBe(true)
			expect(#c.h.errors).toBe(1) -- signalée une fois, puis effacée par le test
			table.clear(c.h.errors)
			c.clean()
		end)

		-- Lot B5, étape 1 (journal B5-8) : défaut de la v1.3 trouvé en reliant les selles de la v2.0. Le
		-- modèle de la monture était construit sans sa pièce de selle (BuildSpec.saddle jamais passé) :
		-- setSaddleColor ne coloriait rien, aucune selle n'était visible (GDD §2 « une selle apparaît »,
		-- §5.4 selles) ; et un modèle rendu puis reconstruit en selle perdait sa traînée
		it(
			"monture : la pièce de selle est dessinée, à la couleur de la selle choisie (classique : couleur du ranch) ; modèle reconstruit en selle : selle et traînée reviennent ; pied à terre : ni selle ni traînée",
			function()
				local c = client()
				local Cosmetics = c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				c.snapshot({
					["3"] = ranch(3, 1, { ride = "a", saddle = 1, saddleColor = "royal", trail = "stars" }),
				}, { ["3"] = { a = sq(1), b = sq(2) } })
				local character = c.h.localPlayer.Character
				local root = character.HumanoidRootPart
				root.CFrame = CFrame.new(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, 0))
				c.camera(root.Position + Vector3.new(0, 6, -12))
				c.run(0.6)
				local function saddle(uid)
					local handle = c.RR.handleOf(3, uid)
					return handle and handle.model:FindFirstChild("Saddle")
				end
				local function trails()
					local n = 0
					for _, d in c.h.workspace:GetDescendants() do
						if d.Name == "MountTrail" then
							n += 1
						end
					end
					return n
				end
				expect(saddle("a") ~= nil).toBe(true)
				expect(saddle("a").Color).toBe(Cosmetics.ByKindId["saddle:royal"].color)
				expect(saddle("a").Transparency).toBe(0)
				expect(saddle("b")).toBeNil() -- seul le squishy monté porte une selle
				expect(#c.RR.handleOf(3, "a").parts <= 12).toBe(true)
				expect(trails()).toBe(1)
				-- selle classique : couleur du ranch
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 2, ranches = { ["3"] = { saddleColor = "" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.2)
				expect(saddle("a").Color).toBe(Cosmetics.RanchColors[3])
				-- le personnage disparaît un instant (réapparition) : modèle rendu, puis reconstruit en selle
				root.Parent = nil
				c.run(0.2)
				expect(c.RR.handleOf(3, "a")).toBeNil()
				expect(trails()).toBe(0)
				root.Parent = character
				c.run(0.2)
				expect(saddle("a") ~= nil).toBe(true)
				expect(saddle("a").Color).toBe(Cosmetics.RanchColors[3])
				expect(trails()).toBe(1)
				-- pied à terre : le squishy retrouve sa place sans selle ni traînée
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 3, ranches = { ["3"] = { ride = "" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.2)
				expect(c.RR.handleOf(3, "a") ~= nil).toBe(true)
				expect(saddle("a")).toBeNil()
				expect(trails()).toBe(0)
				expect(c.RR.stats().models).toBe(2)
				-- en selle de nouveau : la selle revient
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 4, ranches = { ["3"] = { ride = "a", saddleColor = "royal" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.2)
				expect(saddle("a").Color).toBe(Cosmetics.ByKindId["saddle:royal"].color)
				expect(trails()).toBe(1)
				c.clean()
			end
		)

		-- Lot B5, étape 1 (journal B5-9) : second défaut de la v1.3 trouvé avec les tenues de la v2.0. Le
		-- modèle d'un squishy dessiné gardait l'aspect de sa construction : une tenue mise ou retirée,
		-- une mutation ou des étoiles changées dans le miroir ne se voyaient qu'après une reconstruction
		-- (s'éloigner de 220 studs et revenir)
		it(
			"squishy dessiné dont la tenue, la mutation ou les étoiles changent dans le miroir : le modèle suit ; une pression (autre champ) ne reconstruit rien",
			function()
				local c = client()
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = { a = sq(1), b = sq(2) } })
				c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
				c.run(0.5)
				local seq = 1
				local function update(uid, species, fields)
					local rec = sq(species)
					for k, v in fields do
						rec[k] = v
					end
					seq += 1
					c.h:fireClient("ReplicatedStorage.Remotes.RanchPatch", {
						seq = seq,
						ranches = {},
						ops = { { slot = 3, op = "update", uid = uid, rec = rec } },
					})
					c.h:settle(1)
					c.run(0.1)
				end
				local function outfit(uid)
					local handle = c.RR.handleOf(3, uid)
					return handle and handle.model:FindFirstChild("Outfit")
				end
				local function stars(uid)
					local gui = c.RR.handleOf(3, uid).body:FindFirstChild("Stars")
					local n = 0
					if gui and gui.Enabled then
						for i = 1, 5 do
							local ray = gui:FindFirstChild("Star" .. i .. "Ray1")
							if ray and ray.Visible then
								n += 1
							end
						end
					end
					return n
				end
				local first = c.RR.handleOf(3, "a")
				local other = c.RR.handleOf(3, "b")
				expect(outfit("a")).toBeNil()
				expect(stars("a")).toBe(0)
				-- une pression : `ready` change, rien d'autre : le même modèle reste
				update("a", 1, { ready = T0 + 8 })
				expect(c.RR.handleOf(3, "a")).toBe(first)
				-- tenue de la v1.3, puis de la v2.0, puis retirée
				update("a", 1, { o = "sweater" })
				expect(outfit("a") ~= nil).toBe(true)
				local sweater = outfit("a").Color
				update("a", 1, { o = "partyHat" })
				expect(outfit("a") ~= nil).toBe(true)
				expect(outfit("a").Color ~= sweater).toBe(true)
				update("a", 1, { o = "" })
				expect(outfit("a")).toBeNil()
				-- étoiles : même modèle, l'arc suit
				local kept = c.RR.handleOf(3, "a")
				update("a", 1, { st = 3 })
				expect(c.RR.handleOf(3, "a")).toBe(kept)
				expect(stars("a")).toBe(3)
				update("a", 1, { st = 5 })
				expect(stars("a")).toBe(5)
				-- mutation : l'aspect de la mutation, les étoiles gardées
				update("a", 1, { st = 5, m = 2 })
				expect(c.RR.handleOf(3, "a").spec.mutation).toBe(2)
				expect(stars("a")).toBe(5)
				-- l'autre squishy n'a jamais été touché
				expect(c.RR.handleOf(3, "b")).toBe(other)
				expect(c.RR.stats().models).toBe(2)
				c.clean()
			end
		)

		-- v2.0 (lot B5, étape 1, INT-B5-RANCH ; plan B5 D3) : crochets des personnalités. L'interrupteur
		-- Personalities n'arrive au client que par EventState.features.v2 (World/Flags)
		it(
			"personnalités (lot B5) : interrupteur coupé, Personality.pose et forget jamais appelés ; ouvert : pose appelée seulement pour les squishies dessinés, une fois par image, après leur pose de repos ; positionOf et projected lisent toujours la pose de repos",
			function()
				local c = client()
				local P = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Personality")
				local calls, forgets = {}, {}
				local shift = Vector3.zero
				local realPose, realForget = P.pose, P.forget
				P.pose = function(d, h, rec, where, base, cf, now)
					table.insert(
						calls,
						{ slot = d.slot, uid = d.uid, handle = h, where = where, rest = cf.Position }
					)
					expect(typeof(base)).toBe("Vector3")
					expect(type(now)).toBe("number")
					expect(type(rec)).toBe("table")
					return realPose(d, h, rec, where, base, cf, now) + shift
				end
				P.forget = function(slot, uid)
					table.insert(forgets, slot .. ":" .. uid)
					return realForget(slot, uid)
				end
				local far = {}
				for i = 1, 6 do
					far["p" .. i] = sq(1)
				end
				c.snapshot(
					{ ["3"] = ranch(3, 1), ["11"] = ranch(11, 2) },
					{ ["3"] = { a = sq(1), b = sq(2), c = sq(3, "pool") }, ["11"] = far }
				)
				c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
				c.run(1)
				expect(c.RR.stats().models).toBe(3)
				-- coupé (configuration livrée) : aucun appel
				expect(P.active()).toBe(false)
				expect(#calls).toBe(0)
				expect(#forgets).toBe(0)
				for _, uid in { "a", "b", "c" } do
					expect(c.RR.handleOf(3, uid) ~= nil).toBe(true)
				end
				expect(c.RR.handleOf(11, "p1")).toBeNil() -- ranch lointain : pas dessiné
				expect(c.RR.handleOf(3, "zz")).toBeNil()
				for _, bad in { { nil, "a" }, { 3, nil }, { "3", "a" }, { 3, 5 }, { 0 / 0, "a" } } do
					expect(c.RR.handleOf(bad[1], bad[2])).toBeNil()
				end
				-- ouvert par le serveur
				c.h:fireClient(
					"ReplicatedStorage.Remotes.EventState",
					UpgradeScreen.eventState({ Personalities = true })
				)
				c.h:settle(1)
				expect(P.active()).toBe(true)
				c.RR._step(0)
				-- une image : un appel par squishy dessiné du ranch proche, avec son modèle
				expect(#calls).toBe(3)
				local seen = {}
				for _, call in calls do
					expect(call.slot).toBe(3)
					expect(seen[call.uid]).toBeNil()
					seen[call.uid] = true
					expect(call.handle).toBe(c.RR.handleOf(3, call.uid))
					-- la pose de repos passée est celle que lit le ciblage
					expect(call.rest).toBe(c.RR.positionOf(3, call.uid))
				end
				expect(seen.a and seen.b and seen.c).toBe(true)
				-- caméra de projection (la caméra simulée ne projette pas : une projection simple et fixe
				-- suffit, la question est de savoir QUELLE position RanchRenderer lui donne)
				local cam = {
					FieldOfView = 70,
					ViewportSize = roblox.Vector2.new(1920, 1080),
					WorldToViewportPoint = function(_, p)
						return Vector3.new(960 + p.X * 3, 540 - p.Y * 3, 20 + p.Z * 0.01), true
					end,
				}
				local function projected()
					local out = {}
					for _, e in c.RR.projected(cam) do
						out[e.id] = e
					end
					return out
				end
				local rest, screen = {}, projected()
				expect(screen.a ~= nil and screen.b ~= nil).toBe(true)
				for _, uid in { "a", "b", "c" } do
					rest[uid] = c.RR.positionOf(3, uid)
				end
				-- une saynète déplace le modèle (ici de 1,5 stud de côté et 3 studs en hauteur)…
				shift = Vector3.new(1.5, 3, 0)
				table.clear(calls)
				c.RR._step(0)
				expect(#calls).toBe(3)
				local after = projected()
				for _, uid in { "a", "b", "c" } do
					local body = c.RR.handleOf(3, uid).body
					local drawn = body.Position - Vector3.new(0, body.Size.Y / 2, 0)
					expect({ uid, (drawn - (rest[uid] + shift)).Magnitude < 1e-3 }).toEqual({ uid, true })
					-- … mais ni la position de la cible ni la projection du clic ne bougent
					expect({ uid, c.RR.positionOf(3, uid) }).toEqual({ uid, rest[uid] })
					expect({ uid, after[uid] ~= nil }).toEqual({ uid, screen[uid] ~= nil })
					if screen[uid] then
						expect({ uid, after[uid].screen }).toEqual({ uid, screen[uid].screen })
						expect({ uid, after[uid].radius }).toEqual({ uid, screen[uid].radius })
					end
				end
				shift = Vector3.zero
				-- une erreur dans une saynète : la pose de repos est dessinée, signalée une fois
				P.pose = function()
					error("saynète abîmée (simulée)")
				end
				c.RR._step(0)
				for _, uid in { "a", "b", "c" } do
					local body = c.RR.handleOf(3, uid).body
					local drawn = body.Position - Vector3.new(0, body.Size.Y / 2, 0)
					expect({ uid, (drawn - rest[uid]).Magnitude < 1e-3 }).toEqual({ uid, true })
				end
				c.h:settle(1)
				expect(#c.h.errors).toBe(1)
				table.clear(c.h.errors)
				P.pose = function(d, h, rec, where, base, cf, now)
					table.insert(calls, { slot = d.slot, uid = d.uid })
					return realPose(d, h, rec, where, base, cf, now)
				end
				-- modèles rendus (caméra au loin) : forget pour chacun
				table.clear(calls)
				local away = c.WorldLayout.anchor(3, "silhouette")
				c.camera(Vector3.new(-away.X, 300, -away.Z) * 3)
				c.run(0.2)
				expect(c.RR.stats().models).toBe(0)
				table.sort(forgets)
				expect(table.concat(forgets, ",")).toBe("3:a,3:b,3:c")
				expect(#calls).toBe(0)
				-- recoupé en direct : plus aucun appel, même pour des modèles dessinés puis rendus
				c.camera(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, -10))
				c.run(0.5)
				expect(c.RR.stats().models).toBe(3)
				expect(#calls > 0).toBe(true)
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", UpgradeScreen.eventState(nil))
				c.h:settle(1)
				expect(P.active()).toBe(false)
				table.clear(calls)
				table.clear(forgets)
				c.run(0.5)
				c.camera(Vector3.new(-away.X, 300, -away.Z) * 3)
				c.run(0.2)
				expect(#calls).toBe(0)
				expect(#forgets).toBe(0)
				P.pose, P.forget = realPose, realForget
				c.clean()
			end
		)
	end)

	-- v2.0 (lot B5, étape 1 ; plan B5 D12 ; consigne du propriétaire (2c)) : les cosmétiques de la v2.0
	-- (Cosmetics.ListV2 et rotation de la semaine) se VOIENT en jeu. Selles, traînées et drapeaux : couleurs
	-- du lot B4 (D19b) ; tenues et selle d'un modèle construit seul : lot B5 (Render/SquishyBuilder).
	describe("RanchRenderer › cosmétiques de la v2.0 portés en jeu (lot B5, D12)", function()
		it(
			"chaque selle, traînée, drapeau et tenue de la v2.0 a son aspect en jeu, différent du repli et des autres ; la selle a la couleur d'un modèle construit seul ; identifiant inconnu : le repli d'aujourd'hui, sans trace",
			function()
				local c = client()
				local Cosmetics = c.h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				local SB = c.h:require("ReplicatedStorage.Shared.Render.SquishyBuilder")
				local Color3 = roblox.Color3
				local function ids(kind)
					local out = {}
					for _, list in { Cosmetics.ListV2, Cosmetics.WeeklyRotation } do
						for _, def in list do
							if def.kind == kind then
								table.insert(out, def.id)
							end
						end
					end
					return out
				end
				local saddles, trails, flags, outfits =
					ids("saddle"), ids("trail"), ids("flag"), ids("outfit")
				expect({ #saddles, #trails, #flags, #outfits }).toEqual({ 9, 7, 4, 4 })
				c.snapshot(
					{ ["3"] = ranch(3, 1, { ride = "a", saddle = 1 }) },
					{ ["3"] = { a = sq(1), b = sq(2) } }
				)
				local root = c.h.localPlayer.Character.HumanoidRootPart
				root.CFrame = CFrame.new(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 8, 0))
				c.camera(root.Position + Vector3.new(0, 6, -12))
				c.run(0.6)
				local seq = 1
				local function patch(fields, ops)
					seq += 1
					c.h:fireClient(
						"ReplicatedStorage.Remotes.RanchPatch",
						{ seq = seq, ranches = if fields then { ["3"] = fields } else {}, ops = ops or {} }
					)
					c.h:settle(1)
					c.run(0.6)
				end
				local function distinct(seen, key, id)
					expect({ id, seen[key] }).toEqual({ id, nil })
					seen[key] = id
				end

				-- selles : sur la monture
				local ranchColor = Cosmetics.RanchColors[3]
				local function saddle()
					return c.RR.handleOf(3, "a").model:FindFirstChild("Saddle").Color
				end
				expect(saddle()).toBe(ranchColor)
				local seen = {}
				for _, id in saddles do
					patch({ saddleColor = id })
					local color = saddle()
					expect({ id, color ~= ranchColor }).toEqual({ id, true })
					distinct(seen, tostring(color), id)
					local alone = SB.build({
						species = 1,
						mutation = 0,
						stars = 0,
						displayScale = 1,
						lod = 1,
						saddle = id,
					})
					expect({ id, alone.model:FindFirstChild("Saddle").Color }).toEqual({ id, color })
					SB.release(alone)
				end
				patch({ saddleColor = "nope" })
				expect(saddle()).toBe(ranchColor)

				-- traînées : sur la monture
				local PINK = roblox.ColorSequence.new(Color3.fromRGB(255, 220, 240))
				local function trail()
					local found = find(c.h.workspace, "MountTrail")
					return found and found.Color
				end
				seen = {}
				for _, id in trails do
					patch({ trail = id })
					local color = trail()
					expect({ id, color ~= nil and color ~= PINK }).toEqual({ id, true })
					distinct(seen, tostring(color), id)
				end
				patch({ trail = "nope" })
				expect(trail()).toBe(PINK)

				-- drapeaux : à côté du portail
				local WHITE = Color3.fromRGB(255, 255, 255)
				local function flag()
					local found = find(c.h.workspace, "Flag3")
					return found and found.Cloth.Color
				end
				seen = {}
				for _, id in flags do
					patch({ flag = id })
					local color = flag()
					expect({ id, color ~= nil and color ~= WHITE }).toEqual({ id, true })
					distinct(seen, tostring(color), id)
				end
				patch({ flag = "nope" })
				expect(flag()).toBe(WHITE)

				-- tenues : sur un squishy de l'enclos, mises pendant qu'il est dessiné
				local function wear(id)
					local rec = sq(2)
					rec.o = id
					patch(nil, { { slot = 3, op = "update", uid = "b", rec = rec } })
					return c.RR.handleOf(3, "b").model:FindFirstChild("Outfit")
				end
				seen = {}
				for _, id in outfits do
					local part = wear(id)
					expect({ id, part ~= nil }).toEqual({ id, true })
					expect(part.Transparency).toBe(0)
					distinct(seen, tostring(part.Color) .. tostring(part.Size), id)
				end
				expect(wear("nope")).toBeNil()
				expect(wear("")).toBeNil()
				expect(c.RR.stats().models).toBe(2)
				c.clean()
			end
		)
	end)
end
