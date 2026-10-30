--!strict
-- Gamepasses et produits développeur.
-- Les IDs se créent dans le Creator Hub (voir skill roblox-publish) ; un id à 0 = article
-- désactivé : il n'apparaît pas en boutique et aucun achat n'est proposé.

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
}

local Monetization = {}

Monetization.Passes = {} :: { [string]: PassDef }

Monetization.Products = {} :: { [string]: ProductDef }

return Monetization
