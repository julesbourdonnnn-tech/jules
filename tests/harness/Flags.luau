--!strict
-- Préréglages des interrupteurs v2.0 pour les tests (lot I, étape 1, décision D1 du plan I).
-- Une seule liste des 23 clés de lancement de la v2.0 (ordre de Config/Features ; JellyAscend, écrit
-- plus haut dans le fichier, prend la place que lui donne docs/04 §27.3). Préréglages :
--   * "launch" : valeurs livrées de Config/Features, intactes (défaut de Harness.new : le jeu que
--     joue le propriétaire)
--   * "full"   : chaque clé v2 ouverte (le jeu v2.0 complet, avant que chaque groupe soit ouvert)
--   * "v13"    : chaque clé v2 coupée (exactement la configuration livrée jusqu'à 3636608)
--   * "cut"    : SchemaV2 ouvert, les 22 autres coupées (la vraie coupure d'urgence après I : LiveOps
--     coupe tout en direct, jamais SchemaV2)
--   * une table { [clé] = valeur } : la configuration livrée, changée clé par clé
-- Flags.apply écrit les valeurs dans Config/Features.Defaults DU harnais (chaque harnais a son propre
-- cache de modules) puis appelle Features.reset() : à faire avant tout require qui lit Defaults à son
-- chargement (Data/Schema : Schema.VERSION). Harness.new le fait avant de rendre le harnais.

local Flags = {}

Flags.V2_KEYS = table.freeze({
	"SchemaV2",
	"UpgradesScreen",
	"Confetti",
	"Workshop",
	"StarMat",
	"Gloves",
	"Monuments",
	"RecordR",
	"JellyAscend",
	"PetitSplorch",
	"Helpers",
	"WeeklyTrack",
	"Carnet",
	"Mastery",
	"RanchTiers",
	"RanchSkins",
	"DecoPerso",
	"Hearts",
	"PhotoMode",
	"Weather",
	"Fete",
	"Personalities",
	"Ambience",
})

local FEATURES = "ReplicatedStorage.Shared.Config.Features"

export type Preset = string | { [string]: any }

-- Valeurs à écrire pour un préréglage (nil : "launch", rien à changer). Erreur sur un nom inconnu ou
-- une clé inconnue de la table (une faute de frappe ne passe jamais en silence).
function Flags.preset(preset: Preset?): { [string]: any }?
	if preset == nil or preset == "launch" then
		return nil
	end
	local out: { [string]: any } = {}
	if type(preset) == "table" then
		for key, value in preset do
			out[key] = value
		end
		return out
	end
	if preset == "full" then
		for _, key in Flags.V2_KEYS do
			out[key] = true
		end
	elseif preset == "v13" then
		for _, key in Flags.V2_KEYS do
			out[key] = false
		end
	elseif preset == "cut" then
		for _, key in Flags.V2_KEYS do
			out[key] = key == "SchemaV2"
		end
	else
		error(`Flags.preset : préréglage inconnu « {tostring(preset)} »`)
	end
	return out
end

-- Écrit le préréglage dans Config/Features.Defaults du harnais h, puis Features.reset()
function Flags.apply(h: any, preset: Preset?)
	local values = Flags.preset(preset)
	if values == nil then
		return
	end
	local Features = h:require(FEATURES)
	for key, value in values do
		local default = Features.Defaults[key]
		assert(default ~= nil, `Flags.apply : clé inconnue « {key} »`)
		assert(typeof(value) == typeof(default), `Flags.apply : « {key} » attend un {typeof(default)}`)
		Features.Defaults[key] = value
	end
	Features.reset()
end

-- Harnais dont chaque Harness.new prend le préréglage (pour Bots.boot, Brains.boot, Chaos.boot qui
-- reçoivent le module Harness) : Flags.harness(Harness, "v13") = serveur de la v1.3
function Flags.harness(Harness: any, preset: Preset): any
	return setmetatable({
		new = function(options: any?)
			local o = table.clone(options or {})
			o.flags = preset
			return Harness.new(o)
		end,
	}, { __index = Harness })
end

return Flags
