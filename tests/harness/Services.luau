--!nocheck
-- Services Roblox simulés (Players, DataStoreService, MarketplaceService, TweenService…).

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local MockInstance = require("./MockInstance")
local Signal = require("./Signal")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Services = {}

local function deepCopyJson(value: any): any
	-- Aller-retour JSON : reproduit la sérialisation DataStore (rejette Vector3, Instance…)
	if value == nil then
		return nil
	end
	local ok, encoded = pcall(serde.encode, "json", value)
	if not ok then
		error(`[DataStore simulé] valeur non sérialisable : {encoded}`, 3)
	end
	return serde.decode("json", encoded)
end

local function checkSerializable(value: any, path: string)
	local t = typeof(value)
	if t == "table" then
		local isArray = #value > 0
		for k, v in value do
			if type(k) ~= "string" and type(k) ~= "number" then
				error(`[DataStore simulé] clé non sérialisable à {path}`, 4)
			end
			if isArray and type(k) == "string" then
				error(`[DataStore simulé] table mixte (tableau + dictionnaire) à {path} : perte de données dans Roblox`, 4)
			end
			checkSerializable(v, path .. "." .. tostring(k))
		end
	elseif t ~= "string" and t ~= "number" and t ~= "boolean" and t ~= "nil" then
		error(`[DataStore simulé] type {t} non sérialisable à {path}`, 4)
	elseif t == "number" and (value ~= value or value == math.huge or value == -math.huge) then
		error(`[DataStore simulé] nombre invalide (NaN/inf) à {path}`, 4)
	end
end

function Services.install(h)
	local game = h.game
	local cm = MockInstance.classMethods

	local function service(className: string)
		local s = MockInstance.new(className)
		s.Name = className
		s.Parent = game
		return s
	end

	-- Conteneurs
	local workspace = service("Workspace")
	workspace.Gravity = 196.2
	workspace.StreamingEnabled = true
	local camera = MockInstance.new("Camera")
	camera.Name = "Camera"
	camera.Parent = workspace
	workspace.CurrentCamera = camera
	local terrain = MockInstance.new("Terrain")
	terrain.Name = "Terrain"
	terrain.Parent = workspace
	h.workspace = workspace

	cm.Workspace = {
		Raycast = function()
			return nil
		end,
		Spherecast = function()
			return nil
		end,
		Blockcast = function()
			return nil
		end,
		GetPartBoundsInRadius = function()
			return {}
		end,
		GetPartBoundsInBox = function()
			return {}
		end,
		GetPartsInPart = function()
			return {}
		end,
		GetServerTimeNow = function()
			return os.clock() + 1.7e9
		end,
	}
	cm.Terrain = {
		FillBlock = function() end,
		FillBall = function() end,
		FillCylinder = function() end,
		FillWedge = function() end,
		Clear = function() end,
	}

	for _, name in
		{
			"ReplicatedStorage",
			"ReplicatedFirst",
			"ServerScriptService",
			"ServerStorage",
			"Lighting",
			"SoundService",
			"StarterGui",
			"StarterPack",
			"Teams",
			"Chat",
			"TextChatService",
			"ProximityPromptService",
			"LocalizationService",
			"PhysicsService",
			"GuiService",
			"ContentProvider",
			"Debris",
			"CollectionService",
			"HttpService",
			"TweenService",
			"RunService",
			"UserInputService",
			"ContextActionService",
			"MarketplaceService",
			"DataStoreService",
			"MessagingService",
			"BadgeService",
			"PolicyService",
			"SocialService",
			"TeleportService",
			"AnalyticsService",
			"VRService",
			"HapticService",
			"AvatarEditorService",
			"GroupService",
			"TextService",
		}
	do
		service(name)
	end

	local starterPlayer = service("StarterPlayer")
	local sps = MockInstance.new("StarterPlayerScripts")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = starterPlayer
	local scs = MockInstance.new("StarterCharacterScripts")
	scs.Name = "StarterCharacterScripts"
	scs.Parent = starterPlayer

	-- Lighting
	local lighting = game.Lighting
	lighting.ClockTime = 14
	lighting.Brightness = 2
	lighting.Ambient = roblox.Color3.new(0.5, 0.5, 0.5)
	lighting.OutdoorAmbient = roblox.Color3.new(0.5, 0.5, 0.5)
	lighting.FogEnd = 100000
	lighting.GeographicLatitude = 41.7
	cm.Lighting = {
		GetMinutesAfterMidnight = function(self)
			return self.ClockTime * 60
		end,
		SetMinutesAfterMidnight = function(self, m)
			self.ClockTime = m / 60
		end,
	}

	-- RunService
	local isServer = h.mode == "server"
	cm.RunService = {
		IsServer = function()
			return isServer
		end,
		IsClient = function()
			return not isServer
		end,
		IsStudio = function()
			return h.isStudio
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(_, name, _priority, fn)
			h.renderSteps[name] = fn
		end,
		UnbindFromRenderStep = function(_, name)
			h.renderSteps[name] = nil
		end,
	}

	-- HttpService
	local guidCounter = 0
	cm.HttpService = {
		JSONEncode = function(_, v)
			return serde.encode("json", v)
		end,
		JSONDecode = function(_, s)
			return serde.decode("json", s)
		end,
		GenerateGUID = function(_, wrap)
			guidCounter += 1
			local g = string.format("%08X-0000-4000-8000-%012X", guidCounter, guidCounter)
			return if wrap == false then g else "{" .. g .. "}"
		end,
		UrlEncode = function(_, s)
			return s
		end,
	}

	-- Players
	local players = service("Players")
	players.MaxPlayers = 16
	players.RespawnTime = 5
	players.CharacterAutoLoads = true
	cm.Players = {
		GetPlayers = function(self)
			local out = {}
			for _, c in self:GetChildren() do
				if c.ClassName == "Player" then
					table.insert(out, c)
				end
			end
			return out
		end,
		GetPlayerByUserId = function(self, id)
			for _, c in self:GetChildren() do
				if c.ClassName == "Player" and c.UserId == id then
					return c
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(self, character)
			for _, c in self:GetChildren() do
				if c.ClassName == "Player" and c.Character == character then
					return c
				end
			end
			return nil
		end,
		GetUserIdFromNameAsync = function()
			return 1
		end,
		GetNameFromUserIdAsync = function(_, id)
			return "User" .. tostring(id)
		end,
		GetUserThumbnailAsync = function()
			return "rbxasset://textures/ui/GuiImagePlaceholder.png", true
		end,
		GetHumanoidDescriptionFromUserId = function()
			return MockInstance.new("HumanoidDescription")
		end,
	}

	-- TweenService : applique les valeurs finales immédiatement, Completed différé
	cm.TweenService = {
		Create = function(_, inst, info, goals)
			assert(MockInstance.is(inst), "TweenService:Create : instance attendue")
			assert(type(goals) == "table", "TweenService:Create : table de propriétés attendue")
			assert(info ~= nil, "TweenService:Create : TweenInfo attendu")
			local tween = MockInstance.new("Tween")
			local st = MockInstance.state(tween)
			st.props.PlaybackState = Enum.PlaybackState.Begin
			st.props.Instance = inst
			MockInstance.classMethods.Tween = MockInstance.classMethods.Tween
				or {
					Play = function(self)
						local s = MockInstance.state(self)
						if s.props.PlaybackState == Enum.PlaybackState.Cancelled then
							return
						end
						for k, v in s.goals do
							s.props.Instance[k] = v
						end
						s.props.PlaybackState = Enum.PlaybackState.Playing
						task.defer(function()
							if s.props.PlaybackState == Enum.PlaybackState.Playing then
								s.props.PlaybackState = Enum.PlaybackState.Completed
								self.Completed:Fire(Enum.PlaybackState.Completed)
							end
						end)
					end,
					Cancel = function(self)
						local s = MockInstance.state(self)
						s.props.PlaybackState = Enum.PlaybackState.Cancelled
						self.Completed:Fire(Enum.PlaybackState.Cancelled)
					end,
					Pause = function(self)
						MockInstance.state(self).props.PlaybackState = Enum.PlaybackState.Paused
					end,
				}
			st.goals = goals
			h.stats.tweens += 1
			return tween
		end,
		GetValue = function(_, alpha)
			return alpha
		end,
	}

	-- Debris
	cm.Debris = {
		AddItem = function(_, inst, lifetime)
			task.delay(lifetime or 10, function()
				if MockInstance.is(inst) then
					inst:Destroy()
				end
			end)
		end,
	}

	-- CollectionService
	local tagSignals = {}
	local removedSignals = {}
	cm.CollectionService = {
		AddTag = function(_, inst, tag)
			MockInstance.Methods.AddTag(inst, tag)
			if tagSignals[tag] then
				tagSignals[tag]:Fire(inst)
			end
		end,
		RemoveTag = function(_, inst, tag)
			MockInstance.Methods.RemoveTag(inst, tag)
			if removedSignals[tag] then
				removedSignals[tag]:Fire(inst)
			end
		end,
		HasTag = function(_, inst, tag)
			return MockInstance.Methods.HasTag(inst, tag)
		end,
		GetTags = function(_, inst)
			return MockInstance.Methods.GetTags(inst)
		end,
		GetTagged = function(_, tag)
			local out = {}
			for _, d in game:GetDescendants() do
				if MockInstance.Methods.HasTag(d, tag) then
					table.insert(out, d)
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(_, tag)
			tagSignals[tag] = tagSignals[tag] or Signal.new()
			return tagSignals[tag]
		end,
		GetInstanceRemovedSignal = function(_, tag)
			removedSignals[tag] = removedSignals[tag] or Signal.new()
			return removedSignals[tag]
		end,
	}

	-- ContentProvider / GuiService / LocalizationService / PolicyService / TextService
	cm.ContentProvider = {
		PreloadAsync = function() end,
	}
	game.GuiService.ReducedMotionEnabled = false
	game.GuiService.PreferredTransparency = 1
	cm.GuiService = {
		GetGuiInset = function()
			return Vector2.new(0, 58), Vector2.zero
		end,
		IsTenFootInterface = function()
			return false
		end,
	}
	game.LocalizationService.RobloxLocaleId = "en-us"
	game.LocalizationService.SystemLocaleId = "en-us"
	cm.LocalizationService = {
		GetTranslatorForPlayerAsync = function()
			error("Translator non simulé", 2)
		end,
		GetCountryRegionForPlayerAsync = function()
			return "FR"
		end,
	}
	cm.PolicyService = {
		GetPolicyInfoForPlayerAsync = function()
			return {
				AreAdsAllowed = true,
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = {},
				IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false,
				IsContentSharingAllowed = true,
			}
		end,
	}
	cm.TextService = {
		GetTextSize = function(_, text, size)
			return Vector2.new(#text * size * 0.5, size)
		end,
		FilterStringAsync = function(_, text)
			local result = MockInstance.new("TextFilterResult")
			MockInstance.classMethods.TextFilterResult = {
				GetNonChatStringForBroadcastAsync = function()
					return text
				end,
				GetNonChatStringForUserAsync = function()
					return text
				end,
			}
			return result
		end,
	}
	cm.PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
		IsCollisionGroupRegistered = function()
			return true
		end,
	}
	cm.BadgeService = {
		AwardBadge = function(_, userId, badgeId)
			table.insert(h.log.badges, { userId = userId, badgeId = badgeId })
			return true
		end,
		UserHasBadgeAsync = function()
			return false
		end,
		GetBadgeInfoAsync = function()
			return { IsEnabled = true, Name = "Badge" }
		end,
	}
	cm.MessagingService = {
		PublishAsync = function(_, topic, msg)
			table.insert(h.log.messages, { topic = topic, msg = msg })
		end,
		SubscribeAsync = function()
			return { Disconnect = function() end }
		end,
	}
	cm.SocialService = {
		PromptGameInvite = function(_, player)
			table.insert(h.log.invites, player)
		end,
		CanSendGameInviteAsync = function()
			return true
		end,
	}
	cm.TeleportService = {
		TeleportAsync = function() end,
		Teleport = function() end,
	}
	cm.AnalyticsService = setmetatable({}, {
		__index = function(_, key)
			return function(_, ...)
				table.insert(h.log.analytics, { method = key, args = table.pack(...) })
			end
		end,
	})
	cm.StarterGui = {
		SetCore = function() end,
		GetCore = function()
			return nil
		end,
		SetCoreGuiEnabled = function() end,
		GetCoreGuiEnabled = function()
			return true
		end,
	}

	-- UserInputService (client)
	local uis = game.UserInputService
	uis.TouchEnabled = h.touch
	uis.KeyboardEnabled = not h.touch
	uis.MouseEnabled = not h.touch
	uis.GamepadEnabled = false
	uis.MouseBehavior = Enum.MouseBehavior.Default
	uis.MouseIconEnabled = true
	cm.UserInputService = {
		GetLastInputType = function()
			return if h.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1
		end,
		IsKeyDown = function()
			return false
		end,
		GetMouseLocation = function()
			return Vector2.new(640, 360)
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetStringForKeyCode = function(_, kc)
			return kc.Name
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	}
	cm.ContextActionService = {
		BindAction = function(_, name, fn)
			h.actions[name] = fn
		end,
		BindActionAtPriority = function(_, name, fn)
			h.actions[name] = fn
		end,
		UnbindAction = function(_, name)
			h.actions[name] = nil
		end,
		SetTitle = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		GetButton = function()
			return nil
		end,
	}

	-- DataStoreService en mémoire, avec pannes injectables
	h.dataStores = {}
	h.dataStoreFailures = 0
	local function maybeFail(op: string)
		h.stats.dataStoreCalls += 1
		if h.dataStoreFailures > 0 then
			h.dataStoreFailures -= 1
			error(`502: API Services rejected request ({op}) [panne simulée]`, 0)
		end
	end
	local function storeFor(name: string, scope: string?, ordered: boolean)
		local key = (if ordered then "ordered:" else "") .. name .. "/" .. (scope or "global")
		if h.dataStores[key] then
			return h.dataStores[key]
		end
		local data = {}
		local store = MockInstance.new(if ordered then "OrderedDataStore" else "DataStore")
		store.Name = name
		MockInstance.state(store).data = data
		h.dataStores[key] = store
		return store
	end
	cm.DataStore = {
		GetAsync = function(self, key)
			maybeFail("GetAsync")
			task.wait()
			local v = MockInstance.state(self).data[key]
			return deepCopyJson(v), { Version = "1", CreatedTime = 0, UpdatedTime = 0 }
		end,
		SetAsync = function(self, key, value)
			maybeFail("SetAsync")
			checkSerializable(value, key)
			task.wait()
			MockInstance.state(self).data[key] = deepCopyJson(value)
			return "1"
		end,
		UpdateAsync = function(self, key, fn)
			maybeFail("UpdateAsync")
			task.wait()
			local data = MockInstance.state(self).data
			local new = fn(deepCopyJson(data[key]), { Version = "1" })
			if new ~= nil then
				checkSerializable(new, key)
				data[key] = deepCopyJson(new)
			end
			return deepCopyJson(data[key])
		end,
		RemoveAsync = function(self, key)
			maybeFail("RemoveAsync")
			local data = MockInstance.state(self).data
			local old = data[key]
			data[key] = nil
			return old
		end,
		IncrementAsync = function(self, key, delta)
			maybeFail("IncrementAsync")
			local data = MockInstance.state(self).data
			data[key] = (data[key] or 0) + (delta or 1)
			return data[key]
		end,
	}
	cm.OrderedDataStore = {
		GetAsync = cm.DataStore.GetAsync,
		RemoveAsync = cm.DataStore.RemoveAsync,
		IncrementAsync = cm.DataStore.IncrementAsync,
		SetAsync = function(self, key, value)
			maybeFail("SetAsync")
			assert(type(value) == "number" and value % 1 == 0, "OrderedDataStore : entier attendu")
			MockInstance.state(self).data[key] = value
		end,
		UpdateAsync = function(self, key, fn)
			maybeFail("UpdateAsync")
			local data = MockInstance.state(self).data
			local new = fn(data[key])
			if new ~= nil then
				assert(type(new) == "number" and new % 1 == 0, "OrderedDataStore : entier attendu")
				data[key] = new
			end
			return data[key]
		end,
		GetSortedAsync = function(self, ascending, pageSize)
			maybeFail("GetSortedAsync")
			local entries = {}
			for k, v in MockInstance.state(self).data do
				table.insert(entries, { key = k, value = v })
			end
			table.sort(entries, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local page = {}
			for i = 1, math.min(pageSize or 50, #entries) do
				page[i] = entries[i]
			end
			return {
				IsFinished = true,
				GetCurrentPage = function()
					return page
				end,
				AdvanceToNextPageAsync = function() end,
			}
		end,
	}
	cm.DataStoreService = {
		GetDataStore = function(_, name, scope)
			assert(type(name) == "string" and #name > 0 and #name <= 50, "nom de DataStore invalide")
			return storeFor(name, scope, false)
		end,
		GetOrderedDataStore = function(_, name, scope)
			return storeFor(name, scope, true)
		end,
		GetGlobalDataStore = function()
			return storeFor("__global", nil, false)
		end,
		GetRequestBudgetForRequestType = function()
			return 100
		end,
	}

	-- MarketplaceService
	h.ownedPasses = {}
	cm.MarketplaceService = {
		UserOwnsGamePassAsync = function(_, userId, passId)
			assert(type(passId) == "number", "UserOwnsGamePassAsync : id numérique attendu")
			return h.ownedPasses[userId] ~= nil and h.ownedPasses[userId][passId] == true
		end,
		PlayerOwnsAsset = function()
			return false
		end,
		PromptGamePassPurchase = function(_, player, passId)
			table.insert(h.log.prompts, { kind = "pass", player = player, id = passId })
		end,
		PromptProductPurchase = function(_, player, productId)
			table.insert(h.log.prompts, { kind = "product", player = player, id = productId })
		end,
		PromptPurchase = function(_, player, assetId)
			table.insert(h.log.prompts, { kind = "asset", player = player, id = assetId })
		end,
		PromptPremiumPurchase = function() end,
		PromptSubscriptionPurchase = function() end,
		GetProductInfo = function(_, id)
			return { PriceInRobux = 99, Name = "Product " .. tostring(id), Description = "", IsForSale = true }
		end,
		GetDeveloperProductsAsync = function()
			return {
				GetCurrentPage = function()
					return {}
				end,
				IsFinished = true,
			}
		end,
	}

	-- Personnage simulé
	local function makeCharacter(player)
		local model = MockInstance.new("Model")
		model.Name = player.Name
		local root = MockInstance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = CFrame.new(0, 5, 0)
		root.Parent = model
		local head = MockInstance.new("Part")
		head.Name = "Head"
		head.Parent = model
		local torso = MockInstance.new("Part")
		torso.Name = "UpperTorso"
		torso.Parent = model
		local humanoid = MockInstance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Parent = model
		local animator = MockInstance.new("Animator")
		animator.Name = "Animator"
		animator.Parent = humanoid
		model.PrimaryPart = root
		return model
	end
	h.makeCharacter = makeCharacter

	MockInstance.onLoadCharacter = function(player)
		local old = player.Character
		if old then
			player.CharacterRemoving:Fire(old)
			old:Destroy()
		end
		local char = makeCharacter(player)
		player.Character = char
		char.Parent = workspace
		player.CharacterAdded:Fire(char)
	end

	MockInstance.onKick = function(player, message)
		table.insert(h.log.kicks, { player = player, message = message })
	end

	-- Services créés à la demande (ex. noms rares)
	MockInstance.serviceFactory = function(name)
		if name == "VoiceChatService" or name == "ExperienceNotificationService" or name == "OpenCloudService" then
			return service(name)
		end
		return nil
	end
end

return Services
