--!nocheck
-- RanchService_v2 (lot A2, étape 2 ; docs/04 §27.5, §27.7, §27.13 N7, N21) : attributs
-- Types.RanchAttributesV2 posés sur le modèle du ranch (Ranches/<k>, répliqué à tous) et place d'enclos
-- offerte.
--   * interrupteurs coupés : aucun attribut v2.0 posé, jamais (le jeu de base envoie la même chose) ;
--   * BestR [RecordR], SplorchReady [RecordR, d'EconomyService], Monuments [Monuments], TapisTier /
--     GloveTier / ApronTier [RanchTiers] : posés au chargement, recalculés après un achat et un Grand
--     Splorch, effacés quand leur interrupteur se coupe, et quand le ranch est libéré ;
--   * setV2Attributes : noms et sortes du contrat seulement (NaN, inf, mauvais type, nom inconnu :
--     refusés), valeurs gardées jusqu'à l'attribution du ranch ;
--   * offeredPlace : ranch reconstruit, enclos déjà plein → Feedback « +n Confettis ».
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local NAMES = {
		"BestR",
		"Ascend",
		"SplorchReady",
		"AscendReady",
		"PetitSplorchAt",
		"Monuments",
		"DecoPerso",
		"HaloOn",
		"TapisTier",
		"GloveTier",
		"ApronTier",
	}

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 1, z = 10, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	local function boot(flags, profile)
		local caught = {}
		local w = Bots.boot(HarnessV2, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
				w.F = w.h:require(L .. "Config.Features")
				for _, key in flags do
					assert(w.F.set(key, true), key)
				end
				local d = Bots.profile(w, {
					onboarding = { step = 11, done = true, demoDone = true },
					squishies = { ["1"] = rec({ bf = 1 }) },
					nextUid = 2,
				})
				d.tiles.seen = 15
				d.trophies[1] = 1e5
				d.coins = 1e14
				d.R = 6
				d.bestR = 12
				d.unlocksSeen = 12
				d.tiles.snack = 12
				d.tiles.star = 1
				d.tiles.gloves = 10
				d.tiles.monuments = 2
				if profile then
					profile(d)
				end
				Bots.saveProfile(w, 1, d)
			end,
		})
		w.caught = caught
		w.Economy = w.h:require(S .. "EconomyService")
		w.Ranch = w.h:require(S .. "RanchService")
		w.World = w.h:require(S .. "WorldService")
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function attrs(w, slot)
		local model = w.World.ranchModel(slot)
		local out = {}
		for _, name in NAMES do
			out[name] = model:GetAttribute(name)
		end
		return out
	end

	describe("RanchService_v2 › attributs du ranch", function()
		it(
			"interrupteurs coupés : aucun attribut v2.0, même après un achat, un Grand Splorch et 30 s de jeu",
			function()
				local w = boot({})
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				w.Economy.buyTile(p, "decor", "panel")
				w.Economy.applySplorch(p)
				for _ = 1, 30 do
					w.Clock.advance(1)
					w.Economy.step(w.Clock.now())
				end
				w.h:settle(3)
				expect(attrs(w, slot)).toEqual({})
				clean(w)
			end
		)

		it(
			"ouverts : BestR, SplorchReady, Monuments et paliers posés au chargement, recalculés après un achat et un Grand Splorch",
			function()
				local w =
					boot({ "UpgradesScreen", "RecordR", "Monuments", "RanchTiers", "StarMat", "Gloves" })
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				local data = w.DS.get(p)
				w.Economy.step(w.Clock.now())
				w.h:settle(3)
				local TierRules = w.h:require(L .. "Logic.TierRules")
				expect(attrs(w, slot)).toEqual({
					BestR = 12,
					SplorchReady = false,
					Monuments = 2,
					TapisTier = TierRules.of("star", 1),
					GloveTier = TierRules.of("gloves", 10),
					ApronTier = 0,
				})
				-- achat d'un Monument : attribut recalculé (UpgradeBought)
				w.Economy.buyUpgrade(p, "monument", 1, 2)
				w.h:settle(3)
				expect(attrs(w, slot).Monuments).toBe(3)
				-- Gants 15 : palier suivant
				w.Economy.buyUpgrade(p, "gloves", 0, 10)
				w.h:settle(3)
				expect(attrs(w, slot).GloveTier).toBe(TierRules.of("gloves", data.tiles.gloves))
				-- squishy à l'objectif : SplorchReady (toutes les secondes)
				data.squishies["1"].z = 1e30
				w.Clock.advance(1.5)
				w.Economy.step(w.Clock.now())
				expect(attrs(w, slot).SplorchReady).toBe(true)
				-- Grand Splorch : r 7, Record R 12 inchangé ; Tapis remis à zéro → palier 0
				w.Economy.applySplorch(p)
				w.h:require(S .. "SquishyService").resetSizes(p)
				w.Signals.Splorched:Fire(p, 7, 0)
				w.Clock.advance(1.5)
				w.Economy.step(w.Clock.now())
				w.h:settle(3)
				local a = attrs(w, slot)
				expect({ a.BestR, a.TapisTier, a.SplorchReady }).toEqual({ 12, 0, false })
				clean(w)
			end
		)

		it(
			"un interrupteur coupé en direct efface ses attributs ; le ranch libéré n'en garde aucun",
			function()
				local w = boot({ "UpgradesScreen", "RecordR", "Monuments", "RanchTiers" })
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				w.Economy.step(w.Clock.now())
				w.h:settle(3)
				expect(attrs(w, slot).Monuments).toBe(2)
				w.F.set("Monuments", false)
				w.Ranch.refreshV2(p)
				expect(attrs(w, slot).Monuments).toBeNil()
				expect(attrs(w, slot).BestR).toBe(12)
				w.F.set("RecordR", false)
				w.Clock.advance(1.5)
				w.Economy.step(w.Clock.now())
				w.Ranch.refreshV2(p)
				local a = attrs(w, slot)
				expect({ a.BestR, a.SplorchReady }).toEqual({ nil, nil })
				expect(a.TapisTier ~= nil).toBe(true)
				Bots.leave(p)
				w.h:settle(5)
				expect(attrs(w, slot)).toEqual({})
				clean(w)
			end
		)

		it(
			"setV2Attributes : noms et sortes du contrat seulement ; NaN, inf, mauvais type, nom inconnu, chaîne trop longue refusés",
			function()
				local w = boot({})
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				w.Ranch.setV2Attributes(p, {
					BestR = 0 / 0,
					Ascend = math.huge,
					SplorchReady = "oui",
					PetitSplorchAt = -math.huge,
					Monuments = true,
					DecoPerso = string.rep("1,", 40),
					HaloOn = 1,
					Unknown = 3,
					[1] = 2,
				})
				expect(attrs(w, slot)).toEqual({})
				w.Ranch.setV2Attributes(p, {
					Ascend = 2,
					AscendReady = true,
					PetitSplorchAt = 123.5,
					DecoPerso = "1,0,0,0,0,0,0,0,0,0,0,0",
					HaloOn = false,
				})
				expect(attrs(w, slot)).toEqual({
					Ascend = 2,
					AscendReady = true,
					PetitSplorchAt = 123.5,
					DecoPerso = "1,0,0,0,0,0,0,0,0,0,0,0",
					HaloOn = false,
				})
				w.Ranch.setV2Attributes(p, {}, { "Ascend", "Bogus" })
				expect(attrs(w, slot).Ascend).toBeNil()
				expect(attrs(w, slot).AscendReady).toBe(true)
				-- appels illisibles : rien, aucune erreur
				w.Ranch.setV2Attributes(nil, { Ascend = 1 })
				w.Ranch.setV2Attributes(p, nil)
				w.Ranch.setV2Attributes(p, { Ascend = 1 }, 5)
				clean(w)
			end
		)
	end)

	describe("RanchService_v2 › place d'enclos offerte", function()
		it(
			"offeredPlace : ranch reconstruit ; enclos déjà plein → Feedback « Enclos déjà plein : +n Confettis »",
			function()
				local w = boot({ "UpgradesScreen", "Confetti" })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local builds = 0
				local original = w.Ranch.refreshBuild
				w.Ranch.refreshBuild = function(player)
					if player == p then
						builds += 1
					end
					return original(player)
				end
				data.tiles.pens = 7
				w.Ranch.offeredPlace(p, false, 0)
				expect(builds).toBe(1)
				expect(table.find(Bots.feedbackKeys(p), "confetti.fullPen")).toBeNil()
				w.Ranch.offeredPlace(p, true, 25)
				w.h:settle(2)
				local sent = w.h:sentTo(p, "Feedback")
				local last = sent[#sent][1]
				expect({ last.key, last.vars.n }).toEqual({ "confetti.fullPen", 25 })
				-- arguments illisibles : aucun Feedback de plus, aucune erreur
				local n = #w.h:sentTo(p, "Feedback")
				w.Ranch.offeredPlace(p, true, 0 / 0)
				w.Ranch.offeredPlace(p, true, -1)
				w.h:settle(2)
				expect(#w.h:sentTo(p, "Feedback")).toBe(n)
				clean(w)
			end
		)
	end)
end
