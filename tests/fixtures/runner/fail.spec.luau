--!nocheck
-- Spec jouet du lanceur de tests (tests/specs/Runner.spec.luau) : un cas vert, un cas en échec.
return function(T)
	T.describe("jouet en échec", function()
		T.it("passe", function()
			T.expect(1).toBe(1)
		end)
		T.it("échoue", function()
			T.expect(1).toBe(2)
		end)
	end)
end
