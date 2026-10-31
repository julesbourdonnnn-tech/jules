--!strict
-- Appels protégés du paquet « events » : une erreur d'un service voisin (récompense, apparition…)
-- ne doit jamais casser une transition d'événement déjà appliquée. L'erreur est signalée par
-- warn, au plus une fois toutes les WARN_EVERY secondes par étiquette (mesure technique : os.clock).

local Safe = {}

local WARN_EVERY = 10
local lastWarn: { [string]: number } = {}

-- Appelle fn(...) sous pcall ; retourne (réussi, premier résultat)
function Safe.call(tag: string, fn: (...any) -> any, ...: any): (boolean, any)
	local ok, result = pcall(fn, ...)
	if not ok then
		local now = os.clock()
		local last = lastWarn[tag]
		if last == nil or now - last >= WARN_EVERY then
			lastWarn[tag] = now
			warn(`[{tag}]`, result)
		end
		return false, nil
	end
	return true, result
end

-- Comme call, mais retourne `default` en cas d'erreur ou de résultat d'un autre type
function Safe.value<T>(tag: string, default: T, fn: (...any) -> any, ...: any): T
	local ok, result = Safe.call(tag, fn, ...)
	if ok and type(result) == type(default) then
		return result :: T
	end
	return default
end

return Safe
