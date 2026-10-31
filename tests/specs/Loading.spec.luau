--!nocheck
-- Loading (paquet world) : écran de chargement autonome de ReplicatedFirst (docs §13.5, GDD §3,
-- §10.3) : affichage immédiat, fermeture sur game:IsLoaded() + attribut local ClientReady,
-- écran « Réessayer » après 20 s (FR/EN), Mouvement réduit, aucune dépendance répliquée.
local fs = require("@lune/fs")
local MockInstance = require("../harness/MockInstance")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local SOURCE = "src/first/Loading.client.luau"

	local function run(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		if opts.locale then
			h.localPlayer.LocaleId = opts.locale
		end
		if opts.reducedMotion then
			h.game.GuiService.ReducedMotionEnabled = true
		end
		local removed = 0
		MockInstance.classMethods.ReplicatedFirst = {
			RemoveDefaultLoadingScreen = function()
				removed += 1
			end,
		}
		local teleports = {}
		MockInstance.classMethods.TeleportService.Teleport = function(_, placeId, player)
			if opts.teleportFails then
				error("HTTP 403 (simulé)")
			end
			table.insert(teleports, { placeId = placeId, player = player })
		end
		if opts.notLoaded then
			h.loaded = false
			MockInstance.classMethods.DataModel.IsLoaded = function()
				return h.loaded
			end
		end
		local rs = h.game.RunService
		local handlersBefore = #rs.RenderStepped._handlers
		h:run("ReplicatedFirst.Loading")
		MockInstance.classMethods.ReplicatedFirst = nil -- pas de fuite vers les autres specs
		local gui = h.localPlayer.PlayerGui:FindFirstChild("Loading")
		return {
			h = h,
			gui = gui,
			removed = removed,
			teleports = teleports,
			handlersBefore = handlersBefore,
			rs = rs,
		}
	end

	local function find(root, name)
		return root:FindFirstChild(name, true)
	end

	describe("Loading › affichage", function()
		it(
			"s'affiche tout de suite : ScreenGui plein écran, Nebby en Frames, 3 points, écran par défaut retiré",
			function()
				local c = run()
				expect(c.gui ~= nil).toBe(true)
				expect(c.gui.ClassName).toBe("ScreenGui")
				expect(c.gui.IgnoreGuiInset).toBe(true)
				expect(c.gui.ResetOnSpawn).toBe(false)
				expect(c.gui.DisplayOrder).toBeGreaterThanOrEqual(100)
				expect(c.removed).toBe(1)
				local nebby = find(c.gui, "Nebby")
				expect(nebby ~= nil).toBe(true)
				expect(find(nebby, "Body").ClassName).toBe("Frame")
				expect(find(nebby, "Eye1") ~= nil and find(nebby, "Eye2") ~= nil).toBe(true)
				local dots = find(c.gui, "Dots")
				expect(#dots:GetChildren()).toBe(3)
				expect(find(c.gui, "Fail").Visible).toBe(false)
				-- aucun texte long à l'écran pendant le chargement
				for _, d in c.gui:GetDescendants() do
					if
						(d.ClassName == "TextLabel" or d.ClassName == "TextButton")
						and d:FindFirstAncestor("Fail") == nil
					then
						error("texte affiché pendant le chargement : " .. d.Name)
					end
				end
				expect(#c.rs.RenderStepped._handlers).toBe(c.handlersBefore + 1)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("le Nebby rebondit (monte, redescend, s'écrase au sol) et les points s'animent", function()
			local c = run()
			local nebby = find(c.gui, "Nebby")
			local dot = find(c.gui, "Dot1")
			local ys, widths, alphas = {}, {}, {}
			for _ = 1, 30 do
				c.h:step(1 / 30, 1)
				table.insert(ys, nebby.Position.Y.Offset)
				table.insert(widths, nebby.Size.X.Offset)
				table.insert(alphas, dot.BackgroundTransparency)
			end
			local minY, maxY = math.min(table.unpack(ys)), math.max(table.unpack(ys))
			expect(maxY - minY).toBeGreaterThan(30)
			expect(math.max(table.unpack(widths))).toBeGreaterThan(120) -- écrasement : plus large au sol
			expect(math.max(table.unpack(alphas)) - math.min(table.unpack(alphas))).toBeGreaterThan(0.2)
		end)

		it("Mouvement réduit : aucun rebond, seulement des fondus", function()
			local c = run({ reducedMotion = true })
			local nebby = find(c.gui, "Nebby")
			local dot = find(c.gui, "Dot2")
			local y0, size0 = nebby.Position.Y.Offset, nebby.Size.X.Offset
			local alphas = {}
			for _ = 1, 20 do
				c.h:step(1 / 20, 1)
				expect(nebby.Position.Y.Offset).toBe(y0)
				expect(nebby.Size.X.Offset).toBe(size0)
				table.insert(alphas, dot.BackgroundTransparency)
			end
			expect(math.max(table.unpack(alphas)) - math.min(table.unpack(alphas))).toBeGreaterThan(0.2)
		end)
	end)

	describe("Loading › fermeture", function()
		it(
			"reste affiché tant que ClientReady n'est pas posé, puis fondu de 0,3 s et destruction",
			function()
				local c = run()
				c.h:step(1 / 10, 50) -- 5 s
				expect(c.gui.Parent ~= nil).toBe(true)
				local root = find(c.gui, "Root")
				expect(root.GroupTransparency).toBe(0)
				local tweensBefore = c.h.stats.tweens
				c.h.localPlayer:SetAttribute("ClientReady", true)
				c.h:settle(1)
				expect(c.h.stats.tweens).toBeGreaterThan(tweensBefore)
				expect(root.GroupTransparency).toBe(1)
				c.h:settle(3)
				expect(c.h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
				expect(#c.rs.RenderStepped._handlers).toBe(c.handlersBefore)
				c.h:step(1 / 60, 3) -- plus rien ne tourne
				expect(#c.h.errors).toBe(0)
			end
		)

		it("ClientReady déjà posé au lancement : fermeture immédiate", function()
			local h = Harness.new({ mode = "client" })
			h.localPlayer:SetAttribute("ClientReady", true)
			h:run("ReplicatedFirst.Loading")
			h:settle(3)
			expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
		end)

		it("ClientReady sans game:IsLoaded() : attend game.Loaded", function()
			local c = run({ notLoaded = true })
			c.h.localPlayer:SetAttribute("ClientReady", true)
			c.h:step(1 / 10, 10)
			c.h:settle(2)
			expect(c.gui.Parent ~= nil).toBe(true)
			c.h.loaded = true
			c.h.game.Loaded:Fire()
			c.h:settle(3)
			expect(c.h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
			MockInstance.classMethods.DataModel.IsLoaded = function()
				return true
			end
		end)

		it("ClientReady = false ou valeur d'un autre type : ne ferme pas", function()
			local c = run()
			c.h.localPlayer:SetAttribute("ClientReady", false)
			c.h:settle(2)
			c.h.localPlayer:SetAttribute("ClientReady", "true")
			c.h:settle(2)
			c.h.localPlayer:SetAttribute("ClientReady", 1)
			c.h:step(1 / 10, 5)
			expect(c.gui.Parent ~= nil).toBe(true)
			expect(find(c.gui, "Root").GroupTransparency).toBe(0)
		end)
	end)

	describe("Loading › échec (après 20 s)", function()
		it(
			"« Ton Nid se réveille… » en français selon LocaleId, bouton Réessayer → Teleport(PlaceId), anti-répétition",
			function()
				local c = run({ locale = "fr-fr" })
				c.h:step(1, 19)
				expect(find(c.gui, "Fail").Visible).toBe(false)
				c.h:step(1, 2)
				local fail = find(c.gui, "Fail")
				expect(fail.Visible).toBe(true)
				expect(find(fail, "Message").Text).toBe("Ton Nid se réveille…")
				local button = find(fail, "RetryButton")
				expect(button.Text).toBe("Réessayer")
				expect(button.Size.Y.Offset).toBeGreaterThanOrEqual(44) -- cible tactile
				button.Activated:Fire()
				button.Activated:Fire()
				button.Activated:Fire()
				c.h:settle(1)
				expect(#c.teleports).toBe(1)
				expect(c.teleports[1].placeId).toBe(c.h.game.PlaceId)
				expect(c.teleports[1].player).toBe(c.h.localPlayer)
				c.h:step(1, 6)
				button.Activated:Fire()
				c.h:settle(1)
				expect(#c.teleports).toBe(2)
				-- le profil finit par arriver : l'écran se ferme quand même
				c.h.localPlayer:SetAttribute("ClientReady", true)
				c.h:settle(3)
				expect(c.h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
			end
		)

		it("anglais par défaut ; une téléportation impossible avertit sans erreur", function()
			local c = run({ locale = "de-de", teleportFails = true })
			c.h:step(2, 11)
			local fail = find(c.gui, "Fail")
			expect(fail.Visible).toBe(true)
			expect(find(fail, "Message").Text).toBe("Your Nest is waking up…")
			expect(find(fail, "RetryButton").Text).toBe("Retry")
			find(fail, "RetryButton").Activated:Fire()
			c.h:settle(1)
			expect(#c.h:warnings()).toBe(1)
			expect(#c.h.errors).toBe(0)
		end)

		it("dt absurdes (NaN, négatif, énorme) ignorés : pas d'écran d'échec prématuré", function()
			local c = run()
			for _, dt in { 0 / 0, -100, 1e9, math.huge } do
				c.h.game.RunService.RenderStepped:Fire(dt)
			end
			c.h:settle(1)
			expect(find(c.gui, "Fail").Visible).toBe(false)
		end)
	end)

	describe("Loading › autonomie et textes", function()
		it("aucun require ni accès à ReplicatedStorage (s'exécute avant la réplication)", function()
			local source = string.gsub(fs.readFile(SOURCE), "%-%-[^\n]*", "") -- code seul, sans commentaires
			expect(string.find(source, "require(", 1, true)).toBeNil()
			expect(string.find(source, "ReplicatedStorage", 1, true)).toBeNil()
			expect(string.find(source, 'WaitForChild("PlayerGui")', 1, true)).toBeNil() -- attentes bornées
		end)

		it("les textes embarqués sont ceux de loading.wake / loading.retry (EN et FR)", function()
			local h = Harness.new({ mode = "client" })
			local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
			for _, case in { { "en-us", "en" }, { "fr-ca", "fr" } } do
				local c = run({ locale = case[1] })
				c.h:step(1, 21)
				local fail = find(c.gui, "Fail")
				expect(find(fail, "Message").Text).toBe(Strings[case[2]]["loading.wake"])
				expect(find(fail, "RetryButton").Text).toBe(Strings[case[2]]["loading.retry"])
			end
			expect(h ~= nil).toBe(true)
		end)
	end)
end
