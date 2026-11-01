--!nocheck
-- Panels/Leaderboards (paquet client-panels ; GDD §6.9 ; docs/04 §13.6) : 5 onglets, ma place sur ce
-- serveur et mon record contre la semaine dernière d'abord, puis le top 10 mondial (LeaderboardState),
-- alias pour un nom caché, « Toi », charges hostiles, sélection par défaut sur l'onglet en cours,
-- UiSeen("leaderboards"). Zéro trace.
local roblox = require("@lune/roblox")
local TvAudit = require("../harness/TvAudit")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function board(top)
		return { top = top, server = {}, mine = 42, minePrev = 30, myServerRank = 2 }
	end

	local function setup()
		local h = TvAudit.client({})
		return {
			h = h,
			PC = TvAudit.mod(h, "UI.PanelController"),
			LB = TvAudit.mod(h, "UI.Panels.Leaderboards"),
		}
	end

	local function clean(c)
		expect(table.concat(c.h.errors, "\n")).toBe("")
		expect(table.concat(c.h:warnings(), "\n")).toBe("")
	end

	local function body(c)
		return c.PC.window("Leaderboards").Body
	end

	describe("Panels/Leaderboards", function()
		it("5 onglets ; ma place, mon record (battu), top 10 trié ; alias et « Toi »", function()
			local c = setup()
			expect(c.LB.tabs()).toEqual({ "stamps", "combo", "catchScore", "helpful", "generous" })
			c.h:fireClient("ReplicatedStorage.Remotes.LeaderboardState", {
				week = 2900,
				boards = {
					stamps = board({
						{ rank = 2, userId = 20, name = "", value = 120 },
						{ rank = 1, userId = 10, name = "Noah", value = 1500 },
						{ rank = 3, userId = 1, name = "LocalTester", value = 42 },
					}),
				},
			})
			c.PC.open("Leaderboards")
			local b = body(c)
			expect(c.h.game.GuiService.SelectedObject).toBe(b.Tabs.Strip.Tab_stamps)
			expect(b.Summary.Place.Text).toBe("My place on this server: 2")
			expect(b.Summary.Record.Text).toBe("My record: 42")
			expect(b.Summary.LastWeek.Text).toBe("Last week: 30")
			expect(b.Summary.Beaten.Visible).toBe(true)
			expect(b.Row1:FindFirstChild("Name").Text).toBe("Noah")
			expect(b.Row1.Value.Text).toBe("1,500")
			expect(b.Row2:FindFirstChild("Name").Text).toContain("Squishy Fan #")
			expect(b.Row3:FindFirstChild("Name").Text).toBe("You")
			expect(b.Row4.Visible).toBe(false)
			expect(b.Empty.Visible).toBe(false)
			-- un autre onglet sans données : « Pas encore de scores »
			c.LB.setTab("combo")
			expect(b.Empty.Visible).toBe(true)
			expect(b.Summary.Place.Text).toBe("My place on this server: —")
			local seen = 0
			for _, args in TvAudit.sent(c.h, "UiSeen") do
				if args[1] == "leaderboards" then
					seen += 1
				end
			end
			expect(seen).toBe(1)
			clean(c)
		end)

		it(
			"charges hostiles (types faux, NaN, infini, 1 000 lignes, noms longs) : ignorées sans erreur",
			function()
				local c = setup()
				c.PC.open("Leaderboards")
				local rows = {}
				for i = 1, 1000 do
					rows[i] = { rank = i, userId = i, name = string.rep("é", 200), value = i }
				end
				for _, payload in
					{
						"x",
						5,
						{ boards = "x" },
						{ boards = { stamps = "x" } },
						{
							boards = {
								stamps = {
									top = {
										{ rank = "1", userId = 1, value = 1 },
										{ rank = 0 / 0, userId = 2, value = math.huge },
									},
								},
							},
						},
						{
							boards = {
								stamps = {
									top = rows,
									mine = 0 / 0,
									minePrev = "a",
									myServerRank = math.huge,
								},
							},
						},
					}
				do
					c.h:fireClient("ReplicatedStorage.Remotes.LeaderboardState", payload)
				end
				local b = body(c)
				expect(b.Row10.Visible).toBe(true)
				expect(utf8.len(b.Row1:FindFirstChild("Name").Text) <= 40).toBe(true)
				clean(c)
			end
		)
	end)
end
