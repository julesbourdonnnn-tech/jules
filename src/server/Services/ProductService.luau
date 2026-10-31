--!strict
-- ProductService — paquet « economy » (docs/04-architecture.md §11.11).
-- Effets de TOUS les passes et produits, branchés sur MonetizationService (aucun ProcessReceipt ici).
-- Clé de profil : starterKit.
-- Responsabilités :
--   * Init : MonetizationService.registerProduct pour chaque produit de Config/Monetization qui a un
--     effet connu (idleSeconds, stardust, serverBoostSeconds, species, style, boostSeconds), même à
--     id 0 ; chaque handler retourne true seulement si l'effet est appliqué (profil chargé) ;
--     MonetizationService gère l'idempotence des reçus et la sauvegarde
--   * Glow : EconomyService.addGlowSeconds (montant calculé AU MOMENT DE L'ATTRIBUTION, minimum
--     minGlow) ; GlowParty : EventService.queueGlowParty(buyer, 600) — jamais refusée : un reçu payé
--     est toujours honoré, même au-delà de la file de 60 min — + bannière glowParty + Feedback
--     glowPartyQueued ; StardustJar : +400 ; StarterKit : 3 Rares (AtlasService), style comet_tail
--     (NestService.unlock), boost personnel 20 min, profile.starterKit = true (une seconde vente
--     éventuelle est quand même honorée)
--   * attribution ATOMIQUE vis-à-vis du reçu : false seulement AVANT la première mutation (produit
--     inconnu, profil absent, joueur parti, file de Glow Party indisponible) ; ensuite chaque effet
--     est protégé (pcall + warn + Analytics ProductEffectFailed_<clé>) et grant retourne TOUJOURS
--     true : MonetizationService enregistre le reçu, Roblox ne redélivre jamais des effets déjà
--     appliqués (un effet en échec est perdu plutôt que les autres accordés deux fois)
--   * passes (MonetizationService.PassGranted, y compris à l'arrivée, ET PassRevoked : remboursé ou
--     plus possédé) : VIP Star / Double Glow → EconomyService.settle (taux enregistré) + refreshRate ;
--     Extra Perches / Stash Plus → AtlasService.refreshPerches ; Night Shift, Conga Styles : lus
--     dynamiquement (rien à stocker)
--   * « Merci ! » (Celebrate "purchase") et Analytics Pass_<clé> seulement pour un achat en jeu
--     CONFIRMÉ par Roblox (MonetizationService.PassPurchased) : PromptGamePassPurchaseFinished n'est
--     qu'un indice qu'un exploit peut émettre
--   * Celebrate "purchase" (pluie de pièces, « Merci ! ») ; Analytics Product_<clé>
-- GDD : §8.1-§8.3, §4.17 (Glow Party), §14.2.
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService,
-- EventService, Config/{Monetization,Nebbies}, Signals, Util/Notify, Util/Analytics, Shared/Util/Clock,
-- Economy/PassEffects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Nebbies = require(Shared.Config.Nebbies)
local Formulas = require(Shared.Logic.Formulas)
local Clock = require(Shared.Util.Clock)

local Server = script.Parent.Parent
local Notify = require(Server.Util.Notify)
local Analytics = require(Server.Util.Analytics)
local PassEffects = require(Server.Economy.PassEffects)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)
local EconomyService = require(script.Parent.EconomyService)
local AtlasService = require(script.Parent.AtlasService)
local EventService = require(script.Parent.EventService)

local ProductService = {}

-- Champs d'effet reconnus d'un produit (Config/Monetization.ProductDef)
local EFFECT_FIELDS = { "idleSeconds", "stardust", "serverBoostSeconds", "species", "style", "boostSeconds" }

local function hasEffect(def: Monetization.ProductDef): boolean
	for _, field in EFFECT_FIELDS do
		if (def :: any)[field] ~= nil then
			return true
		end
	end
	return false
end

-- Pass accordé OU retiré (possession lue dynamiquement par PassEffects) : effets recalculés
local function onPassChanged(player: Player, passKey: string)
	if PassEffects.passHas(passKey, "glowBonus") or PassEffects.passHas(passKey, "glowMult") then
		-- règle au taux enregistré (avant le changement) puis recalcule M
		EconomyService.settle(player)
		EconomyService.refreshRate(player)
	end
	if PassEffects.passHas(passKey, "extraPerches") or PassEffects.passHas(passKey, "stashSize") then
		AtlasService.refreshPerches(player)
	end
end

-- Achat en jeu confirmé par UserOwnsGamePassAsync : « Merci ! » et analytique de revenus
local function onPassPurchased(player: Player, passKey: string)
	Notify.celebrate(player, "purchase", { pass = passKey })
	Analytics.event(player, `Pass_{passKey}`, 1)
end

-- Exécute un effet d'un produit déjà payé : une erreur est signalée, jamais propagée
local function applyEffect(player: Player, productKey: string, effect: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[ProductService] effet {effect} du produit {productKey} en échec pour {player.Name} :`, err)
		Analytics.event(player, `ProductEffectFailed_{productKey}`, 1)
	end
end

function ProductService.Init()
	for key, def in Monetization.Products do
		if hasEffect(def) then
			MonetizationService.registerProduct(
				key,
				function(player: Player, _data: { [string]: any }): boolean
					return ProductService.grant(player, key)
				end
			)
		end
	end
end

function ProductService.Start()
	MonetizationService.PassGranted:Connect(onPassChanged)
	MonetizationService.PassRevoked:Connect(onPassChanged)
	-- « Merci ! » seulement pour un pass acheté en jeu et vérifié (PassGranted est aussi émis à
	-- l'arrivée ; le signal brut du client n'est qu'un indice)
	MonetizationService.PassPurchased:Connect(onPassPurchased)
end

-- Glow qu'accorderait maintenant un produit Glow (affichage « ≈ » côté client : même calcul)
function ProductService.glowAmount(player: Player, productKey: string): number
	local def = Monetization.Products[productKey]
	if def == nil or def.idleSeconds == nil then
		return 0
	end
	return Formulas.glowForSeconds(EconomyService.idleRate(player), def.idleSeconds, def.minGlow)
end

-- Applique l'effet d'un produit (handler partagé, exposé pour les tests) ; true si le reçu doit être
-- enregistré. false seulement tant que RIEN n'a été accordé (Roblox représentera le reçu) ; après
-- la première mutation, toujours true : une redélivrance accorderait deux fois les effets réussis.
function ProductService.grant(player: Player, productKey: string): boolean
	local def = Monetization.Products[productKey]
	if def == nil or not hasEffect(def) then
		return false
	end
	local data = DataService.get(player)
	if not data or player.Parent == nil then
		return false
	end
	local sku = `Product_{productKey}`

	-- effet externe d'abord : s'il échoue, rien n'est accordé et Roblox représentera le reçu
	local partySeconds = def.serverBoostSeconds
	if partySeconds ~= nil and partySeconds > 0 then
		local queued, endsAt = pcall(EventService.queueGlowParty, player, partySeconds)
		if not queued then
			warn(
				`[ProductService] Glow Party de {player.Name} non mise en file (reçu représenté) :`,
				endsAt
			)
			return false
		end
		-- à partir d'ici, le reçu est TOUJOURS enregistré : chaque effet est protégé
		applyEffect(player, productKey, "glowPartyNotice", function()
			local remaining = if type(endsAt) == "number" and endsAt == endsAt
				then math.max(endsAt - Clock.now(), partySeconds)
				else partySeconds
			Notify.banner("glowParty", {
				userId = player.UserId,
				name = player.DisplayName,
				minutes = math.ceil(partySeconds / 60),
			}, player)
			Notify.feedback(
				player,
				"feedback.glowPartyQueued",
				{ minutes = math.ceil(remaining / 60) },
				"reward"
			)
		end)
	end

	local idleSeconds = def.idleSeconds
	if idleSeconds ~= nil then
		applyEffect(player, productKey, "glow", function()
			EconomyService.addGlowSeconds(player, idleSeconds, sku, def.minGlow)
		end)
	end
	local stardust = def.stardust
	if stardust ~= nil then
		applyEffect(player, productKey, "stardust", function()
			EconomyService.addStardust(player, stardust, sku, "IAP")
		end)
	end
	local species = def.species
	if species ~= nil then
		applyEffect(player, productKey, "nebbies", function()
			local codes = {}
			for _, s in species do
				if Nebbies.Species[s] ~= nil then
					table.insert(codes, Nebbies.pack(s, 0, 0))
				end
			end
			if #codes > 0 then
				AtlasService.addNebbies(player, codes, "product")
			end
		end)
	end
	local style = def.style
	if style ~= nil then
		applyEffect(player, productKey, "style", function()
			NestService.unlock(player, "styles", style)
		end)
	end
	local boostSeconds = def.boostSeconds
	if boostSeconds ~= nil then
		applyEffect(player, productKey, "boost", function()
			EconomyService.grantPersonalBoost(player, boostSeconds)
		end)
	end
	if def.oncePerAccount then
		data.starterKit = true
		DataService.markDirty(player, "starterKit")
	end

	applyEffect(player, productKey, "thanks", function()
		Notify.celebrate(player, "purchase", { product = productKey })
	end)
	Analytics.event(player, sku, 1)
	return true
end

return ProductService
