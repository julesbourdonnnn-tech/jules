--!strict
-- Gamepasses et produits développeur (GDD §8). Contrat (architecte) : liste figée, IDs à 0.
-- Les IDs se créent dans le Creator Hub ; un id à 0 = article désactivé : il n'apparaît pas en
-- boutique et aucun achat n'est proposé ; si tous valent 0, l'onglet Boutique n'existe pas
-- (`lune run scripts/prepublish` liste ceux qui manquent).
-- Les prix sont des replis d'affichage : le prix réel est lu à l'exécution (Client/Util/Prices).
-- Règles (GDD §8.1) : aucun objet aléatoire payant, aucune chance payante (même par les pièces),
-- aucun avantage payant sur les autres joueurs ; résultat connu avant l'achat ; chaque article a un
-- nom et une description EN/FR (nameKey, descKey).
-- MonetizationService (socle) ne lit que id et les handlers des produits ; les effets ci-dessous
-- sont appliqués par ProductService (paquet ranch) et les services qui lisent ownsPass.
-- Contrat v1.2 (GDD v1.3, §8.3) : paquets de pièces RETIRÉS du lancement (CoinsSmall, CoinsBig : id 0
-- et hidden = true, comme SeasonPass ; aucun handler) ; plus aucun article caché par PolicyService
-- (ArePaidRandomItemsRestricted ne sert qu'à l'analytique PolicyPaidRandomRestricted : aucun article du
-- jeu n'est aléatoire) ; plus de 2e confirmation du Grand Splorch.

export type PassDef = {
	id: number,
	price: number, -- prix indicatif en Robux (affichage avant que le prix réel arrive)
	nameKey: string, -- clé de localisation
	descKey: string,
	order: number,
	forever: boolean, -- étiquette « Pour toujours » / « Forever »
	hidden: boolean?, -- réservé (janvier) : jamais affiché au lancement
}

export type ProductDef = {
	id: number,
	price: number,
	nameKey: string,
	descKey: string,
	order: number,
	oncePerAccount: boolean?, -- un seul achat par compte (vérifié par le handler du produit)
	tab: "party" | "outfits", -- onglet de la Boutique (Passes / Fête / Tenues)
	dailyLimit: number?, -- achats par joueur et par jour (Squish Party : 3)
	outfit: string?, -- tenue accordée (Config/Cosmetics, kind "outfit")
	hidden: boolean?, -- jamais affiché ni vendu au lancement (paquets de pièces, réservés : GDD §8.3, §17.2)
}

local Monetization = {}

Monetization.Passes = {
	AutoPot = {
		id = 0,
		price = 149,
		nameKey = "shop.pass.AutoPot",
		descKey = "shop.pass.AutoPot.desc",
		order = 1,
		forever = true,
	},
	DoubleCoins = {
		id = 0,
		price = 249,
		nameKey = "shop.pass.DoubleCoins",
		descKey = "shop.pass.DoubleCoins.desc",
		order = 2,
		forever = true,
	},
	BigRanch = {
		id = 0,
		price = 199,
		nameKey = "shop.pass.BigRanch",
		descKey = "shop.pass.BigRanch.desc",
		order = 3,
		forever = true,
	},
	SaddlesTrails = {
		id = 0,
		price = 99,
		nameKey = "shop.pass.SaddlesTrails",
		descKey = "shop.pass.SaddlesTrails.desc",
		order = 4,
		forever = true,
	},
	-- Réservé (janvier) : piste premium décorative de la saison, Features.Season = false
	SeasonPass = {
		id = 0,
		price = 399,
		nameKey = "shop.pass.SeasonPass",
		descKey = "shop.pass.SeasonPass.desc",
		order = 99,
		forever = false,
		hidden = true,
	},
} :: { [string]: PassDef }

Monetization.Products = {
	SquishParty = {
		id = 0,
		price = 99,
		nameKey = "shop.product.SquishParty",
		descKey = "shop.product.SquishParty.desc",
		order = 1,
		tab = "party",
		dailyLimit = 3,
	},
	CoinsSmall = {
		id = 0,
		price = 49,
		nameKey = "shop.product.CoinsSmall",
		descKey = "shop.product.CoinsSmall.desc",
		order = 2,
		tab = "party",
		hidden = true, -- retiré du lancement (GDD v1.3, §8.3)
	},
	CoinsBig = {
		id = 0,
		price = 149,
		nameKey = "shop.product.CoinsBig",
		descKey = "shop.product.CoinsBig.desc",
		order = 3,
		tab = "party",
		hidden = true, -- retiré du lancement (GDD v1.3, §8.3)
	},
	OutfitSweater = {
		id = 0,
		price = 49,
		nameKey = "shop.product.OutfitSweater",
		descKey = "shop.product.OutfitSweater.desc",
		order = 4,
		tab = "outfits",
		outfit = "sweater",
	},
	OutfitCrown = {
		id = 0,
		price = 79,
		nameKey = "shop.product.OutfitCrown",
		descKey = "shop.product.OutfitCrown.desc",
		order = 5,
		tab = "outfits",
		outfit = "jellyCrown",
	},
	OutfitWinter = {
		id = 0,
		price = 49,
		nameKey = "shop.product.OutfitWinter",
		descKey = "shop.product.OutfitWinter.desc",
		order = 6,
		tab = "outfits",
		outfit = "winterScarf",
	},
} :: { [string]: ProductDef }

return Monetization
