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
local ApiAudit = require("../harness/ApiAudit")
local FontCmap = require("../harness/FontCmap")

local Vector3 = roblox.Vector3

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
			-- « ≈ » (hors police, règle 18) devenu le mot « about » / « environ » (lot B2, D19, journal B2-31)
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
				-- « ♥ » (hors police) devenu un cœur DESSINÉ devant le nombre (lot B2, D18, journal B2-31)
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
			-- « ′ » (hors police) devenu une marque DESSINÉE après le nombre (lot B2, D20, journal B2-31)
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
end
