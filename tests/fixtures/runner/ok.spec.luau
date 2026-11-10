--!nocheck
-- Spec jouet du lanceur de tests (tests/specs/Runner.spec.luau) : deux cas verts.
return function(T)
	T.describe("jouet vert", function()
		T.it("passe 1", function()
			T.expect(1).toBe(1)
		end)
		T.it("passe 2", function()
			T.expect(2).toBe(2)
		end)
	end)
end
