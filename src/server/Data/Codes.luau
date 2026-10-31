--!strict
-- Codes promo (GDD §4.17, §7.7) — paquet « events » (données serveur, jamais répliquées).
-- Utilisés par QuestService (remote RedeemCode) : une fois par compte (profile.codes), mis en
-- majuscules, [A-Z0-9], ≤ 20 caractères ; `expires` en secondes UTC (Clock.unix()).
-- Ajouter un code = ajouter une entrée (publication du samedi 17:00 UTC).

export type CodeReward = {
	glow: number?,
	idleSeconds: number?, -- Glow = idleSeconds × revenu passif (min minGlow)
	minGlow: number?,
	stardust: number?,
	boostSeconds: number?,
	species: number?,
}

export type CodeDef = {
	expires: number,
	reward: CodeReward,
}

local Codes: { [string]: CodeDef } = {
	-- Code de lancement : 200 Stardust + 10 min de boost ×2, valable jusqu'au 31/12/2027 23:59:59 UTC
	COMETCONGA = {
		expires = 1830297599,
		reward = { stardust = 200, boostSeconds = 600 },
	},
}

return Codes
