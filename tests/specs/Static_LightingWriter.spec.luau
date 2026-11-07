--!nocheck
-- Static_LightingWriter (lot B4, étape 2 ; docs/04 §27.7, N12 ; GDD v2.0 §11.3 ; décision D3 du plan B4) :
-- lecture du code du client (src/client et src/first), commentaires retirés, chaînes gardées.
--   1. Render/AmbienceDirector est le SEUL module qui nomme le service Lighting
--      (GetService / FindService("Lighting"), game.Lighting, game["Lighting"],
--      FindFirstChildOfClass / FindFirstChild("Lighting")) ;
--   2. il crée les effets sous leurs noms de la v1.3 (SquishyAtmosphere, SquishyBloom, SquishyColor,
--      SquishySky) ;
--   3. LightingController ne garde aucune écriture d'effet (ni TweenService, ni ClockTime, ni effets).
-- Le détecteur lui-même est vérifié sur des exemples (il doit voir chaque forme, et ignorer un
-- commentaire).
local fs = require("@lune/fs")
local LuauScan = require("../harness/LuauScan")

local ROOTS = { "src/client", "src/first" }
local DIRECTOR = "src/client/Render/AmbienceDirector.luau"
local CONTROLLER = "src/client/Controllers/LightingController.luau"

local function files(dir, out)
	out = out or {}
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			files(full, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, full)
		end
	end
	table.sort(out)
	return out
end

-- Formes qui nomment le service Lighting (chaînes "…" ou '…')
local PATTERNS = {
	"GetService%s*%(%s*[\"']Lighting[\"']%s*%)",
	"FindService%s*%(%s*[\"']Lighting[\"']%s*%)",
	"FindFirstChildOfClass%s*%(%s*[\"']Lighting[\"']%s*%)",
	"FindFirstChild%s*%(%s*[\"']Lighting[\"']",
	"WaitForChild%s*%(%s*[\"']Lighting[\"']",
	"game%s*%.%s*Lighting%f[^%w_]",
	"game%s*%[%s*[\"']Lighting[\"']%s*%]",
}

-- Lignes (numéros) d'un source qui nomment le service, commentaires retirés
local function hits(source: string): { number }
	local code = LuauScan.strip(source, true)
	local out = {}
	local n = 0
	for line in string.gmatch(code .. "\n", "(.-)\n") do
		n += 1
		for _, pattern in PATTERNS do
			if string.find(line, pattern) then
				table.insert(out, n)
				break
			end
		end
	end
	return out
end

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Static_LightingWriter", function()
		it("le détecteur voit chaque forme et ignore les commentaires", function()
			for _, sample in
				{
					'local L = game:GetService("Lighting")',
					"local L = game:GetService('Lighting')",
					'local L = game:FindService("Lighting")',
					'local L = game:FindFirstChildOfClass("Lighting")',
					'local L = game:FindFirstChild("Lighting")',
					'local L = game:WaitForChild("Lighting")',
					"local L = game.Lighting",
					'local L = game["Lighting"]',
					"game.Lighting.ClockTime = 0",
				}
			do
				expect({ sample = sample, n = #hits(sample) }).toEqual({ sample = sample, n = 1 })
			end
			for _, sample in
				{
					'-- game:GetService("Lighting")',
					'--[[ local L = game:GetService("Lighting") ]]',
					"local LightingController = require(x.LightingController)",
					"local s = Enum.LightingStyle.Soft",
					"local g = game.LightingThing",
				}
			do
				expect({ sample = sample, n = #hits(sample) }).toEqual({ sample = sample, n = 0 })
			end
		end)

		it("seul Render/AmbienceDirector nomme le service Lighting (src/client, src/first)", function()
			local found = {}
			local director = 0
			for _, root in ROOTS do
				for _, path in files(root) do
					local lines = hits(fs.readFile(path))
					if path == DIRECTOR then
						director = #lines
					else
						for _, line in lines do
							table.insert(found, path .. ":" .. line)
						end
					end
				end
			end
			expect(table.concat(found, "\n")).toBe("")
			expect(director).toBe(1)
		end)

		it("effets créés sous leurs noms de la v1.3 ; LightingController sans écriture d'effet", function()
			local director = LuauScan.strip(fs.readFile(DIRECTOR), true)
			for _, name in { "SquishyAtmosphere", "SquishyBloom", "SquishyColor", "SquishySky" } do
				expect({ name = name, ok = string.find(director, '"' .. name .. '"', 1, true) ~= nil }).toEqual({
					name = name,
					ok = true,
				})
			end
			local controller = LuauScan.strip(fs.readFile(CONTROLLER), true)
			for _, word in
				{
					"TweenService",
					"ClockTime",
					"SquishyAtmosphere",
					"SquishyBloom",
					"SquishyColor",
					"SquishySky",
					"LightingStyle",
					"PrioritizeLightingQuality",
				}
			do
				expect({ word = word, found = string.find(controller, word, 1, true) ~= nil }).toEqual({
					word = word,
					found = false,
				})
			end
		end)
	end)
end
