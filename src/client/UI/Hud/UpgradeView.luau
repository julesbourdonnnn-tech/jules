--!strict
-- Hud/UpgradeView (lot B2, docs/04 §27.7, §27.8 ; GDD v2.0 §10.7.4 à §10.7.8, §4.26, §4.28) : vue PURE
-- d'une ligne ou d'une carte de l'écran Améliorations, calculée depuis l'instantané versionné
-- (UI/UpgradeSnapshot) seulement. Aucune Instance, aucun service, aucun état : même entrée, même vue.
--
--   local v = UpgradeView.view(lineId, snap, mode, ctx, pending)
--     lineId  : identifiant de ligne (UpgradeView.lines(tab) ; « snack » = ligne Tapis, « star » aussi)
--     mode    : 1 | 10 | 0 (Max) ; toute autre valeur compte comme ×1 (jamais envoyée)
--     ctx     : langue, contexte des effets (D30), Atelier conseillé, mode des Plopettes (HelperMode)
--     pending : nil | "busy" | "retry" (achat en cours, sans réponse en 3 s : lot B2, étape 3)
--   v.state ∈ ready, need, max, locked, loopCap, busy, retry ; v.hidden (ligne coupée par un
--   interrupteur du serveur, D8) ; v.sendId / v.sendMode / v.expectedLevel : l'intention BuyUpgrade
--   exacte (identifiant canonique, mode valide, niveau montré de cet identifiant) ou sendId = nil.
--
-- Règles (plan du lot B2, décisions D1, D7, D8, D22, D29, D30, D31 ; notes A1, A2, A3) :
--  * l'ouverture vient SEULEMENT des plafonds (snap.caps) ; les mots du cadenas viennent des règles
--    d'ouverture de Config/Upgrades (affichage) : « Record {r} », « Ascension {a} », « Boucle {r} »
--    (Tapis Étoilé : plus petit r' dont Prestige.starCap dépasse le niveau) ; une ligne fermée alors
--    que sa règle est remplie est coupée par un interrupteur : hidden (jamais un « Record n » trompeur) ;
--  * ligne Tapis : Tapis à Goûter puis Tapis Étoilé sur UNE ligne, niveau montré 12 + Étoilé sur 20
--    (partie au-delà du plafond de la boucle grisée : capLevel) ; l'identifiant envoyé devient « star »
--    au Tapis 12, avec le niveau de l'Étoilé pour niveau attendu ;
--  * aperçu ×10 / Max = UpgradeMath.plan (même calcul que le débit du serveur : somme exacte
--    UpgradeMath.bulk, plafond, Balance.Upgrades.BulkMax), achat partiel annoncé ; « Il manque » quand
--    rien n'est payable : le premier niveau (le mode n'achète rien de moins) ;
--  * avant → après par UpgradeMath.effect avec le contexte du joueur (Lit douillet, famille Spiky, Sac
--    de nuit, A_bonus, Grand Ranch, Record R, Monuments) : une unité et un formateur par clé d'effet ;
--  * chaque nombre est une chaîne de UI/Format ou de Logic/BigNumber (pièces : BigNumber.abbreviate ;
--    Confettis : Format.confetti) ; la vue ne rend que des clés de Strings et leurs variables.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Upgrades = require(Shared.Config.Upgrades)
local Visuals = require(Shared.Config.Visuals)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local UpgradeAdvisor = require(Shared.Logic.UpgradeAdvisor)
local Prestige = require(Shared.Logic.Prestige)
local TierRules = require(Shared.Logic.TierRules)
local Formulas = require(Shared.Logic.Formulas)
local BigNumber = require(Shared.Logic.BigNumber)

local Format = require(script.Parent.Parent.Format)

export type State = "ready" | "need" | "max" | "locked" | "loopCap" | "busy" | "retry"
export type Pending = "busy" | "retry"
export type Kind = "family" | "workshop" | "fun" | "helper" | "rises"
export type Badge = "loop" | "kept" | "advised"
export type Vars = { [string]: string }
export type Text = { key: string, vars: Vars? }

-- Avant → après : libellé court, valeur actuelle, valeur après l'achat (flèche DESSINÉE entre les deux)
export type Effect = { label: Text?, before: Text?, after: Text? }

-- Aperçu de l'achat du mode (niveaux MONTRÉS : Tapis Étoilé 12 + niveau)
export type Preview = { count: number, from: number, to: number, total: number, partial: boolean }

-- Contexte du joueur (tout est facultatif)
export type Ctx = {
	lang: string?, -- "fr" | "en"
	aBonus: number?, -- Formulas.A du revenu (effet réel d'une décoration)
	bigRanch: boolean?, -- pass Grand Ranch
	spikyFamily: boolean?, -- famille Spiky complète
	helperMode: string?, -- attribut HelperMode du ranch : "active" | "nap" | "paused"
	advised: { [string]: boolean }?, -- lignes de l'Atelier conseillées (figées à l'ouverture de l'onglet)
	regainBonusA: number?, -- champs du profil pour Prestige.firstRecordLoop (Souvenir, D31)
	memoryR: number?,
}

export type View = {
	id: string, -- identifiant de la ligne (FocusId)
	kind: Kind,
	state: State,
	hidden: boolean, -- coupée par un interrupteur du serveur (D8)
	readOnly: boolean, -- rien à acheter (Plopettes, « Monte avec ton record »)
	icon: string, -- dessin (Config/Upgrades.icon)
	badge: Badge?, -- coin de l'icône : boucle (repart de zéro), infini (gardé), étoile (Conseillé)
	name: Text,
	tier: Text?, -- palier atteint (carte)
	reason: Text?, -- raison courte (carte)
	effect: Effect?,
	level: number, -- niveau montré
	maxLevel: number, -- maximum montré (Tapis : 20)
	capLevel: number, -- plafond de la boucle (au-delà : barre grisée) ; = maxLevel sinon
	levelText: string, -- « 12/20 »
	tierFill: number, -- barre vers le prochain palier (0 … 1)
	cardLevel: Effect, -- carte : « Niv. 7 », flèche, « 8 »
	preview: Preview?,
	fromText: string?, -- colonne Niveau en ×10 / Max : « 12 », flèche, « 22 »
	toText: string?,
	currency: Types.UpgradeCurrency?,
	price: number?, -- montant montré (aperçu du mode, ou prix du prochain niveau en gris)
	priceText: string?, -- nil : « — »
	have: number, -- pièces ou Confettis
	fill: number, -- barre « ce que j'ai / ce qu'il faut » (0 … 1)
	missing: number?, -- « Il manque … »
	stateText: Text?, -- mot de l'état (icône dessinée + un mot, jamais la couleur seule)
	stateIcon: string?, -- dessin de l'état (Hud/Icons)
	banner: Text?, -- phrase du bandeau propre à l'état et au mode (nil : le sort de la ligne seul)
	fate: Text?, -- « Repart de zéro au Grand Splorch » / « Gardé pour toujours »
	sendId: string?, -- identifiant canonique de BuyUpgrade (nil : rien à acheter)
	sendMode: number, -- 1 | 10 | 0
	expectedLevel: number?, -- niveau montré de sendId (niveau de la famille, Étoilé : 0 … 8)
	nap: boolean, -- Plopette qui fait la sieste
}

export type Memory = { factor: number, active: boolean, f: string }
export type Rises = {
	vat: number,
	vatMax: number,
	speed: number,
	nozzles: number,
	tier: number,
	tierMax: number,
	nextR: number?, -- prochain Record R de la table du §4.29 (≤ 20), nil au-delà
	next: { Prestige.UnlockTile }, -- ses déblocages (clés et variables ; vars.name est une CLÉ)
	v: string, -- Format.count : « 3 »
	t: string,
}

local UpgradeView = {}

-- Modes de l'intention (Config/Upgrades.Modes : ×1, ×10, Max = 0)
UpgradeView.MODES = table.freeze({ 1, 10, 0 })
local MODE_OK: { [number]: boolean } = { [1] = true, [10] = true, [0] = true }

-- Titre de la section « Pour le plaisir » (posé avant sa première ligne, non sélectionnable)
UpgradeView.SECTION_FUN = "fun.title"
-- Consigne du maintien (relâché trop tôt, « Réessaie »)
UpgradeView.HOLD = table.freeze({ key = "upgrades.detail.hold" }) :: Text

-- Dessin de chaque état (Hud/Icons) ; « En cours » : sablier (animé par l'écran)
UpgradeView.STATE_ICONS = table.freeze({
	ready = "check",
	need = "hourglass",
	max = "star",
	locked = "lock",
	loopCap = "loop",
	busy = "hourglass",
	retry = "retry",
}) :: { [string]: string }

local STATE_WORDS: { [string]: string } = {
	ready = "upgrades.state.ready",
	need = "upgrades.state.need",
	max = "upgrades.state.max",
	busy = "upgrades.state.busy",
	retry = "upgrades.state.retry",
}

local SNACK_MAX = UpgradeMath.maxLevel("snack")
local STAR_MAX = UpgradeMath.maxLevel("star")
local MAX_R = Balance.Prestige.MaxR
local FUN_RULE: Upgrades.OpenRule = { recordR = 1 } -- UpgradeMath.cap : Confettis au Record R 1

-- Lignes en lecture seule (Plopettes, « Monte avec ton record ») par identifiant
local READ_ONLY: { [string]: Upgrades.ReadOnlyDef } = {}
for _, def in Upgrades.ReadOnly do
	READ_ONLY[def.id] = def
end
-- Lignes de « Pour le plaisir » par identifiant canonique
local FUN: { [string]: Upgrades.FunLineDef } = {}
for _, line in Upgrades.Fun do
	if line.store == "bits" then
		FUN["fun." .. line.id] = line
	end
end
-- Plopettes : rang dans ByRecordR (Pip … Puff), Plume par l'Atelier
local HELPERS = { "helper.pip", "helper.pop", "helper.pim", "helper.pom", "helper.puff", "helper.plume" }
local PLUME = "helper.plume"
local HELPER_RANK: { [string]: number } = {}
for i, id in HELPERS do
	HELPER_RANK[id] = i
end
local PLUME_ROW = Upgrades.WorkshopRows[Upgrades.WorkshopIndex.plume]

-- =============================================================================================
-- Lignes de chaque onglet (ordre FIXE de Config/Upgrades, règle 1 : aucun tri)
-- =============================================================================================

local TAB_LINES: { [string]: { string } } = { ranch = {}, helpers = {}, workshop = {} }
local FIRST_FUN: string? = nil
do
	local seenRow: { [string]: boolean } = {}
	for _, def in Upgrades.Families do
		local list = TAB_LINES[def.tab]
		if list and not seenRow[def.row] then
			seenRow[def.row] = true
			table.insert(list, def.row)
		end
	end
	for _, def in Upgrades.ReadOnly do
		if def.tab == "helpers" then
			table.insert(TAB_LINES.helpers, def.id)
		end
	end
	for _, row in Upgrades.WorkshopRows do
		if row.effect ~= "cosmetic" then
			table.insert(TAB_LINES.workshop, row.id)
		end
	end
	for _, def in Upgrades.ReadOnly do
		if def.tab == "workshop" then
			table.insert(TAB_LINES.workshop, def.id)
		end
	end
	for _, line in Upgrades.Fun do
		local id = if line.store == "bits" then "fun." .. line.id else line.id
		FIRST_FUN = FIRST_FUN or id
		table.insert(TAB_LINES.workshop, id)
	end
	for _, list in TAB_LINES do
		table.freeze(list)
	end
end

-- Lignes d'un onglet (« ranch », « helpers », « workshop » ; « suggested » : aucune, ce sont des cartes)
function UpgradeView.lines(tab: string): { string }
	return TAB_LINES[tab] or {}
end

-- Titre de section posé juste avant cette ligne (« Pour le plaisir »), nil sinon
function UpgradeView.sectionBefore(lineId: string): string?
	return if lineId == FIRST_FUN then UpgradeView.SECTION_FUN else nil
end

-- Mode valide (jamais un autre mode envoyé)
function UpgradeView.mode(mode: any): number
	return if type(mode) == "number" and MODE_OK[mode] then mode else 1
end

-- =============================================================================================
-- Petits outils
-- =============================================================================================

local function langOf(ctx: Ctx?): string
	return if ctx and ctx.lang == "fr" then "fr" else "en"
end

local function count(x: any): number
	if type(x) ~= "number" or x ~= x or x < 0 then
		return 0
	end
	return math.floor(math.min(x, 1e15))
end

local function money(n: number, currency: Types.UpgradeCurrency?, lang: string): string
	if currency == "confetti" then
		return Format.confetti(n, lang)
	end
	return BigNumber.abbreviate(n, lang)
end

local function text(key: string, vars: Vars?): Text
	return { key = key, vars = vars }
end

-- Valeur d'un effet dans son unité (formateur de UI/Format seulement)
local function unit(kind: string, x: number, lang: string): Text
	if kind == "mult" then
		return text("upgrades.unit.mult", { n = Format.decimal(x, lang) })
	elseif kind == "mult3" then
		return text("upgrades.unit.mult", { n = Format.decimal(x, lang, 3) })
	elseif kind == "hours" then
		return text("upgrades.unit.hours", { n = Format.decimal(x, lang) })
	elseif kind == "seconds" then
		return text("upgrades.unit.seconds", { n = Format.decimal(x, lang, 1) })
	elseif kind == "studs" then
		return text("upgrades.unit.studs", { n = Format.decimal(x, lang) })
	elseif kind == "levels" then
		return text("upgrades.unit.levels", { n = Format.count(x) })
	elseif kind == "percent" then
		return text("upgrades.unit.percent", { n = Format.decimal(x * 100, lang) })
	elseif kind == "signedPercent" then
		-- « +4 % » des Monuments (signe et espace de Format.percent)
		return text("upgrades.unit.count", { n = Format.percent(x * 100, lang) })
	end
	return text("upgrades.unit.count", { n = Format.count(x) })
end

-- Unités de chaque clé d'effet (GDD §10.7.7) : before / after ; labelA : valeur dans le libellé
type EffectFormat = { before: string?, after: string?, labelA: string? }
local EFFECT_FORMAT: { [string]: EffectFormat } = {
	["upgrades.effect.growth"] = { before = "mult", after = "mult" }, -- Croissance ×13 → ×14
	["upgrades.effect.incomeTotal"] = { labelA = "decor" }, -- Revenu total +1,2 % (prochain niveau)
	["upgrades.effect.spots"] = { before = "count", after = "count" }, -- Places 12 → 13
	["upgrades.effect.night"] = { before = "hours", after = "hours" }, -- Nuit 8 h → 12 h
	["upgrades.effect.presses"] = { before = "mult3", after = "mult3" }, -- Pressions ×1,150 → ×1,175
	["upgrades.effect.helper"] = { before = "seconds", after = "seconds" }, -- Aide 9,3 s → 9,0 s
	["upgrades.effect.monument"] = { labelA = "monument", after = "signedPercent" }, -- Revenu +3 % → +4 %
	["upgrades.effect.gift"] = { before = "count", after = "levels" }, -- Cadeau 1 → 2 niv.
	["upgrades.effect.startMat"] = { before = "count", after = "count" }, -- Départ 0 → 1
	["upgrades.effect.magnet"] = { before = "count", after = "studs" }, -- Aimant 5 → 8 studs
	["upgrades.effect.streak"] = { before = "count", after = "count" }, -- Série max 5 → 6
	["upgrades.effect.kept"] = { before = "count", after = "count" }, -- Déco gardées 9 → 12
	["upgrades.effect.nightPot"] = { before = "percent", after = "percent" }, -- Pot la nuit 25 % → 28 %
	["upgrades.effect.plume"] = { before = "count", after = "count" }, -- Plopettes 5 → 6
	["upgrades.effect.springboard"] = { before = "count", after = "count" }, -- Tremplin 0 → 1
	["upgrades.effect.decoShop"] = {}, -- Objet suivant (l'objet est dans le bandeau)
}

-- =============================================================================================
-- Contextes (D29, D30, D31)
-- =============================================================================================

-- Contexte des effets (D30) : Lit douillet, Sac de nuit, Record R et Monuments lus dans l'instantané ;
-- A_bonus, Grand Ranch et famille Spiky donnés par l'appelant (mêmes valeurs que le revenu du HUD)
function UpgradeView.effectCtx(snap: Types.UpgradeSnapshot, ctx: Ctx?): UpgradeMath.EffectCtx
	local c: Ctx = ctx or {}
	return {
		aBonus = c.aBonus,
		bigRanch = c.bigRanch == true,
		cozyBed = count(snap.levels.cozyBed) >= 1,
		spikyFamily = c.spikyFamily == true,
		nightBag = count(snap.levels.nightBag),
		bestR = snap.bestR,
		monuments = count(snap.levels.monument),
	}
end

-- Une famille de pièces est-elle payable maintenant (même règle que les candidates d'UpgradeAdvisor :
-- ouverte, pas au maximum, Monuments seulement après le Tapis 12) ? Sert au compte « depuis combien de
-- temps rien n'est payable » de la carte Jelly Ascend (D29)
function UpgradeView.anyPayable(snap: Types.UpgradeSnapshot): boolean
	local snack = count(snap.levels.snack)
	for _, def in Upgrades.Families do
		if def.currency == "coins" and not (def.id == "monument" and snack < SNACK_MAX) then
			local level = count(snap.levels[def.id])
			local cap = math.min(count(snap.caps[def.id]), def.levels)
			if cap > level and level < def.levels then
				local price = UpgradeMath.price(def.id, level, snap.r, snap.ascend, snap.bestR)
				if price < math.huge and snap.coins >= price then
					return true
				end
			end
		end
	end
	return false
end

-- Contexte du Conseillé (D29) : AscendReady du ranch du joueur, secondes sans achat de pièces possible
function UpgradeView.advisorCtx(ascendReady: boolean?, unpayableSeconds: number?): UpgradeAdvisor.Ctx
	return { ascendReady = ascendReady == true, unpayableSeconds = count(unpayableSeconds) }
end

-- Souvenir de gelée (D31) : Prestige.memoryFactor avec Prestige.firstRecordLoop (r, Record R et A de
-- l'instantané, regainBonusA et memoryR du profil) ; f = « 3 », « 1,25 » (clé hud.memory)
function UpgradeView.memory(snap: Types.UpgradeSnapshot, ctx: Ctx?): Memory
	local c: Ctx = ctx or {}
	local first = Prestige.firstRecordLoop({
		R = snap.r,
		bestR = snap.bestR,
		ascend = snap.ascend,
		regainBonusA = c.regainBonusA,
		memoryR = c.memoryR,
	})
	local factor = Prestige.memoryFactor(snap.r, snap.bestR, first)
	return { factor = factor, active = factor > 1, f = Format.decimal(factor, langOf(ctx)) }
end

-- Nombre de Plopettes (note du lot A3) : Balance.Helpers.ByRecordR atteints par le Record R, + Plume
-- quand la ligne plume de l'Atelier est achetée
function UpgradeView.helperCount(snap: Types.UpgradeSnapshot): number
	local n = 0
	for _, at in Balance.Helpers.ByRecordR do
		if snap.bestR >= at then
			n += 1
		end
	end
	if count(snap.levels.plume) >= 1 then
		n += 1
	end
	return n
end

-- Intervalle d'une Plopette (s) : UpgradeMath.effect("school", niveau de l'École).a
function UpgradeView.helperInterval(snap: Types.UpgradeSnapshot): number
	return UpgradeMath.effect("school", count(snap.levels.school), UpgradeView.effectCtx(snap, nil)).a
end

-- « Monte avec ton record » (D22) : Cuve (qualité sur QualityMax, vitesse, buses) et palier du ranch
-- au Record R, prochain déblocage de la table du §4.29 (Record R 1 à 20)
function UpgradeView.rises(snap: Types.UpgradeSnapshot): Rises
	local vat = Formulas.vatLevel(snap.bestR)
	local tier = 0
	for _, at in Visuals.RanchTiersAt do
		if snap.bestR >= at then
			tier += 1
		end
	end
	local nextR: number? = nil
	local nextTiles: { Prestige.UnlockTile } = {}
	if snap.bestR < MAX_R and Visuals.RecordTable[snap.bestR + 1] ~= nil then
		nextR = snap.bestR + 1
		nextTiles = Prestige.unlockTiles(snap.bestR + 1)
	end
	return {
		vat = vat.quality,
		vatMax = Balance.Vat.QualityMax,
		speed = vat.speed,
		nozzles = vat.nozzles,
		tier = tier,
		tierMax = #Visuals.RanchTiersAt,
		nextR = nextR,
		next = nextTiles,
		v = Format.count(vat.quality),
		t = Format.count(tier),
	}
end

-- Atelier « Conseillé » (GDD §10.7.4) : au plus 3 lignes de jeu de l'Atelier ouvertes et pas au
-- maximum, les moins chères d'abord, ordre fixe à égalité (Déco perso et « Pour le plaisir » exclus :
-- des cosmétiques ne sont pas un conseil de jeu)
function UpgradeView.advised(snap: Types.UpgradeSnapshot): { string }
	type Cand = { id: string, order: number, price: number }
	local list: { Cand } = {}
	for order, row in Upgrades.WorkshopRows do
		if row.effect ~= "cosmetic" then
			local level = count(snap.levels[row.id])
			local max = UpgradeMath.maxLevel(row.id)
			if level < max and count(snap.caps[row.id]) > level then
				local price = UpgradeMath.price(row.id, level, snap.r, snap.ascend, snap.bestR)
				if price < math.huge then
					table.insert(list, { id = row.id, order = order, price = price })
				end
			end
		end
	end
	table.sort(list, function(a: Cand, b: Cand): boolean
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.order < b.order
	end)
	local out: { string } = {}
	for i = 1, math.min(3, #list) do
		table.insert(out, list[i].id)
	end
	return out
end

-- =============================================================================================
-- Vue d'une ligne
-- =============================================================================================

-- Condition d'ouverture du PROCHAIN niveau qui n'est pas remplie (affichage seulement) :
-- ("record", r) | ("ascend", a) | nil
local function unmet(rule: Upgrades.OpenRule?, nextLevel: number, best: number, A: number): (string?, number)
	if rule == nil then
		return nil, 0
	end
	local byLevel = rule.recordRByLevel
	if byLevel ~= nil then
		local need = byLevel[nextLevel]
		if need ~= nil and best < need then
			return "record", need
		end
	elseif rule.recordR ~= nil and best < rule.recordR then
		return "record", rule.recordR
	end
	if rule.ascend ~= nil and A < rule.ascend then
		return "ascend", rule.ascend
	end
	return nil, 0
end

-- Plus petit r' dont le plafond du Tapis Étoilé dépasse `level` (« Boucle r' ») ; nil s'il n'existe pas
local function loopFor(level: number): number?
	for r = 0, MAX_R do
		if Prestige.starCap(r) > level then
			return r
		end
	end
	return nil
end

-- Barre vers le prochain palier : (niveau − début du palier) ÷ (début du suivant − début du palier)
local function tierFill(def: Upgrades.FamilyDef?, level: number, max: number): number
	if max <= 0 then
		return 1
	end
	if def == nil or #def.tiers == 0 then
		return math.clamp(level / max, 0, 1)
	end
	local from, to = 0, max
	for _, tier in def.tiers do
		if level >= tier.from then
			from = tier.from
		elseif tier.from < to then
			to = tier.from
			break
		end
	end
	if to <= from then
		return 1
	end
	return math.clamp((level - from) / (to - from), 0, 1)
end

type Line = {
	id: string, -- identifiant canonique acheté (famille, ligne de l'Atelier, fun.<id>)
	kind: Kind,
	family: Upgrades.FamilyDef?,
	row: Upgrades.WorkshopRowDef?,
	fun: Upgrades.FunLineDef?,
	rule: Upgrades.OpenRule?,
	nameKey: string,
	effectKey: string?,
	reasonKey: string?,
	icon: string,
	kept: boolean,
}

local function lineOf(id: string): Line?
	local def = Upgrades.ById[id]
	if def ~= nil then
		return {
			id = def.id,
			kind = "family",
			family = def,
			rule = def.open,
			nameKey = def.nameKey,
			effectKey = def.effectKey,
			reasonKey = def.reasonKey,
			icon = def.icon,
			kept = def.kept,
		}
	end
	local index = Upgrades.WorkshopIndex[id]
	if index ~= nil then
		local row = Upgrades.WorkshopRows[index]
		return {
			id = row.id,
			kind = "workshop",
			row = row,
			rule = row.open,
			nameKey = row.nameKey,
			effectKey = row.effectKey,
			reasonKey = if row.effect == "cosmetic" then nil else "upgrades.reason.workshop",
			icon = row.icon,
			kept = true,
		}
	end
	local fun = FUN[id]
	if fun ~= nil then
		return {
			id = id,
			kind = "fun",
			fun = fun,
			rule = FUN_RULE,
			nameKey = fun.nameKey,
			effectKey = nil,
			reasonKey = nil,
			icon = fun.icon,
			kept = true,
		}
	end
	return nil
end

-- Vue vide (identifiant inconnu : cachée, jamais une erreur)
local function emptyView(lineId: string, mode: number): View
	return {
		id = lineId,
		kind = "family",
		state = "max",
		hidden = true,
		readOnly = true,
		icon = "",
		name = text("upgrades.title"),
		level = 0,
		maxLevel = 0,
		capLevel = 0,
		levelText = Format.level(0, 0),
		tierFill = 0,
		cardLevel = {},
		have = 0,
		fill = 0,
		sendMode = mode,
		nap = false,
	}
end

-- Avant → après d'une ligne (niveau L de l'identifiant acheté, niveau atteint par l'aperçu `toL`)
local function effectOf(
	line: Line,
	L: number,
	toL: number,
	max: number,
	snap: Types.UpgradeSnapshot,
	ctx: Ctx?
): Effect?
	local key = line.effectKey
	if key == nil then
		return nil
	end
	local fmt = EFFECT_FORMAT[key] or {}
	local lang = langOf(ctx)
	local ectx = UpgradeView.effectCtx(snap, ctx)
	local now = UpgradeMath.effect(line.id, L, ectx)
	local done = L >= max
	local label = text(key)
	if fmt.labelA == "decor" then
		-- effet réel du PROCHAIN niveau sur le revenu total ; rien à montrer au maximum
		if done then
			return nil
		end
		return { label = text(key, { a = Format.decimal(now.a * 100, lang, 1) }) }
	elseif fmt.labelA == "monument" then
		label = text(key, { a = Format.decimal(now.a * 100, lang) })
	end
	local before = if fmt.before then unit(fmt.before, now.a, lang) else nil
	local after: Text? = nil
	if not done and fmt.after then
		-- valeur au niveau atteint par l'aperçu (×1 : le niveau suivant)
		local reach = UpgradeMath.effect(line.id, math.max(L, toL - 1), ectx)
		after = unit(fmt.after, reach.b, lang)
	end
	return { label = label, before = before, after = after }
end

-- Achat du mode : (aperçu, prix montré, manque) selon UpgradeMath.plan (débit exact du serveur)
local function planOf(
	id: string,
	L: number,
	cap: number,
	mode: number,
	have: number,
	snap: Types.UpgradeSnapshot,
	shownFrom: number
): (Preview, number?)
	local n, total = UpgradeMath.plan(id, L, mode, have, cap, snap.r, snap.ascend, snap.bestR)
	if n >= 1 then
		local partial = mode == 10 and n < 10
		return { count = n, from = shownFrom, to = shownFrom + n, total = total, partial = partial }, nil
	end
	-- rien de payable : le premier niveau, « Il manque … »
	local price = UpgradeMath.price(id, L, snap.r, snap.ascend, snap.bestR)
	return { count = 1, from = shownFrom, to = shownFrom + 1, total = price, partial = false },
		math.max(0, price - have)
end

-- Vue d'une ligne à acheter (famille, ligne de l'Atelier, « Pour le plaisir »)
local function buyView(
	lineId: string,
	line: Line,
	snap: Types.UpgradeSnapshot,
	mode: number,
	ctx: Ctx?,
	pending: Pending?
): View
	local lang = langOf(ctx)
	local best, A = snap.bestR, snap.ascend
	local id = line.id
	local L = count(snap.levels[id])
	local cap = count(snap.caps[id])
	local max = UpgradeMath.maxLevel(id)
	local currency = UpgradeMath.currency(id)
	local have = if currency == "confetti" then snap.confetti else snap.coins

	-- niveaux MONTRÉS (ligne Tapis : 12 + Étoilé sur 20)
	local shownLevel, shownMax, capLevel, offset = L, max, max, 0
	local icon = line.icon
	local hiddenStar = false
	local tapis = lineId == "snack" or lineId == "star"
	local state: State
	local lockKey: string? = nil
	local lockVars: Vars? = nil
	local banner: Text? = nil
	local hidden = false

	if tapis then
		local snack = count(snap.levels.snack)
		local star = count(snap.levels.star)
		local starCapR = Prestige.starCap(snap.r)
		-- Étoilé coupé par son interrupteur : Tapis 12 atteint, plafond de la boucle au-dessus, mais fermé
		hiddenStar = snack >= SNACK_MAX
			and star < STAR_MAX
			and starCapR > star
			and count(snap.caps.star) <= star
		shownMax = if hiddenStar then SNACK_MAX else SNACK_MAX + STAR_MAX
		capLevel = if hiddenStar then SNACK_MAX else SNACK_MAX + math.min(STAR_MAX, starCapR)
		if snack < SNACK_MAX then
			shownLevel = snack
		else
			offset = SNACK_MAX
			shownLevel = if hiddenStar then SNACK_MAX else SNACK_MAX + star
			icon = Upgrades.ById.star.icon
		end
	end

	-- état d'achat (ouverture : plafonds seulement)
	if tapis and count(snap.levels.snack) >= SNACK_MAX then
		local star = count(snap.levels.star)
		if star >= STAR_MAX or hiddenStar then
			state = "max"
		elseif count(snap.caps.star) > star then
			state = "ready" -- ready ou need, décidé plus bas
		else
			local r = loopFor(star)
			if r == nil then
				state = "max"
			else
				state = "loopCap"
				lockKey, lockVars = "upgrades.state.loopCap", { r = Format.count(r) }
				banner = text("upgrades.detail.starCap", { r = Format.count(r) })
			end
		end
	elseif L >= max then
		state = "max"
	elseif cap > L then
		state = "ready"
	else
		local why, value = unmet(line.rule, L + 1, best, A)
		if why == "record" then
			state = "locked"
			lockKey, lockVars = "upgrades.state.locked", { r = Format.count(value) }
			banner = text("upgrades.detail.opensAt", { r = Format.count(value) })
		elseif why == "ascend" then
			state = "locked"
			lockKey, lockVars = "upgrades.state.lockedAscend", { a = Format.count(value) }
			banner = text("upgrades.detail.opensAtAscend")
		else
			-- règle remplie mais fermée : interrupteur du serveur (D8)
			state = "max"
			hidden = true
		end
	end

	-- identifiant et niveau de l'achat (ligne Tapis au-delà du Tapis 12 : Tapis Étoilé)
	local buyId = id
	local buyL = L
	local buyCap = cap
	local buyMax = max
	if tapis and count(snap.levels.snack) >= SNACK_MAX then
		buyId = "star"
		buyL = count(snap.levels.star)
		buyCap = count(snap.caps.star)
		buyMax = STAR_MAX
		currency = UpgradeMath.currency("star")
	end
	local buyLine = if buyId ~= id then lineOf(buyId) :: Line else line

	local preview: Preview? = nil
	local price: number? = nil
	local missing: number? = nil
	if state == "ready" then
		local p, short = planOf(buyId, buyL, buyCap, mode, have, snap, offset + buyL)
		preview = p
		price = p.total
		missing = short
		if short ~= nil then
			state = "need"
			banner = text("upgrades.detail.missing", { amount = money(short, currency, lang) })
		elseif mode == 10 and p.partial then
			banner = text("upgrades.detail.partial", {
				n = Format.count(p.count),
				a = Format.count(p.from),
				b = Format.count(p.to),
				price = money(p.total, currency, lang),
			})
		elseif mode == 10 then
			banner = text("upgrades.detail.bulk", {
				a = Format.count(p.from),
				b = Format.count(p.to),
				price = money(p.total, currency, lang),
			})
		elseif mode == 0 then
			banner = text("upgrades.detail.max", {
				n = Format.count(p.count),
				a = Format.count(p.from),
				b = Format.count(p.to),
				price = money(p.total, currency, lang),
			})
		end
	elseif state == "locked" or state == "loopCap" then
		-- prix du prochain niveau, en gris
		local p = UpgradeMath.price(buyId, buyL, snap.r, snap.ascend, snap.bestR)
		price = if p < math.huge then p else nil
	elseif state == "max" and not hidden then
		banner = text("upgrades.detail.allMax")
	end

	-- en cours / Réessaie : seulement sur une ligne encore achetable (jamais « Réessaie » au maximum)
	if (state == "ready" or state == "need") and (pending == "busy" or pending == "retry") then
		state = pending
		if pending == "retry" then
			banner = UpgradeView.HOLD
		end
	end

	local purchasable = state == "ready" or state == "need" or state == "busy" or state == "retry"
	local toL = if preview then buyL + preview.count else buyL + 1
	local tierKey = if buyLine.family then TierRules.key(buyLine.family.id, buyL) else nil
	if tierKey == nil and tapis and offset > 0 then
		tierKey = TierRules.key("snack", SNACK_MAX)
	end
	local fill = 1
	if price ~= nil and price > 0 then
		fill = math.clamp(have / price, 0, 1)
	end
	local cardBefore = text("common.level", { n = Format.count(shownLevel) })
	local cardAfter: Text? = nil
	if state ~= "max" then
		local target = if preview then preview.to else shownLevel + 1
		cardAfter = text("upgrades.unit.count", { n = Format.count(target) })
	end
	local badge: Badge? = nil
	if ctx and ctx.advised and ctx.advised[lineId] then
		badge = "advised"
	elseif line.kind == "family" then
		badge = if line.kept then "kept" else "loop"
	end
	return {
		id = lineId,
		kind = line.kind,
		state = state,
		hidden = hidden,
		readOnly = false,
		icon = icon,
		badge = badge,
		name = text(buyLine.nameKey),
		tier = if tierKey then text(tierKey) else nil,
		reason = if line.reasonKey then text(line.reasonKey) else nil,
		effect = effectOf(buyLine, buyL, toL, buyMax, snap, ctx),
		level = shownLevel,
		maxLevel = shownMax,
		capLevel = capLevel,
		levelText = Format.level(shownLevel, shownMax),
		tierFill = tierFill(buyLine.family, buyL, buyMax),
		cardLevel = { before = cardBefore, after = cardAfter },
		preview = if purchasable then preview else nil,
		fromText = if purchasable and preview then Format.count(preview.from) else nil,
		toText = if purchasable and preview then Format.count(preview.to) else nil,
		currency = currency,
		price = price,
		priceText = if price ~= nil then money(price, currency, lang) else nil,
		have = have,
		fill = if state == "max" then 1 else fill,
		missing = missing,
		stateText = if lockKey then text(lockKey, lockVars) else text(STATE_WORDS[state]),
		stateIcon = UpgradeView.STATE_ICONS[state],
		banner = banner,
		fate = text(if line.kept then "upgrades.detail.kept" else "upgrades.detail.resets"),
		sendId = if purchasable then buyId else nil,
		sendMode = mode,
		expectedLevel = if purchasable then buyL else nil,
		nap = false,
	}
end

-- Vue d'une Plopette (lecture seule, note du lot A3)
local function helperView(
	lineId: string,
	def: Upgrades.ReadOnlyDef,
	snap: Types.UpgradeSnapshot,
	mode: number,
	ctx: Ctx?
): View
	local lang = langOf(ctx)
	local rank = HELPER_RANK[lineId]
	local best = snap.bestR
	local schoolRule = (Upgrades.ById.school.open.recordR or 0)
	-- Plopettes coupées par leur interrupteur : École fermée alors que son Record R est atteint
	local helpersOff = best >= schoolRule and count(snap.caps.school) == 0
	local present, lockKey, lockVars = false, nil :: string?, nil :: Vars?
	local effect: Effect? = nil
	local banner: Text? = text("upgrades.detail.readOnly")
	if lineId == PLUME then
		present = count(snap.levels.plume) >= 1
		if not present then
			local need = PLUME_ROW.open.recordR or 0
			if best < need then
				lockKey, lockVars = "upgrades.state.locked", { r = Format.count(need) }
			else
				-- achetée à l'Atelier : cadenas « Atelier »
				lockKey = "upgrades.tab.workshop"
			end
			effect = { label = text("workshop.desc.plume") }
			banner = text("workshop.desc.plume")
		end
	else
		local at = Balance.Helpers.ByRecordR[rank] or 0
		present = best >= at
		if not present then
			lockKey, lockVars = "upgrades.state.locked", { r = Format.count(at) }
			effect = { label = text("helper.arrives", { r = Format.count(at) }) }
		end
	end
	local nap = present and ctx ~= nil and ctx.helperMode == "nap"
	if present then
		if nap then
			effect = { label = text("helper.nap") }
		else
			local interval = UpgradeView.helperInterval(snap)
			effect = { label = text("helper.interval", { s = Format.decimal(interval, lang, 1) }) }
		end
	end
	local state: State = if present then "max" else "locked"
	return {
		id = lineId,
		kind = "helper",
		state = state,
		hidden = helpersOff,
		readOnly = true,
		icon = def.icon,
		name = text(def.nameKey),
		effect = effect,
		level = 0,
		maxLevel = 0,
		capLevel = 0,
		levelText = Format.level(0, 0),
		tierFill = 0,
		cardLevel = {},
		have = 0,
		fill = 0,
		stateText = if lockKey then text(lockKey, lockVars) else nil,
		stateIcon = if present then nil else UpgradeView.STATE_ICONS.locked,
		banner = banner,
		sendMode = mode,
		nap = nap,
	}
end

-- Vue de « Monte avec ton record » (lecture seule, D22 : valeurs par UpgradeView.rises)
local function risesView(
	lineId: string,
	def: Upgrades.ReadOnlyDef,
	snap: Types.UpgradeSnapshot,
	mode: number
): View
	-- Atelier coupé : première ligne de l'Atelier fermée alors que le Record R 1 est atteint
	local first = Upgrades.WorkshopRows[1]
	local off = snap.bestR >= (first.open.recordR or 0) and count(snap.caps[first.id]) == 0
	return {
		id = lineId,
		kind = "rises",
		state = "max",
		hidden = off,
		readOnly = true,
		icon = def.icon,
		name = text(def.nameKey),
		level = 0,
		maxLevel = 0,
		capLevel = 0,
		levelText = Format.level(0, 0),
		tierFill = 0,
		cardLevel = {},
		have = 0,
		fill = 0,
		banner = text("workshop.desc.risesWithRecord"),
		sendMode = mode,
		nap = false,
	}
end

-- Vue d'une ligne ou d'une carte (pure ; jamais d'erreur : identifiant inconnu = vue cachée)
function UpgradeView.view(
	lineId: string,
	snap: Types.UpgradeSnapshot,
	mode: any,
	ctx: Ctx?,
	pending: Pending?
): View
	local m = UpgradeView.mode(mode)
	if type(lineId) ~= "string" or type(snap) ~= "table" then
		return emptyView(if type(lineId) == "string" then lineId else "", m)
	end
	local ro = READ_ONLY[lineId]
	if ro ~= nil then
		if HELPER_RANK[lineId] ~= nil then
			return helperView(lineId, ro, snap, m, ctx)
		end
		return risesView(lineId, ro, snap, m)
	end
	local line = lineOf(if lineId == "star" then "snack" else lineId)
	if line == nil then
		return emptyView(lineId, m)
	end
	return buyView(lineId, line, snap, m, ctx, pending)
end

return UpgradeView
