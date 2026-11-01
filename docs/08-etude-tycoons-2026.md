# Étude : les tycoons qui marchent le mieux en 2026, et ce qu'on leur prend

> **Date de référence : dimanche 1er novembre 2026.**
> **Demande du propriétaire (1er novembre 2026)** : « Pour ce jeu, je veux qu'il soit le plus complet possible, plein d'améliorations, la renaissance (rebirth), de beaux visuels. Regarde les tycoons qui marchent le mieux en ce moment et prends exemple. » Et **zéro bug** : Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration.
> **But de ce document** : dire quels tycoons Roblox marchent le mieux maintenant et sur les 18 derniers mois, **pourquoi**, et en tirer des modèles concrets pour *Raise a Squishy*, thème par thème : améliorations, renaissance, visuels, rétention et contenu, monétisation juste, console.
> Documents liés : [`01-analyse-marche-tycoon.md`](01-analyse-marche-tycoon.md) (étude du 31 octobre, que celle-ci complète et corrige), [`02-game-design-document.md`](02-game-design-document.md) (GDD v1.3, cité « GDD §x »), [`03-decision-du-jury.md`](03-decision-du-jury.md).

**Petit lexique.**
- **CCU** : nombre de joueurs connectés **en même temps** sur un jeu.
- **Renaissance (rebirth, prestige)** : on recommence une partie de sa progression en échange d'un bonus permanent. Chez nous : le **Grand Splorch**.
- **Couche de prestige** : un niveau de renaissance au-dessus d'un autre (par exemple *Rebirth*, puis *Evolution*, puis *Ascension*).
- **Famille d'améliorations** : un type d'achat qui monte par niveaux (chez nous : Tapis à Goûter, Décorations, Enclos, Lit douillet).
- **Piste de récompenses** : une suite de paliers qu'on débloque en jouant (gratuite ou payante).
- **Admin Abuse** : séance où le développeur se connecte et déclenche des bonus pour tout le monde ; c'est devenu un rendez-vous du samedi.

**Méthode et limites (à lire).**
- Six recherches parallèles ont été faites le 1er novembre 2026 : classement, améliorations, renaissance, visuels, rétention et monétisation, console.
- **Les pages n'ont presque pas pu être lues en entier.** Depuis notre session, roblox.com, create.roblox.com, devforum.roblox.com et apis.roblox.com sont bloqués, et l'outil de lecture de pages n'a pas pu joindre rowatcher.com, rolimons.com, allthings.how, beebom.com, sportskeeda.com, les wikis Fandom, wikipedia.org ni le PlayStation Blog. Les faits viennent donc d'**extraits de résultats de recherche** (le texte que le moteur montre sous chaque lien). Seule exception : la documentation officielle de Roblox, lue en entier sur GitHub (`Roblox/creator-docs`). Pour lire ces sites directement, il faudrait les autoriser dans les réglages réseau de la session.
- **Les sites de suivi ne sont pas d'accord entre eux**, souvent d'un facteur 2, parfois de 10 (exemple : Ride A Pet à 20 755 joueurs sur Rolimons contre ≈ 120 000 ailleurs, octobre 2026 [19][160]). Chaque chiffre de joueurs est une **photo à une date**, jamais un compte officiel. Les seuls chiffres officiels sont ceux de Roblox et de Guinness.
- **Les wikis de fans se contredisent** sur les prix et les tables de rebirth (exemple : 16, 17, 18 ou 19 niveaux de rebirth pour Steal a Brainrot selon le guide [71][72][73]). Nous les utilisons pour la **forme** des systèmes, jamais pour recopier des valeurs.
- Chaque fait porte sa source entre crochets, par exemple [3], qui renvoie à la liste du chapitre 11, avec sa date. **« (inférence) »** marque notre propre conclusion, qui n'est écrite dans aucune source. « Confiance faible » veut dire : une seule source, ou des sources qui se contredisent.

---

## 1) Résumé pour le propriétaire (10 lignes)

1. **Le n°1 est un tycoon de créatures** : *Steal An Egg*, ≈ 1,04 M de joueurs simultanés le 20/10/2026 et un record de ≈ 14,3 M le 19/09/2026 [1][2]. **Tous** les tycoons au-dessus de 100 000 joueurs mélangent collection de créatures, revenu passif, renaissance à étapes et rendez-vous chaque semaine [1][9][19][24].
2. **Les tycoons « classiques » de gestion sont petits** : Restaurant Tycoon 3, le plus joué, fait ≈ 11-13 K ; Theme Park Tycoon 2 ≈ 3-4 K malgré 6 M de favoris [32][35][36]. La gestion seule ne suffit plus.
3. **Les hits retombent vite** : Grow a Garden est passé de 22,4 M (août 2025) à ≈ 17 K (octobre 2026), Sell Lemons de ≈ 229 K (juillet 2026) à ≈ 9 K (octobre 2026) [11][12][68][69]. La profondeur garde les fidèles ; le public vient des événements, du contenu de chaque semaine et du jeu entre amis.
4. **Améliorations** : les leaders ont beaucoup plus de familles que nous. Sell Lemons a 8 sources de revenu avec leurs managers, une recherche qui survit aux remises à zéro et des « Powers » de confort [42][43][44]. Notre GDD a **4 familles et 45 niveaux**.
5. **Renaissance** : la norme 2026, c'est « on garde ses créatures » (nous aussi), **quelque chose de visible et de neuf à chaque niveau** (un étage, une place, une base qui change d'aspect) et **2 ou 3 couches** de prestige [20][46][97]. Chez nous, le ranch **s'appauvrit à l'écran** à chaque Grand Splorch (décorations remises à zéro), et la 2e couche est repoussée à janvier.
6. **Visuels** : la finesse graphique ne fait pas le succès (Kotaku trouve Steal a Brainrot « très laid » [102]) ; le charme, la lisibilité et les grands moments, si. Notre style en formes simples convient. Roblox a sorti en 2026 des outils d'interface (ombres, dégradés, feuilles de style) qui rendent le look « simulateur » faisable en code [92][93][95].
7. **Rétention** : notre GDD couvre déjà presque tout (jours comptés au total, objectifs faisables, Squishydex, croissance hors ligne, rendez-vous du samedi). Il manque **une activité nouvelle chaque semaine avec une piste de récompenses gratuite** (Steal An Egg le fait depuis août) et **un modèle d'événement de saison** [112][113][34].
8. **Monétisation juste** : nos prix sont sous ceux du marché et nos règles sont plus saines que celles des leaders. Risque nouveau : **Roblox Plus** (−10 % puis −20 % sur les achats depuis le 30/04/2026) fait afficher un **faux prix** si le prix est écrit en dur [124][125] : c'est la même famille de bugs d'affichage que Comet Conga.
9. **Console** : Roblox est le 4e jeu le plus joué sur PlayStation aux États-Unis en 2025 et a une appli PS5 native depuis le 14/04/2026 [139][142], mais la console reste ≈ 3 % des joueurs [138]. Trois bases techniques du GDD sont **dépassées** : le réglage d'éclairage, la détection de la console et la taille du texte choisie par le joueur [91][144][145].
10. **Rien de ce qu'on reprend ne demande de hasard payant, de vol ou de pression sur les enfants.** On copie la forme des systèmes, jamais leurs pièges.

---

## 2) Les jeux qui marchent le mieux, et pourquoi

### 2.1 Le classement fin octobre 2026 (joueurs simultanés)

Tycoons et hybrides de tycoon (collection + revenu + construction). Chiffres pris à des dates différentes : à lire comme des ordres de grandeur.

| # | Jeu | Joueurs simultanés (date) | Record (date) | Type | Source |
|---|---|---|---|---|---|
| 1 | **Steal An Egg** | ≈ 1 038 680 (20/10/2026) | ≈ 14,2-14,3 M (19/09/2026) ; ≈ 6 milliards de visites au 3e trimestre 2026 | Œufs volés ou achetés, familiers, revenu passif | [1][2] |
| 2 | **Adopt Me!** (élevage de familiers, événement d'Halloween) | ≈ 270 K (10/10/2026) | — | Élevage, collection | [30] |
| 3 | **Steal a Brainrot** | ≈ 205-229 K (fin octobre 2026) | **25 868 678** (11/10/2025, record Guinness) | Vol sur tapis roulant, base, rebirths | [7][41] |
| 4 | **Ride A Pet** | ≈ 120 K (24/10/2026) ; 420 M de visites | ≈ 1,55 M (03/10/2026) | Monter ses familiers pour trouver des œufs | [19] |
| 5 | **Fish It!** | ≈ 66 K (mi-octobre 2026) | 1,4 M (24/11/2025) ; une autre source dit 2,7 M | Pêche + collection | [28] |
| 6 | **Grow a Garden** | 16 843 (26/10/2026) | 22 375 597 (23/08/2025) | Jardin, croissance hors ligne | [11][12] |
| 7 | **Restaurant Tycoon 3** | ≈ 11-13 K (octobre 2026) | ≈ 50 K (01/11/2025) | Tycoon classique de restaurant | [32] |
| 8 | **Sell Lemons** | ≈ 9-9,9 K (19-22/10/2026) | ≈ 221-229 K (juillet 2026) | Tycoon pur, 3 couches de prestige | [68][69][70] |
| 9 | **Car Dealership Tycoon** | ≈ 3-9 K (2026) | 66 726 (16/09/2023) | Tycoon classique | [33] |
| 10 | **Theme Park Tycoon 2** | ≈ 3-4 K (octobre 2026) | 18 K suivi (30/12/2025) | Bac à sable créatif | [35][36] |
| 11 | **Build a Zoo** | ≈ 2,6-10 K (non daté) | 95 191 (24/10/2025) | Tapis d'œufs, enclos, revenu passif | [25] |
| 12 | **Retail Tycoon 2** | ≈ 1-3 K (2026) | 5 K suivi (19/04/2026) | Tycoon classique | [37] |

Hors tycoons purs, l'élevage de familiers dure : Adopt Me! ≈ 324 K et Pet Simulator 99 ≈ 78 K en juin 2026 [31].

Sources qui se contredisent : Sell Lemons était donné à « ≈ 32 K » après son pic dans une recherche, à ≈ 9-9,9 K les 19-22 octobre dans deux autres [68][69] : nous retenons le chiffre daté. Grow a Garden 2 : record de 971 967 le 18/06/2026 selon un suivi [16], de 483 561 le 13/08/2026 selon un autre [17] (confiance faible) ; il est de toute façon effondré.

### 2.2 Les grands pics des 18 derniers mois (mai 2025 à octobre 2026)

| Jeu | Record | Date | Où il en est |
|---|---|---|---|
| Steal a Brainrot | 25,87 M (Guinness) ; premier jeu au-delà de 25 M | 11/10/2025 | ≈ 205-229 K (−99 %) [7][8] |
| Grow a Garden | 22,38 M | 23/08/2025 | ≈ 17 K (−99,9 %) [11][12] |
| Steal An Egg | ≈ 14,3 M | 19/09/2026 | ≈ 1 M [1][2] |
| Plants vs Brainrots | ≈ 3,2 M (une autre source : 8,65 M le 11/10/2025) | sept.-oct. 2025 | ≈ 70 K fin décembre 2025, ≈ 5 K mi-février 2026 (confiance faible) [27][75] |
| Ride A Pet | ≈ 1,55 M | 03/10/2026 | ≈ 120 K [19] |
| Fish It! | 1,4 M | 24/11/2025 | ≈ 66 K [28] |
| Sell Lemons | ≈ 229 K | juillet 2026 | ≈ 9 K [68][70] |
| Build a Zoo | 95 191 | 24/10/2025 | quelques milliers [25] |

Le record de toute la plateforme, ≈ 47,4 M de joueurs en même temps (août 2025), est venu d'une « guerre d'admins » entre Grow a Garden et Steal a Brainrot [29]. Le concert de Bruno Mars dans Steal a Brainrot a réuni 12 862 161 joueurs le 17/01/2026 ; celui des Jonas Brothers (31/10/2026) avait plus de 8,5 M d'« intéressés », sans chiffre de présence publié au 1er novembre [6].

### 2.3 Pourquoi les meilleurs marchent

| Jeu | Ce qui le porte | Source |
|---|---|---|
| **Steal An Egg** | **Deux chiffres que tout enfant comprend** : « la vitesse décide des zones que tu atteins, les familiers décident de combien tu gagnes ». Œufs à minuteur (plus gros = plus long, plus fort), enclos qui s'agrandit, Admin Abuse **chaque samedi juste avant la mise à jour**, événements avec des célébrités | [4][5] |
| **Steal a Brainrot** | Tapis roulant central où l'on achète ou vole des personnages ; base verrouillée un temps (+10 s par rebirth) ; **16 à 19 rebirths** qui ajoutent chacun multiplicateur, étages et places : **la base grandit à l'œil**. Mise à jour presque chaque samedi, grosse mise à jour de rebirth environ toutes les 6 semaines | [9][10] |
| **Grow a Garden** | Boucle très simple ; **les plantes poussent même hors ligne** ; frères, sœurs et camarades se comparent (« le plus beau jardin ») ; météo spéciale avec mutations le samedi. Né d'un jeu d'un adolescent repris quand il n'avait qu'≈ 500 joueurs simultanés | [14][15] |
| **Ride A Pet** | On **monte ses familiers** pour trouver des œufs ; une monture plus rapide atteint des nids plus rares. 7 rebirths, chacun demande **un familier précis** et **garde tous les familiers** ; chaque rebirth : +1× d'argent et +1 place au ranch | [20][21] |
| **Sell Lemons** | Très gros nombres, revenu hors ligne, **trois couches de prestige** (Rebirth, Evolution, Ascension) jusqu'à un but final nommé (« The End ») | [23][24] |
| **Build a Zoo** | Œufs achetés sur un tapis, posés dans des enclos, qui éclosent en animaux qui rapportent. **C'est le jeu le plus proche du nôtre**, et il a plafonné sous 100 000 joueurs, sans couche sociale ni événementielle forte | [25][26] |
| **Les classiques** (Theme Park Tycoon 2, Car Dealership Tycoon, Restaurant Tycoon 3) | Construire et s'exprimer, événements de saison réguliers, énormément de favoris. Mais seulement 1 à 13 K joueurs simultanés | [32][33][35] |

Ce que les enfants et les parents en disent : on joue en se parlant dans la vraie vie, partager sa créature préférée sert de « monnaie de cour de récréation », les personnages sont volontairement idiots, on compare avec son frère qui a le plus beau jardin ; les parents s'inquiètent surtout des dépenses et des inconnus [14][38].

**La formule en une phrase (inférence)** : *une créature à collectionner + un revenu qui monte tout seul + une renaissance qu'on voit + un rendez-vous chaque semaine + une raison de jouer avec les autres*. Notre GDD a déjà les cinq ; ce document dit où les leaders vont plus loin.

### 2.4 Ce qui fait tomber les jeux

- **Une suite faite de contenu recyclé**, avec des règles d'événement confuses et du payant qui fait gagner : Grow a Garden 2 a perdu 91,5 % en 30 jours après son pic (mi-septembre 2026) [17][18].
- **La fatigue du rythme hebdomadaire** et des créateurs qui s'épuisent : les fondateurs de Grow a Garden ont pris du recul début 2026 [11][13].
- **Une accroche qui n'est qu'un mème** : la vague « brainrot » s'effondre [41].
- **La gestion seule** : Theme Park Tycoon 2 a perdu 41 % en 30 jours, Retail Tycoon 2 26 % (octobre 2026) [36][37].
- **Un tapis d'œufs + revenu passif sans le reste** : Build a Zoo a plafonné à 95 K [25].
- **Perdre une créature rare** fait pleurer et fâche la communauté : par le vol (docs/01 §5.2), ou par un rebirth fait trop vite, comme ce joueur qui a perdu son seul Mythique [89].

### 2.5 Ce que cette étude corrige dans docs/01 (31 octobre)

| docs/01 | Correction | Source |
|---|---|---|
| En-tête et règle 9 : « Mobile d'abord », « PS5, téléphone et PC » | Remplacé par la décision du 1er novembre : **console d'abord**, sans téléphone ni tactile (déjà dans le GDD v1.2). Le coût en public (≈ 80 % des joueurs sont sur mobile) est écrit dans le GDD (risque 14), pas dans docs/01 | [138] |
| Grow a Garden 2 « sorti le 12 juin » | Sorti le **21 mai 2026** ; record le 18 juin 2026 (ou 13 août selon un autre suivi) | [16][17] |
| Sell Lemons « a mis 16 mois à grandir », « Rebirth puis Ascend », « ≈ 32 K plus tard » | Sortie publique le **15 mai 2026** selon son studio (l'expérience existait depuis mars 2025) : il a atteint son pic en 1 à 2 mois. **Trois** couches de prestige. ≈ **9-9,9 K** les 19-22/10/2026. Système de quêtes seulement du 3 au 13 novembre 2026 | [22][68][69][120] |
| §4.1 : Steal An Egg aurait un rebirth | **Non vérifié** : des wikis de fans l'affirment, les chronologies indépendantes et deux guides disent le contraire | [50] |
| Record de Steal a Brainrot | Confirmé par Guinness : **25 868 678** le 11/10/2025 | [7] |
| §2.3 « les classiques plafonnent à 20-35 K » | Il manque les vrais classiques : Car Dealership Tycoon (66,7 K en 2023), Restaurant Tycoon 3 (50 K en novembre 2025) ; Theme Park Tycoon 2, Retail Tycoon 2, Lumber Tycoon 2 et My Restaurant! ne font plus que ≈ 0,5-4 K | [32][33][36][37] |
| Historique 2025 | Manquaient Grow a Garden (22,38 M), Plants vs Brainrots, Build a Zoo, Fish It et le record plateforme de 47,4 M (août 2025) | [11][27][25][28][29] |
| §6.4 console « aucune donnée fiable » | Données partielles : 4e jeu le plus joué sur PlayStation aux États-Unis en 2025, top 2 des téléchargements gratuits du PS Store 2025, n°1 en heures sur PC + consoles au 1er semestre 2026, appli PS5 native le 14/04/2026 | [139][140][141][142] |
| §4.4 et règles de Roblox | Nouveaux : Roblox Plus a remplacé Premium le 30/04/2026 (remises sur les achats), abonnements en Robux dès 49 R$, règles sur les objets aléatoires payants en vigueur le **26 mai** 2026 (pas juin), mise à jour de la découverte du 20/08/2026 | [123][124][127][130] |
| Merge a Nuke « 122 K en juillet » | Un autre suivi donne 65 625 le 15/08/2026 (confiance faible) | [83] |
| §3.6 captures et Moments | La capture vidéo de Roblox n'est **pas** disponible sur console ; les vignettes vidéo ne s'affichent pas sur console | [154] |

---

## 3) Améliorations

### 3.1 Ce que font les leaders

**Nombre et organisation.** Aucune source ne donne le nombre exact d'améliorations d'un hit à sa sortie. Ce qu'on voit :

| Jeu | Familles d'améliorations (guides 2026) | Source |
|---|---|---|
| **Sell Lemons** | 8 sources de revenu débloquées l'une après l'autre (du stand de limonade à « LemonX »), chacune avec **ses** améliorations et **son manager** qui l'automatise ; une recherche (« Lemon Labs ») **gardée** aux remises à zéro ; 5 à 7 « Powers » payés en Investisseurs (la monnaie du rebirth) ; des jetons « Forever Purchase » | [42][43][44][46] |
| **Steal An Egg** | Une échelle de **tapis de course à paliers nommés et d'aspect différent** (Basic, Sci-Fi, Flame, Celebrity, Golden, Freeze, Lucky Block, Hacker, Demonic, Angelic, Astral…), de gratuit à 15 Qa ; un enclos à 11 niveaux (7 → 18 familiers) ; des places « +1 EQUIP » ; des traînées qui multiplient la vitesse. Un guide parle de « 39 améliorations » (non lu) | [47][49] |
| **Escape Tsunami for Brainrots** | Niveau de chaque créature (plafond relevé de 175 à 350 en 2026, les plus hauts réservés aux rebirths 29-30) ; base à **31 places** avec **un étage visible tous les 10 emplacements** ; capacité de portage | [51][52] |
| **Restaurant Tycoon 3** | 4 types d'employés, embauchés puis montés sur 5 niveaux ; cuisines par paliers ; page de jalons | [55] |
| **Merge a Nuke** | Vitesse d'apparition, palier d'apparition, nombre maximum, verrou de base | [53] |
| **Notre GDD v1.3** | **4 familles, 45 niveaux** : Tapis à Goûter 12, Décorations 18, Enclos 14, Lit douillet 1 (GDD §4.6). La Cuve monte seule avec R (GDD §4.9) | GDD |

**Courbes de prix.** Les jeux de type « idle » utilisent `prix = base × taux^niveau`, avec un taux de **1,07 à 1,15** pour les familles à beaucoup de niveaux, et des **paliers** (gros bonus à 10, 25, 50, 100 exemplaires) qui créent des pics de plaisir (AdVenture Capitalist, Idle Miner) [57][58]. Les **échelles courtes à paliers nommés** multiplient le prix par **15 à 40** par palier pour un gain de ×1,3 à ×2,7 seulement (Steal An Egg) [47]. Sell Lemons multiplie les prix par **×3,33** à chaque Ascension contre ×7,77 de revenu [46] : un hit 2026 renchérit les achats après une remise à zéro, comme notre ×3,5^R (GDD §4.6).

**Deux couches de persistance.** Les références séparent une progression **remise à zéro** et une couche **permanente** payée avec une monnaie gagnée au prestige : Investisseurs et Powers de Sell Lemons [44], recherche « épique » d'Egg, Inc. [59].

**Un arbre d'améliorations seul ne fait pas un succès** : Upgradex, jeu bâti sur un arbre, a un record d'≈ 3 467 joueurs simultanés (2026) [56].

**Les échelles grandissent après la sortie** : Steal a Brainrot est passé du rebirth 11 (28/06/2025, 6 semaines après la sortie) au rebirth 16 (04/10/2025) ; Steal An Egg a ajouté un palier de tapis à l'Update 4 (12/09/2026, 7 semaines après la sortie) [48][71].

### 3.2 Les écrans d'amélioration

- **Clash of Clans a refait son écran d'amélioration** (annoncé le 08/10/2026) : **un seul menu à 4 onglets** et une section **« Recommandé »** en tête. Supercell reconnaît lui-même deux bugs d'affichage : des améliorations payables classées sous des non payables, et un compteur qui **repart de 0** en s'animant quand on change d'onglet [60]. Ce sont exactement les familles de bugs de Comet Conga (tri, compteurs, rafraîchissement) (inférence).
- **Achat en masse** : les joueurs demandent x1, x10, Max, et surtout **un retour clair** : « Buy Max ne dit pas s'il a acheté, ni combien il a dépensé » ; si on ne peut payer que 80 niveaux sur 100, acheter les 80 (confiance faible, commentaires de joueurs) [61].
- **Sur console, marcher jusqu'à chaque dalle est une corvée** : Sell Lemons vend « Manage » (tout gérer depuis un écran) et « Remote Buy » (acheter sans marcher, 459 R$ ou en Investisseurs) [44][45].
- **Règles « 10 pieds »** (joueur à ≈ 3 m) : focus clair et sans ambiguïté, tout faisable à la croix directionnelle, peu d'informations par écran, un changement d'état bref à l'appui [62][63][64].
- **Piège connu de Roblox** : un bouton reste dans l'état « appuyé » après un clic à la manette, jusqu'au prochain survol (rapport 2026) [65].
- **Le retour d'un achat de tycoon** : l'objet sort du sol et apparaît pièce par pièce [66].

### Ce qu'on reprend

1. **Passer de 4 à 7-9 familles d'améliorations**, chacune avec un verbe et un objet **visible dans le ranch**. Pistes compatibles avec le GDD (« les pièces n'achètent jamais de chance », §4.6) : revenu (presse-jus, comptoir), confort (rayon d'encaissement, vitesse de marche dans le ranch), aides animées (petits « Plopettes » qui pressent tout seuls, 5 niveaux chacun, comme les employés de Restaurant Tycoon 3 [55]), espace (terrasses du ranch), décor permanent. Jamais la Cuve ni une probabilité (inférence, d'après [42][47][51]).
2. **Des échelles à paliers nommés qui changent d'aspect**, comme les tapis de Steal An Egg [47] : tous les N niveaux, le Tapis, les enclos ou le Pot changent de « peau » (pique-nique → bonbon → doré → galaxie) avec le nom du palier affiché. Le GDD fait déjà changer le Tapis de couleur et de motif à chaque niveau (GDD §11.2) : il faut des **noms** et un vrai saut visuel aux paliers.
3. **Deux formes de courbe, au choix par famille** : longues (25 à 100 niveaux, taux 1,07 à 1,15, bonus aux niveaux 10, 25, 50, 100) et courtes (8 à 12 paliers, ×10 à ×25 par palier) [47][57]. Notre Tapis (×4 sur 12 niveaux) est une échelle courte : pour « plein d'améliorations », **ajouter des familles longues** plutôt qu'allonger le Tapis. Toute nouvelle famille passe la simulation `EconomyPacing` (GDD §4.24).
4. **Garder les prix ×3,5^R** (même logique que Sell Lemons [46]).
5. **Une méta-couche permanente** payée avec une monnaie gagnée au Grand Splorch (modèle : Investisseurs et Powers [44], recherche gardée [46]) : achat en masse, achat à distance, plafond hors ligne, rayon d'encaissement. **Gratuite, jamais en Robux** (inférence).
6. **Un écran central d'améliorations à onglets, avec une rangée « Recommandé » de 3 cartes au plus** (Clash of Clans [60]). L'onglet *Dalles* du panneau Ranch (GDD §10.3) devient le chemin principal, ouvert par un raccourci : sur console, on ne doit jamais être obligé de marcher jusqu'à une dalle [45].
7. **Achat en masse x1 / x10 / Max à la manette**, toujours avec un retour chiffré (« +7 niveaux · −1,2 M »), achat partiel de ce qui est payable, bouton grisé avec la raison quand rien n'est possible [61].
8. **Une carte d'amélioration lisible à 3 m** (inférence, d'après [62][63]) : grande icône, nom en 2-3 mots, « Niv. 7/25 », avant → après en chiffres (« +6/s → +7/s »), prix avec l'icône de pièce, barre vers le prochain palier, état payable / verrouillé / MAX montré par **une icône et un mot**, jamais par la couleur seule.
9. **Chaque achat change le monde** : petit retour pour x1, un seul retour groupé pour x10 ou Max, gros spectacle seulement aux paliers [66].
10. **Des tables d'amélioration en données, avec des plafonds relevables par configuration** : prévoir dès le lancement les paliers « bientôt » qu'on ouvrira en quelques semaines, comme les leaders [48][71].

---

## 4) Renaissance

### 4.1 Ce que font les leaders

| Jeu | Condition | Ce qui repart de zéro | Ce qui est gardé | Récompense | Source |
|---|---|---|---|---|---|
| **Steal a Brainrot** | Argent **et** un ou deux brainrots précis (R6 : 350 M + Bombardiro Crocodilo ; R16 : 1 Qa + un Secret rare) | Argent **et brainrots de la base** | Multiplicateur, places, objets | Multiplicateur (×3 à ×13 selon le niveau ; valeurs contradictoires entre guides), argent de départ, +10 s de verrou, **étage 2 au R2, étage 3 au R10, étage 4 au R18** ; 16 à 19 niveaux selon les guides | [71][72][73][97] |
| **Ride A Pet** | Argent + un familier précis (R1 : 1 M + un Cheval, 1 chance sur 500 000) ; **le familier n'est pas consommé** | Argent, chance achetée | **Tous les familiers et les œufs** | +1× d'argent, **+1 place** (5 → 12), **base qui change d'aspect** : Gold, Diamond, Ruby, Crystal, Sakura, Draconic | [20][21][76][77] |
| **Plants vs Brainrots** | 1 M + 2 brainrots précis | Argent, places posées | Brainrots, plantes, équipement, graines, œufs | +50 % de chance **et** +50 % d'argent par niveau, plus un objet par niveau (batte, **machine de fusion**, île plus grande) ; 13 niveaux | [54][74] |
| **Pet Simulator 99** | Atteindre une zone précise (autels dans le monde) | Pièces, progression de zone | Familiers et fonctions débloquées | +75 % de puissance **et une fonction nouvelle par rebirth** (R2 : éclosion automatique ; R3 : équipes ; R4 : monde 2…), puis un « Super Rebirth » | [81][82] |
| **Sell Lemons** | 3 couches : Rebirth (≈ 77 sextillions), Void Evolution, Ascension (« The End », 320 octogintillions) | Selon la couche ; l'Ascension remet presque tout à zéro | Achats en Robux, recherche, un bouton gardé par jeton | Investisseurs (+1 % chacun), ×42 par Évolution, ×7,77 à l'Ascension **mais prix ×3,33** (≈ ×2,33 net), **halo** et salon réservé | [46][67][24] |
| **Merge a Nuke** | Palier de bombe le plus haut possédé | Bombes, argent, améliorations | — | +5 paliers de fusion par rebirth ; mutations débloquées aux R3, R5, R10 ; bonus tardifs **additifs** (+110 %, +120 %, +130 %) | [53][83] |
| **Grow a Garden** (Ascension, 30/08/2025) | 1 000 milliards + 1 à 3 fruits | **Tout** l'argent | Jardin, familiers | 10 « Garden Coins ». **Colère des joueurs**, refait le 09/09/2025 (on garde une partie de l'argent, attente de 4 h au lieu de 24 h) | [78][79][80] |
| **Notre GDD v1.3** | Taille du plus gros squishy (15 000, puis ×2,6 par niveau) | Pièces, Pot, Tapis, décorations, taille | **Tous les squishies**, Cuve, selles, enclos, Lit, Squishydex, Fame, passes… | ×2 croissance pour toujours, Cuve meilleure, familles aux R1/R3/R5, Meilleurs Amis aux R3/R10, titres aux R5/10/15/20, **cadeaux pour tout le serveur** (GDD §4.15) | GDD |

**Les pièges vus chez eux.**
- **Perdre sa meilleure créature** : un joueur de Build a Base and Steal a perdu son seul Mythique en faisant son rebirth trop vite (août 2026) [89] ; Steal a Brainrot efface les brainrots de la base [72] ; Military Tycoon fait tout racheter [90].
- **Une remise à zéro dure pour une petite récompense** : l'Ascension de Grow a Garden prenait tout l'argent pour 10 pièces ; elle a été refaite 10 jours plus tard [78][79][80].
- **Des bonus tardifs additifs qui ne servent plus à rien** : Merge a Nuke fait +110 %, +120 %, +130 % ; un calculateur de fans montre 9,5 h au lieu de 10 h pour revenir au même revenu [83].
- **Un effet net caché** : ×7,77 de revenu mais ×3,33 sur les prix, que les guides doivent expliquer [46].
- **Des murs de chance** : 1 chance sur 500 000 pour le Cheval du premier rebirth de Ride A Pet [76].
- **Une couche qui efface les achats de la couche d'avant** : les Powers de Sell Lemons repartent de zéro à l'Évolution [44].
- **La profondeur ne garde pas le grand public** : Sell Lemons de ≈ 229 K à ≈ 9 K, Plants vs Brainrots de millions à ≈ 70 K en deux mois, malgré des rebirths généreux [68][74][75].

**Repères de conception.** Les développeurs de jeux idle conseillent un premier prestige en **10 à 20 minutes** et un gain senti dans les **30 secondes** après la remise à zéro (confiance faible) [88]. Notre premier Grand Splorch à 13 min (11-16, GDD §4.24) est dans la cible. Kongregate rappelle qu'un prestige calculé sur une racine carrée peut ne **rien** rapporter si l'on recommence au même point [87]. Des passes « rebirth automatique » existent dans de vieux simulateurs (Clicker Simulator 299 R$) [86], pas dans les hits tycoon 2025-2026 trouvés.

**Mise en scène.** Les leaders montrent la renaissance **dans le monde** : la soucoupe de Joe l'Alien qui se pose sur la base, l'escalier vers l'« Étoile de l'Ascension » (Sell Lemons) [46][67], les autels de Pet Simulator 99 [81], la base qui change d'aspect (Ride A Pet) [77]. **Aucun concurrent trouvé ne fait de cadeaux à tout le serveur lors d'une renaissance** : les cadeaux du Grand Splorch (GDD §4.15) sont un vrai point différenciant (inférence).

### Ce qu'on reprend

1. **Garder ses créatures, toujours** (norme 2026 : Plants vs Brainrots, PS99, Ride A Pet [54][77][81]). Le GDD le fait déjà ; en faire un test bloquant : aucun chemin du Grand Splorch ne retire un squishy.
2. **Un déblocage nommé à chaque niveau R**, pas seulement ×2 (PS99 [81][82], Steal a Brainrot [71]) : remplir R2, R4, R6-R9 et R11-R20 (une place, une famille d'amélioration, un palier de Cuve visible, un cosmétique gratuit, une fonction de confort), pour que l'aperçu montre toujours 3 tuiles « Tu gagnes ».
3. **Le ranch se transforme à chaque palier, de façon permanente**, visible par les 15 autres joueurs (Ride A Pet Gold → Draconic [77], étages de Steal a Brainrot [97]) : clôture, portail, panneau et terrasses changent aux R = 1, 3, 5, 10, 15, 20, construits en code. Gagné, jamais vendu.
4. **Un coup de pouce après chaque renaissance** (argent de départ de Steal a Brainrot et Break a Lucky Block [71][84]) : un « cadeau du Splorch » en pièces égal aux premiers prix du Tapis, pour sentir le gain en moins de 30 s [88].
5. **Une 2e couche vers R10, avec sa monnaie, sa boutique permanente et un signe de statut** (Sell Lemons, PS99, Arm Wrestle [46][82][85]) : pour Jelly Ascend (GDD §17.2), des « Étoiles de gelée » qui achètent des bonus **jamais remis à zéro** par les couches suivantes, plus un halo sur la plaque de nom.
6. **Un phare « prêt » au-dessus du ranch** quand l'objectif est atteint, pour que les voisins viennent chercher leurs cadeaux (inférence d'après [46][81]).
7. **Un panneau de renaissance toujours à un bouton**, avec le niveau, la condition exacte et les récompenses (Plants vs Brainrots, Ride A Pet [74][77]), plus une ligne de rentabilité : « Tu reviens à ta taille record en ≈ 6 min » (les fans font des calculateurs pour ça [83]).
8. **Des étapes multiplicatives, jamais additives**, et une porte de simulation : chaque Grand Splorch doit revenir au pic précédent en au plus ≈ 50 % du temps de la boucle précédente (inférence d'après [83][87]).
9. **Une condition de collection facultative, visible et protégée** (Steal a Brainrot, Ride A Pet [71][76]) : seulement des conditions dont l'enfant voit la progression dans le Squishydex (« avoir un Épique », « 20 tampons »), jamais un mur de chance, jamais la créature consommée.
10. **Pas de passe « rebirth automatique »** : il sauterait le spectacle et les cadeaux du serveur, qui sont le moment social (inférence). Un rappel gratuit « Ton Grand Splorch est prêt » suffit.

---

## 5) Visuels

### 5.1 Ce qu'on a appris

- **La finesse graphique n'est pas le moteur.** Kotaku a écrit de Steal a Brainrot qu'il était « un jeu très laid et ennuyeux à regarder » (2025) [102], et Grow a Garden utilise des textures à picots façon vieux Roblox [99]. Les deux ont battu des records. **Lisibilité, charme, lueurs et grands moments** comptent plus que le réalisme (inférence) : bon pour notre pipeline de formes simples et de Néon.
- **La renaissance se voit sur la base** chez les leaders : 2e étage au R2 et 3e au R10 dans Steal a Brainrot, 16 skins de base gardés pour toujours [97][98] ; halo à l'Ascension de Sell Lemons [46] ; base qui change d'aspect à chaque rebirth dans Ride A Pet [77]. My Hello Kitty Cafe grandit jusqu'à un café de 5 étages (record de 20,5 K joueurs ; confiance faible) [162].
- **L'expression de soi** : Grow a Garden a ajouté **110** objets purement décoratifs le 24/05/2025 (625 plus tard) [99]. Mais ils étaient vendus dans des **caisses au hasard**, ce que notre GDD interdit (§8.1).
- **Les mutations et raretés sont une couche visuelle lisible d'un coup d'œil** : aura colorée et multiplicateur (Steal An Egg [100]) ; Néon sur certaines parties du corps, puis les mêmes parties qui changent de couleur (Adopt Me [101]). Certaines clignotent sans arrêt (Grow a Garden).
- **Le look « simulateur »** est d'habitude fait d'images : boutons pleins avec un dégradé qui fonce vers le bas, contour extérieur, icônes plutôt que texte ; Roblox n'autorise qu'un `UIStroke` par élément [108].
- **La mode « squishy » 2026** : petits personnages ronds au toucher doux, palettes tendres, auras et traînées en récompense (Find The Squishies ≈ 11,2 K joueurs à 26 jours en juin 2026 ; Clean the Squishies, créé le 24/06/2026, plus de 10 M de visites) [106][107].
- **Le schéma « bébé »** (grosse tête, visage rond, grands yeux, petit nez et petite bouche) rend un visage plus mignon aux yeux des enfants de 3 à 6 ans, chez l'humain comme chez l'animal (étude de 2014) [105].

### 5.2 Les outils de Roblox en 2025-2026

| Outil | État au 1er novembre 2026 | Source |
|---|---|---|
| **Unified Lighting** : `LightingStyle` (Soft ou Realistic) + `PrioritizeLightingQuality` remplacent `Lighting.Technology` | Bêta en janvier 2025, **en service partout depuis juillet 2025**. Notre GDD (§11.3, §10.6) et `default.project.json` règlent encore `Technology = ShadowMap` | [91] |
| Ombres d'interface (`UIShadow`) et coins arrondis séparés (`UICorner`) | **Utilisables en ligne** depuis le 23/06/2026 ; ombres de texte et ombres intérieures encore en bêta Studio (octobre 2026) | [92] |
| `UIGradient` radial, conique et elliptique | **Utilisable** vers le 27-29/10/2026 ; Roblox conseille moins de 1 000 dégradés à la fois | [93] |
| Feuilles de style (jetons, thèmes interchangeables) | Publiables depuis le 20/01/2026 ; requêtes de style le 11/05/2026 | [94][95] |
| Particules 2D dans l'interface, flou derrière l'interface, couches de matériaux | Seulement sur la feuille de route : fin 2026, début 2027, mi-2027. **Pas pour le 12 décembre** | [96] |
| SLIM (niveaux de détail automatiques) | Décembre 2025 ; peu utile pour nos formes simples, risque d'apparitions brusques non maîtrisées (inférence) | [109] |

**Lisibilité à la télé.** Les règles d'accessibilité Xbox (XAG 101) demandent **26 px au moins** à 1080p (52 px en 4K), les mêmes minimums pour les icônes de touches, et un texte **agrandissable jusqu'à 200 %** [103]. Notre minimum de 28 px TV passe ; il n'y a pas de réglage de taille de texte. Les suffixes des grands nombres se confondent : des joueurs mélangent « Sx » et « Sp » [104] ; notre GDD les met côte à côte (§4.2).

### Ce qu'on reprend

1. **Passer à Unified Lighting tout de suite** : régler `LightingStyle = Soft` et `PrioritizeLightingQuality = false` explicitement, essayer Realistic seulement après mesure sur une vraie PS4, et mettre à jour ensemble le GDD (§11.3, §10.6), le contrat et les tests qui vérifient l'ancien réglage [91].
2. **Chaque Grand Splorch embellit le ranch pour toujours** : paliers de ranch aux R = 1, 3, 5, 10, 15, 20 qui ne repartent jamais de zéro (clôture, arche de portail avec le palier, tour ou 2e niveau au R5, 3e au R10, dôme Néon au R15, couronne flottante au R20), construits en formes simples, visibles depuis la place [97][77].
3. **Un signe de prestige porté par le joueur**, visible de loin (halo de Sell Lemons [46], auras de Clean the Squishies [107]) : un petit halo de gelée en orbite dont la couleur change aux paliers de R, dans le budget de particules (GDD §12.9).
4. **Deux familles de décorations** : les décorations actuelles à +5 % (remises à zéro) et une famille « Déco perso » **purement décorative, gardée pour toujours**, gagnée au Squishydex, aux jours de Plop et aux événements, toujours à résultat connu (l'expression de soi de Grow a Garden [99], sans caisse au hasard).
5. **Rareté et mutation lisibles à 3 m par trois canaux à la fois** : couleur, matériau (Néon, Glass, Foil) et mouvement ou lueur (Adopt Me [101]), en respectant la règle du GDD : 3 changements de couleur par seconde au plus, version fixe en Mouvement réduit.
6. **Le look « simulateur » construit en code avec les nouveaux outils** : par bouton, `UICorner` 14-18 px, `UIStroke` 3 px bleu nuit, `UIGradient` clair en haut et foncé en bas, `UIShadow` décalée de 6 px vers le bas ; le 2e contour vient d'un cadre parent ; dégradés radiaux pour les révélations et les anneaux de rareté [92][93][108].
7. **Une feuille de style unique** (couleurs, polices FredokaOne et LuckiestGuy, rayons, épaisseurs, cadre de focus), et le costume d'hiver « Frost & Sprinkles » comme **changement de thème** : moins de valeurs écrites à la main dans chaque écran, donc moins de bugs d'affichage [94][95].
8. **Animations de construction en cascade** : chaque pièce d'une décoration sort de 8 studs sous le sol avec 0,03-0,05 s de décalage, dépasse à 1,15 puis revient à 1, un son qui monte à chaque pièce [66].
9. **Appliquer le schéma « bébé » aux squishies et tester avec des enfants** : essayer des yeux de 0,26 à 0,30 D posés au centre du corps ou juste dessous, au lieu de 0,22 D à +0,12 D (GDD §5.2) [105] (inférence à vérifier par un test).
10. **Grands nombres lisibles à la télé** : une couleur par famille de suffixes (K-M blanc, B-T or, Qa-Qi rose, Sx et au-delà cyan), jamais Sx et Sp côte à côte sans couleur différente, et le mot entier sur les bannières (déjà au GDD §4.2) [104].
11. **Un réglage « Grand texte »** (×1,25), seulement si les tests d'écran le vérifient à chaque résolution et dans les deux langues [103].

---

## 6) Rétention et contenu

### 6.1 Ce que font les leaders

- **Steal An Egg ajoute une activité chaque samedi, pas seulement des familiers.** Update 7 (03/10/2026) : nouveau biome avec 8 familiers, quêtes, chasse aux papillons. Update 8 (10/10) : montures, courses gratuites toutes les 30 min, **piste gratuite de 14 paliers** (« Win Pass »). Update 9 (17/10) : dimension d'Halloween avec 35 familiers. Update 10 (24/10) : manoir, pêche, **65 paliers de récompenses**, boss en 2 phases, fusion à 2 joueurs. Environ **10 mises à jour numérotées en ≈ 14 semaines** depuis la sortie du 25/07/2026 [112][113].
- **Deux rendez-vous par semaine** chez Steal a Brainrot : la mise à jour du samedi avec son Admin Abuse, et un petit « Taco Tuesday » le mardi, chacun de 30 à 45 min [116]. Update 73 annoncée pour le 31/10/2026 [116] ; depuis la sortie du 16/05/2025, cela fait à peu près une mise à jour par semaine (notre calcul).
- **L'index est une cérémonie de récompense** : dans Steal An Egg, chaque nouvelle espèce brille jusqu'à ce qu'on appuie sur « Réclamer », un biome complet donne un bonus et un skin exclusif, un compteur montre « 5/86 » [114]. Dans Steal a Brainrot, chaque section complète ajoute +0,5× au multiplicateur et des skins de base se débloquent ; mais les seuils **bougent** quand on ajoute des brainrots [115].
- **Grow a Garden fait payer la rétention** : passe de saison à 749 R$ (50 paliers, ≈ 35 jours, points seulement par les quêtes du jour), saut de palier à 49 R$, passe entier à 1 699 R$ ; série de connexions de 7 jours **sans rattrapage**, qu'on peut restaurer pour ≈ 99 R$ (Nouvel An 2025-2026) [118][119].
- **Ride A Pet** : 5 météos de 5 minutes qui donnent les mutations ; récompenses d'index ; un seul passe en vente [121].
- **Le modèle d'événement de saison d'un classique** (Car Dealership Tycoon, Halloween du 17/10 au 14/11/2026) : une monnaie d'événement ramassée sur la carte, une course, des pistes de quêtes, une série de connexion de 7 jours, une boutique d'événement avec **une** voiture exclusive, et une « Partie 2 » à mi-parcours [34].
- **L'ouverture des meilleurs tycoons** : on possède quelque chose à construire en moins de 45 s, le revenu par seconde est visible tout de suite, et un objectif « prochaine amélioration » est toujours à l'écran [133].

### 6.2 Les chiffres et règles de la plateforme

- **Repères GameAnalytics 2026** (août 2025-juillet 2026) : rétention médiane J1 10,3 %, J7 1,6 %, J30 0,5 % ; session médiane 9,8 min ; 1,56 session par joueur et par jour [128].
- **La découverte de Roblox récompense la fidélité ET une monétisation durable, ensemble** (20/08/2026) ; les joueurs venus par la publicité ne comptent pas [127].
- **Les notifications push sont réservées aux 13 ans et plus** : elles n'atteignent pas la plupart de nos joueurs de 8 à 12 ans [129].
- **Creator Rewards** : 5 R$ par joueur qualifié et par jour, seulement si notre jeu est **parmi les 3 premiers** qu'il ouvre ce jour-là (et s'il a dépensé au moins 9,99 $ en 60 jours) [126].

### Ce qu'on reprend

1. **Chaque samedi ajoute une activité, pas seulement une espèce** (Steal An Egg [112][113]) : modes de la semaine en données qui réutilisent nos systèmes (course de Wobblers en monture, boss de gelée façon MEGA, chasse aux squishies cachés dans un quartier, recette de fusion à 2 joueurs), chacun avec une **piste gratuite de 10 à 15 paliers, toutes les récompenses visibles d'avance**, publiés comme les espèces (`release`, GDD §7.6).
2. **Un grand rendez-vous et un petit chaque semaine** (Steal a Brainrot [116]) : garder la Jelly Moon et ajouter un court événement automatique en milieu de semaine (20 min, plus de Golden Wobblers), toujours en plusieurs séances avec rattrapage pour qu'aucun enfant ne joue à 3 h du matin.
3. **Le Squishydex en cérémonie** (Steal An Egg [114]) : chaque nouveau tampon brille jusqu'à ce qu'on appuie sur ✕ « Réclamer » (petite récompense, son, vibration) ; chaque famille complète donne aussi un cosmétique visible ; un grand compteur « x / 260 ». **Ne jamais déplacer un seuil** quand on ajoute des espèces (le GDD §4.17 a raison) [115].
4. **Un modèle d'événement de saison réutilisable** (Car Dealership Tycoon [34]) : monnaie d'événement ramassée dans Wobbleton, mini-jeu ou course, pistes de quêtes, boutique d'événement avec **un** objet vedette, « Partie 2 » à mi-parcours. **Tout se gagne gratuitement** ; la monnaie d'événement ne se vend jamais.
5. **Une piste de saison gratuite dès le lancement si possible**, la piste payante seulement décorative, sans saut de palier ni de quête contre des Robux (le GDD prévoit ≈ 399 R$ en janvier) [118].
6. **Des rappels dans le jeu, pas de notifications push** [129] : en partant ou dans le menu, une carte « La prochaine fois » (compte à rebours du samedi, espèce qui arrive, prochain objectif) ; sur la place, un tableau des événements des 2 semaines à venir ; chaque Jelly Moon déclarée comme *Experience Event*.
7. **Être le premier jeu de la journée** [126] : rituel du jour fini en moins de 30 s à la connexion (Nourrir Plop + écran de retour). Compter les jours au total, jamais en série (le GDD §7.3 a raison ; Grow a Garden vend la restauration d'une série [119]).
8. **Garder l'ouverture « classique »** : quelque chose à soi en moins de 45 s, revenu par seconde visible, prochain achat toujours affiché [133] ; notre accueil le fait déjà (GDD §3 : récompense à 10 s, premier achat ≈ 20 s).

---

## 7) Monétisation juste

### 7.1 Ce que font les leaders

| Jeu | Ce qu'il vend (prix relevés sur des wikis et sites de revente, confiance moyenne à faible) | Source |
|---|---|---|
| **Steal An Egg** | ×2 Argent 399 R$, ×2 Vitesse de croissance 467 R$ ; **œuf d'Halloween en Robux seulement**, au hasard (99 R$ l'unité à 3 499 R$ les 50 ; familier le plus rare à 0,5 %), **retiré après l'événement** ; un critique YouTube parle d'achats « agressifs » ; revenu estimé ≈ 10,7 M$ sur 30 jours (estimation tierce) | [110][111] |
| **Steal a Brainrot** | VIP 499 R$, « 2x Money » 299 R$ qui **ajoute** +2× au multiplicateur au lieu de doubler ; chance du serveur de 249 à 999 R$ par palier | [117] |
| **Grow a Garden** | Passe de saison 749 R$, saut de palier 49 R$, restauration de série ≈ 99 R$ ; caisses de cosmétiques au hasard | [118][119][99] |
| **Pet Simulator 99** | Auto Farm 175 R$, VIP 400 R$, Lucky 275 R$ ; abonnement mensuel en argent réel (bloqué sur console) | [122] |
| **Ride A Pet** | Un seul passe en vente : radar infini 399 R$ (12/10/2026) | [121] |
| **Theme Park Tycoon 2** | Monétisation légère ; un critique parle de « zéro payant qui fait gagner » | [136] |
| **Notre GDD v1.3** | 4 passes « Pour toujours » (Pot automatique 149, ×2 Pièces 249, Grand Ranch 199, Selles et Traînées 99 R$), Squish Party 99 R$ (×2 pour tout le serveur, 3 par jour), tenues 49-79 R$ ; aucun hasard payant, aucune monnaie vendue, rien dans les 10 premières minutes (GDD §8) | GDD |

**Nouvelles règles et pressions (2026).**
- **Roblox Plus** a remplacé Premium le 30/04/2026 : 4,99 $ par mois, **−10 % puis −20 %** dès le 3e mois sur les passes et produits. La documentation officielle prévient : **un prix écrit en dur affiche le plein prix** alors que l'abonné paie moins ; il faut lire `PriceInRobux`, `UserBasePriceInRobux` et `PriceDiscountDetails` avec `GetProductInfoAsync` [124][125]. **C'est un bug d'affichage garanti si on ne le prévoit pas** (inférence).
- **Abonnements en Robux dès 49 R$**, au même prix sur toutes les plateformes, donc possibles sur console (≈ avril 2026) [123].
- **Objets aléatoires payants** : règles renforcées le 26/05/2026 ; les passes de chance sont des « objets qui modifient une probabilité » [130].
- **Plainte à la FTC** (mai 2026) contre la conception « qui maximise l'engagement » et une monnaie qui cache le vrai coût [131] ; les parents citent surtout les objets limités dans le temps et les objets premium des copains [132].
- **Échanges** : vérification d'âge obligatoire ; arnaques visant les 12-16 ans [134].
- Les plus gros jeux gagneraient 3 à 7 M$ par mois (Steal a Brainrot, T1 2026, estimation tierce) [137].

### Ce qu'on reprend

1. **Tous les prix des boutons d'achat viennent de l'API, par joueur** : `PriceInRobux`, et si une remise existe, l'ancien prix barré et une étiquette « Plus −10 % » ; bouton grisé si l'appel échoue, jamais un prix deviné ; tests avec un compte Plus au mois 1 et au mois 3, un prix changé pendant la session, un appel en échec [124][125]. Le GDD lit les prix à l'exécution (§8.1 n° 7) mais ne parle pas de la remise par joueur.
2. **Des étiquettes honnêtes** : « ×2 » double vraiment (pas comme le « 2x Money » de Steal a Brainrot [117]) ; chaque carte dit exactement ce qu'on reçoit et porte « Pour toujours ».
3. **Garder nos prix sous le marché** : ×2 Pièces 249 R$ contre 299-399 R$ chez les leaders, Pot automatique 149 R$ contre Auto Farm 175 R$ [110][117][122].
4. **Garder le boost payant « pour tout le serveur », sans chance** : la Squish Party garde l'attrait social de la « chance du serveur » de Steal a Brainrot [117], sans probabilité payante.
5. **Piste de saison payante seulement décorative**, sans saut de palier, sans restauration de série [118][119].
6. **Le confort de base reste gratuit** : sur console, acheter à distance n'est pas un luxe ; Sell Lemons le vend 459 R$ [45]. Chez nous, il passe par l'écran central d'améliorations, gratuit.
7. **Pas d'abonnement au lancement** (inférence) : possible techniquement [123], mais les achats récurrents sont la première plainte des parents [132] ; à revoir avec le propriétaire.

---

## 8) Console

### 8.1 Qui joue, et ce qui a changé

- **Part des joueurs** : ≈ 3 % sur console (exercice 2024, dernier chiffre officiel ; RoWatcher redonne ≈ 3 % au 4e trimestre 2025) [138][135]. GameAnalytics 2026 : 0,43 % de joueurs sur console seulement, 3,69 % qui l'utilisent au moins une fois (vu en extrait) [128].
- **En nombre, c'est un grand jeu console** : 4e jeu le plus joué sur PlayStation et 5e sur Xbox aux États-Unis en 2025 (Circana) ; top 2 des téléchargements gratuits du PS Store 2025 aux États-Unis et en Europe ; n°1 en heures de jeu sur PC + PlayStation + Xbox au 1er semestre 2026 (4,05 milliards d'heures) [139][140][141].
- **Applis natives** : Xbox Series X|S en septembre 2025, **PS5 le 14/04/2026** (chargement jusqu'à 30 % plus rapide, vibrations DualSense par les outils de Roblox) [142]. Aucune source fiable ne garantit la 4K ou 60 images/s : les performances dépendent de chaque jeu [39][40].
- **Ce que PlayStation a mis en avant** : des **autocollants** au lieu de taper au clavier (Dandy's World), un verrou de caméra adapté à la manette [143].
- **Règles de Roblox** (lues le 1/11/2026) : joueur à 2,5-3 m, tout atteignable avec 4 directions + valider + retour, icônes de la manette du joueur, vibrations sans excès, sons de navigation, **informations de maturité obligatoires** sous peine de retrait des consoles [64].
- **Ce qui est dépassé dans notre GDD** :
  - `GuiService:IsTenFootInterface()` est **obsolète** ; Roblox dit de ne pas s'en servir pour savoir si on est sur console. Les remplaçants : `UserInputService.PreferredInput` et `GuiService.ViewportDisplaySize` [144]. Le GDD (§10.6) l'appelle « la seule détection sûre d'une console » ; heureusement, la disposition ne change pas selon l'appareil.
  - Le réglage **Taille du texte** du joueur (`PreferredTextSize`) **n'agit pas** sur un texte en `TextScaled`, et peut faire déborder un texte qui ne l'est pas [145].
  - Le réglage de zone sûre de Roblox ne protège pas du débordement des télés (overscan) ; Microsoft compte ≈ 90 % de l'écran comme zone sûre [157][62]. Notre marge manuelle de 5 % est la bonne réponse.
- **Pannes connues** : curseur virtuel qui fait défiler les listes de travers ou fait planter un bouton [146] ; ○ qui fait **quitter le jeu** juste après l'arrivée sur PlayStation [147] ; avec les nouveaux contrôles, **le stick gauche fait bouger le personnage pendant qu'on navigue dans un menu** [148] ; mémoire saturée à l'arrivée qui fait planter d'abord les PlayStation (erreur 260) [156].
- **Chat** : texte et voix existent maintenant sur console, mais le chat demande une **vérification d'âge** partout depuis janvier 2026 ; le chat intégré à la plateforme sera **obligatoire en mai 2027** [149][158]. Comptes Kids et Select mondiaux depuis juin 2026 ; jeux sans classification injouables depuis le 30/09/2025 [150][151].
- **Serveurs presque vides** : un joueur qui coupe le jeu multiplateforme n'est mis qu'avec des joueurs PlayStation (ou Xbox) [152].
- **Pas de jeu à plusieurs sur une seule console** (ni écran partagé ni multijoueur local) [153].
- **Pas de vignettes vidéo sur console**, pas de capture vidéo Roblox sur console [154].
- **Vibrations** : `HapticEffect` est l'outil officiel (effets d'interface, collision, explosion, forme libre) [155]. Les gâchettes adaptatives ne sont confirmées par aucune documentation Roblox.

### Ce qu'on reprend

1. **Détecter l'appareil avec `PreferredInput` et `ViewportDisplaySize`** et ne changer les icônes qu'au changement d'entrée, pour éviter le clignotement ; garder `IsTenFootInterface()` seulement comme indice pour l'analytique, sous `pcall` [144].
2. **Tester les écrans avec la taille de texte du joueur au maximum** (Medium et Largest), en plus des 3 résolutions et des 2 langues ; aucun texte coupé ni chevauchement [145][103].
3. **Bloquer ○ dans nos menus et pendant les premières secondes après le chargement**, ne jamais lier Options, et **figer le personnage quand un menu a le focus** [147][148][159].
4. **Garder la navigation faite main** (curseur virtuel coupé, `SelectionGroup`, liens `NextSelection` explicites) [146] : le GDD le fait (§10.6).
5. **Remplacer la saisie par des signaux** (autocollants et emotes) [143] : nos 3 emotes vont dans ce sens ; on peut en ajouter sur une roue simple plus tard.
6. **Toute fonction sociale et tout événement doivent marcher à 1-3 joueurs** [152] : le GDD le fait déjà pour le MEGA (objectif selon les joueurs actifs), la jauge et les Wild Wobblers.
7. **Des grands moments faits pour le canapé** : grandes révélations centrées, lisibles à 3 m par le frère ou le parent qui regarde, boucles courtes pour que la manette change de mains (inférence d'après [153]).
8. **Une page de jeu qui marche sans vidéo** : icône et vignettes lisibles sur une télé [154].
9. **Avant la première publication** : questionnaire de maturité (cible Minimal), console cochée seulement après les tests sur vraie console [64][151] (déjà au GDD §18).
10. **Peu de mémoire à l'arrivée** : peu de pièces, rien de lourd au chargement (le GDD vise 4 500 pièces) ; surveiller la mémoire par plateforme après la sortie [156].

---

## 9) Zéro bug d'affichage : ce que les autres nous apprennent

Le propriétaire veut zéro bug, et Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration. Les recherches montrent les mêmes familles de bugs chez les plus grands, et leurs causes.

| Cause vue ailleurs | Exemple | Règle pour nous |
|---|---|---|
| Tri qui se trompe après un rafraîchissement | Clash of Clans classe des améliorations payables sous des non payables (oct. 2026) [60] | Tri **stable** : payables d'abord, puis les moins chères ; la sélection reste sur la même carte après un achat |
| Compteur qui repart de 0 | Clash of Clans, au changement d'onglet [60] | Jamais de ré-animation d'un compteur depuis 0 ; le défilement part toujours de la dernière valeur affichée |
| Prix faux à l'écran | Roblox Plus : plein prix affiché, prix réduit payé [125] | Prix lus par joueur, remise affichée, test avec un compte Plus |
| Texte coupé ou qui saute de taille | `TextScaled` qui ignore la taille de texte du joueur [145] ; nombres longs (« 999,9 Qa ») | Largeur fixe réservée pour la plus longue valeur formatée ; un seul formateur de nombres (le GDD l'a, §4.2) ; tests avec la taille de texte au maximum |
| Achat muet | « Buy Max » sans retour [61] | Toujours un retour chiffré, ou la raison du refus |
| Bouton qui reste « appuyé » | Clic à la manette sur Roblox [65] | Test du focus après chaque achat, après Max et après un rafraîchissement de la liste |
| Mise en page Roblox | Plusieurs layouts dans un même parent (seul le premier compte), `ScrollingFrame` en taille automatique qui déborde, animation qui s'arrête avant sa valeur finale [161][66] | Un seul layout par parent ; valeurs finales posées à la fin de chaque animation ; captures d'écran comparées à chaque palier de R et aux plus grands nombres |

---

## 10) Ce qu'on ne sait pas (à surveiller)

- **Le nombre exact d'améliorations des hits à leur sortie** : aucune source ne le donne ; les guides comptent après des semaines de mises à jour.
- **La rétention réelle des leaders** (J1, J7, J30) : non publiée ; seuls les repères de GameAnalytics existent [128].
- **Les ventes réelles** : seulement des estimations tierces [111][137].
- **La part exacte de la console en 2026** : le dernier chiffre officiel date de l'exercice 2024 [138].
- **Le rebirth de Steal An Egg** : non vérifié [50].
- **Le résultat du concert des Jonas Brothers** (31/10/2026) : pas publié au 1er novembre [6].
- **Le son et la mémoire des PS4 et Xbox One** : la recherche sur les visuels a épuisé son quota avant d'y arriver ; à refaire.
- **Le test avec des enfants** : toutes nos inférences sur la lisibilité, le mignon et la compréhension des écrans doivent être vérifiées avec des enfants de 8 à 13 ans devant une télé (GDD §18, test M14).

---

## 11) Sources

Les numéros renvoient aux crochets du texte. Les pages de roblox.com, create.roblox.com et devforum.roblox.com ont été vues en **extraits de recherche** (domaines bloqués depuis notre session) ; celles de `raw.githubusercontent.com/Roblox/creator-docs` ont été lues en entier le 1/11/2026.

**Classement et pourquoi ça marche**
1. OtakuKart (citant le rapport Aream & Co. du 3e trimestre 2026), Steal An Egg 6 milliards de visites et pic de 14,2 M — https://otakukart.com/robloxs-steal-an-egg-reaches-6-billion-visits-and-14-2-million-peak-concurrent-players/ — octobre 2026
2. clip.dor.gg, classement des jeux Roblox populaires — https://clip.dor.gg/en/blog/roblox-popular-games-ranking — 20/10/2026
3. stealaneggguide.wiki, qui a fait Steal An Egg — https://stealaneggguide.wiki/guides/who-made-steal-an-egg/ — 2026
4. games.gg, guide débutant Steal An Egg — https://games.gg/roblox/guides/steal-an-egg-beginner-guide/ — août-octobre 2026
5. Timesaver, Admin Abuse de Steal An Egg — https://timesaver.gg/blog/steal-an-egg-admin-abuse — septembre 2026
6. Guinness World Records, concert des Jonas Brothers — https://www.guinnessworldrecords.com/news/2026/10/will-the-jonas-brothers-make-music-history-with-a-record-breaking-roblox-concert — octobre 2026
7. Guinness World Records, record de joueurs simultanés pour un jeu Roblox — https://www.guinnessworldrecords.com/world-records/503322-most-concurrent-players-for-a-videogame-made-in-roblox — 11/10/2025
8. PocketGamer.biz, Steal a Brainrot dépasse 25 M — https://www.pocketgamer.biz/robloxs-steal-a-brainrot-becomes-first-game-to-surpass-25m-concurrent-players — 07/10/2025
9. Sportskeeda, rebirth 1 de Steal a Brainrot — https://www.sportskeeda.com/roblox-news/steal-brainrot-rebirth-1-guide — 2025
10. AllThings.How, prochaine mise à jour de Steal a Brainrot — https://allthings.how/steal-a-brainrot-next-update/ — octobre 2026
11. Rolimons, Grow a Garden — https://www.rolimons.com/game/126884695634066 — 2025-2026
12. Endgametools, joueurs de Grow a Garden — https://endgametools.com/en/roblox/players/grow-a-garden — 26/10/2026
13. Game Dev Reports (données Newzoo et RoMonitor), top des jeux Roblox 2025 — https://gamedevreports.substack.com/p/newzoo-top-roblox-games-in-2025 — 2025-2026
14. games.gg (citant la BBC), Grow a Garden — https://games.gg/ar/news/grow-a-garden-roblox-most-popular-game/ — 2025
15. GamesBeat, entretien avec Janzen Madsen (Grow a Garden) — https://gamesbeat.com/janzen-madsen-interview/ — 2025
16. Rolimons, Grow a Garden 2 — https://www.rolimons.com/game/97598239454123 — 2026
17. RoVitals, Grow a Garden 2 — https://rovitals.com/game/97598239454123 — septembre 2026
18. MMOexp, pourquoi Grow a Garden 2 perd des joueurs — https://www.mmoexp.com/News/grow-a-garden-2-is-losing-players-what-really-happened-to-the-roblox-hit.html — 2026
19. AllThings.How, calendrier des événements de Ride A Pet — https://allthings.how/ride-a-pet-events-schedule/ — 24/10/2026
20. AllThings.How, progression et 7 rebirths de Ride A Pet — https://allthings.how/ride-a-pet-progression-guide-best-pets-and-all-7-rebirths/ — octobre 2026
21. Beebom, rebirth de Ride A Pet — https://beebom.com/ride-a-pet-rebirth-guide/ — 2026
22. BloxByte (studio de Sell Lemons) — https://www.bloxbyte.com/ — 2026
23. selllemonswiki.wiki, guide du rebirth de Sell Lemons — https://selllemonswiki.wiki/guides/rebirth-guide/ — mis à jour le 23/10/2026
24. AllThings.How, Void Evolution de Sell Lemons — https://allthings.how/sell-lemons-void-evolution-unlock-requirements-and-fruit-multipliers/ — juin-octobre 2026
25. Rolimons, Build a Zoo — https://www.rolimons.com/game/105555311806207 — 2025-2026
26. CommonSenseGamer, guide de Build a Zoo — https://commonsensegamer.com/build-a-zoo-guide/ — 2025-2026
27. ts2.tech (citant Rolimons), Plants vs Brainrots — https://ts2.tech/en/robloxs-newest-phenomenon-plants-vs-brainrots-breaks-records-heres-why-everyones-obsessed/ — septembre 2025
28. RoWatcher, Fish It! — https://rowatcher.com/games/6701277882/upd-fish-it/dying — octobre 2026
29. Tubefilter, le record de 47 M de joueurs — https://www.tubefilter.com/?p=188004 — août 2025
30. RBLXSTAT, jeux Roblox tendance — https://rblxstat.com/lists/trending-roblox-games — 10/10/2026
31. RoWatcher, jeux les plus joués en direct — https://rowatcher.com/news/the-most-popular-roblox-games-right-now-ranked-by-live-players — juin 2026
32. RoWatcher, Restaurant Tycoon 3 — https://rowatcher.com/games/7094518649/restaurant-tycoon-3-boss-battle/dying — octobre 2026
33. Rolimons, Car Dealership Tycoon — https://www.rolimons.com/game/1554960397 — octobre 2026
34. Of Zen and Computing, citrouilles de Car Dealership Tycoon (Halloween 2026) — https://www.ofzenandcomputing.com/how-to-get-pumpkins-in-car-dealership-tycoon-roblox/ — octobre 2026
35. Bloxodes, Theme Park Tycoon 2 — https://bloxodes.com/stats/games/theme-park-tycoon-2-31970568 — 2026
36. RoWatcher, Theme Park Tycoon 2 — https://rowatcher.com/games/31970568/theme-park-tycoon-2/dying — octobre 2026
37. RoWatcher, Retail Tycoon 2 — https://rowatcher.com/games/2092410051/retail-tycoon-2/dying — 2026
38. Kinzoo, guide des jeux « brainrot » pour les parents — https://www.kinzoo.com/blog/what-are-brainrot-games-a-parents-guide-to-the-roblox-trend — 2025-2026
39. GamesBeat, Roblox natif sur PS5 — https://gamesbeat.com/?p=321053 — 14/04/2026
40. PSU, appli PS5 native de Roblox — https://www.psu.com/news/roblox-ps5-native-app-now-available-from-ps-store-offers-up-to-30-faster-load-times — 14/04/2026
41. RoWatcher, la vague brainrot s'éteint-elle ? — https://rowatcher.com/news/is-the-brainrot-trend-dying-what-ccu-data-from-three-top-games-reveals — 2026

**Améliorations**
42. AllThings.How, Sell Lemons : argent, rebirth, évolution — https://allthings.how/sell-lemons-on-roblox-how-to-farm-cash-rebirth-and-evolve/ — 2026
43. Bloxron, sources de revenu de Sell Lemons — https://bloxron.com/sell-lemons/income-sources — mis à jour le 28/06/2026
44. games.gg, Powers de Sell Lemons — https://games.gg/roblox/guides/sell-lemons-powers-guide/ — 2026 ; Beebom, liste des Powers, https://beebom.com/sell-lemons-powers/ — 2026 (source unique pour certains prix)
45. AllThings.How, Remote Buy dans Sell Lemons — https://allthings.how/how-to-get-remote-buy-in-sell-lemons-robux-and-investor-costs/ — 2026
46. AllThings.How, Ascension de Sell Lemons — https://allthings.how/sell-lemons-ascension-how-to-unlock-it-and-every-reward/ — 2026
47. Bloxswaps, tapis de course de Steal An Egg — https://bloxswaps.com/blog/steal-an-egg-treadmills-and-how-much-each-one-costs — août-octobre 2026
48. Lootester, Update 4 de Steal An Egg — https://lootester.com/steal-an-egg-update-4/ — 12/09/2026
49. stealanegg-wiki.com, améliorations de base — https://stealanegg-wiki.com/wiki/base-upgrades — septembre-octobre 2026
50. stealanegg.app, rebirth (aucun rebirth vérifié) — https://stealanegg.app/guides/rebirth/ — 2026 ; voir aussi bo3.gg, https://bo3.gg/games/articles/steal-an-egg-progression-guide
51. AllThings.How, plafonds de niveau d'Escape Tsunami for Brainrots — https://allthings.how/every-max-level-cap-in-escape-tsunami-for-brainrots-explained/ — 2026
52. Of Zen and Computing, emplacements de base d'Escape Tsunami — https://ofzenandcomputing.com/how-to-upgrade-base-slots-escape-tsunami/ — 2026
53. AllThings.How, Merge a Nuke — https://allthings.how/how-to-become-overpowered-in-merge-a-nuke-roblox/ — juin-août 2026
54. Sportskeeda, rebirth de Plants vs Brainrots — https://www.sportskeeda.com/roblox-news/plants-vs-brainrots-rebirth-requirements-rewards — 2025
55. RT3 Fandom, employés de Restaurant Tycoon 3 — https://rt3.fandom.com/wiki/Workers — octobre 2025
56. Rolimons, Upgradex — https://www.rolimons.com/game/128718594394791 — juillet-septembre 2026
57. Game Developer (Kongregate), les maths des jeux idle, partie I — https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i — 2016
58. AdVenture Capitalist Fandom, entreprises — https://adventure-capitalist.fandom.com/wiki/Businesses — ancien
59. Egg, Inc. Fandom, prestige — https://egg-inc.fandom.com/wiki/Prestige?oldid=9210 — ancien
60. Supercell, nouvelle interface de Clash of Clans — https://supercell.com/en/games/clashofclans/blog/news/weve-revamped-the-clash-of-clans-user-interface/ — 08/10/2026
61. Pixelabor (itch.io), Buy Max — https://pixelabor.itch.io/empire-idle/devlog/210170/buy-max — 2020-2025 (confiance faible)
62. Microsoft, concevoir pour la télé et la Xbox — https://learn.microsoft.com/en-us/windows/apps/design/devices/designing-for-tv — consulté en novembre 2026
63. Amazon Fire TV, règles de design — https://developer.amazon.com/docs/fire-tv/design-and-user-experience-guidelines.html — consulté en novembre 2026
64. Roblox creator-docs, règles pour la console — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/publishing/console-guidelines.md — lu le 01/11/2026
65. DevForum Roblox, bouton à la manette qui reste sélectionné — https://devforum.roblox.com/t/ui-gamepad-support-button-not-deselecting-is-bug/4810126 — 2026
66. Coddy, animation de construction d'un tycoon — https://coddy.tech/learn/courses/roblox_game_factory_tycoon/build_animation — non daté ; DevForum « Tycoon animations », https://devforum.roblox.com/t/tycoon-animations/833635 — 2020-2026

**Renaissance**
67. AllThings.How, rebirth de Sell Lemons (Joe l'Alien, Investisseurs) — https://allthings.how/rebirth-in-sell-lemons-joe-the-alien-investors-and-when-to-reset/ — juin-octobre 2026
68. RoWatcher, Sell Lemons — https://rowatcher.com/games/7395930870/sell-lemons — 19/10/2026
69. AllThings.How, calendrier des événements de Sell Lemons — https://allthings.how/sell-lemons-events-schedule/ — 22/10/2026
70. Rolimons, Sell Lemons — https://www.rolimons.com/game/79268393072444 — 2026
71. Bloxinformer, rebirths de Steal a Brainrot — https://bloxinformer.com/wikis/steal-a-brainrot/rebirth/ — 2025-2026
72. Beebom, rebirths de Steal a Brainrot — https://beebom.com/steal-a-brainrot-rebirth-guide-levels-and-rewards/ — 2026
73. sabexistcount, liste des rebirths de Steal a Brainrot — https://sabexistcount.com/wiki/steal-a-brainrot-rebirth-list — septembre 2026
74. Pocket Tactics, rebirth de Plants vs Brainrots — https://www.pockettactics.com/plants-vs-brainrots-rebirth — 2025
75. EverybodyWiki, jeux Roblox par record de joueurs — https://en.everybodywiki.com/List_of_Roblox_games_by_peak_concurrent_users — 2025-2026 ; Namu Wiki, Plants vs Brainrots, https://en.namu.wiki/w/Plants%20Vs%20Brainrots (confiance faible)
76. Pro Game Guides, rebirth de Ride A Pet — https://progameguides.com/roblox/ride-a-pet-rebirth/ — 2026
77. Bloxodes, rebirths de Ride A Pet — https://bloxodes.com/wiki/ride-a-pet/rebirths — 2026
78. Compte officiel X de Grow a Garden, annonce de l'Ascension — https://x.com/GrowaGardenRblx/status/1961794089285722260 — 30/08/2025
79. Compte officiel X de Grow a Garden, notes de la version 1.22.3 — https://x.com/GrowaGardenRblx/status/1965541408627965993 — 09/09/2025
80. Roonby, les joueurs fâchés par l'Ascension de Grow a Garden — https://roonby.com/2025/09/03/players-are-mad-about-grow-a-garden-new-ascension-features/ — 03/09/2025
81. Bloxguides, Pet Simulator 99 — https://bloxguidesgg.com/games/pet-simulator-99 — 2025-2026
82. Sportskeeda, rebirth 9 de Pet Simulator 99 — https://www.sportskeeda.com/roblox-news/news-pet-simulator-99-kawaii-world-new-world-rebirth-9 — 2026
83. mergeanuke.cc, rebirth de Merge a Nuke — https://mergeanuke.cc/rebirth — août 2026 ; RoVitals donne un record de 65 625 le 15/08/2026 (confiance faible)
84. Of Zen and Computing, rebirth de Break a Lucky Block — https://ofzenandcomputing.com/break-a-lucky-block-rebirth-guide/ — janvier-juillet 2026
85. Pro Game Guides, rebirth de Mining Simulator 2 — https://progameguides.com/roblox/how-to-rebirth-fast-in-roblox-mining-simulator-2/ — non daté ; Mobile Matters, Arm Wrestle Simulator, https://mobilematters.gg/roblox/all-rebirths-arm-wrestle-simulator — non daté
86. Pro Game Guides, Auto Rebirth de Clicker Simulator — https://progameguides.com/roblox/how-to-get-more-rebirths-in-clicker-simulator/ — non daté
87. Game Developer (Kongregate), les maths des jeux idle, partie III — https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii — 2016
88. dev.to (aguier), « 7 jeux idle en 30 jours » — https://dev.to/aguier/i-built-7-idle-games-in-30-days-what-i-learned-about-incremental-design-5d3f — 2025-2026 (confiance faible)
89. beatcopgame, rebirth de Build a Base and Steal — https://beatcopgame.com/build-a-base-and-steal-rebirth-guide-all-requirements-rewards-and-how-to-rebirth/ — août 2026
90. AllThings.How, rebirth de Military Tycoon — https://allthings.how/military-tycoon-how-to-rebirth-fast-and-progress-in-roblox/ — 2026

**Visuels**
91. DevForum Roblox, « Unified Lighting is Fully Live » — https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512 — juillet 2025 (bêta janvier 2025)
92. DevForum Roblox, ombres et coins séparés en version complète — https://devforum.roblox.com/t/full-release-new-ui-capabilities-shadows-individual-corners/4636263 — 23/06/2026
93. DevForum Roblox, dégradés d'interface améliorés — https://devforum.roblox.com/t/full-release-upgraded-ui-gradients/4846594 — fin octobre 2026
94. DevForum Roblox, styles publiables — https://devforum.roblox.com/t/client-beta-you-can-now-publish-styles-in-your-experience/3901480 — 20/01/2026
95. DevForum Roblox, StyleQuery en version complète — https://devforum.roblox.com/t/full-release-stylequery-more-styling-features/4566519 — 11/05/2026
96. DevForum Roblox, feuille de route des créateurs, automne 2026 — https://devforum.roblox.com/t/creator-roadmap-2026-fall-update/4880208 — septembre 2026
97. Lootester, rebirths de Steal a Brainrot 2026 — https://lootester.com/steal-a-brainrot-rebirth-guide-2026/ — octobre 2026
98. TechWiser, skins de base de Steal a Brainrot — https://techwiser.com/steal-a-brainrot-base-skins-how-get-guide/ — 2026
99. Insider Gaming, cosmétiques de Grow a Garden — https://insider-gaming.com/grow-a-garden-latest-update-adds-cosmetic-crates/ — 24/05/2025 ; Wikipédia (textures à picots), https://en.wikipedia.org/wiki/Grow_a_Garden
100. GameRant, mutations de Steal An Egg — https://gamerant.com/roblox-steal-an-egg-all-mutations-how-to-get-them/ — 2026
101. Sportskeeda, Mega Neon dans Adopt Me — https://sportskeeda.com/roblox-news/mega-neon-pet-adopt-me — non daté
102. Kotaku, critique de Steal a Brainrot — https://kotaku.com/steal-a-brainrot-roblox-empire-review-popular-memes-1851787027 — 2025
103. Xbox Accessibility Guidelines 101 (texte) — https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/101 — consulté le 01/11/2026
104. game.guide, suffixes de Clicker Simulator — https://www.game.guide/clicker-simulator-number-suffixes — non daté
105. Borgi et al., « Baby schema in human and animal faces… », Frontiers in Psychology — https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2014.00411/full — mai 2014
106. Gamelandinsider, Find The Squishies — https://gamelandinsider.com/find-the-squishies-guide — juin 2026
107. Rolimons, « [AURA!] Clean the Squishies! » — https://www.rolimons.com/game/135038773889079 — 2026
108. DevForum Roblox, « How to recreate such UI style? » — https://devforum.roblox.com/t/how-to-recreate-such-ui-style/1943553 — 2022
109. GamesBeat, SLIM — https://gamesbeat.com/roblox-launches-scalable-graphics-for-rendering-more-realistic-and-detailed-worlds-exclusive/ — décembre 2025

**Rétention et monétisation**
110. stealanegg.net, passes de Steal An Egg — https://stealanegg.net/game-passes/ — août-octobre 2026
111. Blog vervado, œuf d'Halloween de Steal An Egg et ses chances — https://usa-vervado.myshopify.com/blogs/roblox/steal-an-egg-halloween-egg-store-odds-zombified-reroll — octobre 2026 ; Bloxrant, revenus estimés, https://bloxrant.com/roblox-top-earning-games — novembre 2026 (estimation)
112. Sportskeeda, notes de l'Update 8 de Steal An Egg — https://www.sportskeeda.com/roblox-news/steal-an-egg-update-8-patch-notes-mounts — 10/10/2026
113. Sportskeeda, notes de l'Update 10 de Steal An Egg — https://www.sportskeeda.com/roblox-news/steal-an-egg-update-10-patch-notes-halloween-part-2 — 24/10/2026
114. AllThings.How, récompenses de l'index de Steal An Egg — https://allthings.how/steal-an-egg-how-to-get-rewards-from-the-pet-index/ — août-octobre 2026
115. Bloxodes, skins de base de Steal a Brainrot (index) — https://bloxodes.com/wiki/steal-a-brainrot/base-skins — 2026
116. TheClick, calendrier des Admin Abuse de Steal a Brainrot — https://www.theclick.gg/steal-a-brainrot-admin-abuse-schedule/ — 2026 ; Eldorado, journal des mises à jour, https://www.eldorado.gg/blog/steal-a-brainrot-en/steal-a-brainrot-update-log/ — octobre 2026
117. Buffget, passes de Steal a Brainrot — https://buffget.com/news/steal-a-brainrot-gamepasses-guide-vip-and-2x-money-2026 — 2026 (confiance faible)
118. Sportskeeda, passe de saison 1 de Grow a Garden — https://www.sportskeeda.com/roblox-news/grow-garden-season-1-pass-all-tier-rewards-premium-price — septembre-novembre 2025
119. TechWiser, récompenses du Nouvel An de Grow a Garden — https://techwiser.com/grow-a-garden-new-years-daily-rewards-how-get/ — décembre 2025
120. vexu.gg, Sell Lemons (création de l'expérience le 18/03/2025) — https://www.vexu.gg/game/7395930870/sell-lemons — 2026
121. Bloxron, Ride A Pet — https://bloxron.com/ride-a-pet — octobre 2026
122. Pet Simulator Fandom, passes de Pet Simulator 99 — https://pet-simulator.fandom.com/wiki/Gamepasses_(Pet_Simulator_99) — août 2026
123. DevForum Roblox, abonnements payés en Robux — https://devforum.roblox.com/t/let-your-players-pay-for-subscriptions-within-experiences-in-robux/4552995 — vers avril 2026
124. Roblox Newsroom, Roblox Plus — https://about.roblox.com/newsroom/2026/04/introducing-roblox-plus-subscription — avril 2026
125. Roblox creator-docs, Roblox Plus (prix à lire par l'API) — https://github.com/Roblox/creator-docs/blob/main/content/en-us/production/monetization/roblox-plus.md — 2026
126. DevForum Roblox, Creator Rewards — https://devforum.roblox.com/t/introducing-creator-rewards-earn-more-by-growing-the-community/3777628 — juillet 2025
127. DevForum Roblox, mise à jour de la découverte — https://devforum.roblox.com/t/boost-your-discovery-by-building-games-people-want-to-play/4779042 — 20/08/2026
128. GameAnalytics, rapport Roblox 2026 — https://www.gameanalytics.com/reports/2026-roblox-report — données d'août 2025 à juillet 2026
129. Roblox creator-docs, Experience Notifications (13 ans et plus) — https://create.roblox.com/docs/production/promotion/experience-notifications — 2025-2026
130. DevForum Roblox, règles des objets aléatoires payants — https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622 — 26/05/2026
131. News Tribune, plainte d'associations à la FTC — https://www.newstribune.com/news/2026/may/22/child-safety-groups-want-ftc-to-investigate-roblox/ — 22/05/2026
132. Common Sense Media, guide de Roblox pour les parents — https://www.commonsensemedia.org/es/articulos/guia-esencial-de-roblox-para-padres — 2026
133. RoWatcher, les tycoons, le genre qui a construit Roblox — https://rowatcher.com/news/tycoon-games-the-genre-that-built-roblox-and-still-hasn-t-peaked — 2026
134. Roblox Help Center, échanges — https://en.help.roblox.com/hc/en-us/articles/203313310-Trading-on-Roblox — 2026
135. RoWatcher, mobile contre ordinateur en 2026 — https://rowatcher.com/news/mobile-vs-desktop-on-roblox-who-s-playing-what-in-2026 — données du 4e trimestre 2025
136. Rotrends, Theme Park Tycoon 2 — https://rotrends.com/game/31970568/Theme-Park-Tycoon-2 — août-septembre 2026 ; DungeonPath, comparatif des tycoons, https://dungeonpath.com/posts/pillar/roblox-tycoon-games-compared/ — 2026
137. RoWatcher, les jeux Roblox les plus rentables en 2026 — https://rowatcher.com/news/the-10-highest-earning-roblox-games-in-2026-and-what-they-mean-for-the-platform — 1er trimestre 2026 (estimations)

**Console**
138. PocketGamer.biz, 80 % des joueurs Roblox sur mobile — https://www.pocketgamer.biz/80-of-roblox-users-are-on-mobile-contributing-46-of-robux-revenue/ — exercice 2024
139. VGC, les jeux les plus joués sur PlayStation en 2025 — https://www.videogameschronicle.com/news/playstations-most-played-games-of-2025-are-identical-to-2024s-list/ — janvier 2026 ; GameSpot, PlayStation et Xbox, https://www.gamespot.com/articles/2025s-top-5-most-played-games-on-playstation-and-xbox-are-the-same-as-2024s-in-the-us/1100-6537207/
140. PlayStation Blog, meilleurs téléchargements du PS Store en 2025 — https://blog.playstation.com/2026/01/14/playstation-stores-top-downloads-of-2025/ — 14/01/2026
141. GameDev.net (Newzoo), Roblox le plus joué en heures sur PC et consoles — https://gamedev.net/news/6631-report-explores-how-roblox-can-maintain-older-players-as-it-becomes-most-played/ — mi-2026
142. PlayStation Blog, nouvelle version de Roblox sur PS5 — https://blog.playstation.com/2026/04/14/an-upgraded-version-of-roblox-launches-on-ps5-today/ — 14/04/2026
143. Spawnpoint, Roblox sur PS5 (Dandy's World, autocollants) — https://spawnpoint.be/roblox-ps5/ — 13-14/04/2026
144. Roblox creator-docs, GuiService (IsTenFootInterface obsolète) — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/GuiService.yaml — lu le 01/11/2026 ; entrées, https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/input/index.md
145. Roblox creator-docs, accessibilité (taille du texte) — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/publishing/accessibility.md — lu le 01/11/2026
146. DevForum Roblox, le curseur virtuel ignore le sens de défilement — https://devforum.roblox.com/t/gamepad-virtual-cursor-doesnt-respect-scrollingframescrollingdirection-xbox-playstation/2641826 — 2023-2026
147. DevForum Roblox, ○ qui fait quitter le jeu sur PlayStation — https://devforum.roblox.com/t/playstation-when-pressing-the-circle-button-right-after-joining-the-client-exits-the-experience/2645560 — vers octobre 2023
148. DevForum Roblox, le stick gauche fait bouger le personnage dans l'interface — https://devforum.roblox.com/t/playerscriptsuseinputactionsystem-wiggles-character-while-moving-left-controller-thumbstick-in-ui/4741047 — 2026
149. Roblox Newsroom, vérification d'âge pour le chat — https://about.roblox.com/newsroom/2025/11/roblox-requires-age-checks-limits-minor-and-adult-chat — novembre 2025
150. Roblox Newsroom, comptes Kids et Select dans le monde entier — https://about.roblox.com/newsroom/2026/06/age-based-roblox-kids-and-select-accounts-now-globally-available — juin 2026
151. GameRant, jeux non classés coupés le 30 septembre — https://gamerant.com/new-roblox-rating-system-unrated-games-disabled-on-september-30/ — septembre 2025
152. Roblox Help Center, FAQ PlayStation (jeu multiplateforme) — https://en.help.roblox.com/hc/en-us/articles/19816103303572-PlayStation-FAQ — 2026
153. DevForum Roblox, multijoueur local sur Xbox — https://devforum.roblox.com/t/local-multiplayer-on-xbox/72322 — ancien ; demande d'écran partagé, https://devforum.roblox.com/t/allow-for-split-screen-on-pc-and-console/3978866 — 2025
154. Roblox creator-docs, vignettes (pas de vidéo sur console) — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/production/publishing/thumbnails.md — lu le 01/11/2026 ; Roblox Help Center, capture vidéo, https://en.help.roblox.com/hc/articles/203314190
155. Roblox creator-docs, HapticEffectType — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/HapticEffectType.yaml — lu le 01/11/2026
156. DevForum Roblox, erreur 260 sur PlayStation et mobile — https://devforum.roblox.com/t/playstationmobile-players-receive-error-260-when-joining-public-servers-but-can-join-private-servers-normally/4054483 — fin 2025
157. Roblox creator-docs, ScreenInsets — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/enums/ScreenInsets.yaml — lu le 01/11/2026
158. GameBusiness.jp, chat intégré à la plateforme obligatoire en mai 2027 — https://www.gamebusiness.jp/article/2026/10/23/28425.html — 23/10/2026
159. Roblox creator-docs, Input Action System (Options et F9 réservés) — https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/input/input-action-system.md — mis à jour le 19/10/2026

**Compléments**
160. Rolimons, Ride A Pet (chiffre de 20 755 joueurs, en retard sur les autres suivis) — https://www.rolimons.com/game/124216119978534 — octobre 2026
161. Roblox Creator Hub, mise en page et apparence de l'interface (`UITextSizeConstraint`, un seul layout appliqué) — https://create.roblox.com/docs/ui/layout-and-appearance — 2026 (extrait de recherche) ; DevForum, taille automatique, https://devforum.roblox.com/t/automaticsize-studio-beta/790215?page=4 — 2020-2026
162. Roblox Fandom, My Hello Kitty Cafe — https://roblox.fandom.com/wiki/My_Hello_Kitty_Cafe — juin 2026 (confiance faible)
