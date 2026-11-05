--!strict
-- Catalogue des 9 familles d'amélioration, de l'Atelier de Big Plop et de « Pour le plaisir »
-- (GDD v2.0 §4.6, §4.26, §10.7). Contrat v2.0 (architecte, docs/04 §27.6).
--  * Identifiants DÉFINITIFS (clés de profil, de texte, d'analytique) : ajout à la fin seulement,
--    jamais de renommage ni de retrait (le profil range l'Atelier par position : profile.atelier[i]
--    = niveau de WorkshopRows[i]).
--  * Ce module dit QUOI existe, dans quel ordre, où, ouvert quand ; les PRIX vivent dans
--    Config/Balance (Balance.Tiles pour les 4 dalles de la v1.3, Balance.UpgradePrices pour les
--    familles nouvelles : leviers de la porte EconomyPacing, réglés par le paquet A1 seulement) ; les
--    coûts en Confettis de l'Atelier sont des listes explicites ici (aucune formule).
--  * Logic/UpgradeMath (paquet A1) construit les tables de prix par MULTIPLICATIONS SUCCESSIVES au
--    chargement, dans un ordre fixe, de la même façon sur le client et le serveur (aucun ^ : règle 5
--    du GDD §10.8, Static_NoPow.spec).
--  * Trois lois (GDD §4.6) : rien n'achète une chance ; les familles de la boucle ne donnent pas de
--    croissance (sauf le Tapis et le Tapis Étoilé) ; toute famille passe la porte EconomyPacing.
--  * Aucune famille ne se vend en Robux (règle 16 du GDD §10.8, Static_NoRobuxInUpgrades.spec).
-- Contract_upgrades.spec vérifie ce module (coûts croissants, textes EN/FR, liste fermée des effets).

export type Currency = "coins" | "confetti"
export type UpgradeTab = "suggested" | "ranch" | "helpers" | "workshop"

-- Condition d'ouverture : lue par le SERVEUR seulement (UpgradeMath.cap), figée par l'écran à
-- l'ouverture (règle 19 du GDD §10.8). recordR : Record R minimal (bestR) ; ascend : A minimal ;
-- loopCapByR : plafond de niveau selon r DE LA BOUCLE (Tapis Étoilé : plafond d'économie, jamais un
-- cadenas, état « Boucle r » à l'écran) ; recordRByLevel : niveau n ouvert au Record R donné
-- (Monuments : un par Record R d'ouverture)
export type OpenRule = {
	recordR: number?,
	ascend: number?,
	loopCapByR: { [number]: number }?,
	recordRByLevel: { number }?,
}

-- Palier nommé : niveaux [from ; prochain from[ ; key = clé de texte (Strings)
export type TierDef = { from: number, key: string }

export type FamilyDef = {
	id: string, -- identifiant définitif
	tab: UpgradeTab,
	row: string, -- ligne de l'écran (le Tapis Étoilé partage la ligne « snack » : « 12/20 »)
	currency: Currency,
	-- source du prix : "tile:<clé>" (Balance.Tiles, dalles de la v1.3) ou "price:<clé>"
	-- (Balance.UpgradePrices) ; une seule source par famille
	price: string,
	levels: number, -- niveaux achetables de CETTE famille
	levelOffset: number, -- niveau affiché du premier niveau de la famille − 1 (Tapis Étoilé : 12)
	scaleR: boolean, -- prix × RScale^r (familles de la boucle)
	scaleA: boolean, -- prix × F(A) (Balance.Ascend.PriceByA)
	kept: boolean, -- gardé au Grand Splorch (et à la Jelly Ascend)
	profileKey: string, -- champ du profil : "tiles.snack", "tiles.star" … ("tiles.cozyBed" est un booléen)
	open: OpenRule,
	tiers: { TierDef },
	nameKey: string, -- nom (case (b) : colonne Texte 540 px, 36 px)
	effectKey: string, -- libellé court de l'effet (sans flèche : la flèche est une icône dessinée)
	reasonKey: string, -- « pourquoi » d'une carte Conseillé (une ligne)
	icon: string, -- dessin en formes simples (UI/UpgradeCard)
	feature: string, -- interrupteur Config/Features qui ouvre la famille ("" : toujours là, v1.3)
	hold: boolean, -- achat par maintien de 0,6 s (vrai pour tout achat de l'écran, critique m16)
}

-- Ligne en lecture seule (onglets Plopettes et Atelier) : sélectionnable, ✕ = Bump, jamais achetée
export type ReadOnlyDef = { id: string, tab: UpgradeTab, nameKey: string, icon: string, feature: string }

-- Ligne de l'Atelier (Confettis gagnés en jouant seulement) : un niveau par case de profile.atelier
export type WorkshopRowDef = {
	id: string,
	costs: { number }, -- coût de CHAQUE niveau (liste explicite, strictement croissante)
	effect: string, -- effet de la liste fermée WorkshopEffects
	open: OpenRule,
	nameKey: string,
	effectKey: string,
	icon: string,
	feature: string,
}

-- Ligne de « Pour le plaisir » : cosmétiques seulement (aucun effet de jeu)
export type FunLineDef = {
	id: string,
	costs: { number }, -- un coût par objet de la ligne
	-- où l'achat est noté : "bits" (profile.atelierCosmetics, bits firstBit … firstBit + #costs − 1)
	-- ou "atelier" (case WorkshopRows de la ligne decoShop : niveau = objets achetés)
	store: "bits" | "atelier",
	firstBit: number?,
	grants: { string }, -- identifiants des cosmétiques donnés, dans l'ordre (Config/Cosmetics, Annexe B)
	nameKey: string,
	icon: string,
}

local Upgrades = {}

-- Onglets de l'écran, dans l'ordre (Conseillé ouvert par défaut, GDD §10.7.3)
Upgrades.Tabs = { "suggested", "ranch", "helpers", "workshop" } :: { UpgradeTab }

-- Modes d'achat (bouton de mode : ×1, ×10, Max ; 0 = Max dans l'intention BuyUpgrade)
Upgrades.Modes = { 1, 10, 0 } :: { number }

-- stylua: ignore start
-- Familles achetables en pièces, dans l'ORDRE FIXE des lignes (règle 1 du GDD §10.8 : aucun tri)
Upgrades.Families = {
	{ id = "snack", tab = "ranch", row = "snack", currency = "coins", price = "tile:snack", levels = 12, levelOffset = 0,
		scaleR = true, scaleA = true, kept = false, profileKey = "tiles.snack", open = {},
		tiers = { { from = 1, key = "upgrades.tier.snack.1" }, { from = 4, key = "upgrades.tier.snack.2" }, { from = 7, key = "upgrades.tier.snack.3" }, { from = 10, key = "upgrades.tier.snack.4" } },
		nameKey = "upgrades.family.snack", effectKey = "upgrades.effect.growth", reasonKey = "upgrades.reason.growth", icon = "mat", feature = "", hold = true },
	{ id = "star", tab = "ranch", row = "snack", currency = "coins", price = "price:star", levels = 8, levelOffset = 12,
		scaleR = true, scaleA = true, kept = false, profileKey = "tiles.star",
		open = { loopCapByR = { [6] = 1, [7] = 2, [8] = 3, [9] = 4, [10] = 8 } },
		tiers = { { from = 1, key = "upgrades.tier.snack.5" }, { from = 5, key = "upgrades.tier.snack.6" } },
		nameKey = "upgrades.family.star", effectKey = "upgrades.effect.growth", reasonKey = "upgrades.reason.growth", icon = "starMat", feature = "StarMat", hold = true },
	{ id = "decor", tab = "ranch", row = "decor", currency = "coins", price = "tile:decor", levels = 18, levelOffset = 0,
		scaleR = true, scaleA = true, kept = false, profileKey = "tiles.decor", open = {},
		tiers = { { from = 1, key = "upgrades.tier.decor.1" }, { from = 7, key = "upgrades.tier.decor.2" }, { from = 13, key = "upgrades.tier.decor.3" } },
		nameKey = "upgrades.family.decor", effectKey = "upgrades.effect.incomeTotal", reasonKey = "upgrades.reason.income", icon = "decor", feature = "", hold = true },
	{ id = "pens", tab = "ranch", row = "pens", currency = "coins", price = "tile:pens", levels = 14, levelOffset = 0,
		scaleR = false, scaleA = false, kept = true, profileKey = "tiles.pens", open = {},
		tiers = { { from = 0, key = "upgrades.tier.pens.1" }, { from = 6, key = "upgrades.tier.pens.2" }, { from = 14, key = "upgrades.tier.pens.3" } },
		nameKey = "upgrades.family.pens", effectKey = "upgrades.effect.spots", reasonKey = "upgrades.reason.room", icon = "pen", feature = "", hold = true },
	{ id = "cozyBed", tab = "ranch", row = "cozyBed", currency = "coins", price = "tile:cozyBed", levels = 1, levelOffset = 0,
		scaleR = false, scaleA = false, kept = true, profileKey = "tiles.cozyBed", open = { recordR = 3 },
		tiers = {}, nameKey = "upgrades.family.cozyBed", effectKey = "upgrades.effect.night", reasonKey = "upgrades.reason.sleep", icon = "bed", feature = "", hold = true },
	{ id = "gloves", tab = "ranch", row = "gloves", currency = "coins", price = "price:gloves", levels = 40, levelOffset = 0,
		scaleR = true, scaleA = true, kept = false, profileKey = "tiles.gloves", open = { recordR = 1 },
		tiers = {
			{ from = 1, key = "upgrades.tier.gloves.1" }, { from = 5, key = "upgrades.tier.gloves.2" }, { from = 10, key = "upgrades.tier.gloves.3" },
			{ from = 15, key = "upgrades.tier.gloves.4" }, { from = 20, key = "upgrades.tier.gloves.5" }, { from = 25, key = "upgrades.tier.gloves.6" },
			{ from = 30, key = "upgrades.tier.gloves.7" }, { from = 35, key = "upgrades.tier.gloves.8" }, { from = 40, key = "upgrades.tier.gloves.9" },
		},
		nameKey = "upgrades.family.gloves", effectKey = "upgrades.effect.presses", reasonKey = "upgrades.reason.press", icon = "glove", feature = "Gloves", hold = true },
	{ id = "monument", tab = "ranch", row = "monument", currency = "coins", price = "price:monument", levels = 10, levelOffset = 0,
		scaleR = false, scaleA = false, kept = true, profileKey = "tiles.monuments",
		open = { recordR = 6, recordRByLevel = { 6, 8, 10, 12, 14, 16, 18, 20, 22, 24 } },
		tiers = {}, nameKey = "upgrades.family.monument", effectKey = "upgrades.effect.monument", reasonKey = "upgrades.reason.beauty", icon = "monument", feature = "Monuments", hold = true },
	{ id = "school", tab = "helpers", row = "school", currency = "coins", price = "price:school", levels = 20, levelOffset = 0,
		scaleR = true, scaleA = true, kept = false, profileKey = "tiles.school", open = { recordR = 2 },
		tiers = {
			{ from = 1, key = "upgrades.tier.school.1" }, { from = 5, key = "upgrades.tier.school.2" }, { from = 10, key = "upgrades.tier.school.3" },
			{ from = 15, key = "upgrades.tier.school.4" }, { from = 20, key = "upgrades.tier.school.5" },
		},
		nameKey = "upgrades.family.school", effectKey = "upgrades.effect.helper", reasonKey = "upgrades.reason.helpers", icon = "school", feature = "Helpers", hold = true },
} :: { FamilyDef }

-- Lignes en lecture seule (aucun achat ; données par le Record R)
Upgrades.ReadOnly = {
	{ id = "helper.pip", tab = "helpers", nameKey = "helper.name.pip", icon = "helper", feature = "Helpers" },
	{ id = "helper.pop", tab = "helpers", nameKey = "helper.name.pop", icon = "helper", feature = "Helpers" },
	{ id = "helper.pim", tab = "helpers", nameKey = "helper.name.pim", icon = "helper", feature = "Helpers" },
	{ id = "helper.pom", tab = "helpers", nameKey = "helper.name.pom", icon = "helper", feature = "Helpers" },
	{ id = "helper.puff", tab = "helpers", nameKey = "helper.name.puff", icon = "helper", feature = "Helpers" },
	{ id = "helper.plume", tab = "helpers", nameKey = "helper.name.plume", icon = "helper", feature = "Helpers" },
	-- une seule ligne « Monte avec ton record » (Cuve, palier, prochain déblocage dans le bandeau ;
	-- critique B2, m12)
	{ id = "risesWithRecord", tab = "workshop", nameKey = "workshop.risesWithRecord", icon = "vat", feature = "Workshop" },
} :: { ReadOnlyDef }

-- Effets permis à l'Atelier : LISTE FERMÉE (Contract_upgrades.spec). Rien sur la croissance (sauf
-- startMat : du Tapis acheté d'avance), aucune chance, ni Cuve, ni créatures, ni mutations, ni
-- raretés, ni combo maximal, ni Pot automatique, ni places au-delà de 18.
Upgrades.WorkshopEffects = {
	giftLevels = true, -- niveaux du Tapis payés par le cadeau du Splorch
	startMat = true, -- Tapis de départ
	magnetRadius = true, -- rayon d'encaissement du Pot
	superStreak = true, -- série PERFECT maximale
	keptDecor = true, -- décorations gardées au Grand Splorch
	nightBagHours = true, -- limite hors ligne
	nightPotShare = true, -- part du revenu hors ligne dans le Pot
	extraHelper = true, -- Plume (6e Plopette)
	springboard = true, -- Tremplin après une Ascension
	cosmetic = true, -- « Pour le plaisir » (decoShop)
} :: { [string]: boolean }

-- Lignes de l'Atelier, dans l'ordre FIXE (profile.atelier[i] = niveau de WorkshopRows[i])
Upgrades.WorkshopRows = {
	{ id = "gift", costs = { 3, 25 }, effect = "giftLevels", open = { recordR = 1 }, nameKey = "workshop.gift", effectKey = "upgrades.effect.gift", icon = "gift", feature = "Workshop" },
	{ id = "startMat", costs = { 12, 30, 60 }, effect = "startMat", open = { recordR = 1 }, nameKey = "workshop.startMat", effectKey = "upgrades.effect.startMat", icon = "mat", feature = "Workshop" },
	{ id = "magnet", costs = { 4, 8, 14 }, effect = "magnetRadius", open = { recordR = 1 }, nameKey = "workshop.magnet", effectKey = "upgrades.effect.magnet", icon = "magnet", feature = "Workshop" },
	{ id = "superStreak", costs = { 10, 20 }, effect = "superStreak", open = { recordR = 1 }, nameKey = "workshop.superStreak", effectKey = "upgrades.effect.streak", icon = "streak", feature = "Workshop" },
	{ id = "keptDecor", costs = { 15, 60 }, effect = "keptDecor", open = { recordR = 1 }, nameKey = "workshop.keptDecor", effectKey = "upgrades.effect.kept", icon = "decor", feature = "Workshop" },
	{ id = "nightBag", costs = { 6, 12, 20 }, effect = "nightBagHours", open = { recordR = 1 }, nameKey = "workshop.nightBag", effectKey = "upgrades.effect.night", icon = "bag", feature = "Workshop" },
	{ id = "nightPot", costs = { 15, 30 }, effect = "nightPotShare", open = { recordR = 1 }, nameKey = "workshop.nightPot", effectKey = "upgrades.effect.nightPot", icon = "pot", feature = "Workshop" },
	{ id = "plume", costs = { 40 }, effect = "extraHelper", open = { recordR = 12 }, nameKey = "workshop.plume", effectKey = "upgrades.effect.plume", icon = "helper", feature = "Helpers" },
	{ id = "springboard", costs = { 40, 80, 150 }, effect = "springboard", open = { ascend = 1 }, nameKey = "workshop.springboard", effectKey = "upgrades.effect.springboard", icon = "springboard", feature = "JellyAscend" },
	-- ligne « Déco perso de l'Atelier » de « Pour le plaisir » : sa case vit dans profile.atelier
	-- (niveau = objets achetés, dans l'ordre fixe de Cosmetics/Annexe B.1, objets 17 à 40)
	{ id = "decoShop", costs = { 30, 30, 30, 30, 30, 30, 60, 60, 60, 60, 60, 60, 100, 100, 100, 100, 100, 100, 200, 200, 200, 200, 200, 200 },
		effect = "cosmetic", open = { recordR = 1 }, nameKey = "fun.decoShop", effectKey = "upgrades.effect.decoShop", icon = "deco", feature = "DecoPerso" },
} :: { WorkshopRowDef }

-- « Pour le plaisir » (bas de l'onglet Atelier, 7 lignes ; 2 770 Confettis en tout, GDD §4.26)
Upgrades.Fun = {
	{ id = "palettes", costs = { 20, 20, 20, 20, 20, 20 }, store = "bits", firstBit = 1,
		grants = { "palette.candy", "palette.mint", "palette.lavender", "palette.rainbow", "palette.softNight", "palette.icing" }, nameKey = "fun.palettes", icon = "palette" },
	{ id = "saddle", costs = { 40 }, store = "bits", firstBit = 7, grants = { "saddle.partyPopper" }, nameKey = "fun.saddle", icon = "saddle" },
	{ id = "trail", costs = { 50 }, store = "bits", firstBit = 8, grants = { "trail.streamers" }, nameKey = "fun.trail", icon = "trail" },
	{ id = "emote", costs = { 60 }, store = "bits", firstBit = 9, grants = { "emote.bigPlopDance" }, nameKey = "fun.emote", icon = "emote" },
	{ id = "pennants", costs = { 60 }, store = "bits", firstBit = 10, grants = { "decor.goldPennants" }, nameKey = "fun.pennants", icon = "pennant" },
	{ id = "title", costs = { 100 }, store = "bits", firstBit = 11, grants = { "title.confettiStar" }, nameKey = "fun.title.confettiStar", icon = "title" },
	{ id = "decoShop", costs = {}, store = "atelier", grants = {}, nameKey = "fun.decoShop", icon = "deco" },
} :: { FunLineDef }
-- stylua: ignore end

-- Nombre de bits de profile.atelierCosmetics (11 cosmétiques ; Logic/Bitset, mots de 32 bits)
Upgrades.CosmeticBits = 11

-- Familles par identifiant (lecture)
Upgrades.ById = {} :: { [string]: FamilyDef }
for _, def in Upgrades.Families do
	Upgrades.ById[def.id] = def
end

-- Lignes de l'Atelier par identifiant → position dans profile.atelier
Upgrades.WorkshopIndex = {} :: { [string]: number }
for i, row in Upgrades.WorkshopRows do
	Upgrades.WorkshopIndex[row.id] = i
end

return Upgrades
