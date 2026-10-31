--!strict
-- Panels/Crew — paquet « client-panels » (docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * équipage actuel (WorldStateController.crews), bonus (+10 % par équipier) et escorte ;
--     liste des joueurs du serveur avec Inviter (56 px) → CrewInvite(userId) (limite locale
--     1 / 3 s et 5 / min, comme le serveur) ; Quitter → CrewLeave (recharge 5 s) ; Inviter un
--     ami → SocialService:PromptGameInvite (aucune récompense, §6.2)
--   * carte d'invitation reçue (remote CrewInvitePrompt routé par PanelController) : « Mira
--     t'invite ! » ✓ / ✕ pendant 20 s → CrewRespond(inviterId, accept) ; NON bloquante (elle vit
--     hors de la fenêtre des panneaux, glisse depuis la droite), file de 3 au plus ; échéance lue
--     sur Clock (une connexion Heartbeat tant qu'une carte est visible) ; une nouvelle invitation
--     du même joueur prolonge la carte ; un inviteur qui quitte le serveur retire sa carte
--   * panneau ouvert : rafraîchi chaque seconde (« Inviter » revient après 20 s, Quitter après 5 s)
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged) ; intentions seulement
--     (le serveur valide tout)
-- GDD : §6.1, §6.2, §9.4 (Équipage), §10.3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Cosmetics = require(Shared.Config.Cosmetics)
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local AudioController = require(Client.Controllers.AudioController)
local Prefs = require(Client.Util.Prefs)
local Root = require(Client.UI.Root)
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Juice = require(Client.UI.Juice)
local Toast = require(Client.UI.Toast)
local WorldState = require(Client.Controllers.WorldStateController)
local Widgets = require(script.Parent.Widgets)

local Panel = {}

Panel.name = "Crew" :: Types.PanelName
Panel.tabs = nil :: { string }?

local ROW_HEIGHT = 64
local MAX_PENDING = 3
local INVITE_SIZE = Vector2.new(360, 156)
local SLIDE_TIME = 0.3
local MINUTE = 60
local REFRESH_INTERVAL = 1 -- s : minuteurs « Envoyée ! » et recharge de Quitter

type PlayerRow = { frame: Frame, dot: Frame, name: TextLabel, invite: TextButton, tag: TextLabel }
type Invite = { inviterId: number, expiresAt: number }

local built = false
local isOpen = false
local dirty = false
local membersTitle: TextLabel? = nil
local membersList: Frame? = nil
local bonusLabel: TextLabel? = nil
local leaveButton: TextButton? = nil
local playersTitle: TextLabel? = nil
local playersList: ScrollingFrame? = nil
local aloneLabel: TextLabel? = nil
local friendButton: TextButton? = nil
local rows: { [number]: PlayerRow } = {}
local inviteTimes: { number } = {} -- envois récents (limite 1 / 3 s, 5 / min)
local sentTo: { [number]: number } = {}
local leftAt = -math.huge
local refreshAcc = 0
local membersSig: string? = nil -- équipage affiché (les puces ne sont refaites qu'au changement)

-- carte d'invitation
local pending: { Invite } = {}
local card: Frame? = nil
local cardText: TextLabel? = nil
local cardFill: Frame? = nil
local shown: Invite? = nil
local cardConn: RBXScriptConnection? = nil -- Heartbeat tant qu'une carte est visible
local removingConn: RBXScriptConnection? = nil

-- ---------------------------------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------------------------------

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player then player.UserId else 0
end

local function displayName(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else nil
end

local function nestColor(player: Player): Color3
	local slot = player:GetAttribute("Slot")
	if type(slot) == "number" and Cosmetics.NestColors[slot] then
		return Cosmetics.NestColors[slot]
	end
	return Cosmetics.FreeNestColor
end

-- Membres de l'équipage du joueur local (lui compris), sinon vide
local function myCrew(): { number }
	local me = localUserId()
	local state = WorldState.crews()
	if type(state) ~= "table" or type(state.crews) ~= "table" then
		return {}
	end
	for _, crew in state.crews do
		if type(crew) == "table" and type(crew.userIds) == "table" and table.find(crew.userIds, me) then
			return crew.userIds
		end
	end
	return {}
end

-- Limites locales d'invitation (le serveur reste seul juge : 1 / 3 s et 5 / 60 s)
local function canInvite(now: number): boolean
	local recent = {}
	for _, t in inviteTimes do
		if now - t < MINUTE then
			table.insert(recent, t)
		end
	end
	inviteTimes = recent
	local last = recent[#recent]
	if last and now - last < Balance.Crew.InviteCooldown then
		return false
	end
	return #recent < Balance.Crew.InvitesPerMinute
end

-- ---------------------------------------------------------------------------------------------
-- Rendu du panneau
-- ---------------------------------------------------------------------------------------------

local function memberChip(userId: number, order: number, parent: Instance)
	local player = Players:GetPlayerByUserId(userId)
	local chip = Widgets.card({
		name = "Member" .. userId,
		size = UDim2.fromOffset(180, 48),
		order = order,
		color = Color3.fromRGB(56, 74, 110),
		parent = parent,
	})
	Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = if player then nestColor(player) else Cosmetics.FreeNestColor,
		Parent = chip,
	}, { Widgets.round(), Widgets.stroke(nil, 1.5) })
	Widgets.label({
		name = "Name",
		text = (if userId == localUserId() then "★ " else "") .. (displayName(userId) or "?"),
		size = UDim2.new(1, -44, 1, -8),
		position = UDim2.fromOffset(38, 4),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 20,
		parent = chip,
	})
end

local function playerRow(player: Player, parent: Instance): PlayerRow
	local frame = Widgets.card({
		name = "Player" .. player.UserId,
		size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		parent = parent,
	})
	local dot = Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = nestColor(player),
		Parent = frame,
	}, { Widgets.round(), Widgets.stroke(nil, 1.5) }) :: Frame
	local name = Widgets.label({
		name = "Name",
		size = UDim2.new(1, -(56 + 180), 1, -12),
		position = UDim2.fromOffset(52, 6),
		xAlign = Enum.TextXAlignment.Left,
		maxSize = 22,
		parent = frame,
	})
	local userId = player.UserId
	local invite = Widgets.button({
		name = "Invite",
		size = UDim2.fromOffset(160, 56), -- 56 px (§6.1)
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Theme.Colors.Primary,
		maxText = 22,
		parent = frame,
		onClick = function()
			Panel.invite(userId)
		end,
		onRefused = function()
			-- bouton grisé : l'équipage est plein
			Toast.show(Prefs.t("feedback.crewFull"), "warning")
		end,
	})
	local tag = Widgets.label({
		name = "Tag",
		size = UDim2.fromOffset(160, 40),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = Widgets.CYAN,
		maxSize = 20,
		parent = frame,
	})
	return { frame = frame, dot = dot, name = name, invite = invite, tag = tag }
end

local function render()
	if not built then
		return
	end
	local now = Clock.now()
	local me = localUserId()
	local crew = myCrew()
	local inCrew = #crew > 1
	if membersTitle then
		membersTitle.Text = Prefs.t("crew.members")
	end
	local members = membersList
	-- signature : membres, présence (nom) et Nid (couleur) ; le rafraîchissement d'une seconde ne
	-- recrée rien tant qu'elle ne change pas
	local sigParts = {}
	if inCrew then
		for _, userId in crew do
			local player = Players:GetPlayerByUserId(userId)
			local slot = if player then player:GetAttribute("Slot") else nil
			table.insert(sigParts, `{userId}:{displayName(userId) or ""}:{tostring(slot)}`)
		end
	end
	local sig = table.concat(sigParts, ",")
	if members and sig ~= membersSig then
		membersSig = sig
		for _, child in members:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if inCrew then
			for i, userId in crew do
				memberChip(userId, i, members)
			end
		end
	end
	if bonusLabel then
		bonusLabel.Text = if inCrew
			then Prefs.t("crew.bonus", { percent = math.floor(Balance.Crew.BonusPerMate * 100 + 0.5) })
				.. "\n"
				.. Prefs.t("crew.escort")
			else Prefs.t("crew.empty")
	end
	if leaveButton then
		leaveButton.Visible = inCrew
		Widgets.setText(leaveButton, Prefs.t("crew.leave"))
		Widgets.setEnabled(leaveButton, now - leftAt >= Balance.Crew.LeaveCooldown)
	end
	if playersTitle then
		playersTitle.Text = Prefs.t("crew.players")
	end
	local list = playersList
	if not list then
		return
	end
	local present: { [number]: boolean } = {}
	local count = 0
	local full = #crew >= Balance.Crew.MaxSize
	for _, player in Players:GetPlayers() do
		if player.UserId ~= me then
			count += 1
			present[player.UserId] = true
			local row = rows[player.UserId]
			if not row then
				row = playerRow(player, list)
				rows[player.UserId] = row
			end
			row.frame.LayoutOrder = count
			row.dot.BackgroundColor3 = nestColor(player)
			row.name.Text = player.DisplayName
			local mate = table.find(crew, player.UserId) ~= nil
			local sent = sentTo[player.UserId]
			local recentlySent = sent ~= nil and now - sent < Balance.Crew.InviteTTL
			row.invite.Visible = not mate and not recentlySent
			Widgets.setText(row.invite, Prefs.t("crew.invite"))
			Widgets.setEnabled(row.invite, not full)
			row.tag.Visible = mate or recentlySent
			row.tag.Text = if mate then "★ " .. Prefs.t("crew.mate") else Prefs.t("crew.inviteSent")
		end
	end
	for userId, row in rows do
		if not present[userId] then
			row.frame:Destroy()
			rows[userId] = nil
			sentTo[userId] = nil
		end
	end
	if aloneLabel then
		aloneLabel.Text = Prefs.t("crew.alone")
		aloneLabel.Visible = count == 0
	end
	if friendButton then
		Widgets.setText(friendButton, Prefs.t("crew.inviteFriend"))
	end
end

-- Invite un joueur du serveur (intention ; le serveur vérifie tout)
function Panel.invite(userId: number)
	if type(userId) ~= "number" or userId == localUserId() then
		return
	end
	local row = rows[userId]
	local now = Clock.now()
	if not Players:GetPlayerByUserId(userId) or not canInvite(now) then
		if row then
			Widgets.refuse(row.invite)
		end
		return
	end
	table.insert(inviteTimes, now)
	sentTo[userId] = now
	Net.event("CrewInvite"):FireServer(userId)
	AudioController.play("Pop")
	render()
end

local function leave()
	local now = Clock.now()
	if now - leftAt < Balance.Crew.LeaveCooldown or #myCrew() <= 1 then
		if leaveButton then
			Widgets.refuse(leaveButton)
		end
		return
	end
	leftAt = now
	Net.event("CrewLeave"):FireServer()
	render()
end

local function inviteFriend()
	local player = Players.LocalPlayer
	task.spawn(function()
		local okCan, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if okCan and can == false then
			if friendButton then
				Widgets.refuse(friendButton)
			end
			return
		end
		local ok, err = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if not ok then
			warn("[Crew] PromptGameInvite :", err)
		end
	end)
end

function Panel.build(parent: Frame)
	if built then
		return
	end
	built = true
	membersTitle = Widgets.label({
		name = "MembersTitle",
		size = UDim2.new(0.6, 0, 0, 34),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 26,
		parent = parent,
	})
	leaveButton = Widgets.button({
		name = "Leave",
		size = UDim2.fromOffset(190, 48),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.Danger,
		maxText = 20,
		parent = parent,
		onClick = leave,
	})
	membersList = Create("Frame", {
		Name = "Members",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 52),
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) }) :: Frame
	bonusLabel = Widgets.label({
		name = "Bonus",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 110),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.TextDim,
		font = Theme.Fonts.Body,
		maxSize = 18,
		parent = parent,
	})
	playersTitle = Widgets.label({
		name = "PlayersTitle",
		size = UDim2.new(0.6, 0, 0, 34),
		position = UDim2.fromOffset(0, 160),
		xAlign = Enum.TextXAlignment.Left,
		color = Theme.Colors.Gold,
		maxSize = 26,
		parent = parent,
	})
	friendButton = Widgets.button({
		name = "InviteFriend",
		size = UDim2.fromOffset(220, 48),
		position = UDim2.new(1, 0, 0, 154),
		anchor = Vector2.new(1, 0),
		color = Theme.Colors.Success,
		maxText = 20,
		parent = parent,
		onClick = inviteFriend,
	})
	playersList = Create("ScrollingFrame", {
		Name = "Players",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 210),
		Size = UDim2.new(1, 0, 1, -210),
		CanvasSize = UDim2.new(),
		CanvasPosition = Vector2.zero,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = parent,
	}, { Widgets.listLayout(Enum.FillDirection.Vertical, 6) }) :: ScrollingFrame
	aloneLabel = Widgets.label({
		name = "Alone",
		size = UDim2.new(1, -40, 0, 40),
		position = UDim2.new(0.5, 0, 0, 240),
		anchor = Vector2.new(0.5, 0),
		color = Theme.Colors.TextDim,
		maxSize = 22,
		parent = parent,
	})

	WorldState.CrewsChanged:Connect(function()
		dirty = true
	end)
	Players.PlayerAdded:Connect(function()
		dirty = true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		sentTo[player.UserId] = nil
		dirty = true
	end)
	Prefs.LanguageChanged:Connect(function()
		dirty = true
	end)
	render()
end

function Panel.onOpen(_args: any?)
	isOpen = true
	dirty = false
	render()
end

function Panel.onClose()
	isOpen = false
end

-- Pastille sur l'icône Équipage tant qu'une invitation attend une réponse
function Panel.hasAction(): boolean
	return shown ~= nil or #pending > 0
end

function Panel.step(dt: number)
	if not built or not isOpen then
		return
	end
	refreshAcc += dt
	if refreshAcc >= REFRESH_INTERVAL then
		-- minuteurs : « Envoyée ! » expire (InviteTTL), Quitter se réactive (LeaveCooldown)
		refreshAcc = 0
		dirty = true
	end
	if dirty then
		dirty = false
		render()
	end
end

function Panel.defaultSelection(): GuiObject?
	for _, row in rows do
		if row.invite.Visible then
			return row.invite
		end
	end
	return friendButton
end

-- ---------------------------------------------------------------------------------------------
-- Carte d'invitation (non bloquante, hors de la fenêtre des panneaux)
-- ---------------------------------------------------------------------------------------------

local showNext: () -> ()

local function hideCard()
	shown = nil
	local conn = cardConn
	if conn then
		conn:Disconnect()
		cardConn = nil
	end
	local frame = card
	if frame then
		frame.Visible = false
	end
end

-- Échéance de l'invitation affichée, lue sur l'horloge du jeu (Clock), comme le serveur
local function stepCard()
	local invite = shown
	if invite and Clock.now() >= invite.expiresAt then
		showNext()
	end
end

-- Barre de temps : remplissage restant puis vidage linéaire jusqu'à l'échéance
local function startTimer(invite: Invite)
	local fill = cardFill
	if not fill then
		return
	end
	local remaining = math.max(0, invite.expiresAt - Clock.now())
	fill.Size = UDim2.fromScale(math.clamp(remaining / Balance.Crew.InviteTTL, 0, 1), 1)
	Juice.tween(fill, remaining, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
end

-- Un inviteur qui quitte le serveur : sa carte (ou son invitation en file) disparaît
local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	for i = #pending, 1, -1 do
		if pending[i].inviterId == userId then
			table.remove(pending, i)
		end
	end
	local current = shown
	if current and current.inviterId == userId then
		showNext()
	end
end

local function ensureCard(): Frame
	if card and card.Parent then
		return card
	end
	if removingConn == nil then
		removingConn = Players.PlayerRemoving:Connect(onPlayerRemoving)
	end
	local safe = Root.safe("Panels", 30)
	local frame = Widgets.card({
		name = "CrewInvite",
		size = UDim2.fromOffset(INVITE_SIZE.X, INVITE_SIZE.Y),
		position = UDim2.new(1, -16, 0.42, 0),
		anchor = Vector2.new(1, 0.5),
		color = Color3.fromRGB(56, 74, 120),
		parent = safe,
	})
	frame.Visible = false
	frame.ZIndex = 40
	cardText = Widgets.label({
		name = "Text",
		size = UDim2.new(1, -20, 0, 44),
		position = UDim2.fromOffset(10, 8),
		maxSize = 26,
		zIndex = 41,
		parent = frame,
	})
	local bar = Widgets.bar({
		name = "Timer",
		size = UDim2.new(1, -20, 0, 10),
		position = UDim2.fromOffset(10, 56),
		color = Widgets.CYAN,
		parent = frame,
	})
	cardFill = bar:FindFirstChild("Fill") :: Frame?
	local function respond(accept: boolean)
		local invite = shown
		if not invite then
			return
		end
		Net.event("CrewRespond"):FireServer(invite.inviterId, accept)
		showNext()
	end
	local accept = Widgets.button({
		name = "Accept",
		text = "✓",
		size = UDim2.new(0.5, -15, 0, 64),
		position = UDim2.new(0, 10, 1, -10),
		anchor = Vector2.new(0, 1),
		color = Theme.Colors.Success,
		maxText = 34,
		parent = frame,
		onClick = function()
			respond(true)
		end,
	})
	local decline = Widgets.button({
		name = "Decline",
		text = "✕",
		size = UDim2.new(0.5, -15, 0, 64),
		position = UDim2.new(1, -10, 1, -10),
		anchor = Vector2.new(1, 1),
		color = Theme.Colors.Danger,
		maxText = 34,
		parent = frame,
		onClick = function()
			respond(false)
		end,
	})
	accept.ZIndex = 41
	decline.ZIndex = 41
	card = frame
	return frame
end

function showNext()
	local frame = ensureCard()
	local now = Clock.now()
	-- invitations expirées ou d'un joueur parti : ignorées
	while #pending > 0 do
		local first = pending[1]
		if first.expiresAt > now and displayName(first.inviterId) ~= nil then
			break
		end
		table.remove(pending, 1)
	end
	local invite = table.remove(pending, 1)
	if not invite then
		hideCard()
		return
	end
	shown = invite
	if cardText then
		cardText.Text = Prefs.t("crew.prompt", { name = displayName(invite.inviterId) or "?" })
	end
	frame.Visible = true
	startTimer(invite)
	if Juice.reducedMotion() then
		frame.Position = UDim2.new(1, -16, 0.42, 0)
	else
		-- glisse depuis la droite (0,3 s Back Out)
		frame.Position = UDim2.new(1, INVITE_SIZE.X + 40, 0.42, 0)
		Juice.tween(frame, SLIDE_TIME, { Position = UDim2.new(1, -16, 0.42, 0) }, Enum.EasingStyle.Back)
	end
	AudioController.play("Pop")
	if cardConn == nil then
		cardConn = RunService.Heartbeat:Connect(stepCard)
	end
end

-- Carte d'invitation (appelée par PanelController sur CrewInvitePrompt)
function Panel.showInvite(payload: Types.CrewInvitePayload)
	if type(payload) ~= "table" then
		return
	end
	local inviterId, expiresAt = payload.inviterId, payload.expiresAt
	if type(inviterId) ~= "number" or type(expiresAt) ~= "number" or expiresAt ~= expiresAt then
		return
	end
	if expiresAt <= Clock.now() or displayName(inviterId) == nil then
		return
	end
	-- même inviteur : la nouvelle invitation (serveur) remplace l'ancienne et prolonge la carte
	local current = shown
	if current and current.inviterId == inviterId then
		current.expiresAt = expiresAt
		startTimer(current)
		return
	end
	for _, invite in pending do
		if invite.inviterId == inviterId then
			invite.expiresAt = expiresAt
			return
		end
	end
	if #pending >= MAX_PENDING then
		return
	end
	table.insert(pending, { inviterId = inviterId, expiresAt = expiresAt })
	if shown == nil then
		showNext()
	end
end

-- Exposé pour les tests
Panel._shown = function(): Invite?
	return shown
end
Panel._pending = function(): { Invite }
	return pending
end
Panel._card = function(): Frame?
	return card
end
Panel._rowsByUser = rows

return Panel
