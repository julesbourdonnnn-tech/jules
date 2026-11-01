--!strict
-- Notify : retours au joueur (repris de Comet Conga).
--   Notify.feedback(player, "feedback.notEnoughCoins", { missing = 1200 }, "error")
--   Notify.celebrate(player, "upgrade", { level = 4 })
--   Notify.banner("rareHatch", { userId = 1, name = "Mira" }, player)  -- file de serveur (Signals)
--   Notify.personalBanner(player, "welcomeBack", {})
-- Les clés sont des clés de localisation (Shared/Localization/Strings.luau) : le client traduit.
-- Un joueur parti ne reçoit rien (aucune erreur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Signals = require(script.Parent.Parent.Signals)

local Notify = {}

-- Priorité par défaut d'une bannière dont la sorte n'est pas listée (la plus basse)
Notify.DEFAULT_PRIORITY = 7

-- Priorités des bannières : 1 = plus haute, 7 = plus basse. Les exploits de joueurs passent avant
-- les bannières d'information. Chaque sorte a son texte « banner.<sorte> » en anglais et en français
-- (Contract.spec). Rempli par les paquets du jeu.
Notify.BANNER_PRIORITY = {} :: { [string]: number }

local function connected(player: Player): boolean
	return player.Parent ~= nil
end

function Notify.feedback(player: Player, key: string, vars: { [string]: any }?, tone: Types.FeedbackTone?)
	if not connected(player) then
		return
	end
	local payload: Types.FeedbackPayload = { key = key, vars = vars or {}, tone = tone or "info" }
	Net.event("Feedback"):FireClient(player, payload)
end

function Notify.celebrate(player: Player, kind: Types.CelebrateKind, data: { [string]: any }?)
	if not connected(player) then
		return
	end
	local payload: Types.CelebratePayload = { kind = kind, data = data or {} }
	Net.event("Celebrate"):FireClient(player, payload)
end

-- Bannière de serveur : passe par la file d'attente du service abonné à Signals.BannerRequested
-- (priorité, durée, débit par joueur source)
function Notify.banner(kind: Types.BannerKind, args: { [string]: any }?, source: Player?)
	Signals.BannerRequested:Fire(kind, args or {}, source)
end

-- Bannière personnelle : directe, sans file serveur
function Notify.personalBanner(player: Player, kind: Types.BannerKind, args: { [string]: any }?)
	if not connected(player) then
		return
	end
	local payload: Types.BannerPayload = {
		kind = kind,
		args = args or {},
		priority = Notify.BANNER_PRIORITY[kind] or Notify.DEFAULT_PRIORITY,
		personal = true,
	}
	Net.event("Banner"):FireClient(player, payload)
end

return Notify
