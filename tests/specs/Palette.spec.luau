--!nocheck
-- Palette (paquet world, docs/04 §12.2, GDD §11.3) : préréglages d'éclairage aux valeurs du GDD
-- (jour pastel, BOOP RUSH, Jelly Moon, fêtes, hiver), copies neuves, mélange (Rush discret à 30 %),
-- calques d'événement, couleurs des ranchs et du Tapis à Goûter (13 aspects), entrées bizarres.
local roblox = require("@lune/roblox")

local Color3 = roblox.Color3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function load()
		local h = Harness.new()
		return h, h:require("ReplicatedStorage.Shared.Render.Palette")
	end

	local function rgb(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end

	describe("Palette › préréglages (GDD §11.3)", function()
		it(
			"jour pastel : ClockTime 14,5, Ambient, OutdoorAmbient, Brightness 2,5, Atmosphere, Bloom 0,6",
			function()
				local h, P = load()
				local day = P.preset("day")
				expect(day.clockTime).toBe(14.5)
				expect(rgb(day.ambient)).toEqual({ 150, 140, 170 })
				expect(rgb(day.outdoorAmbient)).toEqual({ 190, 180, 210 })
				expect(day.brightness).toBe(2.5)
				expect(rgb(day.atmosphereColor)).toEqual({ 255, 220, 240 })
				expect(day.bloom).toBe(0.6)
				expect(rgb(day.tint)).toEqual({ 255, 255, 255 })
				expect(#h.errors).toBe(0)
			end
		)

		it("BOOP RUSH, Jelly Moon, fêtes : valeurs du GDD", function()
			local _, P = load()
			local rush = P.preset("rush")
			expect(rgb(rush.tint)).toEqual({ 255, 200, 225 })
			expect(rgb(rush.atmosphereColor)).toEqual({ 255, 190, 220 })
			expect(rush.clockTime).toBe(14.5)
			local moon = P.preset("moon")
			expect(moon.clockTime).toBe(0)
			expect(moon.moonSize).toBe(30)
			expect(moon.starCount).toBe(4000)
			expect(rgb(moon.tint)).toEqual({ 200, 190, 255 })
			expect(rgb(moon.atmosphereColor)).toEqual({ 150, 120, 220 })
			local party = P.preset("party")
			expect(rgb(party.tint)).toEqual({ 255, 240, 210 })
			expect(party.bloom).toBe(0.8)
			local winter = P.preset("winter")
			expect(winter.clockTime).toBe(14.5)
		end)

		it("chaque préréglage est complet et fini ; nom inconnu ou bizarre : « day »", function()
			local _, P = load()
			for _, name in P.NAMES do
				local p = P.preset(name)
				for _, key in { "clockTime", "brightness", "bloom", "starCount", "moonSize" } do
					local v = p[key]
					expect({
						name = name,
						key = key,
						ok = type(v) == "number" and v == v and v >= 0 and v < 1e6,
					}).toEqual({
						name = name,
						key = key,
						ok = true,
					})
				end
				for _, key in { "ambient", "outdoorAmbient", "tint", "atmosphereColor" } do
					expect(typeof(p[key])).toBe("Color3")
				end
			end
			for _, bad in { "nope", "", nil, 42, {}, 0 / 0 } do
				expect(P.preset(bad)).toEqual(P.preset("day"))
			end
		end)

		it("chaque appel rend une copie neuve (un appelant ne peut pas abîmer la palette)", function()
			local _, P = load()
			local a = P.preset("moon")
			a.clockTime = 99
			a.tint = Color3.new(0, 0, 0)
			local b = P.preset("moon")
			expect(b.clockTime).toBe(0)
			expect(rgb(b.tint)).toEqual({ 200, 190, 255 })
		end)
	end)

	describe("Palette › mélange et calques", function()
		it("blend : 0 → a, 1 → b, 0,3 → 30 % ; alpha borné ; NaN → a", function()
			local _, P = load()
			local day, rush = P.preset("day"), P.preset("rush")
			expect(P.blend(day, rush, 0)).toEqual(day)
			expect(rgb(P.blend(day, rush, 1).tint)).toEqual({ 255, 200, 225 })
			local quiet = P.blend(day, rush, P.QuietRush)
			expect(P.QuietRush).toBe(0.3)
			expect(rgb(quiet.tint)).toEqual({
				255,
				math.floor(255 - 55 * 0.3 + 0.5),
				math.floor(255 - 30 * 0.3 + 0.5),
			})
			expect(rgb(P.blend(day, rush, 7).tint)).toEqual({ 255, 200, 225 })
			expect(rgb(P.blend(day, rush, -3).tint)).toEqual({ 255, 255, 255 })
			expect(rgb(P.blend(day, rush, 0 / 0).tint)).toEqual({ 255, 255, 255 })
			local mid = P.blend(day, P.preset("moon"), 0.5)
			expect(mid.clockTime).toBe(7.25)
			expect(mid.starCount).toBe(3500)
		end)

		it(
			"overlay : le Rush ne change que la teinte et l'atmosphère (la nuit de la Lune reste la nuit)",
			function()
				local _, P = load()
				local moon = P.preset("moon")
				local over = P.overlay(moon, "rush", 1)
				expect(over.clockTime).toBe(0)
				expect(over.moonSize).toBe(30)
				expect(rgb(over.tint)).toEqual({ 255, 200, 225 })
				local quiet = P.overlay(P.preset("day"), "rush", 0.3)
				expect(rgb(quiet.tint)).toEqual(rgb(P.blend(P.preset("day"), P.preset("rush"), 0.3).tint))
				local party = P.overlay(P.preset("day"), "party")
				expect(party.bloom).toBe(0.8)
				expect(rgb(party.tint)).toEqual({ 255, 240, 210 })
				expect(P.overlay(moon, "inconnu", 1)).toEqual(moon)
				expect(P.overlay(moon, "rush", 0 / 0).clockTime).toBe(0)
			end
		)
	end)

	describe("Palette › couleurs du monde", function()
		it(
			"ranchs : couleur du propriétaire (Config/Cosmetics.RanchColors), gris (130, 130, 140) si libre",
			function()
				local h, P = load()
				local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
				for slot = 1, 16 do
					expect(P.ranchColor(slot, true)).toBe(Cosmetics.RanchColors[slot])
					expect(rgb(P.ranchColor(slot, false))).toEqual({ 130, 130, 140 })
				end
				for _, bad in { 0, 17, 0 / 0, "3" } do
					expect(P.ranchColor(bad, true)).toBe(Cosmetics.FreeRanchColor)
				end
				expect(rgb(P.World.ground)).toEqual({ 200, 240, 210 })
				expect(rgb(P.World.plaza)).toEqual({ 255, 245, 220 })
				expect(rgb(P.World.street)).toEqual({ 255, 230, 240 })
				expect(#P.World.hills).toBe(3)
			end
		)

		it(
			"Tapis à Goûter : 13 aspects (niveaux 0 … 12), tous différents, biscuits croissants",
			function()
				local h, P = load()
				local Pads = h:require("ReplicatedStorage.Shared.Config.Pads")
				expect(P.SnackLooks).toBe(Pads.SnackLooks)
				local seen = {}
				local last = -1
				for level = 0, 12 do
					local look = P.snackLook(level)
					local key = table.concat(rgb(look.mat), ",") .. "/" .. table.concat(rgb(look.dots), ",")
					expect(seen[key]).toBeNil()
					seen[key] = true
					expect(look.count >= last).toBe(true)
					expect(look.count <= P.SnackDots).toBe(true)
					last = look.count
				end
				expect(P.snackLook(0).count).toBe(0)
				expect(P.snackLook(99)).toEqual(P.snackLook(12))
				for _, bad in { -5, 0 / 0, "7", nil, math.huge } do
					local look = P.snackLook(bad)
					expect(typeof(look.mat)).toBe("Color3")
				end
			end
		)
	end)
end
