--!strict
-- Contenu des bébés et créatures du paquet chase (pur, déterministe : le tirage vient d'un Hash.stream
-- à graine). Chaque fonction rend la ligne à donner (SquishyService.give : { s, m, st, z }) et la
-- rareté de l'espèce (CatchInfo, bannières). Valeurs : Config/Balance, Config/Events (GDD §4.11,
-- §4.15, §4.21.3, §4.21.5, §4.21.6, §4.22, §4.23).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Events = require(Shared.Config.Events)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Hash = require(Shared.Logic.Hash)
local Odds = require(Shared.Logic.Odds)
local Formulas = require(Shared.Logic.Formulas)
local RushRules = require(Shared.Logic.RushRules)

local Babies = {}

export type Baby = { s: number, m: number, st: number, z: number, rarity: number }

local function finite(x: any, default: number): number
	if type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge then
		return x
	end
	return default
end

local function rarityOf(species: number): number
	local def = Species.ById[species]
	return if def then def.rarity else Rarities.COMMON
end

local function fromRoll(rng: Hash.Stream, ctx: Odds.RollCtx, size: number): Baby
	local result = Odds.roll(rng, ctx)
	return { s = result.species, m = result.mutation, st = 0, z = size, rarity = result.rarity }
end

-- Créature en fuite personnelle (GDD §4.11) : table de Qualité de la Cuve, familles débloquées, buses,
-- taille = 5 % du plus gros (minimum 1)
function Babies.runaway(rng: Hash.Stream, R: number, biggest: number, moon: boolean, unix: number): Baby
	local vat = Formulas.vatLevel(finite(R, 0))
	local size = Formulas.babySize(Balance.Runaway.SizeShare, Balance.Runaway.MinSize, finite(biggest, 0))
	return fromRoll(rng, {
		quality = vat.quality,
		nozzles = vat.nozzles,
		moon = moon == true,
		unix = finite(unix, 0),
		families = Odds.unlockedFamilies(finite(R, 0)),
	}, size)
end

-- Golden Wobbler (GDD §4.11) : Doré garanti, Qualité 4, toutes familles, 25 % du plus gros (minimum 10)
function Babies.golden(rng: Hash.Stream, R: number, biggest: number, moon: boolean, unix: number): Baby
	local vat = Formulas.vatLevel(finite(R, 0))
	local size = Formulas.babySize(Balance.Golden.SizeShare, Balance.Golden.MinSize, finite(biggest, 0))
	return fromRoll(rng, {
		quality = Balance.Golden.Quality,
		nozzles = vat.nozzles,
		moon = moon == true,
		unix = finite(unix, 0),
		forceMutation = Mutations.GOLDEN,
	}, size)
end

-- Wild Wobbler (GDD §4.21.5) : Qualité 3, buses 0, toutes familles, 15 % du plus gros (minimum 5)
function Babies.wild(rng: Hash.Stream, biggest: number, moon: boolean, unix: number): Baby
	local size = Formulas.babySize(Balance.Babies.WildShare, Balance.Babies.WildMin, finite(biggest, 0))
	return fromRoll(rng, {
		quality = Events.Wild.Quality,
		nozzles = Events.Wild.Nozzles,
		moon = moon == true,
		unix = finite(unix, 0),
	}, size)
end

-- Bébé du Rush (GDD v1.3 §4.21.3) : même espèce, 0 étoile, taille RushRules.babySize(original,
-- plus gros du receveur) ; mutation de l'original si ≤ ×5, sinon tirée (chances × LuckyMutationMult)
function Babies.rush(
	rng: Hash.Stream,
	original: { s: number, m: number },
	originalSize: number,
	receiverBiggest: number,
	receiverR: number,
	moon: boolean
): Baby
	local vat = Formulas.vatLevel(finite(receiverR, 0))
	local s = if Species.ById[original.s] then original.s else Species.PLOP
	local m = RushRules.babyMutation(finite(original.m, 0), rng:next(), vat.nozzles, moon == true)
	local size = RushRules.babySize(finite(originalSize, 1), finite(receiverBiggest, 0))
	return { s = s, m = m, st = 0, z = size, rarity = rarityOf(s) }
end

-- Démonstration de Big Plop (GDD §4.21.6) : bébé Plop, 10 % de la taille du Plop (minimum 10)
function Babies.demo(plopSize: number, biggest: number): Baby
	local size = Formulas.babySize(
		Balance.Babies.DemoShare,
		Balance.Babies.DemoMin,
		finite(biggest, 0),
		finite(plopSize, 0)
	)
	return { s = Species.PLOP, m = Mutations.NONE, st = 0, z = size, rarity = rarityOf(Species.PLOP) }
end

-- Bébé du MEGA (GDD §4.22) : Qualité min(8, qualité du joueur + 2), chances de mutation × 2, toutes
-- familles, 20 % du plus gros (minimum 10) ; MEGA MOON : 25 % de Lunaire
function Babies.mega(rng: Hash.Stream, R: number, biggest: number, megaMoon: boolean, unix: number): Baby
	local vat = Formulas.vatLevel(finite(R, 0))
	local lunar = megaMoon == true and rng:next() < Events.Mega.MoonLunarChance
	local size = Formulas.babySize(Balance.Babies.MegaShare, Balance.Babies.MegaMin, finite(biggest, 0))
	return fromRoll(rng, {
		quality = math.min(Balance.Vat.QualityMax, vat.quality + Events.Mega.QualityBonus),
		nozzles = vat.nozzles,
		moon = megaMoon == true,
		unix = finite(unix, 0),
		mutationMult = Events.Mega.MutationMult,
		forceMutation = if lunar then Mutations.LUNAR else nil,
	}, size)
end

-- Cadeau du Grand Splorch d'un autre (GDD §4.15) : espèce qui s'envole, ou espèce Peu commune de sa
-- famille si elle est Épique ou mieux (Wibble pour un Secret) ; 5 % du plus gros (minimum 1) ; sans
-- mutation, sauf 10 % de copier une mutation de multiplicateur ≤ ×5
function Babies.gift(
	rng: Hash.Stream,
	flyerSpecies: number,
	flyerMutation: number,
	receiverBiggest: number
): Baby
	local def = Species.ById[flyerSpecies]
	local s = Species.PLOP
	if def then
		s = def.id
		if def.rarity >= Rarities.EPIC then
			local family = Species.Families[def.family]
			s = if family then family.uncommon else Species.PLOP
		end
	end
	local m = Mutations.NONE
	local mut = Mutations.ById[finite(flyerMutation, 0)]
	if
		mut
		and mut.mult <= Balance.Splorch.GiftMutationMaxMult
		and rng:next() < Balance.Splorch.GiftMutationCopyChance
	then
		m = mut.id
	end
	local size = Formulas.babySize(
		Balance.Splorch.GiftSizeShare,
		Balance.Splorch.GiftMinSize,
		finite(receiverBiggest, 0)
	)
	return { s = s, m = m, st = 0, z = size, rarity = rarityOf(s) }
end

-- Goutte de Lune (GDD §4.23) : naissance de Qualité (la sienne + 1), Lunaire garantie, familles
-- débloquées, taille d'une naissance de la Cuve (1)
function Babies.lunar(rng: Hash.Stream, R: number, unix: number): Baby
	local vat = Formulas.vatLevel(finite(R, 0))
	return fromRoll(rng, {
		quality = math.min(Balance.Vat.QualityMax, vat.quality + Events.Moon.DropQualityBonus),
		nozzles = vat.nozzles,
		moon = true,
		unix = finite(unix, 0),
		families = Odds.unlockedFamilies(finite(R, 0)),
		forceMutation = Mutations.LUNAR,
	}, 1)
end

-- Ligne à donner (sans la rareté)
function Babies.spec(baby: Baby): { s: number, m: number, st: number, z: number }
	return { s = baby.s, m = baby.m, st = baby.st, z = baby.z }
end

return Babies
