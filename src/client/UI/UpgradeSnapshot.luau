--!strict
-- UpgradeSnapshot (lot B2, docs/04 §27.7 ; GDD v2.0 §10.8 règle 6 « un seul instantané versionné ») :
-- la SEULE source de l'écran Améliorations et de la puce « Prochain achat » côté client.
--
--   UpgradeSnapshot.start()                 -- idempotent : écoute l'état et UpgradeResult
--   UpgradeSnapshot.current()               -- dernier instantané accepté (gelé), nil avant le premier
--   UpgradeSnapshot.available()             -- vrai tant que l'état du client porte un instantané valide
--   UpgradeSnapshot.apply(snap): boolean    -- accepte un instantané valide de version PLUS GRANDE
--   UpgradeSnapshot.Changed:Connect(fn)     -- une fois par instantané accepté : fn(snap)
--   UpgradeSnapshot.Result:Connect(fn)      -- chaque UpgradeResult valide, APRÈS son instantané : fn(payload)
--   UpgradeSnapshot.AvailableChanged        -- fn(available) quand available() change
--   UpgradeSnapshot.ranchAttribute(name)    -- attribut v2.0 de MON ranch (AscendReady, Helpers…) ou nil
--   UpgradeSnapshot.rebirth(loopReady)      -- renaissance prête : "splorch" | "petit" | "ascend" | nil
--
-- Règles (décisions D1 et D2 du lot B2, notes du lot A2 du 5 novembre) :
--  * le serveur n'ajoute `upgradeSnapshot` à DataSnapshot / DataPatch que si SON interrupteur
--    UpgradesScreen est ouvert : sans la clé, l'écran n'existe pas (aucune instance, aucune intention),
--    et le client ne lit JAMAIS Config/Features pour la v2.0 ;
--  * une version au plus égale à celle montrée est ignorée : l'UpgradeResult et le DataPatch d'une même
--    image portent la MÊME version, le second des deux est donc ignoré quel que soit l'ordre d'arrivée
--    (jamais « Prêt → Il manque → Prêt ») ;
--  * tout est vérifié (version entière ≥ 1, pièces et Confettis finis ≥ 0, niveaux et plafonds entiers
--    de 0 au maximum de CHAQUE identifiant d'UpgradeMath.ids(), r, Record R ≥ r et A dans leurs bornes) ;
--    une charge hostile ou abîmée est ignorée sans aucune trace (ni erreur ni avertissement) ;
--  * UpgradeResult (types.UpgradeResultPayload) : identifiant canonique connu, niveaux dans les bornes,
--    monnaie de la ligne, raison nil ou l'une des 6 clés upgrades.refused.*, instantané valide ; le
--    refus « périmé » est reason == nil et from == to (rien dépensé) : il passe ici comme les autres,
--    l'écran n'en montre rien (règle 12). Le résultat d'un BuyTile ou de l'achat au sol a la même forme :
--    son instantané est appliqué, l'écran ne montre un retour que pour une ligne « en cours ».
-- Les tables rendues sont des copies gelées (table.freeze) : personne ne peut les modifier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Balance = require(Shared.Config.Balance)
local UpgradeMath = require(Shared.Logic.UpgradeMath)
local Prestige = require(Shared.Logic.Prestige)

local Client = script.Parent.Parent
local State = require(Client.Controllers.StateController)
local WorldStateController = require(Client.Controllers.WorldStateController)
local Format = require(Client.UI.Format)

local UpgradeSnapshot = {}

UpgradeSnapshot.Changed = Signal.new() :: Signal.Signal<Types.UpgradeSnapshot>
UpgradeSnapshot.Result = Signal.new() :: Signal.Signal<Types.UpgradeResultPayload>
UpgradeSnapshot.AvailableChanged = Signal.new() :: Signal.Signal<boolean>

-- Clé de l'état du client (DataSnapshot / DataPatch) et remote de la réponse
UpgradeSnapshot.KEY = "upgradeSnapshot"
UpgradeSnapshot.REMOTE = "UpgradeResult"

local IDS = UpgradeMath.ids()
local MAX_LEVEL: { [string]: number } = {}
for _, id in IDS do
	MAX_LEVEL[id] = UpgradeMath.maxLevel(id)
end
local MAX_R = Balance.Prestige.MaxR
local MAX_A = Balance.Prestige.MaxA
local MAX_VERSION = 9007199254740992 -- 2^53 : entier exact (même borne que UpgradeMath.snapshot)

-- Raisons de refus du serveur (EconomyService, lot A2) : clés de texte
UpgradeSnapshot.REASONS = table.freeze({
	"upgrades.refused.coins",
	"upgrades.refused.confetti",
	"upgrades.refused.locked",
	"upgrades.refused.maxed",
	"upgrades.refused.loopCap",
	"upgrades.refused.busy",
})
local REASON_SET: { [string]: boolean } = {}
for _, key in UpgradeSnapshot.REASONS do
	REASON_SET[key] = true
end

local shown: Types.UpgradeSnapshot? = nil
local present = false
local started = false
-- v2.0 (lot B3, D5) : plus petit r vu pendant la séance pour l'Ascension `lowA` (instantanés acceptés) ;
-- une hausse de r à cet A = le premier Petit Splorch de la remontée est déjà fait
local lowA: number? = nil
local lowR = 0

-- =============================================================================================
-- Vérification (pure : aucune trace)
-- =============================================================================================

-- Entier de [lo ; hi] (ni NaN, ni infini, ni décimale)
local function isInt(x: any, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and x >= lo and x <= hi and x % 1 == 0
end

-- Montant fini ≥ 0
local function isAmount(x: any): boolean
	return type(x) == "number" and x == x and x >= 0 and x < math.huge
end

-- Copie gelée d'un instantané valide, nil sinon (champs inconnus ignorés, jamais parcourus)
function UpgradeSnapshot.validate(raw: any): Types.UpgradeSnapshot?
	if type(raw) ~= "table" then
		return nil
	end
	local levelsRaw = rawget(raw, "levels")
	local capsRaw = rawget(raw, "caps")
	if type(levelsRaw) ~= "table" or type(capsRaw) ~= "table" then
		return nil
	end
	local version = rawget(raw, "version")
	local coins = rawget(raw, "coins")
	local confetti = rawget(raw, "confetti")
	local r = rawget(raw, "r")
	local bestR = rawget(raw, "bestR")
	local ascend = rawget(raw, "ascend")
	if not isInt(version, 1, MAX_VERSION) or not isAmount(coins) or not isAmount(confetti) then
		return nil
	end
	if not isInt(r, 0, MAX_R) or not isInt(bestR, 0, MAX_R) or bestR < r or not isInt(ascend, 0, MAX_A) then
		return nil
	end
	local levels: { [string]: number } = {}
	local caps: { [string]: number } = {}
	for _, id in IDS do
		local max = MAX_LEVEL[id]
		local level = rawget(levelsRaw, id)
		local cap = rawget(capsRaw, id)
		if not isInt(level, 0, max) or not isInt(cap, 0, max) then
			return nil
		end
		levels[id] = level
		caps[id] = cap
	end
	return table.freeze({
		coins = coins,
		confetti = confetti,
		levels = table.freeze(levels),
		caps = table.freeze(caps),
		r = r,
		bestR = bestR,
		ascend = ascend,
		version = version,
	})
end

-- Copie gelée d'une réponse UpgradeResult valide, nil sinon
function UpgradeSnapshot.validateResult(raw: any): Types.UpgradeResultPayload?
	if type(raw) ~= "table" then
		return nil
	end
	local id = rawget(raw, "id")
	if type(id) ~= "string" or MAX_LEVEL[id] == nil or UpgradeMath.canonical(id) ~= id then
		return nil
	end
	local max = MAX_LEVEL[id]
	local from = rawget(raw, "from")
	local to = rawget(raw, "to")
	local spent = rawget(raw, "spent")
	if not isInt(from, 0, max) or not isInt(to, from, max) or not isAmount(spent) then
		return nil
	end
	-- un refus (périmé ou non) ne dépense rien
	if to == from and spent ~= 0 then
		return nil
	end
	local currency = rawget(raw, "currency")
	if currency ~= UpgradeMath.currency(id) then
		return nil
	end
	local reason = rawget(raw, "reason")
	if reason ~= nil and (type(reason) ~= "string" or not REASON_SET[reason] or to ~= from) then
		return nil
	end
	local snapshot = UpgradeSnapshot.validate(rawget(raw, "snapshot"))
	if snapshot == nil then
		return nil
	end
	return table.freeze({
		id = id,
		from = from,
		to = to,
		spent = spent,
		currency = currency :: Types.UpgradeCurrency,
		reason = reason :: string?,
		snapshot = snapshot,
	})
end

-- Refus « périmé » : rien acheté, aucune raison (aucun retour visible, la ligne suit l'instantané)
function UpgradeSnapshot.isStale(payload: Types.UpgradeResultPayload): boolean
	return payload.reason == nil and payload.to == payload.from
end

-- =============================================================================================
-- État
-- =============================================================================================

-- Note le r d'un instantané accepté (plus petit r de l'A courant ; remis à zéro quand A change)
local function noteRegain(snap: Types.UpgradeSnapshot)
	if lowA ~= snap.ascend then
		lowA = snap.ascend
		lowR = snap.r
	elseif snap.r < lowR then
		lowR = snap.r
	end
end

-- Accepte un instantané valide de version strictement plus grande que celle montrée (vrai si accepté)
function UpgradeSnapshot.apply(raw: any): boolean
	local snap = UpgradeSnapshot.validate(raw)
	if snap == nil then
		return false
	end
	local cur = shown
	if cur ~= nil and snap.version <= cur.version then
		return false
	end
	shown = snap
	noteRegain(snap)
	UpgradeSnapshot.Changed:Fire(snap)
	return true
end

-- Dernier instantané accepté (nil avant le premier)
function UpgradeSnapshot.current(): Types.UpgradeSnapshot?
	return shown
end

-- Vrai tant que l'état du client porte un instantané valide (interrupteur UpgradesScreen du serveur)
function UpgradeSnapshot.available(): boolean
	return present
end

local function setPresent(on: boolean)
	if present ~= on then
		present = on
		UpgradeSnapshot.AvailableChanged:Fire(on)
	end
end

-- Valeur de la clé `upgradeSnapshot` de l'état (instantané d'arrivée ou patch)
local function onState(value: any)
	if value == nil then
		setPresent(false)
		return
	end
	local snap = UpgradeSnapshot.validate(value)
	if snap == nil then
		return
	end
	local cur = shown
	local fresh = cur == nil or snap.version > cur.version
	if fresh then
		shown = snap
		noteRegain(snap)
	end
	setPresent(true)
	if fresh then
		UpgradeSnapshot.Changed:Fire(snap)
	end
end

-- Réponse du serveur : son instantané d'abord (règle des versions), puis le signal
local function onResult(raw: any)
	local payload = UpgradeSnapshot.validateResult(raw)
	if payload == nil then
		return
	end
	UpgradeSnapshot.apply(payload.snapshot)
	UpgradeSnapshot.Result:Fire(payload)
end

-- Attribut v2.0 de MON ranch (modèle Wobbleton/Ranches/<k> répliqué, posé par le serveur quand son
-- interrupteur est ouvert : AscendReady, Helpers, HelperMode, PetitSplorchAt…) ; nil sans monde, sans
-- ranch ou sans l'attribut. Jamais d'erreur (monde pas encore construit, attribut hostile : nil)
function UpgradeSnapshot.ranchAttribute(name: string): any
	if type(name) ~= "string" then
		return nil
	end
	local ok, slot = pcall(WorldStateController.mySlot)
	if not ok or type(slot) ~= "number" or slot <= 0 then
		return nil
	end
	local world = workspace:FindFirstChild("Wobbleton")
	local list = world and world:FindFirstChild("Ranches")
	local model = list and list:FindFirstChild(Format.id(slot))
	if model == nil then
		return nil
	end
	local okAttr, value = pcall(function()
		return model:GetAttribute(name)
	end)
	return if okAttr then value else nil
end

export type Rebirth = "splorch" | "petit" | "ascend"

-- Renaissance prête (lot B2, D16, D16b, D17, D32) : `loopReady` = le plus gros squishy atteint
-- l'objectif de la boucle (aperçu du Grand Splorch). Pendant une remontée (instantané : A ≥ 1 et
-- r < Record R), le prestige de boucle est un Petit Splorch ; `first` = premier de la remontée (il
-- passe par l'aperçu). Lot B3, D5 (relecture du lot B2) : premier ⇔ r ≤ Prestige.startR(A, Tremplin)
-- ET aucune hausse de r vue pendant la séance à cet A (un Tremplin acheté PENDANT la remontée monte le
-- départ de l'Ascension suivante, pas r : l'ancien test r == startR le manquait ; après une reconnexion
-- en pleine remontée avec un Tremplin acheté, un aperçu de trop au plus). Sinon, la Jelly Ascend quand
-- le ranch porte AscendReady (et qu'aucun prestige de boucle n'est prêt : le Grand Splorch d'abord, GDD
-- §10.7.2). Sans instantané : la v1.3 (Grand Splorch prêt ou rien)
function UpgradeSnapshot.rebirth(loopReady: boolean): (Rebirth?, boolean)
	local snap = shown
	if not present or snap == nil then
		return if loopReady == true then "splorch" else nil, false
	end
	if loopReady == true then
		if snap.ascend >= 1 and snap.r < snap.bestR then
			local springboard = snap.levels.springboard or 0
			local climbed = lowA == snap.ascend and snap.r > lowR
			return "petit", snap.r <= Prestige.startR(snap.ascend, springboard) and not climbed
		end
		return "splorch", false
	end
	if UpgradeSnapshot.ranchAttribute("AscendReady") == true then
		return "ascend", false
	end
	return nil, false
end

-- Remontée vers le record (instantané : A ≥ 1 et r < Record R ; D1, D32) ; faux sans instantané
function UpgradeSnapshot.regain(): boolean
	local snap = shown
	return present and snap ~= nil and snap.ascend >= 1 and snap.r < snap.bestR
end

-- Écoute l'état du client et UpgradeResult (une seule fois, quel que soit le nombre d'appels)
function UpgradeSnapshot.start()
	if started then
		return
	end
	started = true
	State.observe(UpgradeSnapshot.KEY, function(value: any)
		onState(value)
	end)
	Net.event(UpgradeSnapshot.REMOTE).OnClientEvent:Connect(onResult)
end

return UpgradeSnapshot
