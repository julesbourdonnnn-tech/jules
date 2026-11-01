--!strict
-- Construction déclarative d'instances :
--   Create("TextButton", {
--       Name = "Play", Size = UDim2.fromOffset(200, 64), Parent = frame,
--       [Create.Event "Activated"] = function() ... end,
--   }, {
--       Create("UICorner", { CornerRadius = UDim.new(0, 12) }),
--   })
-- `Parent` est toujours appliqué en dernier (évite les réplications/rendus inutiles).

local Create = {}

local EVENT_KEY = {}

type EventKey = { name: string }

local eventKeys: { [string]: EventKey } = {}

function Create.Event(name: string): any
	local key = eventKeys[name]
	if not key then
		key = setmetatable({ name = name }, EVENT_KEY) :: any
		eventKeys[name] = key
	end
	return key
end

local function build(className: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif type(key) == "table" and getmetatable(key :: any) == EVENT_KEY then
				(inst :: any)[(key :: any).name]:Connect(value)
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

setmetatable(Create, {
	__call = function(_, className: string, props: { [any]: any }?, children: { Instance }?)
		return build(className, props, children)
	end,
})

return (Create :: any) :: typeof(Create) & ((string, { [any]: any }?, { Instance }?) -> any)
