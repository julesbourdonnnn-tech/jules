--!strict
-- File du message central du HUD (GDD §10.2, emplacement de message ; docs/04 §13.5) : un seul
-- message à la fois, dans l'emplacement Layout.Hud.message (sous la pastille d'événement).
--   * Les messages (UI/Toast du socle, 32 px TV) attendent leur tour : 3 au plus en file, les messages
--     identiques fusionnés (« +X pièces ×3 »), chacun affiché DISPLAY s ; un message qui attend plus de
--     STALE s est jeté (jamais une file qui grossit sans fin).
--   * Une bannière (UI/Banners) passe d'abord : pendant qu'elle est à l'écran (hold), les messages
--     attendent.
-- Module partagé par UI/HUD (Feedback, célébrations à message) et UI/Banners (hold) : un seul état.
-- step(now) est appelé par la boucle par image du HUD ; temps par Clock (specs : voyage dans le temps).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Clock = require(Shared.Util.Clock)
local Layout = require(Shared.Config.Layout)

local Client = script.Parent.Parent.Parent
local Toast = require(Client.UI.Toast)
local Util = require(Client.UI.Hud.Util)

local Messages = {}

local QUEUE_MAX = 3
local STALE = 12 -- s : un message qui attend plus longtemps est jeté
-- s : durée d'affichage (Toast du socle : 3 s de vie + 0,15 s de sortie ; une seule à l'écran)
local DISPLAY = 3.2
local TEXT_MAX = 160

type Item = { text: string, kind: string, count: number, at: number }

local queue: { Item } = {}
local busyUntil = -math.huge
local holds: { [string]: boolean } = {}
local shown: { text: string, at: number }? = nil

-- Haut de la pile des messages : l'emplacement de message du HUD (coordonnées de Root.safe), posé
-- dès le chargement (un Toast montré directement par un panneau s'y place aussi)
Messages.TopY = Layout.Hud.message.rect.y - Layout.Safe.y
Toast.TopY = Messages.TopY

local function held(): boolean
	return next(holds) ~= nil
end

local function display(item: Item)
	local text = item.text
	if item.count > 1 then
		text = text .. " ×" .. tostring(item.count)
	end
	Toast.TopY = Messages.TopY
	Util.safe("Toast.show", nil, Toast.show, text, item.kind)
	local now = Clock.now()
	busyUntil = now + DISPLAY
	shown = { text = text, at = now }
end

-- Met un message (déjà traduit) dans la file ; fusionné avec un message identique qui attend
function Messages.push(text: string, kind: string?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local value = text
	if #value > TEXT_MAX then
		-- coupe sur un caractère entier (accents, ★, ♥) : jamais un UTF-8 cassé dans le libellé
		local ok, start = pcall(utf8.offset, value, 0, TEXT_MAX + 1)
		local cut = if ok and type(start) == "number" then start - 1 else TEXT_MAX
		value = string.sub(value, 1, cut)
		if utf8.len(value) == nil then
			value = (string.gsub(value, "[\128-\255]", ""))
		end
	end
	local tone = if type(kind) == "string" then kind else "info"
	for _, item in queue do
		if item.text == value then
			item.count += 1
			return
		end
	end
	if #queue >= QUEUE_MAX then
		table.remove(queue, 1) -- le plus ancien laisse sa place
	end
	table.insert(queue, { text = value, kind = tone, count = 1, at = Clock.now() })
	Messages.step(Clock.now())
end

-- Tient (ou libère) l'emplacement : une bannière est à l'écran (raison = qui tient)
function Messages.hold(reason: string, on: boolean)
	if on then
		holds[reason] = true
	else
		holds[reason] = nil
		Messages.step(Clock.now())
	end
end

-- Un tour : messages trop vieux jetés, puis le suivant s'affiche si l'emplacement est libre
function Messages.step(now: number)
	for i = #queue, 1, -1 do
		local age = now - queue[i].at
		if age > STALE or age < -STALE then
			table.remove(queue, i)
		end
	end
	if held() or #queue == 0 then
		return
	end
	if now < busyUntil and now >= busyUntil - DISPLAY then
		return
	end
	display(table.remove(queue, 1) :: Item)
end

-- Messages en attente (specs)
function Messages.pending(): number
	return #queue
end

-- L'emplacement est-il occupé par un message ou tenu par une bannière ?
function Messages.busy(now: number): boolean
	return held() or (now < busyUntil and now >= busyUntil - DISPLAY)
end

-- Dernier message affiché (specs)
function Messages.last(): { text: string, at: number }?
	return shown
end

-- Remise à zéro (specs)
function Messages._reset()
	table.clear(queue)
	table.clear(holds)
	busyUntil = -math.huge
	shown = nil
end

-- Les messages des panneaux (Toast.message) passent par cette file (note client-hud n° 1)
Toast.router = Messages.push

return Messages
