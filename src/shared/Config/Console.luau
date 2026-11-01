--!strict
-- Console et écran « 10 pieds » (couche console reprise de Comet Conga, docs/07-console-ps5.md de
-- Comet Conga). Source unique des nombres utilisés par Client/Util/Platform (échelle, zone sûre),
-- Client/UI/Root, Client/UI/Glyph, Client/Util/Haptics, Client/Controllers/AudioController et les
-- specs. src/first/Loading.client.luau, autonome, en recopie les valeurs d'échelle (vérifié par une
-- spec).
-- Raise a Squishy : CONSOLE D'ABORD (décision du propriétaire du 1er novembre 2026, note INT-TV
-- appliquée par le contrat, docs/04 §14.1, §22). Une seule disposition, la disposition télé
-- 1920 × 1080 (= Config/Layout), sur console comme sur PC ; aucun téléphone au lancement.

export type HapticDef = {
	effect: string, -- Enum.HapticEffectType (HapticEffect, manette)
	motor: string, -- Enum.VibrationMotor (repli HapticService:SetMotor)
	strength: number, -- 0-1 (repli SetMotor, et force atténuée)
	duration: number, -- s (repli SetMotor)
	priority: number, -- une vibration plus prioritaire passe pendant le délai minimal
	cooldownExempt: boolean?, -- joue même pendant le délai minimal (sirène du Rush, contrat v1.2)
}

local Console = {
	-- Résolution de référence des interfaces : « px TV » d'un écran de 1920 × 1080 (= Layout.Reference)
	Reference = { X = 1920, Y = 1080 },
	-- TOUS les écrans (console, télé, moniteur de PC) : UIScale = max(0,5 ; min(L / 1920 ; H / 1080)),
	-- sans plafond (1 en 1080p, 2 en 4K, 0,667 en 720p) : la taille vue du canapé ne change pas
	TvScale = { Min = 0.5 },
	-- Zone sûre TV sur TOUS les écrans : fraction de l'écran laissée libre de chaque côté
	TvSafeMargin = 0.05,
	-- Marge intérieure minimale de Root.safe (px TV), si la zone sûre est plus petite
	BasePadding = { X = 18, Y = 12 },
	-- Texte lisible minimal (px TV, = Layout.Text.Min) : lu à 2,5-3 m sur un téléviseur
	MinTextSize = 28,
	-- Icône de touche (px TV, = Layout.Glyph.Min)
	GlyphSize = 48,
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
			-- Raise a Squishy (contrat, GDD §10.5) : jamais sur une sélection, un bond ou une marche ;
			-- délai minimal Cooldown sauf priorité supérieure. Le joueur de l'événement est seul à vibrer.
			-- Force variable : la force de la carte est le MAXIMUM, le contrôleur passe une échelle ≤ 1
			-- (Haptics.play(nom, force voulue / force de la carte), jamais au-dessus de 1).
			-- pressTick : seulement une pression PERFECT du MEGA (une pression ordinaire, chez soi ou au
			-- MEGA, ne vibre jamais : GDD v1.3), 2 par seconde au plus ; VFXController est le SEUL à la borner
			pressTick = {
				effect = "UIClick",
				motor = "Small",
				strength = 0.15,
				duration = 0.03,
				priority = 1,
			},
			-- perfect : 0,3 + 0,03 par cran de série (0 … 5) : Haptics.play("perfect", (0,3 + 0,03 × série) / 0,45)
			perfect = { effect = "UIClick", motor = "Small", strength = 0.45, duration = 0.05, priority = 2 },
			tileBuy = { effect = "UIClick", motor = "Small", strength = 0.25, duration = 0.05, priority = 2 },
			holdDone = {
				effect = "UINotification",
				motor = "Small",
				strength = 0.35,
				duration = 0.08,
				priority = 2,
			},
			cardIn = {
				effect = "UINotification",
				motor = "Small",
				strength = 0.2,
				duration = 0.06,
				priority = 2,
			},
			catch = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.35,
				duration = 0.08,
				priority = 2,
			},
			-- fusion : 0,4 + 0,05 par étape au-delà de la première (k = 1 … 6) :
			-- Haptics.play("fusion", (0,4 + 0,05 × (k − 1)) / 0,65)
			fusion = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.65,
				duration = 0.08,
				priority = 2,
			},
			comboBig = {
				effect = "GameplayCollision",
				motor = "Large",
				strength = 0.6,
				duration = 0.2,
				priority = 3,
			},
			boopDone = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.3,
				duration = 0.06,
				priority = 2,
			},
			-- squishyBack (GDD v1.3, remplace `booped`) : mon squishy boopé revient, rendu par un autre
			-- joueur ou rentré seul (Celebrate "ownerReturn" / "returnedBigger" ; la capture Héros joue
			-- `catch`). Aucune vibration quand il s'enfuit (signal négatif, pilier P2)
			squishyBack = {
				effect = "GameplayCollision",
				motor = "Small",
				strength = 0.3,
				duration = 0.08,
				priority = 2,
			},
			-- une seule impulsion de 0,3 s (GDD v1.3), jouée même pendant le délai minimal ; jamais pour un
			-- nouveau avant l'étape 9 de l'accueil
			rushSiren = {
				effect = "UINotification",
				motor = "Small",
				strength = 0.4,
				duration = 0.3,
				priority = 3,
				cooldownExempt = true,
			},
			-- atténuée 1 − d / 120 (MinScale 0,35)
			megaLand = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 0.7,
				duration = 0.25,
				priority = 3,
			},
			megaPop = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 0.8,
				duration = 0.3,
				priority = 4,
			},
			hatchLegend = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 0.8,
				duration = 0.3,
				priority = 4,
			},
			splorch = {
				effect = "GameplayExplosion",
				motor = "Large",
				strength = 1.0,
				duration = 0.4,
				priority = 5,
			},
		} :: { [string]: HapticDef },
	},
}

return Console
