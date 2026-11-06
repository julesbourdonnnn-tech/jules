--!nocheck
-- Relecture indépendante du lot A3 (Plopettes côté serveur ; GDD v2.0 §4.28, docs/04 §27.7, §27.10,
-- §27.13 N23, §27.14) : défauts trouvés par la relecture, chacun écrit en spec rouge AVANT sa
-- correction, et cas limites vérifiés sains (horloge qui saute, image longue).
--   * monture : le squishy monté est dessiné SOUS le joueur (RanchRenderer « ride ») ; une Plopette ne
--     doit jamais sauter sur sa place vide ni le presser (« ni porté », §4.28) ;
--   * « prêt depuis au moins 3 s » compte aussi depuis l'ARRIVÉE du squishy à sa place (éclos, fusionné,
--     lancé au Bassin, posé, descendu de monture, revenu de la clôture) : sinon la Plopette vole la 1re
--     pression du squishy tout neuf, qui est justement le plus gros revenu (visé d'abord) ; une place
--     décalée dans le même lieu (vente d'un plus ancien) n'est pas une arrivée ;
--   * rythme : une pause plus courte que l'intervalle ne rend pas une pression de plus (une pression
--     toutes les 12 − 0,3 × École s par Plopette) ; un saut coupé par une pause repart de sa cible
--     (le client l'a dessiné jusque-là, comme A3-21) ;
--   * image longue (gel du serveur de 5 s) et horloge qui saute en avant : au plus une récompense par
--     Plopette, toutes revérifiées.
-- Interrupteur Helpers ouvert DANS le test (Features.set) ; SchemaV2 ouvert dans le harnais avant le
-- premier require du schéma (recette de DataChaos).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60 -- loin de tout Rush ou MEGA pendant ~4 min
	local L = "ReplicatedStorage.Shared."
	local S = "ServerScriptService.Server.Services."
	local R = "ReplicatedStorage.Remotes."

	local HarnessV2 = setmetatable({
		new = function(options)
			local hh = Harness.new(options)
			hh:require(L .. "Config.Features").Defaults.SchemaV2 = true
			return hh
		end,
	}, { __index = Harness })

	local function boot()
		local w = Brains.boot(HarnessV2, { t0 = T0 })
		w.Helper = w.h:require(S .. "HelperService")
		w.Upgrades = w.h:require(L .. "Config.Upgrades")
		w.Rules = w.h:require("ServerScriptService.Server.Helpers.Rules")
		assert(w.Features.set("Helpers", true))
		w.pressed = {}
		w.Signals.HelperPressed:Connect(function(p, helper, uid, coins)
			table.insert(w.pressed, { p = p, helper = helper, uid = uid, coins = coins, t = w.Clock.now() })
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
	end

	local function pen(n)
		local out = {}
		for k = 1, n or 8 do
			table.insert(out, { s = 2, z = 100 * k })
		end
		return out
	end

	-- profil v2 : Record R 12 (5 Plopettes) + Plume (6e)
	local function owner(w, opts)
		opts = opts or {}
		return Brains.profile(w, {
			R = 12,
			squishies = pen(opts.n),
			edit = function(d)
				d.bestR = 12
				if opts.plume ~= false and type(d.atelier) == "table" then
					d.atelier[w.Upgrades.WorkshopIndex.plume] = 1
				end
				if opts.edit then
					opts.edit(d)
				end
			end,
		})
	end

	local function at(w, p, x, z)
		return Brains.atRanch(w, p, x, z)
	end

	-- monde : propriétaire (userId 1) loin de son enclos (Z = 60 local), réveillé
	local function world(opts)
		opts = opts or {}
		local w = boot()
		local p = Brains.join(w, 1, { profile = owner(w, opts) })
		Bots.place(p, at(w, p, 0, 60))
		Brains.frames(w, 2)
		w.Activity.note(p, w.Clock.now())
		return w, p
	end

	local function messages(w, p)
		local out = {}
		for _, args in w.h:sentTo(p, "HelperPress") do
			table.insert(out, args[1])
		end
		return out
	end

	local function pressesOf(w, p)
		local out = {}
		for _, e in w.pressed do
			if e.p == p then
				table.insert(out, e)
			end
		end
		return out
	end

	-- joue n ticks en notant l'heure de chaque nouveau message HelperPress
	local function framesNoting(w, p, n, out)
		for _ = 1, n do
			local before = #messages(w, p)
			Brains.frames(w, 1)
			local msgs = messages(w, p)
			for i = before + 1, #msgs do
				table.insert(out, { t = w.Clock.now(), msg = msgs[i] })
			end
		end
		return out
	end

	describe("Review_A3 › cibles interdites", function()
		it("monture : le squishy monté (dessiné sous le joueur) n'est jamais visé ni pressé", function()
			local w, p = world({
				n = 8,
				edit = function(d)
					d.biggestEver = 2000 -- selle débloquée
				end,
			})
			w.h:fireServer(R .. "Ride", p, true)
			expect(w.Squishy.riding(p)).toBe(true)
			local ride = w.Ranch.publicOf(w.Ranch.slotOf(p)).ride
			expect(type(ride) == "string" and ride ~= "").toBe(true)
			Brains.frames(w, 300)
			expect(w.Squishy.riding(p)).toBe(true)
			local aimed = 0
			for _, msg in messages(w, p) do
				for _, e in msg.presses do
					if e.uid == ride then
						aimed += 1
					end
				end
			end
			expect(aimed).toBe(0)
			for _, e in pressesOf(w, p) do
				expect(e.uid ~= ride).toBe(true)
			end
			expect(#pressesOf(w, p) > 0).toBe(true) -- les autres squishies sont pressés
			-- pied à terre : la monture redevient une cible (3 s après son retour à sa place)
			w.h:fireServer(R .. "Ride", p, false)
			expect(w.Squishy.riding(p)).toBe(false)
			Brains.frames(w, 400)
			local after = 0
			for _, e in pressesOf(w, p) do
				if e.uid == ride then
					after += 1
				end
			end
			expect(after >= 1).toBe(true)
			clean(w)
		end)

		it(
			"squishy arrivé à l'instant (éclos, donné) : visé au plus tôt ReadyFor s après son arrivée",
			function()
				local w, p = world({ n = 2 }) -- 6 Plopettes, 2 squishies : 4 Plopettes sans cible
				Brains.frames(w, 80)
				expect(w.Helper.counters().NoTarget > 0).toBe(true)
				local uid = w.Squishy.give(p, { s = 2, m = 0, st = 0, z = 5000 }, "test")
				expect(type(uid)).toBe("string")
				expect(w.Squishy.get(p, uid).at).toBe("pen")
				local t0 = w.Clock.now()
				local sends = framesNoting(w, p, 80, {})
				local firstAim = math.huge
				for _, s in sends do
					for _, e in s.msg.presses do
						if e.uid == uid then
							firstAim = math.min(firstAim, s.t)
						end
					end
				end
				-- visé (plus gros revenu), mais jamais avant ReadyFor s après son arrivée
				expect(firstAim < math.huge).toBe(true)
				expect(firstAim >= t0 + w.Balance.Helpers.ReadyFor - 1e-6).toBe(true)
				clean(w)
			end
		)

		it("squishy reposé (porté puis posé) : ReadyFor s après son retour à sa place", function()
			local w, p = world({ n = 2 })
			Brains.frames(w, 80)
			-- le joueur prend le plus gros, s'éloigne, le pose : il retourne à sa place
			local uid = "2"
			local place = w.Squishy.placeOf(p, uid)
			local c = w.WL.toLocal(w.Ranch.slotOf(p), place)
			Bots.place(p, at(w, p, c.X, c.Z + 3))
			Brains.frames(w, 2)
			w.h:fireServer(R .. "PickUp", p, uid)
			expect(w.Squishy.carried(p)).toBe(uid)
			Bots.place(p, at(w, p, 0, 60))
			Brains.frames(w, 60)
			w.h:fireServer(R .. "PutDown", p)
			expect(w.Squishy.carried(p)).toBeNil()
			local t0 = w.Clock.now()
			local sends = framesNoting(w, p, 80, {})
			local firstAim = math.huge
			for _, s in sends do
				for _, e in s.msg.presses do
					if e.uid == uid then
						firstAim = math.min(firstAim, s.t)
					end
				end
			end
			expect(firstAim < math.huge).toBe(true)
			expect(firstAim >= t0 + w.Balance.Helpers.ReadyFor - 1e-6).toBe(true)
			clean(w)
		end)
		it(
			"porté puis posé pendant une pause (aucun choix pendant le portage) : ReadyFor s après la pose",
			function()
				local w, p = world({ n = 8 })
				for _ = 1, 50 do
					if #messages(w, p) > 0 then
						break
					end
					Brains.frames(w, 1)
				end
				expect(#messages(w, p)[1].presses).toBe(6)
				-- pause (sauts abandonnés, aucun choix) ; « 8 » (plus gros revenu) pris puis posé
				w.Helper.pause(p, "review")
				Brains.frames(w, 1)
				local place = w.Squishy.placeOf(p, "8")
				local c = w.WL.toLocal(w.Ranch.slotOf(p), place)
				Bots.place(p, at(w, p, c.X, c.Z + 3))
				Brains.frames(w, 1)
				w.h:fireServer(R .. "PickUp", p, "8")
				expect(w.Squishy.carried(p)).toBe("8")
				Brains.frames(w, 3)
				w.h:fireServer(R .. "PutDown", p)
				expect(w.Squishy.carried(p)).toBeNil()
				Bots.place(p, at(w, p, 0, 60))
				Brains.frames(w, 1)
				local t0 = w.Clock.now()
				w.Helper.resume(p)
				-- les 6 Plopettes partent sur les 7 autres ; « 8 » attend une Plopette libre (intervalle)
				local sends = framesNoting(w, p, 170, {})
				expect(#sends >= 1).toBe(true)
				local firstAim = math.huge
				for _, s in sends do
					for _, e in s.msg.presses do
						if e.uid == "8" then
							firstAim = math.min(firstAim, s.t)
						end
					end
				end
				expect(firstAim < math.huge).toBe(true)
				expect(firstAim >= t0 + w.Balance.Helpers.ReadyFor - 0.11).toBe(true)
				clean(w)
			end
		)
	end)

	describe("Review_A3 › rythme et horloge", function()
		it("une pause plus courte que l'intervalle ne rend aucune pression de plus", function()
			local w, p = world({ n = 8 })
			local interval = w.Rules.interval(0)
			-- premier choix des 6 Plopettes (un message), puis leurs pressions payées
			local sends = framesNoting(w, p, 50, {})
			expect(#sends).toBe(1)
			local chosenAt = sends[1].t
			expect(#sends[1].msg.presses).toBe(6)
			for _ = 1, 60 do
				if #pressesOf(w, p) >= 6 then
					break
				end
				Brains.frames(w, 1)
			end
			expect(#pressesOf(w, p)).toBe(6)
			-- pause brève (1 s) puis reprise : le rythme (un choix par intervalle et par Plopette) tient
			w.Helper.pause(p, "review")
			Brains.frames(w, 10)
			expect(w.Helper.state(p)).toBe("paused")
			w.Helper.resume(p)
			local after = framesNoting(w, p, 160, {})
			expect(#after >= 1).toBe(true)
			for _, s in after do
				expect(s.t >= chosenAt + interval - 1e-6).toBe(true)
			end
			clean(w)
		end)

		it("pause pendant les sauts (jamais payés) : les Plopettes repartent dès la reprise", function()
			local w, p = world({ n = 8 })
			for _ = 1, 50 do
				if #messages(w, p) > 0 then
					break
				end
				Brains.frames(w, 1)
			end
			expect(#messages(w, p)).toBe(1)
			-- en vol : pause tout de suite (aucune récompense), reprise 1 s après
			w.Helper.pause(p, "review")
			Brains.frames(w, 10)
			expect(#pressesOf(w, p)).toBe(0)
			w.Helper.resume(p)
			local resumedAt = w.Clock.now()
			local again = framesNoting(w, p, 20, {})
			expect(#again >= 1).toBe(true)
			expect(again[1].t <= resumedAt + w.Rules.WAKE_DELAY + 0.21).toBe(true)
			expect(#again[1].msg.presses).toBe(6)
			-- le client a dessiné chaque saut coupé jusqu'à sa cible (aucun message pour un abandon) : le
			-- saut suivant part de cette cible (même règle que A3-21 pour l'abandon à tPress)
			local first = {}
			for _, e in messages(w, p)[1].presses do
				first[e.helper] = e.uid
			end
			for _, e in again[1].msg.presses do
				local a = w.Squishy.placeOf(p, first[e.helper])
				local b = w.Squishy.placeOf(p, e.uid)
				local expected = w.Rules.travel(a.X, a.Z, b.X, b.Z)
				expect({ helper = e.helper, travel = e.tPress - again[1].t }).toEqual({
					helper = e.helper,
					travel = expected,
				})
			end
			clean(w)
		end)

		it(
			"image longue de 5 s puis horloge qui saute de 10 min : au plus une récompense par Plopette",
			function()
				local w, p = world({ n = 8 })
				-- des sauts en cours
				for _ = 1, 60 do
					local moving = 0
					for _, h in w.Helper.helpers(p) do
						if h.moving then
							moving += 1
						end
					end
					if moving >= 6 then
						break
					end
					Brains.frames(w, 1)
				end
				local before = #pressesOf(w, p)
				w.Clock.advance(5) -- gel du serveur : un seul tick rattrape 5 s
				Brains.frames(w, 1)
				local paid = #pressesOf(w, p) - before
				expect(paid <= 6).toBe(true)
				local seen = {}
				for i = before + 1, #pressesOf(w, p) do
					local e = pressesOf(w, p)[i]
					expect(seen[e.helper]).toBeNil()
					seen[e.helper] = true
				end
				-- saut de 10 min : la sieste (aucune intention depuis plus de 5 min), rien de payé
				local n = #pressesOf(w, p)
				w.Clock.advance(600)
				Brains.frames(w, 5)
				expect(w.Helper.state(p)).toBe("nap")
				expect(#pressesOf(w, p)).toBe(n)
				-- réveil : les pressions reprennent, une par Plopette et par intervalle
				w.Activity.note(p, w.Clock.now())
				Brains.frames(w, 60)
				expect(#pressesOf(w, p) > n).toBe(true)
				clean(w)
			end
		)
	end)
end
