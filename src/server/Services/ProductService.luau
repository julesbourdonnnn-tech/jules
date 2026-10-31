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
--   * passes (MonetizationService.PassGranted, y compris à l'arrivée) : VIP Star / Double Glow →
--     EconomyService.settle + refreshRate ; Extra Perches / Stash Plus → AtlasService.refreshPerches ;
--     Night Shift, Conga Styles : lus dynamiquement (rien à stocker) ; Celebrate "purchase" seulement
--     pour un achat fait en jeu (PromptGamePassPurchaseFinished)
--   * Celebrate "purchase" (pluie de pièces, « Merci ! ») ; Analytics Product_<clé>
-- GDD : §8.1-§8.3, §4.17 (Glow Party), §14.2.
-- Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService,
-- EventService, Config/{Monetization,Nebbies}, Signals, Util/Notify, Util/Analytics, Shared/Util/Clock,
-- Economy/PassEffects.

local MarketplaceService = game:GetService("MarketplaceService")
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

local function onPassGranted(player: Player, passKey: string)
	if PassEffects.passHas(passKey, "glowBonus") or PassEffects.passHas(passKey, "glowMult") then
		-- règle au taux enregistré (sans le pass) puis recalcule M avec le pass
		EconomyService.settle(player)
		EconomyService.refreshRate(player)
	end
	if PassEffects.passHas(passKey, "extraPerches") or PassEffects.passHas(passKey, "stashSize") then
		AtlasService.refreshPerches(player)
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
	MonetizationService.PassGranted:Connect(onPassGranted)

	-- « Merci ! » seulement pour un pass acheté en jeu (PassGranted est aussi émis à l'arrivée)
	local passKeyById: { [number]: string } = {}
	for key, def in Monetization.Passes do
		if def.id > 0 then
			passKeyById[def.id] = key
		end
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			local passKey = passKeyById[passId]
			if wasPurchased and passKey then
				Notify.celebrate(player, "purchase", { pass = passKey })
				Analytics.event(player, `Pass_{passKey}`, 1)
			end
		end
	)
end

-- Glow qu'accorderait maintenant un produit Glow (affichage « ≈ » côté client : même calcul)
function ProductService.glowAmount(player: Player, productKey: string): number
	local def = Monetization.Products[productKey]
	if def == nil or def.idleSeconds == nil then
		return 0
	end
	return Formulas.glowForSeconds(EconomyService.idleRate(player), def.idleSeconds, def.minGlow)
end

-- Applique l'effet d'un produit (handler partagé, exposé pour les tests) ; true si appliqué
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
		local endsAt = EventService.queueGlowParty(player, partySeconds)
		local remaining = if type(endsAt) == "number" and endsAt == endsAt
			then math.max(endsAt - Clock.now(), partySeconds)
			else partySeconds
		Notify.banner("glowParty", {
			userId = player.UserId,
			name = player.DisplayName,
			minutes = math.ceil(partySeconds / 60),
		}, player)
		Notify.feedback(player, "feedback.glowPartyQueued", { minutes = math.ceil(remaining / 60) }, "reward")
	end

	if def.idleSeconds ~= nil then
		EconomyService.addGlowSeconds(player, def.idleSeconds, sku, def.minGlow)
	end
	if def.stardust ~= nil then
		EconomyService.addStardust(player, def.stardust, sku, "IAP")
	end
	if def.species ~= nil then
		local codes = {}
		for _, s in def.species do
			if Nebbies.Species[s] ~= nil then
				table.insert(codes, Nebbies.pack(s, 0, 0))
			end
		end
		if #codes > 0 then
			AtlasService.addNebbies(player, codes, "product")
		end
	end
	if def.style ~= nil then
		NestService.unlock(player, "styles", def.style)
	end
	if def.boostSeconds ~= nil then
		EconomyService.grantPersonalBoost(player, def.boostSeconds)
	end
	if def.oncePerAccount then
		data.starterKit = true
		DataService.markDirty(player, "starterKit")
	end

	Notify.celebrate(player, "purchase", { product = productKey })
	Analytics.event(player, sku, 1)
	return true
end

return ProductService
