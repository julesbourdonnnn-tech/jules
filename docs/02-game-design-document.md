# Raise a Squishy — Game Design Document

> **Document 02 : conception du jeu (GDD).** Version 1.2 du 1er novembre 2026. La version 1.1 a appliqué les critiques indépendantes (sécurité des enfants, console et ergonomie). La version 1.2 applique la **décision du propriétaire du 1er novembre 2026** : **console d'abord** (PS5 avec DualSense sur une télé, puis Xbox et PC ; pas de téléphone au lancement) et **zéro bug** au lancement. Cette décision passe avant l'étude de marché et le concept du jury quand ils se contredisent. Ce qui a changé, ce qui a été refusé et les questions ouvertes sont dans le **Journal de révision**, à la fin. Statut : à valider par le propriétaire, puis base de la production.
> Documents liés : [`01-analyse-marche-tycoon.md`](01-analyse-marche-tycoon.md) (étude de marché, citée « Étude §x ») et [`03-decision-du-jury.md`](03-decision-du-jury.md) (concept final au §8, idées greffées au §6, faiblesses corrigées au §7, calendrier au §8.10, risques au §9).
> Modèle de format : le GDD de Comet Conga (`/home/user/jules/roblox-game/docs/02-game-design-document.md`), sa couche console (`07-console-ps5.md`) et les leçons de son rapport qualité (`06-rapport-qualite.md`).
> **Règle de lecture.** Chaque chiffre de ce document est une **valeur de départ décidée**, à placer telle quelle dans `src/shared/Config/*`. Les valeurs d'économie sont vérifiées par la simulation Lune du §4.24, qui bloque la publication si un jalon sort de sa tolérance. Ensuite, les données réelles peuvent ajuster ces valeurs sans toucher au code.

**Conventions**
- Distances en *studs*. Temps en secondes (s), minutes (min) ou heures (h). Horaires en **UTC**.
- `floor` = arrondi à l'entier inférieur. Les monnaies sont calculées par le serveur seulement.
- Les noms propres de l'univers (Raise a Squishy, Wobbleton, Plop, les noms d'espèces, BOOP RUSH, MEGA SQUISH, Grand Splorch, Squishydex, Jelly Moon…) restent en anglais dans les deux langues : c'est notre propriété intellectuelle. Les mots du quotidien sont traduits (§15).
- Clé de configuration entre crochets, par exemple [`Balance.Press.Cooldown`].
- « R » = nombre de Grand Splorch déjà faits par le joueur (son niveau de renaissance).
- **px TV** = pixels d'un écran de 1920 × 1080, la référence de toute l'interface (§10.1). Sur un écran 4K, tout est 2 fois plus grand en pixels ; en 1280 × 720, 1,5 fois plus petit : la taille vue depuis le canapé ne change pas.
- Glyphes de la manette : noms PlayStation (✕ □ ○ △, L1 R1 L2 R2, croix ↑ → ↓ ←). À l'écran, le jeu montre toujours l'icône de la manette du joueur (§10.6).
- **Au lancement** = la colonne « Au lancement » du §8.10 du jury. Tout le reste est dans la liste « Plus tard » (§17).

**Glossaire**

| Terme | Sens |
|---|---|
| **Squishy** (pl. squishies) | Créature en gelée à élever. Elle grossit seule et rapporte des pièces |
| **Ranch** | La base personnelle du joueur. Personne d'autre n'y entre jamais |
| **Wobbleton** | La ville pastel au centre de la carte, entourée des 16 ranchs |
| **Big Plop** | La mascotte : un grand Plop à nœud papillon. Dans les textes du jeu, elle s'appelle toujours « Big Plop » |
| **Plop** | La première espèce (Jelly, Commun). Ton premier Plop est ton Meilleur Ami n° 1 d'office |
| **SPLORCH** (presser) | Appuyer sur un squishy : il s'écrase, rebondit et crache des pièces |
| **PERFECT** | Presser au sommet du rebond : bonus, jamais d'échec |
| **Dalle** (tile) | Pastille lumineuse au sol du ranch. On marche dessus pour acheter |
| **Tapis à Goûter** (Snack Mat) | Dalle qui fait grossir plus vite tous les squishies du ranch |
| **Cuve à Gelée** (Jelly Vat) | Machine gratuite qui fait naître des squishies au hasard (probabilités affichées) |
| **Bassin de Fusion** (Fusion Pool) | Deux jumeaux lancés dedans fusionnent ; le résultat peut fusionner encore (combo) |
| **Jumeaux** | Deux squishies de la même espèce avec le même nombre d'étoiles |
| **Pot à Pièces** (Coin Pot) | Le revenu passif s'y accumule ; on marche dessus pour encaisser |
| **Créature en fuite** (runaway) | Squishy personnel qui sort de ta Fontaine de Gelée toutes les 60 s |
| **Golden Wobbler** | Créature dorée partagée, lâchée 4 fois par heure dans la ville |
| **BOOP RUSH** | Événement de 90 s toutes les 10 min : on boope un nez par-dessus une clôture, le squishy s'enfuit en ville, tout le monde court |
| **Mode Rush / mode Cozy** | Chaque joueur choisit : participer au BOOP RUSH, ou rester tranquille. On est en Cozy tant qu'on n'a pas choisi |
| **Wild Wobbler** | Créature sans propriétaire lâchée par le serveur pendant le Rush : quelques-unes pour tous, plus une personnelle pour chaque joueur (Rush ou Cozy) |
| **MEGA SQUISH** | Un squishy géant atterrit sur la place ; tout le serveur le presse ensemble |
| **Jauge du serveur** (Wobble Meter) | Remplie par les actions de tous ; pleine = ×2 pour tout le serveur pendant 5 min |
| **Grand Splorch** | La renaissance (rebirth) : le plus gros squishy éclate en cadeaux pour tout le serveur |
| **Étagère à trophées** (Trophy Shelf) | Garde la taille record de chaque espèce, avec un petit bonus permanent |
| **Squishydex** | Le livre de collection : 26 espèces, 234 entrées de mutation, des badges d'étoiles |
| **Fame** (célébrité) | Score permanent gagné pendant le Rush (boopé, Wild Wobbler attrapé, Héros), au Grand Splorch, au MEGA, en relâchant un squishy. Donne un bonus de revenu. Le mode Cozy en gagne autant que le mode Rush |
| **Meilleur Ami** (Best Friend) | Squishy choisi : jamais boopable, il te suit en ville, c'est lui qu'on nourrit au bol. Ton premier Plop l'est d'office |
| **Jelly Moon** (Lune de Gelée) | Le rendez-vous du samedi : mutations rares, Mythiques boopables, MEGA lunaire |
| **Puce Menu** | Petit élément du HUD (glyphe △ + « Menu ») qui ouvre le menu des panneaux ; croix ↓ l'ouvre aussi |
| **Diagnostics** | Panneau réservé aux administrateurs : les erreurs vues sur les vrais serveurs et les vrais appareils, pour les photographier et nous les envoyer (§12.11) |

**Sommaire**

0. Fiche d'identité · 1. Vision, piliers, public, KPI · 2. Boucle de jeu et horloge commune · 3. Les 5 premières minutes · 4. Systèmes détaillés (monnaies, nombres géants, formules, raretés, mutations, dalles, presser, Pot, Cuve, Bassin, fuites, monture, Grand Splorch, Étagère, Squishydex, Fame, hors ligne, BOOP RUSH, MEGA SQUISH, jauge et Jelly Moon, simulation, plafonds) · 5. Contenu (26 espèces, fabrication, Plop, cosmétiques) · 6. Social et multijoueur · 7. Rétention · 8. Monétisation · 9. Juice, animation et sons · 10. Interface télé (disposition principale), commandes à la manette, vibrations · 11. Monde · 12. Architecture technique, stratégie qualité « zéro bug » et Diagnostics · 13. Sécurité des enfants · 14. Accessibilité · 15. Localisation · 16. Analytics · 17. Lancement et « Plus tard » · 18. Checklist de lancement · 19. Risques · 20. Questions ouvertes · Annexe A. Écarts avec le concept

---

## 0. Fiche d'identité

| Élément | Valeur |
|---|---|
| Titre | **Raise a Squishy** (titre de travail ; secours : *Squishy Ranch*). Aucun des deux n'est vérifié (Journal de révision, question 2) |
| Accroche | EN « Raise squishy jelly pets, grow them to a TRILLION… and make them sneeze at the neighbours! » ; FR « Élève des squishies tout mous, fais-les grossir jusqu'à 1 000 milliards… et fais-les éternuer chez les voisins ! » |
| Genre | Tycoon de créatures : croissance automatique + collection + fusion + renaissance, avec des poursuites amicales et des événements coopératifs de serveur |
| Joueurs | **16 par serveur** (`Players.MaxPlayers = 16`), **16 ranchs** |
| Plateformes | **Console d'abord** (décision du propriétaire, 1er novembre 2026) : **PlayStation 5** avec DualSense sur une télé vue à 2,5-3 m, puis **Xbox**, puis **PC** (manette, ou clavier et souris). **Téléphones et tablettes : non visés au lancement** : aucun contrôle tactile, aucune disposition pour petit écran. Types d'appareils publiés : **Ordinateur + Console** (VR coupée). Le PC reste car c'est là qu'on teste dans Studio |
| Contrôles | **Manette d'abord**, sans curseur virtuel : □ = action principale selon le contexte (presser, lancer, attraper, booper), ○ = Prendre / Poser, R2 = Bondir (qui attrape aussi), L2 = Monter, △ ou croix ↓ = Menu. Clavier et souris en second, même disposition (E, Q, Maj, R, Tab) |
| Qualité | **Zéro bug au lancement** : mécaniques vérifiées par le serveur (distances, états), jamais de physique ni d'animation dans les règles, un délai sur chaque état, 10 couches de tests (§12.10) et un panneau **Diagnostics** des erreurs en ligne pour les administrateurs (§12.11) |
| Classification visée | **Minimal** au questionnaire de maturité (Mild au pire) ; éligible aux catalogues Roblox Kids et Select |
| Session cible | 15 à 30 min. Le rythme fixe (fuite 60 s, Rush 10 min, MEGA 30 min) pousse au-delà de 10 min (seuil des Creator Rewards) |
| Public | 6-14 ans au cœur, satisfaisant pour les ados et les adultes collectionneurs |
| Monétisation | 4 passes « Pour toujours » et 3 familles de produits **à résultat connu**. Aucun hasard payant, aucune chance achetable (même avec des pièces), aucune pub vidéo |
| Code | Luau `--!strict`, Rojo, aucun travail manuel dans Studio. Estimation ≈ 12 800 lignes de jeu au premier passage, hors tests ; ≈ 9 000 lignes de tests et d'outils en plus (§12.12). Comet Conga a fini à 58 500 lignes après 6 tours de QA : prévoir large |
| Contenu au lancement | 24 espèces (6 familles × 4) + 2 secrètes, 7 raretés, 9 mutations, 1 ville, 16 ranchs, 6 événements récurrents (créature en fuite, Golden Wobbler, BOOP RUSH, MEGA SQUISH, jauge du serveur, Jelly Moon) |
| Date visée | **Samedi 12 décembre 2026** (costume d'hiver). Repli : samedi 9 janvier 2027 si les portes de qualité ne sont pas vertes (§18). La barre « zéro bug » passe avant la date |

---

## 1. Vision, pitch, piliers, public, positionnement

### 1.1 Pitch

**Pitch court (page du jeu).** À Wobbleton, élève des squishies en gelée qui grossissent toutes seules, presse-les pour faire jaillir des pièces, fusionne les jumeaux en géants… et toutes les 10 minutes, fais-les éternuer chez les voisins !

**Pitch long.** Chaque joueur a son ranch, au bord d'une ville pastel posée sur des collines de bonbons. Ses squishies grossissent de +1 chaque seconde et rapportent des pièces. Le joueur les presse (SPLORCH !) pour un gros jet de pièces, achète des dalles qui construisent son ranch en rebondissant, fait naître de nouvelles espèces dans sa Cuve à Gelée et lance les jumeaux dans le Bassin de Fusion pour des combos géants. Quand un squishy est assez gros, il pose une selle dessus et rebondit à travers la ville.

Toutes les 10 minutes, la sirène du **BOOP RUSH** retentit. Les joueurs qui l'ont choisi boopent le nez des squishies curieux par-dessus les clôtures : ATCHOUM, le squishy saute et rebondit dans la ville, et tout le monde lui court après. Celui qui l'attrape gagne un bébé de cette créature : le squishy lui éternue une petite bulle-bébé, puis rentre chez lui. Le propriétaire ne perd jamais rien : il récupère son squishy, gagne de la Fame et des pièces. Toutes les 30 minutes, un **MEGA SQUISH** grand comme une maison atterrit sur la place et tout le serveur le presse ensemble. Et quand le squishy d'un joueur devient énorme, il l'envoie au-dessus de la place : le **Grand Splorch** fait pleuvoir des cadeaux sur tout le serveur. Chaque samedi, la **Jelly Moon** apporte des mutations rares.

### 1.2 Piliers de design

Chaque fonctionnalité doit servir au moins un pilier. Ce qui n'en sert aucun est coupé.

| # | Pilier | Ce que ça impose |
|---|---|---|
| P1 | **Tout est mou et satisfaisant** | Chaque geste a un retour « ASMR » : écrasement, rebond, son un peu différent à chaque fois, pièces qui volent. Presser est le revenu actif |
| P2 | **On ne perd jamais rien** | Pas de vol. Le propriétaire gagne toujours quelque chose quand on boope son squishy. Le rebirth fait des cadeaux à tout le monde. Personne n'entre jamais dans le ranch d'un autre |
| P3 | **Le serveur vit au même rythme** | Une horloge UTC commune à tous les serveurs : fuite toutes les 60 s, Golden Wobbler 4 fois par heure, BOOP RUSH toutes les 10 min, MEGA SQUISH toutes les 30 min, Jelly Moon le samedi. Un seul grand spectacle à la fois |
| P4 | **La taille se voit** | Échelle logarithmique : un squishy de taille 1 million est 4,6 fois plus gros qu'un nouveau-né, et ça se voit de loin. Les nombres géants restent lisibles à 3 m |
| P5 | **Une manette, un canapé** | Pensé pour une DualSense sur une télé à 3 m. Une action principale selon le contexte (□). Seuls Prendre et Poser ont leur touche (○), pour ne jamais confondre presser et prendre. Tout se fait à la manette, sans curseur et sans glisser-déposer ; le clavier et la souris suivent la même disposition. Peu d'éléments à l'écran, grands, lisibles de loin, avec l'icône de la touche à côté de chaque mot |
| P6 | **Juste, sûr, zéro bug** | Autorité du serveur sur tout. Monétisation déterministe. Peu de systèmes, chacun poli. Ce que le joueur voit est ce que le serveur vérifie. **Règles robustes** : distances et états vérifiés par le serveur, jamais d'événement physique (`Touched`) ni de minutage d'animation dans une règle, un délai de sortie sur chaque état, rien qui casse si un objet n'est pas encore arrivé sur le client (§12.10) |

### 1.3 Public cible

Repère de l'étude : comptes à âge vérifié, 34 % de moins de 13 ans, 37 % de 13-17 ans, 29 % de 18 ans et plus (Étude §2).

| Persona | Profil | Ce qu'il cherche | Ce que Raise a Squishy lui donne |
|---|---|---|---|
| **Léa, 8 ans**, PS5 du salon, sur le canapé à côté de son grand frère ; la manette est grande pour ses mains | Lit peu, aime les animaux mignons | Des créatures à câliner, des récompenses fréquentes, ne pas se faire embêter, ne pas se perdre dans les menus | Un bouton principal (□), aucun appui simultané obligatoire, textes grands et courts avec l'icône de la touche, ○ qui revient toujours en arrière, première récompense à 10 s, mode Cozy par défaut, ranch où personne n'entre, Meilleur Ami qui la suit et ne s'enfuit jamais |
| **Noah, 12 ans**, Xbox ou PS5 dans sa chambre, en ligne avec deux amis | Aime courir, filmer, battre ses amis | Poursuites, combos, gros nombres | BOOP RUSH, bond à visée automatique (R2), combos ×5, monture, classements de la semaine, vibrations au bon moment |
| **Sam, 24 ans**, PC le soir, clavier et souris (ou manette branchée) | Collectionneur, optimise | Profondeur, objectifs longs | 260 tampons de Squishydex, mutations rares, étoiles, Étagère à trophées, Grand Splorch à l'infini ; même interface qu'à la télé, pilotable à la souris |

### 1.4 Positionnement marché

| Constat de l'étude | Réponse de Raise a Squishy |
|---|---|
| La boucle « obtenir une unité → revenu passif → améliorer → rebirth + interaction sociale » a fait les records 2025-2026 (Étude §4.1) | On garde la boucle entière. Le verbe social devient **booper et poursuivre**, pas voler |
| Le vol fait fuir quand il fait perdre : Grow a Garden 2 effondré, clips d'enfants en pleurs (Étude §5.2) | Rien n'est jamais pris. La poursuite donne une **copie bébé** au gagnant, et le propriétaire gagne aussi |
| Les créatures originales hors œufs sont un sous-genre libre (Étude §4.5) | 26 espèces à nous, en gelée, faites en formes simples. Pas d'œufs, pas de brainrot, pas de licence |
| Chevaucher ses créatures (Ride A Pet) et « +1 chaque seconde » (+1 Speed) attirent (Étude §2.2) | Monture dès 4 min ; la taille grossit de +1/s et se voit |
| L'algorithme note la fidélité à 28 jours, l'abandon en première partie et les jours entre amis (Étude §6.2) | Récompense à 10 s, croissance hors ligne visible, Plop à nourrir (jours au total), ranchs voisins, bonus d'amis |
| Les records viennent d'événements à heure fixe et de la mise à jour du samedi (Étude §4.2) | Horloge UTC commune, Jelly Moon chaque samedi, une espèce de plus chaque semaine sous forme de données |
| Le chat demande une vérification d'âge (Étude §6.3) | Tout marche sans chat : emotes, mécaniques, bannières |
| Achats trompeurs dans 14 des 15 jeux les plus rentables étudiés (Étude §4.4) | Résultat connu, prix en Robux clairs, aucun faux minuteur, aucune proposition dans les 10 premières minutes |
| ≈ 80 % des joueurs Roblox sont sur téléphone et ≈ 3 % sur console (exercice 2024, Étude §6.1) : presque tous les tycoons sont pensés pour le doigt | **Décision du propriétaire : console d'abord.** Un tycoon vraiment fait pour la manette et la télé (grands éléments, glyphes, vibrations, aucune action au doigt) se démarque sur un créneau peu servi. On renonce au téléphone au lancement : moins de joueurs possibles, mais une seule disposition à polir et à tester à fond (risque 14, §19) |

**Ce que le jeu n'est pas.** Pas de base à défendre, pas d'objet volé, pas d'œuf payant, pas de tapis roulant d'achat, pas de mème. Le BOOP RUSH n'a lieu que dans la ville, jamais dans un ranch.

### 1.5 Objectifs chiffrés (KPI)

Repères GameAnalytics 2026 : médiane J1 10,3 % / J7 1,6 % / J30 0,5 % ; top 1 % ≈ 22,2 / 9,1 / 4,7 % (Étude §4.3).

| KPI | Seuil de lancement | Objectif | Alerte |
|---|---|---|---|
| Rétention J1 | ≥ 15 % | 18-22 % | < 12 % |
| Rétention J7 | ≥ 5 % | 6-9 % | < 3 % |
| Rétention J30 | ≥ 2 % | 3-4,7 % | < 1 % |
| Session moyenne | ≥ 12 min | ≥ 15 min | < 10 min |
| Abandon avant la première pression | ≤ 5 % | ≤ 3 % | > 8 % |
| Abandon avant le premier Grand Splorch (joueurs de la 1re session restés ≥ 5 min) | ≤ 35 % | ≤ 25 % | > 45 % |
| **Départ dans les 2 min après un premier boop subi** | pas plus de 1,5 fois le taux de départ des autres joueurs au même moment | ≤ 1,2 fois | > 2 fois (déclenche le §16.4) |
| Part des joueurs en mode Rush | **observée seulement, jamais un objectif** (§16.4) | — | — |
| Plaisir du Rush : retour J1 des joueurs en mode Rush, comparé aux joueurs Cozy | ≥ 0,9 fois | ≥ 1 fois | < 0,8 fois |
| Réussite du MEGA SQUISH | 75-85 % | 80 % | < 65 % ou > 92 % |
| Conversion payeurs | 1,5 % | 2-3 % | — |
| Sessions avec au moins un ami Roblox sur le serveur | ≥ 15 % | ≥ 25 % | < 10 % |
| **Sessions sans aucune erreur ni avertissement** remonté par le client ou le serveur (Diagnostics, §12.11) | ≥ 99,5 % | ≥ 99,9 % | < 99 % (correctif sous 48 h) |
| Erreurs serveur par heure de serveur | 0 attendue | 0 | > 0,5 (correctif sous 48 h) |
| Images par seconde sur la console la plus faible (PS4, Xbox One), 16 joueurs | ≥ 30 stables | 30 sans creux | < 25 sur une minute |
| Part des sessions par appareil (console / PC) | observée seulement | — | — |

---

## 2. Boucle de jeu

### 2.1 Boucle principale (10 à 60 s)

```
            ┌──────────────────────────────────────────────────────────────┐
            │                                                              │
            ▼                                                              │
   ┌────────────────┐   +1 taille/s (×Tapis, ×2^R)   ┌────────────────┐     │
   │ 1. GRANDIR     │ ─────────────────────────────▶ │ 2. PRESSER     │     │
   │ (tout seul)    │   revenu passif → Pot          │ SPLORCH !      │     │
   └────────────────┘                                │ pièces ×12 s   │     │
            ▲                                        │ PERFECT ×2     │     │
            │                                        └───────┬────────┘     │
            │                                                │ pièces       │
   ┌────────────────┐   jumeaux                      ┌───────▼────────┐     │
   │ 5. FUSIONNER   │ ◀───────────────────────────── │ 3. CONSTRUIRE  │     │
   │ Bassin, combo  │                                │ dalles : Tapis,│     │
   │ (a+b)×1,25     │                                │ déco, enclos…  │     │
   └───────┬────────┘                                └───────┬────────┘     │
           │                                                 │              │
           │            ┌────────────────┐                   │              │
           └──────────▶ │ 4. FAIRE NAÎTRE│ ◀─────────────────┘              │
                        │ Cuve, fuites,  │   nouveaux squishies             │
                        │ Golden, bébés  │ ─────────────────────────────────┘
                        └────────────────┘
   Méta : quand le plus gros squishy atteint l'objectif → GRAND SPLORCH (×2 croissance pour toujours, Cuve meilleure)
```

1. **Grandir.** Chaque squishy grossit tout seul (+1 par seconde au départ) et remplit le Pot à Pièces.
2. **Presser.** Le joueur presse un squishy prêt : il gagne 12 secondes de revenu de ce squishy d'un coup, ×2 si PERFECT. Chaque squishy se recharge en 8 s.
3. **Construire.** Les pièces achètent des dalles : le Tapis à Goûter (croissance), des décorations (+5 % de revenu chacune) et des places d'enclos. Elles n'achètent jamais de chance : la Cuve s'améliore toute seule à chaque Grand Splorch (§4.9).
4. **Faire naître.** La Cuve fait naître un squishy gratuit à intervalle fixe. Les créatures en fuite, le Golden Wobbler, le BOOP RUSH et le MEGA SQUISH en apportent d'autres.
5. **Fusionner.** Deux jumeaux lancés dans le Bassin fusionnent : taille (a + b) × 1,25 et une étoile de plus. Le résultat peut fusionner encore (combo).

**La décision de chaque minute :** presser maintenant (pièces tout de suite), acheter le prochain Tapis (croissance pour tout le ranch), ou garder des jumeaux dans le Bassin pour préparer un combo ×4.

### 2.2 Boucles secondaires

| Boucle | Durée | Contenu | But |
|---|---|---|---|
| **Rythme du serveur** | 60 s / 10 min / 30 min | Créature en fuite personnelle (60 s), Golden Wobbler (4 par heure), BOOP RUSH (90 s toutes les 10 min), MEGA SQUISH (toutes les 30 min), jauge du serveur | Un rendez-vous toutes les quelques minutes, sessions de plus de 10 min |
| **Boucle de renaissance** | 14 min au début, puis de plus en plus long | Atteindre l'objectif de taille → Grand Splorch → tout regrandit 2 fois plus vite et la Cuve s'améliore | Le plaisir de « recommencer plus vite et plus gros » |
| **Boucle quotidienne** | 1 jour | Croissance hors ligne visible, Nourrir Plop (jours au total), 3 objectifs du jour | Habitude J2-J7 |
| **Boucle hebdomadaire** | 7 jours | Jelly Moon le samedi (et rattrapage le dimanche), 5 classements de la semaine, une nouvelle espèce par semaine (données) | Pic du samedi, rendez-vous |
| **Boucle de collection** | jours → semaines | Squishydex (26 espèces, 234 mutations, badges d'étoiles), bonus de famille, Étagère à trophées, Fame | Profondeur J8-J28 |
| **Boucle sociale** | continue | Ranchs voisins, bonus d'amis, pet-sitting, poursuites, MEGA, jauge, cadeaux du Grand Splorch, emotes, applaudissements | Jeu entre amis, signal de classement |

### 2.3 Méta-progression

| Couche | Horloge | Ce qui progresse | Remis à zéro par le Grand Splorch ? |
|---|---|---|---|
| Ranch | minutes | Pièces, Tapis à Goûter, décorations | **Oui** |
| Taille | minutes → heures | Taille de chaque squishy | **Oui** (chacun redevient taille 1) |
| Enclos | heures → jours | Places d'enclos (4 → 18, 24 avec le pass), Lit douillet | Non |
| Collection | jours | Squishies (espèce, mutation, étoiles), Squishydex, bonus de famille, Meilleurs Amis | Non |
| Prestige | jours → semaines | R : croissance ×2 par Grand Splorch, familles débloquées, niveau de la Cuve (qualité, vitesse, buses : donné, jamais acheté), selles gagnées, Étagère à trophées | — |
| Social | semaines | Fame, jours de Plop, titres, classements | Non |

### 2.4 Horloge commune (UTC, identique sur tous les serveurs)

Toutes les phases viennent du module pur `EventClock` (§12.4), à partir de `Clock.now()` (même heure UTC côté serveur et côté client). Les joueurs apprennent le rythme : « Rush à :05, :15, :25… ».

| Minute de l'heure | Événement | Durée |
|---|---|---|
| :00:30, :10:30, :30:30, :40:30 | **Golden Wobbler** lâché sur la place | 30 s |
| :04:50, :14:50… (10 s avant) | Sirène du BOOP RUSH | 10 s |
| :05, :15, :25, :35, :45, :55 | **BOOP RUSH** | 90 s (jusqu'à :06:30, :16:30…) |
| :19:45 et :49:45 | Alerte MEGA SQUISH (ombre au sol) | 15 s |
| :20 et :50 | **MEGA SQUISH** | 60 s de pression + 5 s d'éclatement |
| Samedi 16:00-16:20, 18:00-18:20, 20:00-20:20, 22:00-22:20 | **Jelly Moon** (le MEGA de :20 devient MEGA MOON SQUISH) | 20 min (+ le MEGA de :20) |
| Dimanche 16:00-16:20 | Jelly Moon de rattrapage | 20 min |
| 00:00 chaque jour | Remise à zéro quotidienne (plafonds journaliers, bol ; objectifs : les terminés sont réclamés tout seuls, ceux en cours restent jusqu'à la fin de la session, §7.4) | — |
| Lundi 00:00 | Remise à zéro hebdomadaire (classements) | — |

Heures à Paris en hiver : Jelly Moon à 17 h, 19 h, 21 h et 23 h le samedi, 17 h le dimanche. À New York en hiver : 11 h, 13 h, 15 h, 17 h.

**Un seul grand spectacle à la fois** [`Events.SpectacleGap = 20`]. Les grands spectacles sont : BOOP RUSH, MEGA SQUISH, Grand Splorch, danse de Big Plop (jauge pleine). Deux grands spectacles sont toujours séparés d'au moins 20 s. Les horaires fixes le garantissent entre Rush, MEGA et Golden Wobbler (le Golden n'est pas un grand spectacle). Le Grand Splorch et la danse de Big Plop, déclenchés par les joueurs, attendent dans une **file du serveur** : le HUD affiche « Ton Grand Splorch passe dans 0:35 ». Un Grand Splorch au plus toutes les 20 s par serveur, dans l'ordre d'arrivée. Pendant un Rush (90 s), l'attente maximale est donc de 110 s. Une fois dans la file, le Grand Splorch est **garanti** (§4.15).

---

## 3. Les 5 premières minutes (FTUE)

**Règles.** Pas de tutoriel écrit. Un chemin lumineux au sol, les gestes de Big Plop (la mascotte), et un mot court à côté du **glyphe de la touche** (4 mots au plus) : le glyphe de la manette du joueur (□, ○, R2, L2, △, stick gauche), ou la touche du clavier si le joueur joue au clavier. Glyphe de 64 px TV, mot de 40 px TV, posés au-dessus de l'objet concerné ou en bas au centre (§10.2). Jamais plus d'une consigne à l'écran. **Aucune étape ne peut bloquer** : si le joueur ne fait pas le geste demandé en 90 s, la consigne se range dans une petite pastille, Big Plop la remontre plus tard, et l'accueil continue (les naissances scriptées restent dues et ne se perdent pas). Une récompense ou un chiffre qui bouge au moins toutes les 15 s. Aucune fenêtre bloquante pendant les 60 premières secondes. Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé (la Boutique Robux reste cachée). Chaque étape numérotée est envoyée à `AnalyticsService:LogOnboardingFunnelStepEvent` (§16.1).

**Pendant l'accueil, l'horloge est réglée pour l'apprentissage** : la Cuve et les créatures en fuite suivent le script ci-dessous jusqu'à 5:00 de jeu, puis reprennent leurs règles normales (§4.9, §4.11). Les événements de serveur (Rush, MEGA, Golden) gardent leur horaire UTC : un Rush croise les 5 premières minutes d'environ 2 nouveaux sur 3. Ils restent donc **discrets pour le nouveau jusqu'à l'étape 9** (≈ 4:30) : aucune bannière, aucune vibration de sirène, teinte du ciel à 30 %, musique du Rush à −12 dB, bannières des autres mises en attente (jetées si elles ont plus de 30 s). Seule reste la petite pastille d'événement du HUD ; Big Plop la montre du doigt une seule fois, après l'étape 8. Pas de Wild Wobbler personnel avant l'étape 9 : la démonstration de Big Plop sert de première poursuite.

| Temps | Ce que voit et fait le joueur | Ce que fait le système | Étape |
|---|---|---|---|
| Chargement | Écran construit en code (`ReplicatedFirst`) : un Plop rebondit, 3 points animés, aucun texte long | Chargement du profil avec verrou de session (§12.6). En cas d'échec : écran « Ton ranch se réveille… » et bouton Réessayer, jamais de profil vide sauvegardé | — |
| 0:00 | Le personnage apparaît **dans son propre ranch**, face au Pot et au premier squishy. Les amis Roblox déjà sur le serveur ont le ranch voisin | `RanchService` attribue le ranch (à côté d'un ami s'il y en a un) | 1 « Chargé » |
| 0:00-0:10 | Big Plop, la mascotte, arrive en rebondissant et pose **ton petit Plop** (taille 1, ton Meilleur Ami n° 1) à 5 studs devant le joueur : il n'a pas besoin de marcher. Le compteur au-dessus de lui défile : 2, 3, 4… Grand anneau au sol avec le glyphe □ (E au clavier) et le mot « Presser » | Croissance +1/s. Le reste du HUD est caché : seul le compteur de pièces (0) est visible | — |
| ~0:10 | **Premier SPLORCH** : Plop s'écrase, rebondit, fontaine de pièces, « +10 » en gros, petite vibration (manette) | Récompense de pression `max(10, floor(12 × revenu))` = 10 (§4.7) | 2 « Première pression » |
| 0:10-0:20 | Deuxième pression possible à 0:18 (anneau qui se remplit sous Plop) : 20 pièces. Les flèches au sol vers la première dalle, **Tapis à Goûter, 20**, n'apparaissent que quand les pièces suffisent ; avant, la dalle montre un anneau qui se remplit (« 10 / 20 »), jamais un refus | — | — |
| ~0:20 | Le joueur marche sur la dalle (si le stick n'a pas bougé depuis 4 s, le glyphe du stick gauche apparaît avec « Marcher ») : le serveur voit qu'il est entré sur la dalle (§4.6) et le Tapis se construit en rebondissant. Plop passe à **+2/s** (le « +2 » flotte au-dessus de lui). **Première récompense en moins de 30 s** | Achat Tapis niveau 1 | 3 « Premier achat » |
| ~0:40 | La **Cuve à Gelée** se construit toute seule (gratuite). Sa première goutte éclot : « **Jumeau de Plop** ! », annoncé comme tel. Ce n'est pas un tirage au hasard | Naissance scriptée : Plop, 0 étoile, taille 1 | 4 « Cuve » |
| ~1:00 | Leçon de fusion. Invite « ○ Prendre » (Q au clavier) au-dessus du jumeau. Un cœur pulse sur Plop, qui attend déjà dans le Bassin (Big Plop l'y a posé). Trois pas, puis « □ Fusion ! » au bord du Bassin. SPLORCH géant, **une étoile apparaît**, le revenu saute. Taille ≈ (96 + 41) × 1,25 = 171 | Fusion (§4.10). Le joueur a compris : grandir, presser, fusionner | 5 « Première fusion » |
| ~1:30 | Le **Pot à Pièces** brille : le joueur marche dessus, gros chiffre (≈ 240). Deux nouvelles dalles s'allument : Tapis niveau 2 (80) et la première décoration, Clôture rebondissante (80) | Encaissement du Pot (§4.8) | 6 « Premier Pot » |
| ~2:00 | **Ta** créature en fuite saute de la Fontaine de Gelée, devant ton portail, marquée d'un anneau à ta couleur. Flèche au bord de l'écran, glyphe R2 avec « Bondir » (un bond qui atterrit près d'elle l'attrape tout seul), puis glyphe □ avec « Attraper » quand elle est à portée. Attrapée : tampon « NOUVEAU ! Mochi Mew » dans le Squishydex | Fuite personnelle scriptée : Mochi Mew, Commun | 7 « Première capture » |
| ~2:45 | **Premier vrai tirage** de la Cuve. Les probabilités apparaissent en barres simples sur la Cuve, avec l'étiquette « Nouveauté garantie (3) » : les 3 premiers tirages donnent une espèce que le joueur n'a pas encore (§4.9). Un tirage Rare ou mieux lance une bannière serveur | Tirage normal (qualité de la Cuve 1 = 1 + R, §4.9) | 8 « Premier tirage » |
| ~3:00 | Le HUD affiche l'horloge du prochain événement (« BOOP RUSH 2:00 »). Big Plop fait sa **démonstration** : il éternue devant ton portail (ATCHOUM) et s'enfuit en rebondissant. Le joueur le poursuit sans rien risquer et gagne un **bébé Plop** (10 % de la taille de son Plop). Son ranch porte le **bouclier débutant** pendant 15 min de jeu ; il est en mode Cozy tant qu'il n'a pas choisi. De retour au ranch, s'il n'a jamais changé de cible : glyphes L1 R1 avec « Choisir » pendant 4 s (clic au clavier-souris), une seule fois | Démonstration personnelle, toujours jouée (§4.21.6) | — |
| ~4:30 | Plop atteint la **taille 1 200** : une selle apparaît, glyphe L2 avec « Monter ». Il rebondit 1,4 fois plus vite. Une flèche mène à la place : statue du plus gros squishy du serveur, Boutique (vente de squishies), Autel de la Lune avec le compte à rebours du samedi, jauge du serveur | Seuil de selle (§4.12) | 9 « Première balade » |
| ~5:00 | Petite carte non bloquante (§10.3) : **3 objectifs du jour** (presser 30, attraper 2, fusionner 1) et « **Nourris Plop : Jour 1** » (avec le vrai nom du Meilleur Ami). Quand elle se range, la puce « Menu » du HUD apparaît avec le glyphe △ et la pastille « ! » : c'est la leçon du menu (△ ou croix ↓ ; Tab au clavier). Avant ce moment, le menu reste fermé : △ et croix ↓ ne font qu'un petit son `Bump`. Le HUD complet est affiché | Objectifs du jour 1 fixes (§7.4) | 10 « Objectifs » |
| ~12-15 min | Le plus gros squishy atteint **15 000** : « Grand Splorch prêt ! » | Objectif R0 (§4.15) | 11 « Premier Grand Splorch » |

**Cible à 5:00** (vérifiée par la simulation, §4.24) : 3 à 4 squishies, au moins 1 fusion, au moins 1 capture, la première balade faite, et assez de pièces pour la dalle Enclos. À 5:00, les 4 places d'enclos de départ sont pleines : la Cuve garde sa goutte suivante (« Plein ! ») et la dalle Enclos (1 200) devient le prochain objectif naturel.

**Cas particuliers**
- *Arrivée pendant un BOOP RUSH* : l'événement reste discret (règle ci-dessus). Le nouveau est en mode Cozy ; la carte du choix Rush/Cozy (§4.21.1) n'apparaît pas avant 15:00 de jeu, à la fin du bouclier débutant.
- *Arrivée juste avant un MEGA SQUISH* : la flèche vers la place n'apparaît qu'après la première balade (≈ 4:30). Le joueur peut y aller avant ; s'il presse le MEGA, il gagne comme tout le monde.
- *Serveur presque vide* : la démonstration de Big Plop et les Wild Wobblers (dont un personnel à chaque Rush, §4.21.5) donnent quand même une poursuite.
- *Retour d'un joueur* (pas la première session) : écran de retour (§7.2), puis le HUD complet.
- *Accueil interrompu* (départ avant 5:00) : l'étape atteinte est sauvegardée (`onboarding.step`) ; au retour, l'accueil reprend à l'étape suivante sans rejouer les naissances scriptées.
- *Personnage mort ou réapparu pendant une étape* : il réapparaît dans son ranch (§6.1) ; l'étape en cours reprend, la consigne se réaffiche, rien n'est perdu (un squishy porté retourne à sa place).
- *Le joueur passe de la manette au clavier (ou change de manette)* : tous les glyphes changent aussitôt (§10.6). Les consignes ne citent jamais une touche dans une phrase.

---

## 4. Systèmes détaillés

### 4.1 Monnaies et scores

Une seule monnaie à dépenser, pour rester simple. Tout est calculé et gardé par le serveur.

| Ressource | Rôle | Sources | Puits | Remise à zéro |
|---|---|---|---|---|
| **Pièces** (Coins) | Construire le ranch de la boucle en cours | Revenu passif (Pot), pressions, combos, vente de squishies, récompenses d'événements, objectifs du jour, produits Robux « Paquet de pièces » | Dalles du ranch (Tapis, décorations), places d'enclos, Lit douillet. **Jamais une chance** (§8.1) | Oui, à chaque Grand Splorch |
| **Fame** (célébrité) | Score permanent, bonus de revenu | Pendant le Rush, 30 par jour au plus : être boopé (+1), Wild Wobbler attrapé (+1, Rush ou Cozy), capture « Héros » (+2). Puis : relâcher un squishy (+1), Grand Splorch (+5), participer au MEGA (+1) | Aucun (on ne la dépense pas) | Jamais |
| **R** (niveau de Grand Splorch) | Prestige | +1 par Grand Splorch | — | Jamais |
| **Jours de Plop** | Fidélité | +1 par jour UTC où l'on nourrit son Meilleur Ami au bol | — | Jamais (total, jamais une série) |

**Sources et puits de pièces (valeurs exactes)**

| Source | Montant |
|---|---|
| Revenu passif | Somme des revenus des squishies du ranch (§4.3), versée dans le Pot |
| Pression | `max(10, floor(12 × revenu du squishy))`, ×2 si PERFECT, +10 % par PERFECT de suite (max +50 %) (§4.7) |
| Combo de fusion | Étape k : `20 × k ×` revenu du squishy obtenu (§4.10) |
| Vente d'un squishy | 60 s de son revenu (minimum 10) (§4.13) |
| Créature dorée vue de près, MEGA réussi, cadeau de Grand Splorch | 60 s du revenu du joueur (§4.11, §4.22, §4.15) |
| Capture « Héros » de son propre squishy en fuite | 120 s du revenu du joueur (§4.21) |
| Squishy boopé rendu au propriétaire | 60 s du revenu du propriétaire (§4.21) |
| Joueur Rush à 30 studs au plus d'une capture du Rush | 20 s de son revenu (§4.21.3) |
| Pet-sitting (presser chez un ami) | Le propriétaire : la pression normale ; le visiteur : 10 s de son propre revenu (§6.4) |
| Applaudir un Grand Splorch | 10 s du revenu (10 récompensés par jour) (§6.7) |
| Objectifs du jour | 3, 6 ou 10 min de revenu (§7.4) |
| Hors ligne | 25 % du revenu de départ, plafonné (§4.19) |

« Revenu du joueur » = la somme des revenus de ses squishies dans les enclos, multiplicateurs compris, au moment de la récompense. Les récompenses « en secondes de revenu » restent ainsi justes à tous les niveaux.

### 4.2 Nombres géants

**Stockage.** Les tailles et les pièces sont des nombres `number` de Luau (double précision, jusqu'à ≈ 1,8e308). Sous 1e15, les pièces restent des entiers exacts (`floor` après chaque calcul). Au-dessus, l'arrondi du double est accepté (il ne se voit pas à l'écran). Le serveur borne toute valeur à `[0 ; 1e300]` et refuse `NaN` et l'infini avant chaque écriture (les DataStores refusent ces valeurs en JSON).

**Affichage** (`Shared/Util/Format.abbreviate(n, lang)`) :
- moins de 10 000 : le nombre entier, avec séparateur des milliers (EN « 9,876 » ; FR « 9 876 » avec espace fine insécable U+202F) ;
- à partir de 10 000 : **3 chiffres significatifs, tronqués** (jamais arrondis vers le haut : 999 999 s'affiche 999K, pas 1.00M), puis le suffixe ;
- en français : virgule décimale et espace fine insécable avant le suffixe (« 1,23 M ») ;
- au-delà de 1e36 : notation « 1.23e36 » (EN) / « 1,23e36 » (FR) ;
- les bannières de jalons écrivent le mot entier (« 1 TRILLION! », « 1 BILLION (1 000 milliards) ! »).

| Puissance | EN | Mot EN | FR | Mot FR |
|---|---|---|---|---|
| 1e3 | K | thousand | k | mille |
| 1e6 | M | million | M | million |
| 1e9 | B | billion | Md | milliard |
| 1e12 | T | trillion | Bn | billion (mille milliards) |
| 1e15 | Qa | quadrillion | Bd | billiard |
| 1e18 | Qi | quintillion | Tn | trillion |
| 1e21 | Sx | sextillion | Td | trilliard |
| 1e24 | Sp | septillion | Qn | quadrillion |
| 1e27 | Oc | octillion | Qd | quadrilliard |
| 1e30 | No | nonillion | Qt | quintillion |
| 1e33 | Dc | decillion | Qtd | quintilliard |

Exemples : 12 345 → EN « 12.3K », FR « 12,3 k » ; 4 560 000 000 → EN « 4.56B », FR « 4,56 Md » ; 7,8e12 → EN « 7.80T », FR « 7,80 Bn ». En français, la fiche d'un squishy et l'info-bulle de la taille montrent aussi le mot entier (« 7,80 Bn = 7,80 billions = 7 800 milliards »). Le choix des suffixes français est une question ouverte (Journal de révision, question 3).

**Échelle de taille visuelle** (`Shared/Logic/SizeScale`) :

```
échelle(S) = 1 + 0,6 × log10(max(1, S))
diamètre du corps = 2 studs × échelle
```

| Taille S | 1 | 100 | 1 200 (selle) | 1 million | 1 milliard | 1e12 | 1e15 | 1e30 |
|---|---|---|---|---|---|---|---|---|
| Échelle | 1× | 2,2× | 2,85× | **4,6×** | 6,4× | 8,2× | 10× | 19× |
| Diamètre (studs) | 2 | 4,4 | 5,7 | 9,2 | 12,8 | 16,4 | 20 | 38 |

Plafonds d'affichage (la taille réelle et le nombre restent exacts) : **4×** dans un enclos (diamètre 8, pour que 24 squishies tiennent) ; **2,85× à 4×** comme monture (taille fixée par la selle, §4.12) ; **19×** pour la silhouette du meilleur squishy qui flotte au-dessus du ranch (§6.6) et pour la statue de la place. Au-delà du plafond de l'enclos, une petite couronne de taille (anneau doré qui tourne) indique « plus gros que ce que l'enclos montre ».

### 4.3 Le squishy : données et formules

Un squishy est une ligne de données dans le profil (§12.6) : `{ s = espèce 1-26, m = mutation 0-9, st = étoiles 0-5, z = taille, bf = emplacement de Meilleur Ami 0-3, lk = verrou, o = tenue }`. Il est dessiné par le client à partir de ces valeurs (§5.2).

**Croissance** (par seconde, identique pour tous les squishies du ranch) :

```
croissance = 1 × 2^R × (1 + niveauTapis) × (1 + 0,10 × familleJellyComplète) × B
```

- `niveauTapis` de 0 à 12 (§4.6) ; `familleJellyComplète` vaut 1 si les 4 espèces de la famille Jelly sont dans le Squishydex (§4.17) ;
- `B` = 2 si un boost ×2 est actif (jauge du serveur, Squish Party, boost personnel), sinon 1. Les boosts ×2 ne se cumulent jamais entre eux (§4.25).

**Revenu** (pièces par seconde, pour un squishy dans un enclos) :

```
revenu = 0,02 × rareté × taille × mutation × (1 + 0,5 × étoiles) × A × P × B
A = 1 + 0,05 × décorations          (18 au plus → +90 %)
      + 0,10 × amisPrésents         (4 au plus → +40 %)
      + 0,01 × min(300, Fame)       (+300 % au plus)
      + bonus de l'Étagère à trophées (+208 % au plus, §4.16)
      + 0,01 × pages dorées du Squishydex (+26 % au plus, §4.17)
P = 2 avec le pass ×2 Pièces, sinon 1
```

Exemple : un Plop Commun de taille 1 000, sans mutation, 1 étoile, sans bonus : 0,02 × 1 × 1 000 × 1 × 1,5 = **30 pièces/s**. Le R n'apparaît pas dans le revenu : il agit par la taille (croissance ×2^R), ce qui revient au facteur « rebirth » du concept sans compter deux fois.

Les squishies de la Boîte à dodo (§4.14) ne grandissent pas et ne rapportent rien. Ceux du Bassin de Fusion grandissent et rapportent comme dans un enclos.

### 4.4 Raretés

La couleur du corps vient de l'espèce (§5.1). La rareté se lit à l'**aura** (couleur **et** forme, pour les daltoniens) et à la couleur de l'étiquette.

| Rareté (EN / FR) | Multiplicateur de revenu | Couleur | Aura (forme lisible sans couleur) | Espèces au lancement |
|---|---|---|---|---|
| Common / Commun | ×1 | Gris clair (220, 220, 225) | Aucune | 6 |
| Uncommon / Peu commun | ×3 | Vert (120, 220, 130) | **Cercle** plat au sol | 6 |
| Rare / Rare | ×10 | Bleu (90, 170, 255) | **3 points** qui tournent (triangle) | 3 |
| Epic / Épique | ×40 | Violet (180, 110, 255) | **Carré** de 4 losanges qui tournent | 5 |
| Legendary / Légendaire | ×200 | Or (255, 200, 60) | **Couronne-étoile** à 5 branches + `PointLight` | 3 |
| Mythic / Mythique | ×1 000 | Rose (255, 110, 190) | **Double anneau** + contour `Highlight` (budget §12.9) | 1 |
| Secret / Secret | ×5 000 | Arc-en-ciel sur fond noir | **Losange** flottant + étincelles « ? » | 2 |

### 4.5 Mutations

Une mutation au plus par squishy. Elle multiplie le revenu. Une fusion garde la meilleure des deux (le plus gros multiplicateur).

| Id | Mutation (EN / FR) | Multiplicateur | Aspect (données de rendu) | Chance par naissance dans la Cuve (buses niveau 0, R = 0) | Buses niveau 5 (×3,5, dès R = 5) |
|---|---|---|---|---|---|
| 1 | Jelly / Gelée | ×1,5 | Corps en matériau `Glass` (transparence 0,2) avec un petit noyau visible dedans | 4 % | 14 % |
| 2 | Neon / Néon | ×2 | Yeux, oreilles et motif en matériau `Neon` ; lueur douce | 2 % | 7 % |
| 3 | Frosted / Givré | ×3 | Matériau `Ice`, 2 flocons par seconde (particules) | 1 % | 3,5 % |
| 4 | Golden / Doré | ×5 | Matériau `Foil` doré (255, 205, 60), `Sparkles` | 0,4 % | 1,4 % |
| 5 | Galaxy / Galaxie | ×8 | Corps bleu nuit (25, 20, 60) parsemé de 6 points `Neon`, coque `ForceField` | 0,15 % | 0,525 % |
| 6 | Rainbow / Arc-en-ciel | ×12 | Teinte qui fait le tour du cercle des couleurs en 6 s (client) | 0,05 % | 0,175 % |
| 7 | Lunar / Lunaire | ×20 | Argent bleuté (210, 220, 255), croissant de lune sur le front, petit troisième œil mignon, 2 gouttes de gelée brillantes qui flottent autour ; **seulement pendant la Jelly Moon** | 0 % (3 % pendant la Jelly Moon, non multiplié par les buses) | — |
| 8 | Glitch / Glitch | ×40 | Couleurs qui changent par paliers 2 fois par seconde (jamais plus de 3 changements/s), 4 petits cubes qui orbitent. Mouvement réduit : damier fixe | 0,004 % (1 sur 25 000) | 0,014 % |
| 9 | **Flop** / Flop | ×100 | **Le raté magnifique** : dégonflé (hauteur ×0,6, largeur ×1,25), yeux mi-clos, petite moue, mais **toujours brillant** : reflets dorés, 3 petites étoiles dorées qui tournent au-dessus de lui, badge doré « ×100 » sur son étiquette. Il fait « blorp » toutes les 6 à 10 s. Un Plop Flop est le « **Flop Plop** », l'autocollant du jeu. Il doit se lire comme un trésor rigolo, jamais comme un squishy cassé ou malade | 0,0005 % (1 sur 200 000) | 0,00175 % (1 sur 57 143) |

- **Tirage** : un seul nombre au hasard dans [0 ; 1[, comparé aux chances cumulées en partant de la plus rare (Flop, puis Glitch… puis Gelée). Au-delà du total : pas de mutation. Total à buses 0 : 7,6 % ; buses 5 : 26,6 %.
- **Buses à mutation** (pièce de la Cuve, niveau = `min(5, R)`, donné par le Grand Splorch, jamais acheté, §4.9) : toutes les chances sauf Lunaire × `(1 + 0,5 × niveau)`.
- **Jelly Moon** : toutes les chances × 2, plus Lunaire 3 % (total à buses 5 : 56,2 %).
- **Autres sources** : Golden Wobbler (Doré garanti), Goutte de Lune (Lunaire garanti, §4.23), bébés du MEGA (chances de mutation × 2), bébés du Rush (même mutation que l'original), cadeaux du Grand Splorch (sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible).
- **Étiquette « 1 sur X »** lors d'une naissance rare : calculée en direct = 1 / (chance de la rareté × chance de la mutation) aux réglages du moment, arrondie à 2 chiffres significatifs. Jamais un chiffre inventé. Exemple au départ (R = 0, qualité 1, buses 0) : Flop Plop = 1 / (0,74 × 0,000005) ≈ **1 sur 270 000**.
- **Naissance rare** : les mutations Arc-en-ciel, Glitch et Flop sont fêtées comme une naissance Légendaire, quelle que soit la rareté de l'espèce : ralenti, bannière serveur, clip automatique, grande étiquette « 1 sur X » (§9.4). Le verrou automatique les protège (§4.13).

### 4.6 Le ranch et ses dalles

Le ranch se construit en marchant sur des dalles lumineuses. Chaque dalle montre une icône, le prix et le niveau. Un achat se construit en rebondissant (§9.4). Les dalles apparaissent dans l'ordre : une nouvelle dalle s'allume quand la précédente a été achetée une fois. **Une dalle trop chère ne refuse jamais** : quand on marche dessus, un anneau se remplit autour d'elle (« 1,2K / 3K ») avec un petit son doux (`Bump`), sans secousse rouge ni son `Error`.

**Comment l'achat est détecté (règle robuste).** Jamais par un événement physique `Touched` (il rate des contacts, en compte deux, et dépend des collisions). Le serveur regarde, à chaque tick de 10 Hz, la **position validée** du joueur (§12.8) : il est « sur » une dalle quand il est à **2,5 studs** au plus de son centre, et il en « sort » au-delà de **3,5 studs** (l'écart évite les achats en rafale au bord). **Un achat par entrée** : pour acheter le niveau suivant, on sort et on revient, ou on presse □ « Acheter » (E au clavier) tant qu'on est dessus. Le panneau Ranch, onglet *Dalles*, achète aussi (§10.3). Les pièces des dalles sont ancrées et non solides : elles ne gênent jamais la marche.

**Les pièces n'achètent jamais de chance.** Elles construisent la croissance, le revenu et la place. La Cuve (qualité, vitesse, buses) s'améliore toute seule à chaque Grand Splorch (§4.9). Ainsi, aucun Robux, même passé par les pièces, ne change une probabilité (§8.1).

Prix : `floor(base × croissance^L)` où L = niveau actuel (le premier achat coûte la base). Les dalles de la boucle sont **multipliées par 2^R** (comme la croissance), pour que la construction garde son sens à chaque boucle. Les places d'enclos et le Lit douillet ne le sont pas (ils sont permanents).

| Dalle | Effet par niveau | Niveaux | Base | Croissance | Grand Splorch |
|---|---|---|---|---|---|
| **Tapis à Goûter** (Snack Mat) | Croissance × (1 + niveau) : +1/s → +13/s au niveau 12 | 12 | 20 | ×4,0 | Remis à zéro |
| **Décorations** (18 dalles différentes, une fois chacune) | +5 % de revenu chacune | 18 | 80 | ×2,2 | Remises à zéro |
| **Enclos** | +1 place (4 → 18) | 14 | 1 200 | ×2,2 | **Gardé** |
| **Lit douillet** (dès R = 1) | Limite hors ligne 8 h → 12 h | 1 | 250 000 | — | **Gardé** |

**Coûts calculés (R = 0 ; multiplier par 2^R pour les dalles de la boucle)**

| Niveau → | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Tapis à Goûter | 20 | 80 | 320 | 1 280 | 5 120 | 20 480 | 81 920 | 327 680 | 1,31 M | 5,24 M | 21,0 M | 83,9 M |
| Décorations | 80 | 176 | 387 | 851 | 1 874 | 4 122 | 9 070 | 19 954 | 43 900 | 96 581 | 212 479 | 467 454 |
| Enclos | 1 200 | 2 640 | 5 808 | 12 777 | 28 110 | 61 843 | 136 055 | 299 322 | 658 510 | 1,45 M | 3,19 M | 7,01 M |

Décorations niveaux 12 à 17 : 1,03 M, 2,26 M, 4,98 M, 11,0 M, 24,1 M et 53,0 M (total des 18 ≈ 97 M, du même ordre que les 12 niveaux du Tapis, ≈ 112 M). Enclos niveaux 12 et 13 : 15,4 M et 33,9 M (total des 14 niveaux ≈ 62 M, un objectif de plusieurs jours).

**Les 18 décorations** (dans l'ordre d'apparition) : Bouncy Fence (clôture rebondissante), Candy Lamp (lampadaire bonbon), Jelly Flowers (fleurs de gelée), Gumdrop Path (chemin de bonbons), Cloud Bench (banc nuage), Lollipop Trees (arbres sucettes), Marshmallow Rocks (rochers guimauve), Bubble Pond (mare à bulles), Sprinkle Arch (arche à vermicelles), Pudding Hut (cabane pudding), Rainbow Kite (cerf-volant arc-en-ciel), Star Windmill (moulin étoilé), Jellybean Swing (balançoire dragée), Cupcake Fountain (fontaine cupcake), Gummy Bridge (pont gélifié), Cotton Candy Tree (arbre barbe à papa), Donut Carousel (manège beignet), Moon Telescope (télescope lunaire).

**Ordre d'apparition des dalles** : Tapis → (Cuve, gratuite) → (Bassin, gratuit) → Tapis 2 + Bouncy Fence → Enclos (quand les enclos sont pleins) → autres décorations → Lit douillet (R ≥ 1). Après un Grand Splorch, toutes les dalles déjà découvertes restent visibles.

**Ce qui ne s'achète jamais** : la Cuve et son niveau, le Bassin, la Fontaine de Gelée, le Pot, l'Étagère à trophées, le bol. Ils sont là dès l'accueil et ne sont jamais remis à zéro.

### 4.7 Presser (SPLORCH) et PERFECT

- **Geste** : touche d'action principale (□ à la manette, E au clavier, ou clic sur le squishy) sur le squishy **ciblé** de son ranch, à 10 studs au plus. Le jeu choisit la cible lui-même (règle exacte au §10.4) : les squishies prêts passent avant ceux en recharge, et après une pression la cible passe au prochain squishy prêt en 0,15 s. **Presser a sa touche, Prendre a la sienne** (○ / Q, §4.10) : un enfant qui martèle □ ne prend jamais un squishy par erreur. L'invite « □ Presser » est dessinée par le jeu, en grand pour la télé, et la touche est liée par `ContextActionService` ; on n'utilise **pas** de `ProximityPrompt`, dont le choix de cible, la ligne de vue et la liaison de touche appartiennent au moteur et ne se testent pas hors de Roblox (§10.4).
- **Recharge** : 8 s par squishy [`Balance.Press.Cooldown`]. Un anneau se remplit sous le squishy ; prêt, il est un peu gonflé et brille.
- **Récompense** : `floor(max(10, 12 × revenu) × (PERFECT ? 2 : 1) × (1 + 0,10 × min(5, série)) × (familleKittyComplète ? 1,10 : 1))`.
- **PERFECT** : chaque squishy rebondit au repos avec une période de 1,2 s, calée sur `Clock.now()` et un décalage propre (`hash(uid)`), donc identique côté client et côté serveur. La fenêtre PERFECT va de **0,08 s avant à 0,20 s après le sommet** du rebond (0,28 s, soit 23 % du cycle). Elle est décalée vers le « tard » parce que le joueur réagit à une image qui arrive en retard : télé familiale 50 à 150 ms (mode Jeu souvent coupé), plus 1 à 2 images de rendu et la liaison sans fil de la manette. La même règle vaut pour tous les appareils, sans bonus déclaré par le client. Un petit anneau blanc se resserre et touche le corps au sommet.
- **Série PERFECT** : chaque PERFECT de suite ajoute +10 % (max +50 % à 5 de suite). Une pression non PERFECT remet la série à 0, sans aucune punition (la récompense de base reste). 6 s sans pression remettent aussi la série à 0. Le son monte d'un demi-ton à chaque marche.
- **Vérification serveur** : le client envoie `Press(uid, tClient)`. Le serveur accepte `tClient` s'il est dans `[maintenant − 0,35 s ; maintenant + 0,05 s]`, sinon il prend `maintenant`. Il calcule la phase du rebond à `tClient`. Au pire, un tricheur obtient ce qu'obtient un joueur adroit (×2) : c'est borné et accepté. C'est aussi pourquoi **aucun classement ne compte les PERFECT** (§6.9).
- **Jauge du serveur** : +1 par pression, +1 de plus si PERFECT (§4.23).
- Débit maximal accepté : 12 pressions/s par joueur (au-delà, ignorées sans message).

### 4.8 Le Pot à Pièces

- Le revenu passif s'accumule dans le Pot (calcul paresseux, §12.3). Le montant flotte au-dessus du Pot.
- **Encaisser** : marcher à 5 studs au plus du Pot (position vérifiée par le serveur à chaque tick). Pas de limite de contenu en ligne : le Pot ne fait jamais perdre de pièces.
- **Pass Pot automatique** : le Pot s'encaisse tout seul toutes les 5 s, où que soit le joueur. Confort seulement.
- Hors ligne : le Pot reçoit 25 % du revenu, dans la limite hors ligne (§4.19).

### 4.9 La Cuve à Gelée

- **Fonctionnement** : la Cuve se remplit (niveau de gelée visible) pendant l'intervalle, puis une goutte tombe et éclot en 2 s dans la première place d'enclos libre. Gratuit. Si les enclos sont pleins, la goutte attend dans la Cuve (« Plein ! ») et le minuteur s'arrête. La Cuve ne tourne que si le joueur est en ligne.
- **Niveau de la Cuve, donné par R** : jamais acheté, ni avec des pièces ni avec des Robux. Il monte tout seul à chaque Grand Splorch et n'est jamais remis à zéro.

| R | 0 | 1 | 2 | 3 | 4 | 5 | 6 | ≥ 7 |
|---|---|---|---|---|---|---|---|---|
| Qualité = `min(8, 1 + R)` | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| Vitesse = `min(10, 3 + 2 × R)` | 3 | 5 | 7 | 9 | 10 | 10 | 10 | 10 |
| Intervalle (s) | 55,3 | 39,9 | 28,9 | 20,8 | 17,7 | 17,7 | 17,7 | 17,7 |
| Buses = `min(5, R)` (mutations ×) | 0 (×1) | 1 (×1,5) | 2 (×2) | 3 (×2,5) | 4 (×3) | 5 (×3,5) | 5 (×3,5) | 5 (×3,5) |

Pendant l'accueil (jusqu'à 5:00 de jeu), la Cuve suit le script du §3 (une goutte toutes les 90 s), pour garder 3 à 4 squishies à 5:00. La vitesse 3 de départ remplace les niveaux de Vitesse qu'un joueur achetait pendant sa première boucle dans la version 1.0 : sans elle, le premier Grand Splorch glissait vers 15 min (simulation, §4.24).

- **Intervalle** : `90 × 0,85^vitesse` s (90 → 17,7 s), ×0,9 avec la famille Bunny complète (§4.17).
- **Chances identiques pour tous à R égal** : un achat peut faire avancer plus vite (§8.1, n° 10), jamais changer une probabilité à R égal. Le Guide affiche les chances du niveau du joueur.
- **Rareté** : tirée dans la table du niveau de Qualité (en %). **Affichée sur la Cuve** en barres simples et en détail dans l'onglet Guide du Squishydex.

| Qualité | Commun | Peu commun | Rare | Épique | Légendaire | Mythique | Secret |
|---|---|---|---|---|---|---|---|
| 0 | 80 | 17 | 2,6 | 0,4 | — | — | — |
| 1 | 74 | 21 | 4 | 0,9 | 0,1 | — | — |
| 2 | 67 | 25 | 6 | 1,7 | 0,28 | 0,02 | — |
| 3 | 60 | 28 | 8,5 | 2,9 | 0,55 | 0,05 | — |
| 4 | 52 | 31 | 11,5 | 4,5 | 0,9 | 0,1 | — |
| 5 | 45 | 32 | 15 | 6,5 | 1,3 | 0,19 | 0,01 |
| 6 | 38 | 33 | 18 | 8,7 | 1,95 | 0,33 | 0,02 |
| 7 | 31,5 | 33 | 21 | 11 | 2,9 | 0,57 | 0,03 |
| 8 | 25 | 32 | 24 | 14 | 4 | 0,96 | 0,04 (1 sur 2 500) |

- **Espèce** : tirée au hasard, à chances égales, parmi les espèces de la rareté tirée **dans les familles débloquées** : R = 0 → Jelly, Kitty, Froggy ; R = 1 → + Axolo ; R = 3 → + Bunny ; R = 5 → + Spiky. Si la rareté tirée n'a aucune espèce débloquée, on prend la rareté juste en dessous. Les bébés (Rush, MEGA, cadeaux, Golden) viennent de **toutes** les familles : les autres joueurs font découvrir les familles plus tôt.
- **Secrets** : un tirage Secret donne Royal Plop ; pendant la Jelly Moon, il donne Moonplop ou Royal Plop à chances égales.
- **Nouveauté garantie** : les 3 premiers tirages naturels du compte prennent une espèce **pas encore possédée** dans la rareté tirée, s'il en reste. La rareté, elle, suit la table affichée. La Cuve affiche « Nouveauté garantie (3) ».
- **Protection contre la malchance** : après 40 naissances de suite sans Rare ou mieux, la suivante est au moins Rare ; après 150 sans Épique ou mieux, au moins Épique. Les compteurs sont affichés dans le Guide (« Rare garanti dans 12 »). C'est une règle publique, pas un hasard caché.
- **Mutation** : tirage du §4.5.
- Naissance : taille 1, 0 étoile. Les naissances Rare+ ont leur propre animation (§9.4) ; Légendaire+ lancent une bannière serveur.

### 4.10 Le Bassin de Fusion et les combos

- **Jumeaux** : même espèce **et** même nombre d'étoiles. La mutation peut être différente.
- **Les jumeaux se voient** : quand on porte un squishy, ses jumeaux (enclos et Bassin) affichent un cœur rose qui pulse. Au repos, le squishy ciblé fait pulser les cœurs de ses jumeaux pendant 1 s. La puce « Menu » du HUD et le bouton Ranch du menu portent une pastille « ♥ 3 » : le nombre de paires de jumeaux. Dans la grille du panneau Ranch, les jumeaux portent le même petit cœur.
- **Prendre et lancer** : « Prendre » (○ à la manette, Q au clavier) : le squishy ciblé se pose sur la tête du joueur (marche normale). Le portage est un **état du serveur**, pas un objet physique soudé au personnage : le client dessine le squishy sur la tête. Il se termine tout seul (le squishy retourne à sa place) si le joueur meurt, réapparaît, sort de son ranch (passe le portail), ouvre un panneau, monte sur sa monture ou quitte le serveur. Pendant le portage : □ = « Lancer » seulement à 12 studs ou moins du Bassin (sinon aucune invite □) ; ○ / Q = « Poser » (il retourne à sa place) ; Bondir et Monter sont ignorés (son `Bump`, aucune vibration). L'invite du Bassin dit « **Fusion !** » si un jumeau y attend, sinon « Poser dans le Bassin ». Un joueur porte un seul squishy à la fois. Après la leçon de fusion de l'accueil, l'invite « Prendre » n'est plus qu'une petite deuxième ligne sous « Presser ».
- **Dans le Bassin** : 5 places d'attente [`Balance.Fusion.PoolSlots = 5`] (6 avec la famille Axolo complète). Un squishy qui attend compte dans les places d'enclos, grandit et rapporte normalement. Si le Bassin est plein et qu'aucun jumeau n'y attend : refus doux (« Bassin plein ! »), le squishy reste porté.
- **Fusion** : si un jumeau attend, les deux fusionnent après 0,4 s (minuteur du serveur ; le client cale l'animation sur l'heure envoyée, jamais l'inverse) :

```
taille   = (a + b) × 1,25
étoiles  = min(5, étoiles + 1)          (deux 5 étoiles donnent un 5 étoiles plus gros)
mutation = celle qui a le plus gros multiplicateur
Meilleur Ami, tenue, verrou : gardés si l'un des deux les avait
```

- **Combo en chaîne** : après chaque fusion, le serveur cherche dans le Bassin un jumeau du résultat (même espèce, nouveau nombre d'étoiles). S'il y en a un, ils fusionnent 0,6 s plus tard, et ainsi de suite. Le combo n compte les fusions de la chaîne.
- **Récompense de combo** : à l'étape k (1, 2, 3…), `20 × k ×` revenu du squishy obtenu, en pièces ; jauge du serveur +3 par étape. Combo ≥ 3 : message personnel ; ≥ 4 : bannière serveur ; ≥ 5 : bannière + grand tampon « COMBO x5 ! ».
- **Exemple** : le Bassin contient un Plop 0★, un Plop 1★ et un Plop 2★. Le joueur lance un Plop 0★ : 0★+0★ → 1★ (combo 1), +1★ → 2★ (combo 2), +2★ → 3★ (combo 3). Avec 5 places, le combo maximal sans 5 étoiles est ×5.
- **Version menu** (manette, accessibilité) : panneau Ranch → « Fusionner » : choisir A, puis choisir B (seuls les jumeaux de A sont proposés). Les deux sautent dans le Bassin et suivent la même règle, combo compris. Jamais de glisser-déposer.
- **Tout fusionner** (panneau Ranch, un seul bouton) : le serveur fusionne en chaîne toutes les paires de jumeaux **non verrouillés**, enclos et Boîte à dodo compris. Il place lui-même les squishies dans le Bassin pour faire les plus longs combos possibles (même règle de chaîne, mêmes places), puis recommence tant qu'il reste des paires. Le résultat va dans l'enclos s'il y a de la place, sinon dans la Boîte à dodo. Les combos comptent comme à la main (récompenses, bannières, clips, classement). Les squishies verrouillés (§4.13) ne fusionnent qu'à la main, pour ne jamais perdre une mutation rare sans le vouloir.
- Aucun hasard, aucun coût.

### 4.11 Créatures en fuite et Golden Wobbler

**Créature en fuite personnelle**
- Elle saute de **ta** Fontaine de Gelée (devant ton portail, côté rue), 60 s après la fin de la précédente (50 s avec la famille Froggy complète). Première à 2:00 de jeu (accueil).
- Elle n'est visible et attrapable **que par toi** (envoyée à ton seul client), avec un anneau à ta couleur.
- Trajet : petits bonds (un bond de 4,5 studs toutes les 0,5 s, une pause de 0,6 s tous les 3 bonds, soit ≈ 7,5 studs/s en moyenne), à 35 studs au plus de la Fontaine, pendant **20 s** au plus. Ensuite elle replonge dans la Fontaine : aucune punition, la suivante viendra.
- Attraper : □ à **5 studs** au plus (le serveur accepte jusqu'à 6,5 studs pour la latence), ou un bond qui atterrit à 5 studs au plus (capture automatique, §4.12).
- Contenu : rareté tirée dans la table de la Qualité de la Cuve (§4.9), familles débloquées, mutation tirée (buses comprises), **taille = 5 % du plus gros squishy du joueur** (minimum 1), 0 étoile.
- En pause pendant : un BOOP RUSH (le Wild Wobbler personnel la remplace, §4.21.5), un MEGA SQUISH, son propre Grand Splorch, l'accueil entre 2:45 et 5:00, et quand enclos, Boîte à dodo et Boîte aux lettres sont pleins.

**Golden Wobbler (partagé)**
- Lâché depuis la fontaine de la place à **:00:30, :10:30, :30:30 et :40:30** UTC.
- Visible par tous, y compris les joueurs Cozy. Trajet calculé par le serveur dans les rues de la ville (§12.5), **30 s**, vitesse 14 studs/s au début qui baisse jusqu'à 10 studs/s.
- Le premier qui l'attrape (5 studs, tolérance 6,5) gagne un squishy **Doré garanti**, de rareté tirée dans la table de Qualité 4, toutes familles, **taille = 25 % de son plus gros squishy** (minimum 10).
- Tous les joueurs à 30 studs au plus au moment de la capture : 60 s de leur revenu et jauge +4.
- Personne ne l'attrape : il éclate en confettis dorés ; les joueurs à 30 studs reçoivent 30 s de leur revenu.
- **Course amicale** : le gagnant ne peut pas gagner le Golden Wobbler suivant pendant 20 min (il peut courir et recevoir la récompense « de près », mais l'invite « Attraper » ne lui est pas proposée ; message « Laisse les autres gagner celle-ci ! »).

### 4.12 Monter sur son squishy

| Seuil de taille | Selle | Effet |
|---|---|---|
| **1 200** (atteint vers 4:30 au premier jeu) | Petite selle | Vitesse **×1,4** (WalkSpeed 16 → 22,4), saut 7,2 → 8,6 studs |
| 1 000 000 | Grande selle | Même vitesse ×1,4, saut 10,8 studs, éclaboussure à l'atterrissage |
| 1e12 | Selle géante | Même vitesse ×1,4, saut 13 studs, onde de choc visuelle à l'atterrissage |

Les selles sont **gagnées pour toujours** : le palier compte la plus grande taille jamais atteinte par un de ses squishies (`stats.biggestEver`), pas la taille du moment. Juste après un Grand Splorch, on remonte donc tout de suite.

- **Monture** : par défaut le plus gros squishy (n'importe lequel, dès que la première selle est gagnée) ; changeable dans le panneau Ranch. Sa **taille affichée dépend de la selle, pas de la taille du moment** : Petite selle 2,85× (Ø 5,7 studs), Grande 3,5× (Ø 7), Géante 4× (Ø 8). Le squishy garde sa vraie taille dans ses chiffres ; l'affichage reste stable et ne fait jamais grandir le personnage sans limite.
- **Monter / descendre** : L2 (R au clavier), n'importe où. La monture saute vers le joueur (petit pop depuis le ranch). Le serveur règle trois valeurs fixes par selle et rien d'autre : `WalkSpeed` (22,4), `JumpHeight` (table ci-dessus) et `HipHeight` = valeur de base + 0,75 × diamètre affiché (+4,3 / +5,3 / +6 studs). Le client dessine la monture sous le personnage. Pas de soudure physique, pas de siège (`Seat`), pas d'animation qui décide de quoi que ce soit : monter et descendre sont des états du serveur. La monture disparaît toute seule à la mort, à la réapparition, en entrant dans le Bassin ou en prenant un squishy ; on remonte d'un appui.
- La vitesse est la même pour toutes les selles : la monture est un plaisir et un signe de statut, pas un avantage acheté. Toutes les selles sont gagnées par la taille ; le pack Selles et Traînées ne change que l'apparence.
- On descend tout seul pour « Prendre » un squishy, nourrir son Meilleur Ami au bol ou entrer dans le Bassin. On peut presser, attraper et booper depuis sa monture.

**Bondir** (R2, Maj au clavier) : petit élan de **12 studs en 0,35 s**, recharge **4 s**.
- **Un bond scripté, pas une impulsion physique** : le client déplace son personnage le long d'un arc fixe (12 studs au sol, sommet à 2,5 studs), image par image, et s'arrête devant le premier obstacle solide (un rayon vers l'avant, contre la liste des solides du §11). La longueur ne dépend donc ni du frottement, ni de la fréquence d'image, ni d'une collision qui rebondit.
- **Visée automatique sur la position future** : le trajet des créatures est connu du client (`SeededPath`), qui vise la position qu'aura la créature à l'atterrissage, `pos(t + 0,35)`. Il vise si cette position est à **16 studs** au plus, dans un cône de **±40°** autour de la direction du stick gauche (au clavier, des touches de déplacement ; au repos, de la direction du personnage). **Jamais selon la caméra.** Sinon, le bond part droit devant. Le marqueur de cible ne change que si une autre créature est 20 % plus proche.
- **Capture automatique à l'atterrissage** si la créature est à 5 studs au plus (8 pour le propriétaire de sa propre fuite du Rush, §4.21.2). Le serveur la tente lui-même à t + 0,35 s, avec sa tolérance (6,5 ; 9,5). Il calcule le point d'atterrissage **à partir de la géométrie du bond** (position validée au départ + direction × 12 studs, raccourci par le même rayon contre les solides), **pas** à partir de l'endroit où la physique a posé le personnage : le résultat est identique sur le client et sur le serveur, et testable hors de Roblox. Un seul bouton suffit donc pour attraper, à la manette comme au clavier.
- □ / Attraper reste possible, avec un **tampon d'entrée de 0,25 s** : un appui juste avant d'entrer à portée compte.
- Le client fait le bond tout de suite (sensation immédiate) et envoie `Leap(dirX, dirZ)` ; le serveur accorde la distance en plus au contrôle de déplacement seulement si la recharge est respectée (§12.8).

### 4.13 Vendre, ranger et relâcher

- **Vendre** (Boutique de la place, ou panneau Ranch → Vendre) : 60 s du revenu actuel du squishy (minimum 10). Refusé pour un Meilleur Ami ou un squishy verrouillé. **Maintien de 0,6 s** pour un Rare ou mieux, ou pour un squishy muté. **Confirmation en 2 étapes** pour un Épique ou mieux, ou une mutation Doré ou mieux (×5 et plus) : la 2e étape montre la carte du squishy avec son « 1 sur X » (« Ce Wibble Doré : 1 sur 1 200 ! »).
- **Ranger** (panneau Ranch, un seul bouton) : propose de vendre d'un coup les squishies Communs et Peu communs, 0 étoile, sans mutation, non verrouillés, ni Meilleur Ami ni monture, dont l'espèce est déjà tamponnée. Le plus gros de chaque espèce est toujours gardé. Un aperçu liste ce qui part (« Vendre 14 squishies = 3,2K ») ; on valide par un maintien de 0,6 s. Rien ne part sans cet aperçu.
- **Relâcher** (panneau Ranch → Relâcher, ou à la **Prairie des copains** sur les collines) : maintien de 0,6 s pour **chaque** relâche, même un Commun ; confirmation en 2 étapes comme pour la vente pour un Épique+ ou une mutation Doré+. Ton positif : « Il part vivre dans les collines ! ». Le squishy fait un signe et part en rebondissant. **+1 Fame** (20 Fame au plus par jour de cette façon). Il ne revient pas dans le ranch, mais les 12 derniers squishies relâchés **restent visibles dans la Prairie des copains** (pour leur ancien propriétaire seulement) et lui font coucou quand il passe.
- **Verrou** (cadenas) : un squishy verrouillé ne peut être ni vendu, ni relâché, ni rangé, ni lancé par erreur. Il peut fusionner si le joueur le choisit (à la main). **Verrou automatique à la naissance** pour toute rareté Légendaire ou mieux et toute mutation Galaxie ou mieux (×8 et plus), cadenas visible ; le joueur peut l'enlever.

### 4.14 Enclos, Boîte à dodo, Boîte aux lettres

| Lieu | Places | Grandit et rapporte ? | Boopable ? |
|---|---|---|---|
| Enclos (dont le Bassin) | 4 au départ, +1 par niveau de la dalle Enclos (18), **+6 avec le pass Grand Ranch (24 au plus, jamais plus)** | Oui | Oui (sauf protections) |
| Boîte à dodo (Dodo Box) | 60 | Non (ils dorment) | Non |
| Boîte aux lettres (cadeaux) | 20 | Non | Non |

- Une naissance de la Cuve va dans un enclos libre, sinon la goutte attend dans la Cuve.
- Une créature attrapée ou un bébé reçu va dans un enclos libre, sinon dans la Boîte à dodo, sinon dans la Boîte aux lettres. Si les trois sont pleines : le bébé devient 60 s de revenu, avec un message clair. Jamais une perte silencieuse.
- Échanger un squishy entre enclos et Boîte à dodo : panneau Ranch, 2 gestes.
- **24 squishies affichés au plus par ranch** (16 ranchs × 24 = 384 sur le serveur), avec niveaux de détail (§5.2, §12.9).

### 4.15 Grand Splorch (renaissance)

**Condition** : le plus gros squishy du joueur atteint l'objectif de son niveau R. Pour **entrer dans la file** (§2.4), le joueur doit être dans son ranch et ne rien porter. Ensuite, le Grand Splorch est **garanti** : rien n'est revérifié au départ, et le joueur peut sortir du ranch (pour sa créature en fuite, par exemple). Le squishy qui va s'envoler attend en tremblant : il ne vient pas à la clôture et ne peut être ni boopé, ni vendu, ni relâché, ni fusionné tant qu'il attend. Si le joueur porte un squishy au départ, celui-ci est posé tout seul.

| R → R+1 | Objectif (taille du plus gros) | R → R+1 | Objectif |
|---|---|---|---|
| 0 → 1 | **15 000** | 10 → 11 | 310 M |
| 1 → 2 | 40 000 | 11 → 12 | 830 M |
| 2 → 3 | 110 000 | 12 → 13 | 2,3 B |
| 3 → 4 | 300 000 | 13 → 14 | 6,1 B |
| 4 → 5 | 800 000 | 14 → 15 | 16 B |
| 5 → 6 | 2,2 M | 15 → 16 | 44 B |
| 6 → 7 | 5,8 M | 16 → 17 | 120 B |
| 7 → 8 | 16 M | 17 → 18 | 320 B |
| 8 → 9 | 42 M | 18 → 19 | 870 B |
| 9 → 10 | 110 M | 19 → 20 | 2,4 T |
| R ≥ 20 | objectif précédent × 2,7, arrondi à 2 chiffres significatifs | | |

La table vit en configuration [`Balance.Splorch.Targets`] : elle suit `15 000 × 2,7^R` arrondi, et la simulation peut l'ajuster ligne par ligne.

**Écran d'aperçu obligatoire**, fait pour des enfants qui lisent peu :
1. En haut, **3 grandes tuiles « Tu gagnes »** : « Croissance ×2 pour toujours », le déblocage de ce niveau (nouvelle famille, Cuve meilleure ou Meilleur Ami en plus), « +5 Fame ».
2. Une petite animation avant/après : le squishy redevient petit, puis regrandit très vite.
3. S'il reste des pièces : une ligne rouge « **Tu vas perdre 1,2 M pièces** » et un bouton « **Dépenser d'abord** » qui ouvre l'onglet *Dalles* du panneau Ranch.
4. Le choix du squishy qui s'envole : par défaut, le plus gros qui n'est pas un Meilleur Ami (s'ils le sont tous, le plus gros).
5. Le bouton à **maintenir 1,5 s** (✕ à la manette) et la case « Filmer mon Grand Splorch ».

Le détail en deux colonnes « Tu gardes » / « Repart de zéro » et le prochain objectif sont derrière un bouton « **Détails** ». Si le joueur a acheté un paquet de pièces il y a moins de 30 min et en garde encore au moins la moitié, une **deuxième confirmation** s'affiche avant le maintien (« Tu as acheté ces pièces il y a 12 min. Les dépenser d'abord ? »). Rien ne part par erreur.

| Gagné | Repart de zéro | Gardé |
|---|---|---|
| Croissance ×2 pour toujours (×2^(R+1)) ; **Cuve meilleure** (qualité +1 jusqu'à 8, vitesse +2 jusqu'à 10, buses +1 jusqu'à 5, §4.9) ; à R = 1 : famille Axolo, Lit douillet ; à R = 3 : famille Bunny, 2e Meilleur Ami ; à R = 5 : famille Spiky ; à R = 10 : 3e Meilleur Ami ; +5 Fame ; titres à R = 5, 10, 15, 20 | Pièces, Pot, Tapis à Goûter, décorations ; la **taille** de chaque squishy (retour à 1) | Tous les squishies (espèce, mutation, étoiles, tenue, verrou), niveau de la Cuve, selles gagnées (on remonte tout de suite), places d'enclos, Lit douillet, Boîte à dodo, Boîte aux lettres, Squishydex, bonus de famille, Fame, jours de Plop, Étagère à trophées, Meilleurs Amis, passes et achats « Pour toujours », réglages, statistiques |

**Le spectacle** (7,5 s, détail au §9.4) : le squishy choisi s'envole vers la place, gonfle et éclate au ralenti au-dessus du MEGA pad en un grand nuage de confettis de gelée. Une pluie de pièces et de bébés tombe sur **chaque joueur du serveur** (Cozy compris). Puis **le squishy sort du nuage, tout petit, fait coucou et rejoint le héros en rebondissant** ; la caméra du héros le suit et le texte dit « **Plop est là ! ×2 pour toujours** » (avec son vrai nom). Il garde tout, sauf sa taille. L'enfant voit son squishy revenir, pas seulement exploser. Bannière serveur. Forte vibration pour le héros. Capture vidéo proposée (§9.5).

**Cadeaux pour les autres joueurs** (payés par le jeu, jamais pris au héros) : 60 s de leur revenu + **1 bébé** de l'espèce qui s'est envolée ; si elle est Épique ou mieux, le bébé est l'espèce Peu commune de sa famille (Wibble pour un Secret), pour que le choix du squishy ne fasse pas pleuvoir des Mythiques (taille = 5 % de leur plus gros squishy, minimum 1 ; 0 étoile ; sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible). 10 bébés de Grand Splorch au plus par jour et par joueur (ensuite, les pièces seulement). Réglage « Recevoir les cadeaux » (activé par défaut).

**Applaudir** : chaque autre joueur voit une puce APPLAUDIR pendant 8 s (croix → à la manette, F au clavier). Voir §6.7.

**File du serveur** : voir §2.4. Pendant l'attente, le squishy « se prépare » (il tremble et brille) ; le joueur peut continuer à jouer, sa place est garantie (voir *Condition*). S'il quitte le serveur (ou si le serveur ferme) avant son tour, sa place est rendue et **rien n'est remis à zéro** : il refera son Grand Splorch plus tard. Le Grand Splorch est appliqué au profil **d'un seul bloc** au moment de l'éclatement (3,2 s, minuteur du serveur), puis sauvegardé tout de suite ; le spectacle du client suit l'heure envoyée, et un client qui ne le joue pas (chargement, Mouvement réduit) ne change rien au résultat.

### 4.16 L'Étagère à trophées

- Une étagère dans le ranch, avec une place par espèce (26). Elle garde la **taille record** jamais atteinte par un squishy de cette espèce (mise à jour en direct et à chaque Grand Splorch). On ne sent jamais qu'on a « perdu » sa créature.
- Chaque trophée est une petite statue de l'espèce, avec la taille record écrite dessous.

| Palier du record | Statue | Bonus de revenu permanent (additif dans A) |
|---|---|---|
| ≥ 1 000 | Bronze | +2 % |
| ≥ 1 million | Argent | +4 % |
| ≥ 1 milliard | Or | +6 % |
| ≥ 1e12 | Cristal | +8 % |

Maximum : 26 × 8 % = +208 %.

### 4.17 Le Squishydex

- **26 pages d'espèces** (tampon de l'espèce, forme normale) et **234 entrées de mutation** (26 espèces × 9 mutations). Total : 260 tampons. Plus 130 **badges d'étoiles** (★1 à ★5 atteint, par espèce).
- Une entrée est tamponnée dès que le joueur possède un squishy qui la remplit (naissance, capture, bébé, fusion, cadeau). Elle reste même si le squishy part.
- Fiche d'espèce : nom, famille, rareté, aspect, mutations trouvées (silhouettes grises pour les autres), meilleur exemplaire, taille record.
- **Page dorée** : les 8 mutations hors Lunaire d'une espèce trouvées → la page devient dorée, +1 % de revenu (additif dans A). La mutation Lunaire est en plus : elle pose un petit croissant d'argent sur la page, sans bonus. Rater les séances de la Lune n'empêche donc aucune page dorée.
- **Bonus de famille** (les 4 espèces de la famille tamponnées) :

| Famille | Bonus permanent |
|---|---|
| Jelly | +10 % de croissance |
| Kitty | +10 % de pièces par pression |
| Froggy | Créature en fuite toutes les 50 s au lieu de 60 |
| Axolo | +1 place dans le Bassin de Fusion (6) |
| Bunny | Intervalle de la Cuve −10 % |
| Spiky | Limite hors ligne +1 h |

- **Jalons** (tampons d'espèces + de mutations) : 10 → titre « Little Collector » ; 25 → couleur de selle Menthe ; 50 → traînée Bulles ; 75 → titre « Squishologist » ; 100 → drapeau de ranch Squishydex ; 130 → couleur de selle Lavande ; 160 → thème de ranch « Moonlit » ; 200 → titre « Dex Master » ; 260 → Squishydex doré et emote couronne. Tous gratuits, tous cosmétiques.
- Onglet **Guide** : toutes les probabilités (Cuve par niveau, mutations, Golden, MEGA, Wild Wobblers, cadeaux), les compteurs de la protection contre la malchance, les règles du BOOP RUSH.

### 4.18 Fame

- Sources : la **Fame du Rush**, 30 par jour au plus en tout : squishy boopé puis rendu (+1), capture « Héros » (+2), Wild Wobbler attrapé (+1, partagé ou personnel, en mode Rush comme en mode Cozy). Puis : relâcher (+1, 20 par jour au plus), Grand Splorch (+5), participer à un MEGA SQUISH avec au moins 10 points (+1). Un joueur Cozy atteint donc le plafond du jour aussi vite qu'un joueur Rush (jusqu'à 3 Wild Wobblers par Rush) : le mode sûr n'est jamais moins rentable.
- Effet : +1 % de revenu par point, jusqu'à 300 points (+300 %). Au-delà, la Fame continue de monter pour le prestige (affichée sous le panneau du ranch).
- **Au lancement**, la Fame n'est créditée que si le propriétaire est sur le serveur (c'est toujours le cas : seuls les présents sont boopables). La lignée complète (bébés nés partout) arrive en janvier (§17).

### 4.19 Hors ligne

- Calculé une seule fois au chargement : `durée = clamp(Clock.unix() − lastOnline, 0, limite)`.
- **Croissance hors ligne** : chaque squishy des enclos grandit de `croissance sans boost × 50 % × durée`.
- **Pièces hors ligne** : le Pot reçoit `revenu au départ (sans boost) × 25 % × durée`.
- **Limite** : 8 h ; 12 h avec le Lit douillet (acheté avec des pièces, gardé pour toujours) ; +1 h avec la famille Spiky. Aucun achat Robux ne change cette limite.
- **Écran de retour** (§7.2) : « Mochi Mew a grossi de +X pendant ton absence ! » (le vrai nom du Meilleur Ami n° 1, sinon du plus gros), et il est réellement plus gros. Si l'objectif de Grand Splorch est atteint, l'écran le dit.

### 4.20 Nourrir Plop, objectifs du jour, carte « Plop a sommeil »

- **Nourrir Plop** (nom du système, hérité du concept) : un grand bol dans le ranch. Le bol nourrit **ton Meilleur Ami n° 1** (au début, ton premier Plop) ; les textes écrivent son vrai nom (« Nourris Mochi Mew »). Une fois par jour UTC, maintenir □ **5 s** devant le bol : le Meilleur Ami accourt et mange (nom nom), le compteur de jours monte de 1. Les paliers comptent le **total de jours**, jamais une série : rater un jour ne fait rien perdre. « Jour 42 » flotte au-dessus du ranch. Paliers et récompenses : §7.3.
- **Objectifs du jour** : 3 par jour (facile, moyen, difficile), §7.4.
- **Carte « Plop a sommeil »** : après 60 min de jeu dans la session (puis après 120 min), une petite carte non bloquante (§10.3), où Big Plop bâille : « Tes squishies continuent de grandir pendant que tu te reposes. » Bouton « OK ». Aucune pénalité, aucun boost pour rester.

### 4.21 BOOP RUSH

Interrupteur de configuration [`Features.BoopRush`] : `"on"` (lancement), `"events"` (seulement pendant la Jelly Moon et les Squish Parties d'administrateur), `"off"`. Changeable sans nouvelle version (§12.2). Avec `"off"`, les Wild Wobblers (partagés et personnels) sont quand même lâchés aux mêmes heures pour tous.

#### 4.21.1 Le choix du mode, des deux côtés

- **Avant tout choix, le joueur est en mode Cozy.** Pendant ses 15 premières minutes de jeu cumulé (bouclier débutant), il regarde le Rush, poursuit les Wild Wobblers (dont le sien, §4.21.5) et le Golden Wobbler.
- **La carte du choix** s'ouvre une seule fois, **au calme**, dès 15:00 de jeu : le joueur est dans son ranch, ne bouge plus depuis 1,5 s, aucun Rush ni MEGA n'est en cours et le prochain Rush est dans plus de 60 s. Elle montre deux gros boutons, « **Je joue au BOOP RUSH** » et « **Je reste tranquille** » (mode Cozy), et une petite **animation de 6 s qui tourne en boucle** : un nez boopé, ATCHOUM, la poursuite, puis le squishy qui rentre avec des cadeaux (« +Fame +pièces »). Une ligne rassure : « **Plop ne s'enfuit jamais** » (le Meilleur Ami n° 1, avec son vrai nom). **Garde d'entrée de 0,6 s** (boutons grisés, aucun appui accepté) : un ✕ appuyé pour sauter au moment où elle s'ouvre ne choisit rien par erreur. Les deux boutons font 440 × 120 px TV, texte de 40 px TV, glyphes ✕ et ○ à côté. Sans réponse en 20 s : **Cozy** (le choix le plus sûr).
- **Seuls les joueurs en mode Rush peuvent booper et être boopés**, et attraper les squishies en fuite du Rush.
- Les joueurs Cozy poursuivent les **Wild Wobblers** (partagés et personnel) et le **Golden Wobbler**, pressent le MEGA, reçoivent les cadeaux du Grand Splorch, la jauge et les Squish Parties, et gagnent autant de Fame que les joueurs Rush (§4.18). Les squishies d'un ranch Cozy ne viennent jamais à la clôture.
- **Après le premier boop subi**, quand le squishy est rentré, une petite carte non bloquante : « **Wibble revient toujours ! +X pièces +1 Fame** », avec les boutons « Continuer », « Mode Cozy » et « Pas ce joueur » (§4.21.4). Elle n'apparaît qu'une fois.
- **Changer de mode** (Réglages, ou la carte ci-dessus). **Passer en Cozy est immédiat, sans recharge** : les squishies quittent la clôture tout de suite, ceux déjà en fuite rentrent aussitôt chez eux (sans bonus, pour que ce ne soit pas une astuce), et le joueur ne peut plus booper jusqu'à la fin de ce Rush. **Passer en Rush** demande une recharge de 60 s depuis le dernier changement, et ne s'applique qu'à la fin du Rush en cours.
- **Serveurs privés** : Cozy pour tous par défaut. Le propriétaire du serveur privé peut activer « BOOP RUSH autorisé » ; chacun choisit ensuite son mode.
- **Repère visuel** : un badge rose « boop » sur le panneau des ranchs boopables (mode Rush, hors bouclier) ; une petite bulle « bouclier » sur un ranch en mode Rush encore protégé. Rien n'est affiché pour les ranchs Cozy : pas de badge dont on pourrait se moquer (« mode bébé »). Chaque joueur voit son propre mode dans son HUD.

#### 4.21.2 Déroulé

| Phase | Détail |
|---|---|
| Sirène (−10 s) | Le ciel vire au rose, musique de gloussements, double vibration (manette), bannière « BOOP RUSH dans 10 ! ». Pour un nouveau avant l'étape 9 de l'accueil : version discrète (§3) |
| Début (:X5:00) | Dans chaque ranch boopable, jusqu'à **4 squishies curieux** éligibles viennent s'appuyer à la clôture, côté rue (choisis au hasard, renouvelés toutes les 20 s) ; **2 seulement** si ce ranch a été boopé au Rush précédent |
| Booper | Un joueur Rush, depuis la rue, **maintient □ 2,5 s** sur le nez d'un squishy à la clôture (8 studs au plus). **5 s** si le propriétaire est à 25 studs au plus de sa clôture (s'il arrive pendant le maintien, le temps restant double). Lâcher, s'éloigner à plus de 8 studs ou une règle qui devient fausse = annulé. Le temps est mesuré par le serveur : un client qui n'envoie jamais « lâché » ne bloque rien, le maintien finit ou s'annule au plus tard 0,5 s après sa fin prévue |
| ATCHOUM | Le squishy éternue (nuage pastel brillant, jamais de morve), saute la clôture et fait un **premier bond de 20 studs à l'opposé du boopeur**, puis rebondit dans la ville sur un **chemin calculé par le serveur** (§12.5). Le propriétaire reçoit **aussitôt une flèche** au bord de l'écran |
| Fuite | **25 s au plus**. Vitesse 16 studs/s au départ, qui baisse de 0,32 stud/s chaque seconde jusqu'à 8 studs/s à 25 s (≈ 300 studs parcourus). Bonds de 0,45 s. Jamais dans un ranch : seulement les rues et la place. Anneau à la couleur du propriétaire, contour `Highlight` |
| Attraper | □, ou un bond qui atterrit près d'elle (§4.12). Rayon **5 studs** (tolérance serveur 6,5), **8 studs pour le propriétaire** (tolérance 9,5). **Le boopeur ne peut pas attraper sa propre fuite pendant ses 6 premières secondes** : la poursuite a vraiment lieu, en ville, pour tout le serveur |
| Fin (:X6:30) | Les squishies à la clôture rentrent. Les fuites en cours continuent jusqu'à leurs 25 s |

#### 4.21.3 Le propriétaire gagne toujours

| Qui attrape | Le propriétaire | L'attrapeur |
|---|---|---|
| **Le propriétaire** | Capture « **Héros** » : +10 % de taille pour ce squishy, 120 s de son revenu, +2 Fame | — |
| **Un autre joueur Rush** | **Son squishy rentre au ranch**, +1 Fame, 60 s de son revenu. Message, le retour d'abord : « **Wibble est rentré ! +1 Fame +X pièces · il a laissé un bébé à Noah** » | Un **bébé** : même espèce, même mutation, 0 étoile, taille = `min(10 % de l'original, 2 × son propre plus gros squishy)`, minimum 1 |
| **Personne** (25 s écoulées) | Le squishy rentre tout seul avec **+5 % de taille** | — |
| Les **autres joueurs Rush à 30 studs au plus** de la capture | — | 20 s de leur revenu et jauge +2 (« Bien joué ! ») : ceux qui ont couru gagnent aussi |

**Mise en scène d'une capture par un autre joueur** (§9.4) : l'attrapeur ne touche **jamais** l'original. Le squishy reçoit une pichenette pleine d'étincelles et éternue une petite **bulle-bébé** brillante ; seule la bulle saute dans les bras de l'attrapeur. L'original fait coucou et rentre au ranch en rebondissant, avec une traînée de cœurs ; le propriétaire a une flèche vers lui. Les images et les clips montrent un cadeau qui naît, jamais un animal emporté (jury §7).

Si le propriétaire quitte le serveur pendant la fuite, le squishy rentre aussitôt chez lui (sauvegardé à sa place).

**Équilibre visé** (mesuré par `EscapeOutcome`, §16.3) : le propriétaire attrape au moins 25 % des fuites, personne ne les attrape dans 20 % des cas au plus. Réglages en cas d'écart : §16.4.

#### 4.21.4 Protections

| Protection | Règle exacte |
|---|---|
| Fuites par ranch | **2 au plus par ranch et par Rush**, et **4 au plus par ranch et par heure** (fenêtre glissante) |
| Cadence du boopeur | **1 boop réussi toutes les 20 s** par joueur ; une même paire boopeur → ranch **au plus 1 fois toutes les 30 min** (on ne peut pas viser le même enfant à chaque Rush) |
| Ranch boopé au Rush précédent | N'envoie que **2 squishies** à la clôture au lieu de 4 |
| **« Pas ce joueur »** | Sur le message « boopé » et sur la carte d'après le premier boop, un bouton « Pas ce joueur » : ce boopeur ne peut plus booper ce joueur jusqu'à ce que l'un des deux quitte le serveur. Règle du serveur, fiable, qui ne dépend pas de la liste de blocage. Le boopeur n'en est pas averti |
| Meilleur Ami | **Jamais boopable** (1 emplacement, le premier Plop d'office ; 2 à R = 3 ; 3 à R = 10). Il ne vient pas à la clôture |
| Mythique et Secret | Boopables **seulement pendant la Jelly Moon** |
| Propriétaire proche | Booper prend **2 fois plus longtemps** (5 s) si le propriétaire est à 25 studs au plus de sa clôture |
| Bouclier débutant | Ranch non boopable tant que le joueur a **moins de 15 min de jeu cumulé** : ses squishies ne viennent pas à la clôture et une petite bulle « bouclier » s'affiche sur le panneau du ranch. Il peut booper les autres s'il a choisi le mode Rush dans les Réglages |
| Petits serveurs | **Wild Wobblers partagés** en plus quand il y a moins de 6 joueurs ; le Wild Wobbler personnel existe à toute taille de serveur (§4.21.5) |
| Pas de fuite en cascade | Un squishy rentré d'une fuite n'est plus boopable jusqu'à la fin de ce Rush ; un squishy porté, dans le Bassin, dans la Boîte à dodo, en attente de Grand Splorch ou né il y a moins de 60 s ne vient pas à la clôture |
| Limite du serveur | 10 fuites en même temps au plus sur le serveur (au-delà, boop refusé : « Trop de squishies en fuite ! ») |
| Bébés | 10 bébés de Rush au plus par jour et par joueur (ensuite : 60 s de revenu à la place) |
| Joueurs bloqués (règle souple) | Le client lit `StarterGui:GetBlockedUserIds()` et l'envoie au serveur (`ReportBlocked`, 200 identifiants au plus). Le serveur refuse les boops entre deux joueurs dont l'un a bloqué l'autre. C'est une liste fournie par le client : un plus, pas une garantie. Les vraies protections restent le mode Cozy (immédiat) et « Pas ce joueur » |

**Ordre de vérification serveur d'un boop** (module pur `RushRules`, testé règle par règle) :

```
si Features.BoopRush == "off" ou (== "events" et pas d'événement)   → refus
si pas de Rush en cours                                              → refus
si boopeur pas en mode Rush, ou propriétaire pas en mode Rush        → refus
si boopeur == propriétaire                                           → refus
si bouclier débutant du propriétaire                                 → refus
si le propriétaire a dit « Pas ce joueur » à ce boopeur              → refus
si l'un a bloqué l'autre (liste souple)                              → refus
si recharge du boopeur (20 s) ou paire boopeur → ranch < 30 min      → refus
si le squishy n'est pas à la clôture, ou Meilleur Ami                → refus
si Mythique ou Secret hors Jelly Moon                                → refus
si 2 fuites pour ce ranch ce Rush, 4 dans l'heure, ou 10 sur le serveur → refus
si boopeur à plus de 8 studs (position validée, budget d'action §12.8) → refus
maintien = 2,5 s, ou 5 s si propriétaire à ≤ 25 studs de sa clôture
à chaque tick du maintien : règles ci-dessus revérifiées (ex. propriétaire passé en Cozy) → sinon annulé
fin du maintien sans rupture → FUITE (chemin, premier bond opposé au boopeur, horodatage, diffusion)
```

**Ordre de vérification d'une capture de fuite du Rush** :

```
si attrapeur pas en mode Rush                                        → refus
si attrapeur == boopeur et fuite de moins de 6 s                     → refus
rayon = 5 + 1,5 (tolérance), ou 8 + 1,5 si attrapeur == propriétaire
si distance à pos(maintenant) > rayon, ou écart vertical > 8, ou pas canAct → refus
sinon → capture (Héros ou bébé) ; joueurs Rush à ≤ 30 studs : 20 s de revenu, jauge +2
```

#### 4.21.5 Wild Wobblers

- À chaque Rush, **chaque joueur (Rush ou Cozy) reçoit 1 Wild Wobbler personnel**, visible et attrapable par lui seul, lâché 15 s après le début du Rush depuis le point de départ le plus proche de lui (fontaine de la place ou bout d'une rue radiale). Il remplace sa créature en fuite personnelle, en pause pendant le Rush. Pas avant l'étape 9 de l'accueil.
- En plus, `3 + 2 × max(0, 6 − N)` Wild Wobblers **partagés**, où N = joueurs sur le serveur (16 joueurs → 3 ; 5 → 5 ; 1 → 13). Lâchés depuis la fontaine de la place et les bouts des rues radiales : un tiers au début, puis par vagues toutes les 15 s. Visibles et attrapables par **tous** (Rush et Cozy).
- Sans propriétaire. Même chemin et même vitesse que les squishies en fuite (25 s).
- Récompense : un bébé d'une espèce au hasard (toutes familles), rareté tirée dans la table de Qualité 3, mutation tirée (buses 0), **taille = 15 % du plus gros squishy de l'attrapeur** (minimum 5), +1 Fame (Fame du Rush, §4.18), jauge +4. **2 partagés au plus par joueur et par Rush**, plus le personnel.
- Avec `Features.BoopRush = "off"`, ils sortent quand même aux heures du Rush (« Wobbler Time »), pour tous, personnel compris.

#### 4.21.6 La démonstration de Big Plop

Pendant l'accueil (§3), vers 3:00 de jeu, Big Plop éternue devant le portail du nouveau joueur et s'enfuit pendant 20 s (8 studs/s, visible par lui seul). Elle est **toujours jouée** : les événements du serveur restent discrets pour le nouveau jusqu'à l'étape 9, ils ne servent donc plus de démonstration. Attrapé : un bébé Plop (10 % de la taille du Plop du joueur, minimum 10). Raté : Big Plop revient, fait un clin d'œil, et la démonstration ne se rejoue pas.

### 4.22 MEGA SQUISH

| Phase | Détail |
|---|---|
| Alerte (:19:45, :49:45) | Grande ombre ronde sur la place, bannière « MEGA SQUISH ! », compte à rebours de 15 s |
| Atterrissage (:20:00, :50:00) | Un squishy géant (24 studs de diamètre, espèce de la semaine en rotation) tombe sur le MEGA pad. Onde de choc, vibration atténuée par la distance (§10.5) |
| Pression (60 s) | Chaque joueur à 20 studs au plus du centre presse (action contextuelle). **1 point** par pression, **3 points** si PERFECT (le géant rebondit avec une période de 2 s ; fenêtre de 0,12 s avant à 0,28 s après le sommet, décalée pour le retard d'image comme au §4.7). Recharge 0,4 s par joueur. La barre de serveur se remplit au-dessus du géant |
| Objectif | `ceil((30 + 50 × N) × indulgence)`, N = joueurs sur le serveur à l'atterrissage (Cozy compris). Indulgence 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite ; retour à 1 après une réussite. Cible de conception : **≈ 80 % de réussite** |
| Réussite | Le géant ÉCLATE en pluie de bébés. Paliers fixes par participant : ≥ 10 points → 1 bébé ; ≥ 40 → 2 ; ≥ 80 → 3. Plus 60 s de revenu, +1 Fame, jauge +5 |
| Échec | Le géant soupire et s'envole doucement. Chaque participant (≥ 10 points) : 60 s de revenu, « Presque ! » |

- **Bébé du MEGA** : espèce au hasard (toutes familles), rareté dans la table de Qualité min(8, qualité du joueur + 2), **chances de mutation × 2**, taille = 20 % du plus gros squishy du joueur (minimum 10), 0 étoile.
- **MEGA MOON SQUISH** (à :20 pendant une Jelly Moon) : mêmes règles, et chaque bébé a 25 % de chance d'être Lunaire.
- Pendant le MEGA, on peut continuer à presser chez soi ; les créatures en fuite personnelles sont en pause.

### 4.23 Jauge du serveur (Wobble Meter) et Jelly Moon

**Jauge du serveur**

Le concept proposait d'additionner la taille de tous les squishies. Avec des tailles de 1 à 1e30, un seul vétéran remplirait la jauge et un nouveau n'y compterait jamais. La jauge compte donc les **actions** de tous, ce qui donne à chacun, même débutant, une vraie part (Annexe A).

| Action (n'importe quel joueur) | Points |
|---|---|
| Pression | 1 (+1 si PERFECT) |
| Naissance dans la Cuve | 2 |
| Pression de pet-sitting | 2 |
| Fusion (par étape de combo) | 3 |
| Créature en fuite attrapée, Wild Wobbler attrapé, Golden vu de près | 4 |
| Capture pendant le Rush (bébé ou Héros) | 6 |
| Être à 30 studs au plus d'une capture du Rush (joueur Rush) | 2 |
| Participation au MEGA (≥ 10 points) | 5 |
| Nourrir Plop | 10 |
| Grand Splorch | 25 |

- **Objectif** = `500 × max(2, N)` points (N = joueurs sur le serveur, recalculé en direct). Avec 16 joueurs actifs (≈ 30 points par minute chacun), la jauge se remplit en ≈ 15 à 20 min ; un joueur seul la remplit en ≈ 35 min.
- **Pleine** : Big Plop danse sur la place (8 s, grand spectacle, file du §2.4), puis **WOBBLE PARTY** : ×2 pièces et croissance pour tout le serveur pendant **5 min**. La jauge est figée pendant la fête, puis repart de 0.
- Grande jarre de gelée sur la place + petite barre dans le HUD.

**Jelly Moon (samedi, et rattrapage le dimanche)**

| Élément | Règle |
|---|---|
| Horaire | Samedi 16:00, 18:00, 20:00, 22:00 UTC (20 min chacune) ; dimanche 16:00 UTC (20 min). Le MEGA de :20 qui suit chaque séance devient MEGA MOON SQUISH |
| Ambiance | Ciel violet et sarcelle, grosse lune, musique douce un peu étrange. Les squishies Lunaires ont un petit troisième œil et 2 gouttes de gelée brillantes qui flottent autour d'eux. Mignon et bizarre, **jamais effrayant** |
| Mutations | Chances × 2 et Lunaire 3 % (§4.5) |
| BOOP RUSH | Les Rush de :05 et :15 rendent **Mythiques et Secrets boopables** |
| Espèce de la Lune | Moonplop (Secret) peut naître ; ensuite, chaque semaine, une nouvelle espèce arrive en données et fait ses débuts pendant la Lune (§7.6) |
| Autel de la Lune | Sur la place. Un joueur présent au moins 5 min pendant une séance reçoit **1 Goutte de Lune** à la fin de la séance : une naissance de Qualité (la sienne + 1) avec mutation **Lunaire garantie**. Une par séance au plus |

### 4.24 Rythme de progression et simulation (porte de qualité)

Joueur de référence : 35 min de jeu actif le premier jour, puis 30 min par jour ; une pression toutes les 2 s sur le squishy prêt le plus rentable, PERFECT 40 % du temps (fenêtre du §4.7) ; Pot encaissé toutes les 40 s ; achats au moins cher utile d'abord (Tapis, Enclos si plein, décorations, Lit douillet) ; fusion dès qu'une paire de jumeaux existe ; il garde toujours son plus gros squishy dans un enclos et range les plus faibles dans la Boîte à dodo pour laisser naître la Cuve ; 85 % des créatures en fuite attrapées ; hors ligne 16 h par nuit ; boosts ×2 20 % du temps ; événements moyens (60 % des Rush avec un bébé, 50 % des Wild Wobblers partagés, 85 % des Wild Wobblers personnels, 2 bébés par MEGA, 30 % des Golden, 1 cadeau de Grand Splorch toutes les 20 min) ; aucun achat Robux.

| Jalon | Cible (médiane) | Tolérance |
|---|---|---|
| Première pression | 10 s | ≤ 15 s |
| Premier achat (Tapis) | ≈ 20 s | ≤ 30 s |
| À 5:00 : squishies | 4 | 3-4 |
| À 5:00 : fusions | 1-2 | ≥ 1 |
| À 5:00 : captures | 1-2 | ≥ 1 |
| Première balade (taille 1 200) | 4:30 | ≤ 5:00 |
| À 5:00 : la dalle Enclos (1 200) est payable | 100 % des joueurs | ≥ 90 % |
| À 5:00 : pièces en poche (repère, pas une porte) | ≈ 10K | 6K-16K (valeur en dents de scie : elle dépend du dernier achat) |
| Premier Grand Splorch | 14 min | **12-16 min** (médiane) ; 10-18 min pour 80 % des joueurs |
| À 30 min : R | 2 | 1-3 |
| À 30 min : tampons de Squishydex | 18 | 14-24 |
| Fin du jour 1 (35 min) : R | 2 | 2-3 |
| Fin du jour 1 : 3 objectifs du jour sur 3 en 30 min | ≥ 90 % des joueurs | ≥ 90 % (jalon nouveau, à mesurer par `EconomyPacing`) |
| Fin du jour 7 : R | 10 | 8-11 |
| Fin du jour 7 : plus gros squishy (avant Grand Splorch) | ≈ 1,7e8 | 5e7-3e8 |
| Fin du jour 7 : tampons de Squishydex (espèces + mutations) | 95 | 80-110 |
| Fin du jour 7 : au moins un Épique ou mieux | 100 % des joueurs | ≥ 95 % |
| Fin du jour 28 : R | 20 | 17-22 |
| Premier squishy de 1e12 (1 000 milliards) | vers le jour 24 (joueur à 30 min/jour) ; vers le jour 13 pour un joueur à 2 h/jour | — (longue traîne) |

**Simulation (porte bloquante).** Un test Lune (`tests/specs/EconomyPacing.spec.luau`) simule 200 joueurs de référence sur 28 jours avec les tables de `Shared/Config/Balance` et `Shared/Config/Squishies`, le même code de formules que le jeu (`Shared/Logic/Formulas`, `Odds`, `FusionRules`, `QuestRules`), et une graine fixe. Le test échoue si la médiane d'un jalon sort de sa tolérance.

**Résultats de la révision 1.1.** Une simulation Lune hors moteur, écrite avec les valeurs exactes de ce document (80 joueurs de référence, 28 jours), donne : premier achat à 18 s, 4 squishies, 1 fusion et 2 captures à 5:00, première balade à 4:27, pièces à 5:00 médiane 10,1K (10 %-90 % : 6,7K-15,7K), premier Grand Splorch à 14,1 min (11,7-16,9), R = 2 à 30 min et en fin de jour 1, R = 10 au jour 7, R = 15 au jour 14, R = 20 au jour 28, 95 tampons au jour 7 et 132 au jour 28, premier 1e12 au jour 24. Avec Fame, trophées, bonus de famille et objectifs : mêmes R, premier Grand Splorch à 14,4 min, premier 1e12 au jour 22. Un gros acheteur (×2 Pièces, Grand Ranch, un gros paquet par jour, Squish Party la moitié du temps) a environ un R d'avance : 12,5 min, R = 11 au jour 7, R = 21 au jour 28 (c'est le « plus tôt, pas plus haut » du §8.1, n° 10).

Deux remarques honnêtes. (1) Le prototype cité dans la version 1.0 n'utilisait pas exactement ces valeurs (prix des dalles non multipliés par 2^R, objectifs ×3) : ses chiffres (balade à 3:52, R = 17 au jour 28, 1e12 au jour 35) étaient trop optimistes sur la balade et trop prudents sur R. (2) Environ 9 Grands Splorch sur 20 deviennent possibles pendant l'absence du joueur (croissance hors ligne) : il les trouve prêts à la connexion, ce que dit l'écran de retour. C'est un bon moment de retour, mais les boucles 3 à 10 se jouent alors en partie hors ligne ; à surveiller avec `SplorchReached` (levier : `Balance.Offline.*`).

Leviers sans code : `Balance.Splorch.Targets`, `Balance.Tiles.*.Base/Growth`, `Balance.Vat.Interval` et `Balance.Vat.ByR` (qualité, vitesse et buses par R), `Balance.Income.Coef` (0,02), `Balance.Press.Seconds` (12), `Balance.Offline.*`.

### 4.25 Boosts, plafonds et limites anti-abus

**Boosts ×2** : boost de serveur (Wobble Party gratuite, Squish Party payée, Squish Party d'administrateur) et boost personnel (objectifs, Nourrir Plop). Ils ne se cumulent jamais : `B` vaut 2 au plus. Une Squish Party payée n'est jamais « mangée » par un boost gratuit : la fête payée passe d'abord, la Wobble Party attend son tour. Un boost personnel est **mis en pause** pendant un boost de serveur (son minuteur s'arrête), pour que le joueur ne perde rien.

| Plafond ou limite | Valeur |
|---|---|
| Bébés de BOOP RUSH | 10 par jour et par joueur |
| Wild Wobblers | 2 partagés + 1 personnel par joueur et par Rush |
| Golden Wobbler | Le gagnant ne peut pas regagner pendant 20 min |
| Bébés de Grand Splorch reçus | 10 par jour |
| Bébés du MEGA | 3 par MEGA (paliers) |
| Taille de **tout** bébé ou cadeau | Au plus **2 × le plus gros squishy** du joueur qui le reçoit |
| Fame du Rush (boopé, Wild Wobblers, Héros) | 30 par jour, en mode Rush comme en mode Cozy |
| Fame en relâchant | 20 par jour |
| Pressions de pet-sitting récompensées | 300 par jour |
| Applaudissements récompensés | 10 par jour |
| Pressions | 12 par seconde au plus (au-delà, ignorées) |
| Fuites du Rush | 2 par ranch et par Rush, 4 par ranch et par heure ; 10 en même temps sur le serveur ; une même paire boopeur → ranch au plus toutes les 30 min |
| Squish Party | Vendue seulement si elle peut commencer aussitôt (une seule en attente au plus) ; 3 achats par joueur et par jour |
| Comptes multiples qui se boopent | Bornés par les plafonds de bébés, la taille ≤ 2 × le plus gros, 1 boop par paire toutes les 30 min et 4 fuites par ranch et par heure |
| Vitesse, téléportation, bond sans recharge | Contrôle de déplacement avec budget d'action (§12.8) |
| Rafales de messages réseau | Seau à jetons par action (§12.7) |
| Échanges et dons de squishies | Aucun au lancement (les colis entre amis arrivent en janvier, §17) |

---

## 5. Contenu complet

### 5.1 Les 26 espèces

L'identifiant numérique est **définitif** (il est sauvegardé) : on ne réordonne jamais la table, on ajoute à la fin. Chaque espèce est **une ligne de données** de `Shared/Config/Squishies` : proportions du corps (X / Y / Z), haut de tête (oreilles, collerette…), yeux, couleurs (principale / secondaire, RGB), motif, tremblement (fréquence, amplitude d'écrasement). Une nouvelle espèce par semaine = une nouvelle ligne, sans nouveau code (§7.6).

| Id | Clé | Nom | Famille | Rareté | Corps X / Y / Z | Haut de tête | Yeux | Couleurs | Motif | Tremblement | Aspect en une ligne |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `plop` | Plop | Jelly | Commun | 1,0 / 1,0 / 1,0 | Antenne en goutte | Grands brillants | (140, 220, 255) / (255, 255, 255) | Ventre clair | 1,0 Hz / 8 % | Boule de gelée bleu menthe, une goutte sur la tête, joues roses : la mascotte |
| 2 | `wibble` | Wibble | Jelly | Peu commun | 0,9 / 1,2 / 0,9 | Calotte de caramel | Endormis | (255, 214, 140) / (170, 100, 50) | Calotte | 1,4 Hz / 12 % | Pudding au caramel qui tremblote et a toujours l'air de faire la sieste |
| 3 | `jiggleberry` | Jiggleberry | Jelly | Rare | 1,0 / 1,05 / 1,0 | Feuille | Points | (240, 80, 120) / (120, 200, 90) | 8 pépins clairs | 1,2 Hz / 10 % | Framboise de gelée toute bosselée, coiffée d'une feuille |
| 4 | `grand_gloop` | Grand Gloop | Jelly | Légendaire | 1,3 / 0,9 / 1,3 | Couronne minuscule | Étoiles | (120, 160, 255) / (255, 220, 120) | Dégradé en 3 couches | 0,7 Hz / 6 % | Grande gelée royale en trois couches brillantes |
| 5 | `mochi_mew` | Mochi Mew | Kitty | Commun | 1,05 / 0,95 / 1,0 | Oreilles de chat | Points | (250, 245, 240) / (255, 180, 200) | Intérieur d'oreilles rose | 1,1 Hz / 8 % | Chat-mochi tout blanc, oreilles roses, petites moustaches |
| 6 | `purrpudding` | Purrpudding | Kitty | Peu commun | 1,0 / 1,0 / 1,0 | Oreilles de chat | Fermés, heureux | (255, 170, 90) / (200, 110, 50) | Rayures tigrées | 1,2 Hz / 10 % | Pudding tigré orange qui ronronne les yeux fermés |
| 7 | `whiskerwob` | Whiskerwob | Kitty | Épique | 0,95 / 1,1 / 0,95 | Oreilles + longues moustaches-antennes | Étoiles | (190, 150, 255) / (255, 240, 255) | Queue en spirale | 1,0 Hz / 9 % | Chat lilas aux moustaches qui ondulent comme des antennes |
| 8 | `blossompurr` | Blossompurr | Kitty | Mythique | 1,0 / 1,0 / 1,0 | Oreilles + couronne de fleurs | Cœurs | (255, 170, 210) / (255, 255, 255) | Pétales qui tombent (3/s) | 0,9 Hz / 7 % | Chat rose cerisier couronné de fleurs, qui sème des pétales |
| 9 | `ribbit_drop` | Ribbit Drop | Froggy | Commun | 1,1 / 0,9 / 1,0 | Yeux globuleux sur le dessus | Globuleux | (120, 210, 110) / (230, 250, 180) | Ventre clair | 1,3 Hz / 10 % | Goutte-grenouille verte au grand sourire |
| 10 | `lilypuff` | Lilypuff | Froggy | Peu commun | 1,1 / 0,85 / 1,1 | Yeux globuleux + chapeau nénuphar | Globuleux | (90, 200, 190) / (140, 230, 120) | Taches de mare | 1,1 Hz / 9 % | Grenouille sarcelle coiffée d'une feuille de nénuphar |
| 11 | `croakaroo` | Croakaroo | Froggy | Rare | 0,9 / 1,15 / 0,9 | Yeux globuleux | Globuleux, clin d'œil | (255, 220, 80) / (255, 140, 60) | Taches orange | 1,5 Hz / 12 % | Grenouille jaune à taches orange, toujours prête à sauter |
| 12 | `boingtoad` | Boingtoad | Froggy | Épique | 1,0 / 1,0 / 1,0 | Yeux globuleux + ressort sous le ventre | Étoiles | (160, 110, 230) / (255, 230, 120) | Taches en étoile | 2,0 Hz / 18 % | Crapaud violet monté sur ressort, qui rebondit plus que tout le monde |
| 13 | `frillo` | Frillo | Axolo | Commun | 1,1 / 0,9 / 1,15 | Collerette (3 branches de chaque côté) | Points | (255, 175, 200) / (255, 110, 150) | — | 1,0 Hz / 8 % | Axolotl rose aux petites branches qui ondulent |
| 14 | `gillygum` | Gillygum | Axolo | Peu commun | 1,1 / 0,9 / 1,15 | Collerette en bulles de chewing-gum | Brillants | (150, 170, 255) / (255, 140, 220) | Bulles | 1,1 Hz / 9 % | Axolotl bleu dont la collerette fait des bulles roses |
| 15 | `lotlolly` | Lotlolly | Axolo | Épique | 1,0 / 1,0 / 1,1 | Collerette | Clin d'œil | (255, 200, 120) / (120, 220, 255) | Spirale de sucette | 1,0 Hz / 9 % | Axolotl en spirale de sucette, qui fait un clin d'œil |
| 16 | `coralotl` | Coralotl | Axolo | Légendaire | 1,15 / 1,0 / 1,2 | Couronne de corail | Brillants | (255, 120, 100) / (255, 230, 200) | 5 petites bosses de récif | 0,8 Hz / 7 % | Axolotl couleur corail, couronné d'un récif lumineux |
| 17 | `bunbun` | Bunbun | Bunny | Commun | 1,0 / 1,0 / 1,0 | Longues oreilles tombantes | Points | (255, 240, 210) / (255, 190, 200) | Bout de nez rose | 1,2 Hz / 9 % | Lapin crème aux oreilles qui tombent |
| 18 | `hopscotch` | Hopscotch | Bunny | Peu commun | 0,95 / 1,05 / 0,95 | Une oreille droite, une tombante | Endormis | (180, 195, 220) / (255, 255, 255) | Chaussettes blanches | 1,4 Hz / 11 % | Lapin gris-bleu, une oreille levée, une oreille baissée |
| 19 | `clover_hop` | Clover Hop | Bunny | Rare | 1,0 / 1,0 / 1,0 | Longues oreilles + trèfle | Brillants | (160, 230, 170) / (90, 170, 90) | Trèfle sur le ventre | 1,3 Hz / 10 % | Lapin menthe porte-bonheur, un trèfle sur la tête |
| 20 | `moonhop` | Moonhop | Bunny | Épique | 1,0 / 1,05 / 1,0 | Oreilles à bouts en croissant | Étoiles | (60, 70, 140) / (255, 240, 160) | Taches d'étoiles | 1,0 Hz / 9 % | Lapin bleu nuit constellé, aux oreilles en croissant de lune |
| 21 | `nubbin` | Nubbin | Spiky | Commun | 1,05 / 0,95 / 1,05 | 3 bosses douces sur le dos | Points | (255, 200, 160) / (255, 150, 120) | — | 1,1 Hz / 8 % | Petit dragon pêche avec trois bosses toutes molles |
| 22 | `prickle_puff` | Prickle Puff | Spiky | Peu commun | 1,0 / 1,0 / 1,0 | 7 pics doux | Brillants | (200, 150, 110) / (255, 230, 200) | Ventre crème | 1,2 Hz / 10 % | Hérisson de gelée aux pics tout mous |
| 23 | `drago_drop` | Drago Drop | Spiky | Épique | 1,0 / 1,0 / 1,05 | Petites ailes + cornes douces | Étoiles | (130, 200, 255) / (255, 255, 255) | Écailles claires | 1,0 Hz / 9 % | Bébé dragon bleu ciel aux ailes trop petites pour voler |
| 24 | `emberwob` | Emberwob | Spiky | Légendaire | 1,1 / 1,05 / 1,1 | Crête en forme de flamme, toute douce (sans feu) | Brillants | (255, 130, 60) / (255, 220, 120) | Ventre doré | 0,9 Hz / 7 % | Dragon orange chaud à la crête de flamme en gelée |
| 25 | `royal_plop` | Royal Plop | (Secret) | Secret | 1,05 / 1,05 / 1,05 | Couronne + petite cape | Étincelles | (140, 220, 255) / (255, 210, 80) | Goutte dorée | 1,0 Hz / 8 % | Plop couronné à cape rouge, goutte dorée sur la tête |
| 26 | `moonplop` | Moonplop | (Secret) | Secret | 1,0 / 1,0 / 1,0 | Antenne en croissant | 3 yeux (un petit au milieu) | (210, 220, 255) / (150, 130, 255) | 2 gouttes brillantes qui flottent autour | 0,8 Hz / 7 % | Plop argenté de la Lune, avec un petit troisième œil tout mignon ; naît seulement pendant la Jelly Moon |

Répartition : Commun 6, Peu commun 6, Rare 3, Épique 5, Légendaire 3, Mythique 1, Secret 2. Chaque famille a 4 espèces : un Commun, un Peu commun, puis deux plus rares. Les Secrets n'ont pas de famille (page « Secrets » du Squishydex) et ne comptent pas dans les bonus de famille.

**Champs réservés pour plus tard** dans chaque ligne (valeur au lancement) : `release = 0` (horodatage UTC d'arrivée ; les lignes futures sont publiées en avance et s'activent seules), `duo = false` (espèce Duo, janvier), `recipe = nil` (combinaison World First, janvier), `limitedUntil = 0` et `encore = {}` (semaines « Encore », février).

**Rotation du MEGA SQUISH** : le géant prend l'espèce `((semaine + numéro du MEGA dans la semaine) mod 24) + 1`, Secrets exclus (semaine = `Clock.week()`).

**Noms** : tous inventés pour ce jeu. On évite tout ce qui rappelle Squishmallows (pas de « -mallow »), les personnages connus et les mèmes. Vérification de marque avant publication (§18).

### 5.2 Fabrication des squishies en formes simples (`Shared/Render/SquishyBuilder`)

Construits **côté client** à partir de la ligne de données et de 4 nombres (espèce, mutation, étoiles, taille). Toutes les pièces sont ancrées, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false` (au clic de souris, on désigne un squishy par projection à l'écran, jamais par un rayon : §10.4). Un squishy n'est jamais un objet physique : rien ne peut le pousser, le faire tomber ou le coincer. **12 pièces au plus** par squishy en détail complet.

| Pièce | Primitive | Dimensions (× diamètre D) | Matériau / couleur |
|---|---|---|---|
| Corps | Ball, mise à l'échelle X / Y / Z de la ligne | D | SmoothPlastic, couleur principale (ou mutation) |
| Ventre / motif | 1 à 4 petites Balls ou Cylinders plats | 0,1 à 0,5 D | Couleur secondaire |
| Yeux (2, ou 3 pour Moonplop) | Ball | 0,22 D, à (±0,2 ; +0,12 ; −0,44) D | Noir, Reflectance 0,3 ; reflet blanc 0,07 D |
| Joues (2) | Cylinder plat | Ø 0,18 D, épaisseur 0,03 D | Rose (255, 160, 190) |
| Bouche | 3 petites Balls en arc (sourire) | 0,04 D chacune | Brun foncé (90, 50, 50) |
| Haut de tête | 1 à 3 pièces selon le type (Ball, WedgePart, Cylinder) | 0,2 à 0,5 D | Couleur secondaire |

**Étoiles** : 1 à 5 petites étoiles `Neon` dorées en arc au-dessus de la tête (BillboardGui en dessous de 60 studs, rien au-delà).

**Niveaux de détail** (distance à la caméra) : < 60 studs = modèle complet animé à chaque image ; 60-140 studs = corps + yeux (3 pièces), animation à 15 Hz ; > 140 studs = corps seul, immobile ; ranchs à plus de 220 studs = seulement la silhouette du meilleur squishy et un compteur « ×N ». Graphismes légers et qualité réduite (§12.9) : distances × 0,6.

**Animation de repos** (client, aucun trafic réseau) : rebond de période 1,2 s (celle du PERFECT), hauteur 0,18 D ; à chaque contact avec le sol, écrasement `(1 + a, 1 − a, 1 + a)` pendant 0,1 s (a = amplitude de tremblement de la ligne), puis tremblement amorti à la fréquence de la ligne ; clignement toutes les 3 à 6 s (yeux à 0,1 en Y pendant 0,08 s) ; regarde le joueur le plus proche à 15 studs au plus. Seul le corps change de taille (une écriture de `Size`) ; les autres pièces suivent par `BulkMoveTo`. Au plus 80 squishies animés à pleine cadence sur un client (40 en qualité réduite, §12.9).

### 5.3 Big Plop, la mascotte

- Dans tous les textes du jeu, la mascotte s'appelle **Big Plop** ; « Plop » seul désigne l'espèce (et ton premier squishy).
- Big Plop est un grand Plop (diamètre 6 studs), bleu menthe, avec un petit nœud papillon jaune, sur sa scène au bord de la place. Il fait coucou, montre la jauge, danse quand elle est pleine.
- Pendant l'accueil, une copie de Big Plop, visible seulement par le nouveau joueur, vient dans son ranch : il pose le petit Plop, montre les dalles du doigt, fait la démonstration d'éternuement (§4.21.6).
- Il ne parle jamais avec des phrases : des gestes, des icônes et des petits sons (« plop ! »).

### 5.4 Cosmétiques

| Catégorie | Élément | Obtention |
|---|---|---|
| Selles (couleur) | Classique (couleur du ranch) | Gratuit |
| | Pêche / Fraise | Plop jour 3 / jour 21 |
| | Menthe / Lavande | Squishydex 25 / 130 |
| | Nuage, Rayures bonbon, Étoilée, Cookie, Bulle, Royale | Pack Selles et Traînées |
| Traînées (derrière la monture) | Bulles / Vermicelles | Squishydex 50 / Plop jour 50 |
| | Ruban arc-en-ciel, Paillettes, Gouttes de gelée, Étoiles, Flocons, Notes de musique | Pack Selles et Traînées |
| Tenues (sur un squishy choisi) | Bavoir de Plop | Plop jour 7 |
| | Pull douillet, Couronne de gelée, Écharpe d'hiver | Produits Robux (§8.3) |
| Titres (sous le nom) | Little Collector, Squishologist, Dex Master | Squishydex 10 / 75 / 200 |
| | Splorch Star, Splorch Legend, Splorch Hero, Jelly Titan | R = 5 / 10 / 15 / 20 |
| | Plop's Best Friend | Plop jour 30 |
| | Stamp Hunter, Combo Star, Top Catcher, Super Helper, Big Heart | Top 10 d'un classement de la semaine (pendant la semaine suivante) |
| Thème de ranch | Couleur du ranch / Moonlit / Candy Night | Gratuit / Squishydex 160 / Plop jour 75 |
| Drapeaux de ranch | Squishydex / « Jour 14 » | Squishydex 100 / Plop jour 14 |
| Emotes en plus (jouées par croix ← à la place de Bravo, au choix dans les Réglages) | Belly Flop / Couronne | Plop jour 10 / Squishydex 260 |

**Palette des 16 ranchs** (couleur du propriétaire) : 1 Corail (255, 130, 120) · 2 Pêche (255, 180, 130) · 3 Citron (250, 225, 100) · 4 Citron vert (170, 225, 100) · 5 Menthe (110, 225, 170) · 6 Sarcelle (70, 205, 205) · 7 Ciel (110, 180, 255) · 8 Pervenche (140, 150, 250) · 9 Lilas (185, 140, 250) · 10 Orchidée (225, 130, 225) · 11 Rose (255, 130, 180) · 12 Framboise (230, 90, 130) · 13 Caramel (215, 160, 100) · 14 Sable (225, 205, 160) · 15 Écume (150, 235, 215) · 16 Nuage (180, 195, 215). Ranch libre : gris (130, 130, 140), sans lumière.

### 5.5 Récapitulatif du contenu au lancement

| Type | Au lancement |
|---|---|
| Espèces | 24 (6 familles × 4) + 2 Secrets = 26 |
| Raretés | 7 |
| Mutations | 9 (dont Lunaire, seulement le samedi, et Flop, la plus rare) |
| Squishydex | 26 pages d'espèces + 234 entrées de mutation + 130 badges d'étoiles ; 6 bonus de famille ; 9 jalons |
| Dalles | Tapis à Goûter (12 niveaux), 18 décorations, Enclos (14), Lit douillet. La Cuve (qualité 8, vitesse 10, buses 5) progresse avec R, jamais avec des pièces |
| Événements récurrents | Créature en fuite personnelle, Golden Wobbler, BOOP RUSH + Wild Wobblers (partagés et personnels), MEGA SQUISH, jauge du serveur et Wobble Party, Jelly Moon |
| Rétention | Nourrir Plop (12 paliers), 3 objectifs du jour (pool de 18), 5 classements de la semaine, carte « Plop a sommeil » |
| Cosmétiques | 11 selles, 8 traînées, 4 tenues, 12 titres + 5 titres de la semaine, 3 thèmes, 2 drapeaux, 2 emotes en plus |
| Monde | Wobbleton (place, rues, collines), 16 ranchs, costume d'hiver « Frost & Sprinkles » |

---

## 6. Social et multijoueur (16 joueurs)

Tout fonctionne **sans chat** : le chat exige une vérification d'âge (Étude §6.3). Le jeu ne lit jamais le texte du chat. Sur console, la fenêtre de chat est coupée (§10.6).

### 6.1 Attribution des ranchs et ranchs voisins

- 16 ranchs pour 16 places. À l'arrivée, `RanchService` donne un ranch libre. **Si un ami Roblox est déjà sur le serveur**, le joueur reçoit le ranch libre le plus proche du sien (vérifié avec `Player:IsFriendsWith`, sous `pcall`, résultat mis en cache pour la session). Les amis qui rejoignent ensemble sont donc voisins.
- **Le serveur place lui-même le personnage** dans son ranch à chaque apparition (`CharacterAdded`, puis `HumanoidRootPart` attendu 10 s au plus, puis `PivotTo` sur le point d'apparition du ranch, face au Pot). On ne compte pas sur les `SpawnLocation` pour choisir le ranch (elles ne savent pas qui est le propriétaire) : une seule `SpawnLocation` neutre, sur la place, sert de repli si le placement échoue (personnage sans `HumanoidRootPart` au bout de 10 s : nouvel essai à la prochaine apparition, message neutre). Après une chute ou une réinitialisation, même règle.
- Si la taille du serveur est réglée au-delà de 16 dans le Creator Hub, un joueur sans ranch voit un message amical puis est renvoyé après 30 s (« Wobbleton est pleine ! Rejoins un autre serveur. »), sauf si un ranch se libère (leçon de Comet Conga, analytics `ServerFullKick`).

### 6.2 Bonus d'amis

**+10 % de revenu par ami Roblox présent sur le serveur, +40 % au plus** (4 amis). Un petit cœur avec le nombre d'amis s'affiche à côté du compteur de pièces. Les ranchs d'amis sont reliés la nuit par un ruban lumineux (repère visuel, image de vignette).

### 6.3 On n'entre jamais chez les autres

- Chaque ranch a une clôture et un **portail de gelée** : le propriétaire le traverse, les autres rebondissent dessus.
- **La règle est vérifiée par le serveur, pas par la physique.** À chaque tick (10 Hz), un joueur dont la position validée est dans le ranch d'un autre (rectangle du ranch, module pur `WorldLayout`) est repoussé doucement à 6 studs devant le portail (`PivotTo`), avec un petit rebond et le message « C'est le ranch de Mira ! » (ou « C'est le ranch 7 ! » si le nom est caché). Aucune exception, même pour les amis.
- **La physique n'est qu'un confort** : la clôture est doublée d'un mur invisible ancré de 12 studs de haut (personne ne l'enjambe, même en monture ou en bondissant) ; la membrane du portail est non solide pour le serveur, et chaque client la rend solide **pour lui seul** sur les ranchs des autres (réglage local de `CanCollide`, qui ne touche que son propre personnage). Si ce confort rate (latence, personnage en réapparition), la poussée du serveur rattrape tout.
- Pendant le BOOP RUSH, on boope **par-dessus la clôture**, depuis la rue. La poursuite a lieu **dans la ville**.

### 6.4 Pet-sitting (presser chez un ami)

- Quand un **ami Roblox** se tient devant ta clôture (à 10 studs au plus), jusqu'à 3 de tes squishies prêts viennent à la clôture (hors Rush ; ils ne s'enfuient jamais).
- L'ami les presse depuis la rue (même geste que chez soi, PERFECT compris ; cible au choix avec L1 / R1 ou un clic, §10.4). **Le propriétaire** reçoit la récompense normale de la pression (sans PERFECT). **Le visiteur** reçoit 10 s de son propre revenu (×2 si PERFECT) et 1 point du classement « Plus serviable ». La recharge de 8 s du squishy s'applique.
- 300 pressions de pet-sitting récompensées par jour et par visiteur. Fonctionne même si le propriétaire est occupé ailleurs sur le serveur.

### 6.5 Emotes et signaux

| Signal | Croix directionnelle | Clavier | Icône | Emote jouée |
|---|---|---|---|---|
| Salut | ↑ | 1 | Main | `wave` |
| Merci (APPLAUDIR pendant les 8 s d'un Grand Splorch, §6.7) | → | 2 | Cœur | `wave` |
| Bravo | ← | 3 | Étoile | `cheer` (ou l'emote en plus choisie dans les Réglages : Belly Flop, Couronne, §5.4) |

- **Croix ↓ ouvre le Menu** (comme △, §10.4) : toute l'interface est ainsi atteignable avec la croix, ✕ et ○ seulement. Le signal « À l'aide » de la version 1.1 est retiré pour libérer ↓.
- Aucune roue à l'écran : un appui = un signal. La première fois, une petite aide montre les 3 glyphes de la croix pendant 4 s.
- Affichage : bulle-icône de 3 × 3 studs au-dessus de la tête pendant 2,5 s, visible jusqu'à 150 studs.
- Limite : 1 signal toutes les 1,5 s (le serveur accepte 1 toutes les 1,2 s pour absorber la gigue du réseau, leçon de Comet Conga).
- L'emote est jouée par le client sur son propre personnage (`Humanoid:PlayEmote`, sous `pcall`).

### 6.6 Voir ce que font les autres

- **Silhouette** : le meilleur squishy de chaque ranch flotte au-dessus du ranch (Y = 40), à sa vraie échelle jusqu'à 19×, avec sa taille. On voit de loin qui a le plus gros.
- **Statue de la place** : le plus gros squishy du serveur, en direct, sur un socle avec le nom du propriétaire (ou « Ranch 7 ») et sa taille.
- **Fanfare des records du serveur** : le premier joueur du serveur à dépasser 1 million, 1 milliard, 1e12 et 1e15 a droit à une fanfare et une bannière (une fois par seuil et par serveur).
- **Bannières de serveur** : file de 3 au plus, 3 s chacune, priorité décroissante : Grand Splorch > naissance Secret ou Mythique, ou mutation Flop, Glitch ou Arc-en-ciel > combo ≥ 5 > naissance Légendaire > fanfare de record > Golden Wobbler attrapé > Squish Party. Un même joueur déclenche au plus une bannière toutes les 10 s. **Une seule bannière à l'écran à la fois**, dans l'emplacement de message du HUD (§10.2). Un nouveau, avant l'étape 9 de l'accueil, ne voit pas celles des autres (§3). Exemples : « Mira : GRAND SPLORCH ! », « Noah a fait naître un SECRET Royal Plop (1 sur 2 500) ! », « Léa : FLOP PLOP ! 1 sur 270 000 », « Sam : COMBO x5 ! ».

### 6.7 Grand Splorch des autres : cadeaux et applaudissements

- Chaque Grand Splorch fait pleuvoir sur **tous** les autres joueurs : 60 s de leur revenu et un bébé (§4.15).
- Pendant 8 s, chaque autre joueur voit une grande puce **APPLAUDIR** avec le glyphe croix → (F au clavier, ou clic sur la puce ; elle prend la place de la puce GRAND SPLORCH, §10.2). Appuyer joue l'emote `cheer` et lance un arc de confettis vers le héros. L'applaudisseur gagne 10 s de son revenu (10 applaudissements récompensés par jour) ; le héros voit « 12 joueurs t'applaudissent ! ».

### 6.8 Moments coopératifs

- **MEGA SQUISH** (§4.22) : tout le serveur presse le géant ; chaque participant reçoit au moins un bébé en cas de réussite.
- **Jauge du serveur** (§4.23) : chaque action de chacun compte ; pleine, tout le monde gagne ×2 pendant 5 min.
- **Golden Wobbler** (§4.11) : course amicale ; tous ceux qui sont près gagnent quelque chose.
- **Squish Party** (§8.3) : un achat qui profite à tout le serveur.

### 6.9 Classements de la semaine

**Règle honnête.** Aucun achat ne donne directement de points de classement. Mais ×2 Pièces, les paquets de pièces et la Squish Party accélèrent le ranch, donc indirectement tout ce qui suit la progression (taille, nombre de Grands Splorch, familles débloquées). C'est pourquoi **la taille n'est pas un classement mondial** : sur une semaine, « y arriver plus tôt » voudrait dire « plus haut ». Le plus gros squishy reste sur la statue de la place, au niveau du serveur, sans titre (§6.6).

| Classement | Mesure | Égalité | Lien avec l'argent |
|---|---|---|---|
| **Plus de tampons** (Stamp Hunter) | Nouveaux tampons et badges d'étoiles du Squishydex gagnés cette semaine | Premier arrivé | Faible et indirect (familles débloquées plus tôt). Un nouveau joueur peut gagner sa première semaine |
| **Meilleur combo** (Combo Star) | Plus long combo de fusion (×5 au plus, ×6 avec la famille Axolo) | **Premier arrivé**, jamais la taille | Aucun |
| **Meilleure capture** (Top Catcher) | Plus forte valeur de capture = rareté × mutation de la créature attrapée (fuite, Golden, Rush, Wild Wobbler) | Premier arrivé | Faible et indirect (la qualité de la Cuve suit R) |
| **Plus serviable** (Super Helper) | Pressions de pet-sitting récompensées (300 par jour au plus) | Premier arrivé | Aucun |
| **Plus généreux** (Big Heart) | Bébés donnés : bébés reçus par d'autres grâce à tes squishies en fuite et à tes Grands Splorch | Premier arrivé | Faible et indirect (un ranch plus rapide fait plus de Grands Splorch) |

**Pourquoi pas « Meilleure série PERFECT »** : un PERFECT se vérifie avec l'heure envoyée par le client (§4.7). Un script peut donc réussir 100 % de PERFECT. Dans le ranch, le gain reste borné (×2) ; dans un classement mondial, le haut du tableau serait rempli de tricheurs.

- **Onglet Classements** : d'abord « **Ma place sur ce serveur** » et « **Mon record contre la semaine dernière** » (flèche verte s'il est battu), puis le top 10 mondial. Un enfant voit un but à sa portée avant de voir les champions.
- Stockage : un `OrderedDataStore` par classement et par semaine (`Weekly_<clé>_<semaine>`). Écriture quand un joueur bat son record de la semaine (file par serveur, vidée toutes les 60 s) ; lecture du top 10 toutes les 120 s. Tableau du serveur en direct. Le record de la semaine passée est gardé dans le profil (`weekly.prev`).
- Remise à zéro le lundi 00:00 UTC. Le top 10 de chaque classement porte le titre de la semaine pendant la semaine suivante.
- Les joueurs exclus par l'anti-triche (§12.8) ne sont pas écrits.
- **Cacher mon nom** (Réglages, désactivé par défaut) : le joueur apparaît comme « Squishy Fan #4821 » (nombre tiré du hash de son identifiant) dans les bannières, les classements, sur la statue et sur le panneau de son ranch.

### 6.10 Serveurs privés

Gratuits. **BOOP RUSH en mode Cozy pour tous par défaut** ; le propriétaire du serveur privé peut l'autoriser (§4.21.1). Tout le reste est identique.

### 6.11 Moments viraux prévus

| Moment | Pourquoi il se filme (clip ≤ 30 s) |
|---|---|
| La sirène du BOOP RUSH | Ciel rose, gloussements, des squishies éternuent par-dessus 16 clôtures, tout le serveur court en ville. À la capture, une bulle-bébé naît et l'original rentre chez lui avec des cœurs. Du chaos sans enfant qui pleure |
| Le Grand Splorch | Un géant éclate au ralenti au-dessus de la place, pluie de cadeaux, 15 joueurs applaudissent, puis le petit squishy revient faire coucou à son propriétaire |
| Le combo géant | « COMBO x5 ! », un squishy qui remplit l'enclos |
| L'éclosion rare | Bannière serveur, ralenti, « SECRET Royal Plop · 1 sur 2 500 » |
| Le Flop Plop | Il a l'air raté et fait « blorp »… puis les étoiles dorées, le badge ×100 et « LE PLUS RARE · 1 sur 270 000 » : le mème |
| Un Mythique boopé pendant la Jelly Moon | Un géant lumineux traverse la ville, poursuivi par 15 joueurs, certains sur leur monture |
| Chevaucher son squishy géant (Selle géante : 4 fois la taille d'un nouveau-né, avec onde de choc à chaque atterrissage) | Rebondir par-dessus les autres, pendant que la silhouette de ce même squishy, à sa vraie taille (jusqu'à 19×), flotte au-dessus du ranch |
| MEGA SQUISH | Tout le serveur presse un géant jusqu'à ce qu'il ÉCLATE en pluie de bébés |
| « De 0 à 1 million de milliards » | Nombres géants à l'écran, statue de la place qui grandit en direct |

---

## 7. Rétention

### 7.1 Crochets par horizon (fidélité sur 28 jours, Étude §6.2)

| Horizon | Crochets |
|---|---|
| **J1** | Récompense à 10 s ; fusion à 1:00 ; capture à 2:00 ; monture vers 4:30 ; premier Grand Splorch vers 14 min ; choix Rush / Cozy à 15 min, au calme ; un événement de serveur au plus toutes les 10 min ; message « Tes squishies grandissent même quand tu dors » à 10 min de jeu et en bas du panneau Réglages |
| **J2-J7** | Écran de retour (croissance hors ligne visible) ; Nourrir Plop (jours au total) ; 3 objectifs du jour ; nouvelles familles à R = 1, 3, 5 ; Squishydex ; Meilleur Ami ; première Jelly Moon |
| **J8-J28** | Grands Splorch 9 à 17 ; mutations rares (Galaxie, Arc-en-ciel, Glitch, Flop) ; étoiles ★5 ; Étagère à trophées ; Fame ; classements de la semaine ; une espèce nouvelle chaque semaine ; costumes de saison |

### 7.2 Écran de retour

S'ouvre au chargement si le joueur a été absent au moins 10 min. Contenu : « Pendant ton absence (5 h 12) : **Mochi Mew a grossi de +X** » (le vrai nom du Meilleur Ami n° 1, sinon du plus gros), le squishy qui gonfle à l'écran (0,8 s, `Quint Out`), « +Y pièces dans ton Pot », et « Grand Splorch prêt ! » si l'objectif est atteint. Un bouton « Super ! » (360 × 112 px TV, texte de 40 px TV, glyphe ✕), sélectionné d'office à la manette ; ✕ ou ○ le ferment. Aucune publicité, aucune offre.

### 7.3 Nourrir Plop (jours au total)

Une fois par jour UTC, maintenir 5 s devant le bol. Les jours sans palier : boost personnel ×2 (croissance et pièces) pendant 5 min. Les paliers comptent le total de jours, jamais une série.

| Jours au total | Récompense (en plus d'un boost personnel ×2 de 15 min) |
|---|---|
| 1 | Autocollant « Jour 1 » au-dessus du ranch |
| 2 | Pièces = 10 min de revenu |
| 3 | Selle Pêche |
| 5 | Traînée Bulles roses |
| 7 | Tenue « Bavoir de Plop » |
| 10 | Emote Belly Flop |
| 14 | Drapeau « Jour 14 » |
| 21 | Selle Fraise |
| 30 | Titre « Plop's Best Friend » |
| 50 | Traînée Vermicelles |
| 75 | Thème de ranch « Candy Night » |
| 100 | Bol doré et couronne pour ton Meilleur Ami |

### 7.4 Objectifs du jour

Chaque jour UTC : 3 objectifs (facile, moyen, difficile), tirés à la première connexion du jour de manière déterministe (`Hash(jour, UserId)`), parmi ceux dont la règle « Proposé si » est vraie à ce moment. **Règle d'or : un objectif n'est proposé que s'il est faisable en 20 min de jeu au plus dans la situation du joueur** (module pur `QuestRules`). 1 relance gratuite par jour. **Jour 1** (accueil) : fixes, « Presse 30 squishies », « Attrape 2 créatures », « Fais 1 fusion ».

**Remise à zéro de 00:00 UTC en pleine session** (16 h à Los Angeles, 19 h à New York) : les objectifs terminés sont **réclamés tout seuls** ; ceux en cours restent jusqu'à la fin de la session. Les nouveaux arrivent à la connexion suivante, avec une carte « Nouveaux objectifs ! ». Rien de commencé n'est perdu.

Récompenses : facile = 3 min de revenu ; moyen = 6 min de revenu + boost personnel ×2 de 5 min ; difficile = 10 min de revenu + boost personnel ×2 de 10 min. **Les 3 terminés** : une « Goutte chanceuse » (une naissance de Qualité + 1, chances de mutation × 2).

| # | Niveau | Objectif | But | Proposé si |
|---|---|---|---|---|
| 1 | Facile | Presse des squishies | 30 pressions | Toujours |
| 2 | Facile | PERFECT ! | 10 PERFECT | Toujours |
| 3 | Facile | Attrape des créatures en fuite | 2 | Toujours (une toutes les 60 s) |
| 4 | Facile | Construis | 3 dalles achetées | Il reste au moins 3 achats de dalle possibles dans la boucle |
| 5 | Facile | Vide ton Pot | 5 encaissements | Toujours (avec le Pot automatique, chaque encaissement automatique compte) |
| 6 | Facile | Salut ! | 3 emotes | Toujours |
| 7 | Moyen | Fusionne | 2 fusions | Toujours |
| 8 | Moyen | Fais naître | 5 naissances dans la Cuve | Toujours (intervalle de 90 s au plus) |
| 9 | Moyen | Série PERFECT | 5 PERFECT de suite | Toujours |
| 10 | Moyen | MEGA SQUISH | Participer (≥ 10 points) | Un MEGA commence dans les 20 min |
| 11 | Moyen | Course dorée | Attraper un Golden Wobbler ou être à 30 studs de sa capture | Toujours (un Golden toutes les 20 min au plus) |
| 12 | Moyen | Pet-sitting (Ami) | 10 pressions chez un ami | Un ami Roblox est sur le serveur ; s'il part, la relance de cet objectif devient gratuite |
| 13 | Moyen | Wobbler Time | Attraper 1 créature pendant un BOOP RUSH (Wild Wobbler compris) ou réussir 1 boop | Toujours, Rush ou Cozy (le Wild Wobbler personnel suffit) |
| 14 | Difficile | Combo ! | 1 combo ×2 | R ≥ 1 |
| 15 | Difficile | Grande éclosion | 1 Rare ou mieux (naissance, capture ou bébé) | R ≥ 3 (qualité de la Cuve ≥ 4) |
| 16 | Difficile | Grand Splorch | 1 Grand Splorch | Temps prévu jusqu'à l'objectif ≤ 20 min (taille qui manque ÷ croissance actuelle) |
| 17 | Difficile | Wild Wobblers | 1 Wild Wobbler attrapé | Toujours (le personnel suffit) |
| 18 | Difficile | Collectionneur | 3 nouveaux tampons ou badges d'étoiles | Le joueur a moins de 120 tampons d'espèces et de mutations |

Aucun objectif n'est réservé au mode Rush : le mode Cozy a les mêmes chances de finir ses 3 objectifs. La simulation vérifie qu'au moins 90 % des joueurs de référence finissent 3 objectifs sur 3 en une session de 30 min (§4.24).

### 7.5 Rendez-vous de la semaine

- **Jelly Moon** chaque samedi (4 séances) et le dimanche (§4.23). Déclarée comme *Experience Event* dans le Creator Hub.
- **Une nouvelle espèce par semaine** (§7.6), qui fait ses débuts pendant la Jelly Moon.
- **Classements de la semaine** (§6.9).
- **Squish Parties d'administrateur** annoncées à l'avance sur les réseaux : un sujet `MessagingService` « LiveOps » permet à une liste blanche d'administrateurs (UserIds dans la configuration serveur) de lancer sur tous les serveurs : 5 Golden Wobblers en 5 min + ×2 gratuit pour tous pendant 10 min. C'est notre version des sessions « admin abuse » (Étude §5.1), sans aucune vente.

### 7.6 Cadence des mises à jour

Rythme tenable (le créateur de Grow a Garden s'est épuisé en hebdomadaire, Étude §4.3) :
- **chaque semaine** : une nouvelle espèce, ajoutée comme ligne de données avec son horodatage `release`. Les lignes sont publiées **en avance** (dans une version du jeudi) et s'activent toutes seules le samedi à 16:00 UTC. Aucun serveur n'a besoin d'être redémarré le samedi ;
- **toutes les 2 semaines** : un ajout de configuration (tenues, décorations, objectifs) ;
- **chaque saison** : un costume (préréglages d'éclairage, décorations, tenue), selon le calendrier de costumes. Au lancement : hiver « Frost & Sprinkles » (neige de sucre glace, guirlandes de bonbons, Écharpe d'hiver).

---

## 8. Monétisation

### 8.1 Principes non négociables

1. **Aucun hasard payant, aucune chance achetable** : ni œuf, ni coffre, ni roue, ni chance payante, ni avantage payant pour attraper ou booper. **Les pièces, qu'on peut acheter en Robux, n'achètent jamais une probabilité ni un tirage** : la Cuve (qualité, vitesse, buses) progresse seulement avec R (§4.9). C'est la définition des « paid random items » de Roblox (`production/monetization/paid-random-items.md` : les « probability modifier items » achetés en Robux ou avec une monnaie achetable en Robux), appliquée à la lettre.
2. **Jamais payer pour sauter un minuteur** : ni la Cuve, ni la Gelée lente (janvier).
3. **Pas de faux compte à rebours**, pas de « plus que 2 en stock », pas de prix caché derrière une monnaie intermédiaire. Chaque bouton montre le prix en Robux et exactement ce qu'on reçoit.
4. **Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé** : la Boutique Robux est cachée, aucun écran ne propose d'acheter.
5. **Aucune publicité vidéo récompensée** au lancement (et aucun code pour en afficher).
6. **Boutique cachée tant que les identifiants sont à 0** : un article dont l'identifiant vaut `0` dans `Shared/Config/Monetization` est désactivé et invisible ; si tous valent 0, l'onglet Boutique Robux n'apparaît pas (leçon de Comet Conga).
7. **Prix lus à l'exécution** (`MarketplaceService:GetProductInfoAsync`) pour la tarification gérée par Roblox (Managed Pricing) ; le prix en configuration n'est qu'un affichage de repli.
8. **`ProcessReceipt` idempotent** (service repris de Comet Conga) : `PurchaseId` mémorisé (100 derniers), `PurchaseGranted` renvoyé seulement après une sauvegarde réussie.
9. **PolicyService** : au chargement, `PolicyService:GetPolicyInfoForPlayerAsync` (sous `pcall`, 3 essais). Si `ArePaidRandomItemsRestricted` est vrai, le joueur ne voit pas les **Paquets de pièces** : c'est un achat direct de monnaie, et les pièces font avancer vers R, qui améliore la Cuve gratuite ; on reste donc prudent. ×2 Pièces et la Squish Party restent visibles : ils n'achètent aucune chance. Si l'appel échoue, on applique la règle la plus stricte. Les probabilités des naissances gratuites sont **toujours** affichées.
10. Le pass ×2 Pièces ne touche **que les pièces**, jamais la taille ni les chances. Dit honnêtement : ×2 Pièces, les paquets et la Squish Party accélèrent le ranch, donc indirectement la taille et le rythme des Grands Splorch. C'est pourquoi la taille n'est pas un classement mondial, et les autres classements se départagent au premier arrivé (§6.9).
11. **Des pièces payées ne disparaissent jamais par surprise** : paquets cachés quand « Grand Splorch prêt ! » est affiché, perte annoncée en rouge dans l'aperçu, deuxième confirmation après un achat récent (§4.15, §8.3).

### 8.2 Passes (« Pour toujours », gardés après chaque Grand Splorch)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `AutoPot` | Pot automatique | 149 R$ | Le Pot s'encaisse tout seul toutes les 5 s, où qu'on soit. Confort seulement |
| `DoubleCoins` | ×2 Pièces | 249 R$ | ×2 sur toutes les pièces (revenu, pressions, combos, ventes, récompenses en pièces). Jamais la taille |
| `BigRanch` | Grand Ranch | 199 R$ | +6 places d'enclos (24 au plus) |
| `SaddlesTrails` | Pack Selles et Traînées | 99 R$ | 6 selles et 6 traînées. Purement décoratif : aucun avantage de vitesse ni de capture |

Chaque carte de pass porte l'étiquette « Pour toujours » / « Forever ».

### 8.3 Produits (achats ponctuels, résultat connu)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `SquishParty` | Squish Party | 99 R$ | ×2 pièces **et** croissance pour **tout le serveur** pendant 10 min. Ne se cumule pas. **Vendue seulement si elle peut commencer aussitôt** : le bouton est caché pendant une Squish Party (si deux achats se croisent, le second suit le premier). **3 achats au plus par joueur et par jour** (« 2 sur 3 aujourd'hui »). Si l'acheteur quitte le serveur avant la fin de sa fête, ou si le serveur ferme, la fête continue pour les autres et il garde un **boost personnel ×2 de 10 min** pour sa prochaine session. Bannière « **SQUISH PARTY ×2 !** », qui ne parle pas d'achat ; « offerte par Noah » seulement si l'acheteur l'a choisi (case « Montrer mon nom », décochée par défaut) |
| `CoinsSmall` | Petit paquet de pièces | 49 R$ | Pièces = **30 min** du revenu actuel (minimum 5 000) |
| `CoinsBig` | Gros paquet de pièces | 149 R$ | Pièces = **120 min** du revenu actuel (minimum 20 000) |
| `OutfitSweater` | Pull douillet | 49 R$ | Une tenue, à mettre sur le squishy de son choix |
| `OutfitCrown` | Couronne de gelée | 79 R$ | Idem |
| `OutfitWinter` | Écharpe d'hiver | 49 R$ | Idem (costume de saison du lancement) |

- **Paquets de pièces et Grand Splorch** : les pièces repartent de zéro à chaque Grand Splorch, et un paquet vaut le plus juste avant. Pour qu'aucun enfant ne perde un achat : (1) quand « Grand Splorch prêt ! » est affiché, les paquets sont cachés, avec le message « Fais d'abord ton Grand Splorch » ; (2) l'aperçu du Grand Splorch annonce la perte en rouge, avec un bouton « Dépenser d'abord » ; (3) après un achat de pièces de moins de 30 min dont il reste au moins la moitié, une deuxième confirmation avant le maintien (§4.15). Le retrait pur et simple des paquets au lancement est une question ouverte (Journal de révision).
- Le montant des paquets de pièces est **calculé par le serveur au moment de l'attribution** et affiché avant l'achat (« ≈ 1,2 M pièces »), calculé par le client à partir du revenu répliqué.
- **Tenues** : on voit le squishy porter la tenue (aperçu 3D qui tourne) **avant** d'acheter. Une tenue achetée appartient au compte : on la met sur un squishy, on la change gratuitement ; une tenue va sur un squishy à la fois. Si ce squishy est vendu ou relâché, la tenue revient dans la garde-robe. Une fusion garde la tenue.

### 8.4 Ce qui est volontairement exclu

Œufs, coffres, roues ; chance payante, y compris par une monnaie achetable (amélioration de la Cuve en pièces) ; avantage pour booper ou attraper ; immunité payante ; « passer le minuteur » ; plafond hors ligne payant (le pass « Offline Plus » du concept est supprimé : le Lit douillet s'achète en pièces) ; récompense d'invitation ; publicité vidéo récompensée ; nom de l'acheteur affiché par défaut.

**Plus tard (janvier)** : piste premium de la saison de 28 jours (≈ 399 R$), uniquement décorative, toutes les récompenses visibles avant l'achat (§17).

### 8.5 Attentes honnêtes

Taux DevEx standard 0,0038 $/R$ et 70 % net sur les ventes. Conversion visée 1,5 à 3 %. Revenus portés par ×2 Pièces, Grand Ranch et Squish Party, plus les Creator Rewards (sessions de 10 min et plus, nouveaux joueurs amenés sur Roblox). Le modèle juste rapporte moins par joueur que les concurrents prédateurs : c'est un choix assumé, car l'algorithme récompense la fidélité et les dépenses des joueurs baissent (bookings −12 % au 3e trimestre 2026, Étude §4.4).

---

## 9. Juice et animation

### 9.1 Module commun et règles

Tous les effets passent par le module client `UI/Juice` (repris de Comet Conga : `tween`, `pulse`, `press`, `popIn`, `popOut`, `shake`, `countTo`, `flash`, `cameraShake`, compatible Mouvement réduit), par `Controllers/VFXController` (repris et étendu : `floatText`, `stamp`, `flyCoins`, `ring`, `burst`, `pillar`, `fovPunch`, `haptic`) et par un nouveau module `Render/Squash` :

| Fonction | Rôle |
|---|---|
| `Squash.play(squishy, profil)` | Joue un profil d'écrasement et d'étirement sur le corps (une écriture de `Size` par image, les autres pièces suivent par `BulkMoveTo`) |
| `Squash.PROFILES` | `press`, `perfect`, `land`, `hatch`, `fuse`, `sneeze`, `hop`, `mount` (valeurs ci-dessous) |
| `VFXController.blobs(pos, couleur, n)` | Gouttes de gelée (réserve de 120 Balls réutilisées) |
| `VFXController.capsule(joueur, bébé)` | Capsule de bébé qui tombe du ciel près d'un joueur, éclate, puis le bébé saute vers son ranch |

**Règles**
- Une seule animation par propriété à la fois (la nouvelle annule l'ancienne). Aucune création d'instances en rafale : réserves de pièces, de BillboardGui et d'émetteurs.
- Les écrasements gardent à peu près le volume (X × Y × Z ≈ 1) : un squishy écrasé s'élargit.
- Secousse de caméra par `Humanoid.CameraOffset` (bruit de Perlin, amplitude ≤ 0,4, durée ≤ 0,3 s). Les pièces 3D disparaissent en **rétrécissant** (Transparency reste 0 ou 1, sauf la gelée Jelly, exception unique).
- Les textes « +N » utilisent `Format.abbreviate` (§4.2) dans la langue du joueur.
- Un son vide ou qui ne se charge pas est muet : le jeu reste jouable en silence (§9.6).

**Mouvement réduit** (réglage, et suit `GuiService.ReducedMotionEnabled`) : pas de secousse, pas de coup de focale, pas de flash, pas de ralenti (les séquences se jouent à vitesse normale), pas de travelling de caméra du Grand Splorch (une flèche montre la place), amplitudes d'écrasement × 0,5, Glitch en damier fixe, Arc-en-ciel en dégradé fixe, déplacements d'interface remplacés par des fondus. Aucun clignotement au-dessus de 3 Hz, réglage ou pas.

**Graphismes légers** (réglage) : particules × 0,3 ; pas de `Trail` sauf derrière les squishies en fuite ; `Highlight` seulement sur la cible et les squishies en fuite ; distances de détail × 0,6 ; 40 squishies animés au plus ; lumières coupées au-delà de 60 studs ; pas de `BlurEffect` ; ombres coupées sur les décors.

### 9.2 Interface

| Interaction | Tweens | Effets | Son |
|---|---|---|---|
| Appui sur un bouton | `UIScale` 1 → 0,92 en 0,06 s (`Quad Out`) ; au relâchement 0,92 → 1,05 → 1 en 0,18 s (`Back Out`) ; +10 % de luminosité pendant l'appui. Souris qui sort du bouton : retour à 1 | — | `Click` |
| Sélection manette (le « focus ») | Cadre blanc de 6 px TV bordé de sombre (2 px), respiration 0 ↔ 0,35 en 1,2 s ; l'objet sélectionné grossit à 1,05 ; pulsation `Juice.press`. Visible à 3 m sur tous les fonds | — | `Select` (au plus 1 toutes les 0,06 s) |
| Refus d'un bouton de menu (pas assez de pièces, enclos pleins). Une dalle trop chère au sol ne refuse pas (§4.6) | Secousse horizontale ±6 px × 3 en 0,25 s, contour rouge 0,25 s | Message « Il manque 1,2K pièces » | `Error` |
| Ouverture de panneau | `UIScale` 0,85 → 1 en 0,22 s (`Back Out`) + fondu 0,15 s ; `BlurEffect` 0 → 8 en 0,2 s (sauf Graphismes légers) | — | `Whoosh` |
| Fermeture / retour | `UIScale` 1 → 0,9 + fondu en 0,12 s (`Quad In`) | — | `Back` |
| Onglet / panneau suivant | Soulignement qui glisse en 0,15 s | — | `Tab` |
| Bout de liste | Rebond de la liste de 8 px en 0,15 s | Vibration `listEnd` | `Bump` |
| Compteur de pièces | Défilement `countTo` 0,5 s (`Quint Out`) + pop `UIScale` 1,15 → 1 en 0,2 s ; le revenu passif défile sans pop | — | `Coin` (8 par seconde au plus) |
| Bouton qui attire l'attention | Pulsation `UIScale` 1 → 1,08, sinus 0,8 s | Glyphe ou main dessinée pendant l'accueil | — |

### 9.3 Les squishies (client, aucun trafic réseau)

| État | Animation |
|---|---|
| Au repos | Rebond de période 1,2 s (hauteur 0,18 D), écrasement au contact (1 + a ; 1 − a ; 1 + a) pendant 0,1 s puis tremblement amorti à la fréquence de l'espèce ; clignement toutes les 3-6 s ; flâne dans l'enclos (pas de 2 studs toutes les 4-8 s) ; regarde le joueur le plus proche |
| Prêt à presser | Corps gonflé de 4 %, petit reflet qui passe toutes les 2 s ; anneau PERFECT qui se resserre vers lui à chaque cycle quand il est la cible |
| En recharge | Anneau qui se remplit au sol en 8 s ; corps normal |
| Porté | Sur la tête du joueur, bat des pieds (oscillation ±10° à 3 Hz) |
| Jumeau du squishy porté ou ciblé | Petit cœur rose qui pulse au-dessus de lui (échelle 1 ↔ 1,25 à 1,5 Hz), vu par le propriétaire seulement |
| Dans le Bassin | Flotte (Y ± 0,3 à 0,5 Hz), petites bulles 1 par seconde |
| Curieux à la clôture (Rush) | Pattes posées sur la clôture, se dandine (±8° à 1,5 Hz), nez qui remue |
| Meilleur Ami en ville | Suit le joueur à 4 studs derrière, par petits bonds |
| Monture | Rebondit à chaque pas (écrasement 8 % au rythme de la course) |
| Dans la Boîte à dodo | Icône endormie dans le panneau (pas de modèle dans le monde) |

### 9.4 Moments de jeu

« D » = diamètre du corps. Durées en secondes. « MR » = Mouvement réduit.

| Moment | Tweens et mouvement | Particules / 3D | Caméra / écran | Texte | Son | Vibration |
|---|---|---|---|---|---|---|
| **Presser** | Profil `press` : (1 ; 1 ; 1) → (1,35 ; 0,60 ; 1,35) en 0,06 (`Quad Out`) → (0,85 ; 1,25 ; 0,85) en 0,12 (`Quad Out`) → (1 ; 1 ; 1) en 0,35 (`Elastic Out`) | 8 gouttes couleur du corps ; 6 à 10 pièces (client) jaillissent en arc 0,5 puis volent vers le compteur en 0,4 (`Quad In`) | Pop du compteur | « +1,2K » : échelle 0 → 1,2 → 1 en 0,2 (`Back Out`), monte de 3 studs en 0,8 | `Press`, hauteur au hasard entre 0,92 et 1,08 (un son un peu différent à chaque fois) | `pressTick` (2 par seconde au plus) |
| **PERFECT** | Profil `perfect` : (1,45 ; 0,50 ; 1,45) puis comme `press` | Anneau `Neon` blanc 0 → 1,6 D en 0,25 ; 14 étincelles | — | Tampon « PERFECT ! » doré : 0 → 1,3 → 1 en 0,25 (`Back Out`) ; « ×3 » sous le tampon pour la série | `Perfect`, hauteur 1,0595^série (un demi-ton de plus par marche) | `perfect` |
| Série de 5 | — | 20 étincelles dorées en gerbe | Légère lueur dorée aux bords de l'écran 0,4 (pas en MR) | « PERFECT ×5 ! » | `StreakMax` | `perfect` |
| **Dalle achetée** | L'objet sort du sol : échelle Y 0 → 1,15 → 1 en 0,45 (`Back Out`), puis (1,08 ; 0,92) → 1 en 0,3 | 12 vermicelles colorés | — | « Tapis à Goûter Niv. 2 » flottant | `TileBuild` | — |
| **Pot encaissé** | Couvercle qui saute (0,15) | Geyser de 12 à 20 pièces, qui volent vers le compteur (décalage 0,03) | Compteur `countTo` 0,5 + pop 1,15 | « +4,5K » doré | `PotCollect` puis `Coin` | — |
| **Cuve qui se remplit** | Niveau de gelée qui monte en continu ; à 90 %, la Cuve tremble (échelle 1,03, sinus 3 Hz) | 2 bulles par seconde | — | — | `VatBubble` (petit blip à 90 %) | — |
| **Naissance Commun / Peu commun** | La goutte tombe (0,3), s'écrase (1,4 ; 0,6 ; 1,4), la coque se fend en 6 gouttes, le squishy sort : 0 → 1,1 → 1 en 0,35 (`Back Out`) | 10 particules couleur de rareté | — | « + Mochi Mew » (taille selon la rareté : ×0,8 Commun → ×1,6 Secret) ; « NOUVEAU ! » doré si nouvelle entrée | `Hatch` | — |
| Naissance Rare / Épique | Idem | + colonne `Neon` 0,8 (Ø 1,5 → 0, hauteur 25) ; 20 particules | Épique : focale 70 → 73 → 70 en 0,3 (pas en MR) | — | `HatchRare` | Épique : `catch` |
| Naissance Légendaire | Le pop se joue au **ralenti** (0,4× pendant 0,6 ; pas en MR) | Faisceau doré de 4 s visible par tout le serveur ; 40 confettis | Flash blanc 0,12 (opacité 30 %, pas en MR) ; secousse 0,25, amplitude 0,25 | Bannière serveur ; étiquette « 1 sur X » | `HatchLegend` | `hatchLegend` |
| Naissance Mythique / Secret | Idem, ralenti 0,8 | + anneau arc-en-ciel 0 → 30 studs en 1,0 ; 60 confettis multicolores | Idem + capture vidéo automatique (§9.5) | Grande étiquette « SECRET Royal Plop · 1 sur 2 500 » pendant 3 s | `HatchLegend` (hauteur 0,9 pour Secret) | `hatchLegend` |
| **Mutation révélée** | Après la sortie, un reflet blanc balaie le corps (0,4) et le matériau change | 10 particules couleur de mutation | — | « Doré ! », « Galaxie ! »… | `MutationReveal` | — |
| Mutation **Flop** (naissance rare, quelle que soit l'espèce) | Le pop se joue au ralenti (0,4× pendant 0,6 ; pas en MR). Au lieu du reflet : le squishy se dégonfle, Y 1 → 0,6 en 0,5 (`Quad Out`), yeux mi-clos, petite moue ; un petit nuage gris tourne 1 s au-dessus… puis **éclate en étoiles dorées** | 40 confettis dorés ; 3 étoiles dorées se mettent à tourner au-dessus de lui | Flash doré 0,12 (pas en MR) ; capture vidéo automatique (§9.5) | Bannière serveur ; grande étiquette « **FLOP ! LE PLUS RARE · 1 sur 270 000** » avec un badge doré « ×100 » pendant 3 s ; le cadenas se ferme | `Blorp` puis `HatchLegend` | `hatchLegend` |
| Mutation **Glitch** ou **Arc-en-ciel** | Comme une naissance Légendaire (ralenti, faisceau doré), quelle que soit l'espèce | 40 confettis | Capture vidéo automatique | Bannière serveur ; étiquette « GLITCH ! · 1 sur X »  ; le cadenas se ferme | `HatchLegend` | `hatchLegend` |
| **Prendre** (○ / Q) | Saute sur la tête du joueur : parabole 0,25 (sommet 3 studs), atterrissage (1,2 ; 0,8 ; 1,2) → 1 en 0,15 | — | — | — | `Pickup` | — |
| **Lancer** | Arc 0,5 (sommet 6 studs) vers le Bassin | Éclaboussure : 16 gouttes + anneau sur l'eau | — | — | `Throw` puis `Splash` | — |
| **Fusion** | Les jumeaux tournent l'un autour de l'autre 0,6 (2 tours, en accélérant), éclair blanc (sphère 0 → 1,3 D → 0 en 0,2), le résultat sort : 0,6 → 1,25 → 1 en 0,4 (`Elastic Out`) ; l'étoile vole du centre vers l'arc d'étoiles (0,3) | 24 particules aux couleurs de l'espèce | Focale 70 → 74 → 70 en 0,3 (pas en MR) | « ★2 ! » | `Fuse` | `fusion` |
| **Combo** (étape k) | Comme la fusion, 0,6 entre deux étapes | Particules + k × 4 | Lueur chaude aux bords, plus forte à chaque étape ; k ≥ 4 : secousse 0,2, amplitude 0,2 (pas en MR) | « COMBO x2 ! », « x3 ! »… taille 1 + 0,15 k ; k ≥ 4 : bannière | `ComboStep`, hauteur 1 + 0,08 k | `fusion`, force + 0,05 par étape |
| COMBO ×5 | — | 50 confettis dorés | Grand tampon « COMBO x5 ! » (0,5, `Elastic Out`) ; capture vidéo automatique | Bannière serveur | `ComboBig` | `comboBig` |
| **Créature en fuite apparaît** | La Fontaine crache une colonne de gelée (0,4), la créature sort en arc (0,6) et atterrit écrasée | Anneau à la couleur du joueur sous elle | Flèche au bord de l'écran si elle est hors champ | — | `RunawayAppear` | — |
| **Bond d'une créature** (fuite, Rush, Wild, Golden) | Profil `hop` : étirement (0,85 ; 1,25 ; 0,85) au départ, écrasement (1,3 ; 0,7 ; 1,3) à l'atterrissage pendant 0,08 | 3 bouffées de poussière par atterrissage (pas en Graphismes légers) | — | — | `Giggle` toutes les 2 à 3 s (son 3D, portée 60 studs) | — |
| **Booper** (maintien) | Anneau de progression autour du nez (2,5 ou 5 s) ; le nez remue ; le squishy inspire : Y 1 → 1,15 pendant le maintien | — | — | « Boop… » | `BoopHold` (petit souffle qui monte) | — |
| **ATCHOUM** | Profil `sneeze` : (1,5 ; 0,6 ; 1,5) en 0,08, puis saut par-dessus la clôture (arc 0,7, sommet 8 studs) | Nuage pastel brillant (20 particules blanches et roses, **jamais vertes**) | — | « ACHOO! » / « ATCHOUM ! » (`Elastic Out`) | `Sneeze` | Boopeur : `boopDone` ; propriétaire : `booped` |
| **Poursuite** | Bonds en continu (profil `hop`) | Anneau à la couleur du propriétaire + contour `Highlight` ; traînée de 6 gouttes ; anneau de temps au-dessus (25 s qui se vident) | Flèche au bord de l'écran vers la fuite la plus proche à 120 studs (joueurs Rush) | — | `MusicRush` (pendant le Rush) | — |
| **Bondir** | — | `Trail` sur la `HumanoidRootPart` pendant 0,35 ; 6 bouffées de poussière | Focale 70 → 76 en 0,1, retour en 0,4 (`Quad InOut`) (pas en MR) | L'indicateur R2 (bas droite, §10.2) montre un balayage de recharge (4 s), puis pop 1,15 quand il est prêt | `Leap` | — |
| **Attraper** (fuite, Wild, Golden) | La créature se roule en boule, saute dans les bras du joueur (parabole 0,3), puis disparaît en rétrécissant (0,2) et réapparaît dans l'enclos | 14 particules | — | « +1 Mochi Mew » ; « NOUVEAU ! » si nouvelle entrée | `Catch` (Golden : `CatchGolden`) | `catch` |
| Attraper le squishy d'un autre (Rush) | **L'attrapeur ne touche jamais l'original.** Pichenette pleine d'étincelles sur le squishy (0,15) ; il éternue une petite **bulle-bébé** brillante (Ø 1,5 stud, le bébé roulé en boule dedans) qui flotte jusqu'aux bras de l'attrapeur (parabole 0,4), éclate en paillettes, et le bébé saute vers son ranch. L'original fait coucou et rentre au ranch en rebondissant | 14 paillettes ; traînée de 6 cœurs par seconde derrière l'original | Propriétaire : flèche au bord de l'écran vers son squishy qui rentre | Attrapeur : « Bébé Wibble ! » ; propriétaire, le retour d'abord : « Wibble est rentré ! +1 Fame +X pièces · il a laissé un bébé à Noah » (« au Ranch 7 » si le nom est caché), avec le bouton « Pas ce joueur » | `BabyGet` ; propriétaire : `Return` | `catch` |
| **Capture Héros** | Le squishy grossit de 10 % sous les yeux (0,3) | 30 particules | — | Tampon « HÉROS ! » / « HERO! » doré (0,4, `Back Out`) | `HeroCatch` | `catch` (force 0,5) |
| Personne n'attrape | Le squishy rentre en bondissant ; au portail, il grossit de 5 % avec une étincelle | 8 étincelles | — | Propriétaire : « Wibble est rentré plus gros ! +5 % » | `Return` | — |
| **Monter** | La monture apparaît (0 → 1 en 0,25, `Back Out`), le joueur saute dessus (arc 0,3) ; profil `mount` : (1,25 ; 0,75 ; 1,25) en 0,12 | — | — | — | `MountUp` | — |
| Atterrissage en monture | (1,3 ; 0,7 ; 1,3) en 0,1 | 8 bouffées ; Grande selle : anneau d'éclaboussure ; Selle géante : onde 0 → 12 studs en 0,4 | — | — | `RideLand` | — |
| **Grand Splorch** (7,5 s) | 0,0 : le squishy brille (pulsation blanche 0,3) et s'élève de 8 studs (0,6, `Quad Out`). 0,6 : il vole vers la place sur une courbe (1,4, `Sine InOut`). 2,0 : à 40 studs au-dessus du MEGA pad, il gonfle de ×1 à ×2,5 en 1,2 (`Quad In`), en tremblant (±6 % de 4 à 8 Hz). 3,2 : **éclatement au ralenti** (0,8 ; pas en MR) en un grand nuage de confettis. 5,2 : il sort du nuage tout petit (0 → 1 en 0,4, `Back Out`) et fait coucou (0,6). 5,8 : il rejoint le héros en 3 grands bonds magiques (1,5 au total, traînée d'étoiles), quelle que soit la distance, atterrit à ses pieds à 7,3, puis rentre à sa place | 3,2 : 60 gouttes de gelée qui retombent, onde 0 → 80 studs en 0,8, `Bloom` +0,6 pendant 0,4. 4,0 : pluie de cadeaux : pour **chaque** joueur, 6 à 10 pièces et une capsule de bébé tombent près de lui (1,2) | Héros : caméra qui suit le vol puis le retour du petit squishy (pas en MR : une flèche le montre) ; secousse 0,3, amplitude 0,35 à l'éclatement ; flash blanc 0,1 (pas en MR). Autres : secousse atténuée par la distance. Visible de toute la carte | 5,2 : titre « GRAND SPLORCH III » qui s'écrit en 0,6 (`MaxVisibleGraphemes`) ; 7,3 : « Plop est là ! ×2 pour toujours » (vrai nom) ; bannière serveur ; puce APPLAUDIR chez les autres (8 s) | 2,0 `SplorchCharge` ; 3,2 `SplorchPop` ; 4,0 `GiftRain` ; 5,2 `Reward` | Héros : `splorch` ; autres : `catch` à la capsule |
| **MEGA SQUISH : alerte** | Ombre ronde qui grandit de 0 à 24 studs en 15 s et pulse | — | — | Bannière « MEGA SQUISH ! » + compte à rebours | `MegaWarn` | — |
| MEGA : atterrissage | Chute de 120 studs en 0,6 (`Quad In`) ; écrasement (1,4 ; 0,55 ; 1,4) en 0,15 puis `Elastic Out` 0,8 | 3 anneaux 0 → 60 studs décalés de 0,15 ; 40 bouffées de poussière | Secousse 0,3, amplitude `0,4 × (1 − d / 120)` si d < 120 studs | — | `MegaLand` | `megaLand` atténuée |
| MEGA : pression | Creux local (1,04 ; 0,96 ; 1,04) en 0,08 à chaque pression locale ; le serveur envoie un battement toutes les 0,25 s, écrasement proportionnel au nombre de pressions | « +1 » / « +3 » flottants | Barre de serveur qui se remplit (`Back Out`, 0,3) ; à 90 %, le géant tremble (±4 % à 6 Hz) et écarquille les yeux | — | `MegaPress`, hauteur de 0,9 à 1,3 selon la progression | `pressTick` |
| MEGA : ÉCLATE | Gonfle 1 → 1,3 en 0,3 (`Quad In`) puis éclate | 80 gouttes ; pluie de capsules de bébés (une par bébé, près de chaque participant) ; 60 confettis | Flash blanc 0,12 (pas en MR) ; coup de focale | « MEGA SPLORCH ! » | `MegaPop` puis `GiftRain` | `megaPop` |
| MEGA : échec | Le géant soupire (Y 1 → 0,9 → 1 en 1) et s'envole doucement (2) | — | — | « Presque ! » | `MegaSigh` | — |
| **Jauge pleine** | La jarre déborde ; Big Plop danse 8 s (sauts, 2 tours sur lui-même, dandinements) ; un grand ballon Plop de 20 studs monte au-dessus de la place pendant la danse | 40 confettis | Ciel légèrement doré pendant 5 min ; pastille « WOBBLE PARTY ×2 5:00 » | Bannière | `GaugeFull` | — |
| **Golden Wobbler** | Geyser doré de la fontaine, la créature sort en arc | 30 étincelles ; traînée dorée de 8 particules par seconde | — | Bannière à la capture | `GoldenAppear` ; à la capture `CatchGolden` | `catch` |
| **Sirène du BOOP RUSH** | Les squishies curieux trottent vers la clôture (un bond de 0,3 par pas) | — | Ciel rose (`Tint` (255, 200, 225)) en 2 s ; pastille rose « BOOP RUSH 1:30 ». Nouveau avant l'étape 9 : teinte à 30 %, pastille seulement | « BOOP RUSH ! » (pas pour un nouveau avant l'étape 9) | `RushSiren` puis `MusicRush` pendant 90 s (−12 dB pour un nouveau avant l'étape 9) | `rushSiren` (pas pour un nouveau avant l'étape 9) |
| **Jelly Moon** début / fin | Transition du ciel 4 s (nuit, grosse lune, teinte violet-sarcelle) ; les Lunaires ont 2 gouttes de gelée brillantes qui flottent autour d'eux (orbite de 3 s) | Lucioles lunaires (12 sur l'écran) | — | Bannière « JELLY MOON ! » | `MoonStart` puis `MusicMoon` | — |
| **Nourrir Plop** (le Meilleur Ami n° 1) | Anneau de maintien 5 s autour du bol ; le Meilleur Ami ouvre et ferme la bouche 4 fois, gonfle à 1,05 et revient | 6 cœurs | — | Tampon « Jour 42 ! » | `FeedPlop` ; palier : `Reward` | — |
| **Nouvelle entrée de Squishydex** | Carte qui glisse de la droite en 0,3 (`Back Out`), reflet `UIGradient` 0,6 | — | — | « NOUVEAU ! Gillygum · Néon » | `DexNew` | — |
| **Objectif terminé** | Barre remplie en 0,3, carte qui pulse à 1,1, coche qui se dessine | La récompense vole vers son compteur | — | — | `ObjectiveDone` | — |
| **Fanfare de record du serveur** | — | 3 feux d'artifice au-dessus de la place | — | Bannière dorée « Premier à 1 MILLIARD ! » | `Fanfare` | — |
| **Portail refusé** (intrus) | Le portail de gelée se bombe (Z 1 → 1,3 → 1 en 0,3), le joueur est repoussé sur un petit arc | — | — | « C'est le ranch de Mira ! » | `Boing` | — |
| **Achat Robux** | Pluie de 30 pièces (1) | Squish Party : bannière « SQUISH PARTY ×2 ! » + confettis pour tout le serveur | — | « Merci ! » | `Reward` | — |
| **Emote** | Icône 0 → 1,2 → 1 en 0,25 (`Back Out`), tenue 2,5, fondu 0,2 | — | — | — | `Emote` | — |

### 9.5 Captures et clips

- Réglage « Clips » (activé par défaut), et seulement si `PolicyService` renvoie `IsContentSharingAllowed = true` pour ce joueur.
- Capture vidéo automatique (`CaptureService:StartVideoCaptureAsync`, côté client) pour : naissance Légendaire ou mieux, mutation Arc-en-ciel, Glitch ou Flop, COMBO ×5, son propre Grand Splorch (case « Filmer mon Grand Splorch » sur l'écran d'aperçu, cochée par défaut). Arrêt après 8 s (`StopVideoCapture` ; Roblox arrête de toute façon à 30 s).
- À la fin, une petite carte **non bloquante** (§10.3) : « Garder ton clip ? » avec Enregistrer (`PromptSaveCapturesToGallery`), Partager (`PromptShareCapture`) et Fermer. Si le joueur n'y répond pas, elle se range dans la pastille « ! » de la puce Menu jusqu'à la fin de la session. Le jeu **ne partage jamais tout seul**.
- **Console** : chaque appel à `CaptureService` est protégé (`pcall`). Si la capture n'est pas disponible sur l'appareil, la case « Filmer » et la carte « Garder ton clip ? » n'apparaissent pas, sans message d'erreur ; le bouton Create de la PS5 (ou Partager de la Xbox) reste la capture du système.

### 9.6 Sons

**Provenance.** Chaque son vient **uniquement** des dépôts officiels de Roblox : **Roblox/resources** (Feature Packages, `SharedConstants.lua`, jeux d'exemple *Plant* et *Gold Rush*) et **Roblox/creator-docs** (tutoriels audio, modules). La source exacte (dépôt, fichier, ligne ou constante) est écrite **sur la ligne** de chaque son dans `Shared/Config/Sounds.luau`, au format `rbxassetid://<nombre>` (leçon de Comet Conga). Rien n'est téléversé.

**Sécurité.** Une clé vide (`id = ""`) est muette ; un son qui ne se charge pas est retiré au préchargement (un avertissement par clé, aucune erreur). Le jeu est entièrement jouable sans aucun son. Garde-fous de lecture (`AudioController`, repris) : 3 copies au plus par image et 4 en même temps pour une clé ; durée maximale 4 s (fondu 0,3 s) ; un seul jingle à la fois ; réglages Musique et Effets respectés. Deux clés qui partagent un enregistrement diffèrent d'au moins 15 % de hauteur.

**Sons d'interface** (partie du design console) : chaque geste dans un menu a son son, toujours le même : sélection qui bouge (`Select`), validation (`Click`), retour (`Back`), onglet ou panneau suivant (`Tab`), bout de liste (`Bump`), refus (`Error`). À 3 m, le son confirme l'appui avant que l'œil voie le changement. Ils respectent le réglage Effets sonores.

**Liste des moments sonores (clés).** Les candidats marqués « Comet » sont des sons officiels déjà retrouvés et vérifiés pour Comet Conga (`/home/user/jules/roblox-game/src/shared/Config/Sounds.luau`) ; les autres sont à chercher dans les mêmes dépôts. **Chaque son doit être écouté dans Studio avant la publication** (§18).

| Clé | Moment | Candidat |
|---|---|---|
| `Click`, `Pop` | Bouton pressé ; petite apparition | Comet (`BUTTON_ACTIVATED`, Pop plus aigu) |
| `Whoosh`, `Back`, `Tab`, `Select`, `Bump` | Panneau ouvert ; retour ○ ; onglet ; sélection manette ; bout de liste | Comet (`PROMPT_OPENED`, `PROMPT_CLOSED`, `BUTTON_HOVER`, hauteurs différentes) |
| `Error` | Refus | Comet (`PROMPT_CLOSED` plus grave) |
| `Coin` | Pièces qui arrivent au compteur | Comet (*Plant* « Coins ») |
| `Reward`, `LevelUp` | Récompense, achat Robux ; palier | Comet (`PURCHASE_EFFECT` ; « retro jingle ») |
| `Music`, `MusicMoon`, `MusicRush` | Musique de jour ; Jelly Moon (plus douce) ; BOOP RUSH (gloussements, rapide) | Comet `Music` pour le jour ; les deux autres à chercher |
| `Press` | SPLORCH (hauteur au hasard 0,92-1,08) | À chercher (son mou, « squish ») ; repli : `Pop` grave |
| `Perfect`, `StreakMax` | PERFECT (hauteur qui monte) ; série de 5 | À chercher ; repli : `Click` aigu |
| `PotCollect`, `TileBuild`, `VatBubble` | Pot ; dalle construite ; Cuve presque pleine | À chercher |
| `Hatch`, `HatchRare`, `HatchLegend`, `MutationReveal` | Naissances ; révélation de mutation | `Catch` / `CatchRare` / `BeaconWin` de Comet comme replis |
| `Blorp` | Le cri du Flop | À chercher (son grave et mou) |
| `Pickup`, `Throw`, `Splash` | Prendre ; lancer ; plongeon dans le Bassin | À chercher |
| `Fuse`, `ComboStep`, `ComboBig` | Fusion ; étape de combo (hauteur qui monte) ; combo ×5 | À chercher ; repli : `LevelUp` |
| `RunawayAppear`, `Giggle`, `Catch`, `CatchGolden` | Créature qui sort ; gloussement ; capture ; Golden attrapé | Comet `Catch`, `CatchRare` |
| `Leap`, `MountUp`, `RideLand` | Bondir ; monter ; atterrir en monture | Comet `Dash` comme repli de `Leap` |
| `RushSiren`, `BoopHold`, `Sneeze`, `Return`, `BabyGet`, `HeroCatch` | Sirène ; maintien du boop ; ATCHOUM ; retour au ranch ; bébé gagné ; capture Héros | À chercher ; `Sneeze` doit rester drôle et doux |
| `MegaWarn`, `MegaLand`, `MegaPress`, `MegaPop`, `MegaSigh` | MEGA SQUISH | Comet `CometWarn`, `CometImpact` comme replis |
| `GaugeFull`, `GoldenAppear`, `MoonStart`, `Fanfare` | Jauge pleine ; Golden ; Jelly Moon ; record | Comet `BeaconWin` comme repli de `Fanfare` |
| `SplorchCharge`, `SplorchPop`, `GiftRain` | Grand Splorch | Comet `Supernova` comme repli de `SplorchPop` |
| `FeedPlop`, `DexNew`, `ObjectiveDone`, `Emote`, `Boing` | Nourrir Plop ; Squishydex ; objectif ; emote ; portail refusé | À chercher |

---

## 10. Interface télé, commandes et console

### 10.1 Principes : la disposition « 10 pieds » est la seule disposition

- **Une seule disposition**, pensée pour une télé vue de 2,5 à 3 m (PS5, Xbox), et utilisée telle quelle sur PC, à la manette comme au clavier-souris. Pas de disposition pour téléphone, aucune commande tactile, **aucun bouton à l'écran pour jouer** : on joue avec les touches, l'écran montre leurs glyphes. La souris peut cliquer ce qui est affiché, mais rien n'est fait pour elle seule.
- Tout est construit en code (`Frame`, `TextLabel`, `TextButton`, `UIGradient`, `UIStroke`, `UICorner`, `UIScale`, `UIListLayout`, `UISizeConstraint`). Aucune image téléversée : icônes en formes de Frames et grands glyphes ; glyphes de manette fournis par Roblox (`GetImageForKeyCode`).
- Un `ScreenGui` par écran logique, `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling`.
- **Référence 1920 × 1080 (px TV)**, la même règle sur tous les écrans : `UIScale = max(0,5 ; min(L / 1920, H / 1080))`, sans plafond. 1 en 1080p, **2 en 4K**, 0,667 en 1280 × 720. La taille vue depuis le canapé est la même sur une télé 720p, 1080p ou 4K. Le module `UI/Root` repris de Comet change seulement sa constante de référence (1280 × 720 → 1920 × 1080) ; l'ancienne règle « écran ordinaire plafonné à 1,25 » disparaît.
- **Zone sûre TV sur tous les écrans** : marge de **5 %** de chaque côté. En px TV : x de 96 à 1824, y de 54 à 1026. Seuls les fonds décoratifs (voile des panneaux, vignette de couleur, flash) en sortent ; ils portent l'attribut `Decorative = true` s'ils contiennent du texte.
- **Tailles minimales** (px TV) :

| Élément | Minimum | Valeurs habituelles |
|---|---|---|
| Texte que le joueur doit lire | **28** | 32 (corps), 40 (boutons, consignes), 48-56 (titres, bannières), 56-72 (compteurs) |
| Glyphe de touche | **48** | 64 pour la consigne principale et l'invite □ |
| Hauteur d'un bouton | **80** | 96 pour le bouton principal d'un écran |
| Écart entre deux éléments sélectionnables | **16** | 24 |
| Cadre de sélection (focus) | 6 px blanc + 2 px sombre | grossissement 1,05 |

  Pourquoi 28 : 28 px TV font 2,6 % de la hauteur de l'écran. Sur une télé de 55 pouces vue à 3 m, c'est environ 20 minutes d'arc, lisible par un enfant de 8 ans. Comet Conga s'arrêtait à 27 px réels en 1080p ; on monte d'un cran et on écrit le texte courant en 32.
- **Contraste** : texte clair sur un fond foncé translucide (opacité ≥ 0,6) ou avec un contour `UIStroke` de 3 px. Jamais de texte posé directement sur le décor.
- **Peu d'éléments, grands** : en jeu calme, 8 éléments au plus sont visibles (pièces, Fame, puce Menu, pastille d'événement, jauge, suivi d'objectif, indicateurs, carte de la cible). Le reste n'apparaît que quand il sert (divulgation progressive) et disparaît ensuite.
- **Aucun chevauchement, aucun texte coupé** : chaque élément du HUD a une place fixe dans une colonne (gauche, centre, droite, bas) ancrée à un bord de la zone sûre. Deux éléments ne se recouvrent jamais, à aucune des 3 résolutions visées (1920 × 1080, 3840 × 2160, 1280 × 720) ni sur un écran plus large ou plus haut que 16:9 (les colonnes s'écartent, elles ne se rapprochent pas). Chaque texte a `TextScaled` et un `UITextSizeConstraint` dont le minimum est 28 px TV : s'il ne tient pas à 28 en anglais **et** en français, le test échoue et on raccourcit le libellé (§12.10, couche d).
- **Le focus n'est jamais perdu ni piégé** : règles au §10.6.
- Style : `UICorner` 14-18 px ; `UIStroke` 3 px bleu nuit (30, 25, 60) ; dégradés pastel ; police `FredokaOne` pour le texte, `LuckiestGuy` pour les tampons.
- **Affichage progressif** : pendant l'accueil, seuls les éléments déjà présentés sont visibles (§3).

### 10.2 HUD (px TV, zone sûre x 96-1824, y 54-1026)

| Élément | Position (ancrage) | Taille | Contenu |
|---|---|---|---|
| Pastille Pièces | Haut gauche (96, 54) | 440 × 112 | Pièce dessinée de 80, montant en 56 px, revenu « +1,2K/s » en 32 px |
| Pastille Fame et amis | Haut gauche (96, 178) | 320 × 56 | Étoile + Fame ; cœur + nombre d'amis présents (32 px) |
| **Puce Menu** | Haut gauche (96, 246) | 260 × 80 | Glyphe △ (48) + « Menu » (40 px) ; « Tab » au clavier ; un clic l'ouvre aussi. Porte les pastilles « ! » (action possible, carte en attente) et « ♥ 3 » (paires de jumeaux) |
| Menu ouvert (le rail) | À la place de la puce, (96, 246) vers le bas | Jusqu'à 7 boutons de 340 × 96, écart 12 (y 246 à 990) | Grand Splorch (seulement quand il est prêt), Ranch, Squishydex, Objectifs, Classements, Boutique (après 10 min de jeu et si un identifiant existe), Réglages. Icône de 56 + libellé de 36 px |
| Pastille d'événement | Haut centre (y = 54) | 560 × 72 | Prochain événement « BOOP RUSH 3:12 » (36 px) ; événement en cours en couleur (Rush rose, MEGA jaune, Lune violet, Wobble Party orange) |
| Barre du MEGA | Haut centre (y = 138) | 720 × 48 | Progression du serveur, objectif, temps restant (28 px) |
| Jauge du serveur | Haut centre (y = 138, hors MEGA) | 400 × 28 + icône Plop de 40 | Remplissage |
| **Emplacement de message** | Haut centre (y = 198) | Bannière 1000 × 112 ; message 760 × 88 | **Un seul à la fois.** Les bannières de serveur (§6.6 ; titre 48 px, ligne 32 px) passent d'abord ; les messages (module `UI/Toast` repris, 32 px) attendent, 3 au plus en file, 2,5 s chacun, les messages identiques fusionnés (« +X pièces ×3 ») |
| Suivi d'objectif | Haut droite (−96, 54) | 440 × 104 | Anneau de 72 + « Grand Splorch » (32 px) + « 12K / 15K » (28 px) |
| Indicateurs d'état | Haut droite (−96, 170), en ligne | 64 × 64 chacun, écart 12, 3 au plus ; minutes en 28 px dessous (jusqu'à y = 266) | Bouclier débutant, boost ×2, mon mode (Rush ou Cozy). Affichage seul |
| Carte non bloquante | Droite (−96, 330) | 520 × 220 au plus | Titre 40 px, texte 32 px, glyphe △ (48) + « Voir ». 8 s, puis rangée dans la pastille « ! » (§10.3) |
| **Puce d'action spéciale** | Bas centre, bas à −162 (y 822-918) | 520 × 96 | « GRAND SPLORCH ! » avec le glyphe △ quand l'objectif est atteint (△ ou croix ↓ ouvre le menu sur l'entrée Grand Splorch : 2 appuis jusqu'à l'aperçu ; à la souris, un clic sur la puce) ; « APPLAUDIR » avec le glyphe croix → et un anneau de 8 s, à la place de la précédente (§6.7). Pendant l'accueil, cette place sert à la consigne du moment (glyphe 64 + mot 40 px) quand l'objet visé n'est pas à l'écran |
| Carte de la cible | Bas centre, bas à −54 (y 930-1026) | 680 × 96 | Squishy visé : nom (36 px), rareté (couleur + forme), taille, revenu, étoiles, mutation (28 px). Affichage seul |
| Indicateur Bondir | Bas droite (−96, −54) | 96 × 96 | Glyphe R2 (64) et balayage de recharge. Visible seulement pendant la recharge, pendant la leçon de l'accueil, et en ville pendant un Rush ou un Golden |
| Flèches de bord d'écran | Bord de la zone sûre | 72 × 72 | Vers sa créature en fuite, son squishy boopé, la fuite la plus proche (joueurs Rush) |

Vérification des colonnes (aucun recouvrement) : à gauche, x ≤ 536 jusqu'à y = 166, puis x ≤ 436 (menu ouvert compris) ; au centre, x de 460 à 1460 et y de 54 à 310 ; à droite, x ≥ 1304, y de 54 à 550 ; en bas, y ≥ 822, x de 620 à 1300, plus l'indicateur Bondir à x ≥ 1728. Le milieu de l'écran (y de 330 à 822, x de 460 à 1300) reste libre pour le personnage et ses squishies. `tests/harness/Layout` vérifie ces rectangles aux 3 résolutions, en anglais et en français.

**Invites dans le monde** (dessinées par `UI/Prompt` au-dessus de la cible, en px TV mis à l'échelle comme le reste) : « □ Presser » (glyphe 64 + mot 40 px, plaque de 300 × 88) et, après la leçon de fusion, une deuxième ligne plus petite « ○ Prendre » (glyphe 48 + mot 32 px). Au clavier : « E Presser », « Q Prendre ». Jamais deux invites sur la même touche, jamais plus de 2 invites à la fois. L'anneau des maintiens (boop, bol) entoure le glyphe □ et suit l'heure de fin envoyée par le serveur.

### 10.3 Écrans

| Écran | Accès | Contenu | Remarques |
|---|---|---|---|
| Chargement | Automatique | Plop qui rebondit, points animés | `ReplicatedFirst`, code seul. Délai : si le profil n'est pas chargé en 60 s, l'écran d'échec s'affiche (jamais un chargement infini) |
| Échec de chargement | Automatique | « Ton ranch se réveille… » + Réessayer | Réessayer attend la fin des essais du DataService (attribut `ProfileLoading`), sélectionné d'office à la manette (leçon de Comet Conga) |
| Écran de retour | Au chargement | §7.2 | « Super ! » sélectionné d'office |
| Carte du choix Rush / Cozy | Au calme, dès 15:00 de jeu (§4.21.1) ; Réglages | Deux gros boutons, animation de 6 s en boucle, « Plop ne s'enfuit jamais » | Garde de 0,6 s ; sans réponse en 20 s : Cozy |
| Carte « Wibble revient toujours ! » | Après le premier boop subi, au retour du squishy | « +X pièces +1 Fame », boutons « Continuer », « Mode Cozy », « Pas ce joueur » | Non bloquante |
| **Ranch** | Menu | Onglets : *Enclos* (grille des squishies, tri, verrou, Meilleur Ami, monture ; les jumeaux portent un cœur ; boutons **Tout fusionner** et **Ranger**), *Dodo* (Boîte à dodo, échanger), *Lettres* (Boîte aux lettres), *Fusionner* (choisir A puis B, ou Tout fusionner), *Vendre / Relâcher* (sélection multiple ; maintien 0,6 s, confirmation en 2 étapes pour Épique+ ou mutation Doré+, §4.13), *Dalles* (liste de toutes les dalles avec prix : on peut aussi acheter d'ici) | Grille virtualisée ; la sélection suit l'index au défilement (leçon de Comet) |
| **Squishydex** | Menu | Onglets : *Espèces* (26 pages), *Mutations* (grille 26 × 9), *Familles* (bonus), *Étoiles*, *Guide* (toutes les probabilités et règles) | Silhouettes grises pour ce qui manque |
| **Objectifs** | Menu | *Aujourd'hui* (3 objectifs, relance), *Plop* (jours au total, paliers), *Accueil* (tant qu'il n'est pas fini) | |
| **Classements** | Menu | 5 onglets (§6.9) : d'abord ma place sur ce serveur et mon record contre la semaine dernière, puis le top 10 mondial | |
| **Boutique** | Menu (après 10 min) | *Passes*, *Fête et pièces*, *Tenues* (aperçu 3D) ; prix lus à l'exécution | Cachée si aucun identifiant ; masquage PolicyService (§8.1) ; paquets de pièces cachés quand « Grand Splorch prêt ! » (§8.3) |
| **Aperçu du Grand Splorch** | Menu → Grand Splorch (entrée sélectionnée d'office quand il est prêt) | 3 tuiles « Tu gagnes », animation avant/après, perte de pièces en rouge et « Dépenser d'abord », choix du squishy qui s'envole, case « Filmer », bouton à maintenir 1,5 s (✕) ; « Détails » ouvre les deux colonnes (§4.15) | Hors du ranch : « Rentre dans ton ranch » (seulement pour entrer dans la file) |
| **Réglages** | Menu | Mode Rush/Cozy, Cacher mon nom, Recevoir les cadeaux, Clips, Mouvement réduit, Graphismes légers, Musique, Effets sonores, Vibrations, Emote de la croix ← (Bravo, Belly Flop, Couronne), Langue (Auto / English / Français) ; propriétaire d'un serveur privé : « BOOP RUSH autorisé » ; administrateurs seulement : **Diagnostics** | Interrupteurs de 120 × 64 px TV ; message « Tes squishies grandissent même quand tu dors » en bas |
| **Diagnostics** | Réglages → Diagnostics (visible et accessible **seulement** aux administrateurs, vérifié par le serveur) | Erreurs et avertissements comptés sur ce serveur et sur ses clients, derniers exemples, état du serveur et du client, totaux du jour (§12.11) | Lecture seule ; fait pour être photographié |

**Panneaux** : 1440 × 860 px TV, centrés (x 240-1680, y 110-970) ; en-tête de 96 (titre 48 px) ; onglets de 72 px de haut (libellés 32 px), atteignables à la croix (↑ depuis le haut du contenu) en plus de L1 / R1 ; grilles de cases de 208 × 232 (6 colonnes, 2 rangées et demie visibles : la demi-rangée montre qu'on peut défiler) ; boutons de 80 à 96 px de haut ; bouton Fermer de 80 × 80 avec le glyphe ○. Un seul panneau ouvert à la fois. Ouvrir un panneau ne met pas le jeu en pause.

**Cartes en jeu** (règle commune, module `UI/Cards`)
- **Cartes non bloquantes** : objectifs à 5:00, « Nouveaux objectifs ! », « Plop a sommeil », nouvelle entrée du Squishydex, « Garder ton clip ? », « Wibble revient toujours ! ». Elles ne prennent **jamais** la sélection de la manette : le stick continue de faire marcher. Elles s'affichent à droite (§10.2) pendant 8 s, puis se rangent dans la pastille « ! » de la puce Menu. Pour agir : △ (ou croix ↓) ouvre le menu sur la carte en attente ; à la souris, un clic sur la carte.
- **Carte bloquante ouverte par le jeu** : seulement la carte du choix Rush / Cozy (l'écran de retour et l'échec de chargement s'ouvrent au chargement). Jamais pendant un Rush, un MEGA, une poursuite ou un portage ; seulement au calme (§4.21.1). **Garde d'entrée de 0,6 s** : boutons grisés, aucun appui accepté, pour qu'un ✕ appuyé pour sauter ne choisisse rien. Délai : 20 s, puis Cozy.
- **Une seule carte à la fois**, dans cet ordre : écran de retour > carte du choix > « Wibble revient toujours ! » > objectifs > Squishydex > clip > « Plop a sommeil ». Les autres attendent leur tour.
- Pendant une carte bloquante, le menu ou un panneau ouvert, les touches du jeu sont déliées (□, ○, R2, L2, L1, R1, croix ↑ → ←) et les invites du monde sont cachées : aucune action ne part derrière une fenêtre.

### 10.4 Commandes

Noms PlayStation (DualSense) avec la `KeyCode` générique de Roblox entre parenthèses. Sur Xbox, les mêmes `KeyCode` portent les noms Xbox ; le jeu affiche **toujours** l'icône de l'appareil (`UserInputService:GetImageForKeyCode`), jamais une lettre écrite en dur.

| Action | Manette (DualSense — `KeyCode`) | Clavier / souris |
|---|---|---|
| Se déplacer | Stick gauche (`Thumbstick1`) | WASD (ZQSD reconnu tout seul en AZERTY) / flèches |
| Caméra | Stick droit (`Thumbstick2`). **La caméra ne bouge jamais toute seule** (sauf le travelling du Grand Splorch, coupé en Mouvement réduit) | Clic droit + souris |
| Sauter (plus haut sur sa monture) | ✕ (`ButtonA`) | Espace |
| **Action principale** : presser, lancer (en portant, près du Bassin), acheter (sur une dalle), attraper, booper (maintien 2,5 s), nourrir au bol (maintien 5 s) | **□** (`ButtonX`) | E, ou clic gauche sur la cible |
| **Prendre / Poser** (un squishy de son ranch) | **○** (`ButtonB`) | Q |
| **Bondir** (visée automatique et capture à l'atterrissage, §4.12) | **R2** (`ButtonR2`) | Maj gauche |
| **Monter / descendre** | **L2** (`ButtonL2`) | R |
| Changer de cible (dans son ranch, et devant une clôture pour booper ou pet-sitter) | L1 / R1 (`ButtonL1` / `ButtonR1`) | Clic sur un squishy (il reste la cible 4 s) |
| **Menu** | **△** (`ButtonY`) **ou croix ↓** (`DPadDown`) | Tab, ou clic sur la puce Menu |
| Emotes : salut, merci, bravo (§6.5) | Croix ↑, →, ← (`DPadUp/Right/Left`) | 1, 2, 3 |
| Applaudir (pendant 8 s) | Croix → (remplace « merci » pendant ces 8 s) | F, ou clic sur la puce |
| Menu Roblox | Options (`ButtonStart`, réservé) | Échap (**jamais lié par le jeu**, leçon de Comet) |
| Pavé tactile / Create | `ButtonSelect`, réservé à Roblox | — |
| Libres volontairement | L3, R3 (un enfant les enfonce sans le vouloir) | — |

- **Aucun appui simultané obligatoire**, aucun clic de stick, aucune combinaison : chaque action tient sur une touche (règle d'accessibilité, §14).
- **Pas de verrouillage de la souris** (`StarterPlayer.EnableMouseLockOption = false`) : Maj sert à Bondir.
- **Le jeu choisit la cible** (`PromptController`) :
  - Candidats : les squishies de son ranch à 10 studs au plus, ou les 4 au plus d'une clôture (boop, pet-sitting), ou la dalle sous ses pieds (□ = Acheter). Pour □, les squishies prêts passent toujours avant ceux en recharge.
  - Score = distance (studs) + 6 × (angle avec la direction du personnage ÷ 90°) ; le plus petit gagne.
  - Hystérésis : la cible change si une autre est meilleure de 1,5 stud, ou au bout de 0,25 s.
  - Après une pression, la cible passe au prochain squishy prêt en 0,15 s : marteler □ presse toujours un squishy prêt.
  - L1 / R1 font défiler les candidats par angle (de gauche à droite), dans le ranch et devant une clôture. En ville, en poursuite, ils ne servent pas (mêlée illisible sur une télé).
  - Un clic de souris sur un squishy le fixe comme cible pendant 4 s. Le clic est trouvé **par l'écran**, pas par un rayon : on projette le centre de chaque squishy candidat (`Camera:WorldToViewportPoint`) et on prend le plus proche du pointeur dans un rayon de `max(32 px TV, rayon projeté × 1,2)`. Les pièces des squishies restent en `CanQuery = false` (performances).
  - Pendant un maintien (boop, bol, Grand Splorch), la cible est verrouillée.
- **Poursuites** : visée et capture du §4.12 (position future, direction du stick gauche, ±40°, 16 studs, capture à l'atterrissage, tampon de 0,25 s). Un marqueur blanc montre la créature visée.
- **Invites dessinées par le jeu, sans `ProximityPrompt`** : `UI/Prompt` dessine l'invite au-dessus de la cible ; `InputController` lie □ et ○ par `ContextActionService:BindActionAtPriority` (au-dessus des contrôles par défaut) **seulement** quand une invite est affichée et qu'aucune fenêtre n'est ouverte. Un maintien suit les états `Begin` et `End` de la touche ; l'anneau suit l'heure de fin envoyée par le serveur (`BoopState.endsAt`), car un boop peut passer de 2,5 à 5 s en cours de route. Pourquoi : un `ProximityPrompt` choisit sa cible selon la caméra, se cache derrière la clôture (ligne de vue), garde sa touche liée derrière un panneau et a un style trop petit pour la télé. Ces comportements du moteur ne se testent pas hors de Roblox ; nos invites se testent entièrement dans le harnais.
- Les actions passent par `ContextActionService`. Le déclenchement envoie une **intention** au serveur (§12.7) ; l'effet n'est montré qu'après sa réponse (sauf le geste lui-même : écrasement, bond).

**Dans les menus**
- **Manette** : croix ou stick gauche déplacent la sélection ; ✕ valide ; ○ recule d'un niveau (depuis le premier niveau, il rend la main au jeu) ; △ ferme tout et revient au jeu ; L1 / R1 changent d'onglet (en boucle) ; L2 / R2 changent de panneau (en boucle : Ranch → Squishydex → Objectifs → Classements → Boutique → Réglages) **seulement quand un panneau est ouvert**, sinon L2 = Monter et R2 = Bondir. La sélection fait défiler les listes toute seule ; le stick droit fait aussi défiler. **Règle des 3 touches** : la croix, ✕ et ○ suffisent pour atteindre chaque écran et en revenir (L1, R1, L2, R2 et △ ne sont que des raccourcis). Quand une sélection d'interface existe, ○ veut toujours dire « retour ».
- **Clavier et souris** : la souris clique ; Retour arrière = retour (comme ○) ; Tab ouvre et ferme le menu ; Échap reste à Roblox. Pas de navigation obligatoire aux flèches : la souris suffit.

### 10.5 Vibrations (DualSense et manettes Xbox)

`Util/Haptics` (repris de Comet Conga) : `HapticEffect` du type indiqué (une instance réutilisée par type), repli `HapticService:SetMotor` pendant la durée. Les vibrations font partie du design : elles disent « c'est fait » à un joueur qui regarde la télé de loin. **Modération** : jamais au clavier-souris ; **délai minimal de 0,25 s** entre deux vibrations, sauf priorité supérieure ; atténuation < 0,35 ignorée ; réglage « Vibrations » (activé par défaut). Seuls les moteurs standard sont utilisés : aucun effet propre à la DualSense (gâchettes adaptatives) n'est supposé, car Roblox ne les expose pas. Jamais de vibration sur un déplacement de sélection, un bond ou une marche.

| Événement | Quand | `HapticEffectType` | Repli (moteur, force, durée) | Priorité |
|---|---|---|---|---|
| `pressTick` | Pression (et pression sur le MEGA) — **2 par seconde au plus** | UIClick | Small, 0,15, 0,03 s | 1 |
| `perfect` | PERFECT ; série de 5 | UIClick | Small, 0,3, 0,05 s | 2 |
| `tileBuy` | Dalle achetée | UIClick | Small, 0,25, 0,05 s | 2 |
| `refuse` | Bouton refusé | UIClick | Small, 0,25, 0,05 s | 1 |
| `listEnd` | Bout de liste | UIClick | Small, 0,2, 0,04 s | 1 |
| `holdStart` | Début d'un maintien (Grand Splorch, boop, Nourrir Plop) | UIClick | Small, 0,25, 0,05 s | 1 |
| `holdDone` | Maintien terminé (boop réussi, bol, confirmation) | UINotification | Small, 0,35, 0,08 s | 2 |
| `cardIn` | La carte du choix Rush / Cozy s'ouvre | UINotification | Small, 0,2, 0,06 s | 2 |
| `catch` | Capture (fuite, Golden, Wild, Rush, Héros, capsule de cadeau) ; naissance Épique | GameplayCollision | Small, 0,35, 0,08 s | 2 |
| `fusion` | Chaque étape de fusion (force + 0,05 par étape) | GameplayCollision | Small, 0,4, 0,08 s | 2 |
| `comboBig` | Combo ≥ 4 | GameplayCollision | Large, 0,6, 0,2 s | 3 |
| `boopDone` | Mon boop a réussi | GameplayCollision | Small, 0,3, 0,06 s | 2 |
| `booped` | Un de mes squishies s'enfuit | UINotification | Small, 0,3, 0,12 s | 2 |
| `rushSiren` | Sirène du BOOP RUSH : **double impulsion** (2 × 0,1 s, écart 0,15 s) ; jamais pour un nouveau avant l'étape 9 de l'accueil | UINotification | Small, 0,4, 2 × 0,1 s | 3 |
| `megaLand` | Atterrissage du MEGA à moins de 120 studs, atténué `1 − d/120` | GameplayExplosion | Large, 0,7, 0,25 s | 3 |
| `megaPop` | Le MEGA éclate (participant) | GameplayExplosion | Large, 0,8, 0,3 s | 4 |
| `hatchLegend` | Naissance Légendaire ou mieux ; Flop — **forte impulsion de 300 ms** | GameplayExplosion | Large, 0,8, 0,3 s | 4 |
| `splorch` | Mon Grand Splorch (à l'éclatement) | GameplayExplosion | Large, 1,0, 0,4 s | 5 |

### 10.6 Console et télé : règles, focus et navigation

Le joueur est assis à 2,5-3 m de la télé. Règles officielles retenues (documentation Roblox *Console development guidelines*, *Gamepad input*, *UI selection*) et leur traduction :

| Règle | Traduction pour Raise a Squishy |
|---|---|
| Publier pour les bons appareils | Creator Hub : types d'appareils **Ordinateur + Console** ; Téléphone et Tablette décochés ; VR coupée (§18) |
| Tailles relatives, agrandir sur grand écran, développer pour la petite résolution d'abord | Référence 1920 × 1080 proportionnelle sans plafond, vérifiée aussi en 1280 × 720 et en 4K (§10.1) |
| `GuiService:IsTenFootInterface()` = seule détection sûre d'une console | `Platform.isTenFoot()` sous `pcall`. Sert à montrer les glyphes de la manette dès le départ et à l'analytique ; **la disposition ne change pas** entre console et PC |
| Zone sûre TV | 5 % de chaque côté sur tous les écrans (§10.1) |
| Tout atteignable avec 4 directions + valider + retour | Chaque fenêtre est un `SelectionGroup` avec `SelectionBehavior* = Stop` ; graphe `NextSelection*` explicite là où la géométrie hésite ; **règle des 3 touches** (croix + ✕ + ○, et croix ↓ pour ouvrir le menu depuis le jeu) vérifiée par un robot qui parcourt tous les écrans (§12.10, couche d) |
| Actions clés en peu de gestes | □ action, ○ prendre / poser, R2 bondir (et attraper), L2 monter, △ menu. Ranch = △ ✕ ; Grand Splorch = △ ✕ (entrée sélectionnée d'office) ; chaque panneau à 3 gestes au plus de son voisin |
| Icônes de la manette du joueur | `UI/Glyph` : `GetImageForKeyCode` (icônes PlayStation sur PlayStation, Xbox sur Xbox), repli neutre en losange (jamais « X » ou « LB » écrits) ; au clavier, texte de la touche selon la disposition (`GetStringForKeyCode` : sur AZERTY, `KeyCode.Q` s'affiche « A »). Changement de manette ou passage au clavier : tous les glyphes changent aussitôt |
| **Pas de fenêtre de chat sur console** | `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)` (nouveaux essais pendant 10 s), `TextChatService.ChatWindowConfiguration.Enabled = false`, `ChatInputBarConfiguration.Enabled = false`. Les bulles restent. Communication : les 3 emotes. Sur PC, le chat de Roblox reste tel quel (il est soumis à la vérification d'âge de Roblox) |
| Vibrations avec modération | §10.5 |
| Sons de navigation | `Select`, `Click`, `Back`, `Tab`, `Bump`, `Error` (§9.6) |
| Navigation sur mesure plutôt que curseur virtuel | `StarterGui.VirtualCursorMode = Disabled` (déjà dans `default.project.json`) |
| Informations de maturité obligatoires | Questionnaire rempli avant d'activer la console (§18) |

**Le focus (la sélection) n'est jamais perdu ni piégé** (module `UI/FocusGuard`, nouveau, qui reprend les règles du `PanelController` de Comet) :
1. Une seule source : `GuiService.SelectedObject`.
2. **En jeu, aucune sélection** : le stick fait marcher. Une sélection qui reste posée alors qu'aucune fenêtre n'est ouverte est effacée en 0,25 s.
3. **Fenêtre ouverte** (menu, panneau, carte bloquante, écran de retour, échec de chargement) : la sélection est toujours dans la fenêtre active. Si elle devient vide ou sort de la fenêtre (objet détruit, onglet changé, liste rechargée, menu système refermé), elle est rendue en 0,25 s au dernier objet encore affiché, sinon à la sélection par défaut de l'écran. Seule exception : pendant une fenêtre de Roblox (achat, invitation, menu système), la sélection est tenue en attente (`holdSelection`), **60 s au plus**, puis rendue de force.
4. Fermer une fenêtre rend la sélection à ce qui l'a ouverte (le bouton du menu), ou au jeu.
5. ○ marche partout et remonte d'un niveau ; depuis le premier niveau, il rend la main au jeu. Aucun écran sans retour.
6. Double appui : une fermeture moins de 0,35 s après l'ouverture de la même fenêtre est ignorée.
7. Un objet sélectionnable n'est jamais caché derrière un autre ni hors de la zone sûre ; une liste défile pour garder la sélection visible avec une rangée de marge.
8. Chaque sauvetage de la sélection est compté (`FocusRescued`, §16.3) : en ligne, c'est le signe d'un bug à corriger.

**Modules repris** (copiés depuis Comet Conga, puis adaptés seulement là où ce GDD le dit) : `Client/Util/Platform`, `UI/Glyph`, `Util/Haptics` (table d'événements remplacée par celle du §10.5), `Config/Console`, `UI/Root` (référence 1920 × 1080, zone sûre de 5 % sur tous les écrans, `selectionImage` blanc de 6 px), le modèle de `PanelController` (○ recule, △ ferme, L1/R1, L2/R2, garde contre le double appui, `holdSelection`), et le harnais `tests/harness/Gamepad` + `Layout`. **Nouveaux** : `UI/Prompt` (invites du monde), `UI/FocusGuard`.

**Appareil tactile inattendu** (Téléphone décoché mais réglage oublié, émulateur de Studio) : rien ne casse et aucune erreur n'est écrite ; un message s'affiche (« Raise a Squishy se joue avec une manette ou un clavier ») ; l'analytique compte `TouchDeviceJoined`. Aucune commande tactile n'est ajoutée.

**Navigation écran par écran**

| Écran | Sélection par défaut | ○ | L1 / R1 | L2 / R2 |
|---|---|---|---|---|
| Jeu | aucune (le stick fait marcher) | Prendre / poser | Changer de cible (ranch, clôture) | Monter / Bondir |
| Menu (après △ ou croix ↓) | Grand Splorch s'il est prêt, sinon le bouton à pastille « ! », sinon le dernier utilisé, sinon Ranch | Retour au jeu | — | — |
| Ranch | 1re case de l'onglet ; *Fusionner* : « Choisir A » ; *Dalles* : la moins chère achetable | → bouton du menu d'origine | Onglets | Panneaux |
| Squishydex | 1re entrée ; *Guide* : 1re ligne (↑ / ↓ font défiler de 70 % les listes en lecture seule) | → menu | Onglets | Panneaux |
| Objectifs | « Réclamer » disponible, sinon 1re carte | → menu | Onglets | Panneaux |
| Classements | Onglet en cours | → menu | Onglets | Panneaux |
| Boutique | 1er « Acheter » de l'onglet | → menu | Onglets | Panneaux |
| Réglages | 1er interrupteur | → menu | — | Panneaux |
| Diagnostics | Onglet « Ce serveur » | → Réglages | Onglets | — |
| Aperçu du Grand Splorch | Bouton « Maintenir » (glyphe ✕) | → menu | — | — |
| Carte du choix Rush / Cozy | « Je reste tranquille » (le choix sûr), après la garde de 0,6 s | = Cozy | — | — |
| Cartes non bloquantes | aucune : elles ne prennent jamais la sélection ; △ ouvre la première en attente | — | — | — |
| Écran de retour | « Super ! » | Ferme | — | — |
| Échec de chargement | Réessayer | — | — | — |

**Réglages de la place** (`default.project.json`, fichier d'un autre rôle) : `Players.MaxPlayers = 16`, **`Workspace.StreamingEnabled = false`** (choix délibéré, §12.9), `VirtualCursorMode = Disabled`, `EnableMouseLockOption = false`, `TextChatService.ChatVersion = TextChatService`, `Lighting.Technology = ShadowMap` (§11.3). La taille du serveur se règle aussi à 16 dans le Creator Hub, avec les types d'appareils Ordinateur + Console (§18).

---

## 11. Monde : Wobbleton, construite en formes simples

### 11.1 Plan (vue de dessus, rayons en studs, origine au centre de la place)

```
                        r = 320  bord du plateau (collines de bonbons jusqu'à r = 420)
             ┌──────────────────────────────────────────────────────────┐
             │  16 RANCHS de r = 178 (portail) à r = 250 (fond),         │
             │  un tous les 22,5°, 64 studs de large                     │
             │     ┌────────────────────────────────────────────┐        │
             │     │  Grand boulevard r = 166 (12 de large)      │        │
             │     │  trottoirs r 170-178 : Fontaines de Gelée   │        │
             │     │     ┌──────────────────────────────┐        │        │
             │     │     │ QUARTIERS r 55-160 : maisons │        │        │
             │     │     │ bonbons, jardins, 8 rues     │        │        │
             │     │     │ radiales, anneau r = 95      │        │        │
             │     │     │     ┌──────────────┐         │        │        │
             │     │     │     │ PLACE r < 50 │         │        │        │
             │     │     │     │ MEGA pad,    │         │        │        │
             │     │     │     │ statue, Lune │         │        │        │
             │     │     │     └──────────────┘         │        │        │
             │     │     └──────────────────────────────┘        │        │
             │     └────────────────────────────────────────────┘        │
             │  Prairie des copains (relâcher) : r = 280, au nord         │
             └──────────────────────────────────────────────────────────┘
```

| Élément | Construction | Position / dimensions |
|---|---|---|
| Plateau | Cylinder vertical, matériau Grass menthe (200, 240, 210) | Rayon 320, dessus à Y = 0 |
| Collines | 40 Balls aplaties pastel (rose, menthe, citron), tag `Float` lent pour quelques nuages | r 320-420, hauteur 10-40 ; murs invisibles à r = 322 |
| Place | Disque de pavés crème (255, 245, 220), bordure rose | r < 50 |
| MEGA pad | Cylinder rose clair Ø 30, épaisseur 0,6, anneau `Neon` qui s'allume à l'alerte | Centre de la place |
| Statue | Socle Marble Ø 10 × 3 ; le squishy est dessiné par le client à partir de l'attribut `Statue` (espèce, mutation, taille) | Nord de la place (0, 0, −38) |
| Boutique | Petite échoppe en Parts (toit rayé), comptoir avec invite « Vendre » et « Boutique » | Est de la place (38, 0, 0) |
| Autel de la Lune | Arche Marble + croissant `Neon`, compte à rebours du samedi (`SurfaceGui`) | Ouest de la place (−38, 0, 0) |
| Jarre de la jauge | Cylinder `Glass` Ø 8 × 12 qui se remplit (gelée `Neon` dont la hauteur suit la jauge) | Sud de la place (0, 0, 38) |
| Scène de Big Plop | Disque surélevé Ø 10 | Sud-est (27, 0, 27) |
| Fontaine dorée | Vasque Ø 8 (départ du Golden Wobbler) | Nord-est (20, 0, −20) |
| Tableaux des classements | 5 panneaux `SurfaceGui` en arc | Nord, r = 46 |
| Rues | Pavés roses (255, 230, 240) : anneau intérieur r = 95 (10 de large), grand boulevard r = 166 (12 de large), 8 rues radiales de r = 50 à r = 166 | ≈ 400 pièces |
| Quartiers | 24 maisons-bonbons non accessibles (corps Part + toit Wedge + 2 fenêtres `Neon`), sucettes, buissons-guimauves | Entre les rues |
| Lampadaires | Poteau Cylinder + Ball `Neon` (couleurs pastel) ; `PointLight` seulement un sur quatre (budget de la console la plus faible, §12.9) ; non solides | 64 le long des rues (16 lumières) |
| Prairie des copains | Champ de fleurs, panneau « Coucou ! » ; les 12 derniers squishies relâchés par le joueur y jouent (dessinés par son seul client) | r = 280, nord |

**Ce qui est solide (règle robuste).** Tous les objets du monde sont **ancrés** (`Anchored = true`) et en `CanTouch = false` : le jeu n'écoute jamais `Touched`. Sont **solides** seulement : le plateau (sol), les murs invisibles du bord, les maisons-bonbons (boîtes simples, `CollisionFidelity = Box`), les clôtures des ranchs et leur mur invisible de 12 studs (§6.3). **Tout le reste est non solide** (`CanCollide = false`, `CanQuery = false`) : lampadaires, sucettes, buissons, fleurs, décorations, dalles, Pot, Cuve, Bassin, bol, coussin, étagère, statue, échoppe, autel, jarre, scène, fontaines, panneaux, membranes des portails (côté serveur). Deux solides sont toujours séparés d'au moins 6 studs ou collés sans fente : aucun recoin où un personnage reste coincé. `WorldBuild.spec` vérifie ces règles sur la carte construite (§12.10).

**Graphe des rues** (`Shared/Logic/WorldLayout`, utilisé par `SeededPath`) : nœuds sur l'anneau de la place (r = 50, tous les 45°), sur l'anneau intérieur (r = 95, tous les 22,5°) et sur le boulevard (r = 166, tous les 11,25°, donc un nœud devant chaque portail) ; arêtes le long des rues. Les fuites, les Wild Wobblers et le Golden Wobbler ne quittent jamais ce graphe : ils n'entrent jamais dans un ranch.

### 11.2 Un ranch (repère local : X en travers de −32 à +32, Z du portail (0) vers le fond (72))

| Pièce | Construction | Position locale |
|---|---|---|
| Clôture | Poteaux sucre d'orge tous les 8 studs + lisses arrondies, hauteur 4, couleur du ranch ; doublée d'un mur invisible ancré de 12 studs de haut (§6.3) | Tout le tour |
| Portail de gelée | Membrane `Glass` (seule transparence permise avec la gelée Jelly) entre deux poteaux, 8 de large ; non solide pour le serveur, solide pour les autres joueurs sur leur propre client ; la règle est la poussée du serveur (§6.3) | Z = 0, X = 0 |
| Fontaine de Gelée | Vasque Ø 5 avec jet de gelée | Côté rue : Z = −6, X = +12 |
| Panneau du ranch | BillboardGui : nom (ou « Ranch 7 »), couronne R, Fame, « Jour 42 », badge rose « boop » (ranch boopable) ou bulle « bouclier » ; rien pour un ranch Cozy | Au-dessus du portail, Y = 14, distance max 150 |
| Enclos | Zone logique de 54 × 36 (4 rangées × 6 places), sol en tapis pastel | Z 8 à 44 |
| Pot à Pièces | Grosse marmite dorée (Cylinder + Ball), montant au-dessus | Z = 6, X = −20 |
| Tapis à Goûter | Grand tapis à motif biscuit sous les enclos ; il change de couleur et de motif à chaque niveau | Sous la zone des enclos |
| Cuve à Gelée | Cylinder `Glass` Ø 6 × 9 + couvercle + tuyau ; niveau de gelée `Neon` visible | Z = 52, X = −20 |
| Bassin de Fusion | Bassin Ø 12, eau pastel `Glass`, 5 (ou 6) places flottantes | Z = 52, X = +6 |
| Dalles d'achat | Disques `Neon` Ø 4 avec icône et prix (`SurfaceGui`) | Rangée Z = 62, X de −24 à +24 |
| Décorations | 18 emplacements fixes | Autour des enclos et du chemin |
| Bol du Meilleur Ami | Grand bol rose Ø 4 | Z = 58, X = +22 |
| Coussin du Meilleur Ami | Coussin rond Ø 4 | Z = 10, X = +22 |
| Étagère à trophées | 3 étagères de 9 places, petites statues dessinées par le client | Fond : Z = 70 |
| Point d'apparition | Une position de `WorldLayout` (aucune pièce) : le serveur y place le personnage à chaque apparition (§6.1) | Z = 30, X = 0, face au Pot |
| Silhouette | Le meilleur squishy (client) | Z = 36, Y = 40 |

Ranch k (k = 0…15) centré sur l'angle `22,5° × k + 11,25°`, portail à r = 178, orienté vers la place. Distance entre deux portails voisins : ≈ 69,8 studs.

### 11.3 Éclairage et palette

| Propriété | Valeur |
|---|---|
| `ClockTime` | 14,5 fixe (plein jour pastel) ; la nuit seulement pendant la Jelly Moon (0,0) |
| `Ambient` / `OutdoorAmbient` / `Brightness` | (150, 140, 170) / (190, 180, 210) / 2,5 |
| `Atmosphere` | Density 0,25, Color (255, 220, 240), Decay (170, 200, 255), Haze 1,2 |
| `BloomEffect` | Intensity 0,6, Size 20, Threshold 1,3 |
| `ColorCorrectionEffect` | Saturation 0,2, Contrast 0,05 |
| `Technology` | **ShadowMap** (réglage du projet) : choix délibéré pour la console la plus faible (PS4, Xbox One) ; les néons et le bloom gardent l'ambiance pastel. Future seulement si le profilage sur PS4 le permet un jour |

| Préréglage (tween de 2 à 4 s, client) | Changements |
|---|---|
| BOOP RUSH | `Tint` (255, 200, 225), Atmosphere Color (255, 190, 220) |
| Jelly Moon | `ClockTime` 0, `MoonAngularSize` 30, `StarCount` 4000, Tint (200, 190, 255), Atmosphere Color (150, 120, 220) |
| Wobble Party / Squish Party | Tint (255, 240, 210), Bloom 0,8 |
| Hiver « Frost & Sprinkles » (lancement) | Plaques de « sucre glace » (Parts blanches `Sand`), guirlandes de bonbons `Neon` sur les lampadaires, flocons de sucre (`ParticleEmitter` qui suit la caméra, 10 par seconde, budget §12.9) |

Matériaux : SmoothPlastic (squishies, maisons), `Neon` (accents, dalles, lampes), `Glass` (gelée, Cuve, Bassin, portails), Grass (sol), Marble (statue, autel), `Foil`, `Ice`, `ForceField` (mutations). Lisibilité sur une télé à 3 m : sol pastel peu saturé, créatures vives et contours nets ; aucune information importante portée seulement par un petit détail.

### 11.4 Budget de construction

Carte ≈ 4 300 pièces (plafond 4 500) : plateau, collines et murs ≈ 120 ; place ≈ 250 ; rues ≈ 400 ; quartiers ≈ 800 ; lampadaires ≈ 130 ; ranchs 16 × ≈ 160 (tout construit, 18 décorations) ≈ 2 560. Les squishies, les créatures en fuite, les statues et les effets sont **côté client** et ne comptent pas ici (§12.9). `StreamingEnabled` est coupé (§12.9) : toute la carte est présente sur chaque client dès la fin du chargement, rien de ce que le jeu utilise ne peut « ne pas être encore arrivé ».

---

## 12. Architecture technique

### 12.1 Principes

1. **Le serveur décide de tout.** Les clients n'envoient que des **intentions** (« je presse ce squishy », « je bondis ») ; le serveur vérifie chaque message (types, `NaN` et infini, bornes, appartenance, tailles des tables), le limite en débit, puis décide. Aucune valeur économique venant d'un client n'est acceptée.
2. **Les squishies sont des données.** Le serveur garde les profils et l'état public des ranchs ; les clients dessinent tout (squishies, créatures, effets) à partir de ces données. Rien de physique n'est répliqué pour les créatures.
3. **Calcul paresseux** : aucune boucle par seconde et par squishy. Taille et Pot se calculent à partir d'horodatages (§12.3).
4. **Une seule horloge** (`Shared/Util/Clock`, reprise de Comet) et des phases d'événements déterministes (`EventClock`) : serveur et clients calculent les mêmes horaires et les mêmes trajets de créatures.
5. **Contenu piloté par les données** : espèces, mutations, raretés, dalles, événements, objectifs, prix, sons sont des tables de `Shared/Config`.
6. **Réutiliser la base de Comet Conga**, durcie par 6 tours de QA : `DataService` (verrou de session, reprise du verrou, migrations, réplication par patchs), `MonetizationService` (reçus idempotents), `Net`/`Remotes`, `Validate`, `RateLimit`, `Trove`, `Signal`, `Clock`, `Hash`, `MoveCheck` (budget d'action), `Juice`, `Toast`, `Theme`, `Build`, `Prices`, `Analytics`, `Notify`, la couche console (§10.6) et le harnais de tests Lune (déjà présent dans `tests/harness`).
7. `--!strict` partout, API publiques typées, commentaires en français, identifiants en anglais. `task.wait/spawn/delay/defer` seulement. Compatible `SignalBehavior = Deferred`. **Cycle de vie** : joueurs déjà présents traités au branchement de `PlayerAdded` ; nettoyage complet à `PlayerRemoving` (`Trove` par joueur) ; personnages absents ou en réapparition toujours tolérés ; tout `WaitForChild` côté client a un délai.
8. Tout texte vu par le joueur passe par des clés de `Shared/Localization/Strings` (anglais **et** français). Tous les nombres viennent de `Shared/Config/*`.
9. **Robustesse avant tout (« zéro bug »)** :
   - aucune règle ne dépend de la physique : distances et zones calculées par le serveur sur la **position validée** (Pot, dalles, ranchs, clôtures, MEGA, bol, captures), jamais `Touched` ; décor ancré et non solide (§11.1) ; bond scripté et capture calculée sur sa géométrie (§4.12) ; aucun squishy n'est un objet physique ;
   - aucune règle ne dépend d'une animation : les délais (fusion 0,4 s, combo 0,6 s, Grand Splorch 3,2 s, maintiens) sont des **minuteurs du serveur** ; le client cale ses animations sur l'heure envoyée et ne renvoie jamais « animation finie » ;
   - **rien ne casse si un objet n'est pas encore arrivé** : `StreamingEnabled` coupé (§12.9), le client attend `game:IsLoaded()`, et les positions dont le jeu a besoin (ranchs, Pot, dalles, Bassin, bol, place, rues) viennent du module pur `WorldLayout`, pas d'une recherche dans le `workspace`. Les pièces du monde ne servent qu'à l'image ; tout `WaitForChild` a un délai et un repli ;
   - **chaque état a une sortie et un délai** (table du §12.10) : aucun état ne peut rester bloqué ;
   - **opérations idempotentes** : rejouer une intention, un reçu ou une sauvegarde ne crée jamais un deuxième effet ;
   - logique dans des **modules purs et déterministes** (`Shared/Logic`), testés hors de Roblox avec des propriétés et du hasard contrôlé.
10. **Zéro trace d'erreur** : en jeu, aucun `warn` ni aucune erreur n'est attendu. Les tests échouent dès qu'une erreur ou un avertissement imprévu apparaît (§12.10, couche h) ; en ligne, le module Diagnostics les compte et les montre aux administrateurs (§12.11).

### 12.2 Arbre Rojo et interrupteurs

```
src/
  first/            → ReplicatedFirst
    Loading.client.luau            écran de chargement en code (repris, adapté)
  shared/           → ReplicatedStorage.Shared
    Net.luau, Remotes.luau          (repris ; liste du §12.7)
    Types.luau
    Config/
      Balance.luau                  revenu, croissance, pression, dalles, Grand Splorch, hors ligne, plafonds
      Squishies.luau                26 espèces (lignes de données §5.1), familles et bonus
      Rarities.luau, Mutations.luau tables du §4.4 et du §4.5
      Vat.luau                      tables de qualité, niveau de la Cuve par R, protection contre la malchance, nouveauté garantie
      Events.luau                   horaires (§2.4), Rush, MEGA, Golden, Wild Wobblers, jauge, Lune
      Quests.luau                   objectifs du jour, paliers de Plop, jalons du Squishydex
      Cosmetics.luau                selles, traînées, tenues, titres, thèmes, palette des ranchs
      Monetization.luau             passes et produits, identifiants à 0 au départ
      Sounds.luau                   clés du §9.6, provenance sur chaque ligne
      Console.luau, Settings.luau   (repris)
      Features.luau                 interrupteurs (ci-dessous)
    Logic/                          modules PURS (aucun service Roblox), testés sous Lune
      Formulas.luau                 croissance, revenu, pression, coûts, objectifs, hors ligne, Pot (forme exacte §12.3)
      Odds.luau                     tirages de rareté, d'espèce, de mutation, protections, « 1 sur X »
      FusionRules.luau              jumeaux, fusion, chaîne de combo
      RushRules.luau                ordre de vérification d'un boop et d'une capture (§4.21.4), récompenses
      QuestRules.luau               objectifs faisables (« Proposé si »), tirage, remise à zéro en session
      MegaRules.luau                objectif, indulgence, paliers
      SizeScale.luau                échelle logarithmique et plafonds
      EventClock.luau               phases de chaque événement à l'instant t
      SeededPath.luau               trajets des créatures (graphe des rues, bonds)
      WorldLayout.luau              positions des ranchs, de la place, graphe des rues
      PressTiming.luau              phase du rebond, fenêtre PERFECT
      ZoneRules.luau                zones du ranch, entrée/sortie des dalles (2,5 / 3,5 studs), Pot, bol, MEGA
      LeapRules.luau                géométrie du bond, point d'atterrissage, capture à l'atterrissage
      StateTimeouts.luau            délai de sortie de chaque état (table du §12.10)
      DiagRules.luau                normalisation des messages d'erreur, clés, plafonds, nettoyage des noms
      Hash.luau                     (repris)
    Render/
      SquishyBuilder.luau           recettes de modèles (client)
    Localization/Strings.luau       EN + FR
    Util/                           (repris) Clock, Format (nombres géants §4.2), Signal, Tables, Trove, Validate
  server/           → ServerScriptService.Server
    Main.server.luau
    Data/Schema.luau, Data/Admins.luau
    Services/
      DataService, MonetizationService          (repris)
      WorldService          construit Wobbleton et les 16 ranchs
      RanchService          attribution, voisins, portails, poussée des intrus, état public des ranchs
      EconomyService        calcul paresseux, Pot, dalles, multiplicateurs, hors ligne, boosts
      SquishyService        collection : naissances, Cuve, enclos, Dodo, Lettres, vente, relâche, verrou, Meilleur Ami, monture, portage, Bassin et combos
      ChaseService          tick 10 Hz : créatures en fuite, Golden, Wild Wobblers (partagés et personnels), fuites du Rush, captures (dont capture à l'atterrissage d'un bond), contrôle de déplacement
      RushService           mode Rush/Cozy, carte du choix, clôtures, maintiens de boop, protections (paires, heure, « Pas ce joueur »)
      EventService          EventClock : Rush, MEGA, Golden, Lune, jauge, Wobble Party, file des spectacles, LiveOps
      SplorchService        Grand Splorch, spectacle, cadeaux, applaudissements, Étagère à trophées
      QuestService          accueil, Nourrir Plop, objectifs, carte « Plop a sommeil », Squishydex
      CommunityService      amis, pet-sitting, emotes, bannières, nom caché, liste de blocage (souple)
      ProductService        effets des passes et produits
      LeaderboardService    tableaux du serveur et OrderedDataStores de la semaine
      DiagnosticsService    erreurs du serveur et des clients : comptes, exemples, totaux du jour, panneau des administrateurs (§12.11)
    Util/ RateLimit, Analytics, Notify, MoveCheck   (repris)
  client/           → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau
    Util/ Platform, Haptics, Prefs, Prices          (repris)
    Controllers/
      StateController       miroir du profil (repris)
      WorldStateController  miroir des ranchs, des événements et des créatures
      RanchRenderer         squishies, niveaux de détail, BulkMoveTo, animations, silhouettes, statue
      ChaseRenderer         créatures en fuite, Golden, Wild Wobblers, fuites du Rush
      PromptController      cible choisie par le jeu (score, hystérésis, projection écran pour la souris), invites □ et ○, cycle L1/R1, visée du bond
      InputController       ContextActionService : action, prendre, bondir, monter, emotes, menu ; touches déliées dès qu'une fenêtre s'ouvre
      ErrorReporter         erreurs et avertissements du client (ScriptContext.Error, LogService.MessageOut) → ReportError, plafonné (§12.11)
      CameraController      travelling du Grand Splorch seulement (aucun cadrage automatique)
      VFXController, AudioController, LightingController, OnboardingController
    UI/
      Root, Theme, Create, Juice, Toast, Glyph       (repris ; Root passe à la référence 1920 × 1080)
      Prompt (invites du monde, §10.4), FocusGuard (focus jamais perdu, §10.6)
      HUD, Banners, ScreenFX, ReturnScreen, ModeCard, Cards (cartes en jeu et leur file, §10.3)
      Panels/ Ranch, Squishydex, Objectives, Leaderboards, Shop, Settings, SplorchPreview, OutfitPreview, Diagnostics
tests/specs/                        §12.10
tools/opencloud/                    lancement des tests serveur dans de vrais serveurs Roblox (§12.10, couche i)
```

**Interrupteurs de configuration** (`Shared/Config/Features.luau`, lus au démarrage et sur un message LiveOps d'administrateur, sans nouvelle version) :

| Clé | Lancement | Effet |
|---|---|---|
| `BoopRush` | `"on"` | `"on"` / `"events"` (Lune et Squish Parties d'administrateur seulement) / `"off"` (Wild Wobblers seuls aux heures du Rush) |
| `MegaSquish`, `GoldenWobbler`, `JellyMoon`, `ServerGauge` | `true` | Couper un événement en cas de problème en ligne |
| `Clips` | `true` | Captures vidéo automatiques |
| `Costumes` | `"winter2026"` | Costume de saison actif (calendrier dans `Events.Costumes`) |
| `JellyAscend`, `Season`, `SlowJelly`, `Duo`, `Parcels`, `WorldFirst`, `FameLineage`, `GreatJelly` | `false` | Fonctions de janvier et février (§17) ; le code de lancement n'en contient que les crochets |
| `RewardedAds` | `false` | Aucun code de publicité au lancement ; la clé existe pour qu'on ne l'ajoute jamais « par défaut » |
| `Diagnostics` | `true` | Remontée des erreurs et panneau des administrateurs (§12.11) ; `false` coupe seulement l'envoi des clients (les comptes du serveur restent) |

### 12.3 Ordre d'initialisation, tick et calcul paresseux

`Main.server.luau` : `DiagnosticsService` branché en tout premier (il doit voir les erreurs du démarrage), puis `Net.setup()`, puis `Init()` puis `Start()` dans cet ordre : DataService → MonetizationService → WorldService → RanchService → EconomyService → SquishyService → QuestService → CommunityService → EventService → RushService → SplorchService → ProductService → LeaderboardService → ChaseService (dernier : il porte le tick).

**Tick de `ChaseService`** (accumulateur sur `RunService.Heartbeat`, pas fixe de 0,1 s, 3 pas rattrapés au plus par image) :

```
1. now = Clock.now()
2. pour chaque joueur chargé avec personnage : MoveCheck.step(...) → position validée ? peut agir ?
3. RanchService.step : intrus repoussés ; Pot encaissé si le joueur est à ≤ 5 studs ; entrée sur une dalle (≤ 2,5 studs, sortie > 3,5) = un achat (positions validées, ZoneRules)
4. EventService.step(now) : transitions de phase (Rush, MEGA, Golden, Lune, Wobble Party, file des spectacles)
5. RushService.step(now) : clôtures (renouvellement toutes les 20 s), maintiens de boop terminés ou rompus
6. Créatures : apparitions dues (fuites personnelles, Wild, Golden), fins (25 s, 20 s, 30 s)
7. Captures : intentions `Catch` reçues depuis le tick précédent, vérifiées à la position SeededPath de maintenant
8. MEGA : pressions reçues agrégées, battement diffusé toutes les 0,25 s
9. Diffusion groupée : ChaseEvent, EventState, RanchPatch
10. Délais : tout état qui a dépassé son délai (StateTimeouts, §12.10) est fermé proprement, compté, et signalé à Diagnostics s'il n'aurait pas dû l'être
```

Chaque étape du tick est protégée : une erreur dans l'étape d'un joueur est attrapée (`pcall`), comptée par Diagnostics, et n'arrête ni les autres joueurs ni les étapes suivantes.

**Calcul paresseux** (module pur `Formulas`). Entre deux événements, la croissance `g` du ranch est constante, donc chaque taille est linéaire : `z(t) = z0 + g × (t − t0)`. Le revenu total `I(t)` est donc lui aussi linéaire : `I(t) = I0 + I' × (t − t0)`, avec `I' = Σ 0,02 × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B × g`. Le Pot est l'intégrale exacte :

```
pot(t) = pot0 + I0 × Δ + ½ × I' × Δ²      (Δ = t − t0)
```

Le serveur « règle » (`settle`) le ranch à chaque événement qui change `g`, `A`, `P` ou `B` (achat, naissance, fusion, vente, boost qui commence ou finit, ami qui arrive ou part, Grand Splorch), avant chaque sauvegarde, et toutes les 30 s (décalé selon le joueur). Le client prédit les tailles et le Pot avec les mêmes formules, corrigé à chaque patch.

### 12.4 Le temps : `Clock` et `EventClock`

`Shared/Util/Clock` (repris de Comet, testé) : `Clock.now()` (secondes UTC fractionnaires = `workspace:GetServerTimeNow()` + décalage ou gel), `Clock.unix()` (entier, pour les horodatages **sauvegardés**), `Clock.day()`, `Clock.week()` (lundi 00:00 UTC), `Clock.weekday()`, `Clock.secondOfDay()`, `Clock.untilNextDay()`, `Clock.untilNextWeek()` ; contrôle pour les tests : `Clock.freeze(t)`, `Clock.advance(dt)`, `Clock.unfreeze()`, `Clock.setOffset(s)`. Règle : durées de jeu et recharges en `Clock.now()` ; horodatages sauvegardés en `Clock.unix()`. **Aucun module ne lit `os.time()` ni `tick()` directement** : les tests font voyager le temps.

`Shared/Logic/EventClock` (nouveau, pur) :

```lua
EventClock.rush(t): { active: boolean, index: number, startsAt: number, endsAt: number, sirenAt: number }
EventClock.mega(t): { active: boolean, index: number, warnAt: number, landsAt: number, endsAt: number, moon: boolean }
EventClock.golden(t): { active: boolean, index: number, spawnAt: number, endsAt: number }
EventClock.moon(t): { active: boolean, session: number?, startsAt: number, endsAt: number }  -- samedi ×4, dimanche ×1
EventClock.nextEvent(t): { kind: string, at: number }        -- pour la pastille du HUD
EventClock.megaSpecies(t): number                            -- rotation §5.1
EventClock.seed(kind: string, index: number): number         -- graine des trajets (Hash)
```

Tests à des instants clés : minuit, :04:50, :05:00, :06:30, :19:45, :20:00, :21:05, samedi 15:59:59, 16:00, 16:20, 22:20, dimanche 16:00, changement de semaine.

### 12.5 Trajets des créatures et réplication

- **`SeededPath`** : `escape(seed, t0, startNode, awayAngle)` renvoie une fonction `pos(t)` : un premier bond de 20 studs dans la direction `awayAngle` (à l'opposé du boopeur), puis marche au hasard (graine) sur le graphe des rues, sans demi-tour immédiat, vitesse `v(t) = 16 − 0,32 × (t − t0)` studs/s (bornée à 8), bonds de 0,45 s (hauteur visuelle seulement). `hopAround(seed, t0, centre, rayon)` pour les créatures en fuite personnelles. Même code côté serveur et côté client : le serveur ne diffuse que la graine, l'instant de départ et le nœud de départ.
- **Capture** : le serveur compare la position validée du joueur (MoveCheck) à `pos(maintenant)` : distance ≤ 6,5 studs (5 + 1,5 de tolérance de latence ; 9,5 = 8 + 1,5 pour le propriétaire de sa fuite du Rush), écart vertical ≤ 8. Après un bond accordé, le serveur tente lui-même la capture à l'atterrissage (t + 0,35 s), au point calculé par `LeapRules` à partir de la géométrie du bond (§4.12), jamais à partir de la position que la physique a donnée.
- **`ChaseEvent`** (fiable, groupé à 4 Hz) : `spawn = { id (u16), kind (runaway | escape | wild | wildPersonal | golden | demo), species, mutation, size, ownerSlot?, booperSlot?, seed, t0, startNode, awayAngle, duration }` et `finish = { id, reason (caught | returned | expired), bySlot? }`. Les créatures personnelles (fuite, Wild Wobbler personnel, démonstration de Big Plop) ne sont envoyées qu'au client concerné.
- **État des ranchs** : `RanchSnapshot` à l'arrivée (16 ranchs, ≈ 15 Ko), puis `RanchPatch` groupé par image : par ranch `{ g, gAt, tiles, decor, R, fame, day, mode, hidden, name }` et par squishy `{ op = add | remove | update, uid, s, m, st, z, zAt, bf, o, at }`. Le client calcule `z(t) = z + g × (t − zAt)`. Aucun envoi par seconde.
- **Arrivée en cours de partie** : `RanchSnapshot` + `EventState` + créatures actives, une seule fois.
- **Messages perdus ou en retard** : chaque patch porte un numéro de suite par destinataire ; un trou dans la suite fait redemander un `RanchSnapshot` (`RequestWorld`). Une créature dont l'heure de fin est passée disparaît chez le client même si le message `finish` n'est pas arrivé. Le client ne reste jamais sur un état faux.

### 12.6 Données sauvegardées (schéma v1)

Magasin `PlayerData_v1`, clé `player_<UserId>`, gérés par le `DataService` repris de Comet Conga, avec ses règles durcies :

- **Verrou de session** posé au chargement (`UpdateAsync`), avec un jeton propre à ce chargement. Un verrou d'un autre serveur plus jeune que 30 min fait réessayer toutes les 5 s ; il n'est **repris** qu'après **5 lectures réussies** qui l'ont vu (au moins 25 s d'observation pendant que les DataStores répondent), **jamais parce que des erreurs ont épuisé les essais** (sinon renvoi poli « reviens dans un instant », rien d'écrit). Le serveur qui détient le verrou réessaie sa sauvegarde de départ en panne toutes les 15 s au plus pendant 5 min : un enfant qui revient sur un autre serveur après une panne retrouve ce qu'il a gagné (leçon `Fix_final_data_lock` de Comet).
- Chaque écriture refuse d'écraser un enregistrement verrouillé par un autre serveur ou de **schéma plus récent** (dans ce cas le joueur est renvoyé : « Ce serveur n'est pas à jour »).
- Attribut répliqué `ProfileLoading` pendant les essais (lu par l'écran de chargement).
- Jamais de profil par défaut sauvegardé par-dessus un échec de chargement ; en ligne, jamais de repli en mémoire si les DataStores sont indisponibles.
- Sauvegarde automatique toutes les 90 s, au départ, à la fermeture (`BindToClose`), et immédiate après un achat Robux (le reçu n'est acquitté qu'après une écriture réussie). `settle` est appelé avant chaque sauvegarde.

```lua
Schema.VERSION = 1
Schema.PRIVATE_KEYS = { receipts = true, flags = true }

function Schema.defaults()
  return {
    version = 1,
    -- économie (§4.1, §4.6, §4.8)
    coins = 0, pot = 0, lastSettle = 0, lastOnline = 0, R = 0,
    tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false },   -- la Cuve n'est pas ici : son niveau se calcule à partir de R (§4.9)
    boosts = { personalLeft = 0 },   -- secondes restantes du boost personnel (en pause pendant un boost de serveur ;
                                     -- +600 si l'acheteur d'une Squish Party part avant la fin, §8.3)
    coinBuy = { at = 0, amount = 0 },   -- dernier paquet de pièces (Clock.unix(), montant) : 2e confirmation du Grand Splorch
    -- collection (§4.3, §4.9, §4.14)
    squishies = {},   -- [uid] = { s = id d'espèce (1-26 au lancement), m = 0-9, st = 0-5, z = taille, zAt = Clock.now() du dernier règlement,
                      --           bf = 0-3, lk = bool, o = tenue ou "", at = "pen"|"pool"|"dodo"|"mail" }
    nextUid = 1,
    mount = "",       -- uid de la monture choisie ("" = la plus grosse, dès que la première selle est gagnée)
    vat = { fillAt = 0, pending = false, pityRare = 0, pityEpic = 0, newPulls = 3 },
    runaway = { nextAt = 0 },
    dex = {   -- tableaux denses, une case par espèce (0 par défaut), allongés par reconcile quand une espèce
              -- arrive : sans limite (une espèce par semaine) et sans trou (les DataStores refusent les tableaux à trous)
      mut = {},       -- mut[s] = masque : bit 0 = page de l'espèce tamponnée, bit m = mutation m trouvée (m = 1-9)
      stars = {},     -- stars[s] = masque de 5 bits : bit (k − 1) = badge ★k
      rewards = 0,    -- dernier jalon réclamé
    },
    released = {},    -- 12 derniers squishies relâchés { s, m } (Prairie des copains, §4.13)
    trophies = {},    -- trophies[s] = taille record (tableau dense, 0 par défaut)
    outfits = { owned = {}, worn = {} },   -- owned[id] = nombre ; worn[id] = uid
    -- social et rétention (§6, §7)
    fame = 0, plopDays = 0, lastFeedDay = 0,
    onboarding = { step = 0, done = false },
    objectives = { day = 0, list = {}, rerolls = 0, allClaimed = false },  -- list = { { id, p, done, claimed } × 3 }
    caps = { day = 0, rushBabies = 0, splorchGifts = 0, fameRush = 0, fameRelease = 0, petSit = 0, claps = 0, partyBuys = 0 },
    mode = { rush = false, chosen = false, changedAt = 0, cardShown = false, postBoopCardShown = false },
    golden = { lastWinAt = 0 },
    weekly = { week = 0, stamps = 0, combo = 0, catchScore = 0, helpful = 0, generous = 0,
               prev = { stamps = 0, combo = 0, catchScore = 0, helpful = 0, generous = 0 } },   -- semaine passée (§6.9)
    settings = { hideName = false, receiveGifts = true, clips = true, reducedMotion = false, lowGraphics = false,
                 music = true, sfx = true, vibration = true, lang = "auto", partyShowName = false,
                 emoteLeft = "bravo" },   -- emote de la croix ← : "bravo" | "bellyFlop" | "crown" (§6.5)
    stats = { presses = 0, perfects = 0, fusions = 0, bestCombo = 0, hatches = 0, catches = 0, boops = 0,
              booped = 0, heroCatches = 0, megas = 0, splorches = 0, playSeconds = 0, sessions = 0,
              firstBoopReceivedAt = 0, lastFriendDay = 0, biggestEver = 0 },
    -- réservé pour plus tard (§17) : valeurs neutres, jamais lues au lancement
    ascend = 0,                                                  -- Jelly Ascend
    season = { id = 0, xp = 0, premium = false, claimed = {} },  -- saison de 28 jours
    slowJelly = { slots = {} },                                  -- Gelée lente 1 / 4 / 12 h
    parcels = { inbox = {}, sentDay = 0, sent = 0 },             -- colis entre amis
    fameLineage = 0,                                             -- lignée de Fame (registre séparé)
    worldFirst = {},                                             -- trouvailles World First
    costumes = {},                                               -- costumes de saison obtenus
    -- privé
    passes = {}, receipts = {}, flags = { strikes = 0, lbBanUntil = 0 },
  }
end
```

- **Taille** : au plus 24 + 60 + 20 = 104 squishies × ≈ 70 octets ≈ 7 Ko ; profil complet < 20 Ko.
- **État de session, jamais sauvegardé** (mémoire du serveur) : paires boopeur → ranch et leur heure, fuites par ranch sur l'heure glissante, listes « Pas ce joueur », file des Grands Splorch, objectifs gardés jusqu'à la fin de la session.
- **Données lues = données à revalider** : au chargement, `reconcile` revérifie chaque champ (type, bornes, `NaN`, tableaux denses, uid existants, emplacements de Meilleur Ami uniques) et répare ce qui est faux avec une valeur sûre, en le comptant dans Diagnostics. Une vieille sauvegarde ou un bug passé ne peut donc jamais faire planter le chargement.
- **Règles** : `coins`, `pot`, `z` dans `[0 ; 1e300]`, jamais `NaN` ; uid = chaîne base 36 de `nextUid` (8 caractères au plus) ; invariants vérifiés en développement après chaque mutation (au plus 24 squishies `pen`/`pool`, 60 `dodo`, 20 `mail` ; un seul squishy par emplacement de Meilleur Ami ; tenue portée par un uid qui existe).
- **Migrations** : `Schema.migrate(data, from)`, étapes pures testées sur une sauvegarde-témoin (`tests/fixtures/profiles/v<n>.json`) ; on n'efface jamais un champ dans la version qui le remplace ; `reconcile` ajoute les champs nouveaux avec leur valeur par défaut. Les champs réservés ci-dessus évitent toute migration pour les fonctions de janvier.
- **Droit à l'effacement** : chaque `UpdateAsync` du profil renvoie `userIds = { UserId }` (procédure reprise de Comet).
- Les classements de la semaine vivent dans des `OrderedDataStore` séparés (§6.9) ; la lignée de Fame aura son propre registre (janvier).

### 12.7 Messages réseau (remotes)

Déclarés dans `Shared/Remotes.luau`, créés par `Net.setup()`. Chaque handler serveur suit l'ordre : **débit** (`RateLimit.allow`, seau à jetons par action, vidé au départ) → **types** (`Validate` : nombres finis, entiers, longueurs de chaînes, tables séquentielles bornées) → **existence** (clé de configuration, uid possédé) → **état** (profil chargé, personnage vivant, position validée, `MoveCheck.canAct`) → **règles métier** → mutation atomique → réplication. Un message refusé ne produit **aucune** mutation et au plus un `Feedback` neutre.

**Client → serveur (intentions)**

| Remote | Charge utile | Validation serveur | Débit max |
|---|---|---|---|
| `Press` | `uid: string, tClient: number` | uid possédé, dans un enclos ou le Bassin, à ≤ 10 studs (position validée), recharge de 8 s écoulée ; `tClient` fini, accepté s'il est dans [maintenant − 0,35 ; maintenant + 0,05] | 12 / s |
| `PickUp` | `uid: string` | Touche ○ / Q. Possédé, dans un enclos, à ≤ 10 studs, rien de porté, pas en monture, pas en attente de Grand Splorch | 4 / s |
| `PutDown` | — | Quelque chose est porté | 4 / s |
| `Throw` | — | Quelque chose est porté, à ≤ 12 studs du Bassin ; place ou jumeau disponible | 4 / s |
| `FuseMenu` | `uidA: string, uidB: string` | Différents, possédés, jumeaux, hors Lettres, pas en attente de Grand Splorch (verrouillés acceptés : choix du joueur) | 2 / s |
| `FuseAll` | — | Au moins une paire de jumeaux non verrouillés, hors Lettres ; le serveur fait toute la chaîne (§4.10) | 1 / 2 s |
| `BuyTile` | `tile: string` | `tile` ∈ {snack, decor, pens, cozyBed} ; niveau < maximum ; condition R ; règlement puis pièces ≥ prix. Position non exigée (achat possible depuis le panneau Ranch ou par □ sur la dalle). L'entrée sur une dalle, elle, est détectée par le serveur sans aucun message (§4.6) | 10 / s |
| `MoveSquishy` | `uid: string, to: string` | `to` ∈ {pen, dodo} ; place libre ; pas porté, pas en fuite | 4 / s |
| `ClaimMail` | `uid: string` | Dans la Boîte aux lettres ; place libre | 4 / s |
| `Sell` / `Release` | `uids: {string}, confirmed: boolean` | Table séquentielle de 1 à 84 chaînes uniques (enclos + Dodo, pour « Ranger »), possédées, ni Meilleur Ami, ni verrouillées, ni en fuite, ni en attente de Grand Splorch ; `confirmed = true` exigé s'il y a un Épique+ ou une mutation Doré+ (2e étape faite par le client, §4.13) | 2 / s |
| `SetLock` | `uid: string, locked: boolean` | Possédé | 6 / s |
| `SetBestFriend` | `uid: string, slot: number` | Entier 1 à 3, emplacement débloqué (R), possédé | 2 / s |
| `SetMount` | `uid: string` | Possédé, dans un enclos ; selle gagnée (record ≥ 1 200, §4.12) | 2 / s |
| `Ride` | `on: boolean` | Une monture existe ; rien de porté | 2 / s |
| `Leap` | `dirX: number, dirZ: number` | Finis, norme entre 0,5 et 1,5 ; recharge de 4 s écoulée ; pas en portage → MoveCheck accorde +12 studs pendant 0,35 s ; point d'atterrissage calculé par `LeapRules` ; capture tentée par le serveur à t + 0,35 s | 3 / s |
| `Catch` | `id: number` | Entier ; créature active ; attrapable par ce joueur (personnelle, mode Rush pour une fuite du Rush, pas le boopeur pendant les 6 premières secondes, recharge du Golden) ; distance ≤ 6,5 à `pos(maintenant)` (9,5 pour le propriétaire de la fuite) ; `canAct` | 6 / s |
| `BoopHold` | `ownerId: number, uid: string, holding: boolean` | Entiers et chaîne bornés ; ordre `RushRules` (§4.21.4) au début et à chaque tick (distance ≤ 8, propriétaire toujours en mode Rush, pas de « Pas ce joueur ») ; le serveur termine le boop lui-même à 2,5 s ou 5 s | 4 / s |
| `MegaPress` | `tClient: number` | MEGA actif, à ≤ 20 studs du centre, recharge de 0,4 s | 3 / s |
| `FeedPlop` | `holding: boolean` | À ≤ 8 studs du bol, pas encore nourri aujourd'hui ; 5 s mesurées par le serveur | 2 / s |
| `GrandSplorch` | `film: boolean, flyer: string` | Plus gros ≥ objectif ; dans son ranch ; rien de porté ; `flyer` possédé, dans un enclos ; maintien de 1,5 s mesuré côté client (geste). Vérifié **une seule fois**, à l'entrée dans la file : ensuite garanti (§4.15) | 1 / 2 s |
| `ClaimObjective` / `RerollObjective` | `slot: number` | Entier 1 à 3 ; terminé et non réclamé / relance disponible et non terminé | 4 / s |
| `ClaimDexReward` | — | Jalon atteint et non réclamé | 2 / s |
| `SetMode` | `rush: boolean` | Vers Cozy : immédiat, sans recharge (clôture vidée, fuites en cours rentrées, boop impossible jusqu'à la fin du Rush). Vers Rush : recharge de 60 s, appliqué à la fin du Rush en cours ; serveur privé sans autorisation : refusé | 1 / s |
| `RefuseBooper` | `userId: number` | Entier ; ce joueur a boopé l'envoyeur pendant cette session (« Pas ce joueur », §4.21.4) | 2 / s |
| `SetSetting` | `key: string, value: boolean \| string` | Clé dans la liste du §10.3 ; type attendu ; `lang` ∈ {auto, en, fr} ; `emoteLeft` ∈ {bravo, bellyFlop, crown} et débloquée ; `allowRush` : propriétaire du serveur privé | 4 / s |
| `EquipOutfit` | `outfit: string, uid: string?` | Tenue possédée (nombre > portées) ; uid possédé ou `nil` (retirer) | 2 / s |
| `Emote` | `kind: number` | Entier 1 à 3 (l'emote de la croix ← est lue dans les réglages du joueur) | client 1 / 1,5 s ; serveur 1 / 1,2 s |
| `Clap` | `heroId: number` | Fenêtre d'applaudissement ouverte pour ce héros ; pas déjà applaudi | 2 / s |
| `ReportBlocked` | `userIds: {number}` | Table séquentielle de 0 à 200 entiers positifs | 1 / 10 s |
| `SetInputType` | `kind: number, tenFoot: boolean` | Entier 1 à 3 (1 manette, 2 clavier-souris, 3 tactile inattendu) ; booléen (console) — **analytique seulement**, ne donne aucun avantage | 1 / 5 s |
| `ReportError` | `kind: number, key: string, message: string, trace: string, ctx: string` | Diagnostics (§12.11). `kind` entier 1 (erreur) ou 2 (avertissement) ; chaînes UTF-8 valides de 64 / 300 / 600 / 120 caractères au plus (tronquées au-delà) ; nettoyées une 2e fois par le serveur (noms des joueurs remplacés) ; 30 par joueur et par session au plus, 1 par clé et par minute ; ne change jamais rien au jeu | client 1 / 2 s ; serveur 1 / 2 s |
| `RequestDiagnostics` | `tab: number` | Entier 1 à 3 ; l'envoyeur est dans la liste des administrateurs (`Data/Admins.luau`), sinon le message est ignoré sans réponse | 1 / 2 s |
| `RequestSnapshot` / `RequestWorld` | — | — | 1 / 2 s |

Aucun `RemoteFunction` ne va du serveur vers le client. Les achats Robux passent par `MarketplaceService:Prompt…Purchase` côté client et `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur, sans remote du jeu.

**Serveur → client**

| Remote | Charge utile | Destinataires |
|---|---|---|
| `DataSnapshot`, `DataPatch` | Profil public, patchs groupés par image (repris) | Le joueur |
| `RanchSnapshot`, `RanchPatch` | §12.5 | Tous |
| `ChaseEvent` | §12.5 | Tous, ou un seul pour les créatures personnelles |
| `EventState` | `{ rush, mega, golden, moon, gauge, boost, spectacleQueue }` | Tous, à chaque changement |
| `MegaBeat` | `{ points, target, presses }` | Tous, 4 Hz pendant le MEGA |
| `Fence` | `{ ranchSlot, uids }` (squishies à la clôture) | Tous, pendant le Rush et le pet-sitting |
| `BoopState` | `{ booperSlot, ownerSlot, uid, endsAt }` (maintien en cours) | Tous |
| `Banner` | `{ kind, args }` | Tous |
| `Feedback` | `{ key, vars, tone }` | Le joueur |
| `Celebrate` | `{ kind, data }` (naissance, fusion, combo, capture, Grand Splorch, palier, objectif) | Le joueur (et tous pour le Grand Splorch) |
| `EmoteShow` | `{ userId, kind }` | Tous |
| `ClapPrompt` | `{ heroId, endsAt }` | Tous sauf le héros |
| `ModePrompt` | — (carte du choix Rush / Cozy : envoyée une fois après 15:00 de jeu ; le client l'affiche au calme, §4.21.1) | Le joueur |
| `DiagnosticsSnapshot` | `{ server, clients, samples, today }` (20 Ko au plus, §12.11) | L'administrateur qui l'a demandé |

### 12.8 Anti-triche

| Menace | Parade |
|---|---|
| Vitesse, téléportation, bond sans recharge | **`MoveCheck` repris de Comet avec son budget d'action** : un « seau » de studs dont le plafond est la règle d'un tick (`vmax × dt × 1,5 + 4`), rempli à `vmax × 1,5` studs/s ; chaque position acceptée retire sa distance ; la dette passe d'un message à l'autre. Tant que la dette n'est pas remboursée, le joueur **ne peut pas agir** (attraper, booper, presser, encaisser le Pot, presser le MEGA). `vmax` = WalkSpeed serveur maximal des 0,5 dernières secondes (16, ou 22,4 en monture) ; un bond accordé par le serveur ajoute 12 studs sur 0,35 s. Une infraction **signale seulement** ; 3 en 5 s → retour à la dernière position valide (`PivotTo`), 3 s sans action, icône neutre « connexion instable » (jamais d'accusation). Gel réseau honnête jusqu'à 1,5 s toléré. Exemptions 3 s après une apparition ou un `PivotTo` du serveur |
| Vol, passe-muraille | Altitude > sol + 14 (+ la hausse de la monture, 4,3 à 6 studs, §4.12) pendant plus de 1,5 s, hors du plateau (r > 322) ou sous le sol → retour à la dernière position valide (règles de hauteur de Comet) |
| Bond truqué | La direction est bornée (norme 0,5-1,5) ; la longueur est fixée par le serveur (12 studs, raccourcie par les solides) ; la capture se calcule sur le point d'atterrissage du serveur, jamais sur une position envoyée |
| Entrer dans un ranch | Poussée hors du ranch à chaque tick (§6.3) ; position validée seulement |
| Debout sur un autre joueur | **Aucune collision entre personnages** (groupe de collision `Characters` qui ne se touche pas lui-même) : personne ne porte personne, personne ne bloque un portail (leçon du tour 5 de Comet) |
| Valeurs envoyées par le client | Aucune valeur économique acceptée. `tClient` des pressions borné à 0,35 s dans le passé (§4.7) ; comme un script peut alors viser le PERFECT à chaque fois, aucun classement ne compte les PERFECT (§6.9). Le type d'entrée et l'appareil sont seulement analytiques (aucun bonus selon l'appareil, leçon de Comet) |
| Rafales de remotes | Seau à jetons par action (§12.7) |
| Fermes de bébés (comptes complices) | Plafonds journaliers, taille ≤ 2 × le plus gros du receveur, 1 boop par paire toutes les 30 min, recharge de 20 s, 2 fuites par ranch et par Rush, 4 par heure ; bébés des Grands Splorch plafonnés à Peu commun pour une espèce Épique+ (§4.15) |
| Robots qui pressent | Rien à gagner hors de son propre ranch ; débit borné ; récompenses en secondes de revenu (un robot ne crée pas de valeur infinie) |
| Classements | Exclusion après 10 retours forcés en 10 min, **jusqu'à la fin de la semaine suivante** (`flags.lbBanUntil`), jamais à vie (question laissée ouverte par Comet, tranchée ici) |
| Lecture de secrets | Administrateurs LiveOps et réglages anti-triche dans `ServerScriptService` seulement |
| Achats | `ProcessReceipt` unique et idempotent ; passes vérifiés à l'arrivée et à l'achat, vérifications bornées en débit (repris) |
| Faux rapports d'erreur (Diagnostics) | Plafonds par joueur et par clé, tailles bornées, noms nettoyés ; un rapport ne change jamais rien au jeu et n'est lu que par les administrateurs ; un joueur qui dépasse ses plafonds est simplement ignoré jusqu'à la fin de la session (§12.11) |
| Duplication | Aucun échange au lancement ; toutes les mutations de collection se font sur le profil d'un seul joueur, sous verrou de session. Un bébé est une **création** du serveur, jamais un déplacement entre profils |

### 12.9 Budgets de performance (console la plus faible : PS4 et Xbox One)

Appareil de référence : **PS4 et Xbox One de base**, les consoles les plus faibles où Roblox tourne. Les mesures se font sur une vraie console : Studio ne mesure ni le processeur ni la mémoire d'une console. La PS5, les Xbox Series et les PC visent 60 images par seconde.

| Ressource | Budget |
|---|---|
| Images par seconde | **30 stables** sur PS4 et Xbox One avec 16 joueurs, 384 squishies affichables et un Rush complet ; 60 sur PS5, Xbox Series et PC |
| Pièces de la carte | ≤ 4 500 (prévu ≈ 4 300), toutes ancrées |
| Instances côté client | ≤ 15 000 dans le `workspace` (carte, squishies, effets) ; ≤ 3 000 objets d'interface |
| Pièces de squishies rendues | ≤ 2 500 ; ≤ 80 squishies en détail complet (12 pièces) et animés à pleine cadence (40 en qualité réduite) ; le reste en 3 ou 1 pièce |
| Mise à jour des squishies | Un `workspace:BulkMoveTo(..., Enum.BulkMoveMode.FireCFrameChanged)` par image ; 15 Hz entre 60 et 140 studs ; immobiles au-delà |
| `Highlight` | **≤ 12** sur un client (la limite d'affichage du moteur est 255, d'après la documentation officielle, mais chaque contour coûte cher sur une vieille console) : cible 1, fuites du Rush les plus proches ≤ 6, Mythiques et Secrets les plus proches ≤ 3, Golden 1, réserve 1. Les autres fuites gardent leur anneau et leur traînée |
| Lumières actives | ≤ 24 : 16 lampadaires (un sur quatre), ranch local 4, Légendaires+ les plus proches ≤ 4 |
| Particules à l'écran | ≤ 200 (≤ 60 en qualité réduite) ; émetteurs réutilisés ; flocons d'hiver compris |
| Transparence | Seulement la gelée Jelly, les portails, le Bassin et la Cuve : les surfaces transparentes superposées coûtent cher aux vieux processeurs graphiques |
| Créatures | ≤ 10 fuites du Rush + ≤ 13 Wild Wobblers partagés + 1 Golden + 1 créature personnelle par joueur (vue par lui seul) ; + 12 squishies de la Prairie des copains (client local, détail réduit) |
| Serveur | Tick de 10 Hz < 3 ms en moyenne avec 16 joueurs ; aucune autre boucle par image |
| Réseau entrant par client | ≤ 8 Ko/s en moyenne ; pic < 40 Ko/s (arrivée) |
| Mémoire client | < 900 Mo (console développeur), plafond prudent pour la PS4 |
| Connexions (`RBXScriptConnection`) | Nombre stable après 5 min de jeu (± 5 % sur une heure) : chaque connexion appartient à un `Trove` qui la coupe |
| DataStores | Sauvegarde automatique 90 s ; écritures des classements groupées par minute ; Diagnostics 1 écriture par serveur toutes les 5 min |

**Qualité adaptative** (client, nouveau). Roblox ne dit pas si la console est une PS4 ou une PS5. Le client mesure donc la durée moyenne de ses images : au-delà de **36 ms pendant 10 s**, il passe en **qualité réduite** (distances de détail × 0,6, 40 squishies animés, particules × 0,3, lumières au-delà de 60 studs coupées, `Highlight` seulement sur la cible et les fuites, pas de flou `BlurEffect` derrière les panneaux). Il ne remonte qu'après **60 s sous 25 ms**, et change au plus une fois par minute : pas de va-et-vient visible. Le réglage Graphismes légers force la qualité réduite.

**StreamingEnabled : coupé, délibérément** (`Workspace.StreamingEnabled = false`). La carte est petite (≤ 4 500 pièces simples) : la garder entière sur chaque client coûte peu de mémoire et supprime toute une famille de bugs (un ranch, une dalle ou une rue « pas encore arrivés », des `WaitForChild` qui attendent pour rien, un modèle qui disparaît en s'éloignant). Les squishies et les créatures sont dessinés par le client à partir des données (§12.5) et ne dépendent pas du streaming. On ne le rallume que si la carte dépasse 8 000 pièces ou si la mémoire de la PS4 l'exige, et alors avec tout ce que le jeu utilise en `ModelStreamingMode = Persistent`. Rien ne dépend des personnages des autres joueurs (positions des créatures et des événements calculées par `SeededPath` et `EventClock`).

### 12.10 Stratégie qualité : « zéro bug »

Le propriétaire a vu en direct des bugs de Comet Conga que nos 1 600 tests hors ligne n'avaient pas vus. Pour Raise a Squishy, la barre est **« aucun bug au lancement »**. Cette partie dit ce que cela veut dire pour le joueur et comment on le prouve. Le détail (harnais, fichiers, commandes) est dans le document d'architecture (`docs/04`).

**Ce que « zéro bug » veut dire pour le joueur**
- **Jamais bloqué** : chaque état a une sortie et un délai ; ○ revient toujours en arrière ; la sélection n'est jamais perdue ni piégée ; le chargement ne tourne jamais à l'infini.
- **Jamais lésé** : aucune pièce, aucun squishy, aucun achat perdu ; aucun double crédit ; une panne de sauvegarde ne fait rien perdre.
- **Ce qu'on voit est vrai** : une capture accordée correspond à l'image ; aucun chiffre faux (`NaN`, négatif, « inf ») ; aucune créature fantôme ou en double.
- **Rien de cassé à l'écran** : aucun texte coupé ou trop petit, aucun chevauchement, rien hors de la zone sûre, rien qui clignote ou disparaît, aux 3 résolutions et dans les 2 langues.
- **Aucune erreur en coulisses** : zéro erreur et zéro avertissement, en test comme en ligne (Diagnostics, §12.11).

**États et délais** (module pur `StateTimeouts`) : chaque état est fermé proprement à son délai, même si un message manque ou si un joueur part.

| État | Délai de sortie | Sortie |
|---|---|---|
| Chargement du profil | 60 s d'écran (essais du DataService compris) | Écran d'échec avec Réessayer ; jamais de profil vide sauvegardé |
| Attente du verrou d'un autre serveur | 5 lectures réussies (≥ 25 s), ou essais épuisés | Reprise du verrou, ou renvoi poli « reviens dans un instant » (§12.6) |
| Placement du personnage | `HumanoidRootPart` attendu 10 s | Nouvel essai à la prochaine apparition, repli sur la place (§6.1) |
| Portage d'un squishy | Mort, réapparition, sortie du ranch, fenêtre ouverte, monture, départ | Le squishy retourne à sa place (§4.10) |
| Maintien de boop / du bol | 2,5 ou 5 s + 0,5 s / 5 s + 0,5 s | Effet, ou annulation |
| Bond | 0,35 s | Fin du bond (capture tentée une seule fois) |
| Créature en fuite / fuite du Rush / Wild Wobbler / Golden / démonstration | 20 / 25 / 25 / 30 / 20 s | Retour, éclatement ou disparition, même chez un client qui a raté le message de fin |
| BOOP RUSH / MEGA SQUISH | 90 s (+ 25 s pour les fuites en cours) / 65 s | Fin de phase par `EventClock` |
| File des Grands Splorch | Son tour (110 s au plus) ; départ du joueur | Spectacle, ou place rendue sans rien remettre à zéro (§4.15) |
| Spectacle (Grand Splorch, danse de Big Plop) | 7,5 s / 8 s, coupure dure à 10 s | Fin du spectacle, file suivante |
| Squish Party / Wobble Party / boost personnel | 10 min / 5 min / son minuteur | Fin du boost |
| Carte du choix Rush / Cozy | 20 s | Cozy |
| Cartes non bloquantes | 8 s | Rangées dans la pastille « ! » |
| Fenêtre d'achat ou d'invitation de Roblox | 60 s de sélection tenue | Sélection rendue de force (§10.6) |
| Étape de l'accueil | 90 s | Consigne rangée, l'accueil continue (§3) |
| Cible fixée par un clic | 4 s | Retour au choix automatique |
| Fenêtre d'applaudissement | 8 s | Puce retirée |

**Les 10 couches de tests** (toutes lancées par `./scripts/check.sh`, sauf la couche i, qui attend la clé de l'API Open Cloud) :

| Couche | Ce qui est prouvé | Où |
|---|---|---|
| **a. Modules purs : cas exacts et propriétés** | Chaque module de `Shared/Logic` et `Util/Format` : les valeurs exactes de ce GDD **et** des propriétés vérifiées sur des milliers d'entrées tirées au hasard avec une graine fixe : jamais `NaN` ni négatif, monotonie, tables qui somment à 100 %, nombre de squishies conservé par une fusion (2 → 1), chemins jamais hors du graphe ni dans un ranch, même résultat côté client et côté serveur. Une entrée bizarre (`NaN`, ±inf, 1e308, −0) donne un résultat sûr, jamais une erreur | `Format`, `SizeScale`, `Formulas`, `Odds`, `FusionRules`, `RushRules`, `QuestRules`, `MegaRules`, `EventClock`, `SeededPath`, `PressTiming`, `ZoneRules`, `LeapRules`, `StateTimeouts`, `DiagRules` (`*.spec` et `Props_*.spec`) |
| **b. Chaque remote attaqué** | Chaque message du §12.7 reçoit des charges hostiles : mauvais types, `nil`, `NaN`, ±inf, nombres énormes, chaînes de 100 000 caractères, UTF-8 invalide, tables profondes, mixtes ou à trous, uid d'un autre joueur, rafales de 1 000 messages par seconde. Attendu : **aucune mutation, aucune erreur**, au plus un `Feedback` neutre, et des seaux à jetons qui coupent au bon débit | `Remotes.spec`, `RateLimit.spec` |
| **c. 16 robots, longue durée** | Un serveur complet avec 16 robots qui jouent (pressent, achètent, fusionnent, boopent, poursuivent, partent, reviennent, meurent, changent de mode) pendant **6 h de temps simulé** (horloge accélérée). À **chaque tick**, des invariants : aucune monnaie négative ou `NaN` ; chaque squishy existe une fois, à un seul endroit, chez un seul propriétaire ; aucun état plus vieux que son délai ; plafonds respectés ; instances et connexions stables après la mise en route (± 5 %) ; tick dans son budget ; **aucune erreur ni aucun avertissement**. Plus le démarrage et la fermeture (`BindToClose`) à 16 joueurs | `Soak.spec`, `Boot.spec` |
| **d. Client complet, profil console, 3 résolutions** | Une partie serveur enregistrée est rejouée dans le vrai client, profil console (`IsTenFootInterface` vrai, manette), en **1920 × 1080, 3840 × 2160 et 1280 × 720**, en anglais puis en français. Un robot parcourt tous les écrans avec **la croix, ✕ et ○ seulement** (depuis le jeu, croix ↓ ouvre le menu) : chaque écran du §10.3 est atteint ; ○ revient toujours au niveau précédent, puis au jeu ; la sélection n'est jamais vide dans une fenêtre, jamais hors de la fenêtre active, jamais posée en jeu. À chaque étape : aucun chevauchement, aucun texte coupé ni sous 28 px TV, rien hors de la zone sûre, aucune touche du jeu active derrière une fenêtre, glyphes PlayStation partout (aucune lettre « X » ou « LB »). Même parcours au clavier-souris | `ClientReplay.spec`, `Console_*.spec`, `Layout.spec` |
| **e. Données en désordre** | Pannes de DataStore injectées (erreurs, délais de 10 s, quotas), verrou de session entre 2 et 3 serveurs simulés, retour immédiat sur un autre serveur, fermeture avec 16 joueurs et un magasin lent, migrations depuis les sauvegardes-témoins, profils abîmés (`NaN`, champs manquants, tableaux à trous, uid inconnus) réparés par `reconcile`, reçu rejoué, achat pendant une panne (accordé seulement après une sauvegarde réussie) | `DataChaos.spec`, `DataService.spec`, `MonetizationService.spec`, `Schema.spec` |
| **f. Rythme de l'économie** | Simulation du §4.24 : 200 joueurs × 28 jours, **porte bloquante** | `EconomyPacing.spec` |
| **g. Contre-audit anti-triche** (« red team ») | Un fichier par menace, écrit comme une attaque : capture téléportée ou de loin, capture de sa propre fuite avant 6 s, capture d'une créature personnelle d'un autre, bond sans recharge ou de direction `NaN` ; boop à travers le mur, de loin, de son propre squishy, d'un Meilleur Ami, contournement de « Pas ce joueur » et des paires ; entrée dans un ranch (monture, saut, bond, téléportation, rester dans le portail) ; reçu rejoué, achat avant le chargement du profil ou pendant un Grand Splorch ; pressions chez un autre, `tClient` truqué ; deux messages contraires dans la même image (vendre pendant une fusion) | `RedTeam_Chase.spec`, `RedTeam_Boop.spec`, `RedTeam_Fence.spec`, `RedTeam_Purchase.spec`, `RedTeam_Press.spec`, `MoveCheck.spec` |
| **h. Règle « zéro trace »** | Le harnais écoute `warn`, `error`, `ScriptContext.Error` et `LogService.MessageOut` pendant **chaque** spec : toute erreur ou tout avertissement imprévu la fait échouer. Un avertissement attendu doit être déclaré dans la spec (`expectWarning(motif)`), et la spec échoue s'il n'arrive pas | `tests/harness` (toutes les specs) |
| **i. Vrai moteur Roblox** (prêt, lancé plus tard) | `tools/opencloud/` : un script Lune construit la place avec Rojo, la publie comme nouvelle version d'une **place de test privée** (API Open Cloud *Place Publishing*), lance la suite des tests serveur **dans de vrais serveurs Roblox** par l'API Open Cloud *Luau Execution* (`luau-execution-session-tasks`), récupère les journaux et échoue si un test échoue ou si une erreur ou un avertissement apparaît. Il tournera dès que le propriétaire fournira une clé d'API et l'accès réseau. Plus les listes de tests manuels dans Studio et sur une vraie PS5 (§18) | `tools/opencloud/run-server-tests.luau`, §18 |
| **j. Diagnostics en ligne** | Ce qui échappe à tout cela est compté en ligne et montré aux administrateurs (§12.11). Chaque erreur vue en ligne devient d'abord un test qui la reproduit, puis une correction | `DiagnosticsService`, `Diagnostics.spec` |

S'ajoutent les specs de services sur un serveur simulé (`Economy`, `Squishy`, `Splorch`, `Quest`, `Rush`, `Chase`, `Mega`), `WorldBuild.spec` (carte construite : tout ancré, `CanTouch = false`, solides seulement dans la liste du §11.1, aucune fente entre solides, budget de pièces) et `Contract.spec` (parité EN/FR, provenance de chaque son, identifiants de monétisation à 0 = articles cachés). Les outils repris de Comet restent (`harness/Wire` pour les règles des messages réseau, `ApiAudit` pour les API Roblox).

**Règle d'équipe** : on ne supprime ni n'affaiblit jamais un test pour le faire passer. Un bug trouvé (en test, dans Studio ou en ligne) devient d'abord un test qui échoue.

### 12.11 Diagnostics (erreurs en ligne et panneau des administrateurs)

But : voir les bugs que les tests n'ont pas vus, sur de vrais serveurs, de vraies consoles et de vrais PC, et permettre au propriétaire de les **photographier** pour nous les envoyer.

**Ce qui est relevé**
- **Serveur** : `ScriptContext.Error` (message, pile d'appels, script) et `LogService.MessageOut` (erreurs et avertissements), les erreurs attrapées par nos `pcall` dans le tick et les handlers (§12.3), les états fermés par leur délai alors qu'ils n'auraient pas dû l'être (§12.10), et les réparations faites par `reconcile` (§12.6).
- **Clients** (`ErrorReporter`) : `ScriptContext.Error` et `LogService.MessageOut` du client, les sauvetages du focus (`FocusRescued`, §10.6) et les `WaitForChild` arrivés à leur délai. Chaque rapport porte un petit contexte : appareil (console ou PC), type d'entrée, résolution, langue, version de la place, étape de l'accueil, fenêtre ouverte, événement en cours.

**Nettoyage et limites** (sécurité des enfants, anti-abus)
- Le texte est **normalisé** par `DiagRules` : chiffres remplacés par « # », chemins `Players.<nom>` et noms d'affichage remplacés par « <joueur> » (par le client, puis encore par le serveur avec le nom et le nom d'affichage de l'envoyeur), longueurs bornées (message 300, pile 600, contexte 120 caractères). La **clé** d'une erreur est le hachage du texte normalisé et du script.
- Client : 1 rapport par clé et par minute, 30 par session au plus. Serveur : les mêmes plafonds par joueur ; au-delà, ignoré sans réponse. 200 clés différentes au plus par serveur, puis un compteur « autres ».
- Aucune donnée personnelle gardée : ni identifiant, ni nom ; seulement l'appareil, la version et le contexte ci-dessus. Rien n'est montré aux joueurs.

**Ce que garde le serveur** : par clé, le nombre d'occurrences (serveur et clients), le nombre de joueurs touchés, l'heure de la première et de la dernière, et **3 exemples** complets (texte, pile, contexte). Toutes les 5 min, il ajoute ses comptes du jour à une clé partagée (`Diagnostics_<jour>` dans un DataStore à part, `UpdateAsync`, les 50 clés les plus fréquentes, < 4 Ko) pour avoir les totaux de tous les serveurs, et envoie un résumé à l'analytique (`ServerError`, `ClientError`, une fois par clé et par 5 min).

**Panneau Diagnostics** (administrateurs seulement : UserIds de `Data/Admins.luau`, vérifiés par le serveur à chaque demande ; l'entrée n'existe même pas dans les Réglages des autres joueurs)
- Onglet **Ce serveur** : version de la place, heure UTC, durée de vie du serveur, joueurs, temps moyen et maximal du tick, mémoire du serveur, puis les erreurs et avertissements triés par nombre (clé courte, texte, nombre, joueurs touchés, dernière fois). ✕ sur une ligne ouvre ses 3 exemples.
- Onglet **Mon client** : images par seconde, temps d'image, mémoire, ping, nombre d'instances et de connexions, qualité (normale ou réduite), et les erreurs de ce client.
- Onglet **Aujourd'hui** : totaux de tous les serveurs depuis 00:00 UTC.
- Lecture seule, texte de 32 px TV, contraste fort, heure et version en haut de chaque onglet : fait pour être photographié (sur PS5, bouton Create ; sur PC, capture d'écran) et envoyé à l'équipe. Navigation à la croix, ✕ et ○, comme partout.
- Mise à jour à la demande (`RequestDiagnostics`, 1 toutes les 2 s) ; `DiagnosticsSnapshot` de 20 Ko au plus.
- Les libellés du panneau passent par les clés EN/FR comme tout le reste ; les messages d'erreur sont montrés tels qu'ils sont écrits par le moteur (en anglais, déjà nettoyés).

**Tests** : `Diagnostics.spec` vérifie le nettoyage des noms, les plafonds, la fusion des clés, le silence pour un non-administrateur, la taille du paquet et l'écriture groupée dans le DataStore.

### 12.12 Budget de lignes et ligne de coupe

| Bloc | Estimation |
|---|---|
| Base reprise de Comet (données, monétisation, réseau, utilitaires, console, UI de base) | ≈ 4 000 lignes (à adapter) |
| Shared (logique et configuration, dont `ZoneRules`, `LeapRules`, `StateTimeouts`, `DiagRules`) | ≈ 2 800 |
| Serveur (15 services, dont `DiagnosticsService`) | ≈ 4 900 |
| Client (rendu, contrôleurs, HUD télé, panneaux, `Prompt`, `FocusGuard`, `ErrorReporter`) | ≈ 5 100 |
| **Total jeu au premier passage** | **≈ 12 800 nouvelles lignes** (hors base reprise et hors tests ; prévoir beaucoup plus après la QA) |
| Tests et outils (10 couches du §12.10 : propriétés, attaques des remotes, robots de longue durée, parcours console, données en désordre, red team, Open Cloud) | ≈ 9 000 lignes en plus (le harnais de Comet est repris) |

Le retrait du téléphone économise environ 1 200 lignes d'interface tactile (bouton Action, Prendre, Bondir, Monter, Emote, désignation au doigt, colonnes du petit écran) et un jeu entier de tests : ce temps passe dans les tests du §12.10.

**Ligne de coupe** (retirée dans cet ordre si le calendrier dérape) : aperçu 3D des tenues (remplacé par une image fixe dessinée en Frames), animation de la carte du choix (remplacée par 3 images fixes), classements mondiaux (on garde le tableau du serveur), badges d'étoiles du Squishydex, applaudissements, pet-sitting, clips automatiques, fanfares de records, squishies visibles dans la Prairie des copains (relâcher seulement par le menu). **Jamais coupé** : grandir, presser et PERFECT, Cuve, Bassin et combos, créatures en fuite et Golden, monture, BOOP RUSH avec ses protections, son interrupteur et le mode Cozy immédiat, Wild Wobblers (dont le personnel), MEGA SQUISH, jauge, Grand Splorch et Étagère, Jelly Moon, Nourrir Plop, objectifs, mode Cozy, couche console (disposition télé, glyphes, règle des 3 touches, `FocusGuard`, vibrations, sons d'interface), délais de tous les états, Diagnostics, et les 10 couches de tests. **Si quelque chose doit céder, c'est le contenu, jamais la qualité** : on coupe une fonction de la liste ci-dessus plutôt que de publier un bug connu.

---

## 13. Sécurité des enfants

| Règle | Comment |
|---|---|
| **Mode Rush ou Cozy, choisi par chaque joueur** | Cozy tant qu'on n'a pas choisi ; carte au calme dès 15:00 de jeu, avec animation, Cozy si pas de réponse en 20 s ; seuls deux joueurs en mode Rush peuvent se booper ; passer en Cozy est immédiat, à tout moment (§4.21.1) |
| **Serveurs privés en Cozy par défaut** | Le propriétaire peut autoriser le Rush (§6.10) |
| **On n'entre jamais chez les autres** | Clôture solide, portail de gelée, poussée du serveur à chaque tick (§6.3). Le Rush se joue par-dessus la clôture et en ville |
| **Le propriétaire gagne toujours** | Fame, pièces, taille en plus ; l'original revient toujours et l'attrapeur ne le touche jamais : il reçoit une bulle-bébé (§4.21.3) |
| **Rien n'est jamais perdu** | Pas de vol, pas de base pillable, Grand Splorch qui donne au lieu de prendre, Étagère à trophées, jours de Plop au total (jamais une série qui retombe) |
| **Protections du Rush** | Meilleur Ami jamais boopable (le premier Plop l'est d'office), 2 fuites par ranch et par Rush et 4 par heure, une même paire au plus toutes les 30 min, 1 boop toutes les 20 s, propriétaire proche = 2 fois plus long, bouclier débutant de 15 min, Mythiques seulement pendant la Lune, bouton « Pas ce joueur » (§4.21.4) |
| **Cacher mon nom** | Bannières, classements, statue et panneau du ranch montrent « Squishy Fan #4821 » (§6.9) ; le nom de l'acheteur d'une Squish Party n'est montré que s'il le choisit |
| **Aucun texte libre** | Pas de nom de squishy à écrire, pas de champ de texte (pas de codes au lancement), pas de dépendance au chat ; fenêtre de chat coupée sur console ; 3 emotes illustrées sur la croix |
| **Joueurs bloqués** | Règle souple : pas de boop entre deux joueurs dont l'un a bloqué l'autre (liste lue côté client). La règle fiable, côté serveur, est « Pas ce joueur » |
| **Rien de rare ne part par erreur** | Verrou automatique (Légendaire+, Galaxie+), confirmation en 2 étapes pour vendre ou relâcher un Épique+ ou un Doré+, maintien pour chaque relâche, aperçu avant « Ranger » (§4.13) |
| **Ton** | Mignon, satisfaisant ; la Jelly Moon est « un peu étrange » (troisième œil mignon, gouttes, lueur), jamais effrayante ; aucune violence (un boop est une pichenette sur le nez, l'éternuement est un nuage pastel brillant, jamais de morve) ; pas de sang, pas de peur, pas de moquerie (aucun badge « cozy » public) ; un Grand Splorch montre toujours le squishy qui revient |
| **Classification visée : Minimal** | Questionnaire de maturité rempli avant le lancement et avant d'activer la console (§18) ; catalogues Roblox Kids et Select visés |
| **Argent** | Aucun hasard payant, aucune chance achetable (même avec des pièces), aucune pub vidéo récompensée, aucun faux minuteur, aucune proposition d'achat dans les 10 premières minutes, prix clairs, `PolicyService` respecté, des pièces payées qui ne disparaissent jamais par surprise (§8.1) |
| **Pas de piège de conception** | Aucun chiffre (part en mode Rush, ventes) ne justifie de changer le choix par défaut, l'ordre ou la taille des boutons d'un choix (§16.4) |
| **Pause** | Carte « Plop a sommeil » après 60 min, sans pénalité ni récompense pour rester (§4.20) |
| **Partage** | Clips seulement si `IsContentSharingAllowed` ; le jeu ne partage jamais tout seul (§9.5) |
| **Mesure** | Départs dans les 2 min après un premier boop subi, comparés aux autres joueurs, dès le premier jour (§16.3, action au §16.4) |
| **Diagnostics sans données personnelles** | Les rapports d'erreur ne gardent ni nom ni identifiant (noms remplacés par « <joueur> »), sont plafonnés, ne changent rien au jeu et ne sont visibles que des administrateurs (§12.11) |
| **Un jeu qui ne casse pas** | Un enfant ne reste jamais bloqué (délai sur chaque état, ○ qui revient toujours en arrière), ne perd jamais un squishy ou un achat à cause d'un bug (sauvegarde sûre, opérations idempotentes), et ne voit jamais un écran d'erreur (§12.10) |

---

## 14. Accessibilité

| Besoin | Réponse |
|---|---|
| Daltonisme | Rareté = couleur **et** forme de l'aura (§4.4) ; mutation = matériau **et** nom ; squishies en fuite = anneau **et** contour ; ranch boopable = badge « boop » (couleur **et** icône) ; jumeaux = cœur (forme) |
| Sensibilité au mouvement | Mouvement réduit (§9.1) ; la caméra ne bouge jamais toute seule ; jamais plus de 3 changements de couleur par seconde (Glitch) ; aucun flash répété |
| Lecture difficile, jeunes enfants | Aucun tutoriel écrit ; icônes, gestes de Big Plop, 4 mots au plus par consigne ; un bouton d'action principal ; aperçu du Grand Splorch en 3 tuiles |
| Jeu sans son | Tout retour est d'abord visuel ; musique et effets réglables séparément |
| Motricité | **Aucun appui simultané**, aucun clic de stick, aucune combinaison : chaque action tient sur une touche (§10.4) ; maintiens limités au boop (2,5 s), au bol (5 s) et à la confirmation du Grand Splorch (1,5 s) ; **aucun geste précis obligatoire** (le PERFECT est un bonus, jamais un échec) ; fusion au menu sans glisser-déposer et « Tout fusionner » ; un seul bouton pour attraper (bond avec capture à l'atterrissage) ; PERFECT décalé pour le retard des télés ; la cible est choisie par le jeu (pas besoin de viser) ; tout le menu se pilote avec la croix, ✕ et ○ |
| Stress de la compétition | Mode Cozy (par défaut, immédiat, aussi rentable), serveurs privés en Cozy, bouclier débutant, « Pas ce joueur », Golden « course amicale », classements qui montrent d'abord ma place sur le serveur |
| Appareils modestes | Graphismes légers, qualité adaptative, niveaux de détail, budgets du §12.9 (PS4 et Xbox One) |
| Téléviseur et manette | Disposition télé unique, proportionnelle (référence 1920 × 1080), textes ≥ 28 px TV (32 pour le texte courant), contraste fort, zone sûre de 5 %, glyphes de l'appareil, tout à la manette sans curseur, focus toujours visible et jamais perdu, vibrations modérées et désactivables, sons d'interface, pas de fenêtre de chat (§10) |

---

## 15. Localisation (anglais et français)

- **Détection** : `Localization.languageFor(player.LocaleId)` (module repris) : `fr-*` → français, sinon anglais. Le réglage « Langue » (Auto / English / Français) passe avant.
- **Toutes les chaînes** dans `Shared/Localization/Strings.luau`, clés `domaine.nom`, variables `{n}`. Anglais **et** français écrits à la main ; un test vérifie la parité des clés et des variables (`Contract.spec`). Les autres langues : affichage anglais avec `AutoLocalize = true` (traduction automatique de Roblox) ; l'interface très illustrée limite la dépendance au texte.
- **Consignes et glyphes** : une consigne ne cite jamais une touche dans une phrase ; le glyphe est posé **à côté** d'un mot court (□ + « Presser »), ce qui marche dans les deux langues et sur toutes les manettes.
- **Nombres** : §4.2 (suffixes et séparateurs propres à chaque langue).
- **Longueur** : le français est ≈ 25 % plus long. Chaque texte a `TextScaled` + `UITextSizeConstraint` ; chaque écran est vérifié en français et en anglais en 1280 × 720, 1920 × 1080 et 3840 × 2160 sans passer sous 28 px TV (§12.10, couche d ; leçon de Comet : prévoir des libellés français courts dès le départ).

| EN | FR |
|---|---|
| Raise a Squishy, Wobbleton, Big Plop, Plop, noms d'espèces, BOOP RUSH, MEGA SQUISH, Grand Splorch, Squishydex, Jelly Moon, Golden Wobbler, Wild Wobbler, Wobble Party, Squish Party, Fame | identiques (noms propres) |
| Coins / Press / SPLORCH! / PERFECT! | Pièces / Presser / SPLORCH ! / PERFECT ! |
| Snack Mat / Jelly Vat / Fusion Pool / Coin Pot / Jelly Fountain | Tapis à Goûter / Cuve à Gelée / Bassin de Fusion / Pot à Pièces / Fontaine de Gelée |
| Pens / Dodo Box / Mailbox / Trophy Shelf | Enclos / Boîte à dodo / Boîte aux lettres / Étagère à trophées |
| Pick up / Throw / Put down / Catch / Leap / Ride / Boop | Prendre / Lancer / Poser / Attraper / Bondir / Monter / Booper |
| Best Friend / Mount / Saddle / Outfit | Meilleur Ami / Monture / Selle / Tenue |
| Rush mode / Cozy mode / Newcomer shield | Mode Rush / Mode Cozy / Bouclier débutant |
| Server meter / Daily goals / Feed Plop / Day 42 | Jauge du serveur / Objectifs du jour / Nourris Plop / Jour 42 |
| Achoo! / HERO! / So close! | Atchoum ! / HÉROS ! / Presque ! |
| Not this player / Merge all / Tidy up / Buddy Meadow | Pas ce joueur / Tout fusionner / Ranger / Prairie des copains |
| Menu / Buy / Clap! / Walk / Choose | Menu / Acheter / Applaudir ! / Marcher / Choisir |
| Common / Uncommon / Rare / Epic / Legendary / Mythic / Secret | Commun / Peu commun / Rare / Épique / Légendaire / Mythique / Secret |
| Jelly / Neon / Frosted / Golden / Galaxy / Rainbow / Lunar / Glitch / Flop | Gelée / Néon / Givré / Doré / Galaxie / Arc-en-ciel / Lunaire / Glitch / Flop |

---

## 16. Analytics

Tout passe par `Server/Util/Analytics` (repris, appels protégés par `pcall`). Trois champs personnalisés pour segmenter : `device` (console manette / PC manette / PC clavier-souris ; tactile inattendu compté à part), `serverBand` (1-5, 6-10, 11-16 joueurs), `sessionBand` (1re session, 2-5, 6 et plus).

### 16.1 Entonnoir d'accueil (`LogOnboardingFunnelStepEvent`)

| Étape | Nom | Déclencheur |
|---|---|---|
| 1 | Loaded | Profil chargé, personnage dans son ranch |
| 2 | FirstPress | Première pression |
| 3 | FirstTile | Premier achat (Tapis à Goûter) |
| 4 | VatBuilt | Jumeau de Plop né |
| 5 | FirstFusion | Première fusion |
| 6 | FirstPot | Premier encaissement du Pot |
| 7 | FirstCatch | Première créature attrapée |
| 8 | FirstPull | Premier vrai tirage de la Cuve |
| 9 | FirstRide | Première balade (selle) |
| 10 | Objectives | Panneau des objectifs du jour vu (≈ 5:00) |
| 11 | FirstSplorch | Premier Grand Splorch |

### 16.2 Économie (`LogEconomyEvent`)

| Flux | Monnaie | `itemSku` | Type de transaction |
|---|---|---|---|
| Source | Coins | `Pot` (cumulé, un événement par tranche de 5 min), `Press`, `Combo`, `Sell`, `Offline`, `Golden`, `Mega`, `RushHero`, `RushReturn`, `RushNear`, `SplorchGift`, `PetSit`, `Clap`, `Objective_<id>`, `Product_<clé>` | Gameplay, TimedReward, Onboarding, IAP |
| Puits | Coins | `Tile_<dalle>_<niveau>`, `CozyBed` | Shop |

### 16.3 Événements personnalisés (`LogCustomEvent`)

| Événement | Valeur | Question |
|---|---|---|
| `RushModeChosen` | 1 Rush / 0 Cozy / −1 sans réponse | Observation seulement, jamais un objectif (§16.4) |
| `ModeAtSessionEnd` | 1 Rush / 0 Cozy | Comparer le retour J1 des joueurs Rush et Cozy : le Rush est-il un plaisir ? |
| `CozyAfterBoop` | 1 si le joueur passe en Cozy dans les 2 min après un boop subi | Le boop fait-il fuir vers le Cozy ? |
| `RefuseBooper` | 1 par « Pas ce joueur » | Y a-t-il du harcèlement ciblé ? |
| `FirstBoopReceived` | Secondes de jeu cumulé | Quand le premier boop arrive-t-il ? |
| `PostBoopQuit` | Secondes entre le premier boop subi et le départ (si < 120) | **Indicateur de frustration n° 1** |
| `QuitBaseline` | 1 par départ d'un joueur qui n'a pas été boopé dans les 2 dernières min (même tranche de temps de jeu) | Référence pour comparer `PostBoopQuit` |
| `BoopDone`, `EscapeOutcome` | 1 ; 0 propriétaire / 1 autre / 2 personne | Équilibre de la poursuite (cible : propriétaire ≥ 25 %, personne ≤ 20 %) |
| `RushCatchByInput` | 1 par capture, segmenté par `device` | La manette est-elle désavantagée face à la souris ? |
| `MegaResult` | 1 réussite / 0 échec, avec N | Calibrage de l'objectif |
| `GaugeFilled` | Minutes depuis la dernière fois | Calibrage de la jauge |
| `SplorchReached` | R et minutes depuis le précédent | Rythme réel contre §4.24 |
| `ComboLength` | n, et 1 si « Tout fusionner » | Les combos sont-ils compris ? |
| `ObjectivesAllDone` | Minutes de session au 3e objectif terminé | Les objectifs sont-ils faisables ? |
| `SplorchCoinsLost` | Pièces perdues au Grand Splorch, en minutes de revenu ; 1 si un paquet avait été acheté dans les 30 min | Des pièces payées se perdent-elles ? |
| `HatchRarity`, `MutationGot` | Rareté ; mutation | Tables réelles contre affichées |
| `RideStart` | Secondes de jeu | La monture est-elle trouvée ? |
| `PetSitPress`, `FriendsOnServer` | 1 ; nombre d'amis | Jeu entre amis |
| `ShopOpened`, `ShopHiddenByPolicy` | 1 | Effet de `PolicyService` |
| `MoveViolation` | Nombre d'infractions dans la session | Faux positifs de l'anti-triche |
| `ServerFullKick` | 1 | Taille du serveur mal réglée ? |
| `SleepyCardShown` | 60 ou 120 | Sessions très longues |
| `SessionLength` | Minutes (au départ) | Durée de session |
| `ServerError`, `ClientError` | Nombre par clé d'erreur (une fois par clé et par 5 min, §12.11) | Y a-t-il des bugs en ligne ? |
| `FocusRescued` | 1 par sélection rendue par `FocusGuard` (§10.6), avec l'écran | La navigation à la manette a-t-elle un trou ? |
| `StateTimedOut` | 1 par état fermé par son délai alors qu'il aurait dû finir seul, avec le nom de l'état | Un flux reste-t-il bloqué ? |
| `QualityReduced` | 1 quand la qualité adaptative descend, avec l'appareil | La console la plus faible tient-elle le budget ? |
| `TouchDeviceJoined` | 1 | Un appareil tactile arrive-t-il malgré les réglages ? |

### 16.4 Seuils d'alerte et actions (par la configuration, sans nouvelle version)

| Signal | Seuil | Action |
|---|---|---|
| `PostBoopQuit` comparé à `QuitBaseline` | > 1,5 fois après une semaine de mesures (seuil à confirmer avec ces mesures) | Premier boop subi seulement après 30 min de jeu (bouclier allongé), puis si besoin `Features.BoopRush = "events"`. Le Grand Splorch porte alors le côté viral. Plan B : les mécaniques de Stack a Squishy (jury §9) |
| Part en mode Rush | — | **Aucune action** : chiffre observé seulement. Règle écrite : on ne change jamais le choix par défaut, l'ordre ni la taille des boutons pour le faire monter |
| Retour J1 des joueurs Rush comparé aux Cozy | < 0,8 fois | Revoir la poursuite et les protections (rayon, vitesse, plafonds), jamais la carte du choix |
| `EscapeOutcome` | propriétaire < 25 % ou personne > 20 % | Verrou du boopeur 6 → 8 s ; rayon du propriétaire 8 → 9 ; durée de fuite 25 → 22 s |
| `ObjectivesAllDone` | < 85 % des sessions de 30 min finissent les 3 | Retirer ou assouplir l'objectif le moins fini (règle « Proposé si ») |
| Réussite du MEGA | < 65 % ou > 92 % | Coefficient 50 par joueur ± 10 |
| Médiane du premier Grand Splorch | hors 12-16 min | `Balance.Splorch.Targets[1]` |
| Perte entre les étapes 2 et 3 de l'accueil | > 10 % | Raccourcir le chemin vers le Tapis, renforcer le geste de Big Plop |
| Écart de captures manette / clavier-souris | > 25 % | Rayon de capture 5 → 6 studs pour **tous** (jamais un bonus déclaré par le client) |
| Sessions avec au moins une erreur (`ServerError`, `ClientError`) | > 0,5 % | Correctif sous 48 h ; la clé d'erreur devient d'abord un test qui échoue (§12.10) |
| `FocusRescued` ou `StateTimedOut` | > 0,1 % des sessions pour un même écran ou un même état | Correctif ; test ajouté à la couche d ou c |
| `QualityReduced` chez les joueurs console | > 30 % des sessions | Baisser les budgets du §12.9 (particules, squishies animés, lumières) |
| `MoveViolation` chez des joueurs honnêtes | > 1 % des sessions | Marge de `MoveCheck` 1,5 → 1,8 |

---

## 17. Lancement et « Plus tard »

### 17.1 Au lancement (samedi 12 décembre 2026, costume d'hiver)

- **Monde** : Wobbleton, 16 ranchs, construits en code ; costume « Frost & Sprinkles ».
- **Boucle** : grandir, presser + PERFECT et séries, Pot, dalles, Cuve à Gelée (tables, protections, nouveauté garantie), Bassin de Fusion et combos, créatures en fuite personnelles et Golden Wobbler, monture et bond.
- **Social et événements** : BOOP RUSH (mode Rush/Cozy, interrupteur, « Pas ce joueur »), Wild Wobblers (partagés et personnels), bouclier débutant, démonstration de Big Plop, MEGA SQUISH, jauge du serveur et Wobble Party, Grand Splorch et ses cadeaux, applaudissements, Étagère à trophées, Jelly Moon (4 séances le samedi, rattrapage le dimanche), Flop Plop, ranchs voisins, bonus d'amis, pet-sitting, emotes, 5 classements de la semaine, nom caché.
- **Rétention** : Nourrir Plop (jours au total), objectifs du jour faisables, Squishydex et bonus de famille, carte « Plop a sommeil », écran de retour.
- **Monétisation** : 4 passes et 3 familles de produits du §8, sans publicité, PolicyService.
- **Appareils** : PS5, PS4, Xbox Series, Xbox One et PC (types d'appareils Ordinateur + Console). Pas de téléphone ni de tablette.
- **Technique** : schéma v1 avec champs réservés, disposition télé unique et couche console (glyphes, `FocusGuard`, vibrations, sons d'interface), anti-triche, analytics, Diagnostics et panneau des administrateurs, qualité adaptative, EN/FR, Mouvement réduit, Graphismes légers.

### 17.2 Plus tard (janvier et février 2027) : liste courte et crochets à laisser dès le lancement

| Quand | Fonction | Crochets que le code de lancement doit laisser |
|---|---|---|
| Janvier | **Jelly Ascend** (2e prestige après 10 Grands Splorch) | Champ `ascend = 0` ; interrupteur `Features.JellyAscend = false` ; l'aperçu du Grand Splorch a une ligne réservée (cachée) |
| Janvier | **Saison de 28 jours** et sa piste premium décorative (≈ 399 R$) | Champ `season` ; `Features.Season = false` ; clé `SeasonPass` à 0 dans `Monetization` (cachée) |
| Janvier | **Lignée de Fame complète** et son tableau | Champ `fameLineage` ; `Features.FameLineage = false` ; au lancement, Fame créditée seulement si le propriétaire est présent (§4.18) |
| Janvier | **Gelée lente** (fournées de 1, 4 ou 12 h, hors ligne, meilleures raretés, jamais accélérée contre de l'argent) | Champ `slowJelly` (horodatages `Clock.unix()`) ; `Features.SlowJelly = false` ; un emplacement de dalle réservé à côté de la Cuve |
| Janvier | **Espèces Duo et colis** entre amis | Champ `duo` dans chaque ligne d'espèce ; champ `parcels` ; `Features.Duo` et `Features.Parcels = false` ; aucun échange au lancement |
| Janvier | **World First et énigme du lundi** | Champ `recipe` dans chaque ligne d'espèce ; champ `worldFirst` ; `Features.WorldFirst = false` ; sujet `MessagingService` « WorldFirst » réservé |
| Janvier | **Costume galette des rois** (squishy « fève » caché) | Calendrier `Events.Costumes` (dates) ; `Features.Costumes` |
| Février | **Grande Gelée entre serveurs** (risque technique) | `Features.GreatJelly = false` ; rien d'autre au lancement |
| Février | **Semaines « Encore »** (retour d'espèces limitées) | Champs `limitedUntil` et `encore` dans les lignes d'espèces |
| Février | Costumes Saint-Valentin et printemps | Calendrier `Events.Costumes` |
| Chaque semaine après le lancement | Une nouvelle espèce | Champ `release` des lignes d'espèces (activation par la date) |
| Pas avant février, et seulement sur décision du propriétaire | Ouverture aux téléphones et tablettes | Rien au lancement (décision du 1er novembre 2026). Il faudrait une disposition tactile, ses commandes et tout un jeu de tests ; les tailles relatives et la cible choisie par le jeu facilitent ce travail le jour venu |

---

## 18. Checklist de lancement

**Portes de qualité (bloquantes)** — les couches du §12.10
1. `./scripts/check.sh` vert : StyLua, Selene (0 erreur), toutes les specs Lune (couches a à h et j), **dont `EconomyPacing`** (§4.24), build Rojo, vérification de la place.
2. Couche c : `Soak.spec` (16 robots, 6 h de temps simulé, invariants à chaque tick) et `Boot.spec` verts, **sans aucune erreur ni aucun avertissement**.
3. Couche d : `ClientReplay.spec` et `Console_*.spec` verts en 1920 × 1080, 3840 × 2160 et 1280 × 720, en anglais et en français : chaque écran atteint avec la croix, ✕ et ○ ; ○ revient toujours ; aucun focus perdu ou piégé ; aucun chevauchement, aucun texte coupé ou sous 28 px TV ; rien hors de la zone sûre ; glyphes PlayStation.
4. Couche e : échec de chargement (rien n'est sauvegardé), arrêt du serveur (`BindToClose` sauvegarde tout), retour sur un autre serveur après une panne (rien de perdu), rejeu de `ProcessReceipt` (aucun double crédit), profils abîmés réparés.
5. Couche g : specs `RedTeam_*` vertes, plus un contre-audit indépendant (« red team ») sur le Rush, les captures, les bonds, le MEGA, les portails des ranchs et les achats.
6. Couche h : aucune spec ne laisse passer une erreur ou un avertissement imprévu.
7. Couche i : dès que la clé de l'API Open Cloud est fournie, la suite des tests serveur est verte **dans de vrais serveurs Roblox**, sans erreur ni avertissement dans les journaux. Si la clé n'est pas là le 10 décembre, les tests manuels ci-dessous la remplacent et le manque est écrit dans le rapport qualité.
8. Tests manuels M1 à M18 tous réussis, dont **une vraie PS5** et **une PS4 ou une Xbox One**.
9. **Aucun bug connu ouvert**, ou chaque bug restant accepté par écrit par le propriétaire.

**Tests manuels dans Studio, en ligne et sur console** (environ deux journées, plus le test à 16). Pendant chaque test : la fenêtre *Output* de Studio ou le panneau Diagnostics (§12.11) reste à zéro erreur.

| # | Test | Résultat attendu |
|---|---|---|
| M1 | Première session seul, 5 min, **à la manette seulement**, sans rien lire d'autre que le jeu ; puis deux fois avec un Rush forcé à 0:30 et un MEGA forcé à 1:30 | Pression à 10 s, Tapis vers 0:20-0:25, fusion à 1:00, capture à 2:00, monture vers 4:30 ; jamais deux consignes à la fois ; chaque consigne montre le bon glyphe ; Rush et MEGA restent discrets ; Presser et Prendre jamais confondus ; aucune étape bloquée |
| M2 | Rendu sur une vraie télé : tour de la ville et des ranchs, un Rush, un MEGA, une Jelly Moon (horloge avancée), Graphismes légers | Pastel lisible à 3 m, raretés reconnaissables par la couleur **et** la forme, rien qui clignote |
| M3 | Physique : portails (propriétaire et intrus), mur invisible des clôtures, bords du plateau, monture (taille fixée par la selle), bond contre une maison, chute | L'intrus rebondit, personne n'entre ni n'enjambe la clôture, même en monture ; personne ne reste coincé dans le décor ; retour sur le plateau après une chute ; réapparition toujours dans son ranch |
| M4 | Vraies sauvegardes : jouer, quitter, revenir, changer de serveur aussitôt, arrêter les serveurs | Rien de perdu, jamais de retour en arrière |
| M5 | Achats : chaque pass et produit (essais gratuits), puis un vrai petit achat en privé, **dont un sur PS5** | Effet reçu une fois ; pass gardé après un Grand Splorch ; Squish Party pour tout le serveur ; nom caché par défaut ; après la fenêtre d'achat PlayStation, la sélection revient sur le bouton Acheter |
| M6 | **16 vrais joueurs** pendant 30 min, dont **une PS4 ou une Xbox One** et une PS5 | ≥ 30 images/s en permanence sur la PS4 ou la Xbox One (la qualité adaptative peut descendre), 60 sur la PS5, mémoire < 900 Mo, aucune erreur dans Diagnostics |
| M7 | Textes en français et en anglais en 1280 × 720, 1920 × 1080 et 4K (émulateur de Studio, puis une vraie télé 4K) | Rien de coupé ni sous 28 px TV ; aucun chevauchement ; nombres au format de la langue |
| M8 | Particules : Grand Splorch, MEGA, naissance Secret, flocons d'hiver | Beaux, lisibles, budget tenu |
| M9 | **Manette seule pendant 30 min sur une vraie PS5**, sans jamais toucher un clavier | Chaque écran atteint avec la croix, ✕ et ○ (et croix ↓ pour le menu) ; ○ revient toujours ; la sélection n'est jamais perdue ni bloquée ; aucune carte ne vole la manette ; marteler □ presse toujours un squishy prêt ; L3 et R3 enfoncés par erreur ne font rien |
| M10 | Poursuite avec 250 ms de latence simulée | Les captures accordées correspondent à ce que voit le joueur (≤ 6,5 studs) ; un bond qui atterrit sur la créature l'attrape |
| M11 | **Vraie PS5 à 3 m** (télés de 43 et 55 pouces, mode Jeu coupé puis activé), puis une Xbox | Tout lisible, rien de coupé, zone sûre respectée ; vibrations modérées et au bon moment ; invites □ / ○ claires ; PERFECT réussi à peu près aussi souvent qu'au PC ; glyphes PlayStation sur PS5 et Xbox sur Xbox |
| M12 | **Écouter chaque son** (d'abord ceux remplis en dernier), dont les sons d'interface | Agréables, pas trop forts, `Sneeze` drôle et doux ; un son qui déplaît est vidé (jeu jouable en silence) |
| M13 | Session de 60 min à plusieurs | Aucune erreur dans Diagnostics, pas de ralentissement, mémoire stable, carte « Plop a sommeil » à 60 min |
| M14 | Un enfant de 8-10 ans accompagné, **à la manette devant la télé**, joue un Rush en mode Rush puis en mode Cozy, puis fait un Grand Splorch | Il comprend le choix, rit pendant la poursuite, ne se sent pas volé, retrouve seul le bouton « Mode Cozy » après un boop, lit les textes depuis le canapé, ne se perd pas dans les menus, et voit son squishy revenir après le Grand Splorch |
| M15 | Rush à 6 joueurs : un boopeur, un propriétaire loin de sa clôture, 4 poursuivants | La poursuite dure plus de 6 s ; le boopeur ne l'attrape pas tout de suite ; le propriétaire voit sa flèche ; à l'image, une bulle-bébé, jamais un animal emporté |
| M16 | **Clavier et souris sur PC** : M1 et le parcours de M9 à la souris | Tout se fait au clavier-souris ; Échap reste à Roblox ; Retour arrière revient en arrière ; les glyphes passent du clavier à la manette dès qu'on la prend |
| M17 | **Diagnostics** : provoquer une erreur de test (commande de développement), côté serveur puis côté client | Elle apparaît dans « Ce serveur », « Mon client » puis « Aujourd'hui », sans aucun nom de joueur ; un compte non administrateur ne voit pas l'entrée et n'obtient aucune réponse |
| M18 | **Pannes et imprévus** : couper le réseau du client 20 s, changer de manette, débrancher la manette, rejoindre pendant un Rush, un MEGA ou le Grand Splorch d'un autre, mourir en portant un squishy ou pendant un boop | Rien de bloqué ni de faux ; le squishy porté revient à sa place ; les créatures finies disparaissent ; l'état se recale tout seul |

**Réglages de publication** (propriétaire)
- Taille du serveur **16** (Creator Hub) et `Players.MaxPlayers = 16` dans le projet ; remplissage maximal, une place réservée aux amis.
- **Types d'appareils : Ordinateur + Console**. Téléphone et Tablette décochés. VR coupée.
- Questionnaire de maturité (cible Minimal) ; langues EN et FR ; traduction automatique activée ; console activée **seulement après** M6, M9 et M11.
- Créer les passes et produits, coller leurs identifiants, vérifier la Boutique (script de prépublication repris de Comet).
- Administrateurs LiveOps et Diagnostics (`Data/Admins.luau`).
- Pour la couche i : une **clé d'API Open Cloud** limitée à la place de test privée (publication de place et exécution Luau), donnée par une variable d'environnement, **jamais écrite dans le dépôt**.
- *Experience Event* de la Jelly Moon déclaré pour le samedi.
- Icône et vignettes capturées en jeu (commande de développement « Photo ») ; test d'icône Raise a Squishy contre Squishy Ranch.
- **Recherche de nom et de marque** : « Raise a Squishy », « Squishy Ranch », « Plop », « Big Plop », « Wobbleton », noms d'espèces (y compris contre Squishmallows).
- Date de repli : si une porte n'est pas verte le 10 décembre, sortie le **samedi 9 janvier 2027** avec le costume galette des rois.

---

## 19. Risques et parades

| # | Risque | Probabilité / impact | Parades | Indicateur |
|---|---|---|---|---|
| 1 | **Le BOOP RUSH semble être du vol** pour les plus jeunes | Moyenne / fort | Mode choisi des deux côtés, Cozy par défaut et immédiat, choix au calme après 15 min, boop par-dessus la clôture, propriétaire gagnant, attrapeur qui ne touche jamais l'original (bulle-bébé), Meilleur Ami protégé, paires limitées, « Pas ce joueur », bouclier de 15 min, interrupteur `"events"` / `"off"` | `PostBoopQuit` contre `QuitBaseline` (§16.4) |
| 2 | **Économie déséquilibrée** (inflation par les bébés et les fusions, ou blocage) | Moyenne / moyen | Taille des bébés ≤ 2 × le plus gros, plafonds journaliers, récompenses en secondes de revenu, simulation bloquante, tables en configuration | Médianes du §4.24, `SplorchReached` |
| 3 | **Calendrier serré** (6 semaines), avec la barre « zéro bug » | Forte / fort | Base de Comet reprise, téléphone retiré (une seule disposition), ligne de coupe qui coupe le contenu et jamais la qualité (§12.12), date de repli du 9 janvier | Portes du §18 |
| 4 | **Performance sur la console la plus faible** (PS4, Xbox One) : 16 ranchs, 384 squishies animés | Moyenne / fort | Rendu client, niveaux de détail, 80 animés au plus (40 en qualité réduite), `BulkMoveTo`, ShadowMap, budgets du §12.9, qualité adaptative, Graphismes légers, test M6 sur une vraie PS4 ou Xbox One | `QualityReduced`, images/s par appareil |
| 5 | **Litiges « je l'ai attrapé ! »** avec la latence | Moyenne / moyen | Trajets déterministes identiques client/serveur, tolérance de 1,5 stud, effets seulement après confirmation, test M10 | Captures par type d'entrée |
| 6 | **Serveurs peu peuplés** sans poursuite | Moyenne / moyen | Wild Wobblers (jusqu'à 13, plus un personnel par joueur), démonstration de Big Plop, Golden, MEGA réussissable seul (objectif 80 pour 1 joueur) | `serverBand`, rétention par tranche |
| 7 | **Noms non vérifiés** (titre, Plop, Wobbleton, espèces) | Inconnue / fort | Recherche Roblox et marques avant publication ; titre de secours Squishy Ranch | Checklist §18 |
| 8 | **Formes simples moins belles** que des modèles 3D | Moyenne / moyen | Direction artistique forte (pastel, écrasement, rebond), test d'icône tôt | Taux de clic sur l'icône |
| 9 | **Copies en 2 à 6 semaines** | Forte / moyen | Une espèce par semaine en données, mascotte forte, progression (Fame, Étagère, jours de Plop) gardée dans la sauvegarde | Joueurs simultanés |
| 10 | **Classification** : le côté étrange de la Lune | Faible / fort | Rester mignon ; questionnaire avant le lancement | Note reçue |
| 11 | **Dérive des règles de Roblox** (hasard payant, publicités, Kids/Select) | Faible / fort | Aucun hasard payant, aucune chance achetable même par les pièces (Cuve liée à R), `PolicyService` (paquets de pièces cachés si restreint), aucune publicité, revue à chaque version | Revue mensuelle |
| 12 | **Faux positifs de l'anti-triche** | Moyenne / moyen | Signaler avant de ramener, gel de 1,5 s toléré, ton neutre, exclusion des classements limitée dans le temps | `MoveViolation` |
| 13 | **Sons manquants ou désagréables** (bibliothèque officielle limitée) | Moyenne / faible | Jeu jouable en silence, écoute obligatoire (M12), replis documentés (§9.6) | Retours des testeurs |
| 14 | **Audience plus petite** : console d'abord, sans téléphone (≈ 80 % des joueurs Roblox en 2024, ≈ 3 % sur console) | Certaine / moyen | Choix assumé du propriétaire : une seule disposition, polie et testée à fond ; PC gardé ; créneau des tycoons faits pour la manette peu servi ; aucun effet propre à la DualSense ; ouverture aux téléphones possible plus tard sur décision (§17.2) | `device`, joueurs simultanés |
| 15 | **Plafond de revenus** d'une monétisation juste | Certaine / moyen | Assumé : fidélité d'abord ; Squish Party sociale ; Creator Rewards | ARPDAU |
| 16 | **Pièces payées perdues au Grand Splorch** | Moyenne / fort | Paquets cachés quand le Grand Splorch est prêt, perte annoncée en rouge, deuxième confirmation (§8.3) ; question au propriétaire sur leur retrait au lancement | `SplorchCoinsLost`, demandes de remboursement |
| 17 | **Ciblage d'un enfant par un même joueur** | Moyenne / fort | Une paire au plus toutes les 30 min, 4 fuites par heure, « Pas ce joueur », Cozy immédiat | `RefuseBooper`, `CozyAfterBoop` |
| 18 | **Des bugs visibles en ligne mais pas hors ligne** (ce qui est arrivé à Comet Conga) | Moyenne / fort | Mécaniques robustes (aucune règle physique ou liée à une animation, `StreamingEnabled` coupé, délais sur tous les états), 10 couches de tests dont les robots de 6 h, le parcours console aux 3 résolutions et la règle « zéro trace » ; tests dans de vrais serveurs par Open Cloud ; tests manuels sur PS5, PS4 ou Xbox One ; Diagnostics en ligne et correctif sous 48 h | `ServerError`, `ClientError`, `StateTimedOut` |
| 19 | **Navigation à la manette qui se perd** (sélection vide, piégée, ou action derrière une fenêtre) | Moyenne / fort | `FocusGuard` (§10.6), règle des 3 touches vérifiée par un robot, touches du jeu déliées derrière une fenêtre, test M9 | `FocusRescued` |
| 20 | **Télé : texte illisible, bords coupés, retard d'image** | Moyenne / moyen | Textes ≥ 28 px TV, zone sûre de 5 % sur tous les écrans, fenêtre PERFECT décalée vers le tard, tests M7 et M11 sur de vraies télés | Retours des testeurs, taux de PERFECT par appareil |

---

## 20. Questions ouvertes pour le propriétaire

La liste à jour est à la fin du document, dans le **Journal de révision**. La version 1.2 a changé la question 6 (date et test fermé) et ajouté la question 7 (matériel et accès pour les tests). Les questions 3 (PolicyService), 4 (classement « Plus gros squishy »), 6 (séance de la Lune de 22:00 UTC) et 10 (Wild Wobblers pour les joueurs Cozy) de la version 1.0 ont été tranchées par la révision ; les questions 8, 9 et 11 sont tranchées en gardant le choix actuel (voir le journal).

---

## Annexe A. Écarts décidés par rapport au concept du jury (§8)

Détails et justifications du concept : [`03-decision-du-jury.md`](03-decision-du-jury.md).

| Point du concept | Décision de ce GDD | Pourquoi |
|---|---|---|
| Une goutte de Cuve toutes les 45 s au début | **90 s** pendant l'accueil, puis 55,3 s à R = 0 et 17,7 s dès R = 4 (vitesse donnée par R, §4.9) | Avec 45 s, le joueur aurait 6 squishies à 5:00 au lieu de 3-4 (cible du jury) ; la simulation tient la cible avec 90 s pendant l'accueil |
| Selle à la taille 100 vers 4:00 | **Selle à 1 200** | Avec +1/s, le Tapis et la fusion de 1:00, Plop dépasse 100 avant 1:00 ; 1 200 tombe vers 4:30 |
| Jauge du serveur = somme des tailles | **Jauge = actions de tous** (§4.23) | Avec des tailles de 1 à 1e30, un vétéran la remplirait seul et un débutant n'y compterait jamais |
| Rush à :00, :10… et MEGA à :00, :30 | **Rush à :05, :15… ; MEGA à :20, :50 ; Golden à :00:30, :10:30, :30:30, :40:30** | Un seul grand spectacle à la fois avec 20 s d'écart (greffe n° 9) |
| « La croissance est doublée pour toujours » | Croissance × 2 par Grand Splorch, **objectif × 2,7** par niveau | Avec un objectif × 2, les boucles raccourciraient sans fin ; × 2,7 donne R = 10 au jour 7 et R = 20 au jour 28 (simulation, §4.24) |
| Le rebirth remet à zéro « les constructions » | Tapis, décorations et Cuve repartent de zéro ; **les places d'enclos et le Lit douillet sont gardés** | Perdre des places ferait dormir des squishies : ressenti de perte, contraire au pilier P2 |
| Revenu = … × rebirth × Fame | R agit par la croissance (donc la taille) ; Fame est un bonus additif plafonné à +300 % | Éviter de compter le rebirth deux fois et l'inflation |
| À 5:00, « environ 1 000 à 2 000 pièces » | Assez de pièces pour la dalle Enclos ; ≈ 10K en poche (repère) | Les pièces en poche montent et descendent à chaque achat ; ce qui compte est que le prochain achat soit à portée |
| Hors ligne 8 h (12 h avec des pièces) | Croissance hors ligne à 50 %, Pot à 25 %, 8 h ; 12 h avec le **Lit douillet** (250 000 pièces, gardé pour toujours) | Le hors ligne à 100 % rendait chaque retour égal à un Grand Splorch immédiat ; un achat en pièces doit survivre au rebirth |
| Squishydex « 26 × 9 = 234 entrées » | 26 pages d'espèces + **234 entrées de mutation** + 130 badges d'étoiles | Les 9 mutations comptent toutes ; la forme normale est la page de l'espèce |
| Premier tirage au hasard pendant l'accueil | Hasard réel, avec « **Nouveauté garantie** » sur les 3 premiers tirages (espèce, jamais la rareté) | Éviter une fusion de plus à 5:00 et donner une découverte sans truquer les chances affichées |
| Prix des passes « 249-299 » | ×2 Pièces à **249 R$** | Palier courant ; ajustable par les prix gérés de Roblox |
| Codes promo (non cités au lancement) | **Pas de codes au lancement** | Aucun champ de texte libre (sécurité des enfants) ; à revoir plus tard |
| Exclusion des classements par l'anti-triche | **Limitée dans le temps** (fin de la semaine suivante) | Question laissée ouverte par Comet Conga (rapport qualité §6.3.7) : on évite une punition à vie pour un mauvais réseau |
| Améliorations de la Cuve achetées (« plus rapide, meilleures raretés, buses à mutation ») | **Niveau de la Cuve donné par R** (qualité, vitesse, buses), jamais acheté (§4.9) | Les pièces s'achètent en Robux : acheter des chances avec elles serait un « paid random item » au sens de Roblox, contraire au principe « aucune chance payante » |
| □ = action unique, y compris « prendre » | □ = presser, lancer, acheter, attraper, booper, nourrir ; **○ / Q = prendre et poser** | Presser et Prendre visent le même squishy : sur une seule touche, l'un des deux gestes devenait impossible ou se faisait par erreur |
| La caméra cadre seule la cible | **Aucun cadrage automatique** | Boucle caméra → cible → caméra, risque de mal des transports, jamais éprouvé dans Comet Conga ; la flèche au bord de l'écran suffit |
| Démonstration de Plop si aucun Rush ni MEGA avant 4:00 | **Toujours jouée** (§4.21.6) | Les événements restent discrets pour le nouveau jusqu'à ≈ 4:30 : ils ne servent plus de démonstration |
| Carte du choix « au premier vrai Rush » | **Au calme, dès 15:00 de jeu** ; Cozy avant (§4.21.1) | Le nouveau voit d'abord le Rush sans risque ; la carte ne s'ouvre plus en pleine sirène, où un saut pouvait choisir par erreur |
| Classement « Plus gros squishy » | Remplacé par « **Plus de tampons** » ; la taille reste sur la statue du serveur (§6.9) | Sur une semaine, payer pour « y arriver plus tôt » voulait dire « plus haut » |
| Selle liée à la taille du moment | Selles **gagnées pour toujours** (record) (§4.12) | Après un Grand Splorch, l'enfant garde sa monture |
| « Plop » pour la mascotte et pour l'espèce | La mascotte s'appelle **Big Plop** dans les textes (§5.3) | Les enfants ne savaient pas qui mangeait au bol ni qui avait grossi |
| Plateformes : téléphone d'abord, commandes tactiles (jury §8.7, « Téléphone ») | **Console d'abord** (PS5, puis Xbox et PC) ; **aucune commande tactile**, types d'appareils Ordinateur + Console | Décision du propriétaire du 1er novembre 2026 ; elle passe avant le concept |
| Les invites sont des `ProximityPrompt` (jury §8.7) | **Invites dessinées par le jeu** et touches liées par `ContextActionService` (§10.4) | Le choix de cible, la ligne de vue et la liaison de touche d'un `ProximityPrompt` appartiennent au moteur et ne se testent pas hors de Roblox (barre « zéro bug ») |
| Croix ↓ = « à l'aide » (jury §8.7) | **Croix ↓ = Menu** (comme △) ; 3 emotes sur ↑ → ← | Règle des 3 touches : toute l'interface doit s'atteindre avec la croix, ✕ et ○ |
| Test sur un téléphone Android modeste, `StreamingEnabled` (jury §8.10 et §9) | Test sur une **PS4 ou une Xbox One** ; **`StreamingEnabled` coupé** (§12.9) | La console la plus faible devient l'appareil de référence ; la carte est petite, et le streaming crée des bugs « objet pas encore arrivé » |
| Monture à la taille du squishy | Taille affichée **fixée par la selle** (2,85× à 4×) (§4.12) | Une monture de 12 studs faisait monter le personnage au-dessus des clôtures et le coinçait dans le décor |
| Mutation Flop « dégonflée et grognonne » | Gardée, mais **brillante** (étoiles dorées, badge ×100, ralenti, bannière) et verrouillée d'office (§4.5, §4.13) | Elle ne doit jamais passer pour un squishy cassé qu'on vend par erreur |

---

## Journal de révision

### Version 1.2 : décision du propriétaire du 1er novembre 2026 (console d'abord, zéro bug)

Le propriétaire a joué Comet Conga en direct et a vu des bugs que nos tests hors ligne n'avaient pas vus. Il décide : **Raise a Squishy est fait d'abord pour la PS5** (DualSense, télé vue de 2,5-3 m), puis Xbox et PC ; **pas de téléphone ni de tablette au lancement** ; et **aucun bug au lancement**. Cette décision passe avant l'étude de marché et le concept du jury quand ils se contredisent (Annexe A).

#### Ce qui a changé
- **Appareils et public** : fiche d'identité, pilier P5 (« Une manette, un canapé »), personas (Léa sur la PS5 du salon, Noah sur Xbox ou PS5, Sam au PC), positionnement honnête (moins de joueurs possibles, créneau peu servi), types d'appareils Ordinateur + Console (§0, §1.2-§1.4, §18).
- **Commandes** : manette d'abord, clavier-souris en second avec la même disposition ; toutes les commandes tactiles retirées ; **croix ↓ = Menu** (comme △) pour que la croix, ✕ et ○ suffisent partout ; 3 emotes au lieu de 4 ; aucun appui simultané ; L3 et R3 libres ; au clavier, Retour arrière = retour (§6.5, §10.4).
- **Interface** : une seule disposition « 10 pieds », **référence 1920 × 1080 (px TV)** proportionnelle (720p, 1080p, 4K) ; zone sûre de 5 % sur tous les écrans ; texte ≥ **28 px TV** (32 pour le texte courant) ; HUD réduit à 8 éléments en jeu calme, le rail remplacé par une **puce Menu** ; un seul message au centre à la fois ; positions de chaque élément vérifiées sans recouvrement ; panneaux de 1440 × 860 ; Grand Splorch en 2 appuis (△ ✕) (§10.1-§10.3).
- **Focus** : nouveau module `FocusGuard` (sélection jamais perdue, jamais piégée, rendue en 0,25 s, ○ partout, 60 s au plus pendant une fenêtre de Roblox) ; touches du jeu déliées derrière toute fenêtre (§10.3, §10.6).
- **Vibrations et sons d'interface** posés comme partie du design : 3 vibrations de plus (`tileBuy`, `holdDone`, `cardIn`), un son fixe par geste de menu (§9.6, §10.5).
- **Accueil** : chaque consigne montre le glyphe de la manette (ou la touche du clavier), le stick gauche, L1 R1 et △ sont enseignés ; **aucune étape ne peut bloquer** (90 s puis la consigne se range) ; mort ou changement de manette pendant l'accueil prévus (§3).
- **Mécaniques rendues robustes** (rien ne dépend de la physique, d'une animation ou d'un objet pas encore arrivé) :
  - dalles achetées quand le serveur voit le joueur entrer (2,5 / 3,5 studs, un achat par entrée), jamais par `Touched` (§4.6) ;
  - ranchs protégés par la poussée du serveur ; mur invisible de 12 studs sur les clôtures ; membrane du portail solide seulement chez chaque client, comme confort (§6.3) ;
  - personnage placé par le serveur dans son ranch, pas par les `SpawnLocation` (§6.1) ;
  - bond scripté sur un arc fixe et capture calculée sur la géométrie du bond (§4.12) ;
  - monture de taille fixée par la selle (2,85× à 4×), trois valeurs fixes réglées par le serveur, aucun siège ni soudure (§4.12) ;
  - portage = état du serveur, terminé tout seul dans 6 cas (§4.10) ;
  - **plus de `ProximityPrompt`** : invites dessinées par le jeu, touches liées par `ContextActionService` (§4.7, §10.4) ;
  - délais du jeu = minuteurs du serveur, jamais la fin d'une animation ; Grand Splorch appliqué d'un bloc, place rendue si le joueur part (§4.10, §4.15, §12.1) ;
  - décor ancré et non solide sauf une courte liste de solides, sans recoin où se coincer (§11.1) ;
  - **`StreamingEnabled` coupé** et positions venues de `WorldLayout` (§12.1, §12.9) ;
  - messages numérotés, créatures finies qui disparaissent même sans message de fin, profils relus et réparés par `reconcile` (§12.5, §12.6) ;
  - étapes du tick protégées une par une (§12.3).
- **Qualité** : nouvelle partie **« Stratégie qualité : zéro bug »** (§12.10) : ce que cela veut dire pour le joueur, **table des états et de leurs délais**, **10 couches de tests** (propriétés des modules purs, attaque de chaque remote, 16 robots pendant 6 h simulées avec invariants à chaque tick, parcours console à 3 touches en 1080p, 4K et 720p, données en désordre, économie, red team, règle « zéro trace », vrais serveurs Roblox par Open Cloud, Diagnostics).
- **Diagnostics** (nouveau, §12.11) : erreurs et avertissements du serveur et des clients relevés, nettoyés (aucun nom), plafonnés, comptés avec 3 exemples par clé, totalisés pour le jour ; **panneau réservé aux administrateurs**, lisible à la télé, fait pour être photographié. Remotes `ReportError`, `RequestDiagnostics`, `DiagnosticsSnapshot` (§12.7) ; interrupteur `Features.Diagnostics`.
- **Performance** : appareil de référence **PS4 et Xbox One** ; 30 images/s stables ; ShadowMap au lieu de Future ; `Highlight` ≤ 12, lumières ≤ 24, particules ≤ 200 ; instances et connexions bornées ; **qualité adaptative** selon la durée des images (§11.3, §12.9).
- **Mesures** : KPI d'erreurs et d'images par seconde ; champ analytique `device` ; événements `ServerError`, `ClientError`, `FocusRescued`, `StateTimedOut`, `QualityReduced`, `TouchDeviceJoined` et leurs seuils d'action (§1.5, §16).
- **Lancement** : portes de qualité alignées sur les 10 couches ; tests manuels réécrits pour la télé (M1 à M18, dont manette seule 30 min sur PS5, PS4 ou Xbox One à 16 joueurs, clavier-souris, Diagnostics, pannes et imprévus) ; « aucun bug connu ouvert » devient une porte ; risques 3, 4 et 14 réécrits, risques 18 à 20 ajoutés ; la ligne de coupe coupe le contenu, jamais la qualité (§12.12, §18, §19).
- **Ce qui disparaît avec le téléphone** : le HUD tactile de la version 1.1 (bouton Menu, bouton Action, boutons Prendre, Bondir, Monter et Emote, zone du joystick, colonnes du petit écran), l'appui long pour Prendre, la désignation au doigt, les tests `Touch.spec` et M9 « téléphone en main », le test sur Android modeste.

#### Ce qui a été refusé ou gardé, et pourquoi
- **Garder une disposition téléphone « au cas où »** : refusé. C'est contraire à la décision, et cela doublerait l'interface et ses tests. Les tailles relatives et la cible choisie par le jeu rendront une ouverture plus simple si le propriétaire la décide (§17.2).
- **Une touche directe pour le Grand Splorch** (maintenir une touche en jeu) : refusé. Toutes les touches sont prises, et un maintien en jeu peut partir par erreur ; △ ✕ fait 2 appuis, avec l'aperçu obligatoire.
- **Garder 4 emotes** : refusé. La règle des 3 touches demande croix ↓ pour ouvrir le menu ; « À l'aide » était le signal le moins utile.
- **Monture jusqu'à 6×** : refusé. Le personnage montait au-dessus des clôtures et se coinçait dans le décor ; la vraie taille reste visible sur la silhouette du ranch et sur la statue.
- **Garder les `ProximityPrompt`**, pourtant utilisés par Comet Conga : refusé. Leurs comportements internes ne se testent pas hors de Roblox, et la barre « zéro bug » demande de tout tester.
- **`StreamingEnabled` allumé avec des modèles persistants** : gardé seulement comme repli si la carte grossit beaucoup ou si la mémoire de la PS4 l'exige.
- **Gâchettes adaptatives de la DualSense** : impossibles, Roblox ne les expose pas ; nous utilisons les moteurs standard.
- **Une interface plus petite et plus dense pour le PC** : refusé. Le propriétaire veut la même disposition ; un joueur PC près de son écran lit sans peine des textes de 28 px TV.

### Version 1.1 : réponses aux critiques indépendantes

La version 1.0 a été relue par des critiques indépendants. Ce journal répond aux deux critiques détaillées que nous avons reçues : **sécurité des enfants et des parents** (1 point bloquant, 14 majeurs, 9 mineurs) et **console et ergonomie** (1 point bloquant et 6 majeurs détaillés ; la suite de cette critique nous est parvenue coupée, ses autres points sont traités d'après son résumé : HUD du téléphone, tailles tactiles, cartes qui prennent la manette ; la phrase coupée sur la capture vidéo est couverte par la règle des cartes non bloquantes, §10.3, et, en v1.2, par la protection de `CaptureService` sur console, §9.5). Une troisième critique (technique) était annoncée, mais son texte ne nous est pas parvenu ; beaucoup de points techniques sont couverts par la v1.2 (robustesse, délais, tests), et elle sera traitée dès qu'elle arrivera. Le concept approuvé (jury §8) est gardé ; les écarts sont listés à l'Annexe A.

#### Ce qui a changé

**Argent et équité**
- **Bloquant : plus aucune chance achetable.** Les pièces s'achètent en Robux ; elles achetaient la qualité, la vitesse et les buses de la Cuve, donc des chances (« paid random items » de Roblox). Le niveau de la Cuve vient maintenant de R : qualité `min(8, 1 + R)`, vitesse `min(10, 3 + 2 × R)`, buses `min(5, R)` (§4.9). Les 3 dalles disparaissent, 6 décorations arrivent (18 au lieu de 12, croissance ×2,2) (§4.6). PolicyService ne cache plus que les paquets de pièces (§8.1 n° 9). Simulation relancée (§4.24).
- **Classements** : « Plus gros squishy » quitte le mondial (il reste sur la statue du serveur), remplacé par « Plus de tampons » ; toutes les égalités au premier arrivé ; l'onglet montre d'abord ma place sur le serveur et mon record contre la semaine dernière. Texte honnête : l'argent accélère le ranch, donc indirectement la taille (§6.9, §8.1 n° 10).
- **Pièces payées perdues au Grand Splorch** : paquets cachés quand le Grand Splorch est prêt, perte annoncée en rouge avec « Dépenser d'abord », deuxième confirmation après un achat de moins de 30 min (§4.15, §8.3).
- **Squish Party** : vendue seulement si elle commence aussitôt, 3 par jour, boost personnel de 10 min si l'acheteur part, bannière qui ne parle pas d'achat (§8.3).
- **KPI « part en mode Rush »** : observé seulement ; règle écrite contre les pièges de conception ; on mesure plutôt le retour J1 des joueurs Rush contre Cozy (§1.5, §16.4).

**BOOP RUSH**
- **Poursuite** : le boopeur ne peut pas attraper sa fuite pendant 6 s ; premier bond de 20 studs à l'opposé de lui ; flèche immédiate et rayon de 8 studs pour le propriétaire ; 20 s de revenu pour les joueurs Rush près d'une capture ; équilibre visé : propriétaire ≥ 25 %, personne ≤ 20 % (§4.21.2, §4.21.3).
- **Mise en scène** : l'attrapeur ne touche jamais l'original ; le squishy éternue une bulle-bébé, l'original rentre avec des cœurs ; message « le retour d'abord » (§4.21.3, §9.4).
- **Choix du mode** : Cozy avant tout choix ; carte au calme dès 15:00 (fin du bouclier), animation de 6 s, « Plop ne s'enfuit jamais », garde de 0,6 s ; premier Plop Meilleur Ami d'office ; carte après le premier boop ; passage en Cozy immédiat (§4.21.1).
- **Protections** : une paire au plus toutes les 30 min, 4 fuites par ranch et par heure, 2 squishies à la clôture après un boop, bouton « Pas ce joueur » côté serveur, pas de clôture sous bouclier (§4.21.4).
- **Mode Cozy** : même Fame que le mode Rush (Fame du Rush partagée, 30 par jour), Wild Wobbler personnel pour tous à chaque Rush, plus de badge « cozy » public (§4.18, §4.21.5).

**Boucle de base, commandes et collection**
- **Bloquant : Presser et Prendre sur deux touches** : □ / E presse (et lance, attrape, boope), ○ / Q prend et pose (§4.7, §4.10, §10.4). L'appui long prévu au téléphone a disparu en v1.2.
- **Cible choisie par le jeu**, jamais par la caméra : score, hystérésis, passage au squishy prêt suivant, L1 / R1 aussi aux clôtures, clic par projection à l'écran (§10.4). En v1.2, les `ProximityPrompt` sont remplacés par des invites dessinées par le jeu.
- **Bond** : visée sur la position future, autour du stick gauche, capture automatique à l'atterrissage, tampon de 0,25 s (§4.12).
- **Caméra** : plus aucun cadrage automatique (§10.4).
- **PERFECT** décalé pour le retard d'image : [−0,08 ; +0,20] s, MEGA [−0,12 ; +0,28] s (§4.7, §4.22).
- **Jumeaux visibles** (cœurs, « Fusion ! », pastille ♥), **Tout fusionner**, **Ranger** (§4.10, §4.13).
- **Flop, Glitch, Arc-en-ciel** fêtés comme des naissances rares ; verrou automatique (Légendaire+, Galaxie+) ; confirmation en 2 étapes pour vendre ou relâcher un Épique+ ou un Doré+ (§4.5, §4.13, §9.4).

**Grand Splorch**
- Le petit squishy sort du nuage et revient faire coucou au héros ; selles gagnées pour toujours ; aperçu en 3 tuiles avec « Détails » ; choix du squishy qui s'envole (cadeaux plafonnés à Peu commun pour une espèce Épique+) ; place dans la file garantie (§4.12, §4.15, §9.4).

**Accueil, objectifs, interface**
- Événements du serveur discrets pour le nouveau jusqu'à l'étape 9 ; démonstration de Big Plop toujours jouée (§3, §4.21.6).
- Objectifs faisables en 20 min (colonne « Proposé si »), aucun objectif réservé au mode Rush, remise à zéro de minuit sans perte, nouveau jalon de simulation (§7.4, §4.24).
- HUD : éléments ancrés aux bords, une seule bannière à la fois, APPLAUDIR à la place de GRAND SPLORCH (§10.2). La partie tactile de cette correction (bouton Menu, zones de toucher, zone du joystick) est sans objet depuis la v1.2.
- Cartes en jeu : non bloquantes par défaut, une seule à la fois, garde de 0,6 s pour la seule carte bloquante (§10.3).

**Petites corrections**
- Tapis à 20 pièces ; flèches seulement quand les pièces suffisent ; une dalle trop chère montre un anneau, jamais un refus (§3, §4.6).
- La mascotte s'appelle Big Plop ; le bol nourrit le Meilleur Ami n° 1 ; les écrans écrivent le vrai nom du squishy (§4.19, §4.20, §5.3, §7.2).
- Lune : page dorée sans la mutation Lunaire ; séance de 22:00 UTC gardée (seule séance jouable en Asie-Pacifique) ; gouttes brillantes qui flottent au lieu de « gouttes qui perlent » (§4.5, §4.17, §4.23).
- Relâcher : maintien pour chaque relâche, ton positif, Prairie des copains où les squishies relâchés font coucou (§4.13, §11).

**Cohérence trouvée pendant la révision**
- Le schéma du Squishydex tenait en bits pour 28 espèces au plus, alors qu'une espèce arrive chaque semaine : il garde maintenant un masque par espèce dans un tableau dense, sans limite et sans trou (les DataStores refusent les tableaux à trous) ; même règle pour l'Étagère à trophées (§12.6).
- Le prototype de simulation de la version 1.0 n'utilisait pas exactement les valeurs du document ; les chiffres du §4.24 viennent d'une nouvelle simulation avec les valeurs de la version 1.1. Conséquences : première balade vers 4:30 (et non 3:50), premier Grand Splorch vers 14 min, R = 10 au jour 7 et 20 au jour 28, premier 1e12 vers le jour 24. Sans la vitesse de départ 3 de la Cuve, le premier Grand Splorch glissait vers 15 min.
- Les cadeaux du Grand Splorch reprenaient l'espèce du squishy qui s'envole : un Mythique aurait fait pleuvoir des Mythiques sur tout le serveur. Plafond à Peu commun pour une espèce Épique+ (§4.15).

#### Ce qui a été refusé, et pourquoi
- **Classement « Meilleure série PERFECT »** (critique sécurité) : un PERFECT se vérifie avec l'heure envoyée par le client ; un script réussit donc 100 % de PERFECT. Borné dans le ranch (×2), mais un classement mondial serait une vitrine pour tricheurs. Remplacé par « Plus de tampons ».
- **Appui long sur □ pour Prendre** (critique sécurité) : un enfant qui maintient □ prendrait au lieu de presser. Nous gardons les deux touches (critique console).
- **Couleurs de selle à acheter en pièces** : inutiles pour l'économie (les 6 décorations suffisent) et elles dévaloriseraient les selles gagnées (Squishydex, jours de Plop).
- **Garder un cadrage automatique en option** : refusé au lancement (mal des transports, jamais éprouvé). À rouvrir après le lancement si des joueurs le demandent.
- **Indicateurs d'état à droite de la pastille Fame** : ils touchaient la barre du MEGA ; ils vont à droite, sous le suivi d'objectif (toujours vrai en v1.2). Le bouton Menu tactile de cette critique est sans objet depuis la v1.2.
- **2 % de Lunaire dans la Goutte chanceuse** : inutile, la page dorée ne demande plus la Lunaire.

### Questions ouvertes pour le propriétaire
1. **Paquets de pièces au lancement** : les garder avec les 3 protections du §8.3, ou les retirer ? Les retirer supprime tout risque de pièces payées perdues au Grand Splorch et simplifie PolicyService, pour un revenu plus faible. Notre avis : les retirer au lancement, puis décider en janvier avec les mesures.
2. **Titre** : Raise a Squishy ou Squishy Ranch, après la recherche de nom et de marque et le test d'icône ?
3. **Suffixes français des grands nombres** : la version française correcte (k, M, Md, Bn…) ou les suffixes internationaux (K, M, B, T…) que les enfants voient déjà dans les jeux Roblox ? Un petit test avec des enfants français aiderait.
4. **Squish Party** : 99 R$, 10 min, 3 achats par jour, seulement si elle commence aussitôt, nom caché par défaut. D'accord ?
5. **Clips automatiques** (moments rares, son Grand Splorch) activés par défaut, ou désactivés par défaut ?
6. **Date et test fermé** : avec la barre « zéro bug », nous proposons un **test fermé d'une semaine** avant la sortie publique, avec 20 à 30 testeurs (PC, PS5, et si possible une PS4 ou une Xbox One) sur la place privée, panneau Diagnostics ouvert. Pour sortir le 12 décembre, ce test devrait commencer le 3 décembre avec un jeu complet ; sinon, test fermé en décembre et sortie le 9 janvier. Quelle option choisissez-vous ?
7. **Matériel et accès pour les tests** : avez-vous une **PS4 ou une Xbox One** (la console la plus faible) et une Xbox, en plus de la PS5, pour les tests M6 et M11 ? Sinon, nous testons sur PS5 en forçant la qualité réduite, et le risque sur la performance reste ouvert. Et quand pourrez-vous fournir la **clé d'API Open Cloud** de la place de test et l'accès réseau (couche i du §12.10) ?

Tranchées en gardant le choix de la version 1.0 (anciennes questions 8, 9 et 11) : les cadeaux du Grand Splorch vont à tout le serveur ; le pet-sitting reste réservé aux amis Roblox ; le Meilleur Ami suit le joueur en ville.
