--!strict
-- Console et écran « 10 pieds » (couche console reprise de Comet Conga, docs/07-console-ps5.md de
-- Comet Conga). Source unique des nombres utilisés par Client/Util/Platform (échelle, zone sûre),
-- Client/UI/Root, Client/UI/Glyph, Client/Util/Haptics, Client/Controllers/AudioController et les
-- specs. src/first/Loading.client.luau, autonome, en recopie les valeurs d'échelle (vérifié par une
-- spec).

export type HapticDef = {
	effect: string, -- Enum.HapticEffectType (HapticEffect, manette)
	motor: string, -- Enum.VibrationMotor (repli HapticService:SetMotor)
	strength: number, -- 0-1 (repli SetMotor, et force atténuée)
	duration: number, -- s (repli SetMotor)
	priority: number, -- une vibration plus prioritaire passe pendant le délai minimal
	mobile: boolean?, -- jouée aussi sur téléphone (réservé aux grands moments)
}

local Console = {
	-- Résolution de référence des interfaces
	Reference = { X = 1280, Y = 720 },
	-- Écrans ordinaires : UIScale = clamp(min(L / 1280 ; H / 720) ; 0,6 ; 1,25)
	Scale = { Min = 0.6, Max = 1.25 },
	-- Écran Large (téléviseur) ou console : UIScale = max(0,6 ; min(L / 1280 ; H / 720)), sans
	-- plafond (1,5 en 1920 × 1080) : la référence 1280 × 720 occupe tout l'écran, comme sur un
	-- téléphone vu à bout de bras
	TvScale = { Min = 0.6 },
	-- Zone sûre TV : fraction de l'écran laissée libre de chaque côté
	TvSafeMargin = 0.05,
	-- Marge intérieure ordinaire de Root.safe (px de référence)
	BasePadding = { X = 12, Y = 8 },
	-- Texte lisible minimal (px de référence) : 27 px réels en 1080p sur téléviseur
	MinTextSize = 18,
	-- Icône de touche (px de référence)
	GlyphSize = 36,
	-- s : attente bornée des configurations de TextChatService (règle « pas de fenêtre de chat »)
	ChatWaitTimeout = 10,
	-- s entre deux essais de StarterGui:SetCoreGuiEnabled(Chat, false) (CoreGui pas encore prêt)
	ChatCoreRetry = 0.5,
	-- s : sélection effacée au plus tant après ✕ sur un objet de la fenêtre = fenêtre Roblox ouverte
	-- par ce bouton (achat : les infos du produit arrivent avant que la fenêtre prenne la manette)
	PromptHoldWindow = 3,
	-- s : une fermeture demandée si peu de temps après l'ouverture du même panneau est ignorée
	-- (double appui sur un bouton du rail de menus)
	ToggleCloseGuard = 0.35,
	-- s : intervalle minimal entre deux sons de navigation (« Select »)
	NavSoundInterval = 0.06,
	Haptics = {
		Cooldown = 0.25, -- s entre deux vibrations (sauf priorité supérieure)
		MinScale = 0.35, -- vibration atténuée (distance) sous ce facteur : pas jouée
		-- Socle : vibrations d'interface. Les vibrations de jeu (pression, fusion, éclosion rare,
		-- sirène du Rush…) s'ajoutent ici, avec modération.
		Events = {
			refuse = { effect = "UIClick", motor = "Small", strength = 0.25, duration = 0.05, priority = 1 },
			listEnd = { effect = "UIClick", motor = "Small", strength = 0.2, duration = 0.04, priority = 1 },
			holdStart = {
				effect = "UIClick",
				motor = "Small",
				strength = 0.25,
				duration = 0.05,
				priority = 1,
			},
		} :: { [string]: HapticDef },
	},
}

return Console
