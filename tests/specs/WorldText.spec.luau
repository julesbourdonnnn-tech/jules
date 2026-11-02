--!nocheck
-- WorldText (paquet client-hud ; docs/04 §13.5, contrat v1.2 ; GDD v1.3 §10.2) : textes du monde en
-- BillboardGui à pixels fixes (Offset × échelle de UI/Root), LightInfluence 0, fond foncé translucide,
-- taille projetée ≥ 28 px TV à 20 studs aux 3 résolutions, bornage des plaques à la zone sûre de 5 %,
-- réserve d'étiquettes (aucune création en rafale), entrées hostiles sans erreur. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		local h = TvAudit.client(opts)
		local WT = TvAudit.mod(h, "UI.WorldText")
		local L = h:require("ReplicatedStorage.Shared.Config.Layout")
		local part = h.globals.Instance.new("Part")
		part.Anchored = true
		part.Position = Vector3.new(0, 2, 0)
		part.Parent = h.game.Workspace
		return h, WT, L, part
	end

	describe("WorldText › étiquette", function()
		it(
			"BillboardGui en Offset × UIScale, LightInfluence 0, fond foncé translucide, MaxDistance",
			function()
				local h, WT, L, part = setup()
				local gui =
					WT.create(part, { kind = "text", maxDistance = 20, studsOffset = Vector3.new(0, 3, 0) })
				WT.setText(gui, "Tapis à Goûter · 1,2 K")
				expect(gui.ClassName).toBe("BillboardGui")
				expect(gui.Adornee).toBe(part)
				expect(gui.LightInfluence).toBe(0)
				expect(gui.MaxDistance).toBe(20)
				expect(gui.StudsOffsetWorldSpace).toEqual(Vector3.new(0, 3, 0))
				-- tailles en Offset seulement (jamais en studs : aucune part d'échelle)
				expect(gui.Size.X.Scale).toBe(0)
				expect(gui.Size.Y.Scale).toBe(0)
				local plate = gui:FindFirstChild("Plate")
				expect(plate.BackgroundTransparency).toBe(L.WorldText.Background)
				expect(plate.BackgroundTransparency <= 0.4).toBe(true) -- opacité ≥ 0,6
				local scale = plate:FindFirstChild("WorldScale")
				expect(scale.ClassName).toBe("UIScale")
				expect(scale.Scale).toBe(1) -- 1920 × 1080
				local label = plate:FindFirstChild("Text")
				expect(label.Text).toBe("Tapis à Goûter · 1,2 K")
				expect(label.TextSize).toBe(L.WorldText.Text)
				-- jamais dans PlayerGui : ce n'est pas un écran du HUD
				expect(gui:IsDescendantOf(h.localPlayer.PlayerGui)).toBe(false)
				expect(gui:IsDescendantOf(h.game.Workspace)).toBe(true)
				clean(h)
			end
		)

		it("tailles des sortes : texte 32, « +N » 40, glyphe 48 (Layout.WorldText)", function()
			local h, WT, L = setup()
			expect(WT.pixelSize("text")).toBe(L.WorldText.Text)
			expect(WT.pixelSize("plus")).toBe(L.WorldText.Plus)
			expect(WT.pixelSize("glyph")).toBe(L.WorldText.Glyph)
			expect(L.WorldText.Text >= 32 and L.WorldText.Plus >= 40 and L.WorldText.Glyph >= 48).toBe(true)
			clean(h)
		end)

		it(
			"taille projetée ≥ 28 px TV à 20 studs en 1920 × 1080, 3840 × 2160 et 1280 × 720",
			function()
				local h, WT, L, part = setup()
				local guis = {
					WT.create(part, { kind = "text", maxDistance = 20 }),
					WT.create(part, { kind = "plus", maxDistance = 30 }),
					WT.create(part, { kind = "glyph", maxDistance = 30 }),
				}
				WT.setText(guis[1], "Lv. 3 · 1,2 K")
				WT.setText(guis[2], "+1,2 K")
				WT.setGlyph(
					guis[3],
					{ gamepad = roblox.Enum.KeyCode.ButtonX, keyboard = roblox.Enum.KeyCode.E }
				)
				WT.setText(guis[3], "Presser")
				for _, res in L.TestResolutions do
					local vp = Vector2.new(res.X, res.Y)
					TvAudit.setResolution(h, vp)
					for _, gui in guis do
						-- étiquette visible à la distance d'essai (20 studs)
						expect(gui.MaxDistance >= L.WorldText.TestDistance).toBe(true)
						local px = WT.projectedPx(gui, vp)
						expect({ res = res.X, px = px >= L.WorldText.MinProjected }).toEqual({
							res = res.X,
							px = true,
						})
					end
					-- pixels d'écran du BillboardGui = plaque (px TV) × échelle de l'écran
					local s = math.max(0.5, math.min(res.X / 1920, res.Y / 1080))
					local plate = WT.plateSize(guis[1])
					expect(math.abs(guis[1].Size.X.Offset - math.ceil(plate.X * s)) <= 1).toBe(true)
				end
				clean(h)
			end
		)

		it(
			"une étiquette dont l'échelle n'a pas suivi l'écran serait trop petite : rescale la corrige",
			function()
				local h, WT, L, part = setup()
				local gui = WT.create(part, { kind = "text", maxDistance = 20 })
				WT.setText(gui, "Size 12")
				-- écran 4K sans rescale : on fausse l'échelle pour simuler un oubli
				gui:FindFirstChild("Plate"):FindFirstChild("WorldScale").Scale = 1
				gui.Size = roblox.UDim2.fromOffset(WT.plateSize(gui).X, WT.plateSize(gui).Y)
				local vp = Vector2.new(3840, 2160)
				h.viewport = vp
				expect(WT.projectedPx(gui, vp) < L.WorldText.MinProjected).toBe(true)
				TvAudit.setResolution(h, vp)
				WT.rescale()
				expect(WT.projectedPx(gui, vp) >= L.WorldText.MinProjected).toBe(true)
				expect(gui:FindFirstChild("Plate"):FindFirstChild("WorldScale").Scale).toBe(2)
				clean(h)
			end
		)
	end)

	describe("WorldText › zone sûre et réserve", function()
		it(
			"clampToSafe ramène une plaque dans la zone sûre de 5 % (et centre une plaque trop grande)",
			function()
				local h, WT = setup()
				local vp = Vector2.new(1920, 1080)
				local size = Vector2.new(300, 88)
				expect(WT.clampToSafe(Vector2.new(-200, -50), size, vp)).toEqual(Vector2.new(96, 54))
				expect(WT.clampToSafe(Vector2.new(1900, 1070), size, vp)).toEqual(
					Vector2.new(1824 - 300, 1026 - 88)
				)
				expect(WT.clampToSafe(Vector2.new(800, 500), size, vp)).toEqual(Vector2.new(800, 500))
				local big = WT.clampToSafe(Vector2.new(0, 0), Vector2.new(4000, 88), vp)
				expect(big.X).toBe((96 + (1824 - 4000)) / 2)
				-- 4K : 5 % de l'écran réel
				expect(WT.clampToSafe(Vector2.new(0, 0), size, Vector2.new(3840, 2160))).toEqual(
					Vector2.new(192, 108)
				)
				-- entrées hostiles : aucune erreur, résultat fini
				local r = WT.clampToSafe(Vector2.new(0 / 0, math.huge), size, vp)
				expect(r.X == r.X and r.Y == r.Y and r.X < math.huge).toBe(true)
				clean(h)
			end
		)

		it("réserve : une étiquette rendue est réutilisée, jamais une création en rafale", function()
			local h, WT, _, part = setup()
			local before = WT.stats()
			local guis = {}
			for i = 1, 20 do
				guis[i] = WT.create(part, { kind = "plus", maxDistance = 30 })
				WT.setText(guis[i], "+" .. i)
			end
			expect(WT.stats().live).toBe(before.live + 20)
			for _, gui in guis do
				WT.release(gui)
			end
			expect(WT.stats().live).toBe(before.live)
			expect(WT.stats().pooled >= 20).toBe(true)
			local reused = WT.create(part, { kind = "plus", maxDistance = 30 })
			local found = false
			for _, gui in guis do
				if gui == reused then
					found = true
				end
			end
			expect(found).toBe(true)
			expect(reused.Enabled).toBe(true)
			expect(reused:FindFirstChild("Plate"):FindFirstChild("Text").Text).toBe("")
			-- une étiquette rendue n'est plus modifiable (aucune erreur)
			WT.release(reused)
			WT.setText(reused, "x")
			WT.release(reused)
			clean(h)
		end)

		it("entrées hostiles : adornee absent, options bizarres, texte énorme ou non textuel", function()
			local h, WT, L = setup()
			local gui = WT.create(nil, { kind = "???", maxDistance = 0 / 0, studsOffset = "haut" })
			expect(gui.ClassName).toBe("BillboardGui")
			expect(gui.MaxDistance).toBe(L.WorldText.TestDistance)
			WT.setText(gui, string.rep("é", 5000))
			expect(#gui:FindFirstChild("Plate"):FindFirstChild("Text").Text <= 200).toBe(true)
			WT.setText(gui, 42)
			WT.setGlyph(gui, nil)
			WT.setTextSize(gui, -5)
			expect(gui:FindFirstChild("Plate"):FindFirstChild("Text").TextSize >= L.WorldText.Text).toBe(true)
			local g2 = WT.create(nil, nil)
			expect(g2.ClassName).toBe("BillboardGui")
			expect(WT.projectedPx(nil, Vector2.new(1920, 1080))).toBe(0)
			clean(h)
		end)

		it("API Roblox : chaque classe et propriété écrite existe (ApiAudit)", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, WT, _, part = setup()
				local gui =
					WT.create(part, { kind = "glyph", maxDistance = 20, alwaysOnTop = true, name = "Lesson" })
				WT.setGlyph(gui, { gamepad = roblox.Enum.KeyCode.ButtonB }, 64)
				WT.setText(gui, "Prendre")
				WT.setDim(gui, true)
				TvAudit.setResolution(h, Vector2.new(1280, 720))
				WT.release(gui)
				clean(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and "" or tostring(err)).toBe("")
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
