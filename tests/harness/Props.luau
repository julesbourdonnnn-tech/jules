--!nocheck
-- Valeur d'une propriété telle que le VRAI moteur Roblox l'afficherait (outils hors jeu :
-- tools/screens, tests/harness/TextFit).
--
-- Les instances simulées (MockInstance) partent de valeurs par défaut pratiques pour les tests
-- (fond blanc, TextSize 14, Text = nom de classe…) qui diffèrent de celles du moteur. Une propriété
-- jamais écrite par le code du jeu prend donc ici la valeur par défaut de la base de réflexion de
-- Roblox livrée avec Lune (fond gris 163, 162, 165, bordure 1 px, TextSize 8, police Legacy Arial,
-- Text « Label » / « Button »…), celle qu'un joueur verrait vraiment.
--
--   Props.get(obj, "BackgroundColor3")

local roblox = require("@lune/roblox")
local MockInstance = require("./MockInstance")

local Props = {}

local cache = {} -- [className] = { [prop] = valeur | NONE }
local NONE = {}

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
Props.engineDefault = engineDefault

-- Valeur affichée par le moteur : celle écrite par le code, sinon le défaut du moteur (à défaut,
-- celle du harnais)
function Props.get(obj, key: string)
	if MockInstance.wasWritten(obj, key) then
		return obj[key]
	end
	-- police posée par l'ancienne propriété Font (Enum.Font) : FontFace en découle, comme dans Roblox
	if key == "FontFace" and MockInstance.wasWritten(obj, "Font") then
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

function Props.written(obj, key: string): boolean
	return MockInstance.wasWritten(obj, key)
end

return Props
