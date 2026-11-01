--!strict
-- Utilitaires de tables.

local Tables = {}

function Tables.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = Tables.deepCopy(v)
	end
	return copy :: any
end

-- Ajoute à `target` les clés manquantes de `template` (récursif), sans rien écraser.
-- Utilisé pour faire évoluer les sauvegardes quand on ajoute des champs.
function Tables.reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for k, v in template do
		local current = target[k]
		if current == nil then
			target[k] = Tables.deepCopy(v)
		elseif type(v) == "table" and type(current) == "table" and next(v) ~= nil and #v == 0 then
			-- ne réconcilie que les dictionnaires non vides (pas les listes ni les maps vides)
			Tables.reconcile(current, v)
		end
	end
	return target
end

function Tables.deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not Tables.deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Tables.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Tables.keys<K>(t: { [K]: any }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

return Tables
