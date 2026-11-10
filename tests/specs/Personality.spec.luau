--!nocheck
-- World/Personality (lot B5 ; GDD §5.6 ; docs/04 §27.10 ; plan B5 D3, D6) : personnalités des squishies,
-- derrière l'interrupteur Personalities (EventState.features.v2, lu par World/Flags).
-- Étape 1 du lot (socle) : interrupteur vu du client, route des visages vers le modèle dessiné,
-- coupure en direct, pose de repos rendue telle quelle. Les saynètes, les réactions et les tours
-- appris (déplacement ≤ 2 studs, cible stable pendant chaque saynète) viennent à l'étape 2 dans ce
-- fichier. Le crochet de RanchRenderer (pose jamais appelée interrupteur coupé) est dans
-- RanchRenderer.spec. Zéro trace (ZeroLog), horloge figée.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local UpgradeScreen = require("../harness/UpgradeScreen")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local T0 = 1796724120
local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

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

	-- Client du rendu : miroir, RanchRenderer et ses modules ; le ranch 3 est le mien (joueur 1)
	local function client()
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		h:require(CLIENT .. "Util.Prefs").Init()
		h:require(CLIENT .. "Controllers.StateController").Init()
		local WSC = h:require(CLIENT .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local RR = h:require(CLIENT .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local c = {
			h = h,
			RR = RR,
			Clock = Clock,
			P = h:require(CLIENT .. "World.Personality"),
			SB = h:require("ReplicatedStorage.Shared.Render.SquishyBuilder"),
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			changed = 0,
		}
		c.P.Changed:Connect(function()
			c.changed += 1
		end)
		function c.snapshot(ranches, squishies)
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = 1, ranches = ranches, squishies = squishies or {} }
			)
			h:settle(1)
		end
		-- interrupteurs annoncés par le serveur (nil : la configuration livrée)
		function c.flags(v2)
			h:fireClient("ReplicatedStorage.Remotes.EventState", UpgradeScreen.eventState(v2))
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
		function c.near()
			c.camera(c.WL.penSlot(3, 1) + Vector3.new(0, 8, -10))
		end
		function c.away()
			local far = c.WL.anchor(3, "silhouette")
			c.camera(Vector3.new(-far.X, 300, -far.Z) * 3)
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return c
	end

	local function drawn3(c)
		c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = { a = sq(1), b = sq(2), c = sq(5) } })
		c.near()
		c.run(0.5)
		expect(c.RR.stats().models).toBe(3)
	end

	describe("Personality › socle (lot B5, étape 1)", function()
		it(
			"active() suit EventState.features.v2.Personalities ; Changed une fois par vrai changement ; un autre interrupteur ne compte pas",
			function()
				local c = client()
				expect(c.P.active()).toBe(false)
				c.flags(nil)
				c.flags({ PhotoMode = true, Hearts = true })
				expect(c.P.active()).toBe(false)
				expect(c.changed).toBe(0)
				c.flags({ Personalities = true })
				expect(c.P.active()).toBe(true)
				expect(c.changed).toBe(1)
				c.flags({ Personalities = true, Carnet = true })
				expect(c.changed).toBe(1)
				for _, hostile in { { Personalities = "yes" }, 3, { Personalities = true, [1] = true } } do
					c.flags({ Personalities = true })
					local before = c.changed
					c.flags(hostile)
					expect(c.P.active()).toBe(false)
					expect(c.changed >= before + 1).toBe(true)
				end
				c.flags(nil)
				expect(c.P.active()).toBe(false)
				c.clean()
			end
		)

		it(
			"interrupteur coupé : setFace ne fait rien (aucune écriture sur le modèle), faceOf rend « happy »",
			function()
				local c = client()
				drawn3(c)
				local handle = c.RR.handleOf(3, "a")
				local writes = 0
				local conns = {}
				for _, part in handle.parts do
					table.insert(
						conns,
						part.Changed:Connect(function(prop)
							if prop == "Size" or prop == "Material" then
								writes += 1
							end
						end)
					)
				end
				for _, face in c.SB.FACES do
					expect(c.P.setFace(3, "a", face)).toBe(false)
				end
				expect(writes).toBe(0)
				expect(c.SB.faceOf(handle)).toBe("happy")
				expect(c.P.faceOf(3, "a")).toBe("happy")
				for _, conn in conns do
					conn:Disconnect()
				end
				c.clean()
			end
		)

		it(
			"ouvert : setFace pose le visage sur le modèle dessiné ; pas dessiné, visage inconnu, valeurs hostiles : faux et rien ; « happy » efface ; modèle rendu : oublié, la réserve le rend avec « happy »",
			function()
				local c = client()
				drawn3(c)
				c.flags({ Personalities = true })
				local a, b = c.RR.handleOf(3, "a"), c.RR.handleOf(3, "b")
				expect(c.P.setFace(3, "a", "starry")).toBe(true)
				expect(c.SB.faceOf(a)).toBe("starry")
				expect(c.P.faceOf(3, "a")).toBe("starry")
				expect(c.SB.faceOf(b)).toBe("happy")
				-- le visage tient pendant que le squishy est animé
				c.run(0.5)
				expect(c.SB.faceOf(a)).toBe("starry")
				for _, part in a.parts do
					if part.Name == "Glint1" then
						expect(part.Material).toBe(Enum.Material.Neon)
					end
				end
				for _, bad in
					{
						{ 3, "zz", "starry" }, -- pas dans le miroir
						{ 9, "a", "starry" }, -- autre ranch
						{ 3, "a", "angry" },
						{ 3, "a", "" },
						{ 3, "a", nil },
						{ 3, "a", 5 },
						{ nil, "a", "sulky" },
						{ 3, nil, "sulky" },
						{ "3", "a", "sulky" },
						{ 3, {}, "sulky" },
					}
				do
					expect(c.P.setFace(bad[1], bad[2], bad[3])).toBe(false)
				end
				expect(c.SB.faceOf(a)).toBe("starry")
				expect(c.P.setFace(3, "a", "happy")).toBe(true)
				expect(c.SB.faceOf(a)).toBe("happy")
				expect(c.P.faceOf(3, "a")).toBe("happy")
				-- modèle rendu (caméra au loin) : oublié ; redessiné : visage de repos
				expect(c.P.setFace(3, "b", "sulky")).toBe(true)
				c.away()
				c.run(0.2)
				expect(c.RR.stats().models).toBe(0)
				expect(c.P.faceOf(3, "b")).toBe("happy")
				expect(c.SB.faceOf(b)).toBe("happy")
				expect(c.P.setFace(3, "b", "sulky")).toBe(false) -- plus dessiné
				c.near()
				c.run(0.5)
				expect(c.RR.stats().models).toBe(3)
				expect(c.SB.faceOf(c.RR.handleOf(3, "b"))).toBe("happy")
				c.clean()
			end
		)

		it(
			"coupure en direct : chaque visage posé revient à « happy » AVANT que Changed parte ; rouvert : rien ne revient tout seul",
			function()
				local c = client()
				drawn3(c)
				c.flags({ Personalities = true })
				local faces = { a = "delighted", b = "surprised", c = "sleepy" }
				for uid, face in faces do
					expect(c.P.setFace(3, uid, face)).toBe(true)
				end
				local atChange = {}
				c.P.Changed:Connect(function()
					for uid in faces do
						atChange[uid] = c.SB.faceOf(c.RR.handleOf(3, uid))
					end
				end)
				c.flags(nil)
				expect(c.P.active()).toBe(false)
				for uid in faces do
					local handle = c.RR.handleOf(3, uid)
					expect({ uid, atChange[uid] }).toEqual({ uid, "happy" })
					expect({ uid, c.P.faceOf(3, uid) }).toEqual({ uid, "happy" })
					-- tailles de la recette (jamais une taille relevée avant : un œil peut cligner à cet
					-- instant, la graine du clignement est tirée au hasard ; le corps, lui, est écrasé par
					-- l'animation et ne se compare pas)
					local d = handle.spec.displayScale * 2
					for i, p in c.SB._plan(handle.spec) do
						if i > 1 then
							local same = (handle.parts[i].Size - p.size * d).Magnitude < 1e-4
							expect({ uid, p.name, same }).toEqual({ uid, p.name, true })
						end
					end
				end
				c.flags({ Personalities = true })
				c.run(0.3)
				for uid in faces do
					expect(c.SB.faceOf(c.RR.handleOf(3, uid))).toBe("happy")
				end
				c.clean()
			end
		)

		it(
			"pose (étape 1) : la pose de repos telle quelle ; aucune boucle, aucun module d'écran, jamais Config/Features dans le module",
			function()
				local c = client()
				drawn3(c)
				local handle = c.RR.handleOf(3, "a")
				local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0, 1, 0)
				expect(c.P.pose({ slot = 3, uid = "a" }, handle, sq(1), "pen", Vector3.new(1, 0, 3), cf, T0)).toBe(
					cf
				)
				for _, file in { "src/client/World/Personality.luau", "src/client/World/Flags.luau" } do
					local src = fs.readFile(file)
					for _, word in
						{
							"RunService",
							"RenderStepped",
							"Heartbeat",
							"BindToRenderStep",
							"task.spawn",
							"task.delay",
							"while ",
							"Config.Features",
							"Client.UI",
						}
					do
						expect({ file, word, string.find(src, word, 1, true) ~= nil }).toEqual({
							file,
							word,
							false,
						})
					end
				end
				c.clean()
			end
		)
	end)
end
