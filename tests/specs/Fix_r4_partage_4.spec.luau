--!nocheck
-- Correctif r4-partage-4 : sons de navigation et d'interface audibles (docs/07-console-ps5.md R9, §9.2)
--   * Select, Back, Tab, Bump, Whoosh, Error et Pop ont un vrai ID « rbxassetid://<nombre> » : avant,
--     tous vides, AudioController.Init les sautait et la PS5 n'avait aucun retour sonore (sélection
--     déplacée, ○, L1/R1, L2/R2, bout de liste, refus)
--   * provenance : jeu de sons d'interface publié par Roblox lui-même (feature-packages-core des
--     Feature Packages officiels, utilisables sans téléversement)
--   * deux clés qui partagent un enregistrement s'en distinguent par la hauteur (≥ 15 %)
--   * de bout en bout sur le client console : chaque clé crée un vrai Sound qui joue cet ID
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

	-- Clés de navigation (docs/07 §9.2) et retours d'interface joués à la manette (activation,
	-- ouverture de panneau, refus, apparition). Click attend la levée de la règle « vides par
	-- défaut » de Contract.spec (notes d'intégration) : pas exigé ici.
	local UI_KEYS = { "Select", "Back", "Tab", "Bump", "Whoosh", "Error", "Pop" }

	-- Sons d'interface publiés par Roblox : github.com/Roblox/resources,
	-- packages/feature-packages-core/src/Configs/SharedConstants.lua (Sounds.Ids)
	local ROBLOX_UI_SET = {
		["rbxassetid://17161204665"] = "BUTTON_HOVER",
		["rbxassetid://17161216230"] = "BUTTON_ACTIVATED",
		["rbxassetid://17161253544"] = "PROMPT_OPENED",
		["rbxassetid://17161255584"] = "PROMPT_CLOSED",
		["rbxassetid://17161225362"] = "PURCHASE_BUTTON_ACTIVATED",
		["rbxassetid://17161210152"] = "PURCHASE_EFFECT",
	}

	local function loadSounds(h)
		return h:require("ReplicatedStorage.Shared.Config.Sounds")
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
			"Select, Back, Tab, Bump, Whoosh, Error, Pop : ID rempli, exactement rbxassetid://<nombre>",
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

		it("provenance : chaque clé d'interface vient du jeu de sons publié par Roblox", function()
			local Sounds = loadSounds(Harness.new({ mode = "client" }))
			for _, key in UI_KEYS do
				local id = Sounds[key].id
				expect({ key = key, id = id, roblox = ROBLOX_UI_SET[id] ~= nil }).toEqual({
					key = key,
					id = id,
					roblox = true,
				})
			end
		end)

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

		it(
			"Init : un Sound préchargé par clé d'interface dans SoundService.GameSounds, avec son ID",
			function()
				local h, Sounds, _, preloaded = consoleAudio()
				local folder = h.game:GetService("SoundService"):FindFirstChild("GameSounds")
				expect(folder ~= nil).toBe(true)
				for _, key in UI_KEYS do
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
			end
		)

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

		it("○, L1/R1, bout de liste, ouverture, refus, apparition : chaque clé joue son ID", function()
			local h, Sounds, Audio = consoleAudio()
			for _, key in UI_KEYS do
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
		end)
	end)
end
