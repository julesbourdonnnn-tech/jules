--!nocheck
-- Arrivée silencieuse (lot I, étape 5 ; item M24 du plan I, leçon B5-63 ; GDD §7.5 « jamais au
-- chargement ») : le client COMPLET démarre AVANT le premier EventState, comme sur un vrai serveur (le
-- profil se charge, puis l'état des événements arrive). Le joueur arrive pendant une fête, une fenêtre de
-- météo, un BOOP RUSH, une Jelly Moon et un MEGA posé : rien ne s'annonce (aucun message, aucun son
-- d'annonce, aucune carte, aucune bannière, aucune réaction des squishies) ; un changement APRÈS
-- l'arrivée s'annonce comme avant. Horloge figée, zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

local NOW = 1800000000

-- sons d'annonce : aucun ne doit jouer à l'arrivée (musique et sons d'interface exclus)
local ANNOUNCE = {
	FeteLevel = true,
	LevelUp = true,
	WeatherStart = true,
	Whoosh = true,
	TrickPop = true,
	Pop = true,
	AscendCharge = true,
	AscendBurst = true,
	SplorchCharge = true,
	SplorchPop = true,
	GiftRain = true,
	ConfettiGain = true,
	Coin = true,
}

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function v2All()
		local v2 = {}
		for k, v in UpgradeScreen.V2_ALL do
			v2[k] = v
		end
		v2.Personalities = true
		v2.PhotoMode = true
		return v2
	end

	-- Client complet console, interrupteurs v2.0 tous ouverts, profil arrivé, AUCUN EventState encore
	local function arrive()
		local rec = { sounds = {}, toasts = {} }
		local h = TvAudit.client({
			preset = "full",
			now = NOW,
			profile = { trophies = { [1] = 150, [4] = 1500 } },
			before = function(h)
				local Audio =
					h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.AudioController")
				local play = Audio.play
				Audio.play = function(name, ...)
					table.insert(rec.sounds, name)
					return play(name, ...)
				end
				local Toast = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.Toast")
				-- Toast.message passe par Toast.show : une seule écoute
				local show = Toast.show
				Toast.show = function(text, ...)
					table.insert(rec.toasts, text)
					return show(text, ...)
				end
			end,
		})
		rec.h = h
		rec.P = TvAudit.mod(h, "World.Personality")
		rec.Cards = TvAudit.mod(h, "UI.Cards")
		rec.Banners = TvAudit.mod(h, "UI.Banners")
		rec.FE = TvAudit.mod(h, "World.Fete")
		rec.WX = TvAudit.mod(h, "World.WeatherFx")
		return rec
	end

	local function announced(rec)
		local out = {}
		for _, s in rec.sounds do
			if ANNOUNCE[s] then
				table.insert(out, s)
			end
		end
		return out
	end

	-- EventState du serveur : tout ce qui peut être en cours à l'arrivée
	local function busyState(over)
		local ev = UpgradeScreen.eventState(v2All())
		ev.rush = { active = true, index = 3, endsAt = NOW + 60, nextAt = NOW + 600, moonBoopable = false }
		ev.moon = { active = true, session = 2, endsAt = NOW + 120, nextAt = NOW + 3600 }
		ev.mega.phase = "press"
		ev.mega.index = 4
		ev.mega.landsAt = NOW - 5
		ev.mega.endsAt = NOW + 40
		ev.fete = { level = 3 }
		ev.weather = { kind = 2, endsAt = NOW + 200 }
		ev.features.ambience = true
		for k, v in over or {} do
			ev[k] = v
		end
		return ev
	end

	describe("Arrivée silencieuse (lot I, étape 5, M24)", function()
		it(
			"client démarré AVANT le premier EventState : fête, météo, Rush, Jelly Moon et MEGA déjà en cours à l'arrivée ; aucun message, aucun son d'annonce, aucune carte, aucune bannière, aucune réaction des squishies",
			function()
				local rec = arrive()
				-- avant l'état : rien n'a été vu ni armé
				expect(rec.FE.level()).toBe(0)
				rec.h:fireClient("ReplicatedStorage.Remotes.EventState", busyState())
				TvAudit.tick(rec.h, 3)
				expect(rec.FE.level()).toBe(3)
				expect(rec.WX.kind()).toBe("sprinkles")
				expect(rec.toasts).toEqual({})
				expect(announced(rec)).toEqual({})
				expect(rec.P.stats().reactions).toBe(0)
				expect(rec.P.stats().announced).toBe(0)
				expect(#rec.Cards.pending()).toBe(0)
				expect(rec.Banners.current()).toBeNil()
				expect(table.concat(rec.h.errors, "\n")).toBe("")
				expect(table.concat(rec.h:warnings(), "\n")).toBe("")
			end
		)

		it(
			"après l'arrivée, un changement s'annonce comme avant : la fête monte (message + FeteLevel), un Rush commence (réaction Surpris), un tour est gagné (trick.new)",
			function()
				local rec = arrive()
				local calm = busyState({
					rush = {
						active = false,
						index = 3,
						endsAt = NOW - 1,
						nextAt = NOW + 600,
						moonBoopable = false,
					},
				})
				rec.h:fireClient("ReplicatedStorage.Remotes.EventState", calm)
				TvAudit.tick(rec.h, 1)
				expect(rec.toasts).toEqual({})
				local up = busyState({ fete = { level = 4 } })
				rec.h:fireClient("ReplicatedStorage.Remotes.EventState", up)
				TvAudit.tick(rec.h, 1)
				expect(#rec.toasts).toBe(1)
				expect(table.find(rec.sounds, "FeteLevel") ~= nil or table.find(rec.sounds, "LevelUp") ~= nil).toBe(
					true
				)
				expect(rec.P.stats().reactions >= 1).toBe(true)
				rec.h:fireClient(
					"ReplicatedStorage.Remotes.DataPatch",
					{ trophies = { [1] = 150, [4] = 1500, [2] = 1500 } },
					{}
				)
				TvAudit.tick(rec.h, 1)
				expect(rec.P.stats().announced).toBe(1)
				expect(table.concat(rec.h.errors, "\n")).toBe("")
				expect(table.concat(rec.h:warnings(), "\n")).toBe("")
			end
		)
	end)
end
