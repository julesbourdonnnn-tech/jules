--!nocheck
-- Prompt (paquet client-hud ; docs/04 §3.4, §13.5 ; GDD §10.2, §10.4) : invites dans le monde sans
-- ProximityPrompt : « □ Presser » au-dessus de la cible de PromptController et, après la leçon de
-- fusion, « ○ Prendre » ; jamais deux invites sur la même touche, 2 au plus ; cachées derrière une
-- fenêtre ; plaques par UI/WorldText (taille projetée ≥ 28 px TV aux 3 résolutions), ramenées dans la
-- zone sûre ; anneau de maintien calé sur l'heure du serveur (bol 2 s, dalle 0,6 s, boop qui passe de
-- 2,5 à 5 s), retiré à endsAt + 0,5 s même sans message ; entrées hostiles sans erreur. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local ApiAudit = require("../harness/ApiAudit")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local h = TvAudit.client({
			profile = { onboarding = opts.onboarding or { step = 11, done = true, demoDone = true } },
			console = opts.console,
		})
		local P = TvAudit.mod(h, "UI.Prompt")
		local PC = TvAudit.mod(h, "Controllers.PromptController")
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		local target = nil
		PC.current = function()
			return target
		end
		local function setTarget(t)
			target = t
			P._step()
		end
		return h, P, Clock, setTarget
	end

	local function squishy(over)
		local t = {
			kind = "squishy",
			slot = 1,
			uid = "u3",
			id = 0,
			tile = "",
			ready = true,
			primary = "press",
			secondary = "pickup",
			position = Vector3.new(0, 2, -6),
		}
		for k, v in over or {} do
			t[k] = v
		end
		return t
	end

	local function glyphKey(plate)
		local g = plate:FindFirstChild("Glyph")
		return if g then g:GetAttribute("GlyphKey") else nil
	end

	describe("Prompt › invites", function()
		it(
			"« □ Presser » et « ○ Prendre » ; jamais deux invites sur la même touche, 2 au plus",
			function()
				local h, P, _, setTarget = setup()
				setTarget(nil)
				expect(#P.plates()).toBe(0)
				setTarget(squishy())
				local plates = P.plates()
				expect(#plates).toBe(2)
				expect(plates[1].Text.Text).toBe("Press")
				expect(plates[2].Text.Text).toBe("Pick up")
				expect(glyphKey(plates[1])).toBe("ButtonX")
				expect(glyphKey(plates[2])).toBe("ButtonB")
				-- tailles du GDD : glyphe 64 + mot 40, puis glyphe 48 + mot 32 (px TV)
				local L = h:require("ReplicatedStorage.Shared.Config.Layout")
				expect(plates[1].Text.TextSize).toBe(L.Prompt.MainText)
				expect(plates[1].Glyph.Size.Y.Offset).toBe(L.Prompt.MainGlyph)
				expect(plates[2].Text.TextSize).toBe(L.Prompt.SecondText)
				expect(plates[2].Glyph.Size.Y.Offset).toBe(L.Prompt.SecondGlyph)
				-- en portant : une seule invite ○ Poser
				setTarget(squishy({ primary = "", secondary = "putdown" }))
				plates = P.plates()
				expect(#plates).toBe(1)
				expect(plates[1].Text.Text).toBe("Put down")
				expect(glyphKey(plates[1])).toBe("ButtonB")
				clean(h)
			end
		)

		-- lot B4, étape 5 (D21, INT-B4-KIOSK) : invite du kiosque de Big Plop, « □ Atelier » (une seule plaque)
		it(
			"kiosque : une seule plaque « Workshop » sur □ (console) ou E (clavier), aucune ligne ○",
			function()
				local function kiosk()
					return {
						kind = "kiosk",
						slot = 0,
						uid = "",
						id = 0,
						tile = "",
						ready = true,
						primary = "workshop",
						secondary = "",
						position = Vector3.new(-30, 0, 24),
					}
				end
				local h, P, _, setTarget = setup({ console = true })
				setTarget(kiosk())
				local plates = P.plates()
				expect(#plates).toBe(1)
				expect(plates[1].Text.Text).toBe("Workshop")
				expect(glyphKey(plates[1])).toBe("ButtonX")
				setTarget(nil)
				expect(#P.plates()).toBe(0)
				clean(h)
				local h2, P2, _, setTarget2 = setup({ console = false })
				setTarget2(kiosk())
				expect(#P2.plates()).toBe(1)
				expect(glyphKey(P2.plates()[1])).toBe("E")
				clean(h2)
			end
		)

		-- lot B3, étape 5 (D22, INT-B3-BINOCULARS) : jumelles devant le portail d'un voisin, « □ Regarder »
		it(
			"jumelles : une seule plaque « Look » sur □ (console) ou E (clavier), aucune ligne ○",
			function()
				local function binoculars()
					return {
						kind = "binoculars",
						slot = 2,
						uid = "",
						id = 22,
						tile = "",
						ready = true,
						primary = "binoculars",
						secondary = "",
						position = Vector3.new(30, 0, -170),
					}
				end
				local h, P, _, setTarget = setup({ console = true })
				setTarget(binoculars())
				local plates = P.plates()
				expect(#plates).toBe(1)
				expect(plates[1].Text.Text).toBe("Look")
				expect(glyphKey(plates[1])).toBe("ButtonX")
				setTarget(nil)
				expect(#P.plates()).toBe(0)
				clean(h)
				local h2, P2, _, setTarget2 = setup({ console = false })
				setTarget2(binoculars())
				expect(#P2.plates()).toBe(1)
				expect(glyphKey(P2.plates()[1])).toBe("E")
				clean(h2)
			end
		)

		it("avant la leçon de fusion : seulement « □ Presser »", function()
			local h, P, _, setTarget = setup({ onboarding = { step = 2, done = false, demoDone = false } })
			setTarget(squishy())
			expect(#P.plates()).toBe(1)
			expect(P.plates()[1].Text.Text).toBe("Press")
			clean(h)
		end)

		it("cachées dès qu'une fenêtre est ouverte (menu), revenues à sa fermeture", function()
			local h, P, _, setTarget = setup()
			setTarget(squishy())
			expect(#P.plates()).toBe(2)
			local PC = TvAudit.mod(h, "UI.PanelController")
			PC.toggleMenu()
			P._step()
			expect(#P.plates()).toBe(0)
			TvAudit.tick(h, 0.5)
			PC.closeAll()
			P._step()
			expect(#P.plates()).toBe(2)
			clean(h)
		end)

		it("clavier : « E Presser », « Q Prendre » ; cible en recharge : invite atténuée", function()
			local h, P, _, setTarget = setup({ console = false })
			setTarget(squishy({ ready = false }))
			local plates = P.plates()
			expect(glyphKey(plates[1])).toBe("E")
			expect(glyphKey(plates[2])).toBe("Q")
			expect(plates[1].Text.TextTransparency > 0).toBe(true)
			clean(h)
		end)

		it("taille projetée ≥ 28 px TV aux 3 résolutions ; plaque ramenée dans la zone sûre", function()
			local h, P, _, setTarget = setup()
			local WT = TvAudit.mod(h, "UI.WorldText")
			local L = h:require("ReplicatedStorage.Shared.Config.Layout")
			setTarget(squishy())
			for _, res in L.TestResolutions do
				local vp = Vector2.new(res.X, res.Y)
				TvAudit.setResolution(h, vp)
				P._step()
				for _, gui in P.guis() do
					expect({ res = res.X, ok = WT.projectedPx(gui, vp) >= L.WorldText.MinProjected }).toEqual({
						res = res.X,
						ok = true,
					})
				end
			end
			TvAudit.setResolution(h, Vector2.new(1920, 1080))
			-- cible au bord gauche de l'écran : la plaque est décalée vers la droite (SizeOffset)
			setTarget(squishy({ position = Vector3.new(-24, 0, 0) }))
			local main = P.guis()[1]
			expect(main.SizeOffset.X > 0).toBe(true)
			-- cible bien au milieu : aucun décalage horizontal
			setTarget(squishy({ position = Vector3.new(0, 2, -6) }))
			expect(math.abs(P.guis()[1].SizeOffset.X) < 1e-6).toBe(true)
			clean(h)
		end)
	end)

	describe("Prompt › anneau de maintien", function()
		it(
			"bol : HoldState « feed » en 2 s, anneau autour du glyphe □ ; fin réussie signalée",
			function()
				local h, P, Clock, setTarget = setup()
				setTarget(squishy({ kind = "bowl", primary = "feed", secondary = "" }))
				local ended = {}
				P.HoldEnded:Connect(function(kind, ok)
					table.insert(ended, kind .. ":" .. tostring(ok))
				end)
				h:fireClient(
					"ReplicatedStorage.Remotes.HoldState",
					{ kind = "feed", endsAt = NOW + 2, active = true, tile = "" }
				)
				h:settle(1)
				expect(P.holdProgress()).toBe(0)
				Clock.advance(1)
				P._step()
				expect(math.abs(P.holdProgress() - 0.5) < 1e-6).toBe(true)
				local ring = P.guis()[1].Plate.HoldRing
				expect(ring.Visible).toBe(true)
				h:fireClient(
					"ReplicatedStorage.Remotes.HoldState",
					{ kind = "feed", endsAt = NOW + 2, active = false, tile = "" }
				)
				h:settle(1)
				expect(P.holdProgress()).toBeNil()
				expect(ended).toEqual({ "feed:false" }) -- relâché avant la fin
				clean(h)
			end
		)

		it("dalle : 0,6 s ; sans message de fin, l'anneau part à endsAt + 0,5 s", function()
			local h, P, Clock, setTarget = setup()
			setTarget(squishy({ kind = "pad", primary = "buy", secondary = "", tile = "snack" }))
			local ended = {}
			P.HoldEnded:Connect(function(kind, ok)
				table.insert(ended, kind .. ":" .. tostring(ok))
			end)
			h:fireClient(
				"ReplicatedStorage.Remotes.HoldState",
				{ kind = "tile", endsAt = NOW + 0.6, active = true, tile = "snack" }
			)
			h:settle(1)
			Clock.advance(0.3)
			expect(math.abs(P.holdProgress() - 0.5) < 1e-6).toBe(true)
			Clock.advance(0.7) -- endsAt + 0,4 s : encore dans la grâce de 0,5 s
			P._step()
			expect(P.holdProgress()).toBe(1)
			Clock.advance(0.11)
			P._step()
			expect(P.holdProgress()).toBeNil()
			expect(ended).toEqual({ "tile:true" })
			clean(h)
		end)

		it("boop : l'anneau suit BoopState.endsAt, qui peut passer de 2,5 à 5 s en cours", function()
			local h, P, Clock, setTarget = setup()
			setTarget(squishy({ primary = "boop", secondary = "", slot = 2 }))
			local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
			local ended = {}
			P.HoldEnded:Connect(function(kind, ok)
				table.insert(ended, kind .. ":" .. tostring(ok))
			end)
			WSC.BoopChanged:Fire({ booperId = 1, ownerId = 9, uid = "u3", endsAt = NOW + 2.5, state = "hold" })
			h:settle(1)
			Clock.advance(1.25)
			expect(math.abs(P.holdProgress() - 0.5) < 1e-6).toBe(true)
			WSC.BoopChanged:Fire({ booperId = 1, ownerId = 9, uid = "u3", endsAt = NOW + 5, state = "hold" })
			h:settle(1)
			expect(math.abs(P.holdProgress() - 0.25) < 1e-6).toBe(true)
			-- boop d'un autre joueur : ignoré
			WSC.BoopChanged:Fire({ booperId = 44, ownerId = 9, uid = "u3", endsAt = NOW + 9, state = "done" })
			h:settle(1)
			expect(P.holdProgress() ~= nil).toBe(true)
			WSC.BoopChanged:Fire({ booperId = 1, ownerId = 9, uid = "u3", endsAt = NOW + 5, state = "done" })
			h:settle(1)
			expect(P.holdProgress()).toBeNil()
			expect(ended).toEqual({ "boop:true" })
			clean(h)
		end)

		it("entrées hostiles : aucune erreur, aucun anneau sans fin", function()
			local h, P, Clock, setTarget = setup()
			setTarget({ kind = "squishy", primary = 42, secondary = {}, position = "ici" })
			setTarget({
				kind = "squishy",
				primary = "press",
				secondary = "",
				position = Vector3.new(0 / 0, 0, 0),
			})
			for _, p in
				{
					"x",
					{ kind = "feed", endsAt = 0 / 0, active = true },
					{ kind = "feed", endsAt = math.huge, active = true },
					{ kind = "autre", endsAt = NOW + 1, active = true },
					{ kind = "tile", endsAt = "bientôt", active = true },
				}
			do
				h:fireClient("ReplicatedStorage.Remotes.HoldState", p)
				h:settle(1)
			end
			P.setHold(nil, NOW + 1)
			P.setHold(string.rep("k", 100), NOW + 1)
			Clock.advance(11)
			P._step()
			expect(P.holdProgress()).toBeNil() -- jamais plus de 10 s
			clean(h)
		end)

		it("API Roblox : chaque classe et propriété écrite existe (ApiAudit)", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, P, Clock, setTarget = setup()
				setTarget(squishy())
				h:fireClient(
					"ReplicatedStorage.Remotes.HoldState",
					{ kind = "feed", endsAt = NOW + 2, active = true, tile = "" }
				)
				h:settle(1)
				Clock.advance(1)
				P._step()
				setTarget(squishy({ position = Vector3.new(-24, 0, 0) }))
				h:step(1 / 60, 3)
				clean(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and "" or tostring(err)).toBe("")
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
