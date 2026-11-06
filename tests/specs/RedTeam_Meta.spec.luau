--!nocheck
-- RedTeam_Meta (lot A4, étape 5 ; docs/04 §17.1 b et g, §27.5) : chaque intention de méta et de social
-- de la v2.0 attaquée, interrupteurs OUVERTS et profils v2 (là où les handlers travaillent vraiment) :
-- PlaceDeco, GiveHeart, SetPhotoMode, EquipCosmetic (palette, coussins), SetSetting (haloOn, emoteLeft),
-- MenuActivity. Charges hostiles par les types (nil, NaN, ±inf, nombres énormes, chaînes de 100 000
-- caractères, UTF-8 invalide, tables), valeurs limites, objets et palette d'un autre joueur, cœur à
-- soi-même, rafales de 1 000 messages → aucune mutation d'un profil, aucun Feedback, au plus le débit de
-- Config/Intents, aucune trace (ZeroLog, Diagnostics sans erreur).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")
local Fuzz = require("../harness/Fuzz")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."
	local R = "ReplicatedStorage.Remotes."
	local NAMES = { "PlaceDeco", "GiveHeart", "SetPhotoMode", "EquipCosmetic", "SetSetting", "MenuActivity" }
	local FLAGS = {
		"DecoPerso",
		"Hearts",
		"PhotoMode",
		"RanchSkins",
		"Workshop",
		"WeeklyTrack",
		"RecordR",
		"Helpers",
		"Carnet",
		"Mastery",
	}

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- p (attaquant) : fanion, banc et gamelle (petits), palette « Bonbon » ; q : fontaine (grand) posée
	-- sur l'emplacement 9, palette « Menthe » équipée, halo coupé
	local function world()
		local w = Brains.boot(HarnessV2, { t0 = T0, stubMeta = false })
		w.Bitset = w.h:require(L .. "Logic.Bitset")
		w.RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
		w.Diag = w.h:require(S .. "DiagnosticsService")
		w.C = w.h:require(S .. "CommunityService")
		for _, key in FLAGS do
			assert(w.Features.set(key, true), key)
		end
		local p = Brains.join(w, 1, {
			profile = Brains.profile(w, {
				squishies = { { s = 1, z = 100, bf = 1 } },
				edit = function(d)
					d.plopDays = 7
					d.dex.mut[1] = 0x3FF
					d.dex.mut[2] = 0x3FF
					d.dex.mut[3] = 0x3FF
					w.Bitset.set(d.atelierCosmetics, 1)
				end,
			}),
		})
		local q = Brains.join(w, 2, {
			profile = Brains.profile(w, {
				squishies = { { s = 2, z = 50, bf = 1 } },
				edit = function(d)
					for s = 1, #w.Species.List do
						d.dex.mut[s] = 0x3FF
					end
					w.Bitset.set(d.decoPerso.owned, 6)
					d.decoPerso.slots[9] = 6
					w.Bitset.set(d.atelierCosmetics, 2)
					d.cosmetics.palette = "mint"
					d.settings.haloOn = false
				end,
			}),
		})
		w.h:settle(2)
		return w, p, q
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
		expect(w.Diag.counts().errors).toBe(0)
	end

	-- `fn` ne change ni le profil de p ni celui de q, n'envoie aucun Feedback ni DataPatch à l'un d'eux
	local function untouched(w, p, q, label, fn)
		local fp, fq = #w.h:sentTo(p, "Feedback"), #w.h:sentTo(q, "Feedback")
		local dp, dq = #w.h:sentTo(p, "DataPatch"), #w.h:sentTo(q, "DataPatch")
		local okP, diffP = Fuzz.profileUnchanged(w.h, p, function()
			local okQ, diffQ = Fuzz.profileUnchanged(w.h, q, fn)
			if not okQ then
				error(label .. " : profil de l'autre joueur changé à " .. tostring(diffQ))
			end
		end)
		if not okP then
			error(label .. " : profil de l'attaquant changé à " .. tostring(diffP))
		end
		w.h:settle(2)
		expect({ label = label, feedback = #w.h:sentTo(p, "Feedback") - fp }).toEqual({
			label = label,
			feedback = 0,
		})
		expect({ label = label, other = #w.h:sentTo(q, "Feedback") - fq }).toEqual({
			label = label,
			other = 0,
		})
		expect({ label = label, patch = #w.h:sentTo(p, "DataPatch") - dp }).toEqual({
			label = label,
			patch = 0,
		})
		expect({ label = label, patchQ = #w.h:sentTo(q, "DataPatch") - dq }).toEqual({
			label = label,
			patchQ = 0,
		})
	end

	describe("RedTeam_Meta", function()
		it(
			"charges hostiles par les types (nil, NaN, ±inf, énormes, chaînes géantes, UTF-8 invalide, tables) : aucun profil changé, aucun envoi, aucune trace",
			function()
				local w, p, q = world()
				local attacked = 0
				for _, name in NAMES do
					untouched(w, p, q, name, function()
						attacked += Fuzz.attack(w.h, p, name, nil, {
							uid = "1",
							otherUid = "zz",
							userId = q.UserId,
							typeHostileOnly = true,
							tick = function()
								w.osClock.advance(11) -- seaux remplis : chaque charge atteint la validation
							end,
						})
					end)
				end
				expect(attacked > #NAMES * 20).toBe(true)
				clean(w)
			end
		)

		it(
			"valeurs limites, objets et palette d'un autre joueur, cœur à soi-même, emotes et habillages non gagnés : refusés sans mutation ni envoi",
			function()
				local w, p, q = world()
				local nan = 0 / 0
				local cases = {
					{ "PlaceDeco", 6, 9 }, -- fontaine : à q seulement
					{ "PlaceDeco", 6, 10 },
					{ "PlaceDeco", 7, 9 }, -- petit objet, grand emplacement
					{ "PlaceDeco", 1, 0 },
					{ "PlaceDeco", 1, 13 },
					{ "PlaceDeco", -1, 1 },
					{ "PlaceDeco", 65, 1 },
					{ "PlaceDeco", 41, 1 },
					{ "PlaceDeco", 1.5, 1 },
					{ "PlaceDeco", nan, 1 },
					{ "PlaceDeco", math.huge, 1 },
					{ "PlaceDeco", 1, -math.huge },
					{ "PlaceDeco", 2 ^ 53, 1 },
					{ "PlaceDeco", "1", 1 },
					{ "PlaceDeco", true, 1 },
					{ "PlaceDeco", {}, 1 },
					{ "PlaceDeco", 1 },
					{ "PlaceDeco", 0, 3 }, -- emplacement vide
					{ "GiveHeart", 1 }, -- soi-même
					{ "GiveHeart", 0 },
					{ "GiveHeart", -2 },
					{ "GiveHeart", 2 + 0.5 },
					{ "GiveHeart", 2 ^ 60 },
					{ "GiveHeart", nan },
					{ "GiveHeart", "2" },
					{ "GiveHeart", 77 }, -- absent
					{ "GiveHeart" },
					{ "SetPhotoMode", "true" },
					{ "SetPhotoMode", 1 },
					{ "SetPhotoMode", nan },
					{ "SetPhotoMode" },
					{ "SetPhotoMode", false }, -- déjà sorti
					{ "EquipCosmetic", "palette", "mint" }, -- palette de q
					{ "EquipCosmetic", "palette", "peachPalette" },
					{ "EquipCosmetic", "cushions", "pinkCushions" },
					{ "EquipCosmetic", "palette", "peach" },
					{ "EquipCosmetic", "palette", string.rep("a", 33) },
					{ "EquipCosmetic", "palette", "\255\254" },
					{ "EquipCosmetic", "palette", 5 },
					{ "EquipCosmetic", "deco", "namePennant" },
					{ "EquipCosmetic", "theme", "royal" }, -- Record R 20
					{ "EquipCosmetic", "saddle", "cosmic" }, -- taille 1e15
					{ "EquipCosmetic", "palette", "" }, -- déjà vide
					{ "SetSetting", "haloOn", "false" },
					{ "SetSetting", "haloOn", 0 },
					{ "SetSetting", "haloOn" },
					{ "SetSetting", "haloOn", true }, -- déjà vrai
					{ "SetSetting", "emoteLeft", "wave" }, -- Record R 13
					{ "SetSetting", "emoteLeft", "hugEmote" },
					{ "SetSetting", "emoteLeft", "hammerTap" },
					{ "SetSetting", "emoteLeft", string.rep("x", 100000) },
					{ "SetSetting", "emoteLeft", nan },
				}
				for i, c in cases do
					local label = i .. ":" .. c[1]
					untouched(w, p, q, label, function()
						w.RateLimit.clear(p)
						w.h:fireServer(R .. c[1], p, table.unpack(c, 2))
					end)
				end
				expect(w.C.inPhotoMode(p)).toBe(false)
				-- MenuActivity avec des arguments en trop : jamais une mutation (réveil des Plopettes seulement)
				untouched(w, p, q, "MenuActivity", function()
					w.RateLimit.clear(p)
					w.h:fireServer(R .. "MenuActivity", p, 1, "x", {}, nan)
				end)
				clean(w)
			end
		)

		it(
			"rafales de 1 000 messages : au plus le débit de Config/Intents ; un seul cœur par ranch ; aucune trace",
			function()
				local w, p, q = world()
				local Intents = w.h:require(L .. "Config.Intents")
				for _, name in NAMES do
					w.osClock.advance(60)
					local passed = Fuzz.rate(w.h, p, name, 1000, { userId = q.UserId, uid = "1" })
					local capacity = Intents[name].rate[1]
					if passed > capacity then
						error(name .. " : " .. passed .. " messages passés pour un débit de " .. capacity)
					end
					expect({ name = name, passed = passed >= 1 }).toEqual({ name = name, passed = true })
				end
				expect(w.DS.get(q).hearts.receivedTotal <= 1).toBe(true)
				expect(#w.DS.get(p).hearts.givenTo <= 1).toBe(true)
				-- 1 000 cœurs de plus, seau vidé à chaque fois : toujours un seul ce jour-là
				for _ = 1, 1000 do
					w.RateLimit.clear(p)
					w.h:fireServer(R .. "GiveHeart", p, q.UserId)
				end
				expect(w.DS.get(q).hearts.receivedTotal).toBe(1)
				expect(w.DS.get(p).hearts.givenTo).toEqual({ q.UserId })
				-- 1 000 poses alternées sur deux emplacements : jamais un objet deux fois
				for i = 1, 1000 do
					w.RateLimit.clear(p)
					w.h:fireServer(R .. "PlaceDeco", p, 1, if i % 2 == 0 then 1 else 2)
				end
				local slots = w.DS.get(p).decoPerso.slots
				local seen = {}
				for _, item in slots do
					if item ~= 0 then
						expect({ item = item, twice = seen[item] == true }).toEqual({
							item = item,
							twice = false,
						})
						seen[item] = true
					end
				end
				clean(w)
			end
		)
	end)
end
