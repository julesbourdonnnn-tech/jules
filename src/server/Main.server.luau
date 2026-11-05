--!strict
-- Point d'entrée serveur : branche DiagnosticsService (attach), crée les remotes (Net.setup), puis
-- Init() de tous les services dans l'ordre, puis Start() de tous les services. Chaque appel est isolé (xpcall) : une erreur est signalée par warn
-- et le service suivant démarre quand même (leçon de Comet Conga : un Start en panne en amont
-- empêchait le tick de jeu de démarrer, serveur ouvert mais injouable).
-- Crochet « attach » (docs/04 §5.1) : un module qui le définit l'exécute JUSTE APRÈS son require,
-- avant le require des suivants. Réservé à DiagnosticsService, premier de la liste, qui doit voir
-- les erreurs de tout le démarrage, Net.setup() compris (GDD §12.3, §12.11 ; contrat v1.2, remarque
-- A29) : Net.setup() est appelé juste après le require et l'attach du PREMIER module de la liste
-- (DiagnosticsService ne touche à aucun remote avant son Init), et avant le require des autres.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Services = script.Parent.Services

-- Ordre explicite (docs/04 §5.1) : un service n'appelle directement que ceux listés AVANT lui ; vers
-- le haut, il passe par Server/Signals ou par un crochet enregistré. ChaseService, qui porte le tick
-- de 10 Hz, est le dernier.
local ORDER = {
	"DiagnosticsService", -- meta : erreurs du serveur et des clients (attach au plus tôt)
	"DataService", -- socle : profils, verrou de session, réplication
	"MonetizationService", -- socle : reçus idempotents, passes
	"WorldService", -- world : construit Wobbleton et les 16 ranchs
	"RanchService", -- ranch : attribution, placement, intrus, Pot, dalles, état public
	"EconomyService", -- ranch : pièces, croissance cumulée, dalles, boosts, Fame, hors ligne
	"SquishyService", -- ranch : collection, presser, Cuve, Bassin, portage, monture
	"QuestService", -- meta : accueil, objectifs, Nourrir Plop, Squishydex, statistiques
	"CommunityService", -- meta : amis, pet-sitting, emotes, bannières, réglages
	"EventService", -- chase : EventClock, MEGA, jauge, Lune, spectacles, fêtes, LiveOps
	"RushService", -- chase : mode Rush / Cozy, clôtures, boops, protections
	"SplorchService", -- chase : Grand Splorch, cadeaux, applaudissements
	"HelperService", -- v2.0 (lot A3, INT-V2-ORDER) : Plopettes, stépées par le tick de ChaseService
	"ProductService", -- ranch : effets des passes et produits
	"LeaderboardService", -- meta : classements de la semaine, statue
	"ChaseService", -- chase : tick de 10 Hz, créatures, bonds, captures, anti-triche
}

local function run(name: string, phase: string, fn: () -> ())
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn(`[Server] {name} {phase}:`, err)
	end
end

local modules: { [string]: any } = {}
for index, name in ORDER do
	run(name, "require", function()
		modules[name] = require(Services:FindFirstChild(name) :: ModuleScript) :: any
	end)
	local m = modules[name]
	if m and type(m.attach) == "function" then
		run(name, "attach", m.attach)
	end
	if index == 1 then
		-- remotes créés une fois Diagnostics branché, avant tout autre service (même si le premier
		-- module est en panne : run isole l'erreur, la suite démarre)
		Net.setup()
	end
end
for _, name in ORDER do
	local m = modules[name]
	if m and m.Init then
		run(name, "Init", m.Init)
	end
end
for _, name in ORDER do
	local m = modules[name]
	if m and m.Start then
		run(name, "Start", m.Start)
	end
end
