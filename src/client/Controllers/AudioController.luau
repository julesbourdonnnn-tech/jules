--!strict
-- Joue les sons déclarés dans Shared/Config/Sounds.luau ; un ID vide est ignoré.
--   AudioController.play("Coin")
--   AudioController.play("Catch", 0.05, 1.2) -- variation aléatoire ±5 %, hauteur × 1,2
--   AudioController.playNav()                 -- son de navigation « Select » (manette)
-- Son de navigation (docs/07-console-ps5.md §9.2) : « Select » quand GuiService.SelectedObject passe
-- d'un objet à un autre, entrée préférée = manette (Client/Util/Platform), au plus 1 par
-- Config/Console.NavSoundInterval ; rien quand le code pose la première sélection ou l'efface.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Console = require(Shared.Config.Console)
local Clock = require(Shared.Util.Clock)

local Platform = require(script.Parent.Parent.Util.Platform)

local AudioController = {}
AudioController.enabled = true -- effets sonores (réglage « sfx », posé par Client/Util/Prefs)

local instances: { [string]: Sound } = {}
local musicEnabled = true
local started = false
local lastSelected: Instance? = nil -- dernière sélection GuiService vue
local lastNavAt = -math.huge -- Clock.now() du dernier son « Select »

function AudioController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "GameSounds"
	local toPreload = {}
	for name, def in Sounds do
		if def.id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = def.id
			sound.Volume = def.volume
			sound.PlaybackSpeed = def.pitch or 1
			sound.Parent = folder
			instances[name] = sound
			table.insert(toPreload, sound)
		end
	end
	folder.Parent = SoundService
	if #toPreload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(toPreload)
			end)
		end)
	end
end

-- Son de navigation « Select » : manette seulement (entrée préférée), au plus 1 par
-- Config/Console.NavSoundInterval ; true s'il a été demandé
function AudioController.playNav(): boolean
	if Platform.inputKind() ~= Platform.GAMEPAD then
		return false
	end
	local now = Clock.now()
	if now - lastNavAt < Console.NavSoundInterval and now >= lastNavAt then
		return false
	end
	lastNavAt = now
	AudioController.play("Select")
	return true
end

-- Sélection déplacée d'un objet à un autre (croix, stick, code) : « Select » ; première sélection
-- posée par le code ou sélection effacée : rien
local function onSelectionChanged()
	local selected: Instance? = GuiService.SelectedObject
	local previous = lastSelected
	lastSelected = selected
	if previous ~= nil and selected ~= nil and previous ~= selected then
		AudioController.playNav()
	end
end

function AudioController.Start()
	if not started then
		started = true
		lastSelected = GuiService.SelectedObject
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged)
	end
	local music = instances.Music
	if music then
		music.Looped = true
		if musicEnabled then
			music:Play()
		end
	end
end

-- Réglage « Musique » (Client/Util/Prefs) : coupe ou relance la musique en boucle
function AudioController.setMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	local music = instances.Music
	if not music then
		return
	end
	if enabled and not music.Playing then
		music:Play()
	elseif not enabled and music.Playing then
		music:Stop()
	end
end

function AudioController.isMusicEnabled(): boolean
	return musicEnabled
end

-- Hauteur demandée par l'appelant : nombre fini et positif, sinon 1 (hauteur du son déclaré)
local function validPitch(pitch: number?): number
	if type(pitch) == "number" and pitch == pitch and pitch > 0 and pitch < math.huge then
		return pitch
	end
	return 1
end

-- Joue une copie du son `name` : PlaybackSpeed = hauteur déclarée × `pitch` (défaut 1, ex. capture
-- 1 + min(0,5 ; 0,01 × n), GDD §9.4) × (1 ± `pitchVariation` au hasard)
function AudioController.play(name: string, pitchVariation: number?, pitch: number?)
	if not AudioController.enabled then
		return
	end
	local template = instances[name]
	if not template then
		return
	end
	local sound = template:Clone()
	local def = Sounds[name]
	local variation = pitchVariation or 0
	sound.PlaybackSpeed = (def.pitch or 1) * validPitch(pitch) * (1 + (math.random() * 2 - 1) * variation)
	sound.Parent = SoundService
	sound:Play()
	task.delay(math.max(sound.TimeLength, 1) + 0.5, function()
		sound:Destroy()
	end)
end

return AudioController
