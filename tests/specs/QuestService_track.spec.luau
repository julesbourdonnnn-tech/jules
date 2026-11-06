--!nocheck
-- QuestService v2.0 (lot A4, étape 4 ; GDD v2.0 §7.5, §4.27, §4.29 ; docs/04 §27.2, §27.7 ; décisions
-- D7, D9-D12, D14, D15, D32-D35 du plan du lot A4) : statistiques à vie, jeu des 7 derniers jours, piste
-- de la semaine (2 points par objectif terminé, 5 par Défi, paliers livrés tout seuls dans l'ordre,
-- réclamés après leur récompense), Défis de Splorch (faisables, jamais deux fois, déterministes), Carnet du
-- Ranch, cartes « Bienvenue dans la v2 ! » et « Nouveau », tenues du Record R, étapes du record, jours de
-- givre, puce « Prochain achat », N1 (Record R) ; interrupteurs coupés : profil et envois d'aujourd'hui.
-- Interrupteurs ouverts DANS le test (Features.set) ; SchemaV2 (figé) dans le harnais avant le premier
-- require du schéma (recette de DataChaos). Zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- vendredi 15 janvier 2027, 08:01 UTC (semaine 2975 du lundi 11 janvier)
	local T0 = 1800000000 + 60
	local DAY = 86400
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : v1 (serveur v1 : profils v1), flags (interrupteurs ouverts), t0
	local function boot(opts)
		opts = opts or {}
		local w =
			Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = opts.t0 or T0, stubMeta = false })
		w.Q = w.h:require(S .. "QuestService")
		w.QR = w.h:require(L .. "Logic.QuestRules")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Bitset = w.h:require(L .. "Logic.Bitset")
		w.Quests = w.h:require(L .. "Config.Quests")
		w.Cosmetics = w.h:require(L .. "Config.Cosmetics")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	-- joueur prêt (profil v2 du serveur v2, ou v1 du serveur v1) ; edit(d) avant la sauvegarde
	local function join(w, id, edit, squishies)
		return Brains.join(w, id, {
			profile = Brains.profile(w, {
				squishies = squishies or { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 } },
				edit = edit,
			}),
		})
	end

	local function data(w, p)
		return w.DS.get(p)
	end

	describe("QuestService v2.0 › objectifs du jour et Record R (N1)", function()
		it(
			"remontée après une Ascension : jamais « Fais un Grand Splorch » (un Petit Splorch ne compte pas) ; combo ×2 et Rare suivent le Record R",
			function()
				local w = boot()
				local today = w.Clock.day()
				-- un joueur à qui l'ancien contexte (R = r = 0, Grand Splorch « tout de suite » : le plus gros a
				-- atteint l'objectif de la boucle) donnait l'objectif 16 en relançant la case difficile
				local old = {
					R = 0,
					tilesLeft = 0,
					megaIn = math.huge,
					friendOnServer = false,
					splorchEta = 0,
					stamps = 0,
				}
				local id
				for u = 1, 300 do
					if w.QR.reroll(u, today, { 1, 8, 17 }, 3, old, 1) == 16 then
						id = u
						break
					end
				end
				expect(id ~= nil).toBe(true)
				local p = join(w, id, function(d)
					d.R = 0
					d.bestR = 15
					d.ascend = 1
					d.objectives = {
						day = today,
						list = {
							{ id = 1, p = 0, done = false, claimed = false },
							{ id = 8, p = 0, done = false, claimed = false },
							{ id = 17, p = 0, done = false, claimed = false },
						},
						rerolls = 0,
						allClaimed = false,
					}
				end, { { s = 1, z = 100, bf = 1 }, { s = 2, z = 20000 } })
				expect(w.Prestige.nextKind(data(w, p))).toBe("petit")
				w.RateLimit.clear(p)
				w.h:fireServer(R .. "RerollObjective", p, 3)
				w.h:settle(1)
				local o = data(w, p).objectives
				expect(o.rerolls).toBe(1)
				-- difficile : 14 (combo ×2, Record R ≥ 1), 15 (Rare, Record R ≥ 3) ou 18 ; jamais 16
				local hard = o.list[3].id
				expect({ hard = hard, ok = hard == 14 or hard == 15 or hard == 18 }).toEqual({
					hard = hard,
					ok = true,
				})
				clean(w)
			end
		)
	end)
end
