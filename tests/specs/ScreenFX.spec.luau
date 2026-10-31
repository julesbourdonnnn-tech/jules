--!nocheck
-- ScreenFX (paquet client-hud) : propriétaire de Feedback et Celebrate (toasts, tampons, « +N »,
-- signaux FeedbackReceived / Celebrated), juice d'écran (tampon PARADE, pièces volantes vers
-- HUD.anchor("glow"), vignette de coupe, confettis, titre de Supernova, cartes d'Atlas), Mouvement
-- réduit, charges malveillantes (docs §13.9, GDD §9.1-§9.4).
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h.localPlayer.LocaleId = opts.locale or "en-us"
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			vfx = {},
			feedback = {},
			celebrated = {},
			slot = 1,
			length = 0,
		}
		-- isolation : paquet client-world remplacé (les signaux restent réels)
		c.VFX.playUpgrade = function(track, level)
			table.insert(c.vfx, { track = track, level = level })
		end
		c.WSC.localSlot = function()
			return c.slot
		end
		c.WSC.lineLength = function()
			return c.length
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.FX.Start()
		c.FX.FeedbackReceived:Connect(function(p)
			table.insert(c.feedback, p)
		end)
		c.FX.Celebrated:Connect(function(p)
			table.insert(c.celebrated, p)
		end)
		-- cible des pièces (pastille Glow du HUD)
		local gui = c.g.Instance.new("ScreenGui")
		gui.Name = "FakeHUD"
		gui.Parent = h.localPlayer.PlayerGui
		local pill = c.g.Instance.new("Frame")
		pill.Name = "GlowPill"
		pill.AbsolutePosition = Vector2.new(16, 16)
		pill.AbsoluteSize = Vector2.new(260, 64)
		pill.Parent = gui
		c.pill = pill
		c.FX.setAnchorResolver(function(element)
			return if element == "glow" then pill else nil
		end)
		return c
	end

	local function toasts(c)
		local out = {}
		local gui = c.h.localPlayer.PlayerGui:FindFirstChild("Toasts")
		if gui == nil then
			return out
		end
		for _, t in gui.Safe.Stack:GetChildren() do
			if t.Name == "Toast" then
				table.insert(out, t.Label.Text)
			end
		end
		return out
	end

	local function fx(c)
		return c.h.localPlayer.PlayerGui.ScreenFX
	end

	local function frames(c, n, dt)
		c.h:step(dt or 1 / 30, n)
	end

	describe("ScreenFX › Feedback", function()
		it("toast traduit avec nombres abrégés, puis FeedbackReceived", function()
			local c = setup()
			c.h:fireClient("ReplicatedStorage.Remotes.Feedback", {
				key = "feedback.notEnoughGlow",
				vars = { missing = 1200 },
				tone = "error",
			})
			expect(toasts(c)[1]).toBe("1.2K Glow missing")
			expect(#c.feedback).toBe(1)
			expect(c.feedback[1].key).toBe("feedback.notEnoughGlow")
			expect(c.feedback[1].tone).toBe("error")
			expect(c.feedback[1].vars.missing).toBe("1.2K")
		end)

		it("français : virgule décimale et texte FR", function()
			local c = setup({ locale = "fr-fr" })
			c.h:fireClient("ReplicatedStorage.Remotes.Feedback", {
				key = "feedback.notEnoughGlow",
				vars = { missing = 1240 },
				tone = "error",
			})
			expect(toasts(c)[1]).toContain("1,24")
		end)

		it(
			"file pleine : petit tampon « FULL » (pas de toast), le même toast n'est pas répété",
			function()
				local c = setup()
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Feedback",
					{ key = "feedback.lineFull", vars = {}, tone = "warning" }
				)
				local small = fx(c).Safe.SmallStamp
				expect(small.Visible).toBe(true)
				expect(small.Text).toBe("FULL")
				expect(#toasts(c)).toBe(0)
				frames(c, 75) -- 2,5 s : le tampon s'efface
				expect(small.Visible).toBe(false)
				for _ = 1, 3 do
					c.h:fireClient(
						"ReplicatedStorage.Remotes.Feedback",
						{ key = "feedback.zenOn", vars = {}, tone = "info" }
					)
				end
				expect(#toasts(c)).toBe(1)
				expect(#c.feedback).toBe(4)
			end
		)

		it("retour local (notify) : même chemin qu'un Feedback serveur", function()
			local c = setup()
			c.FX.notify("feedback.cometNoDash", nil, "warning")
			expect(toasts(c)[1]).toBe("No Dash while carrying the Comet")
			expect(c.feedback[1].key).toBe("feedback.cometNoDash")
		end)

		it("charges malveillantes ignorées sans erreur", function()
			local c = setup()
			local nan = 0 / 0
			local huge = {}
			for i = 1, 200 do
				huge["v" .. i] = i
			end
			for _, payload in
				{
					"x",
					12,
					{},
					{ key = 5 },
					{ key = "feedback.x y" },
					{ key = string.rep("a", 200) },
					{
						key = "feedback.notEnoughGlow",
						vars = { missing = nan, [1] = "z", bad = {} },
						tone = "evil",
					},
					{ key = "feedback.notEnoughGlow", vars = huge, tone = 3 },
				}
			do
				c.h:fireClient("ReplicatedStorage.Remotes.Feedback", payload)
			end
			-- seules les deux clés valides passent, ton ramené à « info », variables filtrées
			expect(#c.feedback).toBe(2)
			expect(c.feedback[1].tone).toBe("info")
			expect(c.feedback[1].vars.missing).toBeNil()
			expect(c.feedback[1].vars.bad).toBeNil()
			local count = 0
			for _ in c.feedback[2].vars do
				count += 1
			end
			expect(count <= 16).toBe(true)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("ScreenFX › Celebrate", function()
		it("Supernova : le titre s'écrit en 0,6 s (MaxVisibleGraphemes) puis disparaît", function()
			local c = setup()
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "supernova", data = { level = 3 } }
			)
			local title = fx(c).Safe.SupernovaTitle
			expect(title.Text).toBe("SUPERNOVA III")
			expect(title.Visible).toBe(true)
			frames(c, 6, 0.05) -- 0,3 s
			expect(title.MaxVisibleGraphemes > 0 and title.MaxVisibleGraphemes < 13).toBe(true)
			frames(c, 8, 0.05) -- 0,7 s
			expect(title.MaxVisibleGraphemes).toBe(-1)
			frames(c, 60, 0.05) -- 3,7 s
			expect(title.Visible).toBe(false)
			expect(c.celebrated[1].kind).toBe("supernova")
		end)

		it("amélioration : VFXController.playUpgrade(track, level) + Celebrated", function()
			local c = setup()
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "upgrade", data = { track = "conga", level = 4 } }
			)
			expect(#c.vfx).toBe(1)
			expect(c.vfx[1].track).toBe("conga")
			expect(c.vfx[1].level).toBe(4)
			expect(c.celebrated[1].data.level).toBe(4)
			-- données absurdes : rien n'est joué, l'événement reste signalé
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "upgrade", data = { track = {}, level = 0 / 0 } }
			)
			expect(#c.vfx).toBe(1)
		end)

		it("Atlas : 3 cartes à l'écran au plus, les suivantes attendent", function()
			local c = setup()
			local entries = {}
			for s = 1, 5 do
				table.insert(entries, { s = s, f = 0 })
			end
			table.insert(entries, { s = 999, f = 0 })
			table.insert(entries, "junk")
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "atlasNew", data = { entries = entries } }
			)
			local st = c.FX._state()
			expect(st.cards).toBe(3)
			expect(st.queuedCards).toBe(2)
			local card = fx(c).Safe.AtlasCard
			expect(card.Text.Text).toBe("NEW! " .. c.Nebbies.Species[1].name .. " · Normal")
			frames(c, 100, 0.05) -- 5 s : les premières sortent, les suivantes entrent
			st = c.FX._state()
			expect(st.queuedCards).toBe(0)
		end)

		it("ReturnScreen : « offline » n'affiche rien mais est relayé aux panneaux", function()
			local c = setup()
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "offline",
				data = { glow = 5000, seconds = 3600, nightShift = false },
			})
			expect(c.celebrated[1].kind).toBe("offline")
			expect(c.celebrated[1].data.glow).toBe(5000)
		end)

		it("récompenses de quête : pièces vers le compteur, déblocage traduit", function()
			local c = setup()
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "questClaimed",
				data = { kind = "onboarding", slot = 1, glow = 50, stardust = 0 },
			})
			expect(c.FX._state().flights).toBe(8)
			c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
				kind = "unlock",
				data = { kind = "styles", id = "comet_tail" },
			})
			expect(toasts(c)[1]).toBe("Unlocked: Comet Tail")
			frames(c, 30)
			expect(c.FX._state().flights).toBe(0)
		end)

		it("charges malveillantes ignorées sans erreur", function()
			local c = setup()
			for _, payload in
				{
					"x",
					{},
					{ kind = "nope", data = {} },
					{ kind = 3 },
					{ kind = "atlasNew", data = "x" },
					{ kind = "atlasNew", data = { entries = { { s = 0 / 0, f = math.huge } } } },
					{ kind = "unlock", data = { kind = "styles", id = "../../x y" } },
					{ kind = "supernova", data = { level = "III" } },
				}
			do
				c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", payload)
			end
			expect(#c.celebrated).toBe(4)
			expect(c.FX._state().cards).toBe(0)
			expect(#toasts(c)).toBe(0)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	describe("ScreenFX › juice du joueur local", function()
		it("parade locale : tampon « PARADE ×1.16! » et 8-16 pièces de la porte au compteur", function()
			local c = setup()
			local camera = c.h.workspace.CurrentCamera
			camera.WorldToViewportPoint = function(_, _pos)
				return Vector3.new(640, 500, 10), true
			end
			c.WSC.Banked:Fire(1, {
				op = "bank",
				slot = 1,
				ver = 3,
				count = 3,
				glow = 69,
				bonus = 1.16,
				atBeacon = false,
				newEntries = 0,
			})
			local stamp = fx(c).Safe.Stamp
			expect(stamp.Visible).toBe(true)
			expect(stamp.Text).toBe("PARADE ×1.16!")
			local st = c.FX._state()
			expect(st.flights).toBe(9)
			frames(c, 40)
			expect(c.FX._state().flights).toBe(0)
			expect(c.pill:FindFirstChild("JuiceScale") ~= nil).toBe(true)
			expect(stamp.Visible).toBe(false)
		end)

		it("parade d'un autre joueur : rien à l'écran", function()
			local c = setup()
			c.WSC.Banked:Fire(5, {
				op = "bank",
				slot = 5,
				ver = 3,
				count = 30,
				glow = 9999,
				bonus = 3.3,
				atBeacon = false,
				newEntries = 0,
			})
			expect(fx(c).Safe:FindFirstChild("Stamp")).toBeNil()
			expect(c.FX._state().flights).toBe(0)
		end)

		it("coupe subie : vignette rose qui pulse puis disparaît", function()
			local c = setup()
			c.WSC.Snipped:Fire({
				snipperSlot = 2,
				victimSlot = 1,
				ver = 4,
				cutIndex = 4,
				count = 3,
				looseIds = {},
				loose = {},
				byWisp = false,
				x = 0,
				y = 0,
				z = 0,
				dust = 0,
			})
			local layer = fx(c).Layer
			local top = layer.VignetteTop
			expect(top.Visible).toBe(true)
			frames(c, 3, 0.05)
			expect(top.BackgroundTransparency < 1).toBe(true)
			frames(c, 10, 0.05)
			expect(top.Visible).toBe(false)
		end)

		it(
			"la file se remplit : « Conga ×3! » ; vol de Comète par le joueur local : « COMET STOLEN! »",
			function()
				local c = setup()
				c.length = 3
				c.WSC.LineOp:Fire(1, { op = "add", slot = 1, ver = 3, codes = { 1 }, ids = { 0 } })
				expect(fx(c).Safe.SmallStamp.Text).toBe("Conga ×3!")
				local comet = {
					id = 600,
					phase = "carried",
					x = 0,
					z = 0,
					code = 1,
					warnAt = 0,
					impactAt = 0,
					burstAt = 0,
				}
				comet.carrierId = 2
				c.WSC.EventChanged:Fire(
					{ t = T0, comet = comet, wisps = {}, snipsDisabled = false, activePlayers = 2 },
					nil
				)
				expect(fx(c).Safe:FindFirstChild("Stamp")).toBeNil()
				local stolen = table.clone(comet)
				stolen.carrierId = c.h.localPlayer.UserId
				c.WSC.EventChanged:Fire(
					{ t = T0, comet = stolen, wisps = {}, snipsDisabled = false, activePlayers = 2 },
					nil
				)
				expect(fx(c).Safe.Stamp.Text).toBe("COMET STOLEN!")
			end
		)

		it("Mouvement réduit : ni pièces volantes ni confettis, le tampon apparaît en fondu", function()
			local c = setup()
			c.Prefs._onSettings({ reducedMotion = true })
			c.FX.flyCoins(Vector2.new(100, 100), c.pill, 10)
			expect(c.FX._state().flights).toBe(0)
			c.FX.confetti(50)
			expect(#c.FX._state().confetti).toBe(0)
			c.FX.stamp("TEST", Color3.new(1, 1, 1), "parade")
			local stamp = fx(c).Safe.Stamp
			expect(stamp.Rotation).toBe(0)
			expect(stamp.StampScale.Scale).toBe(1)
		end)

		it("API : confettis bornés, arguments invalides ignorés", function()
			local c = setup()
			c.FX.confetti(500)
			expect(#c.FX._state().confetti).toBe(80)
			frames(c, 60, 0.05)
			local alive = 0
			for _, piece in c.FX._state().confetti do
				if piece.busy then
					alive += 1
				end
			end
			expect(alive).toBe(0)
			c.FX.flyCoins("x", c.pill, 3)
			c.FX.flyCoins(Vector2.new(0, 0), nil, 3)
			c.FX.flyCoins(Vector2.new(0, 0), c.pill, 0 / 0)
			c.FX.floater(nil, Vector2.new(0, 0), Color3.new())
			c.FX.vignette(Color3.new(), -1)
			c.FX.stamp(nil, Color3.new())
			c.FX.confetti(0 / 0)
			expect(c.FX._state().flights).toBe(0)
			c.FX.floater("+5", Vector2.new(50, 50), Color3.new(1, 1, 0))
			frames(c, 30)
			expect(#c.h:signalErrors()).toBe(0)
		end)
	end)

	-- Le harnais applique un tween d'un coup ; ici, les tweens de Juice restent « en vol » jusqu'à
	-- finish() (comme dans Roblox, où une affectation directe n'annule PAS un tween en cours ; seul
	-- un nouveau Juice.tween sur la même propriété l'annule)
	local function slowTweens(c)
		local Juice = c.h:require(CLIENT .. "UI.Juice")
		local pending = {}
		local original = Juice.tween
		Juice.tween = function(inst, duration, props, style, direction, delayTime)
			for _, p in pending do
				if p.inst == inst then
					for prop in props do
						p.props[prop] = nil
					end
				end
			end
			table.insert(pending, { inst = inst, props = table.clone(props) })
			return original(inst, duration, {}, style, direction, delayTime)
		end
		return function()
			for _, p in pending do
				for k, v in p.props do
					p.inst[k] = v
				end
			end
			table.clear(pending)
		end
	end

	describe("ScreenFX › revue (bogues corrigés)", function()
		it("un tampon remontré pendant le fondu de sortie reste visible (aucun fondu en vol)", function()
			local c = setup()
			local finish = slowTweens(c)
			c.FX.stamp("ONE", Color3.new(1, 1, 1), "small")
			frames(c, 1)
			-- petit tampon : entrée 0,2 s + tenue 1,5 s, puis fondu de 0,2 s
			frames(c, 53) -- ≈ 1,8 s : fondu de sortie entamé
			local small = fx(c).Safe.SmallStamp
			expect(small.Visible).toBe(true)
			c.FX.stamp("TWO", Color3.new(1, 1, 1), "small")
			finish() -- les tweens encore en vol se terminent
			frames(c, 1)
			expect(small.Visible).toBe(true)
			expect(small.Text).toBe("TWO")
			expect(small.TextTransparency).toBe(0)
			expect(small:FindFirstChildOfClass("UIStroke").Transparency).toBe(0)
			-- puis le nouveau tampon s'efface normalement
			frames(c, 75)
			expect(small.Visible).toBe(false)
		end)

		it("Mouvement réduit : fondu d'entrée piloté image par image", function()
			local c = setup()
			c.Prefs._onSettings({ reducedMotion = true })
			c.FX.stamp("CALM", Color3.new(1, 1, 1), "small")
			local small = fx(c).Safe.SmallStamp
			expect(small.TextTransparency).toBe(1)
			frames(c, 2, 0.03) -- 0,06 s : à mi-fondu
			expect(small.TextTransparency > 0 and small.TextTransparency < 1).toBe(true)
			frames(c, 3, 0.03)
			expect(small.TextTransparency).toBe(0)
		end)

		it("anti-doublon des toasts : mémoire bornée pendant une longue session", function()
			local c = setup()
			for i = 1, 300 do
				c.h:fireClient("ReplicatedStorage.Remotes.Feedback", {
					key = "feedback.notEnoughGlow",
					vars = { missing = i },
					tone = "error",
				})
				frames(c, 1)
			end
			local memory = c.FX._state().toastMemory
			expect(type(memory)).toBe("number")
			expect(memory <= 40).toBe(true)
			-- l'anti-doublon fonctionne toujours
			local before = #c.feedback
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Feedback",
				{ key = "feedback.zenOn", vars = {}, tone = "info" }
			)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Feedback",
				{ key = "feedback.zenOn", vars = {}, tone = "info" }
			)
			expect(#c.feedback).toBe(before + 2)
			expect(toasts(c)[#toasts(c)]).toBe(c.Prefs.t("feedback.zenOn"))
			local zen = 0
			for _, text in toasts(c) do
				if text == c.Prefs.t("feedback.zenOn") then
					zen += 1
				end
			end
			expect(zen).toBe(1)
		end)

		it(
			"achat avec la réserve de pièces pleine : aucune pièce déjà en vol n'est reprogrammée",
			function()
				local c = setup()
				c.FX.flyCoins(Vector2.new(100, 400), c.pill, 40)
				local list = c.FX._state().flightList
				expect(#list).toBe(40)
				local before = {}
				for i, f in list do
					before[i] = f.t0
				end
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "purchase", data = { product = "GlowPack" } }
				)
				list = c.FX._state().flightList
				expect(#list).toBe(40)
				for i, f in list do
					expect({ i = i, t0 = f.t0 }).toEqual({ i = i, t0 = before[i] })
				end
				-- réserve libre : la pluie de 30 pièces part, échelonnée sur 1 s
				frames(c, 60)
				expect(c.FX._state().flights).toBe(0)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "purchase", data = { product = "GlowPack" } }
				)
				expect(c.FX._state().flights).toBe(30)
			end
		)

		it(
			"carte d'Atlas : le reflet est une bande blanche sous le texte, pas un trou transparent",
			function()
				local c = setup()
				c.h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "atlasNew", data = { entries = { { s = 1, f = 0 } } } }
				)
				local card = fx(c).Safe.AtlasCard
				expect(card:FindFirstChildOfClass("UIGradient")).toBeNil()
				local shine = card:FindFirstChild("Shine")
				expect(shine ~= nil and shine:IsA("Frame")).toBe(true)
				expect(shine.BackgroundColor3).toEqual(Color3.new(1, 1, 1))
				expect(shine.ShineGradient.Offset).toEqual(Vector2.new(1, 0)) -- balayage −1 → 1
				expect(shine.ZIndex < card.Text.ZIndex).toBe(true)
			end
		)

		it("amélioration d'une piste inconnue, niveau ou étoiles absurdes : aucun effet joué", function()
			local c = setup()
			for _, data in
				{
					{ track = "hack", level = 3 },
					{ track = string.rep("x", 500), level = 1 },
					{ track = "conga", level = -5 },
					{ track = "conga", level = 1e12 },
				}
			do
				c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "upgrade", data = data })
			end
			expect(#c.vfx).toBe(0)
			expect(#c.celebrated).toBe(4)
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "starforge", data = { stars = 1e300 } }
			)
			expect(fx(c).Safe:FindFirstChild("SmallStamp")).toBeNil()
			c.h:fireClient(
				"ReplicatedStorage.Remotes.Celebrate",
				{ kind = "starforge", data = { stars = 3 } }
			)
			expect(fx(c).Safe.SmallStamp.Text).toBe("★3!")
		end)

		it("noms non latins : jamais coupés au milieu d'un caractère UTF-8", function()
			local c = setup()
			local Text = c.h:require(CLIENT .. "UI.Hud.Text")
			local name = string.rep("語", 20) -- 60 octets, 20 caractères
			expect(Text.cleanName(name)).toBe(name)
			local long = Text.cleanName(string.rep("Ж", 50))
			expect(utf8.len(long)).toBe(32)
			-- variable de Feedback : chaîne tronquée à 48 caractères, toujours valide
			c.h:fireClient("ReplicatedStorage.Remotes.Feedback", {
				key = "feedback.crewJoined",
				vars = { name = string.rep("é", 60) },
				tone = "success",
			})
			local text = toasts(c)[1]
			expect(utf8.len(text) ~= nil).toBe(true)
			expect(utf8.len(c.feedback[1].vars.name)).toBe(48)
			-- octets invalides : seuls les caractères ASCII sont gardés
			expect(Text.cleanName("Mi\255ra")).toBe("Mira")
		end)
	end)
end
