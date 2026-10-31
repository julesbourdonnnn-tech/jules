--!nocheck
-- Correctifs QA tour 1, paquet client-world :
--   * GDD §4.14 : pendant la course, un petit « ? » doré PERSISTANT flotte au-dessus de chaque Nebby
--     de la file locale dont l'entrée d'Atlas (espèce × forme) est encore inconnue ; il disparaît à
--     l'enregistrement (atlas mis à jour) et à l'encaissement ; jamais sur la file des autres.
--   * GDD §8.3, §9.4 : une Glow Party achetée déclenche, chez TOUS les joueurs, une bannière dans le
--     ciel « Glow Party offerte par Mira ! » au-dessus de la Balise (≈ 5 s) et des confettis dorés
--     autour de soi ; les autres envoient des cœurs « Merci » (ping 6) qui volent vers l'acheteur.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local PUFFKIN = 1 -- espèce 1, forme 0
	local SPECIES2 = 2 -- espèce 2, forme 0
	local PRISMPAW = 17 -- espèce 17, forme 0 (Rare)

	local function setup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			g = h.globals,
			Clock = Clock,
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
		}
		if opts.settings then
			c.Prefs._onSettings(opts.settings)
		end
		c.State.Init()
		c.WSC.Init()
		c.CR.Init()
		c.VFX.Init()
		c.WSC.Start()
		c.CR.Start()
		c.VFX.Start()
		return c
	end

	local function frames(c, n, dt)
		for _ = 1, n do
			c.Clock.advance(dt or 0.05)
			c.h:step(dt or 0.05, 1)
		end
	end

	local function fire(c, remote, ...)
		c.h:fireClient(REMOTES .. remote, ...)
	end

	local function V(x, y, z)
		return Vector3.new(x, y, z)
	end

	local function events(extra)
		local ev = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 2 }
		for k, v in extra or {} do
			ev[k] = v
		end
		return ev
	end

	local function snapshot(c, lines, extra)
		local snap = {
			serverTime = T0,
			tick = 1,
			lines = lines or {},
			paths = c.PathCodec.encode(1, {}),
			wild = {},
			events = events(),
			crews = { crews = {} },
		}
		for k, v in extra or {} do
			snap[k] = v
		end
		fire(c, "WorldSnapshot", snap)
	end

	-- Mots d'Atlas avec les entrées (espèce, forme 0) des codes donnés déjà enregistrées
	local function atlasWith(c, known)
		local words = { 0, 0, 0, 0, 0, 0, 0 }
		for _, code in known do
			local s, f = c.Nebbies.unpack(code)
			c.Nebbies.setBit(words, c.Nebbies.atlasIndex(s, f))
		end
		return words
	end

	-- Le joueur local marche : son Trail local nourrit le rendu de sa file
	local function walk(c, steps)
		for i = 0, steps do
			c.h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(V(20 + i, 3, 0))
			frames(c, 1)
		end
	end

	-- BillboardGuis « ? » visibles dans le dossier des files
	local function shownMarkers(c)
		local out = {}
		for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
			if child.ClassName == "BillboardGui" and child.Name == "NewEntry" and child.Enabled then
				table.insert(out, child)
			end
		end
		return out
	end

	local function markerOver(c, slot, index)
		local model = c.CR.nodeModel(slot, index)
		if model == nil then
			return nil
		end
		for _, gui in shownMarkers(c) do
			if gui.Adornee ~= nil and gui.Adornee.Parent == model then
				return gui
			end
		end
		return nil
	end

	local function localLine(c, codes, ver)
		c.h.localPlayer:SetAttribute("Slot", 2)
		snapshot(c, { { slot = 2, userId = 1, ver = ver or 1, codes = codes } })
		walk(c, 30)
	end

	local function unknownCodes(n)
		local out = {}
		for i = 1, n do
			out[i] = PUFFKIN
		end
		return out
	end

	describe("Fix client-world r1 › « ? » doré persistant (GDD §4.14)", function()
		it(
			"marque chaque Nebby de la file locale dont l'entrée d'Atlas est inconnue, et seulement eux",
			function()
				local c = setup()
				fire(c, "DataSnapshot", { atlas = atlasWith(c, { PUFFKIN }) })
				localLine(c, { PUFFKIN, PRISMPAW, PUFFKIN, PRISMPAW, SPECIES2 })
				expect(c.CR.newEntryMarkers()).toEqual({ 2, 4, 5 })
				expect(#shownMarkers(c)).toBe(3)
				for _, i in { 2, 4, 5 } do
					local gui = markerOver(c, 2, i)
					expect(gui ~= nil).toBe(true)
					expect(gui.Mark.Text).toBe("?")
					expect(gui.StudsOffset.Y).toBeGreaterThan(0)
				end
				expect(markerOver(c, 2, 1)).toBeNil()
				expect(markerOver(c, 2, 3)).toBeNil()
				-- toujours là plusieurs secondes plus tard (pas un texte éphémère)
				frames(c, 60, 0.1)
				expect(c.CR.newEntryMarkers()).toEqual({ 2, 4, 5 })
				expect(#c.h:warnings()).toBe(0)
			end
		)

		it(
			"nouvelle capture inconnue : un « ? » apparaît ; entrée enregistrée (atlas) : il disparaît",
			function()
				local c = setup()
				fire(c, "DataSnapshot", { atlas = atlasWith(c, { PUFFKIN }) })
				localLine(c, { PUFFKIN })
				expect(c.CR.newEntryMarkers()).toEqual({})
				fire(c, "LineEvent", { { op = "add", slot = 2, ver = 2, codes = { PRISMPAW }, ids = { 0 } } })
				frames(c, 3)
				expect(c.CR.newEntryMarkers()).toEqual({ 2 })
				-- récompense reçue : l'entrée est enregistrée sans encaissement
				fire(c, "DataPatch", { atlas = atlasWith(c, { PUFFKIN, PRISMPAW }) })
				frames(c, 1)
				expect(c.CR.newEntryMarkers()).toEqual({})
				expect(#shownMarkers(c)).toBe(0)
			end
		)

		it("encaissement : tous les « ? » sont retirés avec la parade", function()
			local c = setup()
			fire(c, "DataSnapshot", { atlas = atlasWith(c, {}) })
			localLine(c, { PUFFKIN, PRISMPAW, SPECIES2 })
			expect(c.CR.newEntryMarkers()).toEqual({ 1, 2, 3 })
			fire(c, "LineEvent", {
				{
					op = "bank",
					slot = 2,
					ver = 2,
					count = 3,
					glow = 30,
					bonus = 1.08,
					atBeacon = false,
					newEntries = 3,
				},
			})
			frames(c, 1)
			expect(c.CR.newEntryMarkers()).toEqual({})
			expect(#shownMarkers(c)).toBe(0)
		end)

		it("jamais sur la file d'un autre joueur ; rien tant que l'Atlas n'est pas chargé", function()
			local c = setup()
			c.h.localPlayer:SetAttribute("Slot", 2)
			-- Atlas pas encore reçu : aucune marque
			snapshot(c, { { slot = 2, userId = 1, ver = 1, codes = { PRISMPAW } } })
			walk(c, 20)
			expect(c.CR.newEntryMarkers()).toEqual({})
			fire(c, "DataSnapshot", { atlas = atlasWith(c, {}) })
			frames(c, 1)
			expect(c.CR.newEntryMarkers()).toEqual({ 1 })
			-- un autre joueur avec des entrées inconnues tout près : aucune marque sur sa file
			local other = c.h:addPlayer({ userId = 50, name = "P50" })
			other:SetAttribute("Slot", 5)
			other.Character.HumanoidRootPart.CFrame = CFrame.new(V(45, 3, 4))
			local points = {}
			for i = 1, 30 do
				points[i] = V(15 + i, 3, 4)
			end
			fire(c, "WorldSnapshot", {
				serverTime = T0,
				tick = 2,
				lines = {
					{ slot = 2, userId = 1, ver = 1, codes = { PRISMPAW } },
					{ slot = 5, userId = 50, ver = 1, codes = { PRISMPAW, SPECIES2 } },
				},
				paths = c.PathCodec.encode(2, c.PathCodec.split(5, 1, points)),
				wild = {},
				events = events(),
				crews = { crews = {} },
			})
			frames(c, 4)
			expect(c.CR.nodeModel(5, 1) ~= nil).toBe(true)
			expect(markerOver(c, 5, 1)).toBeNil()
			expect(markerOver(c, 5, 2)).toBeNil()
			expect(#shownMarkers(c)).toBe(1)
		end)

		it("réserve bornée (12, 6 en Graphismes légers), aucune pièce ajoutée au budget", function()
			local c = setup()
			fire(c, "DataSnapshot", { atlas = atlasWith(c, {}) })
			localLine(c, unknownCodes(20))
			expect(#c.CR.newEntryMarkers()).toBe(12)
			expect(c.CR.newEntryMarkers()[1]).toBe(1) -- priorité à la tête de file
			local count = 0
			for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
				if child.Name == "NewEntry" then
					count += 1
					expect(child.ClassName).toBe("BillboardGui") -- pas une pièce : budget §12.8 intact
				end
			end
			expect(count).toBe(12)
			c.Prefs._onSettings({ lowGraphics = true })
			frames(c, 4)
			expect(#c.CR.newEntryMarkers()).toBe(6)
			expect(#shownMarkers(c)).toBe(6)
			-- toujours 12 BillboardGuis au plus (réserve réutilisée)
			c.Prefs._onSettings({ lowGraphics = false })
			frames(c, 4)
			count = 0
			for _, child in c.h.workspace.ClientWorld.Lines:GetChildren() do
				if child.Name == "NewEntry" then
					count += 1
				end
			end
			expect(count).toBe(12)
		end)

		it("Mouvement réduit : marques fixes (pas de flottement)", function()
			local c = setup({ settings = { reducedMotion = true } })
			fire(c, "DataSnapshot", { atlas = atlasWith(c, {}) })
			localLine(c, { PRISMPAW })
			local gui = markerOver(c, 2, 1)
			expect(gui ~= nil).toBe(true)
			local y = gui.StudsOffset.Y
			frames(c, 7, 0.13)
			expect(gui.StudsOffset.Y).toBe(y)
			expect(gui.Mark.UIScale.Scale).toBe(1)
		end)

		it("cycle de vie : réapparition conservée, plus de slot local → marques retirées", function()
			local c = setup()
			fire(c, "DataSnapshot", { atlas = atlasWith(c, {}) })
			localLine(c, { PRISMPAW, SPECIES2 })
			expect(c.CR.newEntryMarkers()).toEqual({ 1, 2 })
			c.h:respawn(c.h.localPlayer)
			walk(c, 10)
			expect(c.CR.newEntryMarkers()).toEqual({ 1, 2 })
			-- slot perdu (départ du Nid) puis file effacée : rien ne reste accroché
			c.h.localPlayer:SetAttribute("Slot", 0)
			fire(c, "LineEvent", { { op = "clear", slot = 2, ver = 2, reason = "leave", loose = {} } })
			fire(c, "LineEvent", { { op = "owner", slot = 2, ver = 0, userId = 0 } })
			frames(c, 4)
			expect(c.CR.newEntryMarkers()).toEqual({})
			expect(#shownMarkers(c)).toBe(0)
			expect(#c.h:warnings()).toBe(0)
		end)
	end)

	describe("Fix client-world r1 › Glow Party sociale (GDD §8.3, §9.4)", function()
		local function skyGui(c)
			local anchor = c.h.workspace.ClientWorld.VFX:FindFirstChild("VFXAnchor")
			local attachment = anchor and anchor:FindFirstChild("GlowPartySky")
			return attachment and attachment:FindFirstChild("GlowPartySky")
		end

		local function skyShown(c)
			local gui = skyGui(c)
			return gui ~= nil and gui.Enabled == true
		end

		local function boost(endsAt, buyerId, source)
			return events({
				serverBoost = { endsAt = endsAt, source = source or "glowParty", buyerId = buyerId },
			})
		end

		it(
			"achat : bannière « Glow Party by Mira! » au-dessus de la Balise et confettis dorés chez tous",
			function()
				local c = setup()
				local mira = c.h:addPlayer({ userId = 7, name = "Mira" })
				mira.DisplayName = "Mira"
				snapshot(c)
				frames(c, 2)
				expect(skyShown(c)).toBe(false)
				local before = c.VFX.particlesAlive()
				fire(c, "EventState", boost(T0 + 600, 7))
				expect(skyShown(c)).toBe(true)
				local gui = skyGui(c)
				expect(gui.Ribbon.Text.Text).toBe("Glow Party by Mira!")
				-- dans le ciel, au-dessus de l'étoile de la Balise
				-- (attachement de l'ancre VFX posée à l'origine : Position = point monde)
				local attachment = gui.Parent
				expect(attachment.Position.Y).toBeGreaterThan(40)
				expect(math.abs(attachment.Position.X) < 1 and math.abs(attachment.Position.Z) < 1).toBe(true)
				expect(c.VFX.particlesAlive()).toBeGreaterThan(before)
				-- vagues de confettis dorés suivantes
				local afterFirst = c.VFX.particlesAlive()
				frames(c, 10, 0.05)
				expect(c.VFX.particlesAlive()).toBeGreaterThan(afterFirst)
				-- tenue ≈ 5 s puis disparition
				frames(c, 30, 0.1)
				expect(skyShown(c)).toBe(true)
				frames(c, 30, 0.1)
				expect(skyShown(c)).toBe(false)
				expect(#c.h:warnings()).toBe(0)
			end
		)

		it(
			"pas de rejeu : arrivée pendant une Glow Party, état renvoyé ; nouvel achat → rejoué",
			function()
				local c = setup()
				local mira = c.h:addPlayer({ userId = 7, name = "Mira" })
				mira.DisplayName = "Mira"
				-- arrivée alors qu'une Glow Party est déjà en cours : pas de fête rejouée
				snapshot(c, nil, { events = boost(T0 + 300, 7) })
				frames(c, 2)
				expect(skyShown(c)).toBe(false)
				-- même état renvoyé (instantané redemandé) : rien
				fire(c, "EventState", boost(T0 + 300, 7))
				frames(c, 1)
				expect(skyShown(c)).toBe(false)
				-- Mira en rachète une : la fin recule de 10 min → fête
				fire(c, "EventState", boost(T0 + 900, 7))
				expect(skyShown(c)).toBe(true)
				frames(c, 70, 0.1)
				expect(skyShown(c)).toBe(false)
				-- Nuit d'Or (boost gratuit) : pas de bannière de Glow Party
				fire(c, "EventState", boost(T0 + 1500, nil, "goldenNight"))
				frames(c, 1)
				expect(skyShown(c)).toBe(false)
				-- acheteur parti : bannière sans nom
				fire(c, "EventState", boost(T0 + 2100, 99))
				expect(skyShown(c)).toBe(true)
				expect(skyGui(c).Ribbon.Text.Text).toBe("Glow Party!")
			end
		)

		it("français : « Glow Party offerte par Mira ! »", function()
			local c = setup({ settings = { lang = "fr" } })
			local mira = c.h:addPlayer({ userId = 7, name = "Mira" })
			mira.DisplayName = "Mira"
			snapshot(c)
			fire(c, "EventState", boost(T0 + 600, 7))
			expect(skyGui(c).Ribbon.Text.Text).toBe("Glow Party offerte par Mira !")
		end)

		it("charges hostiles : source, acheteur et fin invalides ignorés sans erreur", function()
			local c = setup()
			snapshot(c)
			for _, bad in
				{
					{ endsAt = T0 + 600, source = 42, buyerId = 7 },
					{ endsAt = T0 + 600, source = "glowParty", buyerId = "7" },
					{ endsAt = T0 + 600, source = "glowParty", buyerId = 0 / 0 },
					{ endsAt = T0 + 600, source = "glowParty", buyerId = -3 },
					{ endsAt = T0 + 600, source = "glowParty", buyerId = 1.5 },
					{ endsAt = T0 - 10, source = "glowParty", buyerId = 7 }, -- déjà finie
				}
			do
				fire(c, "EventState", events({ serverBoost = bad }))
				frames(c, 1)
			end
			-- seule une charge valide (acheteur inconnu ignoré → anonyme) a pu déclencher la fête
			expect(#c.h.errors).toBe(0)
			local gui = skyGui(c)
			if gui and gui.Enabled then
				expect(gui.Ribbon.Text.Text).toBe("Glow Party!")
			end
		end)

		it("Mouvement réduit : bannière affichée sans animation d'échelle", function()
			local c = setup({ settings = { reducedMotion = true } })
			snapshot(c)
			fire(c, "EventState", boost(T0 + 600, 1))
			expect(skyShown(c)).toBe(true)
			expect(skyGui(c).Ribbon.UIScale.Scale).toBe(1)
			frames(c, 70, 0.1)
			expect(skyShown(c)).toBe(false)
		end)

		it("cœurs « Merci » (ping 6) pendant la Glow Party : ils volent vers l'acheteur", function()
			local c = setup()
			local mira = c.h:addPlayer({ userId = 7, name = "Mira" })
			mira.DisplayName = "Mira"
			mira.Character.HumanoidRootPart.CFrame = CFrame.new(V(30, 3, 0))
			c.h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(V(10, 3, 0))
			snapshot(c)
			fire(c, "EventState", boost(T0 + 600, 7))
			frames(c, 2)
			local function hearts()
				local n = 0
				for _, child in c.h.workspace.ClientWorld.VFX:GetChildren() do
					if child.Name == "ThanksHeart" then
						n += 1
					end
				end
				return n
			end
			-- le joueur local dit merci : des cœurs partent vers Mira
			fire(c, "PingShow", { userId = 1, kind = 6 })
			expect(hearts()).toBeGreaterThan(0)
			frames(c, 20, 0.05)
			expect(hearts()).toBe(0)
			-- un autre ping (« Bravo ! ») : pas de cœurs
			c.Clock.advance(2)
			fire(c, "PingShow", { userId = 1, kind = 4 })
			expect(hearts()).toBe(0)
			-- après la Glow Party : « Merci » n'envoie plus de cœurs
			c.Clock.advance(700)
			fire(c, "PingShow", { userId = 1, kind = 6 })
			expect(hearts()).toBe(0)
			expect(#c.h.errors).toBe(0)
		end)
	end)
end
