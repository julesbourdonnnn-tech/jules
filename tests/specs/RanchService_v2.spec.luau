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
--   * offeredPlace : ranch reconstruit, enclos déjà plein → Feedback « +n Confettis » ;
--   * lot A4 (D31) : DecorGold [RanchTiers] (bit k − 1 : decorBuilds[k] ≥ 10) et GoldPennants
--     [Workshop] (« Fanions dorés » achetés) sur un profil v2 seulement ; les 7 attributs du lot A4
--     (HelperMode, Helpers, GiantTier, DecorGold, GoldPennants, Palette, Cushions) absents tant que
--     tout est coupé.
local Flags = require("../harness/Flags")
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
		-- lot A4
		"HelperMode",
		"Helpers",
		"GiantTier",
		"DecorGold",
		"GoldPennants",
		"Palette",
		"Cushions",
	}

	local function rec(extra)
		local r =
			{ s = 1, m = 0, st = 1, z = 10, zg = 0, bf = 0, lk = false, o = "", at = "pen", b = 100, gd = 0 }
		for k, v in extra or {} do
			r[k] = v
		end
		return r
	end

	-- harness : HarnessV2 (profils v2) par défaut ; Harness pour un profil v1
	local function boot(flags, profile, harness)
		local caught = {}
		local w = Bots.boot(harness or HarnessV2, {
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
				d.tiles.snack = 12
				if d.version >= 2 then
					d.bestR = 12
					d.unlocksSeen = 12
					d.tiles.star = 1
					d.tiles.gloves = 10
					d.tiles.monuments = 2
				end
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
				-- DecorGold [RanchTiers] : attente ajoutée au lot A4 (D31, journal A4-5), aucune dorée ;
				-- Palette = "" (palette du ranch) : posée par CommunityService dès qu'une source de palette
				-- est ouverte (RecordR : palette du Record R 9 ; lot A4, A4-36), attente ajoutée à la relecture
				-- du lot A4 (A4-53 : la spec n'avait pas été relancée aux étapes 5 et 6)
				expect(attrs(w, slot)).toEqual({
					BestR = 12,
					SplorchReady = false,
					Monuments = 2,
					TapisTier = TierRules.of("star", 1),
					GloveTier = TierRules.of("gloves", 10),
					ApronTier = 0,
					DecorGold = 0,
					Palette = "",
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

	describe("RanchService_v2 › décorations et fanions dorés (lot A4, D31)", function()
		it(
			"DecorGold [RanchTiers] et GoldPennants [Workshop] : posés sur un profil v2, recalculés à l'achat et au prestige, effacés en direct, rien au départ",
			function()
				local w = boot({ "UpgradesScreen", "Confetti", "Workshop", "RanchTiers" }, function(d)
					d.decorBuilds[1] = 10
					d.decorBuilds[3] = 9
					d.decorBuilds[18] = 10
					d.confetti, d.confettiTotal = 100, 100
				end)
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				local data = w.DS.get(p)
				w.h:settle(3)
				local a = attrs(w, slot)
				expect({ a.DecorGold, a.GoldPennants }).toEqual({ 1 + 2 ^ 17, false })
				-- « Fanions dorés » de « Pour le plaisir » achetés : posé à l'achat (UpgradeBought)
				local result = w.Economy.buyUpgrade(p, "pennants", 1, 0)
				expect(result.to).toBe(1)
				w.h:settle(3)
				expect(attrs(w, slot).GoldPennants).toBe(true)
				-- 10e boucle de la décoration 3 : dorée au prestige suivant (PrestigeApplied)
				data.decorBuilds[3] = 10
				w.Signals.PrestigeApplied:Fire(p, "splorch", 6, 7, 0)
				w.h:settle(3)
				expect(attrs(w, slot).DecorGold).toBe(1 + 4 + 2 ^ 17)
				-- Workshop coupé en direct : GoldPennants effacé au tick suivant, DecorGold gardé
				w.F.set("Workshop", false)
				w.Ranch.step(w.Clock.now(), {})
				a = attrs(w, slot)
				expect({ a.GoldPennants, a.DecorGold }).toEqual({ nil, 1 + 4 + 2 ^ 17 })
				-- RanchTiers coupé : DecorGold effacé (et les paliers) ; rouvert : reposé. Palette = "" de
				-- CommunityService (sorte ouverte par Workshop, lot A4, A4-36) : effacée à son tick suivant
				-- (≤ 1 s) une fois Workshop coupé, AVANT la vue exacte (relecture du lot A4, A4-53)
				w.F.set("RanchTiers", false)
				w.Ranch.step(w.Clock.now(), {})
				w.Clock.advance(1.1)
				w.h:require(S .. "CommunityService").step(w.Clock.now(), {})
				expect(attrs(w, slot)).toEqual({})
				w.F.set("RanchTiers", true)
				w.Ranch.step(w.Clock.now(), {})
				expect(attrs(w, slot).DecorGold).toBe(1 + 4 + 2 ^ 17)
				Bots.leave(p)
				w.h:settle(5)
				expect(attrs(w, slot)).toEqual({})
				clean(w)
			end
		)

		it("profil v1 : DecorGold et GoldPennants jamais posés, même interrupteurs ouverts", function()
			-- serveur de la v1.3 (préréglage « v13 », lot I D2 a)
			local w = boot(
				{ "UpgradesScreen", "Confetti", "Workshop", "RanchTiers" },
				nil,
				Flags.harness(Harness, "v13")
			)
			local p = Bots.join(1)
			local slot = w.Ranch.slotOf(p)
			expect(w.DS.get(p).version).toBe(1)
			w.h:settle(3)
			w.Ranch.refreshV2(p)
			local a = attrs(w, slot)
			expect({ a.DecorGold, a.GoldPennants }).toEqual({ nil, nil })
			expect(a.TapisTier ~= nil).toBe(true) -- paliers du lot A2 : inchangés
			clean(w)
		end)
	end)

	describe("RanchService_v2 › Aimant de l'Atelier", function()
		it(
			"Pot encaissé dans le rayon de l'Aimant [Workshop] (5 / 8 / 11 / 14 studs) ; coupé : 5 studs (v1.3)",
			function()
				local w = boot({ "UpgradesScreen", "Confetti", "Workshop" })
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local Balance = w.h:require(L .. "Config.Balance")
				local WL = w.h:require(L .. "Logic.WorldLayout")
				local calls = 0
				w.Ranch.setZoneHandler("pot", function()
					calls += 1
				end)
				local slot = w.Ranch.slotOf(p)
				local pot = WL.anchor(slot, "pot")
				local function standAt(dx)
					local actor = {
						player = p,
						slot = slot,
						pos = w.h.globals.Vector3.new(pot.X + dx, 3, pot.Z),
						canAct = true,
						riding = false,
						rootOffset = 0,
					}
					w.Ranch.step(w.Clock.now(), { [p] = actor })
					w.Ranch.flush()
				end
				local far = w.h.globals.Vector3.new(pot.X, 3, pot.Z + 40)
				local function leave()
					w.Ranch.step(w.Clock.now(), {
						[p] = {
							player = p,
							slot = slot,
							pos = far,
							canAct = true,
							riding = false,
							rootOffset = 0,
						},
					})
				end
				expect(Balance.PotV2.MagnetRadii).toEqual({ 5, 8, 11, 14 })
				-- Aimant 0 : 5 studs
				standAt(7)
				expect(calls).toBe(0)
				leave()
				standAt(4)
				expect(calls).toBe(1)
				leave()
				-- Aimant 2 : 11 studs
				data.atelier[3] = 2
				standAt(10)
				expect(calls).toBe(2)
				leave()
				standAt(12)
				expect(calls).toBe(2)
				leave()
				-- interrupteur coupé : rayon de la v1.3
				w.F.set("Workshop", false)
				standAt(10)
				expect(calls).toBe(2)
				clean(w)
			end
		)
	end)

	describe("RanchService_v2 › dalle du Tapis au-delà du Tapis 12 (N21)", function()
		it(
			"debout 0,6 s sur la dalle du Tapis 12 [StarMat], pièces d'abord insuffisantes : Tapis Étoilé acheté au premier tick où elles suffisent, une fois par entrée",
			function()
				local w = boot({ "UpgradesScreen", "StarMat" }, function(d)
					d.tiles.star = 0
					d.R = 10 -- 8 niveaux du Tapis Étoilé ouverts
				end)
				local p = Bots.join(1)
				local data = w.DS.get(p)
				local Pads = w.h:require(L .. "Config.Pads")
				local WL = w.h:require(L .. "Logic.WorldLayout")
				local UM = w.h:require(L .. "Logic.UpgradeMath")
				local slot = w.Ranch.slotOf(p)
				local c = WL.padSocket(slot, Pads.Defs.snack.socket)
				local function stand(pos)
					w.Ranch.step(w.Clock.now(), {
						[p] = {
							player = p,
							slot = slot,
							pos = pos,
							canAct = true,
							riding = false,
							rootOffset = 0,
						},
					})
					w.Ranch.flush()
				end
				local mat = w.h.globals.Vector3.new(c.X, 3, c.Z)
				local price = UM.price("star", 0, 10, 0, 12)
				data.coins = price - 1
				stand(mat)
				w.Clock.advance(0.7)
				stand(mat)
				expect(data.tiles.star).toBe(0)
				-- les pièces arrivent : achat au tick suivant, une seule fois
				data.coins = price * 100
				w.Clock.advance(0.1)
				stand(mat)
				expect(data.tiles.star).toBe(1)
				expect(data.coins).toBe(price * 100 - price)
				for _ = 1, 20 do
					w.Clock.advance(0.1)
					stand(mat)
				end
				expect({ data.tiles.snack, data.tiles.star }).toEqual({ 12, 1 })
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

	-- Lot I, étape 2 (plan I M6, M7, D15 ; journal I-16)
	describe("RanchService_v2 › intégration (lot I)", function()
		it(
			"KeptDecor [Workshop, profil v2] = décorations gardées au prochain Grand Splorch (Record R 8 et 14, + 3 par niveau, 12 au plus) ; suit l'achat ; coupé ou profil v1 : absent",
			function()
				local w = boot({ "UpgradesScreen", "Confetti", "Workshop" })
				local Upgrades = w.h:require(L .. "Config.Upgrades")
				local Prestige = w.h:require(L .. "Logic.Prestige")
				local row = Upgrades.WorkshopIndex.keptDecor
				local p = Bots.join(1)
				local slot = w.Ranch.slotOf(p)
				local data = w.DS.get(p)
				w.h:settle(2)
				local model = w.World.ranchModel(slot)
				-- Record R 12 : 3 (Record R 8)
				expect(model:GetAttribute("KeptDecor")).toBe(3)
				data.atelier[row] = 2
				data.bestR = 14
				w.Ranch.refreshV2(p)
				expect(model:GetAttribute("KeptDecor")).toBe(Prestige.keptDecor(14, data.atelier))
				expect(model:GetAttribute("KeptDecor")).toBe(12)
				-- Workshop coupé en direct : effacé au tick suivant ; rouvert : revient
				Bots.frames(5) -- ticks du serveur (empreinte des interrupteurs relevée)
				expect(w.F.set("Workshop", false)).toBe(true)
				Bots.frames(5)
				expect(model:GetAttribute("KeptDecor")).toBeNil()
				expect(w.F.set("Workshop", true)).toBe(true)
				Bots.frames(5)
				expect(model:GetAttribute("KeptDecor")).toBe(12)
				clean(w)
				-- profil v1 (serveur de la v1.3, Workshop ouvert dans le test) : jamais posé
				local w1 =
					boot({ "UpgradesScreen", "Confetti", "Workshop" }, nil, Flags.harness(Harness, "v13"))
				local p1 = Bots.join(1)
				w1.h:settle(2)
				w1.Ranch.refreshV2(p1)
				expect(w1.World.ranchModel(w1.Ranch.slotOf(p1)):GetAttribute("KeptDecor")).toBeNil()
				clean(w1)
			end
		)

		it(
			"StarMat changé en direct : refreshBuild une fois pour chaque ranch attribué (la dalle du Tapis suit aussitôt) ; sans changement : jamais",
			function()
				local w = boot({ "UpgradesScreen", "StarMat" })
				local p = Bots.join(1)
				local q = Bots.join(2)
				w.h:settle(2)
				Bots.frames(5)
				local builds = {}
				local original = w.Ranch.refreshBuild
				w.Ranch.refreshBuild = function(player)
					builds[player] = (builds[player] or 0) + 1
					return original(player)
				end
				Bots.frames(10)
				expect(next(builds)).toBeNil()
				expect(w.F.set("StarMat", false)).toBe(true)
				Bots.frames(3)
				expect({ builds[p], builds[q] }).toEqual({ 1, 1 })
				expect(w.F.set("StarMat", true)).toBe(true)
				Bots.frames(3)
				expect({ builds[p], builds[q] }).toEqual({ 2, 2 })
				clean(w)
			end
		)
	end)
end
