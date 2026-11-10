--!nocheck
-- Recettes de Render/SquishyBuilder aplaties en lignes de texte (lot B5, étape 1 ; plan B5 D5) : sert au
-- témoin des recettes de la v1.3 (tests/fixtures/squishy-recipes/v13.txt, écrit une fois sur le code
-- de REL-B3, 4a4ac83, avant que les yeux se lisent dans Config/Visuals) et à la spec qui le relit.
--   RecipeDump.piece(p)                    -- une pièce : nom, rôle, forme, taille, décalage, rotation,
--                                          -- couleur, matériau, reflet, transparence, lod, orbite
--   RecipeDump.species(SB, id)             -- lignes des pièces de SB.recipe(id)
--   RecipeDump.plans(SB, mutations, id)    -- empreinte de SB._plan pour l'espèce × chaque mutation ×
--                                          -- chaque tenue de la v1.3 × selle ou non
--   RecipeDump.lines(SB, Species, Mutations) -- le témoin entier (une espèce après l'autre)
-- Nombres écrits avec 9 chiffres significatifs : assez pour retrouver exactement un flottant 32 bits
-- (les Vector3 et CFrame du moteur) ; deux recettes égales donnent donc les mêmes lignes, et deux
-- lignes égales la même recette.

local RecipeDump = {}

-- tenues de la v1.3 (false = aucune) : celles que SquishyBuilder.outfitPiece dessinait à REL-B3
RecipeDump.OUTFITS_V13 = { false, "plopBib", "sweater", "jellyCrown", "winterScarf", "bowTie" }

local function num(x: number): string
	return string.format("%.9g", x)
end

local function vec(v): string
	return num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z)
end

local function rot(cf): string
	local c = { cf:GetComponents() }
	local out = {}
	for i = 4, 12 do
		out[i - 3] = num(c[i])
	end
	return table.concat(out, ",")
end

function RecipeDump.piece(p): string
	local orbit = "-"
	if p.orbit then
		orbit = num(p.orbit.radius)
			.. ","
			.. num(p.orbit.height)
			.. ","
			.. num(p.orbit.period)
			.. ","
			.. num(p.orbit.phase)
	end
	return table.concat({
		p.name,
		p.role,
		p.shape,
		vec(p.size),
		vec(p.offset),
		rot(p.rot),
		num(p.color.R) .. "," .. num(p.color.G) .. "," .. num(p.color.B),
		p.material,
		num(p.reflectance),
		num(p.transparency),
		tostring(p.lod),
		orbit,
	}, "|")
end

function RecipeDump.species(SB, id: number): { string }
	local out = {}
	for _, p in SB.recipe(id).pieces do
		table.insert(out, RecipeDump.piece(p))
	end
	return out
end

-- Empreinte de deux sommes roulantes (moduli < 2^30 : aucun produit ne dépasse 2^53)
local function digest(lines: { string }): string
	local h1, h2 = 7, 11
	for _, line in lines do
		for i = 1, #line do
			local b = string.byte(line, i)
			h1 = (h1 * 131 + b) % 1000000007
			h2 = (h2 * 257 + b) % 998244353
		end
		h1 = (h1 * 131 + 10) % 1000000007
		h2 = (h2 * 257 + 10) % 998244353
	end
	return string.format("%d-%d", h1, h2)
end
RecipeDump.digest = digest

function RecipeDump.plans(SB, mutations: number, id: number): string
	local lines = {}
	for m = 0, mutations do
		for _, outfit in RecipeDump.OUTFITS_V13 do
			for _, saddle in { false, "classic" } do
				local pieces = SB._plan({
					species = id,
					mutation = m,
					stars = 1,
					displayScale = 1,
					lod = 1,
					outfit = outfit or nil,
					saddle = saddle or nil,
				})
				table.insert(lines, string.format("m%d %s %s", m, tostring(outfit), tostring(saddle)))
				for _, p in pieces do
					table.insert(lines, RecipeDump.piece(p))
				end
			end
		end
	end
	return digest(lines)
end

function RecipeDump.lines(SB, Species, Mutations): { string }
	local out = {}
	for _, def in Species.List do
		table.insert(out, string.format("S %d %s", def.id, def.key))
		for _, line in RecipeDump.species(SB, def.id) do
			table.insert(out, "P " .. line)
		end
		table.insert(out, "D " .. RecipeDump.plans(SB, Mutations.Count, def.id))
	end
	return out
end

return RecipeDump
