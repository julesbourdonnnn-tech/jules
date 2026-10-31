--!nocheck
-- Correctifs QA tour 1, paquet world : budget des effets de particules continus des Nebbies
-- (Fire de la forme Blazing, Sparkles des Rares, particules en orbite des Épiques).
-- GDD §12.8 « Particules à l'écran ≤ 300 », §9 Graphismes légers « particules ×0,3 », §4.2, §4.4.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new({ mode = "client" })
		local NB = h:require("ReplicatedStorage.Shared.Render.NebbyBuilder")
		local Nebbies = h:require("ReplicatedStorage.Shared.Config.Nebbies")
		local Balance = h:require("ReplicatedStorage.Shared.Config.Balance")
		return NB, Nebbies, Balance.Render
	end

	local BLAZING = 3

	local function ofClass(model, className)
		local out = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == className then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Effets continus du rig (instances héritées et émetteurs), quel que soit leur nom
	local function emitters(model)
		local out = {}
		for _, d in model:GetDescendants() do
			if d.ClassName == "Fire" or d.ClassName == "Sparkles" or d.ClassName == "ParticleEmitter" then
				table.insert(out, d)
			end
		end
		return out
	end

	local function allEnabled(model, on)
		for _, e in emitters(model) do
			if e.Enabled ~= on then
				return false
			end
		end
		return true
	end

	local function codes(NB, Nebbies)
		return {
			blazing = Nebbies.pack(1, BLAZING, 0),
			rare = Nebbies.pack(Nebbies.byKey.prismpaw, 0, 0),
			epic = Nebbies.pack(Nebbies.byKey.starhorn, 0, 0),
			common = Nebbies.pack(1, 0, 0),
			rareBlazing = Nebbies.pack(Nebbies.byKey.prismpaw, BLAZING, 0),
		}
	end

	describe("Fix world r1 › coût des effets continus", function()
		it(
			"détail complet : Fire (Blazing), Sparkles (Rare) et orbite (Épique) ont un coût > 0",
			function()
				local NB, Nebbies = setup()
				local c = codes(NB, Nebbies)
				local blazing = NB.build(c.blazing, 1, "full")
				local rare = NB.build(c.rare, 1, "full")
				local epic = NB.build(c.epic, 1, "full")
				local common = NB.build(c.common, 1, "full")
				-- comportement du GDD conservé en graphismes normaux : instances héritées allumées
				expect(#ofClass(blazing.model, "Fire")).toBe(1)
				expect(#ofClass(rare.model, "Sparkles")).toBe(1)
				expect(allEnabled(blazing.model, true)).toBe(true)
				expect(allEnabled(rare.model, true)).toBe(true)
				expect(NB.fxParticles(blazing)).toBeGreaterThan(0)
				expect(NB.fxParticles(rare)).toBeGreaterThan(0)
				expect(NB.fxParticles(epic)).toBeGreaterThan(0)
				expect(NB.fxParticles(common)).toBe(0)
				-- Rare Blazing : les deux effets comptent
				local both = NB.build(c.rareBlazing, 1, "full")
				expect(NB.fxParticles(both)).toBeNear(NB.fxParticles(blazing) + NB.fxParticles(rare), 1e-6)
			end
		)

		it("boule et masqué : aucun effet, coût nul", function()
			local NB, Nebbies = setup()
			local c = codes(NB, Nebbies)
			for _, lod in { "ball", "hidden" } do
				local rig = NB.build(c.rareBlazing, 1, lod)
				expect(#emitters(rig.model)).toBe(0)
				expect(NB.fxParticles(rig)).toBe(0)
			end
		end)
	end)

	describe("Fix world r1 › Graphismes légers (particules ×0,3)", function()
		it(
			"Blazing et Rare : plus d'instance héritée, émetteurs réglés à 0,3 × le coût normal",
			function()
				local NB, Nebbies = setup()
				local c = codes(NB, Nebbies)
				for _, code in { c.blazing, c.rare, c.epic, c.rareBlazing } do
					local normal = NB.build(code, 1, "full")
					local low = NB.build(code, 1, "full", { particleMult = 0.3 })
					expect(#ofClass(low.model, "Fire")).toBe(0)
					expect(#ofClass(low.model, "Sparkles")).toBe(0)
					-- forme toujours lisible : un émetteur au moins
					expect(#ofClass(low.model, "ParticleEmitter")).toBeGreaterThanOrEqual(1)
					expect(NB.fxParticles(low)).toBeNear(0.3 * NB.fxParticles(normal), 1e-6)
					-- coût = débit × durée de vie des émetteurs réellement posés
					local sum = 0
					for _, e in ofClass(low.model, "ParticleEmitter") do
						sum += e.Rate * e.Lifetime.Max
					end
					expect(sum).toBeNear(NB.fxParticles(low), 1e-6)
				end
			end
		)

		it("flamme basse qualité : émetteur dirigé vers le haut, couleurs de la flamme", function()
			local NB, Nebbies = setup()
			local low = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full", { particleMult = 0.3 })
			local flame = ofClass(low.model, "ParticleEmitter")[1]
			expect(flame ~= nil).toBe(true)
			expect(flame.EmissionDirection.Name).toBe("Top")
			expect(flame.LightEmission).toBe(1)
			expect(flame.Parent.ClassName).toBe("Attachment")
		end)

		it("particleMult = 0 : aucun effet continu (ni Fire, ni Sparkles, ni orbite)", function()
			local NB, Nebbies = setup()
			local c = codes(NB, Nebbies)
			for _, code in { c.blazing, c.rare, c.epic, c.rareBlazing } do
				local rig = NB.build(code, 1, "full", { particleMult = 0 })
				expect(#emitters(rig.model)).toBe(0)
				expect(NB.fxParticles(rig)).toBe(0)
				expect(rig.orbit).toBeNil()
				-- l'animation ne dépend pas de l'orbite absente
				NB.animate(rig, { t = 1, phase = 0, blink = false, speed = 0 })
			end
		end)

		it("particleMult invalide (NaN, négatif, > 1, texte) : borné sans erreur", function()
			local NB, Nebbies = setup()
			local c = codes(NB, Nebbies)
			local normal = NB.fxParticles(NB.build(c.rareBlazing, 1, "full"))
			expect(NB.fxParticles(NB.build(c.rareBlazing, 1, "full", { particleMult = 0 / 0 }))).toBe(0)
			expect(NB.fxParticles(NB.build(c.rareBlazing, 1, "full", { particleMult = -2 }))).toBe(0)
			expect(NB.fxParticles(NB.build(c.rareBlazing, 1, "full", { particleMult = 5 }))).toBeNear(
				normal,
				1e-6
			)
			expect(NB.fxParticles(NB.build(c.rareBlazing, 1, "full", { particleMult = "x" }))).toBeNear(
				normal,
				1e-6
			)
		end)
	end)

	describe("Fix world r1 › interrupteur et budget", function()
		it("fxEnabled = false : effets créés éteints ; setFx les allume et renvoie le coût", function()
			local NB, Nebbies = setup()
			local c = codes(NB, Nebbies)
			local rig = NB.build(c.rareBlazing, 1, "full", { fxEnabled = false })
			expect(#emitters(rig.model)).toBe(2)
			expect(allEnabled(rig.model, false)).toBe(true)
			local cost = NB.fxParticles(rig)
			expect(NB.setFx(rig, true)).toBeNear(cost, 1e-6)
			expect(allEnabled(rig.model, true)).toBe(true)
			expect(NB.setFx(rig, false)).toBe(0)
			expect(allEnabled(rig.model, false)).toBe(true)
			local epic = NB.build(c.epic, 1, "full", { fxEnabled = false })
			expect(allEnabled(epic.model, false)).toBe(true)
			NB.setFx(epic, true)
			expect(allEnabled(epic.model, true)).toBe(true)
		end)

		it("l'état allumé / éteint survit aux changements de niveau de détail", function()
			local NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full")
			NB.setFx(rig, false)
			NB.setLod(rig, "ball")
			expect(NB.fxParticles(rig)).toBe(0)
			NB.setLod(rig, "hidden")
			NB.setLod(rig, "full")
			expect(#ofClass(rig.model, "Fire")).toBe(1)
			expect(allEnabled(rig.model, false)).toBe(true)
			NB.setFx(rig, true)
			NB.setLod(rig, "ball")
			NB.setLod(rig, "full")
			expect(allEnabled(rig.model, true)).toBe(true)
		end)

		it(
			"Solar Flare : 100 Nebbies en détail complet ; seuls les plus proches s'allument, ≤ budget",
			function()
				local NB, Nebbies, Render = setup()
				local c = codes(NB, Nebbies)
				-- 40 % Blazing, 30 % Rares, 10 % Épiques, le reste Communs (pire cas réaliste)
				local rigs = {}
				for i = 1, Render.MaxFullDetail do
					local k = i % 10
					local code = if k < 4
						then c.blazing
						elseif k < 7 then c.rare
						elseif k < 8 then c.epic
						else c.common
					table.insert(rigs, NB.build(code, 1, "full"))
				end
				-- avant correction : tous les effets hérités allumés, très au-delà de 300 particules
				local before = 0
				for _, rig in rigs do
					before += NB.fxParticles(rig)
				end
				expect(before).toBeGreaterThan(Render.MaxParticles)
				local budget = Render.MaxParticles / 2
				local used = NB.budgetFx(rigs, budget)
				expect(used).toBeLessThanOrEqual(budget)
				expect(used).toBeGreaterThan(0)
				local lit, on = 0, 0
				local firstOff = nil
				for i, rig in rigs do
					local cost = NB.fxParticles(rig)
					local enabled = cost > 0 and allEnabled(rig.model, true)
					if cost > 0 and not enabled and firstOff == nil then
						firstOff = i
					end
					if enabled then
						lit += cost
						on += 1
					elseif cost > 0 then
						expect(allEnabled(rig.model, false)).toBe(true)
					end
				end
				expect(lit).toBeNear(used, 1e-6)
				expect(on).toBeGreaterThan(0)
				-- les plus proches d'abord : le premier rig éteint vient après tous les premiers allumés
				expect(firstOff ~= nil).toBe(true)
				for i = 1, firstOff - 1 do
					local cost = NB.fxParticles(rigs[i])
					if cost > 0 then
						expect(allEnabled(rigs[i].model, true)).toBe(true)
					end
				end
				-- le plus lointain avec effet est éteint
				for i = #rigs, 1, -1 do
					if NB.fxParticles(rigs[i]) > 0 then
						expect(allEnabled(rigs[i].model, false)).toBe(true)
						break
					end
				end
			end
		)

		it(
			"Graphismes légers : budget × 0,3 et coûts × 0,3 → autant de Nebbies, 30 % des particules",
			function()
				local NB, Nebbies, Render = setup()
				local c = codes(NB, Nebbies)
				local normal, low = {}, {}
				for i = 1, 60 do
					local code = if i % 2 == 0 then c.blazing else c.rare
					table.insert(normal, NB.build(code, 1, "full"))
					table.insert(
						low,
						NB.build(code, 1, "full", { particleMult = Render.LowGraphicsParticleMult })
					)
				end
				local budget = Render.MaxParticles / 2
				local usedNormal = NB.budgetFx(normal, budget)
				-- deuxième appelant fictif : le jeu « normal » est d'abord vidé (liste vide → tout éteint)
				expect(NB.budgetFx({}, budget)).toBe(0)
				for _, rig in normal do
					expect(allEnabled(rig.model, false)).toBe(true)
				end
				local usedLow = NB.budgetFx(low, budget * Render.LowGraphicsParticleMult)
				expect(usedLow).toBeLessThanOrEqual(budget * Render.LowGraphicsParticleMult + 1e-6)
				expect(usedLow).toBeNear(usedNormal * Render.LowGraphicsParticleMult, 1e-6)
			end
		)

		it(
			"budget différentiel : un rig sorti de la liste est éteint, un rig revenu est rallumé",
			function()
				local NB, Nebbies = setup()
				local a = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full", { fxEnabled = false })
				local b = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full", { fxEnabled = false })
				local cost = NB.fxParticles(a)
				expect(NB.budgetFx({ a, b }, cost * 2)).toBeNear(cost * 2, 1e-6)
				expect(allEnabled(a.model, true) and allEnabled(b.model, true)).toBe(true)
				-- b est rendu à la réserve : absent de la liste suivante → éteint
				expect(NB.budgetFx({ a }, cost * 2)).toBeNear(cost, 1e-6)
				expect(allEnabled(b.model, false)).toBe(true)
				expect(allEnabled(a.model, true)).toBe(true)
				-- b revient au premier plan
				NB.budgetFx({ b, a }, cost)
				expect(allEnabled(b.model, true)).toBe(true)
				expect(allEnabled(a.model, false)).toBe(true)
			end
		)

		it("entrées hostiles : budget NaN / négatif, doublons, rigs détruits, Gloomwisp, trous", function()
			local NB, Nebbies = setup()
			local rig = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full")
			local cost = NB.fxParticles(rig)
			expect(NB.budgetFx({ rig }, 0 / 0)).toBe(0)
			expect(allEnabled(rig.model, false)).toBe(true)
			expect(NB.budgetFx({ rig }, -10)).toBe(0)
			expect(NB.budgetFx({ rig }, "beaucoup")).toBe(0)
			-- doublon : compté une seule fois
			expect(NB.budgetFx({ rig, rig, rig }, cost * 3)).toBeNear(cost, 1e-6)
			expect(NB.budgetFx({ rig }, math.huge)).toBeNear(cost, 1e-6)
			-- rig détruit, Gloomwisp, Orbe de Comète, valeur non-rig : ignorés
			local dead = NB.build(Nebbies.pack(1, BLAZING, 0), 1, "full")
			NB.destroy(dead)
			expect(NB.fxParticles(dead)).toBe(0)
			expect(NB.setFx(dead, true)).toBe(0)
			local wisp = NB.buildWisp()
			local orb = NB.buildCometOrb()
			expect(NB.fxParticles(wisp)).toBe(0)
			local used = NB.budgetFx({ dead, wisp, orb, 42, "rig", {}, rig } :: any, cost)
			expect(used).toBeNear(cost, 1e-6)
			expect(NB.budgetFx(nil :: any, cost)).toBe(0)
			expect(allEnabled(rig.model, false)).toBe(true)
		end)
	end)
end
