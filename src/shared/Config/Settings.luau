--!strict
-- Réglages joueur (GDD §10.3, §4.16, §13). Contrat : docs/04-architecture.md §9.
-- Source unique pour : les valeurs par défaut du profil (Data/Schema), la validation du remote
-- SetSetting (NestService) et l'interface (Panels/Settings, Util/Prefs).

export type SettingDef = {
	kind: "boolean" | "string",
	default: boolean | string,
	values: { [string]: boolean }?, -- valeurs autorisées (chaînes)
	saved: boolean, -- stocké dans profile.settings
	order: number, -- ordre d'affichage
	ownerOnly: boolean?, -- serveur privé : propriétaire seulement (privateNoSnip)
	harborOnly: boolean?, -- modifiable seulement dans le port sûr de son Nid (zen)
	cooldown: number?, -- s entre deux changements (zen)
}

local Settings = {
	zen = {
		kind = "boolean",
		default = false,
		saved = true,
		order = 1,
		harborOnly = true,
		cooldown = 60,
	},
	reducedMotion = { kind = "boolean", default = false, saved = true, order = 2 },
	lowGraphics = { kind = "boolean", default = false, saved = true, order = 3 },
	music = { kind = "boolean", default = true, saved = true, order = 4 },
	sfx = { kind = "boolean", default = true, saved = true, order = 5 },
	autoCrew = { kind = "boolean", default = true, saved = true, order = 6 },
	refuseInvites = { kind = "boolean", default = false, saved = true, order = 7 },
	lang = {
		kind = "string",
		default = "auto",
		values = { auto = true, en = true, fr = true },
		saved = true,
		order = 8,
	},
	privateNoSnip = {
		kind = "boolean",
		default = false,
		saved = false, -- réglage de serveur (mémoire), pas du profil
		order = 9,
		ownerOnly = true,
	},
} :: { [string]: SettingDef }

return Settings
