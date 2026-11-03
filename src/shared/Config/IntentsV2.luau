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
	-- Écran Améliorations (EconomyService.buyUpgrade, même chemin que BuyTile) : id ∈ Config/Upgrades
	-- (Families, WorkshopRows, lignes « bits » de Fun) ; mode 1, 10 ou 0 (= Max) ; expectedLevel =
	-- niveau que l'écran montre (sinon refus « périmé » : UpgradeResult sans retour visible si
	-- l'instantané montre déjà ce niveau, compteur UpgradeStale)
	BuyUpgrade = { owner = "EconomyService", rate = { 10, 1 }, activity = true, feature = "UpgradesScreen", args = {
		{ name = "id", kind = "str", max = 24 },
		{ name = "mode", kind = "int", min = 0, max = 10 },
		{ name = "expectedLevel", kind = "int", min = 0, max = 64 },
	} },
	-- Jelly Ascend (SplorchService) : maintien de 3 s et carte « Prêt à monter ? » côté client ;
	-- confirm = true exigé ; Prestige.ascendReady vérifié une seule fois, à l'entrée dans la file
	JellyAscend = { owner = "SplorchService", rate = { 1, 5 }, activity = true, feature = "JellyAscend", args = {
		{ name = "confirm", kind = "bool" },
	} },
	-- (Habillages de ranch : PAS d'intention nouvelle. Les 14 habillages sont les valeurs de
	-- cosmetics.theme de la v1.3, équipées par EquipCosmetic("theme", id) : docs/04 §27.2, décision C2.)
	-- Déco perso : objet possédé (1-64, 0 = retirer) dans un emplacement 1-12 de la bonne taille
	PlaceDeco = { owner = "CommunityService", rate = { 4, 1 }, feature = "DecoPerso", args = {
		{ name = "item", kind = "int", min = 0, max = 64 },
		{ name = "slot", kind = "int", min = 1, max = 12 },
	} },
	-- Cœur donné au ranch d'un autre joueur présent (pas soi, pas bloqué, 1 par ranch et par jour)
	GiveHeart = { owner = "CommunityService", rate = { 2, 1 }, activity = true, feature = "Hearts", args = {
		{ name = "ownerId", kind = "userId" },
	} },
	-- Mode photo : analytique et personnage figé MAIS VISIBLE des autres ; aucun avantage
	SetPhotoMode = { owner = "CommunityService", rate = { 1, 1 }, feature = "PhotoMode", args = {
		{ name = "on", kind = "bool" },
	} },
}
-- stylua: ignore end

return IntentsV2
