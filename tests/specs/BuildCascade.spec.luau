--!nocheck
-- BuildCascade (lot B4, étape 3 ; docs/04 §27.7 ; GDD v2.0 §9.4, §10.7.8 ; décisions D12, D29 du plan
-- B4) : cascade de construction des décors v2.0.
--   * temps du GDD §9.4 : départ 8 studs sous la place, montée en 0,30 s (Back Out) jusqu'à l'échelle
--     1,15, retour à 1 en 0,15 s, 0,04 s entre deux pièces, 1,2 s au plus (écart resserré) ;
--   * file de 10 (un 11e job pose le plus ancien), 10 s d'attente au plus ;
--   * écran Améliorations ouvert (faux PanelController.Changed et faux Panels.Upgrades.isOpen) : rien
--     ne bouge ni ne se montre, puis UNE cascade groupée de 1,2 s à la fermeture ;
--   * hors du détail complet, derrière la caméra ou à plus de 150 studs : pose finale tout de suite ;
--   * Mouvement réduit : 4 studs, sans dépassement ni changement d'échelle ;
--   * interruptions (flush, nouveau job sur les mêmes pièces, pièce détruite) : poses finales exactes,
--     sans trace ;
--   * sons : +3 % par pièce (+36 % au plus), +2 % par achat de suite dans les 3 s (+24 % au plus), MON
--     ranch seulement, muets pendant un grand spectacle ; DecoPlace repli TileBuild ; signal Piece ;
--   * jobs illisibles : refusés sans trace.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local PATH = "StarterPlayer.StarterPlayerScripts.Client.Render.BuildCascade"
local EPS = 1e-4

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- Cascade neuve, sources remplacées : caméra au-dessus des pièces (regard vers +Z), mon ranch 3
	local function fresh(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local BC = h:require(PATH)
		BC._reset()
		local f = {
			h = h,
			BC = BC,
			t = 100,
			sounds = {},
			pieces = {},
			open = false,
			big = false,
			reduced = false,
			detail = {},
			cam = CFrame.lookAt(Vector3.new(0, 10, -30), Vector3.new(0, 0, 0)),
		}
		BC.configure({
			now = function()
				return f.t
			end,
			mySlot = function()
				return 3
			end,
			detail = function(slot)
				return f.detail[slot] or "full"
			end,
			upgradesOpen = if opts.panels
				then nil
				else function()
					return f.open
				end,
			bigShow = function()
				return f.big
			end,
			camera = function()
				return f.cam
			end,
			reducedMotion = function()
				return f.reduced
			end,
			play = function(name, pitch)
				table.insert(f.sounds, { name, pitch })
			end,
		})
		BC.Piece:Connect(function(slot, position, index)
			table.insert(f.pieces, { slot, position, index })
		end)
		-- n pièces alignées (x = 0, 3, 6 …), tailles 2 × 4 × 2
		function f.job(slot, n, over)
			local parts, finals, sizes = {}, {}, {}
			for i = 1, n do
				local p = MockInstance.new("Part")
				p.Name = "P" .. i
				p.Size = Vector3.new(2, 4, 2)
				p.Parent = h.workspace
				local final = CFrame.new((i - 1) * 3, 2, 0)
				p.CFrame = final
				parts[i], finals[i], sizes[i] = p, final, Vector3.new(2, 4, 2)
			end
			local job = { slot = slot, id = "j" .. slot, parts = parts, finals = finals, sizes = sizes }
			for k, v in over or {} do
				job[k] = v
			end
			return job
		end
		function f.step(dt)
			f.t += dt
			return BC.step(f.t)
		end
		function f.run(seconds, dt)
			dt = dt or 1 / 60
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				f.step(dt)
			end
		end
		-- toutes les pièces à leur pose finale exacte
		function f.final(job)
			for i, p in job.parts do
				if p.CFrame ~= job.finals[i] or p.Size ~= job.sizes[i] then
					return false
				end
			end
			return true
		end
		function f.clean()
			expect(table.concat(h.errors, "\n")).toBe("")
			expect(table.concat(h:warnings(), "\n")).toBe("")
		end
		return f
	end

	describe("BuildCascade › temps du GDD §9.4", function()
		it(
			"8 studs sous la place, 0,30 s Back Out jusqu'à 1,15, retour à 1 en 0,15 s, 0,04 s d'écart",
			function()
				local f = fresh()
				local job = f.job(3, 3)
				expect(f.BC.push(job)).toBe(true)
				-- en attente de la première image : garées sous le sol
				for i, p in job.parts do
					expect(p.CFrame.Position.Y < job.finals[i].Position.Y - 8).toBe(true)
				end
				f.BC.step(f.t) -- départ à t0 = 100
				local p1, p2 = job.parts[1], job.parts[2]
				expect(math.abs(p1.CFrame.Position.Y - (2 - 8)) < EPS).toBe(true)
				expect(math.abs(p1.Size.Y - 4 * 0.6) < EPS).toBe(true)
				expect(p2.CFrame.Position.Y < 2 - 8).toBe(true) -- pas encore partie (0,04 s)
				-- dépassement du Back Out pendant la montée, puis place exacte à 0,30 s
				local above = false
				for _ = 1, 30 do
					f.step(0.01)
					if f.t - 100 < 0.30 - EPS and p1.CFrame.Position.Y > 2 + 0.01 then
						above = true
					end
				end
				expect(above).toBe(true)
				expect(math.abs(f.t - 100.30) < EPS).toBe(true)
				expect(math.abs(p1.CFrame.Position.Y - 2) < 1e-3).toBe(true)
				expect(math.abs(p1.Size.Y - 4 * 1.15) < 0.05).toBe(true)
				-- deuxième pièce : 0,04 s derrière
				expect(math.abs(p2.CFrame.Position.Y - 2) > 0.001).toBe(true)
				f.step(0.04)
				expect(math.abs(p2.CFrame.Position.Y - 2) < 1e-3).toBe(true)
				-- retour à 1 en 0,15 s : pose finale exacte, puis plus rien en file
				f.run(0.2, 0.01)
				expect(f.final(job)).toBe(true)
				expect(f.BC.busy()).toBe(false)
				expect(#f.pieces).toBe(3)
				expect(f.pieces[1][1]).toBe(3)
				expect(f.pieces[2][3]).toBe(2)
				f.clean()
			end
		)

		it("30 pièces : écart resserré, tout est posé en 1,2 s au plus", function()
			local f = fresh()
			local job = f.job(3, 30)
			f.BC.push(job)
			f.BC.step(f.t)
			local t0 = f.t
			while f.BC.busy() and f.t - t0 < 3 do
				f.step(1 / 120)
			end
			expect(f.t - t0 <= 1.2 + 1 / 60).toBe(true)
			expect(f.final(job)).toBe(true)
			f.clean()
		end)
	end)

	describe("BuildCascade › file de 10 et attente de 10 s", function()
		it("un 11e job pose le plus ancien ; plus de 10 s d'attente : pose finale sans animation", function()
			local f = fresh()
			f.open = true
			local list = {}
			for k = 1, 11 do
				local job = f.job(3, 2, { id = "k" .. k })
				list[k] = job
				f.BC.push(job)
				f.step(0.1)
			end
			local st = f.BC.stats()
			expect(st.queued).toBe(10)
			expect(st.maxQueue).toBe(10)
			expect(f.final(list[1])).toBe(true)
			expect(f.final(list[2])).toBe(false) -- garé, en attente
			-- l'écran reste ouvert : à 10 s, chaque job est posé final, sans pièce sortie
			f.run(10.5, 0.1)
			for k = 1, 11 do
				expect(f.final(list[k])).toBe(true)
			end
			expect(f.BC.busy()).toBe(false)
			expect(#f.pieces).toBe(0)
			expect(#f.sounds).toBe(0)
			f.clean()
		end)
	end)

	describe("BuildCascade › écran Améliorations ouvert", function()
		it(
			"faux PanelController.Changed : attente sans rien montrer, puis UNE cascade groupée de 1,2 s",
			function()
				local f = fresh({ panels = true })
				local Signal = f.h:require("ReplicatedStorage.Shared.Util.Signal")
				local changed = Signal.new()
				local top = nil
				f.BC.configure({
					panelController = {
						Changed = changed,
						current = function()
							return top
						end,
					},
					upgradesPanel = {
						isOpen = function()
							return false
						end,
					},
				})
				-- l'écran s'ouvre : le branchement (au premier job) lit le panneau du dessus, puis écoute
				-- Changed
				top = "Upgrades"
				changed:Fire("Upgrades")
				f.h:settle(1)
				local a, b = f.job(3, 12), f.job(3, 12, { id = "b" })
				f.BC.push(a)
				f.step(0.5)
				f.BC.push(b)
				f.run(3, 0.1)
				expect(f.BC.stats().played).toBe(0)
				expect(#f.pieces).toBe(0)
				for _, job in { a, b } do
					for i, p in job.parts do
						expect(p.CFrame.Position.Y < job.finals[i].Position.Y - 8).toBe(true)
					end
				end
				-- fermeture (seul Changed le dit) : les 24 pièces sortent en une seule cascade, posées en 1,2 s
				changed:Fire(nil)
				f.h:settle(1)
				f.BC.step(f.t)
				local t0 = f.t
				while f.BC.busy() and f.t - t0 < 3 do
					f.step(1 / 120)
				end
				expect(f.BC.stats().played).toBe(1)
				expect(f.t - t0 <= 1.2 + 1 / 60).toBe(true)
				expect(f.final(a) and f.final(b)).toBe(true)
				expect(#f.pieces).toBe(24)
				f.clean()
			end
		)

		it(
			"faux Panels.Upgrades.isOpen : attente aussi ; panneau d'un autre écran : rien n'attend",
			function()
				local f = fresh({ panels = true })
				local Signal = f.h:require("ReplicatedStorage.Shared.Util.Signal")
				local isOpen = true
				f.BC.configure({
					panelController = {
						Changed = Signal.new(),
						current = function()
							return "Ranch"
						end,
					},
					upgradesPanel = {
						isOpen = function()
							return isOpen
						end,
					},
				})
				local job = f.job(3, 2)
				f.BC.push(job)
				f.run(1, 0.1)
				expect(f.BC.stats().played).toBe(0)
				isOpen = false
				f.run(1, 0.05)
				expect(f.BC.stats().played).toBe(1)
				expect(f.final(job)).toBe(true)
				-- panneaux introuvables (require qui échoue) : l'écran compte comme fermé, sans trace
				f.BC.configure({ panelController = false, upgradesPanel = false })
				local job2 = f.job(3, 1)
				f.BC.push(job2)
				f.run(1, 0.05)
				expect(f.final(job2)).toBe(true)
				f.clean()
			end
		)
	end)

	describe("BuildCascade › pas d'animation hors de la vue", function()
		it(
			"ranch en détail réduit, pièces derrière la caméra ou à plus de 150 studs : pose finale",
			function()
				local f = fresh()
				f.detail[5] = "reduced"
				local reduced = f.job(5, 3)
				f.BC.push(reduced)
				expect(f.final(reduced)).toBe(true)
				expect(f.BC.busy()).toBe(false)
				-- derrière la caméra
				f.cam = CFrame.lookAt(Vector3.new(0, 10, -30), Vector3.new(0, 10, -60))
				local behind = f.job(3, 3)
				f.BC.push(behind)
				f.BC.step(f.t)
				expect(f.final(behind)).toBe(true)
				-- à plus de 150 studs, devant
				f.cam = CFrame.lookAt(Vector3.new(0, 10, -200), Vector3.new(0, 0, 0))
				local far = f.job(3, 3)
				f.BC.push(far)
				f.BC.step(f.t)
				expect(f.final(far)).toBe(true)
				expect(#f.pieces).toBe(0)
				expect(#f.sounds).toBe(0)
				-- un ranch qui passe en détail réduit pendant l'attente : posé final au départ
				f.cam = CFrame.lookAt(Vector3.new(0, 10, -30), Vector3.new(0, 0, 0))
				f.open = true
				local later = f.job(3, 2)
				f.BC.push(later)
				f.step(0.5)
				f.detail[3] = "reduced"
				f.open = false
				f.step(0.05)
				expect(f.final(later)).toBe(true)
				expect(#f.pieces).toBe(0)
				f.clean()
			end
		)
	end)

	describe("BuildCascade › Mouvement réduit", function()
		it("monte de 4 studs, jamais au-dessus de sa place, sans changement d'échelle", function()
			local f = fresh()
			f.reduced = true
			local job = f.job(3, 1)
			f.BC.push(job)
			f.BC.step(f.t)
			local p = job.parts[1]
			local low, high = math.huge, -math.huge
			while f.BC.busy() do
				low = math.min(low, p.CFrame.Position.Y)
				high = math.max(high, p.CFrame.Position.Y)
				expect(p.Size).toBe(Vector3.new(2, 4, 2))
				f.step(0.01)
			end
			expect(math.abs(low - (2 - 4)) < EPS).toBe(true)
			expect(high <= 2 + EPS).toBe(true)
			expect(f.final(job)).toBe(true)
			f.clean()
		end)
	end)

	describe("BuildCascade › interruptions", function()
		it(
			"flush, nouveau job sur les mêmes pièces, pièce détruite : poses finales exactes, sans trace",
			function()
				local f = fresh()
				local job = f.job(3, 6)
				f.BC.push(job)
				f.BC.step(f.t)
				f.step(0.1)
				-- finalOf rend la vraie place d'une pièce garée ou en montée
				expect(f.BC.finalOf(job.parts[6])).toBe(job.finals[6])
				f.BC.flush(3)
				expect(f.final(job)).toBe(true)
				expect(f.BC.finalOf(job.parts[6])).toBe(nil)
				expect(f.BC.busy()).toBe(false)
				-- les mêmes pièces repoussées en pleine montée : l'ancien job se termine d'abord
				local again = f.job(3, 4)
				f.BC.push(again)
				f.BC.step(f.t)
				f.step(0.12)
				local moved =
					{ slot = 3, id = "moved", parts = again.parts, finals = {}, sizes = again.sizes }
				for i, cf in again.finals do
					moved.finals[i] = cf + Vector3.new(0, 0, 5)
				end
				f.BC.push(moved)
				-- pièce détruite pendant la cascade : sautée
				moved.parts[2]:Destroy()
				f.run(1.5, 0.02)
				expect(f.BC.busy()).toBe(false)
				for i, p in moved.parts do
					if i ~= 2 then
						expect(p.CFrame).toBe(moved.finals[i])
						expect(p.Size).toBe(moved.sizes[i])
					end
				end
				-- flush de tout, d'un ranch sans job, finish d'un job inconnu : rien, sans trace
				f.BC.flush(nil)
				f.BC.flush(9)
				f.BC.finish(3, "nope")
				f.clean()
			end
		)
	end)

	describe("BuildCascade › sons et grands spectacles", function()
		it("MON ranch : +3 % par pièce (+36 % au plus, 13 sons), +2 % par achat dans les 3 s", function()
			local f = fresh()
			local job = f.job(3, 16)
			f.BC.push(job)
			f.BC.step(f.t)
			f.run(1.5, 1 / 60)
			expect(#f.sounds).toBe(13)
			for k, s in f.sounds do
				expect(s[1]).toBe("TileBuild")
				expect(math.abs(s[2] - (1 + math.min(0.36, 0.03 * (k - 1)))) < EPS).toBe(true)
			end
			-- deux achats de suite dans les 3 s (le premier à 1,5 s) : +2 % puis +4 % sur leur pièce
			table.clear(f.sounds)
			f.BC.push(f.job(3, 1, { id = "x1" }))
			f.run(0.6)
			f.BC.push(f.job(3, 1, { id = "x2" }))
			f.run(0.6)
			expect(#f.sounds).toBe(2)
			expect(math.abs(f.sounds[1][2] - 1.02) < EPS).toBe(true)
			expect(math.abs(f.sounds[2][2] - 1.04) < EPS).toBe(true)
			-- plafond +24 % : 14 achats dans la même image (une cascade groupée : +3 % par rang et +2 %
			-- par achat avant lui), puis un achat seul dans les 3 s
			f.t += 10
			table.clear(f.sounds)
			for k = 1, 14 do
				f.BC.push(f.job(3, 1, { id = "y" .. k }))
			end
			f.run(1.5)
			for k, s in f.sounds do
				local expected = 1 + math.min(0.36, 0.03 * (k - 1)) + math.min(0.24, 0.02 * (k + 4 - 1))
				expect(s[2] <= 1 + 0.36 + 0.24 + EPS).toBe(true)
				expect(expected >= s[2] - EPS).toBe(true)
			end
			table.clear(f.sounds)
			f.BC.push(f.job(3, 1, { id = "z" }))
			f.run(0.6)
			expect(#f.sounds).toBe(1)
			expect(math.abs(f.sounds[1][2] - 1.24) < EPS).toBe(true)
			-- ranch d'un autre : animé, muet
			table.clear(f.sounds)
			f.t += 10
			local other = f.job(7, 3)
			f.BC.push(other)
			f.run(1)
			expect(f.final(other)).toBe(true)
			expect(#f.sounds).toBe(0)
			f.clean()
		end)

		it(
			"muet pendant un Rush, un MEGA, un Grand Splorch, une Ascension ou la danse de Big Plop",
			function()
				local f = fresh()
				f.big = true
				local job = f.job(3, 4)
				f.BC.push(job)
				f.run(1)
				expect(f.final(job)).toBe(true)
				expect(#f.pieces).toBe(4) -- la cascade joue, le son se tait
				expect(#f.sounds).toBe(0)
				-- détection par défaut sur l'état des événements (WorldStateController.event)
				local WSC =
					f.h:require("StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldStateController")
				local Clock = f.h:require("ReplicatedStorage.Shared.Util.Clock")
				Clock.freeze(5000)
				f.BC.configure({ bigShow = false })
				local states = {
					{ rush = { active = true } },
					{ mega = { phase = "press" } },
					{ spectacle = { current = { kind = "splorch", endsAt = 5010 } } },
					{ spectacle = { current = { kind = "dance", endsAt = 5010 } } },
					{ spectacle = { current = { kind = "ascend", endsAt = 5010 } } },
				}
				local real = WSC.event
				for _, ev in states do
					WSC.event = function()
						return ev
					end
					f.t += 5
					f.BC.push(f.job(3, 1))
					f.run(0.6)
				end
				expect(#f.sounds).toBe(0)
				-- calme (spectacle fini, MEGA au repos) : le son revient
				WSC.event = function()
					return {
						rush = { active = false },
						mega = { phase = "idle" },
						spectacle = { current = { kind = "splorch", endsAt = 4000 } },
					}
				end
				f.t += 5
				f.BC.push(f.job(3, 1))
				f.run(0.6)
				expect(#f.sounds).toBe(1)
				WSC.event = real
				f.clean()
			end
		)

		it("socle → décoration : DecoPlace s'il a un son, sinon TileBuild", function()
			local f = fresh()
			local Sounds = f.h:require("ReplicatedStorage.Shared.Config.Sounds")
			f.BC.push(f.job(3, 1, { sound = "DecoPlace" }))
			f.run(0.6)
			expect(f.sounds[1][1]).toBe(if Sounds.DecoPlace.id ~= "" then "DecoPlace" else "TileBuild")
			Sounds.DecoPlace.id = "rbxassetid://1"
			f.t += 5
			f.BC.push(f.job(3, 1, { sound = "DecoPlace", id = "d2" }))
			f.run(0.6)
			expect(f.sounds[2][1]).toBe("DecoPlace")
			Sounds.DecoPlace.id = ""
			f.clean()
		end)
	end)

	describe("BuildCascade › jobs illisibles", function()
		it("refusés sans trace ; pièces non BasePart ou poses manquantes ignorées", function()
			local f = fresh()
			local BC = f.BC
			local nan = 0 / 0
			for _, bad in
				{
					nil,
					5,
					{},
					{ slot = nan, parts = {}, finals = {} },
					{ slot = 17, parts = {}, finals = {} },
					{ slot = 2.5, parts = {}, finals = {} },
					{ slot = 3, parts = "x", finals = {} },
					{ slot = 3, parts = { MockInstance.new("Folder") }, finals = { CFrame.new() } },
					{ slot = 3, parts = { f.job(3, 1).parts[1] }, finals = { "cf" } },
				}
			do
				expect(BC.push(bad)).toBe(false)
			end
			-- mélange : seules les entrées valides sont gardées
			local good = f.job(3, 2)
			local mixed = {
				slot = 3,
				id = string.rep("z", 200),
				parts = { good.parts[1], "x", good.parts[2] },
				finals = { good.finals[1], good.finals[2], good.finals[2] },
			}
			expect(BC.push(mixed)).toBe(true)
			f.run(1)
			expect(good.parts[1].CFrame).toBe(good.finals[1])
			expect(good.parts[2].CFrame).toBe(good.finals[2])
			expect(BC.step(nan)).toBe(false)
			BC.configure(nil)
			BC.configure("x")
			f.clean()
		end)
	end)
end
