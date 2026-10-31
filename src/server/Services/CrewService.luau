--!strict
-- CrewService — paquet « events » (STUB du contrat : docs/04-architecture.md §11.9).
-- Équipages (mémoire), escorte, pings, acclamations, file des bannières de serveur, cadeau Duo.
-- Responsabilités :
--   * équipages de 4 max : formation automatique des amis Roblox présents (réglage autoCrew,
--     Player:IsFriendsWith en pcall, résultat en cache) ; remotes CrewInvite(userId) 1/3 s et 5/min,
--     CrewRespond(inviterId, accept) 2/s (invitation de 20 s), CrewLeave() 1/5 s ; refus si
--     refuseInvites ; départ du serveur = départ de l'équipage ; CrewState à tous à chaque changement ;
--     attribut Player « CrewId » ; Signals.CrewChanged ; EconomyService.setCrewPresent pour chaque
--     membre ; Analytics CrewFormed
--   * escorte : API escortersOf(victim) utilisée par CongaService (le calcul géométrique et le temps
--     d'escorte sont faits par CongaService, qui possède les nœuds)
--   * pings : remote Ping(kind 1-6) 1/1,5 s → PingShow à tous
--   * acclamations : sur Signals.Supernova, CheerPrompt à tous sauf le héros (fenêtre 10 s) ;
--     remote Cheer(heroId) 2/s : une fois par héros et par Supernova ; +5 Stardust plafonnée
--     (cheers, 10/jour) ; Signals.Cheered ; Feedback « N joueurs t'acclament » au héros
--   * bannières : écoute Signals.BannerRequested ; une même source au plus 1 / 10 s ; file de 3 max
--     triée par priorité (Notify.BANNER_PRIORITY) ; une bannière diffusée toutes les 3 s (step)
--   * cadeau Duo : 10 min cumulées sur le même serveur qu'un ami Roblox → 50 Stardust aux deux
--     (plafond caps.duo, une fois par jour UTC)
-- GDD : §6.1-§6.3, §6.5, §6.6, §14.3.
-- Dépendances : DataService, NestService (réglages), EconomyService, Signals, Util/Notify,
-- Util/RateLimit, Util/Analytics, Config/Balance, Shared/Util/Clock.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local CrewService = {}

function CrewService.Init() end

function CrewService.Start() end

-- Expirations des invitations et des fenêtres d'acclamation, file des bannières, temps Duo
function CrewService.step(_now: number)
	error("TODO(events): CrewService.step")
end

-- Identifiant d'équipage (0 = aucun)
function CrewService.crewOf(_player: Player): number
	error("TODO(events): CrewService.crewOf")
end

function CrewService.areCrewmates(_a: Player, _b: Player): boolean
	error("TODO(events): CrewService.areCrewmates")
end

-- Équipiers présents (sans le joueur lui-même)
function CrewService.crewmates(_player: Player): { Player }
	error("TODO(events): CrewService.crewmates")
end

-- Équipiers de la victime qui peuvent escorter sa file
function CrewService.escortersOf(_victim: Player): { Player }
	error("TODO(events): CrewService.escortersOf")
end

-- Diffuse une bannière (même chemin que Signals.BannerRequested)
function CrewService.banner(_kind: Types.BannerKind, _args: { [string]: any }, _source: Player?)
	error("TODO(events): CrewService.banner")
end

function CrewService.snapshot(): Types.CrewStatePayload
	error("TODO(events): CrewService.snapshot")
end

return CrewService
