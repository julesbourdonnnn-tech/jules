--!strict
-- Types partagés du socle. Aucun code exécutable : ce module ne renvoie qu'une table vide ; on
-- l'importe pour ses `export type`.
--   local Types = require(Shared.Types)
--   local function f(payload: Types.FeedbackPayload) … end
-- Registre partagé : ajouts ciblés autorisés (jamais de suppression ni de renommage). Les types du
-- jeu (créatures, ranch, économie…) seront ajoutés par l'architecte.

-- =============================================================================================
-- Généraux
-- =============================================================================================

export type InputKind = number -- 1 tactile, 2 clavier-souris, 3 manette (Client/Util/Platform)
export type Lang = "auto" | "en" | "fr"

-- Réglages sauvegardés du profil (Data/Schema, Config/Settings)
export type ProfileSettings = {
	reducedMotion: boolean,
	lowGraphics: boolean,
	music: boolean,
	sfx: boolean,
	vibration: boolean,
	lang: Lang,
}

-- =============================================================================================
-- Réseau : charges utiles serveur → client
-- =============================================================================================

-- DataPatch(patch, removed, entries?) : 3e argument, entrées d'une grande table du profil
-- (DataService.markDirtyEntry), ex. { items = { set = { u12 = rec }, del = { "u3" } } }.
-- set : nouvelles valeurs des sous-clés ; del : sous-clés supprimées. Jamais avec la clé entière
-- dans le même message (la clé entière l'emporte). Le client applique sur une copie de sa table.
export type DataEntryOps = { set: { [string]: any }, del: { string } }
export type DataPatchEntries = { [string]: DataEntryOps }

-- Feedback : refus et confirmations pour un joueur (Server/Util/Notify.feedback)
export type FeedbackTone = "info" | "success" | "warning" | "error" | "reward"
export type FeedbackPayload = {
	key: string, -- clé de localisation (« feedback.* »)
	vars: { [string]: any },
	tone: FeedbackTone,
}

-- Celebrate : moments personnels (Server/Util/Notify.celebrate). Les sortes sont définies par le
-- jeu (chaîne courte, ex. "upgrade", "purchase").
export type CelebrateKind = string
export type CelebratePayload = {
	kind: CelebrateKind,
	data: { [string]: any },
}

-- Banner : bannière d'écran (Server/Util/Notify.banner / personalBanner). Sortes définies par le jeu,
-- priorité dans Notify.BANNER_PRIORITY (1 = plus haute).
export type BannerKind = string
export type BannerPayload = {
	kind: BannerKind,
	args: { [string]: any }, -- name, userId, n, key…
	priority: number, -- 1 = plus haute
	personal: boolean?, -- envoyé à un seul joueur
}

return {}
