--!strict
-- OnboardingController (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Les 5 premières minutes (GDD §3) côté client : chemin lumineux, gestes de Big Plop (copie locale),
-- une seule consigne à la fois (glyphe 64 + mot 40 px TV, 4 mots au plus), consigne rangée après 90 s
-- (Big Plop la remontre plus tard), affichage progressif du HUD, glyphe du stick après 4 s sans
-- bouger, L1 R1 « Choisir » une fois, leçon du menu, événements discrets avant l'étape 9
-- (LightingController.setQuiet, Banners.setQuiet, musique −12 dB). Reprise après une mort ou un retour.

local OnboardingController = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function OnboardingController.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function OnboardingController.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Étape d'accueil connue du client
function OnboardingController.step(): number
	error("TODO(client-hud): OnboardingController.step")
end

-- Événements discrets (avant l'étape 9)
function OnboardingController.quiet(): boolean
	error("TODO(client-hud): OnboardingController.quiet")
end

return OnboardingController
