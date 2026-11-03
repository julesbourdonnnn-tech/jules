--!nocheck
-- Static_TextSet (lot B1, docs/04 §27.7, §27.8 règle 8 ; GDD v2.0 §10.8 règles 8 et 9) : lecture du
-- code du client (src/client), commentaires retirés.
--   1. UI/Text est le SEUL écrivain de `.Text` : aucune affectation `x.Text =`, `x["Text"] =`, ni
--      champ `Text = …` d'un constructeur d'instance (Create) ailleurs ;
--   2. une seule politique de taille : jamais `TextScaled = true` ; `TextSize`, `UITextSizeConstraint`,
--      `MinTextSize` et `MaxTextSize` posés par UI/Text seulement ;
--   3. dans UI/* (hors UI/Text et UI/Format) : aucun `tostring(…)` (sauf d'une erreur attrapée),
--      aucun `string.format(…)`, aucune chaîne interpolée (`…{x}…`, sauf un message d'erreur), aucun
--      `..` collé à un nombre évident (chiffre, `#liste`, `math.…`) : chaque nombre affiché passe par
--      UN formateur (UI/Format, ou Logic/BigNumber pour les montants). Les noms d'instance et les clés
--      faits d'un indice (« Row » .. i) ne sont pas des textes montrés et restent permis.
-- Le détecteur lui-même est vérifié sur des exemples (il doit voir chaque faute).
local fs = require("@lune/fs")

local ROOT = "src/client"
local TEXT_MODULE = "src/client/UI/Text.luau"
local FORMAT_MODULE = "src/client/UI/Format.luau"

-- variables d'erreur attrapée (pcall) : leur tostring n'est pas un nombre affiché
local ERROR_VARS = { err = true, result = true }

local function files(dir, out)
	out = out or {}
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			files(full, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, full)
		end
	end
	table.sort(out)
	return out
end

-- Code sans commentaires ni contenu des chaînes (« "a.Text = b" » n'est pas une affectation) : lecture
-- caractère par caractère (chaînes "…", '…', `…`, longues [[…]] / [=[…]=], commentaires -- et
-- --[[…]]) ; garde les numéros de ligne
local function codeLines(source: string): { string }
	local out = {}
	local buf = {}
	local i, n = 1, #source
	local function flush()
		table.insert(out, table.concat(buf))
		table.clear(buf)
	end
	local function longClose(at: number): (string?, number)
		local eqs = string.match(source, "^%[(=*)%[", at)
		if eqs == nil then
			return nil, at
		end
		return "]" .. eqs .. "]", at + #eqs + 2
	end
	while i <= n do
		local ch = string.sub(source, i, i)
		if ch == "\n" then
			flush()
			i += 1
		elseif string.sub(source, i, i + 1) == "--" then
			local close, after = longClose(i + 2)
			if close then
				local e = string.find(source, close, after, true) or n
				for _ in string.gmatch(string.sub(source, i, e), "\n") do
					flush()
				end
				i = e + #close
			else
				local e = string.find(source, "\n", i, true) or (n + 1)
				i = e
			end
		elseif ch == "[" and longClose(i) then
			local close, after = longClose(i)
			local e = string.find(source, close :: string, after, true) or n
			table.insert(buf, '""')
			for _ in string.gmatch(string.sub(source, i, e), "\n") do
				flush()
			end
			i = e + #(close :: string)
		elseif ch == '"' or ch == "'" or ch == "`" then
			local j = i + 1
			while j <= n do
				local c = string.sub(source, j, j)
				if c == "\\" then
					j += 2
				elseif c == ch or c == "\n" then
					break
				else
					j += 1
				end
			end
			table.insert(buf, ch .. ch)
			i = j + 1
		else
			table.insert(buf, ch)
			i += 1
		end
	end
	flush()
	return out
end

-- Fautes d'une source (liste de « ligne : raison ») ; `inUi` : règles des nombres (UI/*)
local function scan(source: string, opts): { string }
	local out = {}
	local raw = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(raw, line)
	end
	for i, l in codeLines(source) do
		local function bad(why)
			table.insert(out, string.format("%d : %s — %s", i, why, string.gsub(raw[i] or "", "^%s+", "")))
		end
		if not opts.textModule then
			if
				string.find(l, "[%w_%]%)]%.Text%s*=[^=]")
				or string.find(raw[i] or "", '%[%s*"Text"%s*%]%s*=[^=]')
			then
				bad("affectation de .Text hors de UI/Text")
			end
			local field = string.match(l, "^%s*Text%s*=%s*(.-)%s*,?%s*$")
			if field and not string.match(field, "^Color3") and not string.match(field, "^Theme%.Colors") then
				bad("champ Text = d'un constructeur hors de UI/Text")
			end
			if string.find(l, "TextScaled%s*=%s*true") then
				bad("TextScaled = true")
			end
			if string.find(l, "[%w_%]%)]%.TextScaled%s*=[^=]") then
				bad("TextScaled posé hors de UI/Text")
			end
			if string.find(l, "[%w_%]%)]%.TextSize%s*=[^=]") or string.find(l, "^%s*TextSize%s*=") then
				bad("TextSize posé hors de UI/Text")
			end
			if
				not string.match(l, "^%s*Theme%.") -- constante de la charte (Theme.MinTextSize), pas une instance
				and (
					string.find(l, "[%w_%]%)]%.M[ai][xn]TextSize%s*=[^=]")
					or string.find(l, "^%s*M[ai][xn]TextSize%s*=")
				)
			then
				bad("MinTextSize / MaxTextSize posé hors de UI/Text")
			end
			if
				string.find(raw[i] or "", '"UITextSizeConstraint"', 1, true)
				and string.find(raw[i] or "", "new%(")
			then
				bad("UITextSizeConstraint créée hors de UI/Text")
			end
			if string.find(raw[i] or "", 'Create%(%s*"UITextSizeConstraint"') then
				bad("UITextSizeConstraint créée hors de UI/Text")
			end
		end
		if opts.inUi and not opts.textModule and not opts.formatModule then
			if string.find(l, "string%.format%s*%(") or string.find(l, ":format%s*%(") then
				bad("string.format hors de UI/Format")
			end
			for arg in string.gmatch(l, "tostring%s*%(%s*([^%)]*)%)") do
				if not ERROR_VARS[arg] then
					bad("tostring hors de UI/Format")
				end
			end
			if string.find(l, "tostring%s*%(%s*$") then
				bad("tostring hors de UI/Format")
			end
			local rawLine = raw[i] or ""
			-- message d'erreur : error( / warn( sur la ligne ou la précédente (appel sur plusieurs lignes)
			local prevLine = raw[i - 1] or ""
			local inError = string.find(rawLine, "error%(")
				or string.find(rawLine, "warn%(")
				or string.find(prevLine, "error%(%s*$")
				or string.find(prevLine, "warn%(%s*$")
			if string.find(rawLine, "`[^`]*{[^`]*`") and not inError then
				local code = string.gsub(rawLine, "%-%-.*$", "")
				if string.find(code, "`[^`]*{[^`]*`") then
					bad("chaîne interpolée hors de UI/Format")
				end
			end
			if
				string.find(l, "%.%.%s*#")
				or string.find(l, "%.%.%s*math%.")
				or string.find(l, "%.%.%s*%-?%d")
				or string.find(l, "%f[%w_]%d+%.?%d*%s*%.%.")
			then
				bad("nombre collé par « .. » hors de UI/Format")
			end
		end
	end
	return out
end

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Static_TextSet › le détecteur voit chaque faute (exemples)", function()
		local cases = {
			{ 'label.Text = "x"', false, true },
			{ "frame.Label.Text = name", false, true },
			{ "(sideTitle :: TextLabel).Text = title", false, true },
			{ 'label["Text"] = v', false, true },
			{ "\tText = text,", false, true },
			{ "label.TextScaled = true", false, true },
			{ "\t\tTextScaled = true,", false, true },
			{ "label.TextSize = 40", false, true },
			{ "c.MaxTextSize = 40", false, true },
			{ 'local c = Instance.new("UITextSizeConstraint")', false, true },
			{ 'x = string.format("%d", n)', true, true },
			{ "x = tostring(n)", true, true },
			{ 'x = "#" .. #list', true, true },
			{ 'x = "♥" .. math.floor(n)', true, true },
			{ 'x = 3 .. " s"', true, true },
			{ "x = `{n} s`", true, true },
			-- permis
			{ "Text = Color3.fromRGB(255, 255, 255),", false, false },
			{ "\tText = Theme.Colors.Text,", false, false },
			{ "if label.Text ~= text then", false, false },
			{ "Text.raw(label, Format.count(n))", true, false },
			{ "Widgets.raise(where, tostring(err))", true, false },
			{ '-- label.Text = "commentaire"', true, false },
			{ 'local s = "label.Text = x"', true, false },
			{ 'name = "Row" .. i,', true, false },
			{ "error(`[Root] après {n} s`, 2)", true, false },
			{ "error(\n\t`[Root] après {n} s`,\n\t2\n)", true, false },
			{ "Theme.MinTextSize = 28", false, false },
		}
		for _, c in cases do
			it((if c[3] then "voit : " else "laisse : ") .. c[1], function()
				local found = scan(c[1], { inUi = c[2] })
				expect(#found > 0).toBe(c[3])
			end)
		end
	end)

	describe("Static_TextSet › code du client", function()
		local all = files(ROOT)
		it("au moins 50 fichiers lus, UI/Text et UI/Format présents", function()
			expect(#all >= 50).toBe(true)
			expect(fs.isFile(TEXT_MODULE)).toBe(true)
			expect(fs.isFile(FORMAT_MODULE)).toBe(true)
		end)

		it(
			"UI/Text est le seul écrivain de .Text (aucune affectation, aucun champ Text de constructeur)",
			function()
				local bad = {}
				for _, path in all do
					if path ~= TEXT_MODULE then
						for _, f in scan(fs.readFile(path), { inUi = false }) do
							if
								string.find(f, "Text", 1, true) and not string.find(f, "TextSize", 1, true)
							then
								if
									string.find(f, ".Text hors", 1, true)
									or string.find(f, "champ Text", 1, true)
								then
									table.insert(bad, path .. ":" .. f)
								end
							end
						end
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
			end
		)

		it(
			"une seule politique de taille : aucun TextScaled, TextSize ni contrainte posés hors de UI/Text",
			function()
				local bad = {}
				for _, path in all do
					if path ~= TEXT_MODULE then
						for _, f in scan(fs.readFile(path), { inUi = false }) do
							if
								string.find(f, "TextScaled", 1, true)
								or string.find(f, "TextSize", 1, true)
								or string.find(f, "UITextSizeConstraint", 1, true)
							then
								table.insert(bad, path .. ":" .. f)
							end
						end
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
			end
		)

		it(
			"UI/* : aucun tostring, string.format, chaîne interpolée ni « .. » d'un nombre hors de UI/Text et UI/Format",
			function()
				local bad = {}
				for _, path in all do
					if
						string.sub(path, 1, #"src/client/UI/") == "src/client/UI/"
						and path ~= TEXT_MODULE
						and path ~= FORMAT_MODULE
					then
						for _, f in scan(fs.readFile(path), { inUi = true }) do
							if
								string.find(f, "tostring", 1, true)
								or string.find(f, "string.format", 1, true)
								or string.find(f, "interpolée", 1, true)
								or string.find(f, "collé", 1, true)
							then
								table.insert(bad, path .. ":" .. f)
							end
						end
					end
				end
				expect(table.concat(bad, "\n")).toBe("")
			end
		)

		it(
			"UI/Text écrit .Text à 3 endroits seulement (texte posé, témoins cachés, témoins du TextProbe)",
			function()
				local n = 0
				for _, l in codeLines(fs.readFile(TEXT_MODULE)) do
					if string.find(l, "[%w_%]%)]%.Text%s*=[^=]") then
						n += 1
					end
				end
				-- l'écriture du texte (write), et le texte connu des témoins cachés (mesure) et visibles
				-- (panneau TextProbe)
				expect(n).toBe(3)
			end
		)
	end)
end
