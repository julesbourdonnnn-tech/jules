--!strict
-- Anime côté client les objets du monde tagués par le serveur (un seul RenderStepped) :
--   "Spin"  : rotation continue   (attributs : speed rad/s, axis "Y"|"X"|"Z")
--   "Float" : flottement vertical (attributs : amplitude studs, period s, phase rad)
--   "Pulse" : pulsation de taille (attributs : amount 0-1, period s)
-- L'animation part du CFrame/Size d'origine : aucune dérive, et compatible StreamingEnabled
-- (les objets qui sortent du rayon de streaming sont retirés de la liste).
-- Budgets (GDD §12.8, téléphone Android modeste ; ≈ 175 Float + 9 Spin, surtout des îlots lointains) :
--   * attributs lus une seule fois au suivi, relus seulement sur AttributeChanged : aucun
--     GetAttribute par image ; temps de Shared/Util/Clock (même flottement chez tous les joueurs)
--   * pièces déplacées par un seul workspace:BulkMoveTo par image (listes réutilisées, pas de
--     CFrame écrit pièce par pièce)
--   * pièces à plus de FAR_DISTANCE studs de la caméra mises à jour à FAR_HZ seulement, réparties
--     sur les images
--   * Mouvement réduit : décor immobile, rendu à sa position et à sa taille d'origine ;
--     Graphismes légers : pièces lointaines figées (les proches restent animées)
-- GDD : §11.2 et §11.4 (Balise, décor par zone), §9.1 (réglages), §12.8 (budgets).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)

local WorldFXController = {}

-- Constantes ------------------------------------------------------------------------------------

local TAU = 2 * math.pi
local FAR_DISTANCE = 200 -- studs de la caméra : au-delà, animation à fréquence réduite
local FAR_HZ = 15
local FAR_INTERVAL = 1 / FAR_HZ
local FAR_SLICES = 4 -- décalages des pièces lointaines (mises à jour réparties sur les images)
local DEFAULT_SPEED = 1
local DEFAULT_AMPLITUDE = 0.5
local DEFAULT_FLOAT_PERIOD = 3
local DEFAULT_PULSE_PERIOD = 1.5
local DEFAULT_AMOUNT = 0.08

-- État --------------------------------------------------------------------------------------------

type Entry = {
	part: BasePart,
	origin: CFrame,
	size: Vector3,
	spin: boolean,
	float: boolean,
	pulse: boolean,
	speed: number,
	axis: string,
	amplitude: number,
	period: number, -- Float
	phase: number,
	amount: number,
	pulsePeriod: number, -- Pulse (même attribut « period », autre valeur par défaut)
	due: number, -- prochaine mise à jour (0 : chaque image)
	index: number, -- place dans `list`
	moved: boolean, -- CFrame écarté de l'origine
	resized: boolean, -- Size écartée de l'origine
	conn: RBXScriptConnection?,
}

local records: { [BasePart]: Entry } = {}
local list: { Entry } = {}
-- Pièces suivies par étiquette (exposé pour les tests)
local entries: { [string]: { [BasePart]: Entry } } = {
	Spin = {},
	Float = {},
	Pulse = {},
}
local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}
local bulkLength = 0
local reducedMotion = false
local lowGraphics = false
local rested = false -- Mouvement réduit : décor déjà rendu à l'origine
local started = false

-- Attributs ---------------------------------------------------------------------------------------

local function finiteAttr(part: BasePart, name: string, default: number): number
	local v = part:GetAttribute(name)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function positiveAttr(part: BasePart, name: string, default: number): number
	local v = finiteAttr(part, name, default)
	return if v > 0 then v else default
end

-- Lu au suivi puis sur AttributeChanged seulement (jamais par image)
local function readAttributes(e: Entry)
	local part = e.part
	e.speed = finiteAttr(part, "speed", DEFAULT_SPEED)
	local axis = part:GetAttribute("axis")
	e.axis = if axis == "X" or axis == "Z" then axis else "Y"
	e.amplitude = finiteAttr(part, "amplitude", DEFAULT_AMPLITUDE)
	e.period = positiveAttr(part, "period", DEFAULT_FLOAT_PERIOD)
	e.phase = finiteAttr(part, "phase", 0)
	e.amount = finiteAttr(part, "amount", DEFAULT_AMOUNT)
	e.pulsePeriod = positiveAttr(part, "period", DEFAULT_PULSE_PERIOD)
	e.due = 0
end

-- Suivi -------------------------------------------------------------------------------------------

local function track(tag: string, inst: Instance)
	local set = entries[tag]
	if set == nil or not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	local e = records[part]
	if e == nil then
		local created: Entry = {
			part = part,
			origin = part.CFrame,
			size = part.Size,
			spin = false,
			float = false,
			pulse = false,
			speed = DEFAULT_SPEED,
			axis = "Y",
			amplitude = DEFAULT_AMPLITUDE,
			period = DEFAULT_FLOAT_PERIOD,
			phase = 0,
			amount = DEFAULT_AMOUNT,
			pulsePeriod = DEFAULT_PULSE_PERIOD,
			due = 0,
			index = #list + 1,
			moved = false,
			resized = false,
			conn = nil,
		}
		records[part] = created
		list[created.index] = created
		created.conn = part.AttributeChanged:Connect(function()
			if records[part] == created then
				readAttributes(created)
			end
		end)
		e = created
	end
	local entry = e :: Entry
	set[part] = entry
	if tag == "Spin" then
		entry.spin = true
	elseif tag == "Float" then
		entry.float = true
	else
		entry.pulse = true
	end
	readAttributes(entry)
end

-- Retire une pièce de toutes les listes (échange avec la dernière de `list`)
local function forget(e: Entry)
	local part = e.part
	if records[part] ~= e then
		return
	end
	records[part] = nil
	for _, set in entries do
		set[part] = nil
	end
	local conn = e.conn
	if conn then
		conn:Disconnect()
		e.conn = nil
	end
	local last = list[#list]
	list[e.index] = last
	last.index = e.index
	list[#list] = nil
end

local function untrack(tag: string, inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	local e = records[part]
	if e == nil then
		return
	end
	local set = entries[tag]
	if set then
		set[part] = nil
	end
	if tag == "Spin" then
		e.spin = false
	elseif tag == "Float" then
		e.float = false
	elseif tag == "Pulse" then
		e.pulse = false
	end
	if not (e.spin or e.float or e.pulse) then
		forget(e)
	end
end

-- Image -------------------------------------------------------------------------------------------

local function rotation(axis: string, angle: number): CFrame
	if axis == "X" then
		return CFrame.Angles(angle, 0, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(0, angle, 0)
end

-- Angles réduits à [0, 2π[ en double précision : Clock.now() ≈ 1,8 × 10⁹ s ne passe pas tel quel
-- dans un CFrame (flottants 32 bits)
local function poseOf(e: Entry, now: number): CFrame
	local cf = e.origin
	if e.float then
		local lift = math.sin((now % e.period) / e.period * TAU + e.phase) * e.amplitude
		cf += Vector3.new(0, lift, 0)
	end
	if e.spin then
		cf *= rotation(e.axis, (now * e.speed) % TAU)
	end
	return cf
end

-- Envoie les `n` premières pièces des listes en un seul BulkMoveTo (fin des listes effacée)
local function flush(n: number)
	for i = n + 1, bulkLength do
		bulkParts[i] = nil
		bulkCFrames[i] = nil
	end
	bulkLength = n
	if n > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Mouvement réduit : tout le décor rendu à sa position et à sa taille d'origine, une seule fois
local function rest()
	local n = 0
	for i = #list, 1, -1 do
		local e = list[i]
		if e.part.Parent == nil then
			forget(e)
			continue
		end
		if e.moved then
			e.moved = false
			n += 1
			bulkParts[n] = e.part
			bulkCFrames[n] = e.origin
		end
		if e.resized then
			e.resized = false
			e.part.Size = e.size
		end
	end
	flush(n)
	rested = true
end

local function step(_dt: number?)
	if reducedMotion then
		if not rested then
			rest()
		end
		return
	end
	local now = Clock.now()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local n = 0
	for i = #list, 1, -1 do
		local e = list[i]
		if now < e.due then
			continue
		end
		local part = e.part
		if part.Parent == nil then
			forget(e)
			continue
		end
		if (e.origin.Position - eye).Magnitude > FAR_DISTANCE then
			-- lointaine : mise à jour à FAR_HZ, décalée selon la pièce (réparties sur les images)
			local nextDue = e.due + FAR_INTERVAL
			if nextDue <= now then
				nextDue = now + FAR_INTERVAL * (1 + e.index % FAR_SLICES) / FAR_SLICES
			end
			e.due = nextDue
			if lowGraphics then
				continue -- Graphismes légers : figée (distance revue à FAR_HZ)
			end
		else
			e.due = 0
		end
		if e.spin or e.float then
			n += 1
			bulkParts[n] = part
			bulkCFrames[n] = poseOf(e, now)
			e.moved = true
		end
		if e.pulse then
			local k = 1 + math.sin((now % e.pulsePeriod) / e.pulsePeriod * TAU) * e.amount
			part.Size = e.size * k
			e.resized = true
		end
	end
	flush(n)
end

local function refreshPrefs()
	local reduced = Prefs.reducedMotion()
	if reduced ~= reducedMotion then
		reducedMotion = reduced
		rested = false
		for _, e in list do
			e.due = 0 -- reprise immédiate à la sortie du Mouvement réduit
		end
	end
	lowGraphics = Prefs.lowGraphics()
end

-- Cycle de vie ------------------------------------------------------------------------------------

function WorldFXController.Start()
	if started then
		return
	end
	started = true
	refreshPrefs()
	Prefs.Changed:Connect(function(key: string)
		if key == "reducedMotion" or key == "lowGraphics" then
			refreshPrefs()
		end
	end)
	for tag in entries do
		for _, inst in CollectionService:GetTagged(tag) do
			track(tag, inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			track(tag, inst)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			untrack(tag, inst)
		end)
	end
	RunService.RenderStepped:Connect(step)
end

-- Exposé pour les tests
WorldFXController._step = step
WorldFXController._entries = entries

return WorldFXController
