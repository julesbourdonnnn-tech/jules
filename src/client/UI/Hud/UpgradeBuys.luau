--!strict
-- Hud/UpgradeBuys (lot B2, étape 3 ; décisions D9 et D10 du plan ; docs/04 §27.5, §27.8 règles 12 et
-- 13 ; GDD v2.0 §10.7.6, §10.7.8, §10.7.9) : achats de l'écran Améliorations, module PUR (horloge et
-- envoi injectés : aucune Instance, aucun service, aucune connexion).
--
--   local buys = UpgradeBuys.new({ now = Clock.now, send = Widgets.send })
--   buys:buy(id, mode, expectedLevel): boolean  -- BuyUpgrade valide seulement ; ligne « en cours »
--   buys:state(id)                               -- nil | "busy" | "retry"
--   buys:result(payload): Feedback               -- réponse du serveur (déjà vérifiée) → UN retour, ou rien
--   buys:step(): { string }                      -- délais : identifiants passés à « Réessaie »
--   buys:metric(kind, value)                     -- ClientMetric par le limiteur unique (D10)
--   buys:clear()                                 -- écran fermé : achats en cours oubliés
--   buys:busy(): boolean                         -- reste-t-il quelque chose à suivre ?
--
-- Règles :
--  * jamais une intention invalide : identifiant canonique connu (UpgradeMath, 24 caractères au plus),
--    mode 1, 10 ou 0 (Max), niveau attendu entier de 0 au maximum de la ligne (64 au plus) ; sinon rien
--    n'est envoyé (le serveur ne répondrait pas : la ligne resterait « en cours ») ;
--  * une ligne en attente par identifiant canonique pendant Balance.Upgrades.PendingSeconds (3 s) :
--    « en cours » (appuis ignorés), puis « Réessaie » (le même maintien renvoie l'achat, D9) ; chaque
--    délai dépassé envoie ClientMetric("upgradeTimeout", 0) ; une réponse tardive est appliquée avec
--    exactement un retour ; un renvoi compte une demande de plus (la ligne quitte l'attente quand toutes
--    ses demandes ont une réponse) ;
--  * refus « périmé » (reason == nil et from == to : rien dépensé) : aucun retour, la ligne quitte
--    l'attente et suit l'instantané (règle 12) ; réponse sans ligne en attente (BuyTile, achat au sol,
--    écran fermé puis rouvert) : seulement son instantané (appliqué par UI/UpgradeSnapshot) ;
--  * retour : niveaux et montant DU SERVEUR (to − from, spent) ou sa raison (upgrades.refused.*),
--    jamais un calcul du client ; « n sur m » pour un ×10 acheté en partie ;
--  * limiteur de ClientMetric (D10) : au plus 1 envoi toutes les 5 s (débit de Config/Intents), le
--    dernier upgradeMode seulement (les changements rapprochés se fondent), un délai dépassé passe
--    avant, 20 au plus par séance (le serveur n'en compte pas plus) ; un envoi refusé par le débit du
--    client reste en file.
-- Horloge recalée en arrière : une attente plus « jeune » que maintenant est traitée comme dépassée
-- (jamais une ligne bloquée « en cours ») ; le limiteur repart de l'heure courante.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Types = require(Shared.Types)
local Balance = require(Shared.Config.Balance)
local UpgradeMath = require(Shared.Logic.UpgradeMath)

local UpgradeBuys = {}
UpgradeBuys.__index = UpgradeBuys

export type Kind = "bought" | "refused" | "none"
export type Feedback = {
	kind: Kind,
	id: string,
	levels: number, -- niveaux achetés (to − from du serveur)
	spent: number, -- montant débité par le serveur
	currency: Types.UpgradeCurrency?,
	reason: string?, -- clé upgrades.refused.* du serveur
	requested: number?, -- niveaux demandés (×10 : 10 ; ×1 : 1 ; Max : nil)
	partial: boolean, -- ×10 acheté en partie (« 4 sur 10 »)
}

type Entry = {
	at: number, -- heure du dernier envoi
	mode: number,
	expected: number,
	outstanding: number, -- demandes sans réponse
	timedOut: boolean, -- délai du dernier envoi dépassé (métrique envoyée)
}

export type Options = {
	now: () -> number,
	send: (name: string, ...any) -> boolean,
	pendingSeconds: number?,
}

type BuysData = {
	_now: () -> number,
	_send: (name: string, ...any) -> boolean,
	_pending: number,
	_entries: { [string]: Entry },
	_timeouts: number, -- délais dépassés pas encore envoyés
	_mode: number?, -- dernier mode choisi pas encore envoyé
	_sent: number, -- ClientMetric envoyés dans la séance
	_lastMetric: number?,
}

export type Buys = typeof(setmetatable({} :: BuysData, UpgradeBuys))

-- Débit et plafond des métriques du client (Config/Intents.ClientMetric : 1 / 5 s ; serveur : 20)
UpgradeBuys.METRIC_EVERY = 5
UpgradeBuys.METRIC_MAX = 20
UpgradeBuys.MODES = table.freeze({ 1, 10, 0 })
local MODE_OK: { [number]: boolean } = { [1] = true, [10] = true, [0] = true }
local MAX_ID_LENGTH = 24 -- Config/Intents.BuyUpgrade.id
local MAX_EXPECTED = 64 -- Config/Intents.BuyUpgrade.expectedLevel

local NONE: Kind = "none"

-- =============================================================================================
-- Vérifications (pures)
-- =============================================================================================

local function isInt(x: any, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and x >= lo and x <= hi and x % 1 == 0
end

-- Intention BuyUpgrade exacte (identifiant canonique, mode, niveau attendu lisible)
function UpgradeBuys.valid(id: any, mode: any, expectedLevel: any): boolean
	if type(id) ~= "string" or #id == 0 or #id > MAX_ID_LENGTH then
		return false
	end
	if UpgradeMath.canonical(id) ~= id then
		return false
	end
	if type(mode) ~= "number" or not MODE_OK[mode] then
		return false
	end
	local max = math.min(UpgradeMath.maxLevel(id), MAX_EXPECTED)
	return isInt(expectedLevel, 0, max)
end

-- =============================================================================================
-- Objet
-- =============================================================================================

function UpgradeBuys.new(opts: Options): Buys
	local pending = opts.pendingSeconds
	if type(pending) ~= "number" or pending ~= pending or pending <= 0 then
		pending = Balance.Upgrades.PendingSeconds
	end
	local self = setmetatable({
		_now = opts.now,
		_send = opts.send,
		_pending = pending :: number,
		_entries = {},
		_timeouts = 0,
		_mode = nil,
		_sent = 0,
		_lastMetric = nil,
	}, UpgradeBuys)
	return self
end

local function nowOf(self: Buys): number
	local ok, t = pcall(self._now)
	if ok and type(t) == "number" and t == t then
		return t
	end
	return 0
end

-- Âge d'une attente dépassé ? (horloge recalée en arrière : oui)
local function expired(self: Buys, e: Entry, now: number): boolean
	local age = now - e.at
	return age < 0 or age >= self._pending
end

-- Envoie BuyUpgrade (vrai si envoyé) : intention valide, ligne libre ou « Réessaie »
function UpgradeBuys.buy(self: Buys, id: string, mode: number, expectedLevel: number): boolean
	if not UpgradeBuys.valid(id, mode, expectedLevel) then
		return false
	end
	local now = nowOf(self)
	local e = self._entries[id]
	if e ~= nil and not expired(self, e, now) then
		return false -- « en cours » : appui ignoré
	end
	local ok, sent = pcall(self._send, "BuyUpgrade", id, mode, expectedLevel)
	if not ok or sent ~= true then
		return false
	end
	if e == nil then
		self._entries[id] =
			{ at = now, mode = mode, expected = expectedLevel, outstanding = 1, timedOut = false }
	else
		e.at = now
		e.mode = mode
		e.expected = expectedLevel
		e.outstanding += 1
		e.timedOut = false
	end
	return true
end

-- État d'attente d'un identifiant canonique
function UpgradeBuys.state(self: Buys, id: string): ("busy" | "retry")?
	local e = self._entries[id]
	if e == nil then
		return nil
	end
	return if expired(self, e, nowOf(self)) then "retry" else "busy"
end

-- Identifiants en attente (specs)
function UpgradeBuys.pendingIds(self: Buys): { string }
	local out: { string } = {}
	for id in self._entries do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function feedback(kind: Kind, id: string): Feedback
	return {
		kind = kind,
		id = id,
		levels = 0,
		spent = 0,
		currency = nil,
		reason = nil,
		requested = nil,
		partial = false,
	}
end

-- Réponse du serveur (charge déjà vérifiée par UpgradeSnapshot.validateResult) → un retour, ou rien
function UpgradeBuys.result(self: Buys, payload: Types.UpgradeResultPayload): Feedback
	local id = payload.id
	local e = self._entries[id]
	if e == nil then
		-- BuyTile, achat au sol, demande d'avant la fermeture : seulement l'instantané
		return feedback(NONE, id)
	end
	e.outstanding -= 1
	if e.outstanding <= 0 then
		self._entries[id] = nil
	end
	if payload.reason == nil and payload.to == payload.from then
		-- refus périmé : muet (règle 12)
		return feedback(NONE, id)
	end
	local fb = feedback(if payload.reason ~= nil then "refused" else "bought", id)
	fb.currency = payload.currency
	if payload.reason ~= nil then
		fb.reason = payload.reason
		return fb
	end
	fb.levels = payload.to - payload.from
	fb.spent = payload.spent
	fb.requested = if e.mode == 10 then 10 elseif e.mode == 1 then 1 else nil
	fb.partial = e.mode == 10 and fb.levels < 10
	return fb
end

-- Écran fermé : achats en cours oubliés (la réouverture est neuve) ; le limiteur garde sa file
function UpgradeBuys.clear(self: Buys)
	table.clear(self._entries)
end

-- =============================================================================================
-- Métriques du client (D10)
-- =============================================================================================

local function flush(self: Buys)
	if self._sent >= UpgradeBuys.METRIC_MAX then
		self._timeouts = 0
		self._mode = nil
		return
	end
	if self._timeouts <= 0 and self._mode == nil then
		return
	end
	local now = nowOf(self)
	local last = self._lastMetric
	if last ~= nil and now >= last and now - last < UpgradeBuys.METRIC_EVERY then
		return
	end
	local kind, value
	if self._timeouts > 0 then
		kind, value = "upgradeTimeout", 0
	else
		kind, value = "upgradeMode", self._mode :: number
	end
	local ok, sent = pcall(self._send, "ClientMetric", kind, value)
	if not ok or sent ~= true then
		return -- débit du client : reste en file
	end
	self._sent += 1
	self._lastMetric = now
	if kind == "upgradeTimeout" then
		self._timeouts -= 1
	else
		self._mode = nil
	end
end

-- Met une métrique en file : « upgradeMode » (1, 10 ou 0 ; le dernier compte), « upgradeTimeout »
function UpgradeBuys.metric(self: Buys, kind: string, value: number?)
	if self._sent >= UpgradeBuys.METRIC_MAX then
		return
	end
	if kind == "upgradeTimeout" then
		self._timeouts = math.min(self._timeouts + 1, UpgradeBuys.METRIC_MAX - self._sent)
	elseif kind == "upgradeMode" then
		if type(value) ~= "number" or not MODE_OK[value] then
			return
		end
		self._mode = value
	else
		return
	end
	flush(self)
end

-- Métriques envoyées dans la séance (specs, Diagnostics)
function UpgradeBuys.metricsSent(self: Buys): number
	return self._sent
end

-- =============================================================================================
-- Boucle
-- =============================================================================================

-- Délais : chaque attente qui dépasse 3 s passe à « Réessaie » (une métrique upgradeTimeout) ; rend
-- les identifiants qui viennent de changer d'état ; vide la file des métriques quand le débit le permet
function UpgradeBuys.step(self: Buys): { string }
	local now = nowOf(self)
	local changed: { string } = {}
	for id, e in self._entries do
		if not e.timedOut and expired(self, e, now) then
			e.timedOut = true
			table.insert(changed, id)
		end
	end
	table.sort(changed)
	for _ = 1, #changed do
		UpgradeBuys.metric(self, "upgradeTimeout", 0)
	end
	flush(self)
	return changed
end

-- Reste-t-il une attente ou une métrique en file ?
function UpgradeBuys.busy(self: Buys): boolean
	return next(self._entries) ~= nil or self._timeouts > 0 or self._mode ~= nil
end

return UpgradeBuys
