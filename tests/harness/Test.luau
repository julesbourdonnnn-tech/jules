--!nocheck
-- Mini framework de tests : describe / it / expect.

local Signal = require("./Signal")

local Test = {}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local stack: { string } = {}

local function fullName(name: string): string
	local parts = table.clone(stack)
	table.insert(parts, name)
	return table.concat(parts, " › ")
end

local function deepEqual(a: any, b: any): boolean
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

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	if type(v) == "table" then
		local ok, s = pcall(function()
			local parts = {}
			for k, x in v do
				table.insert(parts, tostring(k) .. "=" .. show(x))
				if #parts > 12 then
					table.insert(parts, "…")
					break
				end
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		end)
		return if ok then s else tostring(v)
	end
	return tostring(v)
end

function Test.describe(name: string, fn: () -> ())
	table.insert(stack, name)
	fn()
	table.remove(stack)
end

function Test.it(name: string, fn: () -> ())
	local label = fullName(name)
	local before = #Signal.errors
	local ok, err = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. debug.traceback(nil, 2)
	end)
	if ok and #Signal.errors > before then
		ok = false
		err = "erreur(s) dans des connexions de signaux :\n" .. table.concat(Signal.errors, "\n", before + 1)
	end
	if ok then
		results.passed += 1
		print("  \27[32m✓\27[0m " .. label)
	else
		results.failed += 1
		table.insert(results.failures, label .. "\n    " .. tostring(err):gsub("\n", "\n    "))
		print("  \27[31m✗ " .. label .. "\27[0m")
	end
end

function Test.expect(actual: any)
	local e = {}
	local function fail(msg: string)
		error(msg, 3)
	end
	function e.toBe(expected)
		if actual ~= expected then
			fail(`attendu {show(expected)}, obtenu {show(actual)}`)
		end
	end
	function e.never()
		return nil
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			fail(`attendu (profond) {show(expected)}, obtenu {show(actual)}`)
		end
	end
	function e.toBeNear(expected: number, eps: number?)
		if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
			fail(`attendu ≈ {show(expected)}, obtenu {show(actual)}`)
		end
	end
	function e.toBeTruthy()
		if not actual then
			fail(`attendu une valeur vraie, obtenu {show(actual)}`)
		end
	end
	function e.toBeFalsy()
		if actual then
			fail(`attendu une valeur fausse, obtenu {show(actual)}`)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			fail(`attendu nil, obtenu {show(actual)}`)
		end
	end
	function e.toBeGreaterThan(n: number)
		if not (type(actual) == "number" and actual > n) then
			fail(`attendu > {n}, obtenu {show(actual)}`)
		end
	end
	function e.toBeGreaterThanOrEqual(n: number)
		if not (type(actual) == "number" and actual >= n) then
			fail(`attendu >= {n}, obtenu {show(actual)}`)
		end
	end
	function e.toBeLessThan(n: number)
		if not (type(actual) == "number" and actual < n) then
			fail(`attendu < {n}, obtenu {show(actual)}`)
		end
	end
	function e.toBeLessThanOrEqual(n: number)
		if not (type(actual) == "number" and actual <= n) then
			fail(`attendu <= {n}, obtenu {show(actual)}`)
		end
	end
	function e.toContain(item)
		if type(actual) == "string" then
			if not string.find(actual, item, 1, true) then
				fail(`{show(actual)} ne contient pas {show(item)}`)
			end
		elseif type(actual) ~= "table" or table.find(actual, item) == nil then
			fail(`{show(actual)} ne contient pas {show(item)}`)
		end
	end
	function e.toHaveLength(n: number)
		if #actual ~= n then
			fail(`longueur attendue {n}, obtenue {#actual}`)
		end
	end
	function e.toThrow(pattern: string?)
		local ok, err = pcall(actual)
		if ok then
			fail("attendu une erreur, aucune levée")
		elseif pattern and not string.find(tostring(err), pattern, 1, true) then
			fail(`erreur {show(err)} ne contient pas {show(pattern)}`)
		end
	end
	function e.notToThrow()
		local ok, err = pcall(actual)
		if not ok then
			fail(`erreur inattendue : {tostring(err)}`)
		end
	end
	function e.toBeType(t: string)
		if typeof(actual) ~= t then
			fail(`type attendu {t}, obtenu {typeof(actual)}`)
		end
	end
	return e
end

function Test.results()
	return results
end

return Test
