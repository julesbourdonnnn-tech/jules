# Comet Conga — Rapport qualité avant publication

> **Document 06.** Établi le 31 octobre 2026 à 22:10 UTC, sur le commit `e951d5e` (« QA tour 4 »). **Mis à jour le 1er novembre 2026 à 06:30 UTC**, sur le commit `bbded7a` (« QA tour 6 », arbre de travail propre) : vérification complète refaite (§1), section « Finition » (§6.3 : contre-audit anti-triche, revue des corrections du tour 4, sons, tours 5 et 6, petits constats encore ouverts revérifiés dans le code).
> Pour le propriétaire du jeu : ce rapport dit **ce qui est prouvé**, **ce qui ne peut l'être que dans Roblox Studio**, et **ce qu'il reste à décider**. Guide de publication : [`05-guide-publication.md`](05-guide-publication.md).

## En bref

| Question | Réponse |
|---|---|
| Le jeu est-il complet ? | Oui pour la version 1.0 du GDD (§15.1) : île, boucle complète, progression, événements, social, boutique, FR/EN, téléphone, PC et manette (PS5 / Xbox) |
| La vérification complète passe-t-elle ? | **Oui** : `./scripts/check.sh` → « ✅ Tout est vert. » (§1) |
| Combien de tests automatiques ? | **1 619 tests**, dans **112 fichiers de tests**, **0 échec** |
| La triche a-t-elle été vérifiée par quelqu'un d'autre ? | Oui : contre-audit indépendant ; la triche qu'il a trouvée est corrigée et reste testée à chaque modification (§6.3.1) |
| Le jeu a-t-il du son ? | Oui : les 27 sons sont des sons publiés par Roblox. **Personne ne les a encore écoutés** : à faire dans Studio avant de publier (§6.3.4, test M12) |
| Qu'est-ce qui n'est pas encore prouvé ? | Ce que seul le vrai moteur Roblox montre : rendu, physique, vraies sauvegardes et vrais achats, serveur avec 12 vrais joueurs, tenue des textes, aspect des particules, confort sur téléphone, rendu sur téléviseur (§4) |
| Que reste-t-il à faire à la main ? | Le plan de test dans Studio (§5) et les réglages de publication ([`05-guide-publication.md`](05-guide-publication.md) §12) |
| Y a-t-il des décisions à prendre ? | Oui, 7 questions de design (§7), plus deux petits choix (§6.3.6, n° 7 et 9) |

---

## 1. Résultat de la vérification complète

Commande : `./scripts/check.sh`, lancée sur le commit `bbded7a` sans modification locale, terminée le 01/11/2026 à 06:20 UTC (environ 6 min), code de sortie 0, message final « ✅ Tout est vert. ».

| Contrôle | Outil | Résultat |
|---|---|---|
| Formatage du code | StyLua | Conforme |
| Analyse du code (erreurs probables, mauvaises pratiques) | Selene | **0 erreur, 0 avertissement**, 0 erreur de lecture |
| Tests automatiques | Lune (`tests/run.luau`) | **1 619 réussis, 0 échoué, 0 fichier de test non chargé** |
| Construction du jeu | Rojo 7.7.1 | `build/Game.rbxl` construit |
| Contrôle du fichier construit | `scripts/verify-place.luau` | Structure valide : 1 Script serveur, 2 LocalScript, 113 ModuleScript |

Lors des validations de publication des tours 3 et 4 et de la passe de finition, la suite complète a été relancée deux fois de plus pour repérer des tests instables (résultat qui change d'une exécution à l'autre) ; ceux trouvés aux tours 3 et 4 ont été corrigés (horloge réelle de la limite de débit, ordre de parcours des tables). À la finition, un test instable a été trouvé et corrigé : `Boot.spec`, scène de coupe (l'ordre de traitement des joueurs n'est pas reproductible d'un processus à l'autre ; la victime pouvait ne rien attraper en 6 s quand le coupeur, resté à portée, prenait ses Nebbies libres à la fin de leur étourdissement, ce que permettent les règles, ou rattraper autant de sauvages pendant la traversée qu'elle en perdait). La scène ne dépend plus de ces courses, la priorité de la victime est maintenant vérifiée de façon déterministe, et la scène a été rejouée 60 fois sans échec, puis la suite complète deux fois de plus. À la validation du tour 5, la suite complète a été relancée deux fois de plus avant les dernières corrections, puis deux fois après (deux exécutions en parallèle, machine chargée) : aucun test instable. À la validation du tour 6, après les corrections : vérification complète, puis la suite complète deux fois de plus (en parallèle), les tests du tour 6 rejoués 8 fois et ceux des sauvegardes en panne 8 fois de plus à quatre exécutions simultanées : aucun test instable. Le nouveau test du débit des pings fige l'horloge de la limite de débit (aucune attente réelle). Pour ce rapport, la vérification complète a été refaite une fois de plus sur le commit `bbded7a` : mêmes chiffres, aucun échec.

## 2. Taille du projet et des tests

| Partie | Fichiers | Lignes |
|---|---|---|
| Serveur (`src/server`) | 36 | 16 027 |
| Client (`src/client`) | 47 | 32 288 |
| Partagé (`src/shared`) | 32 | 9 372 |
| Écran de chargement (`src/first`) | 1 | 787 |
| **Total du jeu** | **116** | **58 474** |
| Tests (`tests/`, dont harnais et simulation) | — | 61 728 |

Tous les modules du jeu sont en Luau `--!strict` (typage strict).

| Famille de tests | Fichiers | Tests | Exemples |
|---|---|---|---|
| Tests unitaires et de services | 40 | 841 | `Formulas`, `SnipRules`, `EventClock`, `CongaService`, `EconomyService`, `DataService`, `MonetizationService`, `Panels`, `HUD`, `Contract` |
| Tests de correction (un par défaut trouvé en QA) | 62 | 646 | `Fix_r3_serveur_3_data`, `Fix_r4_serveur_3`, `Fix_r5_serveur_anticheat`, `Fix_fin_client_hud_onboarding`, `Fix_r6_serveur_2_data`, `Fix_r6_release`… |
| Console et manette | 5 | 86 | `Console`, `Console_input`, `Console_hud`, `Console_panels`, `Console_release` |
| Intégration (jeu entier) | 3 | 32 | `Boot` (serveur de 12 joueurs), `ClientGame` (partie rejouée dans le vrai client), `ClientBoot` |
| Harnais de test lui-même | 2 | 14 | `harness/Harness`, `harness/Wire` |
| **Total** | **112** | **1 619** | |

---

## 3. Comment le jeu a été construit et vérifié

Historique tiré de `git log` (40 commits jusqu'à `bbded7a`, heures UTC).

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
| **Documentation** | 31/10, 22:16 | Guide de publication (docs/05), ce rapport, README |
| **Finition** | 31/10, 23:22 - 01/11, 02:26 | Contre-audit anti-triche et revue des corrections du tour 4, faits par d'autres ingénieurs ; sons officiels Roblox ; restes des tours 3 et 4 (§6.3) |
| **QA tour 5** | 01/11, 04:20 | Corrections (mêmes axes) ; §6.3.5 |
| **QA tour 6** | 01/11, 06:13 | Corrections (mêmes axes) ; §6.3.5 |

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
| **Sons** | Les tests vérifient le format et la provenance de chaque numéro, pas le son lui-même. Les 27 sons (interface, manette, musique, capture, coupe, Comète, Supernova…) sont publiés par Roblox, mais personne ne les a écoutés ; neuf ont été remplis en dernier et sont « à confirmer à l'écoute » (`Scatter`, `Bank`, `Dash`, `CometWarn`, `CometSwipe`, `BeaconStart`, `WispPop`, `Ping`, `Cheer` ; §6.3.4, guide §6.4) | M12 |

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
| M12 | **Sons** | Jouer avec le son : naviguer dans les menus, à la manette et au toucher. **Écouter d'abord** les neuf sons « à confirmer à l'écoute » : `CometWarn` (alerte Comète, enregistrement nouveau, peut-être trop discret) et `Ping` (enregistrement nouveau) en premier, puis `Scatter`, `Bank`, `Dash`, `CometSwipe`, `BeaconStart`, `WispPop`, `Cheer` | Chaque son agréable et pas trop fort (musique comprise) ; un seul jingle à la fois (quête, jalon d'Atlas, achat) ; noter les sons qui déplaisent ; l'équipe technique les vide (`id = ""` : muet, jeu jouable) ou les remplace, en mettant le test des sons à jour (guide §6.4) |
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

| n° | Fichier | Constat | État (revérifié dans le code le 1/11, après la finition et les tours 5 et 6) |
|---|---|---|---|
| 1 | `src/server/Services/DataService.luau` | `writeRecord` traitait un verrou absent comme le sien et pouvait écraser des données plus récentes d'un autre serveur | **Corrigé** au tour 3 (verrou absent = pas d'écriture ; `Fix_r3_serveur_3_data`) |
| 2 | `src/client/Controllers/WorldFXController.luau` | L'animation du décor déplace 184 pièces une par une à chaque image et lit environ 570 attributs | **Corrigé** à la finition (attributs lus au suivi, un `BulkMoveTo`, pièces lointaines ralenties ; `Fix_fin_client_world_perf`) ; à mesurer en M6 |
| 3 | `src/client/World/RigPool.luau` | La réserve de modèles ne libère jamais de place : avec le temps, elle ne réutilise plus | **Corrigé** à la finition (réserve LRU, au plus 24 modèles par clé ; `Fix_fin_client_world_perf`) |
| 4 | `src/client/Controllers/VFXController.luau` | Le budget de 300 particules ne compte pas les étincelles d'immunité, ni le feu et les étincelles de la Comète du ciel | **Corrigé** à la finition (étincelles d'immunité et Comète du ciel comptées ; `Fix_fin_client_world_perf`) ; à regarder en M8 |
| 5 | `src/client/UI/HUD.luau` | Fin d'une quête d'accueil : la barre du suivi ne se remplit pas et n'affiche pas de coche | **Corrigé** à la finition (barre remplie, coche, puis quête suivante ; `Fix_fin_client_hud_onboarding`) |
| 6 | `src/client/UI/HUD.luau` | Le bouton pour replier le suivi de quête fait 17 × 34 px : trop petit au doigt | **Corrigé** à la finition (toute la pastille replie, zone ≥ 44 px réels ; `Fix_fin_client_hud_onboarding`) ; à revérifier au doigt (M9) |
| 7 | `src/client/UI/HUD.luau` | Deux consignes à l'écran : « Attrape des Nebbies ! » (file vide) et la consigne d'accueil | **Corrigé** à la finition (pendant l'accueil le compteur montre « 0/3 » ; `Fix_fin_client_hud_onboarding`) |
| 8 | `src/client/UI/Juice.luau` | Sur téléphone, un bouton reste rétréci (0,9) si le doigt glisse hors du bouton | **Corrigé** à la finition (doigt relevé hors du bouton → taille normale ; `Fix_fin_client_hud_onboarding`) ; à revérifier (M9) |
| 9 | `src/client/UI/Hud/OnboardingPlan.luau` | « Retourne au Nid » est validé si l'enfant est déjà sur le Nid sans passer sous l'arche | **Corrigé** à la finition (« Passe sous l'arche ! » tant que l'arche n'est pas franchie ; `Fix_fin_client_hud_onboarding`) |
| 10 | `src/client/UI/Panels/Collection.luau` | ○ en mode sélection de la Réserve (ou libération armée) ferme toute la Collection au lieu d'annuler | **Corrigé** à la finition (○ recule d'un niveau ; `Fix_r5_panels`) |
| 11 | `src/client/Util/Haptics.luau` | Sur PS5, l'atténuation par la distance est ignorée : chaque impact de Comète proche vibre à pleine force | **Corrigé** à la finition (vibration atténuée jouée au moteur à force × facteur, jamais l'effet pleine force ; `Console.spec`) ; à ressentir sur PS5 (M11) |
| 12 | `src/shared/Config/Sounds.luau` | Aucun son de navigation sur console (ID vides) ; « Select » s'empile lors des déplacements faits par le code | **Corrigé** au tour 4 pour les ID (sons publiés par Roblox, `Fix_r4_partage_4`) et à la finition pour « Select » (`Fix_r5_audio`) ; à écouter (M12) |
| 13 | `src/client/Controllers/PanelController.luau` | Contour rose « queue menacée » affiché pendant la trêve après une Balise réussie et pendant l'immunité | **Corrigé** au tour 4 (`Fix_r4_client_0_panels`) |
| 14 | `src/server/Services/LeaderboardService.luau` | La couronne « Conga Royal » n'est pas retirée quand la semaine change pendant une session | **Corrigé** à la finition (couronne retirée au changement de semaine ; `Fix_fin_server_anticheat_services`) |
| 15 | `src/client/UI/Panels/Collection.luau` | L'onglet Guide affiche les multiplicateurs avec des décimales à l'anglaise en français | **Corrigé** à la finition (« Givrée ×2,5 » en français ; `Fix_fin_client_panels_console`) |
| 16 | `src/client/Controllers/OnboardingController.luau` | « Ton Nid travaille même quand tu dors » absent du menu | **Conforme** (revérifié dans le code le 1/11) : le message s'affiche après 10 min de jeu pour un joueur qui a moins de 2 h de jeu, et toujours en pied du panneau Réglages, comme le demande le GDD (§7, J1) |
| 17 | `src/server/Services/MonetizationService.luau` | Un faux signal de fin d'achat de pass peut relancer sans délai des vérifications auprès de Roblox | **Corrigé** à la finition (vérifications bornées par `RateLimit`, réponse « non possédé » retenue ; `Fix_r5_serveur_data`) |
| 18 | `src/server/Services/CongaService.luau` | Le type d'appareil déclaré par le client élargit le rayon de coupe (l'aide au tactile peut être simulée) | En attente de **votre décision** (question n°1, §7) |
| 19 | `src/server/Services/WorldService.luau` | Après une erreur pendant la construction du monde, `building` reste vrai : chaque accès suivant échoue avec un message trompeur | **Corrigé** à la finition (drapeau remis à zéro, erreur d'origine relancée ; `Fix_fin_server_data_publish`) |

Tous ces constats ont été classés **mineurs** par les auditeurs ; aucun n'a fait échouer un test ni une partie simulée. Après la passe de finition, il ne reste que le n° 18 (votre décision, question n° 1 du §7). Chaque correction a son test ; les n° 2, 4, 6, 8, 11 et 12 restent à confirmer dans Roblox (M6, M8, M9, M11, M12).

### 6.2 Tour 4 (commit `e951d5e`)

Corrections principales (tests `tests/specs/Fix_r4_*.spec.luau`) :

- **Anti-triche** : un bond accepté après un gel réseau ne peut plus couper, attraper ni voler la Comète ; l'explosion de la Comète donne au plus un Épique par joueur (`Fix_r4_serveur_3`).
- **Console** : sons de navigation réels (`Fix_r4_partage_4`) ; sélection jamais perdue dans un menu, contour rose aligné sur les règles du serveur (`Fix_r4_client_0_panels`) ; fenêtre de chat aussi coupée dans l'interface de base de Roblox (`Fix_r4_client_0`) ; curseur de sélection blanc et épais, visible à 3 m (`Fix_r4_ui_1_root`).
- **Téléphone** : la consigne d'accueil ne recouvre plus le bouton Ping ; la pastille d'événement ne recouvre plus Équipage ni Réglages sur les petits écrans (`Fix_r4_client_0`, `Fix_r4_ui_1_hud`).
- **Accueil** : progression juste des quêtes d'achat, pas de double achat au double appui (`Fix_r4_ui_1`) ; quête météo claire pendant une pluie de météores (`Fix_r4_ui_1_plan`) ; moment « Atlas débloqué » avec sa carte et son son (`Fix_r4_ui_2`).
- Validation croisée de publication (`Fix_r4_release`).

### 6.3 Finition : la dernière passe avant publication (1/11/2026)

Après le tour 4, trois contrôles **indépendants** ont été faits par des ingénieurs qui n'avaient pas écrit le code concerné : un contre-audit anti-triche (§6.3.1), une relecture des corrections du tour 4 (§6.3.2) et une recherche de sons officiels Roblox (§6.3.4). Leurs résultats ont été corrigés dans le commit `81d5bdc` (§6.3.3). Deux tours de QA ont suivi (§6.3.5). Les petits constats encore ouverts sont au §6.3.6.

#### 6.3.1 Contre-audit anti-triche indépendant (« red team »)

**Méthode.** Un ingénieur a joué le rôle d'un tricheur débutant : un programme de triche qui déplace son personnage plus vite ou plus loin que permis. Il a écrit un test jetable de 26 scènes, joué sur le serveur simulé complet, puis supprimé (aucun fichier du jeu modifié). Dans ce test, une scène « triche » qui réussit veut dire que la triche marche.

**Ce qui a été essayé**

| Essai | Ce que tente le tricheur |
|---|---|
| Bond en un seul message | Rester immobile 1 s, puis sauter de 27 studs (à pied), 42 (avec le Dash) ou 57 (Foulée au maximum et Dash) en un seul message réseau, pour couper une file ou prendre la Comète |
| Bond, puis action (V1) | Le même bond, puis agir au message suivant, 0,2 s plus tard |
| Chaînes de pas (V2, V3) | 4 à 6 pas de suite, chacun juste sous la limite : jusqu'à 64 studs/s pendant 0,4 s (environ 97 avec Foulée au maximum et Dash) |
| Vitesse un peu trop forte (V4, V5) | Courir trop vite en permanence, ou alterner arrêts et chaînes de pas |
| Cas limites (V6 à V8, V10) | Faux décalages réseau, bond juste après une réapparition, bord de la zone de capture, chaîne de pas le long d'une file |
| Grande Comète (K1 à K5) | Gagner la course au ramassage depuis 27 studs, voler la Comète, l'encaisser depuis 23 studs en 0,2 s |
| Balise (V9) | Bond jusqu'au bord de l'anneau de la Balise, puis entrer et encaisser |
| Plafond de la Comète (C1, C2) | Obtenir plus d'un Épique à l'explosion de la Comète : en quittant puis revenant, ou à cinq joueurs autour du point |
| Contrôle des joueurs honnêtes (Hn1 à Hn5) | Paquets réseau qui arrivent par 2 ou 3, Dash, sauts sur la pente, chute d'une structure, gel réseau |

**Déjà corrigé au tour 4, confirmé.** Le serveur lit bien le signal « bond » de l'anti-triche ; le bond lui-même n'agit plus (aucune coupe aux trois distances) ; l'anneau de la Balise demande une position validée ; une capture est revérifiée au moment même où elle a lieu ; l'explosion de la Comète donne **un seul Épique par joueur**, y compris dans le même instant sous cinq angles et après un retour sur le serveur.

**Trouvé par le contre-audit, corrigé à la finition** (détails au §6.3.3)

- **Critique** : la règle du bond ne regardait qu'un message à la fois et redonnait la tolérance de 4 studs à chaque message. Un bond suivi d'une action au message suivant, ou une chaîne de pas un peu trop longs, permettait de couper la file d'un enfant, de gagner la course à la Comète, de la voler, de l'encaisser et d'encaisser à la Balise, sans aucune alerte. Corrigé par un **budget d'action** : les 8 variantes reproduites sont bloquées ; les joueurs honnêtes (paquets groupés, Dash, sauts) restent sans aucune alerte. Les anciens tests qui disaient « au message après le bond, il agit » ont été rendus **plus stricts** ; aucun n'a été affaibli.
- **Moyen** (présent depuis la première version) : un joueur honnête qui court pendant un gel réseau de 0,7 s ou plus était ramené d'environ 20 studs en arrière, bloqué 3 s, marqué « instable », et recevait un avertissement qui compte pour l'exclusion des classements. Corrigé.
- **Bas** : les récompenses de proximité de la Comète et le contrôle du port sûr (Zen, Supernova) croyaient le point d'arrivée d'un bond ; une erreur dans le contrôle des captures pouvait arrêter tout un tick du serveur ; la couronne « Conga Royal » restait après le changement de semaine. Corrigés.

**Accepté par conception (ce ne sont pas des défauts)**

- Courir jusqu'à environ 1,5 fois la vitesse normale n'est jamais signalé : c'est la marge prévue par le GDD pour les réseaux lents.
- Un bond qui traverse **sa propre** porte de Nid compte encore, pour ne jamais punir un rattrapage réseau honnête : un tricheur immobile 1 s peut encaisser **sa propre** file depuis environ 27 studs. Il ne prend rien aux autres.
- Une personne qui joue avec plusieurs comptes (ou une bande d'amis) reçoit un Épique de Comète par compte.
- Quitter puis revenir ne remet pas les plafonds à zéro (Comète, récompenses) : ils suivent le compte Roblox. C'est voulu : on ne gagne rien à se reconnecter.

**Encore ouvert (bas)** : un équipier qui fait un bond à côté d'une victime compte comme escorte pendant ce tick et peut empêcher une coupe (il faut un complice ; §6.3.6, n° 1).

#### 6.3.2 Revue indépendante des corrections du tour 4

Un autre ingénieur a relu toutes les modifications du tour 4 (22 fichiers, environ 950 lignes) et vérifié chaque correction avec des tests jetables, de bout en bout quand c'était possible : vrai serveur simulé, puis réseau, puis vrai client avec la vraie géométrie de l'écran. À ce moment, la suite comptait 1 396 tests, tous verts, sans aucun avertissement d'analyse. Les anciens tests modifiés au tour 4 avaient été corrigés proprement, pas affaiblis.

| Résultat de la revue | Corrections | Suite donnée |
|---|---|---|
| **Confirmées de bout en bout** | Réserve pleine qui ne libère jamais une récompense ni un Starborn ; cartes des quêtes Q2, Q5 et Q7 visibles à l'ouverture d'Améliorer ; « Réessayer » de l'écran de chargement atteignable à la manette ; « Atlas débloqué » n'est plus perdu par l'écran du joueur ; double appui sur Acheter ; pastille d'événement et consigne d'accueil qui ne cachent plus Réglages ni Ping ; alerte de queue menacée ; △ vers l'invitation d'équipage ; sélection rendue quand un menu est ouvert ; chat coupé sur console ; curseur blanc | — |
| **Partielles** | Son d'achat et carte « Atlas débloqué » muets (leur son, « LevelUp », était vide) ; main sur Collection arrêtée 0,1 s avant la carte de l'Atlas ; « Météo bientôt ! » affiché 112 s avant une pluie de météores, alors que la météo utile était à 473 s ; sons du jeu encore vides | **Finies à la finition** : sons remplis (§6.3.4), main tenue jusqu'à la carte, compte à rebours de la météo utile |
| **Petites régressions** | Consigne d'accueil sur le bouton Boutique à 568 × 320 sous la barre Roblox de 58 px ; supposition « fenêtre d'achat ouverte » après ✕ appliquée à tous les boutons ; croix ← non protégée dans les menus | **Corrigées à la finition** |
| | Le test des sons figeait la liste des numéros autorisés | **Partiellement** : assoupli dans `Fix_r4_partage_4`, mais `Fix_r5_audio` fige de nouveau 20 des 27 sons (§6.3.6, n° 8) |
| **Effets de bord mineurs** | Pendant un pic de latence, la Comète portée et l'escorte d'équipage n'étaient pas mises à jour pendant un tick | La Comète suit maintenant son porteur à chaque tick ; l'escorte (un tick, sans effet notable) n'a pas été retravaillée |

À vérifier sur une vraie PS5, car le harnais ne peut pas le prouver (M11) : une fenêtre d'achat ou d'invitation de Roblox efface-t-elle la sélection ? La croix directionnelle arrive-t-elle au jeu pendant cette fenêtre ? Le chat de l'interface Roblox est-il bien coupé ?

#### 6.3.3 Corrections de la finition

Tests : `tests/specs/Fix_r5_serveur_anticheat`, `Fix_r5_serveur_data`, `Fix_r5_hud`, `Fix_r5_panels`, `Fix_r5_audio`, `Fix_fin_*`, `Fix_final_release`.

- **Anti-triche : budget d'action** (`MoveCheck`, `Fix_r5_serveur_anticheat`). Le budget est un « seau » de studs : son plafond est la règle d'un tick du GDD, il se remplit à 1,5 fois la vitesse maximale, et sa dette passe d'un message à l'autre. Le joueur n'agit de nouveau (capturer, couper, Comète, port sûr) qu'une fois la dette remboursée. Exploits reproduits puis **bloqués**, sans alerte ni retour en arrière (la tolérance des gels réseau ne change pas) : V1, V2, V3, V9, K1 à K5. Les contrôles honnêtes restent propres : paquets groupés, Dash, sauts sur la pente, réapparition, rattrapage par sa propre porte, anneau de la Balise à pied. Même règle pour le port sûr (Zen, Supernova) et les récompenses de proximité de la Comète (`Fix_fin_server_anticheat_services`).
- **Gel réseau en courant** : un gel honnête de 0,7 à 1,5 s en courant ne donne plus de retour, ni de blocage de 3 s, ni d'icône « instable », ni d'avertissement ; la téléportation reste détectée. **Coût pour un joueur honnête** : s'il continue de courir à pleine vitesse après un gel de 0,7 / 1,0 / 1,5 s, il ne peut rien attraper ni couper pendant environ 0,9 / 1,5 / 2,5 s ; s'il s'arrête, moins d'une seconde (à décider : §6.3.6, n° 9).
- **Serveur trop grand** : si la taille du serveur est réglée au-delà de 12 dans le Creator Hub, un joueur sans Nid voit un message, puis est renvoyé poliment après 30 s (« Cette île est pleine ! Rejoins un autre serveur. »), sauf si un Nid se libère entre-temps (analytics `ServerFullKick`).
- **Données** (`Fix_r5_serveur_data`, `Fix_fin_server_data_publish`) : en ligne, plus aucune sauvegarde de secours en mémoire si les sauvegardes Roblox sont indisponibles : le joueur est renvoyé avec un message et aucun achat n'est validé sans sauvegarde, jusqu'au retour du service ; chaque sauvegarde est liée au compte du joueur (droit à l'effacement, procédure dans docs/04 §8) ; faux signaux d'achat de pass bornés ; erreur de construction du monde rapportée telle quelle ; nouveau script `lune run scripts/prepublish` qui vérifie les 12 numéros de la boutique (guide §5.5).
- **Interface, accueil, console, performances** (`Fix_fin_client_hud_onboarding`, `Fix_fin_client_panels_console`, `Fix_fin_client_world_perf`, `Fix_r5_hud`, `Fix_r5_panels`, `Fix_r5_audio`) : la plupart des constats mineurs du tour 3 (§6.1) ; icône Boutique masquée tant qu'aucun article n'a son numéro ; sons plafonnés et toujours arrêtés ; « Snip » plus aigu pour le coupeur (GDD §9.4).

#### 6.3.4 Sons

**D'où viennent les sons.** Un ingénieur a fouillé, hors ligne, les deux dépôts officiels de Roblox sur GitHub : **Roblox/resources** (modules « Feature Packages » et jeux d'exemple *Plant* et *Gold Rush*) et **Roblox/creator-docs** (la documentation officielle et ses tutoriels). Il a ouvert chaque fichier de jeu et de modèle (105 fichiers), listé chaque son, puis lu les scripts qui les jouent pour savoir **à quel moment Roblox s'en sert**. Ces sons sont publiés par Roblox lui-même : publics et utilisables dans toute expérience, sans rien téléverser. La source exacte (dépôt et fichier) est écrite à côté de chaque son dans `src/shared/Config/Sounds.luau`.

**État : les 27 sons du jeu sont remplis, aucun n'est vide.** Avant le tour 4, les 27 étaient vides (jeu muet). Le tour 4 a rempli les 7 sons d'interface et de navigation ; la finition, les 11 sons les plus sûrs ; le tour 5, les 9 derniers.

| Moment du jeu (GDD §9.4) | Son | Source officielle Roblox |
|---|---|---|
| Bouton pressé ; petite apparition (« NOUVEAU ! », libération, équipage formé) | `Click`, `Pop` | Son joué par Roblox à chaque bouton (*Feature Packages*, `BUTTON_ACTIVATED`) ; `Pop` plus aigu |
| Pièces gagnées (parade, Balise, retour hors ligne) | `Coin` | Son « Coins » du jeu d'exemple *Plant* |
| Récompense : quête, achat, Calendrier, Comète encaissée, fin du bouclier débutant | `Reward` | Effet d'achat de Roblox (*Feature Packages*, `PURCHASE_EFFECT`) |
| Amélioration, jalon de l'Atlas, Starforge | `LevelUp` | « Retro jingle » du tutoriel audio 2D |
| Refus (file pleine…) ; ouverture d'un menu, bannières de météo et de fête | `Error`, `Whoosh` | Fermeture et ouverture de fenêtre (*Feature Packages*) |
| Musique de fond | `Music` | « Upbeat Electronica », tutoriel de musique de fond |
| Capture ; capture Rare et plus | `Catch`, `CatchRare` | Carillon de ramassage du tutoriel des sons en jeu ; pépite d'or du jeu d'exemple *Gold Rush* |
| Coupe « SNIP ! » | `Snip` | Son « Harvest » de *Plant* (« un son de coupe ») ; plus aigu pour le coupeur |
| Impact de la Comète | `CometImpact` | Exemple « Boom-Impact » de la documentation |
| Victoire de la Balise ; Supernova | `BeaconWin`, `Supernova` | Morceau « joyeux, festif » du tutoriel audio 3D (Supernova plus grave) |
| Navigation à la manette (sélection, ○, onglet, bout de liste) | `Select`, `Back`, `Tab`, `Bump` | Survol, fermeture et ouverture (*Feature Packages*), à des hauteurs différentes |
| **À confirmer à l'écoute** (remplis en dernier) | `CometWarn` (alerte Comète), `Ping` | Deux enregistrements **nouveaux** : bip de compte à rebours du module *Photo Booth* de la documentation (peut-être trop discret) ; petit « clink » de *Plant* |
| **À confirmer à l'écoute** | `Scatter` (dispersion), `Bank` (encaissement), `Dash`, `CometSwipe` (vol de Comète), `BeaconStart` (début de la Nuit), `WispPop` (Gloomwisp éclaté), `Cheer` (acclamation) | Réemploi d'un son déjà retenu à une autre hauteur : « whoosh » plus grave ou plus aigu, pièces plus graves, pépite plus aiguë, effet d'achat plus grave, clic très aigu, morceau festif plus aigu et court |

Quand deux moments partagent un enregistrement, leurs hauteurs diffèrent d'au moins 15 % (vérifié par un test). Rien dans les deux dépôts ne correspond vraiment au **début de la Nuit de la Balise** (tombée de la nuit, trêve) : `BeaconStart` est un choix par défaut. Restent **sans son, comme le prévoit le GDD** : le grignotage d'un Gloomwisp, l'échec de la Balise, le porteur de la Comète, et les captures Épiques et plus (aucun son en plus de `CatchRare`).

**Lecture sans danger** (`AudioController`, `Fix_r5_audio`) : un son vide ou qui ne se charge pas reste muet (un avertissement, aucune erreur) ; les réglages Musique et Effets sont respectés ; un même son ne s'empile pas (au plus 3 copies par image et 4 en même temps) ; chaque son s'arrête en fondu au plus tard après sa durée maximale (4 s par défaut) ; un seul jingle à la fois.

**Ce qu'aucun test ne peut faire : écouter.** Les tests vérifient le format et la provenance des numéros, pas qu'un son est joli, pas trop fort, ni toujours en ligne. **Avant de publier, écoutez chaque son dans Roblox Studio** (test M12 du §5) : d'abord `CometWarn` et `Ping`, puis les sept autres « à confirmer ». Pour changer un son : guide §6.4.

#### 6.3.5 Tours de QA 5 et 6

**Tour 5** (après la finition, commit `7ed5583`)

| Constats | À corriger | Graves | Mineurs non retenus pour ce tour |
|---|---|---|---|
| **13** | **7** | **2** | **6** |

Les deux constats graves, **corrigés** :

- **Un enfant debout sur la tête d'un ami** était porté par lui : l'anti-triche le prenait pour un tricheur trop rapide, le ramenait en arrière plusieurs fois, puis l'excluait pour toujours des classements. Corrigé : aucune collision entre personnages (personne ne bloque non plus une porte de Nid avec son corps).
- **Carte d'invitation d'équipage** posée sur les boutons Dash et Ping des téléphones, et sur le suivi de quête sur PS5. Corrigé : elle se pose dans une place libre de l'écran, recalculée toutes les 0,5 s.

Autres corrections (tests `Fix_r5_client_0`, `Fix_r5_ui_1`, `Fix_r5_ui_1_audio`, `Fix_r5_partage_2`, `Fix_r5_serveur_3`, `Fix_r5_release`) :

- **Roue de pings** : plus de roue (Q, croix ↑) avant que l'accueil ait présenté le bouton Ping (GDD §3) ; un menu qui s'ouvre referme la roue ; la roue s'affiche entre le HUD et les menus.
- **Un seul jingle à la fois** : fin de Q4 (quête terminée et « Atlas débloqué ! »), jalon de l'Atlas, amélioration qui termine une quête. Les achats gardent toujours leur son.
- **Écran de chargement sur téléphone à l'horizontale** : le bloc « Réessayer » rétrécit (bouton d'au moins 48 px) et reste entier en bas de l'écran.
- **Sons** : les 9 derniers sons vides sont remplis, « à confirmer à l'écoute » (§6.3.4).

Les 6 constats mineurs du tour 5, revérifiés dans le code :

| Constat | État |
|---|---|
| Un porteur de Comète qui passe sa porte pendant un rattrapage réseau n'encaisse pas | **Corrigé** au tour 6 |
| Objectifs : textes sous 18 px sur un téléphone 640 × 360 | **Corrigé** au tour 6 (sauf « Aujourd'hui » en 568 × 320 : §6.3.6, n° 7) |
| « Rentre au Nid » dit à un joueur déjà dans son Nid (Supernova, Zen) | Ouvert (§6.3.6, n° 2) |
| Rien n'empêche un second achat du Starter Kit avant que le serveur ait prévenu l'écran | Ouvert (§6.3.6, n° 3) |
| Échap liée pour fermer les menus, alors que Roblox garde cette touche | Ouvert (§6.3.6, n° 4) |
| Type des réglages du profil sans `vibration` | Ouvert (§6.3.6, n° 5) |

**Tour 6** (commit `bbded7a`). Corrections (tests `Fix_r6_client_0`, `Fix_r6_ui_1`, `Fix_r6_serveur_2_data`, `Fix_r6_serveur_2_movecheck`, `Fix_r6_serveur_2_comet`, `Fix_r6_release`) :

- **Sauvegarde pendant une panne des sauvegardes Roblox** : un joueur qui part pendant la panne ne perd plus ce qu'il a gagné depuis le début de la panne. Le serveur réessaie en arrière-plan pendant 5 minutes au plus ; un joueur qui revient sur le même serveur attend quelques secondes et retrouve ses données à jour (jamais des données anciennes) ; un achat fait pendant la panne n'est compté qu'une fois. Si la panne dure plus de 5 minutes, la perte est notée « PERTE » dans le journal du serveur.
- **Anti-triche et sauts honnêtes** : un saut dont les premiers messages réseau arrivent d'un coup, ou un gel réseau en haut d'un saut, ne comptent plus comme une triche (plus d'icône « instable » ni de retour) ; planer reste détecté.
- **Comète** : un porteur qui passe sa porte pendant un rattrapage réseau honnête encaisse la Comète au tick suivant s'il est toujours du côté du Nid (un bond suivi d'une ressortie reste refusé).
- **Contour rose « queue menacée »** : il suit maintenant point par point la règle des coupes. Un joueur arrêté dans son port sûr dont la queue dépasse dehors est prévenu ; une queue entièrement à l'abri ne l'est plus.
- **Téléphone** : tous les menus et onglets passent l'audit des textes (au moins 18 px) en anglais et en français, en 640 × 360 et 667 × 375.
- **Pings** : le serveur accepte un ping toutes les 1,2 s (l'écran en propose un toutes les 1,5 s) : un ping n'est plus perdu quand le réseau rapproche deux envois.

#### 6.3.6 Petits constats encore ouverts (revérifiés dans le code le 1/11/2026, commit `bbded7a`)

Aucun n'empêche de publier ni ne fait perdre de progression. Les n° 7 et 9 attendent **votre choix** ; les autres sont de petites corrections pour une mise à jour.

| n° | Où | Constat | Ce que voit le joueur | Proposition |
|---|---|---|---|---|
| 1 | `src/server/Services/CongaService.luau` (escorte) | Un équipier compte comme escorte même pendant un tick où il fait un bond | Un tricheur avec un complice d'équipage peut empêcher une coupe pendant un tick | Ne compter que les équipiers dont la position est validée |
| 2 | `src/server/Services/NestService.luau` | Juste après un retour forcé ou un rattrapage réseau, Supernova et Mode Zen sont refusés avec « Rentre au Nid » même si le joueur est dans son Nid | Message trompeur ; réessayer quelques secondes plus tard marche | Un message plus juste (« Attends un instant ») |
| 3 | `src/client/UI/Panels/Shop.luau` | Juste après l'achat du Starter Kit, son bouton reste proposé jusqu'à ce que le serveur ait prévenu l'écran | Dans ce court moment, un enfant peut le racheter : il confirme et paie une seconde fois, et reçoit le contenu deux fois | Masquer le bouton dès la fin du premier achat |
| 4 | `src/client/Controllers/PanelController.luau` | Échap est liée pour fermer les menus, alors que Roblox garde cette touche pour son propre menu | Sur ordinateur, Échap ouvre le menu de Roblox et ne ferme pas forcément celui du jeu (le bouton ✕ du menu et ○ à la manette marchent) | Retirer Échap ou utiliser une autre touche |
| 5 | `src/shared/Types.luau` | Le type des réglages du profil oublie le réglage `vibration` | Rien (détail technique) | Ajouter le champ |
| 6 | `src/client/UI/ScreenFX.luau`, `src/client/UI/Panels/Crew.luau` | Sur ordinateur et tablette, une carte « NOUVEAU ! » peut passer environ 3 s par-dessus le haut de la carte d'invitation d'équipage | Invitation à moitié cachée pendant 3 s | Faire placer les deux cartes par le même calcul |
| 7 | `src/client/UI/Panels/Goals.luau` | Sur le plus petit téléphone (568 × 320, iPhone SE de 1re génération), l'étiquette française « Aujourd'hui » du Calendrier tombe à 16 px | Texte un peu petit | **À choisir** : un libellé français plus court |
| 8 | `tests/specs/Fix_r5_audio.spec.luau` | Le test des sons fige le numéro, le volume et la hauteur de 20 des 27 sons | Rien pour le joueur ; mais changer ou vider un son fait échouer `./scripts/check.sh` | Mettre le test à jour en même temps que le son (guide §6.4) |
| 9 | `src/server/Util/MoveCheck.luau` | Coût honnête du budget d'action après un gel réseau (§6.3.3) | Après un gel, en continuant de courir, rien n'est attrapé pendant 0,9 à 2,5 s | **À décider** : un remboursement plus rapide demande un nouveau réglage, mais un tricheur pourrait agir plus tôt après un bond. Conseil : garder tel quel et surveiller les plaintes |

Le constat n° 18 du tour 3 (bonus de coupe « tactile » déclaré par le client) reste la question n° 1 du §7.

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
| Créer les 6 passes et 6 produits, coller leurs numéros, puis `lune run scripts/prepublish` (« ✅ Boutique prête ») | Propriétaire | Guide §5, `src/shared/Config/Monetization.luau` |
| Ajouter les administrateurs LiveOps | Propriétaire | Guide §6.1, `src/server/Data/Admins.luau` |
| Recaler la semaine du premier Starfall Saturday | Propriétaire | Guide §6.3, `src/shared/Config/Events.luau` |
| Écouter tous les sons dans Studio, d'abord les neuf « à confirmer à l'écoute » (`CometWarn` et `Ping` en premier) ; faire vider ou remplacer ceux qui déplaisent | Propriétaire (écoute) + équipe technique (changement : un test fige aujourd'hui la plupart des sons et doit être mis à jour en même temps) | Guide §6.4, `src/shared/Config/Sounds.luau` |
| Vérifier les noms « Comet Conga » et « Nebbies » (Roblox et marques) | Propriétaire | GDD §16, risque 7 |
| Questionnaire de maturité, icône, miniatures, taille de serveur 12, langues | Propriétaire | Guide §7 à §10 |
| Plan de test manuel M1 à M13 | Propriétaire + testeurs | §5 |
| Essai sur PS5 avant d'activer la console | Propriétaire | Guide §11 |
| Répondre aux 7 questions de design | Propriétaire | §7 |
