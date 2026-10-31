--!nocheck
-- PathCodec (paquet conga) : format binaire PathStream (docs §10.4) — aller-retour, runs multiples,
-- absence de dérive, bornes des entiers, buffers tronqués ou incohérents.
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function setup()
		local h = Harness.new()
		local PathCodec = h:require("ReplicatedStorage.Shared.Logic.PathCodec")
		return PathCodec, h.globals.Vector3
	end

	-- Marche pseudo-aléatoire déterministe : `count` points, pas ≤ `step` studs par axe
	local function walk(Vector3, count, step, seed, origin)
		local state = seed or 7
		local function rnd()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
		local p = origin or Vector3.new(12.3, 3.1, -45.6)
		local out = {}
		for i = 1, count do
			out[i] = p
			p = p + Vector3.new((rnd() * 2 - 1) * step, (rnd() * 2 - 1) * step * 0.2, (rnd() * 2 - 1) * step)
		end
		return out
	end

	local function maxError(a, b)
		local worst = 0
		for i = 1, #a do
			local d = a[i] - b[i]
			worst = math.max(worst, math.abs(d.X), math.abs(d.Y), math.abs(d.Z))
		end
		return worst
	end

	local function concat(runs)
		local out = {}
		for _, run in runs do
			for _, p in run.points do
				table.insert(out, p)
			end
		end
		return out
	end

	describe("PathCodec › contrat", function()
		it("expose les constantes du format §10.4", function()
			local PC = setup()
			expect(PC.MAX_POINTS).toBe(255)
			expect(PC.MAX_RUNS).toBe(255)
			expect(PC.ABS_SCALE).toBe(8)
			expect(PC.DELTA_SCALE).toBe(16)
			expect(PC.HEADER_BYTES).toBe(3)
			expect(PC.RUN_HEADER_BYTES).toBe(12)
			expect(PC.DELTA_BYTES).toBe(3)
		end)

		it(
			"size() vaut exactement la longueur du buffer encodé (≈ 25 octets par joueur en mouvement)",
			function()
				local PC, V3 = setup()
				local runs = PC.split(4, 100, walk(V3, 4, 1))
				expect(#runs).toBe(1)
				local buf = PC.encode(9, runs)
				expect(buffer.len(buf)).toBe(PC.size(runs))
				-- 1 joueur, 4 miettes (2 nouvelles + 2 répétées) : 3 + 12 + 3 × 3 = 24 octets
				expect(buffer.len(buf)).toBe(24)
				expect(PC.size({})).toBe(3)
			end
		)
	end)

	describe("PathCodec › aller-retour", function()
		it("restitue tick, slot, firstSeq et les points au 1/16 de stud près", function()
			local PC, V3 = setup()
			local points = walk(V3, 120, 1.2)
			local runs = PC.split(7, 4242, points)
			local tick, decoded = PC.decode(PC.encode(1234, runs))
			expect(tick).toBe(1234)
			expect(#decoded).toBe(#runs)
			expect(decoded[1].slot).toBe(7)
			expect(decoded[1].firstSeq).toBe(4242)
			local flat = concat(decoded)
			expect(#flat).toBe(120)
			-- premier point : 1/16 (quantification au 1/8) ; suivants : 1/32 contre la reconstruction
			expect(maxError(flat, points) <= 1 / 16 + 1e-3).toBe(true)
		end)

		it("aucune dérive sur 255 points : chaque delta est calculé contre la reconstruction", function()
			local PC, V3 = setup()
			local points = {}
			for i = 1, 255 do
				points[i] = V3.new(i * 0.4333, 3 + math.sin(i) * 0.3, -i * 0.2777)
			end
			local runs = PC.split(1, 1, points)
			expect(#runs).toBe(1)
			local _, decoded = PC.decode(PC.encode(0, runs))
			local flat = concat(decoded)
			for i = 2, 255 do
				local d = flat[i] - points[i]
				expect(math.abs(d.X) <= 1 / 32 + 1e-3 and math.abs(d.Z) <= 1 / 32 + 1e-3).toBe(true)
			end
		end)

		it("un saut de plus de 7,9 studs ouvre un nouveau run du même slot (seq contigus)", function()
			local PC, V3 = setup()
			local points = {
				V3.new(0, 3, 0),
				V3.new(1, 3, 0),
				V3.new(2, 3, 0),
				V3.new(30, 3, 0), -- téléportation
				V3.new(31, 3, 0),
				V3.new(31, 3, 7.9), -- 7,9 studs : tient dans un i8 (126/16)
				V3.new(31, 3, 16), -- 8,1 studs : nouveau run
			}
			local runs = PC.split(3, 50, points)
			expect(#runs).toBe(3)
			expect(runs[1].firstSeq).toBe(50)
			expect(#runs[1].points).toBe(3)
			expect(runs[2].firstSeq).toBe(53)
			expect(#runs[2].points).toBe(3)
			expect(runs[3].firstSeq).toBe(56)
			expect(runs[3].slot).toBe(3)
			local _, decoded = PC.decode(PC.encode(1, runs))
			expect(#decoded).toBe(3)
			expect(maxError(concat(decoded), points) <= 1 / 16 + 1e-3).toBe(true)
		end)

		it("plus de 255 points : runs de 255 au plus", function()
			local PC, V3 = setup()
			local points = walk(V3, 600, 0.9, 3)
			local runs = PC.split(12, 1, points)
			expect(#runs).toBe(3)
			expect(#runs[1].points).toBe(255)
			expect(#runs[2].points).toBe(255)
			expect(#runs[3].points).toBe(90)
			expect(runs[2].firstSeq).toBe(256)
			expect(runs[3].firstSeq).toBe(511)
			local _, decoded = PC.decode(PC.encode(2, runs))
			expect(#concat(decoded)).toBe(600)
		end)

		it("plusieurs slots dans un même message", function()
			local PC, V3 = setup()
			local runs = {}
			for slot = 1, 12 do
				for _, run in PC.split(slot, slot * 1000, walk(V3, 4, 1.5, slot)) do
					table.insert(runs, run)
				end
			end
			local tick, decoded = PC.decode(PC.encode(65535, runs))
			expect(tick).toBe(65535)
			expect(#decoded).toBe(12)
			for i, run in decoded do
				expect(run.slot).toBe(i)
				expect(run.firstSeq).toBe(i * 1000)
				expect(#run.points).toBe(4)
			end
			-- 12 joueurs en mouvement : bien sous la limite de 900 octets d'un UnreliableRemoteEvent
			expect(PC.size(runs) < 900).toBe(true)
		end)

		it("tick modulo 65536, coordonnées négatives, bornes i16 et valeurs non finies", function()
			local PC, V3 = setup()
			local runs = PC.split(2, 0, {
				V3.new(-179.94, -4.5, 181.3),
				V3.new(-180.2, -4.4, 181.0),
				V3.new(5000, 0, -5000), -- hors i16 : borné, nouveau run
				V3.new(0 / 0, math.huge, 1), -- illisible : traité comme 0
			})
			local tick, decoded = PC.decode(PC.encode(70000, runs))
			expect(tick).toBe(70000 % 65536)
			local flat = concat(decoded)
			expect(math.abs(flat[1].X + 179.94) <= 1 / 16).toBe(true)
			expect(math.abs(flat[2].Z - 181.0) <= 1 / 16).toBe(true)
			expect(flat[3].X).toBe(32767 / 8)
			expect(flat[3].Z).toBe(-32768 / 8)
			for _, p in flat do
				expect(p.X == p.X and p.Y == p.Y and p.Z == p.Z).toBe(true)
			end
		end)

		it("une liste vide se code en 3 octets", function()
			local PC = setup()
			local tick, runs = PC.decode(PC.encode(77, {}))
			expect(tick).toBe(77)
			expect(#runs).toBe(0)
			expect(#PC.split(1, 1, {})).toBe(0)
		end)
	end)

	describe("PathCodec › entrées invalides", function()
		it("chaque troncature d'un buffer valide lève une erreur", function()
			local PC, V3 = setup()
			local buf = PC.encode(5, PC.split(1, 9, walk(V3, 10, 1)))
			local len = buffer.len(buf)
			for cut = 0, len - 1 do
				local short = buffer.create(cut)
				buffer.copy(short, 0, buf, 0, cut)
				expect(function()
					PC.decode(short)
				end).toThrow("tronqué")
			end
		end)

		it("octets en trop, slot 0, run vide et non-buffer sont refusés", function()
			local PC, V3 = setup()
			local buf = PC.encode(5, PC.split(1, 9, walk(V3, 3, 1)))
			local long = buffer.create(buffer.len(buf) + 1)
			buffer.copy(long, 0, buf, 0)
			expect(function()
				PC.decode(long)
			end).toThrow("en trop")
			local zeroSlot = buffer.create(buffer.len(buf))
			buffer.copy(zeroSlot, 0, buf, 0)
			buffer.writeu8(zeroSlot, 3, 0)
			expect(function()
				PC.decode(zeroSlot)
			end).toThrow("slot 0")
			local empty = buffer.create(15)
			buffer.writeu8(empty, 2, 1)
			buffer.writeu8(empty, 3, 4)
			buffer.writeu8(empty, 8, 0)
			expect(function()
				PC.decode(empty)
			end).toThrow("vide")
			for _, bad in { "abc", 12, {}, nil } do
				expect(function()
					PC.decode(bad)
				end).toThrow("buffer attendu")
			end
			-- un client protège le décodage par pcall : aucune exception ne remonte
			local ok = pcall(PC.decode, buffer.create(2))
			expect(ok).toBe(false)
		end)

		it("encode refuse les runs non découpés, vides, trop nombreux ou mal numérotés", function()
			local PC, V3 = setup()
			expect(function()
				PC.encode(1, { { slot = 1, firstSeq = 1, points = { V3.new(0, 0, 0), V3.new(20, 0, 0) } } })
			end).toThrow("split")
			expect(function()
				PC.encode(1, { { slot = 1, firstSeq = 1, points = {} } })
			end).toThrow("points")
			expect(function()
				PC.encode(1, { { slot = 0, firstSeq = 1, points = { V3.new(0, 0, 0) } } })
			end).toThrow("slot")
			expect(function()
				PC.encode(1, { { slot = 1, firstSeq = -1, points = { V3.new(0, 0, 0) } } })
			end).toThrow("firstSeq")
			local many = {}
			for i = 1, 256 do
				many[i] = { slot = 1, firstSeq = i, points = { V3.new(0, 0, 0) } }
			end
			expect(function()
				PC.encode(1, many)
			end).toThrow("runs")
		end)

		it(
			"un buffer aléatoire ne fait jamais planter le décodeur (erreur propre ou résultat cohérent)",
			function()
				local PC = setup()
				local state = 99
				for _ = 1, 300 do
					state = (state * 1103515245 + 12345) % 2147483648
					local len = state % 64
					local buf = buffer.create(len)
					for i = 0, len - 1 do
						state = (state * 1103515245 + 12345) % 2147483648
						buffer.writeu8(buf, i, state % 256)
					end
					local ok, tick, runs = pcall(PC.decode, buf)
					if ok then
						expect(type(tick)).toBe("number")
						for _, run in runs do
							expect(run.slot >= 1 and #run.points >= 1).toBe(true)
						end
					end
				end
			end
		)
	end)
end
