--!nocheck
-- Lance tous les tests : `lune run tests/run` depuis la racine du projet.
-- Filtrer : `lune run tests/run -- Economy` (exécute les specs dont le nom contient « Economy »).

local fs = require("@lune/fs")
local process = require("@lune/process")
local Test = require("./harness/Test")
local Harness = require("./harness/Harness")

local filter = nil
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
	end
end

local specs = {}
local function collect(dir: string)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			collect(full)
		elseif entry:match("%.spec%.luau$") then
			table.insert(specs, full)
		end
	end
end
collect("tests/specs")
table.sort(specs)

local T = {
	describe = Test.describe,
	it = Test.it,
	expect = Test.expect,
	Harness = Harness,
}

local loadErrors = {}
for _, path in specs do
	if filter == nil or string.find(path, filter, 1, true) then
		print("\n\27[1m" .. path .. "\27[0m")
		-- require relatif à ce fichier : tests/specs/... → ./specs/...
		local rel = "./" .. path:gsub("^tests/", ""):gsub("%.luau$", "")
		local ok, err = pcall(function()
			local spec = require(rel)
			spec(T)
		end)
		if not ok then
			table.insert(loadErrors, path .. " : " .. tostring(err))
			print("  \27[31m✗ échec de chargement : " .. tostring(err) .. "\27[0m")
		end
	end
end

local r = Test.results()
print(string.format("\n%d réussis, %d échoués, %d specs non chargées", r.passed, r.failed, #loadErrors))
for _, f in r.failures do
	print("\n\27[31m✗ " .. f .. "\27[0m")
end
for _, f in loadErrors do
	print("\n\27[31m✗ " .. f .. "\27[0m")
end
process.exit(if r.failed == 0 and #loadErrors == 0 then 0 else 1)
