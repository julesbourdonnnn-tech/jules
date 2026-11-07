--!nocheck
-- Static_PrestigeOnly (paquet A1, GDD v2.0 §4.27, docs/04 §27.7) : Logic/Prestige est la SEULE source
-- de r, du Record R et de A. Aucune lecture du champ R du profil (x.R ou x["R"], hors commentaires et
-- chaînes ; appels x.R(…) et Enum.KeyCode.R exceptés) hors de Logic/Prestige et de Data/Schema,
-- sauf la liste FERMÉE des modules de la v1.3 ci-dessous, que le lot A2 (et A1 pour Formulas,
-- QuestRules, Invariants) fait passer par Prestige.r / Prestige.bestR. La liste ne fait que
-- rétrécir : un fichier nouveau qui lit .R échoue, un compte qui monte échoue, et une exception
-- périmée (compte qui baisse ou fichier qui n'en a plus) échoue aussi : mettre la liste à jour dans
-- le même lot. Avec l'interrupteur RecordR, tout ce qui est « débloqué » lit le Record R (N1).
local fs = require("@lune/fs")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local LuauScan = require("../harness/LuauScan")

	-- Seuls lecteurs permis
	local ALLOWED = {
		["src/shared/Logic/Prestige.luau"] = true,
		["src/server/Data/Schema.luau"] = true,
	}

	-- Liste fermée des lectures de la v1.3 (fichier → nombre exact), à faire passer par Prestige
	local LEGACY = {
		["src/client/Controllers/RanchRenderer.luau"] = 1, -- ranch.R public (B4 : panneau par BestR / Prestige.r, reste le coût des dalles)
		["src/server/Ranch/PadRules.luau"] = 1, -- A2
		["src/server/Services/EconomyService.luau"] = 9, -- A2
		["src/server/Services/RanchService.luau"] = 2, -- A2
		["src/shared/Logic/Formulas.luau"] = 2, -- A1 (contexte de croissance, aperçu du Grand Splorch)
		["src/shared/Logic/Invariants.luau"] = 1, -- A1 (invariants v2)
		["src/shared/Logic/QuestRules.luau"] = 2, -- A1 (contexte des objectifs)
	}

	-- Receveurs qui ne sont jamais un profil
	local NOT_PROFILE = { KeyCode = true }

	-- Lectures de .R dans un source : liste de « ligne : extrait »
	local function reads(src)
		local code = LuauScan.strip(src, false)
		local found = {}
		local pos = 1
		while true do
			local s, e, recv = string.find(code, "([%w_]+)%s*%.%s*R%f[^%w_]", pos)
			if s == nil then
				break
			end
			local after = string.match(code, "^%s*(.)", e + 1)
			if after ~= "(" and not NOT_PROFILE[recv] then
				table.insert(found, LuauScan.lineOf(code, s) .. " : " .. string.sub(code, s, e))
			end
			pos = e + 1
		end
		-- x["R"] (les chaînes sont gardées pour cette recherche)
		local withStrings = LuauScan.strip(src, true)
		for _ in string.gmatch(withStrings, "%[%s*[\"']R[\"']%s*%]") do
			table.insert(found, '["R"]')
		end
		return found
	end

	describe("Static_PrestigeOnly", function()
		it(
			'le lecteur trouve data.R, d ["R"], profile . R ; ignore les appels, Enum.KeyCode.R, commentaires et chaînes',
			function()
				expect(#reads("local a = data.R")).toBe(1)
				expect(#reads("local a = d[\"R\"] + p[ 'R' ]")).toBe(2)
				expect(#reads("local a = profile . R")).toBe(1)
				expect(#reads("data.R = 3")).toBe(1)
				expect(#reads("local a = EconomyService.R(player)")).toBe(0)
				expect(#reads("function EconomyService.R (player) end")).toBe(0)
				expect(#reads("local k = Enum.KeyCode.R")).toBe(0)
				expect(#reads('-- data.R\nlocal s = "data.R"\nlocal t = data.RScale + data.Rx')).toBe(0)
			end
		)

		it(
			"aucune lecture de profile.R hors de Prestige et Schema, sauf la liste fermée de la v1.3 (comptes exacts)",
			function()
				local seen = {}
				for _, path in LuauScan.files(fs, "src") do
					if not ALLOWED[path] then
						local found = reads(fs.readFile(path))
						local n = #found
						if n > 0 or LEGACY[path] then
							seen[path] = true
							expect({
								file = path,
								reads = n,
								lines = if n ~= (LEGACY[path] or 0) then found else nil,
							}).toEqual({
								file = path,
								reads = LEGACY[path] or 0,
								lines = nil,
							})
						end
					end
				end
				-- une exception de la liste qui n'existe plus (fichier supprimé ou renommé) est périmée
				for path in LEGACY do
					expect({ file = path, listed = seen[path] == true }).toEqual({
						file = path,
						listed = true,
					})
				end
			end
		)

		it("les modules nouveaux de la v2.0 lisent r, Record R et A par Prestige seulement", function()
			for _, path in
				{
					"src/shared/Logic/UpgradeMath.luau",
					"src/shared/Logic/UpgradeAdvisor.luau",
					"src/shared/Logic/TierRules.luau",
					"src/shared/Logic/Bitset.luau",
				}
			do
				expect({ file = path, found = reads(fs.readFile(path)) }).toEqual({ file = path, found = {} })
				-- ni champ bestR ni ascend lu directement (Prestige.bestR(…) et Prestige.ascend(…) seulement ;
				-- rule.ascend / open.ascend : condition d'ouverture de Config/Upgrades, pas le profil)
				local CONFIG = { rule = true, open = true }
				local code = LuauScan.strip(fs.readFile(path), false)
				for _, field in { "bestR", "ascend" } do
					for recv, after in string.gmatch(code, "([%w_]+)%s*%.%s*" .. field .. "%f[^%w_]%s*(.?)") do
						expect({
							file = path,
							read = recv .. "." .. field,
							ok = (recv == "Prestige" and after == "(") or CONFIG[recv] == true,
						}).toEqual({
							file = path,
							read = recv .. "." .. field,
							ok = true,
						})
					end
				end
			end
		end)
	end)
end
