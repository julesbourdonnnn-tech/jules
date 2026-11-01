--!strict
-- DiagnosticsService (paquet meta) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Diagnostics en ligne (GDD §12.11) : erreurs et avertissements du serveur (ScriptContext.Error,
-- LogService.MessageOut), erreurs attrapées par les pcall du tick et des handlers, états fermés par
-- leur délai, réparations de profil, et rapports des clients (ReportError : validés, plafonnés, noms
-- nettoyés une 2e fois). Par clé : nombre, joueurs touchés, première et dernière fois, 3 exemples ;
-- totaux du jour dans un DataStore à part toutes les 5 min (UpdateAsync, DiagRules.mergeDaily) ;
-- analytique ServerError / ClientError une fois par clé et par 5 min. Panneau des administrateurs
-- seulement (Data/Admins, vérifié à chaque demande ; silence pour les autres ; DiagnosticsSnapshot
-- « bonjour » tab 0 envoyé aux administrateurs à PlayerReady : le panneau devient visible). Premier service :
-- attach() est appelé par Main.server juste après son require. Remotes : ReportError,
-- RequestDiagnostics, SetInputType ; DiagnosticsSnapshot. Clés : aucune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

export type Device = { kind: number, tenFoot: boolean }
export type Totals = { errors: number, warnings: number, timedOut: number, keys: number }

local DiagnosticsService = {}

-- Branche ScriptContext.Error et LogService.MessageOut au plus tôt (stub : ne fait rien)
function DiagnosticsService.attach()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function DiagnosticsService.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function DiagnosticsService.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Tick : écriture groupée des totaux du jour (task.spawn, jamais de yield dans le tick)
function DiagnosticsService.step(now: number)
	local _ = { now }
	error("TODO(meta): DiagnosticsService.step")
end

-- Compte un rapport (déjà normalisé côté client, renormalisé ici)
function DiagnosticsService.report(
	source: "server" | "client",
	kind: number,
	text: string,
	trace: string,
	ctx: string,
	player: Player?
)
	local _ = { source, kind, text, trace, ctx, player }
	error("TODO(meta): DiagnosticsService.report")
end

-- Erreur attrapée par un pcall du serveur (étape du tick, handler)
function DiagnosticsService.reportCaught(where: string, err: any)
	local _ = { where, err }
	error("TODO(meta): DiagnosticsService.reportCaught")
end

-- État fermé par son délai alors qu'il aurait dû finir seul (StateTimedOut)
function DiagnosticsService.stateTimedOut(name: string, player: Player?)
	local _ = { name, player }
	error("TODO(meta): DiagnosticsService.stateTimedOut")
end

-- Paquet du panneau (≤ 20 Ko)
function DiagnosticsService.snapshot(tab: number): Types.DiagnosticsSnapshot
	local _ = { tab }
	error("TODO(meta): DiagnosticsService.snapshot")
end

-- UserId dans Data/Admins
function DiagnosticsService.isAdmin(player: Player): boolean
	local _ = { player }
	error("TODO(meta): DiagnosticsService.isAdmin")
end

-- Appareil et entrée déclarés (analytique seulement)
function DiagnosticsService.device(player: Player): Device
	local _ = { player }
	error("TODO(meta): DiagnosticsService.device")
end

-- Totaux de la session (tests : règle zéro trace)
function DiagnosticsService.counts(): Totals
	error("TODO(meta): DiagnosticsService.counts")
end

return DiagnosticsService
