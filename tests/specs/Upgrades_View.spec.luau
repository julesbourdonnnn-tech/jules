--!nocheck
-- Upgrades_View (lot B2, étape 1 ; décision D27 du plan ; docs/04 §27.7, §27.8 ; GDD v2.0 §10.7.4 à
-- §10.7.8, §4.26, §4.28) : vue PURE d'une ligne ou d'une carte de l'écran Améliorations
-- (UI/Hud/UpgradeView), sans écran ni instance :
--   * table des états (Prêt, Il manque, MAX, « Record n » / « Ascension n », « Boucle n », En cours,
--     Réessaie) et ligne cachée quand un interrupteur du serveur la coupe (D8) ;
--   * aperçu ×1 / ×10 / Max = UpgradeMath.plan et UpgradeMath.bulk sur 2 000 instantanés tirés au
--     hasard (graine fixe) ; jamais un mode, un identifiant ni un niveau invalide à envoyer ;
--   * ligne Tapis : bascule vers « star » au Tapis 12 (niveau attendu de l'Étoilé), « Boucle 6 » à r = 3
--     après une Ascension (jamais « Record 6 ») ;
--   * effets avec le contexte du joueur : Lit douillet 9 h → 13 h avec le Sac de nuit 1 ; Pot de nuit
--     25 → 28 → 31 % ; « Pour le plaisir » : la ligne du titre s'appelle fun.title.confettiStar ;
--   * Plopettes (note du lot A3) : nombre, intervalle (UpgradeMath.effect("school")), sieste ;
--   * Atelier conseillé (≤ 3, les moins chères), Souvenir (Prestige), « Monte avec ton record ».
-- Les nombres sont des chaînes de UI/Format ou de Logic/BigNumber ; la vue ne rend que des clés.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Props = require("../harness/Props")

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
	local V = h:require("StarterPlayer.StarterPlayerScripts.Client.UI.Hud.UpgradeView")
	local UpgradeMath = h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Prestige = h:require("ReplicatedStorage.Shared.Logic.Prestige")
	local Features = h:require("ReplicatedStorage.Shared.Config.Features")
	local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
	local Upgrades = h:require("ReplicatedStorage.Shared.Config.Upgrades")
	local Strings = h:require("ReplicatedStorage.Shared.Localization.Strings")

	local IDS = UpgradeMath.ids()
	local ID_SET = {}
	for _, id in IDS do
		ID_SET[id] = true
	end
	local ALL_LINES = {}
	for _, tab in { "ranch", "helpers", "workshop" } do
		for _, id in V.lines(tab) do
			table.insert(ALL_LINES, id)
		end
	end
	table.insert(ALL_LINES, "star")

	local ON = {}
	for k, v in Features.Defaults do
		ON[k] = if type(v) == "boolean" then true else v
	end

	-- Instantané d'un profil témoin modifié (interrupteurs `flags`, tous ouverts par défaut)
	local function snapOf(edit, flags)
		local p = deepCopy(WITNESS)
		if edit then
			edit(p)
		end
		return UpgradeMath.snapshot(p, flags or ON, 1)
	end

	local function txt(t)
		if t == nil then
			return "-"
		end
		local parts = { t.key }
		if t.vars then
			local keys = {}
			for k in t.vars do
				table.insert(keys, k)
			end
			table.sort(keys)
			for _, k in keys do
				table.insert(parts, k .. "=" .. t.vars[k])
			end
		end
		return table.concat(parts, " ")
	end

	local function keyExists(key)
		return Strings.en[key] ~= nil and Strings.fr[key] ~= nil
	end

	describe("Upgrades_View › lignes de chaque onglet (ordre fixe, règle 1)", function()
		it(
			"Ranch 6, Plopettes 7, Atelier 17 (9 + « Monte avec ton record » + 7) ; titre de section",
			function()
				expect(V.lines("ranch")).toEqual({ "snack", "decor", "pens", "cozyBed", "gloves", "monument" })
				expect(V.lines("helpers")).toEqual({
					"school",
					"helper.pip",
					"helper.pop",
					"helper.pim",
					"helper.pom",
					"helper.puff",
					"helper.plume",
				})
				expect(V.lines("workshop")).toEqual({
					"gift",
					"startMat",
					"magnet",
					"superStreak",
					"keptDecor",
					"nightBag",
					"nightPot",
					"plume",
					"springboard",
					"risesWithRecord",
					"fun.palettes",
					"fun.saddle",
					"fun.trail",
					"fun.emote",
					"fun.pennants",
					"fun.title",
					"decoShop",
				})
				expect(#V.lines("suggested")).toBe(0)
				expect(V.sectionBefore("fun.palettes")).toBe("fun.title")
				expect(V.sectionBefore("gift")).toBe(nil)
			end
		)
	end)

	describe("Upgrades_View › table des états (GDD §10.7.6)", function()
		it("Prêt, Il manque, MAX : mot, icône, bandeau et intention", function()
			local s = snapOf(function(p)
				p.coins = 1e300
			end)
			local ready = V.view("decor", s, 1, { lang = "fr" })
			expect(ready.state).toBe("ready")
			expect(txt(ready.stateText)).toBe("upgrades.state.ready")
			expect(ready.stateIcon).toBe("check")
			expect(ready.sendId).toBe("decor")
			expect(ready.expectedLevel).toBe(9)
			expect(ready.banner).toBe(nil) -- ×1 : le sort de la ligne seul
			expect(txt(ready.fate)).toBe("upgrades.detail.resets")
			local poor = snapOf(function(p)
				p.coins = 0
			end)
			local need = V.view("decor", poor, 1, { lang = "fr" })
			expect(need.state).toBe("need")
			expect(txt(need.stateText)).toBe("upgrades.state.need")
			expect(need.stateIcon).toBe("hourglass")
			expect(need.banner.key).toBe("upgrades.detail.missing")
			expect(need.missing).toBe(need.price)
			expect(need.fill).toBe(0)
			local max = V.view("pens", s, 1, { lang = "fr" })
			expect(max.state).toBe("max")
			expect(txt(max.stateText)).toBe("upgrades.state.max")
			expect(max.stateIcon).toBe("star")
			expect(max.priceText).toBe(nil) -- « — »
			expect(max.sendId).toBe(nil)
			expect(txt(max.banner)).toBe("upgrades.detail.allMax")
			expect(txt(max.fate)).toBe("upgrades.detail.kept")
		end)

		it(
			"verrouillé : « Record n » (Record R), « Ascension n » (Tremplin), Monument 10 « Record 24 »",
			function()
				local fresh = snapOf(function(p)
					p.R = 0
					p.bestR = 0
					p.coins = 1e300
				end)
				local gloves = V.view("gloves", fresh, 1, { lang = "fr" })
				expect(gloves.state).toBe("locked")
				expect(txt(gloves.stateText)).toBe("upgrades.state.locked r=1")
				expect(gloves.stateIcon).toBe("lock")
				expect(txt(gloves.banner)).toBe("upgrades.detail.opensAt r=1")
				expect(gloves.sendId).toBe(nil)
				expect(gloves.priceText ~= nil).toBe(true) -- prix du premier niveau, en gris
				local school = V.view("school", fresh, 1, { lang = "fr" })
				expect(txt(school.stateText)).toBe("upgrades.state.locked r=2")
				local bed = V.view(
					"cozyBed",
					snapOf(function(p)
						p.R = 2
						p.bestR = 2
						p.tiles.cozyBed = false
					end),
					1,
					{}
				)
				expect(txt(bed.stateText)).toBe("upgrades.state.locked r=3")
				local spring = V.view("springboard", snapOf(), 1, {})
				expect(spring.state).toBe("locked")
				expect(txt(spring.stateText)).toBe("upgrades.state.lockedAscend a=1")
				expect(txt(spring.banner)).toBe("upgrades.detail.opensAtAscend")
				local mon = V.view(
					"monument",
					snapOf(function(p)
						p.R = 20
						p.bestR = 22
						p.tiles.snack = 12
						p.tiles.monuments = 9
					end),
					1,
					{}
				)
				expect(mon.state).toBe("locked")
				expect(txt(mon.stateText)).toBe("upgrades.state.locked r=24")
			end
		)

		it("En cours et Réessaie : seulement sur une ligne encore achetable", function()
			local s = snapOf(function(p)
				p.coins = 1e300
			end)
			local busy = V.view("decor", s, 1, {}, "busy")
			expect(busy.state).toBe("busy")
			expect(txt(busy.stateText)).toBe("upgrades.state.busy")
			expect(busy.stateIcon).toBe("hourglass")
			expect(busy.sendId).toBe("decor")
			local retry = V.view("decor", s, 10, {}, "retry")
			expect(retry.state).toBe("retry")
			expect(txt(retry.stateText)).toBe("upgrades.state.retry")
			expect(retry.stateIcon).toBe("retry")
			expect(txt(retry.banner)).toBe("upgrades.detail.hold")
			expect(retry.sendMode).toBe(10)
			-- jamais « Réessaie » sur une ligne au maximum, verrouillée ou au plafond de la boucle
			expect(V.view("pens", s, 1, {}, "retry").state).toBe("max")
			expect(V.view("springboard", s, 1, {}, "busy").state).toBe("locked")
		end)

		it(
			"ligne coupée par un interrupteur du serveur (règle remplie, plafond 0) : cachée (D8)",
			function()
				local flags = table.clone(ON)
				flags.Gloves = false
				flags.Helpers = false
				flags.Workshop = false
				local s = snapOf(nil, flags)
				local gloves = V.view("gloves", s, 1, {})
				expect(gloves.hidden).toBe(true)
				expect(gloves.sendId).toBe(nil)
				expect(V.view("school", s, 1, {}).hidden).toBe(true)
				expect(V.view("helper.pip", s, 1, {}).hidden).toBe(true)
				expect(V.view("gift", s, 1, {}).hidden).toBe(true)
				expect(V.view("fun.palettes", s, 1, {}).hidden).toBe(true)
				expect(V.view("risesWithRecord", s, 1, {}).hidden).toBe(true)
				-- Record R pas encore atteint : cadenas, jamais caché
				local early = snapOf(function(p)
					p.R = 0
					p.bestR = 0
				end, flags)
				expect(V.view("gloves", early, 1, {}).hidden).toBe(false)
				expect(V.view("gloves", early, 1, {}).state).toBe("locked")
				-- toujours ouvertes (v1.3) : jamais cachées
				expect(V.view("decor", s, 1, {}).hidden).toBe(false)
				expect(V.view("snack", s, 1, {}).hidden).toBe(false)
			end
		)

		it("identifiant inconnu ou instantané absent : vue cachée, aucune erreur", function()
			local s = snapOf()
			for _, bad in { "inconnu", "fun.inconnu", "", "helper.x" } do
				local v = V.view(bad, s, 1, {})
				expect(v.hidden).toBe(true)
				expect(v.sendId).toBe(nil)
			end
			expect(V.view("decor", nil, 1, {}).hidden).toBe(true)
		end)
	end)

	describe("Upgrades_View › ligne Tapis (Tapis à Goûter + Tapis Étoilé)", function()
		it(
			"bascule vers « star » au Tapis 12 : niveau montré 12 + Étoilé sur 20, niveau attendu de l'Étoilé",
			function()
				local before = V.view(
					"snack",
					snapOf(function(p)
						p.coins = 1e300
						p.tiles.snack = 11
					end),
					1,
					{}
				)
				expect(before.sendId).toBe("snack")
				expect(before.expectedLevel).toBe(11)
				expect(before.levelText).toBe("11/20")
				expect(before.icon).toBe("mat")
				local after = V.view(
					"snack",
					snapOf(function(p)
						p.coins = 1e300
						p.tiles.snack = 12
						p.tiles.star = 3
						p.R = 12
					end),
					10,
					{}
				)
				expect(after.sendId).toBe("star")
				expect(after.expectedLevel).toBe(3)
				expect(after.level).toBe(15)
				expect(after.levelText).toBe("15/20")
				expect(after.icon).toBe("starMat")
				expect(after.name.key).toBe("upgrades.family.star")
				-- ×10 au plafond de la boucle (8 dès r = 10) : 3 → 8, montré 15 → 20
				expect(after.preview.count).toBe(5)
				expect(after.fromText).toBe("15")
				expect(after.toText).toBe("20")
				expect(V.view(
					"star",
					snapOf(function(p)
						p.tiles.snack = 12
						p.tiles.star = 8
					end),
					1,
					{}
				).state).toBe("max")
			end
		)

		it(
			"« Boucle 6 » à r = 3 après une Ascension (Record R 15) : plafond de la boucle, jamais « Record 6 »",
			function()
				local s = snapOf(function(p)
					p.R = 3
					p.bestR = 15
					p.ascend = 1
					p.tiles.snack = 12
					p.tiles.star = 0
					p.coins = 1e300
				end)
				local v = V.view("snack", s, 1, { lang = "fr" })
				expect(v.state).toBe("loopCap")
				expect(txt(v.stateText)).toBe("upgrades.state.loopCap r=6")
				expect(v.stateIcon).toBe("loop")
				expect(txt(v.banner)).toBe("upgrades.detail.starCap r=6")
				expect(v.sendId).toBe(nil)
				expect(v.levelText).toBe("12/20")
				expect(v.capLevel).toBe(12) -- tout l'Étoilé grisé dans cette boucle
				-- r = 7 : plafond 2 ; au niveau 2, « Boucle 8 »
				local s7 = snapOf(function(p)
					p.R = 7
					p.bestR = 15
					p.ascend = 1
					p.tiles.snack = 12
					p.tiles.star = 2
				end)
				local v7 = V.view("snack", s7, 1, {})
				expect(txt(v7.stateText)).toBe("upgrades.state.loopCap r=8")
				expect(v7.capLevel).toBe(14)
			end
		)

		it(
			"Tapis Étoilé coupé par son interrupteur au Tapis 12 : ligne au maximum 12/12, jamais « Boucle »",
			function()
				local flags = table.clone(ON)
				flags.StarMat = false
				local v = V.view(
					"snack",
					snapOf(function(p)
						p.R = 12
						p.tiles.snack = 12
					end, flags),
					1,
					{}
				)
				expect(v.state).toBe("max")
				expect(v.levelText).toBe("12/12")
				expect(v.hidden).toBe(false)
			end
		)
	end)

	describe("Upgrades_View › effets avant → après (contexte du joueur, D30)", function()
		-- relecture des captures de l'étape 2 (Atelier, tv1080 FR) : « Cadeau 3 » au maximum, sans son
		-- unité ; la valeur seule garde l'unité de la valeur d'après (« 3 niv. », « 14 studs »)
		it("au maximum, la valeur seule garde son unité (Cadeau « 3 niv. », Aimant en studs)", function()
			local s = snapOf(function(p)
				p.atelier[Upgrades.WorkshopIndex.gift] = 2
				p.atelier[Upgrades.WorkshopIndex.magnet] = 3
			end)
			local gift = V.view("gift", s, 1, { lang = "fr" })
			expect(gift.state).toBe("max")
			expect(gift.effect.after).toBe(nil)
			expect(gift.effect.before.key).toBe("upgrades.unit.levels")
			local magnet = V.view("magnet", s, 1, { lang = "fr" })
			expect(magnet.state).toBe("max")
			expect(magnet.effect.before.key).toBe("upgrades.unit.studs")
			-- avant le maximum : rien ne change (« 5 → 8 studs », l'unité après la flèche)
			local open = V.view("magnet", snapOf(), 1, { lang = "fr" })
			expect(open.effect.before.key).toBe("upgrades.unit.count")
			expect(open.effect.after.key).toBe("upgrades.unit.studs")
		end)

		it("Lit douillet : « 9 h → 13 h » avec le Sac de nuit 1 (8 h → 12 h sans)", function()
			local s = snapOf(function(p)
				p.tiles.cozyBed = false
				p.atelier[Upgrades.WorkshopIndex.nightBag] = 1
			end)
			local v = V.view("cozyBed", s, 1, { lang = "fr" })
			expect(txt(v.effect.label)).toBe("upgrades.effect.night")
			expect(txt(v.effect.before)).toBe("upgrades.unit.hours n=9")
			expect(txt(v.effect.after)).toBe("upgrades.unit.hours n=13")
			local plain = V.view(
				"cozyBed",
				snapOf(function(p)
					p.tiles.cozyBed = false
				end),
				1,
				{}
			)
			expect(txt(plain.effect.before)).toBe("upgrades.unit.hours n=8")
			expect(txt(plain.effect.after)).toBe("upgrades.unit.hours n=12")
			-- famille Spiky complète : + 1 h
			local spiky = V.view("cozyBed", s, 1, { spikyFamily = true })
			expect(txt(spiky.effect.before)).toBe("upgrades.unit.hours n=10")
			expect(txt(spiky.effect.after)).toBe("upgrades.unit.hours n=14")
		end)

		it("Pot de nuit : 25 % → 28 %, puis 28 % → 31 %, puis 31 % (au maximum, sans flèche)", function()
			local function at(level)
				return V.view(
					"nightPot",
					snapOf(function(p)
						p.atelier[Upgrades.WorkshopIndex.nightPot] = level
					end),
					1,
					{ lang = "fr" }
				)
			end
			expect(txt(at(0).effect.before)).toBe("upgrades.unit.percent n=25")
			expect(txt(at(0).effect.after)).toBe("upgrades.unit.percent n=28")
			expect(txt(at(1).effect.before)).toBe("upgrades.unit.percent n=28")
			expect(txt(at(1).effect.after)).toBe("upgrades.unit.percent n=31")
			expect(txt(at(2).effect.before)).toBe("upgrades.unit.percent n=31")
			expect(at(2).effect.after).toBe(nil)
		end)

		it(
			"Gants ×1,150 → ×1,175 (3 décimales), Décorations : effet réel du prochain niveau, Monuments +3 % → +4 %",
			function()
				local g = V.view(
					"gloves",
					snapOf(function(p)
						p.tiles.gloves = 6
					end),
					1,
					{ lang = "fr" }
				)
				expect(txt(g.effect.before)).toBe("upgrades.unit.mult n=1,150")
				expect(txt(g.effect.after)).toBe("upgrades.unit.mult n=1,175")
				local d = V.view("decor", snapOf(), 1, { lang = "fr", aBonus = 1.6 })
				expect(txt(d.effect.label)).toBe("upgrades.effect.incomeTotal a=3,1")
				expect(d.effect.before).toBe(nil)
				expect(d.effect.after).toBe(nil)
				expect(V.view(
					"decor",
					snapOf(function(p)
						p.tiles.decor = 18
					end),
					1,
					{}
				).effect).toBe(nil) -- au maximum : rien de trompeur
				local m = V.view(
					"monument",
					snapOf(function(p)
						p.tiles.monuments = 3
						p.bestR = 12
						p.tiles.snack = 12
					end),
					1,
					{ lang = "fr" }
				)
				expect(txt(m.effect.label)).toBe("upgrades.effect.monument a=3")
				expect(txt(m.effect.after)).toBe("upgrades.unit.count n=+4 %")
				local e = V.view(
					"monument",
					snapOf(function(p)
						p.tiles.monuments = 3
						p.bestR = 12
					end),
					1,
					{ lang = "en" }
				)
				expect(txt(e.effect.after)).toBe("upgrades.unit.count n=+4%")
			end
		)

		it(
			"×10 : la valeur après est celle du niveau atteint (Croissance ×8 → ×13 pour 5 niveaux)",
			function()
				local v = V.view(
					"snack",
					snapOf(function(p)
						p.tiles.snack = 7
						p.coins = 1e300
					end),
					10,
					{ lang = "fr" }
				)
				expect(v.preview.count).toBe(5)
				expect(txt(v.effect.before)).toBe("upgrades.unit.mult n=8")
				expect(txt(v.effect.after)).toBe("upgrades.unit.mult n=13")
			end
		)

		it(
			"« Pour le plaisir » : la ligne du titre s'appelle fun.title.confettiStar (fun.title = titre de la section)",
			function()
				local v = V.view("fun.title", snapOf(), 1, {})
				expect(v.name.key).toBe("fun.title.confettiStar")
				expect(v.sendId).toBe("fun.title")
				expect(v.currency).toBe("confetti")
				expect(V.SECTION_FUN).toBe("fun.title")
			end
		)
	end)

	describe("Upgrades_View › Plopettes (note du lot A3)", function()
		it(
			"nombre : ByRecordR atteints par le Record R, + Plume ; intervalle de l'École ; sieste",
			function()
				local s = snapOf(function(p)
					p.R = 8
					p.bestR = 8
					p.tiles.school = 10
				end)
				expect(V.helperCount(s)).toBe(4)
				expect(V.helperInterval(s)).toBeNear(9.0, 1e-9)
				local pom = V.view("helper.pom", s, 1, { lang = "fr" })
				expect(pom.readOnly).toBe(true)
				expect(pom.state).toBe("max")
				expect(pom.sendId).toBe(nil)
				expect(txt(pom.effect.label)).toBe("helper.interval s=9,0")
				local nap = V.view("helper.pom", s, 1, { lang = "fr", helperMode = "nap" })
				expect(nap.nap).toBe(true)
				expect(txt(nap.effect.label)).toBe("helper.nap")
				local puff = V.view("helper.puff", s, 1, { helperMode = "nap" })
				expect(puff.state).toBe("locked")
				expect(puff.nap).toBe(false)
				expect(txt(puff.stateText)).toBe("upgrades.state.locked r=12")
				expect(txt(puff.effect.label)).toBe("helper.arrives r=12")
				-- Plume : achetée à l'Atelier (ligne plume ≥ 1)
				local withPlume = snapOf(function(p)
					p.R = 12
					p.bestR = 12
					p.atelier[Upgrades.WorkshopIndex.plume] = 1
				end)
				expect(V.helperCount(withPlume)).toBe(6)
				expect(V.view("helper.plume", withPlume, 1, {}).state).toBe("max")
				local noPlume = V.view(
					"helper.plume",
					snapOf(function(p)
						p.R = 8
						p.bestR = 8
					end),
					1,
					{}
				)
				expect(txt(noPlume.stateText)).toBe("upgrades.state.locked r=12")
				expect(V.helperCount(snapOf(function(p)
					p.R = 1
					p.bestR = 1
				end))).toBe(0)
			end
		)
	end)

	describe("Upgrades_View › aperçu = UpgradeMath, 2 000 instantanés tirés au hasard", function()
		local function randomSnap(rng)
			local levels, caps = {}, {}
			for _, id in IDS do
				local max = UpgradeMath.maxLevel(id)
				levels[id] = rng.int(0, max)
				caps[id] = if rng.chance(0.3) then 0 else rng.int(0, max)
			end
			local r = rng.int(0, Balance.Prestige.MaxR)
			local coins = if rng.chance(0.1) then 0 else math.floor(10 ^ rng.range(0, 60))
			return {
				coins = coins,
				confetti = rng.int(0, 100000),
				levels = levels,
				caps = caps,
				r = r,
				bestR = rng.int(r, Balance.Prestige.MaxR),
				ascend = rng.int(0, Balance.Prestige.MaxA),
				version = rng.int(1, 1000),
			}
		end
		local MODES = { 1, 10, 0, 5, -1, 0 / 0, "x", nil, 10.5 }

		it(
			"aperçu exact (plan, bulk), jamais un mode, un identifiant ni un niveau invalide à envoyer",
			function()
				local rng = Props.rng(20261106)
				local checked, previews = 0, 0
				for _ = 1, 2000 do
					local s = randomSnap(rng)
					local id = ALL_LINES[rng.int(1, #ALL_LINES)]
					local mode = MODES[rng.int(1, #MODES)]
					local pending = rng.pick({ "none", "busy", "retry" })
					local v = V.view(
						id,
						s,
						mode,
						{ lang = rng.pick({ "fr", "en" }) },
						if pending == "none" then nil else pending
					)
					checked += 1
					-- mode envoyé toujours valide
					expect(v.sendMode == 1 or v.sendMode == 10 or v.sendMode == 0).toBe(true)
					if type(mode) == "number" and (mode == 1 or mode == 10 or mode == 0) then
						expect(v.sendMode).toBe(mode)
					end
					if v.sendId ~= nil then
						-- identifiant canonique connu, niveau attendu = niveau montré de cet identifiant
						expect(ID_SET[v.sendId]).toBe(true)
						expect(UpgradeMath.canonical(v.sendId)).toBe(v.sendId)
						expect(v.expectedLevel).toBe(s.levels[v.sendId])
						expect(v.expectedLevel % 1).toBe(0)
						expect(v.expectedLevel < UpgradeMath.maxLevel(v.sendId)).toBe(true)
						expect(s.caps[v.sendId] > v.expectedLevel).toBe(true) -- ouverte par le plafond seul
						expect(
							v.state == "ready" or v.state == "need" or v.state == "busy" or v.state == "retry"
						).toBe(true)
						expect(v.hidden).toBe(false)
						expect(v.readOnly).toBe(false)
						-- aperçu : somme exacte niveau par niveau
						local p = v.preview
						expect(p ~= nil).toBe(true)
						previews += 1
						local n, total =
							UpgradeMath.bulk(v.sendId, v.expectedLevel, p.count, s.r, s.ascend, s.bestR)
						expect(n).toBe(p.count)
						expect(total).toBe(p.total)
						expect(p.to - p.from).toBe(p.count)
						local have = if v.currency == "confetti" then s.confetti else s.coins
						local planN, planTotal = UpgradeMath.plan(
							v.sendId,
							v.expectedLevel,
							v.sendMode,
							have,
							s.caps[v.sendId],
							s.r,
							s.ascend,
							s.bestR
						)
						if planN >= 1 then
							-- payable : l'aperçu est exactement le débit du serveur
							expect(p.count).toBe(planN)
							expect(p.total).toBe(planTotal)
							expect(p.total <= have).toBe(true)
						else
							-- rien de payable : le premier niveau, « Il manque » le reste
							expect(p.count).toBe(1)
							expect(p.total > have).toBe(true)
							expect(v.missing).toBe(p.total - have)
						end
					else
						expect(v.expectedLevel).toBe(nil)
					end
					-- toujours une clé de Strings pour chaque texte rendu
					for _, t in { v.name, v.stateText, v.banner, v.fate, v.tier, v.reason } do
						if t ~= nil then
							expect(keyExists(t.key)).toBe(true)
						end
					end
				end
				expect(checked).toBe(2000)
				expect(previews > 300).toBe(true)
			end
		)
	end)

	describe(
		"Upgrades_View › Atelier conseillé, Souvenir, « Monte avec ton record », Conseillé",
		function()
			it("au plus 3 lignes de jeu de l'Atelier, les moins chères, ordre fixe à égalité", function()
				expect(V.advised(snapOf())).toEqual({ "gift", "magnet", "nightBag" })
				local some = snapOf(function(p)
					p.atelier[Upgrades.WorkshopIndex.gift] = 2 -- au maximum
					p.atelier[Upgrades.WorkshopIndex.magnet] = 1
				end)
				expect(V.advised(some)).toEqual({ "nightBag", "magnet", "superStreak" })
				local v = V.view("magnet", some, 1, { advised = { magnet = true } })
				expect(v.badge).toBe("advised")
				expect(V.view("decor", some, 1, {}).badge).toBe("loop")
				expect(V.view("pens", some, 1, {}).badge).toBe("kept")
				expect(V.view("gift", some, 1, {}).badge).toBe(nil)
			end)

			it(
				"Souvenir de gelée : Prestige.memoryFactor (×3, ×2, ×1,5, ×1,25 sur la 1re boucle record)",
				function()
					local function mem(r, best, A, regainBonusA, memoryR)
						local s = snapOf(function(p)
							p.R = r
							p.bestR = best
							p.ascend = A
						end)
						return V.memory(s, { lang = "fr", regainBonusA = regainBonusA, memoryR = memoryR })
					end
					expect(mem(3, 15, 1).f).toBe("3")
					expect(mem(13, 15, 1).f).toBe("2")
					expect(mem(14, 15, 1).f).toBe("1,5")
					expect(mem(15, 15, 1, 1, 15).f).toBe("1,25")
					expect(mem(15, 15, 1, 1, 15).active).toBe(true)
					expect(mem(15, 15, 1, 0, 15).active).toBe(false)
					expect(mem(12, 12, 0).f).toBe("1")
					expect(mem(3, 15, 1).factor).toBe(Prestige.memoryFactor(3, 15, false))
				end
			)

			it(
				"« Monte avec ton record » : Cuve 3/8 et palier au Record R 2, prochain déblocage du §4.29",
				function()
					local r = V.rises(snapOf(function(p)
						p.R = 2
						p.bestR = 2
					end))
					expect(r.vat).toBe(3)
					expect(r.vatMax).toBe(8)
					expect(r.v).toBe("3")
					expect(r.tier).toBe(1)
					expect(r.tierMax).toBe(6)
					expect(r.nextR).toBe(3)
					expect(#r.next > 0).toBe(true)
					local top = V.rises(snapOf(function(p)
						p.R = 20
						p.bestR = 20
					end))
					expect(top.nextR).toBe(nil)
					expect(top.tier).toBe(6)
					-- lot B2, étape 2 (D22) : seconde ligne « Cuve 8/8 · palier 4/6 » et bandeau « Au record 13 :
					-- … · Cuve : qualité, vitesse, buses » ; au-delà de la table du §4.29 (Record R 20), la
					-- phrase de repli workshop.desc.risesWithRecord
					local view = V.view("risesWithRecord", snapOf(), 1, {})
					expect(view.readOnly).toBe(true)
					expect(view.sendId).toBe(nil)
					expect(view.effect.label.key).toBe("workshop.risesLine")
					expect(view.effect.label.vars).toEqual({
						vat = "8",
						vatMax = "8",
						tier = "4",
						tierMax = "6",
					})
					expect(view.banner.key).toBe("workshop.risesDetail")
					expect(view.banner.vars.r).toBe("13")
					expect(type(view.banner.vars.unlock) == "string" and #view.banner.vars.unlock > 0).toBe(
						true
					)
					expect(view.banner.vars.quality).toBe("8")
					local beyond = V.view(
						"risesWithRecord",
						snapOf(function(p)
							p.R = 20
							p.bestR = 20
						end),
						1,
						{}
					)
					expect(txt(beyond.banner)).toBe("workshop.desc.risesWithRecord")
				end
			)

			it(
				"contexte du Conseillé (D29) et « une famille de pièces payable » (règle d'UpgradeAdvisor)",
				function()
					expect(V.advisorCtx(true, 301)).toEqual({ ascendReady = true, unpayableSeconds = 301 })
					expect(V.advisorCtx(nil, -5)).toEqual({ ascendReady = false, unpayableSeconds = 0 })
					expect(V.anyPayable(snapOf(function(p)
						p.coins = 1e300
					end))).toBe(true)
					expect(V.anyPayable(snapOf(function(p)
						p.coins = 0
					end))).toBe(false)
				end
			)
		end
	)
end
