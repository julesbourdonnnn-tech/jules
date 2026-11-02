--!nocheck
-- ScreenFX (paquet client-hud ; docs/04 §13.5 ; GDD §9.2, §9.4, v1.3 §10.2) : flash borné à 30 %,
-- lueur des bords, jamais au-dessus de 3 Hz, rien en Mouvement réduit sauf les flèches ; flèches de
-- bord d'écran : seulement hors champ et à ≤ 120 studs, 2 au plus avec la priorité Golden > mon
-- squishy > ma créature > Wild > fuite du Rush (dont les flèches automatiques des créatures
-- attrapables), dans la zone sûre, cachées derrière une fenêtre ; entrées hostiles sans erreur.
-- Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Layout = require("../harness/Layout")
local ApiAudit = require("../harness/ApiAudit")

local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local NOW = 1800000000

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function setup(opts)
		local h = TvAudit.client(opts)
		h:moveTo(h.localPlayer, Vector3.new(0, 3, 0))
		local FX = TvAudit.mod(h, "UI.ScreenFX")
		return h, FX
	end

	local function kinds(FX)
		local out = {}
		for _, a in FX.arrows() do
			table.insert(out, a.kind)
		end
		table.sort(out)
		return out
	end

	local function features()
		return {
			boopRush = "on",
			megaSquish = true,
			golden = true,
			jellyMoon = true,
			gauge = true,
			clips = true,
			costume = "",
			diagnostics = true,
		}
	end

	-- Miroir du monde simulé (WorldStateController, paquet client-world, remplacé par la spec)
	local function world(h, opts)
		local WSC = TvAudit.mod(h, "Controllers.WorldStateController")
		local ranch = { slot = 1, userId = 1, mode = opts.mode or "cozy", carry = "", ride = "", saddle = 0 }
		WSC.mySlot = function()
			return 1
		end
		WSC.ranch = function(slot)
			return if slot == 1 then ranch else nil
		end
		WSC.event = function()
			return { features = opts.features or features(), boost = { kind = "", untilT = 0, byName = "" } }
		end
		local list = {}
		for i, c in opts.creatures or {} do
			list[i] = {
				id = c.id,
				kind = c.kind,
				ownerSlot = c.ownerSlot or 0,
				booperSlot = c.booperSlot or 0,
				t0 = NOW - 1,
				duration = 25,
				personal = c.personal == true,
			}
		end
		WSC.creatures = function()
			return list
		end
		WSC.creaturePos = function(id)
			for _, c in opts.creatures or {} do
				if c.id == id then
					return c.pos
				end
			end
			return nil
		end
		return WSC
	end

	describe("ScreenFX › flash et lueur", function()
		it(
			"flash : opacité bornée à 30 %, durée ≤ 1 s, décoratif ; jamais plus de 3 par seconde",
			function()
				local h, FX = setup()
				local J = TvAudit.mod(h, "UI.Juice")
				local orig = J.tween
				local calls = {}
				J.tween = function(inst, d, props, ...)
					if inst.Name == "Flash" then
						table.insert(calls, { start = inst.BackgroundTransparency, d = d })
					end
					return orig(inst, d, props, ...)
				end
				FX.flash(0.9, 5, roblox.Color3.new(1, 1, 0))
				expect(#calls).toBe(1)
				expect(math.abs(calls[1].start - 0.7) < 1e-6).toBe(true)
				expect(calls[1].d <= 1).toBe(true)
				local flash = h.localPlayer.PlayerGui.ScreenFX.Flash
				expect(flash:GetAttribute("Decorative")).toBe(true)
				-- 3 Hz au plus : un deuxième flash moins d'1/3 s après est ignoré
				FX.flash(0.2, 0.1)
				expect(#calls).toBe(1)
				TvAudit.tick(h, 0.34)
				FX.flash(0.2, 0.1)
				expect(#calls).toBe(2)
				clean(h)
			end
		)

		it("Mouvement réduit : ni flash ni lueur (les flèches restent)", function()
			local h, FX = setup()
			local Prefs = TvAudit.mod(h, "Util.Prefs")
			Prefs.reducedMotion = function()
				return true
			end
			local J = TvAudit.mod(h, "UI.Juice")
			local count = 0
			local orig = J.tween
			J.tween = function(inst, ...)
				if inst.Name == "Flash" or string.find(inst.Name, "Glow", 1, true) then
					count += 1
				end
				return orig(inst, ...)
			end
			FX.flash(0.3, 0.12)
			FX.glow(roblox.Color3.new(1, 0.8, 0.2), 0.4, 1)
			expect(count).toBe(0)
			FX.arrow("a", Vector3.new(0, 3, 60), "golden")
			FX._step()
			expect(#FX.arrows()).toBe(1)
			clean(h)
		end)

		it("lueur des bords : 4 bandes décoratives, force bornée, 3 Hz au plus", function()
			local h, FX = setup()
			local gui = h.localPlayer.PlayerGui.ScreenFX
			local J = TvAudit.mod(h, "UI.Juice")
			local orig = J.tween
			local starts = {}
			J.tween = function(inst, d, props, ...)
				if string.find(inst.Name, "Glow", 1, true) then
					table.insert(starts, inst.BackgroundTransparency)
				end
				return orig(inst, d, props, ...)
			end
			FX.glow(roblox.Color3.new(1, 0.8, 0.2), 0.4, 7)
			expect(#starts).toBe(4)
			for _, t in starts do
				expect(t >= 0.4 - 1e-6).toBe(true) -- force 1 → opacité 0,6 au plus
			end
			for _, name in { "GlowTop", "GlowBottom", "GlowLeft", "GlowRight" } do
				expect(gui[name]:GetAttribute("Decorative")).toBe(true)
			end
			FX.glow(roblox.Color3.new(1, 1, 1), 0.4, 0.5)
			expect(#starts).toBe(4)
			clean(h)
		end)
	end)

	describe("ScreenFX › flèches de bord d'écran", function()
		it("2 au plus, par priorité ; seulement hors champ et à 120 studs au plus", function()
			local h, FX = setup()
			FX.arrow("wild", Vector3.new(40, 3, 60), "wild")
			FX.arrow("rush", Vector3.new(-40, 3, 60), "rush")
			FX.arrow("mine", Vector3.new(10, 3, 80), "personal")
			FX.arrow("gold", Vector3.new(0, 3, 100), "golden")
			FX.arrow("onscreen", Vector3.new(0, 0, -10), "golden") -- devant la caméra : à l'écran
			FX.arrow("far", Vector3.new(0, 3, 300), "golden") -- au-delà de 120 studs
			FX._step()
			expect(kinds(FX)).toEqual({ "golden", "personal" })
			-- retirée : la suivante prend sa place
			FX.arrow("gold", nil, "golden")
			FX._step()
			expect(kinds(FX)).toEqual({ "personal", "wild" })
			clean(h)
		end)

		it("dans la zone sûre de 5 % et cachées dès qu'une fenêtre est ouverte", function()
			local h, FX = setup()
			FX.arrow("left", Vector3.new(-500, 3, -20), "wild")
			FX.arrow("behind", Vector3.new(0, 3, 90), "golden")
			FX._step()
			expect(#FX.arrows()).toBe(1) -- « left » est au-delà de 120 studs
			FX.arrow("left", Vector3.new(-100, 3, -20), "wild")
			FX._step()
			expect(#FX.arrows()).toBe(2)
			Layout.apply(h)
			local vp = h.viewport
			for i = 1, 2 do
				local f = h.localPlayer.PlayerGui.ScreenFX.Safe["EdgeArrow" .. i]
				local r = Layout.rect(f)
				expect(r.x >= vp.X * 0.05 - 0.5 and r.x + r.w <= vp.X * 0.95 + 0.5).toBe(true)
				expect(r.y >= vp.Y * 0.05 - 0.5 and r.y + r.h <= vp.Y * 0.95 + 0.5).toBe(true)
			end
			local PC = TvAudit.mod(h, "UI.PanelController")
			PC.toggleMenu()
			FX._step()
			expect(#FX.arrows()).toBe(0)
			TvAudit.tick(h, 0.5)
			PC.closeAll()
			FX._step()
			expect(#FX.arrows()).toBe(2)
			clean(h)
		end)

		it(
			"flèches automatiques : Golden attrapable puis la créature attrapable la plus prioritaire",
			function()
				local h, FX = setup()
				world(h, {
					mode = "cozy",
					creatures = {
						{ id = 1, kind = "golden", pos = Vector3.new(0, 3, 100) },
						{ id = 2, kind = "wild", pos = Vector3.new(30, 3, 50) },
						{
							id = 3,
							kind = "escape",
							ownerSlot = 2,
							booperSlot = 3,
							pos = Vector3.new(5, 3, 40),
						},
						{
							id = 4,
							kind = "runaway",
							ownerSlot = 1,
							personal = true,
							pos = Vector3.new(-30, 3, 70),
						},
					},
				})
				FX._step()
				expect(kinds(FX)).toEqual({ "golden", "personal" })
				clean(h)
			end
		)

		it(
			"Cozy : la fuite du Rush n'a pas de flèche ; Rush : oui ; mon squishy boopé passe avant",
			function()
				local h, FX = setup()
				local creatures = {
					{ id = 3, kind = "escape", ownerSlot = 2, booperSlot = 3, pos = Vector3.new(5, 3, 40) },
				}
				world(h, { mode = "cozy", creatures = creatures })
				FX._step()
				expect(#FX.arrows()).toBe(0)
				world(h, { mode = "rush", creatures = creatures })
				FX._step()
				expect(kinds(FX)).toEqual({ "rush" })
				table.insert(
					creatures,
					{ id = 5, kind = "escape", ownerSlot = 1, booperSlot = 4, pos = Vector3.new(0, 3, 110) }
				)
				world(h, { mode = "rush", creatures = creatures })
				FX._step()
				expect(kinds(FX)).toEqual({ "booped" })
				clean(h)
			end
		)

		it(
			"Golden pendant ma recharge de victoire, ou interrupteur coupé : aucune flèche Golden",
			function()
				local State = nil
				local h, FX = setup()
				State = TvAudit.mod(h, "Controllers.StateController")
				h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ golden = { lastWinAt = NOW - 100 } },
					{}
				)
				h:settle(1)
				expect(State.get("golden").lastWinAt).toBe(NOW - 100)
				local creatures = { { id = 1, kind = "golden", pos = Vector3.new(0, 3, 100) } }
				world(h, { creatures = creatures })
				FX._step()
				expect(#FX.arrows()).toBe(0)
				h:fireClient("ReplicatedStorage.Remotes.DataPatch", { golden = { lastWinAt = 0 } }, {})
				h:settle(1)
				local f = features()
				f.golden = false
				world(h, { creatures = creatures, features = f })
				FX._step()
				expect(#FX.arrows()).toBe(0)
				world(h, { creatures = creatures })
				FX._step()
				expect(kinds(FX)).toEqual({ "golden" })
				clean(h)
			end
		)

		it("entrées hostiles : aucune erreur, aucune flèche fantôme, table bornée", function()
			local h, FX = setup()
			FX.arrow(nil, Vector3.new(0, 3, 60), "golden")
			FX.arrow("", Vector3.new(0, 3, 60), "golden")
			FX.arrow(string.rep("x", 200), Vector3.new(0, 3, 60), "golden")
			FX.arrow("nan", Vector3.new(0 / 0, 3, 60), "golden")
			FX.arrow("inf", Vector3.new(math.huge, 3, 60), "golden")
			FX.arrow("str", "ici", "golden")
			FX._step()
			expect(#FX.arrows()).toBe(0)
			for i = 1, 100 do
				FX.arrow("a" .. i, Vector3.new(0, 3, 60), 42)
			end
			FX._step()
			expect(#FX.arrows() <= 2).toBe(true)
			FX.flash("fort", nil, "rouge")
			FX.glow(nil, -1, 0 / 0)
			clean(h)
		end)

		it("API Roblox : chaque classe et propriété écrite existe (ApiAudit)", function()
			ApiAudit.start()
			local ok, err = pcall(function()
				local h, FX = setup()
				FX.flash(0.3, 0.12)
				FX.glow(roblox.Color3.new(1, 0.8, 0.2), 0.4, 0.5)
				FX.arrow("a", Vector3.new(0, 3, 60), "golden")
				FX._step()
				h:step(1 / 60, 3)
				clean(h)
			end)
			local issues = ApiAudit.stop()
			expect(ok and "" or tostring(err)).toBe("")
			expect(table.concat(issues, "\n")).toBe("")
		end)
	end)
end
