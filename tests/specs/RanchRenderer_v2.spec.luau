--!nocheck
-- RanchRenderer_v2 (lot B4 ; décisions D1, D11 du plan B4 ; GDD v2.0 §4.6, §11.5) : rendu v2.0 du
-- ranch, interrupteurs ouverts DANS le test (le client ne lit jamais Config/Features : il suit ce que le
-- serveur montre). Étape 1 : étiquette de la dalle du Tapis Étoilé (au-delà du Tapis 12, dalle que le
-- serveur laisse allumée avec StarMat : nom de la ligne de l'écran Améliorations, niveau 13 … 20 et prix
-- calculés sur MON profil) ; interrupteur coupé (dalle cachée par le serveur) ou profil v1 : rien de plus
-- que la v1.3. Les étapes suivantes du lot complètent ce fichier.

local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P" .. slot,
			hidden = false,
			R = 7,
			fame = 0,
			day = 4,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function find(root, name)
		for _, d in root:GetDescendants() do
			if d.Name == name and not (d.ClassName == "BillboardGui" and d.Enabled == false) then
				return d
			end
		end
		return nil
	end

	local function textOf(gui)
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextLabel" and d.Text ~= "" then
				return d.Text
			end
		end
		return ""
	end

	local function part(parent, name, props)
		local p = MockInstance.new("Part")
		p.Name = name
		for k, v in props or {} do
			p[k] = v
		end
		p.Parent = parent
		return p
	end

	local function folder(parent, name, class)
		local f = MockInstance.new(class or "Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	-- Client complet de RanchRenderer ; le ranch 3 est le mien (joueur 1), sa dalle du Tapis (prise 1)
	-- est allumée par le serveur (Transparency 0, Maxed = false) ou non (opts.pad)
	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		local Prefs = h:require(base .. "Util.Prefs")
		Prefs.Init()
		if opts.language then
			Prefs._onSettings({ lang = opts.language })
		end
		h:require(base .. "Controllers.StateController").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local pad
		do
			local w = folder(h.workspace, "Wobbleton")
			local r3 = folder(folder(w, "Ranches"), "3", "Model")
			pad = part(folder(r3, "Pads"), "1", opts.pad or { Transparency = 0 })
			pad:SetAttribute("Maxed", opts.maxed == true)
		end
		local RR = h:require(base .. "Controllers.RanchRenderer")
		RR.Init()
		RR.Start()
		local c = { h = h, RR = RR, pad = pad, Clock = Clock }
		function c.profile(data)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", data)
			h:settle(1)
		end
		function c.snapshot(ranches)
			h:fireClient(
				"ReplicatedStorage.Remotes.RanchSnapshot",
				{ seq = 1, ranches = ranches, squishies = {} }
			)
			h:settle(1)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				RR._step(dt)
			end
			h:settle(1)
		end
		function c.label()
			local gui = find(h.workspace, "PadLabel1")
			return if gui then textOf(gui) else nil
		end
		function c.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return c
	end

	-- Profil v2 au Tapis 12 (MON profil, DataSnapshot)
	local function profileV2(R, star, A)
		return {
			version = 2,
			R = R,
			bestR = R,
			ascend = A or 0,
			coins = 0,
			tiles = { snack = 12, decor = 0, pens = 0, cozyBed = false, seen = 15, star = star },
		}
	end

	describe("RanchRenderer_v2 › dalle du Tapis Étoilé (étape 1, D11)", function()
		it(
			"dalle allumée au-delà du Tapis 12 : « Star Mat Lv. 13 · prix » de MON profil, puis Lv. 14",
			function()
				local c = client()
				local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
				local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
				c.profile(profileV2(7, 0, 2))
				c.snapshot({ ["3"] = ranch(3, 1) })
				c.run(0.6)
				local price = UpgradeMath.price("star", 0, 7, 2, 7)
				expect(price < math.huge).toBe(true)
				expect(c.label()).toBe("Star Mat Lv. 13 · " .. Util.number(price))
				-- un niveau acheté : le profil change, l'étiquette suit
				c.profile(profileV2(7, 1, 2))
				c.run(0.6)
				expect(c.label()).toBe(
					"Star Mat Lv. 14 · " .. Util.number(UpgradeMath.price("star", 1, 7, 2, 7))
				)
				c.clean()
			end
		)

		it("en français : « Tapis Étoilé Niv. 13 · prix »", function()
			local c = client({ language = "fr" })
			local UpgradeMath = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
			local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
			c.profile(profileV2(10, 3))
			c.snapshot({ ["3"] = ranch(3, 1, { R = 10 }) })
			c.run(0.6)
			expect(c.label()).toBe(
				"Tapis Étoilé Niv. 16 · " .. Util.number(UpgradeMath.price("star", 3, 10, 0, 10))
			)
			c.clean()
		end)

		it(
			"interrupteur coupé (dalle cachée, Maxed = true), profil v1, plafond de la boucle : aucune étiquette",
			function()
				-- StarMat coupé : le serveur cache la dalle au Tapis 12 (v1.3)
				local off = client({ pad = { Transparency = 1 }, maxed = true })
				off.profile(profileV2(7, 0))
				off.snapshot({ ["3"] = ranch(3, 1) })
				off.run(0.6)
				expect(off.label()).toBe(nil)
				off.clean()
				-- profil v1 (le serveur ne l'allumerait pas) : le client ne montre rien non plus
				local v1 = client()
				local d = profileV2(7, 0)
				d.version = 1
				v1.profile(d)
				v1.snapshot({ ["3"] = ranch(3, 1) })
				v1.run(0.6)
				expect(v1.label()).toBe(nil)
				v1.clean()
				-- plafond de la boucle atteint (r = 7 : 2 niveaux) : aucun niveau ouvert, aucune étiquette
				local capped = client()
				capped.profile(profileV2(7, 2))
				capped.snapshot({ ["3"] = ranch(3, 1) })
				capped.run(0.6)
				expect(capped.label()).toBe(nil)
				capped.clean()
			end
		)

		it("en dessous du Tapis 12 : l'étiquette de la v1.3, inchangée", function()
			local c = client()
			local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
			local Util = c.h:require("StarterPlayer.StarterPlayerScripts.Client.World.Util")
			c.profile(profileV2(7, 0))
			c.snapshot({
				["3"] = ranch(
					3,
					1,
					{ tiles = { snack = 5, decor = 0, pens = 0, cozyBed = false, seen = 15 } }
				),
			})
			c.run(0.6)
			expect(c.label()).toBe("Snack Mat Lv. 6 · " .. Util.number(Formulas.tileCost("snack", 5, 7)))
			c.clean()
		end)
	end)
end
