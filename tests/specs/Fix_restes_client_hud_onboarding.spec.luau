--!nocheck
-- Restes client « HUD et accueil » :
--   * Main.client : chaque require / Init / Start est isolé (xpcall + warn nommant le module) ; un
--     contrôleur en panne ne laisse plus l'écran de chargement à vie : ClientReady est posé dès
--     l'instantané du profil, même sans HUD (Q11)
--   * Hud/EventPill : la météo passe avant un boost de serveur long (Glow Party), qui laisse aussi
--     la place au compte à rebours d'un événement à moins de 60 s ; la Nuit d'Or garde sa place (Q17)
local roblox = require("@lune/roblox")
local Vector2 = roblox.Vector2

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
	local T0 = 1800000000 -- pile à :00:00 UTC (Comète à chaque :X0, météo :02:00-:04:30, :08:00…)

	local function anyLine(lines, ...)
		local needles = { ... }
		for _, line in lines do
			local all = true
			for _, needle in needles do
				if not string.find(line, needle, 1, true) then
					all = false
					break
				end
			end
			if all then
				return true
			end
		end
		return false
	end

	-- =========================================================================================
	-- Main.client : isolation des pannes au démarrage
	-- =========================================================================================

	local function clientWith(patch)
		local h = Harness.new({ mode = "client", touch = true })
		h:createRemotes()
		patch(h)
		local ok, err = pcall(function()
			h:boot()
		end)
		return h, ok, err
	end

	describe("Fix restes client HUD/accueil › démarrage du client isolé (Q11)", function()
		it("un Start qui lève (LightingController) : les suivants démarrent, ClientReady au profil", function()
			local h, ok, err = clientWith(function(h)
				local Lighting = h:require(CLIENT .. "Controllers.LightingController")
				Lighting.Start = function()
					error("panne simulée de LightingController")
				end
			end)
			expect({ ok = ok, err = if ok then nil else tostring(err) }).toEqual({ ok = true })
			-- les modules suivants ont démarré (HUD, Minimap, accueil)
			expect(h.localPlayer.PlayerGui:FindFirstChild("HUD") ~= nil).toBe(true)
			expect(h.localPlayer.PlayerGui:FindFirstChild("Onboarding") ~= nil).toBe(true)
			expect(anyLine(h:warnings(), "LightingController", "Start", "panne simulée")).toBe(true)
			-- l'écran de chargement attend le profil
			expect(h.localPlayer:GetAttribute("ClientReady")).toBeNil()
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("HUD en panne (Init et Start lèvent) : ClientReady posé quand même à l'instantané", function()
			local h, ok = clientWith(function(h)
				local HUD = h:require(CLIENT .. "UI.HUD")
				HUD.Init = function()
					error("panne simulée de HUD.Init")
				end
				HUD.Start = function()
					error("panne simulée de HUD.Start")
				end
			end)
			expect(ok).toBe(true)
			expect(anyLine(h:warnings(), "HUD", "Init")).toBe(true)
			expect(anyLine(h:warnings(), "HUD", "Start")).toBe(true)
			-- OnboardingController (après le HUD) a quand même démarré
			local Onboarding = h:require(CLIENT .. "Controllers.OnboardingController")
			expect(Onboarding._state().hintFrame ~= nil).toBe(true)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBeNil()
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("un module qui ne se charge pas (require lève) : signalé, les autres démarrent", function()
			local h, ok = clientWith(function(h)
				-- require du module en échec (même effet qu'une erreur au chargement du module)
				h.loading[h:find(CLIENT .. "Controllers.LightingController")] = true
			end)
			expect(ok).toBe(true)
			expect(anyLine(h:warnings(), "LightingController", "require")).toBe(true)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
		end)

		it("démarrage sain : aucun avertissement, ClientReady au profil (une seule fois, booléen)", function()
			local h, ok = clientWith(function() end)
			expect(ok).toBe(true)
			local changes = 0
			h.localPlayer:GetAttributeChangedSignal("ClientReady"):Connect(function()
				changes += 1
			end)
			h:fireClient("ReplicatedStorage.Remotes.DataSnapshot", { glow = 5 })
			h:settle(2)
			expect(h.localPlayer:GetAttribute("ClientReady")).toBe(true)
			expect(changes).toBe(1)
			expect(#h:warnings()).toBe(0)
		end)
	end)

	-- =========================================================================================
	-- Hud/EventPill : météo et prochain événement avant un boost long
	-- =========================================================================================

	local function pill()
		local h = Harness.new({ mode = "client" })
		local L = h:require("ReplicatedStorage.Shared.Localization")
		return {
			EventPill = h:require(CLIENT .. "UI.Hud.EventPill"),
			t = function(key, vars)
				return L.get("en", key, vars)
			end,
			nameOf = function()
				return nil
			end,
		}
	end

	local function events(now, over)
		local ev = { t = now, wisps = {} }
		for k, v in over do
			ev[k] = v
		end
		return ev
	end

	describe("Fix restes client HUD/accueil › pastille d'événement et boosts de serveur (Q17)", function()
		it("Glow Party (60 min en file) + fenêtre météo : la météo et son compte à rebours", function()
			local c = pill()
			local now = T0 + 150 -- :02:30, fenêtre météo :02:00-:04:30
			local ev = events(now, {
				weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
				serverBoost = { endsAt = now + 3552, source = "glowParty" },
			})
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("weather")
			expect(s.key).toBe("hud.event.weather")
			expect(s.vars.time).toBe("2:00")
			expect(s.active).toBe(true)
		end)

		it("Glow Party + Comète dans 45 s : le compte à rebours de la Comète", function()
			local c = pill()
			local now = T0 + 1155 -- :19:15 ; Comète à :20, prochaine météo à :22
			local ev = events(now, { serverBoost = { endsAt = now + 3000, source = "glowParty" } })
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			expect(s.key).toBe("hud.event.nextComet")
			expect(s.vars.time).toBe("0:45")
			-- pile 60 s avant : toujours le prochain événement
			s = c.EventPill.compute(ev, T0 + 1140, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			expect(s.vars.time).toBe("1:00")
		end)

		it("Glow Party sans météo ni événement proche : le boost reste affiché", function()
			local c = pill()
			local now = T0 + 1095 -- :18:15 ; Comète dans 105 s
			local ev = events(now, { serverBoost = { endsAt = now + 600, source = "glowParty" } })
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("boost")
			expect(s.key).toBe("hud.event.glowParty")
			expect(s.vars.time).toBe("10:00")
			-- boost terminé : prochain événement
			s = c.EventPill.compute(ev, now + 600, c.t, c.nameOf)
			expect(s.kind).toBe("next")
			-- source inconnue : même règle que la Glow Party (clé de repli)
			ev.serverBoost = { endsAt = T0 + 1155 + 500, source = "mystery" }
			expect(c.EventPill.compute(ev, T0 + 1155, c.t, c.nameOf).kind).toBe("next")
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("boost")
		end)

		it("priorités inchangées : Comète, Balise, Frenzy, Starfall avant la météo et les boosts", function()
			local c = pill()
			local now = T0 + 150
			local base = {
				weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
				serverBoost = { endsAt = now + 3000, source = "glowParty" },
			}
			local ev = events(now, base)
			ev.frenzy = { endsAt = now + 30 }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("frenzy")
			ev.frenzy = nil
			ev.starfall = { startsAt = now - 10, endsAt = now + 500 }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("starfall")
			ev.starfall = nil
			ev.comet = {
				id = 1,
				phase = "ground",
				x = 0,
				z = 0,
				code = 1,
				warnAt = 0,
				impactAt = now,
				burstAt = now + 60,
			}
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("comet")
		end)

		it("Nuit d'Or (temps fort de 5 min après la Balise) : garde sa place devant la météo", function()
			local c = pill()
			local now = T0 + 150
			local ev = events(now, {
				weather = { key = "aurora", startsAt = T0 + 120, endsAt = T0 + 270 },
				serverBoost = { endsAt = now + 200, source = "goldenNight" },
			})
			local s = c.EventPill.compute(ev, now, c.t, c.nameOf)
			expect(s.kind).toBe("boost")
			expect(s.key).toBe("hud.event.goldenNight")
			-- Nuit d'Or déclenchée par LiveOps : même règle
			ev.serverBoost = { endsAt = now + 200, source = "liveOps" }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).key).toBe("hud.event.goldenNight")
			-- données incohérentes : jamais d'erreur
			ev.serverBoost = { endsAt = 0 / 0, source = "glowParty" }
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("weather")
			ev.weather = nil
			expect(c.EventPill.compute(ev, now, c.t, c.nameOf).kind).toBe("next")
		end)
	end)

	-- (suite : rail du HUD, instruction d'accueil, tampon de Starforge plus bas)
	local _ = Vector2
end
