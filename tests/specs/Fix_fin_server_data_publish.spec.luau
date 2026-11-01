--!nocheck
-- Passe finale « fin-server-data-publish » — monde et quêtes :
--   * WorldService.ensureBuilt : une étape de construction qui lève ne laisse plus le drapeau
--     « construction en cours » posé (sinon chaque accès suivant masquait la vraie erreur derrière
--     « construction réentrante ») ; racine partielle détruite, erreur d'origine relancée, nouvel
--     essai possible
--   * QuestService : « Étoile du jour » (3 quêtes du jour réclamées) = boost ×2 de 15 min et UN SEUL
--     toast dédié celebrate.dailyStar (plus le « Glow ×2 » générique)
--   * scripts/prepublish.luau : liste les passes / produits à id 0 et échoue (contrôle du
--     propriétaire avant publication, hors de la porte de développement)
local process = require("@lune/process")

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local T0 = 1800000000 -- vendredi 15/01/2027 08:00:00 UTC

	-- ---------------------------------------------------------------------------------------------
	describe("Fix fin server data publish › WorldService : construction en échec", function()
		it(
			"une étape qui lève une fois : erreur d'origine, pas de drapeau bloqué, reconstruction",
			function()
				local h = Harness.new()
				local WS = h:require("ServerScriptService.Server.Services.WorldService")
				local Decor = h:require("ServerScriptService.Server.World.Decor")
				local buildClouds = Decor.buildClouds
				local fails = 1
				Decor.buildClouds = function(...)
					if fails > 0 then
						fails -= 1
						error("nuages en panne (simulée)")
					end
					return buildClouds(...)
				end
				local ok, err = pcall(WS.root)
				expect(ok).toBe(false)
				expect(string.find(tostring(err), "nuages en panne", 1, true) ~= nil).toBe(true)
				-- aucune racine partielle dans le workspace
				expect(h.workspace:FindFirstChild("Lumora")).toBeNil()
				-- l'accès suivant reconstruit (jamais « construction réentrante »)
				local ok2, root = pcall(WS.root)
				expect(ok2).toBe(true)
				expect(root.Parent).toBe(h.workspace)
				expect(WS.nest(1) ~= nil).toBe(true)
				expect(WS.spawnLocation(1):IsDescendantOf(root)).toBe(true)
				expect(WS.board():IsDescendantOf(root)).toBe(true)
				local count = 0
				for _, child in h.workspace:GetChildren() do
					if child.Name == "Lumora" then
						count += 1
					end
				end
				expect(count).toBe(1)
			end
		)

		it("étape qui lève toujours : chaque accès rapporte la vraie cause", function()
			local h = Harness.new()
			local WS = h:require("ServerScriptService.Server.Services.WorldService")
			local Nests = h:require("ServerScriptService.Server.World.Nests")
			Nests.build = function()
				error("nids en panne (simulée)")
			end
			for _ = 1, 3 do
				local ok, err = pcall(WS.nest, 1)
				expect(ok).toBe(false)
				expect(string.find(tostring(err), "nids en panne", 1, true) ~= nil).toBe(true)
				expect(string.find(tostring(err), "réentrante", 1, true)).toBeNil()
			end
			expect(h.workspace:FindFirstChild("Lumora")).toBeNil()
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix fin server data publish › QuestService : Étoile du jour", function()
		local function boot()
			local h = Harness.new()
			local Clock = h:require("ReplicatedStorage.Shared.Util.Clock")
			Clock.freeze(T0)
			local DS = h:require("ServerScriptService.Server.Services.DataService")
			DS.Settings.RETRY_BASE_DELAY = 0.001
			DS.Settings.LOCKED_RETRY_DELAY = 0.01
			local ctx = {
				h = h,
				Clock = Clock,
				DS = DS,
				Quests = h:require("ReplicatedStorage.Shared.Config.Quests"),
				QuestLogic = h:require("ServerScriptService.Server.Events.QuestLogic"),
				Strings = h:require("ReplicatedStorage.Shared.Localization.Strings"),
			}
			local RateLimit = h:require("ServerScriptService.Server.Util.RateLimit")
			RateLimit.allow = function()
				return true
			end
			h:boot()
			return ctx
		end

		local function feedbackKeys(h, p, from)
			local out = {}
			local sent = h:sentTo(p, "Feedback")
			for i = (from or 0) + 1, #sent do
				table.insert(out, sent[i][1].key)
			end
			return out
		end

		it("3 quêtes du jour réclamées : boost 15 min ×2 et un seul toast celebrate.dailyStar", function()
			local ctx = boot()
			local h = ctx.h
			local p = h:addPlayer({ userId = 1, name = "P1" })
			h:settle(3)
			local data = ctx.DS.waitFor(p, 2)
			h:settle(2)
			local list = {}
			for _, id in ctx.QuestLogic.drawDaily(1, ctx.Clock.day(), false, false) do
				table.insert(list, { id = id, p = 0, done = true, claimed = false })
			end
			data.quests.list = list
			data.quests.day = ctx.Clock.day()
			data.quests.starClaimed = false
			local before = data.boosts.personalUntil or 0
			h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 1)
			h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 2)
			h:settle(2)
			local mark = #h:sentTo(p, "Feedback")
			h:fireServer("ReplicatedStorage.Remotes.ClaimQuest", p, "daily", 3)
			h:settle(2)
			expect(data.quests.starClaimed).toBe(true)
			local boost = ctx.Quests.DailyStar.boostSeconds
			expect(boost).toBe(900)
			expect(data.boosts.personalUntil - math.max(before, ctx.Clock.now()) >= boost - 1).toBe(true)
			local keys = feedbackKeys(h, p, mark)
			expect(keys).toEqual({ "celebrate.dailyStar" })
			local payload = h:sentTo(p, "Feedback")[mark + 1][1]
			expect(payload.tone).toBe("reward")
			expect(payload.vars.minutes).toBe(15)
			-- textes EN / FR avec la durée en variable
			for _, lang in { "en", "fr" } do
				local text = ctx.Strings[lang]["celebrate.dailyStar"]
				expect(type(text)).toBe("string")
				expect(string.find(text, "{minutes}", 1, true) ~= nil).toBe(true)
			end
		end)
	end)

	-- ---------------------------------------------------------------------------------------------
	describe("Fix fin server data publish › scripts/prepublish.luau", function()
		it("ids à 0 : liste chaque article (clé) et échoue avec un message vers docs/05 §5", function()
			local Monetization = require("../../src/shared/Config/Monetization")
			local zero = {}
			for key, def in Monetization.Passes do
				if def.id == 0 then
					table.insert(zero, key)
				end
			end
			for key, def in Monetization.Products do
				if def.id == 0 then
					table.insert(zero, key)
				end
			end
			-- même exécutable que la suite (PATH de scripts/check.sh : ~/.cargo/bin, ~/.rokit/bin)
			local home = process.env.HOME
			local candidates = { "lune" }
			if home then
				table.insert(candidates, 1, home .. "/.rokit/bin/lune")
				table.insert(candidates, 1, home .. "/.cargo/bin/lune")
			end
			local result = nil
			for _, program in candidates do
				local ok, r = pcall(process.exec, program, { "run", "scripts/prepublish" })
				if ok then
					result = r
					break
				end
			end
			expect(result ~= nil).toBe(true)
			if #zero == 0 then
				expect(result.code).toBe(0)
			else
				expect(result.code ~= 0).toBe(true)
				local out = result.stdout .. result.stderr
				for _, key in zero do
					expect({ key = key, listed = string.find(out, key, 1, true) ~= nil }).toEqual({
						key = key,
						listed = true,
					})
				end
				expect(string.find(out, "docs/05", 1, true) ~= nil).toBe(true)
			end
		end)
	end)
end
