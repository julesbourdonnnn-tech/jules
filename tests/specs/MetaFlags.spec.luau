--!nocheck
-- MetaFlags (lot B3, étape 1 ; décisions D1 et D2 du plan B3 ; docs/04 §27.3 règles (1)-(2), §27.5
-- EventState, §27.11 INT-B3-FEATURES) : comment le client sait qu'un système v2.0 est ouvert, sans
-- jamais lire Config/Features.
--   * serveur (INT-B3-FEATURES) : EventState.features.v2 = l'ensemble des interrupteurs OUVERTS parmi la
--     liste fixe RecordR, JellyAscend, PetitSplorch, Confetti, Workshop, Carnet, WeeklyTrack, Mastery,
--     RanchSkins, DecoPerso, Hearts, Personalities, PhotoMode (chacun = true ; les deux derniers : lot B5,
--     INT-B5-FEATURES, journal B5-1) ; clé ABSENTE quand aucun n'est ouvert (charge de la
--     v1.3 identique à celle d'un serveur témoin) ; renvoyé à tous après chaque changement d'interrupteur
--     (commande « feature » d'un administrateur) ; un interrupteur hors liste (Weather…) n'y paraît jamais ;
--   * client (UI/MetaFlags, en fin de fichier) : on(flag), v2Profile(), owned(), attr(name),
--     myPrestige() ; charges hostiles éteintes sans trace ; aucun travail par image.
-- Zéro trace (ZeroLog), horloge figée.
local fs = require("@lune/fs")
local Brains = require("../harness/Brains")
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

local V13_FEATURES = "boopRush,clips,costume,diagnostics,gauge,golden,jellyMoon,megaSquish"
local LISTED = {
	"RecordR",
	"JellyAscend",
	"PetitSplorch",
	"Confetti",
	"Workshop",
	"Carnet",
	"WeeklyTrack",
	"Mastery",
	"RanchSkins",
	"DecoPerso",
	"Hearts",
	"Personalities",
	"PhotoMode",
}

local function keysOf(t)
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function deepEqual(x, y)
	if x == y or (x ~= x and y ~= y) then
		return true
	end
	if type(x) ~= "table" or type(y) ~= "table" then
		return false
	end
	for k, v in x do
		if not deepEqual(v, y[k]) then
			return false
		end
	end
	for k in y do
		if x[k] == nil then
			return false
		end
	end
	return true
end

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- =========================================================================================
	describe("MetaFlags › serveur (INT-B3-FEATURES)", function()
		local function lastState(w, p)
			local list = w.h:sentTo(p, "EventState")
			return list[#list] and list[#list][1]
		end

		-- commande « feature » d'un administrateur (le seau d'AdminCommand, 2 par seconde, est d'abord
		-- rempli : 6 images de 0,1 s) ; rend le nombre d'EventState reçus par `q` aussitôt après
		local ADMIN_FRAMES = 6
		local function admin(w, p, arg, q)
			Brains.frames(w, ADMIN_FRAMES)
			local who = q or p
			local before = #w.h:sentTo(who, "EventState")
			w.h:fireServer("ReplicatedStorage.Remotes.AdminCommand", p, "feature", arg)
			return #w.h:sentTo(who, "EventState") - before
		end

		-- serveur avec deux joueurs (le premier administrateur) ; témoin sans aucun changement
		-- serveur parti de la coupure d'urgence (préréglage « cut » : SchemaV2 seul ouvert ; lot I, étape 2,
		-- D2 a, journal I-19) : chaque cas ouvre en direct ce qu'il prouve, comme un administrateur
		local function boot(t0)
			local w = Brains.boot(Harness, { t0 = t0, preset = "cut" })
			local p = Brains.join(w, 1)
			local q = Brains.join(w, 2)
			w.meta.admins[1] = true
			Brains.frames(w, 2)
			return w, p, q
		end

		it(
			"interrupteurs coupés (configuration livrée) : aucune clé v2, clés de features exactement celles de la v1.3 ; Ambience seul ajoute ambience et jamais v2",
			function()
				local w, p, q = boot(1800000000 + 120)
				for _, key in LISTED do
					expect({ key = key, value = w.Features.get(key) }).toEqual({ key = key, value = false })
				end
				local s = lastState(w, q)
				expect(s.features.v2).toBeNil()
				expect(keysOf(s.features)).toBe(V13_FEATURES)
				expect(w.Event.state().features.v2).toBeNil()
				admin(w, p, "Ambience=true")
				expect(keysOf(lastState(w, q).features)).toBe("ambience," .. V13_FEATURES)
				expect(lastState(w, q).features.v2).toBeNil()
				admin(w, p, "Ambience=false")
				expect(keysOf(lastState(w, q).features)).toBe(V13_FEATURES)
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)

		it(
			"un interrupteur ouvert (feature Carnet=true) : EventState renvoyé à tous avec exactement { Carnet = true } ; recoupé : la clé disparaît",
			function()
				local w, p, q = boot(1800000000 + 120)
				expect(admin(w, p, "Carnet=true", q)).toBe(1)
				expect(w.Features.get("Carnet")).toBe(true)
				for _, who in { p, q } do
					local f = lastState(w, who).features
					expect(deepEqual(f.v2, { Carnet = true })).toBe(true)
					expect(keysOf(f)).toBe(V13_FEATURES .. ",v2")
				end
				expect(admin(w, p, "Carnet=false", q)).toBe(1)
				expect(lastState(w, q).features.v2).toBeNil()
				expect(keysOf(lastState(w, q).features)).toBe(V13_FEATURES)
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)

		it(
			"lot B5 (INT-B5-FEATURES) : Personalities puis PhotoMode ouverts seuls : EventState renvoyé à tous avec exactement cette clé ; recoupés : clé v2 absente",
			function()
				local w, p, q = boot(1800000000 + 120)
				for _, key in { "Personalities", "PhotoMode" } do
					expect({ key = key, value = w.Features.get(key) }).toEqual({ key = key, value = false })
					expect(admin(w, p, key .. "=true", q)).toBe(1)
					for _, who in { p, q } do
						local f = lastState(w, who).features
						expect(deepEqual(f.v2, { [key] = true })).toBe(true)
						expect(keysOf(f)).toBe(V13_FEATURES .. ",v2")
					end
					expect(admin(w, p, key .. "=false", q)).toBe(1)
					expect(lastState(w, q).features.v2).toBeNil()
					expect(keysOf(lastState(w, q).features)).toBe(V13_FEATURES)
				end
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)

		it(
			"toute la liste ouverte : exactement les 13 clés (chacune true ; Personalities et PhotoMode depuis le lot B5) ; les interrupteurs v2.0 hors liste (Weather, UpgradesScreen, Monuments, Helpers…) n'y paraissent jamais",
			function()
				local w, p, q = boot(1800000000 + 120)
				-- hors liste seul : aucune clé v2
				admin(w, p, "Weather=true")
				expect(w.Features.get("Weather")).toBe(true)
				expect(lastState(w, q).features.v2).toBeNil()
				for _, key in LISTED do
					admin(w, p, key .. "=true")
				end
				-- tous les autres interrupteurs booléens de Config/Features ouverts aussi (SchemaV2 est figé)
				for key, value in w.Features.Defaults do
					if
						type(value) == "boolean"
						and not table.find(LISTED, key)
						and not w.Features.Static[key]
					then
						admin(w, p, key .. "=true")
					end
				end
				local v2 = lastState(w, q).features.v2
				expect(type(v2)).toBe("table")
				local sorted = table.clone(LISTED)
				table.sort(sorted)
				expect(keysOf(v2)).toBe(table.concat(sorted, ","))
				for _, key in LISTED do
					expect({ key = key, value = v2[key] }).toEqual({ key = key, value = true })
				end
				expect(v2.Weather).toBeNil()
				expect(v2.UpgradesScreen).toBeNil()
				-- état construit à l'instant : même ensemble
				expect(deepEqual(w.Event.state().features.v2, v2)).toBe(true)
				-- tout recoupé : clé absente
				for _, key in LISTED do
					admin(w, p, key .. "=false")
				end
				expect(lastState(w, q).features.v2).toBeNil()
				expect(table.concat(Brains.problems(w), "\n")).toBe("")
			end
		)

		it(
			"ouvert puis recoupé : charge égale à celle d'un serveur témoin jamais touché (même instant)",
			function()
				local t0 = 1800000000 + 120
				local wA = boot(t0)
				local wB, pB = boot(t0)
				for _, key in LISTED do
					admin(wB, pB, key .. "=true")
				end
				for _, key in LISTED do
					admin(wB, pB, key .. "=false")
				end
				-- le témoin avance des mêmes images (2 × 13 commandes)
				Brains.frames(wA, ADMIN_FRAMES * 2 * #LISTED)
				Brains.frames(wA, 1)
				Brains.frames(wB, 1)
				expect(wA.Clock.now()).toBe(wB.Clock.now())
				local sA, sB = wA.Event.state(), wB.Event.state()
				expect(keysOf(sA.features)).toBe(V13_FEATURES)
				expect(deepEqual(sA.features, sB.features)).toBe(true)
				expect(keysOf(sA)).toBe(keysOf(sB))
				expect(table.concat(Brains.problems(wA), "\n")).toBe("")
				expect(table.concat(Brains.problems(wB), "\n")).toBe("")
			end
		)
	end)
	-- =========================================================================================
	describe("MetaFlags › client (UI/MetaFlags)", function()
		local S = UpgradeScreen.new(Harness)
		local NOW = 1800000000
		local ME = 1 -- joueur local du harnais client

		-- EventState complet (même forme que le serveur) ; `v2` : features.v2 (nil : clé absente)
		local function eventState(v2, spectacle)
			return {
				rush = { active = false, index = 0, endsAt = 0, nextAt = 0, moonBoopable = false },
				mega = {
					phase = "idle",
					index = 0,
					landsAt = 0,
					endsAt = 0,
					target = 0,
					points = 0,
					species = 1,
					moon = false,
					result = "",
				},
				golden = { active = false, id = 0, endsAt = 0 },
				moon = { active = false, session = 0, endsAt = 0, nextAt = 0 },
				gauge = { points = 0, target = 1000, partyUntil = 0, restUntil = 0 },
				boost = { kind = "", untilT = 0, byName = "" },
				spectacle = spectacle or { queue = {} },
				features = {
					boopRush = "on",
					megaSquish = true,
					golden = true,
					jellyMoon = true,
					gauge = true,
					clips = true,
					costume = "",
					diagnostics = true,
					v2 = v2,
				},
				offset = 0,
			}
		end

		local function send(c, v2, spectacle)
			c.h:fireClient("ReplicatedStorage.Remotes.EventState", eventState(v2, spectacle))
			S.run(c, 0.1)
		end

		local function patch(c, values)
			c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", values, {})
			S.run(c, 0.1)
		end

		local function client(opts)
			local c = S.client(opts)
			c.MF = TvAudit.mod(c.h, "UI.MetaFlags")
			c.changed = 0
			c.MF.Changed:Connect(function()
				c.changed += 1
			end)
			return c
		end

		-- liste des interrupteurs ouverts vus par le client (ordre de la liste)
		local function openList(c)
			local out = {}
			for _, key in LISTED do
				if c.MF.on(key) then
					table.insert(out, key)
				end
			end
			return table.concat(out, ",")
		end

		local function ownedList(c)
			local out = {}
			local owned = c.MF.owned()
			local keys = {}
			for k in owned do
				table.insert(keys, k)
			end
			table.sort(keys)
			for _, k in keys do
				table.insert(out, k .. "=" .. tostring(owned[k]))
			end
			return table.concat(out, ",")
		end

		it(
			"aucune clé v2 (configuration livrée), profil v1 : on() faux pour chaque interrupteur, owned() tout faux, v2Profile() faux, aucun Changed",
			function()
				-- profil v1 (préréglage « v13 », lot I D2 a) ; profil v2 : cas suivants
				local c = client({ profile = {}, preset = "v13" })
				send(c, nil)
				expect(openList(c)).toBe("")
				for _, key in LISTED do
					expect({ key = key, on = c.MF.on(key) }).toEqual({ key = key, on = false })
				end
				expect(ownedList(c)).toBe(
					"Carnet=false,DecoPerso=false,JellyAscend=false,Mastery=false,RanchSkins=false,RecordR=false,WeeklyTrack=false,Workshop=false"
				)
				expect(c.MF.v2Profile()).toBe(false)
				expect(c.MF.myPrestige()).toBeNil()
				-- entrées absurdes : faux, jamais d'erreur
				expect(c.MF.on(nil)).toBe(false)
				expect(c.MF.on(5)).toBe(false)
				expect(c.MF.on("Weather")).toBe(false)
				expect(c.changed).toBe(0)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"ensemble exact depuis une table v2 ; owned() suit (gardée tant que le même ensemble revient) ; Changed une fois par vrai changement ; clé inconnue ignorée",
			function()
				local c = client({ profile = {} })
				send(c, { Carnet = true })
				expect(openList(c)).toBe("Carnet")
				expect(c.changed).toBe(1)
				local first = c.MF.owned()
				expect(first.Carnet).toBe(true)
				expect(first.RecordR).toBe(false)
				expect(table.isfrozen(first)).toBe(true)
				-- même ensemble dans un nouvel EventState : ni Changed ni nouvelle table
				send(c, { Carnet = true })
				expect(c.changed).toBe(1)
				expect(c.MF.owned() == first).toBe(true)
				-- deux de plus (dont une hors de Owned.FLAGS) et une clé inconnue, une valeur fausse
				send(c, { Carnet = true, RecordR = true, Hearts = true, Weather = true, Mastery = false })
				expect(openList(c)).toBe("RecordR,Carnet,Hearts")
				expect(c.MF.on("Weather")).toBe(false)
				expect(c.MF.on("Mastery")).toBe(false)
				expect(c.changed).toBe(2)
				local second = c.MF.owned()
				expect(second == first).toBe(false)
				expect(ownedList(c)).toBe(
					"Carnet=true,DecoPerso=false,JellyAscend=false,Mastery=false,RanchSkins=false,RecordR=true,WeeklyTrack=false,Workshop=false"
				)
				-- toute la liste
				local all = {}
				for _, key in LISTED do
					all[key] = true
				end
				send(c, all)
				expect(openList(c)).toBe(table.concat(LISTED, ","))
				expect(c.changed).toBe(3)
				-- recoupé en direct (clé absente) : tout faux
				send(c, nil)
				expect(openList(c)).toBe("")
				expect(c.MF.owned().RecordR).toBe(false)
				expect(c.changed).toBe(4)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			'charges hostiles (v2 = 3, { RecordR = "yes" }, clés non chaînes, 65 entrées…) : tout coupé, sans aucune trace',
			function()
				local c = client({ profile = {} })
				send(c, { RecordR = true })
				expect(openList(c)).toBe("RecordR")
				local big = {}
				for i = 1, 65 do
					big["K" .. i] = true
				end
				big.RecordR = true
				local hostile = {
					3,
					"RecordR",
					true,
					{ RecordR = "yes" },
					{ RecordR = true, JellyAscend = "yes" },
					{ RecordR = 1 },
					{ [1] = true },
					{ RecordR = true, [2] = true },
					{ RecordR = { true } },
					big,
				}
				for i, v2 in hostile do
					send(c, { RecordR = true })
					expect(openList(c)).toBe("RecordR")
					send(c, v2)
					expect({ case = i, open = openList(c) }).toEqual({ case = i, open = "" })
					expect(c.MF.owned().RecordR).toBe(false)
				end
				-- features absente, EventState absurde : ignorés par WorldStateController, rien ne casse
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", { features = 5 })
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", 42)
				S.run(c, 0.1)
				expect(openList(c)).toBe("")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"v2Profile() : version 2 vrai, version 1 faux, valeurs hostiles faux ; Changed suit la version",
			function()
				-- part d'un profil v1 (préréglage « v13 », lot I D2 a)
				local c = client({ profile = {}, preset = "v13" })
				expect(c.MF.v2Profile()).toBe(false)
				patch(c, { version = 2 })
				expect(c.MF.v2Profile()).toBe(true)
				expect(c.changed).toBe(1)
				patch(c, { version = 1 })
				expect(c.MF.v2Profile()).toBe(false)
				expect(c.changed).toBe(2)
				for _, bad in { "2", 2.5, 0 / 0, math.huge, -3, 1e9, true } do
					patch(c, { version = bad })
					expect({ bad = tostring(bad), v2 = c.MF.v2Profile() }).toEqual({
						bad = tostring(bad),
						v2 = false,
					})
				end
				expect(c.changed).toBe(2)
				-- profil v2 dès l'arrivée
				local d = client({ profile = { version = 2 } })
				expect(d.MF.v2Profile()).toBe(true)
				S.clean(c, expect)
				S.clean(d, expect)
			end
		)

		it(
			"attr(name) = attribut de MON ranch (UpgradeSnapshot.ranchAttribute) ; nil sans l'attribut ou pour un nom absurde",
			function()
				local c = client({ profile = {}, ranch = { AscendReady = true, BestR = 12 } })
				expect(c.MF.attr("AscendReady")).toBe(true)
				expect(c.MF.attr("BestR")).toBe(12)
				expect(c.MF.attr("HaloOn")).toBeNil()
				expect(c.MF.attr(5)).toBeNil()
				S.clean(c, expect)
			end
		)

		it(
			"myPrestige() : MON Grand Splorch ou MA Jelly Ascend dans la file → « queued », en cours → « show » ; celui d'un autre, la danse, une entrée abîmée → nil",
			function()
				local c = client({ profile = {} })
				local function entry(kind, userId)
					return {
						kind = kind,
						userId = userId,
						startAt = NOW + 20,
						slot = 1,
						position = 1,
						eta = 20,
					}
				end
				local function current(kind, userId)
					return {
						kind = kind,
						userId = userId,
						startedAt = NOW,
						burstAt = NOW + 4,
						endsAt = NOW + 10,
						level = 16,
					}
				end
				local cases = {
					{ name = "file vide", sp = { queue = {} }, want = nil },
					{
						name = "mon splorch en file",
						sp = { queue = { entry("splorch", ME) } },
						want = "queued",
						kind = "splorch",
					},
					{
						name = "mon ascend en file",
						sp = { queue = { entry("ascend", ME) } },
						want = "queued",
						kind = "ascend",
					},
					{
						name = "mon ascend 2e de la file",
						sp = { queue = { entry("splorch", 77), entry("ascend", ME) } },
						want = "queued",
						kind = "ascend",
					},
					{ name = "splorch d'un autre", sp = { queue = { entry("splorch", 77) } }, want = nil },
					{
						name = "mon splorch en cours",
						sp = { current = current("splorch", ME), queue = {} },
						want = "show",
						kind = "splorch",
					},
					{
						name = "mon ascend en cours",
						sp = { current = current("ascend", ME), queue = {} },
						want = "show",
						kind = "ascend",
					},
					{
						name = "ascend d'un autre",
						sp = { current = current("ascend", 77), queue = {} },
						want = nil,
					},
					{
						name = "danse de Big Plop",
						sp = { current = current("dance", 0), queue = {} },
						want = nil,
					},
					{
						name = "danse avec mon id",
						sp = { current = current("dance", ME), queue = {} },
						want = nil,
					},
					{
						name = "en cours et en file",
						sp = { current = current("splorch", ME), queue = { entry("ascend", ME) } },
						want = "show",
						kind = "splorch",
					},
					{
						name = "entrée abîmée",
						sp = { queue = { 5, "x", { kind = "splorch" }, { userId = ME } } },
						want = nil,
					},
					{ name = "file absurde", sp = { queue = 7 }, want = nil },
					{ name = "id en texte", sp = { queue = { entry("splorch", "1") } }, want = nil },
				}
				for _, case in cases do
					send(c, nil, case.sp)
					-- 2e valeur (lot B3, étape 2) : la sorte du prestige (texte du refus de l'aperçu)
					local state, kind = c.MF.myPrestige()
					expect({ case = case.name, got = state, kind = kind }).toEqual({
						case = case.name,
						got = case.want,
						kind = case.kind,
					})
				end
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"aucun travail par image : start() idempotent (aucune connexion de plus), aucun RunService dans le module",
			function()
				local c = client({ profile = {} })
				local before = c.h:counts().connections
				c.MF.start()
				c.MF.start()
				expect(c.h:counts().connections).toBe(before)
				local src = fs.readFile("src/client/UI/MetaFlags.luau")
				for _, word in
					{
						"RunService",
						"RenderStepped",
						"Heartbeat",
						"BindToRenderStep",
						"Stepped",
						"task.spawn",
						"task.delay",
						"while ",
					}
				do
					expect({ word = word, found = string.find(src, word, 1, true) ~= nil }).toEqual({
						word = word,
						found = false,
					})
				end
				-- jamais Config/Features côté client
				expect(string.find(src, "Config.Features", 1, true)).toBeNil()
				S.clean(c, expect)
			end
		)

		it("_reset() oublie l'état lu : relu au prochain appel depuis le dernier EventState", function()
			local c = client({ profile = {} })
			send(c, { Hearts = true })
			expect(openList(c)).toBe("Hearts")
			c.MF._reset()
			expect(openList(c)).toBe("Hearts")
			S.clean(c, expect)
		end)
	end)

	-- Lot B3, étape 5 (D23) : mesures de diagnostic textScale et styleFallback, envoyées par le seau partagé
	-- de Widgets.send seulement tant que EventState.features.v2 est présent, et pas avant 60 s
	describe("MetaFlags › mesures de diagnostic (lot B3, étape 5, D23)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }
		local function metrics(c, kinds)
			local out = {}
			for _, args in S.sent(c, "ClientMetric") do
				if kinds == nil or kinds[args[1]] then
					table.insert(out, tostring(args[1]) .. "=" .. tostring(args[2]))
				end
			end
			return out
		end
		local D23 = { textScale = true, styleFallback = true }
		-- EventState du serveur (une nouvelle table à chaque fois : la file change)
		local n = 0
		local function event(c, v2)
			n += 1
			S.event(c, v2, { queue = {}, current = nil, seq = n })
		end

		it(
			"interrupteurs coupés : aucune mesure pendant toute une séance (replis, nouvelles mesures, EventState)",
			function()
				local c = S.client({ profile = { onboarding = DONE } })
				local Theme = TvAudit.mod(c.h, "UI.Theme")
				local Text = TvAudit.mod(c.h, "UI.Text")
				for _ = 1, 6 do
					event(c, nil)
					Theme.onStyleFallback("shadow")
					Theme.onStyleFallback("radial")
					Text.remeasure()
					S.run(c, 30)
				end
				expect(metrics(c)).toEqual({})
				S.clean(c, expect)
			end
		)

		it(
			"v2 : textScale une fois après 60 s, puis à chaque nouvelle valeur (3 au plus) ; styleFallback une fois par sorte ; un refus du seau est retenté au déclencheur suivant",
			function()
				local c = S.client({ profile = { version = 2, onboarding = DONE } })
				local Theme = TvAudit.mod(c.h, "UI.Theme")
				local Text = TvAudit.mod(c.h, "UI.Text")
				local MF = TvAudit.mod(c.h, "UI.MetaFlags")
				event(c, UpgradeScreen.V2_ALL)
				Theme.onStyleFallback("shadow")
				S.run(c, 30)
				event(c, UpgradeScreen.V2_ALL)
				-- moins de 60 s après le premier features.v2 : rien
				expect(metrics(c, D23)).toEqual({})
				S.run(c, 31)
				event(c, UpgradeScreen.V2_ALL)
				-- textScale part ; le repli attend le seau (1 envoi par 5 s)
				expect(metrics(c, D23)).toEqual({ "textScale=100" })
				S.run(c, 6)
				event(c, UpgradeScreen.V2_ALL)
				expect(metrics(c, D23)).toEqual({ "textScale=100", "styleFallback=1" })
				-- même sorte encore : rien ; l'autre sorte : une fois
				Theme.onStyleFallback("shadow")
				S.run(c, 6)
				Theme.onStyleFallback("radial")
				Theme.onStyleFallback("radial")
				S.run(c, 6)
				event(c, UpgradeScreen.V2_ALL)
				expect(metrics(c, D23)).toEqual({ "textScale=100", "styleFallback=1", "styleFallback=2" })
				-- facteur du moteur changé (taille de texte du joueur) : nouvelle valeur, 3 envois au plus
				for _, f in { 1.5, 1.5, 1.25, 1.4, 1 } do
					Text.factor = function()
						return f
					end
					S.run(c, 6)
					event(c, UpgradeScreen.V2_ALL)
				end
				expect(metrics(c, D23)).toEqual({
					"textScale=100",
					"styleFallback=1",
					"styleFallback=2",
					"textScale=150",
					"textScale=125",
				})
				expect(MF._metrics().textScale).toBe(3)
				expect(MF._metrics().styleFallback).toEqual({ "shadow", "radial" })
				-- sorte inconnue de repli : ignorée
				Theme.onStyleFallback("glow")
				S.run(c, 6)
				event(c, UpgradeScreen.V2_ALL)
				expect(#metrics(c, D23)).toBe(5)
				S.clean(c, expect)
			end
		)
	end)
end
