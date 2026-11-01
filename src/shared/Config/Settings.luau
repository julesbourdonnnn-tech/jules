--!strict
-- Réglages joueur génériques du socle. Source unique pour : les valeurs par défaut du profil
-- (Data/Schema), la validation d'un futur remote de réglage côté serveur et l'interface
-- (Client/Util/Prefs). Les réglages propres au jeu (ex. mode Cozy, mode Rush) s'ajoutent ici.
--   kind     : type de la valeur ("boolean" | "string")
--   default  : valeur par défaut (du type `kind`)
--   values   : chaînes autorisées (kind "string")
--   saved    : stocké dans profile.settings (false : réglage de serveur, en mémoire)
--   order    : ordre d'affichage
--   ownerOnly: serveur privé, propriétaire seulement
--   cooldown : s minimales entre deux changements (validées par le serveur)
-- Chaque réglage a son texte « settings.<clé> » en anglais et en français (Contract.spec).

export type SettingDef = {
	kind: "boolean" | "string",
	default: boolean | string,
	values: { [string]: boolean }?,
	saved: boolean,
	order: number,
	ownerOnly: boolean?,
	cooldown: number?,
}

local Settings = {
	reducedMotion = { kind = "boolean", default = false, saved = true, order = 1 },
	lowGraphics = { kind = "boolean", default = false, saved = true, order = 2 },
	music = { kind = "boolean", default = true, saved = true, order = 3 },
	sfx = { kind = "boolean", default = true, saved = true, order = 4 },
	-- vibrations manette et téléphone (Client/Util/Haptics)
	vibration = { kind = "boolean", default = true, saved = true, order = 5 },
	lang = {
		kind = "string",
		default = "auto",
		values = { auto = true, en = true, fr = true },
		saved = true,
		order = 6,
	},
} :: { [string]: SettingDef }

return Settings
