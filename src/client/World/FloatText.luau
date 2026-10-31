--!strict
-- FloatText — aide du paquet « client-world » : textes flottants dans le monde (« +N », « +1 Puffkin »,
-- « SNIP ! », « ? »), réserve de Balance.Render.FloatTextPool (20) BillboardGui réutilisés en
-- tourniquet (aucune création en rafale, GDD §9.1). Partagée par CongaRenderer (« +N » des perchés)
-- et VFXController (floatText).
--   FloatText.show(pos, text, color, scale?, style?)
-- Styles : "rise" (pop Back Out 0,25 s, monte de 3 studs, fondu sur la fin) ; "stamp" (échelle
-- 0 → 1,4 → 1 en 0,35 s Elastic Out, police LuckiestGuy, contour 3 px, GDD §9.4 « SNIP ! »).
-- Mouvement réduit (Juice.reducedMotion) : ni pop ni montée, fondu seulement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local Juice = require(Client.UI.Juice)
local Fx = require(script.Parent.Fx)

local FloatText = {}

export type Style = "rise" | "stamp"

local POOL_SIZE = Balance.Render.FloatTextPool
local BASE_WIDTH = 7 -- studs (BillboardGui en échelle = studs)
local BASE_HEIGHT = 1.8
local RISE_STUDS = 3
local RISE_SECONDS = 0.9
local STAMP_SECONDS = 1.1
local POP_SECONDS = 0.25
local STAMP_POP_SECONDS = 0.35
local FADE_PART = 0.35 -- dernière fraction de la durée : fondu
local MAX_DISTANCE = 160
local STROKE_COLOR = Color3.fromRGB(35, 25, 55)
local RISE_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local STAMP_FONT = Font.fromEnum(Enum.Font.LuckiestGuy)

type Entry = {
	attachment: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	token: number,
	tweens: { Tween }, -- tweens de l'affichage en cours (annulés quand la bulle est reprise)
}

local entries: { Entry } = {}
local cursor = 0
local carrier: BasePart? = nil

local function build()
	local folder = Fx.folder(Fx.clientWorld(), "FloatText")
	local anchor = Fx.anchor("FloatAnchor", folder)
	carrier = anchor
	table.clear(entries)
	for i = 1, POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Float" .. i
		attachment.Parent = anchor
		local gui = Instance.new("BillboardGui")
		gui.Name = "Text"
		gui.Size = UDim2.fromScale(BASE_WIDTH, BASE_HEIGHT)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = MAX_DISTANCE
		gui.ResetOnSpawn = false
		gui.Enabled = false
		gui.Adornee = attachment
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.FontFace = RISE_FONT
		label.Text = ""
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = STROKE_COLOR
		stroke.Parent = label
		local scale = Instance.new("UIScale")
		scale.Parent = label
		gui.Parent = attachment
		entries[i] = {
			attachment = attachment,
			gui = gui,
			label = label,
			stroke = stroke,
			scale = scale,
			token = 0,
			tweens = {},
		}
	end
end

-- Annule les tweens encore actifs d'une bulle reprise par le tourniquet : sans cela, le fondu ou la
-- montée de l'affichage précédent continue d'écrire TextTransparency / StudsOffset et rend le
-- nouveau texte invisible (plus de 20 textes en moins d'une seconde : parade + perchés + captures)
local function stopTweens(e: Entry)
	for _, tween in e.tweens do
		tween:Cancel()
	end
	table.clear(e.tweens)
end

local function track(e: Entry, tween: Tween)
	table.insert(e.tweens, tween)
end

local function ensure()
	local c = carrier
	if c == nil or c.Parent == nil or #entries == 0 then
		build()
	end
end

-- Affiche `text` au point monde `pos` ; `scale` agrandit la bulle (Commun ×0,8 → Mythique ×1,6)
function FloatText.show(pos: Vector3, text: string, color: Color3, scale: number?, style: Style?)
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
		return
	end
	ensure()
	cursor = cursor % POOL_SIZE + 1
	local e = entries[cursor]
	e.token += 1
	local token = e.token
	stopTweens(e)
	local k = math.clamp(scale or 1, 0.2, 4)
	local stamp = style == "stamp"
	local reduced = Juice.reducedMotion()
	e.attachment.Position = pos
	e.gui.Size = UDim2.fromScale(BASE_WIDTH * k, BASE_HEIGHT * k)
	e.gui.StudsOffset = Vector3.zero
	e.label.Text = text
	e.label.TextColor3 = color
	e.label.FontFace = if stamp then STAMP_FONT else RISE_FONT
	e.label.TextTransparency = 0
	e.stroke.Transparency = 0
	e.gui.Enabled = true
	local duration = if stamp then STAMP_SECONDS else RISE_SECONDS
	if reduced then
		e.scale.Scale = 1
	elseif stamp then
		e.scale.Scale = 0
		track(
			e,
			Juice.tween(
				e.scale,
				STAMP_POP_SECONDS,
				{ Scale = 1 },
				Enum.EasingStyle.Elastic,
				Enum.EasingDirection.Out
			)
		)
	else
		e.scale.Scale = 0
		track(
			e,
			Juice.tween(e.scale, POP_SECONDS, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		)
		track(e, Juice.tween(e.gui, duration, { StudsOffset = Vector3.new(0, RISE_STUDS, 0) }))
	end
	local fade = duration * FADE_PART
	task.delay(duration - fade, function()
		if e.token ~= token then
			return
		end
		track(e, Juice.tween(e.label, fade, { TextTransparency = 1 }))
		track(e, Juice.tween(e.stroke, fade, { Transparency = 1 }))
	end)
	task.delay(duration, function()
		if e.token == token then
			e.gui.Enabled = false
		end
	end)
end

-- Nombre de bulles de la réserve (tests, budget)
function FloatText.poolSize(): number
	ensure()
	return #entries
end

-- Bulles actuellement affichées
function FloatText.activeCount(): number
	local n = 0
	for _, e in entries do
		if e.gui.Enabled then
			n += 1
		end
	end
	return n
end

return FloatText
