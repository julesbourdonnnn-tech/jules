--!strict
-- Hud/OnboardingPlan — règles PURES de l'accueil (GDD §3, §7.4, §10.1), utilisées par
-- OnboardingController. Le serveur (QuestService) décide de la progression (profile.onboarding) ;
-- ces fonctions traduisent l'état observé du profil en :
--   * éléments du HUD affichés (affichage progressif, jamais retirés) ;
--   * UNE instruction à l'écran au plus (clé "onboarding.*", ≤ 4 mots) ;
--   * guidage au sol (empreintes vers les Puffkins, vers la porte, flèche vers les Nebbies, pilier
--     bleu du Rare de Q4, Nebby météo ou Comète de Q6) ;
--   * éléments qui pulsent pour attirer l'attention (icône Améliorer avec la main, pastille
--     d'événement quand Q6 attend la prochaine météo).
-- L'instruction affichée doit toujours être réalisable MAINTENANT (GDD §3) : rentrer dès que la
-- file contient de quoi réussir la quête, chercher des Nebbies quand les Puffkins ont disparu ou
-- que le Glow manque, attendre la météo (compte à rebours) quand aucun Nebby météo n'existe.
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
	-- Faits facultatifs : nil = inconnu (règle d'origine appliquée)
	goalInLine: boolean?, -- la file locale contient déjà de quoi réussir la quête (Rare pour Q4)
	puffkinsLeft: number?, -- Puffkins de bienvenue (personnels) encore attrapables
	weatherActive: boolean?, -- fenêtre météo en cours, avec une forme météo
	weatherTarget: boolean?, -- un Nebby météo attrapable est connu (Q6)
	cometActive: boolean?, -- Comète au sol ou portée (Q6 accepte aussi la Comète)
}

export type Guide = "toPuffkins" | "toGate" | "toNebbies" | "toRare" | "toWeather" | "toComet"

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

-- La file contient déjà ce que demande la quête : il faut rentrer encaisser, pas attraper encore
local function goalInLine(f: Facts, def: Quests.OnboardingQuest): boolean
	local goal = def.goal
	if goal.kind == "paradeSize" then
		local n = goal.n
		return f.goalInLine == true or (type(n) == "number" and n > 0 and f.lineCount >= n)
	elseif goal.kind == "bankRarity" then
		return f.goalInLine == true
	end
	return false
end

-- Q6 : faits météo / Comète connus (sinon instruction d'origine, sans guidage)
local function eventFactsKnown(f: Facts): boolean
	return f.weatherActive ~= nil or f.weatherTarget ~= nil or f.cometActive ~= nil
end

-- Avant la toute première parade : les Puffkins de bienvenue ont disparu (réinitialisation, mort,
-- durée de vie écoulée) ou n'existent pas (joueur qui revient) → Nebbies sauvages
local function puffkinsGone(f: Facts): boolean
	return f.returning or f.puffkinsLeft == 0
end

-- Après la première parade, Conga +1 pas encore payable (parade de 1-2 Puffkins seulement) : on
-- remplit la file au lieu d'ouvrir une carte grisée. Règle active quand le contrôleur observe le
-- terrain (puffkinsLeft fourni) ; sans ce fait, l'invitation d'origine à toucher Améliorer.
local function congaShort(f: Facts): boolean
	return f.puffkinsLeft ~= nil and not f.canBuyConga
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
			return if puffkinsGone(f) then "onboarding.findNebbies" else "onboarding.catch"
		end
		if f.conga < 1 then
			if congaShort(f) then
				return if f.lineFull then "onboarding.goHome" else "onboarding.findNebbies"
			end
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
	if goalInLine(f, def) then
		return "onboarding.goHome"
	end
	if def.goal.kind == "weatherOrComet" and eventFactsKnown(f) then
		if f.weatherTarget or f.weatherActive then
			return def.hint
		end
		return if f.cometActive then "onboarding.joinComet" else "onboarding.waitWeather"
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
		return if puffkinsGone(f) then "toNebbies" else "toPuffkins"
	end
	if f.lineFull then
		return "toGate"
	end
	if step == 1 and f.conga < 1 then
		-- invité à toucher Améliorer ; Glow insuffisant : vers les Nebbies (Puffkins restants d'abord)
		return if congaShort(f) then "toNebbies" else nil
	end
	local def = Quests.Onboarding[step]
	if def == nil then
		return nil
	end
	if goalInLine(f, def) then
		return "toGate"
	end
	if def.goal.kind == "weatherOrComet" then
		if f.weatherTarget then
			return "toWeather"
		elseif f.cometActive then
			return "toComet"
		elseif f.weatherActive then
			return "toNebbies" -- fenêtre ouverte : les formes météo apparaissent parmi les Nebbies
		end
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
	elseif hint == "onboarding.waitWeather" then
		out.eventPill = true -- le compte à rebours de la prochaine météo pulse
	end
	return out
end

return Plan
