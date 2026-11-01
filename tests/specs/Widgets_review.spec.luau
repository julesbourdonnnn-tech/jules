--!nocheck
-- Panels/Widgets (paquet client-panels, module d'aide) : défauts trouvés à la relecture, chacun
-- reproduit avant sa correction (GDD §9.2, §10.6 ; docs/04 §13.6). Zéro trace.
--   * UiSeen(écran) marqué « vu » même quand le débit du client le retenait : trois panneaux ouverts
--     d'affilée perdaient le troisième pour toute la session (UiSeen("objectives") = étape 10 de
--     l'accueil) ;
--   * rebond de bout de liste pendant un défilement : le rebond revenait à la position intermédiaire
--     du tween de défilement (liste décalée d'une fraction de rangée jusqu'au défilement suivant) ;
--   * liste virtualisée : son cadre coupe (ClipsDescendants) au ras des cases, si bien que le curseur
--     de sélection (6 px blancs + liseré, 4 px de débord, grossissement 1,05) était coupé sur les cases
--     du bord ;
--   * bouton à maintenir grisé : ✕ jouait deux refus (son Error deux fois), l'un au début du maintien,
--     l'autre à Activated.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local Layout = require("../harness/Layout")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function pens(n)
		local sq = {}
		for i = 1, n do
			sq["u" .. i] = TvAudit.squishy(((i - 1) % 26) + 1, { z = 100 * i })
		end
		return sq
	end

	local function seenScreens(h)
		local out = {}
		for _, args in TvAudit.sent(h, "UiSeen") do
			table.insert(out, args[1])
		end
		table.sort(out)
		return out
	end

	describe("Widgets › UiSeen", function()
		it(
			"trois panneaux ouverts d'affilée : chaque écran finit par partir une fois (débit respecté)",
			function()
				local h = TvAudit.client({})
				local PC = TvAudit.mod(h, "UI.PanelController")
				PC.open("Squishydex")
				PC.open("Objectives")
				PC.open("Leaderboards")
				-- le seau du client (2 par seconde) a retenu le troisième : il part dès que le débit le permet
				for _ = 1, 6 do
					TvAudit.tick(h, 0.5)
				end
				expect(seenScreens(h)).toEqual({ "dex", "leaderboards", "objectives" })
				-- jamais deux fois dans la session
				PC.open("Squishydex")
				PC.open("Objectives")
				PC.open("Leaderboards")
				for _ = 1, 4 do
					TvAudit.tick(h, 0.5)
				end
				expect(seenScreens(h)).toEqual({ "dex", "leaderboards", "objectives" })
				clean(h)
			end
		)
	end)

	describe("Widgets › rebond de bout de liste", function()
		it("rebond pendant le tween de défilement : la liste revient à sa position de repos", function()
			local h = TvAudit.client({ profile = { squishies = pens(30) } })
			local PC = TvAudit.mod(h, "UI.PanelController")
			local Widgets = TvAudit.mod(h, "UI.Panels.Widgets")
			local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
			PC.open("Ranch")
			TvAudit.tick(h, 0.5)
			-- dernière case : la grille défile jusqu'en bas
			local cell = Ranch._cellFor("u1")
			h.game.GuiService.SelectedObject = cell
			h:settle(2)
			local holder = cell.Parent.Parent
			expect(holder.Name).toBe("Holder")
			local rest = holder.Position
			expect(rest.Y.Offset < 0).toBe(true)
			-- tween de défilement pas encore fini (position intermédiaire), puis ↓ au bout : rebond
			holder.Position = rest + UDim2.fromOffset(0, 60)
			Widgets.bump(cell, "Down")
			h:settle(3)
			TvAudit.tick(h, 0.5)
			expect(holder.Position.Y.Offset).toBe(rest.Y.Offset)
			expect(holder.Position.X.Offset).toBe(rest.X.Offset)
			clean(h)
		end)
	end)

	describe("Widgets › liste virtualisée", function()
		it(
			"le curseur de sélection d'une case du bord n'est jamais coupé par le cadre de la liste",
			function()
				local h = TvAudit.client({ profile = { squishies = pens(30) } })
				local PC = TvAudit.mod(h, "UI.PanelController")
				PC.open("Ranch")
				TvAudit.tick(h, 0.5)
				local grid = PC.window("Ranch").Body.Page_grid.Grid
				-- débord du curseur (UI/Root : 4 px + trait de 6 px + liseré de 2 px) et grossissement 1,05
				local OUT = 12
				local bad = {}
				for _, name in { "Cell1", "Cell6" } do
					local cell = nil
					for _, r in grid.Holder:GetChildren() do
						local cand = r:FindFirstChild(name)
						if r.Visible and cand and cand:GetAttribute("RowIndex") == 1 then
							cell = cand
						end
					end
					-- mesure au repos (sans le grossissement), puis place du curseur : débord de 12 px et 5 % de
					-- la case (UIScale autour de l'ancrage en haut à gauche : tout le grossissement d'un côté)
					h.game.GuiService.SelectedObject = nil
					h:settle(2)
					Layout.apply(h)
					local r = Layout.rect(cell)
					local frame = Layout.rect(grid)
					local grow = r.w * 0.05
					local ax, ay = r.x - OUT - grow, r.y - OUT - grow
					local bx, by = r.x + r.w + OUT + grow, r.y + r.h + OUT + grow
					if ax < frame.x - 0.5 or bx > frame.x + frame.w + 0.5 or ay < frame.y - 0.5 then
						table.insert(
							bad,
							string.format(
								"%s : curseur (%d, %d)-(%d, %d) hors du cadre (%d, %d, %d × %d)",
								name,
								ax,
								ay,
								bx,
								by,
								frame.x,
								frame.y,
								frame.w,
								frame.h
							)
						)
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
				-- la liste reste dans le panneau et dans la zone sûre
				expect(table.concat(TvAudit.outsideSafe(h), "\n")).toBe("")
				clean(h)
			end
		)
	end)

	describe("Widgets › appels protégés", function()
		it(
			"erreur qui n'est pas un stub : visible (fil à part, une fois par clé), l'interface continue",
			function()
				local h = TvAudit.client({})
				local Widgets = TvAudit.mod(h, "UI.Panels.Widgets")
				local v = Widgets.safe("test.boom", 7, function()
					error("boum")
				end)
				expect(v).toBe(7)
				h:settle(2)
				expect(#h.errors).toBe(1)
				expect(h.errors[1]).toContain("[panels] test.boom")
				expect(Widgets.safe("test.boom", 8, function()
					error("boum")
				end)).toBe(8)
				h:settle(2)
				expect(#h.errors).toBe(1)
				-- stub d'un autre paquet (« TODO(…) ») : le repli, sans bruit
				expect(Widgets.safe("test.todo", 9, function()
					error("TODO(client-hud): Cards.pending")
				end)).toBe(9)
				h:settle(2)
				expect(#h.errors).toBe(1)
				table.clear(h.errors)
				clean(h)
			end
		)

		it("panneau dont build échoue : jamais ouvert à moitié, l'erreur est visible", function()
			local h = TvAudit.client({})
			local PC = TvAudit.mod(h, "UI.PanelController")
			local LB = TvAudit.mod(h, "UI.Panels.Leaderboards")
			LB.build = function()
				error("build cassé")
			end
			PC.open("Leaderboards")
			h:settle(2)
			expect(PC.current()).toBeNil()
			expect(#h.errors).toBe(1)
			expect(h.errors[1]).toContain("Leaderboards")
			TvAudit.tick(h, 0.5)
			PC.open("Leaderboards")
			h:settle(2)
			expect(PC.current()).toBeNil()
			expect(#h.errors).toBe(1)
			table.clear(h.errors)
			-- les autres panneaux marchent
			PC.open("Ranch")
			expect(PC.current()).toBe("Ranch")
			clean(h)
		end)
	end)

	describe("Widgets › bouton à maintenir grisé", function()
		it("✕ sur Vendre sans sélection : un seul refus (un son Error)", function()
			local h = TvAudit.client({ profile = { squishies = pens(3) } })
			local PC = TvAudit.mod(h, "UI.PanelController")
			local Ranch = TvAudit.mod(h, "UI.Panels.Ranch")
			local sounds = {}
			local Audio = TvAudit.mod(h, "Controllers.AudioController")
			local play = Audio.play
			Audio.play = function(name, ...)
				table.insert(sounds, name)
				return play(name, ...)
			end
			PC.open("Ranch", "sell")
			TvAudit.tick(h, 0.5)
			local sell = Ranch._button("sell")
			h.game.GuiService.SelectedObject = sell
			h:settle(1)
			table.clear(sounds)
			Gamepad.press(h, Enum.KeyCode.ButtonA)
			h:step(1 / 60, 2)
			Gamepad.release(h, Enum.KeyCode.ButtonA)
			h:settle(2)
			local errors = 0
			for _, s in sounds do
				if s == "Error" then
					errors += 1
				end
			end
			expect(errors).toBe(1)
			expect(#TvAudit.sent(h, "Sell")).toBe(0)
			clean(h)
		end)
	end)
end
