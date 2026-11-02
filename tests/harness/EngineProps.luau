--!nocheck
-- Valeur d'une propriété telle que le VRAI moteur Roblox l'afficherait (outils hors jeu :
-- tools/screens, tests/harness/TextFit). Repris de l'outil d'écrans de Comet Conga.
--
-- Les instances simulées (MockInstance) partent de valeurs par défaut pratiques pour les tests
-- (fond blanc, TextSize 14, Text = nom de classe…) qui diffèrent de celles du moteur. Une propriété
-- jamais écrite par le code du jeu prend donc ici la valeur par défaut de la base de réflexion de
-- Roblox livrée avec Lune (fond gris 163, 162, 165, bordure 1 px, police Legacy Arial, Text
-- « Label » / « Button »…), celle qu'un joueur verrait vraiment.
--
--   EngineProps.install()                 -- suivi des écritures (idempotent, avant Harness.new)
--   EngineProps.uninstall()               -- retire le suivi (fin d'une spec d'écrans)
--   EngineProps.get(obj, "BackgroundColor3")
--   EngineProps.written(obj, "Text")      -- la propriété a-t-elle été écrite par le code ?
--
-- Suivi des écritures : MockInstance ne garde pas la trace des propriétés écrites ; install()
-- enveloppe son __newindex (et Clone, qui recopie les propriétés) SANS changer leur comportement :
-- l'écriture a lieu exactement comme avant, puis la clé est notée dans l'état de l'instance
-- (champ `written`). Rien n'est modifié dans tests/harness/MockInstance.luau.

local roblox = require("@lune/roblox")
local MockInstance = require("./MockInstance")

local EngineProps = {}

local cache = {} -- [className] = { [prop] = valeur | NONE }
local NONE = {}
local installed = false
local restore = nil -- () -> () : remet __newindex et Clone d'origine

function EngineProps.install()
	if installed then
		return
	end
	installed = true
	local probe = MockInstance.new("Folder")
	local mt = getmetatable(probe)
	local setter = mt.__newindex
	mt.__newindex = function(self, key, value)
		setter(self, key, value)
		local st = MockInstance.state(self)
		if st ~= nil then
			local w = st.written
			if w == nil then
				w = {}
				st.written = w
			end
			w[key] = true
		end
	end
	local Methods = MockInstance.Methods
	local clone = Methods.Clone
	Methods.Clone = function(self)
		local copy = clone(self)
		local src = MockInstance.state(self)
		local dst = MockInstance.state(copy)
		if src ~= nil and dst ~= nil and src.written ~= nil then
			dst.written = table.clone(src.written)
		end
		return copy
	end
	restore = function()
		mt.__newindex = setter
		Methods.Clone = clone
	end
	probe:Destroy()
end

-- Retire le suivi (fin d'une spec d'écrans : les specs suivantes retrouvent MockInstance tel quel)
function EngineProps.uninstall()
	if not installed then
		return
	end
	installed = false
	if restore then
		restore()
		restore = nil
	end
end

function EngineProps.installed(): boolean
	return installed
end

function EngineProps.written(obj, key: string): boolean
	local st = MockInstance.state(obj)
	return st ~= nil and st.written ~= nil and st.written[key] == true
end

local function engineDefault(className: string, key: string)
	local byClass = cache[className]
	if byClass == nil then
		byClass = {}
		cache[className] = byClass
	end
	local v = byClass[key]
	if v == nil then
		local ok, inst = pcall(roblox.Instance.new, className)
		if ok then
			local ok2, value = pcall(function()
				return inst[key]
			end)
			v = if ok2 and value ~= nil then value else NONE
		else
			v = NONE
		end
		byClass[key] = v
	end
	if v == NONE then
		return nil
	end
	return v
end
EngineProps.engineDefault = engineDefault

-- Valeur affichée par le moteur : celle écrite par le code, sinon le défaut du moteur (à défaut,
-- celle du harnais). Sans suivi installé, la valeur du harnais.
function EngineProps.get(obj, key: string)
	if not installed or EngineProps.written(obj, key) then
		return obj[key]
	end
	-- police posée par l'ancienne propriété Font (Enum.Font) : FontFace en découle, comme dans Roblox
	if key == "FontFace" and EngineProps.written(obj, "Font") then
		local ok, face = pcall(roblox.Font.fromEnum, obj.Font)
		if ok then
			return face
		end
	end
	local d = engineDefault(obj.ClassName, key)
	if d ~= nil then
		return d
	end
	return obj[key]
end

return EngineProps
