--!nocheck
-- Contrat du socle : surface d'API publique des modules repris de Comet Conga, registres partagés
-- (remotes, textes, sons, réglages, boutique), schéma v1, ordres d'initialisation, démarrage complet
-- (serveur, client, écran de chargement), Signals et Notify, Prefs et Format.
-- Un paquet du jeu peut AJOUTER des fonctions, des remotes, des clés ; il ne doit jamais retirer ni
-- renommer ce qui est listé ici (l'architecte étend ce contrat).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

-- Surface d'API publique du socle : module → fonctions et signaux exigés
local API = {
	-- Partagé
	["ReplicatedStorage.Shared.Util.Clock"] = {
		fns = {
			"now",
			"unix",
			"day",
			"week",
			"weekday",
			"secondOfDay",
			"untilNextDay",
			"untilNextWeek",
			"setOffset",
			"getOffset",
			"freeze",
			"advance",
			"unfreeze",
			"isFrozen",
			"reset",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Util.Format"] = {
		fns = { "abbreviate", "commas", "clock", "duration", "percent" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Util.Signal"] = { fns = { "new" }, signals = {} },
	["ReplicatedStorage.Shared.Util.Tables"] = {
		fns = { "deepCopy", "reconcile", "deepEqual", "count", "keys" },
		signals = {},
	},
	["ReplicatedStorage.Shared.Util.Trove"] = { fns = { "new" }, signals = {} },
	["ReplicatedStorage.Shared.Util.Validate"] = {
		fns = {
			"finiteNumber",
			"integer",
			"numberInRange",
			"string",
			"key",
			"boolean",
			"vector3",
			"instanceOf",
		},
		signals = {},
	},
	["ReplicatedStorage.Shared.Net"] = { fns = { "setup", "event", "unreliable", "func" }, signals = {} },
	["ReplicatedStorage.Shared.Localization"] = {
		fns = { "languageFor", "get", "translator", "missingKeys" },
		signals = {},
	},
	-- Serveur
	["ServerScriptService.Server.Services.DataService"] = {
		fns = {
			"Init",
			"Start",
			"get",
			"isLoaded",
			"waitFor",
			"set",
			"increment",
			"markDirty",
			"markDirtyEntry",
			"saveNow",
			"onBeforeSave",
			"setStreamOrder",
		},
		signals = { "Loaded" },
	},
	["ServerScriptService.Server.Services.MonetizationService"] = {
		fns = { "Init", "Start", "registerProduct", "ownsPass" },
		signals = { "PassGranted", "ProductGranted", "PassPurchased", "PassRevoked" },
	},
	["ServerScriptService.Server.Util.RateLimit"] = { fns = { "allow", "clear" }, signals = {} },
	["ServerScriptService.Server.Util.Analytics"] = {
		fns = { "funnel", "earn", "spend", "event" },
		signals = {},
	},
	["ServerScriptService.Server.Util.Notify"] = {
		fns = { "feedback", "celebrate", "banner", "personalBanner" },
		signals = {},
	},
	["ServerScriptService.Server.Util.MoveCheck"] = {
		fns = {
			"setSurface",
			"reset",
			"noteSpeed",
			"step",
			"isRestricted",
			"lastWasBurst",
			"canAct",
			"lastValid",
			"violations",
			"recentRewinds",
			"clear",
		},
		signals = {},
	},
	["ServerScriptService.Server.Data.Schema"] = { fns = { "defaults", "migrate" }, signals = {} },
	-- Client
	["StarterPlayer.StarterPlayerScripts.Client.Util.Platform"] = {
		fns = {
			"Init",
			"Start",
			"isTenFoot",
			"displaySize",
			"isLargeDisplay",
			"chatWindowAllowed",
			"kindFor",
			"inputKind",
			"usingGamepad",
			"gamepadConnected",
			"isGamepadKey",
			"glyph",
			"uiScale",
			"safePadding",
			"applyChatRule",
		},
		signals = { "Changed" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Util.Haptics"] = {
		fns = { "enabled", "play" },
		signals = { "Played" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Util.Prefs"] = {
		fns = {
			"Init",
			"Start",
			"get",
			"reducedMotion",
			"lowGraphics",
			"language",
			"t",
			"number",
			"commas",
			"duration",
		},
		signals = { "Changed", "LanguageChanged" },
	},
	["StarterPlayer.StarterPlayerScripts.Client.Util.Prices"] = { fns = { "observe" }, signals = {} },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Root"] = {
		fns = { "Init", "scale", "screen", "safe", "padding", "selectionImage" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Juice"] = {
		fns = {
			"reducedMotion",
			"tween",
			"scaleOf",
			"pulse",
			"press",
			"popIn",
			"popOut",
			"shake",
			"countTo",
			"flash",
			"cameraShake",
		},
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.UI.Toast"] = { fns = { "show" }, signals = {} },
	["StarterPlayer.StarterPlayerScripts.Client.UI.Glyph"] = {
		fns = { "new", "keyFor", "refresh", "set", "shown", "destroy" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioController"] = {
		fns = { "Init", "Start", "play", "playNav", "setMusicEnabled", "isMusicEnabled" },
		signals = {},
	},
	["StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController"] = {
		fns = { "Init", "Start", "get", "waitReady", "observe" },
		signals = { "Changed", "ReadySignal" },
	},
}

local SERVER_ORDER = { "DataService", "MonetizationService" }

local CLIENT_ORDER = {
	"Client.Util.Platform",
	"Client.UI.Root",
	"Client.Controllers.StateController",
	"Client.Controllers.AudioController",
	"Client.Util.Prefs",
}

local REMOTES = {
	DataSnapshot = "event",
	DataPatch = "event",
	RequestSnapshot = "event",
	Feedback = "event",
	Celebrate = "event",
	Banner = "event",
}

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function shared(h, name)
		return h:require("ReplicatedStorage.Shared." .. name)
	end

	local function hasString(Strings, key)
		return Strings.en[key] ~= nil and Strings.fr[key] ~= nil
	end

	describe("Contrat › Surface d'API des modules du socle", function()
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
					}).toEqual({ path = path, signal = sig, ok = true })
				end
			end
		end)

		it("Create : fonction appelable et Create.Event ; Types : module sans code (table vide)", function()
			local hc = Harness.new({ mode = "client" })
			local Create = hc:require("StarterPlayer.StarterPlayerScripts.Client.UI.Create")
			expect(type(Create.Event)).toBe("function")
			local frame = Create("Frame", { Name = "X" })
			expect(frame.Name).toBe("X")
			local Types = shared(hc, "Types")
			expect(next(Types)).toBeNil()
		end)

		it("Init() et Start() de chaque service et contrôleur de l'ordre existent", function()
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
			-- Root n'a pas de Start : Main.client tolère l'absence d'une des deux phases
			for _, path in CLIENT_ORDER do
				local m = hc:require("StarterPlayer.StarterPlayerScripts." .. path)
				expect({
					path = path,
					any = type(m.Init) == "function" or type(m.Start) == "function",
				}).toEqual({ path = path, any = true })
			end
		end)
	end)

	describe("Contrat › Ordres d'initialisation", function()
		local function orderIn(source, names, prefix)
			local last = 0
			for _, name in names do
				local pos = string.find(source, prefix .. name, 1, true)
				expect({ name = name, found = pos ~= nil }).toEqual({ name = name, found = true })
				expect({ name = name, after = pos > last }).toEqual({ name = name, after = true })
				last = pos
			end
		end

		it("Main.server.luau charge les services du socle dans l'ordre (DataService d'abord)", function()
			local source = fs.readFile("src/server/Main.server.luau")
			orderIn(source, SERVER_ORDER, '"')
			local count = 0
			for _ in string.gmatch(source, '\n\t"%w+Service",') do
				count += 1
			end
			expect(count >= #SERVER_ORDER).toBe(true)
		end)

		it("Main.client.luau charge les modules du socle dans l'ordre (Platform d'abord)", function()
			local source = fs.readFile("src/client/Main.client.luau")
			orderIn(source, CLIENT_ORDER, "\t")
		end)
	end)

	describe("Contrat › Remotes", function()
		it("chaque remote du socle est déclaré avec le bon type", function()
			local h = Harness.new()
			local R = shared(h, "Remotes")
			for name, kind in REMOTES do
				expect({ name = name, kind = R[name] }).toEqual({ name = name, kind = kind })
			end
			for name, kind in R do
				expect({ name = name, valid = kind == "event" or kind == "unreliable" or kind == "func" }).toEqual({
					name = name,
					valid = true,
				})
			end
		end)

		it("Net : un nom non déclaré ou d'un autre type lève une erreur claire", function()
			local h = Harness.new()
			local Net = shared(h, "Net")
			Net.setup()
			expect(function()
				Net.event("NexistePas")
			end).toThrow("non déclaré")
			expect(function()
				Net.func("DataSnapshot")
			end).toThrow("déclaré comme")
			expect(Net.event("DataSnapshot").ClassName).toBe("RemoteEvent")
			Net.setup() -- idempotent : un seul dossier, un remote par nom déclaré
			local declared = 0
			for _ in shared(h, "Remotes") do
				declared += 1
			end
			expect(#h.game.ReplicatedStorage.Remotes:GetChildren()).toBe(declared)
		end)
	end)

	describe("Contrat › Schéma v1", function()
		it("valeurs par défaut sérialisables, une clé = un propriétaire, clés privées", function()
			local h = Harness.new()
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local d = Schema.defaults()
			expect(d.version).toBe(1)
			expect(Schema.VERSION).toBe(1)
			expect(Schema.STORE_NAME).toBe("PlayerData_v1")
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
			expect(type(Schema.STREAMED_KEYS)).toBe("table")
			-- deux appels : deux tables indépendantes (aucun partage entre joueurs)
			local d2 = Schema.defaults()
			d2.settings.music = false
			expect(Schema.defaults().settings.music).toBe(true)
			-- réglages : seulement les clés sauvegardées de Config/Settings, à leur valeur par défaut
			local S = shared(h, "Config.Settings")
			for key, def in S do
				if def.saved then
					expect({ key = key, value = d.settings[key] }).toEqual({ key = key, value = def.default })
				else
					expect(d.settings[key]).toBeNil()
				end
			end
		end)

		it("migre la sauvegarde-témoin v0 (tests/fixtures/profiles/v0.json) sans rien perdre", function()
			local h = Harness.new()
			local Schema = h:require("ServerScriptService.Server.Data.Schema")
			local Tables = shared(h, "Util.Tables")
			local v0 = serde.decode("json", fs.readFile("tests/fixtures/profiles/v0.json"))
			local data = Schema.migrate(v0, 0)
			Tables.reconcile(data, Schema.defaults())
			-- champs anciens gardés (jamais effacés), achats conservés, champs manquants créés
			expect(data.coins).toBe(1234)
			expect(data.passes.VIPStar).toBe(true)
			expect(data.receipts[1]).toBe("achat-ancien-1")
			expect(data.settings.lang).toBe("auto")
			expect(data.flags.lbBanned).toBe(false)
		end)
	end)

	describe("Contrat › Boutique, réglages, sons", function()
		it("boutique : modèle vide, même structure ; chaque article a ses textes EN/FR", function()
			local h = Harness.new()
			local M = shared(h, "Config.Monetization")
			local Strings = shared(h, "Localization.Strings")
			expect(type(M.Passes)).toBe("table")
			expect(type(M.Products)).toBe("table")
			for _, list in { M.Passes, M.Products } do
				for key, def in list do
					expect({ key = key, id = type(def.id), price = type(def.price) }).toEqual({
						key = key,
						id = "number",
						price = "number",
					})
					expect(hasString(Strings, def.nameKey) and hasString(Strings, def.descKey)).toBe(true)
				end
			end
		end)

		it("réglages : types, valeurs par défaut, valeurs permises et textes", function()
			local h = Harness.new()
			local S = shared(h, "Config.Settings")
			local Strings = shared(h, "Localization.Strings")
			for _, key in { "reducedMotion", "lowGraphics", "music", "sfx", "vibration", "lang" } do
				expect({ key = key, declared = S[key] ~= nil }).toEqual({ key = key, declared = true })
			end
			for key, def in S do
				expect(type(def.default)).toBe(def.kind)
				expect(hasString(Strings, "settings." .. key)).toBe(true)
				if def.values then
					expect(def.values[def.default]).toBe(true)
					for value in def.values do
						if key == "lang" then
							expect(hasString(Strings, "settings.lang." .. value)).toBe(true)
						end
					end
				end
			end
		end)

		-- Règle de Comet Conga (passe finale) : un ID est vide (son désactivé) ou exactement
		-- rbxassetid://<nombre>, et un ID rempli porte sur sa ligne de Config/Sounds un commentaire de
		-- provenance (dépôt officiel Roblox/resources ou Roblox/creator-docs et fichier source).
		it(
			"sons : les 8 sons d'interface existent ; ID vide ou rbxassetid://<nombre> ; ID rempli = provenance sur sa ligne",
			function()
				local h = Harness.new()
				local Sounds = shared(h, "Config.Sounds")
				local lines = {}
				for line in string.gmatch(fs.readFile("src/shared/Config/Sounds.luau"), "[^\n]+") do
					local key = string.match(line, "^%s*(%w+)%s*=%s*{")
					if key then
						lines[key] = line
					end
				end
				for _, key in { "Click", "Pop", "Error", "Whoosh", "Select", "Back", "Tab", "Bump" } do
					expect({ key = key, declared = Sounds[key] ~= nil }).toEqual({
						key = key,
						declared = true,
					})
				end
				for key, def in Sounds do
					local id = def.id
					local okId = id == "" or string.match(id, "^rbxassetid://%d+$") ~= nil
					expect({ key = key, id = id, ok = okId }).toEqual({ key = key, id = id, ok = true })
					expect(def.volume > 0 and def.volume <= 1).toBe(true)
					if id ~= "" then
						local line = lines[key] or ""
						local comment = string.match(line, "%-%-%s*(.+)$") or ""
						local declared = string.find(line, 'id%s*=%s*"' .. id .. '"') ~= nil
						local repo = string.find(comment, "Roblox/resources", 1, true) ~= nil
							or string.find(comment, "Roblox/creator-docs", 1, true) ~= nil
						local file = string.match(comment, "[%w_%-/%.]+%.%a+") ~= nil
						expect({ key = key, declared = declared, provenance = repo and file }).toEqual({
							key = key,
							declared = true,
							provenance = true,
						})
					end
				end
			end
		)
	end)

	describe("Contrat › Localisation", function()
		it("parité stricte EN ↔ FR", function()
			local h = Harness.new()
			local L = shared(h, "Localization")
			local Strings = shared(h, "Localization.Strings")
			expect(#L.missingKeys("fr")).toBe(0)
			for key in Strings.fr do
				expect({ key = key, en = Strings.en[key] ~= nil }).toEqual({ key = key, en = true })
			end
		end)

		it("les variables {x} sont identiques en EN et en FR", function()
			local h = Harness.new()
			local Strings = shared(h, "Localization.Strings")
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

		it("clé manquante : retombe sur la clé, un seul avertissement ; variables remplacées", function()
			local h = Harness.new()
			local L = shared(h, "Localization")
			expect(L.languageFor("fr-CA")).toBe("fr")
			expect(L.languageFor("de-de")).toBe("en")
			expect(L.languageFor(nil)).toBe("en")
			local t = L.translator("fr")
			expect(t("common.robux", { price = 99 })).toBe("99 R$")
			expect(t("cle.inexistante")).toBe("cle.inexistante")
			expect(t("cle.inexistante")).toBe("cle.inexistante")
			local warns = 0
			for _, line in h:warnings() do
				if string.find(line, "cle.inexistante", 1, true) then
					warns += 1
				end
			end
			expect(warns).toBe(1)
			-- variable absente : laissée telle quelle (jamais d'erreur)
			expect(t("common.robux")).toBe("{price} R$")
		end)
	end)

	describe("Contrat › Démarrage complet", function()
		it(
			"le serveur démarre, accueille, fait avancer le temps et libère des joueurs sans erreur",
			function()
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
			end
		)

		it(
			"Main.server isole les pannes : un Init et un Start qui lèvent n'arrêtent pas les suivants",
			function()
				local h = Harness.new()
				local DS = h:require("ServerScriptService.Server.Services.DataService")
				local M = h:require("ServerScriptService.Server.Services.MonetizationService")
				DS.Init = function()
					error("Init en panne (simulée)")
				end
				local started = false
				local start = M.Start
				M.Start = function()
					started = true
					start()
				end
				DS.Start = function()
					error("Start en panne (simulée)")
				end
				h:boot()
				expect(started).toBe(true)
				local warned = 0
				for _, line in h:warnings() do
					if string.find(line, "DataService", 1, true) then
						warned += 1
					end
				end
				expect(warned).toBe(2)
				expect(#h.errors).toBe(0)
			end
		)

		it("joueur déjà présent avant le démarrage : chargé quand même", function()
			local h = Harness.new()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			local p = h:addPlayer({ userId = 103, name = "Early" })
			h:boot()
			expect(DS.waitFor(p, 2) ~= nil).toBe(true)
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

		it("le client démarre avec tous les modules du socle et reçoit son profil", function()
			local h = Harness.new({ mode = "client", touch = true })
			h:createRemotes()
			h:boot()
			local Schema = Harness.new():require("ServerScriptService.Server.Data.Schema")
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", Schema.defaults())
			h:step(1 / 60, 20)
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
			-- filet de l'écran de chargement : ClientReady posé dès l'instantané du profil
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it(
			"Main.client isole les pannes : un module qui lève n'empêche pas les suivants ni ClientReady",
			function()
				local h = Harness.new({ mode = "client" })
				h:createRemotes()
				local Audio =
					h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioController")
				Audio.Init = function()
					error("Init en panne (simulée)")
				end
				local Prefs = h:require("StarterPlayer.StarterPlayerScripts.Client.Util.Prefs")
				local prefsStarted = false
				local start = Prefs.Start
				Prefs.Start = function()
					prefsStarted = true
					start()
				end
				h:boot()
				h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { settings = {} })
				h:settle(3)
				expect(prefsStarted).toBe(true)
				expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
				local warned = false
				for _, line in h:warnings() do
					if string.find(line, "AudioController.Init", 1, true) then
						warned = true
					end
				end
				expect(warned).toBe(true)
			end
		)
	end)

	describe("Contrat › Démarrage complet : module qui ne se charge pas", function()
		it("require qui lève (client) : signalé, les autres démarrent, ClientReady au profil", function()
			local h = Harness.new({ mode = "client" })
			h:createRemotes()
			-- require du module en échec (même effet qu'une erreur au chargement du module)
			h.loading[h:find("StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioController")] = true
			local ok = pcall(function()
				h:boot()
			end)
			expect(ok).toBe(true)
			local warned = false
			for _, line in h:warnings() do
				if
					string.find(line, "AudioController", 1, true) and string.find(line, "require", 1, true)
				then
					warned = true
				end
			end
			expect(warned).toBe(true)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { settings = {} })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("require qui lève (serveur) : signalé, les autres services démarrent et accueillent", function()
			local h = Harness.new()
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			h.loading[h:find("ServerScriptService.Server.Services.MonetizationService")] = true
			local ok = pcall(function()
				h:boot()
			end)
			expect(ok).toBe(true)
			local warned = false
			for _, line in h:warnings() do
				if
					string.find(line, "MonetizationService", 1, true)
					and string.find(line, "require", 1, true)
				then
					warned = true
				end
			end
			expect(warned).toBe(true)
			local p = h:addPlayer({ userId = 104 })
			expect(DS.waitFor(p, 2) ~= nil).toBe(true)
			expect(#h.errors).toBe(0)
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
			for _, name in { "ServerMoved", "MoveViolation", "BannerRequested" } do
				expect(Signals[name] ~= nil).toBe(true)
			end
			expect(n >= 3).toBe(true)
		end)

		it("Notify envoie Feedback, Celebrate et bannières aux bons destinataires", function()
			local h = Harness.new()
			h:boot()
			local Notify = h:require("ServerScriptService.Server.Util.Notify")
			local Signals = h:require("ServerScriptService.Server.Signals")
			Notify.BANNER_PRIORITY.welcomeBack = 1
			local p = h:addPlayer({ userId = 7, name = "Lea" })
			Notify.feedback(p, "feedback.notEnoughCoins", { missing = 1200 }, "error")
			Notify.celebrate(p, "upgrade", { level = 4 })
			Notify.personalBanner(p, "welcomeBack")
			Notify.personalBanner(p, "sorteInconnue")
			local fb = h:sentTo(p, "Feedback")
			expect(#fb).toBe(1)
			expect(fb[1][1]).toEqual({
				key = "feedback.notEnoughCoins",
				vars = { missing = 1200 },
				tone = "error",
			})
			local cel = h:sentTo(p, "Celebrate")
			expect(cel[1][1].kind).toBe("upgrade")
			expect(cel[1][1].data.level).toBe(4)
			local ban = h:sentTo(p, "Banner")
			expect(ban[1][1].personal).toBe(true)
			expect(ban[1][1].priority).toBe(1)
			expect(ban[2][1].priority).toBe(Notify.DEFAULT_PRIORITY)
			-- valeurs par défaut : vars {}, ton "info"
			Notify.feedback(p, "feedback.saved")
			expect(h:sentTo(p, "Feedback")[2][1]).toEqual({ key = "feedback.saved", vars = {}, tone = "info" })
			local seen = nil
			Signals.BannerRequested:Connect(function(kind, args, source)
				seen = { kind = kind, n = args.n, source = source }
			end)
			Notify.banner("rareHatch", { n = 31 }, p)
			h:settle(1)
			expect(seen).toEqual({ kind = "rareHatch", n = 31, source = p })
			-- joueur parti : rien n'est envoyé, aucune erreur
			h:removePlayer(p)
			Notify.feedback(p, "feedback.maxLevel")
			Notify.celebrate(p, "upgrade")
			Notify.personalBanner(p, "welcomeBack")
			expect(#h:sentTo(p, "Feedback")).toBe(2)
			expect(#h.errors).toBe(0)
		end)

		it("chaque bannière déclarée a une priorité de 1 à 7 et un texte EN/FR", function()
			local h = Harness.new()
			local Notify = h:require("ServerScriptService.Server.Util.Notify")
			local Strings = shared(h, "Localization.Strings")
			expect(Notify.DEFAULT_PRIORITY).toBe(7)
			for kind, prio in Notify.BANNER_PRIORITY do
				expect(prio >= 1 and prio <= 7).toBe(true)
				expect({ kind = kind, text = hasString(Strings, "banner." .. kind) }).toEqual({
					kind = kind,
					text = true,
				})
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
				settings = { reducedMotion = true, sfx = false, music = false, lang = "fr", inconnu = true },
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
			-- lot B1 (INT-V2-GLYPHS d) : espace ordinaire, FredokaOne n'a pas U+00A0
			expect(Prefs.number(1240000)).toBe("1,24 M")
			expect(Prefs.get("vibration")).toBe(true) -- valeur par défaut conservée
			expect(Prefs.get("inconnu")).toBeNil() -- clé hors de Config/Settings ignorée
			-- valeurs de mauvais type ignorées
			Prefs._onSettings({ reducedMotion = "oui", lang = 3 })
			expect(Prefs.reducedMotion()).toBe(false)
			expect(Prefs.language()).toBe("en")
		end)

		-- lot B1 (INT-V2-GLYPHS d, GDD v2.0 §10.8 règle 18) : espaces ORDINAIRES en français (le texte
		-- courant est en FredokaOne, qui n'a pas U+00A0) ; aucune espace insécable écrite
		it("Format : 100K reste 100K ; français avec virgule et espaces ordinaires (FredokaOne)", function()
			local h = Harness.new()
			local F = shared(h, "Util.Format")
			expect(F.abbreviate(100000)).toBe("100K")
			expect(F.abbreviate(120000)).toBe("120K")
			expect(F.abbreviate(1000000000)).toBe("1B")
			expect(F.abbreviate(1240000, "fr")).toBe("1,24 M")
			expect(F.abbreviate(1000000000, "fr")).toBe("1 Md")
			expect(F.abbreviate(-2500, "fr")).toBe("-2,5 k")
			expect(F.commas(1234567, "fr")).toBe("1 234 567")
			expect(F.commas(123456)).toBe("123,456")
			expect(F.duration(18720, "fr")).toBe("5 h 12")
			expect(F.duration(90, "fr")).toBe("1 min 30 s")
			for _, text in
				{
					F.abbreviate(1240000, "fr"),
					F.commas(1234567, "fr"),
					F.duration(18720, "fr"),
					F.duration(42, "fr"),
				}
			do
				expect(string.find(text, "\194\160", 1, true)).toBeNil()
			end
		end)
	end)
end
