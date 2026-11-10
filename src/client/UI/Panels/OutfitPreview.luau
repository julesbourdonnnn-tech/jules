--!strict
-- OutfitPreview (paquet client-panels) : aperçu 3D d'une tenue (GDD §8.3, §5.4 ; docs/04 §13.6),
-- avant l'achat (depuis la Boutique) et dans la garde-robe (depuis Ranch › Style › Tenues) :
-- ViewportFrame où le squishy choisi porte la tenue et tourne (une vue fixe en Mouvement réduit),
-- choix du squishy (◀ ▶ parmi les squishies de l'enclos, du plus gros au plus petit), « Mettre »
-- (EquipOutfit(tenue, uid) si un exemplaire est libre) ou « Retirer » (EquipOutfit(tenue, nil)) quand
-- le squishy choisi la porte déjà ; tenue pas encore achetée : « Acheter » (invite de Roblox).
-- Ouvert par le navigateur avec la tenue en onglet : nav.open("OutfitPreview", "sweater").
-- Sélection par défaut : « Mettre » ; ○ revient au panneau d'où l'on vient (fenêtre empilée).
-- Le modèle vient de Render/SquishyBuilder (réserve) et lui est rendu à la fermeture.
-- v2.0 (lot B3, étape 3 ; plan B3 D17, D28 ; fichier sans propriétaire v2.0, ajouts seulement) :
--   * flèches DESSINÉES (Hud/Icons arrowRight, celle de gauche tournée de 180°) à la place de « ◀ » « ▶ »,
--     absents des polices (règle 18) ;
--   * profil v2 : les tenues de la v2.0 (Cosmetics.ListV2 sorte outfit, tenue de la semaine
--     WeeklyRotation « polkaBow ») sont acceptées, nommées par leur clé, possédées par outfits.owned ;
--     leur pièce 3D vient au lot B5 (Render/SquishyBuilder ne la dessine pas encore : aucune erreur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Cosmetics = require(Shared.Config.Cosmetics)
local Monetization = require(Shared.Config.Monetization)
local Layout = require(Shared.Config.Layout)
local Formulas = require(Shared.Logic.Formulas)
local SquishyBuilder = require(Shared.Render.SquishyBuilder)
local Clock = require(Shared.Util.Clock)

local Client = script.Parent.Parent.Parent
local Juice = require(Client.UI.Juice)
local Format = require(Client.UI.Format)
local Icons = require(Client.UI.Hud.Icons)
local MetaFlags = require(Client.UI.MetaFlags)
local Widgets = require(script.Parent.Widgets)

type Nav = { open: (panel: string, tab: string?) -> (), back: () -> () }

local OutfitPreview = {}

local ORBIT_PERIOD = 6 -- s pour un tour de caméra
local ARROW = 48 -- flèches dessinées du choix du squishy (px TV)

-- Tenues de la v2.0 (lot B3) : identifiant → clé du nom (ListV2 puis cosmétiques de la semaine)
local V2_OUTFITS: { [string]: string } = {}
for _, def in Cosmetics.ListV2 :: { any } do
	if def.kind == "outfit" and Cosmetics.ByKindId["outfit:" .. def.id] == nil then
		V2_OUTFITS[def.id] = def.key
	end
end
for _, def in Cosmetics.WeeklyRotation do
	if
		def.kind == "outfit"
		and V2_OUTFITS[def.id] == nil
		and Cosmetics.ByKindId["outfit:" .. def.id] == nil
	then
		V2_OUTFITS[def.id] = def.key
	end
end

-- Tenue connue : celles de la v1.3 ; celles de la v2.0 seulement avec un profil v2 (D10 du plan B3)
local function knownOutfit(id: any): boolean
	if type(id) ~= "string" then
		return false
	end
	if Cosmetics.ByKindId["outfit:" .. id] then
		return true
	end
	return V2_OUTFITS[id] ~= nil and MetaFlags.v2Profile()
end

local function nameKey(id: string): string
	return V2_OUTFITS[id] or ("cosmetic.outfit." .. id)
end

-- Flèche dessinée d'un bouton du choix du squishy (règle 18 : « ◀ » « ▶ » absents des polices)
local function arrow(button: GuiButton, left: boolean)
	local c = Icons.canvas(button, ARROW, { "arrowRight" }, "Arrow")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.ZIndex = button.ZIndex + 1
	if left then
		c.Rotation = 180
	end
	Icons.draw(c, "arrowRight", Widgets.Colors.Text)
end

local nav: Nav? = nil
local isOpen = false
local outfit = "plopBib"
local uids: { string } = {}
local index = 1
local viewport: ViewportFrame? = nil
local world: Instance? = nil
local camera: Camera? = nil
local handle: SquishyBuilder.Handle? = nil
local modelRadius = 4
local orbitStart = 0
local orbit: RBXScriptConnection? = nil
local labels: { [string]: TextLabel } = {}
local modelKey = "" -- squishy montré (uid, espèce, mutation, étoiles) : modèle reconstruit s'il change
local wearButton: TextButton? = nil
local buyButton: TextButton? = nil
local prevButton: TextButton? = nil
local nextButton: TextButton? = nil

local function squishies(): { [string]: any }
	return Widgets.tbl(Widgets.state("squishies"))
end

local function ownedCount(id: string): number
	local outfits = Widgets.tbl(Widgets.state("outfits"))
	return math.max(0, math.floor(Widgets.n(Widgets.tbl(outfits.owned)[id])))
end

local function wornCount(id: string): number
	local n = 0
	for _, rec in squishies() do
		if type(rec) == "table" and rec.o == id then
			n += 1
		end
	end
	return n
end

local function productFor(id: string): (string?, any)
	for key, def in Monetization.Products do
		if def.outfit == id then
			return key, def
		end
	end
	return nil, nil
end

-- Squishies de l'enclos et du Bassin, du plus gros au plus petit (porteur de la tenue en premier)
local function collectUids(): { string }
	local data = squishies()
	local growth = Widgets.state("growth")
	local G = Widgets.safe("Formulas.G", 0, Formulas.G, growth, Clock.now())
	local list: { { uid: string, size: number, wears: boolean } } = {}
	for uid, rec in data do
		if type(uid) == "string" and type(rec) == "table" and (rec.at == "pen" or rec.at == "pool") then
			local size = Widgets.safe("Formulas.sizeAt", 1, Formulas.sizeAt, rec, G)
			table.insert(list, { uid = uid, size = size, wears = rec.o == outfit })
		end
	end
	table.sort(list, function(a, b)
		if a.wears ~= b.wears then
			return a.wears
		end
		if a.size ~= b.size then
			return a.size > b.size
		end
		return a.uid < b.uid
	end)
	local out = {}
	for _, e in list do
		table.insert(out, e.uid)
	end
	return out
end

local function releaseModel()
	local h = handle
	handle = nil
	if h then
		pcall(SquishyBuilder.release, h)
	end
end

local function placeCamera(t: number)
	local cam = camera
	if cam == nil then
		return
	end
	local angle = if Juice.reducedMotion()
		then math.rad(25)
		else 2 * math.pi * (t / ORBIT_PERIOD) + math.rad(25)
	local dist = modelRadius * 3.2
	local eye = Vector3.new(math.sin(angle) * dist, modelRadius * 0.9, math.cos(angle) * dist)
	cam.CFrame = CFrame.lookAt(eye, Vector3.new(0, modelRadius * 0.15, 0))
end

local function lookKey(uid: string?): string
	local rec = if uid then squishies()[uid] else nil
	if type(rec) ~= "table" then
		return Format.key(uid)
	end
	return Format.key(uid, rec.s, rec.m, rec.st)
end

local function buildModel()
	releaseModel()
	local uid = uids[index]
	modelKey = lookKey(uid)
	local rec = if uid then squishies()[uid] else nil
	local species = if type(rec) == "table" and type(rec.s) == "number" then rec.s else 1
	local mutation = if type(rec) == "table" and type(rec.m) == "number" then rec.m else 0
	local stars = if type(rec) == "table" and type(rec.st) == "number" then rec.st else 0
	local parent = world
	if parent == nil then
		return
	end
	local ok, h = pcall(SquishyBuilder.build, {
		species = species,
		mutation = mutation,
		stars = stars,
		displayScale = 1,
		lod = 1,
		outfit = outfit,
	}, parent)
	if ok and type(h) == "table" then
		handle = h
		local body = (h :: any).body
		if typeof(body) == "Instance" and body:IsA("BasePart") then
			modelRadius = math.max(1, body.Size.Magnitude * 0.6)
		end
	end
	placeCamera(0)
end

local function refresh()
	local name = Widgets.t(nameKey(outfit))
	Widgets.setRaw(labels.title, name)
	local uid = uids[index]
	local rec = if uid then squishies()[uid] else nil
	if type(rec) == "table" then
		Widgets.setRaw(labels.who, Widgets.speciesName(rec.s))
	else
		Widgets.setText(labels.who, "common.empty")
	end
	local owned = ownedCount(outfit)
	local worn = wornCount(outfit)
	local wearsIt = type(rec) == "table" and rec.o == outfit
	Widgets.setText(labels.owned, "panel.shop.outfitOwned", { n = owned })
	local wear = wearButton :: TextButton
	local label = Widgets.buttonLabel(wear) :: TextLabel
	if wearsIt then
		Widgets.setText(label, "panel.ranch.outfitNone")
		Widgets.setDisabled(wear, false)
	else
		Widgets.setText(label, "panel.shop.wear")
		Widgets.setDisabled(wear, uid == nil or owned <= worn)
	end
	local key, def = productFor(outfit)
	local buy = buyButton :: TextButton
	buy.Visible = key ~= nil and type(def) == "table" and def.id > 0 and def.hidden ~= true
	local multiple = #uids > 1
	Widgets.setDisabled(prevButton :: TextButton, not multiple)
	Widgets.setDisabled(nextButton :: TextButton, not multiple)
end

local function step(dir: number)
	if #uids < 2 then
		return
	end
	index = ((index - 1 + dir) % #uids) + 1
	buildModel()
	refresh()
end

local function onWear()
	local uid = uids[index]
	if uid == nil then
		return
	end
	local rec = squishies()[uid]
	if type(rec) == "table" and rec.o == outfit then
		Widgets.send("EquipOutfit", outfit, nil)
	else
		Widgets.send("EquipOutfit", outfit, uid)
	end
end

-- Construit le contenu une seule fois dans le cadre du panneau
function OutfitPreview.build(container: Frame)
	local width = container.Size.X.Offset
	local height = container.Size.Y.Offset
	labels.title = Widgets.label({
		parent = container,
		name = "Outfit",
		size = UDim2.fromOffset(width - 96 - 2 * 380, 56),
		position = UDim2.new(0.5, 0, 0, 8),
		anchor = Vector2.new(0.5, 0),
		text = "",
		textSize = 48,
		color = Widgets.Colors.Gold,
	})
	local vpSize = height - 300
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Viewport"
	vp.Size = UDim2.fromOffset(vpSize, vpSize)
	vp.Position = UDim2.fromOffset(math.floor((width - vpSize) / 2), 72)
	vp.BackgroundColor3 = Widgets.Colors.Card
	vp.BackgroundTransparency = 0.2
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.ZIndex = 2
	Widgets.corner(vp, Widgets.CORNER_LARGE)
	vp.Parent = container
	viewport = vp
	local wm = Instance.new("WorldModel")
	wm.Parent = vp
	world = wm
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	camera = cam
	local rowY = 72 + vpSize + 16
	prevButton = Widgets.button({
		parent = container,
		name = "Prev",
		size = UDim2.fromOffset(120, Layout.Button.MinHeight),
		position = UDim2.fromOffset(math.floor(width / 2) - 360, rowY),
		onActivate = function()
			step(-1)
		end,
	})
	arrow(prevButton :: TextButton, true)
	labels.who = Widgets.label({
		parent = container,
		name = "Who",
		size = UDim2.fromOffset(440, Layout.Button.MinHeight),
		position = UDim2.fromOffset(math.floor(width / 2) - 220, rowY),
		text = "",
		textSize = 40,
	})
	nextButton = Widgets.button({
		parent = container,
		name = "Next",
		size = UDim2.fromOffset(120, Layout.Button.MinHeight),
		position = UDim2.fromOffset(math.floor(width / 2) + 240, rowY),
		onActivate = function()
			step(1)
		end,
	})
	arrow(nextButton :: TextButton, false)
	local actionsY = rowY + Layout.Button.MinHeight + 16
	wearButton = Widgets.button({
		parent = container,
		name = "Wear",
		size = UDim2.fromOffset(400, Layout.Button.MainHeight),
		position = UDim2.fromOffset(math.floor(width / 2) - 420, actionsY),
		key = "panel.shop.wear",
		color = Widgets.Colors.Success,
		onActivate = onWear,
	})
	buyButton = Widgets.button({
		parent = container,
		name = "Buy",
		size = UDim2.fromOffset(400, Layout.Button.MainHeight),
		position = UDim2.fromOffset(math.floor(width / 2) + 20, actionsY),
		key = "common.buy",
		color = Widgets.Colors.Pink,
		onActivate = function()
			local _, def = productFor(outfit)
			if type(def) == "table" then
				Widgets.promptPurchase("product", def.id)
			end
		end,
	})
	labels.owned = Widgets.label({
		parent = container,
		name = "Owned",
		size = UDim2.fromOffset(360, 44),
		position = UDim2.new(1, -48, 0, 14),
		anchor = Vector2.new(1, 0),
		text = "",
		textSize = 32,
		color = Widgets.Colors.TextDim,
		xAlign = Enum.TextXAlignment.Right,
	})
	Widgets.watch({ "squishies", "outfits" }, function()
		if not isOpen then
			return
		end
		-- squishy parti de l'enclos (Dodo, vendu, fusionné) pendant l'aperçu : la liste suit le profil,
		-- « Mettre » ne vise jamais un squishy qui n'est plus là ; le modèle suit le squishy montré
		local keep = uids[index]
		uids = collectUids()
		index = if keep then table.find(uids, keep) or 1 else 1
		if lookKey(uids[index]) ~= modelKey then
			buildModel()
		end
		refresh()
	end)
end

-- Affiche le panneau ; `tab` = tenue (Config/Cosmetics, kind "outfit")
function OutfitPreview.open(tab: string?)
	isOpen = true
	if knownOutfit(tab) then
		outfit = tab :: string
	end
	uids = collectUids()
	index = 1
	buildModel()
	refresh()
	orbitStart = Clock.now()
	if orbit == nil then
		orbit = RunService.Heartbeat:Connect(function()
			placeCamera(Clock.now() - orbitStart)
		end)
	end
end

-- Cache le panneau (modèle rendu à la réserve, caméra arrêtée)
function OutfitPreview.close()
	isOpen = false
	local c = orbit
	orbit = nil
	if c then
		c:Disconnect()
	end
	releaseModel()
end

-- Onglets : aucun (la tenue est passée en « onglet » par le navigateur)
function OutfitPreview.tabs(): { string }
	return {}
end

-- Change de tenue
function OutfitPreview.setTab(tab: string)
	if knownOutfit(tab) then
		outfit = tab
		if isOpen then
			uids = collectUids()
			index = 1
			buildModel()
			refresh()
		end
	end
end

function OutfitPreview.currentTab(): string
	return outfit
end

-- Sélection par défaut : « Mettre »
function OutfitPreview.defaultSelection(): GuiObject?
	return wearButton
end

-- ○ : revient au panneau d'origine (la fenêtre empilée se ferme)
function OutfitPreview.onBack(): boolean
	return false
end

-- Toujours ouvrable par le navigateur (n'est pas une entrée du menu)
function OutfitPreview.visible(): boolean
	return true
end

-- Navigateur fourni par PanelController AVANT build
function OutfitPreview.setNavigator(n: Nav)
	nav = n
end

-- Textes recalculés (langue changée)
function OutfitPreview.refresh()
	if isOpen then
		refresh()
	end
end

-- Squishy choisi et modèle construit (specs)
function OutfitPreview._state(): { outfit: string, uid: string?, model: boolean }
	local _ = nav
	local _v = viewport
	return { outfit = outfit, uid = uids[index], model = handle ~= nil }
end

return OutfitPreview
