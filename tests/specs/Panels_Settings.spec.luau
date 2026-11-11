--!nocheck
-- Panels/Settings (paquet client-panels ; GDD §10.3 ; docs/04 §13.6) : interrupteurs (SetSetting),
-- mode Rush / Cozy (SetMode), choix (emote débloquée, langue), Clips caché si ClipsUnavailable,
-- « BOOP RUSH autorisé » pour le propriétaire d'un serveur privé seulement, Diagnostics pour les
-- administrateurs (après le « bonjour »), message du sommeil en bas, 1er interrupteur par défaut.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function setup(opts)
		local h = TvAudit.client(opts or {})
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Settings = TvAudit.mod(h, "UI.Panels.Settings"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function keys(c)
		local out = {}
		for _, item in c.Settings._items() do
			table.insert(out, item.key)
		end
		return out
	end

	-- ligne d'un réglage (amenée à l'écran : la liste est virtualisée)
	local function rowFor(c, key)
		local control = c.Settings._controlFor(key)
		return if control then control.Parent else nil
	end

	describe("Panels/Settings", function()
		it(
			"lignes dans l'ordre du GDD ; 1er interrupteur par défaut ; ✕ envoie SetSetting(clé, valeur)",
			function()
				local c = setup()
				c.PC.open("Settings")
				expect(keys(c)).toEqual({
					"mode",
					"hideName",
					"receiveGifts",
					"clips",
					"reducedMotion",
					"lowGraphics",
					"music",
					"sfx",
					"vibration",
					"emoteLeft",
					"lang",
				})
				local row = rowFor(c, "hideName")
				expect(c.h.game.GuiService.SelectedObject).toBe(row.Toggle)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				local args = TvAudit.sent(c.h, "SetSetting")[1]
				expect(args[1]).toBe("hideName")
				expect(args[2]).toBe(true)
				-- le profil répliqué fait foi : sans DataPatch, l'interrupteur revient à sa valeur
				expect(c.PC.window("Settings").Body.SleepNote.Text).toBe(
					"Your squishies grow even while you sleep"
				)
				clean(c)
			end
		)

		it("mode Rush / Cozy → SetMode ; langue en boucle ; emote verrouillée absente du choix", function()
			local c = setup()
			c.PC.open("Settings")
			TvAudit.tick(c.h, 0.5)
			local mode = rowFor(c, "mode")
			c.h.game.GuiService.SelectedObject = mode.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(TvAudit.sent(c.h, "SetMode")[1][1]).toBe(true) -- Cozy → Rush
			local lang = rowFor(c, "lang")
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = lang.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			local args = TvAudit.sent(c.h, "SetSetting")[1]
			expect(args[1]).toBe("lang")
			expect(args[2]).toBe("en")
			-- seule l'emote Bravo est débloquée : choix refusé sans envoi
			local emote = rowFor(c, "emoteLeft")
			TvAudit.tick(c.h, 0.5)
			c.h.game.GuiService.SelectedObject = emote.Choice
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			expect(#TvAudit.sent(c.h, "SetSetting")).toBe(1)
			clean(c)
		end)

		it(
			"Clips caché sans capture vidéo ; « BOOP RUSH autorisé » pour le propriétaire du serveur privé",
			function()
				local c = setup()
				c.h.localPlayer:SetAttribute("ClipsUnavailable", true)
				c.PC.open("Settings")
				expect(table.find(keys(c), "clips")).toBeNil()
				expect(table.find(keys(c), "allowRush")).toBeNil()
				local c2 = setup({
					before = function(h)
						h.game.PrivateServerOwnerId = 1 -- le joueur local (UserId 1)
					end,
				})
				c2.PC.open("Settings")
				expect(table.find(keys(c2), "allowRush") ~= nil).toBe(true)
				clean(c)
				clean(c2)
			end
		)

		it(
			"Diagnostics : seulement après le « bonjour » ; ✕ l'ouvre par-dessus, ○ revient aux Réglages",
			function()
				local c = setup()
				c.PC.open("Settings")
				expect(c.Settings._controlFor("diagnostics")).toBeNil()
				c.PC.closeAll()
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Settings")
				expect(table.find(keys(c), "diagnostics")).toBeNil() -- bouton fixe, hors de la liste
				local target = c.Settings._controlFor("diagnostics")
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = target
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.PC.current()).toBe("Diagnostics")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Settings")
				expect(c.h.game.GuiService.SelectedObject).toBe(target)
				clean(c)
			end
		)
	end)

	describe("Panels/Settings › v2.0 (lot B3, halo et emotes gagnées)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local S = UpgradeScreen.new(T.Harness)
		local V2 = UpgradeScreen.V2_ALL
		local V13_KEYS = {
			"mode",
			"hideName",
			"receiveGifts",
			"clips",
			"reducedMotion",
			"lowGraphics",
			"music",
			"sfx",
			"vibration",
			"emoteLeft",
			"lang",
		}

		-- profil v2 : Record R 13 (Splorch! au Record R 4, Ola au 13 ; Couronne de confettis au 19 : non),
		-- 2 500 niveaux (Coup de maillet du Carnet), Câlin gagné sur la piste (5e de la rotation)
		local function v2client(opts)
			opts = opts or {}
			local profile = {
				version = 2,
				R = 13,
				bestR = 13,
				ascend = 0,
				stats = { upgradesBought = 2500 },
				weeklyTrack = { won = { 16 } },
				settings = {
					emoteLeft = opts.emote or "bravo",
					haloOn = opts.halo ~= false,
					lang = opts.lang or "auto",
				},
			}
			if opts.edit then
				opts.edit(profile)
			end
			local c = S.client({ profile = profile, ranch = opts.ranch or { HaloOn = true } })
			if opts.flags ~= false then
				S.event(c, opts.flags or V2)
			end
			c.Settings = TvAudit.mod(c.h, "UI.Panels.Settings")
			return c
		end

		local function open(c)
			c.PC.closeAll()
			TvAudit.tick(c.h, 0.5)
			c.PC.open("Settings")
			TvAudit.tick(c.h, 0.5)
		end

		local function pressControl(c, key)
			local control = c.Settings._controlFor(key)
			S.select(c, control)
			Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
			TvAudit.tick(c.h, 0.5)
			return control
		end

		local function withHalo()
			local out = table.clone(V13_KEYS)
			table.insert(out, #out, "haloOn")
			return out
		end

		it(
			"halo : ligne « Montrer mon halo » après l'emote quand MON ranch porte HaloOn ; l'interrupteur suit settings.haloOn ; ✕ → SetSetting(\"haloOn\", false)",
			function()
				local c = v2client()
				open(c)
				expect(keys(c)).toEqual(withHalo())
				local row = rowFor(c, "haloOn")
				expect(row.Title.Text).toBe("Show my halo")
				expect(row.Desc.Text).toBe("Jelly drops that circle your head")
				expect(row.Toggle:GetAttribute("On")).toBe(true)
				pressControl(c, "haloOn")
				local sent = TvAudit.sent(c.h, "SetSetting")
				expect(sent[#sent][1]).toBe("haloOn")
				expect(sent[#sent][2]).toBe(false)
				-- réglage du profil coupé : l'interrupteur suit le profil répliqué
				local c2 = v2client({ halo = false })
				open(c2)
				expect(rowFor(c2, "haloOn").Toggle:GetAttribute("On")).toBe(false)
				S.clean(c, expect)
				S.clean(c2, expect)
			end
		)

		it(
			"halo : pas d'attribut HaloOn, RanchSkins coupé ou profil v1 → aucune ligne, aucun envoi",
			function()
				for _, opts in
					{
						{ ranch = {} },
						{ ranch = { HaloOn = "oui" } },
						{ flags = { RecordR = true, Carnet = true, WeeklyTrack = true } },
						{
							edit = function(p)
								p.version = 1
							end,
						},
					}
				do
					local c = v2client(opts)
					open(c)
					expect(table.find(keys(c), "haloOn")).toBeNil()
					expect(c.Settings._controlFor("haloOn")).toBeNil()
					S.clean(c, expect)
				end
			end
		)

		it(
			"emote de la croix ← : emotes de la v1.3 débloquées puis emotes de la v2.0 possédées, nommées par leur clé ; ✕ fait tourner les choix",
			function()
				local c = v2client({ emote = "hugEmote" })
				open(c)
				local emote
				for _, item in c.Settings._items() do
					if item.key == "emoteLeft" then
						emote = item
					end
				end
				expect(emote.values).toEqual({ "bravo", "splorch", "wave", "hammerTap", "hugEmote" })
				local choice = c.Settings._controlFor("emoteLeft")
				expect(choice.Label.Text).toBe("Hug Emote")
				-- bouton élargi (noms des emotes gagnées : « Couronne de confettis » sur une ligne)
				expect(choice.Size.X.Offset).toBe(440)
				expect(choice.Parent.Title.Size.X.Offset).toBe(-540)
				pressControl(c, "emoteLeft")
				local sent = TvAudit.sent(c.h, "SetSetting")
				expect(sent[#sent][1]).toBe("emoteLeft")
				expect(sent[#sent][2]).toBe("bravo") -- en boucle après la dernière
				-- emote d'une source coupée (Carnet) : plus proposée ; choisie, elle s'affiche « Bravo »
				local c2 = v2client({ emote = "hammerTap", flags = { RecordR = true } })
				open(c2)
				for _, item in c2.Settings._items() do
					if item.key == "emoteLeft" then
						expect(item.values).toEqual({ "bravo", "splorch", "wave" })
					end
				end
				expect(c2.Settings._controlFor("emoteLeft").Label.Text).toBe("Bravo")
				S.clean(c, expect)
				S.clean(c2, expect)
			end
		)

		it(
			"interrupteurs coupés : lignes, choix et intentions de la v1.3 à l'identique (attribut et emotes v2.0 ignorés)",
			function()
				local c = v2client({ flags = false, emote = "wave" })
				open(c)
				expect(keys(c)).toEqual(V13_KEYS)
				for _, item in c.Settings._items() do
					if item.key == "emoteLeft" then
						expect(item.values).toEqual({ "bravo" })
					end
				end
				expect(c.Settings._controlFor("emoteLeft").Label.Text).toBe("Bravo")
				expect(c.Settings._controlFor("emoteLeft").Size.X.Offset).toBe(320)
				expect(rowFor(c, "emoteLeft").Title.Size.X.Offset).toBe(-420)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
			end
		)

		-- INT-B5-SETTINGS (lot B5, étape 5 ; plan B5 D24)
		it(
			"mode photo (lot B5) : ligne « Photo mode » tout en bas, bouton « Cheese! », seulement PhotoMode ouvert ; ✕ ferme le menu et entre en mode photo ; coupé : aucune ligne ni intention",
			function()
				local flags = table.clone(V2)
				flags.PhotoMode = true
				local c = v2client({ flags = flags })
				open(c)
				local list = keys(c)
				expect(list[#list]).toBe("photo")
				expect(#list).toBe(#withHalo() + 1)
				local control = c.Settings._controlFor("photo")
				expect(control.Label.Text).toBe("Cheese!")
				expect(control.Parent.Title.Text).toBe("Photo mode")
				expect(control.Parent.Desc.Text).toBe("Hide the screen and take nice pictures")
				local Cam = TvAudit.mod(c.h, "Controllers.CameraController")
				pressControl(c, "photo")
				expect(Cam.photoOn()).toBe(true)
				expect(c.PC.menuOpen()).toBe(false)
				expect(c.PC.isOpen()).toBe(false)
				expect(#TvAudit.sent(c.h, "SetSetting")).toBe(0)
				Cam.photo(false)
				TvAudit.tick(c.h, 0.5)
				-- interrupteur coupé en direct, écran ouvert : la ligne disparaît
				open(c)
				S.event(c, V2)
				expect(table.find(keys(c), "photo")).toBeNil()
				expect(c.Settings._controlFor("photo")).toBeNil()
				expect(Cam.photo(true)).toBe(false)
				S.clean(c, expect)
			end
		)
	end)
end
