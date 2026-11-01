--!nocheck
-- Correctifs r6 « client-0 » (PanelController) :
--   * contour rose « queue menacée » (panneau ouvert) : la zone protégée des coupes s'applique
--     POINT PAR POINT comme SnipRules.findCut (un point touché dans le port sûr de n'importe quelle
--     porte est ignoré, GDD §4.7) et non selon la position du joueur. Un joueur arrêté dans le port
--     sûr dont la queue dépasse dehors est prévenu ; une queue coupable entièrement dans le port sûr
--     ne déclenche rien, même si le joueur en est sorti (§13.2 : mêmes règles que le serveur)
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000
	local TODAY = math.floor(T0 / 86400)

	local function profile()
		local nebbies = {}
		for i = 1, 12 do
			nebbies["u" .. i] = { s = (i % 5) + 1, f = 0, v = 0, st = 1 }
		end
		return {
			version = 1,
			glow = 500000,
			glowCarry = 0,
			lastSettle = T0,
			lastOnline = T0,
			idleRate = 120,
			stardust = 5000,
			supernovas = 0,
			upgrades = { conga = 0, stride = 0, lure = 0, perches = 2, guard = 0 },
			boosts = { personalUntil = 0 },
			caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
			nebbies = nebbies,
			nextUid = 100,
			perchIncome = 120,
			atlas = { 255, 255, 3, 0, 0, 0, 0 },
			badges = { 0, 0, 0, 0 },
			atlasRewards = 0,
			onboarding = { step = 8, p = 0 },
			daily = { day = TODAY - 1, step = 2 },
			quests = { day = TODAY, list = {}, rerolls = 0, starClaimed = false },
			weekly = { week = 0, banked = 0, claimed = false },
			rookie = { sessions = 3, playSeconds = 4000, done = true },
			settings = {
				zen = false,
				reducedMotion = false,
				lowGraphics = false,
				music = true,
				sfx = true,
				vibration = true,
				autoCrew = true,
				refuseInvites = false,
				lang = "en",
			},
			cosmetics = { style = "default", title = "", nestTheme = "default" },
			unlocks = { styles = {}, titles = {}, themes = {} },
			weeklyBest = { week = 0, conga = 0 },
			starterKit = false,
			stats = {},
			passes = {},
		}
	end

	local function setup()
		local h = Harness.new({ mode = "client" })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local c = {
			h = h,
			Clock = Clock,
			Root = h:require(CLIENT .. "UI.Root"),
			State = h:require(CLIENT .. "Controllers.StateController"),
			Prefs = h:require(CLIENT .. "Util.Prefs"),
			WSC = h:require(CLIENT .. "Controllers.WorldStateController"),
			CR = h:require(CLIENT .. "Controllers.CongaRenderer"),
			PC = h:require(CLIENT .. "Controllers.PanelController"),
			WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout"),
			Balance = h:require("ReplicatedStorage.Shared.Config.Balance"),
		}
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.WSC.Init()
		c.State.Start()
		c.Prefs.Start()
		c.WSC.Start()
		c.PC.Init()
		c.PC.Start()
		h:fireClient(REMOTES .. "DataSnapshot", profile())
		h:settle(1)
		return c
	end

	local function frames(c, n)
		for _ = 1, n do
			c.Clock.advance(0.05)
			c.h:step(0.05, 1)
		end
	end

	local function placeAt(player, pos)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
	end

	local function flat(v)
		return Vector3.new(v.X, 3, v.Z)
	end

	-- Porte du slot 1, direction de la porte vers le centre de l'île (XZ) et perpendiculaire
	local function gateFrame(c)
		local gate = flat(c.WorldLayout.gateCFrame(1).Position)
		local inward = Vector3.new(-gate.X, 0, -gate.Z).Unit
		local side = Vector3.new(-inward.Z, 0, inward.X)
		return gate, inward, side
	end

	-- File locale de `n` Nebbies (slot 1) dont les nœuds rendus sont `nodes`, un rival non équipier
	local function arm(c, nodes)
		local me = c.h.localPlayer
		me:SetAttribute("Slot", 1)
		c.WSC.lineLength = function()
			return #nodes
		end
		c.CR.nodePositions = function(slot)
			return if slot == 1 then nodes else {}
		end
		return c.h:addPlayer({ userId = 7, name = "Rival" })
	end

	describe("Fix r6 client-0 › contour rose : port sûr point par point (SnipRules.findCut)", function()
		it(
			"joueur arrêté dans le port sûr, queue de 15 qui dépasse dehors : alerte (le serveur coupe)",
			function()
				local c = setup()
				local gate, inward, side = gateFrame(c)
				-- à 20 studs de la porte : dans la zone protégée de 25 studs
				local head = gate + inward * 20
				local nodes = {}
				for i = 1, 15 do
					nodes[i] = head + inward * (2.5 * i)
				end
				local other = arm(c, nodes)
				placeAt(c.h.localPlayer, head)
				expect(c.WorldLayout.inHarbor(head)).toBe(true)
				expect(c.WorldLayout.inHarbor(nodes[4])).toBe(false)
				expect(c.WorldLayout.inHarbor(nodes[15])).toBe(false)
				-- rival près du nœud 12, hors du port sûr : la coupe est possible côté serveur
				local near12 = nodes[12] + side * 4
				expect(c.WorldLayout.inHarbor(near12)).toBe(false)
				placeAt(other, near12)
				expect(c.PC._tailThreatened()).toBe(true)
				-- panneau ouvert : le contour rose s'affiche
				c.PC.open("Collection")
				frames(c, 6)
				local warnFrame = c.h.localPlayer.PlayerGui.Panels.TailWarning
				expect(warnFrame.Visible).toBe(true)
				-- rival loin de toute la queue : plus d'alerte
				placeAt(other, nodes[15] + inward * 40)
				frames(c, 6)
				expect(c.PC._tailThreatened()).toBe(false)
				expect(warnFrame.Visible).toBe(false)
				c.PC.close()
			end
		)

		it("queue coupable entièrement dans le port sûr : pas d'alerte, joueur dedans ou dehors", function()
			local c = setup()
			local gate, inward, side = gateFrame(c)
			-- le joueur sort du port sûr (30 studs), sa queue le suit depuis la porte
			local head = gate + inward * 30
			local nodes = {}
			for i = 1, 15 do
				nodes[i] = head - inward * (1.9 * i)
			end
			local other = arm(c, nodes)
			placeAt(c.h.localPlayer, head)
			expect(c.WorldLayout.inHarbor(head)).toBe(false)
			for i = 4, 15 do
				expect(c.WorldLayout.inHarbor(nodes[i])).toBe(true)
			end
			-- rival à côté du nœud 12, dans le port sûr : aucun point de coupe permis
			local near12 = nodes[12] + side * 3
			placeAt(other, near12)
			expect(c.PC._tailThreatened()).toBe(false)
			-- la queue sort du port sûr : l'alerte revient
			for i = 1, 15 do
				nodes[i] = head + inward * (2.5 * i)
			end
			placeAt(other, nodes[8] + side * 3)
			expect(c.PC._tailThreatened()).toBe(true)
			-- joueur dans le port sûr et queue aussi : rien
			head = gate + inward * 4
			placeAt(c.h.localPlayer, head)
			for i = 1, 15 do
				nodes[i] = head + side * (1.2 * i)
			end
			for i = 4, 15 do
				expect(c.WorldLayout.inHarbor(nodes[i])).toBe(true)
			end
			placeAt(other, nodes[10] + inward * 3)
			expect(c.PC._tailThreatened()).toBe(false)
		end)

		it("seuls les points hors du port sûr comptent, Guard Links toujours exclus", function()
			local c = setup()
			local gate, inward, side = gateFrame(c)
			local head = gate + inward * 18
			-- nœuds 1-3 (Guard Links) hors du port sûr, 4-15 de retour dans le port sûr
			local nodes = {}
			for i = 1, 3 do
				nodes[i] = head + inward * (5 + 4 * i)
			end
			for i = 4, 15 do
				nodes[i] = gate + side * (i - 9)
			end
			local other = arm(c, nodes)
			placeAt(c.h.localPlayer, head)
			expect(c.WorldLayout.inHarbor(nodes[3])).toBe(false)
			-- rival près des Guard Links seulement : rien de coupable
			placeAt(other, nodes[3] + side * 3)
			expect(c.PC._tailThreatened()).toBe(false)
			-- un nœud de la queue sort du port sûr : il compte de nouveau
			nodes[15] = gate + inward * 40
			expect(c.WorldLayout.inHarbor(nodes[15])).toBe(false)
			placeAt(other, nodes[15] + side * 3)
			expect(c.PC._tailThreatened()).toBe(true)
		end)

		it("file pas encore rendue : position du joueur, seulement hors du port sûr", function()
			local c = setup()
			local gate, inward, side = gateFrame(c)
			local other = arm(c, {})
			c.WSC.lineLength = function()
				return 8
			end
			-- dans le port sûr : la position du joueur n'est pas un point de coupe
			local inside = gate + inward * 10
			placeAt(c.h.localPlayer, inside)
			placeAt(other, inside + side * 4)
			expect(c.PC._tailThreatened()).toBe(false)
			-- hors du port sûr : repli sur la position du joueur
			local outside = gate + inward * 45
			placeAt(c.h.localPlayer, outside)
			placeAt(other, outside + side * 4)
			expect(c.PC._tailThreatened()).toBe(true)
		end)
	end)
end
