--!nocheck
-- Équipe rouge des Plopettes (lot A3 ; GDD v2.0 §4.28 « Pas de ferme à Plopettes », §13 ; docs/04 §27.10,
-- §27.13 N23) : le serveur décide de tout, le client ne peut ni réveiller les Plopettes sans jouer, ni
-- faire une pression d'aide, ni déplacer la règle des 12 studs.
--   * second compte garé 5 min (immobile, ou stick calé) : sieste, plus une pièce d'aide ensuite ;
--   * client modifié qui inonde le serveur d'intentions REFUSÉES (uid inconnu, trop loin, types faux,
--     débit dépassé) pour garder les Plopettes éveillées : sieste à l'heure ;
--   * faux HelperPress envoyé par le client (remote serveur → client) : ignoré, aucune pièce, zéro trace ;
--   * position falsifiée près de la limite des 12 studs : téléportation refusée par MoveCheck, la
--     position VALIDÉE fait foi (au choix et à tPress) ; jamais deux récompenses pour une pression.
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 60
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

	local function owner(w, n)
		local list = {}
		for k = 1, n or 8 do
			table.insert(list, { s = 2, z = 100 * k })
		end
		return Brains.profile(w, {
			R = 12,
			squishies = list,
			edit = function(d)
				d.bestR = 12
				d.atelier[w.Upgrades.WorkshopIndex.plume] = 1
			end,
		})
	end

	local function at(w, p, x, z)
		return Brains.atRanch(w, p, x, z)
	end

	local function pressesOf(w, p, since)
		local out = {}
		for _, e in w.pressed do
			if e.p == p and e.t >= (since or -math.huge) then
				table.insert(out, e)
			end
		end
		return out
	end

	local function join(w, userId, x, z)
		local p = Brains.join(w, userId, { profile = owner(w) })
		Bots.place(p, at(w, p, x or 0, z or 60))
		return p
	end

	describe("RedTeam_Helpers › pas de ferme à Plopettes", function()
		it(
			"second compte garé 5 min (une intention à l'arrivée, puis rien) : sieste, plus rien ensuite",
			function()
				local w = boot()
				local main = join(w, 1)
				local alt = join(w, 2)
				Brains.frames(w, 2)
				w.h:fireServer(R .. "SetLock", alt, "1", true) -- seule intention du second compte
				w.h:fireServer(R .. "SetLock", main, "1", true)
				local napAt = w.Clock.now() + w.Balance.Helpers.NapAfter
				-- le compte principal joue (une intention acceptée par minute) ; le second reste garé
				for _ = 1, 10 do
					Brains.frames(w, 600)
					w.h:fireServer(R .. "SetLock", main, "1", false)
				end
				expect(w.Helper.state(alt)).toBe("nap")
				expect(#pressesOf(w, alt) > 0).toBe(true) -- 5 premières minutes : elles travaillent
				-- après l'heure de la sieste (+ 3 s de saut au plus) : plus une pression d'aide
				expect(#pressesOf(w, alt, napAt + 0.11)).toBe(0)
				expect(#pressesOf(w, main, napAt + 60) > 0).toBe(true)
				clean(w)
			end
		)

		it("compte garé dès l'arrivée, jamais une intention : aucune pression d'aide en 10 min", function()
			local w = boot()
			local alt = join(w, 2)
			Brains.frames(w, 6000)
			expect(#pressesOf(w, alt)).toBe(0)
			expect(#w.h:sentTo(alt, "HelperPress")).toBe(0)
			clean(w)
		end)

		it("client modifié : intentions refusées en rafale pendant 6 min : sieste à l'heure", function()
			local w = boot()
			local alt = join(w, 2)
			Brains.frames(w, 2)
			w.h:fireServer(R .. "SetLock", alt, "1", true)
			local t0 = w.Activity.lastIntent(alt)
			local pens = at(w, alt, -22.5, 16)
			local spam = function()
				-- uid inconnu, uid illisible, types faux, trop loin, débit dépassé : tout refusé
				w.h:fireServer(R .. "SetLock", alt, "zzz999", true)
				w.h:fireServer(R .. "SetLock", alt, nil, "x")
				w.h:fireServer(R .. "Press", alt, "1", w.Clock.now()) -- à 44 studs : trop loin
				w.h:fireServer(R .. "Press", alt, "999", w.Clock.now())
				w.h:fireServer(R .. "Press", alt, 0 / 0, 0 / 0)
				w.h:fireServer(R .. "PutDown", alt) -- rien de porté
				w.h:fireServer(R .. "BuyUpgrade", alt, "gloves", 7, 0) -- mode refusé
				w.h:fireServer(R .. "BuyTile", alt, "zzz") -- dalle inconnue (un vrai achat, lui, compte)
				w.h:fireServer(R .. "Catch", alt, 65000, w.Clock.now())
				w.h:fireServer(R .. "Leap", alt, 0 / 0, 1, w.Clock.now())
				w.h:fireServer(R .. "HelperPress", alt, { ownerId = alt.UserId, presses = {} })
			end
			expect(pens ~= nil).toBe(true)
			Brains.frames(w, 3610, spam)
			expect(w.Activity.lastIntent(alt)).toBe(t0)
			expect(w.Helper.state(alt)).toBe("nap")
			expect(#pressesOf(w, alt, t0 + w.Balance.Helpers.NapAfter + 0.11)).toBe(0)
			clean(w)
		end)

		it(
			"faux HelperPress du client (remote serveur → client) : ignoré, aucune pièce, zéro trace",
			function()
				local w = boot()
				local p = join(w, 1)
				Brains.frames(w, 2) -- Plopettes en sieste (aucune intention)
				local before = w.DS.get(p).coins
				for _, payload in
					{
						{
							ownerId = p.UserId,
							presses = { { helper = 1, uid = "1", tPress = w.Clock.now() } },
						},
						{ ownerId = 2, presses = { { helper = 6, uid = "8", tPress = 0 } } },
						"garbage",
						nil,
						{ presses = { { helper = 0 / 0, uid = {}, tPress = math.huge } } },
					}
				do
					for _ = 1, 50 do
						w.h:fireServer(R .. "HelperPress", p, payload)
					end
				end
				Brains.frames(w, 100)
				expect(w.DS.get(p).coins).toBe(before)
				expect(#w.pressed).toBe(0)
				expect(w.Helper.state(p)).toBe("nap")
				expect(w.Activity.lastIntent(p)).toBe(-math.huge)
				clean(w)
			end
		)
	end)

	-- Lot A4 (N23, décision du propriétaire du 6 novembre, A4-12) : MenuActivity réveille les Plopettes ;
	-- un client modifié ne peut ni la faire passer plus d'une fois toutes les 10 s, ni s'en servir pour
	-- changer quoi que ce soit d'autre (profil, pièces, jauge, MEGA)
	describe("RedTeam_Helpers › MenuActivity (lot A4)", function()
		it(
			"rafale de 1 000 MenuActivity : une seule passe le débit (1 / 10 s) ; profil inchangé, aucune pièce, zéro trace",
			function()
				local w = boot()
				local p = join(w, 1)
				Brains.frames(w, 2)
				local Fuzz = require("../harness/Fuzz")
				local active = w.Activity.lastActive(p)
				local sent = {}
				for _, name in { "DataPatch", "Feedback", "Celebrate" } do
					sent[name] = #w.h:sentTo(p, name)
				end
				local ok, diff = Fuzz.profileUnchanged(w.h, p, function()
					local passed = Fuzz.rate(w.h, p, "MenuActivity", 1000, {})
					expect(passed).toBe(1)
				end)
				expect({ ok = ok, diff = diff }).toEqual({ ok = true, diff = nil })
				for _, name in { "DataPatch", "Feedback", "Celebrate" } do
					expect({ remote = name, n = #w.h:sentTo(p, name) }).toEqual({
						remote = name,
						n = sent[name],
					})
				end
				expect(w.Activity.lastIntent(p)).toBe(w.Clock.now())
				expect(w.Activity.lastActive(p)).toBe(active)
				clean(w)
			end
		)

		it(
			"arguments hostiles (types faux, NaN, ±inf, chaînes énormes, tables profondes, arguments en trop) : sans effet de plus, aucune trace ; compte garé qui envoie MenuActivity sans menu : rien d'autre qu'un réveil",
			function()
				local w = boot()
				local p = join(w, 1)
				local q = join(w, 2, 0, 60)
				Brains.frames(w, 2)
				local RateLimit = w.h:require("ServerScriptService.Server.Util.RateLimit")
				local deep = {}
				local cur = deep
				for _ = 1, 40 do
					cur.x = {}
					cur = cur.x
				end
				local Fuzz = require("../harness/Fuzz")
				local activeP = w.Activity.lastActive(p)
				local okQ, diffQ
				local ok, diff = Fuzz.profileUnchanged(w.h, p, function()
					okQ, diffQ = Fuzz.profileUnchanged(w.h, q, function()
						for _, args in
							{
								{ 0 / 0 },
								{ math.huge, -math.huge },
								{ string.rep("A", 100000) },
								{ deep },
								{ { [1] = 1, [3] = 3, x = "y" } },
								{ q.UserId, "1", true, nil, 5 },
								{ "\255\254" },
							}
						do
							RateLimit.clear(p)
							w.h:fireServer(R .. "MenuActivity", p, table.unpack(args, 1, 5))
						end
					end)
				end)
				expect({ ok = ok, diff = diff }).toEqual({ ok = true, diff = nil })
				expect({ ok = okQ, diff = diffQ }).toEqual({ ok = true, diff = nil })
				-- l'autre joueur : jamais réveillé par MenuActivity de p ; p : au plus un réveil
				expect(w.Activity.lastIntent(q)).toBe(-math.huge)
				expect(w.Activity.lastActive(p)).toBe(activeP)
				Brains.frames(w, 2)
				expect(w.Helper.state(q)).toBe("nap")
				clean(w)
			end
		)
	end)

	describe("RedTeam_Helpers › position falsifiée près de la limite des 12 studs", function()
		it(
			"vraiment près (5 studs) mais téléportation annoncée loin : rewind, le squishy n'est jamais visé",
			function()
				local w = boot()
				local p = join(w, 1)
				local c = w.WL.toLocal(w.Ranch.slotOf(p), w.Squishy.placeOf(p, "8"))
				Bots.place(p, at(w, p, c.X, c.Z + 5))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "SetLock", p, "1", true)
				-- le client annonce 40 studs plus loin d'un coup (sans placement du serveur)
				local fake = at(w, p, c.X, c.Z + 45)
				for _ = 1, 200 do
					w.h:moveTo(p, fake)
					Brains.frames(w, 1)
				end
				local valid = w.MC.lastValid(p)
				local place = w.Squishy.placeOf(p, "8")
				local dx, dz = valid.X - place.X, valid.Z - place.Z
				expect(math.sqrt(dx * dx + dz * dz) < 12).toBe(true)
				for _, args in w.h:sentTo(p, "HelperPress") do
					for _, e in args[1].presses do
						expect(e.uid ~= "8").toBe(true)
					end
				end
				for _, e in w.pressed do
					expect(e.uid ~= "8").toBe(true)
				end
				clean(w)
			end
		)

		it(
			"à 12,05 studs (visé) puis téléportation sur la cible pendant le saut : une seule récompense",
			function()
				local w = boot()
				local p = join(w, 1)
				local c = w.WL.toLocal(w.Ranch.slotOf(p), w.Squishy.placeOf(p, "8"))
				Bots.place(p, at(w, p, c.X, c.Z + 12.05))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "SetLock", p, "1", true)
				local target = nil
				for _ = 1, 30 do
					Brains.frames(w, 1)
					for _, args in w.h:sentTo(p, "HelperPress") do
						for _, e in args[1].presses do
							if e.uid == "8" then
								target = e
							end
						end
					end
					if target then
						break
					end
				end
				expect(target ~= nil).toBe(true)
				-- le client se téléporte sur la cible et presse : MoveCheck refuse, la pression aussi
				local presses = 0
				w.Signals.Pressed:Connect(function()
					presses += 1
				end)
				local onTarget = at(w, p, c.X, c.Z + 1)
				while w.Clock.now() < target.tPress + 0.5 do
					w.h:moveTo(p, onTarget)
					w.h:fireServer(R .. "Press", p, "8", w.Clock.now())
					Brains.frames(w, 1)
				end
				local got = 0
				for _, e in w.pressed do
					if e.uid == "8" then
						got += 1
					end
				end
				-- jamais deux récompenses pour le même squishy dans la même recharge
				expect(got + presses <= 1).toBe(true)
				clean(w)
			end
		)

		it(
			"marche honnête de 12,5 à 9 studs pendant le saut : abandon à tPress (position validée)",
			function()
				local w = boot()
				local p = join(w, 1)
				local c = w.WL.toLocal(w.Ranch.slotOf(p), w.Squishy.placeOf(p, "8"))
				Bots.place(p, at(w, p, c.X, c.Z + 12.5))
				Brains.frames(w, 2)
				w.h:fireServer(R .. "SetLock", p, "1", true)
				local target = nil
				for _ = 1, 30 do
					Brains.frames(w, 1)
					for _, args in w.h:sentTo(p, "HelperPress") do
						for _, e in args[1].presses do
							if e.uid == "8" then
								target = e
							end
						end
					end
					if target then
						break
					end
				end
				expect(target ~= nil).toBe(true)
				local dest = at(w, p, c.X, c.Z + 9)
				Brains.frames(w, 35, function()
					Bots.stepToward(p, dest, 0.5)
				end)
				for _, e in w.pressed do
					expect(e.uid ~= "8").toBe(true)
				end
				expect(w.Helper.counters().Abandoned >= 1).toBe(true)
				clean(w)
			end
		)
	end)
end
