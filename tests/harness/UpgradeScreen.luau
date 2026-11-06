--!nocheck
-- UpgradeScreen (lot B2, étape 2) : aides des specs de l'écran Améliorations sur le VRAI client.
--   * instantanés fabriqués avec UpgradeMath.snapshot depuis le profil témoin
--     tests/fixtures/profiles/v2.json (interrupteurs v2.0 ouverts DANS le test : table de valeurs) ;
--   * client console démarré avec (ou sans) la clé `upgradeSnapshot` dans l'instantané d'arrivée ;
--   * ranch du joueur (Wobbleton/Ranches/1) avec les attributs v2.0 du serveur (HelperMode,
--     AscendReady…) ; DataPatch et UpgradeResult fabriqués ; intentions v2.0 relevées.
--
--   local S = UpgradeScreen.new(T.Harness)            -- un par spec
--   local snap = S.snap(1, function(p) p.coins = 1e6 end)
--   local c = S.client({ snap = snap })               -- c.h, c.PC, c.Up, c.US, c.FG
--   S.open(c, "ranch") ; S.patch(c, S.snap(2)) ; S.result(c, payload)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local TvAudit = require("./TvAudit")
local MockInstance = require("./MockInstance")

local UpgradeScreen = {}

local WITNESS = serde.decode("json", fs.readFile("tests/fixtures/profiles/v2.json"))

UpgradeScreen.V2_INTENTS = { "BuyUpgrade", "MenuActivity", "ClientMetric", "UiSeen" }

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end
UpgradeScreen.deepCopy = deepCopy

function UpgradeScreen.witness()
	return deepCopy(WITNESS)
end

function UpgradeScreen.new(Harness)
	local S = {}
	local shared = Harness.new()
	local UpgradeMath = shared:require("ReplicatedStorage.Shared.Logic.UpgradeMath")
	local Features = shared:require("ReplicatedStorage.Shared.Config.Features")
	S.UpgradeMath = UpgradeMath
	S.Upgrades = shared:require("ReplicatedStorage.Shared.Config.Upgrades")
	S.Balance = shared:require("ReplicatedStorage.Shared.Config.Balance")
	S.Layout = shared:require("ReplicatedStorage.Shared.Config.Layout")

	-- interrupteurs v2.0 tous ouverts (copie figée)
	local ON = {}
	for k, v in Features.Defaults do
		ON[k] = if type(v) == "boolean" then true else v
	end
	S.ON = ON

	-- Instantané du profil témoin modifié par `edit`, version `version`
	function S.snap(version, edit, flags)
		local p = deepCopy(WITNESS)
		if edit then
			edit(p)
		end
		return UpgradeMath.snapshot(p, flags or ON, version)
	end

	-- Client console ; opts.snap : instantané d'arrivée (nil : interrupteur coupé) ; opts.profile
	-- (champs en plus) ; opts.ranch : attributs du ranch du joueur ; opts.viewport, opts.lang
	function S.client(opts)
		opts = opts or {}
		local profile = deepCopy(opts.profile or {})
		if opts.snap ~= nil then
			profile.upgradeSnapshot = opts.snap
		end
		local h = TvAudit.client({
			profile = profile,
			viewport = opts.viewport,
			lang = opts.lang,
			before = opts.before,
		})
		local c = {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Up = TvAudit.mod(h, "UI.Panels.Upgrades"),
			US = TvAudit.mod(h, "UI.UpgradeSnapshot"),
			FG = TvAudit.mod(h, "UI.FocusGuard"),
			Clock = h:require("ReplicatedStorage.Shared.Util.Clock"),
		}
		S.ranch(c, opts.ranch or {})
		TvAudit.tick(h, 0.5)
		return c
	end

	-- Modèle Wobbleton/Ranches/1 du joueur (slot 1) avec ses attributs v2.0
	function S.ranch(c, attrs)
		local WSC = TvAudit.mod(c.h, "Controllers.WorldStateController")
		WSC.mySlot = function()
			return 1
		end
		local function child(parent, name, class)
			local f = parent:FindFirstChild(name)
			if f == nil then
				f = MockInstance.new(class)
				f.Name = name
				f.Parent = parent
			end
			return f
		end
		local world = child(c.h.workspace, "Wobbleton", "Folder")
		local list = child(world, "Ranches", "Folder")
		local model = child(list, "1", "Model")
		for k, v in attrs do
			model:SetAttribute(k, v)
		end
		c.model = model
		return model
	end

	function S.patch(c, snap, removed)
		c.h:fireClient("ReplicatedStorage.Remotes.DataPatch", { upgradeSnapshot = snap }, removed or {})
		c.h:settle(1)
	end

	function S.result(c, payload)
		c.h:fireClient("ReplicatedStorage.Remotes.UpgradeResult", payload)
		c.h:settle(1)
	end

	-- Ouvre l'écran (fermé avant) et laisse passer la garde d'ouverture
	function S.open(c, tab)
		c.PC.closeAll()
		TvAudit.tick(c.h, 0.5)
		c.PC.open("Upgrades", tab)
		TvAudit.tick(c.h, 0.5)
	end

	function S.selected(c)
		return c.h.game.GuiService.SelectedObject
	end

	-- Instances sous la fenêtre de l'écran (elle comprise)
	function S.count(c)
		local win = c.PC.window("Upgrades")
		if win == nil then
			return 0
		end
		return #win:GetDescendants() + 1
	end

	-- Objets d'interface (GuiObject) sous la fenêtre de l'écran (elle comprise)
	function S.guiObjects(c)
		local win = c.PC.window("Upgrades")
		if win == nil then
			return 0
		end
		local n = 1
		for _, d in win:GetDescendants() do
			if d:IsA("GuiObject") then
				n += 1
			end
		end
		return n
	end

	-- Aucune intention v2.0 envoyée
	function S.noV2Intent(c, expect)
		for _, name in UpgradeScreen.V2_INTENTS do
			if name == "UiSeen" then
				for _, args in TvAudit.sent(c.h, name) do
					expect(args[1] == "nextBuy").toBe(false)
				end
			else
				expect(#TvAudit.sent(c.h, name)).toBe(0)
			end
		end
	end

	function S.clean(c, expect)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	return S
end

return UpgradeScreen
