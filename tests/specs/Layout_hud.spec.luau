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
end
