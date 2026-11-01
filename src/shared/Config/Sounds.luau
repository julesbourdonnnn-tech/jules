--!strict
-- Sons du jeu (GDD §9, docs/07 §9.2). Chaque ID rempli est un son publié par Roblox lui-même dans
-- ses dépôts officiels, donc public et utilisable dans toute expérience sans téléversement :
--   « Roblox/resources »    = github.com/Roblox/resources (Feature Packages, exemples Plant et Gold Rush)
--   « Roblox/creator-docs » = github.com/Roblox/creator-docs (chemins sous content/en-us/)
-- Règle (Contract.spec, Fix_r4_partage_4.spec) : un ID rempli porte SUR SA LIGNE un commentaire de
-- provenance (dépôt, fichier, constante ou instance). Format exact « rbxassetid://<nombre> » (un
-- nombre seul ou une adresse de page du Creator Store donnerait un son muet sans erreur ;
-- Fix_r3_partage_2.spec). Une chaîne vide = son désactivé : AudioController n'en crée rien et le
-- jeu reste jouable ; un son qui ne se charge pas est retiré au préchargement (un avertissement par
-- clé, aucune erreur). Deux clés qui partagent un enregistrement s'en distinguent par la hauteur,
-- d'au moins 15 % (Fix_r4_partage_4.spec).
-- Encore vides, à choisir À L'ÉCOUTE parmi les sons publiés par Roblox (pistes trop incertaines,
-- notées sur leur ligne) : Scatter, Bank, Dash, CometWarn, CometSwipe, BeaconStart, WispPop, Ping,
-- Cheer. Avant la publication : écouter aussi chaque son rempli (docs/05 §6.4, docs/06 M12).
-- Garde-fous de lecture (AudioController), réglables par clé, sinon valeurs par défaut en bas :
--   maxLength  s : une copie qui joue encore s'éteint alors en fondu (jingles, morceaux de fête
--              joués en effet ; filet si Ended n'arrive jamais) ; ignoré par la musique (boucle)
--   fade       s : fondu de sortie à maxLength ; pour la musique, fondu d'entrée
--   perFrame   copies d'une même clé gardées pour une même image (lot de captures d'un leurre)
--   concurrent copies d'une même clé qui jouent ensemble ; au-delà, la plus ancienne est coupée

export type SoundDef = {
	id: string,
	volume: number,
	pitch: number?,
	maxLength: number?,
	fade: number?,
	perFrame: number?,
	concurrent: number?,
}

local Sounds: { [string]: SoundDef } = {
	Click = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:42 BUTTON_ACTIVATED (joué à chaque bouton par Client/UISounds.client.lua)
	Pop = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1.3 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:42 BUTTON_ACTIVATED, plus léger
	Coin = { id = "rbxassetid://9113849651", volume = 0.4 }, -- Roblox/resources experiences/plant/Plant.rbxl SoundService.SoundEffects.Coins (CoinAnimator.luau : pièces gagnées)
	Reward = { id = "rbxassetid://17161210152", volume = 0.5, maxLength = 2.5 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:40 PURCHASE_EFFECT (Effects/playPurchaseEffect.lua:126)
	LevelUp = { id = "rbxassetid://3422389728", volume = 0.5, maxLength = 2 }, -- Roblox/creator-docs tutorials/use-case-tutorials/audio/add-2D-audio.md:303 « retro jingle audio track »
	Error = { id = "rbxassetid://17161255584", volume = 0.5, pitch = 0.75 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:39 PROMPT_CLOSED, plus grave
	Whoosh = { id = "rbxassetid://17161253544", volume = 0.4 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:38 PROMPT_OPENED
	Music = { id = "rbxassetid://1837849285", volume = 0.25, fade = 2 }, -- Roblox/creator-docs tutorials/use-case-tutorials/audio/play-background-music.md:37 « Upbeat Electronica » (boucle)
	-- Gameplay (GDD §9.4)
	Catch = { id = "rbxassetid://4110925712", volume = 0.45 }, -- Roblox/creator-docs tutorials/use-case-tutorials/audio/in-game-sounds.md:90 « simple chime » de ramassage ; hauteur 1 + min(0,5 ; 0,01 × n) (client)
	CatchRare = { id = "rbxassetid://18635972230", volume = 0.55 }, -- Roblox/resources experiences/gold-rush/GoldRush.rbxl SoundService.GoldSound (pépite ramassée, StarterPlayerScripts.SoundManager)
	Snip = { id = "rbxassetid://9125571221", volume = 0.6 }, -- Roblox/resources experiences/plant/Plant.rbxl SoundService.SoundEffects.Harvest (« a clip sound », creator-docs add-3D-audio.md:261) ; plus aigu côté coupeur
	Scatter = { id = "", volume = 0.5 }, -- à choisir à l'écoute (aucune piste assez sûre)
	Bank = { id = "", volume = 0.6 }, -- à choisir à l'écoute : piste rbxassetid://9118130272 (Roblox/resources experiences/plant/Plant.rbxl SoundService.SoundEffects.Purchase, joué quand on DÉPENSE), sinon Coins à hauteur 0,8
	Dash = { id = "", volume = 0.5 }, -- à choisir à l'écoute : piste PROMPT_OPENED rbxassetid://17161253544 (Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:38) à hauteur 1,5
	CometWarn = { id = "", volume = 0.7 }, -- à choisir à l'écoute : piste rbxassetid://7743999789 (Roblox/creator-docs resources/modules/photo-booth.md:253 countdownBeepSound, peut-être trop discret)
	CometImpact = { id = "rbxassetid://9125402735", volume = 0.5 }, -- Roblox/creator-docs projects/assets/index.md:18-19 (exemple d'asset audio « Boom-Impact »)
	CometSwipe = { id = "", volume = 0.6 }, -- à choisir à l'écoute : piste GoldSound rbxassetid://18635972230 (Roblox/resources experiences/gold-rush/GoldRush.rbxl) à hauteur 1,3
	BeaconStart = { id = "", volume = 0.6 }, -- à choisir à l'écoute (aucune piste trouvée)
	BeaconWin = { id = "rbxassetid://1846248593", volume = 0.6, maxLength = 3.5 }, -- Roblox/creator-docs tutorials/use-case-tutorials/audio/add-3D-audio.md:296 « cheerful, celebratory audio track »
	WispPop = { id = "", volume = 0.5 }, -- à choisir à l'écoute : piste BUTTON_ACTIVATED rbxassetid://17161216230 (Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:42) à hauteur 1,7
	Supernova = { id = "rbxassetid://1846248593", volume = 0.7, pitch = 0.85, maxLength = 3 }, -- Roblox/creator-docs tutorials/use-case-tutorials/audio/add-3D-audio.md:296 « celebratory », plus grave (séquence de 2,5 s)
	Ping = { id = "", volume = 0.5 }, -- à choisir à l'écoute : piste rbxassetid://9114112830 (Roblox/resources experiences/plant/Plant.rbxl SoundService.SoundEffects.Plant, « gentle clink »)
	Cheer = { id = "", volume = 0.6 }, -- à choisir à l'écoute : piste rbxassetid://1846248593 (Roblox/creator-docs tutorials/use-case-tutorials/audio/add-3D-audio.md:296) à hauteur 1,2 ; aucun son de foule officiel
	-- Navigation manette (docs/07-console-ps5.md §9) : sélection déplacée, retour (○), onglet ou
	-- panneau changé (L1/R1, L2/R2), bout de liste atteint
	Select = { id = "rbxassetid://17161204665", volume = 0.3 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:43 BUTTON_HOVER
	Back = { id = "rbxassetid://17161255584", volume = 0.35 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:39 PROMPT_CLOSED
	Tab = { id = "rbxassetid://17161253544", volume = 0.35, pitch = 1.25 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:38 PROMPT_OPENED, plus vif
	Bump = { id = "rbxassetid://17161204665", volume = 0.3, pitch = 0.7 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:43 BUTTON_HOVER, plus sourd
}

-- Garde-fous par défaut (voir l'en-tête), posés sur chaque clé qui ne les fixe pas
local MAX_LENGTH = 4 -- s : aucun effet ne joue plus longtemps
local FADE = 0.3 -- s
local PER_FRAME = 3
local CONCURRENT = 4
for _, def in Sounds do
	def.maxLength = def.maxLength or MAX_LENGTH
	def.fade = def.fade or FADE
	def.perFrame = def.perFrame or PER_FRAME
	def.concurrent = def.concurrent or CONCURRENT
end

return Sounds
