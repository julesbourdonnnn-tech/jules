--!strict
-- Personality (lot B5 ; GDD §5.6 « Des squishies qui ont du caractère » ; docs/04 §27.7 ; plan B5 D3,
-- D6) : personnalités des squishies, entièrement côté client, derrière l'interrupteur Personalities
-- (World/Flags : le client ne lit jamais Config/Features). Étape 1 du lot (socle) : les crochets du
-- rendu et la route des visages ; les saynètes, les réactions et les tours appris viennent à l'étape 2.
--
--   Personality.active()                    -- vrai tant que Personalities est ouvert sur le serveur
--   Personality.Changed                     -- fn() quand active() change (déjà à jour quand il part)
--   Personality.pose(d, h, rec, where, base, cf, now) → CFrame
--                                           -- appelé par RanchRenderer.stepSquishy pour chaque squishy
--                                           -- dessiné et animé à cette image, APRÈS le calcul de sa
--                                           -- pose de repos (d.pos déjà écrit : le ciblage lit toujours
--                                           -- la place de repos) ; rend la pose à dessiner. Étape 1 :
--                                           -- la pose de repos telle quelle
--   Personality.forget(slot, uid)           -- le modèle de ce squishy est rendu à la réserve
--   Personality.setFace(slot, uid, face)    -- visage (Config/Visuals.Faces) du squishy dessiné ; vrai
--                                           -- s'il est posé ; faux et rien si l'interrupteur est coupé,
--                                           -- si le visage est inconnu ou si le squishy n'est pas dessiné
--   Personality.faceOf(slot, uid)           -- visage posé par ce module (« happy » sinon)
--
-- Règles :
--  * interrupteur coupé : RanchRenderer n'appelle ni pose ni forget (un booléen local, relu sur
--    Changed) ; setFace ne fait rien ; aucune instance, aucune connexion par image ;
--  * coupure en direct : chaque visage posé revient à « happy » avant que Changed parte ;
--  * un visage n'est qu'une écriture de Render/SquishyBuilder.setFace (tailles des yeux et des
--    reflets une fois, bouche par CFrame) ; le modèle rendu à la réserve repart avec « happy » ;
--  * RanchRenderer charge ce module (il est 10e dans l'ordre du client) : ce module ne charge aucun
--    module d'écran et ne requiert RanchRenderer qu'à la demande, sous pcall (handleOf).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)

local Client = script.Parent.Parent
local Flags = require(Client.World.Flags)

local Personality = {}

Personality.Changed = Signal.new() :: Signal.Signal<>

local FLAG = "Personalities"
local DEFAULT_FACE = "happy"

local on = Flags.on(FLAG)

-- Visages posés par ce module, autres que « happy » : [ranch][uid] = visage
local faces: { [number]: { [string]: string } } = {}

-- RanchRenderer, requis à la demande (il charge ce module : jamais au chargement de celui-ci)
local function handleOf(slot: number, uid: string): SquishyBuilder.Handle?
	local ok, renderer = pcall(function(): any
		return require(Client.Controllers.RanchRenderer) :: any
	end)
	if not ok or type(renderer) ~= "table" or type(renderer.handleOf) ~= "function" then
		return nil
	end
	local found, handle = pcall(renderer.handleOf, slot, uid)
	if found and type(handle) == "table" then
		return handle
	end
	return nil
end

-- Chaque visage posé revient à « happy » (interrupteur coupé en direct)
local function restoreFaces()
	for slot, list in faces do
		for uid in list do
			local handle = handleOf(slot, uid)
			if handle then
				pcall(SquishyBuilder.setFace, handle, DEFAULT_FACE)
			end
		end
	end
	table.clear(faces)
end

-- Vrai tant que l'interrupteur Personalities est ouvert sur le serveur
function Personality.active(): boolean
	return on
end

-- Pose à dessiner d'un squishy animé à cette image (étape 1 : sa pose de repos)
function Personality.pose(
	_d: any,
	_h: SquishyBuilder.Handle,
	_rec: Types.PublicSquishy,
	_where: string,
	_base: Vector3,
	cf: CFrame,
	_now: number
): CFrame
	return cf
end

-- Le modèle de ce squishy est rendu à la réserve (il y repart avec « happy »)
function Personality.forget(slot: number, uid: string)
	local list = faces[slot]
	if list then
		list[uid] = nil
		if next(list) == nil then
			faces[slot] = nil
		end
	end
end

-- Pose un visage sur le squishy dessiné ; vrai s'il est posé
function Personality.setFace(slot: number, uid: string, face: string): boolean
	if not on or type(slot) ~= "number" or type(uid) ~= "string" or type(face) ~= "string" then
		return false
	end
	if table.find(SquishyBuilder.FACES, face) == nil then
		return false
	end
	local handle = handleOf(slot, uid)
	if handle == nil then
		return false
	end
	if not pcall(SquishyBuilder.setFace, handle, face) then
		return false
	end
	if face == DEFAULT_FACE then
		Personality.forget(slot, uid)
	else
		local list = faces[slot]
		if list == nil then
			list = {}
			faces[slot] = list
		end
		list[uid] = face
	end
	return true
end

-- Visage posé par ce module sur ce squishy (« happy » sinon)
function Personality.faceOf(slot: number, uid: string): string
	local list = faces[slot]
	return if list and list[uid] then list[uid] else DEFAULT_FACE
end

-- Une seule connexion pour la séance : l'interrupteur vu du client (World/Flags)
Flags.Changed:Connect(function()
	local now = Flags.on(FLAG)
	if now == on then
		return
	end
	on = now
	if not on then
		restoreFaces()
	end
	Personality.Changed:Fire()
end)

return Personality
