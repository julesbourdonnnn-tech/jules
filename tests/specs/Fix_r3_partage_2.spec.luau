--!nocheck
-- Correctifs r3-partage-2 :
--   * Loading : « Réessayer » n'apparaît pas tant que le chargement avance encore (attribut répliqué
--     ProfileLoading posé par DataService pendant ses essais, ou réplication initiale pas finie) :
--     message rassurant seul, puis Réessayer RETRY_GRACE s après la fin de ces attentes, au plus
--     tard à RETRY_MAX_WAIT s (sinon : boucle de téléportations sur un profil verrouillé)
--   * Loading : à la manette, une fois « Réessayer » affiché, ○ / △ (InputController) ou toute autre
--     perte de sélection n'en privent plus l'enfant : la sélection revient sur Réessayer
--   * Config/Events : Starborn réellement limités (GDD §4.15.5, §8.1.6) : première apparition de
--     chaque espèce vedette, puis seulement lors d'un Encore annoncé
--   * Config/Sounds : format des IDs (vide = désactivé, sinon exactement rbxassetid://<nombre>)
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
				expect(fail.Message.Text).toBe("Ton Nid se réveille…")
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
		-- de profil (chargement qui traîne) : les liaisons d'InputController sont actives
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
			"○ puis △ (InputController) : la sélection revient sur Réessayer ; ✕ téléporte",
			function()
				local h, gui = consoleClient()
				h:step(1, 21)
				h:settle(2)
				local button = gui:FindFirstChild("RetryButton", true)
				expect(button.Visible).toBe(true)
				expect(Gamepad.selected(h)).toBe(button)
				Gamepad.tap(h, Enum.KeyCode.ButtonB) -- ○
				h:settle(2)
				expect(Gamepad.selected(h)).toBe(button)
				Gamepad.tap(h, Enum.KeyCode.ButtonY) -- △
				h:settle(2)
				expect(Gamepad.selected(h)).toBe(button)
				Gamepad.tap(h, Enum.KeyCode.ButtonB)
				Gamepad.tap(h, Enum.KeyCode.ButtonY)
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

	describe("Fix r3-partage-2 › Starborn réellement limités (GDD §4.15.5, §8.1.6)", function()
		local function load()
			local h = Harness.new({ mode = "client" })
			return h:require("ReplicatedStorage.Shared.Config.Events"),
				h:require("ReplicatedStorage.Shared.Logic.EventClock")
		end

		it("rotation vedette : 12 espèces distinctes (une première apparition chacune)", function()
			local Events = load()
			local list = Events.Rotations.FeaturedSpecies
			local seen = {}
			for _, s in list do
				expect(seen[s]).toBeNil()
				seen[s] = true
			end
			expect(#list).toBe(12)
		end)

		it("semaine w de la 1re apparition : Starborn ; semaine w + 12 (même espèce) : non", function()
			local Events, EventClock = load()
			local SF = Events.Starfall
			local n = #Events.Rotations.FeaturedSpecies
			local species = {}
			for k = 0, n - 1 do
				local w = SF.LaunchWeek + k
				local s = EventClock.featuredSpecies(w)
				expect(EventClock.featuredSpecies(w + n)).toBe(s)
				expect({ week = w, starborn = Events.starbornAllowed(w) }).toEqual({
					week = w,
					starborn = true,
				})
				expect({ week = w + n, starborn = Events.starbornAllowed(w + n) }).toEqual({
					week = w + n,
					starborn = false,
				})
				species[s] = (species[s] or 0) + 1
			end
			for _, count in species do
				expect(count).toBe(1)
			end
			expect(Events.starbornAllowed(SF.LaunchWeek - 1)).toBe(false)
		end)

		it("sans Encore : sur 3 ans, chaque espèce vedette n'a qu'UNE semaine Starborn", function()
			local Events, EventClock = load()
			local SF = Events.Starfall
			local count, total = {}, 0
			for w = SF.LaunchWeek - 10, SF.LaunchWeek + 3 * 52 do
				if Events.starbornAllowed(w) and not SF.Encores[w] then
					local s = EventClock.featuredSpecies(w)
					count[s] = (count[s] or 0) + 1
					total += 1
				end
			end
			expect(total).toBe(#Events.Rotations.FeaturedSpecies)
			for s, c in count do
				expect({ species = s, weeks = c }).toEqual({ species = s, weeks = 1 })
			end
		end)

		it(
			"Encore annoncé : la semaine listée rouvre le Starborn de son espèce vedette, elle seule",
			function()
				local Events = load()
				local SF = Events.Starfall
				local w = SF.LaunchWeek + 52
				expect(Events.starbornAllowed(w)).toBe(false)
				SF.Encores[w] = true
				expect(Events.starbornAllowed(w)).toBe(true)
				expect(Events.starbornAllowed(w + 1)).toBe(false)
				expect(Events.starbornAllowed(w + 0.5)).toBe(true) -- semaine fractionnaire : arrondie en dessous
				SF.Encores[w] = nil
				expect(Events.starbornAllowed(w)).toBe(false)
			end
		)

		it("calendrier bien formé ; entrées absurdes → pas de Starborn", function()
			local Events, EventClock = load()
			local SF = Events.Starfall
			expect(type(SF.LaunchWeek)).toBe("number")
			expect(SF.LaunchWeek % 1).toBe(0)
			-- la semaine de lancement a bien un show (samedi 16:00 UTC)
			local show =
				EventClock.nextStarfall(SF.LaunchWeek * Events.Calendar.Week + Events.Calendar.WeekEpoch)
			expect(EventClock.week(show.startsAt)).toBe(SF.LaunchWeek)
			for week, flag in SF.Encores do
				expect(type(week) == "number" and week % 1 == 0 and week >= SF.LaunchWeek).toBe(true)
				expect(flag).toBe(true)
			end
			for _, bad in { 0 / 0, math.huge, -math.huge, "2970", nil, {} } do
				expect(Events.starbornAllowed(bad)).toBe(false)
			end
		end)

		it("texte du cadeau sans Starborn (semaines ordinaires) en anglais et en français", function()
			local h = Harness.new({ mode = "client" })
			local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")
			for _, lang in { "en", "fr" } do
				local text = Strings[lang]["feedback.starfallGiftPlain"]
				expect(type(text)).toBe("string")
				expect(string.find(text, "{species}", 1, true) ~= nil).toBe(true)
				expect(string.find(text, "Starborn", 1, true)).toBeNil()
			end
		end)
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
				for _, key in
					{
						"Pop",
						"Coin",
						"Catch",
						"Bank",
						"LevelUp",
						"Reward",
						"Error",
						"Whoosh",
						"Supernova",
						"Music",
					}
				do
					expect({ key = key, declared = Sounds[key] ~= nil }).toEqual({
						key = key,
						declared = true,
					})
				end
			end
		)
	end)
end
