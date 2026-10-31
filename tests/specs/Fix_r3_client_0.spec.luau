--!nocheck
-- Correctifs QA tour 3, paquet client r3-client-0 :
--   * CongaRenderer : les Nebbies de parade restent comptés dans les budgets §12.8 (≤ 100 Nebbies
--     en détail complet, ≤ MaxNebbyParts pièces) pendant toute la parade ; le planificateur ne
--     redistribue plus leur part aux autres vues tant qu'ils sont dessinés
--   * NestDisplay : PerchData réordonné (parade d'un Nebby meilleur que des perchés) → les vues
--     perchées sont réutilisées par (code, étoiles), aucun perché ne disparaît une image
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local CODE_A = 1 -- Puffkin (Commun)

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
			PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.Render = c.Balance.Render
		for _, fn in opts.before or {} do
			fn(c)
		end
		c.WSC.Init()
		c.CR.Init()
		c.WSC.Start()
		c.CR.Start()
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

	local function placeLocal(c, pos)
		c.h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
	end

	local function codes(n, code)
		local out = {}
		for i = 1, n do
			out[i] = code or CODE_A
		end
		return out
	end

	-- miettes en ligne droite d'un point par stud (tête = dernier point)
	local function path(n, x0, z)
		local points = {}
		for i = 1, n do
			points[i] = V(x0 + i, 3, z)
		end
		return points
	end

	-- Modèles de Nebbies parentés à plusieurs pièces (détail complet), pièces de Nebbies parentées
	local function census(c)
		local full, parts = 0, 0
		for _, name in { "Lines", "Wild", "Perched" } do
			for _, model in c.h.workspace.ClientWorld[name]:GetChildren() do
				if model.ClassName == "Model" then
					local n = 0
					for _, child in model:GetChildren() do
						if child:IsA("BasePart") then
							n += 1
						end
					end
					parts += n
					if n > 1 then
						full += 1
					end
				end
			end
		end
		return full, parts
	end

	-- ---------------------------------------------------------------------------------------------
	-- CongaRenderer : parade et budgets §12.8
	-- ---------------------------------------------------------------------------------------------

	-- 4 files de 60 Puffkins autour du joueur local (en 0, 3, 0) ; la file du slot 1 est la plus proche
	local function paradeScene(c)
		placeLocal(c, V(0, 3, 0))
		local lines, all = {}, {}
		for k = 1, 4 do
			table.insert(lines, { slot = k, userId = 100 + k, ver = 1, codes = codes(60) })
			for _, e in c.PathCodec.split(k, 1, path(170, -85, 3 + (k - 1) * 6)) do
				table.insert(all, e)
			end
		end
		fire(c, "WorldSnapshot", {
			serverTime = T0,
			tick = 1,
			lines = lines,
			paths = c.PathCodec.encode(1, all),
			wild = {},
			events = { t = T0, wisps = {}, snipsDisabled = false, activePlayers = 5 },
			crews = { crews = {} },
		})
		frames(c, 40)
	end

	local function bank(c, slot)
		fire(c, "LineEvent", {
			{
				op = "bank",
				slot = slot,
				ver = 2,
				count = 60,
				glow = 600,
				bonus = 1.5,
				atBeacon = false,
				newEntries = 0,
			},
		})
	end

	-- Suit la parade image par image (60 i/s) : pics de modèles complets et de pièces
	local function watchParade(c)
		local peakFull, peakParts, peakRendered = 0, 0, 0
		local sawParade = false
		for _ = 1, 200 do
			frames(c, 1, 1 / 60)
			local full, parts = census(c)
			peakFull = math.max(peakFull, full)
			peakParts = math.max(peakParts, parts)
			peakRendered = math.max(peakRendered, c.CR.renderedParts())
			sawParade = sawParade or c.CR.paradeCount() > 0
		end
		return peakFull, peakParts, peakRendered, sawParade
	end

	describe("Fix r3 client-0 › parade dans les budgets §12.8", function()
		it("parade d'une file de 60 : ≤ 100 Nebbies en détail complet à chaque image", function()
			local c = setup()
			paradeScene(c)
			local before = census(c)
			expect(before).toBe(c.Render.MaxFullDetail)
			expect(c.CR.fullDetailCount()).toBe(c.Render.MaxFullDetail)
			bank(c, 1)
			local peakFull, _, peakRendered, sawParade = watchParade(c)
			expect(sawParade).toBe(true)
			-- avant correction : 157 modèles complets parentés pendant la parade
			expect(peakFull <= c.Render.MaxFullDetail).toBe(true)
			expect(peakRendered <= c.Render.MaxNebbyParts).toBe(true)
			expect(c.CR.paradeCount()).toBe(0)
			-- la parade finie, le budget libéré revient aux autres files
			frames(c, 20)
			expect(c.CR.fullDetailCount()).toBe(c.Render.MaxFullDetail)
			expect(#c.h.errors).toBe(0)
			expect(#c.h:warnings()).toBe(0)
		end)

		it("plafond de pièces (600 forcé) tenu pendant la parade, Nebbies de parade compris", function()
			local c = setup({
				before = {
					function(cc)
						cc.Render.MaxNebbyParts = 600
					end,
				},
			})
			paradeScene(c)
			expect(c.CR.renderedParts() <= 600).toBe(true)
			bank(c, 1)
			local peakFull, peakParts, peakRendered, sawParade = watchParade(c)
			expect(sawParade).toBe(true)
			-- avant correction : 527 pièces avant la parade, 690 au pic
			expect(peakRendered <= 600).toBe(true)
			expect(peakParts <= 600).toBe(true)
			expect(peakFull <= c.Render.MaxFullDetail).toBe(true)
			expect(#c.h.errors).toBe(0)
		end)

		it(
			"plafond abaissé pendant la parade : les Nebbies de parade les plus lointains passent en boule",
			function()
				local c = setup()
				paradeScene(c)
				bank(c, 1)
				frames(c, 1, 1 / 60)
				expect(c.CR.paradeCount()).toBe(60)
				-- ex. Graphismes légers ou plafond plus bas : la part des parades seule dépasse déjà
				c.Render.MaxFullDetail = 10
				for _ = 1, 12 do
					frames(c, 1, 1 / 60)
				end
				expect(c.CR.paradeCount()).toBeGreaterThan(0)
				local full = census(c)
				expect(full <= 10).toBe(true)
				expect(c.CR.fullDetailCount() <= 10).toBe(true)
				expect(#c.h.errors).toBe(0)
			end
		)

		it("fullDetailCount compte les Nebbies de parade encore en détail complet", function()
			local c = setup()
			paradeScene(c)
			bank(c, 1)
			frames(c, 1, 1 / 60)
			expect(c.CR.paradeCount()).toBeGreaterThan(0)
			local full = census(c)
			expect(c.CR.fullDetailCount()).toBe(full)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- NestDisplay : perchés réordonnés par une parade
	-- ---------------------------------------------------------------------------------------------

	local NEST = 4

	local function fakeNest(c, slot, attrs)
		local g = c.g
		local model = g.Instance.new("Model")
		model.Name = string.format("Nest_%02d", slot)
		local defaults = {
			Slot = slot,
			OwnerUserId = 0,
			OwnerName = "",
			Color = g.Color3.fromRGB(120, 120, 130),
			Supernovas = 0,
			PerchCount = 0,
			PerchData = "",
			Title = "",
			NestTheme = "default",
			LineStyle = "default",
		}
		for k, v in defaults do
			model:SetAttribute(k, v)
		end
		for k, v in attrs or {} do
			model:SetAttribute(k, v)
		end
		local perches = g.Instance.new("Folder")
		perches.Name = "Perches"
		perches.Parent = model
		model.Parent = c.h.workspace
		c.h.game.CollectionService:AddTag(model, "Nest")
		return model
	end

	-- « code.étoiles » des espèces from..to (forme 0, ★1), dans cet ordre
	local function perchData(from, to, step)
		local out = {}
		for s = from, to, step or -1 do
			table.insert(out, `{s}.1`)
		end
		return table.concat(out, ",")
	end

	local function nestScene(c, data)
		local model = fakeNest(c, NEST, { OwnerUserId = 77, PerchCount = 30, PerchData = data })
		placeLocal(c, c.WorldLayout.nestCenter(NEST) + V(0, 3, 0))
		-- pas de 0,1 s : une passe du planificateur par image, tous les perchés construits
		frames(c, 10, 0.1)
		return model
	end

	local function rigs(c, count)
		local out = {}
		for i = 1, count do
			out[i] = c.CR.NestDisplay.perchedRig(NEST, i)
		end
		return out
	end

	-- le rig du perché `i` est rendu, parenté et posé sur son perchoir
	local function shownOnPerch(c, i)
		local rig = c.CR.NestDisplay.perchedRig(NEST, i)
		if rig == nil or rig.lod == "hidden" or rig.model.Parent == nil then
			return false
		end
		local top = c.CR.NestDisplay.perchTop(NEST, i)
		local d = (rig.body.Position - top) * Vector3.new(1, 0, 1)
		return d.Magnitude < 0.5
	end

	describe("Fix r3 client-0 › perchés réordonnés sans clignotement", function()
		it(
			"un Nebby meilleur arrive en tête : les 19 perchés décalés gardent leur rig, aucun ne disparaît",
			function()
				local c = setup()
				local model = nestScene(c, perchData(20, 1))
				local NestDisplay = c.CR.NestDisplay
				expect(NestDisplay.perchedCount(NEST)).toBe(20)
				local before = rigs(c, 20)
				for i = 1, 20 do
					expect(shownOnPerch(c, i)).toBe(true)
				end
				-- juste après une passe du planificateur : la suivante n'arrive qu'après 6 images à 60 i/s
				model:SetAttribute("PerchData", perchData(21, 2))
				for frame = 1, 3 do
					frames(c, 1, 1 / 60)
					expect(NestDisplay.perchedCount(NEST)).toBe(20)
					for i = 2, 20 do
						-- même rig (même espèce), déplacé d'un perchoir ; avant correction : vue recréée sans rig
						expect(NestDisplay.perchedRig(NEST, i) == before[i - 1]).toBe(true)
						expect(shownOnPerch(c, i)).toBe(true)
					end
					-- le nouveau perché est construit dès l'image suivante (passe du planificateur immédiate)
					expect(shownOnPerch(c, 1)).toBe(true)
					expect(NestDisplay.perchedRig(NEST, 1).code).toBe(21)
					if frame == 1 then
						-- le perché sorti (espèce 1) est rendu à la réserve
						expect(before[20].model.Parent).toBeNil()
					end
				end
				expect(#c.h.errors).toBe(0)
			end
		)

		it("perché ajouté en fin de liste : affiché dès l'image suivante", function()
			local c = setup()
			local model = nestScene(c, perchData(10, 1))
			local before = rigs(c, 10)
			model:SetAttribute("PerchData", perchData(10, 1) .. ",21.1")
			frames(c, 1, 1 / 60)
			for i = 1, 11 do
				expect(shownOnPerch(c, i)).toBe(true)
			end
			-- les 10 premiers n'ont pas bougé : rien de reconstruit
			for i = 1, 10 do
				expect(c.CR.NestDisplay.perchedRig(NEST, i) == before[i]).toBe(true)
			end
			expect(c.CR.NestDisplay.perchedRig(NEST, 11).code).toBe(21)
		end)

		it(
			"doublons et changement d'étoiles : réutilisés par (code, étoiles), les autres reconstruits",
			function()
				local c = setup()
				local model = nestScene(c, "3.1,3.1,2.1,1.1")
				local before = rigs(c, 4)
				model:SetAttribute("PerchData", "1.2,3.1,2.1,3.1")
				frames(c, 1, 1 / 60)
				local NestDisplay = c.CR.NestDisplay
				expect(NestDisplay.perchedCount(NEST)).toBe(4)
				for i = 1, 4 do
					expect(shownOnPerch(c, i)).toBe(true)
				end
				-- 3.1 de l'index 2 resté en place ; l'autre 3.1 (index 1) passe à l'index 4 ; 2.1 garde l'index 3
				expect(NestDisplay.perchedRig(NEST, 2) == before[2]).toBe(true)
				expect(NestDisplay.perchedRig(NEST, 4) == before[1]).toBe(true)
				expect(NestDisplay.perchedRig(NEST, 3) == before[3]).toBe(true)
				-- 1.1 → 1.2 : autre rig (étoiles différentes), l'ancien rendu à la réserve
				local first = NestDisplay.perchedRig(NEST, 1)
				expect(first ~= before[4]).toBe(true)
				expect(first.stars).toBe(2)
				expect(before[4].model.Parent).toBeNil()
				-- Nid vidé : tout est rendu
				model:SetAttribute("PerchData", "")
				frames(c, 1, 1 / 60)
				expect(NestDisplay.perchedCount(NEST)).toBe(0)
				local models = 0
				for _, child in c.h.workspace.ClientWorld.Perched:GetChildren() do
					if child.ClassName == "Model" then
						models += 1
					end
				end
				expect(models).toBe(0)
				expect(#c.h.errors).toBe(0)
			end
		)
	end)
end
