--!nocheck
-- Correctif r5-audio de Comet Conga (passe finale) : des sons sans danger avec de vrais IDs
--   * Config/Sounds : les 8 sons d'interface sont des sons publiés par Roblox (provenance sur la
--     ligne : Contract.spec, Fix_r4_partage_4.spec) ; garde-fous de lecture posés sur chaque clé
--     (maxLength, fade, perFrame, concurrent)
--   * AudioController : ID vide = rien ; échec de chargement = clé retirée, un avertissement, aucune
--     erreur ; effets coupés = aucun Sound et les copies en cours s'arrêtent ; musique coupée dans le
--     profil = la musique ne joue jamais (elle attend l'instantané du profil, puis monte en fondu) ;
--     12 sons dans une image = au plus perFrame copies ; copie terminée détruite ; copie longue
--     coupée en fondu à maxLength ; Mouvement réduit ne contourne pas les réglages
--   * « Select » ne double plus Tab / Back / Whoosh… quand le code déplace la sélection dans la même
--     action (L1 / R1, ○ qui rend la sélection au rail) ; une croix seule joue toujours « Select »
-- Adaptations : les sons de jeu de Comet Conga (Coin, Catch, LevelUp, Supernova, Music, Bank) sont
-- ajoutés à Config/Sounds le temps du test (TEST_SOUNDS : mêmes IDs officiels, mêmes garde-fous),
-- car le socle ne déclare que les sons d'interface ; tests « sons de jeu remplis » et « à confirmer
-- à l'écoute » remplacés par le contrôle des 8 sons d'interface ; tests sur le vrai client console
-- (PanelController, HUD de Comet Conga) retirés : la règle « Select » reste vérifiée sur
-- AudioController seul.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local K = Enum.KeyCode
	local T0 = 1800000000

	-- Sons d'interface du socle (vérifiés dans les dépôts officiels Roblox, Config/Sounds)
	local FILLED = {
		Click = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1 },
		Pop = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1.3 },
		Error = { id = "rbxassetid://17161255584", volume = 0.5, pitch = 0.75 },
		Whoosh = { id = "rbxassetid://17161253544", volume = 0.4, pitch = 1 },
		Select = { id = "rbxassetid://17161204665", volume = 0.3, pitch = 1 },
		Back = { id = "rbxassetid://17161255584", volume = 0.35, pitch = 1 },
		Tab = { id = "rbxassetid://17161253544", volume = 0.35, pitch = 1.25 },
		Bump = { id = "rbxassetid://17161204665", volume = 0.3, pitch = 0.7 },
	}

	-- Sons de jeu de Comet Conga ajoutés à Config/Sounds le temps d'un test (données neutres du test)
	local TEST_SOUNDS = {
		Coin = { id = "rbxassetid://9113849651", volume = 0.4 },
		Catch = { id = "rbxassetid://4110925712", volume = 0.45 },
		LevelUp = { id = "rbxassetid://3422389728", volume = 0.5, maxLength = 2 },
		Supernova = { id = "rbxassetid://1846248593", volume = 0.7, pitch = 0.85, maxLength = 3 },
		Bank = { id = "rbxassetid://9113849651", volume = 0.6, pitch = 0.8 },
		Music = { id = "rbxassetid://1837849285", volume = 0.25, fade = 2 },
	}

	-- Ajoute TEST_SOUNDS à la configuration (avec les garde-fous par défaut de Config/Sounds)
	local function addTestSounds(S)
		for key, def in TEST_SOUNDS do
			local copy = table.clone(def)
			copy.maxLength = copy.maxLength or 4
			copy.fade = copy.fade or 0.3
			copy.perFrame = copy.perFrame or 3
			copy.concurrent = copy.concurrent or 4
			S[key] = copy
		end
	end

	local function sounds(h)
		return h:require("ReplicatedStorage.Shared.Config.Sounds")
	end

	-- Ligne de déclaration de `key` dans Config/Sounds (source lue sur le disque)
	local function declarationLine(key)
		for line in string.gmatch(fs.readFile("src/shared/Config/Sounds.luau"), "[^\n]+") do
			if string.match(line, "^%s*" .. key .. "%s*=%s*{") then
				return line
			end
		end
		return nil
	end

	-- Copies jouées : Sounds enfants directs de SoundService (les modèles sont dans GameSounds)
	local function copies(h, name)
		local out = {}
		for _, child in h.game:GetService("SoundService"):GetChildren() do
			if child.ClassName == "Sound" and (name == nil or child.Name == name) then
				table.insert(out, child)
			end
		end
		return out
	end

	local function playing(h, name)
		local n = 0
		for _, s in copies(h, name) do
			if s.Playing then
				n += 1
			end
		end
		return n
	end

	local function warningsAbout(h, needle)
		local n = 0
		for _, line in h.log.output do
			if string.sub(line, 1, 5) == "WARN " and string.find(line, needle, 1, true) then
				n += 1
			end
		end
		return n
	end

	-- AudioController seul (Init + Start) ; `opts.before(Sounds)` modifie la configuration avant
	-- Init, `opts.preload(list, callback)` remplace ContentProvider:PreloadAsync
	local function audio(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = opts.console })
		local Sounds = sounds(h)
		addTestSounds(Sounds)
		if opts.before then
			opts.before(Sounds)
		end
		local CP = MockInstance.classMethods.ContentProvider
		local saved = CP.PreloadAsync
		if opts.preload then
			CP.PreloadAsync = function(_, list, callback)
				return opts.preload(list, callback)
			end
		end
		local Audio = h:require(CLIENT .. "Controllers.AudioController")
		Audio.Init()
		Audio.Start()
		h:settle(2)
		CP.PreloadAsync = saved
		h:step(1 / 60, 1)
		return h, Audio, Sounds
	end

	describe("Fix r5-audio › Config/Sounds : des sons d'interface vérifiés", function()
		it("8 sons d'interface : ID publié par Roblox, volume et hauteur vérifiés", function()
			local S = sounds(Harness.new({ mode = "client" }))
			for key, want in FILLED do
				local def = S[key]
				expect({ key = key, id = def.id, volume = def.volume, pitch = def.pitch or 1 }).toEqual({
					key = key,
					id = want.id,
					volume = want.volume,
					pitch = want.pitch,
				})
				local line = declarationLine(key)
				expect({ key = key, source = line ~= nil and string.find(line, "Roblox/", 1, true) ~= nil }).toEqual({
					key = key,
					source = true,
				})
			end
		end)

		it(
			"garde-fous sur chaque clé : maxLength ≤ 4 s, fondu, plafonds par image et simultané",
			function()
				local S = sounds(Harness.new({ mode = "client" }))
				for key, def in S do
					local ok = type(def.maxLength) == "number"
						and def.maxLength > 0
						and def.maxLength <= 4
						and type(def.fade) == "number"
						and def.fade > 0
						and type(def.perFrame) == "number"
						and def.perFrame >= 1
						and def.perFrame % 1 == 0
						and type(def.concurrent) == "number"
						and def.concurrent >= def.perFrame
						and def.concurrent % 1 == 0
					expect({ key = key, ok = ok }).toEqual({ key = key, ok = true })
					if key ~= "Music" then
						expect({ key = key, fadeShorter = def.fade < def.maxLength }).toEqual({
							key = key,
							fadeShorter = true,
						})
					end
				end
			end
		)
	end)

	describe("Fix r5-audio › AudioController : sûr avec de vrais IDs", function()
		it("ID vide : aucune instance, play() ne crée rien, aucun avertissement", function()
			-- clé vidée par le test (un son qui déplaît à l'écoute se vide ainsi)
			local h, Audio, S = audio({
				before = function(S)
					S.Bank.id = ""
				end,
			})
			expect(S.Bank.id).toBe("")
			local folder = h.game:GetService("SoundService").GameSounds
			expect(folder:FindFirstChild("Bank")).toBeNil()
			Audio.play("Bank")
			Audio.play("Bank", 0.05, 1.2)
			Audio.play("NoSuchKey")
			expect(#copies(h)).toBe(0)
			expect(table.concat(h:warnings(), "\n")).toBe("")
			expect(#h.errors).toBe(0)
		end)

		it(
			"échec de chargement : clé retirée, un seul avertissement, aucune erreur ; les autres jouent",
			function()
				local h, Audio, S = audio({
					preload = function(list, callback)
						for _, s in list do
							local failed = s.SoundId == "rbxassetid://4110925712" -- Catch
							callback(
								s.SoundId,
								if failed
									then Enum.AssetFetchStatus.Failure
									else Enum.AssetFetchStatus.Success
							)
						end
						-- rapport répété ou absurde : ignoré sans erreur
						callback("rbxassetid://4110925712", Enum.AssetFetchStatus.Failure)
						callback(nil, nil)
						callback(42, "Failure")
						-- adresse d'asset sous une autre forme (même numéro) ; délai dépassé : gardé
						callback("https://www.roblox.com/asset/?id=3422389728", Enum.AssetFetchStatus.Failure)
						callback("rbxassetid://9113849651", Enum.AssetFetchStatus.TimedOut)
					end,
				})
				expect(S.Catch.id).toBe("rbxassetid://4110925712")
				local folder = h.game:GetService("SoundService").GameSounds
				expect(folder:FindFirstChild("Catch")).toBeNil()
				Audio.play("Catch", 0.05, 1.2)
				expect(#copies(h, "Catch")).toBe(0)
				expect(warningsAbout(h, "Catch")).toBe(1)
				expect(S.LevelUp.id).toBe("rbxassetid://3422389728")
				expect(folder:FindFirstChild("LevelUp")).toBeNil()
				Audio.play("LevelUp")
				expect(#copies(h, "LevelUp")).toBe(0)
				expect(warningsAbout(h, "LevelUp")).toBe(1)
				-- les autres clés sont intactes et jouent
				expect(folder:FindFirstChild("Coin") ~= nil).toBe(true)
				Audio.play("Coin")
				expect(playing(h, "Coin")).toBe(1)
				expect(#h.errors).toBe(0)
			end
		)

		it("préchargement qui lève une erreur : aucune erreur, les sons restent jouables", function()
			local h, Audio = audio({
				preload = function()
					error("HTTP 503")
				end,
			})
			Audio.play("Coin")
			expect(playing(h, "Coin")).toBe(1)
			expect(#h.errors).toBe(0)
		end)

		it("effets coupés : aucun Sound ; les copies en cours s'arrêtent à l'image suivante", function()
			local h, Audio = audio()
			Audio.play("Coin")
			Audio.play("Supernova")
			expect(playing(h)).toBe(2)
			Audio.enabled = false
			h:step(1 / 60, 1)
			expect(playing(h)).toBe(0)
			expect(#copies(h)).toBe(0)
			Audio.play("Coin")
			Audio.play("Catch", 0.05, 1.3)
			expect(#copies(h)).toBe(0)
			-- réactivés : ça rejoue
			Audio.enabled = true
			Audio.play("Coin")
			expect(playing(h, "Coin")).toBe(1)
			expect(#h.errors).toBe(0)
		end)

		it("12 sons dans une même image : au plus perFrame copies ; l'image suivante rejoue", function()
			local h, Audio, S = audio()
			for i = 1, 12 do
				Audio.play("Catch", 0.05, 1 + 0.01 * i)
			end
			local n = playing(h, "Catch")
			expect(n >= 1 and n <= S.Catch.perFrame).toBe(true)
			expect(#copies(h, "Catch")).toBe(n)
			h:step(1 / 60, 1)
			Audio.play("Catch")
			expect(playing(h, "Catch") >= 1 and playing(h, "Catch") <= S.Catch.concurrent).toBe(true)
			expect(#h.errors).toBe(0)
		end)

		it("plafond simultané : au plus concurrent copies d'une clé, la plus récente joue", function()
			local h, Audio, S = audio()
			local last
			for _ = 1, S.Coin.concurrent + 4 do
				Audio.play("Coin")
				local list = copies(h, "Coin")
				last = list[#list]
				h:step(1 / 60, 1)
			end
			expect(#copies(h, "Coin")).toBe(S.Coin.concurrent)
			expect(last.Parent ~= nil and last.Playing).toBe(true)
			expect(#h.errors).toBe(0)
		end)

		it("copie terminée (Ended) : détruite tout de suite", function()
			local h, Audio = audio()
			Audio.play("Coin")
			local s = copies(h, "Coin")[1]
			expect(s ~= nil).toBe(true)
			s.Ended:Fire(s.SoundId)
			h:settle(1)
			expect(s.Parent).toBeNil()
			expect(#copies(h)).toBe(0)
			expect(#h.errors).toBe(0)
		end)

		it("copie longue (morceau de fête joué en effet) : coupée en fondu à maxLength", function()
			local h, Audio = audio({
				before = function(S)
					S.Supernova.maxLength = 0.15
					S.Supernova.fade = 0.05
				end,
			})
			h.game:GetService("SoundService").GameSounds.Supernova.TimeLength = 30
			Audio.play("Supernova")
			local s = copies(h, "Supernova")[1]
			expect(s ~= nil and s.Playing).toBe(true)
			task.wait(0.45)
			h:settle(1)
			expect(s.Parent).toBeNil()
			expect(s.Playing).toBe(false)
			expect(#h.errors).toBe(0)
		end)

		it("Music : jamais jouée comme un effet (play), seulement en boucle", function()
			local h, Audio = audio()
			Audio.play("Music")
			expect(#copies(h)).toBe(0)
			expect(#h.errors).toBe(0)
		end)
	end)

	describe("Fix r5-audio › hauteur demandée par l'appelant (restes client-world N31)", function()
		it("AudioController.play(name, variation?, pitch?) multiplie PlaybackSpeed par pitch", function()
			local h, Audio = audio({
				before = function(S)
					S.Catch.pitch = 1.1
				end,
			})
			local SoundService = h.game:GetService("SoundService")
			local known = {}
			for _, child in SoundService:GetChildren() do
				known[child] = true
			end
			local function play(...)
				Audio.play(...)
				for _, child in SoundService:GetChildren() do
					if not known[child] and child.ClassName == "Sound" then
						known[child] = true
						return child
					end
				end
				return nil
			end
			local s = play("Catch", 0, 1.3)
			expect(s ~= nil).toBe(true)
			expect(s.Playing).toBe(true)
			expect(s.PlaybackSpeed).toBeNear(1.1 * 1.3, 1e-6)
			-- appelants sans hauteur inchangés
			h:step(1 / 60, 1)
			expect(play("Catch", 0).PlaybackSpeed).toBeNear(1.1, 1e-6)
			h:step(1 / 60, 1)
			expect(play("Catch").PlaybackSpeed).toBeNear(1.1, 1e-6)
			-- hauteur absurde : ignorée
			h:step(1 / 60, 1)
			expect(play("Catch", 0, 0 / 0).PlaybackSpeed).toBeNear(1.1, 1e-6)
			h:step(1 / 60, 1)
			expect(play("Catch", 0, -2).PlaybackSpeed).toBeNear(1.1, 1e-6)
			h:step(1 / 60, 1)
			expect(play("Catch", 0, math.huge).PlaybackSpeed).toBeNear(1.1, 1e-6)
			-- variation autour de la hauteur demandée
			h:step(1 / 60, 1)
			local v = play("Catch", 0.05, 1.5).PlaybackSpeed
			expect(v >= 1.1 * 1.5 * 0.95 - 1e-6 and v <= 1.1 * 1.5 * 1.05 + 1e-6).toBe(true)
		end)
	end)

	describe("Fix r5-audio › musique et réglages du profil", function()
		-- Client complet ; Played de la musique compté dès le démarrage (avant l'instantané)
		local function bootClient()
			local h = Harness.new({ mode = "client" })
			h:createRemotes()
			addTestSounds(sounds(h))
			h:boot()
			local music = h.game:GetService("SoundService").GameSounds:FindFirstChild("Music")
			local c = { h = h, music = music, played = 0 }
			music.Played:Connect(function()
				c.played += 1
			end)
			h:step(1 / 60, 10)
			h:settle(2)
			c.Audio = h:require(CLIENT .. "Controllers.AudioController")
			c.Prefs = h:require(CLIENT .. "Util.Prefs")
			c.Sounds = sounds(h)
			return c
		end

		local function snapshot(c, settings)
			c.h:fireClient(REMOTES .. "DataSnapshot", { coins = 5, settings = settings })
			c.h:settle(3)
			c.h:step(1 / 60, 5)
			c.h:settle(2)
		end

		it(
			"musique coupée dans le profil : la musique ne joue jamais, même pendant le chargement",
			function()
				local c = bootClient()
				expect(c.music ~= nil).toBe(true)
				expect(c.played).toBe(0)
				expect(c.music.Playing).toBe(false)
				snapshot(c, { music = false, sfx = true, lang = "en" })
				expect(c.Audio.isMusicEnabled()).toBe(false)
				expect(c.played).toBe(0)
				expect(c.music.Playing).toBe(false)
				-- nouvel instantané (reconnexion) : toujours rien
				snapshot(c, { music = false, sfx = true, lang = "en" })
				expect(c.played).toBe(0)
				expect(#c.h.errors).toBe(0)
			end
		)

		it(
			"musique active : attend l'instantané du profil, puis boucle à son volume (fondu d'entrée)",
			function()
				local c = bootClient()
				expect(c.played).toBe(0) -- chargement : réglage pas encore connu
				snapshot(c, { music = true, sfx = true, lang = "en" })
				expect(c.played).toBe(1)
				expect(c.music.Playing).toBe(true)
				expect(c.music.Looped).toBe(true)
				expect(c.music.Volume).toBeNear(c.Sounds.Music.volume, 1e-6)
				-- réglage « Musique » coupé puis rendu
				c.Prefs._onSettings({ music = false })
				c.h:settle(1)
				expect(c.music.Playing).toBe(false)
				c.Prefs._onSettings({ music = true })
				c.h:settle(1)
				expect(c.music.Playing).toBe(true)
				expect(c.played).toBe(2)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("Mouvement réduit ne contourne pas les réglages Effets et Musique", function()
			local c = bootClient()
			snapshot(c, { reducedMotion = true, sfx = false, music = false, lang = "en" })
			expect(c.Audio.enabled).toBe(false)
			c.Audio.play("Coin")
			c.Audio.play("Supernova")
			expect(#copies(c.h)).toBe(0)
			expect(c.played).toBe(0)
			-- Mouvement réduit toujours là, sons rendus : ça joue
			c.Prefs._onSettings({ reducedMotion = true, sfx = true, music = true })
			c.h:settle(1)
			expect(c.Audio.enabled).toBe(true)
			c.Audio.play("Coin")
			expect(playing(c.h, "Coin")).toBe(1)
			expect(c.music.Playing).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)
	end)

	describe("Fix r5-audio › « Select » ne double plus les autres sons d'interface", function()
		-- AudioController seul sur console : sélection a → b → a…
		local function nav()
			local h, Audio = audio({ console = true })
			local gui = MockInstance.new("ScreenGui")
			gui.Name = "Menu"
			local a = MockInstance.new("TextButton")
			a.Name = "A"
			a.Parent = gui
			local b = MockInstance.new("TextButton")
			b.Name = "B"
			b.Parent = gui
			gui.Parent = h.localPlayer.PlayerGui
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(T0)
			h.game.GuiService.SelectedObject = a -- pose initiale : rien
			h:settle(1)
			local called = {}
			local play = Audio.play
			Audio.play = function(name, ...)
				table.insert(called, name)
				return play(name, ...)
			end
			-- nouvelle action de l'utilisateur : bouton relâché, temps qui passe
			local function release()
				h.game.UserInputService.InputEnded:Fire(
					Gamepad.input(K.ButtonA, Enum.UserInputState.End),
					false
				)
				Clock.advance(0.2)
				h:step(1 / 60, 1)
			end
			local function select(target)
				h.game.GuiService.SelectedObject = target
				h:settle(1)
			end
			return { h = h, Audio = Audio, a = a, b = b, called = called, release = release, select = select }
		end

		it("Tab puis sélection déplacée par le code dans la même action : « Tab » seul", function()
			local n = nav()
			n.Audio.play("Tab")
			n.select(n.b)
			expect(n.called).toEqual({ "Tab" })
			-- action suivante : une croix seule joue « Select »
			n.release()
			n.select(n.a)
			expect(n.called).toEqual({ "Tab", "Select" })
			expect(playing(n.h, "Select")).toBe(1)
			expect(#n.h.errors).toBe(0)
		end)

		it(
			"Back, Whoosh, Bump, Click, Error : même règle ; Pop ou Coin ne retiennent pas « Select »",
			function()
				local n = nav()
				local target = n.b
				for _, key in { "Back", "Whoosh", "Bump", "Click", "Error" } do
					n.release()
					table.clear(n.called)
					n.Audio.play(key)
					n.select(target)
					target = if target == n.b then n.a else n.b
					expect({ key = key, called = n.called }).toEqual({ key = key, called = { key } })
				end
				for _, key in { "Pop", "Coin" } do
					n.release()
					table.clear(n.called)
					n.Audio.play(key)
					n.select(target)
					target = if target == n.b then n.a else n.b
					expect({ key = key, called = n.called }).toEqual({ key = key, called = { key, "Select" } })
				end
				expect(#n.h.errors).toBe(0)
			end
		)

		it(
			"ordre inverse (sélection puis Tab dans la même action) : la copie « Select » est coupée",
			function()
				local n = nav()
				n.release()
				n.select(n.b)
				local s = copies(n.h, "Select")[1]
				expect(s ~= nil and s.Playing).toBe(true)
				n.Audio.play("Tab")
				expect(s.Parent).toBeNil()
				expect(playing(n.h, "Tab")).toBe(1)
				-- action suivante : un Tab ne coupe pas le « Select » d'une action précédente
				n.release()
				n.select(n.a)
				local s2
				for _, x in copies(n.h, "Select") do
					s2 = x
				end
				expect(s2 ~= nil and s2.Playing).toBe(true)
				n.release()
				n.Audio.play("Tab")
				expect(s2.Parent ~= nil and s2.Playing).toBe(true)
				expect(#n.h.errors).toBe(0)
			end
		)
	end)
end
