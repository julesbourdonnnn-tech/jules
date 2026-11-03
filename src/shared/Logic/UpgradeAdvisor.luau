--!strict
-- UpgradeAdvisor (paquet A1, docs/04 §27.7, GDD v2.0 §10.7.4, §10.2, N18, N24). Cartes de l'onglet
-- Conseillé et cible de la puce « Prochain achat », calculées depuis l'instantané versionné
-- (Types.UpgradeSnapshot) seulement : même résultat sur le client et le serveur, déterministe.
-- Règle du Conseillé : candidats = familles DE PIÈCES ouvertes et pas au maximum (caps > niveau ;
-- Monuments seulement après le Tapis 12 de la boucle). (1) Le Tapis (ou le Tapis Étoilé, même ligne)
-- s'il est payable ; (2) puis la moins chère payable d'une autre famille ; (3) puis la moins chère
-- payable d'une troisième ; s'il en manque, les moins chères NON payables. Jamais deux cartes de la
-- même famille (le Tapis et le Tapis Étoilé comptent pour une) ; égalités départagées par l'ordre
-- fixe des familles. Place sans famille : carte neutre « Tout est au maximum ! » (jamais un trou).
-- Carte « ascend » (critique M1) : quand l'Ascension est prête et qu'aucun achat de pièces n'est
-- possible depuis Ascend.DeclineCardAfter (5 min), elle prend la place de la première carte neutre,
-- sinon de la 3e carte (la moins utile : une famille non payable).
-- L'écran ne choisit les cartes qu'à l'ouverture et au retour sur l'onglet (B2) ; next() est
-- recalculé après tout achat et tout prestige, et ne désigne jamais un niveau déjà possédé ni
-- inexistant. Jamais d'erreur sur un instantané abîmé.

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, math, table = type, math, table

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local Upgrades = require(script.Parent.Parent.Config.Upgrades)
local UpgradeMath = require(script.Parent.UpgradeMath)

export type Ctx = {
	ascendReady: boolean?, -- Jelly Ascend prête ET interrupteur JellyAscend ouvert (attribut AscendReady)
	unpayableSeconds: number?, -- depuis combien de secondes aucun achat de pièces n'est possible
}

export type Next = { id: string, level: number, price: number }

local UpgradeAdvisor = {}

-- Identifiants des cartes qui ne sont pas une famille
UpgradeAdvisor.NEUTRAL = "neutral"
UpgradeAdvisor.ASCEND = "ascend"
UpgradeAdvisor.Cards = 3

-- Ligne du Tapis (Tapis à Goûter et Tapis Étoilé) et niveau à atteindre avant les Monuments
local TAPIS_ROW = "snack"
local SNACK_MAX = UpgradeMath.maxLevel("snack")

type Candidate = { id: string, row: string, order: number, price: number, payable: boolean }

-- Entier ≥ 0 d'un instantané (illisible → 0)
local function count(x: any): number
	if type(x) ~= "number" or x ~= x or x < 0 then
		return 0
	end
	if x == math.huge then
		return math.huge
	end
	return math.floor(x)
end

local function field(t: any, key: string): any
	return if type(t) == "table" then t[key] else nil
end

-- Familles de pièces candidates, dans l'ordre fixe de Config/Upgrades.Families
local function candidates(snapshot: Types.UpgradeSnapshot): { Candidate }
	local levels = field(snapshot, "levels")
	local caps = field(snapshot, "caps")
	local coins = count(field(snapshot, "coins"))
	local r, A, best =
		count(field(snapshot, "r")), count(field(snapshot, "ascend")), count(field(snapshot, "bestR"))
	local snack = count(field(levels, "snack"))
	local out: { Candidate } = {}
	for order, def in Upgrades.Families do
		if def.currency == "coins" then
			local level = count(field(levels, def.id))
			local cap = math.min(count(field(caps, def.id)), def.levels)
			local open = cap > level and level < def.levels
			if def.id == "monument" and snack < SNACK_MAX then
				open = false
			end
			if open then
				local price = UpgradeMath.price(def.id, level, r, A, best)
				if price < math.huge then
					table.insert(out, {
						id = def.id,
						row = def.row,
						order = order,
						price = price,
						payable = coins >= price,
					})
				end
			end
		end
	end
	return out
end

-- La moins chère des candidates qui passent le filtre (ordre fixe à égalité)
local function cheapest(list: { Candidate }, taken: { [string]: boolean }, payable: boolean): Candidate?
	local best: Candidate? = nil
	for _, c in list do
		if not taken[c.row] and c.payable == payable then
			if best == nil or c.price < best.price or (c.price == best.price and c.order < best.order) then
				best = c
			end
		end
	end
	return best
end

-- Choix des familles (au plus 3), dans l'ordre des cartes
local function pick(list: { Candidate }): { Candidate }
	local chosen: { Candidate } = {}
	local taken: { [string]: boolean } = {}
	local function take(c: Candidate?)
		if c ~= nil and #chosen < UpgradeAdvisor.Cards and not taken[c.row] then
			table.insert(chosen, c)
			taken[c.row] = true
		end
	end
	-- (1) le Tapis (ou le Tapis Étoilé) s'il est payable
	for _, c in list do
		if c.row == TAPIS_ROW and c.payable then
			take(c)
			break
		end
	end
	-- (2), (3) les moins chères payables d'autres familles, puis les moins chères non payables
	while #chosen < UpgradeAdvisor.Cards do
		local c = cheapest(list, taken, true)
		if c == nil then
			break
		end
		take(c)
	end
	while #chosen < UpgradeAdvisor.Cards do
		local c = cheapest(list, taken, false)
		if c == nil then
			break
		end
		take(c)
	end
	return chosen
end

-- 3 cartes : identifiants de famille (jamais deux fois la même), "neutral" ou "ascend"
function UpgradeAdvisor.cards(snapshot: Types.UpgradeSnapshot, ctx: Ctx): { string }
	local list = candidates(snapshot)
	local chosen = pick(list)
	local out: { string } = {}
	local anyPayable = false
	for _, c in list do
		if c.payable then
			anyPayable = true
		end
	end
	for _, c in chosen do
		table.insert(out, c.id)
	end
	while #out < UpgradeAdvisor.Cards do
		table.insert(out, UpgradeAdvisor.NEUTRAL)
	end
	local waited = count(field(ctx, "unpayableSeconds"))
	if field(ctx, "ascendReady") == true and not anyPayable and waited >= Balance.Ascend.DeclineCardAfter then
		local at = table.find(out, UpgradeAdvisor.NEUTRAL) or UpgradeAdvisor.Cards
		out[at] = UpgradeAdvisor.ASCEND
	end
	return out
end

-- Cible de la puce « Prochain achat » : la première famille du Conseillé (payable d'abord), son
-- prochain niveau (niveau de la famille après l'achat ; Tapis Étoilé 1 … 8) et son prix ; nil si
-- tout est au maximum ou fermé
function UpgradeAdvisor.next(snapshot: Types.UpgradeSnapshot, _ctx: Ctx): Next?
	local chosen = pick(candidates(snapshot))
	local first = chosen[1]
	if first == nil then
		return nil
	end
	local level = count(field(field(snapshot, "levels"), first.id)) + 1
	if level > UpgradeMath.maxLevel(first.id) then
		return nil
	end
	return { id = first.id, level = level, price = first.price }
end

return UpgradeAdvisor
