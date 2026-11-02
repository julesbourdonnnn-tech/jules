--!strict
-- Sons du jeu. Socle : les 8 sons d'interface et de navigation repris de Comet Conga (QA tour 4 :
-- sans eux, la PS5 n'avait aucun retour sonore). Les sons de jeu (presser, éclosion, fusion, BOOP
-- RUSH…) seront ajoutés par les paquets du jeu, avec la même règle.
-- Chaque ID rempli est un son publié par Roblox lui-même dans ses dépôts officiels, donc public et
-- utilisable dans toute expérience sans téléversement :
--   « Roblox/resources »    = github.com/Roblox/resources (Feature Packages, exemples Plant et Gold Rush)
--   « Roblox/creator-docs » = github.com/Roblox/creator-docs (chemins sous content/en-us/)
-- Règles (Contract.spec, Sounds.spec) :
--   * un ID rempli porte SUR SA LIGNE un commentaire de provenance (dépôt, fichier, constante) ;
--   * format exact « rbxassetid://<nombre> » (un nombre seul ou une adresse de page du Creator Store
--     donnerait un son muet sans erreur) ;
--   * une chaîne vide = son désactivé : AudioController n'en crée rien et le jeu reste jouable ; un son
--     qui ne se charge pas est retiré au préchargement (un avertissement par clé, aucune erreur) ;
--   * deux clés qui partagent un enregistrement s'en distinguent par la hauteur, d'au moins 15 %.
-- Avant la publication : écouter chaque son dans Roblox Studio ; un son qui déplaît se vide (id = "").
-- Garde-fous de lecture (AudioController), réglables par clé, sinon valeurs par défaut en bas :
--   maxLength  s : une copie qui joue encore s'éteint alors en fondu (filet si Ended n'arrive jamais) ;
--              ignoré par la musique (clé « Music », en boucle, ajoutée par le jeu)
--   fade       s : fondu de sortie à maxLength ; pour la musique, fondu d'entrée
--   perFrame   copies d'une même clé gardées pour une même image
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
	-- Interface : bouton pressé, petite apparition, refus, ouverture d'un menu
	Click = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:42 BUTTON_ACTIVATED (joué à chaque bouton par Client/UISounds.client.lua)
	Pop = { id = "rbxassetid://17161216230", volume = 0.5, pitch = 1.3 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:42 BUTTON_ACTIVATED, plus léger
	Error = { id = "rbxassetid://17161255584", volume = 0.5, pitch = 0.75 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:39 PROMPT_CLOSED, plus grave
	Whoosh = { id = "rbxassetid://17161253544", volume = 0.4 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:38 PROMPT_OPENED
	-- Navigation manette : sélection déplacée, retour (○), onglet ou panneau changé (L1/R1, L2/R2),
	-- bout de liste atteint
	Select = { id = "rbxassetid://17161204665", volume = 0.3 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:43 BUTTON_HOVER
	Back = { id = "rbxassetid://17161255584", volume = 0.35 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:39 PROMPT_CLOSED
	Tab = { id = "rbxassetid://17161253544", volume = 0.35, pitch = 1.25 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:38 PROMPT_OPENED, plus vif
	Bump = { id = "rbxassetid://17161204665", volume = 0.3, pitch = 0.7 }, -- Roblox/resources packages/feature-packages-core/src/Configs/SharedConstants.lua:43 BUTTON_HOVER, plus sourd

	-- Jeu (GDD §9.6). Ajoutés par le contrat avec un ID VIDE (muet) : chaque son se cherche dans les
	-- dépôts officiels (candidats et replis : GDD §9.6), puis s'écoute dans Studio avant d'être rempli
	-- (provenance sur la ligne). Musiques : « Music » (jour) ; « MusicMoon » et « MusicRush » sont
	-- jouées comme musiques (note d'intégration INT-AUDIO, docs/04 §18).
	-- Pièces, récompenses
	Coin = { id = "", volume = 0.35 }, -- pièces qui arrivent au compteur (8 par seconde au plus)
	Reward = { id = "", volume = 0.5 }, -- récompense, achat Robux
	LevelUp = { id = "", volume = 0.5 }, -- palier
	-- Musiques
	Music = { id = "", volume = 0.3, fade = 2 }, -- musique de jour (en boucle ; fondu croisé de 2 s)
	MusicMoon = { id = "", volume = 0.3, fade = 2 }, -- Jelly Moon (plus douce)
	MusicRush = { id = "", volume = 0.35, fade = 1 }, -- BOOP RUSH (gloussements, rapide)
	-- Presser
	Press = { id = "", volume = 0.5 }, -- SPLORCH (hauteur au hasard 0,92-1,08)
	Perfect = { id = "", volume = 0.55 }, -- PERFECT (hauteur 1,0595^série)
	StreakMax = { id = "", volume = 0.55 }, -- série de 5
	-- Ranch
	PotCollect = { id = "", volume = 0.5 },
	TileBuild = { id = "", volume = 0.5 },
	VatBubble = { id = "", volume = 0.3 },
	-- Naissances
	Hatch = { id = "", volume = 0.5 },
	HatchRare = { id = "", volume = 0.55 },
	HatchLegend = { id = "", volume = 0.6 },
	MutationReveal = { id = "", volume = 0.5 },
	Blorp = { id = "", volume = 0.5 }, -- le cri du Flop
	-- Portage, Bassin, fusion
	Pickup = { id = "", volume = 0.45 },
	Throw = { id = "", volume = 0.45 },
	Splash = { id = "", volume = 0.45 },
	Fuse = { id = "", volume = 0.55 },
	ComboStep = { id = "", volume = 0.55 }, -- hauteur 1 + 0,08 k
	ComboBig = { id = "", volume = 0.6 },
	-- Créatures et poursuites
	RunawayAppear = { id = "", volume = 0.45 },
	Giggle = { id = "", volume = 0.35 }, -- son 3D, portée 60 studs
	Catch = { id = "", volume = 0.55 },
	CatchGolden = { id = "", volume = 0.6 },
	Leap = { id = "", volume = 0.45 },
	MountUp = { id = "", volume = 0.45 },
	RideLand = { id = "", volume = 0.4 },
	-- BOOP RUSH
	RushSiren = { id = "", volume = 0.5 },
	BoopHold = { id = "", volume = 0.4 },
	Sneeze = { id = "", volume = 0.55 }, -- ATCHOUM : drôle et doux
	Return = { id = "", volume = 0.45 },
	BabyGet = { id = "", volume = 0.55 },
	HeroCatch = { id = "", volume = 0.6 },
	-- MEGA SQUISH
	MegaWarn = { id = "", volume = 0.5 },
	MegaLand = { id = "", volume = 0.6 },
	MegaPress = { id = "", volume = 0.45 }, -- hauteur 0,9 à 1,3 selon la progression
	MegaPop = { id = "", volume = 0.6 },
	MegaSigh = { id = "", volume = 0.45 },
	-- Serveur
	GaugeFull = { id = "", volume = 0.55 },
	GoldenAppear = { id = "", volume = 0.5 },
	MoonStart = { id = "", volume = 0.5 },
	Fanfare = { id = "", volume = 0.55 },
	-- Grand Splorch
	SplorchCharge = { id = "", volume = 0.55 },
	SplorchPop = { id = "", volume = 0.65 },
	GiftRain = { id = "", volume = 0.5 },
	-- Rétention, social
	FeedPlop = { id = "", volume = 0.5 },
	DexNew = { id = "", volume = 0.5 },
	ObjectiveDone = { id = "", volume = 0.5 },
	Emote = { id = "", volume = 0.4 },
	Boing = { id = "", volume = 0.5 }, -- portail refusé
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
