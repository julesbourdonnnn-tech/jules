--!nocheck
-- PromptController (paquet client-world, docs/04 §13.3, §18.2, GDD §10.4) : prêts d'abord pour □,
-- cible stable puis changée quand une autre est nettement meilleure, verrou pendant un maintien (et sa
-- sortie garantie), aucune cible derrière une fenêtre (signaux de FocusGuard), prochain prêt 0,15 s
-- après une pression, Bassin en portant, dalle sous les pieds, clôture d'un autre ranch (boop), créature
-- à portée, cycle L1 / R1, zéro trace.

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local T0 = 1796724120

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local function ranch(slot, userId, over)
		local r = {
			slot = slot,
			userId = userId,
			name = "P",
			hidden = false,
			R = 0,
			fame = 0,
			day = 0,
			mode = "cozy",
			shield = false,
			boopable = false,
			tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false, seen = 0 },
			vat = true,
			pool = true,
			vatFill = 0,
			growth = { G = 0, g = 0, t = T0 },
			carry = "",
			ride = "",
			saddle = 0,
			waiting = "",
			theme = "",
			flag = "",
			title = "",
			saddleColor = "",
			trail = "",
			best = { s = 0, m = 0, z = 0, zg = 0 },
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function sq(ready, at)
		return { s = 1, m = 0, st = 0, z = 5, zg = 0, at = at or "pen", bf = 0, o = "", ready = ready }
	end

	local function client(opts)
		opts = opts or {}
		local h = Harness.new({ mode = "client", console = true })
		h:createRemotes()
		local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
		Clock.freeze(T0)
		local base = "StarterPlayer.StarterPlayerScripts.Client."
		h:require(base .. "Util.Prefs").Init()
		h:require(base .. "Controllers.StateController").Init()
		local WSC = h:require(base .. "Controllers.WorldStateController")
		WSC.Init()
		WSC.Start()
		local FocusGuard = h:require(base .. "UI.FocusGuard")
		local PC = h:require(base .. "Controllers.PromptController")
		PC.Init()
		PC.Start()
		local ranches = { ["3"] = ranch(3, 1, opts.mine) }
		if opts.other then
			ranches["4"] = ranch(4, 2, opts.other)
		end
		h:fireClient("ReplicatedStorage.Remotes.RanchSnapshot", {
			seq = 1,
			ranches = ranches,
			squishies = { ["3"] = opts.squishies or {}, ["4"] = opts.otherSquishies or {} },
		})
		h:settle(1)
		local WorldLayout = h:require("ReplicatedStorage.Shared.Logic.WorldLayout")
		local changes = {}
		PC.Changed:Connect(function(t)
			table.insert(changes, { t = t })
		end)
		local c = {
			h = h,
			PC = PC,
			WSC = WSC,
			Clock = Clock,
			WorldLayout = WorldLayout,
			FocusGuard = FocusGuard,
			changes = changes,
		}
		function c.place(pos, lookAt)
			local p = Vector3.new(pos.X, WorldLayout.supportY(pos) + 3, pos.Z)
			local target = lookAt and Vector3.new(lookAt.X, p.Y, lookAt.Z) or (p + Vector3.new(0, 0, -1))
			h.localPlayer.Character.HumanoidRootPart.CFrame = CFrame.lookAt(p, target)
		end
		function c.run(seconds)
			local dt = 1 / 30
			for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
				Clock.advance(dt)
				PC._step(dt)
			end
			h:settle(1)
		end
		function c.clean()
			expect(#h.errors).toBe(0)
			expect(#h:warnings()).toBe(0)
		end
		return c
	end

	describe("PromptController", function()
		it(
			"□ : les squishies prêts passent avant ceux en recharge (même plus proches et en face)",
			function()
				local c = client({ squishies = { a = sq(0), b = sq(T0 + 5) } })
				local pa, pb = c.WorldLayout.penSlot(3, 1), c.WorldLayout.penSlot(3, 2)
				local mid = pa:Lerp(pb, 0.6)
				c.place(mid, pb)
				c.run(0.1)
				local t = c.PC.current()
				expect(t ~= nil).toBe(true)
				expect(t.kind).toBe("squishy")
				expect(t.uid).toBe("a")
				expect(t.primary).toBe("press")
				expect(t.secondary).toBe("pickup")
				expect(t.slot).toBe(3)
				c.clean()
			end
		)

		it("cible stable d'une image à l'autre, changée quand une autre est nettement meilleure", function()
			local c = client({ squishies = { a = sq(0), b = sq(0) } })
			local pa, pb = c.WorldLayout.penSlot(3, 1), c.WorldLayout.penSlot(3, 2)
			c.place(pa:Lerp(pb, 0.3), pa)
			c.run(0.1)
			expect(c.PC.current().uid).toBe("a")
			local n = #c.changes
			c.run(1)
			expect(#c.changes).toBe(n) -- aucun signal tant que rien ne change
			c.place(pa:Lerp(pb, 0.8), pb)
			c.run(0.1)
			expect(c.PC.current().uid).toBe("b")
			c.clean()
		end)

		it(
			"verrou pendant un maintien : la cible ne change pas ; unlock la libère ; sortie garantie après 6 s",
			function()
				local c = client({ squishies = { a = sq(0), b = sq(0) } })
				local pa, pb = c.WorldLayout.penSlot(3, 1), c.WorldLayout.penSlot(3, 2)
				c.place(pa:Lerp(pb, 0.3), pa)
				c.run(0.1)
				c.PC.lock("boop")
				c.place(pa:Lerp(pb, 0.8), pb)
				c.run(1)
				expect(c.PC.current().uid).toBe("a")
				c.PC.unlock()
				c.run(0.1)
				expect(c.PC.current().uid).toBe("b")
				c.PC.lock("bowl")
				c.place(pa:Lerp(pb, 0.3), pa)
				c.run(6.5)
				expect(c.PC.locked()).toBe(false)
				expect(c.PC.current().uid).toBe("a")
				c.clean()
			end
		)

		it("aucune cible derrière une fenêtre (FocusGuard), elle revient à la fermeture", function()
			local c = client({ squishies = { a = sq(0) } })
			c.place(c.WorldLayout.penSlot(3, 1) + Vector3.new(0, 0, 3), c.WorldLayout.penSlot(3, 1))
			c.run(0.1)
			expect(c.PC.current() ~= nil).toBe(true)
			c.FocusGuard.WindowOpened:Fire("Menu")
			c.h:settle(1)
			expect(c.PC.current()).toBe(nil)
			c.run(0.2)
			expect(c.PC.current()).toBe(nil)
			expect(c.changes[#c.changes].t).toBe(nil)
			c.FocusGuard.WindowClosed:Fire("Menu")
			c.h:settle(1)
			c.run(0.1)
			expect(c.PC.current().uid).toBe("a")
			c.clean()
		end)

		it("après une pression : le prochain prêt en 0,15 s ; L1 / R1 défilent les candidats", function()
			local c = client({ squishies = { a = sq(0), b = sq(0) } })
			local pa, pb = c.WorldLayout.penSlot(3, 1), c.WorldLayout.penSlot(3, 2)
			c.place(pa:Lerp(pb, 0.3), pa)
			c.run(0.1)
			expect(c.PC.current().uid).toBe("a")
			c.PC.afterPress()
			c.run(0.1)
			expect(c.PC.current().uid).toBe("a")
			c.run(0.1)
			expect(c.PC.current().uid).toBe("b")
			c.PC.cycle(1)
			local first = c.PC.current().uid
			c.PC.cycle(1)
			expect(c.PC.current().uid ~= first).toBe(true)
			c.clean()
		end)

		it(
			"en portant : le Bassin (□ Poser dans le Bassin, ○ Poser) près du Bassin, rien ailleurs",
			function()
				local c = client({ mine = { carry = "a" }, squishies = { a = sq(0) } })
				c.place(c.WorldLayout.anchor(3, "pool") + Vector3.new(0, 0, -8))
				c.run(0.1)
				local t = c.PC.current()
				expect(t.kind).toBe("pool")
				-- GDD §4.9 : sans jumeau, l'invite dit « Poser dans le Bassin » (INT-CWR-3)
				expect(t.primary).toBe("putInPool")
				expect(t.secondary).toBe("putdown")
				c.place(c.WorldLayout.penSlot(3, 1))
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				c.clean()
			end
		)

		it("dalle sous les pieds : □ Acheter ; clôture d'un autre ranch au Rush : □ Booper", function()
			local c = client({
				other = { mode = "rush" },
				otherSquishies = { x = sq(0) },
			})
			c.place(c.WorldLayout.padSocket(3, 1))
			c.run(0.1)
			local t = c.PC.current()
			expect(t.kind).toBe("pad")
			expect(t.tile).toBe("snack")
			expect(t.primary).toBe("buy")
			c.h:fireClient("ReplicatedStorage.Remotes.Fence", { slot = 4, uids = { "x" }, reason = "rush" })
			c.h:settle(1)
			local fp = c.WorldLayout.fencePoint(4, 1)
			local street = c.WorldLayout.toWorld(4, Vector3.new(c.WorldLayout.toLocal(4, fp).X, 0, -2))
			c.place(street, fp)
			c.run(0.1)
			t = c.PC.current()
			expect(t.kind).toBe("fence")
			expect(t.slot).toBe(4)
			expect(t.uid).toBe("x")
			expect(t.primary).toBe("boop")
			c.clean()
		end)

		it(
			"créature attrapable à portée : □ Attraper ; bond visé (leapTarget) ; personnage absent : rien",
			function()
				local c = client()
				c.h:fireClient("ReplicatedStorage.Remotes.ChaseEvent", {
					spawns = {
						{
							id = 12,
							kind = "wild",
							species = 1,
							mutation = 0,
							size = 2,
							stars = 0,
							ownerSlot = 0,
							booperSlot = 0,
							uid = "",
							path = "escape",
							seed = 3,
							t0 = T0,
							startNode = 2,
							awayAngle = 1,
							center = { x = 0, z = 0 },
							speed = 16,
							duration = 25,
							personal = false,
						},
					},
					finishes = {},
				})
				c.h:settle(1)
				local p = c.WSC.creaturePos(12, T0 + 1 / 30)
				c.place(p + Vector3.new(2, 0, 0), c.WSC.creaturePos(12, T0 + 0.4))
				c.run(1 / 30)
				local t = c.PC.current()
				expect(t.kind).toBe("creature")
				expect(t.id).toBe(12)
				expect(t.primary).toBe("catch")
				expect(c.PC.leapTarget()).toBe(12)
				c.h.localPlayer.Character:Destroy()
				c.h.localPlayer.Character = nil
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				expect(c.PC.leapTarget()).toBe(nil)
				c.clean()
			end
		)
		-- Revue client-world (GDD §4.9 « Prendre et lancer ») : l'invite du Bassin dit « Fusion ! » quand
		-- un jumeau (même espèce, mêmes étoiles) y attend
		it("en portant : □ « Fusion ! » quand un jumeau attend dans le Bassin", function()
			local c = client({ mine = { carry = "a" }, squishies = { a = sq(0), b = sq(0, "pool") } })
			c.place(c.WorldLayout.anchor(3, "pool") + Vector3.new(0, 0, -8))
			c.run(0.1)
			local t = c.PC.current()
			expect(t.kind).toBe("pool")
			expect(t.primary).toBe("fusion")
			expect(t.secondary).toBe("putdown")
			c.clean()
		end)

		-- Revue client-world : les squishies pressés (recharge locale de 1 s) ne s'accumulent pas
		it("squishies pressés : la recharge locale est oubliée une fois passée (pas de fuite)", function()
			local c = client({ squishies = { a = sq(0), b = sq(0) } })
			c.place(c.WorldLayout.penSlot(3, 1))
			for _ = 1, 30 do
				c.run(0.1)
				c.PC.afterPress()
				c.run(0.3)
			end
			c.run(2)
			c.PC.afterPress()
			c.run(0.3)
			expect(c.PC._pressedCount() <= 1).toBe(true)
			c.clean()
		end)

		-- lot B4, étape 5 (D21, INT-B4-KIOSK) : kiosque de Big Plop, □ « Atelier » ; le kiosque n'existe que
		-- construit par Render/WorldV2 (instantané de l'écran Améliorations et une ligne de l'Atelier)
		it(
			"kiosque : □ « Atelier » à 8 studs seulement s'il est construit ; jamais en portant ni derrière une fenêtre",
			function()
				local c = client({ squishies = { a = sq(0) } })
				local base = "StarterPlayer.StarterPlayerScripts.Client."
				local WV = c.h:require(base .. "Render.WorldV2")
				local kiosk = c.WorldLayout.plaza("kiosk")
				c.place(kiosk + Vector3.new(4, 0, -3))
				c.run(0.1)
				-- interrupteurs coupés (aucun instantané) : aucun kiosque, aucune cible
				WV.update({ ambience = false, winter = false })
				c.run(0.1)
				expect(WV.kioskOpen()).toBe(false)
				expect(c.PC.current()).toBe(nil)
				-- instantané de l'écran Améliorations : le kiosque est construit, □ « Atelier »
				local fs = require("@lune/fs")
				local serde = require("@lune/serde")
				local UM = c.h:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
				local Features = c.h:require("ReplicatedStorage.Shared.Config.Features")
				local flags = {}
				for k, v in Features.Defaults do
					flags[k] = if type(v) == "boolean" then true else v
				end
				local profile = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))
				c.h:require(base .. "UI.UpgradeSnapshot").start()
				c.h:fireClient(
					"ReplicatedStorage.Remotes.DataSnapshot",
					{ coins = 0, upgradeSnapshot = UM.snapshot(profile, flags, 1) }
				)
				c.h:settle(1)
				WV.update({ ambience = false, winter = false })
				expect(WV.kioskOpen()).toBe(true)
				c.run(0.1)
				local t = c.PC.current()
				expect(t ~= nil and t.kind).toBe("kiosk")
				expect(t.primary).toBe("workshop")
				expect(t.secondary).toBe("")
				expect(t.slot).toBe(0)
				-- à 9 studs : rien
				c.place(kiosk + Vector3.new(9, 0, 0))
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				-- fenêtre ouverte : rien ; fermée : la cible revient
				c.place(kiosk + Vector3.new(4, 0, -3))
				c.run(0.1)
				c.FocusGuard.WindowOpened:Fire("Upgrades")
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				c.FocusGuard.WindowClosed:Fire("Upgrades")
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current().kind).toBe("kiosk")
				-- en portant un squishy : seul le Bassin compte, jamais le kiosque
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 2, ranches = { ["3"] = { carry = "a" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				-- kiosque retiré (instantané retiré) : plus de cible
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 3, ranches = { ["3"] = { carry = "" } }, ops = {} }
				)
				c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", {}, { "upgradeSnapshot" })
				c.h:settle(1)
				WV.update({ ambience = false, winter = false })
				c.run(0.1)
				expect(WV.kioskOpen()).toBe(false)
				expect(c.PC.current()).toBe(nil)
				c.clean()
			end
		)

		-- lot B3, étape 5 (D22, INT-B3-BINOCULARS) : jumelles à 8 studs du portail d'un AUTRE ranch occupé,
		-- dans la rue ; seulement interrupteur Hearts ouvert, profil v2 et ranch visé qui porte BestR
		it(
			"jumelles : □ « Regarder » devant le portail du voisin (Hearts, profil v2, BestR) ; jamais en portant, derrière une fenêtre, ni interrupteurs coupés",
			function()
				local MockInstance = require("../harness/MockInstance")
				local UpgradeScreen = require("../harness/UpgradeScreen")
				local c = client({ other = { name = "" } })
				local world = MockInstance.new("Folder")
				world.Name = "Wobbleton"
				world.Parent = c.h.workspace
				local list = MockInstance.new("Folder")
				list.Name = "Ranches"
				list.Parent = world
				local m4 = MockInstance.new("Model")
				m4.Name = "4"
				m4.Parent = list
				m4:SetAttribute("BestR", 3)
				local gate = c.WorldLayout.gateOutside(4)
				c.place(gate)
				c.run(0.1)
				-- interrupteurs coupés (aucun features.v2, profil v1) : rien
				expect(c.PC.current()).toBe(nil)
				c.h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { coins = 0, version = 2 })
				c.h:fireClient(
					"ReplicatedStorage.Remotes.EventState",
					UpgradeScreen.eventState(UpgradeScreen.V2_ALL)
				)
				c.h:settle(1)
				c.run(0.1)
				local t = c.PC.current()
				expect(t ~= nil and t.kind).toBe("binoculars")
				expect(t.primary).toBe("binoculars")
				expect(t.secondary).toBe("")
				expect(t.slot).toBe(4)
				expect(t.id).toBe(2)
				-- fenêtre ouverte : rien ; fermée : la cible revient
				c.FocusGuard.WindowOpened:Fire("Settings")
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				c.FocusGuard.WindowClosed:Fire("Settings")
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current().kind).toBe("binoculars")
				-- en portant : seul le Bassin compte
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 2, ranches = { ["3"] = { carry = "a" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				c.h:fireClient(
					"ReplicatedStorage.Remotes.RanchPatch",
					{ seq = 3, ranches = { ["3"] = { carry = "" } }, ops = {} }
				)
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current().kind).toBe("binoculars")
				-- sans BestR : rien ; interrupteur Hearts coupé : rien
				m4:SetAttribute("BestR", nil)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				m4:SetAttribute("BestR", 3)
				local flags = table.clone(UpgradeScreen.V2_ALL)
				flags.Hearts = nil
				c.h:fireClient("ReplicatedStorage.Remotes.EventState", UpgradeScreen.eventState(flags))
				c.h:settle(1)
				c.run(0.1)
				expect(c.PC.current()).toBe(nil)
				c.clean()
			end
		)
	end)
end
