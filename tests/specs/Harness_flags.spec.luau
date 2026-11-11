--!nocheck
-- Harness_flags (lot I, étape 1, décision D1 du plan I) : préréglages des interrupteurs v2.0 du
-- harnais (tests/harness/Flags). Chaque préréglage donne ses valeurs dans un harnais neuf, avant
-- tout require du test ; Schema.VERSION suit le préréglage ; SchemaV2 ne se change jamais en direct ;
-- le préréglage « v13 » est EXACTEMENT la configuration livrée jusqu'à 3636608 (liste figée ici).
local Flags = require("../harness/Flags")

-- Config/Features.Defaults au commit 3636608 (version de test v1.3 et lots A1-B5), recopiée à la main
local FROZEN_V13 = {
	BoopRush = "on",
	MegaSquish = true,
	GoldenWobbler = true,
	JellyMoon = true,
	ServerGauge = true,
	Clips = true,
	Costumes = "winter2026",
	Diagnostics = true,
	RewardedAds = false,
	JellyAscend = false,
	Season = false,
	SlowJelly = false,
	Duo = false,
	Parcels = false,
	WorldFirst = false,
	FameLineage = false,
	GreatJelly = false,
	SchemaV2 = false,
	UpgradesScreen = false,
	Confetti = false,
	Workshop = false,
	StarMat = false,
	Gloves = false,
	Monuments = false,
	RecordR = false,
	PetitSplorch = false,
	Helpers = false,
	WeeklyTrack = false,
	Carnet = false,
	Mastery = false,
	RanchTiers = false,
	RanchSkins = false,
	DecoPerso = false,
	Hearts = false,
	PhotoMode = false,
	Weather = false,
	Fete = false,
	Personalities = false,
	Ambience = false,
}

-- Clés qui ne sont pas des fonctions de lancement de la v2.0 (docs/04 §27.3, dernière phrase) :
-- jamais touchées par un préréglage
local NOT_V2 = {
	"BoopRush",
	"MegaSquish",
	"GoldenWobbler",
	"JellyMoon",
	"ServerGauge",
	"Clips",
	"Costumes",
	"Diagnostics",
	"RewardedAds",
	"Season",
	"SlowJelly",
	"Duo",
	"Parcels",
	"WorldFirst",
	"FameLineage",
	"GreatJelly",
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local FEATURES = "ReplicatedStorage.Shared.Config.Features"
	local SCHEMA = "ServerScriptService.Server.Data.Schema"

	-- valeurs livrées (fichier non touché : harnais au préréglage par défaut)
	local function shipped()
		local h = Harness.new()
		local out = table.clone(h:require(FEATURES).Defaults)
		h:dispose()
		return out
	end

	local function snapshot(h)
		local F = h:require(FEATURES)
		local out = {}
		for key in F.Defaults do
			out[key] = { default = F.Defaults[key], now = F.get(key) }
		end
		return out
	end

	describe("Harnais › préréglages des interrupteurs (tests/harness/Flags)", function()
		it("23 clés v2 de lancement, chacune un booléen de Config/Features, aucune autre clé", function()
			local ship = shipped()
			expect(#Flags.V2_KEYS).toBe(23)
			local seen = {}
			for _, key in Flags.V2_KEYS do
				expect({ key = key, twice = seen[key] == true }).toEqual({ key = key, twice = false })
				seen[key] = true
				expect({ key = key, kind = type(ship[key]) }).toEqual({ key = key, kind = "boolean" })
			end
			for _, key in NOT_V2 do
				expect({ key = key, v2 = seen[key] == true }).toEqual({ key = key, v2 = false })
			end
			-- chaque clé de la configuration est soit une clé v2, soit une des clés hors v2.0
			local n = 0
			for key in ship do
				n += 1
				local known = seen[key] == true or table.find(NOT_V2, key) ~= nil
				expect({ key = key, known = known }).toEqual({ key = key, known = true })
			end
			expect(n).toBe(#Flags.V2_KEYS + #NOT_V2)
		end)

		it(
			"« launch » (défaut) : valeurs livrées intactes, Schema.VERSION 2 (SchemaV2 ouvert au lot I)",
			function()
				local ship = shipped()
				for _, h in { Harness.new(), Harness.new({ flags = "launch" }) } do
					local snap = snapshot(h)
					for key, value in ship do
						expect({ key = key, default = snap[key].default, now = snap[key].now }).toEqual({
							key = key,
							default = value,
							now = value,
						})
					end
					expect(h:require(SCHEMA).VERSION).toBe(2)
					expect(h.flags).toBe("launch")
					h:dispose()
				end
				expect(ship.SchemaV2).toBe(true)
			end
		)

		it(
			"« full » : chaque clé v2 ouverte, les autres clés livrées intactes ; Schema.VERSION 2",
			function()
				local ship = shipped()
				local h = Harness.new({ flags = "full" })
				local snap = snapshot(h)
				for _, key in Flags.V2_KEYS do
					expect({ key = key, v = snap[key] }).toEqual({
						key = key,
						v = { default = true, now = true },
					})
				end
				for _, key in NOT_V2 do
					expect({ key = key, v = snap[key].now }).toEqual({ key = key, v = ship[key] })
				end
				expect(h:require(SCHEMA).VERSION).toBe(2)
				h:dispose()
			end
		)

		it("« v13 » : exactement la configuration livrée jusqu'à 3636608 ; Schema.VERSION 1", function()
			local h = Harness.new({ flags = "v13" })
			local snap = snapshot(h)
			local n = 0
			for key, value in FROZEN_V13 do
				n += 1
				expect({ key = key, v = snap[key] }).toEqual({
					key = key,
					v = { default = value, now = value },
				})
			end
			for key in snap do
				expect({ key = key, frozen = FROZEN_V13[key] ~= nil }).toEqual({ key = key, frozen = true })
			end
			expect(n).toBe(39)
			local Schema = h:require(SCHEMA)
			expect(Schema.VERSION).toBe(1)
			expect(Schema.defaults().version).toBe(1)
			h:dispose()
		end)

		it("« cut » : SchemaV2 seul ouvert (coupure d'urgence après I) ; Schema.VERSION 2", function()
			local ship = shipped()
			local h = Harness.new({ flags = "cut" })
			local snap = snapshot(h)
			for _, key in Flags.V2_KEYS do
				local want = key == "SchemaV2"
				expect({ key = key, v = snap[key] }).toEqual({ key = key, v = { default = want, now = want } })
			end
			for _, key in NOT_V2 do
				expect({ key = key, v = snap[key].now }).toEqual({ key = key, v = ship[key] })
			end
			expect(h:require(SCHEMA).VERSION).toBe(2)
			h:dispose()
		end)

		it(
			"table de valeurs : la configuration livrée changée clé par clé ; clé ou type inconnus refusés",
			function()
				local ship = shipped()
				local h = Harness.new({ flags = { UpgradesScreen = true, Weather = true, SchemaV2 = false } })
				local snap = snapshot(h)
				expect(snap.UpgradesScreen.now).toBe(true)
				expect(snap.Weather.now).toBe(true)
				expect(snap.SchemaV2.now).toBe(false)
				expect(h:require(SCHEMA).VERSION).toBe(1)
				for key, value in ship do
					if key ~= "UpgradesScreen" and key ~= "Weather" and key ~= "SchemaV2" then
						expect({ key = key, v = snap[key].now }).toEqual({ key = key, v = value })
					end
				end
				h:dispose()
				expect(function()
					Flags.preset("nope")
				end).toThrow()
				local h2 = Harness.new()
				expect(function()
					Flags.apply(h2, { NotAFlag = true })
				end).toThrow()
				expect(function()
					Flags.apply(h2, { Weather = "oui" })
				end).toThrow()
				h2:dispose()
			end
		)

		it("SchemaV2 jamais changé en direct (Features.set le refuse dans chaque préréglage)", function()
			for _, preset in { "launch", "full", "v13", "cut" } do
				local h = Harness.new({ flags = preset })
				local F = h:require(FEATURES)
				local before = F.get("SchemaV2")
				expect({ preset = preset, set = F.set("SchemaV2", not before) }).toEqual({
					preset = preset,
					set = false,
				})
				expect(F.get("SchemaV2")).toBe(before)
				-- un autre interrupteur v2 se change en direct, puis reset rend le préréglage
				local ok = F.set("Weather", not F.get("Weather"))
				expect(ok).toBe(true)
				F.reset()
				expect(F.get("Weather")).toBe(F.Defaults.Weather)
				h:dispose()
			end
		end)

		it("chaque harnais a ses valeurs : un préréglage n'en touche jamais un autre", function()
			local a = Harness.new({ flags = "v13" })
			local b = Harness.new({ flags = "full" })
			local c = Harness.new()
			expect(a:require(FEATURES).get("UpgradesScreen")).toBe(false)
			expect(b:require(FEATURES).get("UpgradesScreen")).toBe(true)
			expect(c:require(FEATURES).get("SchemaV2")).toBe(true)
			expect(a:require(SCHEMA).VERSION).toBe(1)
			expect(b:require(SCHEMA).VERSION).toBe(2)
			a:dispose()
			b:dispose()
			c:dispose()
		end)
	end)
end
