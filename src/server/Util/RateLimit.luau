--!strict
-- Limiteur de débit par joueur et par action (seau à jetons).
--   if not RateLimit.allow(player, "Buy", 5, 1) then return end  -- 5 appels / seconde

local Players = game:GetService("Players")

type Bucket = { tokens: number, last: number }

local RateLimit = {}

local buckets: { [Player]: { [string]: Bucket } } = {}

function RateLimit.allow(player: Player, action: string, maxCalls: number, perSeconds: number): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		if player.Parent == nil then
			return false
		end
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[action]
	if not bucket then
		bucket = { tokens = maxCalls, last = now }
		perPlayer[action] = bucket
	end
	local refill = (now - bucket.last) * (maxCalls / perSeconds)
	bucket.tokens = math.min(maxCalls, bucket.tokens + refill)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimit.clear(player: Player)
	buckets[player] = nil
end

Players.PlayerRemoving:Connect(RateLimit.clear)

return RateLimit
