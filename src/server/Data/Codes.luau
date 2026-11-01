--!strict
-- Codes promo (données serveur, jamais répliquées). Utilisés par le service des codes : une fois
-- par compte (profile.codes), mis en majuscules, [A-Z0-9], ≤ 20 caractères ; `expires` en secondes
-- UTC (Clock.unix()). Liste vide dans le socle : les codes du jeu (lancement, événements) seront
-- ajoutés avec leurs récompenses.

-- Récompense : quantités par clé (définies par le jeu, ex. { coins = 500, boostSeconds = 600 })
export type CodeReward = { [string]: number }

export type CodeDef = {
	expires: number,
	reward: CodeReward,
}

local Codes: { [string]: CodeDef } = {}

return Codes
