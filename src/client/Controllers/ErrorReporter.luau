--!strict
-- ErrorReporter (paquet meta) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Erreurs et avertissements du client (GDD §12.11) : ScriptContext.Error et LogService.MessageOut,
-- sauvetages du focus (FocusRescued), WaitForChild arrivés à leur délai. Normalisés par DiagRules
-- (noms remplacés), 1 par clé et par minute, 30 par session, envoyés par ReportError avec un petit
-- contexte (appareil, entrée, résolution, langue, version, étape, fenêtre ouverte, événement).
-- Interrupteur du serveur (WorldStateController.event().features.diagnostics, false : aucun envoi ;
-- jamais Config/Features lu côté client). File bornée (10) envoyée au débit d'Intents.ReportError :
-- une cascade au démarrage n'est pas perdue. Celebrate "testError" (administrateurs) : erreur
-- volontaire du client (test manuel M17). Premier module du client : attach() est appelé par
-- Main.client juste après son require ; le contexte est lu au moment de l'envoi.
-- Remotes : ReportError, SetInputType (envoi) ; Celebrate (sorte "testError").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)

local ErrorReporter = {}

-- Branche les sources d'erreurs au plus tôt (stub : ne fait rien)
function ErrorReporter.attach()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function ErrorReporter.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function ErrorReporter.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Rapport interne (FocusRescued, délai de WaitForChild)
function ErrorReporter.report(kind: number, text: string, trace: string?)
	local _ = { kind, text, trace }
	error("TODO(meta): ErrorReporter.report")
end

-- Met à jour un champ du contexte (fenêtre ouverte, événement en cours)
function ErrorReporter.noteContext(key: string, value: string)
	local _ = { key, value }
	error("TODO(meta): ErrorReporter.noteContext")
end

-- Rapports envoyés dans la session (tests)
function ErrorReporter.sent(): number
	error("TODO(meta): ErrorReporter.sent")
end

-- Rapports de ce client dans la session (onglet « Mon client » du panneau Diagnostics), les plus
-- récents en dernier, bornés (comptes par clé)
function ErrorReporter.entries(): { Types.DiagEntry }
	error("TODO(meta): ErrorReporter.entries")
end

-- Mesures du client pour l'onglet « Mon client » : images par seconde, mémoire (Stats), ping,
-- instances, connexions suivies, qualité réduite ou non
function ErrorReporter.stats(): {
	fps: number,
	memoryMb: number,
	pingMs: number,
	instances: number,
	connections: number,
	reduced: boolean,
}
	error("TODO(meta): ErrorReporter.stats")
end

return ErrorReporter
