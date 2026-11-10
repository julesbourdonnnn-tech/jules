--!nocheck
-- CommunityService v2.0 (lot A4, étape 5 ; GDD v2.0 §4.17, §5.4, §7.5, §11.5, Annexe B ; docs/04 §27.5,
-- §27.7 ; décisions D17-D24 du plan du lot A4) : possession par Logic/Owned (sources de la v1.3 :
-- réponses d'aujourd'hui ; sources v2.0 derrière leurs interrupteurs), 14 habillages, palette et coussins
-- (attributs Palette / Cushions), emotes v2.0 de la croix ←, Déco perso (bits de chaque source, cartes,
-- PlaceDeco, attribut DecoPerso), cœurs (refus, Feedback, totaux, jour, 20 par jour, blocage), halo
-- (HaloOn), mode photo (1 000 entrées et sorties, personnage intact) ; interrupteurs coupés : réponses,
-- données et envois de la v1.3. Interrupteurs ouverts DANS le test ; SchemaV2 (figé) dans le harnais
-- avant le premier require du schéma (recette de DataChaos). Zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

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

	-- interrupteurs lus par CommunityService (et Owned) ; RecordR et JellyAscend sont aussi lus ailleurs
	local SOCIAL =
		{ "DecoPerso", "Hearts", "PhotoMode", "RanchSkins", "Workshop", "WeeklyTrack", "Carnet", "Mastery" }
	local ALL = {
		"DecoPerso",
		"Hearts",
		"PhotoMode",
		"RanchSkins",
		"Workshop",
		"WeeklyTrack",
		"Carnet",
		"Mastery",
		"RecordR",
		"JellyAscend",
	}

	-- opts : v1 (serveur v1 : profils v1), flags (interrupteurs ouverts)
	local function boot(opts)
		opts = opts or {}
		local w =
			Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = opts.t0 or T0, stubMeta = false })
		w.C = w.h:require(S .. "CommunityService")
		w.Q = w.h:require(S .. "QuestService")
		w.World = w.h:require(S .. "WorldService")
		w.Owned = w.h:require(L .. "Logic.Owned")
		w.Bitset = w.h:require(L .. "Logic.Bitset")
		w.Prestige = w.h:require(L .. "Logic.Prestige")
		w.Cosmetics = w.h:require(L .. "Config.Cosmetics")
		w.Upgrades = w.h:require(L .. "Config.Upgrades")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.Diag = w.h:require(S .. "DiagnosticsService")
		for _, key in opts.flags or {} do
			assert(w.Features.set(key, true), key)
		end
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
		expect(w.Diag.counts().errors).toBe(0)
	end

	-- joueur prêt ; edit(d) avant la sauvegarde
	local function join(w, id, edit)
		return Brains.join(w, id, {
			profile = Brains.profile(
				w,
				{ squishies = { { s = 1, z = 100, bf = 1 }, { s = 2, z = 50 } }, edit = edit }
			),
		})
	end

	local function data(w, p)
		return w.DS.get(p)
	end

	-- intention envoyée (seau à jetons vidé : la règle du serveur seule décide)
	local function fire(w, name, p, ...)
		w.RateLimit.clear(p)
		w.h:fireServer(R .. name, p, ...)
		w.h:settle(1)
	end

	-- tick de CommunityService après `dt` secondes (relecture des interrupteurs, Déco perso des 30 s)
	local function tick(w, dt)
		w.Clock.advance(dt or 1.1)
		w.C.step(w.Clock.now(), {})
	end

	local function attr(w, p, name)
		local model = w.World.ranchModel(w.Ranch.slotOf(p))
		return model:GetAttribute(name)
	end

	local function patches(w, p)
		w.h:settle(1)
		return #w.h:sentTo(p, "DataPatch")
	end

	-- cartes « unlock » de la Déco perso (identifiants, dans l'ordre)
	local function decoCards(p)
		local out = {}
		for _, d in Bots.celebrations(p, "unlock") do
			if d.kind == "deco" then
				table.insert(out, d.id)
			end
		end
		return out
	end

	local function flagsOf(w)
		return w.Owned.flags(w.Features.get)
	end

	-- liste triée et aplatie (comparaison de deux parties)
	local function ser(v)
		if type(v) == "table" then
			local keys = {}
			for k in v do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			local parts = {}
			for _, k in keys do
				table.insert(parts, tostring(k) .. "=" .. ser(v[k]))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return tostring(v)
	end

	-- règle de la v1.3 (CommunityService.hasCosmetic avant le lot A4), recopiée pour la comparaison
	local function oldRule(w, p, def)
		local d = data(w, p)
		local source = def.source
		if source.kind == "free" then
			return true
		elseif source.kind == "plopDay" then
			return (d.plopDays or 0) >= source.value
		elseif source.kind == "dex" then
			return (d.dex.rewards or 0) >= source.value
		elseif source.kind == "rebirth" then
			return (d.R or 0) >= source.value
		elseif source.kind == "pass" then
			local M = w.h:require(S .. "MonetizationService")
			local ok, owns = pcall(M.ownsPass, p, source.key or "")
			return ok and owns == true
		elseif source.kind == "product" then
			return ((d.outfits.owned or {})[def.id] or 0) > 0
		end
		return false -- weekly : rien débloqué pour la session
	end

	-- ---------------------------------------------------------------------------------------------
	describe("CommunityService v2.0 › possession (Logic/Owned)", function()
		it(
			"sources de la v1.3 : chaque cosmétique de Cosmetics.List répond comme aujourd'hui (profil v1 et v2, tout coupé puis tout ouvert)",
			function()
				local states = {
					{ plopDays = 0, rewards = 0, R = 0, outfit = 0 },
					{ plopDays = 3, rewards = 25, R = 5, outfit = 1 },
					{ plopDays = 21, rewards = 130, R = 10, outfit = 0 },
					{ plopDays = 100, rewards = 260, R = 20, outfit = 2 },
				}
				for _, v1 in { true, false } do
					local w = boot({ v1 = v1 })
					local p = join(w, 1)
					for _, flags in { {}, ALL } do
						w.Features.reset()
						for _, key in flags do
							assert(w.Features.set(key, true), key)
						end
						for _, st in states do
							local d = data(w, p)
							d.plopDays = st.plopDays
							d.dex.rewards = st.rewards
							d.R = st.R
							if d.version >= 2 then
								d.bestR = st.R -- Record R = r : la règle « rebirth » lit le Record R (N1)
							end
							d.outfits.owned.sweater = st.outfit
							for _, def in w.Cosmetics.List do
								local want = oldRule(w, p, def)
								expect({
									v1 = v1,
									k = def.kind .. ":" .. def.id,
									st = st.R,
									has = w.C.hasCosmetic(p, def.kind, def.id),
								}).toEqual({
									v1 = v1,
									k = def.kind .. ":" .. def.id,
									st = st.R,
									has = want,
								})
							end
						end
					end
					-- inconnus, types hostiles : jamais
					expect(w.C.hasCosmetic(p, "saddle", "inconnue")).toBe(false)
					expect(w.C.hasCosmetic(p, "deco", "namePennant")).toBe(false)
					expect(w.C.hasCosmetic(p, 3, "classic")).toBe(false)
					expect(w.C.hasCosmetic(p, "saddle", nil)).toBe(false)
					clean(w)
				end
			end
		)

		it(
			"N1 : titres « rebirth » au Record R (bestR) après une Ascension, profil v1 au R ; titre de la semaine gardé par la session",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.R = 2
					d.bestR = 15
					d.ascend = 1
				end)
				expect(w.C.hasCosmetic(p, "title", "splorch_hero")).toBe(true) -- R15 : Record R
				expect(w.C.hasCosmetic(p, "title", "jelly_titan")).toBe(false)
				expect(w.C.hasCosmetic(p, "title", "stamp_hunter")).toBe(false)
				w.C.unlockSession(p, "title", "stamp_hunter")
				expect(w.C.hasCosmetic(p, "title", "stamp_hunter")).toBe(true)
				local w1 = boot({ v1 = true })
				local q = join(w1, 1, function(d)
					d.R = 10
				end)
				expect(w1.C.hasCosmetic(q, "title", "splorch_legend")).toBe(true)
				expect(w1.C.hasCosmetic(q, "title", "splorch_hero")).toBe(false)
				clean(w)
				clean(w1)
			end
		)

		it(
			"14 habillages par source : les 3 de la v1.3 toujours ; les 11 de la v2.0 seulement profil v2, RanchSkins ET l'interrupteur de leur source ; équipés par EquipCosmetic « theme »",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.R = 20
					d.bestR = 20
					d.ascend = 5
					d.dex.rewards = 160
					d.plopDays = 75
				end)
				local themes = {}
				for _, def in w.Cosmetics.List do
					if def.kind == "theme" then
						table.insert(themes, { id = def.id, v1 = true })
					end
				end
				for _, def in w.Cosmetics.ListV2 do
					if def.kind == "theme" then
						table.insert(themes, { id = def.id, v1 = false, source = def.source.kind })
					end
				end
				expect(#themes).toBe(14)
				local function owned(set)
					w.Features.reset()
					for _, key in set do
						assert(w.Features.set(key, true), key)
					end
					local out = {}
					for _, t in themes do
						if w.C.hasCosmetic(p, "theme", t.id) then
							table.insert(out, t.id)
						end
					end
					return #out
				end
				expect(owned({})).toBe(3)
				expect(owned({ "RecordR", "JellyAscend" })).toBe(3) -- sans RanchSkins
				expect(owned({ "RanchSkins" })).toBe(3) -- sans l'interrupteur des sources
				expect(owned({ "RanchSkins", "RecordR" })).toBe(3 + 8)
				expect(owned({ "RanchSkins", "JellyAscend" })).toBe(3 + 3)
				expect(owned({ "RanchSkins", "RecordR", "JellyAscend" })).toBe(14)
				-- chaque habillage v2.0 exactement à son seuil
				for _, t in themes do
					if not t.v1 then
						local def = w.Cosmetics.ByKindId["theme:" .. t.id]
						expect(def).toBeNil()
					end
				end
				local d = data(w, p)
				d.bestR = 9
				d.R = 9
				d.ascend = 2
				expect(w.C.hasCosmetic(p, "theme", "icedMint")).toBe(true) -- R5
				expect(w.C.hasCosmetic(p, "theme", "lighthouse")).toBe(false) -- R10
				expect(w.C.hasCosmetic(p, "theme", "cloud")).toBe(true) -- A1
				expect(w.C.hasCosmetic(p, "theme", "aurora")).toBe(false) -- A3
				fire(w, "EquipCosmetic", p, "theme", "lighthouse")
				expect(d.cosmetics.theme).toBe("color")
				fire(w, "EquipCosmetic", p, "theme", "icedMint")
				expect(d.cosmetics.theme).toBe("icedMint")
				expect(w.Ranch.publicOf(w.Ranch.slotOf(p)).theme).toBe("icedMint")
				-- profil v1 (serveur v1), tout ouvert : les 3 de la v1.3 seulement
				local w1 = boot({ v1 = true, flags = ALL })
				local q = join(w1, 1, function(x)
					x.R = 20
					x.dex.rewards = 160
					x.plopDays = 75
				end)
				local n = 0
				for _, t in themes do
					if w1.C.hasCosmetic(q, "theme", t.id) then
						n += 1
					end
				end
				expect(n).toBe(3)
				clean(w)
				clean(w1)
			end
		)

		it(
			"cosmétiques v2.0 par source : Record R, A, Atelier, Carnet, semaine, taille, saison ; chaque interrupteur ouvre sa source seulement ; profil v1 jamais",
			function()
				local w = boot()
				local p = join(w, 1)
				local d = data(w, p)
				local cases = {
					{
						k = "saddle",
						id = "confetti",
						flag = "RecordR",
						set = function()
							d.bestR = 2
						end,
					},
					{
						k = "title",
						id = "ascended",
						flag = "JellyAscend",
						set = function()
							d.ascend = 1
						end,
					},
					{
						k = "saddle",
						id = "partyPopper",
						flag = "Workshop",
						set = function()
							w.Bitset.set(d.atelierCosmetics, 7)
						end,
					},
					{
						k = "title",
						id = "builder",
						flag = "Carnet",
						set = function()
							d.stats.upgradesBought = 50
						end,
					},
					{
						k = "saddle",
						id = "cookieSaddle",
						flag = "WeeklyTrack",
						set = function()
							w.Bitset.set(d.weeklyTrack.won, 1)
						end,
					},
					{
						k = "outfit",
						id = "polkaBow",
						flag = "WeeklyTrack",
						set = function()
							w.Bitset.set(d.weeklyTrack.won, 4)
						end,
					},
					{
						k = "saddle",
						id = "cosmic",
						flag = "Mastery",
						set = function()
							d.biggestEver = 1e15
						end,
					},
					{
						k = "emote",
						id = "hammerTap",
						flag = "Carnet",
						set = function()
							d.stats.upgradesBought = 2500
						end,
					},
				}
				for _, c in cases do
					w.Features.reset()
					expect({ id = c.id, before = w.C.hasCosmetic(p, c.k, c.id) }).toEqual({
						id = c.id,
						before = false,
					})
					c.set()
					expect({ id = c.id, off = w.C.hasCosmetic(p, c.k, c.id) }).toEqual({
						id = c.id,
						off = false,
					})
					-- tous les AUTRES interrupteurs ouverts : toujours pas
					for _, other in ALL do
						if other ~= c.flag then
							assert(w.Features.set(other, true), other)
						end
					end
					expect({ id = c.id, others = w.C.hasCosmetic(p, c.k, c.id) }).toEqual({
						id = c.id,
						others = false,
					})
					assert(w.Features.set(c.flag, true), c.flag)
					expect({ id = c.id, on = w.C.hasCosmetic(p, c.k, c.id) }).toEqual({ id = c.id, on = true })
				end
				-- selle « Sucre glace » (costume d'hiver) : 5 jours de givre, sans interrupteur (gagnée pour toujours)
				w.Features.reset()
				d.season.frostDays = 4
				expect(w.C.hasCosmetic(p, "saddle", "icingSugar")).toBe(false)
				d.season.frostDays = w.Owned.FROST_DAYS
				expect(w.C.hasCosmetic(p, "saddle", "icingSugar")).toBe(true)
				-- seuils exacts
				w.Features.set("Mastery", true)
				d.biggestEver = 1e15 - 1
				expect(w.C.hasCosmetic(p, "saddle", "cosmic")).toBe(false)
				-- profil v1, tout ouvert : aucune source v2.0
				local w1 = boot({ v1 = true, flags = ALL })
				local q = join(w1, 1, function(x)
					x.R = 20
					x.plopDays = 200
				end)
				for _, c in cases do
					expect({ id = c.id, v1 = w1.C.hasCosmetic(q, c.k, c.id) }).toEqual({
						id = c.id,
						v1 = false,
					})
				end
				expect(w1.C.hasCosmetic(q, "saddle", "icingSugar")).toBe(false)
				clean(w)
				clean(w1)
			end
		)

		it(
			'palette et coussins : équipés (profil v2, source ouverte), attributs Palette / Cushions, retirés à "" ; refus sans possession, sorte fermée ou profil v1',
			function()
				local w = boot({ flags = { "Workshop" } })
				local p = join(w, 1, function(d)
					d.bestR = 9
					d.R = 9
				end)
				local d = data(w, p)
				expect(attr(w, p, "Palette")).toBe("") -- posé à l'arrivée : la sorte est ouverte (Atelier)
				expect(attr(w, p, "Cushions")).toBeNil() -- coussins : piste de la semaine coupée
				fire(w, "EquipCosmetic", p, "palette", "candy")
				expect(d.cosmetics.palette).toBe("") -- pas achetée
				w.Bitset.set(d.atelierCosmetics, 1) -- ligne « palettes », 1re palette
				fire(w, "EquipCosmetic", p, "palette", "candy")
				expect(d.cosmetics.palette).toBe("candy")
				expect(attr(w, p, "Palette")).toBe("candy")
				fire(w, "EquipCosmetic", p, "palette", "mint") -- 2e palette pas achetée
				expect(d.cosmetics.palette).toBe("candy")
				fire(w, "EquipCosmetic", p, "palette", "fireworks") -- Record R 9, RecordR coupé
				expect(d.cosmetics.palette).toBe("candy")
				assert(w.Features.set("RecordR", true))
				fire(w, "EquipCosmetic", p, "palette", "fireworks")
				expect(d.cosmetics.palette).toBe("fireworks")
				expect(attr(w, p, "Palette")).toBe("fireworks")
				-- semaine : palette « Pêche » (bit 7) et coussins « Nuage rose » (bit 8)
				fire(w, "EquipCosmetic", p, "cushions", "pinkCushions")
				expect(d.cosmetics.cushions).toBe("")
				assert(w.Features.set("WeeklyTrack", true))
				tick(w) -- interrupteur ouvert en direct : attribut Cushions posé
				expect(attr(w, p, "Cushions")).toBe("")
				fire(w, "EquipCosmetic", p, "cushions", "pinkCushions")
				expect(d.cosmetics.cushions).toBe("") -- pas gagnés
				w.Bitset.set(d.weeklyTrack.won, 7)
				w.Bitset.set(d.weeklyTrack.won, 8)
				fire(w, "EquipCosmetic", p, "palette", "peachPalette")
				fire(w, "EquipCosmetic", p, "cushions", "pinkCushions")
				expect(d.cosmetics.palette).toBe("peachPalette")
				expect(d.cosmetics.cushions).toBe("pinkCushions")
				expect(attr(w, p, "Palette")).toBe("peachPalette")
				expect(attr(w, p, "Cushions")).toBe("pinkCushions")
				-- identifiants inconnus ou d'une autre sorte
				fire(w, "EquipCosmetic", p, "palette", "peach")
				fire(w, "EquipCosmetic", p, "cushions", "peachPalette")
				expect(d.cosmetics.palette).toBe("peachPalette")
				expect(d.cosmetics.cushions).toBe("pinkCushions")
				-- retirés
				fire(w, "EquipCosmetic", p, "palette", "")
				fire(w, "EquipCosmetic", p, "cushions", "")
				expect(d.cosmetics.palette).toBe("")
				expect(d.cosmetics.cushions).toBe("")
				expect(attr(w, p, "Palette")).toBe("")
				expect(attr(w, p, "Cushions")).toBe("")
				-- sortes fermées en direct : attributs effacés, équipement (même vide) refusé
				fire(w, "EquipCosmetic", p, "palette", "candy")
				expect(d.cosmetics.palette).toBe("candy")
				w.Features.set("Workshop", false)
				w.Features.set("RecordR", false)
				w.Features.set("WeeklyTrack", false)
				tick(w)
				expect(attr(w, p, "Palette")).toBeNil()
				expect(attr(w, p, "Cushions")).toBeNil()
				local before = patches(w, p)
				fire(w, "EquipCosmetic", p, "palette", "")
				expect(d.cosmetics.palette).toBe("candy")
				expect(patches(w, p)).toBe(before)
				-- profil v1, tout ouvert : refusé, aucune clé créée, aucun attribut
				local w1 = boot({ v1 = true, flags = ALL })
				local q = join(w1, 1)
				local dq = data(w1, q)
				fire(w1, "EquipCosmetic", q, "palette", "")
				fire(w1, "EquipCosmetic", q, "palette", "candy")
				fire(w1, "EquipCosmetic", q, "cushions", "pinkCushions")
				expect(dq.cosmetics.palette).toBeNil()
				expect(dq.cosmetics.cushions).toBeNil()
				expect(attr(w1, q, "Palette")).toBeNil()
				clean(w)
				clean(w1)
			end
		)

		it(
			"emotes v2.0 de la croix ← : SetSetting emoteLeft accepté seulement si Owned la donne ; EmoteShow joue l'emote choisie tant qu'elle est possédée",
			function()
				local w = boot({ flags = { "RecordR" } })
				local p = join(w, 1, function(d)
					d.R = 4
					d.bestR = 4
				end)
				local d = data(w, p)
				fire(w, "SetSetting", p, "emoteLeft", "wave") -- Record R 13
				expect(d.settings.emoteLeft).toBe("bravo")
				fire(w, "SetSetting", p, "emoteLeft", "hugEmote") -- semaine, pas gagnée
				expect(d.settings.emoteLeft).toBe("bravo")
				fire(w, "SetSetting", p, "emoteLeft", "splorch") -- Record R 4
				expect(d.settings.emoteLeft).toBe("splorch")
				fire(w, "Emote", p, 3)
				w.Features.set("WeeklyTrack", true)
				w.Bitset.set(d.weeklyTrack.won, 5)
				fire(w, "SetSetting", p, "emoteLeft", "hugEmote")
				expect(d.settings.emoteLeft).toBe("hugEmote")
				w.Features.set("WeeklyTrack", false) -- source coupée : la croix rejoue Bravo
				w.osClock.advance(2)
				fire(w, "Emote", p, 3)
				local shows = {}
				for _, e in w.h.log.allClientEvents do
					if e.remote == "EmoteShow" and e.args[1].userId == p.UserId then
						table.insert(shows, e.args[1].emote)
					end
				end
				expect(shows).toEqual({ "splorch", "cheer" })
				-- valeur hors liste : refusée par Config/Settings
				fire(w, "SetSetting", p, "emoteLeft", "polkaBow")
				expect(d.settings.emoteLeft).toBe("hugEmote")
				clean(w)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CommunityService v2.0 › Déco perso [DecoPerso]", function()
		it(
			"possession par source (fanion des 5 min, Squishydex, jours de Plop, objectifs, Jelly Moon, pistes, Carnet, Atelier) : bits posés une fois, une carte « unlock » par objet gagné (1-16), aucune pour l'Atelier",
			function()
				local w = boot({ flags = { "DecoPerso" } })
				local p = join(w, 1, function(d)
					d.stats.playSeconds = 280
				end)
				local d = data(w, p)
				local owned = d.decoPerso.owned
				expect(w.Bitset.count(owned)).toBe(0)
				-- fanion à 5:00 de jeu, vu dans les 30 s
				w.Clock.advance(31)
				w.Q.step(w.Clock.now())
				expect(d.stats.playSeconds >= 300).toBe(true)
				w.C.step(w.Clock.now(), {})
				expect(w.Bitset.has(owned, 1)).toBe(true)
				expect(decoCards(p)).toEqual({ "namePennant" })
				-- Squishydex : 260 tampons → objets 2 à 6 (Stamped)
				for s = 1, #w.Species.List do
					d.dex.mut[s] = 0x3FF
				end
				w.Signals.Stamped:Fire(p, 1)
				for n = 2, 6 do
					expect({ n = n, owned = w.Bitset.has(owned, n) }).toEqual({ n = n, owned = true })
				end
				-- jours de Plop (Fed) : 7 → gamelle ; 29 : pas de hamac
				d.plopDays = 29
				w.Signals.Fed:Fire(p, 29)
				expect(w.Bitset.has(owned, 7)).toBe(true)
				expect(w.Bitset.has(owned, 8)).toBe(false)
				-- objectifs : le 25e réclamé (compteur à vie de QuestService) → cloche
				d.stats.objectivesClaimed = 24
				d.objectives = {
					day = w.Clock.day(),
					list = { { id = 1, p = 99, done = true, claimed = false } },
					rerolls = 0,
					allClaimed = false,
				}
				fire(w, "ClaimObjective", p, 1)
				expect(d.stats.objectivesClaimed).toBe(25)
				expect(w.Bitset.has(owned, 9)).toBe(true)
				-- Jelly Moon : Goutte de Lune (moon.sessions compté juste avant)
				d.moon.sessions = 1
				w.Signals.SquishyObtained:Fire(p, "1", "lunar")
				expect(w.Bitset.has(owned, 11)).toBe(true)
				expect(w.Bitset.has(owned, 12)).toBe(false)
				-- Carnet du Ranch : 750 niveaux (UpgradeBought → compteur à vie)
				d.stats.upgradesBought = 749
				w.Signals.UpgradeBought:Fire(p, "gloves", 0, 1, "coins")
				expect(d.stats.upgradesBought).toBe(750)
				expect(w.Bitset.has(owned, 15)).toBe(true)
				-- 1re piste finie : vue des 30 s
				d.stats.tracksDone = 1
				tick(w, 31)
				expect(w.Bitset.has(owned, 13)).toBe(true)
				-- Atelier : 3 objets de la ligne decoShop achetés → 17, 18, 19, sans carte
				d.atelier[w.Upgrades.WorkshopIndex.decoShop] = 3
				w.Signals.UpgradeBought:Fire(p, "decoShop", 2, 3, "confetti")
				for n = 17, 19 do
					expect({ n = n, owned = w.Bitset.has(owned, n) }).toEqual({ n = n, owned = true })
				end
				expect(w.Bitset.has(owned, 20)).toBe(false)
				expect(decoCards(p)).toEqual({
					"namePennant",
					"plopBench",
					"pinkLantern",
					"wateringCan",
					"mochiStatue",
					"goldFountain",
					"plopBowl",
					"morningBell",
					"plushMoon",
					"workbench",
					"ribbonChest",
				})
				-- une seule fois : rien de plus aux vues suivantes
				tick(w, 31)
				w.Signals.Stamped:Fire(p, 1)
				expect(#decoCards(p)).toBe(11)
				-- Owned dit la même chose que les bits
				for n = 1, 40 do
					expect({ n = n, same = w.Owned.deco(d, n, flagsOf(w)) == w.Bitset.has(owned, n) }).toEqual({
						n = n,
						same = true,
					})
				end
				clean(w)
			end
		)

		it(
			"ancien joueur à sa migration (carte « Bienvenue » en attente) : objets déjà gagnés posés sans carte ; un objet gagné ensuite : sa carte",
			function()
				local w = boot({ flags = { "DecoPerso" } })
				local p = join(w, 1, function(d)
					d.onboarding.welcomeV2Pending = true
					d.plopDays = 30
					d.stats.playSeconds = 3600
				end)
				local d = data(w, p)
				for _, n in { 1, 7, 8 } do
					expect({ n = n, owned = w.Bitset.has(d.decoPerso.owned, n) }).toEqual({
						n = n,
						owned = true,
					})
				end
				expect(#decoCards(p)).toBe(0)
				d.stats.objectivesClaimed = 100
				tick(w, 31)
				expect(decoCards(p)).toEqual({ "morningBell", "toyBox" })
				clean(w)
			end
		)

		it(
			"PlaceDeco : objet possédé, de la taille de l'emplacement (8 petits puis 4 grands), jamais posé deux fois, 0 retire ; attribut DecoPerso (12 numéros) à l'arrivée et à chaque changement ; refus sans mutation",
			function()
				local w = boot({ flags = { "DecoPerso" } })
				local p = join(w, 1, function(d)
					d.plopDays = 7
					d.stats.playSeconds = 3600
					d.dex.mut[1] = 0x3FF
					d.dex.mut[2] = 0x3FF
					d.dex.mut[3] = 0x3FF
				end)
				local d = data(w, p)
				local slots = d.decoPerso.slots
				expect(attr(w, p, "DecoPerso")).toBe("0,0,0,0,0,0,0,0,0,0,0,0")
				-- possédés : 1 (fanion, P), 2 (banc, P, 25 tampons), 7 (gamelle, P) ; 6 (fontaine, G) non
				fire(w, "PlaceDeco", p, 1, 1)
				expect(slots[1]).toBe(1)
				expect(attr(w, p, "DecoPerso")).toBe("1,0,0,0,0,0,0,0,0,0,0,0")
				local function refused(item, slot)
					local before = ser(d.decoPerso)
					local n = patches(w, p)
					fire(w, "PlaceDeco", p, item, slot)
					expect({ item = item, slot = slot, same = ser(d.decoPerso) == before }).toEqual({
						item = item,
						slot = slot,
						same = true,
					})
					expect({ item = item, slot = slot, patches = patches(w, p) }).toEqual({
						item = item,
						slot = slot,
						patches = n,
					})
				end
				refused(1, 2) -- déjà posé ailleurs
				refused(2, 9) -- petit objet sur un grand emplacement
				refused(6, 9) -- pas possédé
				refused(3, 3) -- pas possédé (50 tampons)
				refused(41, 1) -- objet inconnu
				refused(64, 12)
				refused(0, 5) -- emplacement déjà vide
				refused(1, 1) -- déjà là
				-- grand objet : 260 tampons → fontaine (G) ; petit emplacement refusé, grand accepté
				for s = 1, #w.Species.List do
					d.dex.mut[s] = 0x3FF
				end
				refused(6, 8)
				fire(w, "PlaceDeco", p, 6, 9) -- source gagnée depuis la dernière vue : bit posé avec sa carte
				expect(slots[9]).toBe(6)
				expect(w.Bitset.has(d.decoPerso.owned, 6)).toBe(true)
				expect(table.find(decoCards(p), "goldFountain") ~= nil).toBe(true)
				-- remplacé : l'objet 1 quitte l'emplacement 1, il peut aller ailleurs
				fire(w, "PlaceDeco", p, 7, 1)
				fire(w, "PlaceDeco", p, 1, 2)
				expect(slots[1]).toBe(7)
				expect(slots[2]).toBe(1)
				-- Atelier : objet 17 acheté (ligne decoShop) puis posé : bit posé, sans carte
				d.atelier[w.Upgrades.WorkshopIndex.decoShop] = 1
				fire(w, "PlaceDeco", p, 17, 8)
				expect(slots[8]).toBe(17)
				expect(table.find(decoCards(p), "mushroom")).toBeNil()
				-- retirer
				fire(w, "PlaceDeco", p, 0, 9)
				expect(slots[9]).toBe(0)
				expect(attr(w, p, "DecoPerso")).toBe("7,1,0,0,0,0,0,17,0,0,0,0")
				-- tailles des emplacements : 8 petits puis 4 grands (contrat, GDD §11.5)
				expect(w.Cosmetics.DecoSlots).toEqual({
					"P",
					"P",
					"P",
					"P",
					"P",
					"P",
					"P",
					"P",
					"G",
					"G",
					"G",
					"G",
				})
				-- à la reconnexion : attribut reposé depuis la sauvegarde
				Bots.leave(p)
				w.h:settle(3)
				local back = Brains.join(w, 1, {})
				expect(attr(w, back, "DecoPerso")).toBe("7,1,0,0,0,0,0,17,0,0,0,0")
				clean(w)
			end
		)

		it(
			"Déco perso coupée ou profil v1 : rien d'écrit, aucun attribut, aucune carte, PlaceDeco refusé",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.plopDays = 30
				end)
				local d = data(w, p)
				local before = ser(d.decoPerso)
				fire(w, "PlaceDeco", p, 1, 1)
				w.Signals.Fed:Fire(p, 30)
				tick(w, 31)
				expect(ser(d.decoPerso)).toBe(before)
				expect(attr(w, p, "DecoPerso")).toBeNil()
				expect(#decoCards(p)).toBe(0)
				-- Owned : rien n'est gagné tant que DecoPerso est coupé (le client « Mon style » lit la même règle)
				expect(w.Owned.deco(d, 7, flagsOf(w))).toBe(false)
				expect(w.Owned.deco(d, 7, { DecoPerso = true })).toBe(true)
				expect(w.Owned.deco(d, 7, nil)).toBe(false)
				-- ouvert en direct : bits revus, attribut posé
				assert(w.Features.set("DecoPerso", true))
				tick(w)
				expect(w.Bitset.has(d.decoPerso.owned, 7)).toBe(true)
				expect(attr(w, p, "DecoPerso")).toBe("0,0,0,0,0,0,0,0,0,0,0,0")
				-- coupé en direct : attribut effacé
				w.Features.set("DecoPerso", false)
				tick(w)
				expect(attr(w, p, "DecoPerso")).toBeNil()
				-- profil v1, ouvert
				local w1 = boot({ v1 = true, flags = { "DecoPerso" } })
				local q = join(w1, 1, function(x)
					x.plopDays = 30
				end)
				fire(w1, "PlaceDeco", q, 1, 1)
				w1.Signals.Fed:Fire(q, 30)
				tick(w1, 31)
				expect(data(w1, q).decoPerso).toBeNil()
				expect(attr(w1, q, "DecoPerso")).toBeNil()
				expect(#decoCards(q)).toBe(0)
				-- interrupteurs des attributs ouverts en direct : un profil v1 n'en reçoit aucun
				for _, key in { "RanchSkins", "Workshop", "WeeklyTrack", "RecordR" } do
					assert(w1.Features.set(key, true), key)
				end
				tick(w1)
				for _, name in { "DecoPerso", "HaloOn", "Palette", "Cushions" } do
					expect({ name = name, value = attr(w1, q, name) }).toEqual({ name = name, value = nil })
				end
				clean(w)
				clean(w1)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CommunityService v2.0 › cœurs [Hearts]", function()
		it(
			"GiveHeart : hearts.given au donneur, hearts.received { name } au propriétaire, totaux ; un par ranch et par jour UTC ; le jour suivant, à nouveau",
			function()
				local w = boot({ flags = { "Hearts" } })
				local a = join(w, 1)
				local b = join(w, 2)
				local da, db = data(w, a), data(w, b)
				local fa, fb = #Bots.feedbackKeys(a), #Bots.feedbackKeys(b)
				local function since(p, n)
					local keys = Bots.feedbackKeys(p)
					return { table.unpack(keys, n + 1) }
				end
				fire(w, "GiveHeart", a, b.UserId)
				expect(da.hearts.givenDay).toBe(w.Clock.day())
				expect(da.hearts.givenTo).toEqual({ 2 })
				expect(db.hearts.receivedTotal).toBe(1)
				expect(da.hearts.receivedTotal).toBe(0)
				expect(since(a, fa)).toEqual({ "hearts.given" })
				expect(since(b, fb)).toEqual({ "hearts.received" })
				local list0 = w.h:sentTo(b, "Feedback")
				local received = list0[#list0][1]
				expect(received.vars.name).toBe(w.C.displayName(a))
				expect(received.vars.name ~= "").toBe(true)
				expect(received.tone).toBe("reward")
				-- même ranch le même jour : refus muet
				fire(w, "GiveHeart", a, b.UserId)
				expect(db.hearts.receivedTotal).toBe(1)
				expect(#since(a, fa)).toBe(1)
				-- l'autre sens : permis (un cœur par ranch, pas par paire)
				fire(w, "GiveHeart", b, a.UserId)
				expect(da.hearts.receivedTotal).toBe(1)
				-- jour UTC suivant : à nouveau, liste du jour remise à zéro
				w.Clock.advance(DAY)
				fire(w, "GiveHeart", a, b.UserId)
				expect(da.hearts.givenDay).toBe(w.Clock.day())
				expect(da.hearts.givenTo).toEqual({ 2 })
				expect(db.hearts.receivedTotal).toBe(2)
				-- « Cacher mon nom » : le nom envoyé est vide (le client écrit l'alias)
				fire(w, "SetSetting", a, "hideName", true)
				w.Clock.advance(DAY)
				fire(w, "GiveHeart", a, b.UserId)
				local list = w.h:sentTo(b, "Feedback")
				expect(list[#list][1].vars.name).toBe("")
				-- aucun compteur public (attribut ou champ public du ranch)
				expect(attr(w, b, "Hearts")).toBeNil()
				expect(w.Ranch.publicOf(w.Ranch.slotOf(b)).hearts).toBeNil()
				clean(w)
			end
		)

		it(
			"refus : soi, absent, inconnu, bloqué dans un sens ou l'autre, interrupteur coupé, profil v1 — rien d'écrit, aucun Feedback",
			function()
				local w = boot()
				local a = join(w, 1)
				local b = join(w, 2)
				local da, db = data(w, a), data(w, b)
				local function none(giver, ownerId)
					local ha, hb = ser(da.hearts), ser(db.hearts)
					local fa, fb = #Bots.feedbackKeys(a), #Bots.feedbackKeys(b)
					fire(w, "GiveHeart", giver, ownerId)
					expect(ser(da.hearts)).toBe(ha)
					expect(ser(db.hearts)).toBe(hb)
					expect(#Bots.feedbackKeys(a)).toBe(fa)
					expect(#Bots.feedbackKeys(b)).toBe(fb)
				end
				none(a, b.UserId) -- interrupteur coupé
				assert(w.Features.set("Hearts", true))
				none(a, a.UserId) -- soi
				none(a, 999) -- absent
				none(a, 0) -- inconnu (type refusé)
				fire(w, "ReportBlocked", b, { a.UserId }) -- b bloque a
				none(a, b.UserId)
				none(b, a.UserId)
				fire(w, "ReportBlocked", b, {})
				fire(w, "ReportBlocked", a, { b.UserId }) -- a bloque b
				none(a, b.UserId)
				fire(w, "ReportBlocked", a, {})
				fire(w, "GiveHeart", a, b.UserId) -- débloqués : accepté
				expect(db.hearts.receivedTotal).toBe(1)
				-- profil v1 (serveur v1), interrupteur ouvert : refusé, aucune clé
				local w1 = boot({ v1 = true, flags = { "Hearts" } })
				local c = join(w1, 1)
				local e = join(w1, 2)
				fire(w1, "GiveHeart", c, e.UserId)
				expect(data(w1, c).hearts).toBeNil()
				expect(data(w1, e).hearts).toBeNil()
				expect(#Bots.feedbackKeys(c)).toBe(0)
				clean(w)
				clean(w1)
			end
		)

		it(
			"20 cœurs par jour : au 21e ranch, hearts.limit et rien d'écrit ; le jour suivant, à nouveau",
			function()
				local w = boot({ flags = { "Hearts" } })
				local a = join(w, 1)
				local b = join(w, 2)
				local da, db = data(w, a), data(w, b)
				-- 19 ranchs servis plus tôt aujourd'hui (propriétaires partis depuis)
				da.hearts.givenDay = w.Clock.day()
				for i = 1, 19 do
					table.insert(da.hearts.givenTo, 1000 + i)
				end
				fire(w, "GiveHeart", a, b.UserId) -- 20e : accepté
				expect(#da.hearts.givenTo).toBe(20)
				expect(db.hearts.receivedTotal).toBe(1)
				local c = join(w, 3)
				fire(w, "GiveHeart", a, c.UserId) -- 21e : refusé, hearts.limit
				expect(#da.hearts.givenTo).toBe(20)
				expect(data(w, c).hearts.receivedTotal).toBe(0)
				local keys = Bots.feedbackKeys(a)
				expect(keys[#keys]).toBe("hearts.limit")
				expect(#Bots.feedbackKeys(c)).toBe(0)
				w.Clock.advance(DAY)
				fire(w, "GiveHeart", a, c.UserId)
				expect(data(w, c).hearts.receivedTotal).toBe(1)
				expect(da.hearts.givenTo).toEqual({ 3 })
				clean(w)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CommunityService v2.0 › halo et mode photo", function()
		it(
			"halo : attribut HaloOn = settings.haloOn (profil v2, RanchSkins) posé à l'arrivée et à chaque SetSetting ; absent coupé ; effacé quand RanchSkins se coupe en direct",
			function()
				local w = boot({ flags = { "RanchSkins" } })
				local p = join(w, 1)
				expect(attr(w, p, "HaloOn")).toBe(true)
				fire(w, "SetSetting", p, "haloOn", false)
				expect(data(w, p).settings.haloOn).toBe(false)
				expect(attr(w, p, "HaloOn")).toBe(false)
				w.Features.set("RanchSkins", false)
				tick(w)
				expect(attr(w, p, "HaloOn")).toBeNil()
				w.Features.set("RanchSkins", true)
				tick(w)
				expect(attr(w, p, "HaloOn")).toBe(false)
				-- reconnexion : reposé depuis la sauvegarde
				Bots.leave(p)
				w.h:settle(3)
				local back = Brains.join(w, 1, {})
				expect(attr(w, back, "HaloOn")).toBe(false)
				-- coupé à l'arrivée : absent
				local w2 = boot()
				local q = join(w2, 1)
				expect(attr(w2, q, "HaloOn")).toBeNil()
				clean(w)
				clean(w2)
			end
		)

		it(
			"mode photo : 1 000 entrées et sorties, personnage toujours visible (Transparency, Anchored et Parent inchangés), aucune donnée, état effacé au départ, analytique cumulée",
			function()
				local w = boot({ flags = { "PhotoMode" } })
				local p = join(w, 1)
				local Analytics = w.h:require("ServerScriptService.Server.Util.Analytics")
				local logged = 0
				local original = Analytics.custom
				Analytics.custom = function(player, name, value, ...)
					if name == "PhotoMode" then
						logged += value
					end
					return original(player, name, value, ...)
				end
				local char = p.Character
				local function look()
					local out = {}
					for _, part in char:GetDescendants() do
						if part:IsA("BasePart") then
							table.insert(
								out,
								part.Name
									.. ":"
									.. tostring(part.Transparency)
									.. ":"
									.. tostring(part.Anchored)
									.. ":"
									.. tostring(part.Parent ~= nil)
							)
						end
					end
					table.sort(out)
					return table.concat(out, "|")
				end
				local before = look()
				expect(#before > 0).toBe(true)
				local parent = char.Parent
				expect(parent ~= nil).toBe(true)
				local profile = ser(data(w, p))
				local patchesBefore = patches(w, p)
				for i = 1, 1000 do
					w.RateLimit.clear(p)
					w.h:fireServer(R .. "SetPhotoMode", p, i % 2 == 1)
					if w.C.inPhotoMode(p) ~= (i % 2 == 1) then
						error("mode photo faux à l'essai " .. i)
					end
				end
				expect(look()).toBe(before)
				expect(p.Character).toBe(char)
				expect(char.Parent).toBe(parent)
				expect(Bots.rootOf(p) ~= nil).toBe(true)
				expect(ser(data(w, p))).toBe(profile)
				expect(patches(w, p)).toBe(patchesBefore)
				-- deux fois le même état : refusé
				fire(w, "SetPhotoMode", p, true)
				fire(w, "SetPhotoMode", p, true)
				expect(w.C.inPhotoMode(p)).toBe(true)
				-- 501 entrées comptées, envoyées au plus toutes les 5 min, puis au départ
				tick(w, 301)
				expect(logged).toBe(501)
				Bots.leave(p)
				w.h:settle(2)
				expect(w.C.inPhotoMode(p)).toBe(false)
				Analytics.custom = original
				-- interrupteur coupé : refusé (rien de gardé : l'ouvrir ensuite ne met pas le joueur en mode photo)
				local w2 = boot()
				local q = join(w2, 1)
				fire(w2, "SetPhotoMode", q, true)
				expect(w2.C.inPhotoMode(q)).toBe(false)
				assert(w2.Features.set("PhotoMode", true))
				expect(w2.C.inPhotoMode(q)).toBe(false)
				fire(w2, "SetPhotoMode", q, false) -- déjà sorti : refusé
				fire(w2, "SetPhotoMode", q, true)
				expect(w2.C.inPhotoMode(q)).toBe(true)
				clean(w)
				clean(w2)
			end
		)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("CommunityService v2.0 › interrupteurs coupés : le jeu d'aujourd'hui", function()
		-- partie sociale jouée : cosmétiques, réglages, emotes, intentions v2.0, signaux des sources
		local function play(w, p, q)
			fire(w, "EquipCosmetic", p, "saddle", "peach")
			fire(w, "EquipCosmetic", p, "title", "splorch_star")
			fire(w, "EquipCosmetic", p, "palette", "candy")
			fire(w, "EquipCosmetic", p, "palette", "")
			fire(w, "SetSetting", p, "emoteLeft", "bellyFlop")
			fire(w, "SetSetting", p, "emoteLeft", "splorch")
			fire(w, "SetSetting", p, "haloOn", false)
			fire(w, "Emote", p, 3)
			fire(w, "PlaceDeco", p, 1, 1)
			fire(w, "GiveHeart", p, q.UserId)
			fire(w, "SetPhotoMode", p, true)
			w.Signals.Fed:Fire(p, 10)
			w.Signals.Stamped:Fire(p, 3)
			w.Signals.UpgradeBought:Fire(p, "decoShop", 0, 1, "confetti")
			tick(w, 31)
			fire(w, "SetPhotoMode", p, false)
			tick(w, 31)
		end

		-- v2.0 (lot B3, INT-B3-FEATURES, docs/04 §27.5, journal B3-82) : chaque EventState porte
		-- features.v2, les interrupteurs ouverts de la liste fixe du client, quel que soit le profil (le
		-- client d'un profil v1 n'en montre et n'en envoie rien, UI/MetaFlags.v2Profile) ; mis à part de la
		-- comparaison à l'octet près (copie : l'envoi journalisé n'est pas touché) et vérifié tel quel
		local function withoutV2(e)
			local payload = e.args[1]
			if e.remote ~= "EventState" or type(payload) ~= "table" or type(payload.features) ~= "table" then
				return e.args, nil
			end
			local features = table.clone(payload.features)
			local v2 = features.v2
			features.v2 = nil
			local copy = table.clone(payload)
			copy.features = features
			local args = table.clone(e.args)
			args[1] = copy
			return args, v2
		end
		-- SOCIAL sans PhotoMode (hors de la liste du client)
		local SOCIAL_ANNOUNCED = ser({
			Carnet = true,
			DecoPerso = true,
			Hearts = true,
			Mastery = true,
			RanchSkins = true,
			WeeklyTrack = true,
			Workshop = true,
		})

		local function run(flags)
			local w = boot({ v1 = true, flags = flags })
			local p = join(w, 1, function(d)
				d.plopDays = 10
				d.R = 5
			end)
			local q = join(w, 2)
			play(w, p, q)
			local sent, announced = {}, {}
			for _, e in w.h.log.clientEvents do
				if e.player == p or e.player == q then
					local args, v2 = withoutV2(e)
					if e.remote == "EventState" then
						table.insert(announced, ser(v2))
					end
					table.insert(sent, e.remote .. ser(args))
				end
			end
			local out =
				{ profile = ser(data(w, p)), other = ser(data(w, q)), sent = sent, announced = announced }
			for _, name in { "DecoPerso", "HaloOn", "Palette", "Cushions" } do
				expect({ name = name, value = attr(w, p, name) }).toEqual({ name = name, value = nil })
			end
			clean(w)
			return out
		end

		it(
			"profil v1 : interrupteurs du lot ouverts ou coupés, mêmes données et mêmes envois (à l'octet près ; EventState.features.v2 annonce exactement les interrupteurs ouverts)",
			function()
				local off = run({})
				local on = run(SOCIAL)
				expect(on.profile).toBe(off.profile)
				expect(on.other).toBe(off.other)
				expect(#on.sent).toBe(#off.sent)
				for i, line in off.sent do
					expect({ i = i, line = on.sent[i] }).toEqual({ i = i, line = line })
				end
				-- features.v2 (INT-B3-FEATURES) : absente coupé ; ouvert, exactement les interrupteurs du lot
				-- que le client doit connaître (PhotoMode n'est pas de la liste), à chaque EventState
				expect(#off.announced > 0).toBe(true)
				expect(#on.announced).toBe(#off.announced)
				for i, v2 in off.announced do
					expect({ i = i, v2 = v2 }).toEqual({ i = i, v2 = "nil" })
					expect({ i = i, v2 = on.announced[i] }).toEqual({ i = i, v2 = SOCIAL_ANNOUNCED })
				end
			end
		)

		it(
			"profil v2, tout coupé : Déco perso, cœurs, palette, halo jamais écrits, aucun attribut v2 de ce service, aucune carte « deco »",
			function()
				local w = boot()
				local p = join(w, 1, function(d)
					d.plopDays = 30
					d.bestR = 9
					d.R = 9
					d.atelier[w.Upgrades.WorkshopIndex.decoShop] = 2
				end)
				local q = join(w, 2)
				local d = data(w, p)
				local before = ser({
					deco = d.decoPerso,
					hearts = d.hearts,
					other = data(w, q).hearts,
					palette = d.cosmetics.palette,
					cushions = d.cosmetics.cushions,
					halo = d.settings.haloOn,
				})
				play(w, p, q)
				expect(ser({
					deco = d.decoPerso,
					hearts = d.hearts,
					other = data(w, q).hearts,
					palette = d.cosmetics.palette,
					cushions = d.cosmetics.cushions,
					halo = d.settings.haloOn,
				})).toBe(before)
				expect(w.Bitset.count(d.decoPerso.owned)).toBe(0)
				expect(d.hearts.givenDay).toBe(0)
				expect(data(w, q).hearts.receivedTotal).toBe(0)
				expect(d.cosmetics.palette).toBe("")
				expect(d.settings.haloOn).toBe(true)
				expect(d.cosmetics.saddle).toBe("peach")
				expect(d.settings.emoteLeft).toBe("bellyFlop")
				expect(w.C.inPhotoMode(p)).toBe(false)
				for _, name in { "DecoPerso", "HaloOn", "Palette", "Cushions" } do
					expect({ name = name, value = attr(w, p, name) }).toEqual({ name = name, value = nil })
				end
				expect(#decoCards(p)).toBe(0)
				clean(w)
			end
		)
	end)
end
