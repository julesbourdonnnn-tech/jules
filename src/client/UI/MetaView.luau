--!strict
-- MetaView (lot B3, décision D3 du plan B3 ; docs/04 §27.7 « Fait au lot B3 » ; GDD v2.0 §4.15, §4.17,
-- §4.27, §4.29, §7.5, §10.3, §17.1, Annexe B.8) : vues PURES des écrans de renaissance et de méta.
-- Aucune Instance, aucun service, aucun état : même entrée, même vue. Les nombres et les règles viennent
-- de Logic/Prestige, Logic/QuestRules, Logic/Owned, Logic/RanchLook et de la configuration ; aucune formule
-- n'est refaite ici. Toute entrée hostile ou abîmée donne la valeur sûre (0, liste vide, nil), jamais
-- d'erreur ni de trace.
--
-- Textes : { key, vars? } (clés de Strings). Une variable dont la valeur est ELLE-MÊME une table
-- { key, vars? } est une clé à traduire (nom d'un déblocage, d'un ciel, d'un cosmétique) :
-- MetaView.resolve(text, tr) la remplace par sa traduction avant Text.set ; toute autre variable est une
-- chaîne déjà formatée (UI/Format, Logic/BigNumber). `ctx.lang` choisit les séparateurs des nombres.
-- `ctx.on(flag)` dit si un interrupteur v2.0 est ouvert (UI/MetaFlags.on) ; absent : TOUS coupés.
--
--   MetaView.previewTiles(kind, ctx)  -- "splorch" | "petit" | "ascend" : 3 tuiles « Tu gagnes »
--       ctx = { lang?, on?, snap? }  (snap = UI/UpgradeSnapshot.current() : r, bestR, ascend, Tremplin)
--       tuile = { id, kind = "tile", state = "ready", readOnly = true, name, value?, icon } : forme de
--       Hud/UpgradeView.View lue par UI/UpgradeCard (gabarit « tile », 400 × 300) ; name = la phrase du
--       GDD (titre sur 2 lignes de 36 px), value = la valeur 40 px quand il y en a une.
--   MetaView.keptPayable(snap, ctx)   -- première ligne de l'onglet Ranch GARDÉE au Grand Splorch et
--       payable en ×1 (UpgradeView.view, la règle de Panels/Upgrades.open("spendFirst")), sinon nil
--   MetaView.ascendLines(snap, ctx)   -- lignes de l'aperçu de la Jelly Ascend : restart, speed,
--       condition (Text), fill (0 à 1), met, startR, need
--   MetaView.records(profile, ctx)    -- Livre des records (D13) : liste de { id, text }
--   MetaView.track(profile, unix, ctx)    -- piste de la semaine (D15)
--   MetaView.challenges(profile, ctx) -- Défis de Splorch de la semaine (3 au plus)
--   MetaView.carnet(profile, ctx)     -- Carnet du Ranch : 8 paliers, objets de Déco perso, progression
--   MetaView.mastery(profile, s)      -- 3 cases de maîtrise de l'espèce s (Owned.mastery)
--   MetaView.masteryCount(profile)    -- (espèces maîtrisées, nombre d'espèces)
--   MetaView.cardText(kind, data, ctx)    -- carte « Nouveau » / v2.0 : { title, line?, panel?, tab? } ou nil
--   MetaView.weeklyIn(index, period)  -- semaines avant le retour du cosmétique de la semaine `index`
--   MetaView.resolve(text, tr)        -- texte prêt pour Text.set (variables-clés traduites par tr)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Quests = require(Shared.Config.Quests)
local Species = require(Shared.Config.Species)
local Prestige = require(Shared.Logic.Prestige)
local QuestRules = require(Shared.Logic.QuestRules)
local Owned = require(Shared.Logic.Owned)
local Bitset = require(Shared.Logic.Bitset)
local BigNumber = require(Shared.Logic.BigNumber)
local RanchLook = require(Shared.Logic.RanchLook)

local Format = require(script.Parent.Format)
local UpgradeView = require(script.Parent.Hud.UpgradeView)

local MetaView = {}

export type Text = { key: string, vars: { [string]: any }? }
export type Tile = {
	id: string,
	kind: "tile",
	state: "ready",
	readOnly: boolean,
	name: Text,
	value: Text?,
	icon: string,
}
export type Ctx = {
	lang: string?,
	on: ((string) -> boolean)?,
	snap: Types.UpgradeSnapshot?,
}
export type AscendLines = {
	restart: Text,
	speed: Text,
	condition: Text,
	fill: number,
	met: boolean,
	startR: number,
	need: number,
}
export type Record = { id: string, text: Text }
export type TrackTier = {
	n: number,
	points: number, -- points de la piste pour l'atteindre
	reward: Text,
	kind: "confetti" | "drop" | "cosmetic",
	reached: boolean,
	claimed: boolean,
}
export type WeeklyItem = {
	index: number,
	id: string,
	kind: string,
	name: Text,
	won: boolean,
	current: boolean, -- cosmétique de la période (palier 12)
	weeks: number, -- semaines avant qu'il revienne (1 à 8 ; 8 pour celui de la période)
	returns: Text, -- « Revient la semaine prochaine » / « Revient dans n semaines »
}
export type Track = {
	period: number,
	first: boolean,
	ended: boolean, -- la période gardée par la session est finie (lundi passé) : plus de jours restants
	endsAt: number,
	daysLeft: number,
	points: number,
	maxPoints: number,
	reached: number,
	pointsText: Text,
	endsText: Text,
	tiers: { TrackTier },
	cosmetic: WeeklyItem?,
	rotation: { WeeklyItem },
}
export type Challenge = { id: number, key: string, p: number, target: number, done: boolean, text: Text }
export type CarnetTier = { n: number, at: number, reward: Text?, reached: boolean, claimed: boolean }
export type CarnetDeco = { at: number, id: string, name: Text, reached: boolean }
export type Carnet = {
	bought: number,
	tier: number,
	next: number?,
	progress: Text,
	tiers: { CarnetTier },
	decos: { CarnetDeco },
}
export type Mastery = {
	star5: boolean,
	golden: boolean,
	crystal: boolean,
	count: number,
	total: number,
	done: boolean,
}
-- highlights : « Bienvenue dans la v2 ! » seulement (3 déblocages déjà gagnés, du plus haut)
export type Card = { title: Text, line: Text?, panel: string?, tab: string?, highlights: { Text }? }

local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local CONF = Balance.Confetti
local TRACK = Quests.WeeklyTrack
local TRACK_TIERS = #TRACK.Tiers
local WEEKLY = Cosmetics.WeeklyRotation
local DAY = 86400
local SPECIES_COUNT = #Species.List
local BIG = 1e300 -- borne des compteurs affichés (BigNumber.abbreviate écrit tout jusqu'ici)

-- =============================================================================================
-- Petits outils (purs, sans trace)
-- =============================================================================================

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

-- Entier de [lo ; hi] (valeur illisible : lo)
local function int(x: any, lo: number, hi: number): number
	if not finite(x) then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

-- Compteur affiché : entier fini ≥ 0 borné (valeur illisible : 0)
local function count(x: any): number
	return int(x, 0, BIG)
end

local function field(t: any, key: string): any
	return if type(t) == "table" then rawget(t, key) else nil
end

local function langOf(ctx: any): string?
	local lang = field(ctx, "lang")
	return if lang == "fr" then "fr" else "en"
end

-- Interrupteur ouvert (ctx.on absent ou en erreur : coupé)
local function isOn(ctx: any, flag: string): boolean
	local fn = field(ctx, "on")
	if type(fn) ~= "function" then
		return false
	end
	local ok, value = pcall(fn, flag)
	return ok and value == true
end

local function text(key: string, vars: { [string]: any }?): Text
	return { key = key, vars = vars }
end

-- Nombre en chaîne : entier exact avec séparateurs sous le million (BigNumber.full : « 10,000 »,
-- « 10 000 »), forme courte au-delà (BigNumber.abbreviate : jamais faux, jamais trop long)
local function num(n: number, lang: string?): string
	if finite(n) and math.abs(n) < 1e6 then
		return BigNumber.full(n, lang)
	end
	return BigNumber.abbreviate(n, lang)
end

-- Instantané lu (champs bornés ; nil ou abîmé : boucle de l'accueil)
type Snap = { r: number, bestR: number, A: number, sb: number }
local function readSnap(raw: any): Snap
	local r = int(field(raw, "r"), 0, MAX_R)
	local bestR = math.max(r, int(field(raw, "bestR"), 0, MAX_R))
	local A = int(field(raw, "ascend"), 0, MAX_A)
	local levels = field(raw, "levels")
	local sb = int(field(levels, "springboard"), 0, 1000)
	return { r = r, bestR = bestR, A = A, sb = sb }
end

-- =============================================================================================
-- Index de la configuration (chargés une fois)
-- =============================================================================================

-- « kind.id » → définition d'un cosmétique de la v2.0 (Cosmetics.ListV2, puis WeeklyRotation)
local V2_BY: { [string]: { kind: string, id: string, key: string } } = {}
for _, def in Cosmetics.ListV2 do
	V2_BY[def.kind .. "." .. def.id] = { kind = def.kind, id = def.id, key = def.key }
end
for _, def in WEEKLY do
	local k = def.kind .. "." .. def.id
	if V2_BY[k] == nil then
		V2_BY[k] = { kind = def.kind, id = def.id, key = def.key }
	end
end

-- Objet de Déco perso par identifiant
local DECO_BY_ID: { [string]: { n: number, key: string } } = {}
for _, def in Cosmetics.DecoPerso do
	DECO_BY_ID[def.id] = { n = def.n, key = def.key }
end

-- Cosmétiques de la v2.0 gagnés à la n-ième Ascension (tuile de repli Confetti coupé)
local ASCEND_ITEMS: { [number]: { kind: string, key: string } } = {}
for _, def in Cosmetics.ListV2 do
	local source = def.source
	if source and source.kind == "ascend" and ASCEND_ITEMS[source.value] == nil then
		ASCEND_ITEMS[source.value] = { kind = def.kind, key = def.key }
	end
end

-- Dessin (Hud/Icons) d'une tuile de déblocage du Record R
local UNLOCK_ICONS: { [string]: string } = {
	["unlock.workshop"] = "gear",
	["unlock.gloves"] = "glove",
	["unlock.offeredPen"] = "pen",
	["unlock.helper"] = "helper",
	["unlock.school"] = "school",
	["unlock.monument"] = "monument",
	["unlock.starMat"] = "starMat",
	["unlock.keptDecor"] = "decor",
	["unlock.goldenVat"] = "vat",
	["unlock.splorchGift"] = "gift",
	["unlock.jellyAscend"] = "star",
	["unlock.recordBonus"] = "confetti",
	["unlock.skin"] = "palette",
	["unlock.plumeRow"] = "helper",
	["unlock.fountainPool"] = "decor",
}
-- Dessin d'un objet nommé (unlock.item : clé de Cosmetics.ListV2 ou palette)
local ITEM_ICONS: { [string]: string } = {
	saddle = "saddle",
	trail = "trail",
	emote = "emote",
	flag = "pennant",
	title = "title",
	theme = "palette",
	palette = "palette",
	outfit = "gift",
	cushions = "bed",
}
local KEY_KIND: { [string]: string } = {}
for _, def in Cosmetics.ListV2 do
	KEY_KIND[def.key] = def.kind
end

local function unlockIcon(tile: Prestige.UnlockTile): string
	local icon = UNLOCK_ICONS[tile.key]
	if icon then
		return icon
	end
	if tile.key == "unlock.item" then
		local name = field(tile.vars, "name")
		local kind = if type(name) == "string" then KEY_KIND[name] else nil
		if kind == nil and type(name) == "string" and string.sub(name, 1, 8) == "palette." then
			kind = "palette"
		end
		return if kind then ITEM_ICONS[kind] or "gift" else "gift"
	end
	-- clés de la v1.3 (panel.splorch.unlock.*) : famille, Meilleur Ami, dalle, titre
	if string.find(tile.key, "bestFriend", 1, true) then
		return "heart"
	elseif string.find(tile.key, ".pad.", 1, true) then
		return "bed"
	elseif string.find(tile.key, ".title.", 1, true) then
		return "title"
	end
	return "gift"
end

-- Texte d'une tuile de déblocage : la variable `name` est une clé (nom de Plopette, d'habillage,
-- d'objet) ; les autres sont des nombres
local function unlockText(tile: Prestige.UnlockTile, lang: string?): Text
	local vars: { [string]: any }? = nil
	if type(tile.vars) == "table" then
		local out: { [string]: any } = {}
		for k, v in tile.vars do
			if k == "name" and type(v) == "string" then
				out[k] = text(v)
			elseif type(v) == "number" then
				out[k] = num(v, lang)
			elseif type(v) == "string" then
				out[k] = v
			end
		end
		vars = out
	end
	return text(tile.key, vars)
end

local function tile(id: string, name: Text, icon: string, value: Text?): Tile
	return {
		id = id,
		kind = "tile",
		state = "ready",
		readOnly = true,
		name = name,
		value = value,
		icon = icon,
	}
end

-- Tuile de repli « Retour au record » (Confettis coupés : aucune tuile qui mentirait)
local function regainTile(r: number, bestR: number, lang: string?): Tile
	return tile(
		"regain",
		text("hud.regainTrack"),
		"arrowUp",
		text("hud.regainProgress", { r = num(r, lang), best = num(bestR, lang) })
	)
end

-- =============================================================================================
-- Aperçus de renaissance (D6)
-- =============================================================================================

-- Tuile 2 d'un Grand Splorch qui atteint le Record R `next` : le premier déblocage NOMMÉ de ce Record R
-- (la prime de record est déjà comptée par la tuile des Confettis), sinon la prime elle-même
local function recordTile(next: number, lang: string?): Tile?
	local tiles = Prestige.unlockTiles(next)
	local pick: Prestige.UnlockTile? = nil
	for _, t in tiles do
		if t.key ~= "unlock.recordBonus" then
			pick = t
			break
		end
	end
	pick = pick or tiles[1]
	if pick == nil then
		return nil
	end
	return tile("unlock", unlockText(pick, lang), unlockIcon(pick))
end

local function splorchTiles(s: Snap, ctx: any): { Tile }
	local lang = langOf(ctx)
	local next = math.min(s.r + 1, MAX_R)
	local record = Prestige.isRecord(next, s.bestR)
	local second: Tile
	if isOn(ctx, "RecordR") then
		second = (if record then recordTile(next, lang) else nil)
			or tile("gift", text("splorch.tile.gift"), "gift")
	else
		-- RecordR coupé : le texte de déblocage de la v1.3 (Balance.Splorch.Unlocks), sinon la Cuve
		local list = Balance.Splorch.Unlocks[next]
		local first = if type(list) == "table" then list[1] else nil
		if type(first) == "string" then
			second = tile("unlock", text("panel.splorch.unlock." .. first), "gift")
		else
			second = tile("unlock", text("panel.splorch.unlock.vat"), "vat")
		end
	end
	local third: Tile
	if isOn(ctx, "Confetti") then
		local n = Prestige.confettiGain("splorch", next, s.bestR, 0)
		third = tile("confetti", text("splorch.tile.confetti", { n = Format.confetti(n, lang) }), "confetti")
	elseif record then
		third = tile("fame", text("panel.splorch.win.fame"), "star")
	else
		third = regainTile(next, s.bestR, lang)
	end
	return { tile("growth", text("splorch.tile.growth"), "arrowUp"), second, third }
end

local function petitTiles(s: Snap, ctx: any): { Tile }
	local lang = langOf(ctx)
	local third = if isOn(ctx, "Confetti")
		then tile("confetti", text("petit.tile"), "confetti")
		else regainTile(math.min(s.r + 1, MAX_R), s.bestR, lang)
	return {
		tile("growth", text("splorch.tile.growth"), "arrowUp"),
		tile("gift", text("splorch.tile.gift"), "gift"),
		third,
	}
end

-- Nom du ciel de l'Ascension `A` (sky.1 … sky.10, puis la constellation et ses étoiles)
local function skyName(A: number, lang: string?): Text
	local id, stars = RanchLook.sky(A)
	if stars > 0 then
		return text("sky.stars", { n = num(stars, lang) })
	end
	return text(id or "sky.1")
end

-- Départ de l'Ascension suivante et Grands Splorch sautés grâce au Tremplin (même écart que
-- Prestige.apply : startR(A + 1, Tremplin) − startR(A + 1, 0))
local function ascendStart(s: Snap): (number, number)
	local nextA = math.min(s.A + 1, MAX_A)
	local start = Prestige.startR(nextA, s.sb)
	return start, math.max(0, start - Prestige.startR(nextA, 0))
end

local function ascendTiles(s: Snap, ctx: any): { Tile }
	local lang = langOf(ctx)
	local nextA = math.min(s.A + 1, MAX_A)
	local start, skipped = ascendStart(s)
	local third: Tile
	if isOn(ctx, "Confetti") then
		local n = Prestige.confettiGain("ascend", start, s.bestR, skipped)
		third = tile("confetti", text("ascend.tile.confetti", { n = Format.confetti(n, lang) }), "confetti")
	else
		local item = ASCEND_ITEMS[nextA]
		if item and (item.kind ~= "theme" or isOn(ctx, "RanchSkins")) then
			third = tile(
				"unlock",
				text("unlock.item", { name = text(item.key) }),
				ITEM_ICONS[item.kind] or "gift"
			)
		else
			third = regainTile(start, s.bestR, lang)
		end
	end
	return {
		tile("growth", text("ascend.tile.growth"), "arrowUp"),
		tile("sky", text("ascend.tile.sky", { name = skyName(nextA, lang) }), "star"),
		third,
	}
end

-- 3 tuiles « Tu gagnes » d'un aperçu (D6) : Grand Splorch (tuile 2 = déblocage du Record R atteint ou
-- « Cadeau du Splorch » ; RecordR coupé : texte de la v1.3 ; tuile 3 = Confettis, Confetti coupé : Fame
-- d'un nouveau record ou « Retour au record »), Petit Splorch (il faut PetitSplorch, sinon celles du
-- Grand Splorch), Jelly Ascend (×3, ciel de l'Ascension suivante, Confettis Tremplin compris)
function MetaView.previewTiles(kind: string, ctx: Ctx?): { Tile }
	local s = readSnap(field(ctx, "snap"))
	if kind == "ascend" then
		return ascendTiles(s, ctx)
	elseif kind == "petit" and isOn(ctx, "PetitSplorch") then
		return petitTiles(s, ctx)
	end
	return splorchTiles(s, ctx)
end

-- Première ligne de l'onglet Ranch gardée au Grand Splorch (Enclos, Lit douillet, Monuments) et payable
-- en ×1 : la règle de Panels/Upgrades.open("spendFirst") ; ligne coupée par un interrupteur : sautée
function MetaView.keptPayable(snap: Types.UpgradeSnapshot?, ctx: UpgradeView.Ctx?): string?
	if type(snap) ~= "table" then
		return nil
	end
	for _, id in UpgradeView.lines("ranch") do
		local ok, view = pcall(UpgradeView.view, id, snap, 1, ctx)
		if ok and type(view) == "table" and view.kept and not view.hidden and view.state == "ready" then
			return id
		end
	end
	return nil
end

-- Lignes de l'aperçu de la Jelly Ascend : départ (Prestige.startR de l'Ascension suivante, Tremplin
-- compris) et Record R, vitesse de la remontée (Prestige.regainSpeedup), condition (r / Prestige.reqR)
function MetaView.ascendLines(snap: Types.UpgradeSnapshot?, ctx: Ctx?): AscendLines
	local s = readSnap(snap)
	local lang = langOf(ctx)
	local start = ascendStart(s)
	local need = Prestige.reqR(s.A + 1)
	local met = s.A < MAX_A and s.r >= need
	local fill = if need > 0 then math.clamp(s.r / need, 0, 1) else 1
	return {
		restart = text("preview.ascend.restart", { s = num(start, lang), r = num(s.bestR, lang) }),
		speed = text("preview.ascend.speed", { n = num(Prestige.regainSpeedup(), lang) }),
		condition = text("ascend.condition", { r = num(s.r, lang), need = num(need, lang) }),
		fill = fill,
		met = met,
		startR = start,
		need = need,
	}
end

-- =============================================================================================
-- Livre des records (D13 ; GDD §17.1)
-- =============================================================================================

-- Espèces maîtrisées (bits de profile.mastery parmi les espèces connues) et nombre d'espèces
function MetaView.masteryCount(profile: any): (number, number)
	local bits = field(profile, "mastery")
	return Bitset.countRange(bits, 1, SPECIES_COUNT), SPECIES_COUNT
end

-- Lignes du Livre des records, lues dans le profil SEUL (ordre du GDD §17.1) ; une ligne d'un système
-- coupé (Confetti, JellyAscend, Mastery, Hearts) n'est pas rendue
function MetaView.records(profile: any, ctx: Ctx?): { Record }
	local lang = langOf(ctx)
	local stats = field(profile, "stats")
	local out: { Record } = {}
	local function add(id: string, key: string, vars: { [string]: any })
		table.insert(out, { id = id, text = text(key, vars) })
	end
	local p = if type(profile) == "table" then profile else {}
	add("biggest", "records.biggest", { size = num(count(field(p, "biggestEver")), lang) })
	add("bestCombo", "records.bestCombo", { n = num(count(field(stats, "bestCombo")), lang) })
	add("splorches", "records.splorches", { n = num(count(field(stats, "splorches")), lang) })
	if isOn(ctx, "JellyAscend") then
		add("ascend", "records.ascend", { n = num(Prestige.ascend(p), lang) })
	end
	add("bestR", "records.bestR", { r = num(Prestige.bestR(p), lang) })
	if isOn(ctx, "Confetti") then
		add(
			"confetti",
			"records.confettiEarned",
			{ n = Format.confetti(count(field(p, "confettiTotal")), lang) }
		)
	end
	if isOn(ctx, "Mastery") then
		local n, m = MetaView.masteryCount(p)
		add("mastery", "records.mastery", { n = num(n, lang), m = num(m, lang) })
	end
	add("plopDays", "records.plopDays", { n = num(count(field(p, "plopDays")), lang) })
	if isOn(ctx, "Hearts") then
		add("hearts", "records.hearts", { n = num(count(field(field(p, "hearts"), "receivedTotal")), lang) })
	end
	add("upgrades", "records.upgrades", { n = num(count(field(stats, "upgradesBought")), lang) })
	return out
end

-- =============================================================================================
-- Piste de la semaine, Défis, Carnet (D15 ; GDD §7.5)
-- =============================================================================================

-- Semaines avant que le cosmétique de la semaine `index` (1 à 8) revienne après la période `period`
-- (rotation de Cosmetics.WeeklyRotation : celui de la période `p` est WeeklyRotation[p % 8 + 1], comme
-- QuestService) : 1 = la semaine prochaine … 8 = celui de la période même, qui revient dans 8 semaines
function MetaView.weeklyIn(index: number, period: number): number
	local n = #WEEKLY
	local i = int(index, 1, n)
	local p = int(period, 0, 1e12)
	local w = ((i - 1) - (p % n)) % n
	return if w == 0 then n else w
end

local function weeklyItem(index: number, period: number, won: any, lang: string?): WeeklyItem?
	local def = WEEKLY[index]
	if def == nil then
		return nil
	end
	local weeks = MetaView.weeklyIn(index, period)
	return {
		index = index,
		id = def.id,
		kind = def.kind,
		name = text(def.key),
		won = Bitset.has(won, index),
		current = (period % #WEEKLY) + 1 == index,
		weeks = weeks,
		returns = if weeks == 1
			then text("track.returnsNext")
			else text("track.returnsIn", { n = num(weeks, lang) }),
	}
end

-- Piste de la semaine : 12 paliers (récompense de Quests.WeeklyTrack.Tiers : Confettis, Goutte
-- chanceuse, cosmétique de la période), points (QuestRules.trackTier), paliers réclamés (bits du
-- serveur, aucun bouton), cosmétique de la période et la rotation des 8 (gagné, retour dans n semaines),
-- jours restants (QuestRules.trackPeriod ; une période gardée par la session après le lundi : finie)
function MetaView.track(profile: any, unix: number, ctx: Ctx?): Track
	local lang = langOf(ctx)
	local wt = field(profile, "weeklyTrack")
	local now = if finite(unix) then unix else 0
	local okPeriod, info =
		pcall(QuestRules.trackPeriod, if type(profile) == "table" then profile else {}, now)
	local computed = if okPeriod and type(info) == "table" then info else nil
	local stored = int(field(wt, "period"), 0, 1e12)
	local period = if stored > 0 then stored elseif computed then computed.period else 0
	local ended = computed ~= nil and stored > 0 and stored ~= computed.period
	local endsAt = if computed and not ended then computed.endsAt else now
	local daysLeft = if ended then 0 else math.max(0, math.ceil((endsAt - now) / DAY))
	local points = int(field(wt, "points"), 0, 1e6)
	local reached = QuestRules.trackTier(points)
	local claimed = field(wt, "claimed")
	local won = field(wt, "won")
	local index = (period % #WEEKLY) + 1
	local cosmetic = weeklyItem(index, period, won, lang)
	local tiers: { TrackTier } = {}
	for n, reward in TRACK.Tiers do
		local r: Text
		local kind: "confetti" | "drop" | "cosmetic"
		if type(reward) == "number" then
			r, kind = text("confetti.gain", { n = Format.confetti(reward, lang) }), "confetti"
		elseif reward == "drop" then
			r, kind = text("track.drop"), "drop"
		else
			r, kind = if cosmetic then cosmetic.name else text("track.drop"), "cosmetic"
		end
		table.insert(tiers, {
			n = n,
			points = n * TRACK.PointsPerTier,
			reward = r,
			kind = kind,
			reached = n <= reached,
			claimed = Bitset.has(claimed, n),
		})
	end
	local rotation: { WeeklyItem } = {}
	for i = 1, #WEEKLY do
		local item = weeklyItem(i, period, won, lang)
		if item then
			table.insert(rotation, item)
		end
	end
	local maxPoints = TRACK_TIERS * TRACK.PointsPerTier
	return {
		period = period,
		first = computed ~= nil and computed.first == true and not ended,
		ended = ended,
		endsAt = endsAt,
		daysLeft = daysLeft,
		points = points,
		maxPoints = maxPoints,
		reached = reached,
		pointsText = text(
			"track.points",
			{ n = num(math.min(points, maxPoints), lang), m = num(maxPoints, lang) }
		),
		endsText = text("track.endsIn", { d = num(daysLeft, lang) }),
		tiers = tiers,
		cosmetic = cosmetic,
		rotation = rotation,
	}
end

-- Défis de Splorch de la semaine (weeklyTrack.challenges, Quests.Challenges[id]) : 3 au plus, entrées
-- illisibles sautées ; fait = done du serveur ou objectif atteint
function MetaView.challenges(profile: any, ctx: Ctx?): { Challenge }
	local lang = langOf(ctx)
	local list = field(field(profile, "weeklyTrack"), "challenges")
	local out: { Challenge } = {}
	if type(list) ~= "table" then
		return out
	end
	for i = 1, TRACK.ChallengesPerWeek do
		local entry = rawget(list, i)
		local id = field(entry, "id")
		local def = if type(id) == "number" and id % 1 == 0 then Quests.Challenges[id] else nil
		if def ~= nil and def.id == id then
			local target = def.target
			local p = int(field(entry, "p"), 0, target)
			local done = field(entry, "done") == true or p >= target
			if done then
				p = target
			end
			table.insert(out, {
				id = id,
				key = def.key,
				p = p,
				target = target,
				done = done,
				text = text("challenge.progress", { n = num(p, lang), m = num(target, lang) }),
			})
		end
	end
	return out
end

-- Nom d'une récompense du Carnet (« kind.id » de Cosmetics.ListV2)
local function rewardName(ref: any): Text?
	local def = if type(ref) == "string" then V2_BY[ref] else nil
	return if def then text(def.key) else nil
end

-- Carnet du Ranch : niveaux achetés à vie (stats.upgradesBought), 8 paliers (QuestRules.carnetTier,
-- bits réclamés du serveur), objets de Déco perso des seuils de Quests.Carnet.DecoAt, progression vers
-- le prochain seuil (le dernier une fois tout atteint)
function MetaView.carnet(profile: any, ctx: Ctx?): Carnet
	local lang = langOf(ctx)
	local bought = count(field(field(profile, "stats"), "upgradesBought"))
	local tier = QuestRules.carnetTier(bought)
	local next = QuestRules.carnetNext(bought)
	local bits = field(profile, "carnet")
	local tiers: { CarnetTier } = {}
	for n, at in Quests.Carnet.Tiers do
		table.insert(tiers, {
			n = n,
			at = at,
			reward = rewardName(Quests.Carnet.Rewards[at]),
			reached = bought >= at,
			claimed = Bitset.has(bits, n),
		})
	end
	local decos: { CarnetDeco } = {}
	for at, id in Quests.Carnet.DecoAt do
		local def = DECO_BY_ID[id]
		if def then
			table.insert(decos, { at = at, id = id, name = text(def.key), reached = bought >= at })
		end
	end
	table.sort(decos, function(a, b)
		return a.at < b.at
	end)
	local last = Quests.Carnet.Tiers[#Quests.Carnet.Tiers]
	local goal = next or last
	return {
		bought = bought,
		tier = tier,
		next = next,
		progress = text("carnet.progress", { n = num(math.min(bought, goal), lang), m = num(goal, lang) }),
		tiers = tiers,
		decos = decos,
	}
end

-- 3 cases de maîtrise de l'espèce s (★5, page dorée, Trophée Cristal ; Owned.mastery)
function MetaView.mastery(profile: any, s: number): Mastery
	local star5, golden, crystal = false, false, false
	if type(s) == "number" and Species.ById[s] ~= nil then
		local ok, a, b, c = pcall(Owned.mastery, profile, s)
		if ok then
			star5, golden, crystal = a == true, b == true, c == true
		end
	end
	local n = (if star5 then 1 else 0) + (if golden then 1 else 0) + (if crystal then 1 else 0)
	return { star5 = star5, golden = golden, crystal = crystal, count = n, total = 3, done = n == 3 }
end

-- =============================================================================================
-- Cartes (D19)
-- =============================================================================================

-- Nom (clé) d'un élément du ranch construit pour la première fois (RanchRenderer.ElementBuilt) :
-- paliers « tierN.* » → ranchTier.N, « monument.N » → monument.N, maisonnette des Plopettes ; nil sinon
local function elementName(id: any): Text?
	if type(id) ~= "string" or #id > 64 then
		return nil
	end
	local n = string.match(id, "^tier(%d)%.%a+$")
	if n then
		local k = tonumber(n)
		return if k and k >= 1 and k <= 6 then text("ranchTier." .. k) else nil
	end
	local m = string.match(id, "^monument%.(%d+)$")
	if m then
		local k = tonumber(m)
		return if k and k >= 1 and k <= #Balance.Monuments.OpenAt then text("monument." .. k) else nil
	end
	if id == "helper.house" then
		return text("helper.house")
	end
	return nil
end

-- Texte d'un déblocage d'un `keys` de « Bienvenue » : retrouvé dans Prestige.unlockTiles du Record R
-- vers 1 (ses variables) ; introuvable : nil (jamais une variable « {n} » laissée à l'écran)
local function highlightText(key: any, bestR: number, lang: string?): Text?
	if type(key) ~= "string" then
		return nil
	end
	for r = math.min(bestR, MAX_R), 1, -1 do
		for _, t in Prestige.unlockTiles(r) do
			if t.key == key then
				return unlockText(t, lang)
			end
		end
	end
	return nil
end

-- Texte d'une carte v2.0 (Celebrate du serveur, ou « element » = ElementBuilt du rendu) ; charge
-- vérifiée, sorte ou identifiant inconnu : nil (la carte n'existe pas). `ctx.snap` donne le Record R
-- (Bienvenue). panel / tab : l'écran qu'ouvre la carte rouverte depuis la liste « ! »
function MetaView.cardText(kind: string, data: any, ctx: Ctx?): Card?
	local lang = langOf(ctx)
	if kind == "welcomeV2" then
		local lines: { Text } = {}
		local s = readSnap(field(ctx, "snap"))
		local list = field(data, "highlights")
		if type(list) == "table" then
			for i = 1, 3 do
				local t = highlightText(rawget(list, i), s.bestR, lang)
				if t then
					table.insert(lines, t)
				end
			end
		end
		return {
			title = text("card.welcomeV2.title"),
			line = text("card.welcomeV2.body"),
			highlights = lines,
		}
	elseif kind == "regainDone" then
		local bestR = field(data, "bestR")
		if type(bestR) ~= "number" or bestR ~= bestR or bestR < 1 or bestR > MAX_R or bestR % 1 ~= 0 then
			return nil
		end
		local confetti = count(field(data, "confetti"))
		return {
			title = text("card.regainDone", { r = num(bestR, lang) }),
			line = if confetti > 0
				then text("confetti.gain", { n = Format.confetti(confetti, lang) })
				else nil,
		}
	elseif kind == "recordStep" then
		local share = field(data, "share")
		local p = if share == 0.25 then 25 elseif share == 0.5 then 50 elseif share == 0.75 then 75 else nil
		if p == nil then
			return nil
		end
		return { title = text("card.recordStep", { p = num(p, lang) }) }
	elseif kind == "unlock" then
		local k = field(data, "kind")
		local id = field(data, "id")
		if type(k) ~= "string" or type(id) ~= "string" then
			return nil
		end
		if k == "deco" then
			local def = DECO_BY_ID[id]
			if def == nil then
				return nil
			end
			return { title = text("card.unlockNew", { name = text(def.key) }), panel = "Ranch", tab = "style" }
		end
		local def = V2_BY[k .. "." .. id]
		if def == nil then
			return nil -- cosmétique de la v1.3 : le message du HUD de la v1.3 suffit
		end
		-- emote : choisie dans les Réglages (emote de la croix) ; le reste : Ranch › Mon style
		if k == "emote" then
			return { title = text("card.unlockNew", { name = text(def.key) }), panel = "Settings" }
		end
		return { title = text("card.unlockNew", { name = text(def.key) }), panel = "Ranch", tab = "style" }
	elseif kind == "unlock2" then
		local r = field(data, "recordR")
		if type(r) ~= "number" or r ~= r or r < 1 or r > MAX_R or r % 1 ~= 0 then
			return nil
		end
		local tiles = Prestige.unlockTiles(r)
		local first, second = tiles[1], tiles[2]
		if first == nil then
			return nil
		end
		return {
			title = text("card.unlockNew", { name = unlockText(first, lang) }),
			line = if second then unlockText(second, lang) else nil,
		}
	elseif kind == "trackTier" then
		local tierN = field(data, "tier")
		if type(tierN) ~= "number" or tierN % 1 ~= 0 or tierN < 1 or tierN > TRACK_TIERS then
			return nil
		end
		local reward = field(data, "reward")
		local line: Text? = nil
		if reward == "confetti" then
			local n = TRACK.Tiers[tierN]
			line = if type(n) == "number"
				then text("confetti.gain", { n = Format.confetti(n, lang) })
				else nil
		elseif reward == "drop" then
			line = text("track.drop")
		elseif type(reward) == "string" and reward ~= "" then
			line = rewardName(reward)
		end
		return {
			title = text("track.tier", { n = num(tierN, lang) }),
			line = line,
			panel = "Objectives",
			tab = "track",
		}
	elseif kind == "carnet" then
		local tierN = field(data, "tier")
		if type(tierN) ~= "number" or tierN % 1 ~= 0 or tierN < 1 or tierN > #Quests.Carnet.Tiers then
			return nil
		end
		return {
			title = text("carnet.title"),
			line = rewardName(field(data, "reward")),
			panel = "Objectives",
			tab = "carnet",
		}
	elseif kind == "mastery" then
		local s = field(data, "species")
		local def = if type(s) == "number" then Species.ById[s] else nil
		if def == nil then
			return nil
		end
		return {
			title = text("mastery.done", {
				name = text("species." .. def.key),
				n = Format.confetti(CONF.Mastery, lang),
			}),
			panel = "Squishydex",
			tab = "species",
		}
	elseif kind == "element" then
		local name = elementName(field(data, "id"))
		if name == nil then
			return nil
		end
		return { title = text("card.unlockNew", { name = name }) }
	end
	return nil
end

-- =============================================================================================
-- Texte prêt à poser
-- =============================================================================================

-- Copie de `t` dont chaque variable-clé ({ key, vars? }) est remplacée par sa traduction tr(key, vars)
-- (récursif, 4 niveaux au plus) ; nil si `t` n'est pas un texte
function MetaView.resolve(t: any, tr: (string, { [string]: any }?) -> string, depth: number?): Text?
	if type(t) ~= "table" or type(rawget(t, "key")) ~= "string" then
		return nil
	end
	local d = depth or 0
	local vars = rawget(t, "vars")
	if type(vars) ~= "table" then
		return { key = t.key }
	end
	local out: { [string]: any } = {}
	for k, v in vars do
		if type(v) == "table" then
			local inner = if d < 4 then MetaView.resolve(v, tr, d + 1) else nil
			out[k] = if inner then tr(inner.key, inner.vars) else ""
		else
			out[k] = v
		end
	end
	return { key = t.key, vars = out }
end

return MetaView
