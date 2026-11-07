--!strict
-- PromptController (paquet client-world, docs/04 §13.3, GDD §10.4).
-- Cible choisie par le jeu, jamais selon la caméra (Logic/TargetRules) :
--   * en portant un squishy : le Bassin à Fusion.ThrowRange studs (□ = Lancer, ○ = Poser) ;
--   * MEGA en phase de pression, dans sa zone (□ = MegaPress) ;
--   * dalle de MON ranch sous mes pieds (□ = Acheter) ; bol du Meilleur Ami (□ maintenu = Nourrir) ;
--   * créature attrapable à portée (□ = Attraper) ;
--   * squishies de mon ranch à Press.Range studs au plus de leur place (prêts d'abord pour □, ○ =
--     Prendre) ou les 4 au plus d'une clôture côté rue (□ = Booper au Rush, Presser en pet-sitting) :
--     score distance + 6 × angle / 90°, hystérésis 1,5 stud ou 0,25 s ; L1 / R1 défilent ces candidats ;
--   * comptoir de la Boutique (□ = Boutique) ;
--   * v2.0 (lot B4, étape 5, INT-B4-KIOSK) : kiosque de Big Plop à 8 studs au plus (□ = Atelier, ouvre
--     l'écran Améliorations sur l'onglet Atelier), seulement tant que le kiosque est construit
--     (Render/WorldV2.kioskOpen : instantané de l'écran et une ligne de l'Atelier visible) ; testé après
--     la Boutique, jamais en portant ni derrière une fenêtre ; interrupteurs coupés : jamais de kiosque.
-- Après une pression, la cible passe au prochain prêt en Press.RetargetDelay (0,15 s). Clic souris :
-- projection à l'écran (RanchRenderer.projected + TargetRules.screenPick), cible fixée
-- ClickTarget.Hold (4 s). Pendant un maintien (boop, bol), la cible est verrouillée (sortie garantie :
-- StateTimeouts « boopHold »). Aucune cible si une fenêtre est ouverte (signaux de FocusGuard) ou sans
-- personnage. La créature visée par le prochain bond (leapTarget) suit LeapRules.aim (position future,
-- direction du stick, hystérésis de 20 %). La cible du jeu est entourée par RanchRenderer.
-- Une seule connexion par image (Heartbeat).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Clock = require(Shared.Util.Clock)
local Balance = require(Shared.Config.Balance)
local Layout = require(Shared.Config.Layout)
local Events = require(Shared.Config.Events)
local Pads = require(Shared.Config.Pads)
local Quests = require(Shared.Config.Quests)
local StateTimeouts = require(Shared.Logic.StateTimeouts)
local TargetRules = require(Shared.Logic.TargetRules)
local LeapRules = require(Shared.Logic.LeapRules)
local ZoneRules = require(Shared.Logic.ZoneRules)
local WorldLayout = require(Shared.Logic.WorldLayout)
local FusionRules = require(Shared.Logic.FusionRules)

local Client = script.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local RanchRenderer = require(Client.Controllers.RanchRenderer)
local Util = require(Client.World.Util)
local Catchable = require(Client.World.Catchable)
local WorldV2 = require(Client.Render.WorldV2)

export type Target = {
	kind: "squishy" | "fence" | "pad" | "bowl" | "pool" | "pot" | "shop" | "mega" | "creature" | "kiosk",
	slot: number,
	uid: string,
	id: number,
	tile: string,
	ready: boolean,
	primary: string, -- action de □ : "press" | "throw" | "fusion" | "putInPool" | "buy" | "boop" | "feed" | "catch" | "sell" | "shop" | "petsit" | "workshop" | ""
	secondary: string, -- action de ○ : "pickup" | "putdown" | ""
	position: Vector3,
}

local PromptController = {}

-- (nouvelle cible)
PromptController.Changed = Signal.new() :: Signal.Signal<Target?>

local SHOP_RADIUS = 8 -- studs du comptoir de la Boutique
local KIOSK_RADIUS = 8 -- studs du kiosque de Big Plop (lot B4, D21)
local LOCK_TIMEOUT = StateTimeouts.seconds("boopHold") + 0.5
local CLICK_HOLD = Layout.ClickTarget.Hold
local RETARGET = Balance.Press.RetargetDelay

local current: Target? = nil
local currentKey = ""
local chosenId: string? = nil -- uid ou « slot:uid » de la clôture retenu par l'hystérésis
local chosenSince = -math.huge
local locked = false
local lockedAt = 0
local clickId: string? = nil
local clickUntil = 0
local afterPressAt: number? = nil
local afterPressId: string? = nil
-- squishy pressé : compté en recharge sur ce client jusqu'au patch du serveur (au plus 1 s)
local pressed: { [string]: number } = {}
local PRESSED_HOLD = 1
local leapId: number? = nil
local windows: { [string]: boolean } = {}
local animT = 0
local started = false
local connections: { any } = {}

local function keyOf(t: Target?): string
	if t == nil then
		return ""
	end
	return table.concat({
		t.kind,
		tostring(t.slot),
		t.uid,
		tostring(t.id),
		t.tile,
		if t.ready then "1" else "0",
		t.primary,
		t.secondary,
	}, "|")
end

local function windowOpen(): boolean
	return next(windows) ~= nil
end

local function lookOf(root: BasePart): Vector3
	local lv = root.CFrame.LookVector
	return Vector3.new(lv.X, 0, lv.Z)
end

local function stickOf(root: BasePart): Vector3
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		local md = hum.MoveDirection
		if Vector3.new(md.X, 0, md.Z).Magnitude > 0.1 then
			return Vector3.new(md.X, 0, md.Z)
		end
	end
	return lookOf(root)
end

local function catchCtx(): Catchable.Ctx
	local slot = WorldStateController.mySlot()
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	local golden = Util.safe("StateController.get", nil, StateController.get, "golden")
	local ev: any = WorldStateController.event()
	return {
		mySlot = slot,
		rush = ranch ~= nil and ranch.mode == "rush",
		features = if type(ev) == "table" and type(ev.features) == "table" then ev.features else {},
		goldenLastWin = if type(golden) == "table" then Util.num(golden.lastWinAt, 0, 0) else 0,
		unixNow = Clock.unix(),
	}
end

local function make(kind: any, slot: number, position: Vector3): Target
	return {
		kind = kind,
		slot = slot,
		uid = "",
		id = 0,
		tile = "",
		ready = true,
		primary = "",
		secondary = "",
		position = position,
	}
end

-- Candidats squishies de mon ranch (prêts d'abord) : liste TargetRules et cibles par id
local function squishyCandidates(
	slot: number,
	pos: Vector3,
	now: number
): ({ TargetRules.Candidate }, { [string]: Target })
	local list: { TargetRules.Candidate } = {}
	local byId: { [string]: Target } = {}
	local ranch = WorldStateController.ranch(slot)
	if ranch == nil then
		return list, byId
	end
	local range = Balance.Press.Range
	for uid, rec in WorldStateController.squishies(slot) do
		if uid ~= ranch.carry and uid ~= ranch.ride then
			local p = RanchRenderer.positionOf(slot, uid)
			if p and ZoneRules.distXZ(pos, p) <= range then
				local ready = rec.ready <= now and not (pressed[uid] ~= nil and now < pressed[uid])
				table.insert(list, { id = uid, pos = p, ready = ready })
				local t = make("squishy", slot, p)
				t.uid = uid
				t.ready = ready
				t.primary = "press"
				t.secondary = if rec.at == "pen" then "pickup" else ""
				byId[uid] = t
			end
		end
	end
	return list, byId
end

-- Candidats d'une clôture d'un autre ranch, côté rue (boop au Rush, pet-sitting)
local function fenceCandidates(
	pos: Vector3,
	mySlot: number
): ({ TargetRules.Candidate }, { [string]: Target })
	local list: { TargetRules.Candidate } = {}
	local byId: { [string]: Target } = {}
	for slot = 1, WorldLayout.Const.Ranches do
		if slot ~= mySlot then
			local uids, reason = WorldStateController.fence(slot)
			if #uids > 0 and reason ~= "" then
				local radius = if reason == "rush" then Events.Rush.BoopRadius else Balance.Press.Range
				if ZoneRules.streetSideOfFence(slot, pos, radius) then
					local squishies = WorldStateController.squishies(slot)
					for i, uid in uids do
						local p = WorldLayout.fencePoint(slot, i)
						if ZoneRules.distXZ(pos, p) <= radius then
							local id = slot .. ":" .. uid
							local rec = squishies[uid]
							local ready = reason == "rush" or (rec ~= nil and rec.ready <= Clock.now())
							table.insert(list, { id = id, pos = p, ready = ready })
							local t = make("fence", slot, p)
							t.uid = uid
							t.ready = ready
							t.primary = if reason == "rush" then "boop" else "petsit"
							byId[id] = t
						end
					end
				end
			end
		end
	end
	return list, byId
end

local function padUnderFeet(slot: number, pos: Vector3): Target?
	if slot == 0 or not WorldLayout.inRanch(slot, pos) then
		return nil
	end
	local root = workspace:FindFirstChild("Wobbleton")
	local ranches = root and root:FindFirstChild("Ranches")
	local model = ranches and ranches:FindFirstChild(tostring(slot))
	local pads = model and model:FindFirstChild("Pads")
	for _, key in Pads.Order do
		local def = Pads.Defs[key]
		local center = WorldLayout.padSocket(slot, def.socket)
		if ZoneRules.distXZ(pos, center) <= Balance.Tiles.EnterRadius then
			local part = pads and pads:FindFirstChild(tostring(def.socket))
			-- dalle éteinte (pas encore découverte, ou au maximum) : aucune invite
			if
				part
				and part:IsA("BasePart")
				and (part.Transparency >= 1 or part:GetAttribute("Maxed") == true)
			then
				return nil
			end
			local t = make("pad", slot, center)
			t.tile = key
			t.primary = "buy"
			return t
		end
	end
	return nil
end

local function nearestCreature(pos: Vector3, now: number): Target?
	local ctx = catchCtx()
	local best: Target? = nil
	local bestD = math.huge
	for id, s in WorldStateController.creatures() do
		if Catchable.check(s, now, ctx) then
			local p = WorldStateController.creaturePos(id, now)
			if p then
				local d = ZoneRules.distXZ(pos, p)
				if d <= Catchable.radius(s, ctx.mySlot) and d < bestD then
					local t = make("creature", s.ownerSlot, p)
					t.id = id
					t.primary = "catch"
					best, bestD = t, d
				end
			end
		end
	end
	return best
end

-- Calcule la cible du moment (sans hystérésis pour les catégories uniques)
local function compute(now: number): Target?
	if windowOpen() then
		return nil
	end
	local root = Util.localRoot()
	if root == nil then
		return nil
	end
	local pos = root.Position
	local slot = WorldStateController.mySlot()
	local ranch = if slot > 0 then WorldStateController.ranch(slot) else nil
	-- en portant : seul le Bassin
	if ranch and ranch.carry ~= "" then
		local pool = WorldLayout.anchor(slot, "pool")
		if ranch.pool and ZoneRules.distXZ(pos, pool) <= Balance.Fusion.ThrowRange then
			local t = make("pool", slot, pool)
			-- □ lance toujours ; l'invite dit « Fusion ! » quand un jumeau attend dans le Bassin, sinon
			-- « Poser dans le Bassin » (GDD §4.9, note INT-CWR-3) : InputController traite les deux en lancer
			t.primary = "putInPool"
			local list = WorldStateController.squishies(slot)
			local carried = list[ranch.carry]
			if carried then
				for uid, rec in list do
					if
						uid ~= ranch.carry
						and rec.at == "pool"
						and Util.safe("FusionRules.areTwins", false, FusionRules.areTwins, carried, rec)
					then
						t.primary = "fusion"
						break
					end
				end
			end
			t.secondary = "putdown"
			return t
		end
		return nil
	end
	local ev: any = WorldStateController.event()
	if type(ev) == "table" and type(ev.mega) == "table" and type(ev.features) == "table" then
		if ev.features.megaSquish == true and ev.mega.phase == "press" and ZoneRules.inMegaZone(pos) then
			local t = make("mega", 0, WorldLayout.plaza("megaPad"))
			t.primary = "press"
			return t
		end
	end
	local pad = padUnderFeet(slot, pos)
	if pad then
		return pad
	end
	if slot > 0 and ZoneRules.distXZ(pos, WorldLayout.anchor(slot, "bowl")) <= Quests.Feed.Radius then
		if WorldLayout.inRanch(slot, pos) then
			local t = make("bowl", slot, WorldLayout.anchor(slot, "bowl"))
			t.primary = "feed"
			return t
		end
	end
	local creature = nearestCreature(pos, now)
	if creature then
		return creature
	end
	-- squishies de mon ranch ou d'une clôture : TargetRules (prêts d'abord, hystérésis)
	local list, byId = {}, {}
	if slot > 0 and WorldLayout.inRanch(slot, pos) then
		list, byId = squishyCandidates(slot, pos, now)
	else
		list, byId = fenceCandidates(pos, slot)
	end
	if #list > 0 then
		if clickId and now < clickUntil and byId[clickId] then
			return byId[clickId]
		end
		local pick = TargetRules.pick(pos, lookOf(root), list, chosenId, now, chosenSince)
		if pick ~= chosenId then
			chosenId = pick
			chosenSince = now
		end
		if pick and byId[pick] then
			return byId[pick]
		end
	end
	if ZoneRules.distXZ(pos, WorldLayout.plaza("shop")) <= SHOP_RADIUS then
		local t = make("shop", 0, WorldLayout.plaza("shop"))
		t.primary = "shop"
		return t
	end
	if
		ZoneRules.distXZ(pos, WorldLayout.plaza("kiosk")) <= KIOSK_RADIUS
		and Util.safe("WorldV2.kioskOpen", false, WorldV2.kioskOpen)
	then
		local t = make("kiosk", 0, WorldLayout.plaza("kiosk"))
		t.primary = "workshop"
		return t
	end
	return nil
end

local function setCurrent(t: Target?)
	local key = keyOf(t)
	if t and current and key == currentKey then
		current.position = t.position -- même cible : la plaque suit sans nouveau signal
		return
	end
	if key == currentKey then
		return
	end
	current = t
	currentKey = key
	local tt = t
	if tt and (tt.kind == "squishy" or tt.kind == "fence") then
		Util.safe("RanchRenderer.highlightTarget", nil, RanchRenderer.highlightTarget, tt.slot, tt.uid)
	else
		Util.safe("RanchRenderer.highlightTarget", nil, RanchRenderer.highlightTarget, nil, nil)
	end
	PromptController.Changed:Fire(t)
end

local function updateLeap(now: number)
	local root = Util.localRoot()
	if root == nil or windowOpen() then
		leapId = nil
		return
	end
	local ctx = catchCtx()
	local candidates: { LeapRules.AimCandidate } = {}
	for id, s in WorldStateController.creatures() do
		if Catchable.check(s, now, ctx) then
			table.insert(candidates, {
				id = id,
				posAt = function(t: number): Vector3
					return WorldStateController.creaturePos(id, t) or Vector3.new(0, -1e6, 0)
				end,
			})
		end
	end
	if #candidates == 0 then
		leapId = nil
		return
	end
	local ok, id = pcall(LeapRules.aim, root.Position, stickOf(root), candidates, now, leapId)
	leapId = if ok then id else nil
end

-- Une image (exposé aux specs ; appelé par Heartbeat)
function PromptController._step(dt: number)
	animT += Util.num(dt, 0, 0, 1)
	local now = Clock.now()
	updateLeap(now)
	if windowOpen() then
		setCurrent(nil)
		return
	end
	if locked then
		if animT - lockedAt > LOCK_TIMEOUT then
			locked = false -- sortie garantie du verrou (fin de maintien jamais reçue)
		else
			return
		end
	end
	if afterPressAt and animT >= afterPressAt then
		afterPressAt = nil
		local root = Util.localRoot()
		local slot = WorldStateController.mySlot()
		if root and slot > 0 and afterPressId then
			-- recharges locales passées oubliées (sinon une entrée par squishy pressé de la session)
			for uid, untilT in pressed do
				if untilT <= now then
					pressed[uid] = nil
				end
			end
			pressed[afterPressId] = now + PRESSED_HOLD
			local list, byId = squishyCandidates(slot, root.Position, now)
			local nextId = TargetRules.afterPress(root.Position, lookOf(root), list, afterPressId)
			if nextId and byId[nextId] then
				chosenId = nextId
				chosenSince = now
				clickId = nil
			end
		end
		afterPressId = nil
	end
	setCurrent(compute(now))
end

-- Création des états ; aucun yield long
function PromptController.Init()
	current = nil
	currentKey = ""
end

-- Connexions et boucles
function PromptController.Start()
	if started then
		return
	end
	started = true
	-- fenêtres ouvertes : signaux de FocusGuard (module plus tardif : écouté, jamais appelé)
	local ok, FocusGuard = pcall(function()
		return require(Client.UI.FocusGuard) :: any
	end)
	if ok and type(FocusGuard) == "table" and FocusGuard.WindowOpened and FocusGuard.WindowClosed then
		table.insert(
			connections,
			FocusGuard.WindowOpened:Connect(function(name: string)
				if type(name) == "string" then
					windows[name] = true
				end
				setCurrent(nil)
			end)
		)
		table.insert(
			connections,
			FocusGuard.WindowClosed:Connect(function(name: string)
				if type(name) == "string" then
					windows[name] = nil
				end
			end)
		)
		-- fenêtres ouvertes avant ce Start (pendant l'Init d'un module plus tardif) : lues une fois
		-- ici, après tous les Init (note INT-CWR-5)
		local okNames, names = pcall(function()
			return FocusGuard.names()
		end)
		if okNames and type(names) == "table" then
			for _, name in names do
				if type(name) == "string" then
					windows[name] = true
				end
			end
		end
	end
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			Util.guard("PromptController.step", PromptController._step, dt)
		end)
	)
end

-- =============================================================================================
-- API
-- =============================================================================================

-- Cible de l'action principale
function PromptController.current(): Target?
	if windowOpen() then
		return nil
	end
	return current
end

-- L1 (−1) / R1 (+1) : candidats du ranch ou de la clôture, de gauche à droite (jamais en ville)
function PromptController.cycle(dir: number)
	if locked or windowOpen() then
		return
	end
	local root = Util.localRoot()
	if root == nil then
		return
	end
	local now = Clock.now()
	local slot = WorldStateController.mySlot()
	local list, byId
	if slot > 0 and WorldLayout.inRanch(slot, root.Position) then
		list, byId = squishyCandidates(slot, root.Position, now)
	else
		list, byId = fenceCandidates(root.Position, slot)
	end
	if #list == 0 then
		return
	end
	local cur = if current and (current.kind == "squishy" or current.kind == "fence")
		then (if current.kind == "fence" then current.slot .. ":" .. current.uid else current.uid)
		else nil
	local pick =
		TargetRules.cycle(root.Position, lookOf(root), list, cur, if Util.finite(dir) then dir else 1)
	if pick and byId[pick] then
		-- un choix manuel tient comme un clic (ClickTarget.Hold)
		clickId = pick
		clickUntil = now + CLICK_HOLD
		chosenId = pick
		chosenSince = now
		setCurrent(byId[pick])
	end
end

-- Clic souris : fixe la cible 4 s si un candidat est désigné (projection à l'écran)
function PromptController.clickAt(screen: Vector2): boolean
	if typeof(screen) ~= "Vector2" or windowOpen() or locked then
		return false
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local projected = Util.safe("RanchRenderer.projected", {}, RanchRenderer.projected, camera)
	local scale = 1
	local okScale, s = pcall(function()
		return (require(Client.UI.Root) :: any).scale()
	end)
	if okScale and Util.finite(s) then
		scale = s
	end
	local pick = TargetRules.screenPick(screen, projected, scale)
	if pick == nil then
		return false
	end
	local root = Util.localRoot()
	local slot = WorldStateController.mySlot()
	if root == nil or slot == 0 then
		return false
	end
	local _, byId = squishyCandidates(slot, root.Position, Clock.now())
	if byId[pick] == nil then
		return false
	end
	clickId = pick
	clickUntil = Clock.now() + CLICK_HOLD
	chosenId = pick
	chosenSince = Clock.now()
	setCurrent(byId[pick])
	return true
end

-- Verrouille la cible pendant un maintien (boop, bol)
function PromptController.lock(kind: string)
	local _ = kind
	if current == nil then
		return
	end
	locked = true
	lockedAt = animT
end

-- Fin du maintien
function PromptController.unlock()
	locked = false
end

-- Après une pression : passe au prochain prêt en 0,15 s
function PromptController.afterPress()
	local t = current
	if t == nil or t.kind ~= "squishy" then
		return
	end
	afterPressId = t.uid
	afterPressAt = animT + RETARGET
end

-- Créature visée par le prochain bond
function PromptController.leapTarget(): number?
	return leapId
end

-- Verrou en cours (specs)
function PromptController.locked(): boolean
	return locked
end

-- Squishies comptés en recharge locale (specs : aucune fuite)
function PromptController._pressedCount(): number
	local n = 0
	for _ in pressed do
		n += 1
	end
	return n
end

-- Coupe les connexions (fin de session, specs)
function PromptController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return PromptController
