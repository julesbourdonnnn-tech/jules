--!nocheck
-- Couche i : intégrité de Config, Strings et Sounds dans le vrai moteur.
return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	describe("Moteur › configuration", function()
		it("Strings : chaque clé en anglais ET en français, mêmes variables {x}", function()
			local Strings = T.require("ReplicatedStorage.Shared.Localization.Strings")
			local function vars(s)
				local out = {}
				for v in string.gmatch(s, "{(%w+)}") do
					out[v] = true
				end
				return out
			end
			local missing = {}
			for key, en in Strings.en do
				local fr = Strings.fr[key]
				if type(fr) ~= "string" then
					table.insert(missing, key)
				else
					for v in vars(en) do
						if not vars(fr)[v] then
							table.insert(missing, key .. " {" .. v .. "}")
						end
					end
				end
			end
			expect(#missing).toBe(0)
		end)

		it(
			"Intents : chaque intention a un propriétaire qui existe sous ServerScriptService.Server.Services",
			function()
				local Intents = T.require("ReplicatedStorage.Shared.Config.Intents")
				local services = T.service("ServerScriptService"):FindFirstChild("Server")
				expect(services ~= nil).toBe(true)
				local folder = services:FindFirstChild("Services")
				for name, spec in Intents do
					expect(folder:FindFirstChild(spec.owner) ~= nil).toBe(true)
					expect(type(spec.rate[1])).toBe("number")
					local _ = name
				end
			end
		)

		it("Sounds : table de sons lisible", function()
			local Sounds = T.require("ReplicatedStorage.Shared.Config.Sounds")
			expect(type(Sounds)).toBe("table")
		end)
	end)
end
