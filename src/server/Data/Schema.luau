--!strict
-- Schéma des données sauvegardées, version 1 (GDD §12.6). Contrat : docs/04-architecture.md §8.
--  * augmenter VERSION et ajouter une étape dans migrate() à chaque changement incompatible
--  * ajouter un champ = l'ajouter dans defaults() (Tables.reconcile le crée chez les anciens joueurs)
--  * PRIVATE_KEYS : jamais envoyé au client
--  * UN SEUL service propriétaire écrit chaque clé (tableau OWNERS) ; les autres lisent
--    DataService.get(player) sans jamais muter, ou passent par l'API du propriétaire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)

local Schema = {}

Schema.STORE_NAME = "PlayerData_v1"
Schema.VERSION = 1

Schema.PRIVATE_KEYS = {
	receipts = true,
	codes = true,
	flags = true,
} :: { [string]: boolean }

-- Propriétaire de chaque clé de premier niveau (docs/04-architecture.md §8)
Schema.OWNERS = {
	version = "DataService",
	glow = "EconomyService",
	glowCarry = "EconomyService",
	lastSettle = "EconomyService",
	lastOnline = "EconomyService",
	idleRate = "EconomyService",
	stardust = "EconomyService",
	supernovas = "EconomyService",
	upgrades = "EconomyService",
	boosts = "EconomyService",
	caps = "EconomyService",
	nebbies = "AtlasService",
	nextUid = "AtlasService",
	perchIncome = "AtlasService",
	atlas = "AtlasService",
	badges = "AtlasService",
	atlasRewards = "AtlasService",
	onboarding = "QuestService",
	daily = "QuestService",
	quests = "QuestService",
	weekly = "QuestService",
	rookie = "QuestService",
	stats = "QuestService",
	codes = "QuestService",
	settings = "NestService",
	cosmetics = "NestService",
	unlocks = "NestService",
	weeklyBest = "LeaderboardService",
	starterKit = "ProductService",
	passes = "MonetizationService",
	receipts = "MonetizationService",
	flags = "CongaService",
} :: { [string]: string }

local function defaultSettings(): { [string]: any }
	local out = {}
	for key, def in SettingsConfig do
		if def.saved then
			out[key] = def.default
		end
	end
	return out
end

function Schema.defaults(): { [string]: any }
	return {
		version = Schema.VERSION,
		-- économie (§4.9) — EconomyService
		glow = 0,
		glowCarry = 0, -- fraction de Glow ∈ [0 ; 1[
		lastSettle = 0, -- Clock.now() du dernier règlement
		lastOnline = 0, -- Clock.unix() de la dernière présence
		idleRate = 0, -- Glow/s actuel (M compris), répliqué pour la prédiction client
		stardust = 0,
		supernovas = 0,
		upgrades = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 },
		boosts = { personalUntil = 0 }, -- Clock.unix()
		caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false }, -- plafonds du jour UTC
		-- collection (§4.13, §4.14) — AtlasService
		-- nebbies[uid] = { s = espèce 1-36, f = forme 0-5, v = bits (1 Golden, 2 Huge, 4 Starborn),
		--                  st = étoiles 1-5, lk = verrou (bool) }
		nebbies = {},
		nextUid = 1, -- uid = "u" .. nextUid
		perchIncome = 0, -- Σ revenu passif des perchés, SANS M (base du taux hors ligne)
		atlas = { 0, 0, 0, 0, 0, 0, 0 }, -- 7 mots de 32 bits : bit (s − 1) × 6 + f
		badges = { 0, 0, 0, 0 }, -- Golden : bit s − 1 ; Huge : 36 + s − 1 ; Starborn : 72 + s − 1
		atlasRewards = 0, -- nombre d'entrées du dernier jalon réclamé
		-- objectifs (§7) — QuestService
		onboarding = { step = 0, p = 0 }, -- step 0 = pas commencé, 1-7 = quête en cours, 8 = fini
		daily = { day = 0, step = 1 }, -- jour UTC du dernier claim, prochain jour du calendrier
		quests = { day = 0, list = {}, rerolls = 0, starClaimed = false }, -- list = { { id, p, done, claimed } × 3 }
		weekly = { week = 0, banked = 0, claimed = false },
		rookie = { sessions = 0, playSeconds = 0, done = false },
		-- social et cosmétiques — NestService
		settings = defaultSettings(),
		cosmetics = { style = "default", title = "", nestTheme = "default" },
		unlocks = { styles = {}, titles = {}, themes = {} },
		weeklyBest = { week = 0, conga = 0 }, -- LeaderboardService
		starterKit = false, -- ProductService
		stats = { -- QuestService (incréments via signaux)
			catches = 0,
			parades = 0,
			longestParade = 0,
			snipsDealt = 0,
			nebbiesSnipped = 0,
			snipsTaken = 0,
			cometsHeld = 0,
			cometsBanked = 0,
			beaconWins = 0,
			wispsPopped = 0,
			cheersGiven = 0,
			cheersReceived = 0,
			escortSeconds = 0,
			playSeconds = 0,
			sessions = 0,
			lastCrewDay = 0,
			fusions = 0,
		},
		-- existant / privé
		passes = {}, -- [passKey] = true (MonetizationService)
		receipts = {}, -- PurchaseId déjà crédités (MonetizationService)
		codes = {}, -- [CODE] = true (QuestService)
		flags = { strikes = 0, lbBanned = false }, -- anti-triche (CongaService)
	}
end

-- Migrations pures, appliquées dans l'ordre. On n'efface jamais un champ dans la version qui
-- le remplace ; DataService appelle ensuite Tables.reconcile(data, defaults()).
function Schema.migrate(data: { [string]: any }, fromVersion: number): { [string]: any }
	if fromVersion < 1 then
		-- v0 (schéma d'exemple « coins ») → v1 : les pièces deviennent du Glow
		local coins = data.coins
		if type(coins) == "number" and coins == coins and data.glow == nil then
			data.glow = math.max(0, math.floor(coins))
		end
	end
	return data
end

return Schema
