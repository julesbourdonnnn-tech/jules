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
	end)
end
