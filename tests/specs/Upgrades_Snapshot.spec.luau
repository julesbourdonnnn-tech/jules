--!nocheck
-- Upgrades_Snapshot (lot B2 ; docs/04 §27.7, §27.8 règle 6 « un seul instantané versionné », §27.10 ;
-- GDD v2.0 §10.8) — partie MODULE (étape 1 : UI/UpgradeSnapshot, sans écran) :
--   * sans la clé `upgradeSnapshot` (interrupteur UpgradesScreen du serveur coupé, la configuration
--     livrée) : available() faux, current() nil, aucun signal, aucune intention ;
--   * instantané d'arrivée et DataPatch : accepté, Changed une fois par version acceptée ;
--   * règle des versions dans les DEUX ordres (UpgradeResult puis DataPatch de la même image, et
--     l'inverse) : la seconde copie de la même version est ignorée ; version égale ou plus ancienne
--     ignorée ; jamais de retour en arrière (versions montrées strictement croissantes) ;
--   * charges hostiles (instantané ou UpgradeResult) : ignorées, sans aucune trace ;
--   * la clé qui disparaît (interrupteur coupé en direct) : available() faux, le dernier instantané reste
--     lisible (écran ouvert figé) ;
--   * un UpgradeResult de BuyTile ou de l'achat au sol (aucune ligne en cours) : son instantané est
--     appliqué, rien d'autre (aucune intention) ; refus « périmé » reconnu (reason nil, from == to) ;
--   * start() idempotent ; copies gelées.
-- Les instantanés sont fabriqués avec UpgradeMath.snapshot (profil témoin tests/fixtures/profiles/v2.json,
-- interrupteurs v2.0 ouverts DANS le test). Zéro trace.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local TvAudit = require("../harness/TvAudit")
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

local V2_INTENTS = { "BuyUpgrade", "MenuActivity", "ClientMetric" }

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- harnais des modules partagés (UpgradeMath, Features) : fabrique les instantanés
	local shared = Harness.new()
	local UpgradeMath = shared:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Features = shared:require("ReplicatedStorage.Shared.Config.Features")

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	-- Interrupteurs v2.0 tous ouverts (table de valeurs, comme une copie figée)
	local ON = {}
	for k, v in Features.Defaults do
		ON[k] = if type(v) == "boolean" then true else v
	end

	-- Instantané fabriqué : profil témoin v2 modifié par `edit`, version `version` (le premier
	-- paramètre, un harnais, est gardé pour la lisibilité des appels)
	local function snapOf(_h, version, edit)
		local p = deepCopy(WITNESS)
		if edit then
			edit(p)
		end
		return UpgradeMath.snapshot(p, ON, version)
	end

	-- Client démarré ; `snap` (facultatif) dans l'instantané d'arrivée ; compteurs des signaux
	local function setup(snapAtBoot)
		local profile = {}
		if snapAtBoot ~= nil then
			profile.upgradeSnapshot = snapAtBoot
		end
		local h = TvAudit.client({ profile = profile })
		local US = TvAudit.mod(h, "UI.UpgradeSnapshot")
		local c = { h = h, US = US, changed = {}, results = {}, avail = {} }
		US.Changed:Connect(function(s)
			table.insert(c.changed, s.version)
		end)
		US.Result:Connect(function(p)
			table.insert(c.results, p)
		end)
		US.AvailableChanged:Connect(function(on)
			table.insert(c.avail, on)
		end)
		return c
	end

	local function patch(h, values, removed)
		h:fireClient("ReplicatedStorage.Remotes.DataPatch", values, removed)
	end

	local function result(h, payload)
		h:fireClient("ReplicatedStorage.Remotes.UpgradeResult", payload)
	end

	local function noV2Intent(h)
		for _, name in V2_INTENTS do
			expect(#TvAudit.sent(h, name)).toBe(0)
		end
	end

	-- Réponse d'achat valide (Décorations, un niveau) portant l'instantané `snap`
	local function bought(snap, from, to)
		return {
			id = "decor",
			from = from,
			to = to,
			spent = 1234,
			currency = "coins",
			reason = nil,
			snapshot = snap,
		}
	end

	describe("Upgrades_Snapshot › interrupteur coupé (aucune clé upgradeSnapshot)", function()
		it("available() faux, current() nil, aucun signal, aucune intention v2.0", function()
			local c = setup(nil)
			c.US.start()
			TvAudit.tick(c.h, 0.5)
			expect(c.US.available()).toBe(false)
			expect(c.US.current()).toBe(nil)
			expect(#c.changed).toBe(0)
			expect(#c.avail).toBe(0)
			noV2Intent(c.h)
			-- un patch sans la clé ne change rien
			patch(c.h, { coins = 99 })
			expect(c.US.available()).toBe(false)
			expect(#c.changed).toBe(0)
			clean(c.h)
		end)

		it("une réponse UpgradeResult hostile ou isolée ne rend pas l'écran disponible", function()
			local c = setup(nil)
			c.US.start()
			result(c.h, { id = "decor" })
			expect(c.US.available()).toBe(false)
			expect(c.US.current()).toBe(nil)
			expect(#c.results).toBe(0)
			clean(c.h)
		end)
	end)

	describe("Upgrades_Snapshot › instantané d'arrivée et DataPatch", function()
		it("instantané d'arrivée accepté : available() vrai, Changed une fois, copie gelée", function()
			local s3 = snapOf(nil, 3)
			local c = setup(s3)
			c.US.start()
			TvAudit.tick(c.h, 0.2)
			expect(c.US.available()).toBe(true)
			expect(c.US.current().version).toBe(3)
			expect(c.changed).toEqual({ 3 })
			expect(c.avail).toEqual({ true })
			local cur = c.US.current()
			expect(table.isfrozen(cur)).toBe(true)
			expect(table.isfrozen(cur.levels)).toBe(true)
			expect(table.isfrozen(cur.caps)).toBe(true)
			-- la source modifiée ensuite ne change pas l'instantané montré
			s3.coins = 1
			s3.levels.decor = 0
			expect(c.US.current().coins).toBe(4250000000)
			expect(c.US.current().levels.decor).toBe(9)
			noV2Intent(c.h)
			clean(c.h)
		end)

		it("start() idempotent : trois appels, un seul Changed par version", function()
			local c = setup(nil)
			c.US.start()
			c.US.start()
			c.US.start()
			patch(c.h, { upgradeSnapshot = snapOf(c.h, 1) })
			patch(c.h, { upgradeSnapshot = snapOf(c.h, 2) })
			expect(c.changed).toEqual({ 1, 2 })
			clean(c.h)
		end)
	end)

	describe("Upgrades_Snapshot › règle des versions (règle 6)", function()
		it("UpgradeResult puis DataPatch de la même image : le patch (même version) est ignoré", function()
			local c = setup(nil)
			c.US.start()
			patch(c.h, { upgradeSnapshot = snapOf(c.h, 4) })
			local s5 = snapOf(c.h, 5, function(p)
				p.tiles.decor = 10
				p.coins -= 1234
			end)
			result(c.h, bought(s5, 9, 10))
			patch(
				c.h,
				{
					upgradeSnapshot = snapOf(c.h, 5, function(p)
						p.tiles.decor = 10
						p.coins -= 1234
					end),
				}
			)
			expect(c.changed).toEqual({ 4, 5 })
			expect(#c.results).toBe(1)
			expect(c.results[1].id).toBe("decor")
			expect(c.results[1].to).toBe(10)
			expect(c.US.current().version).toBe(5)
			expect(c.US.current().levels.decor).toBe(10)
			clean(c.h)
		end)

		it(
			"DataPatch puis UpgradeResult de la même image : l'instantané de la réponse est ignoré, le signal part",
			function()
				local c = setup(nil)
				c.US.start()
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 4) })
				local edit = function(p)
					p.tiles.decor = 10
					p.coins -= 1234
				end
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 5, edit) })
				result(c.h, bought(snapOf(c.h, 5, edit), 9, 10))
				expect(c.changed).toEqual({ 4, 5 })
				expect(#c.results).toBe(1)
				expect(c.results[1].snapshot.version).toBe(5)
				expect(c.US.current().levels.decor).toBe(10)
				clean(c.h)
			end
		)

		it(
			"version égale (contenu différent) ignorée ; version plus ancienne ignorée ; jamais de retour",
			function()
				local c = setup(nil)
				c.US.start()
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 7) })
				-- même version, autre contenu : ignorée
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 7, function(p)
					p.coins = 5
				end) })
				expect(c.US.current().coins).toBe(4250000000)
				-- plus ancienne : ignorée (par l'état comme par apply)
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 6, function(p)
					p.coins = 6
				end) })
				expect(c.US.apply(snapOf(c.h, 2))).toBe(false)
				expect(c.US.current().version).toBe(7)
				expect(c.US.current().coins).toBe(4250000000)
				-- plus récente : acceptée
				expect(c.US.apply(snapOf(c.h, 8, function(p)
					p.coins = 8
				end))).toBe(true)
				expect(c.US.current().coins).toBe(8)
				expect(c.changed).toEqual({ 7, 8 })
				clean(c.h)
			end
		)

		it(
			"200 livraisons mélangées (patchs et réponses) : versions montrées strictement croissantes",
			function()
				local c = setup(nil)
				c.US.start()
				local rng = Props.rng(20261106)
				local shownSeq = {}
				c.US.Changed:Connect(function(s)
					table.insert(shownSeq, s.version)
				end)
				local top = 0
				for _ = 1, 200 do
					local v = rng.int(1, 60)
					top = math.max(top, v)
					local s = snapOf(c.h, v, function(p)
						p.coins = v * 1000
					end)
					if rng.chance(0.5) then
						patch(c.h, { upgradeSnapshot = s })
					else
						result(c.h, bought(s, 9, 9 + (if v % 2 == 0 then 1 else 0)))
					end
				end
				for i = 2, #shownSeq do
					expect(shownSeq[i] > shownSeq[i - 1]).toBe(true)
				end
				expect(c.US.current().version).toBe(top)
				expect(c.US.current().coins).toBe(top * 1000)
				clean(c.h)
			end
		)
	end)

	describe("Upgrades_Snapshot › charges hostiles ignorées sans trace", function()
		it("instantanés abîmés : aucun accepté, aucun signal, aucune erreur ni avertissement", function()
			local c = setup(nil)
			c.US.start()
			patch(c.h, { upgradeSnapshot = snapOf(c.h, 10) })
			local NAN, INF = 0 / 0, math.huge
			local bad = {
				"texte",
				42,
				true,
				{},
				function(s)
					s.version = 0
				end,
				function(s)
					s.version = 11.5
				end,
				function(s)
					s.version = NAN
				end,
				function(s)
					s.version = INF
				end,
				function(s)
					s.version = "11"
				end,
				function(s)
					s.coins = -1
				end,
				function(s)
					s.coins = INF
				end,
				function(s)
					s.coins = NAN
				end,
				function(s)
					s.confetti = -5
				end,
				function(s)
					s.confetti = "9"
				end,
				function(s)
					s.r = 401
				end,
				function(s)
					s.r = -1
				end,
				function(s)
					s.bestR = s.r - 1
				end,
				function(s)
					s.ascend = 61
				end,
				function(s)
					s.ascend = 0.5
				end,
				function(s)
					s.levels = nil
				end,
				function(s)
					s.caps = "x"
				end,
				function(s)
					s.levels.decor = 19 -- au-delà des 18 niveaux
				end,
				function(s)
					s.levels.snack = -1
				end,
				function(s)
					s.levels.gloves = 2.5
				end,
				function(s)
					s.levels["fun.title"] = nil -- un identifiant manquant
				end,
				function(s)
					s.caps.star = 9
				end,
				function(s)
					s.caps.school = NAN
				end,
			}
			for i, b in bad do
				local s
				if type(b) == "function" then
					s = snapOf(c.h, 11 + i, nil)
					b(s)
				else
					s = b
				end
				patch(c.h, { upgradeSnapshot = s })
				expect(c.US.apply(s)).toBe(false)
			end
			expect(c.changed).toEqual({ 10 })
			expect(c.US.current().version).toBe(10)
			-- une charge hostile ne retire pas la disponibilité
			expect(c.US.available()).toBe(true)
			clean(c.h)
		end)

		it("réponses UpgradeResult abîmées : aucun signal Result, aucun instantané appliqué", function()
			local c = setup(nil)
			c.US.start()
			patch(c.h, { upgradeSnapshot = snapOf(c.h, 20) })
			local good = function(v)
				return bought(snapOf(c.h, v), 9, 10)
			end
			local bad = {
				"x",
				{},
				function(p)
					p.id = "inconnu"
				end,
				function(p)
					p.id = "palettes" -- id nu : la réponse dit toujours fun.<id>
					p.currency = "confetti"
				end,
				function(p)
					p.id = 5
				end,
				function(p)
					p.from = 11
					p.to = 10
				end,
				function(p)
					p.to = 19 -- au-delà des 18 niveaux
				end,
				function(p)
					p.from = -1
				end,
				function(p)
					p.from = 9.5
				end,
				function(p)
					p.spent = -3
				end,
				function(p)
					p.spent = math.huge
				end,
				function(p)
					p.to = p.from -- refus qui aurait dépensé
				end,
				function(p)
					p.currency = "confetti" -- monnaie d'une autre ligne
				end,
				function(p)
					p.currency = "robux"
				end,
				function(p)
					p.reason = "upgrades.refused.inconnu"
				end,
				function(p)
					p.reason = "upgrades.refused.coins" -- refus qui aurait acheté
				end,
				function(p)
					p.reason = 7
				end,
				function(p)
					p.snapshot = nil
				end,
				function(p)
					p.snapshot.version = -2
				end,
			}
			for i, b in bad do
				local p
				if type(b) == "function" then
					p = good(30 + i)
					b(p)
				else
					p = b
				end
				result(c.h, p)
			end
			expect(#c.results).toBe(0)
			expect(c.changed).toEqual({ 20 })
			expect(c.US.validateResult(good(99)) ~= nil).toBe(true)
			clean(c.h)
		end)
	end)

	describe("Upgrades_Snapshot › disponibilité (D1, D25)", function()
		it(
			"la clé arrive par un patch, puis disparaît : available() suit, current() reste lisible",
			function()
				local c = setup(nil)
				c.US.start()
				expect(c.US.available()).toBe(false)
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 1) })
				expect(c.US.available()).toBe(true)
				patch(c.h, {}, { "upgradeSnapshot" })
				expect(c.US.available()).toBe(false)
				expect(c.US.current().version).toBe(1)
				expect(c.avail).toEqual({ true, false })
				-- de retour (même version : déjà montrée) : disponible, aucun Changed de plus
				patch(c.h, { upgradeSnapshot = snapOf(c.h, 1) })
				expect(c.US.available()).toBe(true)
				expect(c.changed).toEqual({ 1 })
				expect(c.avail).toEqual({ true, false, true })
				clean(c.h)
			end
		)
	end)

	describe(
		"Upgrades_Snapshot › réponses sans ligne en cours (BuyTile, achat au sol, refus périmé)",
		function()
			it(
				"UpgradeResult d'un BuyTile : son instantané appliqué, Result une fois, aucune intention",
				function()
					local c = setup(nil)
					c.US.start()
					patch(c.h, { upgradeSnapshot = snapOf(c.h, 2) })
					local s3 = snapOf(c.h, 3, function(p)
						p.tiles.decor = 10
					end)
					result(c.h, bought(s3, 9, 10))
					expect(c.changed).toEqual({ 2, 3 })
					expect(c.US.current().levels.decor).toBe(10)
					expect(#c.results).toBe(1)
					expect(c.US.isStale(c.results[1])).toBe(false)
					TvAudit.tick(c.h, 0.5)
					noV2Intent(c.h)
					clean(c.h)
				end
			)

			it(
				"refus « périmé » (reason nil, from == to, rien dépensé) : reconnu, instantané appliqué",
				function()
					local c = setup(nil)
					c.US.start()
					patch(c.h, { upgradeSnapshot = snapOf(c.h, 2) })
					local s3 = snapOf(c.h, 3, function(p)
						p.tiles.decor = 11
					end)
					result(c.h, {
						id = "decor",
						from = 11,
						to = 11,
						spent = 0,
						currency = "coins",
						snapshot = s3,
					})
					expect(#c.results).toBe(1)
					expect(c.US.isStale(c.results[1])).toBe(true)
					expect(c.US.current().levels.decor).toBe(11)
					-- refus avec sa raison : pas « périmé »
					result(c.h, {
						id = "fun.title",
						from = 0,
						to = 0,
						spent = 0,
						currency = "confetti",
						reason = "upgrades.refused.confetti",
						snapshot = snapOf(c.h, 4),
					})
					expect(#c.results).toBe(2)
					expect(c.US.isStale(c.results[2])).toBe(false)
					expect(c.results[2].reason).toBe("upgrades.refused.confetti")
					noV2Intent(c.h)
					clean(c.h)
				end
			)
		end
	)
end
