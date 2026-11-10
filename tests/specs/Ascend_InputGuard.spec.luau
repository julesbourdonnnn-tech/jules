--!nocheck
-- Ascend_InputGuard (règle 17 du GDD v2.0 §10.8, « Un ✕ n'achète jamais par accident » : « maintien de
-- l'Ascension prolongé : jamais confirmé » ; GDD §4.27 « Le moment », étape 3 ; docs/04 §27.8, §27.10,
-- N24 ; lot B3, étape 2, décisions D7 et D8 du plan B3 ; D26 du lot B2) : le VRAI client console
-- (harnais UpgradeScreen), interrupteurs v2.0 ouverts DANS le test (EventState.features.v2), profil v2 à
-- la condition (Grand Splorch 15 / 15), attribut AscendReady sur MON ranch, personnage dans son ranch.
--   (a) ✕ tenu depuis le rail pendant l'ouverture et 3 s de plus : aucun progrès, aucune carte ;
--   (b) vrai maintien de 3 s → carte « Prêt à monter ? », focus sur « Oui » ; ✕ gardé 3 s de plus : rien ;
--       relâché puis ✕ dans la garde de 0,6 s : rien ; ✕ après la garde : un seul JellyAscend(true) et
--       l'aperçu fermé ;
--   (c) 10 appuis de 100 ms sur le maintien : aucune carte ;
--   (d) ○ sur la carte : rien d'envoyé, carte et aperçu fermés, focus sur l'entrée du rail,
--       ascendDeclined envoyé (ClientMetric, au mieux) ;
--   (e) 20 s sans réponse : carte et aperçu fermés, rien d'envoyé ;
--   (f) interrupteurs coupés : aucun onglet ascend, jamais JellyAscend.
-- Zéro trace : aucune erreur ni avertissement.

local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")
local UpgradeScreen = require("../harness/UpgradeScreen")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local S = UpgradeScreen.new(T.Harness)
	local V2 = UpgradeScreen.V2_ALL
	local NOW = 1800000000
	local SMALL = { a = TvAudit.squishy(1, { z = 10, bf = 1 }) } -- boucle pas prête : l'Ascension seule
	local BIG = { a = TvAudit.squishy(1, { z = 3e15, bf = 1 }), b = TvAudit.squishy(5, { z = 2e15 }) }
	local FROZEN = { G = 0, g = 0, t = NOW }
	local DONE = { step = 11, done = true, demoDone = true }
	local A = Enum.KeyCode.ButtonA
	local B = Enum.KeyCode.ButtonB

	-- client v2.0 à la condition de la 1re Ascension (r = 15 = Record R) ; opts.flags = false : aucune clé
	-- v2 dans EventState ; opts.noSnap : aucun instantané ; opts.ready : AscendReady (vrai par défaut)
	local function client(opts)
		opts = opts or {}
		local snap = S.snap(1, function(p)
			p.R = 15
			p.bestR = 15
			p.ascend = 0
		end)
		local c = S.client({
			snap = if opts.noSnap then nil else snap,
			profile = {
				version = 2,
				squishies = opts.squishies or SMALL,
				growth = FROZEN,
				R = 15,
				onboarding = DONE,
			},
			ranch = if opts.ready == false then {} else { AscendReady = true },
		})
		if opts.flags ~= false then
			S.event(c, V2)
		end
		local WorldLayout = c.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local root = c.h.localPlayer.Character.HumanoidRootPart
		root.CFrame = c.h.globals.CFrame.new(WorldLayout.toWorld(1, Vector3.new(0, 3, 36)))
		S.run(c, 0.2)
		c.SP = TvAudit.mod(c.h, "UI.Panels.SplorchPreview")
		return c
	end

	-- △ puis ✕ (appui court) sur l'entrée de renaissance du rail (« Jelly Ascend ») : l'aperçu s'ouvre au
	-- relâchement, sur l'onglet ascend
	local function fromRail(c)
		c.PC.closeAll()
		S.run(c, 0.5)
		c.PC.toggleMenu()
		S.run(c, 0.5)
		local entry = c.PC.entryButton("SplorchPreview")
		expect(S.selected(c)).toBe(entry)
		expect(entry.Label.Text).toBe("Jelly Ascend")
		Gamepad.press(c.h, A)
		S.run(c, 0.1)
		Gamepad.release(c.h, A)
		S.run(c, 0.05)
		expect(c.PC.current()).toBe("SplorchPreview")
		expect(c.SP.currentTab()).toBe("ascend")
		return entry
	end

	local function sent(c, name)
		return #TvAudit.sent(c.h, name)
	end

	-- points de l'anneau allumés (0 : aucun progrès)
	local function lit(c)
		local n = 0
		for _, d in c.SP._v2().ascendHold.Ring:GetChildren() do
			if d:IsA("Frame") and d.BackgroundTransparency == 0 then
				n += 1
			end
		end
		return n
	end

	-- maintien réel de 3 s sur le bouton (sélectionné, garde d'ouverture passée) : la carte s'ouvre, ✕
	-- encore enfoncé
	local function holdToCard(c)
		local parts = c.SP._v2()
		S.select(c, parts.ascendHold)
		Gamepad.press(c.h, A)
		S.run(c, 3.2)
		expect(c.SP._state().card).toBe(true)
		return parts
	end

	local function metrics(c)
		local out = {}
		for _, args in TvAudit.sent(c.h, "ClientMetric") do
			table.insert(out, tostring(args[1]) .. "=" .. tostring(args[2]))
		end
		return table.concat(out, ",")
	end

	describe(
		"Ascend_InputGuard › maintien de 3 s et carte « Prêt à monter ? » (lot B3, D7, D8)",
		function()
			it(
				"(a) ✕ tenu depuis le rail pendant l'ouverture et 3 s de plus : aucun progrès, aucune carte",
				function()
					local c = client()
					fromRail(c)
					-- ✕ rappuyé aussitôt (garde d'ouverture de la fenêtre) et tenu 3,5 s
					Gamepad.press(c.h, A)
					for _ = 1, 7 do
						S.run(c, 0.5)
						expect(lit(c)).toBe(0)
					end
					expect(c.SP._state().card).toBe(false)
					Gamepad.release(c.h, A)
					S.run(c, 0.5)
					expect(c.SP._state().card).toBe(false)
					-- ✕ enfoncé AVANT que le code ouvre l'aperçu (puce du HUD, carte Conseillé) puis tenu 3,5 s
					c.PC.closeAll()
					S.run(c, 0.5)
					Gamepad.press(c.h, A)
					S.run(c, 0.1)
					c.PC.open("SplorchPreview", "ascend")
					S.run(c, 3.5)
					expect(c.SP.currentTab()).toBe("ascend")
					expect(lit(c)).toBe(0)
					expect(c.SP._state().card).toBe(false)
					Gamepad.release(c.h, A)
					S.run(c, 0.5)
					expect(sent(c, "JellyAscend")).toBe(0)
					S.clean(c, expect)
				end
			)

			it(
				"(b) vrai maintien de 3 s → carte, focus sur « Oui » ; ✕ gardé, puis ✕ dans la garde : rien ; ✕ après : un seul JellyAscend(true), aperçu fermé",
				function()
					local c = client()
					fromRail(c)
					S.run(c, 0.5)
					local parts = holdToCard(c)
					expect(S.selected(c)).toBe(parts.yes)
					expect(parts.card.Visible).toBe(true)
					expect(parts.card.Card.Title.Text).toBe("Ready to rise?")
					expect(parts.later.Label.Text).toBe("Later")
					expect(parts.yes.Label.Text).toBe("Yes, Ascend!")
					-- « Plus tard » à gauche, « Oui » à droite
					expect(parts.later.Position.X.Offset < parts.yes.Position.X.Offset).toBe(true)
					expect(c.SP._state().cardActive).toBe(false)
					-- ✕ gardé 3 s de plus : jamais confirmé, boutons encore grisés
					S.run(c, 3.0)
					expect(sent(c, "JellyAscend")).toBe(0)
					expect(c.SP._state().cardActive).toBe(false)
					-- relâché ; ✕ 0,2 s après, dans la garde de 0,6 s : rien
					Gamepad.release(c.h, A)
					S.run(c, 0.2)
					Gamepad.tap(c.h, A)
					S.run(c, 0.1)
					expect(sent(c, "JellyAscend")).toBe(0)
					expect(c.SP._state().card).toBe(true)
					-- après la garde : boutons actifs, ✕ confirme une seule fois
					S.run(c, 0.6)
					expect(c.SP._state().cardActive).toBe(true)
					expect(S.selected(c)).toBe(parts.yes)
					Gamepad.tap(c.h, A)
					S.run(c, 0.5)
					local list = TvAudit.sent(c.h, "JellyAscend")
					expect(#list).toBe(1)
					expect(list[1][1]).toBe(true)
					expect(c.SP._state().card).toBe(false)
					expect(c.PC.isOpen("SplorchPreview")).toBe(false)
					expect(c.PC.menuOpen()).toBe(false)
					-- d'autres appuis ensuite : rien de plus
					Gamepad.tap(c.h, A)
					S.run(c, 0.5)
					Gamepad.tap(c.h, A)
					S.run(c, 0.5)
					expect(sent(c, "JellyAscend")).toBe(1)
					-- mesures : aperçu ouvert sur l'onglet (0) ; confirmé (2) retenu par le seau partagé (1 / 5 s)
					expect(string.sub(metrics(c), 1, 15)).toBe("ascendPreview=0")
					S.clean(c, expect)
				end
			)

			it("(c) 10 appuis de 100 ms sur le maintien : aucune carte", function()
				local c = client()
				fromRail(c)
				S.run(c, 0.5)
				S.select(c, c.SP._v2().ascendHold)
				for _ = 1, 10 do
					Gamepad.press(c.h, A)
					S.run(c, 0.05)
					Gamepad.release(c.h, A)
					S.run(c, 0.05)
				end
				S.run(c, 1)
				expect(c.SP._state().card).toBe(false)
				expect(lit(c)).toBe(0)
				expect(sent(c, "JellyAscend")).toBe(0)
				S.clean(c, expect)
			end)

			it(
				"(d) ○ sur la carte : rien d'envoyé, carte et aperçu fermés, focus sur l'entrée du rail, ascendDeclined",
				function()
					local c = client()
					local entry = fromRail(c)
					-- le seau des mesures (1 / 5 s) se remplit pendant que l'enfant lit l'aperçu
					S.run(c, 5.5)
					holdToCard(c)
					Gamepad.release(c.h, A)
					S.run(c, 1)
					Gamepad.tap(c.h, B)
					S.run(c, 0.5)
					expect(sent(c, "JellyAscend")).toBe(0)
					expect(c.SP._state().card).toBe(false)
					expect(c.PC.isOpen("SplorchPreview")).toBe(false)
					expect(c.PC.menuOpen()).toBe(true)
					expect(S.selected(c)).toBe(entry)
					expect(metrics(c)).toBe("ascendPreview=0,ascendDeclined=0")
					-- « Plus tard » (✕ sur le bouton de gauche, après la garde) : même chose
					fromRail(c)
					S.run(c, 5.5)
					local parts = holdToCard(c)
					Gamepad.release(c.h, A)
					S.run(c, 1)
					S.select(c, parts.later)
					Gamepad.tap(c.h, A)
					S.run(c, 0.5)
					expect(sent(c, "JellyAscend")).toBe(0)
					expect(c.PC.isOpen("SplorchPreview")).toBe(false)
					expect(S.selected(c)).toBe(entry)
					S.clean(c, expect)
				end
			)

			it("(e) 20 s sans réponse : carte et aperçu fermés, rien d'envoyé", function()
				local c = client()
				fromRail(c)
				S.run(c, 0.5)
				holdToCard(c)
				Gamepad.release(c.h, A)
				S.run(c, 19)
				expect(c.SP._state().card).toBe(true)
				S.run(c, 1.5)
				expect(c.SP._state().card).toBe(false)
				expect(c.PC.isOpen("SplorchPreview")).toBe(false)
				expect(sent(c, "JellyAscend")).toBe(0)
				S.clean(c, expect)
			end)

			it("(f) interrupteurs coupés : aucun onglet ascend, jamais JellyAscend", function()
				-- client de la v1.3 : ni instantané, ni clé v2, ni AscendReady ; Grand Splorch prêt
				local c = client({ flags = false, noSnap = true, ready = false, squishies = BIG })
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(c.PC.entryButton("SplorchPreview").Label.Text).toBe("Grand Splorch")
				Gamepad.tap(c.h, A)
				S.run(c, 0.5)
				expect(c.PC.current()).toBe("SplorchPreview")
				expect(c.SP.tabs()).toEqual({})
				expect(c.SP._state().path).toBe("v13")
				c.PC.open("SplorchPreview", "ascend")
				S.run(c, 0.5)
				expect(c.SP.currentTab()).toBe("")
				Gamepad.tap(c.h, Enum.KeyCode.ButtonR1)
				S.run(c, 0.5)
				expect(c.PC.window("SplorchPreview"):FindFirstChild("AscendConfirm")).toBeNil()
				-- AscendReady posé sans instantané (incohérent) : le chemin de la v1.3 l'ignore
				c.model:SetAttribute("AscendReady", true)
				S.run(c, 0.5)
				c.PC.closeAll()
				S.run(c, 0.5)
				c.PC.toggleMenu()
				S.run(c, 0.5)
				expect(c.PC.entryButton("SplorchPreview").Label.Text).toBe("Grand Splorch")
				expect(sent(c, "JellyAscend")).toBe(0)
				S.noV2Intent(c, expect)
				S.clean(c, expect)
				-- instantané présent, profil v2, AscendReady, mais JellyAscend absent de features.v2 : aucun
				-- onglet ascend, aucune carte, jamais JellyAscend (la boucle reste la seule renaissance montrée)
				local d = client({ squishies = BIG })
				local partial = {}
				for k, v in V2 do
					if k ~= "JellyAscend" then
						partial[k] = v
					end
				end
				S.event(d, partial)
				d.PC.open("SplorchPreview", "ascend")
				S.run(d, 0.5)
				expect(d.SP.tabs()).toEqual({ "splorch" })
				expect(d.SP.currentTab()).toBe("splorch")
				expect(d.SP._v2().ascend).toBeNil()
				expect(sent(d, "JellyAscend")).toBe(0)
				S.clean(d, expect)
			end)
		end
	)
end
