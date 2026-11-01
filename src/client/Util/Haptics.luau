--!strict
-- Haptics : vibrations « avec modération » (carte Config/Console.Haptics ; reprise de Comet Conga).
--   Haptics.play("snipped")            -- événement de la carte
--   Haptics.play("cometImpact", 0.6)   -- atténué (distance) ; sous Haptics.MinScale : rien
-- Règles :
--   * manette active (Platform.inputKind() = manette) : HapticEffect du type de l'événement
--     (UIClick, GameplayCollision…), une instance réutilisée par type ; repli
--     HapticService:SetMotor(Gamepad1, moteur, force) pendant la durée si HapticEffect est
--     indisponible
--   * vibration atténuée (`scale` < FULL_SCALE, ex. événement lointain) : jamais l'effet
--     préréglé, qui se joue toujours à pleine force, mais SetMotor(Gamepad1, moteur, force × scale)
--     pendant la durée ; manette sans moteur pris en charge : rien (modération)
--   * appareil tactile : jamais (console d'abord, aucun chemin de code tactile : note INT-TV)
--   * clavier-souris : jamais (une manette branchée mais inutilisée ne vibre pas)
--   * délai minimal Config/Console.Haptics.Cooldown entre deux vibrations, sauf priorité supérieure
--     ou événement `cooldownExempt` (sirène du Rush : contrat v1.2, note INT-HAPTICS)
--   * réglage « vibration » (Prefs) à false : aucune vibration ; réglage absent : activé
-- Haptics.Played(événement) est émis à chaque vibration jouée (specs, débogage).

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Console = require(Shared.Config.Console)
local Clock = require(Shared.Util.Clock)
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local Platform = require(Client.Util.Platform)
local Prefs = require(Client.Util.Prefs)

local Haptics = {}

Haptics.Played = Signal.new() :: Signal.Signal<string>

-- Au-dessus de ce facteur d'atténuation, l'effet préréglé (pleine force) reste le bon rendu ;
-- en dessous, la force est réglée au moteur (force de la carte × facteur)
local FULL_SCALE = 0.9

local lastAt = -math.huge
local lastPriority = 0
local effects: { [string]: Instance } = {}
local effectsUnavailable = false
local motorToken = 0

local function enumItem(enum: any, name: string): EnumItem?
	local ok, item = pcall(function()
		return enum[name]
	end)
	return if ok and typeof(item) == "EnumItem" then item else nil
end

-- Réglage du joueur (absent tant que la clé n'existe pas dans Config/Settings : activé)
function Haptics.enabled(): boolean
	local ok, value = pcall(Prefs.get, "vibration")
	return not (ok and value == false)
end

local function effectFor(typeName: string): Instance?
	if effectsUnavailable then
		return nil
	end
	local existing = effects[typeName]
	if existing and existing.Parent then
		return existing
	end
	local hapticType = enumItem(Enum.HapticEffectType, typeName)
	if hapticType == nil then
		return nil
	end
	local ok, effect = pcall(function()
		local e = Instance.new("HapticEffect")
		e.Name = "Haptic_" .. typeName;
		(e :: any).Type = hapticType
		e.Parent = workspace
		return e
	end)
	if not ok then
		-- moteur sans HapticEffect : repli SetMotor pour toute la session
		effectsUnavailable = true
		warn("[Haptics] HapticEffect indisponible, repli HapticService:SetMotor :", effect)
		return nil
	end
	effects[typeName] = effect
	return effect
end

local function supported(inputType: Enum.UserInputType, motor: Enum.VibrationMotor): boolean
	local ok, result = pcall(function()
		return HapticService:IsVibrationSupported(inputType)
			and HapticService:IsMotorSupported(inputType, motor)
	end)
	return ok and result == true
end

local function runMotor(
	inputType: Enum.UserInputType,
	motor: Enum.VibrationMotor,
	power: number,
	duration: number
)
	motorToken += 1
	local token = motorToken
	pcall(function()
		HapticService:SetMotor(inputType, motor, power)
	end)
	task.delay(math.clamp(duration, 0, 1), function()
		if token == motorToken then
			pcall(function()
				HapticService:SetMotor(inputType, motor, 0)
			end)
		end
	end)
end

-- Joue l'événement `name` de la carte ; `scale` (0-1) atténue la force (moteur à force × scale
-- sous FULL_SCALE, l'effet préréglé ne sachant pas s'atténuer) et coupe la vibration sous
-- Haptics.MinScale. Retourne true si une vibration a été demandée.
function Haptics.play(name: string, scale: number?): boolean
	local def = Console.Haptics.Events[name]
	if def == nil or not Haptics.enabled() then
		return false
	end
	local k = if type(scale) == "number" and scale == scale then math.clamp(scale, 0, 1) else 1
	if k < Console.Haptics.MinScale then
		return false
	end
	local kind = Platform.inputKind()
	local inputType: Enum.UserInputType
	if kind == Platform.GAMEPAD then
		inputType = Enum.UserInputType.Gamepad1
	else
		return false
	end
	local now = Clock.now()
	if
		not def.cooldownExempt
		and now - lastAt < Console.Haptics.Cooldown
		and now >= lastAt
		and def.priority <= lastPriority
	then
		return false
	end
	local motor = (
		enumItem(Enum.VibrationMotor, def.motor) or Enum.VibrationMotor.Small
	) :: Enum.VibrationMotor
	local played = false
	if inputType == Enum.UserInputType.Gamepad1 and k >= FULL_SCALE then
		local effect = effectFor(def.effect)
		if effect then
			played = pcall(function()
				(effect :: any):Play()
			end)
		end
	end
	if not played then
		if not supported(inputType, motor) then
			return false
		end
		runMotor(inputType, motor, def.strength * k, def.duration)
		played = true
	end
	lastAt = now
	lastPriority = def.priority
	Haptics.Played:Fire(name)
	return true
end

-- Remise à zéro (specs)
function Haptics._reset()
	lastAt = -math.huge
	lastPriority = 0
end

return Haptics
