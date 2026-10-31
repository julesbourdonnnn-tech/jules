--!strict
-- Banners — paquet « client-hud » (STUB du contrat : docs/04-architecture.md §13.10).
-- Propriétaire côté client du remote Banner. Affichage en haut au centre (640 × 72, sous la pastille
-- d'événement) : glisse en 0,25 s (Back Out), reste 3 s ; file locale de 3 au plus, triée par
-- priorité (payload.priority) ; bannières personnelles (payload.personal) prioritaires.
-- Textes : "banner.<kind>" interpolés avec args (noms, niveaux en chiffres romains pour
-- Supernova, durées via Prefs.duration, espèces via Config/Nebbies).
-- Sons : CometWarn, BeaconStart, BeaconWin, Reward selon le genre.
-- GDD : §6.5, §9.4 (bannières), §10.2.
-- Dépendances : AudioController, Util/Prefs, UI/Root, UI/Theme, UI/Create, UI/Juice, Shared/Net,
-- Config/Nebbies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Banners = {}

-- Bannière effectivement affichée
Banners.Shown = Signal.new() :: Signal.Signal<Types.BannerPayload>

function Banners.Init() end

function Banners.Start() end

-- Met une bannière en file (utilisé par le remote et par les modules locaux)
function Banners.show(_payload: Types.BannerPayload)
	error("TODO(client-hud): Banners.show")
end

-- Bannières en attente (tests)
function Banners.queued(): { Types.BannerPayload }
	error("TODO(client-hud): Banners.queued")
end

return Banners
