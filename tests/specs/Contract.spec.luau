--!nocheck
-- Contrat d'architecture (docs/04-architecture.md) : intégrité des configurations, registres
-- partagés, schéma v1, surface d'API des modules (stubs ou implémentés), ordres d'initialisation,
-- démarrage complet, et modules du contrat (Signals, Notify, Prefs, Format).
-- Un paquet peut AJOUTER des fonctions ; il ne doit jamais retirer ni renommer celles listées ici.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

-- Surface d'API publique du contrat : module → fonctions et signaux exigés
local API = {
	["ReplicatedStorage.Shared.Logic.Hash"] = { fns = { "u32", "unit", "int", "range", "pickWeighted", "string", "stream" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.EventClock"] = { fns = { "day", "week", "weekday", "weatherKeyForSlot", "weather", "nextWeather", "comet", "nextComet", "cometImpact", "cometContent", "beacon", "nextBeacon", "starfall", "nextStarfall", "nextEvent", "featuredSpecies", "weeklyWanderer", "grandParadeLegendary", "rotation" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.SeededPath"] = { fns = { "wander", "chordAt", "newChordCursor", "cometSky", "scatterPoint" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.WorldLayout"] = { fns = { "radiusXZ", "nestCenter", "nestCFrame", "gateCFrame", "inGateBox", "harborSlot", "inHarbor", "inOwnHarbor", "inBeaconRing", "zoneAt", "groundY", "clampToIsland", "spawnPoints", "perchCFrame", "welcomePoints", "observatoryCFrame", "constellationPoint", "boardCFrame", "pathStones", "lanterns", "decor" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.SnipRules"] = { fns = { "blockReason", "isImmune", "radius", "lossCap", "cutFrom", "boundsOverlap", "findCut", "applyCut" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.Formulas"] = { fns = { "upgradeCost", "upgradeMaxLevel", "congaCapacity", "congaBonus", "guardLinks", "lureRadius", "baseWalkSpeed", "walkSpeed", "dashCooldown", "nebbyMultiplier", "paradeValue", "passiveIncome", "multiplier", "offlineMultiplier", "paradeGlow", "offlineGlow", "settle", "glowForSeconds", "supernovaCost", "auraFor", "atlasPerchMilestones", "perchCount", "stashCap", "fuseCost", "releaseDust", "capScale", "effectiveCap", "beaconGoal", "wispCount", "rookieEligible" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.Trail"] = { fns = { "new", "reset", "setMaxLength", "head", "push", "sample", "findCut", "lastSeq", "since", "segmentDistanceXZ", "findCutSwept" }, signals = {  } },
	["ReplicatedStorage.Shared.Logic.PathCodec"] = { fns = { "encode", "decode", "split", "size" }, signals = {  } },
	["ReplicatedStorage.Shared.Render.NebbyBuilder"] = { fns = { "build", "setLod", "animate", "appendCFrames", "bodySize", "bodyColor", "partCount", "buildWisp", "buildCometOrb", "buildCometSky", "destroy" }, signals = {  } },
	["ServerScriptService.Server.Services.WorldService"] = { fns = { "Init", "Start", "root", "nest", "spawnLocation", "setNestAppearance", "setPerchCount", "beacon", "board", "partCount" }, signals = {  } },
	["ServerScriptService.Server.Services.NestService"] = { fns = { "Init", "Start", "slotOf", "playerAt", "inOwnHarbor", "teleportHome", "setPerchDisplay", "setPerchCount", "setting", "isZen", "snipsDisabled", "unlock", "grantTemporary", "hasUnlock" }, signals = {  } },
	["ServerScriptService.Server.Services.EconomyService"] = { fns = { "Init", "Start", "step", "settle", "refreshRate", "idleRate", "multiplier", "addGlow", "addGlowSeconds", "trySpendGlow", "addStardust", "addStardustCapped", "trySpendStardust", "paradeGlow", "upgradeLevel", "supernovas", "supernovaPreview", "grantPersonalBoost", "hasBoost", "setServerBoostUntil", "setCrewPresent", "setLineBanker" }, signals = {  } },
	["ServerScriptService.Server.Services.AtlasService"] = { fns = { "Init", "Start", "addNebbies", "record", "perched", "perchCount", "stashCap", "atlasCount", "hasEntry", "refreshPerches", "fuse", "fuseAll", "release", "setLock" }, signals = {  } },
	["ServerScriptService.Server.Services.SpawnService"] = { fns = { "Init", "Start", "step", "setModifiers", "setActivePlayers", "query", "positionOf", "canCatch", "consume", "spawnLoose", "spawnPersonal", "spawnWelcome", "spawnGuaranteedRare", "setDirected", "flush", "snapshotFor", "clearPlayer", "aliveCount", "toSpawn" }, signals = {  } },
	["ServerScriptService.Server.Services.EventService"] = { fns = { "Init", "Start", "step", "stepComet", "wispSweeps", "onWispSnip", "stepWisps", "flush", "isTruce", "beaconOpen", "onBeaconParade", "isCarrier", "carrier", "dropComet", "weatherForm", "serverBoostActive", "queueGlowParty", "glowPartyRemaining", "setActivePlayers", "runLiveOps", "snapshot" }, signals = {  } },
	["ServerScriptService.Server.Services.CrewService"] = { fns = { "Init", "Start", "step", "crewOf", "areCrewmates", "crewmates", "escortersOf", "banner", "snapshot" }, signals = {  } },
	["ServerScriptService.Server.Services.QuestService"] = { fns = { "Init", "Start", "step", "isRookie", "onSafeMoment", "onboardingStep", "drawDaily", "redeem" }, signals = {  } },
	["ServerScriptService.Server.Services.ProductService"] = { fns = { "Init", "Start", "glowAmount", "grant" }, signals = {  } },
	["ServerScriptService.Server.Services.LeaderboardService"] = { fns = { "Init", "Start", "step", "liveTop", "serverRecord", "weeklyTop" }, signals = {  } },
	["ServerScriptService.Server.Services.CongaService"] = { fns = { "Init", "Start", "tick", "lineLength", "lineCodes", "lineCapacity", "nodePositions", "forceParade", "isActive", "activeCount", "inputType", "worldSnapshot" }, signals = {  } },
	["ServerScriptService.Server.Util.MoveCheck"] = { fns = { "reset", "noteSpeed", "step", "isRestricted", "lastValid", "violations", "recentRewinds", "clear" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController"] = { fns = { "Init", "Start", "cycleClockTime", "currentPreset", "setPreset" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldStateController"] = { fns = { "Init", "Start", "isReady", "localSlot", "slotOf", "userAt", "line", "lineLength", "trail", "wilds", "wildPosition", "events", "wispPosition", "cometPosition", "crews", "crewOf", "isCrewmate", "requestWorld" }, signals = { "Ready", "LineOp", "Caught", "Banked", "Snipped", "Cleared", "OwnerChanged", "WildAdded", "WildRemoved", "EventChanged", "CrewsChanged", "PingShown" } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.CongaRenderer"] = { fns = { "Init", "Start", "nodePositions", "nodeModel", "wildModel", "renderedParts" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.VFXController"] = { fns = { "Init", "Start", "floatText", "ring", "burst", "pillar", "fovPunch", "haptic", "fireworks", "playDash", "playUpgrade", "playSupernova" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController"] = { fns = { "Init", "Start", "dash", "dashReadyAt", "inputType", "openPingWheel", "closePingWheel", "ping" }, signals = { "Dashed", "InputTypeChanged", "CheerRequested", "MinimapToggled" } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.OnboardingController"] = { fns = { "Init", "Start", "step", "currentHint" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.PanelController"] = { fns = { "Init", "Start", "open", "close", "back", "toggle", "current", "hasAction", "nextTab" }, signals = { "Opened", "Closed", "BadgeChanged" } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.ScreenFX"] = { fns = { "Init", "Start", "stamp", "flyCoins", "floater", "vignette", "confetti" }, signals = { "FeedbackReceived", "Celebrated" } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Banners"] = { fns = { "Init", "Start", "show", "queued" }, signals = { "Shown" } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.HUD"] = { fns = { "Init", "Start", "reveal", "isRevealed", "revealAll", "anchor", "attention" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Minimap"] = { fns = { "Init", "Start", "setExpanded", "toggle", "project" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Upgrades"] = { fns = { "build", "onOpen", "onClose", "hasAction" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Supernova"] = { fns = { "build", "onOpen", "onClose", "hasAction" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Collection"] = { fns = { "build", "onOpen", "onClose", "hasAction", "selectTab" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Goals"] = { fns = { "build", "onOpen", "onClose", "hasAction", "selectTab" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Shop"] = { fns = { "build", "onOpen", "onClose", "hasAction", "selectTab" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Crew"] = { fns = { "build", "onOpen", "onClose", "hasAction", "showInvite" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Settings"] = { fns = { "build", "onOpen", "onClose", "hasAction" }, signals = {  } },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.ReturnScreen"] = { fns = { "build", "onOpen", "onClose", "hasAction", "present" }, signals = {  } },
}

local SERVER_ORDER = {
	"DataService",
	"MonetizationService",
	"WorldService",
	"NestService",
	"EconomyService",
	"AtlasService",
	"SpawnService",
	"EventService",
	"CrewService",
	"QuestService",
	"ProductService",
	"LeaderboardService",
	"CongaService",
}

local CLIENT_ORDER = {
	"Client.UI.Root",
	"Client.Controllers.StateController",
	"Client.Controllers.AudioController",
	"Client.Util.Prefs",
	"Client.Controllers.WorldFXController",
	"Client.Controllers.WorldStateController",
	"Client.Controllers.LightingController",
	"Client.Controllers.CongaRenderer",
	"Client.Controllers.VFXController",
	"Client.UI.ScreenFX",
	"Client.UI.Banners",
	"Client.Controllers.PanelController",
	"Client.Controllers.InputController",
	"Client.UI.HUD",
	"Client.UI.Minimap",
	"Client.Controllers.OnboardingController",
}

local REMOTES = {
	DataSnapshot = "event",
	DataPatch = "event",
	RequestSnapshot = "event",
	Dash = "event",
	BuyUpgrade = "event",
	Supernova = "event",
	Fuse = "event",
	FuseAll = "event",
	Release = "event",
	SetLock = "event",
	ClaimDaily = "event",
	ClaimQuest = "event",
	RerollQuest = "event",
	CrewInvite = "event",
	CrewRespond = "event",
	CrewLeave = "event",
	Ping = "event",
	Cheer = "event",
	SetSetting = "event",
	SetInputType = "event",
	EquipCosmetic = "event",
	RequestWorld = "event",
	RequestPath = "event",
	AdminCommand = "event",
	RedeemCode = "func",
	PathStream = "unreliable",
	PathSnapshot = "event",
	WorldSnapshot = "event",
	LineEvent = "event",
	WildEvent = "event",
	SnipEvent = "event",
	EventState = "event",
	Banner = "event",
	Feedback = "event",
	Celebrate = "event",
	CrewState = "event",
	CrewInvitePrompt = "event",
	CheerPrompt = "event",
	PingShow = "event",
}

local GOAL_KINDS = {
	catch = true,
	catchRarity = true,
	catchWeather = true,
	catchZone = true,
	parades = true,
	paradeSize = true,
	paradeIdle = true,
	bankCount = true,
	bankRarity = true,
	beaconFeed = true,
	beaconWin = true,
	cometParticipate = true,
	cometHold = true,
	weatherOrComet = true,
	wispPop = true,
	dash = true,
	upgrades = true,
	upgrade = true,
	perches = true,
	snipNebbies = true,
	escort = true,
	fusions = true,
	idle = true,
	cheers = true,
	atlasNew = true,
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	local function sum(list, field)
		local s = 0
		for _, x in list do
			s += x[field]
		end
		return s
	end

	local function hasString(Strings, key)
		return Strings.en[key] ~= nil and Strings.fr[key] ~= nil
	end

	describe("Contrat › Config/Nebbies", function()
		local h = Harness.new()
		local N = shared(h, "Config.Nebbies")

		it("36 espèces, identifiants définitifs et clés uniques", function()
			expect(#N.Species).toBe(36)
			local keys = {}
			for i, def in N.Species do
				expect(def.id).toBe(i)
				expect(keys[def.key]).toBeNil()
				keys[def.key] = true
				expect(N.byKey[def.key]).toBe(i)
				expect(#def.archetypes >= 1 and #def.archetypes <= 2).toBe(true)
				expect(N.Rarities[def.rarity] ~= nil).toBe(true)
			end
			expect(N.Species[1].key).toBe("puffkin")
			expect(N.Species[20].key).toBe("daybreak_puff")
			expect(N.Species[36].key).toBe("grand_nebula")
			expect(N.Species[36].hsvAccent).toBe(true)
		end)

		it("répartition MVP 7/6/6/5/3/2/1 et complète 8/7/7/6/4/3/1 (§5.1)", function()
			local mvp, full = {}, {}
			for _, def in N.Species do
				full[def.rarity] = (full[def.rarity] or 0) + 1
				if def.version == "mvp" then
					mvp[def.rarity] = (mvp[def.rarity] or 0) + 1
				end
			end
			expect(mvp).toEqual({ 7, 6, 6, 5, 3, 2, 1 })
			expect(full).toEqual({ 8, 7, 7, 6, 4, 3, 1 })
			expect(N.atlasTotal()).toBe(150)
			expect(#N.enabledForms()).toBe(5)
			expect(N.isFormEnabled(4)).toBe(false)
			expect(#N.speciesOfRarity(1)).toBe(7)
			expect(#N.speciesOfRarity(7)).toBe(1)
		end)

		it("valeurs de rareté du §4.2 (parade = 20 × passif, Cosmique non libérable)", function()
			local passive = { 1, 4, 15, 60, 300, 1500, 10000 }
			for r = 1, 7 do
				local def = N.Rarities[r]
				expect(def.passive).toBe(passive[r])
				expect(def.parade).toBe(20 * def.passive)
				if r < 7 then
					expect(def.dust).toBe(def.passive)
				else
					expect(def.dust).toBeNil()
				end
			end
		end)

		it("formes, variantes et étoiles (§4.4, §4.13)", function()
			local mults = { [0] = 1, 2, 2.5, 3, 4, 6 }
			for f = 0, 5 do
				expect(N.Forms[f].mult).toBe(mults[f])
				expect(N.Forms[f].id).toBe(f)
			end
			expect(N.Variants.golden.mult * N.Variants.huge.mult * N.Forms[5].mult).toBe(72)
			expect(N.Variants.golden.bit + N.Variants.huge.bit + N.Variants.starborn.bit).toBe(7)
			expect(N.Stars).toEqual({ 1, 3.5, 12, 43, 150 })
		end)

		it("pack / unpack aller-retour sur tous les codes possibles", function()
			for s = 1, 36 do
				for f = 0, 5 do
					for v = 0, 7 do
						local code = N.pack(s, f, v)
						expect(code < 4096).toBe(true)
						local s2, f2, v2 = N.unpack(code)
						expect(s2 == s and f2 == f and v2 == v).toBe(true)
						expect(N.isValidCode(code)).toBe(true)
					end
				end
			end
			for _, bad in { 0, -1, 4096, 1.5, 0 / 0, math.huge, "12", N.pack(37, 0, 0), N.pack(1, 6, 0) } do
				expect(N.isValidCode(bad)).toBe(false)
			end
		end)

		it("bits de l'Atlas (7 mots) et des badges (4 mots)", function()
			expect(N.atlasIndex(36, 5)).toBe(215)
			expect(N.atlasIndex(36, 5) < 7 * 32).toBe(true)
			expect(N.badgeIndex("starborn", 36) < 4 * 32).toBe(true)
			local words = { 0, 0, 0, 0, 0, 0, 0 }
			expect(N.setBit(words, 215)).toBe(true)
			expect(N.setBit(words, 215)).toBe(false)
			expect(N.testBit(words, 215)).toBe(true)
			expect(N.testBit(words, 214)).toBe(false)
			expect(N.setBit(words, 31)).toBe(true)
			expect(words[1]).toBe(2147483648)
		end)
	end)

	describe("Contrat › Config (zones, événements, équilibrage, objectifs)", function()
		local h = Harness.new()
		local Z = shared(h, "Config.Zones")
		local E = shared(h, "Config.Events")
		local B = shared(h, "Config.Balance")
		local Q = shared(h, "Config.Quests")
		local N = shared(h, "Config.Nebbies")

		it("zones : probabilités à 100 %, anneaux contigus (§4.3)", function()
			expect(#Z.List).toBe(3)
			for _, zone in Z.List do
				expect(sum(zone.odds, "weight")).toBeNear(100, 1e-9)
				expect(zone.inner < zone.outer).toBe(true)
			end
			expect(Z.byKey.glade.outer).toBe(Z.byKey.meadow.inner)
			expect(Z.byKey.crater.outer).toBe(Z.byKey.glade.inner)
			expect(Z.byKey.crater.inner).toBe(Z.Beacon.Radius)
			expect(Z.byKey.meadow.cap + Z.byKey.glade.cap + Z.byKey.crater.cap).toBe(74)
			local perches = 0
			for _, ring in Z.Perches.Rings do
				perches += ring.count
			end
			expect(perches).toBe(B.Perches.Max)
			expect(Z.Nests.HarborRadius).toBe(B.Snip.HarborRadius)
		end)

		it("météo : poids MVP = 100 ; rotations hebdomadaires cohérentes (§4.15.1, §5.1)", function()
			local total = 0
			for _, w in E.Weather.Kinds do
				if N.isVersionEnabled(w.version) then
					total += w.weight
				end
				if w.form then
					expect(N.Forms[w.form] ~= nil).toBe(true)
				end
				expect(E.Lighting.Presets[w.lighting] ~= nil).toBe(true)
			end
			expect(total).toBe(100)
			expect(#E.Rotations.WeeklyWanderer).toBe(5)
			for _, s in E.Rotations.WeeklyWanderer do
				expect(N.Species[s].rarity).toBe(4)
			end
			for _, s in E.Rotations.GrandParadeLegendary do
				expect(N.Species[s].rarity).toBe(5)
			end
			expect(#E.Rotations.FeaturedSpecies).toBe(12)
			expect(E.Beacon.Offset + B.Beacon.Duration <= E.Beacon.Period).toBe(true)
		end)

		it("équilibrage : tables du §4 cohérentes", function()
			expect(#B.Supernova.Costs).toBe(12)
			for i = 2, #B.Supernova.Costs do
				expect(B.Supernova.Costs[i] > B.Supernova.Costs[i - 1]).toBe(true)
			end
			expect(B.Supernova.Costs[1]).toBe(400000)
			expect(B.Starforge.Costs).toEqual({ 25, 120, 600, 3000 })
			expect(B.Conga.BaseCapacity + B.Upgrades.conga.MaxAbsolute).toBe(B.Conga.AbsoluteMax)
			expect(B.Perches.Base + B.Upgrades.perches.Max + B.Perches.AtlasMilestoneMax + B.Perches.ExtraPerchesPass).toBe(
				B.Perches.Max
			)
			expect(B.Guard.Base + B.Upgrades.guard.Max * B.Guard.PerLevel).toBe(B.Guard.Max)
			expect(#B.UpgradeOrder).toBe(5)
			for _, track in B.UpgradeOrder do
				expect(B.Upgrades[track] ~= nil).toBe(true)
			end
			expect(sum(B.Comet.Content, "weight")).toBe(100)
		end)

		it("objectifs : 7 quêtes d'accueil, 25 quotidiennes (8/9/8), calendrier de 7 jours (§7)", function()
			expect(#Q.Onboarding).toBe(7)
			for i, q in Q.Onboarding do
				expect(q.id).toBe("q" .. i)
				expect(GOAL_KINDS[q.goal.kind]).toBe(true)
			end
			expect(#Q.Daily).toBe(25)
			local tiers = { easy = 0, medium = 0, hard = 0 }
			for i, q in Q.Daily do
				expect(q.id).toBe(i)
				expect(GOAL_KINDS[q.goal.kind]).toBe(true)
				tiers[q.tier] += 1
			end
			expect(tiers).toEqual({ easy = 8, medium = 9, hard = 8 })
			expect(Q.Daily[12].pvp).toBe(true)
			expect(Q.Daily[23].pvp).toBe(true)
			expect(Q.Daily[14].crew).toBe(true)
			expect(#Q.Calendar).toBe(7)
			expect(Q.Calendar[5].species).toBe(N.Named.CalendarDay5)
			expect(#Q.Atlas.Milestones).toBe(12)
			local perches = 0
			for i, m in Q.Atlas.Milestones do
				expect(m.entries).toBe(i * Q.Atlas.Every)
				perches += m.perch or 0
			end
			expect(perches).toBe(B.Perches.AtlasMilestoneMax)
		end)
	end)

	describe("Contrat › Monétisation, cosmétiques, réglages, sons", function()
		local h = Harness.new()
		local M = shared(h, "Config.Monetization")
		local C = shared(h, "Config.Cosmetics")
		local S = shared(h, "Config.Settings")
		local Sounds = shared(h, "Config.Sounds")
		local Strings = shared(h, "Localization.Strings")

		it("6 passes et 6 produits aux prix du §8, IDs à 0, textes EN/FR", function()
			local passPrices = { VIPStar = 199, DoubleGlow = 299, NightShift = 99, ExtraPerches = 149, StashPlus = 99, CongaStyles = 79 }
			local productPrices = { GlowPouch = 25, GlowSack = 89, GlowCrate = 199, GlowParty = 99, StardustJar = 49, StarterKit = 49 }
			local n = 0
			for key, def in M.Passes do
				n += 1
				expect(def.price).toBe(passPrices[key])
				expect(def.id).toBe(0)
				expect(hasString(Strings, def.nameKey) and hasString(Strings, def.descKey)).toBe(true)
			end
			expect(n).toBe(6)
			n = 0
			for key, def in M.Products do
				n += 1
				expect(def.price).toBe(productPrices[key])
				expect(def.id).toBe(0)
				expect(hasString(Strings, def.nameKey) and hasString(Strings, def.descKey)).toBe(true)
			end
			expect(n).toBe(6)
			expect(M.Products.StarterKit.oncePerAccount).toBe(true)
		end)

		it("cosmétiques : 12 couleurs de Nid, sources valides, textes EN/FR", function()
			expect(#C.NestColors).toBe(12)
			local function checkSource(src)
				if src.kind == "pass" then
					expect(M.Passes[src.pass] ~= nil).toBe(true)
				elseif src.kind == "product" then
					expect(M.Products[src.product] ~= nil).toBe(true)
				end
			end
			for id, def in C.Styles do
				checkSource(def.source)
				expect(hasString(Strings, "style." .. id)).toBe(true)
			end
			for id, def in C.Titles do
				checkSource(def.source)
				expect(hasString(Strings, "title." .. id)).toBe(true)
			end
			for id, def in C.Themes do
				checkSource(def.source)
				expect(hasString(Strings, "theme." .. id)).toBe(true)
			end
			for id in C.Auras do
				expect(hasString(Strings, "aura." .. id)).toBe(true)
			end
			for _, pass in M.Passes do
				for _, style in pass.styles or {} do
					expect(C.Styles[style] ~= nil).toBe(true)
				end
			end
		end)

		it("réglages : types, valeurs par défaut et textes", function()
			for key, def in S do
				expect(type(def.default)).toBe(def.kind)
				expect(hasString(Strings, "settings." .. key)).toBe(true)
			end
			expect(S.zen.harborOnly).toBe(true)
			expect(S.privateNoSnip.saved).toBe(false)
		end)

		it("sons : toutes les clés du §9 existent et sont vides par défaut", function()
			for _, key in
				{ "Catch", "CatchRare", "Snip", "Scatter", "Bank", "Dash", "CometWarn", "CometImpact", "CometSwipe" }
			do
				expect(Sounds[key] ~= nil and Sounds[key].id == "").toBe(true)
			end
			for _, key in { "BeaconStart", "BeaconWin", "WispPop", "Supernova", "Ping", "Cheer", "Click", "Coin" } do
				expect(Sounds[key] ~= nil and Sounds[key].id == "").toBe(true)
			end
		end)
	end)

	describe("Contrat › Localisation", function()
		local h = Harness.new()
		local L = shared(h, "Localization")
		local Strings = shared(h, "Localization.Strings")
		local N = shared(h, "Config.Nebbies")
		local E = shared(h, "Config.Events")
		local Q = shared(h, "Config.Quests")
		local Z = shared(h, "Config.Zones")

		it("parité stricte EN ↔ FR", function()
			expect(#L.missingKeys("fr")).toBe(0)
			for key in Strings.fr do
				expect(Strings.en[key] ~= nil).toBe(true)
			end
		end)

		it("toute clé référencée par la configuration existe", function()
			for _, def in N.Rarities do
				expect(hasString(Strings, "rarity." .. def.key)).toBe(true)
			end
			for f = 0, 5 do
				expect(hasString(Strings, "form." .. N.Forms[f].key)).toBe(true)
			end
			for _, def in N.Variants do
				expect(hasString(Strings, "variant." .. def.key)).toBe(true)
			end
			for _, zone in Z.List do
				expect(hasString(Strings, "zone." .. zone.key)).toBe(true)
			end
			for _, w in E.Weather.Kinds do
				expect(hasString(Strings, "weather." .. w.key)).toBe(true)
			end
			for _, q in Q.Onboarding do
				expect(hasString(Strings, "quest.onboarding." .. q.id)).toBe(true)
				expect(hasString(Strings, q.hint)).toBe(true)
			end
			for _, q in Q.Daily do
				expect(hasString(Strings, "quest.daily." .. q.id)).toBe(true)
				expect(hasString(Strings, "quest.daily." .. q.id .. ".desc")).toBe(true)
			end
			for i = 1, 6 do
				expect(hasString(Strings, "ping." .. i)).toBe(true)
			end
			for _, status in { "ok", "invalid", "expired", "used", "busy" } do
				expect(hasString(Strings, "code." .. status)).toBe(true)
			end
		end)

		it("les variables {x} sont identiques en EN et en FR", function()
			local function vars(s)
				local out = {}
				for name in string.gmatch(s, "{(%w+)}") do
					out[name] = true
				end
				return out
			end
			for key, en in Strings.en do
				expect({ key = key, vars = vars(Strings.fr[key]) }).toEqual({ key = key, vars = vars(en) })
			end
		end)
	end)

	describe("Contrat › Remotes", function()
		it("chaque remote du §12.5 est déclaré avec le bon type, et rien d'autre", function()
			local h = Harness.new()
			local R = shared(h, "Remotes")
			for name, kind in REMOTES do
				expect({ name = name, kind = R[name] }).toEqual({ name = name, kind = kind })
			end
			for name in R do
				expect(REMOTES[name] ~= nil).toBe(true)
			end
		end)
	end)

	describe("Contrat › Schéma v1", function()
		it("valeurs par défaut sérialisables, une clé = un propriétaire, clés privées", function()
			local h = Harness.new()
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local d = Schema.defaults()
			expect(d.version).toBe(1)
			local store = h.game.DataStoreService:GetDataStore("SchemaCheck")
			expect(function()
				store:SetAsync("k", d)
			end).notToThrow()
			for key in d do
				expect({ key = key, owned = Schema.OWNERS[key] ~= nil }).toEqual({ key = key, owned = true })
			end
			for key in Schema.OWNERS do
				expect(d[key] ~= nil).toBe(true)
			end
			expect(Schema.PRIVATE_KEYS).toEqual({ receipts = true, codes = true, flags = true })
			expect(#d.atlas).toBe(7)
			expect(#d.badges).toBe(4)
			expect(d.settings.zen).toBe(false)
			expect(d.settings.lang).toBe("auto")
			expect(d.settings.privateNoSnip).toBeNil()
			expect(d.caps.duo).toBe(false)
		end)

		it("migre la sauvegarde-témoin v0 (tests/fixtures/profiles/v0.json)", function()
			local h = Harness.new()
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local Tables = shared(h, "Util.Tables")
			local v0 = serde.decode("json", fs.readFile("tests/fixtures/profiles/v0.json"))
			local data = Schema.migrate(v0, 0)
			Tables.reconcile(data, Schema.defaults())
			expect(data.glow).toBe(1234)
			expect(data.coins).toBe(1234)
			expect(data.passes.VIPStar).toBe(true)
			expect(data.receipts[1]).toBe("achat-ancien-1")
			expect(data.upgrades.perches).toBe(0)
			-- une migration ne repart jamais d'un Glow déjà présent
			local again = Schema.migrate({ coins = 5, glow = 9 }, 0)
			expect(again.glow).toBe(9)
		end)
	end)

	describe("Contrat › Surface d'API des modules", function()
		it("chaque module expose les fonctions et signaux du contrat", function()
			local hs = Harness.new({ mode = "server" })
			local hc = Harness.new({ mode = "client" })
			for path, spec in API do
				local h = if string.find(path, "StarterPlayer", 1, true) then hc else hs
				local ok, mod = pcall(function()
					return h:require(path)
				end)
				expect({ path = path, loaded = ok }).toEqual({ path = path, loaded = true })
				for _, fn in spec.fns do
					expect({ path = path, fn = fn, kind = type(mod[fn]) }).toEqual({ path = path, fn = fn, kind = "function" })
				end
				for _, sig in spec.signals do
					local s = mod[sig]
					expect({ path = path, signal = sig, ok = type(s) == "table" and type(s.Connect) == "function" }).toEqual({
						path = path,
						signal = sig,
						ok = true,
					})
				end
			end
		end)

		it("Init() et Start() de chaque service et contrôleur existent", function()
			local hs = Harness.new({ mode = "server" })
			for _, name in SERVER_ORDER do
				local m = hs:require("ServerScriptService.Server.Services." .. name)
				expect({ name = name, init = type(m.Init), start = type(m.Start) }).toEqual({
					name = name,
					init = "function",
					start = "function",
				})
			end
			local hc = Harness.new({ mode = "client" })
			-- modules du socle existant : Main tolère l'absence d'Init (WorldFXController) ou de Start (Root)
			local FOUNDATION = { ["Client.UI.Root"] = true, ["Client.Controllers.WorldFXController"] = true }
			for _, path in CLIENT_ORDER do
				local m = hc:require("StarterPlayer.StarterPlayerScripts." .. path)
				if FOUNDATION[path] then
					expect({ path = path, any = type(m.Init) == "function" or type(m.Start) == "function" }).toEqual({
						path = path,
						any = true,
					})
				else
					expect({ path = path, init = type(m.Init), start = type(m.Start) }).toEqual({
						path = path,
						init = "function",
						start = "function",
					})
				end
			end
		end)
	end)

	describe("Contrat › Ordres d'initialisation (GDD §12.3)", function()
		local function orderIn(source, names, prefix)
			local last = 0
			for _, name in names do
				local needle = prefix .. name
				local pos = string.find(source, needle, 1, true)
				expect({ name = name, found = pos ~= nil }).toEqual({ name = name, found = true })
				expect({ name = name, after = pos > last }).toEqual({ name = name, after = true })
				last = pos
			end
		end

		it("Main.server.luau charge les 13 services dans l'ordre du contrat", function()
			local source = fs.readFile("src/server/Main.server.luau")
			orderIn(source, SERVER_ORDER, '"')
			local count = 0
			for _ in string.gmatch(source, '\n\t"%w+Service",') do
				count += 1
			end
			expect(count).toBe(#SERVER_ORDER)
		end)

		it("Main.client.luau charge les 16 modules dans l'ordre du contrat", function()
			local source = fs.readFile("src/client/Main.client.luau")
			orderIn(source, CLIENT_ORDER, "\t")
		end)
	end)

	describe("Contrat › Démarrage complet", function()
		it("le serveur démarre, accueille, fait avancer le temps et libère des joueurs sans erreur", function()
			local h = Harness.new()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			h:boot()
			local a = h:addPlayer({ userId = 101, name = "Mira" })
			local b = h:addPlayer({ userId = 102, name = "Noah", locale = "fr-fr" })
			DS.waitFor(a, 2)
			DS.waitFor(b, 2)
			h:step(1 / 60, 30)
			h:respawn(a)
			h:step(1 / 60, 10)
			h:removePlayer(b)
			h:settle(3)
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)

		it("src/first est monté dans ReplicatedFirst et l'écran de chargement s'exécute", function()
			local h = Harness.new({ mode = "client" })
			local loading = h:find("ReplicatedFirst.Loading")
			expect(loading.ClassName).toBe("LocalScript")
			expect(function()
				h:run("ReplicatedFirst.Loading")
			end).notToThrow()
			h:step(1 / 60, 5)
			expect(#h.errors).toBe(0)
		end)

		it("le client démarre avec tous les contrôleurs et reçoit son profil", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			h:boot()
			local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", Schema.defaults())
			h:step(1 / 60, 20)
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end)
	end)

	describe("Contrat › Signals et Notify (serveur)", function()
		it("chaque signal du bus est un Signal utilisable", function()
			local h = Harness.new()
			local Signals = h:require("ServerScriptService.Server.Signals")
			local n = 0
			for name, sig in Signals do
				n += 1
				expect({ name = name, ok = type(sig.Connect) == "function" and type(sig.Fire) == "function" }).toEqual({
					name = name,
					ok = true,
				})
			end
			expect(n >= 25).toBe(true)
		end)

		it("Notify envoie Feedback, Celebrate et bannières aux bons destinataires", function()
			local h = Harness.new()
			h:boot()
			local Notify = h:require("ServerScriptService.Server.Util.Notify")
			local Signals = h:require("ServerScriptService.Server.Signals")
			local p = h:addPlayer({ userId = 7, name = "Lea" })
			Notify.feedback(p, "feedback.notEnoughGlow", { missing = 1200 }, "error")
			Notify.celebrate(p, "upgrade", { track = "conga", level = 4 })
			Notify.personalBanner(p, "rookieEnd")
			local fb = h:sentTo(p, "Feedback")
			expect(#fb).toBe(1)
			expect(fb[1][1]).toEqual({ key = "feedback.notEnoughGlow", vars = { missing = 1200 }, tone = "error" })
			local cel = h:sentTo(p, "Celebrate")
			expect(cel[1][1].kind).toBe("upgrade")
			expect(cel[1][1].data.level).toBe(4)
			local ban = h:sentTo(p, "Banner")
			expect(ban[1][1].personal).toBe(true)
			expect(ban[1][1].priority).toBe(1)
			local seen = nil
			Signals.BannerRequested:Connect(function(kind, args, source)
				seen = { kind = kind, n = args.n, source = source }
			end)
			Notify.banner("megaParade", { n = 31 }, p)
			h:settle(1)
			expect(seen).toEqual({ kind = "megaParade", n = 31, source = p })
			h:removePlayer(p)
			Notify.feedback(p, "feedback.maxLevel")
			expect(#h:sentTo(p, "Feedback")).toBe(1)
		end)

		it("chaque bannière a une priorité et un texte EN/FR", function()
			local h = Harness.new()
			local Notify = h:require("ServerScriptService.Server.Util.Notify")
			local Strings = shared(h, "Localization.Strings")
			for kind, prio in Notify.BANNER_PRIORITY do
				expect(prio >= 1 and prio <= 7).toBe(true)
				expect({ kind = kind, text = hasString(Strings, "banner." .. kind) }).toEqual({ kind = kind, text = true })
			end
		end)
	end)

	describe("Contrat › Prefs et Format (client)", function()
		it("Prefs applique les réglages du profil (mouvement, sons, langue)", function()
			local h = Harness.new({ mode = "client" })
			h:createRemotes()
			h:boot()
			local client = "StarterPlayer.StarterPlayerScripts.Client."
			local Prefs = h:require(client .. "Util.Prefs")
			local Juice = h:require(client .. "UI.Juice")
			local Audio = h:require(client .. "Controllers.AudioController")
			expect(Prefs.language()).toBe("en")
			expect(Prefs.t("common.close")).toBe("Close")
			local langs = {}
			Prefs.LanguageChanged:Connect(function(lang)
				table.insert(langs, lang)
			end)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", {
				settings = { reducedMotion = true, sfx = false, music = false, lang = "fr", zen = false },
			})
			h:settle(2)
			expect(Juice.forceReducedMotion).toBe(true)
			expect(Juice.reducedMotion()).toBe(true)
			expect(Juice.cameraShakeEnabled).toBe(false)
			expect(Audio.enabled).toBe(false)
			expect(Audio.isMusicEnabled()).toBe(false)
			expect(Prefs.language()).toBe("fr")
			expect(langs[#langs]).toBe("fr")
			expect(Prefs.t("common.close")).toBe("Fermer")
			expect(Prefs.number(1240000)).toBe("1,24\194\160M")
			expect(Prefs.get("autoCrew")).toBe(true) -- valeur par défaut conservée
			-- valeurs de mauvais type ignorées
			Prefs._onSettings({ reducedMotion = "oui", lang = 3 })
			expect(Prefs.reducedMotion()).toBe(false)
			expect(Prefs.language()).toBe("en")
		end)

		it("Format : 100K reste 100K ; français avec virgule et espaces insécables", function()
			local h = Harness.new()
			local F = shared(h, "Util.Format")
			expect(F.abbreviate(100000)).toBe("100K")
			expect(F.abbreviate(120000)).toBe("120K")
			expect(F.abbreviate(1000000000)).toBe("1B")
			expect(F.abbreviate(1240000, "fr")).toBe("1,24\194\160M")
			expect(F.abbreviate(1000000000, "fr")).toBe("1\194\160Md")
			expect(F.abbreviate(-2500, "fr")).toBe("-2,5\194\160k")
			expect(F.commas(1234567, "fr")).toBe("1\194\160234\194\160567")
			expect(F.commas(123456)).toBe("123,456")
			expect(F.duration(18720, "fr")).toBe("5\194\160h\194\16012")
			expect(F.duration(90, "fr")).toBe("1\194\160min\194\16030\194\160s")
		end)
	end)
end
