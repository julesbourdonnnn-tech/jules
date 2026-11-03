--!nocheck
-- LuauScan (paquet A1) : lecture statique minimale d'un source Luau pour les specs Static_* :
-- enlève les commentaires (--…, --[[…]], --[==[…]==]) et, au choix, les chaînes ("…", '…', `…`,
-- [[…]], [==[…]==]) en les remplaçant par "" ; le reste du code est rendu tel quel (mêmes
-- caractères). Ce n'est pas un analyseur complet : il suffit à chercher un opérateur ou un accès de
-- champ hors des commentaires et des chaînes. Static_NoPow.spec vérifie son comportement sur des
-- exemples (opérateur caché dans un commentaire, une chaîne, une chaîne longue).

local LuauScan = {}

-- Les retours à la ligne d'un morceau enlevé (les numéros de ligne restent justes)
local function newlines(text: string): string
	local _, count = string.gsub(text, "\n", "")
	return string.rep("\n", count)
end

-- Source sans commentaires ; sans chaînes aussi sauf si keepStrings
function LuauScan.strip(src: string, keepStrings: boolean?): string
	local out = {}
	local i, n = 1, #src
	while i <= n do
		local s = string.find(src, "[%-\"'%[`]", i)
		if s == nil then
			table.insert(out, string.sub(src, i))
			break
		end
		table.insert(out, string.sub(src, i, s - 1))
		local c = string.sub(src, s, s)
		if c == "-" then
			if string.sub(src, s + 1, s + 1) == "-" then
				local level = string.match(src, "^%[(=*)%[", s + 2)
				if level then
					local close = "]" .. level .. "]"
					local e = string.find(src, close, s + 2, true)
					local stop = if e then e + #close - 1 else n
					table.insert(out, newlines(string.sub(src, s, stop)))
					i = stop + 1
				else
					local e = string.find(src, "\n", s, true)
					i = e or n + 1
				end
				table.insert(out, " ")
			else
				table.insert(out, "-")
				i = s + 1
			end
		elseif c == "[" then
			local level = string.match(src, "^%[(=*)%[", s)
			if level then
				local close = "]" .. level .. "]"
				local e = string.find(src, close, s, true)
				local stop = if e then e + #close - 1 else n
				local text = string.sub(src, s, stop)
				table.insert(out, if keepStrings then text else '""' .. newlines(text))
				i = stop + 1
			else
				table.insert(out, "[")
				i = s + 1
			end
		else
			-- chaîne "…", '…' ou `…` : échappements sautés ; une chaîne courte s'arrête à la fin de ligne
			local j = s + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or (d == "\n" and c ~= "`") then
					break
				else
					j += 1
				end
			end
			local text = string.sub(src, s, j)
			table.insert(out, if keepStrings then text else '""' .. newlines(text))
			i = j + 1
		end
	end
	return table.concat(out)
end

-- Numéro de ligne d'une position (messages d'erreur)
function LuauScan.lineOf(src: string, pos: number): number
	local line = 1
	for _ in string.gmatch(string.sub(src, 1, pos), "\n") do
		line += 1
	end
	return line
end

-- Fichiers .luau d'un dossier, triés (récursif)
function LuauScan.files(fs, dir: string): { string }
	local out = {}
	local function walk(d)
		for _, entry in fs.readDir(d) do
			local full = d .. "/" .. entry
			if fs.isDir(full) then
				walk(full)
			elseif string.match(entry, "%.luau$") then
				table.insert(out, full)
			end
		end
	end
	walk(dir)
	table.sort(out)
	return out
end

return LuauScan
