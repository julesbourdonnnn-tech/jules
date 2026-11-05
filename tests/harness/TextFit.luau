--!nocheck
-- Mesure du texte hors moteur, avec les vraies largeurs des polices (tests/harness/TextMetrics,
-- généré par tools/screens/metrics.mjs) et les règles de texte de Roblox (repris de l'outil
-- d'écrans de Comet Conga ; propriétés lues par tests/harness/EngineProps) :
--   * TextSize = hauteur d'UNE ligne (px de mise en page, avant UIScale) ; LineHeight multiplie
--     l'écart entre les lignes ;
--   * TextWrapped : retour à la ligne aux espaces (jamais à l'espace insécable U+00A0 / U+202F) ;
--     un mot plus large que la boîte est coupé entre deux caractères (« mot coupé ») ; « \n » force
--     une ligne ;
--   * TextScaled : la plus grande taille ENTIÈRE ≤ 100, bornée par UITextSizeConstraint
--     (MinTextSize / MaxTextSize), à laquelle le texte tient dans la boîte (en largeur ET en
--     hauteur, retours à la ligne compris) ; sous MinTextSize le texte est dessiné à MinTextSize et
--     déborde (« texte coupé »). Documentation Roblox (TextLabel.TextScaled) : TextScaled active
--     IMPLICITEMENT TextWrapped (SCALED_WRAPS) ;
--   * TextTruncate AtEnd : ce qui ne tient pas est remplacé par « … » ;
--   * UIPadding du libellé retiré de la boîte ; les tailles réelles (px d'écran) = taille × k
--     (UIScale cumulés, tests/harness/Layout).
-- Approximations : crénage ignoré (somme des avances), repli des caractères inconnus sur la
-- largeur moyenne a-z, RichText réduit à son texte brut pour la mesure.
--
--   TextFit.width(text, font, size)                → largeur (px de mise en page)
--   TextFit.lines(text, font, size, boxWidth)      → { lignes }, motCoupé
--   TextFit.scaledSize(text, font, w, h, wrapped, min, max, lineHeight) → taille, tient
--   TextFit.layout(obj)                            → détails (taille retenue, lignes, débords…)
--   TextFit.fits(obj, opts?)                       → ok, détails (détails.issues : liste de textes)
--   TextFit.measureAuto(obj, maxWidth)             → largeur, hauteur (AutomaticSize d'un texte)

local Metrics = require("./TextMetrics")
local Props = require("./EngineProps")
local Layout = require("./Layout")

local TextFit = {}

-- Raise a Squishy : 28 px de référence 1920 × 1080 (Config/Console.MinTextSize = Layout.Text.Min,
-- GDD §10.1), × échelle de UI/Root (1 en 1080p, 2 en 4K, 0,667 en 720p)
TextFit.MIN_READABLE = 28
-- TextScaled implique les retours à la ligne (documentation Roblox de TextLabel.TextScaled ; dans
-- Studio, cocher TextScaled coche TextWrapped)
TextFit.SCALED_WRAPS = true
TextFit.ELLIPSIS = "…"

local DEFAULT_KEY = "GothamSSm@400"
local WEIGHTS = {
	Thin = 100,
	ExtraLight = 200,
	Light = 300,
	Regular = 400,
	Medium = 500,
	SemiBold = 600,
	Bold = 700,
	ExtraBold = 800,
	Heavy = 900,
}

local NBSP = 0xA0
local NNBSP = 0x202F

-- Clé TextMetrics d'une police : Font Roblox, nom d'énumération ou clé déjà résolue
function TextFit.fontKey(font): string
	if type(font) == "string" then
		if Metrics.fonts[font] then
			return font
		end
		local base = string.match(font, "([%w]+)%.json$") or font
		return TextFit.fontKey({ Family = base .. ".json", Weight = "Regular" })
	end
	if font == nil then
		return DEFAULT_KEY
	end
	local family = font.Family or ""
	local base = string.match(family, "([%w]+)%.json$") or "GothamSSm"
	local weight = font.Weight
	local w = 400
	if type(weight) == "number" then
		w = weight
	elseif weight ~= nil then
		w = WEIGHTS[weight.Name or tostring(weight)] or 400
	end
	local exact = base .. "@" .. w
	if Metrics.fonts[exact] then
		return exact
	end
	local best, bestDiff = nil, math.huge
	for key in Metrics.fonts do
		local b, kw = string.match(key, "^(%w+)@(%d+)$")
		if b == base then
			local diff = math.abs(tonumber(kw) - w)
			if diff < bestDiff then
				best, bestDiff = key, diff
			end
		end
	end
	if best then
		return best
	end
	return if w >= 600 then "GothamSSm@700" else DEFAULT_KEY
end

local function metricsFor(font)
	return Metrics.fonts[TextFit.fontKey(font)] or Metrics.fonts[DEFAULT_KEY]
end

-- Largeur d'un caractère (code point) à la taille 100
local function advance(m, cp: number): number
	local w = m.widths[cp]
	if w ~= nil then
		return w
	end
	if cp == 0xFE0F or cp == 0xFE0E or cp == 0x200D or cp == 0x200B then
		return 0
	end
	if cp >= 0x1F000 then
		return m.widths[0x1F43E] or m.avg * 2.4 -- emoji : largeur d'un emoji mesuré
	end
	return m.avg
end

-- Texte brut d'un texte RichText (balises retirées, entités décodées)
function TextFit.plain(text: string): string
	local s = string.gsub(text, "<br%s*/?>", "\n")
	s = string.gsub(s, "<[^<>]->", "")
	s = string.gsub(s, "&lt;", "<")
	s = string.gsub(s, "&gt;", ">")
	s = string.gsub(s, "&quot;", '"')
	s = string.gsub(s, "&apos;", "'")
	s = string.gsub(s, "&amp;", "&")
	return s
end

local function codes(text: string): { number }
	local out = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(text) do
			table.insert(out, cp)
		end
	end)
	if not ok then
		out = {}
		for i = 1, #text do
			table.insert(out, string.byte(text, i))
		end
	end
	return out
end

local function sumWidth(m, cps, i0, i1, size): number
	local w = 0
	for i = i0, i1 do
		w += advance(m, cps[i])
	end
	return w * size / Metrics.size
end

function TextFit.width(text: string, font, size: number): number
	local m = metricsFor(font)
	local cps = codes(text)
	return sumWidth(m, cps, 1, #cps, size)
end

local function isBreakSpace(cp: number): boolean
	return cp == 32 or cp == 9
end

-- Coupe un paragraphe (sans « \n ») en lignes de largeur ≤ boxWidth ; retourne les lignes (chaînes),
-- leurs largeurs et si un mot a dû être coupé entre deux caractères
local function wrapParagraph(m, cps, size, boxWidth, out, widths)
	local split = false
	local n = #cps
	local scale = size / Metrics.size
	local function str(i0, i1)
		if i1 < i0 then
			return ""
		end
		local parts = table.create(i1 - i0 + 1)
		for i = i0, i1 do
			parts[i - i0 + 1] = utf8.char(cps[i])
		end
		return table.concat(parts)
	end
	local lineStart, lineEnd = nil, nil -- indices de la ligne en cours (sans espaces de fin)
	local lineW = 0
	local i = 1
	while i <= n do
		-- espaces avant le mot
		local s0 = i
		while i <= n and isBreakSpace(cps[i]) do
			i += 1
		end
		local spaceW = 0
		for k = s0, i - 1 do
			spaceW += advance(m, cps[k]) * scale
		end
		if i > n then
			break
		end
		local w0 = i
		while i <= n and not isBreakSpace(cps[i]) do
			i += 1
		end
		local w1 = i - 1
		local wordW = sumWidth(m, cps, w0, w1, size)
		if lineStart ~= nil and lineW + spaceW + wordW <= boxWidth + 1e-6 then
			lineEnd = w1
			lineW += spaceW + wordW
		else
			if lineStart ~= nil then
				table.insert(out, str(lineStart, lineEnd))
				table.insert(widths, lineW)
				lineStart, lineW = nil, 0
			end
			if wordW <= boxWidth + 1e-6 then
				lineStart, lineEnd, lineW = w0, w1, wordW
			else
				-- mot plus large que la boîte : coupé entre deux caractères
				split = true
				local c0 = w0
				local acc = 0
				for k = w0, w1 do
					local a = advance(m, cps[k]) * scale
					if acc + a > boxWidth + 1e-6 and k > c0 then
						table.insert(out, str(c0, k - 1))
						table.insert(widths, acc)
						c0, acc = k, 0
					end
					acc += a
				end
				lineStart, lineEnd, lineW = c0, w1, acc
			end
		end
	end
	if lineStart ~= nil then
		table.insert(out, str(lineStart, lineEnd))
		table.insert(widths, lineW)
	end
	-- paragraphe vide (ou fait d'espaces) : TextFit.lines ajoute une ligne vide
	return split
end

-- Lignes affichées : boxWidth = nil → aucun retour automatique (seulement « \n »)
function TextFit.lines(text: string, font, size: number, boxWidth: number?): ({ string }, boolean, { number })
	local m = metricsFor(font)
	local out, widths = {}, {}
	local split = false
	for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
		local cps = codes(paragraph)
		if boxWidth == nil then
			table.insert(out, paragraph)
			table.insert(widths, sumWidth(m, cps, 1, #cps, size))
		else
			local before = #out
			if wrapParagraph(m, cps, size, math.max(boxWidth, 0), out, widths) then
				split = true
			end
			if #out == before then
				table.insert(out, "")
				table.insert(widths, 0)
			end
		end
	end
	return out, split, widths
end

local function blockOf(text, font, size, w, wrapped, lineHeight)
	local lines, split, widths = TextFit.lines(text, font, size, if wrapped then w else nil)
	local maxW = 0
	for _, lw in widths do
		maxW = math.max(maxW, lw)
	end
	local height = #lines * size * (lineHeight or 1)
	return { lines = lines, widths = widths, width = maxW, height = height, split = split }
end

local function fitsBox(block, w, h)
	return block.width <= w + 0.01 and block.height <= h + 0.01
end

-- Taille TextScaled (entière) : la plus grande taille de [min, max] (max ≤ 100) qui tient dans
-- w × h ; recherche dichotomique (comme le moteur) ; (taille, tient)
function TextFit.scaledSize(text, font, w, h, wrapped, minSize, maxSize, lineHeight): (number, boolean)
	local top = math.floor(math.min(maxSize or 100, 100))
	local bottom = math.max(1, math.ceil(minSize or 1))
	if top < bottom then
		top = bottom
	end
	if text == "" then
		return top, true
	end
	if not fitsBox(blockOf(text, font, bottom, w, wrapped, lineHeight), w, h) then
		return bottom, false
	end
	local lo, hi = bottom, top
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if fitsBox(blockOf(text, font, mid, w, wrapped, lineHeight), w, h) then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo, true
end

local function isText(obj): boolean
	return obj.ClassName == "TextLabel" or obj.ClassName == "TextButton" or obj.ClassName == "TextBox"
end
TextFit.isText = isText

local function sizeConstraint(obj)
	local c = obj:FindFirstChildOfClass("UITextSizeConstraint")
	if c == nil then
		return 1, 100
	end
	return Props.get(c, "MinTextSize") or 1, Props.get(c, "MaxTextSize") or 100
end

local function padding(obj, w, h)
	local p = obj:FindFirstChildOfClass("UIPadding")
	if p == nil then
		return 0, 0, 0, 0
	end
	local function u(v, dim)
		return if v then dim * v.Scale + v.Offset else 0
	end
	return u(Props.get(p, "PaddingLeft"), w),
		u(Props.get(p, "PaddingTop"), h),
		u(Props.get(p, "PaddingRight"), w),
		u(Props.get(p, "PaddingBottom"), h)
end

-- Texte affiché par l'objet (TextBox vide : texte indicatif), brut si RichText
function TextFit.displayText(obj): (string, boolean)
	local text = Props.get(obj, "Text") or ""
	local placeholder = false
	if obj.ClassName == "TextBox" and text == "" then
		text = Props.get(obj, "PlaceholderText") or ""
		placeholder = true
	end
	if Props.get(obj, "RichText") == true then
		text = TextFit.plain(text)
	end
	return text, placeholder
end

local function decorative(obj): boolean
	local cur = obj
	while cur ~= nil and not cur:IsA("LayerCollector") do
		if cur:GetAttribute("Decorative") == true then
			return true
		end
		cur = cur.Parent
	end
	return false
end
TextFit.decorative = decorative

-- Rendu du texte d'un objet dans sa boîte : rect = Layout.rect(obj) (px d'écran, k = px d'écran
-- par px de mise en page) ou { w, h, k } fourni
function TextFit.layout(obj, rect)
	rect = rect or Layout.rect(obj)
	if rect == nil then
		return nil
	end
	local k = math.max(rect.k or 1, 1e-6)
	local bw, bh = rect.w / k, rect.h / k
	local pl, pt, pr, pb = padding(obj, bw, bh)
	local w, h = math.max(0, bw - pl - pr), math.max(0, bh - pt - pb)
	local text = TextFit.displayText(obj)
	local font = Props.get(obj, "FontFace")
	local scaled = Props.get(obj, "TextScaled") == true
	local wrapped = Props.get(obj, "TextWrapped") == true or (scaled and TextFit.SCALED_WRAPS)
	local lineHeight = Props.get(obj, "LineHeight") or 1
	local minS, maxS = sizeConstraint(obj)
	local size, fitsScaled
	if scaled then
		size, fitsScaled = TextFit.scaledSize(text, font, w, h, wrapped, minS, maxS, lineHeight)
	else
		size = Props.get(obj, "TextSize") or 8
		-- UITextSizeConstraint borne aussi une taille fixe
		size = math.clamp(size, minS, math.max(minS, maxS))
		fitsScaled = true
	end
	local block = blockOf(text, font, size, w, wrapped, lineHeight)
	local truncate = Props.get(obj, "TextTruncate")
	local truncated, hidden = false, ""
	local overflowX = math.max(0, block.width - w)
	local overflowY = math.max(0, block.height - h)
	if truncate ~= nil and truncate.Name ~= "None" and (overflowX > 0.01 or overflowY > 0.01) then
		truncated = true
		-- lignes entières qui tiennent en hauteur ; la dernière perd sa fin au profit de « … »
		local fitLines = math.max(1, math.floor((h + 0.01) / (size * lineHeight)))
		local keep = {}
		for i = 1, math.min(fitLines, #block.lines) do
			keep[i] = block.lines[i]
		end
		local hiddenParts = {}
		for i = fitLines + 1, #block.lines do
			table.insert(hiddenParts, block.lines[i])
		end
		local last = keep[#keep] or ""
		local ell = TextFit.width(TextFit.ELLIPSIS, font, size)
		local cps = codes(last)
		local cut = #cps
		while cut > 0 and TextFit.width(utf8.char(table.unpack(cps, 1, cut)), font, size) + ell > w + 0.01 do
			cut -= 1
		end
		if cut < #cps then
			table.insert(hiddenParts, 1, utf8.char(table.unpack(cps, cut + 1, #cps)))
		end
		keep[#keep] = (if cut > 0 then utf8.char(table.unpack(cps, 1, cut)) else "") .. TextFit.ELLIPSIS
		hidden = table.concat(hiddenParts, " ")
		block.lines = keep
		overflowX, overflowY = 0, 0
	end
	return {
		text = text,
		font = TextFit.fontKey(font),
		scaled = scaled,
		wrapped = wrapped,
		size = size, -- px de mise en page
		realSize = size * k, -- px d'écran
		k = k,
		minSize = minS,
		maxSize = maxS,
		fitsScaled = fitsScaled,
		lines = block.lines,
		lineCount = #block.lines,
		textWidth = block.width,
		textHeight = block.height,
		boxW = w,
		boxH = h,
		pad = { pl, pt, pr, pb }, -- UIPadding du libellé (px de mise en page)
		overflowX = overflowX,
		overflowY = overflowY,
		splitWord = block.split,
		truncated = truncated,
		hidden = hidden,
		decorative = decorative(obj),
	}
end

-- Ligne sans lettre ni chiffre (« ! », « ? », « ★ », « · »…) : un signe resté seul après un retour
-- à la ligne (lettres accentuées du français : octet de tête UTF-8 0xC3 ou 0xC5)
function TextFit.onlyPunctuation(line: string): boolean
	return string.find(line, "[%w\195\197]") == nil
end

-- Partie cachée par « … » : un mot ENTIER (au moins 2 lettres) au-delà de la fin du mot coupé ?
-- (couper seulement la fin d'un nom trop long est toléré ; cacher un mot entier ne l'est pas)
function TextFit.hidesWord(hidden: string): string?
	local rest = string.match(hidden, "^%S*%s+(.*)$") -- fin du mot coupé retirée
	if rest == nil then
		return nil
	end
	for word in string.gmatch(rest, "%S+") do
		local letters = 0
		for _ in string.gmatch(word, "[%a\128-\255]") do
			letters += 1
		end
		if letters >= 2 then
			return word
		end
	end
	return nil
end

-- Ligne qui commence par une unité (s, min, h, j, %, K, M, B, Qa…, pièces, px) suivie d'une fin de mot ;
-- « sur » aussi : « 1 sur 1 000 000 000 » ne se coupe jamais après le premier nombre (revue de
-- l'outil : grand tampon « SECRET … · 1 » / « sur 1 000 000 000 »)
-- « sur » / « in » : « 1 sur N » et « 1 in N » des cotes (relecture B1 : « in » manquait, le tampon
-- anglais « … · 1 » / « in 1.00B » passait ; même liste que tools/screens/renderer.js, Review_B1 › 8)
local UNITS = {
	"s",
	"min",
	"h",
	"j",
	"%",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"px",
	"sur",
	"in",
}
TextFit.UNITS = UNITS

-- Noms d'événements en capitales, toujours sur une seule ligne (GDD : noms propres de l'univers)
TextFit.BRAND_NAMES = { { "BOOP", "RUSH" }, { "MEGA", "SQUISH" } }

-- Ligne faite d'un nombre seul (chiffres, séparateurs de milliers, ponctuation finale) : « 1 »,
-- « 1 000 », « 14 ! »
function TextFit.onlyNumber(line: string): boolean
	if not string.find(line, "%d") then
		return false
	end
	local rest = string.gsub(line, "\226\128\175", "") -- espace fine insécable
	rest = string.gsub(rest, "\194\160", "") -- espace insécable
	rest = string.gsub(rest, "[%d%s,%.!%?]", "")
	return rest == ""
end
function TextFit.startsWithUnit(line: string): boolean
	for _, u in UNITS do
		if string.sub(line, 1, #u) == u then
			local nextCh = string.sub(line, #u + 1, #u + 1)
			if nextCh == "" or string.find(nextCh, "[%s%.,;:!%?%)/]") then
				return true
			end
		end
	end
	return false
end

-- Débordement vertical toléré : l'intérieur d'une ligne (au-dessus des capitales et sous les
-- jambages) peut dépasser sans qu'aucun trait ne sorte de la boîte
local function verticalSlack(size: number): number
	return math.max(1, 0.2 * size)
end

-- Le texte de obj tient-il ? (ok, détails) ; détails.issues : { { kind, message } }
-- opts : { minReadable: number? (px de référence), rootScale: number? (UIScale de Root : seuil
-- réel = minReadable × rootScale ; défaut : k de l'objet) }
function TextFit.fits(obj, opts)
	opts = opts or {}
	local d = TextFit.layout(obj)
	if d == nil then
		return true, { issues = {} }
	end
	local issues = {}
	local function add(kind, msg)
		table.insert(issues, { kind = kind, message = msg })
	end
	local text = d.text
	local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	if trimmed ~= "" then
		if not d.fitsScaled then
			add("overflow", string.format("ne tient pas même à MinTextSize %d (TextScaled)", d.minSize))
		elseif d.overflowX > 0.5 then
			add("overflow", string.format("déborde de %.0f px en largeur", d.overflowX * d.k))
		elseif d.overflowY > verticalSlack(d.size) then
			add("overflow", string.format("déborde de %.0f px en hauteur", d.overflowY * d.k))
		end
		if d.splitWord then
			add("splitWord", "mot coupé par le retour à la ligne")
		end
		if #d.lines > 1 and not TextFit.onlyPunctuation(text) then
			for _, line in d.lines do
				-- signe seul sur sa ligne (« ACCLAMER » / « ! ») : espace normale devant « ! », « · ★ »…
				if string.find(line, "%S") and TextFit.onlyPunctuation(line) then
					add("orphan", "« " .. line .. " » seul sur une ligne")
					break
				end
			end
		end
		-- unité séparée de son nombre par le retour à la ligne (« toutes les 5 » / « s. ») : l'espace
		-- entre un nombre et son unité doit être insécable
		for i = 2, #d.lines do
			local prev = string.gsub(d.lines[i - 1], "%s+$", "")
			local cur = string.gsub(d.lines[i], "^%s+", "")
			if string.find(prev, "%d$") and TextFit.startsWithUnit(cur) then
				add(
					"unitSplit",
					"« "
						.. string.sub(prev, -6)
						.. " » / « "
						.. string.sub(cur, 1, 6)
						.. " » : unité séparée de son nombre"
				)
				break
			end
		end
		-- nom d'événement en capitales coupé en deux (« Je joue au BOOP » / « RUSH ») : ces noms se
		-- lisent comme un seul mot (espace insécable dans le texte ; revue de l'outil)
		for i = 2, #d.lines do
			local prev = string.gsub(d.lines[i - 1], "%s+$", "")
			local cur = string.gsub(d.lines[i], "^%s+", "")
			for _, name in TextFit.BRAND_NAMES do
				local a, b = name[1], name[2]
				if
					string.sub(prev, -#a) == a
					and (#prev == #a or string.find(string.sub(prev, -#a - 1, -#a - 1), "[%s%p]"))
					and string.sub(cur, 1, #b) == b
				then
					add("splitWord", "nom « " .. a .. " " .. b .. " » coupé par le retour à la ligne")
				end
			end
		end
		-- nombre seul sur sa ligne, séparé du mot qui le précède (« Autocollant Jour » / « 1 ») :
		-- l'espace entre le mot et son nombre doit être insécable (revue de l'outil)
		for i = 2, #d.lines do
			local prev = string.gsub(d.lines[i - 1], "%s+$", "")
			local cur = string.gsub(string.gsub(d.lines[i], "^%s+", ""), "%s+$", "")
			if string.find(prev, "[%a\128-\255]$") and TextFit.onlyNumber(cur) then
				add(
					"unitSplit",
					"« " .. string.sub(prev, -12) .. " » / « " .. cur .. " » : nombre séparé de son mot"
				)
				break
			end
		end
		if d.truncated then
			local hiddenWord = TextFit.hidesWord(d.hidden)
			if string.find(d.hidden, "%d") then
				add("truncated", "« … » cache un nombre : « " .. d.hidden .. " »")
			elseif hiddenWord then
				add("truncated", "« … » cache le mot « " .. hiddenWord .. " »")
			end
		end
		if not d.decorative then
			local minReadable = opts.minReadable or TextFit.MIN_READABLE
			local threshold = minReadable * (opts.rootScale or d.k)
			if d.realSize < threshold - 0.01 then
				add(
					"small",
					string.format(
						"%.1f px réels < %.1f px (%d px de référence)",
						d.realSize,
						threshold,
						minReadable
					)
				)
			end
		end
	end
	d.issues = issues
	return #issues == 0, d
end

-- AutomaticSize d'un texte : taille (px de mise en page) du texte, retours à la ligne à maxWidth
-- (nil : aucune limite)
function TextFit.measureAuto(obj, maxWidth: number?): (number, number)
	local text = TextFit.displayText(obj)
	local font = Props.get(obj, "FontFace")
	local size = Props.get(obj, "TextSize") or 8
	local wrapped = (
		Props.get(obj, "TextWrapped") == true
		or (Props.get(obj, "TextScaled") == true and TextFit.SCALED_WRAPS)
	) and maxWidth ~= nil
	local block = blockOf(text, font, size, maxWidth or math.huge, wrapped, Props.get(obj, "LineHeight") or 1)
	return block.width, block.height
end

return TextFit
