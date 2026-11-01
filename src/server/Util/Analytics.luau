--!strict
-- Wrapper sûr autour d'AnalyticsService (jamais bloquant, jamais d'erreur remontée).
--   Analytics.funnel(player, 3, "FirstUpgrade")       -- entonnoir de première session
--   Analytics.earn(player, "Coins", 50, balance, "Gameplay", "harvest")
--   Analytics.spend(player, "Coins", 100, balance, "Shop", "upgrade_speed")
--   Analytics.event(player, "RareFound", 1)
-- transactionType : nom d'un Enum.AnalyticsEconomyTransactionType (IAP, Shop, Gameplay,
-- ContextualPurchase, TimedReward, Onboarding).

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

local funnelDone: { [Player]: { [number]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function safe(fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[Analytics]", err)
		end
	end)
end

-- Étapes numérotées 1, 2, 3… ; chaque étape n'est envoyée qu'une fois par session
function Analytics.funnel(player: Player, step: number, stepName: string)
	local done = funnelDone[player]
	if not done then
		done = {}
		funnelDone[player] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

local function economy(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	if amount <= 0 or amount ~= amount then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			currency,
			math.floor(amount),
			math.floor(balance),
			transactionType,
			sku
		)
	end)
end

function Analytics.earn(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, currency, amount, balance, transactionType, sku)
end

function Analytics.spend(
	player: Player,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, currency, amount, balance, transactionType, sku)
end

function Analytics.event(player: Player, name: string, value: number?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

return Analytics
