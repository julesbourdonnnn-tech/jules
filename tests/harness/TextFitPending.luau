--!nocheck
-- Liste des cas « en attente » de tests/specs/TextFit_all.spec.luau (tests/fixtures/TextFitPending) :
-- un cas = « <appareil>-<langue>/<écran> » dont les textes ne tiennent pas AUJOURD'HUI. La spec les
-- saute avec un message clair ; les correcteurs retirent une ligne quand le cas est réparé.
--   Pending.render(issuesByCase) → source Luau du fichier (outil : capture -- --pending)
--   Pending.summary(issues)      → résumé d'une ligne (« 3 × small (…) ; 1 × overflow (…) »)

local Pending = {}

local ORDER = {
	"overflow",
	"truncated",
	"splitWord",
	"small",
	"rawKey",
	"placeholder",
	"question",
	"defaultText",
}

local function shortPath(path)
	-- les deux derniers segments suffisent à retrouver l'objet
	local parts = string.split(path, ".")
	return table.concat({ table.unpack(parts, math.max(1, #parts - 1)) }, ".")
end

function Pending.summary(issues): string
	local byKind = {}
	for _, issue in issues do
		byKind[issue.kind] = byKind[issue.kind] or {}
		table.insert(byKind[issue.kind], issue)
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
					string.sub(first.text, 1, 40),
					if kind == "small" then string.format(" %.1f px", first.realSize) else ""
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
		if #issues > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local lines = {
		"--!nocheck",
		"-- Cas EN ATTENTE de tests/specs/TextFit_all.spec.luau : textes qui ne tiennent pas aujourd'hui.",
		"-- Généré par « lune run tools/screens/capture -- --out <dossier> --pending » (tools/screens/README.md).",
		"-- Un cas réparé : retirer sa ligne (la spec le vérifie alors). Ne jamais en ajouter pour masquer",
		"-- une régression : corriger l'interface.",
		"return {",
	}
	for _, key in keys do
		table.insert(lines, string.format('\t["%s"] = "%s",', escape(key), escape(Pending.summary(issuesByCase[key]))))
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n"
end

return Pending
