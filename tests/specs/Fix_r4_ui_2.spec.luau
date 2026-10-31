--!nocheck
-- QA r4 (fixer r4-ui-2) : ScreenFX.
--   1. Celebrate « atlasUnlocked » { count, total } (QuestService.announceUnlock, fin de Q4) : le
--      moment du GDD §3 (« l'Atlas se débloque, page qui tourne, 5/150 », étape 7 de l'entonnoir)
--      était jeté par le client (genre absent de la liste blanche) : ni carte, ni son, ni
--      ScreenFX.Celebrated. Il donne maintenant une carte qui glisse de la droite (la page qui
--      tourne), placée en tête de la file des cartes (jamais perdue derrière les « NOUVEAU ! »), et
--      le son LevelUp quand elle entre ; l'événement est relayé aux abonnés.
--   2. Achat d'amélioration panneau ouvert : aucun son à l'achat (bouton muet, LevelUp seulement
--      dans VFXController.playUpgrade, différé à la fermeture et oublié après 10 s). Le son de l'achat
--      (GDD §9.4 : LevelUp) part maintenant à chaque achat confirmé ; seul l'effet du monde attend,
--      rejoué sans son (playUpgrade(track, level, true)).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local REMOTES = "ReplicatedStorage.Remotes."
	local T0 = 1800000000

	local function fxSetup(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client" })
		h.localPlayer.LocaleId = opts.locale or "en-us"
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
			VFX = h:require(CLIENT .. "Controllers.VFXController"),
			Audio = h:require(CLIENT .. "Controllers.AudioController"),
			FX = h:require(CLIENT .. "UI.ScreenFX"),
			Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies"),
			vfx = {},
			sounds = {},
			celebrated = {},
			open = nil,
		}
		-- isolation : effets du monde et sons remplacés par des enregistreurs
		c.VFX.playUpgrade = function(track, level, silent)
			table.insert(c.vfx, { track = track, level = level, silent = silent })
		end
		c.Audio.play = function(name)
			table.insert(c.sounds, name)
		end
		c.WSC.localSlot = function()
			return 1
		end
		c.WSC.lineLength = function()
			return 0
		end
		c.Root.Init()
		c.State.Init()
		c.Prefs.Init()
		c.Prefs.Start()
		c.FX.Init()
		c.FX.Start()
		c.FX.setPanelResolver(function()
			return c.open
		end)
		c.FX.Celebrated:Connect(function(p)
			table.insert(c.celebrated, p)
		end)
		return c
	end

	local function count(list, value)
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	local function cardTexts(c)
		local out = {}
		for _, card in c.FX._state().cardList do
			table.insert(out, card.frame.Text.Text)
		end
		return out
	end

	local function has(list, value)
		return table.find(list, value) ~= nil
	end

	local function celebrate(c, kind, data)
		c.h:fireClient(REMOTES .. "Celebrate", { kind = kind, data = data })
	end

	-- =============================================================================================
	-- 1. « Star Atlas unlocked! 5/150 »
	-- =============================================================================================
	describe("Fix r4 ui-2 › Celebrate atlasUnlocked : le moment « Atlas débloqué 5/150 »", function()
		it("anglais : carte « Star Atlas unlocked! 5/150 », LevelUp, Celebrated relayé", function()
			local c = fxSetup()
			celebrate(c, "atlasUnlocked", { count = 5, total = 150 })
			local texts = cardTexts(c)
			expect(#texts).toBe(1)
			expect(texts[1]).toBe("Star Atlas unlocked! 5/150")
			expect(count(c.sounds, "LevelUp")).toBe(1)
			-- relayé aux abonnés (accueil : icône Collection, onglet Atlas)
			expect(#c.celebrated).toBe(1)
			expect(c.celebrated[1].kind).toBe("atlasUnlocked")
			expect(c.celebrated[1].data.count).toBe(5)
			expect(c.celebrated[1].data.total).toBe(150)
			-- la carte entre par la droite puis s'en va comme les autres
			c.h:step(0.05, 70) -- 3,5 s
			expect(c.FX._state().cards).toBe(0)
		end)

		it("français : « Star Atlas débloqué ! 5/150 »", function()
			local c = fxSetup({ locale = "fr-fr" })
			celebrate(c, "atlasUnlocked", { count = 5, total = 150 })
			expect(cardTexts(c)[1]).toBe("Star Atlas débloqué ! 5/150")
		end)

		it(
			"pile et file pleines de « NOUVEAU ! » : la carte passe en tête de file, LevelUp quand elle entre",
			function()
				local c = fxSetup()
				-- premier Rare encaissé : 3 cartes à l'écran, 8 en attente (file pleine)
				local entries = {}
				for s = 1, 11 do
					table.insert(entries, { s = s, f = 0 })
				end
				celebrate(c, "atlasNew", { entries = { table.unpack(entries, 1, 8) } })
				celebrate(c, "atlasNew", { entries = { table.unpack(entries, 9, 11) } })
				expect(c.FX._state().cards).toBe(3)
				expect(c.FX._state().queuedCards).toBe(8)
				celebrate(c, "atlasUnlocked", { count = 11, total = 150 })
				-- en attente, pas encore à l'écran : le son attend la carte
				expect(has(cardTexts(c), "Star Atlas unlocked! 11/150")).toBe(false)
				expect(c.FX._state().queuedCards).toBe(8)
				expect(count(c.sounds, "LevelUp")).toBe(0)
				-- les 3 premières cartes partent (~2,95 s) : la carte de l'Atlas entre la première
				c.h:step(0.05, 62)
				local texts = cardTexts(c)
				expect(texts[1]).toBe("Star Atlas unlocked! 11/150")
				expect(count(c.sounds, "LevelUp")).toBe(1)
			end
		)

		it("données invalides : ni carte ni son ; l'événement reste relayé", function()
			local c = fxSetup()
			celebrate(c, "atlasUnlocked", { count = 0 / 0, total = 150 })
			celebrate(c, "atlasUnlocked", { count = 5, total = "150" })
			celebrate(c, "atlasUnlocked", { count = -1, total = 150 })
			celebrate(c, "atlasUnlocked", { count = 5, total = 0 })
			celebrate(c, "atlasUnlocked", { count = 5, total = math.huge })
			celebrate(c, "atlasUnlocked", "junk")
			expect(c.FX._state().cards).toBe(0)
			expect(c.FX._state().queuedCards).toBe(0)
			expect(count(c.sounds, "LevelUp")).toBe(0)
			expect(#c.celebrated).toBe(6)
		end)
	end)

	-- =============================================================================================
	-- 2. Achat d'amélioration : le son ne dépend plus de la fermeture du panneau
	-- =============================================================================================
	describe("Fix r4 ui-2 › achat d'amélioration : son tout de suite, effet du monde différé", function()
		it("panneau Améliorer ouvert : LevelUp à chaque achat confirmé, sans attendre", function()
			local c = fxSetup()
			c.open = "Upgrades"
			celebrate(c, "upgrade", { track = "conga", level = 2 })
			expect(count(c.sounds, "LevelUp")).toBe(1)
			celebrate(c, "upgrade", { track = "stride", level = 1 })
			celebrate(c, "upgrade", { track = "conga", level = 3 })
			expect(count(c.sounds, "LevelUp")).toBe(3)
			-- l'effet du monde attend toujours (sous le voile et le flou)
			expect(#c.vfx).toBe(0)
			-- panneau gardé ouvert plus de 10 s : l'effet est oublié, les sons ont été entendus
			c.h:step(0.25, 44)
			c.open = nil
			c.h:step(1 / 30, 30)
			expect(#c.vfx).toBe(0)
			expect(count(c.sounds, "LevelUp")).toBe(3)
			-- achat refusé ou charge absurde : aucun son
			c.open = "Upgrades"
			celebrate(c, "upgrade", { track = "nope", level = 1 })
			celebrate(c, "upgrade", { track = "conga", level = 0 / 0 })
			expect(count(c.sounds, "LevelUp")).toBe(3)
		end)

		it(
			"effet différé rejoué sans son ; sans panneau, VFXController garde le sien (un seul LevelUp)",
			function()
				local c = fxSetup()
				c.open = "Upgrades"
				celebrate(c, "upgrade", { track = "conga", level = 1 })
				expect(count(c.sounds, "LevelUp")).toBe(1)
				c.open = nil
				c.h:step(1 / 30, 10)
				expect(#c.vfx).toBe(1)
				expect(c.vfx[1].track).toBe("conga")
				expect(c.vfx[1].level).toBe(1)
				-- le son a déjà été joué à l'achat : la reprise est muette
				expect(c.vfx[1].silent).toBe(true)
				-- aucun panneau : effet immédiat, son joué par VFXController (pas de doublon ici)
				celebrate(c, "upgrade", { track = "perches", level = 3 })
				expect(#c.vfx).toBe(2)
				expect(c.vfx[2].silent == true).toBe(false)
				expect(count(c.sounds, "LevelUp")).toBe(1)
			end
		)
	end)
end
