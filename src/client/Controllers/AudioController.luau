--!strict
-- Joue les sons déclarés dans Shared/Config/Sounds.luau ; un ID vide est ignoré.
--   AudioController.play("Click")
--   AudioController.play("Pop", 0.05, 1.2)   -- variation aléatoire ±5 %, hauteur × 1,2
--   AudioController.playNav()                 -- son de navigation « Select » (manette)
-- Sûr avec de vrais IDs :
--   * ID vide : aucune instance, play() ne fait rien ; un son dont le préchargement échoue est retiré
--     (un avertissement par clé, jamais d'erreur)
--   * chaque appel joue une copie ; au plus Sounds[clé].perFrame copies d'une même clé pour une même
--     image (la plus récente remplace la dernière de l'image) et Sounds[clé].concurrent ensemble (la
--     plus ancienne est coupée) ; copie détruite à Ended, au plus tard éteinte en fondu à maxLength
--   * réglage « Effets sonores » (AudioController.enabled, posé par Client/Util/Prefs) : rien ne joue
--     quand il est coupé, et les copies en cours s'arrêtent à l'image suivante
--   * musique (INT-AUDIO, docs/04 §22.2) : trois pistes en boucle (« Music » de jour, « MusicMoon »,
--     « MusicRush »), jamais jouées par play() et sans maxLength ; une seule piste voulue à la fois
--     (setMusic, appelé par LightingController selon les événements) : l'ancienne descend en fondu
--     puis s'arrête, la nouvelle monte en fondu (fade de la clé) ; volume relatif en dB
--     (setMusicVolumeDb : −12 dB pour un nouveau avant l'étape 9, GDD §9.6) ; elle attend
--     l'instantané du profil (StateController, réglage « Musique » appliqué par Prefs) ; réglage coupé :
--     silence tout de suite
-- Son de navigation (consoles) : « Select » quand GuiService.SelectedObject passe
-- d'un objet à un autre, entrée préférée = manette (Client/Util/Platform), au plus 1 par
-- Config/Console.NavSoundInterval ; rien quand le code pose la première sélection ou l'efface.
-- Un seul retour par action : si Tab, Back, Whoosh, Bump, Click ou Error a joué pendant la même
-- action de l'utilisateur (aucun bouton relâché depuis) et dans la même image ou moins de
-- NavSoundInterval avant, « Select » se tait (sélection déplacée par le code : L1/R1, L2/R2, ○,
-- ouverture d'un panneau) ; dans l'ordre inverse, la copie « Select » de cette action est coupée.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Console = require(Shared.Config.Console)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local Platform = require(Client.Util.Platform)
local State = require(Client.Controllers.StateController)

local AudioController = {}
AudioController.enabled = true -- effets sonores (réglage « sfx », posé par Client/Util/Prefs)

local MUSIC = "Music"
-- Pistes de musique (en boucle, jamais jouées par play())
local MUSIC_KEYS: { [string]: true } = { Music = true, MusicMoon = true, MusicRush = true }
local MUSIC_MIN_DB = -60
local SELECT = "Select"
-- Autres retours d'interface et de navigation : « Select » ne les double pas dans la même action
local UI_FEEDBACK: { [string]: true } = {
	Tab = true,
	Back = true,
	Whoosh = true,
	Bump = true,
	Click = true,
	Error = true,
}

-- Copie jouée d'un son (une « voix »)
type Voice = {
	name: string,
	sound: Sound,
	frame: number, -- image où elle a été lancée
	done: boolean,
	connection: RBXScriptConnection?,
	tween: Tween?,
}

local instances: { [string]: Sound } = {}
local voices: { [string]: { Voice } } = {}
local liveCount = 0
local musicEnabled = true
local musicReady = false -- instantané du profil reçu : le réglage « Musique » est connu
local musicKey = MUSIC -- piste voulue (setMusic)
local musicGain = 1 -- facteur de volume (setMusicVolumeDb)
local musicTweens: { [string]: Tween } = {}
local musicEpoch: { [string]: number } = {} -- +1 à chaque décision sur une piste (fin de fondu périmée)
local started = false
local initialized = false
local lastSelected: Instance? = nil -- dernière sélection GuiService vue
local lastNavAt = -math.huge -- Clock.now() du dernier son « Select »
local frameNo = 0 -- images écoulées (Heartbeat)
local inputEpoch = 0 -- actions de l'utilisateur : +1 à chaque bouton ou touche relâché
local lastStarted: Voice? = nil -- dernière copie lancée par play() (lue par playNav)
-- dernier retour d'interface (UI_FEEDBACK) et dernier « Select » joué par playNav
local feedback: { epoch: number, frame: number, at: number }? = nil
local navVoice: { voice: Voice, epoch: number, at: number }? = nil

-- Même action de l'utilisateur, et même image ou moins de NavSoundInterval d'écart
local function sameAction(epoch: number, frame: number, at: number): boolean
	if epoch ~= inputEpoch then
		return false
	end
	if frame == frameNo then
		return true
	end
	local dt = Clock.now() - at
	return dt >= 0 and dt < Console.NavSoundInterval
end

-- Arrête et détruit une copie (idempotent)
local function release(voice: Voice)
	if voice.done then
		return
	end
	voice.done = true
	liveCount -= 1
	local list = voices[voice.name]
	if list then
		local i = table.find(list, voice)
		if i then
			table.remove(list, i)
		end
	end
	local connection = voice.connection
	if connection then
		connection:Disconnect()
	end
	local tween = voice.tween
	if tween then
		tween:Cancel()
	end
	voice.sound:Stop()
	voice.sound:Destroy()
end

-- maxLength atteint : fondu de sortie puis destruction (filet si Ended n'arrive jamais)
local function fadeOut(voice: Voice, fade: number)
	if voice.done then
		return
	end
	local tween = TweenService:Create(voice.sound, TweenInfo.new(fade), { Volume = 0 })
	voice.tween = tween
	tween:Play()
	task.delay(fade, release, voice)
end

local function stopAll()
	for _, list in voices do
		for _, voice in table.clone(list) do
			release(voice)
		end
	end
end

local function onFrame()
	frameNo += 1
	-- effets coupés pendant que des copies jouent encore : silence tout de suite
	if not AudioController.enabled and liveCount > 0 then
		stopAll()
	end
end

-- Numéro d'asset en fin d'adresse (« rbxassetid://123 », « …/asset/?id=123 ») ; nil sinon
local function assetNumber(contentId: string): string?
	return string.match(contentId, "(%d+)%s*$")
end

-- Retire les clés dont l'asset n'a pas pu être chargé (Failure : un avertissement par clé) ; un
-- délai dépassé (TimedOut) garde le son, qui peut encore se charger
local function onPreloaded(contentId: unknown, status: unknown)
	if type(contentId) ~= "string" or status ~= Enum.AssetFetchStatus.Failure then
		return
	end
	local failed = assetNumber(contentId)
	if failed == nil then
		return
	end
	for name, sound in instances do
		if assetNumber(sound.SoundId) == failed then
			instances[name] = nil
			sound:Destroy()
			warn(`[AudioController] son « {name} » impossible à charger ({contentId}) : désactivé`)
		end
	end
end

function AudioController.Init()
	if not initialized then
		initialized = true
		RunService.Heartbeat:Connect(onFrame)
		UserInputService.InputEnded:Connect(function()
			inputEpoch += 1
		end)
	end
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
			sound.Looped = MUSIC_KEYS[name] == true
			sound.Parent = folder
			instances[name] = sound
			table.insert(toPreload, sound)
		end
	end
	folder.Parent = SoundService
	if #toPreload > 0 then
		task.spawn(function()
			local ok = pcall(function()
				ContentProvider:PreloadAsync(toPreload, onPreloaded)
			end)
			if not ok then
				warn("[AudioController] préchargement des sons impossible : ils se chargeront à la demande")
			end
		end)
	end
end

-- Fondu d'une piste de musique vers `volume` (un seul tween par piste : le nouveau annule l'ancien)
local function tweenMusic(name: string, sound: Sound, volume: number, fade: number)
	local old = musicTweens[name]
	if old then
		old:Cancel()
		musicTweens[name] = nil
	end
	if fade <= 0 then
		sound.Volume = volume
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(fade), { Volume = volume })
	musicTweens[name] = tween
	tween:Play()
end

-- Musique : la piste voulue joue (fondu d'entrée) au volume de sa clé × gain ; les autres
-- descendent en fondu puis s'arrêtent ; réglage coupé : tout s'arrête tout de suite ; rien avant
-- l'instantané du profil
local function updateMusic()
	if not musicReady then
		return
	end
	for name in MUSIC_KEYS do
		local sound = instances[name]
		local def = Sounds[name]
		if sound and def then
			local fade = def.fade :: number
			local epoch = (musicEpoch[name] or 0) + 1
			musicEpoch[name] = epoch
			if musicEnabled and name == musicKey then
				local volume = def.volume * musicGain
				if not sound.Playing then
					sound.Volume = 0
					sound:Play()
					tweenMusic(name, sound, volume, fade)
				elseif math.abs(sound.Volume - volume) > 1e-4 or musicTweens[name] ~= nil then
					tweenMusic(name, sound, volume, fade)
				end
			elseif sound.Playing then
				if not musicEnabled then
					local old = musicTweens[name]
					if old then
						old:Cancel()
						musicTweens[name] = nil
					end
					sound:Stop()
				else
					-- changement de piste : fondu de sortie, puis arrêt si personne ne l'a reprise
					tweenMusic(name, sound, 0, fade)
					task.delay(fade, function()
						if musicEpoch[name] == epoch and sound.Playing then
							musicTweens[name] = nil
							sound:Stop()
						end
					end)
				end
			end
		end
	end
end

local function onProfileReady()
	-- différé : Prefs, servi par le même signal, applique d'abord le réglage « Musique » du profil
	task.defer(function()
		musicReady = true
		updateMusic()
	end)
end

-- Son de navigation « Select » : manette seulement (entrée préférée), au plus 1 par
-- Config/Console.NavSoundInterval, jamais en double d'un autre retour de la même action ; true s'il
-- a été demandé
function AudioController.playNav(): boolean
	if Platform.inputKind() ~= Platform.GAMEPAD then
		return false
	end
	local last = feedback
	if last and sameAction(last.epoch, last.frame, last.at) then
		return false
	end
	local now = Clock.now()
	if now - lastNavAt < Console.NavSoundInterval and now >= lastNavAt then
		return false
	end
	lastNavAt = now
	lastStarted = nil
	AudioController.play(SELECT)
	local voice = lastStarted :: Voice?
	if voice and voice.name == SELECT then
		navVoice = { voice = voice, epoch = inputEpoch, at = now }
	end
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
		if State.ready then
			onProfileReady()
		else
			State.ReadySignal:Once(onProfileReady)
		end
	end
end

-- Réglage « Musique » (Client/Util/Prefs) : coupe ou relance la musique en boucle (avant
-- l'instantané du profil, le choix est seulement retenu)
function AudioController.setMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	updateMusic()
end

function AudioController.isMusicEnabled(): boolean
	return musicEnabled
end

-- Facteur de volume d'un niveau en dB borné à [−60 ; 0] (valeur non finie = 0 dB)
local function gainOf(db: number?): number
	local v = if type(db) == "number" and db == db and db > -math.huge and db < math.huge then db else 0
	return 10 ^ (math.clamp(v, MUSIC_MIN_DB, 0) / 20)
end

-- Piste de musique voulue (INT-AUDIO) : "Music" (jour, défaut), "MusicMoon" ou "MusicRush" ; nil ou
-- clé inconnue = "Music". `db` (facultatif) : volume relatif, comme setMusicVolumeDb. Même piste et
-- même volume : rien (aucun fondu relancé)
function AudioController.setMusic(key: string?, db: number?)
	local wanted = if type(key) == "string" and MUSIC_KEYS[key] then key else MUSIC
	local changed = wanted ~= musicKey
	musicKey = wanted
	if db ~= nil then
		local gain = gainOf(db)
		if math.abs(gain - musicGain) >= 1e-6 then
			musicGain = gain
			changed = true
		end
	end
	if changed then
		updateMusic()
	end
end

-- Volume relatif de la musique en dB (0 = volume de la clé ; −12 = nouveau pendant l'accueil)
function AudioController.setMusicVolumeDb(db: number)
	local gain = gainOf(db)
	if math.abs(gain - musicGain) < 1e-6 then
		return
	end
	musicGain = gain
	updateMusic()
end

-- Piste voulue et gain (specs, Diagnostics)
function AudioController.music(): (string, number)
	return musicKey, musicGain
end

-- Hauteur demandée par l'appelant : nombre fini et positif, sinon 1 (hauteur du son déclaré)
local function validPitch(pitch: number?): number
	if type(pitch) == "number" and pitch == pitch and pitch > 0 and pitch < math.huge then
		return pitch
	end
	return 1
end

-- Retour d'interface joué : retenu pour « Select » ; un « Select » de la même action est coupé
local function noteFeedback(name: string)
	if not UI_FEEDBACK[name] then
		return
	end
	local now = Clock.now()
	feedback = { epoch = inputEpoch, frame = frameNo, at = now }
	local nav = navVoice
	if nav and not nav.voice.done and sameAction(nav.epoch, nav.voice.frame, nav.at) then
		release(nav.voice)
	end
	navVoice = nil
end

-- Joue une copie du son `name` : PlaybackSpeed = hauteur déclarée × `pitch` (défaut 1, ex. une
-- série de pressions qui monte : 1 + min(0,5 ; 0,01 × n)) × (1 ± `pitchVariation` au hasard)
function AudioController.play(name: string, pitchVariation: number?, pitch: number?)
	noteFeedback(name)
	if not AudioController.enabled or MUSIC_KEYS[name] then
		return
	end
	local template = instances[name]
	local def = Sounds[name]
	if not template or not def then
		return
	end
	local list = voices[name]
	if not list then
		list = {}
		voices[name] = list
	end
	-- plafond par image : la dernière copie de cette image laisse la place à la plus récente
	local inFrame = 0
	local latest: Voice? = nil
	for _, voice in list do
		if voice.frame == frameNo then
			inFrame += 1
			latest = voice
		end
	end
	if latest and inFrame >= (def.perFrame :: number) then
		release(latest)
	end
	-- plafond simultané : la plus ancienne copie est coupée
	while #list >= (def.concurrent :: number) do
		release(list[1])
	end
	local sound = template:Clone()
	local variation = if type(pitchVariation) == "number" and pitchVariation == pitchVariation
		then math.clamp(pitchVariation, 0, 0.5)
		else 0
	sound.PlaybackSpeed = (def.pitch or 1) * validPitch(pitch) * (1 + (math.random() * 2 - 1) * variation)
	local voice: Voice = { name = name, sound = sound, frame = frameNo, done = false }
	table.insert(list, voice)
	liveCount += 1
	voice.connection = sound.Ended:Connect(function()
		release(voice)
	end)
	sound.Parent = SoundService
	sound:Play()
	lastStarted = voice
	task.delay(def.maxLength :: number, fadeOut, voice, def.fade :: number)
end

return AudioController
