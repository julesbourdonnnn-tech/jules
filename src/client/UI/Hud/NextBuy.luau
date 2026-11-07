--!strict
-- Hud/NextBuy (lot B2, décisions D12, D13, D21 ; GDD v2.0 §10.2 ; docs/04 §27.14, N18) : puce
-- « Prochain achat » du HUD v2.0 (Layout.HudV2.NextBuy : 96, 342, 440 × 96). Construite par le HUD au
-- premier instantané du serveur (UpgradeSnapshot, D2), jamais sans lui (jeu de base : aucune instance).
--
--   NextBuy.build(parent, place, onClick, onSeen) -- la puce (TextButton jamais sélectionnable)
--   NextBuy.onSnapshot(snap)                -- instantané accepté : la cible est-elle à recalculer ?
--   NextBuy.step(now, snap, show)           -- depuis la boucle unique du HUD (aucune connexion ici)
--   NextBuy.target()                        -- cible montrée (specs)
--
-- Cible = UpgradeAdvisor.next(instantané) (famille de pièces du Conseillé, payable d'abord) :
--   * recalculée SEULEMENT après un achat (niveaux), un prestige (r, Record R, A) ou un changement de
--     plafond (caps) ; jamais entre deux : les pièces qui montent ne la changent pas ;
--   * évaluée au plus Balance.Upgrades.NextChipHz fois par seconde (un déclencheur arrivé plus tôt
--     attend son tour) ;
--   * ligne 1 : icône DESSINÉE de la famille (Config/Upgrades.icon), nom court (upgrades.short.<id>,
--     12 caractères au plus) et « Niv. 8 » (common.level : niveau montré par l'écran, Tapis Étoilé
--     12 + n) ; ligne 2 : « 12,3 K / 20 K » (common.ratio, BigNumber) et une barre dessous ;
--   * payable : hud.nextBuy.ready et UNE pulsation au passage à « Prêt » (jamais de clignotement) ;
--   * UiSeen("nextBuy") à sa première vraie apparition (une fois par session, Widgets.seen) ;
--   * clic de souris : l'écran Améliorations sur Conseillé (D13) ; à la manette, aucune sélection en
--     jeu (GDD §10.6) : la puce dit seulement qu'un achat est prêt.
-- Le HUD décide quand elle se montre (accueil jusqu'à la leçon du menu, rail ou panneau ouvert, suivi
-- du Grand Splorch « Prêt », mode photo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Layout = require(Shared.Config.Layout)
local Balance = require(Shared.Config.Balance)
local Upgrades = require(Shared.Config.Upgrades)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local UpgradeAdvisor = require(Shared.Logic.UpgradeAdvisor)

local Client = script.Parent.Parent.Parent
local Theme = require(Client.UI.Theme)
local Juice = require(Client.UI.Juice)
local Text = require(Client.UI.Text)
local Format = require(Client.UI.Format)
local Util = require(Client.UI.Hud.Util)
local Icons = require(Client.UI.Hud.Icons)

local NextBuy = {}

export type Target = UpgradeAdvisor.Next

local RECT = Layout.HudV2.NextBuy
local ICON = 48
local NAME_TEXT = 32
local VALUE_TEXT = 28
local PERIOD = 1 / math.max(0.1, Balance.Upgrades.NextChipHz) -- s entre deux évaluations (0,5 s)
local BAR_H = 6
local GOLD = Theme.Colors.Gold
local BAR_FILL = Color3.fromRGB(120, 220, 160)

local IDS = UpgradeMath.ids()
-- Icônes des familles de pièces (celles que le Conseillé peut désigner)
local KINDS: { string } = {}
for _, def in Upgrades.Families do
	if def.currency == "coins" and Icons.has(def.icon) and not table.find(KINDS, def.icon) then
		table.insert(KINDS, def.icon)
	end
end

local chip: TextButton? = nil
local refs: { [string]: any } = {}
local texts: { [string]: string } = {}
local current: Target? = nil
local dirty = true -- cible à recalculer (premier instantané, achat, prestige, plafond)
local evalAt = -math.huge -- Clock du HUD à la dernière évaluation
local evaluations = 0
local lastTrigger: Types.UpgradeSnapshot? = nil
local shownVersion = -1
local wasReady: boolean? = nil
local seen = false
local seenFn: (() -> ())? = nil

-- =============================================================================================
-- Pur
-- =============================================================================================

-- Ce qui change la cible a-t-il changé entre deux instantanés ? (niveaux, plafonds, r, Record R, A ;
-- jamais les pièces ni les Confettis)
function NextBuy.triggerChanged(a: Types.UpgradeSnapshot?, b: Types.UpgradeSnapshot): boolean
	if a == nil then
		return true
	end
	if a.r ~= b.r or a.bestR ~= b.bestR or a.ascend ~= b.ascend then
		return true
	end
	for _, id in IDS do
		if (a.levels[id] or 0) ~= (b.levels[id] or 0) or (a.caps[id] or 0) ~= (b.caps[id] or 0) then
			return true
		end
	end
	return false
end

-- Niveau montré de la cible (Tapis Étoilé : 12 + n, comme la ligne et la carte de l'écran)
function NextBuy.shownLevel(t: Target): number
	local def = Upgrades.ById[t.id]
	local offset = if def and type(def.levelOffset) == "number" then def.levelOffset else 0
	return t.level + offset
end

-- =============================================================================================
-- Construction
-- =============================================================================================

local function setText(name: string, label: TextLabel?, text: string)
	if label == nil then
		return
	end
	if texts[name] ~= text then
		texts[name] = text
		Text.raw(label, text)
	end
end

-- La puce (TextButton jamais sélectionnable : le stick fait marcher), placée par `place` au rectangle
-- du HUD v2.0 ; `onClick` : clic de souris (l'écran Améliorations sur Conseillé) ; `onSeen` : sa
-- première vraie apparition (UiSeen « nextBuy », une fois par session)
function NextBuy.build(
	parent: Instance,
	place: (GuiObject) -> (),
	onClick: () -> (),
	onSeen: () -> ()
): TextButton
	if chip ~= nil then
		return chip :: TextButton
	end
	local b = Instance.new("TextButton")
	b.Name = "nextBuy"
	Text.raw(b, "")
	b.AutoButtonColor = false
	b.Selectable = false
	b.BackgroundColor3 = Theme.Colors.Panel
	b.BackgroundTransparency = 0.12
	b.BorderSizePixel = 0
	b.ZIndex = 2
	b.Size = UDim2.fromOffset(RECT.w, RECT.h)
	Util.chrome(b)
	local icon = Icons.canvas(b, ICON, KINDS, "Icon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.ZIndex = 3
	refs.icon = icon
	local textX = 16 + ICON + 16
	refs.name = Util.label({
		name = "Name",
		parent = b,
		size = UDim2.fromOffset(RECT.w - textX - 124, 40),
		position = UDim2.fromOffset(textX, 6),
		textSize = NAME_TEXT,
		align = Enum.TextXAlignment.Left,
		zIndex = 3,
	})
	refs.level = Util.label({
		name = "Level",
		parent = b,
		size = UDim2.fromOffset(112, 40),
		position = UDim2.fromOffset(RECT.w - 16 - 112, 6),
		textSize = NAME_TEXT,
		align = Enum.TextXAlignment.Right,
		zIndex = 3,
	})
	refs.value = Util.label({
		name = "Value",
		parent = b,
		size = UDim2.fromOffset(RECT.w - textX - 16, 36),
		position = UDim2.fromOffset(textX, 46),
		textSize = VALUE_TEXT,
		color = Theme.Colors.TextDim,
		align = Enum.TextXAlignment.Left,
		zIndex = 3,
	})
	-- barre « ce que j'ai / ce qu'il faut » sous la ligne 2 (forme, pas seulement la couleur)
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.BackgroundColor3 = Theme.Colors.Background
	track.BackgroundTransparency = 0.15
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(RECT.w - textX - 16, BAR_H)
	track.Position = UDim2.fromOffset(textX, RECT.h - BAR_H - 6)
	track.ZIndex = 3
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = track
	track.Parent = b
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill
	fill.Parent = track
	refs.fill = fill
	b.Activated:Connect(onClick)
	seenFn = onSeen
	b:SetAttribute("Ready", false)
	b:SetAttribute("Target", "")
	b.Visible = false
	place(b)
	b.Parent = parent
	chip = b
	return b
end

-- =============================================================================================
-- Mises à jour (boucle du HUD)
-- =============================================================================================

-- Instantané accepté : la cible n'est recalculée que si ce qui la change a changé
function NextBuy.onSnapshot(snap: Types.UpgradeSnapshot)
	if NextBuy.triggerChanged(lastTrigger, snap) then
		dirty = true
	end
end

local function evaluate(now: number, snap: Types.UpgradeSnapshot)
	dirty = false
	evalAt = now
	evaluations += 1
	lastTrigger = snap
	local ok, t = pcall(UpgradeAdvisor.next, snap, {})
	current = if ok and type(t) == "table" then t else nil
	shownVersion = -1 -- textes à refaire
	wasReady = nil
end

-- Un pas : évaluation (≤ NextChipHz par seconde, seulement après un déclencheur), textes, barre,
-- pulsation au passage à « Prêt » ; `show` = ce que le HUD permet. Rend vrai si la puce est montrée.
function NextBuy.step(now: number, snap: Types.UpgradeSnapshot?, show: boolean): boolean
	local b = chip
	if b == nil then
		return false
	end
	if snap == nil then
		if b.Visible then
			b.Visible = false
		end
		return false
	end
	if dirty and (now - evalAt >= PERIOD or now < evalAt) then
		evaluate(now, snap)
	end
	local t = current
	local visible = show and t ~= nil
	if b.Visible ~= visible then
		b.Visible = visible
	end
	if t == nil then
		return false
	end
	if snap.version ~= shownVersion then
		shownVersion = snap.version
		local have = math.max(0, snap.coins)
		local ready = have >= t.price
		local kind = Upgrades.ById[t.id] and Upgrades.ById[t.id].icon or nil
		if refs.icon and Icons.kindOf(refs.icon) ~= kind then
			Icons.draw(refs.icon, kind)
		end
		setText("name", refs.name, Util.t("upgrades.short." .. t.id))
		setText("level", refs.level, Util.t("common.level", { n = Format.count(NextBuy.shownLevel(t)) }))
		local value = refs.value :: TextLabel
		if ready then
			setText("value", value, Util.t("hud.nextBuy.ready"))
			value.TextColor3 = GOLD
		else
			setText(
				"value",
				value,
				Util.t("common.ratio", { have = Util.big(have), need = Util.big(t.price) })
			)
			value.TextColor3 = Theme.Colors.TextDim
		end
		local k = if t.price > 0 then math.clamp(have / t.price, 0, 1) else 1
		local fill = refs.fill :: Frame
		fill.Size = UDim2.fromScale(k, 1)
		fill.BackgroundColor3 = if ready then GOLD else BAR_FILL
		b:SetAttribute("Ready", ready)
		b:SetAttribute("Target", t.id)
		-- une seule pulsation au passage à « Prêt » (jamais en boucle ; rien en Mouvement réduit)
		if ready and wasReady == false and visible and not Juice.reducedMotion() then
			Juice.pulse(b, 1.08)
		end
		wasReady = ready
	end
	if visible and not seen then
		seen = true
		b:SetAttribute("Seen", true)
		local fn = seenFn
		if fn then
			pcall(fn)
		end
	end
	return visible
end

-- Première vraie apparition déjà vue (UiSeen envoyé par le HUD une fois par session)
function NextBuy.seen(): boolean
	return seen
end

-- Textes recalculés (langue changée)
function NextBuy.refreshTexts()
	table.clear(texts)
	shownVersion = -1
end

-- Cible montrée (specs)
function NextBuy.target(): Target?
	return current
end

-- Nombre d'évaluations d'UpgradeAdvisor.next (specs : ≤ NextChipHz par seconde)
function NextBuy.evaluations(): number
	return evaluations
end

-- Puce construite (specs, disposition)
function NextBuy.frame(): TextButton?
	return chip
end

return NextBuy
