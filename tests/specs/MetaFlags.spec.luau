--!nocheck
-- MetaFlags (lot B3, étape 1 ; décisions D1 et D2 du plan B3 ; docs/04 §27.3 règles (1)-(2), §27.5
-- EventState, §27.11 INT-B3-FEATURES) : comment le client sait qu'un système v2.0 est ouvert, sans
-- jamais lire Config/Features.
--   * serveur (INT-B3-FEATURES) : EventState.features.v2 = l'ensemble des interrupteurs OUVERTS parmi la
--     liste fixe RecordR, JellyAscend, PetitSplorch, Confetti, Workshop, Carnet, WeeklyTrack, Mastery,
--     RanchSkins, DecoPerso, Hearts (chacun = true) ; clé ABSENTE quand aucun n'est ouvert (charge de la
--     v1.3 identique à celle d'un serveur témoin) ; renvoyé à tous après chaque changement d'interrupteur
--     (commande « feature » d'un administrateur) ; un interrupteur hors liste (Weather…) n'y paraît jamais ;
--   * client (UI/MetaFlags, en fin de fichier) : on(flag), v2Profile(), owned(), attr(name),
--     myPrestige() ; charges hostiles éteintes sans trace ; aucun travail par image.
-- Zéro trace (ZeroLog), horloge figée.
local Brains = require("../harness/Brains")

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
		local function boot(t0)
			local w = Brains.boot(Harness, { t0 = t0 })
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
			"toute la liste ouverte : exactement les 11 clés (chacune true) ; les interrupteurs v2.0 hors liste (Weather, UpgradesScreen, Monuments, Helpers…) n'y paraissent jamais",
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
					if type(value) == "boolean" and not table.find(LISTED, key) and not w.Features.Static[key] then
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
				-- le témoin avance des mêmes images (2 × 11 commandes)
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
end
