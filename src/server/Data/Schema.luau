--!strict
-- Schéma des données sauvegardées.
--  * augmenter VERSION et ajouter une étape dans migrate() à chaque changement incompatible
--  * ajouter un champ = l'ajouter dans defaults() (reconcile le crée chez les anciens joueurs)
--  * PRIVATE_KEYS : jamais envoyé au client

local Schema = {}

Schema.STORE_NAME = "PlayerData_v1"
Schema.VERSION = 1

Schema.PRIVATE_KEYS = {
	receipts = true,
} :: { [string]: boolean }

function Schema.defaults(): { [string]: any }
	return {
		version = Schema.VERSION,
		coins = 0,
		receipts = {}, -- PurchaseId des produits déjà crédités (idempotence)
	}
end

function Schema.migrate(data: { [string]: any }, fromVersion: number): { [string]: any }
	-- if fromVersion < 2 then ... end
	local _ = fromVersion
	return data
end

return Schema
