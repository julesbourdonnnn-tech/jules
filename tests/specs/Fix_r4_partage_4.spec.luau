--!nocheck
-- Correctif r4-partage-4 : sons de navigation et d'interface audibles (docs/07-console-ps5.md R9, §9.2)
--   * Select, Back, Tab, Bump, Whoosh, Error et Pop ont un vrai ID « rbxassetid://<nombre> » : avant,
--     tous vides, AudioController.Init les sautait et la PS5 n'avait aucun retour sonore (sélection
--     déplacée, ○, L1/R1, L2/R2, bout de liste, refus)
--   * provenance (passe finale, même règle que Contract.spec) : chaque ID rempli de Config/Sounds porte
--     sur sa ligne un commentaire qui nomme le dépôt officiel (Roblox/resources ou Roblox/creator-docs)
--     et le fichier source ; plus de liste figée d'IDs autorisés (le propriétaire peut changer un son
--     après l'avoir écouté, en citant sa source)
--   * deux clés qui partagent un enregistrement s'en distinguent par la hauteur (≥ 15 %)
--   * de bout en bout sur le client console : un Sound par ID rempli, qui joue cet ID
local fs = require("@lune/fs")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

	-- Clés de navigation (docs/07 §9.2) et retours d'interface joués à la manette (activation,
	-- ouverture de panneau, refus, apparition)
	local UI_KEYS = { "Select", "Back", "Tab", "Bump", "Whoosh", "Error", "Pop", "Click" }

	local function loadSounds(h)
		return h:require("ReplicatedStorage.Shared.Config.Sounds")
	end

	-- Clés à ID rempli, triées (la musique joue en boucle, jamais par play())
	local function filledKeys(Sounds)
		local out = {}
		for name, def in Sounds do
			if def.id ~= "" then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	-- Ligne de déclaration de chaque clé dans Config/Sounds (source lue sur le disque)
	local function declarationLines()
		local lines = {}
		for line in string.gmatch(fs.readFile("src/shared/Config/Sounds.luau"), "[^\n]+") do
			local key = string.match(line, "^%s*(%w+)%s*=%s*{")
			if key then
				lines[key] = line
			end
		end
		return lines
	end

	-- Nouveau Sound apparu dans SoundService depuis `known` (copie jouée par AudioController.play)
	local function newSound(h, known)
		for _, child in h.game:GetService("SoundService"):GetChildren() do
			if not known[child] and child.ClassName == "Sound" then
				known[child] = true
				return child
			end
		end
		return nil
	end

	local function snapshotChildren(h)
		local known = {}
		for _, child in h.game:GetService("SoundService"):GetChildren() do
			known[child] = true
		end
		return known
	end

	describe("Fix r4-partage-4 › Config/Sounds : retours de navigation audibles (R9)", function()
		it(
			"Select, Back, Tab, Bump, Whoosh, Error, Pop, Click : ID rempli, exactement rbxassetid://<nombre>",
			function()
				local Sounds = loadSounds(Harness.new({ mode = "client" }))
				for _, key in UI_KEYS do
					local def = Sounds[key]
					local id = def and def.id
					expect({
						key = key,
						filled = type(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil,
					}).toEqual({ key = key, filled = true })
				end
			end
		)

		it(
			"provenance : chaque ID rempli porte sur sa ligne le dépôt Roblox et le fichier source",
			function()
				local Sounds = loadSounds(Harness.new({ mode = "client" }))
				local lines = declarationLines()
				for _, key in filledKeys(Sounds) do
					local line = lines[key] or ""
					local comment = string.match(line, "%-%-%s*(.+)$") or ""
					local repo = string.find(comment, "Roblox/resources", 1, true) ~= nil
						or string.find(comment, "Roblox/creator-docs", 1, true) ~= nil
					local file = string.match(comment, "[%w_%-/%.]+%.%a+") ~= nil
					expect({
						key = key,
						declared = string.find(line, Sounds[key].id, 1, true) ~= nil,
						repo = repo,
						file = file,
					}).toEqual({
						key = key,
						declared = true,
						repo = true,
						file = true,
					})
				end
				-- les clés d'interface en font partie
				for _, key in UI_KEYS do
					expect({ key = key, filled = table.find(filledKeys(Sounds), key) ~= nil }).toEqual({
						key = key,
						filled = true,
					})
				end
			end
		)

		it("même enregistrement pour deux clés : hauteurs distinctes d'au moins 15 %", function()
			local Sounds = loadSounds(Harness.new({ mode = "client" }))
			local names = {}
			for name, def in Sounds do
				if def.id ~= "" then
					table.insert(names, name)
				end
			end
			table.sort(names)
			for i = 1, #names do
				for j = i + 1, #names do
					local a, b = Sounds[names[i]], Sounds[names[j]]
					if a.id == b.id then
						local pa, pb = a.pitch or 1, b.pitch or 1
						local ratio = math.max(pa, pb) / math.min(pa, pb)
						expect({ pair = names[i] .. "/" .. names[j], distinct = ratio >= 1.15 }).toEqual({
							pair = names[i] .. "/" .. names[j],
							distinct = true,
						})
					end
				end
			end
			-- le bout de liste et le refus ne se confondent pas avec le déplacement et le retour
			expect(
				Sounds.Bump.id ~= Sounds.Select.id or (Sounds.Bump.pitch or 1) ~= (Sounds.Select.pitch or 1)
			).toBe(true)
			expect(Sounds.Error.id ~= Sounds.Back.id or (Sounds.Error.pitch or 1) ~= (Sounds.Back.pitch or 1)).toBe(
				true
			)
		end)
	end)

	describe("Fix r4-partage-4 › AudioController sur console : les sons jouent vraiment", function()
		local function consoleAudio()
			local h = Harness.new({ mode = "client", console = true })
			local Sounds = loadSounds(h)
			local preloaded = {}
			local CP = MockInstance.classMethods.ContentProvider
			local saved = CP and CP.PreloadAsync
			if CP then
				CP.PreloadAsync = function(_, list)
					for _, s in list do
						preloaded[s.Name] = s.SoundId
					end
				end
			end
			local Audio = h:require(CLIENT .. "Controllers.AudioController")
			Audio.Init()
			Audio.Start()
			h:settle(2)
			if CP then
				CP.PreloadAsync = saved
			end
			return h, Sounds, Audio, preloaded
		end

		it("Init : un Sound préchargé par ID rempli dans SoundService.GameSounds, avec son ID", function()
			local h, Sounds, _, preloaded = consoleAudio()
			local folder = h.game:GetService("SoundService"):FindFirstChild("GameSounds")
			expect(folder ~= nil).toBe(true)
			local filled = filledKeys(Sounds)
			expect(#filled >= #UI_KEYS).toBe(true)
			expect(#folder:GetChildren()).toBe(#filled)
			for _, key in filled do
				local s = folder:FindFirstChild(key)
				expect({ key = key, soundId = s and s.SoundId }).toEqual({
					key = key,
					soundId = Sounds[key].id,
				})
				expect(s.Volume).toBe(Sounds[key].volume)
				expect(s.PlaybackSpeed).toBeNear(Sounds[key].pitch or 1, 1e-6)
				expect({ key = key, preloaded = preloaded[key] }).toEqual({
					key = key,
					preloaded = Sounds[key].id,
				})
			end
			expect(#h.errors).toBe(0)
		end)

		it("sélection déplacée à la manette : un Sound « Select » joue l'ID déclaré", function()
			local h, Sounds = consoleAudio()
			local gui = MockInstance.new("ScreenGui")
			gui.Name = "Menu"
			local a = MockInstance.new("TextButton")
			a.Name = "A"
			a.Parent = gui
			local b = MockInstance.new("TextButton")
			b.Name = "B"
			b.Parent = gui
			gui.Parent = h.localPlayer.PlayerGui
			h.game.GuiService.SelectedObject = a -- pose initiale : pas de son
			h:settle(2)
			local known = snapshotChildren(h)
			h.game.GuiService.SelectedObject = b -- déplacement : « Select »
			h:settle(2)
			local s = newSound(h, known)
			expect(s ~= nil).toBe(true)
			expect(s.SoundId).toBe(Sounds.Select.id)
			expect(s.Playing).toBe(true)
			expect(#h.errors).toBe(0)
		end)

		it(
			"○, L1/R1, bout de liste, ouverture, refus, apparition, jeu : chaque clé remplie joue son ID",
			function()
				local h, Sounds, Audio = consoleAudio()
				for _, key in filledKeys(Sounds) do
					if key == "Music" then
						continue -- la musique joue en boucle (AudioController), jamais comme un effet
					end
					local known = snapshotChildren(h)
					Audio.play(key)
					local s = newSound(h, known)
					expect({ key = key, soundId = s and s.SoundId, playing = s and s.Playing }).toEqual({
						key = key,
						soundId = Sounds[key].id,
						playing = true,
					})
					expect(s.PlaybackSpeed).toBeNear(Sounds[key].pitch or 1, 1e-6)
				end
				-- réglage « Effets sonores » coupé : plus rien (comportement existant)
				Audio.enabled = false
				local known = snapshotChildren(h)
				Audio.play("Back")
				expect(newSound(h, known)).toBeNil()
				Audio.enabled = true
				expect(#h.errors).toBe(0)
			end
		)
	end)
end
