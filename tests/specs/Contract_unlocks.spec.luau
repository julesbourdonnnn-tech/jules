--!nocheck
-- Contrat v2.0 (docs/04 §27.6, GDD v2.0 §4.29, Annexe B) : contenu nommé du jeu complet. Chaque
-- Record R de 1 à 20 a un déblocage nommé ET un changement visible ; chaque objet de Déco perso,
-- cosmétique de la semaine, cosmétique v2.0, Défi, palier du Carnet et tour appris a une source, une
-- clé EN et FR et une place unique ; sons et vibrations v2.0 déclarés (muets tant que non écoutés).

local SOURCE_KINDS = {
	recordR = true,
	ascend = true,
	atelier = true,
	carnet = true,
	season = true,
	track = true,
	play = true,
	dex = true,
	plopDay = true,
	objectives = true,
	moon = true,
	-- jalon géant (biggestEver ≥ value, GDD §4.17, §5.4) : lot A4, journal A4-3
	size = true,
}

local V2_SOUNDS = {
	"ChantierTap",
	"DecoGold",
	"DecoPlace",
	"TrickPop",
	"WeatherStart",
	"FeteLevel",
	"Cheese",
	"HeartGive",
	"AscendCharge",
	"AscendBurst",
	"ConfettiGain",
	"HelperHop",
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	local function textOk(S, key)
		return S.en[key] ~= nil and S.fr[key] ~= nil
	end

	describe("Contrat v2 › Un déblocage nommé et visible à chaque Record R (GDD §4.29)", function()
		it("Record R 1 à 20 : au moins une tuile nommée et un élément du ranch ; textes EN/FR", function()
			local h = Harness.new()
			local V = shared(h, "Config.Visuals")
			local S = shared(h, "Localization.Strings")
			for R = 1, 20 do
				local row = V.RecordTable[R]
				expect({ R = R, row = row ~= nil }).toEqual({ R = R, row = true })
				expect({ R = R, tiles = #row.unlocks >= 1, ranch = #row.ranch >= 1 }).toEqual({
					R = R,
					tiles = true,
					ranch = true,
				})
				for _, tile in row.unlocks do
					expect({ R = R, key = tile.key, text = textOk(S, tile.key) }).toEqual({
						R = R,
						key = tile.key,
						text = true,
					})
					if tile.vars and type(tile.vars.name) == "string" then
						expect({ R = R, name = tile.vars.name, text = textOk(S, tile.vars.name) }).toEqual({
							R = R,
							name = tile.vars.name,
							text = true,
						})
					end
				end
			end
			-- les déblocages de la table suivent la configuration (Plopettes, Monuments, Tapis Étoilé)
			local B = shared(h, "Config.Balance")
			local U = shared(h, "Config.Upgrades")
			local function has(R, key, var, value)
				for _, tile in V.RecordTable[R].unlocks do
					if tile.key == key and (var == nil or (tile.vars and tile.vars[var] == value)) then
						return true
					end
				end
				return false
			end
			for _, at in B.Helpers.ByRecordR do
				expect({ at = at, helper = has(at, "unlock.helper") }).toEqual({ at = at, helper = true })
			end
			for n, at in B.Monuments.OpenAt do
				if at <= 20 then
					expect({ n = n, shown = has(at, "unlock.monument", "n", n) }).toEqual({
						n = n,
						shown = true,
					})
				end
			end
			for r, cap in U.ById.star.open.loopCapByR do
				expect({ r = r, shown = has(r, "unlock.starMat", "n", 12 + (if r < 10 then cap else 5)) }).toEqual({
					r = r,
					shown = true,
				})
			end
			for _, at in B.SplorchV2.OfferedPensAt do
				expect({ at = at, pen = has(at, "unlock.offeredPen") }).toEqual({ at = at, pen = true })
			end
			expect(has(15, "unlock.jellyAscend")).toBe(true)
			expect(B.Ascend.ReqR[1]).toBe(15)
		end)

		it("ciel, halo, palettes, paliers du ranch : listes complètes avec leurs textes", function()
			local h = Harness.new()
			local V = shared(h, "Config.Visuals")
			local S = shared(h, "Localization.Strings")
			for i = 1, V.SkyNamed do
				expect(textOk(S, "sky." .. i)).toBe(true)
			end
			expect(textOk(S, "sky.stars")).toBe(true)
			for _, id in V.Halo do
				expect(textOk(S, "halo." .. id)).toBe(true)
			end
			-- nom montré : palette.<id> (Atelier, Record R) ou la clé de la semaine de Cosmetics (lot I, D4 :
			-- « peachPalette » se nomme weekly.peachPalette)
			local C = shared(h, "Config.Cosmetics")
			local weeklyKey = {}
			for _, def in C.WeeklyRotation do
				if def.kind == "palette" then
					weeklyKey[def.id] = def.key
				end
			end
			for _, id in V.Palettes do
				expect({ id = id, text = textOk(S, weeklyKey[id] or ("palette." .. id)) }).toEqual({
					id = id,
					text = true,
				})
			end
			expect(weeklyKey.peachPalette).toBe("weekly.peachPalette")
			expect(#V.RanchTiersAt).toBe(6)
			for i = 1, #V.RanchTiersAt do
				expect(textOk(S, "ranchTier." .. i)).toBe(true)
			end
			expect(#V.Faces).toBe(6)
			expect(#V.Tiers.gloves).toBe(9)
			expect(#V.Tiers.snack).toBe(6)
		end)
	end)

	describe("Contrat v2 › Annexe B : objets, cosmétiques, Défis, Carnet", function()
		it(
			"40 objets de Déco perso : numéros 1-40, 16 gagnés puis 24 de l'Atelier dans l'ordre",
			function()
				local h = Harness.new()
				local C = shared(h, "Config.Cosmetics")
				local S = shared(h, "Localization.Strings")
				local U = shared(h, "Config.Upgrades")
				expect(#C.DecoPerso).toBe(40)
				local ids, big, atelier = {}, 0, 0
				for i, item in C.DecoPerso do
					expect(item.n).toBe(i)
					expect(ids[item.id]).toBeNil()
					ids[item.id] = true
					expect({ id = item.id, text = textOk(S, item.key) }).toEqual({ id = item.id, text = true })
					expect(item.size == "P" or item.size == "G").toBe(true)
					if item.size == "G" then
						big += 1
					end
					expect({ id = item.id, source = SOURCE_KINDS[item.source.kind] == true }).toEqual({
						id = item.id,
						source = true,
					})
					if item.source.kind == "atelier" then
						atelier += 1
						expect(i).toBe(16 + item.source.value)
					else
						expect(i <= 16).toBe(true)
					end
				end
				expect(atelier).toBe(#U.WorkshopRows[U.WorkshopIndex.decoShop].costs)
				expect(big).toBe(16)
				-- 64 bits réservés pour decoPerso.owned (2 mots de 32 bits)
				expect(#C.DecoPerso <= 64).toBe(true)
				-- 12 emplacements (lot A4, D18) : 1 à 8 petits, 9 à 12 grands (GDD §11.5 : 8 P + 4 G)
				expect(C.DecoSlots).toEqual({ "P", "P", "P", "P", "P", "P", "P", "P", "G", "G", "G", "G" })
			end
		)

		it("cosmétiques v2.0 : clé EN/FR, source connue, jamais en double avec la v1.3", function()
			local h = Harness.new()
			local C = shared(h, "Config.Cosmetics")
			local S = shared(h, "Localization.Strings")
			local U = shared(h, "Config.Upgrades")
			-- lot I (D6) : la liste de la v2.0 est fusionnée dans List (since = 2) ; les cosmétiques de
			-- la semaine (weekly) ont leur case à part plus bas
			local seen = {}
			for _, def in C.List do
				if def.since == nil then
					seen[def.kind .. ":" .. def.id] = "v1.3"
				end
			end
			local V2 = {}
			for _, def in C.List do
				if def.since ~= nil and def.weekly == nil then
					table.insert(V2, def)
				end
			end
			local byKindId = {}
			for _, def in V2 do
				local k = def.kind .. ":" .. def.id
				expect({ k = k, twice = seen[k] ~= nil }).toEqual({ k = k, twice = false })
				seen[k] = "v2.0"
				byKindId[def.kind .. "." .. def.id] = def
				expect({ k = k, text = textOk(S, def.key) }).toEqual({ k = k, text = true })
				expect({ k = k, source = SOURCE_KINDS[def.source.kind] == true }).toEqual({
					k = k,
					source = true,
				})
			end
			-- 11 habillages de plus (14 avec les 3 thèmes de la v1.3) ; 52 titres v2.0 (51 jusqu'au lot
			-- A4 : + « Sun Keeper », jalon géant 1e24 du GDD §4.17, §5.4, oublié par l'Annexe B ; A4-3)
			local themes, titles = 0, 0
			for _, def in V2 do
				if def.kind == "theme" then
					themes += 1
				elseif def.kind == "title" then
					titles += 1
				end
			end
			expect(themes).toBe(11)
			expect(titles).toBe(52)
			-- jalons géants (lot A4, D16) : selle 1e15, traînée 1e18, titre 1e24, textes simples EN / FR
			local giants = {
				{ k = "saddle.cosmic", size = 1e15, en = "Cosmic", fr = "Cosmique" },
				{ k = "trail.shootingStars", size = 1e18, en = "Shooting Stars", fr = "Étoiles filantes" },
				{ k = "title.sunKeeper", size = 1e24, en = "Sun Keeper", fr = "Gardien du Soleil" },
			}
			local sized = 0
			for _, def in V2 do
				if def.source.kind == "size" then
					sized += 1
				end
			end
			expect(sized).toBe(#giants)
			for _, g in giants do
				local def = byKindId[g.k]
				expect({ k = g.k, found = def ~= nil }).toEqual({ k = g.k, found = true })
				expect(def.source).toEqual({ kind = "size", value = g.size })
				expect({ k = g.k, en = S.en[def.key], fr = S.fr[def.key] }).toEqual({
					k = g.k,
					en = g.en,
					fr = g.fr,
				})
			end
			-- « Pour le plaisir » : chaque objet donné existe, avec la source atelier = son bit
			for _, line in U.Fun do
				if line.store == "bits" then
					for i, grant in line.grants do
						local kind = string.match(grant, "^(%w+)%.")
						if kind ~= "palette" and kind ~= "decor" then
							local def = byKindId[grant]
							expect({ grant = grant, found = def ~= nil }).toEqual({
								grant = grant,
								found = true,
							})
							expect(def.source).toEqual({ kind = "atelier", value = line.firstBit + i - 1 })
						end
					end
				end
			end
			-- semaine : 8 cosmétiques dans l'ordre de rotation
			expect(#C.WeeklyRotation).toBe(8)
			for _, w in C.WeeklyRotation do
				expect({ id = w.id, text = textOk(S, w.key) }).toEqual({ id = w.id, text = true })
			end
		end)

		it(
			"liste unique (lot I, D6) : Cosmetics.List = v1.3 puis v2.0 (since = 2) puis semaine ; paires sorte:id uniques, ByKindId complet, ListV2 retirée",
			function()
				local h = Harness.new()
				local C = shared(h, "Config.Cosmetics")
				expect(C.ListV2).toBeNil()
				local seen, v13, v2, weekly = {}, 0, 0, 0
				local phase = 1 -- 1 = v1.3, 2 = v2.0, 3 = semaine : jamais en arrière
				local orders = {}
				for _, def in C.List do
					local k = def.kind .. ":" .. def.id
					expect({ k = k, twice = seen[k] ~= nil }).toEqual({ k = k, twice = false })
					seen[k] = true
					expect({ k = k, byKindId = C.ByKindId[k] == def }).toEqual({ k = k, byKindId = true })
					local at = if def.since == nil then 1 elseif def.weekly == nil then 2 else 3
					expect({ k = k, order = at >= phase }).toEqual({ k = k, order = true })
					phase = at
					if at == 1 then
						v13 += 1
						expect(def.key).toBeNil()
					else
						expect({ k = k, since = def.since }).toEqual({ k = k, since = 2 })
						expect({ k = k, key = type(def.key) }).toEqual({ k = k, key = "string" })
						if at == 2 then
							v2 += 1
						else
							weekly += 1
							expect(def.weekly).toBe(weekly)
							expect(def.source).toEqual({ kind = "won", value = weekly })
						end
					end
					-- rang dans la sorte : strictement croissant dans l'ordre de la liste
					expect({ k = k, order = def.order > (orders[def.kind] or 0) }).toEqual({
						k = k,
						order = true,
					})
					orders[def.kind] = def.order
				end
				-- 47 objets de la v1.3 (liste de 3636608), 88 de la v2.0, 8 de la semaine
				expect({ v13 = v13, v2 = v2, weekly = weekly }).toEqual({ v13 = 47, v2 = 88, weekly = 8 })
				local n = 0
				for _ in C.ByKindId do
					n += 1
				end
				expect(n).toBe(#C.List)
				-- WeeklyRotation : vue dérivée, mêmes tables, ORDRE FIGÉ (bit i de weeklyTrack.won, stocké)
				local ids = {}
				for i, def in C.WeeklyRotation do
					expect(def.weekly).toBe(i)
					expect(C.ByKindId[def.kind .. ":" .. def.id]).toBe(def)
					table.insert(ids, def.kind .. ":" .. def.id)
				end
				expect(ids).toEqual({
					"saddle:cookieSaddle",
					"trail:bubbleTrail",
					"flag:strawberryFlag",
					"outfit:polkaBow",
					"emote:hugEmote",
					"title:loyalBuddy",
					"palette:peachPalette",
					"cushions:pinkCushions",
				})
				-- bannières : PriorityV2 fusionnée dans Priority
				local E = shared(h, "Config.Events")
				expect(E.Banners.PriorityV2).toBeNil()
				expect(E.Banners.Priority.ascend).toBe(1)
			end
		)

		it(
			"Défis (12), Carnet (8 paliers), tours appris (5), météo visuelle : textes et cohérence",
			function()
				local h = Harness.new()
				local Q = shared(h, "Config.Quests")
				local C = shared(h, "Config.Cosmetics")
				local E = shared(h, "Config.Events")
				local S = shared(h, "Localization.Strings")
				expect(#Q.Challenges).toBe(12)
				for i, ch in Q.Challenges do
					expect(ch.id).toBe(i)
					expect({ id = ch.id, text = textOk(S, ch.key) }).toEqual({ id = ch.id, text = true })
					expect(ch.target >= 1).toBe(true)
				end
				local byKindId = {}
				for _, def in C.List do
					if def.since ~= nil and def.weekly == nil then
						byKindId[def.kind .. "." .. def.id] = def
					end
				end
				expect(Q.Carnet.Tiers).toEqual({ 50, 100, 250, 500, 1000, 2500, 5000, 10000 })
				for _, tier in Q.Carnet.Tiers do
					local def = byKindId[Q.Carnet.Rewards[tier]]
					expect({ tier = tier, found = def ~= nil }).toEqual({ tier = tier, found = true })
					expect(def.source).toEqual({ kind = "carnet", value = tier })
				end
				for at, id in Q.Carnet.DecoAt do
					local found = nil
					for _, item in C.DecoPerso do
						if item.id == id then
							found = item
						end
					end
					expect(found.source).toEqual({ kind = "carnet", value = at })
				end
				-- piste : 12 paliers ; une semaine complète vaut 24 points au moins par les seuls objectifs et Défis
				local tiers = Q.WeeklyTrack.Tiers
				expect(#tiers).toBe(12)
				expect(tiers[12]).toBe("cosmetic")
				expect(Q.WeeklyTrack.PointsPerObjective).toBe(2)
				expect(Q.WeeklyTrack.PointsPerChallenge).toBe(5)
				expect(#Q.Mastery.Tricks).toBe(5)
				for _, trick in Q.Mastery.Tricks do
					expect(textOk(S, trick.key)).toBe(true)
				end
				-- météo : purement visuelle (décision par défaut n° 4)
				expect(E.Weather.visualOnly).toBe(true)
				for _, kind in E.Weather.Kinds do
					expect({ kind = kind, text = textOk(S, "weather." .. kind) }).toEqual({
						kind = kind,
						text = true,
					})
				end
			end
		)
	end)

	describe("Contrat v2 › Sons, vibrations, Monuments, Plopettes", function()
		it(
			"sons v2.0 déclarés et muets ; vibrations du GDD §10.5 ; noms des Monuments et des Plopettes",
			function()
				local h = Harness.new()
				local Sounds = shared(h, "Config.Sounds")
				local Console = shared(h, "Config.Console")
				local S = shared(h, "Localization.Strings")
				local B = shared(h, "Config.Balance")
				for _, key in V2_SOUNDS do
					expect({ key = key, muted = Sounds[key] ~= nil and Sounds[key].id == "" }).toEqual({
						key = key,
						muted = true,
					})
				end
				for _, name in { "tierUp", "chantier", "ascend" } do
					local def = Console.Haptics.Events[name]
					expect({ name = name, ok = def ~= nil and def.strength <= 1 and def.duration > 0 }).toEqual({
						name = name,
						ok = true,
					})
				end
				for n = 1, #B.Monuments.OpenAt do
					expect(textOk(S, "monument." .. n)).toBe(true)
				end
				for _, id in { "pip", "pop", "pim", "pom", "puff", "plume" } do
					expect(textOk(S, "helper.name." .. id)).toBe(true)
				end
			end
		)
	end)

	describe("Contrat v2 › Personnalités des espèces (Config/Species, GDD §5.6)", function()
		it("colonne perso : chaque espèce a la sienne, exactement la table du GDD §5.6", function()
			local h = Harness.new()
			local Species = shared(h, "Config.Species")
			expect(Species.Personalities).toEqual({
				"curious",
				"sleepy",
				"bouncy",
				"cuddly",
				"prankster",
				"proud",
			})
			local byPerso = {}
			for _, def in Species.List do
				byPerso[def.perso] = byPerso[def.perso] or {}
				table.insert(byPerso[def.perso], def.key)
			end
			for _, list in byPerso do
				table.sort(list)
			end
			expect(byPerso).toEqual({
				curious = { "lotlolly", "moonhop", "moonplop", "plop", "whiskerwob" },
				sleepy = { "hopscotch", "lilypuff", "purrpudding", "wibble" },
				bouncy = { "boingtoad", "clover_hop", "nubbin", "ribbit_drop" },
				cuddly = { "bunbun", "frillo", "mochi_mew", "prickle_puff" },
				prankster = { "croakaroo", "drago_drop", "gillygum", "jiggleberry" },
				proud = { "blossompurr", "coralotl", "emberwob", "grand_gloop", "royal_plop" },
			})
		end)

		it(
			"« proud » réservé aux Légendaires, Mythiques et Secrets ; chaque personnalité a 4 espèces au moins",
			function()
				local h = Harness.new()
				local Species = shared(h, "Config.Species")
				local Rarities = shared(h, "Config.Rarities")
				local known = {}
				for _, perso in Species.Personalities do
					known[perso] = 0
				end
				-- la rareté de seuil est bien Légendaire dans Config/Rarities
				local legendary = nil
				for _, def in Rarities.List do
					if def.key == "legendary" then
						legendary = def.id
					end
				end
				expect(legendary).toBe(Species.ProudMinRarity)
				for _, def in Species.List do
					expect({ key = def.key, known = known[def.perso] ~= nil }).toEqual({
						key = def.key,
						known = true,
					})
					known[def.perso] += 1
					if def.perso == "proud" then
						expect({ key = def.key, rare = def.rarity >= Species.ProudMinRarity }).toEqual({
							key = def.key,
							rare = true,
						})
					end
				end
				for perso, n in known do
					expect({ perso = perso, enough = n >= 4 }).toEqual({ perso = perso, enough = true })
				end
			end
		)

		it("le serveur ne lit jamais la personnalité (affichage du client seulement, GDD §5.6)", function()
			local fs = require("@lune/fs")
			local offenders = {}
			-- lot B5 (INT-B5-FEATURES, docs/04 §27.11, journal B5-1) : UNE mention permise dans src/server,
			-- le nom de l'interrupteur dans la liste fixe qu'EventService ANNONCE au client
			-- (V2_CLIENT_FLAGS → EventState.features.v2) ; aucune règle du serveur ne le lit pour autant
			local announced = 0
			local function scan(dir)
				for _, entry in fs.readDir(dir) do
					local full = dir .. "/" .. entry
					if fs.isDir(full) then
						scan(full)
					elseif string.find(entry, "%.luau$") then
						local source = fs.readFile(full)
						if full == "src/server/Services/EventService.luau" then
							local block = string.match(source, "local V2_CLIENT_FLAGS = {.-\n}")
							if block then
								announced = select(2, string.gsub(block, '"Personalities"', ""))
								source = string.gsub(source, "local V2_CLIENT_FLAGS = {.-\n}", "", 1)
							end
						end
						if
							string.find(source, "%.perso%f[^%w_]")
							or string.find(source, "Personalities", 1, true)
						then
							table.insert(offenders, full)
						end
					end
				end
			end
			scan("src/server")
			expect(offenders).toEqual({})
			expect(announced).toBe(1)
		end)
	end)

	describe("Contrat v2 › Couleurs des suffixes des grands nombres (Config/Visuals, GDD §4.2)", function()
		it("6 familles contiguës de K (1e3) à Tg (1e93), par pas de 3, 6 couleurs distinctes", function()
			local h = Harness.new()
			local Visuals = shared(h, "Config.Visuals")
			local list = Visuals.SuffixColors
			expect(#list).toBe(6)
			expect(list[1].from).toBe(3)
			expect(list[#list].to).toBe(93)
			local seen = {}
			for i, group in list do
				expect({
					i = i,
					step = group.from % 3 == 0 and group.to % 3 == 0,
					order = group.from <= group.to,
				}).toEqual({
					i = i,
					step = true,
					order = true,
				})
				if i > 1 then
					expect({ i = i, contiguous = group.from == list[i - 1].to + 3 }).toEqual({
						i = i,
						contiguous = true,
					})
				end
				local c = group.color
				local id = string.format(
					"%d,%d,%d",
					math.round(c.R * 255),
					math.round(c.G * 255),
					math.round(c.B * 255)
				)
				expect({ i = i, unique = seen[id] == nil }).toEqual({ i = i, unique = true })
				seen[id] = true
			end
			-- bornes du GDD : B-T or, Sx à Dc cyan (Sx et Sp dans la même famille), Ud à Nvd, Vg à Tg
			expect({ list[2].from, list[2].to, list[4].from, list[4].to, list[5].from, list[5].to }).toEqual({
				9,
				12,
				21,
				33,
				36,
				60,
			})
		end)
	end)
end
