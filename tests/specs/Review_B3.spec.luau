--!nocheck
-- Relecture indépendante du lot B3 (écrans de renaissance et de méta) : défauts réels trouvés par la
-- relecture, chacun montré rouge sur le code du lot avant sa correction (docs/04 §27.12, lignes B3-74
-- et suivantes). Vrai client console (harnais UpgradeScreen), interrupteurs v2.0 ouverts DANS le test
-- (EventState.features.v2), profils et réponses du serveur fabriqués. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")
local MockInstance = require("../harness/MockInstance")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local OWNER = 22

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)
	local V2 = UpgradeScreen.V2_ALL
	local DONE = { step = 11, done = true, demoDone = true }
	local A = Enum.KeyCode.ButtonA

	-- ---------------------------------------------------------------------------------------------
	-- Jumelles (D22) : client v2, mon ranch 1, le voisin OWNER au ranch 2 (attribut BestR)
	-- ---------------------------------------------------------------------------------------------

	local function ranch(slot, userId)
		return {
			slot = slot,
			userId = userId,
			name = "",
			hidden = true,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = 1800000000 },
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
	end

	local function model(c, slot, attrs)
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local world = child(c.h.workspace, "Wobbleton", "Folder")
		local list = child(world, "Ranches", "Folder")
		local m = child(list, tostring(slot), "Model")
		for k, v in attrs do
			m:SetAttribute(k, v)
		end
		return m
	end

	local function binocularsClient()
		local c = S.client({ profile = { version = 2, onboarding = DONE } })
		local me = c.h.localPlayer.UserId
		local mine = ranch(1, me)
		mine.name = "Moi"
		mine.hidden = false
		c.h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = { ["1"] = mine, ["2"] = ranch(2, OWNER), ["3"] = ranch(3, 0) },
			squishies = { ["1"] = {}, ["2"] = {}, ["3"] = {} },
		})
		c.h:settle(1)
		model(c, 2, { BestR = 5 })
		S.event(c, V2)
		c.B = TvAudit.mod(c.h, "UI.Binoculars")
		c.WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		c.h:moveTo(c.h.localPlayer, c.WorldLayout.gateOutside(2))
		S.run(c, 0.3)
		return c
	end

	describe("Review_B3 › jumelles (D22)", function()
		-- Défaut : la fenêtre des jumelles ne suivait pas le départ du propriétaire regardé ; elle restait
		-- ouverte sur « Donner un cœur » devant un ranch vide (ou celui d'un nouveau venu) jusqu'au ✕
		-- suivant. Le rapport de l'étape 5 et la décision D22 disent « fermée tout de suite ».
		it("le propriétaire quitte le serveur fenêtre ouverte : elle se referme tout de suite", function()
			local c = binocularsClient()
			expect(c.B.open(OWNER)).toBe(true)
			expect(c.B.isOpen()).toBe(true)
			-- le serveur libère le ranch 2 (départ du joueur)
			c.h:fireClient("ReplicatedStorage.Remotes.RanchPatch", {
				seq = 2,
				ranches = { ["2"] = { userId = 0 } },
			})
			c.h:settle(1)
			S.run(c, 0.2)
			local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
			expect(WSC.ranch(2).userId).toBe(0)
			expect(c.B.isOpen()).toBe(false)
			expect(c.FG.isOpen("binoculars")).toBe(false)
			-- rien n'est parti, et ✕ ensuite n'envoie rien
			Gamepad.tap(c.h, A)
			c.h:settle(1)
			expect(#S.sent(c, "GiveHeart")).toBe(0)
			S.clean(c, expect)
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	-- Aperçu de la Jelly Ascend (D7, D8) : client v2 à la condition de la 1re Ascension (r = 15)
	-- ---------------------------------------------------------------------------------------------

	local SMALL = { a = TvAudit.squishy(1, { z = 10, bf = 1 }) }
	local FROZEN = { G = 0, g = 0, t = 1800000000 }

	local function ascendClient()
		local snap = S.snap(1, function(p)
			p.R = 15
			p.bestR = 15
			p.ascend = 0
		end)
		local c = S.client({
			snap = snap,
			profile = { version = 2, squishies = SMALL, growth = FROZEN, R = 15, onboarding = DONE },
			ranch = { AscendReady = true },
		})
		S.event(c, V2)
		local WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local root = c.h.localPlayer.Character.HumanoidRootPart
		root.CFrame = c.h.globals.CFrame.new(WorldLayout.toWorld(1, Vector3.new(0, 3, 36)))
		S.run(c, 0.2)
		c.SP = TvAudit.mod(c.h, "UI.Panels.SplorchPreview")
		return c
	end

	-- maintien réel de 3 s : la carte « Prêt à monter ? » s'ouvre, ✕ relâché ensuite
	local function toCard(c)
		c.PC.closeAll()
		S.run(c, 0.5)
		c.PC.open("SplorchPreview", "ascend")
		S.run(c, 0.6)
		expect(c.SP.currentTab()).toBe("ascend")
		local parts = c.SP._v2()
		S.select(c, parts.ascendHold)
		Gamepad.press(c.h, A)
		S.run(c, 3.2)
		Gamepad.release(c.h, A)
		S.run(c, 1)
		expect(c.SP._state().card).toBe(true)
		expect(c.SP._state().cardActive).toBe(true)
		return parts
	end

	describe("Review_B3 › carte « Prêt à monter ? » (D7, D8)", function()
		-- Défaut : la carte ne suivait pas l'Ascension devenue impossible pendant qu'elle était ouverte
		-- (interrupteur JellyAscend coupé en direct, attribut AscendReady retiré) : « Prêt à monter ? » et
		-- « Oui » actif restaient à l'écran jusqu'à 20 s (règle (1) du §27.3 : un système coupé ne montre
		-- rien ; plan B3 §0 : la partie v2 part au rafraîchissement suivant)
		it("JellyAscend coupé en direct, carte ouverte : la carte se ferme, rien n'est envoyé", function()
			local c = ascendClient()
			toCard(c)
			local flags = table.clone(V2)
			flags.JellyAscend = nil
			S.event(c, flags)
			S.run(c, 0.2)
			expect(c.SP._state().card).toBe(false)
			Gamepad.tap(c.h, A)
			S.run(c, 0.5)
			expect(#S.sent(c, "JellyAscend")).toBe(0)
			S.clean(c, expect)
		end)

		-- Défaut (même famille) : onglet ascend seul montré, interrupteur coupé en direct et aucune autre
		-- renaissance prête : la page de la Jelly Ascend (titre, « 9 fois plus vite », icônes gardées)
		-- restait à l'écran jusqu'à ○ ; l'aperçu revient au menu, sans faux « ascendDeclined »
		it("JellyAscend coupé en direct sur l'onglet ascend seul : l'aperçu revient au menu", function()
			local c = ascendClient()
			c.PC.closeAll()
			S.run(c, 0.5)
			c.PC.open("SplorchPreview", "ascend")
			S.run(c, 0.6)
			expect(c.PC.current()).toBe("SplorchPreview")
			expect(c.SP.currentTab()).toBe("ascend")
			local flags = table.clone(V2)
			flags.JellyAscend = nil
			S.event(c, flags)
			S.run(c, 0.5)
			expect(c.PC.current() == "SplorchPreview").toBe(false)
			expect(#S.sent(c, "JellyAscend")).toBe(0)
			for _, args in S.sent(c, "ClientMetric") do
				expect(args[1] == "ascendDeclined").toBe(false)
			end
			S.clean(c, expect)
		end)

		it("AscendReady retiré, carte ouverte : la carte se ferme, rien n'est envoyé", function()
			local c = ascendClient()
			toCard(c)
			c.model:SetAttribute("AscendReady", nil)
			c.h:settle(1)
			S.run(c, 0.2)
			expect(c.SP._state().card).toBe(false)
			Gamepad.tap(c.h, A)
			S.run(c, 0.5)
			expect(#S.sent(c, "JellyAscend")).toBe(0)
			S.clean(c, expect)
		end)
	end)
end
