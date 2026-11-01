--!nocheck
-- Manette simulée et audit « console » pour les specs (docs/07-console-ps5.md §10).
--
--   local h = Harness.new({ mode = "client", console = true })  -- PS5 : 10 pieds, manette seule
--   h:createRemotes(); h:boot()
--   Gamepad.tap(h, Enum.KeyCode.ButtonY)          -- △ : appui puis relâchement
--   Gamepad.tap(h, Enum.KeyCode.DPadDown)         -- sélection active : navigation (Layout.step)
--   Gamepad.tap(h, Enum.KeyCode.ButtonA)          -- ✕ sur l'objet sélectionné : Activated
--   Gamepad.stick(h, Enum.KeyCode.Thumbstick1, Vector2.new(0, 1))
--   expect(#Gamepad.audit(h)).toBe(0)             -- glyphes PlayStation, textes ≥ 18 px, zone sûre
--
-- Modèle d'entrée (approximation documentée du moteur Roblox) :
--   * tout appui passe le dernier type d'entrée à Gamepad1 (LastInputTypeChanged si besoin) ;
--   * sélection active (GuiService.SelectedObject) : la croix directionnelle déplace la sélection
--     (UserInputService.InputBegan avec gameProcessedEvent = true, AUCUNE action CAS) ; ✕ (ButtonA)
--     émet InputBegan / InputEnded (gameProcessedEvent = true) puis Activated au relâchement ;
--   * sinon (et pour tous les autres boutons) : InputBegan / InputEnded (gameProcessedEvent = false)
--     puis les actions ContextActionService liées à la touche, de la priorité la plus haute à la plus
--     basse (à égalité, la plus récente d'abord) ; une action qui ne renvoie pas Pass arrête la
--     propagation (Sink, ou nil comme dans Roblox).

local roblox = require("@lune/roblox")
local Layout = require("./Layout")
local Services = require("./Services")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local Gamepad = {}

Gamepad.PS_GLYPHS = Services.PS_GLYPHS
Gamepad.XBOX_GLYPHS = Services.XBOX_GLYPHS

local NAV = {
	DPadUp = "Up",
	DPadDown = "Down",
	DPadLeft = "Left",
	DPadRight = "Right",
}

-- Textes interdits sur console : lettres et noms de boutons Xbox (ButtonX est le Carré d'une
-- DualSense), noms d'énumération bruts
local XBOX_TEXTS = {
	A = true,
	B = true,
	X = true,
	Y = true,
	LB = true,
	RB = true,
	LT = true,
	RT = true,
	LS = true,
	RS = true,
	["View"] = true,
	["Menu"] = true,
}

function Gamepad.input(keyCode, state, position)
	return {
		KeyCode = keyCode,
		UserInputType = Enum.UserInputType.Gamepad1,
		UserInputState = state,
		Position = position or Vector3.zero,
		Delta = Vector3.zero,
	}
end

local function useGamepad(h)
	if h.lastInputType ~= Enum.UserInputType.Gamepad1 then
		h.lastInputType = Enum.UserInputType.Gamepad1
		h.game.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
	end
end

-- Liaisons ContextActionService qui écoutent cette touche, dans l'ordre de traitement
function Gamepad.bindingsFor(h, keyCode)
	local out = {}
	for name, b in h.actionBindings do
		for _, k in b.keys do
			if k == keyCode then
				table.insert(out, { name = name, binding = b })
				break
			end
		end
	end
	table.sort(out, function(a, b)
		if a.binding.priority ~= b.binding.priority then
			return a.binding.priority > b.binding.priority
		end
		return a.binding.seq > b.binding.seq
	end)
	return out
end

-- Envoie l'entrée aux actions CAS ; retourne le nom de l'action qui l'a absorbée (ou nil)
function Gamepad.dispatch(h, keyCode, state, input)
	input = input or Gamepad.input(keyCode, state)
	for _, entry in Gamepad.bindingsFor(h, keyCode) do
		-- une action peut délier les autres pendant le traitement
		if h.actionBindings[entry.name] == entry.binding then
			local result = entry.binding.fn(entry.name, state, input)
			if result ~= Enum.ContextActionResult.Pass then
				return entry.name
			end
		end
	end
	return nil
end

function Gamepad.selected(h)
	return h.game.GuiService.SelectedObject
end

-- Appui (Begin)
function Gamepad.press(h, keyCode)
	useGamepad(h)
	local uis = h.game.UserInputService
	local gs = h.game.GuiService
	local input = Gamepad.input(keyCode, Enum.UserInputState.Begin)
	local selected = gs.SelectedObject
	local dir = NAV[keyCode.Name]
	if selected ~= nil and dir ~= nil then
		uis.InputBegan:Fire(input, true)
		Layout.apply(h)
		local nxt = Layout.step(h, selected, dir)
		if nxt ~= nil then
			gs.SelectedObject = nxt
		end
		h:settle(1)
		return nil
	end
	if selected ~= nil and keyCode == Enum.KeyCode.ButtonA then
		h._padConfirm = selected
		uis.InputBegan:Fire(input, true)
		h:settle(1)
		return nil
	end
	uis.InputBegan:Fire(input, false)
	local sunk = Gamepad.dispatch(h, keyCode, Enum.UserInputState.Begin, input)
	h:settle(1)
	return sunk
end

-- Relâchement (End)
function Gamepad.release(h, keyCode)
	local uis = h.game.UserInputService
	local input = Gamepad.input(keyCode, Enum.UserInputState.End)
	if keyCode == Enum.KeyCode.ButtonA and h._padConfirm ~= nil then
		local target = h._padConfirm
		h._padConfirm = nil
		uis.InputEnded:Fire(input, true)
		if
			target:IsA("GuiButton")
			and h.game.GuiService.SelectedObject == target
			and Layout.visible(target)
		then
			target.Activated:Fire(input, 1)
		end
		h:settle(1)
		return nil
	end
	if NAV[keyCode.Name] and h.game.GuiService.SelectedObject ~= nil then
		uis.InputEnded:Fire(input, true)
		h:settle(1)
		return nil
	end
	uis.InputEnded:Fire(input, false)
	local sunk = Gamepad.dispatch(h, keyCode, Enum.UserInputState.End, input)
	h:settle(1)
	return sunk
end

-- Appui puis relâchement ; retourne l'action qui a absorbé l'appui (nil : navigation ou rien)
function Gamepad.tap(h, keyCode)
	local sunk = Gamepad.press(h, keyCode)
	Gamepad.release(h, keyCode)
	return sunk
end

-- Stick (Thumbstick1 / Thumbstick2) : état Change, position x/y dans [-1, 1] (y vers le haut)
function Gamepad.stick(h, keyCode, v)
	useGamepad(h)
	local input = Gamepad.input(keyCode, Enum.UserInputState.Change, Vector3.new(v.X, v.Y, 0))
	h.game.UserInputService.InputChanged:Fire(input, false)
	local sunk = Gamepad.dispatch(h, keyCode, Enum.UserInputState.Change, input)
	h:settle(1)
	return sunk
end

-- Audit console ----------------------------------------------------------------------------------

local function trimmed(text)
	return (string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", ""))
end

local function maxTextSize(label)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	return if c and c.MaxTextSize then c.MaxTextSize else 100
end

local function minTextSize(label)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	return if c and c.MinTextSize then c.MinTextSize else 1
end

-- Largeur estimée d'un texte en em (FredokaOne, estimation par classe de caractère : étroits
-- « i l t r . , » et espace, larges « m w M W », capitales, chiffres, autres minuscules ; hors ASCII
-- (accents, ≈, —, ✦…) un peu plus large que la moyenne)
local NARROW = "iljtfrI!.,:;'|()[]"
local WIDE = "mwMW@%"
local LINE_EM = 1.2

local function textEm(text)
	local em = 0
	for _, code in utf8.codes(text) do
		if code > 127 then
			em += 0.6
		else
			local ch = string.char(code)
			if ch == " " then
				em += 0.28
			elseif string.find(NARROW, ch, 1, true) then
				em += 0.3
			elseif string.find(WIDE, ch, 1, true) then
				em += 0.78
			elseif ch >= "A" and ch <= "Z" then
				em += 0.64
			elseif ch >= "0" and ch <= "9" then
				em += 0.56
			else
				em += 0.52
			end
		end
	end
	return em
end

-- Plus grande taille (px de référence) à laquelle un texte de largeur `em` tient dans w × h : une
-- ligne sans retour à la ligne, sinon ceil(em × s / w) lignes de 1,2 × s dans la hauteur
local function fittingSize(em, w, h, wrapped, cap)
	if em <= 0 or w <= 0 or h <= 0 then
		return cap
	end
	local single = math.min(cap, h, w / em)
	if not wrapped then
		return single
	end
	local best = single
	local s = math.floor(math.min(cap, h))
	while s > best do
		local lines = math.ceil(em * s / w)
		if lines * LINE_EM * s <= h + 0.01 then
			best = s
			break
		end
		s -= 1
	end
	return best
end

-- Objet hors de l'écran ou masqué par un cadre défilant / ClipsDescendants : ignoré
local function onScreen(r, h)
	if r.clip ~= nil then
		local c = r.clip
		if r.x + r.w <= c.x or r.x >= c.x + c.w or r.y + r.h <= c.y or r.y >= c.y + c.h then
			return false
		end
	end
	return r.x + r.w > 0 and r.y + r.h > 0 and r.x < h.viewport.X and r.y < h.viewport.Y
end

local function decorative(obj)
	local cur = obj
	while cur ~= nil and not cur:IsA("LayerCollector") do
		if cur:GetAttribute("Decorative") == true then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- Écarts aux règles console des interfaces visibles (docs/07-console-ps5.md §3, §5, §10) :
--   * glyphes (attribut « GlyphKey » posé par UI/Glyph) : image PlayStation sur console ;
--   * aucun texte visible égal à une lettre ou un nom de bouton Xbox (A, B, X, Y, LB, RB…) ;
--   * texte lisible : ≥ minText px de référence (défaut 18 ; TextScaled : la plus grande taille où
--     le texte tient en largeur ET en hauteur, retours à la ligne compris (TextWrapped), bornée par
--     MaxTextSize, largeur estimée par classe de caractère) ; « texte coupé » quand il ne tient pas
--     même à MinTextSize ≥ minText (le moteur le tronquerait) ;
--   * zone sûre TV : chaque objet sélectionnable et chaque texte dans les `margin` (défaut 5 %) de
--     chaque bord.
-- Un objet (ou un ancêtre) avec l'attribut « Decorative » = true est ignoré (texte décoratif).
-- opts : { root: Instance?, minText: number?, margin: number?, safeArea: boolean? }
function Gamepad.audit(h, opts)
	opts = opts or {}
	Layout.apply(h)
	local root = opts.root or h.localPlayer:FindFirstChildOfClass("PlayerGui")
	local minText = opts.minText or 18
	local margin = opts.margin or 0.05
	local issues = {}
	local vx, vy = h.viewport.X, h.viewport.Y
	local safe = { x0 = vx * margin, y0 = vy * margin, x1 = vx * (1 - margin), y1 = vy * (1 - margin) }
	local list = root:GetDescendants()
	if root:IsA("GuiObject") then
		table.insert(list, 1, root)
	end
	for _, obj in list do
		local r = Layout.rect(obj)
		if
			r ~= nil
			and obj:IsA("GuiObject")
			and Layout.visible(obj)
			and onScreen(r, h)
			and not decorative(obj)
		then
			local name = Layout.name(obj)
			local key = obj:GetAttribute("GlyphKey")
			if h.console and type(key) == "string" and key ~= "" and string.sub(key, 1, 6) == "Button" then
				local image = obj:FindFirstChild("Image")
				local path = if image and image.Visible ~= false then image.Image else nil
				if type(path) ~= "string" or string.find(path, Gamepad.PS_GLYPHS, 1, true) ~= 1 then
					table.insert(issues, `glyphe non PlayStation : {name} ({key} → {tostring(path)})`)
				end
			end
			local isText = obj.ClassName == "TextLabel"
				or obj.ClassName == "TextButton"
				or obj.ClassName == "TextBox"
			local text = if isText then trimmed(obj.Text) else ""
			if isText and text ~= "" and obj.TextTransparency ~= 1 then
				if h.console and XBOX_TEXTS[text] then
					table.insert(issues, `texte de bouton Xbox sur console : {name} « {text} »`)
				end
				local size
				local cut = false
				if obj.TextScaled then
					-- taille que le moteur choisit : la plus grande où le texte tient en largeur ET en
					-- hauteur (bornée par MaxTextSize) ; sous MinTextSize, le texte est coupé
					local k = math.max(r.k, 1e-6)
					local fit =
						fittingSize(textEm(text), r.w / k, r.h / k, obj.TextWrapped == true, maxTextSize(obj))
					local floor = minTextSize(obj)
					size = math.max(fit, floor)
					cut = fit < floor - 0.01 and floor >= minText - 0.01
				else
					size = obj.TextSize or 14
				end
				if cut then
					table.insert(
						issues,
						`texte coupé : {name} « {text} » (tient à {string.format("%.1f", size)} px seulement)`
					)
				elseif size < minText - 0.01 then
					table.insert(
						issues,
						`texte trop petit : {name} « {text} » ({string.format("%.1f", size)} px)`
					)
				end
			end
			if opts.safeArea ~= false and (Layout.selectable(obj) or (isText and text ~= "")) then
				if
					r.x < safe.x0 - 0.5
					or r.y < safe.y0 - 0.5
					or r.x + r.w > safe.x1 + 0.5
					or r.y + r.h > safe.y1 + 0.5
				then
					table.insert(
						issues,
						string.format(
							"hors de la zone sûre TV : %s (%d, %d, %d × %d)",
							name,
							math.floor(r.x),
							math.floor(r.y),
							math.floor(r.w),
							math.floor(r.h)
						)
					)
				end
			end
		end
	end
	table.sort(issues)
	return issues
end

return Gamepad
