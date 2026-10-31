--!strict
-- Console et écran « 10 pieds » (docs/07-console-ps5.md). Source unique des nombres utilisés par
-- Client/Util/Platform (échelle, zone sûre), Client/UI/Root, Client/UI/Glyph, Client/Util/Haptics
-- et les specs. src/first/Loading.client.luau, autonome, en recopie les valeurs d'échelle
-- (vérifié par une spec).

export type HapticDef = {
	effect: string, -- Enum.HapticEffectType (HapticEffect, manette)
	motor: string, -- Enum.VibrationMotor (repli HapticService:SetMotor)
	strength: number, -- 0-1 (repli SetMotor)
	duration: number, -- s (repli SetMotor)
	priority: number, -- une vibration plus prioritaire passe pendant le délai minimal
	mobile: boolean?, -- jouée aussi sur téléphone (GDD §9.1 : capture Épique+)
}

local Console = {
	-- Résolution de référence des interfaces (GDD §10.1)
	Reference = { X = 1280, Y = 720 },
	-- Écrans ordinaires : UIScale = clamp(min(L / 1280 ; H / 720) ; 0,6 ; 1,25) (GDD §10.1)
	Scale = { Min = 0.6, Max = 1.25 },
	-- Écran Large (téléviseur) ou console : UIScale = max(0,6 ; min(L / 1280 ; H / 720)), sans
	-- plafond (1,5 en 1920 × 1080) : la référence 1280 × 720 occupe tout l'écran, comme sur un
	-- téléphone vu à bout de bras (docs/07 §3)
	TvScale = { Min = 0.6 },
	-- Zone sûre TV : fraction de l'écran laissée libre de chaque côté (docs/07 §4)
	TvSafeMargin = 0.05,
	-- Marge intérieure ordinaire de Root.safe (px de référence)
	BasePadding = { X = 12, Y = 8 },
	-- Texte lisible minimal (px de référence) : 27 px réels en 1080p sur téléviseur
	MinTextSize = 18,
	-- Icône de touche (px de référence)
	GlyphSize = 36,
	-- s : attente bornée des configurations de TextChatService (règle « pas de fenêtre de chat »)
	ChatWaitTimeout = 10,
	-- s : intervalle minimal entre deux sons de navigation (« Select »)
	NavSoundInterval = 0.06,
	Haptics = {
		Cooldown = 0.25, -- s entre deux vibrations (sauf priorité supérieure)
		MinScale = 0.35, -- vibration atténuée (distance) sous ce facteur : pas jouée
		Events = {
			-- interface
			refuse = { effect = "UIClick", motor = "Small", strength = 0.25, duration = 0.05, priority = 1 },
			listEnd = { effect = "UIClick", motor = "Small", strength = 0.2, duration = 0.04, priority = 1 },
			holdStart = {
				effect = "UIClick",
				motor = "Small",
				strength = 0.25,
				duration = 0.05,
				priority = 1,
			},
			-- gameplay
			catchEpic = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.4,
				duration = 0.08,
				priority = 2,
				mobile = true,
			},
			catchLegendary = {
				effect = "GameplayCollision",
				motor = "Large",
				strength = 0.6,
				duration = 0.15,
				priority = 3,
				mobile = true,
			},
			snipper = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.35,
				duration = 0.08,
				priority = 2,
			},
			snipped = {
				effect = "GameplayCollision",
				motor = "Large",
				strength = 0.7,
				duration = 0.25,
				priority = 4,
			},
			parade = {
				effect = "UINotification",
				motor = "Small",
				strength = 0.35,
				duration = 0.12,
				priority = 2,
			},
			cometWarn = {
				effect = "UINotification",
				motor = "Small",
				strength = 0.3,
				duration = 0.12,
				priority = 2,
			},
			cometImpact = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 0.8,
				duration = 0.3,
				priority = 4,
			},
			cometGrab = {
				effect = "GameplayCollision",
				motor = "Large",
				strength = 0.5,
				duration = 0.15,
				priority = 3,
			},
			supernova = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 1,
				duration = 0.4,
				priority = 5,
			},
		} :: { [string]: HapticDef },
	},
}

return Console
