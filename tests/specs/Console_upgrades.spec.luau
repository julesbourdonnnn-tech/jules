--!nocheck
-- Console_upgrades (lot B2, étape 3 ; docs/04 §27.8 règle 14, §27.10 ; GDD v2.0 §10.1, §10.6, §10.7.8,
-- §10.8 ; N11, N19) : l'écran Améliorations à la manette, après les appuis.
--   * « après achat, Max, rafraîchissement : aucun élément appuyé » : aucun maintien en cours, l'anneau
--     caché, aucune ligne ni carte grisée (le maintien coupé d'une ligne « Il manque », MAX ou « En
--     cours » ne change pas son aspect), aucune mise à l'échelle restée (JuiceScale), et rien qui
--     reste « en cours » après la réponse ;
--   * « le rectangle du cadre de focus est dans le rectangle de découpe de chaque ancêtre qui découpe,
--     pour chaque ligne et chaque carte, dans chaque état » (Prêt, Il manque, MAX, cadenas, plafond de
--     la boucle, En cours, Réessaie) : le cadre est dessiné à l'intérieur de l'élément (N11), l'élément
--     sélectionné est entier dans son cadre de défilement et dans le panneau, sans grossissement ;
--   * interrupteur coupé : aucun écran, aucune intention v2.0.
-- Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")
local Layout = require("../harness/Layout")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function inside(a, b): boolean
		return a.x >= b.x - 0.5
			and a.y >= b.y - 0.5
			and a.x + a.w <= b.x + b.w + 0.5
			and a.y + a.h <= b.y + b.h + 0.5
	end

	-- Ancêtres qui découpent (même règle que le moteur et que FocusGuard.clippers)
	local function clippers(obj)
		local out = {}
		local cur = obj.Parent
		while cur ~= nil and not cur:IsA("LayerCollector") do
			if
				cur:IsA("GuiObject")
				and (cur.ClipsDescendants or cur:IsA("ScrollingFrame") or cur:IsA("CanvasGroup"))
			then
				table.insert(out, cur)
			end
			cur = cur.Parent
		end
		return out
	end

	-- Cartes et lignes montrées de l'écran
	local function elements(c)
		local out = {}
		for i = 1, 3 do
			table.insert(out, { tab = "suggested", obj = c.Up._card(i) })
		end
		for _, tab in { "ranch", "helpers", "workshop" } do
			for _, id in c.Up._shown(tab) do
				table.insert(out, { tab = tab, obj = c.Up._row(id) })
			end
		end
		return out
	end

	-- Aucun élément appuyé (règle 14)
	local function nothingPressed(c, where)
		local bad = {}
		local ring = c.Up._ring()
		if ring and ring.Visible then
			table.insert(bad, where .. " : anneau du maintien visible")
		end
		for _, e in elements(c) do
			local obj = e.obj
			local hold = c.Up._hold(obj)
			if hold and hold.holding() then
				table.insert(bad, where .. " : maintien en cours sur " .. obj.Name)
			end
			if math.abs(obj.BackgroundTransparency) > 1e-6 then
				table.insert(bad, where .. " : " .. obj.Name .. " grisé")
			end
			local scale = obj:FindFirstChild("JuiceScale")
			if scale and math.abs(scale.Scale - 1) > 1e-3 then
				table.insert(bad, where .. " : " .. obj.Name .. " à l'échelle " .. scale.Scale)
			end
		end
		return bad
	end

	local function rich(p)
		p.tiles.decor = 2
		p.tiles.gloves = 5
		p.coins = 1e30
	end

	describe("Console_upgrades › aucun élément appuyé (règle 14)", function()
		it("interrupteur coupé : aucun écran, aucune intention v2.0", function()
			local c = S.client({})
			c.PC.open("Upgrades")
			S.run(c, 0.5)
			expect(c.PC.window("Upgrades")).toBeNil()
			S.noV2Intent(c, expect)
			S.clean(c, expect)
		end)

		it("après achat, Max, rafraîchissement : aucun élément appuyé", function()
			local c = S.client({ snap = S.snap(1, rich) })
			S.open(c, "ranch")
			expect(nothingPressed(c, "ouverture")).toEqual({})
			-- pendant un maintien : l'anneau est là (la règle porte sur l'APRÈS)
			S.select(c, c.Up._row("decor"))
			local Gamepad = require("../harness/Gamepad")
			local roblox = require("@lune/roblox")
			Gamepad.press(c.h, roblox.Enum.KeyCode.ButtonA)
			S.run(c, 0.3)
			expect(c.Up._ring().Visible).toBe(true)
			expect(c.Up._ring().Parent).toBe(c.Up._row("decor"))
			S.run(c, 0.4)
			Gamepad.release(c.h, roblox.Enum.KeyCode.ButtonA)
			S.run(c, 0.1)
			-- après l'achat (« En cours ») puis la réponse
			expect(nothingPressed(c, "achat envoyé")).toEqual({})
			local sent = S.sent(c, "BuyUpgrade")
			S.answer(c, sent[1], {
				to = 3,
				spent = 1,
				snap = S.snap(2, function(p)
					rich(p)
					p.tiles.decor = 3
				end),
			})
			expect(nothingPressed(c, "réponse")).toEqual({})
			-- Max : mode changé au bouton (✕), puis achat
			c.Up._playerMode()
			c.Up._playerMode()
			expect(c.Up.mode()).toBe(0)
			S.run(c, 0.5)
			S.hold(c, c.Up._row("gloves"), 0.7)
			expect(nothingPressed(c, "Max")).toEqual({})
			sent = S.sent(c, "BuyUpgrade")
			expect(sent[#sent][2]).toBe(0)
			S.answer(c, sent[#sent], {
				to = 40,
				spent = 1,
				snap = S.snap(3, function(p)
					rich(p)
					p.tiles.decor = 3
					p.tiles.gloves = 40
				end),
			})
			S.run(c, 1.6)
			expect(nothingPressed(c, "Max, réponse")).toEqual({})
			-- la ligne passée à MAX garde le focus, rien n'est appuyé
			expect(S.selected(c)).toBe(c.Up._row("gloves"))
			expect(c.Up._row("gloves"):GetAttribute("State")).toBe("max")
			-- rafraîchissement (langue changée) et changement d'onglet
			TvAudit.setLanguage(c.h, "en")
			S.run(c, 0.5)
			expect(nothingPressed(c, "rafraîchissement")).toEqual({})
			c.Up.setTab("workshop")
			S.run(c, 0.5)
			expect(nothingPressed(c, "onglet")).toEqual({})
			-- relâché trop tôt : l'anneau se vide, rien ne reste appuyé
			S.hold(c, c.Up._row("decor"), 0.3)
			expect(nothingPressed(c, "relâché trop tôt")).toEqual({})
			expect(c.Up._pending()).toEqual({})
			S.clean(c, expect)
		end)
	end)

	describe("Console_upgrades › cadre de focus dans la découpe (règle 14, N11)", function()
		-- états : Prêt / MAX / cadenas (profil riche), Il manque (aucune pièce), plafond de la boucle
		-- (r = 3 après une Ascension), En cours et Réessaie (achats sans réponse)
		local profiles = {
			{ name = "riche", edit = rich },
			{
				name = "pauvre",
				edit = function(p)
					p.coins = 0
					p.confetti = 0
				end,
			},
			{
				name = "boucle",
				edit = function(p)
					p.tiles.snack = 12
					p.tiles.star = 0
					p.R = 3
					p.bestR = 15
					p.ascend = 1
					p.coins = 1e30
				end,
			},
			{
				name = "début",
				edit = function(p)
					p.R = 0
					p.bestR = 0
					p.coins = 120
				end,
			},
		}
		for _, viewport in { { 1920, 1080 }, { 1280, 720 } } do
			it(
				"chaque ligne et chaque carte, dans chaque état, à " .. viewport[1] .. "×" .. viewport[2],
				function()
					local roblox = require("@lune/roblox")
					local states = {}
					local bad = {}
					local checked = 0
					for _, prof in profiles do
						local c = S.client({
							snap = S.snap(1, prof.edit),
							viewport = roblox.Vector2.new(viewport[1], viewport[2]),
						})
						S.open(c, "suggested")
						local function check(label)
							for _, e in elements(c) do
								local obj = e.obj
								if obj.Visible then
									if c.Up.currentTab() ~= e.tab then
										c.Up.setTab(e.tab)
										S.run(c, 0.1)
									end
									c.h.game.GuiService.SelectedObject = obj
									c.h:settle(1)
									S.run(c, 0.1)
									Layout.apply(c.h)
									states[obj:GetAttribute("State") or "?"] = true
									checked += 1
									local r = Layout.rect(obj)
									for _, clip in clippers(obj) do
										local cr = Layout.rect(clip)
										if cr and not inside(r, cr) then
											table.insert(
												bad,
												string.format(
													"%s/%s : %s (%s) tranché par %s",
													prof.name,
													label,
													obj.Name,
													tostring(obj:GetAttribute("State")),
													clip.Name
												)
											)
										end
									end
									local scale = obj:FindFirstChild("JuiceScale")
									if scale and math.abs(scale.Scale - 1) > 1e-3 then
										table.insert(bad, prof.name .. " : " .. obj.Name .. " grossi")
									end
								end
							end
						end
						check("repos")
						if prof.name == "riche" then
							-- En cours (Décorations), puis Réessaie (3 s sans réponse)
							c.Up.setTab("ranch")
							S.run(c, 0.2)
							S.hold(c, c.Up._row("decor"), 0.7)
							check("en cours")
							S.run(c, 3.2)
							check("réessaie")
						end
						S.clean(c, expect)
					end
					for _, st in { "ready", "need", "max", "locked", "loopCap", "busy", "retry" } do
						expect({ st = st, seen = states[st] == true }).toEqual({ st = st, seen = true })
					end
					expect(checked > 100).toBe(true)
					expect(table.concat(bad, "\n")).toBe("")
				end
			)
		end
	end)
end
