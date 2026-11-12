# Raise a Squishy — Game Design Document

> **Document 02 : conception du jeu (GDD).** **Version 2.0 du 2 novembre 2026 : le jeu complet.** Elle fusionne dans un seul document le plan de contenu complet [`09-plan-contenu-complet.md`](09-plan-contenu-complet.md) (9 familles d'amélioration, écran Améliorations et ses 20 règles « zéro bug d'affichage », Confettis et Atelier de Big Plop, Petit Splorch, Jelly Ascend, Plopettes, Monuments, ranch qui évolue, personnalités, piste de la semaine), applique les **6 décisions par défaut** du studio sur les questions du §8.4 de docs/09 (le propriétaire peut revenir sur chacune, §20) et donne l'économie **resimulée** (§4.24, 84 et 140 jours, serveurs de 4, 8 et 16). **Révisée le même jour après une critique indépendante** (45 remarques, toutes décidées : Journal de révision v2.0 ; économie resimulée sur 22 profils, §4.24.1 ; contenu nommé en anglais et en français, Annexe B). **Tout est disponible au lancement** ; seules les espèces de la semaine et les costumes de saison arrivent ensuite (§17). Les sections changées portent la mention *(v2.0 : modifié)*, *(v2.0 : réécrit)* ou *(v2.0 : nouveau)* ; les autres sont celles de la v1.3. Ce qui a changé et pourquoi : **Journal de révision v2.0**, à la fin. **Historique** : version 1.3 du 1er novembre 2026. La version 1.1 a appliqué les critiques indépendantes (sécurité des enfants, console et ergonomie). La version 1.2 applique la **décision du propriétaire du 1er novembre 2026** : **console d'abord** (PS5 avec DualSense sur une télé, puis Xbox et PC ; pas de téléphone au lancement) et **zéro bug** au lancement. Cette décision passe avant l'étude de marché et le concept du jury quand ils se contredisent. La version 1.3 traite les 42 remarques qui n'étaient pas parvenues aux versions précédentes (fin de la critique console, toute la critique technique et économique) : économie refaite et resimulée (prix des dalles, hors ligne, boosts, jauge), anti-triche des captures et des bonds, schéma, monture, textes du monde, vibrations. Ce qui a changé, ce qui a été refusé et les questions ouvertes sont dans le **Journal de révision**, à la fin. Statut : à valider par le propriétaire, puis base de la production.
> Documents liés : [`01-analyse-marche-tycoon.md`](01-analyse-marche-tycoon.md) (étude de marché, citée « Étude §x ») et [`03-decision-du-jury.md`](03-decision-du-jury.md) (concept final au §8, idées greffées au §6, faiblesses corrigées au §7, calendrier au §8.10, risques au §9).
> Modèle de format : le GDD de Comet Conga (`/home/user/jules/roblox-game/docs/02-game-design-document.md`), sa couche console (`07-console-ps5.md`) et les leçons de son rapport qualité (`06-rapport-qualite.md`).
> **Règle de lecture.** Chaque chiffre de ce document est une **valeur de départ décidée**, à placer telle quelle dans `src/shared/Config/*`. Les valeurs d'économie sont vérifiées par la simulation Lune du §4.24, qui bloque la publication si un jalon sort de sa tolérance. Ensuite, les données réelles peuvent ajuster ces valeurs sans toucher au code.

**Conventions**
- Distances en *studs*. Temps en secondes (s), minutes (min) ou heures (h). Horaires en **UTC**.
- `floor` = arrondi à l'entier inférieur. Les monnaies sont calculées par le serveur seulement.
- Les noms propres de l'univers (Raise a Squishy, Wobbleton, Plop, les noms d'espèces, BOOP RUSH, MEGA SQUISH, Grand Splorch, Squishydex, Jelly Moon…) restent en anglais dans les deux langues : c'est notre propriété intellectuelle. Les mots du quotidien sont traduits (§15).
- Clé de configuration entre crochets, par exemple [`Balance.Press.Cooldown`].
- *(v2.0)* **r** = niveau de Grand Splorch de la boucle en cours ; **Record R** = le plus haut r jamais atteint (il ne baisse jamais) ; **A** = nombre de Jelly Ascend faites (§4.27). Avant toute Ascension, r = Record R : dans les passages de la v1.3 qui écrivent « R », lire **r** pour l'économie de la boucle (prix, objectif, croissance) et **Record R** pour tout ce qu'on voit ou possède (Cuve, familles, Meilleurs Amis, Lit, titres). Le code n'a qu'une source : `Logic/Prestige`.
- *(v2.0)* **T12** = prix du 12e niveau du Tapis à Goûter dans la boucle en cours (306 455 660 × 3,5^r × F(A)) : l'unité des jalons de santé de l'économie (§4.24).
- *(v2.0, critique B1)* **F(A)** = facteur de prix de la boucle après A Ascensions = produit des facteurs de la table `Balance.Ascend.PriceByA` : **0,5 pour chacune des 4 premières Ascensions, 0,32 de A5 à A10, puis 0,31, et 0,29 aux Ascensions qui demandent un Grand Splorch de plus (A11, A19, A27…)** (F(1) = 0,5 ; F(4) = 0,0625 ; F(5) = 0,02 ; F(10) ≈ 6,7e-5) *(réglage de la porte d'économie, lot A1, 5 novembre 2026 : docs/04 §21)*. Écrit en maths, calculé par multiplications successives (§4.6).
- *(v2.0, critique M9)* **À l'écran, tous les compteurs qu'on lit sont en chiffres arabes** : « Record 15 » (Record R), « Boucle 3 » (r), « Grand Splorch 15 / 15 » (condition). Les chiffres romains restent un **décor** (arche, titre du spectacle, drapeaux), jamais une information à lire.
- **px TV** = pixels d'un écran de 1920 × 1080, la référence de toute l'interface (§10.1). Sur un écran 4K, tout est 2 fois plus grand en pixels ; en 1280 × 720, 1,5 fois plus petit : la taille vue depuis le canapé ne change pas.
- Glyphes de la manette : noms PlayStation (✕ □ ○ △, L1 R1 L2 R2, croix ↑ → ↓ ←). À l'écran, le jeu montre toujours l'icône de la manette du joueur (§10.6).
- **Au lancement** *(v2.0)* = tout ce document (décision par défaut n° 6) ; seules les espèces de la semaine et les costumes de saison arrivent ensuite (§17).

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
| **Dalle** (tile) | Pastille lumineuse au sol du ranch. On s'arrête dessus 0,6 s pour acheter |
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
| **Jauge du serveur** (Wobble Meter) | Remplie par les actions de tous ; pleine = ×2 pour tout le serveur pendant 5 min, puis 20 min de sieste de Big Plop |
| **Grand Splorch** | La renaissance (rebirth) : le plus gros squishy éclate en cadeaux pour tout le serveur |
| **Étagère à trophées** (Trophy Shelf) | Garde la taille record de chaque espèce, avec un petit bonus permanent |
| **Squishydex** | Le livre de collection : 26 espèces, 234 entrées de mutation, des badges d'étoiles |
| **Fame** (célébrité) | Score permanent gagné pendant le Rush (boopé, Wild Wobbler attrapé, Héros), au Grand Splorch, au MEGA, en relâchant un squishy. Donne un bonus de revenu. Le mode Cozy en gagne autant que le mode Rush |
| **Meilleur Ami** (Best Friend) | Squishy choisi : jamais boopable, il te suit en ville, c'est lui qu'on nourrit au bol. Ton premier Plop l'est d'office |
| **Jelly Moon** (Lune de Gelée) | Le rendez-vous du samedi : mutations rares, Mythiques boopables, MEGA lunaire |
| **Puce Menu** | Petit élément du HUD (glyphe △ + « Menu ») qui ouvre le menu des panneaux ; croix ↓ l'ouvre aussi |
| **Diagnostics** | Panneau réservé aux administrateurs : les erreurs vues sur les vrais serveurs et les vrais appareils, pour les photographier et nous les envoyer (§12.11) |
| **Record R** *(v2.0)* | Le plus haut niveau de Grand Splorch jamais atteint ; il ne baisse jamais. Tout ce qu'on voit ou possède le suit (§4.27) |
| **Petit Splorch** *(v2.0)* | Après une Jelly Ascend, un Grand Splorch qui ne bat pas le Record R : local, hors de la file du serveur, 1 Confetti (§4.27) |
| **Jelly Ascend** *(v2.0)* | La 2e couche de renaissance, à r = 15, 20, 24… : r repart de zéro, la croissance est ×3 à chaque boucle, pour toujours, rien de débloqué ne se perd (§4.27) |
| **Souvenir de gelée** / Jelly Memory *(v2.0)* | Croissance ×3 tant que r est loin sous le Record R, puis ×2, ×1,5 et ×1,25 sur la 1re boucle record : les remontées après une Ascension vont vite, sans falaise au retour (§4.27) |
| **Confettis** *(v2.0)* | 2e monnaie, gagnée en jouant seulement (Grand Splorch, Ascension, piste de la semaine), jamais vendue, jamais remise à zéro (§4.26) |
| **Atelier de Big Plop** *(v2.0)* | La boutique permanente des Confettis : confort et départ rapide, pour toujours (§4.26) |
| **Écran Améliorations** *(v2.0)* | L'écran télé qui achète tout : 4 onglets, cartes « Conseillé », ×1 / ×10 / Max (§10.7) |
| **Plopettes** *(v2.0)* | 6 petites aides nommées qui pressent les squishies que le joueur ne presse pas (§4.28) |
| **Gants Moelleux**, **Tapis Étoilé**, **École des Plopettes**, **Monuments** *(v2.0)* | Familles d'amélioration nouvelles : presser plus fort, grossir encore plus vite, aides plus rapides, grands décors permanents (§4.6) |
| **Paliers de ranch** *(v2.0)* | 6 constructions permanentes (Arche, Tour, Balcon, Phare, Dôme, Couronne) gagnées par le Record R (§11.5) |

**Sommaire**

0. Fiche d'identité · 1. Vision, piliers, public, KPI · 2. Boucle de jeu et horloge commune · 3. Les 5 premières minutes · 4. Systèmes détaillés (monnaies, nombres géants, formules, raretés, mutations, **dalles et 9 familles d'amélioration**, presser, Pot, Cuve, Bassin, fuites, monture, Grand Splorch, Étagère, Squishydex, Fame, hors ligne, BOOP RUSH, MEGA SQUISH, jauge et Jelly Moon, simulation, plafonds, **Confettis et Atelier, Jelly Ascend, Plopettes, table des Record R**) · 5. Contenu (26 espèces, fabrication, Plop, cosmétiques, **personnalités**) · 6. Social et multijoueur · 7. Rétention (**piste de la semaine, Défis, Carnet**) · 8. Monétisation · 9. Juice, animation et sons · 10. Interface télé, commandes à la manette, vibrations, **écran Améliorations et ses 20 règles** · 11. Monde (**le ranch qui évolue**) · 12. Architecture technique, stratégie qualité « zéro bug » et Diagnostics · 13. Sécurité des enfants · 14. Accessibilité · 15. Localisation · 16. Analytics · 17. Lancement et mises à jour · 18. Checklist de lancement · 19. Risques · 20. Questions ouvertes et décisions par défaut · Annexe A. Écarts avec le concept · **Annexe B. Contenu nommé de la v2.0 (EN / FR)** · Journal de révision (v2.0 en tête)

---

## 0. Fiche d'identité

| Élément | Valeur |
|---|---|
| Titre | **Raise a Squishy** (titre de travail ; secours : *Squishy Ranch*). Aucun des deux n'est vérifié (Journal de révision, question 2) |
| Accroche | EN « Raise squishy jelly pets, grow them to a TRILLION… and make them sneeze at the neighbours! » ; FR « Élève des squishies tout mous, fais-les grossir jusqu'à 1 000 milliards… et fais-les éternuer chez les voisins ! » |
| Genre | Tycoon de créatures : croissance automatique + collection + fusion + renaissance, avec des poursuites amicales et des événements coopératifs de serveur |
| Joueurs | **16 par serveur** (`Players.MaxPlayers = 16`), **16 ranchs** |
| Plateformes | **Console d'abord** (décision du propriétaire, 1er novembre 2026) : **PlayStation 5** avec DualSense sur une télé vue à 2,5-3 m, puis **Xbox**, puis **PC** (manette, ou clavier et souris). **Téléphones et tablettes : non visés au lancement** : aucun contrôle tactile, aucune disposition pour petit écran. Types d'appareils publiés : **Ordinateur + Console** (VR coupée). Le PC reste car c'est là qu'on teste dans Studio |
| Contrôles | **Manette d'abord**, sans curseur virtuel : □ = action principale selon le contexte (presser, lancer, attraper, booper), ○ = Prendre / Poser, R2 = Bondir (qui attrape aussi), L2 = Monter, △ ou croix ↓ = Menu. Clavier et souris en second, même disposition (E, Q, Maj, R, M) |
| Qualité | **Zéro bug au lancement** : mécaniques vérifiées par le serveur (distances, états), jamais de physique ni d'animation dans les règles, un délai sur chaque état, 10 couches de tests (§12.10) et un panneau **Diagnostics** des erreurs en ligne pour les administrateurs (§12.11) |
| Classification visée | **Minimal** au questionnaire de maturité (Mild au pire) ; éligible aux catalogues Roblox Kids et Select |
| Session cible | 15 à 30 min. Le rythme fixe (fuite 60 s, Rush 10 min, MEGA 30 min) pousse au-delà de 10 min (seuil des Creator Rewards) |
| Public | 6-14 ans au cœur, satisfaisant pour les ados et les adultes collectionneurs |
| Monétisation | 4 passes « Pour toujours » et 2 familles de produits **à résultat connu** (Squish Party, tenues). Aucun hasard payant, aucune chance achetable (même avec des pièces), **aucune monnaie vendue** (ni pièces ni Confettis), **rien de l'Atelier, aucune Ascension, aucune Plopette, aucune piste payante** (v2.0), aucune pub vidéo |
| Code | Luau `--!strict`, Rojo, aucun travail manuel dans Studio. Estimation ≈ 12 800 lignes de jeu au premier passage, hors tests ; ≈ 9 000 lignes de tests et d'outils en plus (§12.12). Comet Conga a fini à 58 500 lignes après 6 tours de QA : prévoir large |
| Contenu au lancement *(v2.0 : modifié)* | 24 espèces (6 familles × 4) + 2 secrètes, 7 raretés, 9 mutations, 1 ville, 16 ranchs, 6 événements récurrents (créature en fuite, Golden Wobbler, BOOP RUSH, MEGA SQUISH, jauge du serveur, Jelly Moon) ; **9 familles d'amélioration (144 niveaux)** et l'écran Améliorations ; **2 couches de renaissance** (Grand Splorch et Jelly Ascend), Confettis et Atelier ; 6 Plopettes ; 10 Monuments ; 6 paliers de ranch et un changement visible à chaque Record R de 1 à 20 ; 14 habillages ; 40 objets de Déco perso ; 6 personnalités ; piste de la semaine, Défis, Carnet du Ranch (§5.5) |
| Date visée *(v2.0 : modifié)* | **Quand tout le contenu de ce document est construit et que les portes du §18 sont vertes** (décision par défaut n° 6 : pas de calendrier fixé). La v1.3 visait le samedi 12 décembre 2026 avec le costume d'hiver ; cette date n'est plus un engagement. La barre « zéro bug » passe avant la date |

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

### 2.1 Boucle principale (10 à 60 s) *(v2.0 : modifié)*

```
            ┌──────────────────────────────────────────────────────────────┐
            │                                                              │
            ▼                                                              │
   ┌────────────────┐   +1 taille/s (×Tapis, ×2^R)   ┌────────────────┐     │
   │ 1. GRANDIR     │ ─────────────────────────────▶ │ 2. PRESSER     │     │
   │ (tout seul)    │   revenu passif → Pot          │ SPLORCH !      │     │
   └────────────────┘                                │ pièces ×22 s   │     │
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
   Méta : plus gros squishy ≥ objectif → GRAND SPLORCH (×2 croissance, Confettis, déblocage du Record R)
          r = 15, puis 20, 24, 28… → JELLY ASCEND (croissance ×3 à chaque boucle, pour toujours ; r repart de zéro, rien de débloqué ne se perd)
```

1. **Grandir.** Chaque squishy grossit tout seul (+1 par seconde au départ) et remplit le Pot à Pièces.
2. **Presser.** Le joueur presse un squishy prêt : il gagne 22 secondes de revenu de ce squishy d'un coup, ×2 si PERFECT. Chaque squishy se recharge en 8 s.
3. **Construire** *(v2.0 : modifié)*. Les pièces achètent **9 familles d'amélioration** (§4.6), sur les dalles du sol ou depuis l'écran Améliorations (§10.7) : le Tapis à Goûter et le Tapis Étoilé (croissance), les décorations (+5 % de bonus de revenu chacune ; l'écran montre l'effet réel, §4.6), les places d'enclos, le Lit douillet, les Gants Moelleux (presser plus fort), l'École des Plopettes (aides plus rapides) et les Monuments (grands décors permanents) ; les Confettis achètent l'Atelier de Big Plop (§4.26). Ni les pièces ni les Confettis n'achètent jamais de chance : la Cuve s'améliore toute seule avec le Record R (§4.9).
4. **Faire naître.** La Cuve fait naître un squishy gratuit à intervalle fixe. Les créatures en fuite, le Golden Wobbler, le BOOP RUSH et le MEGA SQUISH en apportent d'autres.
5. **Fusionner.** Deux jumeaux lancés dans le Bassin fusionnent : taille (a + b) × 1,25 et une étoile de plus. Le résultat peut fusionner encore (combo).

**La décision de chaque minute :** presser maintenant (pièces tout de suite), acheter le prochain Tapis (croissance pour tout le ranch), ou garder des jumeaux dans le Bassin pour préparer un combo ×4.

### 2.2 Boucles secondaires *(v2.0 : modifié)*

| Boucle | Durée | Contenu | But |
|---|---|---|---|
| **Rythme du serveur** | 60 s / 10 min / 30 min | Créature en fuite personnelle (60 s), Golden Wobbler (4 par heure), BOOP RUSH (90 s toutes les 10 min), MEGA SQUISH (toutes les 30 min), jauge du serveur | Un rendez-vous toutes les quelques minutes, sessions de plus de 10 min |
| **Boucle de renaissance** *(v2.0 : modifié)* | 12 min au début, puis 25 à 40 min de jeu (joueur de référence) | Atteindre l'objectif de taille → Grand Splorch → tout regrandit 2 fois plus vite, des Confettis, un déblocage nommé et visible à chaque Record R (§4.29) | Le plaisir de « recommencer plus vite et plus gros » |
| **Boucle d'Ascension** *(v2.0 : nouveau)* | 10 à 11 jours (référence), 4 à 5 jours (2 h par jour) | r = 15, 20, 24… → Jelly Ascend → croissance ×3 à chaque boucle, pour toujours, remontée rapide (Souvenir de gelée), halo et ciel (§4.27) | Un but de plusieurs jours qui ne fait rien perdre |
| **Boucle quotidienne** | 1 jour | Croissance hors ligne visible (jusqu'à 90 % de l'objectif : le Grand Splorch se fait en jeu), Nourrir Plop (jours au total, boost ×2 de 5 min), 3 objectifs du jour | Habitude J2-J7 |
| **Boucle hebdomadaire** *(v2.0 : modifié)* | 7 jours | Jelly Moon le samedi (et rattrapage le dimanche), 5 classements de la semaine, une nouvelle espèce par semaine (données), **piste de la semaine gratuite et 3 Défis de Splorch** (§7.5) | Pic du samedi, rendez-vous |
| **Boucle de collection** | jours → semaines | Squishydex (26 espèces, 234 mutations, badges d'étoiles), bonus de famille, Étagère à trophées, Fame | Profondeur J8-J28 |
| **Boucle sociale** | continue | Ranchs voisins, bonus d'amis, pet-sitting, poursuites, MEGA, jauge, cadeaux du Grand Splorch, emotes, applaudissements | Jeu entre amis, signal de classement |

### 2.3 Méta-progression *(v2.0 : réécrit)*

| Couche | Horloge | Ce qui progresse | Remis à zéro par le Grand Splorch ? | Par la Jelly Ascend ? |
|---|---|---|---|---|
| Ranch de la boucle | minutes | Pièces, Pot, Tapis à Goûter et Tapis Étoilé, décorations (sauf les gardées), Gants, École | **Oui** | **Oui** |
| Taille | minutes → heures | Taille de chaque squishy | **Oui** (chacun redevient taille 1) | **Oui** |
| Niveau de la boucle | heures | **r** : croissance ×2^r, objectif, prix ×3,5^r | Non (+1) | **Oui** (retour au Grand Splorch de départ, §4.27) |
| Enclos | heures → jours | Places d'enclos (4 → 18, 24 avec le pass), Lit douillet | Non | Non |
| Collection | jours | Squishies (espèce, mutation, étoiles), Squishydex, bonus de famille, Meilleurs Amis | Non | Non |
| Record | jours → semaines | **Record R** : familles débloquées, Cuve (qualité, vitesse, buses : donnée, jamais achetée), selles, paliers de ranch, Monuments ouverts, Plopettes, titres, Étagère à trophées | — | Non |
| Atelier | jours → mois | Confettis et les 9 lignes de l'Atelier de Big Plop, cosmétiques « Pour le plaisir » | Non | Non |
| Ascension | semaines | **A** : croissance ×3^A, prix de la boucle × F(A) (÷ 2 aux 4 premières Ascensions, × 0,32 jusqu'à A10, × 0,31 ensuite et × 0,29 aux Ascensions d'un Grand Splorch de plus), halo, ciel, titres | — | — (+1) |
| Social | semaines | Fame, jours de Plop, titres, classements, Carnet du Ranch | Non | Non |

### 2.4 Horloge commune (UTC, identique sur tous les serveurs) *(v2.0 : modifié)*

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

**Un seul grand spectacle à la fois** [`Events.SpectacleGap = 20`]. Les grands spectacles sont : BOOP RUSH, MEGA SQUISH, Grand Splorch, danse de Big Plop (jauge pleine). Deux grands spectacles sont toujours séparés d'au moins 20 s. Les horaires fixes le garantissent entre Rush, MEGA et Golden Wobbler (le Golden n'est pas un grand spectacle). Le Grand Splorch et la danse de Big Plop, déclenchés par les joueurs, attendent dans une **file du serveur**. Un Grand Splorch au plus toutes les 20 s par serveur, dans l'ordre d'arrivée. L'attente vaut donc **« place dans la file × 20 s + reste du grand spectacle en cours »** (un Rush dure jusqu'à 90 s, un MEGA 65 s) : avec deux joueurs devant soi pendant un Rush, c'est jusqu'à 90 + 2 × 20 = 130 s. Le HUD affiche la place et l'attente prévue (« 2e dans la file · ≈ 0:40 »), recalculées à chaque changement. Une fois dans la file, le Grand Splorch est **garanti** (§4.15).

*(v2.0)* La **Jelly Ascend** est un grand spectacle (10 s) : elle entre dans la même file ; un joueur n'a jamais qu'**un seul prestige** dans la file. Le **Petit Splorch** n'est pas un grand spectacle : il est appliqué tout de suite, hors file (§4.27). Un même joueur déclenche au plus une bannière « GRAND SPLORCH » toutes les 3 min (sinon une petite ligne). La **météo visuelle** (§5.6) tombe dans les seules fenêtres sans Rush ni MEGA : :08-:13 et :38-:43.

---

## 3. Les 5 premières minutes (FTUE) *(v2.0 : modifié)*

**Règles.** Pas de tutoriel écrit. Un chemin lumineux au sol, les gestes de Big Plop (la mascotte), et un mot court à côté du **glyphe de la touche** (4 mots au plus) : le glyphe de la manette du joueur (□, ○, R2, L2, △, stick gauche), ou la touche du clavier si le joueur joue au clavier. Glyphe de 64 px TV, mot de 40 px TV, posés au-dessus de l'objet concerné ou en bas au centre (§10.2). Jamais plus d'une consigne à l'écran. **Aucune étape ne peut bloquer** : si le joueur ne fait pas le geste demandé en 90 s, la consigne se range dans une petite pastille, Big Plop la remontre plus tard, et l'accueil continue (les naissances scriptées restent dues et ne se perdent pas). Une récompense ou un chiffre qui bouge au moins toutes les 15 s. Aucune fenêtre bloquante pendant les 60 premières secondes. Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé (la Boutique Robux reste cachée). Chaque étape numérotée est envoyée à `AnalyticsService:LogOnboardingFunnelStepEvent` (§16.1).

**Pendant l'accueil, l'horloge est réglée pour l'apprentissage** : la Cuve et les créatures en fuite suivent le script ci-dessous jusqu'à 5:00 de jeu, puis reprennent leurs règles normales (§4.9, §4.11). Les événements de serveur (Rush, MEGA, Golden) gardent leur horaire UTC : un Rush croise les 5 premières minutes d'environ 2 nouveaux sur 3. Ils restent donc **discrets pour le nouveau jusqu'à l'étape 9** (≈ 4:30) : aucune bannière, aucune vibration de sirène, teinte du ciel à 30 %, musique du Rush à −12 dB, bannières des autres mises en attente (jetées si elles ont plus de 30 s). Seule reste la petite pastille d'événement du HUD ; Big Plop la montre du doigt une seule fois, après l'étape 8. Pas de Wild Wobbler personnel avant l'étape 9 : la démonstration de Big Plop sert de première poursuite.

| Temps | Ce que voit et fait le joueur | Ce que fait le système | Étape |
|---|---|---|---|
| Chargement | Écran construit en code (`ReplicatedFirst`) : un Plop rebondit, 3 points animés, aucun texte long | Chargement du profil avec verrou de session (§12.6). En cas d'échec : écran « Ton ranch se réveille… » et bouton Réessayer, jamais de profil vide sauvegardé | — |
| 0:00 | Le personnage apparaît **dans son propre ranch**, face au Pot et au premier squishy. Les amis Roblox déjà sur le serveur ont le ranch voisin | `RanchService` attribue le ranch (à côté d'un ami s'il y en a un) | 1 « Chargé » |
| 0:00-0:10 | Big Plop, la mascotte, arrive en rebondissant et pose **ton petit Plop** (taille 1, ton Meilleur Ami n° 1) à 5 studs devant le joueur : il n'a pas besoin de marcher. Le compteur au-dessus de lui défile : 2, 3, 4… Au-dessus de Plop, le glyphe □ (E au clavier) et le mot « Presser » (étiquette du monde en px TV, jamais posée au sol, §10.2) ; un anneau au sol, décoratif, entoure Plop | Croissance +1/s. Le reste du HUD est caché : seul le compteur de pièces (0) est visible | — |
| ~0:10 | **Premier SPLORCH** : Plop s'écrase, rebondit, fontaine de pièces, « +10 » en gros, petite vibration (manette) | Récompense de pression `max(10, floor(22 × revenu))` = 10 (§4.7) | 2 « Première pression » |
| 0:10-0:20 | Deuxième pression possible à 0:18 (anneau qui se remplit sous Plop) : 20 pièces. Les flèches au sol vers la première dalle, **Tapis à Goûter, 20**, n'apparaissent que quand les pièces suffisent ; avant, l'étiquette de prix de la dalle montre une barre qui se remplit (« 10 / 20 »), jamais un refus | — | — |
| ~0:20 | Le joueur marche jusqu'à la dalle (si le stick n'a pas bougé depuis 4 s, le glyphe du stick gauche apparaît avec « Marcher ») et s'y arrête : un anneau blanc se remplit en 0,6 s (le serveur mesure ce temps, §4.6), puis le Tapis se construit en rebondissant. Plop passe à **+2/s** (le « +2 » flotte au-dessus de lui). **Première récompense en moins de 30 s** | Achat Tapis niveau 1 | 3 « Premier achat » |
| ~0:40 | La **Cuve à Gelée** se construit toute seule (gratuite). Sa première goutte éclot : « **Jumeau de Plop** ! », annoncé comme tel. Ce n'est pas un tirage au hasard | Naissance scriptée : Plop, 0 étoile, taille 1 | 4 « Cuve » |
| ~1:00 | Leçon de fusion. Invite « ○ Prendre » (Q au clavier) au-dessus du jumeau. Un cœur pulse sur Plop, qui attend déjà dans le Bassin (Big Plop l'y a posé). Trois pas, puis « □ Fusion ! » au bord du Bassin. SPLORCH géant, **une étoile apparaît**, le revenu saute. Taille ≈ (96 + 41) × 1,25 = 171 | Fusion (§4.10). Le joueur a compris : grandir, presser, fusionner | 5 « Première fusion » |
| ~1:30 | Le **Pot à Pièces** brille : le joueur marche dessus, gros chiffre (≈ 240). Deux nouvelles dalles s'allument : Tapis niveau 2 (80) et la première décoration, Clôture rebondissante (80) | Encaissement du Pot (§4.8) | 6 « Premier Pot » |
| ~2:00 | **Ta** créature en fuite saute de la Fontaine de Gelée, devant ton portail, marquée d'un anneau à ta couleur. Flèche au bord de l'écran, glyphe R2 avec « Bondir » (un bond qui atterrit près d'elle l'attrape tout seul), puis glyphe □ avec « Attraper » quand elle est à portée. Attrapée : tampon « NOUVEAU ! Mochi Mew » dans le Squishydex | Fuite personnelle scriptée : Mochi Mew, Commun | 7 « Première capture » |
| ~2:45 | **Premier vrai tirage** de la Cuve. Les probabilités apparaissent en barres simples sur la Cuve, avec l'étiquette « Nouveauté garantie (3) » : les 3 premiers tirages donnent une espèce que le joueur n'a pas encore (§4.9). Un tirage Rare ou mieux lance une bannière serveur | Tirage normal (qualité de la Cuve 1 = 1 + R, §4.9) | 8 « Premier tirage » |
| ~3:00 | Le HUD affiche l'horloge du prochain événement (« BOOP RUSH 2:00 »). Big Plop fait sa **démonstration** : il éternue devant ton portail (ATCHOUM) et s'enfuit en rebondissant. Le joueur le poursuit sans rien risquer et gagne un **bébé Plop** (10 % de la taille de son Plop). Son ranch porte le **bouclier débutant** pendant 15 min de jeu ; il est en mode Cozy tant qu'il n'a pas choisi. De retour au ranch, s'il n'a jamais changé de cible : glyphes L1 R1 avec « Choisir » pendant 4 s (clic au clavier-souris), une seule fois | Démonstration personnelle, toujours jouée (§4.21.6) | — |
| ~4:30 | Plop atteint la **taille 1 200** : une selle apparaît, glyphe L2 avec « Monter ». Il rebondit 1,4 fois plus vite. Une flèche mène à la place : statue du plus gros squishy du serveur, Boutique (vente de squishies), Autel de la Lune avec le compte à rebours du samedi, jauge du serveur | Seuil de selle (§4.12) | 9 « Première balade » |
| ~5:00 | Petite carte non bloquante (§10.3) : **3 objectifs du jour** (presser 30, attraper 2, fusionner 1) et « **Nourris Plop : Jour 1** » (avec le vrai nom du Meilleur Ami). Quand elle se range, la puce « Menu » du HUD apparaît avec le glyphe △ et la pastille « ! » : c'est la leçon du menu (△ ou croix ↓ ; M au clavier). Avant ce moment, le menu reste fermé : △ et croix ↓ ne font qu'un petit son `Bump`. Le HUD complet est affiché | Objectifs du jour 1 fixes (§7.4) | 10 « Objectifs » |
| ~12-15 min | Le plus gros squishy atteint **15 000** : « Grand Splorch prêt ! » | Objectif R0 (§4.15) | 11 « Premier Grand Splorch » |

*(v2.0)* **À 5:00, avec la leçon du menu** : la puce « Prochain achat » apparaît dans le HUD (§10.2) et l'entrée **Améliorations** dans le menu (sous Ranch) ; le **Fanion à ton nom** se pose dans le ranch (premier objet de Déco perso, §11.5). Les familles nouvelles s'ouvrent ensuite par le Record R (Gants et Atelier au premier Grand Splorch, Pip au 2e) : l'accueil ne change pas.

**Cible à 5:00** (vérifiée par la simulation, §4.24) : 3 à 4 squishies, au moins 1 fusion, au moins 1 capture, la première balade faite, et assez de pièces pour la dalle Enclos. À 5:00, les 4 places d'enclos de départ sont pleines : les naissances suivantes de la Cuve vont dormir dans la Boîte à dodo (bulle « Dodo » sur la Cuve, §4.9), où elles ne grandissent pas, et la dalle Enclos (1 200) devient le prochain objectif naturel.

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

### 4.1 Monnaies et scores *(v2.0 : modifié)*

*(v2.0 : modifié)* **Deux monnaies à dépenser** : les **pièces** (la boucle) et les **Confettis** (pour toujours, gagnés en jouant seulement, §4.26). Tout est calculé et gardé par le serveur.

| Ressource | Rôle | Sources | Puits | Remise à zéro |
|---|---|---|---|---|
| **Pièces** (Coins) | Construire le ranch de la boucle en cours | Revenu passif (Pot), pressions, combos, vente de squishies, récompenses d'événements, objectifs du jour. **Jamais vendues contre des Robux au lancement** (§8.3) | Dalles du ranch (Tapis, décorations), places d'enclos, Lit douillet. **Jamais une chance** (§8.1) | Oui, à chaque Grand Splorch |
| **Confettis** *(v2.0)* | Acheter l'Atelier de Big Plop (confort et départ rapide, pour toujours) et des cosmétiques | Grand Splorch (3 + r si nouveau Record R, r compté jusqu'à 20 ; 1 pour un Petit Splorch), Grand Splorch sauté grâce au Tremplin (1), Jelly Ascend (+20), retour au record (+10), prime de record (+10 au-delà de R20), enclos plein (+25), piste de la semaine (34 par semaine), maîtrise d'espèce (+25). **Jamais vendus** | Atelier (654), « Pour le plaisir » (2 770, dont 24 objets de Déco perso, et les objets des costumes) | **Jamais** (ni Grand Splorch ni Ascension) |
| **Fame** (célébrité) | Score permanent, bonus de revenu | Pendant le Rush, 30 par jour au plus : être boopé (+1), Wild Wobbler attrapé (+1, Rush ou Cozy), capture « Héros » (+2). Puis : relâcher un squishy (+1), Grand Splorch (+5, **50 par jour au plus**, v2.0), Jelly Ascend (+20, v2.0), participer au MEGA (+1) | Aucun (on ne la dépense pas) | Jamais |
| **r** (niveau de la boucle) *(v2.0)* | Économie de la boucle | +1 par Grand Splorch ou Petit Splorch | — | À la Jelly Ascend (retour au départ, §4.27) |
| **Record R** *(v2.0)* | Prestige, déblocages | Le plus haut r jamais atteint | — | Jamais |
| **A** (Jelly Ascend) *(v2.0)* | 2e prestige | +1 par Jelly Ascend (60 au plus) | — | Jamais |
| **Jours de Plop** | Fidélité | +1 par jour UTC où l'on nourrit son Meilleur Ami au bol | — | Jamais (total, jamais une série) |

**Sources et puits de pièces (valeurs exactes)**

| Source | Montant |
|---|---|
| Revenu passif | Somme des revenus des squishies du ranch (§4.3), versée dans le Pot |
| Pression | `max(10, floor(22 × revenu du squishy))`, ×2 si PERFECT, +10 % par PERFECT de suite (max +50 %) (§4.7) |
| Combo de fusion | Étape k : `20 × k ×` revenu du squishy obtenu (§4.10) |
| Vente d'un squishy | 60 s de son revenu (minimum 10) (§4.13) |
| Créature dorée vue de près, MEGA réussi | 60 s du revenu du joueur (§4.11, §4.22) |
| Cadeau de Grand Splorch | 60 s du revenu du joueur, 10 cadeaux en pièces par jour, ensuite 10 s (§4.15) |
| Capture « Héros » de son propre squishy en fuite | 120 s du revenu du joueur (§4.21) |
| Squishy boopé rendu au propriétaire | 60 s du revenu du propriétaire (§4.21) |
| Joueur Rush à 30 studs au plus d'une capture du Rush | 20 s de son revenu (§4.21.3) |
| Pet-sitting (presser chez un ami) | Le propriétaire : la pression normale (100 reçues par jour) ; le visiteur : 2 s de son propre revenu, ×2 si PERFECT (100 par jour) (§6.4) |
| Applaudir un Grand Splorch | 10 s du revenu (10 récompensés par jour) (§6.7) |
| Objectifs du jour | 3, 6 ou 10 min de revenu (§7.4) |
| Hors ligne | 25 % du revenu de départ (28 %, 31 % avec le Pot de nuit de l'Atelier ; réglage de la porte d'économie, docs/04 §21), plafonné (§4.19) |
| Plopettes *(v2.0)* | Une pression normale (sans PERFECT ni série) × Gants, toutes les 12 à 6 s par Plopette (§4.28) |
| Cadeau du Splorch *(v2.0)* | Le prix du prochain niveau du Tapis de la nouvelle boucle (1, puis 2 ou 3 niveaux avec l'Atelier) (§4.15) |
| Pluie d'étoiles (Jelly Ascend d'un autre) *(v2.0)* | 120 s du revenu, 3 par jour au plus (§4.27) |

« Revenu du joueur » = la somme des revenus de ses squishies dans les enclos, multiplicateurs compris, au moment de la récompense. Les récompenses « en secondes de revenu » restent ainsi justes à tous les niveaux. P (×2 Pièces) et B (boost) sont **déjà dans ce revenu** : une récompense de « N s de revenu » vaut N × ce revenu, jamais multipliée une deuxième fois par P ou B (§8.2). Les minimums fixes (10 pièces par pression ou par vente) ne sont multipliés ni par P ni par B.

### 4.2 Nombres géants *(v2.0 : modifié)*

**Stockage.** Les tailles et les pièces sont des nombres `number` de Luau (double précision, jusqu'à ≈ 1,8e308). Sous 1e15, les pièces restent des entiers exacts (`floor` après chaque calcul). Au-dessus, l'arrondi du double est accepté (il ne se voit pas à l'écran). Le serveur borne toute valeur à `[0 ; 1e300]` et refuse `NaN` et l'infini avant chaque écriture (les DataStores refusent ces valeurs en JSON).

**Affichage** (`Shared/Logic/BigNumber.abbreviate(n, lang)`, le seul formateur des nombres du jeu) :
- moins de 10 000 : le nombre entier, avec séparateur des milliers (EN « 9,876 » ; FR « 9 876 » avec espace fine insécable U+202F) ;
- à partir de 10 000 : **3 chiffres significatifs, tronqués** (jamais arrondis vers le haut : 999 999 s'affiche 999K, pas 1.00M), puis le suffixe ;
- **mêmes suffixes internationaux dans les deux langues** (K, M, B, T, Qa…) : ce sont ceux que les enfants voient dans les autres jeux et sur les vidéos, et une comparaison avec la statue ou un ami reste juste d'une langue à l'autre. À 3 m, « Md », « Bn » et « Bd » se ressemblaient, et « B » voulait dire 1e9 en anglais mais « Bn » 1e12 en français ;
- en français : virgule décimale et espace fine insécable avant le suffixe (« 1,23 M », « 4,56 B ») ;
- *(v2.0, critique M11)* suffixes jusqu'à **1e93** (« Tg ») : le joueur de 2 h par jour dépasse 1e36 pièces vers le jour 62 et atteint 1e75 au jour 140 (mesuré, §4.24.1) ; la notation « 1.23e96 » (EN) / « 1,23e96 » (FR) ne sert qu'au-delà de 1e96, où aucun profil simulé n'arrive avant le jour 140 ;
- les bannières de jalons écrivent le mot entier dans la langue du joueur (EN « 1 TRILLION! », FR « 1 000 MILLIARDS ! »).

| Puissance | Suffixe (EN et FR) | Mot EN | Mot FR (fiche et info-bulle) |
|---|---|---|---|
| 1e3 | K | thousand | mille |
| 1e6 | M | million | million |
| 1e9 | B | billion | milliard |
| 1e12 | T | trillion | mille milliards (billion) |
| 1e15 | Qa | quadrillion | million de milliards (billiard) |
| 1e18 | Qi | quintillion | milliard de milliards (trillion) |
| 1e21 | Sx | sextillion | trilliard |
| 1e24 | Sp | septillion | quadrillion |
| 1e27 | Oc | octillion | quadrilliard |
| 1e30 | No | nonillion | quintillion |
| 1e33 | Dc | decillion | quintilliard |
| 1e36 | Ud | undecillion | sextillion |
| 1e39 | Dd | duodecillion | sextilliard |
| 1e42 | Td | tredecillion | septillion |
| 1e45 | Qad | quattuordecillion | septilliard |
| 1e48 | Qid | quindecillion | octillion |
| 1e51 | Sxd | sexdecillion | octilliard |
| 1e54 | Spd | septendecillion | nonillion |
| 1e57 | Ocd | octodecillion | nonilliard |
| 1e60 | Nvd | novemdecillion | décillion |
| 1e63 | Vg | vigintillion | décilliard |
| 1e66 | Uvg | unvigintillion | undécillion |
| 1e69 | Dvg | duovigintillion | undécilliard |
| 1e72 | Tvg | trevigintillion | duodécillion |
| 1e75 | Qavg | quattuorvigintillion | duodécilliard |
| 1e78 | Qivg | quinvigintillion | trédécillion |
| 1e81 | Sxvg | sexvigintillion | trédécilliard |
| 1e84 | Spvg | septenvigintillion | quattuordécillion |
| 1e87 | Ocvg | octovigintillion | quattuordécilliard |
| 1e90 | Nvvg | novemvigintillion | quindécillion |
| 1e93 | Tg | trigintillion | quindécilliard |

Exemples : 12 345 → EN « 12.3K », FR « 12,3 K » ; 4 560 000 000 → EN « 4.56B », FR « 4,56 B » ; 7,8e12 → EN « 7.80T », FR « 7,80 T ».

*(v2.0)* **Une couleur par famille de suffixes**, la même partout : K-M blanc, B-T or (255, 215, 90), Qa-Qi rose (255, 150, 200), Sx à Dc cyan (120, 230, 255) (Sx et Sp ne se confondent plus à 3 m), *(critique M11)* Ud à Nvd vert (140, 235, 150), Vg à Tg lilas (205, 175, 255). **Un formateur par sorte de nombre** : `BigNumber.abbreviate` pour les montants ; `Format.multiplier` (×1,175, toujours 3 décimales ; croissance ×14, entier) ; `Format.percent` (+5 %, entier) ; `Format.seconds` (9,0 s, 1 décimale) ; `Format.roman` (**décor seulement** : arche, titre du spectacle, drapeaux ; critique M9). Les Confettis s'affichent en entier brut jusqu'à 99 999, puis avec `BigNumber.abbreviate`. **Largeurs réservées** pour la plus longue valeur formatée : la plus large de « 1,00e300 » et « 99,9 Nvvg » (mesurées à 40 px : 141 et 157 px, dans les 192 px de la colonne Prix) : rien ne change de taille quand un nombre grandit (§10.8, règle 7). En français, la fiche d'un squishy et l'info-bulle de la taille montrent aussi le mot entier (« 7,80 T = 7 800 milliards »). Décision de la version 1.3 (ancienne question 3 du Journal de révision).

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

### 4.3 Le squishy : données et formules *(v2.0 : modifié)*

Un squishy est une ligne de données dans le profil (§12.6) : `{ s = espèce 1-26, m = mutation 0-9, st = étoiles 0-5, z = taille, bf = emplacement de Meilleur Ami 0-3, lk = verrou, o = tenue }`. Il est dessiné par le client à partir de ces valeurs (§5.2).

**Croissance** *(v2.0 : modifié)* (par seconde, identique pour tous les squishies du ranch) :

```
croissance = 1 × 2^r × 3^A × (1 + niveauTapis [0 à 20]) × (1 + 0,10 × familleJellyComplète)
               × Souvenir(Record R − r)     -- Souvenir de gelée (§4.27) : 3 si l'écart ≥ 3, puis 2, 1,5, et 1,25 sur la 1re boucle record
               × B
```

- `niveauTapis` de 0 à 20 : 12 niveaux du Tapis à Goûter, puis 8 du Tapis Étoilé, plafonnés par r (§4.6) ; A = nombre de Jelly Ascend (§4.27) ; `familleJellyComplète` vaut 1 si les 4 espèces de la famille Jelly sont dans le Squishydex (§4.17) ;
- `B` = 2 si un boost ×2 est actif (Wobble Party de la jauge, Squish Party, boost personnel de Nourrir Plop), sinon 1. Les boosts ×2 ne se cumulent jamais entre eux (§4.25). Le joueur de référence passe environ 36 % de son temps de jeu en ×2 (simulation, §4.24) : un boost reste un moment, pas l'état normal. *(Critique m8)* Cette cible vaut pour les séances de 30 min et plus : à 20 min par jour, c'est 45 %, à 10 min par jour 70 % (le bol de 5 min y pèse plus) ; c'est assumé et seulement rapporté (§4.24.1).

**Revenu** *(v2.0 : modifié)* (pièces par seconde, pour un squishy dans un enclos) :

```
revenu = 0,02 × rareté × taille × mutation × (1 + 0,5 × étoiles) × A_bonus × (1 + 0,01 × Monuments) × P × B
A_bonus = 1 + 0,05 × décorations    (18 au plus → +90 % de bonus ; effet réel affiché, voir plus bas)
      + 0,10 × amisPrésents         (4 au plus → +40 %)
      + 0,01 × min(300, Fame)       (+300 % au plus)
      + bonus de l'Étagère à trophées (+8 % au plus par espèce : +208 % avec les 26 du lancement, §4.16)
      + 0,01 × pages dorées du Squishydex (+1 % par espèce : +26 % au lancement, §4.17)
P = 2 avec le pass ×2 Pièces, sinon 1
```

Exemple : un Plop Commun de taille 1 000, sans mutation, 1 étoile, sans bonus : 0,02 × 1 × 1 000 × 1 × 1,5 = **30 pièces/s**. Le r n'apparaît pas dans le revenu : il agit par la taille (croissance ×2^r), ce qui revient au facteur « rebirth » du concept sans compter deux fois.

*(v2.0)* L'additif « A » de la v1.3 s'appelle **`A_bonus`** pour ne pas le confondre avec le nombre d'Ascensions. Les **Monuments** sont un multiplicateur à part (+1 % chacun, 10 au plus) : ajouté dans `A_bonus` (entre 2 et 7 au jour 28), « +1 % » n'aurait valu que +0,14 à +0,5 %. *(Critique M8)* Les **décorations** restent dans `A_bonus` (les jalons des 14 premiers jours de la v1.3 en dépendent : à 10 décorations et sans autre bonus, un multiplicateur × (1 + 0,02 × décorations) donnerait × 1,2 au lieu de × 1,5, soit −20 % de revenu dans les premières boucles) ; **l'écran n'affiche donc jamais « +5 % »** mais l'effet **réel** du prochain niveau sur le revenu total, calculé par `UpgradeMath.effect` (le même calcul que le serveur) : « Revenu total +1,2 % » (0,05 ÷ `A_bonus`). Tous les facteurs nouveaux sont multiplicatifs ou bornés, jamais des bonus additifs qui ne servent plus en fin de courbe.

**Pression** *(v2.0)* : `floor(max(Balance.Press.Min [10], Balance.Press.Seconds [22] × revenu) × (PERFECT ? 2 : 1) × (1 + 0,10 × min(5 + superSérie, série)) × (Kitty ? 1,10 : 1) × (1 + 0,025 × niveauGants))` (§4.7).

**Prix** *(v2.0)* : `floor(base × croissanceDuPrix^L × 3,5^r × F(A))` pour les familles de la boucle (§4.6). **Aucune puissance dans le code** : tables par multiplications successives (§4.6). **Bornes** : `MaxR = 400`, `MaxA = 60`.

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
- **Autres sources** : Golden Wobbler (Doré garanti), Goutte de Lune (Lunaire garanti, §4.23), bébés du MEGA (chances de mutation × 2), bébés du Rush (la mutation de l'original si elle vaut ×5 ou moins, Doré ou plus faible ; sinon tirée avec des chances × 2 : une mutation rare ne passe jamais d'un compte à l'autre, §4.21.3), cadeaux du Grand Splorch (sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible).
- **Étiquette « 1 sur X »** lors d'une naissance rare : calculée en direct = 1 / (chance de la rareté × chance de la mutation) aux réglages du moment, arrondie à 2 chiffres significatifs. Jamais un chiffre inventé. Exemple au départ (R = 0, qualité 1, buses 0) : Flop Plop = 1 / (0,74 × 0,000005) ≈ **1 sur 270 000**.
- **Naissance rare** : les mutations Arc-en-ciel, Glitch et Flop sont fêtées comme une naissance Légendaire, quelle que soit la rareté de l'espèce : ralenti, bannière serveur, clip automatique, grande étiquette « 1 sur X » (§9.4). Le verrou automatique les protège (§4.13).

### 4.6 Le ranch, ses dalles et les 9 familles d'amélioration *(v2.0 : réécrit)*

Le ranch se construit de deux façons : en s'arrêtant sur les **dalles lumineuses** du sol (le geste du début, gardé tel quel) et depuis l'**écran Améliorations** (§10.7), qui achète tout, y compris les familles qui n'ont pas de dalle. Chaque dalle porte son icône sur le disque ; son prix et son niveau sont écrits sur une étiquette au-dessus d'elle, en px TV, visible à 20 studs ou moins (texte du monde, §10.2). Un achat se construit en cascade (§9.4). Les dalles apparaissent dans l'ordre : une nouvelle dalle s'allume quand la précédente a été achetée une fois. **Une dalle trop chère ne refuse jamais** : quand on s'y arrête, la barre de l'étiquette montre ce qui manque (« 1,2K / 3K ») avec un petit son doux (`Bump`), sans secousse rouge ni son `Error`.

**Comment l'achat sur une dalle est détecté (règle robuste, inchangée).** Jamais par un événement physique `Touched`. Le serveur regarde, à chaque tick de 10 Hz, la **position validée** du joueur (§12.8) : il est « sur » une dalle à **2,5 studs** au plus de son centre, et il en « sort » au-delà de **3,5 studs**. **On achète en restant 0,6 s sur la dalle** [`Balance.Tiles.DwellSeconds = 0.6`] : un anneau blanc se remplit, puis l'achat part. Sortir avant la fin, porter un squishy ou être dans un autre maintien annule sans rien dépenser. **Un achat par entrée** : pour le niveau suivant, on sort et on revient, ou on presse □ « Acheter » (E au clavier) tant qu'on est dessus. Les dalles sont à 8 studs au moins de tout autre point d'action (§11.2) ; leurs pièces sont ancrées et non solides.

**Trois lois, valables pour toute famille présente et future**
1. **Les pièces et les Confettis n'achètent jamais une chance**, une naissance, un tirage ni un saut de minuteur (§8.1, étendu à l'Atelier). La Cuve (qualité, vitesse, buses) s'améliore toute seule avec le **Record R** (§4.9).
2. **Les familles de la boucle donnent des pièces, de la place ou du confort, pas de la croissance.** Seuls le Tapis à Goûter (et son prolongement, le Tapis Étoilé), r, les Ascensions (×3 chacune) et le Souvenir de gelée (×3 pendant les remontées, §4.27) changent la croissance. C'est ce qui garde les jalons du §4.24.
3. **Toute famille passe la porte `EconomyPacing`** (§4.24) avant d'exister dans le jeu.

**Prix** : `floor(base × croissanceDuPrix^L × 3,5^r × F(A))` pour les familles de la boucle (Tapis, Tapis Étoilé, Décorations, Gants, École), où L = niveau actuel (le premier achat coûte la base), r = niveau de Grand Splorch de la boucle et A = nombre de Jelly Ascend [`Balance.Tiles.RScale = 3.5`, `Balance.Ascend.PriceByA` : une liste de 60 facteurs, 0,5 de A1 à A4, 0,32 de A5 à A10, puis 0,31, et 0,29 aux Ascensions qui demandent un Grand Splorch de plus (A11, A19, A27…, réglage de la porte d'économie, docs/04 §21) ; le dernier facteur vaudrait au-delà de la liste]. *(v2.0 révisé, critique B1)* **Les prix de la boucle sont divisés par 2 à chacune des 4 premières Ascensions, puis multipliés par 0,32 à chacune des suivantes** (0,31 dès A11, 0,29 aux Ascensions d'un Grand Splorch de plus : réglage de la porte d'économie, §4.27) : avec la croissance × 3 de chaque Ascension, une boucle rapporte 3 fois moins de pièces au même r (elle dure 3 fois moins), et chaque Ascension ajoute 4 r de boucles record ; avec un facteur fixe de 0,5, le pouvoir d'achat d'une boucle record baissait encore de × 1,5 par Ascension (le joueur de 2 h par jour à 36,7 % puis 62,5 % de temps « sans but » aux jours 85-140, mesure de la critique) ; avec 0,32 à partir de A5, il reste le même d'une Ascension à l'autre (Tapis 12 atteint entre 0,58 et 0,87 de chaque boucle record de A1 à A38, mesuré, §4.24.1). L'Enclos et le Lit douillet ont des prix fixes ; les Monuments suivent leur propre règle (plus bas). **Pourquoi 3,5^r** (inchangé) : d'une boucle à l'autre, la croissance double, l'objectif est multiplié par 2,6 et la collection s'enrichit ; le revenu d'une boucle monte d'environ × 3,5 par r.

**Écrit en maths, calculé sans puissance.** Les formules sont des notations. `Logic/UpgradeMath` et `Logic/Prestige` n'appellent jamais `^`, `math.pow` ni `math.exp` (la puissance n'est pas garantie identique au bit près entre les consoles, le PC et le serveur ; un écart d'un bit devient une pièce après `floor`). Les tables de prix, d'objectifs et de croissance sont construites par **multiplications successives dans un ordre fixe**, de la même façon sur le client et sur le serveur (test statique, §10.8 règle 5). **Bornes** : `Balance.Prestige.MaxR = 400`, `MaxA = 60` ; tout prix est borné à 1e300 par `Formulas.clampCoins` ; à r = MaxR, le Grand Splorch n'est plus proposé (« Record absolu ! ») ; à A = MaxA, la Jelly Ascend non plus.

#### 4.6.1 Le catalogue

| # | Famille (FR / EN) | Onglet | Ce qu'elle fait | Niveaux | Monnaie et prix (r = 0, A = 0) | Au Grand Splorch | Ouverture | Effet au maximum |
|---|---|---|---|---|---|---|---|---|
| 1 | Tapis à Goûter / Snack Mat | Ranch (+ dalle) | Grossir plus vite | 12 | `20 × 4,5^L` | Remis à zéro (sauf Tapis de départ) | Dès le début | Croissance ×13 |
| 1b | Tapis Étoilé / Star Mat (même ligne) | Ranch | Grossir encore plus vite | 8 (13 → 20) | `20 × 4,5^11 × 1,25^(L − 11)`, L = 12 … 19 | Remis à zéro | Plafond **par r de la boucle** : niveau 13 à r ≥ 6, 14 à r ≥ 7, 15 à r ≥ 8, 16 à r ≥ 9, 17 à 20 à r ≥ 10 | Croissance ×21 |
| 2 | Décorations / Decorations | Ranch (+ dalle) | Gagner plus | 18 | `80 × 2,2^L` | Remises à zéro, sauf les décorations gardées (12 au plus) | Dès le début | Bonus +90 % dans `A_bonus` (effet réel affiché, §4.3) |
| 3 | Enclos / Pens | Ranch (+ dalle) | Plus de place | 14 | `1 200 × 2,2^L`, fixe | Gardé | Dès le début | 18 places (24 avec le pass) |
| 4 | Lit douillet / Cozy Bed | Ranch (+ dalle) | Dormir plus longtemps | 1 | 25 M, fixe | Gardé | Record R ≥ 3 | Hors ligne 8 h → 12 h |
| 5 | Gants Moelleux / Squishy Gloves | Ranch | Presser plus fort | 40 | `2 000 × 1,55^L` | Remis à zéro | Record R ≥ 1 | Pressions ×2,0 |
| 6 | École des Plopettes / Plopette School | Plopettes | Des aides plus rapides | 20 | `20 000 × 1,75^L` | Remise à zéro (les Plopettes restent) | Record R ≥ 2 | Une pression d'aide toutes les 6 s par Plopette |
| 7 | Monuments / Monuments | Ranch | Embellir pour toujours | 10 | Plus bas | Gardés | Record R = 6, 8, 10 … 24 | +10 % de revenu, 10 grands décors |
| 8 | Atelier de Big Plop / Big Plop's Workshop | Atelier | Confort et départ rapide, pour toujours | 9 lignes, 21 niveaux (+ « Pour le plaisir » : 11 cosmétiques et 24 objets de Déco perso) | Confettis (§4.26) | Gardé | Record R ≥ 1 | §4.26 |
| — | Cuve à Gelée (lecture seule) | Atelier | — | 8 | Donnée par le Record R | Gardée | Record R 0 → 7 | Qualité 8, vitesse 10, 5 buses |
| — | Paliers de ranch (lecture seule) | Atelier | — | 6 | Donnés par le Record R | Gardés | Record R 1, 3, 5, 10, 15, 20 | Ranch transformé (§11.5) |

**Total des niveaux achetables** : 12 + 8 + 18 + 14 + 1 + 40 + 20 + 10 + 21 = **144** (v1.3 : 45 ; docs/09 : 136 ; v2.0 avant la critique : 146, les niveaux 3-4 de « Déco qui reste » sont retirés), plus 35 objets « Pour le plaisir » en Confettis (11 cosmétiques, 24 objets de Déco perso). **Tout est disponible au lancement** (décision par défaut n° 6) ; chaque famille s'ouvre par la progression (colonne « Ouverture »), jamais par une date.

**Tapis à Goûter** (prix à r = 0, × 3,5^r × F(A) ; effet = croissance du ranch)

| Niveau acheté | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 20 | 90 | 405 | 1 822 | 8 201 | 36,9 K | 166 K | 747 K | 3,36 M | 15,1 M | 68,1 M | 306 M |
| Croissance | ×2 | ×3 | ×4 | ×5 | ×6 | ×7 | ×8 | ×9 | ×10 | ×11 | ×12 | ×13 |
| Palier | Nappe pique-nique | | | Biscuit sablé | | | Bonbon arc-en-ciel | | | Gelée dorée | | |

Somme des 12 niveaux : 394 M. **T12** = prix du 12e niveau dans la boucle en cours = 306 455 660 × 3,5^r × F(A) : c'est l'unité de mesure de la santé de l'économie (§4.24).

**Tapis Étoilé** (niveaux 13 à 20, seulement après le Tapis 12, sur la même ligne) : prix = `floor(20 × 4,5^11 × 1,25^(L − 11) × 3,5^r × F(A))`, L = niveau actuel (12 à 19). Chaque niveau coûte **plus** que le précédent, Tapis 12 compris (test « coûts strictement croissants »).

| Niveau acheté | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|
| Prix (r = 0, A = 0 ; tronqué comme à l'écran) | 383 M | 478 M | 598 M | 748 M | 935 M | 1,16 B | 1,46 B | 1,82 B |
| Croissance | ×14 | ×15 | ×16 | ×17 | ×18 | ×19 | ×20 | ×21 |
| Ouvert dans la boucle à | r ≥ 6 | r ≥ 7 | r ≥ 8 | r ≥ 9 | r ≥ 10 | r ≥ 10 | r ≥ 10 | r ≥ 10 |
| Palier | Étoilé | | | | Galaxie | | | |

Cas exacts de `UpgradeMath.spec` : niveau 13 = 383 069 575 et niveau 20 = 1 826 618 076 à r = 0 et A = 0 ; niveau 13 = 105 671 556 317 044 à r = 10 et A = 0 ; niveau 13 = 52 835 778 158 522 à r = 10 et A = 1. Somme des niveaux 13-20 : 7,60 B (24,8 T12). Le plafond suit **r de la boucle**, pas le Record R : c'est un plafond d'économie, pas un déblocage (sinon un joueur juste après une Ascension achèterait une croissance ×21 à r = 0 pour presque rien). L'écran le montre avec un état à part (« Boucle 7 »), jamais avec un cadenas (§10.7.6).

**Pourquoi la v2.0 ouvre le Tapis Étoilé plus tôt** (mesuré, §4.24) : avec l'ouverture de docs/09 (2 niveaux à r = 10, 12, 14, 16), le joueur de référence n'en achetait presque aucun (médiane 1,5 niveau à r = 10-11, 0 de r = 14 à 19) et le joueur de 2 h par jour était bloqué au plafond avec des pièces en trop à la fin de chaque boucle. Ouvert dès r = 6 (un niveau par r jusqu'à r = 9, puis les 4 derniers à r = 10), il est acheté (référence : médiane 7 à 8 niveaux par boucle de r = 10 à 15). Un prolongement jusqu'au niveau 40 a été essayé : il ne changeait rien au temps « sans but » de l'assidu (16,9 % contre 16,6 % aux jours 8-14) et ajoutait 20 niveaux, des textes et des décors : écarté.

**Décorations** (prix à r = 0, × 3,5^r × F(A) ; effet = revenu de tout le ranch) : inchangées (18 niveaux, 80 × 2,2^L, +5 % de bonus chacune dans `A_bonus`, somme 97,1 M). *(Critique M8)* L'écran montre l'**effet réel** du prochain niveau sur le revenu total (« Revenu total +1,2 % », `UpgradeMath.effect`, §4.3), jamais « +5 % » : au jour 28, une décoration vaut en vrai +0,7 à +2,5 %. Trois ensembles nommés de 6 : **Jardin bonbon** (1-6), **Parc nuage** (7-12), **Fête foraine** (13-18) ; un ensemble complet allume une guirlande (décor seulement). Les 18 décorations dans l'ordre d'apparition : Bouncy Fence, Candy Lamp, Jelly Flowers, Gumdrop Path, Cloud Bench, Lollipop Trees, Marshmallow Rocks, Bubble Pond, Sprinkle Arch, Pudding Hut, Rainbow Kite, Star Windmill, Jellybean Swing, Cupcake Fountain, Gummy Bridge, Cotton Candy Tree, Donut Carousel, Moon Telescope. **Décorations gardées** au Grand Splorch : toujours les premières dans l'ordre d'apparition, jamais un choix : 3 au Record R 8, 3 de plus au Record R 14, puis +3 par niveau de la ligne « Déco qui reste » de l'Atelier (2 niveaux), **12 au plus** *(critique M3 : avec 18 gardées, le joueur de 2 h par jour n'achetait plus que 0,3 décoration par boucle et son temps « sans but » montait de 6 points)*. Une décoration remise à zéro laisse un **socle de souvenir** (§11.5).

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 80 | 176 | 387 | 851 | 1 874 | 4 122 | 9 070 | 19,9 K | 43,9 K | 96,5 K | 212 K | 467 K | 1,02 M | 2,26 M | 4,97 M | 10,9 M | 24,0 M | 52,9 M |
| Bonus déco (dans `A_bonus`) | +5 % | +10 % | +15 % | +20 % | +25 % | +30 % | +35 % | +40 % | +45 % | +50 % | +55 % | +60 % | +65 % | +70 % | +75 % | +80 % | +85 % | +90 % |

**Enclos** (prix fixes ; effet = nombre de places) : inchangé (14 niveaux, 1 200 × 2,2^L, somme 62,2 M). **Places offertes** aux Record R 2, 6, 11 et 16 : +1 niveau de la dalle, dans les 14 niveaux (jamais au-delà de 18 places, 24 avec Grand Ranch) ; si la dalle est déjà au maximum, **+25 Confettis** à la place, avec le message « Enclos déjà plein : +25 Confettis ». Paliers d'aspect : **Herbe tendre** (4-9 places), **Coussins moelleux** (10-17), **Coussins nuage** (18-24).

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 1 200 | 2 640 | 5 808 | 12,7 K | 28,1 K | 61,8 K | 136 K | 299 K | 658 K | 1,44 M | 3,18 M | 7,01 M | 15,4 M | 33,9 M |
| Places | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |

**Lit douillet** : 25 M, dès le Record R 3, hors ligne 8 h → 12 h ; il se construit en **lit à baldaquin** avec un mobile de 3 lunes.

**Gants Moelleux** (s'ouvrent au Record R 1 ; prix à r = 0, × 3,5^r × F(A) ; effet = récompense de chaque pression, × (1 + 0,025 × niveau))

| Niveau | 1 | 5 | 10 | 15 | 20 | 25 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 2 000 | 11,5 K | 103 K | 924 K | 8,26 M | 73,9 M | 661 M | 1,02 B | 1,58 B | 2,46 B | 3,81 B | 5,91 B | 9,17 B | 14,2 B | 22,0 B | 34,1 B | 52,9 B |
| Pressions | ×1,025 | ×1,125 | ×1,250 | ×1,375 | ×1,500 | ×1,625 | ×1,750 | ×1,775 | ×1,800 | ×1,825 | ×1,850 | ×1,875 | ×1,900 | ×1,925 | ×1,950 | ×1,975 | ×2,000 |

(Les niveaux 2-4, 6-9… suivent la même formule ; table complète des 40 prix dans `Config/Upgrades`, cas exacts dans `UpgradeMath.spec` : niveau 30 = 661 681 881 et niveau 40 = 52 962 225 282 à r = 0.) Somme des niveaux 1-30 : 1,86 B (6,1 T12) ; 1-40 : 149 B. À r = 1, le niveau 1 coûte 7 000 pièces, à peu près le Tapis niveau 4. **+2,5 % par niveau se sent peu** : le retour passe donc par **9 paliers nommés**, chacun avec la couleur de l'éclaboussure et du « +N » : **Coton** (1-4, blanc), **Velours** (5-9, pêche), **À pois** (10-14, rose à pois), **Rayés** (15-19, menthe et blanc), **Guimauve** (20-24, pastel), **Nuage** (25-29, ciel), **Arc-en-ciel** (30-34), **Étoilés** (35-39, bleu nuit à points), **Dorés** (40, or). Les Gants comptent pour les pressions dans son ranch et pour celles des Plopettes ; pas pour le pet-sitting (pas de ferme entre comptes) ni pour le MEGA (des points, pas des pièces). **Pourquoi 40 niveaux (docs/09 : 30)** : le joueur de 2 h par jour finissait les 30 niveaux au milieu de chaque longue boucle et attendait ensuite sans rien à acheter ; les niveaux 31-40 coûtent 3 à 173 T12 et occupent la fin de ses boucles (mesuré, §4.24).

**École des Plopettes** (dès le Record R 2 ; prix à r = 0, × 3,5^r × F(A) ; effet = intervalle entre deux pressions de chaque Plopette, 12 − 0,3 × niveau)

| Niveau | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Prix | 20,0 K | 35,0 K | 61,2 K | 107 K | 187 K | 328 K | 574 K | 1,00 M | 1,75 M | 3,07 M | 5,38 M | 9,42 M | 16,5 M | 28,8 M | 50,5 M | 88,4 M | 154 M | 270 M | 473 M | 829 M |
| Intervalle | 11,7 s | 11,4 s | 11,1 s | 10,8 s | 10,5 s | 10,2 s | 9,9 s | 9,6 s | 9,3 s | 9,0 s | 8,7 s | 8,4 s | 8,1 s | 7,8 s | 7,5 s | 7,2 s | 6,9 s | 6,6 s | 6,3 s | 6,0 s |

Somme : 1,93 B (6,3 T12). Paliers de tablier : **Blanc** (1-4), **Fleuri** (5-9), **Rayé** (10-14), **Arc-en-ciel** (15-19), **Doré** (20). Les Plopettes elles-mêmes : §4.28.

**Monuments** : grands objets en formes simples, construits **derrière le fond du ranch** sur 10 emplacements fixes (§11.5), visibles du ranch, de la rue et des voisins ; ils restent pour toujours. Effet : **+1 % de revenu chacun, en multiplicateur à part** (`revenu × (1 + 0,01 × Monuments)`, +10 % au plus) : le « +1 % » affiché est vrai. Surtout décoratif.

| # | Monument (FR / EN) | Ouverture (Record R) | Prix avant toute Ascension |
|---|---|---|---|
| 1 | Moulin à Gelée / Jelly Mill | 6 | 1,69 T |
| 2 | Statue de Big Plop / Big Plop Statue | 8 | 20,7 T |
| 3 | Grande Roue Guimauve / Marshmallow Wheel | 10 | 254 T |
| 4 | Château de Pudding / Pudding Castle | 12 | 3,11 Qa |
| 5 | Bateau-Bonbon / Candy Boat | 14 | 38,1 Qa |
| 6 | Fusée Sucette / Lollipop Rocket | 16 | 466 Qa |
| 7 | Jardin Suspendu / Hanging Garden | 18 | 5,71 Qi |
| 8 | Horloge Bonbon / Candy Clock | 20 | 70,0 Qi |
| 9 | Pyramide de Dragées / Jellybean Pyramid | 22 | 857 Qi |
| 10 | Cascade de Sirop / Syrup Falls | 24 | 10,5 Sx |

**Prix d'un Monument** : `3 × 306 455 660 × 3,5^(R d'ouverture) × 3,5^(r − Record R)`, sans le facteur d'Ascension. Avant toute Ascension, r = Record R : le prix est fixe (3 T12 au moment où il s'ouvre : un but de plusieurs boucles, puis abordable). Après une Ascension, le prix suit la boucle en cours : c'est le puits naturel des pièces en trop des remontées. Mesuré : 2 Monuments au jour 7, 5 au jour 14, 8 au jour 28, 10 au jour 56 pour le joueur de référence.

**Ordre d'apparition des dalles** (inchangé) : Tapis → (Cuve, gratuite) → (Bassin, gratuit) → Tapis 2 + Bouncy Fence → Enclos (quand les enclos sont pleins) → autres décorations → Lit douillet (Record R ≥ 3). Après un Grand Splorch, toutes les dalles déjà découvertes restent visibles. Les Gants, l'École, le Tapis Étoilé, les Monuments et l'Atelier n'ont pas de dalle : la puce « Prochain achat » du HUD et l'écran Améliorations les présentent (§10.2, §10.7).

**Ce qui ne s'achète jamais** : la Cuve et son niveau, le Bassin, la Fontaine de Gelée, le Pot, l'Étagère à trophées, le bol, les Plopettes elles-mêmes (sauf Plume, en Confettis gagnés), les paliers de ranch. Ils sont donnés par le jeu et ne sont jamais remis à zéro.

### 4.7 Presser (SPLORCH) et PERFECT *(v2.0 : modifié)*

- **Geste** : touche d'action principale (□ à la manette, E au clavier, ou clic sur le squishy) sur le squishy **ciblé** de son ranch, à 10 studs au plus. Le serveur ne connaît pas la flânerie du squishy (dessinée par le client) : il mesure la distance **à plat (XZ)** entre la position validée du joueur et la **place** du squishy (`WorldLayout`), avec 2 studs de tolérance, car le client ne le fait jamais flâner à plus de 2 studs de sa place (§9.3). Même règle depuis la monture. Le jeu choisit la cible lui-même (règle exacte au §10.4) : les squishies prêts passent avant ceux en recharge, et après une pression la cible passe au prochain squishy prêt en 0,15 s. **Presser a sa touche, Prendre a la sienne** (○ / Q, §4.10) : un enfant qui martèle □ ne prend jamais un squishy par erreur. L'invite « □ Presser » est dessinée par le jeu, en grand pour la télé, et la touche est liée par `ContextActionService` ; on n'utilise **pas** de `ProximityPrompt`, dont le choix de cible, la ligne de vue et la liaison de touche appartiennent au moteur et ne se testent pas hors de Roblox (§10.4).
- **Recharge** : 8 s par squishy [`Balance.Press.Cooldown`]. Un anneau se remplit sous le squishy ; prêt, il est un peu gonflé et brille.
- **Récompense** *(v2.0 : modifié)* : `floor(max(10, 22 × revenu) × (PERFECT ? 2 : 1) × (1 + 0,10 × min(5 + superSérie, série)) × (familleKittyComplète ? 1,10 : 1) × (1 + 0,025 × niveauGants))`, où superSérie = 0 à 2 (ligne « Super Série » de l'Atelier) et niveauGants = 0 à 40 (×2,0 au plus, §4.6).
- **PERFECT** : chaque squishy rebondit au repos avec une période de 1,2 s, calée sur `Clock.now()` et un décalage propre (`hash(UserId du propriétaire, uid)` : l'uid n'est unique que dans un profil, et le squishy « 1 » de chaque joueur ne doit pas rebondir en même temps que les autres), donc identique côté client et côté serveur. La fenêtre PERFECT va de **0,08 s avant à 0,20 s après le sommet** du rebond (0,28 s, soit 23 % du cycle). Elle est décalée vers le « tard » parce que le joueur réagit à une image qui arrive en retard : télé familiale 50 à 150 ms (mode Jeu souvent coupé), plus 1 à 2 images de rendu et la liaison sans fil de la manette. La même règle vaut pour tous les appareils, sans bonus déclaré par le client. Un petit anneau blanc se resserre et touche le corps au sommet.
- **Série PERFECT** : chaque PERFECT de suite ajoute +10 % (max +50 % à 5 de suite ; +60 % et +70 % avec la Super Série de l'Atelier, v2.0). Une pression non PERFECT remet la série à 0, sans aucune punition (la récompense de base reste). 6 s sans pression remettent aussi la série à 0. Le son monte d'un demi-ton à chaque marche.
- **Vérification serveur** : le client envoie `Press(uid, tClient)`. Le serveur accepte `tClient` s'il est dans `[maintenant − 0,35 s ; maintenant + 0,05 s]`, sinon il prend `maintenant`. Il calcule la phase du rebond à `tClient`. Au pire, un tricheur obtient ce qu'obtient un joueur adroit (×2) : c'est borné et accepté. C'est aussi pourquoi **aucun classement ne compte les PERFECT** (§6.9).
- **Jauge du serveur** : +1 par pression **PERFECT** seulement ; une pression normale ne compte pas (§4.23).
- Débit maximal accepté : 12 pressions/s par joueur (au-delà, ignorées sans message).

### 4.8 Le Pot à Pièces *(v2.0 : modifié)*

- Le revenu passif s'accumule dans le Pot (calcul paresseux, §12.3). Le montant flotte au-dessus du Pot.
- **Encaisser** : marcher à 5 studs au plus du Pot (8, 11 puis 14 studs avec l'Aimant à pièces de l'Atelier, v2.0) (position vérifiée par le serveur à chaque tick). Pas de limite de contenu en ligne : le Pot ne fait jamais perdre de pièces.
- **Pass Pot automatique** : le Pot s'encaisse tout seul toutes les 5 s, où que soit le joueur. Confort seulement.
- Hors ligne : le Pot reçoit 25 % du revenu (28 % puis 31 % avec le Pot de nuit de l'Atelier, v2.0 ; réglage de la porte d'économie, docs/04 §21), dans la limite hors ligne (§4.19).
- *(v2.0)* **Le Pot montre son contenu** : tas en 4 états selon les secondes de revenu qu'il contient, matériau qui suit le Record R (cuivre, argent, doré, cristal) (§11.5).

### 4.9 La Cuve à Gelée *(v2.0 : modifié)*

- **Fonctionnement** : la Cuve se remplit (niveau de gelée visible) pendant l'intervalle, puis une goutte tombe et éclot en 2 s dans la première place d'enclos libre, **sinon dans la Boîte à dodo** (une bulle « Dodo » s'affiche sur la Cuve ; le nouveau-né y dort et ne grandit pas tant que le joueur ne lui fait pas de place). Gratuit. La goutte n'attend dans la Cuve (« Plein ! », minuteur arrêté) que si les enclos **et** la Boîte à dodo sont pleins. Même règle que les captures (§4.14) : le rythme ne dépend plus d'un rangement manuel qu'un enfant de 8 ans ne connaît pas (sans lui, la simulation de la critique technique tombait à 54 tampons au jour 7 au lieu de 94). La Cuve ne tourne que si le joueur est en ligne.
- **Niveau de la Cuve, donné par le Record R** *(v2.0 : précisé)* : jamais acheté, ni avec des pièces ni avec des Robux. Il monte tout seul à chaque nouveau Record R et n'est jamais remis à zéro, **même par une Jelly Ascend** (dans ce paragraphe et dans le tirage des familles débloquées, « R » = Record R). Ses 3 axes se voient sur la Cuve (anneaux, agitateur, buses, §11.5).

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
- **Prendre et lancer** : « Prendre » (○ à la manette, Q au clavier) : le squishy ciblé se pose sur la tête du joueur (marche normale). Le portage est un **état du serveur**, pas un objet physique soudé au personnage : le client dessine le squishy sur la tête. Il se termine tout seul (le squishy retourne à sa place) si le joueur meurt, réapparaît, sort de son ranch (passe le portail), ouvre un panneau, monte sur sa monture, quitte le serveur ou, *(critique m23, comme le code v1.3)*, après **300 s** de portage (`Balance.Carry.SafetySeconds`, délai de sûreté : « chaque état a un délai et une sortie »). Pendant le portage : □ = « Lancer » seulement à 12 studs ou moins du Bassin (sinon aucune invite □) ; ○ / Q = « Poser » (il retourne à sa place) ; Bondir et Monter sont ignorés (son `Bump`, aucune vibration). L'invite du Bassin dit « **Fusion !** » si un jumeau y attend, sinon « Poser dans le Bassin ». Un joueur porte un seul squishy à la fois. Après la leçon de fusion de l'accueil, l'invite « Prendre » n'est plus qu'une petite deuxième ligne sous « Presser ».
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
- Attraper : □ à **5 studs** au plus (le serveur accepte jusqu'à 6,5 studs, mesurés à plat, **à l'instant où le joueur a appuyé**, §12.5), ou un bond qui atterrit à 5 studs au plus (capture automatique, §4.12).
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
- **Monter / descendre** : L2 (R au clavier), n'importe où. La monture saute vers le joueur (petit pop depuis le ranch). Le serveur règle trois valeurs fixes par selle et rien d'autre : `WalkSpeed` (22,4), `JumpHeight` (table ci-dessus) et `HipHeight` = valeur de base + 0,75 × diamètre affiché (+4,3 / +5,3 / +6 studs). À chaque montée et descente, le serveur donne aussi au contrôle de déplacement la hausse de la racine et la hauteur de saut de la selle (§12.8) : un cavalier honnête, à chaque selle, court et saute sans jamais être signalé. Le client dessine la monture sous le personnage. Pas de soudure physique, pas de siège (`Seat`), pas d'animation qui décide de quoi que ce soit : monter et descendre sont des états du serveur. La monture disparaît toute seule à la mort, à la réapparition, en entrant dans le Bassin ou en prenant un squishy ; on remonte d'un appui.
- La vitesse est la même pour toutes les selles : la monture est un plaisir et un signe de statut, pas un avantage acheté. Toutes les selles sont gagnées par la taille ; le pack Selles et Traînées ne change que l'apparence.
- On descend tout seul pour « Prendre » un squishy, nourrir son Meilleur Ami au bol ou entrer dans le Bassin. On peut presser, attraper et booper depuis sa monture : toutes les portées d'action (presser 10, attraper 5 et 6,5, booper 8, Pot 5, bol 8, MEGA 20) se mesurent **à plat (XZ)**, et l'écart vertical se mesure depuis les **pieds** du joueur (racine − hauteur debout − hausse de la monture), jamais depuis la racine.

**Bondir** (R2, Maj au clavier) : petit élan de **12 studs en 0,35 s**, recharge **4 s**.
- **Un bond scripté, pas une impulsion physique** : le client déplace son personnage le long d'un arc fixe (12 studs au sol, sommet à 2,5 studs), image par image, et s'arrête devant le premier obstacle solide (un rayon vers l'avant, contre la liste des solides du §11). La longueur ne dépend donc ni du frottement, ni de la fréquence d'image, ni d'une collision qui rebondit.
- **Visée automatique sur la position future** : le trajet des créatures est connu du client (`SeededPath`), qui vise la position qu'aura la créature à l'atterrissage, `pos(t + 0,35)`. Il vise si cette position est à **16 studs** au plus, dans un cône de **±40°** autour de la direction du stick gauche (au clavier, des touches de déplacement ; au repos, de la direction du personnage). **Jamais selon la caméra.** Sinon, le bond part droit devant. Le marqueur de cible ne change que si une autre créature est 20 % plus proche.
- **Capture automatique à l'atterrissage** si la créature est à 5 studs au plus (8 pour le propriétaire de sa propre fuite du Rush, §4.21.2). Le serveur la tente lui-même à `tClient + 0,35 s` (l'instant du bond chez le joueur, §12.5), avec sa tolérance (6,5 ; 9,5). Il calcule le point d'atterrissage **à partir de la géométrie du bond** (position validée au départ + direction × 12 studs, raccourci par le même rayon contre les solides), **pas** à partir de l'endroit où la physique a posé le personnage : le résultat est identique sur le client et sur le serveur, et testable hors de Roblox. Un seul bouton suffit donc pour attraper, à la manette comme au clavier.
- □ / Attraper reste possible, avec un **tampon d'entrée de 0,25 s** : un appui juste avant d'entrer à portée compte.
- Le client fait le bond tout de suite (sensation immédiate) et envoie `Leap(dirX, dirZ, tClient)` ; si la recharge est respectée, le serveur accorde au contrôle de déplacement un **crédit de 12 studs** sur 0,35 s, rétroactif jusqu'à 0,3 s avant la réception du message (les positions du bond arrivent parfois avant lui), au plus un toutes les 4 s (§12.8). Un joueur qui attrape avec □ juste après l'atterrissage n'est donc jamais bloqué par une dette du bond.

### 4.13 Vendre, ranger et relâcher

- **Vendre** (Boutique de la place, ou panneau Ranch → Vendre) : 60 s du revenu actuel du squishy (minimum 10). Refusé pour un Meilleur Ami ou un squishy verrouillé. **Maintien de 0,6 s** pour un Rare ou mieux, ou pour un squishy muté. **Confirmation en 2 étapes** pour un Épique ou mieux, ou une mutation Doré ou mieux (×5 et plus) : la 2e étape montre la carte du squishy avec son « 1 sur X » (« Ce Wibble Doré : 1 sur 1 200 ! »).
- **Ranger** (panneau Ranch, un seul bouton) : propose de vendre d'un coup les squishies Communs et Peu communs, 0 étoile, sans mutation, non verrouillés, ni Meilleur Ami ni monture, dont l'espèce est déjà tamponnée. Le plus gros de chaque espèce est toujours gardé. Un aperçu liste ce qui part (« Vendre 14 squishies = 3,2K ») ; on valide par un maintien de 0,6 s. Rien ne part sans cet aperçu.
- **Relâcher** (panneau Ranch → Relâcher, ou à la **Prairie des copains** sur les collines) : maintien de 0,6 s pour **chaque** relâche, même un Commun ; confirmation en 2 étapes comme pour la vente pour un Épique+ ou une mutation Doré+. Ton positif : « Il part vivre dans les collines ! ». Le squishy fait un signe et part en rebondissant. **+1 Fame** (20 Fame au plus par jour de cette façon). Il ne revient pas dans le ranch, mais les 12 derniers squishies relâchés **restent visibles dans la Prairie des copains** (pour leur ancien propriétaire seulement) et lui font coucou quand il passe.
- **Verrou** (cadenas) : un squishy verrouillé ne peut être ni vendu, ni relâché, ni rangé, ni lancé par erreur. Il peut fusionner si le joueur le choisit (à la main). **Verrou automatique à la naissance** pour toute rareté Légendaire ou mieux et toute mutation Galaxie ou mieux (×8 et plus), cadenas visible ; le joueur peut l'enlever.

### 4.14 Enclos, Boîte à dodo, Boîte aux lettres *(v2.0 : modifié)*

| Lieu | Places | Grandit et rapporte ? | Boopable ? |
|---|---|---|---|
| Enclos (dont le Bassin) | 4 au départ, +1 par niveau de la dalle Enclos (18), **+6 avec le pass Grand Ranch (24 au plus, jamais plus)** | Oui | Oui (sauf protections) |
| Boîte à dodo (Dodo Box) | 60 | Non (ils dorment) | Non |
| Boîte aux lettres (cadeaux) | 20 | Non | Non |

- *(v2.0)* **Places offertes** aux Record R 2, 6, 11 et 16 (+1 niveau de la dalle Enclos, jamais au-delà de 18 places) ; enclos déjà plein : +25 Confettis (§4.6).
- Une naissance de la Cuve va dans un enclos libre, sinon dans la Boîte à dodo ; la goutte n'attend dans la Cuve que si les deux sont pleins (§4.9).
- Une créature attrapée ou un bébé reçu va dans un enclos libre, sinon dans la Boîte à dodo, sinon dans la Boîte aux lettres. Si les trois sont pleines : le bébé devient 60 s de revenu, avec un message clair. Jamais une perte silencieuse.
- Échanger un squishy entre enclos et Boîte à dodo : panneau Ranch, 2 gestes.
- **24 squishies affichés au plus par ranch** (16 ranchs × 24 = 384 sur le serveur), avec niveaux de détail (§5.2, §12.9).

### 4.15 Grand Splorch (renaissance) *(v2.0 : modifié)*

**Condition** : le plus gros squishy du joueur atteint l'objectif de son niveau R. Pour **entrer dans la file** (§2.4), le joueur doit être dans son ranch, ne rien porter et n'avoir **aucun squishy en fuite** (« Attends que Wibble rentre ! » : une fuite du Rush en cours au moment où les tailles repartent à 1 donnerait un bébé faux à l'attrapeur). Ces conditions ne sont vérifiées **qu'à l'entrée dans la file** : ensuite, le Grand Splorch est **garanti**, rien n'est revérifié au départ, il n'y a pas de second maintien, et le joueur peut sortir du ranch (pour sa créature en fuite, par exemple). Pendant l'attente, **aucun de ses squishies ne vient à la clôture** (aucune fuite ne peut commencer), et le squishy qui va s'envoler attend en tremblant : il ne peut être ni boopé, ni vendu, ni relâché, ni fusionné. Si le joueur porte un squishy au départ, celui-ci est posé tout seul.

| R → R+1 | Objectif (taille du plus gros) | R → R+1 | Objectif |
|---|---|---|---|
| 0 → 1 | **15 000** | 10 → 11 | 210 M |
| 1 → 2 | 39 000 | 11 → 12 | 550 M |
| 2 → 3 | 100 000 | 12 → 13 | 1,4 B |
| 3 → 4 | 260 000 | 13 → 14 | 3,7 B |
| 4 → 5 | 690 000 | 14 → 15 | 9,7 B |
| 5 → 6 | 1,8 M | 15 → 16 | 25 B |
| 6 → 7 | 4,6 M | 16 → 17 | 65 B |
| 7 → 8 | 12 M | 17 → 18 | 170 B |
| 8 → 9 | 31 M | 18 → 19 | 440 B |
| 9 → 10 | 81 M | 19 → 20 | 1,1 T |
| R ≥ 20 | objectif précédent × 2,6, arrondi à 2 chiffres significatifs | | |

La table vit en configuration [`Balance.Splorch.Targets`] : elle suit `15 000 × 2,6^R` arrondi à 2 chiffres significatifs [`Balance.Splorch.BeyondMult = 2.6`], et la simulation peut l'ajuster ligne par ligne. La version 1.2 suivait × 2,7 : avec les prix des dalles × 3,5^R, la croissance hors ligne arrêtée à 90 % et les boosts calculés d'après les règles (§4.24), × 2,6 garde R = 10 au jour 7 et R = 20 au jour 28.

**Écran d'aperçu obligatoire**, fait pour des enfants qui lisent peu :
1. En haut, **3 grandes tuiles « Tu gagnes »** *(v2.0 : modifié)* : « **Croissance ×2** » (plus « pour toujours » : décision par défaut n° 2, §4.27) ; le **déblocage de ce Record R** (une image et 2-3 mots, §4.29), ou « Cadeau du Splorch » s'il est déjà gagné ; « **+13 Confettis** » (3 + r) pour un Grand Splorch, « **Petit Splorch : +1 Confetti** » pour un Petit Splorch. La Fame (+5) passe dans « Détails ».
2. Une petite animation avant/après : le squishy redevient petit, puis regrandit très vite.
3. S'il reste des pièces (Pot compris) **et qu'une ligne gardée au Grand Splorch est payable** (Enclos, Lit douillet, Monuments) : une ligne rouge « **Tu vas perdre 1,2 M pièces** » et un bouton « **Dépenser d'abord** » qui ouvre l'**écran Améliorations** sur l'onglet Ranch (v2.0, §10.7.1), sélection sur cette ligne. *(v2.0 révisé, critique M16)* Sinon, une phrase neutre « Tes pièces deviennent le cadeau du Splorch » et aucun bouton : jamais un bouton qui mène à une impasse.
4. *(v2.0 révisé, critique m24 : une seule décision sur l'écran principal)* Le choix du squishy qui s'envole est dans « **Détails** » : par défaut, le plus gros qui n'est pas un Meilleur Ami (s'ils le sont tous, le plus gros).
5. Le bouton à **maintenir 1,5 s** (✕ à la manette) ; la case « Filmer mon Grand Splorch » est dans « Détails ». Une fois dans la file, l'aperçu se ferme et le HUD montre la place et l'attente (« 2e dans la file · ≈ 0:40 », §2.4).

Le détail en deux colonnes « Tu gardes » / « Repart de zéro » et le prochain objectif sont derrière un bouton « **Détails** ». Aucune monnaie n'est vendue au lancement (§8.3) : les pièces qui repartent de zéro ont toujours été gagnées en jeu, et l'aperçu le dit avant. Rien ne part par erreur.

| Gagné | Repart de zéro | Gardé |
|---|---|---|
| Croissance ×2 (×2^(r+1)) ; **3 + r Confettis** si nouveau Record R (1 sinon) ; **cadeau du Splorch** ; le déblocage nommé du Record R (§4.29) ; **Cuve meilleure** (qualité +1 jusqu'à 8, vitesse +2 jusqu'à 10, buses +1 jusqu'à 5, §4.9) ; à R = 1 : famille Axolo ; à R = 3 : famille Bunny, 2e Meilleur Ami, Lit douillet ; à R = 5 : famille Spiky ; à R = 10 : 3e Meilleur Ami ; +5 Fame ; titres à R = 5, 10, 15, 20 | Pièces, Pot, Tapis à Goûter et Tapis Étoilé (sauf le Tapis de départ de l'Atelier), décorations (sauf les décorations gardées), Gants Moelleux, École des Plopettes ; la **taille** de chaque squishy (retour à 1) | Tous les squishies (espèce, mutation, étoiles, tenue, verrou), niveau de la Cuve, selles gagnées (on remonte tout de suite), places d'enclos, Lit douillet, Boîte à dodo, Boîte aux lettres, Squishydex, bonus de famille, Fame, jours de Plop, Étagère à trophées, Meilleurs Amis, passes et achats « Pour toujours », réglages, statistiques ; *(v2.0)* Record R, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, Enclos, décorations gardées |

**Le spectacle** (7,5 s, détail au §9.4) : le squishy choisi s'envole vers la place, gonfle et éclate au ralenti au-dessus du MEGA pad en un grand nuage de confettis de gelée. Une pluie de pièces et de bébés tombe sur **chaque joueur du serveur** (Cozy compris ; en version courte pour un spectateur qui a vu un spectacle complet il y a moins de 3 min, voir plus bas). Puis **le squishy sort du nuage, tout petit, fait coucou et rejoint le héros en rebondissant** ; la caméra du héros le suit et le texte dit « **Plop est là ! ×2 !** » (avec son vrai nom ; v2.0 : plus « pour toujours »). Il garde tout, sauf sa taille. L'enfant voit son squishy revenir, pas seulement exploser. Bannière serveur. Forte vibration pour le héros. Capture vidéo proposée (§9.5).

**Le cadeau du Splorch** *(v2.0)* (gratuit pour tous dès le premier Grand Splorch) : juste après l'éclatement, une pluie de pièces dorées tombe dans le Pot. Elle vaut **le prix du prochain niveau du Tapis** dans la nouvelle boucle (1 niveau ; 2 puis 3 avec la ligne de l'Atelier) : l'enfant rachète le Tapis dans les 30 s et sent la vitesse doublée. **Plafond** : le Tapis de départ et le cadeau ensemble ne donnent jamais plus de **6 niveaux** du Tapis au début d'une boucle.

**Chantier de Big Plop** *(v2.0)* (7,5 → 11,5 s, seulement si un élément nouveau arrive dans le ranch) : un petit Big Plop casqué donne 3 coups de maillet, la pièce se construit en cascade, étiquette « Nouveau : Phare de gelée » 3 s. **Non bloquant** : le joueur marche pendant ce temps ; la caméra ne bouge jamais seule ; aucune flèche de bord ; ensuite une carte non bloquante « Nouveau : … » (8 s, puis rangée dans la pastille « ! »). Délai : 4 s, coupure dure à 6 s.

**Plafonds sociaux** *(v2.0)* : Fame du Grand Splorch +5, **50 par jour au plus** (`Balance.Caps.fameSplorch = 50`) ; un même joueur déclenche **au plus une bannière « GRAND SPLORCH » toutes les 3 min** (sinon une petite ligne). Le Petit Splorch ne donne ni Fame, ni bannière, ni cadeaux aux autres (§4.27).

**Cadeaux pour les autres joueurs** (payés par le jeu, jamais pris au héros) : 60 s de leur revenu (10 cadeaux en pièces par jour et par joueur, ensuite 10 s : sur un serveur de nouveaux joueurs, il y a jusqu'à un Grand Splorch par minute) + **1 bébé** de l'espèce qui s'est envolée ; si elle est Épique ou mieux, le bébé est l'espèce Peu commune de sa famille (Wibble pour un Secret), pour que le choix du squishy ne fasse pas pleuvoir des Mythiques (taille = 5 % de leur plus gros squishy, minimum 1 ; 0 étoile ; sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible). 10 bébés de Grand Splorch au plus par jour et par joueur (ensuite, les pièces seulement). Réglage « Recevoir les cadeaux » (activé par défaut).

**Spectacle complet ou version courte, pour chaque spectateur.** Sur un serveur plein de nouveaux joueurs, il y a environ un Grand Splorch par minute ; chacun imposait aux 15 autres une bannière, une secousse, une capsule avec vibration et la puce APPLAUDIR. Pour un même spectateur, le **spectacle complet** (capsule qui tombe, secousse, vibration `catch`, puce APPLAUDIR) a lieu **au plus une fois toutes les 3 min** [`Balance.Splorch.FullShowGap = 180`] ; sinon, **version courte** : petite bannière, cadeau compté directement (pièces et bébé dans l'enclos, la Boîte à dodo ou la Boîte aux lettres, avec un message), sans capsule, sans secousse, sans vibration, sans APPLAUDIR. Le héros, lui, a toujours le spectacle complet.

**Applaudir** : chaque autre joueur qui a la version complète voit une puce APPLAUDIR pendant 8 s (croix → à la manette, F au clavier), jamais pendant une poursuite, un maintien ou une fenêtre ouverte. Voir §6.7.

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

Maximum au lancement : 26 × 8 % = +208 %. Le bonus se compte **par espèce** : chaque espèce publiée ensuite ajoute sa place sur l'étagère (+8 % au plus). Les records sont gardés dans un tableau dense, une case par espèce (§12.6).

### 4.17 Le Squishydex *(v2.0 : modifié)*

- **26 pages d'espèces** (tampon de l'espèce, forme normale) et **234 entrées de mutation** (26 espèces × 9 mutations). Total : 260 tampons. Plus 130 **badges d'étoiles** (★1 à ★5 atteint, par espèce).
- Une entrée est tamponnée dès que le joueur possède un squishy qui la remplit (naissance, capture, bébé, fusion, cadeau). Elle reste même si le squishy part.
- Fiche d'espèce : nom, famille, rareté, aspect, mutations trouvées (silhouettes grises pour les autres), meilleur exemplaire, taille record.
- **Page dorée** : les 8 mutations hors Lunaire d'une espèce trouvées → la page devient dorée, +1 % de revenu (additif dans A). La mutation Lunaire est en plus : elle pose un petit croissant d'argent sur la page, sans bonus. Rater les séances de la Lune n'empêche donc aucune page dorée.
- **Bonus de famille** (les 4 espèces de la famille tamponnées), **gagné pour toujours** : il est noté dans le profil au moment où il est gagné (`dex.fam`, §12.6), et une espèce ajoutée plus tard ne le retire jamais (pilier P2). Règle de contenu : les espèces de la semaine (§7.6) ne rejoignent jamais une famille déjà complète ; elles forment de **nouvelles familles de 4** (une famille par mois, son bonus est décidé avec le contenu et passe par la simulation), ou restent **sans famille**, comme les Secrets. Une nouvelle famille entre dans la Cuve dès R = 5 ; avant, on la trouve par les bébés.

| Famille | Bonus permanent |
|---|---|
| Jelly | +10 % de croissance |
| Kitty | +10 % de pièces par pression |
| Froggy | Créature en fuite toutes les 50 s au lieu de 60 |
| Axolo | +1 place dans le Bassin de Fusion (6) |
| Bunny | Intervalle de la Cuve −10 % |
| Spiky | Limite hors ligne +1 h |

- **Jalons** (tampons d'espèces + de mutations) : 10 → titre « Little Collector » ; 25 → couleur de selle Menthe ; 50 → traînée Bulles ; 75 → titre « Squishologist » ; 100 → drapeau de ranch Squishydex ; 130 → couleur de selle Lavande ; 160 → thème de ranch « Moonlit » ; 200 → titre « Dex Master » ; 260 → Squishydex doré et emote couronne. Tous gratuits, tous cosmétiques.
- *(v2.0)* **Maîtrise d'espèce** : une fiche à 3 cases par espèce : ★5, Page dorée (8 mutations hors Lunaire), Trophée Cristal (taille record ≥ 1e12) ; quand les 3 sont faites, la fiche brille et les 25 Confettis arrivent tout seuls (§4.26), avec une carte « Maîtrise ! » : aucune touche à presser, comme les paliers de la piste et du Carnet ; si les Confettis ne peuvent pas être donnés à ce moment, la maîtrise attend et arrive plus tard *(lot A4, décision D13)* ; compteur « Maîtrises 3 / 26 » ; **un seuil ne bouge jamais** quand une espèce arrive (champ `mastery`, ensemble de bits). **Jalons de taille géante** (record de taille de n'importe quelle espèce) : 1e15 selle « Cosmique », 1e18 traînée « Étoiles filantes », 1e21 **Squishy-Soleil** (couronne de rayons sur la silhouette du ranch), 1e24 titre « Gardien du Soleil » (« Sun Keeper »).
- Onglet **Guide** : toutes les probabilités (Cuve par niveau, mutations, Golden, MEGA, Wild Wobblers, cadeaux), les compteurs de la protection contre la malchance, les règles du BOOP RUSH.

### 4.18 Fame *(v2.0 : modifié)*

- Sources : la **Fame du Rush**, 30 par jour au plus en tout : squishy boopé puis rendu (+1), capture « Héros » (+2), Wild Wobbler attrapé (+1, partagé ou personnel, en mode Rush comme en mode Cozy). Puis : relâcher (+1, 20 par jour au plus), Grand Splorch (+5), participer à un MEGA SQUISH avec au moins 10 points (+1). Un joueur Cozy atteint donc le plafond du jour aussi vite qu'un joueur Rush (jusqu'à 3 Wild Wobblers par Rush) : le mode sûr n'est jamais moins rentable.
- Effet : +1 % de revenu par point, jusqu'à 300 points (+300 %). Au-delà, la Fame continue de monter pour le prestige (affichée sous le panneau du ranch).
- **Au lancement**, la Fame n'est créditée que si le propriétaire est sur le serveur (c'est toujours le cas : seuls les présents sont boopables). La lignée complète (bébés nés partout) est dans la réserve non planifiée (v2.0, §17.2).

### 4.19 Hors ligne *(v2.0 : modifié)*

- Calculé une seule fois au chargement : `durée = clamp(Clock.unix() − lastOnline, 0, limite)`.
- **Croissance hors ligne** : chaque squishy des enclos grandit de `croissance sans boost × 30 % × durée` [`Balance.Offline.GrowthShare = 0.3`], **et la croissance hors ligne du ranch s'arrête dès que le plus gros squishy des enclos atteint 90 % de l'objectif de Grand Splorch en cours** [`Balance.Offline.StopAt = 0.9`] (s'il y était déjà, rien ne grandit hors ligne). Comme toutes les tailles suivent le compteur de croissance du ranch (§12.3), c'est un seul plafond sur ce compteur. Les derniers 10 % se font en jeu, en 5 à 10 min : le Grand Splorch, avec son spectacle et ses cadeaux pour le serveur, reste un moment de la session. Avec les valeurs de la version 1.2, environ 9 Grands Splorch sur 20, et presque tous ceux de R = 6 à R = 11 (jours 3 à 10), devenaient prêts pendant l'absence : jouer faisait à peine avancer le prestige, et le suivi « Grand Splorch » du HUD n'était presque jamais atteint en jeu.
- **Pièces hors ligne** : le Pot reçoit `revenu au départ (sans boost) × 25 % × durée`.
- **Limite** *(v2.0 : modifié)* : 8 h ; 12 h avec le Lit douillet (acheté avec des pièces dès le Record R 3, gardé pour toujours) ; +1 h avec la famille Spiky ; +1 h par niveau du Sac de nuit de l'Atelier (3 au plus) : **16 h au plus**. Aucun achat Robux ne change cette limite.
- *(v2.0)* **La croissance hors ligne laisse toujours au moins 2 min de jeu** : elle s'arrête aussi quand il ne manque plus que **120 s de croissance maximale de la boucle** (Tapis et Tapis Étoilé au plafond de r, boost ×2) pour atteindre l'objectif, si c'est plus tôt que 90 % [`Balance.Offline.MinPlaySeconds = 120`]. Sans cette règle, après plusieurs Ascensions, une boucle commencée la veille pouvait finir 13 à 30 s après la connexion (mesuré, §4.24).
- **Écran de retour** (§7.2) : « Mochi Mew a grossi de +X pendant ton absence ! » (le vrai nom du Meilleur Ami n° 1, sinon du plus gros), et il est réellement plus gros. Si le plus gros a atteint 90 % de l'objectif, l'écran le dit (« Presque prêt pour le Grand Splorch ! ») ; s'il l'avait déjà atteint en jeu à la session précédente, « Grand Splorch prêt ! ».

### 4.20 Nourrir Plop, objectifs du jour, carte « Plop a sommeil »

- **Nourrir Plop** (nom du système, hérité du concept) : un grand bol dans le ranch. Le bol nourrit **ton Meilleur Ami n° 1** (au début, ton premier Plop) ; les textes écrivent son vrai nom (« Nourris Mochi Mew »). Une fois par jour UTC, maintenir □ **2 s** devant le bol : le Meilleur Ami accourt et mange (nom nom ; l'animation continue 3 s sans qu'on maintienne), le compteur de jours monte de 1 et un **boost personnel ×2 de 5 min** commence (§7.3). Un maintien de 5 s était long pour de petites mains sur une DualSense (§14). Les paliers comptent le **total de jours**, jamais une série : rater un jour ne fait rien perdre. « Jour 42 » flotte au-dessus du ranch. Paliers et récompenses : §7.3.
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
| Sirène (−10 s) | Le ciel vire au rose, musique de gloussements, une vibration (manette, §10.5), bannière « BOOP RUSH dans 10 ! ». Pour un nouveau avant l'étape 9 de l'accueil : version discrète (§3) |
| Début (:X5:00) | Dans chaque ranch boopable, jusqu'à **4 squishies curieux** éligibles viennent s'appuyer à la clôture, côté rue (choisis au hasard, renouvelés toutes les 20 s) ; **2 seulement** si ce ranch a été boopé au Rush précédent |
| Booper | Un joueur Rush, depuis la rue, **maintient □ 2,5 s** sur le nez d'un squishy à la clôture (8 studs au plus). **5 s** si le propriétaire est à 25 studs au plus de sa clôture (s'il arrive pendant le maintien, le temps restant double). Lâcher, s'éloigner à plus de 8 studs ou une règle qui devient fausse = annulé. Le temps est mesuré par le serveur : un client qui n'envoie jamais « lâché » ne bloque rien, le maintien finit ou s'annule au plus tard 0,5 s après sa fin prévue |
| ATCHOUM | Le squishy éternue (nuage pastel brillant, jamais de morve), saute la clôture et fait un **premier bond de 20 studs à l'opposé du boopeur**, puis rebondit dans la ville sur un **chemin calculé par le serveur** (§12.5). Le propriétaire reçoit **aussitôt une flèche** au bord de l'écran |
| Fuite | **25 s au plus**. Vitesse 16 studs/s au départ, qui baisse de 0,32 stud/s chaque seconde jusqu'à 8 studs/s à 25 s (≈ 300 studs parcourus). Bonds de 0,45 s. Jamais dans un ranch : seulement les rues et la place. Anneau à la couleur du propriétaire, contour `Highlight` |
| Attraper | □, ou un bond qui atterrit près d'elle (§4.12). Rayon **5 studs** (tolérance serveur 6,5), **8 studs pour le propriétaire** (tolérance 9,5). **Le boopeur ne peut pas attraper sa propre fuite pendant ses 6 premières secondes** : la poursuite a vraiment lieu, en ville, pour tout le serveur |
| Fin (:X6:30) | Les squishies à la clôture rentrent. Les fuites en cours continuent jusqu'à leurs 25 s |

#### 4.21.3 Le propriétaire gagne toujours

| Qui attrape | Le propriétaire | L'attrapeur |
|---|---|---|
| **Le propriétaire** | Capture « **Héros** » : **+1 h de croissance du ranch** pour ce squishy (croissance sans boost × 3 600 s, une fois par squishy et par jour UTC ; ensuite, les pièces et la Fame seulement), 120 s de son revenu, +2 Fame | — |
| **Un autre joueur Rush** | **Son squishy rentre au ranch**, +1 Fame, 60 s de son revenu. Message, le retour d'abord : « **Wibble est rentré ! +1 Fame +X pièces · il a laissé un bébé à Noah** » | Un **bébé** : même espèce, 0 étoile, taille = `min(10 % de l'original, 0,5 × son propre plus gros squishy)`, minimum 1 ; mutation de l'original si elle vaut ×5 ou moins (Doré ou plus faible), sinon tirée avec des chances × 2 (§4.5) |
| **Personne** (25 s écoulées) | Le squishy rentre tout seul avec **+30 min de croissance du ranch** (même règle : une fois par squishy et par jour) | — |
| Les **autres joueurs Rush à 30 studs au plus** de la capture | — | 20 s de leur revenu et jauge +2 (« Bien joué ! ») : ceux qui ont couru gagnent aussi |

**Mise en scène d'une capture par un autre joueur** (§9.4) : l'attrapeur ne touche **jamais** l'original. Le squishy reçoit une pichenette pleine d'étincelles et éternue une petite **bulle-bébé** brillante ; seule la bulle saute dans les bras de l'attrapeur. L'original fait coucou et rentre au ranch en rebondissant, avec une traînée de cœurs ; le propriétaire a une flèche vers lui. Les images et les clips montrent un cadeau qui naît, jamais un animal emporté (jury §7).

Si le propriétaire quitte le serveur pendant la fuite, le squishy rentre aussitôt chez lui (sauvegardé à sa place).

**Pourquoi « 1 h de croissance » et un bébé plafonné.** Un pourcentage se cumule : deux comptes complices qui se boopent (4 fuites par heure) pouvaient faire grossir un squishy de +46 % par heure, et un bébé valait jusqu'à 2 fois le plus gros squishy du receveur, mutation rare comprise (un Légendaire Glitch vaut ×8 000). Une durée de croissance une fois par jour, un bébé d'au plus la moitié du plus gros et une mutation rare jamais copiée gardent le plaisir sans ferme à deux comptes (§12.8).

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
| Pas de fuite en cascade | Un squishy rentré d'une fuite n'est plus boopable jusqu'à la fin de ce Rush ; un squishy porté, dans le Bassin, dans la Boîte à dodo, né il y a moins de 60 s, ou dont le propriétaire attend son Grand Splorch dans la file (§4.15), ne vient pas à la clôture |
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
si attrapeur == boopeur et fuite de moins de 6 s (heure du serveur)  → refus
rayon = 5 + 1,5 (tolérance), ou 8 + 1,5 si attrapeur == propriétaire
t = tClient ramené dans [maintenant − 0,35 ; maintenant]
si distance à plat (XZ) entre pos(t) et la position validée du joueur à t > rayon,
   ou écart vertical (pieds du joueur / sol de la fuite) > 8, ou pas canAct → refus
égalité entre deux attrapeurs                                       → ordre d'arrivée
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
| Objectif | `ceil((30 + 50 × N) × indulgence)`, N = **joueurs actifs** à l'atterrissage (Cozy compris), au moins 1 : un joueur est actif s'il a eu une intention acceptée ou un déplacement validé de 4 studs ou plus dans les 2 dernières minutes, ou s'il est à 60 studs au plus du centre de la place pendant l'alerte. Les absents du clavier, fréquents dans un tycoon à Pot automatique, ne rendent plus l'objectif impossible (avec 12 absents sur 16, 4 joueurs devaient faire 207 points chacun en 60 s). Indulgence 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite ; retour à 1 après une réussite. Cible de conception : **≈ 80 % de réussite** |
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
| Pression **PERFECT** (une pression normale ne compte pas) | 1 |
| Naissance dans la Cuve | 2 |
| Pression de pet-sitting | 2 |
| Fusion (par étape de combo) | 3 |
| Créature en fuite attrapée, Wild Wobbler attrapé, Golden vu de près | 4 |
| Capture pendant le Rush (bébé ou Héros) | 6 |
| Être à 30 studs au plus d'une capture du Rush (joueur Rush) | 2 |
| Participation au MEGA (≥ 10 points) | 5 |
| Nourrir Plop | 10 |
| Grand Splorch | 25 |
| *(v2.0)* Petit Splorch (§4.27, critique m9) | 5 |

- *(v2.0)* Une **Jelly Ascend** ne donne **aucun** point de jauge : sa Pluie d'étoiles (§4.27) est son cadeau au serveur ; le Grand Splorch qui la précède a déjà compté ses 25 points [`Events.Gauge.Points.petitSplorch = 5`, aucune clé pour l'Ascension].
- **Objectif** = `600 × max(2, N)` points [`Events.Gauge.TargetPerPlayer = 600`] (N = joueurs actifs, même définition que le MEGA, §4.22, recalculé en direct). Un joueur de référence donne ≈ 20 points par minute (12 PERFECT, naissances, captures, fusions) : la jauge se remplit en ≈ 30 min sur un serveur de 16 joueurs actifs, en ≈ 60 min pour un joueur seul. Dans la version 1.2, chaque pression comptait : un serveur actif (une pression par seconde et par joueur) la remplissait en 6 min, et le ×2 tournait 45 à 60 % du temps.
- **Pleine** : Big Plop danse sur la place (8 s, grand spectacle, file du §2.4), puis **WOBBLE PARTY** : ×2 pièces et croissance pour tout le serveur pendant **5 min**. La jauge repart de 0 à la fin de la fête.
- **Sieste de Big Plop** : après une Wobble Party, Big Plop se repose **20 min** [`Events.Gauge.RestSeconds = 1200`] (jarre grise, « Big Plop se repose 12:34 » dans le HUD). Les points continuent de compter (rien n'est perdu), mais la fête suivante attend la fin de la sieste : **au plus 5 min de ×2 toutes les 25 min**, quel que soit le serveur.
- Grande jarre de gelée sur la place + petite barre dans le HUD.

**Jelly Moon (samedi, et rattrapage le dimanche)**

| Élément | Règle |
|---|---|
| Horaire | Samedi 16:00, 18:00, 20:00, 22:00 UTC (20 min chacune) ; dimanche 16:00 UTC (20 min). Le MEGA de :20 qui suit chaque séance devient MEGA MOON SQUISH |
| Ambiance | Ciel violet et sarcelle, grosse lune, musique douce un peu étrange. Les squishies Lunaires ont un petit troisième œil et 2 gouttes de gelée brillantes qui flottent autour d'eux. Mignon et bizarre, **jamais effrayant** |
| Mutations | Chances × 2 et Lunaire 3 % (§4.5) |
| BOOP RUSH | Les Rush de :05 et :15 rendent **Mythiques et Secrets boopables** |
| Espèce de la Lune | Moonplop (Secret) peut naître ; ensuite, chaque semaine, une nouvelle espèce arrive en données et fait ses débuts pendant la Lune (§7.6) |
| Autel de la Lune | Sur la place. Un joueur présent au moins 5 min pendant une séance reçoit **1 Goutte de Lune** à la fin de la séance : une naissance de Qualité (la sienne + 1) avec mutation **Lunaire garantie**. Une par séance et par compte au plus, notée dans le profil (`moon.lastSession`, §12.6) : changer de serveur ne la redonne pas |

### 4.24 Rythme de progression et simulation (porte de qualité) *(v2.0 : modifié)*

**Joueur de référence** (politique exacte, la même dans la simulation et dans ce document) : 35 min de jeu actif le premier jour, puis 30 min par jour ; une pression toutes les 2 s sur le squishy prêt le plus rentable, PERFECT 40 % du temps (fenêtre du §4.7) ; Pot encaissé toutes les 40 s ; achat de la dalle la moins chère qui sert (Tapis, Enclos seulement si les enclos sont pleins et qu'un squishy dort, décorations, Lit douillet dès R = 3) ; « Tout fusionner » dès qu'une paire de jumeaux existe ; il garde dans les enclos les squishies qui rapportent le plus (échange gratuit au panneau Ranch), toujours son plus gros compris, les autres dorment dans la Boîte à dodo, et il vend le plus faible quand la Boîte à dodo est pleine ; 85 % de ses créatures en fuite attrapées ; hors ligne 16 h par nuit ; **boosts ×2 calculés d'après les règles**, jamais supposés : Nourrir Plop au début de chaque session (5 min), Wobble Party du serveur de référence (jauge pleine en ≈ 30 min, sieste de 20 min, §4.23), pas de Squish Party ; événements avec les **vraies parts d'un serveur plein de 16 joueurs** (60 % des Rush avec un bébé, Wild Wobbler partagé 19 %, Wild Wobbler personnel 85 %, 2 bébés par MEGA, Golden 6 %, un cadeau de Grand Splorch toutes les 20 min, 10 cadeaux en pièces par jour au plus) ; aucun achat Robux. La porte refait le même calcul pour des serveurs de **4 et 8 joueurs** (Golden 25 % et 12 %, Wild Wobbler partagé 75 % et 38 %) : chaque jalon doit tenir aux trois tailles.

| Jalon | Cible (médiane) | Tolérance |
|---|---|---|
| Première pression | 10 s | ≤ 15 s |
| Premier achat (Tapis) | ≈ 20 s | ≤ 30 s |
| À 5:00 : squishies | 4 | 3-4 |
| À 5:00 : fusions | 1-2 | ≥ 1 |
| À 5:00 : captures | 1-2 | ≥ 1 |
| Première balade (taille 1 200) | 4:30 | ≤ 5:00 |
| À 5:00 : la dalle Enclos (1 200) est payable | 100 % des joueurs | ≥ 90 % |
| À 5:00 : pièces en poche (repère, pas une porte) | ≈ 10K | 5K-17K (valeur en dents de scie : elle dépend du dernier achat) |
| Premier Grand Splorch | 13 min | **11-16 min** (médiane) ; 10-18 min pour 80 % des joueurs |
| À 30 min : R | 2 | 1-3 |
| À 30 min : tampons de Squishydex | 18 | 14-24 |
| Fin du jour 1 (35 min) : R | 2 | 2-3 |
| Fin du jour 1 : 3 objectifs du jour sur 3 en 30 min | ≥ 90 % des joueurs | ≥ 90 % |
| Fin du jour 7 : R | 10 | 8-11 |
| Fin du jour 7 : plus gros squishy (avant Grand Splorch) | ≈ 1e8 | 4e7-4e8 |
| Fin du jour 7 : tampons de Squishydex (espèces + mutations) | 93 | 80-110 |
| Fin du jour 7 : au moins un Épique ou mieux | 100 % des joueurs | ≥ 95 % |
| Fin du jour 14 : R | 15 | 14-16 |
| Fin du jour 28 : R | 20 | 17-22 |
| Premier squishy de 1e12 (1 000 milliards) | vers le jour 27 (joueur à 30 min/jour ; 2 joueurs sur 3 l'ont avant la fin du jour 28) ; vers le jour 14 pour un joueur à 2 h/jour | — (longue traîne) |
| **Santé de l'économie** (jours 1 à 14, médiane des boucles) : moment où le Tapis 12 est atteint | vers 90 % de la boucle | après 50 % de la boucle |
| Santé de l'économie (jours 1 à 14) : pièces perdues au Grand Splorch | ≈ 3 × le prix du Tapis 12 de la boucle | ≤ 10 × |
| Jour 7 : part des pressions dans les pièces gagnées en jeu (hors Pot hors ligne) | ≈ 60 % | ≥ 50 % |
| Jours 2 à 14 : Grands Splorch déjà prêts à la connexion | 0 % | ≤ 50 % |
| Part du temps de jeu en ×2 (boosts calculés) | ≈ 30 % | 20-40 % |
| Gros acheteur (×2 Pièces, Grand Ranch, Squish Party la moitié du temps) : avance au jour 28 | 1 R | ≤ 2 R |

**Simulation (porte bloquante).** Un test Lune (`tests/specs/EconomyPacing.spec.luau`) simule les joueurs de référence sur 28 jours avec les tables de `Shared/Config/Balance` et `Shared/Config/Squishies`, le même code de formules que le jeu (`Shared/Logic/Formulas`, `Odds`, `FusionRules`, `QuestRules`), et une graine fixe : **20 joueurs par taille de serveur (4, 8 et 16) dans `./scripts/check.sh`** *(v2.0 révisé, critique M14 : 50 joueurs coûtaient ≈ 9 min)*, 50 joueurs et 140 jours la nuit, 200 en lancement manuel avant chaque version (§4.24.1). Le moteur saute d'un événement au suivant (pression, achat, naissance, capture, événement du serveur) avec les formules exactes du calcul paresseux (§12.3), au lieu de simuler chaque seconde : 28 jours de 200 joueurs restent sous la minute. Le test échoue si la médiane d'un jalon sort de sa tolérance.

**Résultats de la révision 1.3.** Une simulation Lune hors moteur, écrite avec les valeurs exactes de ce document (80 joueurs de référence, serveur de 16, 28 jours), donne : premier achat à 18 s, 4 squishies, 1 fusion et 2 captures à 5:00, première balade à 4:26, pièces à 5:00 médiane 10,2K (10 %-90 % : 5,6K-16,5K), premier Grand Splorch à 12,5 min (10,6-15,3), R = 2 à 30 min et en fin de jour 1, 18 tampons à 30 min, R = 10 au jour 7 (plus gros 1,0e8 ; 3,8e7-3,5e8 ; 93 tampons), R = 15 au jour 14, R = 20 au jour 28 (131 tampons), premier 1e12 au jour 27 pour les deux tiers des joueurs. Tapis 12 atteint à 93 % de la boucle, pièces perdues au Grand Splorch = 3,0 fois le prix du Tapis 12, pressions = 61 % des pièces gagnées en jeu, aucun Grand Splorch prêt à la connexion, 31 % du temps en ×2. Avec Fame, trophées, bonus de famille et objectifs : premier Grand Splorch à 12,5 min, R = 10 / 16 / 20 aux jours 7 / 14 / 28, 97 tampons au jour 7, premier 1e12 au jour 24, Tapis 12 à 80 % de la boucle, pertes = 7,8 fois. Serveurs de 4 et de 8 joueurs : mêmes R (10 / 15 / 20), premier Grand Splorch à 11,6 et 12,2 min. Un joueur à 2 h par jour : R = 20 au jour 14, 24 au jour 28, premier 1e12 au jour 14. Un gros acheteur a un à deux R d'avance : 11,4 min, R = 12 au jour 7, R = 21 au jour 28, premier 1e12 au jour 21 (c'est le « plus tôt, pas plus haut » du §8.1, n° 10).

**Ce que la version 1.3 a corrigé** (simulation de la critique technique, refaite avec les valeurs de la version 1.2) : (1) avec des prix de dalles × 2^R, toutes les dalles étaient au maximum 3 à 8 min après chaque Grand Splorch dès le jour 3 et les pièces perdues valaient plus de 1 000 fois le prix du Tapis 12 ; ×2 Pièces ne changeait rien de mesurable ; (2) environ 9 Grands Splorch sur 20 devenaient possibles pendant l'absence ; (3) l'hypothèse « boosts ×2 20 % du temps » était fausse : avec les règles de la version 1.2 (chaque pression dans la jauge, boosts des objectifs et des paliers de Plop), le joueur de référence passait **95 %** de son temps en ×2. Le prototype cité dans la version 1.0 n'utilisait pas exactement les valeurs du document (prix des dalles non multipliés par R, objectifs × 3) ; ses chiffres ne servent plus.

Leviers sans code (*v2.0 révisé, critique M13* : `Balance.Splorch.Targets`, `BeyondMult` et `Balance.Ascend.*` sont protégés par l'invariant de stabilité du §4.27, vérifié au chargement ; « objectifs × 2,3 dès R16 » est retiré des leviers) : `Balance.Splorch.Targets`, `Balance.Ascend.PriceByA`, `Balance.Tiles.*.Base/Growth`, `Balance.Tiles.RScale` (3,5), `Balance.Vat.Interval` et `Balance.Vat.ByR` (qualité, vitesse et buses par R), `Balance.Income.Coef` (0,02), `Balance.Press.Seconds` (22), `Balance.Offline.GrowthShare` (0,3), `Balance.Offline.StopAt` (0,9), `Events.Gauge.TargetPerPlayer` (600), `Events.Gauge.RestSeconds` (1 200).

#### 4.24.1 Simulation de l'économie v2.0 *(v2.0 : nouveau ; refaite après la critique indépendante du 2 novembre 2026)*

**Ce qui a été simulé.** Une copie de `tests/sim/EconomyModel.luau` et `tests/sim/Sim.luau` (dossier de travail du rôle design, jamais la copie du dépôt), étendue avec **toutes** les règles de la v2.0 et jouée avec les **vraies formules et tables** du dépôt (instantané du commit 7382f88 : `Formulas`, `Odds`, `FusionRules`, `QuestRules`, `RushRules`, `EventClock`, `Config/*`) : les 9 familles d'amélioration avec leurs prix et plafonds exacts (Tapis Étoilé ouvert de r = 6 à 10, Gants à 40 niveaux, École, Monuments × 3,5^(r − Record R), +1 % en multiplicateur à part), Confettis (3 + r compté jusqu'à 20, Petit Splorch 1, Grand Splorch sauté grâce au Tremplin 1, Ascension 20, retour au record 10, prime de record, enclos plein 25, piste de la semaine 34 par semaine) et Atelier complet (9 lignes, 21 niveaux, puis « Pour le plaisir » : 11 cosmétiques et 24 objets de Déco perso, la moins chère d'abord), cadeau du Splorch et Tapis de départ (6 niveaux au plus), places offertes, décorations gardées (12 au plus), Plopettes (5 par le Record R + Plume, règle des 12 studs comptée comme 75 % des pressions d'aide qui trouvent une cible, « prête depuis 3 s »), Jelly Ascend (15, 20, +4 ; ×3 ; **prix × F(A)** ; plancher de `StartR` ; Tremplin qui s'ajoute), Petit Splorch hors file, **Souvenir de gelée dégressif** (×3, ×2, ×1,5, ×1,25), arrêt de la croissance hors ligne à 120 s de croissance maximale, **`MaxR` = 400 et `MaxA` = 60 appliqués par le modèle** (critique M13). *Ajouté après la critique* : jours sans séance (joueur du week-end), joueur qui n'ouvre jamais l'Atelier, joueur qui refuse sa 1re Ascension pendant 3 jours, bandes de jours 85-112 et 113-140, et les mesures par valeur de A (Tapis 12 dans les boucles record, achats par boucle, falaise du retour au record), `offlinePotShare`, `everyFamilyBought`, jour où l'Atelier est fini. Joueur de **référence** (35 min le jour 1, puis 30 min par jour, politique du §4.24) et joueur **assidu** (2 h par jour, une séance), 84 et 140 jours, serveurs de **4, 8 et 16 joueurs**, 50 joueurs par configuration des portes (10 à 30 pour les autres), graine fixe ; 2 politiques d'achat (« la moins chère d'abord » et « Conseillé », §10.7.4) ; gros acheteur ; sans Ascension. Commandes : `scratchpad/v2/gdd/sim/batch.sh f1` … `f8` ; sorties : `scratchpad/v2/gdd/sim/out/v21/` (`summarize_v21.py` les résume ; les sorties d'avant la critique restent dans `out/`).

**Temps « sans but »** = part du temps de jeu passée à plus de 3 min d'un achat, d'un Grand Splorch (ou Petit) ou d'une Ascension (somme des dépassements de 3 min ÷ temps de jeu de la bande de jours). Les « étapes du record » (25, 50 et 75 % de l'objectif d'une boucle record : une carte et un éclat de confettis, sans récompense, critique B1 (c), §4.27 ; boucle record = r égal au Record R, Record R ≥ 1 : jamais la boucle de l'accueil ni une remontée ; une fois chacune par boucle ; jamais pendant la file ou le spectacle du joueur ; plusieurs étapes passées d'un coup : une seule carte) existent dans le jeu mais **ne sont pas comptées comme un but** dans ces chiffres.

**Jalons de la v1.3 : tous tenus** (serveur de 16 ; entre crochets : 4 et 8 joueurs)

| Jalon | Cible v1.3 | v2.0 mesuré (après la critique) |
|---|---|---|
| Premier Grand Splorch | 11-16 min | **12,6 min** [12,6 ; 12,9] |
| Première balade (selle) | ≤ 5:00 (cible 4:30) | **4:50** aux 3 tailles (comme le code du dépôt : la v2.0 ne touche pas aux 5 premières minutes) |
| R à 30 min, fin du jour 1 | 1-3, 2-3 | 2, 2 |
| Record R au jour 7 | 8-11 (cible 10) | **10** (p10 9, p90 10) aux 3 tailles |
| Record R au jour 14 | 14-16 | **15** (1re Ascension au jour 13) |
| Record R au jour 28 | 17-22 | **20** (A = 2) ; sans Ascension : 20 |
| Tampons au jour 7 | 80-110 | 93,5 [96 ; 95] |
| Plus gros au jour 7 | 4e7-4e8 | 8,1e7 |
| Part des pressions au jour 7 | ≥ 50 % | 64 % (Plopettes 8 %) [63 ; 63] |
| Temps en ×2 | 20-40 % | 36,4 % (rapporté seulement pour les séances plus courtes : 45 % à 20 min par jour, 70 % à 10 min ; critique m8) |
| Tapis 12 dans la boucle (médiane des boucles des jours 1 à 14) | ≥ 0,5 | 0,87 [0,86 ; 0,85] |
| Pièces perdues au Grand Splorch (médiane, jours 1 à 14) | ≤ 10 × T12 (v1.3) ; 0,2-3 (docs/09) | 1,4 [1,2 ; 1,2] |
| Grands Splorch prêts à la connexion | ≤ 50 % | 0 % |
| Premier squishy de 1e12 | ≈ jour 27 | jour 24 [24 ; 24] |

**Temps « sans but »** (médiane ; 50 joueurs jusqu'au jour 84, 10 joueurs pour les jours 85 à 140)

| Bande de jours | Référence (16 / 8 / 4 joueurs) | Assidu, 2 h par jour (16 / 8 / 4) | Cible |
|---|---|---|---|
| Jour 1 | 0,0 % | 0,1 % | ≤ 1 % |
| Jours 2-7 | 0,0 % / 0,1 / 0,1 | **10,6 %** / 9,4 / 10,7 | référence ≤ 5 % ; **assidu ≤ 15 %** |
| Jours 8-14 | 2,6 % / 2,3 / 2,7 | **15,5 %** / 15,9 / 15,3 | référence ≤ 15 % ; **assidu ≤ 30 %** |
| Jours 15-28 | 3,5 % / 3,8 / 3,8 | **16,1 %** / 15,7 / 15,9 | référence ≤ 20 % ; **assidu ≤ 30 %** |
| Jours 29-56 | 5,7 % / 5,8 / 6,0 | **16,5 %** / 15,9 / 15,5 | idem |
| Jours 57-84 | 5,7 % / 6,2 / 6,5 | **14,8 %** / 14,8 / 14,5 | idem |
| Jours 85-112 | 4,9 % | **13,9 %** | idem |
| Jours 113-140 | 5,2 % | **11,7 %** | idem |
| Plus long trou d'un joueur, p90 (pire bande) | 12,7 min (jours 29-84) | 14,9 min (jours 29-56) | assidu ≤ 15 min dans chaque bande |

Avant la critique (prix × 0,5 fixe, 18 décorations gardées, Souvenir qui s'arrêtait net) : assidu 22,0 / 24,0 % aux jours 29-56 / 57-84, puis **36,7 / 62,5 %** aux jours 85-112 / 113-140 (plus long trou médian 69,5 min). La v2.0 révisée **tient le but proche du joueur de 2 h par jour sur 140 jours** (décision par défaut n° 6), et sa courbe baisse au lieu de monter.

**Les profils que la critique a joués** (serveur de 16 sauf mention ; chaque cible est écrite, et tenue sauf la ligne marquée)

| Profil | Joueurs × jours | « Sans but » par bande (J2-7 / J8-14 / J15-28 / J29-56 / J57-84) | Autres mesures | Cible | Verdict |
|---|---|---|---|---|---|
| 20 min par jour | 50 × 84 | 0,0 / 2,0 / 4,6 / 4,9 / 5,8 % ; plus long trou p90 ≤ 12,8 min | R 8 / 14 / 19 aux jours 7 / 14 / 28 ; A1 au jour 15, une Ascension tous les 13-14 jours ; remontée 7 jours (0,19) ; ×2 45 % (rapporté) | référence | tient |
| 10 min par jour (15 le jour 1) | 30 × 56 | 0,0 / 0,5 / 1,9 / 4,2 % ; p90 ≤ 8,8 min | R 7 / 13 / 16 ; A1 au jour 18 ; remontée 9 jours (0,38) ; ×2 70 % (rapporté) ; Pot de nuit 1,9 × la séance (médiane ; 1,87 avec le Pot de nuit à 28 / 31 %, porte d'économie du lot A1, 80 joueurs) | référence | tient |
| Week-end seulement (90 min samedi et dimanche) | 50 × 84 | 0,6 / 6,7 / 12,7 / 10,6 / 13,3 % ; p90 ≤ 12,6 min | R 8 / 11 / 15 ; A1 au jour 23, puis tous les 21 jours ; **piste : 27 points possibles pour 24** (§7.5) | référence | tient |
| Jamais l'Atelier (référence) | 50 × 84 | 0,1 / 4,2 / 4,5 / 6,4 / 7,6 % (avec l'Atelier : 0,0 / 2,6 / 3,5 / 5,7 / 5,7) | Record R 40 au jour 84 (= 40), A = 7 (= 7) ; `atelierEffect` : l'Atelier retire 1,9 point de temps « sans but » aux jours 57-84 | référence | tient ; l'Atelier n'enlève plus d'achats |
| Jamais l'Atelier (2 h par jour) | 20 × 84 | 10,6 / 15,1 / 15,0 / 15,9 / 14,5 % (avec : 10,6 / 15,5 / 16,1 / 16,5 / 14,8) | Record R 84 au jour 84 (84,5 avec) | assidu | tient ; écart ≤ 1,1 point (avant : +7,3 points avec l'Atelier) |
| 6 h par jour, serveur de 4 (vacances) | 10 × 28 | **17,8** / 21,1 / 19,0 % (J2-7 / J8-14 / J15-28) ; plus long trou p90 **19,9** / 14,7 / 14,2 min | Ascension tous les 2 jours, A = 15 au jour 28 ; avant la critique : 18,4 / 24,2 / 28,4 % | ≤ 30 % par bande | tient ≤ 30 % ; **la limite de 15 % (jours 2-7) n'est pas appliquée à ce profil** : décision argumentée plus bas |
| 2 h par jour, 140 jours | 10 × 140 | 10,1 / 16,1 / 16,2 / 16,7 / 15,2 %, puis 13,9 / 11,7 % (J85-112 / J113-140) ; p90 ≤ 14,9 min | A = 34,5 au jour 140 (28, une Ascension tous les 5 jours, après le réglage de la porte d'économie du lot A1 : condition + 5 une fois toutes les 8 Ascensions dès la 11e, médiane sur 400 joueurs, §4.27) ; Tapis 12 atteint entre 0,58 et 0,87 de chaque boucle record (médiane, A1 à A38) ; achats de la ligne Tapis par boucle record ≥ 10,4 ; Atelier complet au jour 79 | assidu | tient |
| Référence, 140 jours | 10 × 140 | 0,1 / 1,6 / 3,1 / 6,3 / 5,5 %, puis 4,9 / 5,2 % | A = 13 au jour 137 ; Confettis en poche 25 au jour 140 (l'Atelier n'est pas fini : il reste des achats) | référence | tient |
| Référence sans Ascension | 20 × 84 | 0,0 / 4,5 / 30,0 / 51,2 / 64,5 % | Record R 29 au jour 84 | — (rapporté) | le jeu se creuse : corrigé par l'interface (carte Conseillé, focus sur « Oui », §4.27, critique M1), mesuré par le profil suivant |
| 2 h par jour sans Ascension | 20 × 84 | 16,0 / 40,8 / 57,2 / 78,7 / 89,8 % ; plus long trou médian 170 min aux jours 57-84 | Record R 42 au jour 84 | — (rapporté) | idem |
| **Refuse la 1re Ascension pendant 3 jours** (nouveau) | 20 × 84 | référence 0,0 / 4,5 / 8,7 / 4,8 / 6,9 % (A1 au jour 17) ; assidu 16,0 / 17,0 / 15,7 / 16,4 / 14,9 % (A1 au jour 9) | référence Record R 20 au jour 28 ; assidu 31,5 | référence ≤ 20 %, assidu ≤ 30 % dans chaque bande | tient |
| Politique « Conseillé » | 20 × 56 et 20 × 84 | référence (20 × 84) 0,1 / 2,0 / 3,3 / 6,0 / 5,6 % ; assidu (20 × 84) 10,6 / 15,6 / 15,9 / 16,4 / 15,1 % ; 20 min par jour (20 × 56) 0,0 / 2,0 / 5,2 / 5,3 % | | référence / assidu | tient : à ± 1 point de « la moins chère d'abord » |

**Pourquoi la limite de 15 % des jours 2-7 n'est pas appliquée au joueur de 6 h par jour** (la seule remarque de la critique rejetée, en partie) : (1) la décision n° 6 du propriétaire vise le joueur de 2 h par jour, qui est à 9,4-10,7 % ; (2) le joueur de 6 h par jour vit en une semaine ce que l'assidu vit en deux (Record R 24,5 au jour 7 contre 15) et reste **sous 30 % dans chaque bande** (17,8 / 21,1 / 19,0 %, contre 18,4 / 24,2 / 28,4 % avant la critique) ; (3) l'écart vient des boucles **avant la 1re Ascension**, de R9 à R15 (70 à 118 min de jeu chacune pour lui, plus long écart médian 5 à 7 min), c'est-à-dire l'économie de la v1.3 qui tient les jalons du joueur de référence (Record R 10 au jour 7, 15 au jour 14) ; la changer pour lui déplacerait ces jalons. La limite qui s'applique à ce profil est donc **30 % par bande**, et son plus long trou (p90 19,9 min aux jours 2-7, 14,7 et 14,2 ensuite) est rapporté.

**La Jelly Ascend** (serveur de 16)

| Mesure | Référence | Assidu | Cible |
|---|---|---|---|
| 1re Ascension | **jour 13** (p10 12, p90 14) | **jour 6** | 12-16 / 5-9 |
| Écart entre deux Ascensions | **10 à 11 jours** (A2 jour 24, A3 36, A4 46, A5 57, A6 68, A7 79 ; sur 140 jours : A10 109, A13 137) | **4 à 5 jours** (A2 11,5, A3 16, A4 21, A8 40 ; sur 140 jours : A20 92) | 10-16 / 4-8 |
| Retour au record après une Ascension (temps de jeu ÷ temps de la 1re fois) | 0,16 (5 jours) | 0,12 (1 jour) | 0,10-0,40 |
| **Falaise du retour** (`regainCliff` : 1re boucle record ÷ médiane des 3 dernières boucles de remontée) | **1,2** (p90 1,8) | **2,1** (p90 3,4) | ≤ 4 en médiane et au p90 (critique M6 ; avant : 4,6 et 11) |
| Boucle la plus courte après une Ascension | 41 s (2 sur 6 298 sous 45 s) [42 s ; 43 s] | 44 s (1 sur 14 712) [48 s ; 42 s] | **≤ 0,3 % des boucles sous 45 s, chacune avec sa cible atteinte ≤ 10 s après une fusion** (moment « combo → Grand Splorch », §4.10 ; mesuré de la fusion à l'instant où la cible est atteinte, sans le geste du Petit Splorch ni l'attente de la pression suivante : décision du 5 novembre 2026, plus bas), **aucune boucle de 0 s** (v2.0 révisé : « 99,9 % » était dépassé par le joueur de 10 min par jour, 3 boucles sur 1 310, toutes 2 s après une fusion) |
| Tapis 12 dans les **boucles record**, par valeur de A (médiane) | 0,68 à 0,87 (A1-A7) ; 0,64 à 0,93 (A1-A13, 140 jours, 10 joueurs) | 0,59 à 0,77 (A1-A18) ; 0,58 à 0,87 (A1-A38, 140 jours) | chaque A entre 0,45 et 0,95, toutes les boucles record entre 0,5 et 0,9 (critique B1 ; 40 boucles par A et par profil de 10 joueurs : la marge de chaque A couvre l'échantillon) |
| Achats de la ligne Tapis (Tapis + Tapis Étoilé) par boucle record | 11,2 à 14,7 | 10,4 à 16,3 | ≥ 10 pour A = 1 à 30 |
| Record R au jour 28 avec Ascension / sans | 20 / 20 | 33 / 28 | ≥ sans Ascension − 1 |
| Confettis gagnés / en poche (médiane) aux jours 7, 14, 28, 56, 84 | 144 / 10 · 312 / 26 · 560 / 35 · 1 162 / 47 · 1 742 / 45 | 294 / 20 · 566 / 13 · 1 137 / 34 · 2 358 / 134 · 3 693 / 269 | **≤ 300 en poche jusqu'au jour 84, référence et assidu** (critique M4 ; avant : 4 414 pour l'assidu au jour 84) |
| Lignes de l'Atelier finies (21 niveaux) / Atelier et « Pour le plaisir » complets (56 niveaux) | jour 106 (8 lignes sur 9 au jour 84 : « la moins chère d'abord » achète des objets de Déco perso avant le Tremplin 3) / après le jour 140 | jour 54 / jour 79 | lignes ≥ jour 35 (`workshopAllDay`) |
| Monuments aux jours 7, 14, 28, 56 | 2, 5, 8, 10 | 5, 8, 10, 10 | 1-3 au jour 7, ≥ 4 au jour 28 |
| Valeurs non finies (pièces, tailles) | 0 | 0 (pièces jusqu'à 2,2e79 au jour 140) | 0 |

**Santé des boucles** (référence, serveur de 16) : Grands Splorch : pièces perdues 0,44 à 1,34 T12 selon la bande (p90 ≤ 4,7), Tapis 12 atteint à 0,74-1,0 de la boucle, boucles de 24 à 39 min de jeu (assidu : pertes 1,2 à 2,5 T12, boucles de 51 à 106 min). **Petits Splorch** (remontées) : boucles de **4 à 7 min**, pièces perdues **15 T12 aux jours 8-14, 10 aux jours 15-28, 5 aux jours 29-56, 4 aux jours 57-84** : pendant une remontée, la collection du joueur est bien plus riche qu'au premier passage ; il achète tout en quelques minutes (Monuments compris) et la boucle se termine vite. C'est voulu (le plaisir de la remontée) ; la clé `coinsLostRatioGrand` (0,2-3) ne porte donc que sur les **Grands Splorch** ; celle des Petits Splorch est seulement rapportée, et l'aperçu ne montre plus de ligne rouge quand rien de gardé n'est payable (critique M16).

**Chaque famille est achetée** (`everyFamilyBought`, part des boucles où la famille est achetée au moins une fois **pendant qu'elle est ouverte et pas au maximum** ; le Tapis Étoilé est ouvert quand r ≥ 6 et que le Tapis 12 est atteint dans la boucle) : référence Tapis 100 %, Tapis Étoilé 98 %, Décorations 100 % (6 à racheter par boucle : 12 sont gardées au plus), Gants 100 %, École 100 % ; assidu 100 / 96 / 100 / 100 / 100 % (96 % mesuré avec la définition plus large, sans la condition du Tapis 12) ; joueurs de 10 et 20 min par jour, du week-end et de 6 h par jour : Tapis Étoilé 97 à 99 %, les autres familles 100 %. Enclos, Lit et Monuments sont des achats **permanents** : ils ont leurs propres clés (Enclos au maximum dès le jour 2, Lit au Record R 3, `monumentsDay7`, `monumentsDay28`).

**Gros acheteur** (20 joueurs ; ×2 Pièces, Grand Ranch, Squish Party la moitié de chaque séance ; 77 % du temps en ×2) : il atteint chaque Ascension **15 à 22 % plus tôt** (A1 au jour 11 contre 13, soit 15 % ; A2 19 contre 24, A3 28 contre 36, A5 45 contre 57, A7 62 contre 79 : `spenderLeadTimeShare` = 22 % au plus, cible ≤ 25 %, **bloquante**, critique M2). En Record R : +1,5 au jour 7 (11,5 contre 10), +0 au jour 14, **+4 au jour 28** (24 contre 20, A = 3 contre 2), +5 au jour 56, **+9,5 au jour 84** (49,5 contre 40) : avec l'Ascension, la progression devient linéaire dans le temps, donc une avance en temps se lit en Record R qui grandit. Sans la Squish Party (×2 Pièces et Grand Ranch seulement) : 8 à 15 % plus tôt, +2 Record R au jour 28 (22) et +7,5 au jour 84 (47,5). Sans Ascension : +2 Record R au jour 28 (22 contre 20), comme en v1.3. Décision ouverte pour le propriétaire : §20, question 8.

**Les « boucles de 0 s » de docs/09 : expliquées et supprimées.**
1. **C'était une erreur de mesure.** Dans le modèle de la contre-mesure du 01/11/2026, la Jelly Ascend était appliquée à l'intérieur du Grand Splorch qui l'autorisait, et le journal écrivait l'événement « ascend » **avant** l'événement « splorch », au même instant ; l'analyse ouvrait une boucle à « ascend » et la fermait au « splorch » qui suivait : **une boucle de 0 s par Ascension**, exactement (20 joueurs × 4 Ascensions = 80 ; mesuré : 82, soit 5,5 % de 1 483 boucles). Corrigé dans le modèle v2.0 : le Grand Splorch est journalisé d'abord, puis l'Ascension, et la boucle suivante commence à l'Ascension. Résultat : **aucune boucle de 0 s** dans aucune configuration ; **aucune** renaissance au même instant qu'une autre (compteur `zeroGapRenaissances` = 0, dans les 22 configurations après la critique aussi).
2. **Les boucles courtes qui restaient (13 à 30 s dans docs/09 et dans les premiers essais v2.0) commençaient presque toutes la veille** : la croissance hors ligne (30 % de 16 h, arrêtée à 90 % de l'objectif) faisait presque toute une boucle de remontée, et les derniers 10 % prenaient 13 à 30 s une fois le Tapis racheté et le bol de Plop servi. **Corrigé dans le design** : la croissance hors ligne s'arrête aussi à **120 s de croissance maximale de la boucle** avant l'objectif (§4.19). Il reste 1 à 3 boucles sur 1 300 à 15 000 entre 16 et 45 s : **chacune finit 2 à 8 s après une fusion** (mesuré : le plus gros était à 65-95 % de l'objectif au début de la séance, puis « Tout fusionner » donne (a + b) × 1,25 et dépasse l'objectif d'un coup). C'est le moment « combo → Grand Splorch » voulu par le §4.10, jamais une boucle vide.
3. **Les autres pistes de docs/09 sont écartées par vérification** : (a) un squishy hors de l'enclos qui garderait sa taille : le Grand Splorch du modèle remet à 1 les squishies des enclos, du Bassin et de la Boîte à dodo, et le contrat v2.0 l'exige aussi pour la Boîte aux lettres et le squishy porté (propriété de `Prestige.apply`, `contract-changes.md`) ; (b) un bébé ou une capture calculés avec l'ancien r : leur taille est une part du **plus gros actuel** (remis à 1), donc au plus 0,5 ; (c) deux renaissances dans le même pas : **0** (compteur `zeroGapRenaissances`) ; (d) la croissance hors ligne appliquée avant la remise à zéro : le hors-ligne est appliqué au chargement, après la sauvegarde du Grand Splorch ; c'est la cause n° 2, qui ne venait pas de l'ordre mais de la quantité.

**Leviers essayés et écartés** (mesurés ; sorties dans `out/explore/`, `out/v21/` et, pour ceux de la critique, `critique/sim/out/`) : prix × 1,6^A (docs/09 : pouvoir d'achat ÷ 5 par Ascension, assidu à 74,5 % « sans but » aux jours 57-84) ; prix × 0,5 fixe (v2.0 avant la critique : 36,7 puis 62,5 % aux jours 85-140) ; × 0,4 fixe (critique : 21,2 % au jour 140 mais Tapis 12 à 1,00 dès les jours 57-84) ; × 0,4 jusqu'à A12 puis × 1/3 (point de départ de la critique : Tapis 12 à 1,00 de A9 à A33) ; × 1/3 fixe (*la ligne de la v2.0 qui l'écartait citait une sortie d'un modèle antérieur, R = 11,5 au jour 7 pour l'assidu ; rejoué avec les valeurs finales par la critique* : 11,5-16,9 % sur 140 jours, mais pièces perdues au Grand Splorch 5,5-9,0 T12 et Tapis 12 à 0,33-0,45 de la boucle aux jours 8-84 : trop riche au milieu) ; × 0,5 jusqu'à A4 puis × 0,3 (pertes 3 à 7,5 T12 au-delà de A19) ; × 0,5 jusqu'à A4 puis × 0,33 (Tapis 12 à 0,93-1,00 au-delà de A26) ; `ReqStep` 3 seul ou objectifs × 2,3 dès R16 (**emballement** : Record R 453 et A = 60 au jour 28 pour l'assidu, 461 au jour 84 pour la référence ; interdit par l'invariant de stabilité, §4.27) ; `ReqStep` 3 et croissance × 2,2 (stable, mais l'assidu reste à 21,7 % aux jours 57-84) ; prix × 1 avec Souvenir de gelée × 4 (assidu à 82,6 % aux jours 57-84) ; Tapis Étoilé prolongé jusqu'à 40 (aucun gain mesurable, 20 niveaux de plus à afficher) ; Squish Party qui ne double que les pièces, ou ×2 Pièces qui ne s'ajoute pas à un boost (même avance du gros acheteur : c'est la vitesse, pas le mode de calcul) ; arrêt hors ligne à 60 et 90 s (encore des boucles de 38-40 s) ; décorations en multiplicateur à part × (1 + 0,02 × décorations) (critique M8 : −20 % de revenu dans les premières boucles à 10 décorations, contre les jalons de la v1.3 ; on affiche l'effet réel à la place, §4.3).

**Clés de la porte `EconomyPacing` v2.0** (à ajouter à la spec du dépôt avec le modèle étendu ; *v2.0 révisé, critique M12 et M14*) — **dans `check.sh`** (bloquantes, **20 joueurs** par taille de serveur 4, 8 et 16, référence 84 jours et assidu 28 jours, ≈ 3,5 min mesurées sur ce poste) ; **la nuit** (bloquantes aussi, 50 joueurs, référence et assidu **140 jours**, gros acheteur 200 joueurs, et les configurations forcées : profils de départ à **A = 10, 20, 30 et 60** construits par `Prestige.apply` répété, « Atelier complet dès le début », « une connexion par jour » de 23,5 h, les 6 profils de la critique ci-dessus) :
- toutes les clés de la v1.3 (tableau du §4.24) ;
- temps « sans but », référence : `starvedDay1` ≤ 1 % ; `starvedDay2to7` ≤ 5 % ; `starvedDay8to14` ≤ 15 % ; `starvedDay15to28` ≤ 20 % ; `starvedDay29to56`, `starvedDay57to84`, `starvedDay85to140` ≤ 20 % ; assidu : `starvedAssiduDay2to7` ≤ 15 % ; `starvedAssiduDay8to14`, `…15to28`, `…29to56`, `…57to84`, `…85to140` ≤ 30 % ; `longestGapAssiduP90` ≤ 15 min dans chaque bande (critique B1) ; joueurs de 10 et 20 min par jour et du week-end : limites de la référence ; 6 h par jour : ≤ 30 % par bande ; « refuse 3 jours » : limites de son profil ;
- `loopMaxGap` (plus long moment sans achat d'une boucle, avant toute Ascension, pour chaque r de 0 à 13) : médiane ≤ 3 min et p90 ≤ 5 min, **bloquante pour la référence** (mesuré : 2,7 et 4,1 au pire, à R12-13) ; **rapportée pour l'assidu** (3,3 / 3,8 à R7, jusqu'à 5,9 / 8,6 à R13 : ses boucles avant la 1re Ascension durent 46 à 105 min ; c'est le temps « sans but » de l'assidu, ≤ 15 % aux jours 2-7, qui le borne) ;
- `helperShareDay7` 5-15 % ; `ascend1Day` 12-16 (référence), 5-9 (assidu) ; `ascendGapDays` 10-16 (référence), 4-8 (assidu) ; `regainRatio` 0,10-0,40 ; `regainCliff` ≤ 4 (médiane et p90) ; `shortestLoopSec` (≤ 0,3 % des boucles sous 45 s, chacune avec sa cible atteinte ≤ 10 s après une fusion, jamais 0 s) ; `zeroGapRenaissances` = 0 ; `recordRDay28` ≥ celui sans Ascension − 1 ;
- `coinsLostRatioGrand` 0,2-3 (médiane des Grands Splorch de chaque bande à partir des jours 2-7) ; `tapis12LoopShare` ≥ 0,5 (Grands Splorch, jours 1-14) ; **`tapis12RecordLoopByA`** : médiane de chaque A de 1 à 30 entre 0,45 et 0,95, de toutes les boucles record entre 0,5 et 0,9 ; **`purchasesPerRecordLoopByA`** : achats de la ligne Tapis ≥ 10 par boucle record pour A = 1 à 30 ;
- `confettiUnspent` ≤ 300 en poche (médiane) jusqu'au jour 84, **référence et assidu** ; `workshopAllDay` (21 niveaux des 9 lignes) ≥ jour 35 ; `atelierEffect` (écart de temps « sans but » et de Record R avec et sans Atelier) **rapporté** ; `monumentsDay7` 1-3, `monumentsDay28` ≥ 4 ; `firstWorkshopBuy` ≤ 35 min ;
- `everyFamilyBought` ≥ 80 % pour Tapis, Tapis Étoilé, Décorations, Gants et École (définition plus haut) ;
- `offlinePotShare` (Pot de la nuit ÷ pièces gagnées en jeu le même jour) : médiane ≤ 2 (mesuré : référence 0,96, assidu 0,42, 20 min par jour 1,25, 10 min par jour 1,91 ; p90 2,5 / 0,8 / 3,2 / 4,7, rapporté) ;
- `nonFinite` = 0 ; `MaxR` et `MaxA` jamais dépassés ; **`spenderLeadTimeShare` ≤ 25 %** (avance du gros acheteur **en temps** au même jalon, A1 à A7), au lieu d'un écart en Record R (critique M2) ;
- `queueWaitNewcomer` ≤ 40 s : **spec `Soak_queue`** (16 robots dont 8 vétérans qui font des Petits Splorch en rafale après une Ascension ; attente médiane du premier Grand Splorch d'un nouveau joueur), dans la couche c du §12.10 (critique M12).

**Coût mesuré** (critique M14 ; ce poste, 4 cœurs) : une configuration référence 84 jours × 50 joueurs prend 90 s, assidu 84 jours × 50 joueurs 300 s ; à 20 joueurs, référence 84 jours ≈ 35 s et assidu 28 jours ≈ 35 s par taille de serveur, soit ≈ 3,5 min pour les 3 tailles. Les 140 jours (10 joueurs : 60 s référence, 150-200 s assidu) et les 50 joueurs vont la nuit.

**Ce qui n'est pas simulé** (honnêteté) : le pet-sitting et les amis (aucun ami dans le modèle, comme en v1.3) ; la position réelle du joueur pour la règle des 12 studs des Plopettes (approximée par 75 %) ; les Squish Parties achetées par **d'autres** joueurs du serveur ; la maîtrise d'espèce (+25 Confettis) et les jalons de taille géante ; le confort (Aimant) ; un joueur qui fait deux séances par jour ; les configurations forcées A = 10 à 60 (elles demandent le vrai `Prestige.apply`, au paquet de la porte) ; la file du serveur avec 8 vétérans (`queueWaitNewcomer`, robots de `Soak_queue`).

### 4.25 Boosts, plafonds et limites anti-abus *(v2.0 : modifié)*

**Boosts ×2** : boost de serveur (Wobble Party gratuite, Squish Party payée, Squish Party d'administrateur) et boost personnel (Nourrir Plop, 5 min par jour ; minutes de Squish Party non jouées d'un acheteur, §8.3). Les objectifs du jour ne donnent plus de boost (§7.4) : avec eux et les paliers de Plop à 15 min, le joueur de référence passait 95 % de son temps en ×2, et le boost ne voulait plus rien dire. Ils ne se cumulent jamais : `B` vaut 2 au plus. Une Squish Party payée n'est jamais « mangée » par un boost gratuit : la fête payée passe d'abord, la Wobble Party attend son tour. Un boost personnel est **mis en pause** pendant un boost de serveur (son minuteur s'arrête), pour que le joueur ne perde rien.

| Plafond ou limite | Valeur |
|---|---|
| Bébés de BOOP RUSH | 10 par jour et par joueur |
| Wild Wobblers | 2 partagés + 1 personnel par joueur et par Rush |
| Golden Wobbler | Le gagnant ne peut pas regagner pendant 20 min |
| Bébés de Grand Splorch reçus | 10 par jour |
| Cadeaux de Grand Splorch en pièces (60 s de revenu) | 10 par jour, ensuite 10 s de revenu |
| Spectacle complet d'un Grand Splorch des autres | Au plus une fois toutes les 3 min par spectateur (sinon version courte, §4.15) |
| Bébés du MEGA | 3 par MEGA (paliers) |
| Taille de **tout** bébé ou cadeau | Au plus **0,5 × le plus gros squishy** du joueur qui le reçoit (le bébé du Rush : `min(10 % de l'original, 0,5 × le plus gros)`) |
| Mutation d'un bébé du Rush | Copiée seulement si elle vaut ×5 ou moins ; sinon tirée avec des chances × 2 |
| Croissance « Héros » (+1 h) et « rentré seul » (+30 min) | Une fois par squishy et par jour UTC |
| Fame du Rush (boopé, Wild Wobblers, Héros) | 30 par jour, en mode Rush comme en mode Cozy |
| Fame en relâchant | 20 par jour |
| Pressions de pet-sitting récompensées | 100 par jour et par visiteur ; 100 reçues par jour et par propriétaire ; « Plus serviable » compte 20 pressions au plus par ami et par jour |
| Applaudissements récompensés | 10 par jour |
| Pressions | 12 par seconde au plus (au-delà, ignorées) |
| Fuites du Rush | 2 par ranch et par Rush, 4 par ranch et par heure ; 10 en même temps sur le serveur ; une même paire boopeur → ranch au plus toutes les 30 min |
| Squish Party | Vendue seulement si aucune fête n'est en cours ; deux achats qui se croisent : la seconde fête prolonge la première de 10 min (aucune file d'attente en mémoire) ; 3 achats par joueur et par jour |
| Wobble Party | Au plus 5 min de ×2 toutes les 25 min (sieste de Big Plop, §4.23) |
| Comptes multiples qui se boopent | Bornés par les plafonds de bébés, la taille ≤ 0,5 × le plus gros, aucune mutation rare copiée, la croissance « Héros » une fois par squishy et par jour, 1 boop par paire toutes les 30 min et 4 fuites par ranch et par heure |
| Vitesse, téléportation, bond sans recharge | Contrôle de déplacement avec budget d'action (§12.8) |
| Rafales de messages réseau | Seau à jetons par action (§12.7) |
| Échanges et dons de squishies | Aucun (les colis entre amis sont dans la réserve non planifiée, §17.2) |
| Fame du Grand Splorch *(v2.0)* | 50 par jour (`Balance.Caps.fameSplorch`) |
| Bannière « GRAND SPLORCH » d'un même joueur *(v2.0)* | Une toutes les 3 min au plus (sinon une petite ligne) |
| Pluie d'étoiles (Jelly Ascend d'un autre) *(v2.0)* | 120 s de revenu, 3 par jour ; son bébé compte dans les 10 bébés de cadeau par jour |
| Cœurs donnés *(v2.0)* | 1 par ranch et par jour, 20 par jour ; aucun compteur public |
| Confettis *(v2.0)* | Entiers de 0 à 1e9 ; gagnés seulement par les sources du §4.26, jamais vendus |
| Plopettes *(v2.0)* | Sieste après 5 min sans entrée du joueur ; aucune pression d'aide pour le pet-sitting ni le MEGA |

### 4.26 Confettis et Atelier de Big Plop *(v2.0 : nouveau)*

**Les Confettis** sont la 2e monnaie du jeu, **gagnée en jouant seulement, jamais vendue, jamais une chance, jamais remise à zéro** (ni par un Grand Splorch, ni par une Ascension). Ils achètent le confort et le départ rapide, pour toujours, à l'Atelier de Big Plop.

| Source | Confettis | Clé |
|---|---|---|
| **Grand Splorch** (nouveau Record R) | **3 + r** (r après la renaissance), *(v2.0 révisé, critique M4)* **r compté jusqu'à 20** : 4 au premier, 13 au dixième, 23 au plus | `Balance.Confetti.PerGrandSplorch` (= 3, plus r), `Balance.Confetti.CapR = 20` |
| **Petit Splorch** (r après la renaissance ≤ Record R, après une Ascension, §4.27) | **1** | `Balance.Confetti.PerPetitSplorch = 1` |
| Grand Splorch **sauté grâce au Tremplin** (§4.26, ligne 9) | **1** par Grand Splorch sauté, **3 au plus par Ascension** ; *(critique M4)* ceux que saute le **plancher** de `StartR` ne rapportent rien (sinon 38 Confettis d'un coup à A10, ≈ 60 à A15 : plus que l'Ascension elle-même) | `Balance.Confetti.PerSkipped = 1` |
| **Jelly Ascend** | **+20** | `Balance.Confetti.PerAscend = 20` |
| *(v2.0 révisé, critique M5)* **Retour au record** après une Ascension (le Petit Splorch qui ramène r au Record R) | **+10**, une fois par Ascension, avec la carte « De retour à ton record 15 ! » | `Balance.Confetti.RegainBonus = 10` |
| **Prime de record** (premier passage de chaque Record R au-delà de 20) | **+10** | `Balance.Confetti.RecordBonus = 10` |
| Place d'enclos offerte qui tombe sur un enclos plein (R2, R6, R11, R16) | **+25** | `Balance.Confetti.FullPenBonus = 25` |
| **Piste de la semaine** (§7.5, 12 paliers) | **34** par semaine complète | `Quests.WeeklyTrack` |
| Maîtrise d'une espèce (§4.17) | **+25** par espèce maîtrisée | `Balance.Confetti.Mastery = 25` |

Cumul des Grands Splorch et des primes au premier passage (sans la piste) : R1 4 · R2 9 · R5 30 · R8 60 · R10 85 · R12 114 · R15 165 · R20 270 · R25 435 · R30 600 (v2.0 avant la critique : 450 et 655) ; avec les places offertes sur un enclos plein : R8 85 · R10 110 · R12 164 · R15 215 · R20 345. **Mesuré** (§4.24.1, piste comprise) : joueur de référence 144 Confettis gagnés au jour 7, 312 au jour 14, 560 au jour 28, 1 162 au jour 56 et 1 742 au jour 84 ; en poche (médiane) 10, 26, 35, 47 et 45 ; joueur de 2 h par jour 294, 566, 1 137, 2 358 et 3 693 gagnés ; 20, 13, 34, 134 et 269 en poche : les Confettis sont dépensés, jamais thésaurisés, tant qu'il reste quelque chose à acheter. **Affichage** : entier brut jusqu'à 99 999, puis le formateur des grands nombres (§4.2). Icône dessinée en cadres (3 petits rectangles inclinés rose, menthe, jaune), de forme et de couleur différentes de la pièce. Le compteur n'est pas dans le HUD (règle « peu d'éléments », §10.2) : il est dans l'en-tête de l'écran Améliorations, dans l'aperçu du Grand Splorch et sur la carte de récompense. Bornes : `confetti` et `confettiTotal` entiers de 0 à 1e9. *(Critique m2)* Seuls `EconomyService.addConfetti` (gains : `Prestige.apply`, la piste de la semaine, la maîtrise, le retour au record) et `EconomyService.buyUpgrade` (dépenses) les modifient. *(Critique M4)* **Quand l'Atelier et « Pour le plaisir » sont complets**, la tuile Confettis de l'aperçu devient « Cadeau du Splorch », l'en-tête de l'écran affiche « Confettis gagnés : 4 414 » (le total, comme dans le Livre des records) et le Défi « Gagne 20 Confettis » n'est plus tiré ; les Confettis gagnés restent comptés pour les objets des costumes de saison suivants (§7.6).

**L'Atelier de Big Plop** est le 4e onglet de l'écran Améliorations (§10.7) ; le kiosque de Big Plop sur la place l'ouvre aussi. Il s'ouvre au **premier Grand Splorch** (Record R ≥ 1), avec ses 4 premiers Confettis : une ligne s'achète tout de suite (mesuré : premier achat à l'Atelier à 12,6 min). Chaque achat en Confettis demande un **maintien de 0,6 s** (§10.7.8).

| # | Ligne (FR / EN) | Niveaux | Coût de chaque niveau (Confettis) | Effet | Condition |
|---|---|---|---|---|---|
| 1 | Cadeau du Splorch / Splorch Gift | 2 | 3 · 25 (28) | Le cadeau du Splorch (§4.15) paie **2 puis 3** niveaux du Tapis (les prochains, après ceux du Tapis de départ) au lieu de 1 | Record R ≥ 1 |
| 2 | Tapis de départ / Head-Start Mat | 3 | 12 · 30 · 60 (102) | Chaque boucle commence avec le Tapis déjà au niveau 1, 2 puis 3 | Record R ≥ 1 |
| 3 | Aimant à pièces / Coin Magnet | 3 | 4 · 8 · 14 (26) | Rayon d'encaissement du Pot : 5 → 8 → 11 → 14 studs | Record R ≥ 1 |
| 4 | Super Série / Super Streak | 2 | 10 · 20 (30) | Série PERFECT jusqu'à 6 puis 7 (+60 % puis +70 % au lieu de +50 %) | Record R ≥ 1 |
| 5 | Déco qui reste / Kept Decorations | 2 | 15 · 60 (75) | +3 décorations gardées au Grand Splorch par niveau (**12 au plus** avec celles des R8 et R14 ; v2.0 révisé, critique M3 : les niveaux 3 et 4 sont retirés, ils enlevaient des achats au joueur qui en manque déjà) | Record R ≥ 1 |
| 6 | Sac de nuit / Night Bag | 3 | 6 · 12 · 20 (38) | Limite hors ligne +1 h par niveau. **Maximum : 16 h** (8 h + 4 h du Lit + 3 h du Sac + 1 h de la famille Spiky). La croissance hors ligne s'arrête toujours avant l'objectif (§4.19) ; le Sac donne surtout plus de Pot la nuit | Record R ≥ 1 |
| 7 | Pot de nuit / Night Pot | 2 | 15 · 30 (45) | Pièces hors ligne dans le Pot : 25 % → 28 % → 31 % du revenu (réglage de la porte d'économie, docs/04 §21) | Record R ≥ 1 |
| 8 | Plume (6e Plopette) / Plume | 1 | 40 | Une Plopette de plus (§4.28) | Record R ≥ 12 |
| 9 | Tremplin / Springboard | 3 | 40 · 80 · 150 (270) | Après une Ascension, on repart 1, 2 puis 3 Grands Splorch **plus haut que le départ normal** (§4.27) ; chaque Grand Splorch sauté grâce au Tremplin rapporte 1 Confetti | A ≥ 1 |
| | **Total des 9 lignes** | **21** | **654** | | |

**Plafond de 6 niveaux offerts** : Tapis de départ (3) + cadeau du Splorch (1 + 2) = 6 au plus ; les niveaux 7 à 12 du Tapis restent des achats de la boucle (sinon le Tapis devenait un achat qu'on ne fait plus).

**Section « Pour le plaisir » / « Just for fun »** (en bas du même onglet, 7 lignes, **2 770 Confettis** ; v2.0 révisé, critique M4 et M10) : **Palettes du spectacle** du Grand Splorch (1 ligne de 6 niveaux : Bonbon, Menthe, Lavande, Arc-en-ciel, Nuit douce, Sucre glace ; 20 chacune), selle « Cotillon » (40), traînée « Serpentins » (50), emote « Danse de Big Plop » (60), **Fanions dorés** (60 : les fanions des décorations gardées deviennent dorés et scintillent), titre « Confetti Star » (100), et **Déco perso de l'Atelier** (1 ligne de 24 niveaux : chaque achat donne l'objet suivant d'une liste fixe de 24 objets de Déco perso, 6 à 30, 6 à 60, 6 à 100, 6 à 200, soit 2 340 ; liste à l'Annexe B). Chaque costume de saison (§7.6) y ajoute ses objets (données), pour que les Confettis gagnés après l'Atelier complet servent encore. Mesuré : les 9 lignes sont finies vers le jour 106 (référence) et 54 (assidu) ; tout, « Pour le plaisir » compris, au jour 79 pour le joueur de 2 h par jour et après le jour 140 pour la référence (25 Confettis en poche au jour 140 : il reste toujours un achat) ; avant la critique, tout était acheté vers le jour 42 par l'assidu, qui gardait ensuite 4 414 Confettis inutiles au jour 84 (§4.24.1).

**Au lancement, tout est là** (décision par défaut n° 6) : les 9 lignes, les 21 niveaux et « Pour le plaisir » ; les conditions (Record R, A) font l'échelonnement. Atelier et « Pour le plaisir » valent **3 424 Confettis** (654 + 2 770 ; v2.0 avant la critique : 1 304, tout acheté vers le jour 42 par le joueur de 2 h par jour, qui gardait ensuite 4 414 Confettis inutiles au jour 84).

*(Critique M3)* **Chaque ligne affiche son effet concret** dans le bandeau, calculé par `UpgradeMath.effect` : « Ta boucle commence avec 3 niveaux de Tapis : environ 2 min gagnées », « 3 décorations de plus restent au Grand Splorch ». L'effet de l'Atelier est **rapporté** par la porte (`atelierEffect` : écart de durée de boucle avec et sans Atelier, §4.24.1), pas bloquant : c'est du confort, et il est dit comme tel.

**Ce que l'Atelier ne vend jamais** (test de contrat sur la liste fermée des effets, `Contract_upgrades.spec`) : rien qui touche la croissance (sauf le Tapis de départ, qui n'est que du Tapis acheté d'avance), une probabilité, la Cuve, les créatures en fuite, le Golden Wobbler, les mutations, les raretés ; rien qui allonge le combo maximal (classement « Meilleur combo » juste, §6.9) ; rien qui double un pass payant (pas de Pot automatique, pas de places au-delà de 18).

**Pourquoi les 8-13 ans vont aimer.** Les meilleurs tycoons séparent une progression remise à zéro et une couche permanente gagnée au prestige (Investisseurs et Powers de Sell Lemons, recherche gardée aux remises à zéro, docs/08 [44][46]). L'Atelier transforme le Grand Splorch en « je gagne quelque chose à moi », pas seulement « ×2 ».

### 4.27 Jelly Ascend, Petit Splorch et Souvenir de gelée *(v2.0 : nouveau)*

**Deux couches de renaissance, et une seule règle à retenir : le Record R.** r est le niveau de Grand Splorch de la boucle en cours ; le **Record R** est le plus haut r jamais atteint (il ne baisse jamais) ; A est le nombre de Jelly Ascend faites. Tout ce qu'on **voit ou possède** (familles d'espèces, Cuve, Meilleurs Amis, Lit douillet, titres, paliers de ranch, changements du ranch, Plopettes, Monuments ouverts, lignes de l'Atelier, cosmétiques, selles) suit le **Record R**. Ce qui règle **l'économie de la boucle** (objectif de taille, prix × 3,5^r, croissance × 2^r, plafond du Tapis Étoilé, Confettis du Grand Splorch) suit **r**. Une Ascension ne fait donc **jamais** disparaître une arche, une buse, un Meilleur Ami ou une Plopette. **Test statique** : aucune lecture du champ `R` du profil hors de `Logic/Prestige` et de `Data/Schema` (`Static_PrestigeOnly.spec`).

| | **Couche 1 : Grand Splorch** (§4.15) | **Couche 2 : Jelly Ascend** |
|---|---|---|
| Condition | Plus gros squishy ≥ objectif(r) (§4.15) | **r ≥ 15** pour la 1re, **20** pour la 2e, puis **+4** à chaque Ascension (24, 28, 32…), et **+5** une fois toutes les 8 Ascensions à partir de la 11e (57, 90, 123, 156, 189, 222, 255) [`Balance.Ascend.ReqR` : liste de 60 conditions ; `ReqStep = 4` au-delà ; réglage de la porte d'économie, docs/04 §21] |
| Repart de zéro | Pièces, Pot, Tapis (et Tapis Étoilé), décorations non gardées, Gants, École, taille de chaque squishy | Tout ce que repart le Grand Splorch, **et r** (retour au Grand Splorch de départ, plus bas) |
| Toujours gardé | Squishies (espèce, mutation, étoiles, tenue, verrou), Record R et tous ses déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, Enclos, Lit, Cuve, selles, Squishydex, Étagère, Fame, jours de Plop, passes, cosmétiques | Idem |
| Gain | Croissance ×2 (pour la boucle), 3 + r Confettis (r compté jusqu'à 20) si c'est un nouveau Record R (1 sinon : Petit Splorch), cadeau du Splorch, le déblocage nommé du Record R atteint (§4.29), +5 Fame (50 par jour au plus) | **Croissance ×3 à chaque boucle, pour toujours** (×3^A) [`GrowthMult = 3`], **+20 Confettis**, une goutte de halo, un élément de ciel, un titre, la ligne Tremplin à l'Atelier, +20 Fame (*critique m10* : **hors du plafond** de 50 par jour ; au plus une Ascension tous les 2 jours, mesuré pour le joueur de 6 h par jour) ; **prix de la boucle × 0,5** pour chacune des 4 premières Ascensions, **× 0,32** de A5 à A10, **× 0,31** ensuite (**× 0,29** aux Ascensions qui demandent un Grand Splorch de plus) [`PriceByA`, critique B1 ; porte d'économie, docs/04 §21] |
| Première fois | 12,6 min (joueur de référence, mesuré) | **Jour 13** pour le joueur de référence (p10 12, p90 14) ; **jour 6** pour le joueur de 2 h par jour (mesuré) |
| Rythme ensuite | — | Une Ascension tous les **10 à 11 jours** (référence, jusqu'au jour 140) et tous les **4 à 5 jours** (assidu) (mesuré, 84 et 140 jours) |

**Grand Splorch de départ après la A-ième Ascension** [`Balance.Ascend.StartFloorOffset = 4.7`] :
`StartR(A) = min(ReqR[A+1] − 10, max(2 × (A − 1), ceil(A × ln 3 / ln 1,3 − 4,7)) + Tremplin)`, où ln 3 / ln 1,3 = 4,19 et Tremplin = 0 à 3 (ligne de l'Atelier). Sans Tremplin : **0, 4, 8, 13, 17, 21, 25, 29, 33, 38** pour A1 à A10. *(Critique M4)* Seuls les Grands Splorch sautés **grâce au Tremplin** rapportent 1 Confetti (3 au plus) ; ceux que saute le plancher ne rapportent rien. Le plancher garde la première boucle après une Ascension au-dessus d'une minute (mesuré : 1 à 3 boucles sur 6 000 sous 45 s, toutes juste après une fusion, §4.24.1) ; le Tremplin **s'ajoute** toujours au plancher, il n'est donc jamais un achat inutile (dans docs/09, le plancher l'effaçait dès A3).

**Bornes** : `MaxA = 60`, `MaxR = 400` (appliquées aussi par le modèle de simulation). *(v2.0 révisé, critique M13)* **Invariant de stabilité**, vérifié au chargement de la configuration (`Props_Prestige.spec`, bloquant ; une configuration en ligne qui le viole est refusée et comptée dans Diagnostics) : **(BeyondMult / 2)^ReqStep ≥ 0,95 × GrowthMult** (aujourd'hui 1,3^4 = 2,856 ≥ 2,85) et **objectif(r + 1) / objectif(r) ≥ 2,5 pour tout r ≥ 16**. Sans lui, une boucle record raccourcit à chaque Ascension et l'économie s'emballe : avec « objectifs × 2,3 dès R16 » (ancien levier H10 de docs/09), la critique mesure le Record R 453 et A = 60 au jour 28 pour l'assidu ; avec `ReqStep = 3` seul, A = 60 au jour 84. Ce levier est **retiré** des leviers sans code (§4.24).

**Facultative, mais montrée** *(v2.0 révisé, critique M1)* : jamais forcée ; continuer r au-delà de la condition ne fait rien perdre. Mais **ne pas la faire rend le jeu creux** (mesuré : référence sans Ascension à 29,9 / 52,1 / 64,3 % de temps « sans but » aux jours 15-28, 29-56, 57-84 ; assidu à 40,8 % dès les jours 8-14) : quand elle est prête et qu'aucun achat n'est possible depuis 5 min, la carte Conseillé « Jelly Ascend » remplace la carte neutre (§10.7.4) et Big Plop fait un geste vers l'Observatoire (une fois par séance) ; l'analytique compte `ascendDeclined` (aperçu fermé, « Plus tard », délai de 20 s) ; la porte joue un profil « refuse la 1re Ascension pendant 3 jours » (§4.24.1). **Rien en Robux** : aucune Ascension vendue, aucun bonus effacé.

**Le Petit Splorch.** Après une Ascension, les Grands Splorch qui ne battent pas le Record R sont des **Petits Splorch** (*critique m3, une seule définition* : **r après la renaissance ≤ Record R**) : mêmes conditions d'entrée (dans son ranch, rien porté, aucun squishy en fuite), mais **hors de la file du serveur** et appliqués tout de suite, d'un seul bloc. *(v2.0 révisé, critique M16 : il y en a environ 15 par Ascension, à des boucles de 4 à 9 min)* **Seul le premier de chaque remontée ouvre l'aperçu** ; les suivants se font en **maintenant ✕ 1,5 s sur la puce d'action spéciale « PETIT SPLORCH ! »** du HUD (§10.2), sans aperçu. La ligne rouge « Tu vas perdre … » et « Dépenser d'abord » n'apparaissent que si une ligne **gardée** est payable ; sinon l'aperçu dit « Tes pièces deviennent le cadeau du Splorch » (neutre : le pilier P2 « on ne perd jamais rien » reste vrai à l'écran ; spec `Panels_SplorchPreview` › « aucun bouton Dépenser d'abord sans ligne gardée payable »). Le serveur écrit sur le ranch l'attribut répliqué **`PetitSplorchAt`** (heure du serveur) : chaque client qui dessine ce ranch en détail complet (lui et ses 2 voisins, §11.5) joue la même animation de **2,5 s** (coupure dure à 4 s) : le squishy saute, rétrécit avec un « pouf », pluie de confettis sur le ranch, petit texte « Plop est là ! ×2 » (vrai nom). Les clients plus loin posent directement l'état final. Pas de bannière, pas de cadeaux aux autres, pas de Fame. Il donne **1 Confetti** et le cadeau du Splorch. Raison : le §2.4 limite chaque serveur à un Grand Splorch toutes les 20 s ; des vétérans à boucles courtes satureraient la file et retarderaient le premier Grand Splorch des nouveaux joueurs.

**Le Souvenir de gelée / Jelly Memory** *(nouveau en v2.0, mesuré nécessaire ; dégressif depuis la critique M6)* : pendant une remontée, la croissance du ranch est **×3 tant que r ≤ Record R − 3**, puis **×2** (r = Record R − 2), **×1,5** (r = Record R − 1) et **×1,25 sur la 1re boucle record** qui suit [`Balance.Ascend.RegainMult = 3`, `Balance.Ascend.RegainTaper = {2, 1.5, 1.25}`] (« Tes squishies se souviennent : ils regrandissent plus vite jusqu'à ton record ! »). Il s'arrête tout seul après la 1re boucle record ; il ne touche que la croissance, jamais une chance ni un prix ; il compte aussi hors ligne. **Pourquoi dégressif** : avec un ×3 qui s'arrêtait net, la 1re boucle record durait 4,6 fois (référence) à 11 fois (assidu) la dernière boucle de remontée ; mesuré avec la pente : **1,2 fois** (référence) et **2,2 fois** (assidu) en médiane, p90 1,8 et 3,7 (clé `regainCliff` ≤ 4 en médiane et au p90, §4.24.1). *(Critique M5)* **La remontée se voit** : le suivi d'objectif du HUD affiche « Retour au record » et « 4 / 15 » ; au retour, **+10 Confettis** et la carte « De retour à ton record 15 ! » (une fois par Ascension). *(Critique B1 (c))* **Étapes du record** : pendant une boucle record (r = Record R), à 25, 50 et 75 % de l'objectif, une petite carte non bloquante « Étape du record : 50 % ! » et un éclat de confettis sur le ranch ; aucune récompense (rien à simuler), pour que les longues boucles record aient des moments. **Pourquoi** (mesuré) : sans lui, une remontée après la 1re Ascension prenait **10 jours** au joueur de référence et le joueur de 2 h par jour, plus riche qu'au premier passage, achetait tout en 5 minutes puis attendait 20 à 30 minutes la fin de chaque boucle ; avec lui, une remontée prend 5 jours (référence) et 1 jour (assidu), en boucles de 3 à 12 min (médianes), et le temps de jeu de l'assidu « à plus de 3 min d'un achat ou d'un but » pendant les remontées tombe à 0-0,8 %. **Ce qu'on voit est vrai** : l'aperçu de l'Ascension le dit (2e ligne de texte, plus bas) ; une pastille « Souvenir ×3 » (puis ×2, ×1,5, ×1,25) s'affiche dans les indicateurs d'état du HUD (§10.2) et dans l'en-tête de l'écran Améliorations (§10.7.3).

**Le moment, étape par étape**
1. Quand r atteint la condition, l'**Observatoire** sur la colline nord braque son faisceau vers le ranch, la puce Menu prend la pastille « ! » (*critique B2* : son libellé « MENU » ne change jamais ; « Jelly Ascend ! » mesurait 221 px pour 168), la puce d'action spéciale affiche « JELLY ASCEND ! » et le bouton de renaissance du rail porte son nom (§10.7.2).
2. **Aperçu** (plein panneau) : 3 tuiles « Tu gagnes » (gabarit tuile 400 × 300, §10.8 règle 11) : « **×3 à chaque boucle, pour toujours** » (*critique M5* : « Croissance ×3 pour toujours » était faux au moment où l'enfant le lit, la croissance passant de 2^15 à 9), « Halo et ciel : Nuage-coussin » (l'élément du A suivant), « +20 Confettis » ; une ligne claire en 40 px (boîte de 1 376 × 120, 2 lignes au facteur 1,5) : « Tu repars au Grand Splorch 0 (ton record : 15). **Tout le reste est gardé.** » (« au Grand Splorch 4 », « 8 »… quand le départ est plus haut ; chiffres arabes, critique M9) ; une 2e ligne **calculée** en 32 px : « Jusqu'à ton record, tes squishies grandissent 9 fois plus vite qu'avant. » (9 = 3 × `RegainMult`, fonction pure `Prestige.regainSpeedup`, testée) ; 6 icônes « gardé » (squishies, Confettis, Atelier, Plopettes, paliers, Squishydex) ; la condition avec sa barre (« Grand Splorch 15 / 15 » et une coche dessinée).
3. **Maintien de ✕ pendant 3 s** (anneau autour d'un glyphe de 64 px), puis une carte « Prêt à monter ? » avec 2 gros boutons de 360 × 112 : « Plus tard » à gauche, « Oui, Ascension ! » à droite (critique m19), ***(critique M1)* focus d'office sur « Oui »**, garde d'entrée de 0,6 s (boutons grisés) **et relâchement de ✕ exigé** (`InputGuard`, §10.7.9), fermée sans rien changer après 20 s.
4. **File** : la même que le Grand Splorch (c'est un grand spectacle). Un joueur n'a jamais qu'**un seul prestige** dans la file (« Ton Grand Splorch passe d'abord ! »).
5. **Spectacle de 10 s** (coupure dure à 12 s) : le faisceau se pose sur le ranch, l'élément de ciel se construit pièce par pièce au-dessus, le Meilleur Ami n° 1 monte dans le faisceau, éclat de lumière, « JELLY ASCEND » et une étoile dessinée avec le chiffre de A, il redescend avec le halo, « ×3 à chaque boucle ! » (critique M5). Le profil change **d'un seul bloc à 4,0 s** (`Prestige.apply(profil, "ascend", maintenant)`), puis il est sauvegardé tout de suite. Le spectacle dessine le Meilleur Ami à partir d'**une copie de sa taille prise au début** : il ne rétrécit pas dans le faisceau, et il redescend à sa nouvelle taille.
6. **Pour les autres joueurs** : « Pluie d'étoiles » (décor) qui donne 120 s de leur revenu (3 par jour au plus) et un bébé de l'espèce du Meilleur Ami (dans les 10 bébés de cadeau par jour du §4.25).

**Le halo** : de 1 à 5 petites gouttes de gelée qui tournent autour de la tête (menthe, ciel, lilas, or, arc-en-ciel à 5 et plus). **Le nombre de gouttes porte l'information**, lisible sans les couleurs ; une goutte dessinée et « 3 » sur la plaque du nom ; réglage « Montrer mon halo » (activé par défaut) ; immobile en Mouvement réduit. **Le ciel du ranch** : A1 Nuage-coussin, A2 Arc de gelée, A3 Aurore sucrée (3 rubans `Neon` courbes, sans particules), A4 Planète bonbon, A5 Anneau prismatique, A6 à A9 variantes de couleur, A10 Constellation, puis une étoile de plus par Ascension jusqu'à A20. **Titres** : A1 « Ascended », A3 « Sky Keeper », A5 « Sky Wobbler », A10 « Star Jelly », A20 « Jelly Galaxy », A40 « Cosmic Jelly », A60 « Jelly Forever ». **Habillages** (gagnés) : A1 « Nuage », A3 « Aurore », A5 « Céleste ».

**Des textes vrais.** Avec une couche au-dessus, « Croissance ×2 pour toujours » deviendrait faux (décision par défaut n° 2) : la tuile du Grand Splorch devient « **Croissance ×2** » et le spectacle dit « Plop est là ! ×2 ! ». « Pour toujours » reste écrit seulement sur ce qui l'est vraiment : squishies, déblocages, Confettis et Atelier, Plopettes, Monuments, paliers de ranch, « ×3 à chaque boucle » de chaque Ascension.

**Pourquoi ces réglages diffèrent de docs/09** (mesuré, §4.24) :
- **Prix × 0,5 puis × 0,32 par Ascension (docs/09 : × 1,6 ; v2.0 avant la critique : × 0,5 fixe ; × 0,31 et × 0,29 dès A11 depuis la porte d'économie : voir la condition, ci-dessous).** Une boucle au même r rapporte 3 fois moins de pièces après une Ascension (elle dure 3 fois moins), et chaque Ascension ajoute 4 r de boucles record. Avec × 1,6, le pouvoir d'achat d'une boucle « record » était divisé par ≈ 5 à chaque Ascension (assidu à 74,5 % « sans but » aux jours 57-84). Avec × 0,5 fixe, il baissait encore de × 1,5 par Ascension : 24 % aux jours 57-84, puis **36,7 %** et **62,5 %** aux jours 85-112 et 113-140 (mesure de la critique, 140 jours), Tapis Étoilé jamais acheté au-delà de r = 16. Avec la table (× 0,5 aux 4 premières, × 0,32 ensuite) : 10,6 / 15,5 / 16,1 / 16,5 / 14,8 % de temps « sans but » aux jours 2-7 … 57-84, puis 13,9 / 11,7 % aux jours 85-112 / 113-140 ; Tapis 12 atteint entre 0,58 et 0,87 de chaque boucle record de A1 à A38 ; pièces perdues au Grand Splorch 0,7 à 2,4 T12 (§4.24.1). Essayés et écartés (assidu, 140 jours) : × 0,4 jusqu'à A12 puis × 1/3 (proposition de départ de la critique : Tapis 12 atteint à 1,00 de la boucle dès A9, pouvoir d'achat qui baisse encore) ; × 0,3 dès A5 (trop riche : pièces perdues au Grand Splorch 3 à 7,5 T12 au-delà de A19) ; × 0,33 dès A5 (Tapis 12 à 0,93-1,00 au-delà de A26).
- **Souvenir de gelée (absent de docs/09)** : voir plus haut.
- **Plancher de `StartR` décalé de 8,9 à 4,7** : le Souvenir de gelée raccourcit déjà les premières boucles ; avec 8,9, le départ montait trop haut et sautait des boucles faciles et joyeuses.
- **La condition 15, 20, puis +4 (et +5 une fois toutes les 8 Ascensions dès la 11e)** : chaque r de plus allonge une boucle record de × 1,3 (objectif × 2,6, croissance × 2) ; 1,3^4 = 2,86 ≈ 3, donc la boucle record garde à peu près la même durée d'une Ascension à l'autre (mesuré : boucles record de 33 à 41 min de jeu pour la référence de A1 à A13 ; de 96 à 108 min pour l'assidu de A1 à A10, puis 60 à 75 min de A20 à A32, le Tapis Étoilé de nouveau acheté accélérant la boucle). C'est l'invariant de stabilité plus haut. *Réglage de la porte d'économie (lot A1, 5 novembre 2026, docs/04 §21)* : 2,86 tient l'invariant (≥ 0,95 × 3) mais la boucle record raccourcissait d'environ 3 % par Ascension : une Ascension tous les 9 jours pour la référence après A11, tous les 3 jours pour l'assidu après A22 (limites de `ascendGapDays` : 10-16 et 4-8 jours, pour chaque Ascension jusqu'au jour 140). Un Grand Splorch de plus une fois toutes les 8 Ascensions à partir de la 11e (pas moyen 4,125) garde la difficulté de la dernière boucle record entre 0,73 et 1 fois celle de A1 jusqu'à A60 ; avec lui, les prix × 0,31 dès A11 (× 0,29 aux Ascensions d'un Grand Splorch de plus), sans lesquels le Tapis Étoilé n'était presque plus acheté dans les boucles record tardives. Mesuré (160 joueurs, 140 jours) : référence 10 à 12 jours entre deux Ascensions de A1 à A12 ; assidu 5 jours (4 au pire), A = 28 au jour 140.

### 4.28 Les Plopettes *(v2.0 : nouveau)*

De petites aides mignonnes et nommées, **gardées pour toujours**, qui pressent les squishies prêts que le joueur ne presse pas. Des personnages qui travaillent pour toi sont le cœur des tycoons qui marchent (managers de Sell Lemons, employés de Restaurant Tycoon 3, docs/08 [43][55]) ; les nôtres sont mignons et nommés. **Disponibles au lancement** (décision par défaut n° 3).

| Plopette | Arrive | Aspect (≤ 5 pièces) |
|---|---|---|
| **Pip** | Record R 2 | Petite goutte rose à tablier |
| **Pop** | Record R 4 | Goutte menthe, bonnet à pompon |
| **Pim** | Record R 6 | Goutte citron, lunettes rondes |
| **Pom** | Record R 8 | Goutte lilas, nœud papillon |
| **Puff** | Record R 12 | Goutte nuage, cape |
| **Plume** | Atelier, 40 Confettis, dès le Record R 12 | Goutte arc-en-ciel, plume sur la tête |

**Comment elles pressent** (règles du serveur, `HelperService`, tick de 10 Hz) :
- **Cible et heure choisies par le serveur** : le serveur choisit un squishy de l'enclos ou du Bassin **prêt depuis au moins 3 s**, ni porté, ni en attente de Grand Splorch, **à plus de 12 studs à plat de la position validée du joueur** (sa portée de pression est de 10 studs : une Plopette ne vole jamais le squishy que l'enfant vise), et l'heure de la pression `tPress` = maintenant + temps de trajet (fonction pure des deux positions, 3 s au plus). Le client règle le saut de la Plopette pour atterrir à `tPress`. À `tPress`, le serveur **revérifie** « prête depuis 3 s » et la règle des 12 studs ; sinon il abandonne et choisit une autre cible. À égalité, la pression du joueur gagne.
- **Rythme** : une pression toutes les `12 − 0,3 × niveau de l'École` secondes par Plopette (12 s sans École, 6 s à l'École 20).
- **Récompense** : `pressReward(revenu du squishy, PERFECT = non, série = 0, Kitty) × Gants`, soit une pression normale sans PERFECT ni série (docs/09 : la moitié ; mesuré trop faible, 3 % des pièces au jour 7). Une pression d'aide ne compte ni pour la jauge du serveur, ni pour les objectifs, ni pour les classements.
- **Quand** : seulement si le propriétaire est sur le serveur ; **sieste après 5 min sans aucune intention de jeu acceptée ni navigation dans un menu** du joueur (*v2.0 révisé, critique m17* : une pression, un achat, une capture… acceptés par le serveur, ou la navigation dans un menu ouvert — intention `MenuActivity`, une au plus toutes les 20 s, décision du propriétaire du 6 novembre ; elle ne compte que pour les Plopettes, jamais pour la jauge ni le MEGA, et ne donne jamais rien ; un stick calé ou une touche maintenue ne comptent pas) (« Fait la sieste », petite bulle « z »), réveil à la première intention acceptée ou navigation dans un menu ; pause pendant son Grand Splorch, sa Jelly Ascend et le BOOP RUSH à sa clôture.
- **Mesuré** (§4.24.1) : les Plopettes font **8 %** des pièces gagnées en jeu au jour 7 pour le joueur de référence (7 à 8 % selon la taille du serveur ; cible 5-15 %), **10,7 %** pour l'assidu ; les pressions du joueur restent à 63-64 % (minimum 50 %).
- **Maisonnette des Plopettes** : petite cabane de 6 pièces dans le ranch (§11.2), où elles dorment pendant la sieste.

Réseau : `HelperPress { helper, uid, tPress }` regroupé par tick (§12.7). États : `idle`, `moving` (3 s au plus, §12.10), `nap`, `paused`.

### 4.29 Un déblocage nommé et visible à chaque Record R *(v2.0 : nouveau)*

Une seule table en données (`Balance.Splorch.Unlocks` pour ce qui se débloque, `Config/Visuals.RanchByRecordR` pour ce qui se voit), lue par le serveur, l'aperçu et le rendu du ranch. Chaque ligne s'applique **au premier passage** du Record R. **Tout est disponible au lancement** (décision par défaut n° 6) : la colonne « plus tard » de docs/09 (habillages, Plopettes en décembre) est fusionnée ici.

| Record R | Débloqué (tuile de l'aperçu) | Ce qui change dans le ranch |
|---|---|---|
| 1 | **Atelier de Big Plop** (+4 Confettis) · **Gants Moelleux** · famille Axolo · cadeau du Splorch · habillage « Guimauve » | Palier 1 **Arche à pompons** · Cuve : 2e anneau, 1re buse |
| 2 | **Place d'enclos offerte** · **Pip** et l'École des Plopettes · selle « Confetti » | Pot **argent** · coussin offert · Cuve : 3e anneau, 2e buse, agitateur plus rapide · maisonnette des Plopettes |
| 3 | Famille Bunny · 2e Meilleur Ami · Lit douillet · habillage « Caramel » | Palier 2 **Tour à bonbons** · Cuve : 4e anneau, 3e buse |
| 4 | **Pop** · emote « Splorch ! » | **Agitateur arc-en-ciel** (vitesse maximale) · 5e anneau, 4e buse |
| 5 | Famille Spiky · titre Splorch Star · habillage « Menthe glacée » | Palier 3 **Balcon de gelée** · 5 buses (maximum) · 6e anneau |
| 6 | **Place offerte** · **Pim** · Monument 1 · traînée « Confettis » · Tapis Étoilé 13 | Pot **doré** · coussin offert · 7e anneau |
| 7 | **Cuve dorée** · tenue « Chapeau de fête » · Tapis Étoilé 14 | La Cuve devient dorée (8e anneau), visible de la rue |
| 8 | **« 3 décorations restent »** · **Pom** · Monument 2 · Tapis Étoilé 15 | Fanion ★ sur les 3 décorations gardées |
| 9 | Palette de spectacle « Feu d'artifice » · drapeau « IX » · Tapis Étoilé 16 | **Bassin-fontaine** : 3 jets de gelée |
| 10 | 3e Meilleur Ami · titre Splorch Legend · **Tapis Étoilé 17-20** · Monument 3 · habillage « Phare » | Palier 4 **Phare de gelée** |
| 11 | **Place offerte** · selle « Gelée d'or » | **Coussins étoilés** · coussin offert |
| 12 | **Puff** · Monument 4 · ligne **Plume** à l'Atelier · habillage « Glacier sucré » | **8 lampions** sur la clôture (allumés pendant la Jelly Moon) |
| 13 | Emote « Ola » · traînée « Arc de gelée » | **Portail arc-en-ciel** (7 segments fixes, aucun clignotement) |
| 14 | **« 3 décorations de plus restent »** (6) · Monument 5 | Fanions ★ sur 6 décorations |
| 15 | Titre Splorch Hero · **Jelly Ascend** · habillage « Néon » | Palier 5 **Dôme néon** · faisceau de l'Observatoire quand l'Ascension est prête |
| 16 | **Place offerte** · Monument 6 · tenue « Lunettes étoiles » | Pot **cristal** (matériau `Ice`, sans transparence) · coussin offert |
| 17 | Selle « Cosmos » · habillage « Cosmos sucré » | **Geyser de gelée** dans le ranch, côté rue (Z = 4 à 10, à 6 studs au moins des dalles, hors du chemin du portail) |
| 18 | Monument 7 | **Cadre doré** autour de la silhouette du ranch |
| 19 | Emote « Couronne de confettis » · drapeau « Splorch Royal » | **Étagère à trophées dorée** |
| 20 | Titre Jelly Titan · Monument 8 · selle « Titan » · habillage « Royal » | Palier 6 **Couronne flottante** |
| 21 et plus | **Prime de record** (+10 Confettis au premier passage de chaque Record R) | — |
| 22, 24 | Monuments 9 et 10 | — |
| 25, 30, 35, 40 | Titres Splorch Myth, Jelly Monarch, Wobble Legend, Cosmic Splorcher · une couleur de traînée | 1 à 4 étoiles sur la couronne |
| 50, puis tous les 10 jusqu'à 400 (`MaxR`) | Titre (36 titres, liste EN / FR à l'Annexe B, critique M10) | Couronne arc-en-ciel au 50 |

**Note sur le Tapis Étoilé** : la colonne « Débloqué » rappelle quand un niveau **peut** s'acheter dans une boucle ; c'est r de la boucle qui décide (§4.6), pas le Record R. L'aperçu ne l'affiche qu'au premier passage, comme les autres lignes.

**L'aperçu montre toujours 3 tuiles concrètes**, jamais une tuile vide : « Croissance ×2 » ; le déblocage de ce Record R (une image et 2-3 mots : « Place d'enclos offerte », « 3 décorations restent ! ») ou, s'il est déjà gagné, « Cadeau du Splorch » ; « +13 Confettis » pour un Grand Splorch, **« Petit Splorch : +1 Confetti »** pour un Petit Splorch (« Cadeau du Splorch » quand l'Atelier et « Pour le plaisir » sont complets, §4.26).

**Test bloquant** (`RanchLook.spec`, `Contract_unlocks.spec`) : chaque Record R de 1 à 20 a au moins un déblocage nommé **et** au moins un changement visible ; chaque clé existe en anglais et en français ; l'aperçu montre toujours 3 tuiles ; chaque R de 21 à 400 a au moins une ligne (prime de record ou titre).

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

Répartition : Commun 6, Peu commun 6, Rare 3, Épique 5, Légendaire 3, Mythique 1, Secret 2. Chaque famille a 4 espèces : un Commun, un Peu commun, puis deux plus rares. Les Secrets n'ont pas de famille (page « Secrets » du Squishydex) et ne comptent pas dans les bonus de famille. **Espèces de la semaine** (§7.6) : elles ne rejoignent jamais une famille déjà complète (un bonus gagné ne se perd jamais, §4.17) ; elles forment une nouvelle famille de 4 (une famille par mois) ou restent sans famille. Rien dans les données ni dans le code ne suppose 26 espèces : tout ce qui est rangé par espèce (Squishydex, Étagère, rotation du MEGA) suit la liste publiée.

**Champs réservés pour plus tard** dans chaque ligne (valeur au lancement) : `release = 0` (horodatage UTC d'arrivée ; les lignes futures sont publiées en avance et s'activent seules), `duo = false` (espèce Duo, janvier), `recipe = nil` (combinaison World First, janvier), `limitedUntil = 0` et `encore = {}` (semaines « Encore », février).

**Rotation du MEGA SQUISH** : le géant prend une espèce de la liste des espèces **non secrètes déjà publiées** (`release` ≤ maintenant), rangée par identifiant : l'élément `((semaine + numéro du MEGA dans la semaine) mod taille de la liste) + 1` (semaine = `Clock.week()`). Une espèce publiée le samedi entre donc dans la rotation toute seule ; un « mod 24 » écrit en dur l'aurait oubliée.

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

### 5.4 Cosmétiques *(v2.0 : modifié)*

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
| *(v2.0)* Selles | Confetti / Gelée d'or / Cosmos / Titan | Record R 2 / 11 / 17 / 20 |
| | Cotillon ; Brique ; Sucre glace ; Cosmique | Atelier (40 Confettis) ; Carnet 100 ; costume d'hiver (5 jours de Plop) ; taille 1e15 |
| *(v2.0)* Traînées | Confettis / Arc de gelée | Record R 6 / 13 |
| | Serpentins ; Petits marteaux ; Étoiles filantes | Atelier (50) ; Carnet 1 000 ; taille 1e18 |
| *(v2.0)* Emotes | « Splorch ! » / « Ola » / « Couronne de confettis » ; « Danse de Big Plop » | Record R 4 / 13 / 19 ; Atelier (60) |
| *(v2.0)* Tenues | Chapeau de fête / Lunettes étoiles | Record R 7 / 16 |
| *(v2.0)* Titres | Splorch Myth, Jelly Monarch, Wobble Legend, Cosmic Splorcher ; puis tous les 10 jusqu'à 400 | Record R 25 / 30 / 35 / 40 ; 50 à 400 |
| | Ascended, Sky Keeper, Sky Wobbler, Star Jelly, Jelly Galaxy, Cosmic Jelly, Jelly Forever | A 1 / 3 / 5 / 10 / 20 / 40 / 60 |
| | Confetti Star ; Bâtisseur, Architecte, Grand Architecte ; Gardien du Soleil (Sun Keeper) | Atelier (100) ; Carnet 50 / 500 / 5 000 ; taille 1e24 |
| *(v2.0)* Drapeaux | « IX » / « Splorch Royal » ; « Chantier » | Record R 9 / 19 ; Carnet 250 |
| *(v2.0)* Palettes du spectacle du Grand Splorch | Feu d'artifice ; Bonbon, Menthe, Lavande, Arc-en-ciel, Nuit douce, Sucre glace | Record R 9 ; Atelier (20 chacune) |
| *(v2.0)* Habillages de ranch (14) | Les 3 de la v1.3 + Guimauve, Caramel, Menthe glacée, Phare, Glacier sucré, Néon, Cosmos sucré, Royal, Nuage, Aurore, Céleste ; Atelier | Record R 1 à 20, A 1 / 3 / 5 (§11.5) ; Carnet 2 500 |
| *(v2.0)* Halo, ciel | 1 à 5 gouttes ; 20 éléments de ciel | A 1 à 20 (§4.27) |
| *(v2.0)* Déco perso | 40 objets sur 12 emplacements (liste à l'Annexe B) | 16 gagnés (Squishydex, jours de Plop, objectifs, Jelly Moon, piste de la semaine, Carnet) et 24 achetés en Confettis gagnés à l'Atelier (§4.26, critique M4) ; jamais au hasard ni en Robux (§11.5) |
| *(v2.0)* Cosmétique de la semaine | 8 en rotation (retour au plus tard 8 semaines après) | Palier 12 de la piste de la semaine (§7.5) |

**Palette des 16 ranchs** (couleur du propriétaire) : 1 Corail (255, 130, 120) · 2 Pêche (255, 180, 130) · 3 Citron (250, 225, 100) · 4 Citron vert (170, 225, 100) · 5 Menthe (110, 225, 170) · 6 Sarcelle (70, 205, 205) · 7 Ciel (110, 180, 255) · 8 Pervenche (140, 150, 250) · 9 Lilas (185, 140, 250) · 10 Orchidée (225, 130, 225) · 11 Rose (255, 130, 180) · 12 Framboise (230, 90, 130) · 13 Caramel (215, 160, 100) · 14 Sable (225, 205, 160) · 15 Écume (150, 235, 215) · 16 Nuage (180, 195, 215). Ranch libre : gris (130, 130, 140), sans lumière.

### 5.5 Récapitulatif du contenu au lancement *(v2.0 : réécrit)*

| Type | Au lancement (v2.0) | v1.3 |
|---|---|---|
| Espèces | 24 (6 familles × 4) + 2 Secrets = 26, puis une par semaine | Idem |
| Raretés, mutations | 7, 9 | Idem |
| Squishydex | 26 pages + 234 entrées de mutation + 130 badges d'étoiles ; 6 bonus de famille ; 9 jalons ; **maîtrise d'espèce** ; jalons de taille géante | Sans maîtrise ni jalons géants |
| **Familles d'amélioration** | **9** : Tapis à Goûter (12), Tapis Étoilé (8), Décorations (18), Enclos (14), Lit douillet (1), Gants Moelleux (40), École des Plopettes (20), Monuments (10), Atelier de Big Plop (9 lignes, 21 niveaux) : **144 niveaux** (v2.0 révisé, critique M3), plus 35 objets « Pour le plaisir » | 4 familles, 45 niveaux |
| Renaissance | Grand Splorch, Petit Splorch, **Jelly Ascend** (A1 à A60), Souvenir de gelée ; un déblocage nommé **et** un changement visible à chaque Record R de 1 à 20, puis des titres jusqu'à 400 | 1 couche, 4 déblocages nommés |
| Monnaies | Pièces, **Confettis** (gagnés), Fame (score) | Pièces, Fame |
| Aides | **6 Plopettes** | 0 |
| Ranch qui évolue | **6 paliers**, 10 Monuments, Tapis en 6 paliers, coussins, lit à baldaquin, socles, décorations dorées, Cuve et Pot qui montrent leur niveau, halo et ciel | Couleur du Tapis seulement |
| Personnalité des squishies | 6 personnalités, 18 saynètes, 6 visages, 5 tours appris | 1 visage |
| Événements récurrents | Créature en fuite, Golden Wobbler, BOOP RUSH + Wild Wobblers, MEGA SQUISH, jauge et Wobble Party, Jelly Moon ; **météo visuelle**, place en fête | Sans météo ni place en fête |
| Rétention | Nourrir Plop (12 paliers), 3 objectifs du jour, 5 classements, carte « Plop a sommeil » ; **piste de la semaine** (gratuite), **3 Défis de Splorch**, **Carnet du Ranch**, Livre des records, jumelles et cœurs, mode photo | Sans piste, Défis ni Carnet |
| Cosmétiques | 11 selles de la v1.3 + 8 ; 8 traînées + 5 ; 4 tenues + 3 ; titres de la v1.3 + 15 (et 36 titres de Record R 50 à 400) ; **14 habillages** ; **40 objets de Déco perso** ; 7 palettes ; 8 cosmétiques de la semaine (liste complète EN / FR : Annexe B) | 11 selles, 8 traînées, 4 tenues, 12 titres, 3 thèmes |
| Monde | Wobbleton, 16 ranchs, Observatoire, kiosque de Big Plop, jardin de la Prairie des copains, costume d'hiver « Frost & Sprinkles » | Sans Observatoire ni kiosque |
| Nouveaux articles en Robux | **0** | — |

### 5.6 Des squishies qui ont du caractère *(v2.0 : nouveau)*

Tout est **calculé et dessiné par le client** à partir des pièces existantes : aucune pièce en plus, aucun trafic réseau, aucune règle du serveur ne dépend d'une saynète.

**Six personnalités** (colonne `perso` de `Config/Species` ; une espèce nouvelle reçoit la sienne dans sa ligne de données, sans code)

| Personnalité (FR / EN) | Espèces | Saynète 1 | Saynète 2 | Saynète 3 |
|---|---|---|---|---|
| **Curieux / Curious** | Plop, Whiskerwob, Lotlolly, Moonhop, Moonplop | « Coucou » : se penche vers le joueur (1,5 s) | « Tour de place » : petit cercle de 1,5 stud (3 s) | « C'est quoi ? » : regarde la dernière décoration construite, « ? » au-dessus (2 s) |
| **Dormeur / Sleepy** | Wibble, Purrpudding, Lilypuff, Hopscotch | « Bâillement » (2 s) | « Mini-sieste », bulle « z » (3 s) | « Réveil en sursaut » (1 s) |
| **Rebondi / Bouncy** | Ribbit Drop, Boingtoad, Clover Hop, Nubbin | « Triple saut » de 1,5 stud (1,8 s) | « Toupie » : 2 tours (1 s) | « Plat ! » : saut de 3 studs, atterrissage penché de 20° (1,5 s) |
| **Câlin / Cuddly** | Mochi Mew, Frillo, Bunbun, Prickle Puff | « Cœurs » : 3 cœurs si le joueur est à 8 studs ou moins (2 s) | « Bisou au voisin » (2 s) | « Dandinement » : ±10° à 2 Hz (2 s) |
| **Farceur / Prankster** | Jiggleberry, Croakaroo, Gillygum, Drago Drop | « Langue » : clin d'œil (1,5 s) | « Faux éternuement » : inspire… rien, puis rit (2,5 s ; jamais le texte « ATCHOUM », réservé au Rush) | « Cache-cache » : s'aplatit puis ressort (2 s) |
| **Fier / Proud** | Grand Gloop, Blossompurr, Coralotl, Emberwob, Royal Plop | « Pose » : petit saut sur place, 2 étoiles (2 s) | « Révérence » (1,5 s) | « Défilé » : avance de 1,5 stud et revient (3 s) |

« Fier » est réservé aux Légendaires, Mythiques et Secrets : un petit signe de rareté de plus. **Règles** : une saynète toutes les **8 à 20 s** par squishy à 40 studs de la caméra ou moins ; **6 au plus qui commencent** en même temps (3 en qualité réduite), les plus proches d'abord : la limite empêche d'en commencer une 7e, elle n'en coupe jamais une en cours ; jamais pendant un portage, une fusion, un Rush à la clôture ou un grand spectacle ; une pression ou un ciblage l'arrête tout de suite. **Jamais à plus de 2 studs de sa place** (le serveur mesure les portées depuis la place, §4.7). **Le ciblage (`TargetRules`) et la projection du clic lisent toujours la place de repos du squishy, jamais le modèle animé** : l'invite □ ne saute jamais d'un voisin à l'autre (spec : cible stable pendant chaque saynète). **`CFrame` seulement** : les saynètes déplacent les pièces existantes dans la passe `BulkMoveTo` (une par image), sans toucher à `Size`.

**Six visages** faits avec les pièces existantes : Content (défaut), **Ravi** (yeux en arc « ^ ^ »), **Surpris** (yeux ×1,2, bouche ronde), **Endormi**, **Étoilé** (reflets ×1,6 en `Neon`), **Boudeur** (visage du Flop). **Réactions** : achat dans le ranch (tous se tournent, Ravi, petit saut ; une fois toutes les 2 s au plus) ; série PERFECT ×5 (Ravi) ; sirène du Rush (Surpris) ; MEGA qui atterrit à 120 studs ou moins (Surpris) ; Grand Splorch d'un autre (Étoilé, regardent la place) ; début de la Jelly Moon (Étoilé, regardent la lune) ; retour du joueur après 60 s dehors (le Meilleur Ami : Ravi + 3 cœurs) ; joueur immobile 60 s (ceux à 15 studs s'endorment). Un visage revient toujours à « Content » à la fin de sa durée, même si l'événement de fin manque. Un changement de visage écrit les tailles des yeux et des reflets **en une seule écriture**, sans animation de `Size`. **Yeux « bébé »** : taille et hauteur des yeux en configuration ; 3 versions comparées devant des enfants de 8 à 13 ans sur une télé (test M14) : A = 0,22 D à +0,12 D (v1.3), B = 0,26 D à +0,04 D, C = 0,30 D à 0,00 D ; décision avant le gel du contenu.

**Cinq tours appris en grandissant** : chaque espèce apprend un tour quand son record de taille (Étagère, §4.16) passe 100 (« Coucou »), 1 200 (« Toupie »), 1 million (« Salto »), 1 milliard (« Danse »), 1e12 (« Feu d'artifice »). Le Meilleur Ami fait son plus beau tour quand le joueur joue l'emote « Bravo » (aucun message réseau de plus : l'emote est déjà répliquée).

**Événements relookés pour la télé** : le géant du MEGA a des expressions ; une **lune de gelée** de 80 studs (4 pièces) ouvre les yeux au début de chaque Jelly Moon et fait un clin d'œil par minute ; le Golden Wobbler laisse des **traces dorées** (6 empreintes qui rétrécissent) qu'on suit à l'œil ; les lampadaires passent une fois au rose à la sirène du Rush (aucun clignotement) ; ballons de la Wobble Party au-dessus de la place.

**Météo de Wobbleton, purement visuelle** (décision par défaut n° 4) : fenêtres de 5 min à **:08-:13 et :38-:43 UTC** (les seules sans Rush ni MEGA), la même sur tous les serveurs (fonction pure de l'heure, `Logic/AmbienceRules`), suspendue pendant la Jelly Moon : Pluie de vermicelles, Brise de bulles, Ciel de guimauve, Arc-en-ciel de gelée. **Aucun bonus de mutation, aucun effet sur le jeu** : rien à simuler, rien à afficher dans le Guide. Une pastille d'événement discrète (« Brise de bulles ») et des particules (≤ 60 par seconde, à la place des flocons d'hiver).

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
- **La physique n'est qu'un confort** : la clôture est doublée d'un mur invisible ancré et solide de **30 studs** de haut, plus haut que toute portée (saut de la selle géante 13 + hausse de la monture 6 + 3 de marge = 22) : personne ne l'enjambe, même en monture ou en bondissant, et aucune position « debout sur le mur » n'existe ; la membrane du portail est non solide pour le serveur, et chaque client la rend solide **pour lui seul** sur les ranchs des autres (réglage local de `CanCollide`, qui ne touche que son propre personnage). Si ce confort rate (latence, personnage en réapparition), la poussée du serveur rattrape tout.
- Pendant le BOOP RUSH, on boope **par-dessus la clôture**, depuis la rue. La poursuite a lieu **dans la ville**.

### 6.4 Pet-sitting (presser chez un ami)

- Quand un **ami Roblox** se tient devant ta clôture (à 10 studs au plus), jusqu'à 3 de tes squishies prêts viennent à la clôture (hors Rush ; ils ne s'enfuient jamais).
- L'ami les presse depuis la rue (même geste que chez soi, PERFECT compris ; cible au choix avec L1 / R1 ou un clic, §10.4), par un message à lui : `PetPress(ownerId, uid, tClient)` (§12.7). **Le propriétaire** reçoit la récompense normale de la pression (sans PERFECT). **Le visiteur** reçoit **2 s** de son propre revenu (×2 si PERFECT) et 1 point du classement « Plus serviable » (20 au plus par ami et par jour). La recharge de 8 s du squishy s'applique.
- **100** pressions de pet-sitting récompensées par jour et par visiteur, et **100** reçues par jour et par propriétaire. Fonctionne même si le propriétaire est occupé ailleurs sur le serveur. Dans la version 1.2, le visiteur gagnait 10 s de **tout** son revenu par pression, sur 3 squishies toutes les 8 s : 2 à 4 fois plus que presser chez soi, et un second compte remplissait le classement.

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

### 6.6 Voir ce que font les autres *(v2.0 : modifié)*

- **Silhouette** : le meilleur squishy de chaque ranch flotte au-dessus du ranch (Y = 40), à sa vraie échelle jusqu'à 19×, avec sa taille. On voit de loin qui a le plus gros.
- **Statue de la place** : le plus gros squishy du serveur, en direct, sur un socle avec le nom du propriétaire (ou « Ranch 7 ») et sa taille.
- *(v2.0)* **Le ranch des autres raconte leur progression** : paliers de ranch, Monuments, habillage, signal « prêt » (anneau rose, phare rose), faisceau de l'Observatoire quand une Jelly Ascend est prête, **halo** (1 à 5 gouttes, lisible sans couleur) et **ciel** au-dessus du ranch (§4.27, §11.5).
- **Fanfare des records du serveur** : le premier joueur du serveur à dépasser 1 million, 1 milliard, 1e12 et 1e15 a droit à une fanfare et une bannière (une fois par seuil et par serveur).
- **Bannières de serveur** : file de 3 au plus, 3 s chacune, priorité décroissante : Grand Splorch > naissance Secret ou Mythique, ou mutation Flop, Glitch ou Arc-en-ciel > combo ≥ 5 > naissance Légendaire > fanfare de record > Golden Wobbler attrapé > Squish Party. Un même joueur déclenche au plus une bannière toutes les 10 s. **Une seule bannière à l'écran à la fois**, dans l'emplacement de message du HUD (§10.2). Un nouveau, avant l'étape 9 de l'accueil, ne voit pas celles des autres (§3). Exemples : « Mira : GRAND SPLORCH ! », « Noah a fait naître un SECRET Royal Plop (1 sur 2 500) ! », « Léa : FLOP PLOP ! 1 sur 270 000 », « Sam : COMBO x5 ! ».

### 6.7 Grand Splorch des autres : cadeaux et applaudissements

- Chaque Grand Splorch fait pleuvoir sur **tous** les autres joueurs : 60 s de leur revenu et un bébé (§4.15).
- Pendant 8 s, chaque autre joueur qui a la version complète du spectacle (au plus une fois toutes les 3 min, §4.15) voit une grande puce **APPLAUDIR** avec le glyphe croix → (F au clavier, ou clic sur la puce ; elle prend la place de la puce GRAND SPLORCH, §10.2). Elle n'apparaît jamais pendant une poursuite (créature attrapable à 30 studs ou moins), un maintien ou une fenêtre ouverte : la croix → garde alors son emote « Merci ». Appuyer joue l'emote `cheer` et lance un arc de confettis vers le héros. L'applaudisseur gagne 10 s de son revenu (10 applaudissements récompensés par jour) ; le héros voit « 12 joueurs t'applaudissent ! ».

### 6.8 Moments coopératifs

- **MEGA SQUISH** (§4.22) : tout le serveur presse le géant ; chaque participant reçoit au moins un bébé en cas de réussite.
- **Jauge du serveur** (§4.23) : les actions de chacun comptent (pressions PERFECT, naissances, captures, fusions…) ; pleine, tout le monde gagne ×2 pendant 5 min, puis Big Plop fait une sieste de 20 min.
- **Golden Wobbler** (§4.11) : course amicale ; tous ceux qui sont près gagnent quelque chose.
- **Squish Party** (§8.3) : un achat qui profite à tout le serveur.

### 6.9 Classements de la semaine

**Règle honnête.** Aucun achat ne donne directement de points de classement. Mais ×2 Pièces et la Squish Party accélèrent le ranch, donc indirectement tout ce qui suit la progression (taille, nombre de Grands Splorch, familles débloquées). C'est pourquoi **la taille n'est pas un classement mondial** : sur une semaine, « y arriver plus tôt » voudrait dire « plus haut ». Le plus gros squishy reste sur la statue de la place, au niveau du serveur, sans titre (§6.6).

| Classement | Mesure | Égalité | Lien avec l'argent |
|---|---|---|---|
| **Plus de tampons** (Stamp Hunter) | Nouveaux tampons et badges d'étoiles du Squishydex gagnés cette semaine | Premier arrivé | Faible et indirect (familles débloquées plus tôt). Un nouveau joueur peut gagner sa première semaine |
| **Meilleur combo** (Combo Star) | Plus long combo de fusion (×5 au plus, ×6 avec la famille Axolo) | **Premier arrivé**, jamais la taille | Aucun |
| **Meilleure capture** (Top Catcher) | Plus forte valeur de capture = rareté × mutation de la créature attrapée (fuite, Golden, Rush, Wild Wobbler) | Premier arrivé | Faible et indirect (la qualité de la Cuve suit R) |
| **Plus serviable** (Super Helper) | Pressions de pet-sitting récompensées (100 par jour au plus, 20 au plus par ami et par jour : il faut aider 5 amis différents pour compter 100) | Premier arrivé | Aucun |
| **Plus généreux** (Big Heart) | Bébés donnés : bébés reçus par d'autres grâce à tes squishies en fuite et à tes Grands Splorch | Premier arrivé | Faible et indirect (un ranch plus rapide fait plus de Grands Splorch) |

**Pourquoi pas « Meilleure série PERFECT »** : un PERFECT se vérifie avec l'heure envoyée par le client (§4.7). Un script peut donc réussir 100 % de PERFECT. Dans le ranch, le gain reste borné (×2) ; dans un classement mondial, le haut du tableau serait rempli de tricheurs.

- **Onglet Classements** : d'abord « **Ma place sur ce serveur** » et « **Mon record contre la semaine dernière** » (flèche verte s'il est battu), puis le top 10 mondial. Un enfant voit un but à sa portée avant de voir les champions.
- Stockage : un `OrderedDataStore` par classement et par semaine (`Weekly_<clé>_<semaine>`). Un `OrderedDataStore` ne garde que des **entiers** : la valeur écrite code le score, l'égalité « premier arrivé » et le nom caché dans un seul entier, `((score × 2^20) + (2^20 − 1 − secondes écoulées depuis lundi 00:00 UTC)) × 2 + caché` (une semaine compte 604 800 s < 2^20), décodé à l'affichage. Le plus grand score possible (meilleure capture : 5 000 × 100 = 500 000) donne ≈ 1,05e12, loin sous 2^53 : aucun arrondi. Aucune taille n'est écrite dans un classement. Écriture quand un joueur bat son record de la semaine (file par serveur, vidée toutes les 60 s) ; lecture du top 10 toutes les 120 s. Tableau du serveur en direct. Le record de la semaine passée est gardé dans le profil (`weekly.prev`).
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

### 7.1 Crochets par horizon (fidélité sur 28 jours, Étude §6.2) *(v2.0 : modifié)*

| Horizon | Crochets |
|---|---|
| **J1** | Récompense à 10 s ; fusion à 1:00 ; capture à 2:00 ; monture vers 4:30 ; premier Grand Splorch vers 13 min ; choix Rush / Cozy à 15 min, au calme ; un événement de serveur au plus toutes les 10 min ; message « Tes squishies grandissent même quand tu dors » à 10 min de jeu et en bas du panneau Réglages |
| **J2-J7** | Écran de retour (croissance hors ligne visible) ; Nourrir Plop (jours au total) ; 3 objectifs du jour ; nouvelles familles à R = 1, 3, 5 ; Squishydex ; Meilleur Ami ; première Jelly Moon |
| **J8-J28** | Grands Splorch 11 à 20 ; mutations rares (Galaxie, Arc-en-ciel, Glitch, Flop) ; étoiles ★5 ; Étagère à trophées ; Fame ; classements de la semaine ; une espèce nouvelle chaque semaine ; costumes de saison ; *(v2.0)* paliers de ranch (Phare R10, Dôme R15, Couronne R20), Monuments, Plopettes, Atelier, **1re Jelly Ascend vers le jour 13**, piste de la semaine, Défis, Carnet |
| **J29-J84** *(v2.0)* | Une Jelly Ascend tous les 10 à 11 jours (halo, ciel, titres), Monuments 9-10, lignes de l'Atelier finies (vers le jour 106 pour la référence, 54 pour l'assidu) puis « Pour le plaisir » et ses 24 objets de Déco perso (au-delà du jour 140 pour la référence, jour 79 pour l'assidu), maîtrises d'espèces, jalons de taille géante (1e15 à 1e24), Carnet 2 500 et 5 000, cosmétiques de la semaine |

### 7.2 Écran de retour

S'ouvre au chargement si le joueur a été absent au moins 10 min. Contenu : « Pendant ton absence (5 h 12) : **Mochi Mew a grossi de +X** » (le vrai nom du Meilleur Ami n° 1, sinon du plus gros), le squishy qui gonfle à l'écran (0,8 s, `Quint Out`), « +Y pièces dans ton Pot », et « Presque prêt pour le Grand Splorch ! » si le plus gros a atteint 90 % de l'objectif (la croissance hors ligne s'arrête là, §4.19). Un bouton « Super ! » (360 × 112 px TV, texte de 40 px TV, glyphe ✕), sélectionné d'office à la manette ; ✕ ou ○ le ferment. Aucune publicité, aucune offre.

### 7.3 Nourrir Plop (jours au total)

Une fois par jour UTC, maintenir 2 s devant le bol. Chaque jour : boost personnel ×2 (croissance et pièces) pendant 5 min. Les paliers comptent le total de jours, jamais une série.

| Jours au total | Récompense (en plus du boost personnel ×2 de 5 min de chaque jour) |
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

Récompenses : facile = 3 min de revenu ; moyen = 6 min de revenu ; difficile = 10 min de revenu. **Les 3 terminés** : une « Goutte chanceuse » (une naissance de Qualité + 1, chances de mutation × 2). Les objectifs ne donnent plus de boost ×2 (version 1.3) : ajoutés aux boosts du bol, ils mettaient le joueur de référence en ×2 pendant 95 % de son temps de jeu (§4.25). Avec les prix des dalles × 3,5^R, les pièces gardent leur valeur, et la récompense aussi.

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

### 7.5 Rendez-vous de la semaine *(v2.0 : modifié)*

- **Jelly Moon** chaque samedi (4 séances) et le dimanche (§4.23). Déclarée comme *Experience Event* dans le Creator Hub.
- **Une nouvelle espèce par semaine** (§7.6), qui fait ses débuts pendant la Jelly Moon.
- **Classements de la semaine** (§6.9).
- **Squish Parties d'administrateur** (inchangé) : un sujet `MessagingService` « LiveOps » permet à une liste blanche d'administrateurs de lancer sur tous les serveurs 5 Golden Wobblers en 5 min + ×2 gratuit pour tous pendant 10 min, sans aucune vente.
- **Piste de la semaine** *(v2.0, au lancement)* : gratuite, **12 paliers**, toutes les récompenses visibles d'avance. *(v2.0 révisé, critique M15 : un enfant qui ne joue que le week-end n'atteignait jamais le cosmétique, 18 points au plus sur 24)* **2 points** par objectif du jour terminé (6 par jour au plus), **5 points** par Défi de Splorch ; 1 palier = 2 points ; 24 points pour les 12 paliers. Repères (calcul, règles ci-dessus) : joueur du **week-end** (2 jours) : 12 + 15 = **27** points possibles, 3 de marge ; joueur de référence (7 jours) : 42 + 15 = 57, la piste finit en 3 à 4 séances (ce n'est que du cosmétique et 34 Confettis). Les 2 points d'un objectif arrivent **dès qu'il est terminé** (avant même de le réclamer). Paliers **réclamés tout seuls**, dans l'ordre, chacun après sa récompense (un palier de Confettis attend tant que les Confettis sont coupés, puis il arrive tout seul). Récompenses : palier 1 : 2 Confettis · 2 : 2 · 3 : 3 · 4 : Goutte chanceuse · 5 : 3 · 6 : 4 · 7 : 4 · 8 : Goutte chanceuse · 9 : 5 · 10 : 5 · 11 : 6 · 12 : **cosmétique de la semaine** (34 Confettis par semaine ; Goutte chanceuse = une naissance de Qualité + 1, chances de mutation × 2, §7.4).
- **Une seule définition de la semaine** pour la piste, les Défis et les classements : `weekIndex = floor((heureUnix − 345 600) / 604 800)`, comptée depuis le lundi 5 janvier 1970 à 00:00 UTC ; jamais un numéro de semaine de l'année (les semaines ISO ont des années de 53 semaines). Remise à zéro chaque lundi à 00:00 UTC, **à la session suivante** : une session en cours le lundi à 00:00 garde sa période, ses Défis et ses points jusqu'à sa fin (comme les objectifs du jour à minuit). **La première période d'un compte** va de sa première connexion au 2e lundi qui suit (8 à 14 jours), pour que le premier cosmétique soit toujours atteignable. Les points d'un Défi vont à la période où il a été tiré ; un Défi en cours reste jusqu'à la fin de la session. Specs `QuestRules` : changements de semaine au dimanche 23:59:59 / lundi 00:00:00 UTC, aux fins d'année (2026-12-28, 2027-01-04) ; chaque période permet d'atteindre 24 points.
- **Aucune peur de rater** : les cosmétiques de la semaine tournent sur une liste de 8 et **reviennent au plus tard 8 semaines après** (écrit sur la piste : « Revient dans 6 semaines »). Un cosmétique de la semaine déjà gagné n'est pas redonné : le palier 12 ne donne alors rien de plus (les Confettis et les Gouttes des autres paliers restent). **Aucune version payante, jamais** (décision par défaut n° 5) : il n'y a qu'**une seule piste** dans le jeu ; la « saison de 28 jours » et sa piste premium du §17.2 v1.3 sont supprimées.
- **Défis de Splorch** *(v2.0, au lancement)* : 3 par semaine, tirés parmi 12, chacun **faisable dans la situation du joueur** (module `QuestRules`, règle d'or du §7.4) *(v2.0 révisé, critique M15)* **dans son temps de jeu médian des 7 derniers jours** (au plus 2 h, au moins 30 min ; un nouveau compte prend 30 min), jamais dans 2 h fixes ; « Nourris Plop 3 jours » n'est tiré que si le joueur a joué au moins 3 jours la semaine précédente ; « Gagne 20 Confettis » n'est plus tiré quand l'Atelier est complet (et ne compte jamais les Confettis de la piste) ; les Défis de situation ne sont tirés que si une estimation du serveur tient dans ce temps de jeu (2 Grands Splorch et nouveau Record R : seulement sur une boucle record, jamais pendant une remontée ; Jelly Ascend : prête, ou à la fin de la boucle en cours ; 2 MEGA SQUISH : calendrier des MEGA) ; et **jamais dépendant des autres joueurs** (un serveur peut n'avoir que 1 à 3 joueurs) : Fais 2 Grands Splorch (si faisable) · Gagne 20 Confettis · Achète 10 niveaux d'amélioration · Atteins un nouveau Record R (si faisable) · Fais une Jelly Ascend (si prête dans les 2 h) · Fais un combo ×3 · Fais naître 2 Rares ou mieux · Remplis 5 nouveaux tampons · Participe à 2 MEGA SQUISH · Nourris Plop 3 jours · Attrape 5 créatures en fuite · Fais 30 PERFECT.
- **Carnet du Ranch** *(v2.0, au lancement)* : compteur à vie des niveaux achetés (×10 et Max compris), récompenses gratuites et cosmétiques : **50** titre « Bâtisseur », **100** selle « Brique », **250** drapeau « Chantier », **500** titre « Architecte », **1 000** traînée « Petits marteaux », **2 500** emote « Coup de maillet » (v2.0 révisé : un habillage « Atelier » aurait fait 15 habillages au lieu de 14), **5 000** titre « Grand Architecte », **10 000** couronne de chantier pour le Meilleur Ami. Repères pour le joueur de référence (calcul d'après les achats par boucle de la simulation, ≈ 65 à 77 achats par boucle) : 50 et 100 au jour 1, 500 vers le jour 5, 1 000 vers le jour 9, 2 500 vers le jour 22, 5 000 vers le jour 45, 10 000 après 3 mois.
- *(Critique m9)* **Ce que compte un Petit Splorch** : Défi « Fais 2 Grands Splorch » **non** (seulement les Grands Splorch qui battent le Record R) ; jauge du serveur **5 points** (25 pour un Grand Splorch) ; place en fête **0** ; « Plus généreux » (§6.9) **0** ; statistique à part `stats.petitSplorches` (jamais `stats.splorches`) ; objectif du jour « Fais un Grand Splorch » **non** (et il n'est jamais proposé pendant une remontée, où chaque boucle finit par un Petit Splorch).
- **Place en fête** : chaque Grand Splorch (+1), Jelly Ascend (+1), MEGA réussi (+3, une fois par MEGA) et Wobble Party (+2) du serveur ajoutent des points (un Petit Splorch : 0) [`Events.Fete.Points`] ; la place monte de niveau (guirlandes à 5, ballons à 15, arches à 30, petits feux d'artifice à 50, statue dorée de Big Plop à 80). Décor seulement ; repart de 0 avec un nouveau serveur.
- **Jumelles et cœurs** : depuis la rue, les jumelles (invite □ « Regarder ») montrent le ranch d'un voisin ; un **cœur** par ranch et par jour (20 par jour au plus), **notification privée** au propriétaire, **aucun compteur public**, joueurs bloqués exclus (§13).
- **Mode photo « Cheese ! »** (pensé pour le bouton Create de la PS5) : filtres, caméra bornée au ranch et à la place, personnage figé **et toujours visible des autres** *(v2.0 révisé, critique m18 : jamais masqué, pas de présence invisible sur un serveur d'enfants)* ; robot : 1 000 entrées et sorties rendent toujours la caméra d'origine. Pendant le mode photo, les petits textes flottants du monde (« z » des Plopettes et des squishies endormis, « Nouveau : … » du Chantier) se cachent avec le HUD et reviennent à la sortie (prix et « PRÊT ! » restent : ils font partie du ranch) ; une carte qui arrive pendant le mode photo attend dans la file et se montre après la sortie, jamais un panneau par-dessus la photo *(lot I, règle B5-50)*.

### 7.6 Cadence des mises à jour *(v2.0 : réécrit)*

**Tout le contenu de ce document est construit et testé avant la sortie** (décision par défaut n° 6). Il n'y a **pas de calendrier daté** : chaque système est disponible au lancement et s'ouvre par la progression (Record R, Ascension, jours de Plop, Squishydex), jamais par une date. **Seuls deux contenus arrivent ensuite, par des mises à jour** :
- **chaque semaine, une nouvelle espèce**, ajoutée comme ligne de données avec son horodatage `release` (champ déjà prévu), publiée **en avance** dans une version et activée toute seule le samedi à 16:00 UTC ; elle rejoint une nouvelle famille de 4 ou reste sans famille (§4.17) ;
- **chaque saison, un costume** (kit du §11.5 : décor, éclairage, musique, vedette gagnée, objets ajoutés à « Pour le plaisir »).

*(v2.0 révisé, critique B1 : toutes les bandes, pas seulement les 28 premiers jours)* **Le joueur de 2 h par jour a toujours un but proche, réglé dans le design** (Gants à 40 niveaux, Tapis Étoilé ouvert dès r = 6, Souvenir de gelée dégressif, facteur de prix par Ascension en table, 12 décorations gardées au plus, Atelier et « Pour le plaisir » jusqu'au jour 79), sans attendre une mise à jour : mesuré à **10,6 / 15,5 / 16,1 / 16,5 / 14,8 %** de son temps de jeu « à plus de 3 min d'un achat ou d'un but » aux jours 2-7, 8-14, 15-28, 29-56 et 57-84, puis **13,9 et 11,7 %** aux jours 85-112 et 113-140 (limites 15 % puis 30 %), plus long trou p90 ≤ 14,9 min dans chaque bande (§4.24.1). Avant la critique, la v2.0 n'était mesurée que jusqu'au jour 28 et montait à 36,7 puis 62,5 % aux jours 85-140.

---

## 8. Monétisation

### 8.1 Principes non négociables *(v2.0 : modifié)*

1. **Aucun hasard payant, aucune chance achetable** : ni œuf, ni coffre, ni roue, ni chance payante, ni avantage payant pour attraper ou booper. **Les pièces, qu'on peut obtenir plus vite avec des Robux (×2 Pièces, Squish Party), n'achètent jamais une probabilité ni un tirage** : la Cuve (qualité, vitesse, buses) progresse seulement avec R (§4.9). C'est la définition des « paid random items » de Roblox (`production/monetization/paid-random-items.md` : les « probability modifier items » achetés en Robux ou avec une monnaie achetable en Robux), appliquée à la lettre.
2. **Jamais payer pour sauter un minuteur** : ni la Cuve, ni la Gelée lente (si elle vient un jour, §17.2), ni l'Atelier, ni une Ascension (v2.0).
3. **Pas de faux compte à rebours**, pas de « plus que 2 en stock », pas de prix caché derrière une monnaie intermédiaire. Chaque bouton montre le prix en Robux et exactement ce qu'on reçoit.
4. **Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé** : la Boutique Robux est cachée, aucun écran ne propose d'acheter.
5. **Aucune publicité vidéo récompensée** au lancement (et aucun code pour en afficher).
6. **Boutique cachée tant que les identifiants sont à 0** : un article dont l'identifiant vaut `0` dans `Shared/Config/Monetization` est désactivé et invisible ; si tous valent 0, l'onglet Boutique Robux n'apparaît pas (leçon de Comet Conga).
7. **Prix lus à l'exécution** (`MarketplaceService:GetProductInfoAsync`) pour la tarification gérée par Roblox (Managed Pricing) ; le prix en configuration n'est qu'un affichage de repli.
8. **`ProcessReceipt` idempotent** (service repris de Comet Conga) : `PurchaseId` mémorisé (100 derniers), `PurchaseGranted` renvoyé seulement après une sauvegarde réussie.
9. **PolicyService** : au chargement, `PolicyService:GetPolicyInfoForPlayerAsync` (sous `pcall`, 3 essais). Le jeu ne vend ni objet aléatoire payant ni monnaie : `ArePaidRandomItemsRestricted` ne cache donc aucun article (il est seulement compté par l'analytique) ; l'appel sert surtout à `IsContentSharingAllowed` (clips, §9.5). Si l'appel échoue, on applique la règle la plus stricte (clips coupés). Les probabilités des naissances gratuites sont **toujours** affichées. Au questionnaire de maturité, la réponse sur les objets aléatoires payants est « non » (§18).
10. Le pass ×2 Pièces ne touche **que les pièces**, jamais la taille ni les chances. Dit honnêtement : ×2 Pièces et la Squish Party accélèrent le ranch, donc indirectement la taille et le rythme des Grands Splorch. *(v2.0 révisé, critique M2 : le texte doit être vrai)* Un gros acheteur atteint chaque jalon **environ 15 à 22 % plus tôt** ; sans Ascension, c'est **+2 Record R** au jour 28 ; avec l'Ascension, cette avance en temps devient une avance en Record R qui grandit : **+4 Record R et +1 Ascension au jour 28, +9,5 Record R au jour 84 ; avec le ×2 Pièces et le Grand Ranch seuls, 8 à 15 % plus tôt, +2 au jour 28 et +7,5 au jour 84** (§4.24.1 ; décision du propriétaire, question 8 du §20.2). C'est pourquoi la taille n'est pas un classement mondial, et les autres classements se départagent au premier arrivé (§6.9).
11. **Aucune monnaie vendue au lancement** (§8.3) : des Robux ne peuvent jamais disparaître dans un Grand Splorch. L'aperçu annonce quand même en rouge les pièces gagnées en jeu qui vont repartir de zéro, avec « Dépenser d'abord » (§4.15).
12. *(v2.0)* **Rien de la v2.0 n'est vendu** : ni Confettis, ni ligne de l'Atelier, ni Ascension, ni Plopette, ni Monument, ni niveau d'amélioration, ni « achat à distance » (l'écran Améliorations est gratuit pour tous), ni piste payante (décision par défaut n° 5 : jamais). Tout se gagne en jouant. Aucun nouvel article en Robux.

### 8.2 Passes (« Pour toujours », gardés après chaque Grand Splorch)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `AutoPot` | Pot automatique | 149 R$ | Le Pot s'encaisse tout seul toutes les 5 s, où qu'on soit. Confort seulement |
| `DoubleCoins` | ×2 Pièces | 249 R$ | ×2 sur le revenu (facteur P, §4.3), donc sur tout ce qui se compte en revenu ou en secondes de revenu (Pot, pressions, combos, ventes, récompenses), **une seule fois** : une récompense de « N s de revenu » n'est jamais multipliée une deuxième fois par P (§4.1). Jamais la taille. Avec les prix des dalles × 3,5^R (§4.6), les pièces gardent leur valeur à toutes les boucles, et ce pass aussi |
| `BigRanch` | Grand Ranch | 199 R$ | +6 places d'enclos (24 au plus) |
| `SaddlesTrails` | Pack Selles et Traînées | 99 R$ | 6 selles et 6 traînées. Purement décoratif : aucun avantage de vitesse ni de capture |

Chaque carte de pass porte l'étiquette « Pour toujours » / « Forever ».

### 8.3 Produits (achats ponctuels, résultat connu)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `SquishParty` | Squish Party | 99 R$ | ×2 pièces **et** croissance pour **tout le serveur** pendant 10 min. Ne se cumule pas. **Vendue seulement si elle peut commencer aussitôt** : le bouton est caché pendant une Squish Party. Si deux achats se croisent (on ne peut pas refuser un reçu payé), la seconde fête **prolonge** la première de 10 min : aucune fête n'attend dans une file en mémoire du serveur. **3 achats au plus par joueur et par jour** (« 2 sur 3 aujourd'hui »). Si l'acheteur quitte le serveur avant la fin de sa fête, la fête continue pour les autres et il garde un **boost personnel ×2 de 10 min** pour sa prochaine session. Si le serveur ferme (mise à jour, panne) avant la fin, chaque acheteur dont les minutes n'ont pas été jouées les retrouve en boost personnel ×2 (10 min au plus par achat), écrit dans son profil avant la fermeture (`BindToClose`) : une fête payée n'est jamais perdue. Bannière « **SQUISH PARTY ×2 !** », qui ne parle pas d'achat ; « offerte par Noah » seulement si l'acheteur l'a choisi (case « Montrer mon nom », décochée par défaut) |
| `OutfitSweater` | Pull douillet | 49 R$ | Une tenue, à mettre sur le squishy de son choix |
| `OutfitCrown` | Couronne de gelée | 79 R$ | Idem |
| `OutfitWinter` | Écharpe d'hiver | 49 R$ | Idem (costume de saison du lancement) |

- **Paquets de pièces : retirés du lancement** (décision de la version 1.3, ancienne question 1). Trois raisons : (1) les pièces repartent de zéro à chaque Grand Splorch, et un enfant qui achète un paquet puis appuie sur GRAND SPLORCH perd ses Robux en quelques secondes, même avec des protections ; (2) le montant affiché était calculé avant l'achat, mais l'attribution le recalculait : un reçu rejoué par Roblox après une panne, juste après un Grand Splorch, donnait le minimum (20 000 pièces pour 149 R$ au lieu de « ≈ 1,2 M »), contraire au n° 3 du §8.1 ; (3) moins d'articles, moins de cas à tester (barre « zéro bug »). Les clés `CoinsSmall` et `CoinsBig` restent dans la configuration avec l'identifiant 0, donc invisibles. Ils ne reviendront (janvier au plus tôt, sur décision du propriétaire) qu'avec un porte-monnaie « Pièces de côté » qui survit au Grand Splorch et se dépense en premier, et un devis du serveur écrit dans le profil avant l'invite d'achat (champ réservé `packs`, §12.6, §17.2).
- **Tenues** : on voit le squishy porter la tenue (aperçu 3D qui tourne) **avant** d'acheter. Une tenue achetée appartient au compte : on la met sur un squishy, on la change gratuitement ; une tenue va sur un squishy à la fois. Si ce squishy est vendu ou relâché, la tenue revient dans la garde-robe. Une fusion garde la tenue.

### 8.4 Ce qui est volontairement exclu *(v2.0 : modifié)*

Œufs, coffres, roues ; chance payante, y compris par une monnaie achetable (amélioration de la Cuve en pièces) ; monnaie vendue (paquets de pièces) au lancement ; avantage pour booper ou attraper ; immunité payante ; « passer le minuteur » ; plafond hors ligne payant (le pass « Offline Plus » du concept est supprimé : le Lit douillet s'achète en pièces) ; récompense d'invitation ; publicité vidéo récompensée ; nom de l'acheteur affiché par défaut.

**Jamais** *(v2.0, décision par défaut n° 5)* : piste premium (la « saison de 28 jours » de la v1.3 est remplacée par la piste de la semaine, gratuite et unique, §7.5).

### 8.5 Attentes honnêtes *(v2.0 : modifié)*

Taux DevEx standard 0,0038 $/R$ et 70 % net sur les ventes. Conversion visée 1,5 à 3 %. Revenus portés par ×2 Pièces, Grand Ranch et Squish Party, plus les Creator Rewards (sessions de 10 min et plus, nouveaux joueurs amenés sur Roblox). *(v2.0 révisé, critique M2)* **Avance mesurée d'un gros acheteur** (×2 Pièces, Grand Ranch, Squish Party la moitié de chaque séance) : environ **15 à 22 % plus tôt** sur chaque jalon ; avec l'Ascension, l'écart en Record R grandit (**+4 Record R et +1 Ascension au jour 28, +9,5 Record R au jour 84 ; avec le ×2 Pièces et le Grand Ranch seuls, 8 à 15 % plus tôt, +2 au jour 28 et +7,5 au jour 84**) ; la porte le suit **en temps** (`spenderLeadTimeShare` ≤ 25 %, bloquante) ; voir §4.24.1 et la question 8 du §20.2. Le modèle juste rapporte moins par joueur que les concurrents prédateurs : c'est un choix assumé, car l'algorithme récompense la fidélité et les dépenses des joueurs baissent (bookings −12 % au 3e trimestre 2026, Étude §4.4).

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
| Au repos | Rebond de période 1,2 s (hauteur 0,18 D), écrasement au contact (1 + a ; 1 − a ; 1 + a) pendant 0,1 s puis tremblement amorti à la fréquence de l'espèce ; clignement toutes les 3-6 s ; flâne dans l'enclos (pas de 2 studs toutes les 4-8 s, **jamais à plus de 2 studs de sa place** : le serveur mesure les portées depuis la place, §4.7) ; regarde le joueur le plus proche |
| Prêt à presser | Corps gonflé de 4 %, petit reflet qui passe toutes les 2 s ; anneau PERFECT qui se resserre vers lui à chaque cycle quand il est la cible |
| En recharge | Anneau qui se remplit au sol en 8 s ; corps normal |
| Porté | Sur la tête du joueur, bat des pieds (oscillation ±10° à 3 Hz) |
| Jumeau du squishy porté ou ciblé | Petit cœur rose qui pulse au-dessus de lui (échelle 1 ↔ 1,25 à 1,5 Hz), vu par le propriétaire seulement |
| Dans le Bassin | Flotte (Y ± 0,3 à 0,5 Hz), petites bulles 1 par seconde |
| Curieux à la clôture (Rush) | Pattes posées sur la clôture, se dandine (±8° à 1,5 Hz), nez qui remue |
| Meilleur Ami en ville | Suit le joueur à 4 studs derrière, par petits bonds |
| Monture | Rebondit à chaque pas (écrasement 8 % au rythme de la course) |
| Dans la Boîte à dodo | Icône endormie dans le panneau (pas de modèle dans le monde) |

### 9.4 Moments de jeu *(v2.0 : modifié)*

« D » = diamètre du corps. Durées en secondes. « MR » = Mouvement réduit.

| Moment | Tweens et mouvement | Particules / 3D | Caméra / écran | Texte | Son | Vibration |
|---|---|---|---|---|---|---|
| **Presser** | Profil `press` : (1 ; 1 ; 1) → (1,35 ; 0,60 ; 1,35) en 0,06 (`Quad Out`) → (0,85 ; 1,25 ; 0,85) en 0,12 (`Quad Out`) → (1 ; 1 ; 1) en 0,35 (`Elastic Out`) | 8 gouttes couleur du corps ; 6 à 10 pièces (client) jaillissent en arc 0,5 puis volent vers le compteur en 0,4 (`Quad In`) | Pop du compteur | « +1,2K » à **taille fixe à l'écran** (40 px TV, §10.2) : échelle 0 → 1,2 → 1 en 0,2 (`Back Out`), monte de 3 studs en 0,8 | `Press`, hauteur au hasard entre 0,92 et 1,08 (un son un peu différent à chaque fois) | — (seul le PERFECT vibre : une vibration à chaque pression surchargeait la manette) |
| **PERFECT** | Profil `perfect` : (1,45 ; 0,50 ; 1,45) puis comme `press` | Anneau `Neon` blanc 0 → 1,6 D en 0,25 ; 14 étincelles | — | Tampon « PERFECT ! » doré : 0 → 1,3 → 1 en 0,25 (`Back Out`) ; « ×3 » sous le tampon pour la série | `Perfect`, hauteur 1,0595^série (un demi-ton de plus par marche) | `perfect` |
| Série de 5 | — | 20 étincelles dorées en gerbe | Légère lueur dorée aux bords de l'écran 0,4 (pas en MR) | « PERFECT ×5 ! » | `StreakMax` | `perfect` |
| **Dalle achetée** | Pendant l'attente de 0,6 s : anneau blanc qui se remplit autour de la dalle (il se vide en 0,15 si le joueur sort). Puis l'objet sort du sol : échelle Y 0 → 1,15 → 1 en 0,45 (`Back Out`), puis (1,08 ; 0,92) → 1 en 0,3 | 12 vermicelles colorés | — | « Tapis à Goûter Niv. 2 » flottant | `TileBuild` | — |
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
| **ATCHOUM** | Profil `sneeze` : (1,5 ; 0,6 ; 1,5) en 0,08, puis saut par-dessus la clôture (arc 0,7, sommet 8 studs) | Nuage pastel brillant (20 particules blanches et roses, **jamais vertes**) | — | « ACHOO! » / « ATCHOUM ! » (`Elastic Out`) | `Sneeze` | Boopeur : `boopDone` ; propriétaire : aucune (une vibration de perte serait un signal négatif ; il vibre quand son squishy revient, `squishyBack`) |
| **Poursuite** | Bonds en continu (profil `hop`) | Anneau à la couleur du propriétaire + contour `Highlight` ; traînée de 6 gouttes ; anneau de temps au-dessus (25 s qui se vident) | Flèche au bord de l'écran vers la fuite la plus proche à 120 studs (joueurs Rush) | — | `MusicRush` (pendant le Rush) | — |
| **Bondir** | — | `Trail` sur la `HumanoidRootPart` pendant 0,35 ; 6 bouffées de poussière | Focale 70 → 76 en 0,1, retour en 0,4 (`Quad InOut`) (pas en MR) | L'indicateur R2 (bas droite, §10.2) montre un balayage de recharge (4 s), puis pop 1,15 quand il est prêt | `Leap` | — |
| **Attraper** (fuite, Wild, Golden) | La créature se roule en boule, saute dans les bras du joueur (parabole 0,3), puis disparaît en rétrécissant (0,2) et réapparaît dans l'enclos | 14 particules | — | « +1 Mochi Mew » ; « NOUVEAU ! » si nouvelle entrée | `Catch` (Golden : `CatchGolden`) | `catch` |
| Attraper le squishy d'un autre (Rush) | **L'attrapeur ne touche jamais l'original.** Pichenette pleine d'étincelles sur le squishy (0,15) ; il éternue une petite **bulle-bébé** brillante (Ø 1,5 stud, le bébé roulé en boule dedans) qui flotte jusqu'aux bras de l'attrapeur (parabole 0,4), éclate en paillettes, et le bébé saute vers son ranch. L'original fait coucou et rentre au ranch en rebondissant | 14 paillettes ; traînée de 6 cœurs par seconde derrière l'original | Propriétaire : flèche au bord de l'écran vers son squishy qui rentre | Attrapeur : « Bébé Wibble ! » ; propriétaire, le retour d'abord : « Wibble est rentré ! +1 Fame +X pièces · il a laissé un bébé à Noah » (« au Ranch 7 » si le nom est caché), avec le bouton « Pas ce joueur » | `BabyGet` ; propriétaire : `Return` | Attrapeur : `catch` ; propriétaire, quand son squishy est rentré : `squishyBack` |
| **Capture Héros** | Le squishy grossit sous les yeux (0,3) : +1 h de croissance du ranch, une fois par squishy et par jour (sinon, pas de grossissement, le reste est pareil) | 30 particules | — | Tampon « HÉROS ! » / « HERO! » doré (0,4, `Back Out`) | `HeroCatch` | `catch` (force 0,5) |
| Personne n'attrape | Le squishy rentre en bondissant ; au portail, il grossit avec une étincelle (+30 min de croissance, une fois par squishy et par jour) | 8 étincelles | — | Propriétaire : « Wibble est rentré plus gros ! » | `Return` | `squishyBack` |
| **Monter** | La monture apparaît (0 → 1 en 0,25, `Back Out`), le joueur saute dessus (arc 0,3) ; profil `mount` : (1,25 ; 0,75 ; 1,25) en 0,12 | — | — | — | `MountUp` | — |
| Atterrissage en monture | (1,3 ; 0,7 ; 1,3) en 0,1 | 8 bouffées ; Grande selle : anneau d'éclaboussure ; Selle géante : onde 0 → 12 studs en 0,4 | — | — | `RideLand` | — |
| **Grand Splorch** (7,5 s) | 0,0 : le squishy brille (pulsation blanche 0,3) et s'élève de 8 studs (0,6, `Quad Out`). 0,6 : il vole vers la place sur une courbe (1,4, `Sine InOut`). 2,0 : à 40 studs au-dessus du MEGA pad, il gonfle de ×1 à ×2,5 en 1,2 (`Quad In`), en tremblant (±6 % de 4 à 8 Hz). 3,2 : **éclatement au ralenti** (0,8 ; pas en MR) en un grand nuage de confettis. 5,2 : il sort du nuage tout petit (0 → 1 en 0,4, `Back Out`) et fait coucou (0,6). *(v2.0 : le texte dit « Plop est là ! ×2 ! », sans « pour toujours ».)* 5,8 : il rejoint le héros en 3 grands bonds magiques (1,5 au total, traînée d'étoiles), quelle que soit la distance, atterrit à ses pieds à 7,3, puis rentre à sa place | 3,2 : 60 gouttes de gelée qui retombent, onde 0 → 80 studs en 0,8, `Bloom` +0,6 pendant 0,4. 4,0 : pluie de cadeaux : pour **chaque** joueur, 6 à 10 pièces et une capsule de bébé tombent près de lui (1,2) | Héros : caméra qui suit le vol puis le retour du petit squishy (pas en MR : une flèche le montre) ; secousse 0,3, amplitude 0,35 à l'éclatement ; flash blanc 0,1 (pas en MR). Autres : secousse atténuée par la distance. Visible de toute la carte | 5,2 : titre « GRAND SPLORCH III » qui s'écrit en 0,6 (`MaxVisibleGraphemes`) ; 7,3 : « Plop est là ! ×2 ! » (vrai nom) ; bannière serveur ; puce APPLAUDIR chez les autres (8 s) | 2,0 `SplorchCharge` ; 3,2 `SplorchPop` ; 4,0 `GiftRain` ; 5,2 `Reward` | Héros : `splorch` ; autres : `catch` à la capsule (spectacle complet seulement, au plus une fois toutes les 3 min ; la version courte n'a ni capsule, ni secousse, ni vibration, ni APPLAUDIR, §4.15) |
| **MEGA SQUISH : alerte** | Ombre ronde qui grandit de 0 à 24 studs en 15 s et pulse | — | — | Bannière « MEGA SQUISH ! » + compte à rebours | `MegaWarn` | — |
| MEGA : atterrissage | Chute de 120 studs en 0,6 (`Quad In`) ; écrasement (1,4 ; 0,55 ; 1,4) en 0,15 puis `Elastic Out` 0,8 | 3 anneaux 0 → 60 studs décalés de 0,15 ; 40 bouffées de poussière | Secousse 0,3, amplitude `0,4 × (1 − d / 120)` si d < 120 studs | — | `MegaLand` | `megaLand` atténuée |
| MEGA : pression | Creux local (1,04 ; 0,96 ; 1,04) en 0,08 à chaque pression locale ; le serveur envoie un battement toutes les 0,25 s, écrasement proportionnel au nombre de pressions | « +1 » / « +3 » flottants | Barre de serveur qui se remplit (`Back Out`, 0,3) ; à 90 %, le géant tremble (±4 % à 6 Hz) et écarquille les yeux | — | `MegaPress`, hauteur de 0,9 à 1,3 selon la progression | `pressTick` sur un PERFECT seulement |
| MEGA : ÉCLATE | Gonfle 1 → 1,3 en 0,3 (`Quad In`) puis éclate | 80 gouttes ; pluie de capsules de bébés (une par bébé, près de chaque participant) ; 60 confettis | Flash blanc 0,12 (pas en MR) ; coup de focale | « MEGA SPLORCH ! » | `MegaPop` puis `GiftRain` | `megaPop` |
| MEGA : échec | Le géant soupire (Y 1 → 0,9 → 1 en 1) et s'envole doucement (2) | — | — | « Presque ! » | `MegaSigh` | — |
| **Jauge pleine** | La jarre déborde ; Big Plop danse 8 s (sauts, 2 tours sur lui-même, dandinements) ; un grand ballon Plop de 20 studs monte au-dessus de la place pendant la danse | 40 confettis | Ciel légèrement doré pendant 5 min ; pastille « WOBBLE PARTY ×2 5:00 » | Bannière | `GaugeFull` | — |
| **Golden Wobbler** | Geyser doré de la fontaine, la créature sort en arc | 30 étincelles ; traînée dorée de 8 particules par seconde | — | Bannière à la capture | `GoldenAppear` ; à la capture `CatchGolden` | `catch` |
| **Sirène du BOOP RUSH** | Les squishies curieux trottent vers la clôture (un bond de 0,3 par pas) | — | Ciel rose (`Tint` (255, 200, 225)) en 2 s ; pastille rose « BOOP RUSH 1:30 ». Nouveau avant l'étape 9 : teinte à 30 %, pastille seulement | « BOOP RUSH ! » (pas pour un nouveau avant l'étape 9) | `RushSiren` puis `MusicRush` pendant 90 s (−12 dB pour un nouveau avant l'étape 9) | `rushSiren` (pas pour un nouveau avant l'étape 9) |
| **Jelly Moon** début / fin | Transition du ciel 4 s (nuit, grosse lune, teinte violet-sarcelle) ; les Lunaires ont 2 gouttes de gelée brillantes qui flottent autour d'eux (orbite de 3 s) | Lucioles lunaires (12 sur l'écran) | — | Bannière « JELLY MOON ! » | `MoonStart` puis `MusicMoon` | — |
| **Nourrir Plop** (le Meilleur Ami n° 1) | Anneau de maintien 2 s autour du bol ; puis, sans maintien, le Meilleur Ami ouvre et ferme la bouche 4 fois (3 s), gonfle à 1,05 et revient | 6 cœurs | — | Tampon « Jour 42 ! » | `FeedPlop` ; palier : `Reward` | — |
| **Nouvelle entrée de Squishydex** | Carte qui glisse de la droite en 0,3 (`Back Out`), reflet `UIGradient` 0,6 | — | — | « NOUVEAU ! Gillygum · Néon » | `DexNew` | — |
| **Objectif terminé** | Barre remplie en 0,3, carte qui pulse à 1,1, coche qui se dessine | La récompense vole vers son compteur | — | — | `ObjectiveDone` | — |
| **Fanfare de record du serveur** | — | 3 feux d'artifice au-dessus de la place | — | Bannière dorée « Premier à 1 MILLIARD ! » | `Fanfare` | — |
| **Portail refusé** (intrus) | Le portail de gelée se bombe (Z 1 → 1,3 → 1 en 0,3), le joueur est repoussé sur un petit arc | — | — | « C'est le ranch de Mira ! » | `Boing` | — |
| **Achat Robux** | Pluie de 30 pièces (1) | Squish Party : bannière « SQUISH PARTY ×2 ! » + confettis pour tout le serveur | — | « Merci ! » | `Reward` | — |
| **Emote** | Icône 0 → 1,2 → 1 en 0,25 (`Back Out`), tenue 2,5, fondu 0,2 | — | — | — | `Emote` | — |
| **Un achat** *(v2.0)* | **Cascade** : chaque pièce part de 8 studs sous sa place, monte en 0,30 s (`Back Out`) jusqu'à 1,15 puis 1 en 0,15 s ; 0,04 s entre deux pièces ; 1,2 s au plus ; les squishies du ranch se tournent vers l'objet et sourient | 12 vermicelles | — | « +1 niv. » 40 px | `TileBuild`, +3 % de hauteur par pièce (au plus +36 %), +2 % par achat de suite dans les 3 s (au plus +24 %) | `tileBuy` |
| **Achat groupé** ×10 / Max *(v2.0)* | Un seul retour : les cascades se suivent, 1,2 s au total | 24 vermicelles | — | « +7 niveaux · −1,2 M » (texte de la réponse du serveur) | `TileBuild` une fois, puis `Reward` | `tileBuy` |
| **Palier** *(v2.0)* (nouveau palier nommé, 10e et 18e place, décoration dorée) | 2,5 s : anneau `Neon` de 0 à 40 studs en 0,6 s ; **la ola** des squishies, colonne par colonne | 30 confettis | — | Bannière personnelle « PALIER ! Bonbon arc-en-ciel » (48 px) | `LevelUp` | `tierUp` |
| Achats faits depuis l'écran Améliorations *(v2.0)* | Les cascades attendent la **fermeture du panneau** et se jouent alors, groupées ; 10 constructions ou 10 s au plus, ensuite l'état final est posé sans animation ; un objet hors du détail complet ou derrière la caméra n'est pas animé | — | — | — | — | — |
| **Chantier de Big Plop** *(v2.0)* | Big Plop casqué, 3 coups de maillet, la pièce se construit en cascade (§4.15) | — | — | « Nouveau : Phare de gelée » 3 s | `ChantierTap` (repli `Click`) | `chantier` à chaque coup |
| **Socle → décoration** *(v2.0)* | Le socle rétrécit (0,2 s), la décoration sort en cascade | 8 vermicelles | — | — | `DecoPlace` (repli `TileBuild`) | — |
| **Petit Splorch** *(v2.0)* | 2,5 s depuis `PetitSplorchAt` (coupure dure à 4 s) : le squishy saute, rétrécit avec un « pouf » ; les voisins en détail complet jouent la même animation | Pluie de confettis sur le ranch (30) | — | « Plop est là ! ×2 » (petit, 32 px) | `SplorchPop` (hauteur 1,2) | `holdDone` |
| **Jelly Ascend** *(v2.0)* (10 s, coupure à 12 s) | Le faisceau de l'Observatoire se pose sur le ranch, l'élément de ciel se construit pièce par pièce, le Meilleur Ami n° 1 monte dans le faisceau (taille copiée au début), éclat de lumière, redescend avec le halo ; profil changé d'un bloc à 4,0 s | 60 étincelles, anneau `Neon` | Flash blanc 0,12 (pas en MR) ; la caméra suit le Meilleur Ami (pas en MR) | « JELLY ASCEND » + étoile dessinée avec A ; « ×3 à chaque boucle ! » | `AscendCharge` puis `AscendBurst` (replis `SplorchCharge`, `SplorchPop`) | `ascend` |
| **Pluie d'étoiles** *(v2.0)* (Jelly Ascend d'un autre) | Étoiles dorées qui tombent sur la place 3 s | 20 étincelles | — | Petite bannière | `GiftRain` | — |

### 9.5 Captures et clips

- Réglage « Clips » (activé par défaut), et seulement si `PolicyService` renvoie `IsContentSharingAllowed = true` pour ce joueur.
- Capture vidéo automatique (`CaptureService:StartVideoCaptureAsync`, côté client) pour : naissance Légendaire ou mieux, mutation Arc-en-ciel, Glitch ou Flop, COMBO ×5, son propre Grand Splorch (case « Filmer mon Grand Splorch » sur l'écran d'aperçu, cochée par défaut). Arrêt après 8 s (`StopVideoCapture` ; Roblox arrête de toute façon à 30 s).
- À la fin, une petite carte **non bloquante** (§10.3) : « Garder ton clip ? » avec Enregistrer (`PromptSaveCapturesToGallery`), Partager (`PromptShareCapture`) et Fermer. Si le joueur n'y répond pas, elle se range dans la pastille « ! » de la puce Menu jusqu'à la fin de la session. Le jeu **ne partage jamais tout seul**.
- **Console** : chaque appel à `CaptureService` est protégé (`pcall`). Si la capture n'est pas disponible sur l'appareil, la case « Filmer » et la carte « Garder ton clip ? » n'apparaissent pas ; si `StartVideoCaptureAsync` ne renvoie pas un succès, aucune carte pour cette capture ; jamais de message d'erreur ; le bouton Create de la PS5 (ou Partager de la Xbox) reste la capture du système.

### 9.6 Sons *(v2.0 : modifié)*

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
| *(v2.0)* `ChantierTap`, `DecoGold`, `DecoPlace`, `TrickPop`, `WeatherStart`, `FeteLevel`, `Cheese`, `HeartGive`, `AscendCharge`, `AscendBurst`, `ConfettiGain`, `HelperHop` | Coup de maillet ; décoration dorée ; décoration qui ressort du socle ; tour appris ; début d'une météo ; niveau de la place en fête ; mode photo ; cœur donné ; Jelly Ascend (montée, éclat) ; Confettis gagnés ; saut d'une Plopette | Dépôts officiels seulement ; repli sur une clé qui existe (`Click`, `TileBuild`, `TileBuild`, `Pop`, `Whoosh`, `LevelUp`, `Click`, `Pop`, `SplorchCharge`, `SplorchPop`, `Coin`, `Boing`) ; test de contrat : chaque clé utilisée existe dans `Config/Sounds` |

---

## 10. Interface télé, commandes et console

### 10.1 Principes : la disposition « 10 pieds » est la seule disposition *(v2.0 : modifié)*

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
| Cadre de sélection (focus) | 6 px blanc + 2 px sombre, **dessiné à l'intérieur de l'élément** (v2.0) | grossissement 1,05 seulement pour les gros boutons isolés ; **jamais** pour les lignes, les cartes, les boutons du rail, ni dans un cadre qui découpe (v2.0) |

  Pourquoi 28 : 28 px TV font 2,6 % de la hauteur de l'écran. Sur une télé de 55 pouces vue à 3 m, c'est environ 20 minutes d'arc, lisible par un enfant de 8 ans. Comet Conga s'arrêtait à 27 px réels en 1080p ; on monte d'un cran et on écrit le texte courant en 32.
- **Contraste** : texte clair sur un fond foncé translucide (opacité ≥ 0,6) ou avec un contour `UIStroke` de 3 px. Jamais de texte posé directement sur le décor.
- **Textes du monde** (prix des dalles, consigne de l'accueil, « +N », taille au-dessus d'un squishy, invites) : la règle des 28 px TV vaut aussi pour eux. Ils sont détaillés au §10.2 (*Textes du monde*) : `BillboardGui` en pixels fixes, jamais de texte à lire posé au sol ou dimensionné en studs.
- **Peu d'éléments, grands** : en jeu calme, 8 éléments au plus sont visibles (pièces, puce Menu, puce « Prochain achat », pastille d'événement, jauge, suivi d'objectif, indicateurs, carte de la cible) *(v2.0 révisé, critique M7 : la pastille Fame et amis n'est plus au HUD calme ; elle s'affiche 3 s quand la Fame ou le nombre d'amis change et reste dans le panneau Ranch)*. Le reste n'apparaît que quand il sert (divulgation progressive) et disparaît ensuite.
- **Aucun chevauchement, aucun texte coupé** : chaque élément du HUD a une place fixe dans une colonne (gauche, centre, droite, bas) ancrée à un bord de la zone sûre. Deux éléments ne se recouvrent jamais, à aucune des 3 résolutions visées (1920 × 1080, 3840 × 2160, 1280 × 720) ni sur un écran plus large ou plus haut que 16:9 (les colonnes s'écartent, elles ne se rapprochent pas). *(v2.0 : politique de texte unique, remplace « chaque texte a `TextScaled` »)* `TextSize` **fixe** partout, **jamais `TextScaled`** (un texte en `TextScaled` n'est pas agrandi par la taille de texte choisie par le joueur, `GuiService.PreferredTextSize`) ; les noms, nombres et libellés des cartes, lignes et boutons ont un `UITextSizeConstraint.MaxTextSize` égal à leur taille dessinée (28 à 48 px TV) ; les phrases (bandeaux, cartes) sont dans des boîtes prévues pour la taille **Largest**. **Aucun rétrécissement automatique en jeu** : un texte qui ne tient pas, en anglais ou en français, à la taille Medium ou Largest, fait échouer `TextFit_all.spec` et on raccourcit le libellé (§12.10, couche d). La règle vaut pour **tout le client**, pas seulement pour l'écran Améliorations.
  *(v2.0 révisé, critique B3 : on ne dépend plus d'un comportement du moteur jamais mesuré.)* (1) **`UI/Text` mesure lui-même le facteur réel** au démarrage et à chaque changement de `GuiService.PreferredTextSize` : une étiquette témoin cachée (texte connu, `TextSize` 100) donne par ses `TextBounds` le facteur f qu'applique vraiment le moteur. Si `UITextSizeConstraint` ne borne pas un texte non `TextScaled` (f > 1 sur une étiquette contrainte), `UI/Text` **compense** : les noms, nombres et libellés reçoivent `TextSize = taille dessinée ÷ f`, les phrases `TextSize = taille dessinée` (agrandies par le moteur) ; sinon il ne fait rien. `Text_policy.spec` simule les deux comportements du moteur (contrainte respectée ou ignorée) : chaque libellé garde sa taille dessinée, chaque phrase grandit. (2) **Tâche n° 1 du paquet P0** : un panneau **TextProbe** dans Diagnostics (administrateurs) pose 6 étiquettes témoins (28, 36 et 48 px, avec et sans contrainte, avec et sans `TextScaled`) et affiche leurs `TextBounds` aux 4 valeurs de `PreferredTextSize` ; le propriétaire le photographie **sur sa PS5** (la version de test y est déjà) ; les chiffres vont dans `TextMetrics`. Studio n'est pas utilisé (le studio construit sans Studio, et Studio ne reproduit pas la PS5). (3) **Tant que la photo n'est pas là**, `TextFit_all` prend le **pire cas** : facteur **1,5** pour les phrases (bandeaux, cartes, messages) ; les libellés sont vérifiés à leur taille dessinée, que la compensation garantit dans les deux comportements.
- **Le focus n'est jamais perdu ni piégé** : règles au §10.6.
- Style *(v2.0 : feuille de style unique, `UI/Theme`)* : coins (`UICorner`) 16 px ; contour (`UIStroke`) 3 px bleu nuit (30, 25, 60), un 2e contour venant d'un cadre parent ; ombre (`UIShadow`) de 6 px vers le bas, douce, 50 % d'opacité, **seulement sur les panneaux et les cartes** ; bouton principal en dégradé (255, 170, 210) → (235, 110, 170) ; secondaire (150, 235, 200) → (80, 200, 160) ; impossible (180, 180, 195) → (140, 140, 160) + icône et mot de la raison ; fond de panneau bleu nuit (30, 25, 60) à 85 % vers (60, 45, 110) ; dégradés radiaux pour les révélations et le titre du Grand Splorch ; polices `FredokaOne` (texte) et `LuckiestGuy` (tampons), **fichiers rangés dans le dépôt** (test de la table `cmap`). Si `UIShadow` ou le dégradé radial manquent sur un appareil, **repli automatique sur l'aplat** (sous `pcall`, compté dans Diagnostics, jamais une erreur) ; ce repli à plat est aussi le style des captures de référence hors ligne. *(Critique m21)* `UIShadow` (en ligne depuis le 23/06/2026) et le dégradé radial (quelques jours seulement, fin octobre 2026, docs/08 [92][93]) sont ajoutés au harnais (`MockInstance`, `ApiAudit`, `EngineProps`) avec un test du repli ; l'**ombre de repli** est un `Frame` décalé de 6 px vers le bas, à 50 % (1 objet par panneau ou carte). *(Critique m22)* Les fichiers de police FredokaOne et LuckiestGuy (licence OFL, Google Fonts) sont rangés dans le dépôt au paquet P0 ; d'ici là, `Contract_glyphs.spec` est marquée « en attente » avec sa date. Test statique : aucune couleur ni rayon écrit en dur dans `UI/*` hors de `UI/Theme`. Tout texte passe par `Text.set(label, clé, args)`.
- **Affichage progressif** : pendant l'accueil, seuls les éléments déjà présentés sont visibles (§3).

### 10.2 HUD (px TV, zone sûre x 96-1824, y 54-1026) *(v2.0 : modifié)*

| Élément | Position (ancrage) | Taille | Contenu |
|---|---|---|---|
| Pastille Pièces | Haut gauche (96, 54) | 440 × 112 | Pièce dessinée de 80, montant en 56 px, revenu « +1,2K/s » en 32 px |
| Pastille Fame et amis *(v2.0 révisé, critique M7)* | Haut gauche (96, 178) | 320 × 56 | Étoile + Fame ; cœur + nombre d'amis présents (32 px). **Visible 3 s seulement** quand la Fame ou le nombre d'amis change (et dans le panneau Ranch) ; hors du HUD calme |
| **Puce Menu** | Haut gauche (96, 246) | 260 × 80 | Glyphe △ (48) + « MENU » (40 px, en capitales comme le code v1.3, docs/04 §26.2 ; critique m23 ; **ce libellé ne change jamais**, critique B2) ; « M » au clavier (affiché selon la disposition, `GetStringForKeyCode`) ; un clic l'ouvre aussi. Porte les pastilles « ! » (action possible, carte en attente) et « ♥ 3 » (paires de jumeaux ; *lot B2, D18 : cœur dessiné devant le nombre, « ♥ » est absent des polices, règle 18*) |
| Menu ouvert (le rail) *(v2.0 : modifié)* | À la place de la puce, (96, 246) vers le bas | **Jusqu'à 8 boutons de 340 × 80, écart 16 (y 246 à 998)** | Grand Splorch **ou Jelly Ascend** (un seul bouton, au nom de la renaissance prête, seulement quand elle l'est), Ranch, **Améliorations**, Squishydex, Objectifs, Classements, Boutique (après 10 min de jeu et si un identifiant existe), Réglages. Icône de 48 + libellé de 36 px. *(Lot B2, D14 : le bouton « ! » d'une carte en attente reste, juste sous la renaissance, soit 9 boutons au plus ; avec 9, le rail monte, son haut jamais au-dessus de y 178 ; s'ils ne tiennent toujours pas (barre de Roblox), l'écart passe à 12, puis à ce qui tient, jamais sous 4 : boutons de 80 et zone sûre toujours tenus ; la renaissance prête peut aussi être « Petit Splorch » pendant une remontée)* |
| **Puce « Prochain achat »** *(v2.0 : nouveau)* | Gauche (96, 342) | 440 × 96 | Ligne 1 : icône 48 + nom court de la famille (12 caractères au plus : Tapis, Gants, Déco, Enclos, École, Lit, Monument) + « Niv. 8 », 32 px. Ligne 2 : barre et « 12,3 K / 20 K », 28 px. Payable : « Prêt ! » et **une seule** pulsation (jamais de clignotement). Fonction pure `UpgradeAdvisor.next(état)`, évaluée au plus 2 fois par seconde ; *(v2.0 révisé, critique M7)* **sa cible est recalculée après tout achat et après tout Grand Splorch, Petit Splorch, Jelly Ascend et changement de plafond de la boucle** (spec `UpgradeAdvisor` › « après `Prestige.apply`, `next` ne désigne jamais un niveau déjà possédé ni inexistant ») ; entre deux, elle ne change pas. **Cachée** seulement pendant l'accueil jusqu'à la leçon du menu, quand le menu ou un panneau est ouvert, et quand le suivi du Grand Splorch affiche « Prêt » ; elle reste visible quand la carte de la cible est affichée (la pastille Fame ne prend plus sa place) : le HUD calme montre au plus 8 éléments |
| Pastille d'événement | Haut centre (y = 54) | 560 × 72 | Prochain événement « BOOP RUSH 3:12 » (36 px) ; événement en cours en couleur (Rush rose, MEGA jaune, Lune violet, Wobble Party orange) |
| Barre du MEGA | Haut centre (y = 138) | 720 × 48 | Progression du serveur, objectif, temps restant (28 px) |
| Jauge du serveur | Haut centre (y = 138, hors MEGA) | 400 × 28 + icône Plop de 40 | Remplissage ; grise avec « Big Plop se repose 12:34 » (28 px) pendant la sieste (§4.23) |
| **Emplacement de message** | Haut centre (y = 198) | Bannière 1000 × 112 ; message 760 × 88 | **Un seul à la fois.** Les bannières de serveur (§6.6 ; titre 48 px, ligne 32 px) passent d'abord ; les messages (module `UI/Toast` repris, 32 px) attendent, 3 au plus en file, 2,5 s chacun, les messages identiques fusionnés (« +X pièces ×3 ») |
| Suivi d'objectif | Haut droite (−96, 54) | 440 × 104 | Anneau de 72 + « Grand Splorch » (32 px) + « 12K / 15K » (28 px) ; dans la file : « 2e de la file · environ 0:40 » (§2.4 ; *lot B2, D19 : le mot « environ » / « about » remplace « ≈ », absent des polices, règle 18*) ; *(v2.0 révisé, critique M5)* pendant une remontée, 2 lignes : « Retour au record » (32 px) et « 4 / 15 » (28 px), mesurées à 276 px pour 324 utiles |
| Indicateurs d'état | Haut droite (−96, 170), en ligne | 64 × 64 chacun, écart 12, 3 au plus ; minutes en 28 px dessous (jusqu'à y = 266 ; *lot B2, D20 : le nombre et une marque des minutes dessinée, « ′ » étant absent des polices*) | Bouclier débutant, boost ×2, mon mode (Rush ou Cozy) ; *(v2.0)* **Souvenir de gelée** (goutte + son facteur du moment « ×3 », « ×2 », « ×1,5 » ou « ×1,25 ») pendant une remontée, à la place du bouclier débutant (jamais les deux : le bouclier dure 15 min, la 1re Ascension arrive après des jours). Affichage seul |
| Carte non bloquante | Droite (−96, 330) | 520 × 220 au plus | Titre 40 px, texte 32 px, glyphe △ (48) + « Voir ». 8 s, puis rangée dans la pastille « ! » (§10.3) |
| **Puce d'action spéciale** | Bas centre, bas à −162 (y 822-918) | 520 × 96 | *(v2.0 révisé)* « JELLY ASCEND ! » (261 px à 40 px pour 428 utiles) quand l'Ascension est prête et qu'aucun Grand Splorch n'est prêt (critique B2, m24) ; « PETIT SPLORCH ! » (276 px) pendant une remontée, avec le glyphe △ comme « GRAND SPLORCH ! » ; *(lot B2, D16 : en jeu, ✕ est le saut et les enfants le tiennent, un maintien de ✕ sur une puce jamais sélectionnée partirait par accident)* △ ou croix ↓ ouvre le menu sur l'entrée « Petit Splorch » ; le premier Petit Splorch de chaque remontée passe par l'aperçu (✕) ; les suivants se font en **maintenant ✕ 1,5 s sur cette entrée du menu** (glyphe ✕ affiché, un appui court ouvre toujours l'aperçu), sans aperçu (critique M16) ; à la souris, un clic sur la puce ouvre le menu et un clic maintenu 1,5 s sur la puce fait le Petit Splorch ; « GRAND SPLORCH ! » avec le glyphe △ quand l'objectif est atteint (△ ou croix ↓ ouvre le menu sur l'entrée Grand Splorch : 2 appuis jusqu'à l'aperçu ; à la souris, un clic sur la puce) ; « APPLAUDIR » avec le glyphe croix → et un anneau de 8 s, à la place de la précédente (§6.7 ; jamais pendant une poursuite, un maintien ou une fenêtre ouverte). Pendant l'accueil, cette place sert à la consigne du moment (glyphe 64 + mot 40 px) quand l'objet visé n'est pas à l'écran |
| Carte de la cible | Bas centre, bas à −54 (y 930-1026) | 680 × 96 | Squishy visé : nom (36 px), rareté (couleur + forme), taille, revenu, étoiles, mutation (28 px). Affichage seul |
| Indicateur Bondir | Bas droite (−96, −54) | 96 × 96 | Glyphe R2 (64) et balayage de recharge. Visible seulement pendant la recharge, pendant la leçon de l'accueil, et en ville pendant un Rush ou un Golden |
| Flèches de bord d'écran | Bord de la zone sûre | 72 × 72 | **2 au plus**, pour tous les joueurs (Rush ou Cozy), vers une cible hors champ à 120 studs au plus : une vers le Golden Wobbler s'il est attrapable par moi ; une vers la créature attrapable la plus proche, dans cet ordre : mon squishy boopé, ma créature personnelle (fuite, Wild Wobbler personnel, démonstration), un Wild Wobbler partagé, une fuite du Rush (joueurs Rush seulement). Sur une télé à 3 m, un joueur Cozy ne voyait pas les Wild Wobblers hors champ |

Vérification (aucun recouvrement) *(v2.0 révisé, critique m13 : les rectangles réels de chaque élément, pas des colonnes)* :

| Élément | x | y |
|---|---|---|
| Pastille Pièces | 96-536 | 54-166 |
| Pastille Fame et amis (3 s) | 96-416 | 178-234 |
| Puce Menu | 96-356 | 246-326 |
| Rail ouvert (à la place de la puce) | 96-436 | 246-998 |
| Puce « Prochain achat » (cachée quand le rail est ouvert) | 96-536 | 342-438 |
| Pastille d'événement | 680-1240 | 54-126 |
| Barre du MEGA ou jauge du serveur | 600-1320 (MEGA) ou 740-1180 (jauge et icône) | 138-186 |
| Emplacement de message (bannière) | 460-1460 | 198-310 |
| Suivi d'objectif | 1384-1824 | 54-158 |
| Indicateurs d'état (3 au plus) | 1608-1824 | 170-266 |
| Carte non bloquante | 1304-1824 | 330-550 |
| Puce d'action spéciale | 700-1220 | 822-918 |
| Carte de la cible | 620-1300 | 930-1026 |
| Indicateur Bondir | 1728-1824 | 930-1026 |

La puce « Prochain achat » (x ≤ 536, y 342-438) est hors du rectangle de la bannière (x ≥ 460 seulement jusqu'à y = 310) ; le milieu de l'écran (x de 560 à 1280, y de 330 à 822) reste libre pour le personnage et ses squishies. `tests/harness/Layout` vérifie ces rectangles aux 3 résolutions, en anglais et en français.

**Invites dans le monde** (dessinées par `UI/Prompt` au-dessus de la cible, en px TV mis à l'échelle comme le reste) : « □ Presser » (glyphe 64 + mot 40 px, plaque de 300 × 88) et, après la leçon de fusion, une deuxième ligne plus petite « ○ Prendre » (glyphe 48 + mot 32 px). Au clavier : « E Presser », « Q Prendre ». Jamais deux invites sur la même touche, jamais plus de 2 invites à la fois. L'anneau des maintiens (boop, bol) entoure le glyphe □ et suit l'heure de fin envoyée par le serveur. Une invite qui sortirait de la zone sûre est ramenée à son bord.

**Textes du monde** (règle commune, `UI/WorldText`) : en vue à la troisième personne sur une télé à 3 m, un texte posé au sol ou dimensionné en studs devient illisible au-delà d'environ 15 studs, et un `SurfaceGui` vu de biais encore plus tôt. Tout texte du monde que le joueur **doit lire** est donc un `BillboardGui` dimensionné en **pixels fixes** (`Offset`) multipliés par l'échelle d'interface (`UIScale` du §10.1) : texte **≥ 32 px TV** (40 pour les « +N »), glyphes ≥ 48 px TV, `LightInfluence = 0`, fond foncé translucide ou contour, distance maximale fixée par usage. Cas : prix et niveau d'une dalle sur une étiquette au-dessus d'elle, visible à 20 studs ou moins (le disque garde seulement l'icône) ; glyphe et mot de la leçon d'accueil au-dessus de l'objet (jamais un anneau au sol) ; « +N » à taille fixe à l'écran ; taille au-dessus d'un squishy ciblé ; probabilités de la Cuve en barres sur la Cuve, chiffres seulement dans le Guide. Les `SurfaceGui` restent pour le décor et pour ce qui est aussi ailleurs (tableaux des classements, doublés par le panneau Classements ; compte à rebours de l'Autel, doublé par la pastille d'événement). Test (couche d, §12.10) : taille projetée de chaque texte du monde ≥ 28 px TV à 20 studs, aux 3 résolutions.

### 10.3 Écrans *(v2.0 : modifié)*

| Écran | Accès | Contenu | Remarques |
|---|---|---|---|
| Chargement | Automatique | Plop qui rebondit, points animés | `ReplicatedFirst`, code seul. Délai : si le profil n'est pas chargé en 60 s, l'écran d'échec s'affiche (jamais un chargement infini) |
| Échec de chargement | Automatique | « Ton ranch se réveille… » + Réessayer | Réessayer attend la fin des essais du DataService (attribut `ProfileLoading`), sélectionné d'office à la manette (leçon de Comet Conga) |
| Écran de retour | Au chargement | §7.2 | « Super ! » sélectionné d'office |
| Carte du choix Rush / Cozy | Au calme, dès 15:00 de jeu (§4.21.1) ; Réglages | Deux gros boutons, animation de 6 s en boucle, « Plop ne s'enfuit jamais » | Garde de 0,6 s ; sans réponse en 20 s : Cozy |
| Carte « Wibble revient toujours ! » | Après le premier boop subi, au retour du squishy | « +X pièces +1 Fame », boutons « Continuer », « Mode Cozy », « Pas ce joueur » | Non bloquante |
| **Ranch** *(v2.0 : modifié)* | Menu | Onglets : *Enclos* (grille des squishies, tri, verrou, Meilleur Ami, monture ; les jumeaux portent un cœur ; boutons **Tout fusionner** et **Ranger**), *Dodo* (Boîte à dodo, échanger), *Lettres* (Boîte aux lettres), *Fusionner* (choisir A puis B, ou Tout fusionner), *Vendre / Relâcher* (sélection multiple ; ○ vide d'abord la sélection, puis recule d'un niveau ; maintien 0,6 s, confirmation en 2 étapes pour Épique+ ou mutation Doré+, §4.13), ***Mon style*** (habillage, Déco perso sur un plan vu du dessus, selle, traînée, titre, drapeau, tenues, palette, coussins ; *(lot B3, tel que fait)* une liste des sortes à gauche et une grille de 5 cases à droite ; Déco perso : les 12 emplacements sur le plan, ✕ ouvre le choix des objets de la bonne taille, « Aucun » d'abord ; un objet verrouillé montre d'où il vient ; le halo se règle dans *Réglages*) ; l'onglet *Dalles* de la v1.3 est **retiré** : l'écran Améliorations le remplace | Grille virtualisée ; la sélection suit l'index au défilement (leçon de Comet) |
| **Améliorations** *(v2.0 : nouveau)* | Menu (sous Ranch), U au clavier, kiosque de Big Plop, « Dépenser d'abord » | 4 onglets (Conseillé, Ranch, Plopettes, Atelier), cartes et lignes, ×1 / ×10 / Max, bandeau de détail (§10.7) | Construit une fois au chargement ; 20 règles et leurs tests (§10.8) |
| **Squishydex** | Menu | Onglets : *Espèces* (une rangée par famille de 4, plus la rangée des Secrets ; ✕ ouvre la **fiche de l'espèce** : ses 9 mutations en 3 × 3, ses badges d'étoiles, sa taille record), *Familles* (bonus), *Guide* (toutes les probabilités et règles), *(v2.0, lot B3)* *Records* (le Livre des records du §17.1, lu dans le profil, en lecture seule ; ↑ / ↓ font défiler de 70 %) ; *(v2.0)* sur la fiche d'une espèce, la colonne de la **maîtrise** (« Maîtrises : n / m », 3 cases : 5★, Page dorée, Trophée Cristal, cochées quand elles sont faites, dorées quand les 3 le sont, §4.17) ; *(lot B3)* rouvert depuis le menu, le Squishydex montre toujours les *Espèces* | Silhouettes grises pour ce qui manque. La grille 26 × 9 de la version 1.2 demandait 25 appuis sur ↓ à la manette ; avec une fiche par espèce, la dernière rangée est à 6 appuis sur ↓ au lancement, et une espèce ajoutée chaque semaine ne fait qu'ajouter une case. Le stick droit fait défiler d'un écran |
| **Objectifs** | Menu | *Aujourd'hui* (3 objectifs, relance), *(v2.0, lot B3)* *Cette semaine* (les 12 paliers de la piste, ses points et les jours restants, les 3 Défis, le cosmétique de la semaine et les 2 suivants, §7.5), *(v2.0)* *Carnet* (8 paliers et 2 objets de Déco perso, « Améliorations achetées : n / m »), *Plop* (jours au total, paliers), *Accueil* (tant qu'il n'est pas fini) | Paliers de la piste et du Carnet en lecture seule (le serveur les donne, aucun bouton « Réclamer ») ; cochés quand ils sont gagnés (coches dessinées, comme celles de *Plop* et de l'*Accueil*) |
| **Classements** | Menu | 5 onglets (§6.9) : d'abord ma place sur ce serveur et mon record contre la semaine dernière, puis le top 10 mondial | |
| **Boutique** | Menu (après 10 min) | *Passes*, *Fête*, *Tenues* (aperçu 3D) ; prix lus à l'exécution | Cachée si aucun identifiant ; aucune monnaie vendue (§8.3) |
| **Aperçu du Grand Splorch** *(v2.0 révisé)* | Menu → Grand Splorch (entrée sélectionnée d'office quand il est prêt) | 3 tuiles « Tu gagnes » (gabarit tuile 400 × 300 de `UI/UpgradeCard`, critique M17), animation avant/après, perte de pièces en rouge et « Dépenser d'abord » **seulement si une ligne gardée est payable** (sinon la phrase neutre « Tes pièces deviennent le cadeau du Splorch », critique M16), bouton à maintenir 1,5 s (✕) ; **« Détails »** ouvre les deux colonnes, le choix du squishy qui s'envole et la case « Filmer » (critique m24 : une seule décision sur l'écran principal, maintenir) ; *(lot B3)* colonnes de la v2.0 : « Tu gardes : Squishies, Record R, Confettis, Atelier, Plopettes, Monuments, enclos, Cuve » et « Repart de zéro : Pièces, Pot, Tapis, Gants, École, déco non gardée, tailles » (§4.15) ; onglets « Grand Splorch » / « Jelly Ascend » (L1 / R1) quand les deux sont prêts | Messages de refus dans une boîte de 600 × 120 (2 lignes à Largest ; critique m20 : « Attends que Blossompurr rentre ! » mesure 428 px à 32 px) : hors du ranch, « Rentre dans ton ranch » ; un squishy en fuite, « Attends que Wibble rentre ! » (seulement pour entrer dans la file). Une fois dans la file, l'aperçu se ferme et le suivi d'objectif montre la place et l'attente (§2.4). **Petit Splorch** : cet aperçu s'ouvre seulement pour le premier de chaque remontée ; les suivants se font en maintenant ✕ 1,5 s sur l'entrée « Petit Splorch » du menu (à la souris : clic maintenu sur la puce d'action spéciale ; lot B2, D16, §10.2) |
| **Aperçu de la Jelly Ascend** *(v2.0 : nouveau)* | Menu → Jelly Ascend (entrée sélectionnée d'office quand elle est prête ; carte Conseillé « Jelly Ascend », §10.7.4) | 3 tuiles « Tu gagnes », « Tout le reste est gardé » et 6 icônes, ligne calculée « 9 fois plus vite jusqu'à ton record », condition et sa barre, maintien de ✕ 3 s (§4.27) | Même gabarit de tuile que l'aperçu du Grand Splorch (§10.8 règle 11) |
| **Carte « Prêt à monter ? »** *(v2.0 révisé)* | Après le maintien de 3 s | « Plus tard » **à gauche**, « Oui, Ascension ! » **à droite** (360 × 112 chacun, texte 36 px, `MaxTextSize = 36` ; mesuré 224 px pour 268 utiles ; critique m19) | *(Critique M1)* **Focus d'office sur « Oui »** : le maintien volontaire de 3 s protège déjà contre l'erreur, et un focus sur « Plus tard » transformait l'hésitation en refus ; garde de 0,6 s et relâchement de ✕ exigé (`InputGuard`) gardés ; 20 s sans réponse : fermée, rien ne change |
| **Livre des records** *(v2.0 : nouveau)* | Squishydex → onglet *Records* | Lecture seule (§17.1) | ↑ / ↓ font défiler de 70 % |
| **Réglages** | Menu | Mode Rush/Cozy, Cacher mon nom, Recevoir les cadeaux, Clips, Mouvement réduit, Graphismes légers, Musique, Effets sonores, Vibrations, Emote de la croix ← (Bravo, Belly Flop, Couronne et les emotes gagnées), Montrer mon halo (v2.0), Langue (Auto / English / Français) ; propriétaire d'un serveur privé : « BOOP RUSH autorisé » ; administrateurs seulement : **Diagnostics** | Interrupteurs de 120 × 64 px TV ; message « Tes squishies grandissent même quand tu dors » en bas |
| **Diagnostics** | Réglages → Diagnostics (visible et accessible **seulement** aux administrateurs, vérifié par le serveur) | Erreurs et avertissements comptés sur ce serveur et sur ses clients, derniers exemples, état du serveur et du client, totaux du jour (§12.11) | Lecture seule ; fait pour être photographié |

**Panneaux** : 1440 × 860 px TV, centrés (x 240-1680, y 110-970) ; en-tête de 96 (titre 48 px) ; onglets de 72 px de haut (libellés 32 px), atteignables à la croix (↑ depuis le haut du contenu) en plus de L1 / R1 ; grilles de cases de 208 × 232 (6 colonnes, 2 rangées et demie visibles : la demi-rangée montre qu'on peut défiler) ; boutons de 80 à 96 px de haut ; bouton Fermer de 80 × 80 avec le glyphe ○. Un seul panneau ouvert à la fois. Ouvrir un panneau ne met pas le jeu en pause.

**Cartes en jeu** (règle commune, module `UI/Cards`)
- **Cartes non bloquantes** : objectifs à 5:00, « Nouveaux objectifs ! », « Plop a sommeil », nouvelle entrée du Squishydex, « Garder ton clip ? », « Wibble revient toujours ! ». Elles ne prennent **jamais** la sélection de la manette : le stick continue de faire marcher. Elles s'affichent à droite (§10.2) pendant 8 s, puis se rangent dans la pastille « ! » de la puce Menu. Pour agir : △ (ou croix ↓) ouvre le menu sur la carte en attente ; à la souris, un clic sur la carte.
- **Carte bloquante ouverte par le jeu** : seulement la carte du choix Rush / Cozy (l'écran de retour et l'échec de chargement s'ouvrent au chargement). Jamais pendant un Rush, un MEGA, une poursuite ou un portage ; seulement au calme (§4.21.1). **Garde d'entrée de 0,6 s** : boutons grisés, aucun appui accepté, pour qu'un ✕ appuyé pour sauter ne choisisse rien. Délai : 20 s, puis Cozy.
- **Une seule carte à la fois**, dans cet ordre : écran de retour > carte du choix > « Wibble revient toujours ! » > objectifs > Squishydex > clip > « Plop a sommeil ». Les autres attendent leur tour.
- Pendant une carte bloquante, le menu ou un panneau ouvert, les touches du jeu sont déliées (□, ○, R2, L2, L1, R1, croix ↑ → ←) et les invites du monde sont cachées : aucune action ne part derrière une fenêtre.

### 10.4 Commandes *(v2.0 : modifié)*

Noms PlayStation (DualSense) avec la `KeyCode` générique de Roblox entre parenthèses. Sur Xbox, les mêmes `KeyCode` portent les noms Xbox ; le jeu affiche **toujours** l'icône de l'appareil (`UserInputService:GetImageForKeyCode`), jamais une lettre écrite en dur.

| Action | Manette (DualSense — `KeyCode`) | Clavier / souris |
|---|---|---|
| Se déplacer | Stick gauche (`Thumbstick1`) | WASD (ZQSD reconnu tout seul en AZERTY) / flèches |
| Caméra | Stick droit (`Thumbstick2`). **La caméra ne bouge jamais toute seule** (sauf le travelling du Grand Splorch, coupé en Mouvement réduit) | Clic droit + souris |
| Sauter (plus haut sur sa monture) | ✕ (`ButtonA`) | Espace |
| **Action principale** : presser, lancer (en portant, près du Bassin), acheter (sur une dalle), attraper, booper (maintien 2,5 s), nourrir au bol (maintien 2 s) | **□** (`ButtonX`) | E, ou clic gauche sur la cible |
| **Prendre / Poser** (un squishy de son ranch) | **○** (`ButtonB`) | Q |
| **Bondir** (visée automatique et capture à l'atterrissage, §4.12) | **R2** (`ButtonR2`) | Maj gauche |
| **Monter / descendre** | **L2** (`ButtonL2`) | R |
| Changer de cible (dans son ranch, et devant une clôture pour booper ou pet-sitter) | L1 / R1 (`ButtonL1` / `ButtonR1`) | Clic sur un squishy (il reste la cible 4 s) |
| **Menu** | **△** (`ButtonY`) **ou croix ↓** (`DPadDown`) | M, ou clic sur la puce Menu ; raccourcis directs : G Ranch, **U Améliorations** (v2.0), C Squishydex, J Objectifs, L Classements, B Boutique, P Réglages |
| *(v2.0)* Mode d'achat ×1 / ×10 / Max (écran Améliorations) | Bouton de mode (↑ depuis les onglets puis ✕) ; □ en raccourci | E, ou clic sur le bouton |
| *(v2.0)* Acheter ×10 / Max | Maintien de ✕ 0,6 s | Maintien d'Entrée ou du bouton de la souris 0,6 s |
| Emotes : salut, merci, bravo (§6.5) | Croix ↑, →, ← (`DPadUp/Right/Left`) | 1, 2, 3 |
| Applaudir (pendant 8 s) | Croix → (remplace « merci » pendant ces 8 s) | F, ou clic sur la puce |
| Menu Roblox | Options (`ButtonStart`, réservé) | Échap (**jamais lié par le jeu**, leçon de Comet) |
| Pavé tactile / Create | `ButtonSelect`, réservé à Roblox | — |
| Libres volontairement | L3, R3 (un enfant les enfonce sans le vouloir) | — |

- **Aucun appui simultané obligatoire**, aucun clic de stick, aucune combinaison : chaque action tient sur une touche (règle d'accessibilité, §14).
- **Pas de verrouillage de la souris** (`StarterPlayer.EnableMouseLockOption = false`) : Maj sert à Bondir.
- **Touches de Roblox laissées libres au clavier** : Tab ouvre la liste des joueurs de Roblox, il n'est donc jamais lié par le jeu (le menu passe sur M) ; le sac à objets de Roblox est coupé (`StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)`, sous `pcall`, nouveaux essais pendant 10 s) pour que 1, 2 et 3 ne servent qu'aux emotes. Les lettres affichées suivent la disposition du clavier (`GetStringForKeyCode`). Pour le menu, le jeu lie `KeyCode.M` **et** `KeyCode.Semicolon` : sur AZERTY, la touche marquée « M » est `KeyCode.Semicolon` ; la puce Menu affiche celle des deux qui donne « M » sur le clavier du joueur.
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
- **Manette** : croix ou stick gauche déplacent la sélection ; ✕ valide ; ○ recule d'un niveau (depuis le premier niveau, il rend la main au jeu) ; △ ferme tout et revient au jeu ; L1 / R1 changent d'onglet (en boucle) ; L2 / R2 changent de panneau (en boucle : Ranch → **Améliorations** → Squishydex → Objectifs → Classements → Boutique → Réglages) **seulement quand un panneau est ouvert**, sinon L2 = Monter et R2 = Bondir. La sélection fait défiler les listes toute seule ; le stick droit fait aussi défiler. **Règle des 3 touches** : la croix, ✕ et ○ suffisent pour atteindre chaque écran et en revenir (L1, R1, L2, R2 et △ ne sont que des raccourcis). Quand une sélection d'interface existe, ○ veut toujours dire « retour » : en portant un squishy, ○ ferme d'abord le menu (le portage continue : seul un panneau ouvert le termine, §4.10), puis, en jeu, pose le squishy. En sélection multiple (*Vendre / Relâcher*), ○ vide d'abord la sélection.
- **Clavier et souris** : la souris clique ; Retour arrière = retour (comme ○) ; M ouvre et ferme le menu ; G, C, J, L, B et P ouvrent directement leur panneau ; Échap et Tab restent à Roblox. Pas de navigation obligatoire aux flèches : la souris suffit.

### 10.5 Vibrations (DualSense et manettes Xbox) *(v2.0 : modifié)*

`Util/Haptics` (repris de Comet Conga) : `HapticEffect` du type indiqué (une instance réutilisée par type), repli `HapticService:SetMotor` pendant la durée. Les vibrations font partie du design : elles disent « c'est fait » à un joueur qui regarde la télé de loin. **Modération** : jamais au clavier-souris ; **délai minimal de 0,25 s** entre deux vibrations, sauf priorité supérieure (et sauf `rushSiren`, joué une seule fois) ; une pression ordinaire ne vibre jamais (au MEGA, cela faisait 2 vibrations par seconde pendant 60 s) ; atténuation < 0,35 ignorée ; réglage « Vibrations » (activé par défaut). Seuls les moteurs standard sont utilisés : aucun effet propre à la DualSense (gâchettes adaptatives) n'est supposé, car Roblox ne les expose pas. Jamais de vibration sur un déplacement de sélection, un bond ou une marche.

| Événement | Quand | `HapticEffectType` | Repli (moteur, force, durée) | Priorité |
|---|---|---|---|---|
| `pressTick` | Pression **PERFECT** sur le MEGA seulement (une pression normale ne vibre pas) | UIClick | Small, 0,15, 0,03 s | 1 |
| `perfect` | PERFECT dans son ranch (force + 0,03 par marche de série) ; série de 5 | UIClick | Small, 0,3, 0,05 s | 2 |
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
| `squishyBack` | Mon squishy boopé revient (rendu par un autre joueur, ou rentré seul ; la capture Héros joue `catch`) : une vibration douce et positive. Aucune vibration quand il s'enfuit (la version 1.2 avait `booped`, un signal négatif contraire au pilier P2) | GameplayCollision | Small, 0,3, 0,08 s | 2 |
| `rushSiren` | Sirène du BOOP RUSH : **une seule impulsion** de 0,3 s, exemptée du délai minimal ; jamais pour un nouveau avant l'étape 9 de l'accueil | UINotification | Small, 0,4, 0,3 s | 3 |
| `megaLand` | Atterrissage du MEGA à moins de 120 studs, atténué `1 − d/120` | GameplayExplosion | Large, 0,7, 0,25 s | 3 |
| `megaPop` | Le MEGA éclate (participant) | GameplayExplosion | Large, 0,8, 0,3 s | 4 |
| `hatchLegend` | Naissance Légendaire ou mieux ; Flop — **forte impulsion de 300 ms** | GameplayExplosion | Large, 0,8, 0,3 s | 4 |
| `splorch` | Mon Grand Splorch (à l'éclatement) | GameplayExplosion | Large, 1,0, 0,4 s | 5 |
| `tierUp` *(v2.0)* | Nouveau palier nommé (Tapis, Gants, École, Enclos), décoration dorée | UINotification | Large, 0,4, 0,35 s | 2 |
| `chantier` *(v2.0)* | Chaque coup de maillet du Chantier de Big Plop | UIClick | Small, 0,3, 0,05 s | 1 |
| `ascend` *(v2.0)* | Ma Jelly Ascend (à 4,0 s, l'éclat) | GameplayExplosion | Large, 1,0, 0,5 s | 5 |

### 10.6 Console et télé : règles, focus et navigation *(v2.0 : modifié)*

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
6. Double appui : une fermeture moins de 0,35 s après l'ouverture de la même fenêtre est ignorée. *(v2.0)* **Garde de ✕** (`InputGuard`) à l'ouverture de **tout** panneau, pas seulement des cartes bloquantes : ✕ est ignoré tant qu'on ne l'a pas vu relâché et qu'au moins 0,3 s n'est pas passée (0,4 s quand l'élément sous le focus change d'identifiant) ; les achats et les confirmations partent d'un `InputBegan` capté, jamais de `GuiButton.Activated` (§10.7.9).
7. Un objet sélectionnable n'est jamais caché derrière un autre ni hors de la zone sûre ; une liste défile pour garder la sélection visible avec une rangée de marge.
8. Chaque sauvetage de la sélection est compté (`FocusRescued`, §16.3) : en ligne, c'est le signe d'un bug à corriger.

**Modules repris** (copiés depuis Comet Conga, puis adaptés seulement là où ce GDD le dit) : `Client/Util/Platform`, `UI/Glyph`, `Util/Haptics` (table d'événements remplacée par celle du §10.5), `Config/Console`, `UI/Root` (référence 1920 × 1080, zone sûre de 5 % sur tous les écrans, `selectionImage` blanc de 6 px), le modèle de `PanelController` (○ recule, △ ferme, L1/R1, L2/R2, garde contre le double appui, `holdSelection`), et le harnais `tests/harness/Gamepad` + `Layout`. **Nouveaux** : `UI/Prompt` (invites du monde), `UI/FocusGuard`.

**Appareil tactile inattendu** (Téléphone décoché mais réglage oublié, émulateur de Studio) : rien ne casse et aucune erreur n'est écrite ; un message s'affiche (« Raise a Squishy se joue avec une manette ou un clavier ») ; l'analytique compte `TouchDeviceJoined`. Aucune commande tactile n'est ajoutée.

**Navigation écran par écran**

| Écran | Sélection par défaut | ○ | L1 / R1 | L2 / R2 |
|---|---|---|---|---|
| Jeu | aucune (le stick fait marcher) | Prendre / poser | Changer de cible (ranch, clôture) | Monter / Bondir |
| Menu (après △ ou croix ↓) | Grand Splorch s'il est prêt, sinon le bouton à pastille « ! », sinon le dernier utilisé, sinon Ranch | Retour au jeu | — | — |
| Ranch | 1re case de l'onglet ; *Fusionner* : « Choisir A » ; *Mon style* : l'objet équipé de la sorte, sinon la 1re case (v2.0) ; plan de Déco perso : l'emplacement 1 ; choix d'un objet : l'objet posé dans l'emplacement, sinon « Aucun » (lot B3) | → bouton du menu d'origine ; *(lot B3)* choix d'un objet → son emplacement → liste des sortes → menu | Onglets (la sélection suit l'onglet affiché, même depuis un onglet vide : lot B3) | Panneaux |
| Améliorations *(v2.0)* | Onglet Conseillé, carte 1 ; ouvert par « Dépenser d'abord » : 1re ligne gardée et payable de l'onglet Ranch ; ouvert par le kiosque : 1re ligne de l'Atelier | → ce qui l'a ouvert (menu, aperçu du Grand Splorch, jeu) | Onglets | Panneaux |
| Aperçu de la Jelly Ascend *(v2.0)* | Bouton « Maintenir » (glyphe ✕) | → menu | Onglets (si le Grand Splorch est prêt aussi) | — |
| Carte « Prêt à monter ? » *(v2.0)* | « Oui, Ascension ! » (critique M1, §4.27), actif après le relâchement de ✕ et la garde de 0,6 s | = Plus tard (la carte ET l'aperçu se ferment, retour à l'entrée du menu) | — | — |
| Squishydex | 1re espèce ; fiche d'une espèce : 1re mutation (○ revient à la case de l'espèce) ; *Guide* : 1re ligne (↑ / ↓ font défiler de 70 % les listes en lecture seule) ; *Records* (v2.0) : la liste (↓ en bout rebondit, ↑ remonte aux onglets) | → menu | Onglets | Panneaux |
| Objectifs | « Réclamer » disponible, sinon 1re carte ; *Cette semaine* et *Carnet* (v2.0) : 1er palier | → menu | Onglets | Panneaux |
| Classements | Onglet en cours | → menu | Onglets | Panneaux |
| Boutique | 1er « Acheter » de l'onglet | → menu | Onglets | Panneaux |
| Réglages | 1er interrupteur | → menu | — | Panneaux |
| Jumelles *(v2.0)* | Le bouton « Donner un cœur » | → jeu | — | — |
| Diagnostics | Onglet « Ce serveur » | → Réglages | Onglets | — |
| Aperçu du Grand Splorch | Bouton « Maintenir » (glyphe ✕) | → menu | — | — |
| Carte du choix Rush / Cozy | « Je reste tranquille » (le choix sûr), après la garde de 0,6 s | = Cozy | — | — |
| Cartes non bloquantes | aucune : elles ne prennent jamais la sélection ; △ ouvre la première en attente | — | — | — |
| Écran de retour | « Super ! » | Ferme | — | — |
| Échec de chargement | Réessayer | — | — | — |

**Réglages de la place** (`default.project.json`, fichier d'un autre rôle) : `Players.MaxPlayers = 16`, **`Workspace.StreamingEnabled = false`** (choix délibéré, §12.9), `VirtualCursorMode = Disabled`, `EnableMouseLockOption = false`, `TextChatService.ChatVersion = TextChatService`, éclairage du §11.3 (v2.0 : `LightingStyle = Soft` et `PrioritizeLightingQuality = false`, réglés dans `default.project.json` depuis le lot I, étape 5). La taille du serveur se règle aussi à 16 dans le Creator Hub, avec les types d'appareils Ordinateur + Console (§18).

### 10.7 L'écran « Améliorations » *(v2.0 : nouveau)*

Comet Conga est sorti avec des bugs d'affichage dans ses écrans d'amélioration (textes coupés, qui débordent, qui se chevauchent, illisibles) : c'est la première plainte du propriétaire. Clash of Clans en a reconnu deux sur son nouvel écran (tri, compteur qui repart de 0, 08/10/2026, docs/08 [60]). Cet écran est donc spécifié au pixel, et chacune des **20 règles** du §10.8 a un test bloquant. Toutes les tailles sont en **px TV** à 1 920 × 1 080, mises à l'échelle par l'`UIScale` du §10.1 (× 2 en 4K, × 0,667 en 1 280 × 720) ; tout est dans la zone sûre de 5 %.

#### 10.7.1 Où on le trouve

- **Menu** (△ ou croix ↓) : une entrée **Améliorations**, juste sous **Ranch**. La sélection d'office du menu reste celle du §10.6 (Grand Splorch ou Jelly Ascend s'il est prêt, sinon le bouton à pastille « ! », sinon le dernier utilisé, sinon Ranch) : « Ranch = △ ✕ » ne change pas. Améliorations = △ ↓ ✕, ou △ ✕ si c'est la dernière entrée utilisée. Raccourci clavier : **U** (*branché à l'étape I sur `PanelController.available`, décision D24 du lot B2*). L2 / R2 (panneau ouvert) : Ranch → **Améliorations** → Squishydex → Objectifs → Classements → Boutique → Réglages.
- **Puce « Prochain achat »** du HUD (§10.2) : elle ne s'ouvre pas d'elle-même (aucune sélection en jeu, §10.6) ; elle dit seulement qu'un achat est prêt.
- **Kiosque de Big Plop** sur la place (invite □ « Atelier ») : ouvre le même écran sur l'onglet Atelier (*lot B4 : `PanelController.open("Upgrades", "workshop")`, prêt depuis le lot B2*).
- **« Dépenser d'abord »** (aperçu du Grand Splorch, §4.15) : ouvre l'écran sur l'onglet Ranch, **sans changer l'ordre des lignes** ; la sélection se pose sur la première ligne **gardée au Grand Splorch** et payable (Enclos, Lit douillet, Monuments), sinon sur la première ligne gardée. ○ ramène à l'aperçu : ○ revient toujours à ce qui a ouvert l'écran (*lot B3 : `PanelController.open("Upgrades", "spendFirst")`, prêt et testé depuis le lot B2*).
- **Les dalles au sol restent** (Tapis, décoration suivante, Enclos, Lit douillet) pour le geste du début (§4.6) ; les familles nouvelles (Tapis Étoilé, Gants, École, Monuments, Atelier) s'achètent seulement depuis l'écran. L'onglet *Dalles* du panneau Ranch est **retiré** : l'écran Améliorations le remplace (le panneau Ranch prend l'onglet *Mon style*, §10.3).
- **Pendant son propre Grand Splorch ou sa Jelly Ascend**, l'écran se ferme tout seul au début du spectacle (la caméra suit le squishy, §9.4) ; il se rouvre à l'état neuf de la boucle. *(Relecture du lot B2)* Rouvert pendant le spectacle, il se ferme encore à l'éclatement, quand la boucle change (r, Record R ou A) : jamais les prix ni les plafonds de l'ancienne boucle avec les niveaux de la nouvelle.

#### 10.7.2 Le rail du menu avec 8 boutons

Avec l'entrée Améliorations, le rail peut avoir 8 boutons. Ils passent à **80 px de haut avec 16 px d'écart** (l'écart minimal du §10.1 entre deux éléments sélectionnables), **icône de 48 et libellé de 36 px**, largeur 340 : 8 × 80 + 7 × 16 = 752 px, de y = 246 à y = 998, sous la limite de 1 026. Ordre : [Grand Splorch ou Jelly Ascend], Ranch, **Améliorations**, Squishydex, Objectifs, Classements, Boutique (après 10 min de jeu et si un identifiant existe), Réglages. Grand Splorch et Jelly Ascend **partagent un seul bouton**, montré seulement quand l'une des deux est prête ; son libellé est le **nom de la renaissance prête** (« Grand Splorch » ou « Jelly Ascend ») ; *(v2.0 révisé, critique m24 : une renaissance à la fois)* si les deux le sont, le bouton est **Grand Splorch** (le faire d'abord ne coûte rien : l'Ascension reste possible juste après, avec un Record R de plus) ; le bouton devient « Jelly Ascend » après lui. Rectangles à jour dans `Layout_hud.spec` et `Console_hud.spec` (§10.2). *(Lot B2, D14, D16, D16b : le bouton « ! » d'une carte en attente reste, juste sous la renaissance, soit **9 boutons au plus** ; avec 9, le rail monte, son haut jamais au-dessus de y = 178 (sous la pastille des pièces), puis l'écart passe à 12 s'ils ne tiennent toujours pas (barre de Roblox à 1 280 × 720) ; boutons de 80 et zone sûre toujours tenus. Pendant une remontée, la renaissance prête s'appelle **« Petit Splorch »** : ✕ ouvre l'aperçu pour le premier de la remontée ; pour les suivants, **maintenir ✕ 1,5 s sur ce bouton** fait le Petit Splorch sans aperçu, un appui court ouvre toujours l'aperçu. Le maintien est sur le bouton du menu, pas sur la puce du HUD : en jeu, ✕ est le saut et les enfants le tiennent. Aucune pastille sur l'entrée Améliorations.)*

#### 10.7.3 Le panneau et ses zones

Panneau de **1 440 × 860** (x 240-1 680, y 110-970), comme les autres (§10.3). Les zones sont calculées **depuis le panneau**, jamais l'inverse : 12 + 88 + 64 + 560 + 120 + 16 = 860 ; largeur utile 1 376 (marges de 32).

| Zone | y dans le panneau | Taille | Contenu |
|---|---|---|---|
| En-tête | 12 → 100 | 1 376 × 88 | Titre « Améliorations » / « Upgrades » 48 px à gauche ; à droite, 3 éléments **à place fixe** : pièces (icône 48 + montant 40 px, largeur réservée 280), Confettis (icône 48 + montant 40 px, largeur 200), **bouton de mode** (glyphe □ dessiné 48 + « ×1 » / « ×10 » / « Max » 40 px, largeur 200, sélectionnable) |
| Onglets | 100 → 164 | 1 376 × 64, libellés 32 px | **Conseillé**, **Ranch**, **Plopettes**, **Atelier** (EN : Suggested, Ranch, Plopettes, Workshop). L1 / R1 changent d'onglet ; ↑ depuis le haut du contenu atteint les onglets, et ↑ encore le bouton de mode (règle des 3 touches) |
| Contenu | 164 → 724 | 1 376 × 560 | Conseillé : 3 cartes. Autres onglets : liste de lignes |
| Bandeau de détail | 724 → 844 | 1 376 × 120 | La phrase complète de ce qui est sélectionné : effet entier, palier actuel et suivant, aperçu ×10 / Max, raison d'un refus, ce que devient la ligne au Grand Splorch. 28 px ; *(v2.0 révisé, critique B3)* **3 lignes à Medium, 2 lignes à Largest** (2 × 28 × 1,5 = 84 px de texte + marges, dans 120) : chaque phrase du bandeau tient en **2 lignes au facteur 1,5** (`TextFit_all`, pire cas). Vide : « — » (jamais un trou) |

**Indicateur « Souvenir de gelée »** (§4.27) *(v2.0 révisé, critique B2 : mesuré avec les vraies avances de FredokaOne)* : quand il est actif, une pastille de **360 × 48** « Souvenir ×3 » / « Memory ×3 » (icône goutte 32 + texte 28 px ; le facteur suit la boucle : ×3, ×2, ×1,5, ×1,25 ; « Souvenir ×1,25 » mesure 159 px pour 288 utiles avec 2 marges de 16) se pose dans l'en-tête, entre le titre et le groupe de droite, à une place fixe : **x 320-680 dans le panneau** (le titre « Améliorations » à 48 px mesure 271 px et **finit à x = 303** ; le groupe de droite, 280 + 200 + 200 et deux écarts de 16, commence à x = 696). « ×3 jusqu'au record » (203 px) ne tenait pas dans l'ancienne pastille de 200. Elle n'est jamais sélectionnable. Sa place est réservée même quand elle est cachée : rien ne bouge.

#### 10.7.4 Onglet Conseillé (ouvert par défaut)

**3 cartes de 432 × 528**, écart 32, posées à y = 16 dans la zone de contenu (3 × 432 + 2 × 32 = 1 360 : 8 px de marge à gauche et à droite, 16 en haut et en bas). La carte entière est l'élément sélectionnable ; le bouton qu'elle montre est un dessin. Pile fixe, en px dans la carte (largeur utile 400) :

| y dans la carte | Hauteur | Élément |
|---|---|---|
| 16 → 96 | 80 | Icône de la famille dessinée en cadres |
| 104 → 152 | 48 | Nom de la famille, 36 px, 1 ligne (« Gants Moelleux », « École des Plopettes ») |
| 152 → 188 | 36 | Palier, 28 px, 1 ligne (« Bonbon arc-en-ciel ») |
| 192 → 232 | 40 | Niveau, 32 px : « Niv. 7 », flèche dessinée, « 8 » |
| 240 → 320 | 80 | Avant → après, 2 lignes de 32 px : « Pressions », puis « ×1,150 », flèche dessinée, « ×1,175 » |
| 328 → 364 | 36 | Raison courte, 28 px, 1 ligne (« Pour gagner plus ») ; la phrase entière va dans le bandeau |
| 372 → 420 | 48 | Prix : icône 48 + montant 40 px, et barre « ce que j'ai / ce qu'il faut » de 400 × 8 dessous si ce n'est pas payable |
| 432 → 512 | 80 | Dessin du bouton « Acheter » (glyphe ✕ dessiné + texte 36 px), ou état (§10.7.6) |
| 512 → 528 | 16 | Marge |

Le cadre de focus est **dessiné à l'intérieur de la carte** (6 px blanc + 2 px sombre), **sans grossissement** : rien ne sort de la carte ni de la zone. ← → passent d'une carte à l'autre ; ↓ ne fait rien (son `Bump`) ; ↑ va aux onglets. S'il manque une carte (tout est au maximum), sa place montre une carte neutre « Tout est au maximum ! Prochain but : Grand Splorch » : jamais un trou. *(v2.0 révisé, critique M1)* **Quand la Jelly Ascend est prête et qu'aucun achat de pièces n'est possible depuis 5 min**, cette carte neutre devient la carte **« Jelly Ascend »** (raison « Prête : une nouvelle couche ! », 322 px à 28 px pour 400) ; ✕ ouvre son aperçu ; et Big Plop fait un geste vers l'Observatoire (une fois par séance). Sans Ascension, la référence passait **29,9 %** puis **52,1 %** de son temps « sans but » (jours 15-28, 29-56) : le jeu doit montrer le chemin.

**Règle du Conseillé** (module pur `UpgradeAdvisor.cards(état)`, déterministe) : candidats = familles **de pièces** ouvertes et pas au maximum. (1) Le Tapis (ou le Tapis Étoilé) s'il est payable ; (2) puis la moins chère payable d'une autre famille ; (3) puis la moins chère payable d'une troisième famille ; s'il en manque, on complète avec les moins chères **non payables** (barre « Il manque … »). Jamais deux cartes de la même famille ; égalités départagées par l'ordre fixe des familles (§10.7.5) ; les Monuments n'apparaissent qu'après le Tapis 12 de la boucle. **Les 3 familles ne sont choisies qu'à l'ouverture de l'écran et à chaque retour sur l'onglet Conseillé.** Après un achat confirmé, **la carte garde sa famille** : elle montre le niveau suivant, ou MAX ; jamais une autre famille sous le curseur. Dans l'onglet Atelier, un badge « Conseillé » (étoile dessinée de 32 px dans le coin de l'icône) se pose à l'ouverture de l'onglet sur au plus 3 lignes (les moins chères achetables, ordre fixe à égalité) et ne bouge plus tant que l'onglet reste ouvert.

#### 10.7.5 Onglets Ranch, Plopettes, Atelier : des lignes

**Lignes de 1 328 × 112**, au pas de 128 (écart 16), avec **24 px de marge à gauche et à droite** dans le cadre de défilement : on voit 4 lignes entières et 48 px de la 5e (ce bout de ligne dit qu'on peut descendre). Hauteur de défilement = fonction pure `somme(hauteurs) + (n − 1) × 16`, où un titre de section compte comme un élément de 112 non sélectionnable. Colonnes **de largeur fixe** :

| Colonne | x dans la ligne | Largeur | Contenu |
|---|---|---|---|
| Icône | 16 | 80 | Icône dessinée en cadres (aucune image téléversée) ; badge de 32 px dans le coin (boucle « repart de zéro » ou infini « gardé ») |
| Texte | 112 | 540 | Ligne 1 : nom de la famille, 36 px. Ligne 2 : **avant → après**, 32 px, en libellé court (« Croissance ×13 », flèche dessinée, « ×14 » ; tableau du §10.7.7) |
| Niveau | 668 | 140 | « 12/20 » en 40 px ; dessous, barre de 140 × 12 vers le prochain palier. En mode ×10 / Max : « 12 », flèche dessinée, « 22 » |
| Prix | 824 | 240 | Icône 40 + montant 40 px (prix du mode choisi) ; dessous, barre de 240 × 8 « ce que j'ai / ce qu'il faut » |
| État | 1 080 | 232 | **Icône 48 + un mot de 28 px**, jamais la couleur seule (§10.7.6) ; le plus long, « Record 400 », mesure 126 px pour 160 utiles |

Une seule chose sélectionnable par ligne : la ligne elle-même (↑ ↓ seulement, aucun sous-bouton). Cadre de focus dessiné à l'intérieur de la ligne, sans grossissement. La sélection reste visible avec une ligne de marge (§10.6). Le bandeau dit en mots ce que devient la ligne au Grand Splorch : « Repart de zéro au Grand Splorch » (Tapis, Tapis Étoilé, décorations non gardées, Gants, École) ou « Gardé pour toujours » (Enclos, Lit, Monuments, Atelier).

**Ordre fixe des lignes** (`Config/Upgrades`, identifiants définitifs, ajout seulement à la fin, **jamais retrié**)
- **Ranch** (6 lignes) : Tapis à Goûter (avec le Tapis Étoilé sur la même ligne), Décorations, Enclos, Lit douillet, Gants Moelleux, Monuments.
- **Plopettes** (7 lignes) : École des Plopettes, puis une ligne en lecture seule par Plopette, dans l'ordre Pip, Pop, Pim, Pom, Puff, Plume (nom, « Presse toutes les 9,0 s », « Fait la sieste » le cas échéant). Avant Pip (Record R 2), l'onglet est visible avec un cadenas « Record 2 ».
- **Atelier** (17 lignes et 1 titre ; v2.0 révisé, critique m12 : 23 lignes demandaient 22 appuis sur ↓) : les 9 lignes du §4.26 dans leur ordre, puis **une** ligne en lecture seule « Monte avec ton record » (ligne 2 : « Cuve 3/8 · palier 4/6 », 263 px pour 540 ; le prochain déblocage et les 3 axes de la Cuve dans le bandeau ; critique B2 : « Cuve Niv. 3/8 · Qualité 4 · Vitesse 9 · Buses 3 » mesurait 565 px pour 540), puis le titre de section « Pour le plaisir » / « Just for fun », puis **7 lignes groupées** : Palettes du spectacle (6 niveaux), Selle « Cotillon », Traînée « Serpentins », Emote « Danse de Big Plop », Titre « Confetti Star », Fanions dorés, **Déco perso de l'Atelier** (24 niveaux : chaque achat donne l'objet suivant d'une liste fixe, montrée dans le bandeau, Annexe B). Dernière ligne à **16 appuis** sur ↓ ; ↓ maintenu répète à 8 par seconde après 0,4 s (2 s jusqu'en bas) et le stick droit fait défiler d'un écran (§10.6).
- *(Critique m11)* **Les lignes en lecture seule sont sélectionnables** (pour lire leur bandeau) ; ✕ y joue le son `Bump`, sans vibration ni retour ; `Console_upgrades_nav.spec` le vérifie.
- **Toutes les lignes existent toujours**, même verrouillées (cadenas et condition) : **aucune ligne n'est ajoutée, retirée ou déplacée pendant que l'écran est ouvert**.
- **L'écran est construit une seule fois par session**, pendant le chargement, puis montré ou caché (`Visible`) : rouvrir ne crée aucune instance. Les interrupteurs (`Features.*`) et les maxima de la boucle (plafond du Tapis Étoilé par r) sont **figés à l'ouverture** ; un changement pendant que l'écran est ouvert s'applique à la prochaine ouverture. Seul le serveur dit ce qui est ouvert (instantané, §10.8 règle 6).

**La ligne Tapis** (Tapis à Goûter et Tapis Étoilé sur une seule ligne) *(v2.0 révisé, critique m14)* : la colonne Niveau montre **toujours le maximum de la famille**, « 12/20 », avec la partie de la barre au-delà du plafond de la boucle **grisée** ; la colonne État montre **un seul état** : à r = 3, l'état boucle « **Boucle 6** » (le Tapis Étoilé s'ouvre à la boucle 6) ; à r ≥ 10, « Prêt », « Il manque » ou « MAX » comme les autres lignes. Le dénominateur ne change jamais d'une boucle à l'autre. Le bandeau dit « Tapis Étoilé : niveau suivant à partir du Grand Splorch 7 dans cette boucle ». Le cadenas « Record … » reste réservé au **Record R** : après une Ascension, un joueur au Record R 15 et à r = 3 voit « Boucle 6 », jamais « Record 6 », qu'il lirait comme déjà gagné. *(Critique m15)* La **dalle Tapis du sol** continue avec le Tapis Étoilé quand il est ouvert dans la boucle (même famille, même ligne) : elle affiche « MAX » seulement au niveau 20 ou au plafond de la boucle.

#### 10.7.6 États d'une ligne ou d'une carte

| État | Quand | Icône dessinée + mot (FR / EN) | Prix | Achat |
|---|---|---|---|---|
| **Payable** | Ouvert, pas au maximum, pièces (ou Confettis) ≥ prix du mode | Coche « Prêt » / « Ready » | Montant en blanc, barre pleine | ✕ (×1) ou maintien (×10, Max) |
| **Il manque** | Ouvert, pas au maximum, pas assez | Sablier « Il manque » / « Need » | Montant en gris clair ; barre partielle ; le bandeau dit « Il manque 1,2 K » | Refus doux : son `Bump`, vibration `refuse`, aucune secousse |
| **Au maximum** | Niveau = maximum de la famille | Étoile « MAX » / « MAX » | Colonne vide sauf « — » | Rien ; bandeau « Tout est acheté : bravo ! » quand toutes les lignes de l'onglet (ses cartes au Conseillé) sont au maximum, sinon ce que devient la ligne au Grand Splorch (« Gardé pour toujours » / « Repart de zéro au Grand Splorch ») : la phrase ne dit jamais « tout » à côté d'une ligne encore à acheter (relecture des écrans du lot B2, B2-72) |
| **Verrouillé** | Record R ou Ascension pas atteints | Cadenas « Record 6 » / « Record 6 » (ou « Ascension 1 » / « Ascend 1 » pour une ligne d'Ascension) | Prix du premier niveau en gris | Rien ; bandeau « S'ouvre au Grand Splorch 6 » / « Opens at Grand Splorch 6 » |
| **Plafond de la boucle** (Tapis Étoilé seulement) | Niveau = plafond par r, inférieur à 20 | Boucle « Boucle 7 » / « Loop 7 » | Prix du niveau suivant en gris | Rien ; bandeau du §10.7.5 |
| **En cours** | Achat envoyé, réponse attendue (3 s au plus) | Sablier animé « En cours » / « Busy » | Inchangé | Appuis ignorés |
| **Réessaie** | Pas de réponse en 3 s | Flèche « Réessaie » / « Retry » | Valeur du dernier instantané | ✕ renvoie l'achat |

*(v2.0 révisé, critique M9)* Le cadenas « Record n » et la boucle « Boucle n » utilisent des **chiffres arabes** (un enfant de 8 ans lit mal VIII et pas du tout LXXXVIII, 8 caractères à 28 px ; l'assidu dépasse le Record R 80 vers le jour 84). Un seul mot par compteur : **Record** (Record R) et **Boucle** (r). Les chiffres romains (`Format.roman`) ne restent que sur le décor : l'arche du ranch, le titre du spectacle, les drapeaux.

#### 10.7.7 Libellés courts « avant → après »

Écrits en français et en anglais, ajoutés à `TextFitPending` avant le code. Les valeurs sont celles du joueur ; « → » est **une flèche dessinée entre deux libellés**, jamais un caractère (§10.8 règle 18).

| Ligne | FR | EN |
|---|---|---|
| Tapis à Goûter / Snack Mat (et Étoilé) | Croissance ×13 → ×14 | Growth ×13 → ×14 |
| Décorations / Decorations | Revenu total +1,2 % (effet réel du prochain niveau, `UpgradeMath.effect`, critique M8) | Total income +1.2% |
| Enclos / Pens | Places : 12 → 13 | Spots: 12 → 13 |
| Lit douillet / Cozy Bed | Nuit : 8 h → 12 h | Night: 8 h → 12 h |
| Gants Moelleux / Squishy Gloves | Pressions ×1,150 → ×1,175 | Presses ×1.150 → ×1.175 |
| Monuments / Monuments | Revenu +3 % → +4 % | Income +3% → +4% |
| École des Plopettes / Plopette School | Aide : 9,3 s → 9,0 s | Helper: 9.3 s → 9.0 s |
| Cadeau du Splorch / Splorch Gift | Cadeau : 1 → 2 niv. | Gift: 1 → 2 lv |
| Tapis de départ / Head-Start Mat | Départ : Tapis 0 → 1 | Start: Mat 0 → 1 |
| Aimant à pièces / Coin Magnet | Aimant : 5 → 8 studs | Magnet: 5 → 8 studs |
| Super Série / Super Streak | Série max : 5 → 6 | Max streak: 5 → 6 |
| Déco qui reste / Kept Decorations | Déco gardées : 9 → 12 | Kept decor: 9 → 12 |
| Sac de nuit / Night Bag | Nuit : 12 h → 13 h | Night: 12 h → 13 h |
| Pot de nuit / Night Pot | Pot la nuit : 25 % → 28 % | Night pot: 25% → 28% |
| Plume | Plopettes : 5 → 6 | Plopettes: 5 → 6 |
| Tremplin / Springboard | Tremplin : 0 → 1 | Springboard: 0 → 1 |

**Cas les plus longs** (ceux que `TextFit_all` mesure en premier, en 28 à 40 px TV, à la taille Medium et au pire cas ; *v2.0 révisé, critique B2* : **tous les libellés à place fixe** de l'en-tête (titre, pastille Souvenir, groupe de droite), de la puce Menu, de la puce d'action spéciale, du suivi d'objectif et des lignes en lecture seule entrent dans `TextFitPending` **avant le code**, mesurés avec les avances réelles de FredokaOne de `TextMetrics`) :
- noms : « École des Plopettes » (19 caractères, 36 px, 540 px de colonne), « Atelier de Big Plop », « Big Plop's Workshop », « Déco qui reste », « Kept Decorations » ;
- libellés : « Pressions ×1,975 → ×2,000 » (FR, le plus long des Gants), « Pot la nuit : 28 % → 31 % », « Déco gardées : 9 → 12 », « Croissance ×20 → ×21 », « Revenu total +12,5 % » (263 px à 32 px) ;
- états : « Il manque » (FR), « Réessaie » (FR), « Boucle 10 » (105 px) ; cadenas « Record 24 » (Monument 10) et « Record 400 » (126 px pour 160 utiles) ;
- nombres : prix et pièces jusqu'à **« 1,00e300 »** et « 99,9 Nvvg » (le plus large des suffixes, 157 px à 40 px ; borne des pièces du §4.2 ; le prix le plus haut possible, Gants 40 ou Tapis Étoilé 20 à r = 400 et A = 0, est borné à 1e300 par `Formulas.clampCoins`) ; Confettis jusqu'à **« 99 999 »** puis **« 999 K »** (largeur 200 couvre les deux) ; niveaux jusqu'à **« 20/20 »** (Tapis), **« 40/40 »** (Gants), « 20/20 » (École), « 18/18 », « 14/14 », « 10/10 », « 1/1 » ;
- bandeau (phrase entière, 2 lignes au facteur 1,5) : « Max (×7) : niveau 12 à 19 · 845 K » ; « Tapis Étoilé : niveau suivant à partir du Grand Splorch 8 dans cette boucle » (FR, la plus longue) ; « Maintiens ✕ pour acheter ×10 » (le glyphe est dessiné, pas écrit).

**Maxima affichés par famille** : Tapis 20 (dont 8 du Tapis Étoilé, plafonnés par r), Décorations 18, Enclos 14, Lit 1, Gants 40, École 20, Monuments 10, lignes de l'Atelier 1 à 3, lignes « Pour le plaisir » 1, 6 (palettes) et 24 (Déco perso de l'Atelier).

#### 10.7.8 Acheter ×1, ×10 ou Max

- Le **bouton de mode** fait tourner **×1 → ×10 → Max → ×1** : on l'atteint avec ↑ depuis les onglets et on appuie sur ✕ (le D-pad, ✕ et ○ suffisent) ; □ est un raccourci ; **E** au clavier ; un clic aussi. **Le mode revient à ×1 à chaque ouverture** de l'écran.
- *(v2.0 révisé, critique m16 : un seul geste pour une même touche)* **Tout achat de l'écran, ×1 compris, se fait par un maintien de 0,6 s** de ✕, d'Entrée ou du bouton de la souris (anneau autour du glyphe, même durée que sur une dalle) : ×1, ×10, Max et l'Atelier ont le même geste. Relâché trop tôt : l'anneau se vide, son `Bump`, et le bandeau dit « Maintiens ✕ pour acheter ×10 » (glyphe de l'appareil) : jamais un bouton qui semble mort.
- **Aperçu exact avant d'acheter** : en ×10 / Max, la colonne Niveau montre « 12 → 22 » et la colonne Prix le total ; le bandeau dit la phrase entière : « ×10 : niveau 12 à 22 · 1,23 M », « Max (×7) : niveau 12 à 19 · 845 K », « ×10 : 4 possibles · niveau 12 à 16 · 310 K ». Le total est la **somme exacte niveau par niveau** de `UpgradeMath.bulk` (le même calcul que le serveur). *(Lot B2, étape 5)* La ligne Décorations dit le gain réel **des niveaux montrés par l'aperçu** (« Revenu total +12,5 % » pour 10 niveaux de 1,25 %), jamais celui d'un seul niveau.
- **Retour chiffré, toujours** : dans la ligne même, « +7 niveaux · −1,2 M » pendant 1,5 s, son `TileBuild`, vibration `tileBuy` ; la cascade de construction dans le ranch attend la fermeture de l'écran (§9.4). Sur un refus du serveur, l'écran montre **la raison et le montant envoyés par le serveur**, jamais un calcul du client.
- Max ne dépense que dans **la famille choisie**, jusqu'au maximum ou au plafond de la boucle. Achat partiel accepté et annoncé (« 4 sur 10 »).
- Atelier : mêmes modes et même maintien de 0,6 s ; chaque ligne n'a que 1 à 3 niveaux (24 pour la Déco perso de l'Atelier).

#### 10.7.9 Entrées protégées (`InputGuard`)

Après l'ouverture d'une fenêtre (cet écran, l'aperçu des renaissances et leurs cartes, et désormais **tout panneau**), ✕ est ignoré **tant qu'on n'a pas vu ✕ relâché et qu'au moins 0,3 s n'est pas passée** ; quand l'élément sous le focus change d'identifiant (onglet, Conseillé recalculé au retour sur l'onglet), même règle avec 0,4 s. Un achat part **à la fin d'un maintien de 0,6 s** commencé par un `InputBegan` de `ButtonA` capté par `ContextActionService` (ou d'Entrée, ou du bouton de la souris sur la ligne ; v2.0 révisé, critique m16), **jamais** de `GuiButton.Activated`. Pendant qu'une ligne est « en cours », ses appuis sont ignorés. Protection contre le double achat : chaque intention porte le **niveau attendu** (`expectedLevel`, §12.7) ; deux appuis rapides n'achètent jamais deux fois le même niveau.

#### 10.7.10 Budget

**1 400 objets d'interface au plus** pour tout l'écran (36 lignes × 32 instances + 3 cartes × 45 + 100 pour le cadre, les onglets et le bandeau = 1 387 ; v2.0 révisé : 6 + 7 + 17 = 30 lignes, la marge reste), construits une fois au chargement ; ombre (`UIShadow`) seulement sur le panneau et les cartes, jamais par ligne. L'interface entière (HUD, panneaux, écran Améliorations) tient dans le budget du §12.9 (4 150 objets sur une séance normale, mesuré au lot I).

### 10.8 Les 20 règles « zéro bug d'affichage » et leurs tests *(v2.0 : nouveau)*

Chaque règle a un test **bloquant** de `./scripts/check.sh` (couche a, d ou h du §12.10). Le nom du fichier et le cas sont écrits ici pour qu'aucune règle ne reste sans test.

| # | Règle | Test (fichier › cas) |
|---|---|---|
| 1 | **Ordre fixe.** Aucun tri dynamique ; les familles du Conseillé ne sont choisies qu'à l'ouverture et au retour sur l'onglet ; une carte garde sa famille après un achat ; la sélection reste sur la même ligne ou le même emplacement | `Upgrades_Order.spec` › « 1 000 achats au hasard : ordre inchangé, sélection en place, aucune carte ne change de famille » |
| 2 | **Aucune ligne détruite ni créée** pendant que l'écran est ouvert ; écran construit une fois au chargement ; lignes verrouillées toujours présentes | `Upgrades_Structure.spec` › « même nombre d'instances avant et après 1 000 achats » ; « une réouverture crée 0 instance » |
| 3 | **Un compteur ne repart jamais de 0.** Montré pour la première fois (ouverture, onglet), il affiche directement sa valeur ; il ne s'anime que si la valeur change pendant qu'il est visible, depuis la dernière valeur affichée. Au Grand Splorch, les pièces passent à 0 sans animation, avec un « pouf » | `Upgrades_Counters.spec` › « 50 changements d'onglet : aucun nombre ne vaut transitoirement 0 » |
| 4 | **Valeur finale toujours posée** à la fin d'une animation et à son interruption | `Upgrades_Tween.spec` › « interruption à 0 %, 50 % et 100 % : même image finale » |
| 5 | **Un seul calcul de prix**, le module pur `UpgradeMath`, partagé par l'aperçu du client et le serveur ; **aucune puissance** (`^`, `math.pow`, `math.exp`) : tables par multiplications successives dans un ordre fixe ; jamais de prix en cache ; somme exacte niveau par niveau ; sur un refus, l'écran montre le montant du serveur | `UpgradeMath.spec` › cas exacts du §4.6 ; `Props_UpgradeMath.spec` › « bulk(n) = somme de n achats ×1 », « aperçu = débit réel (10 000 cas) », « coûts strictement croissants, Tapis 12 → Étoilé 13 compris », « jamais NaN ni inf à MaxR et MaxA » ; `Static_NoPow.spec` › « aucun ^ dans Logic/UpgradeMath et Logic/Prestige » |
| 6 | **Un seul instantané versionné.** L'écran ne lit qu'un objet `{ coins, confetti, levels, caps, version }`, envoyé dans `UpgradeResult` **et** dans le correctif de données ; l'état « payable » ne se calcule que sur lui ; un instantané plus ancien que celui affiché est ignoré | `Upgrades_Snapshot.spec` › « correctif des pièces et UpgradeResult livrés dans les deux ordres : la colonne État ne clignote jamais (Prêt → Il manque → Prêt) » |
| 7 | **Largeurs réservées** pour la plus longue valeur formatée (« 1,00e300 », 8 caractères à 40 px ; Confettis « 99 999 » et « 999 K » ; niveaux « 40/40 » des Gants) ; aucun `AutomaticSize` sur une ligne ; rien ne change de taille quand un nombre grandit ; r ≤ `MaxR`, A ≤ `MaxA` | `Format_Widths.spec` › « 10 000 nombres tirés au hasard : largeur mesurée ≤ largeur réservée » ; `Props_BigNumber.spec` › « 1e300 et math.huge : le plus grand suffixe ou la notation e, jamais inf ni nan » |
| 8 | **Un seul formateur par sorte de nombre**, selon la langue : `BigNumber.abbreviate` pour les montants (§4.2) ; `Format.multiplier` (×1,175, 3 décimales ; croissance ×14, entier) ; `Format.percent` (+5 %, entier) ; `Format.seconds` (9,0 s, 1 décimale) ; `Format.roman` (Record R). Une couleur par famille de suffixes (§4.2). Tout texte passe par `Text.set(label, clé, args)` | `Format.spec` › « deux niveaux voisins donnent deux textes différents » ; « carte, ligne et bandeau montrent le même texte » ; `Static_TextSet.spec` › « aucune affectation .Text hors de UI/Text ; aucun tostring, .. ni string.format de nombre dans UI/* hors de Text et Format » |
| 9 | **Texte mesuré, une seule politique** (§10.1 v2.0 révisé) : `TextSize` fixe, **jamais `TextScaled`** ; noms, nombres et libellés avec `UITextSizeConstraint.MaxTextSize` = taille dessinée (28 à 48 px) **et la compensation de `UI/Text`** si le moteur les agrandit quand même ; 1 ligne pour un nom, 2 au plus pour l'avant → après d'une carte ; phrases du bandeau en 2 lignes au facteur 1,5 ; aucun rétrécissement automatique | `TextFit_all.spec` › « chaque clé de l'écran, EN et FR, à Medium et au pire cas (phrases × 1,5), dans sa boîte » ; `Text_policy.spec` › « contrainte respectée ou ignorée par le moteur : libellés à leur taille dessinée, phrases agrandies » ; facteurs réels photographiés sur la PS5 avec le panneau TextProbe (§10.1), jamais « mesurés dans Studio » |
| 10 | **Tailles fixes, calculées depuis la zone** : carte 432 × 528, ligne 1 328 × 112 au pas de 128 ; un seul layout par parent ; hauteur de défilement par fonction pure, jamais une `ScrollingFrame` en taille automatique | `Layout_upgrades.spec` › « chaque rectangle enfant dans sa carte ou sa ligne, chaque carte dans la zone de 560, à 720p, 1080p et 4K, EN et FR » ; « aucun parent avec deux UI*Layout » |
| 11 | **Un seul composant de carte** (`UI/UpgradeCard`, **3 gabarits fixes** : carte 432 × 528, ligne 1 328 × 112 et *(v2.0 révisé, critique M17)* **tuile 400 × 300** des aperçus de renaissance : icône 120, titre en 2 lignes de 36 px, valeur en 1 ligne de 40 px, marges de 16), partagé par les 4 onglets et les aperçus de renaissance ; la ligne d'explication des aperçus a une boîte de 1 376 × 120 (2 lignes de 40 px au facteur 1,5) | `UpgradeCard.spec` › « chaque gabarit dans chacun des 7 états du §10.7.6 » ; « « ×3 à chaque boucle, pour toujours » (483 px à 36 px) tient en 2 lignes dans la tuile » |
| 12 | **État « en cours » de 3 s** par ligne ; sans réponse, la ligne revient et dit « Réessaie » ; une réponse tardive est appliquée normalement (l'écran montre toujours l'état du serveur) ; un refus « périmé » (`expectedLevel` dépassé) alors que l'instantané montre déjà le niveau visé ne produit **aucun** retour visible, seulement le compteur `UpgradeStale` | `Upgrades_Pending.spec` › « serveur muet : retour en 3 s, focus intact » ; « réponse à 3,5 s puis nouvel appui : exactement un retour +n niveaux » |
| 13 | **Jamais un achat muet** : chaque réponse du serveur produit exactement un retour visible (« +n niveaux · −prix » ou la raison), sauf le refus périmé de la règle 12 | `Upgrades_Feedback.spec` › « 1 réponse = 1 retour » |
| 14 | **Bouton remis à l'état normal** après chaque appui, rafraîchissement ou changement d'onglet ; **cadre de focus dessiné à l'intérieur** de l'élément (6 + 2 px), sans grossissement pour les lignes, les cartes et le rail | `Console_upgrades.spec` › « après achat, Max, rafraîchissement : aucun élément appuyé » ; « le rectangle du cadre de focus est dans le rectangle de découpe de chaque ancêtre qui découpe, pour chaque ligne et chaque carte, dans chaque état » |
| 15 | **Focus jamais perdu ni piégé** (`FocusGuard`, §10.6) ; le focus reste sur la carte achetée, même si elle passe à MAX | `Console_upgrades_nav.spec` › « croix + ✕ + ○ sur les 4 onglets et le bouton de mode, dans chaque état » |
| 16 | **Aucun Robux dans cet écran** | `Static_NoRobuxInUpgrades.spec` › « aucune clé de produit ni de pass dans UI/Panels/Upgrades » |
| 17 | **Un ✕ n'achète jamais par accident** (`InputGuard`, §10.7.9) | `Upgrades_InputGuard.spec` › « △ puis ✕ tenu 2 s : 0 BuyUpgrade » ; « maintien de l'Ascension prolongé : jamais confirmé » ; « 10 appuis à 100 ms sur la carte 1 : une seule famille » ; « chaque mode atteint avec le D-pad, ✕ et ○ seulement » |
| 18 | **Aucun symbole hors police** : → ✓ ★ ∞ ↺ et les glyphes de manette sont des icônes dessinées, jamais des caractères | `Contract_glyphs.spec` › « chaque clé EN et FR n'utilise que des caractères de la table cmap de FredokaOne et de LuckiestGuy (fichiers de police rangés dans le dépôt) » |
| 19 | **Seul le serveur dit ce qui est ouvert** (interrupteurs, plafonds par r, Record R) ; l'écran fige cette liste à l'ouverture ; il se ferme au début de son propre Grand Splorch ou de sa Jelly Ascend | `Upgrades_Freeze.spec` › « changement d'interrupteur ou de plafond écran ouvert : rien ne change avant la prochaine ouverture ; jamais un achat refusé pour une ligne montrée ouverte » ; « Grand Splorch écran ouvert : fermeture, puis réouverture à l'état neuf » |
| 20 | **Budget d'instances de l'écran : 1 400 au plus** | `Upgrades_Budget.spec` › « après la première ouverture : instances ≤ 1 400 ; réouverture : 0 instance créée » |

**Captures de référence** (outil Screens, style de repli à plat, §10.1) *(v2.0 révisé, critique M14 : budget écrit)* : dans `check.sh`, **24 états clés** à 1 920 × 1 080, en anglais et en français, à Medium (≈ 48 images, 3 min au plus) ; **la nuit**, la matrice complète 3 résolutions × 2 langues × 2 tailles de texte (Medium, Largest) × 2 qualités (≈ 360 images, 25 min au plus), pour ces états : r = 0 tout neuf ; r = 5 ; r = 20 tout au maximum ; r = 3 après une Ascension (état « Boucle 6 ») ; r = 10 (Tapis 20/20) ; pièces à 1e300 ; Confettis à 99 999 et à 100 000 ; tout verrouillé ; une ligne « en cours » ; une ligne « Réessaie » ; chaque mode ×1 / ×10 / Max ; Atelier vide, à moitié, complet ; Souvenir de gelée actif. Toute différence d'image non voulue fait échouer la porte. Le vrai style (ombres, dégradés radiaux) n'est vérifié que sur l'appareil, aux tests M6, M11 et M14. *(Lot B2, D23 : dans `check.sh`, les 24 états sont comparés par **relevés de mise en page** (chaque objet visible : chemin, rectangle en px TV, texte montré, sélection ; `Upgrades_Reference.spec`, 48 relevés de référence, ≈ 6 s) ; une différence non voulue fait échouer la porte de la même façon. Les images de l'outil d'écrans servent à la relecture ; la matrice de nuit d'environ 360 images est à faire à l'étape I.)*

---

## 11. Monde : Wobbleton, construite en formes simples

### 11.1 Plan (vue de dessus, rayons en studs, origine au centre de la place) *(v2.0 : modifié)*

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
             │  Monuments (v2.0) : bande r ≈ 260-300 derrière les ranchs  │
             └──────────────────────────────────────────────────────────┘
```

| Élément | Construction | Position / dimensions |
|---|---|---|
| Plateau | Cylinder vertical, matériau Grass menthe (200, 240, 210) | Rayon 320, dessus à Y = 0 |
| Collines | 40 Balls aplaties pastel (rose, menthe, citron), tag `Float` lent pour quelques nuages | r 320-420, hauteur 10-40 ; murs invisibles à r = 322, 30 studs de haut |
| Place | Disque de pavés crème (255, 245, 220), bordure rose | r < 50 |
| MEGA pad | Cylinder rose clair Ø 30, épaisseur 0,6, anneau `Neon` qui s'allume à l'alerte | Centre de la place |
| Statue | Socle Marble Ø 10 × 3 ; le squishy est dessiné par le client à partir de l'attribut `Statue` (espèce, mutation, taille) | Nord de la place (0, 0, −38) |
| Boutique | Petite échoppe en Parts (toit rayé), comptoir avec invite « Vendre » et « Boutique » | Est de la place (38, 0, 0) |
| Autel de la Lune | Arche Marble + croissant `Neon`, compte à rebours du samedi (étiquette du monde en px TV, aussi dans la pastille d'événement, §10.2) | Ouest de la place (−38, 0, 0) |
| Jarre de la jauge | Cylinder `Glass` Ø 8 × 12 qui se remplit (gelée `Neon` dont la hauteur suit la jauge) | Sud de la place (0, 0, 38) |
| Scène de Big Plop | Disque surélevé Ø 10 | Sud-est (27, 0, 27) |
| Fontaine dorée | Vasque Ø 8 (départ du Golden Wobbler) | Nord-est (20, 0, −20) |
| Tableaux des classements | 5 panneaux `SurfaceGui` en arc | Nord, r = 46 |
| Rues | Pavés roses (255, 230, 240) : anneau intérieur r = 95 (10 de large), grand boulevard r = 166 (12 de large), 8 rues radiales de r = 50 à r = 166 | ≈ 400 pièces |
| Quartiers | 24 maisons-bonbons non accessibles (corps Part + toit Wedge + 2 fenêtres `Neon`, coiffées d'une boîte invisible solide jusqu'à 30 studs : aucun toit atteignable), sucettes, buissons-guimauves | Entre les rues |
| Lampadaires | Poteau Cylinder + Ball `Neon` (couleurs pastel) ; `PointLight` seulement un sur quatre (budget de la console la plus faible, §12.9) ; non solides | 64 le long des rues (16 lumières) |
| Prairie des copains *(v2.0 : déplacée)* | Champ de fleurs, panneau « Coucou ! » ; les 12 derniers squishies relâchés par le joueur y jouent (dessinés par son seul client) | **Jardin du quartier nord, centre (52, 0, −135,5), r ≈ 145** (r = 280 est maintenant la bande des Monuments) ; position dans `Logic/WorldLayout.meadowCenter(true)`, disque de 12 studs, 12 places. *(Lot B4)* La Prairie déplacée (≈ 32 pièces) est **dessinée par le client** tant que l'interrupteur `Monuments` est ouvert ; le serveur garde la Prairie de la v1.3 en (0, 0, −284), que chaque client cache alors pour lui seul et rend telle quelle à la coupure |
| Observatoire *(v2.0)* | Tour ronde et coupole (≈ 25 pièces) sur la colline nord ; son faisceau (`Neon`, dessiné par le client) se braque vers un ranch dont la Jelly Ascend est prête | Colline nord, (0, sol, −340), au-delà du mur du bord : inaccessible, aucune invite. *(Lot B4)* **Construit par le client** (24 pièces et le faisceau) tant que l'interrupteur `RanchTiers` est ouvert ; faisceau vers le premier ranch prêt (le sien d'abord), vers le héros pendant une Jelly Ascend |
| Kiosque de Big Plop *(v2.0)* | Petite échoppe à rayures menthe (≈ 15 pièces) avec invite □ « Atelier » : ouvre l'écran Améliorations sur l'onglet Atelier | Ouest-sud-ouest de la place (−32, 0, 24) *(relecture du lot B4 : (−30, 0, 24) avant ; l'échoppe dessinée mesure 4,25 studs de rayon et ne doit jamais couvrir le point d'apparition neutre de la place, 6 × 6 en (−24, 0, 24))*. *(Lot B4)* **Construit par le client** (15 pièces, étiquette « Atelier de Big Plop ») tant que l'écran Améliorations a son instantané et qu'une ligne de l'Atelier est visible ; invite à 8 studs, glyphe de la plateforme (□ PS5, X Xbox, E clavier), aucun travail du serveur |

**Ce qui est solide (règle robuste).** Tous les objets du monde sont **ancrés** (`Anchored = true`) et en `CanTouch = false` : le jeu n'écoute jamais `Touched`. Sont **solides** seulement : le plateau (sol), les murs invisibles du bord, les maisons-bonbons (boîtes simples, `CollisionFidelity = Box`, et leur coiffe invisible), les clôtures des ranchs et leur mur invisible (§6.3). **Chaque solide monte à 30 studs au moins au-dessus du sol** (décision du contrat d'architecture, docs/04 §3.1 et §20 n° 21) : c'est plus que la plus haute portée d'un joueur (saut de la selle géante 13 + hausse de la monture 6 + 3 de marge = 22). Personne n'enjambe une clôture ni ne monte sur un toit, même en monture, et aucune position « debout sur un toit » n'existe pour les règles du serveur. **Tout le reste est non solide** (`CanCollide = false`, `CanQuery = false`) : lampadaires, sucettes, buissons, fleurs, décorations, dalles, Pot, Cuve, Bassin, bol, coussin, étagère, statue, échoppe, autel, jarre, scène, fontaines, panneaux, membranes des portails (côté serveur). Deux solides sont toujours séparés d'au moins 6 studs ou collés sans fente : aucun recoin où un personnage reste coincé. `WorldBuild.spec` vérifie ces règles sur la carte construite (§12.10).

**Graphe des rues** (`Shared/Logic/WorldLayout`, utilisé par `SeededPath`) : nœuds sur l'anneau de la place (r = 50, tous les 45°), sur l'anneau intérieur (r = 95, tous les 22,5°) et sur le boulevard (r = 166, tous les 11,25°, donc un nœud devant chaque portail) ; arêtes le long des rues. Les fuites, les Wild Wobblers et le Golden Wobbler ne quittent jamais ce graphe : ils n'entrent jamais dans un ranch.

### 11.2 Un ranch (repère local : X en travers de −32 à +32, Z du portail (0) vers le fond (72)) *(v2.0 : modifié)*

| Pièce | Construction | Position locale |
|---|---|---|
| Clôture | Poteaux sucre d'orge tous les 8 studs + lisses arrondies, hauteur 4, couleur du ranch ; doublée d'un mur invisible ancré et solide de **30 studs** de haut (§6.3, §11.1) | Tout le tour |
| Portail de gelée | Membrane `Glass` (seule transparence permise avec la gelée Jelly) entre deux poteaux, 8 de large ; non solide pour le serveur, solide pour les autres joueurs sur leur propre client ; la règle est la poussée du serveur (§6.3) | Z = 0, X = 0 |
| Fontaine de Gelée | Vasque Ø 5 avec jet de gelée | Côté rue : Z = −6, X = +12 |
| Panneau du ranch | BillboardGui : nom (ou « Ranch 7 »), couronne R, Fame, « Jour 42 », badge rose « boop » (ranch boopable) ou bulle « bouclier » ; rien pour un ranch Cozy | Au-dessus du portail, Y = 14, distance max 150 |
| Enclos | Zone logique de 54 × 32 (4 rangées × 6 places : colonnes tous les 9 studs, rangées Z = 16, 24, 32, 40), sol en tapis pastel | Z 12 à 44 |
| Pot à Pièces | Grosse marmite dorée (Cylinder + Ball), montant au-dessus | Z = 6, X = −20 |
| Tapis à Goûter | Grand tapis à motif biscuit sous les enclos ; il change de couleur et de motif à chaque niveau | Sous la zone des enclos |
| Cuve à Gelée | Cylinder `Glass` Ø 6 × 9 + couvercle + tuyau ; niveau de gelée `Neon` visible | Z = 52, X = −20 |
| Bassin de Fusion | Bassin Ø 12, eau pastel `Glass`, 5 (ou 6) places flottantes | Z = 52, X = +6 |
| Dalles d'achat | 4 disques `Neon` Ø 4 (Tapis, décoration suivante, Enclos, Lit douillet) avec leur icône (`SurfaceGui`) ; prix et niveau sur une étiquette du monde au-dessus de chaque dalle (§10.2) | Rangée Z = 67 : X = −18, −6, +6, +18 (une 5e prise, réservée (Gelée lente, réserve non planifiée du §17.2), à côté de la Cuve : Z = 52, X = −28) |
| Décorations | 18 emplacements fixes | Autour des enclos et du chemin |
| Bol du Meilleur Ami | Grand bol rose Ø 4 | Z = 58, X = +22 |
| Coussin du Meilleur Ami | Coussin rond Ø 4 | Z = 10, X = +22 (devant la première rangée d'enclos, hors de la zone des places) |
| Étagère à trophées | 3 étagères de 9 places, petites statues dessinées par le client | Fond : Z = 70 |
| Point d'apparition | Une position de `WorldLayout` (aucune pièce) : le serveur y place le personnage à chaque apparition (§6.1) | Z = 30, X = 0, face au Pot |
| Silhouette | Le meilleur squishy (client) | Z = 36, Y = 40 |
| Paliers de ranch *(v2.0)* | Arche, Tour, Balcon, Phare, Dôme, Couronne (§11.5) | Positions du §11.5 |
| Emplacements des Monuments *(v2.0)* | 10 emplacements fixes, derrière le fond, hors clôture | Z = 88 et 116, X = −36, −18, 0, +18, +36 |
| Maisonnette des Plopettes *(v2.0)* | Cabane de 6 pièces, non solide | Z = 60, X = −28 (à 12 studs de la dalle la plus proche ; la prise réservée de la v1.3, Z = 52, X = −28, reste réservée) |
| Geyser de gelée *(v2.0, Record R 17)* | Jet de gelée `Neon` | Z = 4 à 10, X = −24, à 6 studs au moins des dalles, hors du chemin du portail |
| Emplacements de Déco perso *(v2.0)* | 8 petits, 4 grands | Le long des clôtures latérales et du chemin, positions dans `Config/WorldLayout` (règle des 6 studs des dalles) |

**Règle de plan (testée par `WorldLayout.spec`)** : au moins **8 studs** entre le centre d'une dalle et le centre du bol, de la Cuve, du Pot, du coussin et de la prise réservée, et entre le centre d'une dalle et le **bord** du Bassin (rayon 6) ; deux dalles à 12 studs l'une de l'autre ; aucune décoration à moins de 6 studs d'une dalle. Dans la version 1.2, la dalle de droite (X = +24, Z = 62) était à 4,5 studs du bol, qu'on approche pour nourrir, et la rangée de dalles à 2 studs du bord du Bassin, où l'on vient lancer : au stick, on achetait sans le vouloir. Avec la rangée à Z = 67, la dalle la plus proche du Bassin est à 9 studs de son bord, et celle du bol à 9,8 studs.

Ranch k (k = 0…15) centré sur l'angle `22,5° × k + 11,25°`, portail à r = 178, orienté vers la place. Distance entre deux portails voisins : ≈ 69,8 studs.

### 11.3 Éclairage et palette *(v2.0 : modifié)*

| Propriété | Valeur |
|---|---|
| `ClockTime` | 14,5 fixe (plein jour pastel) ; la nuit seulement pendant la Jelly Moon (0,0) |
| `Ambient` / `OutdoorAmbient` / `Brightness` | (150, 140, 170) / (190, 180, 210) / 2,5 |
| `Atmosphere` | Density 0,25, Color (255, 220, 240), Decay (170, 200, 255), Haze 1,2 |
| `BloomEffect` | Intensity 0,6, Size 20, Threshold 1,3 |
| `ColorCorrectionEffect` | Saturation 0,2, Contrast 0,05 |
| `Technology` *(v2.0 : modifié)* | **Unified Lighting** (en service partout depuis juillet 2025) : `LightingStyle = Soft`, `PrioritizeLightingQuality = false`, réglés explicitement dans la place (`default.project.json`, sans `Technology`) et vérifiés par `verify-place` (cible « v2.0 » par défaut) et `Contract_game` ; `Realistic` seulement après mesure sur une vraie PS4. Un seul module possède `Lighting` : le **Directeur d'ambiance** (`Render/AmbienceDirector` dans `LightingController`), une pile à priorités résolue par une fonction pure (`Logic/AmbienceRules`) : **Jelly Moon > BOOP RUSH > alerte et MEGA > Wobble Party / Squish Party > météo > costume de saison > base** ; transition de 2 à 4 s ; 4 s sans flash en Mouvement réduit. *(Lot I, étape 5 : fait)* La place est passée à l'éclairage unifié dans le même commit qu'`Ambience = true` ; si LiveOps coupe `Ambience` en direct, le client rend les valeurs de la place (Soft), il ne revient pas à `ShadowMap`. |

| Préréglage (tween de 2 à 4 s, client) | Changements |
|---|---|
| BOOP RUSH | `Tint` (255, 200, 225), Atmosphere Color (255, 190, 220) |
| Jelly Moon | `ClockTime` 0, `MoonAngularSize` 30, `StarCount` 4000, Tint (200, 190, 255), Atmosphere Color (150, 120, 220) |
| Wobble Party / Squish Party | Tint (255, 240, 210), Bloom 0,8 |
| Hiver « Frost & Sprinkles » (lancement) | Plaques de « sucre glace » (Parts blanches `Sand`), guirlandes de bonbons `Neon` sur les lampadaires, flocons de sucre (`ParticleEmitter` qui suit la caméra, 10 par seconde, budget §12.9) |

Matériaux : SmoothPlastic (squishies, maisons), `Neon` (accents, dalles, lampes), `Glass` (gelée, Cuve, Bassin, portails), Grass (sol), Marble (statue, autel), `Foil`, `Ice`, `ForceField` (mutations). Lisibilité sur une télé à 3 m : sol pastel peu saturé, créatures vives et contours nets ; aucune information importante portée seulement par un petit détail.

### 11.4 Budget de construction *(v2.0 : modifié)*

*(v2.0)* Les décors de la v2.0 sont **dessinés par le client** (§11.5) et ne comptent pas ici. *(Lot B4)* L'Observatoire et le kiosque aussi : ils sont construits par le client (≈ 40 pièces, budget « monde » du budget visuel, §11.5), pas par le serveur, parce que leurs interrupteurs changent en direct ; la carte du serveur est celle de la v1.3. Carte ≈ 4 300 pièces (plafond 4 500) : plateau, collines et murs ≈ 120 ; place ≈ 250 ; rues ≈ 400 ; quartiers ≈ 800 ; lampadaires ≈ 130 ; ranchs 16 × ≈ 160 (tout construit, 18 décorations) ≈ 2 560. Les squishies, les créatures en fuite, les statues et les effets sont **côté client** et ne comptent pas ici (§12.9). `StreamingEnabled` est coupé (§12.9) : toute la carte est présente sur chaque client dès la fin du chargement, rien de ce que le jeu utilise ne peut « ne pas être encore arrivé ».

### 11.5 Le ranch qui évolue *(v2.0 : nouveau)*

Tout ce qui suit est **dessiné par le client** à partir d'attributs répliqués du ranch (`BestR`, `Ascend`, `SplorchReady`, `PetitSplorchAt`, niveaux des dalles, `ranchSkin`, `decoPerso`) : rien ne compte dans le plafond de 4 500 pièces de la carte (§11.4) ; tout compte dans les 15 000 instances d'un client. Toutes les pièces sont ancrées, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false` ; **aucune règle du serveur ne dépend d'un décor**. Une fonction de rendu idempotente par objet ; une interruption pose les mêmes `CFrame` finaux.

**Les 6 paliers permanents** (construits sous les yeux du joueur au premier passage, visibles par les 15 autres)

| Palier | Record R | Nom (FR / EN) | Construction (formes simples, `Neon` pour les accents) | Où (repère du ranch, §11.2) | Pièces |
|---|---|---|---|---|---|
| 1 | 1 | Arche à pompons / Pompom Arch | Arche de guimauve au-dessus du portail, 2 pompons, chiffre romain du Record R | Z = 0, Y = 9 à 13 | 12 |
| 2 | 3 | Tour à bonbons / Candy Tower | Tourelle sucre d'orge (Ø 4, hauteur 16) + drapeau à la couleur du ranch | Coin arrière gauche, hors clôture : X = −30, Z = 76 | 14 |
| 3 | 5 | Balcon de gelée / Jelly Balcony | 2e niveau **décoratif, jamais accessible**, derrière l'Étagère, lampions | Z = 76, Y = 10 à 14 | 18 |
| 4 | 10 | Phare de gelée / Jelly Lighthouse | Phare (hauteur 22), lanterne `Neon` qui tourne doucement ; rose quand le Grand Splorch est prêt | Coin arrière droit : X = +30, Z = 76 | 16 |
| 5 | 15 | Dôme néon / Neon Dome | Dôme filaire `Neon` au-dessus de l'Étagère | Z = 70, Y = 16 | 14 |
| 6 | 20 | Couronne flottante / Floating Crown | Couronne qui tourne lentement au-dessus du panneau du ranch | Y = 18 au-dessus du portail | 12 |
| + | 25, 30, 35, 40 | Étoiles de couronne | 1 à 4 étoiles `Neon` ; couronne arc-en-ciel au 50 | Sur la couronne | 1 chacune |

**Niveau de détail par ranch, jamais par distance.** Le **ranch courant** est celui où se tient le personnage (il ne change que quand le personnage est à 10 studs au moins à l'intérieur d'un autre ranch), sinon le sien ; le ranch courant et **ses 2 voisins** sont en détail complet, les 13 autres en détail réduit (*(lot B4)* 9 pièces au plus : tour, phare et couronne en 3 pièces chacun, le chiffre du tableau des budgets, 13 × 9 ; l'arche, le balcon et le dôme n'ont pas de version réduite). Spec : un robot qui traverse son ranch dans tous les sens ne fait changer de niveau de détail aucun élément. **Aucune lumière de plus** : le phare de son propre ranch prend une des 4 lumières du ranch local (§12.9) ; ceux des voisins restent en `Neon`. **Règle de placement** (`WorldLayout.spec`, pour chacun des 16 ranchs) : au moins 6 studs de toute dalle, rien dans les enclos ni sur le chemin du portail, **rien au-dessus de Y = 21 au centre du ranch** (la silhouette du meilleur squishy ne traverse rien).

**Entre les paliers, les objets qu'on regarde tout le temps montrent la progression** (table complète au §4.29) :
- **La Cuve montre ses 3 axes** : qualité = nombre d'anneaux lumineux (1 à 8) ; vitesse = un agitateur à 3 pales qui tourne en 4 s à la vitesse 3 et en 1 s à la vitesse 10 ; buses = 0 à 5 petites buses qui lâchent une étincelle à chaque naissance mutée ; dorée à la qualité 8. Dans l'onglet Atelier, la ligne en lecture seule « Monte avec ton record » dit « Cuve 3/8 · palier 4/6 » ; les 3 axes (« Qualité 4 → 5 au prochain record ») sont dans le bandeau (critique B2 : la ligne d'origine mesurait 565 px pour 540).
- **Le Pot montre son contenu** : tas de pièces en 4 états selon les **secondes de revenu** qu'il contient (moins de 30 s : vide ; 30 s à 2 min : petit tas ; 2 à 10 min : gros tas ; plus de 10 min : il déborde, 3 pièces sautillent). Son matériau suit le Record R : cuivre, argent (R2), doré (R6), cristal (R16).
- **Le Tapis passe par 6 paliers nommés** (chaque niveau éclaircit la couleur de 8 % ; chaque palier change tout le motif) ; chaque place d'enclos achetée pose un coussin rond à la couleur du ranch ; le Lit douillet est un lit à baldaquin avec un mobile de 3 lunes.

| Niveaux du Tapis | Palier (EN / FR) | Aspect (sur le grand tapis de 54 × 32 studs) | Pièces ajoutées |
|---|---|---|---|
| 0 | — | Herbe du ranch | 0 |
| 1-3 | Picnic Cloth / Nappe pique-nique | Carreaux rose et blanc, 6 pastilles rouges | 6 |
| 4-6 | Shortbread / Biscuit sablé | Beige doré, bord dentelé, 8 « trous » de biscuit | 20 |
| 7-9 | Rainbow Candy / Bonbon arc-en-ciel | 7 bandes `Neon` pastel | 7 |
| 10-12 | Golden Jelly / Gelée dorée | Matériau `Foil` doré, étincelles (2 par seconde) | 0 + particules |
| 13-16 | Starry Mat / Étoilé | Bleu nuit, 12 points `Neon` qui scintillent lentement | 12 |
| 17-20 | Galaxy Mat / Galaxie | Bleu nuit, 12 points qui tournent (un tour en 30 s), 2 étoiles filantes | 14 |

- **Le ranch ne paraît jamais vide après un Grand Splorch** : chaque décoration remise à zéro laisse un **socle de souvenir** (disque de vermicelles Ø 2,5 studs + l'icône de la décoration en `Neon`, 2 pièces) ; quand on la rachète, elle ressort de son socle en cascade. Les décorations gardées restent debout avec un fanion ★. Règle : décoration n° k construite si `tiles.decor ≥ k`, sinon socle ; jamais les deux (test sur les 19 valeurs). *(Lot B4)* Les socles n'apparaissent qu'à partir du Record R 1 : un ranch qui n'a jamais fait de Grand Splorch n'a pas de souvenir (ses décorations pas encore achetées ne laissent rien).
- **Décorations dorées** : une décoration construite dans 10 boucles devient dorée pour toujours ; « Moulin étoilé · 7/10 » suivi d'une **étoile dessinée** dans l'écran Améliorations (bandeau ; critique m4 : jamais le caractère, règle 18). Champ `decorBuilds` (18 petits entiers bornés à 10).
- **Monuments** derrière le fond du ranch, sur **10 emplacements fixes en coordonnées du ranch**, les mêmes pour les 16 ranchs : 2 rangées de 5, à Z = 88 et Z = 116 (r ≈ 266 et 294, le fond du ranch étant à r = 250), X = −36, −18, 0, +18, +36. La **Prairie des copains** (r = 280 au nord en v1.3, en plein sur ces emplacements) **déménage dans un jardin du quartier nord** (r ≈ 120 à 150 ; position dans `Config/WorldLayout`). 20 pièces au plus par Monument pour le ranch courant, 6 pour ses 2 voisins, 1 silhouette pour les autres.
- **Déco perso** (au lancement) : 12 emplacements fixes (les emplacements 1 à 8 sont petits, les 9 à 12 grands ; un objet ne se pose que sur un emplacement de **sa** taille, et jamais sur deux emplacements à la fois ; « Retirer » vide l'emplacement), choisis sur un **plan du ranch vu du dessus** dans l'onglet *Mon style* du panneau Ranch (jamais en visant au stick) ; **40 objets** (liste EN / FR, source et taille d'emplacement à l'Annexe B, critique M10) : **16 gagnés** (Squishydex, jours de Plop, objectifs, Jelly Moon, piste de la semaine, Carnet du Ranch) et **24 achetés en Confettis** à l'Atelier (ligne « Déco perso de l'Atelier », §4.26), jamais au hasard ni en Robux. Le premier, le **Fanion à ton nom**, est offert à 5:00 de jeu.
- **Signal « prêt »** : quand le Grand Splorch est prêt, anneau rose qui pulse autour de la silhouette du ranch, panneau « PRÊT ! », phare rose si le palier 4 est construit (attribut `SplorchReady`, écrit seulement par le serveur). Quand la Jelly Ascend est prête, l'Observatoire de la colline nord braque son faisceau vers le ranch.
- **Halo et ciel** (§4.27) au-dessus du ranch, jusqu'à 80 pièces près, 10 pour les voisins, 3 loin. *(Lot B4)* Le ciel est au-dessus de la clôture du fond (repère du ranch (0, 34, 84), disque de 12 studs, au-dessus des Monuments), jamais dans la colonne de la silhouette ; le halo suit la tête du joueur (budget à part : 5 gouttes × 16 joueurs). **Squishy-Soleil** (jalon géant `GiantTier` ≥ 3) : un anneau-soleil derrière la silhouette du ranch (disque pâle et 8 rayons `Neon`, 9 pièces, détail complet seulement), avec l'anneau rose « prêt » et le cadre doré du Record R 18 : les seuls décors permis dans la colonne au-dessus de Y = 21.

**Habillages de ranch** (14, gagnés, jamais au hasard, jamais en Robux) : couleur, matériaux de la clôture, du sol et du portail. Les 3 de la v1.3 (couleur du ranch, Moonlit, Candy Night) + Guimauve (R1), Caramel (R3), Menthe glacée (R5), Phare (R10), Glacier sucré (R12), Néon (R15), Cosmos sucré (R17), Royal (R20), Nuage (A1), Aurore (A3), Céleste (A5). Un habillage = une ligne de données appliquée par le client à des pièces qui existent déjà ; le serveur garde un identifiant (`ranchSkin`), validé contre la liste gagnée ; inconnu au chargement → habillage par défaut, compté dans Diagnostics. Panneau Ranch → onglet *Mon style* (qui remplace l'onglet *Dalles*).

**Kit de costume de saison** (une ligne de données `Events.Costumes`) : `dates` (UTC, intervalle **[début, fin)** : la date de fin est exclue), `theme` (≤ 12 jetons de la feuille de style), `lighting` (1 préréglage), `decorSet` (≤ 300 pièces dessinées par le client), `particles` (≤ 20 par seconde), `bigPlop` (≤ 3 pièces), `music` (sons officiels seulement), `featured` (une récompense vedette **gagnée**). Le costume actif est une fonction pure de la date ; deux costumes ne se recouvrent jamais (test). Au lancement : **Frost & Sprinkles** (sucre glace et guirlandes `Neon`, chapeau de neige sur les 24 maisons-bonbons, stalactites de sucre d'orge sur la clôture avant de son ranch et des 2 plus proches, écharpe et bonnet de Big Plop, thème bleu glacier, flocons 10 par seconde ; vedette gagnée : selle « Sucre glace » en nourrissant Plop 5 jours pendant la saison, champ `season.frostDays`). Les costumes suivants (Galette des rois, Saint-Valentin, Printemps…) sont des **mises à jour de contenu** (§7.6), sans date dans ce document.

**Budgets ajoutés** (console la plus faible, §12.9 ; pire cas sur un client)

| Ajout | Pièces | Particules | Lumières | `Highlight` | Transparence |
|---|---|---|---|---|---|
| Tapis, coussins, lit (ranch courant + 2 voisins ; couleur seulement ailleurs) | (20 + 24 + 10) × 3 = 162 | ≤ 6 | 0 | 0 | 0 |
| Changements par R : Cuve, Pot, Bassin, lampions, portail, geyser | ≤ 40 × 3 = 120 | 0 | 0 | 0 | 0 |
| Paliers de ranch | 405 (3 × 96 + 13 × 9) | 0 | 0 de plus | 0 | 0 |
| Socles de souvenir | 18 × 2 × 3 = 108 | 0 | 0 | 0 | 0 |
| Monuments (10) | 200 + 120 + 130 = 450 | 0 | 0 | 0 | 0 |
| Plopettes et maisonnette (≤ 5 pièces chacune, détail complet dans 3 ranchs) | ≤ 170 | 0 | 0 | 0 | 0 |
| Halo et ciel | ≤ 80 + ≤ 10 près, 3 loin | 0 | 0 | 0 | 0 |
| Déco perso | 3 × 120 + 13 × 4 = 412 | 0 | 0 | 0 | 0 |
| Événements relookés (lune, traces, ballons) | ≤ 26 | 0 de plus | 0 | 0 | 0 |
| Météo (temporaire) | ≤ 84 | ≤ 60 (remplace les flocons) | 0 | 0 | 0 |
| Personnalités, visages, tours | **0** (pièces existantes) | ≤ 20 | 0 | 0 | 0 |
| *(Lot B5)* Place en fête (guirlandes, ballons, arches, feux, statue ; temporaire) | ≤ 40 | ≤ 20 | 0 | 0 | 0 |
| *(Lot B5)* Copies des spectacles (Petit Splorch, Jelly Ascend, Palier ; temporaire) | ≤ 96 | quota des effets | 0 | 0 | 0 |
| *(Lot B5)* Petit Big Plop (Chantier, geste vers l'Observatoire ; temporaire) | ≤ 17 | 0 | 0 | 0 | 0 |
| **Total** | **≈ 2 040 pièces** | **≤ 200 avec le reste du jeu** | **0 de plus** | **0 de plus** | **0 de plus** |

**Budget visuel en direct** (`Render/VisualBudget`) : chaque système déclare ses pièces, particules et lumières ; au-delà, il **dégrade** dans un ordre fixe (ranchs les plus lointains d'abord, son propre ranch en dernier) ; un dépassement n'est jamais une erreur, seulement un compteur de Diagnostics. Mesure obligatoire sur une vraie PS4 ou Xbox One avec 16 joueurs (test M6). **Trois versions de chaque effet** : normale, Mouvement réduit (pas de déplacement d'interface, pas de secousse, pas de flash, amplitudes ×0,5, 3 changements de couleur par seconde au plus) et Graphismes légers (particules ×0,3, détail réduit). **Un seul grand spectacle à la fois** : les moments nouveaux sont locaux ou d'ambiance et se taisent pendant un Rush, un MEGA, un Grand Splorch ou la danse de Big Plop.

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

### 12.2 Arbre Rojo et interrupteurs *(v2.0 : modifié)*

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
      BigNumber.luau                affichage des nombres géants, suffixes K, M, B, T… dans les deux langues (§4.2)
      Hash.luau                     (repris)
    Render/
      SquishyBuilder.luau           recettes de modèles (client)
    Localization/Strings.luau       EN + FR
    Util/                           (repris) Clock, Format, Signal, Tables, Trove, Validate
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
      Prompt (invites du monde, §10.4), FocusGuard (focus jamais perdu, §10.6), WorldText (textes du monde en px TV, §10.2)
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
| `JellyAscend`, `Helpers`, `WeeklyTrack`, `Weather` *(v2.0)* | `true` | Jelly Ascend et Petit Splorch (§4.27), Plopettes (§4.28), piste de la semaine et Défis (§7.5), météo visuelle (§5.6) : **au lancement** ; `false` seulement pour couper une fonction en cas de problème en ligne (l'écran Améliorations est alors reconstruit pendant qu'il est fermé, §10.7.5) |
| `Season`, `SlowJelly`, `Duo`, `Parcels`, `WorldFirst`, `FameLineage`, `GreatJelly` | `false` | Réserve non planifiée (§17.2) ; le code de lancement n'en contient que les crochets |
| `RewardedAds` | `false` | Aucun code de publicité au lancement ; la clé existe pour qu'on ne l'ajoute jamais « par défaut » |
| `Diagnostics` | `true` | Remontée des erreurs et panneau des administrateurs (§12.11) ; `false` coupe seulement l'envoi des clients (les comptes du serveur restent) |

### 12.3 Ordre d'initialisation, tick et calcul paresseux

`Main.server.luau` : `DiagnosticsService` branché en tout premier (il doit voir les erreurs du démarrage), puis `Net.setup()`, puis `Init()` puis `Start()` dans cet ordre : DataService → MonetizationService → WorldService → RanchService → EconomyService → SquishyService → QuestService → CommunityService → EventService → RushService → SplorchService → ProductService → LeaderboardService → ChaseService (dernier : il porte le tick).

**Tick de `ChaseService`** (accumulateur sur `RunService.Heartbeat`, pas fixe de 0,1 s, 3 pas rattrapés au plus par image) :

```
1. now = Clock.now()
2. pour chaque joueur chargé avec personnage : MoveCheck.step(...) → position validée ? peut agir ?
3. RanchService.step : intrus repoussés ; Pot encaissé si le joueur est à ≤ 5 studs ; dalle : entrée (≤ 2,5 studs, sortie > 3,5), puis 0,6 s dessus sans porter ni maintenir = un achat (positions validées, ZoneRules)
4. EventService.step(now) : transitions de phase (Rush, MEGA, Golden, Lune, Wobble Party, file des spectacles)
5. RushService.step(now) : clôtures (renouvellement toutes les 20 s), maintiens de boop terminés ou rompus
6. Créatures : apparitions dues (fuites personnelles, Wild, Golden), fins (25 s, 20 s, 30 s)
7. Captures : intentions `Catch` reçues depuis le tick précédent, dans leur ordre d'arrivée, chacune vérifiée à **son** instant `tClient` (position SeededPath à tClient contre la position validée du joueur à tClient, §12.5) ; captures à l'atterrissage des bonds arrivés à échéance
8. MEGA : pressions reçues agrégées, battement diffusé toutes les 0,25 s
9. Diffusion groupée : ChaseEvent, EventState, RanchPatch
10. Délais : tout état qui a dépassé son délai (StateTimeouts, §12.10) est fermé proprement, compté, et signalé à Diagnostics s'il n'aurait pas dû l'être
```

Chaque étape du tick est protégée : une erreur dans l'étape d'un joueur est attrapée (`pcall`), comptée par Diagnostics, et n'arrête ni les autres joueurs ni les étapes suivantes.

**Calcul paresseux** (module pur `Formulas`) avec un **compteur de croissance par ranch** : `G(t) = G0 + g × (t − t0)`, où `g` est la croissance par seconde du §4.3. La taille d'un squishy d'enclos ou du Bassin vaut `z + (G(t) − zg)`, où `z` et `zg` sont notés quand il entre dans l'enclos ; dans la Boîte à dodo ou la Boîte aux lettres, elle reste figée à `z`. Un changement de `g` (dalle, boost, famille Jelly) ne touche que le compteur du ranch, jamais les squishies : une Wobble Party qui touche les 16 ranchs à la fois envoie 16 petits messages, pas 384 mises à jour de squishies. `G` repart de 0 au Grand Splorch (les doubles restent précis). Le revenu total est linéaire en `G` : `I(t) = S1 + K × G(t)`, avec `K = Σ 0,02 × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B` sur les squishies d'enclos et `S1 = Σ k × (z − zg)`. Le Pot est l'intégrale exacte :

```
pot(t) = pot0 + I(t0) × Δ + ½ × K × g × Δ²      (Δ = t − t0)
```

Le serveur « règle » (`settle`) le ranch à chaque événement qui change `g`, `A`, `P` ou `B` (achat, naissance, fusion, vente, boost qui commence ou finit, ami qui arrive ou part, Grand Splorch, **palier de trophée franchi, page dorée ou bonus de famille gagné, changement de Fame**), avant chaque sauvegarde, et toutes les 30 s (décalé selon le joueur). Chaque seconde n'est intégrée qu'une fois. Le client prédit les tailles et le Pot avec les mêmes formules, corrigé à chaque patch.

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
- **Capture vérifiée à l'instant de l'appui.** Le joueur a vu la créature au moment où il a appuyé ; entre l'envoi et le tick du serveur, elle a avancé de `v × (latence aller + attente du tick)`. Comparer à `pos(maintenant)` coûtait 3,6 studs à 250 ms de ping et 16 studs/s : la marge réelle tombait de 5 à 2,9 studs, et les joueurs les plus loin du serveur perdaient leurs captures. Donc : le client envoie `Catch(id, tClient)` ; `tClient` est ramené dans `[maintenant − 0,35 ; maintenant]` ; le serveur compare `pos(tClient)` (trajet déterministe, donc exact) à la **position validée du joueur à `tClient`** (historique interpolé de 0,5 s des positions acceptées par MoveCheck) : distance **à plat (XZ)** ≤ 6,5 studs (5 + 1,5 de tolérance ; 9,5 = 8 + 1,5 pour le propriétaire de sa fuite du Rush) ; écart vertical entre les **pieds** du joueur (racine − hauteur debout − hausse de la monture) et le sol sous la créature ≤ 8 ; budget d'action positif (`canAct`). Deux captures de la même créature (Golden, fuite du Rush) : la première arrivée gagne. Un tricheur qui choisit son `tClient` gagne au plus 0,35 s de trajet : c'est borné, comme pour les pressions (§4.7). Après un bond accordé, le serveur tente lui-même la capture à l'atterrissage, à `tClient du bond + 0,35 s`, au point calculé par `LeapRules` à partir de la géométrie du bond (§4.12), jamais à partir de la position que la physique a donnée.
- **`ChaseEvent`** (fiable, groupé à 4 Hz) : `spawn = { id (u16), kind (runaway | escape | wild | wildPersonal | golden | demo), species, mutation, size, ownerSlot?, booperSlot?, seed, t0, startNode, awayAngle, duration }` et `finish = { id, reason (caught | returned | expired), bySlot? }`. Les créatures personnelles (fuite, Wild Wobbler personnel, démonstration de Big Plop) ne sont envoyées qu'au client concerné.
- **État des ranchs** : `RanchSnapshot` à l'arrivée (16 ranchs, ≈ 15 Ko), puis `RanchPatch` groupé par image : par ranch `{ growth = { G, g, t }, tiles, decor, R, fame, day, mode, hidden, name }` et par squishy `{ op = add | remove | update, uid, s, m, st, z, zg, bf, o, at }`. Le client calcule la taille d'un squishy d'enclos par `z + (G(t) − zg)` (§12.3) ; un changement de croissance n'envoie que le compteur du ranch. Aucun envoi par seconde.
- **Arrivée en cours de partie** : `RanchSnapshot` + `EventState` + créatures actives, une seule fois.
- **Messages perdus ou en retard** : chaque patch porte un numéro de suite par destinataire ; un trou dans la suite fait redemander un `RanchSnapshot` (`RequestWorld`). Une créature dont l'heure de fin est passée disparaît chez le client même si le message `finish` n'est pas arrivé. Le client ne reste jamais sur un état faux.

### 12.6 Données sauvegardées (schéma v1, v2 en v2.0) *(v2.0 : modifié)*

Magasin `PlayerData_v1`, clé `player_<UserId>`, gérés par le `DataService` repris de Comet Conga, avec ses règles durcies :

- **Verrou de session** posé au chargement (`UpdateAsync`), avec un jeton propre à ce chargement. Un verrou d'un autre serveur plus jeune que 30 min fait réessayer toutes les 5 s ; il n'est **repris** qu'après **5 lectures réussies** qui l'ont vu (au moins 25 s d'observation pendant que les DataStores répondent), **jamais parce que des erreurs ont épuisé les essais** (sinon renvoi poli « reviens dans un instant », rien d'écrit). Le serveur qui détient le verrou réessaie sa sauvegarde de départ en panne toutes les 15 s au plus pendant 5 min : un enfant qui revient sur un autre serveur après une panne retrouve ce qu'il a gagné (leçon `Fix_final_data_lock` de Comet).
- Chaque écriture refuse d'écraser un enregistrement verrouillé par un autre serveur ou de **schéma plus récent** (dans ce cas le joueur est renvoyé : « Ce serveur n'est pas à jour »).
- Attribut répliqué `ProfileLoading` pendant les essais (lu par l'écran de chargement).
- Jamais de profil par défaut sauvegardé par-dessus un échec de chargement ; en ligne, jamais de repli en mémoire si les DataStores sont indisponibles.
- Sauvegarde automatique toutes les 90 s, au départ, à la fermeture (`BindToClose`), et immédiate après un achat Robux (le reçu n'est acquitté qu'après une écriture réussie). `settle` est appelé avant chaque sauvegarde.

*(v2.0 révisé, critique m6)* Le bloc ci-dessous est le **schéma v1 de la version de test** (commit 7382f88), gardé comme référence de migration ; le schéma **v2** (`Schema.VERSION = 2`, `ascend` = A au lieu de « réservé », `season.premium` supprimé, champs ajoutés plus bas) est écrit dans `contract-changes.md` §1, puis docs/04. La sauvegarde-témoin `tests/fixtures/profiles/v1.json` (qui n'existe pas encore : seul `v0.json` existe) est créée au paquet P0 à partir d'un profil de la version de test envoyée au propriétaire.

```lua
Schema.VERSION = 1
Schema.PRIVATE_KEYS = { receipts = true, flags = true }

function Schema.defaults()
  return {
    version = 1,
    -- économie (§4.1, §4.6, §4.8)
    coins = 0, pot = 0, lastOnline = 0, R = 0,
    growth = { G = 0, g = 1, t = 0 },   -- compteur de croissance du ranch (§12.3) ; t = Clock.now() du dernier règlement
    tiles = { snack = 0, decor = 0, pens = 0, cozyBed = false },   -- la Cuve n'est pas ici : son niveau se calcule à partir de R (§4.9)
    boosts = { personalLeft = 0 },   -- secondes restantes du boost personnel (en pause pendant un boost de serveur) :
                                     -- Nourrir Plop (+300), minutes non jouées d'une Squish Party achetée (§8.3)
    -- collection (§4.3, §4.9, §4.14)
    squishies = {},   -- [uid] = { s = id d'espèce, m = 0-9, st = 0-5, z = taille notée, zg = compteur G noté avec z,
                      --           bf = 0-3, lk = bool, o = tenue ou "" (seul endroit où la tenue portée est gardée),
                      --           at = "pen"|"pool"|"dodo"|"mail", gd = Clock.day() du dernier bonus Héros / retour (§4.21.3) }
    nextUid = 1,
    mount = "",       -- uid de la monture choisie ("" = la plus grosse, dès que la première selle est gagnée)
    vat = { fillAt = 0, pending = false, pityRare = 0, pityEpic = 0, newPulls = 3 },
    runaway = { nextAt = 0 },
    dex = {   -- tableaux denses, une case par espèce (0 par défaut), allongés par reconcile quand une espèce
              -- arrive : sans limite (une espèce par semaine) et sans trou (les DataStores refusent les tableaux à trous)
      mut = {},       -- mut[s] = masque : bit 0 = page de l'espèce tamponnée, bit m = mutation m trouvée (m = 1-9)
      stars = {},     -- stars[s] = masque de 5 bits : bit (k − 1) = badge ★k
      fam = {},       -- fam[f] = 1 si le bonus de la famille f est gagné (pour toujours, §4.17) ; dense, une case par famille
      rewards = 0,    -- dernier jalon réclamé
    },
    released = {},    -- 12 derniers squishies relâchés { s, m } (Prairie des copains, §4.13)
    trophies = {},    -- trophies[s] = taille record (tableau dense, 0 par défaut)
    outfits = { owned = {} },   -- owned[id] = nombre d'exemplaires ; la tenue portée n'est gardée que dans squishy.o
    moon = { lastSession = 0 },  -- dernière séance de la Lune où une Goutte de Lune a été donnée (une par séance et par compte, §4.23)
    -- social et rétention (§6, §7)
    fame = 0, plopDays = 0, lastFeedDay = 0,
    onboarding = { step = 0, done = false },
    objectives = { day = 0, list = {}, rerolls = 0, allClaimed = false },  -- list = { { id, p, done, claimed } × 3 }
    caps = { day = 0, rushBabies = 0, splorchGifts = 0, splorchCoins = 0, fameRush = 0, fameRelease = 0,
             petSit = 0, petSitIn = 0, petSitBy = {}, claps = 0, partyBuys = 0 },
             -- petSit = pressions récompensées comme visiteur (100) ; petSitIn = reçues comme propriétaire (100) ;
             -- petSitBy[tostring(UserId du propriétaire)] = pressions comptées pour « Plus serviable » (20 par ami)
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
    season = { id = 0, xp = 0, premium = false, claimed = {} },  -- v2.0 : la saison de 28 jours est supprimée ; season.frostDays (costume) s'y ajoute
    slowJelly = { slots = {} },                                  -- Gelée lente 1 / 4 / 12 h
    parcels = { inbox = {}, sentDay = 0, sent = 0 },             -- colis entre amis
    fameLineage = 0,                                             -- lignée de Fame (registre séparé)
    worldFirst = {},                                             -- trouvailles World First
    costumes = {},                                               -- costumes de saison obtenus
    packs = { side = 0, quoteProduct = "", quoteAmount = 0, quoteAt = 0 },  -- paquets de pièces (si le propriétaire les
                                                                 -- rouvre) : porte-monnaie « Pièces de côté » et devis du serveur
    -- privé
    passes = {}, receipts = {}, flags = { strikes = 0, lbBanUntil = 0 },
  }
end
```

- **Champs ajoutés par la v2.0** *(v2.0 : nouveau ; détail, propriétaires et migration dans `contract-changes.md` du rôle design, puis docs/04)* : `bestR` (Record R, ≥ R) ; `ascend` (le champ réservé devient A, 0 à 60) ; `confetti`, `confettiTotal` (entiers de 0 à 1e9) ; `tiles.star` (niveaux 13-20 du Tapis Étoilé, 0 à 8), `tiles.gloves` (0 à 40), `tiles.school` (0 à 20), `tiles.monuments` (0 à 10, gardé) ; `atelier` (tableau dense d'un niveau par ligne de `Config/Upgrades`, borné par le maximum de la ligne) et `atelierCosmetics` (ensemble de bits) ; `stats.upgradesBought` (Carnet du Ranch), `carnet` (ensemble de bits des paliers réclamés) ; `weeklyTrack = { period, points, claimed, challenges }` (`period` = numéro de période de `QuestRules.weekIndex`, jamais un numéro de semaine de l'année) ; `ranchSkin` (identifiant gagné) ; `settings.haloOn` ; `decorBuilds` (18 petits entiers bornés à 10) ; `decoPerso = { owned (ensemble de bits), slots (12) }` ; `hearts = { givenDay, givenTo (20 au plus), receivedTotal }` ; `mastery` (ensemble de bits, un par espèce) ; `season.frostDays` ; `unlocksSeen` (Record R dont la carte « Nouveau : … » a été montrée). **Ensembles de bits** : un `number` de Luau ne garde les entiers exacts que jusqu'à 2^53 et `bit32` travaille sur 32 bits : chaque ensemble est un **tableau de mots de 32 bits** (`{number}`, longueur ceil(n / 32)), agrandi par `reconcile`, lu et écrit seulement par `Logic/Bitset` (200 espèces et 64 objets passent `JSONEncode` / `JSONDecode` sans perdre un bit). **Migration** : `Schema.VERSION` passe à **2** ; l'étape `migrate(v1 → v2)` est pure et testée sur `tests/fixtures/profiles/v1.json` : `bestR = R`, Confettis et places offertes du premier passage rendus d'un coup pour les Record R déjà atteints, tout le reste à sa valeur par défaut (aucune perte, aucun champ effacé).

- **Taille** : au plus 24 + 60 + 20 = 104 squishies × ≈ 70 octets ≈ 7 Ko ; profil complet < 20 Ko (v2.0 compris). `Contract.spec` vérifie qu'un profil plein (104 squishies, trophées et Squishydex partiels, 64 espèces) passe `JSONEncode` puis `JSONDecode` sans aucun changement, et `Schema.spec` qu'un Squishydex de 64 espèces garde ses tampons et ses étoiles après sauvegarde puis rechargement (aucun masque de bits partagé entre espèces : en Luau, `bit32.lshift(1, 32) == 0`).
- **État de session, jamais sauvegardé** (mémoire du serveur) : paires boopeur → ranch et leur heure, fuites par ranch sur l'heure glissante, listes « Pas ce joueur », file des Grands Splorch, objectifs gardés jusqu'à la fin de la session, historique de 0,5 s des positions validées (captures, §12.5), crédits de bond, attente sur une dalle, dernière activité de chaque joueur (N actifs du MEGA et de la jauge), dernier spectacle complet vu (§4.15), réglage « BOOP RUSH autorisé » d'un serveur privé (attribut du serveur, réglé par son propriétaire `PrivateServerOwnerId`).
- **Données lues = données à revalider** : au chargement, `reconcile` revérifie chaque champ (type, bornes, `NaN`, tableaux denses, uid existants, emplacements de Meilleur Ami uniques) et répare ce qui est faux avec une valeur sûre, en le comptant dans Diagnostics. Une vieille sauvegarde ou un bug passé ne peut donc jamais faire planter le chargement.
- **Règles** : `coins`, `pot`, `z` dans `[0 ; 1e300]`, jamais `NaN` ; uid = chaîne base 36 de `nextUid` (8 caractères au plus) ; invariants vérifiés en développement après chaque mutation (au plus 24 squishies `pen`/`pool`, 60 `dodo`, 20 `mail` ; un seul squishy par emplacement de Meilleur Ami ; tenue portée par un uid qui existe).
- *(v2.0 révisé, critique m7)* **Migration v1 → v2** : `stats.upgradesBought` (Carnet du Ranch) part d'une **estimation** = somme des niveaux actuels (dalles, Enclos, Lit), jamais de 0 ; `decorBuilds` part de 1 pour chaque décoration construite au moment de la migration ; `weeklyTrack.firstPeriodEnd` = le **2e lundi après la migration** (le schéma v1 n'a pas de date de première connexion) ; une carte « Bienvenue dans la v2 ! » (Annexe B) s'affiche une fois.
- **Migrations** : `Schema.migrate(data, from)`, étapes pures testées sur une sauvegarde-témoin (`tests/fixtures/profiles/v<n>.json`) ; on n'efface jamais un champ dans la version qui le remplace ; `reconcile` ajoute les champs nouveaux avec leur valeur par défaut. Les champs réservés ci-dessus évitent toute migration pour les fonctions de janvier.
- **Droit à l'effacement** : chaque `UpdateAsync` du profil renvoie `userIds = { UserId }` (procédure reprise de Comet).
- Les classements de la semaine vivent dans des `OrderedDataStore` séparés (§6.9) ; la lignée de Fame, si elle est un jour décidée, aura son propre registre (§17.2).

### 12.7 Messages réseau (remotes) *(v2.0 : modifié)*

Déclarés dans `Shared/Remotes.luau`, créés par `Net.setup()`. Chaque handler serveur suit l'ordre : **débit** (`RateLimit.allow`, seau à jetons par action, vidé au départ) → **types** (`Validate` : nombres finis, entiers, longueurs de chaînes, tables séquentielles bornées) → **existence** (clé de configuration, uid possédé) → **état** (profil chargé, personnage vivant, position validée, `MoveCheck.canAct`) → **règles métier** → mutation atomique → réplication. Un message refusé ne produit **aucune** mutation et au plus un `Feedback` neutre.

**Client → serveur (intentions)**

| Remote | Charge utile | Validation serveur | Débit max |
|---|---|---|---|
| `Press` | `uid: string, tClient: number` | uid possédé, dans un enclos ou le Bassin, à ≤ 10 + 2 studs à plat de la place du squishy (position validée, §4.7), recharge de 8 s écoulée ; `tClient` fini, accepté s'il est dans [maintenant − 0,35 ; maintenant + 0,05] | 12 / s |
| `PetPress` | `ownerId: number, uid: string, tClient: number` | Pet-sitting (§6.4). Propriétaire présent et ami Roblox de l'envoyeur ; uid dans le dernier message `Fence` de pet-sitting de ce ranch ; envoyeur côté rue à ≤ 10 studs de la clôture ; recharge de 8 s du squishy ; plafonds du jour (100 visiteur, 100 propriétaire) ; `tClient` comme `Press` ; PERFECT calculé avec `hash(ownerId, uid)` | 12 / s |
| `PickUp` | `uid: string` | Touche ○ / Q. Possédé, dans un enclos, à ≤ 10 studs, rien de porté, pas en monture, pas en attente de Grand Splorch | 4 / s |
| `PutDown` | — | Quelque chose est porté | 4 / s |
| `Throw` | — | Quelque chose est porté, à ≤ 12 studs du Bassin ; place ou jumeau disponible | 4 / s |
| `FuseMenu` | `uidA: string, uidB: string` | Différents, possédés, jumeaux, hors Lettres, pas en attente de Grand Splorch (verrouillés acceptés : choix du joueur) | 2 / s |
| `FuseAll` | — | Au moins une paire de jumeaux non verrouillés, hors Lettres ; le serveur fait toute la chaîne (§4.10) | 1 / 2 s |
| `BuyTile` | `tile: string` | `tile` ∈ {snack, decor, pens, cozyBed} ; *(v2.0 révisé, critique m15)* `snack` achète aussi les niveaux 13 à 20 (Tapis Étoilé) quand ils sont ouverts dans la boucle (même famille, même ligne, même `UpgradeMath`) ; niveau < maximum ; condition R ; règlement puis pièces ≥ prix. Position non exigée (achat possible depuis le panneau Ranch ou par □ sur la dalle). L'achat en restant 0,6 s sur une dalle, lui, est détecté par le serveur sans aucun message (§4.6) | 10 / s |
| `MoveSquishy` | `uid: string, to: string` | `to` ∈ {pen, dodo} ; place libre ; pas porté, pas en fuite | 4 / s |
| `ClaimMail` | `uid: string` | Dans la Boîte aux lettres ; place libre | 4 / s |
| `Sell` / `Release` | `uids: {string}, confirmed: boolean` | Table séquentielle de 1 à 84 chaînes uniques (enclos + Dodo, pour « Ranger »), possédées, ni Meilleur Ami, ni verrouillées, ni en fuite, ni en attente de Grand Splorch ; `confirmed = true` exigé s'il y a un Épique+ ou une mutation Doré+ (2e étape faite par le client, §4.13) | 2 / s |
| `SetLock` | `uid: string, locked: boolean` | Possédé | 6 / s |
| `SetBestFriend` | `uid: string, slot: number` | Entier 1 à 3, emplacement débloqué (R), possédé | 2 / s |
| `SetMount` | `uid: string` | Possédé, dans un enclos ; selle gagnée (record ≥ 1 200, §4.12) | 2 / s |
| `Ride` | `on: boolean` | Une monture existe ; rien de porté | 2 / s |
| `Leap` | `dirX: number, dirZ: number, tClient: number` | Finis, norme entre 0,5 et 1,5 ; recharge de 4 s écoulée (horloge du serveur) ; pas en portage ; `tClient` ramené dans [maintenant − 0,35 ; maintenant] → MoveCheck accorde un crédit de 12 studs sur 0,35 s, rétroactif jusqu'à 0,3 s, un au plus toutes les 4 s (§12.8) ; point d'atterrissage calculé par `LeapRules` ; capture tentée par le serveur à `tClient + 0,35 s` | 3 / s |
| `Catch` | `id: number, tClient: number` | Entier ; créature active ; attrapable par ce joueur (personnelle, mode Rush pour une fuite du Rush, pas le boopeur pendant les 6 premières secondes, recharge du Golden) ; `tClient` ramené dans [maintenant − 0,35 ; maintenant] ; distance à plat ≤ 6,5 entre `pos(tClient)` et la position validée du joueur à `tClient` (9,5 pour le propriétaire de la fuite) ; écart vertical depuis les pieds ≤ 8 ; `canAct` ; égalité : ordre d'arrivée (§12.5) | 6 / s |
| `BoopHold` | `ownerId: number, uid: string, holding: boolean` | Entiers et chaîne bornés ; ordre `RushRules` (§4.21.4) au début et à chaque tick (distance ≤ 8, propriétaire toujours en mode Rush, pas de « Pas ce joueur ») ; le serveur termine le boop lui-même à 2,5 s ou 5 s | 4 / s |
| `MegaPress` | `tClient: number` | MEGA actif, à ≤ 20 studs du centre, recharge de 0,4 s | 3 / s |
| `FeedPlop` | `holding: boolean` | À ≤ 8 studs à plat du bol, pas encore nourri aujourd'hui ; 2 s mesurées par le serveur | 2 / s |
| `GrandSplorch` | `film: boolean, flyer: string` | Plus gros ≥ objectif ; dans son ranch ; rien de porté ; aucun de ses squishies en fuite ; `flyer` possédé, dans un enclos ; maintien de 1,5 s mesuré côté client (geste). Vérifié **une seule fois**, à l'entrée dans la file : ensuite garanti (§4.15) | 1 / 2 s |
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

**Messages ajoutés par la v2.0** *(v2.0 : nouveau)*

| Remote (client → serveur) | Charge utile | Validation serveur | Débit max |
|---|---|---|---|
| `BuyUpgrade` | `id: string, mode: number, expectedLevel: number` | `id` dans `Config/Upgrades` ; `mode` ∈ {1, 10, 0 = Max} ; entier `expectedLevel` = niveau actuel (sinon refus « périmé », sans retour visible si l'instantané montre déjà ce niveau) ; famille ouverte (Record R, A, interrupteur) et pas au maximum ni au plafond de la boucle ; règlement du Pot, puis `n = min(demandé, payable, restant)` ; **somme exacte niveau par niveau** par `UpgradeMath.bulk` (pièces ou Confettis) ; **un seul bloc** ; refusé pendant l'application d'un prestige ; position non exigée (l'écran est gratuit pour tous) | 10 / s (seau à jetons) |
| `BuyTile` (v1.3) | Inchangé pour les dalles au sol | Même fonction serveur et même `UpgradeMath` que `BuyUpgrade` (`expectedLevel` pris au niveau actuel) | 10 / s |
| `GrandSplorch` (v1.3) | Inchangé | Sert aussi au Petit Splorch (r après la renaissance ≤ Record R ; depuis l'aperçu ou le maintien de 1,5 s sur la puce d'action spéciale, critique M16) : mêmes conditions d'entrée, appliqué tout de suite, hors file | 1 / 2 s |
| `JellyAscend` | `confirm: boolean` | `Prestige.ascendReady` (r ≥ condition, A < 60) ; dans son ranch, rien porté, aucun squishy en fuite ; **un seul prestige par joueur dans la file** ; vérifié une seule fois, à l'entrée dans la file | 1 / 5 s |
| `EquipCosmetic` (v1.3) | `kind` + `"palette"`, `"cushions"` ; `theme` accepte les 14 habillages | Cosmétique possédé (`Logic/Owned` : Record R, A, Atelier, Carnet, piste, saison, jalons géants ; chaque source derrière son interrupteur). **Pas de remote `SetRanchSkin`** (décision C2 du contrat) : l'habillage du ranch passe par `EquipCosmetic("theme", id)` | 2 / s |
| `PlaceDeco` | `item: number, slot: number` | Objet possédé (`Bitset`), emplacement 1 à 12 de la bonne taille ; 0 = retirer | 4 / s |
| `GiveHeart` | `ownerId: number` | Propriétaire présent, pas soi-même, pas bloqué (liste souple), 1 par ranch et par jour, 20 par jour | 2 / s |
| `MenuActivity` | — | Envoyée par le client à l'ouverture d'un panneau et pendant la navigation dans un menu (une au plus toutes les 20 s, décision du propriétaire du 6 novembre) ; acceptée seulement Plopettes ouvertes, profil v2, joueur prêt et vivant ; réveille seulement les Plopettes (sieste, §4.28) : jamais une récompense, une progression, ni une activité de la jauge ou du MEGA | 1 / 10 s |
| `SetPhotoMode` | `on: boolean` | Interrupteur du mode photo, joueur chargé ; état en mémoire et analytique seulement : le personnage reste **visible** des autres (N22), aucun avantage | 1 / s |
| `UiSeen` (v1.3) | + `"nextBuy"` | Puce « Prochain achat » apparue : `onboarding.nextBuyShown` une fois (profil v2) ; ne donne jamais rien | 2 / s |
| `ClientMetric` | `kind: string, value: number` | Faits que seul le client mesure : `upgradeTimeout`, `upgradeMode` (1, 10 ou 0 = Max) [écran Améliorations] ; `ascendPreview` (0 ouvert, 1 annulé, 2 confirmé), `ascendDeclined` (jours) [Jelly Ascend] ; `textScale` (facteur × 100), `styleFallback`, `visualBudget` [toujours] ; entier de 0 à 1 000 ; 20 par session ; compteurs de Diagnostics et analytique **seulement** (§16), jamais un changement du jeu | 1 / 5 s |
| `SetSetting` (v1.3) | + `haloOn: boolean` ; `emoteLeft` + les 6 emotes v2.0 possédées | Comme v1.3 | 4 / s |

| Remote (serveur → client) | Charge utile | Destinataires |
|---|---|---|
| `UpgradeResult` | `{ id, from, to, spent, currency ("coins" \| "confetti"), reason, snapshot }`, où `snapshot = { coins, confetti, levels, caps, version }` est **aussi** envoyé dans le correctif de données (l'écran ne lit que lui, §10.8 règle 6) | Le joueur |
| `HelperPress` | Liste groupée par tick de `{ helper, uid, tPress }` : le serveur choisit la cible et l'heure ; à `tPress`, il revérifie « prête depuis 3 s » et la règle des 12 studs, sinon il abandonne | Le joueur et les clients qui dessinent ce ranch en détail complet |
| `Celebrate` (v1.3) | + sortes `petitSplorch`, `ascend`, `tier`, `unlock`, `confetti` | Le joueur (et tous pour `ascend`) |
| Attributs répliqués du ranch | `BestR`, `Ascend`, `SplorchReady`, `AscendReady`, `PetitSplorchAt` (heure du serveur), `RanchSkin`, `Monuments`, `DecoPerso` | Tous |

Aucun `RemoteFunction` ne va du serveur vers le client. Les achats Robux passent par `MarketplaceService:Prompt…Purchase` côté client et `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur, sans remote du jeu.

**Serveur → client**

| Remote | Charge utile | Destinataires |
|---|---|---|
| `DataSnapshot`, `DataPatch` | Profil public, patchs groupés par image (repris) | Le joueur |
| `RanchSnapshot`, `RanchPatch` | §12.5 | Tous |
| `ChaseEvent` | §12.5 | Tous, ou un seul pour les créatures personnelles |
| `EventState` | `{ rush, mega, golden, moon, gauge (dont la fin de la sieste), boost, spectacleQueue (places et attentes prévues) }` | Tous, à chaque changement |
| `MegaBeat` | `{ points, target, presses }` | Tous, 4 Hz pendant le MEGA (non fiable : battement visuel) |
| `Fence` | `{ ranchSlot, uids }` (squishies à la clôture) | Tous, pendant le Rush et le pet-sitting |
| `BoopState` | `{ booperSlot, ownerSlot, uid, endsAt }` (maintien en cours) | Tous |
| `Banner` | `{ kind, args }` | Tous |
| `Feedback` | `{ key, vars, tone }` | Le joueur |
| `Celebrate` | `{ kind, data }` (naissance, fusion, combo, capture, Grand Splorch, palier, objectif) | Le joueur (et tous pour le Grand Splorch) |
| `EmoteShow` | `{ userId, kind }` | Tous |
| `ClapPrompt` | `{ heroId, endsAt }` | Les spectateurs qui ont la version complète du spectacle (au plus une fois toutes les 3 min, §4.15) ; le client ne l'affiche pas pendant une poursuite, un maintien ou une fenêtre |
| `ModePrompt` | — (carte du choix Rush / Cozy : envoyée une fois après 15:00 de jeu ; le client l'affiche au calme, §4.21.1) | Le joueur |
| `DiagnosticsSnapshot` | `{ server, clients, samples, today }` (20 Ko au plus, §12.11) | L'administrateur qui l'a demandé |

### 12.8 Anti-triche

| Menace | Parade |
|---|---|
| Vitesse, téléportation, bond sans recharge | **`MoveCheck` repris de Comet avec son budget d'action** : un « seau » de studs dont le plafond est la règle d'un tick (`vmax × dt × 1,5 + 4`), rempli à `vmax × 1,5` studs/s ; chaque position acceptée retire sa distance ; la dette passe d'un message à l'autre. Tant que la dette n'est pas remboursée, le joueur **ne peut pas agir** (attraper, booper, presser, encaisser le Pot, presser le MEGA). `vmax` = WalkSpeed serveur maximal des 0,5 dernières secondes (16, ou 22,4 en monture). **Bond** : un bond accordé ajoute un **crédit de 12 studs** sur 0,35 s, ajouté au plafond par tick, au budget d'action et à la fenêtre soutenue d'1 s ; il est **rétroactif** jusqu'à 0,3 s avant la réception du message `Leap` (les positions du bond et le message passent par des canaux différents et arrivent parfois dans le désordre), et refusé si le bond accordé précédent date de moins de 4 s (horloge du serveur) : une rafale de faux `Leap` n'apporte jamais plus de 12 studs par 4 s. Sans ce crédit, un bond de 12 studs en courant laissait une dette d'environ 4,8 studs, et le joueur ne pouvait plus attraper pendant 0,6 s, au moment exact où il appuyait sur □. **Monture** : à chaque montée et descente, le contrôle reçoit la hausse de la racine (`HipHeight` − valeur de base, jusqu'à 6) et la hauteur de saut de la selle ; la racine debout, le vol bas et l'altitude maximale suivent la hausse, et la montée permise par tick devient `max(12, √(2 × 196,2 × JumpHeight)) × dt × 1,5 + 4` : le saut de 13 studs de la selle géante monte de 6,2 studs au premier tick, au-dessus des 5,8 permis par la règle reprise de Comet. Une infraction **signale seulement** ; 3 en 5 s → retour à la dernière position valide (`PivotTo`), 3 s sans action, icône neutre « connexion instable » (jamais d'accusation). Gel réseau honnête jusqu'à 1,5 s toléré. Exemptions 3 s après une apparition ou un `PivotTo` du serveur |
| Vol, passe-muraille | Altitude > sol + 14 (+ la hausse de la monture, 4,3 à 6 studs, §4.12) pendant plus de 1,5 s, hors du plateau (r > 322) ou sous le sol → retour à la dernière position valide (règles de hauteur de Comet) |
| Bond truqué | La direction est bornée (norme 0,5-1,5) ; la longueur est fixée par le serveur (12 studs, raccourcie par les solides) ; la capture se calcule sur le point d'atterrissage du serveur, jamais sur une position envoyée |
| Entrer dans un ranch | Poussée hors du ranch à chaque tick (§6.3) ; position validée seulement |
| Debout sur un autre joueur | **Aucune collision entre personnages** (groupe de collision `Characters` qui ne se touche pas lui-même) : personne ne porte personne, personne ne bloque un portail (leçon du tour 5 de Comet) |
| Valeurs envoyées par le client | Aucune valeur économique acceptée. `tClient` des pressions, des captures et des bonds borné à 0,35 s dans le passé (§4.7, §12.5) ; comme un script peut alors viser le PERFECT à chaque fois, aucun classement ne compte les PERFECT (§6.9). Le type d'entrée et l'appareil sont seulement analytiques (aucun bonus selon l'appareil, leçon de Comet) |
| Rafales de remotes | Seau à jetons par action (§12.7) |
| Fermes de bébés (comptes complices) | Plafonds journaliers, taille ≤ 0,5 × le plus gros du receveur, mutation du bébé du Rush copiée seulement jusqu'à ×5 (sinon tirée), 1 boop par paire toutes les 30 min, recharge de 20 s, 2 fuites par ranch et par Rush, 4 par heure ; bébés des Grands Splorch plafonnés à Peu commun pour une espèce Épique+ (§4.15) |
| Croissance « Héros » à deux comptes | +1 h de croissance du ranch (et +30 min pour un retour seul), une fois par squishy et par jour, au lieu d'un pourcentage qui se cumulait (§4.21.3) |
| Pet-sitting avec un second compte | 2 s de revenu par pression, 100 pressions récompensées par jour (et 100 reçues par propriétaire) ; « Plus serviable » compte 20 pressions au plus par ami et par jour (§6.4) |
| Robots qui pressent | Rien à gagner hors de son propre ranch ; débit borné ; récompenses en secondes de revenu (un robot ne crée pas de valeur infinie) |
| Classements | Exclusion après 10 retours forcés en 10 min, **jusqu'à la fin de la semaine suivante** (`flags.lbBanUntil`), jamais à vie (question laissée ouverte par Comet, tranchée ici). Valeurs entières codées (score, premier arrivé, nom caché), jamais une taille (§6.9) |
| Lecture de secrets | Administrateurs LiveOps et réglages anti-triche dans `ServerScriptService` seulement |
| Achats | `ProcessReceipt` unique et idempotent ; passes vérifiés à l'arrivée et à l'achat, vérifications bornées en débit (repris) |
| Faux rapports d'erreur (Diagnostics) | Plafonds par joueur et par clé, tailles bornées, noms nettoyés ; un rapport ne change jamais rien au jeu et n'est lu que par les administrateurs ; un joueur qui dépasse ses plafonds est simplement ignoré jusqu'à la fin de la session (§12.11) |
| Duplication | Aucun échange au lancement ; toutes les mutations de collection se font sur le profil d'un seul joueur, sous verrou de session. Un bébé est une **création** du serveur, jamais un déplacement entre profils |

### 12.9 Budgets de performance (console la plus faible : PS4 et Xbox One) *(v2.0 : modifié)*

Appareil de référence : **PS4 et Xbox One de base**, les consoles les plus faibles où Roblox tourne. Les mesures se font sur une vraie console : Studio ne mesure ni le processeur ni la mémoire d'une console. La PS5, les Xbox Series et les PC visent 60 images par seconde.

| Ressource | Budget |
|---|---|
| Images par seconde | **30 stables** sur PS4 et Xbox One avec 16 joueurs, 384 squishies affichables et un Rush complet ; 60 sur PS5, Xbox Series et PC |
| Pièces de la carte | ≤ 4 500 (prévu ≈ 4 300), toutes ancrées |
| Instances côté client | ≤ 15 000 dans le `workspace` (carte, squishies, effets ; *v2.0* : + ≈ 2 040 pièces de décor dessinées par le client, §11.5) ; **≤ 4 150 objets d'interface** sur une séance normale du jeu v2.0 (mesuré au lot I : 1 506 au chargement, écran Améliorations compris ; 4 148 au plus haut quand chaque panneau du rail a été ouvert une fois, chacun gardé une fois construit ; 4 631 si tout est construit, Diagnostics et garde-robe compris), **dont l'écran Améliorations ≤ 1 400** (v2.0). *Pourquoi 4 150 et plus 3 000* : l'écran Améliorations seul fait ≤ 1 400 et il est construit une fois ; les panneaux de la v1.3 et de la v2.0 sont construits à la première ouverture et gardés (tout panneau garde des liaisons et des références à ses objets : le relâcher à la fermeture demande un démontage propre par panneau, pas fait au lancement, à mesurer d'abord sur une vraie console) |
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

### 12.10 Stratégie qualité : « zéro bug » *(v2.0 : modifié)*

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
| Maintien de boop / du bol | 2,5 ou 5 s + 0,5 s / 2 s + 0,5 s | Effet, ou annulation |
| Attente sur une dalle | 0,6 s ; sortie de la dalle, portage ou autre maintien | Achat, ou annulation sans rien dépenser (§4.6) |
| Bond | 0,35 s (crédit de déplacement : 0,35 s, un toutes les 4 s) | Fin du bond (capture tentée une seule fois) |
| Créature en fuite / fuite du Rush / Wild Wobbler / Golden / démonstration | 20 / 25 / 25 / 30 / 20 s | Retour, éclatement ou disparition, même chez un client qui a raté le message de fin |
| BOOP RUSH / MEGA SQUISH | 90 s (+ 25 s pour les fuites en cours) / 65 s | Fin de phase par `EventClock` |
| File des Grands Splorch | Son tour (place × 20 s + reste du grand spectacle en cours, recalculé ; coupure dure à 8 min) ; départ du joueur | Spectacle, ou place rendue sans rien remettre à zéro (§4.15) |
| Spectacle (Grand Splorch, danse de Big Plop) | 7,5 s / 8 s, coupure dure à 10 s | Fin du spectacle, file suivante |
| Squish Party / Wobble Party / boost personnel | 10 min par achat (prolongée par un achat croisé) / 5 min / son minuteur | Fin du boost ; à la fermeture du serveur, minutes de fête non jouées rendues aux acheteurs en boost personnel (§8.3) |
| Sieste de Big Plop (jauge) | 20 min | Jauge active ; fête si elle est pleine (§4.23) |
| Carte du choix Rush / Cozy | 20 s | Cozy |
| Cartes non bloquantes | 8 s | Rangées dans la pastille « ! » |
| Fenêtre d'achat ou d'invitation de Roblox | 60 s de sélection tenue | Sélection rendue de force (§10.6) |
| Étape de l'accueil | 90 s | Consigne rangée, l'accueil continue (§3) |
| Cible fixée par un clic | 4 s | Retour au choix automatique |
| Fenêtre d'applaudissement | 8 s | Puce retirée |
| *(v2.0)* Garde d'entrée (ouverture d'une fenêtre ; changement sous le focus) | Relâchement de ✕ vu, puis 0,3 s (0,4 s) | Appuis acceptés |
| *(v2.0)* Maintien ×10 / Max ou d'une ligne de l'Atelier | 0,6 s | Achat, ou annulation sans rien dépenser (« Maintiens ✕ … ») |
| *(v2.0)* Réponse du serveur à un achat | **3 s** | Ligne remise à l'état du serveur, « Réessaie » |
| *(v2.0)* Petit Splorch (animation chez le propriétaire et ses 2 voisins) | 2,5 s depuis `PetitSplorchAt`, coupure dure à 4 s | État final posé |
| *(v2.0)* Maintien de la Jelly Ascend | 3 s | Carte de confirmation |
| *(v2.0)* Carte « Prêt à monter ? » | 20 s | Fermée, rien ne change |
| *(v2.0)* File (Jelly Ascend) | Comme le Grand Splorch (coupure à 8 min) ; départ du joueur | Spectacle, ou place rendue **sans rien remettre à zéro** |
| *(v2.0)* Spectacle de la Jelly Ascend | 10 s, coupure dure à 12 s | Fin, file suivante |
| *(v2.0)* Chantier de Big Plop | 4 s, coupure dure à 6 s | Élément posé ; carte si interrompu |
| *(v2.0)* Plopette en route (`moving`) | Jusqu'à `tPress`, **3 s au plus** | Pression si tout est encore vrai, sinon abandon et nouvelle cible |
| *(v2.0)* Plopette (`idle`, `nap`, `paused`) | Sieste après 5 min sans entrée ; pause pendant son Grand Splorch ou son Ascension | Réveil à la première entrée |
| *(v2.0)* Cascade de construction en attente (écran ouvert) | 10 constructions ou 10 s | État final posé sans animation |
| *(v2.0)* Saynète d'un squishy | 3 s au plus | Retour à sa place et à « Content » |

**Les 10 couches de tests** (toutes lancées par `./scripts/check.sh`, sauf la couche i, qui attend la clé de l'API Open Cloud) :

| Couche | Ce qui est prouvé | Où |
|---|---|---|
| **a. Modules purs : cas exacts et propriétés** | Chaque module de `Shared/Logic` et `Util/Format` : les valeurs exactes de ce GDD **et** des propriétés vérifiées sur des milliers d'entrées tirées au hasard avec une graine fixe : jamais `NaN` ni négatif, monotonie, tables qui somment à 100 %, nombre de squishies conservé par une fusion (2 → 1), chemins jamais hors du graphe ni dans un ranch, même résultat côté client et côté serveur. Une entrée bizarre (`NaN`, ±inf, 1e308, −0) donne un résultat sûr, jamais une erreur | `Format`, `SizeScale`, `Formulas`, `Odds`, `FusionRules`, `RushRules`, `QuestRules`, `MegaRules`, `EventClock`, `SeededPath`, `PressTiming`, `ZoneRules`, `LeapRules`, `StateTimeouts`, `DiagRules` (`*.spec` et `Props_*.spec`) |
| **b. Chaque remote attaqué** | Chaque message du §12.7 reçoit des charges hostiles : mauvais types, `nil`, `NaN`, ±inf, nombres énormes, chaînes de 100 000 caractères, UTF-8 invalide, tables profondes, mixtes ou à trous, uid d'un autre joueur, rafales de 1 000 messages par seconde. Attendu : **aucune mutation, aucune erreur**, au plus un `Feedback` neutre, et des seaux à jetons qui coupent au bon débit | `Remotes.spec`, `RateLimit.spec` |
| **c. 16 robots, longue durée** | Un serveur complet avec 16 robots qui jouent (pressent, achètent, fusionnent, boopent, poursuivent, partent, reviennent, meurent, changent de mode) pendant **6 h de temps simulé** (horloge accélérée). À **chaque tick**, des invariants : aucune monnaie négative ou `NaN` ; chaque squishy existe une fois, à un seul endroit, chez un seul propriétaire ; aucun état plus vieux que son délai ; plafonds respectés ; instances et connexions stables après la mise en route (± 5 %) ; tick dans son budget ; **aucune erreur ni aucun avertissement**. Plus le démarrage et la fermeture (`BindToClose`) à 16 joueurs | `Soak.spec`, `Boot.spec` |
| **d. Client complet, profil console, 3 résolutions** | Une partie serveur enregistrée est rejouée dans le vrai client, profil console (`IsTenFootInterface` vrai, manette), en **1920 × 1080, 3840 × 2160 et 1280 × 720**, en anglais puis en français. Un robot parcourt tous les écrans avec **la croix, ✕ et ○ seulement** (depuis le jeu, croix ↓ ouvre le menu) : chaque écran du §10.3 est atteint ; ○ revient toujours au niveau précédent, puis au jeu ; la sélection n'est jamais vide dans une fenêtre, jamais hors de la fenêtre active, jamais posée en jeu. À chaque étape : aucun chevauchement, aucun texte coupé ni sous 28 px TV, rien hors de la zone sûre, aucune touche du jeu active derrière une fenêtre, glyphes PlayStation partout (aucune lettre « X » ou « LB »), chaque texte du monde (étiquettes des dalles, consignes, « +N ») d'une taille projetée ≥ 28 px TV à 20 studs. Même parcours au clavier-souris | `ClientReplay.spec`, `Console_*.spec`, `Layout.spec` |
| **e. Données en désordre** | Pannes de DataStore injectées (erreurs, délais de 10 s, quotas), verrou de session entre 2 et 3 serveurs simulés, retour immédiat sur un autre serveur, fermeture avec 16 joueurs et un magasin lent, migrations depuis les sauvegardes-témoins, profils abîmés (`NaN`, champs manquants, tableaux à trous, uid inconnus) réparés par `reconcile`, reçu rejoué, achat pendant une panne (accordé seulement après une sauvegarde réussie) | `DataChaos.spec`, `DataService.spec`, `MonetizationService.spec`, `Schema.spec` |
| **f. Rythme de l'économie** | Simulation du §4.24 : 50 joueurs × 28 jours × 3 tailles de serveur (4, 8, 16) dans `check.sh`, 200 joueurs en lancement manuel ; moteur par événements ; jalons de rythme **et** de santé de l'économie (Tapis 12, pièces perdues, part des pressions, Grands Splorch prêts à la connexion, temps en ×2), **porte bloquante** | `EconomyPacing.spec` |
| **g. Contre-audit anti-triche** (« red team ») | Un fichier par menace, écrit comme une attaque : capture téléportée ou de loin, capture avec un `tClient` truqué (dans le futur, trop ancien, `NaN`), capture de sa propre fuite avant 6 s, capture d'une créature personnelle d'un autre, bond sans recharge ou de direction `NaN`, rafale de faux `Leap` (jamais plus de 12 studs par 4 s) ; ferme de bébés et de croissance « Héros » à deux comptes, pet-sitting par un second compte ; boop à travers le mur, de loin, de son propre squishy, d'un Meilleur Ami, contournement de « Pas ce joueur » et des paires ; entrée dans un ranch (monture, saut, bond, téléportation, rester dans le portail) ; reçu rejoué, achat avant le chargement du profil ou pendant un Grand Splorch ; pressions chez un autre, `tClient` truqué ; deux messages contraires dans la même image (vendre pendant une fusion) | `RedTeam_Chase.spec`, `RedTeam_Boop.spec`, `RedTeam_Fence.spec`, `RedTeam_Purchase.spec`, `RedTeam_Press.spec`, `MoveCheck.spec` |
| **h. Règle « zéro trace »** | Le harnais écoute `warn`, `error`, `ScriptContext.Error` et `LogService.MessageOut` pendant **chaque** spec : toute erreur ou tout avertissement imprévu la fait échouer. Un avertissement attendu doit être déclaré dans la spec (`expectWarning(motif)`), et la spec échoue s'il n'arrive pas | `tests/harness` (toutes les specs) |
| **i. Vrai moteur Roblox** (prêt, lancé plus tard) | `tools/opencloud/` : un script Lune construit la place avec Rojo, la publie comme nouvelle version d'une **place de test privée** (API Open Cloud *Place Publishing*), lance la suite des tests serveur **dans de vrais serveurs Roblox** par l'API Open Cloud *Luau Execution* (`luau-execution-session-tasks`), récupère les journaux et échoue si un test échoue ou si une erreur ou un avertissement apparaît. Il tournera dès que le propriétaire fournira une clé d'API et l'accès réseau. Plus les listes de tests manuels dans Studio et sur une vraie PS5 (§18) | `tools/opencloud/run-server-tests.luau`, §18 |
| **j. Diagnostics en ligne** | Ce qui échappe à tout cela est compté en ligne et montré aux administrateurs (§12.11). Chaque erreur vue en ligne devient d'abord un test qui la reproduit, puis une correction | `DiagnosticsService`, `Diagnostics.spec` |

S'ajoutent les specs de services sur un serveur simulé (`Economy`, `Squishy`, `Splorch`, `Quest`, `Rush`, `Chase`, `Mega`) — dont, pour `Chase`, des captures à 0, 100 et 250 ms de latence sur une créature qui fuit (au moins 95 % acceptées quand le client la voyait à 5 studs ou moins, aucune au-delà de 7) et un bond suivi d'une capture au tick suivant (acceptée), et pour `MoveCheck`, un cavalier à chaque selle qui court et saute 60 s sans aucune infraction —, `WorldLayout.spec` (règle de plan du §11.2), `WorldBuild.spec` (carte construite : tout ancré, `CanTouch = false`, solides seulement dans la liste du §11.1, aucune fente entre solides, budget de pièces) et `Contract.spec` (parité EN/FR, provenance de chaque son, identifiants de monétisation à 0 = articles cachés). Les outils repris de Comet restent (`harness/Wire` pour les règles des messages réseau, `ApiAudit` pour les API Roblox).

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

### 12.12 Budget de lignes et ligne de coupe *(v2.0 : modifié)*

| Bloc | Estimation |
|---|---|
| Base reprise de Comet (données, monétisation, réseau, utilitaires, console, UI de base) | ≈ 4 000 lignes (à adapter) |
| Shared (logique et configuration, dont `ZoneRules`, `LeapRules`, `StateTimeouts`, `DiagRules`) | ≈ 2 800 |
| Serveur (15 services, dont `DiagnosticsService`) | ≈ 4 900 |
| Client (rendu, contrôleurs, HUD télé, panneaux, `Prompt`, `FocusGuard`, `ErrorReporter`) | ≈ 5 100 |
| **Total jeu au premier passage** | **≈ 12 800 nouvelles lignes** (hors base reprise et hors tests ; prévoir beaucoup plus après la QA) |
| *(v2.0)* Jeu complet (améliorations et écran, renaissance à 2 couches, Plopettes, visuels, rétention) | ≈ 9 000 lignes de jeu et ≈ 7 000 de tests en plus (≈ 78 jours de développement estimés par docs/09 §8.1, dont ≈ 8 pour la Jelly Ascend) ; découpage en paquets parallèles dans `packages-proposal.md` |
| Tests et outils (10 couches du §12.10 : propriétés, attaques des remotes, robots de longue durée, parcours console, données en désordre, red team, Open Cloud) | ≈ 9 000 lignes en plus (le harnais de Comet est repris) |

Le retrait du téléphone économise environ 1 200 lignes d'interface tactile (bouton Action, Prendre, Bondir, Monter, Emote, désignation au doigt, colonnes du petit écran) et un jeu entier de tests : ce temps passe dans les tests du §12.10.

**Ligne de coupe** (retirée dans cet ordre si le calendrier dérape) : aperçu 3D des tenues (remplacé par une image fixe dessinée en Frames), animation de la carte du choix (remplacée par 3 images fixes), classements mondiaux (on garde le tableau du serveur), badges d'étoiles du Squishydex, applaudissements, pet-sitting, clips automatiques, fanfares de records, squishies visibles dans la Prairie des copains (relâcher seulement par le menu). **Jamais coupé** : grandir, presser et PERFECT, Cuve, Bassin et combos, créatures en fuite et Golden, monture, BOOP RUSH avec ses protections, son interrupteur et le mode Cozy immédiat, Wild Wobblers (dont le personnel), MEGA SQUISH, jauge, Grand Splorch et Étagère, Jelly Moon, Nourrir Plop, objectifs, mode Cozy, couche console (disposition télé, glyphes, règle des 3 touches, `FocusGuard`, vibrations, sons d'interface), délais de tous les états, Diagnostics, et les 10 couches de tests. **Si quelque chose doit céder, c'est le contenu, jamais la qualité** : on coupe une fonction de la liste ci-dessus plutôt que de publier un bug connu.

---

## 13. Sécurité des enfants *(v2.0 : modifié)*

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
| **Argent** | Aucun hasard payant, aucune chance achetable (même avec des pièces), aucune pub vidéo récompensée, aucun faux minuteur, aucune proposition d'achat dans les 10 premières minutes, prix clairs, `PolicyService` respecté, aucune monnaie vendue au lancement : des Robux ne disparaissent jamais dans un Grand Splorch (§8.1, §8.3) |
| **Pas de piège de conception** | Aucun chiffre (part en mode Rush, ventes) ne justifie de changer le choix par défaut, l'ordre ou la taille des boutons d'un choix (§16.4) |
| **Pause** | Carte « Plop a sommeil » après 60 min, sans pénalité ni récompense pour rester (§4.20) |
| **Partage** | Clips seulement si `IsContentSharingAllowed` ; le jeu ne partage jamais tout seul (§9.5) |
| **Mesure** | Départs dans les 2 min après un premier boop subi, comparés aux autres joueurs, dès le premier jour (§16.3, action au §16.4) |
| **Diagnostics sans données personnelles** | Les rapports d'erreur ne gardent ni nom ni identifiant (noms remplacés par « <joueur> »), sont plafonnés, ne changent rien au jeu et ne sont visibles que des administrateurs (§12.11) |
| **Cœurs sans popularité** *(v2.0)* | Un cœur par ranch et par jour (20 par jour), notification **privée** au propriétaire, **aucun compteur public**, joueurs bloqués exclus ; jumelles en lecture seule, sans texte |
| **Rien de la v2.0 à acheter** *(v2.0)* | Confettis, Atelier, Ascension, Plopettes, Monuments, piste de la semaine : tout se gagne ; aucune piste payante, jamais |
| **Pas de ferme à Plopettes** *(v2.0)* | Les Plopettes ne travaillent que si le propriétaire est là, font la sieste après 5 min sans intention acceptée ni navigation dans un menu (un stick calé ne compte pas) et ne pressent jamais chez un autre (pas de pet-sitting par aide) |
| **Rien n'est perdu à l'Ascension** *(v2.0)* | Aperçu avec 6 icônes « gardé », maintien de 3 s, carte de confirmation (focus sur « Oui » après un maintien volontaire de 3 s, garde de 0,6 s et relâchement de ✕ exigé ; critique M1), Souvenir de gelée pour remonter vite, textes vrais et chiffrés |
| **Un jeu qui ne casse pas** | Un enfant ne reste jamais bloqué (délai sur chaque état, ○ qui revient toujours en arrière), ne perd jamais un squishy ou un achat à cause d'un bug (sauvegarde sûre, opérations idempotentes), et ne voit jamais un écran d'erreur (§12.10) |

---

## 14. Accessibilité

| Besoin | Réponse |
|---|---|
| Daltonisme | Rareté = couleur **et** forme de l'aura (§4.4) ; mutation = matériau **et** nom ; squishies en fuite = anneau **et** contour ; ranch boopable = badge « boop » (couleur **et** icône) ; jumeaux = cœur (forme) |
| Sensibilité au mouvement | Mouvement réduit (§9.1) ; la caméra ne bouge jamais toute seule ; jamais plus de 3 changements de couleur par seconde (Glitch) ; aucun flash répété |
| Lecture difficile, jeunes enfants | Aucun tutoriel écrit ; icônes, gestes de Big Plop, 4 mots au plus par consigne ; un bouton d'action principal ; aperçu du Grand Splorch en 3 tuiles |
| Jeu sans son | Tout retour est d'abord visuel ; musique et effets réglables séparément |
| Motricité | **Aucun appui simultané**, aucun clic de stick, aucune combinaison : chaque action tient sur une touche (§10.4) ; maintiens limités au boop (2,5 s), au bol (2 s), à la confirmation du Grand Splorch et du Petit Splorch (1,5 s), à la Jelly Ascend (3 s, puis une carte de confirmation) et à tout achat de l'écran Améliorations et de l'Atelier (0,6 s, ×1, ×10 et Max) *(v2.0 révisé, critique m5)* ; achat d'une dalle en restant 0,6 s dessus, sans maintenir de touche ; **aucun geste précis obligatoire** (le PERFECT est un bonus, jamais un échec) ; fusion au menu sans glisser-déposer et « Tout fusionner » ; un seul bouton pour attraper (bond avec capture à l'atterrissage) ; PERFECT décalé pour le retard des télés ; la cible est choisie par le jeu (pas besoin de viser) ; tout le menu se pilote avec la croix, ✕ et ○ |
| Stress de la compétition | Mode Cozy (par défaut, immédiat, aussi rentable), serveurs privés en Cozy, bouclier débutant, « Pas ce joueur », Golden « course amicale », classements qui montrent d'abord ma place sur le serveur |
| Appareils modestes | Graphismes légers, qualité adaptative, niveaux de détail, budgets du §12.9 (PS4 et Xbox One) |
| Téléviseur et manette | Disposition télé unique, proportionnelle (référence 1920 × 1080), textes ≥ 28 px TV (32 pour le texte courant), contraste fort, zone sûre de 5 %, glyphes de l'appareil, tout à la manette sans curseur, focus toujours visible et jamais perdu, vibrations modérées et désactivables, sons d'interface, pas de fenêtre de chat (§10) |

---

## 15. Localisation (anglais et français) *(v2.0 : modifié)*

- **Détection** : `Localization.languageFor(player.LocaleId)` (module repris) : `fr-*` → français, sinon anglais. Le réglage « Langue » (Auto / English / Français) passe avant.
- **Toutes les chaînes** dans `Shared/Localization/Strings.luau`, clés `domaine.nom`, variables `{n}`. Anglais **et** français écrits à la main ; un test vérifie la parité des clés et des variables (`Contract.spec`). Les autres langues : affichage anglais avec `AutoLocalize = true` (traduction automatique de Roblox) ; l'interface très illustrée limite la dépendance au texte.
- **Consignes et glyphes** : une consigne ne cite jamais une touche dans une phrase ; le glyphe est posé **à côté** d'un mot court (□ + « Presser »), ce qui marche dans les deux langues et sur toutes les manettes.
- **Nombres** : §4.2 (mêmes suffixes internationaux K, M, B, T… dans les deux langues ; virgule et espace fine en français ; mot entier français dans la fiche et l'info-bulle).
- **Longueur** : le français est ≈ 25 % plus long. *(v2.0 : modifié)* `TextSize` fixe et `UITextSizeConstraint.MaxTextSize` (plus de `TextScaled`, §10.1) ; chaque écran est vérifié en français et en anglais en 1280 × 720, 1920 × 1080 et 3840 × 2160, à la taille de texte Medium **et** Largest, sans passer sous 28 px TV (`TextFit_all.spec`, §12.10, couche d ; leçon de Comet : prévoir des libellés français courts dès le départ). Toutes les clés nouvelles de la v2.0 (écran Améliorations, Atelier, Ascension, Plopettes, piste, Carnet, habillages, Déco perso, personnalités) sont écrites en anglais **et** en français avant le code et ajoutées à `TextFitPending` ; les libellés courts de l'écran sont au §10.7.7.

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

Tout passe par `Server/Util/Analytics` (repris, appels protégés par `pcall`). **Budget** : Roblox accepte au plus `120 + 20 × joueurs` requêtes d'analytique par minute et par serveur ; au-delà, les événements sont perdus, y compris `PostBoopQuit`, l'indicateur de sécurité n° 1. Le jeu vise **10 requêtes au plus par joueur et par minute** (vérifié par `Analytics.spec` sur une partie simulée de 16 joueurs). Trois champs personnalisés pour segmenter : `device` (console manette / PC manette / PC clavier-souris ; tactile inattendu compté à part), `serverBand` (1-5, 6-10, 11-16 joueurs), `sessionBand` (1re session, 2-5, 6 et plus).

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

### 16.2 Économie (`LogEconomyEvent`) *(v2.0 : modifié)*

| Flux | Monnaie | `itemSku` | Type de transaction |
|---|---|---|---|
| Source | Coins | `Pot`, `Press`, `Combo`, `Sell`, `Offline`, `Golden`, `Mega`, `RushHero`, `RushReturn`, `RushNear`, `SplorchGift`, `PetSit`, `Clap`, `Objective_<niveau>` (facile, moyen, difficile) | Gameplay, TimedReward, Onboarding |
| Puits | Coins | `Tile_<dalle>` (snack, decor, pens), `CozyBed` | Shop |
| Source *(v2.0)* | Coins | `Helper`, `SplorchGiftOwn` (cadeau du Splorch), `StarRain` | Gameplay |
| Puits *(v2.0)* | Coins | `Upgrade_<famille>` (star, gloves, school, monument) | Shop |
| Source *(v2.0)* | Confetti | `GrandSplorch`, `PetitSplorch`, `Skipped`, `Ascend`, `Regain`, `RecordBonus`, `FullPen`, `Mastery` (Gameplay) ; `WeeklyTrack` (TimedReward) | Gameplay, TimedReward |
| Puits *(v2.0)* | Confetti | `Workshop_<ligne>` (lignes de l'Atelier), `Fun_<ligne>` (« Pour le plaisir » : `palettes`, `saddle`, `trail`, `emote`, `pennants`, `title`, `decoShop`) | Shop |

**Toutes les sources et tous les puits sont cumulés par joueur et par tranche de 5 min** : un événement par `itemSku` et par tranche (une pression par seconde aurait fait 180 événements par minute et par joueur). Les montants et le solde sont exprimés en **secondes de revenu** du joueur au moment de l'envoi (lisibles à tous les niveaux, alors que les pièces dépassent 1e19) ; *(v2.0)* les Confettis restent en **unités brutes** (solde = Confettis en poche), et le niveau des dalles n'est pas dans l'`itemSku` (au-delà de 100 `itemSku`, Roblox range le reste dans « Other ») : il est mesuré par `TileLevelAtSplorch` (§16.3). Aucun achat Robux ne donne de pièces au lancement (§8.3).

### 16.3 Événements personnalisés (`LogCustomEvent`) *(v2.0 : modifié)*

| Événement | Valeur | Question |
|---|---|---|
| `RushModeChosen` | 1 Rush / 0 Cozy / −1 sans réponse | Observation seulement, jamais un objectif (§16.4) |
| `ModeAtSessionEnd` | 1 Rush / 0 Cozy | Comparer le retour J1 des joueurs Rush et Cozy : le Rush est-il un plaisir ? |
| `CozyAfterBoop` | 1 si le joueur passe en Cozy dans les 2 min après un boop subi | Le boop fait-il fuir vers le Cozy ? |
| `RefuseBooper` | 1 par « Pas ce joueur » | Y a-t-il du harcèlement ciblé ? |
| `AscendDeclined` *(v2.0 révisé, critique M1)* | 1 par aperçu de l'Ascension fermé sans la faire (« Plus tard », ○ ou délai de 20 s) ; valeur = jours depuis qu'elle est prête | Les enfants refusent-ils l'Ascension ? (sans elle, le jeu se creuse, §4.27) |
| `FirstBoopReceived` | Secondes de jeu cumulé | Quand le premier boop arrive-t-il ? |
| `PostBoopQuit` | Secondes entre le premier boop subi et le départ (si < 120) | **Indicateur de frustration n° 1** |
| `QuitBaseline` | 1 par départ d'un joueur qui n'a pas été boopé dans les 2 dernières min (même tranche de temps de jeu) | Référence pour comparer `PostBoopQuit` |
| `BoopDone`, `EscapeOutcome` | 1 ; 0 propriétaire / 1 autre / 2 personne | Équilibre de la poursuite (cible : propriétaire ≥ 25 %, personne ≤ 20 %) |
| `RushCatchByInput` | 1 par capture, segmenté par `device` | La manette est-elle désavantagée face à la souris ? |
| `MegaResult` | 1 réussite / 0 échec, avec N (joueurs actifs) et le nombre de participants | Calibrage de l'objectif |
| `GaugeFilled` | Minutes depuis la dernière fois (sieste comprise) | Calibrage de la jauge |
| `SplorchReached` | R, minutes depuis le précédent, et 1 s'il était déjà prêt à la connexion | Rythme réel contre §4.24 ; le hors ligne fait-il le prestige ? |
| `TileLevelAtSplorch` | Niveau du Tapis et nombre de décorations au Grand Splorch, avec R | Les dalles gardent-elles leur sens à chaque boucle (§4.6) ? |
| `BoostShare` | Part de la session passée en ×2 (au départ) | Le ×2 reste-t-il un moment (cible ≈ 30 %, §4.24) ? |
| `ComboLength` | n, et 1 si « Tout fusionner » | Les combos sont-ils compris ? |
| `ObjectivesAllDone` | Minutes de session au 3e objectif terminé | Les objectifs sont-ils faisables ? |
| `SplorchCoinsLost` | Pièces perdues au Grand Splorch, en multiples du prix du Tapis 12 de la boucle | L'inflation des pièces revient-elle (cible ≈ 3, §4.24) ? |
| `HatchRarity`, `MutationGot` | Rareté ; mutation | Tables réelles contre affichées |
| `RideStart` | Secondes de jeu | La monture est-elle trouvée ? |
| `PetSitPress`, `FriendsOnServer` | 1 ; nombre d'amis | Jeu entre amis |
| `ShopOpened`, `PolicyPaidRandomRestricted` | 1 | Fréquentation de la Boutique ; part des joueurs concernés par `ArePaidRandomItemsRestricted` (aucun article n'est caché pour eux, §8.1 n° 9) |
| `MoveViolation` | Nombre d'infractions dans la session | Faux positifs de l'anti-triche |
| `ServerFullKick` | 1 | Taille du serveur mal réglée ? |
| `SleepyCardShown` | 60 ou 120 | Sessions très longues |
| `SessionLength` | Minutes (au départ) | Durée de session |
| `ServerError`, `ClientError` | Nombre par clé d'erreur (une fois par clé et par 5 min, §12.11) | Y a-t-il des bugs en ligne ? |
| `FocusRescued` | 1 par sélection rendue par `FocusGuard` (§10.6), avec l'écran | La navigation à la manette a-t-elle un trou ? |
| `StateTimedOut` | 1 par état fermé par son délai alors qu'il aurait dû finir seul, avec le nom de l'état | Un flux reste-t-il bloqué ? |
| `QualityReduced` | 1 quand la qualité adaptative descend, avec l'appareil | La console la plus faible tient-elle le budget ? |
| `TouchDeviceJoined` | 1 | Un appareil tactile arrive-t-il malgré les réglages ? |
| `Upgrade_<famille>` *(v2.0)* | Niveaux achetés (cumulés par tranche de 5 min) | Chaque famille est-elle achetée ? |
| `UpgradeMode` *(v2.0)* | 1 par choix de mode, champ `mode` : x1 / x10 / max (envoyé par le client, cumulé par tranche) | Le mode Max est-il compris (test M14) ? |
| `WorkshopBuy_<ligne>` *(v2.0)* | Niveaux achetés, champ `level` = niveau atteint (cumulés par tranche) | Quelles lignes de l'Atelier d'abord ? |
| `ConfettiEarned` *(v2.0)* | Nombre, champ `source` (itemSku du §16.2), cumulé par tranche et par source | Les Confettis arrivent-ils au rythme du §4.26 ? |
| `UpgradeTimeout`, `UpgradeStale` *(v2.0)* | 1 par réponse manquée en 3 s (client) / par refus périmé (serveur), cumulés par tranche | Le réseau fait-il échouer des achats ? |
| `NextGoalGap` *(v2.0)* | Secondes de jeu passées plus de 3 min de jeu après le dernier achat ou but (cumulées par tranche ; une seconde compte si le joueur a fait une intention acceptée, menus compris, dans les 5 dernières minutes) | Le joueur a-t-il toujours un but proche (§4.24, temps « sans but ») ? |
| `HelperCoinsShare` *(v2.0)* | Part des Plopettes dans les pièces gagnées en jeu, en % (une décimale), une par tranche de 5 min où elles ont rapporté | Cible 5-15 % (§4.28) |
| `RanchTierReached` *(v2.0)* | Palier (1 à 6), champ `bestR` | Rythme des paliers de ranch |
| `AscendPreview` *(v2.0)* | 1 par étape de l'aperçu, champ `step` : opened / cancelled / confirmed (envoyé par le client, cumulé par tranche) | L'Ascension fait-elle peur ? |
| `AscendDone` *(v2.0)* | A, r, jours depuis la précédente | Rythme réel contre §4.24 |
| `PetitSplorch` *(v2.0)* | 1, avec la durée de la boucle | Les remontées vont-elles vite ? |
| `WeeklyTrackTier` *(v2.0)* | Palier | La piste est-elle atteignable ? |
| `TextScaleMeasured` *(v2.0)* | Facteur de taille du texte mesuré par le client × 100 | Les textes tiennent-ils sur la vraie console (§12.9) ? |
| `PhotoMode` *(v2.0)* | Entrées en mode photo (cumulées) | Le mode photo sert-il ? |

### 16.4 Seuils d'alerte et actions (par la configuration, sans nouvelle version) *(v2.0 : modifié)*

| Signal | Seuil | Action |
|---|---|---|
| `PostBoopQuit` comparé à `QuitBaseline` | > 1,5 fois après une semaine de mesures (seuil à confirmer avec ces mesures) | Premier boop subi seulement après 30 min de jeu (bouclier allongé), puis si besoin `Features.BoopRush = "events"`. Le Grand Splorch porte alors le côté viral. Plan B : les mécaniques de Stack a Squishy (jury §9) |
| Part en mode Rush | — | **Aucune action** : chiffre observé seulement. Règle écrite : on ne change jamais le choix par défaut, l'ordre ni la taille des boutons pour le faire monter |
| Retour J1 des joueurs Rush comparé aux Cozy | < 0,8 fois | Revoir la poursuite et les protections (rayon, vitesse, plafonds), jamais la carte du choix |
| `EscapeOutcome` | propriétaire < 25 % ou personne > 20 % | Verrou du boopeur 6 → 8 s ; rayon du propriétaire 8 → 9 ; durée de fuite 25 → 22 s |
| `ObjectivesAllDone` | < 85 % des sessions de 30 min finissent les 3 | Retirer ou assouplir l'objectif le moins fini (règle « Proposé si ») |
| Réussite du MEGA | < 65 % ou > 92 % | Coefficient 50 par joueur ± 10 |
| Médiane du premier Grand Splorch | hors 11-16 min | `Balance.Splorch.Targets[1]` |
| `SplorchReached` prêts à la connexion (jours 2 à 14) | > 50 % | `Balance.Offline.StopAt` 0,9 → 0,8, puis `Balance.Offline.GrowthShare` |
| `TileLevelAtSplorch` : Tapis 12 atteint avant la moitié de la boucle, ou `SplorchCoinsLost` > 10 | médiane sur une semaine | `Balance.Tiles.RScale` 3,5 → 3,8 |
| `BoostShare` | > 40 % ou < 20 % (médiane) | `Events.Gauge.TargetPerPlayer` ± 100 |
| Perte entre les étapes 2 et 3 de l'accueil | > 10 % | Raccourcir le chemin vers le Tapis, renforcer le geste de Big Plop |
| Écart de captures manette / clavier-souris | > 25 % | Rayon de capture 5 → 6 studs pour **tous** (jamais un bonus déclaré par le client) |
| Sessions avec au moins une erreur (`ServerError`, `ClientError`) | > 0,5 % | Correctif sous 48 h ; la clé d'erreur devient d'abord un test qui échoue (§12.10) |
| `FocusRescued` ou `StateTimedOut` | > 0,1 % des sessions pour un même écran ou un même état | Correctif ; test ajouté à la couche d ou c |
| `QualityReduced` chez les joueurs console | > 30 % des sessions | Baisser les budgets du §12.9 (particules, squishies animés, lumières) |
| `MoveViolation` chez des joueurs honnêtes | > 1 % des sessions | Marge de `MoveCheck` 1,5 → 1,8 |
| Médiane de la 1re Jelly Ascend *(v2.0)* | hors 10-18 jours | `Balance.Ascend.ReqR[1]` (15 ± 1) |
| `NextGoalGap` > 3 min *(v2.0)* | > 20 % du temps de jeu (référence) ou > 30 % (joueurs de 2 h par jour) sur une semaine | Leviers du §4.24 (Gants, Tapis Étoilé, `Balance.Ascend.*`) |
| `UpgradeTimeout` *(v2.0)* | > 0,1 % des achats | Correctif ; délai d'« en cours » revu |

---

## 17. Lancement et mises à jour *(v2.0 : réécrit)*

### 17.1 Au lancement : le jeu complet

**Décision par défaut n° 6 : tout le contenu est construit et testé avant la sortie ; il n'y a pas de calendrier daté.** La date de sortie n'est plus fixée dans ce document : le jeu sort quand les portes de qualité du §18 sont vertes (la barre « zéro bug » passe avant la date).

**Repris de la v1.3** :
- **Monde** : Wobbleton, 16 ranchs, construits en code ; costume « Frost & Sprinkles ».
- **Boucle** : grandir, presser + PERFECT et séries, Pot, dalles, Cuve à Gelée (tables, protections, nouveauté garantie), Bassin de Fusion et combos, créatures en fuite personnelles et Golden Wobbler, monture et bond.
- **Social et événements** : BOOP RUSH (mode Rush/Cozy, interrupteur, « Pas ce joueur »), Wild Wobblers (partagés et personnels), bouclier débutant, démonstration de Big Plop, MEGA SQUISH, jauge du serveur et Wobble Party, Grand Splorch et ses cadeaux, applaudissements, Étagère à trophées, Jelly Moon (4 séances le samedi, rattrapage le dimanche), Flop Plop, ranchs voisins, bonus d'amis, pet-sitting, emotes, 5 classements de la semaine, nom caché.
- **Rétention** : Nourrir Plop (jours au total), objectifs du jour faisables, Squishydex et bonus de famille, carte « Plop a sommeil », écran de retour.
- **Monétisation** : 4 passes et 2 familles de produits du §8 (Squish Party, tenues), sans publicité, sans monnaie vendue, PolicyService.
- **Appareils** : PS5, PS4, Xbox Series, Xbox One et PC (types d'appareils Ordinateur + Console). Pas de téléphone ni de tablette.
- **Technique** : schéma (v2 en v2.0) avec champs réservés, disposition télé unique et couche console (glyphes, `FocusGuard`, vibrations, sons d'interface), anti-triche, analytics, Diagnostics et panneau des administrateurs, qualité adaptative, EN/FR, Mouvement réduit, Graphismes légers.

**Ajouté par la v2.0, au lancement aussi** :
- **Améliorations** : les 9 familles du §4.6 (144 niveaux), l'écran Améliorations et ses 20 règles (§10.7, §10.8), la puce « Prochain achat », le Carnet du Ranch (§7.5).
- **Renaissance** : Grand Splorch enrichi (cadeau du Splorch, places offertes, décorations gardées, socles), table des Record R 1 à 400 (§4.29), Confettis et Atelier complet (§4.26), **Jelly Ascend, Petit Splorch et Souvenir de gelée** (§4.27), halo et ciel A1 à A20.
- **Plopettes** et École (§4.28).
- **Visuels** : feuille de style, 6 paliers de ranch, Monuments 1 à 10, paliers du Tapis, coussins, lit à baldaquin, socles, décorations dorées, habillages (14), Déco perso (40 objets), personnalités, visages et tours appris (§5.6), événements relookés, météo visuelle, place en fête, mode photo, jumelles et cœurs.
- **Rétention** : piste de la semaine (gratuite, la seule), Défis de Splorch, Carnet du Ranch, Livre des records (lecture seule : plus gros squishy, meilleur combo, Grands Splorch, Ascensions, Record R, Confettis gagnés, maîtrises, jours de Plop, cœurs reçus), **Maîtrise d'espèce** (fiche à 3 cases : ★5, Page dorée, Trophée Cristal ; +25 Confettis ; « Maîtrises 3 / 26 » ; un seuil ne bouge jamais quand une espèce arrive), **jalons de taille géante** (1e15 selle « Cosmique », 1e18 traînée « Étoiles filantes », 1e21 Squishy-Soleil, 1e24 titre « Sun Keeper »).
- **Costume** : « Frost & Sprinkles ».

**Ce qui s'ouvre par la progression** (jamais par une date) : Gants (Record R 1), Atelier (R1), Plopettes (R2, R4, R6, R8, R12), Lit (R3), Monuments (R6 à R24), Tapis Étoilé (r 6 à 10 dans la boucle), Plume (R12), Jelly Ascend (r 15, puis 20, puis +4), Tremplin (A ≥ 1 ; les niveaux 3-4 de « Déco qui reste » sont retirés depuis la critique M3), habillages, titres et paliers (§4.29).

### 17.2 Ensuite : seulement des espèces et des costumes

| Rythme | Contenu | Comment |
|---|---|---|
| Chaque semaine | Une nouvelle espèce (nouvelle famille de 4 par mois, ou sans famille, §4.17), sa personnalité, ses débuts pendant la Jelly Moon | Ligne de données `Config/Species` avec `release` ; aucun nouveau code |
| Chaque saison | Un costume (kit du §11.5) et ses objets dans « Pour le plaisir » et la piste de la semaine | Ligne de données `Events.Costumes` |

**Réserve non planifiée** (idées de la v1.3 qui ne font pas partie du jeu complet de la v2.0 ; aucune date ; chacune demanderait une décision du propriétaire et une nouvelle porte de qualité) : lignée de Fame complète, Gelée lente, espèces Duo et colis entre amis, World First et énigme du lundi, Grande Gelée entre serveurs, semaines « Encore », paquets de pièces (retirés, §8.3), ouverture aux téléphones et tablettes. Leurs crochets restent dans le schéma (§12.6) et les interrupteurs (`Features.*` à `false`) : rien à migrer s'ils arrivent un jour. **Supprimés** : la « saison de 28 jours » et sa piste premium (décision par défaut n° 5 : jamais de piste payante) ; « Jelly Ascend en janvier après 10 Grands Splorch » (remplacée par le §4.27, au lancement).

---

## 18. Checklist de lancement *(v2.0 : modifié)*

**Portes de qualité (bloquantes)** — les couches du §12.10
1. `./scripts/check.sh` vert : StyLua, Selene (0 erreur), toutes les specs Lune (couches a à h et j), **dont `EconomyPacing`** (§4.24 ; v2.0 révisé, critique M14 : 20 joueurs par taille de serveur dans `check.sh`, ≈ 3,5 min ; 50 joueurs, 140 jours et les configurations forcées **la nuit**, §4.24.1), build Rojo, vérification de la place.
2. Couche c : `Soak.spec` (16 robots, 6 h de temps simulé, invariants à chaque tick) et `Boot.spec` verts, **sans aucune erreur ni aucun avertissement**.
3. Couche d : `ClientReplay.spec` et `Console_*.spec` verts en 1920 × 1080, 3840 × 2160 et 1280 × 720, en anglais et en français : chaque écran atteint avec la croix, ✕ et ○ ; ○ revient toujours ; aucun focus perdu ou piégé ; aucun chevauchement, aucun texte coupé ou sous 28 px TV ; rien hors de la zone sûre ; glyphes PlayStation.
4. Couche e : échec de chargement (rien n'est sauvegardé), arrêt du serveur (`BindToClose` sauvegarde tout), retour sur un autre serveur après une panne (rien de perdu), rejeu de `ProcessReceipt` (aucun double crédit), profils abîmés réparés.
5. Couche g : specs `RedTeam_*` vertes, plus un contre-audit indépendant (« red team ») sur le Rush, les captures (dont `tClient`), les bonds (crédit de 12 studs), le MEGA, les portails des ranchs, les achats, les fermes de bébés et de croissance « Héros » à deux comptes et le pet-sitting par un second compte.
6. Couche h : aucune spec ne laisse passer une erreur ou un avertissement imprévu.
7. Couche i : dès que la clé de l'API Open Cloud est fournie, la suite des tests serveur est verte **dans de vrais serveurs Roblox**, sans erreur ni avertissement dans les journaux. Si la clé n'est pas là avant la sortie (aucune date fixée, décision par défaut n° 6), les tests manuels ci-dessous la remplacent et le manque est écrit dans le rapport qualité.
8. Tests manuels M1 à M18 tous réussis, dont **une vraie PS5** et **une PS4 ou une Xbox One**.
9. **Aucun bug connu ouvert**, ou chaque bug restant accepté par écrit par le propriétaire.

**Tests manuels dans Studio, en ligne et sur console** (environ deux journées, plus le test à 16). Pendant chaque test : la fenêtre *Output* de Studio ou le panneau Diagnostics (§12.11) reste à zéro erreur.

| # | Test | Résultat attendu |
|---|---|---|
| M1 | Première session seul, 5 min, **à la manette seulement**, sans rien lire d'autre que le jeu ; puis deux fois avec un Rush forcé à 0:30 et un MEGA forcé à 1:30 | Pression à 10 s, Tapis vers 0:20-0:25, fusion à 1:00, capture à 2:00, monture vers 4:30 ; jamais deux consignes à la fois ; chaque consigne montre le bon glyphe ; Rush et MEGA restent discrets ; Presser et Prendre jamais confondus ; aucune étape bloquée |
| M2 | Rendu sur une vraie télé : tour de la ville et des ranchs, un Rush, un MEGA, une Jelly Moon (horloge avancée), Graphismes légers | Pastel lisible à 3 m, raretés reconnaissables par la couleur **et** la forme, rien qui clignote |
| M3 | Physique : portails (propriétaire et intrus), mur invisible des clôtures (30 studs), bords du plateau, monture à chaque selle (taille fixée par la selle ; courir et sauter 1 min, puis presser et attraper depuis la monture), bond contre une maison, chute | L'intrus rebondit, personne n'entre ni n'enjambe la clôture, même en monture ; aucun « connexion instable » pour un cavalier honnête ; presser et attraper marchent depuis la monture ; personne ne reste coincé dans le décor ; retour sur le plateau après une chute ; réapparition toujours dans son ranch |
| M4 | Vraies sauvegardes : jouer, quitter, revenir, changer de serveur aussitôt, arrêter les serveurs | Rien de perdu, jamais de retour en arrière |
| M5 | Achats : chaque pass et produit (essais gratuits), puis un vrai petit achat en privé, **dont un sur PS5** | Effet reçu une fois ; pass gardé après un Grand Splorch ; Squish Party pour tout le serveur ; nom caché par défaut ; après la fenêtre d'achat PlayStation, la sélection revient sur le bouton Acheter |
| M6 | **16 vrais joueurs** pendant 30 min, dont **une PS4 ou une Xbox One** et une PS5, *(v2.0)* avec des profils de test au Record R 20 (paliers, Monuments, Déco perso, halo, ciel, Plopettes) | ≥ 30 images/s en permanence sur la PS4 ou la Xbox One (la qualité adaptative peut descendre), 60 sur la PS5, mémoire < 900 Mo, aucune erreur dans Diagnostics |
| M7 | Textes en français et en anglais en 1280 × 720, 1920 × 1080 et 4K (émulateur de Studio, puis une vraie télé 4K) | Rien de coupé ni sous 28 px TV ; aucun chevauchement ; nombres au format de la langue |
| M8 | Particules : Grand Splorch, MEGA, naissance Secret, flocons d'hiver | Beaux, lisibles, budget tenu |
| M9 | **Manette seule pendant 30 min sur une vraie PS5**, sans jamais toucher un clavier | Chaque écran atteint avec la croix, ✕ et ○ (et croix ↓ pour le menu) ; ○ revient toujours ; la sélection n'est jamais perdue ni bloquée ; aucune carte ne vole la manette ; marteler □ presse toujours un squishy prêt ; L3 et R3 enfoncés par erreur ne font rien |
| M10 | Poursuite avec 250 ms de latence simulée, sur une fuite du Rush à 16 studs/s | Les captures accordées correspondent à ce que voyait le joueur au moment de l'appui : au moins 95 % accordées quand il la voyait à 5 studs ou moins, aucune au-delà de 7 ; un bond qui atterrit sur la créature l'attrape ; une capture avec □ juste après un bond n'est jamais refusée |
| M11 | **Vraie PS5 à 3 m** (télés de 43 et 55 pouces, mode Jeu coupé puis activé), puis une Xbox | Tout lisible, rien de coupé, zone sûre respectée ; vibrations modérées et au bon moment ; invites □ / ○ claires ; PERFECT réussi à peu près aussi souvent qu'au PC ; glyphes PlayStation sur PS5 et Xbox sur Xbox |
| M12 | **Écouter chaque son** (d'abord ceux remplis en dernier), dont les sons d'interface | Agréables, pas trop forts, `Sneeze` drôle et doux ; un son qui déplaît est vidé (jeu jouable en silence) |
| M13 | Session de 60 min à plusieurs | Aucune erreur dans Diagnostics, pas de ralentissement, mémoire stable, carte « Plop a sommeil » à 60 min |
| M14 | Un enfant de 8-10 ans accompagné, **à la manette devant la télé**, joue un Rush en mode Rush puis en mode Cozy, puis fait un Grand Splorch ; *(v2.0)* ouvre l'écran Améliorations, achète avec le Conseillé, puis en ×10 et Max (« Léa comprend-elle Max ? »), achète une ligne de l'Atelier, voit une Jelly Ascend (profil de test) et dit ce qui est gardé ; compare les 3 versions des yeux « bébé » | Il comprend le choix, rit pendant la poursuite, ne se sent pas volé, retrouve seul le bouton « Mode Cozy » après un boop, lit les textes depuis le canapé, ne se perd pas dans les menus, et voit son squishy revenir après le Grand Splorch |
| M15 | Rush à 6 joueurs : un boopeur, un propriétaire loin de sa clôture, 4 poursuivants | La poursuite dure plus de 6 s ; le boopeur ne l'attrape pas tout de suite ; le propriétaire voit sa flèche ; à l'image, une bulle-bébé, jamais un animal emporté |
| M16 | **Clavier et souris sur PC** : M1 et le parcours de M9 à la souris | Tout se fait au clavier-souris ; Échap reste à Roblox ; Retour arrière revient en arrière ; les glyphes passent du clavier à la manette dès qu'on la prend |
| M17 | **Diagnostics** : provoquer une erreur de test (commande de développement), côté serveur puis côté client | Elle apparaît dans « Ce serveur », « Mon client » puis « Aujourd'hui », sans aucun nom de joueur ; un compte non administrateur ne voit pas l'entrée et n'obtient aucune réponse |
| M18 | **Pannes et imprévus** : couper le réseau du client 20 s, changer de manette, débrancher la manette, rejoindre pendant un Rush, un MEGA ou le Grand Splorch d'un autre, mourir en portant un squishy ou pendant un boop | Rien de bloqué ni de faux ; le squishy porté revient à sa place ; les créatures finies disparaissent ; l'état se recale tout seul |

**Réglages de publication** (propriétaire)
- *(v2.0 révisé, critique m25)* Publier la v2.0 avec **« Migrer vers la dernière mise à jour »** (Creator Hub) : sinon des serveurs v1.3 restent ouverts et un joueur déjà migré en v2 qui suit un ami sur un vieux serveur est renvoyé (« Ce serveur n'est pas à jour », §12.6). Étape écrite aussi dans le guide de publication (docs/05).
- Taille du serveur **16** (Creator Hub) et `Players.MaxPlayers = 16` dans le projet ; remplissage maximal, une place réservée aux amis.
- **Types d'appareils : Ordinateur + Console**. Téléphone et Tablette décochés. VR coupée.
- Questionnaire de maturité (cible Minimal ; « non » aux objets aléatoires payants : aucun hasard payant, aucune chance achetable, aucune monnaie vendue, §8.1) ; langues EN et FR ; traduction automatique activée ; console activée **seulement après** M6, M9 et M11.
- Créer les passes et produits, coller leurs identifiants, vérifier la Boutique (script de prépublication repris de Comet).
- Administrateurs LiveOps et Diagnostics (`Data/Admins.luau`).
- Pour la couche i : une **clé d'API Open Cloud** limitée à la place de test privée (publication de place et exécution Luau), donnée par une variable d'environnement, **jamais écrite dans le dépôt**.
- *Experience Event* de la Jelly Moon déclaré pour le samedi.
- Icône et vignettes capturées en jeu (commande de développement « Photo ») ; test d'icône Raise a Squishy contre Squishy Ranch.
- **Recherche de nom et de marque** : « Raise a Squishy », « Squishy Ranch », « Plop », « Big Plop », « Wobbleton », noms d'espèces (y compris contre Squishmallows).
- *(v2.0)* **Pas de date de repli fixée** : tant qu'une porte n'est pas verte, on ne sort pas (décision par défaut n° 6). Portes v2.0 ajoutées : les 20 règles du §10.8 et leurs tests ; les clés de la simulation v2.0 (§4.24) à 4, 8 et 16 joueurs, pour le joueur de référence **et** le joueur de 2 h par jour ; le robot de 6 h avec achats ×1 / ×10 / Max et Ascensions (Record R jamais en baisse, aucun squishy perdu, un seul prestige par joueur dans la file, instances stables).

---

## 19. Risques et parades *(v2.0 : modifié)*

| # | Risque | Probabilité / impact | Parades | Indicateur |
|---|---|---|---|---|
| 1 | **Le BOOP RUSH semble être du vol** pour les plus jeunes | Moyenne / fort | Mode choisi des deux côtés, Cozy par défaut et immédiat, choix au calme après 15 min, boop par-dessus la clôture, propriétaire gagnant, attrapeur qui ne touche jamais l'original (bulle-bébé), Meilleur Ami protégé, paires limitées, « Pas ce joueur », bouclier de 15 min, interrupteur `"events"` / `"off"` | `PostBoopQuit` contre `QuitBaseline` (§16.4) |
| 2 | **Économie déséquilibrée** (inflation par les bébés et les fusions, ou blocage) | Moyenne / moyen | Taille des bébés ≤ 0,5 × le plus gros, plafonds journaliers, récompenses en secondes de revenu, prix des dalles × 3,5^R, croissance hors ligne arrêtée à 90 % de l'objectif, boosts calculés d'après les règles, simulation bloquante (rythme et santé de l'économie, 3 tailles de serveur), tables en configuration | Médianes du §4.24, `SplorchReached`, `TileLevelAtSplorch`, `BoostShare` |
| 3 | **Charge de travail du jeu complet** (≈ 78 jours de développement en plus, v2.0) avec la barre « zéro bug » *(v2.0 : modifié)* | Forte / fort | Pas de date fixée (décision n° 6) : on sort quand tout est vert ; paquets parallèles sans fichiers communs (`packages-proposal.md`) ; base de Comet reprise, téléphone retiré ; si un système ne passe pas sa porte, il attend, jamais la qualité | Portes du §18 |
| 4 | **Performance sur la console la plus faible** (PS4, Xbox One) : 16 ranchs, 384 squishies animés | Moyenne / fort | Rendu client, niveaux de détail, 80 animés au plus (40 en qualité réduite), `BulkMoveTo`, ShadowMap, budgets du §12.9, qualité adaptative, Graphismes légers, test M6 sur une vraie PS4 ou Xbox One | `QualityReduced`, images/s par appareil |
| 5 | **Litiges « je l'ai attrapé ! »** avec la latence | Moyenne / moyen | Trajets déterministes identiques client/serveur, capture vérifiée à l'instant de l'appui (`tClient` et historique des positions validées), tolérance de 1,5 stud, crédit de déplacement du bond, effets seulement après confirmation, test M10 | Captures par type d'entrée |
| 6 | **Serveurs peu peuplés** sans poursuite | Moyenne / moyen | Wild Wobblers (jusqu'à 13, plus un personnel par joueur), démonstration de Big Plop, Golden, MEGA réussissable seul (objectif 80 pour 1 joueur) | `serverBand`, rétention par tranche |
| 7 | **Noms non vérifiés** (titre, Plop, Wobbleton, espèces) | Inconnue / fort | Recherche Roblox et marques avant publication ; titre de secours Squishy Ranch | Checklist §18 |
| 8 | **Formes simples moins belles** que des modèles 3D | Moyenne / moyen | Direction artistique forte (pastel, écrasement, rebond), test d'icône tôt | Taux de clic sur l'icône |
| 9 | **Copies en 2 à 6 semaines** | Forte / moyen | Une espèce par semaine en données, mascotte forte, progression (Fame, Étagère, jours de Plop) gardée dans la sauvegarde | Joueurs simultanés |
| 10 | **Classification** : le côté étrange de la Lune | Faible / fort | Rester mignon ; questionnaire avant le lancement | Note reçue |
| 11 | **Dérive des règles de Roblox** (hasard payant, publicités, Kids/Select) | Faible / fort | Aucun hasard payant, aucune chance achetable même par les pièces (Cuve liée à R), aucune monnaie vendue au lancement, `PolicyService` lu, aucune publicité, revue à chaque version | Revue mensuelle |
| 12 | **Faux positifs de l'anti-triche** | Moyenne / moyen | Signaler avant de ramener, gel de 1,5 s toléré, ton neutre, exclusion des classements limitée dans le temps | `MoveViolation` |
| 13 | **Sons manquants ou désagréables** (bibliothèque officielle limitée) | Moyenne / faible | Jeu jouable en silence, écoute obligatoire (M12), replis documentés (§9.6) | Retours des testeurs |
| 14 | **Audience plus petite** : console d'abord, sans téléphone (≈ 80 % des joueurs Roblox en 2024, ≈ 3 % sur console) | Certaine / moyen | Choix assumé du propriétaire : une seule disposition, polie et testée à fond ; PC gardé ; créneau des tycoons faits pour la manette peu servi ; aucun effet propre à la DualSense ; ouverture aux téléphones possible plus tard sur décision (§17.2) | `device`, joueurs simultanés |
| 15 | **Plafond de revenus** d'une monétisation juste | Certaine / moyen | Assumé : fidélité d'abord ; Squish Party sociale ; Creator Rewards | ARPDAU |
| 16 | **Pièces perdues au Grand Splorch** (ressenti de perte) | Moyenne / moyen | Aucune monnaie vendue au lancement (paquets retirés, §8.3) ; perte annoncée en rouge avec « Dépenser d'abord » (dalles gardées d'abord, §4.15) ; croissance hors ligne arrêtée à 90 % : le Grand Splorch se fait en jeu, après avoir dépensé | `SplorchCoinsLost` |
| 17 | **Ciblage d'un enfant par un même joueur** | Moyenne / fort | Une paire au plus toutes les 30 min, 4 fuites par heure, « Pas ce joueur », Cozy immédiat | `RefuseBooper`, `CozyAfterBoop` |
| 18 | **Des bugs visibles en ligne mais pas hors ligne** (ce qui est arrivé à Comet Conga) | Moyenne / fort | Mécaniques robustes (aucune règle physique ou liée à une animation, `StreamingEnabled` coupé, délais sur tous les états), 10 couches de tests dont les robots de 6 h, le parcours console aux 3 résolutions et la règle « zéro trace » ; tests dans de vrais serveurs par Open Cloud ; tests manuels sur PS5, PS4 ou Xbox One ; Diagnostics en ligne et correctif sous 48 h | `ServerError`, `ClientError`, `StateTimedOut` |
| 19 | **Navigation à la manette qui se perd** (sélection vide, piégée, ou action derrière une fenêtre) | Moyenne / fort | `FocusGuard` (§10.6), règle des 3 touches vérifiée par un robot, touches du jeu déliées derrière une fenêtre, test M9 | `FocusRescued` |
| 21 *(v2.0)* | **Bugs d'affichage de l'écran Améliorations** (la plainte n° 1 du propriétaire sur Comet Conga) | Moyenne / fort | Écran au pixel (§10.7), 20 règles et leurs tests (§10.8), politique de texte unique, mesure à Medium et Largest, captures à 720p, 1080p et 4K | `UpgradeTimeout`, `FocusRescued`, retours des testeurs |
| 22 *(v2.0)* | **Un système lit r au lieu du Record R** et « reprend » un déblocage après une Ascension | Moyenne / fort | `Logic/Prestige` seule source ; test statique ; propriétés de `Prestige.apply` sur des milliers de profils | Diagnostics |
| 23 *(v2.0)* | **Double achat, achat rejoué, Confettis comptés deux fois** | Moyenne / fort | `expectedLevel`, seau à jetons, un seul bloc ; Confettis modifiés seulement par `EconomyService.addConfetti` et `buyUpgrade` (critique m2) | Robots de 6 h |
| 24 *(v2.0)* | **File du serveur saturée** par les vétérans après les Ascensions | Moyenne / moyen | Petit Splorch hors file ; clé `queueWaitNewcomer` | Attente médiane du premier Grand Splorch |
| 25 *(v2.0)* | **Joueur de 2 h par jour sans but proche** | Moyenne / moyen | Gants à 40 niveaux, Tapis Étoilé ouvert dès r = 6, Souvenir de gelée dégressif, prix × F(A) en table, 12 décorations gardées au plus ; mesuré sur 140 jours (§4.24.1, critique B1) ; invariant de stabilité contre l'emballement (§4.27, critique M13) | `NextGoalGap` |
| 26 *(v2.0)* | **Performance PS4** avec ≈ 2 040 pièces de décor en plus | Moyenne / fort | Budget en direct, détail par index de ranch, 0 lumière de plus, test M6 | `QualityReduced` |
| 27 *(v2.0)* | **Écran trop dense pour Léa, 8 ans** | Moyenne / moyen | 4 onglets, Conseillé, bandeau, mode ×1 à chaque ouverture, test M14 | `UpgradeMode` |
| 28 *(v2.0)* | **Avance d'un gros acheteur** plus visible avec l'Ascension | Certaine / faible | Mesurée (§4.24.1) ; clé `spenderLeadTimeShare` ≤ 25 % (en temps) ; décision du propriétaire (§20, question 8) | `spenderLeadTimeShare` |
| 29 *(v2.0 révisé, critique B3)* | **Le moteur agrandit les libellés** avec `PreferredTextSize` malgré `UITextSizeConstraint` | Inconnue / fort | `UI/Text` mesure le facteur réel avec une étiquette témoin et compense ; `Text_policy.spec` joue les deux comportements ; panneau TextProbe photographié sur la PS5 | Diagnostics (`TextScaleMeasured`) |
| 30 *(v2.0 révisé, critique M1)* | **Les enfants refusent l'Ascension** et le jeu se creuse | Moyenne / moyen | Carte Conseillé « Jelly Ascend », geste de Big Plop, focus sur « Oui », textes vrais et chiffrés (§4.27) ; profil « refuse 3 jours » dans la porte | `AscendDeclined` |
| 20 | **Télé : texte illisible, bords coupés, retard d'image** | Moyenne / moyen | Textes ≥ 28 px TV, zone sûre de 5 % sur tous les écrans, fenêtre PERFECT décalée vers le tard, tests M7 et M11 sur de vraies télés | Retours des testeurs, taux de PERFECT par appareil |

---

## 20. Questions ouvertes et décisions par défaut *(v2.0 : réécrit)*

### 20.1 Les 6 décisions par défaut de la v2.0

Le studio a tranché les 6 questions du §8.4 de docs/09 ; ce sont des **décisions par défaut** : elles sont appliquées dans tout ce document, et **le propriétaire peut revenir sur chacune** (ce qui changerait alors est écrit à côté).

| # | Question de docs/09 §8.4 | **Décision par défaut** | Où | Si le propriétaire la change |
|---|---|---|---|---|
| 1 | Jelly Ascend au Grand Splorch 15, en gardant les déblocages, les Confettis, l'Atelier, les Plopettes et les Monuments ? | **Oui**, au lancement : 1re à r ≥ 15, puis 20, puis +4 ; tout ce qui est débloqué est gardé ; Souvenir de gelée (dégressif) pour remonter vite ; l'interface la montre quand le jeu se creuse (carte Conseillé, focus sur « Oui », critique M1) | §4.27 | Sans Ascension, la fin du premier mois est creuse (mesuré après la critique : 30,0 / 51,2 / 64,5 % du temps « sans but » aux jours 15-28, 29-56, 57-84 pour la référence, limite 20 %) ; il faudrait d'autres leviers |
| 2 | Remplacer « Croissance ×2 pour toujours » par « Croissance ×2 » ? | **Oui** (« pour toujours » serait faux avec l'Ascension) | §4.15, §4.27, §9.4 | Seulement possible sans Ascension |
| 3 | Plopettes au lancement ? | **Oui**, au lancement (Pip au Record R 2) | §4.28 | Sans Plopettes, l'École disparaît (−20 niveaux) et la porte est à refaire |
| 4 | Météo de Wobbleton : bonus de mutation ou purement visuelle ? | **Purement visuelle** (aucun effet sur le jeu, rien à simuler) | §5.6 | Un bonus demanderait une ligne dans le Guide et une nouvelle mesure des tampons du jour 7 (cible 80-110) |
| 5 | Piste premium décorative ? | **Jamais** : une seule piste, gratuite | §7.5, §8.4 | — |
| 6 | Calendrier de sortie ? | **Tout le contenu est construit et testé avant la sortie** ; **aucun calendrier daté** ; tout est disponible au lancement, ouvert par la progression ; seules les **espèces** de la semaine et les **costumes** de saison arrivent ensuite. Le joueur de 2 h par jour a un but proche **par le design** (mesuré après la critique : 10,6 à 16,5 % du temps « sans but » dans chaque bande jusqu'au jour 84 et 11,7 à 13,9 % aux jours 85-140, limites 15 et 30 %) | §7.6, §17, §4.24.1 | — |

### 20.2 Questions encore ouvertes

1. ~~**Paquets de pièces au lancement**~~ : tranchée en v1.3 (retirés). Ils restent dans la réserve non planifiée (§17.2).
2. **Titre** : Raise a Squishy ou Squishy Ranch, après la recherche de nom et de marque et le test d'icône ?
3. ~~**Suffixes français des grands nombres**~~ : tranchée en v1.3 (suffixes internationaux).
4. **Squish Party** : 99 R$, 10 min, 3 achats par jour, seulement si elle commence aussitôt, nom caché par défaut. D'accord ? (Voir aussi la question 8.)
5. **Clips automatiques** activés par défaut, ou désactivés par défaut ?
6. **Test fermé** *(v2.0 : modifié)* : avec la barre « zéro bug » et sans date fixée, nous proposons un **test fermé de 2 semaines** dès que le jeu complet est vert, avec 20 à 30 testeurs (PC, PS5, et si possible une PS4 ou une Xbox One), panneau Diagnostics ouvert, et des profils de test avancés (Record R 20, A = 3) pour voir la fin de jeu sans y jouer 2 mois. D'accord ?
7. **Matériel et accès pour les tests** : une **PS4 ou une Xbox One** et une Xbox, en plus de la PS5, pour M6 et M11 ? La **clé d'API Open Cloud** de la place de test (couche i du §12.10) ?
8. **Avance d'un gros acheteur avec la Jelly Ascend** *(v2.0 : nouvelle ; chiffres refaits après la critique)* : le gros acheteur (×2 Pièces, Grand Ranch, Squish Party la moitié de chaque séance) a, comme en v1.3, environ **15 à 22 % d'avance en temps** ; sans Ascension c'est +2 R au jour 28, mais avec l'Ascension cela se lit **+4 Record R et +1 Ascension au jour 28** (24 contre 20), et l'écart grandit ensuite (+9,5 Record R au jour 84). Le ×2 Pièces et le Grand Ranch seuls : 8 à 15 % plus tôt, +2 au jour 28, +7,5 au jour 84. **Proposition par défaut : garder les passes et la Squish Party tels quels** (rien n'est vendu au-delà de la v1.3, la vitesse n'achète rien que le joueur gratuit n'obtienne plus tard), dire la vérité dans le §8.1 n° 10 et le §8.5 (critique M2), et suivre l'avance **en temps** (`spenderLeadTimeShare` ≤ 25 %, bloquante). Si vous voulez strictement « 1 à 2 R » : la Squish Party pourrait ne plus profiter à son acheteur (un cadeau pour les autres joueurs du serveur), ce qui ramène l'avance à celle du ×2 Pièces seul (+2 R).
9. **Profil du joueur de 2 h par jour** *(v2.0 : nouvelle ; chiffres refaits après la critique)* : avec 2 h par jour, il fait une Ascension tous les 4 à 5 jours et atteint A = 18 au jour 84 (Record R 84,5) et A = 34,5 au jour 140 : il voit tout le halo (A5) au jour 26 et tout le ciel (A20) vers le jour 92. Voulez-vous ralentir sa cadence (par exemple condition +5 au lieu de +4 au-delà de A = 5), au prix de boucles record plus longues pour tous ? *(5 novembre 2026, porte d'économie du lot A1 : condition + 5 une fois toutes les 8 Ascensions dès la 11e, pour tenir `ascendGapDays` à chaque Ascension ; l'assidu fait une Ascension tous les 5 jours et atteint A = 28 au jour 140, médiane sur 400 joueurs ; la question de sa cadence reste ouverte.)*

Tranchées en gardant le choix de la version 1.0 (anciennes questions 8, 9 et 11) : les cadeaux du Grand Splorch vont à tout le serveur ; le pet-sitting reste réservé aux amis Roblox ; le Meilleur Ami suit le joueur en ville.

---

## Annexe A. Écarts décidés par rapport au concept du jury (§8)

Détails et justifications du concept : [`03-decision-du-jury.md`](03-decision-du-jury.md).

| Point du concept | Décision de ce GDD | Pourquoi |
|---|---|---|
| Une goutte de Cuve toutes les 45 s au début | **90 s** pendant l'accueil, puis 55,3 s à R = 0 et 17,7 s dès R = 4 (vitesse donnée par R, §4.9) | Avec 45 s, le joueur aurait 6 squishies à 5:00 au lieu de 3-4 (cible du jury) ; la simulation tient la cible avec 90 s pendant l'accueil |
| Selle à la taille 100 vers 4:00 | **Selle à 1 200** | Avec +1/s, le Tapis et la fusion de 1:00, Plop dépasse 100 avant 1:00 ; 1 200 tombe vers 4:30 |
| Jauge du serveur = somme des tailles | **Jauge = actions de tous** (pressions PERFECT seulement, naissances, captures, fusions…), objectif 600 × joueurs actifs, sieste de 20 min après chaque fête (§4.23) | Avec des tailles de 1 à 1e30, un vétéran la remplirait seul et un débutant n'y compterait jamais ; en comptant chaque pression, un serveur actif était en ×2 la moitié du temps |
| Rush à :00, :10… et MEGA à :00, :30 | **Rush à :05, :15… ; MEGA à :20, :50 ; Golden à :00:30, :10:30, :30:30, :40:30** | Un seul grand spectacle à la fois avec 20 s d'écart (greffe n° 9) |
| « La croissance est doublée pour toujours » | Croissance × 2 par Grand Splorch, **objectif × 2,6** par niveau, **prix des dalles de la boucle × 3,5^R** | Avec un objectif × 2, les boucles raccourciraient sans fin ; × 2,6 donne R = 10 au jour 7 et R = 20 au jour 28 (simulation v1.3, §4.24). Des prix × 2^R laissaient toutes les dalles au maximum quelques minutes après chaque Grand Splorch (§4.6) |
| Le rebirth remet à zéro « les constructions » | Tapis, décorations et Cuve repartent de zéro ; **les places d'enclos et le Lit douillet sont gardés** | Perdre des places ferait dormir des squishies : ressenti de perte, contraire au pilier P2 |
| Revenu = … × rebirth × Fame | R agit par la croissance (donc la taille) ; Fame est un bonus additif plafonné à +300 % | Éviter de compter le rebirth deux fois et l'inflation |
| À 5:00, « environ 1 000 à 2 000 pièces » | Assez de pièces pour la dalle Enclos ; ≈ 10K en poche (repère) | Les pièces en poche montent et descendent à chaque achat ; ce qui compte est que le prochain achat soit à portée |
| Hors ligne 8 h (12 h avec des pièces) | Croissance hors ligne à **30 %, arrêtée à 90 % de l'objectif** de Grand Splorch, Pot à 25 %, 8 h ; 12 h avec le **Lit douillet** (25 M pièces, dès R = 3, gardé pour toujours) | Le hors ligne à 100 % rendait chaque retour égal à un Grand Splorch immédiat ; à 50 % sans arrêt, 9 Grands Splorch sur 20 se faisaient encore pendant l'absence (§4.19) ; un achat en pièces doit survivre au rebirth |
| Squishydex « 26 × 9 = 234 entrées » | 26 pages d'espèces + **234 entrées de mutation** + 130 badges d'étoiles | Les 9 mutations comptent toutes ; la forme normale est la page de l'espèce |
| Premier tirage au hasard pendant l'accueil | Hasard réel, avec « **Nouveauté garantie** » sur les 3 premiers tirages (espèce, jamais la rareté) | Éviter une fusion de plus à 5:00 et donner une découverte sans truquer les chances affichées |
| Prix des passes « 249-299 » | ×2 Pièces à **249 R$** | Palier courant ; ajustable par les prix gérés de Roblox |
| Paquets de pièces calibrés sur le revenu (30 ou 120 min) | **Retirés du lancement** (§8.3) | Les pièces repartent de zéro au Grand Splorch (Robux perdus en quelques secondes) et un reçu rejoué après une panne pouvait donner le minimum au lieu du montant affiché ; retour possible en janvier avec un porte-monnaie qui survit au Grand Splorch |
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

## Annexe B. Contenu nommé de la v2.0 : clés, anglais, français, source, case *(v2.0 révisé, critique M10)*

La règle est « chaque clé en anglais et en français **avant le code** » (§15). Cette annexe donne tout le contenu nommé que la v2.0 ajoute et qui manquait. Chaque nom entre dans `TextFitPending` avec sa **case** (la boîte où il s'affiche) avant le code ; `Contract_unlocks.spec` vérifie aussi la Déco perso et les cosmétiques de la semaine (chaque objet a une source, une clé EN et FR, et une case). Les noms propres (Plop, Pip, Big Plop…) sont identiques dans les deux langues.

**Cases utilisées** : (a) case de grille *Mon style* 208 × 232, nom en 28 px sur 2 lignes au plus (176 px utiles) ; (b) ligne de l'écran Améliorations, colonne Texte 540 px, nom en 36 px ; (c) bandeau 1 376 px, phrase en 28 px ; (d) plaque du nom (titres) 400 px, 28 px, 1 ligne ; (e) case de la piste de la semaine 208 × 232, comme (a) ; (f) carte non bloquante 520 × 220, titre 40 px.

### B.1 Les 40 objets de Déco perso (§11.5)

Taille : **P** = petit emplacement (8), **G** = grand emplacement (4). Les 16 premiers sont gagnés ; les 24 suivants s'achètent en Confettis gagnés à l'Atelier, dans cet ordre fixe (ligne « Déco perso de l'Atelier », §4.26). Cases (a) et (c).

| # | Clé | FR | EN | Taille | Source |
|---|---|---|---|---|---|
| 1 | `deco.namePennant` | Fanion à ton nom | Name Pennant | P | Offert à 5:00 de jeu |
| 2 | `deco.plopBench` | Banc de Plop | Plop Bench | P | Squishydex : 25 tampons |
| 3 | `deco.pinkLantern` | Lampion rose | Pink Lantern | P | Squishydex : 50 tampons |
| 4 | `deco.wateringCan` | Arrosoir de gelée | Jelly Watering Can | P | Squishydex : 100 tampons |
| 5 | `deco.mochiStatue` | Statuette Mochi | Mochi Statuette | P | Squishydex : 150 tampons |
| 6 | `deco.goldFountain` | Fontaine dorée | Golden Fountain | G | Squishydex : 260 tampons |
| 7 | `deco.plopBowl` | Gamelle de Plop | Plop's Bowl | P | Nourris Plop : 7 jours |
| 8 | `deco.cloudHammock` | Hamac nuage | Cloud Hammock | G | Nourris Plop : 30 jours |
| 9 | `deco.morningBell` | Cloche du matin | Morning Bell | P | 25 objectifs du jour |
| 10 | `deco.toyBox` | Coffre à jouets | Toy Box | P | 100 objectifs du jour |
| 11 | `deco.plushMoon` | Lune en peluche | Plush Moon | P | 1re Jelly Moon jouée |
| 12 | `deco.moonKite` | Cerf-volant lunaire | Moon Kite | G | 4 Jelly Moon jouées |
| 13 | `deco.ribbonChest` | Coffre à rubans | Ribbon Chest | P | 1re piste de la semaine finie |
| 14 | `deco.miniCarousel` | Petit manège | Mini Carousel | G | 4 pistes de la semaine finies |
| 15 | `deco.workbench` | Établi de Big Plop | Big Plop's Workbench | P | Carnet du Ranch : 750 |
| 16 | `deco.sugarCrane` | Grue en sucre | Sugar Crane | G | Carnet du Ranch : 7 500 |
| 17 | `deco.mushroom` | Champignon guimauve | Marshmallow Mushroom | P | Atelier, 30 Confettis |
| 18 | `deco.candyBucket` | Seau de bonbons | Candy Bucket | P | Atelier, 30 |
| 19 | `deco.birdhouse` | Nichoir sucré | Sweet Birdhouse | P | Atelier, 30 |
| 20 | `deco.hiSign` | Panneau « Coucou » | "Hi!" Sign | P | Atelier, 30 |
| 21 | `deco.puddingStool` | Tabouret pudding | Pudding Stool | P | Atelier, 30 |
| 22 | `deco.mintLantern` | Lanterne menthe | Mint Lantern | P | Atelier, 30 |
| 23 | `deco.wishingWell` | Puits à vœux | Wishing Well | P | Atelier, 60 |
| 24 | `deco.miniWindmill` | Petit moulin | Little Windmill | P | Atelier, 60 |
| 25 | `deco.lollipopSwing` | Balançoire sucette | Lollipop Swing | G | Atelier, 60 |
| 26 | `deco.syrupBarrel` | Tonneau de sirop | Syrup Barrel | P | Atelier, 60 |
| 27 | `deco.sugarSandbox` | Bac à sable sucré | Sugar Sandbox | G | Atelier, 60 |
| 28 | `deco.musicBox` | Boîte à musique | Music Box | P | Atelier, 60 |
| 29 | `deco.iceCreamStand` | Kiosque à glaces | Ice Cream Stand | G | Atelier, 100 |
| 30 | `deco.rainbowBridge` | Pont arc-en-ciel | Rainbow Bridge | G | Atelier, 100 |
| 31 | `deco.rockingBoat` | Bateau à bascule | Rocking Boat | P | Atelier, 100 |
| 32 | `deco.flowerArch` | Arche de fleurs | Flower Arch | G | Atelier, 100 |
| 33 | `deco.pipStatue` | Statue de Pip | Pip Statue | P | Atelier, 100 |
| 34 | `deco.cuckooClock` | Horloge coucou | Cuckoo Clock | P | Atelier, 100 |
| 35 | `deco.cakeTower` | Tour de gâteau | Cake Tower | G | Atelier, 200 |
| 36 | `deco.hotAirBalloon` | Montgolfière | Hot-Air Balloon | G | Atelier, 200 |
| 37 | `deco.bouncyCastle` | Château gonflable | Bouncy Castle | G | Atelier, 200 |
| 38 | `deco.giantSlide` | Toboggan géant | Giant Slide | G | Atelier, 200 |
| 39 | `deco.sugarRocket` | Fusée en sucre | Sugar Rocket | G | Atelier, 200 |
| 40 | `deco.jellyDragon` | Dragon de gelée | Jelly Dragon | G | Atelier, 200 |

Le plus long nom, « Marshmallow Mushroom » (EN), tient en 2 lignes de 28 px dans 176 px ; mesuré avec `TextMetrics` avant le code.

### B.2 Les 8 cosmétiques de la semaine (palier 12 de la piste, §7.5)

Ils tournent dans cet ordre et reviennent au plus tard 8 semaines après. Cases (e) et (f).

| # | Clé | FR | EN | Sorte |
|---|---|---|---|---|
| 1 | `weekly.cookieSaddle` | Selle « Biscuit » | "Cookie" Saddle | Selle |
| 2 | `weekly.bubbleTrail` | Traînée « Bulles » | "Bubbles" Trail | Traînée |
| 3 | `weekly.strawberryFlag` | Drapeau « Fraise » | "Strawberry" Flag | Drapeau |
| 4 | `weekly.polkaBow` | Nœud à pois | Polka Bow | Tenue |
| 5 | `weekly.hugEmote` | Emote « Câlin » | "Hug" Emote | Emote |
| 6 | `weekly.loyalBuddy` | Titre « Copain fidèle » | "Loyal Buddy" Title | Titre |
| 7 | `weekly.peachPalette` | Palette « Pêche » | "Peach" Palette | Palette du spectacle |
| 8 | `weekly.pinkCushions` | Coussins « Nuage rose » | "Pink Cloud" Cushions | Aspect des coussins d'enclos |

### B.3 Habillages de ranch (14, §11.5) et éléments de ciel (20, §4.27)

| Habillage FR | EN | Source | | Ciel | FR | EN |
|---|---|---|---|---|---|---|
| Couleur du ranch | Ranch Colour | v1.3 | | A1 | Nuage-coussin | Cushion Cloud |
| Moonlit | Moonlit | v1.3 | | A2 | Arc de gelée | Jelly Arc |
| Candy Night | Candy Night | v1.3 | | A3 | Aurore sucrée | Sugar Aurora |
| Guimauve | Marshmallow | Record 1 | | A4 | Planète bonbon | Candy Planet |
| Caramel | Caramel | Record 3 | | A5 | Anneau prismatique | Prism Ring |
| Menthe glacée | Iced Mint | Record 5 | | A6 | Anneau menthe | Mint Ring |
| Phare | Lighthouse | Record 10 | | A7 | Anneau lilas | Lilac Ring |
| Glacier sucré | Sugar Glacier | Record 12 | | A8 | Anneau doré | Golden Ring |
| Néon | Neon | Record 15 | | A9 | Anneau arc-en-ciel | Rainbow Ring |
| Cosmos sucré | Sugar Cosmos | Record 17 | | A10 | Constellation | Constellation |
| Royal | Royal | Record 20 | | A11 à A20 | Constellation · 11 étoiles … 20 étoiles | Constellation · 11 stars … 20 stars |
| Nuage | Cloud | Ascension 1 | | | | |
| Aurore | Aurora | Ascension 3 | | | | |
| Céleste | Celestial | Ascension 5 | | | | |

Gouttes du halo (§4.27) : menthe / mint, ciel / sky, lilas / lilac, or / gold, arc-en-ciel / rainbow. Cases (a), (c) et (f).

### B.4 Paliers nommés des familles (§4.6) — case (b), ligne 2

| Famille | Paliers FR → EN |
|---|---|
| Gants Moelleux (9) | Coton → Cotton · Velours → Velvet · À pois → Polka Dot · Rayés → Striped · Guimauve → Marshmallow · Nuage → Cloud · Arc-en-ciel → Rainbow · Étoilés → Starry · Dorés → Golden |
| École des Plopettes (5) | Blanc → White · Fleuri → Flowery · Rayé → Striped · Arc-en-ciel → Rainbow · Doré → Golden |
| Enclos (3) | Herbe tendre → Soft Grass · Coussins moelleux → Fluffy Cushions · Coussins nuage → Cloud Cushions |
| Tapis (6) | §11.5 (déjà en EN et FR) |

### B.5 Selles, traînées, drapeaux, tenues, emotes et titres de la v2.0 — cases (a) et (d)

| Sorte | FR / EN (source) |
|---|---|
| Selles (9) | Confetti / Confetti (Record 2) · Gelée d'or / Golden Jelly (Record 11) · Cosmos / Cosmos (Record 17) · Titan / Titan (Record 20) · Cotillon / Party Popper (Atelier) · Brique / Brick (Carnet 100) · Sucre glace / Icing Sugar (saison Frost & Sprinkles) · Biscuit / Cookie (piste de la semaine) · Cosmique / Cosmic (taille 1e15, §4.17) |
| Traînées (6) | Confettis / Confetti (Record 6) · Arc de gelée / Jelly Arc (Record 13) · Serpentins / Streamers (Atelier) · Petits marteaux / Little Hammers (Carnet 1 000) · Traînée colorée / Colour Trail (Records 25, 30, 35, 40 : une couleur chacun) · Étoiles filantes / Shooting Stars (taille 1e18, §4.17) |
| Drapeaux (3) | « IX » (Record 9 ; chiffre romain, décor) · Splorch Royal / Splorch Royal (Record 19) · Chantier / Building Site (Carnet 250) |
| Tenues (3) | Chapeau de fête / Party Hat (Record 7) · Lunettes étoiles / Star Glasses (Record 16) · Couronne de chantier / Builder's Crown (Carnet 10 000, pour le Meilleur Ami) |
| Emotes (5) | Splorch ! / Splorch! (Record 4) · Ola / Wave (Record 13) · Couronne de confettis / Confetti Crown (Record 19) · Danse de Big Plop / Big Plop Dance (Atelier) · Coup de maillet / Hammer Tap (Carnet 2 500 ; *remplace l'habillage « Atelier », qui aurait fait un 15e habillage*) |
| Titres (16 + 36) | Splorch Myth (R25) · Jelly Monarch (R30) · Wobble Legend (R35) · Cosmic Splorcher (R40) · Ascended (A1) · Sky Keeper (A3) · Sky Wobbler (A5) · Star Jelly (A10) · Jelly Galaxy (A20) · Cosmic Jelly (A40) · Jelly Forever (A60) · Confetti Star (Atelier) · Bâtisseur / Builder (Carnet 50) · Architecte / Architect (Carnet 500) · Grand Architecte / Master Architect (Carnet 5 000) · Gardien du Soleil / Sun Keeper (taille 1e24, §4.17) ; les 4 titres de Record 5, 10, 15, 20 sont ceux de la v1.3 ; et les 36 titres de B.6 |

### B.6 Les 36 titres de Record R 50 à 400 (§4.29) — case (d)

| R | EN | FR | R | EN | FR |
|---|---|---|---|---|---|
| 50 | Jelly Emperor | Empereur de gelée | 230 | Bubble Baron | Baron des bulles |
| 60 | Wobble Wizard | Magicien Wobble | 240 | Marshmallow Master | Maître guimauve |
| 70 | Candy Comet | Comète bonbon | 250 | Legend of Wobbleton | Légende de Wobbleton |
| 80 | Splorch Sage | Sage du Splorch | 260 | Sprinkle Star | Étoile vermicelle |
| 90 | Mega Monarch | Monarque Mega | 270 | Pudding Pharaoh | Pharaon pudding |
| 100 | Splorch Centurion | Centurion du Splorch | 280 | Jelly Colossus | Colosse de gelée |
| 110 | Galaxy Gloop | Gloop galactique | 290 | Wobble Wonder | Merveille Wobble |
| 120 | Nebula Nibbler | Croqueur de nébuleuse | 300 | Splorch Supreme | Splorch suprême |
| 130 | Star Shaper | Façonneur d'étoiles | 310 | Comet Captain | Capitaine comète |
| 140 | Moonlight Mayor | Maire du clair de lune | 320 | Orbit Ace | As de l'orbite |
| 150 | Jelly Guardian | Gardien de gelée | 330 | Starlight Squisher | Squisheur des étoiles |
| 160 | Sugar Supernova | Supernova sucrée | 340 | Aurora Keeper | Gardien d'aurore |
| 170 | Plop Pioneer | Pionnier de Plop | 350 | Infinity Jelly | Gelée infinie |
| 180 | Squish Champion | Champion du Squish | 360 | Celestial Plopper | Plopeur céleste |
| 190 | Rainbow Ruler | Maître arc-en-ciel | 370 | Mythic Wobbler | Wobbler mythique |
| 200 | Ultra Splorcher | Ultra Splorcheur | 380 | Universe Hugger | Câlineur d'univers |
| 210 | Cosmic Cuddler | Câlineur cosmique | 390 | Almost Forever | Presque pour toujours |
| 220 | Gummy Giant | Géant en gomme | 400 | Absolute Splorch | Splorch absolu |

### B.7 Les 12 Défis de Splorch (§7.5) et les 5 tours appris (§5.6) — cases (e) et (f)

| # | FR | EN |
|---|---|---|
| 1 | Fais 2 Grands Splorch | Do 2 Grand Splorches |
| 2 | Gagne 20 Confettis | Earn 20 Confettis |
| 3 | Achète 10 niveaux d'amélioration | Buy 10 upgrade levels |
| 4 | Bats ton record | Beat your record |
| 5 | Fais une Jelly Ascend | Do a Jelly Ascend |
| 6 | Fais un combo ×3 | Make a ×3 combo |
| 7 | Fais naître 2 Rares ou mieux | Hatch 2 Rares or better |
| 8 | Remplis 5 nouveaux tampons | Fill 5 new stamps |
| 9 | Participe à 2 MEGA SQUISH | Join 2 MEGA SQUISH |
| 10 | Nourris Plop 3 jours | Feed Plop on 3 days |
| 11 | Attrape 5 créatures en fuite | Catch 5 runaways |
| 12 | Fais 30 PERFECT | Get 30 PERFECTs |

Tours appris (annoncés par une carte non bloquante « Nouveau tour : Salto ! » / « New trick: Flip! ») : Coucou / Peekaboo (100) · Toupie / Spin (1 200) · Salto / Flip (1 million) · Danse / Dance (1 milliard) · Feu d'artifice / Fireworks (1e12).

### B.8 Textes de moments nouveaux — case (f) sauf mention

| Clé | FR | EN |
|---|---|---|
| `card.welcomeV2.title` | Bienvenue dans la v2 ! | Welcome to v2! |
| `card.welcomeV2.body` | Nouveau : l'Atelier de Big Plop, les Plopettes et plein d'améliorations. Tout ce que tu avais est gardé. | New: Big Plop's Workshop, the Plopettes and lots of upgrades. Everything you had is kept. |
| `card.regainDone` | De retour à ton record 15 ! | Back to your record 15! |
| `card.recordStep` | Étape du record : 50 % ! | Record step: 50%! |
| `hud.regainTrack` | Retour au record | Back to record |
| `hud.memory` (pastille, 28 px) | Souvenir ×3 | Memory ×3 |
| `upgrades.advisor.ascend` (carte, 28 px) | Prête : une nouvelle couche ! | Ready: a new layer! |
| `preview.ascend.restart` (ligne de 40 px) | Tu repars au Grand Splorch 0 (ton record : 15). Tout le reste est gardé. | You start again at Grand Splorch 0 (your record: 15). Everything else is kept. |
| `preview.ascend.speed` (32 px) | Jusqu'à ton record, tes squishies grandissent 9 fois plus vite qu'avant. | Until your record, your squishies grow 9 times faster than before. |
| `preview.splorch.neutral` (32 px) | Tes pièces deviennent le cadeau du Splorch. | Your coins become the Splorch gift. |
| `records.confettiEarned` (32 px) | Confettis gagnés : 4 414 | Confetti earned: 4,414 |

---

## Journal de révision

### Journal de révision v2.0 (2 novembre 2026) : le jeu complet

**Demande du propriétaire** : « le plus complet possible, plein d'améliorations, la renaissance, de beaux visuels, comme les meilleurs tycoons ; prendre le temps qu'il faut ; un jeu complet à la fin », **zéro bug** (en particulier aucun bug d'affichage dans les écrans d'amélioration, la plainte n° 1 sur Comet Conga), console d'abord, rien de vendu au-delà de ce que ce GDD permet. **Sources** : le plan de contenu complet `docs/09-plan-contenu-complet.md` (révisé le 02/11/2026 après deux critiques), ses plans de travail (`etude-tycoons/plan-progression.md`, `plan-renaissance.md`, `plan-spectacle.md`, `ecarts.md`), l'étude `docs/08-etude-tycoons-2026.md` et le contrat `docs/04` (§8, §16, §26). **Méthode** : fusion section par section dans ce document (une seule version de chaque chose), application des 6 décisions par défaut (§20.1), puis **nouvelle simulation** de toute l'économie v2.0 avant d'écrire un seul chiffre de rythme (§4.24.1).

#### Ce qui a été fusionné depuis docs/09 (et où)

| Système de docs/09 | Ici | Remarque |
|---|---|---|
| 9 familles d'amélioration, prix, effets, paliers nommés (§2.1) | §4.6 | Valeurs du code (Tapis ×4,5, pression 22 s) ; Tapis Étoilé et Gants changés (plus bas) |
| Écran Améliorations, rail de 8 boutons, puce « Prochain achat », libellés courts (§2.2) | §10.2, §10.7 | Tapis 20/20 au lieu de « …/20 » plafonné r = 10-16 |
| 20 règles « zéro bug d'affichage » (§2.3) | §10.8 | **Un nom de test par règle** (fichier et cas) |
| Couches, Grand Splorch et Petit Splorch, cadeau du Splorch (§3.1-3.2) | §4.15, §4.27 | — |
| Table des Record R 1-40 (§3.3) | §4.29 | Colonne « plus tard » fusionnée : tout au lancement |
| Confettis et Atelier (§3.4) | §4.26 | + maîtrise d'espèce (+25) ; « Pour le plaisir » qui grandit avec les costumes |
| Jelly Ascend (§3.5), minute par minute (§3.6), états et délais (§3.7) | §4.27, §4.15, §12.10 | Prix ÷ 2 (puis × 0,32 dès A5 après la critique), Souvenir de gelée (dégressif après la critique), plancher 4,7, Tremplin additif |
| Direction artistique, feuille de style, Unified Lighting, Directeur d'ambiance (§4.1) | §10.1, §11.3 | Éclairage à changer avec `default.project.json` (fichier d'un autre rôle) |
| Ranch qui évolue, paliers, Monuments, socles, Déco perso (§4.2) | §11.5 | Budgets réunis (≈ 2 040 pièces côté client) |
| Habillages et costumes (§4.3) | §11.5 | Costumes suivants = mises à jour, sans date |
| Animations de construction (§4.4) | §9.4 | — |
| Personnalités, visages, tours, événements relookés (§4.5) | §5.6 | — |
| Budgets des effets (§4.6) | §11.5, §12.9 | — |
| Collection, quêtes, événements, fin de jeu, contenu de la semaine (§5) | §7.5, §17.1 | Piste de la semaine au lancement ; première période d'un compte de 8 à 14 jours (plus de date fixe du 2 janvier) |
| Rythme et hypothèses H1-H10 (§6) | §4.24.1 | **Remesuré** ; les clés de docs/09 sont reprises et complétées |
| Modules, données, messages, analytique, risques (§7) | §12.6, §12.7, §16, §19 ; `contract-changes.md` | — |
| Découpage et calendrier (§8) | §17 | **Supprimé** (décision n° 6) ; remplacé par « tout au lancement » |

#### Décisions du rôle design en v2.0 (écarts mesurés avec docs/09)

1. **Prix de la boucle ÷ 2 par Ascension** (docs/09 : × 1,6). Mesuré : avec × 1,6, le joueur de 2 h par jour passait **74,5 %** de son temps « sans but » aux jours 57-84 (plus long trou 2 h) ; avec ÷ 2 : 24,0 %. *Révisé après la critique (B1)* : ÷ 2 aux 4 premières Ascensions, puis × 0,32 (14,8 % aux jours 57-84, 11,7 % aux jours 113-140).
2. **Souvenir de gelée** (nouveau) : croissance ×3 tant que r < Record R. Mesuré : remontée de 10 jours ramenée à 5 (référence) ; assidu aux jours 2-7 : 20,6 % → 10,6 %.
3. **Plancher de `StartR` : décalage 4,7** (docs/09 : 8,9) et **Tremplin qui s'ajoute** au plancher (dans docs/09, il devenait inutile dès A3).
4. **Tapis Étoilé ouvert dès r = 6** (13 à r 6, 14 à r 7, 15 à r 8, 16 à r 9, 17-20 à r 10) au lieu de 2 niveaux à r = 10, 12, 14, 16 : la référence l'achète enfin (médiane 8 niveaux par boucle de r = 10 à 15, contre 0 à 1,5). Prolongement jusqu'à 40 essayé et écarté (aucun gain).
5. **Gants à 40 niveaux** (docs/09 : 30 ; le repli « 40 niveaux » de docs/09 devient la règle) : la fin des boucles de l'assidu a toujours un achat.
6. **Plopettes : une pression normale** (docs/09 : la moitié) et règle des 12 studs comptée à 75 % : 8 % des pièces au jour 7 (cible 5-15 % ; docs/09 mesurait 3,4 % avec ses valeurs).
7. **Croissance hors ligne arrêtée aussi à 120 s de croissance maximale** de l'objectif (nouveau) : supprime les boucles de 13-30 s commencées la veille.
8. **Les « boucles de 0 s » étaient une erreur de mesure** (journal « ascend » écrit avant « splorch » au même instant) : expliquées et corrigées (§4.24.1). Aucune boucle de 0 s ; aucune renaissance double.
9. **Total : 146 niveaux** (docs/09 : 136 ; +10 niveaux de Gants), tous au lancement. *Révisé après la critique (M3)* : **144** (les niveaux 3 et 4 de « Déco qui reste » sont retirés), plus 35 objets « Pour le plaisir ».
10. **Écran Améliorations** : la règle 19 de docs/09 (« seul le serveur dit ce qui est sorti ») devient « ce qui est ouvert » (plus de dates) ; l'écran se ferme au début de son propre Grand Splorch ou de sa Jelly Ascend (sinon les plafonds figés à l'ouverture seraient faux juste après).
11. **Atelier** : tout achat en Confettis demande un maintien de 0,6 s, même en ×1 (les Confettis sont rares).
12. **Première période de la piste de la semaine** : de la première connexion du compte au 2e lundi qui suit (8 à 14 jours), au lieu d'une date fixe.
13. **Maisonnette des Plopettes** à Z = 60, X = −28 dans le ranch (la prise réservée de la v1.3 reste réservée) ; l'**Observatoire** et le **kiosque de Big Plop** sont ajoutés à la carte (≈ 40 pièces).

#### Critique indépendante de la v2.0 (2 novembre 2026, soir) : décision par remarque

Critique : `scratchpad/v2/critique/critique-v2.md` (3 bloquants, 17 majeurs, 25 mineurs : 45 remarques). **Bilan : 45 appliquées (dont 6 adaptées, en écrivant pourquoi), 0 déjà couverte, 0 rejetée en entier ; 2 sous-points rejetés en partie, argumentés avec des chiffres (dans B1).** Simulation refaite après tous les changements d'économie (22 configurations, `scratchpad/v2/gdd/sim/out/v21/`, §4.24.1).

- **B1** (but proche du joueur de 2 h par jour au-delà du jour 84) — **appliquée** : facteur de prix par Ascension en table `PriceByA` = 0,5 pour A1-A4 puis **0,32** (la table de départ de la critique, 0,5 / 0,4 / 1/3, laissait le Tapis 12 à 1,00 de la boucle de A9 à A33 ; 0,3 et 0,33 essayés), « Déco qui reste » 3-4 retirés, étapes du record dans le jeu (non comptées), clés de porte sur 140 jours, §7.6 et §20.1 réécrits avec toutes les bandes, ligne « leviers écartés » corrigée (× 1/3 rejoué). Mesuré : assidu 10,6 / 15,5 / 16,1 / 16,5 / 14,8 / 13,9 / 11,7 % (jours 2-7 … 113-140), plus long trou p90 ≤ 14,9 min. **Sous-points rejetés en partie** : (i) la limite de 15 % aux jours 2-7 pour le joueur de **6 h par jour** (mesuré 17,8 %, puis 21,1 et 19,0 % : sous 30 %) : l'écart vient des boucles R9-R15 d'avant la 1re Ascension, qui tiennent les jalons de la référence (§4.24.1) ; (ii) « Tapis 12 entre 0,5 et 0,9 à chaque valeur de A » devient « chaque A entre 0,45 et 0,95, toutes les boucles record entre 0,5 et 0,9 » : 40 boucles par A et par profil de 10 joueurs (mesuré 0,58-0,87 pour l'assidu de A1 à A38, 0,64-0,93 pour la référence sur 140 jours, 0,45 au pire pour le joueur de 6 h par jour à A1).
- **B2** (débordements mesurés dans l'en-tête, la puce Menu, la ligne de la Cuve) — appliquée : pastille x 320-680 « Souvenir ×3 » (159 px au pire pour 288), puce Menu « MENU » fixe, ligne « Monte avec ton record » (263 px pour 540), titre « finit à x = 303 » (§10.7.3, §10.2, §11.5).
- **B3** (politique de texte fondée sur un comportement non mesuré) — appliquée et renforcée : `UI/Text` mesure le facteur réel (étiquette témoin) et compense dès le départ, `Text_policy.spec` joue les deux comportements, panneau TextProbe photographié sur la PS5 (tâche 1 du paquet P0), pire cas 1,5 pour les phrases, bandeau « 3 lignes à Medium, 2 à Largest » (§10.1, §10.7.3, §10.8 règle 9).
- **M1** (ne pas faire l'Ascension rend le jeu creux) — appliquée : carte Conseillé « Jelly Ascend », geste de Big Plop, `AscendDeclined`, profil « refuse 3 jours » (tient : 8,7 % au pire pour la référence, 17,0 % pour l'assidu), **focus sur « Oui »** après le maintien de 3 s (§4.27, §10.3, §10.7.4, §16.3).
- **M2** (avance du gros acheteur contraire au §8.1) — appliquée : textes vrais au §8.1 n° 10 et au §8.5 (15 à 22 % plus tôt ; +4 Record R au jour 28, +9,5 au jour 84), clé `spenderLeadTimeShare` ≤ 25 % bloquante (mesuré 22 %) ; la décision reste au propriétaire (§20.2 q. 8).
- **M3** (Atelier sans effet mesurable, « Déco qui reste » qui retire des achats) — appliquée : 12 décorations gardées au plus, effet concret de chaque ligne dans le bandeau, `atelierEffect` rapporté (l'Atelier retire maintenant 1,9 point de temps « sans but » à la référence, ±1 point à l'assidu).
- **M4** (Confettis morts) — **adaptée** : Confettis du Grand Splorch avec r compté jusqu'à 20, Grand Splorch sauté payé seulement par le Tremplin, « Pour le plaisir » étendu à 24 objets de Déco perso et aux Fanions dorés (puits **fini** plutôt qu'« infini » : des couleurs générées sans fin ne sont pas une récompense), affichage « Confettis gagnés » une fois tout acheté. Mesuré : ≤ 269 en poche jusqu'au jour 84 (référence 47 au plus), avant : 4 414 pour l'assidu.
- **M5** (l'Ascension se ressent comme une perte) — appliquée : tuile « ×3 à chaque boucle, pour toujours », ligne calculée « 9 fois plus vite jusqu'à ton record », suivi « Retour au record 4 / 15 », +10 Confettis et une carte au retour.
- **M6** (falaise au retour du record) — appliquée : Souvenir dégressif ×3 / ×2 / ×1,5 / ×1,25 ; `regainCliff` mesuré 1,2 (référence) et 2,1 (assidu), cible ≤ 4.
- **M7** (puce « Prochain achat » cachée et périmée) — appliquée : pastille Fame hors du HUD calme, puce visible avec la carte de la cible, cible recalculée après tout prestige.
- **M8** (« +5 % » des décorations faux) — appliquée, **1re option de la critique** (effet réel affiché par `UpgradeMath.effect`) ; la 2e option (multiplicateur à part, recommandée) est écartée avec un chiffre : −20 % de revenu dans les premières boucles à 10 décorations, contre les jalons de la v1.3.
- **M9** (chiffres romains et 3 notations) — appliquée : « Record 15 », « Boucle 3 », « Grand Splorch 15 / 15 » ; le romain reste un décor.
- **M10** (contenu et textes absents) — appliquée : Annexe B (40 objets de Déco perso, 8 cosmétiques de la semaine, habillages, ciel, paliers, selles, traînées, drapeaux, tenues, emotes, titres, 36 titres de R50 à R400, 12 Défis, 5 tours, textes nouveaux), noms mesurés.
- **M11** (notation « e » pour des enfants) — **adaptée** : suffixes jusqu'à 1e93 (« Tg ») au lieu de 1e63, parce que l'assidu atteint 1e75 au jour 140 ; couleurs par famille de suffixes.
- **M12** (clés de docs/09 retirées, `everyFamilyBought` intenable) — appliquée : `loopMaxGap` (bloquante pour la référence, rapportée pour l'assidu, choix écrit), `offlinePotShare` mesurée (médiane 0,42 à 1,91), `workshopAllDay`, configurations forcées A = 10/20/30/60 la nuit, `everyFamilyBought` redéfinie (≥ 80 % ; mesuré 96-100 %), spec `Soak_queue`.
- **M13** (une valeur « sans code » peut faire exploser l'économie) — appliquée : invariant de stabilité vérifié au chargement, `MaxR` / `MaxA` dans le modèle, « × 2,3 dès R16 » retiré des leviers.
- **M14** (coût de la porte et des captures) — appliquée : 20 joueurs par taille dans `check.sh` (≈ 3,5 min), 50 joueurs et 140 jours la nuit ; 24 états de capture dans `check.sh`, la matrice complète la nuit (25 min au plus).
- **M15** (piste inaccessible au joueur du week-end) — **adaptée** : 2 points par objectif comme proposé, mais **5** points par Défi (au lieu de 4) pour laisser 3 points de marge (27 possibles pour 24) ; Défis faisables dans le temps médian du joueur ; « Nourris Plop » seulement après 3 jours joués.
- **M16** (Petit Splorch fastidieux) — appliquée : maintien de 1,5 s sur la puce d'action spéciale, aperçu seulement au premier de chaque remontée, ligne rouge seulement si une ligne gardée est payable.
- **M17** (3e gabarit de tuile non spécifié) — appliquée : gabarit tuile 400 × 300 dans `UI/UpgradeCard`, règle 11 à 3 gabarits, boîte de la ligne d'explication.
- **m1** renumérotation du §8.1 — appliquée. **m2** `addConfetti` seul point d'entrée — appliquée. **m3** une définition du Petit Splorch — appliquée. **m4** étoile dessinée — appliquée. **m5** maintiens du §14 — appliquée. **m6** bloc du schéma v1 et fixture `v1.json` — appliquée (bloc marqué v1, v2 dans `contract-changes.md`, fixture au paquet P0). **m7** migration du Carnet, de `decorBuilds` et de la 1re période — appliquée. **m8** temps en ×2 des séances courtes — appliquée (2e option : cible écrite pour la référence, le reste rapporté ; raccourcir le bol pénaliserait le joueur qui joue le moins, déjà à R 16 au jour 28). **m9** ce que compte un Petit Splorch — appliquée. **m10** Fame de l'Ascension hors plafond — appliquée. **m11** lignes en lecture seule sélectionnables — appliquée. **m12** 22 appuis dans l'Atelier — **adaptée** (lignes groupées : 16 appuis, ↓ maintenu et stick droit ; pas de grille, qui aurait fait un 4e gabarit). **m13** rectangles réels du HUD — appliquée. **m14** un seul état et « 12/20 » — appliquée. **m15** dalle Tapis qui continue avec le Tapis Étoilé — appliquée. **m16** maintien de 0,6 s pour tout achat — appliquée. **m17** sieste comptée sur les intentions acceptées — appliquée (§4.28). **m18** mode photo visible des autres — appliquée. **m19** ordre et taille des boutons de la carte — appliquée. **m20** boîte des refus 600 × 120 — appliquée. **m21** `UIShadow` et dégradé radial dans le harnais — appliquée. **m22** fichiers de police — appliquée (paquet P0 ou spec « en attente »). **m23** portage de 300 s et « MENU » — appliquée. **m24** une renaissance à la fois — appliquée (le Grand Splorch d'abord ; squishy et « Filmer » dans « Détails »). **m25** « Migrer vers la dernière mise à jour » — appliquée (§18).
- **Décisions du rôle design pendant cette révision** (pas des remarques de la critique) : `shortestLoopSec` devient « ≤ 0,3 % des boucles sous 45 s, chacune ≤ 10 s après une fusion, jamais 0 s » (le joueur de 10 min par jour faisait 3 boucles sur 1 310 sous 45 s, toutes 2 s après une fusion) ; l'habillage « Atelier » du Carnet devient l'emote « Coup de maillet » (il faisait un 15e habillage) ; le total des niveaux passe de 146 à 144 ; la date du 10 décembre de la checklist (couche i) est retirée (décision n° 6).

#### Porte d'économie du lot A1 (5 novembre 2026) : trois réglages de `Balance`

La porte v2.0 jouée avec le vrai code (`tests/specs/EconomyPacing.spec.luau`, jeu de nuit `scripts/economy-nightly.sh`, 400 joueurs pour les clés de queue) a trouvé deux vrais problèmes ; réglés dans `Config/Balance` (journal docs/04 §21 et §27.12 A1-31, A1-32), le texte de ce document suit :

- **Pot de nuit de l'Atelier** 25 % → 30 % → 35 % devient **25 % → 28 % → 31 %** (§3, §4.19, §4.26 ligne 7, Annexe B) : le joueur de 10 min par jour recevait la nuit 2,09 fois sa séance (`offlinePotShare` ≤ 2) ; 1,87 maintenant.
- **Condition de l'Ascension** : 15, 20, puis + 4, et **+ 5 une fois toutes les 8 Ascensions à partir de la 11e** (57, 90, 123…) (§4.27) : avec + 4 seul, la boucle record raccourcissait à chaque Ascension (`ascendGapDays` à 9 jours pour la référence dès A11, 3 jours pour l'assidu dès A22).
- **Prix de la boucle** × 0,32 jusqu'à A10, puis **× 0,31**, et **× 0,29** aux Ascensions qui demandent un Grand Splorch de plus (§1, §4.6, §4.27) : sans eux, le Tapis Étoilé n'était presque plus acheté dans les boucles record tardives.

Tout ce qui précède A11 est inchangé. Conséquence pour le joueur de 2 h par jour : une Ascension tous les 5 jours, A = 28 au jour 140 (34,5 avant ; §4.24.1, question 9).

#### Lot B2 (6 et 7 novembre 2026) : écran Améliorations et HUD v2.0, ce que la fabrication a précisé

L'écran, le rail et le HUD v2.0 sont faits côté client (journal docs/04 §27.12, B2-1 à B2-64), derrière l'interrupteur `UpgradesScreen` : sans lui, le HUD et le menu de la v1.3 sont inchangés. Le texte de ce document suit :

- **Rail du menu** : le bouton « ! » d'une carte en attente reste, soit 9 boutons au plus ; le rail monte, puis l'écart se resserre (§10.2, §10.7.2).
- **Petit Splorch à la manette** : le maintien de ✕ de 1,5 s se fait sur l'entrée « Petit Splorch » du menu, pas sur la puce du HUD, parce qu'en jeu ✕ est le saut ; à la souris, un clic maintenu sur la puce (§10.2, §10.7.2).
- **Aucun caractère hors des polices** (règle 18, dans les deux états de l'interrupteur) : « environ » au lieu de « ≈ » dans la file (« 2e de la file · environ 0:40 »), cœur et étoile dessinés (jumeaux, amis, Fame), marque des minutes dessinée sous les indicateurs (§10.2).
- **Textes ajoutés** : noms courts de la puce « Prochain achat » (Tapis, Tapis Étoilé, Déco, Enclos, Lit, Gants, Monument, École), libellé « Petit Splorch » du menu, seconde ligne de « Monte avec ton record » (« Cuve 3/8 · palier 4/6 ») et son bandeau.
- **Carte du Conseillé** : icône de 80 (la pile du §10.7.4 fait alors 528 px), écart de 40 entre les cartes (3 × 432 + 2 × 40 = 1 376, contrat docs/04 §27.8).
- **Décorations en ×10 et Max** : la ligne montre le gain de tous les niveaux achetés, pas d'un seul (§10.7.8).
- **Remontée** : quand le Petit Splorch est prêt, le suivi garde « Retour au record » et « 4 / 15 » (état clé 24 du §10.8).
- **Captures de référence** : relevés de mise en page dans `check.sh`, images pour la relecture (§10.8).
- **Ouvert, décision demandée** : le budget de 3 000 objets d'interface pour toute l'interface (§12.9) n'est pas tenu quand tout est construit avec l'écran (3 751 mesurés, dont 1 219 pour l'écran, qui tient ses 1 400) ; les panneaux de la v1.3 en prennent déjà environ 2 500. Raccourci U, kiosque de Big Plop, « Dépenser d'abord » et dessin des Plopettes : lots I, B4, B3 et B5.

#### Lot B4 (7 novembre 2026) : le ranch qui évolue et le monde v2.0, ce que la fabrication a précisé

Le ranch qui évolue, l'éclairage et le monde v2.0 sont faits côté client (journal docs/04 §27.12, B4-1 à B4-75), derrière leurs interrupteurs (`RanchTiers`, `Monuments`, `DecoPerso`, `RanchSkins`, `Ambience`, `Workshop`, `StarMat`) : coupés, le monde, le ranch et la lumière sont ceux de la v1.3 (prouvé contre la version précédente : mêmes pièces du serveur, mêmes messages, même lumière), à la couronne du panneau près. Le texte de ce document suit :

- **Observatoire et kiosque dessinés par le client**, pas par le serveur : leurs interrupteurs changent en direct ; la carte du serveur reste celle de la v1.3 (§11.1, §11.4).
- **Prairie des copains** en (52, 0, −135,5), r ≈ 145 ; le serveur garde l'ancienne, que chaque client cache pour lui seul quand il dessine la nouvelle (§11.1).
- **Éclairage unifié** : écrit par le client tant qu'`Ambience` est ouvert ; le fichier de la place bascule à l'étape I (§11.3).
- **Détail réduit** d'un ranch : 9 pièces (tour, phare et couronne en 3 pièces), le chiffre du tableau des budgets (§11.5).
- **Socles de souvenir** seulement à partir du Record R 1 (§11.5).
- **Ciel des Ascensions** au-dessus du fond du ranch, hors de la colonne de la silhouette ; **anneau-soleil** du Squishy-Soleil derrière la silhouette (§11.5).
- **Placement** : 8 studs au moins de chaque dalle pour un décor posé au sol (plus large que les 6 studs du texte), prouvé pour les 16 ranchs.
- *(Relecture du lot B4)* **Kiosque de Big Plop** en (−32, 0, 24) au lieu de (−30, 0, 24) : l'échoppe dessinée mesure 4,25 studs de rayon (2,75 étaient déclarés) et son comptoir mordait sur le point d'apparition neutre de la place, où chaque personnage apparaît avant d'être placé dans son ranch (§11.1). Une 2e naissance mutée pendant les étincelles de la Cuve n'en ajoute pas et ne compte plus comme un dépassement du budget visuel (§11.5).
- **Couronne du panneau du ranch** : « ♛ » n'existe dans aucune des deux polices ; la couronne est dessinée, dans les deux états des interrupteurs (règle 18) ; « PRÊT ! » au bout du panneau quand le Grand Splorch est prêt.
- **Budget visuel mesuré** (16 ranchs entièrement construits, pire cas des halos : les 16 joueurs sur la place) : 1 711 pièces dessinées sur les 2 069 déclarées par le lot (le halo compté à part du ciel, la Prairie, le tas et l'anneau du Pot, les accessoires de la silhouette ; les Plopettes, la météo et les événements relookés restent aux lots B5 et A4) ; workspace du client ≈ 9 800 instances avec la carte et 2 500 pièces de squishies (plafond 15 000) ; aucune lumière ni `Highlight` de plus ; 6 h de robots sans un seul dépassement.
- **Non vu à l'image** : le monde 3D sur une vraie télé (prouvé par des tests : positions, budgets, idempotence), la lumière réelle sur PS5, la durée d'une image sur PS4 et Xbox One (à mesurer à l'étape I).

#### Lot B5 (10 et 11 novembre 2026) : la vie des squishies, ce que la fabrication a précisé

Les personnalités, les Plopettes à l'écran, les spectacles, la météo, la place en fête, le mode photo et le zoom des jumelles sont faits côté client (journal docs/04 §27.12, B5-1 à B5-61), derrière leurs interrupteurs (`Personalities`, `Helpers`, `JellyAscend`, `PetitSplorch`, `Weather`, `Fete`, `PhotoMode`, `Hearts`), tous coupés dans la configuration livrée : interrupteurs coupés, le jeu reste la v1.3 (preuve contre la version envoyée au propriétaire : mêmes envois à l'octet près, mêmes écritures de `Lighting`, mêmes connexions ; seules différences : les étoiles dessinées, la selle de la monture dessinée et deux défauts de la v1.3 corrigés, B5-8, B5-9, B5-56).

- **§5.6 Personnalités** : 18 saynètes et 5 tours ; une saynète toutes les 8 à 20 s par squishy proche (≤ 40 studs), 6 au plus (3 en qualité réduite), jamais à plus de 2 studs de sa place, la cible du jeu lit toujours la place de repos ; les 6 visages sont faits avec les pièces existantes ; les yeux « bébé » ont 3 versions (A = v1.3 ; B et C pour le test M14 du propriétaire, une constante) ; « Nouveau tour : … ! » est un message, pas une carte (budget d'interface).
- **§4.28 Plopettes** : 5 pièces chacune (Pim et Plume simplifiées), dessinées seulement dans le ranch courant et ses 2 voisins ; le saut atterrit à `tPress` ; le « pop » ne joue que si le miroir montre la pression (un saut abandonné atterrit en douceur, sans message) ; sieste en rangée devant la porte de la maisonnette avec un seul « z ».
- **§9.4 Spectacles** : Petit Splorch (2,5 s, coupure dure 4 s) montré pareil chez le propriétaire et ses voisins (copie du squishy public du ranch) ; Jelly Ascend (10 s, coupure 12 s, caméra du héros sauf en Mouvement réduit) ; Pluie d'étoiles pour le héros de l'Ascension seulement ; Chantier de Big Plop (3 coups de maillet, coupure 6 s, jamais pendant un grand spectacle) ; Palier envoyé par `RanchService` au propriétaire quand son Tapis monte d'un palier jamais vu dans la séance (lot I, étape 5) ; 6 emotes de la v2.0 en effets courts au-dessus de la tête.
- **§7.5 Mode photo et jumelles** : entrée par la ligne « Mode photo » en bas des *Réglages* (bouton « Cheese ! ») ; sticks pour bouger et tourner, L2 / R2 pour zoomer, □ pour 4 filtres, ○ ou ✕ sur « Quitter » pour revenir au jeu en un appui ; l'aide s'efface après 3 s, le bouton reste ; l'écran se cache seulement chez le joueur, le personnage reste visible ; zoom des jumelles : vue au-dessus du portail regardé, la carte n'est jamais couverte, △ ouvre le menu par-dessus et ○ le referme.
- **§10.4 Manette** : aucun bouton du mode photo ou des jumelles n'achète, ne vend, ne boope ni ne lance un prestige (promenades à la manette dans les specs) ; aucun bouton nouveau (L3 / R3 restent libres).
- **§11.5 Budgets** : 3 lignes ajoutées au tableau « Budgets ajoutés » (place en fête 40 pièces et 20 particules, copies des spectacles 96, petit Big Plop 17) ; la météo partage ses 60 particules par seconde avec les flocons d'hiver ; 6 h de jeu simulé avec tous les interrupteurs ouverts : aucun budget dépassé, aucune fuite (B5-57).
- **Non vu à l'image** : toute la 3D du lot (saynètes, visages, Plopettes, spectacles, particules, fête, vues de la caméra) n'a été prouvée que par des specs de structure ; à regarder par le propriétaire sur une vraie PS5.

#### Lot B3 (9 et 10 novembre 2026) : écrans de renaissance et de méta, ce que la fabrication a précisé

Les aperçus de renaissance, Mon style, la piste, les Défis, le Carnet, les Records, la maîtrise, le halo, les cartes « Nouveau », les jumelles et les cœurs sont faits côté client (journal docs/04 §27.12, B3-1 à B3-73), derrière leurs interrupteurs (`JellyAscend`, `PetitSplorch`, `WeeklyTrack`, `Carnet`, `DecoPerso`, `RanchSkins`, `RecordR`, `Mastery`, `Hearts`, `Confetti`) que le serveur annonce au client dans `EventState` : coupés, chaque écran est celui de la v1.3 (prouvé contre la version précédente : mêmes messages, mêmes intentions, mêmes rectangles), sauf les glyphes de la règle 18. Le texte de ce document suit :

- **Glyphes dessinés** (règle 18, dans les deux états) : étoile dessinée après le nombre sur les badges du Squishydex, cœur et coche dessinés dans les cases du Ranch, coches dessinées de *Plop* et de l'*Accueil*, flèches dessinées du choix de l'envol et de l'aperçu des tenues ; « Jumeaux », « Emote : croix gauche » et « environ … pièces » en mots (§10.3).
- **Aperçu du Grand Splorch v2.0** : les colonnes de « Détails » disent ce que la v2.0 garde et remet à zéro (§4.15, §10.3) ; onglets « Grand Splorch » / « Jelly Ascend » quand les deux sont prêts ; carte « Prêt à monter ? » focus sur « Oui » (§10.6).
- **Mon style** tel que fait : liste des sortes et grille de 5 cases, palettes et coussins en plus, halo dans *Réglages* (§10.3) ; plan de Déco perso, choix des objets de la bonne taille (§10.6).
- **Squishydex** : onglet *Records* et colonne de la maîtrise ; rouvert depuis le menu, toujours sur les *Espèces* (§10.3, §10.6).
- **Objectifs** : onglets *Cette semaine* (piste, Défis, cosmétique de la semaine et les 2 suivants, pas toute la rotation) et *Carnet* (le compte va jusqu'au prochain objet, Déco perso comprise) ; paliers en lecture seule (§10.3, §7.5).
- **Livre des records** : un compteur de 6 chiffres s'abrège dès 100 000 (« 999K », règle du §4.2), comme partout (§17.1).
- **Manette** : L1 / R1 font suivre la sélection à l'onglet affiché, même depuis un onglet vide (dans les deux états : avant, la sélection restait sur le bouton de l'onglet quitté) (§10.6).
- **Écran de retour** : la puce « Prochain achat », la barre du MEGA et la jauge se cachent le temps de l'écran, comme sous un panneau (la carte les coupait à mi-hauteur) ; la pastille des jumeaux du rail montre son cœur à gauche du nombre, plus dessus ; un squishy boopé que personne n'attrape et qui rentre tout seul n'annonce plus « +1 Fame, pièces, bébé laissé à… » (rien n'est gagné : la carte « revient toujours ! » garde son titre et ses boutons, sans ligne de gains) (dans les deux états) (§10.2, §10.6).
- **Jumelles** : invite □ « Regarder » devant le portail d'un voisin, un seul bouton « Donner un cœur », aucun nom, ○ ramène au jeu ; la caméra ne zoome pas encore (lot B5) (§7.5, §10.6).
- **Budget d'interface** : avec toutes les fenêtres de la v2.0 construites, l'interface entière compte 4 631 objets (écran Améliorations 1 219, chargement 1 506) : les 3 000 du §12.9 ne tiennent pas ; décision du budget demandée au lot I (B2-13).
- **Non vu à l'image** : la sensation sur une vraie manette PS5 (maintien de 3 s, carte, plan de Déco perso, distance de l'invite des jumelles) : à valider par le propriétaire.

#### Lot I (11 et 12 novembre 2026) : l'ouverture, ce que l'intégration a précisé

Les 23 interrupteurs de la v2.0 sont ouverts dans la configuration livrée, par groupes et dans l'ordre (données, progression, méta, écrans, monde et vie) ; **le jeu que joue le propriétaire est la v2.0** (journal docs/04 §27.12, I-1 à I-55). Chaque interrupteur, sauf le schéma v2, reste coupable en direct (LiveOps) et son chemin coupé reste prouvé.

- **Sauvegardes** (§12.6) : chaque profil de la v1.3 passe en v2 à son premier chargement, une seule fois, sans rien perdre (pièces, squishies, cosmétiques, records, réglages) ; le schéma v2 ne se coupe jamais ; une place plus ancienne ne doit plus jamais être publiée ; publier avec « Shut down all servers » (docs/05).
- **Coupure d'urgence** : si LiveOps coupe tout sauf le schéma v2, le jeu de base joue sur les profils v2 sans qu'aucune intention v2.0 ne réponde ni qu'aucun champ v2 ne change (prouvé à 16 joueurs).
- **Noms figés** : la palette de la semaine s'appelle `peachPalette` partout ; la date de la dernière Ascension est gardée (`ascendDay`) pour « AscendDone » (§16).
- **Raccourci U** (clavier) et puce « Prochain achat » : l'écran Améliorations ouvert depuis le jeu se ferme d'un ○ vers le jeu (§10.6) ; fanions ★ des décorations gardées par l'Atelier jusqu'à 12 (§4.26).
- **Textes** : en français, « studs » devient « pas » (« Aimant à pièces : 5 → 8 pas ») ; la carte d'un nouveau Record R montre chacun de ses déblocages ; aucune clé v2.0 n'attend plus sa preuve d'affichage.
- **Budget d'interface** (§12.9) : 4 150 objets sur une séance normale (écran Améliorations construit une fois, les autres panneaux rendus à la fermeture).
- **Mode photo** : les textes flottants du monde (« z » des Plopettes et des squishies, étiquette du Chantier) se cachent avec le HUD ; une carte qui arrive attend la sortie (§7.5).
- **Croix de la v1.3** : les 3 signaux de base montrent enfin une bulle-icône dessinée au-dessus du joueur pendant 2,5 s (§6.5).
- **Éclairage de la place** : `LightingStyle = Soft`, `PrioritizeLightingQuality = false` dans le fichier de la place (§11.3, §12).
- **Big Plop sur sa scène pendant la danse** (§5.3, §9.4) et **événements relookés pour la télé** (§5.6) : pas faits ici, laissés au lot de QA final (3D à voir sur une vraie console).
- **Non vu à l'image** : toute la 3D des lots B4 et B5, la caméra, les sons (encore muets pour la v2.0), les vibrations et le vrai rendu des polices : liste du premier essai sur PS5 dans docs/05 §7.

#### Ce qui reste ouvert (aussi au §20.2)

- **Avance du gros acheteur** avec l'Ascension (chiffres refaits après la critique : 15 à 22 % plus tôt ; +9,5 Record R au jour 84) : +4 Record R et +1 Ascension au jour 28 (≈ 20 % plus tôt, comme en v1.3) ; « 1 à 2 R » tient sans Ascension et avec le ×2 Pièces seul (question 8).
- **Cadence de l'assidu** : une Ascension tous les 4 à 5 jours (A = 34,5 au jour 140 ; tous les 5 jours et A = 28 depuis la porte d'économie du lot A1) ; est-ce trop vite ? (question 9).
- **Clé `shortestLoopSec` de la politique « Conseillé »** (seule clé rouge du jeu de nuit de la porte d'économie, 5 novembre 2026) : 2 boucles sur 50 463 (400 joueurs de référence) finissent en moins de 45 s, 10,7 et 10,8 s après une fusion (limite : ≤ 10 s) ; ces deux boucles sont pleines (un achat toutes les 2 s, aucune croissance hors ligne) et la cible y est atteinte 8,2 à 8,3 s après la fusion, le reste étant le geste du Petit Splorch (2,5 s) et l'attente de la pression suivante. **Décidé (chef de projet, 5 novembre 2026, docs/04 §27.12 A2-7)** : l'intention de la clé est le temps que le joueur attend après une fusion avant d'atteindre la cible ; le geste du Petit Splorch et l'attente de la pression suivante sont du temps du joueur, pas du jeu. La clé se mesure donc de la fusion à l'instant où la cible est atteinte ; la limite (10 s, aucune boucle au-delà) est inchangée, aucune valeur de `Balance` n'a changé. Avec cette mesure, la clé est verte (porte de check.sh et cas `advisor` du jeu de nuit).
- **Non simulé** : pet-sitting et amis, position réelle du joueur (règle des 12 studs), Squish Parties achetées par d'autres, maîtrise et jalons géants, deux séances par jour, file du serveur avec 8 vétérans (`queueWaitNewcomer`, robots).
- **À mesurer sur l'appareil** : les 4 facteurs de `PreferredTextSize` (photo du panneau TextProbe sur la PS5, critique B3 ; la compensation de `UI/Text` protège les libellés en attendant), les vraies largeurs de texte (`TextFit_all`), le vrai style (ombres, dégradés radiaux) sur PS5 et PS4, la performance PS4 des ≈ 2 040 pièces de décor (M6), le ressenti des enfants (M14 : Max, maintiens de 0,6 s et 3 s, yeux « bébé »).
- **Fichiers d'autres rôles à changer avec cette version** : `default.project.json` (éclairage), `Config/*`, `Remotes`, `Types`, `Strings`, schéma v2 : liste exhaustive dans `contract-changes.md` ; découpage en paquets parallèles dans `packages-proposal.md` (dossier de travail `scratchpad/v2/gdd/`).

### Version 1.3 : les 42 remarques qui n'étaient pas parvenues (fin de la critique console, critique technique et économique)

Le texte des critiques donné aux versions 1.1 et 1.2 était coupé à 40 000 caractères : la critique console et UX s'arrêtait à sa 3e remarque, et la critique technique et économique (2 points bloquants, 12 majeurs, 8 mineurs) n'était jamais arrivée. La version 1.3 traite ces 42 remarques une par une. Les directives du propriétaire passent avant les critiques : les remarques qui supposaient un téléphone ou un écran tactile sont sans objet (décision du 1er novembre 2026). Bilan : **31 appliquées**, **8 déjà couvertes** par les versions 1.1 et 1.2, **3 sans objet** depuis le passage à la console, **aucune refusée en entier** (les parties refusées de remarques appliquées sont expliquées plus bas). L'économie a été **resimulée** avec toutes les nouvelles règles (§4.24).

#### Ce qui a changé
- **Économie** : prix des dalles de la boucle × 3,5^R au lieu de × 2^R (§4.6) ; objectifs de Grand Splorch × 2,6 au lieu de × 2,7, nouvelle table (§4.15) ; croissance hors ligne 30 % au lieu de 50 %, arrêtée à 90 % de l'objectif (§4.19) ; Lit douillet à 25 M pièces dès R = 3 (§4.6) ; jauge du serveur : seules les pressions PERFECT comptent, objectif 600 × joueurs actifs, sieste de 20 min après chaque fête (§4.23) ; plus de boost dans les objectifs du jour, boost du bol de 5 min chaque jour (§7.3, §7.4) ; naissances de la Cuve dans la Boîte à dodo quand les enclos sont pleins (§4.9) ; cadeaux de Grand Splorch en pièces plafonnés à 10 par jour (§4.15) ; simulation refaite : boosts calculés d'après les règles (la version 1.2 donnait 95 % du temps en ×2), vraies parts d'un serveur de 4, 8 et 16 joueurs, moteur par événements, nouveaux jalons de santé de l'économie (§4.24).
- **Abus à plusieurs comptes** : bébé ≤ 0,5 × le plus gros du receveur, mutation rare jamais copiée (§4.21.3) ; « Héros » et retour = 1 h et 30 min de croissance, une fois par squishy et par jour (§4.21.3) ; pet-sitting à 2 s de revenu, 100 par jour, 20 par ami pour « Plus serviable » (§6.4).
- **Réseau et anti-triche** : captures vérifiées à l'instant de l'appui (`Catch(id, tClient)`, historique des positions validées, distances à plat) (§12.5) ; bond = crédit de 12 studs rétroactif, un par 4 s (§12.8) ; monture : hauteur de saut connue du contrôle de déplacement, portées en XZ, écart vertical depuis les pieds (§4.12, §12.8) ; message `PetPress` (§12.7) ; N actifs pour le MEGA et la jauge (§4.22) ; Grand Splorch refusé pendant une fuite, aucune clôture pendant l'attente, attente affichée juste (§2.4, §4.15).
- **Données** : compteur de croissance du ranch au lieu d'une heure par squishy (§12.3, §12.5) ; bonus de famille gagnés pour toujours (`dex.fam`), nouvelles espèces en nouvelles familles, rotation du MEGA sur les espèces publiées (§4.17, §5.1) ; `moon.lastSession`, plafonds de pet-sitting, `gd` par squishy, tenue portée seulement dans le squishy, champ réservé `packs`, test d'aller-retour JSON d'un profil plein (§12.6) ; classements en entiers codés (§6.9) ; analytique cumulée par tranche de 5 min, ≤ 10 requêtes par joueur et par minute (§16).
- **Console et télé** : achat d'une dalle en restant 0,6 s dessus, dalles à 8 studs de tout point d'action, rangée Z = 67 (§4.6, §11.2) ; textes du monde en px TV (§10.2) ; spectacle complet d'un Grand Splorch des autres au plus toutes les 3 min (§4.15) ; vibrations : rien sur une pression ordinaire, une seule impulsion de sirène, `squishyBack` au lieu de `booped` (§10.5) ; bol en 2 s (§4.20) ; flèches vers le Golden et la créature attrapable la plus proche pour tous (§10.2) ; fiche par espèce au Squishydex (§10.3) ; ○ dans le bon ordre (§10.4) ; clavier : M pour le menu, raccourcis directs, sac à objets coupé (§10.4) ; suffixes internationaux (§4.2) ; carte du clip seulement si la capture a réussi (§9.5).
- **Monétisation** : paquets de pièces retirés du lancement (§8.3) ; Squish Party croisée = fête prolongée, minutes non jouées rendues à la fermeture du serveur (§8.3) ; ×2 Pièces appliqué une seule fois (§4.1, §8.2).
- **Monde** : murs invisibles des clôtures, du bord et coiffes des maisons à **30 studs** (décision du contrat d'architecture, docs/04 §3.1 et §20 n° 21), au lieu des 12 studs des clôtures en v1.2 (§6.3, §11.1, §11.2).

#### Décision par remarque

| Remarque | Décision | Où |
|---|---|---|
| C2-3 caméra qui cadre seule | Déjà couverte | v1.2 §10.4 (« La caméra ne bouge jamais toute seule »), Annexe A, journal v1.1 (« Caméra » ; option refusée) |
| C2-4 visée du bond (18 studs pour 12) | Déjà couverte | v1.2 §4.12 (position future, 16 studs, ±40° autour du stick, jamais la caméra, capture à l'atterrissage, tampon de 0,25 s, marqueur à 20 %) et §10.4 |
| C2-5 squishies non cliquables (`CanQuery`) | Déjà couverte | v1.2 §10.4 (clic par projection à l'écran) et §5.2 ; la partie tactile est sans objet |
| C2-6 fenêtre PERFECT et retard des télés | Déjà couverte | v1.2 §4.7 ([−0,08 ; +0,20] s), §4.22 ([−0,12 ; +0,28] s), test M11 |
| C2-7 cartes qui prennent la manette | Appliquée | Déjà en v1.2 §10.3 (une carte à la fois, seule la carte du choix est bloquante et s'ouvre au calme, garde de 0,6 s) ; ajouté : carte du clip seulement si `StartVideoCaptureAsync` réussit (§9.5) |
| C2-8 HUD du téléphone | Sans objet (console) | Aucune disposition tactile (§10.1) |
| C2-9 tailles tactiles | Sans objet (console) | Minimums télé du §10.1 |
| C2-10 achats sans le vouloir sur les dalles | Appliquée | §4.6 (0,6 s sur la dalle), §11.2 (règle des 8 studs, rangée Z = 67), §3, §9.4, §12.3, §12.10 |
| C2-11 trop de Grands Splorch pour les spectateurs | Appliquée | §4.15 (spectacle complet au plus toutes les 3 min, version courte), §6.7 et §10.2 (APPLAUDIR jamais en poursuite, maintien ou fenêtre), §2.4 (attente = place × 20 s + spectacle en cours), §12.10 |
| C2-12 textes du monde illisibles | Appliquée | §10.1, §10.2 (*Textes du monde*), §3, §4.6, §9.4, §11.1, §11.2, §12.10 couche d |
| C2-13 carte de la cible trop petite | Déjà couverte | v1.2 §10.2 (680 × 96, nom en 36 px, ligne en 28 px, affichage seul) |
| C2-14 chemins manquants à la manette | Appliquée | Déjà en v1.2 §10.2-§10.6 (Réglages dans le menu, △ sur GRAND SPLORCH, HUD jamais sélectionnable) ; ajouté : ordre de ○ en portant, ○ vide d'abord une sélection multiple (§10.3, §10.4) |
| C2-15 bannières et messages qui se chevauchent | Déjà couverte | v1.2 §10.2 (emplacement de message unique, colonnes vérifiées aux 3 résolutions, APPLAUDIR à la place de GRAND SPLORCH) ; la partie tactile est sans objet |
| C2-16 vibrations trop nombreuses ou négatives | Appliquée | §10.5, §9.4, §4.21.2 |
| C2-17 maintien de 5 s au bol | Appliquée | §4.20, §7.3, §9.4, §10.4, §12.7, §12.10, §14 (2 s) |
| C2-18 « jouable à une main » au téléphone | Sans objet (console) | Pas de tactile ; M9 réécrit pour la PS5 en v1.2 ; §14 (une touche par action) |
| C2-19 clavier : Tab, sac à objets, survol | Appliquée (survol refusé) | §10.4, §10.2, §0, §3 (M, raccourcis directs, sac coupé) |
| C2-20 grille 26 × 9 du Squishydex | Appliquée | §10.3 (fiche par espèce) |
| C2-21 suffixes français | Appliquée | §4.2, §15 ; question 3 tranchée |
| C2-22 flèches pour les joueurs Cozy | Appliquée | §10.2 |
| C3-1 monture et contrôle de déplacement (bloquant) | Appliquée | Déjà en v1.2 §4.12 (taille fixée par la selle) et au contrat (`setRootOffset`, sol pur, solides à 30 studs) ; ajouté : hauteur de saut, portées à plat, écart depuis les pieds, tests par selle (§4.12, §12.5, §12.8, §12.10, §18 M3) |
| C3-2 Squishydex en bits (bloquant) | Appliquée | Débordement déjà corrigé en v1.1 (§12.6, tableaux denses) ; ajouté : `dex.fam`, règle des nouvelles familles, rotation du MEGA, bonus « par espèce », test à 64 espèces (§4.3, §4.16, §4.17, §5.1, §12.6) |
| C3-3 simulation fausse | Appliquée | Écart de la v1.0 déjà corrigé en v1.1 ; v1.3 resimulée, objectif × 2,6, jalon du jour 14, politique exacte (§4.15, §4.24, Annexe A) |
| C3-4 inflation des pièces | Appliquée | §4.6 (× 3,5^R), §4.24 (jalons de santé), §16 |
| C3-5 prestige porté par le hors ligne | Appliquée | §4.19, §4.6, §4.15, §4.24, §7.2, Annexe A |
| C3-6 paquets de pièces | Appliquée | §8.3 (retirés), §0, §4.1, §4.15, §8.1, §8.4, §10.3, §12.6, §13, §17.2, §19, Annexe A ; question 1 tranchée |
| C3-7 capture vérifiée « maintenant » | Appliquée | §12.5, §12.3, §12.7, §4.11, §4.12, §4.21.4, §18 M10 |
| C3-8 bond sans crédit de déplacement | Appliquée | §12.8, §4.12, §12.7, §12.10 |
| C3-9 hasard payant par les pièces | Déjà couverte | v1.1 et v1.2 §4.6, §4.9, §8.1 n° 1, Annexe A (Cuve donnée par R) ; v1.3 précise la réponse « non » au questionnaire (§8.1 n° 9, §18) |
| C3-10 classements en entiers | Appliquée | Déjà en v1.1 §6.9 (plus de classement de taille) ; ajouté : codage entier avec égalité au premier arrivé (§6.9, §12.8) |
| C3-11 bébés, Héros et pet-sitting farmés | Appliquée | §4.21.3, §4.5, §4.25, §6.4, §6.9, §9.4, §12.8, §12.10 |
| C3-12 jauge et ×2 trop fréquents | Appliquée | §4.23, §4.7, §4.24, §4.25, §7.3, §7.4 |
| C3-13 Squish Party en file mémoire | Appliquée | §8.3, §4.25, §12.10 |
| C3-14 budget de l'analytique | Appliquée | §16 |
| C3-15 calcul paresseux par squishy | Appliquée | §12.3, §12.5, §12.6 (déjà choisi par le contrat, docs/04 §8.3) |
| C3-16 détails du schéma | Appliquée | §12.6 (tenue, `moon`, réglage du serveur privé, aller-retour JSON) |
| C3-17 pet-sitting sans message, position du squishy | Appliquée | §12.7 (`PetPress`, déjà au contrat), §4.7, §6.4, §9.3 |
| C3-18 N du MEGA et absents | Appliquée | §4.22, §4.23, §16.3 |
| C3-19 Cuve bloquée quand les enclos sont pleins | Appliquée | §4.9, §4.14, §3 |
| C3-20 hypothèses de la simulation | Appliquée | §4.24, §4.15, §4.25, §12.10 |
| C3-21 portail et groupes de collision, harnais | Déjà couverte | v1.2 §6.3 et §11.2 (membrane solide seulement chez chaque client, aucun groupe par propriétaire) ; harnais : voir le contrat |
| C3-22 file du Grand Splorch et P | Appliquée | §4.15, §4.1, §8.2 |

#### Ce qui a été refusé ou adapté, et pourquoi
- **○ « Fermer » sur les cartes non bloquantes** (C2-7) : en jeu, ○ veut dire Prendre / Poser ; la carte se range seule après 8 s et △ l'ouvre.
- **Visée au survol de la souris** (C2-19) : un curseur posé au milieu de l'écran aurait remplacé la cible automatique pendant qu'un joueur presse E (« les squishies prêts d'abord ») ; le clic fixe toujours la cible 4 s, par projection à l'écran.
- **Facteur 2,9 des objectifs** (C3-3) : il était calculé sur les valeurs de la version 1.0 ; avec les règles de la v1.3, × 2,6 tient les jalons.
- **Prix des dalles en secondes d'un « revenu de référence »** (C3-4) : la variante simple × 3,5^R donne le même résultat, se calcule à partir de R seul, sans champ sauvegardé, et se teste mieux.
- **Lit douillet « 25 M ou R = 3 »** (C3-5) : les deux à la fois ; à prix fixe, seul le moment du déblocage compte vraiment.
- **Objectif de la jauge 800** (C3-12) : 600, car les naissances, captures et fusions comptent toujours ; la sieste plafonne de toute façon le ×2 à 5 min toutes les 25 min.
- **Champ `party.pending`** (C3-13, C3-16) : une fête croisée prolonge la fête en cours ; rien n'attend en mémoire, rien à reprendre ailleurs.
- **Second compteur de croissance sans boost** (C3-10, C3-15) et **codage log10 des tailles** : il n'y a plus de classement de taille depuis la version 1.1.
- **Garder les paquets de pièces avec des protections** (C3-6) : retirés du lancement ; leur retour demanderait le porte-monnaie et le devis décrits au §8.3.
- **Sortir le coussin de la grille des enclos** (C2-10) : la grille des places commence à Z = 16 ; le coussin (Z = 10) est déjà hors des places, la zone des enclos est réécrite Z 12 à 44.

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
  - ranchs protégés par la poussée du serveur ; mur invisible de 12 studs sur les clôtures (30 studs depuis la v1.3, décision du contrat d'architecture) ; membrane du portail solide seulement chez chaque client, comme confort (§6.3) ;
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

La version 1.0 a été relue par des critiques indépendants. Ce journal répond aux deux critiques détaillées que nous avons reçues : **sécurité des enfants et des parents** (1 point bloquant, 14 majeurs, 9 mineurs) et **console et ergonomie** (1 point bloquant et 6 majeurs détaillés ; la suite de cette critique nous est parvenue coupée, ses autres points sont traités d'après son résumé : HUD du téléphone, tailles tactiles, cartes qui prennent la manette ; la phrase coupée sur la capture vidéo est couverte par la règle des cartes non bloquantes, §10.3, et, en v1.2, par la protection de `CaptureService` sur console, §9.5). La fin de la critique console (à partir de sa 3e remarque) et toute la troisième critique (technique et économie, avec 2 points bloquants) nous sont parvenues après la version 1.2 : elles sont traitées une par une par la **version 1.3** (plus haut). Le concept approuvé (jury §8) est gardé ; les écarts sont listés à l'Annexe A.

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

*(v2.0)* La liste à jour (questions 1 à 9) et les 6 décisions par défaut sont au **§20**.
