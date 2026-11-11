--!nocheck
-- Lot B5, étape 6 (vérification du lot ; docs/04 §27.10 « VisualBudget jamais dépassé », §17.2 robot de
-- longue durée ; plan B5 Q1, D29, D30) : le VRAI client complet (Main.client, console PS5, profil v2)
-- avec TOUS les interrupteurs du lot B5 ouverts (Personalities, Helpers, JellyAscend, PetitSplorch,
-- Weather, Fete, PhotoMode) et les autres interrupteurs v2.0 annoncés au client (features.v2,
-- ambience), 16 ranchs de 8 squishies, 6 Plopettes par ranch :
--   * 6 h sur l'horloge figée (720 étapes de 30 s, graine fixe) : saynètes, réactions, sauts des
--     Plopettes (HelperPress de 16 ranchs à chaque étape), siestes et pauses, Petits Splorchs,
--     Ascensions et Pluies d'étoiles, Palier, record, Chantier, emotes v2.0, fenêtres de météo, niveaux
--     de fête, entrées et sorties du mode photo (sticks, L2 / R2, □), jumelles (ouvertes, fermées, en
--     s'éloignant), Rush, MEGA, Lune, coupure en direct de chaque interrupteur ; aux trois points
--     calmes : mêmes instances, connexions et fils ; chaque système de VisualBudget dans son budget à
--     chaque image ; zéro trace ;
--   * coût par image avec 16 ranchs construits (méthode du lot B4 : meilleur de 5 × 300 appels), tous
--     interrupteurs coupés puis tous ouverts : RanchRenderer._step, HelperRenderer._step,
--     VFXController._step, CameraController._step et l'image complète ; aucune table ni fermeture
--     créée dans les fonctions par image des modules du lot.
-- Tout est en 3D : ces cas prouvent la structure ; personne n'a pu regarder l'image elle-même.
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")
local TvAudit = require("../harness/TvAudit")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame

local DONE = { step = 11, done = true, demoDone = true }
local REMOTES = "ReplicatedStorage.Remotes."
local UIDS = { "q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8" }

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	-- tous les interrupteurs annoncés au client (13 de la liste fixe)
	local FLAGS = {}
	for k, v in UpgradeScreen.V2_ALL do
		FLAGS[k] = v
	end
	FLAGS.Personalities = true
	FLAGS.PhotoMode = true

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 5 + slot,
			fame = slot,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 2, decor = 1, pens = 1, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0.5,
			growth = { G = 100, g = 1, t = 1800000000 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = slot % 26 + 1, m = 0, z = 5000, zg = 0 },
		}
	end

	-- Client complet, profil v2, mon ranch 1 ; 16 ranchs de 8 squishies ; les ranchs 2 à 16
	-- appartiennent aux joueurs 100 + k (le 2 au joueur 102, présent pour les jumelles)
	local function client()
		local c = S.client({ profile = { version = 2, onboarding = DONE } })
		local h = c.h
		c.me = h.localPlayer.UserId
		c.WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		c.Cam = TvAudit.mod(h, "Controllers.CameraController")
		c.RR = TvAudit.mod(h, "Controllers.RanchRenderer")
		c.HR = TvAudit.mod(h, "Controllers.HelperRenderer")
		c.VFX = TvAudit.mod(h, "Controllers.VFXController")
		c.B = TvAudit.mod(h, "UI.Binoculars")
		c.VB = TvAudit.mod(h, "Render.VisualBudget")
		c.P = TvAudit.mod(h, "World.Personality")
		c.SH = TvAudit.mod(h, "World.ShowsV2")
		c.EM = TvAudit.mod(h, "World.Emotes")
		c.BP = TvAudit.mod(h, "World.BigPlop")
		c.WX = TvAudit.mod(h, "World.WeatherFx")
		c.FE = TvAudit.mod(h, "World.Fete")
		c.WT = TvAudit.mod(h, "UI.WorldText")
		c.camera = h.workspace.CurrentCamera
		c.seq = 1
		c.models = {}
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local list = child(child(h.workspace, "Wobbleton", "Folder"), "Ranches", "Folder")
		for slot = 1, 16 do
			c.models[slot] = child(list, tostring(slot), "Model")
			c.models[slot]:SetAttribute("Slot", slot)
		end
		function c.owner(slot)
			return if slot == 1 then c.me else 100 + slot
		end
		function c.world(gone)
			local ranches, squishies = {}, {}
			for slot = 1, 16 do
				ranches[tostring(slot)] = ranch(slot, if gone == slot then 0 else c.owner(slot))
				local s = {}
				if gone ~= slot then
					for i, uid in UIDS do
						s[uid] = TvAudit.squishy((slot + i) % 26 + 1, {
							z = 400 * i,
							st = i % 4,
							o = if i == 2 then "plopBib" elseif i == 3 then "partyHat" else "",
						})
					end
				end
				squishies[tostring(slot)] = s
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
				c.models[slot]:SetAttribute(k, v)
			end
			h:settle(1)
		end
		function c.event(v2, over)
			local ev = UpgradeScreen.eventState(v2, over and over.spectacle)
			if v2 then
				ev.features.ambience = true
			end
			for k, v in over or {} do
				if k ~= "spectacle" then
					ev[k] = v
				end
			end
			h:fireClient(REMOTES .. "EventState", ev)
			h:settle(1)
		end
		function c.cele(kind, data)
			h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = data })
			h:settle(1)
		end
		-- une image du client complet (Heartbeat, RenderStepped…) après l'horloge
		function c.frame(dt)
			c.Clock.advance(dt)
			h:step(dt, 1)
		end
		function c.play(seconds, fps, watch)
			local dt = 1 / (fps or 30)
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				c.frame(dt)
				if watch then
					watch()
				end
			end
			h:settle(1)
		end
		function c.at(pos)
			if h.localPlayer.Character == nil then
				h:respawn(h.localPlayer)
			end
			h:moveTo(h.localPlayer, pos + Vector3.new(0, 3, 0))
		end
		c.world()
		return c
	end

	describe("Life_longrun › lot B5, étape 6 : tous les interrupteurs ouverts", function()
		it(
			"6 h d'horloge figée (graine fixe) dans le client complet, 16 ranchs × 6 Plopettes, spectacles, météo, fête, mode photo, jumelles : instances, connexions et fils identiques aux trois points calmes ; VisualBudget tenu à chaque image ; zéro trace",
			function()
				local started = os.clock()
				local c = client()
				local h = c.h
				local seed = 20261111
				local function rand(n)
					seed = (seed * 1103515245 + 12345) % 2147483648
					-- bits de poids fort (les bits faibles d'un générateur congruentiel modulo 2^31 ont
					-- des périodes courtes)
					return (seed // 65536) % n + 1
				end
				-- un joueur proche (emotes v2.0)
				local friend = h:addPlayer({ userId = 50 })
				c.event(FLAGS)
				for slot = 1, 16 do
					c.attrs(slot, { Helpers = 6, HelperMode = "active" })
				end
				c.at(c.WL.penSlot(1, 5))
				h:moveTo(friend, c.WL.penSlot(1, 6) + Vector3.new(0, 3, 0))
				c.play(1)
				-- chaque système déclaré dans son budget, à chaque image
				local over, peak = 0, {}
				local function watch()
					for name, s in c.VB.stats() do
						if s.used > s.parts or s.usedParticles > s.particles or s.usedLights > s.lights then
							over += 1
						end
						peak[name] = math.max(peak[name] or 0, s.used)
					end
				end
				local counters =
					{ photo = 0, bino = 0, binoWalk = 0, ascend = 0, petit = 0, weather = 0, fete = 0 }
				-- point calme : tout ouvert, aucun spectacle, ni météo ni fête, mode photo et jumelles
				-- fermés, chez moi, 16 ranchs × 6 Plopettes actives ; 16 s d'images (coupures dures
				-- 12 s au plus, visages et étiquettes finis)
				local function quiet()
					if c.Cam.photoOn() then
						c.Cam.photo(false)
					end
					if c.B.isOpen() then
						c.B.close()
					end
					c.event(FLAGS)
					c.world()
					for slot = 1, 16 do
						c.attrs(slot, { Helpers = 6, HelperMode = "active" })
					end
					c.at(c.WL.penSlot(1, 5))
					h:moveTo(friend, c.WL.penSlot(1, 6) + Vector3.new(0, 3, 0))
					-- caméra du jeu derrière le personnage (le moteur simulé ne la fait pas suivre) : le
					-- niveau de détail des squishies dépend de la caméra
					c.camera.CameraType = Enum.CameraType.Custom
					c.camera.CFrame =
						CFrame.lookAt(c.WL.penSlot(1, 5) + Vector3.new(0, 12, -14), c.WL.penSlot(1, 5))
					c.play(50, 30, watch)
					-- les 10 dernières secondes sous la danse de Big Plop : aucune saynète ne commence,
					-- gerbes, étiquettes et visages des saynètes finis (comme le point calme de
					-- Personality.spec)
					local now = c.Clock.now()
					c.event(FLAGS, {
						spectacle = {
							current = {
								kind = "dance",
								userId = 0,
								startedAt = now,
								burstAt = now + 1,
								endsAt = now + 30,
								level = 1,
							},
							queue = {},
						},
					})
					c.play(10, 30, watch)
					local counts = h:counts()
					-- réserves bornées (pas des fuites) : étiquettes rangées de UI/WorldText (64 par sorte
					-- au plus) et étoiles dessinées à la première étoile d'un modèle de la réserve de
					-- RanchRenderer (1 + 3 × 5 au plus par modèle, B5-4) ; leur contenu dépend de l'ordre
					-- de réutilisation
					local function pooled()
						local n = 0
						local wt = h.workspace:FindFirstChild("WorldText")
						if wt then
							n += #wt:GetDescendants()
						end
						local cw = h.workspace:FindFirstChild("ClientWorld")
						for _, d in (if cw then cw:GetDescendants() else {}) do
							if d.Name == "Stars" and d:IsA("BillboardGui") then
								n += 1 + #d:GetDescendants()
							end
						end
						return n
					end
					-- copies de sons encore vivantes (AudioController : détruites à Ended ou par
					-- task.delay(maxLength) en temps RÉEL sous Lune, jamais sur l'horloge figée) : une
					-- instance, une connexion Ended et un fil en attente chacune
					local voices = 0
					for _, d in h.game:GetService("SoundService"):GetChildren() do
						if d:IsA("Sound") then
							voices += 1
						end
					end
					local function looping()
						return c.SH.stats().looping
							+ c.EM.stats().looping
							+ c.WX.stats().looping
							+ c.FE.stats().looping
					end
					return {
						instances = #h.game:GetDescendants() - pooled() - voices,
						worldText = c.WT.stats().live,
						-- chaque étiquette de UI/WorldText (vivante ou rangée) garde sa connexion Destroying
						connections = counts.connections - voices - c.WT.stats().live - c.WT.stats().pooled,
						threads = counts.threads - voices,
						looping = looping(),
						weatherParts = c.WX.stats().parts,
						feteParts = c.FE.stats().parts,
						helpers = c.HR.stats().drawn,
						photo = c.Cam.photoOn(),
						lease = c.Cam.leaseHolder(),
						fg = c.FG.anyOpen(),
						shows = c.VB.used("shows"),
					}
				end
				local snapshots = {}
				local frames = 0
				for step = 1, 720 do
					c.Clock.advance(30 - 10 / 30)
					local now = c.Clock.now()
					local k = (step - 1) % 16 + 1
					local action = step % 12
					-- le joueur visite un ranch (détail complet : ce ranch et ses 2 voisins)
					if step % 3 == 0 then
						c.at(c.WL.penSlot(k, 5))
					end
					if action == 0 then
						-- fin du MEGA de l'étape d'avant (un grand spectacle fait taire le Petit Splorch, B5-40)
						c.event(FLAGS)
						c.attrs(k, { PetitSplorchAt = now })
						c.attrs(1, { PetitSplorchAt = now })
						c.cele(
							"petitSplorch",
							{ userId = c.me, startedAt = now, endsAt = now + 2.5, level = 2 }
						)
						counters.petit += 1
					elseif action == 1 then
						local hero = if step % 24 == 1 then c.me else c.owner(k)
						local data = {
							userId = hero,
							ascend = 3,
							startR = 0,
							bestR = 15,
							startedAt = now,
							burstAt = now + 4,
							endsAt = now + 10,
							flyer = { s = 1, m = 0, st = 0, z = 2 },
						}
						c.event(FLAGS, {
							spectacle = {
								current = {
									kind = "ascend",
									userId = hero,
									startedAt = now,
									burstAt = now + 4,
									endsAt = now + 10,
									level = 1,
								},
								queue = {},
							},
						})
						c.cele("ascend", data)
						c.play(4.5, 30, watch)
						frames += 135
						c.cele("giftRain", {
							heroId = hero,
							heroName = "P",
							coins = 5,
							uid = "",
							species = 1,
							short = false,
						})
						counters.ascend += 1
					elseif action == 2 then
						c.event(FLAGS, { weather = { kind = rand(4), endsAt = now + 200 + rand(100) } })
						counters.weather += 1
					elseif action == 3 then
						c.event(FLAGS, { fete = { level = rand(6) - 1 } })
						counters.fete += 1
					elseif action == 4 then
						-- mode photo : sticks, L2 / R2, □, puis sortie (○ ou par le jeu)
						c.at(c.WL.penSlot(1, 4))
						if c.Cam.photo(true) then
							counters.photo += 1
							for i = 1, 30 do
								local r = rand(4)
								if r == 1 then
									Gamepad.stick(
										h,
										Enum.KeyCode.Thumbstick1,
										Vector2.new(rand(3) - 2, rand(3) - 2)
									)
								elseif r == 2 then
									Gamepad.stick(
										h,
										Enum.KeyCode.Thumbstick2,
										Vector2.new(rand(3) - 2, rand(3) - 2)
									)
								elseif r == 3 then
									Gamepad.tap(
										h,
										if i % 2 == 0 then Enum.KeyCode.ButtonL2 else Enum.KeyCode.ButtonR2
									)
								else
									Gamepad.tap(h, Enum.KeyCode.ButtonX)
								end
								c.frame(1 / 30)
								watch()
							end
							frames += 30
							Gamepad.stick(h, Enum.KeyCode.Thumbstick1, Vector2.zero)
							Gamepad.stick(h, Enum.KeyCode.Thumbstick2, Vector2.zero)
							if step % 24 == 4 then
								Gamepad.tap(h, Enum.KeyCode.ButtonB)
							else
								c.Cam.photo(false)
							end
							h:settle(1)
							expect(c.Cam.photoOn()).toBe(false)
						end
					elseif action == 5 then
						-- jumelles devant le portail du ranch 2 : ○, fermeture du jeu, ou s'éloigner
						c.at(c.WL.gateOutside(2) - Vector3.new(0, 3, 0))
						c.play(0.3, 30, watch)
						if c.B.open(c.owner(2)) then
							counters.bino += 1
							c.play(1, 30, watch)
							frames += 30
							local how = (step // 12) % 3
							if how == 0 then
								Gamepad.tap(h, Enum.KeyCode.ButtonB)
							elseif how == 1 then
								c.B.close()
							else
								c.at(c.WL.toWorld(2, Vector3.new(0, 0, -20)))
								counters.binoWalk += 1
							end
							c.play(0.3, 30, watch)
							expect(c.B.isOpen()).toBe(false)
						end
					elseif action == 6 then
						c.cele("tier", { family = "tapis", tier = 1 + rand(5), key = "tier1" })
						c.cele("recordStep", { share = 0.75 })
						c.cele("regainDone", { bestR = 15, confetti = 3 })
					elseif action == 7 then
						h:fireClient(
							REMOTES .. "EmoteShow",
							{ userId = 50, kind = 3, emote = c.EM.IDS[rand(#c.EM.IDS)] }
						)
						h:fireClient(
							REMOTES .. "EmoteShow",
							{ userId = c.owner(k), kind = 3, emote = "bravo" }
						)
						h:settle(1)
					elseif action == 8 then
						-- Chantier : un élément v2.0 arrive (premier passage) dans un ranch en détail complet
						c.at(c.WL.penSlot(k, 5))
						c.play(0.2, 30, watch)
						local at = CFrame.new(c.WL.helperHouse(k))
						local real = c.RR.elementCFrame
						c.RR.elementCFrame = function()
							return at
						end
						c.RR.ElementBuilt:Fire(k, "lantern")
						h:settle(1)
						c.RR.elementCFrame = real
					elseif action == 9 then
						c.attrs(k, { HelperMode = if step % 24 == 9 then "nap" else "paused" })
					elseif action == 10 then
						c.event(FLAGS, {
							rush = {
								active = true,
								index = step,
								endsAt = now + 60,
								nextAt = 0,
								moonBoopable = false,
							},
						})
					else
						c.event(FLAGS, {
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
						c.attrs(k, { HelperMode = "active", Helpers = rand(7) - 1 })
					end
					-- un message HelperPress par ranch, jusqu'à 6 sauts
					for slot = 1, 16 do
						local presses = {}
						for i = 1, rand(6) do
							presses[i] =
								{ helper = i, uid = UIDS[rand(8)], tPress = c.Clock.now() + rand(30) / 10 }
						end
						h:fireClient(REMOTES .. "HelperPress", { ownerId = c.owner(slot), presses = presses })
					end
					h:settle(1)
					-- coupures en direct : tout le lot, puis chaque interrupteur à son tour
					if step % 60 == 30 then
						c.event(nil)
					elseif step % 60 == 31 then
						c.event(FLAGS)
					elseif step % 60 == 45 then
						local cut = table.clone(FLAGS)
						cut[({ "Personalities", "JellyAscend", "PetitSplorch", "PhotoMode", "Hearts" })[(step // 60) % 5 + 1]] =
							nil
						c.event(cut)
					elseif step % 60 == 46 then
						c.event(FLAGS)
					end
					if step % 90 == 45 then
						c.world(k % 15 + 2) -- un joueur part
					elseif step % 90 == 46 then
						c.world()
					end
					c.play(10 / 30, 30, watch)
					frames += 10
					if step % 240 == 0 then
						table.insert(snapshots, quiet())
						frames += 1800
					end
				end
				expect(#snapshots).toBe(3)
				expect(snapshots[2]).toEqual(snapshots[1])
				expect(snapshots[3]).toEqual(snapshots[1])
				expect({ snapshots[1].looping, snapshots[1].shows, snapshots[1].photo, snapshots[1].fg }).toEqual({
					0,
					0,
					false,
					false,
				})
				expect(over).toBe(0)
				for _, n in { "photo", "bino", "binoWalk", "ascend", "petit", "weather", "fete" } do
					expect({ n, counters[n] > 0 }).toEqual({ n, true })
				end
				local hs, ss, es = c.HR.stats(), c.SH.stats(), c.EM.stats()
				expect(hs.jumps > 1000).toBe(true)
				expect(ss.petits > 0 and ss.starRains > 0).toBe(true)
				expect(es.shown > 0).toBe(true)
				expect(c.P.stats().started > 100).toBe(true)
				local names = {}
				for name in peak do
					table.insert(names, name)
				end
				table.sort(names)
				local parts = {}
				for _, name in names do
					table.insert(parts, string.format("%s %d/%d", name, peak[name], c.VB.stats()[name].parts))
				end
				print(
					string.format(
						"  6 h, tous les interrupteurs : %d images ; %d saynètes, %d sauts de Plopettes, %d Petits Splorchs, %d Ascensions (%d Pluies d'étoiles), %d emotes, %d Chantiers, %d fenêtres de météo, %d niveaux de fête, %d entrées en mode photo, %d vues des jumelles (%d fermées en s'éloignant) ; pièces au plus (budget) : %s ; instances %d, connexions %d, fils %d aux trois points calmes ; %.1f s",
						frames,
						c.P.stats().started,
						hs.jumps,
						ss.petits,
						ss.ascends,
						ss.starRains,
						es.shown,
						c.BP.stats().chantiers,
						counters.weather,
						counters.fete,
						counters.photo,
						counters.bino,
						counters.binoWalk,
						table.concat(parts, ", "),
						snapshots[3].instances,
						snapshots[3].connections,
						snapshots[3].threads,
						os.clock() - started
					)
				)
				S.clean(c, expect)
			end
		)

		it(
			"coût par image avec 16 ranchs construits (méthode du lot B4), interrupteurs coupés puis tous ouverts : RanchRenderer, HelperRenderer, VFXController, CameraController et l'image complète",
			function()
				local c = client()
				local h = c.h
				c.event(nil)
				c.at(c.WL.penSlot(1, 5))
				c.play(3)
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
					h:settle(1)
					return out
				end
				local function whole(dt)
					h:step(dt, 1)
				end
				local function measure()
					return {
						rr = best(c.RR._step),
						hr = best(c.HR._step),
						vfx = best(c.VFX._step),
						cam = best(c.Cam._step),
						frame = best(whole),
					}
				end
				local off = measure()
				local offInstances = #h.game:GetDescendants()
				-- tout ouvert : Plopettes, météo (bulles), fête niveau 5, Ascension d'un voisin, saynètes,
				-- puis le mode photo pendant la dernière mesure de la caméra
				c.event(FLAGS)
				for slot = 1, 16 do
					c.attrs(slot, { Helpers = 6, HelperMode = "active" })
				end
				local now = c.Clock.now()
				c.event(FLAGS, { weather = { kind = 3, endsAt = now + 600 }, fete = { level = 5 } })
				c.play(20)
				local on = measure()
				now = c.Clock.now()
				c.cele("ascend", {
					userId = 102,
					ascend = 3,
					startR = 0,
					bestR = 15,
					startedAt = now,
					burstAt = now + 4,
					endsAt = now + 600,
					flyer = { s = 1, m = 0, st = 0, z = 2 },
				})
				c.attrs(2, { PetitSplorchAt = now })
				local show = { vfx = best(c.VFX._step), frame = best(whole) }
				expect(c.Cam.photo(true)).toBe(true)
				Gamepad.stick(h, Enum.KeyCode.Thumbstick2, Vector2.new(0.6, 0.3))
				local photo = { cam = best(c.Cam._step), frame = best(whole) }
				Gamepad.stick(h, Enum.KeyCode.Thumbstick2, Vector2.zero)
				c.Cam.photo(false)
				h:settle(1)
				print(
					string.format(
						"  16 ranchs × 8 squishies, %d instances coupé : ms par image (coupé → ouvert) : RanchRenderer._step %.3f → %.3f ; HelperRenderer._step %.3f → %.3f (%d Plopettes dessinées) ; VFXController._step %.3f → %.3f (%.3f pendant une Ascension et un Petit Splorch) ; CameraController._step %.3f → %.3f (%.3f en mode photo) ; image complète %.3f → %.3f (%.3f pendant les spectacles, %.3f en mode photo)",
						offInstances,
						off.rr,
						on.rr,
						off.hr,
						on.hr,
						c.HR.stats().drawn,
						off.vfx,
						on.vfx,
						show.vfx,
						off.cam,
						on.cam,
						photo.cam,
						off.frame,
						on.frame,
						show.frame,
						photo.frame
					)
				)
				-- gardes larges (moteur simulé bruyant) : coupé, les modules du lot ne coûtent rien de plus
				-- qu'un test ; ouvert, l'image ne double pas
				expect(off.hr < 0.05).toBe(true)
				expect(on.frame < off.frame * 2 + 2).toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"aucune table ni fermeture créée par image : fonctions par image des modules du lot B5 (HelperRenderer, ShowsV2, Emotes, BigPlop, WeatherFx, Fete, CameraController)",
			function()
				local PER_FRAME = {
					["src/client/Controllers/HelperRenderer.luau"] = { "function HelperRenderer._step(" },
					["src/client/World/ShowsV2.luau"] = { "function ShowsV2._step(" },
					["src/client/World/Emotes.luau"] = { "function Emotes._step(" },
					["src/client/World/BigPlop.luau"] = { "function BigPlop._step(" },
					["src/client/World/WeatherFx.luau"] = { "function WeatherFx._step(" },
					["src/client/World/Fete.luau"] = { "function Fete._step(" },
					["src/client/Controllers/CameraController.luau"] = {
						"function CameraController._step(",
						"local function stepPhoto(",
						"local function stepBinoculars(",
					},
				}
				for path, headers in PER_FRAME do
					local src = fs.readFile(path)
					for _, header in headers do
						local from = string.find(src, header, 1, true)
						expect({ header, from ~= nil }).toEqual({ header, true })
						local to = string.find(src, "\nend\n", from, true)
						local body = string.gsub(string.sub(src, from, to), "%-%-[^\n]*", "")
						-- les chaînes « … » ne contiennent pas d'accolade dans ces fonctions
						expect({ header, string.find(body, "{", 1, true) ~= nil }).toEqual({ header, false })
						expect({ header, string.find(body, "function%(") ~= nil }).toEqual({ header, false })
					end
				end
			end
		)
	end)
end
