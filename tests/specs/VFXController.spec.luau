--!nocheck
-- VFXController (paquet client-world, docs/04 §13.3, §14.4, §18.2, GDD §9.4, §9.5) : clips (appareil
-- sans capture : aucune carte, attribut ClipsUnavailable, aucun avertissement, plus aucun essai ; carte
-- « clip » SEULEMENT après un StartVideoCaptureAsync réussi, arrêt à 8 s ; réglage, interrupteur et
-- PolicyService respectés), version courte du Grand Splorch (ni capsule ni vibration, message
-- celebrate.giftShort), vibrations (pressTick seulement sur un PERFECT du MEGA, 2 par seconde ; une
-- pression ordinaire ne vibre jamais ; échelles perfect et fusion), « +N » par UI/WorldText, budget
-- de particules, Mouvement réduit (aucun flash), effets d'événement coupés par interrupteur, zéro trace.

local ApiAudit = require("../harness/ApiAudit")
local MockInstance = require("../harness/MockInstance")
local TvAudit = require("../harness/TvAudit")

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function features(over)
		local f = {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
		for k, v in over or {} do
			f[k] = v
		end
		return f
	end

	local function eventState(over, feats)
		local p = {
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
			spectacle = { queue = {} },
			features = features(feats),
			offset = 0,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
	end

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		h.captureAvailable = opts.capture == true
		if opts.policyError then
			-- PolicyService qui lève (réseau) : réponse inconnue
			MockInstance.classMethods.PolicyService.GetPolicyInfoForPlayerAsync = function()
				error("HTTP 500 (simulé)")
			end
		end
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		local rm = opts.reducedMotion == true
		Prefs.reducedMotion = function()
			return rm
		end
		if opts.clipsSetting == false then
			local realGet = Prefs.get
			Prefs.get = function(key)
				if key == "clips" then
					return false
				end
				return realGet(key)
			end
		end
		local QC = h:require(base .. "Controllers.QualityController")
		if opts.reduced then
			QC.reduced = function()
				return true
			end
		end
		local Haptics = h:require(base .. "Util.Haptics")
		local haptics = {}
		Haptics.play = function(name, scale)
			table.insert(haptics, { name = name, scale = scale })
			return true
		end
		local Audio = h:require(base .. "Controllers.AudioController")
		local sounds = {}
		Audio.play = function(name)
			table.insert(sounds, name)
		end
		local Juice = h:require(base .. "UI.Juice")
		local flashes = 0
		Juice.flash = function()
			flashes += 1
		end
		local Cards = h:require(base .. "UI.Cards")
		local cards = {}
		Cards.push = function(card)
			table.insert(cards, card)
			return "c" .. #cards
		end
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		h:fireClient(
			"ReplicatedStorage.Remotes.RanchSnapshot",
			{ seq = 1, ranches = { ["3"] = ranch(3, 1), ["5"] = ranch(5, 2) }, squishies = {} }
		)
		h:fireClient("ReplicatedStorage.Remotes.EventState", eventState(nil, opts.features))
		h:settle(1)
		local VFX = h:require(base .. "Controllers.VFXController")
		VFX.Init()
		VFX.Start()
		h:settle(2)
		local c = {
			h = h,
			VFX = VFX,
			Clock = Clock,
			haptics = haptics,
			sounds = sounds,
			cards = cards,
			QC = QC,
			flashes = function()
				return flashes
			end,
		}
		function c.celebrate(kind, data)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = kind, data = data })
			h:settle(2)
		end
		function c.event(over, feats)
			h:fireClient("ReplicatedStorage.Remotes.EventState", eventState(over, feats))
			h:settle(1)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				VFX._step(dt)
			end
			h:settle(2)
		end
		function c.named(name)
			local n = 0
			for _, e in haptics do
				if e.name == name then
					n += 1
				end
			end
			return n
		end
		function c.captures(kind)
			local n = 0
			for _, e in h.log.captures do
				if e.kind == kind then
					n += 1
				end
			end
			return n
		end
		function c.floatTexts()
			local out = {}
			for _, d in h.workspace:GetDescendants() do
				if d.ClassName == "BillboardGui" and d.Name == "FloatText" and d.Enabled then
					for _, l in d:GetDescendants() do
						if l.ClassName == "TextLabel" and l.Text ~= "" then
							table.insert(out, l.Text)
						end
					end
				end
			end
			return out
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	local function legendHatch()
		return {
			uid = "z",
			species = 1,
			rarity = 5,
			mutation = 0,
			oneIn = 900,
			isNew = true,
			scripted = false,
			at = "pen",
		}
	end

	local function splorch(userId, short)
		return {
			userId = userId,
			level = 2,
			flyer = { s = 1, m = 0, st = 0, z = 10 },
			startedAt = T0,
			burstAt = T0 + 3.2,
			endsAt = T0 + 7.5,
			short = short,
		}
	end

	describe("VFXController", function()
		it(
			"appareil sans capture : aucune carte, ClipsUnavailable, aucun avertissement, plus aucun essai",
			function()
				local c = client()
				c.celebrate("hatch", legendHatch())
				c.run(0.2)
				expect(c.captures("start")).toBe(1)
				expect(#c.cards).toBe(0)
				expect(c.h.localPlayer:GetAttribute("ClipsUnavailable")).toBe(true)
				c.celebrate("hatch", legendHatch())
				c.celebrate("fusion", { uid = "z", step = 5, stars = 1, coins = 10 })
				c.run(0.2)
				expect(c.captures("start")).toBe(1)
				expect(#c.cards).toBe(0)
				c.clean()
			end
		)

		it(
			"capture réussie : arrêt au plus tard 8 s après, puis carte « clip » (save / share sous pcall)",
			function()
				local c = client({ capture = true })
				c.celebrate("fusion", { uid = "z", step = 5, stars = 1, coins = 10 })
				c.run(0.2)
				expect(c.captures("start")).toBe(1)
				expect(#c.cards).toBe(0) -- pas de carte avant la fin de la capture
				c.run(7)
				expect(c.captures("stop")).toBe(0)
				c.run(1.2)
				expect(c.captures("stop")).toBe(1)
				expect(#c.cards).toBe(1)
				expect(c.cards[1].kind).toBe("clip")
				expect(c.cards[1].blocking).toBe(false)
				c.cards[1].data.save()
				c.cards[1].data.share()
				c.h:settle(2)
				expect(c.captures("save")).toBe(1)
				expect(c.captures("share")).toBe(1)
				expect(c.h.localPlayer:GetAttribute("ClipsUnavailable")).toBe(nil)
				c.clean()
			end
		)

		it("réglage Clips coupé ou interrupteur du serveur coupé : aucun essai de capture", function()
			local c = client({ capture = true, clipsSetting = false })
			c.celebrate("hatch", legendHatch())
			c.run(0.2)
			expect(c.captures("start")).toBe(0)
			local c2 = client({ capture = true, features = { clips = false } })
			c2.celebrate("hatch", legendHatch())
			c2.run(0.2)
			expect(c2.captures("start")).toBe(0)
			expect(#c2.cards).toBe(0)
			c.clean()
			c2.clean()
		end)

		it(
			"Grand Splorch d'un autre en version courte : ni capsule ni vibration ; message giftShort",
			function()
				local c = client()
				c.celebrate("splorch", splorch(2, true))
				c.run(4)
				c.celebrate(
					"giftRain",
					{ heroId = 2, heroName = "Mira", coins = 100, uid = "q", species = 1, short = true }
				)
				c.run(0.1)
				expect(#c.haptics).toBe(0)
				local texts = c.floatTexts()
				local found = false
				for _, t in texts do
					if string.find(t, "Gift from Mira", 1, true) then
						found = true
					end
				end
				expect(found).toBe(true)
				for _, d in c.h.workspace:GetDescendants() do
					expect(d.Name == "Capsule").toBe(false)
				end
				-- version complète : capsule et vibration catch
				c.celebrate(
					"giftRain",
					{ heroId = 2, heroName = "Mira", coins = 100, uid = "q", species = 1, short = false }
				)
				expect(c.named("catch")).toBe(1)
				c.run(4)
				c.clean()
			end
		)

		it("mon Grand Splorch : vibration splorch à l'éclatement, une seule fois", function()
			local c = client()
			c.celebrate("splorch", splorch(1, false))
			c.run(3)
			expect(c.named("splorch")).toBe(0)
			c.run(0.5)
			expect(c.named("splorch")).toBe(1)
			c.run(5)
			expect(c.named("splorch")).toBe(1)
			c.clean()
		end)

		it(
			"vibrations : pression ordinaire jamais ; PERFECT à (0,3 + 0,03 × série) / 0,45 ; fusion (0,4 + 0,05 × (k − 1)) / 0,65",
			function()
				local c = client()
				c.celebrate("press", { uid = "a", coins = 12, perfect = false, streak = 0, petsit = false })
				expect(#c.haptics).toBe(0)
				c.celebrate("press", { uid = "a", coins = 12, perfect = true, streak = 3, petsit = false })
				expect(c.named("perfect")).toBe(1)
				expect(math.abs(c.haptics[1].scale - (0.3 + 0.03 * 3) / 0.45) < 1e-9).toBe(true)
				c.celebrate("fusion", { uid = "a", step = 2, stars = 1, coins = 0 })
				local last = c.haptics[#c.haptics]
				expect(last.name).toBe("fusion")
				expect(math.abs(last.scale - (0.4 + 0.05 * 1) / 0.65) < 1e-9).toBe(true)
				-- « +N » par UI/WorldText
				local plus = false
				for _, t in c.floatTexts() do
					if string.find(t, "+12", 1, true) then
						plus = true
					end
				end
				expect(plus).toBe(true)
				c.clean()
			end
		)

		it("pressTick : seulement une pression PERFECT du MEGA, 2 par seconde au plus", function()
			local c = client()
			local MegaRules = c.h:require("ReplicatedStorage.Shared.Logic.MegaRules")
			local landsAt = T0 - 2
			c.event({
				mega = {
					phase = "press",
					index = 1,
					landsAt = landsAt,
					endsAt = T0 + 20,
					target = 100,
					points = 0,
					species = 1,
					moon = false,
					result = "",
				},
			})
			local apex = MegaRules.nextApex(landsAt, T0)
			expect(MegaRules.isPerfect(landsAt, apex)).toBe(true)
			local bad = apex + 0.5
			if MegaRules.isPerfect(landsAt, bad) then
				bad = apex + 0.4
			end
			expect(c.VFX.megaPress(bad)).toBe(false)
			expect(c.named("pressTick")).toBe(0)
			for _ = 1, 5 do
				c.VFX.megaPress(apex)
			end
			expect(c.named("pressTick")).toBe(2)
			c.run(1.05)
			expect(c.VFX.megaPress(apex)).toBe(true)
			expect(c.named("pressTick")).toBe(3)
			-- MEGA coupé par l'interrupteur : jamais
			c.event({
				mega = {
					phase = "press",
					index = 1,
					landsAt = landsAt,
					endsAt = T0 + 20,
					target = 100,
					points = 0,
					species = 1,
					moon = false,
					result = "",
				},
			}, { megaSquish = false })
			c.run(1.05)
			expect(c.VFX.megaPress(apex)).toBe(false)
			c.clean()
		end)

		it("particules dans particleQuota.vfx (et × 0,3 en qualité réduite)", function()
			local c = client()
			local Vector3 = require("@lune/roblox").Vector3
			for _ = 1, 10 do
				c.VFX.burst(Vector3.new(0, 5, 0), require("@lune/roblox").Color3.new(1, 1, 1), 60)
			end
			expect(c.VFX.stats().particles <= c.QC.budgets().particleQuota.vfx).toBe(true)
			expect(c.VFX.stats().particles).toBe(120)
			c.run(1)
			expect(c.VFX.stats().particles).toBe(0)
			local c2 = client({ reduced = true })
			for _ = 1, 10 do
				c2.VFX.burst(Vector3.new(0, 5, 0), require("@lune/roblox").Color3.new(1, 1, 1), 60)
			end
			expect(c2.VFX.stats().particles <= 36).toBe(true)
			-- gouttes : réserve de 120 au plus
			for _ = 1, 5 do
				c2.VFX.blobs(Vector3.new(0, 5, 0), require("@lune/roblox").Color3.new(1, 0, 0), 60)
			end
			expect(c2.VFX.stats().blobs <= 120).toBe(true)
			c2.run(1)
			expect(c2.VFX.stats().blobs).toBe(0)
			c.clean()
			c2.clean()
		end)

		it(
			"Mouvement réduit : aucun flash ; naissance Légendaire sans flash mais avec vibration",
			function()
				local c = client({ reducedMotion = true })
				c.celebrate("hatch", legendHatch())
				expect(c.flashes()).toBe(0)
				expect(c.named("hatchLegend")).toBe(1)
				local c2 = client()
				c2.celebrate("hatch", legendHatch())
				expect(c2.flashes()).toBe(1)
				c.clean()
				c2.clean()
			end
		)

		it("effets d'événement seulement si l'interrupteur du serveur est vrai (MEGA, jauge)", function()
			local mega = {
				phase = "press",
				index = 2,
				landsAt = T0 + 0.1,
				endsAt = T0 + 20,
				target = 100,
				points = 0,
				species = 1,
				moon = false,
				result = "",
			}
			local c = client({ features = { megaSquish = false, gauge = false } })
			c.event({ mega = mega }, { megaSquish = false, gauge = false })
			c.event(
				{ gauge = { points = 0, target = 1000, partyUntil = T0 + 300, restUntil = 0 } },
				{ megaSquish = false, gauge = false }
			)
			c.run(0.5)
			expect(table.find(c.sounds, "MegaLand")).toBe(nil)
			expect(table.find(c.sounds, "GaugeFull")).toBe(nil)
			c.celebrate("megaResult", { success = true, points = 100, babies = 1, coins = 5 })
			expect(c.named("megaPop")).toBe(0)
			local c2 = client()
			c2.event({ mega = mega })
			c2.run(0.5)
			expect(table.find(c2.sounds, "MegaLand") ~= nil).toBe(true)
			c2.event({ gauge = { points = 0, target = 1000, partyUntil = T0 + 300, restUntil = 0 } })
			c2.run(0.1)
			expect(table.find(c2.sounds, "GaugeFull") ~= nil).toBe(true)
			c.clean()
			c2.clean()
		end)

		it("API Roblox valide (ApiAudit) : chaque effet, la capture et la carte", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local c = client({ capture = true })
				c.celebrate("press", { uid = "a", coins = 1200, perfect = true, streak = 5, petsit = false })
				c.celebrate("hatch", {
					uid = "z",
					species = 1,
					rarity = 7,
					mutation = 0,
					oneIn = 2500,
					isNew = true,
					scripted = false,
					at = "pen",
				})
				c.celebrate("fusion", { uid = "a", step = 5, stars = 2, coins = 10 })
				c.celebrate("catch", {
					kind = "golden",
					species = 1,
					mutation = 0,
					uid = "",
					coins = 5,
					hero = true,
					byLeap = false,
				})
				c.celebrate("tile", { tile = "snack", level = 2 })
				c.celebrate("pot", { coins = 4500, auto = false })
				c.celebrate("splorch", splorch(1, false))
				c.celebrate(
					"giftRain",
					{ heroId = 2, heroName = "Mira", coins = 100, uid = "q", species = 1, short = false }
				)
				c.celebrate("megaResult", { success = true, points = 100, babies = 2, coins = 5 })
				c.celebrate("purchase", { key = "x" })
				c.celebrate("fanfare", { threshold = 1e6 })
				c.run(9)
				c.clean()
			end)
			local issues = ApiAudit.stop()
			expect(ok and true or err).toBe(true)
			expect(table.concat(issues, "\n")).toBe("")
		end)

		it("charges hostiles : aucune erreur", function()
			local c = client()
			local nan = 0 / 0
			for _, kind in
				{
					"press",
					"tile",
					"pot",
					"hatch",
					"fusion",
					"catch",
					"boopDone",
					"splorch",
					"giftRain",
					"megaResult",
					"lunarDrop",
					"plopDay",
					"purchase",
					"fanfare",
					"unknown",
				}
			do
				c.celebrate(kind, {
					uid = nan,
					coins = nan,
					streak = math.huge,
					rarity = "x",
					step = nan,
					startedAt = nan,
					species = {},
					tile = 5,
				})
				c.celebrate(kind, {})
			end
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", nil)
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "press" })
			c.h:settle(2)
			c.VFX.floatText(nil, "x")
			c.VFX.ring(nil, nil, nan, nan)
			c.VFX.megaPress(nan)
			c.run(2)
			c.clean()
		end)
		-- Revue client-world (GDD §9.5) : sans réponse POSITIVE de PolicyService (appel qui lève),
		-- aucune capture n'est lancée ; jamais d'avertissement
		it("PolicyService sans réponse : aucune capture lancée, aucun avertissement", function()
			local c = client({ capture = true, policyError = true })
			c.celebrate("hatch", legendHatch())
			c.run(0.2)
			expect(c.captures("start")).toBe(0)
			expect(#c.cards).toBe(0)
			c.clean()
		end)

		-- Revue client-world (contrat v1.2, variante ClientReplay) : le héros part pendant son spectacle
		-- → le spectacle s'arrête chez les spectateurs (plus d'éclatement, de titre ni de cadeaux)
		it("le héros part pendant son Grand Splorch : spectacle arrêté chez les autres", function()
			local c = client()
			c.celebrate("splorch", splorch(2, false))
			c.run(1)
			c.h:fireClient("ReplicatedStorage.Remotes.RanchPatch", {
				seq = 2,
				ranches = { ["5"] = { userId = 0, name = "" } },
				ops = {},
			})
			c.h:settle(1)
			c.run(6)
			for _, name in c.sounds do
				expect(name == "SplorchPop" or name == "GiftRain").toBe(false)
			end
			for _, d in c.h.localPlayer.PlayerGui:GetDescendants() do
				if d.ClassName == "TextLabel" and d.Visible then
					expect(string.find(d.Text, "GRAND SPLORCH", 1, true) == nil).toBe(true)
				end
			end
			expect(c.VFX.stats().effects).toBe(0)
			c.clean()
		end)

		-- Revue client-world (télé, 10 pieds) : le grand tampon tient dans la zone sûre, à 28 px TV au
		-- moins, même avec un long nom et une longue cote
		it("tampon : texte long tenu dans la zone sûre (TextScaled, 28 px TV au moins)", function()
			local c = client()
			c.VFX.stamp("celebrate.secretTag", { species = "Mochi Mew Royal", odds = "1 000 000 000" })
			c.run(0.1)
			local screen = c.h.localPlayer.PlayerGui:FindFirstChild("VFXStamp")
			expect(screen ~= nil).toBe(true)
			local label = screen:FindFirstChild("Stamp", true)
			expect(label.TextScaled).toBe(true)
			expect(#TvAudit.clipped(c.h, screen)).toBe(0)
			expect(#TvAudit.outsideSafe(c.h, screen)).toBe(0)
			c.clean()
		end)
		-- Revue client-world : un effet qui lève rend sa réserve et libère son spectacle (sinon un seul
		-- incident empêchait tout Grand Splorch de ce héros pour la session)
		it(
			"un effet qui lève libère son spectacle : le Grand Splorch suivant du même héros se joue",
			function()
				local c = client()
				local SplorchPath = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.SplorchPath")
				local real = SplorchPath.sample
				SplorchPath.sample = function()
					error("panne simulée")
				end
				c.celebrate("splorch", splorch(2, false))
				c.run(0.1)
				SplorchPath.sample = real
				expect(#c.h.errors).toBe(1) -- l'erreur est signalée (une fois), puis effacée par le test
				table.clear(c.h.errors)
				local again = splorch(2, false)
				again.startedAt, again.burstAt, again.endsAt = T0 + 1, T0 + 4.2, T0 + 8.5
				c.celebrate("splorch", again)
				c.run(4.5)
				local popped = false
				for _, name in c.sounds do
					if name == "SplorchPop" then
						popped = true
					end
				end
				expect(popped).toBe(true)
				c.run(5)
				expect(c.VFX.stats().effects).toBe(0)
				c.clean()
			end
		)
	end)
end
