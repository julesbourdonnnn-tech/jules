--!strict
-- Prefs : préférences du joueur côté client (contrat, docs/04-architecture.md §13.3).
-- Fusionne profile.settings (répliqué par StateController) avec GuiService, résout la langue
-- (réglage « Langue » prioritaire sur LocaleId) et applique les réglages aux modules existants :
--   Juice.forceReducedMotion / Juice.cameraShakeEnabled, AudioController.enabled / setMusicEnabled.
--
--   Prefs.t("hud.line.empty")                  -- texte traduit dans la langue courante
--   Prefs.number(1240000)                      -- "1.24M" / "1,24 M"
--   Prefs.reducedMotion(), Prefs.lowGraphics()
--   Prefs.Changed:Connect(function(key, value) end)
--   Prefs.LanguageChanged:Connect(function(lang) end)   -- chaque UI ré-applique ses textes

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.Settings)
local Localization = require(Shared.Localization)
local Format = require(Shared.Util.Format)
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local AudioController = require(Client.Controllers.AudioController)
local Juice = require(Client.UI.Juice)

local Prefs = {}
Prefs.Changed = Signal.new() :: Signal.Signal<string, any>
Prefs.LanguageChanged = Signal.new() :: Signal.Signal<Localization.Language>

local current: { [string]: any } = {}
local language: Localization.Language = "en"
local translator: Localization.Translator = Localization.translator("en")

local function defaults(): { [string]: any }
	local out = {}
	for key, def in SettingsConfig do
		if def.saved then
			out[key] = def.default
		end
	end
	return out
end

local function systemReducedMotion(): boolean
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

local function resolveLanguage(): Localization.Language
	local lang = current.lang
	if lang == "en" or lang == "fr" then
		return lang
	end
	local player = Players.LocalPlayer
	return Localization.languageFor(if player then player.LocaleId else nil)
end

local function apply()
	Juice.forceReducedMotion = current.reducedMotion == true
	Juice.cameraShakeEnabled = not (current.reducedMotion == true or systemReducedMotion())
	AudioController.enabled = current.sfx ~= false
	AudioController.setMusicEnabled(current.music ~= false)
	local lang = resolveLanguage()
	if lang ~= language then
		language = lang
		translator = Localization.translator(lang)
		Prefs.LanguageChanged:Fire(lang)
	end
end

local function onSettings(value: any)
	if type(value) ~= "table" then
		return
	end
	local nextValues = defaults()
	for key, v in value do
		if SettingsConfig[key] and type(v) == SettingsConfig[key].kind then
			nextValues[key] = v
		end
	end
	local changed: { string } = {}
	for key, v in nextValues do
		if current[key] ~= v then
			table.insert(changed, key)
		end
	end
	current = nextValues
	apply()
	for _, key in changed do
		Prefs.Changed:Fire(key, current[key])
	end
end

function Prefs.Init()
	current = defaults()
	language = resolveLanguage()
	translator = Localization.translator(language)
end

function Prefs.Start()
	apply()
	State.observe("settings", onSettings)
	pcall(function()
		GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			apply()
			Prefs.Changed:Fire("reducedMotion", Prefs.reducedMotion())
		end)
	end)
end

-- Valeur d'un réglage du profil (valeurs par défaut de Config/Settings avant l'instantané)
function Prefs.get(key: string): any
	return current[key]
end

function Prefs.reducedMotion(): boolean
	return current.reducedMotion == true or systemReducedMotion()
end

function Prefs.lowGraphics(): boolean
	return current.lowGraphics == true
end

function Prefs.language(): Localization.Language
	return language
end

function Prefs.t(key: string, vars: { [string]: any }?): string
	return translator(key, vars)
end

-- Nombres et durées dans la langue courante (GDD §13.1)
function Prefs.number(n: number): string
	return Format.abbreviate(n, language)
end

function Prefs.commas(n: number): string
	return Format.commas(n, language)
end

function Prefs.duration(seconds: number): string
	return Format.duration(seconds, language)
end

-- Exposé pour les tests
Prefs._onSettings = onSettings

return Prefs
