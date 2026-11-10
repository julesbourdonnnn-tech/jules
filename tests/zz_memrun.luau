--!nocheck
-- SONDE JETABLE (porte B3, jamais validée) : comme tests/run.luau, plus le tas Luau après chaque spec
local fs = require("@lune/fs")
local process = require("@lune/process")
local Test = require("./harness/Test")
local Harness = require("./harness/Harness")
local filters = {}
for _, arg in process.args do
	if arg ~= "--" then
		table.insert(filters, arg)
	end
end
local specs = {}
local function collect(dir)
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
local T = { describe = Test.describe, it = Test.it, expect = Test.expect, Harness = Harness }
local ZeroLog = require("./harness/ZeroLog")
local function match(path)
	if #filters == 0 then
		return true
	end
	for _, f in filters do
		if string.find(path, f, 1, true) then
			return true
		end
	end
	return false
end
for _, path in specs do
	if match(path) then
		local before = collectgarbage("count")
		local rel = "./" .. path:gsub("^tests/", ""):gsub("%.luau$", "")
		local ok, err = pcall(function()
			require(rel)(ZeroLog.forSpec(path, T))
		end)
		Harness.disposeAll()
		local mid = collectgarbage("count")
		print(string.format("MEM %s avant=%.0f Mo fin=%.0f Mo %s", path, before / 1024, mid / 1024, ok and "" or ("ERR " .. tostring(err))))
	end
end
local r = Test.results()
print(string.format("\n%d réussis, %d échoués", r.passed, r.failed))
