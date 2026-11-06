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
--   since    : version du schéma qui l'ajoute (absent = 1). Un réglage `since = 2` n'existe que dans
--              un profil v2 : Data/Schema ne le met pas dans les valeurs par défaut d'une version
--              plus ancienne (defaultsV1 inchangé) et CommunityService refuse de l'écrire dans un
--              profil v1 (lot A4, docs/04 §27.2, §27.6).
-- Chaque réglage a son texte « settings.<clé> » en anglais et en français (Contract.spec).

export type SettingDef = {
	kind: "boolean" | "string",
	default: boolean | string,
	values: { [string]: boolean }?,
	saved: boolean,
	order: number,
	ownerOnly: boolean?,
	cooldown: number?,
	since: number?,
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
	-- emote de la croix ← (à la place de Bravo), débloquée (Config/Cosmetics, kind "emote") ; v2.0
	-- (lot A4, D21) : emotes du Record R, de l'Atelier, du Carnet et de la semaine (possession revue par
	-- Logic/Owned : jamais choisies tant que leur interrupteur est coupé)
	emoteLeft = {
		kind = "string",
		default = "bravo",
		values = {
			bravo = true,
			bellyFlop = true,
			crown = true,
			splorch = true,
			wave = true,
			confettiCrown = true,
			bigPlopDance = true,
			hammerTap = true,
			hugEmote = true,
		},
		saved = true,
		order = 10,
	},
	-- « offerte par … » sur la bannière de SA Squish Party (case de la Boutique, décochée par défaut)
	partyShowName = { kind = "boolean", default = false, saved = true, order = 11 },
	-- serveur privé : « BOOP RUSH autorisé » (propriétaire seulement, réglage de serveur en mémoire)
	allowRush = { kind = "boolean", default = false, saved = false, order = 12, ownerOnly = true },
	-- v2.0 : « Montrer mon halo » (gouttes de gelée de l'Ascension autour de la tête, GDD §4.27),
	-- affiché par le panneau Réglages derrière l'interrupteur RanchSkins (lot B3) ; profils v2 seulement
	haloOn = { kind = "boolean", default = true, saved = true, order = 13, since = 2 },
} :: { [string]: SettingDef }

return Settings
