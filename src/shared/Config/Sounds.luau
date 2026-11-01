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
