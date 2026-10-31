# Comet Conga — Rapport qualité avant publication

> **Document 06.** Établi le 31 octobre 2026 à 22:10 UTC, sur le commit `e951d5e` (« QA tour 4 »), arbre de travail propre (seuls les documents 05 et 06 étaient en cours d'écriture).
> Pour le propriétaire du jeu : ce rapport dit **ce qui est prouvé**, **ce qui ne peut l'être que dans Roblox Studio**, et **ce qu'il reste à décider**. Guide de publication : [`05-guide-publication.md`](05-guide-publication.md).

## En bref

| Question | Réponse |
|---|---|
| Le jeu est-il complet ? | Oui pour la version 1.0 du GDD (§15.1) : île, boucle complète, progression, événements, social, boutique, FR/EN, téléphone, PC et manette (PS5 / Xbox) |
| La vérification complète passe-t-elle ? | **Oui** : `./scripts/check.sh` → « ✅ Tout est vert. » (§1) |
| Combien de tests automatiques ? | **1 396 tests**, dans **89 fichiers de tests**, **0 échec** |
| Qu'est-ce qui n'est pas encore prouvé ? | Ce que seul le vrai moteur Roblox montre : rendu, physique, vraies sauvegardes et vrais achats, serveur avec 12 vrais joueurs, tenue des textes, aspect des particules, confort sur téléphone, rendu sur téléviseur (§4) |
| Que reste-t-il à faire à la main ? | Le plan de test dans Studio (§5) et les réglages de publication ([`05-guide-publication.md`](05-guide-publication.md) §12) |
| Y a-t-il des décisions à prendre ? | Oui, 7 questions de design (§7) |

---

## 1. Résultat de la vérification complète

Commande : `./scripts/check.sh`, lancée le 31/10/2026 à 22:05 UTC, durée 4 min 47 s, code de sortie 0.

| Contrôle | Outil | Résultat |
|---|---|---|
| Formatage du code | StyLua | Conforme |
| Analyse du code (erreurs probables, mauvaises pratiques) | Selene | **0 erreur, 0 avertissement**, 0 erreur de lecture |
| Tests automatiques | Lune (`tests/run.luau`) | **1 396 réussis, 0 échoué, 0 fichier de test non chargé** |
| Construction du jeu | Rojo 7.7.1 | `build/Game.rbxl` construit |
| Contrôle du fichier construit | `scripts/verify-place.luau` | Structure valide : 1 Script serveur, 2 LocalScript, 113 ModuleScript |

Lors des validations de publication des tours 3 et 4, la suite complète a été relancée deux fois de plus pour repérer des tests instables (résultat qui change d'une exécution à l'autre) ; ceux trouvés ont été corrigés (horloge réelle de la limite de débit, ordre de parcours des tables).

## 2. Taille du projet et des tests

| Partie | Fichiers | Lignes |
|---|---|---|
| Serveur (`src/server`) | 36 | 15 373 |
| Client (`src/client`) | 47 | 30 516 |
| Partagé (`src/shared`) | 32 | 9 336 |
| Écran de chargement (`src/first`) | 1 | 740 |
| **Total du jeu** | **116** | **55 965** |
| Tests (`tests/`, dont harnais et simulation) | — | 52 164 |

Tous les modules du jeu sont en Luau `--!strict` (typage strict).

| Famille de tests | Fichiers | Tests | Exemples |
|---|---|---|---|
| Tests unitaires et de services | 40 | 839 | `Formulas`, `SnipRules`, `EventClock`, `CongaService`, `EconomyService`, `DataService`, `MonetizationService`, `Panels`, `HUD`, `Contract` |
| Tests de correction (un par défaut trouvé en QA) | 39 | 429 | `Fix_r3_serveur_3_data`, `Fix_r4_serveur_3`, `Fix_r4_partage_4`… |
| Console et manette | 5 | 82 | `Console`, `Console_input`, `Console_hud`, `Console_panels`, `Console_release` |
| Intégration (jeu entier) | 3 | 32 | `Boot` (serveur de 12 joueurs), `ClientGame` (partie rejouée dans le vrai client), `ClientBoot` |
| Harnais de test lui-même | 2 | 14 | `harness/Harness`, `harness/Wire` |
| **Total** | **89** | **1 396** | |

---

## 3. Comment le jeu a été construit et vérifié

Historique tiré de `git log` (34 commits jusqu'à `e951d5e`, heures UTC).

| Étape | Quand | Ce qui a été fait |
|---|---|---|
| **Socle** | 30/10, 22:28-23:06 | Outils (Rojo, Selene, StyLua, Lune), **harnais de test** qui simule Roblox hors de Roblox, skills du projet, achats à reçus idempotents, prix lus à l'exécution, analytics, décor en formes simples, éclairage du crépuscule, logique de la file |
| **Conception** | 30/10, 22:34-23:24 | Étude de marché (docs/01), GDD complet (docs/02), choix entre 3 concepts par un jury (docs/03) |
| **Contrat d'architecture** | 31/10, 00:15 | docs/04 : chaque module, ses fonctions, ses messages réseau, ses données sauvegardées, et **quel lot possède quel fichier** (75 fichiers) |
| **Fondations** | 31/10, 01:04 | Logique pure testée (formules, horloge commune, règles de coupe, **simulation économique** de 200 joueurs sur 28 jours) et monde de Lumora |
| **6 lots** | 31/10, 05:01 | Cœur conga, économie, événements et social, rendu client, HUD, panneaux : chaque lot **implémenté puis relu** par un autre ingénieur, sur des fichiers séparés (73 fichiers, 48 754 lignes ajoutées) |
| **Intégration** | 31/10, 05:29-06:43 | Jeu complet de bout en bout : **serveur simulé de 12 joueurs** (`Boot.spec`, robots qui marchent, chassent, paradent et coupent) et **rejeu d'une session enregistrée** dans le vrai client (`ClientGame.spec`) |
| **QA tour 1** | 31/10, 10:01 | Corrections sécurité, données, robustesse, conformité au GDD |
| **QA tour 2** | 31/10, 12:05 | Idem, puis restes et notes d'intégration (13:55) |
| **Console PS5** | 31/10, 14:35-16:12 | Manette DualSense, interface « 10 pieds », icônes PlayStation, navigation complète (docs/07) |
| **QA tour 3** | 31/10, 19:21 | Corrections (sécurité, données, robustesse, expérience joueur, conformité) ; résultats au §6 |
| **QA tour 4** | 31/10, 20:46-22:02 | Corrections (mêmes axes) ; résumé au §6 |

**Les tours de QA.** À chaque tour, des auditeurs indépendants relisent tout le jeu, chacun avec une « lentille » :

| Lentille | Ce qu'elle cherche |
|---|---|
| Sécurité | Triche : messages réseau truqués, valeurs absurdes, débit excessif, achats simulés |
| Données | Perte ou duplication de progression, sauvegardes concurrentes entre serveurs, reçus d'achat |
| Robustesse | Joueur qui part pendant un chargement, personnage absent, pannes, fuites de mémoire |
| Expérience joueur | Un enfant sur téléphone ou sur PS5 comprend-il ? Textes lisibles, boutons atteignables |
| Conformité | Le jeu fait-il exactement ce que disent le GDD et le contrat ? |
| roblox-dev | Bonnes pratiques Roblox : performance, budgets, API réellement existantes |

Chaque constat est **reproduit par un test qui échoue**, puis corrigé par l'ingénieur propriétaire des fichiers ; le test reste dans la suite (fichiers `Fix_*`) pour que le défaut ne revienne jamais. Aucun test existant n'est supprimé ni affaibli.

---

## 4. Ce qui est vérifié automatiquement… et ce qui ne peut l'être que dans Roblox

Les tests tournent **hors de Roblox** : le harnais (`tests/harness/`) imite le moteur (joueurs, sauvegardes avec pannes, achats, messages réseau, interface, manette). C'est rapide et refait à chaque modification, mais ce n'est pas le vrai moteur.

### 4.1 Vérifié automatiquement à chaque modification

| Domaine | Ce qui est prouvé | Où |
|---|---|---|
| Règles du jeu | Formules (coûts, bonus, revenus, hors ligne), file et coupe (chaque règle et leurs combinaisons), trajets déterministes, horloge des événements (météo, Comète, Balise, Starfall), codage réseau des files | `Formulas`, `Trail`, `SnipRules`, `SeededPath`, `EventClock`, `PathCodec`, `WorldLayout` |
| Rythme de l'économie | Simulation de 200 joueurs × 28 jours : première parade 10,5 s, Supernova 1 à 25 min, Supernova 10 au jour 21, 50 % de l'Atlas au jour 12, dans les tolérances du GDD §4.18 (docs/04 §17) | `EconomyPacing` |
| Anti-triche | Chaque message réseau reçu par le serveur est bombardé de valeurs invalides (NaN, infini, mauvais types, tables énormes, identifiant d'un autre joueur, débit excessif) : aucun effet, aucune erreur. Vitesse, téléportation, vol plané, passage sous le sol | specs de chaque service (`CongaService`, `EconomyService`, `QuestService`…), `MoveCheck`, `Fix_conga_r1`, `Fix_conga_r2` |
| Sauvegardes | Pannes de DataStore injectées, nouvelles tentatives, verrou de session entre serveurs, migration des anciens profils, sauvegarde à la fermeture du serveur | `DataService`, `Contract` (migration), `Fix_r3_serveur_3_data` |
| Achats | Reçu rejoué = un seul crédit ; crédit seulement après une sauvegarde réussie ; pass vérifié auprès de Roblox, retiré s'il est remboursé | `MonetizationService`, `ProductService` |
| Jeu entier, côté serveur | 12 joueurs simulés : coupes, améliorations, Supernova, Comète, Balise, Starfall, départs et retours, morts, réapparitions, fermeture | `Boot` |
| Jeu entier, côté client | Une vraie partie serveur est enregistrée puis rejouée dans le vrai client : l'image du client correspond à l'état du serveur ; chaque panneau, onglet et bouton est pressé en anglais puis en français ; arrivée en cours de partie | `ClientGame` |
| Messages réseau | Chaque envoi respecte les règles de Roblox (pas de tables mixtes, pas de NaN…) ; chaque message affiché existe en anglais et en français | `harness/Wire`, `Boot`, `Contract` |
| API Roblox | Chaque classe créée, propriété écrite ou lue est confrontée à la base officielle des API Roblox livrée avec Lune : une faute de frappe qui passerait hors de Roblox est détectée | `harness/ApiAudit` (dans les tests d'intégration) |
| Console | Manette seule : tout est atteignable, la sélection ne s'échappe pas des fenêtres, icônes PlayStation, textes ≥ 18 px de référence, zone sûre TV, pas de fenêtre de chat, vibrations modérées | `Console*`, `harness/Gamepad`, `harness/Layout` |
| Budgets de rendu (en simulation) | ≤ 100 Nebbies en détail complet, plafond de pièces, lumières, `Highlight`, particules comptées | `CongaRenderer`, `VFXController`, `Fix_r3_client_0` |
| Textes | Parité anglais / français et variables `{x}` de chaque texte | `Contract` |

### 4.2 Ce qui ne peut être vérifié que dans Roblox Studio ou en ligne

| Domaine | Pourquoi les tests ne suffisent pas | Test manuel (§5) |
|---|---|---|
| **Rendu réel** | Le harnais ne dessine rien : éclairage *Future*, néons, lueurs, ciel, couleurs des raretés, lisibilité des files | M2 |
| **Physique réelle** | Marche, saut, Dash, collisions, bords de l'île, détection de la porte du Nid sont simulés de façon simplifiée | M3 |
| **Vraies sauvegardes** | Les vrais DataStores ont des délais, des quotas et des pannes que la simulation imite seulement | M4 |
| **Vrais achats** | Fenêtres d'achat Roblox, prix réels, achats sur téléphone et console | M5 |
| **Serveur avec 12 vrais joueurs** | Temps du tick serveur (< 2 ms à 10 Hz visé), réseau par joueur (≤ 6 Ko/s), mémoire du client (< 900 Mo), images par seconde sur téléphone modeste (GDD §12.8) | M6 |
| **Tenue des textes** | Le harnais estime la largeur des lettres ; seul Roblox montre si un texte français (≈ 25 % plus long) est coupé ou trop petit | M7 |
| **Aspect des particules** | Le nombre est compté, pas la beauté : étincelles, Comète, Supernova, météo | M8 |
| **Ergonomie sur téléphone** | Le pouce atteint-il le Dash ? Un bouton est-il caché par le joystick ? | M9 |
| **Équité des coupes avec latence** | Le serveur décide ; la sensation « je l'ai touché ! » à 250 ms de latence se juge en vrai | M10 |
| **Téléviseur et PS5** | Lisibilité à 3 m, zone sûre réelle, vibrations, achats sur PlayStation | M11 |
| **Sons** | Les sons de jeu et la musique sont encore vides (choix à faire, guide §6.4) ; les sons d'interface sont à écouter | M12 |

Limites connues du harnais (sans effet sur le jeu) : la sélection à la croix de la manette est une approximation (Roblox ne publie pas sa règle exacte : les tests vérifient que tout est **atteignable**, pas le chemin exact) ; un bouton grossi à la sélection peut, au bord gauche d'une grille, faire dévier la simulation (docs/07 §10.1).

---

## 5. Plan de test manuel dans Roblox Studio

À dérouler avant le lancement public, dans l'ordre. Préparation : `rojo build -o build/Game.rbxl`, publication **privée**, accès aux API activé (guide §4). Gardez ouvertes la fenêtre **Output** (aucune ligne rouge attendue) et, en ligne, la **console développeur** (touche F9). Comptez environ une journée, plus le test à 12 joueurs.

| # | Test | Comment | Résultat attendu |
|---|---|---|---|
| M1 | **Première session** (seul) | **Play**. Jouer 5 minutes sans rien lire d'autre que le jeu | Première capture en quelques secondes, première parade vers 12 s, premier achat vers 20 s ; 4 à 6 parades et améliorations en 5 min (GDD §3) ; jamais deux consignes à l'écran en même temps (voir constat mineur n°7) |
| M2 | **Rendu** | Faire le tour de l'île (Prairie, Clairière, Cratère, Balise, 12 Nids) ; attendre une météo, une Grande Comète, une Nuit de la Balise ; Réglages › Graphismes légers | Ambiance crépuscule lisible, raretés reconnaissables par la couleur **et** la forme, aucun objet qui clignote ou disparaît, rien de « gris » ; Graphismes légers allège sans rien casser |
| M3 | **Physique** | Marcher, sauter, Dash contre le décor, aller au bord de l'île, tomber, entrer au Nid par l'arche, sous l'arche puis à côté | Le décor ne bloque pas bizarrement (pièces décoratives non solides), retour sur l'île après une chute, parade déclenchée sous l'arche et seulement là |
| M4 | **Sauvegardes réelles** | Accès aux API activé. Jouer, acheter des améliorations, quitter, revenir. Puis en ligne : rejoindre un serveur, quitter, rejoindre **aussitôt** un autre serveur. Puis arrêter tous les serveurs depuis le Creator Hub en cours de partie | Progression retrouvée à chaque fois, jamais de retour en arrière ; l'écran « Ton Nid se réveille… » attend puis charge ; rien de perdu à l'arrêt |
| M5 | **Achats** | Dans Studio : chaque pass et produit (achats d'essai gratuits). En ligne, jeu privé : un vrai achat de **Glow Pouch** (25 R$) et d'un pass, puis quitter et revenir | Effet reçu **une seule fois** ; pass toujours actif après retour ; Starter Kit refusé la 2e fois (une fois par compte) ; Glow Party : bannière pour tout le serveur |
| M6 | **12 vrais joueurs** | Serveur en ligne privé avec 12 personnes (amis, testeurs) pendant 30 min, dont un **téléphone Android modeste** (~3 Go de RAM). Console développeur (F9) : performances du serveur et mémoire | ≥ 30 images/s en permanence sur le téléphone, mémoire client < 900 Mo, temps de traitement du serveur stable, aucune erreur (GDD §15.2, porte 3) |
| M7 | **Textes** | Émulateur (onglet Test › Device) : plus petit téléphone, tablette, écran 4K ; chaque panneau et onglet **en français puis en anglais** (Réglages › Langue) | Aucun texte coupé, superposé ou illisible ; nombres au format français (« 1,24 M ») en français |
| M8 | **Particules** | Grande capture, coupe d'une longue file, Comète, Supernova, Starfall, neige de Frostfall | Effets jolis et lisibles ; pendant la neige, les effets de capture restent visibles (voir question n°4) |
| M9 | **Téléphone en main** | Sur un vrai téléphone : jouer 15 min à une main, ouvrir chaque menu, replier le suivi de quête, glisser le doigt hors d'un bouton | Dash atteignable au pouce, rien sous le joystick, boutons faciles à toucher (voir constats mineurs n°6 et n°8, question n°3) |
| M10 | **Coupes avec latence** | Studio : 2 à 4 joueurs en *Local Server*, latence simulée de 250 ms (réglages réseau de Studio, nom exact à vérifier) ; 100 traversées franches de files | ≥ 95 coupes accordées, aucune coupe à plus de 3,5 studs de distance visible (GDD §15.2, porte 2) |
| M11 | **Manette et PS5** | Controller Emulator ou manette USB dans Studio, puis vraie PS5 (guide §11) | Tout se fait à la manette ; à 3 m sur le téléviseur, tout est lisible et rien n'est coupé ; vibrations agréables |
| M12 | **Sons** | Jouer avec le son : naviguer dans les menus, à la manette et au toucher | Sons d'interface agréables et pas trop forts ; décision prise pour les sons de jeu et la musique (guide §6.4) |
| M13 | **Session longue** | 30 minutes de jeu à plusieurs, en ligne | Aucune erreur dans la console développeur, pas de ralentissement progressif |

---

## 6. Résultats des tours de QA

### 6.1 Tour 3 (commit `c0a97f9`)

| Constats | À corriger | Graves | Mineurs non retenus pour ce tour |
|---|---|---|---|
| **47** | **28** | **4** | **19** |

Les 28 constats à corriger ont été traités par groupes de fichiers, chacun avec son test de correction (`tests/specs/Fix_r3_*.spec.luau`). Exemple détaillé, groupe **r3-client-0** :

- **Parade et budgets de rendu** (`CongaRenderer`) : pendant une parade, les Nebbies qui défilent restent comptés dans les budgets du GDD §12.8 avant que le reste ne soit planifié ; si la parade seule dépasse le budget, les plus lointains passent en forme simplifiée. Mesuré avec 4 files de 60 Nebbies : jamais plus de **100** Nebbies en détail complet (157 avant) ; avec un plafond forcé à 600 pièces, jamais plus de 600 (690 avant).
- **Sélection de repli dans les menus** (`PanelController`) : quand le bouton sélectionné disparaît, la sélection va sur l'onglet **affiché** (et non sur le premier onglet) ; Collection ouverte sur Atlas ou Guide sélectionne cet onglet.
- **Listes en lecture seule à la croix** (`PanelController`) : ↑ / ↓ font défiler l'Atlas, le Guide et l'aperçu de la Supernova (70 % de la hauteur visible) ; le signal « bout de liste » (son + vibration) n'arrive qu'au vrai bout.
- **Nebbies perchés qui clignotaient** (`NestDisplay`) : quand l'ordre des perchoirs change (un meilleur Nebby arrive), chaque perché garde son modèle ; mesuré avec 20 perchés : les 19 décalés restent visibles à chaque image, le nouveau apparaît à l'image suivante.
- Tests : `Fix_r3_client_0.spec.luau`, `Fix_r3_client_0_panels.spec.luau`.

Autres groupes du tour 3 (un fichier de test chacun) : écran de chargement qui n'affiche plus « Réessayer » trop tôt (`Fix_r3_partage_2`) ; sauvegarde refusée si la session a perdu son verrou, arrivée d'un joueur à 640 Nebbies sous le budget réseau (`Fix_r3_serveur_3_data`) ; trajectoire des files après un grand déplacement (`Fix_r3_serveur_3_conga`) ; Glow Party payée jamais recouverte par un boost gratuit (`Fix_r3_serveur_3_events`) ; réserve pleine qui ne libère jamais un cadeau ni un Starborn (`Fix_r3_serveur_3_atlas`) ; anti-triche et Mode Zen (`Fix_r3_serveur_4`) ; lisibilité sur téléphone et console (`Fix_r3_ui_1`) ; validation croisée (`Fix_r3_release`).

**Les 19 constats mineurs du tour 3**, avec leur état vérifié dans le code au moment de ce rapport :

| n° | Fichier | Constat | État au 31/10, 22:10 UTC |
|---|---|---|---|
| 1 | `src/server/Services/DataService.luau` | `writeRecord` traitait un verrou absent comme le sien et pouvait écraser des données plus récentes d'un autre serveur | **Corrigé** au tour 3 (verrou absent = pas d'écriture ; `Fix_r3_serveur_3_data`) |
| 2 | `src/client/Controllers/WorldFXController.luau` | L'animation du décor déplace 184 pièces une par une à chaque image et lit environ 570 attributs | Ouvert (performance, à mesurer en M6) |
| 3 | `src/client/World/RigPool.luau` | La réserve de modèles ne libère jamais de place : avec le temps, elle ne réutilise plus | À revérifier au prochain tour |
| 4 | `src/client/Controllers/VFXController.luau` | Le budget de 300 particules ne compte pas les étincelles d'immunité, ni le feu et les étincelles de la Comète du ciel | À revérifier (M8) |
| 5 | `src/client/UI/HUD.luau` | Fin d'une quête d'accueil : la barre du suivi ne se remplit pas et n'affiche pas de coche | À revérifier (M1) |
| 6 | `src/client/UI/HUD.luau` | Le bouton pour replier le suivi de quête fait 17 × 34 px : trop petit au doigt | À revérifier (M9) |
| 7 | `src/client/UI/HUD.luau` | Deux consignes à l'écran : « Attrape des Nebbies ! » (file vide) et la consigne d'accueil | À revérifier (M1) |
| 8 | `src/client/UI/Juice.luau` | Sur téléphone, un bouton reste rétréci (0,9) si le doigt glisse hors du bouton | À revérifier (M9) |
| 9 | `src/client/UI/Hud/OnboardingPlan.luau` | « Retourne au Nid » est validé si l'enfant est déjà sur le Nid sans passer sous l'arche | À revérifier (M1) |
| 10 | `src/client/UI/Panels/Collection.luau` | ○ en mode sélection de la Réserve (ou libération armée) ferme toute la Collection au lieu d'annuler | À revérifier (M11) |
| 11 | `src/client/Util/Haptics.luau` | Sur PS5, l'atténuation par la distance est ignorée : chaque impact de Comète proche vibre à pleine force | Ouvert : la vibration PlayStation (`HapticEffect`) ne reçoit pas l'atténuation, seul le repli l'utilise (M11) |
| 12 | `src/shared/Config/Sounds.luau` | Aucun son de navigation sur console (ID vides) ; « Select » s'empile lors des déplacements faits par le code | **Corrigé** au tour 4 pour les ID (sons publiés par Roblox, `Fix_r4_partage_4`) ; à écouter (M12) |
| 13 | `src/client/Controllers/PanelController.luau` | Contour rose « queue menacée » affiché pendant la trêve après une Balise réussie et pendant l'immunité | **Corrigé** au tour 4 (`Fix_r4_client_0_panels`) |
| 14 | `src/server/Services/LeaderboardService.luau` | La couronne « Conga Royal » n'est pas retirée quand la semaine change pendant une session | À revérifier au prochain tour |
| 15 | `src/client/UI/Panels/Collection.luau` | L'onglet Guide affiche les multiplicateurs avec des décimales à l'anglaise en français | À revérifier (M7) |
| 16 | `src/client/Controllers/OnboardingController.luau` | « Ton Nid travaille même quand tu dors » absent du menu | À revérifier (le pied du panneau Réglages affiche ce texte) |
| 17 | `src/server/Services/MonetizationService.luau` | Un faux signal de fin d'achat de pass peut relancer sans délai des vérifications auprès de Roblox | Ouvert (sans gain pour le tricheur : le pass n'est accordé que si Roblox confirme l'achat) |
| 18 | `src/server/Services/CongaService.luau` | Le type d'appareil déclaré par le client élargit le rayon de coupe (l'aide au tactile peut être simulée) | En attente de **votre décision** (question n°1, §7) |
| 19 | `src/server/Services/WorldService.luau` | Après une erreur pendant la construction du monde, `building` reste vrai : chaque accès suivant échoue avec un message trompeur | Ouvert (seulement si la construction échoue, ce qu'aucun test n'a produit) |

« À revérifier » : constat non retenu au tour 3 ; ce rapport n'a pas pu confirmer son état dans le code sans refaire l'audit. Tous ces constats ont été classés **mineurs** par les auditeurs ; aucun n'a fait échouer un test ni une partie simulée. Ils sont à reprendre dans le prochain tour, en commençant par les n° 11 (PS5), 6 et 8 (téléphone).

### 6.2 Tour 4 (commit `e951d5e`)

Corrections principales (tests `tests/specs/Fix_r4_*.spec.luau`) :

- **Anti-triche** : un bond accepté après un gel réseau ne peut plus couper, attraper ni voler la Comète ; l'explosion de la Comète donne au plus un Épique par joueur (`Fix_r4_serveur_3`).
- **Console** : sons de navigation réels (`Fix_r4_partage_4`) ; sélection jamais perdue dans un menu, contour rose aligné sur les règles du serveur (`Fix_r4_client_0_panels`) ; fenêtre de chat aussi coupée dans l'interface de base de Roblox (`Fix_r4_client_0`) ; curseur de sélection blanc et épais, visible à 3 m (`Fix_r4_ui_1_root`).
- **Téléphone** : la consigne d'accueil ne recouvre plus le bouton Ping ; la pastille d'événement ne recouvre plus Équipage ni Réglages sur les petits écrans (`Fix_r4_client_0`, `Fix_r4_ui_1_hud`).
- **Accueil** : progression juste des quêtes d'achat, pas de double achat au double appui (`Fix_r4_ui_1`) ; quête météo claire pendant une pluie de météores (`Fix_r4_ui_1_plan`) ; moment « Atlas débloqué » avec sa carte et son son (`Fix_r4_ui_2`).
- Validation croisée de publication (`Fix_r4_release`).

---

## 7. Questions de design ouvertes (à trancher par le propriétaire)

1. **Bonus de coupe « tactile » (Q21)** : sur téléphone, le rayon pour couper la file d'un autre joueur est un peu plus grand (3,1 au lieu de 2,8), comme le prévoit le GDD. Le serveur ne peut pas savoir quel appareil utilise un joueur : un tricheur sur ordinateur peut se déclarer « téléphone » et garder ce bonus (environ 11 % de coupes en plus). Que préférez-vous ? (a) garder le bonus réservé au tactile en acceptant ce risque ; (b) donner 3,1 à tout le monde ; (c) supprimer le bonus (2,8 pour tous).
2. **Badge « ★ VIP » (N35)** : le GDD dit « badge doré sous le nom ». Aujourd'hui, le badge s'affiche sur le panneau du Nid du joueur. Voulez-vous aussi un badge flottant sous le nom, au-dessus de la tête du personnage, visible partout sur l'île ?
3. **Menus ouverts sur téléphone (N57)** : glisser le doigt sur le fond d'un menu ouvert fait tourner la caméra. Bloquer cela empêcherait aussi le joystick de fonctionner dans la partie en bas à gauche de l'écran couverte par le menu. Préférez-vous (a) garder la caméra mobile (situation actuelle) ou (b) bloquer la caméra et le joystick sous le menu ?
4. **Mise à jour du GDD (N68, N140, N146)** : plusieurs chiffres du GDD ne correspondent plus au jeu. Chance qu'un Nebby apparaisse en forme météo : 20 % dans le jeu, 40 % dans le GDD. Coûts des Supernovas 4 à 12 : doublés. Neige de Frostfall : 60 flocons/s pendant 6 s dépassent à eux seuls le budget de 300 particules ; nous allons la réduire, sinon les effets de capture disparaissent pendant la neige. Nouvelles règles anti-triche : vol plané prolongé et passage sous le sol. Validez-vous ces valeurs pour que nous mettions le GDD à jour ?
5. **Starfall Saturday (N69)** : l'espèce vedette représente 25 % des apparitions dans toutes les zones, donc un Nebby Épique peut apparaître dans la Prairie des débutants. Est-ce voulu, ou faut-il limiter l'espèce vedette aux zones de sa rareté ?
6. **Récompense de la Comète en début de partie (N70)** : un seul Nebby de Comète a fait passer le revenu d'un nouveau joueur de 24 à 679 Glow par seconde (×28). C'est conforme aux formules. Gardez-vous une récompense aussi forte pour un débutant, ou faut-il l'adoucir pendant les premières sessions ?
7. **Accueil, quêtes d'achat (N162)** : pendant les quêtes d'achat (Q2, Q5, Q7), seule la carte d'amélioration demandée par la quête clignote, même quand le joueur n'a pas encore assez de Glow pour l'acheter. Pendant Q7, cela peut durer plusieurs niveaux de Perchoirs. Les autres cartes restent achetables mais ne clignotent pas. Est-ce bien le comportement souhaité ?

Les justifications des réglages d'économie déjà faits (Supernovas, formes météo) sont dans docs/04 §17.

---

## 8. Ce qui reste à faire à la main avant de publier

| Action | Qui | Où |
|---|---|---|
| Créer les 6 passes et 6 produits, coller leurs numéros | Propriétaire | Guide §5, `src/shared/Config/Monetization.luau` |
| Ajouter les administrateurs LiveOps | Propriétaire | Guide §6.1, `src/server/Data/Admins.luau` |
| Recaler la semaine du premier Starfall Saturday | Propriétaire | Guide §6.3, `src/shared/Config/Events.luau` |
| Choisir les sons de jeu et la musique (ou lancer en silence) | Propriétaire + équipe technique (un test vérifie aujourd'hui que ces sons sont vides) | Guide §6.4, `src/shared/Config/Sounds.luau` |
| Vérifier les noms « Comet Conga » et « Nebbies » (Roblox et marques) | Propriétaire | GDD §16, risque 7 |
| Questionnaire de maturité, icône, miniatures, taille de serveur 12, langues | Propriétaire | Guide §7 à §10 |
| Plan de test manuel M1 à M13 | Propriétaire + testeurs | §5 |
| Essai sur PS5 avant d'activer la console | Propriétaire | Guide §11 |
| Répondre aux 7 questions de design | Propriétaire | §7 |
