# Plan de contenu complet — Raise a Squishy

> **Date : dimanche 1er novembre 2026.** Rôle : direction créative.
> **Demande du propriétaire (1er novembre 2026)** : « Pour ce jeu, je veux qu'il soit le plus complet possible, plein d'améliorations, la renaissance (rebirth), de beaux visuels. Regarde les tycoons qui marchent le mieux en ce moment et prends exemple. Prends autant de temps qu'il faut. Je veux un jeu complet à la fin. » Et **zéro bug** : Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration.
> **Ce document fusionne** les trois plans de travail (« Progression », « Renaissance et long terme », « Spectacle et sensations ») d'après le verdict des deux jurys, l'étude `docs/08-etude-tycoons-2026.md` et le GDD v1.3 (`docs/02-game-design-document.md`). Il garde les meilleures idées, écarte les faibles et **tranche chaque doublon** : une seule version de chaque chose.
> **Règle de base : on étend le GDD, on ne recommence rien.** Tout ce qui suit s'ajoute au GDD v1.3. Ce document fait foi jusqu'à la version 1.4 du GDD (liste des changements au chapitre 7).
> **Statut** : proposition à valider par le propriétaire.

**Comment lire ce document**
- **(mesuré)** : chiffre sorti d'une simulation qui rejoue les vraies règles du jeu. Deux sources seulement : la simulation du GDD v1.3 (§4.24) et le prototype du plan « Progression » du 01/11/2026 (`scratchpad/plan-sim/results/ext-16.txt`, résultats vérifiés par un juré). Le prototype avait les Plopettes allumées.
- **(cible)** : valeur de départ choisie par nous, à placer en configuration ; la porte de simulation `EconomyPacing` doit la confirmer avant la sortie. Ce n'est **pas** un résultat.
- **(inférence)** : notre conclusion de designer, écrite nulle part ailleurs.
- **[08-n]** : source de `docs/08-etude-tycoons-2026.md` (liste de son chapitre 11, avec URL et date). **[Wn]** : source vue pour ce document le 01/11/2026 (annexe A).
- **r** = niveau de Grand Splorch de la boucle en cours (le « R » du GDD). **Record R** = le plus haut r jamais atteint ; il ne baisse jamais. **A** = nombre de Jelly Ascend faites.
- **T12** = prix du 12e niveau du Tapis à Goûter dans la boucle en cours : 306 M × 3,5^r (306 M à r = 0, 84,5 T à r = 10). Un prix écrit en T12 donne le même ressenti à tous les r.
- **Effort** : S = 1 à 2 jours de développement avec les tests ; M = 3 à 5 jours ; L = 6 à 10 jours.
- Les chiffres des concurrents viennent de guides et de wikis de fans, souvent contradictoires : ce sont des ordres de grandeur, avec leur date.

---

## 1. Résumé pour le propriétaire

1. **Plus d'améliorations** : on passe de 4 à **9 familles** et de 45 à **141 niveaux** achetables (107 au lancement). Nouveautés : les **Gants Moelleux** (presser plus fort), le **Tapis Étoilé** (le Tapis monte jusqu'au niveau 20), les **Monuments** (grands décors permanents), l'**École des Plopettes** (de petites aides mignonnes) et l'**Atelier de Big Plop**.
2. **Un seul écran « Améliorations »**, fait pour la télé : 4 onglets, 3 cartes « Conseillé », achat ×1 / ×10 / Max à la manette, et une puce « Prochain achat » toujours à l'écran. Plus besoin de marcher jusqu'aux dalles.
3. **Zéro bug d'affichage** : 16 règles écrites, chacune avec son test. Les lignes ne changent jamais d'ordre. Les chiffres ne repartent jamais de 0. Chaque texte est mesuré en anglais et en français, en 720p, 1080p et 4K.
4. **Une renaissance plus riche** : chaque Grand Splorch donne des **Confettis**, la monnaie de l'Atelier (gagnée en jouant, jamais vendue). Chaque niveau R de 1 à 20 débloque quelque chose de nommé **et** de visible dans le ranch.
5. **Une 2e couche, la Jelly Ascend** (dès le Grand Splorch XV) : croissance ×3 pour toujours, un halo, un ciel au-dessus du ranch. **Rien de débloqué ne se perd jamais.** Elle est livrée éteinte et s'allume le 26 décembre si la simulation est verte.
6. **Le ranch embellit pour toujours** : 6 grands paliers (arche, tour, balcon, phare, dôme, couronne) et un changement visible à chaque Grand Splorch. Il ne paraît plus jamais vide après une renaissance.
7. **Des squishies qui ont du caractère** : 6 personnalités, 18 petites saynètes, 6 visages, des réactions au monde. Tout est calculé sur l'appareil du joueur : aucun trafic réseau en plus.
8. **Du contenu chaque semaine** : une piste gratuite de 12 paliers, 3 Défis, des cosmétiques qui reviennent au plus tard 8 semaines après (aucune peur de rater). Un calendrier daté sur 3 mois, publié en données.
9. **Rien n'est vendu en plus** : ni Confettis, ni Ascension, ni chance, ni achat à distance. Tous ces systèmes se gagnent en jouant.
10. **Le calendrier tient grâce à une ligne de coupe** : le 12 décembre, un jeu complet (améliorations, renaissance, visuels) ; Plopettes, Ascension, piste de la semaine et décor personnel dans les 3 semaines qui suivent. **On coupe du contenu, jamais la qualité.**

### 1.1 Ce que nous avons tranché entre les trois plans

| Sujet | Version gardée | Pourquoi |
|---|---|---|
| Confettis par Grand Splorch | **3 + r** (r après le Grand Splorch) : 4 au premier, 13 au dixième | 4 Confettis dès le premier Grand Splorch : une ligne de l'Atelier s'achète tout de suite (choix des deux jurys) |
| Atelier | **Un seul**, comme 4e onglet de l'écran Améliorations, en **lignes** (pas de grille) | Un seul composant et une seule navigation à tester ; une grille à 2 dimensions de plus n'apportait rien à un enfant |
| Contenu de l'Atelier | Confort et départ rapide seulement (§3.4) | Les cartes de croissance et de revenu non simulées (Engrais jusqu'à +75 %, Pot doré, Gelée éternelle) cassaient les jalons ; règle : « seuls le Tapis et r touchent la croissance » |
| 3e monnaie (Prismes) et écran Observatoire | **Supprimés**. Les bonus de l'Ascension se paient en Confettis, dans l'Atelier | Pièces, Confettis et Fame suffisent pour un enfant de 8 ans qui lit peu |
| Condition de la Jelly Ascend | **r ≥ 15**, puis +5 par Ascension ; **aucune condition de tampons** | Mesuré : avec l'extension, le creux commence à R = 15, pas à R = 10 ; une seule condition = un seul texte à lire |
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
2. **Les familles de la boucle donnent des pièces, pas de la croissance.** Seuls le Tapis (et son prolongement, le Tapis Étoilé) et r changent la croissance. C'est ce qui garde les jalons du GDD (mesuré : premier Grand Splorch à 12,6 min, R = 10 / 15 / 20 aux jours 7 / 14 / 28, inchangés avec l'extension).
3. **Toute famille passe la porte `EconomyPacing`** avant d'être allumée (§6.3).

**Le catalogue**

| # | Famille (FR / EN) | Onglet | Ce qu'elle fait | Niveaux | Monnaie et prix | Au Grand Splorch | Ouverture | Effet au maximum |
|---|---|---|---|---|---|---|---|---|
| 1 | Tapis à Goûter / Snack Mat (GDD) | Ranch | Grossir plus vite | 12 | `floor(20 × 4,5^L × 3,5^r)` | Remis à zéro | Dès le début | Croissance ×13 |
| 1b | Tapis Étoilé / Star Mat (même ligne que le Tapis) | Ranch | Grossir encore plus vite | 8 (13 → 20) | `floor(T12 × 1,25^(L − 12) × 3,5^r)` | Remis à zéro | 2 niveaux à r = 10, 12, 14, 16 (dans la boucle) | Croissance ×21 |
| 2 | Décorations / Decorations (GDD) | Ranch | Gagner plus | 18 | `floor(80 × 2,2^L × 3,5^r)` | Remises à zéro, sauf les décorations gardées | Dès le début | Revenu +90 % |
| 3 | Enclos / Pens (GDD) | Ranch | Plus de place | 14 | `floor(1 200 × 2,2^L)` (fixe) | Gardé | Dès le début | 18 places (24 avec le pass) |
| 4 | Lit douillet / Cozy Bed (GDD) | Ranch | Dormir plus longtemps | 1 | 25 M (fixe) | Gardé | Record R ≥ 3 | Hors ligne 8 h → 12 h |
| 5 | Gants Moelleux / Squishy Gloves | Ranch | Presser plus fort | 30 | `floor(2 000 × 1,55^L × 3,5^r)` | Remis à zéro | Record R ≥ 1 | Pressions ×1,75 |
| 6 | École des Plopettes / Plopette School | Plopettes | Des aides plus rapides | 20 | `floor(20 000 × 1,75^L × 3,5^r)` | Remise à zéro (les Plopettes restent) | Record R ≥ 2, dès que les Plopettes sont allumées | Une pression d'aide toutes les 6 s par Plopette |
| 7 | Monuments / Monuments | Ranch | Embellir pour toujours | 10 (4 au lancement) | Voir plus bas | Gardés | Record R = 6, 8, 10 … 24 | +10 % de revenu, 10 grands décors |
| 8 | Atelier de Big Plop / Big Plop's Workshop | Atelier | Confort et départ rapide, pour toujours | 9 lignes, 28 niveaux | Confettis | Gardé | Record R ≥ 1 | §3.4 |
| — | Cuve à Gelée (GDD, lecture seule) | Atelier | — | 8 | Donnée par le Record R | Gardée | R0 → R7 | Qualité 8, vitesse 10, 5 buses |
| — | Paliers de ranch (lecture seule) | Atelier | — | 6 | Donnés par le Record R | Gardés | R1, 3, 5, 10, 15, 20 | Ranch transformé |

L = niveau actuel (le premier achat coûte la base). Les familles 1, 1b, 2, 5 et 6 sont multipliées par 3,5^r, comme au GDD. **Total des niveaux achetables** : 12 + 8 + 18 + 14 + 1 + 30 + 20 + 10 + 28 = **141** (107 au lancement, sans l'École, sans Plume, avec 4 Monuments et sans les niveaux réservés aux joueurs qui ont fait une Ascension).

**Écart GDD / code à corriger dans le GDD** : le GDD §4.6 donne au Tapis une croissance de prix ×4,0 ; le code (`src/shared/Config/Balance.luau`, réglage de la revue « logic » du 01/11/2026) utilise **×4,5**, parce qu'avec ×4,0 les pièces perdues au Grand Splorch valaient 13 à 17 fois le Tapis 12. Toutes les valeurs de ce document sont celles du code.

**Tapis à Goûter (prix à r = 0, à multiplier par 3,5^r ; effet = croissance du ranch)**

| Niveau acheté | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 20 | 90 | 405 | 1 822 | 8 201 | 36,9 K | 166 K | 747 K | 3,36 M | 15,1 M | 68,1 M | 306 M |
| Croissance | ×2 | ×3 | ×4 | ×5 | ×6 | ×7 | ×8 | ×9 | ×10 | ×11 | ×12 | ×13 |
| Palier | Nappe pique-nique | | | Biscuit sablé | | | Bonbon arc-en-ciel | | | Gelée dorée | | |

Somme des 12 niveaux : 394 M (1,3 T12).

**Tapis Étoilé (niveaux 13 à 20 ; seulement après le Tapis 12)**

| Niveau acheté | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|
| Prix (r = 0) | 306 M | 383 M | 478 M | 598 M | 748 M | 935 M | 1,16 B | 1,46 B |
| Croissance | ×14 | ×15 | ×16 | ×17 | ×18 | ×19 | ×20 | ×21 |
| Ouvert dans la boucle à | r = 10 | r = 10 | r = 12 | r = 12 | r = 14 | r = 14 | r = 16 | r = 16 |
| Palier | Étoilé | | | | Galaxie | | | |

Somme : 6,08 B (19,8 T12) ; à r = 10, le niveau 13 coûte 84,5 T. Le plafond du Tapis Étoilé suit **r de la boucle**, pas le Record R : c'est un plafond d'économie, pas un déblocage (sinon, après une Ascension, un joueur à r = 0 achèterait une croissance ×21 pour presque rien). Le texte le dit : « Tapis Étoilé : à partir du Grand Splorch X dans cette boucle ». Le prototype en fait la pièce qui comble la fin des boucles : temps « à plus de 3 min d'un achat » aux jours 8-14 de 14,3 % sans lui contre 7,8 % avec (mesuré, mais les deux variantes diffèrent aussi par d'autres réglages). Il change la croissance : il passe donc la porte de simulation (aucun jalon déplacé dans le prototype, car il s'achète en toute fin de boucle).

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

**Les Plopettes** (personnages, gardés pour toujours) : **Pip** (Record R 2), **Pop** (R4), **Pim** (R6), **Pom** (R8), **Puff** (R12), et **Plume**, la 6e, achetée à l'Atelier (dès R12). Une Plopette sautille jusqu'à un squishy prêt et le presse. Sa récompense : `0,5 × pressReward(revenu du squishy, PERFECT = non, série = 0, Kitty) × Gants`. Règles du serveur : seulement un squishy de l'enclos ou du Bassin **prêt depuis au moins 3 s**, ni porté ni en attente de Grand Splorch, **à plus de 12 studs à plat de la position validée du joueur** (sa portée de pression est de 10 studs : une Plopette ne vole jamais le squishy que l'enfant vise) ; elles ne travaillent que si le propriétaire est sur le serveur, **font la sieste après 5 min sans aucune entrée** et se réveillent à la première ; pause pendant son Grand Splorch. Mesuré au jour 7 : les Plopettes font ≈ 9 % des pièces gagnées en jeu, les pressions du joueur 60 % (le GDD exige au moins 50 %). Le prototype ne connaissait pas la règle des 12 studs : leur part réelle sera plutôt plus faible (à refaire dans le vrai modèle). Pourquoi les enfants vont aimer : des personnages qui travaillent pour toi sont le cœur des tycoons qui marchent (managers de Sell Lemons [08-43], employés de Restaurant Tycoon 3 [08-55]), et les nôtres sont mignons et nommés (inférence).

**Monuments** : grands objets en formes simples, construits **derrière le fond du ranch**, visibles du ranch, de la rue et des voisins ; ils restent pour toujours. Effet : **+1 % de revenu chacun** (additif dans le bonus du GDD §4.3), surtout décoratif. Mesuré : 2 Monuments au jour 7, 7 au jour 28 pour le joueur de référence, aucun effet sur le rythme.

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

**Prix d'un Monument** : `3 × T12(R d'ouverture) × 3,5^(r − Record R)`. Avant toute Ascension, r = Record R, donc le prix est fixe (3 T12 au moment où il s'ouvre : un but de plusieurs boucles, puis abordable ; c'est la version mesurée). Après une Ascension, r repart de 0 mais le Record R reste : le prix suit la boucle en cours, avec la même difficulté relative qu'avant. Correction de la critique du jury (« le prix fixe casse après une Ascension »). Les noms ont été choisis pour ne doubler aucun autre objet du jeu (le phare est un palier de ranch, la lune est celle de la Jelly Moon).

**Formules du GDD qui changent** (ajouts en gras)

```
croissance g = 1 × 2^r × 3^A × (1 + niveauTapis [0 à 20]) × (1 + 0,10 × familleJellyComplète) × B
revenu       = 0,02 × rareté × taille × mutation × (1 + 0,5 × étoiles) × A_bonus × P × B
               A_bonus = l'additif « A » du GDD (décorations, amis, Fame, Étagère, pages dorées) + 0,01 × Monuments
pression     = floor(max(10, 12 × revenu) × (PERFECT ? 2 : 1) × (1 + 0,10 × min(5 + superSérie, série))
                     × (Kitty ? 1,10 : 1) × (1 + 0,025 × niveauGants))
```

L'additif « A » du GDD est renommé **`A_bonus`** pour ne pas le confondre avec le nombre d'Ascensions. Tous les facteurs nouveaux sont multiplicatifs ou bornés, jamais des bonus additifs inutiles en fin de courbe (piège de Merge a Nuke [08-83]).

### 2.2 L'écran « Améliorations » à la télé

**Où on le trouve.** Le menu (△ ou croix ↓) a une entrée **Améliorations**. Sélection d'office du menu : Grand Splorch s'il est prêt, sinon le bouton à pastille « ! », sinon **Améliorations si un achat est payable**, sinon le dernier utilisé, sinon Ranch. Dans le cas courant, **△ puis ✕** ouvre l'écran (2 appuis). Raccourci clavier : **U**. Le kiosque de Big Plop sur la place ouvre le même écran sur l'onglet Atelier. Les **dalles au sol restent** (Tapis, décorations, Enclos, Lit) pour le geste du début ; les familles nouvelles s'achètent seulement depuis l'écran. L'onglet *Dalles* du panneau Ranch est retiré : l'écran Améliorations le remplace.

**Le rail du menu reste dans la zone sûre.** Avec l'entrée Améliorations, le rail peut avoir 8 boutons : ils passent à **88 px de haut avec 8 px d'écart** (8 × 88 + 7 × 8 = 760 px, de y = 246 à 1 006, sous la limite de 1 026). Grand Splorch et Jelly Ascend **partagent un seul bouton** « Renaissance » : il affiche le premier qui est prêt ; si les deux le sont, l'aperçu a deux onglets (L1 / R1).

**Le panneau** (1 440 × 860 px TV, comme les autres, GDD §10.3 ; toutes les tailles sont en px TV à 1 920 × 1 080, mises à l'échelle par l'`UIScale` du GDD §10.1)

| Zone | Position et taille | Contenu |
|---|---|---|
| En-tête | 96 px de haut | Titre « Améliorations » 48 px ; à droite, 3 pastilles **toujours présentes, à place fixe** : pièces (icône 48 + montant 40 px, largeur réservée 280), Confettis (icône 48 + montant 40 px, largeur 200), mode « □ ×1 » (glyphe 48 + texte 40 px, largeur 200) |
| Onglets | 72 px de haut, libellés 32 px | **Conseillé**, **Ranch**, **Plopettes**, **Atelier**. L1 / R1 changent d'onglet ; ↑ depuis le haut du contenu atteint aussi les onglets (règle des 3 touches) |
| Contenu | 1 376 × 560 | Conseillé : 3 grandes cartes. Autres onglets : liste de lignes |
| Bandeau de détail | 1 376 × 88, toujours en bas | Ce qui ne tient pas dans la ligne sélectionnée : palier actuel et prochain, aperçu ×10 / Max complet, raison d'un refus. 28 px, 2 lignes au plus. Vide : « — » (jamais un trou) |

**Onglet Conseillé** (ouvert par défaut) : **3 grandes cartes** de 432 × 600, écart 32. Chaque carte : icône 160 ; nom de la famille 40 px (2 lignes au plus) ; nom du palier 28 px ; « Niv. 7 → 8 » 32 px ; **avant → après** 32 px (« Pressions ×1,15 → ×1,18 », 2 lignes au plus) ; une raison 28 px (« Pour grossir plus vite », 2 lignes au plus) ; prix (icône 48 + montant 40 px) ; bouton « ✕ Acheter » de 96 px de haut. ← → passent d'une carte à l'autre ; ↓ ne fait rien (son `Bump`). S'il manque une carte (tout est au maximum), la place montre une carte neutre « Tout est au maximum ! Prochain but : Grand Splorch » : jamais un trou.

**Règle du Conseillé** (module pur `UpgradeAdvisor`, déterministe) : candidats = familles ouvertes et pas au maximum. (1) Le Tapis s'il est payable ; (2) puis la moins chère payable d'une autre famille ; (3) puis la moins chère payable d'une troisième famille ; s'il en manque, on complète avec les moins chères **non payables** (barre « Il manque … »). Jamais deux cartes de la même famille ; égalités départagées par l'ordre fixe des familles ; les Monuments n'apparaissent qu'après le Tapis 12 de la boucle. L'Atelier a sa propre rangée « Conseillé » de 3 cartes en tête de son onglet (la moins chère achetable de chaque ligne, à égalité dans l'ordre fixe). **Le Conseillé n'est recalculé qu'à l'ouverture de l'écran et après un achat confirmé**, jamais en continu.

**Onglets Ranch, Plopettes, Atelier : des lignes de 1 376 × 128**, écart 16 (4 lignes et demie visibles : la demi-ligne montre qu'on peut descendre). Colonnes **de largeur fixe**, de gauche à droite :

| Colonne | x (dans la ligne) | Largeur | Contenu |
|---|---|---|---|
| Icône | 16 | 96 | Icône dessinée en cadres (aucune image téléversée) |
| Texte | 128 | 588 | Ligne 1 : nom de la famille, 36 px (1 ligne). Ligne 2 : **avant → après**, 32 px (« Croissance ×13 → ×14 », 1 ligne) |
| Niveau | 732 | 140 | « 12/30 » en 40 px ; dessous, barre de 140 × 12 vers le prochain palier. En mode ×10 / Max : « 12→22 » |
| Prix | 888 | 240 | Icône 40 + montant 40 px (prix du mode choisi) ; dessous, barre de 240 × 8 de « ce que j'ai / ce qu'il faut » |
| État | 1 144 | 200 | **Icône 48 + un mot 28 px**, jamais la couleur seule : ✓ « Prêt », sablier « Il manque », étoile « MAX », cadenas « R 6 », sablier animé « En cours », flèche « Réessaie » |

Une seule chose sélectionnable par ligne : la ligne elle-même (↑ ↓ seulement, aucun sous-bouton). La sélection reste visible avec une ligne de marge (GDD §10.6). Un badge de 32 px dans le coin de l'icône dit ce que devient la ligne au Grand Splorch : **↺** « repart de zéro » (Tapis, décorations, Gants, École) ou **∞** « gardé » (Enclos, Lit, Monuments, Atelier).

**Ordre fixe des lignes** (configuration `Config/Upgrades`, jamais retrié)
- **Ranch** : Tapis à Goûter (et Tapis Étoilé sur la même ligne), Décorations, Enclos, Lit douillet, Gants Moelleux, Monuments.
- **Plopettes** : École des Plopettes, puis une ligne en lecture seule par Plopette (nom, « Presse toutes les 9,0 s », « Fait la sieste » le cas échéant). L'onglet est caché tant que les Plopettes sont éteintes par configuration. Les onglets et les lignes liés à un interrupteur (Plopettes, Plume, Tremplin) sont **construits à l'ouverture de l'écran** d'après l'interrupteur ; un interrupteur qui change pendant que l'écran est ouvert ne s'applique qu'à la prochaine ouverture : jamais un onglet ou une ligne qui apparaît sous les yeux du joueur. Allumé, l'onglet reste visible avec un cadenas « R 2 » avant Pip.
- **Atelier** : rangée Conseillé, puis les 9 lignes du §3.4 dans leur ordre, puis 3 lignes en lecture seule « Monte avec le Grand Splorch » (Cuve, prochain palier de ranch, prochain déblocage), puis la section « Pour le plaisir » (cosmétiques).
- **Toutes les lignes d'un onglet existent toujours**, même verrouillées (cadenas et condition) : **aucune ligne n'est jamais ajoutée, retirée ou déplacée pendant que l'écran est ouvert.** On voit ce qui arrive, et la mise en page ne bouge jamais.

**Acheter ×1, ×10 ou Max**
- □ fait tourner la puce de mode : **×1 → ×10 → Max → ×1**. **Le mode revient à ×1 à chaque ouverture** de l'écran : un petit frère qui reprend la manette ne vide pas la cagnotte.
- **×1 : un appui sur ✕. ×10 et Max : maintien de ✕ pendant 0,6 s** (anneau autour du glyphe, même durée que sur une dalle).
- **Aperçu exact avant d'acheter** : en ×10 / Max, la ligne montre « 12→22 » et le prix total ; le bandeau dit la phrase entière : « ×10 : Niv. 12 → 22 · 1,23 M », « Max (×7) : Niv. 12 → 19 · 845 K », ou « ×10 : 4 possibles · Niv. 12 → 16 · 310 K ».
- **Retour chiffré, toujours** : dans la ligne même, « +7 niveaux · −1,2 M » pendant 1,5 s, son `TileBuild`, vibration `tileBuy`. Si rien n'est payable : la raison (« Il manque 1,2 K »), son `Error` doux, vibration `refuse`, aucune secousse.
- Max ne dépense que dans **la famille choisie**. Achat partiel accepté et annoncé (« 4 sur 10 »).

**La puce « Prochain achat »** du HUD : colonne de gauche, à (96, 342), 340 × 88. Icône 56, nom et niveau (« Tapis Niv. 8 », 32 px), barre et « 12,3 K / 20 K » (28 px). Quand c'est payable : « Prêt ! » et **une seule** pulsation (jamais de clignotement). Elle montre la première carte du Conseillé. Cachée pendant l'accueil jusqu'à la leçon du menu (GDD §3), et quand le menu ou un panneau est ouvert (elle ne chevauche donc jamais le rail).

**« Dépenser d'abord »** (aperçu du Grand Splorch, GDD §4.15) ouvre l'écran sur l'onglet Ranch, **sans changer l'ordre** : la sélection se pose sur la première ligne **gardée** (∞) et payable (Enclos, Lit douillet, Monuments).

### 2.3 Les règles « zéro bug d'affichage »

Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration. Clash of Clans en a reconnu deux sur son nouvel écran (tri, compteur qui repart de 0, 08/10/2026 [08-60]). Chaque règle ci-dessous a un test **bloquant**.

| # | Règle | Test |
|---|---|---|
| 1 | **Ordre fixe.** Aucun tri dynamique ; seul le Conseillé est recalculé (ouverture et achat confirmé) ; la sélection reste sur la même ligne ou le même emplacement de carte | Rejouer 1 000 achats au hasard : l'ordre ne change jamais, la sélection reste en place |
| 2 | **Aucune ligne détruite ni créée** pendant que l'écran est ouvert ; lignes verrouillées toujours présentes | Spec de structure : même nombre d'instances avant et après 1 000 achats |
| 3 | **Un compteur ne repart jamais de 0.** Montré pour la première fois (ouverture, onglet), il affiche directement sa valeur ; il ne s'anime que si la valeur change pendant qu'il est visible, depuis la **dernière valeur affichée**. Au Grand Splorch, les pièces passent à 0 sans animation, avec un « pouf » | Changer d'onglet 50 fois : aucun nombre ne vaut transitoirement « 0 » |
| 4 | **Valeur finale toujours posée** à la fin d'une animation **et** à son interruption | Capture après interruption à 0 %, 50 %, 100 % : même image |
| 5 | **Un seul calcul de prix**, le module pur `UpgradeMath`, partagé par l'aperçu du client et le serveur ; jamais de prix en cache ; somme exacte niveau par niveau (boucle de 30 au plus, pas de formule fermée arrondie autrement) | Propriété : `bulk(n)` = somme de n achats ×1 ; aperçu = débit réel dans 10 000 cas tirés au hasard |
| 6 | **Version de l'état.** Chaque réplication porte `upgradesVersion` ; l'écran ignore une version plus ancienne que celle affichée | Messages livrés dans le désordre : l'écran finit toujours sur l'état du serveur |
| 7 | **Largeurs réservées** pour la plus longue valeur formatée (« 8,88e305 », 8 caractères à 40 px) ; aucun `AutomaticSize` sur une ligne ; rien ne change de taille quand un nombre grandit | Propriété sur 10 000 nombres : largeur mesurée ≤ largeur réservée |
| 8 | **Un seul formateur de nombres** (`BigNumber.abbreviate`, GDD §4.2 : 3 chiffres tronqués, suffixes K à Dc, puis notation « 1,23e36 ») et **une couleur par famille de suffixes** : K-M blanc, B-T or, Qa-Qi rose, Sx et au-delà cyan (Sx et Sp ne se confondent plus [08-104]) | Chaque nombre de l'écran passe par le formateur (test statique : aucun `tostring` de nombre dans `UI/*`) |
| 9 | **Texte mesuré, 2 lignes au plus.** Tailles de police fixes (pas de `TextScaled`, qui ignore la taille de texte choisie par le joueur [08-145]) ; chaque clé de texte de l'écran est mesurée avec la vraie police, à sa taille, dans sa boîte, en anglais et en français ; noms ≤ 1 ligne, phrases ≤ 2 lignes ; **aucun rétrécissement automatique en jeu** : un texte qui ne tient pas fait échouer la porte | `TextFit_all.spec` (outil Screens) sur toutes les clés nouvelles, à la taille de texte du joueur au maximum |
| 10 | **Tailles de carte et de ligne fixes** (432 × 600 et 1 376 × 128) ; un seul layout par parent ; hauteur de défilement calculée (lignes × 144), jamais une `ScrollingFrame` en taille automatique [08-161] | Spec de structure : aucun parent avec deux `UI*Layout` |
| 11 | **Un seul composant de carte** (`UI/UpgradeCard`, 2 gabarits fixes : grande carte et ligne), partagé par Ranch, Plopettes, Atelier et les aperçus de renaissance | Toutes les variantes testées une fois, dans tous les états |
| 12 | **État « en attente » de 3 s** par ligne (sablier, ligne inactive) ; sans réponse, la ligne revient et dit « Réessaie » ; une réponse tardive est appliquée normalement (l'écran affiche toujours l'état du serveur, jamais un état deviné) ; compté dans Diagnostics (`UpgradeTimeout`) | Serveur muet : retour à l'état normal en 3 s, focus intact ; réponse à 3,5 s : un seul retour chiffré |
| 13 | **Jamais un achat muet** : chaque réponse du serveur produit exactement un retour visible (« +n niveaux · −prix » ou la raison) | Spec : 1 réponse = 1 retour |
| 14 | **Bouton remis à l'état normal** après chaque appui à la manette, rafraîchissement ou changement d'onglet (le bouton qui reste « appuyé » est un bug connu de Roblox [08-65]) ; aspect de sélection dessiné par nous (cadre de 6 px) | Robot manette : après achat, Max, rafraîchissement, aucun élément « appuyé » |
| 15 | **Focus jamais perdu ni piégé** (`FocusGuard`, GDD §10.6) ; le focus reste sur la carte achetée, même si elle passe à MAX | Robot croix + ✕ + ○ sur les 4 onglets, à chaque état |
| 16 | **Aucun Robux dans cet écran.** Les prix en Robux restent dans la Boutique, lus par joueur avec la remise Roblox Plus [08-125] | Test statique : aucune clé de produit dans `UI/Panels/Upgrades` |

**Captures de référence** (outil Screens) aux **3 résolutions (1 280 × 720, 1 920 × 1 080, 3 840 × 2 160) × 2 langues × 2 qualités**, pour ces états : r = 0 tout neuf ; r = 5 ; r = 20 tout au maximum ; pièces à 1e300 ; tout verrouillé ; une ligne « en attente » ; une ligne « Réessaie » ; chaque mode ×1 / ×10 / Max ; Atelier vide, à moitié, complet. Toute différence d'image non voulue fait échouer la porte.

---

## 3. Renaissance

### 3.1 Les couches

| | **Couche 1 : Grand Splorch** | **Couche 2 : Jelly Ascend** |
|---|---|---|
| Statut | GDD v1.3, enrichi ; au lancement | Code prêt avant le lancement, **éteint** (`Features.JellyAscend = false`) ; allumé le **samedi 26 décembre** si la porte est verte, sinon le 2 janvier |
| Condition | Plus gros squishy ≥ objectif(r) : 15 000 × 2,6^r (table du GDD §4.15) | **r ≥ 15** pour la 1re, puis **+5** à chaque Ascension (20, 25, 30…) |
| Repart de zéro | Pièces, Pot, Tapis (et Tapis Étoilé), décorations non gardées, Gants, École, taille de chaque squishy | Tout ce que repart le Grand Splorch, **et r** (retour au Grand Splorch de départ) |
| Toujours gardé | Squishies (espèce, mutation, étoiles, tenue, verrou), Record R et tous ses déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, Enclos, Lit, Cuve, selles, Squishydex, Étagère, Fame, jours de Plop, passes, cosmétiques | Idem |
| Gain | Croissance ×2 (pour la boucle), **3 + r Confettis**, cadeau du Splorch, un déblocage nommé à chaque nouveau Record R, +5 Fame (50 par jour au plus) | **Croissance ×3 pour toujours** (×3^A), une goutte de halo, un élément de ciel, un titre, des lignes nouvelles à l'Atelier, +20 Fame |
| Première fois (joueur de référence, 30 min par jour) | 12,6 min (mesuré) | Jour 14 (cible) ; jour 7 à 8 pour un joueur de 2 h par jour (cible) |

**Pas de 3e couche** dans ce plan. Une décision ne viendra pas avant mars 2027, sur les données (par exemple : part des joueurs du jour 30 qui ont fait 8 Ascensions), et sans 3e monnaie.

**Le Record R, seule règle à retenir.** Tout ce qu'on **voit ou possède** (familles d'espèces, Cuve, Meilleurs Amis, Lit douillet, titres, paliers de ranch, changements du ranch, Plopettes, Monuments ouverts, lignes de l'Atelier, cosmétiques) suit le **Record R**, qui ne baisse jamais. Ce qui règle **l'économie de la boucle** (objectif de taille, prix ×3,5^r, croissance ×2^r, plafond du Tapis Étoilé, Confettis gagnés) suit **r**. Une Ascension ne fait donc jamais disparaître une arche, une buse, un Meilleur Ami ou une Plopette.

**Des textes vrais.** Avec une couche au-dessus, « Croissance ×2 **pour toujours** » (GDD §4.15, §9.4) deviendrait faux. La tuile devient « **Croissance ×2** » et le spectacle dit « Plop est là ! ×2 ! ». « Pour toujours » reste écrit seulement sur ce qui l'est vraiment : squishies, déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, ×3 de chaque Ascension. C'est la règle du GDD « ce qu'on voit est vrai » (§12.10) appliquée aux mots.

### 3.2 Grand Splorch et Petit Splorch

- **Grand Splorch** (le nouveau r dépasse le Record R) : tout le GDD §4.15 sans changement (aperçu, maintien de 1,5 s, file du serveur, spectacle de 7,5 s, cadeaux pour tout le serveur). Avant toute Ascension, **chaque** renaissance est un Grand Splorch : le lancement se joue exactement comme le GDD.
- **Petit Splorch** (le nouveau r est ≤ Record R ; n'existe qu'après une Ascension) : même aperçu et même maintien de 1,5 s, mêmes conditions d'entrée (dans son ranch, rien porté, aucun squishy en fuite), mais **hors de la file du serveur** et appliqué tout de suite, d'un seul bloc. Animation **locale** de 2,5 s dans son ranch : le squishy saute, rétrécit avec un « pouf », pluie de confettis sur son ranch, petit texte « Plop est là ! ×2 ». Pas de bannière, pas de cadeaux aux autres. Il donne ses Confettis et le cadeau du Splorch. Raison : le GDD limite chaque serveur à un Grand Splorch toutes les 20 s ; 6 à 8 vétérans à boucles de 60 s après une Ascension satureraient la file et retarderaient le premier Grand Splorch des nouveaux joueurs (remarque du jury).
- **Plafonds sociaux** : Fame du Grand Splorch +5, **50 par jour au plus** (`Balance.Caps.fameSplorch = 50`) ; un même joueur déclenche **au plus une bannière « GRAND SPLORCH » toutes les 3 min** (sinon une petite ligne).

**L'aperçu montre toujours 3 tuiles concrètes**, jamais une tuile vide : « Croissance ×2 » ; **le déblocage de ce niveau** (une image et 2-3 mots : « Place d'enclos offerte », « 3 décorations restent ! ») ou, s'il est déjà gagné, « Cadeau du Splorch » ; « +13 Confettis ».

**Le cadeau du Splorch** (gratuit pour tous dès le premier Grand Splorch) : juste après l'éclatement, une pluie de pièces dorées tombe dans le Pot. Elle vaut **le prix du prochain niveau du Tapis** dans la nouvelle boucle (1 niveau ; jusqu'à 6 avec la ligne de l'Atelier) : l'enfant rachète le Tapis dans les 30 s et sent la vitesse doublée (gain senti dans les 30 s, conseil des développeurs de jeux idle, confiance faible [08-88]).

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
| 17 | Selle « Cosmos » | **Fontaine de Gelée géante** (côté rue, vue par tous) | Habillage « Cosmos sucré » |
| 18 | Monument 7 | **Cadre doré** autour de la silhouette du ranch | — |
| 19 | Emote « Couronne de confettis » · drapeau « Splorch Royal » | **Étagère à trophées dorée** | — |
| 20 | Titre Jelly Titan · Monument 8 · selle « Titan » | Palier 6 **Couronne flottante** | Habillage « Royal » |
| 21 et plus | **Prime de record** : +10 Confettis au premier passage de chaque Record R | — | — |
| 22, 24 | Monuments 9 et 10 | — | — |
| 25, 30, 35, 40 | Titres Splorch Myth, Jelly Monarch, Wobble Legend, Cosmic Splorcher · une couleur de traînée | 1 à 4 étoiles sur la couronne | — |
| 50, puis tous les 10 | Titre écrit en données | Couronne arc-en-ciel au 50 | — |

Chaque R de 1 à 20 a **au moins une entrée de la colonne « ranch » disponible au lancement** : la table reste complète même si les Plopettes et les habillages arrivent plus tard. Test bloquant : chaque R de 1 à 20 a au moins un déblocage nommé et au moins un changement visible ; chaque clé existe en anglais et en français ; l'aperçu montre toujours 3 tuiles.

### 3.4 L'Atelier de Big Plop : chaque ligne, chaque niveau

**Confettis** : **3 + r** à chaque Grand ou Petit Splorch (r après la renaissance), plus la prime de record (+10 au-delà de R20), plus +25 si une place offerte tombe sur un enclos plein, plus la piste de la semaine (34 par semaine, à partir du 2 janvier). **Jamais vendus, jamais une chance, jamais remis à zéro**, même par une Ascension. Cumul au premier passage : R1 = 4, R2 = 9, R5 = 30, R8 = 60, R10 = 85, R12 = 114, R15 = 165, R20 = 270, R25 = 400, R30 = 555. Petits entiers (moins de 10 000 le premier mois) : jamais de suffixe K. Icône dessinée en cadres (3 petits rectangles inclinés rose, menthe, jaune), de forme et de couleur différentes de la pièce. Le compteur n'est pas dans le HUD (règle « peu d'éléments », GDD §10.2) : il est dans l'en-tête de l'écran Améliorations, dans l'aperçu du Grand Splorch et sur la carte de récompense.

| # | Ligne (FR / EN) | Niveaux | Coût de chaque niveau (Confettis) | Effet | Condition |
|---|---|---|---|---|---|
| 1 | Cadeau du Splorch / Splorch Gift | 5 | 3 · 5 · 8 · 12 · 18 (46) | Le cadeau du Splorch paie **2, 3, 4, 5 puis 6** niveaux du Tapis (les prochains, après ceux du Tapis de départ) au lieu de 1 | Record R ≥ 1 |
| 2 | Tapis de départ / Head-Start Mat | 5 | 12 · 25 · 45, puis 90 · 160 (332) | Chaque boucle commence avec le Tapis déjà au niveau 1, 2, 3, puis 4, 5 | Niveaux 4 et 5 : A ≥ 1 |
| 3 | Aimant à pièces / Coin Magnet | 3 | 4 · 8 · 14 (26) | Rayon d'encaissement du Pot : 5 → 8 → 11 → 14 studs | Record R ≥ 1 |
| 4 | Super Série / Super Streak | 2 | 10 · 20 (30) | Série PERFECT jusqu'à 6 puis 7 (+60 % puis +70 % au lieu de +50 %) | Record R ≥ 1 |
| 5 | Déco qui reste / Kept Decorations | 4 | 15 · 60, puis 100 · 180 (355) | +3 décorations gardées au Grand Splorch par niveau (18 au plus avec celles des R8 et R14) | Niveaux 3 et 4 : A ≥ 1 |
| 6 | Sac de nuit / Night Bag | 3 | 6 · 12 · 20 (38) | Limite hors ligne +1 h par niveau (8 → 11 h ; 12 → 15 h avec le Lit). La croissance hors ligne s'arrête toujours à 90 % de l'objectif | Record R ≥ 1 |
| 7 | Pot de nuit / Night Pot | 2 | 15 · 30 (45) | Pièces hors ligne dans le Pot : 25 % → 30 % → 35 % du revenu | Record R ≥ 1 |
| 8 | Plume (6e Plopette) | 1 | 40 | Une Plopette de plus | Record R ≥ 12 et Plopettes allumées |
| 9 | Tremplin / Springboard | 3 | 40 · 80 · 150 (270) | Après une Ascension, on repart 1, 2 puis 3 Grands Splorch plus haut ; les Confettis des Grands Splorch sautés sont versés d'un coup | A ≥ 1 |
| | **Total des 9 lignes** | **28** | **1 182** | | |

**Section « Pour le plaisir »** (en bas du même onglet, pour les Confettis en trop) : 6 palettes de couleurs du spectacle du Grand Splorch (Bonbon, Menthe, Lavande, Arc-en-ciel, Nuit douce, Sucre glace ; 20 chacune), selle « Cotillon » (40), traînée « Serpentins » (50), emote « Danse de Big Plop » (60), titre « Confetti Star » (100) : **370**. Au lancement : 3 palettes et la selle (100).

**Au lancement** : lignes 1 à 7 sans les niveaux réservés à A ≥ 1 (**342 Confettis**, tout acheté vers R23-24, soit vers la fin du premier mois pour le joueur de référence ; cible). Plume suit les Plopettes ; Tremplin et les niveaux A ≥ 1 suivent la Jelly Ascend. Au total, Atelier et cosmétiques valent **1 552 Confettis** : un but de plusieurs mois (cible).

**Ce que l'Atelier ne vend jamais** (test de contrat sur la liste fermée des effets) : rien qui touche la croissance (sauf le Tapis de départ, qui n'est que du Tapis acheté d'avance), une probabilité, la Cuve, les créatures en fuite, le Golden Wobbler, les mutations, les raretés ; rien qui allonge le combo maximal (classement « Meilleur combo » juste, GDD §6.9) ; rien qui double un pass payant (pas de Pot automatique, pas de places au-delà de 18).

**Pourquoi les 8-13 ans vont aimer.** Les meilleurs tycoons séparent une progression remise à zéro et une couche permanente gagnée au prestige : Investisseurs et Powers de Sell Lemons, recherche « Lemon Labs » gardée aux remises à zéro (2026) [08-44][08-46]. L'Atelier transforme le Grand Splorch en « je gagne quelque chose à moi », pas seulement « ×2 » (inférence).

### 3.5 Jelly Ascend en détail

| Paramètre (configuration `Balance.Ascend`) | Valeur de départ (cible) |
|---|---|
| Condition de la k-ième Ascension | r ≥ **15 + 5 × (k − 1)** : 15, 20, 25, 30… (`ReqR`) |
| Gain | Croissance **×3 pour toujours** par Ascension (`GrowthMult = 3`) |
| Grand Splorch de départ après la A-ième Ascension | `min(2 × (A − 1) + Tremplin, condition suivante − 10)` : 0, puis 2, 4… (`StartR`). Les Grands Splorch sautés paient leurs Confettis (3 + k pour chacun) |
| Fame | +20 |
| Halo | Une goutte de plus, jusqu'à 5 |
| Ciel du ranch | A1 Nuage-coussin, A2 Arc de gelée, A3 Aurore sucrée (3 rubans `Neon` courbes, sans particules), A4 Planète bonbon, A5 Anneau prismatique, A6 à A9 variantes de couleur, A10 Constellation |
| Titres | A1 « Ascended », A3 « Sky Keeper », A5 « Sky Wobbler », A10 « Star Jelly » |
| Atelier | A1 ouvre Tremplin et les niveaux 4-5 du Tapis de départ et 3-4 de Déco qui reste |
| Habillages (2 janvier) | A1 « Nuage », A3 « Aurore », A5 « Céleste » |
| Facultative | Jamais forcée ; continuer r au-delà de la condition ne fait rien perdre |
| Rien en Robux | Aucune Ascension vendue (Sell Lemons vend un saut d'Évolution 160 R$, juin-juillet 2026, d'après TechWiser cité par le plan Renaissance) ; aucun bonus de la couche d'avant effacé (Sell Lemons efface les Powers à l'Évolution, 2026) |

**Pourquoi c'est équilibré (inférence, à confirmer par la porte).** Avec ×3 de croissance, une boucle dure environ 3 fois moins longtemps ; le revenu suit la taille, donc les dalles s'achètent au même moment de la boucle : les prix n'ont pas besoin de suivre A. La condition qui monte de 5 compense la vitesse gagnée. Cible : une Ascension tous les 5 à 9 jours pour le joueur de référence après la première.

**Le moment, étape par étape**
1. Quand r atteint la condition, l'**Observatoire** sur la colline nord braque son faisceau vers le ranch et la puce Menu affiche « Jelly Ascend ! ».
2. **Aperçu** (plein panneau) : 3 tuiles de 400 × 300 « Tu gagnes » (« Croissance ×3 pour toujours », « Halo : 1 goutte », « Ciel : Nuage-coussin ») ; une ligne claire en 40 px : « Tes Grands Splorch recommencent au début (tu es au XV). **Tout le reste est gardé.** », suivie de 6 icônes (squishies, Confettis, Atelier, Plopettes, paliers, Squishydex) ; la condition avec sa barre (« Grand Splorch XV / XV ✓ »).
3. **Maintien de ✕ pendant 3 s** (anneau autour d'un glyphe de 64 px), puis une carte « Prêt à monter ? » avec 2 gros boutons de 360 × 112 : « Oui, Ascension ! » et « Plus tard », **focus d'office sur « Plus tard »**, garde d'entrée de 0,6 s (boutons grisés), fermée sans rien changer après 20 s.
4. **File** : la même que le Grand Splorch (c'est un grand spectacle). Un joueur n'a jamais qu'**un seul prestige** dans la file (« Ton Grand Splorch passe d'abord ! »).
5. **Spectacle de 10 s** (coupure dure à 12 s) : le faisceau se pose sur le ranch, l'élément de ciel se construit pièce par pièce au-dessus, le Meilleur Ami n° 1 monte dans le faisceau, éclat de lumière, « JELLY ASCEND ✦1 », il redescend avec le halo, « ×3 pour toujours ! ». Le profil change **d'un seul bloc à 4,0 s**, puis il est sauvegardé tout de suite.
6. **Pour les autres joueurs** : « Pluie d'étoiles » (décor) qui donne 120 s de leur revenu (3 par jour au plus) et un bébé de l'espèce du Meilleur Ami (dans les 10 bébés de cadeau par jour du GDD).

**Le halo** : de 1 à 5 petites gouttes de gelée qui tournent autour de la tête (menthe, ciel, lilas, or, arc-en-ciel à 5 et plus). **Le nombre de gouttes porte l'information**, lisible sans les couleurs ; « ✦3 » sur la plaque du nom ; réglage « Montrer mon halo » (activé par défaut) ; immobile en Mouvement réduit. Gagné, jamais vendu (le halo de l'Ascension de Sell Lemons [08-46] ; à l'inverse, Clean the Squishies vend une aura à +200 % de revenu pour 999 R$, 2026, confiance faible).

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
| 7,5 → 11,5 s | **Chantier de Big Plop**, seulement si un élément nouveau arrive dans le ranch : un petit Big Plop casqué donne 3 coups de maillet, la pièce se construit en cascade, étiquette « Nouveau : Phare de gelée ! » 3 s. **Non bloquant** : le joueur marche pendant ce temps ; la caméra ne bouge jamais seule (flèche de bord si l'objet est hors champ) | Client |
| après | Carte non bloquante « Nouveau : … » (8 s, puis rangée dans la pastille « ! ») | Client |

### 3.7 États et délais ajoutés (module `StateTimeouts`)

| État | Délai | Sortie |
|---|---|---|
| Maintien ×10 / Max ou d'une ligne de l'Atelier | 0,6 s | Achat, ou annulation sans rien dépenser |
| Réponse du serveur à un achat | **3 s** | Ligne remise à l'état du serveur, « Réessaie » |
| Petit Splorch (animation locale) | 2,5 s, coupure dure à 4 s | État final posé |
| Maintien de l'Ascension | 3 s | Carte de confirmation |
| Carte « Prêt à monter ? » | 20 s | Fermée, rien ne change |
| File (Ascension) | Comme le Grand Splorch (coupure à 8 min) ; départ du joueur | Spectacle, ou place rendue **sans rien remettre à zéro** |
| Spectacle de l'Ascension | 10 s, coupure dure à 12 s | Fin, file suivante |
| Chantier de Big Plop | 4 s, coupure dure à 6 s | Élément posé ; carte si interrompu |
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
| Ombre (`UIShadow`, en ligne depuis le 23/06/2026 [08-92]) | 6 px TV vers le bas, douce, 50 % d'opacité, bleu nuit |
| Bouton principal | Dégradé (255, 170, 210) → (235, 110, 170) |
| Bouton secondaire | Dégradé (150, 235, 200) → (80, 200, 160) |
| Bouton impossible | Dégradé (180, 180, 195) → (140, 140, 160) + icône et mot de la raison |
| Fond de panneau | Bleu nuit (30, 25, 60) à 85 %, dégradé vers (60, 45, 110) |
| Révélations, anneaux de rareté, titre du Grand Splorch | Dégradé **radial** (sorti pour tous : sujet « [Full Release] Upgraded UI Gradients » vu en extrait de recherche le 01/11/2026 [W1], date exacte incertaine) |
| Polices | FredokaOne (texte), LuckiestGuy (tampons) |
| Focus | Cadre blanc de 6 px + 2 px sombres, respiration 1,2 s |
| Suffixes des nombres | K-M blanc, B-T or (255, 215, 90), Qa-Qi rose (255, 150, 200), Sx et au-delà cyan (120, 230, 255) |

  Si `UIShadow` ou le dégradé radial manquent sur un appareil, repli automatique sur l'aplat (sous `pcall`, compté dans Diagnostics, jamais une erreur). Test statique : aucune couleur ni rayon écrit en dur dans `UI/*` hors de la feuille de style.
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

Au-delà de 140 studs : un niveau de détail de 6 pièces (tour, phare, couronne). **Aucune lumière de plus** : le phare de **son** ranch prend une des 4 lumières du ranch local du GDD ; ceux des voisins restent en `Neon` (correction du plan Spectacle : le budget de 24 lumières du GDD §12.9 est déjà plein). Règle de placement (`WorldLayout.spec`) : au moins 6 studs de toute dalle, rien dans les enclos ni sur le chemin du portail, **rien au-dessus de Y = 21 au centre du ranch** (la silhouette du meilleur squishy, jusqu'à Ø 38 studs à Y = 40, ne traverse rien).

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
- **Monuments** derrière le fond du ranch (r de 256 à 310 studs, hors de la Prairie des copains au nord, `WorldLayout.spec`) : 20 pièces au plus pour son ranch, 6 pour les 2 voisins, 1 silhouette au-delà de 140 studs.
- **Déco perso** (janvier) : 12 emplacements fixes (8 petits, 4 grands), choisis sur un **plan du ranch vu du dessus** dans le menu (jamais en visant au stick) ; 40 objets gagnés (Squishydex, jours de Plop, objectifs, Jelly Moon, piste de la semaine), jamais au hasard ni en Robux. Au lancement, seul le **Fanion à ton nom** (offert à 5:00), posé sur un emplacement fixe.

### 4.3 Thèmes : habillages et costumes

**Habillages de ranch** (2 janvier ; donnés tout de suite à qui a déjà le Record R ou l'Ascension) : couleur, matériaux de la clôture, du sol et du portail. 14 en tout : les 3 du GDD (couleur du ranch, Moonlit, Candy Night) + Guimauve (R1), Caramel (R3), Menthe glacée (R5), Phare (R10), Glacier sucré (R12), Néon (R15), Cosmos sucré (R17), Royal (R20), Nuage (A1), Aurore (A3), Céleste (A5). Gagnés, jamais au hasard, jamais en Robux. Un habillage = une ligne de données appliquée par le client à des pièces qui existent déjà ; le serveur garde un identifiant (`ranchSkin`), validé contre la liste gagnée ; inconnu au chargement → habillage par défaut, compté dans Diagnostics. Menu → Ranch → onglet *Mon style* (qui remplace l'onglet *Dalles*).

**Kit de costume de saison** (une ligne de données `Events.Costumes`, champ déjà prévu au GDD §17.2) : `dates` (UTC), `theme` (≤ 12 jetons de la feuille de style), `lighting` (1 préréglage), `decorSet` (≤ 300 pièces dessinées par le client), `particles` (≤ 20 par seconde), `bigPlop` (≤ 3 pièces), `music` (sons officiels seulement), `featured` (une récompense vedette **gagnée**). Le costume actif est une fonction pure de la date ; deux costumes ne se recouvrent jamais (test).

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
| **2. Achat groupé** | ×10, Max | **Un seul** retour : les cascades se suivent, 1,2 s au total ; « +7 niveaux · −1,2 M » ; 24 vermicelles | `TileBuild` une fois puis `Coin` à l'envers ; `uiConfirm` | Fondu / 8 vermicelles |
| **3. Palier** | Nouveau palier nommé, 10e et 18e place, décoration dorée | 2,5 s : bannière **personnelle** « PALIER ! Bonbon arc-en-ciel » (48 px) ; anneau `Neon` de 0 à 40 studs en 0,6 s ; 30 confettis ; **la ola** des squishies, colonne par colonne | `LevelUp` ; vibration nouvelle `tierUp` (force 0,4, 0,35 s) | Sans ola ni anneau / 10 confettis |

- **Achats faits depuis l'écran** : le joueur ne voit pas le ranch quand un panneau est ouvert ; les cascades attendent la **fermeture du panneau** et se jouent alors, groupées. File de **10 constructions ou 10 s au plus** ; au-delà, l'état final est posé sans animation. Un objet hors de vue (plus de 140 studs, derrière la caméra) n'est pas animé : il est simplement là.
- **Chantier de Big Plop** : voir §3.6. **Socle → décoration** : le socle rétrécit (0,2 s), la décoration sort en cascade.
- Le texte groupé vient de **la réponse du serveur** (niveaux réellement achetés, pièces réellement dépensées), jamais d'un calcul du client.

### 4.5 Des squishies qui ont du caractère

**Six personnalités** (colonne `perso` de `Config/Species` ; une espèce nouvelle reçoit la sienne dans sa ligne de données, sans code)

| Personnalité | Espèces | Saynète 1 | Saynète 2 | Saynète 3 |
|---|---|---|---|---|
| **Curieux** | Plop, Whiskerwob, Lotlolly, Moonhop, Moonplop | « Coucou » : se penche vers le joueur (1,5 s) | « Tour de place » : petit cercle de 1,5 stud (3 s) | « C'est quoi ? » : regarde la dernière décoration construite, « ? » au-dessus (2 s) |
| **Dormeur** | Wibble, Purrpudding, Lilypuff, Hopscotch | « Bâillement » (2 s) | « Mini-sieste », bulle « z » (3 s) | « Réveil en sursaut » (1 s) |
| **Rebondi** | Ribbit Drop, Boingtoad, Clover Hop, Nubbin | « Triple saut » de 1,5 stud (1,8 s) | « Toupie » : 2 tours (1 s) | « Plat ! » : saut de 3 studs et écrasement ×1,5 (1,5 s) |
| **Câlin** | Mochi Mew, Frillo, Bunbun, Prickle Puff | « Cœurs » : 3 cœurs si le joueur est à 8 studs ou moins (2 s) | « Bisou au voisin » (2 s) | « Dandinement » : ±10° à 2 Hz (2 s) |
| **Farceur** | Jiggleberry, Croakaroo, Gillygum, Drago Drop | « Langue » : clin d'œil (1,5 s) | « Faux éternuement » : inspire… rien, puis rit (2,5 s ; jamais le texte « ATCHOUM », réservé au Rush) | « Cache-cache » : s'aplatit puis ressort (2 s) |
| **Fier** | Grand Gloop, Blossompurr, Coralotl, Emberwob, Royal Plop | « Pose » : gonfle à 1,08, 2 étoiles (2 s) | « Révérence » (1,5 s) | « Défilé » : avance de 1,5 stud et revient (3 s) |

« Fier » est réservé aux Légendaires, Mythiques et Secrets : un petit signe de rareté de plus. Règles : une saynète toutes les **8 à 20 s** par squishy à 40 studs de la caméra ou moins ; **6 au plus en même temps** (3 en qualité réduite), les plus proches d'abord ; jamais pendant un portage, une fusion, un Rush à la clôture ou un grand spectacle ; une pression ou un ciblage l'arrête tout de suite. **Jamais à plus de 2 studs de sa place** (le serveur mesure les portées depuis la place, GDD §4.7). **Aucune pièce en plus** : on déplace les pièces existantes ; les icônes viennent de la réserve commune de `BillboardGui`. **Aucun trafic réseau.**

**Six visages** faits avec les pièces existantes : Content (défaut), **Ravi** (yeux en arc « ^ ^ »), **Surpris** (yeux ×1,2, bouche ronde), **Endormi**, **Étoilé** (reflets ×1,6 en `Neon`), **Boudeur** (visage du Flop). **Réactions** : achat dans le ranch (tous se tournent, Ravi, petit saut ; une fois toutes les 2 s au plus) ; série PERFECT ×5 (Ravi) ; sirène du Rush (Surpris) ; MEGA qui atterrit à 120 studs ou moins (Surpris) ; Grand Splorch d'un autre (Étoilé, regardent la place) ; début de la Jelly Moon (Étoilé, regardent la lune) ; retour du joueur après 60 s dehors (le Meilleur Ami : Ravi + 3 cœurs) ; joueur immobile 60 s (ceux à 15 studs s'endorment). Un visage revient toujours à « Content » à la fin de sa durée, même si l'événement de fin manque.

**Cinq tours appris en grandissant** (9 janvier) : chaque espèce apprend un tour quand son record de taille passe 100 (« Coucou »), 1 200 (« Toupie »), 1 million (« Salto »), 1 milliard (« Danse »), 1e12 (« Feu d'artifice »), comme les tours par âge d'Adopt Me (wiki, non daté). Le Meilleur Ami fait son plus beau tour quand le joueur joue l'emote « Bravo » (aucun message réseau de plus : l'emote est déjà répliquée).

**Des événements relookés pour la télé** (lancement) : le géant du MEGA a des expressions ; une **lune de gelée** de 80 studs (4 pièces) ouvre les yeux au début de chaque Jelly Moon et fait un clin d'œil par minute ; le Golden Wobbler laisse des **traces dorées** (6 empreintes qui rétrécissent) qu'on suit à l'œil sur une télé ; les lampadaires passent une fois au rose à la sirène du Rush (aucun clignotement). Ballons de la Wobble Party : janvier.

### 4.6 Budgets des effets (console la plus faible : PS4 et Xbox One, GDD §12.9)

Tout ce plan est **dessiné par le client** à partir d'attributs répliqués : rien ne compte dans le plafond de 4 500 pièces de la carte (GDD §11.4) ; tout compte dans les 15 000 instances d'un client.

| Ajout | Pièces au pire cas sur un client | Particules | Lumières | `Highlight` | Transparence | Quand |
|---|---|---|---|---|---|---|
| Tapis, coussins, lit (son ranch + 2 plus proches ; couleur seulement pour les autres) | (20 + 24 + 10) × 3 = 162 | ≤ 6 | 0 | 0 | 0 | Lancement |
| Changements par R : Cuve, Pot, Bassin, lampions, portail… (idem) | ≤ 40 × 3 = 120 | 0 | 0 | 0 | 0 | Lancement |
| Paliers de ranch | ≤ 405 (3 ranchs proches × 96 + 13 lointains × 9) | 0 | 0 de plus | 0 | 0 | Lancement |
| Socles de souvenir | 18 × 2 × 3 = 108 | 0 | 0 | 0 | 0 | Lancement |
| Monuments (4, puis 10) | 4 : 80 + 48 + 52 = 180 ; 10 : 200 + 120 + 130 = 450 | 0 | 0 | 0 | 0 | Lancement / janvier |
| Personnalités, visages, tours | **0** (pièces existantes) | ≤ 20 | 0 | 0 | 0 | Lancement / janvier |
| Événements (lune, traces, ballons) | ≤ 26 | 0 de plus | 0 | 0 | 0 | Lancement |
| Costume d'hiver | ≤ 300 | 10 par seconde (GDD) | 0 | 0 | 0 | Lancement |
| Plopettes (≤ 5 pièces ; détail complet à 140 studs ou moins) | ≤ 170 | 0 | 0 | 0 | 0 | 19 décembre / janvier |
| Halo et ciel | ≤ 80 + ≤ 10 près, 3 loin | 0 | 0 | 0 | 0 | 26 décembre |
| Déco perso | 3 × 120 + 13 × 4 = 412 | 0 | 0 | 0 | 0 | Janvier |
| Météo, place en fête | ≤ 84 (temporaire) + ≤ 80 | ≤ 60 (remplace les flocons) + ≤ 40 pendant 3 s | 0 | 0 | 0 | Fin janvier |
| **Total au lancement** | **≈ 1 300** | **≤ 200 avec le reste du jeu** | **0 de plus** | **0 de plus** | **0 de plus** | |
| **Total à la fin janvier** | **≈ 2 450** | idem (arbitré par le budget en direct) | 0 | 0 | 0 | |

Marge (inférence, à mesurer) : 15 000 − 4 300 (carte) − 2 500 (pièces des squishies) ≈ 8 200 instances pour tout le reste. **Budget visuel en direct** (`Render/VisualBudget`) : chaque système déclare ses pièces, particules et lumières ; au-delà, il **dégrade** dans un ordre fixe (ranchs les plus lointains d'abord, son propre ranch en dernier) ; un dépassement n'est jamais une erreur, seulement un compteur de Diagnostics. Mesure obligatoire sur une vraie PS4 ou Xbox One avec 16 joueurs (test M6 du GDD).

**Trois versions de chaque effet** : normale, Mouvement réduit (pas de déplacement d'interface, pas de secousse, pas de flash, amplitudes ×0,5, 3 changements de couleur par seconde au plus) et Graphismes légers (particules ×0,3, détail réduit). **Aucune transparence de plus** (réservée à la gelée, aux portails, au Bassin et à la Cuve). **Aucune lumière ni `Highlight` de plus.** **Un seul grand spectacle à la fois** : les moments nouveaux sont locaux ou d'ambiance et se taisent pendant un Rush, un MEGA, un Grand Splorch ou la danse de Big Plop.

**Captures de référence** (outil Screens ; 3 résolutions, 2 langues pour ce qui a du texte, qualité normale et réduite) : ranch aux Record R 0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13, 15, 16, 17, 19, 20, 25 ; 7 paliers du Tapis ; 3 paliers d'enclos ; **6 visages × 6 familles** (une espèce par famille, plus Lilypuff, la plus plate) au lieu de 6 × 26 ; chaque phase des événements ; costume d'hiver ; écrans d'amélioration (§2.3). Matrice volontairement réduite (remarque du jury sur la taille de la matrice du plan Spectacle).

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
| Atelier de lancement complet | ≈ jour 28 (cible) |
| Atelier et cosmétiques complets (1 552 Confettis) | Plusieurs mois (cible) |
| 10 Monuments | Record R 24 |
| Tapis Étoilé 20 | Chaque boucle à r ≥ 16 |
| Jelly Ascend 1 à 5 (halo complet), puis 10 (Constellation) | A1 vers le jour 14, puis tous les 5 à 9 jours (cible) |
| Titres de Record R tous les 5, puis tous les 10 à l'infini | En données |
| Carnet 2 500, 5 000, 10 000 | Fidèles |
| Maîtrises (26 et plus) | Des mois |
| Squishy-Soleil (1e21) | Plusieurs mois (inférence d'après les objectifs du GDD) |
| Livre des records (janvier) | Lecture seule : plus gros squishy, meilleur combo, Grands Splorch, Ascensions, Record R, Confettis gagnés, maîtrises, jours de Plop, cœurs reçus |

### 5.5 Le contenu de chaque semaine

- **Chaque samedi** : une espèce nouvelle (GDD §7.6) **et** un ajout de renaissance ou de décor publié en données, avec une date d'activation (champ `release`) : on publie en avance, sans nouvelle version. Steal An Egg tient ce rythme depuis sa sortie : environ 10 mises à jour numérotées en ≈ 14 semaines (fin octobre 2026 [08-112][08-113]), puis un biome « Alien » annoncé du 07/11 au 14/11/2026 [W2].
- **Piste de la semaine** (2 janvier) : gratuite, **12 paliers**, toutes les récompenses visibles d'avance ; 1 point par objectif du jour terminé (3 par jour au plus), 4 points par Défi de Splorch, 1 palier = 2 points ; 24 points sur 33 possibles (≈ 4 à 5 séances de 30 min, cible). Remise à zéro le lundi à 00:00 UTC ; paliers **réclamés tout seuls** ; un Défi en cours reste jusqu'à la fin de la session.

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
| **5 min** | R0 ; Tapis niv. 5 « Biscuit sablé », bâti en cascade ; 8 décorations ; Enclos niv. 1 ; 4 squishies, 1 fusion, 1-2 captures ; première balade à 4:26 ; premières saynètes de Plop ; Fanion à son nom | Pareil (accueil identique) | Dalle Enclos ; suivi « Grand Splorch 12K / 15K » ; premier Grand Splorch vers 12,6 min | Mesuré (GDD, prototype) ; décor : cible |
| **30 min** | R2 ; Arche à pompons ; Pot argent ; 1 place offerte ; Atelier ouvert, 9 Confettis, 1-2 lignes achetées ; Gants niv. 13 « À pois » (×1,325) ; Enclos 12 ; 20 squishies ; 18 tampons | Pareil | Tour à bonbons et Lit douillet (R3) ; famille Bunny | R, Gants, Enclos, squishies, tampons : mesurés (prototype avec Plopettes) |
| **2 h de jeu** | ≈ fin du jour 4 : R6 ; paliers 1-3 ; Pot doré ; Gants 25 ; Tapis 11 ; 18 décorations ; Enclos au maximum ; 2 places offertes ; Atelier : Cadeau 3 et Tapis de départ 1 ; Monument 1 ouvert (1,69 T) ; 59 squishies | Fin du jour 1 : R5-6 ; Gants 22 | Cuve dorée (R7) ; Monument 1 ; 3 décorations gardées (R8) | Mesuré (prototype) ; Confettis : calculés |
| **1 jour** | Fin du jour 1 : R2 (35 min de jeu), 9 Confettis | R5-6, 30 à 39 Confettis | — | Mesuré (R) |
| **1 semaine** | R10 : Phare de gelée, Cuve dorée, Bassin-fontaine, 3 décorations gardées, 2 Monuments, 85 Confettis, Tapis Étoilé 13-14 ouvert, 3e Meilleur Ami, ≈ 93 tampons, ≈ 650 niveaux au Carnet | R15 : Dôme néon, ≈ 5 Monuments (si publiés), premier 1e12 vers le jour 12 ; **1re Jelly Ascend** (si allumée) | Château de Pudding (R12) ; Tapis Étoilé 15-16 ; Jelly Ascend à R15 | R, tampons, Monuments, R de l'assidu : mesurés ; Carnet : inférence ; Ascension : cible |
| **2 semaines** | R15 : Dôme néon, 6 décorations gardées, 165 Confettis ; **1re Jelly Ascend** (cible : jour 14, 12-16) | A ≈ 2 (cible) | Halo, ciel, Tremplin | R : mesuré ; reste : cible |
| **1 mois** | Sans Ascension : R20, Couronne flottante, 7 Monuments, 270 Confettis + piste, premier 1e12 vers le jour 26, 131 tampons, ≈ 1 400 niveaux au Carnet. Avec Ascension : A = 2 à 3, Record R ≈ 20-22, Atelier de lancement fini | Sans Ascension : R27, **contenu épuisé** (mesuré). Avec : A ≈ 4 à 6 | Monuments 9-10 ; Maîtrise (février) ; Carnet 2 500 | Sans Ascension : mesuré ; avec : cible |

**Ce que la mesure montre** (prototype du 01/11/2026, 50 joueurs de référence, 28 jours, serveurs de 4, 8 et 16) : 48 à 79 achats par boucle au lieu de 28 à 30 ; plus long moment sans achat **≤ 2,7 min** (médiane) de R0 à R13 ; temps de jeu à plus de 3 min d'un achat ou d'un Grand Splorch : **1,0 %** (jours 2-7, contre 24,3 %), **7,8 %** (jours 8-14, contre 40,3 %), **33,8 %** (jours 15-28, contre 66,3 %). Jalons inchangés. **La fin de mois reste creuse** sans la Jelly Ascend (33,8 % ; 70 % pour l'assidu) : c'est la raison chiffrée de l'allumer pendant les vacances.

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

La porte `EconomyPacing` (GDD §4.24) est **bloquante**. Elle rejoue le joueur de référence avec les formules du jeu, aux **3 tailles de serveur (4, 8, 16)** et avec les **2 politiques d'achat** (« le moins cher d'abord », celle du GDD, et « Conseillé », celle de l'écran). Elle tourne dans `./scripts/check.sh` sur la **configuration du lancement** (sans Plopettes, sans Ascension), et chaque nuit sur les autres configurations : avec Plopettes, avec Ascension, joueur assidu, gros acheteur (200 joueurs avant chaque version).

| Clé | Mesure | Tolérance | Prototype |
|---|---|---|---|
| (toutes celles du GDD §4.24) | Premier Grand Splorch, R à 30 min, R aux jours 7 / 14 / 28, tampons, part des pressions, temps en ×2… | Inchangées | Toutes tenues |
| `starvedDay1` | Part du temps de jeu à plus de 3 min d'un achat ou d'un Grand Splorch, jour 1 | ≤ 1 % | 0,0 % |
| `starvedDay2to7` | Idem, jours 2-7 | ≤ 5 % | 1,0 % |
| `starvedDay8to14` | Idem, jours 8-14 | ≤ 15 % | 7,8 % |
| `starvedDay15to28` | Idem, jours 15-28 | ≤ 40 % sans Ascension ; **≤ 20 % avec** | 33,8 % ; avec : non mesuré |
| `loopMaxGapR0to13` | Plus long moment sans achat d'une boucle, médiane, R0 à R13 | ≤ 3 min | ≤ 2,7 min |
| `coinsLostRatio` | Pièces perdues au Grand Splorch / T12 (remplace « ≈ 3 » du GDD) | 0,2 à 3 | 0,54 |
| `tapis12LoopShare` | Moment de la boucle où le Tapis 12 est atteint | ≥ 0,5 | 0,99 |
| `helperShareDay7` | Part des Plopettes dans les pièces gagnées en jeu, jour 7 (configuration avec Plopettes) | 5 à 15 % | 9 % |
| `firstWorkshopBuy` | Premier achat à l'Atelier | ≤ 35 min | (cible : 13 min) |
| `workshopLaunchDoneDay` | Lignes de lancement de l'Atelier toutes achetées | Jour 24 à 35 | (cible : 28) |
| `monumentsDay7` / `Day28` | Monuments construits | 1-3 / ≥ 4 | 2 / 7 |
| `ascend1Day` | 1re Ascension (référence / assidu) | 12-16 / 6-9 | Non mesuré |
| `ascendGapDays` | Jours entre deux Ascensions (référence) | 5-9 | Non mesuré |
| `regainRatio` | Temps pour revenir au Record R après une Ascension / temps de la première fois | 0,20-0,55 | Non mesuré |
| `shortestLoopSec` | Boucle la plus courte après une Ascension | ≥ 45 s (cible 60) | Non mesuré |
| `queueWaitNewcomer` | Robots : serveur de 16 dont 8 vétérans après une Ascension ; attente médiane du premier Grand Splorch d'un nouveau joueur | ≤ 40 s | Non mesuré |
| `spenderLead` | Gros acheteur : avance au jour 28 | ≤ 2 R et ≤ 1 Ascension | 2 R |

**Les hypothèses écrites, une par une**
- **H1** — Les familles de pièces (Gants, École, Monuments) ne bougent pas les jalons. *Mesuré avec Plopettes.*
- **H2** — **Sans Plopettes** (lancement), Gants + Tapis Étoilé + Monuments suffisent à tenir `starvedDay2to7` ≤ 5 % et `starvedDay8to14` ≤ 15 %. *Non mesuré.* Si la porte échoue : Gants à 40 niveaux (variante mesurée avec l'École : 6,2 % / 29,7 %) ou Plopettes au lancement.
- **H3** — L'Aimant, le Sac de nuit et le Pot de nuit ne bougent pas les jalons. *Non modélisés.* Le Sac de nuit allonge la croissance hors ligne (le joueur de référence dort 16 h, au-delà de la limite de 8 h) : vérifier « Grands Splorch prêts à la connexion » (médiane 0 %, au plus 50 %) et R au jour 7. Si la porte échoue, le Sac de nuit ne compte plus que pour les pièces du Pot.
- **H4** — Les décorations gardées et le Tapis de départ accélèrent seulement le début des boucles. *Mesuré pour le Tapis de départ 1-3 ; pas pour les décorations gardées.*
- **H5** — Ascension : ×3, `StartR`, Tremplin et condition +5 donnent une Ascension tous les 5 à 9 jours et un retour au record en 20-55 % du temps. *Cible.*
- **H6** — Le prix corrigé des Monuments ne permet pas d'en acheter plus de 2 par boucle juste après une Ascension. *Cible.*
- **H7** — Le Petit Splorch garde la file du serveur libre (`queueWaitNewcomer`). *Robots.*
- **H8** — La piste de la semaine (34 Confettis) ne finit pas l'Atelier de lancement avant le jour 24. *Calcul : 270 + 4 × 34 ≈ 406 Confettis au jour 28 pour 342.*
- **H9** — La météo (fin janvier) garde les tampons du jour 7 dans 80-110. *À simuler avant l'allumage.*

**Leviers sans code** : `Balance.Tiles.*`, `Config/Upgrades` (prix, niveaux, ouvertures), `Balance.Confetti.PerSplorch` (3 + r), `Balance.Ascend.*` (`ReqR`, `GrowthMult`, `StartR`), `Balance.Splorch.BeyondMult` (2,6), `Balance.Caps.fameSplorch`, `Events.Weather.*`, interrupteurs `Features.*`.

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
| §4.3 Formules | ×3^A ; Tapis jusqu'à 20 ; Gants et Super Série dans la pression ; Monuments dans `A_bonus` ; renommer l'additif « A » en `A_bonus` |
| §4.6 Dalles | Catalogue complet (§2.1) ; valeurs du code (×4,5) ; paliers nommés ; coussins, lit à baldaquin, socles ; décorations gardées ; places offertes ; onglet *Dalles* remplacé par l'écran Améliorations |
| §4.7 Presser | Formule avec Gants et Super Série |
| §4.8 Pot | Tas en 4 états ; matériau selon le Record R ; Aimant |
| §4.9 Cuve | Anneaux, agitateur, buses visibles ; lit le Record R |
| §4.14 Enclos | Places offertes aux R2, R6, R11, R16 (+25 Confettis si plein) |
| §4.15 Grand Splorch | Tuile « Croissance ×2 » (sans « pour toujours ») ; 3e tuile « +n Confettis » ; table R1-R40 ; cadeau du Splorch ; Petit Splorch ; bannière une fois par 3 min et par joueur ; Chantier non bloquant |
| §4.17, §7.4 | Tout « dès R = x » lit le Record R |
| §4.19 Hors ligne | Sac de nuit et Pot de nuit |
| §4.24 Simulation | Portes du §6.3 ; 2 politiques ; configurations |
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
| §10.1 Style | Feuille de style unique, jetons du §4.1, `UIShadow`, dégradés radiaux avec repli ; tailles de police fixes là où il y a des nombres |
| §10.2 HUD | Puce « Prochain achat » à (96, 342) ; rail du menu en boutons de 88 px |
| §10.3 Écrans | Écran Améliorations ; aperçu de l'Ascension et sa carte ; onglet *Mon style* du panneau Ranch |
| §10.4 Commandes | U au clavier ; □ = mode dans l'écran |
| §10.5 Vibrations | `tierUp`, `chantier` |
| §10.6 Navigation | Sélection d'office du menu ; ordre fixe des lignes |
| §11.2 Ranch | Positions des paliers, du ciel, des Monuments, de la maisonnette des Plopettes, des 12 emplacements de Déco perso ; règle « rien au-dessus de Y = 21 au centre » |
| §11.3 Éclairage | `LightingStyle = Soft` ; Directeur d'ambiance ; `default.project.json` et sa spec mis à jour ensemble |
| §12.6 Schéma | Champs du §7.3 |
| §12.7 Messages | Intentions du §7.4 |
| §12.9 Budgets | Lignes du §4.6 ; phare sans lumière de plus |
| §12.10 Qualité | États du §3.7 ; règles du §2.3 ; tests du §7.6 |
| §12.12 Lignes | Lignes de ce plan et ligne de coupe du §8 |
| §16 Analytique | Événements du §7.5 |
| §17 Lancement et plus tard | Découpage du §8 ; Jelly Ascend à r ≥ 15 (au lieu de « après 10 Grands Splorch »), allumée le 26 décembre ; « saison de 28 jours » = 4 pistes de la semaine |
| §18 Checklist | M14 avec l'écran Améliorations (« Léa comprend-elle Max ? ») ; M6 avec les nouveaux décors |
| §19 Risques | Risques du §7.6 |

### 7.2 Modules nouveaux

| Module | Où | Rôle | Tests |
|---|---|---|---|
| `Logic/UpgradeMath` | Shared (pur) | Prix d'un niveau, de n niveaux, maximum payable, effet à un niveau, palier ; pièces **et** Confettis ; prix des Monuments | Propriétés : `bulk(n)` = somme ; monotone ; jamais `NaN` ; plafonds par r |
| `Logic/UpgradeAdvisor` | Shared (pur) | Conseillé, prochain achat | Déterministe ; jamais 2 cartes d'une famille ; jamais une carte vide |
| `Logic/Prestige` | Shared (pur) | **Seule source** de r, Record R, A ; `growthFactor`, `target`, `isRecordSplorch`, `ascendReady`, `startR`, `confettiGain`, `grantRecord`, **`apply(profile, genre, now)`** (genre = « splorch » ou « ascend ») | Propriétés sur des milliers de profils (squishies jamais perdus ; Record R, Confettis, A, Atelier jamais en baisse ; seuls les champs « repart de zéro » changent) ; **test statique : aucune lecture de `profile.R` hors de `Prestige` et de `Schema`** |
| `Logic/TierRules`, `Logic/RanchLook` | Shared (pur) | Palier d'une famille à un niveau ; éléments du ranch pour un Record R | Chaque niveau a un palier ; chaque R1-R20 a un élément visible ; mêmes entrées = même sortie |
| `Logic/AmbienceRules` | Shared (pur) | Pile d'ambiance | Toute combinaison donne une seule réponse |
| `Config/Upgrades` | Shared | Familles, lignes de l'Atelier, onglets, ordre, paliers, ouvertures, clés de texte ; identifiants définitifs (on ajoute à la fin, jamais de réordonnancement) | Coûts strictement croissants ; aucun champ de probabilité (test de schéma) |
| `Config/Visuals` | Shared | `RanchByRecordR`, paliers, visages, yeux, palettes | Clés EN et FR |
| `UI/UpgradeCard`, `UI/Panels/Upgrades`, puce du HUD | Client | Écran et carte unique | Règles du §2.3 |
| `Render/BuildCascade`, rendu des paliers dans `RanchRenderer` | Client | Cascade ; décors du ranch à partir des attributs `BestR`, `Ascend`, `SplorchReady` | Idempotent ; interruption → mêmes `CFrame` finaux ; instances stables |
| `Render/AmbienceDirector` (dans `LightingController`) | Client | Seul possesseur de `Lighting` | Une écriture par changement |
| `Render/VisualBudget` | Client | Budgets et dégradation | Jamais dépassé sur 6 h de robots |
| Personnalités et visages (dans le rendu des squishies) | Client | Saynètes, visages, réactions | Déplacement ≤ 2 studs ; retour à « Content » |
| `EconomyService` (étendu) | Serveur | `buyUpgrade` pièces et Confettis | Attaques du §7.6 |
| `SplorchService` (étendu) | Serveur | `Prestige.apply`, Petit Splorch, Ascension dans la file | Contre-audit du §7.6 |
| `HelperService` (19 décembre) | Serveur | Plopettes à 10 Hz | Règle des 12 studs, sieste, pause |
| `QuestService` (étendu, 2 janvier) | Serveur | Piste de la semaine, Défis, Carnet | Changement de semaine à 23:59:59 / 00:00:00 UTC et en fin d'année |

### 7.3 Données (schéma v1, tous les champs ajoutés **avant** le lancement)

Ajoutés par `reconcile` avec leur valeur par défaut, même pour les fonctions allumées plus tard : **aucune migration en janvier**. `bestR` (≥ r), `ascend` (le champ réservé du GDD devient A), `confetti` et `confettiTotal` (entiers de 0 à 1e9), `tiles.gloves`, `tiles.school` (le Tapis Étoilé réutilise `tiles.snack` jusqu'à 20), `monuments` (bits), `atelier` (tableau dense d'un niveau par ligne, borné par le maximum de la ligne), `stats.upgradesBought`, `carnet` (bits réclamés), `weeklyTrack = { week, points, claimed, quests }`, `ranchSkin`, `settings.haloOn`, `decorBuilds` (18 petits entiers bornés à 10), `decoPerso = { owned (64 bits), slots (12) }`, `hearts = { givenDay, givenTo (20 au plus), receivedTotal }`, `mastery` (bit par espèce), `season.frostDays`. `Contract.spec` : un profil plein reste identique après `JSONEncode` / `JSONDecode` et pèse moins de 20 Ko.

### 7.4 Messages réseau

| Intention (client → serveur) | Contenu | Règles du serveur |
|---|---|---|
| `BuyUpgrade` | `id`, `mode` (1, 10 ou « max »), `expectedLevel` | Famille connue et ouverte ; niveau actuel = `expectedLevel` (sinon refus « périmé », l'écran se remet à jour) ; `n = min(demandé, payable, restant)` ; somme exacte niveau par niveau ; un seul bloc ; seau à jetons de 10 par seconde ; refus pendant l'application d'un prestige |
| `BuyTile` (GDD) | Inchangé pour les dalles au sol ; même fonction serveur et même `UpgradeMath` | — |
| `JellyAscend` | `confirm` | `ascendReady` ; un seul prestige par joueur dans la file ; conditions vérifiées à l'entrée seulement |
| `SetRanchSkin`, `PlaceDeco` (janvier), `GiveHeart` (février) | Identifiant, emplacement et niveau attendu, ranch | Validés contre ce qui est gagné ; réponse attendue en 3 s côté client |

Réponses (serveur → client) : `UpgradeResult { id, from, to, spent, currency, reason }` ; `HelperPress { helper, uid, t }` regroupé par tick (Plopettes). Attributs répliqués du ranch : `BestR`, `Ascend`, `SplorchReady`.

### 7.5 Analytique

`Upgrade_<famille>` (cumulé), `UpgradeMode` (×1 / ×10 / Max), `WorkshopBuy_<ligne>`, `ConfettiEarned(source, n)`, `UpgradeTimeout`, `NextGoalGap` (histogramme serveur du temps depuis le dernier achat), `HelperCoinsShare`, `RanchTierReached(tier)`, `AscendPreview(opened | cancelled | confirmed)`, `AscendDone(A, r, daysSinceLast)`, `PetitSplorch`, `WeeklyTrackTier(tier)`. Alerte : si la médiane de la 1re Ascension sort de 10-18 jours, régler `ReqR` par configuration.

### 7.6 Risques, parades et notes « zéro bug »

| Risque | Parade |
|---|---|
| **Calendrier trop chargé** (le jeu de base du GDD est encore en fabrication) | 3 voies en parallèle, revue le jeudi 3 décembre, ligne de coupe du §8, date de repli du GDD (samedi 9 janvier 2027) |
| **Rythme cassé** par une partie non mesurée (configuration sans Plopettes, Atelier de confort, Sac de nuit, Ascension) | Porte bloquante dans chaque configuration (§6.3) ; leviers en configuration ; Ascension allumable et éteignable par `Features.JellyAscend` |
| **File du serveur saturée** après les Ascensions | Petit Splorch hors file ; clé `queueWaitNewcomer` |
| **Un système lit r au lieu du Record R** et « reprend » un déblocage après une Ascension (le bug le plus probable d'une 2e couche) | Module `Prestige` seule source ; test statique ; propriétés de `apply` |
| **Double achat**, achat rejoué | `expectedLevel`, seau à jetons, un seul bloc |
| **Confettis comptés deux fois** | Crédités dans le bloc du Grand Splorch ; seuls `Prestige.apply` et `EconomyService.buyUpgrade` les modifient ; robots de 6 h : jamais en baisse hors achat, jamais négatifs |
| **Texte coupé en français**, taille de texte du joueur | Règle 9 du §2.3 ; captures à 720p, 1080p et 4K |
| **Écran trop dense pour Léa, 8 ans** | 4 onglets, Conseillé, bandeau de détail, mode ×1 à chaque ouverture ; test M14 « comprend-elle Max ? » avant le gel |
| **Performance PS4** (≈ 1 300 pièces de plus au lancement, ≈ 2 450 fin janvier) | Budget en direct, niveaux de détail, 0 lumière de plus, test M6 |
| **Changement d'éclairage** tardif qui casse toutes les captures | Fait la première semaine, mesuré sur PS4, captures prises après |
| **Outils d'interface absents** sur un appareil | Repli sous `pcall`, compté dans Diagnostics |
| **Enfant qui perd quelque chose à l'Ascension** sans comprendre | Rien de débloqué n'est perdu ; aperçu avec 6 icônes « gardé » ; maintien de 3 s ; focus sur « Plus tard » |
| **Matrice de captures énorme** | Matrice réduite (§4.6) |
| **Ranch encombré** par paliers, Monuments et Déco perso | Zones séparées et testées (`WorldLayout.spec`) ; règle Y = 21 |

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

Il reste **29 jours ouvrés** du lundi 2 novembre au jeudi 10 décembre. Le travail tient en **3 voies parallèles** de ≈ 24 jours, ce qui laisse ≈ 5 jours par voie pour les tests et les corrections (estimation, inférence). C'est très serré : la ligne de coupe s'applique à la **revue du jeudi 3 décembre**, et la Jelly Ascend est la première à sortir du lancement. Cette charge s'ajoute au jeu de base du GDD v1.3, qui passe d'abord.

| Voie | Fonction | Effort |
|---|---|---|
| **A. Améliorations** | `UpgradeMath`, `UpgradeAdvisor`, `Config/Upgrades` | 3 j |
| | Écran Améliorations, carte unique (2 gabarits), bandeau de détail, puce « Prochain achat », rail du menu | 8 j |
| | ×1 / ×10 / Max, `BuyUpgrade`, état « en attente » | 3 j |
| | Gants Moelleux et leur effet visuel | 2 j |
| | Tapis Étoilé | 2 j |
| | Atelier et Confettis (lignes 1-7, 4 cosmétiques) | 4 j |
| | Portes de simulation (§6.3) | 2 j |
| **B. Renaissance et ranch** | `Prestige`, champs du schéma, test statique | 2 j |
| | Table R1-R40, cadeau du Splorch, places offertes, décorations gardées, plafonds de Fame et de bannière | 3 j |
| | Paliers de ranch, Chantier, Cuve et Pot visibles, éléments par R | 6 j |
| | Socles de souvenir ; signal « prêt » | 2 j |
| | Monuments 1-4 | 3 j |
| | Jelly Ascend (code éteint), Petit Splorch, halo, ciel A1-A2 : livrés éteints si leurs specs sont vertes le 10 décembre, sinon dans la version du 19 décembre | 7 j |
| **C. Spectacle** | Feuille de style ; Unified Lighting et mesure PS4 (semaine 1) | 4 j |
| | Cascade et retour à 3 niveaux | 3 j |
| | Paliers du Tapis, coussins, lit à baldaquin | 3 j |
| | Personnalités (18 saynètes) et visages, réactions ; test des yeux | 6,5 j |
| | Événements relookés (MEGA, lune, traces dorées, palette du Grand Splorch) | 2 j |
| | Costume « Frost & Sprinkles » (kit de costume) | 3 j |
| | Budget visuel en direct et captures de référence | 3 j |
| | **Total** | **≈ 72 jours de développement** (A ≈ 24, B ≈ 23, C ≈ 24,5 ; ≈ 65 sans la Jelly Ascend) |

**Ligne de coupe** (dans cet ordre, si une porte de qualité n'est pas verte le 3 décembre) : (1) Jelly Ascend → version du 19 décembre ; (2) Monuments → 19 décembre (données) ; (3) Tapis Étoilé → 19 décembre (le joueur de référence n'atteint r = 10 qu'au jour 7) ; (4) cosmétiques de l'Atelier → 2 janvier ; (5) 3e saynète de chaque personnalité et ola du palier ; (6) Chantier de Big Plop (les éléments arrivent en cascade simple) ; (7) traces dorées et lune du MEGA.

**Jamais coupé** : l'écran Améliorations avec ×1 / ×10 / Max et ses 16 règles et tests ; les Gants ; la table R1-R20 avec au moins un changement visible à chaque R ; les paliers de ranch ; les socles ; `Prestige` et les champs du schéma ; les portes de simulation ; la feuille de style ; la décision d'éclairage ; la cascade ; les paliers du Tapis ; au moins 2 saynètes par personnalité et les visages ; le budget visuel et les captures. **Si quelque chose doit céder, c'est le contenu, jamais la qualité** (GDD §12.12) ; la date de repli du GDD (samedi 9 janvier 2027) reste la vraie protection.

### 8.2 Les mises à jour

| Date | Contenu | Effort | Condition |
|---|---|---|---|
| Sam. 19 déc. | Plopettes et École (L, 8 j, construites en parallèle dès que la voie A a fini l'écran), Monuments 5-6 (données), 2 palettes d'hiver | L | Porte avec Plopettes verte ; robots de 6 h verts |
| **Sam. 26 déc.** | **Jelly Ascend allumée**, Petit Splorch, halo, ciel A1-A2, Tremplin, niveaux A ≥ 1 de l'Atelier | Configuration | Porte avec Ascension verte ; `queueWaitNewcomer` vert |
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
| Niveaux achetables | 45 | 107 | 141 |
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

---

## Annexe A. Sources

**Sources de `docs/08-etude-tycoons-2026.md`** (liste complète avec URL et date dans son chapitre 11) citées ici : [08-19] Ride A Pet ; [08-43] [08-44] [08-45] [08-46] Sell Lemons (managers, Powers, achat à distance à 459 R$, couches) ; [08-55] Restaurant Tycoon 3 ; [08-60] Clash of Clans, nouvel écran d'amélioration et ses bugs (08/10/2026) ; [08-61] retours de joueurs sur « Buy Max » ; [08-65] bouton qui reste « appuyé » à la manette ; [08-68] [08-69] chute de Sell Lemons ; [08-83] Merge a Nuke ; [08-86] passes de rebirth automatique ; [08-88] premier prestige et gain en 30 s ; [08-91] Unified Lighting ; [08-92] `UIShadow` ; [08-94] feuilles de style ; [08-102] Kotaku sur Steal a Brainrot ; [08-104] confusion Sx / Sp ; [08-105] schéma « bébé » ; [08-108] look « simulateur » ; [08-112] [08-113] rythme de Steal An Egg ; [08-125] prix et Roblox Plus ; [08-145] `TextScaled` et taille de texte du joueur ; [08-152] serveurs PlayStation seuls ; [08-161] pièges de mise en page Roblox.

**Plans de travail fusionnés** (01/11/2026, dossier de travail `scratchpad/etude-tycoons/`) : `plan-progression.md` (avec sa simulation `scratchpad/plan-sim/`), `plan-renaissance.md`, `plan-spectacle.md`, `ecarts.md`. Leurs sources propres (guides de Sell Lemons, Steal a Brainrot, Ride A Pet, Pet Simulator 99, Adopt Me, Restaurant Tycoon 3, Build a Zoo, Clean the Squishies, vues en extraits de recherche le 01/11/2026) sont listées dans chacun d'eux ; nous n'en reprenons ici que la forme des systèmes, jamais les valeurs.

**Vues pour ce document le 01/11/2026** (extraits de recherche ; roblox.com et devforum.roblox.com sont bloqués depuis cette machine) :
- **[W1]** Developer Forum, « [Full Release] Upgraded UI Gradients » : dégradés radiaux, coniques et elliptiques, modes de répétition et échelle, accessibles à tous (le drapeau de bêta est retiré) — https://devforum.roblox.com/t/full-release-upgraded-ui-gradients/4846594 — date exacte incertaine (un juré cite le 29/10/2026 ; l'extrait dit « il y a 60 jours »). Confirme la sortie ; la disponibilité dans le client sur console reste à vérifier sur une vraie PS5.
- **[W2]** timesaver.gg, « Steal An Egg Alien Biome » : carte d'événement « NEW ALIEN BIOME » du 07/11/2026 16:00 UTC au 14/11/2026 19:00 UTC ; dernier billet numéroté : Update 10.5 — https://timesaver.gg/blog/steal-an-egg-alien-biome — 01/11/2026, site de fans, confiance moyenne.

## Annexe B. Ce qui n'est pas vérifié

- **La configuration du lancement n'est pas mesurée** : le prototype avait les Plopettes. La porte doit la vérifier (hypothèse H2) avant le 3 décembre.
- **Le rythme de la Jelly Ascend** (jours, retour au record, boucle la plus courte) est entièrement en cible.
- **Le confort de l'Atelier** (Aimant, Sac et Pot de nuit) et les décorations gardées ne sont pas modélisés.
- **Le vrai poids des Plopettes** avec la règle des 12 studs : le prototype ne connaît pas la position du joueur.
- **Les performances sur PS4** des décors ajoutés et d'Unified Lighting : à mesurer (test M6).
- **Le ressenti des enfants** devant l'écran Améliorations, le mode ×10 / Max, les maintiens de 0,6 s et de 3 s, les yeux « bébé » : test M14 avec des enfants de 8 à 13 ans devant une télé.
- **Un pic de joueurs pendant les vacances d'hiver 2025**, cité par un juré d'après un rapport tiers (12,5 M) : la recherche du 01/11/2026 ne l'a pas confirmé (elle ne trouve que le record d'août 2025, ≈ 45 à 47 M selon les sources). L'argument « allumer l'Ascension pendant les vacances » repose donc sur le calendrier scolaire, pas sur ce chiffre.
- **Le nombre d'achats par séance des leaders** : aucune source ne le donne ; « un but toutes les 1 à 3 minutes » est un choix de design.
