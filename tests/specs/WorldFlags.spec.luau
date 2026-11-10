--!nocheck
-- World/Flags (lot B5, étape 1 ; décision D2 du plan B5 ; docs/04 §27.3 règles (1)-(2), §27.5
-- EventState, §27.11 INT-B3-FEATURES et INT-B5-FEATURES) : le portail du RENDU vers les interrupteurs
-- de la v2.0 (EventState.features.v2), à côté de UI/MetaFlags (le portail des écrans).
--   * même liste fixe que UI/MetaFlags et qu'EventService (13 interrupteurs, Personalities et
--     PhotoMode compris depuis le lot B5) ;
--   * Flags.on(x) == MetaFlags.on(x) pour chaque interrupteur et chaque charge, hostile ou non ;
--   * Changed une fois par vrai changement de l'ensemble ouvert ;
--   * état reçu AVANT le chargement du module : lu au chargement ;
--   * aucun travail par image : on() ne relit jamais le miroir, aucune boucle, aucun module d'écran.
-- Zéro trace (ZeroLog), horloge figée.
local fs = require("@lune/fs")
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

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
-- noms hors liste (interrupteurs v2.0 qui ont un autre signal, noms inconnus) : jamais ouverts
local OUTSIDE = { "Weather", "Fete", "Helpers", "UpgradesScreen", "Ambience", "SchemaV2", "nope", "" }

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local S = UpgradeScreen.new(Harness)

	local function client(opts)
		local c = S.client(opts or { profile = {} })
		c.MF = TvAudit.mod(c.h, "UI.MetaFlags")
		c.F = TvAudit.mod(c.h, "World.Flags")
		c.changed = 0
		c.F.Changed:Connect(function()
			c.changed += 1
		end)
		return c
	end

	local function send(c, v2)
		S.event(c, v2)
	end

	-- les deux portails répondent pareil pour chaque nom ; rend la liste ouverte (ordre de la liste)
	local function same(c, label)
		local open = {}
		for _, key in LISTED do
			local a, b = c.F.on(key), c.MF.on(key)
			expect({ label, key, a }).toEqual({ label, key, b })
			if a then
				table.insert(open, key)
			end
		end
		for _, key in OUTSIDE do
			expect({ label, key, c.F.on(key) }).toEqual({ label, key, false })
			expect({ label, key, c.MF.on(key) }).toEqual({ label, key, false })
		end
		return table.concat(open, ",")
	end

	describe("World/Flags (lot B5, D2)", function()
		it(
			"liste fixe : la même que UI/MetaFlags.FLAGS et que V2_CLIENT_FLAGS d'EventService (13 interrupteurs, même ordre), gelée",
			function()
				local c = client()
				expect(c.F.FLAGS).toEqual(LISTED)
				expect(c.MF.FLAGS).toEqual(LISTED)
				expect(table.isfrozen(c.F.FLAGS)).toBe(true)
				local src = fs.readFile("src/server/Services/EventService.luau")
				local block = string.match(src, "local V2_CLIENT_FLAGS = {(.-)\n}")
				expect(block ~= nil).toBe(true)
				local server = {}
				for name in string.gmatch(block, '"(%w+)"') do
					table.insert(server, name)
				end
				expect(server).toEqual(LISTED)
				S.clean(c, expect)
			end
		)

		it(
			"configuration livrée (aucune clé v2) : tout coupé, aucun Changed ; noms absurdes : faux, jamais d'erreur",
			function()
				local c = client()
				send(c, nil)
				expect(same(c, "livré")).toBe("")
				expect(c.changed).toBe(0)
				for _, bad in { 5, true, {}, 0 / 0 } do
					expect(c.F.on(bad)).toBe(false)
				end
				expect(c.F.on(nil)).toBe(false)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"égal à MetaFlags.on pour chaque interrupteur : un seul, plusieurs, toute la liste, clé inconnue, valeur fausse, recoupé ; Changed une fois par vrai changement",
			function()
				local c = client()
				for i, key in LISTED do
					send(c, { [key] = true })
					expect(same(c, key)).toBe(key)
					expect(c.changed).toBe(i)
				end
				local n = c.changed
				-- même ensemble dans un nouvel EventState : pas de Changed
				send(c, { PhotoMode = true })
				expect(c.changed).toBe(n)
				send(
					c,
					{ Personalities = true, PhotoMode = true, Weather = true, Mastery = false, Zzz = true }
				)
				expect(same(c, "mélange")).toBe("Personalities,PhotoMode")
				expect(c.changed).toBe(n + 1)
				local all = {}
				for _, key in LISTED do
					all[key] = true
				end
				send(c, all)
				expect(same(c, "tout")).toBe(table.concat(LISTED, ","))
				expect(c.changed).toBe(n + 2)
				send(c, nil)
				expect(same(c, "recoupé")).toBe("")
				expect(c.changed).toBe(n + 3)
				S.clean(c, expect)
			end
		)

		it(
			'charges hostiles (v2 = 3, { Personalities = "yes" }, clés non chaînes, 65 entrées…) : tout coupé comme UI/MetaFlags, sans aucune trace',
			function()
				local c = client()
				local big = {}
				for i = 1, 65 do
					big["K" .. i] = true
				end
				big.Personalities = true
				local hostile = {
					3,
					"Personalities",
					true,
					{ Personalities = "yes" },
					{ Personalities = true, PhotoMode = "yes" },
					{ Personalities = 1 },
					{ [1] = true },
					{ Personalities = true, [2] = true },
					{ Personalities = { true } },
					big,
				}
				for i, v2 in hostile do
					send(c, { Personalities = true })
					expect(same(c, "avant " .. i)).toBe("Personalities")
					local before = c.changed
					send(c, v2)
					expect({ i, same(c, "hostile " .. i) }).toEqual({ i, "" })
					expect(c.changed).toBe(before + 1)
				end
				-- EventState absurde : ignoré par le miroir, l'ensemble lu reste
				send(c, { PhotoMode = true })
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", { features = 5 })
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", 42)
				S.run(c, 0.1)
				expect(same(c, "absurde")).toBe("PhotoMode")
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"aucun travail par image : on() ne relit jamais le miroir (EventChanged seulement), aucune boucle ni module d'écran dans le module",
			function()
				local c = client()
				send(c, { Personalities = true })
				local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
				local real = WSC.event
				local reads = 0
				WSC.event = function(...)
					reads += 1
					return real(...)
				end
				-- 13 000 appels de on() : aucune lecture du miroir, aucune connexion de plus (d'autres modules
				-- du client lisent le miroir à chaque image : on ne compte que pendant ces appels)
				local connections = c.h:counts().connections
				for _ = 1, 1000 do
					for _, key in LISTED do
						c.F.on(key)
					end
				end
				expect(reads).toBe(0)
				expect(c.h:counts().connections).toBe(connections)
				-- 120 images sans EventState : l'ensemble lu ne bouge pas, aucun Changed
				local changed = c.changed
				for _ = 1, 120 do
					S.run(c, 1 / 60)
				end
				expect(c.F.on("Personalities")).toBe(true)
				expect(c.changed).toBe(changed)
				reads = 0
				-- un EventState : une lecture (deux portails : UI/MetaFlags lit aussi)
				send(c, { PhotoMode = true })
				expect(reads >= 1).toBe(true)
				expect(c.F.on("PhotoMode")).toBe(true)
				WSC.event = real
				local src = fs.readFile("src/client/World/Flags.luau")
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
						"Config.Features",
						"Client.UI",
					}
				do
					expect({ word = word, found = string.find(src, word, 1, true) ~= nil }).toEqual({
						word = word,
						found = false,
					})
				end
				S.clean(c, expect)
			end
		)

		it(
			"EventState reçu AVANT le chargement du module : l'ensemble est lu au chargement ; _reset() relit le dernier état",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h:createRemotes()
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(1800000000)
				local base = "StarterPlayer.StarterPlayerScripts.Client."
				h:require(base .. "Util.Prefs").Init()
				h:require(base .. "Controllers.StateController").Init()
				local WSC = h:require(base .. "Controllers.WorldStateController")
				WSC.Init()
				WSC.Start()
				h:fireClient(
					"ReplicatedStorage.Remotes.EventState",
					UpgradeScreen.eventState({ Personalities = true, Hearts = true })
				)
				h:settle(1)
				local F = h:require(base .. "World.Flags")
				expect(F.on("Personalities")).toBe(true)
				expect(F.on("Hearts")).toBe(true)
				expect(F.on("PhotoMode")).toBe(false)
				local changed = 0
				F.Changed:Connect(function()
					changed += 1
				end)
				F._reset()
				expect(F.on("Personalities")).toBe(true)
				expect(changed).toBe(1)
				expect(table.concat(h.errors, "\n")).toBe("")
				expect(table.concat(h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
