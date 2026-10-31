--!strict
-- Gamepasses et produits développeur (GDD §8). Contrat : docs/04-architecture.md §9.
-- Les IDs se créent dans le Creator Hub (voir skill roblox-publish) ; un id à 0 = article
-- désactivé : il n'apparaît pas en boutique et aucun achat n'est proposé.
-- Les prix sont des replis d'affichage : le prix réel est lu à l'exécution (Client/Util/Prices).
-- Aucun objet aléatoire payant ; tout ce qui touche aux autres joueurs s'obtient en jouant.

export type PassDef = {
	id: number,
	price: number, -- prix indicatif en Robux (affichage avant que l'ID existe)
	nameKey: string, -- clé de localisation
	descKey: string,
	order: number,
	-- effets (lus par ProductService / EconomyService / AtlasService…)
	glowBonus: number?, -- additif dans M (VIP Star)
	glowMult: number?, -- multiplicateur (Double Glow)
	extraPerches: number?,
	stashSize: number?,
	offlineRate: number?,
	offlineCap: number?,
	extraRerolls: number?,
	styles: { string }?, -- Cosmetics.Styles accordés
	theme: string?, -- Cosmetics.Themes accordé
}

export type ProductDef = {
	id: number,
	price: number,
	nameKey: string,
	descKey: string,
	order: number,
	-- effets (ProductService)
	idleSeconds: number?, -- Glow = idleSeconds × revenu passif actuel…
	minGlow: number?, -- … avec ce minimum
	stardust: number?,
	serverBoostSeconds: number?, -- Glow Party
	boostSeconds: number?, -- boost personnel ×2
	species: { number }?, -- Nebbies accordés (★1, forme 0)
	style: string?,
	oncePerAccount: boolean?,
}

local Monetization = {}

Monetization.Passes = {
	VIPStar = {
		id = 0,
		price = 199,
		nameKey = "shop.pass.VIPStar.name",
		descKey = "shop.pass.VIPStar.desc",
		order = 1,
		glowBonus = 0.25,
		extraRerolls = 1,
		styles = { "royal_star" },
		theme = "royal_gold",
	},
	DoubleGlow = {
		id = 0,
		price = 299,
		nameKey = "shop.pass.DoubleGlow.name",
		descKey = "shop.pass.DoubleGlow.desc",
		order = 2,
		glowMult = 2,
	},
	NightShift = {
		id = 0,
		price = 99,
		nameKey = "shop.pass.NightShift.name",
		descKey = "shop.pass.NightShift.desc",
		order = 3,
		offlineRate = 0.75,
		offlineCap = 12 * 3600,
	},
	ExtraPerches = {
		id = 0,
		price = 149,
		nameKey = "shop.pass.ExtraPerches.name",
		descKey = "shop.pass.ExtraPerches.desc",
		order = 4,
		extraPerches = 6,
	},
	StashPlus = {
		id = 0,
		price = 99,
		nameKey = "shop.pass.StashPlus.name",
		descKey = "shop.pass.StashPlus.desc",
		order = 5,
		stashSize = 600,
	},
	CongaStyles = {
		id = 0,
		price = 79,
		nameKey = "shop.pass.CongaStyles.name",
		descKey = "shop.pass.CongaStyles.desc",
		order = 6,
		styles = { "rainbow_ripple", "ember", "bubbles", "starlight", "frost", "neon_wave" },
	},
} :: { [string]: PassDef }

Monetization.Products = {
	GlowPouch = {
		id = 0,
		price = 25,
		nameKey = "shop.product.GlowPouch.name",
		descKey = "shop.product.GlowPouch.desc",
		order = 1,
		idleSeconds = 600,
		minGlow = 1000,
	},
	GlowSack = {
		id = 0,
		price = 89,
		nameKey = "shop.product.GlowSack.name",
		descKey = "shop.product.GlowSack.desc",
		order = 2,
		idleSeconds = 2400,
		minGlow = 4000,
	},
	GlowCrate = {
		id = 0,
		price = 199,
		nameKey = "shop.product.GlowCrate.name",
		descKey = "shop.product.GlowCrate.desc",
		order = 3,
		idleSeconds = 7200,
		minGlow = 12000,
	},
	GlowParty = {
		id = 0,
		price = 99,
		nameKey = "shop.product.GlowParty.name",
		descKey = "shop.product.GlowParty.desc",
		order = 4,
		serverBoostSeconds = 600,
	},
	StardustJar = {
		id = 0,
		price = 49,
		nameKey = "shop.product.StardustJar.name",
		descKey = "shop.product.StardustJar.desc",
		order = 5,
		stardust = 400,
	},
	StarterKit = {
		id = 0,
		price = 49,
		nameKey = "shop.product.StarterKit.name",
		descKey = "shop.product.StarterKit.desc",
		order = 6,
		species = { 16, 18, 20 }, -- Cometcub, Frostfinch, Daybreak Puff (Nebbies.Named.StarterKit)
		style = "comet_tail",
		boostSeconds = 1200,
		oncePerAccount = true,
	},
} :: { [string]: ProductDef }

return Monetization
