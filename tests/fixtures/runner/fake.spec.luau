--!nocheck
-- Spec jouet du lanceur de tests (tests/specs/Runner.spec.luau) : un cas en échec dont le texte
-- imite la ligne de comptes du lanceur, seule sur sa ligne et sans aucun échec.
return function(T)
	T.describe("jouet menteur", function()
		T.it("échoue avec une fausse ligne de comptes", function()
			error("texte de l'échec :\n9 réussis, 0 échoués, 0 specs non chargées")
		end)
	end)
end
