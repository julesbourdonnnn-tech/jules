--!strict
-- Intentions du jeu complet (GDD v2.0 §12.7, docs/04 §27.5). Contrat v2.0 (architecte).
-- Même forme que Config/Intents (sortes d'arguments, débit, propriétaire, activité), plus
-- l'interrupteur Config/Features qui les ouvre. Les remotes sont DÉJÀ déclarés dans Shared/Remotes
-- (Net.setup les crée), mais AUCUN service ne les écoute tant que leur paquet n'est pas fait : le
-- client du jeu de base ne les envoie jamais (interrupteurs coupés).
-- Règle de passage (docs/04 §27.5) : le paquet qui branche le handler DÉPLACE la ligne de ce
-- catalogue vers Config/Intents dans le même lot (note d'intégration au contrat), avec la mise à jour
-- des specs Remotes_<paquet> qui comptent les intentions de leur propriétaire. Une intention n'est
-- jamais dans les deux catalogues (Contract_v2.spec).
-- Ordre de chaque handler : débit → types (cette description) → existence → état → règles →
-- mutation atomique → réplication ; refus = aucune mutation, au plus un Feedback neutre.

-- Même forme que Config/Intents.IntentSpec (recopiée : les modules de Config ne se requièrent pas
-- entre eux, certains specs les chargent par un chemin de fichier)
export type ArgSpec = {
	name: string,
	kind: string,
	min: number?,
	max: number?,
	set: { string }?,
	truncate: boolean?,
}

export type IntentSpecV2 = {
	owner: string,
	rate: { number },
	args: { ArgSpec },
	clientRate: { number }?,
	activity: boolean?,
	feature: string, -- interrupteur Config/Features qui ouvre l'intention
}

-- stylua: ignore start
local IntentsV2: { [string]: IntentSpecV2 } = {
	-- (BuyUpgrade et JellyAscend : passées dans Config/Intents avec leur handler, lot A2, note
	-- INT-V2-INTENTS ; PlaceDeco, GiveHeart et SetPhotoMode : passées dans Config/Intents avec leur
	-- handler, lot A4, journal A4-37. Catalogue vide : toute intention v2.0 est écoutée.)
	-- (Habillages de ranch : PAS d'intention nouvelle. Les 14 habillages sont les valeurs de
	-- cosmetics.theme de la v1.3, équipées par EquipCosmetic("theme", id) : docs/04 §27.2, décision C2.)
}
-- stylua: ignore end

return IntentsV2
