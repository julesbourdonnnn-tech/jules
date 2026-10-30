--!strict
-- Textes du jeu. Clés en « domaine.nom ». Variables entre accolades : {amount}.

local Strings: { [string]: { [string]: string } } = {}

Strings.en = {
	["common.ok"] = "OK",
	["common.close"] = "Close",
	["common.buy"] = "Buy",
	["common.claim"] = "Claim",
	["common.locked"] = "Locked",
	["common.notEnough"] = "Not enough {currency}!",
	["common.loading"] = "Loading...",
}

Strings.fr = {
	["common.ok"] = "OK",
	["common.close"] = "Fermer",
	["common.buy"] = "Acheter",
	["common.claim"] = "Récupérer",
	["common.locked"] = "Verrouillé",
	["common.notEnough"] = "Pas assez de {currency} !",
	["common.loading"] = "Chargement...",
}

return Strings
