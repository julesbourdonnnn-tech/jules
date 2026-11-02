--!nocheck
-- Captures à l'instant de l'appui sous latence (docs/04 §11.14, §17.3 « latence réelle » ; GDD §12.5).
-- Modèle réseau réaliste : le client et le serveur partagent l'horloge (Clock) ; les positions du
-- personnage ET le message Catch(id, tClient) mettent L secondes (aller) pour arriver au serveur. Le
-- client appuie quand il VOIT la fuite du Rush (16 studs/s) à une distance d (sa position et
-- SeededPath.pos(tClient), même code des deux côtés).
--   * L = 0, 100 et 250 ms ; joueur immobile (la fuite passe) ou qui poursuit à 14 studs/s ;
--   * client à ≤ 5 studs : ≥ 95 % des captures acceptées ;
--   * client à ≥ 7 studs : aucune acceptée (rayon serveur 5 + 1,5).
local Bots = require("../harness/Bots")
local Brains = require("../harness/Brains")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 + 301 -- Rush en cours

	local function run(L, chase, trials)
		local w = Brains.boot(Harness, { t0 = T0 })
		local profile = Brains.profile(w, { rush = true, squishies = { { s = 2, z = 500 } } })
		local owner = Brains.join(w, 1, { profile = profile })
		local booper = Brains.join(w, 2, { profile = Brains.profile(w, { rush = true }) })
		local catcher = Brains.join(w, 3, { profile = Brains.profile(w, { rush = true }) })
		Brains.frames(w, 2)
		local rng = Brains.rng(1000 + math.floor(L * 1000) + (if chase then 7 else 0))
		local stats = { near = 0, nearOk = 0, far = 0, farOk = 0 }
		for trial = 1, trials do
			local far = trial % 2 == 0
			-- nouvelle fuite (même squishy : la précédente est rentrée)
			w.Chase.returnEscapes(owner, "cozy")
			w.Signals.Booped:Fire(booper, owner, "1", rng:NextNumber(0, 2 * math.pi))
			local esc = nil
			for _, s in Brains.creatures(w, "escape") do
				esc = s
			end
			assert(esc, "fuite créée")
			local path = w.SeededPath.fromSpawn(esc)
			-- l'appui a lieu dans 1 à 6 s (fuite déjà lancée), à la distance d vue par le client
			local s0 = w.Clock.now()
			local tc = s0 + rng:NextNumber(1.5, 6)
			local d = if far then rng:NextNumber(7.2, 9) else rng:NextNumber(0.3, 5)
			local atPress = path(tc)
			local ahead = path(tc + 0.1)
			local dir = w.V3.new(ahead.X - atPress.X, 0, ahead.Z - atPress.Z)
			local vel = if chase and dir.Magnitude > 1e-6 then dir.Unit * 14 else w.V3.zero
			-- position au moment de l'appui : à d studs de la fuite, hors des ranchs et des solides sur
			-- toute la fenêtre suivie (le client marche dans les rues comme un vrai joueur)
			local pressPos = nil
			for _ = 1, 40 do
				local angle = rng:NextNumber(0, 2 * math.pi)
				local candidate =
					w.V3.new(atPress.X + math.cos(angle) * d, 3, atPress.Z + math.sin(angle) * d)
				local clear = true
				for k = -14, 6 do
					local q = candidate + vel * (k * 0.1)
					if w.WL.ranchAt(q) ~= 0 or w.WL.blocked(q.X, q.Z, 1) then
						clear = false
						break
					end
				end
				if clear then
					pressPos = candidate
					break
				end
			end
			assert(pressPos, "position de départ dégagée")
			local function clientAt(t)
				local p = pressPos + vel * (t - tc)
				return w.V3.new(p.X, 3, p.Z)
			end
			-- le client rejoint sa trajectoire 1,2 s avant l'appui
			while w.Clock.now() < tc - 1.2 - L do
				Bots.frame()
			end
			Bots.place(catcher, clientAt(w.Clock.now() - L))
			local sent = false
			for _ = 1, 200 do
				local now = w.Clock.now()
				local arrival = tc + L
				if not sent and now + 0.1 > arrival then
					-- le message arrive entre deux ticks : instant exact, position reçue à cet instant
					w.Clock.freeze(math.max(now, arrival))
					w.h:moveTo(catcher, clientAt(w.Clock.now() - L))
					w.h:fireServer("ReplicatedStorage.Remotes.Catch", catcher, esc.id, tc)
					sent = true
				end
				Bots.frame(function()
					w.h:moveTo(catcher, clientAt(w.Clock.now() + Bots.DT - L))
				end)
				if sent and w.Clock.now() > arrival + 0.35 then
					break
				end
			end
			local ok = w.Chase.active()[esc.id] == nil
			if far then
				stats.far += 1
				stats.farOk += if ok then 1 else 0
			else
				stats.near += 1
				stats.nearOk += if ok then 1 else 0
			end
		end
		expect(table.concat(Brains.problems(w), "\n")).toBe("")
		return stats
	end

	describe("Chase › captures à tClient sous latence", function()
		for _, L in { 0, 0.1, 0.25 } do
			for _, chase in { false, true } do
				local label = string.format(
					"latence %d ms, joueur %s : ≥ 95 %% acceptées à ≤ 5 studs, aucune au-delà de 7",
					math.floor(L * 1000),
					if chase then "qui poursuit" else "immobile"
				)
				it(label, function()
					local stats = run(L, chase, 40)
					expect(stats.near).toBe(20)
					expect(stats.nearOk / stats.near >= 0.95).toBe(true)
					expect(stats.farOk).toBe(0)
				end)
			end
		end
	end)
end
