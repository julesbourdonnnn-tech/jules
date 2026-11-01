--!strict
-- Notifications « toast » empilées en haut de l'écran (3 max, 3 s chacune ; repris de Comet Conga).
--   Toast.show(Prefs.t("feedback.saved"), "success")   -- texte DÉJÀ traduit
--   Toast.TopY = 270                                  -- haut de la pile (px TV, dans Root.safe)
-- La pile commence SOUS la zone des bannières du jeu (Toast.TopY, à régler par le HUD) : un toast
-- ne cache jamais une bannière. Texte jamais sous Config/Console.MinTextSize (28 px TV, lisible sur
-- téléviseur ; console d'abord, note INT-TV : tailles en px TV d'un écran 1920 × 1080).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Console = require(ReplicatedStorage:WaitForChild("Shared").Config.Console)

local Root = require(script.Parent.Root)
local Theme = require(script.Parent.Theme)
local Create = require(script.Parent.Create)
local Juice = require(script.Parent.Juice)

local MAX_VISIBLE = 3
local LIFETIME = 3

local Toast = {}

-- px TV : haut de la pile, sous la zone des bannières (Comet Conga : 72 + 72 + 34 + 2 px de
-- référence 1280 × 720, soit 270 px TV)
Toast.TopY = 270

local container: Frame? = nil
local visible: { Frame } = {}
local order = 0

local KIND_COLORS: { [string]: Color3 } = {
	info = Theme.Colors.Primary,
	success = Theme.Colors.Success,
	warning = Theme.Colors.Warning,
	error = Theme.Colors.Danger,
	reward = Theme.Colors.Gold,
}

local function getContainer(): Frame
	if container and container.Parent then
		return container
	end
	local safe = Root.safe("Toasts", 50)
	container = Create("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Toast.TopY),
		Size = UDim2.fromOffset(780, 300),
		BackgroundTransparency = 1,
		Parent = safe,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
	return container :: Frame
end

local function dismiss(frame: Frame)
	local i = table.find(visible, frame)
	if not i then
		return
	end
	table.remove(visible, i)
	Juice.popOut(frame, function()
		frame:Destroy()
	end)
end

function Toast.show(text: string, kind: string?)
	local parent = getContainer()
	while #visible >= MAX_VISIBLE do
		local oldest = visible[1]
		table.remove(visible, 1)
		oldest:Destroy()
	end
	order += 1
	local accent = KIND_COLORS[kind or "info"] or Theme.Colors.Primary
	local frame = Create("Frame", {
		Name = "Toast",
		LayoutOrder = order,
		Size = UDim2.fromOffset(760, 88),
		BackgroundColor3 = Theme.Colors.Panel,
		Parent = parent,
	}, {
		Create("UICorner", { CornerRadius = Theme.Corner }),
		Create("UIStroke", { Color = accent, Thickness = Theme.StrokeThickness }),
		Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -36, 1, 0),
			Position = UDim2.fromOffset(18, 0),
			FontFace = Theme.Fonts.Body,
			Text = text,
			TextColor3 = Theme.Colors.Text,
			TextScaled = true,
		}, {
			Create("UITextSizeConstraint", { MinTextSize = Console.MinTextSize, MaxTextSize = 32 }),
		}),
	})
	table.insert(visible, frame)
	Juice.popIn(frame)
	task.delay(LIFETIME, function()
		if frame.Parent then
			dismiss(frame)
		end
	end)
end

return Toast
