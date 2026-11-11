--!nocheck
-- Contrat v2.0 (docs/04 §27, GDD v2.0) : interrupteurs coupés par défaut (le jeu de base joue
-- exactement comme la version de test), schéma v2 et migration v1 → v2 (exacte, sans perte,
-- idempotente, jamais écrite par un serveur v1), intentions et remotes déclarés mais pas écoutés,
-- signaux et types figés, textes EN et FR. L'architecte étend ce fichier ; un paquet n'y retire
-- rien (une attente qui change avec le GDD est mise à jour avec lui, raison au journal §27.12).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Flags = require("../harness/Flags")

-- Interrupteurs des systèmes v2.0 (Config/Features, docs/04 §27.3) : ouverts par groupe au lot I
-- (OPEN_AT_LAUNCH : les clés déjà ouvertes dans la configuration livrée ; les autres restent coupées
-- jusqu'à l'étape de leur groupe : progression, méta, monde et vie)
local V2_FLAGS = {
	"JellyAscend",
	"SchemaV2",
	"UpgradesScreen",
	"Confetti",
	"Workshop",
	"StarMat",
	"Gloves",
	"Monuments",
	"RecordR",
	"PetitSplorch",
	"Helpers",
	"WeeklyTrack",
	"Carnet",
	"Mastery",
	"RanchTiers",
	"RanchSkins",
	"DecoPerso",
	"Hearts",
	"PhotoMode",
	"Weather",
	"Fete",
	"Personalities",
	"Ambience",
}

-- Lot I, étape 1 (journal I-4) : SchemaV2 seul (données d'abord ; un profil migré ne revient jamais) ;
-- étape 2 (journal I-19) : la progression (Record R, écran Améliorations, Confettis, Atelier, familles,
-- Jelly Ascend et Petit Splorch ensemble, Plopettes)
local OPEN_AT_LAUNCH = {
	SchemaV2 = true,
	UpgradesScreen = true,
	Confetti = true,
	Workshop = true,
	StarMat = true,
	Gloves = true,
	Monuments = true,
	RecordR = true,
	JellyAscend = true,
	PetitSplorch = true,
	Helpers = true,
}

local V2_SIGNALS = { "PrestigeApplied", "UpgradeBought", "ConfettiChanged", "RecordReached", "HelperPressed" }

local V2_TYPES = {
	"PrestigeKind",
	"UpgradeCurrency",
	"UpgradeSnapshot",
	"UpgradeResultPayload",
	"HelperPressEntry",
	"HelperPressPayload",
	"HelperState",
	"CelebrateAscend",
	"CelebratePetitSplorch",
	"RanchAttributesV2",
	"ChallengeEntry",
}

-- Champs de premier niveau ajoutés par le schéma v2 (GDD v2.0 §12.6, docs/04 §27.2)
local V2_KEYS = {
	"bestR",
	"regainBonusA",
	"memoryR", -- décision INT-A1-MEMORY (lot A2, docs/04 §27.12 A2-1)
	"ascendDay", -- jour de la dernière Ascension (lot I, D5, journal I-3)
	"confetti",
	"confettiTotal",
	"atelier",
	"atelierCosmetics",
	"decorBuilds",
	"carnet",
	"weeklyTrack",
	"mastery",
	"unlocksSeen",
	"decoPerso",
	"hearts",
}

local ARG_KINDS = {
	uid = true,
	uidOpt = true,
	uids = true,
	time = true,
	dir = true,
	bool = true,
	int = true,
	userId = true,
	userIds = true,
	key = true,
	str = true,
	setting = true,
}

-- Textes du contrat v2.0 qui doivent exister (les autres viennent de Config/Upgrades, plus bas)
local V2_TEXT_KEYS = {
	"upgrades.title",
	"upgrades.tab.suggested",
	"upgrades.tab.ranch",
	"upgrades.tab.helpers",
	"upgrades.tab.workshop",
	"upgrades.mode.x1",
	"upgrades.mode.x10",
	"upgrades.mode.max",
	"upgrades.state.ready",
	"upgrades.state.need",
	"upgrades.state.max",
	"upgrades.state.locked",
	"upgrades.state.loopCap",
	"upgrades.state.busy",
	"upgrades.state.retry",
	"upgrades.detail.missing",
	"upgrades.detail.bulk",
	"upgrades.detail.max",
	"upgrades.detail.partial",
	"upgrades.detail.starCap",
	"upgrades.detail.opensAt",
	"upgrades.detail.allMax",
	"upgrades.allMaxCard",
	"upgrades.bought",
	"upgrades.partial",
	"upgrades.advisor.ascend",
	"hud.nextBuy.ready",
	"hud.memory",
	"hud.regainTrack",
	"card.welcomeV2.title",
	"card.welcomeV2.body",
	"card.regainDone",
	"card.recordStep",
	"preview.ascend.restart",
	"preview.ascend.speed",
	"preview.splorch.neutral",
	"records.confettiEarned",
	"splorch.tile.growth",
	"splorch.tile.confetti",
	"petit.tile",
	"ascend.tile.growth",
	"ascend.confirm",
	"ascend.yes",
	"ascend.later",
	"confetti.fullPen",
}

-- Annexe B du GDD : listes nommées complètes (préfixe → nombre de clés)
local ANNEX_COUNTS = {
	["deco%."] = 42, -- 40 objets + titre + emplacement libre
	["weekly%."] = 8,
	["skin%."] = 11, -- + 3 habillages de la v1.3 (cosmetic.theme.*)
	["sky%."] = 11,
	["title%.r%d+$"] = 36,
	["challenge%."] = 12,
	["trick%."] = 6, -- 5 tours + l'annonce « Nouveau tour » (trick.new, lot B5, journal B5-11)
	["monument%.%d+$"] = 10,
	["helper%.name%."] = 6,
	["ranchTier%."] = 6,
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	local function schema(h)
		return h:require("ServerScriptService.Server.Data.Schema")
	end

	local function serverOrder()
		local source = fs.readFile("src/server/Main.server.luau")
		local out = {}
		for name in string.gmatch(source, '\n\t"(%w+)",') do
			out[name] = true
		end
		return out
	end

	local function readV1()
		return serde.decode("json", fs.readFile("tests/fixtures/profiles/v1.json"))
	end

	-- Migration complète comme DataService la fera (étape pure puis reconcile des valeurs v2)
	local function migrateFull(h, data)
		local Schema = schema(h)
		local Tables = shared(h, "Util.Tables")
		local out = Schema.migrate(data, 1, 2)
		Tables.reconcile(out, Schema.defaultsFor(2))
		return out
	end

	-- Feuilles d'une table : chemin → valeur (les tableaux vides comptent comme une feuille)
	local function leaves(t, prefix, out)
		out = out or {}
		local empty = true
		for k, v in t do
			empty = false
			local path = if prefix == "" then tostring(k) else prefix .. "." .. tostring(k)
			if type(v) == "table" then
				leaves(v, path, out)
			else
				out[path] = v
			end
		end
		if empty and prefix ~= "" then
			out[prefix] = "{}"
		end
		return out
	end

	local function get(t, path)
		local cur = t
		for part in string.gmatch(path, "[^%.]+") do
			if type(cur) ~= "table" then
				return nil
			end
			local n = tonumber(part)
			local nextValue = cur[part]
			if nextValue == nil and n ~= nil then
				nextValue = cur[n]
			end
			cur = nextValue
		end
		if type(cur) == "table" and next(cur) == nil then
			return "{}"
		end
		return cur
	end

	-- ---------------------------------------------------------------------------------------------
	describe("Contrat v2 › Interrupteurs (le jeu de base joue comme avant)", function()
		it(
			"chaque système v2.0 a son interrupteur : SchemaV2 et la progression ouverts au lancement, les autres coupés jusqu'à leur groupe",
			function()
				local h = Harness.new()
				local F = shared(h, "Config.Features")
				F.reset()
				for _, key in V2_FLAGS do
					local want = OPEN_AT_LAUNCH[key] == true
					expect({ key = key, default = F.Defaults[key] }).toEqual({ key = key, default = want })
					expect({ key = key, now = F.get(key) }).toEqual({ key = key, now = want })
				end
				-- la liste du harnais (tests/harness/Flags) est la même que celle du contrat
				local listed = {}
				for _, key in Flags.V2_KEYS do
					listed[key] = true
				end
				expect(#Flags.V2_KEYS).toBe(#V2_FLAGS)
				for _, key in V2_FLAGS do
					expect({ key = key, listed = listed[key] == true }).toEqual({ key = key, listed = true })
				end
				-- un interrupteur v2.0 se coupe en direct (LiveOps), sauf SchemaV2 (figé : jamais recoupé)
				expect(F.set("UpgradesScreen", false)).toBe(true)
				expect(F.get("UpgradesScreen")).toBe(false)
				expect(F.set("SchemaV2", false)).toBe(false)
				expect(F.get("SchemaV2")).toBe(true)
				expect(F.Static.SchemaV2).toBe(true)
				F.reset()
				expect(F.get("UpgradesScreen")).toBe(true)
			end
		)

		it("chaque interrupteur nommé par la configuration v2.0 existe", function()
			local h = Harness.new()
			local F = shared(h, "Config.Features")
			local IV2 = shared(h, "Config.IntentsV2")
			local U = shared(h, "Config.Upgrades")
			local named = {}
			for _, spec in IV2 do
				table.insert(named, spec.feature)
			end
			for _, list in { U.Families, U.ReadOnly, U.WorkshopRows } do
				for _, def in list do
					if def.feature ~= "" then
						table.insert(named, def.feature)
					end
				end
			end
			for _, key in named do
				-- un interrupteur booléen du contrat (ouvert ou non au lancement : lot I, journal I-19)
				expect({ key = key, known = type(F.Defaults[key]) == "boolean" }).toEqual({
					key = key,
					known = true,
				})
			end
		end)

		it(
			"schéma : la v1 reste écrite tant que SchemaV2 est coupé (defaults, OWNERS, VERSION)",
			function()
				-- serveur v1.3 (préréglage « v13 ») : chemin gardé tant que le code v1 existe (lot I, D10)
				local h = Harness.new({ flags = "v13" })
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				expect(Schema.VERSION).toBe(1)
				expect(Schema.LATEST).toBe(2)
				expect(Schema.defaults().version).toBe(1)
				expect(Tables.deepEqual(Schema.defaults(), Schema.defaultsV1())).toBe(true)
				expect(Tables.deepEqual(Schema.defaultsFor(1), Schema.defaultsV1())).toBe(true)
				expect(Tables.deepEqual(Schema.OWNERS, Schema.OWNERS_V1)).toBe(true)
				for _, key in V2_KEYS do
					expect({ key = key, v1 = Schema.defaults()[key] }).toEqual({ key = key, v1 = nil })
				end
				expect(string.find(Schema.OWNERS.ascend, "(réservé", 1, true)).toBe(1)
			end
		)

		it("schéma au lancement : SchemaV2 ouvert, la v2 est écrite (defaults, OWNERS, VERSION)", function()
			local h = Harness.new()
			local Schema = schema(h)
			local Tables = shared(h, "Util.Tables")
			expect(Schema.VERSION).toBe(2)
			expect(Schema.LATEST).toBe(2)
			expect(Schema.STORE_NAME).toBe("PlayerData_v1")
			expect(Schema.defaults().version).toBe(2)
			expect(Tables.deepEqual(Schema.defaults(), Schema.defaultsFor(2))).toBe(true)
			expect(Tables.deepEqual(Schema.OWNERS, Schema.ownersFor(2))).toBe(true)
			for _, key in V2_KEYS do
				expect({ key = key, v2 = Schema.defaults()[key] ~= nil }).toEqual({ key = key, v2 = true })
			end
			expect(Schema.OWNERS.ascend).toBe("SplorchService")
			expect(Schema.OWNERS.ascendDay).toBe("SplorchService")
			expect(Schema.defaults().ascendDay).toBe(0)
		end)

		it(
			"aucun service du serveur ne branche encore une intention v2.0 (déclarées, jamais écoutées)",
			function()
				local h = Harness.new()
				local IV2 = shared(h, "Config.IntentsV2")
				local scanned = 0
				local function scan(dir)
					for _, entry in fs.readDir(dir) do
						local full = dir .. "/" .. entry
						if fs.isDir(full) then
							scan(full)
						elseif string.match(entry, "%.luau$") then
							scanned += 1
							local source = fs.readFile(full)
							for name in IV2 do
								local used = string.find(source, '"' .. name .. '"', 1, true) ~= nil
								expect({ file = full, name = name, used = used }).toEqual({
									file = full,
									name = name,
									used = false,
								})
							end
						end
					end
				end
				-- le client peut déjà les envoyer derrière son interrupteur (paquets B2, B3) ; le serveur les
				-- branche en les déplaçant vers Config/Intents (note INT-V2-INTENTS). Catalogue vide depuis
				-- le lot A4 (journal A4-37) : la règle garde une intention v2.0 ajoutée plus tard ; le scan
				-- lit vraiment les fichiers du serveur
				scan("src/server")
				expect(scanned > 40).toBe(true)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Contrat v2 › Schéma v2", function()
		it(
			"defaultsFor(2) : sérialisable, accepté par le DataStore, une clé = un propriétaire",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local d = Schema.defaultsFor(2)
				expect(d.version).toBe(2)
				local store = h.game.DataStoreService:GetDataStore("SchemaV2Check")
				expect(function()
					store:SetAsync("k", d)
				end).notToThrow()
				local owners = Schema.ownersFor(2)
				local services = serverOrder()
				services.DataService = true
				services.MonetizationService = true
				for key in d do
					local owner = owners[key]
					local ok = owner ~= nil
						and (services[owner] == true or string.find(owner, "(réservé", 1, true) == 1)
					expect({ key = key, owner = owner, ok = ok }).toEqual({
						key = key,
						owner = owner,
						ok = true,
					})
				end
				for key in owners do
					expect({ key = key, present = d[key] ~= nil }).toEqual({ key = key, present = true })
				end
				-- le champ réservé de la v1 devient A ; chaque clé v2 a son propriétaire unique
				expect(owners.ascend).toBe("SplorchService")
				expect(owners.confetti).toBe("EconomyService")
				expect(owners.confettiTotal).toBe("EconomyService")
				expect(owners.bestR).toBe("SplorchService")
				expect(owners.memoryR).toBe("SplorchService") -- écrit par Prestige.apply (retour au record)
				expect(d.memoryR).toBe(0)
				expect(owners.season).toBe("QuestService")
				expect(Schema.OWNERS_V1.season).toBe("(réservé : saison)")
				for _, key in V2_KEYS do
					expect({ key = key, owned = owners[key] ~= nil }).toEqual({ key = key, owned = true })
				end
				-- deux appels : deux tables indépendantes
				local d2 = Schema.defaultsFor(2)
				d2.atelier[1] = 9
				expect(Schema.defaultsFor(2).atelier[1]).toBe(0)
			end
		)

		it(
			"chaque champ v1 reste dans le v2 avec la même valeur par défaut (seule version change)",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local v1 = leaves(Schema.defaultsV1(), "")
				local v2 = Schema.defaultsFor(2)
				for path, value in v1 do
					if path ~= "version" then
						expect({ path = path, value = get(v2, path) }).toEqual({ path = path, value = value })
					end
				end
			end
		)

		-- Lot A4 (docs/04 §27.2, journal A4-1, A4-2) : champs de la méta v2 et réglage « Montrer mon
		-- halo » (Config/Settings since = 2) : un profil v1 n'en porte jamais aucun
		it(
			"champs du lot A4 : dans defaultsFor(2), jamais dans defaultsV1() ni defaults() ; réglages « since »",
			function()
				-- serveur v1.3 (préréglage « v13 », lot I D10 : defaults() d'un serveur v1) ; au lancement,
				-- defaults() = defaultsFor(2) (cas « schéma au lancement »)
				local h = Harness.new({ flags = "v13" })
				local Schema = schema(h)
				local S = shared(h, "Config.Settings")
				local C = shared(h, "Config.Cosmetics")
				local d = Schema.defaultsFor(2)
				expect(d.stats.objectivesClaimed).toBe(0)
				expect(d.stats.tracksDone).toBe(0)
				expect(d.moon.sessions).toBe(0)
				expect(#C.WeeklyRotation).toBe(8)
				expect(d.weeklyTrack.won).toEqual({ 0 }) -- un bit par cosmétique de la semaine
				expect(d.weeklyTrack.play).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
				expect(d.weeklyTrack.playDay).toBe(0)
				expect(d.cosmetics.palette).toBe("")
				expect(d.cosmetics.cushions).toBe("")
				expect(d.settings.haloOn).toBe(true)
				for _, v1 in { Schema.defaultsV1(), Schema.defaults() } do
					expect(v1.version).toBe(1)
					expect(v1.stats.objectivesClaimed).toBeNil()
					expect(v1.stats.tracksDone).toBeNil()
					expect(v1.moon.sessions).toBeNil()
					expect(v1.weeklyTrack).toBeNil()
					expect(v1.cosmetics.palette).toBeNil()
					expect(v1.cosmetics.cushions).toBeNil()
					expect(v1.settings.haloOn).toBeNil()
				end
				-- règle « since » : un réglage sauvegardé est dans les valeurs par défaut de la version N
				-- exactement quand since ≤ N (absent = 1) ; un réglage de serveur jamais
				expect(S.haloOn.saved).toBe(true)
				expect(S.haloOn.since).toBe(2)
				for version = 1, 2 do
					local settings = Schema.defaultsFor(version).settings
					for key, def in S do
						local want = if def.saved and (def.since or 1) <= version then def.default else nil
						expect({ version = version, key = key, value = settings[key] }).toEqual({
							version = version,
							key = key,
							value = want,
						})
					end
					for key in settings do
						expect({ key = key, declared = S[key] ~= nil }).toEqual({ key = key, declared = true })
					end
				end
				-- la migration v1 → v2 les écrit (règle A2-3) : témoin v1.json migré
				local m = migrateFull(h, readV1())
				expect(m.settings.haloOn).toBe(true)
				expect(m.moon.sessions).toBe(0)
				expect(m.stats.objectivesClaimed + m.stats.tracksDone).toBe(0)
				expect(m.weeklyTrack.won).toEqual({ 0 })
				expect(m.cosmetics.palette .. m.cosmetics.cushions).toBe("")
			end
		)

		it("ensembles de bits : tableaux denses de mots de 32 bits ; tailles du GDD", function()
			local h = Harness.new()
			local Schema = schema(h)
			local Species = shared(h, "Config.Species")
			local U = shared(h, "Config.Upgrades")
			local d = Schema.defaultsFor(2)
			local function words(n)
				return math.max(1, math.ceil(n / 32))
			end
			for name, pair in
				{
					mastery = { d.mastery, words(#Species.List) },
					atelierCosmetics = { d.atelierCosmetics, words(U.CosmeticBits) },
					carnet = { d.carnet, 1 },
					decoOwned = { d.decoPerso.owned, 2 },
					trackClaimed = { d.weeklyTrack.claimed, 1 },
					trackWon = { d.weeklyTrack.won, 1 }, -- lot A4 : 8 cosmétiques de la semaine
				}
			do
				local list, n = pair[1], pair[2]
				expect({ name = name, n = #list }).toEqual({ name = name, n = n })
				for _, w in list do
					expect(w).toBe(0)
				end
			end
			expect(#d.atelier).toBe(#U.WorkshopRows)
			expect(#d.decorBuilds).toBe(18)
			expect(#d.decoPerso.slots).toBe(12)
			expect(d.tiles.star + d.tiles.gloves + d.tiles.school + d.tiles.monuments).toBe(0)
			expect(d.caps.fameSplorch + d.caps.starRain).toBe(0)
			expect(d.stats.upgradesBought + d.stats.petitSplorches).toBe(0)
			expect(d.onboarding.welcomeV2Pending).toBe(false)
			expect(d.season.frostDays).toBe(0)
			expect(d.season.premium).toBe(false) -- jamais effacé (règle du contrat)
		end)

		it(
			"profil v2 plein (104 squishies, 64 espèces, tout acheté) : JSON aller-retour exact, < 20 Ko",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				local d = Schema.defaultsFor(2)
				for i = 1, 104 do
					local uid = string.format("%06d", i)
					d.squishies[uid] = {
						s = 64,
						m = 9,
						st = 5,
						z = 1.2345678901234e299,
						zg = 123456789.25,
						bf = if i <= 3 then i else 0,
						lk = true,
						o = "crown",
						at = if i <= 24 then "pen" elseif i <= 84 then "dodo" else "mail",
						gd = 20759,
					}
				end
				for s = 1, 64 do
					d.dex.mut[s] = 1023
					d.dex.stars[s] = 31
					d.trophies[s] = 1.2345678901234e299 -- (Lune : certains doubles ne font pas l'aller-retour JSON exact)
				end
				d.mastery = { 4294967295, 4294967295 }
				for i = 1, #d.atelier do
					d.atelier[i] = 24
				end
				d.atelierCosmetics = { 2047 }
				d.decoPerso =
					{ owned = { 4294967295, 255 }, slots = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } }
				d.hearts.givenTo = {}
				for i = 1, 20 do
					table.insert(d.hearts.givenTo, 9007199254740 + i)
				end
				d.weeklyTrack.challenges = {
					{ id = 12, p = 30, done = true },
					{ id = 11, p = 5, done = true },
					{ id = 10, p = 2, done = false },
				}
				d.coins = 1e300
				d.confetti = 1e9
				d.confettiTotal = 1e9
				local json = serde.encode("json", d)
				expect({ bytes = #json, ok = #json < 20000 }).toEqual({ bytes = #json, ok = true })
				local back = serde.decode("json", json)
				expect(Tables.deepEqual(back, d)).toBe(true)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Contrat v2 › Migration v1 → v2", function()
		it("constantes figées de la migration = valeurs du GDD v2.0 (§4.26, §4.6)", function()
			local h = Harness.new()
			local m = schema(h).MIGRATION_V2
			expect(m.ConfettiBase).toBe(3)
			expect(m.CapR).toBe(20)
			expect(m.RecordBonus).toBe(10)
			expect(m.RecordBonusFrom).toBe(21)
			expect(m.OfferedPensAt).toEqual({ 2, 6, 11, 16 })
			expect(m.PensMax).toBe(14)
			expect(m.FullPenBonus).toBe(25)
		end)

		it("rattrapage des Confettis = cumul du GDD §4.26 (R1 4 … R30 600)", function()
			local h = Harness.new()
			local Schema = schema(h)
			for R, n in
				{
					[0] = 0,
					[1] = 4,
					[2] = 9,
					[5] = 30,
					[8] = 60,
					[10] = 85,
					[12] = 114,
					[15] = 165,
					[20] = 270,
					[25] = 435,
					[30] = 600,
				}
			do
				expect({ R = R, n = Schema.confettiCatchUp(R) }).toEqual({ R = R, n = n })
			end
		end)

		it("v1.json (version de test, Record R 12, Enclos 12/14) : rattrapage exact", function()
			local h = Harness.new()
			local d = migrateFull(h, readV1())
			expect(d.version).toBe(2)
			expect(d.R).toBe(12)
			expect(d.bestR).toBe(12)
			expect(d.ascend).toBe(0)
			-- places offertes aux Record R 2, 6, 11 : Enclos 12 → 14, la 3e tombe sur un enclos plein
			expect(d.tiles.pens).toBe(14)
			expect(d.confetti).toBe(114 + 25)
			expect(d.confettiTotal).toBe(114 + 25)
			expect(d.unlocksSeen).toBe(12)
			-- Carnet : somme des niveaux v1 (Tapis 7 + Décorations 9 + Enclos 12 + Lit 1)
			expect(d.stats.upgradesBought).toBe(29)
			expect(d.decorBuilds).toEqual({ 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
			expect(d.onboarding.welcomeV2Pending).toBe(true)
			expect(d.weeklyTrack.firstPeriodEnd).toBe(0) -- fixé par QuestService au premier chargement
			expect(d.tiles.star).toBe(0)
			expect(d.regainBonusA).toBe(0)
			expect(d.memoryR).toBe(0) -- aucun retour au record avant la v2.0 (INT-A1-MEMORY)
		end)

		-- Lot A2 (docs/04 §27.12 A2-3) : la migration ÉCRIT chaque champ que la v2 ajoute ; une valeur
		-- trouvée dans un profil v1 (essai, vieux bug) ne passe jamais en v2, rien de la v1 n'est perdu
		it(
			"profil v1 portant des champs v2 périmés : chacun repart de sa valeur v2 calculée ou par défaut",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				local stale = readV1()
				stale.bestR = 99
				stale.regainBonusA = 7
				stale.memoryR = 12
				stale.confetti = 5000
				stale.confettiTotal = 9000
				stale.atelier = { 3, 3, 3 }
				stale.atelierCosmetics = { 2047 }
				stale.decorBuilds = { 9, 9 }
				stale.carnet = { 255 }
				stale.weeklyTrack =
					{ period = 4, points = 99, claimed = { 4095 }, challenges = {}, firstPeriodEnd = 7 }
				stale.mastery = { 1 }
				stale.unlocksSeen = 300
				stale.decoPerso = { owned = { 1, 1 }, slots = { 1 } }
				stale.hearts = { givenDay = 9, givenTo = { 5 }, receivedTotal = 50 }
				stale.tiles.star, stale.tiles.gloves, stale.tiles.school, stale.tiles.monuments =
					8, 40, 20, 10
				stale.stats.upgradesBought, stale.stats.petitSplorches = 999, 77
				-- champs du lot A4 (journal A4-1) : aussi écrits à leur valeur v2 par la migration
				stale.weeklyTrack.won = { 255 }
				stale.weeklyTrack.play = { 86400, 1, 2 }
				stale.weeklyTrack.playDay = 20000
				stale.stats.objectivesClaimed, stale.stats.tracksDone = 100, 4
				stale.moon.sessions = 12
				stale.cosmetics.palette, stale.cosmetics.cushions = "candy", "pinkCushions"
				stale.settings.haloOn = false
				stale.onboarding.nextBuyShown = true
				stale.season.frostDays = 30
				stale.caps.fameSplorch, stale.caps.starRain = 50, 3
				stale.futureKey = { kept = true } -- clé inconnue de ce serveur : gardée
				local d = migrateFull(h, stale)
				local clean = migrateFull(h, readV1())
				local fromStale = Tables.deepCopy(d)
				fromStale.futureKey = nil
				expect(Tables.deepEqual(fromStale, clean)).toBe(true)
				expect(d.futureKey).toEqual({ kept = true })
				expect(d.bestR).toBe(12)
				expect(d.memoryR).toBe(0)
				expect(d.confetti).toBe(139)
				expect(d.moon.sessions).toBe(0)
				expect(d.settings.haloOn).toBe(true)
				expect(d.cosmetics.palette).toBe("")
				expect(d.weeklyTrack.play).toEqual({ 0, 0, 0, 0, 0, 0, 0 })
				-- chaque valeur v1 est gardée (season.premium compris)
				expect(d.season.premium).toBe(clean.season.premium)
			end
		)

		it("aucune donnée v1 perdue : chaque valeur v1 est gardée (sauf tiles.pens et version)", function()
			local h = Harness.new()
			local v1 = readV1()
			local before = leaves(v1, "")
			local d = migrateFull(h, readV1())
			local checked = 0
			for path, value in before do
				if path ~= "version" and path ~= "tiles.pens" then
					checked += 1
					expect({ path = path, value = get(d, path) }).toEqual({ path = path, value = value })
				end
			end
			expect(checked > 150).toBe(true)
			-- et chaque clé v2 existe après la migration
			for key in schema(h).ownersFor(2) do
				expect({ key = key, present = d[key] ~= nil }).toEqual({ key = key, present = true })
			end
		end)

		it(
			"aller-retour : v1 → v2 → JSON → v2 identique ; DataStore accepte le profil migré",
			function()
				local h = Harness.new()
				local Tables = shared(h, "Util.Tables")
				local d = migrateFull(h, readV1())
				local back = serde.decode("json", serde.encode("json", d))
				expect(Tables.deepEqual(back, d)).toBe(true)
				local store = h.game.DataStoreService:GetDataStore("MigratedCheck")
				expect(function()
					store:SetAsync("k", d)
				end).notToThrow()
			end
		)

		-- Sauvegarde-témoin v2 (docs/04 §16, §27.2) : v1.json migrée, figée dans le dépôt. Chaque
		-- valeur du témoin doit sortir de la migration telle quelle (une valeur de migration qui
		-- change fait échouer ce cas) ; un champ v2 ajouté plus tard au schéma ne le casse pas.
		-- Le témoin sert aussi de sauvegarde v2 réelle : chargé en v2, rien n'est perdu.
		it(
			"v2.json (témoin) : v1.json migrée redonne chaque valeur du témoin ; chargé en v2, rien ne change",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				local witness = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
				expect(witness.version).toBe(2)
				local expected = leaves(witness, "")
				local d = migrateFull(h, readV1())
				local checked = 0
				for path, value in expected do
					checked += 1
					expect({ path = path, value = get(d, path) }).toEqual({ path = path, value = value })
				end
				expect(checked > 200).toBe(true)
				-- chaque clé v2 est dans le témoin
				for key in Schema.ownersFor(2) do
					expect({ key = key, present = witness[key] ~= nil }).toEqual({ key = key, present = true })
				end
				-- sauvegarde v2 chargée par un serveur v2 : migrate(2 → 2) puis reconcile, rien de perdu
				local loaded = Schema.migrate(Tables.deepCopy(witness), 2, 2)
				Tables.reconcile(loaded, Schema.defaultsFor(2))
				for path, value in expected do
					expect({ path = path, value = get(loaded, path) }).toEqual({ path = path, value = value })
				end
			end
		)

		it(
			"idempotente : migrer deux fois = une fois ; un profil déjà v2 n'est jamais retouché",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				local once = migrateFull(h, readV1())
				local twice = Tables.deepCopy(once)
				Schema.migrate(twice, 1, 2)
				Schema.migrateV1toV2(twice)
				Tables.reconcile(twice, Schema.defaultsFor(2))
				expect(Tables.deepEqual(twice, once)).toBe(true)
				-- un v2 avec des Confettis dépensés : rien n'est recalculé
				local spent = Tables.deepCopy(once)
				spent.confetti = 3
				spent.tiles.pens = 9
				Schema.migrate(spent, 2, 2)
				Schema.migrateV1toV2(spent)
				expect(spent.confetti).toBe(3)
				expect(spent.tiles.pens).toBe(9)
			end
		)

		it(
			"places offertes : enclos vides → +1 niveau chacune ; enclos pleins → +25 Confettis chacune",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local low = Schema.defaultsV1()
				low.R = 16
				local a = Schema.migrate(low, 1, 2)
				expect(a.tiles.pens).toBe(4)
				expect(a.confetti).toBe(Schema.confettiCatchUp(16))
				local full = Schema.defaultsV1()
				full.R = 16
				full.tiles.pens = 14
				local b = Schema.migrate(full, 1, 2)
				expect(b.tiles.pens).toBe(14)
				expect(b.confetti).toBe(Schema.confettiCatchUp(16) + 4 * 25)
				-- nouveau joueur (R = 0) : rien d'offert, pas de carte « Bienvenue dans la v2 ! »
				local fresh = Schema.migrate(Schema.defaultsV1(), 1, 2)
				expect(fresh.confetti).toBe(0)
				expect(fresh.tiles.pens).toBe(0)
				expect(fresh.onboarding.welcomeV2Pending).toBe(false)
				expect(fresh.stats.upgradesBought).toBe(0)
			end
		)

		it(
			"sauvegarde abîmée : aucune erreur, valeurs sûres (R NaN, tiles illisible, stats absent)",
			function()
				local h = Harness.new()
				local Schema = schema(h)
				local Tables = shared(h, "Util.Tables")
				local cases = {
					{ R = 0 / 0, tiles = "x" },
					{ R = -5, tiles = { pens = 1e9, snack = "a" }, stats = 4 },
					{ R = 1e9, onboarding = false, ascend = 3 },
					{},
				}
				for i, raw in cases do
					local ok, out = pcall(function()
						local d = Schema.migrate(raw, 1, 2)
						Tables.reconcile(d, Schema.defaultsFor(2))
						return d
					end)
					expect({ case = i, ok = ok }).toEqual({ case = i, ok = true })
					expect(out.version).toBe(2)
					expect(out.bestR >= 0 and out.bestR <= 400).toBe(true)
					expect(out.ascend).toBe(0)
					expect(out.confetti == out.confettiTotal and out.confetti >= 0).toBe(true)
					expect(out.tiles.pens >= 0 and out.tiles.pens <= 14).toBe(true)
				end
			end
		)

		it("jeu de base : sans cible, migrate ne dépasse jamais Schema.VERSION (= 1)", function()
			-- serveur v1.3 (préréglage « v13 », lot I D10) ; au lancement : Migration_I
			local h = Harness.new({ flags = "v13" })
			local Schema = schema(h)
			local Tables = shared(h, "Util.Tables")
			local v1 = readV1()
			local copy = Tables.deepCopy(v1)
			Schema.migrate(copy, 1)
			expect(Tables.deepEqual(copy, v1)).toBe(true)
			local v0 = serde.decode("json", fs.readFile("tests/fixtures/profiles/v0.json"))
			local out = Schema.migrate(v0, 0)
			expect(out.bestR).toBeNil()
			expect(out.confetti).toBeNil()
		end)

		it("un serveur v1 ne corrompt jamais un profil v2 : chargement refusé, rien d'écrit", function()
			T.expectWarning("écrit par un schéma plus récent que v1")
			-- serveur v1 (préréglage « v13 », lot I D3 : déploiement, ancien serveur encore allumé)
			local h = Harness.new({ flags = "v13" })
			local Clock = shared(h, "Util.Clock")
			Clock.freeze(1800000000)
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			DS.Settings.LOCKED_RETRY_DELAY = 0.01
			local Tables = shared(h, "Util.Tables")
			local v2 = migrateFull(h, readV1())
			local store = h.game.DataStoreService:GetDataStore("PlayerData_v1")
			store:SetAsync("player_77", { data = v2, meta = { created = 1, lastSave = 2, saves = 9 } })
			local before = store:GetAsync("player_77")
			h:boot()
			local p = h:addPlayer({ userId = 77, name = "Vet" })
			h:settle(5)
			expect(DS.get(p)).toBeNil()
			expect(#h.log.kicks).toBe(1)
			expect(DS.saveNow(p)).toBe(false)
			h:removePlayer(p)
			h:settle(5)
			h:close()
			h:settle(3)
			local after = store:GetAsync("player_77")
			expect(Tables.deepEqual(after, before)).toBe(true)
			expect(after.data.version).toBe(2)
			expect(after.data.confetti).toBe(139)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Contrat v2 › Intentions, remotes, signaux, types", function()
		it(
			"chaque intention v2.0 : remote « event » déclaré, propriétaire de l'ordre serveur, arguments bornés",
			function()
				local h = Harness.new()
				local R = shared(h, "Remotes")
				local Intents = shared(h, "Config.Intents")
				local IV2 = shared(h, "Config.IntentsV2")
				local services = serverOrder()
				local n = 0
				for name, spec in IV2 do
					n += 1
					expect({ name = name, kind = R[name] }).toEqual({ name = name, kind = "event" })
					expect({ name = name, owner = services[spec.owner] == true }).toEqual({
						name = name,
						owner = true,
					})
					expect({ name = name, twice = Intents[name] ~= nil }).toEqual({
						name = name,
						twice = false,
					})
					expect(spec.rate[1] > 0 and spec.rate[2] > 0).toBe(true)
					expect(type(spec.feature)).toBe("string")
					for _, arg in spec.args do
						expect({ name = name, arg = arg.name, kind = ARG_KINDS[arg.kind] == true }).toEqual({
							name = name,
							arg = arg.name,
							kind = true,
						})
						if arg.kind == "int" then
							expect(arg.min ~= nil and arg.max ~= nil and arg.min <= arg.max).toBe(true)
						end
						if arg.kind == "str" or arg.kind == "uids" or arg.kind == "userIds" then
							expect(type(arg.max) == "number" and arg.max > 0).toBe(true)
						end
					end
				end
				-- 0 : BuyUpgrade (journal A2-8) puis JellyAscend (journal A2-23) sont passées dans
				-- Config/Intents avec leur handler (lot A2, note INT-V2-INTENTS), puis PlaceDeco, GiveHeart et
				-- SetPhotoMode (lot A4, étape 5, journal A4-37 : 3 → 0) ; jamais dans les deux catalogues
				expect(n).toBe(0)
				expect(IV2.BuyUpgrade).toBeNil()
				expect(Intents.BuyUpgrade.owner).toBe("EconomyService")
				expect(Intents.BuyUpgrade.activity).toBe(true)
				expect(R.BuyUpgrade).toBe("event")
				expect(IV2.JellyAscend).toBeNil()
				expect(Intents.JellyAscend.owner).toBe("SplorchService")
				expect(Intents.JellyAscend.activity).toBe(true)
				expect(Intents.JellyAscend.args).toEqual({ { name = "confirm", kind = "bool" } })
				expect(R.JellyAscend).toBe("event")
				-- lot A4 (N23, décision du propriétaire du 6 novembre, journal A4-12) : MenuActivity,
				-- navigation dans un menu ; intention d'interface (jamais une activité de jeu), sans
				-- argument, QuestService, une toutes les 10 s au plus (le client : une toutes les 20 s)
				expect(IV2.MenuActivity).toBeNil()
				expect(Intents.MenuActivity.owner).toBe("QuestService")
				expect(Intents.MenuActivity.activity).toBeNil()
				expect(Intents.MenuActivity.args).toEqual({})
				expect(Intents.MenuActivity.rate).toEqual({ 1, 10 })
				expect(R.MenuActivity).toBe("event")
				-- lot A4 (étape 5, journal A4-37) : Déco perso, cœurs, mode photo, même forme qu'avant le
				-- passage (débit, arguments ; GiveHeart seule intention de jeu des trois), CommunityService
				for _, name in { "PlaceDeco", "GiveHeart", "SetPhotoMode" } do
					expect({ name = name, v2 = IV2[name] }).toEqual({ name = name, v2 = nil })
					expect({ name = name, owner = Intents[name].owner }).toEqual({
						name = name,
						owner = "CommunityService",
					})
					expect({ name = name, remote = R[name] }).toEqual({ name = name, remote = "event" })
				end
				expect(Intents.PlaceDeco.rate).toEqual({ 4, 1 })
				expect(Intents.PlaceDeco.activity).toBeNil()
				expect(Intents.PlaceDeco.args).toEqual({
					{ name = "item", kind = "int", min = 0, max = 64 },
					{ name = "slot", kind = "int", min = 1, max = 12 },
				})
				expect(Intents.GiveHeart.activity).toBe(true)
				expect(Intents.GiveHeart.args).toEqual({ { name = "ownerId", kind = "userId" } })
				expect(Intents.SetPhotoMode.rate).toEqual({ 1, 1 })
				expect(Intents.SetPhotoMode.activity).toBeNil()
				expect(Intents.SetPhotoMode.args).toEqual({ { name = "on", kind = "bool" } })
				-- lot A4 (étape 6, D29, journal A4-44) : ClientMetric, faits mesurés par le client v2.0 ;
				-- DiagnosticsService, jamais une intention de jeu, une toutes les 5 s, valeur entière 0-1000
				expect(IV2.ClientMetric).toBeNil()
				expect(Intents.ClientMetric.owner).toBe("DiagnosticsService")
				expect(Intents.ClientMetric.activity).toBeNil()
				expect(Intents.ClientMetric.rate).toEqual({ 1, 5 })
				expect(Intents.ClientMetric.args).toEqual({
					{
						name = "kind",
						kind = "key",
						set = {
							"upgradeTimeout",
							"upgradeMode",
							"ascendPreview",
							"ascendDeclined",
							"textScale",
							"styleFallback",
							"visualBudget",
						},
					},
					{ name = "value", kind = "int", min = 0, max = 1000 },
				})
				expect(R.ClientMetric).toBe("event")
				-- ClientEvent reste celui de la v1.3 (deux sortes, analytique seulement)
				expect(Intents.ClientEvent.args[1].set).toEqual({ "qualityReduced", "shopOpened" })
				-- débits du GDD v2.0 §12.7
				expect(Intents.BuyUpgrade.rate).toEqual({ 10, 1 })
				expect(Intents.JellyAscend.rate).toEqual({ 1, 5 })
				expect(Intents.GiveHeart.rate).toEqual({ 2, 1 })
				-- mode : 1, 10 ou 0 (= Max) ; expectedLevel entier borné ; id ≤ 24 caractères
				expect(Intents.BuyUpgrade.args[1]).toEqual({ name = "id", kind = "str", max = 24 })
				expect(Intents.BuyUpgrade.args[2]).toEqual({ name = "mode", kind = "int", min = 0, max = 10 })
				expect(Intents.BuyUpgrade.args[3]).toEqual({
					name = "expectedLevel",
					kind = "int",
					min = 0,
					max = 64,
				})
				-- remotes serveur → client
				expect(R.UpgradeResult).toBe("event")
				expect(R.HelperPress).toBe("unreliable")
				-- habillages : aucune intention à part (EquipCosmetic « theme », décision C2)
				expect(R.SetRanchSkin).toBeNil()
			end
		)

		it("Net.setup crée les remotes v2.0 ; le démarrage reste sans erreur ni avertissement", function()
			local h = Harness.new()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			h:boot()
			local folder = h.game.ReplicatedStorage:FindFirstChild("Remotes")
			for _, name in
				{
					"BuyUpgrade",
					"JellyAscend",
					"PlaceDeco",
					"GiveHeart",
					"SetPhotoMode",
					"MenuActivity", -- lot A4 (N23, journal A4-12)
					"ClientMetric", -- lot A4 (étape 6, D29, journal A4-44)
					"UpgradeResult",
					"HelperPress",
				}
			do
				expect({ name = name, made = folder:FindFirstChild(name) ~= nil }).toEqual({
					name = name,
					made = true,
				})
			end
			local p = h:addPlayer({ userId = 202, name = "Zoe" })
			DS.waitFor(p, 2)
			h:step(1 / 60, 20)
			h:removePlayer(p)
			h:settle(3)
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end)

		it("signaux v2.0 du serveur", function()
			local h = Harness.new()
			local Signals = h:require("ServerScriptService.Server.Signals")
			for _, name in V2_SIGNALS do
				local s = Signals[name]
				expect({ name = name, ok = type(s) == "table" and type(s.Fire) == "function" }).toEqual({
					name = name,
					ok = true,
				})
			end
		end)

		it(
			"types v2.0 figés dans Shared/Types (charges utiles des deux voies) ; sortes v2.0 fusionnées dans CelebrateKind",
			function()
				local source = fs.readFile("src/shared/Types.luau")
				for _, name in V2_TYPES do
					local found = string.find(source, "export type " .. name .. " =", 1, true) ~= nil
					expect({ name = name, found = found }).toEqual({ name = name, found = true })
				end
				local snap = string.match(source, "export type UpgradeSnapshot = (%b{})")
				for _, field in { "coins", "confetti", "levels", "caps", "version" } do
					expect(string.find(snap, "\t" .. field .. ":", 1, true) ~= nil).toBe(true)
				end
				-- Lot I, étape 2 (INT-V2-CELEBRATE, journal I-13) : les sortes v2.0 sont fusionnées dans
				-- CelebrateKind ; le type à part CelebrateKindV2 n'existe plus (la table du §10.3 est vérifiée
				-- contre l'union par Contract_game)
				expect(string.find(source, "CelebrateKindV2", 1, true)).toBeNil()
				local union =
					string.match(source, "export type CelebrateKind =(.-)\nexport type CelebratePayload")
				expect(union ~= nil).toBe(true)
				for _, kind in
					{
						"petitSplorch",
						"ascend",
						"tier",
						"unlock2",
						"confetti",
						"trackTier",
						"carnet",
						"mastery",
						"regainDone",
						"recordStep",
						"welcomeV2",
					}
				do
					local found = string.find(union :: string, '"' .. kind .. '"', 1, true) ~= nil
					expect({ kind = kind, found = found }).toEqual({ kind = kind, found = true })
				end
			end
		)

		-- lot A4, étape 3 (D3, D4, D5, D26 ; journal A4-17)
		it(
			"Config/Events v2.0 : spectacle « ascend » = Balance.Ascend (10 s, coupure 12 s), Petit Splorch 5 points, points de la fête, priorité de la bannière « ascend »",
			function()
				local h = Harness.new()
				local E = h:require("ReplicatedStorage.Shared.Config.Events")
				local B = h:require("ReplicatedStorage.Shared.Config.Balance")
				expect(E.Spectacles.ascend.duration).toBe(B.Ascend.Duration)
				expect(E.Spectacles.ascend.hardCut).toBe(B.Ascend.HardCut)
				expect(E.Spectacles.ascend.duration).toBe(10)
				expect(E.Spectacles.ascend.hardCut).toBe(12)
				expect(B.Ascend.BurstAt < E.Spectacles.ascend.duration).toBe(true)
				-- GDD §4.23 (m9) : Petit Splorch 5, Grand Splorch 25 inchangé, Jelly Ascend 0 (aucune clé)
				expect(E.Gauge.Points.petitSplorch).toBe(5)
				expect(E.Gauge.Points.splorch).toBe(25)
				expect(E.Gauge.Points.ascend).toBeNil()
				expect(E.Fete.Points).toEqual({ splorch = 1, ascend = 1, mega = 3, party = 2 })
				expect(#E.Fete.Levels).toBe(5)
				for i = 2, #E.Fete.Levels do
					expect(E.Fete.Levels[i] > E.Fete.Levels[i - 1]).toBe(true)
				end
				-- priorité v2.0 à part de Priority (règle « banner.<sorte> » de Contract_game inchangée)
				expect(E.Banners.PriorityV2.ascend).toBe(1)
				expect(E.Banners.Priority.ascend).toBeNil()
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Contrat v2 › Textes EN et FR", function()
		it("clés v2.0 du contrat : EN et FR, mêmes variables, aucun symbole hors police", function()
			local h = Harness.new()
			local Strings = shared(h, "Localization.Strings")
			local function vars(s)
				local out = {}
				for v in string.gmatch(s, "{(%w+)}") do
					table.insert(out, v)
				end
				table.sort(out)
				return out
			end
			for _, key in V2_TEXT_KEYS do
				expect({ key = key, en = Strings.en[key] ~= nil, fr = Strings.fr[key] ~= nil }).toEqual({
					key = key,
					en = true,
					fr = true,
				})
				expect({ key = key, vars = vars(Strings.fr[key]) }).toEqual({
					key = key,
					vars = vars(Strings.en[key]),
				})
			end
			-- règle 18 du GDD §10.8 : → ✓ ★ ∞ ↺ sont des icônes dessinées, jamais des caractères
			for lang, list in Strings do
				for key, text in list do
					for _, ch in { "→", "✓", "★", "∞", "↺" } do
						if string.find(text, ch, 1, true) and string.find(key, "^upgrades%.") then
							error(lang .. " " .. key .. " contient « " .. ch .. " »")
						end
					end
				end
			end
		end)

		it("Annexe B : chaque liste nommée est complète dans les deux langues", function()
			local h = Harness.new()
			local Strings = shared(h, "Localization.Strings")
			for pattern, n in ANNEX_COUNTS do
				local en, fr = 0, 0
				for key in Strings.en do
					if string.find(key, "^" .. pattern) then
						en += 1
					end
				end
				for key in Strings.fr do
					if string.find(key, "^" .. pattern) then
						fr += 1
					end
				end
				expect({ pattern = pattern, en = en, fr = fr }).toEqual({ pattern = pattern, en = n, fr = n })
			end
			-- noms propres identiques dans les deux langues (GDD §15)
			for _, key in { "helper.name.pip", "helper.name.plume", "ascend.title" } do
				expect(Strings.fr[key]).toBe(Strings.en[key])
			end
		end)
	end)
end
