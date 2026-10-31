--!strict
-- Invariants — aide du paquet « economy » : contrôles de DÉVELOPPEMENT du profil (GDD §12.6 :
-- « après chaque mutation, invariants vérifiés en développement : jamais négatif, jamais NaN,
-- perchés ⊂ nebbies »).
-- Actifs seulement dans Studio (RunService:IsStudio()), ou quand Settings.Enabled force la valeur
-- (tests) ; en ligne : aucun calcul. Une violation est signalée bruyamment (warn « INVARIANT ») et
-- n'interrompt JAMAIS le jeu : aucune erreur levée, aucune réparation (le bug doit rester visible).
-- Contrôles :
--   * glow, stardust, supernovas : entiers finis, 0 ≤ x ≤ 2^53
--   * glowCarry ∈ [0 ; 1[ ; idleRate et perchIncome finis ≥ 0 ; boosts.personalUntil fini
--   * niveaux d'amélioration : entiers, 0 ≤ niveau ≤ Formulas.upgradeMaxLevel(piste, R)
--   * nebbies : chaque enregistrement valide (Collection.isValidRecord : bornes entières, pas de NaN)
--   * perchés ⊂ nebbies : les perchés sont dérivés du PROFIL par la règle des perchoirs d'AtlasService
--     (Formulas.perchCount(niveau, entrées d'Atlas, pass Extra Perches), Collection.rank) ; chacun
--     existe dans data.nebbies, et perchIncome = Σ revenu passif de ces enregistrements. Le cache de
--     session d'AtlasService n'est pas lu : EconomyService (appelant) précède AtlasService dans
--     l'ordre des services (docs §5), et AtlasService.perched() recalcule (effets de bord) quand
--     son cache est vide.
-- API :
--   Invariants.enabled() -> boolean
--   Invariants.check(player, data, where) -> { string }   -- violations (vide si tout va bien)
-- Appelé par EconomyService : avant chaque sauvegarde (DataService.onBeforeSave), après BuyUpgrade
-- et après une Supernova.
-- Dépendances : Config/Balance, Logic/Formulas, Economy/{Collection,PassEffects}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Formulas = require(Shared.Logic.Formulas)
local Collection = require(script.Parent.Collection)
local PassEffects = require(script.Parent.PassEffects)

local Invariants = {}

-- Réglages (tests) : Enabled = nil → actif seulement dans Studio
Invariants.Settings = {
	Enabled = nil :: boolean?,
}

-- Plus grand entier exact d'un double : les soldes ne le dépassent jamais (EconomyService)
local MAX_MONEY = 2 ^ 53
-- Écart toléré entre perchIncome et la somme recalculée (mêmes additions dans le même ordre :
-- normalement 0 ; la marge absorbe un ordre d'addition différent)
local INCOME_TOLERANCE = 1e-6

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function describe(x: any): string
	return if type(x) == "string" then `"{x}"` else tostring(x)
end

function Invariants.enabled(): boolean
	local forced = Invariants.Settings.Enabled
	if forced ~= nil then
		return forced
	end
	return RunService:IsStudio()
end

local function collect(player: Player, data: { [string]: any }, out: { string })
	-- monnaies et compteurs : entiers finis, jamais négatifs
	for _, key in { "glow", "stardust", "supernovas" } do
		local v = data[key]
		if not finite(v) or v % 1 ~= 0 or v < 0 or v > MAX_MONEY then
			table.insert(out, `{key} = {describe(v)} (entier fini ≥ 0 attendu)`)
		end
	end
	local carry = data.glowCarry
	if not finite(carry) or carry < 0 or carry >= 1 then
		table.insert(out, `glowCarry = {describe(carry)} (attendu dans [0 ; 1[)`)
	end
	for _, key in { "idleRate", "perchIncome" } do
		local v = data[key]
		if not finite(v) or v < 0 then
			table.insert(out, `{key} = {describe(v)} (nombre fini ≥ 0 attendu)`)
		end
	end
	local boosts = data.boosts
	if type(boosts) ~= "table" or not finite(boosts.personalUntil) then
		table.insert(out, "boosts.personalUntil non fini")
	end

	-- niveaux d'amélioration dans leurs bornes (le plafond Conga dépend de R)
	local upgrades = data.upgrades
	local R = if finite(data.supernovas) then data.supernovas else 0
	if type(upgrades) ~= "table" then
		table.insert(out, "upgrades n'est pas une table")
	else
		for _, track in Balance.UpgradeOrder do
			local level = upgrades[track]
			local max = Formulas.upgradeMaxLevel(track, R)
			if not finite(level) or level % 1 ~= 0 or level < 0 or level > max then
				table.insert(out, `upgrades.{track} = {describe(level)} (entier dans [0 ; {max}] attendu)`)
			end
		end
	end

	-- collection : enregistrements valides, perchés ⊂ nebbies, revenu perché cohérent
	local nebbies = data.nebbies
	if type(nebbies) ~= "table" then
		table.insert(out, "nebbies n'est pas une table")
		return
	end
	for uid, rec in nebbies do
		if type(uid) ~= "string" or not Collection.isValidRecord(rec) then
			table.insert(out, `nebbies[{describe(uid)}] invalide`)
		end
	end
	local perchLevel = if type(upgrades) == "table" then upgrades.perches else 0
	local atlasWords = if type(data.atlas) == "table" then data.atlas else nil
	local count =
		Formulas.perchCount(perchLevel, Collection.atlasCount(atlasWords), PassEffects.extraPerches(player))
	local ranked = Collection.rank(nebbies)
	local income = 0
	for i = 1, math.min(count, #ranked.uids) do
		local uid = ranked.uids[i]
		if nebbies[uid] == nil then
			table.insert(out, `perché {uid} absent de nebbies`)
		else
			income += ranked.income[uid]
		end
	end
	local stored = data.perchIncome
	if finite(stored) and math.abs(stored - income) > INCOME_TOLERANCE * math.max(1, income) then
		table.insert(out, `perchIncome = {stored}, Σ revenu des {count} perchoirs = {income}`)
	end
end

-- Vérifie le profil de `player` (where : point d'appel, pour le message). Ne lève jamais d'erreur.
function Invariants.check(player: Player, data: { [string]: any }, where: string): { string }
	if not Invariants.enabled() then
		return {}
	end
	local out: { string } = {}
	local ok, err = pcall(collect, player, data, out)
	if not ok then
		table.insert(out, `contrôle interrompu : {tostring(err)}`)
	end
	if #out > 0 then
		warn(`[Invariants] INVARIANT VIOLÉ ({where}) pour {player.Name} : {table.concat(out, " ; ")}`)
	end
	return out
end

return Invariants
