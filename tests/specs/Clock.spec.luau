--!nocheck
-- Shared/Util/Clock : source de temps unique (docs/04-architecture.md §4).
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness

	-- samedi 31/10/2026 16:00:00 UTC (début de Starfall Saturday)
	local SATURDAY_16H = 1793462400
	-- lundi 26/10/2026 00:00:00 UTC (début de semaine)
	local MONDAY = 1792972800

	local function clock()
		local h = Harness.new()
		return h:require("ReplicatedStorage.Shared.Util.Clock"), h
	end

	describe("Clock", function()
		it("suit workspace:GetServerTimeNow() par défaut", function()
			local Clock, h = clock()
			local a = h.workspace:GetServerTimeNow()
			local now = Clock.now()
			expect(math.abs(now - a) < 1).toBe(true)
			expect(Clock.unix()).toBe(math.floor(Clock.now()))
			expect(Clock.isFrozen()).toBe(false)
		end)

		it("freeze / advance / unfreeze / reset", function()
			local Clock = clock()
			Clock.freeze(1000.25)
			expect(Clock.now()).toBe(1000.25)
			expect(Clock.unix()).toBe(1000)
			Clock.advance(10)
			expect(Clock.now()).toBe(1010.25)
			Clock.unfreeze()
			expect(Clock.isFrozen()).toBe(false)
			Clock.setOffset(3600)
			expect(Clock.getOffset()).toBe(3600)
			local shifted = Clock.now()
			Clock.reset()
			expect(math.abs(shifted - Clock.now() - 3600) < 1).toBe(true)
			expect(Clock.getOffset()).toBe(0)
		end)

		it("advance sans freeze décale l'horloge réelle", function()
			local Clock = clock()
			local before = Clock.now()
			Clock.advance(86400)
			expect(Clock.now() - before >= 86400).toBe(true)
			expect(Clock.getOffset()).toBe(86400)
		end)

		it("refuse NaN et l'infini", function()
			local Clock = clock()
			expect(function()
				Clock.freeze(0 / 0)
			end).toThrow("Clock.freeze")
			expect(function()
				Clock.setOffset(math.huge)
			end).toThrow("Clock.setOffset")
			expect(function()
				Clock.advance(-math.huge)
			end).toThrow("Clock.advance")
		end)

		it("jour, semaine et jour de la semaine UTC", function()
			local Clock = clock()
			expect(Clock.weekday(SATURDAY_16H)).toBe(6)
			expect(Clock.weekday(MONDAY)).toBe(1)
			expect(Clock.weekday(0)).toBe(4) -- 01/01/1970 : jeudi
			expect(Clock.week(MONDAY) - Clock.week(MONDAY - 1)).toBe(1)
			expect(Clock.week(SATURDAY_16H)).toBe(Clock.week(MONDAY))
			expect(Clock.day(SATURDAY_16H)).toBe(math.floor(SATURDAY_16H / 86400))
			expect(Clock.secondOfDay(SATURDAY_16H)).toBe(16 * 3600)
			expect(Clock.untilNextDay(SATURDAY_16H)).toBe(8 * 3600)
			expect(Clock.untilNextWeek(SATURDAY_16H)).toBe(MONDAY + 7 * 86400 - SATURDAY_16H)
			Clock.freeze(SATURDAY_16H)
			expect(Clock.weekday()).toBe(6)
			expect(Clock.week()).toBe(Clock.week(MONDAY))
		end)

		it("chaque harnais a sa propre horloge (aucune fuite entre tests)", function()
			local A = clock()
			local B = clock()
			A.freeze(5)
			expect(A.now()).toBe(5)
			expect(B.isFrozen()).toBe(false)
		end)
	end)
end
