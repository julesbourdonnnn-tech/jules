--!strict
-- Outils communs du paquet client-world (dossier d'aide src/client/World, docs/04 §2) :
--   * appels protégés vers les modules des autres paquets (un stub « TODO (…) » du contrat rend le
--     repli sans bruit ; une vraie erreur est relancée UNE fois par appelant dans un fil à part, pour
--     que ScriptContext.Error la voie : jamais une erreur avalée, jamais un rendu planté) ;
--   * intentions envoyées au débit CLIENT de Config/Intents (seau à jetons sur l'horloge Clock) ;
--   * lecture sûre des charges utiles (nombres finis bornés, chaînes, tables) ;
--   * textes : clés de Strings vérifiées avant traduction, noms d'espèces et alias d'un nom caché.
-- Ne dépend que du socle et de Shared : utilisable par chaque contrôleur du paquet, à tout rang.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Net = require(Shared.Net)
local Clock = require(Shared.Util.Clock)
local Intents = require(Shared.Config.Intents)
local Species = require(Shared.Config.Species)
local Mutations = require(Shared.Config.Mutations)
local Strings = require(Shared.Localization.Strings)
local BigNumber = require(Shared.Logic.BigNumber)
local Hash = require(Shared.Logic.Hash)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)

local Util = {}

-- Marque d'une erreur de stub du contrat (« TODO » suivi du paquet entre parenthèses). Tous les paquets
-- sont livrés : la marque ne sert plus qu'au rapport d'intégration (liste vide attendue par Boot et Soak).
local STUB_MARK = "TODO" .. "("

local MAX_NUMBER = 1e300

-- =============================================================================================
-- Appels protégés
-- =============================================================================================

local reported: { [string]: boolean } = {}

-- Relance une erreur attrapée dans un fil à part (ScriptContext.Error la voit ; l'appelant continue)
function Util.raise(where: string, text: string)
	if reported[where] then
		return
	end
	reported[where] = true
	task.spawn(error, "[world] " .. where .. " : " .. text, 0)
end

-- Appelle fn(...) sous pcall : un stub du contrat rend `fallback` ; une autre erreur est signalée une
-- fois par `where` puis rend aussi `fallback`
function Util.safe<T>(where: string, fallback: T, fn: any, ...: any): T
	if type(fn) ~= "function" then
		return fallback
	end
	local ok, result = pcall(fn, ...)
	if ok then
		if result == nil then
			return fallback
		end
		return result
	end
	local text = tostring(result)
	if string.find(text, STUB_MARK, 1, true) == nil then
		Util.raise(where, text)
	end
	return fallback
end

-- Exécute fn(...) sous pcall sans valeur de retour (handlers de remotes, étapes d'une image)
function Util.guard(where: string, fn: any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		Util.raise(where, tostring(err))
	end
end

-- =============================================================================================
-- Lecture sûre
-- =============================================================================================

function Util.finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Nombre fini borné, sinon `default`
function Util.num(x: any, default: number, min: number?, max: number?): number
	if not Util.finite(x) then
		return default
	end
	local v = x :: number
	local lo = if min ~= nil then min else -MAX_NUMBER
	local hi = if max ~= nil then max else MAX_NUMBER
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

-- Entier fini dans [min ; max], sinon nil
function Util.int(x: any, min: number, max: number): number?
	if not Util.finite(x) or x % 1 ~= 0 or x < min or x > max then
		return nil
	end
	return x :: number
end

function Util.str(x: any, default: string, maxLen: number?): string
	if type(x) ~= "string" then
		return default
	end
	local limit = maxLen or 200
	if #x > limit then
		return string.sub(x, 1, limit)
	end
	return x
end

function Util.vec(x: any): boolean
	return typeof(x) == "Vector3" and Util.finite(x.X) and Util.finite(x.Y) and Util.finite(x.Z)
end

-- =============================================================================================
-- Intentions au débit du client
-- =============================================================================================

local buckets: { [string]: { tokens: number, at: number } } = {}
local remotes: { [string]: RemoteEvent } = {}

-- Seau à jetons au débit de Config/Intents (calls par seconds) : vrai si l'envoi est permis
function Util.allow(name: string): boolean
	local def = (Intents :: any)[name]
	local rate = if type(def) == "table" then def.rate else nil
	if type(rate) ~= "table" then
		return true
	end
	local calls = Util.num(rate[1], 1, 1, 1000)
	local seconds = Util.num(rate[2], 1, 0.01, 3600)
	local now = Clock.now()
	local b = buckets[name]
	if b == nil then
		b = { tokens = calls, at = now }
		buckets[name] = b
	end
	local elapsed = now - b.at
	if elapsed < 0 then
		elapsed = 0 -- décalage d'horloge en arrière : on ne crédite rien
	end
	b.tokens = math.min(calls, b.tokens + elapsed * calls / seconds)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Envoie une intention (débit client respecté) ; vrai si elle est partie
function Util.send(name: string, ...: any): boolean
	if not Util.allow(name) then
		return false
	end
	local remote = remotes[name]
	if remote == nil then
		local ok, found = pcall(Net.event, name)
		if not ok or found == nil then
			return false
		end
		remote = found
		remotes[name] = found
	end
	local ok, err = pcall(remote.FireServer, remote, ...)
	if not ok then
		Util.raise("send:" .. name, tostring(err))
		return false
	end
	return true
end

-- Remote écouté (nil si introuvable) : jamais d'attente infinie (Net borne l'attente)
function Util.remote(name: string): RemoteEvent?
	local ok, found = pcall(Net.event, name)
	if ok then
		return found
	end
	return nil
end

function Util.unreliable(name: string): UnreliableRemoteEvent?
	local ok, found = pcall(Net.unreliable, name)
	if ok then
		return found
	end
	return nil
end

-- Remet à zéro les seaux (specs)
function Util._reset()
	buckets = {}
	remotes = {}
	reported = {}
end

-- =============================================================================================
-- Textes
-- =============================================================================================

local function known(key: string): boolean
	local en = (Strings :: any).en
	return type(en) == "table" and type(en[key]) == "string"
end

-- Traduction d'une clé connue (texte vide pour une clé inconnue : aucun avertissement)
function Util.t(key: string, vars: { [string]: any }?): string
	if type(key) ~= "string" or not known(key) then
		return ""
	end
	local ok, text = pcall(Prefs.t, key, vars)
	if ok and type(text) == "string" then
		return text
	end
	return ""
end

-- Nombre abrégé dans la langue du joueur (« 1,2 K »)
function Util.number(n: number): string
	local ok, text = pcall(BigNumber.abbreviate, Util.num(n, 0, 0), Prefs.language())
	return if ok and type(text) == "string" then text else "0"
end

-- Nom traduit d'une espèce (repli : nom de la configuration, ou vide pour une espèce inconnue)
function Util.speciesName(id: any): string
	local def = if type(id) == "number" then Species.ById[id] else nil
	if def == nil then
		return ""
	end
	local text = Util.t("species." .. def.key)
	return if text ~= "" then text else def.name
end

-- Clé d'une mutation (« flop », « glitch »…) ou ""
function Util.mutationKey(id: any): string
	local def = if type(id) == "number" then Mutations.ById[id] else nil
	return if def then def.key else ""
end

-- Nom affiché d'un joueur : nom donné, sinon alias « Squishy Fan #NNNN » (nom caché)
function Util.displayName(name: any, userId: any): string
	if type(name) == "string" and name ~= "" then
		return Util.str(name, "", 40)
	end
	local id = Util.num(userId, 0, 0)
	local ok, alias = pcall(Hash.alias, id)
	return Util.t("name.alias", { n = if ok then alias else 0 })
end

-- Joueur local (nil pendant un arrêt)
function Util.localPlayer(): Player?
	return Players.LocalPlayer
end

-- Racine du personnage local (nil si absent, mort ou en réapparition)
function Util.localRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

return Util
