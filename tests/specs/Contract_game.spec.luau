--!nocheck
-- Contrat du JEU (docs/04, v1.2) : surface d'API des 66 modules des 8 paquets, ordres d'initialisation,
-- catalogue des intentions (Config/Intents) et registre des remotes, propriétaires des clés du profil,
-- données réelles des configurations (26 espèces, raretés, mutations, tables de la Cuve, prix des
-- dalles, objectifs, paliers, bannières, cosmétiques, sons, vibrations) et disposition télé du HUD.
-- Un paquet peut AJOUTER des fonctions ; il ne doit jamais retirer ni renommer ce qui est listé ici
-- (l'architecte étend ce contrat). Les valeurs d'économie peuvent bouger (paquet logic, porte
-- EconomyPacing) : seules les valeurs du GDD citées comme témoins sont vérifiées ici.
local fs = require("@lune/fs")

-- Surface d'API publique des modules du jeu : module → paquet, fonctions et signaux exigés
local API = {
	["ReplicatedStorage.Shared.Logic.Hash"] = {
		pkg = "logic",
		fns = { "u32", "unit", "int", "range", "pickWeighted", "string", "stream", "alias" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.BigNumber"] = {
		pkg = "logic",
		fns = { "abbreviate", "full", "words", "milestoneKey", "suffixes" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.SizeScale"] = {
		pkg = "logic",
		fns = { "scale", "diameter", "display", "overCap" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.Formulas"] = {
		pkg = "logic",
		fns = {
			"clampCoins",
			"clampSize",
			"G",
			"sizeAt",
			"growthRate",
			"A",
			"incomeFactor",
			"income",
			"ranchIncome",
			"potGain",
			"pressReward",
			"tileCost",
			"penCapacity",
			"poolSlots",
			"vatLevel",
			"vatInterval",
			"fusionSize",
			"fusionStars",
			"bestMutation",
			"comboReward",
			"sellValue",
			"secondsOfIncome",
			"splorchTarget",
			"offlineSeconds",
			"offlineGrowth",
			"offlinePot",
			"babySize",
			"saddleLevel",
			"rideStats",
			"trophyTier",
			"trophyBonus",
			"coinPack",
			"splorchPreview",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.Odds"] = {
		pkg = "logic",
		fns = {
			"unlockedFamilies",
			"rarityTable",
			"rollRarity",
			"mutationChances",
			"rollMutation",
			"speciesFor",
			"roll",
			"oneIn",
			"seed",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.FusionRules"] = {
		pkg = "logic",
		fns = { "areTwins", "fuse", "keepUid", "nextInChain", "throwOutcome", "twinPairs", "planMergeAll" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.RushRules"] = {
		pkg = "logic",
		fns = {
			"checkBoop",
			"holdTime",
			"extendHold",
			"checkCatch",
			"catchRadius",
			"fenceCount",
			"fenceEligible",
			"wildShared",
			"babySize",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.QuestRules"] = {
		pkg = "logic",
		fns = {
			"eligible",
			"draw",
			"reroll",
			"apply",
			"rollover",
			"plopReward",
			"dexMilestones",
			"stampCount",
			"starBadges",
			"familyComplete",
			"goldenPages",
			"isNewStamp",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.MegaRules"] = {
		pkg = "logic",
		fns = { "target", "leniency", "babiesFor", "isPerfect", "species" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.EventClock"] = {
		pkg = "logic",
		fns = {
			"rush",
			"mega",
			"golden",
			"moon",
			"nextEvent",
			"rushMoonBoopable",
			"megaSpecies",
			"seed",
			"costume",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.WorldLayout"] = {
		pkg = "logic",
		fns = {
			"ranchCFrame",
			"toWorld",
			"toLocal",
			"ranchAt",
			"inRanch",
			"gateOutside",
			"spawnCFrame",
			"anchor",
			"padSocket",
			"decorSlot",
			"penSlot",
			"poolSlot",
			"fencePoint",
			"plaza",
			"graph",
			"nearestNode",
			"fountainNode",
			"wildSpawnNodes",
			"solids",
			"groundY",
			"supportY",
			"meadowPoint",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.SeededPath"] = {
		pkg = "logic",
		fns = { "escape", "hopAround", "golden", "demo", "fromSpawn" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.PressTiming"] = {
		pkg = "logic",
		fns = { "offset", "phase", "isPerfect", "nextApex", "clampClientTime" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.ZoneRules"] = {
		pkg = "logic",
		fns = {
			"padStep",
			"near",
			"inMegaZone",
			"streetSideOfFence",
			"ownerNearFence",
			"intruder",
			"atAltar",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.LeapRules"] = {
		pkg = "logic",
		fns = { "validDir", "landing", "arc", "aim", "catchesOnLanding" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.TargetRules"] = {
		pkg = "logic",
		fns = { "score", "pick", "cycle", "afterPress", "screenPick" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.StateTimeouts"] = {
		pkg = "logic",
		fns = { "seconds", "deadline", "expired", "names" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.DiagRules"] = {
		pkg = "logic",
		fns = { "normalize", "truncate", "validUtf8", "key", "context", "mergeDaily" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Logic.Invariants"] = {
		pkg = "logic",
		fns = { "profile", "number", "dense", "uid" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Render.SquishyBuilder"] = {
		pkg = "world",
		fns = {
			"build",
			"setLod",
			"setScale",
			"setSquash",
			"pose",
			"setMutation",
			"setStars",
			"attachments",
			"release",
			"partCount",
			"recipe",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Render.Squash"] = {
		pkg = "world",
		fns = { "sample", "idle", "duration" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Render.Palette"] = {
		pkg = "world",
		fns = { "preset", "blend" },
		signals = {},
	},
	["ServerScriptService.Server.Services.WorldService"] = {
		pkg = "world",
		fns = {
			"build",
			"ranchModel",
			"setRanchOwner",
			"setRanchBuild",
			"setStatue",
			"setGauge",
			"partCount",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController"] = {
		pkg = "world",
		fns = { "current", "setQuiet" },
		signals = {},
	},
	["ServerScriptService.Server.Services.RanchService"] = {
		pkg = "ranch",
		fns = {
			"Init",
			"Start",
			"slotOf",
			"playerAt",
			"isReady",
			"place",
			"step",
			"onPad",
			"setPublic",
			"squishyOp",
			"setFence",
			"fenceOf",
			"publicOf",
			"setZoneHandler",
			"refreshBuild",
			"flush",
			"sendSnapshot",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.EconomyService"] = {
		pkg = "ranch",
		fns = {
			"Init",
			"Start",
			"step",
			"settle",
			"refresh",
			"coins",
			"addCoins",
			"trySpend",
			"income",
			"squishyIncome",
			"addIncomeSeconds",
			"growth",
			"G",
			"buyTile",
			"collectPot",
			"R",
			"addFame",
			"consumeCap",
			"grantPersonalBoost",
			"setServerBoost",
			"boostActive",
			"setFriendsPresent",
			"consumeFriendCap",
			"gNoBoost",
			"applySplorch",
			"onSettle",
			"incomeCtx",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.SquishyService"] = {
		pkg = "ranch",
		fns = {
			"Init",
			"Start",
			"step",
			"records",
			"get",
			"sizeOf",
			"biggest",
			"counts",
			"give",
			"hatchScripted",
			"press",
			"carried",
			"endCarry",
			"riding",
			"dismount",
			"resetSizes",
			"setWaiting",
			"growFor",
			"waiting",
			"anyEscaping",
			"setEscaping",
			"bestFriend",
			"fenceCandidates",
			"readyAt",
			"saddle",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.ProductService"] = {
		pkg = "ranch",
		fns = { "Init", "Start", "partyBuysToday" },
		signals = {},
	},
	["ServerScriptService.Server.Data.ProfileRepair"] = { pkg = "ranch", fns = { "repair" }, signals = {} },
	["ServerScriptService.Server.Services.ChaseService"] = {
		pkg = "chase",
		fns = {
			"Init",
			"Start",
			"tick",
			"actors",
			"active",
			"isEscaping",
			"returnEscapes",
			"leapCooldownLeft",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.RushService"] = {
		pkg = "chase",
		fns = { "Init", "Start", "step", "isRush", "isShielded", "canBeBooped", "allowRush", "openStates" },
		signals = {},
	},
	["ServerScriptService.Server.Services.EventService"] = {
		pkg = "chase",
		fns = {
			"Init",
			"Start",
			"step",
			"state",
			"rushActive",
			"moonActive",
			"eventBoopActive",
			"addGauge",
			"enqueueSpectacle",
			"cancelSpectacle",
			"canStartParty",
			"startSquishParty",
			"partyUnplayed",
			"playerCount",
			"isActive",
			"activeCount",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.SplorchService"] = {
		pkg = "chase",
		fns = { "Init", "Start", "step", "queued", "isWaiting", "openStates" },
		signals = {},
	},
	["ServerScriptService.Server.Services.QuestService"] = {
		pkg = "meta",
		fns = {
			"Init",
			"Start",
			"step",
			"stage",
			"isNewcomerQuiet",
			"playSeconds",
			"script",
			"stamp",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.CommunityService"] = {
		pkg = "meta",
		fns = {
			"Init",
			"Start",
			"step",
			"displayName",
			"friendsPresent",
			"areFriends",
			"isBlocked",
			"setting",
			"openClapWindow",
			"hasCosmetic",
			"unlockSession",
			"openStates",
		},
		signals = {},
	},
	["ServerScriptService.Server.Services.LeaderboardService"] = {
		pkg = "meta",
		fns = { "Init", "Start", "step", "submit", "isBanned" },
		signals = {},
	},
	["ServerScriptService.Server.Services.DiagnosticsService"] = {
		pkg = "meta",
		fns = {
			"attach",
			"Init",
			"Start",
			"step",
			"report",
			"reportCaught",
			"stateTimedOut",
			"snapshot",
			"isAdmin",
			"device",
			"counts",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.ErrorReporter"] = {
		pkg = "meta",
		fns = { "attach", "Init", "Start", "report", "noteContext", "sent", "entries", "stats" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldStateController"] = {
		pkg = "client-world",
		fns = {
			"Init",
			"Start",
			"ready",
			"mySlot",
			"ranch",
			"squishies",
			"sizeOf",
			"fence",
			"creatures",
			"creaturePos",
			"event",
			"boops",
		},
		signals = {
			"RanchChanged",
			"SquishyChanged",
			"FenceChanged",
			"CreatureSpawned",
			"CreatureFinished",
			"EventChanged",
			"MegaBeat",
			"BoopChanged",
			"EmoteShown",
		},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.QualityController"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "reduced", "budgets" },
		signals = { "Changed" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.RanchRenderer"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "positionOf", "play", "pulseTwins", "projected", "stats" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.ChaseRenderer"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "positionOf", "stats" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.VFXController"] = {
		pkg = "client-world",
		fns = {
			"Init",
			"Start",
			"floatText",
			"stamp",
			"flyCoins",
			"ring",
			"burst",
			"blobs",
			"capsule",
			"stats",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "splorch", "fovPunch", "shake", "busy" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.PromptController"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "current", "cycle", "clickAt", "lock", "unlock", "afterPress", "leapTarget" },
		signals = { "Changed" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.ChaseController"] = {
		pkg = "client-world",
		fns = { "Init", "Start", "leap", "tryCatch", "cooldownLeft" },
		signals = { "Leaped" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.HUD"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "reveal", "setHint", "setMenuBadges", "element", "clapHero" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Banners"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "show", "setQuiet", "queued" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Cards"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "push", "dismiss", "pending", "open", "current" },
		signals = { "Changed", "Requested" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.ScreenFX"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "flash", "glow", "arrow" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Prompt"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "setHold", "plates" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.WorldText"] = {
		pkg = "client-hud",
		fns = { "create", "setText", "pixelSize", "projectedPx", "clampToSafe", "rescale", "release" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "gameBound" },
		signals = { "Action" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.OnboardingController"] = {
		pkg = "client-hud",
		fns = { "Init", "Start", "step", "quiet" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.FocusGuard"] = {
		pkg = "client-panels",
		fns = { "Init", "Start", "open", "close", "top", "anyOpen", "back", "hold", "release", "rescues" },
		signals = { "WindowOpened", "WindowClosed" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.PanelController"] = {
		pkg = "client-panels",
		fns = {
			"Init",
			"Start",
			"toggleMenu",
			"openMenu",
			"open",
			"closeAll",
			"isOpen",
			"current",
			"entries",
		},
		signals = { "Changed" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.ReturnScreen"] = {
		pkg = "client-panels",
		fns = { "Init", "Start", "show", "isOpen" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Ranch"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Squishydex"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Objectives"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Leaderboards"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Shop"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Settings"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.SplorchPreview"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.OutfitPreview"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Panels.Diagnostics"] = {
		pkg = "client-panels",
		fns = {
			"build",
			"open",
			"close",
			"tabs",
			"setTab",
			"defaultSelection",
			"onBack",
			"visible",
			"setNavigator",
		},
		signals = {},
	},
}

local SERVER_ORDER = {
	"DiagnosticsService",
	"DataService",
	"MonetizationService",
	"WorldService",
	"RanchService",
	"EconomyService",
	"SquishyService",
	"QuestService",
	"CommunityService",
	"EventService",
	"RushService",
	"SplorchService",
	"ProductService",
	"LeaderboardService",
	"ChaseService",
}

local CLIENT_ORDER = {
	"Controllers.ErrorReporter",
	"Util.Platform",
	"UI.Root",
	"Controllers.StateController",
	"Controllers.AudioController",
	"Util.Prefs",
	"Controllers.WorldStateController",
	"Controllers.QualityController",
	"Controllers.LightingController",
	"Controllers.RanchRenderer",
	"Controllers.ChaseRenderer",
	"Controllers.VFXController",
	"Controllers.CameraController",
	"Controllers.PromptController",
	"Controllers.ChaseController",
	"UI.FocusGuard",
	"UI.Cards",
	"UI.PanelController",
	"UI.ReturnScreen",
	"UI.HUD",
	"UI.Banners",
	"UI.ScreenFX",
	"UI.Prompt",
	"Controllers.InputController",
	"Controllers.OnboardingController",
}

-- Remotes serveur → client du jeu (les autres remotes du jeu sont des intentions : Config/Intents)
local SERVER_TO_CLIENT = {
	DataSnapshot = true,
	DataPatch = true,
	Feedback = true,
	Celebrate = true,
	Banner = true,
	RanchSnapshot = true,
	RanchPatch = true,
	Fence = true,
	ChaseEvent = true,
	EventState = true,
	MegaBeat = true,
	BoopState = true,
	ModePrompt = true,
	HoldState = true,
	EmoteShow = true,
	ClapPrompt = true,
	LeaderboardState = true,
	DiagnosticsSnapshot = true,
	-- contrat v2.0 (docs/04 §27.5)
	UpgradeResult = true,
	HelperPress = true,
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

local SIGNALS = {
	"ServerMoved",
	"MoveViolation",
	"BannerRequested",
	"PlayerReady",
	"WorldRequested",
	"ProfileRepaired",
	"Pressed",
	"TileBought",
	"PotCollected",
	"SquishyObtained",
	"Hatched",
	"Fused",
	"SquishyRemoved",
	"Caught",
	"NearCatch",
	"Booped",
	"EscapeEnded",
	"ModeChanged",
	"EventPhase",
	"SpectacleStarted",
	"MegaJoined",
	"Splorched",
	"Fed",
	"OnboardingStep",
	"Stamped",
	"Emoted",
	"SettingChanged",
	"FriendsChanged",
	"PetSitRewarded",
	"UiSeen",
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	local function hasString(Strings, key)
		return Strings.en[key] ~= nil and Strings.fr[key] ~= nil
	end

	local function expectString(Strings, key)
		expect({ key = key, text = hasString(Strings, key) }).toEqual({ key = key, text = true })
	end

	describe("Contrat du jeu › Surface d'API des 8 paquets", function()
		it("chaque module existe, se charge sans erreur et expose ses fonctions et signaux", function()
			local hs = Harness.new({ mode = "server" })
			local hc = Harness.new({ mode = "client" })
			local count = 0
			for path, spec in API do
				count += 1
				local h = if string.find(path, "StarterPlayer", 1, true) then hc else hs
				local ok, mod = pcall(function()
					return h:require(path)
				end)
				expect({ path = path, loaded = ok }).toEqual({ path = path, loaded = true })
				for _, fn in spec.fns do
					expect({ path = path, fn = fn, kind = type(mod[fn]) }).toEqual({
						path = path,
						fn = fn,
						kind = "function",
					})
				end
				for _, sig in spec.signals do
					local s = mod[sig]
					expect({
						path = path,
						signal = sig,
						ok = type(s) == "table" and type(s.Connect) == "function",
					}).toEqual({
						path = path,
						signal = sig,
						ok = true,
					})
				end
			end
			expect(count).toBe(66)
			expect(#hs.errors + #hc.errors).toBe(0)
		end)

		it("chaque fichier possédé par un paquet appartient à un seul paquet", function()
			local seen = {}
			for path, spec in API do
				expect(seen[path]).toBeNil()
				seen[path] = spec.pkg
				local known = spec.pkg == "logic"
					or spec.pkg == "world"
					or spec.pkg == "ranch"
					or spec.pkg == "chase"
					or spec.pkg == "meta"
					or spec.pkg == "client-world"
					or spec.pkg == "client-hud"
					or spec.pkg == "client-panels"
				expect({ path = path, known = known }).toEqual({ path = path, known = true })
			end
		end)
	end)

	describe("Contrat du jeu › Ordres d'initialisation", function()
		it("Main.server.luau : la liste ORDER est exactement celle du contrat", function()
			local source = fs.readFile("src/server/Main.server.luau")
			local found = {}
			for name in string.gmatch(source, '\n\t"(%w+)",') do
				table.insert(found, name)
			end
			expect(found).toEqual(SERVER_ORDER)
		end)

		it("Main.client.luau : la liste ORDER est exactement celle du contrat", function()
			local source = fs.readFile("src/client/Main.client.luau")
			local found = {}
			for name in string.gmatch(source, "\n\tClient%.([%w%.]+),") do
				table.insert(found, name)
			end
			expect(found).toEqual(CLIENT_ORDER)
		end)

		it(
			"démarrage complet serveur et client avec tous les stubs : aucune erreur, aucun avertissement",
			function()
				local h = Harness.new()
				local DS = h:require("ServerScriptService.Server.Services.DataService")
				DS.Settings.RETRY_BASE_DELAY = 0.001
				h:boot()
				local p = h:addPlayer({ userId = 201, name = "Lea" })
				DS.waitFor(p, 2)
				h:step(1 / 60, 30)
				h:removePlayer(p)
				h:settle(3)
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
				local hc = Harness.new({ mode = "client", console = true })
				hc:createRemotes()
				hc:boot()
				local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
				hc:fireClient("ReplicatedStorage.Remotes.DataSnapshot", Schema.defaults())
				hc:step(1 / 60, 20)
				expect(table.concat(hc.errors, "\n")).toBe("")
				expect(table.concat(hc:warnings(), "\n")).toBe("")
				expect(hc.localPlayer:GetAttribute("ClientReady")).toBe(true)
			end
		)
	end)

	describe("Contrat du jeu › Intentions et remotes", function()
		it(
			"chaque intention est un remote « event » déclaré, avec un propriétaire de l'ordre serveur",
			function()
				local h = Harness.new()
				local R = shared(h, "Remotes")
				local Intents = shared(h, "Config.Intents")
				local services = {}
				for _, name in SERVER_ORDER do
					services[name] = true
				end
				local n = 0
				for name, spec in Intents do
					n += 1
					expect({ name = name, kind = R[name] }).toEqual({ name = name, kind = "event" })
					expect({ name = name, owner = services[spec.owner] == true }).toEqual({
						name = name,
						owner = true,
					})
					expect(spec.rate[1] > 0 and spec.rate[2] > 0).toBe(true)
					for _, arg in spec.args do
						expect({ name = name, arg = arg.name, kind = ARG_KINDS[arg.kind] == true }).toEqual({
							name = name,
							arg = arg.name,
							kind = true,
						})
						if arg.kind == "int" then
							expect(arg.min ~= nil and arg.max ~= nil and arg.min <= arg.max).toBe(true)
						end
						if arg.kind == "key" then
							expect(type(arg.set) == "table" and #arg.set > 0).toBe(true)
						end
						if arg.kind == "str" or arg.kind == "uids" or arg.kind == "userIds" then
							expect(type(arg.max) == "number" and arg.max > 0).toBe(true)
						end
					end
				end
				expect(n >= 38).toBe(true)
			end
		)

		it(
			"chaque remote est soit une intention, soit un envoi serveur → client connu ; aucun RemoteFunction",
			function()
				local h = Harness.new()
				local R = shared(h, "Remotes")
				local Intents = shared(h, "Config.Intents")
				-- contrat v2.0 (docs/04 §27.5) : intentions déclarées, pas encore écoutées
				local IntentsV2 = shared(h, "Config.IntentsV2")
				for name, kind in R do
					local known = Intents[name] ~= nil
						or IntentsV2[name] ~= nil
						or SERVER_TO_CLIENT[name] == true
						or name == "RequestSnapshot"
					expect({ name = name, known = known }).toEqual({ name = name, known = true })
					expect({ name = name, func = kind == "func" }).toEqual({ name = name, func = false })
				end
				for name in SERVER_TO_CLIENT do
					expect({ name = name, declared = R[name] ~= nil }).toEqual({
						name = name,
						declared = true,
					})
				end
			end
		)

		it("bus de signaux du serveur : chaque signal du contrat existe", function()
			local h = Harness.new()
			local Signals = h:require("ServerScriptService.Server.Signals")
			for _, name in SIGNALS do
				local s = Signals[name]
				expect({ name = name, ok = type(s) == "table" and type(s.Fire) == "function" }).toEqual({
					name = name,
					ok = true,
				})
			end
		end)
	end)

	describe("Contrat du jeu › Schéma v1", function()
		it("chaque clé a un propriétaire du contrat ; les réglages du jeu sont dans le profil", function()
			local h = Harness.new()
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local owners = { DataService = true, MonetizationService = true }
			for _, name in SERVER_ORDER do
				owners[name] = true
			end
			for key, owner in Schema.OWNERS do
				local ok = owners[owner] == true or string.find(owner, "(réservé", 1, true) == 1
				expect({ key = key, owner = owner, ok = ok }).toEqual({ key = key, owner = owner, ok = true })
			end
			local d = Schema.defaults()
			for _, key in { "hideName", "receiveGifts", "clips", "emoteLeft", "partyShowName" } do
				expect(d.settings[key] ~= nil).toBe(true)
			end
			expect(d.settings.allowRush).toBeNil() -- réglage de serveur, jamais sauvegardé
			expect(Schema.STREAMED_KEYS).toEqual({ "squishies" })
			expect(d.flags.lbBanUntil).toBe(0)
			expect(d.growth).toEqual({ G = 0, g = 1, t = 0 })
		end)

		it(
			"règlement du Pot : aucune clé lastSettle (intégrale sur [growth.t ; now], docs/04 §11.5)",
			function()
				local h = Harness.new()
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				expect(Schema.OWNERS.lastSettle).toBeNil()
				expect(Schema.defaults().lastSettle).toBeNil()
			end
		)

		it(
			"tableaux denses dès les valeurs par défaut : dex.mut, dex.stars, trophies (une case par espèce)",
			function()
				local h = Harness.new()
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				local Species = shared(h, "Config.Species")
				local d = Schema.defaults()
				for name, list in { mut = d.dex.mut, stars = d.dex.stars, trophies = d.trophies } do
					expect({ name = name, n = #list }).toEqual({ name = name, n = #Species.List })
					local count = 0
					for k, v in list do
						count += 1
						expect(type(k) == "number" and v == 0).toBe(true)
					end
					expect(count).toBe(#Species.List)
				end
				-- le DataStore simulé refuse un tableau à trous (couche e) : les valeurs par défaut passent
				local store = h.game.DataStoreService:GetDataStore("ContractDense")
				expect(function()
					store:SetAsync("k", d)
				end).notToThrow()
			end
		)

		it("DataService.onPrepare existe (rebase hors ligne avant l'instantané et Loaded)", function()
			local h = Harness.new()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			expect(type(DS.onPrepare)).toBe("function")
		end)
	end)

	describe("Contrat du jeu › Espèces, raretés, mutations (GDD §4.4, §4.5, §5.1)", function()
		it("26 espèces, identifiants 1-26 contigus, répartition 6/6/3/5/3/1/2, 4 par famille", function()
			local h = Harness.new()
			local S = shared(h, "Config.Species")
			local Strings = shared(h, "Localization.Strings")
			expect(#S.List).toBe(26)
			local byRarity = { 0, 0, 0, 0, 0, 0, 0 }
			local keys = {}
			for i, def in S.List do
				expect(def.id).toBe(i)
				expect(keys[def.key]).toBeNil()
				keys[def.key] = true
				byRarity[def.rarity] += 1
				expect(def.body.x > 0 and def.body.y > 0 and def.body.z > 0).toBe(true)
				expect(def.wobble.hz > 0 and def.wobble.amp > 0 and def.wobble.amp < 0.3).toBe(true)
				expect(typeof(def.colors.main)).toBe("Color3")
				expect(typeof(def.colors.second)).toBe("Color3")
				expect(
					type(def.top) == "string" and type(def.eyes) == "string" and type(def.pattern) == "string"
				).toBe(true)
				expect(def.release).toBe(0)
				expect(def.duo).toBe(false)
				expect(def.recipe).toBe("")
				expectString(Strings, "species." .. def.key)
				expectString(Strings, "species." .. def.key .. ".desc")
				expect(Strings.en["species." .. def.key]).toBe(def.name)
				expect(Strings.fr["species." .. def.key]).toBe(def.name)
			end
			expect(byRarity).toEqual({ 6, 6, 3, 5, 3, 1, 2 })
			for key, fam in S.Families do
				expect(#fam.species).toBe(if key == "secret" then 2 else 4)
				for _, id in fam.species do
					expect(S.ById[id].family).toBe(key)
				end
				expectString(Strings, "family." .. key)
				expect(S.ById[fam.uncommon].rarity).toBe(2)
			end
		end)

		it("7 raretés aux multiplicateurs du GDD ; 9 mutations ; chances de départ ≈ 7,6 %", function()
			local h = Harness.new()
			local R = shared(h, "Config.Rarities")
			local M = shared(h, "Config.Mutations")
			local Strings = shared(h, "Localization.Strings")
			local mults = {}
			for i, def in R.List do
				expect(def.id).toBe(i)
				table.insert(mults, def.mult)
				expectString(Strings, "rarity." .. def.key)
			end
			expect(mults).toEqual({ 1, 3, 10, 40, 200, 1000, 5000 })
			expect(#M.List).toBe(9)
			local total = 0
			for i, def in M.List do
				expect(def.id).toBe(i)
				total += def.chance
				expectString(Strings, "mutation." .. def.key)
			end
			expect(math.abs(total - 0.076045) < 1e-9).toBe(true)
			expect(#M.DrawOrder).toBe(8)
			expectString(Strings, "mutation.none")
		end)
	end)

	describe("Contrat du jeu › Économie : valeurs témoins du GDD", function()
		it("tables de qualité de la Cuve : 9 lignes qui somment à 100 %", function()
			local h = Harness.new()
			local B = shared(h, "Config.Balance")
			for q = 0, 8 do
				local row = B.Vat.Quality[q]
				expect(#row).toBe(7)
				local sum = 0
				for _, p in row do
					sum += p
				end
				expect({ q = q, ok = math.abs(sum - 100) < 1e-9 }).toEqual({ q = q, ok = true })
			end
		end)

		it("prix des dalles : floor(Base × Growth^L) donne les coûts du GDD §4.6", function()
			local h = Harness.new()
			local B = shared(h, "Config.Balance")
			local function cost(tile, level)
				local t = B.Tiles[tile]
				return math.floor(t.Base * t.Growth ^ level)
			end
			expect(cost("snack", 0)).toBe(20)
			-- Growth 4,0 → 4,5 (docs/04 §21, revue logic, note INT-LR1) : 1 822 et 306 455 660
			expect(cost("snack", 3)).toBe(1822)
			expect(cost("snack", 11)).toBe(306455660)
			expect(cost("decor", 0)).toBe(80)
			expect(cost("decor", 5)).toBe(4122)
			expect(cost("decor", 11)).toBe(467454)
			expect(cost("pens", 0)).toBe(1200)
			expect(cost("pens", 4)).toBe(28110)
			expect(cost("pens", 8)).toBe(658510)
			expect(B.Tiles.snack.Levels).toBe(12)
			expect(B.Tiles.decor.Levels).toBe(18)
			expect(B.Tiles.pens.Levels).toBe(14)
			-- Lit douillet : témoin de la version des valeurs annoncée (Balance.GddValues, docs/04 §16, §25)
			expect(B.Tiles.cozyBed.MinR).toBe(if B.GddValues == "1.3" then 3 else 1)
			expect(B.Pens.Base + B.Tiles.pens.Levels).toBe(18)
			expect(B.Pens.Base + B.Tiles.pens.Levels + B.Pens.BigRanchBonus).toBe(B.Pens.Max)
		end)

		it("objectifs du Grand Splorch : 20 lignes croissantes, 15 000 pour le premier", function()
			local h = Harness.new()
			local B = shared(h, "Config.Balance")
			expect(#B.Splorch.Targets).toBe(20)
			expect(B.Splorch.Targets[1]).toBe(15000)
			for i = 2, 20 do
				expect(B.Splorch.Targets[i] > B.Splorch.Targets[i - 1]).toBe(true)
			end
			expect(B.Splorch.BeyondMult).toBe(if B.GddValues == "1.3" then 2.6 else 2.7)
		end)
	end)

	describe("Contrat du jeu › Données de contenu et textes", function()
		it("dalles, décorations, objectifs, paliers et jalons ont leurs textes EN/FR", function()
			local h = Harness.new()
			local Pads = shared(h, "Config.Pads")
			local Q = shared(h, "Config.Quests")
			local B = shared(h, "Config.Balance")
			local Strings = shared(h, "Localization.Strings")
			expect(#Pads.Decor).toBe(18)
			for _, key in Pads.Decor do
				expectString(Strings, "decor." .. key)
			end
			local sockets = {}
			for key, def in Pads.Defs do
				expect(B.Tiles[key] ~= nil).toBe(true)
				expect(sockets[def.socket]).toBeNil()
				sockets[def.socket] = true
				expectString(Strings, "pad." .. key)
			end
			expect(#Q.Objectives).toBe(18)
			local tiers = { easy = 0, medium = 0, hard = 0 }
			for i, def in ipairs(Q.Objectives) do
				expect(def.id).toBe(i)
				tiers[def.tier] += 1
				expectString(Strings, "objective." .. def.id)
			end
			expect(tiers).toEqual({ easy = 6, medium = 7, hard = 5 })
			for _, id in Q.ObjectiveRules.Day1 do
				expect(Q.Objectives[id] ~= nil).toBe(true)
			end
			expect(#Q.Feed.Milestones).toBe(12)
			for _, m in Q.Feed.Milestones do
				expectString(Strings, "plop.reward." .. m.key)
			end
			expect(#Q.Dex.Milestones).toBe(9)
			for _, step in Q.Onboarding.Steps do
				expectString(Strings, "onboarding.step." .. step.key)
			end
			expect(#Q.Onboarding.Steps).toBe(11)
		end)

		it("bannières, cosmétiques et emotes ont leurs textes ; 16 couleurs de ranch", function()
			local h = Harness.new()
			local E = shared(h, "Config.Events")
			local C = shared(h, "Config.Cosmetics")
			local Strings = shared(h, "Localization.Strings")
			for kind, prio in E.Banners.Priority do
				expect(prio >= 1 and prio <= 7).toBe(true)
				expectString(Strings, "banner." .. kind)
			end
			for _, def in C.List do
				expectString(Strings, "cosmetic." .. def.kind .. "." .. def.id)
			end
			expect(#C.RanchColors).toBe(16)
			for _, e in C.EmoteSignals do
				expectString(Strings, "emote." .. e.key)
			end
		end)

		it(
			"boutique : identifiants à 0 au départ, effets déclarés ; paquets de pièces retirés (cachés)",
			function()
				local h = Harness.new()
				local M = shared(h, "Config.Monetization")
				for _, list in { M.Passes, M.Products } do
					for key, def in list do
						expect({ key = key, id = def.id }).toEqual({ key = key, id = 0 })
						-- plus aucun article caché par PolicyService ni « Grand Splorch prêt » (contrat v1.2)
						expect({
							key = key,
							policy = def.hideIfRandomRestricted,
							ready = def.hideWhenSplorchReady,
						}).toEqual({
							key = key,
						})
					end
				end
				for _, key in { "AutoPot", "DoubleCoins", "BigRanch", "SaddlesTrails" } do
					expect(M.Passes[key].forever).toBe(true)
				end
				for _, key in { "CoinsSmall", "CoinsBig" } do
					expect({ key = key, hidden = M.Products[key].hidden }).toEqual({
						key = key,
						hidden = true,
					})
					expect(M.Products[key].coinMinutes).toBeNil()
				end
				expect(M.Passes.SeasonPass.hidden).toBe(true)
				expect(M.Products.SquishParty.dailyLimit).toBe(3)
				expect(M.Products.SquishParty.hidden).toBeNil()
			end
		)

		it("sons du GDD §9.6 déclarés (ID vide = muet) ; vibrations du GDD §10.5 déclarées", function()
			local hc = Harness.new({ mode = "client" })
			local Sounds = shared(hc, "Config.Sounds")
			local Console = shared(hc, "Config.Console")
			for _, key in
				{
					"Coin",
					"Reward",
					"LevelUp",
					"Music",
					"MusicMoon",
					"MusicRush",
					"Press",
					"Perfect",
					"StreakMax",
					"PotCollect",
					"TileBuild",
					"VatBubble",
					"Hatch",
					"HatchRare",
					"HatchLegend",
					"MutationReveal",
					"Blorp",
					"Pickup",
					"Throw",
					"Splash",
					"Fuse",
					"ComboStep",
					"ComboBig",
					"RunawayAppear",
					"Giggle",
					"Catch",
					"CatchGolden",
					"Leap",
					"MountUp",
					"RideLand",
					"RushSiren",
					"BoopHold",
					"Sneeze",
					"Return",
					"BabyGet",
					"HeroCatch",
					"MegaWarn",
					"MegaLand",
					"MegaPress",
					"MegaPop",
					"MegaSigh",
					"GaugeFull",
					"GoldenAppear",
					"MoonStart",
					"Fanfare",
					"SplorchCharge",
					"SplorchPop",
					"GiftRain",
					"FeedPlop",
					"DexNew",
					"ObjectiveDone",
					"Emote",
					"Boing",
				}
			do
				expect({ key = key, declared = Sounds[key] ~= nil }).toEqual({ key = key, declared = true })
			end
			for _, name in
				{
					"pressTick",
					"perfect",
					"tileBuy",
					"refuse",
					"listEnd",
					"holdStart",
					"holdDone",
					"cardIn",
					"catch",
					"fusion",
					"comboBig",
					"boopDone",
					"squishyBack",
					"rushSiren",
					"megaLand",
					"megaPop",
					"hatchLegend",
					"splorch",
				}
			do
				local def = Console.Haptics.Events[name]
				expect({ name = name, declared = def ~= nil }).toEqual({ name = name, declared = true })
				expect(def.mobile).toBeNil() -- console d'abord : aucune vibration de téléphone
			end
			-- GDD v1.3 §10.5 : plus de vibration quand un squishy s'enfuit ; sirène en une seule impulsion
			-- de 0,3 s, jouée même pendant le délai minimal
			expect(Console.Haptics.Events.booped).toBeNil()
			local back = Console.Haptics.Events.squishyBack
			expect({ back.effect, back.motor, back.strength, back.duration, back.priority }).toEqual({
				"GameplayCollision",
				"Small",
				0.3,
				0.08,
				2,
			})
			expect(Console.Haptics.Events.rushSiren.duration).toBe(0.3)
			expect(Console.Haptics.Events.rushSiren.cooldownExempt).toBe(true)
		end)
	end)

	describe("Contrat du jeu › Disposition télé (GDD §10.1, §10.2)", function()
		local function overlap(a, b)
			return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
		end
		-- Paires qui ne sont jamais visibles ensemble (même place, l'une remplace l'autre)
		local EXCLUSIVE = {
			["menuChip|menuRail"] = true,
			["gauge|megaBar"] = true,
		}

		it(
			"chaque élément du HUD est dans la zone sûre ; aucun recouvrement entre éléments visibles ensemble",
			function()
				local h = Harness.new()
				local L = shared(h, "Config.Layout")
				local safe = L.Safe
				local names = {}
				for name, slot in L.Hud do
					table.insert(names, name)
					local r = slot.rect
					local inside = r.x >= safe.x
						and r.y >= safe.y
						and r.x + r.w <= safe.x + safe.w
						and r.y + r.h <= safe.y + safe.h
					expect({ name = name, inside = inside }).toEqual({ name = name, inside = true })
				end
				table.sort(names)
				for i = 1, #names do
					for j = i + 1, #names do
						local a, b = names[i], names[j]
						local pair = if a < b then a .. "|" .. b else b .. "|" .. a
						if not EXCLUSIVE[pair] then
							expect({ pair = pair, overlap = overlap(L.Hud[a].rect, L.Hud[b].rect) }).toEqual({
								pair = pair,
								overlap = false,
							})
						end
					end
				end
				expect(L.Text.Min).toBe(28)
				expect(L.Reference).toEqual({ X = 1920, Y = 1080 })
				expect(L.Safe).toEqual({ x = 96, y = 54, w = 1728, h = 972 })
			end
		)

		it("le milieu de l'écran reste libre pour le personnage", function()
			local h = Harness.new()
			local L = shared(h, "Config.Layout")
			for name, slot in L.Hud do
				if name ~= "menuRail" then
					expect({ name = name, free = not overlap(slot.rect, L.Columns.free) }).toEqual({
						name = name,
						free = true,
					})
				end
			end
		end)
	end)

	describe("Contrat du jeu › Interrupteurs", function()
		it("Features : valeurs de lancement, set refuse une clé inconnue ou un mauvais type", function()
			local h = Harness.new()
			local F = shared(h, "Config.Features")
			F.reset()
			expect(F.get("BoopRush")).toBe("on")
			expect(F.get("Diagnostics")).toBe(true)
			expect(F.get("RewardedAds")).toBe(false)
			expect(F.set("BoopRush", "events")).toBe(true)
			expect(F.get("BoopRush")).toBe("events")
			expect(F.set("BoopRush", "chaos")).toBe(false)
			expect(F.set("BoopRush", true)).toBe(false)
			expect(F.set("Inconnu", true)).toBe(false)
			F.reset()
			expect(F.get("BoopRush")).toBe("on")
		end)
	end)

	-- Corrections du contrat après la revue indépendante (docs/04 §14, §17, §22) ------------------

	describe("Contrat du jeu › Console d'abord (note INT-TV appliquée)", function()
		it(
			"Config/Console = disposition télé : 1920 × 1080, texte 28, glyphe 48, plancher et zone sûre de Layout",
			function()
				local hc = Harness.new({ mode = "client" })
				local Console = shared(hc, "Config.Console")
				local L = shared(hc, "Config.Layout")
				expect(Console.Reference).toEqual({ X = 1920, Y = 1080 })
				expect(Console.Reference).toEqual(L.Reference)
				expect(Console.MinTextSize).toBe(28)
				expect(Console.MinTextSize).toBe(L.Text.Min)
				expect(Console.GlyphSize).toBe(L.Glyph.Min)
				expect(Console.TvScale.Min).toBe(L.MinScale)
				expect(Console.TvSafeMargin).toBe(L.SafeMargin)
				expect(Console.Scale).toBeNil() -- plus d'échelle « écran ordinaire »
				local Theme = hc:require("StarterPlayer.StarterPlayerScripts.Client.UI.Theme")
				expect(Theme.MinTouch).toBeNil()
				expect(Theme.MinTextSize).toBe(28)
				for name, def in Console.Haptics.Events do
					expect({ name = name, mobile = def.mobile }).toEqual({ name = name })
				end
				-- une seule règle d'échelle sur tous les écrans
				local P = hc:require("StarterPlayer.StarterPlayerScripts.Client.Util.Platform")
				local V2 = hc.globals.Vector2
				for _, large in { false, true } do
					expect(P.uiScale(V2.new(1920, 1080), large)).toBe(1)
					expect(P.uiScale(V2.new(3840, 2160), large)).toBe(2)
					expect(P.safePadding(V2.new(1920, 1080), large)).toEqual(V2.new(L.Safe.x, L.Safe.y))
				end
			end
		)

		it("aucun chemin de code tactile dans src/ (seule la détection de Platform reste)", function()
			local FORBIDDEN = {
				"TouchEnabled",
				"TouchTap",
				"TouchSwipe",
				"TouchLongPress",
				"TouchPan",
				"TouchPinch",
				"TouchRotate",
				"UserInputType.Touch",
				"PreferredInput.Touch",
				"mobile =",
				"MinTouch",
			}
			-- exceptions exactes : détection de l'appareil (message device.touch, analytique) et
			-- relâchement d'un pointeur générique par Juice.press (aucun contrôle tactile)
			local ALLOWED = {
				["src/client/Util/Platform.luau"] = true,
				["src/client/UI/Juice.luau|UserInputType.Touch"] = true,
			}
			local found = {}
			local function scan(dir)
				for _, entry in fs.readDir(dir) do
					local path = dir .. "/" .. entry
					if fs.isDir(path) then
						scan(path)
					elseif string.match(entry, "%.luau$") and not ALLOWED[path] then
						local source = fs.readFile(path)
						for _, word in FORBIDDEN do
							if string.find(source, word, 1, true) and not ALLOWED[path .. "|" .. word] then
								table.insert(found, path .. " : " .. word)
							end
						end
					end
				end
			end
			scan("src")
			expect(table.concat(found, "\n")).toBe("")
		end)

		it("specs du jeu : jamais Harness.new({ touch = true })", function()
			local found = {}
			for _, entry in fs.readDir("tests/specs") do
				local path = "tests/specs/" .. entry
				if fs.isFile(path) and string.match(entry, "%.spec%.luau$") then
					local source = fs.readFile(path)
					local socle = string.find(source, "Comet Conga", 1, true) ~= nil
					if not socle and string.find(source, "touch = true", 1, true) then
						table.insert(found, path)
					end
				end
			end
			expect(table.concat(found, "\n")).toBe("")
		end)
	end)

	describe("Contrat du jeu › Corrections de la revue", function()
		it(
			"jauge : une seule source de points (Events.Gauge.Points), aucun champ *Gauge* ailleurs",
			function()
				local h = Harness.new()
				local E = shared(h, "Config.Events")
				local B = shared(h, "Config.Balance")
				local found = {}
				local function walk(t, path, seen)
					if seen[t] then
						return
					end
					seen[t] = true
					for k, v in t do
						local p = path .. "." .. tostring(k)
						if
							type(k) == "string"
							and string.find(k, "Gauge", 1, true)
							and p ~= "Events.Gauge"
						then
							table.insert(found, p)
						end
						if type(v) == "table" and p ~= "Events.Gauge" then
							walk(v, p, seen)
						end
					end
				end
				walk(E, "Events", {})
				walk(B, "Balance", {})
				expect(table.concat(found, ", ")).toBe("")
				for _, key in
					{
						"press",
						"perfect",
						"petSit",
						"hatch",
						"fuseStep",
						"catch",
						"rushCatch",
						"rushNear",
						"mega",
						"feed",
						"splorch",
					}
				do
					-- GDD v1.3 §4.23 : une pression ordinaire ne compte pas (press = 0) ; tout le reste compte
					local value = E.Gauge.Points[key]
					local ok = type(value) == "number" and (if key == "press" then value == 0 else value > 0)
					expect({ key = key, ok = ok }).toEqual({ key = key, ok = true })
				end
				expect(E.Gauge.Points.splorch).toBe(25)
				expect(E.Gauge.Points.perfect).toBe(1)
			end
		)

		it(
			"carte « booped » (Pas ce joueur atteignable à la manette) juste après « postBoop »",
			function()
				local h = Harness.new()
				local L = shared(h, "Config.Layout")
				local Strings = shared(h, "Localization.Strings")
				local order = L.Cards.Order
				local i = table.find(order, "postBoop")
				expect(i ~= nil).toBe(true)
				expect(order[i + 1]).toBe("booped")
				for _, key in { "card.booped.title", "card.booped.continue", "card.booped.refuse" } do
					expectString(Strings, key)
				end
			end
		)

		it("onglets Style (cosmétiques) et Outils (administrateurs) ont leurs textes", function()
			local h = Harness.new()
			local Strings = shared(h, "Localization.Strings")
			for _, key in
				{
					"panel.ranch.tab.style",
					"panel.ranch.style.saddle",
					"panel.ranch.style.trail",
					"panel.ranch.style.title",
					"panel.ranch.style.theme",
					"panel.ranch.style.flag",
					"panel.ranch.style.outfits",
					"panel.diag.tab.tools",
					"panel.diag.tools.forceRush",
					"panel.diag.tools.forceMega",
					"panel.diag.tools.testServer",
					"panel.diag.tools.testClient",
					"panel.diag.tools.photo",
				}
			do
				expectString(Strings, key)
			end
		end)

		it("délais des états : arrivée, serveur plein, resynchronisation, instabilité, clip", function()
			local h = Harness.new()
			local ST = shared(h, "Logic.StateTimeouts")
			expect(ST.Table.playerReady).toBe(15)
			expect(ST.Table.serverFull).toBe(30)
			expect(ST.Table.worldResync).toBe(3)
			expect(ST.Table.unstable).toBe(3)
			expect(ST.Table.clip).toBe(8)
			expect(ST.Table.boopHold).toBe(5.5)
		end)

		it("hauteurs des solides au-dessus de la plus haute portée (selle géante comprise)", function()
			local h = Harness.new()
			local W = shared(h, "Logic.WorldLayout")
			local B = shared(h, "Config.Balance")
			local maxJump, maxScale = B.Ride.BaseJumpHeight, 1
			for _, saddle in B.Ride.Saddles do
				maxJump = math.max(maxJump, saddle.jumpHeight)
				maxScale = math.max(maxScale, saddle.scale)
			end
			local maxOffset = B.Ride.HipFactor * B.SizeScale.BaseDiameter * maxScale
			expect(W.Const.MaxReach >= maxJump + maxOffset).toBe(true)
			expect(W.Const.SolidMinHeight >= W.Const.MaxReach + 8).toBe(true)
			for _, key in { "FenceWallHeight", "EdgeWallHeight", "HouseCapHeight" } do
				expect({ key = key, ok = W.Const[key] >= W.Const.SolidMinHeight }).toEqual({
					key = key,
					ok = true,
				})
			end
		end)

		it(
			"interrupteurs envoyés aux clients : EventStatePayload.features porte chaque événement",
			function()
				local source = fs.readFile("src/shared/Types.luau")
				local block = string.match(source, "export type EventFeatures = (%b{})")
				expect(block ~= nil).toBe(true)
				for _, field in
					{
						"boopRush",
						"megaSquish",
						"golden",
						"jellyMoon",
						"gauge",
						"clips",
						"costume",
						"diagnostics",
					}
				do
					expect({ field = field, ok = string.find(block, field .. ":", 1, true) ~= nil }).toEqual({
						field = field,
						ok = true,
					})
				end
				expect(string.find(source, "features: EventFeatures", 1, true) ~= nil).toBe(true)
			end
		)

		it("specs du vrai moteur (couche i) : tests/engine/*.spec.luau n'importent jamais @lune", function()
			local found = {}
			if fs.isDir("tests/engine") then
				for _, entry in fs.readDir("tests/engine") do
					local path = "tests/engine/" .. entry
					if fs.isFile(path) and string.match(entry, "%.luau$") then
						if string.find(fs.readFile(path), "@lune", 1, true) then
							table.insert(found, path)
						end
					end
				end
			end
			expect(table.concat(found, "\n")).toBe("")
		end)
	end)

	-- Contrat v1.2 : GDD v1.3 et remarques A20-A29 de la revue d'architecture (docs/04 §25) ---------

	describe("Contrat du jeu › Contrat v1.2 (GDD v1.3, remarques A20-A29)", function()
		local GAMEPLAY = {
			"Press",
			"PickUp",
			"PutDown",
			"Throw",
			"FuseMenu",
			"FuseAll",
			"BuyTile",
			"BuyUpgrade", -- lot A2 (note INT-V2-INTENTS, journal A2-8) : achat, intention de jeu
			"MoveSquishy",
			"ClaimMail",
			"Sell",
			"Release",
			"SetLock",
			"SetBestFriend",
			"SetMount",
			"Ride",
			"EquipOutfit",
			"Leap",
			"Catch",
			"BoopHold",
			"MegaPress",
			"GrandSplorch",
			"JellyAscend", -- lot A2 (note INT-V2-INTENTS, journal A2-23) : prestige, intention de jeu
			"FeedPlop",
			"ClaimObjective",
			"RerollObjective",
			"ClaimDexReward",
			"PetPress",
			"EquipCosmetic",
			"Emote",
			"Clap",
		}

		it(
			"intentions : Catch et Leap portent tClient ; ClientEvent (analytique) ; activity sur les seules intentions de jeu",
			function()
				local h = Harness.new()
				local Intents = shared(h, "Config.Intents")
				local R = shared(h, "Remotes")
				local function argNames(name)
					local out = {}
					for _, arg in Intents[name].args do
						table.insert(out, arg.name .. ":" .. arg.kind)
					end
					return out
				end
				expect(argNames("Catch")).toEqual({ "id:int", "tClient:time" })
				expect(argNames("Leap")).toEqual({ "dirX:dir", "dirZ:dir", "tClient:time" })
				expect(Intents.ClientEvent.owner).toBe("DiagnosticsService")
				expect(Intents.ClientEvent.rate).toEqual({ 1, 5 })
				expect(Intents.ClientEvent.args[1].set).toEqual({ "qualityReduced", "shopOpened" })
				expect(R.ClientEvent).toBe("event")
				local expected = {}
				for _, name in GAMEPLAY do
					expected[name] = true
				end
				for name, spec in Intents do
					expect({ name = name, activity = spec.activity == true }).toEqual({
						name = name,
						activity = expected[name] == true,
					})
				end
			end
		)

		it(
			"types : sortes de Celebrate = table du §10.3 de docs/04 ; champs ajoutés par le contrat v1.2",
			function()
				local source = fs.readFile("src/shared/Types.luau")
				local union =
					string.match(source, "export type CelebrateKind =(.-)\nexport type CelebratePayload")
				expect(union ~= nil).toBe(true)
				local kinds = {}
				for kind in string.gmatch(union, '"(%w+)"') do
					kinds[kind] = true
				end
				local doc = fs.readFile("docs/04-architecture.md")
				local section = string.match(doc, "### 10%.3 Célébrations.-\n(.-)\n### 10%.4")
				expect(section ~= nil).toBe(true)
				local documented = 0
				for line in string.gmatch(section, "[^\n]+") do
					for kind in string.gmatch(string.match(line, "^| ([^|]+) |") or "", "`(%w+)`") do
						documented += 1
						expect({ kind = kind, typed = kinds[kind] == true }).toEqual({
							kind = kind,
							typed = true,
						})
					end
				end
				expect(documented >= 30).toBe(true)
				for _, needle in
					{
						"\tgd: number,",
						"best: { s: SpeciesId, m: MutationId, z: number, zg: number },",
						"restUntil: number",
						'kind: "feed" | "tile"',
						"position: number,",
						"eta: number,",
						"rootOffset: number,",
						"short: boolean,",
						"nearlyReady: boolean,",
					}
				do
					expect({ needle = needle, found = string.find(source, needle, 1, true) ~= nil }).toEqual({
						needle = needle,
						found = true,
					})
				end
				-- RanchPatch : aucun champ optionnel dans RanchPublic (un nil ne voyage pas, remarque A27)
				local ranch = string.match(source, "export type RanchPublic = (%b{})")
				expect(string.find(ranch, "}?", 1, true)).toBeNil()
			end
		)

		it(
			"schéma : coinBuy retiré, packs réservé, moon (EventService), dex.fam dense, plafonds de pet-sitting",
			function()
				local h = Harness.new()
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				local Species = shared(h, "Config.Species")
				local B = shared(h, "Config.Balance")
				local d = Schema.defaults()
				expect(d.coinBuy).toBeNil()
				expect(Schema.OWNERS.coinBuy).toBeNil()
				expect(d.packs).toEqual({ side = 0, quoteProduct = "", quoteAmount = 0, quoteAt = 0 })
				expect(string.find(Schema.OWNERS.packs, "(réservé", 1, true)).toBe(1)
				expect(d.moon).toEqual({ lastSession = 0 })
				expect(Schema.OWNERS.moon).toBe("EventService")
				expect(#d.dex.fam).toBe(#Species.FamilyOrder)
				for f, v in d.dex.fam do
					expect(type(f) == "number" and v == 0).toBe(true)
				end
				for _, key in { "splorchCoins", "petSitIn" } do
					expect({ key = key, value = d.caps[key] }).toEqual({ key = key, value = 0 })
				end
				expect(d.caps.petSitBy).toEqual({})
				-- chaque plafond scalaire de Balance.Caps a son compteur dans caps (Logic/Invariants)
				for key in B.Caps do
					expect({ key = key, counter = type(d.caps[key]) }).toEqual({
						key = key,
						counter = "number",
					})
				end
				expect(B.CapsPerFriend.petSit).toBe(20)
				-- tenue portée : seulement dans squishies[uid].o ; outfits.worn obsolète, toujours vide
				expect(d.outfits.worn).toEqual({})
			end
		)

		it(
			"profil plein (104 squishies, trophées et Squishydex partiels, 64 espèces) : JSON aller-retour sans changement",
			function()
				local h = Harness.new()
				local Schema = h:require("ServerScriptService.Server.Data.Schema")
				local Http = h.game.HttpService
				local d = Schema.defaults()
				local places = { "pen", "pool", "dodo", "mail" }
				local counts = { pen = 19, pool = 5, dodo = 60, mail = 20 }
				local n = 0
				for _, at in places do
					for _ = 1, counts[at] do
						n += 1
						local uid = string.format("%x", n)
						d.squishies[uid] = {
							s = (n % 64) + 1,
							m = n % 10,
							st = n % 6,
							z = 1 + n * 1234.5,
							zg = n * 0.25,
							bf = if n <= 3 then n else 0,
							lk = n % 7 == 0,
							o = if n == 5 then "sweater" else "",
							at = at,
							b = 1797033600 + n,
							gd = if n % 2 == 0 then 20800 else 0,
						}
					end
				end
				expect(n).toBe(104)
				d.nextUid = 105
				for s = 1, 64 do
					d.dex.mut[s] = if s % 3 == 0 then 0 else bit32.bor(1, bit32.lshift(1, (s % 9) + 1))
					d.dex.stars[s] = s % 32
					d.trophies[s] = if s % 4 == 0 then 0 else s * 1e9
				end
				d.dex.fam = { 1, 0, 1, 0, 0, 0, 0, 1 }
				d.outfits.owned.sweater = 1
				d.caps.petSitBy["123456"] = 7
				local back = Http:JSONDecode(Http:JSONEncode(d))
				expect(back).toEqual(d)
				expect(#Http:JSONEncode(d) < 20000).toBe(true)
				-- le DataStore simulé l'accepte (aucun tableau à trous, aucune table mixte)
				local store = h.game.DataStoreService:GetDataStore("ContractFull")
				expect(function()
					store:SetAsync("k", d)
				end).notToThrow()
			end
		)

		it(
			"Squishydex de 64 espèces : tampons et étoiles gardés après sauvegarde et rechargement (DataService)",
			function()
				local h = Harness.new()
				local DS = h:require("ServerScriptService.Server.Services.DataService")
				DS.Settings.LOCKED_RETRY_DELAY = 0.01
				DS.Settings.RETRY_BASE_DELAY = 0.001
				h:boot()
				local p = h:addPlayer({ userId = 301, name = "Mia" })
				local data = DS.waitFor(p, 2)
				expect(data ~= nil).toBe(true)
				for s = 1, 64 do
					data.dex.mut[s] = bit32.bor(1, bit32.lshift(1, (s % 9) + 1))
					data.dex.stars[s] = s % 32
					data.trophies[s] = s * 1000
				end
				DS.markDirty(p, "dex")
				DS.markDirty(p, "trophies")
				h:removePlayer(p)
				h:settle(5)
				local p2 = h:addPlayer({ userId = 301, name = "Mia" })
				local d2 = DS.waitFor(p2, 2)
				expect(d2 ~= nil).toBe(true)
				expect(#d2.dex.mut).toBe(64)
				expect(#d2.dex.stars).toBe(64)
				for s = 1, 64 do
					expect({ s = s, mut = d2.dex.mut[s], stars = d2.dex.stars[s], trophy = d2.trophies[s] }).toEqual({
						s = s,
						mut = bit32.bor(1, bit32.lshift(1, (s % 9) + 1)),
						stars = s % 32,
						trophy = s * 1000,
					})
				end
				expect(table.concat(h.errors, "\n")).toBe("")
			end
		)

		it(
			"valeurs du GDD v1.3 tenues par le contrat : jauge, activité, bol, objectifs, nouvelles clés",
			function()
				local h = Harness.new()
				local E = shared(h, "Config.Events")
				local Q = shared(h, "Config.Quests")
				local B = shared(h, "Config.Balance")
				local S = shared(h, "Config.Species")
				expect(E.Gauge.TargetPerPlayer).toBe(600)
				expect(E.Gauge.RestSeconds).toBe(1200)
				expect(E.Gauge.Points.press).toBe(0)
				expect(E.Activity).toEqual({
					Window = 120,
					MoveStuds = 4,
					MegaAlertRadius = 60,
					MinPlayers = 1,
				})
				expect(E.SplorchQueueHardCut).toBe(480)
				expect(Q.Feed.Hold).toBe(2)
				for tier, reward in Q.ObjectiveRules.Rewards do
					expect({ tier = tier, boost = reward.boost }).toEqual({ tier = tier, boost = 0 })
				end
				expect(B.Tiles.DwellSeconds).toBe(0.6)
				expect(B.Tiles.RScale).toBe(3.5)
				expect(B.Offline.StopAt).toBe(0.9)
				expect(B.Caps.petSitIn).toBe(100)
				expect(B.Caps.splorchCoins).toBe(10)
				expect(B.Rewards.GiftSecondsAfterCap).toBe(10)
				expect(B.Babies.RushMutationMaxMult).toBe(5)
				expect(B.RushSize).toEqual({ HeroGrowthSeconds = 3600, ReturnGrowthSeconds = 1800 })
				expect(B.Splorch.FullShowGap).toBe(180)
				expect(B.Press.RangeTolerance).toBe(2)
				expect(B.Catch.ClientPast).toBe(0.35)
				expect(B.Leap.GrantSpeed).toBeNil() -- remplacé par MoveCheck.grant (note INT-MOVE)
				expect(S.NewFamilyUnlockR).toBe(5)
				-- familles : liste en ajout seul = index de dex.fam
				expect(#S.FamilyOrder).toBe(7)
				local seen = {}
				for i, key in S.FamilyOrder do
					expect(S.Families[key].order).toBe(i)
					seen[key] = true
				end
				for key in S.Families do
					expect({ key = key, listed = seen[key] == true }).toEqual({ key = key, listed = true })
				end
				-- valeurs témoins de la version annoncée (logic passe GddValues à "1.3" en appliquant ses notes)
				expect(B.GddValues == "1.2" or B.GddValues == "1.3").toBe(true)
				if B.GddValues == "1.3" then
					expect(B.Tiles.cozyBed.Base).toBe(25e6)
					expect(B.Splorch.Targets[2]).toBe(39000)
					expect(B.Splorch.Targets[20]).toBe(1.1e12)
					expect(B.Offline.GrowthShare).toBe(0.3)
					expect(B.Babies.MaxOfBiggest).toBe(0.5)
					expect(B.Caps.petSit).toBe(100)
					expect(B.Rewards.PetSitVisitor).toBe(2)
					expect(B.Boosts.ObjectiveMedium).toBe(0)
					expect(B.Boosts.ObjectiveHard).toBe(0)
					expect(B.Splorch.RecentBuyWindow).toBeNil()
					expect(B.CoinPacks).toBeNil()
				end
			end
		)

		it("nouveaux textes EN / FR du contrat v1.2", function()
			local h = Harness.new()
			local Strings = shared(h, "Localization.Strings")
			for _, key in
				{
					"feedback.waitEscape",
					"hud.gauge.rest",
					"hud.queue.next",
					"hud.queue.place",
					"world.vat.dodo",
					"celebrate.giftShort",
					"return.nearly",
					"panel.dex.sheet.mutations",
					"panel.dex.sheet.stars",
					"panel.dex.sheet.record",
					"panel.dex.sheet.found",
				}
			do
				expectString(Strings, key)
			end
			expect(Strings.fr["num.word.12"]).toBe("1 000 MILLIARDS")
		end)

		it(
			"projet Rojo : StreamingEnabled coupé, curseur virtuel désactivé, Lighting ShadowMap (remarque A28)",
			function()
				local serde = require("@lune/serde")
				local project = serde.decode("json", fs.readFile("default.project.json"))
				local tree = project.tree
				expect(tree.Workspace["$properties"].StreamingEnabled).toBe(false)
				local lighting = tree.Lighting["$properties"].Technology
				local tech = if type(lighting) == "table" then lighting.Enum or lighting[1] else lighting
				expect(tostring(tech)).toBe("ShadowMap")
				local starterGui = tree.StarterGui and tree.StarterGui["$properties"] or {}
				local cursor = starterGui.VirtualCursorMode
				local mode = if type(cursor) == "table" then cursor.Enum or cursor[1] else cursor
				expect(tostring(mode)).toBe("Disabled")
			end
		)

		it(
			"clavier : menu sur M et Semicolon (AZERTY), jamais Tab ; raccourcis directs des panneaux",
			function()
				local h = Harness.new()
				local L = shared(h, "Config.Layout")
				expect(L.Keyboard.Menu).toEqual({ "M", "Semicolon" })
				expect(L.Keyboard.Panels).toEqual({
					Ranch = "G",
					Squishydex = "C",
					Objectives = "J",
					Leaderboards = "L",
					Shop = "B",
					Settings = "P",
				})
				for _, key in L.Keyboard.Menu do
					expect(key ~= "Tab").toBe(true)
				end
				expect(L.HudContent.edgeArrow.max).toBe(2)
				expect(L.WorldText.Text >= 32 and L.WorldText.Plus >= 40 and L.WorldText.Glyph >= 48).toBe(
					true
				)
				expect(L.WorldText.MinProjected).toBe(28)
			end
		)

		it(
			"Main.server : Net.setup() après l'attach de DiagnosticsService, avant les autres require (remarque A29)",
			function()
				local source = fs.readFile("src/server/Main.server.luau")
				local attachAt = string.find(source, 'run(name, "attach", m.attach)', 1, true)
				local setupAt = string.find(source, "\t\tNet.setup()", 1, true)
				expect(attachAt ~= nil and setupAt ~= nil and setupAt > attachAt).toBe(true)
				expect(string.find(source, "\nNet.setup()", 1, true)).toBeNil()
				local h = Harness.new()
				h:boot()
				h:step(1 / 60, 5)
				expect(h.game.ReplicatedStorage:FindFirstChild("Remotes") ~= nil).toBe(true)
				expect(table.concat(h.errors, "\n")).toBe("")
			end
		)

		it(
			'harnais : StarterGui:GetCore("GetBlockedUserIds") simulé ({} par défaut, liste par joueur, panne)',
			function()
				local hc = Harness.new({ mode = "client" })
				local gui = hc.game.StarterGui
				expect(gui:GetCore("GetBlockedUserIds")).toEqual({})
				hc:setBlocked(hc.localPlayer, { 7, 8 })
				local list = gui:GetCore("GetBlockedUserIds")
				expect(list).toEqual({ 7, 8 })
				list[1] = 99 -- copie : la liste du harnais ne change pas
				expect(gui:GetCore("GetBlockedUserIds")).toEqual({ 7, 8 })
				hc:setBlocked(hc.localPlayer, false)
				expect(pcall(function()
					return gui:GetCore("GetBlockedUserIds")
				end)).toBe(false)
			end
		)

		it(
			"vibrations : la sirène du Rush (cooldownExempt) passe pendant le délai minimal, pas les autres",
			function()
				local hc = Harness.new({ mode = "client", console = true })
				hc:createRemotes()
				local Clock = hc:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(1800000000)
				hc:require("StarterPlayer.StarterPlayerScripts.Client.Util.Platform").Init()
				local Haptics = hc:require("StarterPlayer.StarterPlayerScripts.Client.Util.Haptics")
				Haptics._reset()
				expect(Haptics.play("splorch")).toBe(true) -- priorité 5
				expect(Haptics.play("catch")).toBe(false) -- délai minimal, priorité plus basse
				expect(Haptics.play("rushSiren")).toBe(true) -- exemptée du délai minimal
				Clock.unfreeze()
				expect(#hc.errors).toBe(0)
			end
		)
	end)
end
