--!nocheck
-- HUD (paquet client-hud ; docs/04 §13.5, §14 ; GDD §10.2, v1.3) : éléments aux rectangles de
-- Config/Layout.Hud ; pastille d'événement et barre du MEGA selon l'interrupteur du serveur (aucune
-- pastille MEGA si megaSquish est faux) ; jauge grise « Big Plop se repose mm:ss » pendant la sieste ;
-- place et attente dans la file du Grand Splorch ; vibration squishyBack au retour (aucune quand il
-- s'enfuit) ; APPLAUDIR (clapHero) caché en poursuite, en maintien ou derrière une fenêtre ; pastilles
-- de la puce Menu ; messages (Feedback) ; carte de la cible ; indicateur Bondir ; mode photo ;
-- affichage progressif ; charges hostiles sans erreur. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local ApiAudit = require("../harness/ApiAudit")
local FontCmap = require("../harness/FontCmap")

local Vector3 = roblox.Vector3
local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000
	local MEGA_LAND = 1800001200
	local CMAPS = FontCmap.load()

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

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

	local function eventState(over)
		local ev = {
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
			gauge = { points = 300, target = 1200, partyUntil = 0, restUntil = 0 },
			boost = { kind = "", untilT = 0, byName = "" },
			spectacle = { queue = {} },
			features = features(),
			offset = 0,
		}
		for k, v in over or {} do
			ev[k] = v
		end
		return ev
	end

	local function setup(opts)
		opts = opts or {}
		local profile = opts.profile or {}
		if profile.onboarding == nil then
			profile.onboarding = { step = 11, done = true, demoDone = true }
		end
		local h = TvAudit.client({ profile = profile, now = opts.now, console = opts.console })
		h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
		local HUD = TvAudit.mod(h, "UI.HUD")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		local state = { ev = opts.ev or eventState(), creatures = {}, ranch = opts.ranch }
		WSC.event = function()
			return state.ev
		end
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return if slot == 1 then state.ranch else nil
		end
		WSC.creatures = function()
			return state.creatures
		end
		WSC.creaturePos = function(id)
			for _, c in state.creatures do
				if c.id == id then
					return c.pos
				end
			end
			return nil
		end
		HUD._refresh()
		return h, HUD, Clock, state
	end

	local function text(h, HUD, element, child)
		return HUD.element(element):FindFirstChild(child, true).Text
	end

	describe("HUD › éléments", function()
		it("chaque élément au rectangle de Config/Layout.Hud ; ClientReady posé", function()
			local h, HUD = setup()
			local L = h:require("ReplicatedStorage.Shared.Config.Layout")
			for name, slot in L.Hud do
				if name ~= "menuRail" then
					local e = HUD.element(name)
					expect({ name = name, ok = e ~= nil }).toEqual({ name = name, ok = true })
					expect({ name = name, size = e.Size }).toEqual({
						name = name,
						size = roblox.UDim2.fromOffset(slot.rect.w, slot.rect.h),
					})
				end
			end
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
			clean(h)
		end)

		it("pièces : montant abrégé (BigNumber), revenu « +N/s », mise à jour du profil", function()
			local h, HUD = setup({ profile = { coins = 1234 } })
			expect(text(h, HUD, "coins", "Amount")).toBe("1,234")
			h:fireClient("ReplicatedStorage.Remotes.DataPatch", { coins = 2500000 }, {})
			h:settle(2)
			HUD._refresh()
			-- défilement 0,5 s calé sur Clock (Quint Out) : la valeur finale à la fin
			expect(text(h, HUD, "coins", "Amount")).toBe("1,234")
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.advance(0.25)
			HUD._refresh()
			local mid = text(h, HUD, "coins", "Amount")
			expect(mid ~= "1,234" and mid ~= "2.50M").toBe(true)
			Clock.advance(0.3)
			HUD._refresh()
			expect(text(h, HUD, "coins", "Amount")).toBe("2.50M")
			expect(string.sub(text(h, HUD, "coins", "Rate"), 1, 1)).toBe("+")
			clean(h)
		end)

		-- relecture des références de l'étape 5 du lot B2 (Upgrades_Reference, rail après « Prêt ! ») : une
		-- baisse de 1e30 à 4,25B finissait sur « 0 » (from + (to − from) × 1 perd `to` quand from ≫ to,
		-- double à 53 bits) ; règle 4 du GDD §10.8 : la valeur finale est toujours posée, exactement
		it(
			"défilement des pièces : la valeur finale est exacte, même après une très grande baisse",
			function()
				local h, HUD = setup({ profile = { coins = 1e30 } })
				local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
				expect(text(h, HUD, "coins", "Amount")).toBe("1.00No")
				for _, case in { { 4.25e9, "4.25B" }, { 25, "25" }, { 1e30, "1.00No" }, { 7, "7" } } do
					h:fireClient("ReplicatedStorage.Remotes.DataPatch", { coins = case[1] }, {})
					h:settle(2)
					Clock.advance(0.6)
					HUD._refresh()
					expect(text(h, HUD, "coins", "Amount")).toBe(case[2])
				end
				clean(h)
			end
		)
	end)

	describe("HUD › événements", function()
		it("pastille : prochain événement selon les interrupteurs du serveur", function()
			local h, HUD, _, state = setup()
			expect(text(h, HUD, "eventPill", "Text")).toBe("Golden Wobbler 0:30")
			state.ev = eventState({ features = features({ golden = false }) })
			HUD._refresh()
			expect(text(h, HUD, "eventPill", "Text")).toBe("BOOP RUSH 5:00")
			clean(h)
		end)

		-- INT-B5-HUD (lot B5, étape 5 ; plan B5 D22) : nom de la météo 10 s, puis le compte à rebours
		it(
			"météo (lot B5) : le nom de chaque sorte 10 s (aussi pour qui arrive pendant), puis le prochain événement ; un événement « en cours » passe avant ; clé absente ou finie : rien ne change",
			function()
				local h, HUD, Clock, state = setup()
				local before = text(h, HUD, "eventPill", "Text")
				expect(before).toBe("Golden Wobbler 0:30")
				local names = { "Sunny", "Sprinkle Shower", "Bubble Breeze", "Rainbow" }
				for kind = 1, 4 do
					local endsAt = Clock.unix() + 240 + kind
					state.ev = eventState({ weather = { kind = kind, endsAt = endsAt } })
					HUD._refresh()
					expect(text(h, HUD, "eventPill", "Text")).toBe(names[kind])
					expect(HUD.visible("eventPill")).toBe(true)
					Clock.advance(9.5)
					HUD._refresh()
					expect(text(h, HUD, "eventPill", "Text")).toBe(names[kind])
					Clock.advance(0.6)
					HUD._refresh()
					expect(string.find(text(h, HUD, "eventPill", "Text"), "Golden Wobbler", 1, true)).toBeTruthy()
					-- la même fenêtre ne revient jamais
					Clock.advance(30)
					HUD._refresh()
					expect(string.find(text(h, HUD, "eventPill", "Text"), names[kind], 1, true)).toBeNil()
					Clock.advance(-40.1)
				end
				-- fenêtre finie (endsAt passé) ou abîmée : rien ne change
				for _, w in
					{ { kind = 2, endsAt = Clock.unix() - 1 }, { kind = 9, endsAt = Clock.unix() + 60 }, "x" }
				do
					state.ev = eventState({ weather = w })
					HUD._refresh()
					expect(text(h, HUD, "eventPill", "Text")).toBe(before)
				end
				-- un événement en cours (Wobble Party) passe avant la météo
				state.ev = eventState({
					weather = { kind = 4, endsAt = Clock.unix() + 300 },
					boost = { kind = "wobble", untilT = Clock.now() + 300, byName = "" },
				})
				HUD._refresh()
				expect(text(h, HUD, "eventPill", "Text")).toBe("WOBBLE PARTY ×2 5:00")
				clean(h)
			end
		)

		it("MEGA : pastille et barre seulement si megaSquish est vrai", function()
			local h, HUD, Clock, state = setup({ now = MEGA_LAND + 10 })
			state.ev = eventState({
				mega = {
					phase = "press",
					index = 1,
					landsAt = MEGA_LAND,
					endsAt = MEGA_LAND + 60,
					target = 400,
					points = 120,
					species = 1,
					moon = false,
					result = "",
				},
			})
			HUD._refresh()
			expect(text(h, HUD, "eventPill", "Text")).toBe("MEGA SQUISH! 0:50")
			expect(HUD.visible("megaBar")).toBe(true)
			expect(HUD.visible("gauge")).toBe(false) -- même place que la jauge
			expect(text(h, HUD, "megaBar", "Text")).toBe("120 / 400 · 0:50")
			state.ev = eventState({ features = features({ megaSquish = false }) })
			HUD._refresh()
			expect(string.find(text(h, HUD, "eventPill", "Text"), "MEGA", 1, true)).toBeNil()
			expect(HUD.visible("megaBar")).toBe(false)
			Clock.advance(0)
			clean(h)
		end)

		it("jauge grise « Big Plop se repose mm:ss » pendant la sieste, puis normale", function()
			local h, HUD, Clock, state = setup()
			state.ev =
				eventState({ gauge = { points = 50, target = 1200, partyUntil = 0, restUntil = NOW + 754 } })
			HUD._refresh()
			local gauge = HUD.element("gauge")
			expect(HUD.visible("gauge")).toBe(true)
			expect(gauge:GetAttribute("Resting")).toBe(true)
			expect(gauge.Rest.Visible).toBe(true)
			expect(gauge.Rest.Text).toBe("Big Plop is napping 12:34")
			Clock.advance(754)
			HUD._refresh()
			expect(gauge:GetAttribute("Resting")).toBe(false)
			expect(gauge.Rest.Visible).toBe(false)
			-- interrupteur coupé : pas de jauge
			state.ev = eventState({ features = features({ gauge = false }) })
			HUD._refresh()
			expect(HUD.visible("gauge")).toBe(false)
			clean(h)
		end)

		it("suivi d'objectif : place et attente dans la file du Grand Splorch, qui décompte", function()
			local h, HUD, Clock, state = setup()
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			state.ev = eventState({
				spectacle = {
					queue = {
						{
							kind = "splorch",
							userId = 9,
							startAt = NOW + 20,
							slot = 3,
							position = 1,
							eta = 20,
						},
						{
							kind = "splorch",
							userId = 1,
							startAt = NOW + 40,
							slot = 1,
							position = 2,
							eta = 40,
						},
					},
				},
			})
			WSC.EventChanged:Fire(state.ev)
			HUD._refresh()
			-- « ≈ » (hors police, règle 18) devenu le mot « about » / « environ » (lot B2, D19, journal B2-44)
			expect(text(h, HUD, "goalTracker", "Value")).toBe("#2 in line · about 0:40")
			expect(FontCmap.missing(CMAPS, text(h, HUD, "goalTracker", "Value"))).toEqual({})
			expect(HUD.element("goalTracker"):GetAttribute("Queued")).toBe(true)
			Clock.advance(10)
			HUD._refresh()
			expect(text(h, HUD, "goalTracker", "Value")).toBe("#2 in line · about 0:30")
			state.ev.spectacle.queue = {
				{ kind = "splorch", userId = 1, startAt = NOW + 30, slot = 1, position = 1, eta = 12 },
			}
			WSC.EventChanged:Fire(state.ev)
			HUD._refresh()
			expect(text(h, HUD, "goalTracker", "Value")).toBe("Next in line · about 0:12")
			expect(FontCmap.missing(CMAPS, text(h, HUD, "goalTracker", "Value"))).toEqual({})
			clean(h)
		end)

		it("suivi d'objectif : « 12K / 15K », puis « Ready! » et la puce GRAND SPLORCH !", function()
			local h, HUD = setup({
				profile = {
					squishies = { a = TvAudit.squishy(1, { z = 12000 }) },
					growth = { G = 0, g = 0, t = NOW },
				},
			})
			expect(text(h, HUD, "goalTracker", "Value")).toBe("12.0K / 15.0K")
			h:fireClient(
				"ReplicatedStorage.Remotes.DataPatch",
				{ squishies = { a = TvAudit.squishy(1, { z = 16000 }) } },
				{}
			)
			h:settle(2)
			HUD._refresh()
			expect(text(h, HUD, "goalTracker", "Value")).toBe("Ready!")
			expect(HUD.element("specialChip"):GetAttribute("Mode")).toBe("splorch")
			expect(HUD.visible("specialChip")).toBe(true)
			clean(h)
		end)
	end)

	describe("HUD › retours", function()
		-- lot B3, étape 6 (journal B3-72) : rentré tout seul (ChaseService.escapeReturned : ownerReturn
		-- sans attrapeur, 0 pièce, aucune Fame) : le message disait « +1 Fame +0 coins · left a baby for »
		it("ownerReturn sans attrapeur (rentré tout seul) : aucun message « left a baby for »", function()
			local h = setup()
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "ownerReturn",
				data = {
					uid = "u1",
					species = 2,
					coins = 0,
					catcherId = 0,
					catcherName = "",
					firstBoop = true,
				},
			})
			h:settle(1)
			local last = M.last()
			expect(string.find(if last then last.text else "", "baby", 1, true)).toBeNil()
			-- avec un attrapeur : le message de la v1.3, inchangé
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "ownerReturn",
				data = {
					uid = "u1",
					species = 2,
					coins = 50,
					catcherId = 7,
					catcherName = "Noah",
					firstBoop = false,
				},
			})
			h:settle(1)
			expect(M.last().text).toBe("Wibble came back! +1 Fame +50 coins · left a baby for Noah")
			clean(h)
		end)

		it("vibration squishyBack au retour de mon squishy boopé ; aucune quand il s'enfuit", function()
			local h, HUD = setup()
			local Haptics = TvAudit.mod(h, "Util.Haptics")
			local played = {}
			Haptics.Played:Connect(function(name)
				table.insert(played, name)
			end)
			h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "booped", data = { uid = "u1", species = 2, booperId = 7 } }
			)
			h:settle(1)
			expect(played).toEqual({})
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "ownerReturn",
				data = {
					uid = "u1",
					species = 2,
					coins = 50,
					catcherId = 7,
					catcherName = "Noah",
					firstBoop = false,
				},
			})
			h:settle(1)
			expect(played).toEqual({ "squishyBack" })
			Haptics._reset()
			h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "returnedBigger", data = { uid = "u1", species = 2 } }
			)
			h:settle(1)
			expect(played).toEqual({ "squishyBack", "squishyBack" })
			-- le retour d'abord, dans la file des messages
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			expect(string.find(M.last().text, "Wibble came back!", 1, true) ~= nil).toBe(true)
			expect(HUD.element("coins") ~= nil).toBe(true)
			clean(h)
		end)

		it(
			"Feedback : texte traduit avec nombres abrégés ; clé inconnue ignorée sans avertissement",
			function()
				local h = setup()
				local M = TvAudit.mod(h, "UI.Hud.Messages")
				h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "feedback.sellDone", vars = { coins = 25000 }, tone = "reward" }
				)
				h:settle(1)
				expect(M.last().text).toBe("+25.0K coins")
				h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "feedback.inexistant", vars = {}, tone = "info" }
				)
				h:fireClient("ReplicatedStorage.Remotes.Feedback", { key = 42 })
				h:fireClient("ReplicatedStorage.Remotes.Feedback", "x")
				h:settle(1)
				expect(M.pending()).toBe(0)
				-- messages identiques fusionnés (« ×3 »)
				for _ = 1, 3 do
					h:fireClient(
						"ReplicatedStorage.Remotes.Feedback",
						{ key = "feedback.tooFar", vars = {}, tone = "info" }
					)
				end
				h:settle(1)
				expect(M.pending()).toBe(1)
				clean(h)
			end
		)

		it(
			"pastilles de la puce Menu : « ♥ N » (paires de jumeaux) et « ! » (objectif à réclamer)",
			function()
				local h, HUD = setup({
					profile = {
						squishies = { a = TvAudit.squishy(1), b = TvAudit.squishy(1), c = TvAudit.squishy(2) },
						objectives = {
							day = 0,
							list = { { id = 1, p = 30, done = true, claimed = false } },
							rerolls = 0,
							allClaimed = false,
						},
					},
				})
				local chip = HUD.element("menuChip")
				expect(chip:GetAttribute("Twins")).toBe(1)
				expect(chip.Twins.Visible).toBe(true)
				-- « ♥ » (hors police) devenu un cœur DESSINÉ devant le nombre (lot B2, D18, journal B2-45)
				expect(chip.Twins.Text.Text).toBe("1")
				expect(chip.Twins.Heart:GetAttribute("Icon")).toBe("heart")
				expect(chip.Twins.Heart.Visible).toBe(true)
				expect(chip:GetAttribute("Bang")).toBe(true)
				clean(h)
			end
		)

		it("puce Menu (et Fame) cachée tant que le rail du menu est ouvert", function()
			local h, HUD = setup()
			expect(HUD.visible("menuChip")).toBe(true)
			TvAudit.mod(h, "UI.PanelController").toggleMenu()
			HUD._refresh()
			expect(HUD.visible("menuChip")).toBe(false)
			expect(HUD.visible("fame")).toBe(false)
			TvAudit.tick(h, 0.5)
			TvAudit.mod(h, "UI.PanelController").closeAll()
			HUD._refresh()
			expect(HUD.visible("menuChip")).toBe(true)
			clean(h)
		end)
	end)

	describe("HUD › APPLAUDIR", function()
		local function clap(h, heroId, endsAt)
			h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = heroId, endsAt = endsAt })
			h:settle(1)
		end

		it("clapHero pendant la fenêtre de 8 s ; puce APPLAUDIR avec son anneau ; un seul Clap", function()
			local h, HUD, Clock = setup()
			clap(h, 5, NOW + 8)
			HUD._refresh()
			expect(HUD.clapHero()).toBe(5)
			local chip = HUD.element("specialChip")
			expect(chip:GetAttribute("Mode")).toBe("clap")
			expect(chip.ClapRing.Visible).toBe(true)
			expect(HUD._clap()).toBe(true)
			expect(TvAudit.sent(h, "Clap")[1][1]).toBe(5)
			expect(HUD.clapHero()).toBeNil() -- une fois par fenêtre
			clap(h, 6, NOW + 8)
			Clock.advance(8)
			expect(HUD.clapHero()).toBeNil() -- fenêtre finie
			clean(h)
		end)

		it(
			"cachée en poursuite (créature attrapable ≤ 30 studs), en maintien, derrière une fenêtre",
			function()
				local h, HUD, Clock, state = setup()
				clap(h, 5, NOW + 8)
				expect(HUD.clapHero()).toBe(5)
				-- poursuite : Wild Wobbler à 10 studs
				state.creatures =
					{ { id = 3, kind = "wild", t0 = NOW - 1, duration = 25, pos = Vector3.new(10, 3, 0) } }
				expect(HUD.clapHero()).toBeNil()
				HUD._refresh()
				expect(HUD.element("specialChip"):GetAttribute("Mode")).toBe("")
				-- à 60 studs : plus une poursuite
				state.creatures[1].pos = Vector3.new(60, 3, 0)
				expect(HUD.clapHero()).toBe(5)
				-- maintien (bol)
				h:fireClient(
					"ReplicatedStorage.Remotes.HoldState",
					{ kind = "feed", endsAt = NOW + 2, active = true, tile = "" }
				)
				h:settle(1)
				expect(HUD.clapHero()).toBeNil()
				h:fireClient(
					"ReplicatedStorage.Remotes.HoldState",
					{ kind = "feed", endsAt = NOW + 2, active = false, tile = "" }
				)
				h:settle(1)
				expect(HUD.clapHero()).toBe(5)
				-- fenêtre ouverte (menu)
				TvAudit.mod(h, "UI.PanelController").toggleMenu()
				expect(HUD.clapHero()).toBeNil()
				Clock.advance(0)
				clean(h)
			end
		)

		it(
			"charges hostiles : héros invalide, soi-même, fin passée ou très lointaine (bornée à 8 s)",
			function()
				local h, HUD, Clock = setup()
				clap(h, 0 / 0, NOW + 8)
				clap(h, 1, NOW + 8) -- moi-même (joueur local)
				clap(h, 5, NOW - 1)
				expect(HUD.clapHero()).toBeNil()
				clap(h, 5, NOW + 1e9)
				expect(HUD.clapHero()).toBe(5)
				Clock.advance(8.01)
				expect(HUD.clapHero()).toBeNil()
				h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", "x")
				h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = "5", endsAt = {} })
				h:settle(1)
				clean(h)
			end
		)
	end)

	describe("HUD › cible, Bondir, photo, accueil", function()
		it("carte de la cible : squishy visé (nom, taille) ; rien sans cible", function()
			local h, HUD = setup()
			expect(HUD.visible("targetCard")).toBe(false)
			local PC = TvAudit.mod(h, "Controllers.PromptController")
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			PC.current = function()
				return {
					kind = "squishy",
					slot = 1,
					uid = "u7",
					primary = "press",
					secondary = "pickup",
					ready = true,
					position = Vector3.new(0, 2, -6),
				}
			end
			WSC.squishies = function()
				return {
					u7 = { s = 2, m = 4, st = 2, z = 1500, zg = 0, at = "pen", bf = 0, o = "", ready = 0 },
				}
			end
			HUD._refresh()
			expect(HUD.visible("targetCard")).toBe(true)
			expect(text(h, HUD, "targetCard", "Name")).toBe("Wibble")
			local details = text(h, HUD, "targetCard", "Details")
			expect(string.find(details, "Size", 1, true) ~= nil).toBe(true)
			-- lot B1 (règle 18, INT-V2-GLYPHS a) : « ★ » est hors des polices ; « 2 » puis l'étoile DESSINÉE
			-- (UI/Text.STAR → UI/Glyph.star), des espaces ordinaires à sa place dans le texte
			expect(string.find(details, "★", 1, true)).toBeNil()
			expect(string.find(details, "2 ", 1, true) ~= nil).toBe(true)
			local detailsLabel = HUD.element("targetCard"):FindFirstChild("Details", true)
			local Text = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.Text")
			expect(#Text.icons(detailsLabel)).toBe(1)
			clean(h)
		end)

		it(
			"indicateur Bondir : visible pendant la recharge seulement (hors leçon et événement)",
			function()
				local h, HUD = setup()
				expect(HUD.visible("leap")).toBe(false)
				local CC = TvAudit.mod(h, "Controllers.ChaseController")
				CC.cooldownLeft = function()
					return 2
				end
				HUD._refresh()
				expect(HUD.visible("leap")).toBe(true)
				CC.cooldownLeft = function()
					return 0
				end
				HUD._refresh()
				expect(HUD.visible("leap")).toBe(false)
				clean(h)
			end
		)

		it("indicateurs d'état : bouclier, ×2 et mode (Rush / Cozy)", function()
			local h, HUD, _, state = setup({
				ranch = {
					slot = 1,
					userId = 1,
					mode = "rush",
					shield = true,
					carry = "",
					ride = "",
					saddle = 0,
				},
			})
			state.ev = eventState({ boost = { kind = "wobble", untilT = NOW + 300, byName = "" } })
			HUD._refresh()
			local status = HUD.element("status")
			expect(status.shield.Visible).toBe(true)
			expect(status.boost.Visible).toBe(true)
			-- « ′ » (hors police) devenu une marque DESSINÉE après le nombre (lot B2, D20, journal B2-46)
			expect(status.boost.Minutes.Text).toBe("5")
			expect(status.boost.Prime:GetAttribute("Icon")).toBe("prime")
			expect(status.boost.Prime.Visible).toBe(true)
			expect(status.shield.Minutes.Text ~= "").toBe(true)
			expect(status.shield.Prime.Visible).toBe(true)
			expect(status:GetAttribute("Mode")).toBe("rush")
			expect(text(h, HUD, "eventPill", "Text")).toBe("WOBBLE PARTY ×2 5:00")
			clean(h)
		end)

		it("mode photo : le HUD se cache (administrateurs, vignettes)", function()
			local h = setup()
			local gui = h.localPlayer.PlayerGui.HUD
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "photo", data = { on = true } })
			h:settle(1)
			expect(gui.Enabled).toBe(false)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "photo", data = { on = false } })
			h:settle(1)
			expect(gui.Enabled).toBe(true)
			clean(h)
		end)

		it("nouveau : seul le compteur de pièces au début ; reveal / setHint", function()
			local h, HUD = setup({ profile = { onboarding = { step = 0, done = false, demoDone = false } } })
			TvAudit.mod(h, "Controllers.OnboardingController")._tick()
			HUD._refresh()
			expect(HUD.visible("coins")).toBe(true)
			for _, name in { "fame", "menuChip", "eventPill", "gauge", "goalTracker", "status" } do
				expect({ name = name, visible = HUD.visible(name) }).toEqual({ name = name, visible = false })
			end
			HUD.setHint("action", "prompt.press")
			HUD._refresh()
			expect(HUD.element("specialChip"):GetAttribute("Mode")).toBe("hint")
			expect(text(h, HUD, "specialChip", "Text")).toBe("Press")
			HUD.setHint(nil, nil)
			HUD.setHint("action", "clé.inexistante")
			HUD._refresh()
			expect(HUD.element("specialChip"):GetAttribute("Mode")).toBe("")
			HUD.reveal("all", true)
			HUD._refresh()
			expect(HUD.visible("fame")).toBe(true)
			HUD.reveal(42, true)
			HUD.reveal("inconnu", true)
			clean(h)
		end)
	end)

	describe("HUD › robustesse", function()
		it("EventState abîmé, célébrations hostiles, stubs du contrat : aucune erreur", function()
			local h, HUD, _, state = setup()
			state.ev = {
				gauge = "x",
				spectacle = {
					queue = { 1, "a", { userId = 1, kind = "splorch", position = 0 / 0, eta = math.huge } },
				},
				features = { gauge = true, megaSquish = "oui" },
				boost = 5,
			}
			HUD._refresh()
			state.ev = nil
			HUD._refresh()
			for _, p in
				{
					{ kind = "ownerReturn", data = { species = "x", coins = 0 / 0, catcherId = -5 } },
					{ kind = "unlock", data = { kind = "title", id = string.rep("x", 900) } },
					{ kind = "clapCount", data = { n = math.huge } },
					{ kind = "photo", data = "on" },
					{ kind = "press", data = {} },
					{ kind = {}, data = {} },
				}
			do
				h:fireClient("ReplicatedStorage.Remotes.Celebrate", p)
				h:settle(1)
			end
			h:fireClient(
				"ReplicatedStorage.Remotes.HoldState",
				{ kind = "tile", endsAt = 0 / 0, active = true, tile = 5 }
			)
			h:settle(1)
			HUD._refresh()
			HUD.setMenuBadges(nil, 0 / 0)
			expect(HUD.element("inconnu")).toBeNil()
			clean(h)
		end)

		it("API Roblox : chaque classe et propriété écrite existe (ApiAudit)", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, HUD, _, state = setup({ now = MEGA_LAND + 5 })
				state.ev = eventState({
					gauge = { points = 1, target = 2, partyUntil = 0, restUntil = MEGA_LAND + 60 },
				})
				h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = 5, endsAt = MEGA_LAND + 13 })
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { coins = 99999 }, {})
				h:settle(2)
				HUD.setHint("target", "prompt.choose")
				HUD._refresh()
				h:step(1 / 60, 10)
				clean(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and "" or tostring(err)).toBe("")
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
	-- =========================================================================================
	-- v2.0 (lot B2, étape 4 ; N9, N18, docs/04 §27.14) : HUD v2.0 quand l'instantané du serveur est
	-- là (interrupteur UpgradesScreen, D1) ; fabriqué dans le test (UpgradeScreen, profil témoin v2)
	-- =========================================================================================
	describe("HUD › v2.0 (lot B2)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local DONE = { step = 11, done = true, demoDone = true }

		-- profil témoin en remontée : A = 1, boucle r, Record R 15
		local function regain(r)
			return function(p)
				p.ascend = 1
				p.R = r
				p.bestR = 15
			end
		end

		local function v2setup(opts)
			opts = opts or {}
			local profile = opts.profile or {}
			profile.onboarding = profile.onboarding or DONE
			-- croissance figée : la taille des squishies ne bouge pas pendant le test
			profile.growth = profile.growth or { G = 0, g = 0, t = NOW }
			local c = S.client({ snap = opts.snap, profile = profile, ranch = opts.ranch, lang = opts.lang })
			local h = c.h
			h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
			local HUD = TvAudit.mod(h, "UI.HUD")
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			local state = { ev = opts.ev or eventState(), ranch = opts.ranchPublic }
			WSC.event = function()
				return state.ev
			end
			WSC.ranch = function(slot)
				return if slot == 1 then state.ranch else nil
			end
			HUD._refresh()
			return c, HUD, state
		end

		-- état public de MON ranch (complet : RanchRenderer le lit aussi, le modèle Ranches/1 existant)
		local function ranchPublic(over)
			local r = {
				slot = 1,
				userId = 1,
				name = "Me",
				hidden = false,
				R = 3,
				fame = 0,
				day = 1,
				mode = "cozy",
				shield = false,
				boopable = false,
				tiles = { snack = 5, decor = 5, pens = 3, cozyBed = true, seen = 0 },
				vat = false,
				pool = false,
				vatFill = 0,
				growth = { G = 0, g = 1, t = NOW },
				carry = "",
				ride = "",
				saddle = 0,
				waiting = "",
				theme = "",
				flag = "",
				title = "",
				saddleColor = "",
				trail = "",
			}
			for k, v in over or {} do
				r[k] = v
			end
			return r
		end

		-- grand squishy : prestige de boucle prêt quelle que soit la boucle
		local BIG = { a = TvAudit.squishy(1, { z = 1e15 }) }

		-- aucune intention v2.0 d'achat ni de métrique (UiSeen « nextBuy » compté à part : la puce s'est
		-- montrée)
		local function noBuy(c)
			for _, name in { "BuyUpgrade", "MenuActivity", "ClientMetric" } do
				expect({ name = name, n = #TvAudit.sent(c.h, name) }).toEqual({ name = name, n = 0 })
			end
		end

		local function textsOf(root)
			local out = {}
			for _, d in root:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
					table.insert(out, d.Text)
				end
			end
			return out
		end

		it(
			"interrupteur coupé : HUD de la v1.3, aucune instance ni intention v2.0, glyphes dessinés",
			function()
				local c, HUD = v2setup({ profile = { fame = 42 } })
				local h = c.h
				expect(HUD.element("nextBuy")).toBeNil()
				expect(HUD.element("status"):FindFirstChild("memory")).toBeNil()
				expect(HUD.element("menuChip").Label.Size.X.Offset).toBe(96)
				local L = h:require("ReplicatedStorage.Shared.Config.Layout")
				expect(HUD.element("status").Size).toEqual(
					roblox.UDim2.fromOffset(L.Hud.status.rect.w, L.Hud.status.rect.h)
				)
				expect(HUD.element("gauge").Size).toEqual(
					roblox.UDim2.fromOffset(L.Hud.gauge.rect.w, L.Hud.gauge.rect.h)
				)
				-- Fame toujours là (v1.3), étoile et cœur dessinés devant les nombres
				expect(HUD.visible("fame")).toBe(true)
				expect(HUD.element("fame").FameIcon:GetAttribute("Icon")).toBe("star")
				expect(HUD.element("fame").FriendsIcon:GetAttribute("Icon")).toBe("heart")
				expect(HUD.element("fame").Fame.Text).toBe("42")
				-- aucun caractère hors des polices dans tout le HUD (règle 18, les deux états)
				for _, t in textsOf(h.localPlayer.PlayerGui.HUD) do
					expect({ text = t, missing = FontCmap.missing(CMAPS, t) }).toEqual({
						text = t,
						missing = {},
					})
				end
				S.run(c, 5)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		it(
			"Prochain achat : cible d'UpgradeAdvisor.next, nom court et niveau ; recalculée seulement après achat, prestige ou plafond ; 2 fois par seconde au plus",
			function()
				local c, HUD = v2setup({ snap = S.snap(1) })
				local h = c.h
				local NB = TvAudit.mod(h, "UI.Hud.NextBuy")
				local Advisor = h:require("ReplicatedStorage.Shared.Logic.UpgradeAdvisor")
				S.run(c, 1)
				local chip = HUD.element("nextBuy")
				expect(chip ~= nil and chip.Visible).toBe(true)
				local first = Advisor.next(c.US.current(), {})
				expect(NB.target().id).toBe(first.id)
				expect(NB.target().level).toBe(first.level)
				-- jamais un niveau déjà possédé ni inexistant
				expect(first.level).toBe((c.US.current().levels[first.id] or 0) + 1)
				expect(chip.ShortName.Text).toBe(S.Localization.get("en", "upgrades.short." .. first.id))
				expect(chip.Icon:GetAttribute("Icon") ~= "").toBe(true)
				local evals = NB.evaluations()
				-- 20 instantanés où seules les pièces changent : aucune évaluation, cible inchangée
				for v = 2, 21 do
					S.patch(
						c,
						S.snap(v, function(p)
							p.coins = 1000 + v
						end)
					)
					S.run(c, 0.2)
				end
				expect(NB.evaluations()).toBe(evals)
				expect(NB.target().id).toBe(first.id)
				-- 20 achats en 2 s (un niveau du Tapis toutes les 0,1 s) : au plus 2 évaluations par seconde
				for v = 22, 41 do
					S.patch(
						c,
						S.snap(v, function(p)
							p.tiles.snack = 7 + (v - 21) % 5
						end)
					)
					S.run(c, 0.1)
				end
				S.run(c, 0.6)
				local n = NB.evaluations() - evals
				expect(n >= 2 and n <= 6).toBe(true)
				-- la cible suit le DERNIER instantané (achat)
				local last = Advisor.next(c.US.current(), {})
				expect(NB.target().id).toBe(last.id)
				expect(NB.target().level).toBe(last.level)
				-- prestige (r, Record R) et plafonds : recalculée
				evals = NB.evaluations()
				S.patch(
					c,
					S.snap(42, function(p)
						p.R = 13
						p.bestR = 13
					end)
				)
				S.run(c, 0.6)
				expect(NB.evaluations()).toBe(evals + 1)
				noBuy(c)
				S.clean(c, expect)
			end
		)

		it(
			"payable : « Ready! » et une seule pulsation ; « have / need » sinon ; jamais de clignotement",
			function()
				local c, HUD = v2setup({ snap = S.snap(1, function(p)
					p.coins = 1
				end) })
				local h = c.h
				local Juice = TvAudit.mod(h, "UI.Juice")
				local chip = HUD.element("nextBuy")
				local pulses = 0
				local pulse = Juice.pulse
				Juice.pulse = function(gui, ...)
					if gui == chip then
						pulses += 1
					end
					return pulse(gui, ...)
				end
				S.run(c, 1)
				expect(chip:GetAttribute("Ready")).toBe(false)
				expect(string.find(chip.Value.Text, " / ", 1, true) ~= nil).toBe(true)
				-- assez de pièces : « Ready! », une pulsation ; d'autres instantanés payables : aucune de plus
				for v = 2, 8 do
					S.patch(
						c,
						S.snap(v, function(p)
							p.coins = 1e30 + v
						end)
					)
					S.run(c, 0.3)
				end
				expect(chip:GetAttribute("Ready")).toBe(true)
				expect(chip.Value.Text).toBe("Ready!")
				expect(pulses).toBe(1)
				S.clean(c, expect)
			end
		)

		it(
			"cachée pendant l'accueil avant la leçon du menu, rail ou panneau ouvert, suivi « Prêt » ; UiSeen une fois ; clic : Améliorations sur Conseillé",
			function()
				-- accueil en cours, leçon du menu pas encore vue : la puce Menu (et donc « Prochain
				-- achat ») ne sont pas encore montrées
				local c, HUD = v2setup({
					snap = S.snap(1),
					profile = { onboarding = { step = 2, done = false, demoDone = false } },
				})
				local h = c.h
				local function seen()
					local n = 0
					for _, args in TvAudit.sent(h, "UiSeen") do
						if args[1] == "nextBuy" then
							n += 1
						end
					end
					return n
				end
				S.run(c, 1)
				expect(HUD.visible("menuChip")).toBe(false)
				expect(HUD.visible("nextBuy")).toBe(false)
				expect(seen()).toBe(0)
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { onboarding = DONE }, {})
				S.run(c, 1)
				expect(HUD.visible("menuChip")).toBe(true)
				expect(HUD.visible("nextBuy")).toBe(true)
				expect(seen()).toBe(1)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(HUD.visible("nextBuy")).toBe(false)
				c.PC.closeAll()
				S.run(c, 0.5)
				expect(HUD.visible("nextBuy")).toBe(true)
				-- clic de souris : l'écran Améliorations sur Conseillé (D13), ouvert depuis le jeu (lot I,
				-- étape 2, plan I M4 / D14, journal I-14) : ○ rend la main au jeu en un appui (ni écran ni rail)
				HUD.element("nextBuy").Activated:Fire()
				S.run(c, 0.5)
				expect(c.PC.current()).toBe("Upgrades")
				expect(c.Up.currentTab()).toBe("suggested")
				expect(HUD.visible("nextBuy")).toBe(false)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				S.run(c, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				expect(c.PC.menuOpen()).toBe(false)
				expect(table.concat(TvAudit.mod(h, "UI.FocusGuard").names(), ",")).toBe("")
				-- suivi « Prêt » (Grand Splorch prêt) : cachée ; l'apparition suivante n'envoie rien
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { squishies = BIG }, {})
				S.run(c, 0.5)
				expect(HUD.element("goalTracker"):GetAttribute("Ready")).toBe(true)
				expect(HUD.visible("nextBuy")).toBe(false)
				h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ squishies = { a = TvAudit.squishy(1, { z = 10 }) } },
					{}
				)
				S.run(c, 0.5)
				expect(HUD.visible("nextBuy")).toBe(true)
				expect(seen()).toBe(1)
				S.clean(c, expect)
			end
		)

		it(
			"Fame et amis : 3 s quand ils changent, hors du HUD calme (≤ 8 éléments) ; « MENU » à 40 px",
			function()
				local c, HUD = v2setup({ snap = S.snap(1), profile = { fame = 10 } })
				local h = c.h
				TvAudit.mod(h, "Controllers.PromptController").current = function()
					return {
						kind = "squishy",
						slot = 1,
						uid = "u1",
						primary = "press",
						secondary = "pickup",
						ready = true,
						position = Vector3.new(0, 2, -6),
					}
				end
				TvAudit.mod(h, "Controllers.WorldStateController").squishies = function()
					return { u1 = TvAudit.squishy(2) }
				end
				S.run(c, 1)
				expect(HUD.visible("fame")).toBe(false)
				local names = {
					"coins",
					"fame",
					"menuChip",
					"nextBuy",
					"eventPill",
					"megaBar",
					"gauge",
					"goalTracker",
					"status",
					"specialChip",
					"targetCard",
					"leap",
				}
				local function count()
					local n = 0
					for _, name in names do
						if HUD.visible(name) then
							n += 1
						end
					end
					return n
				end
				expect(HUD.visible("targetCard")).toBe(true)
				expect(HUD.visible("nextBuy")).toBe(true)
				expect(count() <= 8).toBe(true)
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { fame = 11 }, {})
				S.run(c, 0.5)
				expect(HUD.visible("fame")).toBe(true)
				expect(HUD.element("fame").Fame.Text).toBe("11")
				S.run(c, 3)
				expect(HUD.visible("fame")).toBe(false)
				expect(count() <= 8).toBe(true)
				-- « MENU » dessiné à ses 40 px dans une boîte de 100 (plus de rétrécissement)
				local label = HUD.element("menuChip").Label
				local Text = TvAudit.mod(h, "UI.Text")
				expect(label.Size.X.Offset).toBe(100)
				expect(Text.kind(label)).toBe("label")
				expect(Text.drawnSize(label)).toBe(40)
				S.clean(c, expect)
			end
		)

		it(
			"puces spéciales : JELLY ASCEND ! (AscendReady, aucun Grand Splorch prêt, pas déjà en file) ; PETIT SPLORCH ! pendant une remontée ; GRAND SPLORCH ! d'abord ; « ! » de la puce Menu",
			function()
				local c, HUD, state = v2setup({ snap = S.snap(1), ranch = { AscendReady = true } })
				local h = c.h
				local chip = HUD.element("specialChip")
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("ascend")
				expect(chip:FindFirstChild("Text").Text).toBe("JELLY ASCEND!")
				expect(chip.Glyph:GetAttribute("GlyphKey")).toBe("ButtonY")
				expect(HUD.element("menuChip").Bang.Visible).toBe(true)
				-- déjà dans la file des grands spectacles : plus de puce
				state.ev = eventState({
					spectacle = {
						queue = {
							{
								kind = "ascend",
								userId = 1,
								startAt = NOW + 40,
								slot = 1,
								position = 2,
								eta = 40,
							},
						},
					},
				})
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("")
				state.ev = eventState()
				-- Grand Splorch prêt (pas de remontée) : GRAND SPLORCH ! d'abord, même avec l'Ascension prête
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { squishies = BIG }, {})
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("splorch")
				expect(chip:FindFirstChild("Text").Text).toBe("GRAND SPLORCH!")
				-- remontée (A = 1, r 3 < Record R 15) : PETIT SPLORCH !
				c.model:SetAttribute("AscendReady", false)
				S.patch(c, S.snap(2, regain(3)))
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("petit")
				expect(chip:FindFirstChild("Text").Text).toBe("PETIT SPLORCH!")
				expect(HUD.element("menuChip").Bang.Visible).toBe(false)
				noBuy(c)
				expect(#TvAudit.sent(c.h, "GrandSplorch")).toBe(0)
				S.clean(c, expect)
			end
		)

		it(
			"clic maintenu 1,5 s sur PETIT SPLORCH ! (souris) : GrandSplorch une fois, pas de menu ; premier de la remontée : aucun maintien",
			function()
				local c, HUD = v2setup({ snap = S.snap(1, regain(3)), profile = { R = 3, squishies = BIG } })
				local h = c.h
				local uis = h.game.UserInputService
				local chip = HUD.element("specialChip")
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("petit")
				local function mouseHold(secs)
					local down = {
						UserInputType = Enum.UserInputType.MouseButton1,
						UserInputState = Enum.UserInputState.Begin,
					}
					uis.InputBegan:Fire(down, true)
					chip.MouseButton1Down:Fire(10, 10)
					S.run(c, secs)
					uis.InputEnded:Fire({
						UserInputType = Enum.UserInputType.MouseButton1,
						UserInputState = Enum.UserInputState.End,
					}, true)
					chip.Activated:Fire()
					S.run(c, 0.3)
				end
				-- clic court : le menu s'ouvre sur l'entrée de renaissance, rien n'est envoyé
				mouseHold(0.2)
				expect(c.PC.menuOpen()).toBe(true)
				expect(#TvAudit.sent(h, "GrandSplorch")).toBe(0)
				c.PC.closeAll()
				S.run(c, 0.5)
				-- clic maintenu 1,6 s : GrandSplorch(false, squishy « a ») une fois, le menu reste fermé
				mouseHold(1.6)
				local sent = TvAudit.sent(h, "GrandSplorch")
				expect(#sent).toBe(1)
				expect(sent[1][1]).toBe(false)
				expect(sent[1][2]).toBe("a")
				expect(c.PC.menuOpen()).toBe(false)
				-- premier Petit Splorch de la remontée (r = Prestige.startR(1, 0) = 0) : aucun maintien
				S.patch(c, S.snap(2, regain(0)))
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { R = 0 }, {})
				S.run(c, 0.5)
				expect(chip:GetAttribute("Mode")).toBe("petit")
				mouseHold(1.6)
				expect(#TvAudit.sent(h, "GrandSplorch")).toBe(1)
				S.clean(c, expect)
			end
		)

		it(
			"Souvenir de gelée à la place du bouclier débutant (jamais les deux) ; suivi « Back to record » + « r / Record R », gardé quand le Petit Splorch est prêt (puce PETIT SPLORCH !)",
			function()
				local c, HUD = v2setup({
					snap = S.snap(1, regain(3)),
					profile = { R = 3 },
					ranchPublic = ranchPublic({ shield = true }),
				})
				local h = c.h
				S.run(c, 0.5)
				local status = HUD.element("status")
				expect(status.memory.Visible).toBe(true)
				expect(status.shield.Visible).toBe(false)
				expect(status.memory.Icon.Drop:GetAttribute("Icon")).toBe("drop")
				expect(string.sub(status.memory.Minutes.Text, 1, 2)).toBe("×")
				expect(text(h, HUD, "goalTracker", "Title")).toBe("Back to record")
				expect(text(h, HUD, "goalTracker", "Value")).toBe("3 / 15")
				expect(HUD.element("goalTracker"):GetAttribute("Regain")).toBe(true)
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { squishies = BIG }, {})
				S.run(c, 0.5)
				-- Petit Splorch prêt : la puce « PETIT SPLORCH ! » le dit ; le suivi garde « Retour au record »
				-- et « 3 / 15 » (GDD §10.2 et §10.8, état clé 24 : « PETIT SPLORCH ! », Souvenir ×3, « Retour
				-- au record 4 / 15 » ensemble ; relecture des captures de l'étape 5 : « Prêt ! » le cachait)
				expect(HUD.element("specialChip"):GetAttribute("Mode")).toBe("petit")
				expect(HUD.element("goalTracker"):GetAttribute("Ready")).toBe(true)
				expect(text(h, HUD, "goalTracker", "Title")).toBe("Back to record")
				expect(text(h, HUD, "goalTracker", "Value")).toBe("3 / 15")
				expect(status.memory.Visible).toBe(true)
				-- fin de la remontée (r = Record R) : bouclier de nouveau, titre du Grand Splorch
				S.patch(
					c,
					S.snap(2, function(p)
						p.ascend = 1
						p.R = 15
						p.bestR = 15
					end)
				)
				h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ squishies = { a = TvAudit.squishy(1) } },
					{}
				)
				S.run(c, 0.5)
				expect(text(h, HUD, "goalTracker", "Title")).toBe("Grand Splorch")
				expect(status.shield.Visible).toBe(true)
				expect(status.memory.Visible).toBe(false)
				S.clean(c, expect)
			end
		)

		it("file des grands spectacles : une entrée « ascend » compte comme un Grand Splorch", function()
			local c, HUD, state = v2setup({ snap = S.snap(1), ranch = { AscendReady = true } })
			local h = c.h
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			state.ev = eventState({
				spectacle = {
					queue = {
						{
							kind = "splorch",
							userId = 9,
							startAt = NOW + 20,
							slot = 3,
							position = 1,
							eta = 20,
						},
						{ kind = "ascend", userId = 1, startAt = NOW + 30, slot = 1, position = 2, eta = 30 },
					},
				},
			})
			WSC.EventChanged:Fire(state.ev)
			HUD._refresh()
			expect(text(h, HUD, "goalTracker", "Value")).toBe("#2 in line · about 0:30")
			expect(text(h, HUD, "goalTracker", "Title")).toBe("Jelly Ascend")
			expect(HUD.element("goalTracker"):GetAttribute("Queued")).toBe(true)
			S.clean(c, expect)
		end)
	end)
end
