--!nocheck
-- Lanceur des specs du vrai moteur (paquet meta, docs/04 §17.1 i). Placé sous ServerStorage.EngineTests
-- par tests/engine.project.json ; la tâche Open Cloud exécute `return Runner.runJson()` dans un vrai
-- serveur Roblox (tools/opencloud). Une spec du moteur est un module qui rend function(T) et n'utilise que
-- T.describe, T.it, T.expect, T.require("ReplicatedStorage.Shared.Logic.Formulas") (résolveur vers la vraie
-- instance), T.service(nom) et T.logErrors() : aucun module de test hors-moteur, aucun harnais. Les mêmes
-- specs passent sous Lune (tests/specs/OpenCloud.spec.luau) avec un T fait par Runner.makeT.

local Runner = {}

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
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

local function expectOf(actual)
	local e = {}
	local function fail(msg)
		error(msg, 3)
	end
	function e.toBe(x)
		if actual ~= x then
			fail("attendu " .. tostring(x) .. ", obtenu " .. tostring(actual))
		end
	end
	function e.toEqual(x)
		if not deepEqual(actual, x) then
			fail("tables différentes")
		end
	end
	function e.toBeTruthy()
		if not actual then
			fail("attendu une valeur vraie, obtenu " .. tostring(actual))
		end
	end
	function e.toBeFalsy()
		if actual then
			fail("attendu une valeur fausse, obtenu " .. tostring(actual))
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			fail("attendu nil, obtenu " .. tostring(actual))
		end
	end
	function e.toBeNear(x, eps)
		if type(actual) ~= "number" or math.abs(actual - x) > (eps or 1e-6) then
			fail("attendu ≈ " .. tostring(x) .. ", obtenu " .. tostring(actual))
		end
	end
	function e.toBeGreaterThan(x)
		if not (type(actual) == "number" and actual > x) then
			fail("attendu > " .. tostring(x) .. ", obtenu " .. tostring(actual))
		end
	end
	function e.toBeLessThan(x)
		if not (type(actual) == "number" and actual < x) then
			fail("attendu < " .. tostring(x) .. ", obtenu " .. tostring(actual))
		end
	end
	function e.toContain(x)
		if type(actual) == "string" then
			if not string.find(actual, x, 1, true) then
				fail(tostring(actual) .. " ne contient pas " .. tostring(x))
			end
		elseif type(actual) ~= "table" or table.find(actual, x) == nil then
			fail("élément absent : " .. tostring(x))
		end
	end
	return e
end

-- T de base : results = { passed, failed, failures }, resolve(chemin) → module, service(nom) → service,
-- logErrors() → lignes d'erreur ou d'avertissement du journal du moteur
function Runner.makeT(results, resolve, service, logErrors)
	local stack = {}
	local T = {}
	function T.describe(name, fn)
		table.insert(stack, name)
		fn()
		table.remove(stack)
	end
	function T.it(name, fn)
		local parts = table.clone(stack)
		table.insert(parts, name)
		local label = table.concat(parts, " › ")
		local ok, err = pcall(fn)
		if ok then
			results.passed += 1
		else
			results.failed += 1
			table.insert(results.failures, label .. " : " .. tostring(err))
		end
	end
	T.expect = expectOf
	T.require = resolve
	T.service = service
	T.logErrors = logErrors
	return T
end

-- Résolveur vers la vraie instance : "ReplicatedStorage.Shared.Logic.Formulas"
local function engineResolve(path)
	local parts = string.split(path, ".")
	local cur = game:GetService(parts[1])
	for i = 2, #parts do
		cur = cur:WaitForChild(parts[i], 10)
		assert(cur ~= nil, "introuvable : " .. path)
	end
	return require(cur)
end

local function engineLogErrors()
	local out = {}
	local ok, history = pcall(function()
		return game:GetService("LogService"):GetLogHistory()
	end)
	if ok and type(history) == "table" then
		for _, entry in history do
			local t = entry.messageType
			if t == Enum.MessageType.MessageError or t == Enum.MessageType.MessageWarning then
				table.insert(out, tostring(entry.message))
			end
		end
	end
	return out
end

-- Toutes les specs (ModuleScripts « *.spec ») du dossier du lanceur ; bilan en table
function Runner.run()
	local results = { passed = 0, failed = 0, failures = {}, errors = {} }
	local conn = game:GetService("ScriptContext").Error:Connect(function(message)
		table.insert(results.errors, tostring(message))
	end)
	local T = Runner.makeT(results, engineResolve, function(name)
		return game:GetService(name)
	end, engineLogErrors)
	local specs = {}
	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and string.sub(child.Name, -5) == ".spec" then
			table.insert(specs, child)
		end
	end
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)
	for _, module in specs do
		local ok, err = pcall(function()
			require(module)(T)
		end)
		if not ok then
			results.failed += 1
			table.insert(results.failures, module.Name .. " (chargement) : " .. tostring(err))
		end
	end
	conn:Disconnect()
	return results
end

function Runner.runJson()
	return game:GetService("HttpService"):JSONEncode(Runner.run())
end

return Runner
