# Plan de contenu complet — Raise a Squishy

> **Date : dimanche 1er novembre 2026.** Rôle : direction créative.
> **Demande du propriétaire (1er novembre 2026)** : « Pour ce jeu, je veux qu'il soit le plus complet possible, plein d'améliorations, la renaissance (rebirth), de beaux visuels. Regarde les tycoons qui marchent le mieux en ce moment et prends exemple. Prends autant de temps qu'il faut. Je veux un jeu complet à la fin. » Et **zéro bug** : Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration.
> **Ce document fusionne** les trois plans de travail (« Progression », « Renaissance et long terme », « Spectacle et sensations ») d'après le verdict des deux jurys, l'étude `docs/08-etude-tycoons-2026.md` et le GDD v1.3 (`docs/02-game-design-document.md`). Il garde les meilleures idées, écarte les faibles et **tranche chaque doublon** : une seule version de chaque chose.
> **Règle de base : on étend le GDD, on ne recommence rien.** Tout ce qui suit s'ajoute au GDD v1.3. Ce document fait foi jusqu'à la version 1.4 du GDD (liste des changements au chapitre 7).
> **Statut** : proposition à valider par le propriétaire ; **révisée le 2 novembre 2026** après deux critiques (économie, interface et technique) : voir le journal de révision en fin de document.

**Comment lire ce document**
- **(mesuré)** : chiffre sorti d'une simulation qui rejoue les vraies règles du jeu. Trois sources : la simulation du GDD v1.3 (§4.24) ; le prototype du plan « Progression » du 01/11/2026 (`scratchpad/plan-sim/results/ext-16.txt`, **avec les Plopettes allumées**) ; la **contre-mesure de la critique du 01/11/2026** : le vrai `EconomyModel` du dépôt avec les valeurs de ce document, 40 joueurs de référence (20 pour les variantes), 28 à 84 jours, serveurs de 4, 8 et 16 (`scratchpad/etude-tycoons/sim/results/*.txt`, par exemple `launch-16.txt` pour la configuration du lancement). Quand deux sources diffèrent, la contre-mesure fait foi.
- **(cible)** : valeur de départ choisie par nous, à placer en configuration ; la porte de simulation `EconomyPacing` doit la confirmer avant la sortie. Ce n'est **pas** un résultat.
- **(inférence)** : notre conclusion de designer, écrite nulle part ailleurs.
- **[08-n]** : source de `docs/08-etude-tycoons-2026.md` (liste de son chapitre 11, avec URL et date). **[Wn]** : source vue pour ce document le 01/11/2026 (annexe A).
- **r** = niveau de Grand Splorch de la boucle en cours (le « R » du GDD). **Record R** = le plus haut r jamais atteint ; il ne baisse jamais. **A** = nombre de Jelly Ascend faites. Bornes dures : `Balance.Prestige.MaxR = 400`, `MaxA = 60` (§2.1).
- **T12** = prix du 12e niveau du Tapis à Goûter dans la boucle en cours : 306 M × 3,5^r × 1,6^A (306 M à r = 0 et A = 0 ; 84,5 T à r = 10 et A = 0 ; 1,6^A est le facteur de prix de l'Ascension, §3.5). Un prix écrit en T12 donne le même ressenti à tous les r.
- **Effort** : S = 1 à 2 jours de développement avec les tests ; M = 3 à 5 jours ; L = 6 à 10 jours.
- Les chiffres des concurrents viennent de guides et de wikis de fans, souvent contradictoires : ce sont des ordres de grandeur, avec leur date.

---

## 1. Résumé pour le propriétaire

1. **Plus d'améliorations** : on passe de 4 à **9 familles** et de 45 à **136 niveaux** achetables (104 au lancement). Nouveautés : les **Gants Moelleux** (presser plus fort), le **Tapis Étoilé** (le Tapis monte jusqu'au niveau 20), les **Monuments** (grands décors permanents), l'**École des Plopettes** (de petites aides mignonnes) et l'**Atelier de Big Plop**.
2. **Un seul écran « Améliorations »**, fait pour la télé : 4 onglets, 3 cartes « Conseillé », achat ×1 / ×10 / Max à la manette (le D-pad, ✕ et ○ suffisent), et une puce « Prochain achat » dans le HUD. Plus besoin de marcher jusqu'aux dalles.
3. **Zéro bug d'affichage** : **20 règles** écrites, chacune avec son test. Chaque rectangle est calculé depuis sa zone et vérifié (rien ne déborde d'une carte ni d'un cadre de défilement, le cadre de sélection n'est jamais coupé). Les lignes ne changent jamais d'ordre. Les chiffres ne repartent jamais de 0. Un ✕ appuyé pour ouvrir l'écran n'achète jamais rien. Chaque texte est mesuré en anglais et en français, en 720p, 1080p et 4K, à la taille de texte normale et à la plus grande.
4. **Une renaissance plus riche** : chaque nouveau record de Grand Splorch donne des **Confettis** (3 + r), la monnaie de l'Atelier (gagnée en jouant, jamais vendue). Chaque niveau R de 1 à 20 débloque quelque chose de nommé **et** de visible dans le ranch.
5. **Une 2e couche, la Jelly Ascend** (au Grand Splorch XV, puis XX, XXIV, XXVIII…) : croissance ×3 pour toujours, +20 Confettis, un halo, un ciel au-dessus du ranch. **Rien de débloqué ne se perd jamais.** Elle est livrée éteinte et s'allume le 26 décembre si la simulation est verte. Mesuré : 1re Ascension au jour 13 pour un enfant qui joue 30 min par jour.
6. **Le ranch embellit pour toujours** : 6 grands paliers (arche, tour, balcon, phare, dôme, couronne) et un changement visible à chaque Grand Splorch. Il ne paraît plus jamais vide après une renaissance.
7. **Des squishies qui ont du caractère** : 6 personnalités, 18 petites saynètes, 6 visages, des réactions au monde. Tout est calculé sur l'appareil du joueur : aucun trafic réseau en plus.
8. **Du contenu chaque semaine** : une piste gratuite de 12 paliers, 3 Défis, des cosmétiques qui reviennent au plus tard 8 semaines après (aucune peur de rater). Un calendrier daté sur 3 mois, publié en données.
9. **Rien n'est vendu en plus** : ni Confettis, ni Ascension, ni chance, ni achat à distance. Tous ces systèmes se gagnent en jouant.
10. **Le calendrier tient grâce à une ligne de coupe** : le 12 décembre, un jeu complet (améliorations, renaissance, visuels) ; Plopettes, Ascension, piste de la semaine et décor personnel dans les 3 semaines qui suivent. **Règle mesurée** : les Plopettes ou la Jelly Ascend doivent être en ligne le 26 décembre, sinon la fin du premier mois est trop creuse. **On coupe du contenu, jamais la qualité.**

### 1.1 Ce que nous avons tranché entre les trois plans

| Sujet | Version gardée | Pourquoi |
|---|---|---|
| Confettis | **3 + r** à chaque **Grand Splorch** (nouveau Record R) : 4 au premier, 13 au dixième ; **1** par Petit Splorch et par Grand Splorch sauté ; **+20** par Jelly Ascend | 4 Confettis dès le premier Grand Splorch : une ligne de l'Atelier s'achète tout de suite (choix des deux jurys). Payer 3 + r à chaque boucle rejouée vidait les Confettis de leur sens après quelques Ascensions (mesuré : 1 160 en poche au jour 84) |
| Atelier | **Un seul**, comme 4e onglet de l'écran Améliorations, en **lignes** (pas de grille) | Un seul composant et une seule navigation à tester ; une grille à 2 dimensions de plus n'apportait rien à un enfant |
| Contenu de l'Atelier | Confort et départ rapide seulement (§3.4) | Les cartes de croissance et de revenu non simulées (Engrais jusqu'à +75 %, Pot doré, Gelée éternelle) cassaient les jalons ; règle : « seuls le Tapis et r touchent la croissance » |
| 3e monnaie (Prismes) et écran Observatoire | **Supprimés**. Les bonus de l'Ascension se paient en Confettis, dans l'Atelier | Pièces, Confettis et Fame suffisent pour un enfant de 8 ans qui lit peu |
| Condition de la Jelly Ascend | **r ≥ 15**, puis **20**, puis **+4** à chaque Ascension (24, 28, 32…) ; **aucune condition de tampons** | Mesuré : avec l'extension, le creux commence à R = 15. Avec +5 à chaque fois, l'écart entre deux Ascensions s'allonge (15 puis 20 jours) ; avec +4, il reste stable (13 à 13,5 jours). La 1re marche de +5 garde la Couronne (R20) dans le premier mois (§3.5). Une seule condition = un seul texte à lire |
| Noms des paliers de ranch | Arche à pompons (R1), Tour à bonbons (R3), Balcon de gelée (R5), Phare de gelée (R10), Dôme néon (R15), Couronne flottante (R20) | Version des plans Renaissance et Spectacle, choisie par le jury ; le phare sert aussi de signal « prêt » |
| Paliers du Tapis | Nappe pique-nique (1-3), Biscuit sablé (4-6), Bonbon arc-en-ciel (7-9), Gelée dorée (10-12), **Étoilé (13-16), Galaxie (17-20)** | Le jury proposait « Galaxie au niveau 12 puis Étoilé » ; nous mettons le nom le plus beau tout en haut, pour qu'un enfant ne « redescende » jamais de Galaxie à Étoilé |
| Délai « en attente » d'un achat | **3 s** pour tous les achats (2 s et 5 s étaient proposés) | Bien au-dessus d'un aller-retour normal du réseau ; assez court pour qu'un enfant ne voie pas un bouton figé ; réglable en configuration |
| Protection contre le double achat | **`expectedLevel`** (niveau attendu envoyé au serveur), pas un compteur `seq` | Deux appuis rapides n'achètent jamais deux niveaux, même dans le désordre ; un seul mécanisme pour toutes les boutiques |
| Tables par R | **Une seule table** R1-R20 (§3.3) | Deux tables auraient fait diverger textes, tests et captures |
| Onglets de l'écran | **4** : Conseillé, Ranch, Plopettes, Atelier (le plan Progression en avait 5) | L'onglet « Pression » n'aurait eu qu'une ligne ; les Gants vont dans Ranch. Moins d'onglets pour Léa, 8 ans |
| Ordre des lignes | **Fixe**, jamais retrié | La règle « payables d'abord » du plan Spectacle est la famille du bug de tri de Clash of Clans (08/10/2026) [08-60] |
| Plopettes | Code prêt, **sortie le 19 décembre** si la porte est verte, sinon le 2 janvier | Plus gros risque serveur (tick à 10 Hz, jusqu'à 96 aides) ; les deux jurys le demandent |
| Monuments | **4 au lancement** (R6 à R12), puis publiés en données ; prix corrigé pour l'Ascension (§2.1) | Seul usage utile des pièces de fin de boucle (mesuré) ; le prix fixe du plan cassait après une Ascension |
| Grand Splorch rejoué après une Ascension | **« Petit Splorch »** local, hors de la file du serveur (§3.2) | Le GDD limite le serveur à un Grand Splorch toutes les 20 s : des vétérans à boucles de 60 s satureraient la file |

### 1.2 Ce que nous avons écarté

| Idée | Pourquoi non |
|---|---|
| Tri « payables d'abord » (Spectacle V13) | Une ligne qui bouge sous le curseur de la manette : bug d'affichage garanti [08-60] |
| Ligne de rentabilité « ≈ 6 min » (Renaissance F1) | Précision visée de ±30 % seulement 9 fois sur 10 : « 6 min » qui en durent 12 est un bug pour un enfant. Le suivi d'objectif du GDD (« 12K / 15K ») suffit |
| Applaudimètre (Renaissance F3) | Le gain dépend des autres enfants : quémander, second compte ; surface de triche pour une valeur faible |
| Bassin agrandi (Progression 5.7) | Fausse le classement « Meilleur combo » ; les combos font ≈ 1 % des pièces au jour 7 (mesuré) : achat piège |
| Prismes et Observatoire comme écran (Renaissance F7) | 3e monnaie de trop ; l'Observatoire reste un décor sur la colline |
| Cartes Engrais, Pot doré, Gelée éternelle, Pièces prismatiques, Sieste étoilée | Croissance ou revenu non simulés ; contraires à la règle de rythme mesurée |
| Ambiance de mon ranch (Spectacle V7) | Faible valeur, une teinte de plus qui gêne la lecture des raretés |
| Compteur public « ♥ 12 aujourd'hui » (Spectacle V20) | Classement de popularité entre enfants ; on garde le cœur et la notification privée |
| Wobbleverse, 3e couche (Renaissance F15) | Aucune donnée avant mars 2027 ; la profondeur ne retient pas le grand public (Sell Lemons ≈ 229 K → ≈ 9 K, juillet → octobre 2026 [08-68][08-69]) |
| Recherche à minuteur réel, rebirth automatique, Cuve ou chance achetables, achat à distance payant | Interdits du GDD (§8.1) ou pièges vus ailleurs [08-45][08-86] |

---

## 2. Améliorations

### 2.1 Les familles, leurs niveaux, leurs prix et leurs effets

**Trois lois, valables pour toute famille présente et future**
1. **Les pièces et les Confettis n'achètent jamais une chance**, une naissance, un tirage ni un saut de minuteur (GDD §8.1, étendu à l'Atelier).
2. **Les familles de la boucle donnent des pièces, pas de la croissance.** Seuls le Tapis (et son prolongement, le Tapis Étoilé) et r changent la croissance. C'est ce qui garde les jalons du GDD (mesuré : premier Grand Splorch à 12,6 min, R = 10 / 15 / 20 aux jours 7 / 14 / 28, inchangés avec l'extension ; contre-mesure sans Plopettes : 12,5 min, R = 9,5 / 15 / 21).
3. **Toute famille passe la porte `EconomyPacing`** avant d'être allumée (§6.3).

**Le catalogue**

| # | Famille (FR / EN) | Onglet | Ce qu'elle fait | Niveaux | Monnaie et prix | Au Grand Splorch | Ouverture | Effet au maximum |
|---|---|---|---|---|---|---|---|---|
| 1 | Tapis à Goûter / Snack Mat (GDD) | Ranch | Grossir plus vite | 12 | `floor(20 × 4,5^L × 3,5^r)` | Remis à zéro | Dès le début | Croissance ×13 |
| 1b | Tapis Étoilé / Star Mat (même ligne que le Tapis) | Ranch | Grossir encore plus vite | 8 (13 → 20) | `floor(20 × 4,5^11 × 1,25^(L − 11) × 3,5^r)`, L = 12 … 19 | Remis à zéro | 2 niveaux à r = 10, 12, 14, 16 (dans la boucle) | Croissance ×21 |
| 2 | Décorations / Decorations (GDD) | Ranch | Gagner plus | 18 | `floor(80 × 2,2^L × 3,5^r)` | Remises à zéro, sauf les décorations gardées | Dès le début | Revenu +90 % |
| 3 | Enclos / Pens (GDD) | Ranch | Plus de place | 14 | `floor(1 200 × 2,2^L)` (fixe) | Gardé | Dès le début | 18 places (24 avec le pass) |
| 4 | Lit douillet / Cozy Bed (GDD) | Ranch | Dormir plus longtemps | 1 | 25 M (fixe) | Gardé | Record R ≥ 3 | Hors ligne 8 h → 12 h |
| 5 | Gants Moelleux / Squishy Gloves | Ranch | Presser plus fort | 30 | `floor(2 000 × 1,55^L × 3,5^r)` | Remis à zéro | Record R ≥ 1 | Pressions ×1,75 |
| 6 | École des Plopettes / Plopette School | Plopettes | Des aides plus rapides | 20 | `floor(20 000 × 1,75^L × 3,5^r)` | Remise à zéro (les Plopettes restent) | Record R ≥ 2, dès que les Plopettes sont allumées | Une pression d'aide toutes les 6 s par Plopette |
| 7 | Monuments / Monuments | Ranch | Embellir pour toujours | 10 (4 au lancement) | Voir plus bas | Gardés | Record R = 6, 8, 10 … 24 | +10 % de revenu, 10 grands décors |
| 8 | Atelier de Big Plop / Big Plop's Workshop | Atelier | Confort et départ rapide, pour toujours | 9 lignes, 23 niveaux | Confettis | Gardé | Record R ≥ 1 | §3.4 |
| — | Cuve à Gelée (GDD, lecture seule) | Atelier | — | 8 | Donnée par le Record R | Gardée | R0 → R7 | Qualité 8, vitesse 10, 5 buses |
| — | Paliers de ranch (lecture seule) | Atelier | — | 6 | Donnés par le Record R | Gardés | R1, 3, 5, 10, 15, 20 | Ranch transformé |

L = niveau actuel (le premier achat coûte la base). Les familles 1, 1b, 2, 5 et 6 sont multipliées par 3,5^r, comme au GDD, **et par le facteur d'Ascension 1,6^A** (`Balance.Ascend.PriceMult`, §3.5) ; l'Enclos, le Lit et les Monuments ne le sont pas (prix fixes, ou qui suivent déjà r − Record R). **Total des niveaux achetables** : 12 + 8 + 18 + 14 + 1 + 30 + 20 + 10 + 23 = **136** (104 au lancement : sans l'École, sans Plume, avec 4 Monuments et sans les niveaux réservés aux joueurs qui ont fait une Ascension).

**Écrit en maths, calculé sans puissance.** Les formules de ce document sont des notations. `Logic/UpgradeMath` et `Logic/Prestige` n'appellent jamais `^`, `math.pow` ni `math.exp` : la puissance n'est pas garantie identique au bit près entre les consoles, le PC et le serveur Linux (+, −, × et ÷ le sont), et un écart d'un bit devient une pièce, ou des centaines, après `floor`. Les tables de prix, d'objectifs et de croissance sont construites par **multiplications successives dans un ordre fixe**, de la même façon sur le client et sur le serveur (test statique : aucun `^` dans ces deux modules). **Bornes** : `MaxR = 400` (prix ≤ 1,4e239 même à A = 60), `MaxA = 60` ; à r = MaxR, le Grand Splorch n'est plus proposé (« Record absolu ! ») ; à A = MaxA, la Jelly Ascend non plus. Tests de propriété à MaxR et MaxA : aucun infini, aucun `NaN`, `bulk(n)` toujours fini.

**Écarts GDD / code à corriger dans le GDD** : (1) le GDD §4.6 donne au Tapis une croissance de prix ×4,0 ; le code (`src/shared/Config/Balance.luau`, réglage de la revue « logic » du 01/11/2026) utilise **×4,5**, parce qu'avec ×4,0 les pièces perdues au Grand Splorch valaient 13 à 17 fois le Tapis 12. (2) Le GDD §4.7 compte une pression comme **12 s** de revenu ; le code utilise **`Balance.Press.Seconds = 22`** (même revue : avec 12, les pressions ne faisaient que 40 % des pièces au jour 7, sous le minimum de 50 %). Toutes les valeurs de ce document, simulations comprises, sont celles du code.

**Tapis à Goûter (prix à r = 0, à multiplier par 3,5^r ; effet = croissance du ranch)**

| Niveau acheté | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 20 | 90 | 405 | 1 822 | 8 201 | 36,9 K | 166 K | 747 K | 3,36 M | 15,1 M | 68,1 M | 306 M |
| Croissance | ×2 | ×3 | ×4 | ×5 | ×6 | ×7 | ×8 | ×9 | ×10 | ×11 | ×12 | ×13 |
| Palier | Nappe pique-nique | | | Biscuit sablé | | | Bonbon arc-en-ciel | | | Gelée dorée | | |

Somme des 12 niveaux : 394 M (1,3 T12).

**Tapis Étoilé (niveaux 13 à 20 ; seulement après le Tapis 12)** : prix = `floor(20 × 4,5^11 × 1,25^(L − 11) × 3,5^r × 1,6^A)`, où L est le niveau actuel (12 à 19) et 20 × 4,5^11 = 306 455 660 le prix du Tapis 12 à r = 0. **Un seul** facteur 3,5^r (la version précédente le comptait deux fois : 275 855 fois trop cher à r = 10), et chaque niveau coûte **plus** que le précédent, Tapis 12 compris (avant, le niveau 13 coûtait exactement le prix du Tapis 12, ce qui cassait le test « coûts strictement croissants »).

| Niveau acheté | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|
| Prix (r = 0, A = 0 ; tronqué comme à l'écran) | 383 M | 478 M | 598 M | 748 M | 935 M | 1,16 B | 1,46 B | 1,82 B |
| Croissance | ×14 | ×15 | ×16 | ×17 | ×18 | ×19 | ×20 | ×21 |
| Ouvert dans la boucle à | r = 10 | r = 10 | r = 12 | r = 12 | r = 14 | r = 14 | r = 16 | r = 16 |
| Palier | Étoilé | | | | Galaxie | | | |

Somme : 7,60 B (24,8 T12) ; à r = 10, le niveau 13 coûte 105 T. Cas exacts de `UpgradeMath.spec` : niveau 13 = 383 069 575 et niveau 20 = 1 826 618 076 à r = 0 ; niveau 13 = 105 671 556 317 044 à r = 10 ; chaque rangée strictement croissante, du Tapis 1 au niveau 20. Le plafond du Tapis Étoilé suit **r de la boucle**, pas le Record R : c'est un plafond d'économie, pas un déblocage (sinon, après une Ascension, un joueur à r = 0 achèterait une croissance ×21 pour presque rien). L'écran le montre avec un état à part, jamais avec un cadenas (§2.2), et le bandeau dit : « Tapis Étoilé : à partir du Grand Splorch X dans cette boucle ». Le prototype en fait la pièce qui comble la fin des boucles : temps « à plus de 3 min d'un achat » aux jours 8-14 de 14,3 % sans lui contre 7,8 % avec (mesuré, mais les deux variantes diffèrent aussi par d'autres réglages). Il change la croissance : il passe donc la porte de simulation, **à remesurer avec ce prix corrigé**.

**Décorations (prix à r = 0, × 3,5^r ; effet = revenu de tout le ranch)**

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 80 | 176 | 387 | 851 | 1 874 | 4 122 | 9 070 | 19,9 K | 43,9 K | 96,5 K | 212 K | 467 K | 1,02 M | 2,26 M | 4,97 M | 10,9 M | 24,0 M | 52,9 M |
| Revenu | +5 % | +10 % | +15 % | +20 % | +25 % | +30 % | +35 % | +40 % | +45 % | +50 % | +55 % | +60 % | +65 % | +70 % | +75 % | +80 % | +85 % | +90 % |

Somme : 97,1 M. Trois ensembles nommés de 6 : **Jardin bonbon** (1-6), **Parc nuage** (7-12), **Fête foraine** (13-18) ; un ensemble complet allume une guirlande (décor seulement). **Décorations gardées** au Grand Splorch : toujours les premières dans l'ordre d'apparition, jamais un choix (un seul cas à tester) : 3 au Record R 8, 3 de plus au Record R 14, puis +3 par niveau de la ligne « Déco qui reste » de l'Atelier, 18 au plus.

**Enclos (prix fixes ; effet = nombre de places)**

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 1 200 | 2 640 | 5 808 | 12,7 K | 28,1 K | 61,8 K | 136 K | 299 K | 658 K | 1,44 M | 3,18 M | 7,01 M | 15,4 M | 33,9 M |
| Places | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |

Somme : 62,2 M. **Places offertes** aux Record R 2, 6, 11 et 16 : +1 niveau de la dalle, dans les 14 niveaux (jamais au-delà de 18 places, 24 avec Grand Ranch : budget de 384 squishies affichés, GDD §4.14) ; si la dalle est déjà au maximum, **+25 Confettis** à la place, avec le message « Enclos déjà plein : +25 Confettis ». Paliers d'aspect : **Herbe tendre** (4-9 places), **Coussins moelleux** (10-17), **Coussins nuage** (18-24).

**Lit douillet** : 25 M, dès le Record R 3, hors ligne 8 h → 12 h ; il se construit en **lit à baldaquin**.

**Gants Moelleux** (s'ouvrent au Record R 1 ; prix à r = 0, × 3,5^r ; effet = récompense de chaque pression)

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 2 000 | 3 100 | 4 805 | 7 447 | 11,5 K | 17,8 K | 27,7 K | 42,9 K | 66,6 K | 103 K |
| Pressions | ×1,025 | ×1,05 | ×1,075 | ×1,10 | ×1,125 | ×1,15 | ×1,175 | ×1,20 | ×1,225 | ×1,25 |

| Niveau | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 160 K | 248 K | 384 K | 596 K | 924 K | 1,43 M | 2,21 M | 3,44 M | 5,33 M | 8,26 M |
| Pressions | ×1,275 | ×1,30 | ×1,325 | ×1,35 | ×1,375 | ×1,40 | ×1,425 | ×1,45 | ×1,475 | ×1,50 |

| Niveau | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 |
|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 12,8 M | 19,8 M | 30,7 M | 47,7 M | 73,9 M | 114 M | 177 M | 275 M | 426 M | 661 M |
| Pressions | ×1,525 | ×1,55 | ×1,575 | ×1,60 | ×1,625 | ×1,65 | ×1,675 | ×1,70 | ×1,725 | ×1,75 |

Somme : 1,86 B (6,1 T12). À r = 1, le niveau 1 coûte 7 000 pièces, à peu près le Tapis niveau 4 (6 378) : il arrive tout de suite sans voler la place du Tapis. **+2,5 % par niveau se sent peu** (remarque d'un juré) : le retour passe donc par **7 paliers nommés, un tous les 5 niveaux**, chacun avec la couleur de l'éclaboussure et du « +N » : **Coton** (1-4, blanc), **Velours** (5-9, pêche), **À pois** (10-14, rose à pois), **Rayés** (15-19, menthe et blanc), **Guimauve** (20-24, pastel), **Nuage** (25-29, ciel), **Dorés** (30, or). Les Gants comptent pour les pressions dans son ranch et celles des Plopettes ; pas pour le pet-sitting (pas de ferme entre comptes) ni pour le MEGA (des points, pas des pièces).

**École des Plopettes** (dès le Record R 2 et l'allumage des Plopettes ; prix à r = 0, × 3,5^r ; effet = intervalle de chaque Plopette)

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 20,0 K | 35,0 K | 61,2 K | 107 K | 187 K | 328 K | 574 K | 1,00 M | 1,75 M | 3,07 M |
| Intervalle | 11,7 s | 11,4 s | 11,1 s | 10,8 s | 10,5 s | 10,2 s | 9,9 s | 9,6 s | 9,3 s | 9,0 s |

| Niveau | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 5,38 M | 9,42 M | 16,5 M | 28,8 M | 50,5 M | 88,4 M | 154 M | 270 M | 473 M | 829 M |
| Intervalle | 8,7 s | 8,4 s | 8,1 s | 7,8 s | 7,5 s | 7,2 s | 6,9 s | 6,6 s | 6,3 s | 6,0 s |

Somme : 1,93 B (6,3 T12). Paliers de tablier : **Blanc** (1-4), **Fleuri** (5-9), **Rayé** (10-14), **Arc-en-ciel** (15-19), **Doré** (20).

**Les Plopettes** (personnages, gardés pour toujours) : **Pip** (Record R 2), **Pop** (R4), **Pim** (R6), **Pom** (R8), **Puff** (R12), et **Plume**, la 6e, achetée à l'Atelier (dès R12). Une Plopette sautille jusqu'à un squishy prêt et le presse : le serveur choisit la cible et l'heure de la pression (`tPress`), et le client règle le saut pour atterrir à cette heure (§7.4). Sa récompense : `0,5 × pressReward(revenu du squishy, PERFECT = non, série = 0, Kitty) × Gants`. Règles du serveur : seulement un squishy de l'enclos ou du Bassin **prêt depuis au moins 3 s**, ni porté ni en attente de Grand Splorch, **à plus de 12 studs à plat de la position validée du joueur** (sa portée de pression est de 10 studs : une Plopette ne vole jamais le squishy que l'enfant vise) ; elles ne travaillent que si le propriétaire est sur le serveur, **font la sieste après 5 min sans aucune entrée** et se réveillent à la première ; pause pendant son Grand Splorch. Mesuré au jour 7 : les Plopettes font ≈ 9 % des pièces gagnées en jeu, les pressions du joueur 60 % (le GDD exige au moins 50 %). Le prototype ne connaissait pas la règle des 12 studs : leur part réelle sera plutôt plus faible (à refaire dans le vrai modèle). Pourquoi les enfants vont aimer : des personnages qui travaillent pour toi sont le cœur des tycoons qui marchent (managers de Sell Lemons [08-43], employés de Restaurant Tycoon 3 [08-55]), et les nôtres sont mignons et nommés (inférence).

**Monuments** : grands objets en formes simples, construits **derrière le fond du ranch** sur 10 emplacements fixes (§4.2), visibles du ranch, de la rue et des voisins ; ils restent pour toujours. Effet : **+1 % de revenu chacun, en multiplicateur à part** (`revenu × (1 + 0,01 × Monuments)`, +10 % au plus) : le « +1 % » affiché est vrai, alors qu'ajouté dans `A_bonus` (entre 2 et 7 au jour 28) il ne valait que +0,14 à +0,5 %. Surtout décoratif. Mesuré : 2 Monuments au jour 7 et 4 au jour 28 (les 4 du lancement) pour le joueur de référence, aucun effet sur le rythme.

| # | Monument | Ouverture (Record R) | Prix avant toute Ascension | Sortie |
|---|---|---|---|---|
| 1 | Moulin à Gelée | 6 | 1,69 T | Lancement |
| 2 | Statue de Big Plop | 8 | 20,7 T | Lancement |
| 3 | Grande Roue Guimauve | 10 | 253 T | Lancement |
| 4 | Château de Pudding | 12 | 3,10 Qa | Lancement |
| 5 | Bateau-Bonbon | 14 | 38,0 Qa | 19 décembre (données) |
| 6 | Fusée Sucette | 16 | 466 Qa | 19 décembre (données) |
| 7 | Jardin Suspendu | 18 | 5,71 Qi | 2 janvier (données) |
| 8 | Horloge Bonbon | 20 | 69,9 Qi | 2 janvier (données) |
| 9 | Pyramide de Dragées | 22 | 857 Qi | 23 janvier (données) |
| 10 | Cascade de Sirop | 24 | 10,4 Sx | 23 janvier (données) |

**Prix d'un Monument** : `3 × 306 M × 3,5^(R d'ouverture) × 3,5^(r − Record R)`, sans le facteur d'Ascension. Avant toute Ascension, r = Record R, donc le prix est fixe (3 T12 au moment où il s'ouvre : un but de plusieurs boucles, puis abordable ; c'est la version mesurée). Après une Ascension, r repart de 0 mais le Record R reste : le prix suit la boucle en cours, avec la même difficulté relative qu'avant. Correction de la critique du jury (« le prix fixe casse après une Ascension »). Les noms ont été choisis pour ne doubler aucun autre objet du jeu (le phare est un palier de ranch, la lune est celle de la Jelly Moon).

**Formules du GDD qui changent** (ajouts en gras)

```
croissance g = 1 × 2^r × 3^A × (1 + niveauTapis [0 à 20]) × (1 + 0,10 × familleJellyComplète) × B
revenu       = 0,02 × rareté × taille × mutation × (1 + 0,5 × étoiles) × A_bonus × (1 + 0,01 × Monuments) × P × B
               A_bonus = l'additif « A » du GDD (décorations, amis, Fame, Étagère, pages dorées)
pression     = floor(max(Balance.Press.Min [10], Balance.Press.Seconds [22] × revenu) × (PERFECT ? 2 : 1)
                     × (1 + 0,10 × min(5 + superSérie, série)) × (Kitty ? 1,10 : 1) × (1 + 0,025 × niveauGants))
prix         = base × croissanceDuPrix^L × 3,5^r × 1,6^A   (familles 1, 2, 5, 6 ; Tapis Étoilé : ci-dessus)
```

L'additif « A » du GDD est renommé **`A_bonus`** pour ne pas le confondre avec le nombre d'Ascensions. Tous les facteurs nouveaux sont multiplicatifs ou bornés, jamais des bonus additifs inutiles en fin de courbe (piège de Merge a Nuke [08-83]) : c'est pour cela que les Monuments sortent de `A_bonus`.

### 2.2 L'écran « Améliorations » à la télé

**Où on le trouve.** Le menu (△ ou croix ↓) a une entrée **Améliorations**, juste sous **Ranch**. La sélection d'office du menu reste celle du GDD §10.6 : Grand Splorch s'il est prêt, sinon le bouton à pastille « ! », sinon le dernier utilisé, sinon Ranch (« Ranch = △ ✕ » et la spec `Console_hud` ne changent pas). Améliorations s'ouvre donc par △ ↓ ✕, ou par △ ✕ si c'est la dernière entrée utilisée ; c'est la puce « Prochain achat » du HUD qui dit qu'un achat est prêt. Raccourci clavier : **U**. L2 / R2 font tourner les panneaux dans l'ordre Ranch → **Améliorations** → la suite du GDD §10.6. Le kiosque de Big Plop sur la place ouvre le même écran sur l'onglet Atelier. Les **dalles au sol restent** (Tapis, décorations, Enclos, Lit) pour le geste du début ; les familles nouvelles s'achètent seulement depuis l'écran. L'onglet *Dalles* du panneau Ranch est retiré : l'écran Améliorations le remplace.

**Le rail du menu reste dans la zone sûre.** Avec l'entrée Améliorations, le rail peut avoir 8 boutons : ils passent à **80 px de haut avec 16 px d'écart** (l'écart minimal du GDD §10.1 entre deux éléments sélectionnables), icône 48 et libellé 36 px : 8 × 80 + 7 × 16 = 752 px, de y = 246 à 998, sous la limite de 1 026. Grand Splorch et Jelly Ascend **partagent un seul bouton**, montré seulement quand l'une des deux est prête (GDD) ; son libellé est **le nom de la renaissance prête** (« Grand Splorch » ou « Jelly Ascend », comme la puce du HUD) ; si les deux le sont, l'aperçu s'ouvre sur l'onglet Grand Splorch et L1 / R1 passent à l'autre. Rectangles mis à jour dans `Layout_hud`, `Console_hud` et la ligne du GDD §10.2.

**Le panneau** (1 440 × 860 px TV, comme les autres, GDD §10.3 ; toutes les tailles sont en px TV à 1 920 × 1 080, mises à l'échelle par l'`UIScale` du GDD §10.1). Les zones sont calculées depuis le panneau, jamais l'inverse : 12 + 88 + 64 + 560 + 120 + 16 = 860 ; largeur utile 1 376 (marges de 32).

| Zone | y dans le panneau | Taille | Contenu |
|---|---|---|---|
| En-tête | 12 → 100 | 1 376 × 88 | Titre « Améliorations » 48 px ; à droite, 3 éléments **à place fixe** : pièces (icône 48 + montant 40 px, largeur 280), Confettis (icône 48 + montant 40 px, largeur 200 : entier brut jusqu'à 99 999, puis le formateur des grands nombres ; la largeur couvre « 99 999 » et « 999 K »), **bouton de mode** « ×1 » (icône □ dessinée 48 + texte 40 px, largeur 200, sélectionnable) |
| Onglets | 100 → 164 | 1 376 × 64, libellés 32 px | **Conseillé**, **Ranch**, **Plopettes**, **Atelier**. L1 / R1 changent d'onglet ; ↑ depuis le haut du contenu atteint les onglets, et ↑ encore le bouton de mode (règle des 3 touches) |
| Contenu | 164 → 724 | 1 376 × 560 | Conseillé : 3 cartes. Autres onglets : liste de lignes |
| Bandeau de détail | 724 → 844 | 1 376 × 120 | La phrase complète de ce qui est sélectionné : effet en entier, palier actuel et prochain, aperçu ×10 / Max, raison d'un refus. 28 px ; la boîte doit contenir la phrase **à la plus grande taille de texte du joueur** (3 lignes réservées, §2.3 règle 9). Vide : « — » (jamais un trou) |

**Onglet Conseillé** (ouvert par défaut) : **3 cartes de 432 × 528**, écart 32, posées à y = 16 dans la zone (3 × 432 + 2 × 32 = 1 360 : 8 px de marge à gauche et à droite, 16 en haut et en bas). La carte entière est l'élément sélectionnable ; le bouton est un dessin. Pile fixe, en px dans la carte (largeur utile 400) :

| y dans la carte | Hauteur | Élément |
|---|---|---|
| 16 → 96 | 80 | Icône dessinée en cadres |
| 104 → 152 | 48 | Nom de la famille, 36 px, 1 ligne (« Gants Moelleux », « École des Plopettes ») |
| 152 → 188 | 36 | Palier, 28 px, 1 ligne (« Bonbon arc-en-ciel ») |
| 192 → 232 | 40 | Niveau, 32 px : « Niv. 7 », flèche dessinée, « 8 » |
| 240 → 320 | 80 | Avant → après, 2 lignes de 32 px : « Pressions », puis « ×1,150 », flèche dessinée, « ×1,175 » |
| 328 → 364 | 36 | Raison courte, 28 px, 1 ligne (« Pour gagner plus ») ; la phrase entière va dans le bandeau |
| 372 → 420 | 48 | Prix : icône 48 + montant 40 px |
| 432 → 512 | 80 | Dessin du bouton « Acheter » (glyphe ✕ dessiné + texte 36 px) |
| 512 → 528 | 16 | Marge |

Le cadre de focus est **dessiné à l'intérieur de la carte**, sur ses bords, **sans grossissement** : rien ne sort jamais de la carte ni de la zone. Spec `Layout` : chaque rectangle enfant est dans sa carte et chaque carte dans la zone de 560 px, à 720p, 1080p et 4K, en anglais et en français. ← → passent d'une carte à l'autre ; ↓ ne fait rien (son `Bump`) ; ↑ va aux onglets. S'il manque une carte à l'ouverture (tout est au maximum), la place montre une carte neutre « Tout est au maximum ! Prochain but : Grand Splorch » : jamais un trou.

**Règle du Conseillé** (module pur `UpgradeAdvisor`, déterministe) : candidats = familles de **pièces** ouvertes et pas au maximum. (1) Le Tapis s'il est payable ; (2) puis la moins chère payable d'une autre famille ; (3) puis la moins chère payable d'une troisième famille ; s'il en manque, on complète avec les moins chères **non payables** (barre « Il manque … »). Jamais deux cartes de la même famille ; égalités départagées par l'ordre fixe des familles ; les Monuments n'apparaissent qu'après le Tapis 12 de la boucle. **Les 3 familles ne sont choisies qu'à l'ouverture de l'écran et à chaque retour sur l'onglet Conseillé.** Après un achat confirmé, **la carte garde sa famille** : elle montre le niveau suivant, ou MAX ; jamais une autre famille sous le curseur, donc un double appui n'achète jamais deux familles différentes. L'Atelier n'a plus de rangée de cartes : à l'ouverture de son onglet, un badge « Conseillé » (étoile dessinée) se pose sur au plus 3 de ses lignes (le moins cher achetable, à égalité dans l'ordre fixe), et ne bouge plus tant que l'onglet reste ouvert.

**Onglets Ranch, Plopettes, Atelier : des lignes de 1 328 × 112**, au pas de 128 (écart 16), avec **24 px de marge à gauche et à droite** dans le cadre de défilement : on voit 4 lignes entières et 48 px de la 5e (ce bout de ligne montre qu'on peut descendre). Hauteur de défilement = fonction pure `somme(hauteurs) + (n − 1) × 16`, où un titre de section compte comme un élément de 112 px non sélectionnable. Colonnes **de largeur fixe**, de gauche à droite :

| Colonne | x (dans la ligne) | Largeur | Contenu |
|---|---|---|---|
| Icône | 16 | 80 | Icône dessinée en cadres (aucune image téléversée) ; badge de 32 px dans le coin |
| Texte | 112 | 540 | Ligne 1 : nom de la famille, 36 px. Ligne 2 : **avant → après**, 32 px, en libellé court (« Croissance ×13 », flèche dessinée, « ×14 » ; tableau des libellés plus bas) |
| Niveau | 668 | 140 | « 12/30 » en 40 px ; dessous, barre de 140 × 12 vers le prochain palier. En mode ×10 / Max : « 12 », flèche, « 22 » |
| Prix | 824 | 240 | Icône 40 + montant 40 px (prix du mode choisi) ; dessous, barre de 240 × 8 de « ce que j'ai / ce qu'il faut » |
| État | 1 080 | 232 | **Icône 48 + un mot de 28 px**, jamais la couleur seule. FR / EN : coche « Prêt » / « Ready » ; sablier « Il manque » / « Need » ; étoile « MAX » / « MAX » ; cadenas « R 6 » / « R 6 » (Record R) ; **boucle « Splorch X »** / « Splorch X » (plafond de la boucle, Tapis Étoilé seulement) ; sablier animé « En cours » / « Busy » ; flèche « Réessaie » / « Retry » |

Une seule chose sélectionnable par ligne : la ligne elle-même (↑ ↓ seulement, aucun sous-bouton). Le cadre de focus est dessiné à l'intérieur de la ligne, sans grossissement. La sélection reste visible avec une ligne de marge (GDD §10.6). Le badge de l'icône dit ce que devient la ligne au Grand Splorch : icône dessinée **boucle** « repart de zéro » (Tapis, décorations, Gants, École) ou **infini** « gardé » (Enclos, Lit, Monuments, Atelier) ; le mot est écrit dans le bandeau.

**La ligne Tapis** (Tapis à Goûter et Tapis Étoilé sur une seule ligne) montre le maximum que la boucle permet. r < 10 : « 12/12 » avec l'étoile MAX, état **boucle « Splorch X »**, et dans le bandeau « Tapis Étoilé : à partir du Grand Splorch X dans cette boucle ». À r = 10 : « 12/14 » (ou « 14/14 » et « Splorch XII » une fois les deux niveaux pris), à r = 12 : « …/16 », et ainsi de suite jusqu'à 20. Le cadenas « R … » reste réservé au Record R : après une Ascension, un joueur au Record R 15 et à r = 3 voit « Splorch X », jamais « R 10 », qu'il lirait comme déjà gagné. Captures de référence : r = 3 après une Ascension, r = 10, r = 16.

**Ordre fixe des lignes** (configuration `Config/Upgrades`, jamais retrié)
- **Ranch** : Tapis à Goûter (et Tapis Étoilé sur la même ligne), Décorations, Enclos, Lit douillet, Gants Moelleux, Monuments.
- **Plopettes** : École des Plopettes, puis une ligne en lecture seule par Plopette (nom, « Presse toutes les 9,0 s », « Fait la sieste » le cas échéant). L'onglet est caché tant que les Plopettes sont éteintes par configuration ; allumé, il reste visible avec un cadenas « R 2 » avant Pip.
- **Atelier** : les 9 lignes du §3.4 dans leur ordre, puis 3 lignes en lecture seule « Monte avec le Grand Splorch » (Cuve, prochain palier de ranch, prochain déblocage), puis le titre de section « Pour le plaisir » et les cosmétiques.
- **Toutes les lignes d'un onglet existent toujours**, même verrouillées (cadenas et condition) : **aucune ligne n'est jamais ajoutée, retirée ou déplacée pendant que l'écran est ouvert.** On voit ce qui arrive, et la mise en page ne bouge jamais.
- **L'écran est construit une seule fois par session**, pendant le chargement, puis montré ou caché (`Visible`) : rouvrir ne crée aucune instance. Les interrupteurs (Plopettes, Plume, Tremplin), la liste des contenus datés déjà sortis (champ `release`) et les maxima des familles sont **figés à l'ouverture**. Seul le serveur décide qu'un contenu est sorti et il réplique la liste des identifiants sortis (le client ne lit jamais sa propre horloge pour cela). Un changement pendant que l'écran est ouvert ne s'applique qu'à la prochaine ouverture ; un changement d'interrupteur reconstruit l'écran **pendant qu'il est fermé**. Jamais un onglet ni une ligne qui apparaît sous les yeux du joueur.

**Acheter ×1, ×10 ou Max**
- Le **bouton de mode** de l'en-tête fait tourner **×1 → ×10 → Max → ×1**. On l'atteint avec ↑ depuis les onglets et on appuie sur ✕ : le D-pad, ✕ et ○ suffisent, comme partout (règle des 3 touches) ; □ est un raccourci ; **E** au clavier (les touches de jeu ne servent pas dans le panneau) ; un clic aussi. **Le mode revient à ×1 à chaque ouverture** de l'écran : un petit frère qui reprend la manette ne vide pas la cagnotte.
- **×1 : un appui** sur ✕, sur Entrée ou un clic. **×10 et Max : maintien de 0,6 s** de ✕, d'Entrée ou du bouton de la souris (anneau autour du glyphe, même durée que sur une dalle). Un appui court en ×10 / Max démarre l'anneau ; relâché trop tôt, l'anneau se vide, son `Bump`, et le bandeau dit « Maintiens ✕ pour acheter ×10 » (glyphe selon l'appareil) : jamais un bouton qui semble mort.
- **Aperçu exact avant d'acheter** : en ×10 / Max, la colonne Niveau montre « 12 → 22 » (flèche dessinée) et la colonne Prix le total ; le bandeau dit la phrase entière, sans flèche : « ×10 : niveau 12 à 22 · 1,23 M », « Max (×7) : niveau 12 à 19 · 845 K », ou « ×10 : 4 possibles · niveau 12 à 16 · 310 K ».
- **Retour chiffré, toujours** : dans la ligne même, « +7 niveaux · −1,2 M » pendant 1,5 s, son `TileBuild`, vibration `tileBuy`. Si rien n'est payable : la raison (« Il manque 1,2 K »), son `Error` doux, vibration `refuse`, aucune secousse. Sur un refus du serveur, l'écran montre **la raison et le montant envoyés par le serveur**, jamais un calcul du client.
- Max ne dépense que dans **la famille choisie**. Achat partiel accepté et annoncé (« 4 sur 10 »).

**Entrées protégées** (`InputGuard`, dans `InputController` ; pour cet écran, l'aperçu des renaissances et leurs cartes). Après l'ouverture d'une fenêtre, ✕ est ignoré **tant qu'on n'a pas vu ✕ relâché et qu'au moins 0,3 s n'est pas passée** ; quand l'élément sous le focus change d'identifiant (onglet, Conseillé recalculé au retour sur l'onglet), même règle avec 0,4 s. Un achat part d'un `InputBegan` de `ButtonA` capté par `ContextActionService` (ou d'Entrée, ou du bouton de la souris sur la ligne), **jamais** de `GuiButton.Activated`, qui peut partir à l'appui comme au relâchement. Pendant qu'une ligne est « en cours », ses appuis sont ignorés. Specs du robot manette : « △, puis ✕ tenu 2 s » ne produit aucun `BuyUpgrade` ; « maintien de 3 s de l'Ascension, puis ✕ gardé enfoncé » ne confirme jamais ; ✕ appuyé 10 fois à 100 ms d'écart sur la carte 1 : tous les `BuyUpgrade` portent la même famille ; chaque mode est atteint et utilisé avec le D-pad, ✕ et ○ seulement.

**Libellés courts** (2e ligne de la colonne Texte). Écrits dès maintenant en français et en anglais et ajoutés à `TextFitPending` avant le code ; les valeurs sont celles du joueur ; la phrase entière va dans le bandeau ; « → » est une flèche dessinée entre deux libellés, jamais un caractère.

| Ligne | FR | EN |
|---|---|---|
| Cadeau du Splorch | Cadeau : 1 → 2 niv. | Gift: 1 → 2 lv |
| Tapis de départ | Départ : Tapis 0 → 1 | Start: Mat 0 → 1 |
| Aimant à pièces | Aimant : 5 → 8 studs | Magnet: 5 → 8 studs |
| Super Série | Série max : 5 → 6 | Max streak: 5 → 6 |
| Déco qui reste | Déco gardées : 6 → 9 | Kept decor: 6 → 9 |
| Sac de nuit | Nuit : 12 h → 13 h | Night: 12 h → 13 h |
| Pot de nuit | Pot la nuit : 25 % → 30 % | Night pot: 25% → 30% |
| Plume | Plopettes : 5 → 6 | Plopettes: 5 → 6 |
| Tremplin | Tremplin : 0 → 1 | Springboard: 0 → 1 |

**La puce « Prochain achat »** du HUD : colonne de gauche, alignée sur la pastille des pièces, à (96, 342), **440 × 96** (sous la puce Menu, qui finit à y = 326). Ligne 1 : icône 48 + nom court de la famille (12 caractères au plus : Tapis, Gants, Déco, Enclos, École, Lit, Monument) + « Niv. 8 », 32 px. Ligne 2 : barre et « 12,3 K / 20 K », 28 px. Quand c'est payable : « Prêt ! » et **une seule** pulsation (jamais de clignotement). Elle a sa propre fonction pure, `UpgradeAdvisor.next(état)`, évaluée **au plus 2 fois par seconde** quand les pièces changent et après **tout** achat (écran ou dalle au sol) ; **sa cible ne change qu'après un achat**, jamais pendant que la barre se remplit. Cachée pendant l'accueil jusqu'à la leçon du menu (GDD §3), quand le menu ou un panneau est ouvert (elle ne chevauche donc jamais le rail), quand le suivi du Grand Splorch affiche « Prêt » (le prochain but est alors le Grand Splorch) et quand la carte de la cible est affichée : le HUD calme ne montre ainsi **jamais plus de 8 éléments** (GDD §10.2 ; spec `Layout_hud` sur tous les états, rectangles mis à jour).

**« Dépenser d'abord »** (aperçu du Grand Splorch, GDD §4.15) ouvre l'écran sur l'onglet Ranch, **sans changer l'ordre** : la sélection se pose sur la première ligne **gardée** et payable (Enclos, Lit douillet, Monuments), sinon sur la première ligne gardée. ○ ramène à l'aperçu : ○ revient toujours à ce qui a ouvert l'écran.

### 2.3 Les règles « zéro bug d'affichage »

Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration. Clash of Clans en a reconnu deux sur son nouvel écran (tri, compteur qui repart de 0, 08/10/2026 [08-60]). Chaque règle ci-dessous a un test **bloquant**.

| # | Règle | Test |
|---|---|---|
| 1 | **Ordre fixe.** Aucun tri dynamique ; les familles du Conseillé ne sont choisies qu'à l'ouverture et au retour sur l'onglet ; une carte garde sa famille après un achat ; la sélection reste sur la même ligne ou le même emplacement de carte | Rejouer 1 000 achats au hasard : l'ordre ne change jamais, la sélection reste en place, aucune carte ne change de famille |
| 2 | **Aucune ligne détruite ni créée** pendant que l'écran est ouvert ; écran construit une fois, au chargement ; lignes verrouillées toujours présentes | Spec de structure : même nombre d'instances avant et après 1 000 achats ; une réouverture crée 0 instance |
| 3 | **Un compteur ne repart jamais de 0.** Montré pour la première fois (ouverture, onglet), il affiche directement sa valeur ; il ne s'anime que si la valeur change pendant qu'il est visible, depuis la **dernière valeur affichée**. Au Grand Splorch, les pièces passent à 0 sans animation, avec un « pouf » | Changer d'onglet 50 fois : aucun nombre ne vaut transitoirement « 0 » |
| 4 | **Valeur finale toujours posée** à la fin d'une animation **et** à son interruption | Capture après interruption à 0 %, 50 %, 100 % : même image |
| 5 | **Un seul calcul de prix**, le module pur `UpgradeMath`, partagé par l'aperçu du client et le serveur ; **aucune puissance** (`^`, `math.pow`, `math.exp`) : tables par multiplications successives dans un ordre fixe ; jamais de prix en cache ; somme exacte niveau par niveau (boucle de 30 au plus) ; sur un refus, l'écran montre le montant du serveur | Propriété : `bulk(n)` = somme de n achats ×1 ; aperçu = débit réel dans 10 000 cas tirés au hasard ; test statique : aucun `^` dans `Logic/UpgradeMath` et `Logic/Prestige` ; cas exacts du §2.1 |
| 6 | **Un seul instantané versionné.** L'écran ne lit qu'un objet `{ coins, confetti, levels, version }`, envoyé dans `UpgradeResult` **et** dans le correctif de données ; l'état « payable » ne se calcule que sur lui ; un instantané plus ancien que celui affiché est ignoré. (Un même `RemoteEvent` livre dans l'ordre ; le vrai risque est le mélange de deux canaux : pièces par le correctif, niveaux par la réponse) | Livrer le correctif des pièces et `UpgradeResult` dans les deux ordres : la colonne État ne clignote jamais (Prêt → Il manque → Prêt) et la barre de prix ne montre jamais un état périmé |
| 7 | **Largeurs réservées** pour la plus longue valeur formatée (« 8,88e305 », 8 caractères à 40 px ; Confettis : « 99 999 » et « 999 K ») ; aucun `AutomaticSize` sur une ligne ; rien ne change de taille quand un nombre grandit ; r ≤ `MaxR`, A ≤ `MaxA` | Propriété sur 10 000 nombres : largeur mesurée ≤ largeur réservée ; formateur à 1e308 et à `math.huge` : le plus grand suffixe, jamais « inf » ni « nan » |
| 8 | **Un seul formateur par sorte de nombre**, selon la langue, troncature écrite : `BigNumber.abbreviate` pour les montants (GDD §4.2 : 3 chiffres tronqués, suffixes K à Dc, puis « 1,23e36 ») ; **`Format.multiplier`** (Gants, Super Série : ×1,175, toujours 3 décimales ; croissance : ×14, entier) ; **`Format.percent`** (+5 %, entier) ; **`Format.seconds`** (9,0 s, 1 décimale). **Une couleur par famille de suffixes** : K-M blanc, B-T or, Qa-Qi rose, Sx et au-delà cyan (Sx et Sp ne se confondent plus [08-104]). Tout texte de l'interface passe par **`Text.set(label, clé, args)`** | Propriétés : deux niveaux voisins donnent toujours deux textes différents ; carte, ligne et bandeau montrent le même texte ; test statique : aucune affectation `.Text =` hors de `Text`, et aucun `tostring`, `..` ni `string.format` de nombre dans `UI/*` hors de `Text` et `Format` |
| 9 | **Texte mesuré, une seule politique** (GDD §10.1 v1.4). `TextSize` fixe partout, **jamais `TextScaled`** : il n'est pas agrandi par la taille de texte choisie par le joueur [W3][08-145]. Noms, nombres et libellés des cartes et des lignes : `UITextSizeConstraint.MaxTextSize` = taille dessinée (28 à 48 px TV ; la documentation dit que cette limite tient quel que soit le réglage du joueur [W3]) ; 1 ligne pour un nom, 2 au plus pour l'avant → après d'une carte. Phrases du bandeau : elles grandissent avec le réglage, dans une boîte prévue pour la taille Largest. **Aucun rétrécissement automatique en jeu** : un texte qui ne tient pas fait échouer la porte | `TextFit_all.spec` (outil Screens) sur toutes les clés nouvelles, en anglais et en français, **à la taille Medium et à la taille Largest** ; les 4 facteurs de `PreferredTextSize` sont mesurés une fois dans Studio et écrits dans `TextMetrics` (l'outil ne les connaît pas encore) |
| 10 | **Tailles fixes, calculées depuis la zone** : carte 432 × 528, ligne 1 328 × 112 au pas de 128 ; un seul layout par parent ; hauteur de défilement par fonction pure, jamais une `ScrollingFrame` en taille automatique [08-161] | Spec `Layout` : chaque rectangle enfant dans sa carte ou sa ligne, chaque carte dans la zone de 560 px, à 720p, 1080p et 4K, en anglais et en français ; aucun parent avec deux `UI*Layout` |
| 11 | **Un seul composant de carte** (`UI/UpgradeCard`, 2 gabarits fixes : carte et ligne), partagé par Ranch, Plopettes, Atelier et les aperçus de renaissance | Toutes les variantes testées une fois, dans tous les états |
| 12 | **État « en cours » de 3 s** par ligne (sablier, appuis ignorés) ; sans réponse, la ligne revient et dit « Réessaie » ; une réponse tardive est appliquée normalement (l'écran affiche toujours l'état du serveur, jamais un état deviné) ; un refus « périmé » (`expectedLevel` dépassé) alors que l'instantané montre déjà le niveau visé ne produit **aucun** retour visible, seulement le compteur `UpgradeStale` ; compté dans Diagnostics (`UpgradeTimeout`) | Serveur muet : retour à l'état normal en 3 s, focus intact ; réponse à 3,5 s puis nouvel appui de l'enfant : exactement **un** retour « +n niveaux » |
| 13 | **Jamais un achat muet** : chaque réponse du serveur produit exactement un retour visible (« +n niveaux · −prix » ou la raison), sauf le refus périmé de la règle 12 | Spec : 1 réponse = 1 retour |
| 14 | **Bouton remis à l'état normal** après chaque appui à la manette, rafraîchissement ou changement d'onglet (le bouton qui reste « appuyé » est un bug connu de Roblox [08-65]) ; **cadre de focus dessiné par nous, à l'intérieur de l'élément** (6 + 2 px), **sans grossissement** pour les lignes, les cartes et les boutons du rail | Robot manette : après achat, Max, rafraîchissement, aucun élément « appuyé » ; assertion `FocusGuard` / `Layout` : le rectangle du cadre de focus est entièrement dans le rectangle de découpe de chaque ancêtre qui découpe (`ScrollingFrame`, `ClipsDescendants`, `CanvasGroup`), pour chaque ligne et chaque carte, dans chaque état |
| 15 | **Focus jamais perdu ni piégé** (`FocusGuard`, GDD §10.6) ; le focus reste sur la carte achetée, même si elle passe à MAX | Robot croix + ✕ + ○ sur les 4 onglets et le bouton de mode, à chaque état |
| 16 | **Aucun Robux dans cet écran.** Les prix en Robux restent dans la Boutique, lus par joueur avec la remise Roblox Plus [08-125] | Test statique : aucune clé de produit dans `UI/Panels/Upgrades` |
| 17 | **Un ✕ n'achète jamais par accident** (`InputGuard`, §2.2) : relâchement vu, puis 0,3 s après une ouverture (0,4 s après un changement sous le focus) ; achat sur un `InputBegan` capté, jamais sur `Activated` | Robot : « △ puis ✕ tenu 2 s » = 0 `BuyUpgrade` ; maintien de l'Ascension prolongé = jamais confirmé ; 10 appuis à 100 ms = une seule famille |
| 18 | **Aucun symbole hors police** : → ✓ ★ ∞ ↺ ✦ et les glyphes de manette sont des icônes dessinées en cadres, jamais des caractères ; la flèche « avant → après » est une icône posée entre deux libellés | Test de contrat : chaque clé EN et FR n'utilise que des caractères présents dans la table `cmap` de FredokaOne et de LuckiestGuy, lue dans les fichiers de police **rangés dans le dépôt** |
| 19 | **Seul le serveur dit ce qui est sorti** (champ `release`, maxima des familles) ; l'écran fige cette liste à l'ouverture, comme les interrupteurs | Franchir une heure de sortie écran ouvert : rien ne change avant la prochaine ouverture ; jamais un achat refusé pour « pas encore sorti » |
| 20 | **Budget d'instances de l'écran : 1 400 au plus** (§4.6) ; ombre (`UIShadow`) seulement sur le panneau et les cartes, jamais par ligne | Après la première ouverture : nombre d'instances ≤ budget ; réouverture : 0 instance créée |

**Captures de référence** (outil Screens) aux 3 résolutions (1 280 × 720, 1 920 × 1 080, 3 840 × 2 160) × 2 langues × 2 tailles de texte (Medium, Largest) × 2 qualités, pour ces états : r = 0 tout neuf ; r = 5 ; r = 20 tout au maximum ; r = 3 après une Ascension (état « Splorch X ») ; r = 10 ; r = 16 ; pièces à 1e300 ; Confettis à 99 999 et à 100 000 ; tout verrouillé ; une ligne « en cours » ; une ligne « Réessaie » ; chaque mode ×1 / ×10 / Max ; Atelier vide, à moitié, complet. Toute différence d'image non voulue fait échouer la porte. **Limite connue** : le moteur de rendu hors ligne de l'outil (`tools/screens/renderer.js`, commit bf3e275) ne dessine que `UIStroke` et les dégradés linéaires, ni `UIShadow` ni dégradé radial. Les captures de référence se font donc **dans le style de repli à plat** (§4.1), qui doit être propre à lui seul ; le vrai style (ombres, dégradés radiaux) n'est vérifié que sur l'appareil, aux tests M6 et M14 sur PS5 et PS4 (annexe B).

---

## 3. Renaissance

### 3.1 Les couches

| | **Couche 1 : Grand Splorch** | **Couche 2 : Jelly Ascend** |
|---|---|---|
| Statut | GDD v1.3, enrichi ; au lancement | Code prêt avant le lancement, **éteint** (`Features.JellyAscend = false`) ; allumé le **samedi 26 décembre** si la porte est verte, sinon le 2 janvier |
| Condition | Plus gros squishy ≥ objectif(r) : 15 000 × 2,6^r (table du GDD §4.15) | **r ≥ 15** pour la 1re, **20** pour la 2e, puis **+4** à chaque Ascension (24, 28, 32…) |
| Repart de zéro | Pièces, Pot, Tapis (et Tapis Étoilé), décorations non gardées, Gants, École, taille de chaque squishy | Tout ce que repart le Grand Splorch, **et r** (retour au Grand Splorch de départ) |
| Toujours gardé | Squishies (espèce, mutation, étoiles, tenue, verrou), Record R et tous ses déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, Enclos, Lit, Cuve, selles, Squishydex, Étagère, Fame, jours de Plop, passes, cosmétiques | Idem |
| Gain | Croissance ×2 (pour la boucle), **3 + r Confettis** si c'est un nouveau Record R (1 sinon), cadeau du Splorch, un déblocage nommé à chaque nouveau Record R, +5 Fame (50 par jour au plus) | **Croissance ×3 pour toujours** (×3^A), **+20 Confettis**, une goutte de halo, un élément de ciel, un titre, des lignes nouvelles à l'Atelier, +20 Fame ; les prix de la boucle sont ensuite ×1,6 par Ascension (§3.5) |
| Première fois (joueur de référence, 30 min par jour) | 12,5 min (mesuré) | **Jour 13** (mesuré : p10 jour 12, p90 jour 14) ; **jour 6** pour un joueur de 2 h par jour (mesuré) |

**Pas de 3e couche** dans ce plan. Une décision ne viendra pas avant mars 2027, sur les données (par exemple : part des joueurs du jour 30 qui ont fait 8 Ascensions), et sans 3e monnaie.

**Le Record R, seule règle à retenir.** Tout ce qu'on **voit ou possède** (familles d'espèces, Cuve, Meilleurs Amis, Lit douillet, titres, paliers de ranch, changements du ranch, Plopettes, Monuments ouverts, lignes de l'Atelier, cosmétiques) suit le **Record R**, qui ne baisse jamais. Ce qui règle **l'économie de la boucle** (objectif de taille, prix ×3,5^r, croissance ×2^r, plafond du Tapis Étoilé, Confettis gagnés) suit **r**. Une Ascension ne fait donc jamais disparaître une arche, une buse, un Meilleur Ami ou une Plopette.

**Des textes vrais.** Avec une couche au-dessus, « Croissance ×2 **pour toujours** » (GDD §4.15, §9.4) deviendrait faux. La tuile devient « **Croissance ×2** » et le spectacle dit « Plop est là ! ×2 ! ». « Pour toujours » reste écrit seulement sur ce qui l'est vraiment : squishies, déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, ×3 de chaque Ascension. C'est la règle du GDD « ce qu'on voit est vrai » (§12.10) appliquée aux mots.

### 3.2 Grand Splorch et Petit Splorch

- **Grand Splorch** (le nouveau r dépasse le Record R) : tout le GDD §4.15 sans changement (aperçu, maintien de 1,5 s, file du serveur, spectacle de 7,5 s, cadeaux pour tout le serveur). Avant toute Ascension, **chaque** renaissance est un Grand Splorch : le lancement se joue exactement comme le GDD.
- **Petit Splorch** (le nouveau r est ≤ Record R ; n'existe qu'après une Ascension) : même aperçu et même maintien de 1,5 s, mêmes conditions d'entrée (dans son ranch, rien porté, aucun squishy en fuite), mais **hors de la file du serveur** et appliqué tout de suite, d'un seul bloc. Le serveur écrit sur le ranch l'attribut répliqué **`PetitSplorchAt`** (heure du serveur) : **chaque client qui dessine ce ranch en détail complet** (lui et ses 2 voisins, §4.2) joue la même animation de 2,5 s à partir de cette heure (coupure dure à 4 s) : le squishy saute, rétrécit avec un « pouf », pluie de confettis sur le ranch, petit texte « Plop est là ! ×2 ». Les clients plus loin posent directement l'état final. Pas de bannière, pas de cadeaux aux autres. Il donne **1 Confetti** et le cadeau du Splorch. Raison : le GDD limite chaque serveur à un Grand Splorch toutes les 20 s ; 6 à 8 vétérans à boucles courtes après une Ascension satureraient la file et retarderaient le premier Grand Splorch des nouveaux joueurs (remarque du jury). Spec : un client voisin joue l'animation et finit sur le même état que le propriétaire.
- **Plafonds sociaux** : Fame du Grand Splorch +5, **50 par jour au plus** (`Balance.Caps.fameSplorch = 50`) ; un même joueur déclenche **au plus une bannière « GRAND SPLORCH » toutes les 3 min** (sinon une petite ligne).

**L'aperçu montre toujours 3 tuiles concrètes**, jamais une tuile vide : « Croissance ×2 » ; **le déblocage de ce niveau** (une image et 2-3 mots : « Place d'enclos offerte », « 3 décorations restent ! ») ou, s'il est déjà gagné, « Cadeau du Splorch » ; « +13 Confettis » pour un Grand Splorch, **« Petit Splorch : +1 Confetti »** pour un Petit Splorch.

**Le cadeau du Splorch** (gratuit pour tous dès le premier Grand Splorch) : juste après l'éclatement, une pluie de pièces dorées tombe dans le Pot. Elle vaut **le prix du prochain niveau du Tapis** dans la nouvelle boucle (1 niveau ; 2 puis 3 avec la ligne de l'Atelier) : l'enfant rachète le Tapis dans les 30 s et sent la vitesse doublée (gain senti dans les 30 s, conseil des développeurs de jeux idle, confiance faible [08-88]). **Plafond** : le Tapis de départ et le cadeau ensemble ne donnent jamais plus de **6 niveaux** du Tapis au début d'une boucle (3 + 3) ; les niveaux 7 à 12 restent des achats de la boucle.

### 3.3 Un déblocage nommé et visible à chaque Grand Splorch

Une seule table en données (`Balance.Splorch.Unlocks` pour ce qui se débloque, `Config/Visuals.RanchByRecordR` pour ce qui se voit), lue par le serveur, l'aperçu et le rendu du ranch. Chaque ligne s'applique **au premier passage** du Record R.

| Record R | Débloqué (tuile de l'aperçu) | Ce qui change dans le ranch | Arrive plus tard (donné tout de suite à qui a déjà ce Record R) |
|---|---|---|---|
| 1 | **Atelier de Big Plop** (+4 Confettis) · **Gants Moelleux** · famille Axolo · cadeau du Splorch | Palier 1 **Arche à pompons** · Cuve : 2e anneau, 1re buse | Habillage « Guimauve » (2 janv.) |
| 2 | **Place d'enclos offerte** · selle « Confetti » | Pot **argent** · coussin offert · Cuve : 3e anneau, 2e buse, agitateur plus rapide | **Pip** et l'École des Plopettes |
| 3 | Famille Bunny · 2e Meilleur Ami · Lit douillet | Palier 2 **Tour à bonbons** · Cuve : 4e anneau, 3e buse | Habillage « Caramel » |
| 4 | Emote « Splorch ! » | **Agitateur arc-en-ciel** (vitesse maximale) · 5e anneau, 4e buse | **Pop** |
| 5 | Famille Spiky · titre Splorch Star | Palier 3 **Balcon de gelée** · 5 buses (maximum) · 6e anneau | Habillage « Menthe glacée » |
| 6 | **Place offerte** · Monument 1 à construire · traînée « Confettis » | Pot **doré** · coussin offert · 7e anneau | **Pim** |
| 7 | **Cuve dorée** · tenue « Chapeau de fête » | La Cuve devient dorée (8e anneau), visible de la rue | — |
| 8 | **« 3 décorations restent »** · Monument 2 | Fanion ★ sur les 3 décorations gardées | **Pom** |
| 9 | Palette de spectacle « Feu d'artifice » · drapeau « IX » | **Bassin-fontaine** : 3 jets de gelée | — |
| 10 | 3e Meilleur Ami · titre Splorch Legend · **Tapis Étoilé** 13-14 · Monument 3 | Palier 4 **Phare de gelée** | Habillage « Phare » |
| 11 | **Place offerte** · selle « Gelée d'or » | **Coussins étoilés** · coussin offert | — |
| 12 | Tapis Étoilé 15-16 · Monument 4 · ligne **Plume** à l'Atelier | **8 lampions** sur la clôture (allumés pendant la Jelly Moon) | **Puff** · habillage « Glacier sucré » |
| 13 | Emote « Ola » · traînée « Arc de gelée » | **Portail arc-en-ciel** (7 segments fixes, aucun clignotement) | — |
| 14 | **« 3 décorations de plus restent »** (6) · Tapis Étoilé 17-18 · Monument 5 | Fanions ★ sur 6 décorations | — |
| 15 | Titre Splorch Hero · **Jelly Ascend** (dès son allumage) | Palier 5 **Dôme néon** | Habillage « Néon » · faisceau de l'Observatoire quand l'Ascension est prête |
| 16 | **Place offerte** · Tapis Étoilé 19-20 · Monument 6 · tenue « Lunettes étoiles » | Pot **cristal** (matériau `Ice`, sans transparence) · coussin offert | — |
| 17 | Selle « Cosmos » | **Geyser de gelée** dans le ranch, côté rue (Z = 4 à 10, à 6 studs au moins des dalles, hors du chemin du portail), vu de la rue | Habillage « Cosmos sucré » |
| 18 | Monument 7 | **Cadre doré** autour de la silhouette du ranch | — |
| 19 | Emote « Couronne de confettis » · drapeau « Splorch Royal » | **Étagère à trophées dorée** | — |
| 20 | Titre Jelly Titan · Monument 8 · selle « Titan » | Palier 6 **Couronne flottante** | Habillage « Royal » |
| 21 et plus | **Prime de record** : +10 Confettis au premier passage de chaque Record R | — | — |
| 22, 24 | Monuments 9 et 10 | — | — |
| 25, 30, 35, 40 | Titres Splorch Myth, Jelly Monarch, Wobble Legend, Cosmic Splorcher · une couleur de traînée | 1 à 4 étoiles sur la couronne | — |
| 50, puis tous les 10 jusqu'à 400 (`MaxR`) | Titre écrit en données | Couronne arc-en-ciel au 50 | — |

Chaque R de 1 à 20 a **au moins une entrée de la colonne « ranch » disponible au lancement** : la table reste complète même si les Plopettes et les habillages arrivent plus tard. Test bloquant : chaque R de 1 à 20 a au moins un déblocage nommé et au moins un changement visible ; chaque clé existe en anglais et en français ; l'aperçu montre toujours 3 tuiles.

### 3.4 L'Atelier de Big Plop : chaque ligne, chaque niveau

**Confettis** : **3 + r** à chaque **Grand Splorch** (nouveau Record R ; r après la renaissance), **1** par Petit Splorch et **1** par Grand Splorch sauté (Grand Splorch de départ et Tremplin, §3.5), **+20** par Jelly Ascend, plus la prime de record (+10 au premier passage de chaque Record R au-delà de 20), plus +25 si une place offerte tombe sur un enclos plein, plus la piste de la semaine (34 par semaine, à partir du 2 janvier). **Jamais vendus, jamais une chance, jamais remis à zéro**, même par une Ascension.

Pourquoi 1 seulement par Petit Splorch : payer 3 + r à chaque boucle rejouée faisait repayer toute la remontée à chaque Ascension (165, 270, 400… Confettis par cycle). Mesuré avec cette ancienne règle : 1 160 Confettis en poche au jour 84 pour le joueur de référence, 3 004 au jour 56 pour le joueur de 2 h par jour ; ils n'achetaient plus rien. Avec la règle actuelle (mesuré, 20 joueurs, 56 jours) : 18 à 57 Confettis en poche jusqu'au jour 56, 682 à 820 gagnés au jour 56, et les lignes de l'Atelier toujours achetées (7 à 8 lignes finies aux jours 42-56).

| Cumul au premier passage | R1 | R2 | R5 | R8 | R10 | R12 | R15 | R20 | R25 | R30 |
|---|---|---|---|---|---|---|---|---|---|---|
| Grands Splorch et prime de record | 4 | 9 | 30 | 60 | 85 | 114 | 165 | 270 | 450 | 655 |
| Avec les places offertes sur un enclos plein (R6, R11, R16) | 4 | 9 | 30 | 85 | 110 | 164 | 215 | 345 | 525 | 730 |

Mesuré (configuration du lancement, sans la piste) : **379 Confettis gagnés au jour 28**, au Record R 21 : c'est la 2e ligne (les enclos sont pleins dès R6). Les portes lisent ces totaux dans la simulation `EconomyPacing`, avec les mêmes valeurs `Balance`, jamais dans une somme faite à la main. Montant affiché : entier brut jusqu'à 99 999, puis le formateur des grands nombres (§2.3, règle 7). Icône dessinée en cadres (3 petits rectangles inclinés rose, menthe, jaune), de forme et de couleur différentes de la pièce. Le compteur n'est pas dans le HUD (règle « peu d'éléments », GDD §10.2) : il est dans l'en-tête de l'écran Améliorations, dans l'aperçu du Grand Splorch et sur la carte de récompense.

| # | Ligne (FR / EN) | Niveaux | Coût de chaque niveau (Confettis) | Effet | Condition |
|---|---|---|---|---|---|
| 1 | Cadeau du Splorch / Splorch Gift | 2 | 3 · 25 (28) | Le cadeau du Splorch paie **2 puis 3** niveaux du Tapis (les prochains, après ceux du Tapis de départ) au lieu de 1 | Record R ≥ 1 |
| 2 | Tapis de départ / Head-Start Mat | 3 | 12 · 30 · 60 (102) | Chaque boucle commence avec le Tapis déjà au niveau 1, 2 puis 3 | Record R ≥ 1 |
| 3 | Aimant à pièces / Coin Magnet | 3 | 4 · 8 · 14 (26) | Rayon d'encaissement du Pot : 5 → 8 → 11 → 14 studs | Record R ≥ 1 |
| 4 | Super Série / Super Streak | 2 | 10 · 20 (30) | Série PERFECT jusqu'à 6 puis 7 (+60 % puis +70 % au lieu de +50 %) | Record R ≥ 1 |
| 5 | Déco qui reste / Kept Decorations | 4 | 15 · 60, puis 100 · 180 (355) | +3 décorations gardées au Grand Splorch par niveau (18 au plus avec celles des R8 et R14) | Niveaux 3 et 4 : A ≥ 1 |
| 6 | Sac de nuit / Night Bag | 3 | 6 · 12 · 20 (38) | Limite hors ligne +1 h par niveau. **Maximum : 16 h** (8 h de base + 4 h du Lit + 3 h du Sac + 1 h de la famille Spiky, GDD §4.19). La croissance hors ligne s'arrête toujours à 90 % de l'objectif | Record R ≥ 1 |
| 7 | Pot de nuit / Night Pot | 2 | 15 · 30 (45) | Pièces hors ligne dans le Pot : 25 % → 30 % → 35 % du revenu (ramené à 30 % au plus si la porte « une connexion par jour » échoue, §6.3) | Record R ≥ 1 |
| 8 | Plume (6e Plopette) | 1 | 40 | Une Plopette de plus | Record R ≥ 12 et Plopettes allumées |
| 9 | Tremplin / Springboard | 3 | 40 · 80 · 150 (270) | Après une Ascension, on repart 1, 2 puis 3 Grands Splorch plus haut ; chaque Grand Splorch sauté rapporte 1 Confetti | A ≥ 1 |
| | **Total des 9 lignes** | **23** | **934** | | |

**Plafond de 6 niveaux offerts** : Tapis de départ (3) + cadeau (1 + 2) = 6 au plus. Les anciens niveaux 4 et 5 du Tapis de départ (A ≥ 1) et 4 à 6 du cadeau sont supprimés : ensemble, ils posaient le Tapis au niveau 11 dès le début de chaque boucle, ce qui raccourcissait trop les boucles après une Ascension (§3.5) et faisait du Tapis un achat qu'on ne fait plus.

**Section « Pour le plaisir »** (en bas du même onglet, pour les Confettis en trop) : 6 palettes de couleurs du spectacle du Grand Splorch (Bonbon, Menthe, Lavande, Arc-en-ciel, Nuit douce, Sucre glace ; 20 chacune), selle « Cotillon » (40), traînée « Serpentins » (50), emote « Danse de Big Plop » (60), titre « Confetti Star » (100) : **370**. Au lancement : 3 palettes et la selle (100).

**Au lancement** : lignes 1 à 7 sans les niveaux réservés à A ≥ 1 (**344 Confettis**, 17 niveaux). Mesuré, sans la piste : tout est acheté **vers le jour 28, au Record R 21** (7 lignes finies au jour 28). Plume suit les Plopettes ; Tremplin et les niveaux A ≥ 1 suivent la Jelly Ascend. Au total, Atelier et cosmétiques valent **1 304 Confettis** : 2 à 3 mois pour le joueur de référence (inférence d'après les 682 à 820 Confettis gagnés au jour 56, piste non comprise).

**Ce que l'Atelier ne vend jamais** (test de contrat sur la liste fermée des effets) : rien qui touche la croissance (sauf le Tapis de départ, qui n'est que du Tapis acheté d'avance), une probabilité, la Cuve, les créatures en fuite, le Golden Wobbler, les mutations, les raretés ; rien qui allonge le combo maximal (classement « Meilleur combo » juste, GDD §6.9) ; rien qui double un pass payant (pas de Pot automatique, pas de places au-delà de 18).

**Pourquoi les 8-13 ans vont aimer.** Les meilleurs tycoons séparent une progression remise à zéro et une couche permanente gagnée au prestige : Investisseurs et Powers de Sell Lemons, recherche « Lemon Labs » gardée aux remises à zéro (2026) [08-44][08-46]. L'Atelier transforme le Grand Splorch en « je gagne quelque chose à moi », pas seulement « ×2 » (inférence).

### 3.5 Jelly Ascend en détail

| Paramètre (configuration `Balance.Ascend`) | Valeur de départ (cible) |
|---|---|
| Condition de la k-ième Ascension | r ≥ `ReqR[k]` : **15, 20**, puis **+4** à chaque fois : 24, 28, 32… (`ReqR = {15, 20}`, `ReqStep = 4`) |
| Gain | Croissance **×3 pour toujours** par Ascension (`GrowthMult = 3`) ; **+20 Confettis** une fois (`Balance.Confetti.PerAscend = 20`) |
| Prix de la boucle | Tapis, Tapis Étoilé, Décorations, Gants et École **× 1,6^A** (`PriceMult = 1,6`) ; pas l'Enclos, le Lit ni les Monuments |
| Grand Splorch de départ après la A-ième Ascension | `StartR(A) = min(ReqR[A+1] − 10, max(2 × (A − 1) + Tremplin, ceil(A × ln(GrowthMult) / ln(BeyondMult / 2) − 8,9)))`, où ln 3 / ln 1,3 = 4,19 (`StartFloorOffset = 8,9`). Sans Tremplin : **0, 2, 4, 8, 13, 17, 21, 25, 29, 33** pour A1 à A10. Chaque Grand Splorch sauté rapporte **1 Confetti** (`StartR`) |
| Bornes | `MaxA = 60` ; `MaxR = 400` |
| Fame | +20 |
| Halo | Une goutte de plus, jusqu'à 5 |
| Ciel du ranch | A1 Nuage-coussin, A2 Arc de gelée, A3 Aurore sucrée (3 rubans `Neon` courbes, sans particules), A4 Planète bonbon, A5 Anneau prismatique, A6 à A9 variantes de couleur, A10 Constellation |
| Titres | A1 « Ascended », A3 « Sky Keeper », A5 « Sky Wobbler », A10 « Star Jelly » |
| Atelier | A1 ouvre Tremplin et les niveaux 3-4 de Déco qui reste |
| Habillages (2 janvier) | A1 « Nuage », A3 « Aurore », A5 « Céleste » |
| Facultative | Jamais forcée ; continuer r au-delà de la condition ne fait rien perdre |
| Rien en Robux | Aucune Ascension vendue (Sell Lemons vend un saut d'Évolution 160 R$, juin-juillet 2026, d'après TechWiser cité par le plan Renaissance) ; aucun bonus de la couche d'avant effacé (Sell Lemons efface les Powers à l'Évolution, 2026) |

**Pourquoi ces réglages (mesuré par la contre-mesure, puis inférence)**
- **Le plancher de `StartR`.** Avec ×3^A de croissance et seulement +2 r de départ par Ascension (+2 r n'allongent une boucle que de ×1,69), chaque Ascension rendait la première boucle environ 1,78 fois plus courte : 66 s à A3, 37 s à A4, 21 s à A5, 12 s à A6, 1,2 s à A10 (calcul de la critique : taille 1 jusqu'à l'objectif, Tapis 11 au départ, boost ×2, sans Tremplin ; sans boost et avec le Tapis 9 : 89 s à A4, 50 s à A5, 28 s à A6). Le plancher ajoute 4,19 r par facteur ×3, ce qui garde la première boucle vers 60 s au moins (cible). Le plafond de 6 niveaux de Tapis offerts (§3.4) va dans le même sens. Les 84 jours simulés n'atteignent jamais A10 : un robot de nuit force A = 10 pour vérifier `shortestLoopSec`.
- **La condition +4.** Chaque r de plus allonge la boucle de ×1,3 (objectif ×2,6, croissance ×2). +5 r font ×3,71 pour ×3 gagnés : la boucle « frontière » s'allongeait de ×1,24 par Ascension. Mesuré avec +5 (84 jours) : écarts de 15,0 / 17,5 / 19,0 / 20,0 jours, seulement 11 joueurs sur 40 à A5 au jour 84, et 43,4 % du temps de jeu des jours 29 et plus à plus de 3 min d'un but. Avec +4 (1,3^4 = 2,86 ≈ 3) : écarts stables de 13,5 / 13,5 / 13,0 jours, et 11,6 % seulement des jours 29+ à plus de 3 min (5,0 % à plus de 5 min).
- **La 1re marche reste à +5 (15 puis 20).** Avec +4 dès la 2e Ascension, le Record R du jour 28 tombe à 19, contre 21 sans Ascension : la Couronne (R20), les Monuments 7-8 et les plafonds du Tapis Étoilé reculent de deux semaines. Avec +5, il est de 20 (mesuré), dans la tolérance de `recordRDay28`. La suite en +4 garde des écarts stables. **La combinaison exacte (15, 20, puis +4) n'est pas encore mesurée.**
- **Le facteur de prix 1,6^A.** Avec ×3^A, le revenu dépasse les prix en 3,5^r. Mesuré pour le joueur de 2 h par jour avec Ascension (56 jours) : le Tapis 12 arrive à 45 % de la boucle (clé ≥ 0,5) et les pièces perdues au Grand Splorch valent 23,6 T12 (clé ≤ 3) ; le joueur de référence glisse dans le même sens (0,855 et 2,33 contre 0,95 et 0,85 sans Ascension), et +4 seul pousse ses pièces perdues à 4,91 T12. **Les prix doivent donc suivre A** ; 1,6 est un point de départ que la porte règle (cible).
- **Cibles** : une Ascension tous les **11 à 16 jours** pour le joueur de référence après la première, **6 à 10 jours** pour le joueur de 2 h par jour (7 à 11 mesurés avec l'ancienne règle) ; retour au record en 20 à 55 % du temps de la première fois (0,25 mesuré avec +4).
- **Boucles de 0 s, à expliquer avant l'allumage.** Toutes les variantes mesurées montrent au moins une boucle de 0 s après une Ascension (4,8 à 5,5 % des boucles sous 45 s). Soit c'est un défaut du modèle, soit le plus gros squishy dépasse déjà l'objectif juste après la renaissance. Pistes (inférence) : un squishy hors de l'enclos (Bassin, Dodo, Lettres, porté) qui garderait sa taille ; un bébé, un cadeau ou une créature capturée dont la taille serait calculée avec l'ancien r ; deux renaissances comptées dans le même pas de simulation ; la croissance hors ligne appliquée avant la remise à zéro. **La Jelly Ascend ne s'allume pas** tant que la cause n'est pas écrite dans le journal de la porte et corrigée (§8.2).

**Le moment, étape par étape**
1. Quand r atteint la condition, l'**Observatoire** sur la colline nord braque son faisceau vers le ranch et la puce Menu affiche « Jelly Ascend ! ».
2. **Aperçu** (plein panneau) : 3 tuiles de 400 × 300 « Tu gagnes » : « Croissance ×3 pour toujours », « Halo et ciel : Nuage-coussin », « +20 Confettis » ; une ligne claire en 40 px : « Tes Grands Splorch repartent du début (tu es au XV). **Tout le reste est gardé.** » (« repartent du II », « du IV »… quand le Grand Splorch de départ est plus haut), suivie de 6 icônes (squishies, Confettis, Atelier, Plopettes, paliers, Squishydex) ; la condition avec sa barre (« Grand Splorch XV / XV » et une coche dessinée).
3. **Maintien de ✕ pendant 3 s** (anneau autour d'un glyphe de 64 px), puis une carte « Prêt à monter ? » avec 2 gros boutons de 360 × 112 : « Oui, Ascension ! » et « Plus tard », **focus d'office sur « Plus tard »**, garde d'entrée de 0,6 s (boutons grisés) **et relâchement de ✕ exigé** (`InputGuard`, §2.2 : un ✕ encore tenu depuis le maintien ne confirme jamais), fermée sans rien changer après 20 s.
4. **File** : la même que le Grand Splorch (c'est un grand spectacle). Un joueur n'a jamais qu'**un seul prestige** dans la file (« Ton Grand Splorch passe d'abord ! »).
5. **Spectacle de 10 s** (coupure dure à 12 s) : le faisceau se pose sur le ranch, l'élément de ciel se construit pièce par pièce au-dessus, le Meilleur Ami n° 1 monte dans le faisceau, éclat de lumière, « JELLY ASCEND » et une étoile dessinée avec le chiffre 1, il redescend avec le halo, « ×3 pour toujours ! ». Le profil change **d'un seul bloc à 4,0 s**, puis il est sauvegardé tout de suite. Le spectacle dessine le Meilleur Ami à partir d'**une copie de sa taille prise au début** : il ne rétrécit pas dans le faisceau, et il redescend à sa nouvelle taille.
6. **Pour les autres joueurs** : « Pluie d'étoiles » (décor) qui donne 120 s de leur revenu (3 par jour au plus) et un bébé de l'espèce du Meilleur Ami (dans les 10 bébés de cadeau par jour du GDD).

**Le halo** : de 1 à 5 petites gouttes de gelée qui tournent autour de la tête (menthe, ciel, lilas, or, arc-en-ciel à 5 et plus). **Le nombre de gouttes porte l'information**, lisible sans les couleurs ; une goutte dessinée et « 3 » sur la plaque du nom ; réglage « Montrer mon halo » (activé par défaut) ; immobile en Mouvement réduit. Gagné, jamais vendu (le halo de l'Ascension de Sell Lemons [08-46] ; à l'inverse, Clean the Squishies vend une aura à +200 % de revenu pour 999 R$, 2026, confiance faible).

### 3.6 Le Grand Splorch du lancement, minute par minute

| Temps | Ce qui se passe | Qui décide |
|---|---|---|
| — | Signal « prêt » : anneau rose qui pulse autour de la silhouette du ranch, panneau « PRÊT ! », phare rose si le palier 4 est construit (attribut répliqué `SplorchReady`, écrit seulement par le serveur) | Serveur |
| Aperçu | 3 tuiles, perte en rouge et « Dépenser d'abord », choix du squishy, maintien de 1,5 s | Joueur |
| File | « 2e dans la file · ≈ 0:40 » ; place garantie | Serveur |
| 0 → 7,5 s | Spectacle du GDD §9.4 ; confettis et flash **aux couleurs de l'espèce** qui s'envole et du ranch du héros | Client (suit l'heure du serveur) |
| 3,2 s | Profil changé d'un seul bloc (`Prestige.apply`) et sauvegardé : r, Confettis, cadeau, déblocages, places offertes | Serveur |
| 7,3 → 7,5 s | Le squishy revient faire coucou ; le joueur reprend la main | Client |
| 7,5 → 9 s | « +13 Confettis » filent vers le compteur ; pièces du cadeau qui tombent dans le Pot | Client |
| 7,5 → 11,5 s | **Chantier de Big Plop**, seulement si un élément nouveau arrive dans le ranch : un petit Big Plop casqué donne 3 coups de maillet, la pièce se construit en cascade, étiquette « Nouveau : Phare de gelée ! » 3 s. **Non bloquant** : le joueur marche pendant ce temps ; la caméra ne bouge jamais seule ; **aucune flèche de bord** (les 2 flèches du GDD §10.2 restent réservées aux créatures) : si l'objet est hors champ, la carte « Nouveau : … » suffit | Client |
| après | Carte non bloquante « Nouveau : … » (8 s, puis rangée dans la pastille « ! ») | Client |

### 3.7 États et délais ajoutés (module `StateTimeouts`)

| État | Délai | Sortie |
|---|---|---|
| Garde d'entrée (ouverture d'une fenêtre ; changement sous le focus) | Relâchement de ✕ vu, puis 0,3 s (0,4 s après un changement sous le focus) | Appuis acceptés |
| Maintien ×10 / Max ou d'une ligne de l'Atelier | 0,6 s | Achat, ou annulation sans rien dépenser (« Maintiens ✕ … » dans le bandeau) |
| Réponse du serveur à un achat | **3 s** | Ligne remise à l'état du serveur, « Réessaie » |
| Petit Splorch (animation chez le propriétaire et ses 2 voisins) | 2,5 s depuis `PetitSplorchAt`, coupure dure à 4 s | État final posé |
| Maintien de l'Ascension | 3 s | Carte de confirmation |
| Carte « Prêt à monter ? » | 20 s | Fermée, rien ne change |
| File (Ascension) | Comme le Grand Splorch (coupure à 8 min) ; départ du joueur | Spectacle, ou place rendue **sans rien remettre à zéro** |
| Spectacle de l'Ascension | 10 s, coupure dure à 12 s | Fin, file suivante |
| Chantier de Big Plop | 4 s, coupure dure à 6 s | Élément posé ; carte si interrompu |
| Plopette en route (`moving`) | Jusqu'à `tPress`, **3 s au plus** | Pression si tout est encore vrai, sinon abandon et nouvelle cible |
| Plopette (`idle`, `nap`, `paused`) | Sieste après 5 min sans entrée ; pause pendant son Grand Splorch | Réveil à la première entrée |

---

## 4. Visuels

### 4.1 Direction artistique

- **Mou, rond, satisfaisant, lisible à 3 m.** On garde les formes simples du GDD (12 pièces au plus par squishy), le `Neon` pour ce qui doit briller, les raretés lisibles par la couleur **et** la forme de l'aura. Les hits gagnent malgré des visuels jugés « très laids » (Kotaku sur Steal a Brainrot, 2025 [08-102]) : notre charme en formes simples est un avantage, à condition qu'il **bouge et change** (inférence).
- **Look « simulateur » construit en code** (aucune image téléversée, GDD §10.1), avec une **feuille de style unique** (publiable depuis le 20/01/2026 [08-94]) :

| Jeton | Valeur |
|---|---|
| Coins (`UICorner`) | 16 px TV |
| Contour (`UIStroke`) | 3 px bleu nuit (30, 25, 60) ; un 2e contour vient d'un cadre parent (Roblox n'en permet qu'un par élément [08-108]) |
| Ombre (`UIShadow`, en ligne depuis le 23/06/2026 [08-92]) | 6 px TV vers le bas, douce, 50 % d'opacité, bleu nuit ; **seulement sur les panneaux et les cartes**, jamais par ligne de liste (budget d'instances, §4.6) |
| Bouton principal | Dégradé (255, 170, 210) → (235, 110, 170) |
| Bouton secondaire | Dégradé (150, 235, 200) → (80, 200, 160) |
| Bouton impossible | Dégradé (180, 180, 195) → (140, 140, 160) + icône et mot de la raison |
| Fond de panneau | Bleu nuit (30, 25, 60) à 85 %, dégradé vers (60, 45, 110) |
| Révélations, anneaux de rareté, titre du Grand Splorch | Dégradé **radial** (sorti pour tous : sujet « [Full Release] Upgraded UI Gradients » vu en extrait de recherche le 01/11/2026 [W1], date exacte incertaine) |
| Polices | FredokaOne (texte), LuckiestGuy (tampons) |
| Focus | Cadre blanc de 6 px + 2 px sombres, **dessiné à l'intérieur** de l'élément, respiration 1,2 s. Le grossissement 1,05 du GDD reste pour les gros boutons isolés ; **jamais** pour les lignes, les cartes, les boutons du rail, ni dans un cadre qui découpe |
| Suffixes des nombres | K-M blanc, B-T or (255, 215, 90), Qa-Qi rose (255, 150, 200), Sx et au-delà cyan (120, 230, 255) |

  Si `UIShadow` ou le dégradé radial manquent sur un appareil, repli automatique sur l'aplat (sous `pcall`, compté dans Diagnostics, jamais une erreur). Ce repli à plat est aussi le style des captures de référence hors ligne (le moteur de rendu de l'outil Screens ne dessine ni ombre ni dégradé radial, §2.3) : il doit être propre à lui seul. Test statique : aucune couleur ni rayon écrit en dur dans `UI/*` hors de la feuille de style.
- **Unified Lighting** (en service partout depuis juillet 2025 [08-91]) : `LightingStyle = Soft`, `PrioritizeLightingQuality = false`, réglés explicitement ; `Realistic` seulement après mesure sur une vraie PS4. **À faire la première semaine** (avant les captures de référence), en mettant à jour ensemble le GDD (§11.3, §10.6), `default.project.json` (qui règle encore `"Technology": "ShadowMap"`) et le test qui le vérifie. Un seul module possède `Lighting` : le **Directeur d'ambiance**, une pile à priorités résolue par une fonction pure : **Jelly Moon > BOOP RUSH > alerte et MEGA > Wobble Party / Squish Party > météo > costume de saison > base**. Transition de 2 à 4 s ; 4 s sans flash en Mouvement réduit.
- **Yeux « bébé » testés avec des enfants** : taille et hauteur des yeux en configuration ; 3 versions comparées devant des enfants de 8 à 13 ans sur une télé (test M14) : A = 0,22 D à +0,12 D (GDD), B = 0,26 D à +0,04 D, C = 0,30 D à 0,00 D. Le schéma « bébé » rend un visage plus mignon pour les enfants (étude de 2014 sur les 3-6 ans [08-105]). Décision avant le gel du contenu.

### 4.2 Le ranch qui évolue

**Les 6 paliers permanents** (construits sous les yeux du joueur au premier passage, visibles par les 15 autres ; dessinés par le client, ancrés, sans collision)

| Palier | Record R | Nom | Construction (formes simples, `Neon` pour les accents) | Où (repère du ranch, GDD §11.2) | Pièces |
|---|---|---|---|---|---|
| 1 | 1 | Arche à pompons | Arche de guimauve au-dessus du portail, 2 pompons, chiffre romain du Record R | Z = 0, Y = 9 à 13 | 12 |
| 2 | 3 | Tour à bonbons | Tourelle sucre d'orge (Ø 4, hauteur 16) + drapeau à la couleur du ranch | Coin arrière gauche, hors clôture : X = −30, Z = 76 | 14 |
| 3 | 5 | Balcon de gelée | 2e niveau **décoratif, jamais accessible**, derrière l'Étagère, lampions | Z = 76, Y = 10 à 14 | 18 |
| 4 | 10 | Phare de gelée | Phare (hauteur 22), lanterne `Neon` qui tourne doucement ; rose quand le Grand Splorch est prêt | Coin arrière droit : X = +30, Z = 76 | 16 |
| 5 | 15 | Dôme néon | Dôme filaire `Neon` au-dessus de l'Étagère | Z = 70, Y = 16 | 14 |
| 6 | 20 | Couronne flottante | Couronne qui tourne lentement au-dessus du panneau du ranch | Y = 18 au-dessus du portail | 12 |
| + | 25, 30, 35, 40 | Étoiles de couronne | 1 à 4 étoiles `Neon` ; couronne arc-en-ciel au 50 | Sur la couronne | 1 chacune |

**Niveau de détail par ranch, jamais par distance.** Deux portails voisins sont à 69,8 studs (GDD §11.1) : les ranchs à deux places tombent à ≈ 139,6 studs, juste sur un seuil de 140, et leurs décors changeraient de niveau de détail à chaque mouvement de caméra dans son propre ranch. Règle : le **ranch courant** est celui où se tient le personnage (il ne change que quand le personnage est à 10 studs au moins à l'intérieur d'un autre ranch), sinon le sien ; le ranch courant et **ses 2 voisins** sont en détail complet, les 13 autres en détail réduit (6 pièces : tour, phare, couronne). Spec : un robot qui traverse son ranch dans tous les sens ne fait changer de niveau de détail aucun élément. **Aucune lumière de plus** : le phare de **son** ranch prend une des 4 lumières du ranch local du GDD ; ceux des voisins restent en `Neon` (correction du plan Spectacle : le budget de 24 lumières du GDD §12.9 est déjà plein). Règle de placement (`WorldLayout.spec`, pour chacun des 16 ranchs, k = 0 … 15) : au moins 6 studs de toute dalle, rien dans les enclos ni sur le chemin du portail, **rien au-dessus de Y = 21 au centre du ranch** (la silhouette du meilleur squishy, jusqu'à Ø 38 studs à Y = 40, ne traverse rien).

**Entre les paliers, les objets qu'on regarde tout le temps montrent la progression** (table complète au §3.3) :
- **La Cuve montre ses 3 axes** : qualité = nombre d'anneaux lumineux (1 à 8) ; vitesse = un agitateur à 3 pales qui tourne en 4 s à la vitesse 3 et en 1 s à la vitesse 10 ; buses = 0 à 5 petites buses qui lâchent une étincelle à chaque naissance mutée ; dorée à la qualité 8. Le nombre se lit sans la couleur. Dans l'onglet Atelier, une ligne en lecture seule : « Cuve Niv. 3/8 · Qualité 4 · Vitesse 9 · Buses 3 ».
- **Le Pot montre son contenu** : tas de pièces en 4 états selon les **secondes de revenu** qu'il contient (moins de 30 s : vide ; 30 s à 2 min : petit tas ; 2 à 10 min : gros tas ; plus de 10 min : il déborde, 3 pièces sautillent). L'enfant voit quand aller encaisser. Son matériau suit le Record R : cuivre, argent (R2), doré (R6), cristal (R16).
- **Les dalles se voient** : le Tapis passe par 6 paliers nommés (chaque niveau éclaircit la couleur de 8 % ; chaque palier change tout le motif) ; chaque place d'enclos achetée pose un coussin rond à la couleur du ranch ; le Lit douillet est un lit à baldaquin avec un mobile de 3 lunes.

| Niveaux du Tapis | Palier (EN / FR) | Aspect (sur le grand tapis existant de 54 × 32 studs) | Pièces ajoutées |
|---|---|---|---|
| 0 | — | Herbe du ranch | 0 |
| 1-3 | Picnic Cloth / Nappe pique-nique | Carreaux rose et blanc, 6 pastilles rouges | 6 |
| 4-6 | Shortbread / Biscuit sablé | Beige doré, bord dentelé, 8 « trous » de biscuit | 20 |
| 7-9 | Rainbow Candy / Bonbon arc-en-ciel | 7 bandes `Neon` pastel | 7 |
| 10-12 | Golden Jelly / Gelée dorée | Matériau `Foil` doré, étincelles (2 par seconde) | 0 + particules |
| 13-16 | Starry Mat / Étoilé | Bleu nuit, 12 points `Neon` qui scintillent lentement | 12 |
| 17-20 | Galaxy Mat / Galaxie | Bleu nuit, 12 points qui tournent (un tour en 30 s), 2 étoiles filantes | 14 |

- **Le ranch ne paraît jamais vide après un Grand Splorch** : chaque décoration remise à zéro laisse un **socle de souvenir** (disque de vermicelles Ø 2,5 studs + l'icône de la décoration en `Neon`, 2 pièces) ; quand on la rachète, elle ressort de son socle en cascade. Les décorations gardées restent debout avec un fanion ★. Règle : décoration n° k construite si `tiles.decor ≥ k`, sinon socle ; jamais les deux (test sur les 19 valeurs).
- **Décorations dorées** (2e semaine de janvier) : une décoration construite dans 10 boucles devient dorée pour toujours ; « Moulin étoilé · 7/10 ★ » dans l'écran. Champ `decorBuilds` ajouté au schéma **avant** le lancement.
- **Monuments** derrière le fond du ranch, sur **10 emplacements fixes en coordonnées du ranch**, les mêmes pour les 16 ranchs : 2 rangées de 5, à Z = 88 et Z = 116 (r ≈ 266 et 294, le fond du ranch étant à r = 250), X = −36, −18, 0, +18, +36 ; le secteur de 22,5° d'un ranch y fait 104 à 115 studs de large. La **Prairie des copains** (r = 280 au nord dans le GDD §11.1, en plein sur les emplacements des 1 ou 2 ranchs du nord) **déménage dans un jardin du quartier nord** (r ≈ 120 à 150 ; position dans `Config/WorldLayout`). `WorldLayout.spec` vérifie les 16 ranchs. 20 pièces au plus pour le ranch courant, 6 pour ses 2 voisins, 1 silhouette pour les autres.
- **Déco perso** (janvier) : 12 emplacements fixes (8 petits, 4 grands), choisis sur un **plan du ranch vu du dessus** dans le menu (jamais en visant au stick) ; 40 objets gagnés (Squishydex, jours de Plop, objectifs, Jelly Moon, piste de la semaine), jamais au hasard ni en Robux. Au lancement, seul le **Fanion à ton nom** (offert à 5:00), posé sur un emplacement fixe.

### 4.3 Thèmes : habillages et costumes

**Habillages de ranch** (2 janvier ; donnés tout de suite à qui a déjà le Record R ou l'Ascension) : couleur, matériaux de la clôture, du sol et du portail. 14 en tout : les 3 du GDD (couleur du ranch, Moonlit, Candy Night) + Guimauve (R1), Caramel (R3), Menthe glacée (R5), Phare (R10), Glacier sucré (R12), Néon (R15), Cosmos sucré (R17), Royal (R20), Nuage (A1), Aurore (A3), Céleste (A5). Gagnés, jamais au hasard, jamais en Robux. Un habillage = une ligne de données appliquée par le client à des pièces qui existent déjà ; le serveur garde un identifiant (`ranchSkin`), validé contre la liste gagnée ; inconnu au chargement → habillage par défaut, compté dans Diagnostics. Menu → Ranch → onglet *Mon style* (qui remplace l'onglet *Dalles*).

**Kit de costume de saison** (une ligne de données `Events.Costumes`, champ déjà prévu au GDD §17.2) : `dates` (UTC, intervalle **[début, fin)** : la date de fin est exclue), `theme` (≤ 12 jetons de la feuille de style), `lighting` (1 préréglage), `decorSet` (≤ 300 pièces dessinées par le client), `particles` (≤ 20 par seconde), `bigPlop` (≤ 3 pièces), `music` (sons officiels seulement), `featured` (une récompense vedette **gagnée**). Le costume actif est une fonction pure de la date ; deux costumes ne se recouvrent jamais (test, avec le cas 2027-01-10T00:00:00Z : un seul costume actif, la Galette).

| Costume | Dates (cible) | Contenu | Vedette gagnée |
|---|---|---|---|
| **Frost & Sprinkles** | 12/12/2026 → 10/01/2027 (lancement) | Sucre glace et guirlandes `Neon` (GDD §11.3), chapeau de neige sur les 24 maisons-bonbons, stalactites de sucre d'orge sur la clôture avant (son ranch et les 2 plus proches), écharpe et bonnet de Big Plop, thème bleu glacier, flocons (10 par seconde) | Selle « Sucre glace » : nourrir Plop 5 jours pendant la saison (champ `season.frostDays`) |
| Galette des rois | 10/01 → 31/01/2027 | Squishy « fève » caché (GDD §17.2), couronnes dorées | (à définir dans les données) |
| Saint-Valentin | 07/02 → 21/02/2027 | Cœurs en gelée, thème rose | (à définir) |
| Printemps | 07/03 → 04/04/2027 | Fleurs de gelée, pastel | (à définir) |

### 4.4 Animations de construction

| Retour | Quand | Ce qu'on voit | Son, vibration | Mouvement réduit / Graphismes légers |
|---|---|---|---|---|
| **1. Un achat** | Un niveau | **Cascade** : chaque pièce part de 8 studs sous sa place, monte en 0,30 s (`Back Out`) jusqu'à 1,15 puis 1 en 0,15 s ; 0,04 s entre deux pièces ; 1,2 s au plus ; 12 vermicelles ; « +1 niv. » 40 px ; les squishies du ranch se tournent vers l'objet et sourient | `TileBuild`, **+3 % de hauteur par pièce** (au plus +36 %), **+2 % par achat de suite** dans les 3 s (au plus +24 %) : une série d'achats « monte » comme la série PERFECT | Fondu de 0,15 s / 4 vermicelles |
| **2. Achat groupé** | ×10, Max | **Un seul** retour : les cascades se suivent, 1,2 s au total ; « +7 niveaux · −1,2 M » ; 24 vermicelles | `TileBuild` une fois, puis `Reward` (clés qui existent déjà) | Fondu / 8 vermicelles |
| **3. Palier** | Nouveau palier nommé, 10e et 18e place, décoration dorée | 2,5 s : bannière **personnelle** « PALIER ! Bonbon arc-en-ciel » (48 px) ; anneau `Neon` de 0 à 40 studs en 0,6 s ; 30 confettis ; **la ola** des squishies, colonne par colonne | `LevelUp` ; vibration nouvelle `tierUp` (ligne complète au GDD §10.5 : `UINotification`, repli Large, 0,4, 0,35 s, priorité 2) | Sans ola ni anneau / 10 confettis |

- **Achats faits depuis l'écran** : le joueur ne voit pas le ranch quand un panneau est ouvert ; les cascades attendent la **fermeture du panneau** et se jouent alors, groupées. File de **10 constructions ou 10 s au plus** ; au-delà, l'état final est posé sans animation. Un objet hors du détail complet (§4.2) ou derrière la caméra n'est pas animé : il est simplement là.
- **Chantier de Big Plop** : voir §3.6. **Socle → décoration** : le socle rétrécit (0,2 s), la décoration sort en cascade.
- **Clés de son et de vibration** : seulement des clés qui existent dans `Config` (test de contrat sur chaque clé utilisée). `chantier` a sa ligne complète au GDD §10.5 (`UIClick`, repli Small, 0,3, 0,05 s, une par coup de maillet, priorité 1).
- Le texte groupé vient de **la réponse du serveur** (niveaux réellement achetés, pièces réellement dépensées), jamais d'un calcul du client.

### 4.5 Des squishies qui ont du caractère

**Six personnalités** (colonne `perso` de `Config/Species` ; une espèce nouvelle reçoit la sienne dans sa ligne de données, sans code)

| Personnalité | Espèces | Saynète 1 | Saynète 2 | Saynète 3 |
|---|---|---|---|---|
| **Curieux** | Plop, Whiskerwob, Lotlolly, Moonhop, Moonplop | « Coucou » : se penche vers le joueur (1,5 s) | « Tour de place » : petit cercle de 1,5 stud (3 s) | « C'est quoi ? » : regarde la dernière décoration construite, « ? » au-dessus (2 s) |
| **Dormeur** | Wibble, Purrpudding, Lilypuff, Hopscotch | « Bâillement » (2 s) | « Mini-sieste », bulle « z » (3 s) | « Réveil en sursaut » (1 s) |
| **Rebondi** | Ribbit Drop, Boingtoad, Clover Hop, Nubbin | « Triple saut » de 1,5 stud (1,8 s) | « Toupie » : 2 tours (1 s) | « Plat ! » : saut de 3 studs, atterrissage penché de 20° (1,5 s) |
| **Câlin** | Mochi Mew, Frillo, Bunbun, Prickle Puff | « Cœurs » : 3 cœurs si le joueur est à 8 studs ou moins (2 s) | « Bisou au voisin » (2 s) | « Dandinement » : ±10° à 2 Hz (2 s) |
| **Farceur** | Jiggleberry, Croakaroo, Gillygum, Drago Drop | « Langue » : clin d'œil (1,5 s) | « Faux éternuement » : inspire… rien, puis rit (2,5 s ; jamais le texte « ATCHOUM », réservé au Rush) | « Cache-cache » : s'aplatit puis ressort (2 s) |
| **Fier** | Grand Gloop, Blossompurr, Coralotl, Emberwob, Royal Plop | « Pose » : petit saut sur place, 2 étoiles (2 s) | « Révérence » (1,5 s) | « Défilé » : avance de 1,5 stud et revient (3 s) |

« Fier » est réservé aux Légendaires, Mythiques et Secrets : un petit signe de rareté de plus. Règles : une saynète toutes les **8 à 20 s** par squishy à 40 studs de la caméra ou moins ; **6 au plus qui commencent** en même temps (3 en qualité réduite), les plus proches d'abord : la limite empêche d'en **commencer** une 7e, elle n'en coupe jamais une en cours ; jamais pendant un portage, une fusion, un Rush à la clôture ou un grand spectacle ; une pression ou un ciblage l'arrête tout de suite. **Jamais à plus de 2 studs de sa place** (le serveur mesure les portées depuis la place, GDD §4.7). **Le ciblage (`TargetRules`) et la projection du clic lisent toujours la place de repos du squishy, jamais le modèle animé** : un « Tour de place » de 1,5 stud ne fait jamais sauter l'invite □ d'un voisin à l'autre malgré l'hystérésis de 1,5 stud du GDD (spec : cible stable pendant chaque saynète). **`CFrame` seulement** : les saynètes déplacent les pièces existantes dans la passe `BulkMoveTo` du GDD (une par image), sans toucher à `Size` ; les icônes viennent de la réserve commune de `BillboardGui`. **Aucune pièce en plus, aucun trafic réseau.**

**Six visages** faits avec les pièces existantes : Content (défaut), **Ravi** (yeux en arc « ^ ^ »), **Surpris** (yeux ×1,2, bouche ronde), **Endormi**, **Étoilé** (reflets ×1,6 en `Neon`), **Boudeur** (visage du Flop). **Réactions** : achat dans le ranch (tous se tournent, Ravi, petit saut ; une fois toutes les 2 s au plus) ; série PERFECT ×5 (Ravi) ; sirène du Rush (Surpris) ; MEGA qui atterrit à 120 studs ou moins (Surpris) ; Grand Splorch d'un autre (Étoilé, regardent la place) ; début de la Jelly Moon (Étoilé, regardent la lune) ; retour du joueur après 60 s dehors (le Meilleur Ami : Ravi + 3 cœurs) ; joueur immobile 60 s (ceux à 15 studs s'endorment). Un visage revient toujours à « Content » à la fin de sa durée, même si l'événement de fin manque. Un changement de visage écrit les tailles des yeux et des reflets **en une seule écriture**, sans animation de `Size`.

**Cinq tours appris en grandissant** (9 janvier) : chaque espèce apprend un tour quand son record de taille passe 100 (« Coucou »), 1 200 (« Toupie »), 1 million (« Salto »), 1 milliard (« Danse »), 1e12 (« Feu d'artifice »), comme les tours par âge d'Adopt Me (wiki, non daté). Le Meilleur Ami fait son plus beau tour quand le joueur joue l'emote « Bravo » (aucun message réseau de plus : l'emote est déjà répliquée).

**Des événements relookés pour la télé** (lancement) : le géant du MEGA a des expressions ; une **lune de gelée** de 80 studs (4 pièces) ouvre les yeux au début de chaque Jelly Moon et fait un clin d'œil par minute ; le Golden Wobbler laisse des **traces dorées** (6 empreintes qui rétrécissent) qu'on suit à l'œil sur une télé ; les lampadaires passent une fois au rose à la sirène du Rush (aucun clignotement). Ballons de la Wobble Party : janvier.

### 4.6 Budgets des effets (console la plus faible : PS4 et Xbox One, GDD §12.9)

Tout ce plan est **dessiné par le client** à partir d'attributs répliqués : rien ne compte dans le plafond de 4 500 pièces de la carte (GDD §11.4) ; tout compte dans les 15 000 instances d'un client.

| Ajout | Pièces au pire cas sur un client | Particules | Lumières | `Highlight` | Transparence | Quand |
|---|---|---|---|---|---|---|
| Tapis, coussins, lit (ranch courant + ses 2 voisins ; couleur seulement pour les autres) | (20 + 24 + 10) × 3 = 162 | ≤ 6 | 0 | 0 | 0 | Lancement |
| Changements par R : Cuve, Pot, Bassin, lampions, portail, geyser… (idem) | ≤ 40 × 3 = 120 | 0 | 0 | 0 | 0 | Lancement |
| Paliers de ranch | 405 exactement (3 ranchs en détail complet × 96 + 13 × 9 ; exact parce que le détail suit l'index du ranch, plus la distance) | 0 | 0 de plus | 0 | 0 | Lancement |
| Socles de souvenir | 18 × 2 × 3 = 108 | 0 | 0 | 0 | 0 | Lancement |
| Monuments (4, puis 10) | 4 : 80 + 48 + 52 = 180 ; 10 : 200 + 120 + 130 = 450 | 0 | 0 | 0 | 0 | Lancement / janvier |
| Personnalités, visages, tours | **0** (pièces existantes) | ≤ 20 | 0 | 0 | 0 | Lancement / janvier |
| Événements (lune, traces, ballons) | ≤ 26 | 0 de plus | 0 | 0 | 0 | Lancement |
| Costume d'hiver | ≤ 300 | 10 par seconde (GDD) | 0 | 0 | 0 | Lancement |
| Plopettes (≤ 5 pièces ; détail complet dans les 3 ranchs en détail complet) | ≤ 170 | 0 | 0 | 0 | 0 | 19 décembre / janvier |
| Halo et ciel | ≤ 80 + ≤ 10 près, 3 loin | 0 | 0 | 0 | 0 | 26 décembre |
| Déco perso | 3 × 120 + 13 × 4 = 412 | 0 | 0 | 0 | 0 | Janvier |
| Météo, place en fête | ≤ 84 (temporaire) + ≤ 80 | ≤ 60 (remplace les flocons) + ≤ 40 pendant 3 s | 0 | 0 | 0 | Fin janvier |
| **Interface : écran Améliorations** (le GDD §12.9 permet 3 000 objets d'interface pour tout le jeu) | **1 400 objets d'interface au plus** (estimation comptée : 36 lignes × 32 + 3 cartes × 45 + 100 pour le cadre, les onglets et le bandeau = 1 387), construits une fois au chargement | — | — | — | — | Lancement |
| **Total au lancement** | **≈ 1 300 pièces** et ≤ 1 400 objets d'interface | **≤ 200 avec le reste du jeu** | **0 de plus** | **0 de plus** | **0 de plus** | |
| **Total à la fin janvier** | **≈ 2 450 pièces** | idem (arbitré par le budget en direct) | 0 | 0 | 0 | |

Marge (inférence, à mesurer) : 15 000 − 4 300 (carte) − 2 500 (pièces des squishies) ≈ 8 200 instances pour tout le reste. L'interface entière (HUD, panneaux, écran Améliorations) doit tenir dans les 3 000 objets du GDD §12.9 : la porte compte les instances de `PlayerGui` après l'ouverture de chaque panneau (spec). Ligne de 32 instances au plus : cadre, coin, contour, dégradé ; icône (6) ; badge (3) ; nom ; avant → après (2 libellés et une flèche de 2 cadres) ; niveau (libellé et barre de 2) ; prix (icône de 3, libellé, barre de 2) ; état (icône de 3, mot) ; retour chiffré. **Budget visuel en direct** (`Render/VisualBudget`) : chaque système déclare ses pièces, particules et lumières ; au-delà, il **dégrade** dans un ordre fixe (ranchs les plus lointains d'abord, son propre ranch en dernier) ; un dépassement n'est jamais une erreur, seulement un compteur de Diagnostics. Mesure obligatoire sur une vraie PS4 ou Xbox One avec 16 joueurs (test M6 du GDD).

**Trois versions de chaque effet** : normale, Mouvement réduit (pas de déplacement d'interface, pas de secousse, pas de flash, amplitudes ×0,5, 3 changements de couleur par seconde au plus) et Graphismes légers (particules ×0,3, détail réduit). **Aucune transparence de plus** (réservée à la gelée, aux portails, au Bassin et à la Cuve). **Aucune lumière ni `Highlight` de plus.** **Un seul grand spectacle à la fois** : les moments nouveaux sont locaux ou d'ambiance et se taisent pendant un Rush, un MEGA, un Grand Splorch ou la danse de Big Plop.

**Captures de référence** (outil Screens ; 3 résolutions, 2 langues pour ce qui a du texte, qualité normale et réduite, dans le style de repli à plat, §2.3) : ranch aux Record R 0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13, 15, 16, 17, 19, 20, 25 ; 7 paliers du Tapis ; 3 paliers d'enclos ; **6 visages × 6 familles** (une espèce par famille, plus Lilypuff, la plus plate) au lieu de 6 × 26 ; chaque phase des événements ; costume d'hiver ; écrans d'amélioration (§2.3). Matrice volontairement réduite (remarque du jury sur la taille de la matrice du plan Spectacle).

---

## 5. Contenu et rétention

### 5.1 Collection

| Collection | Contenu | Quand |
|---|---|---|
| Squishydex (GDD) | 26 espèces au lancement + **1 par semaine**, 9 mutations chacune, badges d'étoiles, bonus de famille | Lancement, puis chaque samedi |
| Étagère à trophées (GDD) | Record de taille par espèce | Lancement |
| Paliers de ranch et changements par R | 6 paliers + un changement visible à chaque R1-R20 | Lancement |
| Monuments | 10 grands décors permanents | 4 au lancement, puis en données |
| Plopettes | 6 aides nommées | 19 décembre ou 2 janvier |
| Habillages | 14 | 2 janvier |
| Déco perso | 40 objets + 2 de cœurs | Système et 18 objets le 2 janvier, 22 le 23 janvier |
| Halo et ciel | 5 gouttes, 10 éléments de ciel | 26 décembre puis janvier |
| Tours appris | 5 par espèce | 9 janvier |
| Décorations dorées | 18 | 9 janvier |
| **Maîtrise d'espèce** | Fiche avec 3 cases : ★5, Page dorée (8 mutations hors Lunaire), Trophée Cristal (taille record ≥ 1e12) ; la fiche brille jusqu'à « Réclamer » (+25 Confettis) ; compteur « Maîtrises 3 / 26 » ; **un seuil ne bouge jamais** quand une espèce arrive | Février (les premières arrivent vers le jour 27 : premier 1e12 mesuré vers les jours 24-27) |
| Jalons de taille géante | 1e15 selle « Cosmique », 1e18 traînée « Étoiles filantes », 1e21 **Squishy-Soleil** (couronne de rayons sur la silhouette), 1e24 titre « Sun Keeper » | Février |

### 5.2 Quêtes

- **Objectifs du jour** (GDD §7.4, inchangés) : 3 tirés parmi 18, faisables en 20 min.
- **Défis de Splorch** (2 janvier) : 3 par semaine, tirés parmi 12, chacun **faisable en 2 h de jeu au plus dans la situation du joueur** (module `QuestRules`, règle d'or du GDD) et **jamais dépendant des autres joueurs** (un serveur PlayStation peut n'avoir que 1 à 3 joueurs [08-152]) : Fais 2 Grands Splorch (si faisable) · Gagne 20 Confettis · Achète 10 niveaux d'amélioration · Atteins un nouveau Record R (si faisable) · Fais une Jelly Ascend (si prête dans les 2 h) · Fais un combo ×3 · Fais naître 2 Rares ou mieux · Remplis 5 nouveaux tampons · Participe à 2 MEGA SQUISH · Nourris Plop 3 jours · Attrape 5 créatures en fuite · Fais 30 PERFECT. (Écartés : « Applaudis 5 Grands Splorch » et « Encaisse 3 cadeaux », qui dépendent des autres.)
- **Carnet du Ranch** (2 janvier) : compteur à vie des niveaux achetés (×10 et Max compris), récompenses gratuites et cosmétiques : **50** titre « Bâtisseur », **100** selle « Brique », **250** drapeau « Chantier », **500** titre « Architecte », **1 000** traînée « Petits marteaux », **2 500** habillage « Atelier », **5 000** titre « Grand Architecte », **10 000** couronne de chantier pour le Meilleur Ami. Repères (inférence, ≈ 75 niveaux par boucle) : 50 et 100 au jour 1, 250 vers le jour 3, 500 vers le jour 6, 1 000 vers le jour 14.

### 5.3 Événements

- **Horloge commune du GDD** (§2.4), inchangée : créature en fuite toutes les 60 s, Golden Wobbler 4 fois par heure, BOOP RUSH toutes les 10 min, MEGA toutes les 30 min, jauge du serveur, Jelly Moon du samedi (4 séances + rattrapage le dimanche). Relookés pour la télé (§4.5).
- **Place en fête** (16 janvier) : chaque Grand Splorch (+1), MEGA réussi (+3) et Wobble Party (+2) du serveur ajoutent des points ; la place monte de niveau (guirlandes à 5, ballons à 15, arches à 30, petits feux d'artifice à 50, statue dorée de Big Plop à 80). Décor seulement, rien à tricher ; repart de 0 avec un nouveau serveur.
- **Météo de Wobbleton** (30 janvier, après la porte de simulation) : fenêtres de 5 min à **:08-:13 et :38-:43 UTC** (les seules sans Rush ni MEGA), même météo sur tous les serveurs (fonction pure de l'heure), suspendue pendant la Jelly Moon. Pluie de vermicelles (Néon ×2), Brise de bulles (Gelée ×2 ; Neige de sucre et Givré ×2 en hiver), Ciel de guimauve (visuel seulement), Arc-en-ciel de gelée (Arc-en-ciel ×2). Bonus **gratuit et affiché** dans le Guide, seulement sur les naissances de la Cuve et les créatures en fuite personnelles, jamais cumulé avec la Lune. Les météos de 5 min qui donnent des mutations sont un pilier de Ride A Pet (≈ 1,55 M de joueurs simultanés le 03/10/2026 [08-19]). Question au propriétaire : bonus ou purement visuel (§8.4).
- **Costumes de saison** : §4.3.

### 5.4 Fin de jeu (les buts longs)

| But | Repère (joueur de référence, 30 min par jour) |
|---|---|
| Atelier de lancement complet | ≈ jour 28 sans la piste (mesuré) ; ≈ jour 16-17 avec la piste (calcul, §6.3 H8) |
| Atelier et cosmétiques complets (1 304 Confettis) | 2 à 3 mois (inférence d'après les gains mesurés) |
| 10 Monuments | Record R 24 |
| Tapis Étoilé 20 | Chaque boucle à r ≥ 16 |
| Jelly Ascend 1 à 5 (halo complet), puis 10 (Constellation) | A1 vers le jour 13 (mesuré), puis tous les 11 à 16 jours (cible ; 13 à 13,5 mesurés avec +4) : A5 vers le jour 68 (inférence) |
| Titres de Record R tous les 5, puis tous les 10, jusqu'au Record R 400 | En données |
| Carnet 2 500, 5 000, 10 000 | Fidèles |
| Maîtrises (26 et plus) | Des mois |
| Squishy-Soleil (1e21) | Plusieurs mois (inférence d'après les objectifs du GDD) |
| Livre des records (janvier) | Lecture seule : plus gros squishy, meilleur combo, Grands Splorch, Ascensions, Record R, Confettis gagnés, maîtrises, jours de Plop, cœurs reçus |

### 5.5 Le contenu de chaque semaine

- **Chaque samedi** : une espèce nouvelle (GDD §7.6) **et** un ajout de renaissance ou de décor publié en données, avec une date d'activation (champ `release`) : on publie en avance, sans nouvelle version. Steal An Egg tient ce rythme depuis sa sortie : environ 10 mises à jour numérotées en ≈ 14 semaines (fin octobre 2026 [08-112][08-113]), puis un biome « Alien » annoncé du 07/11 au 14/11/2026 [W2].
- **Piste de la semaine** (2 janvier) : gratuite, **12 paliers**, toutes les récompenses visibles d'avance ; 1 point par objectif du jour terminé (3 par jour au plus), 4 points par Défi de Splorch, 1 palier = 2 points ; 24 points sur 33 possibles par semaine (≈ 4 à 5 séances de 30 min, cible). **Une seule définition de la semaine** pour la piste, les Défis et les classements du GDD : `weekIndex = floor((heureUnix − 345 600) / 604 800)`, comptée depuis le lundi 5 janvier 1970 à 00:00 UTC ; jamais un numéro de semaine de l'année (2026 a 53 semaines ISO : la semaine 2026-W53 va du lundi 28 décembre 2026 au dimanche 3 janvier 2027, et « semaine 1 » du 4 janvier paraîtrait plus ancienne que « 53 »). **La première période va du samedi 2 janvier au lundi 11 janvier 2027 à 00:00 UTC** (9 jours, 39 points possibles), pour que le premier cosmétique soit atteignable (2 jours n'auraient donné que 18 points sur les 24 du palier 12) ; ensuite, remise à zéro chaque lundi à 00:00 UTC. Les points d'un Défi vont à la période où il a été tiré. Paliers **réclamés tout seuls** ; un Défi en cours reste jusqu'à la fin de la session. Specs `QuestRules` : 2027-01-03T23:59:59Z et 2027-01-04T00:00:00Z (même période de piste, deux semaines de classement), 2027-01-10T23:59:59Z et 2027-01-11T00:00:00Z (changement), 2027-12-26 et 2028-01-03 ; chaque période permet d'atteindre 24 points.

| Palier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Récompense | 2 C | 2 C | 3 C | Goutte chanceuse | 3 C | 4 C | 4 C | Goutte chanceuse | 5 C | 5 C | 6 C | **Cosmétique de la semaine** |

(C = Confettis, 34 par semaine. Goutte chanceuse = une naissance de Qualité +1, chances de mutation ×2, comme au GDD §7.4.)

- **Aucune peur de rater** : les cosmétiques de la semaine tournent sur une liste de 8 et **reviennent au plus tard 8 semaines après** (écrit sur la piste : « Revient le 6 février »). Aucune version payante au lancement ; **une seule piste** dans le jeu : la « saison de 28 jours » du GDD §17.2 devient 4 pistes de la semaine, et une piste premium (≈ 399 R$ au GDD) resterait décorative, sans saut de palier, sur décision du propriétaire.

**Calendrier des 3 premiers mois** (samedis ; tout en données sauf mention « version »)

| Date | Contenu (en plus de l'espèce de la semaine) |
|---|---|
| **12 déc. 2026 (lancement)** | Écran Améliorations, Gants, Tapis Étoilé, Atelier (lignes 1-7, 3 palettes, selle), table R1-R40, paliers de ranch, Monuments 1-4, cadeau du Splorch, places offertes, décorations gardées, socles, personnalités et visages, costume « Frost & Sprinkles » |
| 19 déc. | Plopettes et École (si la porte est verte), Monuments 5-6, 2 palettes d'hiver ; code de la Jelly Ascend (éteint) s'il n'était pas au lancement (version) |
| **26 déc.** | **Jelly Ascend allumée** (configuration), Petit Splorch, halo, ciel A1-A2, Tremplin et niveaux A ≥ 1 de l'Atelier |
| **2 janv. 2027 (1re mise à jour, version)** | Plopettes (si pas avant), piste de la semaine et Défis, Carnet du Ranch, Livre des records, habillages, onglet *Mon style*, Déco perso (système + 18 objets), reste des cosmétiques de l'Atelier, Monuments 7-8 |
| 9 janv. | Tours appris, décorations dorées, ciel A3-A5 |
| 16 janv. | Mode photo (« Cheese ! », pensé pour le bouton Create de la PS5 ; filtres, caméra bornée, personnage figé), place en fête, ballons de la Wobble Party ; costume « Galette » (dès le 10) |
| 23 janv. | Déco perso, 2e vague (22 objets), Monuments 9-10 |
| 30 janv. | Météo (après la porte), ciel A6-A10, titres de Record R 45-60 |
| Février | Jumelles et cœurs (1 par ranch et par jour, 20 par jour, notification privée, **aucun compteur public**, joueurs bloqués exclus), Maîtrise d'espèce, jalons de taille géante, costume Saint-Valentin |
| Mars | Bilan sur les données ; costume du printemps |

---

## 6. Rythme

### 6.1 Ce que le joueur a, et ce qu'il vise, à chaque horizon

Joueur de **référence** : 35 min le jour 1, puis 30 min par jour (la politique du GDD §4.24). Joueur **assidu** : 2 h par jour.

| Moment | Joueur de référence | Joueur assidu | Prochain but visible | Statut |
|---|---|---|---|---|
| **5 min** | R0 ; Tapis niv. 5 « Biscuit sablé », bâti en cascade ; 8 décorations ; Enclos niv. 1 ; 4 squishies, 1 fusion, 1-2 captures ; première balade à 4:26 ; premières saynètes de Plop ; Fanion à son nom | Pareil (accueil identique) | Dalle Enclos ; suivi « Grand Splorch 12K / 15K » ; premier Grand Splorch vers 12,5 min | Mesuré (GDD, prototype) ; décor : cible |
| **30 min** | R2 ; Arche à pompons ; Pot argent ; 1 place offerte ; Atelier ouvert, 9 Confettis, 1-2 lignes achetées ; Gants niv. 13 « À pois » (×1,325) ; Enclos 12 ; 20 squishies ; 18 tampons | Pareil | Tour à bonbons et Lit douillet (R3) ; famille Bunny | R, Gants, Enclos, squishies, tampons : mesurés (prototype avec Plopettes) |
| **2 h de jeu** | ≈ fin du jour 4 : R6 ; paliers 1-3 ; Pot doré ; Gants 25 ; Tapis 11 ; 18 décorations ; Enclos au maximum ; 2 places offertes ; Atelier : Cadeau 2 et Tapis de départ 1 ; Monument 1 ouvert (1,69 T) ; 59 squishies | Fin du jour 1 : R5-6 ; Gants 22 | Cuve dorée (R7) ; Monument 1 ; 3 décorations gardées (R8) | Mesuré (prototype) ; Confettis : calculés |
| **1 jour** | Fin du jour 1 : R2 (35 min de jeu), 9 Confettis | R5-6, 30 à 39 Confettis | — | Mesuré (R) |
| **1 semaine** | R ≈ 10 (9,5 mesuré) : Phare de gelée, Cuve dorée, Bassin-fontaine, 3 décorations gardées, 2 Monuments, ≈ 110 Confettis, Tapis Étoilé 13-14 ouvert, 3e Meilleur Ami, ≈ 94 tampons, ≈ 650 niveaux au Carnet | R15 : Dôme néon, ≈ 5 Monuments (si publiés), premier 1e12 vers le jour 12 ; **1re Jelly Ascend au jour 6** (si allumée) | Château de Pudding (R12) ; Tapis Étoilé 15-16 ; Jelly Ascend à R15 | R, tampons, Monuments, Confettis, Ascension de l'assidu : mesurés ; Carnet : inférence |
| **2 semaines** | R15 : Dôme néon, 6 décorations gardées, ≈ 228 Confettis ; **1re Jelly Ascend** (jour 13, p10 12, p90 14) | A ≈ 2 (inférence d'après les écarts mesurés de 7 à 11 jours) | Halo, ciel, Tremplin | Mesuré, sauf A de l'assidu |
| **1 mois** | Sans Ascension : R21, Couronne flottante, 4 Monuments (ceux du lancement), 379 Confettis (sans la piste), Atelier de lancement fini, premier 1e12 vers le jour 24, ≈ 131 tampons, ≈ 1 400 niveaux au Carnet. Avec Ascension : A = 2, Record R 20 (mesuré avec +5 ; à confirmer avec la règle retenue) | Sans Ascension : R27, **contenu épuisé** (prototype). Avec : A ≈ 3 (inférence) | Monuments 9-10 ; Maîtrise (février) ; Carnet 2 500 | Sans Ascension : mesuré ; avec : mesuré pour +5, cible pour la règle retenue |

**Ce que la mesure montre** (contre-mesure du 01/11/2026 sur la **configuration du lancement**, sans Plopettes ni Ascension, 40 joueurs de référence, 28 jours, `launch-16.txt`). Les jalons du GDD tiennent tous : premier Grand Splorch à 12,5 min, R = 9,5 / 15 / 21 aux jours 7 / 14 / 28, pièces perdues au Grand Splorch 0,85 T12, Tapis 12 atteint à 95 % de la boucle, pressions 71 % des pièces au jour 7. De R1 à R14, 48 à 60 achats par boucle. Temps de jeu à plus de 3 min d'un achat ou d'un Grand Splorch : **0,0 %** (jour 1), **3,7 %** (jours 2-7), **12,9 %** (jours 8-14), **46,7 %** (jours 15-28 : **trop**, la limite est 40 %), aux 3 tailles de serveur (47,0 % à 4 joueurs, 46,6 % à 8) et même avec la politique « Conseillé » (40,3 %). À partir de R15, les boucles passent de 39 à 93 min et le plus long trou d'un joueur atteint 19 min (médiane ; 43 min au pire). **Sans Plopettes ni Ascension, la fin du premier mois est trop creuse** ; mesuré, les Plopettes seules la ramènent à 36,3 % et l'Ascension seule à 18,6 %. D'où la règle du §8.1 : l'une des deux doit être en ligne le 26 décembre, quand les joueurs du lancement arrivent à leur jour 15. Le joueur assidu (2 h par jour) est bien plus creux, dès la première semaine (33,4 %, §6.3).

### 6.2 « Toujours un prochain but » : les horloges

| Horloge | Sources |
|---|---|
| Quelques secondes | Pression prête, PERFECT, série |
| 1 à 3 min | **Prochain achat** (puce du HUD), créature en fuite (60 s), naissance de la Cuve (18 à 55 s) |
| 10 à 30 min | BOOP RUSH (10 min), Golden Wobbler, MEGA (30 min), palier nommé suivant, Grand Splorch |
| Jour | 3 objectifs, Nourrir Plop, prochain R et son déblocage nommé |
| Semaine | Monument, palier de ranch, Plopette, piste de la semaine, Jelly Moon, espèce du samedi |
| Mois | Ascensions, Atelier complet, Monuments, Carnet, Maîtrises |

### 6.3 Les hypothèses que la porte de simulation doit vérifier

La porte `EconomyPacing` (GDD §4.24) est **bloquante**. Elle rejoue le joueur de référence avec les formules du jeu, aux **3 tailles de serveur (4, 8, 16)** et avec les **2 politiques d'achat** (« le moins cher d'abord », celle du GDD, et « Conseillé », celle de l'écran).

**La porte suit le calendrier.** Un joueur du lancement (samedi 12 décembre) vit son jour 8 le 19 décembre et son jour 15 le 26 décembre. `./scripts/check.sh` rejoue donc la **configuration du calendrier** : jours 1-7 avec la configuration du lancement, jours 8-14 avec ce qui sort le 19 décembre (Plopettes si elles sont prêtes), jours 15 et suivants avec ce qui sort le 26 décembre (Jelly Ascend si elle est prête). Chaque changement de date de sortie change cette configuration. Chaque nuit, la porte rejoue aussi : lancement seul (28 jours) ; avec Plopettes ; avec Ascension (84 jours) ; **Ascension forcée à A = 10** (les 84 jours simulés n'y arrivent jamais) ; **Atelier de lancement complet** dès le début (cadeau et Tapis de départ au maximum) ; **joueur assidu** (2 h par jour), avec et sans Ascension ; **une connexion par jour** (23,5 h d'absence, 30 min de jeu) ; gros acheteur (200 joueurs avant chaque version). Une clé de nuit rouge bloque la version suivante, pas le commit.

| Clé | Mesure | Tolérance | Configuration | Mesuré (contre-mesure du 01/11/2026, sauf mention) |
|---|---|---|---|---|
| (toutes celles du GDD §4.24) | Premier Grand Splorch, R à 30 min, R aux jours 7 / 14 / 28, tampons, part des pressions, temps en ×2… | Inchangées (R au jour 28 : 17 à 22) | Toutes | Tenues : 12,5 min ; R 9,5 / 15 / 21 ; pressions 71 % |
| `starvedDay1` | Part du temps de jeu à plus de 3 min d'un achat ou d'un Grand Splorch, jour 1 | ≤ 1 % | Calendrier | 0,0 % |
| `starvedDay2to7` | Idem, jours 2-7 | ≤ 5 % | Calendrier | 3,7 % |
| `starvedDay8to14` | Idem, jours 8-14 | ≤ 15 % | Calendrier | 12,9 % (lancement seul) ; 7,8 % (prototype avec Plopettes) |
| `starvedDay15to28` | Idem, jours 15-28 | ≤ 40 % avec Plopettes seules ; **≤ 20 %** avec Ascension | Calendrier | **46,7 % avec le lancement seul : échoue** ; 36,3 % avec Plopettes ; 18,6 % avec Ascension |
| `starvedDay29plus` | Idem, jours 29 et plus | ≤ 20 % | Ascension (84 jours) | 43,4 % avec +5 ; 11,6 % avec +4 |
| `starvedAssiduDay2to7` | Idem, joueur de 2 h par jour, jours 2-7 | ≤ 15 % | Assidu | **33,4 % : échoue** (leviers H10) |
| `starvedAssiduDay8to14` | Idem, jours 8-14 | ≤ 30 % | Assidu | **56,9 % : échoue** (78,8 % aux jours 15-28) |
| `loopMaxGap` | Plus long moment sans achat d'une boucle, **pour chaque r de 0 à 13** | Médiane ≤ 3 min **et** p90 ≤ 5 min | Lancement ; Atelier complet | **Échoue** : 3,2 min à R8, 3,3 (p90 5,2) à R12, 3,3 (p90 5,7) à R13. Levier : croissance du prix des Gants ×1,55 → ×1,45 dès le niveau 20 |
| `coinsLostRatio` | Pièces perdues au Grand Splorch / T12 | 0,2 à 3 | Toutes, assidu compris | 0,85 (lancement) ; 2,33 (Ascension, ancienne règle) ; 4,91 (+4 sans facteur de prix) ; **23,6 (assidu avec Ascension)** |
| `tapis12LoopShare` | Moment de la boucle où le Tapis 12 est atteint | ≥ 0,5 | Toutes, assidu et Atelier complet compris | 0,95 (lancement) ; 0,855 (Ascension) ; **0,45 (assidu avec Ascension : échoue)** |
| `helperShareDay7` | Part des Plopettes dans les pièces gagnées en jeu, jour 7 | 5 à 15 % | Avec Plopettes | 9 % (prototype, sans la règle des 12 studs) |
| `readyAtLogin` | Grands Splorch prêts à la connexion | Médiane 0 %, ≤ 50 % | Toutes, une connexion par jour comprise | 0 % (lancement) ; une connexion par jour : non mesuré |
| `offlinePotShare` | Pièces du Pot de nuit / pièces gagnées pendant la séance | ≤ 2 | Une connexion par jour | Non mesuré (si échec : Pot de nuit plafonné à 30 %) |
| `firstWorkshopBuy` | Premier achat à l'Atelier | ≤ 35 min | Lancement | (cible : 13 min) |
| `workshopLaunchDoneDay` | Lignes de lancement de l'Atelier toutes achetées | Jour 24 à 35 | Lancement (sans piste) | Jour 28 |
| `workshopAllDay` | Atelier sans les niveaux A ≥ 1, et cosmétiques (754 Confettis) | ≥ jour 35 | Configuration du 2 janvier (avec piste) | Non mesuré (≈ jour 43 par extrapolation) |
| `monumentsDay7` / `Day28` | Monuments construits | 1-3 / ≥ 4 | Lancement | 2 / 4 |
| `ascend1Day` | 1re Ascension (référence / assidu) | 12-16 / 5-9 | Ascension ; assidu | 13 / 6 |
| `ascendGapDays` | Jours entre deux Ascensions | **11-16** (référence) ; **6-10** (assidu) | Ascension ; assidu | +5 : 15,0 / 17,5 / 19,0 / 20,0 (échoue) ; +4 : 13,5 / 13,5 / 13,0 ; assidu (ancienne règle) : 7 à 11 |
| `recordRDay28` | Record R au jour 28, avec Ascension | ≥ celui du lancement − 1 | Ascension | +5 : 20 contre 21 (passe) ; +4 : 19 (échoue) ; règle retenue : non mesuré |
| `regainRatio` | Temps pour revenir au Record R après une Ascension / temps de la première fois | 0,20-0,55 | Ascension | 0,25 (+4) |
| `shortestLoopSec` | Boucle la plus courte après une Ascension | ≥ 45 s (cible 60), **aucune boucle de 0 s** | Ascension ; A = 10 | **Échoue** : minimum 0 s, 4,8 à 5,5 % des boucles sous 45 s ; calcul sans plancher : 12 s à A6 |
| `confettiUnspent` | Confettis en poche (médiane) | ≤ 150 jusqu'au jour 56 (cible) | Ascension ; assidu | Ancienne règle : 250 (jour 56), 1 160 (jour 84) ; assidu 3 004 (jour 56). Règle retenue : 18 à 57 jusqu'au jour 56 |
| `queueWaitNewcomer` | Robots : serveur de 16 dont 8 vétérans après une Ascension ; attente médiane du premier Grand Splorch d'un nouveau joueur | ≤ 40 s | Robots | Non mesuré |
| `spenderLead` | Gros acheteur : avance au jour 28 | ≤ 2 R et ≤ 1 Ascension | Gros acheteur | 2 R (prototype) |

**Les hypothèses écrites, une par une**
- **H1** — Les familles de pièces (Gants, École, Monuments) ne bougent pas les jalons. *Mesuré* (prototype avec Plopettes ; contre-mesure du lancement sans Plopettes : jalons tenus).
- **H2** — Sans Plopettes (lancement), Gants + Tapis Étoilé + Monuments tiennent `starvedDay2to7` ≤ 5 % et `starvedDay8to14` ≤ 15 %. *Mesuré : vrai* (3,7 % et 12,9 %), mais les jours 2-7 ont déjà des trous de plus de 5 min (plus long trou d'un joueur : médiane 5,7 min, p90 8,9 ; jours 8-14 : médiane 9,7 min), et **les jours 15-28 échouent** (46,7 %). Parade : la porte du calendrier et la règle du §8.1. Si ni les Plopettes ni la Jelly Ascend ne peuvent sortir le 26 décembre : Gants à 40 niveaux, et la porte rejouée sur la configuration du lancement.
- **H3** — L'Aimant, le Sac de nuit et le Pot de nuit ne bougent pas les jalons. *Non modélisés.* Le maximum hors ligne est **16 h** (§3.4) : c'est exactement l'absence de 16 h du joueur de référence, si bien que la limite ne joue jamais dans la simulation actuelle (mesuré : 16 h comptées au plus). La configuration « une connexion par jour » (23,5 h d'absence) vérifie `readyAtLogin`, `coinsLostRatio` et `offlinePotShare` ; le Pot de nuit à 35 % pendant 16 h vaut 5,6 h de revenu sans boost par nuit.
- **H4** — Les décorations gardées et le Tapis de départ accélèrent seulement le début des boucles. *Mesuré pour le Tapis de départ 1-3 ; pas pour les décorations gardées ni pour l'Atelier complet* (Tapis de départ 3 + cadeau 3) : configuration « Atelier de lancement complet », avec `tapis12LoopShare` et `loopMaxGap` bloquantes. Le plafond de 6 niveaux offerts est déjà plus strict que le repli proposé par la critique (8).
- **H5** — Ascension : ×3, plancher de `StartR`, Tremplin, conditions 15, 20, +4, prix ×1,6^A et Petit Splorch à 1 Confetti donnent une Ascension tous les 11 à 16 jours, un retour au record en 20-55 % du temps, aucune boucle sous 45 s, `recordRDay28` et `confettiUnspent` tenus. *Morceaux mesurés (§3.5), combinaison à mesurer.*
- **H6** — Le prix corrigé des Monuments ne permet pas d'en acheter plus de 2 par boucle juste après une Ascension. *Cible.*
- **H7** — Le Petit Splorch garde la file du serveur libre (`queueWaitNewcomer`). *Robots.*
- **H8** — La piste de la semaine ne finit pas l'Atelier trop tôt. *Calcul refait* : sans la piste, les lignes de lancement sont finies au jour 28 (mesuré, 379 Confettis gagnés) ; avec 34 Confettis par semaine dès le jour 1, elles le seraient vers le jour 16-17 (279 gagnés au jour 17 + ≈ 82 de piste ≥ 344). L'ancienne hypothèse (« pas avant le jour 24 ») est donc fausse. Ce n'est pas grave en soi : à partir du 2 janvier, Plume (40) et tous les cosmétiques (370) sont en vente, soit 754 Confettis avant toute Ascension, atteints vers le jour 43 (extrapolation). La clé de cette configuration devient `workshopAllDay` ≥ jour 35.
- **H9** — La météo (fin janvier) garde les tampons du jour 7 dans 80-110. *À simuler avant l'allumage.*
- **H10** — Leviers du joueur assidu, à mesurer dans cet ordre, chacun en gardant le R du jour 28 du joueur de référence dans 17-22 : (1) au-delà de r = 16, ouvrir 2 niveaux du Tapis Étoilé tous les 2 r (r = 18, 20, 22…, ×1,25 par niveau) ; (2) `Balance.Splorch.Targets` en ×2,3 au lieu de ×2,6 à partir de R16 ; (3) croissance du prix des Gants ×1,55 → ×1,45 dès le niveau 20 (aussi levier de `loopMaxGap`) ; (4) les Plopettes (19 décembre). Mesuré pour le comprendre : à partir de R15, ses boucles durent 117 à 294 min pour 37 à 55 achats, et son plus long trou est de 30,7 min (médiane ; p90 57 min) ; l'Ascension n'aide pas sa première semaine (33,5 %, car A1 n'arrive qu'au jour 6).

**Leviers sans code** : `Balance.Tiles.*`, `Config/Upgrades` (prix, niveaux, ouvertures), `Balance.Confetti.*` (`PerGrandSplorch` = 3 + r, `PerPetitSplorch` = 1, `PerSkipped` = 1, `PerAscend` = 20), `Balance.Ascend.*` (`ReqR`, `ReqStep`, `GrowthMult`, `PriceMult`, `StartFloorOffset`), `Balance.Splorch.BeyondMult` (2,6) et `Targets`, `Balance.Prestige.MaxR` / `MaxA`, `Balance.Caps.fameSplorch`, `Events.Weather.*`, interrupteurs `Features.*`.

---

## 7. Ce qui change dans le GDD et dans l'architecture

### 7.1 GDD v1.4, section par section

| Section | Changement |
|---|---|
| §2.1 Boucle | « Construire » : 9 familles ; Gants (presser plus fort) ; Plopettes |
| §2.3 Méta-progression | Couches : Confettis et Atelier, Record R, Jelly Ascend ; colonne « Remis à zéro par l'Ascension » ; Monuments et paliers gardés |
| §2.4 Horloge | Le Petit Splorch est hors file ; l'Ascension entre dans la file ; fenêtres de météo :08-:13 et :38-:43 (fin janvier) |
| §3 Accueil | Puce « Prochain achat » et entrée Améliorations après la leçon du menu ; Fanion à 5:00 |
| §4.1 Monnaies | Confettis : gagnés en jeu seulement, jamais vendus, jamais remis à zéro ; Fame du Grand Splorch 50 par jour au plus |
| §4.2 Nombres | Couleur par famille de suffixes ; largeurs réservées |
| §4.3 Formules | ×3^A ; prix ×1,6^A (familles de la boucle) ; Tapis jusqu'à 20 ; Gants et Super Série dans la pression ; **Monuments en multiplicateur à part** (1 + 0,01 × Monuments) ; renommer l'additif « A » en `A_bonus` ; bornes `MaxR` et `MaxA` ; aucun calcul par puissance dans le code |
| §4.6 Dalles | Catalogue complet (§2.1) ; valeurs du code (×4,5) ; paliers nommés ; coussins, lit à baldaquin, socles ; décorations gardées ; places offertes ; onglet *Dalles* remplacé par l'écran Améliorations |
| §4.7 Presser | Formule avec Gants et Super Série ; **12 → 22 s de revenu (valeur du code, `Balance.Press.Seconds`)** |
| §4.8 Pot | Tas en 4 états ; matériau selon le Record R ; Aimant |
| §4.9 Cuve | Anneaux, agitateur, buses visibles ; lit le Record R |
| §4.14 Enclos | Places offertes aux R2, R6, R11, R16 (+25 Confettis si plein) |
| §4.15 Grand Splorch | Tuile « Croissance ×2 » (sans « pour toujours ») ; 3e tuile « +n Confettis » (« +1 » pour un Petit Splorch) ; table R1-R40 ; cadeau du Splorch (3 niveaux au plus avec l'Atelier) ; Petit Splorch répliqué (`PetitSplorchAt`) ; bannière une fois par 3 min et par joueur ; Chantier non bloquant, sans flèche de bord |
| §4.17, §7.4 | Tout « dès R = x » lit le Record R |
| §4.19 Hors ligne | Sac de nuit et Pot de nuit ; maximum 16 h (8 + 4 du Lit + 3 du Sac + 1 de Spiky) |
| §4.24 Simulation | Portes du §6.3 ; 2 politiques ; configuration du calendrier dans `check.sh` ; configurations de nuit |
| §4.25 Plafonds | Fame du Grand Splorch ; cadeaux de la Pluie d'étoiles (3 par jour) |
| §5.1 Espèces | Colonne `perso` |
| §5.2 Fabrication | 6 visages ; yeux réglables, version retenue après M14 |
| §5.3 Big Plop | Chantier, kiosque de l'Atelier |
| §5.4 Cosmétiques | Selles, traînées, emotes, tenues, drapeaux, palettes, titres de la table R, de l'Atelier, du Carnet ; habillages ; Déco perso |
| §6.6 Voir les autres | Signal « prêt », halo, ciel |
| §7.5, §7.6 Semaine | Piste de la semaine, Défis, calendrier en données (§5.5) |
| §8.1, §8.4 Monétisation | Rien de l'Atelier n'est vendu ; aucune Ascension en Robux ; pas de piste payante au lancement |
| §9.4 Moments | Cascade à 3 niveaux, Chantier, Petit Splorch, spectacle de l'Ascension ; texte « Plop est là ! ×2 ! » |
| §9.6 Sons | `ChantierTap`, `DecoGold`, `DecoPlace`, `TrickPop`, `WeatherStart`, `FeteLevel`, `Cheese`, `HeartGive` (dépôts officiels seulement, repli sur des clés existantes) |
| §10.1 Style | Feuille de style unique, jetons du §4.1, `UIShadow` sur les panneaux et les cartes, dégradés radiaux avec repli ; **politique de texte unique** : `TextSize` fixe partout, plus de `TextScaled` (remplace « chaque texte a `TextScaled` et un `UITextSizeConstraint` min 28 ») ; noms et nombres plafonnés par `MaxTextSize` = taille dessinée ; phrases dimensionnées pour la taille Largest ; **focus dessiné à l'intérieur, sans grossissement** pour les lignes, les cartes et le rail ; écart de 16 px entre éléments sélectionnables, désormais tenu par le rail |
| §10.2 HUD | Puce « Prochain achat » à (96, 342), 440 × 96, cachée quand le Grand Splorch est prêt ou que la carte de la cible est affichée (8 éléments au plus) ; rail du menu en 8 boutons de 80 px, écart 16 (y 246 à 998), bouton de renaissance au nom de celle qui est prête |
| §10.3 Écrans | Écran Améliorations ; aperçu de l'Ascension et sa carte ; onglet *Mon style* du panneau Ranch |
| §10.4 Commandes | U au clavier ; □ et E = mode dans l'écran ; maintien d'Entrée ou du bouton de la souris 0,6 s pour ×10 / Max |
| §10.5 Vibrations | Lignes complètes `tierUp` (`UINotification` ; Large, 0,4, 0,35 s ; priorité 2) et `chantier` (`UIClick` ; Small, 0,3, 0,05 s ; priorité 1) |
| §10.6 Navigation | Sélection d'office du menu **inchangée** (Ranch = △ ✕) ; Améliorations sous Ranch et dans le cycle L2 / R2 juste après Ranch ; ordre fixe des lignes ; garde de ✕ (relâchement vu + 0,3 s) à l'ouverture de tout panneau, pas seulement des cartes bloquantes ; achats sur `InputBegan` capté, jamais sur `Activated` |
| §11.1 Plan | Prairie des copains déplacée dans un jardin du quartier nord (r ≈ 120-150) ; bande des Monuments à r ≈ 260-300 derrière chaque ranch |
| §11.2 Ranch | Positions des paliers, du ciel, des 10 emplacements de Monuments, du Geyser de gelée (R17), de la maisonnette des Plopettes, des 12 emplacements de Déco perso ; règle « rien au-dessus de Y = 21 au centre » ; détail complet pour le ranch courant et ses 2 voisins |
| §11.3 Éclairage | `LightingStyle = Soft` ; Directeur d'ambiance ; `default.project.json` et sa spec mis à jour ensemble |
| §12.6 Schéma | Champs du §7.3 |
| §12.7 Messages | Intentions du §7.4 |
| §12.9 Budgets | Lignes du §4.6 ; phare sans lumière de plus ; écran Améliorations ≤ 1 400 objets d'interface, construit une fois |
| §12.10 Qualité | États du §3.7 ; règles du §2.3 ; tests du §7.6 |
| §12.12 Lignes | Lignes de ce plan et ligne de coupe du §8 |
| §16 Analytique | Événements du §7.5 |
| §17 Lancement et plus tard | Découpage du §8 ; Jelly Ascend à r ≥ 15, puis 20, puis +4 (au lieu de « après 10 Grands Splorch »), allumée le 26 décembre ; « saison de 28 jours » = 4 pistes de la semaine |
| §18 Checklist | M14 avec l'écran Améliorations (« Léa comprend-elle Max ? ») ; M6 avec les nouveaux décors |
| §19 Risques | Risques du §7.6 |

### 7.2 Modules nouveaux

| Module | Où | Rôle | Tests |
|---|---|---|---|
| `Logic/UpgradeMath` | Shared (pur) | Prix d'un niveau, de n niveaux, maximum payable, effet à un niveau, palier ; pièces **et** Confettis ; prix des Monuments ; tables construites par multiplications | Propriétés : `bulk(n)` = somme ; chaque rangée strictement croissante (Tapis 12 compris) ; jamais `NaN` ni infini, aussi à `MaxR` et `MaxA` ; plafonds par r ; cas exacts du §2.1 ; test statique sans `^` |
| `Logic/UpgradeAdvisor` | Shared (pur) | Conseillé (`cards`), prochain achat (`next`) | Déterministe ; jamais 2 cartes d'une famille ; jamais une carte vide ; `next` ne change de cible qu'après un achat |
| `Logic/Prestige` | Shared (pur) | **Seule source** de r, Record R, A ; `growthFactor`, `target`, `isRecordSplorch`, `ascendReady`, `reqR`, `startR` (avec plancher), `priceFactor`, `confettiGain` (3 + r, 1, 1 par Grand Splorch sauté, 20), `grantRecord`, **`apply(profile, genre, now)`** (genre = « splorch » ou « ascend ») | Propriétés sur des milliers de profils (squishies jamais perdus ; Record R, Confettis, A, Atelier jamais en baisse ; seuls les champs « repart de zéro » changent) ; **test statique : aucune lecture de `profile.R` hors de `Prestige` et de `Schema`** ; aucun `^` |
| `Logic/Bitset` | Shared (pur) | Ensembles de bits en tableaux de mots de 32 bits (`monuments`, `carnet`, `decoPerso.owned`, `mastery`) | 200 espèces et 64 objets passent `JSONEncode` / `JSONDecode` et `reconcile` sans perdre un bit |
| `Logic/QuestRules` (étendu) | Shared (pur) | `weekIndex`, période de la piste (première période du 2 au 11 janvier), Défis faisables | Changements de semaine et de période du §5.5 ; chaque période atteint 24 points |
| `Logic/TierRules`, `Logic/RanchLook` | Shared (pur) | Palier d'une famille à un niveau ; éléments du ranch pour un Record R | Chaque niveau a un palier ; chaque R1-R20 a un élément visible ; mêmes entrées = même sortie |
| `Logic/AmbienceRules` | Shared (pur) | Pile d'ambiance | Toute combinaison donne une seule réponse |
| `Config/Upgrades` | Shared | Familles, lignes de l'Atelier, onglets, ordre, paliers, ouvertures, clés de texte ; identifiants définitifs (on ajoute à la fin, jamais de réordonnancement) | Coûts strictement croissants ; aucun champ de probabilité (test de schéma) ; chaque clé de son et de vibration existe |
| `Config/Visuals` | Shared | `RanchByRecordR`, paliers, visages, yeux, palettes | Clés EN et FR |
| `UI/Format`, `UI/Text` | Client | `Format.multiplier`, `percent`, `seconds` ; `Text.set(label, clé, args)`, seul à écrire `.Text` | Deux niveaux voisins = deux textes ; même texte dans la carte, la ligne et le bandeau ; test statique ; caractères présents dans la `cmap` des polices du dépôt |
| `UI/UpgradeCard`, `UI/Panels/Upgrades`, `UI/UpgradeSnapshot`, puce du HUD | Client | Écran et carte unique, construits au chargement ; instantané versionné | Règles du §2.3 ; ≤ 1 400 instances |
| `InputGuard` (dans `InputController`) | Client | Garde de ✕ (relâchement + 0,3 / 0,4 s) ; achats sur `InputBegan` capté | Specs du robot manette du §2.2 |
| `Render/BuildCascade`, rendu des paliers dans `RanchRenderer` | Client | Cascade ; décors du ranch à partir des attributs `BestR`, `Ascend`, `SplorchReady`, `PetitSplorchAt` | Idempotent ; interruption → mêmes `CFrame` finaux ; instances stables |
| `Render/AmbienceDirector` (dans `LightingController`) | Client | Seul possesseur de `Lighting` | Une écriture par changement |
| `Render/VisualBudget` | Client | Budgets, dégradation, **détail par index de ranch** | Jamais dépassé sur 6 h de robots ; un robot qui traverse son ranch ne change le détail d'aucun élément |
| Personnalités et visages (dans le rendu des squishies) | Client | Saynètes (`CFrame` seulement), visages, réactions | Déplacement ≤ 2 studs ; retour à « Content » ; cible stable pendant chaque saynète |
| `EconomyService` (étendu) | Serveur | `buyUpgrade` pièces et Confettis ; instantané versionné ; liste des contenus sortis | Attaques du §7.6 |
| `SplorchService` (étendu) | Serveur | `Prestige.apply`, Petit Splorch, Ascension dans la file | Contre-audit du §7.6 |
| `HelperService` (19 décembre) | Serveur | Plopettes à 10 Hz : cible, `tPress`, nouvelle vérification à `tPress` | Aucune récompense avant `tPress` ; joueur à moins de 12 studs à `tPress` = aucune pression d'aide ; la pression du joueur gagne à égalité ; sieste, pause |
| `QuestService` (étendu, 2 janvier) | Serveur | Piste de la semaine, Défis, Carnet ; même `weekIndex` que les classements | Specs du §5.5 |
| `EconomyPacing` (outil de simulation) | Outil | Configurations du §6.3, dont celle du calendrier | Clés du §6.3 |

### 7.3 Données (schéma v1, tous les champs ajoutés **avant** le lancement)

Ajoutés par `reconcile` avec leur valeur par défaut, même pour les fonctions allumées plus tard : **aucune migration en janvier**. `bestR` (≥ r), `ascend` (le champ réservé du GDD devient A), `confetti` et `confettiTotal` (entiers de 0 à 1e9), `tiles.gloves`, `tiles.school` (le Tapis Étoilé réutilise `tiles.snack` jusqu'à 20), `monuments` (ensemble de bits), `atelier` (tableau dense d'un niveau par ligne, borné par le maximum de la ligne), `stats.upgradesBought`, `carnet` (ensemble de bits des paliers réclamés), `weeklyTrack = { period, points, claimed, quests }` (`period` = numéro de période du §5.5, jamais un numéro de semaine de l'année), `ranchSkin`, `settings.haloOn`, `decorBuilds` (18 petits entiers bornés à 10), `decoPerso = { owned (ensemble de bits), slots (12) }`, `hearts = { givenDay, givenTo (20 au plus), receivedTotal }`, `mastery` (ensemble de bits, un par espèce), `season.frostDays`. **Ensembles de bits** : un `number` de Luau ne garde les entiers exacts que jusqu'à 2^53 et `bit32` travaille sur 32 bits ; un champ « 64 bits » ne peut donc pas tenir dans un seul nombre (ni passer le JSON), et un bit par espèce dans un seul nombre déborderait à la 33e espèce, le 30 janvier 2027 au rythme d'une espèce par samedi, avant même la Maîtrise de février. Chaque ensemble est un **tableau de mots de 32 bits** (`{number}`, longueur ceil(n / 32)), agrandi par `reconcile`, lu et écrit seulement par `Logic/Bitset`. `Contract.spec` : un profil plein reste identique après `JSONEncode` / `JSONDecode` ; 200 espèces et 64 objets de Déco perso passent sans perdre un bit ; le profil pèse moins de 20 Ko.

### 7.4 Messages réseau

| Intention (client → serveur) | Contenu | Règles du serveur |
|---|---|---|
| `BuyUpgrade` | `id`, `mode` (1, 10 ou « max »), `expectedLevel` | Famille connue, ouverte et sortie (liste du serveur) ; niveau actuel = `expectedLevel` (sinon refus « périmé », sans retour visible si l'instantané montre déjà ce niveau, §2.3 règle 12) ; `n = min(demandé, payable, restant)` ; somme exacte niveau par niveau ; un seul bloc ; seau à jetons de 10 par seconde ; refus pendant l'application d'un prestige |
| `BuyTile` (GDD) | Inchangé pour les dalles au sol ; même fonction serveur et même `UpgradeMath` | — |
| `JellyAscend` | `confirm` | `ascendReady` ; un seul prestige par joueur dans la file ; conditions vérifiées à l'entrée seulement |
| `SetRanchSkin`, `PlaceDeco` (janvier), `GiveHeart` (février) | Identifiant, emplacement et niveau attendu, ranch | Validés contre ce qui est gagné ; réponse attendue en 3 s côté client |

Réponses (serveur → client) : `UpgradeResult { id, from, to, spent, currency, reason, snapshot }`, où `snapshot = { coins, confetti, levels, version }` est aussi envoyé dans le correctif de données (l'écran ne lit que lui, §2.3 règle 6) ; `HelperPress { helper, uid, tPress }` regroupé par tick (Plopettes) : le serveur choisit la cible ; `tPress` = maintenant + temps de trajet, fonction pure des deux positions ; le client règle le saut pour atterrir à `tPress` ; à `tPress`, le serveur revérifie « prêt depuis 3 s » et la règle des 12 studs, sinon il abandonne et choisit une autre cible (état `moving`, 3 s au plus, §3.7) ; à égalité, la pression du joueur gagne ; `Released { ids }` (contenus datés sortis, décidés par le serveur). Attributs répliqués du ranch : `BestR`, `Ascend`, `SplorchReady`, `PetitSplorchAt`.

### 7.5 Analytique

`Upgrade_<famille>` (cumulé), `UpgradeMode` (×1 / ×10 / Max), `WorkshopBuy_<ligne>`, `ConfettiEarned(source, n)`, `UpgradeTimeout`, `UpgradeStale`, `NextGoalGap` (histogramme serveur du temps depuis le dernier achat), `HelperCoinsShare`, `RanchTierReached(tier)`, `AscendPreview(opened | cancelled | confirmed)`, `AscendDone(A, r, daysSinceLast)`, `PetitSplorch`, `WeeklyTrackTier(tier)`. Alerte : si la médiane de la 1re Ascension sort de 10-18 jours, régler `ReqR` par configuration.

### 7.6 Risques, parades et notes « zéro bug »

| Risque | Parade |
|---|---|
| **Calendrier trop chargé** (le jeu de base du GDD est encore en fabrication) | 3 voies en parallèle, revue le jeudi 3 décembre, ligne de coupe du §8, date de repli du GDD (samedi 9 janvier 2027) |
| **Rythme cassé** par une partie non mesurée (configuration sans Plopettes, Atelier de confort, Sac de nuit, Ascension) | Porte bloquante dans chaque configuration (§6.3) ; leviers en configuration ; Ascension allumable et éteignable par `Features.JellyAscend` |
| **File du serveur saturée** après les Ascensions | Petit Splorch hors file ; clé `queueWaitNewcomer` |
| **Un système lit r au lieu du Record R** et « reprend » un déblocage après une Ascension (le bug le plus probable d'une 2e couche) | Module `Prestige` seule source ; test statique ; propriétés de `apply` |
| **Double achat**, achat rejoué | `expectedLevel`, seau à jetons, un seul bloc |
| **Confettis comptés deux fois** | Crédités dans le bloc du Grand Splorch ; seuls `Prestige.apply` et `EconomyService.buyUpgrade` les modifient ; robots de 6 h : jamais en baisse hors achat, jamais négatifs |
| **Texte coupé en français**, taille de texte du joueur | Règle 9 du §2.3 (une seule politique, mesure à Medium et à Largest) ; captures à 720p, 1080p et 4K |
| **Écran trop dense pour Léa, 8 ans** | 4 onglets, Conseillé, bandeau de détail, mode ×1 à chaque ouverture ; test M14 « comprend-elle Max ? » avant le gel |
| **Performance PS4** (≈ 1 300 pièces de plus au lancement, ≈ 2 450 fin janvier) | Budget en direct, niveaux de détail, 0 lumière de plus, test M6 |
| **Changement d'éclairage** tardif qui casse toutes les captures | Fait la première semaine, mesuré sur PS4, captures prises après |
| **Outils d'interface absents** sur un appareil | Repli sous `pcall`, compté dans Diagnostics |
| **Enfant qui perd quelque chose à l'Ascension** sans comprendre | Rien de débloqué n'est perdu ; aperçu avec 6 icônes « gardé » ; maintien de 3 s ; focus sur « Plus tard » |
| **Matrice de captures énorme** | Matrice réduite (§4.6) |
| **Ranch encombré** par paliers, Monuments et Déco perso | Zones séparées et testées (`WorldLayout.spec`, 16 ranchs) ; règle Y = 21 ; Prairie des copains déplacée |
| **Fin du premier mois creuse** si les Plopettes et l'Ascension glissent toutes les deux (mesuré : 46,7 %) | Porte du calendrier ; règle du §8.1 ; repli Gants à 40 niveaux |
| **Joueur assidu sans but proche** dès la 1re semaine (mesuré : 33,4 %) | Clés `starvedAssidu*` ; leviers H10 ; question au propriétaire (§8.4) |
| **Boucles éclair après les Ascensions** | Plancher de `StartR` ; plafond de 6 niveaux de Tapis offerts ; robot à A = 10 ; cause des boucles de 0 s trouvée avant l'allumage |
| **Interface existante en `TextScaled`** (4 fichiers de `src/client` aujourd'hui) | Politique de texte unique (GDD §10.1) appliquée à tout le client, pas seulement au nouvel écran ; `TextFit_all` à Medium et à Largest |
| **Calculs différents entre console et serveur** | Aucune puissance dans `UpgradeMath` et `Prestige` ; montant du serveur affiché sur un refus |
| **Achat par un ✕ resté enfoncé** | `InputGuard` ; achats sur `InputBegan` capté ; robot « △ puis ✕ tenu 2 s » |

**Notes « zéro bug » communes à tout le plan**
1. Le décor est **dessiné par le client** à partir de données répliquées ; toutes les pièces ancrées, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false` ; **aucune règle du serveur ne dépend d'un décor**.
2. **Une fonction de rendu idempotente par objet** ; tout vit dans un `Trove` (connexions stables à ±5 %).
3. **Aucune animation ne décide de rien** ; la valeur finale est posée à la fin et à l'interruption.
4. **Aucune physique** : pas de contrainte, pas de `Touched`, pas de confettis qui roulent.
5. **Un délai sur chaque état nouveau** (§3.7).
6. **Un seul prestige appliqué d'un seul bloc**, sauvegardé tout de suite.
7. **Aucune carte, ligne ou météo ne touche une probabilité en cachette** : test d'égalité de `Odds` pour 1 000 états d'Atelier tirés au hasard ; la météo passe par la table affichée dans le Guide.
8. **Attaques des intentions** (couche b du GDD §12.10) : `NaN`, identifiant inconnu, mode 1e9, `expectedLevel` faux, famille verrouillée, achat pendant un prestige, `JellyAscend` deux fois dans la même image, pendant un Grand Splorch en file, départ à 3,9 s et à 4,1 s du spectacle, fermeture du serveur avec 16 joueurs en file.
9. **Robots de 6 h** avec achats ×1 / ×10 / Max et Ascensions : Record R jamais en baisse, aucun squishy perdu, un seul prestige par joueur dans la file, instances stables.
10. **Red team** : second compte et Plopettes ; ferme en restant immobile (sieste à 5 min) ; cœurs (février).

---

## 8. Découpage : le lancement, puis les mises à jour

### 8.1 Le lancement (samedi 12 décembre 2026) : un jeu complet

Il reste **29 jours ouvrés** du lundi 2 novembre au jeudi 10 décembre. Le travail tient en **3 voies parallèles** de 25 à 27,5 jours (la voie B descend à 20 jours si la Jelly Ascend glisse à la version du 19 décembre), ce qui laisse 2 à 4 jours par voie pour les tests et les corrections, contre 5 avant cette révision (estimation, inférence). C'est **très** serré : la ligne de coupe s'applique à la **revue du jeudi 3 décembre**, et la Jelly Ascend est la première à sortir du lancement. Cette charge s'ajoute au jeu de base du GDD v1.3, qui passe d'abord.

| Voie | Fonction | Effort |
|---|---|---|
| **A. Améliorations** | `UpgradeMath` (tables par multiplications, bornes), `UpgradeAdvisor` (`cards`, `next`), `Config/Upgrades` | 3,5 j |
| | Écran Améliorations construit au chargement, carte unique (2 gabarits), bandeau de détail, puce « Prochain achat », rail du menu, specs `Layout` et `FocusGuard` | 8 j |
| | ×1 / ×10 / Max, bouton de mode, `BuyUpgrade`, état « en cours », `InputGuard`, instantané versionné | 4,5 j |
| | Formateurs, `Text.set`, politique de texte sur tout le client, polices rangées dans le dépôt, `TextFit` à Largest | 2 j |
| | Gants Moelleux et leur effet visuel | 2 j |
| | Tapis Étoilé | 2 j |
| | Atelier et Confettis (lignes 1-7, 4 cosmétiques) | 4 j |
| **B. Renaissance et ranch** | `Prestige`, `Bitset`, champs du schéma, test statique | 2,5 j |
| | Table R1-R40, cadeau du Splorch, places offertes, décorations gardées, plafonds de Fame et de bannière | 3 j |
| | Paliers de ranch, Chantier, Cuve et Pot visibles, éléments par R, Geyser de gelée | 6 j |
| | Socles de souvenir ; signal « prêt » | 2 j |
| | Monuments 1-4 (10 emplacements, Prairie déplacée) | 3 j |
| | Portes de simulation : configuration du calendrier et configurations de nuit (§6.3) | 3,5 j |
| | Jelly Ascend (code éteint), Petit Splorch répliqué, plancher de `StartR`, facteur de prix, halo, ciel A1-A2 : livrés éteints si leurs specs sont vertes le 10 décembre, sinon dans la version du 19 décembre | 7,5 j |
| **C. Spectacle** | Feuille de style (et son repli à plat) ; Unified Lighting et mesure PS4 (semaine 1) | 4 j |
| | Cascade et retour à 3 niveaux | 3 j |
| | Paliers du Tapis, coussins, lit à baldaquin | 3 j |
| | Personnalités (18 saynètes) et visages, réactions ; test des yeux | 6,5 j |
| | Événements relookés (MEGA, lune, traces dorées, palette du Grand Splorch) | 2 j |
| | Costume « Frost & Sprinkles » (kit de costume) | 3 j |
| | Budget visuel en direct, détail par index de ranch, captures de référence | 3,5 j |
| | **Total** | **≈ 78,5 jours de développement** (A ≈ 26, B ≈ 27,5 dont 7,5 de Jelly Ascend, C ≈ 25) ; ≈ 71 sans la Jelly Ascend |

**Ligne de coupe** (dans cet ordre, si une porte de qualité n'est pas verte le 3 décembre) : (1) Jelly Ascend → version du 19 décembre ; (2) Monuments → 19 décembre (données) ; (3) Tapis Étoilé → 19 décembre (le joueur de référence n'atteint r = 10 qu'au jour 7) ; (4) cosmétiques de l'Atelier → 2 janvier ; (5) 3e saynète de chaque personnalité et ola du palier ; (6) Chantier de Big Plop (les éléments arrivent en cascade simple) ; (7) traces dorées et lune du MEGA.

**Règle de calendrier (mesurée)** : les Plopettes et la Jelly Ascend **ne peuvent pas glisser toutes les deux après le samedi 26 décembre**. Les joueurs du lancement atteignent leur jour 15 ce jour-là ; sans l'une des deux, ils jouent leurs jours 15-21 dans une configuration qui échoue (46,7 % du temps à plus de 3 min d'un but, pour une limite de 40 % ; Plopettes seules : 36,3 % ; Ascension seule : 18,6 %). Si aucune des deux ne peut sortir à temps : Gants à 40 niveaux, et la porte rejouée sur la configuration du lancement avant le 26 décembre.

**Jamais coupé** : l'écran Améliorations avec ×1 / ×10 / Max et ses 20 règles et tests ; les Gants ; la table R1-R20 avec au moins un changement visible à chaque R ; les paliers de ranch ; les socles ; `Prestige`, `Bitset` et les champs du schéma ; les portes de simulation, dont celle du calendrier ; la feuille de style ; la décision d'éclairage ; la cascade ; les paliers du Tapis ; au moins 2 saynètes par personnalité et les visages ; le budget visuel et les captures. **Si quelque chose doit céder, c'est le contenu, jamais la qualité** (GDD §12.12) ; la date de repli du GDD (samedi 9 janvier 2027) reste la vraie protection.

### 8.2 Les mises à jour

| Date | Contenu | Effort | Condition |
|---|---|---|---|
| Sam. 19 déc. | Plopettes et École (L, 8 j, construites en parallèle dès que la voie A a fini l'écran), Monuments 5-6 (données), 2 palettes d'hiver | L | Porte du calendrier verte (jours 8-14 avec Plopettes) ; `helperShareDay7` ; specs de `tPress` ; robots de 6 h verts |
| **Sam. 26 déc.** | **Jelly Ascend allumée**, Petit Splorch, halo, ciel A1-A2, Tremplin, niveaux A ≥ 1 de l'Atelier | Configuration | Porte avec Ascension verte (`shortestLoopSec` au robot A = 10, `ascendGapDays`, `recordRDay28`, `confettiUnspent`, `coinsLostRatio` et `tapis12LoopShare` de l'assidu) ; **cause des boucles de 0 s trouvée et corrigée** ; `queueWaitNewcomer` vert ; les Plopettes ou l'Ascension en ligne ce jour-là (§8.1) |
| **Sam. 2 janv. (1re mise à jour)** | Piste de la semaine et Défis (M), Carnet du Ranch (S), Livre des records (S), habillages et onglet *Mon style* (S-M), Déco perso (M + 18 objets), cosmétiques de l'Atelier, Monuments 7-8 | ≈ 15 j | — |
| Sam. 9 janv. | Tours appris (M), décorations dorées (S), ciel A3-A5 | ≈ 6 j | — |
| Sam. 16 janv. | Mode photo (M), place en fête (S), ballons de la Wobble Party ; costume « Galette » | ≈ 8 j | Robot : 1 000 entrées et sorties du mode photo rendent toujours la caméra d'origine |
| Sam. 23 janv. | Déco perso, 22 objets ; Monuments 9-10 | ≈ 5 j | — |
| Sam. 30 janv. | Météo (M), ciel A6-A10, titres 45-60 | ≈ 4 j | Porte avec météo verte |
| Février | Jumelles et cœurs (M), Maîtrise d'espèce (S-M), jalons géants (S), Saint-Valentin | ≈ 10 j | — |
| Mars | Bilan sur les données ; printemps ; décision éventuelle sur une 3e couche | — | Données |

Les fonctions du GDD §17.2 (lignée de Fame, Gelée lente, espèces Duo et colis, World First, Grande Gelée, semaines « Encore ») gardent leur place ; la « saison de 28 jours » devient 4 pistes de la semaine (§5.5).

### 8.3 Ce que le propriétaire aura, en chiffres

| | GDD v1.3 | Lancement (12 déc.) | Fin janvier |
|---|---|---|---|
| Familles d'amélioration achetables | 4 | 8 (dont le Tapis Étoilé et l'Atelier) | 9 (+ l'École des Plopettes) |
| Niveaux achetables | 45 | 104 | 136 |
| Couches de renaissance | 1 | 1 (+ code de la 2e) | 2 |
| R avec un déblocage nommé (R1-R20) | 4 | 20 | 20 |
| R avec un changement visible dans le ranch (R1-R20) | 0 (seulement le chiffre R sur le panneau) | 20 | 20 |
| Paliers de ranch permanents | 0 | 6 | 6 + ciel et halo |
| Monuments | 0 | 4 | 10 |
| Plopettes | 0 | 0 | 6 |
| Habillages de ranch | 3 | 3 | 14 |
| Déco perso | 0 | 1 (Fanion) | 40 |
| Personnalités / saynètes / visages / tours | 0 / 0 / 1 / 0 | 6 / 18 / 6 / 0 | 6 / 18 / 6 / 5 |
| Contenu de la semaine | 1 espèce | 1 espèce + données | 1 espèce + piste + 3 Défis + données |
| Nouveaux articles en Robux | — | 0 | 0 |

### 8.4 Questions pour le propriétaire

1. **Jelly Ascend** : d'accord pour r ≥ 15, une remise à zéro de r (en gardant tout ce qui est débloqué, les Confettis, l'Atelier, les Plopettes et les Monuments), et un allumage le 26 décembre si la simulation est verte ?
2. **Textes** : d'accord pour remplacer « Croissance ×2 pour toujours » par « Croissance ×2 » ?
3. **Plopettes** : sortie le 19 décembre (proposé) ou au lancement, si la voie A a de l'avance ?
4. **Météo** : petit bonus de mutation gratuit et affiché (proposé), ou purement visuelle (aucune simulation à refaire) ?
5. **Piste premium** décorative (≈ 399 R$, GDD §8.4) : jamais, ou plus tard sur décision ? Notre recommandation : pas avant mars.
6. **Joueur assidu** (2 h par jour) : mesuré, il passe un tiers de son temps de jeu à plus de 3 min d'un achat dès la 1re semaine (33,4 %), contre 3,7 % pour le joueur de référence. Nous essayons les leviers en configuration (H10) avant la revue du 3 décembre. S'ils ne suffisent pas : sortir quand même le 12 décembre (le joueur de référence est vert), ou avancer les Plopettes au lancement ?

---

## Annexe A. Sources

**Sources de `docs/08-etude-tycoons-2026.md`** (liste complète avec URL et date dans son chapitre 11) citées ici : [08-19] Ride A Pet ; [08-43] [08-44] [08-45] [08-46] Sell Lemons (managers, Powers, achat à distance à 459 R$, couches) ; [08-55] Restaurant Tycoon 3 ; [08-60] Clash of Clans, nouvel écran d'amélioration et ses bugs (08/10/2026) ; [08-61] retours de joueurs sur « Buy Max » ; [08-65] bouton qui reste « appuyé » à la manette ; [08-68] [08-69] chute de Sell Lemons ; [08-83] Merge a Nuke ; [08-86] passes de rebirth automatique ; [08-88] premier prestige et gain en 30 s ; [08-91] Unified Lighting ; [08-92] `UIShadow` ; [08-94] feuilles de style ; [08-102] Kotaku sur Steal a Brainrot ; [08-104] confusion Sx / Sp ; [08-105] schéma « bébé » ; [08-108] look « simulateur » ; [08-112] [08-113] rythme de Steal An Egg ; [08-125] prix et Roblox Plus ; [08-145] `TextScaled` et taille de texte du joueur ; [08-152] serveurs PlayStation seuls ; [08-161] pièges de mise en page Roblox.

**Plans de travail fusionnés** (01/11/2026, dossier de travail `scratchpad/etude-tycoons/`) : `plan-progression.md` (avec sa simulation `scratchpad/plan-sim/`), `plan-renaissance.md`, `plan-spectacle.md`, `ecarts.md`. Leurs sources propres (guides de Sell Lemons, Steal a Brainrot, Ride A Pet, Pet Simulator 99, Adopt Me, Restaurant Tycoon 3, Build a Zoo, Clean the Squishies, vues en extraits de recherche le 01/11/2026) sont listées dans chacun d'eux ; nous n'en reprenons ici que la forme des systèmes, jamais les valeurs.

**Vues pour ce document le 01/11/2026** (extraits de recherche ; roblox.com et devforum.roblox.com sont bloqués depuis cette machine) :
- **[W1]** Developer Forum, « [Full Release] Upgraded UI Gradients » : dégradés radiaux, coniques et elliptiques, modes de répétition et échelle, accessibles à tous (le drapeau de bêta est retiré) — https://devforum.roblox.com/t/full-release-upgraded-ui-gradients/4846594 — date exacte incertaine (un juré cite le 29/10/2026 ; l'extrait dit « il y a 60 jours »). Confirme la sortie ; la disponibilité dans le client sur console reste à vérifier sur une vraie PS5.
- **[W2]** timesaver.gg, « Steal An Egg Alien Biome » : carte d'événement « NEW ALIEN BIOME » du 07/11/2026 16:00 UTC au 14/11/2026 19:00 UTC ; dernier billet numéroté : Update 10.5 — https://timesaver.gg/blog/steal-an-egg-alien-biome — 01/11/2026, site de fans, confiance moyenne.
- **[W3]** Documentation officielle Roblox (creator-docs), page « Accessibility », `content/en-us/production/publishing/accessibility.md`, lue dans une copie locale du dossier de travail le 01/11/2026 (create.roblox.com est bloqué depuis cette machine ; source officielle, date de la page non relevée). Elle dit : le réglage « Text Size » correspond à `GuiService.PreferredTextSize` (Medium par défaut, puis Large, Larger, Largest) ; un texte en `TextScaled` n'est pas agrandi par ce réglage ; un `UITextSizeConstraint` empêche le texte de dépasser `MaxTextSize` quel que soit le réglage ; `TextWrapped` passe à la ligne « dans les limites de la taille absolue de l'élément » ; `TextService:GetTextSize()` tient compte du réglage. Les facteurs d'agrandissement ne sont pas donnés : à mesurer dans Studio.
- **Contre-mesure de la critique** (01/11/2026) : `scratchpad/etude-tycoons/sim/results/` (`launch-4.txt`, `launch-8.txt`, `launch-16.txt`, `launch-16-advisor.txt`, `helpers-16.txt`, `ascend-16-84d.txt`, `ascend-helpers-16-84d.txt`, `assidu-launch-16.txt`, `assidu-ascend-16-56d.txt`, `fix-step4-petit1-56d.txt`, `fix-next10-petit1-56d.txt`), produits par l'`EconomyModel` du dépôt avec les valeurs de ce document ; calculs de boucles de `critic-econ.mjs`. Les chiffres cités ici ont été relus dans `launch-16.txt` et `fix-step4-petit1-56d.txt` le 02/11/2026.

## Annexe B. Ce qui n'est pas vérifié

- **La configuration du lancement est mesurée** depuis la contre-mesure du 01/11/2026 : elle tient les jours 1-14 et **échoue aux jours 15-28** (46,7 %). La porte du calendrier et la règle du §8.1 en tiennent compte.
- **Le rythme de la Jelly Ascend** est mesuré par morceaux (+5, +4, Petit Splorch à 1 Confetti). La combinaison retenue (15, 20, puis +4 ; plancher de `StartR` ; prix ×1,6^A ; +20 Confettis ; 6 niveaux de Tapis offerts au plus) **n'est pas mesurée**. Les boucles de 0 s ne sont pas expliquées.
- **Le joueur assidu** échoue (33,4 % aux jours 2-7, 56,9 % aux jours 8-14) ; les leviers H10 ne sont pas mesurés.
- **À remesurer** : le Tapis Étoilé au prix corrigé, le multiplicateur des Monuments, le facteur de prix, l'Atelier raccourci (Cadeau 2 niveaux, Tapis de départ 3 niveaux).
- **Le confort de l'Atelier** (Aimant, Sac et Pot de nuit) et les décorations gardées ne sont pas modélisés ; la configuration « une connexion par jour » n'est pas encore écrite.
- **Le vrai poids des Plopettes** avec la règle des 12 studs : le prototype ne connaît pas la position du joueur.
- **Les 4 facteurs de `PreferredTextSize`** ne sont pas connus (à mesurer dans Studio) : la hauteur du bandeau (120 px, 3 lignes) est donc une cible jusqu'au passage de `TextFit` à Largest.
- **Les largeurs de texte** des libellés courts, des mots d'état anglais et de « Splorch XVI » sont des estimations jusqu'au passage de `TextFit`. La police FredokaOne du dossier de travail est un téléchargement raté (14 octets) : les vrais fichiers de police doivent être rangés dans le dépôt pour le test de `cmap`.
- **Le vrai style (ombres, dégradés radiaux)** n'est pas vérifié hors ligne : le moteur de rendu de l'outil Screens ne les dessine pas. Captures de référence dans le style de repli ; vrai style vérifié sur PS5 et PS4 (M6, M14).
- **Le budget d'interface** (1 400 objets pour l'écran) est une estimation comptée à la main ; le total actuel de l'interface du jeu n'est pas compté.
- **Les coordonnées** des 10 emplacements de Monuments, du Geyser de gelée et du nouveau jardin de la Prairie sont à confirmer par `WorldLayout.spec` sur la vraie carte.
- **Les performances sur PS4** des décors ajoutés et d'Unified Lighting : à mesurer (test M6).
- **Le ressenti des enfants** devant l'écran Améliorations, le mode ×10 / Max, les maintiens de 0,6 s et de 3 s, les yeux « bébé » : test M14 avec des enfants de 8 à 13 ans devant une télé.
- **Un pic de joueurs pendant les vacances d'hiver 2025**, cité par un juré d'après un rapport tiers (12,5 M) : la recherche du 01/11/2026 ne l'a pas confirmé (elle ne trouve que le record d'août 2025, ≈ 45 à 47 M selon les sources). L'argument « allumer l'Ascension pendant les vacances » repose donc sur le calendrier scolaire et sur la mesure du creux de fin de mois, pas sur ce chiffre.
- **Le nombre d'achats par séance des leaders** : aucune source ne le donne ; « un but toutes les 1 à 3 minutes » est un choix de design.

---

## Journal de révision (lundi 2 novembre 2026)

Deux critiques ont relu la version du 1er novembre : une critique **économie**, qui a fait tourner le vrai `EconomyModel` du dépôt avec les valeurs de ce document (14 points), et une critique **interface et technique** (34 points). Tous les points bloquants et majeurs sont traités ; les mineurs aussi. Quand nous nous écartons de la correction proposée, la raison est écrite. Les chiffres de la critique économie ont été relus dans `launch-16.txt` et `fix-step4-petit1-56d.txt`.

**Critique économie**

| # | Gravité | Section | Problème | Ce que nous avons fait |
|---|---|---|---|---|
| E1 | Bloquant | §6.3, H2, §8.1 | La configuration du lancement échoue `starvedDay15to28` (46,7 % pour 40 %, à toutes les tailles de serveur) ; le 33,8 % cité venait du prototype avec Plopettes | Porte du **calendrier** dans `check.sh` (jours 1-7 lancement, 8-14 avec ce qui sort le 19 décembre, 15+ avec ce qui sort le 26) ; règle « Plopettes et Ascension ne glissent pas toutes les deux après le 26 décembre » (§8.1) ; repli Gants à 40 niveaux ; H2 marquée mesurée ; §6.1 réécrit avec les chiffres du lancement |
| E2 | Bloquant | §3.5 `StartR`, §6.3 | Les premières boucles raccourcissent de ×1,78 par Ascension (12 s à A6) ; boucles de 0 s inexpliquées | Plancher `ceil(A × ln 3 / ln 1,3 − 8,9)` écrit avec les clés de configuration ; valeurs 0, 2, 4, 8, **13**, 17, 21, 25, 29, 33 (la critique donnait 12 à A5, mais ceil(12,04) = 13) ; plafond de **6 niveaux** de Tapis offerts (Tapis de départ 3 + cadeau 3, au lieu des 11 possibles) ; robot de nuit à A = 10 ; pistes des boucles de 0 s listées, allumage conditionné à leur explication (§3.5, §8.2) |
| E3 | Bloquant | §3.4, §5.4 | 3 + r Confettis à chaque Petit Splorch : plus rien à acheter vers le jour 55 | 3 + r seulement au Grand Splorch ; 1 par Petit Splorch et par Grand Splorch sauté ; prime de record et +25 gardés ; tuile « Petit Splorch : +1 Confetti » ; clé `confettiUnspent` |
| E4 | Majeur | §3.5 `ReqR`, `ascendGapDays` | +5 par Ascension : écarts de 15 à 20 jours qui s'allongent ; jours 29+ creux à 43,4 % | Pas de +4 (1,3^4 ≈ 3) **après une 1re marche de +5** : conditions 15, 20, 24, 28… La marche de +5 garde `recordRDay28` (20 mesuré avec +5, 19 avec +4 dès la 2e) ; écart à la correction proposée, à mesurer. `ascendGapDays` 11-16 (référence) et 6-10 (assidu) ; clé `starvedDay29plus` ; appliqué avec le facteur de prix (E5) |
| E5 | Majeur | §3.5 « les prix n'ont pas besoin de suivre A » | Faux : assidu avec Ascension à 0,45 / 23,6 T12 | Facteur `Balance.Ascend.PriceMult` = 1,6 sur Tapis, Tapis Étoilé, Décorations, Gants, École (pas Enclos, Lit, Monuments) ; T12 redéfini ; `tapis12LoopShare` et `coinsLostRatio` ajoutées à la configuration « assidu + Ascension » ; phrase fausse retirée |
| E6 | Majeur | §2.1 Tapis Étoilé | 3,5^r compté deux fois ; niveau 13 au prix du Tapis 12 | Formule `floor(20 × 4,5^11 × 1,25^(L − 11) × 3,5^r × 1,6^A)`, L = 12…19 ; tableau refait (383 M à 1,82 B, somme 7,60 B = 24,8 T12) ; cas exacts et test « chaque rangée strictement croissante » |
| E7 | Majeur | §6.1, §6.3, joueur de 2 h par jour | Assidu creux dès la 1re semaine (33,4 %, 56,9 %, 78,8 %) | Clés `starvedAssiduDay2to7` ≤ 15 % et `starvedAssiduDay8to14` ≤ 30 % ; leviers H10 dans l'ordre (Tapis Étoilé prolongé, objectifs ×2,3 dès R16, Gants ×1,45, Plopettes), chacun avec le contrôle du R du jour 28 ; question 6 au propriétaire. **Non résolu** : à mesurer avant le 3 décembre |
| E8 | Majeur | §2.1 formule de pression | 12 × revenu dans le document, 22 dans le code | Formule écrite avec `Balance.Press.Min` et `Balance.Press.Seconds [22]` ; écart ajouté au §2.1 et à la ligne §4.7 du §7.1 |
| E9 | Mineur | §2.1 Monuments | +1 % ajouté dans `A_bonus` = +0,14 à +0,5 % réels | Multiplicateur à part `(1 + 0,01 × Monuments)` ; formule, catalogue et §7.1 mis à jour |
| E10 | Mineur | §3.4 Sac de nuit | Maximum réel 16 h, égal à l'absence simulée ; une connexion par jour non testée | Maximum écrit à 16 h ; configuration de nuit « une connexion par jour » (23,5 h) avec `readyAtLogin`, `coinsLostRatio`, `offlinePotShare` ≤ 2 ; Pot de nuit plafonné à 30 % si échec |
| E11 | Mineur | §3.3, §5.4 | L'Ascension retarde le Record R sans le dire | Clé `recordRDay28` ≥ lancement − 1 ; 3e tuile concrète « +20 Confettis » dans l'aperçu (payés une fois par Ascension) |
| E12 | Mineur | §3.4 cumul des Confettis | Prime de record oubliée (R25 = 450, R30 = 655) | Tableau refait avec toutes les sources (2 lignes ; la 2e retrouve les 379 mesurés au jour 28) ; H8 recalculée (voir U32) |
| E13 | Mineur | §6.3 `loopMaxGapR0to13` | Clé ambiguë ; par r, le lancement échoue | Clé `loopMaxGap` définie par r (médiane ≤ 3 min et p90 ≤ 5 min), mesurée sur le lancement : échoue à R8, R12, R13 ; levier Gants ×1,45 dès le niveau 20 |
| E14 | Mineur | §2.3 règle 7, BigNumber | Ni r ni A bornés ; rien ne teste l'infini | `MaxR = 400`, `MaxA = 60` ; tests de propriété à ces bornes ; formateur testé à 1e308 et `math.huge` ; titres « jusqu'à 400 » au lieu de « à l'infini » |

**Critique interface et technique**

| # | Gravité | Section | Problème | Ce que nous avons fait |
|---|---|---|---|---|
| U1 | Bloquant | §2.2 cartes du Conseillé | Cartes de 600 px dans une zone de 560 ; contenu de 564 px | Cartes de **432 × 528** posées à y = 16 ; pile écrite au pixel (icône 80 au lieu de 96, pour faire tenir le palier sur sa propre ligne : « Bonbon arc-en-ciel · Niv. 7 → 8 » ne tenait pas en 400 px) ; raison sur 1 ligne, phrase entière dans le bandeau ; zones du panneau recalculées (12 + 88 + 64 + 560 + 120 + 16 = 860) ; spec `Layout` |
| U2 | Bloquant | §2.2 lignes et focus | Grossissement 1,05 coupé par la `ScrollingFrame` | Aucun grossissement pour les lignes, les cartes et le rail ; cadre dessiné à l'intérieur ; lignes de 1 328 avec 24 px de marge ; assertion `FocusGuard` sur les rectangles de découpe (règle 14) |
| U3 | Bloquant | §2.3 règle 9 contre GDD §10.1 | `TextScaled` imposé par le GDD, interdit ici ; taille Largest non mesurable | Politique unique pour le GDD §10.1 v1.4 : `TextSize` fixe, `MaxTextSize` pour noms et nombres, phrases prévues pour Largest ; 4 facteurs à mesurer dans Studio et à écrire dans `TextMetrics` ; `TextFit` à Medium et Largest ; affirmations vérifiées dans la documentation [W3] ; risque ajouté pour les 4 fichiers du client qui utilisent `TextScaled` |
| U4 | Bloquant | §2.2 « △ puis ✕ », §3.5 maintien | Le même ✕ peut acheter ou confirmer | `InputGuard` : relâchement vu + 0,3 s (0,4 s après un changement sous le focus) ; achats sur `InputBegan` capté, jamais `Activated` ; specs du robot ; carte de l'Ascension couverte (règle 17, §3.5, §3.7) |
| U5 | Bloquant | §7.3 schéma | Champ « 64 bits » impossible ; `mastery` déborde à la 33e espèce (30 janvier 2027) | Ensembles en tableaux de mots de 32 bits, module `Logic/Bitset` ; spec 200 espèces et 64 objets ; contrôle des 20 Ko gardé |
| U6 | Majeur | §2.1 formule du Tapis Étoilé | Même défaut que E6 | Corrigé comme E6. Écart : nous n'avons pas gardé « niveau 13 = 306 M » proposé ici, car il casse « coûts strictement croissants » ; cas exacts mis à jour (383 M à r = 0, 105 T à r = 10, 1,82 B au niveau 20) |
| U7 | Majeur | §2.3 règle 5 | `^` non identique entre plateformes | Aucune puissance dans `UpgradeMath` et `Prestige`, tables par multiplications successives ; test statique ; montant du serveur affiché sur un refus |
| U8 | Majeur | §2.2 Conseillé recalculé après achat | Une autre famille glisse sous le curseur | La carte garde sa famille (niveau suivant ou MAX) ; choix des familles seulement à l'ouverture et au retour sur l'onglet ; garde de 0,4 s ; spec des 10 appuis |
| U9 | Majeur | §2.2 rail | Écart de 8 px sous les 16 du GDD | 8 boutons de 80 px, écart 16, y 246 à 998 ; icône 48, libellé 36 ; GDD §10.2 et specs du HUD à mettre à jour |
| U10 | Majeur | §2.2 lignes et défilement | Pas de demi-ligne visible ; hauteur fausse ; cartes de 600 px dans l'Atelier | Lignes 1 328 × 112 au pas de 128 (48 px de la 5e visibles) ; hauteur par fonction pure ; rangée de cartes de l'Atelier supprimée, remplacée par un badge « Conseillé » figé à l'ouverture |
| U11 | Majeur | §2.2 modes | □ seulement ; clavier et souris non définis ; appui court muet | Bouton de mode sélectionnable (↑ depuis les onglets, ✕), □ en raccourci, E au clavier, clic ; maintien d'Entrée ou de la souris ; appui court = anneau, `Bump` et message ; spec « D-pad, ✕ et ○ seulement » |
| U12 | Majeur | §2.2 puce « Prochain achat » | 9e élément du HUD ; texte trop long ; cible périmée | `UpgradeAdvisor.next`, au plus 2 fois par seconde, après tout achat ; cible qui ne change qu'après un achat ; 440 × 96 ; noms courts ; cachée quand le Grand Splorch est prêt **ou** que la carte de la cible est affichée (8 éléments au plus, spec) |
| U13 | Majeur | §2.2 cadenas « R 10 » du Tapis Étoilé | Confusion avec le Record R après une Ascension | État à part, icône de boucle et « Splorch X » ; « 12/12 » MAX puis « 12/14 » ; captures r = 3 après Ascension, r = 10, r = 16 |
| U14 | Majeur | §2.2 colonne Texte | Effets de l'Atelier trop longs | Tableau des libellés courts FR / EN, à mettre dans `TextFitPending` avant le code ; phrase entière dans le bandeau |
| U15 | Majeur | §2.3 règle 8 | Multiplicateurs, pourcentages, secondes sans formateur | `Format.multiplier` (3 décimales), `percent`, `seconds` ; `Text.set` seul écrivain de `.Text` ; tests statiques et de propriété |
| U16 | Majeur | §2.2, §3 glyphes | Symboles hors police dans des textes mesurés | Tous dessinés en cadres, flèche entre deux libellés ; test de contrat sur la `cmap` des polices rangées dans le dépôt (règle 18) ; « ✦ » retiré du halo et du spectacle |
| U17 | Majeur | §2.3 règle 6 | Le vrai risque est le mélange de deux canaux | Instantané versionné `{ coins, confetti, levels, version }` dans `UpgradeResult` et le correctif ; spec des deux ordres |
| U18 | Majeur | §4.6, §4.2 seuil de 140 studs | Clignotement du niveau de détail ; budget faux | Détail par index de ranch (ranch courant et ses 2 voisins, hystérésis de 10 studs à la limite) ; budgets refaits (405 exacts) ; spec du robot qui traverse son ranch |
| U19 | Majeur | §4.6 interface | Écran ≈ 2 300 objets, construit à chaque ouverture | Ligne « interface » au budget ; écran construit une fois au chargement ; ombre retirée des lignes ; budget compté de **1 400** (et non l'exemple de 1 000, que le comptage ligne par ligne ne permet pas) ; spec de réouverture |
| U20 | Majeur | §3.2 Petit Splorch | Les voisins voient le squishy sauter de taille | Attribut `PetitSplorchAt` ; animation chez tous les clients en détail complet ; spec du voisin |
| U21 | Majeur | §2.1 Plopettes | Animation et décision du serveur non liées | Cible et `tPress` choisis par le serveur ; nouvelle vérification à `tPress` ; état `moving` de 3 s ; le joueur gagne à égalité ; specs (§7.4, §3.7, §7.2) |
| U22 | Majeur | §4.5 saynètes et visages | Invite □ qui saute ; saynètes coupées ; écritures de `Size` | Ciblage sur la place de repos ; limite de 6 seulement au démarrage ; `CFrame` seulement (« Plat ! » et « Pose » refaits sans changement de taille) ; visage en une seule écriture |
| U23 | Majeur | §4.2, §3.3 placement | Monuments sur la Prairie ; fontaine sans place | 10 emplacements en coordonnées du ranch ; Prairie déplacée dans un jardin du quartier nord ; `WorldLayout.spec` sur les 16 ranchs ; « Geyser de gelée » dans l'emprise du ranch |
| U24 | Majeur | §5.5, §7.2 semaine ISO 53 | Remise à zéro sautée au 4 janvier 2027 | `weekIndex` unique depuis le lundi 5 janvier 1970 ; `weeklyTrack.period` ; specs aux bascules d'année |
| U25 | Majeur | §5.5 première semaine | 18 points possibles pour un palier à 24 | Première période du 2 au 11 janvier (39 points) ; points d'un Défi à la période du tirage ; spec « chaque période atteint 24 » |
| U26 | Majeur | §2.3 captures, §4.1 | Le moteur hors ligne ne dessine ni ombre ni dégradé radial | Captures en style de repli à plat, vrai style vérifié sur l'appareil (M6, M14) ; annexe B |
| U27 | Mineur | §2.2 contenus datés | La date peut basculer écran ouvert | Seul le serveur dit ce qui est sorti (`Released`) ; liste figée à l'ouverture (règle 19) |
| U28 | Mineur | §2.2 colonne État, Confettis | Mots anglais trop longs ; Confettis sans suffixe | Colonne de 232 px (au prix de la colonne Texte, ramenée à 540) ; mots EN Ready, Need, MAX, Busy, Retry ; Confettis bruts jusqu'à 99 999, puis formateur |
| U29 | Mineur | §2.2 navigation | Sélection d'office changée ; libellés différents ; L2 / R2 ; retour de ○ | Sélection d'office du GDD gardée ; bouton au nom de la renaissance prête ; Améliorations dans le cycle après Ranch ; ○ revient à ce qui a ouvert l'écran ; repli du focus sur la première ligne gardée |
| U30 | Mineur | §2.3 règles 12-13 | Réponse tardive puis refus « périmé » : 3 retours | Refus périmé muet quand l'instantané montre déjà le niveau (compteur `UpgradeStale`) ; spec « un seul retour » |
| U31 | Mineur | §3.6, §4.4 | 3e sorte de flèche de bord ; clés de son inexistantes | Aucune flèche pour le Chantier ; `Reward` au lieu de `uiConfirm` et du son à l'envers ; lignes complètes `tierUp` et `chantier` pour le GDD §10.5 ; test de contrat des clés |
| U32 | Mineur | §3.4, H8, `workshopLaunchDoneDay` | Totaux de Confettis faux | Tableau refait (voir E12) ; H8 recalculée : avec la piste, l'Atelier de lancement serait fini vers le jour 16-17, l'ancienne hypothèse était fausse ; nouvelle clé `workshopAllDay` ≥ jour 35 ; seuils lus dans la simulation |
| U33 | Mineur | §6.3 H4 | Cadeau 6 + Tapis de départ 5 non modélisés | Configuration « Atelier de lancement complet » bloquante sur `tapis12LoopShare` et `loopMaxGap` ; plafond de 6 niveaux, plus strict que les 8 proposés |
| U34 | Mineur | §3.5 spectacle, §4.3 costumes | Le Meilleur Ami rétrécit dans le faisceau ; dates qui se touchent | Copie de la taille prise au début du spectacle ; intervalles [début, fin) en UTC ; spec au 2027-01-10T00:00:00Z |

**Ce qui reste ouvert** (aussi dans l'annexe B) : la combinaison retenue pour l'Ascension n'est pas mesurée ; les boucles de 0 s ne sont pas expliquées ; le joueur assidu échoue encore ; les facteurs de `PreferredTextSize` et les vraies largeurs de texte attendent Studio et `TextFit`.
