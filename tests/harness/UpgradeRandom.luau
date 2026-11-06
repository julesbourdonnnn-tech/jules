--!nocheck
-- UpgradeRandom (lot B2, étape 2) : profils v2 et réponses UpgradeResult tirés au hasard, graine
-- fixe (générateur congruentiel : même suite sur toutes les machines), pour les specs de l'écran
-- Améliorations (Upgrades_Order, Upgrades_Structure). Chaque réponse est VALIDE (identifiant
-- canonique, niveaux dans les bornes, monnaie de la ligne, instantané valide) : l'écran l'applique.
local UpgradeRandom = {}

function UpgradeRandom.rng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r.next(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function r.int(lo: number, hi: number): number
		return lo + math.floor(r.next() * (hi - lo + 1))
	end
	return r
end

-- Profil témoin modifié : niveaux, pièces et Confettis tirés (structure r, Record R, A inchangée)
function UpgradeRandom.edit(r, Upgrades)
	return function(p)
		local t = p.tiles
		t.snack = r.int(0, 12)
		t.star = if t.snack >= 12 then r.int(0, 8) else 0
		t.decor = r.int(0, 18)
		t.pens = r.int(0, 14)
		t.cozyBed = r.int(0, 1) == 1
		t.gloves = r.int(0, 40)
		t.school = r.int(0, 20)
		t.monuments = r.int(0, 10)
		for i, row in Upgrades.WorkshopRows do
			p.atelier[i] = r.int(0, #row.costs)
		end
		p.coins = 10 ^ r.int(0, 30) * (1 + r.next())
		p.confetti = r.int(0, 5000)
	end
end

-- Réponse valide d'un achat (ou d'un refus) portant l'instantané `snap`
function UpgradeRandom.result(r, UpgradeMath, snap)
	local ids = UpgradeMath.ids()
	local id = ids[r.int(1, #ids)]
	local max = UpgradeMath.maxLevel(id)
	local level = snap.levels[id] or 0
	local from = math.min(level, max)
	local refused = r.int(0, 3) == 0 or from >= max
	local to = if refused then from else math.min(max, from + r.int(1, 3))
	local reasons = {
		"upgrades.refused.coins",
		"upgrades.refused.confetti",
		"upgrades.refused.locked",
		"upgrades.refused.maxed",
		"upgrades.refused.loopCap",
		"upgrades.refused.busy",
	}
	return {
		id = id,
		from = from,
		to = to,
		spent = if to > from then r.int(1, 1000000) else 0,
		currency = UpgradeMath.currency(id),
		reason = if refused and r.int(0, 1) == 1 then reasons[r.int(1, #reasons)] else nil,
		snapshot = snap,
	}
end

return UpgradeRandom
