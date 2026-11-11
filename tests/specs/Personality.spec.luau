--!nocheck
-- World/Personality et World/Scenes (lot B5 ; GDD §5.6 ; docs/04 §27.10 ; plan B5 D3, D4, D6 à D10, D29,
-- D30) : personnalités des squishies, derrière l'interrupteur Personalities (EventState.features.v2,
-- lu par World/Flags).
--   * socle (étape 1) : interrupteur vu du client, route des visages vers le modèle dessiné, coupure
--     en direct, pose de repos rendue telle quelle sans saynète ;
--   * étape 2 : les 18 saynètes et les 5 tours (durées du GDD, valeurs toutes les 1/60 s, Mouvement
--     réduit), composition (centre du corps à 2 studs de la place avec la pire flânerie), chaque
--     saynète sur un vrai squishy à côté d'un client témoin sans saynète (aucune écriture de Size,
--     positionOf et projected identiques : cible stable), horaire de 8 à 20 s par personnalité, limite
--     de 6 (3 en qualité réduite), les plus proches d'abord, arrêts à l'image même (pression, ciblage,
--     portage, Bassin, clôture, spectacle, Petit Splorch), visages qui reviennent toujours à « happy »,
--     les 8 réactions, tours par seuils, « Bravo », annonce une fois et jamais au chargement, ola,
--     vermicelles d'une cascade, Prairie (12 et ses deux dispositions), interrupteur coupé (zéro appel,
--     zéro instance, zéro connexion), coupure en direct, 6 h d'horloge figée avec 16 ranchs, coût par
--     image. Le crochet de RanchRenderer (pose jamais appelée interrupteur coupé) est aussi dans
--     RanchRenderer.spec. Zéro trace (ZeroLog), horloge figée, hasards à graine.
-- Tout est en 3D : ces cas prouvent la structure (instances, CFrame, tailles, durées), personne n'a pu
-- regarder les saynètes ni les visages.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
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
		-- étape 2 : modules, sources capturées (message, son, vermicelles), images complètes
		c.Scenes = h:require(CLIENT .. "World.Scenes")
		c.WSC = WSC
		c.Species = h:require("ReplicatedStorage.Shared.Config.Species")
		c.Quests = h:require("ReplicatedStorage.Shared.Config.Quests")
		c.Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
		c.VB = h:require(CLIENT .. "Render.VisualBudget")
		c.BC = h:require(CLIENT .. "Render.BuildCascade")
		c.WT = h:require(CLIENT .. "UI.WorldText")
		c.Prefs = h:require(CLIENT .. "Util.Prefs")
		c.QC = h:require(CLIENT .. "Controllers.QualityController")
		c.toasts, c.sounds, c.bursts = {}, {}, {}
		c.P._configure({
			toast = function(text)
				table.insert(c.toasts, text)
			end,
			play = function(name)
				table.insert(c.sounds, name)
			end,
			burst = function(pos, color, n)
				table.insert(c.bursts, { pos = pos, n = n })
			end,
		})
		c.seq = 1
		-- instantané suivant (numéro croissant)
		function c.snap(ranches, squishies)
			c.seq += 1
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = c.seq, ranches = ranches, squishies = squishies or {} }
			)
			h:settle(1)
		end
		-- EventState complet ; over : rush, mega, moon, spectacle remplacés
		function c.event(v2, over)
			local ev = UpgradeScreen.eventState(v2, over and over.spectacle)
			for key, value in over or {} do
				if key ~= "spectacle" then
					ev[key] = value
				end
			end
			h:fireClient("ReplicatedStorage.Remotes.EventState", ev)
			h:settle(1)
		end
		function c.celebrate(kind, data)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
		end
		-- une image complète : l'horloge avance, puis RenderStepped (RanchRenderer et Personality)
		function c.frame(dt)
			Clock.advance(dt)
			h.game.RunService.RenderStepped:Fire(dt)
		end
		function c.play(seconds, fps, each)
			local dt = 1 / (fps or 30)
			for i = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				c.frame(dt)
				if each then
					each(i, dt)
				end
			end
			h:settle(1)
		end
		-- mon personnage (créé à la demande) posé à `pos`
		function c.me(pos)
			if h.localPlayer.Character == nil then
				h:respawn(h.localPlayer)
			end
			h:moveTo(h.localPlayer, pos + Vector3.new(0, 3, 0))
		end
		-- modèle du ranch comme celui du serveur (attributs v2.0)
		function c.ranchModel(slot)
			local function folder(parent, name)
				local f = parent:FindFirstChild(name)
				if f == nil then
					f = MockInstance.new("Folder")
					f.Name = name
					f.Parent = parent
				end
				return f
			end
			return folder(folder(folder(h.workspace, "Wobbleton"), "Ranches"), tostring(slot))
		end
		function c.flat(a, b)
			return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
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

		-- attente changée à l'étape 2 (journal B5-12) : World/Personality a maintenant UNE boucle par image
		-- (RenderStepped, branchée seulement tant qu'il y a quelque chose à faire vivre, D29), l'étiquette
		-- du monde (UI/WorldText, déjà chargée par RanchRenderer) et le message du HUD (UI/Toast, à la
		-- demande) ; les autres interdits restent, et World/Flags garde la liste entière
		it(
			"pose sans saynète : la pose de repos telle quelle ; une seule boucle (RenderStepped), aucun fil, jamais Config/Features dans le module ; World/Flags : aucune boucle, aucun module d'écran",
			function()
				local c = client()
				drawn3(c)
				local handle = c.RR.handleOf(3, "a")
				local cf = CFrame.new(1, 2, 3) * CFrame.Angles(0, 1, 0)
				expect(c.P.pose({ slot = 3, uid = "a" }, handle, sq(1), "pen", Vector3.new(1, 0, 3), cf, T0)).toBe(
					cf
				)
				local FORBIDDEN = {
					["src/client/World/Flags.luau"] = {
						"RunService",
						"RenderStepped",
						"Heartbeat",
						"BindToRenderStep",
						"task.spawn",
						"task.delay",
						"while ",
						"Config.Features",
						"Client.UI",
					},
					["src/client/World/Personality.luau"] = {
						"Heartbeat",
						"BindToRenderStep",
						"task.spawn",
						"task.delay",
						"task.wait",
						"task.defer",
						"while ",
						"Config.Features",
						"Lighting",
						"FireServer",
					},
					["src/client/World/Scenes.luau"] = {
						"RunService",
						"Instance.new",
						"game:",
						"workspace",
						"task.",
						"while ",
						"Config.Features",
						".Size",
					},
				}
				for file, words in FORBIDDEN do
					local src = fs.readFile(file)
					for _, word in words do
						expect({ file, word, string.find(src, word, 1, true) ~= nil }).toEqual({
							file,
							word,
							false,
						})
					end
				end
				-- une seule connexion par image dans World/Personality
				local _, loops =
					string.gsub(fs.readFile("src/client/World/Personality.luau"), "RenderStepped:Connect", "")
				expect(loops).toBe(1)
				c.clean()
			end
		)
	end)

	-- =========================================================================================
	-- Étape 2 : saynètes, composition, horaire, limite, arrêts
	-- =========================================================================================

	local T60 = 1 / 60

	-- angle ramené dans ]−π ; π]
	local function wrap(a)
		local x = a % (2 * math.pi)
		return if x > math.pi then x - 2 * math.pi else x
	end

	local function allIds(S)
		local ids = {}
		for _, id in S.LIST do
			table.insert(ids, id)
		end
		for _, id in S.TRICKS do
			table.insert(ids, id)
		end
		return ids
	end

	-- Première espèce de chaque personnalité (colonne perso de Config/Species)
	local function speciesByPerso(c)
		local out = {}
		for _, def in c.Species.List do
			if out[def.perso] == nil then
				out[def.perso] = def.id
			end
		end
		return out
	end

	-- Deux clients sur le même monde : `a` avec Personalities, `b` témoin sans ; caméra à 50 studs de
	-- l'enclos (détail complet, hors des 40 studs : aucune saynète de l'horaire, seulement _play)
	local function twin(squishies)
		local a, b = client(), client()
		for _, c in { a, b } do
			c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = squishies or { a = sq(1), b = sq(2), c = sq(5) } })
			c.camera(c.WL.penSlot(3, 1) + Vector3.new(0, 30, -40))
		end
		a.flags({ Personalities = true })
		for _, c in { a, b } do
			c.play(1, 60)
		end
		return a, b
	end

	-- Les deux clients avancent ensemble (même horloge, mêmes images)
	local function both(a, b, seconds, each)
		for i = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
			a.frame(T60)
			b.frame(T60)
			if each then
				each(i)
			end
		end
		a.h:settle(1)
		b.h:settle(1)
	end

	-- Écritures de Size sur les pièces d'un modèle, hors yeux et reflets (visages et clignement)
	local function watchSizes(c, uid)
		local handle = c.RR.handleOf(3, uid)
		local plan = c.SB._plan(handle.spec)
		local counts = { body = 0, other = 0 }
		local conns = {}
		for i, part in handle.parts do
			local role = plan[i].role
			if role ~= "eye" and role ~= "glint" then
				table.insert(
					conns,
					part.Changed:Connect(function(prop)
						if prop == "Size" then
							if i == 1 then
								counts.body += 1
							else
								counts.other += 1
							end
						end
					end)
				)
			end
		end
		return handle, counts, function()
			for _, conn in conns do
				conn:Disconnect()
			end
		end
	end

	local FAKE_CAMERA = {
		FieldOfView = 70,
		ViewportSize = Vector2.new(1920, 1080),
		WorldToViewportPoint = function(_, p)
			return Vector3.new(960 + p.X * 3, 540 - p.Y * 3, 20 + p.Z * 0.01), true
		end,
	}

	local function projected(c)
		local out = {}
		for _, e in c.RR.projected(FAKE_CAMERA) do
			out[e.id] = { e.screen.X, e.screen.Y, e.radius, e.depth }
		end
		return out
	end

	describe("Scenes › données pures (lot B5, étape 2)", function()
		local DURATIONS = {
			hello = 1.5,
			circle = 3,
			what = 2,
			yawn = 2,
			nap = 3,
			startle = 1,
			tripleHop = 1.8,
			twirl = 1,
			flat = 1.5,
			hearts = 2,
			kiss = 2,
			waddle = 2,
			tongue = 1.5,
			fakeSneeze = 2.5,
			hide = 2,
			pose = 2,
			bow = 1.5,
			parade = 3,
		}
		local PERSO = {
			curious = { "hello", "circle", "what" },
			sleepy = { "yawn", "nap", "startle" },
			bouncy = { "tripleHop", "twirl", "flat" },
			cuddly = { "hearts", "kiss", "waddle" },
			prankster = { "tongue", "fakeSneeze", "hide" },
			proud = { "pose", "bow", "parade" },
		}

		it(
			"18 saynètes aux durées du GDD §5.6, 3 par personnalité ; 5 tours dans l'ordre des seuils de Config/Quests ; chaque espèce a ses 3 saynètes",
			function()
				local c = client()
				local S = c.Scenes
				expect(#S.LIST).toBe(18)
				local seen, n = {}, 0
				for _, id in S.LIST do
					expect({ id, S.duration(id) }).toEqual({ id, DURATIONS[id] })
					if not seen[id] then
						seen[id] = true
						n += 1
					end
				end
				expect(n).toBe(18)
				expect(#c.Species.Personalities).toBe(6)
				for _, perso in c.Species.Personalities do
					expect({ perso, S.of(perso) }).toEqual({ perso, PERSO[perso] })
				end
				for _, def in c.Species.List do
					expect({ def.key, #S.of(def.perso) }).toEqual({ def.key, 3 })
				end
				-- tours : mêmes identifiants que les clés de Config/Quests, seuils du GDD
				expect(#S.TRICKS).toBe(5)
				local sizes = {}
				for i, trick in c.Quests.Mastery.Tricks do
					expect("trick." .. S.TRICKS[i]).toBe(trick.key)
					expect(S.duration(S.TRICKS[i]) > 0).toBe(true)
					sizes[i] = trick.size
				end
				expect(sizes).toEqual({ 100, 1200, 1e6, 1e9, 1e12 })
				expect(S.of("nobody")).toEqual({})
				expect(S.duration("nobody")).toBe(0)
				c.clean()
			end
		)

		it(
			"chaque saynète et chaque tour, toutes les 1/60 s, normal et Mouvement réduit : valeurs finies, raccord à la pose de repos au début et à la fin, déplacement à plat ≤ 1,5 stud ; réduit : aucune rotation au-delà de 45°, amplitudes × 0,5",
			function()
				local c = client()
				local S = c.Scenes
				local ids = allIds(S)
				expect(#ids).toBe(23)
				local problems = {}
				local function note(msg)
					if #problems < 12 then
						table.insert(problems, msg)
					end
				end
				local samples = 0
				for _, id in ids do
					local T = S.duration(id)
					local n = math.floor(T * 60 + 0.5)
					for _, D in { 1, 2, 6 } do
						for _, look in { 0, 2.5, -3 } do
							for _, home in { 0, 1.3, -2.7 } do
								local peak = { [false] = { flat = 0, dy = 0 }, [true] = { flat = 0, dy = 0 } }
								for _, reduced in { false, true } do
									local ctx = { reduced = reduced, look = look, home = home }
									local p = peak[reduced]
									for i = 0, n do
										local dx, dy, dz, yaw, pitch, roll, pivot =
											S.sample(id, i * T60, D, ctx)
										samples += 1
										for _, v in { dx, dy, dz, yaw, pitch, roll, pivot } do
											if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
												note(id .. " : valeur illisible")
											end
										end
										if pivot ~= 0 and pivot ~= 1 then
											note(id .. " : pivot " .. tostring(pivot))
										end
										local flat = math.sqrt(dx * dx + dz * dz)
										p.flat = math.max(p.flat, flat)
										p.dy = math.max(p.dy, math.abs(dy))
										if flat > 1.5 + 1e-6 then
											note(string.format("%s : %.3f studs à plat", id, flat))
										end
										if reduced then
											local angle =
												math.max(math.abs(yaw), math.abs(pitch), math.abs(roll))
											if angle > math.pi / 4 + 1e-9 then
												note(
													string.format(
														"%s réduit : rotation de %.2f rad",
														id,
														angle
													)
												)
											end
										end
										if i <= 1 or i >= n - 1 then
											local gap = math.abs(dx)
												+ math.abs(dy)
												+ math.abs(dz)
												+ math.abs(wrap(yaw))
												+ math.abs(wrap(pitch))
												+ math.abs(wrap(roll))
											if gap > 0.45 then
												note(
													string.format(
														"%s : saut de %.2f au raccord (image %d)",
														id,
														gap,
														i
													)
												)
											end
										end
									end
								end
								if peak[true].flat > 0.5 * peak[false].flat + 1e-6 then
									note(id .. " réduit : déplacement à plat pas divisé par 2")
								end
								if peak[true].dy > 0.5 * peak[false].dy + 1e-6 then
									note(id .. " réduit : hauteur pas divisée par 2")
								end
							end
						end
					end
				end
				expect(table.concat(problems, "\n")).toBe("")
				expect(samples > 100000).toBe(true)
				c.clean()
			end
		)

		it(
			"identifiant inconnu, temps hors de la durée, valeurs illisibles : la pose de repos, aucune erreur ; visages et ornements du tableau",
			function()
				local c = client()
				local S = c.Scenes
				local zero = { 0, 0, 0, 0, 0, 0, 0 }
				local nan = 0 / 0
				for _, args in
					{
						{ "nobody", 0.5, 2, {} },
						{ nil, 0.5, 2, {} },
						{ 12, 0.5, 2, {} },
						{ "nap", -1, 2, {} },
						{ "nap", 0, 2, {} },
						{ "nap", 3, 2, {} },
						{ "nap", 99, 2, {} },
						{ "nap", nan, 2, {} },
						{ "nap", math.huge, 2, {} },
						{ "nap", "1", 2, {} },
					}
				do
					expect({ S.sample(args[1], args[2], args[3], args[4]) }).toEqual(zero)
				end
				-- diamètre ou contexte illisibles : la saynète se joue quand même, valeurs finies
				for _, args in
					{
						{ "circle", 1, nan, nil },
						{ "circle", 1, -5, "x" },
						{ "parade", 1, math.huge, { look = nan, home = math.huge, reduced = "yes" } },
						{ "kiss", 1, nil, { look = {}, home = "a" } },
					}
				do
					for _, v in { S.sample(args[1], args[2], args[3], args[4]) } do
						expect(type(v) == "number" and v == v and math.abs(v) ~= math.huge).toBe(true)
					end
				end
				-- visages : ceux de Config/Visuals, et le changement en cours de saynète
				expect(S.face("nap", 1)).toBe("sleepy")
				expect(S.face("hello", 1)).toBe(nil)
				expect({ S.face("fakeSneeze", 1), S.face("fakeSneeze", 2) }).toEqual({
					"surprised",
					"delighted",
				})
				expect({ S.face("peekaboo", 0.2), S.face("peekaboo", 1) }).toEqual({ nil, "surprised" })
				for _, id in allIds(S) do
					for _, t in { 0, 0.5, 1, 2.9 } do
						local face = S.face(id, t)
						expect(face == nil or table.find(c.SB.FACES, face) ~= nil).toBe(true)
					end
				end
				-- ornements : « z » et « ? » en étiquettes (0 particule), cœurs, étoiles et gerbe en particules
				expect({ S.adorn("nap") }).toEqual({ "z", 0, 0.4, 2.8 })
				expect({ S.adorn("what") }).toEqual({ "what", 0, 0.3, 1.8 })
				expect({ S.adorn("hearts") }).toEqual({ "hearts", 3, 0.3, 0.3 })
				expect({ S.adorn("pose") }).toEqual({ "stars", 2, 0.5, 0.5 })
				expect({ S.adorn("fireworks") }).toEqual({ "sparks", 12, 1.1, 1.1 })
				expect({ S.adorn("waddle") }).toEqual({ nil, 0, 0, 0 })
				local most = 0
				for _, id in allIds(S) do
					local _, n = S.adorn(id)
					most = math.max(most, n)
				end
				expect(most <= 20).toBe(true)
				c.clean()
			end
		)
	end)

	describe("Personality › composition sur la pose de repos (lot B5, étape 2)", function()
		it(
			"pire flânerie (2 studs dans 8 directions) : pour chaque saynète et chaque tour, toutes les 1/60 s, le centre du corps reste à 2 studs à plat de la place ; sans saynète la pose de repos est rendue telle quelle",
			function()
				local c = client()
				local S, compose = c.Scenes, c.P._compose
				expect(type(compose)).toBe("function")
				local base = Vector3.new(40, 0, -25)
				local worst, checked, pushed = 0, 0, 0
				for _, id in allIds(S) do
					local T = S.duration(id)
					for _, D in { 2, 6 } do
						local half = D / 2
						for w = 0, 8 do
							local wander = if w == 0
								then Vector3.zero
								else Vector3.new(
									math.cos(w * math.pi / 4) * 2,
									0,
									math.sin(w * math.pi / 4) * 2
								)
							for _, face in { 0.3, 2.2, -1.9 } do
								local cf = CFrame.new(base + wander + Vector3.new(0, half, 0))
									* CFrame.Angles(0, face, 0)
								-- direction libre : vers la place, comme World/Personality
								local home = if w == 0 then 0.7 else math.atan2(wander.X, wander.Z) - face
								for _, reduced in { false, true } do
									local ctx = { reduced = reduced, look = 1.1, home = home }
									for i = 0, math.floor(T * 60 + 0.5) do
										local dx, dy, dz, yaw, pitch, roll, pivot =
											S.sample(id, i * T60, D, ctx)
										local out =
											compose(cf, base, half, dx, dy, dz, yaw, pitch, roll, pivot)
										local centre = (out * CFrame.new(0, half, 0)).Position
										local d = c.flat(centre, base)
										worst = math.max(worst, d)
										checked += 1
										-- sans la borne, la saynète sortirait des 2 studs
										local free = cf * CFrame.new(dx, dy, dz)
										if c.flat(free.Position, base) > 2.01 then
											pushed += 1
										end
									end
								end
							end
						end
					end
				end
				expect(worst <= 2 + 1e-4).toBe(true)
				expect(worst > 1.999).toBe(true)
				expect(pushed > 1000).toBe(true)
				expect(checked > 200000).toBe(true)
				-- rien à composer : exactement la pose de repos
				local cf = CFrame.new(41, 1, -24) * CFrame.Angles(0, 1.2, 0)
				local same = compose(cf, base, 1, 0, 0, 0, 0, 0, 0, 0)
				expect((same.Position - cf.Position).Magnitude < 1e-6).toBe(true)
				expect(same.LookVector:Dot(cf.LookVector) > 1 - 1e-6).toBe(true)
				-- la hauteur est libre : dy s'ajoute tel quel
				local up = compose(cf, base, 1, 0, 3, 0, 0, 0, 0, 0)
				expect(math.abs(up.Position.Y - (cf.Position.Y + 3)) < 1e-6).toBe(true)
				c.clean()
			end
		)
	end)

	describe("Personality › saynètes sur un vrai squishy (lot B5, étape 2)", function()
		it(
			"défaut du crochet du lot B4 : sans aucun ranch v2.0, RanchRenderer.detail rend « full » pour le ranch courant et ses 2 voisins (le ranch courant est relu à la demande)",
			function()
				local c = client()
				drawn3(c)
				c.run(1)
				expect({ c.RR.detail(2), c.RR.detail(3), c.RR.detail(4) }).toEqual({ "full", "full", "full" })
				expect({ c.RR.detail(5), c.RR.detail(11), c.RR.detail(1) }).toEqual({
					"reduced",
					"reduced",
					"reduced",
				})
				-- le personnage entre dans le ranch 9 : le détail suit
				c.me(c.WL.penSlot(9, 9))
				expect({ c.RR.detail(8), c.RR.detail(9), c.RR.detail(10), c.RR.detail(3) }).toEqual({
					"full",
					"full",
					"full",
					"reduced",
				})
				c.clean()
			end
		)

		it(
			"chaque saynète et chaque tour, à côté d'un client témoin sans saynète : centre du corps à 2 studs de la place, aucune écriture de Size par la saynète, positionOf et projected identiques à chaque image (cible stable), retour exact à la pose de repos",
			function()
				local a, b = twin()
				local S = a.Scenes
				local place = a.WL.penSlot(3, 1)
				local ha, countsA, stopA = watchSizes(a, "a")
				local hb, countsB, stopB = watchSizes(b, "a")
				local problems = {}
				local function note(msg)
					if #problems < 12 then
						table.insert(problems, msg)
					end
				end
				local frames = 0
				for _, id in allIds(S) do
					expect({ id, a.P.sceneOf(3, "a") }).toEqual({ id, nil })
					expect({ id, a.P._play(3, "a", id) }).toEqual({ id, true })
					expect(a.P.sceneOf(3, "a")).toBe(id)
					local moved, far = 0, 0
					both(a, b, S.duration(id) + 0.1, function()
						frames += 1
						local pa, pb = ha.body.CFrame, hb.body.CFrame
						moved = math.max(
							moved,
							(pa.Position - pb.Position).Magnitude + (1 - pa.LookVector:Dot(pb.LookVector))
						)
						far = math.max(far, a.flat(pa.Position, place))
						-- la cible du jeu lit la pose de repos : identique avec et sans la saynète
						local ra, rb = a.RR.positionOf(3, "a"), b.RR.positionOf(3, "a")
						if ra ~= rb then
							note(id .. " : positionOf diffère")
						end
						local ja, jb = projected(a), projected(b)
						for uid, e in jb do
							local o = ja[uid]
							if o == nil or o[1] ~= e[1] or o[2] ~= e[2] or o[3] ~= e[3] or o[4] ~= e[4] then
								note(id .. " : projected diffère pour " .. uid)
							end
						end
						if ha.body.Size ~= hb.body.Size then
							note(id .. " : Size du corps diffère")
						end
					end)
					if moved < 0.02 then
						note(id .. " : le modèle n'a pas bougé")
					end
					if far > 2 + 1e-3 then
						note(string.format("%s : centre du corps à %.3f studs de la place", id, far))
					end
					-- fin : plus de saynète, pose de repos exacte, visage de repos
					if a.P.sceneOf(3, "a") ~= nil then
						note(id .. " : saynète encore en cours")
					end
					local pa, pb = ha.body.CFrame, hb.body.CFrame
					if
						(pa.Position - pb.Position).Magnitude > 1e-6
						or pa.LookVector:Dot(pb.LookVector) < 1 - 1e-5
					then
						note(
							string.format(
								"%s : pas revenu à la pose de repos (écart %.6f, regard %.9f)",
								id,
								(pa.Position - pb.Position).Magnitude,
								pa.LookVector:Dot(pb.LookVector)
							)
						)
					end
					if a.SB.faceOf(ha) ~= "happy" or a.P.faceOf(3, "a") ~= "happy" then
						note(id .. " : visage pas revenu à « happy »")
					end
				end
				stopA()
				stopB()
				expect(table.concat(problems, "\n")).toBe("")
				expect(frames > 2500).toBe(true)
				-- Size : le corps est écrit par l'écrasement de repos, autant avec que sans saynète ; aucune
				-- autre pièce (hors yeux et reflets : visages et clignement)
				expect(countsA.body).toBe(countsB.body)
				expect(countsA.body > 0).toBe(true)
				expect({ countsA.other, countsB.other }).toEqual({ 0, 0 })
				-- l'interrupteur coupé chez le témoin : rien de Personality
				expect(b.P.stats().records).toBe(0)
				a.clean()
				b.clean()
			end
		)

		it(
			"une pression et un ciblage arrêtent la saynète à l'image même ; rien ne commence pour un squishy pressé, ciblé, porté, dans le Bassin, à la clôture, pendant un grand spectacle ni pendant le Petit Splorch de son propriétaire",
			function()
				local a, b = twin()
				local ha, hb = a.RR.handleOf(3, "a"), b.RR.handleOf(3, "a")
				local function atRest()
					local pa, pb = a.RR.handleOf(3, "a").body.CFrame, b.RR.handleOf(3, "a").body.CFrame
					return (pa.Position - pb.Position).Magnitude < 1e-6
						and pa.LookVector:Dot(pb.LookVector) > 1 - 1e-5
				end
				local function playing(id)
					expect({ id, a.P._play(3, "a", id) }).toEqual({ id, true })
					both(a, b, 0.5)
					expect(a.P.sceneOf(3, "a")).toBe(id)
					expect(atRest()).toBe(false)
				end
				expect(ha ~= nil and hb ~= nil).toBe(true)
				-- pression (profil d'écrasement) : arrêt à l'image suivante, visage rendu
				playing("nap")
				expect(a.SB.faceOf(ha)).toBe("sleepy")
				a.RR.play(3, "a", "press")
				b.RR.play(3, "a", "press")
				both(a, b, T60)
				expect(a.P.sceneOf(3, "a")).toBe(nil)
				expect(atRest()).toBe(true)
				expect(a.SB.faceOf(ha)).toBe("happy")
				expect(a.P._play(3, "a", "nap")).toBe(false) -- encore pressé
				both(a, b, 1.2)
				-- ciblage (RanchRenderer.highlightTarget, posé par PromptController)
				playing("parade")
				a.RR.highlightTarget(3, "a")
				b.RR.highlightTarget(3, "a")
				both(a, b, T60)
				expect(a.P.sceneOf(3, "a")).toBe(nil)
				expect(atRest()).toBe(true)
				expect(a.P._play(3, "a", "parade")).toBe(false)
				expect({ a.RR.target() }).toEqual({ 3, "a" })
				a.RR.highlightTarget(nil, nil)
				b.RR.highlightTarget(nil, nil)
				expect({ a.RR.target() }).toEqual({ 0, "" })
				-- grand spectacle (EventState.spectacle) : arrêt, puis aucun départ tant qu'il dure
				for _, kind in { "splorch", "dance", "ascend" } do
					playing("circle")
					local now = a.Clock.now()
					a.event({ Personalities = true }, {
						spectacle = {
							current = {
								kind = kind,
								userId = 77,
								startedAt = now,
								burstAt = now + 4,
								endsAt = now + 6,
								level = 2,
							},
							queue = {},
						},
					})
					both(a, b, T60)
					expect({ kind, a.P.sceneOf(3, "a") }).toEqual({ kind, nil })
					expect(atRest()).toBe(true)
					expect(a.P._play(3, "a", "circle")).toBe(false)
					-- le message de fin n'arrive jamais : le blocage tombe tout seul après endsAt
					both(a, b, 8)
					expect({ kind, a.P._play(3, "a", "bow") }).toEqual({ kind, true })
					both(a, b, 2)
				end
				a.event({ Personalities = true })
				-- Petit Splorch du propriétaire (attribut PetitSplorchAt du ranch) : 4 s sans saynète
				playing("dance")
				a.ranchModel(3):SetAttribute("PetitSplorchAt", a.Clock.now())
				both(a, b, 1.1)
				expect(a.P.sceneOf(3, "a")).toBe(nil)
				expect(a.P._play(3, "a", "dance")).toBe(false)
				both(a, b, 4)
				expect(a.P._play(3, "a", "bow")).toBe(true)
				both(a, b, 2)
				-- porté sur la tête : arrêt à l'image même, aucun départ
				for _, c in { a, b } do
					c.me(c.WL.penSlot(3, 2))
				end
				playing("nap")
				for _, c in { a, b } do
					c.snap(
						{ ["3"] = ranch(3, 1, { carry = "a" }) },
						{ ["3"] = { a = sq(1), b = sq(2), c = sq(5) } }
					)
				end
				both(a, b, 2 * T60)
				expect(a.P.sceneOf(3, "a")).toBe(nil)
				expect(a.P._play(3, "a", "nap")).toBe(false)
				-- Bassin
				for _, c in { a, b } do
					c.snap({ ["3"] = ranch(3, 1) }, { ["3"] = { a = sq(1, "pool"), b = sq(2), c = sq(5) } })
				end
				both(a, b, 0.5)
				expect(a.P._play(3, "a", "nap")).toBe(false)
				expect(a.P._play(3, "b", "nap")).toBe(true)
				-- clôture (Rush, pet-sitting)
				for _, c in { a, b } do
					c.h:fireClient(
						"ReplicatedStorage.Remotes.Fence",
						{ slot = 3, uids = { "b" }, reason = "rush" }
					)
				end
				both(a, b, 2 * T60)
				expect(a.P.sceneOf(3, "b")).toBe(nil)
				expect(a.P._play(3, "b", "nap")).toBe(false)
				expect(a.P.stats().running).toBe(0)
				a.clean()
				b.clean()
			end
		)

		it(
			"horaire : chaque espèce joue les 3 saynètes de SA personnalité, en entier, la suivante 8 à 20 s après la fin de la précédente ; jamais à plus de 40 studs de la caméra, ni dans un ranch en détail réduit",
			function()
				local c = client()
				local bySpecies = speciesByPerso(c)
				local squishies, perso = {}, {}
				for i, name in c.Species.Personalities do
					local uid = "p" .. i
					squishies[uid] = sq(bySpecies[name])
					perso[uid] = name
				end
				-- un squishy hors de portée (ranch 9, détail réduit : ni le mien ni un voisin)
				c.snapshot(
					{ ["3"] = ranch(3, 1), ["9"] = ranch(9, 109) },
					{ ["3"] = squishies, ["9"] = { far = sq(1) } }
				)
				local mid = (c.WL.penSlot(3, 3) + c.WL.penSlot(3, 4)) / 2
				c.camera(mid + Vector3.new(0, 10, 0))
				c.flags({ Personalities = true })
				local log = {}
				for uid in squishies do
					log[uid] = { seen = {}, current = nil, startedAt = 0, endedAt = nil, problems = {} }
				end
				local now0 = c.Clock.now()
				local dt = 1 / 30
				c.play(600, 30, function()
					local now = c.Clock.now()
					for uid, l in log do
						local id = c.P.sceneOf(3, uid)
						if id ~= l.current then
							if id ~= nil then
								local gap = now - (l.endedAt or now0)
								if l.endedAt == nil then
									if gap > 20 + 1 + 2 * dt then
										table.insert(
											l.problems,
											string.format("première saynète après %.1f s", gap)
										)
									end
								elseif gap < 8 - 2 * dt or gap > 20 + 1 + 2 * dt then
									table.insert(
										l.problems,
										string.format("%.2f s entre deux saynètes", gap)
									)
								end
								l.seen[id] = (l.seen[id] or 0) + 1
								l.startedAt = now
							end
							if l.current ~= nil then
								local length = now - l.startedAt
								if math.abs(length - c.Scenes.duration(l.current)) > 2 * dt + 1e-6 then
									table.insert(
										l.problems,
										string.format("%s a duré %.2f s", l.current, length)
									)
								end
								l.endedAt = now
							end
							l.current = id
						end
					end
					expect(c.P.sceneOf(9, "far")).toBe(nil)
				end)
				for uid, l in log do
					expect({ uid, table.concat(l.problems, " ; ") }).toEqual({ uid, "" })
					local mine = c.Scenes.of(perso[uid])
					local count = 0
					for id in l.seen do
						expect({ uid, id, table.find(mine, id) ~= nil }).toEqual({ uid, id, true })
						count += 1
					end
					expect({ uid, perso[uid], count }).toEqual({ uid, perso[uid], 3 })
				end
				-- le ranch 9 est en détail réduit : rien, même caméra au-dessus de lui
				expect(c.RR.detail(9)).toBe("reduced")
				c.camera(c.WL.penSlot(9, 1) + Vector3.new(0, 8, -10))
				c.play(45, 30, function()
					expect(c.P.sceneOf(9, "far")).toBe(nil)
				end)
				-- à plus de 40 studs de la caméra (niveau de détail 1 quand même) : rien non plus
				c.camera(c.WL.penSlot(3, 1) + Vector3.new(0, 30, -40))
				c.play(4, 30)
				local before = c.P.stats().started
				c.play(45, 30)
				expect(c.P.stats().started).toBe(before)
				c.clean()
			end
		)

		it(
			"limite : 6 saynètes en cours au plus, les 6 plus proches de la caméra d'abord ; une 7e ne commence jamais, aucune n'est coupée ; 3 en Graphismes légers et en qualité réduite",
			function()
				local function scenario(setup, cap)
					local c = client()
					setup(c)
					local squishies, uids = {}, {}
					for i = 1, 12 do
						local uid = string.format("s%02d", i)
						squishies[uid] = sq(2) -- Dormeur : saynètes de 1 à 3 s
						table.insert(uids, uid)
					end
					c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = squishies })
					local mid = (
						c.WL.penSlot(3, 3)
						+ c.WL.penSlot(3, 4)
						+ c.WL.penSlot(3, 9)
						+ c.WL.penSlot(3, 10)
					) / 4
					local cam = mid + Vector3.new(1.3, 12, 0.7)
					c.camera(cam)
					-- un spectacle de 22 s : toutes les saynètes attendent, les 12 sont dues à sa fin
					local now = c.Clock.now()
					c.event({ Personalities = true }, {
						spectacle = {
							current = {
								kind = "dance",
								userId = 77,
								startedAt = now,
								burstAt = now + 1,
								endsAt = now + 22,
								level = 1,
							},
							queue = {},
						},
					})
					local function running()
						local list = {}
						for _, uid in uids do
							if c.P.sceneOf(3, uid) ~= nil then
								table.insert(list, uid)
							end
						end
						table.sort(list)
						return list
					end
					local dt = 1 / 30
					local first = nil
					local most, live, problems = 0, {}, {}
					-- à chaque image : saynètes en cours (jamais plus que la limite), aucune coupée
					local function track()
						local t = c.Clock.now()
						local count = 0
						for _, uid in uids do
							local id = c.P.sceneOf(3, uid)
							local l = live[uid]
							if id ~= nil then
								count += 1
								if l == nil or l.id ~= id then
									live[uid] = { id = id, at = t }
								end
							elseif l ~= nil then
								if t - l.at < c.Scenes.duration(l.id) - 2 * dt then
									table.insert(problems, uid .. " : " .. l.id .. " coupée")
								end
								live[uid] = nil
							end
						end
						most = math.max(most, count)
						if count > cap then
							table.insert(problems, count .. " saynètes en cours")
						end
					end
					c.play(30, 30, function()
						if first == nil then
							local list = running()
							if #list > 0 then
								-- les plus proches de la caméra à cette image
								local order = table.clone(uids)
								local dist = {}
								for _, uid in uids do
									dist[uid] = (c.RR.positionOf(3, uid) - cam).Magnitude
								end
								table.sort(order, function(x, y)
									return dist[x] < dist[y]
								end)
								local nearest = {}
								for i = 1, cap do
									nearest[i] = order[i]
								end
								table.sort(nearest)
								first = { list = list, nearest = nearest, at = c.Clock.now() - now }
							end
						end
						track()
					end)
					expect(first ~= nil).toBe(true)
					expect(first.at > 22).toBe(true)
					-- 12 saynètes dues, la limite seulement commence : les plus proches
					expect(#first.list).toBe(cap)
					expect(first.list).toEqual(first.nearest)
					c.play(90, 30, track)
					expect(table.concat(problems, " ; ")).toBe("")
					expect(most).toBe(cap)
					expect(c.P.stats().cap).toBe(cap)
					expect(c.P.stats().cut).toBe(0)
					c.clean()
				end
				scenario(function() end, 6)
				scenario(function(c)
					c.Prefs.lowGraphics = function()
						return true
					end
				end, 3)
				scenario(function(c)
					c.QC.reduced = function()
						return true
					end
				end, 3)
			end
		)
	end)

	-- =========================================================================================
	-- Étape 2 : visages, réactions, tours, annonce, ola, vermicelles, Prairie
	-- =========================================================================================

	local REMOTES = "ReplicatedStorage.Remotes."

	-- Caméra à 50 studs de l'enclos du ranch 3 : détail complet, aucune saynète de l'horaire
	local function farCamera(c)
		c.camera(c.WL.penSlot(3, 1) + Vector3.new(0, 30, -40))
	end

	local function faces(c, slot, uid)
		return { c.P.faceOf(slot, uid), c.SB.faceOf(c.RR.handleOf(slot, uid)) }
	end

	-- Texte d'une étiquette du monde posée par ce module (« z », « ? »)
	local function lifeLabels(c)
		local out = {}
		local root = c.h.workspace:FindFirstChild("WorldText")
		for _, d in (if root then root:GetDescendants() else {}) do
			if d.ClassName == "BillboardGui" and d.Name == "LifeLabel" and d.Enabled and d.Adornee ~= nil then
				for _, l in d:GetDescendants() do
					if l.ClassName == "TextLabel" and l.Text ~= "" then
						table.insert(out, l.Text)
					end
				end
			end
		end
		table.sort(out)
		return out
	end

	local function named(c, name)
		local n = 0
		for _, d in c.h.workspace:GetDescendants() do
			if d.Name == name then
				n += 1
			end
		end
		return n
	end

	local function trophies(c, over)
		local t = table.create(#c.Species.List, 0)
		for k, v in over or {} do
			t[k] = v
		end
		return t
	end

	-- Hauteur du corps au-dessus de sa pose de repos (bond d'une réaction, ola) et regard à plat
	local function lift(c, slot, uid)
		local handle = c.RR.handleOf(slot, uid)
		return handle.body.CFrame.Position.Y - c.RR.positionOf(slot, uid).Y
	end

	local function looksAt(c, slot, uid, point)
		local cf = c.RR.handleOf(slot, uid).body.CFrame
		local to = Vector3.new(point.X - cf.Position.X, 0, point.Z - cf.Position.Z)
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if to.Magnitude < 1e-3 or look.Magnitude < 1e-3 then
			return 0
		end
		return to.Unit:Dot(look.Unit)
	end

	describe("Personality › visages et réactions (lot B5, étape 2)", function()
		it(
			"chaque visage revient à « happy » à la fin de sa durée, même si aucun message de fin n'arrive (60 s au plus, sommeil 300 s, horloge recalée) ; le visage d'une réaction passe devant celui d'une saynète",
			function()
				local c = client()
				drawn3(c)
				farCamera(c)
				c.flags({ Personalities = true })
				c.play(1, 30)
				local function all(face)
					for _, uid in { "a", "b", "c" } do
						expect({ uid, faces(c, 3, uid) }).toEqual({ uid, { face, face } })
					end
				end
				all("happy")
				local CASES = {
					{ "delight", nil, "delighted", 2 },
					{ "surprise", nil, "surprised", 2.5 },
					{ "starry", nil, "starry", 6 },
					{ "build", { at = c.WL.anchor(3, "vat") }, "delighted", 1.6 },
					{ "delight", { seconds = 5 }, "delighted", 5 },
					{ "starry", { seconds = 500 }, "starry", 60 },
				}
				for _, case in CASES do
					expect({ case[1], c.P.react(3, case[1], case[2]) }).toEqual({ case[1], 3 })
					all(case[3])
					c.play(case[4] - 0.3, 10)
					all(case[3])
					c.play(0.6, 10)
					all("happy")
				end
				expect(c.P.stats().faced).toBe(0)
				-- API : 60 s par défaut et au plus ; durée donnée
				expect(c.P.setFace(3, "a", "sulky")).toBe(true)
				c.play(59.5, 10)
				expect(faces(c, 3, "a")).toEqual({ "sulky", "sulky" })
				c.play(1, 10)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				expect(c.P.setFace(3, "a", "sulky", 3)).toBe(true)
				c.play(2.5, 10)
				expect(faces(c, 3, "a")).toEqual({ "sulky", "sulky" })
				c.play(1, 10)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				expect(c.P.setFace(3, "a", "sulky", 1e9)).toBe(true)
				c.play(60.5, 10)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- sommeil : 300 s au plus
				expect(c.P.react(3, "sleep")).toBe(3)
				all("sleepy")
				expect(c.P.stats().sleepers).toBe(3)
				c.play(299, 10)
				all("sleepy")
				c.play(2, 10)
				all("happy")
				expect(c.P.stats().sleepers).toBe(0)
				-- horloge recalée en arrière : le visage tombe au lieu de durer
				expect(c.P.react(3, "delight", { seconds = 30 })).toBe(3)
				c.Clock.freeze(c.Clock.now() - 500)
				c.play(0.3, 10)
				all("happy")
				c.play(1, 10)
				-- pendant une saynète : la réaction passe devant, puis le visage de la saynète revient
				expect(c.P._play(3, "a", "nap")).toBe(true)
				c.play(0.5, 30)
				expect(faces(c, 3, "a")).toEqual({ "sleepy", "sleepy" })
				expect(c.P.react(3, "surprise", { uid = "a", seconds = 1 })).toBe(1)
				expect(faces(c, 3, "a")).toEqual({ "surprised", "surprised" })
				expect(faces(c, 3, "b")).toEqual({ "happy", "happy" })
				c.play(1.2, 30)
				expect(c.P.sceneOf(3, "a")).toBe("nap")
				expect(faces(c, 3, "a")).toEqual({ "sleepy", "sleepy" })
				c.play(1.6, 30)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- réaction inconnue, ranch illisible, squishy inconnu : rien
				for _, bad in { { 3, "dance" }, { 99, "delight" }, { "3", "delight" }, { 3, nil }, { 3, 5 } } do
					expect(c.P.react(bad[1], bad[2])).toBe(0)
				end
				expect(c.P.react(3, "delight", { uid = "zz" })).toBe(0)
				all("happy")
				c.clean()
			end
		)

		it(
			"achat dans le ranch (Celebrate « tile », première pièce d'une cascade, ElementBuilt) : tous se tournent vers l'objet, Ravi, petit saut, une fois toutes les 2 s au plus par ranch ; « C'est quoi ? » regarde la dernière construction, « ? » au-dessus",
			function()
				local c = client()
				c.snapshot(
					{ ["3"] = ranch(3, 1), ["4"] = ranch(4, 104) },
					{ ["3"] = { a = sq(1), b = sq(2) }, ["4"] = { n1 = sq(5), n2 = sq(3) } }
				)
				farCamera(c)
				c.flags({ Personalities = true })
				c.play(1, 30)
				expect(c.RR.handleOf(4, "n1") ~= nil).toBe(true)
				local pad =
					c.WL.padSocket(3, c.h:require("ReplicatedStorage.Shared.Config.Pads").Defs.snack.socket)
				local count = c.P.stats().reactions
				c.celebrate("tile", { tile = "snack", level = 2 })
				expect(faces(c, 3, "a")).toEqual({ "delighted", "delighted" })
				expect(faces(c, 3, "b")).toEqual({ "delighted", "delighted" })
				expect(faces(c, 4, "n1")).toEqual({ "happy", "happy" })
				expect(c.P.stats().reactions).toBe(count + 1)
				-- petit saut (≈ 0,5 stud pour un corps de 2 studs), puis regard tourné vers la dalle
				local rest = lift(c, 3, "a")
				local dia = c.RR.handleOf(3, "a").spec.displayScale * 2
				local top = 0
				c.play(0.35, 60, function()
					top = math.max(top, lift(c, 3, "a") - rest)
				end)
				-- un quart du diamètre (à l'écrasement de repos près)
				expect({ top > 0.15 * dia and top < 0.35 * dia + 0.1, top, dia }).toEqual({ true, top, dia })
				c.play(0.45, 60)
				expect(looksAt(c, 3, "a", pad) > 0.99).toBe(true)
				expect(looksAt(c, 3, "b", pad) > 0.99).toBe(true)
				-- une seconde dalle moins de 2 s après : aucune nouvelle réaction
				c.celebrate("tile", { tile = "decor", level = 1 })
				expect(c.P.stats().reactions).toBe(count + 1)
				c.play(2.2, 30)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- chez le voisin : première pièce d'une cascade, puis un élément construit (2 s plus tard)
				local spot = c.WL.anchor(4, "vat")
				c.BC.Piece:Fire(4, spot, 1)
				expect(faces(c, 4, "n1")).toEqual({ "delighted", "delighted" })
				expect(faces(c, 4, "n2")).toEqual({ "delighted", "delighted" })
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				c.BC.Piece:Fire(4, spot, 2) -- les pièces suivantes ne relancent rien
				expect(c.P.stats().reactions).toBe(count + 2)
				c.play(2.5, 30)
				expect(faces(c, 4, "n1")).toEqual({ "happy", "happy" })
				c.RR.ElementBuilt:Fire(4, "nothing-drawn") -- élément inconnu : rien
				expect(faces(c, 4, "n1")).toEqual({ "happy", "happy" })
				local realElement = c.RR.elementCFrame
				c.RR.elementCFrame = function(slot, id)
					return if slot == 4 and id == "lighthouse"
						then CFrame.new(spot)
						else realElement(slot, id)
				end
				c.RR.ElementBuilt:Fire(4, "lighthouse")
				expect(faces(c, 4, "n1")).toEqual({ "delighted", "delighted" })
				c.play(2.5, 30)
				-- valeurs hostiles : rien, aucune trace
				for _, bad in { { nil, spot, 1 }, { 99, spot, 1 }, { 4, "x", 1 }, { 4.5, spot, 1 } } do
					c.BC.Piece:Fire(bad[1], bad[2], bad[3])
				end
				c.RR.ElementBuilt:Fire("4", "lighthouse")
				c.RR.ElementBuilt:Fire(4, 12)
				for _, bad in { { tile = "nope" }, { tile = 5 }, {}, "x" } do
					c.celebrate("tile", bad)
				end
				c.h:settle(1)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- « C'est quoi ? » : regarde la dernière construction du ranch (la dalle), « ? » au-dessus
				local labels = c.WT.stats().live
				expect(c.P._play(3, "a", "what")).toBe(true)
				c.play(1, 60)
				-- la dernière construction est la seconde dalle (notée même quand la réaction est retenue)
				local last =
					c.WL.padSocket(3, c.h:require("ReplicatedStorage.Shared.Config.Pads").Defs.decor.socket)
				expect(looksAt(c, 3, "a", last) > 0.99).toBe(true)
				expect(lifeLabels(c)).toEqual({ "?" })
				expect(c.P.stats().labels).toBe(1)
				c.play(1.2, 60)
				expect(lifeLabels(c)).toEqual({})
				expect(c.WT.stats().live).toBe(labels)
				-- « Cœurs » sans joueur à 8 studs ou moins : la saynète se joue, aucune gerbe
				expect(c.P._play(3, "a", "hearts")).toBe(true)
				c.play(1, 60)
				expect({ c.P.stats().bursts, c.VB.used("life", "particles") }).toEqual({ 0, 0 })
				c.play(1.2, 60)
				-- « Bisou au voisin » : un cœur (1 particule, 20 au plus en vie), rendu à la fin de la gerbe
				expect(c.P._play(3, "a", "kiss")).toBe(true)
				c.play(1.2, 60)
				expect({ c.P.stats().bursts, c.VB.used("life", "particles") }).toEqual({ 1, 1 })
				expect(looksAt(c, 3, "a", c.RR.positionOf(3, "b")) > 0.9).toBe(true) -- tourné vers son voisin
				c.play(1.5, 60)
				expect({ c.P.stats().bursts, c.VB.used("life", "particles") }).toEqual({ 0, 0 })
				-- une saynète en cours s'arrête quand le squishy s'endort (le visage du sommeil reste)
				expect(c.P._play(3, "a", "parade")).toBe(true)
				c.play(0.5, 60)
				expect(c.P.react(3, "sleep", { uid = "a" })).toBe(1)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				expect(faces(c, 3, "a")).toEqual({ "sleepy", "sleepy" })
				expect(c.P.react(3, "wake", { uid = "a" })).toBe(1)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- « Mini-sieste » : « z »
				expect(c.P._play(3, "b", "nap")).toBe(true)
				c.play(1, 60)
				expect(lifeLabels(c)).toEqual({ "z" })
				c.play(2.2, 60)
				expect(lifeLabels(c)).toEqual({})
				expect(c.WT.stats().live).toBe(labels)
				c.clean()
			end
		)

		it(
			"série PERFECT ×5 (Ravi), sirène du Rush (Surpris), MEGA qui atterrit à 120 studs ou moins (Surpris), Grand Splorch d'un autre (Étoilé, regard vers la place), début de la Jelly Moon (Étoilé, regard vers le ciel) ; jamais à la première lecture d'EventState",
			function()
				local c = client()
				c.me(c.WL.plaza("center") + Vector3.new(12, 0, 0))
				c.snapshot(
					{ ["3"] = ranch(3, 1, { carry = "k" }) },
					{ ["3"] = { a = sq(1), b = sq(2), k = sq(5) } }
				)
				farCamera(c)
				local now = c.Clock.now()
				local rushOn =
					{ active = true, index = 3, endsAt = now + 300, nextAt = 0, moonBoopable = false }
				-- première lecture (ouverture de l'interrupteur) : un Rush déjà en cours n'est pas une sirène
				c.event({ Personalities = true }, { rush = rushOn })
				c.play(1, 30)
				local function each(face, only)
					for _, uid in only or { "a", "b", "k" } do
						expect({ uid, faces(c, 3, uid) }).toEqual({ uid, { face, face } })
					end
				end
				each("happy")
				expect(c.RR.handleOf(3, "k") ~= nil).toBe(true)
				c.event({ Personalities = true })
				each("happy")
				-- sirène : le Rush commence
				rushOn.index = 4
				c.event({ Personalities = true }, { rush = rushOn })
				each("surprised")
				c.play(2.3, 30)
				each("surprised")
				c.play(0.5, 30)
				each("happy")
				c.event({ Personalities = true })
				-- MEGA : l'annonce ne fait rien ; à l'atterrissage, seul le squishy à 120 studs ou moins du
				-- point de chute réagit (celui que je porte sur la place ; les enclos sont à plus de 190 studs)
				local mega = {
					phase = "warn",
					index = 2,
					landsAt = c.Clock.now() + 5,
					endsAt = c.Clock.now() + 60,
					target = 100,
					points = 0,
					species = 1,
					moon = false,
					result = "",
				}
				c.event({ Personalities = true }, { mega = mega })
				each("happy")
				mega.phase = "press"
				c.event({ Personalities = true }, { mega = mega })
				each("surprised", { "k" })
				each("happy", { "a", "b" })
				c.play(3.3, 30)
				each("happy")
				c.event({ Personalities = true })
				-- Jelly Moon : Étoilé, ceux de l'enclos regardent le ciel au-dessus de la place
				c.event({ Personalities = true }, {
					moon = { active = true, session = 1, endsAt = c.Clock.now() + 600, nextAt = 0 },
				})
				each("starry")
				c.play(1.5, 30)
				local plaza = c.WL.plaza("center")
				expect(looksAt(c, 3, "a", plaza) > 0.99).toBe(true)
				expect(c.RR.handleOf(3, "a").body.CFrame.UpVector.Y < 0.985).toBe(true) -- penché en arrière
				c.play(5, 30)
				each("happy")
				expect(looksAt(c, 3, "a", plaza) < 0.99).toBe(true)
				-- Grand Splorch d'un autre : Étoilé jusqu'à sa fin ; le mien : rien
				local t = c.Clock.now()
				local splorch = {
					userId = 555,
					startedAt = t,
					burstAt = t + 4,
					endsAt = t + 7.5,
					short = true,
					level = 3,
				}
				c.celebrate("splorch", splorch)
				each("starry")
				c.play(1.5, 30)
				expect(looksAt(c, 3, "b", plaza) > 0.99).toBe(true)
				c.play(5.5, 30)
				each("starry")
				c.play(1, 30)
				each("happy")
				t = c.Clock.now()
				c.celebrate(
					"splorch",
					{ userId = 1, startedAt = t, burstAt = t + 4, endsAt = t + 7.5, short = false, level = 3 }
				)
				each("happy")
				for _, bad in
					{ { userId = 555 }, { userId = "x", endsAt = t + 5 }, { userId = 555, endsAt = t - 5 } }
				do
					c.celebrate("splorch", bad)
				end
				each("happy")
				-- série PERFECT : seulement au plus haut de la série (×5)
				c.celebrate("press", { uid = "a", coins = 5, perfect = true, streak = 4, petsit = false })
				each("happy")
				c.celebrate("press", { uid = "a", coins = 5, perfect = false, streak = 5, petsit = false })
				each("happy")
				c.play(1.5, 30)
				c.celebrate("press", { uid = "a", coins = 5, perfect = true, streak = 5, petsit = false })
				each("delighted")
				c.play(2.4, 30)
				each("happy")
				c.clean()
			end
		)

		it(
			"retour dans mon ranch après 60 s dehors : le Meilleur Ami est Ravi, 3 cœurs (jamais à l'arrivée, ni après moins de 60 s) ; joueur immobile 60 s : ceux à 15 studs s'endorment, réveil à l'image où il bouge, 300 s au plus",
			function()
				local c = client()
				local friend = sq(1)
				friend.bf = 1
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = { a = friend, b = sq(2), c = sq(5) } })
				farCamera(c)
				local inside = c.WL.penSlot(3, 1) + Vector3.new(0, 0, 3)
				local outside = c.WL.plaza("center")
				expect(c.WL.inRanch(3, inside)).toBe(true)
				c.me(inside)
				c.flags({ Personalities = true })
				c.play(2.5, 10)
				-- à l'arrivée : rien
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				expect(c.VB.used("life", "particles")).toBe(0)
				-- 30 s dehors : rien
				c.me(outside)
				c.play(30, 10)
				c.me(inside)
				c.play(2, 10)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				expect(c.P.stats().bursts).toBe(0)
				-- 61 s dehors : le Meilleur Ami accueille le joueur
				c.me(outside)
				c.play(61, 10)
				c.me(inside)
				c.play(1.1, 10)
				expect(faces(c, 3, "a")).toEqual({ "delighted", "delighted" })
				expect(faces(c, 3, "b")).toEqual({ "happy", "happy" })
				expect(c.VB.used("life", "particles")).toBe(3)
				expect(c.P.stats().bursts).toBe(1)
				local body = c.RR.handleOf(3, "a").body
				local att = body:FindFirstChild("LifeFx")
				expect(att ~= nil and att:FindFirstChild("Burst") ~= nil).toBe(true)
				-- la gerbe finit, l'attache est rendue (aucune instance laissée sur le modèle)
				c.play(1.5, 10)
				expect(c.VB.used("life", "particles")).toBe(0)
				expect(body:FindFirstChild("LifeFx")).toBe(nil)
				expect(c.P.stats().attachments).toBe(1)
				c.play(1.5, 10)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				-- immobile 60 s : a et b (à moins de 15 studs) s'endorment, c (à 18 studs et plus) non
				c.play(54, 10)
				expect(c.P.stats().sleepers).toBe(0)
				c.play(5, 10)
				expect(faces(c, 3, "a")).toEqual({ "sleepy", "sleepy" })
				expect(faces(c, 3, "b")).toEqual({ "sleepy", "sleepy" })
				expect(faces(c, 3, "c")).toEqual({ "happy", "happy" })
				expect(c.P.stats().sleepers).toBe(2)
				expect(c.P._play(3, "a", "bow")).toBe(false) -- endormi : aucune saynète
				-- le joueur bouge : réveil à l'image même
				c.me(inside + Vector3.new(1.5, 0, 0))
				c.play(1 / 30, 30)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				expect(faces(c, 3, "b")).toEqual({ "happy", "happy" })
				expect(c.P.stats().sleepers).toBe(0)
				-- immobile de nouveau : rendormis ; après 300 s ils se réveillent et ne se rendorment plus tant
				-- que le joueur n'a pas bougé
				c.play(63, 10)
				expect(c.P.stats().sleepers).toBe(2)
				c.play(301, 10)
				expect(c.P.stats().sleepers).toBe(0)
				expect(faces(c, 3, "a")).toEqual({ "happy", "happy" })
				c.play(90, 10)
				expect(c.P.stats().sleepers).toBe(0)
				c.me(inside)
				c.play(63, 10)
				expect(c.P.stats().sleepers).toBe(2)
				c.clean()
			end
		)
	end)

	describe("Personality › tours appris (lot B5, étape 2)", function()
		it(
			"seuils 100, 1 200, 1e6, 1e9, 1e12 : la 4e saynète d'un squishy qui connaît un tour est son plus beau tour (taille du squishy chez les autres) ; sous 100 : jamais de tour",
			function()
				local c = client()
				local sizes = { t0 = 99, t1 = 100, t2 = 1200, t3 = 1e6, t4 = 1e9, t5 = 1e12 }
				local expected = { t1 = "peekaboo", t2 = "spin", t3 = "flip", t4 = "dance", t5 = "fireworks" }
				local squishies = {}
				for uid, z in sizes do
					local s = sq(1)
					s.z = z
					squishies[uid] = s
				end
				c.snapshot({ ["3"] = ranch(3, 1), ["4"] = ranch(4, 104) }, { ["3"] = {}, ["4"] = squishies })
				for uid, z in sizes do
					expect({ uid, c.WSC.sizeOf(4, uid) }).toEqual({ uid, z })
				end
				local mid = (c.WL.penSlot(4, 3) + c.WL.penSlot(4, 4)) / 2
				c.camera(mid + Vector3.new(0, 10, 0))
				c.flags({ Personalities = true })
				local seq, current = {}, {}
				for uid in sizes do
					seq[uid] = {}
				end
				c.play(150, 30, function()
					for uid in sizes do
						local id = c.P.sceneOf(4, uid)
						if id ~= current[uid] then
							current[uid] = id
							if id then
								table.insert(seq[uid], id)
							end
						end
					end
				end)
				local curious = c.Scenes.of("curious")
				for uid in sizes do
					expect({ uid, #seq[uid] >= 4 }).toEqual({ uid, true })
					for i, id in seq[uid] do
						if i % 4 == 0 and expected[uid] then
							expect({ uid, i, id }).toEqual({ uid, i, expected[uid] })
						else
							expect({ uid, i, id, table.find(curious, id) ~= nil }).toEqual({
								uid,
								i,
								id,
								true,
							})
						end
					end
				end
				expect(c.P.stats().tricks >= 5).toBe(true)
				c.clean()
			end
		)

		it(
			"« Bravo » (emote de sorte 3) : le Meilleur Ami n° 1 du ranch de ce joueur joue son plus beau tour (record de MON Étagère pour le mien), s'il est dessiné en détail complet ; les autres emotes, un Meilleur Ami sans tour, une limite pleine (le tour attend une place 3 s au plus)",
			function()
				local c = client()
				c.h:fireClient(REMOTES .. "DataSnapshot", { trophies = trophies(c, { [5] = 1e9 }) })
				local squishies = {}
				for i = 1, 7 do
					squishies["s" .. i] = sq(2)
				end
				local friend = sq(5)
				friend.bf = 1
				squishies.a = friend
				local second = sq(1)
				second.bf = 2
				second.z = 1e12
				squishies.b = second
				local neighbour = sq(1)
				neighbour.bf = 1
				neighbour.z = 2000
				c.snapshot(
					{ ["3"] = ranch(3, 1), ["4"] = ranch(4, 104) },
					{ ["3"] = squishies, ["4"] = { n1 = neighbour } }
				)
				farCamera(c)
				c.flags({ Personalities = true })
				c.play(1, 30)
				local function emote(userId, kind)
					c.h:fireClient(REMOTES .. "EmoteShow", { userId = userId, kind = kind, emote = "bravo" })
				end
				emote(1, 1)
				emote(1, 2)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				emote(1, 3)
				expect(c.P.sceneOf(3, "a")).toBe("dance") -- record 1e9 de MON Étagère, pas sa taille (50)
				expect(c.P.sceneOf(3, "b")).toBe(nil) -- Meilleur Ami n° 2
				emote(1, 3) -- un second Bravo ne coupe ni ne relance le tour
				c.play(1, 30)
				expect(c.P.sceneOf(3, "a")).toBe("dance")
				expect(c.P.stats().started).toBe(1)
				c.play(2.2, 30)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				-- le voisin : son Meilleur Ami est en détail réduit vu d'ici (plus de 60 studs) : rien
				emote(104, 3)
				expect(c.P.sceneOf(4, "n1")).toBe(nil)
				c.camera(c.WL.penSlot(4, 1) + Vector3.new(0, 30, -40))
				c.play(1, 30)
				emote(104, 3)
				expect(c.P.sceneOf(4, "n1")).toBe("spin") -- sa taille : 2 000
				c.play(2, 30)
				farCamera(c)
				c.play(1, 30)
				-- un joueur sans ranch, un ranch sans Meilleur Ami, une charge hostile : rien
				emote(999, 3)
				emote("x", 3)
				c.h:fireClient(REMOTES .. "EmoteShow", "bravo")
				-- limite pleine : le tour attend qu'une place se libère
				expect(c.P._play(3, "s1", "startle")).toBe(true)
				for i = 2, 6 do
					expect(c.P._play(3, "s" .. i, "nap")).toBe(true)
				end
				expect(c.P.stats().running).toBe(6)
				expect(c.P._play(3, "s7", "nap")).toBe(false) -- une 7e ne commence jamais
				emote(1, 3)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				expect(c.P.stats().wanting).toBe(1)
				c.play(1.1, 30)
				expect(c.P.sceneOf(3, "a")).toBe("dance")
				expect(c.P.stats().wanting).toBe(0)
				expect(c.P.stats().running).toBe(6)
				c.play(3.5, 30)
				expect(c.P.stats().running).toBe(0)
				-- limite pleine, puis le Meilleur Ami devient la cible du jeu : la demande tombe, aucun tour
				for i = 1, 6 do
					expect(c.P._play(3, "s" .. i, "nap")).toBe(true)
				end
				c.play(0.2, 30)
				emote(1, 3)
				expect(c.P.stats().wanting).toBe(1)
				local startedBefore = c.P.stats().started
				c.RR.highlightTarget(3, "a")
				c.play(3.2, 30)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				expect(c.P.stats().wanting).toBe(0)
				expect(c.P.stats().started).toBe(startedBefore)
				emote(1, 3) -- ciblé : rien non plus
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				c.RR.highlightTarget(nil, nil)
				-- Meilleur Ami sans tour (record sous 100) : rien
				c.h:fireClient(REMOTES .. "DataPatch", { trophies = trophies(c, { [5] = 60 }) }, {})
				emote(1, 3)
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				c.clean()
			end
		)

		it(
			"nouveau tour d'une de MES espèces : annoncé une fois par séance et par (espèce, tour), jamais au chargement ni à la réouverture de l'interrupteur ; message trick.new, son TrickPop (repli Pop tant qu'il est muet)",
			function()
				local c = client()
				local Util = c.h:require(CLIENT .. "World.Util")
				local learned = {}
				c.P.TrickLearned:Connect(function(species, id)
					table.insert(learned, species .. ":" .. id)
				end)
				local function patch(over)
					c.h:fireClient(
						REMOTES .. "DataPatch",
						{ trophies = if type(over) == "table" then trophies(c, over) else over },
						{}
					)
				end
				local function text(id)
					return Util.t("trick.new", { name = Util.t("trick." .. id) })
				end
				expect(text("spin")).toBe("New trick: Spin!")
				expect(c.Strings.fr["trick.new"]).toBe("Nouveau tour : {name} !")
				expect(c.Strings.en["trick.new"]).toBe("New trick: {name}!")
				c.h:fireClient(REMOTES .. "DataSnapshot", { trophies = trophies(c, { [1] = 150, [2] = 5 }) })
				drawn3(c)
				c.flags({ Personalities = true })
				c.play(2, 30)
				-- au chargement : rien, même si l'espèce 1 connaît déjà « Coucou »
				expect(c.toasts).toEqual({})
				expect(c.sounds).toEqual({})
				patch({ [1] = 150, [2] = 120 })
				expect(c.toasts).toEqual({ text("peekaboo") })
				expect(c.sounds).toEqual({ "Pop" })
				expect(learned).toEqual({ "2:peekaboo" })
				-- même tour : plus jamais dans la séance (record qui monte sans changer de tour, qui retombe et remonte)
				patch({ [1] = 150, [2] = 130 })
				patch({ [1] = 150, [2] = 50 })
				patch({ [1] = 150, [2] = 140 })
				expect(#c.toasts).toBe(1)
				patch({ [1] = 150, [2] = 1500 })
				expect(c.toasts[2]).toBe(text("spin"))
				-- plusieurs seuils d'un coup : le plus beau tour seulement
				patch({ [1] = 2e12, [2] = 1500 })
				expect(c.toasts[3]).toBe(text("fireworks"))
				expect(#c.toasts).toBe(3)
				-- interrupteur coupé : rien ; rouvert : la première lecture ne fait qu'armer
				c.flags(nil)
				patch({ [1] = 2e12, [2] = 1500, [3] = 2e6 })
				c.flags({ Personalities = true })
				c.play(1, 30)
				expect(#c.toasts).toBe(3)
				patch({ [1] = 2e12, [2] = 1500, [3] = 3e9 })
				expect(c.toasts[4]).toBe(text("dance"))
				-- beaucoup d'espèces d'un coup : 3 annonces au plus (les autres sont connues sans message)
				patch({
					[1] = 2e12,
					[2] = 1500,
					[3] = 3e9,
					[10] = 100,
					[11] = 100,
					[12] = 100,
					[13] = 100,
					[14] = 100,
				})
				expect(#c.toasts).toBe(7)
				patch({
					[1] = 2e12,
					[2] = 1500,
					[3] = 3e9,
					[10] = 100,
					[11] = 100,
					[12] = 100,
					[13] = 100,
					[14] = 100,
				})
				expect(#c.toasts).toBe(7)
				-- profil illisible : rien, aucune trace
				patch("x")
				patch({ [1] = "big", [2] = 0 / 0 })
				c.h:fireClient(REMOTES .. "DataPatch", { trophies = { a = 5, [1] = {} } }, {})
				expect(#c.toasts).toBe(7)
				expect(#c.sounds).toBe(7)
				expect(c.P.stats().announced).toBe(7)
				c.clean()
			end
		)
	end)

	describe("Personality › ola, vermicelles et Prairie (lot B5, étape 2)", function()
		it(
			"la ola (Personality.wave) : un bond par squishy de l'enclos, colonne par colonne ; hauteur divisée par 2 en Mouvement réduit",
			function()
				local c = client()
				local squishies, uids = {}, {}
				for i = 1, 12 do
					local uid = string.format("s%02d", i)
					squishies[uid] = sq(1)
					table.insert(uids, uid)
				end
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = squishies })
				farCamera(c)
				c.flags({ Personalities = true })
				c.play(1.5, 30)
				local dia = c.RR.handleOf(3, uids[1]).spec.displayScale * 2
				-- hauteur atteinte et instant où chaque squishy décolle (0,12 diamètre au-dessus du repos)
				local function wave()
					local rest, peakAt, peak = {}, {}, {}
					for _, uid in uids do
						rest[uid] = lift(c, 3, uid)
						peak[uid] = 0
					end
					expect(c.P.wave(3)).toBe(12)
					local t = 0
					c.play(1.3, 60, function(_, dt)
						t += dt
						for _, uid in uids do
							local up = lift(c, 3, uid) - rest[uid]
							peak[uid] = math.max(peak[uid], up)
							if peakAt[uid] == nil and up > 0.12 * dia then
								peakAt[uid] = t
							end
						end
					end)
					return peak, peakAt
				end
				local peak, peakAt = wave()
				for i = 1, 6 do
					local top, bottom = uids[i], uids[i + 6] -- même colonne, deux rangées
					-- la moitié du diamètre (à l'écrasement de repos près)
					expect({ i, peak[top] > 0.38 * dia and peak[top] < 0.62 * dia + 0.1, peak[top], dia }).toEqual({
						i,
						true,
						peak[top],
						dia,
					})
					expect({ i, math.abs(peakAt[top] - peakAt[bottom]) < 0.02 }).toEqual({ i, true })
					if i > 1 then
						-- la colonne suivante bondit après la précédente (0,6 s d'un bord à l'autre)
						local gap = peakAt[top] - peakAt[uids[i - 1]]
						expect({ i, gap > 0.08 and gap < 0.16 }).toEqual({ i, true })
					end
				end
				c.Prefs.reducedMotion = function()
					return true
				end
				c.play(1.5, 30)
				local reduced = wave()
				expect(reduced[uids[1]] > 0.17 * dia and reduced[uids[1]] < 0.33 * dia + 0.1).toBe(true)
				expect({ c.P.wave(99), c.P.wave("3"), c.P.wave(nil), c.P.wave(7) }).toEqual({ 0, 0, 0, 0 })
				c.clean()
			end
		)

		it(
			"vermicelles d'une cascade (BuildCascade.Piece) : 12 par construction, 24 pour un achat groupé, répartis sur les pièces ; une cascade interrompue ne déborde pas sur la suivante",
			function()
				local c = client()
				drawn3(c)
				farCamera(c)
				c.flags({ Personalities = true })
				c.play(1, 30)
				local jobs, total = 1, 1
				c.BC.playing = function()
					return jobs, total
				end
				local function cascade(n, fired)
					table.clear(c.bursts)
					total = n
					for i = 1, fired or n do
						c.Clock.advance(0.04)
						c.BC.Piece:Fire(3, Vector3.new(i, 5, 0), i)
					end
					local sum = 0
					for _, b in c.bursts do
						sum += b.n
						expect(b.pos.Y).toBe(6) -- 1 stud au-dessus de la pièce
					end
					c.Clock.advance(1)
					return sum, #c.bursts
				end
				expect({ cascade(1) }).toEqual({ 12, 1 })
				expect({ cascade(2) }).toEqual({ 12, 2 })
				expect({ cascade(5) }).toEqual({ 12, 3 })
				local sum, bursts = cascade(40)
				expect(sum).toBe(12)
				expect(bursts).toBe(3)
				expect(c.bursts[1].pos.X < c.bursts[2].pos.X and c.bursts[2].pos.X < c.bursts[3].pos.X).toBe(
					true
				)
				expect(c.bursts[3].pos.X > 30).toBe(true) -- jusqu'aux dernières pièces
				-- achat groupé : deux jobs ou plus dans la même cascade
				jobs = 3
				expect((cascade(20))).toBe(24)
				jobs = 1
				-- cascade interrompue (4 pièces sur 10), puis la suivante : son propre budget
				local cut = cascade(10, 4)
				expect(cut <= 12).toBe(true)
				expect((cascade(6))).toBe(12)
				expect(c.P.stats().sprinkles).toBe(12 * 5 + 24 + cut)
				-- interrupteur coupé : plus rien
				c.flags(nil)
				expect((cascade(6))).toBe(0)
				c.clean()
			end
		)

		it(
			"Prairie des copains : les 12 derniers relâchés de MON profil, en détail réduit, à meadowPoint(i) ; Prairie v2 quand MON ranch porte Monuments ; seulement caméra à 140 studs ou moins ; rebond à 15 Hz ; la boucle vit pour elle seule",
			function()
				local c = client()
				local built = {}
				local realBuild = c.SB.build
				c.SB.build = function(spec, parent)
					local handle = realBuild(spec, parent)
					if parent ~= nil and parent.Name == "Meadow" then
						table.insert(built, { species = spec.species, lod = spec.lod, handle = handle })
					end
					return handle
				end
				local function meadow()
					local world = c.h.workspace:FindFirstChild("ClientWorld")
					local folder = world and world:FindFirstChild("Meadow")
					return if folder then #folder:GetChildren() else 0
				end
				local released = {}
				for i = 1, 14 do
					released[i] = { s = (i % 5) + 1, m = 0 }
				end
				c.h:fireClient(REMOTES .. "DataSnapshot", { released = released })
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = {} })
				local center = c.WL.meadowCenter()
				c.camera(center + Vector3.new(0, 20, 400))
				c.flags({ Personalities = true })
				c.play(2, 30)
				-- loin : rien de construit, mais la boucle tourne (des relâchés à montrer), sans aucun squishy de ranch
				expect(meadow()).toBe(0)
				expect(c.P.stats().records).toBe(0)
				expect(c.P.stats().stepping).toBe(1)
				c.camera(center + Vector3.new(0, 20, 138))
				c.play(2, 30)
				expect(meadow()).toBe(12)
				expect(c.P.stats().meadow).toBe(12)
				expect(#built).toBe(12)
				for i, b in built do
					-- les 12 derniers (les entrées 3 à 14), en détail réduit, chacun à sa place
					expect({ i, b.species, b.lod }).toEqual({ i, released[i + 2].s, 2 })
					expect({ i, c.flat(b.handle.body.CFrame.Position, c.WL.meadowPoint(i)) < 0.01 }).toEqual({
						i,
						true,
					})
				end
				-- rebond de repos à 15 Hz : 15 poses par seconde, pas 60
				local writes = 0
				local conn = built[1].handle.body.Changed:Connect(function(prop)
					if prop == "CFrame" then
						writes += 1
					end
				end)
				c.play(1, 60)
				conn:Disconnect()
				expect(writes >= 14 and writes <= 16).toBe(true)
				-- entre 140 et 150 studs : elle reste ; au-delà : rendue ; de retour à 140 : reconstruite
				c.camera(center + Vector3.new(0, 20, 146))
				c.play(1.5, 30)
				expect(meadow()).toBe(12)
				c.camera(center + Vector3.new(0, 20, 152))
				c.play(1.5, 30)
				expect(meadow()).toBe(0)
				c.camera(center + Vector3.new(0, 20, 146))
				c.play(1.5, 30)
				expect(meadow()).toBe(0)
				c.camera(center + Vector3.new(0, 20, 60))
				c.play(1.5, 30)
				expect(meadow()).toBe(12)
				-- MON ranch porte Monuments : la Prairie v2 (jardin du quartier nord)
				table.clear(built)
				c.ranchModel(3):SetAttribute("Monuments", "1")
				local v2 = c.WL.meadowCenter(true)
				c.camera(v2 + Vector3.new(0, 20, 40))
				c.play(2.5, 30)
				expect(meadow()).toBe(12)
				expect(#built).toBe(12)
				for i, b in built do
					expect({ i, c.flat(b.handle.body.CFrame.Position, c.WL.meadowPoint(i, true)) < 0.01 }).toEqual({
						i,
						true,
					})
				end
				table.clear(built)
				c.ranchModel(3):SetAttribute("Monuments", nil)
				c.camera(center + Vector3.new(0, 20, 40))
				c.play(2.5, 30)
				expect(#built).toBe(12)
				expect(c.flat(built[5].handle.body.CFrame.Position, c.WL.meadowPoint(5)) < 0.01).toBe(true)
				-- un relâché de plus : les 12 derniers changent
				table.clear(built)
				table.insert(released, { s = 9, m = 0 })
				c.h:fireClient(REMOTES .. "DataPatch", { released = released }, {})
				c.play(2.5, 30)
				expect(#built).toBe(12)
				expect(built[12].species).toBe(9)
				expect(built[1].species).toBe(released[4].s)
				-- entrées illisibles ignorées ; liste vide : plus rien, et la boucle s'arrête
				c.h:fireClient(
					REMOTES .. "DataPatch",
					{ released = { { s = 999, m = 0 }, "x", { s = "1" }, { s = 2 } } },
					{}
				)
				c.play(2.5, 30)
				expect(meadow()).toBe(1)
				c.h:fireClient(REMOTES .. "DataPatch", { released = {} }, {})
				c.play(2.5, 30)
				expect(meadow()).toBe(0)
				expect(c.P.stats().stepping).toBe(0)
				c.h:fireClient(REMOTES .. "DataPatch", { released = "x" }, {})
				c.play(2.5, 30)
				expect(meadow()).toBe(0)
				expect(c.P.stats().stepping).toBe(0)
				c.clean()
			end
		)
	end)

	-- =========================================================================================
	-- Étape 2 : interrupteur coupé, coupure en direct, longue durée, coût
	-- =========================================================================================

	-- 16 ranchs occupés (le 3 est le mien), `per` squishies chacun, espèces variées ; le n° 1 de chaque
	-- ranch est son Meilleur Ami (taille 5 000 : il connaît « Toupie »)
	local function sixteen(per, edit)
		local ranches, squishies = {}, {}
		for slot = 1, 16 do
			ranches[tostring(slot)] = ranch(slot, if slot == 3 then 1 else 100 + slot)
			local list = {}
			for i = 1, per do
				local s = sq((slot * 7 + i * 3) % 26 + 1)
				if i == 1 then
					s.bf = 1
					s.z = 5000
				end
				list[string.format("q%02d", i)] = s
			end
			squishies[tostring(slot)] = list
		end
		if edit then
			edit(ranches, squishies)
		end
		return ranches, squishies
	end

	describe("Personality › interrupteur, fuites et coût (lot B5, étape 2)", function()
		it(
			"interrupteur coupé : zéro appel de pose, zéro instance, zéro connexion, zéro boucle, quoi qu'il arrive (achats, série, Rush, MEGA, Splorch, Bravo, cascade, records, relâchés, joueur immobile)",
			function()
				local c = client()
				local calls = 0
				local realPose = c.P.pose
				c.P.pose = function(...)
					calls += 1
					return realPose(...)
				end
				local released = {}
				for i = 1, 5 do
					released[i] = { s = i, m = 0 }
				end
				c.h:fireClient(
					REMOTES .. "DataSnapshot",
					{ released = released, trophies = trophies(c, { [1] = 50 }) }
				)
				local friend = sq(1)
				friend.bf = 1
				friend.z = 5000
				c.snapshot({ ["3"] = ranch(3, 1) }, { ["3"] = { a = friend, b = sq(2), c = sq(5) } })
				c.near()
				c.me(c.WL.penSlot(3, 1) + Vector3.new(0, 0, 3))
				c.play(2, 30)
				local base = c.h:counts()
				local instances = #c.h.game:GetDescendants()
				local labels = c.WT.stats().live
				local function storm(v2)
					local now = c.Clock.now()
					c.celebrate("tile", { tile = "snack", level = 2 })
					c.celebrate("press", { uid = "a", coins = 5, perfect = true, streak = 5, petsit = false })
					c.celebrate("splorch", {
						userId = 555,
						startedAt = now,
						burstAt = now + 4,
						endsAt = now + 7.5,
						short = true,
						level = 3,
					})
					c.event(v2, {
						rush = {
							active = true,
							index = 3,
							endsAt = now + 300,
							nextAt = 0,
							moonBoopable = false,
						},
					})
					c.event(v2, {
						mega = {
							phase = "press",
							index = 2,
							landsAt = now,
							endsAt = now + 60,
							target = 100,
							points = 0,
							species = 1,
							moon = false,
							result = "",
						},
						moon = { active = true, session = 1, endsAt = now + 600, nextAt = 0 },
					})
					c.event(v2)
					c.h:fireClient(REMOTES .. "EmoteShow", { userId = 1, kind = 3, emote = "bravo" })
					c.BC.Piece:Fire(3, c.WL.anchor(3, "vat"), 1)
					c.RR.ElementBuilt:Fire(3, "lighthouse")
					c.h:fireClient(
						REMOTES .. "DataPatch",
						{ trophies = trophies(c, { [1] = 2e6 }), released = released },
						{}
					)
				end
				storm(nil)
				storm({ PhotoMode = true, Hearts = true, Carnet = true }) -- d'autres interrupteurs ouverts, pas celui-ci
				c.camera(c.WL.meadowCenter() + Vector3.new(0, 20, 40))
				c.play(3, 30)
				c.near()
				c.play(70, 10) -- joueur immobile plus de 60 s
				expect(calls).toBe(0)
				local stats = c.P.stats()
				expect({
					stats.records,
					stats.connections,
					stats.stepping,
					stats.meadow,
					stats.running,
					stats.faced,
				}).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect({ #c.toasts, #c.sounds, #c.bursts }).toEqual({ 0, 0, 0 })
				expect(c.VB.declared("life")).toBe(false)
				expect(c.h:counts().connections).toBe(base.connections)
				expect(c.h:counts().threads).toBe(base.threads)
				expect(#c.h.game:GetDescendants()).toBe(instances)
				expect(c.WT.stats().live).toBe(labels)
				expect({ named(c, "Meadow"), named(c, "LifeFx"), named(c, "LifeLabel") }).toEqual({ 0, 0, 0 })
				expect({
					c.P.setFace(3, "a", "starry"),
					c.P.wave(3),
					c.P.react(3, "delight"),
					c.P._play(3, "a", "nap"),
				}).toEqual({
					false,
					0,
					0,
					false,
				})
				expect(c.P.sceneOf(3, "a")).toBe(nil)
				for _, uid in { "a", "b", "c" } do
					expect(c.SB.faceOf(c.RR.handleOf(3, uid))).toBe("happy")
				end
				c.clean()
			end
		)

		it(
			"coupure en direct : saynètes, visages, étiquettes, gerbes et Prairie rendus AVANT que Changed parte, connexions et boucle coupées ; rouvert : tout repart",
			function()
				local c = client()
				-- mon ranch : le plus proche de la Prairie (les deux doivent être dessinés ensemble)
				local center = c.WL.meadowCenter()
				local slot, best = 1, math.huge
				for s = 1, 16 do
					local d = c.flat(c.WL.penSlot(s, 1), center)
					if d < best then
						slot, best = s, d
					end
				end
				local cam = c.WL.penSlot(slot, 1) + Vector3.new(0, 30, 0)
				expect(c.flat(cam, center) < 135).toBe(true)
				local released = {}
				for i = 1, 12 do
					released[i] = { s = i, m = 0 }
				end
				c.h:fireClient(REMOTES .. "DataSnapshot", { released = released })
				local key = tostring(slot)
				c.snapshot(
					{ [key] = ranch(slot, 1) },
					{ [key] = { a = sq(2), b = sq(5), c = sq(1), d = sq(4) } }
				)
				c.camera(cam)
				c.me(c.WL.penSlot(slot, 2) + Vector3.new(0, 0, 2))
				c.play(1, 30)
				-- UI/WorldText branche ses propres écoutes à sa première étiquette (une fois par séance) : faites
				-- avant le relevé, elles ne sont pas à ce module
				c.WT.release(c.WT.create(c.RR.handleOf(slot, "a").body, { kind = "plus", maxDistance = 10 }))
				local base = c.h:counts()
				local labels = c.WT.stats().live
				-- instances par classe et par nom, hors de la réserve d'étiquettes de UI/WorldText (une étiquette
				-- rendue y reste, éteinte)
				local function instances()
					local pool = c.h.workspace:FindFirstChild("WorldText")
					local census = {}
					for _, d in c.h.game:GetDescendants() do
						if d ~= pool and not (pool and d:IsDescendantOf(pool)) then
							local key = d.ClassName .. " " .. d.Name
							census[key] = (census[key] or 0) + 1
						end
					end
					return census
				end
				local function difference(before, after)
					local out = {}
					for key, n in after do
						if n ~= (before[key] or 0) then
							table.insert(out, string.format("%s %+d", key, n - (before[key] or 0)))
						end
					end
					for key, n in before do
						if after[key] == nil then
							table.insert(out, string.format("%s %+d", key, -n))
						end
					end
					table.sort(out)
					return table.concat(out, " ; ")
				end
				local before0 = instances()
				c.flags({ Personalities = true })
				c.play(3, 30)
				expect(c.P.stats().meadow).toBe(12)
				-- une saynète avec étiquette et visage, une avec des cœurs, une réaction, un tour qui attend
				for _, uid in { "a", "b", "c", "d" } do
					if c.P.sceneOf(slot, uid) ~= nil then
						c.play(3.2, 30)
					end
				end
				local started = 0
				for _, try in { { "a", "nap" }, { "b", "hearts" } } do
					if c.P._play(slot, try[1], try[2]) then
						started += 1
					end
				end
				expect(started).toBe(2)
				expect(c.P.react(slot, "starry", { uid = "d", seconds = 30 })).toBe(1)
				c.play(0.6, 30)
				local before = c.P.stats()
				expect(before.running >= 2).toBe(true)
				expect(before.labels).toBe(1)
				expect(before.bursts >= 1).toBe(true)
				expect(before.faced >= 3).toBe(true)
				expect(before.connections >= 7).toBe(true)
				expect(named(c, "LifeFx") >= 1).toBe(true)
				local atChange = nil
				c.P.Changed:Connect(function()
					local s = c.P.stats()
					local sad = 0
					for _, uid in { "a", "b", "c", "d" } do
						if c.SB.faceOf(c.RR.handleOf(slot, uid)) ~= "happy" then
							sad += 1
						end
					end
					atChange = {
						s.records,
						s.running,
						s.faced,
						s.labels,
						s.bursts,
						s.attachments,
						s.meadow,
						s.connections,
						s.stepping,
						s.particles,
						sad,
						named(c, "Meadow"),
						named(c, "LifeFx"),
						#lifeLabels(c),
						c.WT.stats().live - labels,
					}
				end)
				c.flags(nil)
				expect(table.concat(atChange, " ")).toBe("0 0 0 0 0 0 0 0 0 0 0 0 0 0 0")
				c.play(1, 30)
				-- aucune connexion de plus qu'avant l'ouverture (+ l'écoute de ce test ; la réserve de UI/WorldText
				-- peut en rendre une)
				expect(c.h:counts().connections <= base.connections + 1).toBe(true)
				expect(c.h:counts().threads).toBe(base.threads)
				expect(difference(before0, instances())).toBe("")
				-- rouvert : saynètes et Prairie repartent
				c.flags({ Personalities = true })
				c.play(2.5, 30)
				expect(c.P.stats().meadow).toBe(12)
				expect(c.P.stats().records).toBe(4)
				c.clean()
			end
		)

		it(
			"6 h d'horloge figée avec 16 ranchs (graine fixe) : aucune fuite d'instance, de connexion ni de fil, tables stables, limites tenues (saynètes, 20 particules, 6 étiquettes, 6 attaches)",
			function()
				local started = os.clock()
				local c = client()
				local low = false
				c.Prefs.lowGraphics = function()
					return low
				end
				-- hasard à graine fixe (générateur congruentiel)
				local seed = 20261110
				local function rand(n)
					seed = (seed * 1103515245 + 12345) % 2147483648
					return seed % n + 1
				end
				local released = {}
				for i = 1, 12 do
					released[i] = { s = i, m = 0 }
				end
				local records = trophies(c, {})
				c.h:fireClient(REMOTES .. "DataSnapshot", { released = released, trophies = records })
				c.snapshot(sixteen(6))
				local V2 = { Personalities = true }
				local function visit(k)
					local at = c.WL.penSlot(k, 2)
					c.me(at + Vector3.new(0, 0, 2))
					c.camera(at + Vector3.new(0, 9, -8))
				end
				visit(3)
				c.flags(V2)
				local most =
					{ running = 0, particles = 0, labels = 0, attachments = 0, records = 0, over = 0 }
				local function watch()
					local s = c.P.stats()
					most.running = math.max(most.running, s.running)
					most.particles = math.max(most.particles, s.particles)
					most.labels = math.max(most.labels, s.labels)
					most.attachments = math.max(most.attachments, s.attachments)
					most.records = math.max(most.records, s.records)
					if s.running > s.cap then
						most.over += 1
					end
				end
				-- état calme comparable : interrupteur ouvert, monde de départ, joueur et caméra chez moi,
				-- un grand spectacle de 8 s (aucune saynète, étiquettes et gerbes finies), visages retombés
				local function quiet()
					low = false
					c.flags(V2)
					c.snap(sixteen(6))
					c.RR.highlightTarget(nil, nil)
					visit(3)
					local now = c.Clock.now()
					c.event(V2, {
						spectacle = {
							current = {
								kind = "dance",
								userId = 77,
								startedAt = now,
								burstAt = now + 1,
								endsAt = now + 20,
								level = 1,
							},
							queue = {},
						},
					})
					c.play(14, 10, watch)
					local s = c.P.stats()
					local counts = c.h:counts()
					local snapshot = {
						instances = #c.h.game:GetDescendants(),
						connections = counts.connections,
						threads = counts.threads,
						running = s.running,
						faced = s.faced,
						sleepers = s.sleepers,
						labels = s.labels,
						bursts = s.bursts,
						particles = s.particles,
						meadow = s.meadow,
						wanting = s.wanting,
						moduleConnections = s.connections,
						worldText = c.WT.stats().live,
					}
					-- squishies suivis : ceux que RanchRenderer a posés depuis l'ouverture, jamais plus que de modèles
					expect(s.records >= 1 and s.records <= c.RR.stats().models).toBe(true)
					c.event(V2)
					return snapshot
				end
				local snapshots = {}
				local frames = 0
				local ids, forced = allIds(c.Scenes), 0
				for step = 1, 720 do
					c.Clock.advance(30 - 12 / 30)
					local k = (step - 1) % 16 + 1
					visit(k)
					c.play(4 / 30, 30, watch) -- les squishies du ranch visité sont posés avant l'action
					local now = c.Clock.now()
					local action = step % 12
					if action == 0 then
						c.celebrate("tile", { tile = "snack", level = 1 + step % 5 })
					elseif action == 1 then
						c.celebrate(
							"press",
							{ uid = "q01", coins = 5, perfect = true, streak = 5, petsit = false }
						)
					elseif action == 2 then
						c.celebrate("splorch", {
							userId = 100 + k,
							startedAt = now,
							burstAt = now + 4,
							endsAt = now + 7.5,
							short = true,
							level = 2,
						})
					elseif action == 3 then
						c.event(V2, {
							rush = {
								active = true,
								index = step,
								endsAt = now + 120,
								nextAt = 0,
								moonBoopable = false,
							},
						})
					elseif action == 4 then
						c.event(
							V2,
							{ moon = { active = true, session = step, endsAt = now + 600, nextAt = 0 } }
						)
					elseif action == 5 then
						c.event(V2, {
							mega = {
								phase = "press",
								index = step,
								landsAt = now,
								endsAt = now + 60,
								target = 100,
								points = 0,
								species = 1,
								moon = false,
								result = "",
							},
						})
					elseif action == 6 then
						c.event(V2, {
							spectacle = {
								current = {
									kind = "ascend",
									userId = 100 + k,
									startedAt = now,
									burstAt = now + 4,
									endsAt = now + 6,
									level = 1,
								},
								queue = {},
							},
						})
					elseif action == 7 then
						c.event(V2)
						c.h:fireClient(
							REMOTES .. "EmoteShow",
							{ userId = if k == 3 then 1 else 100 + k, kind = 3, emote = "bravo" }
						)
					elseif action == 8 then
						for i = 1, 3 do
							c.BC.Piece:Fire(k, c.WL.anchor(k, "vat") + Vector3.new(i, 0, 0), i)
						end
						c.P.wave(k)
					elseif action == 9 then
						local species = rand(26)
						records[species] = math.max(records[species], 1) * 40
						c.h:fireClient(REMOTES .. "DataPatch", { trophies = table.clone(records) }, {})
					elseif action == 10 then
						table.remove(released, 1)
						table.insert(released, { s = rand(26), m = 0 })
						c.h:fireClient(REMOTES .. "DataPatch", { released = table.clone(released) }, {})
						c.camera(c.WL.meadowCenter() + Vector3.new(0, 20, 30 + rand(60)))
					else
						-- une pression, une cible, et chaque saynète et chaque tour à son tour, joués en entier
						-- (étiquettes « z » et « ? », cœurs, étoiles, gerbe du Feu d'artifice)
						c.RR.play(k, "q02", "press")
						c.RR.highlightTarget(k, "q03")
						if c.P._play(k, "q04", ids[(step // 12) % #ids + 1]) then
							forced += 1
						end
						c.play(1.4, 30, watch)
						frames += 42
					end
					if step % 60 == 30 then
						c.flags(nil) -- coupure en direct
					elseif step % 60 == 31 then
						c.flags(V2)
					end
					if step % 45 == 0 then
						low = not low
					end
					if step % 90 == 45 then
						-- le ranch visité perd deux squishies, un autre joueur part
						c.snap(sixteen(6, function(ranches, squishies)
							squishies[tostring(k)].q05 = nil
							squishies[tostring(k)].q06 = nil
							local gone = tostring(k % 16 + 1)
							ranches[gone] = nil
							squishies[gone] = nil
						end))
					elseif step % 90 == 46 then
						c.snap(sixteen(6))
					end
					c.play(8 / 30, 30, watch)
					frames += 12
					if step % 240 == 0 then
						table.insert(snapshots, quiet())
					end
				end
				expect(#snapshots).toBe(3)
				expect(snapshots[2]).toEqual(snapshots[1])
				expect(snapshots[3]).toEqual(snapshots[1])
				expect({
					snapshots[3].running,
					snapshots[3].labels,
					snapshots[3].bursts,
					snapshots[3].particles,
					snapshots[3].faced,
				}).toEqual({
					0,
					0,
					0,
					0,
					0,
				})
				-- limites tenues à chaque image
				expect(most.over).toBe(0)
				expect(most.running <= 6 and most.running >= 3).toBe(true)
				expect(most.particles <= 20 and most.particles >= 12).toBe(true)
				expect(most.labels <= 6 and most.labels >= 1).toBe(true)
				expect(most.attachments <= 6 and most.attachments >= 1).toBe(true)
				expect(forced >= 40).toBe(true)
				local s = c.P.stats()
				expect(s.started > 300).toBe(true)
				expect(s.tricks > 10).toBe(true)
				expect(s.announced > 5).toBe(true)
				print(
					string.format(
						"  6 h de personnalités : 720 étapes, %d images, %d saynètes commencées (%d finies, %d coupées, %d tours), %d réactions, %d annonces, au plus %d saynètes / %d particules / %d étiquettes / %d attaches / %d squishies suivis ; instances %d, connexions %d, fils %d aux trois points calmes ; %.1f s",
						frames,
						s.started,
						s.finished,
						s.cut,
						s.tricks,
						s.reactions,
						s.announced,
						most.running,
						most.particles,
						most.labels,
						most.attachments,
						most.records,
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
			"aucune table ni fonction créée par image : les fonctions par image de World/Personality ne contiennent ni constructeur de table ni fermeture",
			function()
				local src = fs.readFile("src/client/World/Personality.luau")
				local PER_FRAME = {
					"function Personality.pose(",
					"function Personality._step(",
					"local function compose(",
					"local function meadowStep(",
					"local function expireFaces(",
					"local function expireFx(",
					"local function expireLabels(",
					"local function sceneTick(",
				}
				for _, header in PER_FRAME do
					local from = string.find(src, header, 1, true)
					expect({ header, from ~= nil }).toEqual({ header, true })
					local to = string.find(src, "\nend\n", from, true)
					local body = string.sub(src, from, to)
					-- commentaires retirés
					body = string.gsub(body, "%-%-[^\n]*", "")
					expect({ header, string.find(body, "{", 1, true) ~= nil }).toEqual({ header, false })
					expect({ header, string.find(body, "function%(") ~= nil }).toEqual({ header, false })
				end
			end
		)

		it(
			"coût par image avec 16 ranchs construits (méthode du lot B4) : RanchRenderer._step avec et sans Personalities, Personality._step, image complète",
			function()
				local c = client()
				c.h:fireClient(REMOTES .. "DataSnapshot", { trophies = trophies(c, {}) })
				c.snapshot(sixteen(12))
				local at = (
					c.WL.penSlot(3, 3)
					+ c.WL.penSlot(3, 4)
					+ c.WL.penSlot(3, 9)
					+ c.WL.penSlot(3, 10)
				) / 4
				c.me(at)
				c.camera(at + Vector3.new(0, 14, -6))
				c.play(4, 30)
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
				local stats = c.RR.stats()
				local offStep = best(c.RR._step)
				local offFrame = best(whole)
				c.flags({ Personalities = true })
				c.play(25, 30) -- les saynètes tournent
				local running, samples = 0, 0
				local onFrame = best(function(dt)
					whole(dt)
					running += c.P.stats().running
					samples += 1
				end)
				local onStep = best(c.RR._step)
				local own = best(c.P._step)
				print(
					string.format(
						"  16 ranchs × 12 squishies (%d modèles, %d pièces, %d animés à pleine cadence) : RanchRenderer._step %.3f ms coupé, %.3f ms ouvert ; image complète (RenderStepped) %.3f ms coupé, %.3f ms ouvert (%.1f saynètes en cours en moyenne, %d squishies suivis) ; Personality._step seul %.3f ms",
						stats.models,
						stats.parts,
						stats.animated,
						offStep,
						onStep,
						offFrame,
						onFrame,
						running / math.max(1, samples),
						c.P.stats().records,
						own
					)
				)
				-- garde large (le moteur simulé est bruyant) : les personnalités ne doublent pas l'image
				expect(onFrame < offFrame * 2 + 1).toBe(true)
				expect(own < 0.5).toBe(true)
				c.clean()
			end
		)
	end)
end
