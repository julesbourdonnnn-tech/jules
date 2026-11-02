--!nocheck
-- Revue adversariale du paquet client-hud : chaque défaut trouvé à la revue est reproduit ici avant
-- sa correction (docs/04 §17, §18.2). Zéro trace.
--   1. Carte du choix : un glyphe montré dit toujours vrai (✕ seulement sur le bouton sélectionné ;
--      « ✕ Je joue au BOOP RUSH » avec « Je reste tranquille » sélectionné faisait choisir Cozy).
--   2. WorldText : une étiquette dont l'objet porteur est détruit (ou détruite directement) est rendue
--      à la réserve (aucune fuite d'étiquettes vivantes sur une longue session).
--   3. ScreenFX : deux demandes vers la même créature ne font jamais deux flèches.
--   4. Messages : un texte trop long est coupé sur un caractère entier (UTF-8 valide, accents).
--   5. Mode photo : ni bannière ni message à l'écran.
--   6. △ / M avec une carte rouverte à la souris (sans menu) : la carte se ferme, le menu ne s'ouvre pas.
--   7. Indicateur Bondir et anneau : durées lues dans Config (Balance.Leap.Cooldown), jamais en dur.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		opts = opts or {}
		local profile = opts.profile or {}
		profile.onboarding = profile.onboarding or { step = 11, done = true, demoDone = true }
		local h = TvAudit.client({ profile = profile, now = opts.now })
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		return h, Clock
	end

	-- monde simulé pour le calme de la carte du choix : ranch 1, rien de porté
	local function calmWorld(h)
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local ranch = { slot = 1, userId = 1, mode = "cozy", carry = "", ride = "", saddle = 0 }
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return if slot == 1 then ranch else nil
		end
		WSC.creatures = function()
			return {}
		end
		h:moveTo(h.localPlayer, WorldLayout.toWorld(1, Vector3.new(0, 3, 36)))
	end

	local function glyphKey(button)
		local g = button:FindFirstChild("Glyph")
		if g == nil or not g.Visible then
			return ""
		end
		return g:GetAttribute("GlyphKey") or ""
	end

	describe("Revue client-hud › carte du choix", function()
		it(
			"✕ n'est montré que sur le bouton sélectionné ; ○ reste sur « Je reste tranquille »",
			function()
				local h, Clock = setup()
				calmWorld(h)
				local C = TvAudit.mod(h, "UI.Cards")
				h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
				h:settle(1)
				C._step()
				Clock.advance(1.6)
				C._step()
				expect(C.current().kind).toBe("mode")
				local rush, cozy = C.buttons()[1], C.buttons()[2]
				expect(h.game.GuiService.SelectedObject).toBe(cozy)
				-- « Je reste tranquille » sélectionné : ✕ le choisirait ; aucun ✕ sur « BOOP RUSH »
				expect(glyphKey(rush)).toBe("")
				expect(glyphKey(cozy)).toBe("ButtonB")
				-- chaque glyphe ✕ montré est sur le bouton que ✕ active
				h.game.GuiService.SelectedObject = rush
				h:settle(1)
				C._step()
				expect(glyphKey(rush)).toBe("ButtonA")
				expect(glyphKey(cozy)).toBe("ButtonB")
				Clock.advance(0.7)
				C._step()
				Gamepad.tap(h, Enum.KeyCode.ButtonA)
				expect(TvAudit.sent(h, "SetMode")[1][1]).toBe(true)
				clean(h)
			end
		)
	end)

	describe("Revue client-hud › WorldText", function()
		it(
			"objet porteur détruit, ou étiquette détruite : rendue, jamais une étiquette vivante perdue",
			function()
				local h = setup()
				local WT = TvAudit.mod(h, "UI.WorldText")
				local before = WT.stats().live
				local parts = {}
				for i = 1, 5 do
					local part = h.globals.Instance.new("Part")
					part.Anchored = true
					part.Position = Vector3.new(i * 4, 2, 0)
					part.Parent = h.game.Workspace
					local gui = WT.create(part, { kind = "plus", maxDistance = 40 })
					WT.setText(gui, "+12")
					table.insert(parts, part)
				end
				expect(WT.stats().live).toBe(before + 5)
				for _, part in parts do
					part:Destroy() -- l'appelant oublie release (VFX, dalle retirée, ranch remis à zéro)
				end
				h:settle(1)
				expect(WT.stats().live).toBe(before)
				-- l'étiquette elle-même détruite (Destroy au lieu de release) : plus comptée vivante
				local part = h.globals.Instance.new("Part")
				part.Anchored = true
				part.Parent = h.game.Workspace
				local gui = WT.create(part, { kind = "text", maxDistance = 20 })
				gui:Destroy()
				h:settle(1)
				expect(WT.stats().live).toBe(before)
				-- une étiquette reprise de la réserve sert un nouvel objet : l'ancien ne la retire plus
				local a = h.globals.Instance.new("Part")
				a.Parent = h.game.Workspace
				local g1 = WT.create(a, { kind = "glyph", maxDistance = 20 })
				WT.release(g1)
				local b = h.globals.Instance.new("Part")
				b.Parent = h.game.Workspace
				local g2 = WT.create(b, { kind = "glyph", maxDistance = 20 })
				a:Destroy()
				h:settle(1)
				expect(g2.Adornee).toBe(b)
				expect(WT.stats().live).toBe(before + 1)
				WT.release(g2)
				clean(h)
			end
		)
	end)

	describe("Revue client-hud › ScreenFX", function()
		it(
			"même créature demandée deux fois (flèche manuelle + automatique) : une seule flèche",
			function()
				local h = setup()
				h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
				local FX = TvAudit.mod(h, "UI.ScreenFX")
				FX.arrow("chase:7", Vector3.new(0, 3, 60), "booped")
				FX.arrow("owner:u7", Vector3.new(0.4, 3, 60.2), "booped") -- même créature, un autre appelant
				FX.arrow("wild", Vector3.new(40, 3, 60), "wild")
				FX._step()
				local kinds = {}
				for _, a in FX.arrows() do
					table.insert(kinds, a.kind)
				end
				table.sort(kinds)
				expect(kinds).toEqual({ "booped", "wild" })
				clean(h)
			end
		)
	end)

	describe("Revue client-hud › messages et mode photo", function()
		it("texte trop long coupé sur un caractère entier : UTF-8 toujours valide", function()
			local h = setup()
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			M._reset()
			local shown = {}
			local Toast = TvAudit.mod(h, "UI.Toast")
			Toast.show = function(text)
				table.insert(shown, text)
			end
			-- 159 octets ASCII puis « é » (2 octets) : une coupe à 160 octets casserait le caractère
			M.push(string.rep("a", 159) .. "éééé", "info")
			expect(#shown).toBe(1)
			expect(utf8.len(shown[1]) ~= nil).toBe(true)
			expect(#shown[1] <= 160).toBe(true)
			clean(h)
		end)

		it("mode photo : bannières et messages retenus, puis rendus à la fin", function()
			local h, Clock = setup()
			local B = TvAudit.mod(h, "UI.Banners")
			local M = TvAudit.mod(h, "UI.Hud.Messages")
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "photo", data = { on = true } })
			h:settle(1)
			B.show({ kind = "rushStart", args = {}, personal = true, priority = 1 })
			B._step()
			expect(B.current()).toBeNil()
			M.push("Hello", "info")
			expect(M.pending()).toBe(1)
			h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "photo", data = { on = false } })
			h:settle(1)
			B._step()
			expect(B.current() ~= nil).toBe(true)
			Clock.advance(3.1)
			B._step()
			M.step(Clock.now())
			expect(M.pending()).toBe(0)
			clean(h)
		end)
	end)

	describe("Revue client-hud › △ au-dessus d'une carte rouverte", function()
		it(
			"carte rouverte à la souris, menu fermé : M / △ referment la carte, le menu ne s'ouvre pas",
			function()
				local h = setup()
				local C = TvAudit.mod(h, "UI.Cards")
				local FG = TvAudit.mod(h, "UI.FocusGuard")
				local PC = TvAudit.mod(h, "UI.PanelController")
				h:fireClient(
					"ReplicatedStorage.Remotes.Celebrate",
					{ kind = "sleepy", data = { minutes = 60 } }
				)
				h:settle(1)
				local id = C.current().id
				C.open(id) -- clic de souris sur la carte affichée
				expect(FG.isOpen("card:" .. id)).toBe(true)
				TvAudit.tick(h, 0.5)
				Gamepad.tap(h, Enum.KeyCode.ButtonY)
				h:settle(1)
				expect(FG.anyOpen()).toBe(false)
				expect(PC.menuOpen()).toBe(false)
				expect(#C.pending()).toBe(1) -- rangée dans « ! »
				clean(h)
			end
		)
	end)

	describe("Revue client-hud › valeurs de Config", function()
		it("balayage de l'indicateur Bondir calé sur Balance.Leap.Cooldown", function()
			local h = setup()
			local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
			local CC = TvAudit.mod(h, "Controllers.ChaseController")
			local HUD = TvAudit.mod(h, "UI.HUD")
			local old = Balance.Leap.Cooldown
			Balance.Leap.Cooldown = 8 -- réglage changé dans Config : le HUD suit
			CC.cooldownLeft = function()
				return 4
			end
			HUD._refresh()
			local sweep = HUD.element("leap"):FindFirstChild("Sweep", true)
			Balance.Leap.Cooldown = old
			expect(math.abs(sweep.Size.Y.Scale - 0.5) < 1e-6).toBe(true)
			clean(h)
		end)
	end)
end
