--!nocheck
-- RanchLook (lot B4, étape 1 ; décisions D6, D7, D11, D14, D18 du plan B4 ; GDD v2.0 §4.27, §4.29,
-- §11.5) : règles pures de l'aspect du ranch qui évolue.
--   * elements : chaque Record R de 1 à 20 ajoute au moins un élément ; sans doublon, dans l'ordre de
--     la table ; étoiles de la couronne (25, 30, 35, 40), couronne arc-en-ciel (50), ciel (A) ;
--   * paliers, Cuve (accord avec Formulas.vatLevel), Pot, Tapis, socles (jamais construit et socle à la
--     fois, sur les 19 valeurs de tiles.decor), fanions, coussins, halo, ciel ;
--   * habillages : les 3 de la v1.3 rendent exactement les couleurs de RanchRenderer ; les 11 de la v2.0
--     ont une ligne complète (matériaux permis, jamais Glass) ; inconnu → nil ;
--   * decoPerso : 12 numéros sûrs (inconnu, mauvaise taille, doublon → 0) ;
--   * currentRanch / detail : un robot qui traverse son ranch ne fait changer de détail aucun ranch ;
--   * padLabel = Server/Ranch/PadRules sur 2 400 profils tirés (v1 et v2, StarMat ouvert et coupé) ;
--   * entrées hostiles : jamais d'erreur, valeurs finies ; zéro trace.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local L = "ReplicatedStorage.Shared."
	-- Recette SchemaV2 de DataChaos : interrupteur figé ouvert dans CE harnais avant le schéma
	local h = Harness.new()
	h:require(L .. "Config.Features").Defaults.SchemaV2 = true
	local RanchLook = h:require(L .. "Logic.RanchLook")
	local Visuals = h:require(L .. "Config.Visuals")
	local Cosmetics = h:require(L .. "Config.Cosmetics")
	local Formulas = h:require(L .. "Logic.Formulas")
	local Prestige = h:require(L .. "Logic.Prestige")
	local UpgradeMath = h:require(L .. "Logic.UpgradeMath")
	local WorldLayout = h:require(L .. "Logic.WorldLayout")
	local Features = h:require(L .. "Config.Features")
	local PadRules = h:require("ServerScriptService.Server.Ranch.PadRules")
	local Schema = h:require("ServerScriptService.Server.Data.Schema")

	local Hash = h:require(L .. "Logic.Hash")

	local HOSTILE = { 0 / 0, math.huge, -math.huge, -5, 1e300, "3", {}, true, false }

	-- Hasard contrôlé (Hash.stream, xorshift32 graine fixe) avec l'interface de Random
	local function newRng(seed)
		local s = Hash.stream(seed)
		return {
			NextNumber = function(_, a, b)
				if a == nil then
					return s:next()
				end
				return s:range(a, b)
			end,
			NextInteger = function(_, a, b)
				return s:int(a, b)
			end,
		}
	end

	local function contains(list, value)
		return table.find(list, value) ~= nil
	end

	describe("RanchLook › éléments et paliers", function()
		it(
			"Record R 0 et A 0 : aucun élément ; chaque Record R de 1 à 20 en ajoute au moins un",
			function()
				expect(#RanchLook.elements(0, 0)).toBe(0)
				local before = {}
				for R = 1, 20 do
					local now = RanchLook.elements(R, 0)
					local added = 0
					for _, id in now do
						if not contains(before, id) then
							added += 1
						end
					end
					expect({ R = R, added = added >= 1 }).toEqual({ R = R, added = true })
					-- jamais un élément perdu en montant
					for _, id in before do
						expect(contains(now, id)).toBe(true)
					end
					before = now
				end
			end
		)

		it(
			"ordre de la table, sans doublon : pen.cushion une seule fois, les 6 paliers au Record R 20",
			function()
				local list = RanchLook.elements(20, 0)
				local expected, seen = {}, {}
				for R = 1, 20 do
					for _, id in Visuals.RecordTable[R].ranch do
						if not seen[id] then
							seen[id] = true
							table.insert(expected, id)
						end
					end
				end
				expect(list).toEqual(expected)
				local count = 0
				for _, id in list do
					if id == "pen.cushion" then
						count += 1
					end
				end
				expect(count).toBe(1)
				for _, id in
					{
						"tier1.pompomArch",
						"tier2.candyTower",
						"tier3.jellyBalcony",
						"tier4.jellyLighthouse",
						"tier5.neonDome",
						"tier6.floatingCrown",
					}
				do
					expect(contains(list, id)).toBe(true)
				end
			end
		)

		it("étoiles de la couronne à 25, 30, 35, 40, couronne arc-en-ciel à 50, puis le ciel", function()
			local function tail(R, A)
				local all = RanchLook.elements(R, A)
				local base = #RanchLook.elements(20, 0)
				return { table.unpack(all, base + 1) }
			end
			expect(tail(24, 0)).toEqual({})
			expect(tail(25, 0)).toEqual({ "crown.star1" })
			expect(tail(39, 0)).toEqual({ "crown.star1", "crown.star2", "crown.star3" })
			expect(tail(49, 0)).toEqual({ "crown.star1", "crown.star2", "crown.star3", "crown.star4" })
			expect(tail(50, 0)).toEqual({
				"crown.star1",
				"crown.star2",
				"crown.star3",
				"crown.star4",
				"crown.rainbow",
			})
			expect(tail(20, 1)).toEqual({ "sky.1" })
			expect(tail(20, 10)).toEqual({ "sky.10" })
			expect(tail(20, 11)).toEqual({ "sky.10", "sky.stars" })
			expect(tail(20, 60)).toEqual({ "sky.10", "sky.stars" })
			expect(RanchLook.elements(0, 3)).toEqual({ "sky.3" })
		end)

		it("paliers 0 … 6 aux Record R 1, 3, 5, 10, 15, 20 (Visuals.RanchTiersAt)", function()
			local expected = { [0] = 0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6 }
			for R = 0, 20 do
				expect({ R = R, tier = RanchLook.tier(R) }).toEqual({ R = R, tier = expected[R] })
			end
			expect(RanchLook.tier(400)).toBe(6)
		end)

		it("Cuve : anneaux, buses, agitateur ; d'accord avec Formulas.vatLevel (qualité, buses)", function()
			local rows = {
				[0] = { 1, 0, 4, false, false },
				{ 2, 1, 4, false, false },
				{ 3, 2, 2, false, false },
				{ 4, 3, 2, false, false },
				{ 5, 4, 1, true, false },
				{ 6, 5, 1, true, false },
				{ 7, 5, 1, true, false },
				{ 8, 5, 1, true, true },
			}
			for R = 0, 7 do
				local v = RanchLook.vat(R)
				local e = rows[R]
				expect({ R = R, v = { v.rings, v.nozzles, v.stirrerPeriod, v.rainbow, v.golden } }).toEqual({
					R = R,
					v = e,
				})
			end
			for R = 0, 30 do
				local v, f = RanchLook.vat(R), Formulas.vatLevel(R)
				expect({ R = R, rings = v.rings, nozzles = v.nozzles }).toEqual({
					R = R,
					rings = f.quality,
					nozzles = f.nozzles,
				})
			end
		end)

		it(
			"Pot : cuivre, argent (R2), doré (R6), cristal (R16) ; 4 tas selon les secondes de revenu",
			function()
				local mat = {}
				for R = 0, 17 do
					mat[R] = RanchLook.potMaterial(R)
				end
				expect({ mat[0], mat[1], mat[2], mat[5], mat[6], mat[15], mat[16], mat[17] }).toEqual({
					"copper",
					"copper",
					"silver",
					"silver",
					"gold",
					"gold",
					"crystal",
					"crystal",
				})
				local cases = {
					{ 0, 0 },
					{ 29.99, 0 },
					{ 30, 1 },
					{ 119.99, 1 },
					{ 120, 2 },
					{ 600, 2 },
					{ 600.01, 3 },
					{ 1e9, 3 },
					{ -4, 0 },
				}
				for _, c in cases do
					expect({ s = c[1], state = RanchLook.potState(c[1]) }).toEqual({ s = c[1], state = c[2] })
				end
			end
		)

		it("Tapis : 6 paliers (1, 4, 7, 10, 13, 17) ; + 8 % par niveau dans son palier", function()
			local tiers = { [0] = 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6 }
			local shades = { [0] = 0, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 3, 0, 1, 2, 3 }
			for l = 0, 20 do
				expect({ l = l, tier = RanchLook.tapisTier(l) }).toEqual({ l = l, tier = tiers[l] })
				expect(RanchLook.tapisShade(l)).toBeNear(0.08 * shades[l], 1e-9)
			end
			expect(RanchLook.tapisTier(99)).toBe(6)
			expect(RanchLook.tapisShade(99)).toBeNear(0.24, 1e-9)
		end)

		it(
			"socles : décoration k construite si tiles.decor ≥ k, sinon socle (R ≥ 1) ; jamais les deux (19 valeurs)",
			function()
				for decor = 0, 18 do
					for _, R in { 0, 1, 7, 400 } do
						local built, plinths, none = 0, 0, 0
						for k = 1, 18 do
							local s = RanchLook.decorState(k, decor, R)
							if s == "built" then
								built += 1
								expect(decor >= k).toBe(true)
							elseif s == "plinth" then
								plinths += 1
								expect(decor < k and R >= 1).toBe(true)
							else
								expect(s).toBe("none")
								none += 1
								expect(decor < k and R == 0).toBe(true)
							end
						end
						expect(built).toBe(decor)
						expect(plinths).toBe(if R >= 1 then 18 - decor else 0)
						expect(built + plinths + none).toBe(18)
					end
				end
				for _, k in { 0, 19, 0.5, 18.5 + 0.5 } do
					expect(RanchLook.decorState(k, 18, 5)).toBe("none")
				end
			end
		)

		-- Lot I, étape 2 (D15, journal I-16) : KeptDecor (décorations gardées, Atelier compris) monte les
		-- fanions jusqu'à 12 ; jamais sous le compte du Record R ; valeur hostile ou absente : Record R seul
		it(
			"fanions avec KeptDecor : max(Record R, KeptDecor), 12 au plus ; absent ou illisible : Record R seul",
			function()
				expect({
					RanchLook.pennants(7, nil),
					RanchLook.pennants(7, 9),
					RanchLook.pennants(14, 3),
					RanchLook.pennants(14, 9),
					RanchLook.pennants(20, 12),
					RanchLook.pennants(20, 40),
					RanchLook.pennants(8, -5),
					RanchLook.pennants(8, 0 / 0),
					RanchLook.pennants(8, math.huge),
					RanchLook.pennants(8, "9"),
					RanchLook.pennants(8, 7.5),
				}).toEqual({ 0, 9, 6, 9, 12, 12, 3, 3, 3, 3, 7 })
			end
		)

		it("fanions 0 / 3 (R8) / 6 (R14) ; coussins ; halo ; ciel", function()
			expect({
				RanchLook.pennants(7),
				RanchLook.pennants(8),
				RanchLook.pennants(13),
				RanchLook.pennants(14),
			}).toEqual({
				0,
				3,
				3,
				6,
			})
			expect(RanchLook.cushions(0, 0)).toBe(0)
			expect(RanchLook.cushions(14, 4)).toBe(18)
			expect(RanchLook.cushions(30, 30)).toBe(24)
			expect(RanchLook.cushions(3.7, 1)).toBe(4)
			expect(RanchLook.halo(3, false)).toBe(0)
			expect(RanchLook.halo(3, true)).toBe(3)
			expect(RanchLook.halo(60, true)).toBe(#Visuals.Halo)
			expect(RanchLook.halo(2, "yes")).toBe(0)
			local function sky(A)
				local key, stars = RanchLook.sky(A)
				return { key or "", stars }
			end
			expect(sky(0)).toEqual({ "", 0 })
			expect(sky(1)).toEqual({ "sky.1", 0 })
			expect(sky(10)).toEqual({ "sky.10", 0 })
			expect(sky(11)).toEqual({ "sky.10", 11 })
			expect(sky(25)).toEqual({ "sky.10", Visuals.SkyMaxStars })
		end)
	end)

	describe("RanchLook › habillages", function()
		it(
			"les 14 identifiants sont les valeurs de cosmetics.theme (v1.3 + v2.0), chacun a sa ligne",
			function()
				local ids = {}
				-- Cosmetics.List fusionnée au lot I (D6) : 3 thèmes de la v1.3 et 11 de la v2.0 (since = 2)
				for _, item in Cosmetics.List do
					if item.kind == "theme" then
						table.insert(ids, item.id)
					end
				end
				table.sort(ids)
				local mine = table.clone(RanchLook.SKINS)
				table.sort(mine)
				expect(mine).toEqual(ids)
				expect(#ids).toBe(14)
				for _, id in RanchLook.SKINS do
					expect(RanchLook.skin(id) ~= nil).toBe(true)
				end
			end
		)

		it(
			"v1.3 : exactement l'aspect de RanchRenderer (THEME_COLORS ; « color » ne change rien)",
			function()
				local src = fs.readFile("src/client/Controllers/RanchRenderer.luau")
				local block = string.match(src, "local THEME_COLORS[^\n]*\n(.-)\n}")
				expect(block ~= nil).toBe(true)
				local colors = {}
				for id, r, g, b in string.gmatch(block, "(%w+) = Color3%.fromRGB%((%d+), (%d+), (%d+)%)") do
					colors[id] = { tonumber(r), tonumber(g), tonumber(b) }
				end
				expect(colors.moonlit ~= nil and colors.candyNight ~= nil).toBe(true)
				for id, rgb in colors do
					local row = RanchLook.skin(id)
					local c = row.fence
					expect({
						id = id,
						rgb = { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) },
					}).toEqual({ id = id, rgb = rgb })
					-- seule la clôture change (comme stepTheme)
					expect({ row.fenceMaterial, row.floor, row.floorMaterial, row.gate }).toEqual({})
				end
				expect(colors.color).toBe(nil)
				local color = RanchLook.skin("color")
				expect({ color.fence, color.fenceMaterial, color.floor, color.floorMaterial, color.gate }).toEqual({})
			end
		)

		it(
			"v2.0 : ligne complète, matériaux permis (jamais Glass), clôture ≠ sol, 11 aspects différents",
			function()
				local seen = {}
				for i = 4, #RanchLook.SKINS do
					local id = RanchLook.SKINS[i]
					local row = RanchLook.skin(id)
					for _, key in { "fence", "floor", "gate" } do
						expect(typeof(row[key])).toBe("Color3")
					end
					for _, key in { "fenceMaterial", "floorMaterial" } do
						local m = row[key]
						expect(contains(RanchLook.SKIN_MATERIALS, m)).toBe(true)
						expect(roblox.Enum.Material[m] ~= nil).toBe(true)
						expect(m ~= "Glass").toBe(true)
					end
					expect(row.fence ~= row.floor).toBe(true)
					local sig = string.format(
						"%.3f %.3f %.3f %.3f %.3f %.3f",
						row.fence.R,
						row.fence.G,
						row.fence.B,
						row.floor.R,
						row.floor.G,
						row.floor.B
					)
					expect(seen[sig]).toBe(nil)
					seen[sig] = id
				end
			end
		)

		it("identifiant inconnu → nil ; lignes en lecture seule", function()
			expect(RanchLook.skin(nil)).toBe(nil)
			for _, id in { "", "Moonlit", "???", 5, {}, true } do
				expect(RanchLook.skin(id)).toBe(nil)
			end
			local ok = pcall(function()
				RanchLook.skin("moonlit").fence = Color3.new(0, 0, 0)
			end)
			expect(ok).toBe(false)
		end)
	end)

	describe("RanchLook › aspects du Tapis, des coussins et du Pot (étape 3, D14, D18, D18b)", function()
		it("6 paliers du Tapis : aspect complet, matériaux permis ; 0 et illisibles → nil", function()
			local allowed = { SmoothPlastic = true, Neon = true, Foil = true, Ice = true }
			for tier = 1, 6 do
				local look = RanchLook.tapisLook(tier)
				expect(look ~= nil).toBe(true)
				expect(typeof(look.mat)).toBe("Color3")
				expect(allowed[look.material]).toBe(true)
				expect(#look.accents >= 1).toBe(true)
			end
			-- Gelée dorée en Foil ; Bonbon arc-en-ciel : 7 couleurs de bandes
			expect(RanchLook.tapisLook(4).material).toBe("Foil")
			expect(#RanchLook.tapisLook(3).accents).toBe(7)
			for _, bad in { 0, 7, 2.5, 0 / 0, "1", {}, nil } do
				expect(RanchLook.tapisLook(bad)).toBe(nil)
			end
		end)

		it("coussins : style de la semaine, inconnu → nil ; étoilés au Record R 11", function()
			expect(RanchLook.cushionStyle("pinkCushions")).toBe(roblox.Color3.fromRGB(255, 182, 213))
			for _, bad in { "", "nimporte", 5, nil, {} } do
				expect(RanchLook.cushionStyle(bad)).toBe(nil)
			end
			for r = 0, 60 do
				expect(RanchLook.starCushions(r)).toBe(r >= 11)
			end
			expect(RanchLook.starCushions(0 / 0)).toBe(false)
			expect(RanchLook.STAR_CUSHION.material).toBe("Foil")
		end)

		it("Pot : cuivre, argent, cristal (Ice) ; doré = l'aspect de la v1.3 (aucune ligne)", function()
			for _, name in { "copper", "silver", "crystal" } do
				local look = RanchLook.potLook(name)
				expect(look ~= nil).toBe(true)
				expect(look.material == "Foil" or look.material == "Ice").toBe(true)
			end
			expect(RanchLook.potLook("crystal").material).toBe("Ice")
			expect(RanchLook.potLook("gold")).toBe(nil)
			expect(RanchLook.potLook(nil)).toBe(nil)
			-- chaque matériau que potMaterial peut rendre a une ligne ou vaut l'aspect de la v1.3
			for r = 0, 60 do
				local name = RanchLook.potMaterial(r)
				expect(name == "gold" or RanchLook.potLook(name) ~= nil).toBe(true)
			end
		end)

		it("habillages v2.0 : les 11 nouveaux, jamais les 3 de la v1.3 ni un inconnu", function()
			local n = 0
			for _, id in RanchLook.SKINS do
				if RanchLook.isV2Skin(id) then
					n += 1
				end
			end
			expect(n).toBe(11)
			for _, id in { "color", "moonlit", "candyNight", "", "nope", 3 } do
				expect(RanchLook.isV2Skin(id)).toBe(false)
			end
		end)
	end)

	describe("RanchLook › Déco perso", function()
		it(
			"12 numéros sûrs : bon placement gardé ; inconnu, mauvaise taille, doublon, illisible → 0",
			function()
				-- 1 … 8 : objets « P » ; 9 … 12 : objets « G » (Cosmetics.DecoSlots)
				expect(RanchLook.decoPerso("1,2,3,4,5,7,9,10,6,8,12,14")).toEqual({
					1,
					2,
					3,
					4,
					5,
					7,
					9,
					10,
					6,
					8,
					12,
					14,
				})
				expect(RanchLook.decoPerso("6,0,0,0,0,0,0,0,1,0,0,0")).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect(RanchLook.decoPerso("1,1,0,0,0,0,0,0,0,0,0,0")).toEqual({
					1,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect(RanchLook.decoPerso("41,-1,3.5,abc,007,,2")).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
					2,
					0,
					0,
					0,
					0,
					0,
				})
				expect(RanchLook.decoPerso("3")).toEqual({ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				expect(RanchLook.decoPerso("0,0,0,0,0,0,0,0,0,0,0,0,1,1,1")).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
				})
				expect(RanchLook.decoPerso(string.rep("1,", 40))).toEqual({
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
					0,
				})
				for _, v in { nil, 5, {}, true, "" } do
					expect(RanchLook.decoPerso(v)).toEqual({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
				end
			end
		)

		it(
			"entrées tirées au hasard : toujours 12 entiers de 0 à 40, chacun à sa taille d'emplacement",
			function()
				local rng = newRng(4242)
				local alphabet =
					{ "0", "1", "2", "3", "9", "12", "40", "41", "", "x", "-", ".", " ", ",", ",," }
				for _ = 1, 2000 do
					local parts = {}
					for _ = 1, rng:NextInteger(0, 20) do
						table.insert(parts, alphabet[rng:NextInteger(1, #alphabet)])
					end
					local out = RanchLook.decoPerso(table.concat(parts, ","))
					expect(#out).toBe(12)
					local used = {}
					for i, n in out do
						expect(n % 1 == 0 and n >= 0 and n <= #Cosmetics.DecoPerso).toBe(true)
						if n > 0 then
							expect(Cosmetics.DecoPerso[n].size).toBe(Cosmetics.DecoSlots[i])
							expect(used[n]).toBe(nil)
							used[n] = true
						end
					end
				end
			end
		)
	end)

	describe("RanchLook › détail par ranch", function()
		local half = WorldLayout.Const.RanchWidth / 2
		local depth = WorldLayout.Const.RanchDepth

		it(
			"un robot qui traverse son ranch dans tous les sens ne fait changer de détail aucun ranch",
			function()
				local rng = newRng(16)
				for slot = 1, 16 do
					local current = RanchLook.currentRanch(0, slot, nil)
					expect(current).toBe(slot)
					local details = {}
					for k = 1, 16 do
						details[k] = RanchLook.detail(k, current)
					end
					for _ = 1, 400 do
						-- partout dans le rectangle, bords compris (clôture, portail, fond)
						local p = WorldLayout.toWorld(
							slot,
							Vector3.new(
								rng:NextNumber(-half, half),
								rng:NextNumber(0, 6),
								rng:NextNumber(0, depth)
							)
						)
						current = RanchLook.currentRanch(current, slot, p)
						expect(current).toBe(slot)
						for k = 1, 16 do
							expect(RanchLook.detail(k, current)).toBe(details[k])
						end
					end
				end
			end
		)

		it("ranch courant : 10 studs dans un autre ranch pour changer ; place et rues → le sien", function()
			local mine, other = 3, 9
			local edge = WorldLayout.toWorld(other, Vector3.new(0, 0, 9.5)) -- près du portail
			local deep = WorldLayout.toWorld(other, Vector3.new(0, 0, 10.5))
			local side = WorldLayout.toWorld(other, Vector3.new(half - 9.5, 0, 36))
			expect(RanchLook.currentRanch(mine, mine, edge)).toBe(mine)
			expect(RanchLook.currentRanch(mine, mine, side)).toBe(mine)
			expect(RanchLook.currentRanch(mine, mine, deep)).toBe(other)
			-- sur le bord de l'autre ranch, il reste l'autre ranch tant qu'il y est
			expect(RanchLook.currentRanch(other, mine, edge)).toBe(other)
			-- place, rue, boulevard, sans personnage : son ranch
			for _, p in { Vector3.new(0, 3, 0), Vector3.new(95, 0, 0), WorldLayout.gateOutside(other) } do
				expect(RanchLook.currentRanch(other, mine, p)).toBe(mine)
			end
			expect(RanchLook.currentRanch(other, mine, nil)).toBe(mine)
			-- pas de ranch à soi : 0 sur la place, le ranch où l'on est à 10 studs
			expect(RanchLook.currentRanch(0, 0, Vector3.new(0, 3, 0))).toBe(0)
			expect(RanchLook.currentRanch(0, 0, deep)).toBe(other)
		end)

		it(
			"détail : ranch courant et ses 2 voisins (modulo 16) en complet, les 13 autres réduits",
			function()
				for current = 1, 16 do
					local full = 0
					for k = 1, 16 do
						local d = RanchLook.detail(k, current)
						local near = k == current or k == current % 16 + 1 or k == (current - 2) % 16 + 1
						expect(d).toBe(if near then "full" else "reduced")
						if d == "full" then
							full += 1
						end
					end
					expect(full).toBe(3)
				end
				expect(RanchLook.detail(1, 16)).toBe("full")
				expect(RanchLook.detail(16, 1)).toBe("full")
				for _, v in HOSTILE do
					expect(RanchLook.detail(v, 3)).toBe("reduced")
					expect(RanchLook.detail(3, v)).toBe("reduced")
				end
			end
		)
	end)

	describe("RanchLook › dalle du Tapis Étoilé (copie de PadRules)", function()
		-- Profil tiré : v1 ou v2 (Schema.defaultsFor), Tapis 0 … 12, Tapis Étoilé 0 … 8, r 0 … 30, A 0 … 10
		local function profile(rng)
			local v2 = rng:NextNumber() < 0.6
			local d = Schema.defaultsFor(if v2 then 2 else 1)
			d.version = if v2 then 2 else 1
			d.R = rng:NextInteger(0, 30)
			d.tiles.snack = if rng:NextNumber() < 0.6 then 12 else rng:NextInteger(0, 12)
			d.tiles.seen = rng:NextInteger(0, 63)
			d.onboarding = { done = rng:NextNumber() < 0.8, step = rng:NextInteger(0, 20) }
			if v2 then
				d.bestR = d.R + rng:NextInteger(0, 10)
				d.ascend = rng:NextInteger(0, 10)
				d.tiles.star = rng:NextInteger(0, 8)
			end
			return d
		end

		it(
			"2 400 profils tirés, StarMat ouvert et coupé : allumée, niveau affiché et prix = PadRules",
			function()
				local rng = newRng(2026)
				local lit, star, total = 0, 0, 0
				for i = 1, 2400 do
					local d = profile(rng)
					Features.set("StarMat", i % 2 == 0)
					local label = RanchLook.padLabel(d, "snack", Features)
					local target, level = PadRules.target(d, "snack")
					local case = { i = i, star = label.star }
					expect(case).toEqual({ i = i, star = target == "star" })
					if PadRules.level(d, "snack") >= 12 then
						expect({ i = i, lit = label.lit }).toEqual({
							i = i,
							lit = PadRules.visible(d, "snack"),
						})
					end
					if label.lit then
						lit += 1
						expect(label.level).toBe(PadRules.progress(d, "snack") + 1)
						expect(label.level >= 13 and label.level <= 20).toBe(true)
						local price = UpgradeMath.price(
							"star",
							level,
							Prestige.r(d),
							Prestige.ascend(d),
							Prestige.bestR(d)
						)
						expect(label.price).toBe(price)
						expect(price < math.huge).toBe(true)
					else
						expect(label.level).toBe(0)
						expect(label.price).toBe(math.huge)
					end
					if label.star then
						star += 1
					end
					total += 1
				end
				Features.reset()
				-- les deux branches sont vraiment parcourues
				expect(total).toBe(2400)
				expect(lit > 150).toBe(true)
				expect(star - lit > 100).toBe(true)
			end
		)

		it(
			"table de valeurs au lieu du module : { StarMat = true } (signal du client) = Features ouvert",
			function()
				local rng = newRng(7)
				Features.set("StarMat", true)
				for _ = 1, 300 do
					local d = profile(rng)
					expect(RanchLook.padLabel(d, "snack", { StarMat = true })).toEqual(
						RanchLook.padLabel(d, "snack", Features)
					)
				end
				Features.reset()
			end
		)

		it("StarMat coupé, profil v1, autre dalle, entrées hostiles : jamais le Tapis Étoilé", function()
			local d = Schema.defaultsFor(2)
			d.version = 2
			d.R, d.bestR = 8, 8
			d.tiles.snack, d.tiles.star = 12, 0
			expect(RanchLook.padLabel(d, "snack", { StarMat = true }).lit).toBe(true)
			expect(RanchLook.padLabel(d, "snack", {}).star).toBe(false)
			expect(RanchLook.padLabel(d, "snack", nil).star).toBe(false)
			expect(RanchLook.padLabel(d, "decor", { StarMat = true }).star).toBe(false)
			local v1 = table.clone(d)
			v1.version = 1
			expect(RanchLook.padLabel(v1, "snack", { StarMat = true }).star).toBe(false)
			local str = table.clone(d)
			str.version = "2"
			expect(RanchLook.padLabel(str, "snack", { StarMat = true }).star).toBe(false)
			for _, v in HOSTILE do
				local label = RanchLook.padLabel(v, v, v)
				expect(label.star).toBe(false)
				expect(label.price).toBe(math.huge)
			end
		end)
	end)

	describe("RanchLook › Jelly Moon des lampions (étape 4)", function()
		it("moonLit = LightingController.resolve(…).moon sur 6 000 instants et charges tirés", function()
			local hc = Harness.new({ mode = "client" })
			local LC = hc:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController")
			local EventClock = h:require(L .. "Logic.EventClock")
			local rng = newRng(4242)
			local t0 = 1796724120
			local active, total = 0, 0
			for _ = 1, 6000 do
				local t = t0 + rng:NextNumber(0, 7 * 86400)
				local roll = rng:NextInteger(1, 8)
				local payload
				if roll == 1 then
					payload = nil
				elseif roll == 2 then
					payload = { features = "x" }
				else
					local jm = ({ true, false, nil, "true" })[rng:NextInteger(1, 4)]
					local features = { jellyMoon = jm }
					local moon = nil
					if rng:NextInteger(1, 3) > 1 then
						moon = {
							active = rng:NextInteger(1, 4) > 1,
							endsAt = t + rng:NextNumber(-600, 600),
						}
					end
					payload = { features = features, moon = moon }
				end
				local want = LC.resolve(payload, t, false, t).moon
				expect(RanchLook.moonLit(payload, t)).toBe(want)
				total += 1
				if want then
					active += 1
				end
			end
			-- les deux cas se présentent (séances actives et calme)
			expect(active > 100 and active < total).toBe(true)
			-- l'horloge des événements seule (pas de charge moon) : même règle
			local inMoon = nil
			for k = 0, 2000 do
				local t = t0 + k * 300
				if EventClock.moon(t).active then
					inMoon = t
					break
				end
			end
			expect(inMoon ~= nil).toBe(true)
			expect(RanchLook.moonLit({ features = { jellyMoon = true } }, inMoon)).toBe(true)
			expect(RanchLook.moonLit({ features = { jellyMoon = false } }, inMoon)).toBe(false)
			for _, bad in HOSTILE do
				expect(RanchLook.moonLit(bad, bad)).toBe(false)
				-- heure de fin illisible : la séance ne compte pas, seule l'horloge des événements décide
				expect(
					RanchLook.moonLit(
						{ features = { jellyMoon = true }, moon = { active = true, endsAt = bad } },
						t0
					)
				).toBe(
					if type(bad) == "number"
							and bad == bad
							and bad > t0
						then bad ~= math.huge or EventClock.moon(t0).active
						else EventClock.moon(t0).active
				)
			end
			expect(#hc.errors).toBe(0)
			expect(#hc:warnings()).toBe(0)
		end)
	end)

	describe("RanchLook › entrées hostiles", function()
		it("aucune erreur, valeurs finies, aspect sûr par défaut", function()
			for _, v in HOSTILE do
				local list = RanchLook.elements(v, v)
				expect(type(list)).toBe("table")
				local t = RanchLook.tier(v)
				expect(t >= 0 and t <= 6).toBe(true)
				local vat = RanchLook.vat(v)
				expect(vat.rings >= 1 and vat.rings <= 8 and vat.nozzles >= 0 and vat.nozzles <= 5).toBe(true)
				expect(vat.stirrerPeriod == 1 or vat.stirrerPeriod == 2 or vat.stirrerPeriod == 4).toBe(true)
				expect(type(RanchLook.potMaterial(v))).toBe("string")
				local s = RanchLook.potState(v)
				expect(s >= 0 and s <= 3).toBe(true)
				local tier = RanchLook.tapisTier(v)
				expect(tier >= 0 and tier <= 6).toBe(true)
				local shade = RanchLook.tapisShade(v)
				expect(shade >= 0 and shade <= 0.24 + 1e-9).toBe(true)
				expect(type(RanchLook.decorState(v, v, v))).toBe("string")
				expect(RanchLook.pennants(v) % 3).toBe(0)
				local c = RanchLook.cushions(v, v)
				expect(c >= 0 and c <= 24).toBe(true)
				local halo = RanchLook.halo(v, true)
				expect(halo >= 0 and halo <= 5).toBe(true)
				local _, stars = RanchLook.sky(v)
				expect(stars >= 0 and stars <= Visuals.SkyMaxStars).toBe(true)
				expect(RanchLook.currentRanch(v, v, v)).toBe(0)
				expect(type(RanchLook.currentRanch(v, 5, Vector3.new(0 / 0, 0, 0 / 0)))).toBe("number")
			end
			-- grands Record R et A : tout est construit, valeurs bornées
			expect(RanchLook.tier(1e9)).toBe(6)
			expect(RanchLook.vat(1e9).golden).toBe(true)
			expect(RanchLook.potMaterial(1e9)).toBe("crystal")
			expect(RanchLook.pennants(1e9)).toBe(6)
		end)

		it("zéro trace", function()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)
end
