--!nocheck
-- Correctifs r3-partage-2 de Comet Conga :
--   * Loading : « Réessayer » n'apparaît pas tant que le chargement avance encore (attribut répliqué
--     ProfileLoading posé par DataService pendant ses essais, ou réplication initiale pas finie) :
--     message rassurant seul, puis Réessayer RETRY_GRACE s après la fin de ces attentes, au plus
--     tard à RETRY_MAX_WAIT s (sinon : boucle de téléportations sur un profil verrouillé)
--   * Loading : à la manette, une fois « Réessayer » affiché, le bouton retour ou le bouton de menu
--     du jeu (sélection effacée, ou posée sur un objet caché derrière) ou toute autre perte de
--     sélection n'en privent plus l'enfant : la sélection revient sur Réessayer
--   * Config/Sounds : format des IDs (vide = désactivé, sinon exactement rbxassetid://<nombre>)
-- Adaptations : ○ / △ d'InputController (Comet Conga) simulés par leurs effets (sélection effacée,
-- sélection posée sur un bouton du HUD derrière l'écran) ; partie « Starborn » retirée (gameplay) ;
-- liste des sons attendus = les 8 sons d'interface du socle.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Gamepad = require("../harness/Gamepad")
local ApiAudit = require("../harness/ApiAudit")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000

	local function runLoading(h)
		MockInstance.classMethods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() end }
		h:run("ReplicatedFirst.Loading")
		MockInstance.classMethods.ReplicatedFirst = nil -- pas de fuite vers les autres specs
		return h.localPlayer.PlayerGui:FindFirstChild("Loading")
	end

	local function recordTeleports()
		local teleports = {}
		MockInstance.classMethods.TeleportService.Teleport = function(_, placeId, player)
			table.insert(teleports, { placeId = placeId, player = player })
		end
		return teleports
	end

	-- Avance de `seconds` images d'une seconde ; retourne true si « Réessayer » a été visible
	local function stepWatching(h, button, seconds)
		local seen = false
		for _ = 1, seconds do
			h:step(1, 1)
			if button.Visible and button:FindFirstAncestor("Fail").Visible then
				seen = true
			end
		end
		return seen
	end

	describe("Fix r3-partage-2 › Loading : chargement encore en cours", function()
		it(
			"verrou d'un autre serveur (ProfileLoading) : message rassurant seul, Réessayer 10 s après la fin des essais",
			function()
				local h = Harness.new({ mode = "client" })
				h.localPlayer.LocaleId = "fr-fr"
				h.localPlayer:SetAttribute("ProfileLoading", 1)
				local gui = runLoading(h)
				local fail = gui:FindFirstChild("Fail", true)
				local button = fail.RetryButton
				h:step(1, 21)
				expect(fail.Visible).toBe(true)
				expect(fail.Message.Text).toBe("Presque prêt…")
				expect(button.Visible).toBe(false)
				-- DataService réessaie toutes les 5 s (essais 2 à 5) : toujours pas de Réessayer
				for attempt = 2, 5 do
					h.localPlayer:SetAttribute("ProfileLoading", attempt)
					expect(stepWatching(h, button, 5)).toBe(false)
				end
				-- verrou pris à l'essai 6 : l'attribut disparaît, l'instantané est en route
				h.localPlayer:SetAttribute("ProfileLoading", nil)
				expect(stepWatching(h, button, 9)).toBe(false)
				h:step(1, 2)
				expect(button.Visible).toBe(true)
				expect(#h.errors).toBe(0)
			end
		)

		it(
			"profil arrivé après ≈ 26 s de verrou : l'écran se ferme sans jamais montrer Réessayer",
			function()
				local h = Harness.new({ mode = "client" })
				h.localPlayer:SetAttribute("ProfileLoading", 1)
				local teleports = recordTeleports()
				local gui = runLoading(h)
				local button = gui:FindFirstChild("RetryButton", true)
				local seen = false
				for attempt = 1, 5 do
					h.localPlayer:SetAttribute("ProfileLoading", attempt)
					seen = stepWatching(h, button, 5) or seen
				end
				h.localPlayer:SetAttribute("ProfileLoading", nil)
				seen = stepWatching(h, button, 1) or seen
				h.localPlayer:SetAttribute("ClientReady", true)
				h:settle(3)
				expect(seen).toBe(false)
				expect(#teleports).toBe(0)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
			end
		)

		it("attribut resté posé (serveur figé) : Réessayer au plus tard à 60 s", function()
			local h = Harness.new({ mode = "client" })
			h.localPlayer:SetAttribute("ProfileLoading", 3)
			local gui = runLoading(h)
			local button = gui:FindFirstChild("RetryButton", true)
			expect(stepWatching(h, button, 59)).toBe(false)
			h:step(1, 2)
			expect(button.Visible).toBe(true)
		end)

		it("valeur d'attribut absurde (texte, 0, NaN) : ignorée, Réessayer à 20 s comme avant", function()
			for _, value in { "1", 0, 0 / 0, false } do
				local h = Harness.new({ mode = "client" })
				h.localPlayer:SetAttribute("ProfileLoading", value)
				local gui = runLoading(h)
				local button = gui:FindFirstChild("RetryButton", true)
				h:step(1, 21)
				expect(button.Visible).toBe(true)
			end
		end)

		it(
			"réplication initiale lente (game:IsLoaded() faux) : pas de Réessayer tant qu'elle avance",
			function()
				local h = Harness.new({ mode = "client" })
				h.loaded = false
				MockInstance.classMethods.DataModel.IsLoaded = function()
					return h.loaded
				end
				local gui = runLoading(h)
				local fail = gui:FindFirstChild("Fail", true)
				local button = fail.RetryButton
				expect(stepWatching(h, button, 30)).toBe(false)
				expect(fail.Visible).toBe(true) -- message rassurant
				h.loaded = true
				h.game.Loaded:Fire()
				expect(stepWatching(h, button, 9)).toBe(false)
				h:step(1, 2)
				expect(button.Visible).toBe(true)
			end
		)

		it(
			"console : rien de sélectionné tant que Réessayer est caché, puis Réessayer sélectionné (✕)",
			function()
				local h = Harness.new({ mode = "client", console = true })
				h.localPlayer:SetAttribute("ProfileLoading", 2)
				local gui = runLoading(h)
				local fail = gui:FindFirstChild("Fail", true)
				h:step(1, 21)
				expect(fail.Visible).toBe(true)
				expect(Gamepad.selected(h)).toBeNil()
				expect(fail:FindFirstChild("PadGlyph")).toBeNil()
				h.localPlayer:SetAttribute("ProfileLoading", nil)
				h:step(1, 11)
				expect(fail.RetryButton.Visible).toBe(true)
				expect(Gamepad.selected(h)).toBe(fail.RetryButton)
				expect(fail:FindFirstChild("PadGlyph") ~= nil).toBe(true)
			end
		)
	end)

	describe("Fix r3-partage-2 › Loading : Réessayer reste atteignable à la manette", function()
		-- Client console complet (Main.client) démarré derrière l'écran de chargement, sans instantané
		-- de profil (chargement qui traîne)
		local function consoleClient()
			local h = Harness.new({ mode = "client", console = true })
			h.localPlayer.LocaleId = "en-us"
			h:createRemotes()
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(T0)
			local gui = runLoading(h)
			h:boot()
			h:step(1 / 30, 10)
			h:settle(3)
			return h, gui
		end

		it(
			"○ puis △ du jeu (sélection effacée, puis posée derrière l'écran) : rendue à Réessayer ; ✕ téléporte",
			function()
				local h, gui = consoleClient()
				h:step(1, 21)
				h:settle(2)
				local button = gui:FindFirstChild("RetryButton", true)
				expect(button.Visible).toBe(true)
				expect(Gamepad.selected(h)).toBe(button)
				-- rail de menus du jeu, caché derrière l'écran de chargement
				local hud = MockInstance.new("ScreenGui")
				hud.Name = "HUD"
				local rail = MockInstance.new("TextButton")
				rail.Name = "RailButton"
				rail.Parent = hud
				hud.Parent = h.localPlayer.PlayerGui
				local function back() -- ○ : le jeu efface la sélection
					Gamepad.tap(h, Enum.KeyCode.ButtonB)
					h.game.GuiService.SelectedObject = nil
				end
				local function menu() -- △ : le jeu sélectionne son rail de menus
					Gamepad.tap(h, Enum.KeyCode.ButtonY)
					h.game.GuiService.SelectedObject = rail
				end
				back()
				h:settle(2)
				expect(Gamepad.selected(h)).toBe(button)
				menu()
				h:settle(2)
				expect(Gamepad.selected(h)).toBe(button)
				back()
				menu()
				h:settle(2)
				h:step(1 / 30, 2)
				expect(Gamepad.selected(h)).toBe(button)
				Gamepad.tap(h, Enum.KeyCode.DPadDown) -- nulle part où aller : reste sur Réessayer
				expect(Gamepad.selected(h)).toBe(button)
				local teleports = recordTeleports()
				Gamepad.tap(h, Enum.KeyCode.ButtonA) -- ✕
				expect(#teleports).toBe(1)
				expect(teleports[1].placeId).toBe(h.game.PlaceId)
				-- le profil finit par arriver : l'écran se ferme et rend la main au stick
				h.localPlayer:SetAttribute("ClientReady", true)
				h:settle(3)
				h:step(1 / 30, 2)
				h:settle(3)
				expect(h.localPlayer.PlayerGui:FindFirstChild("Loading")).toBeNil()
				expect(Gamepad.selected(h)).toBeNil()
				expect(#h.errors).toBe(0)
			end
		)

		it(
			"sélection volée par un objet hors de l'écran (bouton du HUD derrière) : rendue à Réessayer",
			function()
				local h = Harness.new({ mode = "client", console = true })
				local gui = runLoading(h)
				h:step(1, 21)
				local button = gui:FindFirstChild("RetryButton", true)
				expect(Gamepad.selected(h)).toBe(button)
				local other = MockInstance.new("ScreenGui")
				other.Name = "HUD"
				local behind = MockInstance.new("TextButton")
				behind.Parent = other
				other.Parent = h.localPlayer.PlayerGui
				h.game.GuiService.SelectedObject = behind
				h:settle(2)
				expect(Gamepad.selected(h)).toBe(button)
			end
		)

		it(
			"PC à la souris (manette branchée mais pas en main) : la sélection effacée n'est pas forcée",
			function()
				local h = Harness.new({ mode = "client" })
				h.game.UserInputService.GamepadEnabled = true
				ApiAudit.start() -- GetLastInputType, SelectedObject, Visible : vraies API Roblox
				local ok, err = pcall(function()
					local gui = runLoading(h)
					h:step(1, 21)
					local button = gui:FindFirstChild("RetryButton", true)
					expect(Gamepad.selected(h)).toBe(button)
					h.game.GuiService.SelectedObject = nil
					h:settle(2)
					expect(Gamepad.selected(h)).toBeNil()
					-- la manette reprise en main : Réessayer sélectionné (comportement existant)
					Gamepad.tap(h, Enum.KeyCode.DPadDown)
					expect(Gamepad.selected(h)).toBe(button)
					-- puis ○ (aucune liaison ici) qui efface la sélection : rendue à Réessayer
					h.game.GuiService.SelectedObject = nil
					h:settle(2)
					expect(Gamepad.selected(h)).toBe(button)
				end)
				local issues = ApiAudit.stop()
				expect(ok and true or err).toBe(true)
				expect(table.concat(issues, "\n")).toBe("")
				expect(#h.errors).toBe(0)
			end
		)
	end)

	describe("Fix r3-partage-2 › Config/Sounds", function()
		it(
			"chaque son : ID vide (désactivé) ou exactement rbxassetid://<nombre> ; volume ]0 ; 1] ; hauteur > 0",
			function()
				local h = Harness.new({ mode = "client" })
				local Sounds = h:require("ReplicatedStorage.Shared.Config.Sounds")
				local n = 0
				for name, def in Sounds do
					n += 1
					local okId = def.id == "" or string.match(def.id, "^rbxassetid://%d+$") ~= nil
					expect({ name = name, id = def.id, ok = okId }).toEqual({
						name = name,
						id = def.id,
						ok = true,
					})
					expect(type(def.volume) == "number" and def.volume > 0 and def.volume <= 1).toBe(true)
					expect(
						def.pitch == nil or (type(def.pitch) == "number" and def.pitch > 0 and def.pitch < 4)
					).toBe(true)
				end
				expect(n).toBeGreaterThan(0)
				for _, key in { "Click", "Pop", "Error", "Whoosh", "Select", "Back", "Tab", "Bump" } do
					expect({ key = key, declared = Sounds[key] ~= nil }).toEqual({
						key = key,
						declared = true,
					})
				end
			end
		)
	end)
end
