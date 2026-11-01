--!strict
-- DiagRules (paquet logic, docs/04 §11.2, §12.1).
-- Normalisation et plafonds des rapports d'erreur (GDD §12.11) : chiffres → « # », chemins
-- Players.<nom> et noms d'affichage → « <joueur> », UTF-8 valide, longueurs bornées (message 300,
-- pile 600, contexte 120, clé 64). Clé d'une erreur = hachage court du texte normalisé et du script.
-- Fusion pure des totaux du jour (UpdateAsync partagé, 50 clés les plus fréquentes, < 4 Ko).

-- Bibliothèques gardées en local : appels rapides, aussi dans l'environnement injecté du harnais
local type, typeof, math, string, table = type, typeof, math, string, table

local Types = require(script.Parent.Parent.Types)
local Hash = require(script.Parent.Hash)

-- Plafonds (GDD §12.11)
local LIMITS = {
	Message = 300,
	Trace = 600,
	Context = 120,
	Key = 64,
	PerSession = 30, -- rapports d'un client par session
	PerKeyWindow = 60, -- s : 1 rapport par clé et par minute
	MaxKeys = 200, -- clés différentes par serveur, puis « autres »
	Samples = 3,
	SnapshotBytes = 20000,
	DailyTop = 50,
	DailyBytes = 4000,
	FlushInterval = 300, -- s : écriture des totaux du jour
}

local DiagRules = {}

DiagRules.Limits = LIMITS

local PLAYER = "<joueur>"
local REPLACEMENT = "?" -- octet UTF-8 invalide remplacé (1 octet : longueur prévisible)
local INPUT_MAX = 4000 -- octets lus au plus dans un texte reçu (le reste est jeté avant tout calcul)
local CONTEXT_VALUE_MAX = 24
-- Champs du contexte, dans l'ordre d'écriture, et leur clé courte
local CONTEXT_FIELDS = {
	{ "device", "dev" },
	{ "input", "in" },
	{ "resolution", "res" },
	{ "lang", "lang" },
	{ "version", "ver" },
	{ "step", "step" },
	{ "window", "win" },
	{ "event", "ev" },
}

-- Longueur d'une séquence UTF-8 valide (RFC 3629 : ni surlongue, ni substitut, ≤ U+10FFFF) qui
-- commence à l'octet i, ou 0 si elle est invalide
local function sequenceLength(s: string, i: number): number
	local c = string.byte(s, i)
	if c == nil then
		return 0
	end
	if c < 0x80 then
		return 1
	end
	local n, min
	if c >= 0xC2 and c <= 0xDF then
		n, min = 2, 0x80
	elseif c >= 0xE0 and c <= 0xEF then
		n, min = 3, 0x800
	elseif c >= 0xF0 and c <= 0xF4 then
		n, min = 4, 0x10000
	else
		return 0
	end
	if i + n - 1 > #s then
		return 0
	end
	local code = c % (if n == 2 then 0x20 elseif n == 3 then 0x10 else 0x08)
	for k = 1, n - 1 do
		local b = string.byte(s, i + k)
		if b == nil or b < 0x80 or b > 0xBF then
			return 0
		end
		code = code * 64 + (b - 0x80)
	end
	if code < min or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then
		return 0
	end
	return n
end

-- Remplace chaque octet invalide et coupe à `max` octets sans casser un caractère
local function sanitize(s: string, max: number): string
	local out = {}
	local used = 0
	local i = 1
	local len = #s
	while i <= len do
		local n = sequenceLength(s, i)
		local piece
		if n == 0 then
			piece = REPLACEMENT
			n = 1
		else
			piece = string.sub(s, i, i + n - 1)
		end
		if used + #piece > max then
			break
		end
		table.insert(out, piece)
		used += #piece
		i += n
	end
	return table.concat(out)
end

-- Échappe les caractères magiques d'un motif Lua
local function escapePattern(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Texte normalisé (aucun nom, aucun nombre)
function DiagRules.normalize(text: string, names: { string }?): string
	if type(text) ~= "string" then
		return ""
	end
	local s = sanitize(string.sub(text, 1, INPUT_MAX), INPUT_MAX)
	-- marque provisoire (octet nul, retiré du texte d'abord) : un nom court ne peut jamais réécrire
	-- l'intérieur d'un « <joueur> » déjà posé
	s = string.gsub(s, "\0", "")
	local mark = "\0"
	-- chemins Players.<nom> (et Players["nom"])
	s = string.gsub(s, "Players%.[^%s%.%:%,%)%]]+", "Players." .. mark)
	s = string.gsub(s, 'Players%["[^"]*"%]', "Players." .. mark)
	-- noms et noms d'affichage fournis (les plus longs d'abord : un nom qui en contient un autre)
	if type(names) == "table" then
		local list = {}
		for _, name in names do
			if type(name) == "string" and #name >= 2 and not string.find(name, "\0", 1, true) then
				table.insert(list, name)
			end
		end
		table.sort(list, function(a, b)
			if #a ~= #b then
				return #a > #b
			end
			return a < b
		end)
		for _, name in list do
			s = string.gsub(s, escapePattern(name), mark)
		end
	end
	-- nombres : chaque suite de chiffres devient « # »
	s = string.gsub(s, "%d+", "#")
	s = string.gsub(s, mark, PLAYER)
	return s
end

-- Coupe sans casser un caractère UTF-8 ; remplace l'UTF-8 invalide
function DiagRules.truncate(s: string, max: number): string
	if type(s) ~= "string" or type(max) ~= "number" or max ~= max or max < 1 then
		return ""
	end
	local limit = if max == math.huge then #s else math.floor(max)
	return sanitize(s, limit)
end

-- Chaîne UTF-8 valide
function DiagRules.validUtf8(s: string): boolean
	if type(s) ~= "string" then
		return false
	end
	local i = 1
	while i <= #s do
		local n = sequenceLength(s, i)
		if n == 0 then
			return false
		end
		i += n
	end
	return true
end

-- Clé courte (8 caractères hexadécimaux)
function DiagRules.key(normalized: string, source: string): string
	local a = if type(normalized) == "string" then normalized else ""
	local b = if type(source) == "string" then source else ""
	return string.format("%08x", Hash.u32(Hash.string(a), Hash.string(b)))
end

-- Valeur de contexte sûre : texte court, sans séparateur ni caractère de contrôle
local function contextValue(v: any): string
	local t = typeof(v)
	local text
	if t == "string" then
		text = v
	elseif t == "number" then
		if v ~= v or math.abs(v) == math.huge then
			text = "0"
		elseif v % 1 == 0 and math.abs(v) < 1e15 then
			text = string.format("%d", v)
		else
			text = string.format("%.2f", v)
		end
	elseif t == "boolean" then
		text = if v then "1" else "0"
	elseif t == "Vector2" then
		text = string.format("%dx%d", math.floor(v.X), math.floor(v.Y))
	else
		return ""
	end
	text = sanitize(string.sub(text, 1, 200), 200)
	text = string.gsub(text, "[%c;=]", "")
	return DiagRules.truncate(text, CONTEXT_VALUE_MAX)
end

-- Contexte compact (appareil, entrée, résolution, langue, version, étape, fenêtre, événement), ≤ 120
function DiagRules.context(fields: { [string]: any }): string
	if type(fields) ~= "table" then
		return ""
	end
	local parts = {}
	for _, field in CONTEXT_FIELDS do
		local value = fields[field[1]]
		if value ~= nil then
			local text = contextValue(value)
			if text ~= "" then
				table.insert(parts, field[2] .. "=" .. text)
			end
		end
	end
	return DiagRules.truncate(table.concat(parts, ";"), LIMITS.Context)
end

-- Nombre entier sûr ≥ 0
local function count(x: any): number
	if type(x) ~= "number" or x ~= x or x < 0 or x == math.huge then
		return 0
	end
	return math.floor(x)
end

-- Entrée lisible (champs sûrs, texte borné) ou nil
local function cleanEntry(e: any): Types.DiagEntry?
	if type(e) ~= "table" or type(e.key) ~= "string" or e.key == "" then
		return nil
	end
	return {
		key = DiagRules.truncate(e.key, LIMITS.Key),
		kind = if e.kind == 2 then 2 else 1,
		text = DiagRules.truncate(if type(e.text) == "string" then e.text else "", 80),
		source = if e.source == "client" then "client" else "server",
		count = count(e.count),
		players = count(e.players),
		first = count(e.first),
		last = count(e.last),
	}
end

-- Taille estimée d'une entrée une fois encodée (JSON du DataStore)
local function entryBytes(e: Types.DiagEntry): number
	return #e.key + #e.text + 96
end

-- Totaux du jour fusionnés, bornés (transformation d'UpdateAsync) : { entries = { DiagEntry } triées
-- par nombre décroissant (50 au plus, < 4 Ko), others = occurrences des clés écartées }
function DiagRules.mergeDaily(current: { [string]: any }?, entries: { Types.DiagEntry }): { [string]: any }
	local merged: { [string]: Types.DiagEntry } = {}
	local others = 0
	local cur: any = if type(current) == "table" then current else {}
	others += count(cur.others)

	local function add(raw: any)
		local e = cleanEntry(raw)
		if e == nil then
			return
		end
		local existing = merged[e.key]
		if existing == nil then
			merged[e.key] = e
		else
			existing.count += e.count
			existing.players += e.players
			if e.first > 0 and (existing.first == 0 or e.first < existing.first) then
				existing.first = e.first
			end
			existing.last = math.max(existing.last, e.last)
			if existing.text == "" then
				existing.text = e.text
			end
		end
	end

	if type(cur.entries) == "table" then
		for _, e in cur.entries do
			add(e)
		end
	end
	if type(entries) == "table" then
		for _, e in entries do
			add(e)
		end
	end

	local list = {}
	for _, e in merged do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)

	local kept = {}
	local bytes = 32
	for _, e in list do
		local size = entryBytes(e)
		if #kept < LIMITS.DailyTop and bytes + size < LIMITS.DailyBytes then
			table.insert(kept, e)
			bytes += size
		else
			others += e.count
		end
	end
	return { entries = kept, others = others }
end

return DiagRules
