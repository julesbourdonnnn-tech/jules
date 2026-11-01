--!nocheck
-- Seuils de l'anti-triche côté serveur seulement (Comet Conga, restes serveur Q2) : un tricheur qui
-- connaît « 1,5 × vmax + 4 studs » règle sa triche juste en dessous. MoveCheck.Config est la table
-- Server/Movement/Tuning.MoveCheck (ServerScriptService, jamais répliquée), avec les valeurs
-- éprouvées par Comet Conga ; seules les bornes du monde dépendent de la carte du jeu.
local fs = require("@lune/fs")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	describe("MoveCheck › seuils côté serveur", function()
		it("MoveCheck.Config = Movement/Tuning.MoveCheck, valeurs éprouvées de Comet Conga", function()
			local h = Harness.new()
			local MC = h:require("ServerScriptService.Server.Util.MoveCheck")
			local Tuning = h:require("ServerScriptService.Server.Movement.Tuning")
			expect(MC.Config == Tuning.MoveCheck).toBe(true)
			local cfg = table.clone(MC.Config)
			-- bornes du monde : à régler sur la carte du jeu (vérifiées seulement en forme)
			expect(type(cfg.CenterX) == "number" and type(cfg.CenterZ) == "number").toBe(true)
			expect(cfg.MaxRadius > 0).toBe(true)
			cfg.CenterX, cfg.CenterZ, cfg.MaxRadius = nil, nil, nil
			expect(cfg).toEqual({
				Margin = 1.5,
				Slack = 4,
				SpeedWindow = 0.5,
				MaxClimbSpeed = 12,
				FlagsToRewind = 3,
				FlagWindow = 5,
				RewindLockout = 3,
				Exemption = 3,
				MaxAltitude = 14,
				AltitudeTime = 1.5,
				MinY = -5,
				StrikesForBan = 10,
				StrikeWindow = 600,
			})
			expect(Tuning.RootHeight).toBe(3)
			expect(Tuning.ActionReachY).toBe(4)
			expect(Tuning.HoverTime).toBe(1)
			expect(Tuning.MaxBelowGround).toBe(2)
			expect(Tuning.TickStep).toBe(0.1)
			expect(Tuning.MaxCatchUp).toBe(3)
			expect(Tuning.DefaultMaxSpeed >= 16).toBe(true)
		end)

		it("aucun module répliqué (src/shared, src/client, src/first) ne porte ces seuils", function()
			local offenders = {}
			local function walk(dir)
				if not fs.isDir(dir) then
					return
				end
				for _, name in fs.readDir(dir) do
					local path = dir .. "/" .. name
					if fs.isDir(path) then
						walk(path)
					elseif string.sub(name, -5) == ".luau" then
						local src = fs.readFile(path)
						for _, needle in
							{
								"StrikesForBan",
								"FlagsToRewind",
								"MaxClimbSpeed",
								"RewindLockout",
								"ActionReachY",
							}
						do
							if string.find(src, needle, 1, true) then
								table.insert(offenders, path .. " : " .. needle)
							end
						end
					end
				end
			end
			for _, root in { "src/shared", "src/client", "src/first" } do
				walk(root)
			end
			expect(offenders).toEqual({})
			-- et Tuning vit bien sous ServerScriptService (src/server)
			expect(fs.isFile("src/server/Movement/Tuning.luau")).toBe(true)
		end)
	end)
end
