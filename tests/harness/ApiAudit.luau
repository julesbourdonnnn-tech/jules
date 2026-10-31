--!nocheck
-- Audit de l'API Roblox pendant un test d'intégration : le harnais accepte n'importe quel nom de
-- propriété (une faute de frappe passe sous Lune et casse dans Roblox : « X is not a valid member
-- of Part »). Pendant l'audit, chaque écriture de propriété, chaque lecture d'un membre inconnu
-- du harnais et chaque classe créée sont confrontées à la base de réflexion de Roblox livrée avec
-- Lune (classes, propriétés, types, droits d'écriture).
--
--   ApiAudit.start()  … partie complète …  local issues = ApiAudit.stop()

local roblox = require("@lune/roblox")
local MockInstance = require("./MockInstance")

local ApiAudit = {}

local db = roblox.getReflectionDatabase()
local MT = getmetatable(MockInstance.new("Folder"))

-- Classes propres au harnais (aucune équivalence Roblox à vérifier)
local HARNESS_CLASSES = {
	DataModel = true,
}

-- Méthodes et rappels (callbacks) Roblox absents de la base de réflexion (elle ne décrit que les
-- propriétés) que le jeu appelle sous pcall ou assigne et que le harnais ne simule pas
local CALLBACKS = {
	["MarketplaceService.ProcessReceipt"] = true,
	["RemoteFunction.OnServerInvoke"] = true,
	["RemoteFunction.OnClientInvoke"] = true,
	["BindableFunction.OnInvoke"] = true,
}
local METHODS = {
	["Camera.WorldToViewportPoint"] = true,
	["Camera.WorldToScreenPoint"] = true,
	["Camera.ViewportPointToRay"] = true,
	["HapticService.IsVibrationSupported"] = true,
	["HapticService.IsMotorSupported"] = true,
	["HapticService.SetMotor"] = true,
}
local IGNORED_READS = {}

local running = false
local origIndex, origNewindex, origNew = nil, nil, nil
local writes = {} -- "Class.prop" → { class, prop, types = {}, where }
local reads = {} -- "Class.member" → { class, member, where }
local classes = {} -- className → where

local propCache = {}
local function findProp(className: string, name: string)
	local key = className .. "." .. name
	local cached = propCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local c = db:GetClass(className)
	local found = false
	while c do
		local p = c.Properties[name]
		if p then
			found = p
			break
		end
		c = if c.Superclass then db:GetClass(c.Superclass) else nil
	end
	propCache[key] = found
	return found or nil
end

local function short(source)
	local s = string.gsub(tostring(source), "^.*/src/", "src/")
	return (string.gsub(s, '"%]$', ""))
end

-- emplacement de l'appelant (et de son propre appelant : aides comme UI/Create)
local function caller(level)
	local source, line = debug.info(level + 1, "sl")
	local source2, line2 = debug.info(level + 2, "sl")
	if source2 and string.find(source2, "/src/", 1, true) then
		return `{short(source)}:{line} ← {short(source2)}:{line2}`
	end
	return `{short(source)}:{line}`
end

local function fromGame(level)
	local source = debug.info(level + 1, "s")
	return type(source) == "string" and string.find(source, "/src/", 1, true) ~= nil
end

-- Écriture faite par le Play du TweenService simulé (objectifs d'un tween créé par le jeu)
local function isTweenPlay(level)
	local source, name = debug.info(level + 1, "sn")
	return type(source) == "string"
		and string.find(source, "harness/Services", 1, true) ~= nil
		and name == "Play"
end

-- Types que TweenService sait interpoler
local TWEENABLE = {
	number = true,
	boolean = true,
	CFrame = true,
	Rect = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector3 = true,
	EnumItem = true,
}

local function valueType(value)
	if MockInstance.is(value) then
		return "Instance"
	end
	return typeof(value)
end

-- Le type d'une valeur assignée convient-il au type de la propriété ?
local function compatible(datatype: string, value): boolean
	local t = valueType(value)
	if value == nil then
		return datatype == "Ref" or datatype == "PhysicalProperties" or datatype == "OptionalCFrame"
	end
	if datatype == "Float32" or datatype == "Float64" or datatype == "Int32" or datatype == "Int64" then
		return t == "number" and value == value
	elseif datatype == "Bool" then
		return t == "boolean"
	elseif datatype == "String" or datatype == "ContentId" or datatype == "BinaryString" then
		return t == "string"
	elseif datatype == "Content" then
		return t == "string" or t == "Content"
	elseif datatype == "Ref" then
		return t == "Instance"
	elseif datatype == "OptionalCFrame" then
		return t == "CFrame"
	elseif string.sub(datatype, 1, 5) == "Enum." then
		if t == "EnumItem" then
			return string.find(tostring(value), datatype .. ".", 1, true) == 1
		end
		return t == "number" or t == "string"
	end
	return t == datatype
end

function ApiAudit.start()
	if running then
		return
	end
	running = true
	table.clear(writes)
	table.clear(reads)
	table.clear(classes)
	origIndex = MT.__index
	origNewindex = MT.__newindex
	origNew = MockInstance.new
	MT.__newindex = function(self, key, value)
		local tween = type(key) == "string" and isTweenPlay(2)
		if type(key) == "string" and (tween or fromGame(2)) then
			local className = MockInstance.state(self).ClassName
			local id = className .. "." .. key
			local w = writes[id]
			if w == nil then
				w = { class = className, prop = key, types = {}, values = {}, where = caller(2) }
				writes[id] = w
			end
			local t = valueType(value)
			if tween then
				w.tween = true
			end
			if not w.types[t] then
				w.types[t] = true
				table.insert(w.values, { value = value, where = if tween then "tween" else caller(2) })
			end
		end
		return origNewindex(self, key, value)
	end
	MT.__index = function(self, key)
		local v = origIndex(self, key)
		if v == nil and type(key) == "string" and fromGame(2) then
			local className = MockInstance.state(self).ClassName
			local id = className .. "." .. key
			if reads[id] == nil and not IGNORED_READS[key] then
				reads[id] = { class = className, member = key, where = caller(2) }
			end
		end
		return v
	end
	MockInstance.new = function(className, parent)
		if classes[className] == nil then
			classes[className] = caller(2)
		end
		return origNew(className, parent)
	end
end

-- Arrête l'audit ; retourne la liste des écarts (chaînes lisibles)
function ApiAudit.stop(): { string }
	if not running then
		return {}
	end
	running = false
	MT.__index = origIndex
	MT.__newindex = origNewindex
	MockInstance.new = origNew
	local issues = {}
	for className, where in classes do
		if not HARNESS_CLASSES[className] and db:GetClass(className) == nil then
			table.insert(issues, `classe inconnue de Roblox : {className} ({where})`)
		end
	end
	for id, w in writes do
		local p = findProp(w.class, w.prop)
		if CALLBACKS[id] then
			for _, sample in w.values do
				if type(sample.value) ~= "function" and sample.value ~= nil then
					table.insert(issues, `rappel {id} : fonction attendue ({sample.where})`)
				end
			end
		elseif p == nil then
			table.insert(issues, `propriété inexistante : {w.class}.{w.prop} ({w.where})`)
		elseif p.Scriptability ~= "ReadWrite" and p.Scriptability ~= "Custom" then
			table.insert(issues, `propriété non modifiable par script : {w.class}.{w.prop} ({w.where})`)
		else
			for _, sample in w.values do
				if w.tween and not TWEENABLE[valueType(sample.value)] then
					table.insert(
						issues,
						`tween d'un type non interpolable : {w.class}.{w.prop} ({valueType(sample.value)})`
					)
				end
				if not compatible(p.Datatype, sample.value) then
					table.insert(
						issues,
						`type invalide : {w.class}.{w.prop} attend {p.Datatype}, reçu {valueType(
							sample.value
						)} ({sample.where})`
					)
				end
			end
		end
	end
	for id, r in reads do
		if findProp(r.class, r.member) == nil and not METHODS[id] and not CALLBACKS[id] then
			table.insert(issues, `membre inexistant lu : {r.class}.{r.member} ({r.where})`)
		end
	end
	table.sort(issues)
	return issues
end

-- Statistiques (pour les journaux de test)
function ApiAudit.counts()
	local nw, nr, nc = 0, 0, 0
	for _ in writes do
		nw += 1
	end
	for _ in reads do
		nr += 1
	end
	for _ in classes do
		nc += 1
	end
	return nw, nr, nc
end

return ApiAudit
