--!strict
-- Notifications « toast » empilées en haut de l'écran (3 max, 3 s chacune ; repris de Comet Conga).
--   Toast.show(Prefs.t("feedback.saved"), "success")   -- texte DÉJÀ traduit, affiché tout de suite
--   Toast.message(Prefs.t("feedback.penFull"), "warning") -- message du jeu : passe par Toast.router
--   Toast.TopY = 270                                  -- haut de la pile (px TV, dans Root.safe)
-- Toast.router (posé par le HUD : file du message central, GDD §10.2) reçoit chaque Toast.message :
-- un message à la fois, après la bannière, caché en mode photo. Sans routeur, Toast.message = show.
-- Toast.Lifetime : durée de vie d'un toast (s), lue à chaque show.
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

local Toast = {}

Toast.Lifetime = 3
Toast.router = nil :: ((text: string, kind: string?) -> ())?

-- px TV : haut de la pile, sous la zone des bannières (Comet Conga : 72 + 72 + 34 + 2 px de
-- référence 1280 × 720, soit 270 px TV)
Toast.TopY = 270

-- Panneau ouvert (posé par PanelController) : rend le haut de la pile en px de Root.safe, ou nil.
-- La pile se pose alors dans la barre de titre du panneau (le titre est caché 3 s) et ne garde
-- qu'un toast : à sa place habituelle, elle cachait les onglets du panneau (outil d'écrans, type
-- « covered » : Ranch › Enclos › Ranger quand il n'y a rien à ranger)
Toast.anchor = nil :: (() -> number?)?

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

-- Haut de la pile et nombre de toasts gardés : sous les bannières, ou dans la barre de titre du
-- panneau ouvert (un seul toast)
local function placement(): (number, number)
	local anchor = Toast.anchor
	if anchor then
		local ok, y = pcall(anchor)
		if ok and type(y) == "number" and y == y and y >= 0 then
			return y, 1
		end
	end
	return Toast.TopY, MAX_VISIBLE
end

-- Replace la pile (panneau ouvert ou fermé) et retire les toasts en trop, les plus anciens d'abord
function Toast.relayout()
	local stack = container
	if stack == nil or stack.Parent == nil then
		return
	end
	local y, keep = placement()
	stack.Position = UDim2.new(0.5, 0, 0, y)
	while #visible > keep do
		local oldest = visible[1]
		table.remove(visible, 1)
		oldest:Destroy()
	end
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
	local y, keep = placement()
	parent.Position = UDim2.new(0.5, 0, 0, y)
	while #visible >= keep do
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
	local lifetime = if type(Toast.Lifetime) == "number" and Toast.Lifetime > 0 then Toast.Lifetime else 3
	task.delay(lifetime, function()
		if frame.Parent then
			dismiss(frame)
		end
	end)
end

-- Message du jeu : par le routeur s'il existe (file du HUD), sinon affiché tout de suite ; un
-- routeur qui lève retombe sur show (jamais un message perdu)
function Toast.message(text: string, kind: string?)
	local router = Toast.router
	if router then
		local ok = pcall(router, text, kind)
		if ok then
			return
		end
	end
	Toast.show(text, kind)
end

return Toast
