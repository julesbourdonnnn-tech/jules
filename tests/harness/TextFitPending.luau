--!nocheck
-- Cas « en attente » de tests/specs/TextFit_all.spec.luau (liste : tests/fixtures/TextFitPending).
-- Un problème = « <type> <chemin de l'objet> » dans un cas « <appareil>-<langue>/<écran> ». La spec
-- saute (avec un message clair) un écran dont TOUS les problèmes sont déjà dans la liste ; elle
-- échoue sur un problème NOUVEAU, et sur un problème de la liste qui a disparu (réparé : retirer sa
-- ligne pour que la spec le vérifie désormais).
--   Pending.relevant(issue)            → le problème compte-t-il pour la spec ?
--   Pending.entry(issue)               → « type chemin »
--   Pending.compare(issues, listed)    → nouveaux, réparés (listes de « type chemin »)
--   Pending.render(issuesByCase)       → source Luau de la liste (outil : capture -- --pending)
--   Pending.summary(issues)            → résumé d'une ligne

local Pending = {}

-- Types vérifiés (Screens.textIssues) : texte qui ne tient pas, « … » qui cache un nombre ou un mot
-- entier, TextScaled sous le minimum lisible (18 px de référence × échelle de Root), mot coupé,
-- ponctuation seule sur sa ligne, clé de traduction, variable, « ? », texte jamais posé.
Pending.KINDS = {
	overflow = true,
	truncated = true,
	small = true,
	splitWord = true,
	orphan = true,
	unitSplit = true,
	numberFormat = true,
	rawKey = true,
	placeholder = true,
	question = true,
	defaultText = true,
}

local ORDER = {
	"overflow",
	"truncated",
	"small",
	"splitWord",
	"orphan",
	"unitSplit",
	"numberFormat",
	"rawKey",
	"placeholder",
	"question",
	"defaultText",
}

function Pending.relevant(issue): boolean
	if not Pending.KINDS[issue.kind] then
		return false
	end
	-- taille fixe trop petite : relevée par le rapport (smallFixed) et Gamepad.audit, pas ici
	if issue.kind == "small" and not issue.scaled then
		return false
	end
	return true
end

function Pending.entry(issue): string
	return issue.kind .. " " .. issue.path
end

-- Problèmes pertinents d'un écran, sans doublon, triés
function Pending.entries(issues): { string }
	local seen, out = {}, {}
	for _, issue in issues do
		if Pending.relevant(issue) then
			local e = Pending.entry(issue)
			if not seen[e] then
				seen[e] = true
				table.insert(out, e)
			end
		end
	end
	table.sort(out)
	return out
end

-- (nouveaux, réparés) par rapport à la liste `listed` (nil : aucun cas en attente)
function Pending.compare(issues, listed): ({ string }, { string })
	local now = Pending.entries(issues)
	local inList = {}
	for _, e in listed or {} do
		inList[e] = true
	end
	local present = {}
	local fresh = {}
	for _, e in now do
		present[e] = true
		if not inList[e] then
			table.insert(fresh, e)
		end
	end
	local fixed = {}
	for _, e in listed or {} do
		if not present[e] then
			table.insert(fixed, e)
		end
	end
	return fresh, fixed
end

local function shortPath(path)
	local parts = string.split(path, ".")
	return table.concat({ table.unpack(parts, math.max(1, #parts - 1)) }, ".")
end

function Pending.summary(issues): string
	local byKind = {}
	for _, issue in issues do
		if Pending.relevant(issue) then
			byKind[issue.kind] = byKind[issue.kind] or {}
			table.insert(byKind[issue.kind], issue)
		end
	end
	local parts = {}
	for _, kind in ORDER do
		local list = byKind[kind]
		if list then
			local first = list[1]
			table.insert(
				parts,
				string.format(
					"%d × %s (%s « %s »%s)",
					#list,
					kind,
					shortPath(first.path),
					string.sub(first.text or "", 1, 40),
					if kind == "small" then string.format(" %.1f px", first.realSize or 0) else ""
				)
			)
		end
	end
	return table.concat(parts, " ; ")
end

local function escape(s: string): string
	return (string.gsub(s, '[\\"]', "\\%0"))
end

function Pending.render(issuesByCase): string
	local keys = {}
	for key, issues in issuesByCase do
		if #Pending.entries(issues) > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local lines = {
		"--!nocheck",
		"-- Cas EN ATTENTE de tests/specs/TextFit_all.spec.luau : problèmes de texte présents aujourd'hui.",
		"-- Généré par « lune run tools/screens/capture -- --out <dossier> --pending » (tools/screens/README.md).",
		"-- Un problème réparé : retirer sa ligne (la spec échoue tant qu'il reste listé, puis le vérifie).",
		"-- Ne jamais ajouter de ligne pour masquer une régression : corriger l'interface.",
		"return {",
	}
	for _, key in keys do
		table.insert(lines, string.format('\t["%s"] = {', escape(key)))
		for _, e in Pending.entries(issuesByCase[key]) do
			table.insert(lines, string.format('\t\t"%s",', escape(e)))
		end
		table.insert(lines, "\t},")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

return Pending
