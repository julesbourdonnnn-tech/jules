# Raise a Squishy — Architecture technique (contrat d'implémentation)

> **Document 04.** Version 1.2 du 1er novembre 2026 : application du **GDD v1.3** et des remarques A20 à A29 de la revue d'architecture (journal au §25 ; corrections de la v1.1 au §24). Statut : **contrat figé** pour l'implémentation en parallèle par 8 paquets. Les paquets déjà écrits (logic) ou en cours (world) reçoivent leurs changements par des **notes du contrat v1.2** (§25), jamais par une édition de leurs fichiers.
> Sources : [`02-game-design-document.md`](02-game-design-document.md) (GDD v1.3, cité « GDD §x » ; le §12 est l'architecture de référence), [`03-decision-du-jury.md`](03-decision-du-jury.md) (concept, §8) et la **décision du propriétaire du 1er novembre 2026** : **console d'abord** (PS5 avec DualSense sur une télé, puis Xbox et PC ; aucun téléphone au lancement) et **zéro bug au lancement**. Cette décision passe avant tout le reste.
> Le code du contrat est **déjà dans le dépôt** : configurations avec les vraies données, types, remotes, catalogue des intentions, schéma v1, bus de signaux, ordres d'initialisation, l'utilitaire `Server/Util/Activity` (implémenté et testé par le contrat) et **66 stubs** aux signatures exactes. Il est vérifié par `tests/specs/Contract.spec.luau` (socle) et `tests/specs/Contract_game.spec.luau` (jeu). En cas de doute, **le code du contrat fait foi**, puis ce document, puis le GDD.
> Modèle de format : le document 04 de Comet Conga (`/home/user/jules/roblox-game/docs/04-architecture.md`).

## Sommaire

1. Objet et règles du contrat
2. Paquets et propriété des fichiers
3. Monde : dossiers, instances, attributs, collisions, interactions
4. Temps : `Clock` et `EventClock`
5. Serveur : ordre d'initialisation, dépendances, crochets, cycle de vie des joueurs
6. Le tick de 10 Hz de `ChaseService`
7. Signaux internes du serveur (`Server/Signals`)
8. Données sauvegardées (schéma v1), propriétaires, réplication
9. Configuration (`Shared/Config`) et types (`Shared/Types`)
10. Réseau : intentions, charges utiles, célébrations, recouvrement
11. Services serveur (API)
12. Modules partagés purs et rendu (API)
13. Client : ordre, propriétaires des remotes, API des contrôleurs et de l'interface
14. Console d'abord : disposition télé, navigation, glyphes, vibrations, sons
15. Anti-triche : où chaque action est vérifiée
16. Économie : formules, réglages, simulation, nombres géants
17. Stratégie zéro bug
18. Plan de tests par paquet et specs d'intégration
19. Localisation et sons
20. Décisions d'interprétation du GDD
21. Journal des réglages d'économie
22. Modifications du socle faites par le contrat et notes d'intégration
23. Définition de « fini »
24. Journal des corrections de la version 1.1
25. Journal des corrections de la version 1.2 (GDD v1.3, remarques A20-A29)

---

## 1. Objet et règles du contrat

Ce document permet à **8 ingénieurs** d'implémenter Raise a Squishy **en parallèle**, sans se deviner et sans éditer les fichiers des autres. Chaque module à écrire existe déjà sous forme de **stub** : `Init()`, `Start()` (et `attach()` pour les deux modules de diagnostic) ne font rien ; les autres fonctions publiques lèvent `error("TODO(<paquet>): <Module>.<fonction>")`. Le jeu démarre donc déjà, serveur et client, **sans erreur ni avertissement** (vérifié par `Contract_game.spec`). Implémenter un module, c'est remplacer les `error("TODO…")` par le comportement décrit ici, **sans changer les signatures**. On peut ajouter des fonctions publiques ; on n'en retire et on n'en renomme aucune.

**Règles communes (toutes non négociables)**

1. `--!strict` en tête de chaque module de `src/` ; API publiques typées ; **commentaires en français, identifiants en anglais**.
2. `task.wait/spawn/delay/defer` uniquement (`wait`, `spawn`, `delay` font échouer le harnais).
3. **Autorité du serveur.** Le client n'envoie que des **intentions** (§10.1). Chaque handler suit l'ordre : débit (`RateLimit.allow` avec le débit de `Config/Intents`) → types (`Validate` : nombres finis, entiers, longueurs, tables séquentielles bornées, uid valides) → existence (clé de configuration, uid possédé) → état (profil chargé, personnage vivant, position validée, `canAct`) → règles métier → mutation atomique → réplication. Un message refusé ne produit **aucune** mutation et au plus un `Feedback` neutre. Aucune valeur économique venant d'un client.
4. **Temps.** Toujours `Shared/Util/Clock` (§4), jamais `os.time()`, `tick()` ni `workspace:GetServerTimeNow()` directement. Horodatages **sauvegardés** en `Clock.unix()`. **Aucun minuteur de jeu par `task.delay`** : chaque état porte son heure d'échéance (`Clock.now()`) et le `step(now)` du tick le ferme (fusion 0,4 s, combo 0,6 s, éclosion 2 s, maintiens, éclatement du Grand Splorch 3,2 s, fins de créatures, boosts). Ainsi les tests font voyager le temps et rien ne reste bloqué si un thread meurt.
5. **Données.** Tous les nombres et contenus viennent de `src/shared/Config/*`. Aucun nombre du GDD en dur dans un service ou un contrôleur (les dimensions purement graphiques d'une recette visuelle sont tolérées si elles sont nommées).
6. **Cycle de vie.** Traiter les joueurs déjà présents au branchement de `PlayerAdded` ; nettoyer tout état par joueur à `PlayerRemoving` (un `Trove` par joueur) ; le personnage peut être `nil`, mort ou réapparaître ; **côté client, tout `WaitForChild` a un délai** (et un repli).
7. **Une seule connexion `Heartbeat` côté serveur** : l'accumulateur du tick de `ChaseService` (§6). Les autres services sont « stepés » par lui. Aucun appel DataStore ni aucun yield dans le thread du tick (`task.spawn` pour les écritures de classement et de diagnostics). Côté client : une connexion par image et par système au plus.
8. **Textes** : uniquement des clés de `Shared/Localization/Strings.luau`, en anglais **et** en français (§19). Le serveur envoie des clés ; le client traduit (`Prefs.t`).
9. **Visuels côté client uniquement.** Le serveur n'envoie que des événements compacts ; les squishies et les créatures sont dessinés par le client à partir des données.
10. **Dépendances.** Un module n'appelle directement que des modules initialisés **avant** lui (§5.1, §13.1). Vers les modules plus tardifs, il passe par les **signaux** (§7) ou par un **crochet** que le module tardif enregistre (§5.3).
11. **Un seul propriétaire par clé de profil** (§8) : les autres lisent `DataService.get(player)` sans jamais muter, ou passent par l'API du propriétaire.
12. **Robustesse (zéro bug, §17).** Aucune règle ne dépend de la physique (`Touched` est interdit), d'une animation ou d'un objet pas encore répliqué : distances et zones calculées par le serveur sur la **position validée** ; positions du jeu lues dans `Logic/WorldLayout`, jamais dans le `workspace` ; `StreamingEnabled` coupé ; chaque état a un délai de sortie (`Logic/StateTimeouts`) ; opérations idempotentes ; logique dans des modules **purs et déterministes**.
13. **Zéro trace.** En jeu, aucun `warn` ni aucune erreur n'est attendu. Une étape du tick ou un handler protégé par `pcall` qui échoue appelle `DiagnosticsService.reportCaught(où, erreur)`. Toute spec tourne sous `tests/harness/ZeroLog` (§17). Le harnais ne laisse passer aucune erreur silencieuse : une erreur dans un thread lancé par le code (`task.spawn/defer/delay`, donc chaque handler de signal) va dans `h.errors` et déclenche `ScriptContext.Error` et `LogService.MessageOut` (§17.1 h, fait par le contrat).
14. **Console d'abord** (§14). Une seule disposition, la disposition télé ; tout se fait à la manette, sans curseur virtuel ; clavier et souris en second, même disposition ; **aucun chemin de code tactile** (`Contract_game.spec` fouille `src/`).
15. **Départ = `onBeforeSave(release)`.** Toute mutation de profil « au départ » (règlement et `lastOnline`, boost du partant de la Squish Party, compteurs de session) se fait dans `DataService.onBeforeSave(fn(player, data, release))` quand `release == true`, **jamais dans `PlayerRemoving`** : DataService (rang 2) branche `PlayerRemoving` avant tous les services du jeu, sauvegarde puis oublie le profil. `PlayerRemoving` ne sert qu'à nettoyer l'état de session (Trove). Le même crochet couvre `BindToClose`.
16. **Profil chargé = profil préparé.** Ce qui doit être juste avant que quiconque lise le profil (rebase hors ligne de l'économie) se fait dans `DataService.onPrepare(fn(player, data))` : synchrone, après migration, réconciliation et réparation, **avant** l'instantané envoyé au client et `Loaded`.
17. **Portées à plat, écart depuis les pieds** (v1.2, GDD §12.5, §12.8). Toute portée d'action du serveur (Press, PetPress, Catch, BoopHold, Pot, FeedPlop, MegaPress, Throw, dalles, comptoir) est une distance **XZ** (`ZoneRules.distXZ`) entre la position validée et le centre visé, plus un écart vertical mesuré depuis les **pieds** (`ZoneRules.feetY(pos.Y, rootOffset)` = racine − hauteur debout − hausse de la monture) ≤ `Balance.Catch.MaxDY` (8). Une monture (racine plus haute de 4,3 à 6 studs) ne réduit donc jamais une portée.
18. **Joueurs actifs** (v1.2, GDD §4.22). Le handler d'une intention marquée `activity = true` dans `Config/Intents` appelle `Activity.note(player, Clock.now())` (`Server/Util/Activity`) une fois l'intention acceptée ; ChaseService appelle `Activity.noteMove` avec la position validée de chaque tick. N du MEGA et de la jauge = joueurs actifs (`EventService.activeCount`).

---

## 2. Paquets et propriété des fichiers

Chaque fichier appartient à **un seul** paquet. Un paquet ne crée et ne modifie que ses fichiers. Il peut **ajouter** des modules privés dans son dossier d'aide et des specs `tests/specs/<Nom>.spec.luau` à son nom. S'il a besoin d'un changement dans le fichier d'un autre paquet, du contrat ou du socle, il ne l'édite pas : il le signale dans ses **notes d'intégration**.

**Registres partagés** (exception) : `src/shared/Localization/Strings.luau`, `src/shared/Remotes.luau`, `src/shared/Config/Sounds.luau` et `src/shared/Types.luau`. Tout paquet peut y **ajouter** des entrées : relire le fichier juste avant chaque `Edit`, faire de **petites modifications ciblées**, ne jamais réécrire le fichier, ne jamais renommer ni supprimer une entrée. Pour `Strings.luau` : toujours la clé en anglais **et** en français (parité et variables `{x}` vérifiées). Un remote ajouté a sa ligne dans `Config/Intents.luau` s'il va du client au serveur : c'est alors une **note d'intégration** (fichier du contrat), jamais un ajout silencieux.

| Paquet | Fichiers possédés (stubs à implémenter) | Dossier d'aide | Outils de test et fichiers en plus |
|---|---|---|---|
| **logic** | `src/shared/Logic/Hash.luau`, `src/shared/Logic/BigNumber.luau`, `src/shared/Logic/SizeScale.luau`, `src/shared/Logic/Formulas.luau`, `src/shared/Logic/Odds.luau`, `src/shared/Logic/FusionRules.luau`, `src/shared/Logic/RushRules.luau`, `src/shared/Logic/QuestRules.luau`, `src/shared/Logic/MegaRules.luau`, `src/shared/Logic/EventClock.luau`, `src/shared/Logic/WorldLayout.luau`, `src/shared/Logic/SeededPath.luau`, `src/shared/Logic/PressTiming.luau`, `src/shared/Logic/ZoneRules.luau`, `src/shared/Logic/LeapRules.luau`, `src/shared/Logic/TargetRules.luau`, `src/shared/Logic/StateTimeouts.luau`, `src/shared/Logic/DiagRules.luau`, `src/shared/Logic/Invariants.luau` | `src/shared/Logic/` (modules privés), `tests/sim/` | `tests/harness/Props.luau`, `tests/sim/EconomyModel.luau` ; valeurs de `Config/Balance` |
| **world** | `src/shared/Render/SquishyBuilder.luau`, `src/shared/Render/Squash.luau`, `src/shared/Render/Palette.luau`, `src/server/Services/WorldService.luau`, `src/client/Controllers/LightingController.luau`, `src/first/Loading.client.luau` (repris du socle) | `src/server/World/`, `src/shared/Render/` | — |
| **ranch** | `src/server/Services/RanchService.luau`, `src/server/Services/EconomyService.luau`, `src/server/Services/SquishyService.luau`, `src/server/Services/ProductService.luau`, `src/server/Data/ProfileRepair.luau` | `src/server/Ranch/` | `tests/harness/Chaos.luau` ; note **INT-REPAIR** (seul éditeur de `src/server/Services/DataService.luau` pendant les paquets) |
| **chase** | `src/server/Services/ChaseService.luau`, `src/server/Services/RushService.luau`, `src/server/Services/EventService.luau`, `src/server/Services/SplorchService.luau` | `src/server/Chase/` | `tests/harness/Soak.luau`, `tests/harness/Brains.luau` ; note **INT-MOVE** (seul éditeur de `src/server/Util/MoveCheck.luau` et `src/server/Movement/Tuning.luau`) |
| **meta** | `src/server/Services/QuestService.luau`, `src/server/Services/CommunityService.luau`, `src/server/Services/LeaderboardService.luau`, `src/server/Services/DiagnosticsService.luau`, `src/client/Controllers/ErrorReporter.luau` | `src/server/Meta/`, `src/client/Meta/` | `tests/harness/ZeroLog.luau`, `tests/harness/Fuzz.luau`, `tools/opencloud/`, `tests/engine/`, `tests/engine.project.json`, `src/server/Data/{Admins,Codes}.luau`, `docs/05-guide-publication.md` (v1.2, remarque A28 : tests manuels M1-M18, à livrer avec le paquet) ; note **INT-ANALYTICS** (seul éditeur de `src/server/Util/Analytics.luau` pendant les paquets) |
| **client-world** | `src/client/Controllers/WorldStateController.luau`, `src/client/Controllers/QualityController.luau`, `src/client/Controllers/RanchRenderer.luau`, `src/client/Controllers/ChaseRenderer.luau`, `src/client/Controllers/VFXController.luau`, `src/client/Controllers/CameraController.luau`, `src/client/Controllers/PromptController.luau`, `src/client/Controllers/ChaseController.luau` | `src/client/World/` | — |
| **client-hud** | `src/client/UI/HUD.luau`, `src/client/UI/Banners.luau`, `src/client/UI/Cards.luau`, `src/client/UI/ScreenFX.luau`, `src/client/UI/Prompt.luau`, `src/client/UI/WorldText.luau` (v1.2), `src/client/Controllers/InputController.luau`, `src/client/Controllers/OnboardingController.luau` | `src/client/UI/Hud/` | — |
| **client-panels** | `src/client/UI/FocusGuard.luau`, `src/client/UI/PanelController.luau`, `src/client/UI/ReturnScreen.luau`, `src/client/UI/Panels/Ranch.luau`, `src/client/UI/Panels/Squishydex.luau`, `src/client/UI/Panels/Objectives.luau`, `src/client/UI/Panels/Leaderboards.luau`, `src/client/UI/Panels/Shop.luau`, `src/client/UI/Panels/Settings.luau`, `src/client/UI/Panels/SplorchPreview.luau`, `src/client/UI/Panels/OutfitPreview.luau`, `src/client/UI/Panels/Diagnostics.luau` | `src/client/UI/Panels/` (modules d'aide, ex. `Widgets.luau`) | `tests/harness/TvAudit.luau` |

**Contrat (architecte, figé)** : `docs/04-architecture.md`, `default.project.json`, `src/shared/Types.luau`\*, `src/shared/Remotes.luau`\*, `src/shared/Localization/Strings.luau`\*, `src/shared/Config/Sounds.luau`\*, `src/shared/Config/{Species,Rarities,Mutations,Events,Quests,Pads,Cosmetics,Features,Layout,Intents,Monetization}.luau`, `src/shared/Config/Balance.luau` (structure ; **valeurs** réglées par logic seulement, §16 ; la marque `Balance.GddValues` dit quelle version du GDD les valeurs suivent), les ajouts du contrat dans `src/shared/Config/{Settings,Console}.luau` (§22), `src/server/Data/Schema.luau`, `src/server/Signals.luau`, `src/server/Util/Activity.luau` (v1.2, **implémenté** par le contrat, spec `tests/specs/Activity.spec.luau`), `src/server/Main.server.luau`, `src/client/Main.client.luau`, `tests/specs/Contract_game.spec.luau`. (\* registre partagé.)

**Socle (repris de Comet Conga, propriété de personne)** : `src/shared/{Net}.luau`, `src/shared/Util/*`, `src/shared/Localization/init.luau`, `src/shared/Config/{Console,Settings}.luau` (hors ajouts du contrat), `src/server/Services/{DataService,MonetizationService}.luau`, `src/server/Util/{RateLimit,Analytics,Notify,MoveCheck}.luau`, `src/server/Movement/Tuning.luau`, `src/client/Util/{Platform,Haptics,Prefs,Prices}.luau`, `src/client/UI/{Root,Theme,Create,Juice,Toast,Glyph}.luau`, `src/client/Controllers/{StateController,AudioController}.luau`, `tests/harness/*` (fichiers existants), `tests/sim/Sim.luau`, `scripts/*`, les specs du socle. Toute modification passe par une **note d'intégration** ; celles que le contrat demande sont listées au §22 (INT-*).

**Exceptions de propriété** : `src/first/Loading.client.luau` passe du socle au paquet **world** (habillage du jeu, et partie Loading de la note INT-TV : §22.2), à condition de garder vertes les specs de l'écran de chargement (`Loading.spec`, `Console_loading.spec`, `Fix_r3_partage_2.spec`, `Fix_r5_partage_2.spec`). `src/server/Data/{Admins,Codes}.luau` appartiennent au paquet **meta**. Pendant le travail des paquets, chaque fichier du socle touché par une note d'intégration a **un seul** éditeur : DataService → ranch (INT-REPAIR), MoveCheck et Tuning → chase (INT-MOVE), Loading → world ; les specs du socle restent vertes.

**Étape 0 (faite par le contrat, avant les paquets, v1.1)** : note **INT-TV** (sauf l'habillage de Loading), note **INT-HARNESS** étendue (threads surveillés, services du moteur simulés, compteurs, tableaux à trous refusés, branchement de `ZeroLog` dans `run.luau`), crochet `DataService.onPrepare`, `scripts/soak.sh`. Les paquets travaillent donc dès le départ sur la bonne échelle télé et sous un harnais qui voit chaque erreur. **v1.2** : note **INT-HAPTICS** (`cooldownExempt` dans `Util/Haptics`), **INT-HARNESS v1.2** (`StarterGui:GetCore("GetBlockedUserIds")` simulé, `h:setBlocked`, entrées d'`ApiAudit`), `Net.setup()` après l'attach de DiagnosticsService (`Main.server`). Détail : §22.1.

**Étape d'intégration** (après les 8 paquets, par l'équipe d'intégration) : `tests/specs/Boot.spec.luau`, `tests/specs/Soak.spec.luau`, `tests/specs/ClientReplay.spec.luau`, application des notes des paquets (§18.3) et des notes INT-* restantes (INT-AUDIO, INT-FORMAT, INT-PREPUBLISH, INT-SKILLS).

---

## 3. Monde : dossiers, instances, attributs, collisions, interactions

### 3.1 Construit par le serveur (`WorldService`, paquet world) — GDD §11

`StreamingEnabled` est coupé (`default.project.json`) : toute la carte est sur chaque client à la fin du chargement. Le client n'en a **besoin** que pour l'image : chaque position de jeu vient de `Logic/WorldLayout`.

```
workspace.Wobbleton                      (Folder, construit une fois par WorldService.build)
  Plate, Hills, Walls                    plateau (sol, solide), collines, murs invisibles (r = 322, 30 studs de haut, solides ; MoveCheck : MaxRadius = 330)
  Plaza (Folder)
    MegaPad, Statue, Shop, Altar, GaugeJar, Stage, GoldenFountain
    Boards (Folder) 1 … 5                tableaux des classements (SurfaceGui rempli par le client)
  Streets, Houses, Lamps                 rues, maisons-bonbons (solides, CollisionFidelity Box, coiffe invisible jusqu'à 30 studs : toit inaccessible), lampadaires
  Meadow                                 Prairie des copains (fleurs, panneau)
  Ranches (Folder)
    "1" … "16" (Model)                   un ranch par numéro (WorldLayout.ranchCFrame)
      Fence, FenceWall                   clôture (solide) et mur invisible de 30 studs (solide, WorldLayout.Const.FenceWallHeight)
      Gate                               membrane de gelée : CanCollide = false côté serveur
      Fountain, Sign, PenFloor, SnackMat, Pot, Vat, Pool, Bowl, Cushion, Shelf
      Pads (Folder) 1 … 4                prises de dalles (Config/Pads.Defs[].socket ; rangée Z = 67, à ≥ 8 studs de tout point d'action)
      Decor (Folder) 1 … 18              décorations, cachées tant qu'elles ne sont pas construites
  NeutralSpawn                           SpawnLocation neutre sur la place (repli si le placement échoue)
```

**Attributs posés par le serveur** (lus par le client, jamais nécessaires à une règle) :

| Instance | Attribut | Type | Écrit par | Sens |
|---|---|---|---|---|
| `Ranches/<k>` | `Slot` | number | WorldService | numéro du ranch |
| `Ranches/<k>` | `OwnerUserId` | number | WorldService (`setRanchOwner`, appelé par RanchService) | 0 = ranch libre (gris, sans lumière) |
| `Ranches/<k>/Pads/<i>` | `Tile` | string | WorldService | clé de la dalle de la prise |
| `Plaza/Statue` | `StatueSpecies`, `StatueMutation`, `StatueSize`, `StatueName` | number, number, number, string | WorldService (`setStatue`, appelé par LeaderboardService) | plus gros squishy du serveur ; nom vide = alias côté client |
| `Plaza/GaugeJar` | `Fill` | number | WorldService (`setGauge`, appelé par EventService) | remplissage 0 … 1 |
| `Player` | `RanchSlot` | number | RanchService | ranch du joueur (0 = aucun) |
| `Player` | `Unstable` | boolean | ChaseService | icône neutre « connexion instable » (3 s après un retour forcé) |
| `Player` | `ProfileLoading` | number? | DataService (socle) | essais de chargement (écran de chargement) |
| `Player` | `ClientReady` | boolean | client (local) | ferme l'écran de chargement |
| `Player` | `ClipsUnavailable` | boolean | VFXController (local) | capture vidéo indisponible ou partage interdit : cases « Filmer » et « Clips » cachées |

**Tag CollectionService** : `Solid` sur chaque pièce qui collisionne (plateau, murs du bord, maisons et leur coiffe, clôtures et murs invisibles). `WorldBuild.spec` vérifie que les pièces `Solid` sont exactement les boîtes de `WorldLayout.solids()` (le bond du client, la capture à l'atterrissage et le sol des règles du serveur, `WorldLayout.supportY`, utilisent ces boîtes). Toute autre pièce est `CanCollide = CanQuery = CanTouch = false`. Toutes les pièces sont ancrées. Deux solides sont soit collés sans fente, soit séparés d'au moins 6 studs.

**Hauteur des solides** (décision §20 n° 21) : chaque boîte de `WorldLayout.solids()` (sauf le plateau) mesure au moins `WorldLayout.Const.SolidMinHeight` = 30 studs au-dessus du sol, plus que `MaxReach` = 22 (saut de la selle géante 13 + décalage de racine de la monture 6 + 3 de marge). Personne n'enjambe une clôture ni ne monte sur un toit, même en monture : aucune position « debout sur un toit » n'existe à vérifier. `Contract_game.spec` vérifie les constantes, `WorldBuild.spec` chaque boîte construite.

### 3.2 Dossiers côté client

Le client crée `workspace.ClientWorld` (Folder local) : `Squishies/<slot>` (RanchRenderer), `Creatures` (ChaseRenderer), `Effects` (VFXController), `Meadow`, `Silhouettes`, `StatueModel`. Tout y est ancré et sans collision. Les flocons du costume d'hiver suivent la caméra. Les `ScreenGui` viennent tous de `UI/Root` (`Root.screen` / `Root.safe`).

### 3.3 Collisions

- Groupe de collision `Characters` qui ne se touche pas lui-même : enregistré par `WorldService.Init` (`PhysicsService:RegisterCollisionGroup`, `CollisionGroupSetCollidable`) ; chaque pièce du personnage y est mise par `RanchService` à `CharacterAdded` (et `DescendantAdded`). Personne ne porte personne, personne ne bloque un portail.
- Membrane du portail : non solide sur le serveur ; chaque client la rend solide **pour lui seul** sur les ranchs des autres (`RanchRenderer`, `CanCollide` local). La règle est la **poussée du serveur** (`RanchService.step`).

### 3.4 Interactions dans le monde : aucune `ProximityPrompt`

Décision du GDD (§10.4, Annexe A) : **aucune `ProximityPrompt`**. Leur choix de cible, leur ligne de vue et leur liaison de touche appartiennent au moteur et ne se testent pas hors de Roblox. À la place : `PromptController` choisit la cible (`Logic/TargetRules`), `UI/Prompt` dessine l'invite (glyphe 64 + mot 40 px TV), `InputController` lie les touches par `ContextActionService:BindActionAtPriority` seulement quand une invite est affichée et qu'aucune fenêtre n'est ouverte. Conventions :

| Action | Manette (PS) | Clavier / souris | Portée serveur (position validée) | Maintien | Intention | Texte |
|---|---|---|---|---|---|---|
| Presser | □ (`ButtonX`) | E / clic | 10 + 2 studs à plat du centre de la place du squishy (pieds ≤ 8) | — | `Press` | `prompt.press` |
| Prendre / Poser | ○ (`ButtonB`) | Q | 10 studs | — | `PickUp` / `PutDown` | `prompt.pickup` / `prompt.putdown` |
| Lancer (en portant) | □ | E | 12 studs du Bassin | — | `Throw` | `prompt.fusion` / `prompt.putInPool` |
| Acheter (sur une dalle) | □ (tout de suite) ou rester 0,6 s dessus | E, ou rester 0,6 s | dedans ≤ 2,5 / sortie > 3,5 (à plat) | 0,6 s (`HoldState` « tile ») | `BuyTile` (ou attente détectée par le serveur, un achat par entrée) | `prompt.buy` |
| Encaisser le Pot | marcher dessus | marcher dessus | 5 studs | — | aucune (tick) | — |
| Attraper | □ (+ tampon 0,25 s) | E | 5 + 1,5 à plat à l'instant `tClient` (8 + 1,5 propriétaire), pieds ≤ 8 | — | `Catch` | `prompt.catch` |
| Booper (depuis la rue) | □ maintenu | E maintenue | 8 studs | 2,5 s (5 s propriétaire proche) | `BoopHold` | `prompt.boop` |
| Nourrir au bol | □ maintenu | E maintenue | 8 studs à plat | 2 s | `FeedPlop` | `prompt.feed` |
| Pet-sitting (chez un ami) | □ | E | côté rue, 10 + 2 à plat du centre de la place à la clôture | — | `PetPress` | `prompt.petsit` |
| Presser le MEGA | □ | E | 20 studs du centre | — | `MegaPress` | `prompt.press` |
| Comptoir de la Boutique | □ | E | 8 studs à plat | — | aucune (ouvre le panneau) | `prompt.sell` / `prompt.shop` |
| Bondir (et attraper à l'atterrissage) | R2 | Maj | 16 studs de visée | — | `Leap` | `hud.leap` |
| Monter / descendre | L2 | R | partout | — | `Ride` | `prompt.ride` / `prompt.dismount` |
| Changer de cible | L1 / R1 | clic sur un squishy (4 s) | — | — | aucune | `prompt.choose` |
| Menu | △ ou croix ↓ | M (`KeyCode.M` et `KeyCode.Semicolon`, AZERTY) ou clic ; **jamais Tab** (liste des joueurs de Roblox) | — | — | aucune | `hud.menu` |
| Panneaux directs | — | G Ranch, C Squishydex, J Objectifs, L Classements, B Boutique, P Réglages | — | — | aucune | — |
| Emotes | croix ↑ → ← | 1 2 3 | — | — | `Emote` | `emote.*` |
| Applaudir (8 s) | croix → | F ou clic | — | — | `Clap` | `prompt.clap` |

Jamais deux invites sur la même touche ; deux invites au plus ; aucune invite (et aucune touche du jeu liée) quand une fenêtre est ouverte. Les anneaux de maintien suivent l'heure de fin **envoyée par le serveur** (`BoopState.endsAt`, `HoldState.endsAt` : bol et attente sur une dalle). Les textes des invites et du monde passent par `UI/WorldText` (§13.5) : `BillboardGui` en px TV, jamais en studs. Les squishies vendus ou relâchés depuis le panneau : ○ vide d'abord une sélection multiple ; en portant, ○ ferme d'abord le menu ouvert, puis pose (ouvrir le menu ne termine pas le portage, ouvrir un panneau si).

---

## 4. Temps : `Clock` et `EventClock`

- `Shared/Util/Clock` (socle, inchangé) est la seule source de temps : `Clock.now()` (secondes UTC fractionnaires, identiques serveur et client), `Clock.unix()` (entier, pour tout ce qui est **sauvegardé**), `Clock.day()`, `Clock.week()` (lundi 00:00 UTC), `Clock.weekday()` (0 = dimanche … 6 = samedi), `Clock.secondOfDay()`, `Clock.untilNextDay()`, `Clock.untilNextWeek()`. Tests : `Clock.freeze(t)`, `Clock.advance(dt)`, `Clock.setOffset(s)`, `Clock.unfreeze()`, `Clock.reset()`.
- Les commandes de développement (`AdminCommand`, §11.10) peuvent décaler l'horloge du serveur (`Clock.setOffset`), **en Studio seulement** (jamais sur un serveur privé : les horodatages sauvegardés en seraient faussés) ; `EventState.offset` porte ce décalage et `WorldStateController` l'applique au client : serveur et client gardent la même heure.
- `Shared/Logic/EventClock` (pur, paquet logic) calcule les phases de chaque événement à l'instant t à partir de `Config/Events` :

| Événement | Horaire UTC | Durée | Fonction |
|---|---|---|---|
| Golden Wobbler | :00:30, :10:30, :30:30, :40:30 | 30 s | `EventClock.golden(t)` |
| Sirène du BOOP RUSH | 10 s avant le Rush | 10 s | `EventClock.rush(t).sirenAt` |
| BOOP RUSH | :05, :15, :25, :35, :45, :55 | 90 s | `EventClock.rush(t)` |
| Alerte MEGA | :19:45, :49:45 | 15 s | `EventClock.mega(t).warnAt` |
| MEGA SQUISH | :20, :50 | 60 s de pression + 5 s | `EventClock.mega(t)` |
| Jelly Moon | samedi 16:00, 18:00, 20:00, 22:00 ; dimanche 16:00 | 20 min | `EventClock.moon(t)` |
| Remise à zéro du jour / de la semaine | 00:00 ; lundi 00:00 | — | `Clock.day()`, `Clock.week()` |

- **Un seul grand spectacle à la fois**, au moins `Events.SpectacleGap` (20 s) entre deux. Les horaires fixes le garantissent entre Rush et MEGA (`EventClock.spec` le prouve sur 100 000 créneaux). Le Grand Splorch et la danse de Big Plop passent par la **file du serveur** de `EventService` (§11.10).
- **Index** : chaque phase porte un `index` global (numéro du créneau depuis l'époque), qui sert de graine (`EventClock.seed(kind, index)`) et de clé d'idempotence (un Rush n'est traité qu'une fois, même si le tick rattrape plusieurs pas).

---

## 5. Serveur : ordre d'initialisation, dépendances, crochets, cycle de vie

### 5.1 Ordre (GDD §12.3)

`Main.server.luau` : pour chaque service de la liste, `require` puis, s'il existe, `attach()` aussitôt (réservé à DiagnosticsService) ; **juste après le premier module (DiagnosticsService), `Net.setup()` crée les remotes** (v1.2, remarque A29 : Diagnostics voit les erreurs de tout le démarrage, création des remotes comprise, GDD §12.3) ; ensuite `Init()` de tous dans l'ordre, puis `Start()` de tous. Chaque appel est isolé par `xpcall` (une panne est signalée, la suite démarre).

| Rang | Service | Paquet | Appelle directement (rangs précédents seulement) |
|---|---|---|---|
| 1 | DiagnosticsService | meta | aucun service (utilitaires, `Data/Admins`, `Logic/DiagRules`) |
| 2 | DataService | socle | — |
| 3 | MonetizationService | socle | DataService |
| 4 | WorldService | world | DiagnosticsService |
| 5 | RanchService | ranch | DiagnosticsService, DataService, WorldService |
| 6 | EconomyService | ranch | DataService, MonetizationService, RanchService, DiagnosticsService |
| 7 | SquishyService | ranch | DataService, MonetizationService, RanchService, EconomyService |
| 8 | QuestService | meta | DataService, RanchService, EconomyService, SquishyService, WorldService |
| 9 | CommunityService | meta | DataService, RanchService, EconomyService, SquishyService, QuestService |
| 10 | EventService | chase | DataService, WorldService, RanchService, EconomyService, SquishyService, QuestService, CommunityService, DiagnosticsService |
| 11 | RushService | chase | DataService, RanchService, SquishyService, QuestService, CommunityService, EventService |
| 12 | SplorchService | chase | DataService, RanchService, EconomyService, SquishyService, CommunityService, EventService |
| 13 | ProductService | ranch | DataService, MonetizationService, EconomyService, SquishyService, EventService |
| 14 | LeaderboardService | meta | DataService, WorldService, SquishyService, CommunityService |
| 15 | ChaseService | chase | tous les précédents ; porte le tick (§6) |

### 5.2 Dépendances « vers le haut »

Un service plus précoce ne connaît jamais un service plus tardif. Pour l'informer, le service tardif **écoute un signal** (§7) ou **enregistre un crochet** chez le précoce (§5.3). Les modules purs (`Shared/Logic`) et les configurations sont lisibles par tous.

### 5.3 Crochets (le service tardif s'inscrit chez le service précoce)

| Crochet | Chez | Inscrit par | Usage |
|---|---|---|---|
| `RanchService.setZoneHandler("pot", fn)` / `("pad", fn)` | RanchService | EconomyService (Start) | le tick détecte l'entrée sur le Pot, ou l'attente de `Balance.Tiles.DwellSeconds` sur une dalle (une fois par entrée) ; EconomyService encaisse ou achète |
| `EconomyService.onSettle(fn)` | EconomyService | SquishyService (Start) | après chaque règlement : trophées et record (`biggestEver`) mis à jour avec le nouveau G |
| `DataService.onPrepare(fn)` | DataService (socle, ajouté par le contrat) | EconomyService (Init) | rebase hors ligne pur et synchrone (G, Pot, `growth.t = Clock.now()`), après la réparation du profil et **avant** l'instantané et `Loaded` (§11.5) |
| `DataService.onBeforeSave(fn)` | DataService (socle) | EconomyService, ProductService, QuestService | avant chaque écriture : `settle` (EconomyService) ; si `release == true` (départ, `BindToClose`) : `lastOnline` (EconomyService), secondes de Squish Party achetées et non jouées de l'acheteur (`EventService.partyUnplayed`, ≤ 600 par achat) en boost personnel (ProductService), compteurs de session (QuestService). Jamais de mutation de profil dans `PlayerRemoving` (§1 règle 15) |
| `DataService.setStreamOrder("squishies", fn)` | DataService (socle) | SquishyService | ordre d'envoi de la collection (enclos et Bassin, puis Dodo, puis Lettres) |
| `MonetizationService.registerProduct(clé, fn)` | MonetizationService (socle) | ProductService | effets des produits ; `true` seulement après la mutation |
| `Notify.BANNER_PRIORITY[sorte] = p` | Notify (socle) | CommunityService (Init) | priorités recopiées de `Config/Events.Banners.Priority` |
| `MoveCheck.setSurface(fn)` | MoveCheck (socle) | ChaseService (Init) | surface analytique `WorldLayout.groundY` (règles de racine enfouie) |
| `MoveCheck.setRootOffset(player, studs, jumpHeight)` | MoveCheck (INT-MOVE, paquet chase) | SquishyService | hausse de la racine de la monture (`rideStats.hipHeight − Balance.Ride.BaseHipHeight`) et hauteur de saut de la selle (`rideStats.jumpHeight`) à chaque montée ; `(0, Balance.Ride.BaseJumpHeight)` à chaque descente (même forcée) ; marge verticale ponctuelle égale au changement et montée permise par tick `max(12, √(2 × 196,2 × jumpHeight)) × dt × Margin + Slack` (§11.6, §22.2) |
| `MoveCheck.grant(player, studs, duration, tStart)` | MoveCheck (INT-MOVE) | ChaseService (`Leap`) | crédit du bond : 12 studs sur 0,35 s au plafond par tick, au budget d'action et à la fenêtre soutenue d'1 s ; rétroactif jusqu'à 0,3 s avant la réception ; refusé si le précédent a moins de 4 s (horloge du serveur). Remplace `noteSpeed(GrantSpeed)` (§20 n° 14) |

### 5.4 Cycle de vie d'un joueur

1. `PlayerAdded` (et joueurs déjà présents) : `RanchService` attribue un ranch (ranch libre le plus proche de celui d'un ami Roblox présent, sinon le plus petit numéro libre ; `IsFriendsWith` sous `pcall`, en cache). Plus de ranch libre : `feedback.serverFull`, puis renvoi après 30 s (`kick.serverFull` dans sa langue, analytics `ServerFullKick`), annulé si un ranch se libère. `WorldService.setRanchOwner`.
2. `CharacterAdded` : `RanchService.place` (HumanoidRootPart attendu 10 s ; `PivotTo(WorldLayout.spawnCFrame(slot))` ; `Signals.ServerMoved`) ; pièces dans le groupe `Characters`. Échec : repli sur `NeutralSpawn`, nouvel essai à la prochaine apparition.
3. `DataService.Loaded(player, data)` :
   - EconomyService : le rebase hors ligne (G et Pot) est **déjà fait** par `onPrepare` (aucun règlement ne peut intégrer l'absence au tarif plein) ; ici : `Celebrate "return"` si absence ≥ 10 min, multiplicateurs, publication de l'état public (R, Fame, dalles, croissance).
   - SquishyService : caches, publication des squishies d'enclos et du Bassin, selle ; **premier squishy du compte** : quand QuestService lui donne le Plop de l'accueil, `give` pose `bf = 1` sur le premier squishy jamais créé (`nextUid == 1`).
   - QuestService : `firstJoin`, sessions, reprise de l'accueil à l'étape suivante (les naissances scriptées déjà faites ne sont jamais rejouées), objectifs du jour (tirage ou remise à zéro).
   - RushService : mode effectif (Cozy si jamais choisi ; serveur privé : Cozy sauf autorisation).
   - CommunityService : réglages, amis présents (et ceux des autres joueurs), alias si nom caché.
   - LeaderboardService : changement de semaine (`weekly.prev`).
4. `Signals.PlayerReady(player, slot)` : émis par RanchService une fois par session, quand le profil est chargé et le ranch attribué, **dès le premier placement réussi et au plus tard 15 s après** (`StateTimeouts` « playerReady ») même si le placement a échoué (il est réessayé à part, repli sur `NeutralSpawn`). EventService envoie `EventState`, ChaseService les créatures actives, RanchService le `RanchSnapshot`, LeaderboardService son état, DiagnosticsService le « bonjour » du panneau aux administrateurs ; QuestService marque l'étape 1.
5. Réapparition : portage terminé (le squishy retourne à sa place), monture retirée, replacement dans le ranch, `MoveCheck.reset` (par `ServerMoved`). L'étape d'accueil en cours reprend.
6. Départ. **Mutations du profil** : uniquement dans `DataService.onBeforeSave` avec `release == true`, appelé par DataService pendant sa sauvegarde de départ (règle §1 n° 15) : EconomyService règle et pose `lastOnline` ; ProductService accorde à l'acheteur d'une Squish Party encore en cours ses secondes achetées et non jouées (`EventService.partyUnplayed`, 600 au plus par achat) en boost personnel ; QuestService écrit ses compteurs de session. La fermeture du serveur (`BindToClose`) passe par le même crochet pour chaque joueur présent (aucune fête payée perdue). **`PlayerRemoving`** : chaque service nettoie seulement son état de session (Trove). Les fuites du joueur rentrent aussitôt (rien n'a quitté le profil) ; sa place dans la file du Grand Splorch est rendue (rien n'est remis à zéro) ; parti pendant son spectacle avant l'éclatement : EventService efface aussitôt `EventState.spectacle.current` et les clients arrêtent le spectacle sans pluie de cadeaux (remarque A26) ; sa Squish Party continue pour les autres ; ses clôtures sont libérées ; **ChaseService appelle `MoveCheck.clear(player)`** (remarque A26) ; `RateLimit.clear` et `Activity.clear` (branchés sur `PlayerRemoving` par les utilitaires eux-mêmes) ; analytics `SessionLength`, `PostBoopQuit` / `QuitBaseline`, `BoostShare` (part de la session en ×2).

---

## 6. Le tick de 10 Hz de `ChaseService`

Accumulateur sur `RunService.Heartbeat`, pas fixe `Tuning.TickStep` (0,1 s), au plus `Tuning.MaxCatchUp` (3) pas rattrapés par image. `ChaseService.tick(now)` est appelable directement par les specs. Chaque étape est protégée (`pcall`) ; une erreur est comptée par `DiagnosticsService.reportCaught("tick:<étape>", err)` et n'arrête ni les autres joueurs ni les étapes suivantes. Budget : < 3 ms en moyenne avec 16 joueurs.

```
tick(now):
 1. acteurs = joueurs chargés, prêts (PlayerReady) et vivants (HumanoidRootPart)
 2. pour chaque acteur (pcall par joueur) :
      MoveCheck.noteSpeed(player, humanoid.WalkSpeed, now) si la vitesse serveur a changé
      verdict, back, burst = MoveCheck.step(player, root.Position, dt, now, WorldLayout.supportY(root.Position))
      "rewind" → PivotTo(back), attribut Unstable 3 s, Signals.MoveViolation, strikes (flags)
      TickActor = { pos = MoveCheck.lastValid(player), canAct = verdict == "ok" and not burst
                    and MoveCheck.canAct(player, now), riding = SquishyService.riding(player),
                    rootOffset = MoveCheck.rootOffset(player) }
      Activity.noteMove(player, TickActor.pos, now)   (joueurs actifs, §1 règle 18)
 3. RanchService.step(now, acteurs)        intrus repoussés ; entrée sur le Pot → crochet ; dalle : entrée puis
                                           0,6 s dessus sans porter ni autre maintien (HoldState « tile ») → crochet
 4. EconomyService.step(now)               règlements échelonnés (30 s), fins de boost, Pot automatique (5 s)
 5. SquishyService.step(now, acteurs)      gouttes de Cuve dues, éclosions, fusions et combos dus, portage hors du ranch
 6. QuestService.step(now)                 temps de jeu, accueil (délais, script), minuit, maintien du bol, carte sommeil
 7. CommunityService.step(now, acteurs)    clôtures de pet-sitting, fenêtres d'applaudissement, file des bannières
 8. EventService.step(now, acteurs)        phases EventClock → Signals.EventPhase ; MEGA (pressions agrégées,
                                           MegaBeat toutes les 0,25 s, fin) ; jauge ; fêtes ; file des spectacles ; Autel
 9. RushService.step(now, acteurs)         clôtures (renouvellement 20 s), maintiens de boop finis ou rompus, carte du choix
10. SplorchService.step(now)               éclatement dû (3,2 s), fin du spectacle (coupure dure à 10 s)
11. créatures : apparitions dues (fuite personnelle, Golden, Wild, démonstration), fins (20 / 25 / 30 s)
12. bonds dus : capture tentée à l'atterrissage (tClient du bond + 0,35 s) au point de LeapRules.landing
13. captures : intentions Catch(id, tClient) reçues depuis le tick précédent, dans leur ordre d'arrivée,
    chacune à SON instant tClient : SeededPath.pos(tClient) contre MoveCheck.positionAt(joueur, tClient)
    (historique interpolé de 0,5 s des positions acceptées), à plat ≤ rayon + 1,5, pieds ≤ 8, canAct
14. diffusion groupée : ChaseEvent (4 Hz, tous ou un seul), RanchService.flush() (RanchPatch du tick)
15. LeaderboardService.step(now), DiagnosticsService.step(now)   (écritures DataStore en task.spawn)
```

Le sol passé à `MoveCheck.step` est `WorldLayout.supportY(position)` : pur, max de la surface analytique et du haut des solides sous la position ; **jamais** un `Blockcast` ni un `Raycast` pour une règle (dépendance au moteur, non testable). Les solides étant plus hauts que toute portée (§3.1), un joueur honnête n'est jamais « en vol » au-dessus d'un mur.

Les intentions qui exigent un lieu (Press, PickUp, Throw, BoopHold, FeedPlop, MegaPress, PetPress, Catch) sont traitées **dans leur handler** avec la dernière position validée (`ChaseService.actors()[player]` ou `MoveCheck.lastValid` + `MoveCheck.canAct`), jamais avec la racine brute du client (§15), en distance **à plat** et écart vertical depuis les pieds (§1 règle 17). Les captures sont mises en file et vérifiées au tick (étape 13) à l'instant `tClient` de l'appui (GDD §12.5) : un joueur à 250 ms de ping ne perd plus ses captures, et un tricheur qui choisit son `tClient` gagne au plus 0,35 s de trajet.

---

## 7. Signaux internes du serveur (`src/server/Signals.luau`)

Chaque signal a **un** émetteur. Les handlers tournent chacun dans un thread lancé aussitôt (`task.spawn`) : sans yield, ils finissent avant que l'émetteur reprenne. Une erreur dans un handler n'arrête ni l'émetteur ni les autres handlers ; dans le harnais elle va dans `h.errors` et fait échouer la spec (§17.1 h).

| Signal | Arguments | Émis par | Écouté par |
|---|---|---|---|
| `ServerMoved` | Player | RanchService | ChaseService (`MoveCheck.reset`) |
| `MoveViolation` | Player, infractions | ChaseService | DiagnosticsService (contexte), Analytics `MoveViolation` |
| `BannerRequested` | sorte, args, source? | tous (via `Notify.banner`) | CommunityService (file) |
| `PlayerReady` | Player, slot | RanchService (au premier placement, au plus tard 15 s après le chargement) | QuestService, CommunityService, EventService, LeaderboardService, DiagnosticsService, ChaseService |
| `WorldRequested` | Player | RanchService | EventService, ChaseService |
| `ProfileRepaired` | Player, champs | DataService (INT-REPAIR) | DiagnosticsService |
| `Pressed` | Player (propriétaire), PressInfo | SquishyService | QuestService, EventService (jauge : perfect seulement chez soi, petSit au visiteur ; `press` vaut 0) |
| `TileBought` | Player, dalle, niveau | EconomyService | QuestService |
| `PotCollected` | Player, montant, auto | EconomyService | QuestService |
| `SquishyObtained` | Player, uid, source | SquishyService | QuestService |
| `Hatched` | Player, uid, rareté | SquishyService | QuestService, EventService |
| `Fused` | Player, uid, étape | SquishyService | QuestService, EventService, LeaderboardService |
| `SquishyRemoved` | Player, uid, raison | SquishyService | RushService, CommunityService, ChaseService |
| `Caught` | Player (attrapeur), CatchInfo | ChaseService | QuestService, EventService, LeaderboardService |
| `NearCatch` | Player, sorte | ChaseService | QuestService, EventService |
| `Booped` | boopeur, propriétaire, uid, angle | RushService | ChaseService (crée la fuite), QuestService |
| `EscapeEnded` | propriétaire, uid, issue, attrapeur? | ChaseService | RushService, QuestService |
| `ModeChanged` | Player, rush | RushService | ChaseService |
| `EventPhase` | sorte, phase, index | EventService | RushService, ChaseService, SplorchService, QuestService |
| `SpectacleStarted` | sorte, userId, départ | EventService | SplorchService |
| `MegaJoined` | Player, points, réussite | EventService | QuestService |
| `Splorched` | Player, nouveau R, cadeaux donnés | SplorchService | QuestService, LeaderboardService (« Plus généreux »), RushService, EventService (jauge : splorch, une fois) |
| `Fed` | Player, jours | QuestService | EventService |
| `OnboardingStep` | Player, étape | QuestService | ChaseService, CommunityService |
| `Stamped` | Player, nombre | QuestService | LeaderboardService |
| `Emoted` | Player, sorte | CommunityService | QuestService |
| `SettingChanged` | Player, clé, valeur | CommunityService | tout service qui en dépend (LeaderboardService : `hideName`) |
| `FriendsChanged` | Player, nombre d'amis présents | CommunityService | QuestService (`QuestCtx.friendOnServer`, objectif 12, `stats.lastFriendDay`) |
| `PetSitRewarded` | visiteur, propriétaire, compte pour « Plus serviable » | CommunityService (pression de pet-sitting **récompensée** : `caps.petSit` du visiteur et `caps.petSitIn` du propriétaire sous leur plafond ; 3e argument vrai si `caps.petSitBy[propriétaire]` du visiteur était sous 20, `EconomyService.consumeFriendCap`) | LeaderboardService (« Plus serviable » seulement si le 3e argument est vrai), QuestService |
| `UiSeen` | Player, écran | QuestService (intention `UiSeen`, une fois par écran et par session) | RushService (`"modeCard"` : délai de 20 s de la carte du choix) |

Types : `Signals.PressInfo = { uid, perfect, streak, visitor? }`, `Signals.CatchInfo = { kind, species, rarity, mutation, ownerId, hero, byLeap, babyUid }`.

---

## 8. Données sauvegardées (schéma v1), propriétaires, réplication

Le schéma est dans `src/server/Data/Schema.luau` (contrat). Magasin `PlayerData_v1`, clé `player_<UserId>`, gérés par le `DataService` du socle (verrou de session à jeton, reprise après 5 lectures réussies seulement, jamais sur des erreurs, `BindToClose`, `{ UserId }` à chaque écriture, schéma plus récent refusé, aucun repli en mémoire en ligne). Sauvegarde automatique (90 s), au départ, à la fermeture, et immédiate après un achat Robux ou un Grand Splorch (`DataService.saveNow`).

### 8.1 Clés et propriétaires (une clé = un service qui écrit)

| Clé | Propriétaire | Contenu (valeurs par défaut dans `Schema.defaults()`) |
|---|---|---|
| `version` | DataService | 1 |
| `firstJoin` | QuestService | `Clock.unix()` de la première arrivée |
| `lastOnline` | EconomyService | `Clock.unix()` de la dernière présence (hors ligne) |
| `settings` | CommunityService | réglages sauvegardés de `Config/Settings` (dont `hideName`, `receiveGifts`, `clips`, `emoteLeft`, `partyShowName`) |
| `passes`, `receipts` | MonetizationService | passes possédés ; 100 derniers `PurchaseId` (privé) |
| `codes` | QuestService | toujours `{}` au lancement (aucun code, aucun champ de texte : GDD §13) ; privé |
| `flags` | ChaseService | `{ strikes, lbBanned = false (champ du socle, jamais vrai), lbBanUntil }` ; privé |
| `coins`, `pot`, `R`, `fame` | EconomyService | monnaie, Pot, niveau de Grand Splorch, Fame (pas de `lastSettle` : le règlement part de `growth.t`, §11.5) |
| `growth` | EconomyService | croissance cumulée `{ G, g, t }` (§8.3) ; `t` = `Clock.now()` du dernier règlement (borne de l'intégrale du Pot) |
| `tiles` | EconomyService | `{ snack, decor, pens, cozyBed, seen }` (seen = masque des dalles découvertes) |
| `boosts` | EconomyService | `{ personalLeft }` (secondes du boost personnel, en pause pendant un boost de serveur : bol de Plop, secondes non jouées d'une Squish Party achetée) |
| `caps` | EconomyService | plafonds du jour `{ day, rushBabies, splorchGifts, splorchCoins, fameRush, fameRelease, petSit, petSitIn, petSitBy, claps, partyBuys }` : `petSit` = pressions récompensées comme visiteur (100), `petSitIn` = reçues comme propriétaire (100), `petSitBy[tostring(UserId du propriétaire)]` = pressions comptées pour « Plus serviable » (20 par ami, `Balance.CapsPerFriend`), `splorchCoins` = cadeaux en pièces des Grands Splorch des autres (10, ensuite 10 s). La clé `coinBuy` de la v1.1 est **retirée** (paquets de pièces retirés du lancement) |
| `squishies` | SquishyService | `[uid] = SquishyRecord` (§8.2) ; **envoyée par morceaux** (`STREAMED_KEYS`) |
| `nextUid`, `mount`, `vat`, `released`, `trophies`, `outfits`, `biggestEver` | SquishyService | uid suivant ; monture choisie ; Cuve `{ fillAt, pending, pityRare, pityEpic, newPulls, pulls }` (`pending` seulement quand enclos **et** Boîte à dodo sont pleins) ; 12 derniers relâchés ; records par espèce (tableau dense dès la création : `table.create(#Species.List, 0)`) ; garde-robe `{ owned }` : la tenue portée n'est gardée **que** dans `squishies[uid].o` (`outfits.worn` obsolète depuis la v1.2 : gardé vide, jamais lu ni écrit, vidé par ProfileRepair) ; record de taille (selles) |
| `golden` | ChaseService | `{ lastWinAt }` (`Clock.unix()`, recharge de 20 min, même après un changement de serveur) |
| `moon` | EventService | `{ lastSession }` : séance de Jelly Moon (numéro global de `EventClock.moon`) où la Goutte de Lune a été donnée ; une par séance et par compte, même après un changement de serveur (v1.2) |
| `mode` | RushService | `{ rush, chosen, changedAt, cardShown, postBoopCardShown }` |
| `dex`, `plopDays`, `lastFeedDay`, `onboarding`, `objectives`, `stats` | QuestService | Squishydex (masques denses par espèce dès la création ; `dex.fam` : tableau dense, une case par famille de `Species.FamilyOrder` (liste en ajout seul), 1 = bonus de famille gagné **pour toujours**, écrit par QuestService au tampon qui complète la famille) ; jours de Plop ; dernier repas (`Clock.day()`) ; `{ step, done, demoDone }` ; objectifs du jour ; statistiques (dont `playSeconds`) |
| `cosmetics` | CommunityService | `{ saddle, trail, title, theme, flag }` équipés |
| `weekly` | LeaderboardService | valeurs de la semaine et `prev` |
| `ascend`, `season`, `slowJelly`, `parcels`, `fameLineage`, `worldFirst`, `costumes`, `packs` | (réservé, janvier et février) | valeurs neutres, jamais lues ni écrites au lancement ; `packs = { side = 0, quoteProduct = "", quoteAmount = 0, quoteAt = 0 }` : porte-monnaie « Pièces de côté » et devis du serveur si le propriétaire rouvre les paquets de pièces (GDD §8.3, §17.2) |

### 8.2 Ligne d'un squishy (`Types.SquishyRecord`)

`{ s = espèce, m = mutation 0-9, st = étoiles 0-5, z = taille à la marque, zg = croissance cumulée à la marque, bf = Meilleur Ami 0-3, lk = verrou, o = tenue ou "" (seul endroit où la tenue portée est gardée), at = "pen" | "pool" | "dodo" | "mail", b = naissance (Clock.unix()), gd = Clock.day() du dernier bonus de croissance du Rush (0 = jamais ; v1.2) }`. uid = base 36 de `nextUid` (8 caractères au plus), **unique par profil seulement** : toute intention qui vise le squishy d'un autre joueur porte aussi `ownerId` (BoopHold, PetPress).

Capacités : `pen` + `pool` ≤ `Formulas.penCapacity` (24 au plus), `pool` ≤ `Formulas.poolSlots` (5 ou 6), `dodo` ≤ 60, `mail` ≤ 20 ; un seul squishy par emplacement de Meilleur Ami ; pour chaque tenue, le nombre de squishies qui la portent (`o == id`) ≤ `outfits.owned[id]`. Taille d'un profil plein (104 squishies, 64 espèces) < 20 Ko ; `Contract_game.spec` vérifie qu'il passe `JSONEncode` puis `JSONDecode` sans aucun changement et qu'un Squishydex de 64 espèces garde ses tampons et ses étoiles après sauvegarde et rechargement par DataService (aucun masque de bits partagé entre espèces).

### 8.3 Croissance cumulée (décision du contrat, §20 n° 1)

Le GDD gardait `zAt` par squishy. Le contrat remplace ce champ par une **croissance cumulée du ranch** : `G(t) = growth.G + growth.g × (t − growth.t)`. La taille d'un squishy d'enclos ou du Bassin vaut `z + (G(t) − zg)` ; dans la Boîte à dodo ou aux Lettres, elle est figée à `z`. Conséquences :
- un changement de croissance `g` (dalle, boost, famille Jelly, Grand Splorch) ne touche que `growth` (EconomyService) : **aucune écriture dans `squishies`** par un autre service que SquishyService ;
- hors ligne : `G += clamp(g sans boost × Offline.GrowthShare (30 %) × durée, 0, max(0, Offline.StopAt (0,9) × objectif(R) − plus gros squishy d'enclos ou du Bassin))`, dans le rebase de `DataService.onPrepare` (§11.5) : la croissance hors ligne s'arrête à 90 % de l'objectif, les derniers 10 % se font en jeu ; la taille de chaque squishy d'enclos suit toute seule ;
- revenu du ranch linéaire en G : `revenu(t) = S1 + K × G(t)` avec `K = Σ k` et `S1 = Σ k × (z − zg)` (`Formulas.ranchIncome`) ; Pot = intégrale exacte (`Formulas.potGain`) ;
- au Grand Splorch, `G = 0`, et chaque squishy reprend `z = 1`, `zg = 0` (`EconomyService.applySplorch` + `SquishyService.resetSizes`, dans le même bloc sans yield) : la précision des doubles reste bonne (G ne dépasse jamais la plus grande taille d'une boucle) ;
- passer en Dodo : `z = taille(now)` ; revenir en enclos : `zg = G(now)` ;
- le client prédit les tailles avec `growth` publié dans `RanchPublic.growth` (§10.2).

### 8.4 Réplication vers le client

- Le profil entier sauf les clés privées (`receipts`, `codes`, `flags`) part au client dans `DataSnapshot`, puis en `DataPatch` groupés par image (socle). `squishies` part par morceaux : les `SNAPSHOT_INLINE` (50) premières entrées dans l'instantané (ordre `setStreamOrder` de SquishyService), le reste en entrées de `DataPatch` ; chaque mutation d'un squishy utilise `DataService.markDirtyEntry(player, "squishies", uid)` (jamais la table entière).
- L'état **public** d'un ranch (ce que les autres voient) ne passe jamais par le profil : `RanchSnapshot` / `RanchPatch` (§10.2).
- Le client prédit pièces et Pot avec `Formulas` à partir de son profil (même code que le serveur) et se recale à chaque patch.

### 8.5 Revalidation, invariants, migrations

- **Données lues = données à revalider** : après `migrate` et `reconcile`, `Server/Data/ProfileRepair.repair(data)` (paquet ranch, pur) répare chaque champ faux avec une valeur sûre (types, bornes, `NaN`, tableaux denses allongés à `Species.List`, uids, lieux, Meilleurs Amis uniques, tenues, capacités) et rend la liste des réparations, comptées par Diagnostics (note INT-REPAIR, §22). Ensuite seulement tournent les crochets `onPrepare` (rebase hors ligne), puis l'instantané et `Loaded`.
- **Tableaux denses** dès `Schema.defaults()` (`dex.mut`, `dex.stars`, `trophies` : une case à 0 par espèce). Le DataStore simulé du harnais refuse un tableau à trous (« tableau à trous », couche e) comme Roblox ; `DataChaos.spec` vérifie `Invariants.dense` après chaque écriture.
- **Invariants** : `Logic/Invariants.profile(data)` rend les violations (vide = sain). Vérifiés à chaque tick du robot de longue durée (§17), après chaque mutation en Studio et dans les specs, jamais réparés en douce.
- **Migrations** : `Schema.migrate(data, from)`, étapes pures derrière `if fromVersion < N`, testées sur les sauvegardes-témoins `tests/fixtures/profiles/v<n>.json` (v0 existe). On n'efface jamais un champ dans la version qui le remplace.
- **Janvier et février** : champs réservés déjà dans le schéma, interrupteurs dans `Config/Features`, colonnes réservées dans `Config/Species` (`release`, `duo`, `recipe`, `limitedUntil`, `encore`), clé `SeasonPass` cachée : aucune migration ne sera nécessaire.

### 8.6 État de session (mémoire du serveur, jamais sauvegardé)

Portage, monture montée, maintiens, file des Grands Splorch, paires boopeur → ranch et leur heure, fuites par ranch sur l'heure glissante, listes « Pas ce joueur », liste de blocage souple, Wild Wobblers partagés attrapés par Rush, objectifs gardés jusqu'à la fin de la session après minuit, recharges des pressions et des bonds, état des événements ; depuis la v1.2 : historique de 0,5 s des positions validées (`MoveCheck.positionAt`), crédits de bond (`MoveCheck.grant`), attente sur une dalle (RanchService), dernière activité de chaque joueur (`Server/Util/Activity`), dernier spectacle complet vu par spectateur (SplorchService), segments de Squish Party par acheteur (EventService), réglage « BOOP RUSH autorisé » d'un serveur privé.

---

## 9. Configuration (`Shared/Config`) et types (`Shared/Types`)

Toutes les configurations sont des données du contrat (seul `Balance` est réglé par logic). Aucun service n'écrit un nombre du GDD en dur.

| Module | Contenu | GDD |
|---|---|---|
| `Balance` | revenu, croissance, presser, Pot, dalles (prix × `RScale`^R, attente `DwellSeconds`), enclos, Cuve (tables de qualité, niveau par R, protections), Bassin, vente, fuites, captures (`ClientPast`), Golden, monture et bond, échelle de taille, Grand Splorch (objectifs, cadeaux, déblocages, `FullShowGap`), hors ligne (`StopAt`), Fame, plafonds (et `CapsPerFriend`), bébés, récompenses en secondes de revenu, croissance du Rush (`RushSize`), boosts ; marque `GddValues` (version du GDD des valeurs) | §4 |
| `Species` | 26 lignes d'espèces (corps, haut de tête, yeux, couleurs, motif, tremblement, champs réservés), 6 familles + Secrets (bonus, R de déblocage, espèce Peu commune), `FamilyOrder` (liste en ajout seul = index de `dex.fam`), `NewFamilyUnlockR` (5), `isReleased` | §5.1, §4.17 |
| `Rarities` | 7 raretés (multiplicateur, couleur, forme de l'aura, effets, verrou automatique, confirmations) | §4.4 |
| `Mutations` | 9 mutations (multiplicateur, chance, aspect de rendu, naissance rare, verrou, confirmations), ordre de tirage, buses, Lune | §4.5 |
| `Events` | horloge (Golden, Rush, MEGA, Lune), règles du Rush et des protections, Wild Wobblers, MEGA, jauge (600 × N actifs, sieste `RestSeconds`), joueurs actifs (`Activity`), spectacles (coupure de la file `SplorchQueueHardCut`), démonstration, fêtes, bannières et priorités, costumes | §2.4, §4.21-§4.23, §6.6 |
| `Quests` | accueil (étapes, script), 18 objectifs et leurs règles (minutes de revenu, aucun boost), Nourrir Plop (maintien 2 s, paliers), jalons du Squishydex, carte sommeil, Boutique cachée 10 min | §3, §7 |
| `Pads` | prises de dalles, règles de découverte, constructions gratuites, 18 décorations | §4.6, §11.2 |
| `Cosmetics` | selles, traînées, tenues, titres, thèmes, drapeaux, emotes (sources), palette des 16 ranchs, signaux de la croix | §5.4, §6.5 |
| `Features` | interrupteurs (`get`, `set` sur message LiveOps validé, `reset` pour les tests) | §12.2 |
| `Layout` | disposition télé : référence 1920 × 1080, zone sûre, tailles minimales, rectangles du HUD, colonnes, invites, textes du monde (`WorldText`), clavier (`Keyboard`), panneaux, cartes, délais du focus | §10.1-§10.4, §10.6 |
| `Intents` | catalogue des intentions : propriétaire, débit, arguments, drapeau `activity` (intention de jeu) (§10.1) | §12.7 |
| `Monetization` | 4 passes + `SeasonPass` caché ; 6 produits dont `CoinsSmall` et `CoinsBig` cachés (`hidden`, retirés du lancement) ; effets ; identifiants à 0 | §8 |
| `Sounds` | 8 sons d'interface (IDs officiels) + 53 clés de jeu à ID vide (muettes jusqu'à l'écoute) | §9.6 |
| `Settings` (socle + contrat) | réglages : génériques + `hideName`, `receiveGifts`, `clips`, `emoteLeft`, `partyShowName`, `allowRush` (serveur) | §10.3 |
| `Console` (socle + contrat) | couche console ; référence 1920 × 1080, texte 28, glyphe 48, plancher 0,5, zone sûre 5 % partout (note INT-TV appliquée) ; les vibrations du jeu (§14.4), sans champ `mobile`, avec `cooldownExempt` (sirène) | §10.5 |

`Shared/Types.luau` (registre partagé) définit les types de toutes les charges utiles et des données : `SquishyRecord` (dont `gd`), `PublicSquishy`, `Growth`, `Tiles`, `ModeState`, `ObjectiveEntry`, `RanchPublic` (`best` toujours présent, `s = 0` = aucune silhouette), `RanchSnapshotPayload`, `RanchPatchPayload`, `SquishyOp`, `FencePayload`, `CreatureKind`, `ChaseSpawn`, `ChaseFinish`, `ChaseEventPayload`, les phases d'`EventClock`, `SpectacleEntry` (`slot`, `position`, `eta`), `SpectacleCurrent`, `EventFeatures`, `EventStatePayload` (`gauge.restUntil`), `MegaBeatPayload`, `BoopStatePayload`, `HoldStatePayload` (`kind` « feed » | « tile », `tile`), `EmoteShowPayload`, `ClapPromptPayload`, `LeaderboardPayload`, `DiagEntry`, `DiagSample`, `DiagnosticsSnapshot`, `ReturnScreenData` (`nearlyReady`), `SplorchPreview`, `OpenState`, `TickActor` (`rootOffset`), la liste fermée `CelebrateKind` et les données de chaque sorte (`CelebratePress` … `CelebratePhoto`, §10.3 ; remarque A29).

---

## 10. Réseau : intentions, charges utiles, célébrations, recouvrement

Tous les remotes sont déclarés dans `Shared/Remotes.luau` (registre partagé) et créés par `Net.setup()`. **Aucun `RemoteFunction`.** Les achats Robux passent par `MarketplaceService:Prompt…Purchase` côté client et `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur, sans remote du jeu.

### 10.1 Client → serveur : intentions (`Config/Intents.luau`)

Le débit est un seau à jetons par joueur et par action (`RateLimit.allow(player, nom, appels, secondes)`), avec les valeurs de `Config/Intents`. Les arguments sont validés selon leur sorte (`uid`, `uids`, `time`, `dir`, `bool`, `int`, `userId`, `userIds`, `key`, `str`, `setting` : définitions en tête de `Config/Intents`). Le fuzzeur de la couche b (§17) lit ce même catalogue. Une intention marquée `activity = true` (les 29 intentions de jeu, vérifiées par `Contract_game`) appelle `Activity.note` une fois acceptée (§1 règle 18). Bornes des `time` : Press, PetPress, MegaPress par `PressTiming.clampClientTime` ([maintenant − 0,35 ; maintenant + 0,05]) ; Catch et Leap ramenés dans [maintenant − `Balance.Catch.ClientPast` ; maintenant].

| Intention | Charge utile | Propriétaire | Débit | Validation serveur (après les types) |
|---|---|---|---|---|
| `Press` | `uid, tClient` | SquishyService | 12 / 1 s | uid possédé, en enclos ou Bassin, à plat ≤ `Press.Range + Press.RangeTolerance` (10 + 2) du centre de la place du squishy (`WorldLayout.penSlot` / `poolSlot`), pieds ≤ 8 (position validée, `canAct`), recharge de 8 s écoulée ; `tClient` borné par `PressTiming.clampClientTime` |
| `PickUp` | `uid` | SquishyService | 4 / 1 s | possédé, en enclos, ≤ 10 studs, rien de porté, pas en monture, ni en fuite ni en attente de Grand Splorch ; retiré aussitôt de sa clôture (§11.6) |
| `PutDown` | — | SquishyService | 4 / 1 s | quelque chose est porté |
| `Throw` | — | SquishyService | 4 / 1 s | quelque chose est porté, ≤ 12 studs du Bassin ; place ou jumeau (`FusionRules.throwOutcome`) |
| `FuseMenu` | `uidA, uidB` | SquishyService | 2 / 1 s | différents, possédés, jumeaux, hors Lettres, ni en fuite ni en attente (verrouillés acceptés) |
| `FuseAll` | — | SquishyService | 1 / 2 s | au moins une paire de jumeaux non verrouillés hors Lettres ; chaîne faite par le serveur (`FusionRules.planMergeAll`) |
| `BuyTile` | `tile` | EconomyService | 10 / 1 s | `tile` ∈ {snack, decor, pens, cozyBed} ; niveau < maximum ; R minimal ; settle puis pièces ≥ prix ; achète **tout de suite** (position non exigée : panneau ou □ sur la dalle) ; source `"pad"` si `RanchService.onPad(player) == tile` (refus doux, aucun Feedback), sinon `"panel"` (`Feedback notEnoughCoins`) (remarque A24) |
| `MoveSquishy` | `uid, to` | SquishyService | 4 / 1 s | `to` ∈ {pen, dodo} ; place libre ; pas porté, pas en fuite, **pas en attente de Grand Splorch** (remarque A26), pas dans le Bassin en fusion ; vers le Dodo : retiré aussitôt de sa clôture |
| `ClaimMail` | `uid` | SquishyService | 4 / 1 s | dans la Boîte aux lettres ; place libre en enclos (sinon Dodo) |
| `Sell` / `Release` | `uids, confirmed` | SquishyService | 2 / 1 s | 1 à 84 uids uniques, possédés, ni Meilleur Ami, ni verrouillés, ni en fuite, ni en attente, ni portés ; `confirmed = true` exigé s'il y a un Épique+ ou une mutation ×5+ |
| `SetLock` | `uid, locked` | SquishyService | 6 / 1 s | possédé |
| `SetBestFriend` | `uid, slot` | SquishyService | 2 / 1 s | 1 à 3, emplacement débloqué (`Balance.Splorch.BestFriendSlotsAt`), possédé ; l'ancien titulaire perd son emplacement |
| `SetMount` | `uid` | SquishyService | 2 / 1 s | possédé, en enclos ; selle gagnée |
| `Ride` | `on` | SquishyService | 2 / 1 s | une selle est gagnée ; rien de porté ; pas dans le Bassin ; `MoveCheck.setRootOffset` à la montée et à la descente (§11.6) |
| `EquipOutfit` | `outfit, uid?` | SquishyService | 2 / 1 s | tenue connue et possédée (nombre > portées) ; uid possédé ou nil (retirer) |
| `Leap` | `dirX, dirZ, tClient` | ChaseService | 3 / 1 s | `LeapRules.validDir` ; recharge de 4 s (horloge du serveur) ; pas en portage ; `canAct` au départ ; `tClient` ramené dans [maintenant − 0,35 ; maintenant] → `MoveCheck.grant(player, 12, 0,35, tClient)` (crédit rétroactif jusqu'à 0,3 s, un par 4 s) ; point d'atterrissage `LeapRules.landing` ; capture tentée à `tClient + 0,35 s` |
| `Catch` | `id, tClient` | ChaseService | 6 / 1 s | créature active et attrapable par ce joueur (personnelle, mode Rush, boopeur après 6 s, recharge du Golden) ; `tClient` ramené dans [maintenant − 0,35 ; maintenant] ; à plat ≤ rayon + 1,5 (6,5 ; 9,5 pour le propriétaire de sa fuite) entre `SeededPath.pos(tClient)` et `MoveCheck.positionAt(joueur, tClient)` ; pieds ≤ 8 du sol de la créature ; `canAct` ; égalité : ordre d'arrivée |
| `BoopHold` | `ownerId, uid, holding` | RushService | 4 / 1 s | `RushRules.checkBoop` au début et à chaque tick ; fin mesurée par le serveur |
| `SetMode` | `rush` | RushService | 1 / 1 s | vers Cozy : immédiat ; vers Rush : recharge de 60 s, appliqué à la fin du Rush en cours ; serveur privé sans autorisation : refusé |
| `RefuseBooper` | `userId` | RushService | 2 / 1 s | ce joueur a boopé l'envoyeur pendant la session |
| `MegaPress` | `tClient` | EventService | 3 / 1 s | MEGA en phase de pression, ≤ 20 studs du centre, recharge de 0,4 s |
| `AdminCommand` | `command, arg` | EventService | 2 / 1 s | envoyeur dans `Data/Admins` (sinon ignoré sans réponse) ; commandes de §11.10 (`"clock"` : Studio seulement) ; envoyé par l'onglet Outils du panneau Diagnostics |
| `GrandSplorch` | `film, flyer` | SplorchService | 1 / 2 s | plus gros ≥ objectif ; dans son ranch ; rien de porté ; **aucun de ses squishies en fuite** (sinon `Feedback waitEscape`) ; `flyer` possédé, en enclos ; pas déjà dans la file. Vérifié **une seule fois** |
| `FeedPlop` | `holding` | QuestService | 2 / 1 s | à plat ≤ 8 studs du bol (pieds), pas encore nourri aujourd'hui ; **2 s** mesurées par le serveur (`Quests.Feed.Hold`) |
| `ClaimObjective` / `RerollObjective` | `slot` | QuestService | 4 / 1 s | 1 à 3 ; terminé et non réclamé / relance disponible et non terminé |
| `ClaimDexReward` | — | QuestService | 2 / 1 s | jalon atteint et non réclamé |
| `UiSeen` | `screen` | QuestService | 2 / 1 s | `screen` ∈ {objectives, modeCard, postBoop, booped, shop, dex, leaderboards} ; une fois par écran et par session (les suivants ignorés) ; ne donne **jamais** rien : étape 10 de l'accueil (objectifs vus, GDD §16.1), `Signals.UiSeen` (RushService : départ du délai de 20 s de la carte du choix), analytique |
| `PetPress` | `ownerId, uid, tClient` | CommunityService | 12 / 1 s | propriétaire ami Roblox présent ; uid à sa clôture (raison "petsit") ; côté rue, à plat ≤ 10 + 2 du centre de la place à la clôture (`WorldLayout.fencePoint`), pieds ≤ 8 ; plafonds du jour : 100 récompensées par visiteur (`caps.petSit`), 100 reçues par propriétaire (`caps.petSitIn`), « Plus serviable » ≤ 20 par ami (`caps.petSitBy`) ; `tClient` comme `Press` |
| `SetSetting` | `key, value` | CommunityService | 4 / 1 s | clé de `Config/Settings` ; type attendu ; valeur permise et débloquée ; `allowRush` : propriétaire du serveur privé |
| `EquipCosmetic` | `kind, id` | CommunityService | 2 / 1 s | cosmétique connu et débloqué (`hasCosmetic`, déblocages de session compris) ; envoyé par l'onglet Style du panneau Ranch |
| `Emote` | `kind` | CommunityService | 1 / 1,2 s (client 1 / 1,5 s) | 1 à 3 ; l'emote de la croix ← vient des réglages |
| `Clap` | `heroId` | CommunityService | 2 / 1 s | fenêtre ouverte pour ce héros ; pas déjà applaudi |
| `ReportBlocked` | `userIds` | CommunityService | 1 / 10 s | 0 à 200 entiers positifs ; envoyé une fois par `WorldStateController.Start` depuis `StarterGui:GetCore("GetBlockedUserIds")` sous `pcall` (liste vide en cas d'échec ; remarque A21) |
| `RequestWorld` | — | RanchService | 1 / 2 s | renvoie `RanchSnapshot` et émet `WorldRequested` ; le client le renvoie toutes les 3 s tant qu'aucun instantané n'arrive (§10.5) |
| `SetInputType` | `kind, tenFoot` | DiagnosticsService | 1 / 5 s | `kind` = `Platform.inputKind()` (1 tactile inattendu, 2 clavier-souris, 3 manette) ; analytique seulement |
| `ReportError` | `kind, key, message, trace, ctx` | DiagnosticsService | 1 / 2 s | 1 ou 2 ; chaînes tronquées (64 / 300 / 600 / 120) ; renormalisées ; 30 par session, 1 par clé et par minute ; ne change jamais rien au jeu |
| `RequestDiagnostics` | `tab` | DiagnosticsService | 1 / 2 s | 1 à 3 ; administrateur, sinon silence |
| `ClientEvent` | `kind` | DiagnosticsService | 1 / 5 s | `kind` ∈ {qualityReduced, shopOpened} (v1.2, remarque A21) ; 20 par session au plus ; **analytique seulement** (`QualityReduced`, `ShopOpened`), ne change jamais rien au jeu ; envoyé par QualityController (descente de qualité) et Panels/Shop (chaque ouverture). « Objectifs vus » (étape 10) reste `UiSeen("objectives")` |
| `RequestSnapshot` | — | DataService (socle) | 2 / 10 s | renvoie `DataSnapshot` |

### 10.2 Serveur → client

| Remote | Charge utile (`Shared/Types`) | Émetteur | Destinataires | Quand |
|---|---|---|---|---|
| `DataSnapshot`, `DataPatch` | profil public, patchs groupés | DataService | le joueur | chargement, puis par image |
| `RanchSnapshot` | `RanchSnapshotPayload { seq, ranches[slot], squishies[slot][uid] }` | RanchService | un joueur | `PlayerReady`, `RequestWorld`, trou de suite |
| `RanchPatch` | `RanchPatchPayload { seq, ranches[slot] = champs changés, ops = { SquishyOp } }` | RanchService | tous (seq par destinataire) | fin de chaque tick qui a changé quelque chose |
| `Fence` | `FencePayload { slot, uids, reason }` | RanchService | tous | Rush (renouvellement 20 s), pet-sitting |
| `ChaseEvent` | `ChaseEventPayload { spawns, finishes }` | ChaseService | tous, ou le seul concerné (personnelles) | groupé à 4 Hz |
| `EventState` | `EventStatePayload { rush, mega, golden, moon, gauge, boost, spectacle, features, offset }` ; `gauge.restUntil` = fin de la sieste de Big Plop ; `spectacle.queue[i] = { kind, userId, startAt, slot, position, eta }` (place et attente prévue, recalculées à chaque changement : c'est le « spectacleQueue » du GDD) ; `features = EventFeatures { boopRush, megaSquish, golden, jellyMoon, gauge, clips, costume, diagnostics }` (interrupteurs en vigueur sur le serveur) | EventService | tous | à chaque changement, à `PlayerReady`, et à chaque `Features.set` appliqué (LiveOps, `AdminCommand "feature"`) |
| `MegaBeat` (non fiable) | `MegaBeatPayload { points, target, presses, t }` | EventService | tous | 4 Hz pendant la pression du MEGA |
| `BoopState` | `BoopStatePayload { booperId, ownerId, uid, endsAt, state }` | RushService | tous | début, changement de durée, fin ou annulation d'un maintien |
| `ModePrompt` | — | RushService | le joueur | une fois, dès 15:00 de jeu ; le client attend le calme |
| `HoldState` | `HoldStatePayload { kind, endsAt, active, tile }` | QuestService (`"feed"`, bol, 2 s) et RanchService (`"tile"`, attente de 0,6 s sur une dalle) | le joueur | anneaux de maintien |
| `EmoteShow` | `EmoteShowPayload { userId, kind, emote }` | CommunityService | tous | emote acceptée |
| `ClapPrompt` | `ClapPromptPayload { heroId, endsAt }` | CommunityService | les spectateurs qui ont le spectacle **complet** (au plus un toutes les 180 s par spectateur, choisis par SplorchService) ; le client ne l'affiche pas pendant une poursuite (créature attrapable ≤ 30 studs), un maintien ou une fenêtre ouverte | Grand Splorch d'un autre |
| `LeaderboardState` | `LeaderboardPayload` | LeaderboardService | le joueur | `PlayerReady`, puis toutes les 120 s et à chaque record battu |
| `DiagnosticsSnapshot` | `DiagnosticsSnapshot` (≤ 20 Ko) | DiagnosticsService | l'administrateur demandeur ; « bonjour » (`tab = 0`, vide) à chaque administrateur | `RequestDiagnostics` ; `PlayerReady` d'un administrateur |
| `Feedback` | `{ key, vars, tone }` | tous (via `Notify.feedback`) | le joueur | refus, confirmations |
| `Celebrate` | `{ kind, data }` | voir §10.3 | le joueur (tous pour le Grand Splorch) | moments de jeu |
| `Banner` | `{ kind, args, priority, personal }` | CommunityService (file) ou `Notify.personalBanner` | tous / le joueur | §6.6 du GDD |

### 10.3 Célébrations (`Celebrate`) : sortes, données et consommateurs côté client

Liste fermée : `Types.CelebrateKind` ; données de chaque sorte : types `Types.Celebrate<Sorte>` (remarque A29 ; `Contract_game` vérifie que chaque sorte de cette table est dans `Types.CelebrateKind`).

| Sorte | Données | Émetteur | Consommateurs client |
|---|---|---|---|
| `press` | `{ uid, coins, perfect, streak, petsit }` | SquishyService | VFXController (écrasement, pièces, « +N » par `UI/WorldText`, PERFECT), HUD (compteur), vibration `perfect` (0,3 + 0,03 par cran de série ; une pression ordinaire ne vibre jamais) |
| `tile` | `{ tile, level }` | EconomyService | VFXController (construction qui rebondit), HUD, vibration `tileBuy` |
| `pot` | `{ coins, auto }` | EconomyService | VFXController (geyser), HUD |
| `hatch` | `{ uid, species, rarity, mutation, oneIn, isNew, scripted, at }` (`at` = "pen", ou "dodo" quand les enclos sont pleins) | SquishyService | VFXController (révélation par rareté), RanchRenderer (bulle `world.vat.dodo` sur la Cuve si `at = "dodo"`), Banners (rien : la bannière de serveur vient de la file) |
| `fusion` | `{ uid, step, stars, coins }` | SquishyService | VFXController (fusion, combo), HUD, vibration `fusion` / `comboBig` |
| `catch` | `{ kind, species, mutation, uid, coins, hero, byLeap }` | ChaseService | VFXController, HUD, vibration `catch` |
| `ownerReturn` | `{ uid, species, coins, catcherId, catcherName, firstBoop }` | ChaseService | Cards (carte « revient toujours ! » la première fois), Toast (« le retour d'abord »), HUD (vibration `squishyBack`) |
| `returnedBigger` | `{ uid, species }` | ChaseService | Toast (`feedback.returnedHome`, + 30 min de croissance une fois par jour), HUD (vibration `squishyBack`) |
| `booped` | `{ uid, species, booperId }` | RushService | **Cards** : carte non bloquante `booped` (« Continuer », « Pas ce joueur » → `RefuseBooper`), atteignable à la manette (△ → entrée « ! » → ✕) ; ScreenFX (flèche). **Aucune vibration** quand un squishy s'enfuit (GDD v1.3 §10.5 : `booped` retiré, il vibre à son retour, `squishyBack`). Jamais un Toast pour un bouton : un Toast ne prend jamais la sélection |
| `boopDone` | `{ ownerId, uid }` | RushService | VFXController (ATCHOUM), vibration `boopDone` |
| `splorch` | `{ userId, level, flyer, startedAt, burstAt, endsAt, short }` | SplorchService | tous : VFXController (spectacle ; `short = true` : version courte, ni capsule, ni secousse, ni vibration, ni APPLAUDIR ; le héros a toujours `short = false`), CameraController (héros), Banners |
| `giftRain` | `{ heroId, heroName, coins, uid, species, short }` | SplorchService | VFXController (capsule et vibration `catch` si `short = false` ; sinon message `celebrate.giftShort`, cadeau déjà compté) |
| `megaResult` | `{ success, points, babies, coins }` | EventService | VFXController, HUD |
| `lunarDrop`, `luckyDrop` | `{ uid, species, mutation }` | EventService / QuestService | VFXController |
| `dexNew` | `{ species, mutation, star }` | QuestService | Cards (non bloquante) |
| `objectiveDone` | `{ slot, id }` | QuestService | HUD (suivi), son `ObjectiveDone` |
| `objectivesCard`, `newObjectives` | `{ day }` | QuestService | Cards |
| `plopDay` | `{ day, reward }` | QuestService | VFXController (tampon « Jour 42 ! ») |
| `onboarding` | `{ step, hint }` | QuestService | OnboardingController |
| `sleepy` | `{ minutes }` | QuestService | Cards |
| `return` | `ReturnScreenData` (dont `nearlyReady` : « Presque prêt pour le Grand Splorch ! », `return.nearly`) | EconomyService | ReturnScreen |
| `unlock` | `{ kind, id }` | QuestService, CommunityService | Toast |
| `saddle` | `{ saddle }` | SquishyService | Toast, HUD (indicateur Monter) |
| `purchase` | `{ key }` | ProductService | VFXController (pluie de pièces), Toast « Merci ! » |
| `clapCount` | `{ n }` | CommunityService | Toast (héros) |
| `fanfare` | `{ threshold }` | LeaderboardService | VFXController (feux d'artifice) |
| `photo` | `{ on }` | EventService (`AdminCommand "photo"`) | HUD (cache l'interface pour les vignettes ; administrateurs seulement) |
| `testError` | `{}` | EventService (`AdminCommand "testError"`, `arg = "client"`, administrateurs seulement) | ErrorReporter (lève une erreur volontaire du client : test manuel M17) |

### 10.4 Feedback et bannières

- `Notify.feedback(player, "feedback.<code>", vars, tone)` : refus et confirmations (clés `feedback.*` de `Strings`). Une dalle trop chère **ne refuse jamais** (anneau + son `Bump`, aucun Feedback) ; un joueur resté dessus achète au premier tick où ses pièces suffisent, une fois par entrée (remarque A24).
- Bannières de serveur : `Notify.banner(sorte, args, source)` → `Signals.BannerRequested` → file de CommunityService (3 au plus, 3 s, priorité de `Config/Events.Banners.Priority`, une bannière par joueur source toutes les 10 s, nouveaux avant l'étape 9 : rien). `args` porte toujours `userId` et `name` (vide si le nom est caché : le client écrit l'alias `name.alias`) et les données du texte (`species`, `mutation`, `odds`, `n`, `word`).
- Bannières d'événement (sirène, MEGA, Lune) : calculées par le client (`EventClock`), jamais envoyées, et **seulement si l'interrupteur du serveur est vrai** (`WorldStateController.event().features` : `megaSquish`, `golden`, `jellyMoon`, `gauge`, `costume`, `clips`, `diagnostics`). Un client ne lit jamais `Config/Features` pour un événement : après un interrupteur coupé en direct, aucune bannière, pastille, ciel ni costume fantôme.

### 10.5 Numérotation, recouvrement, arrivée en cours de partie

- `RanchSnapshot` et `RanchPatch` portent un numéro de suite **par destinataire**. Un trou → le client ignore les patchs, envoie `RequestWorld` et **le renvoie toutes les 3 s** (`StateTimeouts` « worldResync », jamais plus vite que le débit de 1 / 2 s) jusqu'au nouvel instantané : une demande perdue par le débit ne bloque jamais le miroir. `WorldStateController.spec` : deux trous en moins d'1 s convergent.
- Une créature dont `t0 + duration` est passé disparaît chez le client même sans `finish`. Un maintien dont `endsAt + 0,5 s` est passé est retiré. Une phase d'événement est recalculée par `EventClock` entre deux `EventState`.
- Arrivée en cours de partie : `RanchSnapshot` + `EventState` + créatures actives (une fois, à `PlayerReady`).

### 10.6 Règles des charges utiles

Tables soit tableaux séquentiels, soit dictionnaires à clés **chaînes** (les numéros de ranch sont des clés `"1"` … `"16"`), jamais mixtes ni à trous ; aucun `NaN` ni infini ; aucune `Instance` ; tous les envois des specs d'intégration passent par `tests/harness/Wire` (règles de sérialisation de Roblox). **Aucun champ optionnel dans une table patchée** : un `nil` ne voyage pas dans un `RanchPatch`, donc chaque champ de `RanchPublic` a une valeur « vide » (`""`, `0`, et `best.s = 0` pour « aucune silhouette » ; remarque A27).

---

## 11. Services serveur (API)

Chaque bloc reprend **exactement** les signatures des stubs (générés depuis la même source que ce document). Les services du socle gardent leur API (vérifiée par `Contract.spec`).

### 11.1 DataService et MonetizationService (socle)

API : `DataService.get / isLoaded / waitFor / set / increment / markDirty / markDirtyEntry / saveNow / onBeforeSave / onPrepare / setStreamOrder`, signal `Loaded`, attribut `ProfileLoading` (`onPrepare` ajouté par le contrat : §1 règle 16) ; `MonetizationService.registerProduct / ownsPass`, signaux `PassGranted`, `PassPurchased`, `PassRevoked`, `ProductGranted`. Règles : un seul propriétaire écrit chaque clé (`DataService.set` pour une clé de premier niveau, mutation en place + `markDirty` / `markDirtyEntry` pour les tables) ; aucune écriture dans un profil non chargé ; un handler de produit renvoie `true` seulement après la mutation ; le reçu n'est acquitté qu'après une sauvegarde réussie (socle).

### 11.2 DiagnosticsService (paquet meta) — GDD §12.11, §16.3

*Fichier : `src/server/Services/DiagnosticsService.luau` (paquet meta).*

```lua
export type Device = { kind: number, tenFoot: boolean }
export type Totals = { errors: number, warnings: number, timedOut: number, keys: number }

DiagnosticsService.attach()  -- Branche ScriptContext.Error et LogService.MessageOut au plus tôt (stub : ne fait rien)
DiagnosticsService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
DiagnosticsService.Start()  -- Connexions et boucles (stub : ne fait rien)
DiagnosticsService.step(now: number)  -- Tick : écriture groupée des totaux du jour (task.spawn, jamais de yield dans le tick)
DiagnosticsService.report(source: "server" | "client", kind: number, text: string, trace: string, ctx: string, player: Player?)  -- Compte un rapport (déjà normalisé côté client, renormalisé ici)
DiagnosticsService.reportCaught(where: string, err: any)  -- Erreur attrapée par un pcall du serveur (étape du tick, handler)
DiagnosticsService.stateTimedOut(name: string, player: Player?)  -- État fermé par son délai alors qu'il aurait dû finir seul (StateTimedOut)
DiagnosticsService.snapshot(tab: number): Types.DiagnosticsSnapshot  -- Paquet du panneau (≤ 20 Ko)
DiagnosticsService.isAdmin(player: Player): boolean  -- UserId dans Data/Admins
DiagnosticsService.device(player: Player): Device  -- Appareil et entrée déclarés (analytique seulement)
DiagnosticsService.counts(): Totals  -- Totaux de la session (tests : règle zéro trace)
```

- `attach()` (appelé par `Main.server` juste après le require, avant les autres services) : `ScriptContext.Error` et `LogService.MessageOut` (types `MessageError`, `MessageWarning`) → `report("server", …)`. Ses propres erreurs ne se rapportent jamais elles-mêmes (garde de réentrance).
- Normalisation par `DiagRules.normalize` (noms des joueurs présents et de l'envoyeur remplacés par `<joueur>`, nombres par `#`), clé `DiagRules.key`. Par clé : `count`, joueurs touchés (ensemble d'UserIds en mémoire, jamais envoyé), `first`, `last`, 3 exemples. 200 clés au plus, puis un compteur « autres ».
- `ReportError` : débit (1 / 2 s), types (`Config/Intents`), 30 par joueur et par session, 1 par clé et par minute ; au-delà, ignoré sans réponse jusqu'à la fin de la session. Interrupteur `Features.Diagnostics` : `false` ignore les rapports des clients, garde ceux du serveur.
- Totaux du jour : toutes les 5 min (`step`, `task.spawn`), `UpdateAsync` sur la clé `Diagnostics_<Clock.day()>` d'un DataStore à part (`Diagnostics_v1`) avec `DiagRules.mergeDaily` (50 clés, < 4 Ko). Analytics `ServerError` / `ClientError` une fois par clé et par 5 min.
- `RequestDiagnostics` : `isAdmin` vérifié à chaque demande ; un non-administrateur n'obtient **aucune** réponse. `snapshot(tab)` ≤ 20 Ko (tronque les exemples d'abord).
- `ClientEvent(kind)` (v1.2, remarque A21) : débit 1 / 5 s, `kind` ∈ {qualityReduced, shopOpened}, 20 par joueur et par session ; analytique seulement (`QualityReduced` avec l'appareil, `ShopOpened`) ; ne change jamais rien au jeu.
- **« Bonjour » des administrateurs** : à `PlayerReady` d'un administrateur, `DiagnosticsSnapshot { tab = 0 }` vide. C'est le seul moyen pour le client de savoir qu'il est administrateur (`Data/Admins` reste sur le serveur) : `Panels/Diagnostics.visible()` devient vrai à sa réception, et l'entrée Diagnostics des Réglages apparaît. Un non-administrateur ne reçoit jamais rien.
- `stateTimedOut(name, player)` : compte et analytics `StateTimedOut` (avec le nom de l'état). `reportCaught(où, err)` : compte sous la clé de `où`.
- Dépendances : utilitaires du socle, `Data/Admins`, `Logic/DiagRules`, `Config/Features`. Aucun service.

### 11.3 WorldService (paquet world) — GDD §11

*Fichier : `src/server/Services/WorldService.luau` (paquet world).*

```lua
WorldService.build(): Folder  -- Construit le monde une seule fois (idempotent) et rend workspace.Wobbleton
WorldService.ranchModel(slot: number): Model?  -- Modèle du ranch (Ranches/<slot>)
WorldService.setRanchOwner(slot: number, userId: number, color: Color3?)  -- Couleur du propriétaire (clôtures, panneau) ; gris sans lumière si libre (userId 0)
WorldService.setRanchBuild(slot: number, tiles: Types.Tiles, vat: boolean, pool: boolean)  -- Montre les décorations construites, l'aspect du Tapis, la Cuve et le Bassin
WorldService.setStatue(species: number, mutation: number, size: number, name: string)  -- Attributs de la statue (dessinée par le client)
WorldService.setGauge(ratio: number)  -- Remplissage de la jarre de la jauge (0 … 1)
WorldService.partCount(): number  -- Pièces construites (budget ≤ 4 500)
```

- `Init` : groupe de collision `Characters` ; `build()` (idempotent). `Start` : rien.
- Construction par blocs protégés (plateau, collines, place, rues, quartiers, lampadaires, Prairie, chaque ranch) : un bloc en panne est compté (`DiagnosticsService.reportCaught("world:<bloc>")`), les autres se construisent.
- Ranch libre : clôtures grises (130, 130, 140), sans lumière. `setRanchOwner` colore avec `Cosmetics.RanchColors[slot]`.
- `setRanchBuild` : montre les `tiles.decor` premières décorations, l'aspect du Tapis (13 aspects), la Cuve et le Bassin selon l'accueil. Les apparitions animées (rebond) sont jouées par le client.
- Budget : `partCount()` ≤ 4 500 (prévu ≈ 4 300). Vérifié par `WorldBuild.spec`.
- Dépendances : DiagnosticsService, `Logic/WorldLayout`, `Render/Palette`, `Config/{Cosmetics,Pads}`.

### 11.4 RanchService (paquet ranch) — GDD §6.1, §6.3, §4.6, §4.8, §12.5

*Fichier : `src/server/Services/RanchService.luau` (paquet ranch).*

```lua
RanchService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
RanchService.Start()  -- Connexions et boucles (stub : ne fait rien)
RanchService.slotOf(player: Player): number  -- Ranch du joueur (0 = aucun)
RanchService.playerAt(slot: number): Player?  -- Propriétaire présent du ranch
RanchService.isReady(player: Player): boolean  -- PlayerReady déjà émis pour ce joueur dans cette session
RanchService.place(player: Player)  -- Replace le personnage à son point d'apparition (PivotTo + Signals.ServerMoved)
RanchService.step(now: number, actors: { [Player]: Types.TickActor })  -- Tick : intrus repoussés, Pot, entrées sur les dalles et attente de DwellSeconds (positions validées, canAct)
RanchService.onPad(player: Player): string  -- Clé de la dalle sur laquelle le joueur se tient (état « dedans » du tick), "" sinon : BuyTile choisit source = "pad" ou "panel" (remarque A24)
RanchService.setPublic(player: Player, fields: { [string]: any })  -- Champs de RanchPublic changés (fusionnés dans le prochain RanchPatch)
RanchService.squishyOp(player: Player, op: "add" | "remove" | "update", uid: string, rec: Types.PublicSquishy?)  -- Changement d'un squishy visible (enclos ou Bassin)
RanchService.setFence(slot: number, uids: { string }, reason: "rush" | "petsit" | "")  -- Squishies posés à la clôture ("rush" passe avant "petsit") ; effacer = setFence(slot, {}, maRaison), sans effet si la raison actuelle est une autre ; "" réservé à RanchService (ranch libéré)
RanchService.fenceOf(slot: number): ({ string }, string)  -- (uids à la clôture, raison)
RanchService.publicOf(slot: number): Types.RanchPublic?  -- État public d'un ranch
RanchService.setZoneHandler(kind: "pot" | "pad", handler: (Player, string) -> ())  -- Crochet du service plus tardif (EconomyService) : step l'appelle quand le joueur entre sur le Pot ("pot", "") ou sur une dalle ("pad", clé de la dalle)
RanchService.refreshBuild(player: Player)  -- Relit le profil (dalles, accueil) et met à jour le ranch construit (WorldService.setRanchBuild) et l'état public
RanchService.flush()  -- Envoie le RanchPatch groupé du tick (appelé par ChaseService à la fin du tick)
RanchService.sendSnapshot(player: Player)  -- RanchSnapshot complet à ce joueur (arrivée, RequestWorld, trou de suite)
RanchService.openStates(): { Types.OpenState }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- Attribution, serveur plein, placement, groupe `Characters` : §5.4.
- `step(now, acteurs)` : pour chaque acteur avec `canAct` : intrus (`ZoneRules.intruder`) → `PivotTo(WorldLayout.gateOutside(k))`, `Signals.ServerMoved`, `Feedback ranchOf { name }` (ou `ranchN { n }` si le nom est caché), son `Boing` côté client ; Pot (`ZoneRules.near(slot, "pot", pos, Balance.Pot.Radius)`, à plat, à l'entrée seulement) → crochet `"pot"` ; dalles (`ZoneRules.padStep` par prise, à plat, état « dedans » mémorisé par joueur et par prise) : à l'**entrée**, l'attente commence (`HoldState { kind = "tile", endsAt = now + Balance.Tiles.DwellSeconds, tile }`) ; sortie, portage (`SquishyService.carried`) ou autre maintien (boop, bol, Grand Splorch) → attente annulée sans rien dépenser (`HoldState active = false`) ; à `endsAt` → crochet `"pad"` avec la clé de la dalle, **une fois par entrée** ; si l'achat échoue faute de pièces, le crochet est rappelé au premier tick où `EconomyService.coins ≥ prix`, toujours une seule fois par entrée (remarque A24). Un joueur qui n'a pas `canAct` n'achète ni n'encaisse rien ce tick (mais l'intrus est toujours repoussé). `StateTimeouts` « tileDwell ».
- `setPublic` / `squishyOp` : accumulent les changements ; `flush()` (fin du tick) envoie **un** `RanchPatch` par destinataire avec son numéro de suite. `sendSnapshot` : instantané complet (16 ranchs, ≈ 15 Ko).
- `setFence(slot, uids, raison)` : "rush" passe avant "petsit" (un appel "petsit" sur un ranch en "rush" est ignoré) ; envoie `Fence` à tous. **Effacer** (remarque A25) : `setFence(slot, {}, maRaison)` n'efface que si la raison actuelle est `maRaison` (la fin du Rush n'efface jamais une clôture de pet-sitting, et inversement) ; `""` est réservé à RanchService (ranch libéré). Après la fin du Rush, CommunityService réapplique le pet-sitting à son step suivant. Appelé aussi par SquishyService (rang plus tardif, appel permis) pour **retirer aussitôt** un squishy qui quitte l'enclos : `setFence(slot, uids sans uid, raison actuelle)`. `RanchService.spec` : les deux ordres (Rush puis pet-sitting, pet-sitting puis Rush).
- **PlayerReady** : posé au premier placement réussi ; sinon, au plus tard 15 s après le chargement du profil et l'attribution du ranch (`StateTimeouts` « playerReady »), même si `HumanoidRootPart` n'est jamais arrivé ; le placement est réessayé à la prochaine apparition. `RanchService.spec` : sans HumanoidRootPart, PlayerReady à 15 s.
- `openStates()` : « playerReady » (chargé, pas encore prêt), « serverFull » (renvoi en attente), « characterPlace », « tileDwell » (attente sur une dalle).
- `RanchPublic.best` est toujours présent : `{ s = 0, m = 0, z = 0, zg = 0 }` quand le ranch est libre ou ses enclos vides (remarque A27).
- `refreshBuild(player)` : lit `tiles` et `onboarding` (Pads.FreeBuilds), appelle `WorldService.setRanchBuild` et publie `tiles`, `vat`, `pool`.
- Clés : aucune. Dépendances : DiagnosticsService, DataService, WorldService, `Logic/{WorldLayout,ZoneRules,Hash}`.

### 11.5 EconomyService (paquet ranch) — GDD §4.1-§4.8, §4.16-§4.19, §4.25, §12.3, §16.2

*Fichier : `src/server/Services/EconomyService.luau` (paquet ranch).*

```lua
EconomyService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
EconomyService.Start()  -- Connexions et boucles (stub : ne fait rien)
EconomyService.step(now: number)  -- Tick : règlements échelonnés (30 s), fins de boost, Pot automatique (pass, 5 s)
EconomyService.settle(player: Player)  -- Règle le Pot et la croissance cumulée jusqu'à maintenant
EconomyService.refresh(player: Player)  -- settle puis recalcule g, A, P, B (après un changement) et publie growth (RanchService.setPublic)
EconomyService.coins(player: Player): number  -- Pièces actuelles (après settle)
EconomyService.addCoins(player: Player, amount: number, sku: string, txType: string?): number  -- Crédite (borné, entier) ; rend le montant crédité ; analytics source
EconomyService.trySpend(player: Player, amount: number, sku: string): boolean  -- Débite si assez (après settle) ; analytics puits
EconomyService.income(player: Player): number  -- Revenu actuel du joueur (enclos + Bassin, multiplicateurs compris)
EconomyService.squishyIncome(player: Player, uid: string): number  -- Revenu actuel d'un squishy
EconomyService.addIncomeSeconds(player: Player, seconds: number, sku: string, minimum: number?): number  -- Récompense « en secondes de revenu » ; rend le montant
EconomyService.growth(player: Player): Types.Growth  -- Croissance cumulée du ranch (lecture)
EconomyService.G(player: Player, t: number?): number  -- G(t) du ranch
EconomyService.buyTile(player: Player, tile: string, source: "pad" | "panel"): boolean  -- Achète le niveau suivant (condition R, prix × Tiles.RScale^R si la dalle suit R) ; refus doux sur une dalle (anneau)
EconomyService.collectPot(player: Player, auto: boolean): number  -- Encaisse le Pot ; rend le montant
EconomyService.R(player: Player): number  -- Niveau de Grand Splorch
EconomyService.addFame(player: Player, amount: number, source: "rush" | "release" | "splorch" | "mega"): number  -- Fame bornée par les plafonds du jour ; rend la Fame accordée
EconomyService.consumeCap(player: Player, capKey: string, wanted: number): number  -- Plafond journalier (Balance.Caps) : rend la part accordée (0 = plafond atteint)
EconomyService.consumeFriendCap(player: Player, capKey: string, friendUserId: number, wanted: number): number  -- Plafond journalier PAR AMI (caps.petSitBy[tostring(friendUserId)], Balance.CapsPerFriend[capKey])
EconomyService.gNoBoost(player: Player): number  -- Croissance par seconde SANS boost (bonus du Rush, hors ligne)
EconomyService.grantPersonalBoost(player: Player, seconds: number)  -- Boost personnel ×2 (secondes ajoutées, en pause pendant un boost de serveur)
EconomyService.setServerBoost(kind: string, untilT: number)  -- Boost de serveur poussé par EventService ("wobble", "squish", "admin", "")
EconomyService.boostActive(player: Player): boolean  -- B = 2 pour ce joueur
EconomyService.setFriendsPresent(player: Player, count: number)  -- Amis Roblox présents (poussé par CommunityService)
EconomyService.applySplorch(player: Player): number  -- Grand Splorch d'un bloc : pièces, Pot, Tapis, décorations à 0, R + 1, Fame + 5, G = 0 ; rend les pièces perdues
EconomyService.onSettle(fn: (Player, number) -> ())  -- Crochet appelé après chaque settle avec G (SquishyService : trophées, record)
EconomyService.incomeCtx(player: Player): Formulas.IncomeCtx  -- Contexte des multiplicateurs (lecture)
```

- **Règlement** (`settle`) : intervalle **[growth.t ; now]**, deux `Clock.now()` fractionnaires : `K, S1 = Formulas.ranchIncome(squishies, G, ctx)` ; `pot += Formulas.potGain(K, S1, growth, growth.t, now)` (rien si `now ≤ growth.t`) ; `growth.G = Formulas.G(growth, now)`, `growth.t = now` ; crochet `onSettle(player, G)`. Chaque seconde n'est intégrée qu'une fois : N règlements sur [t0, t1] donnent exactement le Pot d'un seul règlement, et un refus de `BuyTile` (10 / s) n'ajoute rien. Il n'y a plus de `lastSettle` (l'ancien `Clock.unix()` entier recomptait jusqu'à 1 s par règlement). `refresh` = `settle` puis nouveau `g` (`Formulas.growthRate`) et nouveau contexte (A, P, B), publiés (`RanchService.setPublic(player, { growth = … })`). Appelé à chaque événement qui change g, A, P ou B : dalle, naissance, fusion, vente, relâche, déplacement Dodo / enclos, boost qui commence ou finit, ami qui arrive ou part, Grand Splorch, pass ×2 Pièces accordé, **palier de trophée franchi, page dorée gagnée, bonus de famille gagné, changement de Fame** (v1.2, GDD §12.3) ; avant chaque sauvegarde (`onBeforeSave`) ; toutes les 30 s (décalé selon le joueur).
- **Boosts** : `B = 2` si un boost de serveur (`setServerBoost`) ou personnel est actif ; jamais cumulés. Le boost personnel est en pause pendant un boost de serveur (`boosts.personalLeft` ne descend pas). La Squish Party payée n'est jamais « mangée » : EventService la fait passer avant la Wobble Party.
- **Hors ligne : rebase pur et synchrone** dans le crochet `DataService.onPrepare` (enregistré à `Init`), avant l'instantané du client, `Loaded` et tout règlement : `s = Formulas.offlineSeconds(Clock.unix(), lastOnline, cozyBed, Spiky)` (borné à 8 h, 12 h…) ; `G += Formulas.offlineGrowth(g sans boost, s, R, plus gros)` = `clamp(g sans boost × Offline.GrowthShare × s, 0, max(0, Offline.StopAt × objectif(R) − plus gros squishy d'enclos ou du Bassin))` (v1.2 : 30 %, arrêt à 90 % de l'objectif) ; `pot += Formulas.offlinePot(revenu sans boost, s)` ; `growth.t = Clock.now()` (l'ancien `growth.t` d'une autre session n'est **jamais** intégré au tarif plein) ; l'absence et ses gains sont gardés en mémoire pour l'écran de retour. Puis, sur `Loaded` : si `s ≥ Balance.Offline.ReturnScreenMin`, `Notify.celebrate(player, "return", ReturnScreenData)` (Meilleur Ami n° 1, sinon le plus gros ; `splorchReady` ; `nearlyReady` si le plus gros atteint `StopAt` × objectif). Premier chargement : rien (sauf `growth.t = Clock.now()`).
- **Départ** : `onBeforeSave(fn(player, data, release))` : `settle` à chaque écriture ; si `release == true`, `lastOnline = Clock.unix()` (jamais dans `PlayerRemoving`, §1 règle 15).
- **Dalles** : `buyTile(player, tile, source)` : niveau < `Levels`, `R ≥ MinR`, `settle`, `trySpend(Formulas.tileCost(tile, niveau, R))` (prix × `Tiles.RScale`^R pour le Tapis et les décorations) ; sinon, depuis une dalle (`source = "pad"`) : aucun Feedback (le client montre l'anneau) ; depuis le panneau : `Feedback notEnoughCoins { missing }`. Le handler de `BuyTile` choisit `source = "pad"` si `RanchService.onPad(player) == tile`, sinon `"panel"` (remarque A24) ; le crochet `"pad"` (attente de 0,6 s) passe toujours `"pad"`. Succès : niveau + 1, bit `seen`, `RanchService.refreshBuild`, `refresh`, `Signals.TileBought`, `Celebrate "tile"`, analytics `Tile_<dalle>` (sans le niveau, cumulée : note INT-ANALYTICS).
- **Pot** : `collectPot` : `settle`, `coins += pot`, `pot = 0`, `Signals.PotCollected`, `Celebrate "pot"`, analytics `Pot` cumulée par tranche de 5 min. Pass Pot automatique : toutes les 5 s dans `step`.
- **Fame** : `addFame` borne la Fame du Rush (`caps.fameRush`, 30) et de la relâche (`caps.fameRelease`, 20) ; Grand Splorch (+5) et MEGA (+1) sans plafond ; `refresh` (Fame dans A, plafonnée à 300).
- **Plafonds** : `consumeCap` remet `caps` à zéro au changement de `Clock.day()` (y compris `caps.petSitBy = {}`) puis accorde `min(voulu, plafond − déjà)` ; `consumeFriendCap(player, "petSit", ownerUserId, 1)` fait de même sur `caps.petSitBy[tostring(ownerUserId)]` avec `Balance.CapsPerFriend.petSit` (20).
- **Récompenses en secondes de revenu** : `addIncomeSeconds` utilise le revenu du moment, **P et B compris une seule fois** (jamais multiplié de nouveau par P) ; `EconomyService.spec` le vérifie explicitement avec le pass ×2 Pièces et un boost actifs.
- **Grand Splorch** (`applySplorch`, appelé par SplorchService à l'éclatement, sans yield) : `settle` ; pièces perdues = `coins + pot` (rendues pour l'analytique `SplorchCoinsLost`, exprimée par SplorchService en multiples du prix du Tapis 12 de la boucle ; `TileLevelAtSplorch` avec le niveau du Tapis et le nombre de décorations avant la remise à zéro) ; `coins = pot = 0` ; `tiles.snack = tiles.decor = 0` ; `R += 1` ; `fame += 5` ; `growth = { G = 0, g = nouveau, t = now }` ; `RanchService.refreshBuild` ; publication.
- **Analytique de l'économie** (GDD §16.2, note INT-ANALYTICS) : sources et puits cumulés par joueur, par tranche de 5 min et par `itemSku` (`Pot`, `Press`, `Combo`, `Sell`, `Offline`, `Golden`, `Mega`, `RushHero`, `RushReturn`, `RushNear`, `SplorchGift`, `PetSit`, `Clap`, `Objective_<easy|medium|hard>` ; puits `Tile_<dalle>`, `CozyBed`), montants et solde en secondes de revenu ; aucune source `Product_` (aucun achat ne donne de pièces) ; ≤ 10 requêtes par joueur et par minute.
- Specs de propriété exigées (`EconomyService.spec`) : N règlements dans [t0, t1] = 1 règlement (à 1e-9 relatif près) ; 100 refus de `BuyTile` en 10 s n'ajoutent aucune pièce au-delà de l'intégrale de base ; un `settle` juste après le chargement n'ajoute rien de l'absence au-delà de la part hors ligne (25 % / 30 %, arrêt à 90 % de l'objectif, 8 h) ; chaque déclencheur de `refresh` (dont trophée, page dorée, famille, Fame) ; récompense en secondes de revenu avec P et B appliqués une seule fois ; joueur resté sur une dalle trop chère : achat au premier tick où les pièces suffisent, une seule fois par entrée.
- Clés : `lastOnline`, `coins`, `pot`, `R`, `growth`, `tiles`, `fame`, `boosts`, `caps` (plus de `coinBuy`). Émet `TileBought`, `PotCollected`. Remote : `BuyTile`. Dépendances : DataService, MonetizationService (`ownsPass("DoubleCoins")`, `"AutoPot"`), RanchService, DiagnosticsService, `Logic/{Formulas,QuestRules}` (familles, pages dorées lues dans `data.dex`).

### 11.6 SquishyService (paquet ranch) — GDD §4.3, §4.7, §4.9, §4.10, §4.12-§4.16

*Fichier : `src/server/Services/SquishyService.luau` (paquet ranch).*

```lua
export type Counts = { pen: number, pool: number, dodo: number, mail: number, penCapacity: number, poolSlots: number }
export type GiveSpec = { s: number, m: number, st: number, z: number }

SquishyService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
SquishyService.Start()  -- Connexions et boucles (stub : ne fait rien)
SquishyService.step(now: number, actors: { [Player]: Types.TickActor })  -- Tick : gouttes dues, fusions et combos dus, portage hors du ranch terminé
SquishyService.records(player: Player): { [string]: Types.SquishyRecord }  -- Collection (lecture seule)
SquishyService.get(player: Player, uid: string): Types.SquishyRecord?  -- Une ligne (lecture seule)
SquishyService.sizeOf(player: Player, uid: string, t: number?): number  -- Taille actuelle
SquishyService.biggest(player: Player): (string?, number)  -- Plus gros squishy (enclos et Bassin) et sa taille
SquishyService.counts(player: Player): Counts  -- Places occupées et capacités
SquishyService.give(player: Player, spec: GiveSpec, source: string): (string?, string)  -- Ajoute un squishy (enclos → Dodo → Lettres → pièces) ; rend (uid, lieu ou "coins")
SquishyService.hatchScripted(player: Player, kind: "twin" | "firstPull")  -- Naissance scriptée de l'accueil (jumeau de Plop, premier vrai tirage)
SquishyService.press(owner: Player, uid: string, tClient: number, visitor: Player?): boolean  -- Pression (chez soi, ou pet-sitting par visitor) ; récompenses et Signals.Pressed
SquishyService.carried(player: Player): string?  -- uid porté
SquishyService.endCarry(player: Player, reason: string)  -- Le squishy porté retourne à sa place
SquishyService.riding(player: Player): boolean  -- Sur sa monture
SquishyService.dismount(player: Player, reason: string)  -- Descend (mort, Bassin, prise, panneau)
SquishyService.resetSizes(player: Player)  -- Grand Splorch : chaque squishy repasse à la taille 1 (z = 1, zg = 0)
SquishyService.setWaiting(player: Player, uid: string?)  -- Squishy en attente de Grand Splorch (ni boopable, ni vendable, ni fusionnable)
SquishyService.growFor(player: Player, uid: string, seconds: number): boolean  -- z += EconomyService.gNoBoost × seconds (Héros 3 600 s, retour seul 1 800 s), une fois par squishy et par jour UTC (rec.gd) ; false si déjà fait aujourd'hui
SquishyService.waiting(player: Player): string?  -- uid en attente de Grand Splorch (nil = aucun) : RushService n'amène alors aucun squishy de ce joueur à la clôture
SquishyService.anyEscaping(player: Player): string?  -- uid d'un squishy du joueur en fuite (nil = aucun) : GrandSplorch refusé (Feedback waitEscape)
SquishyService.setEscaping(player: Player, uid: string, escaping: boolean)  -- En fuite (exclu du portage, de la vente, de la fusion)
SquishyService.bestFriend(player: Player, slot: number): string?  -- uid du Meilleur Ami n° slot
SquishyService.fenceCandidates(player: Player, ctx: RushRules.FenceCtx): { string }  -- Squishies prêts à venir à la clôture
SquishyService.readyAt(player: Player, uid: string): number  -- Clock.now() où la recharge de pression finit
SquishyService.saddle(player: Player): number  -- Selle gagnée 0 … 3
SquishyService.openStates(): { Types.OpenState }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- **Ajouter** (`give`) : enclos s'il y a de la place (`counts`), sinon Dodo, sinon Lettres, sinon `EconomyService.addIncomeSeconds(player, Balance.Babies.FallbackSeconds, …)` et `Feedback babyAsCoins` (jamais une perte silencieuse). Verrou automatique (rareté ou mutation `autoLock`). Le tout premier squishy du compte (`nextUid == 1`) devient Meilleur Ami n° 1. `Signals.SquishyObtained`, `markDirtyEntry`, `RanchService.squishyOp`, `EconomyService.refresh`.
- **Presser** (`press`, et remote `Press`) : uid en enclos ou Bassin ; distance **à plat** ≤ `Balance.Press.Range + RangeTolerance` (10 + 2) entre la position validée et le centre de la place du squishy (`WorldLayout.penSlot` / `poolSlot`, ou `fencePoint` pour le pet-sitting), pieds ≤ 8 ; recharge (`readyAt`) ; PERFECT = `PressTiming.isPerfect(PressTiming.clampClientTime(tClient, now), PressTiming.offset(ownerId, uid))` ; série (remise à 0 par une pression non PERFECT ou 6 s sans pression) ; récompense `Formulas.pressReward(revenu du squishy, perfect, série, Kitty)` → `EconomyService.addCoins` ; `Signals.Pressed` ; `Celebrate "press"` (au propriétaire ; au visiteur pour le pet-sitting). Pet-sitting (`visitor`) : le propriétaire reçoit la récompense **sans** PERFECT ; le visiteur reçoit `Balance.Rewards.PetSitVisitor` s de son revenu (× 2 si PERFECT ; 2 s en v1.3) par CommunityService. PERFECT = `PressTiming.isPerfect(t, PressTiming.offset(ownerId, uid))` (hachage de l'UserId du propriétaire et de l'uid, même calcul chez soi et en pet-sitting).
- **Cuve** : `vat.fillAt` (Clock.unix()) ; à échéance (`step`) : la naissance va dans un enclos libre, **sinon dans la Boîte à dodo** (`Celebrate "hatch"` avec `at = "dodo"` : bulle « Boîte à dodo ! » sur la Cuve côté client) ; enclos **et** Dodo pleins → `vat.pending = true` (minuteur arrêté, « Plein ! ») ; goutte, éclosion 2 s plus tard (échéance dans `step`), tirage `Odds.roll(Hash.stream(Odds.seed(UserId, vat.pulls)), ctx)` avec qualité, buses, Lune, familles débloquées, nouveauté garantie (`vat.newPulls`) et protections (`pityRare`, `pityEpic`). Pendant l'accueil (`QuestService` appelle `hatchScripted`) : jumeau de Plop à 0:40, premier vrai tirage à 2:45 ; la Cuve naturelle démarre à 5:00 de jeu (`Quests.Onboarding.ScriptUntil`). La Cuve ne tourne que joueur présent. `Signals.Hatched`, `Celebrate "hatch"`, bannière (`legendHatch`, `mythicHatch`, `secretHatch`, `rareMutation`) avec `oneIn`.
- **Clôture toujours vraie** : tout squishy qui quitte l'enclos (`PickUp`, `Throw`, `MoveSquishy` vers le Dodo, `FuseMenu`, `FuseAll`, `setWaiting`, `Sell`, `Release`) est retiré **aussitôt** de la clôture de son ranch : `RanchService.setFence(slot, uids sans lui, raison actuelle)`. Le maintien de boop en cours sur lui est annulé au tick suivant par RushService (`BoopCtx.eligible`, §11.9).
- **Portage** : `PickUp` → `carried[player] = uid` (RanchPublic `carry`), descente de monture ; fin (`endCarry`) sur : mort, réapparition, sortie du ranch (vérifiée dans `step` avec la position validée), fenêtre ouverte (le client envoie `PutDown`), monture, départ. Pendant le portage : Bondir et Monter refusés.
- **Bassin et combos** : `Throw` → `FusionRules.throwOutcome` ; "fuse" → fusion à `now + FuseDelay` (échéance dans `step`), puis chaîne (`FusionRules.nextInChain`) à `+ ComboDelay` par étape ; récompense `Formulas.comboReward(k, revenu du résultat)` ; `Signals.Fused` par étape ; bannières `combo4` (k ≥ 4), `combo5` (k ≥ 5) ; "full" → `Feedback poolFull`, le squishy reste porté. `FuseMenu` : les deux sautent dans le Bassin, même règle. `FuseAll` : `FusionRules.planMergeAll`, étapes jouées une par une par les échéances (jamais d'un coup), résultat en enclos sinon en Dodo.
- **Vendre / ranger / relâcher** : `Sell` (`Formulas.sellValue`) ; `Release` (+1 Fame via `EconomyService.addFame(…, "release")`, 12 derniers dans `released`) ; refus pour Meilleur Ami, verrou, fuite, attente, portage ; `confirmed` exigé pour Épique+ ou mutation `sellConfirm`. Tenue d'un squishy vendu ou relâché : rendue à la garde-robe. `Signals.SquishyRemoved`.
- **Monture** : selle = `Formulas.saddleLevel(biggestEver)` ; `Ride(true)` : `Humanoid.WalkSpeed`, `JumpHeight`, `HipHeight` fixés par `Formulas.rideStats` (seules valeurs touchées) puis `MoveCheck.setRootOffset(player, rideStats.hipHeight − Balance.Ride.BaseHipHeight, rideStats.jumpHeight)` ; `Ride(false)` ou fin forcée (mort, réapparition, Bassin, prise, panneau, départ) : valeurs de base et `MoveCheck.setRootOffset(player, 0, Balance.Ride.BaseJumpHeight)`. Le décalage accorde une marge verticale ponctuelle égale à son changement (note INT-MOVE) : monter ne déclenche ni « montée » ni « vol bas ». Monture par défaut : la plus grosse.
- **Trophées et record** : crochet `EconomyService.onSettle` → `trophies[s] = max(trophies[s], taille)` et `biggestEver` ; nouvelle selle → `Celebrate "saddle"` ; palier de trophée franchi → `EconomyService.refresh` (bonus de l'Étagère dans A).
- **Croissance du Rush** (`growFor`, GDD v1.3 §4.21.3) : `z += EconomyService.gNoBoost(player) × seconds` pour ce squishy, si `rec.gd ~= Clock.day()`, puis `rec.gd = Clock.day()` ; appelé par ChaseService (Héros : `Balance.RushSize.HeroGrowthSeconds`, retour seul : `ReturnGrowthSeconds`).
- **Tenues** : la tenue portée vit dans `rec.o` seulement ; `EquipOutfit` compte les porteurs (`o == id`) et refuse si `porteurs ≥ owned[id]` ; `outfits.worn` n'est jamais lu ni écrit.
- `openStates()` : « carry », « fusion », « combo », « hatch » (échéances dues).
- Clés : `squishies`, `nextUid`, `mount`, `vat`, `released`, `trophies`, `outfits`, `biggestEver`. Émet `Pressed`, `SquishyObtained`, `Hatched`, `Fused`, `SquishyRemoved`. Dépendances : DataService, MonetizationService (`BigRanch`), RanchService, EconomyService, `Logic/{Odds,FusionRules,PressTiming,ZoneRules,Formulas,SizeScale,RushRules,Hash}`.

### 11.7 QuestService (paquet meta) — GDD §3, §4.17, §4.20, §7.3, §7.4, §16.1

*Fichier : `src/server/Services/QuestService.luau` (paquet meta).*

```lua
export type OnboardingScript = {
	active: boolean, -- accueil en cours (avant Quests.Onboarding.ScriptUntil)
	runawayAt: number?, -- s de jeu de la première créature en fuite (Mochi Mew)
	demoAt: number?, -- s de jeu de la démonstration de Big Plop
	runawayPaused: boolean, -- fuites en pause (2:45 → 5:00)
	vatScripted: boolean, -- la Cuve suit le script (une goutte toutes les 90 s)
}

QuestService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
QuestService.Start()  -- Connexions et boucles (stub : ne fait rien)
QuestService.step(now: number)  -- Tick : temps de jeu, délais de l'accueil, script (jumeau, premier tirage), minuit, carte sommeil, maintien du bol
QuestService.stage(player: Player): number  -- Étape d'accueil atteinte (0 … 11)
QuestService.isNewcomerQuiet(player: Player): boolean  -- Événements discrets pour ce nouveau (avant l'étape 9)
QuestService.playSeconds(player: Player): number  -- Jeu cumulé
QuestService.script(player: Player): OnboardingScript  -- Horaires scriptés de l'accueil pour ChaseService et SquishyService
QuestService.stamp(player: Player, species: number, mutation: number, stars: number): boolean  -- Tamponne le Squishydex (vrai si nouvelle entrée) ; Celebrate "dexNew"
QuestService.openStates(): { { name: string, startedAt: number, player: Player? } }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- **Accueil** : étapes de `Config/Quests.Onboarding.Steps`, déclenchées par les signaux (première pression, premier achat, première fusion…) ou par le temps de jeu (script). Chaque étape → `onboarding.step`, `Signals.OnboardingStep`, `Celebrate "onboarding"`, `Analytics.funnel(player, n, key)`. Délai d'une consigne : 90 s (`StepTimeout`), puis l'accueil continue (aucune étape ne bloque). Naissances scriptées : `SquishyService.give` (Plop de départ à l'étape 1), `hatchScripted("twin")` à 0:40, `hatchScripted("firstPull")` à 2:45 ; jamais rejouées au retour. `script(player)` donne à ChaseService la première fuite (2:00, Mochi Mew) et la démonstration (3:00).
- **Temps de jeu** : `stats.playSeconds += dt` dans `step` ; bouclier (15 min), carte du choix (15 min), Boutique (10 min) lisent cette valeur.
- **Objectifs** : à la première connexion du jour, `QuestRules.draw(UserId, Clock.day(), ctx, premier jour)` ; progression par les signaux (`QuestRules.apply`) ; réclamation (`Formulas.secondsOfIncome`, **aucun boost** depuis la v1.2 : `Quests.ObjectiveRules.Rewards[niveau].boost = 0` ; analytique `Objective_<easy|medium|hard>`) ; les 3 terminés : Goutte chanceuse (`Odds.roll` qualité + 1, mutations × 2, `SquishyService.give`) ; minuit en session : `QuestRules.rollover` (terminés réclamés seuls, en cours gardés pour la session), nouveaux objectifs à la connexion suivante (`Celebrate "newObjectives"`).
- **Nourrir Plop** : `FeedPlop(true)` à plat ≤ 8 studs du bol → maintien de **2 s** mesuré par le serveur (`HoldState { kind = "feed" }` envoyé), `FeedPlop(false)` ou sortie de zone → annulé ; fin : `plopDays += 1`, `lastFeedDay = Clock.day()`, palier (`QuestRules.plopReward`) et boost de 5 min chaque jour (`Balance.Boosts.FeedDay` = `FeedMilestone` = 300), `Signals.Fed`, `Celebrate "plopDay"`.
- **Squishydex** : sur `SquishyObtained` → `stamp` (bits d'espèce, de mutation, badges d'étoiles) ; nouvelle entrée → `Celebrate "dexNew"`, `Signals.Stamped`, `EconomyService.refresh` (familles, pages dorées) ; jalons réclamés par `ClaimDexReward`. Quand un tampon complète une famille (`QuestRules.familyComplete`), `dex.fam[f] = 1` (index de `Species.FamilyOrder`) : bonus **gagné pour toujours** ; les bonus de famille de l'économie lisent `dex.fam`, jamais l'ensemble actuel des espèces (une espèce ajoutée plus tard ne retire rien).
- **Carte « Plop a sommeil »** : `Celebrate "sleepy"` à 60 et 120 min de jeu dans la session.
- **Écrans vus** (`UiSeen(screen)`, une fois par écran et par session) : `"objectives"` → étape 10 de l'accueil (GDD §16.1) ; chaque écran → `Signals.UiSeen` et analytique. Ne donne jamais rien.
- **Amis** : `Signals.FriendsChanged(player, n)` (CommunityService) → `QuestCtx.friendOnServer`, objectif 12 (relance gratuite si l'ami part), `stats.lastFriendDay`.
- **Départ** : compteurs de session écrits dans `onBeforeSave` quand `release == true` (§1 règle 15).
- `openStates()` : « feedHold », « onboardingStep ».
- Clés : `firstJoin`, `codes`, `dex`, `plopDays`, `lastFeedDay`, `onboarding`, `objectives`, `stats`. Dépendances : DataService, RanchService, EconomyService, SquishyService, WorldService (via `RanchService.refreshBuild`), `Logic/{QuestRules,Odds,StateTimeouts}`.

### 11.8 CommunityService (paquet meta) — GDD §6

*Fichier : `src/server/Services/CommunityService.luau` (paquet meta).*

```lua
CommunityService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
CommunityService.Start()  -- Connexions et boucles (stub : ne fait rien)
CommunityService.step(now: number, actors: { [Player]: Types.TickActor })  -- Tick : clôtures de pet-sitting, fenêtres d'applaudissement, file des bannières
CommunityService.displayName(player: Player): string  -- Nom d'affichage, ou alias « Squishy Fan #NNNN » si caché (clé de texte côté client)
CommunityService.friendsPresent(player: Player): number  -- Amis Roblox présents (mis en cache)
CommunityService.areFriends(a: Player, b: Player): boolean  -- Amis Roblox (cache de session)
CommunityService.isBlocked(a: Player, b: Player): boolean  -- L'un a bloqué l'autre (liste souple fournie par le client)
CommunityService.setting(player: Player, key: string): any  -- Réglage du joueur (Config/Settings) ou du serveur (allowRush)
CommunityService.openClapWindow(hero: Player, endsAt: number)  -- Fenêtre APPLAUDIR de 8 s chez les autres joueurs
CommunityService.hasCosmetic(player: Player, kind: string, id: string): boolean  -- Cosmétique débloqué (source de Config/Cosmetics)
CommunityService.openStates(): { Types.OpenState }  -- États minutés ouverts (« clapWindow ») : robot de longue durée
CommunityService.unlockSession(player: Player, kind: string, id: string)  -- Déblocage de session (titres du top 10 de la semaine, appelé par LeaderboardService)
```

- **Amis** : à chaque arrivée et départ, recompte les amis Roblox présents de chaque joueur (`IsFriendsWith` sous `pcall`, en cache pour la session) → `EconomyService.setFriendsPresent` (appel direct, rang plus précoce) et `Signals.FriendsChanged(player, n)` quand le nombre change (QuestService : objectif 12, `stats.lastFriendDay`).
- **Pet-sitting** (`step`) : hors Rush, pour chaque ranch dont un ami se tient côté rue à ≤ 10 studs (`ZoneRules.streetSideOfFence`) : jusqu'à 3 squishies prêts → `RanchService.setFence(slot, uids, "petsit")` ; libérés quand l'ami s'en va (`setFence(slot, {}, "petsit")`, sans effet sur une clôture du Rush) ; réappliqués au step qui suit la fin du Rush. `PetPress` : vérifie d'abord les plafonds sans consommer (`caps.petSit` du visiteur < 100, `caps.petSitIn` du propriétaire < 100), puis `SquishyService.press(owner, uid, tClient, visitor)` (portée à plat 10 + 2 du centre de la place à la clôture, pieds) ; s'il rend `true` : `consumeCap(visiteur, "petSit", 1)`, `consumeCap(propriétaire, "petSitIn", 1)`, `Balance.Rewards.PetSitVisitor` s de revenu du visiteur (× 2 si PERFECT), `helpful = consumeFriendCap(visiteur, "petSit", ownerId, 1) > 0` et `Signals.PetSitRewarded(visiteur, propriétaire, helpful)` (« Plus serviable » ne compte que `helpful = true` : 20 par ami et par jour, il faut aider 5 amis pour compter 100).
- **Déblocages de session** : `unlockSession(player, kind, id)` (titres du top 10, source `weekly`) ; `hasCosmetic` les voit aussitôt ; perdus au départ (redonnés par LeaderboardService à l'arrivée suivante tant que la semaine dure).
- **Emotes** : `Emote(kind)` → `EmoteShow` à tous (l'emote de la croix ← vient de `settings.emoteLeft`), `Signals.Emoted`.
- **Applaudissements** : `openClapWindow(hero, endsAt, viewers?)` → `ClapPrompt` aux seuls `viewers` (spectateurs du spectacle complet, choisis par SplorchService ; `nil` = tous sauf le héros) ; `Clap(heroId)` dans la fenêtre, seulement d'un joueur de `viewers` → 10 s de revenu (`caps.claps`), `EmoteShow` (cheer), `Celebrate "clapCount"` au héros (cumulé).
- **Bannières** : abonnement à `BannerRequested` ; file (3 au plus, 3 s, priorité, 10 s par joueur source) ; `Banner` envoyé à chaque joueur sauf les nouveaux avant l'étape 9 (`QuestService.isNewcomerQuiet`).
- **Réglages** : `SetSetting` (types et valeurs de `Config/Settings`, emote débloquée, `allowRush` réservé au propriétaire du serveur privé : réglage de serveur en mémoire) → `settings`, `Signals.SettingChanged` ; `hideName` → `RanchService.setPublic({ name, hidden })`.
- **Nom caché** : `displayName` rend `""` quand le nom est caché ; le client écrit `name.alias` avec `Hash.alias(userId)`.
- **Liste de blocage souple** : `ReportBlocked` (envoyé une fois par `WorldStateController.Start` depuis `StarterGui:GetCore("GetBlockedUserIds")`, sous `pcall`) remplace la liste de l'envoyeur ; `isBlocked(a, b)` vrai si l'un des deux a bloqué l'autre.
- Clés : `settings`, `cosmetics`. Émet `Emoted`, `SettingChanged`, `FriendsChanged`, `PetSitRewarded`. Dépendances : DataService, RanchService, EconomyService, SquishyService, QuestService, `Logic/{ZoneRules,Hash}`, `Util/Notify`.

### 11.9 RushService (paquet chase) — GDD §4.21, §13

*Fichier : `src/server/Services/RushService.luau` (paquet chase).*

```lua
RushService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
RushService.Start()  -- Connexions et boucles (stub : ne fait rien)
RushService.step(now: number, actors: { [Player]: Types.TickActor })  -- Tick : clôtures, maintiens de boop finis ou rompus, carte du choix au calme
RushService.isRush(player: Player): boolean  -- Mode effectif Rush
RushService.isShielded(player: Player): boolean  -- Bouclier débutant actif
RushService.canBeBooped(owner: Player): boolean  -- Ranch boopable maintenant (badge rose)
RushService.allowRush(): boolean  -- BOOP RUSH autorisé sur ce serveur (serveur privé)
RushService.openStates(): { Types.OpenState }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- **Mode** : `mode.rush` est le mode **choisi** ; le mode **effectif** est Cozy si le joueur n'a jamais choisi, s'il est sous bouclier pour être boopé (il peut booper s'il a choisi Rush), ou sur un serveur privé sans autorisation. `SetMode(false)` : immédiat (clôture vidée, `Signals.ModeChanged` → ChaseService fait rentrer ses fuites sans bonus ; plus de boop jusqu'à la fin du Rush). `SetMode(true)` : refusé avant 60 s depuis `changedAt` ; appliqué à la fin du Rush en cours. `RanchService.setPublic({ mode, shield, boopable })`.
- **Carte du choix** : `ModePrompt` une fois (`mode.cardShown`), quand `QuestService.playSeconds ≥ 900` ; le client attend le calme (dans son ranch, immobile 1,5 s, aucun Rush ni MEGA, prochain Rush à plus de 60 s), affiche la carte et envoie `UiSeen("modeCard")` ; le serveur ouvre alors l'état « modeCard » (20 s, `openStates`) ; réponse `SetMode` → analytics 1 / 0 ; sans réponse en 20 s (+ 0,5 s de grâce) : Cozy et `RushModeChosen = −1`. La carte du client se ferme seule à 20 s sans rien envoyer.
- **Clôtures** (`step`, sur `EventPhase("rush", "start")` puis toutes les 20 s) : pour chaque ranch boopable, `RushRules.fenceCount` squishies parmi `SquishyService.fenceCandidates` (tirage `Hash`, graine `EventClock.seed("rush", index)`) → `RanchService.setFence(slot, uids, "rush")`. **Aucun squishy d'un joueur en file de Grand Splorch** (`SquishyService.waiting(owner) ~= nil` : clôture vidée, ranch sauté ; GDD v1.3 §4.15). Fin du Rush : `setFence(slot, {}, "rush")` (n'efface jamais une clôture de pet-sitting).
- **Boop** (`BoopHold(ownerId, uid, true)`) : `RushRules.checkBoop` (contexte construit avec EventService, CommunityService, SquishyService, `ChaseService` non appelé : la distance vient de `MoveCheck.lastValid`) ; `BoopCtx.eligible = RushRules.fenceEligible(rec, FenceCtx)` avec le lieu **actuel** du squishy (ni porté, ni Bassin, ni Dodo, ni en attente…), vérifié juste après `atFence` (refus `notAtFence`) ; maintien `RushRules.holdTime(propriétaire proche)` ; `BoopState` ; à chaque tick : toutes les règles revérifiées, dont `eligible` (squishy pris, lancé, rangé au Dodo, mis en attente : maintien annulé), propriétaire passé en Cozy, distance, canAct → sinon annulé (`BoopState cancel`, `Feedback boopCancelled`) ; propriétaire qui arrive : `RushRules.extendHold`, **une seule fois par maintien** (la durée ne dépasse jamais `StateTimeouts` « boopHold » = 5,5 s). `holding = false` ou absence de message : fin au plus tard à `endsAt + 0,5 s`. Succès : compteurs (paire, ranch, heure, serveur), `Signals.Booped(boopeur, propriétaire, uid, angle opposé au boopeur)`, `Celebrate "boopDone"` / `"booped"`, analytics `BoopDone`.
- **« Pas ce joueur »** (`RefuseBooper`) : ce boopeur ne peut plus booper l'envoyeur jusqu'au départ de l'un des deux ; le boopeur n'en sait rien.
- **Après le premier boop subi** : sur `EscapeEnded` du propriétaire (première fois) → la carte « revient toujours » est déclenchée par ChaseService (`Celebrate "ownerReturn"` avec `firstBoop = true`) ; `mode.postBoopCardShown`.
- `openStates()` : « boopHold », « modeCard », « rush ».
- Clé : `mode`. Dépendances : DataService, RanchService, SquishyService, QuestService, CommunityService, EventService, `Logic/{RushRules,ZoneRules,EventClock,Hash}`, `Config/Features`.

### 11.10 EventService (paquet chase) — GDD §2.4, §4.11, §4.22, §4.23, §7.5

*Fichier : `src/server/Services/EventService.luau` (paquet chase).*

```lua
EventService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
EventService.Start()  -- Connexions et boucles (stub : ne fait rien)
EventService.step(now: number, actors: { [Player]: Types.TickActor })  -- Tick : phases, MEGA (agrégation, battement), jauge, fêtes, file des spectacles, Autel
EventService.state(): Types.EventStatePayload  -- État diffusé (dernier envoyé)
EventService.rushActive(): boolean  -- Rush en cours
EventService.moonActive(): boolean  -- Séance de Jelly Moon en cours
EventService.eventBoopActive(): boolean  -- Mode BOOP RUSH "events" : Lune ou fête d'administrateur en cours
EventService.addGauge(points: number)  -- Points de jauge (bornés, ignorés pendant la fête)
EventService.enqueueSpectacle(kind: "splorch" | "dance", userId: number): number  -- Place dans la file ; rend le Clock.now() de départ prévu
EventService.cancelSpectacle(userId: number)  -- Retire de la file (départ du joueur avant son tour)
EventService.canStartParty(): boolean  -- Une Squish Party peut commencer aussitôt
EventService.startSquishParty(buyer: Player, showName: boolean): boolean  -- Démarre la fête payée (10 min, ×2 serveur) ; pendant une fête, la prolonge de 600 s (segment noté pour l'acheteur)
EventService.partyUnplayed(userId: number): number  -- Secondes de Squish Party achetées par ce joueur et pas encore jouées (≤ 600 par achat)
EventService.playerCount(): number  -- Joueurs sur le serveur (N)
EventService.isActive(player: Player, now: number): boolean  -- Joueur actif (Activity, ou à 60 studs du centre de la place pendant l'alerte du MEGA)
EventService.activeCount(now: number): number  -- N actifs (au moins Events.Activity.MinPlayers) : objectifs du MEGA et de la jauge
EventService.openStates(): { Types.OpenState }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- **Phases** (`step`) : `EventClock.rush/mega/golden/moon(now)` comparées à l'état précédent → `Signals.EventPhase(sorte, phase, index)` une seule fois par index (idempotent même si le tick rattrape plusieurs pas) ; `EventState` envoyé à chaque changement.
- **Interrupteurs vers les clients** : `EventState.features` (`Types.EventFeatures`) est rempli depuis `Features.get` (`BoopRush`, `MegaSquish`, `GoldenWobbler`, `JellyMoon`, `ServerGauge`, `Clips`, `Costumes`, `Diagnostics`) ; EventService est le seul à appeler `Features.set` sur le serveur (LiveOps, `AdminCommand "feature"`) et renvoie `EventState` à tous après chaque changement appliqué. Variante de `ClientReplay.spec` : `MegaSquish = false` → aucune bannière ni pastille MEGA.
- **MEGA** : alerte (15 s), atterrissage (espèce `EventClock.megaSpecies`, N = `activeCount(now)` à l'atterrissage, au moins 1, objectif `MegaRules.target(N, échecs de suite)`), pression 60 s (`MegaPress` : phase, distance à plat ≤ 20 studs du centre à la position validée, pieds ≤ 8, `canAct`, recharge 0,4 s, `MegaRules.isPerfect(landsAt, PressTiming.clampClientTime(tClient, now))` → 1 ou 3 points), `MegaBeat` toutes les 0,25 s, fin : réussite (bébés par paliers `MegaRules.babiesFor`, qualité + 2, mutations × 2, 25 % Lunaire en MEGA MOON, `SquishyService.give` ; 60 s de revenu ; +1 Fame ; jauge `Gauge.Points.mega`) ou échec (60 s de revenu pour chaque participant à ≥ 10 points). `Signals.MegaJoined`, `Celebrate "megaResult"`, analytics `MegaResult`. Pas de MEGA si `Features.MegaSquish` est faux.
- **Joueurs actifs** (v1.2, GDD §4.22) : `isActive(player, now)` = `Activity.isActive(player, now)` (intention de jeu acceptée ou déplacement validé ≥ 4 studs dans les 120 s) ou, pendant l'alerte du MEGA, position validée à ≤ `Events.Activity.MegaAlertRadius` (60) du centre de la place ; `activeCount(now)` ≥ `Events.Activity.MinPlayers` (1). N du MEGA = `activeCount` à l'atterrissage ; N de la jauge = `activeCount` recalculé en direct. Analytique `MegaResult` avec N et le nombre de participants.
- **Jauge — règle unique** : seul EventService convertit les faits du jeu en points, et seulement avec `Config/Events.Gauge.Points` (aucun autre champ de configuration ne porte de points : `Contract_game` le vérifie). Sources : `Pressed` (`press` = 0, + `perfect` si PERFECT : seule une pression PERFECT compte ; `petSit` au visiteur si `PressInfo.visitor`), `Hatched` (`hatch`), `Fused` (`fuseStep` par étape), `Caught` (sorte `"escape"` → `rushCatch`, sinon `catch`), `NearCatch` (`"golden"` → `catch`, `"rush"` → `rushNear`), `Fed` (`feed`), `Splorched` (`splorch`, une fois), réussite du MEGA calculée ici (`mega`, à chaque participant). `addGauge` est réservé aux commandes d'administrateur et aux specs : aucun service ne l'appelle. Objectif `Events.Gauge.TargetPerPlayer (600) × max(2, N actifs)` recalculé en direct ; pleine → danse de Big Plop (spectacle `"dance"` dans la file), puis WOBBLE PARTY 5 min (`EconomyService.setServerBoost("wobble", …)`), jauge figée pendant la fête puis 0, puis **sieste de Big Plop** de `Events.Gauge.RestSeconds` (1 200 s) : `EventState.gauge.restUntil`, les points continuent de compter, aucune fête ne commence avant la fin de la sieste (au plus 5 min de ×2 toutes les 25 min). `WorldService.setGauge`. Analytique `GaugeFilled` (minutes depuis la précédente, sieste comprise). `EventService.spec` : un Grand Splorch donne exactement +25 ; une pression ordinaire 0 ; jauge pleine pendant la sieste → fête à la fin de la sieste seulement.
- **File des spectacles** : `enqueueSpectacle` place à `max(now, dernier départ + SpectacleGap, fin du prochain grand spectacle fixe + SpectacleGap)` ; à l'heure : `Signals.SpectacleStarted(sorte, userId, now)` ; coupure dure à 10 s ; `cancelSpectacle` au départ du joueur. Chaque entrée de `EventState.spectacle.queue` porte `slot`, `position` (1 = prochain) et `eta = position × Events.SpectacleGap + reste du grand spectacle en cours` (Rush jusqu'à 90 s, MEGA 65 s, Grand Splorch, danse), recalculés à chaque changement : suivi du HUD « 2e dans la file · ≈ 0:40 » (`hud.queue.place`). État « splorchQueue » : attente dynamique, coupure dure à `Events.SplorchQueueHardCut` (480 s, `StateTimeouts`). **Héros parti pendant son spectacle avant l'éclatement** : `EventState.spectacle.current` effacé aussitôt et renvoyé ; les clients arrêtent le spectacle sans pluie de cadeaux (remarque A26, variante de `ClientReplay.spec`).
- **Jelly Moon** : Autel — présence ≥ 5 min (`ZoneRules.atAltar`, acteurs) pendant une séance → à la fin, Goutte de Lune (`Odds.roll` qualité + 1, Lunaire forcée), `Celebrate "lunarDrop"` ; une par séance **et par compte** : `moon.lastSession` (clé d'EventService) = numéro de la séance, jamais redonnée après un changement de serveur.
- **Boosts de serveur et fêtes** : priorité payée > administrateur > Wobble Party ; `canStartParty` vrai si aucune Squish Party n'est en cours (le client cache alors le bouton) ; `startSquishParty` (10 min) → `setServerBoost("squish", …)`, bannière `squishParty` (ou `squishPartyBy` si l'acheteur l'a choisi) ; un reçu qui arrive **pendant** une fête la **prolonge** de 600 s (jamais refusé, aucune file en mémoire) ; un segment de 600 s est noté par achat et par acheteur ; `partyUnplayed(userId)` = secondes achetées par ce joueur et pas encore jouées (≤ 600 par achat), rendues en boost personnel par ProductService (§11.12).
- **LiveOps** : abonnement `MessagingService` au sujet `Events.Party.LiveOpsTopic` (sous `pcall`, nouvel essai) ; messages acceptés seulement s'ils portent l'UserId d'un administrateur : fête d'administrateur (5 Golden en 5 min + ×2 10 min), `Features.set` (couper un événement).
- **`AdminCommand`** (administrateurs seulement, envoyé par l'onglet Outils du panneau Diagnostics) : `"party"`, `"feature"` (`arg` = `clé=valeur`), `"clock"` (`arg` = secondes de décalage, `Clock.setOffset`, diffusé par `EventState.offset`) **seulement si `RunService:IsStudio()`** (§20 n° 25 : un serveur privé écrit le vrai magasin `PlayerData_v1`, un décalage y corromprait les horodatages sauvegardés), `"forceRush"`, `"forceMega"`, `"testError"` (`arg = "server"` : erreur volontaire comptée par Diagnostics ; `arg = "client"` : `Celebrate "testError"` à l'envoyeur, erreur volontaire de son client ; test manuel M17), `"photo"` (cache le HUD des administrateurs pour les vignettes : `Celebrate "photo"`). Commande inconnue ou refusée : ignorée. `EventService.spec` : `"clock"` hors Studio est ignorée.
- `openStates()` : « mega », « spectacle », « squishParty », « wobbleParty », « gaugeRest ».
- Clé : `moon`. Émet `EventPhase`, `SpectacleStarted`, `MegaJoined`. Dépendances : DataService, WorldService, RanchService, EconomyService, SquishyService, QuestService, CommunityService, DiagnosticsService, `Logic/{EventClock,MegaRules,Odds,ZoneRules,PressTiming}`, `Config/Features`.

### 11.11 SplorchService (paquet chase) — GDD §4.15, §6.7, §9.4

*Fichier : `src/server/Services/SplorchService.luau` (paquet chase).*

```lua
SplorchService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
SplorchService.Start()  -- Connexions et boucles (stub : ne fait rien)
SplorchService.step(now: number)  -- Tick : éclatement dû, fin du spectacle (coupure dure à 10 s)
SplorchService.queued(player: Player): number?  -- Clock.now() de départ prévu si le joueur est dans la file
SplorchService.isWaiting(player: Player, uid: string): boolean  -- Ce squishy attend son Grand Splorch
SplorchService.openStates(): { { name: string, startedAt: number, player: Player? } }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- `GrandSplorch(film, flyer)` : plus gros ≥ `Formulas.splorchTarget(R)`, dans son ranch (position validée), rien de porté, **aucun de ses squishies en fuite** (`SquishyService.anyEscaping(player)`, tenu à jour par `setEscaping` ; ChaseService, plus tardif, n'est pas appelé ; refus `Feedback waitEscape { species }`), `flyer` possédé en enclos, pas déjà en file ; puis **garanti** : `SquishyService.setWaiting(player, flyer)`, `EventService.enqueueSpectacle("splorch", UserId)`, `Feedback splorchQueued { time }`. Pendant l'attente, RushService n'amène aucun squishy de ce joueur à la clôture. `film` ne sert qu'au client (capture vidéo).
- `SpectacleStarted("splorch", userId, t)` : spectacle de 7,5 s ; `Celebrate "splorch"` à tous ; à `t + BurstAt` (échéance dans `step`), **d'un seul bloc sans yield** : `EconomyService.applySplorch`, `SquishyService.resetSizes`, `SquishyService.setWaiting(player, nil)`, puis `DataService.saveNow` (en `task.spawn`) ; cadeaux à chaque autre joueur (`receiveGifts`) : `addIncomeSeconds(GiftSeconds)` si `consumeCap("splorchCoins", 1)` (10 par jour), sinon `addIncomeSeconds(Balance.Rewards.GiftSecondsAfterCap)` (10 s) ; + 1 bébé si `consumeCap("splorchGifts", 1)` (espèce qui s'envole, ou espèce Peu commune de sa famille si Épique+, Wibble pour un Secret ; taille `Formulas.babySize(GiftSizeShare, …)`, ≤ 0,5 × le plus gros du receveur ; 10 % de copier une mutation ×5 au plus) ; **spectacle complet ou version courte par spectateur** (GDD v1.3 §4.15) : complet si son dernier spectacle complet date d'au moins `Balance.Splorch.FullShowGap` (180 s, mémoire de session), sinon `Celebrate "splorch"` et `"giftRain"` avec `short = true` (cadeau compté directement, ni capsule, ni secousse, ni vibration, ni APPLAUDIR) ; le héros a toujours le spectacle complet ; `Signals.Splorched(héros, nouveau R, bébés-cadeaux donnés)` émis **après** les cadeaux (la jauge, « Plus généreux » et l'accueil viennent de ce signal ; jamais `EventService.addGauge`) ; `CommunityService.openClapWindow(hero, t + 8, spectateurs du spectacle complet)` ; bannière `splorch` ; analytics `SplorchReached` (R, minutes depuis le précédent, 1 s'il était déjà prêt à la connexion : `readyAtLogin`), `SplorchCoinsLost` (en multiples du prix du Tapis 12 de la boucle), `TileLevelAtSplorch`.
- Départ du héros avant son tour : place rendue (`cancelSpectacle`), `setWaiting(nil)`, rien remis à zéro. Départ pendant le spectacle avant l'éclatement : idem (le profil n'a pas changé) ; EventService efface aussitôt le spectacle en cours et les clients l'arrêtent sans pluie de cadeaux (remarque A26).
- `openStates()` : « splorchQueue », « splorchBurst ».
- Clés : aucune. Émet `Splorched`. Dépendances : DataService, RanchService, EconomyService, SquishyService, CommunityService, EventService, `Logic/{Formulas,Odds}`.

### 11.12 ProductService (paquet ranch) — GDD §8

*Fichier : `src/server/Services/ProductService.luau` (paquet ranch).*

```lua
ProductService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ProductService.Start()  -- Connexions et boucles (stub : ne fait rien)
ProductService.partyBuysToday(player: Player): number  -- Squish Parties achetées aujourd'hui
```

- `Init` : `registerProduct` pour `SquishParty` (refus seulement si `consumeCap("partyBuys", 1) == 0` : rend `false`, Roblox ne débite pas ; un reçu qui arrive pendant une fête la **prolonge** de 600 s par `EventService.startSquishParty`, jamais refusé), `OutfitSweater`, `OutfitCrown`, `OutfitWinter` (garde-robe `outfits.owned[id] += 1` via SquishyService). **Paquets de pièces retirés du lancement** (contrat v1.2, GDD §8.3) : `CoinsSmall` et `CoinsBig` restent dans `Config/Monetization` avec l'id 0 et `hidden = true`, **sans handler** ; plus de `noteCoinBuy`, plus de 2e confirmation du Grand Splorch. Chaque succès : `Celebrate "purchase"`, analytics `Product_<clé>` (IAP ; aucune source de pièces).
- Passes : `PassGranted` → `EconomyService.refresh` (×2 Pièces, appliqué une seule fois), `SquishyService` relit la capacité (Grand Ranch) ; Pot automatique lu par EconomyService.step.
- PolicyService au chargement (`pcall`) : **aucun article caché** ; `ArePaidRandomItemsRestricted` ne sert qu'à l'analytique `PolicyPaidRandomRestricted` (remplace `ShopHiddenByPolicy`) ; `IsContentSharingAllowed` est lu côté client (clips, VFXController). Plus d'attribut `PolicyNoCoins`.
- **Squish Party payée, jamais perdue** : dans le crochet `DataService.onBeforeSave` quand `release == true` (départ de l'acheteur, et `BindToClose` pour chaque joueur présent), `EconomyService.grantPersonalBoost(acheteur, EventService.partyUnplayed(UserId))` (secondes achetées et non jouées, ≤ 600 par achat ; jamais dans `PlayerRemoving`, §1 règle 15), écrit avant la fermeture. `ProductService.spec` : reçu pendant une fête → prolongée de 600 s ; l'acheteur part pendant sa fête → profil sauvegardé avec `boosts.personalLeft` = secondes non jouées ; reçu, fermeture du serveur, nouveau serveur → boost présent **exactement une fois**.
- Dépendances : DataService, MonetizationService, EconomyService, SquishyService, EventService.

### 11.13 LeaderboardService (paquet meta) — GDD §6.6, §6.9

*Fichier : `src/server/Services/LeaderboardService.luau` (paquet meta).*

```lua
LeaderboardService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
LeaderboardService.Start()  -- Connexions et boucles (stub : ne fait rien)
LeaderboardService.step(now: number)  -- Tick : files d'écriture (60 s), lectures (120 s), statue, changement de semaine
LeaderboardService.submit(player: Player, category: string, value: number)  -- Nouvelle valeur de la semaine (écrite si record battu)
LeaderboardService.isBanned(player: Player): boolean  -- Exclu des classements jusqu'à flags.lbBanUntil
```

- Valeurs de la semaine (`weekly`) mises à jour par les signaux : `Stamped` (tampons), `Fused` (meilleur combo), `Caught` (rareté × mutation de la capture ; « généreux » +1 au propriétaire quand un bébé est donné), `PetSitRewarded` (serviable : seulement si son 3e argument est vrai, soit 20 pressions au plus par ami et par jour, 100 par jour), `Splorched` (généreux : 3e argument, bébés-cadeaux donnés). Égalités : premier arrivé (codé dans la valeur, ci-dessous).
- Écritures `OrderedDataStore` `Weekly_<clé>_<semaine>` groupées (60 s), lectures du top 10 (120 s), toujours en `task.spawn` et sous `pcall`. Bannis (`flags.lbBanUntil > Clock.unix()`) jamais écrits.
- **Valeur codée** (GDD §6.9, contrat v1.2 : remplace `valeur × 2 + caché`) : un `OrderedDataStore` ne garde que des entiers ; la valeur écrite est `((score × 2^20) + (2^20 − 1 − s)) × 2 + caché`, où `s` = secondes écoulées depuis lundi 00:00 UTC à l'écriture (< 604 800 < 2^20 : à score égal, le premier arrivé passe devant) et `caché` = 1 si le nom est caché. Lecture : `caché = v % 2`, `u = floor(v / 2)`, `score = floor(u / 2^20)`, `s = 2^20 − 1 − (u % 2^20)`. Plus grande valeur : meilleure capture 5 000 × 100 = 500 000 → ≈ 1,05e12, loin sous 2^53 (aucun arrondi). `LeaderboardService.spec` : égalités (premier arrivé), valeur maximale, décodage exact, drapeau caché.
- **Nom caché dans le top 10 mondial** (protection de l'enfant, GDD §6.9) : drapeau `caché` de la valeur codée ; Caché ou nom inconnu → `name = ""` (le client écrit l'alias `name.alias` avec `Hash.alias(userId)`). Sur `SettingChanged("hideName")`, la valeur de la semaine est réécrite au lot suivant avec le nouveau drapeau. Noms des joueurs absents : `UserService:GetUserInfosByUserIdsAsync` (un appel pour le top 10, sous `pcall`, en `task.spawn`, cache de la semaine) ; échec → `name = ""`. `LeaderboardService.spec` : joueur caché sur un autre serveur → `name = ""` ; panne de UserService → `name = ""`, aucun avertissement.
- Changement de semaine (lundi 00:00) : `weekly.prev`, valeurs à 0 ; titres du top 10 accordés pour la semaine suivante par `CommunityService.unlockSession(player, "title", id)` (source `weekly`), à chaque arrivée tant que la semaine dure.
- Statue : plus gros squishy du serveur (`SquishyService.biggest` de chaque joueur, toutes les 2 s dans `step`) → `WorldService.setStatue` (nom vide si caché). Fanfare du premier à 1e6, 1e9, 1e12, 1e15 sur ce serveur (`Notify.banner("record")`, `Celebrate "fanfare"`).
- Clé : `weekly`. Dépendances : DataService, WorldService, SquishyService, CommunityService.

### 11.14 ChaseService (paquet chase) — GDD §4.11, §4.12, §4.21, §12.3, §12.5, §12.8

*Fichier : `src/server/Services/ChaseService.luau` (paquet chase).*

```lua
ChaseService.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ChaseService.Start()  -- Connexions et boucles (stub : ne fait rien)
ChaseService.tick(now: number)  -- Tick complet (docs/04 §6) ; chaque étape sous pcall, erreur comptée par Diagnostics
ChaseService.actors(): { [Player]: Types.TickActor }  -- Acteurs du dernier tick (positions validées)
ChaseService.active(): { [number]: Types.ChaseSpawn }  -- Créatures actives
ChaseService.isEscaping(owner: Player, uid: string): boolean  -- Ce squishy est en fuite
ChaseService.returnEscapes(owner: Player, reason: string)  -- Toutes les fuites de ce propriétaire rentrent aussitôt (Cozy, départ)
ChaseService.leapCooldownLeft(player: Player, now: number): number  -- Recharge du bond restante
ChaseService.openStates(): { Types.OpenState }  -- États minutés ouverts (débogage, robot de longue durée : §17.2 invariant 6)
```

- **Tick** : §6. `Init` : `MoveCheck.setSurface(WorldLayout.groundY)` ; bornes du monde dans `Movement/Tuning` (note INT-MOVE) : centre (0, 0), `MaxRadius = 330` (murs invisibles à r = 322 ; une seule valeur partout, remarque A29). `Start` : accumulateur Heartbeat. Sol de chaque acteur : `WorldLayout.supportY(root.Position)` (jamais un Blockcast). Chaque tick : `Activity.noteMove(player, pos validée, now)`. `PlayerRemoving` : `MoveCheck.clear(player)` (remarque A26).
- **Créatures** (identifiants 1-65535, recyclés après fin) :
  - fuite personnelle : toutes les `Balance.Runaway.Interval` s (50 avec Froggy) après la fin de la précédente, depuis la Fontaine du ranch (`SeededPath.hopAround`, 20 s) ; envoyée au seul propriétaire ; en pause pendant un Rush, un MEGA, son propre Grand Splorch, l'accueil (2:45 → 5:00) et quand enclos, Dodo et Lettres sont pleins. Contenu : `Odds.roll` (qualité de la Cuve, familles débloquées), taille `Formulas.babySize(SizeShare, MinSize, plus gros)`.
  - Golden Wobbler (`EventPhase("golden","spawn")`, `Features.GoldenWobbler`) : `SeededPath.golden`, 30 s, visible par tous ; premier qui l'attrape (hors recharge de 20 min : `golden.lastWinAt`) : Doré garanti, qualité 4, toutes familles, 25 % de son plus gros ; « de près » (30 studs) : 60 s de revenu et `Signals.NearCatch(joueur, "golden")` (la jauge vient du signal) ; personne : 30 s de revenu à ceux de près.
  - Wild Wobblers (`EventPhase("rush","start")`) : un personnel par joueur 15 s après le début (point de départ le plus proche), plus `RushRules.wildShared(N)` partagés par vagues de 15 s ; 2 partagés au plus par joueur et par Rush ; bébé de qualité 3, buses 0, 15 % du plus gros (min 5), +1 Fame du Rush (jauge : via `Caught`). Avec `BoopRush = "off"`, ils sortent quand même.
  - Fuites du Rush (`Signals.Booped`) : `SeededPath.escape(seed, now, WorldLayout.fountainNode(slot), angle)`, 25 s ; `SquishyService.setEscaping`. Le boopeur ne peut pas l'attraper avant 6 s. Fins (GDD v1.3 §4.21.3) : Héros (propriétaire : `SquishyService.growFor(owner, uid, Balance.RushSize.HeroGrowthSeconds)` = + 1 h de croissance une fois par squishy et par jour, 120 s de revenu, +2 Fame, vibration `catch`), bébé (autre joueur Rush : taille `RushRules.babySize` = min(10 % de l'original, 0,5 × son plus gros), minimum 1 ; mutation de l'original si son multiplicateur ≤ `Balance.Babies.RushMutationMaxMult` (Doré), sinon tirée avec des chances × `LuckyMutationMult` ; `consumeCap("rushBabies")`, sinon 60 s de revenu ; propriétaire : retour, +1 Fame, 60 s de revenu, vibration `squishyBack`), personne (`growFor(owner, uid, ReturnGrowthSeconds)` = + 30 min, même règle ; `squishyBack`). Joueurs Rush à 30 studs : 20 s de revenu et `Signals.NearCatch(joueur, "rush")` (jauge : via le signal). `Signals.EscapeEnded`, analytics `EscapeOutcome`. Propriétaire parti ou passé en Cozy : retour immédiat sans bonus.
  - Démonstration de Big Plop (`QuestService.script(player).demoAt`) : `SeededPath.demo`, 20 s, 8 studs/s, personnelle ; attrapée : bébé Plop (10 % de son Plop, min 10). Jamais rejouée (`onboarding.demoDone`).
- **Bond** (`Leap(dirX, dirZ, tClient)`) : `LeapRules.validDir`, recharge 4 s (horloge du serveur), pas de portage, `canAct` au départ ; `tClient` ramené dans [maintenant − `Balance.Catch.ClientPast` ; maintenant] ; `MoveCheck.grant(player, Balance.Leap.Distance, Balance.Leap.Duration, tClient)` : crédit de 12 studs sur 0,35 s, ajouté au plafond par tick, au budget d'action et à la fenêtre soutenue d'1 s, **rétroactif** jusqu'à 0,3 s avant la réception, refusé si le précédent date de moins de 4 s (§20 n° 14) ; atterrissage `LeapRules.landing(MoveCheck.positionAt(player, tClient), dir)` ; à `tClient + 0,35` : capture tentée (`LeapRules.catchesOnLanding` + tolérance) sur la créature visée la plus proche.
- **Capture** (`Catch(id, tClient)`) : mise en file, vérifiée au tick suivant (§6 étape 13), dans l'ordre d'arrivée, **à son instant** : `tClient` ramené dans [maintenant − 0,35 ; maintenant] ; `SeededPath.pos(tClient)` (exact, trajet déterministe) contre `MoveCheck.positionAt(player, tClient)` (historique interpolé de 0,5 s des positions acceptées, note INT-MOVE) ; distance **à plat** ≤ `Balance.Catch.Radius` (ou `OwnerRadius`) + `Tolerance` ; écart vertical `|ZoneRules.feetY(pos.Y, rootOffset) − sol de la créature| ≤ MaxDY` ; `canAct` ; règles de §4.21.4 pour les fuites du Rush (`RushRules.checkCatch`, `dy` mesuré depuis les pieds). Deux captures de la même créature : la première arrivée gagne. Effets (`Celebrate "catch"`, bulle-bébé) seulement après accord. `ChaseService.spec` : captures à 0, 100 et 250 ms de latence sur une créature qui fuit (≥ 95 % acceptées quand le client la voyait à ≤ 5 studs, aucune au-delà de 7) ; bond puis capture au tick suivant acceptée ; deux bonds à 2 s d'écart : le second est une rafale ; rafale de faux `Leap` : jamais plus de 12 studs par 4 s.
- **Anti-triche** : `"rewind"` → `PivotTo(back)`, attribut `Unstable` 3 s, `flags.strikes += 1` ; `MoveCheck.recentRewinds(player, now) ≥ Tuning.StrikesForBan` en 10 min → `flags.lbBanUntil` = fin de la semaine suivante (jamais à vie). Analytics `MoveViolation`.
- `openStates()` : « runaway », « escape », « wild », « golden », « demo » (créatures), « leap », « unstable ».
- Clés : `flags`, `golden`. Émet `MoveViolation`, `Caught`, `NearCatch`, `EscapeEnded`. Dépendances : tous les services précédents, `Util/MoveCheck`, `Logic/{SeededPath,LeapRules,RushRules,Odds,Formulas,WorldLayout,EventClock,StateTimeouts}`.

### 11.15 ProfileRepair (paquet ranch) — GDD §12.6

*Fichier : `src/server/Data/ProfileRepair.luau` (paquet ranch).*

```lua
ProfileRepair.repair(data: { [string]: any }): { string }  -- Répare en place ; rend la liste des champs réparés (vide = sain)
```

Pur. Appelé par `DataService` après `migrate` + `reconcile` (note INT-REPAIR). Chaque réparation est nommée (`"squishies.<uid>.z"`, `"dex.mut"`…) pour Diagnostics. Une vieille sauvegarde ou un bug passé ne peut jamais faire planter le chargement ni casser un invariant. Contrat v1.2 : `squishies[uid].gd` (entier ≥ 0, sinon 0) ; `dex.fam` (tableau dense de 0 / 1, allongé à `#Species.FamilyOrder`) ; `outfits.worn` vidé (la tenue portée vit dans `rec.o` ; tenues portées au-delà de `owned` retirées) ; `caps.petSitIn`, `caps.splorchCoins` (nombres), `caps.petSitBy` (dictionnaire de clés chaînes vers des entiers ≥ 0) ; `moon.lastSession` ; un tableau dense plus long que `Species.List` (espèces ajoutées, 64 dans le test) n'est **jamais** tronqué ; une clé `coinBuy` héritée est ignorée (ni lue ni effacée).

---

## 12. Modules partagés purs et rendu (API)

### 12.1 `Shared/Logic` (paquet logic)

Règles communes : **aucun service Roblox** (sauf `Vector3`, `CFrame`, `Vector2`, `Color3`, types de données) ; aucun état caché (sauf caches purs) ; déterministes ; toute entrée bizarre (`NaN`, ±inf, 1e308, −0, `nil` là où un nombre est attendu, chaîne vide) donne un résultat sûr, jamais une erreur ; même résultat côté serveur, client et simulation. Chaque module a sa spec de cas exacts (valeurs du GDD) **et** une spec de propriétés `Props_<Module>.spec.luau` (milliers d'entrées tirées avec une graine fixe, §17 couche a).

**Contrat v1.2 : changements à appliquer par logic** (paquet déjà écrit : notes du contrat, §25 ; les blocs ci-dessous décrivent la cible, les signatures nouvelles sont marquées « v1.2 ») :
- **Valeurs** de `Config/Balance` (GDD v1.3) : `Tiles.cozyBed.Base` 25e6 et `MinR` 3, `Splorch.Unlocks` (« pad.cozyBed » de [1] à [3]), `Splorch.Targets` (15 000, 39 000, 100 000, 260 000, 690 000, 1,8e6, 4,6e6, 12e6, 31e6, 81e6, 210e6, 550e6, 1,4e9, 3,7e9, 9,7e9, 25e9, 65e9, 170e9, 440e9, 1,1e12), `Splorch.BeyondMult` 2,6, `Offline.GrowthShare` 0,3, `Babies.MaxOfBiggest` 0,5, `Caps.petSit` 100, `Rewards.PetSitVisitor` 2, `Boosts.ObjectiveMedium` et `ObjectiveHard` 0 ; retrait de `Splorch.RecentBuyWindow`, `RecentBuyShare` et `CoinPacks` (autorisé) ; puis `Balance.GddValues = "1.3"` (témoins de `Contract_game`), porte `EconomyPacing` retenue et §21 tenu.
- **Formulas** : `tileCost` × `Tiles.RScale`^R (au lieu de 2^R) pour les dalles `ScaleWithR` ; `offlineGrowth(gNoBoost, seconds, R?, biggest?)` avec l'arrêt `StopAt` ; `babySize` borné à `MaxOfBiggest` (0,5) ; `splorchPreview` sans `recentBuy` ; `coinPack` retiré (plus de paquets) ; specs aux valeurs du GDD v1.3 (`splorchTarget(19) = 1,1e12`, `splorchTarget(20) = 2,9e12`, `tileCost("snack", 0, 1) = 70`, `tileCost("cozyBed", 0, 3) = 25e6`).
- **RushRules** : `babySize(original, receiverBiggest)` = min(10 % de l'original, 0,5 × plus gros du receveur), minimum 1 ; nouvelle `babyMutation(original, r, nozzles, moon)` ; `CatchCtx.dy` mesuré depuis les pieds.
- **ZoneRules** : nouvelles `distXZ(a, b)` et `feetY(rootY, rootOffset)` ; toutes les portées (`near`, `inMegaZone`, `streetSideOfFence`, `padStep`) à plat.
- **EventClock / MegaRules** : rotation du MEGA sur la liste des espèces **publiées** et non secrètes à t, triées par id, `(semaine + numéro du MEGA) mod #liste` (jamais mod 24 ; `Species.MegaRotation` obsolète).
- **QuestRules** : nouvelle `familyEarned(dex, family)` qui lit `dex.fam` (bonus pour toujours) ; les bonus de famille de `Formulas` / `EconomyModel` la lisent.
- **StateTimeouts** : `tileDwell` (0,6 + 0,5), `feedHold` (2 + 0,5), `splorchQueue` (480, coupure dure), `gaugeRest` (1 200).
- **BigNumber** : suffixes FR = EN (K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc) avec virgule et espace fine ; mots FR du GDD §4.2.
- **PressTiming** : `offset(ownerId, uid)` = hachage de l'UserId du propriétaire et de l'uid (confirmé) ; cas de spec +0,18 s après le sommet = PERFECT, +0,22 s non, −0,08 s PERFECT, −0,10 s non.
- **WorldLayout** : prises de dalles à Z = 67 (X −18, −6, 6, 18 ; 5e réservée (−28, 52)) ; décorations à ≥ 6 studs des prises ; règle de plan de `WorldLayout.spec` (centre d'une prise ≥ 8 studs du bol, de la Cuve, du Pot, du coussin, de la prise réservée et du bord du Bassin, prises à 12 studs l'une de l'autre).
- **Invariants** : tenues portées dérivées de `squishies[uid].o` (≤ `owned`), `outfits.worn` absent ou vide accepté, `dex.fam` dense, `caps.petSitBy` ≤ `CapsPerFriend.petSit`, `gd` entier ≥ 0.
- **FusionRules** : `fuse` garde le `gd` de l'uid gardé ; **SeededPath** : inchangé ; **EconomyModel** : porte refaite (§16).

#### Hash — reprise de Comet Conga

*Fichier : `src/shared/Logic/Hash.luau` (paquet logic).*

```lua
export type Stream = {
	next: (self: any) -> number,
	int: (self: any, min: number, max: number) -> number,
	range: (self: any, min: number, max: number) -> number,
}

Hash.u32(...: number): number  -- Hachage 32 bits (murmur3) de nombres entiers ou réels finis
Hash.unit(...: number): number  -- Réel déterministe dans [0 ; 1[
Hash.int(min: number, max: number, ...: number): number  -- Entier déterministe dans [min ; max]
Hash.range(min: number, max: number, ...: number): number  -- Réel déterministe dans [min ; max[
Hash.pickWeighted(weights: { number }, r: number): number  -- Index tiré dans des poids positifs avec r dans [0 ; 1[
Hash.string(s: string): number  -- Hachage 32 bits d'une chaîne (FNV-1a)
Hash.stream(seed: number): Stream  -- Flux pseudo-aléatoire déterministe (:next() dans [0 ; 1[, :int, :range)
Hash.alias(userId: number): number  -- Numéro d'alias à 4 chiffres [1000 ; 9999] d'un joueur au nom caché
```

Reprendre le module de Comet Conga (`/home/user/jules/roblox-game/src/shared/Logic/Hash.luau`) et ses valeurs de référence ; ajouter `alias`.

#### BigNumber — GDD §4.2

*Fichier : `src/shared/Logic/BigNumber.luau` (paquet logic).*

```lua
BigNumber.abbreviate(n: number, lang: string?): string  -- Forme courte du HUD, des étiquettes et des « +N »
BigNumber.full(n: number, lang: string?): string  -- Entier exact avec séparateurs sous 1e15, sinon abbreviate
BigNumber.words(n: number, lang: string?): (string, string)  -- (forme courte, mot entier « 7,80 billions ») pour la fiche
BigNumber.milestoneKey(n: number): string?  -- Clé « num.word.<p> » si n est un jalon de bannière (1e6, 1e9, 1e12, 1e15)
BigNumber.suffixes(lang: string?): { string }  -- Suffixes de la langue, du plus petit au plus grand
```

Exemples exigés (spec, GDD v1.3 : mêmes suffixes internationaux dans les deux langues) : 9 876 → EN « 9,876 », FR « 9 876 » (U+202F) ; 12 345 → « 12.3K » / « 12,3 K » ; 999 999 → « 999K » ; 4 560 000 000 → « 4.56B » / « 4,56 B » ; 7,8e12 → « 7.80T » / « 7,80 T » ; 1e36 → « 1.00e36 » / « 1,00e36 ». Mots entiers FR (fiche, info-bulle) : table du GDD §4.2 (« 7,80 T = 7 800 milliards ») ; bannières de jalons `num.word.<p>` (FR « 1 000 MILLIARDS »). Le zéro final après la virgule est gardé à 3 chiffres significatifs (« 7.80T »), contrairement à `Format.abbreviate` du socle.

#### SizeScale — GDD §4.2

*Fichier : `src/shared/Logic/SizeScale.luau` (paquet logic).*

```lua
export type Where = "pen" | "pool" | "ride" | "silhouette" | "statue" | "free"

SizeScale.scale(size: number): number  -- Échelle sans plafond (1× pour S ≤ 1 ; NaN → 1)
SizeScale.diameter(size: number): number  -- Diamètre du corps en studs, sans plafond
SizeScale.display(size: number, where: Where, saddle: number?): number  -- Échelle affichée selon le lieu (enclos 4×, monture fixée par la selle, silhouette et statue 19×)
SizeScale.overCap(size: number, where: Where): boolean  -- La taille dépasse le plafond du lieu (couronne de taille)
```

#### Formulas — GDD §4, §12.3

*Fichier : `src/shared/Logic/Formulas.luau` (paquet logic).*

```lua
export type GrowthCtx = {
	R: number,
	snack: number, -- niveau du Tapis à Goûter
	jellyFamily: boolean,
	boost: boolean, -- B = 2 (un seul ×2, jamais cumulé)
}

export type IncomeCtx = {
	decor: number, -- décorations construites
	friends: number, -- amis Roblox présents
	fame: number,
	trophyBonus: number, -- Formulas.trophyBonus
	goldenPages: number, -- pages dorées du Squishydex
	doubleCoins: boolean, -- P = 2
	boost: boolean, -- B = 2
}

export type VatLevel = { quality: number, speed: number, nozzles: number }

export type RideStats = { walkSpeed: number, jumpHeight: number, hipHeight: number, scale: number }

export type PreviewCtx = {
	now: number, -- Clock.now()
	unix: number, -- Clock.unix()
}

Formulas.clampCoins(x: number): number  -- NaN, ±inf ou négatif → 0 ; > Max → Max ; entier (floor) sous ExactBelow
Formulas.clampSize(x: number): number  -- Taille bornée à [1 ; Max] ; NaN → 1
Formulas.G(growth: Types.Growth, t: number): number  -- Croissance cumulée à l'instant t (t antérieur à growth.t → growth.G)
Formulas.sizeAt(rec: Types.SquishyRecord, G: number): number  -- Taille d'un squishy : z + (G − zg) en enclos ou Bassin, z ailleurs
Formulas.growthRate(ctx: GrowthCtx): number  -- g = Base × 2^R × (1 + niveauTapis) × (1 + 0,10 × Jelly) × B
Formulas.A(ctx: IncomeCtx): number  -- Multiplicateur additif A (décos, amis, Fame, Étagère, pages dorées)
Formulas.incomeFactor(species: number, mutation: number, stars: number, ctx: IncomeCtx): number  -- Revenu par unité de taille k = Coef × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B
Formulas.income(size: number, species: number, mutation: number, stars: number, ctx: IncomeCtx): number  -- Revenu par seconde d'un squishy d'enclos (k × taille)
Formulas.ranchIncome(squishies: { [string]: Types.SquishyRecord }, G: number, ctx: IncomeCtx): (number, number)  -- (K = Σ k, S1 = Σ k × (z − zg)) sur les squishies d'enclos et du Bassin ; revenu(t) = S1 + K × G(t)
Formulas.potGain(K: number, S1: number, growth: Types.Growth, t0: number, t1: number): number  -- Pièces gagnées entre t0 et t1 (intégrale exacte, g constant sur l'intervalle)
Formulas.pressReward(income: number, perfect: boolean, streak: number, kittyFamily: boolean): number  -- floor(max(Min, Seconds × revenu) × PERFECT × série × Kitty)
Formulas.tileCost(tile: string, level: number, R: number): number  -- Prix du prochain niveau : floor(Base × Growth^L × (ScaleWithR ? Tiles.RScale^R : 1)) (v1.2 : RScale au lieu de 2^R) ; math.huge si niveau maximal ou dalle inconnue
Formulas.penCapacity(pensLevel: number, bigRanch: boolean): number  -- Places d'enclos (Bassin compris) : 4 + niveau (+ 6), 24 au plus
Formulas.poolSlots(axoloFamily: boolean): number  -- Places d'attente du Bassin (5, ou 6 avec la famille Axolo)
Formulas.vatLevel(R: number): VatLevel  -- Qualité, vitesse et buses de la Cuve données par R
Formulas.vatInterval(R: number, bunnyFamily: boolean): number  -- Intervalle de la Cuve en secondes (90 × 0,85^vitesse, × 0,9 Bunny)
Formulas.fusionSize(a: number, b: number): number  -- (a + b) × 1,25, borné
Formulas.fusionStars(stars: number): number  -- min(5, étoiles + 1)
Formulas.bestMutation(m1: number, m2: number): number  -- Mutation au plus gros multiplicateur (0 si aucune)
Formulas.comboReward(step: number, income: number): number  -- Étape k : ComboSeconds × k × revenu du squishy obtenu
Formulas.sellValue(income: number): number  -- max(Min, floor(Seconds × revenu du squishy))
Formulas.secondsOfIncome(income: number, seconds: number, minimum: number?): number  -- Récompense « en secondes de revenu » (entier, ≥ minimum)
Formulas.splorchTarget(R: number): number  -- Objectif de taille pour passer de R à R + 1 (table, puis × 2,7 arrondi à 2 chiffres significatifs)
Formulas.offlineSeconds(nowUnix: number, lastOnline: number, cozyBed: boolean, spikyFamily: boolean): number  -- Absence comptée, bornée à la limite (8 h, 12 h Lit douillet, + 1 h Spiky) ; 0 au premier chargement
Formulas.offlineGrowth(gNoBoost: number, seconds: number, R: number?, biggest: number?): number  -- Croissance cumulée gagnée hors ligne : clamp(g × GrowthShare × s, 0, max(0, StopAt × splorchTarget(R) − biggest)) (v1.2 : R et biggest)
Formulas.offlinePot(incomeNoBoost: number, seconds: number): number  -- Pièces hors ligne versées au Pot (× PotShare)
Formulas.babySize(share: number, minimum: number, receiverBiggest: number, original: number?): number  -- Taille d'un bébé ou d'un cadeau : part (de l'original, sinon du plus gros du receveur), ≥ minimum, ≤ MaxOfBiggest (v1.3 : 0,5) × plus gros du receveur
Formulas.saddleLevel(biggestEver: number): number  -- Selle gagnée 0 … 3 (record ≥ 1 200, 1e6, 1e12)
Formulas.rideStats(saddle: number): RideStats  -- WalkSpeed, JumpHeight, HipHeight et échelle affichée de la monture
Formulas.trophyTier(record: number): number  -- Palier de l'Étagère 0 … 4 (bronze, argent, or, cristal)
Formulas.trophyBonus(trophies: { number }): number  -- Bonus additif de l'Étagère (somme des paliers, + 208 % au plus)
Formulas.coinPack(income: number, productKey: string): number  -- OBSOLÈTE (v1.2 : paquets de pièces retirés) ; logic le retire avec Balance.CoinPacks
Formulas.splorchPreview(data: { [string]: any }, ctx: PreviewCtx): Types.SplorchPreview  -- Aperçu du Grand Splorch à partir d'un profil (même calcul côté serveur et client)
```

Valeurs exigées (spec, valeurs du GDD v1.3 une fois `Balance.GddValues = "1.3"`) : Plop Commun de taille 1 000, 1 étoile, sans bonus = 30 pièces/s ; première pression = 10 ; coûts des dalles du GDD §4.6 (× 3,5^R pour la boucle) ; `splorchTarget(0) = 15 000`, `splorchTarget(19) = 1,1e12`, `splorchTarget(20) = 2,9e12` (1,1e12 × 2,6 = 2,86e12 arrondi à 2 chiffres significatifs) ; intervalles de la Cuve 55,3 s (R = 0) et 17,7 s (R ≥ 4) ; échelle 4,6× à 1 million. Propriété : `potGain` sur [t0, t2] = `potGain` sur [t0, t1] + [t1, t2] quand g ne change pas (à 1e-9 relatif près).

#### Odds — GDD §4.5, §4.9

*Fichier : `src/shared/Logic/Odds.luau` (paquet logic).*

```lua
export type RollCtx = {
	quality: number,
	nozzles: number,
	moon: boolean,
	unix: number, -- espèces publiées (Species.isReleased)
	families: { [string]: boolean }?, -- nil = toutes les familles (bébés, cadeaux)
	owned: { [number]: boolean }?, -- espèces tamponnées (nouveauté garantie)
	newPull: boolean?, -- ce tirage est « nouveauté garantie »
	pityRare: number?,
	pityEpic: number?,
	mutationMult: number?, -- MEGA, Goutte chanceuse : × 2
	forceMutation: number?, -- Golden Wobbler (Doré), Goutte de Lune (Lunaire)
	maxRarity: number?, -- plafond de rareté (cadeaux du Grand Splorch : Peu commun pour une espèce Épique+)
}

export type RollResult = {
	species: number,
	rarity: number,
	mutation: number,
	oneIn: number,
	pityRare: number, -- compteurs après ce tirage
	pityEpic: number,
	usedNewPull: boolean,
}

Odds.unlockedFamilies(R: number): { [string]: boolean }  -- Familles de la Cuve débloquées à ce R (Jelly, Kitty, Froggy ; Axolo R ≥ 1 ; Bunny R ≥ 3 ; Spiky R ≥ 5)
Odds.rarityTable(quality: number): { number }  -- Pourcentages par rareté (1 … 7) de la table de qualité
Odds.rollRarity(quality: number, r: number, pityRare: number, pityEpic: number): number  -- Rareté tirée avec r dans [0 ; 1[ et la protection contre la malchance
Odds.mutationChances(nozzles: number, moon: boolean, mult: number?): { [number]: number }  -- Chances effectives par mutation (fraction) : buses, Lune (× 2, Lunaire 3 %), multiplicateur (MEGA, Goutte chanceuse)
Odds.rollMutation(r: number, nozzles: number, moon: boolean, mult: number?): number  -- Mutation tirée (0 = aucune) : comparée aux chances cumulées depuis la plus rare
Odds.speciesFor(rarity: number, families: { [string]: boolean }?, owned: { [number]: boolean }?, preferNew: boolean, r: number, unix: number, moon: boolean): number  -- Espèce de la rareté (nil = toutes les familles) ; nouveauté garantie si preferNew et une espèce non possédée existe
Odds.roll(rng: Hash.Stream, ctx: RollCtx): RollResult  -- Naissance complète (rareté, espèce, mutation, « 1 sur X », compteurs de protection)
Odds.oneIn(rarity: number, mutation: number, quality: number, nozzles: number, moon: boolean): number  -- Étiquette « 1 sur X » d'une naissance, calculée aux réglages du moment (2 chiffres significatifs)
Odds.seed(userId: number, counter: number): number  -- Graine déterministe du tirage n° counter d'un joueur
```

Règles exactes : rareté par table de qualité ; protection (`pityRare ≥ 40` → au moins Rare ; `pityEpic ≥ 150` → au moins Épique) ; espèce à chances égales parmi les espèces **publiées** de la rareté dans les familles débloquées (si aucune : rareté juste en dessous, jusqu'à Commun) ; Secret → Royal Plop, pendant la Lune Royal ou Moonplop à chances égales ; nouveauté garantie : parmi les espèces non tamponnées de la rareté tirée s'il en reste ; mutation tirée avec un seul nombre, depuis la plus rare (`Mutations.DrawOrder`), Lunaire à part (3 % pendant la Lune). Propriétés : sur 1 million de tirages à graine fixe, chaque rareté et chaque mutation à ±3 écarts-types de la table affichée ; le « 1 sur X » est l'inverse exact du produit des chances.

#### FusionRules — GDD §4.10

*Fichier : `src/shared/Logic/FusionRules.luau` (paquet logic).*

```lua
FusionRules.areTwins(a: Types.SquishyRecord, b: Types.SquishyRecord): boolean  -- Même espèce et mêmes étoiles
FusionRules.fuse(a: Types.SquishyRecord, b: Types.SquishyRecord, G: number, unix: number): Types.SquishyRecord  -- Résultat de la fusion (nouvelle ligne, marque zg = G)
FusionRules.keepUid(uidA: string, uidB: string, a: Types.SquishyRecord, b: Types.SquishyRecord): string  -- uid gardé par le résultat (Meilleur Ami d'abord, puis le plus ancien)
FusionRules.nextInChain(pool: { [string]: Types.SquishyRecord }, resultUid: string): string?  -- Jumeau du résultat qui attend dans le Bassin (étape suivante du combo)
FusionRules.throwOutcome(pool: { [string]: Types.SquishyRecord }, rec: Types.SquishyRecord, slots: number): "fuse" | "place" | "full"  -- Effet d'un lancer dans le Bassin
FusionRules.twinPairs(records: { [string]: Types.SquishyRecord }): number  -- Nombre de paires de jumeaux (pastille « ♥ N »), hors Lettres et hors verrouillés
FusionRules.planMergeAll(records: { [string]: Types.SquishyRecord }, slots: number): { { string } }  -- Plan déterministe de « Tout fusionner » : liste ordonnée de paires { uidA, uidB } pour les plus longs combos, verrouillés exclus
```

#### RushRules — GDD §4.21.4

*Fichier : `src/shared/Logic/RushRules.luau` (paquet logic).*

```lua
export type BoopCtx = {
	feature: string, -- Features.BoopRush
	eventActive: boolean, -- Lune ou fête d'administrateur (mode "events")
	rushActive: boolean,
	booperRush: boolean,
	ownerRush: boolean,
	sameUser: boolean,
	ownerShield: boolean,
	refused: boolean, -- « Pas ce joueur »
	blocked: boolean, -- liste de blocage souple
	booperCooldownLeft: number,
	pairCooldownLeft: number,
	atFence: boolean,
	eligible: boolean, -- RushRules.fenceEligible avec le lieu ACTUEL (ni porté, ni Bassin, ni Dodo, ni en attente) ; faux → "notAtFence"
	bestFriend: boolean,
	rarity: number,
	moonBoopable: boolean,
	ranchThisRush: number,
	ranchThisHour: number,
	serverEscapes: number,
	distance: number, -- studs (position validée du boopeur → squishy à la clôture)
	canAct: boolean,
}

export type CatchCtx = {
	catcherRush: boolean,
	isBooper: boolean,
	age: number, -- s depuis le début de la fuite
	isOwner: boolean,
	distance: number,
	dy: number, -- écart vertical entre les PIEDS du joueur (ZoneRules.feetY) et le sol de la créature (v1.2)
	canAct: boolean,
}

export type FenceCtx = {
	now: number, -- Clock.unix()
	carried: string, -- uid porté ("" = aucun)
	waiting: string, -- uid en attente de Grand Splorch
	returnedThisRush: { [string]: boolean },
	moonBoopable: boolean,
}

RushRules.checkBoop(ctx: BoopCtx): (boolean, string?)  -- Ordre du GDD §4.21.4 ; (true) ou (false, code du premier refus)
RushRules.holdTime(ownerNear: boolean): number  -- 2,5 s, ou 5 s si le propriétaire est à 25 studs de sa clôture
RushRules.extendHold(endsAt: number, now: number): number  -- Le propriétaire arrive pendant le maintien : le temps restant double (une seule fois par maintien)
RushRules.checkCatch(ctx: CatchCtx): (boolean, string?)  -- Ordre de vérification d'une capture de fuite du Rush
RushRules.catchRadius(isOwner: boolean): number  -- Rayon serveur (5 + 1,5 ; 8 + 1,5 pour le propriétaire)
RushRules.fenceCount(boopedLastRush: boolean): number  -- Squishies curieux à la clôture (4, ou 2)
RushRules.fenceEligible(rec: Types.SquishyRecord, ctx: FenceCtx): boolean  -- Le squishy peut venir à la clôture (ni Meilleur Ami, ni porté, ni Bassin, ni Dodo, ni en attente, ni né il y a < 60 s, ni rentré ce Rush ; Mythique/Secret seulement pendant la Lune)
RushRules.wildShared(players: number): number  -- Wild Wobblers partagés : 3 + 2 × max(0, 6 − N)
RushRules.babySize(original: number, receiverBiggest: number): number  -- min(10 % de l'original, 0,5 × plus gros du receveur), minimum 1 (v1.3)
RushRules.babyMutation(original: number, r: number, nozzles: number, moon: boolean): number  -- v1.2 : mutation de l'original si son multiplicateur ≤ Babies.RushMutationMaxMult (Doré), sinon tirée (Odds.rollMutation) avec les chances × LuckyMutationMult
```

Codes de refus de `checkBoop` dans l'ordre du GDD : `feature`, `notRush`, `notRushMode`, `self`, `shieldOn`, `refused`, `blocked`, `cooldown`, `notAtFence` (`atFence` faux, puis `eligible` faux), `bestFriend`, `moonOnly`, `tooManyEscapes`, `tooFar` (ou `canAct`). Ceux qui sont montrés au joueur ont leur clé `feedback.<code>` ; les autres sont muets.

#### QuestRules — GDD §7.3, §7.4, §4.17

*Fichier : `src/shared/Logic/QuestRules.luau` (paquet logic).*

```lua
export type QuestCtx = {
	R: number,
	tilesLeft: number, -- achats de dalle encore possibles dans la boucle
	megaIn: number, -- s avant le prochain MEGA
	friendOnServer: boolean,
	splorchEta: number, -- s estimées jusqu'à l'objectif (taille qui manque ÷ croissance)
	stamps: number,
}

QuestRules.eligible(def: Quests.ObjectiveDef, ctx: QuestCtx): boolean  -- Règle « Proposé si » de l'objectif dans la situation du joueur
QuestRules.draw(userId: number, day: number, ctx: QuestCtx, firstDay: boolean): { number }  -- 3 objectifs (facile, moyen, difficile) ; jour 1 : Quests.ObjectiveRules.Day1
QuestRules.reroll(userId: number, day: number, current: { number }, slot: number, ctx: QuestCtx, salt: number): number  -- Nouvel objectif du même niveau pour cette case, différent des 3 actuels
QuestRules.apply(entry: Types.ObjectiveEntry, stat: string, amount: number, perfect: boolean?): Types.ObjectiveEntry  -- Progression d'un objectif par un événement (série PERFECT remise à 0 par une pression ratée)
QuestRules.rollover(list: { Types.ObjectiveEntry }, autoClaim: boolean): ({ Types.ObjectiveEntry }, { number })  -- Minuit en session : (liste gardée, ids terminés à réclamer d'office)
QuestRules.plopReward(days: number): Quests.PlopReward?  -- Palier de Nourrir Plop atteint à ce total de jours
QuestRules.dexMilestones(stamps: number, lastClaimed: number): { Quests.DexMilestone }  -- Jalons atteints et non réclamés
QuestRules.stampCount(dex: { [string]: any }): number  -- Tampons d'espèces + de mutations
QuestRules.starBadges(dex: { [string]: any }): number  -- Badges d'étoiles (★1 à ★5 par espèce)
QuestRules.familyComplete(dex: { [string]: any }, family: string): boolean  -- Les 4 espèces de la famille tamponnées (Secrets : jamais) : QuestService pose alors dex.fam[f] = 1
QuestRules.familyEarned(dex: { [string]: any }, family: string): boolean  -- v1.2 : bonus de la famille gagné pour toujours (dex.fam[index de Species.FamilyOrder] == 1) ; lu par les bonus de famille de l'économie
QuestRules.goldenPages(dex: { [string]: any }): number  -- Espèces dont les 8 mutations hors Lunaire sont trouvées
QuestRules.isNewStamp(dex: { [string]: any }, species: number, mutation: number, stars: number): boolean  -- La naissance remplit une entrée encore vide (espèce, mutation ou badge d'étoiles)
```

#### MegaRules — GDD §4.22

*Fichier : `src/shared/Logic/MegaRules.luau` (paquet logic).*

```lua
MegaRules.target(players: number, failStreak: number): number  -- ceil((30 + 50 × N) × indulgence)
MegaRules.leniency(failStreak: number): number  -- 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite
MegaRules.babiesFor(points: number): number  -- Paliers : ≥ 10 → 1 ; ≥ 40 → 2 ; ≥ 80 → 3
MegaRules.isPerfect(landsAt: number, t: number): boolean  -- Fenêtre [−0,12 ; +0,28] s autour du sommet (période 2 s)
MegaRules.species(week: number, indexInWeek: number, unix: number?): number  -- v1.2 : liste des espèces publiées (Species.isReleased à unix) et non secrètes, triées par id, indexée par (semaine + n) mod #liste (jamais mod 24)
```

#### EventClock — GDD §2.4, §12.4

*Fichier : `src/shared/Logic/EventClock.luau` (paquet logic).*

```lua
EventClock.rush(t: number): Types.RushPhase  -- Rush en cours ou prochain (index = numéro global du créneau)
EventClock.mega(t: number): Types.MegaPhase  -- MEGA en cours ou prochain (moon = MEGA MOON SQUISH)
EventClock.golden(t: number): Types.GoldenPhase  -- Golden Wobbler en cours ou prochain
EventClock.moon(t: number): Types.MoonPhase  -- Séance de Jelly Moon en cours ou prochaine (session 1-5 dans la semaine)
EventClock.nextEvent(t: number): Types.NextEvent  -- Prochain événement pour la pastille du HUD
EventClock.rushMoonBoopable(t: number): boolean  -- Rush de :05 ou :15 pendant une séance de Lune (Mythiques et Secrets boopables)
EventClock.megaSpecies(t: number): number  -- Espèce du géant (rotation du GDD §5.1 sur les espèces publiées et non secrètes à t, v1.2)
EventClock.seed(kind: string, index: number): number  -- Graine des trajets d'un événement (Hash)
EventClock.costume(unix: number): string  -- Costume de saison actif (Events.Costumes), "" sinon
```

#### WorldLayout — GDD §11

*Fichier : `src/shared/Logic/WorldLayout.luau` (paquet logic).*

```lua
export type Anchor = "pot" | "vat" | "pool" | "bowl" | "cushion" | "shelf" | "fountain" | "sign" | "silhouette" | "gate"
export type PlazaName = "center" | "megaPad" | "statue" | "shop" | "altar" | "gauge" | "stage" | "goldenFountain" | "boards"
export type Graph = { nodes: { Vector3 }, neighbors: { { number } } }
export type Box = { cframe: CFrame, size: Vector3 }

WorldLayout.ranchCFrame(slot: number): CFrame  -- Repère local du ranch (origine au portail, Z vers le fond, tourné vers la place)
WorldLayout.toWorld(slot: number, localPos: Vector3): Vector3  -- Point local → monde
WorldLayout.toLocal(slot: number, worldPos: Vector3): Vector3  -- Point monde → local
WorldLayout.ranchAt(pos: Vector3): number  -- Ranch dont le rectangle contient la position (0 = aucun)
WorldLayout.inRanch(slot: number, pos: Vector3): boolean  -- Position dans le rectangle de ce ranch
WorldLayout.gateOutside(slot: number): Vector3  -- Point de poussée d'un intrus : 6 studs devant le portail, côté rue
WorldLayout.spawnCFrame(slot: number): CFrame  -- Point d'apparition (Z = 30, X = 0) face au Pot
WorldLayout.anchor(slot: number, name: Anchor): Vector3  -- Position monde d'un objet du ranch (Pot, Cuve, Bassin, bol, coussin, étagère, Fontaine, panneau, silhouette)
WorldLayout.padSocket(slot: number, socket: number): Vector3  -- Centre monde d'une prise de dalle (1 … 4, Config/Pads)
WorldLayout.decorSlot(slot: number, index: number): CFrame  -- Emplacement de la décoration n° index (1 … 18)
WorldLayout.penSlot(slot: number, index: number): Vector3  -- Place n° index (1 … 24) dans la zone d'enclos
WorldLayout.poolSlot(slot: number, index: number): Vector3  -- Place flottante n° index (1 … 6) du Bassin
WorldLayout.fencePoint(slot: number, index: number): Vector3  -- Place n° index (1 … 4) à la clôture, côté rue (Rush, pet-sitting)
WorldLayout.plaza(name: PlazaName): Vector3  -- Position d'un objet de la place (MEGA pad, statue, boutique, autel, jarre, scène, fontaine dorée, tableaux)
WorldLayout.graph(): Graph  -- Graphe des rues (nœuds et voisins) utilisé par SeededPath
WorldLayout.nearestNode(pos: Vector3): number  -- Nœud du graphe le plus proche
WorldLayout.fountainNode(slot: number): number  -- Nœud du boulevard devant le portail du ranch (départ des fuites du Rush)
WorldLayout.wildSpawnNodes(): { number }  -- Points de départ des Wild Wobblers (fontaine de la place, bouts des rues radiales)
WorldLayout.solids(): { Box }  -- Boîtes solides (maisons et leur coiffe, clôtures et leurs murs invisibles, bord du plateau), ≥ Const.SolidMinHeight de haut
WorldLayout.groundY(x: number, z: number): number  -- Surface analytique du sol (MoveCheck.setSurface)
WorldLayout.supportY(pos: Vector3): number  -- Sol des règles du serveur : max(groundY, haut des solides dont l'emprise XZ contient pos) ; jamais de Blockcast
WorldLayout.meadowPoint(index: number): Vector3  -- Place n° index (1 … 12) dans la Prairie des copains
```

`WorldLayout.Const` porte les rayons du plan et les hauteurs des solides (`MaxReach` 22, `SolidMinHeight` 30, `FenceWallHeight`, `EdgeWallHeight`, `HouseCapHeight` 30 : §3.1). La géométrie exacte (prises de dalles, 18 emplacements de décoration, 24 places d'enclos, 6 places du Bassin, 4 places de clôture, Prairie) est décidée par logic, dans le repère du GDD §11.2 ; `WorldBuild.spec` (world) vérifie qu'aucune pièce ne chevauche une autre de façon interdite et que les solides correspondent aux boîtes.

#### SeededPath — GDD §12.5

*Fichier : `src/shared/Logic/SeededPath.luau` (paquet logic).*

```lua
-- pos(t) : position au sol et vrai si la créature est en l'air (bond, visuel seulement)
export type PathFn = (t: number) -> (Vector3, boolean)

SeededPath.escape(seed: number, t0: number, startNode: number, awayAngle: number, speed: number?): PathFn  -- Fuite du Rush, Wild Wobbler
SeededPath.hopAround(seed: number, t0: number, center: Vector3, radius: number): PathFn  -- Créature en fuite personnelle autour de sa Fontaine
SeededPath.golden(seed: number, t0: number, startNode: number): PathFn  -- Golden Wobbler (30 s)
SeededPath.demo(seed: number, t0: number, start: Vector3): PathFn  -- Démonstration de Big Plop (20 s)
SeededPath.fromSpawn(spawn: Types.ChaseSpawn): PathFn  -- Trajet d'une créature diffusée (dispatch selon kind et path)
```

#### PressTiming, ZoneRules, LeapRules, TargetRules — GDD §4.7, §4.6, §4.12, §10.4

*Fichier : `src/shared/Logic/PressTiming.luau` (paquet logic).*

```lua
PressTiming.offset(ownerId: number, uid: string): number  -- Décalage du rebond dans [0 ; Period[
PressTiming.phase(t: number, offset: number): number  -- Phase dans [0 ; 1[ (0 = sommet)
PressTiming.isPerfect(t: number, offset: number): boolean  -- t est dans la fenêtre PERFECT
PressTiming.nextApex(t: number, offset: number): number  -- Instant du prochain sommet (anneau qui se resserre)
PressTiming.clampClientTime(tClient: number, now: number): number  -- tClient s'il est fini et dans [now − 0,35 ; now + 0,05], sinon now
```

*Fichier : `src/shared/Logic/ZoneRules.luau` (paquet logic).*

```lua
ZoneRules.padStep(wasInside: boolean, distance: number): (boolean, boolean)  -- (dedans, vient d'entrer) avec l'hystérésis 2,5 / 3,5 (distance à plat)
ZoneRules.distXZ(a: Vector3, b: Vector3): number  -- v1.2 : distance à plat (XZ) de toutes les portées du serveur
ZoneRules.feetY(rootY: number, rootOffset: number): number  -- v1.2 : altitude des pieds = rootY − hauteur debout (MoveCheck) − hausse de la monture
ZoneRules.near(slot: number, anchor: string, pos: Vector3, radius: number): boolean  -- Position à radius studs d'un objet du ranch (WorldLayout.anchor)
ZoneRules.inMegaZone(pos: Vector3): boolean  -- À 20 studs du centre du MEGA pad
ZoneRules.streetSideOfFence(slot: number, pos: Vector3, radius: number): boolean  -- Côté rue de la clôture du ranch, à radius studs d'une place de clôture
ZoneRules.ownerNearFence(slot: number, pos: Vector3): boolean  -- Propriétaire à 25 studs de sa clôture (boop plus long)
ZoneRules.intruder(ownerSlot: number, pos: Vector3): number  -- Ranch d'un autre où se trouve cette position (0 = aucun)
ZoneRules.atAltar(pos: Vector3): boolean  -- Présence à l'Autel de la Lune
```

*Fichier : `src/shared/Logic/LeapRules.luau` (paquet logic).*

```lua
export type AimCandidate = { id: number, posAt: (t: number) -> Vector3 }

LeapRules.validDir(dirX: number, dirZ: number): Vector3?  -- Direction normalisée si les composantes sont finies et la norme dans [0,5 ; 1,5]
LeapRules.landing(from: Vector3, dir: Vector3): Vector3  -- Point d'atterrissage (raccourci devant le premier solide)
LeapRules.arc(from: Vector3, to: Vector3, alpha: number): Vector3  -- Point de l'arc à alpha dans [0 ; 1] (sommet 2,5 studs)
LeapRules.aim(origin: Vector3, stick: Vector3, candidates: { AimCandidate }, now: number, current: number?): number?  -- Créature visée (id) ou nil (bond droit devant)
LeapRules.catchesOnLanding(landing: Vector3, creaturePos: Vector3, isOwner: boolean): boolean  -- Capture automatique (5 studs, 8 pour le propriétaire de sa fuite du Rush ; + tolérance côté serveur)
```

*Fichier : `src/shared/Logic/TargetRules.luau` (paquet logic).*

```lua
export type Candidate = { id: string, pos: Vector3, ready: boolean }
export type Projected = { id: string, screen: Vector2, radius: number, depth: number }

TargetRules.score(origin: Vector3, look: Vector3, pos: Vector3): number  -- Score d'un candidat (plus petit = meilleur)
TargetRules.pick(origin: Vector3, look: Vector3, candidates: { Candidate }, current: string?, now: number, since: number): string?  -- Cible retenue (id)
TargetRules.cycle(origin: Vector3, look: Vector3, candidates: { Candidate }, current: string?, dir: number): string?  -- Cible suivante (dir = 1) ou précédente (−1) par angle, de gauche à droite
TargetRules.afterPress(origin: Vector3, look: Vector3, candidates: { Candidate }, pressed: string): string?  -- Prochain squishy prêt après une pression
TargetRules.screenPick(pointer: Vector2, projected: { Projected }, scale: number): string?  -- Candidat désigné par la souris (projection écran, jamais un rayon)
```

#### StateTimeouts, DiagRules, Invariants — GDD §12.10, §12.11

*Fichier : `src/shared/Logic/StateTimeouts.luau` (paquet logic).*

```lua
StateTimeouts.seconds(state: string): number  -- Délai de l'état (s) ; erreur claire pour un état inconnu
StateTimeouts.deadline(state: string, startedAt: number, extra: number?): number  -- Échéance = début + délai (+ extra)
StateTimeouts.expired(state: string, startedAt: number, now: number, extra: number?): boolean  -- L'état a dépassé son délai
StateTimeouts.names(): { string }  -- Liste des états connus (tests : chaque état a un test de délai)
```

`StateTimeouts.Table` (données du contrat dans le stub) : en plus des états du GDD §12.10, `playerReady` (15 s : PlayerReady émis même si le placement échoue), `serverFull` (30 s : renvoi), `worldResync` (3 s : `RequestWorld` renvoyé par le client), `unstable` (3 s : attribut), `clip` (8 s : capture vidéo arrêtée). `boopHold` (5,5 s) suppose `extendHold` une seule fois par maintien. Contrat v1.2 (note logic) : `tileDwell` (1,1 s : 0,6 + 0,5), `feedHold` (2,5 s), `splorchQueue` (480 s : coupure dure de l'attente dynamique), `gaugeRest` (1 200 s).

*Fichier : `src/shared/Logic/DiagRules.luau` (paquet logic).*

```lua
DiagRules.normalize(text: string, names: { string }?): string  -- Texte normalisé (aucun nom, aucun nombre)
DiagRules.truncate(s: string, max: number): string  -- Coupe sans casser un caractère UTF-8 ; remplace l'UTF-8 invalide
DiagRules.validUtf8(s: string): boolean  -- Chaîne UTF-8 valide
DiagRules.key(normalized: string, source: string): string  -- Clé courte (8 caractères hexadécimaux)
DiagRules.context(fields: { [string]: any }): string  -- Contexte compact (appareil, entrée, résolution, langue, version, étape, fenêtre, événement), ≤ 120
DiagRules.mergeDaily(current: { [string]: any }?, entries: { Types.DiagEntry }): { [string]: any }  -- Totaux du jour fusionnés, bornés (transformation d'UpdateAsync)
```

*Fichier : `src/shared/Logic/Invariants.luau` (paquet logic).*

```lua
Invariants.profile(data: { [string]: any }): { string }  -- Pièces, Pot, Fame, tailles finies et bornées ; places ≤ capacités (24 / 60 / 20) ; un squishy par emplacement de Meilleur Ami ; tenues portées par des uid existants ; tableaux denses ; niveaux bornés
Invariants.number(x: any, min: number, max: number): boolean  -- Nombre fini dans [min ; max]
Invariants.dense(t: any): boolean  -- Tableau séquentiel sans trou
Invariants.uid(x: any): boolean  -- uid valide (base 36, 1 à 8 caractères)
```

### 12.2 `Shared/Render` (paquet world)

*Fichier : `src/shared/Render/SquishyBuilder.luau` (paquet world).*

```lua
export type BuildSpec = {
	species: number,
	mutation: number,
	stars: number,
	displayScale: number,
	lod: number,
	outfit: string?,
	saddle: string?, -- couleur de selle (monture)
	rarityAura: boolean?, -- aura de rareté visible
}

export type Handle = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
	spec: BuildSpec,
	lod: number,
}

export type Attachments = { saddle: CFrame, outfit: CFrame, head: CFrame }

SquishyBuilder.build(spec: BuildSpec, parent: Instance?): Handle  -- Construit (ou reprend dans la réserve) un modèle
SquishyBuilder.setLod(handle: Handle, lod: number)  -- Niveau de détail 1 (complet), 2 (corps + yeux), 3 (corps seul)
SquishyBuilder.setScale(handle: Handle, displayScale: number)  -- Échelle affichée (SizeScale.display)
SquishyBuilder.setSquash(handle: Handle, sx: number, sy: number, sz: number)  -- Écrasement du corps (une écriture de Size), volume à peu près gardé
SquishyBuilder.pose(handle: Handle, cframe: CFrame): ({ BasePart }, { CFrame })  -- Pièces et CFrames à passer à workspace:BulkMoveTo pour ce modèle
SquishyBuilder.setMutation(handle: Handle, mutation: number, reducedMotion: boolean)  -- Aspect de mutation (rendu fixe en Mouvement réduit)
SquishyBuilder.setStars(handle: Handle, stars: number)  -- Arc d'étoiles (BillboardGui sous 60 studs)
SquishyBuilder.attachments(handle: Handle): Attachments  -- Points d'attache (selle, tenue, tête) en repère du modèle
SquishyBuilder.release(handle: Handle)  -- Rend le modèle à la réserve
SquishyBuilder.partCount(spec: BuildSpec): number  -- Nombre de pièces du modèle (≤ 12 en complet ; specs de budget)
SquishyBuilder.recipe(species: number): { [string]: any }  -- Recette pure (pièces, couleurs, tailles) d'une espèce, sans instance (tests)
```

- Recettes : une ligne de `Config/Species` + mutation + étoiles + échelle → pièces (GDD §5.2) : corps Ball (X / Y / Z de la ligne, `SmoothPlastic`), ventre / motif (1 à 4 pièces), yeux (2, ou 3 pour Moonplop ; noirs, `Reflectance` 0,3, reflet blanc), joues, bouche (3 petites Balls), haut de tête (1 à 3 pièces), étoiles (BillboardGui sous 60 studs), aura de rareté (forme de `Config/Rarities`), aspect de mutation (`Config/Mutations.look`). **12 pièces au plus** en détail complet.
- Toutes les pièces : `Anchored = true`, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false`. Transparence seulement pour la mutation Gelée.
- `setSquash` n'écrit que `body.Size` ; les autres pièces suivent par `pose` + `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` (une fois par image pour tous les squishies, par le renderer).
- Réserve : `release` remet le modèle dans une réserve par espèce ; `build` en reprend un (aucune création en rafale).

*Fichier : `src/shared/Render/Squash.luau` (paquet world).*

```lua
Squash.sample(profile: string, t: number, amplitude: number?): (number, number, number, boolean)  -- (sx, sy, sz, fini) du profil à t secondes
Squash.idle(t: number, offset: number, wobbleHz: number, wobbleAmp: number): (number, number, number, number)  -- (sx, sy, sz, hauteur en × diamètre) de l'animation de repos
Squash.duration(profile: string): number  -- Durée d'un profil (s)
```

*Fichier : `src/shared/Render/Palette.luau` (paquet world).*

```lua
export type Preset = {
	clockTime: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	tint: Color3,
	atmosphereColor: Color3,
	bloom: number,
	starCount: number,
	moonSize: number,
}

Palette.preset(name: string): Preset  -- Préréglage d'éclairage ("day", "rush", "moon", "party", "winter")
Palette.blend(a: Preset, b: Preset, alpha: number): Preset  -- Mélange de deux préréglages (teinte à 30 % pour un nouveau)
```

---

## 13. Client : ordre, propriétaires des remotes, API des contrôleurs et de l'interface

### 13.1 Ordre d'initialisation (`Main.client.luau`)

Pour chaque module de la liste : `require` puis `attach()` s'il existe (ErrorReporter seulement) ; ensuite `Init()` de tous, puis `Start()` de tous ; chaque appel isolé par `xpcall`. ClientReady est posé par le HUD (et, en filet, dès l'instantané du profil).

| Rang | Module | Paquet | Rôle |
|---|---|---|---|
| 1 | `Controllers/ErrorReporter` | meta | erreurs du client (attach au plus tôt ; contexte lu à l'envoi) |
| 2-6 | `Util/Platform`, `UI/Root`, `Controllers/StateController`, `Controllers/AudioController`, `Util/Prefs` | socle | couche console, écrans, miroir du profil, sons, réglages |
| 7 | `Controllers/WorldStateController` | client-world | miroir du monde |
| 8 | `Controllers/QualityController` | client-world | qualité adaptative |
| 9 | `Controllers/LightingController` | world | éclairage |
| 10 | `Controllers/RanchRenderer` | client-world | ranchs, squishies, place |
| 11 | `Controllers/ChaseRenderer` | client-world | créatures |
| 12 | `Controllers/VFXController` | client-world | effets |
| 13 | `Controllers/CameraController` | client-world | travelling du Grand Splorch |
| 14 | `Controllers/PromptController` | client-world | cible choisie par le jeu |
| 15 | `Controllers/ChaseController` | client-world | bond et capture |
| 16 | `UI/FocusGuard` | client-panels | sélection jamais perdue |
| 17 | `UI/Cards` | client-hud | cartes et leur file |
| 18 | `UI/PanelController` | client-panels | menu et panneaux (charge `UI/Panels/*`) |
| 19 | `UI/ReturnScreen` | client-panels | écran de retour |
| 20 | `UI/HUD` | client-hud | HUD télé |
| 21 | `UI/Banners` | client-hud | bannières |
| 22 | `UI/ScreenFX` | client-hud | effets d'écran |
| 23 | `UI/Prompt` | client-hud | invites dans le monde |
| 24 | `Controllers/InputController` | client-hud | commandes |
| 25 | `Controllers/OnboardingController` | client-hud | accueil |

Un module n'appelle directement que ceux d'avant ; vers le haut, il écoute leurs signaux. Exemples : `InputController` appelle `PromptController.current`, `ChaseController.leap`, `PanelController.toggleMenu`, `HUD.clapHero` ; `HUD` appelle `PanelController.toggleMenu` (clic sur la puce) ; `OnboardingController` appelle `HUD.reveal`, `HUD.setHint`, `LightingController.setQuiet`, `Banners.setQuiet`. **Vers le haut** : `Cards` (17) n'appelle jamais `PanelController` (18) ; il émet `Cards.Requested(sorte, action)`, que PanelController écoute (ouvrir Objectifs, Squishydex…). Un panneau n'appelle jamais `PanelController` (require circulaire : PanelController les charge) ; il reçoit un navigateur par `setNavigator(nav)` avant `build` (`nav.open(panneau, onglet?)`, `nav.back()`).

| Module | Appelle directement (rangs précédents, socle compris) | Remotes écoutés → envoyés | GDD |
|---|---|---|---|
| ErrorReporter | `Logic/DiagRules` ; contexte lu dans les services du moteur (`GuiService`, `UserInputService`, `LocaleId`, `Stats`) et poussé par les autres (`noteContext`), jamais en appelant un module plus tardif ; interrupteur `diagnostics` lu dans le dernier `EventState` (écouté directement sur le remote, jamais `Config/Features`) | `EventState` (interrupteur), `Celebrate` (`testError`) → `ReportError`, `SetInputType` | §12.11 |
| WorldStateController | StateController, `Logic/{SeededPath,EventClock,Formulas}` | `RanchSnapshot`, `RanchPatch`, `Fence`, `ChaseEvent`, `EventState`, `MegaBeat`, `BoopState`, `EmoteShow` → `RequestWorld`, `ReportBlocked` (une fois au `Start`, `StarterGui:GetCore("GetBlockedUserIds")` sous `pcall`) | §12.5 |
| QualityController | Prefs | → `ClientEvent("qualityReduced")` | §12.9 |
| LightingController | WorldStateController, QualityController, Prefs, `Render/Palette` | — | §11.3 |
| RanchRenderer | WorldStateController, QualityController, StateController, Prefs, `UI/WorldText` (étiquettes des dalles ≤ 20 studs, glyphe de la leçon au-dessus de l'objet), `Render/{SquishyBuilder,Squash}`, `Logic/{SizeScale,WorldLayout,PressTiming,TargetRules}` | `LeaderboardState` | §5.2, §6.6, §9.3, §11.2 |
| ChaseRenderer | WorldStateController, QualityController, AudioController, `Render/*`, `Logic/SeededPath` | — | §9.4 |
| VFXController | WorldStateController, RanchRenderer, ChaseRenderer, QualityController, Prefs, AudioController, Haptics, Juice, `UI/WorldText` (« +N ») ; `CaptureService`, `PolicyService` (sous `pcall`) | `Celebrate` | §9, §9.5 |
| CameraController | WorldStateController, Prefs | `Celebrate` (`splorch`) | §9.4, §10.4 |
| PromptController | WorldStateController, StateController, RanchRenderer, ChaseRenderer, `Logic/{TargetRules,LeapRules,ZoneRules,WorldLayout}` | — | §10.4 |
| ChaseController | WorldStateController, PromptController, AudioController, `Logic/{LeapRules,WorldLayout}` | → `Leap`, `Catch` | §4.12 |
| FocusGuard | Root, AudioController, ErrorReporter (`report` des sauvetages) | — | §10.6 |
| Cards | FocusGuard, Root, Prefs, Haptics, AudioController | `ModePrompt`, `Celebrate` → `SetMode`, `RefuseBooper`, `UiSeen` ; émet `Requested` | §10.3, §4.21.1 |
| PanelController | FocusGuard, Cards (`Requested`, `pending`), StateController, Prefs, AudioController, Haptics, `UI/Panels/*` (+ `setNavigator`) | (par les panneaux) | §10.3-§10.6 |
| ReturnScreen | FocusGuard, Cards, Prefs, `Render/SquishyBuilder` | `Celebrate` (`return`) | §7.2 |
| HUD | StateController, WorldStateController, PromptController, ChaseController, Cards, PanelController, Prefs, Glyph, Toast, Juice, `Logic/{BigNumber,Formulas}` | `Feedback`, `ClapPrompt`, `Celebrate` → `Clap` (clic) | §10.2 |
| Banners | WorldStateController, Prefs | `Banner` | §6.6 |
| ScreenFX | WorldStateController, Prefs, Root | — | §9.2, §9.4 |
| Prompt | PromptController, FocusGuard, WorldStateController, Glyph, Root, `UI/WorldText` (plaques bornées à la zone sûre) | `HoldState` (bol et dalle) | §10.2, §10.4 |
| InputController | Platform, PromptController, ChaseController, FocusGuard, Cards, PanelController, HUD (`clapHero`) | → `Press`, `PickUp`, `PutDown`, `Throw`, `BuyTile`, `BoopHold`, `FeedPlop`, `MegaPress`, `PetPress`, `Ride`, `Emote`, `Clap` ; **seul** à lier △ / croix ↓ / M (jamais Tab) et les raccourcis G C J L B P | §10.4 |
| OnboardingController | StateController, LightingController, PromptController, HUD, Banners | `Celebrate` (`onboarding`) | §3 |

Les panneaux (`UI/Panels/*`) appellent ce qui est chargé avant PanelController et envoient les intentions de leurs boutons (`BuyTile`, `FuseMenu`, `FuseAll`, `MoveSquishy`, `ClaimMail`, `Sell`, `Release`, `SetLock`, `SetBestFriend`, `SetMount`, `EquipOutfit`, `GrandSplorch`, `ClaimObjective`, `RerollObjective`, `ClaimDexReward`, `SetSetting`, `SetMode`, `EquipCosmetic`, `RequestDiagnostics`, `AdminCommand` (onglet Outils, administrateurs), `UiSeen` (écran ouvert)). Les modules purs de `Shared/Logic` ne dépendent que de `Shared/Config` et de `Logic/Hash` ; `Shared/Render` dépend de `Shared/Config` et de `Logic/SizeScale`.

### 13.2 Propriétaires des remotes côté client

| Remote | Écouté par |
|---|---|
| `DataSnapshot`, `DataPatch` | StateController (socle) ; les autres lisent `StateController.get / observe` |
| `RanchSnapshot`, `RanchPatch`, `Fence`, `ChaseEvent`, `EventState`, `MegaBeat`, `BoopState`, `EmoteShow` | WorldStateController (qui ré-émet ses signaux) |
| `Celebrate` | VFXController, HUD, Cards, ReturnScreen, OnboardingController, CameraController, ErrorReporter (`testError`) (chacun ne traite que ses sortes, §10.3) |
| `EventState` | WorldStateController (miroir) ; ErrorReporter lit seulement l'interrupteur `diagnostics` (premier module : il ne peut pas appeler WorldStateController) |
| `Feedback` | HUD (via `UI/Toast`, file du message central) |
| `Banner` | Banners |
| `ModePrompt` | Cards (carte bloquante du choix) |
| `HoldState` | Prompt (anneau du bol) |
| `ClapPrompt` | HUD (puce APPLAUDIR) |
| `LeaderboardState` | Panels/Leaderboards, RanchRenderer (tableaux de la place) |
| `DiagnosticsSnapshot` | Panels/Diagnostics (`tab = 0` : « bonjour » qui rend le panneau visible) |

Envoyés par le client : intentions de §10.1 (par le module qui porte le geste : InputController pour □ / ○ et les emotes, ChaseController pour `Leap` / `Catch` (avec `tClient`), les panneaux pour leurs boutons et `UiSeen` à l'ouverture, Cards pour `SetMode` / `RefuseBooper` / `UiSeen` (carte affichée), ErrorReporter pour `ReportError` / `SetInputType`, WorldStateController pour `RequestWorld` et `ReportBlocked` (une fois, remarque A21), QualityController pour `ClientEvent("qualityReduced")`, Panels/Shop pour `ClientEvent("shopOpened")`, Panels/Diagnostics pour `AdminCommand`).

### 13.3 Contrôleurs du monde (paquet client-world)

*Fichier : `src/client/Controllers/WorldStateController.luau` (paquet client-world).*

```lua
WorldStateController.RanchChanged: Signal.Signal<number, { string }>  -- (slot, champs changés)
WorldStateController.SquishyChanged: Signal.Signal<number, string, string>  -- (slot, uid, op)
WorldStateController.FenceChanged: Signal.Signal<number>  -- (slot)
WorldStateController.CreatureSpawned: Signal.Signal<Types.ChaseSpawn>
WorldStateController.CreatureFinished: Signal.Signal<Types.ChaseFinish>
WorldStateController.EventChanged: Signal.Signal<Types.EventStatePayload>
WorldStateController.MegaBeat: Signal.Signal<Types.MegaBeatPayload>
WorldStateController.BoopChanged: Signal.Signal<Types.BoopStatePayload>
WorldStateController.EmoteShown: Signal.Signal<Types.EmoteShowPayload>
WorldStateController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
WorldStateController.Start()  -- Connexions et boucles (stub : ne fait rien)
WorldStateController.ready(): boolean  -- Premier RanchSnapshot reçu
WorldStateController.mySlot(): number  -- Ranch du joueur local
WorldStateController.ranch(slot: number): Types.RanchPublic?  -- État public d'un ranch
WorldStateController.squishies(slot: number): { [string]: Types.PublicSquishy }  -- Squishies visibles d'un ranch
WorldStateController.sizeOf(slot: number, uid: string, t: number?): number  -- Taille prédite (z + G(t) − zg)
WorldStateController.fence(slot: number): ({ string }, string)  -- Clôture d'un ranch (uids, raison)
WorldStateController.creatures(): { [number]: Types.ChaseSpawn }  -- Créatures actives visibles par ce joueur
WorldStateController.creaturePos(id: number, t: number?): Vector3?  -- Position d'une créature (SeededPath)
WorldStateController.event(): Types.EventStatePayload?  -- Dernier EventState
WorldStateController.boops(): { [string]: Types.BoopStatePayload }  -- Maintiens de boop en cours (clé « booperId:ownerId:uid »)
```

*Fichier : `src/client/Controllers/QualityController.luau` (paquet client-world).*

```lua
export type Budgets = {
	lodScale: number, -- distances de détail × 1 ou × 0,6
	animated: number, -- squishies animés à pleine cadence (80 ou 40)
	particles: number, -- facteur de particules (1 ou 0,3)
	highlights: number, -- Highlight au plus (12, ou 7 : cible + 6 fuites)
	lightRange: number, -- studs au-delà desquels les lumières sont coupées (math.huge ou 60)
	blur: boolean,
	particleQuota: { vfx: number, chase: number, lighting: number }, -- v1.2 : 120 / 50 / 30 (× 0,3 en qualité réduite)
	highlightQuota: { target: number, chase: number, ranch: number }, -- v1.2 : 1 / 7 / 3 (+ 1 de réserve ; réduite : 1 / 6 / 0)
	lightQuota: { world: number, ranch: number, squishies: number }, -- v1.2 : 16 / 4 / 4
}

QualityController.Changed: Signal.Signal<boolean>  -- (reduced)
QualityController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
QualityController.Start()  -- Connexions et boucles (stub : ne fait rien)
QualityController.reduced(): boolean  -- Qualité réduite en vigueur
QualityController.budgets(): Budgets  -- Budgets du moment pour les rendus et les effets
```

- **Budgets partagés** (remarque A23) : chaque ressource partagée a un quota par module, jamais « tout le budget pour moi » : particules ≤ 200 (VFXController 120, ChaseRenderer 50, LightingController 30 dont les flocons d'hiver) ; `Highlight` ≤ 12 (cible 1, ChaseRenderer 7 = 6 fuites du Rush + Golden, RanchRenderer 3 = Mythiques et Secrets les plus proches, réserve 1) ; lumières ≤ 24 (monde 16, ranch local 4, Légendaires+ 4). Le `stats()` de chaque module reste dans son quota, vérifié par sa spec. Descente de qualité : `ClientEvent("qualityReduced")` (analytique `QualityReduced`).

*Fichier : `src/client/Controllers/RanchRenderer.luau` (paquet client-world).*

```lua
RanchRenderer.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
RanchRenderer.Start()  -- Connexions et boucles (stub : ne fait rien)
RanchRenderer.positionOf(slot: number, uid: string): Vector3?  -- Position dessinée d'un squishy (cible, effets)
RanchRenderer.play(slot: number, uid: string, profile: string)  -- Joue un profil d'écrasement (Render/Squash) sur un squishy
RanchRenderer.pulseTwins(uid: string)  -- Fait pulser 1 s les cœurs des jumeaux d'un squishy du ranch local
RanchRenderer.projected(camera: Camera): { TargetRules.Projected }  -- Squishies candidats projetés à l'écran (clic souris)
RanchRenderer.stats(): { [string]: number }  -- Compteurs de budget (modèles, pièces, animés) pour les specs
```

- Étiquettes de prix des dalles (≤ 20 studs) et glyphe de la leçon de l'accueil au-dessus de l'objet : `UI/WorldText` (jamais un texte au sol ni en studs). `RanchPublic.best` avec `s = 0` : aucune silhouette. Bulle « Boîte à dodo ! » (`world.vat.dodo`) sur la Cuve quand une naissance va au Dodo (`Celebrate "hatch"`, `at = "dodo"`).
- Détail : < 60 studs complet et animé à chaque image ; 60-140 studs corps + yeux à 15 Hz ; > 140 studs corps seul immobile ; ranch à > 220 studs : silhouette du meilleur et compteur « ×N » ; distances × `QualityController.budgets().lodScale`. Au plus `budgets().animated` squishies animés à pleine cadence. Tailles : `WorldStateController.sizeOf` puis `SizeScale.display` (enclos plafonné à 4×, couronne de taille au-delà).
- Le squishy porté et la monture sont dessinés sur le personnage (aucune soudure physique) ; un personnage `nil` ou en réapparition n'affiche rien et ne lève rien.
- **Cosmétiques publics** (champs de `RanchPublic`) : RanchRenderer dessine la couleur de selle (`saddleColor`) et la traînée (`trail`) sur la monture, le thème (`theme`) et le drapeau (`flag`) sur le ranch, et le **titre** (`title`) dans un `BillboardGui` au-dessus de la tête de chaque joueur (visible à ≤ 150 studs, texte ≥ 28 px TV, `MaxDistance`, alias si le nom est caché). `RanchRenderer.spec` : chaque champ dessiné, titre absent au-delà de 150 studs, personnage `nil` toléré.

*Fichier : `src/client/Controllers/ChaseRenderer.luau` (paquet client-world).*

```lua
ChaseRenderer.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ChaseRenderer.Start()  -- Connexions et boucles (stub : ne fait rien)
ChaseRenderer.positionOf(id: number): Vector3?  -- Position dessinée d'une créature
ChaseRenderer.stats(): { [string]: number }  -- Compteurs de budget (créatures, Highlight, particules)
```

*Fichier : `src/client/Controllers/VFXController.luau` (paquet client-world).*

```lua
VFXController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
VFXController.Start()  -- Connexions et boucles (stub : ne fait rien)
VFXController.floatText(pos: Vector3, text: string, color: Color3?, scale: number?)  -- Texte qui monte (« +1,2K »)
VFXController.stamp(key: string, vars: { [string]: any }?, color: Color3?)  -- Grand tampon à l'écran (« PERFECT ! », « COMBO x5 ! »)
VFXController.flyCoins(from: Vector3, count: number)  -- Pièces qui volent vers le compteur
VFXController.ring(pos: Vector3, color: Color3, diameter: number, duration: number)  -- Anneau Neon qui s'élargit
VFXController.burst(pos: Vector3, color: Color3, count: number)  -- Gerbe de particules (bornée par le budget)
VFXController.blobs(pos: Vector3, color: Color3, count: number)  -- Gouttes de gelée (réserve de 120)
VFXController.capsule(pos: Vector3, species: number)  -- Capsule de bébé qui tombe près du joueur puis saute vers son ranch
VFXController.stats(): { [string]: number }  -- Compteurs (particules actives, instances en réserve) pour les specs de budget
```

- **Clips automatiques** (GDD §9.5, propriétaire : VFXController) : sur `Celebrate` `hatch` (Légendaire+, Arc-en-ciel, Glitch, Flop), `fusion` (COMBO ×5) et `splorch` (le mien), `CaptureService:StartVideoCaptureAsync` sous `pcall`, arrêt par `StopVideoCapture` au plus tard 8 s après (`StateTimeouts` « clip ») ; seulement si `settings.clips`, l'interrupteur du serveur `features.clips` et la réponse `IsContentSharingAllowed` de `PolicyService` (mise en cache, `pcall`). Capture prête → `Cards.push({ kind = "clip" })` **seulement si `StartVideoCaptureAsync` a rendu un succès** (GDD v1.3 §9.5 ; « Enregistrer » : `PromptSaveCapturesToGallery`, « Partager » : `PromptShareCapture`). Résultat autre que `Success` (appareil sans capture), erreur, ou partage interdit par `PolicyService` : plus aucun essai dans la session et attribut local `ClipsUnavailable = true` sur le joueur local ; Panels/Settings et Panels/SplorchPreview le lisent pour cacher la case « Filmer » / « Clips ». `VFXController.spec` : appareil sans capture → aucune case, aucun avertissement (le harnais simule `CaptureService`, indisponible par défaut).

*Fichier : `src/client/Controllers/CameraController.luau` (paquet client-world).*

```lua
CameraController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
CameraController.Start()  -- Connexions et boucles (stub : ne fait rien)
CameraController.splorch(startedAt: number, burstAt: number, endsAt: number)  -- Travelling du héros calé sur l'heure envoyée
CameraController.fovPunch(degrees: number, duration: number)  -- Coup de focale (pas en Mouvement réduit)
CameraController.shake(amplitude: number, duration: number)  -- Secousse bornée (pas en Mouvement réduit)
CameraController.busy(): boolean  -- Travelling en cours
```

*Fichier : `src/client/Controllers/PromptController.luau` (paquet client-world).*

```lua
export type Target = {
	kind: "squishy" | "fence" | "pad" | "bowl" | "pool" | "pot" | "shop" | "mega" | "creature",
	slot: number,
	uid: string,
	id: number,
	tile: string,
	ready: boolean,
	primary: string, -- action de □ : "press" | "throw" | "fusion" | "putInPool" | "buy" | "boop" | "feed" | "catch" | "sell" | "shop" | "petsit" | ""
	secondary: string, -- action de ○ : "pickup" | "putdown" | ""
	position: Vector3,
}

PromptController.Changed: Signal.Signal<Target?>  -- (nouvelle cible)
PromptController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
PromptController.Start()  -- Connexions et boucles (stub : ne fait rien)
PromptController.current(): Target?  -- Cible de l'action principale
PromptController.cycle(dir: number)  -- L1 (−1) / R1 (+1)
PromptController.clickAt(screen: Vector2): boolean  -- Clic souris : fixe la cible 4 s si un candidat est désigné
PromptController.lock(kind: string)  -- Verrouille la cible pendant un maintien (boop, bol)
PromptController.unlock()  -- Fin du maintien
PromptController.afterPress()  -- Après une pression : passe au prochain prêt en 0,15 s
PromptController.leapTarget(): number?  -- Créature visée par le prochain bond
```

*Fichier : `src/client/Controllers/ChaseController.luau` (paquet client-world).*

```lua
ChaseController.Leaped: Signal.Signal<>
ChaseController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ChaseController.Start()  -- Connexions et boucles (stub : ne fait rien)
ChaseController.leap(): boolean  -- Bondit si possible (recharge, pas de portage, pas de fenêtre)
ChaseController.tryCatch(): boolean  -- Tente une capture (□) ; garde l'appui 0,25 s si la créature arrive à portée
ChaseController.cooldownLeft(): number  -- Recharge restante du bond
```

### 13.4 Éclairage (paquet world)

*Fichier : `src/client/Controllers/LightingController.luau` (paquet world).*

```lua
LightingController.current(): string  -- Préréglage en vigueur
LightingController.setQuiet(quiet: boolean)  -- Version discrète des événements pour un nouveau (OnboardingController)
```

### 13.5 HUD, cartes, commandes, accueil (paquet client-hud)

*Fichier : `src/client/UI/HUD.luau` (paquet client-hud).*

```lua
HUD.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
HUD.Start()  -- Connexions et boucles (stub : ne fait rien)
HUD.reveal(element: string, visible: boolean)  -- Montre ou cache un élément (accueil)
HUD.setHint(action: string?, textKey: string?)  -- Consigne du moment dans la place de la puce spéciale (accueil)
HUD.setMenuBadges(bang: boolean, twins: number)  -- Pastilles de la puce Menu
HUD.element(name: string): GuiObject?  -- Élément du HUD (specs de disposition)
HUD.clapHero(): number?  -- Héros de la fenêtre APPLAUDIR ouverte, ou nil (InputController : croix → = Clap)
```

- Contrat v1.2 (GDD v1.3 §10.2) : flèches de bord d'écran **2 au plus dans tous les modes** (`Layout.HudContent.edgeArrow` : le Golden, puis la créature attrapable la plus proche par priorité, à ≤ 120 studs ; Cozy compris) ; jauge **grise** avec « Big Plop se repose mm:ss » (`hud.gauge.rest`) tant que `EventState.gauge.restUntil > now` ; suivi d'objectif : place et attente dans la file du Grand Splorch (`spectacle.queue[i].position` / `eta`, `hud.queue.next` / `hud.queue.place`) ; anneau du bol en 2 s et anneau d'attente sur une dalle (`HoldState`, dessinés par `UI/Prompt`) ; vibration `squishyBack` au retour de mon squishy boopé (`Celebrate "ownerReturn"` / `"returnedBigger"` ; aucune vibration quand il s'enfuit) ; puce APPLAUDIR cachée pendant une poursuite (créature attrapable à ≤ 30 studs), un maintien ou une fenêtre ouverte.

*Fichier : `src/client/UI/WorldText.luau` (paquet client-hud, v1.2).*

```lua
export type Kind = "text" | "plus" | "glyph"
export type Options = { kind: Kind, maxDistance: number, studsOffset: Vector3?, alwaysOnTop: boolean?, name: string? }

WorldText.create(adornee: Instance, options: Options): BillboardGui  -- BillboardGui en Offset × UIScale, LightInfluence 0, fond foncé translucide, accroché à adornee
WorldText.setText(gui: BillboardGui, text: string)  -- Texte affiché (déjà traduit ; nombres par BigNumber)
WorldText.pixelSize(kind: Kind): number  -- Taille en px TV (Layout.WorldText : 32, 40, 48)
WorldText.projectedPx(gui: BillboardGui, viewport: Vector2): number  -- Taille du texte projetée à l'écran, en px TV (specs de disposition)
WorldText.clampToSafe(screen: Vector2, size: Vector2, viewport: Vector2): Vector2  -- Coin haut gauche d'une plaque ramené dans la zone sûre de 5 % (invites)
WorldText.rescale()  -- Réapplique l'échelle à toutes les étiquettes vivantes (résolution changée)
WorldText.release(gui: BillboardGui)  -- Rend l'étiquette à la réserve
```

- **Textes du monde** (GDD v1.3 §10.2, remarque C2-12) : tout texte du monde que le joueur doit lire (prix et niveau d'une dalle, consigne de l'accueil, « +N », taille d'un squishy ciblé, invites) est un `BillboardGui` en **pixels fixes** (Offset × `UIScale` de `UI/Root`), texte ≥ 32 px TV, « +N » 40, glyphes ≥ 48, `LightInfluence = 0`, fond foncé translucide ou contour, distance maximale fixée par usage (dalle : 20 studs) ; jamais un texte posé au sol ni dimensionné en studs. Module-outil sans `Init` ni `Start` (comme `UI/Juice`), appelé par `UI/Prompt`, RanchRenderer et VFXController. `Console_hud.spec` / `Layout_hud.spec` : taille projetée ≥ 28 px TV à 20 studs, aux 3 résolutions.

*Fichier : `src/client/UI/Banners.luau` (paquet client-hud).*

```lua
Banners.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
Banners.Start()  -- Connexions et boucles (stub : ne fait rien)
Banners.show(payload: Types.BannerPayload)  -- Met une bannière dans la file
Banners.setQuiet(quiet: boolean)  -- Mode discret du nouveau
Banners.queued(): number  -- Bannières en attente (specs)
```

*Fichier : `src/client/UI/Cards.luau` (paquet client-hud).*

```lua
export type Card = {
	id: string,
	kind: string, -- Config/Layout.Cards.Order
	blocking: boolean,
	data: { [string]: any },
}

Cards.Changed: Signal.Signal<>
Cards.Requested: Signal.Signal<string, string>  -- (sorte de carte, action) : ouvrir un panneau ; écouté par PanelController
Cards.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
Cards.Start()  -- Connexions et boucles (stub : ne fait rien)
Cards.push(card: Card): string  -- Ajoute une carte ; rend son id
Cards.dismiss(id: string)  -- Retire une carte
Cards.pending(): { Card }  -- Cartes rangées (pastille « ! », entrée du menu)
Cards.open(id: string)  -- Rouvre une carte rangée (depuis le menu)
Cards.current(): Card?  -- Carte affichée
```

- Carte **`booped`** (`Celebrate "booped"`) : non bloquante, `{ uid, species, booperId }`, boutons « Continuer » et « Pas ce joueur » (`RefuseBooper(booperId)`) ; rangée après 8 s dans la pastille « ! » comme les autres. Le Toast ne porte que du texte.
- **Cards ne lie aucune touche.** Une carte non bloquante ne prend jamais la sélection ; on y va par le menu : △ / croix ↓ (liés par InputController seul) → `PanelController.toggleMenu` → l'entrée « ! » est la sélection par défaut quand une carte attend → ✕ rouvre la carte (`Cards.open`), qui prend alors la sélection (fenêtre FocusGuard) jusqu'à ○. `Console_hud.spec` : carte « booped » atteinte par △ → ✕ → « Pas ce joueur » avec la croix, ✕ et ○ seulement.
- Boutons de carte qui mènent à un panneau (objectifs, Squishydex, nouveaux objectifs) : `Cards.Requested:Fire(sorte, "open")`.

*Fichier : `src/client/UI/ScreenFX.luau` (paquet client-hud).*

```lua
ScreenFX.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ScreenFX.Start()  -- Connexions et boucles (stub : ne fait rien)
ScreenFX.flash(alpha: number, duration: number, color: Color3?)  -- Flash (pas en Mouvement réduit)
ScreenFX.glow(color: Color3, duration: number, strength: number?)  -- Lueur des bords
ScreenFX.arrow(id: string, worldPos: Vector3?, kind: string)  -- Flèche de bord d'écran vers une position (nil : retirée)
```

*Fichier : `src/client/UI/Prompt.luau` (paquet client-hud).*

```lua
Prompt.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
Prompt.Start()  -- Connexions et boucles (stub : ne fait rien)
Prompt.setHold(kind: string, endsAt: number?)  -- Anneau de maintien (nil : retiré)
Prompt.plates(): { GuiObject }  -- Plaques affichées (specs)
```

*Fichier : `src/client/Controllers/InputController.luau` (paquet client-hud).*

```lua
InputController.Action: Signal.Signal<string>  -- (action jouée : "press", "pickup", "leap"…)
InputController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
InputController.Start()  -- Connexions et boucles (stub : ne fait rien)
InputController.gameBound(): boolean  -- Les touches du jeu sont liées (aucune fenêtre ouverte)
```

- Liaisons (`BindActionAtPriority`, priorité au-dessus des contrôles par défaut) seulement quand une invite existe et qu'aucune fenêtre n'est ouverte (`FocusGuard.anyOpen()`, signaux `WindowOpened` / `WindowClosed`) ; △ / croix ↓ / M restent liés (ouvrir le menu) sauf pendant une carte bloquante : InputController est le **seul** module qui les lie (ni Cards, ni HUD, ni PanelController). Clavier (v1.2, `Config/Layout.Keyboard`) : menu sur `KeyCode.M` **et** `KeyCode.Semicolon` (sur AZERTY, la touche marquée « M » est `Semicolon` ; la puce affiche celle des deux qui donne « M » par `GetStringForKeyCode`), **jamais Tab** (liste des joueurs de Roblox) ; raccourcis directs G Ranch, C Squishydex, J Objectifs, L Classements, B Boutique, P Réglages ; `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)` sous `pcall`, nouveaux essais pendant 10 s (1, 2, 3 ne servent qu'aux emotes). Croix → devient `Clap(heroId)` tant que `HUD.clapHero()` rend un héros. Échap, Options, `ButtonSelect`, L3 et R3 ne sont **jamais** liés.
- ○ en portant : si le menu est ouvert, ○ le ferme d'abord ; sinon ○ pose (`PutDown`). Ouvrir le menu ne termine pas le portage ; ouvrir un panneau, si (le client envoie `PutDown`).
- Maintiens : `Begin` envoie `BoopHold(…, true)` / `FeedPlop(true)` ; `End` envoie `false` ; l'anneau suit l'heure du serveur.
- Pendant un portage : R2 et L2 jouent `Bump` et ne font rien (pas de vibration).

*Fichier : `src/client/Controllers/OnboardingController.luau` (paquet client-hud).*

```lua
OnboardingController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
OnboardingController.Start()  -- Connexions et boucles (stub : ne fait rien)
OnboardingController.step(): number  -- Étape d'accueil connue du client
OnboardingController.quiet(): boolean  -- Événements discrets (avant l'étape 9)
```

### 13.6 Panneaux et navigation (paquet client-panels)

*Fichier : `src/client/UI/FocusGuard.luau` (paquet client-panels).*

```lua
export type Window = {
	name: string,
	root: GuiObject,
	blocking: boolean,
	default: () -> GuiObject?, -- sélection par défaut (règle de l'écran, GDD §10.6)
	onBack: () -> boolean, -- sous-niveau géré (vrai) ou fermer (faux)
	opener: GuiObject?,
}

FocusGuard.WindowOpened: Signal.Signal<string>  -- (nom)
FocusGuard.WindowClosed: Signal.Signal<string>  -- (nom)
FocusGuard.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
FocusGuard.Start()  -- Connexions et boucles (stub : ne fait rien)
FocusGuard.open(window: Window)  -- Ouvre une fenêtre (devient la fenêtre active ; SelectionGroup, comportement Stop)
FocusGuard.close(name: string)  -- Ferme une fenêtre et rend la sélection à son ouvreur
FocusGuard.top(): Window?  -- Fenêtre active
FocusGuard.anyOpen(): boolean  -- Au moins une fenêtre ouverte (touches du jeu déliées)
FocusGuard.back(): boolean  -- ○ / Retour arrière : remonte d'un niveau (vrai si géré)
FocusGuard.hold(seconds: number?)  -- Tient la sélection pendant une fenêtre de Roblox (60 s au plus)
FocusGuard.release()  -- Fin de la fenêtre de Roblox
FocusGuard.rescues(): number  -- Sauvetages comptés dans la session (specs)
```

*Fichier : `src/client/UI/PanelController.luau` (paquet client-panels).*

```lua
PanelController.Changed: Signal.Signal<string?>  -- (panneau ouvert ou nil)
PanelController.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
PanelController.Start()  -- Connexions et boucles (stub : ne fait rien)
PanelController.toggleMenu()  -- △ / croix ↓ / M (jamais Tab)
PanelController.openMenu(entry: string?)  -- Ouvre le rail (entrée sélectionnée)
PanelController.open(panel: string, tab: string?)  -- Ouvre un panneau
PanelController.closeAll()  -- Ferme tout et rend la main au jeu
PanelController.isOpen(panel: string?): boolean  -- Un panneau (ou celui-ci) est ouvert
PanelController.current(): string?  -- Panneau ouvert
PanelController.entries(): { string }  -- Entrées visibles du rail, dans l'ordre
```

*Fichier : `src/client/UI/ReturnScreen.luau` (paquet client-panels).*

```lua
ReturnScreen.Init()  -- Création des remotes et des états ; aucun yield long (stub : ne fait rien)
ReturnScreen.Start()  -- Connexions et boucles (stub : ne fait rien)
ReturnScreen.show(data: Types.ReturnScreenData)  -- Affiche l'écran
ReturnScreen.isOpen(): boolean  -- Écran ouvert
```

**Interface commune des panneaux** (`UI/Panels/Ranch`, `Squishydex`, `Objectives`, `Leaderboards`, `Shop`, `Settings`, `SplorchPreview`, `OutfitPreview`, `Diagnostics`) :

*Fichier : `src/client/UI/Panels/Ranch.luau` (paquet client-panels).*

```lua
Ranch.build(container: Frame)  -- Construit le contenu une seule fois dans le cadre du panneau
Ranch.open(tab: string?)  -- Affiche le panneau (onglet demandé ou le dernier)
Ranch.close()  -- Cache le panneau
Ranch.tabs(): { string }  -- Onglets, dans l'ordre (L1 / R1)
Ranch.setTab(tab: string)  -- Change d'onglet
Ranch.defaultSelection(): GuiObject?  -- Sélection par défaut (table du GDD §10.6)
Ranch.onBack(): boolean  -- ○ : sous-niveau géré (vrai) ou remonter au menu (faux)
Ranch.visible(): boolean  -- Entrée du menu visible pour ce joueur
Ranch.setNavigator(nav: { open: (panel: string, tab: string?) -> (), back: () -> () })  -- Navigateur passé par PanelController avant build
```

PanelController appelle `setNavigator(nav)` de chaque panneau **avant** `build` : un panneau qui mène à un autre (SplorchPreview « Dépenser d'abord » → Ranch / Dalles, Settings → Diagnostics, Shop et Ranch › Style → OutfitPreview) appelle `nav.open(panneau, onglet?)`, jamais `PanelController` (require circulaire). Chaque panneau envoie `UiSeen(écran)` à sa première ouverture de la session quand l'écran fait partie de la liste de l'intention. Chaque panneau construit son contenu dans le cadre fourni par PanelController (1440 × 860 px TV), une seule fois, puis se met à jour par `StateController.observe` / signaux. Grilles virtualisées (la sélection suit l'index au défilement). Rôles de chaque panneau :

- **`UI/Panels/Ranch`** : Panneau Ranch (GDD §10.3, §4.10, §4.13, §4.14, §5.4) : Enclos (grille virtualisée, tri, verrou, Meilleur Ami, monture, cœurs des jumeaux, Tout fusionner, Ranger avec aperçu), Dodo, Lettres, Fusionner (choisir A puis B), Vendre / Relâcher (maintien 0,6 s, confirmation en 2 étapes avec « 1 sur X » ; ○ vide d'abord une sélection multiple, puis remonte), Dalles (acheter d'ici), **Style** : sous-listes Selle, Traînée, Titre, Thème du ranch, Drapeau, Tenues (`panel.ranch.style.*`) ; chaque case montre l'objet, « Équipé » s'il l'est, ou le cadenas et sa source (`cosmetic.source.*`) s'il est verrouillé ; ✕ sur un objet débloqué → `EquipCosmetic(kind, id)` (« Aucun » pour retirer) ; ✕ sur une tenue possédée → OutfitPreview (`nav.open("OutfitPreview")`, qui envoie `EquipOutfit`). Onglets dans l'ordre : Enclos, Dodo, Lettres, Fusionner, Vendre, Dalles, Style. `Panels_Ranch.spec` : Style atteint à la croix, équiper / retirer, verrouillé refusé sans envoi (son `Error`, vibration `refuse`), textes EN / FR à 28 px TV.
- **`UI/Panels/Squishydex`** : Panneau Squishydex (GDD §4.17, §10.3 v1.3) : Espèces (grille par famille, silhouettes grises) ; ✕ sur une espèce ouvre sa **fiche** (9 mutations en 3 × 3, badges d'étoiles, record ; `panel.dex.sheet.*`) ; Familles (bonus gagnés pour toujours, `dex.fam`) ; Guide (toutes les probabilités, protection contre la malchance, règles du BOOP RUSH). Plus d'onglets Mutations (grille 26 × 9) ni Étoiles (v1.2). Jalons à réclamer ; nombres géants avec le mot entier.
- **`UI/Panels/Objectives`** : Panneau Objectifs (GDD §7.3, §7.4) : Aujourd'hui (3 objectifs, réclamer, relance), Plop (jours au total, paliers), Accueil (tant qu'il n'est pas fini).
- **`UI/Panels/Leaderboards`** : Panneau Classements (GDD §6.9) : 5 onglets ; d'abord ma place sur ce serveur et mon record contre la semaine dernière, puis le top 10 mondial (LeaderboardState).
- **`UI/Panels/Shop`** : Panneau Boutique (GDD §8) : onglets **Passes / Fête / Tenues** (aperçu 3D) ; prix lus à l'exécution (Prices.observe) ; articles à id 0 ou `hidden` cachés (paquets de pièces retirés du lancement), onglet absent si tous cachés ; caché les 10 premières minutes ; bouton Squish Party caché pendant une fête ; aucun article caché par PolicyService ; `ClientEvent("shopOpened")` à chaque ouverture ; sélection tenue pendant la fenêtre d'achat (FocusGuard.hold).
- **`UI/Panels/Settings`** : Panneau Réglages (GDD §10.3) : mode Rush / Cozy (SetMode), Cacher mon nom, Recevoir les cadeaux, Clips (caché si `ClipsUnavailable`), Mouvement réduit, Graphismes légers, Musique, Effets sonores, Vibrations, Emote de la croix ←, Langue ; « BOOP RUSH autorisé » (propriétaire d'un serveur privé) ; Diagnostics (administrateurs) ; message « Tes squishies grandissent même quand tu dors ».
- **`UI/Panels/SplorchPreview`** : Aperçu du Grand Splorch (GDD §4.15) : 3 tuiles « Tu gagnes », animation avant / après, pièces perdues en rouge et « Dépenser d'abord » (onglet Dalles, dalles gardées d'abord), choix du squishy qui s'envole, case « Filmer », bouton à maintenir 1,5 s (✕), « Détails » (deux colonnes, prochain objectif), « Rentre dans ton ranch », « Attends que … rentre ! » si un squishy est en fuite. Plus de 2e confirmation (paquets retirés, v1.2).
- **`UI/Panels/OutfitPreview`** : Aperçu 3D d'une tenue (GDD §8.3) avant l'achat (depuis Boutique) et dans la garde-robe (depuis Ranch › Style › Tenues) : ViewportFrame qui tourne, mettre / retirer sur le squishy choisi (EquipOutfit) ; ○ revient au panneau d'où l'on vient (`nav.back()`).
- **`UI/Panels/Diagnostics`** : Panneau Diagnostics (GDD §12.11), administrateurs seulement : `visible()` devient vrai à la réception du `DiagnosticsSnapshot` « bonjour » (`tab = 0`). Onglets : Ce serveur, Mon client (`ErrorReporter.stats()` : images par seconde, mémoire, ping, instances, connexions, qualité ; `ErrorReporter.entries()` : erreurs du client), Aujourd'hui, **Outils** (`AdminCommand` : lancer un BOOP RUSH, lancer un MEGA, horloge ±10 min et remise à zéro — grisés « Studio seulement » hors Studio —, erreur de test serveur et client, mode photo, fête d'administrateur ; boutons atteignables à la croix, ✕ envoie) ; ✕ sur une ligne ouvre ses 3 exemples ; texte 32 px TV, heure et version en haut, fait pour être photographié ; RequestDiagnostics (1 / 2 s). C'est la seule interface des commandes de développement : console sans chat ni champ de texte (tests manuels M1, M17, vignettes).

### 13.7 ErrorReporter (paquet meta)

*Fichier : `src/client/Controllers/ErrorReporter.luau` (paquet meta).*

```lua
ErrorReporter.attach()  -- Branche ScriptContext.Error et LogService.MessageOut au plus tôt
ErrorReporter.report(kind: number, text: string, trace: string?)  -- Rapport interne (FocusRescued, délai de WaitForChild)
ErrorReporter.noteContext(key: string, value: string)  -- Champ du contexte (fenêtre ouverte, événement en cours)
ErrorReporter.sent(): number  -- Rapports envoyés dans la session (tests)
ErrorReporter.entries(): { Types.DiagEntry }  -- Rapports de ce client (onglet « Mon client »)
ErrorReporter.stats(): { fps: number, memoryMb: number, pingMs: number, instances: number, connections: number, reduced: boolean }  -- Mesures du client
```

- Normalisation `DiagRules`, 1 par clé et par minute, 30 par session ; **file bornée (10)** vidée au débit d'`Intents.ReportError` (1 envoi toutes les 2,2 s) : une cascade d'erreurs différentes au démarrage n'est pas perdue par le débit du serveur.
- Interrupteur : `features.diagnostics` du dernier `EventState` (faux : rien n'est envoyé, `entries()` continue de compter).
- `Celebrate "testError"` (administrateur, `AdminCommand "testError" "client"`) : lève une erreur volontaire dans un thread du client, qui suit le chemin normal (test manuel M17).

---

## 14. Console d'abord : disposition télé, navigation, glyphes, vibrations, sons

Décision du propriétaire : **PS5 avec DualSense sur une télé vue de 2,5 à 3 m**, puis Xbox, puis PC. Types d'appareils publiés : Ordinateur + Console (VR coupée). **Aucun code tactile** : pas de bouton à l'écran pour jouer, pas de disposition pour petit écran, pas de geste au doigt.

### 14.1 La disposition télé est la disposition principale (et la seule)

- Référence **1920 × 1080 px TV** (`Config/Layout.Reference`), la même règle sur tous les écrans : `UIScale = max(0,5 ; min(L / 1920, H / 1080))`, **sans plafond** (1 en 1080p, 2 en 4K, 0,667 en 720p). Zone sûre de **5 %** de chaque côté sur tous les écrans (x 96-1824, y 54-1026). Le socle (`Config/Console`, `Util/Platform`, `UI/Root`, `UI/Theme`, `UI/Toast`, `Util/Haptics`, `tests/harness/Gamepad`) applique déjà ces valeurs : note **INT-TV faite par le contrat** avant les paquets (§22.1) ; seul l'habillage de `Loading` (encore dessiné dans l'unité 1280 × 720, facteur `DRAWN_UNIT`, et sa mise en page « écran bas ») reste à refaire par world. Le code du jeu place tout en px TV dans `Root.safe(...)` avec les valeurs de `Config/Layout` : les rectangles sont en coordonnées d'écran 1920 × 1080 ; dans `Root.safe` (dont la marge intérieure est la zone sûre), un élément se place à (x − 96, y − 54) depuis le coin de son ancrage.
- Tailles minimales (px TV) : texte lisible **28** (texte courant 32, boutons 40, titres 48-56, compteurs 56-72) ; glyphe **48** (64 pour la consigne et l'invite □) ; bouton **80** de haut (96 pour le principal) ; écart **16** entre deux éléments sélectionnables (24 habituel) ; cadre de sélection blanc **6 px** bordé de sombre **2 px**, grossissement 1,05, respiration 1,2 s.
- Chaque texte : `TextScaled` + `UITextSizeConstraint` (minimum 28 px TV) ; s'il ne tient pas à 28 en anglais **et** en français, la spec échoue et on raccourcit le libellé. Contraste : fond foncé translucide (≥ 0,6) ou `UIStroke` 3 px. Jamais de texte posé sur le décor.
- HUD : rectangles fixes de `Config/Layout.Hud`, dans 4 colonnes accrochées aux bords de la zone sûre ; aucun recouvrement aux 3 résolutions (et en 21:9, 16:10 : les colonnes s'écartent) ; 8 éléments au plus en jeu calme ; affichage progressif ; le milieu (x 460-1300, y 330-822) reste libre. `Contract_game.spec` vérifie déjà les rectangles ; `TvAudit` (§17) vérifie l'écran réel.
- Panneaux : 1440 × 860 px TV centrés ; en-tête 96 (titre 48) ; onglets de 72 de haut (32 px), atteignables à la croix (↑ depuis le haut du contenu) et par L1 / R1 ; grilles de cases 208 × 232 (6 colonnes, 2,5 rangées visibles) ; bouton Fermer 80 × 80 avec le glyphe ○. Un seul panneau ouvert. Le jeu n'est pas mis en pause.
- Style : `UICorner` 14-18 px, `UIStroke` 3 px bleu nuit (30, 25, 60), dégradés pastel, polices FredokaOne (texte) et LuckiestGuy (tampons). Aucune image téléversée : formes en Frames et glyphes de Roblox.
- Un `ScreenGui` par écran logique, `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling` (fourni par `Root.screen`). Fonds décoratifs qui débordent de la zone sûre : attribut `Decorative = true`.

### 14.2 Navigation à la manette seule (règle des 3 touches)

- La croix (ou le stick gauche) déplace la sélection, ✕ valide, ○ recule d'un niveau (depuis le premier niveau : retour au jeu), △ ferme tout ; L1 / R1 changent d'onglet (en boucle) ; L2 / R2 changent de panneau (en boucle : Ranch → Squishydex → Objectifs → Classements → Boutique → Réglages) **seulement quand un panneau est ouvert**. Depuis le jeu, croix ↓ ouvre le menu (comme △). **La croix, ✕ et ○ suffisent pour atteindre chaque écran et en revenir** ; L1, R1, L2, R2 et △ ne sont que des raccourcis.
- Chaque fenêtre est un `SelectionGroup` avec `SelectionBehavior* = Stop` ; graphe `NextSelection*` explicite là où la géométrie hésite ; la sélection fait défiler les listes (une rangée de marge).
- `UI/FocusGuard` applique les 8 règles du GDD §10.6 ; chaque sauvetage est compté (`FocusRescued` → ErrorReporter → Diagnostics).
- Sélection par défaut de chaque écran (GDD §10.6) :

| Écran | Sélection par défaut | ○ | L1 / R1 | L2 / R2 |
|---|---|---|---|---|
| Jeu | aucune (le stick fait marcher) | Prendre / Poser | changer de cible (ranch, clôture) | Monter / Bondir |
| Menu | Grand Splorch s'il est prêt, sinon l'entrée à pastille « ! » (carte en attente, ex. « booped »), sinon la dernière, sinon Ranch | retour au jeu | — | — |
| Ranch | 1re case de l'onglet ; Fusionner : « Choisir A » ; Dalles : la moins chère achetable ; Style : l'objet équipé de la 1re sous-liste (Selle) | → bouton du menu (Style : d'une sous-liste à la liste des sous-listes, puis au menu) | onglets | panneaux |
| Squishydex | 1re entrée ; Guide : 1re ligne (↑ / ↓ font défiler de 70 %) | → menu | onglets | panneaux |
| Objectifs | « Réclamer » disponible, sinon 1re carte | → menu | onglets | panneaux |
| Classements | onglet en cours | → menu | onglets | panneaux |
| Boutique | 1er « Acheter » de l'onglet | → menu | onglets | panneaux |
| Réglages | 1er interrupteur | → menu | — | panneaux |
| Diagnostics | onglet « Ce serveur » ; Outils : 1er bouton actif | → Réglages | onglets | — |
| Aperçu de tenue | « Mettre » | → panneau d'origine (Boutique ou Ranch › Style) | — | — |
| Aperçu du Grand Splorch | bouton « Maintenir » (glyphe ✕) | → menu | — | — |
| Carte du choix | « Je reste tranquille », après la garde de 0,6 s | = Cozy | — | — |
| Cartes non bloquantes | aucune (jamais la sélection) ; on y va par le menu (△ / croix ↓, liés par InputController seul) dont l'entrée « ! » est sélectionnée ; ✕ rouvre la carte, qui prend alors la sélection (« booped » : « Continuer » par défaut) | ferme la carte (rangée) | — | — |
| Écran de retour | « Super ! » | ferme | — | — |
| Échec de chargement | Réessayer | — | — | — |

### 14.3 Glyphes

Uniquement `UI/Glyph` (socle) : icône `GetImageForKeyCode` (PlayStation sur PlayStation, Xbox sur Xbox), repli neutre en losange, jamais « X », « Y » ou « LB » écrits ; au clavier, texte de la touche selon la disposition (`GetStringForKeyCode` : sur AZERTY, `KeyCode.Q` s'affiche « A »). Changement de manette ou passage au clavier : tous les glyphes changent aussitôt (`Platform.Changed`). Une consigne ne cite jamais une touche dans une phrase : glyphe à côté d'un mot court.

### 14.4 Vibrations (catalogue, `Config/Console.Haptics.Events`)

`Util/Haptics.play(nom, échelle?)` seulement. Jamais au clavier-souris, délai minimal 0,25 s sauf priorité supérieure ou événement `cooldownExempt` (sirène, v1.2), atténuation < 0,35 ignorée, réglage « Vibrations ». Jamais sur une sélection, un bond ou une marche. Moteurs standard seulement (aucun effet propre à la DualSense). Force variable : la force de la carte est le **maximum** ; le contrôleur passe une échelle ≤ 1 (`force voulue / force de la carte`).

| Nom | Quand | Joué par | Priorité |
|---|---|---|---|
| `pressTick` | **seulement** une pression PERFECT du MEGA (une pression ordinaire, chez soi ou au MEGA, ne vibre jamais ; GDD v1.3), 2 par seconde au plus : VFXController est le **seul** à la borner (remarque A29) | VFXController | 1 |
| `perfect` | PERFECT chez soi : 0,3 + 0,03 par cran de série (carte 0,45, échelle `(0,3 + 0,03 × série) / 0,45`) | VFXController | 2 |
| `tileBuy` | dalle achetée | VFXController | 2 |
| `refuse` | bouton de menu refusé | panneaux | 1 |
| `listEnd` | bout de liste | PanelController | 1 |
| `holdStart` | début d'un maintien (Grand Splorch, boop, bol) | InputController, SplorchPreview | 1 |
| `holdDone` | maintien terminé | InputController, SplorchPreview | 2 |
| `cardIn` | la carte du choix s'ouvre | Cards | 2 |
| `catch` | capture, capsule de cadeau, naissance Épique | VFXController | 2 |
| `fusion` | chaque étape de fusion : 0,4 + 0,05 par étape au-delà de la première (carte 0,65, échelle `(0,4 + 0,05 × (k − 1)) / 0,65`) | VFXController | 2 |
| `comboBig` | combo ≥ 4 | VFXController | 3 |
| `boopDone` | mon boop a réussi | VFXController | 2 |
| `squishyBack` | mon squishy boopé revient (rendu par un autre joueur, ou rentré seul ; la capture Héros joue `catch`) : GameplayCollision, Small, 0,3, 0,08 s. Remplace `booped` (v1.2 : aucune vibration quand il s'enfuit) | HUD | 2 |
| `rushSiren` | sirène du Rush, **une seule impulsion de 0,3 s**, jouée même pendant le délai minimal (`cooldownExempt`) ; jamais pour un nouveau avant l'étape 9 | LightingController | 3 |
| `megaLand` | atterrissage du MEGA à < 120 studs, atténué 1 − d / 120 | VFXController | 3 |
| `megaPop` | le MEGA éclate (participant) | VFXController | 4 |
| `hatchLegend` | naissance Légendaire+, Flop, Glitch, Arc-en-ciel | VFXController | 4 |
| `splorch` | mon Grand Splorch (éclatement) | VFXController | 5 |

### 14.5 Sons d'interface

Chaque geste de menu a son son, toujours le même (`AudioController.play`) : sélection qui bouge `Select` (au plus 1 toutes les 0,06 s, joué par `AudioController.playNav` du socle), validation `Click`, retour `Back`, onglet ou panneau suivant `Tab`, bout de liste `Bump`, refus `Error`, ouverture `Whoosh`. Ils respectent le réglage Effets sonores.

### 14.6 Clavier et souris (second)

Même disposition : E (action), Q (Prendre / Poser), Maj (Bondir), R (Monter), **M (Menu : `KeyCode.M` et `KeyCode.Semicolon`, la touche marquée « M » en AZERTY)**, G C J L B P (Ranch, Squishydex, Objectifs, Classements, Boutique, Réglages), 1 2 3 (emotes), F (Applaudir), Retour arrière (= ○ dans les menus) ; la souris clique ce qui est affiché (clic sur un squishy : cible fixée 4 s, par projection à l'écran). **Échap et Tab restent à Roblox** (Tab = liste des joueurs : jamais lié par le jeu). Sac à objets de Roblox coupé (`SetCoreGuiEnabled(Backpack, false)` sous `pcall`, nouveaux essais pendant 10 s). Libellés des touches par `GetStringForKeyCode`. `EnableMouseLockOption = false`. Pas de navigation obligatoire aux flèches. Valeurs : `Config/Layout.Keyboard`.

### 14.7 Ni tactile ni chat sur console

- Appareil tactile inattendu (`Platform.inputKind() == TOUCH`) : aucun contrôle ajouté, aucune erreur ; message `device.touch` une fois (HUD) ; `SetInputType(1, …)` pour l'analytique `TouchDeviceJoined`. Les specs du jeu n'utilisent jamais `Harness.new({ touch = true })`.
- Chat : `Platform.applyChatRule` (socle) coupe la fenêtre de chat sur console ; communication par les 3 emotes.

### 14.8 Qui utilise quoi

| Module | Platform | Glyph | Haptics | Root | FocusGuard |
|---|---|---|---|---|---|
| HUD, Banners, ScreenFX, Cards | `isTenFoot`, `inputKind`, `Changed` | puce Menu, consignes, carte | `squishyBack`, `cardIn` | `Root.safe` | Cards (carte bloquante) |
| Prompt | `inputKind` | □ / ○ des invites | — | `Root.safe` | caché si une fenêtre est ouverte |
| InputController | `usingGamepad`, `isGamepadKey` | — | `holdStart`, `holdDone` | — | délie les touches du jeu |
| OnboardingController | `inputKind` (stick ou touches) | consigne du moment | — | — | — |
| PanelController, panneaux, ReturnScreen | `isTenFoot` | ○ Fermer, ✕ Maintenir, L1 / R1, L2 / R2 | `listEnd`, `refuse`, `holdStart`, `holdDone` | `Root.screen`, `Root.selectionImage` | chaque fenêtre |
| VFXController, LightingController | — | — | effets de jeu | — | — |
| ErrorReporter | contexte (appareil, entrée, résolution) | — | — | — | compte `FocusRescued` |

---

## 15. Anti-triche : où chaque action est vérifiée

Toute action qui exige un lieu utilise la **position validée** (`MoveCheck.lastValid`, avancée à chaque tick) et `MoveCheck.canAct(player, now)` (aucune dette du budget d'action, aucune restriction), jamais la racine brute du client. Un refus est neutre (aucune accusation : « connexion instable »).

| Action | Où | Vérification |
|---|---|---|
| Attraper (□) | ChaseService (tick suivant l'intention, ordre d'arrivée) | à l'instant `tClient` (ramené dans [maintenant − 0,35 ; maintenant]) : `MoveCheck.positionAt(joueur, tClient)` contre `SeededPath.pos(tClient)` ; à plat ≤ rayon + 1,5 ; écart vertical **depuis les pieds** ≤ 8 ; `canAct` ; règles de `RushRules.checkCatch` |
| Bondir et capture à l'atterrissage | ChaseService | recharge 4 s (horloge du serveur), direction bornée, `canAct` au **départ** ; point d'atterrissage = `LeapRules.landing(positionAt(tClient), dir)` (jamais la position physique) ; crédit `MoveCheck.grant` de 12 studs sur 0,35 s, rétroactif ≤ 0,3 s, **un par 4 s** (une rafale de faux `Leap` n'apporte jamais plus de 12 studs par 4 s) |
| Booper | RushService | `RushRules.checkBoop` (distance ≤ 8 à la position validée, `canAct`, squishy toujours éligible à la clôture : `BoopCtx.eligible`), revérifié à **chaque tick** du maintien ; durée mesurée par le serveur ; `extendHold` une fois au plus |
| Presser chez soi | SquishyService | uid possédé, à plat ≤ 10 + 2 du centre de la place du squishy, pieds ≤ 8, `canAct`, recharge, 12 / s ; `tClient` borné (au pire ×2 PERFECT, accepté et borné ; aucun classement ne compte les PERFECT) |
| Pet-sitting | CommunityService | ami Roblox, squishy à la clôture, côté rue à plat ≤ 10 + 2 du centre de sa place, `canAct` ; 100 récompensées par visiteur, 100 reçues par propriétaire, « Plus serviable » ≤ 20 par ami et par jour ; 2 s de revenu par pression |
| Presser le MEGA | EventService | phase, à plat ≤ 20 studs du centre, pieds ≤ 8, `canAct`, recharge 0,4 s |
| Encaisser le Pot, acheter sur une dalle | RanchService (tick) | acteur `canAct` ; distances à plat ; entrée par hystérésis ; dalle : 0,6 s dessus sans porter ni autre maintien ; un achat par entrée |
| Nourrir au bol | QuestService | à plat ≤ 8 studs, pieds ≤ 8, `canAct`, une fois par jour UTC, 2 s mesurées par le serveur |
| Clôtures des ranchs | RanchService (tick) | intrus repoussé à chaque tick (même sans `canAct`) ; aucune exception, même pour les amis ; murs invisibles de 30 studs, plus hauts que tout saut (selle géante comprise) |
| Grand Splorch (entrée en file) | SplorchService | dans son ranch (position validée), rien de porté, objectif atteint, aucun squishy en fuite ; une seule vérification puis garanti |
| Joueurs actifs (N du MEGA et de la jauge) | EventService (`Server/Util/Activity`) | seulement les intentions de jeu **acceptées** (`activity = true`) et les déplacements **validés** ≥ 4 studs ; un joueur absent ne gonfle jamais l'objectif des autres ; un tricheur qui se rend « actif » ne fait que durcir l'objectif |
| Bébés, croissance « Héros », pet-sitting à deux comptes | ChaseService, SquishyService, CommunityService | bébé ≤ 0,5 × le plus gros du receveur, mutation copiée jusqu'à ×5 seulement ; + 1 h / + 30 min de croissance une fois par squishy et par jour (`gd`) ; plafonds de pet-sitting par visiteur, par propriétaire et par ami |
| Achats | MonetizationService / ProductService | reçu idempotent, acquitté après sauvegarde ; aucun achat avant le chargement du profil ; Squish Party seulement si elle commence aussitôt |
| Vitesse, téléportation, vol, passe-muraille | ChaseService (MoveCheck) | budget d'action, retours après 3 infractions en 5 s, gels honnêtes jusqu'à 1,5 s tolérés ; sol = `WorldLayout.supportY` (pur) ; monture : `MoveCheck.setRootOffset(player, hausse, hauteur de saut)` à chaque montée et descente, marge verticale ponctuelle égale au changement, montée permise par tick `max(12, √(2 × 196,2 × JumpHeight)) × dt × Margin + Slack` (INT-MOVE) ; bornes `MaxRadius = 330` (murs à 322) |
| Écrans vus (`UiSeen`) | QuestService | clé d'une liste fermée, une fois par écran et par session ; ne donne rien |
| Rapports d'erreur | DiagnosticsService | plafonds, tailles, noms nettoyés ; ne change jamais rien au jeu |
| Classements | LeaderboardService | exclusion après `Tuning.StrikesForBan` retours en 10 min, jusqu'à la fin de la semaine suivante ; « Plus serviable » seulement sur les pressions récompensées (`PetSitRewarded`) |
| Commandes de développement | EventService | `Data/Admins` à chaque message ; `"clock"` seulement en Studio |

---

## 16. Économie : formules, réglages, simulation, nombres géants

- **Une seule source de vérité** : les formules sont dans `Logic/Formulas` (et `Odds`, `FusionRules`, `QuestRules`, `MegaRules`), les nombres dans `Config/Balance` (et `Events`, `Quests`). Le serveur, le client (prédiction) et la simulation appellent **le même code**.
- **Porte de simulation** (bloquante, paquet logic) : `tests/specs/EconomyPacing.spec.luau` avec `tests/sim/Sim.luau` (socle) et un modèle `tests/sim/EconomyModel.luau` (logic) qui joue les vraies règles (presser toutes les 2 s le plus rentable, PERFECT 40 %, Pot toutes les 40 s, achats les moins chers utiles d'abord, fusions dès qu'une paire existe, 85 % des fuites attrapées, une séance par jour, événements moyens, aucun achat Robux), graine fixe. **Contrat v1.2 (GDD v1.3 §4.24, note logic)** : boosts **calculés d'après les règles**, jamais « 20 % du temps » : bol de Plop 5 min au début de chaque séance ; cycle de la Wobble Party tiré des règles de la jauge (remplissage ≈ 30 min sur un serveur de 16 actifs, seules les pressions PERFECT comptant, puis fête de 5 min et sieste de 20 min) ; vraies parts d'un serveur de **4, 8 et 16** joueurs ; moteur **par événements** ; **50 joueurs × 3 tailles dans `check.sh`**, 200 en lancement manuel. Jalons : premier Grand Splorch **11-16 min** ; J7 plus gros **4e7-4e8**, tampons J7 **80-110** ; **J14 R 14-16** ; **J28 R 17-22** ; pièces à 5:00 **5K-17K** (repère seulement) ; plus les jalons d'accueil (première pression ≤ 15 s, premier achat ≤ 30 s, à 5:00 : 3-4 squishies, ≥ 1 fusion, ≥ 1 capture, balade ≤ 5:00, dalle Enclos payable pour ≥ 90 %, 3 objectifs sur 3 au jour 1 pour ≥ 90 %, un Épique+ au jour 7 pour ≥ 95 %). **Jalons de santé** : Tapis 12 atteint après ≥ 50 % de la boucle ; pièces perdues au Grand Splorch ≤ 10 × le prix du Tapis 12 ; pressions ≥ 50 % des pièces gagnées en ligne au J7 ; Grands Splorch prêts à la connexion ≤ 50 % du J2 au J14 ; part du temps en ×2 entre 20 et 40 % ; joueur qui achète beaucoup ≤ 2 R d'avance au J28.
- **Réglage** : seul logic modifie les **valeurs** de `Config/Balance` (jamais la structure), seulement pour tenir la porte, et écrit chaque changement au §21 (valeur avant, après, raison, résultat de la simulation).
- **Nombres géants** : pièces, Pot et tailles bornés à [0 ; 1e300], jamais `NaN` ni infini (`Formulas.clampCoins`, `clampSize`) ; pièces entières sous 1e15. Affichage par `Logic/BigNumber.abbreviate(n, Prefs.language())` seulement (jamais `Prefs.number` ni `Format.abbreviate` pour un nombre du jeu). Échelle visuelle logarithmique (`SizeScale`).
- **Pot exact** : chaque seconde est intégrée une seule fois (`settle` sur [`growth.t` ; now], §11.5) ; le hors-ligne est versé par le rebase de `onPrepare` (Pot 25 %, croissance 30 % arrêtée à 90 % de l'objectif, 8 h au plus) avant tout règlement. La simulation (`EconomyModel`) appelle les mêmes `Formulas.potGain`, `offlinePot` et `offlineGrowth`.
- **Récompenses en secondes de revenu** : `EconomyService.addIncomeSeconds` avec le revenu du moment, **P et B compris une seule fois** (jamais × P de nouveau ; spec explicite) : justes à tous les niveaux. Les minimums fixes (10 pièces par pression, 10 par vente) ne sont pas multipliés.
- **Prix des dalles de la boucle × 3,5^R** (`Balance.Tiles.RScale`, GDD v1.3 §4.6) : avec × 2^R, toutes les dalles étaient au maximum quelques minutes après chaque Grand Splorch ; Enclos et Lit douillet ne sont jamais multipliés.

---

## 17. Stratégie zéro bug

Le propriétaire a vu en direct des bugs de Comet Conga que 1 600 tests hors ligne n'avaient pas vus. Barre de Raise a Squishy : **aucun bug au lancement**. Trois moyens : des **mécaniques robustes par construction** (§1 règle 12), **10 couches de tests** et **Diagnostics en ligne**.

### 17.1 Les 10 couches (GDD §12.10) : specs, extensions du harnais, propriétaires

| Couche | Ce qui est prouvé | Specs | Extension du harnais (propriétaire) |
|---|---|---|---|
| **a.** Modules purs : cas exacts et propriétés | valeurs du GDD ; jamais `NaN` ni négatif ; monotonie ; tables à 100 % ; fusion 2 → 1 ; chemins jamais hors graphe ni dans un ranch ; mêmes résultats client / serveur ; entrées bizarres sûres | `<Module>.spec` et `Props_<Module>.spec` pour les 19 modules de `Shared/Logic`, `SquishyBuilder.spec`, `Squash.spec` | `tests/harness/Props.luau` : générateurs à graine (nombres limites `NaN`, ±inf, 1e308, −0, entiers, chaînes UTF-8 valides et invalides, tables mixtes ou à trous), `Props.check(n, gen, prédicat)` avec réduction du contre-exemple (**logic**) |
| **b.** Chaque remote attaqué | pour chaque intention de `Config/Intents` : mauvais types, `nil`, `NaN`, ±inf, nombres énormes, chaînes de 100 000 caractères, UTF-8 invalide, tables profondes, mixtes ou à trous, uid d'un autre joueur, rafales de 1 000 messages par seconde → **aucune mutation du profil, aucune erreur**, au plus un `Feedback` neutre, seau à jetons au bon débit | `Remotes_<Paquet>.spec` (une par paquet serveur), `RateLimit.spec` (socle) | `tests/harness/Fuzz.luau` : `Fuzz.payloads(spec)` (charges hostiles par sorte d'argument), `Fuzz.attack(h, joueur, nom, n)`, `Fuzz.profileUnchanged(h, joueur, fn)`, `Fuzz.rate(h, joueur, nom)` (**meta**) |
| **c.** 16 robots, longue durée | serveur complet, 16 robots qui jouent `SOAK_HOURS` heures de temps simulé (variable d'environnement ; **0,5 h par défaut** dans `check.sh`, **6 h** dans `scripts/soak.sh`, porte de nuit du §18 n° 2) ; **à chaque tick** : `Invariants.profile` de chaque profil ; uid uniques et à un seul endroit ; aucun état plus vieux que son délai (`X.openStates()` de chaque service + `StateTimeouts.expired`) ; plafonds ; instances et connexions stables après la mise en route (± 5 %, `Harness:counts()` + nombre de handlers des `Signals`) ; tick dans son budget ; zéro erreur, zéro avertissement ; démarrage et fermeture (`BindToClose`) à 16. `Soak.luau` rapporte les ms par tick ; la spec échoue au-delà de **10 ms en moyenne sous Lune** | `Soak.spec`, `Boot.spec` (intégration) | `tests/harness/Soak.luau` : boucle de temps accélérée (`Clock.advance` + `ChaseService.tick`), contrôles par tick, compteurs (`Harness:counts()` : instances sous `game`, connexions vivantes des signaux simulés, threads en attente — ajoutés au socle par le contrat) ; `tests/harness/Brains.luau` : cerveaux de robots (presser, acheter, fusionner, booper, poursuivre, monter, partir, revenir, mourir, changer de mode, gigue et gels réseau de `Bots`) (**chase**) |
| **d.** Client complet, profil console, 3 résolutions | partie serveur enregistrée (`Wire`) rejouée dans le vrai client, `console = true`, en 1920 × 1080, 3840 × 2160, 1280 × 720, EN puis FR ; un robot parcourt **tous les écrans** avec la croix, ✕ et ○ seulement ; ○ revient toujours ; sélection jamais vide dans une fenêtre, jamais hors de la fenêtre active, jamais posée en jeu ; à chaque étape : aucun chevauchement, aucun texte coupé ni sous 28 px TV, rien hors de la zone sûre, aucune touche du jeu active derrière une fenêtre, glyphes PlayStation ; même parcours au clavier-souris | `ClientReplay.spec` (intégration), `Console_<Module>.spec` (paquets client), `Layout_<Écran>.spec` | `tests/harness/TvAudit.luau` : `TvAudit.run(h, { resolutions, langs })`, `walk(h)` (parcours à 3 touches à partir du menu, graphe des écrans atteints), `overlaps(h)`, `clipped(h)` (texte qui ne tient pas à 28 px TV), `outsideSafe(h)`, `boundBehindWindow(h)` ; bâti sur `Layout` et `Gamepad` du socle (**client-panels**) |
| **e.** Données en désordre | pannes de DataStore (erreurs, délais de 10 s, quotas), verrou entre 2-3 serveurs, retour immédiat sur un autre serveur, fermeture à 16 avec un magasin lent, migrations depuis les sauvegardes-témoins, profils abîmés réparés par `ProfileRepair`, reçu rejoué, achat pendant une panne, mutations « au départ » présentes dans la sauvegarde de départ (§1 règle 15), rebase hors ligne avant tout règlement ; le DataStore simulé refuse les tableaux à trous et les tables mixtes | `DataChaos.spec`, `ProfileRepair.spec`, `Schema_game.spec`, specs du socle (`DataService`, `Fix_*`) | `tests/harness/Chaos.luau` : pannes par type d'appel, latence, quotas, serveurs multiples (méthode de `Fix_final_data_lock`) (**ranch**) |
| **f.** Rythme de l'économie | simulation du §16 (boosts calculés d'après les règles, serveurs de 4, 8, 16, moteur par événements, jalons de rythme et de santé), porte bloquante | `EconomyPacing.spec` (50 joueurs × 3 tailles dans `check.sh`, 200 à la main) | `tests/sim/EconomyModel.luau` (**logic**) |
| **g.** Contre-audit anti-triche | un fichier par menace, écrit comme une attaque | `RedTeam_Chase.spec` (capture téléportée, de loin, `tClient` truqué : futur, trop ancien, `NaN` ; rafale de faux `Leap` ≤ 12 studs par 4 s), `RedTeam_Boop.spec` et **`RedTeam_Event.spec`** (v1.2, remarque A22 : `MegaPress` à 25 studs, plus vite que 0,4 s, `tClient` truqué, hors de la phase de pression ; `GrandSplorch` hors du ranch, en portant, `flyer` d'un autre ou au Dodo, double entrée dans la file, pendant une fuite ; `AdminCommand` d'un non-administrateur : aucune réponse, aucune mutation) (**chase**), `RedTeam_Fence.spec`, `RedTeam_Press.spec` (dont portée à plat et pieds, monture), `RedTeam_Purchase.spec` (**ranch**), `RedTeam_Social.spec` (**meta** : pet-sitting (plafonds 100 / 100 / 20 par ami, second compte), applaudissements, rapports, `FeedPlop` de loin et deux fois le même jour, `ClientEvent` en rafale), specs `MoveCheck*` (socle et INT-MOVE : cavalier à chaque selle 60 s sans infraction, crédits de bond) | — |
| **h.** Zéro trace | pendant **chaque** spec, toute erreur ou tout avertissement imprévu la fait échouer ; un avertissement attendu est déclaré (`expectWarning(motif)`) et doit arriver | toutes les specs du jeu | **Crochets du harnais (faits par le contrat, INT-HARNESS)** : `task.spawn/defer/delay` du code monté enveloppent la fonction dans `xpcall` ; une erreur (handler de `Shared/Util/Signal`, écriture DataStore en `task.spawn`…) va dans `h.errors` (préfixe `[thread]`) et déclenche `ScriptContext.Error(message, trace)` et `LogService.MessageOut(message, MessageError)` ; `warn` déclenche `MessageOut(…, MessageWarning)` ; `ScriptContext`, `LogService` (`GetLogHistory`), `Stats`, `CaptureService`, `UserService` sont simulés ; `Harness.live()` rend les harnais vivants. `Harness.spec` prouve qu'une erreur dans un handler arrive dans `h.errors`. **`tests/harness/ZeroLog.luau` (meta)** : `ZeroLog.wrap(T)` (idempotent) rend un `T` dont `it` vérifie, après le test, `h.errors` et `h:warnings()` de chaque harnais de `Harness.live()` créé pendant le test ; `T.expectWarning(motif)` ; `ZeroLog.forSpec(chemin, T)` rend `T` tel quel pour les specs du socle (liste `ZeroLog.SOCLE`) et `ZeroLog.wrap(T)` sinon. `tests/run.luau` l'applique **automatiquement** dès que le fichier existe (déjà branché par le contrat). `ZeroLog.spec` prouve qu'une erreur dans un handler lancé fait échouer un test enveloppé et qu'un avertissement imprévu aussi |
| **i.** Vrai moteur Roblox (prêt, lancé plus tard) | la suite des tests serveur **portables** tourne **dans de vrais serveurs Roblox** | `tests/engine/*.spec.luau` (**meta**) | **Format** : une spec du moteur est un module qui rend `function(T)` et n'utilise que `T.describe`, `T.it`, `T.expect` (injectés par le lanceur) et `T.require("ReplicatedStorage.Shared.Logic.Formulas")` (résolveur vers la vraie instance) ; **aucun** `@lune/*`, aucun `Harness`, aucun `Bots` (`Contract_game.spec` refuse `@lune` dans `tests/engine`). **Paquetage** : projet Rojo à part `tests/engine.project.json` = `src` + `tests/engine` + un petit lanceur sous `ServerStorage.EngineTests` ; c'est cette place qui est publiée, jamais `default.project.json`. **Portée** : toutes les specs de `Shared/Logic` (cas exacts + propriétés avec N réduit), intégrité de Config / Strings / Sounds, démarrage de `Main.server` avec zéro `ScriptContext.Error`, `WorldService.build` + invariants de `WorldBuild`, aller-retour DataStore sur un magasin de test dédié (`EngineTest_v1`), `ApiAudit` des instances construites. **Outil** `tools/opencloud/run-server-tests.luau` (Lune) : construit la place de test (Rojo), la publie comme nouvelle version d'une **place de test privée** (`POST /universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved`, en-tête `x-api-key`), crée une tâche `POST /cloud/v2/universes/{u}/places/{p}/versions/{v}/luau-execution-session-tasks` (script : le lanceur, qui rend le bilan en JSON, `timeout` 300 s), attend l'état `COMPLETE` / `FAILED`, lit les journaux (`…/tasks/{task}/logs`), échoue si un test échoue ou si une ligne Error / Warning apparaît. Clé d'API et identifiants par variables d'environnement (`ROBLOX_API_KEY`, `UNIVERSE_ID`, `PLACE_ID`), **jamais dans le dépôt** ; sans clé : message clair et code 2 (« non lancé »). `OpenCloud.spec` vérifie la construction des requêtes, le code 2 sans clé et que chaque spec de `tests/engine` se charge et passe aussi sous Lune avec un `T` minimal. `tools/opencloud/README.md` explique la mise en route (**meta**) |
| **j.** Diagnostics en ligne | ce qui échappe à tout cela est compté en ligne et montré aux administrateurs ; chaque erreur vue en ligne devient d'abord un test qui la reproduit | `Diagnostics.spec` (nettoyage des noms, plafonds, fusion des clés, silence pour un non-administrateur, taille du paquet, écriture groupée), `ErrorReporter.spec`, `Panels_Diagnostics.spec` | — |

Plus : `WorldBuild.spec` (world : tout ancré, `CanTouch = false`, solides = boîtes de `WorldLayout`, aucune fente, ≤ 4 500 pièces), `Contract_game.spec` (contrat, dont le projet Rojo : `StreamingEnabled = false`, `VirtualCursorMode = Disabled`, `Technology = ShadowMap`), `Activity.spec` (contrat), les specs de services (`EconomyService`, `SquishyService`, `RanchService`, `QuestService`, `CommunityService`, `EventService`, `RushService`, `SplorchService`, `ChaseService`, `ProductService`, `LeaderboardService`), `Wire` (sérialisation) et `ApiAudit` (API Roblox) du socle, et les **tests manuels M1 à M18** du GDD §18 (Studio, vraie PS5, PS4 ou Xbox One, 16 vrais joueurs). Leur liste pas à pas (préparation, entrées, résultat attendu, où regarder dans Diagnostics, section PS5 / PS4) vit dans **`docs/05-guide-publication.md`, propriété du paquet meta**, à livrer avec le paquet (remarque A28), et dans `tools/opencloud/README.md` pour la partie Open Cloud.

### 17.2 Invariants vérifiés à chaque tick du robot de longue durée

1. Pièces, Pot, Fame, tailles : finis, ≥ 0, ≤ 1e300 (`Invariants.number`).
2. Chaque uid existe une fois, à un seul endroit (`pen`, `pool`, `dodo`, `mail`), chez un seul propriétaire ; aucun squishy porté, en fuite ou en attente n'est ailleurs que dans son profil.
3. Capacités : `pen + pool ≤ penCapacity`, `pool ≤ poolSlots`, `dodo ≤ 60`, `mail ≤ 20`.
4. Un seul squishy par emplacement de Meilleur Ami ; pour chaque tenue, porteurs (`squishies[uid].o == id`) ≤ `owned[id]` ; `outfits.worn` vide.
5. Tableaux `dex.mut`, `dex.stars`, `trophies`, `dex.fam` denses ; `gd` entier ≥ 0.
6. Aucun état ouvert au-delà de son délai : pour chaque entrée de `X.openStates()` (RanchService, SquishyService, QuestService, CommunityService, EventService, RushService, SplorchService, ChaseService), `StateTimeouts.expired(name, startedAt, now) == false` (maintiens, portage, créatures, spectacles, fêtes, carte du choix, fenêtres d'applaudissement, arrivée).
7. Plafonds journaliers respectés (dont `petSitIn`, `splorchCoins` et `petSitBy[ami]` ≤ 20) ; jamais plus de 10 fuites du Rush sur le serveur, 2 par ranch et par Rush, 4 par heure ; aucune Wobble Party pendant la sieste de Big Plop ; aucun squishy à la clôture pour un joueur en file de Grand Splorch.
8. Instances serveur et connexions stables (± 5 %) après la mise en route (`Harness:counts()`, handlers des `Signals`) ; temps du tick : < 10 ms en moyenne sous Lune (porte de la spec), < 3 ms visé dans le moteur.
9. `DiagnosticsService.counts().errors == 0` et `warnings == 0`.

### 17.3 Angles morts du harnais Lune et règle de conception qui les supprime ou les contient

| Angle mort hors ligne | Risque | Règle de conception (contrat) | Filet |
|---|---|---|---|
| **Physique** (collisions, frottement, `Touched`, personnages qui se poussent) | achats ratés ou doublés, joueur coincé, bond qui rebondit, joueur sur un toit pris pour un tricheur | aucune règle ne lit la physique : zones et distances sur la position validée (`ZoneRules`) ; sol des règles = `WorldLayout.supportY` (pur, jamais un Blockcast) ; bond **scripté** sur un arc fixe et capture calculée sur `LeapRules.landing` ; décor ancré et non solide sauf la liste des solides ; solides plus hauts que toute portée (30 studs) ; aucune collision entre personnages ; solides sans recoin (6 studs ou collés) | `WorldBuild.spec`, `RedTeam_Fence.spec` ; tests manuels M3, M10 |
| **Rendu** (ce qui se voit vraiment à l'écran, images par seconde) | effets trop lourds sur PS4, clignotements | budgets nommés (`QualityController.budgets`), réserves d'instances, LOD, `stats()` de chaque renderer vérifiées par specs ; qualité adaptative ; aucun clignotement au-dessus de 3 Hz | M2, M6, M8 sur vraie console |
| **Délais de réplication** (ordre et retard des messages, attributs pas encore arrivés) | état faux chez le client, créature fantôme | messages numérotés et `RequestWorld` sur un trou ; créatures et maintiens qui finissent tout seuls à leur heure ; phases recalculées par `EventClock` ; les effets ne se jouent qu'après la réponse du serveur ; jamais d'attente sur un attribut pour une règle | M10 (latence 250 ms), M18 (coupure de 20 s) |
| **Streaming** (objets pas encore chargés) | `WaitForChild` infini, ranch absent | `StreamingEnabled = false` ; positions de jeu dans `WorldLayout` ; `WaitForChild` client toujours avec délai et repli | `Contract_game` vérifie `default.project.json` (`StreamingEnabled = false`, `VirtualCursorMode = Disabled`, `Technology = ShadowMap`) ; `scripts/verify-place.luau` vérifie la place construite (note INT-PREPUBLISH) ; M18 |
| **États du Humanoid** (mort, assis, nage, chute, `HipHeight`) | portage ou monture bloqués | portage et monture = états du serveur terminés par 6 événements ; seules `WalkSpeed`, `JumpHeight`, `HipHeight` sont réglées ; personnage `nil` toléré partout ; placement par le serveur à chaque apparition | M3, M18 |
| **Mise en page réelle du texte** (polices, `TextScaled`, langues) | texte coupé ou trop petit sur une télé | marge de 25 % pour le français ; `TextScaled` + minimum 28 px TV ; textes du monde en `BillboardGui` à pixels fixes (`UI/WorldText`, taille projetée ≥ 28 px TV à 20 studs) ; `TvAudit.clipped` estime la largeur des textes (approximation documentée) ; libellés courts | M7 (3 résolutions, 2 langues, vraie télé 4K), M11 |
| **API du moteur** (propriétés mal écrites, comportements de `MarketplaceService`, `PolicyService`, `CaptureService`, `HapticService`, `TextChatService`) | erreur en ligne seulement | `ApiAudit` confronte chaque classe et propriété à la base de réflexion ; chaque appel de service externe sous `pcall` avec repli silencieux (pas de capture sur console → pas de case « Filmer ») ; Open Cloud (couche i) exécute la suite serveur dans le vrai moteur | M5, M11, M17, couche i |
| **DataStores réels** (quotas, latence, verrous entre serveurs) | perte de données | `DataService` durci du socle ; `Chaos` (couche e) ; sauvegarde immédiate après un achat et un Grand Splorch | M4, couche i |
| **Entrées réelles** (DualSense, TV en mode Jeu coupé, AZERTY) | PERFECT injouable, glyphe faux, menu inaccessible au clavier AZERTY | fenêtre PERFECT décalée vers le tard ; aucune combinaison de touches ; glyphes par `GetImageForKeyCode` / `GetStringForKeyCode` ; menu sur `KeyCode.M` **et** `KeyCode.Semicolon`, jamais Tab ; aucune touche liée derrière une fenêtre | M1, M9, M11, M16 |
| **Latence réelle** (ping de 100 à 250 ms, positions et messages dans le désordre) | captures perdues par les joueurs loin du serveur, joueur qui ne peut plus agir après un bond | captures vérifiées à l'instant `tClient` (`MoveCheck.positionAt`) ; crédit de bond `MoveCheck.grant` rétroactif | `Chase.spec` à 0, 100, 250 ms ; M10 |

---

## 18. Plan de tests par paquet et specs d'intégration

### 18.1 Conventions

- Commandes : `~/.cargo/bin/stylua <fichiers>`, `~/.cargo/bin/selene src` (0 erreur, 0 avertissement), `~/.cargo/bin/lune run tests/run -- <filtre>`, puis toute la suite `~/.cargo/bin/lune run tests/run` et `./scripts/check.sh`.
- Chaque spec du jeu reçoit un `T` enveloppé par `ZeroLog` (`tests/run.luau` l'applique dès que `tests/harness/ZeroLog.luau` existe ; une spec peut aussi écrire `T = ZeroLog.wrap(T)`, idempotent ; d'ici là, chaque test vérifie `#h.errors == 0` et `#h:warnings() == 0`). Depuis la v1.1, `h.errors` contient aussi les erreurs des threads lancés (handlers de signaux compris).
- Temps : `Clock.freeze(t)` et `Clock.advance(dt)` sur le harnais, `Bots.fakeOsClock` pour `RateLimit` ; jamais d'attente réelle longue.
- Isolation : une spec peut **remplacer une fonction d'une dépendance** (y compris un stub `TODO` d'un autre paquet) avant `h:boot()` ou avant l'appel testé.
- Tick : `ChaseService.tick(now)` directement ; services : `X.step(now, acteurs)` avec des acteurs construits à la main.
- Couverture minimale de chaque paquet : chemins heureux ; cas limites ; **charges hostiles** sur chacune de ses intentions (`Fuzz`) ; **cycle de vie** (arrivée avant / après le démarrage, départ, réapparition, personnage absent, départ pendant un yield) ; **délais** de chacun de ses états (`StateTimeouts`).
- Ne jamais supprimer ni affaiblir un test existant (dont `Contract.spec` et `Contract_game.spec`).

### 18.2 Specs à écrire par paquet

| Paquet | Specs (au moins) | Outils du harnais |
|---|---|---|
| **logic** | `<Module>.spec` + `Props_<Module>.spec` pour les 19 modules ; `EventClock.spec` (instants clés, 100 000 créneaux, ≥ 20 s entre deux grands spectacles) ; `SeededPath.spec` (10 000 trajets dans le graphe, hors ranchs) ; `Odds.spec` (1 million de tirages, ±3 σ) ; `EconomyPacing.spec` (porte) | `Props` (à écrire), `Sim` (socle), `EconomyModel` (à écrire) |
| **world** | `WorldBuild.spec` (dont : chaque boîte solide ≥ `Const.SolidMinHeight`, coiffes des maisons), `SquishyBuilder.spec` (12 pièces au plus, chaque espèce et mutation, LOD, réserve), `Squash.spec`, `Palette.spec`, `LightingController.spec` (préréglages, version discrète, aucun ciel de Lune ni costume si l'interrupteur du serveur est coupé), écran de chargement (specs du socle gardées vertes, `Loading_game.spec` : habillage en px TV, plus de mise en page de téléphone) | `ApiAudit`, `MockInstance` |
| **ranch** | `RanchService.spec` (dont : sans HumanoidRootPart, PlayerReady à 15 s), `EconomyService.spec` (règlement exact ; N règlements = 1 ; 100 refus de `BuyTile` = 0 pièce de plus ; rebase hors ligne avant tout règlement ; boosts non cumulés ; Grand Splorch d'un bloc), `SquishyService.spec` (Cuve, protections, Bassin, combos, Tout fusionner, vente, relâche, monture et `setRootOffset`, squishy retiré de la clôture dès qu'il quitte l'enclos), `ProductService.spec` (reçu rejoué, Squish Party refusée si active, paquets cachés, acheteur parti pendant la fête → `boosts.personalLeft ≥ 600` dans le profil sauvegardé), `ProfileRepair.spec`, `DataChaos.spec` (`Invariants.dense` après chaque écriture), `Remotes_Ranch.spec`, `RedTeam_Fence.spec` (dont : saut de la selle géante contre le mur de clôture, aucun toit atteignable, joueur honnête jamais signalé), `RedTeam_Press.spec`, `RedTeam_Purchase.spec` | `Chaos` (à écrire), `Fuzz`, `Bots` |
| **chase** | `ChaseService.spec` (tick, créatures, bonds, captures, délais, sol `supportY`), `RushService.spec` (chaque protection, carte du choix et son délai via `UiSeen`, Cozy immédiat, `extendHold` une fois), `EventService.spec` (phases idempotentes, MEGA, jauge à source unique : un Grand Splorch = +25 exactement, file des spectacles, LiveOps et renvoi d'`EventState` à chaque interrupteur, `"clock"` ignorée hors Studio), `SplorchService.spec` (file garantie, départ avant son tour, cadeaux et plafonds, `Splorched` avec le nombre de cadeaux), `Remotes_Chase.spec`, `RedTeam_Chase.spec`, `RedTeam_Boop.spec` (dont : squishy pris pendant un maintien → annulé ; rangé au Dodo pendant un maintien → annulé), specs MoveCheck de la note INT-MOVE (monture sans faux positif, décalage qui ne permet aucun vol) | `Soak`, `Brains` (à écrire), `Bots`, `Fuzz` |
| **meta** | `QuestService.spec` (accueil sans blocage, étape 10 par `UiSeen`, objectifs, minuit en session, bol, `FriendsChanged`), `CommunityService.spec` (amis et `FriendsChanged`, pet-sitting : `PetSitRewarded` seulement sous le plafond, bannières, réglages, `unlockSession`), `LeaderboardService.spec` (égalités, bannis, semaine, nom caché d'un joueur d'un autre serveur → `name = ""`, panne de UserService → `name = ""`), `Diagnostics.spec` (dont « bonjour » aux seuls administrateurs), `ErrorReporter.spec` (file bornée au débit, `entries`, `stats`, `testError`), `Remotes_Meta.spec`, `RedTeam_Social.spec`, `ZeroLog.spec`, `Fuzz.spec`, `OpenCloud.spec` (le script se charge, sans clé il rend 2, construit la bonne requête, specs de `tests/engine` portables) | `ZeroLog`, `Fuzz` (à écrire) |
| **client-world** | `WorldStateController.spec` (trous de suite : deux trous en 1 s convergent, `RequestWorld` renvoyé toutes les 3 s ; fin sans message), `RanchRenderer.spec` (LOD, budgets, personnage absent, cosmétiques publics et titre ≤ 150 studs), `ChaseRenderer.spec`, `VFXController.spec` (budgets, Mouvement réduit, Graphismes légers, clips : appareil sans capture → aucune case et aucun avertissement, arrêt à 8 s ; aucun effet d'événement coupé par interrupteur), `CameraController.spec`, `PromptController.spec` (prêts d'abord, hystérésis, verrou pendant un maintien, aucune cible derrière une fenêtre), `ChaseController.spec` (arc, solides, tampon), `QualityController.spec` | `Wire`, `Layout`, `ApiAudit` |
| **client-hud** | `HUD.spec` (pastille sans MEGA si `megaSquish` est faux, `clapHero`), `Banners.spec`, `Cards.spec` (une seule carte, ordre, garde de 0,6 s, 20 s → Cozy, `Requested`, aucune touche liée), `ScreenFX.spec`, `Prompt.spec`, `InputController.spec` (liaisons, seul à lier △, touches déliées derrière une fenêtre, jamais Échap / L3 / R3, croix → = Clap pendant la fenêtre), `OnboardingController.spec` (90 s, reprise) ; `Console_hud.spec` (dont : carte « booped » atteinte par △ → ✕ → « Pas ce joueur ») et `Layout_hud.spec` aux 3 résolutions | `Gamepad`, `Layout`, `TvAudit` |
| **client-panels** | `FocusGuard.spec` (8 règles), `PanelController.spec` (règle des 3 touches, L1 / R1, L2 / R2, `Cards.Requested`, `setNavigator` avant `build`), `ReturnScreen.spec`, `Panels_<Nom>.spec` pour les 9 panneaux (Ranch : onglet Style ; Diagnostics : visible après le « bonjour », onglet Outils ; Settings : Clips caché si `ClipsUnavailable`) ; `Console_panels.spec` et `Layout_panels.spec` aux 3 résolutions, EN et FR ; `TvAudit.spec` | `TvAudit` (à écrire), `Gamepad`, `Layout` |

**Ajouts du contrat v1.2 par paquet** (en plus du tableau ; chaque ligne correspond à une note du §25) :
- **logic** : specs aux valeurs du GDD v1.3 (`Formulas` : `RScale`, `offlineGrowth` avec arrêt à 90 %, `babySize` 0,5, cibles 1,1e12 / 2,9e12 ; `RushRules.babyMutation` ; `ZoneRules.distXZ` / `feetY` ; `QuestRules.familyEarned` ; `EventClock.megaSpecies` sur les espèces publiées avec 27, 30 et 64 espèces ; `StateTimeouts` nouveaux états ; `BigNumber` suffixes FR = EN ; `PressTiming` +0,18 / +0,22 / −0,08 / −0,10 s ; `WorldLayout.spec` règle des 8 studs et rangée Z = 67 ; `Invariants` tenues dérivées, `dex.fam`, `petSitBy`) ; `EconomyPacing` refaite (§16) ; `Balance.GddValues = "1.3"`.
- **world** : `WorldBuild.spec` avec les prises de dalles à Z = 67 (suit `WorldLayout.padSocket`) et les décorations déplacées ; aucun texte à lire posé au sol dans le monde construit (les étiquettes sont du client, `UI/WorldText`).
- **ranch** : `RanchService.spec` (attente de 0,6 s, une fois par entrée, annulée en portant ou dans un autre maintien, `HoldState` « tile », `onPad`, achat au premier tick où les pièces suffisent (A24), clôtures dans les deux ordres Rush / pet-sitting (A25), `best.s = 0`) ; `EconomyService.spec` (déclencheurs de `refresh` : trophée, page dorée, famille, Fame ; P et B une seule fois ; rebase 30 % arrêté à 90 % ; `consumeFriendCap`) ; `SquishyService.spec` (Cuve → enclos puis Dodo, `pending` seulement si les deux sont pleins ; `growFor` une fois par jour (`gd`) ; `setRootOffset` à 3 arguments ; `EquipOutfit` compte les porteurs ; `MoveSquishy` du squishy en attente refusé (A26) ; `anyEscaping`, `waiting`) ; `ProductService.spec` (reçu pendant une fête → + 600 s ; départ de l'acheteur ; reçu, fermeture, nouveau serveur → boost présent exactement une fois ; plus de paquets) ; `ProfileRepair.spec` / `Schema_game.spec` (`gd`, `dex.fam`, `outfits.worn` vidé, `petSitBy`, 64 espèces jamais tronquées).
- **chase** : `ChaseService.spec` (captures à `tClient` à 0, 100, 250 ms ; bond puis capture au tick suivant ; deux bonds à 2 s ; Héros + 1 h une fois par jour ; bébé du Rush ≤ 0,5 × le plus gros, mutation > ×5 tirée ; `MoveCheck.clear` au départ) ; `EventService.spec` (joueurs actifs et N du MEGA / de la jauge, sieste de 20 min, pression ordinaire = 0 point, fête prolongée de 600 s, `partyUnplayed`, `moon.lastSession` d'un serveur à l'autre, héros parti avant l'éclatement : spectacle effacé, place et attente prévue des entrées de la file, coupure à 480 s) ; `SplorchService.spec` (refus pendant une fuite, spectacle complet au plus toutes les 180 s par spectateur, `ClapPrompt` aux seuls spectateurs du spectacle complet, 10 cadeaux en pièces puis 10 s) ; `RushService.spec` (aucune clôture pour un joueur en file) ; `RedTeam_Event.spec` (A22) ; specs MoveCheck de la note INT-MOVE (`grant`, `positionAt`, cavalier à chaque selle).
- **meta** : `CommunityService.spec` (plafonds de pet-sitting 100 / 100 / 20 par ami, 2 s de revenu, `PetSitRewarded` à 3 arguments, `openClapWindow` avec spectateurs) ; `LeaderboardService.spec` (valeur codée : égalités au premier arrivé, valeur maximale ≈ 1,05e12, décodage) ; `QuestService.spec` (bol en 2 s, objectifs sans boost, `dex.fam` posé au tampon qui complète la famille) ; `Diagnostics.spec` (`ClientEvent` : 20 par session, analytique seulement) ; `Analytics_game.spec` (note INT-ANALYTICS : cumul par joueur, tranche de 5 min et `itemSku`, ≤ 10 requêtes par joueur et par minute sur un serveur simulé de 16 joueurs) ; `RedTeam_Social.spec` (`FeedPlop` de loin et deux fois par jour, A22) ; `docs/05-guide-publication.md` (A28).
- **client-world** : `VFXController.spec` (carte du clip seulement après un `StartVideoCaptureAsync` réussi ; version courte du Grand Splorch sans capsule ni vibration ; `pressTick` seulement sur un PERFECT du MEGA) ; `QualityController.spec` et le `stats()` de chaque rendu dans son quota (A23) ; `WorldStateController.spec` (`ReportBlocked` une fois, liste vide si `GetCore` lève ; `best.s = 0`) ; `RanchRenderer.spec` (étiquettes des dalles par `UI/WorldText`, bulle « Boîte à dodo ! »).
- **client-hud** : `WorldText.spec` (Offset × UIScale, `LightInfluence = 0`, taille projetée ≥ 28 px TV à 20 studs aux 3 résolutions, bornage à la zone sûre) ; `HUD.spec` (2 flèches au plus, jauge grise pendant la sieste, place et attente dans la file, `squishyBack`, APPLAUDIR caché en poursuite, maintien ou fenêtre) ; `InputController.spec` (M et Semicolon, jamais Tab, G C J L B P, sac à objets coupé sous `pcall` avec nouveaux essais, ○ ferme le menu avant de poser) ; `Console_hud.spec` / `Layout_hud.spec` (textes du monde).
- **client-panels** : `Panels_Squishydex.spec` (grille par famille, fiche 3 × 3, plus d'onglets Mutations ni Étoiles) ; `Panels_Shop.spec` (onglets Passes / Fête / Tenues, articles `hidden` absents, `ClientEvent("shopOpened")`) ; `Panels_Ranch.spec` (○ vide d'abord une sélection multiple dans Vendre / Relâcher) ; `Panels_SplorchPreview.spec` (plus de 2e confirmation).

### 18.3 Specs d'intégration (étape d'intégration, après les 8 paquets)

- **`Boot.spec`** : serveur complet, **16 joueurs** (`Bots` + `Brains`) ; accueil complet d'un nouveau (pression à ~10 s, Tapis, Cuve, fusion, Pot, capture, premier tirage, démonstration, balade, objectifs) ; Rush, MEGA, Golden, Jelly Moon et Grand Splorch par voyage dans le temps ; réapparitions, départs et retours (profil persisté) ; joueurs présents avant le démarrage ; départ pendant le chargement ; fermeture (`BindToClose`) ; tous les envois passent par `Wire` ; chaque `Feedback`, bannière et célébration est vérifié contre `Strings` (EN et FR, variables comprises) ; `ApiAudit` ; zéro trace.
- **`Soak.spec`** : 16 robots, `SOAK_HOURS` heures de temps simulé (0,5 h dans `check.sh`, **6 h** dans `scripts/soak.sh`), invariants à chaque tick (§17.2), instances et connexions stables, ≤ 10 ms par tick en moyenne sous Lune.
- **`ClientReplay.spec`** : un vrai serveur joue une partie ; tout ce qu'il envoie à un joueur (remotes, attributs, position) est enregistré puis rejoué dans le vrai client (`Main.client`, `console = true`) au même instant ; aux points de contrôle, le miroir du client (ranchs, créatures, événements, profil) égale l'état du serveur sans `RequestWorld` ; puis `TvAudit.run` en 1080p, 4K et 720p, EN puis FR : chaque écran atteint avec la croix, ✕ et ○, aucune faute de disposition ; les intentions produites sont livrées au vrai serveur. Variante : arrivée en cours de partie (pendant un Rush, un MEGA, le Grand Splorch d'un autre) ; variante clavier-souris ; variante interrupteurs coupés en direct (`MegaSquish = false` : aucune bannière ni pastille MEGA ; `GoldenWobbler = false`, `JellyMoon = false` : idem) ; variante héros parti pendant son spectacle avant l'éclatement (spectacle arrêté, aucune pluie de cadeaux, A26). Budgets mesurés (remarque A23) : objets d'interface (`GuiObject`) ≤ 3 000 à chaque point de contrôle ; octets par seconde des charges enregistrées par `Wire` ≤ 8 Ko/s en moyenne, pic < 40 Ko/s (arrivée).

---

## 19. Localisation et sons

- `Shared/Localization/Strings.luau` contient **toutes les clés prévisibles** du jeu (762 au contrat v1.2 : + `feedback.waitEscape`, `hud.gauge.rest`, `hud.queue.next` / `place`, `world.vat.dodo`, `celebrate.giftShort`, `return.nearly`, `panel.dex.sheet.*` ; bannières FR « 1 000 MILLIARDS » ; onglet « Fête »), en anglais et en français, par domaine : `common`, `name`, `kick`, `device`, `settings`, `hud`, `prompt`, `onboarding`, `menu`, `panel.ranch`, `pad`, `decor`, `rarity`, `mutation`, `family`, `species` (noms en anglais dans les deux langues, description traduite), `panel.dex`, `panel.goals`, `objective`, `plop.reward`, `panel.lb`, `panel.shop`, `shop.pass`, `shop.product`, `panel.splorch`, `panel.diag`, `return`, `card`, `feedback`, `banner`, `celebrate`, `num` (mots entiers des grands nombres), `event`, `world`, `emote`, `cosmetic`. Un paquet qui a besoin d'une clé de plus l'**ajoute** (registre partagé, EN + FR, mêmes variables).
- Libellés français courts dès le départ (marge de 25 %). Une consigne : glyphe + mot court (4 mots au plus). Les nombres passent par `BigNumber` (suffixes et séparateurs de chaque langue). L'alias du nom caché : `name.alias` avec `Hash.alias(userId)`.
- Sons : `Config/Sounds` (registre partagé). Les 8 sons d'interface ont leur ID officiel (Roblox/resources). Les **53 clés de jeu** ont un ID vide (muettes) : chaque son se cherche dans les dépôts officiels Roblox/resources et Roblox/creator-docs (candidats et replis : GDD §9.6), s'écoute dans Studio, puis est rempli avec sa provenance **sur sa ligne** (`Contract.spec` le vérifie). Le jeu est entièrement jouable sans aucun son. Musiques `MusicMoon` et `MusicRush` : note INT-AUDIO.

---

## 20. Décisions d'interprétation du GDD

1. **Croissance cumulée du ranch** (§8.3) au lieu de `zAt` par squishy : un seul propriétaire par clé, aucune réécriture des tailles quand g change, Pot exact, G remis à 0 au Grand Splorch (précision).
2. **Noms des configurations** : `Config/Species` (GDD : `Squishies`) et `Config/Pads` (dalles) selon la fiche de mission ; `Config/Vat` est fondu dans `Balance.Vat` (leviers de la simulation) ; `Config/Layout` et `Config/Intents` sont nouveaux.
3. **Paquets et services** : les services du GDD §12.2 sont répartis ainsi : ranch = RanchService, EconomyService, SquishyService, ProductService (+ ProfileRepair) ; chase = ChaseService, RushService, EventService, **SplorchService** (le Grand Splorch est un spectacle de serveur ; l'application au profil passe par l'API de ranch) ; meta = QuestService, **CommunityService** (social du GDD), LeaderboardService, DiagnosticsService, ErrorReporter. Le module de la fiche nommé « Rolls » s'appelle `Odds` (GDD). Les promo codes de la fiche sont retirés : **pas de codes au lancement** (GDD Annexe A, aucun champ de texte).
4. **Carte « Plop a sommeil »** dans la file unique des cartes de client-hud (`UI/Cards`), et non dans client-panels : une seule file = jamais deux cartes à l'écran. L'écran de retour reste dans client-panels (fenêtre bloquante de FocusGuard).
5. **Accueil de la Cuve** : deux naissances scriptées (jumeau à 0:40, premier tirage à 2:45), puis la Cuve normale à 5:00 de jeu. La phrase « une goutte toutes les 90 s » du GDD §4.9 décrit cet espacement ; la simulation vérifie la cible de 3 à 4 squishies à 5:00.
6. **Premier Meilleur Ami** : le tout premier squishy du compte (`nextUid == 1`, le Plop donné par Big Plop) reçoit `bf = 1` dans `SquishyService.give`.
7. **Pet-sitting** : intention dédiée `PetPress(ownerId, uid, tClient)` (les uids ne sont uniques que par profil) ; les clôtures du Rush et du pet-sitting partagent `RanchService.setFence` (le Rush passe avant).
8. **Cosmétiques équipés** : clé `cosmetics` et intention `EquipCosmetic` (le GDD les décrit sans clé ni remote).
9. **`stats.biggestEver`** devient la clé `biggestEver` de SquishyService (un seul propriétaire de `stats` : QuestService).
10. **`runaway.nextAt`** n'est pas sauvegardé : minuteur de session de ChaseService (repart à 60 s).
11. **`SetInputType.kind`** suit l'encodage du socle (`Platform.inputKind()` : 1 tactile, 2 clavier-souris, 3 manette) et non celui du GDD §12.7.
12. **`flags`** garde le champ du socle `lbBanned` (toujours `false`, exigé par `Contract.spec`) à côté de `lbBanUntil`.
13. **Traînée « Bulles roses »** (Nourrir Plop, jour 5) est distincte de « Bulles » (Squishydex 50) : 9 traînées au lieu des 8 du GDD §5.5.
14. **Bond accordé** (remplacé en v1.2, GDD v1.3 §12.8) : `MoveCheck.grant(player, 12, 0,35, tClient)` (note INT-MOVE) crédite 12 studs sur 0,35 s au plafond par tick, au budget d'action et à la fenêtre soutenue d'1 s, rétroactif jusqu'à 0,3 s avant la réception, un au plus toutes les 4 s (horloge du serveur). `noteSpeed(GrantSpeed)` laissait une dette d'environ 4,8 studs : le joueur ne pouvait plus attraper pendant 0,6 s, au moment exact où il appuyait sur □. `Balance.Leap.GrantSpeed` est retiré.
15. **Capture à l'atterrissage** : `canAct` est exigé au **départ** du bond (la dette du bond lui-même ne l'annule pas).
16. **`MegaBeat`** est un remote non fiable (battement purement visuel à 4 Hz).
17. **Commandes de développement** : intention `AdminCommand` réservée aux administrateurs (forcer un Rush ou un MEGA, décaler l'horloge en Studio, erreur de test du serveur ou du client, mode photo, fête), envoyée par l'onglet Outils du panneau Diagnostics (console : ni chat ni champ de texte), utile aux tests manuels M1 et M17 et aux vignettes.
18. **Bannières d'événement** (sirène, MEGA, Lune) calculées par le client avec `EventClock`, jamais envoyées par le serveur, mais **réglées par les interrupteurs du serveur** reçus dans `EventState.features`.
19. **Statue et fanfares** dans LeaderboardService (tableau du serveur en direct).
20. **Paquets de pièces : retirés du lancement** (renversé en v1.2, GDD v1.3 §8.3, question 1 tranchée) : `CoinsSmall` et `CoinsBig` restent dans `Config/Monetization` avec l'id 0 et `hidden = true`, sans handler ; plus de `coinBuy`, de `noteCoinBuy`, de `PolicyNoCoins` ni de 2e confirmation du Grand Splorch ; champ réservé `packs` pour un retour éventuel (porte-monnaie « Pièces de côté », devis du serveur).
21. **Hauteur des solides** : murs invisibles des clôtures et du bord, et coiffe des maisons à **30 studs**, au-dessus de la plus haute portée (saut de la selle géante 13 + décalage de racine 6). Aucun « toit » n'existe donc pour les règles. Le GDD v1.3 (§11.1, §11.2) est désormais aligné sur 30 studs (la v1.2 du GDD disait 12).
22. **Pas de `lastSettle`** : le règlement du Pot intègre [`growth.t` ; now] (deux `Clock.now()`) ; le champ entier recomptait jusqu'à 1 s par règlement (exploitable par des refus d'achat en rafale).
23. **`UiSeen(screen)`** : intention pour les faits que seul le client connaît (étape 10 de l'accueil « objectifs vus », départ du délai de la carte du choix pour `RushModeChosen = −1`) ; liste fermée, une fois par session, ne donne jamais rien.
24. **Valeur codée des classements** (remplacée en v1.2, GDD v1.3 §6.9) : `((score × 2^20) + (2^20 − 1 − secondes depuis lundi 00:00 UTC)) × 2 + caché`, décodée à la lecture : égalité au premier arrivé et nom caché dans un seul entier (≈ 1,05e12 au plus, sous 2^53) ; caché ou inconnu → alias.
25. **`AdminCommand "clock"` en Studio seulement** : un serveur privé écrit le vrai magasin `PlayerData_v1` ; un décalage d'horloge y corromprait les horodatages sauvegardés (plafonds, Feed Plop, Golden).
26. **Écran Style** : les cosmétiques (selles, traînées, titres, thèmes, drapeaux, tenues possédées) s'équipent dans l'onglet Style du panneau Ranch ; RanchRenderer les dessine (titre au-dessus de la tête, ≤ 150 studs).
27. **Carte « booped »** : « Pas ce joueur » vit sur une carte non bloquante (atteinte par le menu), jamais sur un Toast : chaque bouton doit être atteignable à la croix, ✕ et ○. Depuis la v1.2, aucune vibration quand un squishy s'enfuit (`squishyBack` à son retour).
28. **Joueurs actifs** (v1.2) : utilitaire `Server/Util/Activity` du contrat, appelable par tous les services (comme `RateLimit`), plutôt qu'une API d'EventService : les intentions de jeu sont acceptées par des services plus précoces qu'EventService, qui ne peuvent pas l'appeler. Le drapeau `activity = true` de `Config/Intents` rend la règle vérifiable (Contract_game). La règle de la place pendant l'alerte du MEGA reste dans `EventService.isActive`.
29. **`Balance.CapsPerFriend`** (v1.2) : le plafond « Plus serviable » par ami (`petSitPerFriend` du GDD) vit hors de `Balance.Caps`, dont chaque clé est un compteur scalaire de `caps` vérifié par `Logic/Invariants` ; son compteur est le dictionnaire `caps.petSitBy`.
30. **`outfits.worn` gardé vide** (v1.2) : la tenue portée n'est gardée que dans `squishies[uid].o` (GDD §12.6) ; le champ reste dans `Schema.defaults()` vide, jamais lu ni écrit (règle : on n'efface pas un champ du schéma), ce qui garde les invariants de logic verts jusqu'à leur note.
31. **`Balance.GddValues`** (v1.2) : marque de la version du GDD dont logic a appliqué les valeurs ; `Contract_game` vérifie les témoins de cette version (v1.2 aujourd'hui, v1.3 après les notes logic) ; la publication exige « 1.3 » (§23).
32. **`ClientEvent(kind)`** (v1.2, remarque A21) : seul transport des faits d'analytique connus du client (`qualityReduced`, `shopOpened`), propriété de DiagnosticsService, analytique seulement ; « objectifs vus » (étape 10) reste `UiSeen("objectives")`.
33. **`UI/WorldText`** (v1.2) : module-outil du paquet client-hud (il porte `UI/Prompt` et les tailles de texte), appelé aussi par client-world (RanchRenderer, VFXController) : un module sans `Init` ni `Start` peut être requis par tous, comme `UI/Juice`.
34. **`HoldState` à deux émetteurs** (v1.2) : QuestService (bol) et RanchService (attente sur une dalle) ; le champ `kind` les distingue, `tile` porte la dalle.
35. **`RanchPublic.best` toujours présent** (v1.2, remarque A27) : `s = 0` = aucune silhouette, plutôt qu'une liste `cleared` dans `RanchPatch`.
36. **`Net.setup()` après l'attach de DiagnosticsService** (v1.2, remarque A29, GDD §12.3) : Diagnostics voit aussi les erreurs de la création des remotes ; DiagnosticsService ne touche à aucun remote avant son `Init`.
37. **Croissance du Rush par `SquishyService.growFor`** (v1.2) : + 1 h / + 30 min de croissance sans boost, une fois par squishy et par jour (`gd`), au lieu de `growBy(ratio)` (cumulable à deux comptes).

---

## 21. Journal des réglages d'économie

Tenu par le paquet logic (seul autorisé à changer les **valeurs** de `Config/Balance`). Format : date, clé, avant → après, raison, médianes de la simulation avant / après.

Contrat v1.2 : le GDD v1.3 a changé des valeurs de `Config/Balance`, `Config/Events` et `Config/Quests`. Les lignes « contrat v1.2 » sont faites (clés nouvelles de `Balance`, valeurs d'`Events` et de `Quests`, fichiers du contrat) ; les lignes « note logic » attendent le paquet logic (valeurs existantes de `Balance`, avec leurs specs et la porte), qui remplit alors la colonne Résultat et passe `Balance.GddValues` à « 1.3 ».

| Date | Clé | Avant → après | Raison | Résultat |
|---|---|---|---|---|
| 01/11/2026 | `Balance.Boosts.FeedMilestone` | 900 → 300 | GDD v1.3 §7.3, §4.25 (bol : 5 min chaque jour) | logic (déjà fait) : premier Grand Splorch dans sa tolérance |
| 01/11/2026 | `Balance.Tiles.RScale` (nouvelle) | — → 3,5 | GDD v1.3 §4.6 (C3-4 : inflation des pièces) | contrat v1.2 ; `Formulas.tileCost` : note logic |
| 01/11/2026 | `Balance.Tiles.DwellSeconds` (nouvelle) | — → 0,6 | GDD v1.3 §4.6 (C2-10 : achats sans le vouloir) | contrat v1.2 |
| 01/11/2026 | `Balance.Tiles.cozyBed.Base` / `MinR` | 250 000 / 1 → 25e6 / 3 | GDD v1.3 §4.6 (C3-5) | note logic |
| 01/11/2026 | `Balance.Splorch.Unlocks` | « pad.cozyBed » à R = 1 → R = 3 | GDD v1.3 §4.15 | note logic |
| 01/11/2026 | `Balance.Splorch.Targets` | table × 2,7 → table v1.3 (15 000 … 1,1e12) | GDD v1.3 §4.15, §4.24 (C3-3) | note logic |
| 01/11/2026 | `Balance.Splorch.BeyondMult` | 2,7 → 2,6 | GDD v1.3 §4.15 | note logic |
| 01/11/2026 | `Balance.Splorch.RecentBuyWindow` / `RecentBuyShare`, `Balance.CoinPacks` | → retirés | GDD v1.3 §8.3 (C3-6 : paquets retirés) | note logic (après `splorchPreview` et `coinPack`) |
| 01/11/2026 | `Balance.Splorch.FullShowGap` (nouvelle) | — → 180 | GDD v1.3 §4.15 (C2-11) | contrat v1.2 |
| 01/11/2026 | `Balance.Offline.GrowthShare` | 0,5 → 0,3 | GDD v1.3 §4.19 (C3-5) | note logic |
| 01/11/2026 | `Balance.Offline.StopAt` (nouvelle) | — → 0,9 | GDD v1.3 §4.19 (C3-5) | contrat v1.2 ; `Formulas.offlineGrowth` : note logic |
| 01/11/2026 | `Balance.Babies.MaxOfBiggest` | 2 → 0,5 | GDD v1.3 §4.21.3, §4.25 (C3-11) | note logic |
| 01/11/2026 | `Balance.Babies.RushMutationMaxMult` (nouvelle) | — → 5 | GDD v1.3 §4.21.3 (C3-11) | contrat v1.2 ; `RushRules.babyMutation` : note logic |
| 01/11/2026 | `Balance.RushSize.HeroBonus` / `ReturnBonus` | 10 % / 5 % → `HeroGrowthSeconds` 3 600 / `ReturnGrowthSeconds` 1 800 | GDD v1.3 §4.21.3 (C3-11) | contrat v1.2 (aucune valeur lue par logic) |
| 01/11/2026 | `Balance.Caps.petSit` | 300 → 100 | GDD v1.3 §6.4 (C3-11) | note logic |
| 01/11/2026 | `Balance.Caps.petSitIn`, `splorchCoins` (nouvelles) | — → 100, 10 | GDD v1.3 §6.4, §4.15 | contrat v1.2 |
| 01/11/2026 | `Balance.CapsPerFriend.petSit` (nouvelle) | — → 20 | GDD v1.3 §6.4, §6.9 | contrat v1.2 |
| 01/11/2026 | `Balance.Rewards.PetSitVisitor` | 10 → 2 | GDD v1.3 §6.4 (C3-11) | note logic |
| 01/11/2026 | `Balance.Rewards.GiftSecondsAfterCap` (nouvelle) | — → 10 | GDD v1.3 §4.15 | contrat v1.2 |
| 01/11/2026 | `Balance.Boosts.ObjectiveMedium` / `ObjectiveHard` | 300 / 600 → 0 / 0 | GDD v1.3 §7.4 (C3-12) | note logic |
| 01/11/2026 | `Balance.Press.RangeTolerance`, `Balance.Catch.ClientPast` (nouvelles) | — → 2, 0,35 | GDD v1.3 §12.7, §12.5 | contrat v1.2 |
| 01/11/2026 | `Balance.Leap.GrantSpeed` | 36 → retirée | GDD v1.3 §12.8 (C3-8 : `MoveCheck.grant`) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.Points.press` | 1 → 0 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.TargetPerPlayer` | 500 → 600 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.RestSeconds` (nouvelle) | — → 1 200 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Activity` (nouvelle) | — → 120 s, 4 studs, 60 studs, min 1 | GDD v1.3 §4.22 (C3-18) | contrat v1.2 |
| 01/11/2026 | `Events.SplorchQueueHardCut` (nouvelle) | — → 480 | GDD v1.3 §12.10 | contrat v1.2 |
| 01/11/2026 | `Quests.Feed.Hold` | 5 → 2 | GDD v1.3 §4.20 (C2-17) | contrat v1.2 |
| 01/11/2026 | `Quests.ObjectiveRules.Rewards.medium.boost` / `hard.boost` | 300 / 600 → 0 / 0 | GDD v1.3 §7.4 (C3-12) | contrat v1.2 (`EconomyModel` ne les lisait déjà plus) |

---

## 22. Modifications du socle faites par le contrat et notes d'intégration

### 22.1 Faites par le contrat (ajouts de données, sans changement de comportement)

- `src/shared/Config/Settings.luau` : réglages du jeu `hideName`, `receiveGifts`, `clips`, `emoteLeft`, `partyShowName`, `allowRush` (serveur, propriétaire).
- `src/shared/Config/Console.luau` : les vibrations du jeu (§14.4), sans `mobile` (puis la note INT-TV, ci-dessous).
- `src/shared/Config/Sounds.luau` : 53 clés de jeu à ID vide.
- `src/shared/Config/Monetization.luau`, `src/shared/Types.luau`, `src/shared/Remotes.luau`, `src/shared/Localization/Strings.luau` (le texte `settings.vibration.desc` ne parle plus de téléphone), `src/server/Signals.luau`, `src/server/Data/Schema.luau`, `src/server/Main.server.luau` (liste ORDER, crochet `attach`), `src/client/Main.client.luau` (liste ORDER, crochet `attach`).
- `default.project.json` : `Workspace.StreamingEnabled = false` (choix délibéré, GDD §12.9), `Lighting.Technology = ShadowMap` (console la plus faible). Le reste est inchangé (`MaxPlayers = 16`, `VirtualCursorMode = Disabled`, `EnableMouseLockOption = false`, `TextChatService`).

**Étape 0 de la v1.1 (faite par le contrat avant les paquets, specs du socle mises à jour aux règles plus strictes, suite verte)** :
- **INT-TV** : `Config/Console` (référence 1920 × 1080, plancher 0,5, plus d'échelle « écran ordinaire », zone sûre 5 % partout, `BasePadding` 18 × 12, `MinTextSize` 28, `GlyphSize` 48, plus de champ `mobile`) ; `Util/Platform.uiScale` et `safePadding` : une seule règle télé sur tous les écrans (`large` sans effet) ; `UI/Root` (commentaires, même code) ; `UI/Theme` (`MinTouch` retiré, `ButtonHeight` 80, `MinTextSize` 28) ; `Util/Haptics` (plus de branche tactile) ; `UI/Toast` (tailles en px TV, texte 28-32) ; `tests/harness/Gamepad.audit` (texte < 28 px TV signalé) ; `src/first/Loading.client.luau` : seulement les constantes recopiées (`REFERENCE` 1920 × 1080, `TV_SCALE_MIN` 0,5) et le facteur `DRAWN_UNIT` qui garde son dessin à l'identique ; specs `Console`, `Fix_client_socle` mises à jour. `Platform.inputKind` garde la détection `TOUCH` seulement pour le message `device.touch` et l'analytique. `Contract_game.spec` vérifie ces valeurs et fouille `src/` à la recherche de tout chemin tactile.
- **INT-HARNESS** (étendue) : `tests/harness/Harness` (threads surveillés par `xpcall` → `h.errors`, `ScriptContext.Error`, `LogService.MessageOut` ; `warn` → `MessageOut` ; `Harness.live()` ; `h:counts()`), `tests/harness/Services` (`ScriptContext`, `LogService`, `Stats`, `CaptureService` indisponible par défaut, `UserService` ; DataStore : tableaux à trous refusés), `tests/harness/Signal` (`Signal.live`), `tests/harness/MockInstance` (événements `Error`, `MessageOut`, `Capture*`), `tests/run.luau` (applique `ZeroLog.forSpec` dès que `tests/harness/ZeroLog.luau` existe), `tests/specs/harness/Harness.spec` (6 auto-tests de ces crochets).
- `src/server/Services/DataService.luau` : crochet `DataService.onPrepare(fn)` (après `prepare`, avant l'instantané et `Loaded`, sous `pcall`).
- `scripts/soak.sh` : robot de longue durée de nuit (`SOAK_HOURS=6`).

**Étape 0 de la v1.2 (faite par le contrat, suite verte)** :
- **INT-HAPTICS** : `src/client/Util/Haptics.luau` lit le champ facultatif `cooldownExempt` d'un événement de `Config/Console.Haptics.Events` (une ligne : la sirène du Rush passe pendant le délai minimal) ; type `HapticDef` étendu ; `booped` remplacé par `squishyBack`, forces maximales de `perfect` (0,45) et `fusion` (0,65) pour des échelles ≤ 1. Test : `Contract_game.spec`.
- **INT-HARNESS v1.2** (GDD C3-21) : `tests/harness/Services.luau` simule `StarterGui:GetCore("GetBlockedUserIds")` (copie de `h.blocked[UserId du joueur local]`, `{}` par défaut, `false` = l'appel lève comme avant l'enregistrement des CoreScripts) ; `tests/harness/Harness.luau` : `h.blocked`, `h:setBlocked(joueur, liste)` ; `tests/harness/ApiAudit.luau` : entrées `StarterGui.GetCore` et `StarterGui.SetCoreGuiEnabled` (appels sous `pcall`). Test : `Contract_game.spec`.
- `src/server/Main.server.luau` : `Net.setup()` juste après le require et l'attach du premier module (DiagnosticsService), avant les autres require (remarque A29, GDD §12.3).
- `src/server/Util/Activity.luau` et `tests/specs/Activity.spec.luau` (joueurs actifs, §1 règle 18).

### 22.2 Notes d'intégration du contrat (fichiers du socle)

Chaque note restante a **un propriétaire et un moment**. « Étape 0 du paquet » = le paquet l'applique **en premier**, avant son propre code, et il est le seul à éditer ces fichiers du socle pendant le travail des paquets (§2) ; en attendant, un autre paquet n'appelle une API prévue que si elle existe (`if MoveCheck.setRootOffset then`).

| Note | Propriétaire et moment | Fichiers | Changement |
|---|---|---|---|
| **INT-TV** | **fait par le contrat** (étape 0, §22.1), sauf l'habillage de Loading : **world**, étape 0 du paquet | `src/first/Loading.client.luau` | refaire l'habillage en px TV (retirer `DRAWN_UNIT` en multipliant ses dimensions par 1,5) et retirer la mise en page « écran bas » de téléphone ; `Console_loading.spec` et les autres specs de Loading restent vertes (attentes mises à jour seulement là où le téléphone disparaît) |
| **INT-MOVE** | **chase**, étape 0 du paquet | `Server/Movement/Tuning`, `Server/Util/MoveCheck` | bornes du monde : `CenterX = 0`, `CenterZ = 0`, `MaxRadius = 330` (murs à 322) ; **`MoveCheck.setRootOffset(player, studs, jumpHeight)`** (v1.2 : 3e argument) : la hauteur de racine debout du joueur est relevée de `studs` (monture : `rideStats.hipHeight − BaseHipHeight`, jusqu'à 6) pour les règles de vol bas, de racine enfouie et d'altitude ; 0 à pied ; un changement de décalage accorde une **marge verticale ponctuelle égale au changement** pour le pas suivant (ni remise à zéro de l'historique, ni exemption de 3 s qu'on pourrait abuser en montant et descendant) ; montée permise par tick = `max(Tuning.MaxClimbSpeed (12), √(2 × 196,2 × jumpHeight)) × dt × Margin + Slack` (`jumpHeight` = `rideStats.jumpHeight` à la montée, `Balance.Ride.BaseJumpHeight` 7,2 à la descente) ; **`MoveCheck.rootOffset(player): number`** (acteur du tick) ; **`MoveCheck.grant(player, studs = 12, duration = 0,35, tStart)`** (v1.2, remplace `noteSpeed(GrantSpeed)`) : crédit ajouté au plafond par tick, au budget d'action et à la fenêtre soutenue d'1 s, rétroactif jusqu'à `Tuning.GrantRetro` (0,3 s) avant la réception, refusé si le crédit précédent date de moins de `Tuning.GrantMinGap` (4 s, horloge du serveur) ; **`MoveCheck.positionAt(player, t): Vector3?`** (v1.2) : position validée à l'instant t, interpolée dans un anneau de `Tuning.PositionHistory` (0,5 s) de positions acceptées ; tout est effacé par `clear` (appelé par ChaseService à `PlayerRemoving`, remarque A26). Tests : aucun faux positif en monture (un cavalier à chaque selle 8,6 / 10,8 / 13 court et saute 60 s sans infraction), monter et descendre en boucle ne permet aucun vol, bond puis capture au tick suivant acceptée, deux bonds à 2 s d'écart = le second est une rafale, rafale de faux `Leap` ≤ 12 studs par 4 s, `positionAt` interpolée et `nil` hors de l'anneau |
| **INT-REPAIR** | **ranch**, étape 0 du paquet (après `ProfileRepair`) | `Server/Services/DataService` | dans le chargement, après `prepare(raw)` et **avant** les crochets `onPrepare` (déjà là) : `local ok, fixes = pcall(ProfileRepair.repair, data)` ; après `Loaded`, `Signals.ProfileRepaired:Fire(player, fixes)` si la liste n'est pas vide ; échec de la réparation : `warn` (zéro trace) et chargement continué |
| **INT-HARNESS** | **fait par le contrat** (étape 0, §22.1) ; reste `tests/harness/ZeroLog.luau` : **meta** | `tests/harness/ZeroLog.luau` | `ZeroLog.wrap(T)`, `ZeroLog.forSpec(chemin, T)`, `ZeroLog.SOCLE` (specs du socle exemptées) ; `run.luau` le branche déjà |
| **INT-AUDIO** | avant la publication | `Client/Controllers/AudioController` | `AudioController.setMusic(clé?)` : piste de musique en boucle (`Music`, `MusicMoon`, `MusicRush`) avec fondu, volume −12 dB possible (nouveau pendant l'accueil) ; les clés de musique ignorent `maxLength` |
| **INT-FORMAT** | facultatif | `Shared/Util/Format`, `Client/Util/Prefs` | `Prefs.number` délègue à `Logic/BigNumber` (règles du GDD §4.2) ; mise à jour des attentes de `Contract.spec` sur `Format` en conséquence. Le jeu n'en dépend pas : il appelle `BigNumber` |
| **INT-PREPUBLISH** | avant la publication | `scripts/prepublish.luau`, `tests/specs/Prepublish.spec.luau`, `scripts/verify-place.luau` | ignorer les articles `hidden = true` (passes **et produits** : `SeasonPass`, `CoinsSmall`, `CoinsBig`) ; `verify-place` vérifie la place construite : `Workspace.StreamingEnabled == false`, `StarterGui.VirtualCursorMode == Disabled`, `Lighting.Technology == ShadowMap` (remarque A28 ; `Contract_game` vérifie déjà `default.project.json`) ; refuser la publication si `Balance.GddValues ~= "1.3"` |
| **INT-ANALYTICS** | **meta**, étape 0 du paquet (v1.2) | `Server/Util/Analytics` | cumul des événements d'économie par joueur, par tranche de 5 min et par `itemSku` (montants et solde en secondes de revenu, `Analytics.earnIncome(player, sku, coins, incomePerSecond, txType)` / `spendIncome(…)` / `flush(player)` au départ et à la fermeture) ; `itemSku` `Tile_<dalle>` sans niveau, `Objective_<easy\|medium\|hard>`, aucune source `Product_` ; événements personnalisés `TileLevelAtSplorch`, `BoostShare`, `PolicyPaidRandomRestricted` (remplace `ShopHiddenByPolicy`), `SplorchReached` avec `readyAtLogin`, `SplorchCoinsLost` en multiples du prix du Tapis 12 de la boucle, `MegaResult` avec N et participants, `GaugeFilled` sieste comprise ; spec `Analytics_game.spec` : ≤ 10 requêtes par joueur et par minute sur un serveur simulé de 16 joueurs ; `Analytics.spec` du socle reste vert |
| **INT-SKILLS** | dès que possible | `.claude/skills/*/SKILL.md`, `README.md` | console d'abord (plus de « mobile d'abord », de cibles tactiles ni de `ProximityPrompt`), `StreamingEnabled` coupé, disposition télé 1920 × 1080, 28 px TV ; README : PS5 / Xbox / PC, sans téléphone |

---

## 23. Définition de « fini »

Un paquet est fini quand :
- plus aucun `error("TODO(<paquet>)…")` dans ses fichiers ;
- comportement conforme au GDD et à ce document ;
- ses specs (§18.2) sont écrites et vertes, dont les charges hostiles (`Fuzz`), les délais de ses états (`openStates()` de ses services) et la règle zéro trace (aucune erreur de thread dans `h.errors`) ;
- ses notes d'intégration d'étape 0 (§22.2) sont appliquées, specs du socle vertes ;
- `selene src` : 0 erreur, 0 avertissement ; fichiers formatés (StyLua) ;
- la suite complète a été lancée et son résultat rapporté honnêtement (sans test supprimé ni affaibli) ;
- ses besoins hors de ses fichiers sont écrits en **notes d'intégration** (fichier, changement exact, raison) ;
- les **notes du contrat v1.2** qui le concernent (§25) sont appliquées ; pour logic, `Balance.GddValues = "1.3"` et la porte `EconomyPacing` refaite (§16) sont verts ; **aucune publication** tant que `Balance.GddValues ~= "1.3"`.


---

## 24. Journal des corrections de la version 1.1

Revue indépendante du contrat (1er novembre 2026). Chaque point est corrigé dans le code du contrat **et** dans ce document.

| Gravité | Problème | Correction |
|---|---|---|
| critique | Couche h impossible : erreurs des threads lancés invisibles, `ScriptContext` / `LogService` non simulés | Harnais étendu par le contrat (§17.1 h, §22.1) ; auto-tests dans `Harness.spec` ; `run.luau` branche `ZeroLog` |
| critique | Pot intégré depuis `lastSettle` entier : jusqu'à 1 s comptée deux fois par règlement ; absence au tarif plein avant le rebase | `lastSettle` retiré ; intervalle [`growth.t` ; now] ; rebase hors ligne dans `DataService.onPrepare` (§11.5, §1 règle 16) |
| haute | Écritures du profil faites dans `PlayerRemoving` perdues | Règle §1 n° 15 : `onBeforeSave(release)` ; boost du partant de la Squish Party (§11.12) |
| haute | Monture et MoveCheck : `setRootOffset` sans appelant, sol indéfini, mur de 12 studs franchissable | `setRootOffset` à chaque montée / descente avec marge ponctuelle (INT-MOVE) ; `WorldLayout.supportY` ; solides à 30 studs (§3.1, §6, §11.6, §20 n° 21) |
| haute | Couche i sans format portable | `tests/engine/*.spec.luau`, `tests/engine.project.json`, portée et bilan JSON (§17.1 i) |
| haute | Cosmétiques sans écran ni rendu | Onglet Style du panneau Ranch ; RanchRenderer dessine selle, traînée, thème, drapeau, titre (§13.3, §13.6) |
| haute | Points de jauge donnés deux fois | Source unique `Events.Gauge.Points`, seul EventService convertit ; champs en double retirés (§11.10) |
| haute | Clôture du Rush différente du lieu réel du squishy | Retrait immédiat de la clôture ; `BoopCtx.eligible` revérifié à chaque tick (§11.6, §11.9) |
| haute | Console d'abord pas appliquée ; notes INT sans propriétaire | INT-TV faite par le contrat ; chaque note a un propriétaire et un moment ; fouille des chemins tactiles (§2, §22) |
| haute | « Pas ce joueur » dans un Toast inatteignable | Carte `booped` ; seul InputController lie △ (§10.3, §13.5, §14.2) |
| haute | Invariants 6 et 8 du robot non vérifiables | `X.openStates()` ; `Harness:counts()` ; `SOAK_HOURS` et budget de 10 ms (§17.1 c, §17.2) |
| haute | Noms cachés visibles au top 10 mondial | Drapeau codé dans la valeur ; noms par UserService ; alias (§11.13) |
| haute | Interrupteurs jamais envoyés aux clients | `EventState.features` complet, renvoyé à chaque changement (§10.2, §11.10) |
| moyenne | Diagnostics : visibilité, « Mon client », pertes en rafale, erreur de test du client, commandes sans interface | « Bonjour » tab 0, `entries` / `stats`, file bornée, `Celebrate "testError"`, onglet Outils (§11.2, §13.6, §13.7) |
| moyenne | États bloquants non couverts | `worldResync`, `playerReady`, `serverFull`, `unstable`, `clip` ; `extendHold` une fois (§10.5, §12.1) |
| moyenne | Signaux et API manquants entre paquets | `FriendsChanged`, `PetSitRewarded`, `Splorched(…, cadeaux)`, `CommunityService.unlockSession` (§7) |
| moyenne | Appels vers le haut du client indéfinis | `Cards.Requested`, `setNavigator`, `HUD.clapHero` (§13.1) |
| moyenne | Tableaux denses dépendants de ProfileRepair ; DataStore simulé trop permissif | `table.create` dans `Schema.defaults()` ; tableaux à trous refusés (§8.5) |
| moyenne | Clips sans propriétaire | VFXController + carte « clip » ; `CaptureService` simulé (§13.3) |
| moyenne | `AdminCommand "clock"` sur un serveur privé corrompt les sauvegardes | Studio seulement (§11.10, §20 n° 25) |
| moyenne | Faits connus du seul client (étape 10 de l'accueil, carte du choix sans réponse) sans intention | Intention `UiSeen` (§10.1, §20 n° 23) |

---

## 25. Journal des corrections de la version 1.2 (GDD v1.3, remarques A20-A29)

Deux entrées n'avaient pas atteint la v1.1 : le **GDD v1.3** (42 remarques des critiques console, technique et économique, voir son journal de révision) et la fin de la revue d'architecture (remarques **A20 à A29**). Chaque point est corrigé dans le code du contrat **et** dans ce document ; quand le fichier appartient à un paquet déjà écrit (logic) ou en cours (world), ou à un paquet encore à écrire, le changement passe par une **note du contrat v1.2** adressée à ce paquet (colonne « Où »). Suite verte et `check.sh` vert à la livraison du contrat v1.2.

### 25.1 GDD v1.3

| Point (GDD v1.3) | Correction | Où |
|---|---|---|
| Prix des dalles × 3,5^R | `Balance.Tiles.RScale = 3.5` ; `ScaleWithR` dit seulement si la dalle suit R | contrat ; `Formulas.tileCost` : note logic |
| Achat en restant 0,6 s sur une dalle | `Balance.Tiles.DwellSeconds`, `HoldState` « tile » (RanchService), état « tileDwell », `RanchService.onPad`, □ achète tout de suite (§3.4, §6, §11.4) | contrat ; ranch, logic (`StateTimeouts`), client-hud (anneau) |
| Lit douillet 25 M dès R = 3 | valeurs `cozyBed`, `Unlocks` ; découverte `rMin` suit `MinR` (`Config/Pads`) | note logic |
| Objectifs du Grand Splorch × 2,6 ; plus de 2e confirmation | table v1.3, `BeyondMult` ; `RecentBuy*` obsolètes, `SplorchPreview.recentBuy` facultatif | note logic ; contrat (Types) |
| Hors ligne 30 %, arrêt à 90 % | `Balance.Offline.StopAt`, `Formulas.offlineGrowth(g, s, R, plus gros)`, `ReturnScreenData.nearlyReady` (§8.3, §11.5) | contrat ; note logic ; ranch |
| Bébés ≤ 0,5 × le plus gros ; mutation du bébé du Rush ≤ ×5 copiée | `MaxOfBiggest` (logic), `Babies.RushMutationMaxMult`, `RushRules.babyMutation` | contrat ; note logic ; chase |
| Héros + 1 h, retour + 30 min, une fois par jour | `Balance.RushSize.{Hero,Return}GrowthSeconds`, `SquishyRecord.gd`, `SquishyService.growFor` (remplace `growBy`), `EconomyService.gNoBoost` | contrat ; ranch, chase |
| Plafonds de pet-sitting et de cadeaux | `Caps.petSitIn`, `Caps.splorchCoins`, `CapsPerFriend.petSit`, `caps.petSitBy`, `Rewards.GiftSecondsAfterCap`, `EconomyService.consumeFriendCap`, `PetSitRewarded(visiteur, propriétaire, compte)` ; `Caps.petSit` 100 et `PetSitVisitor` 2 | contrat ; note logic ; meta, ranch |
| Bol en 2 s ; boost du bol 5 min chaque jour ; objectifs sans boost | `Quests.Feed.Hold = 2`, `Quests.ObjectiveRules.Rewards.*.boost = 0` ; `Boosts.Objective*` = 0 | contrat ; note logic ; meta |
| Jauge : PERFECT seulement, 600 × N actifs, sieste de 20 min | `Events.Gauge` (`press = 0`, 600, `RestSeconds`), `EventStatePayload.gauge.restUntil`, analytique `GaugeFilled` | contrat ; chase, client-hud |
| Joueurs actifs | `Server/Util/Activity` (implémenté, testé), `Events.Activity`, drapeau `activity` des intentions, `EventService.isActive` / `activeCount`, `TickActor`, `MegaResult` avec N et participants | contrat ; chase, tous les handlers |
| Spectacle complet au plus toutes les 3 min par spectateur | `Balance.Splorch.FullShowGap`, `short` dans `Celebrate "splorch"` / `"giftRain"`, `openClapWindow(hero, fin, spectateurs)`, `ClapPrompt` caché en poursuite, maintien ou fenêtre | contrat ; chase, meta, client-world, client-hud |
| File : place et attente prévue | `SpectacleEntry.{slot, position, eta}`, `Events.SplorchQueueHardCut` (480), état « splorchQueue » | contrat ; chase, logic, client-hud |
| Grand Splorch refusé pendant une fuite ; aucune clôture pendant l'attente | `Feedback waitEscape`, `SquishyService.anyEscaping` / `waiting`, RushService saute le ranch | contrat ; ranch, chase |
| Vibrations : `squishyBack`, `pressTick` sur PERFECT du MEGA, `perfect` + 0,03, sirène 0,3 s | catalogue `Config/Console`, `cooldownExempt` (INT-HAPTICS, fait) | contrat ; client-world, client-hud, world (sirène) |
| `Catch(id, tClient)`, `Leap(dirX, dirZ, tClient)`, `FeedPlop` 2 s, `GrandSplorch`, `PetPress`, portées 10 + 2 | `Config/Intents`, `Remotes`, `Balance.Catch.ClientPast`, `Balance.Press.RangeTolerance` (§10.1) | contrat ; chase, ranch, meta |
| Captures vérifiées à `tClient` | `MoveCheck.positionAt` (INT-MOVE), étape 13 du tick, `Chase.spec` à 0 / 100 / 250 ms | chase |
| Crédit de bond rétroactif | `MoveCheck.grant` (INT-MOVE), §20 n° 14 remplacé, `Balance.Leap.GrantSpeed` retiré | contrat ; chase |
| Monture : hauteur de saut connue de MoveCheck | `setRootOffset(player, studs, jumpHeight)`, montée permise par tick, test par selle (INT-MOVE) | chase, ranch |
| Portées à plat, écart depuis les pieds | §1 règle 17, `ZoneRules.distXZ` / `feetY`, `TickActor.rootOffset`, `CatchCtx.dy`, §15 | contrat ; note logic ; tous les serveurs |
| Prises de dalles à Z = 67, règle des 8 studs | `WorldLayout` (`PAD_SOCKETS`, décorations), `WorldLayout.spec` | note logic ; world (`WorldBuild.spec` suit) |
| Schéma : `coinBuy` retiré, `packs`, `outfits.worn`, `moon`, `dex.fam`, plafonds, `gd` | `Schema.defaults()` / `OWNERS` (§8.1), `ProfileRepair`, `Invariants` | contrat ; ranch, logic |
| Profil plein en JSON, Squishydex de 64 espèces | 2 tests dans `Contract_game.spec` (aller-retour JSON ; sauvegarde puis rechargement par DataService) | contrat |
| Types | `gd`, `tClient`, `restUntil`, `SpectacleEntry`, `HoldState` « tile », `short`, `CelebrateKind` et données par sorte, `best` toujours présent, `TickActor.rootOffset`, plus de `PolicyNoCoins` | contrat |
| Rotation du MEGA, familles en ajout seul, bonus pour toujours | `Species.FamilyOrder` (index de `dex.fam`), `NewFamilyUnlockR`, `MegaRotation` obsolète ; `EventClock.megaSpecies`, `MegaRules.species`, `QuestRules.familyEarned` | contrat ; note logic ; meta, ranch |
| Paquets de pièces retirés ; PolicyService pour l'analytique seulement | `Config/Monetization` (`hidden`), `ProductService.coinsHidden` et `EconomyService.noteCoinBuy` retirés, §20 n° 20 renversé | contrat ; ranch, client-panels, INT-PREPUBLISH |
| Squish Party croisée prolongée, minutes non jouées rendues | `EventService.startSquishParty` prolonge, `partyUnplayed`, crochet `onBeforeSave(release)` et `BindToClose` | contrat ; chase, ranch |
| Déclencheurs du règlement ; P et B une seule fois | §11.5 | ranch |
| Cuve : enclos, sinon Dodo | `Celebrate "hatch"` avec `at`, bulle `world.vat.dodo` | contrat ; ranch, client-world |
| Analytique cumulée, ≤ 10 requêtes par joueur et par minute | note INT-ANALYTICS | meta |
| Classements en entiers codés | §11.13, §20 n° 24 remplacé | meta |
| Textes du monde en px TV | `UI/WorldText` (stub, client-hud), `Layout.WorldText` | contrat ; client-hud, client-world |
| HUD : 2 flèches, sieste, file, anneaux | `Layout.HudContent.edgeArrow`, §13.5 | client-hud |
| Panneaux : fiche d'espèce, onglets de la Boutique, ○ | §13.6, textes `panel.dex.sheet.*`, onglet « Fête » | contrat ; client-panels |
| Clavier : M et Semicolon, raccourcis, sac à objets | `Layout.Keyboard`, §14.6, §3.4 | contrat ; client-hud |
| Suffixes internationaux en français | bannières FR `num.word.*` ; `BigNumber` | contrat ; note logic |
| Carte du clip seulement si la capture réussit | §13.3 | client-world |
| `PressTiming.offset(ownerId, uid)` et cas de spec | §12.1 | note logic |
| `GetBlockedUserIds` simulé (C3-21) | INT-HARNESS v1.2 (fait) | contrat |
| Porte `EconomyPacing` refaite | §16 | note logic |
| Mises à jour de docs/04 | §3.1, §8.1, §8.2, §20 n° 14, 20, 21, 24, §21 | contrat |

### 25.2 Remarques A20 à A29 de la revue d'architecture

| Remarque | Gravité | Correction | Où |
|---|---|---|---|
| A20 horloge d'administration sur un serveur privé | moyenne | déjà traitée en v1.1 : `"clock"` seulement si `RunService:IsStudio()` (§4, §11.10, §20 n° 25) ; vérifiée, `EventService.spec` doit prouver qu'elle est ignorée hors Studio | chase |
| A21 envois du client sans propriétaire ni transport | moyenne | `ReportBlocked` envoyé une fois par `WorldStateController.Start` (`GetCore("GetBlockedUserIds")` sous `pcall`) ; intention `ClientEvent(kind ∈ {qualityReduced, shopOpened})` de DiagnosticsService, 1 / 5 s, analytique seulement ; « objectifs vus » = `UiSeen("objectives")` (§10.1, §13.2, §20 n° 32) | contrat ; client-world, client-panels, meta |
| A22 contre-audit incomplet | moyenne | `RedTeam_Event.spec` (chase) et cas `FeedPlop` de `RedTeam_Social.spec` (meta) (§17.1 g) | chase, meta |
| A23 budgets partagés sans quotas | moyenne | quotas par module dans `QualityController.Budgets` ; `ClientReplay.spec` : ≤ 3 000 objets d'interface, ≤ 8 Ko/s (§13.3, §18.3) | contrat (stub) ; client-world, intégration |
| A24 `BuyTile` sur une dalle trop chère | moyenne | `RanchService.onPad` → source « pad » (refus doux) ; achat au premier tick où les pièces suffisent, une fois par entrée (§10.1, §11.4, §11.5) | contrat (stub) ; ranch |
| A25 effacement des clôtures | basse | `setFence(slot, {}, maRaison)` n'efface que sa raison ; `""` réservé à RanchService ; pet-sitting réappliqué après le Rush (§11.4, §11.8, §11.9) | ranch, meta, chase |
| A26 nettoyages et validations | basse | `MoveCheck.clear` par ChaseService au départ ; `MoveSquishy` refusé pour un squishy en attente ; héros parti avant l'éclatement : spectacle effacé, aucune pluie de cadeaux (§5.4, §10.1, §11.10, §11.11) | chase, ranch, client-world |
| A27 `RanchPatch` ne peut pas effacer `best` | basse | `best` toujours présent, `s = 0` = aucune silhouette (Types, §10.6) | contrat ; ranch, client-world |
| A28 tests manuels sans propriétaire ; streaming non vérifié | basse | `docs/05-guide-publication.md` au paquet meta ; `Contract_game` vérifie `default.project.json` ; `verify-place` étendu (INT-PREPUBLISH) (§2, §17.1, §17.3) | contrat ; meta, intégration |
| A29 petites incohérences | basse | `MaxRadius = 330` partout (murs à 322) ; commentaire de `Balance` vers §21 ; `CelebrateKind` fermé et données par sorte ; bloc d'API d'ErrorReporter : déjà au §13.7, aligné sur le stub ; `Net.setup()` après l'attach de DiagnosticsService ; VFXController seul à borner `pressTick` (§11.14, §9, §10.3, §5.1, §14.4) | contrat |

### 25.3 Changements de surface d'API (stubs et contrat)

- Ajoutés : `RanchService.onPad` ; `EconomyService.consumeFriendCap`, `gNoBoost` ; `SquishyService.growFor`, `waiting`, `anyEscaping` ; `EventService.partyUnplayed`, `isActive`, `activeCount` ; module `UI/WorldText` (7 fonctions) ; `CommunityService.openClapWindow` reçoit `viewers?` ; utilitaire `Server/Util/Activity` (implémenté) ; intention `ClientEvent`.
- Retirés (stubs jamais implémentés) : `EconomyService.noteCoinBuy`, `ProductService.coinsHidden`, `SquishyService.growBy`.
- Prévus chez logic (notes) : `ZoneRules.distXZ`, `ZoneRules.feetY`, `RushRules.babyMutation`, `QuestRules.familyEarned`, signatures étendues de `Formulas.offlineGrowth` et `MegaRules.species` ; retirés : `Formulas.coinPack`, `SplorchPreview.recentBuy`. `Contract_game` les ajoutera à sa liste quand logic les aura livrés (contrat suivant).
- Prévus dans le socle (notes) : `MoveCheck.grant`, `positionAt`, `rootOffset`, `setRootOffset` à 3 arguments (INT-MOVE, chase) ; cumul de `Analytics` (INT-ANALYTICS, meta).
