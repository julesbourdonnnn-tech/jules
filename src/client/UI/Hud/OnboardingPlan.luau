--!strict
-- Hud/OnboardingPlan — règles PURES de l'accueil (GDD §3, §7.4, §10.1), utilisées par
-- OnboardingController. Le serveur (QuestService) décide de la progression (profile.onboarding) ;
-- ces fonctions traduisent l'état observé du profil en :
--   * éléments du HUD affichés (affichage progressif, jamais retirés) ;
--   * UNE instruction à l'écran au plus (clé "onboarding.*", ≤ 4 mots) ;
--   * guidage au sol (empreintes vers les Puffkins, vers la porte, flèche vers les Nebbies, pilier
--     bleu du Rare de Q4) ;
--   * éléments qui pulsent pour attirer l'attention (icône Améliorer avec la main).
-- Étapes : 0 pas commencé, 1-7 = quête Q1-Q7 en cours, 8 = accueil terminé.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Types = require(Shared.Types)

local Plan = {}

Plan.DONE = #Quests.Onboarding + 1 -- 8

export type Facts = {
	step: number, -- profile.onboarding.step
	returning: boolean, -- pas la première session : HUD complet
	parades: number, -- stats.parades
	conga: number, -- upgrades.conga
	stardust: number,
	lineCount: number, -- longueur de la file locale
	lineFull: boolean, -- file pleine
	upgradesOpen: boolean, -- panneau Améliorer ouvert
	canBuyConga: boolean, -- Glow prédit ≥ coût du prochain niveau
	canBuyStride: boolean,
	canBuyPerches: boolean,
	rareTarget: boolean, -- un Rare attrapable est visible (Q4)
}

export type Guide = "toPuffkins" | "toGate" | "toNebbies" | "toRare"

local ALL: { Types.HudElement } = {
	"glow",
	"stardust",
	"line",
	"dash",
	"ping",
	"rail",
	"rail.Upgrades",
	"rail.Collection",
	"rail.Goals",
	"rail.Shop",
	"eventPill",
	"minimap",
	"status",
	"questTracker",
	"crew",
	"settings",
}
Plan.ALL = ALL

-- Tout le HUD est affiché (accueil fini ou joueur qui revient)
function Plan.complete(f: Facts): boolean
	return f.returning or f.step >= Plan.DONE
end

-- Éléments du HUD à afficher pour cet état (ensemble croissant avec la progression)
function Plan.reveals(f: Facts): { Types.HudElement }
	if Plan.complete(f) then
		return table.clone(ALL)
	end
	local out: { Types.HudElement } = { "glow", "line", "dash" }
	local function add(...: Types.HudElement)
		for _, e in { ... } do
			table.insert(out, e)
		end
	end
	-- ~14 s : l'icône Améliorer rejoint le rail après la première parade
	if f.parades >= 1 or f.step >= 2 then
		add("rail", "rail.Upgrades")
	end
	-- ~25 s : le suivi de quête glisse à droite après le premier achat
	if f.conga >= 1 or f.step >= 2 then
		add("questTracker")
	end
	if f.step >= 2 then
		add("eventPill", "settings")
	end
	-- 1-2 min (Q3) : bouclier près du compteur de file, minicarte, pings, équipage
	if f.step >= 3 then
		add("status", "minimap", "ping", "crew", "rail.Goals")
	end
	-- Q4 : la Stardust apparaît (récompense de Q4)
	if f.step >= 4 or f.stardust > 0 then
		add("stardust")
	end
	-- Q4 réussie : l'Atlas se débloque, l'icône Collection rejoint le rail
	if f.step >= 5 then
		add("rail.Collection")
	end
	if f.step >= 6 then
		add("rail.Shop")
	end
	return out
end

-- Instruction à afficher (une seule), nil si aucune
function Plan.hint(f: Facts): string?
	local step = f.step
	if step < 1 or step >= Plan.DONE then
		return nil
	end
	if step == 1 then
		if f.parades < 1 then
			-- 3-8 s : attraper les Puffkins ; ~8 s : retour à la porte. Les Puffkins de bienvenue
			-- n'apparaissent qu'à la première session (QuestService, step 0) : un joueur qui revient
			-- est guidé vers les Nebbies sauvages
			if f.lineFull or f.lineCount >= 3 then
				return "onboarding.goHome"
			end
			return if f.returning then "onboarding.findNebbies" else "onboarding.catch"
		end
		if f.conga < 1 then
			return if f.upgradesOpen then "onboarding.buyConga" else "onboarding.tapUpgrade"
		end
	end
	if f.lineFull then
		return "onboarding.goHome"
	end
	local def = Quests.Onboarding[step]
	if def == nil then
		return nil
	end
	-- quêtes d'achat : n'inviter à acheter que si c'est possible, sinon guider vers les Nebbies
	if def.goal.kind == "upgrade" then
		local affordable = if def.goal.track == "stride" then f.canBuyStride else f.canBuyConga
		if not affordable then
			return "onboarding.findNebbies"
		end
	elseif def.goal.kind == "perches" then
		if not f.canBuyPerches then
			return "onboarding.findNebbies"
		end
	end
	return def.hint
end

-- Guidage au sol (3D), nil si aucun
function Plan.guide(f: Facts): Guide?
	local step = f.step
	if step < 1 or step >= Plan.DONE then
		return nil
	end
	if step == 1 and f.parades < 1 then
		if f.lineFull or f.lineCount >= 3 then
			return "toGate"
		end
		return if f.returning then "toNebbies" else "toPuffkins"
	end
	if f.lineFull then
		return "toGate"
	end
	if step == 1 and f.conga < 1 then
		return nil -- le joueur est invité à toucher Améliorer
	end
	local def = Quests.Onboarding[step]
	if def == nil then
		return nil
	end
	if def.goal.kind == "bankRarity" and f.rareTarget then
		return "toRare"
	end
	if def.goal.kind == "paradeSize" or def.goal.kind == "bankRarity" then
		return "toNebbies"
	end
	if def.goal.kind == "upgrade" or def.goal.kind == "perches" then
		local hint = Plan.hint(f)
		return if hint == "onboarding.findNebbies" then "toNebbies" else nil
	end
	return nil
end

-- Éléments qui doivent pulser (avec la main sur l'icône Améliorer)
function Plan.attention(f: Facts): { [Types.HudElement]: boolean }
	local out: { [Types.HudElement]: boolean } = {}
	local step = f.step
	if step < 1 or step >= Plan.DONE or f.upgradesOpen then
		return out
	end
	local hint = Plan.hint(f)
	if
		hint == "onboarding.tapUpgrade"
		or hint == "onboarding.buyConga"
		or hint == "onboarding.buyStride"
		or hint == "onboarding.perches"
	then
		out["rail.Upgrades"] = true
	end
	return out
end

return Plan
