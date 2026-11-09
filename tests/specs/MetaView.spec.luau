--!nocheck
-- MetaView (lot B3, étape 1 ; décision D3 du plan B3 ; GDD v2.0 §4.15, §4.17, §4.27, §4.29, §7.5, §17.1,
-- Annexe B.8) : vues PURES des écrans de renaissance et de méta, construites depuis Logic/Prestige,
-- Logic/QuestRules, Logic/Owned, Logic/RanchLook et la configuration, jamais en refaisant une formule.
--   * tuiles « Tu gagnes » : Grand Splorch (R0 → 1, R5 → 6, R regagné, R21 prime de record, R22 et R24
--     Monuments, R30 titre), Petit Splorch, Jelly Ascend (A0 … A10 nommés, puis la constellation ;
--     Confettis du Tremplin), replis interrupteur coupé (RecordR, Confetti, PetitSplorch) ;
--   * « Dépenser d'abord » : aucune / Enclos payable / seuls les Monuments payables ;
--   * lignes de l'Ascension, Livre des records (1e300, champs absents), piste de la semaine (première
--     période, lundi passé, cosmétique de la semaine la semaine prochaine / dans 6 semaines / déjà
--     gagné), Défis (faits, partiels, abîmés), Carnet (49, 50, 10 000), maîtrise ;
--   * textes de cartes de chaque sorte, identifiants inconnus → nil ; charges hostiles → valeurs sûres.
-- Toutes les clés rendues existent en anglais ET en français (et leurs variables-clés aussi).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local WITNESS = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local h = Harness.new()
	local MV = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.MetaView")
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local QuestRules = h:require("ReplicatedStorage.Shared.Logic.QuestRules")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Cosmetics = h:require("ReplicatedStorage.Shared.Config.Cosmetics")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")

	-- tous les interrupteurs booléens ouverts (comme le harnais UpgradeScreen)
	local ON = {}
	for k, v in Features.Defaults do
		ON[k] = if type(v) == "boolean" then true else v
	end
	local function onAll(flag)
		return true
	end
	local function onExcept(...)
		local off = {}
		for _, k in { ... } do
			off[k] = true
		end
		return function(flag)
			return not off[flag]
		end
	end

	-- instantané fabriqué (seuls r, bestR, ascend et le Tremplin comptent pour les aperçus)
	local function snap(r, bestR, A, springboard)
		return { r = r, bestR = bestR or r, ascend = A or 0, levels = { springboard = springboard or 0 } }
	end

	-- toutes les clés d'un texte (et de ses variables-clés) existent dans les deux langues
	local function keysOf(t, out)
		out = out or {}
		if type(t) ~= "table" then
			return out
		end
		if type(t.key) == "string" then
			table.insert(out, t.key)
		end
		if type(t.vars) == "table" then
			for _, v in t.vars do
				if type(v) == "table" then
					keysOf(v, out)
				end
			end
		end
		return out
	end
	local function expectKeys(t)
		for _, key in keysOf(t) do
			expect({ key = key, en = Strings.en[key] ~= nil }).toEqual({ key = key, en = true })
			expect({ key = key, fr = Strings.fr[key] ~= nil }).toEqual({ key = key, fr = true })
		end
	end

	-- traduction de test (anglais) : résout les variables-clés puis remplit le texte
	local function tr(key, vars)
		local text = Strings.en[key] or key
		return (
			string.gsub(text, "{(%w+)}", function(name)
				local v = vars and vars[name]
				return if v ~= nil then tostring(v) else "{" .. name .. "}"
			end)
		)
	end
	local function render(t)
		local r = MV.resolve(t, tr)
		return tr(r.key, r.vars)
	end
	local function tiles(kind, s, on, lang)
		local list = MV.previewTiles(kind, { snap = s, on = on or onAll, lang = lang })
		expect(#list).toBe(3)
		local out = {}
		for _, t in list do
			expect(t.kind).toBe("tile")
			expect(t.state).toBe("ready")
			expect(t.readOnly).toBe(true)
			expect(type(t.icon)).toBe("string")
			expectKeys(t.name)
			if t.value then
				expectKeys(t.value)
			end
			table.insert(out, render(t.name) .. (if t.value then " | " .. render(t.value) else ""))
		end
		return out, list
	end

	-- =========================================================================================
	describe("MetaView › tuiles des aperçus (D6)", function()
		it(
			"Grand Splorch R0 → 1 et R5 → 6 : Croissance ×2, déblocage nommé du Record R, Confettis 3 + r",
			function()
				local t, list = tiles("splorch", snap(0, 0))
				expect(t).toEqual({ "Growth ×2", "Big Plop's Workshop", "+4 Confetti" })
				expect(list[2].icon).toBe("gear")
				expect(list[3].icon).toBe("confetti")
				t = tiles("splorch", snap(5, 5))
				expect(t).toEqual({ "Growth ×2", "Free pen spot", "+9 Confetti" })
				-- les nombres viennent de Prestige (jamais refaits)
				expect(Prestige.confettiGain("splorch", 6, 5, 0)).toBe(9)
			end
		)

		it(
			"R regagné (r + 1 ≤ Record R) : « Cadeau du Splorch » et le gain d'un Petit Splorch",
			function()
				local t, list = tiles("splorch", snap(5, 10, 1))
				expect(t).toEqual({ "Growth ×2", "Splorch Gift", "+1 Confetti" })
				expect(list[2].icon).toBe("gift")
			end
		)

		it(
			"R21 : prime de record (+10) ; R22 et R24 : le Monument nommé ; R30 : le titre (unlock.item)",
			function()
				local t = tiles("splorch", snap(20, 20))
				expect(t).toEqual({ "Growth ×2", "Record bonus: +10 Confetti", "+33 Confetti" })
				t = tiles("splorch", snap(21, 21))
				expect(t[2]).toBe("Monument 9")
				expect(t[3]).toBe("+33 Confetti")
				t = tiles("splorch", snap(23, 23))
				expect(t[2]).toBe("Monument 10")
				local t30, list30 = tiles("splorch", snap(29, 29))
				expect(t30[2]).toBe("Jelly Monarch")
				expect(list30[2].name.key).toBe("unlock.item")
				expect(list30[2].name.vars.name.key).toBe("title.jellyMonarch")
				expect(list30[2].icon).toBe("title")
				-- au-delà de MaxR : jamais au-delà de la table
				local top = tiles("splorch", snap(Balance.Prestige.MaxR, Balance.Prestige.MaxR))
				expect(#top).toBe(3)
			end
		)

		it(
			"Petit Splorch (PetitSplorch ouvert) : Croissance ×2, Cadeau du Splorch, Petit Splorch : +1 Confetti",
			function()
				local t = tiles("petit", snap(4, 12, 1))
				expect(t).toEqual({ "Growth ×2", "Splorch Gift", "Petit Splorch: +1 Confetti" })
				-- PetitSplorch coupé : les tuiles du Grand Splorch (aucun texte d'un système coupé)
				t = tiles("petit", snap(4, 12, 1), onExcept("PetitSplorch"))
				expect(t).toEqual({ "Growth ×2", "Splorch Gift", "+1 Confetti" })
			end
		)

		it(
			"Jelly Ascend A0 … A9 : ciel nommé de l'Ascension suivante ; A10 et plus : constellation (étoiles bornées à 20)",
			function()
				local names = {}
				for A = 0, 9 do
					local t, list = tiles("ascend", snap(15 + 4 * A, 15 + 4 * A, A))
					expect(t[1]).toBe("×3 every loop, forever")
					expect(list[2].name.vars.name.key).toBe("sky." .. (A + 1))
					table.insert(names, t[2])
				end
				expect(names[1]).toBe("Halo and sky: Cushion Cloud")
				expect(names[10]).toBe("Halo and sky: Constellation")
				local t10 = tiles("ascend", snap(57, 57, 10))
				expect(t10[2]).toBe("Halo and sky: Constellation · 11 stars")
				local t30 = tiles("ascend", snap(100, 100, 30))
				expect(t30[2]).toBe("Halo and sky: Constellation · 20 stars")
			end
		)

		it(
			"Jelly Ascend : +20 Confettis, +1 par Grand Splorch sauté grâce au Tremplin (même écart que Prestige.apply)",
			function()
				local t = tiles("ascend", snap(20, 20, 1, 0))
				expect(t[3]).toBe("+20 Confetti")
				-- A = 1 → A2 : départ 4 sans Tremplin, 6 avec 2 niveaux : 2 sautés
				expect(Prestige.startR(2, 0)).toBe(4)
				expect(Prestige.startR(2, 2)).toBe(6)
				t = tiles("ascend", snap(20, 20, 1, 2))
				expect(t[3]).toBe("+22 Confetti")
				-- départ plafonné (ReqR(A + 2) − 10) : jamais plus que les sautés réels
				local start, skipped = Prestige.startR(2, 3), Prestige.startR(2, 3) - Prestige.startR(2, 0)
				t = tiles("ascend", snap(20, 20, 1, 3))
				expect(t[3]).toBe("+" .. Prestige.confettiGain("ascend", start, 20, skipped) .. " Confetti")
			end
		)

		it(
			"replis interrupteur coupé : RecordR (texte de la v1.3), Confetti (Fame d'un record, « Retour au record », objet de l'Ascension)",
			function()
				local t = tiles("splorch", snap(0, 0), onExcept("RecordR"))
				expect(t[2]).toBe(Strings.en["panel.splorch.unlock.family.axolo"])
				t = tiles("splorch", snap(1, 1), onExcept("RecordR"))
				expect(t[2]).toBe(Strings.en["panel.splorch.unlock.vat"])
				t = tiles("splorch", snap(5, 5), onExcept("Confetti"))
				expect(t[3]).toBe("+5 Fame")
				t = tiles("splorch", snap(5, 10, 1), onExcept("Confetti"))
				expect(t[3]).toBe("Back to record | 6 / 10")
				t = tiles("petit", snap(5, 10, 1), onExcept("Confetti"))
				expect(t[3]).toBe("Back to record | 6 / 10")
				t = tiles("ascend", snap(15, 15, 0), onExcept("Confetti"))
				expect(t[3]).toBe("Ascended")
				t = tiles("ascend", snap(20, 20, 1), onExcept("Confetti"))
				expect(t[3]).toBe("Back to record | 4 / 20")
				-- aucun interrupteur connu (ctx.on absent) : tout coupé, jamais d'erreur
				local list = MV.previewTiles("splorch", { snap = snap(0, 0) })
				expect(list[2].name.key).toBe("panel.splorch.unlock.family.axolo")
				expect(list[3].name.key).toBe("panel.splorch.win.fame")
			end
		)

		it(
			"charges hostiles (instantané absent, NaN, négatif, énorme, ctx.on qui casse) : boucle de l'accueil, sans trace",
			function()
				local hostile = {
					nil,
					5,
					"x",
					{ r = 0 / 0, bestR = -3, ascend = math.huge },
					{ r = -10, bestR = 1e9, ascend = -1, levels = "x" },
					{ r = 3.5, bestR = 2, ascend = 0, levels = { springboard = 1e9 } },
				}
				for i = 1, 6 do
					local s = hostile[i]
					for _, kind in { "splorch", "petit", "ascend", "nope" } do
						local list = MV.previewTiles(kind, { snap = s, on = onAll })
						expect(#list).toBe(3)
					end
				end
				local list = MV.previewTiles("splorch", {
					snap = snap(0, 0),
					on = function()
						error("cassé")
					end,
				})
				expect(list[3].name.key).toBe("panel.splorch.win.fame")
				expect(#MV.previewTiles("splorch", nil)).toBe(3)
				expect(#h.errors).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › « Dépenser d'abord » (keptPayable)", function()
		local W = WITNESS
		local function snapOf(edit)
			local p = deepCopy(W)
			edit(p)
			return UpgradeMath.snapshot(p, ON, 1)
		end

		it(
			"aucune pièce : aucune ligne gardée payable (nil) ; instantané absent ou abîmé : nil",
			function()
				local s = snapOf(function(p)
					p.coins = 0
				end)
				expect(MV.keptPayable(s, {})).toBeNil()
				expect(MV.keptPayable(nil, {})).toBeNil()
				expect(MV.keptPayable("x", {})).toBeNil()
			end
		)

		it(
			"Enclos payable : la ligne des Enclos (première gardée payable, ordre de l'onglet Ranch)",
			function()
				local s = snapOf(function(p)
					p.coins = 1e30
					p.tiles.pens = 3
				end)
				expect(MV.keptPayable(s, {})).toBe("pens")
			end
		)

		it(
			"Enclos au maximum et Lit douillet acheté : seuls les Monuments payables → « monuments »",
			function()
				local s = snapOf(function(p)
					p.coins = 1e30
					p.tiles.pens = 14
					p.tiles.cozyBed = true
					p.tiles.snack = 12
				end)
				expect(MV.keptPayable(s, {})).toBe("monument")
				-- Enclos au maximum, Lit douillet à acheter : le Lit douillet
				local s2 = snapOf(function(p)
					p.coins = 1e30
					p.tiles.pens = 14
					p.tiles.cozyBed = false
				end)
				expect(MV.keptPayable(s2, {})).toBe("cozyBed")
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › lignes de la Jelly Ascend", function()
		it(
			"départ (Prestige.startR, Tremplin compris), Record R, vitesse calculée, condition et barre",
			function()
				local l = MV.ascendLines(snap(15, 15, 0), {})
				expect(render(l.restart)).toBe(
					"You start again at Grand Splorch 0 (your record: 15). Everything else is kept."
				)
				expect(render(l.speed)).toBe(
					"Until your record, your squishies grow "
						.. Prestige.regainSpeedup()
						.. " times faster than before."
				)
				expect(Prestige.regainSpeedup()).toBe(9)
				expect(render(l.condition)).toBe("Grand Splorch 15 / 15")
				expect(l.met).toBe(true)
				expect(l.fill).toBe(1)
				-- A = 10, r = 50 : condition de la 11e (57), départ de l'A11
				l = MV.ascendLines(snap(50, 50, 10, 1), {})
				expect(render(l.condition)).toBe("Grand Splorch 50 / " .. Prestige.reqR(11))
				expect(Prestige.reqR(11)).toBe(57)
				expect(l.met).toBe(false)
				expect(l.fill).toBe(50 / 57)
				expect(l.startR).toBe(Prestige.startR(11, 1))
				expectKeys(l.restart)
				expectKeys(l.speed)
				expectKeys(l.condition)
				-- hostile : boucle de l'accueil
				l = MV.ascendLines(nil, nil)
				expect(l.need).toBe(Prestige.reqR(1))
				expect(l.met).toBe(false)
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › Livre des records (D13)", function()
		it(
			"ordre du GDD §17.1 ; 1e300 et champs absents sans erreur ; lignes d'un système coupé absentes",
			function()
				local p = deepCopy(WITNESS)
				p.biggestEver = 1e300
				p.confettiTotal = 1e300
				p.stats.bestCombo = 7
				p.stats.splorches = 1e300
				p.hearts.receivedTotal = 3
				p.plopDays = 9
				p.mastery = { 7 }
				local list = MV.records(p, { on = onAll })
				local ids = {}
				for _, line in list do
					table.insert(ids, line.id)
					expectKeys(line.text)
					local shown = render(line.text)
					expect(string.find(shown, "{", 1, true)).toBeNil()
				end
				expect(table.concat(ids, ",")).toBe(
					"biggest,bestCombo,splorches,ascend,bestR,confetti,mastery,plopDays,hearts,upgrades"
				)
				expect(render(list[2].text)).toBe("Best combo: ×7")
				expect(render(list[7].text)).toBe("Masteries: 3 / 26")
				expect(render(list[9].text)).toBe("Hearts received: 3")
				-- système coupé : ligne absente
				local cut = MV.records(p, { on = onExcept("Hearts", "Mastery", "JellyAscend", "Confetti") })
				local cutIds = {}
				for _, line in cut do
					table.insert(cutIds, line.id)
				end
				expect(table.concat(cutIds, ",")).toBe("biggest,bestCombo,splorches,bestR,plopDays,upgrades")
				-- profil vide ou absurde : des zéros, jamais d'erreur
				for _, bad in { {}, nil, 5, { stats = "x", hearts = 4, mastery = "y", biggestEver = 0 / 0 } } do
					local l = MV.records(bad, { on = onAll })
					expect(#l).toBe(10)
					expect(render(l[1].text)).toBe("Biggest squishy: 0")
				end
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › piste de la semaine, Défis, Carnet (D15)", function()
		local WEEK = 604800
		local EPOCH = 345600
		local function monday(week)
			return EPOCH + week * WEEK
		end
		local function trackProfile(edit)
			local p = deepCopy(WITNESS)
			edit(p.weeklyTrack, p)
			return p
		end

		it(
			"première période (firstPeriodEnd = 0) : jusqu'au 2e lundi, 24 points, paliers et récompenses visibles d'avance",
			function()
				local week = 2965
				local now = monday(week) + 2 * 86400 + 3600 -- mercredi
				local p = trackProfile(function(t)
					t.firstPeriodEnd = 0
					t.period = 0
					t.points = 5
				end)
				local v = MV.track(p, now, {})
				expect(v.first).toBe(true)
				expect(v.ended).toBe(false)
				expect(v.endsAt).toBe(monday(week + 2))
				expect(v.daysLeft).toBe(12)
				expect(v.maxPoints).toBe(24)
				expect(v.reached).toBe(2)
				expect(#v.tiers).toBe(12)
				expect(render(v.pointsText)).toBe("5 / 24 points")
				expect(render(v.endsText)).toBe("Ends in 12 d")
				expect(render(v.tiers[1].reward)).toBe("+2 Confetti")
				expect(render(v.tiers[4].reward)).toBe("Lucky Drop")
				expect(v.tiers[12].kind).toBe("cosmetic")
				expect(v.tiers[2].reached).toBe(true)
				expect(v.tiers[3].reached).toBe(false)
				for _, tier in v.tiers do
					expectKeys(tier.reward)
				end
				-- même calcul que QuestRules.trackPeriod
				expect(v.endsAt).toBe(QuestRules.trackPeriod(p, now).endsAt)
			end
		)

		it(
			"lundi passé pendant la session (période gardée par le serveur) : finie, 0 jour ; semaine ordinaire : jours restants",
			function()
				local week = 2970
				local p = trackProfile(function(t)
					t.firstPeriodEnd = monday(2960)
					t.period = week
					t.points = 24
					t.claimed = { 4095 }
				end)
				local v = MV.track(p, monday(week) + 6 * 86400 + 86399, {})
				expect(v.ended).toBe(false)
				expect(v.daysLeft).toBe(1)
				expect(v.tiers[12].claimed).toBe(true)
				expect(v.reached).toBe(12)
				v = MV.track(p, monday(week + 1) + 60, {})
				expect(v.ended).toBe(true)
				expect(v.daysLeft).toBe(0)
				expect(v.period).toBe(week)
			end
		)

		it(
			"cosmétique de la semaine : celui de la période (rotation de 8), la semaine prochaine, dans 6 semaines, déjà gagné",
			function()
				local week = 2968 -- 2968 % 8 = 0 : le premier de la rotation
				local p = trackProfile(function(t)
					t.firstPeriodEnd = monday(2960)
					t.period = week
					t.won = { 0 }
				end)
				local v = MV.track(p, monday(week) + 3600, {})
				expect(v.cosmetic.index).toBe(1)
				expect(v.cosmetic.id).toBe(Cosmetics.WeeklyRotation[1].id)
				expect(v.cosmetic.current).toBe(true)
				expect(v.cosmetic.won).toBe(false)
				expect(v.cosmetic.weeks).toBe(8)
				expect(render(v.cosmetic.returns)).toBe("Back in 8 weeks")
				expect(render(v.tiers[12].reward)).toBe(Strings.en[Cosmetics.WeeklyRotation[1].key])
				expect(v.rotation[2].weeks).toBe(1)
				expect(render(v.rotation[2].returns)).toBe("Back next week")
				expect(v.rotation[7].weeks).toBe(6)
				expect(render(v.rotation[7].returns)).toBe("Back in 6 weeks")
				-- déjà gagné (bit 1 de won)
				p.weeklyTrack.won = { 1 }
				v = MV.track(p, monday(week) + 3600, {})
				expect(v.cosmetic.won).toBe(true)
				-- même rotation que QuestService (period % 8 + 1) et MetaView.weeklyIn
				for i = 1, 8 do
					expect(MV.weeklyIn(i, week + i - 1)).toBe(8)
				end
				expect(MV.weeklyIn(0 / 0, -5)).toBe(8)
			end
		)

		it(
			"piste hostile (champs absents, points NaN, période texte) : valeurs sûres, sans erreur",
			function()
				for _, bad in
					{
						{},
						nil,
						{ weeklyTrack = 5 },
						{ weeklyTrack = { points = 0 / 0, period = "x", claimed = "y" } },
					}
				do
					local v = MV.track(bad, 1800000000, {})
					expect(#v.tiers).toBe(12)
					expect(v.points).toBe(0)
					expect(#v.rotation).toBe(8)
				end
				local v = MV.track(WITNESS, 0 / 0, {})
				expect(#v.tiers).toBe(12)
			end
		)

		it(
			"Défis : faits, partiels, au-delà de l'objectif (bornés), entrées abîmées sautées (3 au plus)",
			function()
				local p = trackProfile(function(t)
					t.challenges = {
						{ id = 1, p = 1, done = false },
						{ id = 3, p = 10, done = false },
						{ id = 12, p = 40, done = false },
						{ id = 2, p = 1, done = false },
					}
				end)
				local list = MV.challenges(p, {})
				expect(#list).toBe(3)
				expect(list[1].key).toBe("challenge.1")
				expect(list[1].done).toBe(false)
				expect(render(list[1].text)).toBe("1 / 2")
				expect(list[2].done).toBe(true)
				expect(list[3].p).toBe(30)
				expect(render(list[3].text)).toBe("30 / 30")
				for _, row in list do
					expectKeys(row.text)
					expect(Strings.en[row.key] ~= nil and Strings.fr[row.key] ~= nil).toBe(true)
				end
				-- 3 entrées lues au plus (Quests.WeeklyTrack.ChallengesPerWeek) : la 4e est ignorée
				p.weeklyTrack.challenges =
					{ { id = 99, p = 1 }, { id = "1", p = 1 }, { id = 5, p = 0, done = true }, 5 }
				list = MV.challenges(p, {})
				expect(#list).toBe(1)
				expect(list[1].id).toBe(5)
				expect(list[1].done).toBe(true)
				expect(#MV.challenges(nil, {})).toBe(0)
				expect(#MV.challenges({ weeklyTrack = { challenges = "x" } }, {})).toBe(0)
			end
		)

		it(
			"Carnet : 49 (aucun palier), 50 (premier), 10 000 (tous) ; récompenses nommées et objets de Déco perso",
			function()
				local function carnet(n, lang)
					local p = deepCopy(WITNESS)
					p.stats.upgradesBought = n
					return MV.carnet(p, { lang = lang })
				end
				local c = carnet(49)
				expect(c.tier).toBe(0)
				expect(c.next).toBe(50)
				expect(render(c.progress)).toBe("Upgrades bought: 49 / 50")
				expect(c.tiers[1].reached).toBe(false)
				expect(#c.tiers).toBe(8)
				for _, tier in c.tiers do
					expect(tier.reward ~= nil).toBe(true)
					expectKeys(tier.reward)
				end
				expect(render(c.tiers[1].reward)).toBe(Strings.en["title.builder"])
				c = carnet(50)
				expect(c.tier).toBe(1)
				expect(c.next).toBe(100)
				expect(c.tiers[1].reached).toBe(true)
				expect(render(c.progress)).toBe("Upgrades bought: 50 / 100")
				c = carnet(10000)
				expect(c.tier).toBe(8)
				expect(c.next).toBeNil()
				expect(render(c.progress)).toBe("Upgrades bought: 10,000 / 10,000")
				expect(#c.decos).toBe(2)
				expect(c.decos[1].at).toBe(750)
				expect(c.decos[1].reached).toBe(true)
				expectKeys(c.decos[1].name)
				-- français : séparateur des milliers dans la police
				local fr = carnet(10000, "fr")
				local r = MV.resolve(fr.progress, tr)
				expect(r.vars.n).toBe("10 000")
				-- hostile
				expect(carnet(-5).bought).toBe(0)
				expect(carnet(0 / 0).bought).toBe(0)
				expect(MV.carnet(nil, {}).tier).toBe(0)
			end
		)

		it(
			"maîtrise : 3 cases (Owned.mastery), compteur ; espèce inconnue ou profil vide : tout faux",
			function()
				local p = deepCopy(WITNESS)
				local m = MV.mastery(p, 1)
				expect(m.total).toBe(3)
				expect(m.count).toBe(
					(if m.star5 then 1 else 0) + (if m.golden then 1 else 0) + (if m.crystal then 1 else 0)
				)
				expect(MV.mastery(p, 999).count).toBe(0)
				expect(MV.mastery(nil, 1).count).toBe(0)
				expect(MV.mastery(p, "1").count).toBe(0)
				local n, total = MV.masteryCount({ mastery = { 7 } })
				expect(n).toBe(3)
				expect(total).toBe(26)
				expect(MV.masteryCount(nil)).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › textes des cartes (D19)", function()
		local function card(kind, data, ctx)
			local c = MV.cardText(kind, data, ctx or { snap = snap(12, 12) })
			if c then
				expectKeys(c.title)
				if c.line then
					expectKeys(c.line)
				end
			end
			return c
		end

		it("chaque sorte rend son texte (anglais), l'écran qu'ouvre la carte rouverte", function()
			local c =
				card("welcomeV2", { highlights = { "unlock.helper", "unlock.monument", "unlock.skin" } })
			expect(render(c.title)).toBe("Welcome to v2!")
			expect(#c.highlights).toBe(3)
			expect(render(c.highlights[1])).toBe("Puff joins you")
			expect(render(c.highlights[2])).toBe("Monument 4")
			for _, t in c.highlights do
				expectKeys(t)
			end
			c = card("regainDone", { bestR = 12, confetti = 10 })
			expect(render(c.title)).toBe("Back to your record 12!")
			expect(render(c.line)).toBe("+10 Confetti")
			c = card("recordStep", { share = 0.5 })
			expect(render(c.title)).toBe("Record step: 50%!")
			c = card("unlock", { kind = "deco", id = "namePennant" })
			expect(render(c.title)).toBe("New: " .. Strings.en["deco.namePennant"])
			expect(c.panel).toBe("Ranch")
			expect(c.tab).toBe("style")
			c = card("unlock", { kind = "saddle", id = "cosmic" })
			expect(render(c.title)).toBe("New: " .. Strings.en["v2cosmetic.saddle.cosmic"])
			c = card("unlock", { kind = "emote", id = "hugEmote" })
			expect(c.panel).toBe("Settings")
			c = card("unlock2", { recordR = 6, keys = {} })
			expect(render(c.title)).toBe("New: Free pen spot")
			expect(render(c.line)).toBe((string.gsub(Strings.en["unlock.helper"], "{name}", "Pim")))
			c = card("trackTier", { tier = 3, reward = "confetti" })
			expect(render(c.title)).toBe("Tier 3")
			expect(render(c.line)).toBe("+3 Confetti")
			expect(c.panel).toBe("Objectives")
			expect(c.tab).toBe("track")
			c = card("trackTier", { tier = 12, reward = "saddle.cookieSaddle" })
			expect(render(c.line)).toBe(Strings.en["weekly.cookieSaddle"])
			c = card("trackTier", { tier = 4, reward = "drop" })
			expect(render(c.line)).toBe("Lucky Drop")
			c = card("trackTier", { tier = 12, reward = "" })
			expect(c.line).toBeNil()
			c = card("carnet", { tier = 8, reward = "outfit.buildersCrown" })
			expect(render(c.title)).toBe("Ranch Notebook")
			expect(render(c.line)).toBe(Strings.en["v2cosmetic.outfit.buildersCrown"])
			expect(c.tab).toBe("carnet")
			c = card("mastery", { species = 1 })
			local want = string.gsub(Strings.en["mastery.done"], "{name}", Strings.en["species.plop"])
			expect(render(c.title)).toBe((string.gsub(want, "{n}", "25")))
			expect(c.panel).toBe("Squishydex")
			for _, id in
				{ "tier1.pompomArch", "tier6.floatingCrown", "monument.1", "monument.10", "helper.house" }
			do
				c = card("element", { id = id })
				expect({ id = id, ok = c ~= nil }).toEqual({ id = id, ok = true })
			end
			expect(render(card("element", { id = "tier4.jellyLighthouse" }).title)).toBe(
				"New: Jelly Lighthouse"
			)
			expect(render(card("element", { id = "monument.10" }).title)).toBe("New: Syrup Falls")
		end)

		it(
			"identifiants inconnus, sortes inconnues, charges hostiles : nil, jamais d'erreur ; cosmétique de la v1.3 : nil (le HUD de la v1.3 l'annonce)",
			function()
				for _, case in
					{
						{ "nope", {} },
						{ "regainDone", { bestR = 0 } },
						{ "regainDone", { bestR = 0 / 0 } },
						{ "regainDone", 5 },
						{ "recordStep", { share = 0.3 } },
						{ "unlock", { kind = "deco", id = "nope" } },
						{ "unlock", { kind = "saddle", id = "classic" } },
						{ "unlock", { kind = 5, id = "x" } },
						{ "unlock2", { recordR = -1 } },
						{ "unlock2", { recordR = 1.5 } },
						{ "trackTier", { tier = 13, reward = "drop" } },
						{ "trackTier", { tier = "1" } },
						{ "carnet", { tier = 0 } },
						{ "mastery", { species = 999 } },
						{ "element", { id = "vat" } },
						{ "element", { id = "deco.3" } },
						{ "element", { id = "tier7.x" } },
						{ "element", { id = "monument.11" } },
						{ "element", { id = string.rep("a", 500) } },
						{ "element", nil },
					}
				do
					expect({ kind = case[1], card = MV.cardText(case[1], case[2], {}) }).toEqual({
						kind = case[1],
					})
				end
				-- Bienvenue : clé introuvable ou Record R inconnu : rien de montré avec une variable vide
				local c = MV.cardText(
					"welcomeV2",
					{ highlights = { "unlock.nope", 5, "unlock.monument" } },
					{}
				)
				expect(#c.highlights).toBe(0)
				c = MV.cardText("welcomeV2", { highlights = "x" }, { snap = snap(12, 12) })
				expect(#c.highlights).toBe(0)
				expect(#h.errors).toBe(0)
			end
		)
	end)

	-- =========================================================================================
	describe("MetaView › resolve", function()
		it("traduit les variables-clés (imbriquées), garde les chaînes ; entrée absurde : nil", function()
			local t =
				{ key = "ascend.tile.sky", vars = { name = { key = "sky.stars", vars = { n = "12" } } } }
			expect(render(t)).toBe("Halo and sky: Constellation · 12 stars")
			expect(MV.resolve(nil, tr)).toBeNil()
			expect(MV.resolve({ key = 5 }, tr)).toBeNil()
			local deep = { key = "unlock.item", vars = {} }
			local cur = deep
			for _ = 1, 10 do
				local inner = { key = "unlock.item", vars = {} }
				cur.vars.name = inner
				cur = inner
			end
			expect(type(render(deep))).toBe("string")
		end)
	end)
end
