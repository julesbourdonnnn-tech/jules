--!nocheck
-- Mode photo « Cheese ! » et zoom des jumelles (lot B5, étape 5 ; GDD v2.0 §7.5, §10.4, §10.6 ; docs/04
-- §27.5 SetPhotoMode, §27.13 N22 ; plan B5 W3, W4, D24-D28) :
--   * 1 000 entrées et sorties mêlées au hasard (graine fixe) à des spectacles, des jumelles, des
--     réapparitions, des coupures de l'interrupteur, des panneaux ouverts par une carte, ○, ✕ sur le
--     bouton : type, sujet, focale et CFrame de la caméra rendus EXACTEMENT, même ensemble de
--     ScreenGuis rallumés, aucun sauvetage de FocusGuard, aucune instance de plus ;
--   * point visé et caméra dans leurs bornes pour 10 000 appuis de sticks au hasard dans les trois zones ;
--   * aucune propriété du personnage écrite ; SetPhotoMode : au plus une fois par 1,2 s, dernier état
--     voulu seulement, jamais égal au dernier envoyé ;
--   * manette : chaque bouton en mode photo n'envoie AUCUNE intention sauf SetPhotoMode ; le ✕ qui ouvre
--     depuis le menu ne ressort jamais aussitôt ; ○ ramène au jeu en un appui ; glyphes PS5, Xbox et
--     clavier ; interrupteur coupé : ni ligne, ni mode photo, ni intention ;
--   * jumelles : vue atteinte, caméra rendue à chaque fermeture (propriétaire parti compris), centre du
--     ranch projeté au-dessus de la carte en 720p, 1080p et 4K, s'éloigner referme.
-- Personne n'a pu regarder la vue de la caméra elle-même : ces cas prouvent la structure.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame

local OWNER = 22
local DONE = { step = 11, done = true, demoDone = true }

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local FLAGS = {}
	for k, v in UpgradeScreen.V2_ALL do
		FLAGS[k] = v
	end
	FLAGS.PhotoMode = true
	local NO_PHOTO = table.clone(FLAGS)
	NO_PHOTO.PhotoMode = nil

	-- tirage à graine fixe (générateur congruentiel : Random n'existe pas sous Lune)
	local function newRng(seed)
		local rng = {}
		function rng:NextNumber(a, b)
			seed = (seed * 1103515245 + 12345) % 2147483648
			local u = seed / 2147483648
			if a == nil then
				return u
			end
			return a + (b - a) * u
		end
		function rng:NextInteger(a, b)
			return a + math.floor(self:NextNumber() * (b - a + 1))
		end
		return rng
	end

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "",
			hidden = true,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = 1800000000 },
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

	local function model(c, slot, attrs)
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local m = child(
			child(child(c.h.workspace, "Wobbleton", "Folder"), "Ranches", "Folder"),
			tostring(slot),
			"Model"
		)
		for k, v in attrs do
			m:SetAttribute(k, v)
		end
	end

	-- Client console, profil v2, mon ranch 1, le voisin OWNER au ranch 2 ; opts.flags, opts.viewport
	local function client(opts)
		opts = opts or {}
		local c = S.client({ profile = { version = 2, onboarding = DONE }, viewport = opts.viewport })
		local me = c.h.localPlayer.UserId
		c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = { ["1"] = ranch(1, me), ["2"] = ranch(2, OWNER), ["3"] = ranch(3, 0) },
			squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {} },
		})
		c.h:settle(1)
		model(c, 2, { BestR = 5 })
		S.event(c, opts.flags or FLAGS)
		c.Cam = TvAudit.mod(c.h, "Controllers.CameraController")
		c.Hud = TvAudit.mod(c.h, "UI.PhotoHud")
		c.B = TvAudit.mod(c.h, "UI.Binoculars")
		c.WL = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		c.camera = c.h.workspace.CurrentCamera
		c.me = me
		-- debout dans mon ranch, face au Pot
		c.h:moveTo(c.h.localPlayer, c.WL.toWorld(1, Vector3.new(0, 3, 30)))
		c.camera.CameraType = Enum.CameraType.Custom
		c.camera.FieldOfView = 70
		c.camera.CFrame =
			CFrame.lookAt(c.WL.toWorld(1, Vector3.new(0, 14, 12)), c.WL.toWorld(1, Vector3.new(0, 3, 30)))
		local hum = c.h.localPlayer.Character and c.h.localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			c.camera.CameraSubject = hum
		end
		S.run(c, 0.5)
		return c
	end

	-- Images du jeu (pas de 0,25 s : les boucles comptent en dt)
	local function play(c, seconds, dt)
		dt = dt or 0.25
		for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
			c.Clock.advance(dt)
			c.h:step(dt, 1)
		end
		c.h:settle(1)
	end

	local function camState(c)
		local cam = c.camera
		return {
			type = cam.CameraType,
			subject = cam.CameraSubject,
			fov = cam.FieldOfView,
			cframe = tostring(cam.CFrame),
		}
	end

	local function enabledGuis(c)
		local out = {}
		for _, g in c.h.localPlayer.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled then
				table.insert(out, g.Name)
			end
		end
		table.sort(out)
		return table.concat(out, ",")
	end

	local function instances(c)
		local n = #c.h.localPlayer.PlayerGui:GetDescendants()
		local w = c.h.workspace:FindFirstChild("ClientWorld")
		return n + (if w then #w:GetDescendants() else 0)
	end

	-- Intentions envoyées depuis `from` ; « ClientEvent qualityReduced » (QualityController : les images
	-- longues des specs font baisser la qualité) n'est pas une action du joueur et n'est pas comptée
	local function intents(c, from)
		local out = {}
		for i = from + 1, #c.h.log.serverEvents do
			local e = c.h.log.serverEvents[i]
			if not (e.remote == "ClientEvent" and e.args[1] == "qualityReduced") then
				table.insert(out, e.remote)
			end
		end
		return out
	end

	-- Entrée depuis le menu : ligne « Mode photo » des Réglages, ✕ appuyé et relâché
	local function enterFromMenu(c)
		c.PC.closeAll()
		S.run(c, 0.5)
		c.PC.open("Settings")
		S.run(c, 0.6)
		local Settings = TvAudit.mod(c.h, "UI.Panels.Settings")
		local row = Settings._controlFor("photo")
		expect(row ~= nil).toBe(true)
		S.select(c, row)
		Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
		c.h:settle(1)
		return row
	end

	describe("CameraController_photo › entrée et sortie (lot B5, étape 5)", function()
		it(
			"depuis les Réglages : ✕ ferme le menu et entre ; HUD caché localement, bouton « Exit photo mode » choisi avec ○ PS5 ; le ✕ d'ouverture tenu ou répété tout de suite ne ressort pas ; ○ ramène au jeu en un appui ; Cheese → Click",
			function()
				local c = client()
				local before = camState(c)
				local guis = enabledGuis(c)
				local rescues = c.FG.rescues()
				enterFromMenu(c)
				expect(c.Cam.photoOn()).toBe(true)
				expect(c.PC.menuOpen()).toBe(false)
				expect(c.FG.names()).toEqual({ "photo" })
				expect(c.FG.top().blocking).toBe(true)
				expect(S.selected(c)).toBe(c.Hud.exitButton())
				expect(c.Hud.exitButton().Label.Text).toBe("Exit photo mode")
				expect(enabledGuis(c)).toBe("PhotoHud")
				expect(c.camera.CameraType).toBe(Enum.CameraType.Scriptable)
				-- glyphe du bouton : ○ de la PS5
				local g = c.Hud.exitButton():FindFirstChild("Glyph", true)
				expect(g:GetAttribute("GlyphKey")).toBe("ButtonB")
				expect(g:GetAttribute("GlyphMode")).toBe("image")
				-- ✕ répété tout de suite (garde d'ouverture) puis ✕ tenu 2 s : toujours en photo
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				expect(c.Cam.photoOn()).toBe(true)
				Gamepad.press(c.h, Enum.KeyCode.ButtonA)
				play(c, 2)
				expect(c.Cam.photoOn()).toBe(true)
				Gamepad.release(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				-- l'appui avait commencé pendant la garde d'ouverture : son relâchement n'agit pas
				expect(c.Cam.photoOn()).toBe(true)
				-- un NOUVEL appui de ✕ sur le bouton : sortie
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				c.h:settle(1)
				expect(c.Cam.photoOn()).toBe(false)
				expect(c.FG.anyOpen()).toBe(false)
				expect(camState(c)).toEqual(before)
				expect(enabledGuis(c)).toBe(guis)
				-- ○ : un seul appui, retour au JEU (pas au menu)
				enterFromMenu(c)
				expect(c.Cam.photoOn()).toBe(true)
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				c.h:settle(1)
				expect(c.Cam.photoOn()).toBe(false)
				expect(c.FG.anyOpen()).toBe(false)
				expect(c.PC.menuOpen()).toBe(false)
				expect(camState(c)).toEqual(before)
				expect(enabledGuis(c)).toBe(guis)
				expect(c.FG.rescues()).toBe(rescues)
				S.clean(c, expect)
			end
		)

		it(
			"1 000 entrées et sorties mêlées au hasard à des spectacles, des jumelles, des réapparitions, des coupures, des panneaux ouverts par une carte : caméra exacte, mêmes ScreenGuis, aucun sauvetage, aucune instance de plus",
			function()
				local c = client()
				local rng = newRng(5150)
				local Settings = TvAudit.mod(c.h, "UI.Panels.Settings")
				-- l'éclair plein écran de Juice (créé au premier éclair, au premier Grand Splorch du héros)
				-- existe avant le relevé : il ne compte pas comme un écran rallumé par le mode photo ;
				-- de même pour le dossier ClientWorld/VFX des effets (créé au premier spectacle) : un Grand
				-- Splorch avant le relevé
				local Juice = TvAudit.mod(c.h, "UI.Juice")
				Juice.flash()
				-- et pour l'échelle d'animation du message central du HUD (créée au premier message)
				local banner = c.h.localPlayer.PlayerGui:FindFirstChild("Banner", true)
				if banner and banner:IsA("GuiObject") then
					Juice.scaleOf(banner)
				end
				local t0 = c.Clock.now()
				c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
					kind = "splorch",
					data = { userId = c.me, startedAt = t0, burstAt = t0 + 2, endsAt = t0 + 4 },
				})
				play(c, 5)
				local base = camState(c)
				local guis = enabledGuis(c)
				local rescues = c.FG.rescues()
				local count = nil
				local kinds = {}
				-- 8 tours d'échauffement (une fois chaque sorte : les objets créés à la première utilisation
				-- d'un effet ou d'un message, hors mode photo, existent avant le relevé), puis 1 000 tours
				for i = 1, 1008 do
					-- l'état de départ de ce tour (une réapparition change le sujet : le moteur le pose)
					local before = camState(c)
					local entered
					if i % 10 == 1 then
						enterFromMenu(c)
						entered = c.Cam.photoOn()
					else
						entered = c.Cam.photo(true)
					end
					expect(entered).toBe(true)
					play(c, rng:NextNumber(0.4, 1.2))
					local k = if i <= 8 then i else rng:NextInteger(1, 8)
					kinds[k] = (kinds[k] or 0) + 1
					if k == 1 then
						Gamepad.tap(c.h, Enum.KeyCode.ButtonB) -- ○
					elseif k == 2 then
						Gamepad.tap(c.h, Enum.KeyCode.ButtonA) -- ✕ sur le bouton
					elseif k == 3 then
						-- MON Grand Splorch : fin du mode photo, puis le travelling, puis la caméra rendue
						local now = c.Clock.now()
						c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
							kind = "splorch",
							data = { userId = c.me, startedAt = now, burstAt = now + 2, endsAt = now + 4 },
						})
						c.h:settle(1)
						expect(c.Cam.photoOn()).toBe(false)
						-- pendant le spectacle : le mode photo est refusé
						play(c, 0.5)
						expect(c.Cam.photo(true)).toBe(false)
						play(c, 4)
						expect(c.Cam.leaseHolder()).toBeNil()
					elseif k == 4 then
						-- jumelles prises puis mode photo repris : les jumelles cèdent ; sortie par ○
						c.Cam.photo(false)
						play(c, 0.25)
						c.h:moveTo(c.h.localPlayer, c.WL.gateOutside(2))
						c.Cam.binoculars(2)
						play(c, 0.5)
						expect(c.Cam.binocularsSlot()).toBe(2)
						expect(c.Cam.photo(true)).toBe(true)
						expect(c.Cam.binocularsSlot()).toBeNil()
						play(c, 0.5)
						Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
						c.h:moveTo(c.h.localPlayer, c.WL.toWorld(1, Vector3.new(0, 3, 30)))
					elseif k == 5 then
						-- réapparition : sortie d'office ; le moteur pose le nouveau sujet
						c.h:respawn(c.h.localPlayer)
						c.h:settle(1)
						expect(c.Cam.photoOn()).toBe(false)
						c.h:moveTo(c.h.localPlayer, c.WL.toWorld(1, Vector3.new(0, 3, 30)))
						local after = camState(c)
						expect(after.type).toBe(before.type)
						expect(after.fov).toBe(before.fov)
						expect(after.cframe).toBe(before.cframe)
						local hum = c.h.localPlayer.Character:FindFirstChildOfClass("Humanoid")
						c.camera.CameraSubject = hum
						before = camState(c)
					elseif k == 6 then
						-- interrupteur coupé en direct, puis rouvert
						S.event(c, NO_PHOTO)
						expect(c.Cam.photoOn()).toBe(false)
						expect(c.Cam.photo(true)).toBe(false)
						S.event(c, FLAGS)
					elseif k == 7 then
						-- panneau demandé par une carte : refusé tant que la fenêtre bloquante « photo » est
						-- ouverte (rien ne s'ouvre par-dessus un écran caché) ; ○ ramène ensuite au jeu
						c.PC._onCardRequest("dex", "open")
						c.h:settle(1)
						expect(c.Cam.photoOn()).toBe(true)
						expect(c.PC.isOpen()).toBe(false)
						expect(c.FG.names()).toEqual({ "photo" })
						play(c, 0.5)
						Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
					else
						c.Cam.photo(false)
					end
					play(c, 0.5)
					expect(c.Cam.photoOn()).toBe(false)
					expect(c.FG.anyOpen()).toBe(false)
					expect(camState(c)).toEqual(before)
					expect(enabledGuis(c)).toBe(guis)
					if i == 8 then
						count = instances(c)
					elseif i > 8 then
						expect(instances(c)).toBe(count)
					end
				end
				for k = 1, 8 do
					expect((kinds[k] or 0) > 60).toBe(true)
				end
				expect(c.FG.rescues()).toBe(rescues)
				expect(camState(c).cframe).toBe(base.cframe)
				expect(c.Cam.photoStats().entries).toBe(c.Cam.photoStats().exits)
				S.clean(c, expect)
			end
		)

		it(
			"600 s : sortie d'office ; aucune propriété du personnage écrite (il reste visible, N22) ; mort : sortie",
			function()
				local c = client()
				local before = camState(c)
				local char = c.h.localPlayer.Character
				local writes = {}
				local conns = {}
				local function watchInst(inst)
					table.insert(
						conns,
						inst.Changed:Connect(function(prop)
							table.insert(writes, inst.Name .. "." .. tostring(prop))
						end)
					)
				end
				watchInst(char)
				for _, d in char:GetDescendants() do
					watchInst(d)
				end
				expect(c.Cam.photo(true)).toBe(true)
				-- sticks et zoom pendant 5 s : la caméra bouge, le personnage non
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick1, Vector2.new(0.8, 0.6))
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick2, Vector2.new(-0.5, 0.4))
				Gamepad.press(c.h, Enum.KeyCode.ButtonR2)
				play(c, 5)
				Gamepad.release(c.h, Enum.KeyCode.ButtonR2)
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick1, Vector2.new(0, 0))
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick2, Vector2.new(0, 0))
				expect(table.concat(writes, ", ")).toBe("")
				play(c, 590, 1)
				expect(c.Cam.photoOn()).toBe(true)
				play(c, 10, 1)
				expect(c.Cam.photoOn()).toBe(false)
				expect(camState(c)).toEqual(before)
				expect(table.concat(writes, ", ")).toBe("")
				for _, conn in conns do
					conn:Disconnect()
				end
				-- mort : sortie d'office
				expect(c.Cam.photo(true)).toBe(true)
				local hum = char:FindFirstChildOfClass("Humanoid")
				hum.Health = 0
				hum.Died:Fire()
				c.h:settle(1)
				expect(c.Cam.photoOn()).toBe(false)
				S.clean(c, expect)
			end
		)
	end)

	describe("CameraController_photo › caméra bornée (lot B5, étape 5)", function()
		it(
			"10 000 appuis de sticks, L2 / R2 au hasard dans les trois zones (mon ranch, la place, la rue) : point visé dans sa zone, 8 à 60 studs, 5° à 75°, jamais sous le sol",
			function()
				local c = client()
				local rng = newRng(77)
				local zones = {
					{ name = "ranch", at = c.WL.toWorld(1, Vector3.new(10, 3, 40)) },
					{ name = "plaza", at = c.WL.plaza("center") + Vector3.new(12, 3, 0) },
					{ name = "self", at = c.WL.gateOutside(1) + Vector3.new(0, 3, 0) },
				}
				local KEYS = { Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2 }
				for _, z in zones do
					c.h:moveTo(c.h.localPlayer, z.at)
					expect(c.Cam.photo(true)).toBe(true)
					local st = c.Cam._photoState()
					expect(st.zone).toBe(z.name)
					for _ = 1, 3334 do
						local r = rng:NextNumber()
						if r < 0.4 then
							Gamepad.stick(
								c.h,
								Enum.KeyCode.Thumbstick1,
								Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
							)
						elseif r < 0.8 then
							Gamepad.stick(
								c.h,
								Enum.KeyCode.Thumbstick2,
								Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
							)
						else
							local key = KEYS[rng:NextInteger(1, 2)]
							if rng:NextNumber() < 0.5 then
								Gamepad.press(c.h, key)
							else
								Gamepad.release(c.h, key)
							end
						end
						c.Cam._step(rng:NextNumber(0.01, 0.1)) -- 3 334 images : < 600 s
						local s = c.Cam._photoState()
						if z.name == "ranch" then
							local l = c.WL.toLocal(1, s.focus)
							-- Vector3 en simple précision : 1e-3 stud de marge
							expect(math.abs(l.X) <= 34 + 1e-3).toBe(true)
							expect(l.Z >= -2 - 1e-3 and l.Z <= 74 + 1e-3).toBe(true)
						else
							local dx, dz = s.focus.X - s.center.X, s.focus.Z - s.center.Z
							expect(math.sqrt(dx * dx + dz * dz) <= s.radius + 1e-3).toBe(true)
						end
						expect(s.dist >= 8 - 1e-9 and s.dist <= 60 + 1e-9).toBe(true)
						expect(s.pitch >= math.rad(5) - 1e-9 and s.pitch <= math.rad(75) + 1e-9).toBe(true)
						expect(s.eye.Y >= c.WL.groundY(s.eye.X, s.eye.Z) + 1 - 1e-6).toBe(true)
						expect(tostring(c.camera.CFrame.Position)).toBe(tostring(s.eye))
					end
					c.Cam.photo(false)
					c.h:settle(1)
				end
				S.clean(c, expect)
			end
		)
	end)

	describe("CameraController_photo › manette et intentions (lot B5, étape 5)", function()
		it(
			"chaque bouton et chaque stick en mode photo : AUCUNE intention sauf SetPhotoMode (ni achat, ni vente, ni boop, ni prestige) ; □ change le filtre et montre son nom 2 s ; l'aide s'efface après 3 s et revient au prochain appui",
			function()
				local c = client()
				local from = #c.h.log.serverEvents
				expect(c.Cam.photo(true)).toBe(true)
				play(c, 0.5, 1 / 30)
				expect(c.Hud.hintShown()).toBe(true)
				play(c, 3, 1 / 30)
				expect(c.Hud.hintShown()).toBe(false)
				local names = {}
				for _, key in
					{
						Enum.KeyCode.ButtonX,
						Enum.KeyCode.ButtonY,
						Enum.KeyCode.ButtonL1,
						Enum.KeyCode.ButtonR1,
						Enum.KeyCode.ButtonL2,
						Enum.KeyCode.ButtonR2,
						Enum.KeyCode.ButtonL3,
						Enum.KeyCode.ButtonR3,
						Enum.KeyCode.DPadUp,
						Enum.KeyCode.DPadDown,
						Enum.KeyCode.DPadLeft,
						Enum.KeyCode.DPadRight,
						Enum.KeyCode.ButtonStart,
						Enum.KeyCode.ButtonSelect,
					}
				do
					Gamepad.press(c.h, key)
					play(c, 0.8, 1 / 30)
					Gamepad.release(c.h, key)
					c.h:settle(1)
					expect(c.Cam.photoOn()).toBe(true)
					if key == Enum.KeyCode.ButtonX then
						expect(c.Hud.hintShown()).toBe(true)
						expect(c.Hud.filter()).toBe("warm")
						expect(c.Hud.nameShown()).toBe(true)
						table.insert(names, c.Hud.gui():FindFirstChild("FilterName", true).Label.Text)
					end
				end
				for _ = 1, 3 do
					Gamepad.tap(c.h, Enum.KeyCode.ButtonX)
					table.insert(names, c.Hud.gui():FindFirstChild("FilterName", true).Label.Text)
				end
				expect(names).toEqual({ "Warm", "Pink", "Dream", "No filter" })
				play(c, 2.1, 1 / 30)
				expect(c.Hud.nameShown()).toBe(false)
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick1, Vector2.new(1, 0))
				Gamepad.stick(c.h, Enum.KeyCode.Thumbstick2, Vector2.new(0, 1))
				play(c, 1, 1 / 30)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				play(c, 2, 1 / 30)
				expect(c.Cam.photoOn()).toBe(false)
				for _, name in intents(c, from) do
					expect(name).toBe("SetPhotoMode")
				end
				expect(#S.sent(c, "SetPhotoMode") >= 2).toBe(true)
				S.clean(c, expect)
			end
		)

		it(
			"SetPhotoMode : au plus une fois par 1,2 s, seulement le dernier état voulu, jamais égal au dernier envoyé",
			function()
				local c = client()
				local rng = newRng(9)
				local times = {}
				local from = #c.h.log.serverEvents
				local lastSent = nil
				local seen = 0
				-- chaque envoi est relevé à l'heure où il part (après l'appel, puis après l'image)
				local function collect()
					local sent = S.sent(c, "SetPhotoMode")
					while seen < #sent do
						seen += 1
						local v = sent[seen][1]
						expect(type(v)).toBe("boolean")
						expect(v ~= lastSent).toBe(true)
						lastSent = v
						table.insert(times, c.Clock.now())
					end
				end
				for _ = 1, 300 do
					if rng:NextNumber() < 0.5 then
						c.Cam.photo(true)
					else
						c.Cam.photo(false)
					end
					c.h:settle(1)
					collect()
					local dt = rng:NextNumber(0.05, 0.9)
					c.Clock.advance(dt)
					c.h:step(dt, 1)
					collect()
				end
				c.Cam.photo(false)
				play(c, 2)
				local sent = S.sent(c, "SetPhotoMode")
				expect(sent[#sent][1]).toBe(false)
				for i = 2, #times do
					expect(times[i] - times[i - 1] >= 1.2 - 1e-6).toBe(true)
				end
				expect(#times > 20).toBe(true)
				for _, name in intents(c, from) do
					expect(name).toBe("SetPhotoMode")
				end
				S.clean(c, expect)
			end
		)

		it(
			"glyphes : PS5 (○ et □ en images), Xbox (sans lettre PlayStation), clavier (Retour arrière, W, ←, Page, F)",
			function()
				-- PS5
				local c = client()
				expect(c.Cam.photo(true)).toBe(true)
				local gui = c.Hud.gui()
				local function keys()
					local out = {}
					for _, d in gui:GetDescendants() do
						local k = d:GetAttribute("GlyphKey")
						if k ~= nil then
							table.insert(out, k .. ":" .. tostring(d:GetAttribute("GlyphMode")))
						end
					end
					table.sort(out)
					return table.concat(out, ",")
				end
				expect(keys()).toBe(
					"ButtonB:image,ButtonL2:image,ButtonR2:image,ButtonX:image,Thumbstick1:image,Thumbstick2:image"
				)
				expect(#Gamepad.audit(c.h)).toBe(0)
				-- budget d'interface (Q4) : l'écran du mode photo, construit à la première entrée, hors du
				-- chemin méta de Layout_panels
				local objects = 0
				for _, d in gui:GetDescendants() do
					if d:IsA("GuiObject") then
						objects += 1
					end
				end
				-- 63 objets au lot B5 (journal B5-53) : garde à 64
				expect(objects <= 64).toBe(true)
				-- clavier
				c.h.lastInputType = Enum.UserInputType.Keyboard
				c.h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
				c.h:settle(1)
				expect(keys()).toBe("Backspace:text,F:text,Left:text,PageDown:text,PageUp:text,W:text")
				-- touches du clavier : WASD absorbées (le personnage ne bouge pas), F change le filtre
				for _, key in { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.Space, Enum.KeyCode.F } do
					local input = Gamepad.input(key, Enum.UserInputState.Begin)
					expect(Gamepad.dispatch(c.h, key, Enum.UserInputState.Begin, input) ~= nil).toBe(true)
					Gamepad.dispatch(
						c.h,
						key,
						Enum.UserInputState.End,
						Gamepad.input(key, Enum.UserInputState.End)
					)
				end
				expect(c.Hud.filter()).toBe("warm")
				c.Cam.photo(false)
				S.clean(c, expect)
				-- Xbox : manette hors console
				local x = S.client({ profile = { version = 2, onboarding = DONE } })
				x.h.console = false
				S.event(x, FLAGS)
				local Cam = TvAudit.mod(x.h, "Controllers.CameraController")
				local Hud = TvAudit.mod(x.h, "UI.PhotoHud")
				expect(Cam.photo(true)).toBe(true)
				Gamepad.stick(x.h, Enum.KeyCode.Thumbstick1, Vector2.new(0, 0))
				x.h:settle(1)
				for _, d in Hud.gui():GetDescendants() do
					local mode = d:GetAttribute("GlyphMode")
					if mode ~= nil then
						expect(mode == "image" or mode == "diamond" or mode == "text").toBe(true)
						local img = d:FindFirstChild("Image")
						if img and img:IsA("ImageLabel") and img.Image ~= "" then
							expect(string.find(img.Image, Gamepad.PS_GLYPHS, 1, true)).toBeNil()
						end
					end
				end
				Cam.photo(false)
				S.clean(x, expect)
			end
		)

		it(
			"interrupteur PhotoMode coupé : aucune ligne dans les Réglages, photo(true) refusé, aucune intention",
			function()
				local c = client({ flags = NO_PHOTO })
				local from = #c.h.log.serverEvents
				c.PC.open("Settings")
				S.run(c, 0.6)
				local Settings = TvAudit.mod(c.h, "UI.Panels.Settings")
				expect(Settings._controlFor("photo")).toBeNil()
				for _, item in Settings._items() do
					expect(item.kind ~= "action").toBe(true)
				end
				c.PC.closeAll()
				S.run(c, 0.5)
				expect(c.Cam.photo(true)).toBe(false)
				expect(c.Cam.photoOn()).toBe(false)
				expect(c.Hud.gui()).toBeNil()
				play(c, 2)
				expect(#S.sent(c, "SetPhotoMode")).toBe(0)
				expect(#intents(c, from)).toBe(0)
				S.clean(c, expect)
			end
		)
	end)

	describe("CameraController_photo › jumelles (lot B5, étape 5)", function()
		local function atGate(c, slot)
			c.h:moveTo(c.h.localPlayer, c.WL.gateOutside(slot))
			S.run(c, 0.3)
		end

		it(
			"□ devant le portail : vue atteinte en 0,4 s (18 studs au-dessus, 16 dehors, focale 50) ; caméra rendue à ○, à close, au départ du propriétaire, à la coupure de Hearts ; s'éloigner de plus de 14 studs referme",
			function()
				local c = client()
				local function openAt()
					atGate(c, 2)
					local before = camState(c)
					expect(c.B.open(OWNER)).toBe(true)
					c.h:settle(1)
					expect(c.Cam.binocularsSlot()).toBe(2)
					play(c, 0.5, 0.1)
					local cam = c.camera
					local gate = c.WL.toWorld(2, Vector3.zero)
					local out = c.WL.toWorld(2, Vector3.new(0, 0, -16))
					local eye = cam.CFrame.Position
					expect(eye.Y).toBeNear(gate.Y + 18, 1e-4)
					expect(eye.X).toBeNear(out.X, 1e-4)
					expect(eye.Z).toBeNear(out.Z, 1e-4)
					expect(cam.FieldOfView).toBeNear(50, 1e-6)
					local target = c.WL.toWorld(2, Vector3.new(0, 0, 36))
					local dir = (target - eye).Unit
					expect((cam.CFrame.LookVector - dir).Magnitude < 1e-4).toBe(true)
					return before
				end
				-- ○
				local before = openAt()
				S.run(c, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				c.h:settle(1)
				expect(c.B.isOpen()).toBe(false)
				expect(camState(c)).toEqual(before)
				-- close() du jeu
				before = openAt()
				c.B.close()
				c.h:settle(1)
				expect(camState(c)).toEqual(before)
				-- propriétaire parti
				before = openAt()
				c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
					seq = 2,
					ranches = { ["1"] = ranch(1, c.me), ["2"] = ranch(2, 0), ["3"] = ranch(3, 0) },
					squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {} },
				})
				c.h:settle(1)
				S.run(c, 0.2)
				expect(c.B.isOpen()).toBe(false)
				expect(camState(c)).toEqual(before)
				c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
					seq = 3,
					ranches = { ["1"] = ranch(1, c.me), ["2"] = ranch(2, OWNER), ["3"] = ranch(3, 0) },
					squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {} },
				})
				c.h:settle(1)
				-- interrupteur Hearts coupé en direct
				before = openAt()
				local noHearts = table.clone(FLAGS)
				noHearts.Hearts = nil
				S.event(c, noHearts)
				expect(c.B.isOpen()).toBe(false)
				expect(camState(c)).toEqual(before)
				S.event(c, FLAGS)
				-- s'éloigner : à 14 studs du portail, toujours ; à plus de 14, fermé et caméra rendue
				before = openAt()
				c.h:moveTo(c.h.localPlayer, c.WL.toWorld(2, Vector3.new(0, 3, -13.5)))
				play(c, 0.2, 0.1)
				expect(c.B.isOpen()).toBe(true)
				c.h:moveTo(c.h.localPlayer, c.WL.toWorld(2, Vector3.new(0, 3, -15)))
				play(c, 0.2, 0.1)
				expect(c.B.isOpen()).toBe(false)
				expect(c.Cam.binocularsSlot()).toBeNil()
				expect(camState(c)).toEqual(before)
				expect(c.FG.anyOpen()).toBe(false)
				S.clean(c, expect)
			end
		)

		it(
			"Mouvement réduit : vue tout de suite ; un spectacle prend la caméra : les jumelles se referment, caméra rendue à la fin",
			function()
				local c = client()
				local Prefs = TvAudit.mod(c.h, "Util.Prefs")
				atGate(c, 2)
				local before = camState(c)
				local old = Prefs.reducedMotion
				Prefs.reducedMotion = function()
					return true
				end
				expect(c.B.open(OWNER)).toBe(true)
				c.h:settle(1)
				expect(c.camera.FieldOfView).toBe(50)
				Prefs.reducedMotion = old
				-- MON Grand Splorch : le travelling prend la caméra (bail « show »)
				local now = c.Clock.now()
				c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
					kind = "splorch",
					data = { userId = c.me, startedAt = now, burstAt = now + 2, endsAt = now + 4 },
				})
				play(c, 0.5, 0.1)
				expect(c.Cam.leaseHolder()).toBe("show")
				expect(c.B.isOpen()).toBe(false)
				play(c, 5)
				expect(c.Cam.leaseHolder()).toBeNil()
				expect(camState(c)).toEqual(before)
				S.clean(c, expect)
			end
		)

		for _, vp in
			{
				{ name = "720p", size = Vector2.new(1280, 720) },
				{ name = "1080p", size = Vector2.new(1920, 1080) },
				{ name = "4K", size = Vector2.new(3840, 2160) },
			}
		do
			it(
				"carte des jumelles jamais couverte : centre du ranch projeté au-dessus du haut de la carte en "
					.. vp.name,
				function()
					local c = client({ viewport = vp.size })
					atGate(c, 2)
					expect(c.B.open(OWNER)).toBe(true)
					play(c, 0.5, 0.1)
					Layout.apply(c.h)
					local cam = c.camera
					local p = cam.CFrame:PointToObjectSpace(c.WL.toWorld(2, Vector3.new(0, 0, 36)))
					expect(p.Z < 0).toBe(true)
					local half = math.tan(math.rad(cam.FieldOfView) / 2)
					local y = vp.size.Y / 2 - (p.Y / -p.Z) / half * vp.size.Y / 2
					local card = c.B.button().Parent
					local r = Layout.rect(card)
					expect(r ~= nil).toBe(true)
					expect(y < r.y).toBe(true)
					-- aucun objet d'interface ajouté par la vue : la carte reste la seule chose montrée
					expect(c.Hud.gui()).toBeNil()
					S.clean(c, expect)
				end
			)
		end
	end)
end
