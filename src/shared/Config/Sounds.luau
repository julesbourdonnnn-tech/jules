--!strict
-- Sons optionnels. Mettre un ID « rbxassetid://… » (Creator Store, sons publics) ;
-- une chaîne vide = son désactivé, le jeu reste entièrement jouable en silence.
-- Format exact « rbxassetid://<nombre> » (un nombre seul ou une adresse de page du Creator Store
-- donnerait un son muet sans erreur ; vérifié par Fix_r3_partage_2.spec).
-- Retours d'interface et de navigation manette (docs/07 R9, §9.2) : sons d'interface publiés par
-- Roblox lui-même pour ses Feature Packages officiels (github.com/Roblox/resources,
-- packages/feature-packages-core/src/Configs/SharedConstants.lua, Sounds.Ids), utilisables dans
-- toute expérience sans téléversement ; deux clés qui partagent un enregistrement s'en distinguent
-- par la hauteur, d'au moins 15 % (Fix_r4_partage_4.spec). Click attend la levée de la règle
-- « vides par défaut » de Contract.spec (BUTTON_ACTIVATED, hauteur 1).
-- Avant la publication : valider ces choix à l'écoute, puis choisir de même, parmi les sons publiés
-- par Roblox, au moins Coin, Catch, Bank, LevelUp, Reward, Supernova et Music.

export type SoundDef = { id: string, volume: number, pitch: number? }

local Sounds: { [string]: SoundDef } = {
	Click = { id = "", volume = 0.5 },
	Pop = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1.3 }, -- BUTTON_ACTIVATED, plus léger
	Coin = { id = "", volume = 0.4 },
	Reward = { id = "", volume = 0.6 },
	LevelUp = { id = "", volume = 0.7 },
	Error = { id = "rbxassetid://17161255584", volume = 0.5, pitch = 0.75 }, -- PROMPT_CLOSED, plus grave
	Whoosh = { id = "rbxassetid://17161253544", volume = 0.4 }, -- PROMPT_OPENED
	Music = { id = "", volume = 0.25 },
	-- Gameplay (GDD §9.4)
	Catch = { id = "", volume = 0.5 }, -- hauteur 1 + min(0,5 ; 0,01 × n) (client)
	CatchRare = { id = "", volume = 0.6 },
	Snip = { id = "", volume = 0.6 }, -- plus aigu côté coupeur
	Scatter = { id = "", volume = 0.5 },
	Bank = { id = "", volume = 0.6 },
	Dash = { id = "", volume = 0.5 },
	CometWarn = { id = "", volume = 0.7 },
	CometImpact = { id = "", volume = 0.7 },
	CometSwipe = { id = "", volume = 0.6 },
	BeaconStart = { id = "", volume = 0.6 },
	BeaconWin = { id = "", volume = 0.7 },
	WispPop = { id = "", volume = 0.5 },
	Supernova = { id = "", volume = 0.8 },
	Ping = { id = "", volume = 0.5 },
	Cheer = { id = "", volume = 0.6 },
	-- Navigation manette (docs/07-console-ps5.md §9) : sélection déplacée, retour (○), onglet ou
	-- panneau changé (L1/R1, L2/R2), bout de liste atteint
	Select = { id = "rbxassetid://17161204665", volume = 0.3 }, -- BUTTON_HOVER
	Back = { id = "rbxassetid://17161255584", volume = 0.35 }, -- PROMPT_CLOSED
	Tab = { id = "rbxassetid://17161253544", volume = 0.35, pitch = 1.25 }, -- PROMPT_OPENED, plus vif
	Bump = { id = "rbxassetid://17161204665", volume = 0.3, pitch = 0.7 }, -- BUTTON_HOVER, plus sourd
}

return Sounds
