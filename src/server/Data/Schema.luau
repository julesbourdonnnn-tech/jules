--!strict
-- Schéma des données sauvegardées, version 1 (socle minimal ; l'architecte l'étend avec les données
-- du jeu : pièces, créatures, ranch…).
--  * augmenter VERSION et ajouter une étape dans migrate() à chaque changement incompatible
--  * ajouter un champ = l'ajouter dans defaults() (Tables.reconcile le crée chez les anciens joueurs)
--  * PRIVATE_KEYS : jamais envoyé au client
--  * STREAMED_KEYS : grandes tables envoyées par morceaux après l'instantané (DataService)
--  * UN SEUL service propriétaire écrit chaque clé (tableau OWNERS) ; les autres lisent
--    DataService.get(player) sans jamais muter, ou passent par l'API du propriétaire.
--    « (à attribuer) » : clé du socle sans service propriétaire pour l'instant.
-- Contract.spec : valeurs par défaut sérialisables, une clé = un propriétaire, clés privées.

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

-- Tables de profil envoyées par morceaux (au-delà de DataService.Settings.SNAPSHOT_INLINE entrées).
-- Vide dans le socle ; ex. la collection de créatures du jeu.
Schema.STREAMED_KEYS = {} :: { string }

-- Propriétaire de chaque clé de premier niveau
Schema.OWNERS = {
	version = "DataService",
	firstJoin = "(à attribuer)",
	lastOnline = "(à attribuer)",
	settings = "(à attribuer)",
	passes = "MonetizationService",
	receipts = "MonetizationService",
	codes = "(à attribuer)",
	flags = "(à attribuer)",
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
		-- horodatages (Clock.unix()) : première arrivée, dernière présence (gains hors ligne)
		firstJoin = 0,
		lastOnline = 0,
		-- réglages du joueur (Config/Settings, clés saved = true)
		settings = defaultSettings(),
		-- achats
		passes = {}, -- [passKey] = true (MonetizationService)
		receipts = {}, -- PurchaseId déjà crédités, au plus 100 (MonetizationService)
		codes = {}, -- [CODE] = true : codes promo déjà utilisés (Data/Codes)
		-- anti-triche : retours forcés comptés, exclusion des classements
		flags = { strikes = 0, lbBanned = false },
	}
end

-- Migrations pures, appliquées dans l'ordre. On n'efface jamais un champ dans la version qui le
-- remplace ; DataService appelle ensuite Tables.reconcile(data, defaults()). Une version absente ou
-- illisible (sauvegarde abîmée) vaut 0.
function Schema.migrate(data: { [string]: any }, fromVersion: number): { [string]: any }
	if fromVersion < 1 then
		-- v0 → v1 : rien à transformer dans le socle (reconcile ajoute les champs manquants). Les
		-- étapes du jeu s'ajoutent ici, chacune derrière « if fromVersion < N then ».
		local _ = data
	end
	return data
end

return Schema
