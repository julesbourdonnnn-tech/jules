--!strict
-- Joue les sons déclarés dans Shared/Config/Sounds.luau ; un ID vide est ignoré.
--   AudioController.play("Coin")

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)

local AudioController = {}
AudioController.enabled = true

local instances: { [string]: Sound } = {}

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

function AudioController.Start()
	local music = instances.Music
	if music then
		music.Looped = true
		music:Play()
	end
end

function AudioController.play(name: string, pitchVariation: number?)
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
	sound.PlaybackSpeed = (def.pitch or 1) * (1 + (math.random() * 2 - 1) * variation)
	sound.Parent = SoundService
	sound:Play()
	task.delay(math.max(sound.TimeLength, 1) + 0.5, function()
		sound:Destroy()
	end)
end

return AudioController
