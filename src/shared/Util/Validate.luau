--!strict
-- Validation des valeurs venant du client (jamais fiables).

local Validate = {}

function Validate.finiteNumber(x: unknown): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Validate.integer(x: unknown, min: number?, max: number?): boolean
	if not Validate.finiteNumber(x) then
		return false
	end
	local n = x :: number
	if n % 1 ~= 0 then
		return false
	end
	if min and n < min then
		return false
	end
	if max and n > max then
		return false
	end
	return true
end

function Validate.numberInRange(x: unknown, min: number, max: number): boolean
	return Validate.finiteNumber(x) and (x :: number) >= min and (x :: number) <= max
end

function Validate.string(x: unknown, maxLength: number?): boolean
	return type(x) == "string" and #x > 0 and #x <= (maxLength or 64)
end

-- La valeur est-elle une clé existante de `set` ? (ex. Config.Items)
function Validate.key(x: unknown, set: { [string]: any }, maxLength: number?): boolean
	return Validate.string(x, maxLength) and set[x :: string] ~= nil
end

function Validate.boolean(x: unknown): boolean
	return type(x) == "boolean"
end

function Validate.vector3(x: unknown, maxMagnitude: number?): boolean
	if typeof(x) ~= "Vector3" then
		return false
	end
	local v = x :: Vector3
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		return false
	end
	return v.Magnitude <= (maxMagnitude or 1e6)
end

function Validate.instanceOf(x: unknown, className: string): boolean
	return typeof(x) == "Instance" and (x :: Instance):IsA(className)
end

return Validate
