--!strict
-- Banners (paquet client-hud) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Bannières (GDD §6.6, §9.4) dans l'emplacement de message du HUD : bannières de serveur (Banner),
-- bannières d'événement calculées par le client (sirène du Rush, MEGA, Jelly Moon), une seule à
-- l'écran, 3 s, priorité, messages (Toast) mis en attente pendant une bannière, nouveaux avant
-- l'étape 9 : bannières des autres retenues puis jetées après 30 s.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)

local Banners = {}

-- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
function Banners.Init()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Connexions et boucles (stub : ne fait rien)
function Banners.Start()
	-- stub inoffensif : le démarrage complet reste sans erreur ni avertissement
end

-- Met une bannière dans la file
function Banners.show(payload: Types.BannerPayload)
	local _ = { payload }
	error("TODO(client-hud): Banners.show")
end

-- Mode discret du nouveau
function Banners.setQuiet(quiet: boolean)
	local _ = { quiet }
	error("TODO(client-hud): Banners.setQuiet")
end

-- Bannières en attente (specs)
function Banners.queued(): number
	error("TODO(client-hud): Banners.queued")
end

return Banners
