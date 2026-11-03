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
			for _, id in V.Palettes do
				expect({ id = id, text = textOk(S, "palette." .. id) }).toEqual({ id = id, text = true })
			end
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
			end
		)

		it("cosmétiques v2.0 : clé EN/FR, source connue, jamais en double avec la v1.3", function()
			local h = Harness.new()
			local C = shared(h, "Config.Cosmetics")
			local S = shared(h, "Localization.Strings")
			local U = shared(h, "Config.Upgrades")
			local seen = {}
			for _, def in C.List do
				seen[def.kind .. ":" .. def.id] = "v1.3"
			end
			local byKindId = {}
			for _, def in C.ListV2 do
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
			-- 11 habillages de plus (14 avec les 3 thèmes de la v1.3) ; 51 titres v2.0
			local themes, titles = 0, 0
			for _, def in C.ListV2 do
				if def.kind == "theme" then
					themes += 1
				elseif def.kind == "title" then
					titles += 1
				end
			end
			expect(themes).toBe(11)
			expect(titles).toBe(51)
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
				for _, def in C.ListV2 do
					byKindId[def.kind .. "." .. def.id] = def
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
end
