--!nocheck
-- Controllers/HelperRenderer et Render/HelperKit (lot B5, étape 3 ; GDD §4.28 ; docs/04 §27.5, §27.10
-- « atterrissage à tPress » ; plan B5 D14 à D16, D29, D30) : les Plopettes dessinées, derrière
-- l'interrupteur Helpers (attributs Helpers et HelperMode des ranchs, posés par HelperService).
-- Monde fabriqué (modèles Wobbleton/Ranches/<k> comme ceux du serveur), horloge figée, zéro trace
-- (ZeroLog), hasard à graine fixe. Tout est en 3D : ces cas prouvent la structure (instances, pièces,
-- couleurs, positions, heures d'atterrissage, budgets) ; personne n'a pu regarder les Plopettes.

local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local T0 = 1796724120
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local REMOTES = "ReplicatedStorage.Remotes."
local UIDS = { "a", "b", "c", "d", "e", "f", "g", "h" }

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 12,
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
	end

	local function sq(ready)
		return { s = 1, m = 0, st = 0, z = 50, zg = 0, at = "pen", bf = 0, o = "", ready = ready or 0 }
	end

	local function folder(parent, name, class)
		local f = parent:FindFirstChild(name)
		if f == nil then
			f = MockInstance.new(class or "Folder")
			f.Name = name
			f.Parent = parent
		end
		return f
	end

	-- Client du rendu : miroir, RanchRenderer, HelperRenderer ; `mine` = mon ranch (joueur 1), les autres
	-- ranchs appartiennent aux joueurs 100 + k ; 8 squishies dans chaque enclos
	local function client(opts)
		opts = opts or {}
		local mine = opts.mine or 3
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:require(CLIENT .. "Util.Prefs").Init()
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local models = {}
		local list = folder(folder(h.workspace, "Wobbleton"), "Ranches")
		for slot = 1, 16 do
			models[slot] = folder(list, tostring(slot), "Model")
			models[slot]:SetAttribute("Slot", slot)
		end
		local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local HR = h:require(CLIENT .. "Controllers.HelperRenderer")
		HR.Init()
		HR.Start()
		local c = {
			h = h,
			RR = RR,
			HR = HR,
			WSC = WSC,
			Clock = Clock,
			models = models,
			mine = mine,
			seq = 1,
			sounds = {},
			drops = {},
			presses = {},
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			VB = h:require(CLIENT .. "Render.VisualBudget"),
			Kit = h:require(CLIENT .. "Render.HelperKit"),
			WT = h:require(CLIENT .. "UI.WorldText"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
		}
		HR._configure({
			play = function(name)
				table.insert(c.sounds, name)
			end,
			drops = function(pos, color, n)
				table.insert(c.drops, { pos = pos, color = color, n = n })
			end,
			press = function(slot, uid)
				table.insert(c.presses, slot .. ":" .. uid)
			end,
		})
		function c.owner(slot)
			return if slot == mine then 1 else 100 + slot
		end
		function c.world(over)
			local ranches, squishies = {}, {}
			for slot = 1, 16 do
				ranches[tostring(slot)] = ranch(slot, c.owner(slot))
				local s = {}
				for _, uid in UIDS do
					s[uid] = sq()
				end
				squishies[tostring(slot)] = s
			end
			if over then
				over(ranches, squishies)
			end
			c.seq += 1
			h:fireClient(
				REMOTES .. "RanchSnapshot",
				{ seq = c.seq, ranches = ranches, squishies = squishies }
			)
			h:settle(1)
		end
		function c.attrs(slot, attrs)
			for k, v in attrs do
				models[slot]:SetAttribute(k, v)
			end
			h:settle(1)
		end
		function c.unset(slot, names)
			for _, k in names do
				models[slot]:SetAttribute(k, nil)
			end
			h:settle(1)
		end
		-- une image complète : l'horloge avance, puis RenderStepped
		function c.frame(dt)
			Clock.advance(dt)
			h.game.RunService.RenderStepped:Fire(dt)
		end
		function c.play(seconds, fps)
			local dt = 1 / (fps or 60)
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				c.frame(dt)
			end
			h:settle(1)
		end
		-- images de 1/60 s jusqu'à `t` exactement (la dernière image tombe sur t)
		function c.untilT(t)
			while Clock.now() + 1 / 60 < t do
				c.frame(1 / 60)
			end
			c.frame(t - Clock.now())
			h:settle(1)
		end
		function c.press(slot, presses)
			h:fireClient(REMOTES .. "HelperPress", { ownerId = c.owner(slot), presses = presses })
			h:settle(1)
		end
		function c.raw(payload)
			h:fireClient(REMOTES .. "HelperPress", payload)
			h:settle(1)
		end
		-- le miroir montre la pression : `ready` posé à `readyAt`
		function c.ready(slot, uid, readyAt)
			c.seq += 1
			h:fireClient(REMOTES .. "RanchPatch", {
				seq = c.seq,
				ranches = {},
				ops = { { op = "update", slot = slot, uid = uid, rec = sq(readyAt) } },
			})
			h:settle(1)
		end
		function c.me(pos)
			if h.localPlayer.Character == nil then
				h:respawn(h.localPlayer)
			end
			h:moveTo(h.localPlayer, pos + Vector3.new(0, 3, 0))
		end
		function c.state(slot, k)
			return HR._state(slot, k)
		end
		-- distance d'atterrissage attendue depuis le centre du squishy : 1,2 studs, ou son rayon + 0,6
		function c.beside(center)
			return math.max(1.2, center.Y - c.WL.groundY(center.X, center.Z) + 0.6)
		end
		function c.flat(a, b)
			return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
		end
		function c.helpersFolder()
			local root = h.workspace:FindFirstChild("ClientWorld")
			return root and root:FindFirstChild("Helpers")
		end
		function c.drawnModels()
			local f = c.helpersFolder()
			return if f then #f:GetChildren() else 0
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		c.world()
		return c
	end

	-- client avec Helpers posés sur `slot` et une image jouée (détail lu)
	local function withHelpers(opts, slot, n, mode)
		local c = client(opts)
		c.attrs(slot, { Helpers = n, HelperMode = mode or "active" })
		c.play(0.1)
		return c
	end

	describe("HelperRenderer › interrupteur et état (lot B5, étape 3)", function()
		it(
			"interrupteur coupé (aucun attribut) : aucune instance, aucune connexion par image, HelperPress sans effet ; 16 écoutes d'attributs seulement",
			function()
				local c = client()
				local before = c.h:counts().connections
				c.play(2)
				c.press(3, { { helper = 1, uid = "a", tPress = c.Clock.now() + 1 } })
				c.play(1)
				local s = c.HR.stats()
				expect({ s.connections, s.drawn, s.ranches, s.jumps, s.messages }).toEqual({ 0, 0, 0, 0, 0 })
				expect(c.helpersFolder()).toBeNil()
				expect(c.VB.declared("helpers")).toBe(false)
				expect(c.h:counts().connections).toBe(before)
				expect(#c.sounds + #c.drops + #c.presses).toBe(0)
				c.clean()
			end
		)

		it(
			"les 6 recettes : 5 pièces au plus, ancrées, sans collision ni requête ni toucher ni ombre",
			function()
				local c = withHelpers(nil, 3, 6)
				local names = {}
				for k = 1, 6 do
					local st = c.state(3, k)
					expect(st.drawn).toBe(true)
					expect(#st.parts <= 5).toBe(true)
					table.insert(names, st.model.Name)
					for _, p in st.parts do
						expect({ k, p.Name, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow }).toEqual({
							k,
							p.Name,
							true,
							false,
							false,
							false,
							false,
						})
						expect(p.Size.Y <= 1).toBe(true)
					end
				end
				expect(names).toEqual({
					"Plopette_Pip",
					"Plopette_Pop",
					"Plopette_Pim",
					"Plopette_Pom",
					"Plopette_Puff",
					"Plopette_Plume",
				})
				expect(c.Kit.recipe(0)).toBeNil()
				expect(c.Kit.recipe(7)).toBeNil()
				c.clean()
			end
		)

		it(
			"Helpers 0 → 6 → 0 : rangée devant la porte de la maisonnette, budget « helpers » pris puis rendu, connexions coupées",
			function()
				local c = withHelpers(nil, 3, 1)
				expect(c.HR.stats().drawn).toBe(1)
				for n = 2, 6 do
					c.attrs(3, { Helpers = n })
					c.play(0.05)
					expect(c.HR.stats().drawn).toBe(n)
					expect(c.VB.used("helpers")).toBe(n * 5)
				end
				local door = c.WL.helperHouse(3)
				for k = 1, 6 do
					local st = c.state(3, k)
					expect(st.state).toBe("idle")
					expect(c.flat(st.pos, door) < 2.5).toBe(true)
					expect(st.model.Parent).toBe(c.helpersFolder())
				end
				expect(c.HR.stats().connections).toBe(3)
				c.attrs(3, { Helpers = 2 })
				expect(c.HR.stats().drawn).toBe(2)
				expect(c.VB.used("helpers")).toBe(10)
				c.attrs(3, { Helpers = 0 })
				local s = c.HR.stats()
				expect({ s.drawn, s.ranches, s.connections }).toEqual({ 0, 0, 0 })
				expect(c.VB.used("helpers")).toBe(0)
				expect(c.drawnModels()).toBe(0)
				c.clean()
			end
		)
	end)

	describe("HelperRenderer › saut réglé sur tPress (D15)", function()
		it(
			"trajets 0,5 / 1,7 / 3 s : chaque Plopette atterrit sur sa cible exactement à tPress, à côté du squishy ; arc en l'air avant",
			function()
				local c = withHelpers(nil, 3, 3)
				local now = c.Clock.now()
				local travels = { 0.5, 1.7, 3 }
				c.press(3, {
					{ helper = 1, uid = "a", tPress = now + travels[1] },
					{ helper = 2, uid = "b", tPress = now + travels[2] },
					{ helper = 3, uid = "c", tPress = now + travels[3] },
				})
				for k = 1, 3 do
					local st = c.state(3, k)
					expect(math.abs(st.t1 - (now + travels[k])) < 1e-5).toBe(true)
					expect(math.abs(st.t1 - st.t0 - travels[k]) < 1e-5).toBe(true)
					local center = c.RR.positionOf(3, ({ "a", "b", "c" })[k])
					expect(math.abs(c.flat(st.target, center) - c.beside(center)) < 1e-4).toBe(true)
				end
				for k = 1, 3 do
					local tPress = now + travels[k]
					c.untilT(tPress - 0.1)
					local mid = c.state(3, k)
					expect(mid.state).toBe("jump")
					expect(mid.pos ~= mid.target).toBe(true)
					expect(mid.parts[1].Position.Y > c.WL.groundY(mid.pos.X, mid.pos.Z) + 0.45 + 0.05).toBe(
						true
					)
					c.untilT(tPress)
					local st = c.state(3, k)
					expect(st.state).toBe("idle")
					expect(st.pos).toEqual(st.target)
					expect(math.abs(st.parts[1].Position.Y - (st.target.Y + 0.45)) < 1e-6).toBe(true)
				end
				expect(c.sounds).toEqual({ "Boing", "Boing", "Boing" }) -- HelperHop sans identifiant : repli
				c.clean()
			end
		)

		it(
			"paquet en retard (tPress passé) : posée sur sa cible sans arc ; tPress dans 0,05 s : saut de 0,1 s ; à plus de 3 s : départ à tPress − 3",
			function()
				local c = withHelpers(nil, 3, 3)
				local now = c.Clock.now()
				c.press(3, {
					{ helper = 1, uid = "a", tPress = now - 0.5 },
					{ helper = 2, uid = "b", tPress = now + 0.05 },
					{ helper = 3, uid = "c", tPress = now + 4.5 },
				})
				local late = c.state(3, 1)
				expect(late.state).toBe("idle")
				expect(late.pos).toEqual(late.target)
				local short = c.state(3, 2)
				expect(math.abs(short.t1 - short.t0 - 0.1) < 1e-5).toBe(true)
				local far = c.state(3, 3)
				expect(far.state).toBe("wait")
				expect(math.abs(far.t0 - (now + 1.5)) < 1e-5).toBe(true)
				c.untilT(now + 4.5)
				expect(c.state(3, 3).pos).toEqual(c.state(3, 3).target)
				c.clean()
			end
		)
	end)

	describe("HelperRenderer › « pop » seulement quand le miroir montre la pression", function()
		local function popCase(mine)
			local c = withHelpers({ mine = mine }, 3, 4)
			local now = c.Clock.now()
			local t = now + 1
			c.press(3, {
				{ helper = 1, uid = "a", tPress = t },
				{ helper = 2, uid = "b", tPress = t },
				{ helper = 3, uid = "c", tPress = t },
				{ helper = 4, uid = "d", tPress = t },
			})
			c.untilT(t + 0.1)
			c.ready(3, "a", t + 8) -- vraie pression
			c.ready(3, "c", t - 1) -- `ready` pas plus tard que tPress : pas une pression de Plopette
			c.untilT(t + 0.9)
			c.ready(3, "d", t + 8) -- trop tard : après tPress + 0,8 s
			-- b : aucun message (saut abandonné par le serveur)
			c.play(0.5)
			expect(c.presses).toEqual({ "3:a" })
			expect(#c.drops).toBe(1)
			expect(c.drops[1].n).toBe(6)
			local s = c.HR.stats()
			expect({ s.pops, s.soft }).toEqual({ 1, 3 })
			for k = 1, 4 do
				expect(c.state(3, k).pos).toEqual(c.state(3, k).target)
			end
			c.clean()
			return c
		end

		it("sur le client du propriétaire", function()
			local c = popCase(3)
			expect(#c.sounds).toBe(4)
		end)

		it("sur le client d'un voisin (ranch 4, ranch 3 en détail complet) : même état final", function()
			local c = popCase(4)
			expect(c.RR.detail(3)).toBe("full")
			expect(#c.sounds).toBe(0) -- ni mon ranch ni le ranch courant : aucun son
		end)
	end)

	describe("HelperRenderer › sieste, pause, réparation", function()
		it(
			"saut coupé par une sieste : il finit sans « pop », retour à la maisonnette, sommeil en rangée avec UNE étiquette « z » ; réveil : elles attendent, puis 6 sauts d'un message partent ensemble",
			function()
				local c = withHelpers(nil, 3, 6)
				local now = c.Clock.now()
				c.press(3, { { helper = 1, uid = "a", tPress = now + 1.5 } })
				c.play(0.5)
				c.attrs(3, { HelperMode = "nap" })
				c.untilT(now + 1.6)
				c.ready(3, "a", now + 9) -- le miroir montre une pression : trop tard, la sieste l'a coupée
				c.play(4)
				expect(#c.presses).toBe(0)
				local door = c.WL.helperHouse(3)
				for k = 1, 6 do
					local st = c.state(3, k)
					expect(st.state).toBe("sleep")
					expect(c.flat(st.pos, door) < 2.5).toBe(true)
				end
				expect(c.HR.stats().labels).toBe(1)
				local labels = 0
				for _, gui in c.h.game:GetDescendants() do
					if gui.Name == "HelperNap" and gui:IsA("BillboardGui") and gui.Enabled then
						labels += 1
					end
				end
				expect(labels).toBe(1)
				-- message pendant la sieste : ignoré
				c.press(3, { { helper = 2, uid = "b", tPress = c.Clock.now() + 1 } })
				expect(c.state(3, 2).state).toBe("sleep")
				-- réveil
				c.attrs(3, { HelperMode = "active" })
				expect(c.HR.stats().labels).toBe(0)
				c.play(1)
				for k = 1, 6 do
					expect(c.state(3, k).state).toBe("idle")
				end
				local t = c.Clock.now() + 2
				local all = {}
				for k = 1, 6 do
					all[k] = { helper = k, uid = UIDS[k], tPress = t }
				end
				c.press(3, all)
				c.play(0.05)
				for k = 1, 6 do
					expect(c.state(3, k).state).toBe("jump")
				end
				c.untilT(t)
				for k = 1, 6 do
					expect(c.state(3, k).pos).toEqual(c.state(3, k).target)
				end
				expect(#c.sounds).toBe(7)
				c.clean()
			end
		)

		it(
			"saut coupé par une pause : il finit sur sa cible sans « pop », puis elle attend sur place",
			function()
				local c = withHelpers(nil, 3, 2)
				local now = c.Clock.now()
				c.press(3, { { helper = 1, uid = "a", tPress = now + 1 } })
				c.play(0.4)
				c.attrs(3, { HelperMode = "paused" })
				c.untilT(now + 1.1)
				c.ready(3, "a", now + 9)
				c.play(1)
				local st = c.state(3, 1)
				expect(st.state).toBe("idle")
				expect(st.pos).toEqual(st.target)
				expect(#c.presses).toBe(0)
				-- message pendant la pause : ignoré
				c.press(3, { { helper = 2, uid = "b", tPress = c.Clock.now() + 1 } })
				expect(c.state(3, 2).state).toBe("idle")
				c.clean()
			end
		)

		it(
			"paquet perdu : le saut suivant part de là où la Plopette est dessinée (réparation)",
			function()
				local c = withHelpers(nil, 3, 1)
				local now = c.Clock.now()
				c.press(3, { { helper = 1, uid = "a", tPress = now + 1 } })
				c.untilT(now + 1)
				local first = c.state(3, 1).pos
				-- le message vers « b » est perdu ; le suivant vise « c »
				c.play(2)
				c.press(3, { { helper = 1, uid = "c", tPress = c.Clock.now() + 1 } })
				c.play(1 / 60)
				local st = c.state(3, 1)
				expect(c.flat(st.pos, first) < 0.5).toBe(true)
				c.untilT(st.t1)
				expect(c.state(3, 1).pos).toEqual(c.state(3, 1).target)
				local center = c.RR.positionOf(3, "c")
				expect(math.abs(c.flat(c.state(3, 1).target, center) - c.beside(center)) < 1e-4).toBe(true)
				c.clean()
			end
		)
	end)

	describe("HelperRenderer › coupures", function()
		it(
			"interrupteur coupé en direct (attributs effacés) : chaque instance rendue à l'image même",
			function()
				local c = withHelpers(nil, 3, 6)
				c.press(3, { { helper = 1, uid = "a", tPress = c.Clock.now() + 2 } })
				c.play(0.5)
				c.unset(3, { "Helpers", "HelperMode" })
				local s = c.HR.stats()
				expect({ s.drawn, s.parts, s.connections, s.labels }).toEqual({ 0, 0, 0, 0 })
				expect(c.drawnModels()).toBe(0)
				expect(c.VB.used("helpers")).toBe(0)
				-- rallumé : reparties de la maisonnette
				c.attrs(3, { Helpers = 6, HelperMode = "active" })
				c.play(0.3)
				expect(c.HR.stats().drawn).toBe(6)
				expect(c.flat(c.state(3, 1).pos, c.WL.helperHouse(3)) < 2.5).toBe(true)
				c.clean()
			end
		)

		it(
			"départ du propriétaire puis nouveau propriétaire : tout rendu, les Plopettes repartent de la maisonnette",
			function()
				local c = withHelpers({ mine = 4 }, 3, 3)
				local now = c.Clock.now()
				c.press(3, { { helper = 1, uid = "a", tPress = now + 1 } })
				c.untilT(now + 1)
				-- le serveur libère le ranch et ses attributs
				c.unset(3, { "Helpers", "HelperMode" })
				c.world(function(ranches)
					ranches["3"].userId = 0
				end)
				expect(c.HR.stats().drawn).toBe(0)
				-- un autre joueur arrive avec ses Plopettes
				c.world(function(ranches)
					ranches["3"].userId = 777
				end)
				c.attrs(3, { Helpers = 3, HelperMode = "active" })
				c.play(0.3)
				expect(c.HR.stats().drawn).toBe(3)
				expect(c.flat(c.state(3, 1).pos, c.WL.helperHouse(3)) < 2.5).toBe(true)
				-- un message de l'ancien propriétaire est ignoré
				c.raw({ ownerId = 103, presses = { { helper = 1, uid = "a", tPress = c.Clock.now() + 1 } } })
				expect(c.state(3, 1).state).toBe("idle")
				c.raw({ ownerId = 777, presses = { { helper = 1, uid = "a", tPress = c.Clock.now() + 1 } } })
				expect(c.state(3, 1).state).toBe("wait")
				c.clean()
			end
		)

		it(
			"le ranch quitte le détail complet : tout rendu à l'image ; il y revient : à la maisonnette",
			function()
				local c = withHelpers(nil, 3, 6)
				c.press(3, { { helper = 2, uid = "b", tPress = c.Clock.now() + 2 } })
				c.play(0.3)
				c.me(c.WL.penSlot(10, 5))
				c.play(0.3)
				expect(c.RR.detail(3)).toBe("reduced")
				local s = c.HR.stats()
				expect({ s.drawn, s.parts }).toEqual({ 0, 0 })
				expect(c.drawnModels()).toBe(0)
				expect(c.VB.used("helpers")).toBe(0)
				-- un message pour un ranch hors détail : ignoré, aucune instance
				c.press(3, { { helper = 1, uid = "a", tPress = c.Clock.now() + 1 } })
				expect(c.drawnModels()).toBe(0)
				c.me(c.WL.penSlot(3, 5))
				c.play(0.3)
				expect(c.HR.stats().drawn).toBe(6)
				for k = 1, 6 do
					expect(c.state(3, k).state).toBe("idle")
					expect(c.flat(c.state(3, k).pos, c.WL.helperHouse(3)) < 2.5).toBe(true)
				end
				c.clean()
			end
		)

		it("charges hostiles : ignorées sans trace, sans saut ni instance", function()
			local c = withHelpers(nil, 3, 3)
			local now = c.Clock.now()
			local models = c.drawnModels()
			local function e(helper, uid, tPress)
				return { helper = helper, uid = uid, tPress = tPress }
			end
			local long = string.rep("x", 33)
			local seven = {}
			for k = 1, 7 do
				seven[k] = e(1, "a", now + 1)
			end
			for _, bad in
				{
					nil,
					3,
					"x",
					{},
					{ ownerId = 1 },
					{ ownerId = "1", presses = { e(1, "a", now + 1) } },
					{ ownerId = 0 / 0, presses = { e(1, "a", now + 1) } },
					{ ownerId = 1, presses = "x" },
					{ ownerId = 1, presses = {} },
					{ ownerId = 1, presses = seven },
					{ ownerId = 1, presses = { e(0, "a", now + 1) } },
					{ ownerId = 1, presses = { e(4, "a", now + 1) } }, -- au-delà de Helpers = 3
					{ ownerId = 1, presses = { e(7, "a", now + 1) } },
					{ ownerId = 1, presses = { e(1.5, "a", now + 1) } },
					{ ownerId = 1, presses = { e(1, "", now + 1) } },
					{ ownerId = 1, presses = { e(1, long, now + 1) } },
					{ ownerId = 1, presses = { e(1, 5, now + 1) } },
					{ ownerId = 1, presses = { e(1, "a", now + 6) } },
					{ ownerId = 1, presses = { e(1, "a", now - 6) } },
					{ ownerId = 1, presses = { e(1, "a", math.huge) } },
					{ ownerId = 1, presses = { e(1, "a", 0 / 0) } },
					{ ownerId = 1, presses = { e(1, "a", "soon") } },
					{ ownerId = 1, presses = { e(1, "a", now + 1), "x" } },
					{ ownerId = 1, presses = { x = e(1, "a", now + 1) } },
					{ ownerId = 999, presses = { e(1, "a", now + 1) } },
				}
			do
				c.raw(bad)
			end
			-- uid absent du miroir : saut ignoré (aucune cible)
			c.raw({ ownerId = 1, presses = { e(1, "zz", now + 1) } })
			c.play(1)
			local s = c.HR.stats()
			expect(s.jumps).toBe(0)
			expect(s.ignored >= 24).toBe(true)
			expect(c.drawnModels()).toBe(models)
			for k = 1, 3 do
				expect(c.state(3, k).state).toBe("idle")
			end
			c.clean()
		end)
	end)

	describe("HelperRenderer › budget, durée et coût", function()
		it(
			"16 ranchs × 6 Plopettes : seulement les 3 ranchs en détail complet dessinés, budget « helpers » (152) jamais dépassé, Graphismes légers : mon ranch seul (il est aussi le ranch courant)",
			function()
				local c = client()
				for slot = 1, 16 do
					c.attrs(slot, { Helpers = 6, HelperMode = "active" })
				end
				c.play(0.3)
				local full = 0
				for slot = 1, 16 do
					if c.RR.detail(slot) == "full" then
						full += 1
						expect(c.state(slot, 1).drawn).toBe(true)
					else
						expect(c.state(slot, 1).drawn).toBe(false)
					end
				end
				expect(full).toBe(3)
				local s = c.HR.stats()
				expect({ s.drawn, s.parts, s.ranches }).toEqual({ 18, 90, 16 })
				local vb = c.VB.stats().helpers
				expect(vb.parts).toBe(152)
				expect(vb.peak <= 152).toBe(true)
				c.Prefs.lowGraphics = function()
					return true
				end
				c.play(0.3)
				-- Graphismes légers : mon ranch et le ranch courant (ici le même) en détail complet
				expect(c.HR.stats().drawn).toBe(6)
				expect(c.VB.stats().helpers.refused).toBe(0)
				c.clean()
			end
		)

		it(
			"6 h d'horloge figée, 16 ranchs × 6 Plopettes (graine fixe) : aucune fuite d'instance, de connexion ni de fil ; budget tenu à chaque image",
			function()
				local started = os.clock()
				local c = client()
				local seed = 20261111
				local function rand(n)
					seed = (seed * 1103515245 + 12345) % 2147483648
					return seed % n + 1
				end
				for slot = 1, 16 do
					c.attrs(slot, { Helpers = 6, HelperMode = "active" })
				end
				c.play(0.3)
				local most, over = 0, 0
				local function watch()
					local used = c.VB.used("helpers")
					most = math.max(most, used)
					if used > 152 then
						over += 1
					end
				end
				local function quiet()
					for slot = 1, 16 do
						c.attrs(slot, { Helpers = 6, HelperMode = "active" })
					end
					c.me(c.WL.penSlot(3, 5))
					c.play(4, 30)
					local counts = c.h:counts()
					return {
						instances = #c.h.game:GetDescendants(),
						connections = counts.connections,
						threads = counts.threads,
						drawn = c.HR.stats().drawn,
						used = c.VB.used("helpers"),
						worldText = c.WT.stats().live,
						kits = c.Kit.stats().live,
					}
				end
				local snapshots = {}
				for step = 1, 720 do
					c.Clock.advance(30 - 1)
					local k = (step - 1) % 16 + 1
					local now = c.Clock.now()
					local action = step % 8
					if action == 0 then
						c.me(c.WL.penSlot(rand(16), 5))
					elseif action == 1 then
						c.attrs(k, { HelperMode = "nap" })
					elseif action == 2 then
						c.attrs(k, { HelperMode = "active" })
					elseif action == 3 then
						c.attrs(k, { HelperMode = "paused" })
					elseif action == 4 then
						c.attrs(k, { Helpers = rand(7) - 1, HelperMode = "active" })
					elseif action == 5 then
						c.unset(k, { "Helpers", "HelperMode" })
					else
						c.attrs(k, { Helpers = 6, HelperMode = "active" })
					end
					-- un message par ranch, jusqu'à 6 sauts
					for slot = 1, 16 do
						local list = {}
						for h = 1, rand(6) do
							list[h] = { helper = h, uid = UIDS[rand(8)], tPress = now + rand(30) / 10 }
						end
						c.press(slot, list)
					end
					for _ = 1, 30 do
						c.frame(1 / 30)
						watch()
					end
					if step % 240 == 0 then
						table.insert(snapshots, quiet())
					end
				end
				expect(#snapshots).toBe(3)
				expect(snapshots[2]).toEqual(snapshots[1])
				expect(snapshots[3]).toEqual(snapshots[1])
				expect(over).toBe(0)
				expect(most <= 152 and most >= 60).toBe(true)
				local s = c.HR.stats()
				expect(s.jumps > 1000).toBe(true)
				print(
					string.format(
						"  6 h de Plopettes : 720 étapes, %d sauts, %d atterrissages doux, au plus %d pièces ; instances %d, connexions %d, fils %d aux trois points calmes ; %.1f s",
						s.jumps,
						s.soft,
						most,
						snapshots[3].instances,
						snapshots[3].connections,
						snapshots[3].threads,
						os.clock() - started
					)
				)
				c.clean()
			end
		)

		it(
			"coût par image avec 16 ranchs × 6 Plopettes (méthode du lot B4) : HelperRenderer._step seul et image complète avec et sans Plopettes",
			function()
				local c = client()
				c.me(c.WL.penSlot(3, 5))
				c.play(1, 30)
				local function best(fn)
					local out = math.huge
					for _ = 1, 5 do
						local t = os.clock()
						for _ = 1, 300 do
							c.Clock.advance(1 / 30)
							fn(1 / 30)
						end
						out = math.min(out, (os.clock() - t) / 300 * 1000)
					end
					c.h:settle(1)
					return out
				end
				local function whole(dt)
					c.h.game.RunService.RenderStepped:Fire(dt)
				end
				local offFrame = best(whole)
				for slot = 1, 16 do
					c.attrs(slot, { Helpers = 6, HelperMode = "active" })
				end
				c.play(0.5, 30)
				-- les 18 Plopettes dessinées sautent sans arrêt
				local function busy(dt)
					for slot = 2, 4 do
						local st = c.state(slot, 1)
						if st and st.state == "idle" then
							local list = {}
							for k = 1, 6 do
								list[k] = { helper = k, uid = UIDS[k], tPress = c.Clock.now() + 1 }
							end
							c.press(slot, list)
						end
					end
					whole(dt)
				end
				local onFrame = best(busy)
				local own = best(c.HR._step)
				print(
					string.format(
						"  16 ranchs × 6 Plopettes (%d dessinées, %d pièces) : image complète %.3f ms sans Plopette, %.3f ms avec (sauts sans arrêt) ; HelperRenderer._step seul %.3f ms",
						c.HR.stats().drawn,
						c.HR.stats().parts,
						offFrame,
						onFrame,
						own
					)
				)
				expect(own < 0.5).toBe(true)
				expect(onFrame < offFrame * 2 + 1).toBe(true)
				c.clean()
			end
		)
	end)

	local _ = CFrame
end
