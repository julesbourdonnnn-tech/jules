--!nocheck
-- Static_NoPow (paquet A1, règle 5 du GDD §10.8, docs/04 §27.7) : aucune puissance dans
-- Logic/UpgradeMath ni Logic/Prestige (ni dans les autres modules purs de la progression : Bitset,
-- TierRules, UpgradeAdvisor). La puissance n'est pas garantie identique au bit près entre les
-- consoles, le PC et le serveur ; un écart d'un bit devient une pièce après floor. Interdits hors
-- des commentaires et des chaînes : l'opérateur ^, math.pow, math.exp, tout champ .pow / .exp et
-- un accès math[…] (math["pow"]). Le lecteur statique (tests/harness/LuauScan) est vérifié ici
-- sur des exemples.
local fs = require("@lune/fs")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local LuauScan = require("../harness/LuauScan")

	local FILES = {
		"src/shared/Logic/Prestige.luau",
		"src/shared/Logic/UpgradeMath.luau",
		"src/shared/Logic/UpgradeAdvisor.luau",
		"src/shared/Logic/Bitset.luau",
		"src/shared/Logic/TierRules.luau",
	}

	-- Interdits trouvés dans un source (liste de « ligne : motif »)
	local function forbidden(src)
		local code = LuauScan.strip(src, false)
		local found = {}
		for _, pattern in { "%^", "%.%s*pow%f[^%w_]", "%.%s*exp%f[^%w_]", "math%s*%[" } do
			local pos = 1
			while true do
				local s, e = string.find(code, pattern, pos)
				if s == nil then
					break
				end
				table.insert(found, LuauScan.lineOf(code, s) .. " : " .. string.sub(code, s, e))
				pos = e + 1
			end
		end
		return found
	end

	describe("Static_NoPow", function()
		it("le lecteur statique ignore commentaires et chaînes, et trouve chaque forme interdite", function()
			local clean = table.concat({
				"-- 2 ^ 10 dans un commentaire",
				"--[[ math.pow(2, 3) ]]",
				"--[==[ x ^ y ]==]",
				"local s = \"a ^ b\" .. 'math.exp(1)' .. [[ 3 ^ 4 ]] .. [=[ ^ ]=]",
				'local p = string.match(s, "^(%w+)$")',
				"local t = `{1} ^ {2}`",
				'local q = "\\" ^ "',
				"local x = a * b",
			}, "\n")
			expect(forbidden(clean)).toEqual({})
			expect(#forbidden("local y = 2 ^ 8")).toBe(1)
			expect(#forbidden("local y = math.pow(2, 8)")).toBe(1)
			expect(#forbidden("local e = math.exp\nlocal z = e(1)")).toBe(1)
			expect(#forbidden('local f = math["pow"]')).toBe(1)
			expect(#forbidden("local m = math; local f = m.pow")).toBe(1)
			expect(#forbidden("x ^= 2")).toBe(1)
			-- les numéros de ligne restent justes après un commentaire ou une chaîne longue
			expect(forbidden("--[[\n\n]]\nlocal s = [[\n]]\nlocal y = 2 ^ 3")[1]).toBe("6 : ^")
		end)

		it(
			"aucun ^, math.pow, math.exp dans Prestige, UpgradeMath, UpgradeAdvisor, Bitset, TierRules",
			function()
				for _, path in FILES do
					expect({ file = path, found = forbidden(fs.readFile(path)) }).toEqual({
						file = path,
						found = {},
					})
				end
			end
		)
	end)
end
