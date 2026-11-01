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
	-- Réglages du jeu (contrat de Raise a Squishy, GDD §10.3). Le mode Rush / Cozy n'est PAS un
	-- réglage : il a ses règles (recharge, fin du Rush en cours) et son remote SetMode (RushService).
	-- « Cacher mon nom » : bannières, classements, statue et panneau du ranch montrent
	-- « Squishy Fan #NNNN » (GDD §6.9)
	hideName = { kind = "boolean", default = false, saved = true, order = 7 },
	-- cadeaux du Grand Splorch des autres joueurs (GDD §4.15)
	receiveGifts = { kind = "boolean", default = true, saved = true, order = 8 },
	-- captures vidéo automatiques des grands moments (GDD §9.5)
	clips = { kind = "boolean", default = true, saved = true, order = 9 },
	-- emote de la croix ← (à la place de Bravo), débloquée (Config/Cosmetics, kind "emote")
	emoteLeft = {
		kind = "string",
		default = "bravo",
		values = { bravo = true, bellyFlop = true, crown = true },
		saved = true,
		order = 10,
	},
	-- « offerte par … » sur la bannière de SA Squish Party (case de la Boutique, décochée par défaut)
	partyShowName = { kind = "boolean", default = false, saved = true, order = 11 },
	-- serveur privé : « BOOP RUSH autorisé » (propriétaire seulement, réglage de serveur en mémoire)
	allowRush = { kind = "boolean", default = false, saved = false, order = 12, ownerOnly = true },
} :: { [string]: SettingDef }

return Settings
