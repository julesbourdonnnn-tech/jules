--!strict
-- Gamepasses et produits développeur. Modèle du socle : listes VIDES, même structure que Comet Conga.
-- Les articles du jeu (passes « Pour toujours », Squish Party, paquets de pièces…) seront ajoutés par
-- l'architecte et le paquet boutique.
-- Les IDs se créent dans le Creator Hub ; un id à 0 = article désactivé : il n'apparaît pas en
-- boutique et aucun achat n'est proposé (`lune run scripts/prepublish` liste ceux qui manquent).
-- Les prix sont des replis d'affichage : le prix réel est lu à l'exécution (Client/Util/Prices).
-- Règles : aucun objet aléatoire payant, aucune chance payante, aucun avantage payant sur les autres
-- joueurs ; chaque article a un nom et une description EN/FR (clés nameKey, descKey).
-- Les effets d'un article (multiplicateur, emplacements…) sont des champs optionnels à ajouter aux
-- types ci-dessous ; MonetizationService ne lit que id, et les handlers des produits.

export type PassDef = {
	id: number,
	price: number, -- prix indicatif en Robux (affichage avant que l'ID existe)
	nameKey: string, -- clé de localisation
	descKey: string,
	order: number,
}

export type ProductDef = {
	id: number,
	price: number,
	nameKey: string,
	descKey: string,
	order: number,
	oncePerAccount: boolean?, -- un seul achat par compte (vérifié par le handler du produit)
}

local Monetization = {}

Monetization.Passes = {} :: { [string]: PassDef }

Monetization.Products = {} :: { [string]: ProductDef }

return Monetization
