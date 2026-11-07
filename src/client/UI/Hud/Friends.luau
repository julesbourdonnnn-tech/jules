--!strict
-- Hud/Friends (lot B2, relecture indépendante, B2-67) : amis Roblox présents sur le serveur, UNE seule
-- liste pour le revenu du HUD (pastille Fame et amis, « +1,2K/s ») et pour le contexte des effets de
-- l'écran Améliorations (D30 : l'A_bonus du revenu, amis compris ; l'écran comptait 0 ami). Même règle
-- que le HUD de la v1.3, au geste près : un joueur compte quand Player:IsFriendsWith le dit (appel sous
-- pcall, dans son propre fil), jusqu'à son départ.
--
--   Friends.watch(onChange)  -- une seule fois (le HUD) : joueurs déjà là, PlayerAdded, PlayerRemoving
--   Friends.count()          -- amis présents (joueurs encore dans Players)

local Players = game:GetService("Players")

local Friends = {}

local here: { [number]: boolean } = {}
local watching = false

-- Amis présents (un joueur parti ne compte plus, même avant son PlayerRemoving)
function Friends.count(): number
	local n = 0
	for userId in here do
		local p = Players:GetPlayerByUserId(userId)
		if p and p.Parent then
			n += 1
		end
	end
	return n
end

-- Suit les amis du serveur (idempotent) ; `onChange` après chaque ami trouvé et chaque départ
function Friends.watch(onChange: () -> ())
	if watching then
		return
	end
	local me = Players.LocalPlayer
	if me == nil then
		return
	end
	watching = true
	local function check(p: Player)
		if p == me then
			return
		end
		task.spawn(function()
			local ok, friend = pcall(function()
				return me:IsFriendsWith(p.UserId)
			end)
			if ok and friend == true and p.Parent ~= nil then
				here[p.UserId] = true
				onChange()
			end
		end)
	end
	Players.PlayerAdded:Connect(check)
	Players.PlayerRemoving:Connect(function(p: Player)
		here[p.UserId] = nil
		task.defer(onChange)
	end)
	for _, p in Players:GetPlayers() do
		check(p)
	end
end

return Friends
