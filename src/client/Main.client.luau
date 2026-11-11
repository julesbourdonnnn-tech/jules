--!strict
-- Point d'entrée client : Init() de tous les contrôleurs dans l'ordre, puis Start() (repris de
-- Comet Conga). Isolation des pannes : chaque require, attach, Init et Start passe par xpcall ; une
-- erreur est signalée par warn (nom du module, phase, pile) et le module suivant démarre quand même.
-- Crochet « attach » (docs/04 §13.1) : exécuté JUSTE APRÈS le require du module, avant le require
-- des suivants ; réservé à ErrorReporter, premier de la liste (erreurs de tout le démarrage).
-- L'écran de chargement (src/first/Loading.client.luau) se ferme sur l'attribut LOCAL
-- « ClientReady », posé normalement par le HUD du jeu une fois construit ; filet de sécurité
-- indépendant du HUD : l'attribut est aussi posé dès l'instantané du profil (StateController),
-- sinon un contrôleur en panne avant le HUD laisserait l'écran de chargement à vie.

local Players = game:GetService("Players")

local Client = script.Parent

-- Ordre explicite (docs/04 §13.1) : un module n'appelle directement que ceux listés avant lui ;
-- vers le haut, il écoute leurs signaux.
local ORDER: { ModuleScript } = {
	Client.Controllers.ErrorReporter, -- meta : erreurs du client → Diagnostics (attach au plus tôt)
	Client.Util.Platform, -- console, écran, entrée préférée, règle du chat
	Client.UI.Root, -- écrans, échelle TV, zone sûre, curseur de sélection
	Client.Controllers.StateController, -- miroir du profil
	Client.Controllers.AudioController, -- sons (Config/Sounds), son de navigation manette
	Client.Util.Prefs, -- réglages du profil appliqués (mouvement, sons, langue)
	Client.Controllers.WorldStateController, -- client-world : miroir des ranchs, créatures, événements
	Client.Controllers.QualityController, -- client-world : qualité adaptative
	Client.Controllers.LightingController, -- world : éclairage, ciel des événements
	Client.Controllers.RanchRenderer, -- client-world : squishies, ranchs, statue, place
	Client.Controllers.ChaseRenderer, -- client-world : créatures et poursuites
	Client.Controllers.HelperRenderer, -- v2.0 (lot B5, INT-V2-ORDER) : Plopettes dans le monde
	Client.Controllers.VFXController, -- client-world : effets des moments de jeu
	Client.Controllers.CameraController, -- client-world : travelling du Grand Splorch seulement
	Client.Controllers.PromptController, -- client-world : cible choisie par le jeu
	Client.Controllers.ChaseController, -- client-world : bond et capture
	Client.UI.FocusGuard, -- client-panels : sélection jamais perdue ni piégée
	Client.UI.Cards, -- client-hud : cartes en jeu et leur file
	Client.UI.PanelController, -- client-panels : menu et panneaux
	Client.UI.ReturnScreen, -- client-panels : écran de retour
	Client.UI.HUD, -- client-hud : HUD télé (pose ClientReady)
	Client.UI.Banners, -- client-hud : bannières
	Client.UI.ScreenFX, -- client-hud : effets d'écran, flèches de bord
	Client.UI.Prompt, -- client-hud : invites dans le monde
	Client.Controllers.InputController, -- client-hud : commandes (ContextActionService)
	Client.Controllers.OnboardingController, -- client-hud : les 5 premières minutes
}

-- Exécute fn ; une erreur est signalée (module, phase, pile) sans interrompre le démarrage
local function run(name: string, phase: string, fn: () -> ()): boolean
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn(`[Client] {name}.{phase} a échoué :`, err)
	end
	return ok
end

type Entry = { name: string, module: any }

local entries: { Entry } = {}
for _, moduleScript in ORDER do
	local name = moduleScript.Name
	local module: any = nil
	run(name, "require", function()
		module = require(moduleScript) :: any
		table.insert(entries, { name = name, module = module })
	end)
	if type(module) == "table" and type(module.attach) == "function" then
		run(name, "attach", module.attach)
	end
end

for _, phase in { "Init", "Start" } do
	for _, entry in entries do
		local m = entry.module
		local fn = if type(m) == "table" then m[phase] else nil
		if type(fn) == "function" then
			run(entry.name, phase, fn)
		end
	end
end

-- Filet de sécurité de l'écran de chargement : ClientReady dès l'instantané du profil, même si le
-- HUD (qui le pose normalement) est en panne. Attribut LOCAL et idempotent.
local function markReady()
	local player = Players.LocalPlayer
	if player and player:GetAttribute("ClientReady") ~= true then
		player:SetAttribute("ClientReady", true)
	end
end

local state: any = nil
for _, entry in entries do
	if entry.name == "StateController" then
		state = entry.module
	end
end
if type(state) == "table" then
	run("Main", "ClientReady", function()
		if state.ready == true then
			markReady()
		else
			state.ReadySignal:Once(markReady)
		end
	end)
end
