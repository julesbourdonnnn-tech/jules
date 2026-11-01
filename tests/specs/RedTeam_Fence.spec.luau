--!nocheck
-- RedTeam_Fence (paquet ranch, docs/04 §15, §17.1 couche g, §18.2) : on n'entre jamais chez les autres.
-- Attaques : entrer par le portail, par un coin, en monture (racine 6 studs plus haute), « debout » sur
-- la clôture, sans droit d'agir (rafale) ; saut de la selle géante contre le mur de clôture ; aucun toit
-- atteignable. Défense : poussée du serveur à CHAQUE tick sur la position validée (rectangle du ranch,
-- à plat), aucune exception (même un ami) ; solides de 30 studs, plus hauts que toute portée. Un joueur
-- honnête (chez lui, dans la rue, devant les portails) n'est jamais repoussé.
local Bots = require("../harness/Bots")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000
	local S = "ServerScriptService.Server.Services."

	local function boot()
		local caught = {}
		local w = Bots.boot(Harness, {
			t0 = T0,
			before = function(w)
				w.DS.Settings.AUTOSAVE_INTERVAL = 1e6
				local Diag = w.h:require(S .. "DiagnosticsService")
				Diag.reportCaught = function(where, err)
					table.insert(caught, where .. " : " .. tostring(err))
				end
				Diag.stateTimedOut = function() end
			end,
		})
		w.caught = caught
		w.Ranch = w.h:require(S .. "RanchService")
		w.W = w.h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		w.Balance = w.h:require("ReplicatedStorage.Shared.Config.Balance")
		w.moved = {}
		w.Signals.ServerMoved:Connect(function(p)
			table.insert(w.moved, p)
		end)
		return w
	end

	local function clean(w)
		expect(table.concat(w.caught, "\n")).toBe("")
		expect(table.concat(w.h.errors, "\n")).toBe("")
		expect(table.concat(w.h:warnings(), "\n")).toBe("")
	end

	local function actor(w, p, pos, canAct, rootOffset)
		return {
			player = p,
			slot = w.Ranch.slotOf(p),
			pos = pos,
			canAct = canAct ~= false,
			riding = (rootOffset or 0) > 0,
			rootOffset = rootOffset or 0,
		}
	end

	local function local2world(w, slot, x, y, z)
		local q = w.W.toWorld(slot, w.V3.new(x, 0, z))
		return w.V3.new(q.X, y, q.Z)
	end

	-- Le joueur est-il repoussé depuis cette position (un tick) ?
	local function pushedFrom(w, p, pos, canAct, rootOffset)
		local before = #w.moved
		w.Ranch.step(w.Clock.now(), { [p] = actor(w, p, pos, canAct, rootOffset) })
		w.h:settle(1)
		return #w.moved > before
	end

	describe("RedTeam_Fence › intrusions", function()
		it(
			"portail, coins, fond du ranch, monture, « debout sur la clôture », sans canAct : toujours repoussé",
			function()
				local w = boot()
				local owner = Bots.join(1)
				local thief = Bots.join(2)
				w.h:makeFriends(1, 2) -- aucune exception, même pour un ami
				local slot = w.Ranch.slotOf(owner)
				local spots = {
					{ 0, 3, 0.5 }, -- juste passé le portail
					{ -31.5, 3, 1 }, -- coin avant gauche
					{ 31.5, 3, 71 }, -- coin du fond
					{ 0, 3, 36 }, -- milieu
					{ 10, 9, 20 }, -- en monture (racine + 6)
					{ -31.9, 25, 40 }, -- « sur » le mur de clôture (aucun toit n'existe : à plat, c'est dedans)
					{ 5, 400, 30 }, -- vol
				}
				for _, s in spots do
					local pos = local2world(w, slot, s[1], s[2], s[3])
					expect({ spot = s, pushed = pushedFrom(w, thief, pos, true, if s[2] == 9 then 6 else 0) }).toEqual({
						spot = s,
						pushed = true,
					})
					expect({ spot = s, pushed = pushedFrom(w, thief, pos, false) }).toEqual({
						spot = s,
						pushed = true,
					})
				end
				-- repoussé 6 studs devant le portail, côté rue
				local root = thief.Character.HumanoidRootPart
				expect((root.Position - w.W.gateOutside(slot)).Magnitude < 1e-3).toBe(true)
				expect(w.W.ranchAt(root.Position)).toBe(0)
				clean(w)
			end
		)

		it(
			"joueur honnête : chez lui, dans la rue et devant les portails, jamais repoussé (16 ranchs occupés)",
			function()
				local w = boot()
				local players = {}
				for i = 1, 16 do
					players[i] = Bots.join(i)
				end
				w.h:settle(2)
				table.clear(w.moved) -- placements des arrivées
				for i, p in players do
					local slot = w.Ranch.slotOf(p)
					-- grille de son propre ranch (bords compris)
					for x = -32, 32, 8 do
						for z = 0, 72, 9 do
							local pos = local2world(w, slot, x, 3, z)
							if pushedFrom(w, p, pos) then
								error(string.format("joueur %d repoussé chez lui en (%d, %d)", i, x, z))
							end
						end
					end
					-- rue devant tous les portails (côté rue de la clôture)
					for k = 1, 16 do
						local pos = local2world(w, k, 0, 3, -6)
						if pushedFrom(w, p, pos) then
							error(string.format("joueur %d repoussé dans la rue devant le ranch %d", i, k))
						end
					end
				end
				expect(#w.moved).toBe(0)
				clean(w)
			end
		)

		it("ranch libre : personne n'y est repoussé (aucun propriétaire présent)", function()
			local w = boot()
			local p = Bots.join(1)
			local pos = local2world(w, 9, 0, 3, 30)
			expect(pushedFrom(w, p, pos)).toBe(false)
			clean(w)
		end)
	end)

	describe("RedTeam_Fence › hauteur des solides", function()
		it(
			"saut de la selle géante + hausse de la monture < mur de clôture : aucun toit, aucun mur enjambable",
			function()
				local w = boot()
				local Formulas = w.h:require("ReplicatedStorage.Shared.Logic.Formulas")
				local giant = Formulas.rideStats(3)
				local reach = giant.jumpHeight + (giant.hipHeight - w.Balance.Ride.BaseHipHeight)
				expect(reach <= w.W.Const.MaxReach).toBe(true)
				expect(w.W.Const.FenceWallHeight >= w.W.Const.SolidMinHeight).toBe(true)
				expect(w.W.Const.SolidMinHeight > w.W.Const.MaxReach).toBe(true)
				-- chaque boîte solide (sauf le plateau, n° 1) part du sol du plan (Y = 0) et monte plus haut que
				-- toute portée : aucune position « debout sur un mur ou un toit » n'existe
				local solids = w.W.solids()
				expect(#solids > 16).toBe(true)
				for i = 2, #solids do
					local box = solids[i]
					local bottom = box.cframe.Position.Y - box.size.Y / 2
					expect(math.abs(bottom) < 1e-6).toBe(true)
					expect(box.size.Y >= w.W.Const.SolidMinHeight).toBe(true)
					expect(box.size.Y > reach).toBe(true)
				end
				clean(w)
			end
		)
	end)
end
