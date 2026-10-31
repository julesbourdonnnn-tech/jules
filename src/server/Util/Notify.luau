--!strict
-- Notify : retours au joueur (contrat, docs/04-architecture.md §10.3).
--   Notify.feedback(player, "feedback.notEnoughGlow", { missing = 1200 }, "error")
--   Notify.celebrate(player, "upgrade", { track = "conga", level = 4 })
--   Notify.banner("megaParade", { userId = 1, name = "Mira", n = 32 }, player)  -- file serveur (CrewService)
--   Notify.personalBanner(player, "rookieEnd", {})
-- Les clés sont des clés de localisation (Shared/Localization/Strings.luau) : le client traduit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Signals = require(script.Parent.Parent.Signals)

local Notify = {}

-- Priorités des bannières (§6.5) : 1 = plus haute. Les bannières d'information (météo, Balise…)
-- passent après les exploits de joueurs.
Notify.BANNER_PRIORITY = {
	mythicCatch = 1,
	cometStolen = 2,
	cometBanked = 2,
	cometBurst = 2,
	cometPickup = 2,
	cometWarn = 2,
	supernova = 3,
	legendaryCatch = 4,
	megaParade = 4,
	serverRecord = 5,
	glowParty = 6,
	beaconStart = 6,
	beaconWin = 6,
	beaconTop = 6,
	beaconFail = 6,
	goldenNight = 6,
	starfall = 6,
	weather = 7,
	liveOps = 7,
	rookieEnd = 1,
	atlasMilestone = 3,
} :: { [string]: number }

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

-- Bannière de serveur : passe par la file d'attente de CrewService (3 max, 3 s, priorité,
-- 1 bannière / 10 s par joueur source)
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
		priority = Notify.BANNER_PRIORITY[kind] or 7,
		personal = true,
	}
	Net.event("Banner"):FireClient(player, payload)
end

return Notify
