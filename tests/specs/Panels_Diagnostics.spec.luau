--!nocheck
-- Panels/Diagnostics (paquet client-panels ; GDD §12.11 ; docs/04 §11.2, §13.6) : visible seulement
-- après le DiagnosticsSnapshot « bonjour » (tab = 0) ; RequestDiagnostics à l'ouverture d'un onglet ;
-- lignes triées par nombre, ✕ ouvre les 3 exemples, ○ les ferme puis revient aux Réglages ; « Mon
-- client » (ErrorReporter.stats / entries) ; onglet Outils : AdminCommand, horloge grisée « Studio
-- seulement » hors Studio ; charges hostiles. Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")
local Gamepad = require("../harness/Gamepad")

local Enum = roblox.Enum

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function snapshot(tab)
		return {
			tab = tab,
			server = {
				placeVersion = 42,
				utc = 1800000000,
				uptime = 3600,
				players = 12,
				tickAvgMs = 1.5,
				tickMaxMs = 4.2,
				memoryMb = 812,
				timedOut = 1,
			},
			entries = {
				{
					key = "k1",
					kind = 2,
					text = "Avertissement rare",
					source = "server",
					count = 2,
					players = 1,
					first = 0,
					last = 0,
				},
				{
					key = "k2",
					kind = 1,
					text = "Erreur fréquente",
					source = "client",
					count = 9,
					players = 3,
					first = 0,
					last = 0,
				},
			},
			samples = {
				{ key = "k2", text = "Erreur fréquente #1", trace = "Script:12", ctx = "ps5", at = 0 },
				{ key = "k2", text = "Erreur fréquente #2", trace = "Script:12", ctx = "pc", at = 0 },
			},
			today = {},
		}
	end

	local function setup(opts)
		local h = TvAudit.client(opts or {})
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			Diag = TvAudit.mod(h, "UI.Panels.Diagnostics"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function hello(c)
		c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
		c.h:settle(1)
	end

	local function openFromSettings(c)
		c.PC.open("Settings")
		TvAudit.tick(c.h, 0.5)
		c.PC.open("Diagnostics")
		TvAudit.tick(c.h, 0.5)
	end

	describe("Panels/Diagnostics", function()
		it(
			"invisible sans « bonjour » (open refusé) ; visible après ; RequestDiagnostics(1) à l'ouverture",
			function()
				local c = setup()
				expect(c.Diag.visible()).toBe(false)
				c.PC.open("Settings")
				c.PC.open("Diagnostics")
				expect(c.PC.current()).toBe("Settings")
				hello(c)
				expect(c.Diag.visible()).toBe(true)
				TvAudit.tick(c.h, 0.5)
				c.PC.open("Diagnostics")
				expect(c.PC.current()).toBe("Diagnostics")
				expect(TvAudit.sent(c.h, "RequestDiagnostics")[1][1]).toBe(1)
				expect(c.h.game.GuiService.SelectedObject).toBe(
					c.PC.window("Diagnostics").Body.Tabs.Strip.Tab_server
				)
				clean(c)
			end
		)

		it(
			"Ce serveur : état, lignes triées par nombre ; ✕ sur une ligne : ses exemples ; ○, ○",
			function()
				local c = setup()
				hello(c)
				openFromSettings(c)
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", snapshot(1))
				c.h:settle(2)
				local page = c.PC.window("Diagnostics").Body.Page_server
				expect(page.Stamp.Text).toContain("Version 42")
				expect(page.Stat2.Text).toBe("12 players")
				local holder = page.List.Holder
				local first = nil
				for _, row in holder:GetChildren() do
					if row.Visible and row.Line:GetAttribute("RowIndex") == 1 then
						first = row.Line
					end
				end
				expect(first:FindFirstChild("Text").Text).toContain("k2") -- 9 occurrences avant 2
				expect(first.Count.Text).toBe("×9")
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = first
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(c.Diag._samplesOpen()).toBe(true)
				local samples = c.PC.window("Diagnostics").Body.Samples
				expect(samples.Sample1:FindFirstChild("Text").Text).toContain("Erreur fréquente #1")
				expect(samples.Sample2:FindFirstChild("Text").Text).toContain("#2")
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.Diag._samplesOpen()).toBe(false)
				expect(c.h.game.GuiService.SelectedObject).toBe(first)
				TvAudit.tick(c.h, 0.5)
				Gamepad.tap(c.h, Enum.KeyCode.ButtonB)
				expect(c.PC.current()).toBe("Settings") -- ○ → Réglages
				clean(c)
			end
		)

		it(
			"Mon client : mesures d'ErrorReporter ; Outils : horloge grisée hors Studio, AdminCommand",
			function()
				local c = setup()
				local ER = TvAudit.mod(c.h, "Controllers.ErrorReporter")
				ER.stats = function()
					return {
						fps = 59,
						memoryMb = 700,
						pingMs = 80,
						instances = 9000,
						connections = 300,
						reduced = true,
					}
				end
				ER.entries = function()
					return {
						{
							key = "c1",
							kind = 1,
							text = "Erreur client",
							source = "client",
							count = 1,
							players = 1,
							first = 0,
							last = 0,
						},
					}
				end
				hello(c)
				openFromSettings(c)
				TvAudit.tick(c.h, 2.5) -- RequestDiagnostics : 1 / 2 s (Config/Intents)
				c.Diag.setTab("client")
				local page = c.PC.window("Diagnostics").Body.Page_client
				expect(page.Stat1.Text).toBe("59 FPS")
				expect(page.Stat6.Text).toBe("Quality: reduced")
				expect(page.Empty.Visible).toBe(false)
				expect(TvAudit.sent(c.h, "RequestDiagnostics")[2][1]).toBe(2)
				c.Diag.setTab("tools")
				local tools = c.PC.window("Diagnostics").Body.Page_tools
				expect(c.Diag.defaultSelection()).toBe(tools.Tool_forceRush)
				expect(tools.Tool_clockPlus.Label.Text).toBe("Studio only")
				TvAudit.tick(c.h, 0.5)
				c.h.game.GuiService.SelectedObject = tools.Tool_clockPlus
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				expect(#TvAudit.sent(c.h, "AdminCommand")).toBe(0) -- grisé : refusé sans envoi
				TvAudit.tick(c.h, 1)
				c.h.game.GuiService.SelectedObject = tools.Tool_testClient
				Gamepad.tap(c.h, Enum.KeyCode.ButtonA)
				local args = TvAudit.sent(c.h, "AdminCommand")[1]
				expect(args[1]).toBe("testError")
				expect(args[2]).toBe("client")
				-- en Studio : l'horloge part avec le décalage + 10 min
				local s = setup({ isStudio = true })
				hello(s)
				openFromSettings(s)
				s.Diag.setTab("tools")
				local t2 = s.PC.window("Diagnostics").Body.Page_tools
				TvAudit.tick(s.h, 0.5)
				s.h.game.GuiService.SelectedObject = t2.Tool_clockPlus
				Gamepad.tap(s.h, Enum.KeyCode.ButtonA)
				local a2 = TvAudit.sent(s.h, "AdminCommand")[1]
				expect(a2[1]).toBe("clock")
				expect(a2[2]).toBe("600")
				clean(c)
				clean(s)
			end
		)

		it("charges hostiles : instantanés abîmés ignorés sans erreur", function()
			local c = setup()
			for _, payload in
				{
					"x",
					{ tab = "1" },
					{ tab = 0 / 0 },
					{
						tab = 1,
						server = "x",
						entries = { "a", { key = 5 }, { key = "k", count = 0 / 0 } },
						samples = 3,
					},
					{ tab = 3, today = { { key = "t", text = string.rep("x", 5000), count = math.huge } } },
					{ tab = 99 },
				}
			do
				c.h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", payload)
			end
			hello(c)
			openFromSettings(c)
			for _, tab in c.Diag.tabs() do
				c.Diag.setTab(tab)
				TvAudit.tick(c.h, 0.5)
			end
			clean(c)
		end)
	end)
end
