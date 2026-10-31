--!strict
-- Anime côté client les objets du monde tagués par le serveur (un seul RenderStepped) :
--   "Spin"  : rotation continue   (attributs : speed rad/s, axis "Y"|"X"|"Z")
--   "Float" : flottement vertical (attributs : amplitude studs, period s, phase rad)
--   "Pulse" : pulsation de taille (attributs : amount 0-1, period s)
-- L'animation part du CFrame/Size d'origine : aucune dérive, et compatible StreamingEnabled
-- (les objets qui sortent du rayon de streaming sont retirés de la liste).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

type Entry = { part: BasePart, origin: CFrame, size: Vector3 }

local WorldFXController = {}

local entries: { [string]: { [BasePart]: Entry } } = {
	Spin = {},
	Float = {},
	Pulse = {},
}

local function track(tag: string, inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	entries[tag][inst] = { part = inst, origin = inst.CFrame, size = inst.Size }
end

local function untrack(tag: string, inst: Instance)
	if inst:IsA("BasePart") then
		entries[tag][inst] = nil
	end
end

local function attr(part: BasePart, name: string, default: number): number
	local v = part:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function step()
	local t = os.clock()
	for part, e in entries.Spin do
		if part.Parent == nil then
			entries.Spin[part] = nil
			continue
		end
		local angle = t * attr(part, "speed", 1)
		local axis = part:GetAttribute("axis")
		local rot = if axis == "X"
			then CFrame.Angles(angle, 0, 0)
			elseif axis == "Z" then CFrame.Angles(0, 0, angle)
			else CFrame.Angles(0, angle, 0)
		local float = entries.Float[part]
		local lift = if float
			then math.sin(t * (2 * math.pi) / attr(part, "period", 3) + attr(part, "phase", 0)) * attr(
				part,
				"amplitude",
				0.5
			)
			else 0
		part.CFrame = (e.origin + Vector3.new(0, lift, 0)) * rot
	end
	for part, e in entries.Float do
		if part.Parent == nil then
			entries.Float[part] = nil
			continue
		end
		if entries.Spin[part] then
			continue -- déjà géré avec la rotation
		end
		local lift = math.sin(t * (2 * math.pi) / attr(part, "period", 3) + attr(part, "phase", 0))
			* attr(part, "amplitude", 0.5)
		part.CFrame = e.origin + Vector3.new(0, lift, 0)
	end
	for part, e in entries.Pulse do
		if part.Parent == nil then
			entries.Pulse[part] = nil
			continue
		end
		local k = 1 + math.sin(t * (2 * math.pi) / attr(part, "period", 1.5)) * attr(part, "amount", 0.08)
		part.Size = e.size * k
	end
end

function WorldFXController.Start()
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
