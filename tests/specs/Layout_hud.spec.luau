--!nocheck
-- Layout_hud (paquet client-hud ; couche d, docs/04 §14.1, §17.1 d ; GDD §10.1, §10.2) : HUD complet
-- (tous les éléments visibles ensemble, carte non bloquante à droite, message central) en 1920 × 1080,
-- 3840 × 2160 et 1280 × 720 (barre de Roblox simulée), en anglais et en français, plus 21:9 et 16:10 :
-- aucun chevauchement, aucun texte coupé ni sous 28 px TV, rien hors de la zone sûre de 5 %, carte et
-- HUD qui ne se recouvrent pas, textes du monde (invites, étiquette de dalle) ≥ 28 px TV à 20 studs ;
-- fenêtres des cartes (rouverte, carte du choix) auditées de même ; budget d'objets d'interface.
-- Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Layout = require("../harness/Layout")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- Client au HUD complet : profil riche, Grand Splorch en file, sieste de Big Plop, bouclier, ×2,
	-- APPLAUDIR, cible, recharge du bond, carte non bloquante et message
	local function fullHud(opts)
		opts = opts or {}
		local profile = TvAudit.richProfile(NOW)
		profile.onboarding = { step = 11, done = true, demoDone = true }
		profile.fame = 123456
		local h = TvAudit.client({ profile = profile, viewport = opts.viewport, lang = opts.lang })
		h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return if slot == 1
				then { slot = 1, userId = 1, mode = "rush", shield = true, carry = "", ride = "", saddle = 2 }
				else nil
		end
		WSC.event = function()
			return {
				features = {
					boopRush = "on",
					megaSquish = true,
					golden = true,
					jellyMoon = true,
					gauge = true,
					clips = true,
					costume = "",
					diagnostics = true,
				},
				boost = { kind = "wobble", untilT = NOW + 299, byName = "" },
				gauge = { points = 400, target = 1200, partyUntil = 0, restUntil = NOW + 754 },
				spectacle = {
					queue = {
						{
							kind = "splorch",
							userId = 1,
							startAt = NOW + 40,
							slot = 1,
							position = 2,
							eta = 40,
						},
					},
				},
				mega = { phase = "idle", points = 0, target = 0 },
			}
		end
		WSC.squishies = function()
			return {
				u7 = { s = 14, m = 6, st = 5, z = 123456789, zg = 0, at = "pen", bf = 0, o = "", ready = 0 },
			}
		end
		TvAudit.mod(h, "Controllers.PromptController").current = function()
			return {
				kind = "squishy",
				slot = 1,
				uid = "u7",
				primary = "press",
				secondary = "pickup",
				ready = true,
				position = Vector3.new(0, 2, -6),
			}
		end
		TvAudit.mod(h, "Controllers.ChaseController").cooldownLeft = function()
			return 2
		end
		h:fireClient("ReplicatedStorage.Remotes.ClapPrompt", { heroId = 5, endsAt = NOW + 8 })
		h:fireClient("ReplicatedStorage.Remotes.Celebrate", { kind = "objectivesCard", data = { day = 1 } })
		h:fireClient(
			"ReplicatedStorage.Remotes.Feedback",
			{ key = "feedback.notEnoughCoins", vars = { missing = 123456 }, tone = "warning" }
		)
		h:settle(2)
		TvAudit.mod(h, "UI.HUD")._refresh()
		TvAudit.mod(h, "UI.Prompt")._step()
		h:step(1 / 60, 2)
		return h
	end

	local function rectsIntersect(a, b)
		local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
		local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
		return ox > 2 and oy > 2
	end

	local function audit(h, label)
		local issues = {}
		local gui = h.localPlayer.PlayerGui
		for _, root in { gui.HUD, gui.Cards } do
			for _, list in
				{ TvAudit.overlaps(h, root), TvAudit.clipped(h, root), TvAudit.outsideSafe(h, root) }
			do
				for _, issue in list do
					table.insert(issues, label .. " " .. root.Name .. " : " .. issue)
				end
			end
		end
		-- la carte non bloquante (écran Cards) ne recouvre aucun élément visible du HUD
		Layout.apply(h)
		local HUD = TvAudit.mod(h, "UI.HUD")
		local side = TvAudit.mod(h, "UI.Cards").frame("side")
		if side.Visible then
			local rs = Layout.rect(side)
			for name in h:require("ReplicatedStorage.Shared.Config.Layout").Hud do
				local e = HUD.element(name)
				if e and e ~= side and e.Visible and name ~= "message" then
					local r = Layout.rect(e)
					if r and rectsIntersect(r, rs) then
						table.insert(issues, label .. " carte × " .. name)
					end
				end
			end
		end
		return issues
	end

	describe("Layout_hud › HUD complet", function()
		it(
			"aucun chevauchement, aucun texte coupé ni hors zone sûre, aux 3 résolutions, EN et FR",
			function()
				local L = nil
				local all = {}
				for _, lang in { "en", "fr" } do
					local h = fullHud({ lang = lang })
					L = h:require("ReplicatedStorage.Shared.Config.Layout")
					local HUD = TvAudit.mod(h, "UI.HUD")
					-- tous les éléments du jeu calme sont visibles ensemble
					for _, name in
						{
							"coins",
							"fame",
							"menuChip",
							"eventPill",
							"gauge",
							"goalTracker",
							"status",
							"specialChip",
							"targetCard",
							"leap",
						}
					do
						expect({ lang = lang, name = name, visible = HUD.visible(name) }).toEqual({
							lang = lang,
							name = name,
							visible = true,
						})
					end
					expect(TvAudit.mod(h, "UI.Cards").frame("side").Visible).toBe(true)
					for _, res in L.TestResolutions do
						TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
						HUD._refresh()
						for _, issue in audit(h, lang .. " " .. res.X .. "×" .. res.Y) do
							table.insert(all, issue)
						end
					end
					for _, res in L.ExtraResolutions do
						TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
						HUD._refresh()
						for _, issue in TvAudit.overlaps(h, h.localPlayer.PlayerGui.HUD) do
							table.insert(all, lang .. " " .. res.X .. "×" .. res.Y .. " : " .. issue)
						end
					end
					expect(TvAudit.guiObjects(h) <= 3000).toBe(true)
					clean(h)
				end
				expect(table.concat(all, "\n")).toBe("")
			end
		)

		it(
			"textes du monde (invites, étiquette de dalle) ≥ 28 px TV à 20 studs aux 3 résolutions",
			function()
				local h = fullHud()
				local L = h:require("ReplicatedStorage.Shared.Config.Layout")
				local WT = TvAudit.mod(h, "UI.WorldText")
				local P = TvAudit.mod(h, "UI.Prompt")
				local part = h.globals.Instance.new("Part")
				part.Anchored = true
				part.Parent = h.game.Workspace
				local tile = WT.create(part, { kind = "text", maxDistance = L.WorldText.TileLabelDistance })
				WT.setText(tile, "Lv. 3 · 1.2K")
				local plus = WT.create(part, { kind = "plus", maxDistance = 40 })
				WT.setText(plus, "+1.2K")
				for _, res in L.TestResolutions do
					local vp = Vector2.new(res.X, res.Y)
					TvAudit.setResolution(h, vp)
					P._step()
					local guis = P.guis()
					expect(#guis).toBe(2)
					table.insert(guis, tile)
					table.insert(guis, plus)
					for _, gui in guis do
						expect(gui.MaxDistance >= L.WorldText.TestDistance).toBe(true)
						expect({
							res = res.X,
							name = gui.Name,
							ok = WT.projectedPx(gui, vp) >= L.WorldText.MinProjected,
						}).toEqual({
							res = res.X,
							name = gui.Name,
							ok = true,
						})
					end
				end
				clean(h)
			end
		)
	end)

	describe("Layout_hud › fenêtres des cartes", function()
		it(
			"carte rouverte et carte du choix : aucune faute de disposition aux 3 résolutions, EN et FR",
			function()
				local all = {}
				for _, lang in { "en", "fr" } do
					local h = fullHud({ lang = lang })
					local L = h:require("ReplicatedStorage.Shared.Config.Layout")
					local C = TvAudit.mod(h, "UI.Cards")
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					-- carte « Wibble revient toujours ! » (3 boutons, le cas le plus large) rouverte
					h:fireClient(
						"ReplicatedStorage.Remotes.Celebrate",
						{ kind = "booped", data = { uid = "u9", species = 2, booperId = 55 } }
					)
					h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
						kind = "ownerReturn",
						data = {
							uid = "u9",
							species = 2,
							coins = 999999,
							catcherId = 6,
							catcherName = "Noah",
							firstBoop = true,
						},
					})
					h:settle(1)
					for _ = 1, 4 do
						Clock.advance(8.01)
						C._step()
					end
					local id = nil
					for _, c in C.pending() do
						if c.kind == "postBoop" then
							id = c.id
						end
					end
					C.open(id)
					for _, res in L.TestResolutions do
						TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
						for _, issue in TvAudit.check(h, lang .. " " .. res.X .. " carte : ") do
							table.insert(all, issue)
						end
					end
					TvAudit.setResolution(h, Vector2.new(1920, 1080))
					TvAudit.tick(h, 0.5)
					TvAudit.mod(h, "UI.FocusGuard").back()
					clean(h)
				end
				for _, lang in { "en", "fr" } do
					local h = fullHud({ lang = lang })
					local L = h:require("ReplicatedStorage.Shared.Config.Layout")
					local C = TvAudit.mod(h, "UI.Cards")
					local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
					C.dismiss(C.current().id)
					local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
					h:moveTo(h.localPlayer, WorldLayout.toWorld(1, Vector3.new(0, 3, 36)))
					TvAudit.mod(h, "Controllers.WorldStateController").creatures = function()
						return {}
					end
					h:fireClient("ReplicatedStorage.Remotes.ModePrompt")
					h:settle(1)
					C._step()
					Clock.advance(1.6)
					C._step()
					Clock.advance(0.7)
					C._step()
					expect(C.current().kind).toBe("mode")
					for _, res in L.TestResolutions do
						TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
						for _, issue in TvAudit.check(h, lang .. " " .. res.X .. " choix : ") do
							table.insert(all, issue)
						end
					end
					clean(h)
				end
				expect(table.concat(all, "\n")).toBe("")
			end
		)
	end)
	-- =========================================================================================
	-- v2.0 (lot B2, étape 4 ; N9, N18, D14 ; docs/04 §27.8) : HUD v2.0 aux rectangles de
	-- Layout.HudV2.Rects, rail de 8 et 9 entrées avec et sans la barre de Roblox
	-- =========================================================================================
	describe("Layout_hud › HUD v2.0 (lot B2)", function()
		local UpgradeScreen = require("../harness/UpgradeScreen")
		local MockInstance = require("../harness/MockInstance")
		local S = UpgradeScreen.new(T.Harness)
		local NAMES = {
			coins = "coins",
			fame = "fame",
			menuChip = "menuChip",
			nextBuy = "nextBuy",
			eventPill = "eventPill",
			megaBar = "megaBar",
			gauge = "gauge",
			message = "message",
			tracker = "goalTracker",
			status = "status",
			card = "card",
			special = "specialChip",
			target = "targetCard",
			dash = "leap",
		}

		-- barre de Roblox absente (GuiService:GetGuiInset = 0 ; mise en page du harnais sans décalage) ;
		-- rendue à la fin du cas, quoi qu'il arrive
		local function withoutBar(fn)
			local cm = MockInstance.classMethods.GuiService
			local get = cm.GetGuiInset
			local inset = Layout.GUI_INSET
			cm.GetGuiInset = function()
				return Vector2.new(0, 0), Vector2.zero
			end
			Layout.GUI_INSET = 0
			local ok, err = pcall(fn)
			cm.GetGuiInset = get
			Layout.GUI_INSET = inset
			if not ok then
				error(err, 0)
			end
		end

		-- Client v2.0 au HUD complet (comme fullHud, avec l'instantané du serveur et la puce « Prochain
		-- achat ») ; opts.shop, opts.pending (carte en attente : 9e entrée du rail), opts.ready
		local function v2Hud(opts)
			opts = opts or {}
			local profile = TvAudit.richProfile(NOW)
			profile.onboarding = { step = 11, done = true, demoDone = true }
			profile.growth = { G = 0, g = 0, t = NOW }
			if opts.ready then
				profile.squishies.u20.z = 1e15
			end
			local c = S.client({
				snap = S.snap(1, function(p)
					p.coins = 1
				end),
				profile = profile,
				lang = opts.lang,
				before = if opts.shop then TvAudit.enableShop else nil,
			})
			local h = c.h
			h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
			-- événements du serveur (pastille, jauge), comme fullHud
			TvAudit.mod(h, "Controllers.WorldStateController").event = function()
				return {
					features = {
						boopRush = "on",
						megaSquish = true,
						golden = true,
						jellyMoon = true,
						gauge = true,
						clips = true,
						costume = "",
						diagnostics = true,
					},
					boost = { kind = "wobble", untilT = NOW + 299, byName = "" },
					gauge = { points = 400, target = 1200, partyUntil = 0, restUntil = 0 },
					spectacle = { queue = {} },
					mega = { phase = "idle", points = 0, target = 0 },
				}
			end
			if opts.pending then
				TvAudit.mod(h, "UI.Cards").pending = function()
					return { { id = "x1", kind = "sleepy" } }
				end
			end
			return c
		end

		local function tvRect(h, obj)
			local r = Layout.rect(obj)
			local s = h.viewport.Y / 1080
			return { x = r.x / s, y = r.y / s, w = r.w / s, h = r.h / s }
		end

		local function near(a, b)
			return math.abs(a - b) <= 1.5
		end

		local function overlap(a, b)
			local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
			local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
			return ox > 2 and oy > 2
		end

		it(
			"chaque élément à son rectangle de Layout.HudV2.Rects, aux 3 résolutions, EN et FR (sans barre) ; paires exclusives ; milieu libre ; aucun chevauchement",
			function()
				local all = {}
				withoutBar(function()
					for _, lang in { "en", "fr" } do
						local c = v2Hud({ lang = lang })
						local h = c.h
						local L = h:require("ReplicatedStorage.Shared.Config.Layout")
						local HUD = TvAudit.mod(h, "UI.HUD")
						-- Fame qui change : la pastille se montre (3 s) ; cible et recharge du bond
						h:fireClient("ReplicatedStorage.Remotes.DataPatch", { fame = 777 }, {})
						TvAudit.mod(h, "Controllers.ChaseController").cooldownLeft = function()
							return 2
						end
						TvAudit.mod(h, "Controllers.PromptController").current = function()
							return {
								kind = "squishy",
								slot = 1,
								uid = "u7",
								primary = "press",
								secondary = "pickup",
								ready = true,
								position = Vector3.new(0, 2, -6),
							}
						end
						TvAudit.mod(h, "Controllers.WorldStateController").squishies = function()
							return { u7 = TvAudit.squishy(14, { z = 123456789 }) }
						end
						h:fireClient(
							"ReplicatedStorage.Remotes.Celebrate",
							{ kind = "objectivesCard", data = { day = 1 } }
						)
						S.run(c, 0.5)
						for _, res in L.TestResolutions do
							TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
							HUD._refresh()
							Layout.apply(h)
							local seen = {}
							for rect, name in NAMES do
								local e = HUD.element(name)
								if e and e.Visible then
									local want = L.HudV2.Rects[rect]
									local got = tvRect(h, e)
									local same = near(got.x, want.x)
										and near(got.y, want.y)
										and near(got.w, want.w)
										and near(got.h, want.h)
									if not same and rect ~= "message" and rect ~= "card" then
										table.insert(
											all,
											string.format(
												"%s %d : %s à (%d, %d, %d × %d), attendu (%d, %d, %d × %d)",
												lang,
												res.X,
												rect,
												got.x,
												got.y,
												got.w,
												got.h,
												want.x,
												want.y,
												want.w,
												want.h
											)
										)
									end
									seen[rect] = got
									-- milieu de l'écran libre (personnage et squishies)
									if rect ~= "message" and overlap(got, L.HudV2.Center) then
										table.insert(
											all,
											lang .. " " .. res.X .. " : " .. rect .. " dans le milieu"
										)
									end
								end
							end
							-- tous les éléments du HUD calme v2.0 sont là (Fame : ses 3 s)
							for _, rect in
								{
									"coins",
									"fame",
									"menuChip",
									"nextBuy",
									"eventPill",
									"gauge",
									"tracker",
									"status",
									"target",
									"dash",
								}
							do
								if seen[rect] == nil then
									table.insert(all, lang .. " " .. res.X .. " : " .. rect .. " absent")
								end
							end
							-- paires exclusives : jamais visibles ensemble
							for _, pair in L.HudV2.Exclusive do
								if seen[pair[1]] and seen[pair[2]] then
									table.insert(
										all,
										lang .. " " .. res.X .. " : " .. pair[1] .. " et " .. pair[2]
									)
								end
							end
							for _, issue in audit(h, lang .. " " .. res.X .. "×" .. res.Y) do
								table.insert(all, issue)
							end
						end
						S.clean(c, expect)
					end
				end)
				expect(table.concat(all, "\n")).toBe("")
			end
		)

		it(
			"rail de 8 et 9 entrées, avec et sans la barre de Roblox, aux 3 résolutions : boutons de 80, jamais sur la pastille des pièces, dans la zone sûre",
			function()
				local all = {}
				local function check(label, pending)
					local c = v2Hud({ shop = true, ready = true, pending = pending })
					local h = c.h
					local L = h:require("ReplicatedStorage.Shared.Config.Layout")
					local PC = c.PC
					local HUD = TvAudit.mod(h, "UI.HUD")
					for _, res in L.TestResolutions do
						TvAudit.setResolution(h, Vector2.new(res.X, res.Y))
						PC.closeAll()
						S.run(c, 0.4)
						PC.toggleMenu()
						S.run(c, 0.5)
						local entries = PC.entries()
						local want = if pending then 9 else 8
						if #entries ~= want then
							table.insert(all, label .. " " .. res.X .. " : " .. #entries .. " entrées")
						end
						Layout.apply(h)
						local rail = PC.entryButton("Ranch").Parent
						local r = tvRect(h, rail)
						local coins = tvRect(h, HUD.element("coins"))
						if r.y < coins.y + coins.h + 12 - 1 then
							table.insert(
								all,
								string.format(
									"%s %d : rail en y %d, sur les pièces (bas %d)",
									label,
									res.X,
									r.y,
									coins.y + coins.h
								)
							)
						end
						local bottom = (h.viewport.Y * 0.95) / (h.viewport.Y / 1080)
						if r.y + r.h > bottom + 1 then
							table.insert(
								all,
								string.format(
									"%s %d : rail jusqu'en y %d (zone sûre %d)",
									label,
									res.X,
									r.y + r.h,
									bottom
								)
							)
						end
						local gap = rail:GetAttribute("Gap")
						if gap < 4 or (not pending and gap ~= 16) then
							table.insert(all, label .. " " .. res.X .. " : écart " .. tostring(gap))
						end
						for _, entry in entries do
							local b = tvRect(h, PC.entryButton(entry))
							if not near(b.h, 80) then
								table.insert(
									all,
									string.format("%s %d : %s haut de %d", label, res.X, entry, b.h)
								)
							end
						end
						for _, issue in TvAudit.outsideSafe(h, h.localPlayer.PlayerGui.Menu) do
							table.insert(all, label .. " " .. res.X .. " : " .. issue)
						end
						for _, issue in TvAudit.clipped(h, h.localPlayer.PlayerGui.Menu) do
							table.insert(all, label .. " " .. res.X .. " : " .. issue)
						end
						-- le rail remplace la puce Menu et cache « Prochain achat » (paires exclusives)
						if HUD.visible("menuChip") or HUD.visible("nextBuy") then
							table.insert(
								all,
								label .. " " .. res.X .. " : puce Menu ou Prochain achat sous le rail"
							)
						end
						-- lot I (M21, revue de la galerie) : un panneau ouvert, le bas du rail ne dépasse
						-- jamais sous le coin du panneau (Réglages passait sous le coin en bas à gauche)
						PC.open("Ranch")
						S.run(c, 0.6)
						Layout.apply(h)
						local win = PC.window("Ranch")
						if win then
							local w = tvRect(h, win)
							local rr = tvRect(h, rail)
							if rr.y + rr.h > w.y + w.h + 1 then
								table.insert(
									all,
									string.format(
										"%s %d : rail jusqu'en y %d sous le panneau (bas %d)",
										label,
										res.X,
										rr.y + rr.h,
										w.y + w.h
									)
								)
							end
						end
					end
					S.clean(c, expect)
				end
				check("barre 8", false)
				check("barre 9", true)
				withoutBar(function()
					check("sans barre 8", false)
					check("sans barre 9", true)
				end)
				expect(table.concat(all, "\n")).toBe("")
			end
		)
	end)
end
