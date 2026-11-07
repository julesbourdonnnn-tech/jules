--!nocheck
-- RanchRenderer_v2_designs (lot B4, étape 4 ; GDD v2.0 §11.5 ; décisions D6, D8, D15, D17, D18,
-- D18b du plan B4) : les dessins PURS des décors v2.0 (Render/RanchTiers, Render/MonumentKit,
-- Render/DecoKit) tiennent leurs promesses, pour les 16 ranchs :
--   * paliers : 12, 14, 18, 16, 14, 12 pièces (étoiles 1 chacune), détail réduit 3 pièces pour la tour,
--     le phare et la couronne (9 au plus) ; chaque pièce dans l'emprise WorldLayout de son palier ;
--   * éléments du Record R dans leurs emprises (geyser, maisonnette, lampions) ; « record » ≤ 40 par
--     ranch ; accessoires de la silhouette autour d'elle (rayon r + 1 au moins) ;
--   * 10 Monuments : ≤ 20 / 6 / 1 pièces, ≤ 18 studs, rayon ≤ 6 ;
--   * 40 objets de Déco perso : ≤ 10 pièces, petits dans 2,5 × 2,5, grands dans 4,5 × 4,5, silhouette
--     d'une pièce pour les grands seulement ;
--   * rien de la v2 au-dessus de Y = 21 dans la colonne du centre, sauf les accessoires ;
--   * pièces conformes (ancrées, sans collision ni requête ni toucher ni ombre, opaques, matériaux
--     SmoothPlastic, Neon, Foil, Ice).

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local EPS = 0.02

	local function mods()
		local h = Harness.new({ mode = "client", console = true })
		return {
			h = h,
			WL = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Kit = h:require(CLIENT .. "Render.RanchKit"),
			Tiers = h:require(CLIENT .. "Render.RanchTiers"),
			Mon = h:require(CLIENT .. "Render.MonumentKit"),
			Deco = h:require(CLIENT .. "Render.DecoKit"),
			Cos = h:require("ReplicatedStorage.Shared.Config.Cosmetics"),
		}
	end

	-- Points extrêmes d'une spec (bloc : 8 coins ; boule : centre ± rayon ; cylindre : 2 cercles de 32
	-- points) en monde
	local function points(spec)
		local out = {}
		local cf, size = spec.cf, spec.size
		if spec.shape == "Ball" then
			local r = size.X / 2
			local c = cf.Position
			for _, d in
				{
					Vector3.new(r, 0, 0),
					Vector3.new(-r, 0, 0),
					Vector3.new(0, r, 0),
					Vector3.new(0, -r, 0),
					Vector3.new(0, 0, r),
					Vector3.new(0, 0, -r),
				}
			do
				table.insert(out, c + d)
			end
			-- points diagonaux horizontaux (rayon horizontal exact)
			for k = 0, 15 do
				local a = 2 * math.pi * k / 16
				table.insert(out, c + Vector3.new(r * math.cos(a), 0, r * math.sin(a)))
			end
		elseif spec.shape == "Cylinder" then
			local len, r = size.X / 2, size.Y / 2
			for _, sx in { -len, len } do
				for k = 0, 31 do
					local a = 2 * math.pi * k / 32
					table.insert(out, (cf * CFrame.new(sx, r * math.cos(a), r * math.sin(a))).Position)
				end
			end
		else
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(
							out,
							(cf * CFrame.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)).Position
						)
					end
				end
			end
		end
		return out
	end

	-- Plus grande distance horizontale à l'origine du repère `base` et bornes en Y (repère local)
	local function extent(specs, base)
		local rmax, ymin, ymax = 0, math.huge, -math.huge
		for _, spec in specs do
			for _, p in points(spec) do
				local l = base:PointToObjectSpace(p)
				rmax = math.max(rmax, math.sqrt(l.X * l.X + l.Z * l.Z))
				ymin = math.min(ymin, l.Y)
				ymax = math.max(ymax, l.Y)
			end
		end
		return rmax, ymin, ymax
	end

	local function footprint(WL, name)
		for _, f in WL.v2Footprints() do
			if f.name == name then
				return f
			end
		end
		return nil
	end

	-- Tous les points des specs dans l'emprise f (repère local du ranch)
	local function inside(m, slot, specs, f)
		for _, spec in specs do
			for _, p in points(spec) do
				local l = m.WL.toLocal(slot, p)
				if l.Y < f.bottom - EPS or l.Y > f.top + EPS then
					return spec.key .. " Y " .. l.Y .. " hors de " .. f.bottom .. " … " .. f.top
				end
				if f.kind == "disc" then
					local d = math.sqrt((l.X - f.x) ^ 2 + (l.Z - f.z) ^ 2)
					if d > f.r + EPS then
						return spec.key .. " à " .. d .. " du centre de " .. f.name .. " (r " .. f.r .. ")"
					end
				elseif l.X < f.x0 - EPS or l.X > f.x1 + EPS or l.Z < f.z0 - EPS or l.Z > f.z1 + EPS then
					return spec.key .. " (" .. l.X .. ", " .. l.Z .. ") hors de " .. f.name
				end
			end
		end
		return "ok"
	end

	local STATE = { color = roblox.Color3.fromRGB(255, 130, 120), ready = true, stars = 4, rainbow = true }
	local NAMES = { "arch", "tower", "balcony", "lighthouse", "dome", "crown" }

	describe("RanchRenderer_v2_designs › paliers du ranch", function()
		it("pièces du GDD §11.5 (12, 14, 18, 16, 14, 12 ; étoiles 1 chacune), réduit 3 × 3", function()
			local m = mods()
			local full = { 12, 14, 18, 16, 14, 12 }
			for k = 1, 6 do
				local s = table.clone(STATE)
				s.stars = 0
				expect(#m.Tiers.tier(5, k, s)).toBe(full[k])
				expect(#m.Tiers.tierReduced(5, k, s)).toBe(if k == 2 or k == 4 or k == 6 then 3 else 0)
				expect(m.Tiers.TIER_PARTS[k]).toBe(full[k])
			end
			for stars = 0, 4 do
				local s = table.clone(STATE)
				s.stars = stars
				expect(#m.Tiers.tier(5, 6, s)).toBe(12 + stars)
			end
			-- budget « tiers » : 3 × 96 + 13 × 9 ; un ranch complet au maximum : 86 + 4 ≤ 96
			local sum = 0
			for k = 1, 6 do
				sum += full[k]
			end
			expect(sum + 4 <= 96).toBe(true)
			expect(m.Tiers.REDUCED_PARTS[2] + m.Tiers.REDUCED_PARTS[4] + m.Tiers.REDUCED_PARTS[6] <= 9).toBe(
				true
			)
		end)

		it("chaque palier (complet et réduit) dans son emprise WorldLayout, pour les 16 ranchs", function()
			local m = mods()
			for slot = 1, 16 do
				for k = 1, 6 do
					local f = footprint(m.WL, NAMES[k])
					expect(f ~= nil).toBe(true)
					expect(inside(m, slot, m.Tiers.tier(slot, k, STATE), f)).toBe("ok")
					expect(inside(m, slot, m.Tiers.tierReduced(slot, k, STATE), f)).toBe("ok")
				end
			end
		end)

		it(
			"hauteurs du GDD : arche Y 9 à 13, tour 16 (+ drapeau), phare 22, dôme Y 16, couronne Y 18",
			function()
				local m = mods()
				local base = m.WL.ranchCFrame(1)
				local function yr(specs)
					local _, ymin, ymax = extent(specs, base)
					return ymin, ymax
				end
				local a0, a1 = yr(m.Tiers.tier(1, 1, STATE))
				expect(a0 >= 9 - EPS and a1 <= 13 + EPS).toBe(true)
				local _, t1 = yr(m.Tiers.tier(1, 2, STATE))
				expect(t1 >= 16 and t1 <= 19 + EPS).toBe(true)
				local _, l1 = yr(m.Tiers.tier(1, 4, STATE))
				expect(math.abs(l1 - 22) < 0.05).toBe(true)
				local d0 = yr(m.Tiers.tier(1, 5, STATE))
				expect(d0 >= 16 - EPS).toBe(true)
				local c0 = yr(m.Tiers.tier(1, 6, STATE))
				expect(c0 >= 17 - EPS).toBe(true)
			end
		)
	end)

	describe("RanchRenderer_v2_designs › éléments du Record R et accessoires", function()
		it("geyser, maisonnette et lampions dans leurs emprises ; « record » ≤ 40 par ranch", function()
			local m = mods()
			for slot = 1, 16 do
				expect(inside(m, slot, m.Tiers.geyser(slot), footprint(m.WL, "geyser"))).toBe("ok")
				expect(inside(m, slot, m.Tiers.house(slot), footprint(m.WL, "house"))).toBe("ok")
				local lanterns = m.Tiers.lanterns(slot, true)
				expect(#lanterns).toBe(8)
				for i, spec in lanterns do
					expect(inside(m, slot, { spec }, footprint(m.WL, "lantern" .. i))).toBe("ok")
				end
				expect(#m.Tiers.house(slot)).toBe(6)
			end
			local vat = { rings = 8, nozzles = 5, period = 1, rainbow = true, golden = true }
			expect(#m.Tiers.vat(3, vat)).toBe(m.Tiers.vatCount(vat))
			local record = m.Tiers.vatCount(vat)
				+ #m.Tiers.fountain(3)
				+ #m.Tiers.lanterns(3, false)
				+ #m.Tiers.rainbowGate(3)
				+ #m.Tiers.geyser(3)
			expect(record <= 40).toBe(true)
			expect(#m.Tiers.rainbowGate(3)).toBe(7)
			expect(#m.Tiers.fountain(3)).toBe(3)
			-- buses de la Cuve (hors de son corps), jets du Bassin, geyser, maisonnette : à 8 studs au moins
			-- du centre de chaque prise de dalle (6 studs de son bord, prise réservée comprise) ; anneaux et
			-- agitateur restent dans le corps de la Cuve de la v1.3 (Ø 7)
			for slot = 1, 16 do
				local specs = {}
				for _, list in
					{
						m.Tiers.vat(slot, vat),
						m.Tiers.fountain(slot),
						m.Tiers.geyser(slot),
						m.Tiers.house(slot),
					}
				do
					for _, sp in list do
						if string.sub(sp.key, 1, 3) ~= "vat" or string.sub(sp.key, 1, 9) == "vatNozzle" then
							table.insert(specs, sp)
						end
					end
				end
				for socket = 1, 5 do
					local pad = m.WL.toLocal(slot, m.WL.padSocket(slot, socket))
					for _, spec in specs do
						for _, p in points(spec) do
							local l = m.WL.toLocal(slot, p)
							local d = math.sqrt((l.X - pad.X) ^ 2 + (l.Z - pad.Z) ^ 2)
							if d < m.WL.Const.PadClearance - EPS then
								expect(spec.key .. " à " .. d .. " de la prise " .. socket).toBe(
									"≥ 8 studs"
								)
							end
						end
					end
				end
			end
		end)

		it(
			"cadre, anneau « prêt » et anneau-soleil autour de la silhouette (≥ r + 1), 8 / 8 / 9 pièces",
			function()
				local m = mods()
				for _, r in { 2, 8, 19 } do
					local base = m.WL.v2Anchor(4, "frame")
					for _, case in
						{
							{ m.Tiers.frame(4, r), 8 },
							{ m.Tiers.readyRing(4, r), 8 },
							{ m.Tiers.sunRing(4, r), 9 },
						}
					do
						local specs, n = case[1], case[2]
						expect(#specs).toBe(n)
						-- aucune pièce ne traverse le disque de la silhouette (rayon r) dans son plan
						for _, spec in specs do
							if spec.key ~= "sunDisc" then
								local l = base:PointToObjectSpace(spec.cf.Position)
								expect(math.sqrt(l.X * l.X + l.Y * l.Y) >= r + 1 - EPS).toBe(true)
							end
						end
					end
				end
				expect(m.Tiers.quantize(0)).toBe(0)
				expect(m.Tiers.quantize(3.1)).toBe(4)
				expect(m.Tiers.quantize(40)).toBe(m.WL.Const.SilhouetteRadius)
				expect(m.Tiers.quantize(0 / 0)).toBe(0)
			end
		)

		it("colonne du centre : rien au-dessus de Y = 21 sauf les accessoires de la silhouette", function()
			local m = mods()
			local col = m.WL.centerColumn()
			for slot = 1, 16 do
				local specs = {}
				for k = 1, 6 do
					for _, s in m.Tiers.tier(slot, k, STATE) do
						table.insert(specs, s)
					end
				end
				local vat = { rings = 8, nozzles = 5, period = 1, rainbow = true, golden = true }
				for _, list in
					{
						m.Tiers.vat(slot, vat),
						m.Tiers.fountain(slot),
						m.Tiers.lanterns(slot, true),
						m.Tiers.rainbowGate(slot),
						m.Tiers.geyser(slot),
						m.Tiers.house(slot),
					}
				do
					for _, s in list do
						table.insert(specs, s)
					end
				end
				for _, spec in specs do
					for _, p in points(spec) do
						local l = m.WL.toLocal(slot, p)
						local d = math.sqrt((l.X - col.center.X) ^ 2 + (l.Z - col.center.Z) ^ 2)
						if d <= col.radius then
							expect(l.Y <= 21 + EPS).toBe(true)
						end
					end
				end
			end
		end)
	end)

	describe("RanchRenderer_v2_designs › Monuments et Déco perso", function()
		it("10 Monuments : ≤ 20 / 6 / 1 pièces, ≤ 18 studs, rayon ≤ 6, au sol", function()
			local m = mods()
			expect(m.Mon.COUNT).toBe(10)
			for n = 1, 10 do
				for level, max in { full = 20, near = 6, reduced = 1 } do
					local specs = m.Mon.specs(2, n, level)
					expect(#specs >= 1 and #specs <= max).toBe(true)
					expect(m.Mon.count(n, level)).toBe(#specs)
					local r, ymin, ymax = extent(specs, m.WL.monumentSlot(2, n))
					if
						r > m.WL.Const.MonumentRadius + EPS
						or ymax > m.WL.Const.MonumentTop + EPS
						or ymin < -EPS
					then
						expect(
							"monument " .. n .. " " .. level .. " r " .. r .. " y " .. ymin .. " … " .. ymax
						).toBe("dans son emprise")
					end
				end
				-- le budget « monuments » : 20 au plus (courant), 6 (voisins), 1 (les autres)
				expect(m.Mon.count(n, "full")).toBe(20)
				expect(m.Mon.count(n, "near")).toBe(6)
				expect(m.Mon.count(n, "reduced")).toBe(1)
			end
			expect(#m.Mon.specs(2, 11, "full")).toBe(0)
			expect(#m.Mon.specs(2, 1, "nope")).toBe(0)
		end)

		it(
			"40 objets de Déco perso : ≤ 10 pièces, dans leur taille ; silhouette pour les grands seulement",
			function()
				local m = mods()
				expect(#m.Cos.DecoPerso).toBe(40)
				for n = 1, 40 do
					local def = m.Cos.DecoPerso[n]
					local rows, far, size = m.Deco.rows(n)
					expect(size).toBe(def.size)
					expect(#rows >= 3 and #rows <= 10).toBe(true)
					local slot = if def.size == "G" then 9 else 1
					local base = m.WL.decoPersoSlot(6, slot)
					local specs = m.Deco.specs(6, slot, n, "full")
					expect(#specs).toBe(#rows)
					local limit = if def.size == "G" then 4.5 else 2.5
					local r, ymin, ymax = extent(specs, base)
					if r > limit / 2 + EPS or ymax > limit + EPS or ymin < -EPS then
						expect(def.id .. " r " .. r .. " y " .. ymin .. " … " .. ymax).toBe(
							"dans sa taille"
						)
					end
					local reduced = m.Deco.specs(6, slot, n, "reduced")
					if def.size == "G" then
						expect(far ~= nil).toBe(true)
						expect(#reduced).toBe(1)
						local fr, f0, f1 = extent(reduced, base)
						expect(fr <= limit / 2 + EPS and f0 >= -EPS and f1 <= limit + EPS).toBe(true)
					else
						expect(#reduced).toBe(0)
					end
				end
				-- numéro inconnu : rien
				expect(#m.Deco.specs(6, 1, 41, "full")).toBe(0)
				expect(#m.Deco.specs(6, 1, 0, "full")).toBe(0)
				expect(m.Deco.count(99, "full")).toBe(0)
			end
		)

		it(
			"pièces conformes : formes et matériaux permis, tailles positives, clés uniques par dessin",
			function()
				local m = mods()
				local allowed = { SmoothPlastic = true, Neon = true, Foil = true, Ice = true }
				local all = {}
				for k = 1, 6 do
					table.insert(all, m.Tiers.tier(7, k, STATE))
					table.insert(all, m.Tiers.tierReduced(7, k, STATE))
				end
				for n = 1, 10 do
					for _, level in { "full", "near", "reduced" } do
						table.insert(all, m.Mon.specs(7, n, level))
					end
				end
				for n = 1, 40 do
					table.insert(
						all,
						m.Deco.specs(7, if m.Cos.DecoPerso[n].size == "G" then 10 else 2, n, "full")
					)
				end
				table.insert(
					all,
					m.Tiers.vat(7, { rings = 8, nozzles = 5, period = 1, rainbow = true, golden = false })
				)
				table.insert(all, m.Tiers.frame(7, 10))
				table.insert(all, m.Tiers.readyRing(7, 10))
				table.insert(all, m.Tiers.sunRing(7, 10))
				for _, specs in all do
					local keys = {}
					for _, spec in specs do
						expect(keys[spec.key]).toBe(nil)
						keys[spec.key] = true
						expect(allowed[spec.material.Name]).toBe(true)
						expect(spec.size.X > 0 and spec.size.Y > 0 and spec.size.Z > 0).toBe(true)
						expect(spec.shape == "Block" or spec.shape == "Ball" or spec.shape == "Cylinder").toBe(
							true
						)
					end
				end
			end
		)
	end)
end
