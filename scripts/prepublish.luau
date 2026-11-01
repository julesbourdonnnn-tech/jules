--!strict
-- Contrôle du propriétaire AVANT de publier le jeu en ligne (pas dans scripts/check.sh : la porte de
-- développement reste verte tant que la boutique n'est pas créée).
--   lune run scripts/prepublish
-- Vérifie src/shared/Config/Monetization.luau : chaque game pass et chaque produit développeur doit
-- avoir son vrai numéro du Creator Hub (un id à 0 cache l'article : boutique vide « bientôt »).
-- Échoue (code 1) en listant les articles à compléter, les numéros invalides ou en double, avec la
-- marche à suivre (docs/05-guide-publication.md §5). Code 0 : boutique prête.

local process = require("@lune/process")

-- Modules sans require : chargés tels quels
local Monetization = require("../src/shared/Config/Monetization")
local Strings = require("../src/shared/Localization/Strings")

type Item = { kind: string, key: string, def: { [string]: any } }

local function sorted(list: { [string]: any }, kind: string): { Item }
	local out: { Item } = {}
	for key, def in list do
		table.insert(out, { kind = kind, key = key, def = def })
	end
	table.sort(out, function(a, b)
		local oa = tonumber(a.def.order) or math.huge
		local ob = tonumber(b.def.order) or math.huge
		if oa ~= ob then
			return oa < ob
		end
		return a.key < b.key
	end)
	return out
end

-- Nom affiché (anglais, comme dans le Creator Hub) puis français, si connus
local function label(item: Item): string
	local nameKey = item.def.nameKey
	local en = if type(nameKey) == "string" then Strings.en[nameKey] else nil
	local fr = if type(nameKey) == "string" then Strings.fr[nameKey] else nil
	if en and fr and en ~= fr then
		return `« {en} » / « {fr} »`
	elseif en then
		return `« {en} »`
	end
	return "(nom inconnu)"
end

local items: { Item } = {}
for _, item in sorted(Monetization.Passes, "game pass") do
	table.insert(items, item)
end
for _, item in sorted(Monetization.Products, "produit développeur") do
	table.insert(items, item)
end

local missing: { string } = {}
local invalid: { string } = {}
local seen: { [number]: string } = {}
for _, item in items do
	local id = item.def.id
	local line = `{item.kind} {item.key} {label(item)}, {tostring(item.def.price)} Robux`
	if id == 0 then
		table.insert(missing, line)
	elseif type(id) ~= "number" or id ~= id or id < 0 or id % 1 ~= 0 or id == math.huge then
		table.insert(invalid, `{line} : id = {tostring(id)} (entier positif attendu)`)
	elseif seen[id] then
		table.insert(invalid, `{line} : id {id} déjà utilisé par {seen[id]}`)
	else
		seen[id] = `{item.kind} {item.key}`
	end
end

if #missing == 0 and #invalid == 0 then
	print(`✅ Boutique prête : {#items} articles ont leur numéro du Creator Hub.`)
	process.exit(0)
end

print("❌ Ne publiez pas encore : la boutique n'est pas prête (src/shared/Config/Monetization.luau).")
if #missing > 0 then
	print(`\n{#missing} article(s) avec id = 0 (caché(s) dans la boutique, aucun achat possible) :`)
	for _, line in missing do
		print("  • " .. line)
	end
end
if #invalid > 0 then
	print(`\n{#invalid} numéro(s) invalide(s) :`)
	for _, line in invalid do
		print("  • " .. line)
	end
end
print(
	"\nÀ faire : créer chaque article dans le Creator Hub puis remplacer seulement le 0 de « id = 0, »"
		.. " par son numéro (docs/05-guide-publication.md §5, étapes 5.3 à 5.5), puis relancer :"
		.. "\n  lune run scripts/prepublish"
)
process.exit(1)
