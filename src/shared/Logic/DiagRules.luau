--!strict
-- DiagRules (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Normalisation et plafonds des rapports d'erreur (GDD §12.11) : chiffres → « # », chemins
-- Players.<nom> et noms d'affichage → « <joueur> », UTF-8 valide, longueurs bornées (message 300,
-- pile 600, contexte 120, clé 64). Clé d'une erreur = hachage court du texte normalisé et du script.
-- Fusion pure des totaux du jour (UpdateAsync partagé, 50 clés les plus fréquentes, < 4 Ko).

local Types = require(script.Parent.Parent.Types)
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

-- Texte normalisé (aucun nom, aucun nombre)
function DiagRules.normalize(text: string, names: { string }?): string
	local _ = { text, names }
	error("TODO(logic): DiagRules.normalize")
end

-- Coupe sans casser un caractère UTF-8 ; remplace l'UTF-8 invalide
function DiagRules.truncate(s: string, max: number): string
	local _ = { s, max }
	error("TODO(logic): DiagRules.truncate")
end

-- Chaîne UTF-8 valide
function DiagRules.validUtf8(s: string): boolean
	local _ = { s }
	error("TODO(logic): DiagRules.validUtf8")
end

-- Clé courte (8 caractères hexadécimaux)
function DiagRules.key(normalized: string, source: string): string
	local _ = { normalized, source }
	error("TODO(logic): DiagRules.key")
end

-- Contexte compact (appareil, entrée, résolution, langue, version, étape, fenêtre, événement), ≤ 120
function DiagRules.context(fields: { [string]: any }): string
	local _ = { fields }
	error("TODO(logic): DiagRules.context")
end

-- Totaux du jour fusionnés, bornés (transformation d'UpdateAsync)
function DiagRules.mergeDaily(current: { [string]: any }?, entries: { Types.DiagEntry }): { [string]: any }
	local _ = { current, entries }
	error("TODO(logic): DiagRules.mergeDaily")
end

return DiagRules
