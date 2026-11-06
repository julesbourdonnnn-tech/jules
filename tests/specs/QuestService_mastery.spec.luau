--!nocheck
-- QuestService v2.0, maîtrise et jalons géants (lot A4, étape 5 ; GDD v2.0 §4.17, §5.4 ; docs/04 §27.5,
-- §27.7 ; décisions D13 et D16 du plan du lot A4) : maîtrise d'espèce donnée toute seule (★5, page dorée
-- sans la Lunaire, Trophée Cristal) : + Balance.Confetti.Mastery une fois, bit de `mastery`, carte
-- « mastery » ; Confettis refusés (interrupteur coupé) : rien d'écrit, nouvel essai ; ancien joueur à sa
-- migration : Confettis sans carte ; jalons géants : attribut GiantTier (1e15, 1e18, 1e21, 1e24),
-- cosmétiques de taille possédés (Logic/Owned), carte « unlock » d'un jalon passé en session ;
-- interrupteur coupé ou profil v1 : rien. Interrupteurs ouverts DANS le test ; SchemaV2 (figé) dans le
-- harnais avant le premier require du schéma (recette de DataChaos). Zéro trace.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
	local S = "ServerScriptService.Server.Services."
	local L = "ReplicatedStorage.Shared."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	-- opts : v1 (serveur v1 : profils v1), flags (interrupteurs ouverts)
	local function boot(opts)
		opts = opts or {}
		local w = Brains.boot(if opts.v1 then Harness else HarnessV2, { t0 = T0, stubMeta = false })
		w.Q = w.h:require(S .. "QuestService")
		w.C = w.h:require(S .. "CommunityService")
		w.World = w.h:require(S .. "WorldService")
		w.Owned = w.h:require(L .. "Logic.Owned")
		w.Bitset = w.h:require(L .. "Logic.Bitset")
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

	-- mutations d'une page dorée (les 8 hors Lunaire) et bit de la Lunaire
	local function goldenMask(w)
		local mask = 1 -- bit 0 : page de l'espèce
		for _, def in w.Mutations.List do
			if not w.Mutations.GoldenPageExcludes[def.id] then
				mask = bit32.bor(mask, bit32.lshift(1, def.id))
			end
		end
		return mask
	end

	local function lunarBit(w)
		for id in w.Mutations.GoldenPageExcludes do
			return bit32.lshift(1, id)
		end
		return 0
	end

	-- espèce s maîtrisée dans le profil : ★1 à ★5, page dorée, Trophée Cristal
	local function master(w, d, s)
		d.dex.stars[s] = 0x1F
		d.dex.mut[s] = goldenMask(w)
		d.trophies[s] = 1e12
	end

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

	-- `n` vues de 10 s (tick de QuestService)
	local function wait10(w, n)
		for _ = 1, n or 1 do
			w.Clock.advance(10.1)
			w.Q.step(w.Clock.now())
		end
	end

	local function masteries(p)
		local out = {}
		for _, d in Bots.celebrations(p, "mastery") do
			table.insert(out, d.species)
		end
		return out
	end

	local function sizeCards(p)
		local out = {}
		for _, d in Bots.celebrations(p, "unlock") do
			if d.kind ~= "deco" then
				table.insert(out, d.kind .. "." .. d.id)
			end
		end
		return out
	end

	local function giantTier(w, p)
		return w.World.ranchModel(w.Ranch.slotOf(p)):GetAttribute("GiantTier")
	end

	describe("QuestService v2.0 › maîtrise d'espèce [Mastery] (D13)", function()
		it(
			"les 3 cases (★5, page dorée sans la Lunaire, Trophée Cristal) : + 25 Confettis une fois, bit, carte « mastery » ; une case manquante : rien",
			function()
				local w = boot({ flags = { "Mastery", "Confetti" } })
				local p = join(w, 1, function(d)
					master(w, d, 1) -- sans la Lunaire
					master(w, d, 3)
					d.dex.mut[3] = bit32.bor(d.dex.mut[3], lunarBit(w)) -- avec la Lunaire : pareil
					master(w, d, 2)
					d.dex.stars[2] = 0x0F -- ★4 seulement
					master(w, d, 4)
					d.dex.mut[4] = bit32.band(d.dex.mut[4], bit32.bnot(bit32.lshift(1, 1))) -- une mutation manque
					master(w, d, 5)
					d.trophies[5] = 1e12 - 1 -- Trophée d'or seulement
				end)
				local d = data(w, p)
				-- vue à l'arrivée
				expect(masteries(p)).toEqual({ 1, 3 })
				expect(d.confetti).toBe(2 * w.Balance.Confetti.Mastery)
				expect(d.confettiTotal).toBe(50)
				for s = 1, 5 do
					expect({ s = s, bit = w.Bitset.has(d.mastery, s) }).toEqual({
						s = s,
						bit = s == 1 or s == 3,
					})
				end
				-- une seule fois
				wait10(w, 3)
				expect(masteries(p)).toEqual({ 1, 3 })
				expect(d.confetti).toBe(50)
				-- le Trophée Cristal de l'espèce 5 : vue suivante (10 s)
				d.trophies[5] = 1e12
				w.Clock.advance(5)
				w.Q.step(w.Clock.now())
				expect(masteries(p)).toEqual({ 1, 3 })
				w.Clock.advance(5.2)
				w.Q.step(w.Clock.now())
				expect(masteries(p)).toEqual({ 1, 3, 5 })
				expect(d.confetti).toBe(75)
				expect(w.Bitset.count(d.mastery)).toBe(3)
				-- Owned dit les mêmes cases
				local a, b, c = w.Owned.mastery(d, 2)
				expect({ a, b, c }).toEqual({ false, true, true })
				a, b, c = w.Owned.mastery(d, 4)
				expect({ a, b, c }).toEqual({ true, false, true })
				clean(w)
			end
		)

		it(
			"Confettis coupés : rien d'écrit (ni bit, ni carte, ni Confettis) ; repris à la vue suivante quand ils s'ouvrent",
			function()
				local w = boot({ flags = { "Mastery" } })
				local p = join(w, 1, function(d)
					master(w, d, 1)
				end)
				local d = data(w, p)
				wait10(w, 3)
				expect(w.Bitset.count(d.mastery)).toBe(0)
				expect(#masteries(p)).toBe(0)
				expect(d.confetti).toBe(0)
				assert(w.Features.set("Confetti", true))
				wait10(w, 1)
				expect(masteries(p)).toEqual({ 1 })
				expect(d.confetti).toBe(25)
				expect(w.Bitset.has(d.mastery, 1)).toBe(true)
				clean(w)
			end
		)

		it(
			"ancien joueur à sa migration (carte « Bienvenue » en attente) : maîtrises déjà faites créditées sans carte ; une maîtrise faite ensuite : sa carte",
			function()
				local w = boot({ flags = { "Mastery", "Confetti" } })
				local p = join(w, 1, function(d)
					d.onboarding.welcomeV2Pending = true
					master(w, d, 1)
					master(w, d, 2)
				end)
				local d = data(w, p)
				expect(w.Bitset.count(d.mastery)).toBe(2)
				expect(d.confetti).toBe(50)
				expect(#masteries(p)).toBe(0)
				master(w, d, 6)
				wait10(w, 1)
				expect(masteries(p)).toEqual({ 6 })
				expect(d.confetti).toBe(75)
				clean(w)
			end
		)
	end)

	describe("QuestService v2.0 › jalons géants [Mastery] (D16)", function()
		it(
			"GiantTier = jalons 1e15 / 1e18 / 1e21 / 1e24 atteints, posé à l'arrivée et quand il change ; cosmétiques de taille possédés ; carte « unlock » d'un jalon passé en session, jamais à l'arrivée",
			function()
				local w = boot({ flags = { "Mastery" } })
				local p = join(w, 1, function(d)
					d.biggestEver = 2e15
				end)
				local d = data(w, p)
				expect(giantTier(w, p)).toBe(1)
				expect(#sizeCards(p)).toBe(0)
				expect(w.C.hasCosmetic(p, "saddle", "cosmic")).toBe(true)
				expect(w.C.hasCosmetic(p, "trail", "shootingStars")).toBe(false)
				expect(w.C.hasCosmetic(p, "title", "sunKeeper")).toBe(false)
				d.biggestEver = 5e18
				wait10(w, 1)
				expect(giantTier(w, p)).toBe(2)
				expect(sizeCards(p)).toEqual({ "trail.shootingStars" })
				d.biggestEver = 1e21 -- Squishy-Soleil : aucun cosmétique
				wait10(w, 1)
				expect(giantTier(w, p)).toBe(3)
				expect(#sizeCards(p)).toBe(1)
				d.biggestEver = 1e24
				wait10(w, 2)
				expect(giantTier(w, p)).toBe(4)
				expect(sizeCards(p)).toEqual({ "trail.shootingStars", "title.sunKeeper" })
				expect(w.C.hasCosmetic(p, "title", "sunKeeper")).toBe(true)
				-- équipé (CommunityService) : le titre public suit
				w.h:fireServer("ReplicatedStorage.Remotes.EquipCosmetic", p, "title", "sunKeeper")
				expect(d.cosmetics.title).toBe("sunKeeper")
				-- seuils exacts (module pur)
				for _, c in
					{
						{ 0, 0 },
						{ 1e15 - 1, 0 },
						{ 1e15, 1 },
						{ 1e18, 2 },
						{ 9.99e20, 2 },
						{ 1e21, 3 },
						{ 1e24, 4 },
						{ 1e300, 4 },
					}
				do
					expect({ big = c[1], tier = w.Owned.giantTier({ biggestEver = c[1] }) }).toEqual({
						big = c[1],
						tier = c[2],
					})
				end
				expect(w.Owned.giantTier({ biggestEver = 0 / 0 })).toBe(0)
				expect(w.Owned.giantTier({ biggestEver = math.huge })).toBe(0)
				expect(w.Owned.giantTier(nil)).toBe(0)
				clean(w)
			end
		)

		it(
			"interrupteur coupé : rien d'écrit, aucun attribut, aucune carte ; ouvert en direct : vu dans les 10 s ; coupé en direct : GiantTier effacé",
			function()
				local w = boot({ flags = { "Confetti" } })
				local p = join(w, 1, function(d)
					master(w, d, 1)
					d.biggestEver = 3e18
				end)
				local d = data(w, p)
				wait10(w, 3)
				expect(w.Bitset.count(d.mastery)).toBe(0)
				expect(d.confetti).toBe(0)
				expect(giantTier(w, p)).toBeNil()
				expect(#masteries(p) + #sizeCards(p)).toBe(0)
				expect(w.C.hasCosmetic(p, "saddle", "cosmic")).toBe(false)
				assert(w.Features.set("Mastery", true))
				wait10(w, 1)
				expect(giantTier(w, p)).toBe(2)
				expect(masteries(p)).toEqual({ 1 })
				expect(#sizeCards(p)).toBe(0) -- déjà atteints : rien de nouveau dans la session
				w.Features.set("Mastery", false)
				wait10(w, 1)
				expect(giantTier(w, p)).toBeNil()
				clean(w)
			end
		)

		it("profil v1 (serveur v1), interrupteurs ouverts : jamais rien", function()
			local w = boot({ v1 = true, flags = { "Mastery", "Confetti" } })
			local p = join(w, 1, function(d)
				master(w, d, 1)
				d.biggestEver = 1e24
			end)
			local d = data(w, p)
			wait10(w, 3)
			expect(d.mastery).toBeNil()
			expect(d.confetti).toBeNil()
			expect(giantTier(w, p)).toBeNil()
			expect(#masteries(p) + #sizeCards(p)).toBe(0)
			clean(w)
		end)
	end)
end
