--!nocheck
-- Upgrades_Tween (lot B2, étape 2 ; docs/04 §27.8 règle 4 ; GDD v2.0 §10.8) : une animation
-- interrompue (à 0 %, 50 % et 100 % de sa durée) donne la même image finale qu'une animation
-- jouée jusqu'au bout. Animations de l'écran : compteur de l'en-tête (0,4 s), ouverture du panneau
-- (0,22 s), changement d'onglet et de mode. Interruptions : fermeture puis réouverture, changement
-- d'onglet aller-retour, nouvel instantané. Image = textes visibles, positions et tailles des
-- objets visibles de la fenêtre. Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	-- Image de la fenêtre : un texte par objet visible (texte, position, taille), triée
	local function image(c)
		local win = c.PC.window("Upgrades")
		local lines = {}
		for _, d in win:GetDescendants() do
			if d:IsA("GuiObject") then
				local shown = true
				local cur = d
				while cur and cur ~= win do
					if cur:IsA("GuiObject") and not cur.Visible then
						shown = false
						break
					end
					cur = cur.Parent
				end
				if shown then
					local p, sz = d.Position, d.Size
					local text = if d:IsA("TextLabel") then d.Text else ""
					table.insert(
						lines,
						string.format(
							"%s|%s|%d,%d,%d,%d|%d,%d,%d,%d",
							d:GetFullName(),
							text,
							p.X.Scale * 1000,
							p.X.Offset,
							p.Y.Scale * 1000,
							p.Y.Offset,
							sz.X.Scale * 1000,
							sz.X.Offset,
							sz.Y.Scale * 1000,
							sz.Y.Offset
						)
					)
				end
			end
		end
		table.sort(lines)
		local scale = win:FindFirstChild("JuiceScale")
		table.insert(lines, "scale=" .. tostring(if scale then scale.Scale else 1))
		return table.concat(lines, "\n")
	end

	local function settle(c)
		for _ = 1, 30 do
			c.Clock.advance(0.1)
			c.h:step(0.1, 1)
		end
		c.h:settle(2)
	end

	-- Scénario : écran ouvert sur le Ranch, pièces 1 000 puis 5 e9 (compteur de 0,4 s) ; interruption
	-- `cut` à la fraction `at` de la durée ; puis tout s'arrête
	local function run(cut, at)
		local c = S.client({
			snap = S.snap(1, function(p)
				p.coins = 1000
			end),
		})
		S.open(c, "ranch")
		S.patch(
			c,
			S.snap(2, function(p)
				p.coins = 5e9
			end)
		)
		local dt = 0.4 * at
		if dt > 0 then
			c.Clock.advance(dt)
			c.h:step(dt, 1)
		end
		if cut == "close" then
			c.PC.closeAll()
			TvAudit.tick(c.h, 1)
			S.open(c, "ranch")
		elseif cut == "tab" then
			c.Up.setTab("workshop")
			c.h:step(0.01, 1)
			c.Up.setTab("ranch")
		elseif cut == "snapshot" then
			S.patch(
				c,
				S.snap(3, function(p)
					p.coins = 5e9
				end)
			)
		end
		settle(c)
		local out = image(c)
		S.clean(c, expect)
		return out
	end

	describe("Upgrades_Tween › interruption à 0, 50 et 100 %", function()
		it("compteur de l'en-tête : même image finale, quelle que soit l'interruption", function()
			local reference = run(nil, 1)
			expect(#reference > 0).toBe(true)
			for _, cut in { "close", "tab", "snapshot" } do
				for _, at in { 0, 0.5, 1 } do
					local got = run(cut, at)
					if got ~= reference then
						error(string.format("image différente après « %s » à %d %%", cut, at * 100))
					end
				end
			end
		end)

		it("ouverture du panneau interrompue à 0, 50 et 100 % : échelle 1, même image", function()
			local c = S.client({ snap = S.snap(1) })
			S.open(c, "suggested")
			settle(c)
			local reference = image(c)
			for _, at in { 0, 0.5, 1 } do
				c.PC.closeAll()
				settle(c)
				c.PC.open("Upgrades", "suggested")
				local dt = 0.22 * at
				if dt > 0 then
					c.Clock.advance(dt)
					c.h:step(dt, 1)
				end
				c.PC.closeAll()
				c.h:step(0.01, 1)
				S.open(c, "suggested")
				settle(c)
				expect(image(c)).toBe(reference)
			end
			S.clean(c, expect)
		end)
	end)
end
