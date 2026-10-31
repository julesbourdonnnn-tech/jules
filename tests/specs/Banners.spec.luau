--!nocheck
-- Banners (paquet client-hud) : file locale de 3 triée par priorité (personnelles d'abord), une
-- bannière à la fois pendant 3 s (+ glissade), textes EN/FR interpolés (chiffres romains, espèces,
-- météo, compte à rebours), charges malveillantes ignorées sans erreur (docs §13.10, GDD §6.5).

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function setup(locale)
		local h = Harness.new({ mode = "client" })
		h.localPlayer.LocaleId = locale or "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			Banners = h:require(CLIENT .. "UI.Banners"),
			shown = {},
		}
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.Banners.Init()
		c.Banners.Start()
		c.Banners.Shown:Connect(function(payload)
			table.insert(c.shown, payload)
		end)
		return c
	end

	local function banner(c)
		return c.h.localPlayer.PlayerGui.Banners.Safe.Banner
	end

	-- avance le temps de jeu et fait tourner une image (la file est pilotée par Heartbeat)
	local function advance(c, dt)
		c.Clock.advance(dt)
		c.h:step(1 / 60, 1)
	end

	describe("Banners › file et priorités", function()
		it("affiche une bannière reçue du serveur et la retire après 3 s", function()
			local c = setup()
			c.h:fireClient("ReplicatedStorage.Remotes.Banner", {
				kind = "megaParade",
				args = { userId = 7, name = "Mira", n = 32 },
				priority = 4,
			})
			expect(#c.shown).toBe(1)
			expect(c.Banners.current().kind).toBe("megaParade")
			local frame = banner(c)
			expect(frame.Visible).toBe(true)
			expect(frame.Text.Text).toBe("Mira: MEGA PARADE ×32!")
			advance(c, 2)
			expect(c.Banners.current() ~= nil).toBe(true)
			advance(c, 1.3) -- 0,25 s d'entrée + 3 s : départ de la sortie
			advance(c, 0.25)
			expect(c.Banners.current()).toBeNil()
			expect(frame.Visible).toBe(false)
		end)

		it("garde 3 bannières en attente au plus, triées par priorité puis par arrivée", function()
			local c = setup()
			c.Banners.show({
				kind = "weather",
				args = { key = "aurora", form = 1, endsAt = T0 + 150 },
				priority = 7,
			})
			expect(c.Banners.current().kind).toBe("weather")
			c.Banners.show({ kind = "glowParty", args = { name = "A", minutes = 10 }, priority = 6 })
			c.Banners.show({ kind = "liveOps", args = {}, priority = 7 })
			c.Banners.show({ kind = "mythicCatch", args = { name = "B", code = 33 }, priority = 1 })
			c.Banners.show({ kind = "supernova", args = { name = "C", level = 3 }, priority = 3 })
			local q = c.Banners.queued()
			expect(#q).toBe(3)
			expect(q[1].kind).toBe("mythicCatch")
			expect(q[2].kind).toBe("supernova")
			expect(q[3].kind).toBe("glowParty") -- liveOps (7, la plus faible) est tombée
			-- la bannière en cours n'est jamais interrompue
			expect(c.Banners.current().kind).toBe("weather")
			advance(c, 3.3)
			advance(c, 0.25)
			expect(c.Banners.current().kind).toBe("mythicCatch")
			expect(#c.Banners.queued()).toBe(2)
		end)

		it("les bannières personnelles passent devant à priorité moindre", function()
			local c = setup()
			c.Banners.show({
				kind = "weather",
				args = { key = "frost", form = 2, endsAt = T0 + 100 },
				priority = 7,
			})
			c.Banners.show({ kind = "mythicCatch", args = { name = "B", code = 33 }, priority = 1 })
			c.Banners.show({ kind = "atlasMilestone", args = { count = 25 }, priority = 3, personal = true })
			local q = c.Banners.queued()
			expect(q[1].kind).toBe("atlasMilestone")
			expect(q[1].personal).toBe(true)
			expect(q[2].kind).toBe("mythicCatch")
		end)
	end)

	describe("Banners › textes", function()
		it("Supernova en chiffres romains, espèce depuis le code, météo et multiplicateur", function()
			local c = setup()
			expect(c.Banners.text({ kind = "supernova", args = { name = "Léa", level = 3 }, priority = 3 })).toBe(
				"Léa: SUPERNOVA III!"
			)
			local code = c.Nebbies.pack(1, 0, 0)
			expect(
				c.Banners.text({ kind = "mythicCatch", args = { name = "Mira", code = code }, priority = 1 })
			).toBe("Mira caught a MYTHIC Puffkin!")
			expect(c.Banners.text({
				kind = "weather",
				args = { key = "aurora", form = 1, endsAt = T0 + 150 },
				priority = 7,
			})).toBe("Aurora Drift Nebbies ×" .. tostring(c.Nebbies.Forms[1].mult) .. " · 2:30")
			expect(
				c.Banners.text({ kind = "weather", args = { key = "meteor", endsAt = T0 + 90 }, priority = 7 })
			).toBe("Meteor Shower! More Nebbies · 1:30")
			expect(c.Banners.text({ kind = "cometStolen", args = { name = "Noah" }, priority = 2 })).toBe(
				"COMET STOLEN by Noah!"
			)
		end)

		it("français : textes traduits, compte à rebours mis à jour à chaque image", function()
			local c = setup("fr-fr")
			c.Banners.show({
				kind = "weather",
				args = { key = "frost", form = 2, endsAt = T0 + 150 },
				priority = 7,
			})
			local label = banner(c).Text
			expect(label.Text).toContain("2:30")
			expect(label.Text).toContain(
				c.h:require("ReplicatedStorage.Shared.Localization").get("fr", "weather.frost")
			)
			advance(c, 5)
			expect(label.Text).toContain("2:25")
			c.Banners.show({ kind = "starfall", args = { s = 1, endsAt = T0 + 20 }, priority = 6 })
			expect(c.Banners.text(c.Banners.queued()[1])).toContain("Puffkin")
			c.Banners.show({ kind = "beaconStart", args = {}, priority = 6 })
			expect(c.Banners.text(c.Banners.queued()[2])).toBe(
				c.h:require("ReplicatedStorage.Shared.Localization").get("fr", "banner.beaconStart")
			)
		end)

		it("arguments manquants ou absurdes : texte de repli, aucune erreur", function()
			local c = setup()
			local text = c.Banners.text({
				kind = "mythicCatch",
				args = { name = string.rep("x", 200), code = 0 / 0 },
				priority = 1,
			})
			expect(text).toContain("MYTHIC ?")
			expect(#text < 120).toBe(true)
			expect(c.Banners.text({ kind = "supernova", args = {}, priority = 3 })).toBe("?: SUPERNOVA ?!")
		end)
	end)

	describe("Banners › revue (bogues corrigés)", function()
		it("nom non latin : affiché en entier, jamais coupé au milieu d'un caractère UTF-8", function()
			local c = setup()
			local name = string.rep("語", 20) -- DisplayName de 20 caractères, 60 octets
			local text = c.Banners.text({
				kind = "supernova",
				args = { name = name, level = 2 },
				priority = 3,
			})
			expect(utf8.len(text) ~= nil).toBe(true)
			expect(string.find(text, name, 1, true) ~= nil).toBe(true)
		end)

		it("Nuit de la Balise : la bannière s'affiche sous la barre de serveur, pas dessus", function()
			local c = setup()
			local WSC = c.h:require(CLIENT .. "Controllers.WorldStateController")
			local events = nil
			WSC.events = function()
				return events
			end
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Banner",
				{ kind = "weather", args = { key = "aurora", form = 1 }, priority = 7 }
			)
			c.h:step(1 / 60, 1)
			expect(banner(c).Position.Y.Offset).toBe(72)
			advance(c, 3.5)
			events = {
				t = T0,
				beacon = {
					phase = "active",
					warnAt = T0 - 15,
					startsAt = T0,
					endsAt = T0 + 180,
					points = 3,
					goal = 40,
				},
				wisps = {},
				snipsDisabled = true,
				activePlayers = 4,
			}
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Banner",
				{ kind = "beaconStart", args = {}, priority = 6 }
			)
			c.h:step(1 / 60, 1)
			expect(c.Banners.current().kind).toBe("beaconStart")
			expect(banner(c).Position.Y.Offset).toBe(72 + 34)
			-- données d'événement illisibles : position par défaut, aucune erreur
			advance(c, 3.5)
			events = { beacon = "x" }
			c.h:fireClient("ReplicatedStorage.Remotes.Banner", { kind = "liveOps", args = {}, priority = 7 })
			c.h:step(1 / 60, 1)
			expect(banner(c).Position.Y.Offset).toBe(72)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("Banners › charges malveillantes", function()
		it("ignore les charges invalides sans erreur ni affichage", function()
			local c = setup()
			local bad = {
				"x",
				42,
				{},
				{ kind = 5 },
				{ kind = "notAKind", args = {} },
				{ kind = "supernova", args = "oops", priority = 0 / 0 },
				{ kind = "supernova", args = { [1] = "a", [{}] = 2, name = {} }, priority = math.huge },
			}
			for _, payload in bad do
				c.h:fireClient("ReplicatedStorage.Remotes.Banner", payload)
			end
			-- seules les deux dernières (genre connu) passent, priorité normalisée
			expect(#c.shown).toBe(1)
			expect(c.shown[1].priority).toBe(7)
			expect(c.shown[1].args.name).toBeNil()
			expect(#c.Banners.queued()).toBe(1)
			local big = { kind = "liveOps", args = {}, priority = 7 }
			for i = 1, 100 do
				big.args["k" .. i] = i
			end
			c.Banners.show(big)
			expect(#c.Banners.queued()).toBe(2)
			local stored = c.Banners.queued()[2]
			local count = 0
			for _ in stored.args do
				count += 1
			end
			expect(count <= 16).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)
end
