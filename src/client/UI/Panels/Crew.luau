--!strict
-- Panels/Crew — paquet « client-panels » (STUB du contrat : docs/04-architecture.md §13.16).
-- Module de panneau (interface PanelController.Panel), construit à la première ouverture.
-- Responsabilités :
--   * équipage actuel (WorldStateController.crews), liste des joueurs du serveur avec Inviter (56 px)
--     → CrewInvite(userId), Quitter → CrewLeave (recharge 5 s), Inviter un ami →
--     SocialService:PromptGameInvite (aucune récompense)
--   * carte d'invitation reçue (remote CrewInvitePrompt routé par PanelController) : ✓ / ✕ pendant
--     20 s → CrewRespond(inviterId, accept), non bloquante (exposée par showInvite)
--   * textes via Prefs.t (ré-appliqués sur Prefs.LanguageChanged), nombres via Prefs.number,
--     boutons Juice.press + Selectable ; intentions seulement (le serveur valide tout)
-- GDD : §6.1, §6.2, §10.3.
-- Dépendances : StateController, Util/Prefs, UI/Theme, UI/Create, UI/Juice, Shared/Net, Logic/Formulas,
-- Config/*, WorldStateController, ScreenFX, Shared/Util/Clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared").Types)

local Panel = {}

Panel.name = "Crew" :: Types.PanelName
Panel.tabs = nil :: { string }?

function Panel.build(_parent: Frame)
	error("TODO(client-panels): Crew.build")
end

function Panel.onOpen(_args: any?)
	error("TODO(client-panels): Crew.onOpen")
end

function Panel.onClose()
	error("TODO(client-panels): Crew.onClose")
end

function Panel.hasAction(): boolean
	error("TODO(client-panels): Crew.hasAction")
end

-- Carte d'invitation (appelée par PanelController sur CrewInvitePrompt)
function Panel.showInvite(_payload: Types.CrewInvitePayload)
	error("TODO(client-panels): Crew.showInvite")
end

return Panel
