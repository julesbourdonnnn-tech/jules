--!strict
-- BigNumber (paquet logic) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Affichage des nombres géants (GDD §4.2), anglais et français. Remplace Format.abbreviate du socle
-- pour tout nombre du jeu (note INT-FORMAT) : moins de 10 000 = entier avec séparateur des milliers
-- (EN « , », FR espace fine insécable U+202F) ; ensuite 3 chiffres significatifs TRONQUÉS (999 999 →
-- « 999K ») et suffixe (EN K M B T Qa Qi Sx Sp Oc No Dc ; FR k M Md Bn Bd Tn Td Qn Qd Qt Qtd, virgule
-- décimale, espace fine insécable avant le suffixe) ; à partir de 1e36 « 1.23e36 » / « 1,23e36 ».
-- NaN → « 0 », ±inf → « ∞ », −0 → « 0 » : jamais d'erreur (propriétés : Props_BigNumber.spec).

local BigNumber = {}

-- Forme courte du HUD, des étiquettes et des « +N »
function BigNumber.abbreviate(n: number, lang: string?): string
	local _ = { n, lang }
	error("TODO(logic): BigNumber.abbreviate")
end

-- Entier exact avec séparateurs sous 1e15, sinon abbreviate
function BigNumber.full(n: number, lang: string?): string
	local _ = { n, lang }
	error("TODO(logic): BigNumber.full")
end

-- (forme courte, mot entier « 7,80 billions ») pour la fiche
function BigNumber.words(n: number, lang: string?): (string, string)
	local _ = { n, lang }
	error("TODO(logic): BigNumber.words")
end

-- Clé « num.word.<p> » si n est un jalon de bannière (1e6, 1e9, 1e12, 1e15)
function BigNumber.milestoneKey(n: number): string?
	local _ = { n }
	error("TODO(logic): BigNumber.milestoneKey")
end

-- Suffixes de la langue, du plus petit au plus grand
function BigNumber.suffixes(lang: string?): { string }
	local _ = { lang }
	error("TODO(logic): BigNumber.suffixes")
end

return BigNumber
