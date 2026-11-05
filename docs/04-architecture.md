# Raise a Squishy — Architecture technique (contrat d'implémentation)

> **Document 04, version 2.0 du 3 novembre 2026 : le jeu complet** (GDD **v2.0** : 9 familles d'amélioration, écran Améliorations, Confettis et Atelier de Big Plop, Jelly Ascend, Petit Splorch et Souvenir de gelée, Plopettes, Monuments, ranch qui évolue, piste de la semaine, Carnet, Déco perso). Le contrat v2.0 est le **§27** : paquets et propriété des fichiers, schéma v2 et sa migration exacte, interrupteurs, réseau, configuration, API des modules nouveaux, contrat de disposition de l'écran Améliorations et ses 20 règles « zéro bug d'affichage », porte d'économie v2.0, plan de tests, notes d'intégration, définition de « fini » et journal. **Tout système v2.0 est derrière un interrupteur `Config/Features` coupé par défaut** : le jeu de base joue exactement comme la version de test (commit 7382f88) tant qu'un paquet n'est pas implémenté, relu et ouvert. Les §1 à §26 (contrat v1.2 et journal d'intégration) restent valables pour tout ce que la v2.0 ne change pas.
> Version 1.2 du 1er novembre 2026 : application du **GDD v1.3** et des remarques A20 à A29 de la revue d'architecture (journal au §25 ; corrections de la v1.1 au §24). Les paquets déjà écrits (logic) ou en cours (world) reçoivent leurs changements par des **notes du contrat v1.2** (§25), jamais par une édition de leurs fichiers.
> Sources : [`02-game-design-document.md`](02-game-design-document.md) (GDD **v2.0**, cité « GDD §x » ; le §12 est l'architecture de référence), [`09-plan-contenu-complet.md`](09-plan-contenu-complet.md), [`03-decision-du-jury.md`](03-decision-du-jury.md) (concept, §8) et la **décision du propriétaire du 1er novembre 2026** : **console d'abord** (PS5 avec DualSense sur une télé, puis Xbox et PC ; aucun téléphone au lancement) et **zéro bug au lancement**. Cette décision passe avant tout le reste.
> Le code du contrat est **déjà dans le dépôt** : configurations avec les vraies données, types, remotes, catalogue des intentions, schéma v1 (et le schéma v2 décrit, testé, non activé), bus de signaux, ordres d'initialisation, l'utilitaire `Server/Util/Activity` (implémenté et testé par le contrat). Il est vérifié par `tests/specs/Contract.spec.luau` (socle), `tests/specs/Contract_game.spec.luau` (jeu), `Contract_v2.spec.luau`, `Contract_upgrades.spec.luau` et `Contract_unlocks.spec.luau` (v2.0). En cas de doute, **le code du contrat fait foi**, puis ce document, puis le GDD.
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
26. Journal d'intégration et de validation (2 novembre 2026)
27. **Contrat v2.0 : le jeu complet** — 27.0 ce qui est dans le dépôt · 27.1 paquets et propriété · 27.2 schéma v2 et migration · 27.3 interrupteurs · 27.4 signaux · 27.5 réseau · 27.6 configuration · 27.7 API des modules nouveaux · 27.8 écran Améliorations et les 20 règles · 27.9 porte d'économie v2.0 · 27.10 plan de tests · 27.11 notes d'intégration · 27.12 définition de « fini » et journal

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

> **v2.0** : les paquets du jeu complet (P0, A1-A4, B1-B5, I), leur propriété des fichiers et leur ordre sont au **§27.1** ; ils remplacent le tableau ci-dessous pour le travail v2.0 (les règles de ce paragraphe restent).

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
| `Ranches/<k>` | v2.0 : `Types.RanchAttributesV2` (`BestR`, `Ascend`, `SplorchReady`, `AscendReady`, `PetitSplorchAt`, `Monuments`, `DecoPerso`, `HaloOn`, `TapisTier`, `GloveTier`, `ApronTier`) | number, boolean, string | RanchService (`setV2Attributes` : `BestR`, `Monuments`, paliers calculés ici ; `SplorchReady` par EconomyService, `Ascend`, `AscendReady`, `PetitSplorchAt` par SplorchService, `DecoPerso`, `HaloOn` par CommunityService) | chacun derrière son interrupteur (§27.3) : absent tant qu'il est coupé, effacé au départ du propriétaire et quand l'interrupteur se coupe en direct (lot A2, A2-20, A2-33) |
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
| `DataSnapshot`, `DataPatch` | profil public, patchs groupés ; v2.0 : clé dérivée `upgradeSnapshot` (`Types.UpgradeSnapshot`, jamais sauvegardée, `DataService.setPatchExtra` posé par EconomyService) dans l'instantané d'arrivée et dans chaque patch qui touche ce qu'elle montre [UpgradesScreen] | DataService | le joueur | chargement, puis par image |
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
- **Portage** : `PickUp` → `carried[player] = uid` (RanchPublic `carry`), descente de monture ; fin (`endCarry`) sur : mort, réapparition, sortie du ranch (vérifiée dans `step` avec la position validée), fenêtre ouverte (le client envoie `PutDown`), monture, départ, et **délai de sûreté** de `Balance.Carry.SafetySeconds` (300 s, note INT-LR10 : le squishy retourne à sa place ; `StateTimeouts.carry` = 301 pour le contrôle du robot). Pendant le portage : Bondir et Monter refusés.
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

> **v2.0** : plan de tests des paquets du jeu complet au **§27.10** (et les specs des 20 règles d'affichage au §27.8).

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
| 01/11/2026 | `Balance.Tiles.RScale` (nouvelle) | — → 3,5 | GDD v1.3 §4.6 (C3-4 : inflation des pièces) | contrat v1.2 ; revue logic : `Formulas.tileCost` × `RScale`^R (`tileCost("snack", 0, 1) = 70`) |
| 01/11/2026 | `Balance.Tiles.DwellSeconds` (nouvelle) | — → 0,6 | GDD v1.3 §4.6 (C2-10 : achats sans le vouloir) | contrat v1.2 |
| 01/11/2026 | `Balance.Tiles.cozyBed.Base` / `MinR` | 250 000 / 1 → 25e6 / 3 | GDD v1.3 §4.6 (C3-5) | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) ; `tileCost("cozyBed", 0, 3) = 25e6` |
| 01/11/2026 | `Balance.Splorch.Unlocks` | « pad.cozyBed » à R = 1 → R = 3 | GDD v1.3 §4.15 | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) (aperçu : tuile à R = 3) |
| 01/11/2026 | `Balance.Splorch.Targets` | table × 2,7 → table v1.3 (15 000 … 1,1e12) | GDD v1.3 §4.15, §4.24 (C3-3) | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) : R = 10 / 15 / 20 aux jours 7 / 14 / 28 aux 3 tailles |
| 01/11/2026 | `Balance.Splorch.BeyondMult` | 2,7 → 2,6 | GDD v1.3 §4.15 | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) : `splorchTarget(20) = 2,9e12` |
| 01/11/2026 | `Balance.Splorch.RecentBuyWindow` / `RecentBuyShare`, `Balance.CoinPacks` | → retirés | GDD v1.3 §8.3 (C3-6 : paquets retirés) | revue logic : retirés ; `splorchPreview` ne rend plus `recentBuy` ; `coinPack` rend 0 (gardée tant que `Contract_game` la liste, note INT-LR1) |
| 01/11/2026 | `Balance.Splorch.FullShowGap` (nouvelle) | — → 180 | GDD v1.3 §4.15 (C2-11) | contrat v1.2 |
| 01/11/2026 | `Balance.Offline.GrowthShare` | 0,5 → 0,3 | GDD v1.3 §4.19 (C3-5) | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) : Grands Splorch prêts à la connexion 0 % (J2-J14) |
| 01/11/2026 | `Balance.Offline.StopAt` (nouvelle) | — → 0,9 | GDD v1.3 §4.19 (C3-5) | contrat v1.2 ; revue logic : `Formulas.offlineGrowth(g, s, R, plus gros)` borné à 0,9 × objectif − plus gros, joué par `EconomyModel` |
| 01/11/2026 | `Balance.Babies.MaxOfBiggest` | 2 → 0,5 | GDD v1.3 §4.21.3, §4.25 (C3-11) | revue logic : appliqué, specs à jour ; porte EconomyPacing v1.2 verte (50 joueurs × 4/8/16) (`babySize`, `RushRules.babySize`) |
| 01/11/2026 | `Balance.Babies.RushMutationMaxMult` (nouvelle) | — → 5 | GDD v1.3 §4.21.3 (C3-11) | contrat v1.2 ; revue logic : `RushRules.babyMutation` livrée et jouée par `EconomyModel` |
| 01/11/2026 | `Balance.RushSize.HeroBonus` / `ReturnBonus` | 10 % / 5 % → `HeroGrowthSeconds` 3 600 / `ReturnGrowthSeconds` 1 800 | GDD v1.3 §4.21.3 (C3-11) | contrat v1.2 (aucune valeur lue par logic) |
| 01/11/2026 | `Balance.Caps.petSit` | 300 → 100 | GDD v1.3 §6.4 (C3-11) | revue logic : appliqué (vérifié par `Invariants`) ; hors porte (aucun ami dans le modèle) |
| 01/11/2026 | `Balance.Caps.petSitIn`, `splorchCoins` (nouvelles) | — → 100, 10 | GDD v1.3 §6.4, §4.15 | contrat v1.2 |
| 01/11/2026 | `Balance.CapsPerFriend.petSit` (nouvelle) | — → 20 | GDD v1.3 §6.4, §6.9 | contrat v1.2 |
| 01/11/2026 | `Balance.Rewards.PetSitVisitor` | 10 → 2 | GDD v1.3 §6.4 (C3-11) | revue logic : appliqué ; hors porte (aucun ami dans le modèle) |
| 01/11/2026 | `Balance.Rewards.GiftSecondsAfterCap` (nouvelle) | — → 10 | GDD v1.3 §4.15 | contrat v1.2 |
| 01/11/2026 | `Balance.Boosts.ObjectiveMedium` / `ObjectiveHard` | 300 / 600 → 0 / 0 | GDD v1.3 §7.4 (C3-12) | revue logic : appliqué ; la porte ne donne aucun boost aux objectifs ; `Balance.GddValues = "1.3"` |
| 01/11/2026 | `Balance.Press.RangeTolerance`, `Balance.Catch.ClientPast` (nouvelles) | — → 2, 0,35 | GDD v1.3 §12.7, §12.5 | contrat v1.2 |
| 01/11/2026 | `Balance.Leap.GrantSpeed` | 36 → retirée | GDD v1.3 §12.8 (C3-8 : `MoveCheck.grant`) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.Points.press` | 1 → 0 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.TargetPerPlayer` | 500 → 600 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Gauge.RestSeconds` (nouvelle) | — → 1 200 | GDD v1.3 §4.23 (C3-12) | contrat v1.2 |
| 01/11/2026 | `Events.Activity` (nouvelle) | — → 120 s, 4 studs, 60 studs, min 1 | GDD v1.3 §4.22 (C3-18) | contrat v1.2 |
| 01/11/2026 | `Events.SplorchQueueHardCut` (nouvelle) | — → 480 | GDD v1.3 §12.10 | contrat v1.2 |
| 01/11/2026 | `Quests.Feed.Hold` | 5 → 2 | GDD v1.3 §4.20 (C2-17) | contrat v1.2 |
| 01/11/2026 | `Quests.ObjectiveRules.Rewards.medium.boost` / `hard.boost` | 300 / 600 → 0 / 0 | GDD v1.3 §7.4 (C3-12) | contrat v1.2 (`EconomyModel` ne les lisait déjà plus) |
| 01/11/2026 | `Balance.Press.Seconds` | 12 → 22 | Revue logic, porte v1.2 (santé « pressions ≥ 50 % des pièces gagnées en jeu au J7 ») : avec 12, les pressions faisaient 40-42 % (objectifs 30-40 %, Pot en jeu 20 %) ; levier nommé par le GDD §4.24 | 50 joueurs × 3 tailles : pressions 0,56-0,60 au J7 (avant 0,40-0,42) ; pièces à 5:00 10,3-10,8K (repère 5K-17K, GDD ≈ 10K) ; premier Grand Splorch 12,6-12,9 min |
| 01/11/2026 | `Balance.Tiles.snack.Growth` | 4,0 → 4,5 | Revue logic, porte v1.2 (santé « pièces perdues au Grand Splorch ≤ 10 × le prix du Tapis 12 ») : avec 4,0, 13,8-14,4 × (le revenu d'une boucle croît plus vite que 3,5^R : 18 squishies d'enclos qui grandissent tous de G, étoiles, Fame, trophées) ; `RScale` (3,5) est figé par `Contract_game` ; levier nommé par le GDD §4.24 ; le GDD ne retrouve « 3 ×, Tapis 12 à 93 % » qu'avec A = 1 (sans décorations, Fame ni trophées). Tapis 12 = 306 M (GDD : 83,9 M), niveaux 0-3 presque inchangés (20, 90, 405, 1 822). **Le témoin « prix des dalles » de `Contract_game` (Tapis niveaux 3 et 11) reste à mettre à jour par l'architecte : note INT-LR1 de la revue logic** ; essais sans ce réglage (dans les seules valeurs libres : `Offline.PotShare`, `Income.FamePerPoint`, `Trophies`, `Income.DecorBonus`, `Vat.QualityMax`) : aucun ne passe sous 10 sans retirer une règle du GDD | 50 joueurs × 3 tailles : pertes 3,5-4,1 × (GDD ≈ 3), Tapis 12 à 0,86-0,9 de la boucle (GDD ≈ 90 %), balade 290 s, R = 10 / 15 / 20, plus gros J7 8,3e7-9,5e7 (GDD ≈ 1e8), tampons J7 95-96, temps en ×2 36 % (jauge pleine en ≈ 18 min au débit mesuré de 33 points/min, cycle de 25 min sieste comprise), gros acheteur + 2 R au J28 (limite 2) |
| 03/11/2026 | tables v2.0 (`Gloves.StepPerLevel`, `Monuments.IncomeStep`, `Helpers.RewardShare`, `SplorchV2.GiftLevelsBase`) | **aucune valeur changée** (essais : 0,025 → 0,03 / 0,035 ; 0,01 → 0,02 / 0,025 ; 1 → 1,25 / 1,5 ; 1 → 2) | Lot A1 (3/4), porte v2.0 (docs/04 §27.9, journal A1-25) : 2 clés hors limite à 20 joueurs (r13 de la référence 3,075 min ≤ 3 ; pertes J8-14 de l'assidu au serveur de 4 3,55 T12 ≤ 3), tenues à 80 joueurs (2,87 ; 2,50), même résultat dans la simulation du design sur les mêmes graines (3,0 ; 3,07). Chaque essai déplace une clé serrée contre une autre (pertes de l'assidu contre son trou p90 ≤ 15 min, r13 de la référence contre les pertes de l'assidu) et aucun ne tient toutes les clés à 80 joueurs (Gants 0,03 : trou p90 de l'assidu de 4 = 15,3 ; Gants 0,035 : pertes de l'assidu de 16 = 3,12) ; prix des Gants, du Tapis Étoilé, de l'École et des Monuments tenus par les témoins de `Contract_upgrades` (contrat) | valeurs du GDD v2.0 gardées ; décision demandée (`scratchpad/v2/notes-croisees.md`) |
| 05/11/2026 | `Balance.OfflineV2.NightPotShares` (Pot de nuit de l'Atelier) | { 0,25 ; 0,30 ; 0,35 } → { 0,25 ; 0,28 ; 0,31 } | Lot A1 (3/4), porte v2.0, vrai problème (journal A1-31) : `offlinePotShare` du joueur de 10 min par jour 2,092 à 80 joueurs, 84 jours (≤ 2 ; bruit ≈ 0,01) : dès le jour 15, la nuit rapportait plus de 2 fois la séance (1,65 aux jours 1-14 ; 2,08 / 2,13 / 2,19 aux jours 15-28 / 29-56 / 57-84) | 1,873 ; trou p90 J8-14 de l'assidu 14,27 / 14,69 / 14,93 → 14,07 / 13,97 / 14,05 min (serveurs de 16 / 4 / 8, 400 joueurs), pertes J8-14 inchangées (2,65 / 2,66 / 2,56 T12), référence inchangée (`offlinePotShare` 1,03) ; aucun témoin de `Contract_upgrades` ; texte du GDD (« 25 % → 30 % → 35 % ») : note au design |
| 05/11/2026 | `Balance.Ascend.ReqR` | { 15, 20 } puis + 4 → 60 conditions : 15, 20, + 4, et + 5 une fois toutes les 8 Ascensions dès la 11e (57, 90, 123, 156, 189, 222, 255) | Lot A1 (3/4), vrai problème (journal A1-32) : `ascendGapDays` des Ascensions tardives (GDD §4.27 : chaque Ascension, 10-16 / 4-8 jours) : référence 9,5 / 9 jours (A11→A13, 50 joueurs), assidu 3 jours de A22 à A36 ; avec + 4 seul, la dernière boucle record tombait à 0,13 fois la difficulté de A1 à A60 (0,73 à 1 maintenant) | avec la ligne suivante (160 joueurs, 140 jours) : référence 11, 11, 11, 11, 11, 11, 10, 10, 10, 12, 11 jours (A1→A2 … A11→A12) ; assidu 5 jours (4 à A9→A10 et A25→A26), A = 28 au jour 140 (médiane sur 400 joueurs ; 36 avant) ; trou p90 J85-140 de l'assidu 14,81 (12,8 avant : boucles record tardives de nouveau longues, au bord) ; témoins de `Contract_upgrades` tenus ; texte du GDD (« puis + 4 ») : note au design |
| 05/11/2026 | `Balance.Ascend.PriceByA` | { 0,5 ×4 ; 0,32 } → 60 facteurs : 0,5 ×4, 0,32 jusqu'à A10, puis 0,31, et 0,29 aux Ascensions du Grand Splorch de plus | Lot A1 (3/4), avec la ligne précédente : un Grand Splorch de plus rend la boucle record ≈ 3,5 % plus pauvre (prix × 3,5, pièces × 3,38) ; sans compensation, achats de la ligne Tapis par boucle record 10,43 à A26 (limite 10), Tapis 12 à 0,89 de la boucle | achats ≥ 11,97 et Tapis 12 ≤ 0,77 dans les boucles record A1-A30 (assidu, 160 joueurs) ; prix jusqu'à A10 inchangés (facteurs 1 à 6 du témoin de `Contract_upgrades`) |

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
| **INT-AUDIO** | **fait** (intégration client, §26) | `Client/Controllers/AudioController` | `AudioController.setMusic(clé?)` : piste de musique en boucle (`Music`, `MusicMoon`, `MusicRush`) avec fondu, volume −12 dB possible (nouveau pendant l'accueil) ; les clés de musique ignorent `maxLength` |
| **INT-FORMAT** | facultatif, **non fait** (le jeu appelle `BigNumber`, §26) | `Shared/Util/Format`, `Client/Util/Prefs` | `Prefs.number` délègue à `Logic/BigNumber` (règles du GDD §4.2) ; mise à jour des attentes de `Contract.spec` sur `Format` en conséquence. Le jeu n'en dépend pas : il appelle `BigNumber` |
| **INT-PREPUBLISH** | **fait** (intégration serveur, §26) | `scripts/prepublish.luau`, `tests/specs/Prepublish.spec.luau`, `scripts/verify-place.luau` | ignorer les articles `hidden = true` (passes **et produits** : `SeasonPass`, `CoinsSmall`, `CoinsBig`) ; `verify-place` vérifie la place construite : `Workspace.StreamingEnabled == false`, `StarterGui.VirtualCursorMode == Disabled`, `Lighting.Technology == ShadowMap` (remarque A28 ; `Contract_game` vérifie déjà `default.project.json`) ; refuser la publication si `Balance.GddValues ~= "1.3"` |
| **INT-ANALYTICS** | **meta**, étape 0 du paquet (v1.2) | `Server/Util/Analytics` | cumul des événements d'économie par joueur, par tranche de 5 min et par `itemSku` (montants et solde en secondes de revenu, `Analytics.earnIncome(player, sku, coins, incomePerSecond, txType)` / `spendIncome(…)` / `flush(player)` au départ et à la fermeture) ; `itemSku` `Tile_<dalle>` sans niveau, `Objective_<easy\|medium\|hard>`, aucune source `Product_` ; événements personnalisés `TileLevelAtSplorch`, `BoostShare`, `PolicyPaidRandomRestricted` (remplace `ShopHiddenByPolicy`), `SplorchReached` avec `readyAtLogin`, `SplorchCoinsLost` en multiples du prix du Tapis 12 de la boucle, `MegaResult` avec N et participants, `GaugeFilled` sieste comprise ; spec `Analytics_game.spec` : ≤ 10 requêtes par joueur et par minute sur un serveur simulé de 16 joueurs ; `Analytics.spec` du socle reste vert |
| **INT-SKILLS** | **fait** (validation, §26) | `.claude/skills/*/SKILL.md`, `README.md` | console d'abord (plus de « mobile d'abord », de cibles tactiles ni de `ProximityPrompt`), `StreamingEnabled` coupé, disposition télé 1920 × 1080, 28 px TV ; README : PS5 / Xbox / PC, sans téléphone |

---

## 23. Définition de « fini »

> **v2.0** : définition de « fini » d'un paquet du jeu complet et du jeu complet au **§27.12**.

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

---

## 26. Journal d'intégration et de validation (2 novembre 2026)

Décisions prises par les intégrateurs serveur et client, puis par le validateur de la version (qui a pu éditer tous les fichiers). Rapports complets : notes `integration-server`, `integration-client` et rapport de validation.

### 26.1 Ajouts d'API (tous additifs, aucune signature changée)

- **INT-AUDIO** (§13.5, §13.6) : `AudioController.setMusic(key: string?, db: number?)` (`key` ∈ {`Music`, `MusicMoon`, `MusicRush`} ; nil ou inconnu = `Music` ; fondu croisé de `Sounds[key].fade` s) ; `AudioController.setMusicVolumeDb(db)` borné à [−60 ; 0] (non fini = 0) ; `AudioController.music(): (string, number)`. Les pistes ne passent jamais par `play()`. **LightingController** est le seul écrivain de la musique : `MusicRush` pendant le Rush (après la sirène), `MusicMoon` pendant la Jelly Moon, sinon `Music`, −12 dB (`Quests.Onboarding.QuietMusicDb`) pour un nouveau avant l'étape 9 ; il ne pousse qu'un changement de décision. La note client-hud n° 2 (`setMusicVolumeDb` par OnboardingController) est remplacée par cette règle. **Banners** joue `RushSiren`, `MegaWarn`, `MoonStart` avec leur bannière d'événement (jamais pour un nouveau avant l'étape 9).
- **Messages** (§13.5) : `Toast.message(text, kind?)` passe par `Toast.router` (posé par `Hud/Messages` sur `Messages.push` : un message à la fois, après la bannière, caché en mode photo ; un routeur qui lève retombe sur `show`) ; `Toast.Lifetime` lu à chaque `show`. `Toast.show` reste immédiat (specs du socle).
- `Widgets.followGlyph(label, glyph, left, gap, right)` : un libellé suit la largeur réelle de la pastille de touche (touches longues du clavier).
- `DiagnosticsService.noteTick(ms)` (durée de chaque tick de ChaseService) ; `AdminCommand("photo", arg)` : « on » / « off » imposent, tout autre argument (dont "") bascule.

### 26.2 Interprétations et réglages

- **GDD §10.2 (validation)** : chaque message central vit **2,5 s** (`Hud/Messages` pose `Toast.Lifetime = 2.5`, affichage 2,7 s, un seul à l'écran). Spec : `Fix_validation`.
- **GDD §4.9, INT-CWR-3 (validation)** : en portant près du Bassin, l'invite □ dit « Fusion ! » si un jumeau attend, sinon **« Poser dans le Bassin »** (`primary = "putInPool"`, toujours un lancer pour InputController). Attente de `PromptController.spec` alignée sur le GDD.
- **INT-LR10 (validation)** : consigne du propriétaire « chaque état a un délai et une sortie » : le portage a un délai de sûreté de 300 s (`Balance.Carry.SafetySeconds`) ; ensuite le squishy retourne à sa place, sans trace (c'est une sortie normale, comme « Poser »). `StateTimeouts.carry = 301` (1 s de grâce pour le contrôle du robot de longue durée).
- **Bannières du Rush en mode `events` (validation)** : `BoopRush = "events"` montre les bannières du Rush seulement pendant la Jelly Moon ou une fête d'administrateur, même règle que `RushService` et le ciel de `LightingController`.
- **INT-LR1 (intégration serveur, validation)** : `Tiles.snack.Growth = 4.5` et `Press.Seconds = 22` (§21) ; témoin de `Contract_game` aligné ; texte du GDD aligné (§4.6 : Tapis ×4,5 et table 20, 90, 405, 1 822… 306 M ; §2, §3, §4.7, §4.24 : 22 s de revenu par pression). `Formulas.coinPack` reste (rend 0) : `Formulas.spec` et `Props_Formulas.spec` le testent et aucun test n'est supprimé.
- **Note meta n° 2** (§18.1) : `Brains.boot` garde les doublures du paquet meta par défaut (isolation des specs unitaires du paquet chase) ; les specs d'intégration et du paquet meta passent `stubMeta = false` ; `Soak.run` utilise les vrais services par défaut.
- **Note meta n° 6** : `Pads.FreeBuilds.pool.atStep = 4` (GDD §3 vers 1:00 : Plop attend déjà dans le Bassin).
- **GDD §16.3** : `PostBoopQuit` se mesure depuis le premier boop subi de la session ; `QuitBaseline` = aucun boop subi dans les 120 s avant le départ ; `ComboLength` porte `all` (0 chaîne manuelle, 1 « Tout fusionner ») ; `RideStart` à la première balade de la session seulement ; `RushCatchByInput` pour les captures des fuites du Rush.
- **`hud.menu`** (client-hud n° 6) : la puce affiche `string.upper(hud.menu)` = « MENU » ; l'audit des manettes, qui refuse un nom de bouton nu (« Menu » est un bouton Xbox), reste strict.
- **§23** : plus aucune marque de stub dans `src` (`Fix_validation` fouille `src`) ; les gardes `Chase/Guard`, `Meta/Guard`, `Widgets.safe`, `Hud/Util.safe`, `World/Util.safe` reconnaissent encore une erreur de stub par une marque construite (rapport d'intégration : listes `stubbed` vides vérifiées par Boot et Soak).

### 26.3 Laissé ouvert (sans effet sur le comportement vérifié)

- INT-CW-8 / INT-CW-9 / ranch n° 2 et R8 (`placeRank`, `PadRules.visible`, `CatchRules` partagés entre client et serveur) : refactorisation non faite ; `ClientReplay.spec` vérifie que le miroir du client égale le serveur à 6 points de contrôle.
- client-panels n° 4 (`EquipOutfit("", uid)`) et n° 15 (`Juice.press` 1,06), client-hud R-D et INT-CW-5 (constantes de rendu dans Config), INT-FORMAT : facultatifs.
- Notes « texte du contrat » des rapports de paquets (chase 1-5 et 16, ranch R6, R7, 15, 16, logic INT-LR2, INT-LR9, INT-LR11, meta 7-11 et 13, world 7, 9, 10, client-hud 3-5 et R-A à R-C, client-panels 6, 7, R6, client-world CWR-1, CWR-2, CW-4 à CW-6, CW-11) : aucune modification de code attendue ; le code livré fait foi.
- Sons encore sans déclencheur (`LevelUp`, `VatBubble`, `Pickup`, `Splash`, `MountUp`, `RideLand`, `Boing`) et finitions visuelles (arcs Prendre / Lancer, bombement du portail) ; tous les identifiants de sons restent vides avant la publication.
- Robot de 6 h (`scripts/soak.sh`) et tests manuels M1 à M18 sur vraie PS5, Xbox et PC.

---

## 27. Contrat v2.0 : le jeu complet (GDD v2.0)

> **Version 2.0 du 3 novembre 2026** (architecte). Entrées : GDD v2.0 (`docs/02`, cité « GDD §x »), `scratchpad/v2/gdd/contract-changes.md` (N1-N25, §1-§10) et `packages-proposal.md` du rôle design, `docs/09` (plan de contenu, 20 règles « zéro bug d'affichage »). Base : commit 7382f88 (porte verte, version de test envoyée au propriétaire). Ce chapitre **remplace**, pour le travail v2.0, le tableau des paquets du §2, le plan de tests du §18 et la définition de « fini » du §23 ; les §1-§26 restent valables pour tout ce que la v2.0 ne change pas. **Règle n° 1 de la v2.0 : chaque système nouveau est derrière un interrupteur `Config/Features` COUPÉ par défaut** ; le jeu de base joue donc exactement comme la version de test tant qu'un paquet n'est pas implémenté, relu et ouvert à l'étape d'intégration (§27.3).

### 27.0 Ce qui est déjà dans le dépôt (code du contrat v2.0) et ce qui fait foi

| Fichier | Ajout v2.0 (aucun comportement changé) |
|---|---|
| `src/shared/Config/Features.luau` | 22 interrupteurs v2.0 à `false` (§27.3) ; `Features.Static` (interrupteurs figés, refusés par `Features.set`) : `SchemaV2` |
| `src/shared/Config/Upgrades.luau` (nouveau) | Catalogue : 8 familles en pièces (ordre fixe), 7 lignes en lecture seule, 10 lignes de l'Atelier (9 + `decoShop`), 7 lignes de « Pour le plaisir », liste fermée des effets (§27.6) |
| `src/shared/Config/IntentsV2.luau` (nouveau) | 5 intentions déclarées, pas encore écoutées : `BuyUpgrade`, `JellyAscend`, `PlaceDeco`, `GiveHeart`, `SetPhotoMode` (§27.5) |
| `src/shared/Config/Balance.luau` | Tables v2.0 à part : `Prestige`, `Ascend`, `Confetti`, `UpgradePrices`, `Monuments`, `Gloves`, `SplorchV2`, `CapsV2`, `Hearts`, `OfflineV2`, `PotV2`, `PressV2`, `Helpers`, `Upgrades` ; marque `GddValuesV2 = "2.0"` (la marque `GddValues` reste `"1.3"`) |
| `src/shared/Config/Layout.luau` | `Layout.Upgrades` (zones, 3 gabarits, colonnes, budget) et `Layout.HudV2` (rail 8 × 80, largeur 340, puce « Prochain achat », **rectangles réels des 15 éléments du HUD** du GDD §10.2 : `Rects`, `Exclusive`, `Center`, `CalmMax`, critique m13) |
| `src/shared/Config/Species.luau` | Colonne `perso` (GDD §5.6) : 6 personnalités `curious`, `sleepy`, `bouncy`, `cuddly`, `prankster`, `proud` (`Species.Personalities`, ordre et identifiants définitifs) ; `proud` réservé aux raretés ≥ `Species.ProudMinRarity` (5, Légendaire) ; lue par le client seulement (B5, derrière `Personalities`) |
| `assets/fonts/` (nouveau, fichiers de **test** seulement) | `FredokaOne.ttf` (SIL OFL 1.1, licence `FredokaOne-OFL.txt`) et `LuckiestGuy.ttf` (**Apache License 2.0**, licence `LuckiestGuy-LICENSE.txt`), téléchargés de `fonts.gstatic.com` (API CSS de Google Fonts) le 3 novembre 2026 ; empreintes SHA-256 figées dans `Contract_glyphs` ; aucun projet Rojo ne range `assets/` (décision C19) |
| `src/shared/Config/Visuals.luau` (nouveau) | `RecordTable[1..20]` (déblocages nommés de l'aperçu + éléments du ranch, GDD §4.29), `Tiers` (Tapis 6, Gants 9, tablier 5, Enclos 3), `RanchTiersAt`, `Faces`, `Eyes`, `Palettes` (8), ciel, halo, `SuffixColors` (6 familles de suffixes, K-M … Vg-Tg, GDD §4.2, critique M11 ; lu par `UI/Format`, B1) |
| `src/shared/Config/Cosmetics.luau` | `DecoPerso` (40 objets, taille, source), `WeeklyRotation` (8), `ListV2` (85 : selles, traînées, drapeaux, tenues, emotes, 51 titres, 11 habillages en `theme`), à part de `Cosmetics.List` jusqu'à l'étape I |
| `src/shared/Config/{Quests,Events}.luau` | `Quests.WeeklyTrack`, `Quests.Challenges` (12), `Quests.Carnet` (8 paliers et récompenses), `Quests.Mastery` (5 tours) ; `Events.Weather` (visuelle seulement), `Events.Fete`, `Events.StarRain` |
| `src/shared/Config/{Sounds,Console}.luau` | 12 sons v2.0 muets (`id = ""`) ; vibrations `tierUp`, `chantier`, `ascend` |
| `src/shared/Remotes.luau` | 5 intentions + `UpgradeResult` (event) + `HelperPress` (unreliable), créés par `Net.setup`, écoutés par personne |
| `src/shared/Types.luau` | `PrestigeKind`, `UpgradeCurrency`, `UpgradeSnapshot`, `UpgradeResultPayload`, `HelperPressEntry`, `HelperPressPayload`, `HelperState`, `CelebrateKindV2` et ses charges, `RanchAttributesV2`, `ChallengeEntry` |
| `src/server/Signals.luau` | `PrestigeApplied`, `UpgradeBought`, `ConfettiChanged`, `RecordReached`, `HelperPressed` |
| `src/server/Data/Schema.luau` | Schéma v2 décrit et testé, **non activé** : `LATEST = 2`, `VERSION = 1` tant que `SchemaV2` est coupé ; `defaultsV1`, `defaultsFor(v)`, `OWNERS_V1`, `OWNERS_V2`, `ownersFor(v)`, `migrate(data, from, to?)`, `migrateV1toV2`, `confettiCatchUp`, constantes figées `MIGRATION_V2` (§27.2) |
| `src/shared/Localization/Strings.luau` | 435 clés v2.0 en EN et FR (écran Améliorations, Atelier, renaissances, Plopettes, Monuments, paliers, déblocages, habillages, ciel, halo, Annexe B complète : 40 objets de Déco perso, 8 cosmétiques de la semaine, 36 + 15 titres, 12 Défis, 5 tours) |
| `tests/harness/TextFitKeys.luau` (outil d'écrans, autre équipe) | Une clé que le client ne référence pas encore (contrat d'un écran à venir) est acceptée par `TextFit_all` sans ligne en attente ; dès qu'un paquet l'affiche, elle doit être prouvée dans les deux langues, à Medium et au pire cas |
| `tests/fixtures/profiles/v1.json` (nouveau) | Profil v1 réaliste de la version de test (Record R 12, Enclos 12/14, Lit, 4 squishies, Squishydex, objectifs, passes, reçus) |
| `tests/fixtures/profiles/v2.json` (nouveau) | Sauvegarde-témoin v2 : `v1.json` migrée (`migrate(1 → 2)` puis `reconcile`), figée ; `Contract_v2` › « v2.json (témoin) » : chaque valeur du témoin sort de la migration telle quelle, et le témoin chargé en v2 ne perd rien (base des migrations v2 → v3). Une valeur de migration changée exprès = témoin régénéré dans le même lot, raison au journal |
| `tests/specs/Contract_v2.spec.luau`, `Contract_upgrades.spec.luau`, `Contract_unlocks.spec.luau`, `Contract_glyphs.spec.luau` (nouveaux) ; `Contract_game.spec.luau` | Témoins v2.0, migration, interrupteurs, catalogues, contenu nommé, textes ; disposition v2.0 (zones de l'écran Améliorations, rectangles du HUD) ; personnalités ; règle 18 sur la table `cmap` des deux polices (clés EN et FR, et sorties des formateurs `Logic/BigNumber` et `Util/Format`) ; `Contract_game` connaît les remotes v2.0 |

**Pas de stubs de modules.** Le contrat v1.x posait des stubs `error("TODO(...)")` ; depuis l'intégration du 2 novembre, `Fix_validation.spec` interdit toute marque `TODO(` dans `src/`. Les modules nouveaux ne sont donc **pas** créés par le contrat : leur fichier, leur paquet et leur API exacte sont écrits au §27.7 ; le paquet qui en est propriétaire crée le fichier avec ces signatures (et peut en ajouter, jamais en retirer). Ordre de foi inchangé : le code du contrat, puis ce chapitre, puis le GDD.

### 27.1 Paquets v2.0 et propriété des fichiers

Règles du §2 reprises : **un fichier = un paquet** pendant la v2.0 ; un paquet ne crée et ne modifie que ses fichiers et ses specs `tests/specs/<Nom>.spec.luau` ; un besoin ailleurs = **note d'intégration** (fichier, changement exact, raison) ; registres partagés (`Strings`, `Remotes`, `Types`, `Config/Sounds`) en ajouts ciblés, relus juste avant chaque `Edit`. **Deux voies** (E1 serveur et logique, puis rendu des squishies ; E2 interface et monde) qui ne partagent **aucun fichier** après P0 ; elles se parlent par les types et les charges utiles figés au §27.5. Le fichier JSON des paquets (`scratchpad/arch-packages-v2.json`) reprend ce tableau.

| Paquet | Voie | Possède (fichiers créés ou modifiés) | Dépend de | Durée |
|---|---|---|---|---|
| **P0** Contrat v2.0 (fin) | E1 | `docs/04` (v2.0), `default.project.json` (éclairage N12, à l'intégration seulement), `src/shared/Config/{Features,Upgrades,IntentsV2,Intents,Balance(structure),Layout,Quests,Events,Cosmetics,Species,Settings,Console,Sounds,Visuals}.luau`, `Types`, `Remotes`, `Strings`, `src/server/{Signals,Data/Schema}.luau`, `tests/fixtures/profiles/{v1,v2}.json`, `assets/fonts/*` (FredokaOne OFL, LuckiestGuy Apache 2.0), `Contract_v2`, `Contract_upgrades`, `Contract_unlocks`, `Contract_glyphs`, `Contract_game` | — | **fait** (§27.0, 3 novembre 2026) ; reste, au fil des lots : `Config/Settings.haloOn` et ses clés (avec A4), notes INT-V2-ORDER et INT-V2-INTENTS (avec A2, A3, A4, B5), INT-V2-GLYPHS (Strings, avec B1) |
| **A1** Logique de progression et porte d'économie | E1 | `src/shared/Logic/{Prestige,UpgradeMath,UpgradeAdvisor,Bitset,TierRules}.luau` (nouveaux), `Logic/{Formulas,QuestRules,Invariants,BigNumber}.luau`, valeurs de `Config/Balance` (tables v2.0), `tests/sim/EconomyModel.luau`, `tests/specs/EconomyPacing.spec.luau` | P0 | 5 j |
| **A2** Serveur de progression | E1 | `src/server/Services/{EconomyService,SplorchService,RanchService,DataService}.luau`, `src/server/Data/ProfileRepair.luau`, `src/server/Ranch/*`, `src/server/Chase/Splorch*` (aide) | A1 | 6 j |
| **A3** Plopettes, serveur | E1 | `src/server/Services/HelperService.luau` (nouveau), `src/server/Helpers/*` (nouveau), `src/server/Util/Activity.luau` (ajout `lastIntent`, N23 : §27.7), `src/server/Main.server.luau` (ligne `HelperService` dans `ORDER`, note au contrat appliquée par A3) | A2 | 4 j |
| **A4** Méta v2.0 | E1 | `src/server/Services/{QuestService,CommunityService,EventService,LeaderboardService,DiagnosticsService}.luau`, `src/server/Meta/*`, `src/server/Util/Analytics.luau` (note INT-ANALYTICS : seul éditeur ; événements v2.0 du §27.14) | A2 | 8 j |
| **B5** Vie des squishies | E1 | `src/shared/Render/SquishyBuilder.luau`, `src/client/World/Personality.luau` (nouveau), `src/client/Controllers/{HelperRenderer,VFXController,CameraController}.luau` | A3, A4, B1 | 8 j |
| **B1** Fondations de l'interface | E2 | `src/client/UI/{Theme,Text,Format,FocusGuard,Glyph,Toast,WorldText}.luau`, `src/client/UI/Hud/Util.luau`, `src/client/UI/Panels/Widgets.luau`, `src/client/Controllers/{InputController,LightingController}.luau` (politique de texte seulement, N10, puis rendus : `LightingController` à B4, `VFXController` à B5), `src/client/UI/Panels/Diagnostics.luau` (panneau TextProbe), `tests/harness/{TextMetrics,MockInstance,EngineProps,ApiAudit}.luau` | P0 | 5 j (peut commencer pendant P0) |
| **B2** Écran Améliorations | E2 | `src/client/UI/Panels/Upgrades.luau`, `src/client/UI/{UpgradeCard,UpgradeSnapshot}.luau` (nouveaux), `src/client/UI/{HUD,PanelController}.luau`, `src/client/UI/Hud/*` (hors `Hud/Util.luau`, à B1) | B1, A1 (`UpgradeMath`, `UpgradeAdvisor`) | 9 j |
| **B3** Écrans de renaissance et de méta | E2 | `src/client/UI/Panels/{SplorchPreview,Ranch,Squishydex,Objectives,Settings}.luau`, `src/client/UI/{Cards,Banners,ReturnScreen}.luau` | B2 | 8 j |
| **B4** Le ranch qui évolue | E2 | `src/client/Controllers/{RanchRenderer,LightingController}.luau`, `src/client/Render/{BuildCascade,VisualBudget,AmbienceDirector}.luau` (nouveaux), `src/shared/Logic/{RanchLook,AmbienceRules,WorldLayout}.luau`, `src/server/Services/WorldService.luau`, `src/server/World/*` | B1, A1 | 9 j |
| **I** Intégration | les deux | ouverture des interrupteurs, `SchemaV2`, `Contract.spec` (VERSION 2), `Boot.spec`, `Soak.spec`, `Soak_queue.spec`, `ClientReplay.spec`, `Screens`, `TextFit_all` sans clé v2.0 en attente | tous | 4 j |

**Fichiers touchés par deux paquets : aucun en même temps.** Trois passages de main, datés dans le plan : `LightingController` (B1 pour la politique de texte, jours 1-5, puis B4) ; `VFXController` (B1, puis B5 après le jour 26 environ) ; `WorldLayout` (B4 seulement ; A3 lit `WorldLayout.helperHouse`, écrit par B4 au début de son lot, ou demande une note). `Main.server.luau` et `Main.client.luau` sont des fichiers du contrat : A3 (`HelperService`) et B5 (`HelperRenderer`) y ajoutent leur ligne par note d'intégration appliquée par le contrat dans le même lot, et `Contract_game.spec` (`SERVER_ORDER`, `CLIENT_ORDER`) suit. **Ordre** : P0 → A1 (porte d'économie verte avant tout autre code serveur) → A2 → A3 → A4 → B5 sur la voie E1 ; B1 → B2 → B3 → B4 sur la voie E2 ; I à la fin.

**Ordres d'initialisation v2.0** (à poser par les notes ci-dessus) : serveur — `HelperService` juste après `SplorchService` (il lit EconomyService, SquishyService et SplorchService ; ChaseService, dernier, le « stèpe » dans son tick de 10 Hz, règle 7 du §1 : aucune nouvelle connexion `Heartbeat`) ; client — `Controllers.HelperRenderer` juste après `Controllers.ChaseRenderer` ; l'écran Améliorations n'est pas dans l'ordre : `PanelController` le construit avec les autres panneaux.

### 27.2 Données : schéma v2, migration exacte, réparation

**Activation.** `Schema.VERSION = if Features.Defaults.SchemaV2 then 2 else 1` ; `SchemaV2` est **figé** (`Features.Static` : jamais changé en direct). Tant qu'il est coupé, `defaults()` = `defaultsV1()` (la v1 de la version de test, jamais modifiée), `OWNERS` = `OWNERS_V1`, et `migrate(data, from)` sans cible ne dépasse jamais la v1. L'étape d'intégration passe `SchemaV2` à `true` dans **le même lot** que : `Contract.spec` (VERSION 2, `STORE_NAME` inchangé `PlayerData_v1`), `ProfileRepair` v2 (A2), `Invariants` v2 (A1), les interrupteurs v2.0. Avant ce lot, aucune sauvegarde v2 n'est jamais écrite.

**Champs ajoutés** (`Schema.defaultsFor(2)` ; un seul écrivain par clé, `Schema.OWNERS_V2`)

| Clé | Type, défaut, bornes | Écrivain unique | Réplication |
|---|---|---|---|
| `bestR` | entier, 0, `R ≤ bestR ≤ 400` | SplorchService (`Prestige.apply`) | attribut public `BestR` |
| `ascend` (champ réservé de la v1 devenu A) | entier, 0, 0-60 | SplorchService | attribut public `Ascend` |
| `regainBonusA` | entier 0-60 : dernier A dont le bonus de retour au record (+10) a été donné | SplorchService | profil |
| `memoryR` (lot A2, décision INT-A1-MEMORY, A2-1) | entier, 0, `0 ≤ memoryR ≤ bestR` (≤ 400) : Record R au moment du dernier retour au record après une Ascension ; la 1re boucle record qui suit (× 1,25, `Prestige.firstRecordLoop`) est celle où r = bestR = memoryR | SplorchService (`Prestige.apply`) | profil |
| `confetti`, `confettiTotal` | entiers, 0, 0-1e9, `confetti ≤ confettiTotal` | EconomyService : `addConfetti` (gains) et `buyUpgrade` (dépenses) **seulement** | profil |
| `tiles.star`, `tiles.gloves`, `tiles.school`, `tiles.monuments` | entiers 0-8, 0-40, 0-20, 0-10 (Monuments gardés) | EconomyService | profil ; paliers et `Monuments` publics |
| `atelier` | tableau dense, une case par ligne de `Config/Upgrades.WorkshopRows` (10, ordre définitif), bornée par `#costs` | EconomyService | profil |
| `atelierCosmetics` | ensemble de bits (11 : `Upgrades.CosmeticBits`) | EconomyService | profil |
| `decorBuilds` | 18 entiers 0-10 (décorations dorées) | EconomyService (au Grand Splorch) | public (dorées) |
| `stats.upgradesBought`, `stats.petitSplorches` | entiers ≥ 0 | QuestService (`stats`, propriétaire v1) sur `UpgradeBought` / `PrestigeApplied` | profil |
| `carnet` | ensemble de bits (8 paliers) | QuestService | profil |
| `weeklyTrack` | `{ period, points, claimed (bits, 12), challenges = { Types.ChallengeEntry × 3 }, firstPeriodEnd }` | QuestService | profil |
| `mastery` | ensemble de bits, un par espèce (agrandi par `reconcile`) | QuestService | profil |
| `unlocksSeen` | entier 0-400 | QuestService | profil |
| `onboarding.nextBuyShown`, `onboarding.welcomeV2Pending` | booléens, `false` | QuestService | profil |
| `season.frostDays` | entier, 0 (`season.premium` gardé, jamais effacé) | QuestService | profil |
| `caps.fameSplorch`, `caps.starRain` | compteurs du jour, bornés par `Balance.CapsV2` | EconomyService (propriétaire de `caps`) | privé |
| `decoPerso` | `{ owned = bits (64), slots = 12 entiers (0 = vide) }` | CommunityService | public `DecoPerso` |
| `hearts` | `{ givenDay, givenTo (≤ 20 UserIds), receivedTotal }` | CommunityService | privé |

**Ensembles de bits** : tableau dense de mots de 32 bits (`{number}`, longueur `ceil(n / 32)`, au moins 1), lus et écrits **seulement** par `Logic/Bitset` (jamais un `number` de 64 bits : `bit32` travaille sur 32 bits). **Habillages** (décision C2) : pas de champ `ranchSkin` ; les 14 habillages sont les valeurs de `cosmetics.theme` (3 de la v1.3 + 11), équipés par l'intention existante `EquipCosmetic("theme", id)`, répliqués par le thème public de la v1.3. **Halo** : `settings.haloOn` arrive par `Config/Settings` (`saved = true`, défaut `true`) au lot A4, avec son affichage dans le panneau Réglages derrière `RanchSkins`.

**Migration v1 → v2** (`Schema.migrateV1toV2`, étape pure appelée par `migrate(data, from, to)` si `from < 2 ≤ to`) : (1) `bestR = R`, `ascend = 0` ; (2) Confettis du premier passage : `confettiCatchUp(R) = Σ_{k=1..R} (3 + min(k, 20)) + 10 par k ≥ 21` ; (3) places offertes aux Record R 2, 6, 11, 16 déjà atteints : +1 niveau d'Enclos (14 au plus), **+25 Confettis** chacune si la dalle est pleine ; (4) `unlocksSeen = R` ; (5) `stats.upgradesBought` = Tapis + Décorations + Enclos (avant les places offertes) + Lit ; `decorBuilds[k] = 1` pour chaque décoration construite ; (6) `onboarding.welcomeV2Pending = (R ≥ 1)` (une carte « Bienvenue dans la v2 ! » au lieu de R cartes « Nouveau ») ; (7) `weeklyTrack.firstPeriodEnd = 0` : **QuestService** le fixe au premier chargement v2 (2e lundi après `Clock.unix()`, `QuestRules.trackPeriod`) — la migration reste pure ; (8) `version = 2` ; (9) **chaque autre champ ajouté par la v2** (clé de premier niveau, ou sous-clé d'une table de la v1 : `tiles.star`, `caps.starRain`, `season.frostDays`, `memoryR`…) est **écrit** à sa valeur par défaut v2 par la migration (lot A2, A2-3) : une valeur trouvée sous une clé v2 dans un profil v1 ne passe jamais en v2 ; les clés inconnues sont gardées ; `reconcile(defaultsFor(2))` complète ensuite. **Constantes figées** `Schema.MIGRATION_V2` (jamais liées à `Config/Balance` : deux joueurs migrés à un mois d'écart reçoivent le même rattrapage). **Garanties testées** (`Contract_v2.spec`) : profil v1 de la version de test → Record R 12, Enclos 14, 114 + 25 Confettis ; **chaque valeur v1 gardée** (seuls `tiles.pens` et `version` changent) ; aller-retour JSON exact ; **idempotente** (un profil déjà v2 n'est jamais retouché : garde sur `data.version`) ; sauvegarde abîmée (R `NaN`, `tiles` illisible, `stats` absent) sans erreur et bornée ; profil v2 plein < 20 Ko. **Anciens serveurs** : pendant un déploiement, un serveur encore en v1 qui lit un profil v2 le **refuse** sans rien écrire (`DataService`, schéma plus récent : renvoi poli « Ce serveur n'est pas à jour », verrou non pris, aucune sauvegarde) — testé avec un vrai profil migré.

**Réparation et invariants v2** (A2 : `ProfileRepair` ; A1 : `Logic/Invariants`) : bornes de chaque champ ci-dessus ; `bestR = max(bestR, R)` ; `atelier` allongé ou raccourci à `#WorkshopRows`, chaque case ≤ `#costs` ; `confetti ≤ confettiTotal ≤ 1e9` ; ensembles de bits allongés à leur taille ; `decoPerso.slots` vers un objet non possédé → 0 ; `hearts.givenTo` tronqué à 20 ; `cosmetics.theme` inconnu ou non gagné → `"color"`. Invariants : `R ≤ bestR ≤ MaxR`, `0 ≤ ascend ≤ MaxA`, chaque niveau ≤ son maximum, `tiles.star ≤ Prestige.starCap(R)`, décorations gardées ≤ 12, **toutes** les tailles (enclos, Bassin, Dodo, Lettres, porté) = 1 juste après un prestige. Chaque réparation est comptée par Diagnostics (`ProfileRepaired`).

**Réparation v2 : règles du lot A2** (A2-2, A2-4) : la réparation v2 se choisit sur la **version du profil** (≥ 2), jamais sur celle du serveur ; un profil v1 est réparé exactement comme dans la version de test (modèle `Schema.defaults()`, aucun champ v2 lu ni écrit, R borné à 1e6). Bornes de plus : `R ≤ 400` ; `ascend` 0-60 ; `regainBonusA ≤ A` ; `memoryR ≤ bestR` ; `version` entier ≥ 2 ; chaque niveau ≤ `UpgradeMath.cap` tous interrupteurs ouverts (même règle que `Invariants`) ; `decorBuilds` 18 × 0-10 ; piste (3 Défis au plus, chacun une fois, id connu) ; `unlocksSeen ≤ bestR`. Valeur sûre d'une valeur illisible : celle qui ne donne jamais rien deux fois — `regainBonusA` → A, `memoryR` → 0 (aussi au-delà de `bestR`), `unlocksSeen` → `bestR`, mot de bits abîmé → 0, emplacement vers un objet non possédé ou déjà posé → 0 ; Confettis en poche > total → **total relevé** (jamais un Confetti de poche perdu) ; ensembles de bits jamais tronqués en deçà de `Bitset.MaxBits` (un bit au-delà de n peut être celui d'une espèce ou d'une ligne future) ; habillage : condition lisible dans le profil (Record R, A, Squishydex, jours de Plop), une autre source n'est jamais retirée ici. Specs : `ProfileRepair_v2`, `DataChaos` › schéma v2, `Contract_v2`.

### 27.3 Interrupteurs (`Config/Features`) : coupés jusqu'à la relecture du paquet

| Interrupteur | Ouvre | Paquet qui l'implémente | Valeur de lancement |
|---|---|---|---|
| `SchemaV2` (figé) | schéma v2 et migration | P0 + A2 | `true` à l'étape I |
| `RecordR` | `bestR` séparé de r : tout ce qui est débloqué lit le Record R (N1) | A1 + A2 | `true` |
| `UpgradesScreen` | écran Améliorations, `BuyUpgrade`, puce « Prochain achat », rail v2.0 | A2 + B2 | `true` |
| `Confetti` | 2e monnaie (gains, en-tête, tuile d'aperçu) | A1 + A2 + B2 | `true` |
| `Workshop` | Atelier (9 lignes), kiosque de Big Plop | A2 + B2 | `true` |
| `StarMat`, `Gloves`, `Monuments` | familles nouvelles | A1 + A2 + B2 + B4 | `true` |
| `JellyAscend`, `PetitSplorch` | 2e couche de renaissance, Petit Splorch hors file | A2 + B3 + B5 | `true` |
| `Helpers` | Plopettes, École, Plume | A3 + B5 | `true` (décision par défaut n° 3) |
| `WeeklyTrack`, `Carnet`, `Mastery` | piste de la semaine et Défis, Carnet du Ranch, maîtrise et jalons géants | A4 + B3 | `true` |
| `RanchTiers`, `Ambience` | ranch qui évolue, directeur d'ambiance et Unified Lighting | B4 | `true` |
| `RanchSkins`, `DecoPerso`, `Hearts`, `PhotoMode` | 11 habillages de plus, Déco perso, cœurs, mode photo | A4 + B3 + B4 | `true` |
| `Weather`, `Fete` | météo **purement visuelle** (décision n° 4), place en fête | A4 + B5 | `true` |
| `Personalities` | personnalités, saynètes, visages, tours | B5 | `true` |

Règles : (1) **coupé = le code v2.0 ne fait rien** : aucune intention envoyée, aucun handler branché, aucun champ lu ni écrit, aucune instance créée, aucun texte affiché ; (2) chaque paquet teste **les deux états** (interrupteur coupé : la spec du jeu de base correspondante reste verte telle quelle ; ouvert : ses specs v2.0) ; (3) l'écran fige la liste de ce qui est ouvert à l'ouverture (règle 19) ; (4) `Features.set` refuse `SchemaV2` ; les autres se changent en direct par LiveOps comme en v1.3 ; (5) les valeurs de lancement (`true`) sont posées à l'étape I, **dans le même lot** que la mise à jour de `Contract_v2.spec` (« coupé par défaut » devient « ouvert au lancement ») et des specs du jeu de base dont l'attente change avec le GDD v2.0 (N1-N25 du §27.13, raison au journal §27.12). `Features.Defaults.Season` reste `false` (saison de 28 jours supprimée, GDD v2.0).

### 27.4 Signaux internes v2.0 (`src/server/Signals.luau`)

| Signal | Émetteur | Arguments | Consommateurs |
|---|---|---|---|
| `PrestigeApplied` | SplorchService, après `Prestige.apply` | `(player, kind: "splorch" \| "petit" \| "ascend", fromR, toR, A)` | QuestService (piste, cartes), HelperService (reprise), RanchService (attributs), LeaderboardService (Livre des records), analytique |
| `UpgradeBought` | EconomyService.buyUpgrade (et BuyTile) | `(player, id, fromLevel, toLevel, currency)` | QuestService (Carnet, objectifs), RanchService (paliers, cascade) |
| `ConfettiChanged` | EconomyService | `(player, delta, source)` ; sources : `"splorch"`, `"petit"`, `"skipped"`, `"ascend"`, `"regain"`, `"record"`, `"fullPen"`, `"track"`, `"mastery"`, `"spend"` | QuestService (Défi n° 2), analytique `ConfettiEarned` |
| `RecordReached` | SplorchService, premier passage d'un Record R | `(player, bestR)` | QuestService (carte « Nouveau », `unlocksSeen`), CommunityService (cosmétiques gagnés), RanchService |
| `HelperPressed` | HelperService, pression accordée à `tPress` | `(player, helper, uid, coins)` | EconomyService (crédit, source `Helper`) ; **jamais** la jauge, les objectifs ni les classements |

`TileBought` (v1.3) reste émis pour les 4 dalles (étape 3 de l'accueil, objectifs) ; `UpgradeBought` est émis **en plus** pour tout achat, dalles comprises.

### 27.5 Réseau : intentions, charges utiles, attributs

**Catalogue.** Les intentions v2.0 vivent dans `Config/IntentsV2` (même forme que `Config/Intents`, plus `feature`). **Le paquet qui branche un handler déplace la ligne vers `Config/Intents` dans le même lot** (note au contrat) et met à jour les specs `Remotes_<paquet>` qui comptent les intentions de leur propriétaire (`Remotes_Meta` en attend 15 aujourd'hui) ; une intention n'est jamais dans les deux catalogues (`Contract_v2.spec`). Ordre de chaque handler (règle 3 du §1) : débit → types → existence → état → règles → mutation atomique → réplication ; refus = aucune mutation.

| Intention | Arguments | Propriétaire | Débit | Règles (dans l'ordre) | Réponse |
|---|---|---|---|---|---|
| `BuyUpgrade` | `id: str ≤ 24`, `mode: int 0-10` (1, 10 ou 0 = Max ; autre valeur refusée), `expectedLevel: int 0-64` | EconomyService | 10 / s | `id` ∈ `Upgrades.Families` ∪ `WorkshopRows` ∪ lignes « bits » de `Fun` ; interrupteur ouvert ; `expectedLevel` = niveau actuel (sinon refus **périmé** : muet si l'instantané du client montre déjà ce niveau, compteur `UpgradeStale`) ; famille ouverte (`UpgradeMath.cap > niveau`) ; aucun prestige en cours d'application pour ce joueur ; règlement du Pot, puis `n = min(demandé, payable, restant, Balance.Upgrades.BulkMax)` et somme exacte `UpgradeMath.bulk` ; **un seul bloc** (pièces ou Confettis, niveau, `stats`, signaux) ; position non exigée | `UpgradeResult` **toujours** (refus périmé muet dedans : `reason = nil`, `from = to`, `spent = 0`, lot A2, A2-10), `DataPatch` avec le même instantané |
| `BuyTile` (v1.3) | inchangé | EconomyService | 10 / s | même fonction que `BuyUpgrade(tile, 1, niveau actuel)` ; `snack` achète aussi le Tapis Étoilé ouvert (N21) | inchangée + `UpgradeResult` quand `UpgradesScreen` est ouvert |
| `JellyAscend` | `confirm: bool` (true exigé) | SplorchService | 1 / 5 s | `Prestige.ascendReady` (r ≥ condition, A < 60) ; dans son ranch, rien porté, aucun squishy en fuite ; **un seul prestige par joueur** dans la file (« Ton Grand Splorch passe d'abord ! ») ; vérifié une fois, à l'entrée dans la file | `Celebrate("ascend")` à tous ; `Banner("ascend")` |
| `GrandSplorch` (v1.3) | inchangé | SplorchService | 1 / 2 s | Petit Splorch si **r après la renaissance ≤ `bestR`** : hors file, appliqué tout de suite ; si Grand Splorch et Ascension sont prêts, le rail propose le Grand Splorch d'abord | `Celebrate("petitSplorch")` au joueur ; attribut `PetitSplorchAt` |
| `PlaceDeco` | `item: int 0-64` (0 = retirer), `slot: int 1-12` | CommunityService | 4 / s | objet possédé (`Bitset`), emplacement de la bonne taille (8 petits, 4 grands), pas déjà posé ailleurs | attribut `DecoPerso` |
| `GiveHeart` | `ownerId: userId` | CommunityService | 2 / s | présent, pas soi, pas bloqué, 1 par ranch et par jour, `Balance.Hearts.PerDay` | `Feedback` aux deux |
| `SetPhotoMode` | `on: bool` | CommunityService | 1 / s | analytique ; personnage figé **et visible** des autres (N22) ; aucun avantage | — |
| `SetSetting` (v1.3) | + `haloOn` | CommunityService | 4 / s | comme v1.3 | — |
| `EquipCosmetic` (v1.3) | `theme` accepte les 14 habillages | CommunityService | 2 / s | habillage gagné (Record R, A, Carnet, Squishydex, jours de Plop) | thème public |

Pas de remote pour réclamer un palier de la piste ni du Carnet : QuestService les donne tout seul.

**Serveur → client**

| Remote / attribut | Charge utile (`Shared/Types`) | Destinataires |
|---|---|---|
| `UpgradeResult` (event) | `Types.UpgradeResultPayload = { id, from, to, spent, currency, reason?, snapshot }` ; `reason` ∈ `upgrades.refused.{coins, confetti, locked, maxed, loopCap, busy}` | le joueur |
| `DataPatch` (v1.3) | porte aussi `upgradeSnapshot: Types.UpgradeSnapshot` (même `version`) | le joueur |
| `HelperPress` (unreliable, regroupé par tick) | `Types.HelperPressPayload = { ownerId, presses = { { helper, uid, tPress } } }` ; l'issue arrive par `DataPatch` | le joueur et les clients qui dessinent ce ranch en détail complet |
| `Celebrate` (v1.3) | + `Types.CelebrateKindV2` (`petitSplorch`, `ascend`, `tier`, `unlock2`, `confetti`, `trackTier`, `carnet`, `mastery`, `regainDone`, `recordStep`, `welcomeV2`) et leurs charges ; fusionnées dans `CelebrateKind` (et la table du §10.3) à l'étape I | le joueur (tous pour `ascend`) |
| `Banner` (v1.3) | + `ascend.banner`, `monument.banner` (clés hors de la famille `banner.*` jusqu'à ce que B3 les montre) ; 1 bannière de Grand Splorch par joueur toutes les 180 s (`SplorchV2.BannerGap`) | tous |
| Attributs du ranch (RanchService) | `Types.RanchAttributesV2` : `BestR`, `Ascend`, `SplorchReady`, `AscendReady`, `PetitSplorchAt`, `Monuments`, `DecoPerso`, `HaloOn`, `TapisTier`, `GloveTier`, `ApronTier` | tous |
| `EventState` (v1.3) | + `weather = { kind, endsAt }`, `fete = { level }` (visuels seulement) | tous |

**Instantané versionné** (règle 6) : `version` croît de 1 à chaque mutation d'une valeur qu'il porte (achat, règlement qui change `coins`, prestige, Confettis) ; le client ignore tout instantané de `version` ≤ celle affichée ; l'état « payable » ne se calcule que sur lui.

### 27.6 Configuration v2.0

**`Config/Upgrades`** (fait) : `Tabs`, `Modes`, `Families` (ordre fixe : `snack`, `star` sur la même ligne, `decor`, `pens`, `cozyBed`, `gloves`, `monument`, `school`), `ReadOnly` (6 Plopettes + `risesWithRecord`), `WorkshopEffects` (liste fermée), `WorkshopRows` (`gift`, `startMat`, `magnet`, `superStreak`, `keptDecor`, `nightBag`, `nightPot`, `plume`, `springboard`, `decoShop`), `Fun` (palettes, selle, traînée, emote, fanions, titre, Déco perso), `CosmeticBits = 11`, `ById`, `WorkshopIndex`. Chaque famille : `price` = `"tile:<clé>"` (Balance.Tiles) ou `"price:<clé>"` (Balance.UpgradePrices), une seule source ; `open` = `{ recordR?, ascend?, loopCapByR?, recordRByLevel? }`, lu par le serveur seulement.

**`Config/Balance`** (structure faite, valeurs de départ du GDD v2.0, réglées ensuite par A1 seul) : voir §27.0. **Règle des prix** (`UpgradeMath.price`) : `max(1, floor(base × g^L × RScale^r × F(A)))`, calculé par multiplications successives dans cet ordre ; `star` part du prix du Tapis 12 **avant** `floor` ; `monument` = `3 × T12 × RScale^(OpenAt[n]) × RScale^(r − bestR)`, sans F(A). Les tables v2.0 sont **à part** de `Balance.Tiles` et `Balance.Caps` (le code de base les parcourt : `EconomyService.applySplorch`, `Invariants`, `ProfileRepair`).

**`Config/Layout`** (fait) : `Layout.Upgrades` et `Layout.HudV2` (§27.8).

**Contenu nommé (fait)** : `Config/Visuals` (table du §4.29 : `RecordTable[R] = { unlocks = { {key, vars} }, ranch = { identifiants } }` ; `vars.name` est une **clé** de texte, traduite avant d'être posée), `Config/Cosmetics.{DecoPerso, WeeklyRotation, ListV2}` (sources v2.0 : `recordR`, `ascend`, `atelier`, `carnet`, `season`, `track`, `play`, `objectives`, `moon` en plus de celles de la v1.3), `Config/Quests.{WeeklyTrack, Challenges, Carnet, Mastery}`, `Config/Events.{Weather, Fete, StarRain}`, sons et vibrations v2.0 ; `Contract_unlocks.spec` les vérifie (chaque Record R 1-20 : une tuile nommée et un élément du ranch ; chaque objet : une source, une clé EN et FR, une place unique ; les objets de « Pour le plaisir » et du Carnet existent avec la bonne source). Les identifiants de récompense sont écrits `"<sorte>.<id>"` (`"saddle.brick"`, `"title.builder"`) partout. **Fait le 3 novembre 2026** : `Config/Species` colonne `perso` (6 valeurs, GDD §5.6 ; `Contract_unlocks` › « colonne perso : exactement la table du GDD », « proud réservé aux Légendaires, Mythiques et Secrets », « le serveur ne lit jamais la personnalité ») ; polices et `Contract_glyphs` (règle 18). **Reste à ajouter par le contrat** : `Config/Settings.haloOn` (`saved = true`, défaut `true`) et les clés `settings.haloOn` / `settings.haloOn.desc` avec A4 (le panneau Réglages construit ses clés par le préfixe `settings.` : elles ne peuvent arriver qu'avec la ligne qu'il affiche).

### 27.7 Modules nouveaux et API exactes (le paquet propriétaire crée le fichier)

Tous `--!strict`, purs quand ils sont dans `Shared/Logic`, sans `^`, `math.pow` ni `math.exp` dans `Prestige` et `UpgradeMath` (`Static_NoPow.spec`).

**`Shared/Logic/Prestige` (A1) — seule source de r, Record R et A.** `growthFactor(R: number, A: number, bestR: number, firstRecordLoop: boolean): number` (× 3^A par multiplications × Souvenir : 3 si `bestR − R ≥ 3`, puis 2, 1,5, et 1,25 sur la 1re boucle record) ; `memoryFactor(R, bestR, firstRecordLoop): number` ; `target(R): number` ; `isRecord(R, bestR): boolean` ; `reqR(k: number): number` (k-ième Ascension) ; `ascendReady(profile): boolean` ; `startR(A, springboard): number` ; `priceFactor(A): number` (produit de `PriceByA`) ; `confettiGain(kind: Types.PrestigeKind, R, bestR, skippedBySpringboard: number): number` (r compté jusqu'à `CapR`) ; `regainSpeedup(): number` (= `GrowthMult × RegainMult`, texte de l'aperçu) ; `validateConfig(balance): (boolean, string?)` (invariant de stabilité) ; `unlocksFor(bestR): { string }` ; `keptDecor(bestR, atelier): number` (≤ 12) ; `starCap(R): number` ; `apply(profile, kind, now): { [string]: any }` (un bloc, idempotent, ne touche que les champs « repart de zéro » ; remet à 1 **toutes** les tailles, Lettres et porté compris ; rend la liste des clés changées pour `markDirty`). Test statique `Static_PrestigeOnly.spec` : aucune lecture de `profile.R` hors de `Prestige` et `Schema` (et des modules v1.3 listés dans la spec, jusqu'à leur passage à `Prestige` dans A2).

**`Shared/Logic/UpgradeMath` (A1).** `price(id, level, R, A, bestR): number` ; `bulk(id, from, n, R, A, bestR): (count: number, total: number)` ; `maxAffordable(id, from, money, R, A, bestR): (count, total)` ; `cap(id, profile, features): number` (niveau maximal achetable maintenant : ouverture, plafond de boucle, interrupteur) ; `effect(id, level, ctx): { a: number, b: number, key: string }` (décorations : gain réel `0,05 ÷ A_bonus` ; Atelier : effet concret) ; `tier(id, level): number` ; `snapshot(profile, features, version): Types.UpgradeSnapshot`. Tables par multiplications successives, construites une fois au chargement ; même module sur le client et le serveur.

**`Shared/Logic/UpgradeAdvisor` (A1).** `cards(snapshot, ctx): { string }` (3 identifiants de famille, jamais deux fois la même, jamais une carte vide ; carte `"ascend"` si l'Ascension est prête et rien n'est payable depuis `Ascend.DeclineCardAfter`) ; `next(snapshot, ctx): { id: string, level: number, price: number }?` (recalculé après tout achat **et tout prestige** ; jamais un niveau déjà possédé ni inexistant).

**`Shared/Logic/Bitset` (A1).** `new(n): {number}`, `has(set, i): boolean`, `set(set, i)`, `clear(set, i)`, `count(set): number`, `grow(set, n)` (mots de 32 bits, `bit32`).

**`Shared/Logic/TierRules` (A1), `RanchLook` et `AmbienceRules` (B4).** `TierRules.of(familyId, level): number` ; `RanchLook.elements(bestR, A): { string }` ; `AmbienceRules.preset(stack): string`, `AmbienceRules.weather(unix): { kind: number, endsAt: number }?`.

**Modifiés (A1)** : `Formulas` (N2-N6 : croissance `× Prestige.growthFactor`, prix `× priceFactor`, revenu `× (1 + 0,01 × monuments)`, pression `× (1 + 0,025 × gants)` et série jusqu'à `5 + superSérie`, hors ligne `offlineGrowth(g, s, R, biggest, gMax)` arrêté à 120 s de croissance maximale, Sac et Pot de nuit) ; `QuestRules` (`weekIndex(unix)`, `trackPeriod(profile, unix)`, `challengeFeasible(id, ctx)`, `carnetTier(n)`) ; `BigNumber` (suffixes jusqu'à 1e93, notation e au-delà de 1e96) ; `Invariants.profile` v2.

**Serveur.** `EconomyService` (A2) : `buyUpgrade(player, id, mode, expectedLevel): Types.UpgradeResultPayload?` (handler de `BuyUpgrade` et de `BuyTile`), `addConfetti(player, n, source): number`, `snapshot(player): Types.UpgradeSnapshot`, `applyPrestige(player, kind)` (pièces, Pot, dalles de la boucle ; appelé par SplorchService). `SplorchService` (A2) : `petitSplorch(player)`, `ascend(player)`, `canPrestige(player): boolean` (un seul prestige par joueur). `RanchService` (A2) : `setV2Attributes(player, attrs: Types.RanchAttributesV2)`. `HelperService` (A3, nouveau) : `Init()`, `Start()`, `step(now)` (appelé par le tick de ChaseService), `state(player): Types.HelperState`, `pause(player, reason)`, `resume(player)` ; < 0,5 ms par tick à 16 joueurs × 6 aides. `QuestService`, `CommunityService`, `EventService`, `LeaderboardService`, `DiagnosticsService` (A4) : ajouts du §27.14, API publique nommée dans leur spec. `Server/Util/Activity` (A3, N23) : `lastIntent(player): number` (instant de la dernière **intention acceptée**, `-math.huge` sinon ; `noteMove` ne la change jamais : un stick calé ne retarde pas la sieste) ; `note`, `noteMove`, `isActive`, `lastActive` inchangés (jauge et MEGA du jeu de base).

**Client.** `UI/Text` (B1) : `Text.set(label, key, args?)` (seul écrivain de `.Text` côté client, `Static_TextSet.spec`), `Text.factor(): number` (facteur réel mesuré par une étiquette témoin cachée, au démarrage et à chaque changement de `PreferredTextSize`), `Text.compensate(label)` ; `UI/Format` (B1) : `multiplier(x, lang)`, `percent(x, lang)`, `seconds(x, lang)`, `level(a, b)`, `confetti(n, lang)` (entier brut jusqu'à 99 999), `roman(n)` (décor seulement) ; `UI/UpgradeSnapshot` (B2) : `apply(snap): boolean` (refuse une version plus ancienne), `current(): Types.UpgradeSnapshot`, `Changed: Signal` ; `UI/UpgradeCard` (B2) : `new(template: "card" | "row" | "tile", parent): Card`, `Card:set(state, view)`, 7 états (`ready`, `need`, `max`, `locked`, `loopCap`, `busy`, `retry`) ; `UI/Panels/Upgrades` (B2) : `build(root)`, `open(tab?)`, `close()`, `isOpen()` ; `Render/BuildCascade` (B4) : `push(job)`, `step(now)`, file de `BuildQueueMax` ; `Render/VisualBudget` (B4) : `declare(name, n)`, `take(name, n): boolean` ; `Render/AmbienceDirector` (B4) : seul écrivain de `Lighting` ; `Controllers/HelperRenderer` (B5) : `Init()`, `Start()` (saut réglé pour atterrir à `tPress`) ; `World/Personality` (B5) : saynètes en `CFrame` seulement.

### 27.8 L'écran Améliorations : contrat de disposition et les 20 règles

**Disposition** (`Config/Layout.Upgrades`, px TV de référence, GDD §10.7) : panneau `Layout.Panel.rect` 1 440 × 860 ; zones 12 + 88 (en-tête) + 64 (onglets) + 560 (contenu) + 120 (bandeau) + 16 = 860, largeur utile 1 376 ; en-tête : titre 48 px, pastille Souvenir x 320-680 (360 × 48, jamais sélectionnable, place réservée même cachée), groupe de droite pièces 280 + Confettis 200 + bouton de mode 200, écarts 16 ; **3 gabarits** d'un seul composant `UI/UpgradeCard` : carte 432 × 528 (3 par écran, écart 40), ligne 1 328 × 112 au pas de 128 (colonnes icône 16/80, texte 112/540, niveau 668/140, effet 824/240, état 1080/232), tuile 400 × 300 des aperçus (icône 120, titre 2 lignes de 36 px, valeur 40 px, marges 16) ; bandeau 1 376 × 120, phrases en 28 px, **2 lignes au facteur 1,5** ; ligne d'explication des aperçus 1 376 × 120 en 40 px ; boîte des refus 600 × 120 ; boutons de confirmation 360 × 112 ; budget 1 400 instances. HUD v2.0 (`Layout.HudV2`) : rail de 8 boutons de 80, écart 16, y 246-998, icônes 48 ; puce « Prochain achat » (96, 342, 440 × 96). **Entrées** : tout achat par un **maintien de 0,6 s** (×1 compris, `Balance.Upgrades.HoldSeconds`) ; `InputGuard` à l'ouverture de tout panneau (relâchement de ✕ vu + `GuardOpen` 0,3 s ; + `GuardFocus` 0,4 s après un changement de focus) ; achats sur `InputBegan` capté ; L1 / R1 changent d'onglet, ↑ atteint les onglets puis le bouton de mode ; ○ revient à ce qui a ouvert. **Textes** : clés `upgrades.*`, `workshop.*`, `fun.*` ; les libellés d'effet n'ont **pas** de flèche (icône dessinée entre l'avant et l'après, règle 18) ; chiffres arabes pour les états (« Record 6 », « Boucle 7 »).

**Les 20 règles et leurs tests** (bloquants dans `check.sh` ; paquet responsable entre crochets ; noms exacts du GDD §10.8)

| # | Règle | Spec › cas |
|---|---|---|
| 1 | Ordre fixe, aucun tri ; familles du Conseillé choisies à l'ouverture et au retour sur l'onglet | `Upgrades_Order.spec` › « 1 000 achats au hasard : ordre inchangé, sélection en place, aucune carte ne change de famille » [B2] |
| 2 | Aucune ligne créée ni détruite écran ouvert ; construit une fois | `Upgrades_Structure.spec` › « même nombre d'instances avant et après 1 000 achats » ; « une réouverture crée 0 instance » [B2] |
| 3 | Un compteur ne repart jamais de 0 | `Upgrades_Counters.spec` › « 50 changements d'onglet : aucun nombre ne vaut transitoirement 0 » [B2] |
| 4 | Valeur finale toujours posée | `Upgrades_Tween.spec` › « interruption à 0 %, 50 % et 100 % : même image finale » [B2] |
| 5 | Un seul calcul de prix, sans puissance | `UpgradeMath.spec` › cas exacts du §4.6 ; `Props_UpgradeMath.spec` › « bulk(n) = somme de n achats ×1 », « aperçu = débit réel (10 000 cas) », « coûts strictement croissants, Tapis 12 → Étoilé 13 compris », « jamais NaN ni inf à MaxR et MaxA » ; `Static_NoPow.spec` › « aucun ^ dans Logic/UpgradeMath et Logic/Prestige » [A1] ; témoins du contrat : `Contract_upgrades.spec` [P0, fait] |
| 6 | Un seul instantané versionné | `Upgrades_Snapshot.spec` › « correctif des pièces et UpgradeResult livrés dans les deux ordres : la colonne État ne clignote jamais (Prêt → Il manque → Prêt) » [B2] |
| 7 | Largeurs réservées | `Format_Widths.spec` › « 10 000 nombres tirés au hasard : largeur mesurée ≤ largeur réservée » [B1] ; `Props_BigNumber.spec` › « 1e300 et math.huge : le plus grand suffixe ou la notation e, jamais inf ni nan » [A1] |
| 8 | Un seul formateur par sorte de nombre ; tout texte par `Text.set` | `Format.spec` › « deux niveaux voisins donnent deux textes différents » ; « carte, ligne et bandeau montrent le même texte » [B1/B2] ; `Static_TextSet.spec` › « aucune affectation .Text hors de UI/Text ; aucun tostring, .. ni string.format de nombre dans UI/* hors de Text et Format » [B1] |
| 9 | Texte mesuré, une seule politique (jamais `TextScaled`) | `TextFit_all.spec` › « chaque clé de l'écran, EN et FR, à Medium et au pire cas (phrases × 1,5), dans sa boîte » [B2] ; `Text_policy.spec` › « contrainte respectée ou ignorée par le moteur : libellés à leur taille dessinée, phrases agrandies » [B1] |
| 10 | Tailles fixes calculées depuis la zone | `Layout_upgrades.spec` › « chaque rectangle enfant dans sa carte ou sa ligne, chaque carte dans la zone de 560, à 720p, 1080p et 4K, EN et FR » ; « aucun parent avec deux UI*Layout » [B2] |
| 11 | Un seul composant, 3 gabarits | `UpgradeCard.spec` › « chaque gabarit dans chacun des 7 états du §10.7.6 » ; « « ×3 à chaque boucle, pour toujours » (483 px à 36 px) tient en 2 lignes dans la tuile » [B2] |
| 12 | État « en cours » de 3 s ; refus périmé muet | `Upgrades_Pending.spec` › « serveur muet : retour en 3 s, focus intact » ; « réponse à 3,5 s puis nouvel appui : exactement un retour +n niveaux » [B2] |
| 13 | Jamais un achat muet | `Upgrades_Feedback.spec` › « 1 réponse = 1 retour » [B2] |
| 14 | Bouton remis à l'état normal ; focus dessiné à l'intérieur | `Console_upgrades.spec` › « après achat, Max, rafraîchissement : aucun élément appuyé » ; « le rectangle du cadre de focus est dans le rectangle de découpe de chaque ancêtre qui découpe, pour chaque ligne et chaque carte, dans chaque état » [B2] |
| 15 | Focus jamais perdu ni piégé | `Console_upgrades_nav.spec` › « croix + ✕ + ○ sur les 4 onglets et le bouton de mode, dans chaque état » (lignes en lecture seule sélectionnables, ✕ = `Bump`) [B2] |
| 16 | Aucun Robux dans cet écran | `Static_NoRobuxInUpgrades.spec` › « aucune clé de produit ni de pass dans UI/Panels/Upgrades » [B2] ; aucun champ de Robux dans `Config/Upgrades` : `Contract_upgrades.spec` [P0, fait] |
| 17 | Un ✕ n'achète jamais par accident | `Upgrades_InputGuard.spec` › « △ puis ✕ tenu 2 s : 0 BuyUpgrade » ; « maintien de l'Ascension prolongé : jamais confirmé » ; « 10 appuis à 100 ms sur la carte 1 : une seule famille » ; « chaque mode atteint avec le D-pad, ✕ et ○ seulement » [B1 partie générique, B2, B3] |
| 18 | Aucun symbole hors police | `Contract_glyphs.spec` › « chaque clé EN et FR n'utilise que des caractères de la table cmap de FredokaOne et de LuckiestGuy (fichiers de police rangés dans le dépôt) » et › « formateurs (Logic/BigNumber, Util/Format), EN et FR, de 0 à 1e300 » [P0, fait ; exceptions fermées du jeu de base : INT-V2-GLYPHS] ; aujourd'hui : `Contract_v2.spec` refuse → ✓ ★ ∞ ↺ dans `upgrades.*` [fait] |
| 19 | Seul le serveur dit ce qui est ouvert ; écran figé à l'ouverture ; fermé au début de son propre prestige | `Upgrades_Freeze.spec` › « changement d'interrupteur ou de plafond écran ouvert : rien ne change avant la prochaine ouverture ; jamais un achat refusé pour une ligne montrée ouverte » ; « Grand Splorch écran ouvert : fermeture, puis réouverture à l'état neuf » [B2] |
| 20 | Budget d'instances : 1 400 au plus | `Upgrades_Budget.spec` › « après la première ouverture : instances ≤ 1 400 ; réouverture : 0 instance créée » [B2] |

**Captures de référence** (outil Screens, style de repli à plat) : 24 états clés à 1 920 × 1 080, EN et FR, à Medium dans `check.sh` ; la matrice complète la nuit (GDD §10.8). Le vrai style (ombres, dégradés) se vérifie sur l'appareil (tests M6, M11, M14 de `docs/05`).

### 27.9 Porte d'économie v2.0 (ce que `EconomyPacing.spec` doit affirmer)

Le modèle `tests/sim/EconomyModel.luau` reçoit l'extension du dossier de travail du design (`scratchpad/v2/gdd/sim/`), avec `Config/Upgrades` et les tables v2.0 de `Balance` **lues directement** (aucune copie de valeur) et `MaxR`, `MaxA` appliqués. **Dans `check.sh`** (bloquant ; **56 s mesurées** le 5 novembre 2026, 3 min 21 s de calcul, au lieu de 5 min 52 s ; les 11 configurations des deux portes sont jouées par 4 processus fils `tests/sim/economy-worker.luau` à la fois, mêmes graines et mêmes joueurs au bit près que le calcul en place, `ECON_WORKERS=1` pour tout jouer dans un seul processus) : 20 joueurs par taille de serveur (4, 8, 16), référence 84 jours, assidu (2 h par jour) 28 jours ; **chaque clé bloque à sa vraie limite, sauf les 11 clés de queue** (plus bas), gardées en **alarme rapide**. **La nuit** (`scripts/economy-nightly.sh`, bloquant aussi, 20 cas, 4 à la fois : 47 min 31 s mesurées, 152 min de calcul) : **80 joueurs au moins** par configuration (`ECON_NIGHT_PLAYERS`, 20 pour les profils forcés, qui n'affirment que les bornes et la santé des renaissances), référence et assidu 140 jours, 10 et 20 min par jour, week-end, 6 h par jour, jamais l'Atelier, « refuse 3 jours », politique « Conseillé », gros acheteur (200 joueurs), configurations forcées A = 10, 20, 30 et 60 (par `Prestige.apply` répété) et « Atelier complet dès le début » ; **et les 6 configurations de check.sh sur 400 joueurs** (`ECON_TAIL_PLAYERS`, cas `tailsRef4`, `tailsRef8`, `tailsRef16`, `tailsAssidu4`, `tailsAssidu8` ; mêmes graines, les 20 premiers joueurs sont ceux de check.sh ; l'assidu du serveur de 16 est le cas `assidu140`, joué lui aussi sur 400 joueurs comme `ref140`), où **chaque clé, clés de queue comprises, est affirmée à sa vraie limite**. **Clés** (GDD §4.24.1, toutes celles de la v1.3 en plus) :

| Groupe | Clés et limites |
|---|---|
| Jalons v1.3 (gardés) | premier Grand Splorch 11-16 min ; première balade ≤ 5:00 ; R à 30 min 1-3 ; Record R jour 7 8-11, jour 14 14-16, jour 28 17-22 ; tampons jour 7 80-110 ; plus gros jour 7 4e7-4e8 ; part des pressions ≥ 50 % ; ×2 20-40 % ; `tapis12LoopShare` ≥ 0,5 ; Grands Splorch prêts à la connexion ≤ 50 % |
| Temps « sans but », référence | `starvedDay1` ≤ 1 % ; `starvedDay2to7` ≤ 5 % ; `starvedDay8to14` ≤ 15 % ; `starvedDay15to28`, `…29to56`, `…57to84`, `…85to140` ≤ 20 % ; profils 10 et 20 min, week-end : mêmes limites |
| Temps « sans but », assidu | `starvedAssiduDay2to7` ≤ 15 % ; `…8to14`, `…15to28`, `…29to56`, `…57to84`, `…85to140` ≤ 30 % ; `longestGapAssiduP90` ≤ 15 min dans chaque bande (**le but proche du joueur de 2 h par jour**, décision n° 6) ; 6 h par jour : ≤ 30 % par bande ; « refuse 3 jours » : limites de son profil |
| Boucles | `loopMaxGap` (r 0-13, avant toute Ascension) médiane ≤ 3 min et p90 ≤ 5 min, bloquant pour la référence ; `coinsLostRatioGrand` 0,2-3 T12 ; `shortestLoopSec` (≤ 0,3 % sous 45 s, chacune **cible atteinte** ≤ 10 s après une fusion, jamais 0 s ; l'écart va de la dernière fusion à l'instant où la cible de la boucle est atteinte, exact sur le segment de croissance en cours : ni le geste du Petit Splorch (2,5 s), ni la file du Grand Splorch, ni l'attente de la pression qui la voit, temps du joueur et non du jeu ; décision du chef, lot A2, A2-7 ; limite inchangée) ; `zeroGapRenaissances` = 0 |
| Jelly Ascend | `ascend1Day` 12-16 (référence), 5-9 (assidu) ; `ascendGapDays` 10-16 / 4-8 ; `regainRatio` 0,10-0,40 ; `regainCliff` ≤ 4 (médiane et p90) ; `recordRDay28` ≥ sans Ascension − 1 ; `tapis12RecordLoopByA` : médiane de chaque A de 1 à 30 dans [0,45 ; 0,95], toutes les boucles record dans [0,5 ; 0,9] ; `purchasesPerRecordLoopByA` ≥ 10 pour A = 1 à 30 |
| Confettis et Atelier | `confettiUnspent` ≤ 300 en poche (médiane) jusqu'au jour 84, référence et assidu ; `workshopAllDay` ≥ jour 35 ; `firstWorkshopBuy` ≤ 35 min ; `atelierEffect` rapporté |
| Familles | `everyFamilyBought` ≥ 80 % (Tapis, Tapis Étoilé, Décorations, Gants, École) ; `monumentsDay7` 1-3, `monumentsDay28` ≥ 4 ; `helperShareDay7` 5-15 % |
| Hors ligne, achats, bornes | `offlinePotShare` médiane ≤ 2 ; `spenderLeadTimeShare` ≤ 25 % (A1 à A7) ; `nonFinite` = 0 ; `MaxR`, `MaxA` jamais dépassés ; `Prestige.validateConfig(Balance)` vrai (invariant de stabilité, aussi dans `Props_Prestige`) |
| File du serveur | `queueWaitNewcomer` ≤ 40 s : spec `Soak_queue` (16 robots dont 8 vétérans en Petits Splorch) [A2] |

**Clés de queue : la règle du bruit d'échantillon** (décision du 5 novembre 2026, journal A1-28). Une limite n'est **jamais** assouplie ; une clé dont le bruit d'échantillon à 20 joueurs dépasse la marge est mesurée là où elle a un sens. Mesure : `ECON_NIGHT=spread` (400 joueurs = 20 blocs disjoints de 20 joueurs ; σ20 = écart type de la clé d'un bloc à l'autre). Une clé est **de queue** quand sa marge (valeur sur 400 joueurs → limite) est inférieure à 2 σ20 à l'une des 3 tailles de serveur. Sa vraie limite est affirmée **la nuit sur 400 joueurs** (σ400 ≈ σ20 / 4,5 ; à 80 joueurs plusieurs clés restaient dans le bruit : le trou p90 J8-14 de l'assidu au serveur de 8 valait 15,86 à 80 joueurs et 14,93 à 400, avant réglage) ; **check.sh la garde en alarme rapide** : la même clé, sa limite **du seul côté de queue** élargie de 2 σ20 mesurés (libellé « [alarme rapide −2σ | +2σ, σ = … ; vraie limite : nuit] »), qui ne sort pas par le bruit seul quand la vraie valeur tient (table `TAIL` de la spec, champ `side`) ; l'autre limite d'une clé à deux bornes, à 5 σ20 ou plus de la valeur, reste la vraie dans check.sh (relecture A1, journal A1-39 : les deux côtés étaient élargis, et la borne basse des pertes de l'assidu valait −0,56, impossible à franchir). Les cas de 140 jours (serveur de 16) sont joués sur 400 joueurs eux aussi : leurs clés tardives (trou p90 des jours 85-140, écarts des Ascensions en jours entiers, boucles record par A) sont au bord elles aussi (journal A1-33). Les cas `tails*`, `ref140` et `assidu140` impriment chaque nuit le bruit de chaque clé (lignes `SPREAD`) : une clé qui deviendrait de queue s'y voit. Les 11 clés de queue (mesure du 5 novembre 2026 avec les valeurs de `Balance` du lot A1 3/4 ; σ20 au pire des 3 serveurs, arrondi vers le haut ; valeur sur 400 joueurs au pire serveur) :

| Profil | Clé | σ20 | Sur 400 joueurs | Limite | Alarme rapide (check.sh, côté de queue seulement) |
|---|---|---|---|---|---|
| référence | premier Grand Splorch (min) | 0,69 | 12,16 (serveur de 16) | 11-16 | 9,62-16 |
| référence | plus gros au jour 7 (bimodal : un bloc de 20 à 3,97e7) | 1,2e7 | 8,1e7 | 4e7-4e8 | 1,6e7-4e8 |
| référence | `loopMaxGap` r12 médiane (min) | 0,28 | 2,53 (4 et 16) | ≤ 3 | ≤ 3,56 |
| référence | `loopMaxGap` r13 médiane (min) | 0,47 | 2,80 (8) | ≤ 3 | ≤ 3,94 |
| référence | `loopMaxGap` r13 p90 (min) | 0,41 | 4,93 (4) | ≤ 5 | ≤ 5,82 |
| référence | `ascendGapDays` A6→A7 (jours entiers) | 0,5 | 10 (4 et 16) | 10-16 | 9-16 |
| référence | `tapis12RecordLoopByA` A7 | 0,075 | 0,83 (4) | 0,45-0,95 | 0,45-1,10 |
| référence | `purchasesPerRecordLoopByA` A7 | 0,77 | 11,5 (4) | ≥ 10 | ≥ 8,46 |
| assidu | `longestGapAssiduP90` J8-14 (min) | 1,35 | 14,07 (16) | ≤ 15 | ≤ 17,7 |
| assidu | `longestGapAssiduP90` J15-28 (min) | 1,13 | 13,90 (4) | ≤ 15 | ≤ 17,26 |
| assidu | `coinsLostRatioGrand` J8-14 (T12) | 0,38 | 2,66 (4) | 0,2-3 | 0,2-3,76 |

« **Refuse 3 jours** » : limites du tableau des profils du GDD §4.24.1 (référence ≤ 20 %, assidu ≤ 30 % dans chaque bande ; le GDD est la source du design) ; le trou p90 de l'assidu, dont le GDD ne dit rien pour ce profil, garde la limite de 15 min.

Les sorties du design (`scratchpad/v2/gdd/sim/out/v21/`) servent de référence ; **aucune valeur de `Balance` ne change sans cette porte** ; chaque réglage est écrit au §21.

### 27.10 Plan de tests par paquet (v2.0)

Conventions du §18.1 inchangées (ZeroLog, `Clock.freeze`, jamais un test supprimé ni affaibli ; une attente qui change avec le GDD v2.0 est mise à jour avec lui et sa raison écrite au §27.12). Chaque paquet teste **interrupteur coupé et ouvert**.

| Paquet | Specs (au moins) |
|---|---|
| P0 | `Contract_v2` (fait), `Contract_upgrades` (fait), `Contract_game` (fait : remotes v2.0), `Contract_unlocks` (chaque déblocage du §4.29, chaque objet de Déco perso et cosmétique de la semaine : source, clé EN/FR, case), `Contract_glyphs` (fait : polices dans `assets/fonts/`, table `cmap` lue, exceptions du jeu de base en liste fermée), `Contract_upgrades` › disposition v2.0 (fait), `Contract_unlocks` › personnalités (fait) |
| A1 | `Prestige`, `Props_Prestige` (+ invariant de stabilité ; squishies jamais perdus, Record R, Confettis, A, Atelier jamais en baisse ; `apply` deux fois = une fois), `UpgradeMath`, `Props_UpgradeMath`, `UpgradeAdvisor` (+ « après `Prestige.apply`, `next` ne désigne jamais un niveau déjà possédé ni inexistant »), `Bitset` (200 espèces et 64 objets passent JSON et `reconcile`), `TierRules`, `Static_NoPow`, `Static_PrestigeOnly`, `Formulas` et `Props_Formulas` (N2-N6), `QuestRules` (bascules de semaine et de fin d'année ; chaque période atteint 24 points), `Props_BigNumber`, `EconomyPacing` v2.0 |
| A2 | `EconomyService_upgrades` (somme exacte, un bloc, périmé muet, `BuyTile` = même chemin, Tapis Étoilé par la dalle), `SplorchService_ascend` (`JellyAscend` deux fois dans la même image, pendant un Grand Splorch en file, départ à 3,9 et 4,1 s, fermeture avec 16 joueurs en file), `RanchService_v2`, `RedTeam_Upgrade` (`NaN`, id inconnu, mode 1e9, `expectedLevel` faux, famille verrouillée, achat pendant un prestige), `ProfileRepair_v2`, `DataChaos` (migration), `Soak_queue`, mises à jour de `SplorchService*`, `EconomyService*` |
| A3 | `HelperService` (aucune récompense avant `tPress` ; joueur à moins de 12 studs ; égalité : la pression du joueur gagne ; sieste après 5 min **sans intention acceptée**, un stick calé ne la retarde pas ; pause ; < 0,5 ms par tick), `RedTeam_Helpers` (second compte, immobile 5 min), `Soak` (16 joueurs × 6 aides) |
| A4 | `QuestService_track` (2 points par objectif, 5 par Défi, paliers tout seuls, première période), `CommunityService_v2` (Déco perso, cœurs, halo, photo visible), `EventService_weather` (visuel seulement : aucun effet de jeu), `Analytics_v2` (≤ 10 requêtes par joueur et par minute) |
| B1 | `Static_TextSet`, `Format`, `Format_Widths`, `Text_policy`, `FocusGuard` (découpe), `Upgrades_InputGuard` (partie générique), `TextFit_all` au pire cas (phrases × 1,5), harnais `UIShadow` et dégradé radial (absents → repli) |
| B2 | les 15 specs des règles 1-4, 6, 8, 10-17, 19, 20 ci-dessus ; `HUD`, `Layout_hud`, `Console_hud` mis à jour (N9, N18) ; captures de référence |
| B3 | `Panels_SplorchPreview` (+ « aucun bouton Dépenser d'abord sans ligne gardée payable »), `Panels_Ranch` (*Mon style*, *Dalles* retiré), `Panels_Squishydex` (*Records*), `Panels_Objectives` (piste, Défis, Carnet), `Panels_Settings` (halo), `Cards`, `Banners`, `Console_panels`, `Layout_panels`, `Ascend_InputGuard` (« maintien de l'Ascension prolongé : jamais confirmé ») |
| B4 | `RanchRenderer_v2` (idempotence ; robot qui traverse son ranch sans changement de détail), `BuildCascade`, `VisualBudget` (jamais dépassé sur 6 h de robots), `RanchLook`, `AmbienceRules`, `WorldLayout` et `Props_WorldLayout` (16 ranchs : 6 studs des dalles, rien au-dessus de Y = 21 au centre), `WorldBuild`, `LightingController` ; vérification de la place (N12) |
| B5 | `Personality` (déplacement ≤ 2 studs, cible stable pendant chaque saynète), `HelperRenderer` (atterrissage à `tPress`), `VFXController_v2` (voisin = même état final que le propriétaire ; coupures dures), `CameraController_photo` (1 000 entrées et sorties) |
| I | `Boot` (16 joueurs, interrupteurs ouverts, Ascensions par voyage dans le temps), `Soak` (6 h, Ascensions, Record R jamais en baisse, aucun squishy perdu, Confettis jamais négatifs), `ClientReplay` (3 résolutions × 2 langues, manette seule, écran Améliorations), `TextFit_all` sans clé v2.0 en attente, `Contract_v2` (interrupteurs « ouverts au lancement »), `Contract` (VERSION 2) |

### 27.11 Notes d'intégration v2.0

- **INT-V2-ORDER** (A3, B5 → contrat) : `HelperService` dans `Main.server.luau` après `SplorchService` ; `Controllers.HelperRenderer` dans `Main.client.luau` après `Controllers.ChaseRenderer` ; `Contract_game.spec` (`SERVER_ORDER`, `CLIENT_ORDER`, compte des modules de la surface d'API) dans le même lot.
- **INT-V2-INTENTS** (A2, A4 → contrat) : chaque intention de `Config/IntentsV2` passe dans `Config/Intents` avec son handler ; `Remotes_Meta.spec` (15 → 18 intentions du paquet meta : `PlaceDeco`, `GiveHeart`, `SetPhotoMode`), `Remotes_Ranch.spec` (+ `BuyUpgrade`), `Remotes_Chase.spec` (+ `JellyAscend`) mis à jour dans le même lot ; `Fuzz` les attaque alors automatiquement.
- **INT-V2-SCHEMA** (I) : `SchemaV2 = true` ; `Contract.spec` : `VERSION` 2 (`STORE_NAME` inchangé) ; `ProfileRepair` et `Invariants` v2 déjà verts sur `defaultsFor(2)` ; `Bots.extendSchema` inchangé (il enveloppe `Schema.defaults`).
- **INT-V2-CELEBRATE** (I) : `CelebrateKindV2` fusionné dans `CelebrateKind`, lignes ajoutées à la table du §10.3 (vérifiée par `Contract_game`).
- **INT-V2-BALANCE** (A1) : quand une valeur v1.3 change avec le GDD v2.0 (N2-N6 : `Offline.StopAt` remplacé par `OfflineV2.MinPlaySeconds`, `Press` et série), `GddValues` passe à `"2.0"` avec la porte v2.0 verte et les témoins de `Contract_game` mis à jour.
- **INT-V2-TEXT** (B1-B5) : chaque paquet retire de `TextFitKeysPending` les clés v2.0 que ses scénarios prouvent ; jamais une clé ajoutée pour masquer un texte qui ne tient pas.
- **INT-V2-LIGHT** (B4) : `default.project.json` (`LightingStyle = Soft`, `PrioritizeLightingQuality = false`) et `scripts/verify-place.luau` dans le lot de B4, derrière `Ambience` côté client.
- **INT-V2-GLYPHS** (B1, B2, B3, A1 → contrat) : `Contract_glyphs` garde une liste **fermée** de 22 clés du jeu de base hors police, qui ne fait que rétrécir. (a) **B1** : quand `UI/Theme` passe le texte courant de GothamBold à FredokaOne (GDD §10.1 v2.0), le contrat remplace dans le même lot l'espace insécable U+00A0 (absente de FredokaOne) par une espace ordinaire dans les 13 clés listées (`common.oneIn`, `celebrate.flop`…), et B1 reprouve `TextFit_all` ; « ★ » de `common.stars` et `celebrate.star` devient une étoile dessinée (`Glyph`). (b) **B2** : « ♥ » de `hud.twins`, « ≈ » de `hud.queue.next` / `hud.queue.place` deviennent des icônes dessinées (ou le mot « environ »). (c) **B3** : `panel.dex.starBadge` (★), `panel.ranch.twins` (♥), `settings.emoteLeft` (← : glyphe de la croix dessiné), `panel.shop.coinsAmount` (≈). (d) **Formateurs** (même règle, liste fermée `FORMATTER_EXCEPTIONS`) : `Logic/BigNumber` écrit U+202F (espace fine insécable, absente des **deux** polices) dans chaque montant français (« 12,3 K », « 1 234 ») ; `Util/Format` écrit U+00A0 (absente de FredokaOne) dans les durées et montants français ; les deux écrivent « ∞ » pour ±inf (valeur hostile seulement). **B1**, quand le texte courant passe à FredokaOne : `UI/Format` (nouveau) écrit une espace ordinaire U+0020 à la place (ou une espace dessinée à la largeur de la police), et demande à **A1** le même changement dans `BigNumber` (`Props_BigNumber` et `Format` mis à jour dans le même lot, GDD §4.2 cité au journal) ; « ∞ » devient « 0 » ou le plafond affiché. Chaque retrait enlève la ligne de `BASE_EXCEPTIONS` ou le caractère de `FORMATTER_EXCEPTIONS` (la spec échoue sur une exception périmée). Les noms des joueurs (bannières, cartes) ne sont pas des clés : le repli de police du moteur les dessine.

### 27.12 Définition de « fini » v2.0 et journal

**Un paquet v2.0 est fini quand** : ses fichiers suivent l'API du §27.7 (sans marque `TODO(`) ; ses specs (§27.10) sont vertes **interrupteur coupé et ouvert** ; la spec de chaque règle d'affichage qui le concerne (§27.8) est verte à 720p, 1080p et 4K, EN et FR ; la porte `EconomyPacing` v2.0 est verte (A1, puis à chaque lot qui touche l'économie) ; `selene src` 0 / 0, StyLua ; la suite complète et `./scripts/check.sh` ont été lancés et leur résultat rapporté honnêtement ; ses besoins hors de ses fichiers sont des notes d'intégration ; une relecture indépendante a eu lieu **avant** l'ouverture de son interrupteur. **Le jeu complet est fini** quand tous les interrupteurs sont ouverts, `SchemaV2` aussi, `TextFit_all` n'a plus aucune clé v2.0 en attente, `Boot`, `Soak` (6 h) et `ClientReplay` sont verts, et les tests manuels sur PS5 (dont les photos du panneau TextProbe) sont faits. Aucune date fixée (décision par défaut n° 6) : rien ne sort avant.

**Journal du contrat v2.0 (3 novembre 2026)** — décisions et écarts avec `contract-changes.md`, chacune testée :

- **C1. Interrupteurs coupés par défaut** (consigne du propriétaire « le jeu de base joue exactement comme avant ») au lieu des valeurs `true` du `contract-changes.md` §2.3 : la valeur de lancement est écrite au §27.3 et posée à l'étape I. `Contract_v2` › « chaque système v2.0 a son interrupteur, COUPÉ par défaut ».
- **C2. Habillages = `cosmetics.theme`** : le champ `ranchSkin` et l'intention `SetRanchSkin` de `contract-changes.md` dupliquaient le thème de la v1.3 (3 des 14 habillages en sont déjà) ; une seule source, l'intention existante `EquipCosmetic("theme", id)`. `Contract_v2` › « … habillages : aucune intention à part ».
- **C3. Aucun stub de module** (`Fix_validation.spec` interdit `TODO(` dans `src/`) : API exactes au §27.7.
- **C4. Catalogue `Config/IntentsV2` à part** : mettre les intentions dans `Config/Intents` sans handler aurait cassé `Remotes_Meta` (compte et débit mesuré sur un handler), `Fuzz` et la règle « un remote écouté par son propriétaire ». Passage par INT-V2-INTENTS.
- **C5. Tables v2.0 de `Balance` à part** : `Balance.Tiles` est parcouru par `EconomyService.applySplorch` et `Balance.Caps` par `Invariants` et `ProfileRepair` ; y mettre `star`, `gloves`, `fameSplorch`… aurait changé le jeu de base. `Contract_upgrades` › « jamais une clé v2.0 dans les tables parcourues par le code de base ».
- **C6. Schéma v2 derrière l'interrupteur figé `SchemaV2`** et `migrate(data, from, to?)` : écrire des profils v2 avant que les systèmes v2.0 tournent ferait perdre les Confettis des Record R atteints entre la migration et l'ouverture, et rendrait la version de test incapable de lire les profils (refus « pas à jour »).
- **C7. Constantes de migration figées** (`Schema.MIGRATION_V2`) plutôt que lues dans `Balance` (qu'A1 peut régler).
- **C8. `weeklyTrack.firstPeriodEnd = 0` à la migration**, fixé par QuestService au premier chargement : la migration reste pure (aucune horloge).
- **C9. `onboarding.welcomeV2Pending`** (vrai si R ≥ 1 à la migration) porte la carte « Bienvenue dans la v2 ! » ; un nouveau joueur ne la voit jamais.
- **C10. Clés de texte sous `upgrades.*`** (`upgrades.family.*`, `upgrades.state.*`, `upgrades.effect.*`, `upgrades.detail.*`, `upgrades.tier.*`) au lieu de `family.*`, `state.*`… : `family.*` est déjà le domaine des familles d'espèces. Titres v2.0 sous `title.*`, cosmétiques v2.0 sous `v2cosmetic.*`, bannières sous `ascend.banner` / `monument.banner` : hors des familles de `TextFitKeys` (sinon « prouvées » par leurs sœurs avant d'être montrées). Les libellés d'effet n'ont **ni flèche ni `{glyph}`** (règle 18 : icônes dessinées) ; « − » des montants écrit « - ».
- **C11. `CelebrateKindV2` à part** jusqu'à l'étape I (la table du §10.3 et l'union `CelebrateKind` sont vérifiées l'une contre l'autre par `Contract_game`).
- **C12. `HelperPressPayload = { ownerId, presses }`** : le client qui dessine plusieurs ranchs sait à quel ranch appartient chaque paquet.
- **C13. Prix au moins 1 pièce** (`max(1, floor(…))`) : à r = 0 après plusieurs Ascensions, `floor` donnerait 0 (achat gratuit, coûts non croissants) ; `Contract_upgrades` vérifie la croissance stricte pour chaque A dès son Grand Splorch de départ.
- **C14. La migration normalise `tiles.pens`** (entier 0-14) : une sauvegarde abîmée ne garde jamais un niveau hors bornes.

- **C15. Clés de texte de l'écran à venir sans ligne en attente** : l'outil d'écrans accepte une clé que le client ne référence pas encore ; `settings.haloOn` (préfixe construit par le panneau Réglages) arrive donc avec A4, pas avant.
- **C17. `season` passe à QuestService en v2** (champ réservé de la v1 : seul `season.frostDays` est écrit ; `id`, `xp`, `premium`, `claimed` restent neutres, jamais effacés).
- **C18. Sons v2.0 : 4 s au plus comme tout effet** (`Fix_r5_audio` › garde-fous) : le son de charge de l'Ascension boucle ou se relance pendant le maintien de 3 s, jamais une copie de plus de 4 s.
- **C16. Contenu v2.0 à part des listes parcourues par le jeu de base** (`Cosmetics.ListV2` à côté de `Cosmetics.List`, `Visuals.RecordTable` à côté de `Balance.Splorch.Unlocks` que lit l'aperçu de la v1.3) : fusion à l'étape I, mêmes identifiants.

- **C19. Polices de test** : FredokaOne (SIL OFL 1.1) et LuckiestGuy, **sous Apache License 2.0** et non OFL comme l'écrivent le GDD §10.1 et la critique m22 (Google Fonts la range dans `apache/luckiestguy` ; la table `name` du fichier le dit aussi) : licence aussi libre pour un fichier de test, gardée à côté du fichier. `raw.githubusercontent.com` répond 404 dans ce conteneur ; les fichiers viennent de `fonts.gstatic.com` (API CSS de Google Fonts, format TrueType), les textes de licence des paquets npm `@fontsource/fredoka-one` et `@fontsource/luckiest-guy` 5.3.0. Rangées dans `assets/fonts/`, **jamais** dans la place (Rojo ne range que `src/` : `Contract_glyphs` › « jamais livrées »). Le jeu utilise les polices intégrées de Roblox (`Enum.Font`), aucune police n'est téléversée.
- **C20. Règle 18 sur les deux polices** : une clé peut être posée en FredokaOne (texte) ou en LuckiestGuy (tampons, titres des bannières et des cartes, puce d'action spéciale) ; `Contract_glyphs` exige donc chaque caractère (variables `{x}` exclues) dans les **deux** tables `cmap`. Écarts trouvés dans le jeu de base : « ★ » (3 clés), « ♥ » (2), « ≈ » (3), « ← » (1), absents des deux polices ; U+00A0 (13 clés), absente de FredokaOne seulement. Ces clés sont dessinées aujourd'hui en GothamBold (`Theme.Body`) ou avec le repli de police du moteur : elles restent telles quelles (le jeu de base ne change pas) dans une liste fermée, retirées par INT-V2-GLYPHS. Aucune clé v2.0 n'a d'exception (435 clés vérifiées). Les **formateurs** sont vérifiés aussi (EN et FR, de 0 à 1e300, valeurs hostiles comprises) : U+202F (`BigNumber`, absente des deux polices), U+00A0 (`Util/Format`, absente de FredokaOne) et « ∞ » sont la seule liste fermée `FORMATTER_EXCEPTIONS`, retirée par INT-V2-GLYPHS (d).
- **C21. Panneau TextProbe au paquet B1** (et non « tâche n° 1 de P0 » comme au §10 de `contract-changes.md`) : le panneau Diagnostics est un fichier du client (`src/client/UI/Panels/Diagnostics.luau`), pris par la relecture de l'interface en cours ; B1 le livre en premier (avant `UI/Text`), et les photos de la PS5 sont une condition de fin de B1 (§27.12).
- **C22. Personnalités sans texte** : le GDD §5.6 ne montre pas le nom des personnalités à l'écran (les saynètes sont dessinées) ; aucune clé `perso.*` n'est ajoutée (elle entrerait dans `TextFit_all` sans écran). Une clé viendra avec l'écran qui l'affiche, s'il existe un jour.
- **C23. Propriétaires oubliés** : `DiagnosticsService` (compteurs et panneau TextProbe côté serveur, §27.14) va à A4 (propriétaire v1.3 : meta) ; `Server/Util/Activity` (module du contrat, N23) à A3 pour le seul ajout `lastIntent`.
- **C24. Sauvegarde-témoin `v2.json`** (`contract-changes.md` §1.2, point 6) : créée depuis `v1.json` par la migration du dépôt (aucune valeur écrite à la main) et comparée valeur par valeur, pas en bloc : un champ v2 ajouté plus tard au schéma (contrat) ne casse pas le témoin, une valeur de migration changée le casse (mutation faite : `confetti` 139 → 138 fait échouer le cas).

**Journal du lot A1, étape 1 (3 novembre 2026)** — lectures du §27.7 alignées sur le GDD et la simulation du design (détail : `scratchpad/v2/a1-decisions.md`) :

- **A1-1. Prix** : `max(1, floor((base × g^L) × RScale^r × F(A)))`, chaque facteur en table construite au chargement par multiplications successives ; égal à chaque témoin de `Contract_upgrades` et à chaque valeur du GDD §4.6 (`UpgradeMath.spec`) ; le module est le seul calcul (client = serveur).
- **A1-2. Monuments** : base = T12 avant `floor` (comme le Tapis Étoilé et la simulation), × RScale^(r − bestR) par divisions successives, jamais F(A) ; le GDD les écrit arrondis, les autres tables tronquées.
- **A1-3. `Prestige.apply` idempotent par construction** : appliqué seulement si le prestige est possible (plus gros squishy, tous lieux compris, ≥ objectif(r) ; `ascendReady`) ; après lui la condition est fausse, aucun champ marqueur.
- **A1-4. `apply` rend `(changed, report)`** : `changed` = ensemble des clés pour `markDirty` ; Confettis (prestige, retour +10, enclos plein +25), Fame et niveaux du cadeau sont RENDUS et versés par l'appelant dans le même bloc (`EconomyService.addConfetti` reste le seul point d'entrée, GDD §4.26 m2).
- **A1-5. Sorte effective** : un « splorch » qui ne bat pas le record paie comme un Petit Splorch et inversement ; la file se choisit par `Prestige.nextKind`.
- **A1-6. Décorations gardées** au Record R d'avant le prestige (comme la simulation), aussi à l'Ascension ; **A1-7. cadeau du Splorch** aussi pour la boucle qui suit une Ascension (simulation).
- **A1-8. Tremplin** : sautés payés = `StartR(A, Tremplin) − StartR(A, 0)` (GDD) ; la simulation paie `min(StartR, Tremplin)`, différent seulement pour A ≥ 42 environ.
- **A1-9. Note INT-A1-MEMORY** : la 1re boucle record (×1,25) ne se distingue pas des suivantes avec les champs du schéma v2 ; champ `memoryR` (0-400, SplorchService via `Prestige.apply`) proposé au contrat ; en attendant `Prestige.firstRecordLoop` rend faux.
- **A1-10. Note INT-A1-BALANCE** : « ReqR[A+1] − 10 », « +3 décorations par niveau », 0,95 et × 2,5 dès r = 16 sont des constantes de `Prestige` faute de clé dans `Config/Balance` (structure au contrat) ; 5 clés proposées.
- **A1-11. Plancher de StartR** par `math.log` (pas une puissance), une fois au chargement ; à plus de 0,0138 d'un entier pour A = 1 … 60 (même valeur partout).
- **A1-12. Objectifs** : table propre de `Prestige` (égale à `Formulas.splorchTarget` de r = 0 à 400), pour que `Formulas` puisse lire `Prestige` sans cycle ; note **INT-A1-TILECOST** : `Formulas.tileCost` diffère d'une pièce dans un seul cas sous 1e15 (décoration 10 à r = 17) : `BuyTile`, dalles et aperçu passent par `UpgradeMath` quand `UpgradesScreen` s'ouvre (A2, B4).

**Journal du lot A1, étape 2 (3 novembre 2026)** — formules v2.0 (N2-N6), `QuestRules`, `BigNumber`, `Invariants` (détail : `scratchpad/v2/a1-decisions.md`) :

- **A1-13. Interrupteurs dans `Formulas`** : chaque terme v2.0 lit son interrupteur à chaque appel (`Features.get`) ET un champ facultatif du contexte (`A`, `bestR`, `firstRecordLoop`, `star`, `monuments`, `gloves`, `superStreak`, `nightBag`, `nightPot`, `gMax`) ; coupé ou champ absent = mêmes opérations dans le même ordre qu'en v1.3 (`Props_Formulas` › « v2.0 coupé », 5 000 cas bit à bit). N2 [JellyAscend, StarMat], N3 [UpgradesScreen ou JellyAscend], N4 [Monuments], N5 [Gloves, Workshop], N6 [Workshop ; arrêt à 120 s : RecordR].
- **A1-14. INT-A1-TILECOST réglée dans `Formulas`** : dès que `UpgradesScreen` ou `JellyAscend` est ouvert, `tileCost(tile, L, r, A?)` rend `UpgradeMath.price` (× F(A) avec `JellyAscend`) : dalle, étiquette, écran et débit montrent le même nombre sans que A2 ni B4 changent d'appel (ils passent seulement A en 4e argument).
- **A1-15. Tapis Étoilé dans la croissance** : compté seulement au-dessus du Tapis 12 et jamais au-delà de `Prestige.starCap(r)` (un profil abîmé ne grandit pas plus vite que la boucle) ; `Formulas.maxGrowthRate(ctx)` (Tapis 12 + plafond de r, boost ×2) donne le `gMax` de `offlineGrowth`.
- **A1-16. Pression : un seul `floor`** (GDD §4.3) : `floor(base × PERFECT × série(≤ 5 + Super Série) × Kitty × Gants)` ; la simulation du design arrondit avant les Gants et la Super Série (écart < 4 pièces, `Props_Formulas`) : le GDD fait foi.
- **A1-17. Arrêt hors ligne à 120 s** : `min(90 % − plus gros, objectif − 120 × gMax − plus gros)` ; une boucle qui dure en tout moins de 120 s à la croissance maximale ne grandit pas du tout hors ligne (elle se fait en jeu).
- **A1-18. `BigNumber` (GDD v2.0 §4.2, INT-V2-GLYPHS d)** : 31 suffixes (K … Tg, 1e93), notation e dès 1e96 ; aucune des deux polices n'a d'espace insécable (seule U+0020, où un libellé à retours à la ligne, défaut de `UI/Text`, peut couper) : en français le suffixe est **collé** (« 12,3K », « 4,56B ») et 4 chiffres s'écrivent sans séparateur (« 9876 », espace facultative en français), U+0020 au-delà dans `full` et `words` (fiche, libellé sans retour à la ligne) ; ±inf → plafond affiché « 1.00e300 » (« ∞ » absent des deux polices). Attentes changées : `BigNumber.spec` (1e36 « 1.00e36 » → « 1.00Ud » ; exemples FR sans U+202F ; ±inf « ∞ » → « 1.00e300 » ; mot d'un palier sans clé → forme courte), `Props_BigNumber` (suffixes, sans U+202F) ; `Contract_glyphs` : U+202F et « ∞ » retirés de `FORMATTER_EXCEPTIONS.BigNumber`. Note **INT-A1-WORDS** (contrat) : clés `num.name.36` … `num.name.93` (EN, FR, table du GDD §4.2) et leurs lignes de `TextFitKeysPending` ; en attendant, `words` rend la forme courte (jamais un mot vide).
- **A1-19. `QuestRules` (GDD §7.5)** : `weekIndex`, `weekStart`, `trackPeriod` (1re période jusqu'au 2e lundi, numéro = dernière semaine couverte ; fin abîmée ou à plus de 2 semaines = 1re période finie, jamais de recul), `trackTier`, `trackMaxPoints` (borne basse : jours UTC entiers × 6 + 15 ; 27 au joueur du week-end), `challengeFeasible` (temps de jeu borné à 30 min … 2 h ; Défis de situation — 2 Grands Splorch, record, Ascension, MEGA — seulement avec une estimation de l'appelant ; Ascension seulement avec `JellyAscend`), `drawChallenges` (3 distincts, déterministes), `carnetTier`, `carnetNext`. 30 min et 2 h sont des constantes locales (ajout à INT-A1-BALANCE).
- **A1-20. `Invariants` v2** (version ≥ 2 seulement ; un profil v1 garde exactement les invariants de la v1.3) : bornes du §27.2, `R ≤ bestR ≤ MaxR`, `regainBonusA ≤ A`, `confetti ≤ confettiTotal ≤ 1e9`, Tapis Étoilé après le Tapis 12 et ≤ plafond de r, chaque niveau ≤ `UpgradeMath.cap` (tous interrupteurs ouverts), ensembles de bits, piste, Déco perso (objet possédé, jamais deux fois), cœurs ; `Invariants.afterPrestige` (toutes les tailles à 1, décorations ≤ `keptDecor` ≤ 12, Tapis Étoilé, Gants, École à 0). Les témoins `v1.json` / `v2.json` n'ont pas `b` (posé par `ProfileRepair`).

**Journal du lot A1, étape 3 (3 novembre 2026)** — porte d'économie v2.0 (`tests/sim/EconomyModel.luau`, `tests/specs/EconomyPacing.spec.luau`, `scripts/economy-nightly.sh` ; détail : `scratchpad/v2/a1-decisions.md`, décisions 32-38) :

- **A1-21. Les interrupteurs décident, comme dans le jeu** : `EconomyModel` lit `Config/Features` ; les 12 interrupteurs de l'économie (`EconomyModel.ECON_FLAGS`) tous coupés = la v1.3 exacte (chaque métrique égale bit à bit à celle du modèle de 533e02e : serveurs de 4 et 16, avec et sans gros acheteur, 28 jours), tous ouverts = la v2.0, un mélange est refusé. Le jeu les garde coupés ; seule la spec les ouvre, le temps des simulations v2.0 (`Features.reset` ensuite).
- **A1-22. Le vrai code, aucune formule ni valeur copiée** : chaque renaissance par `Prestige.apply` (gains versés comme l'appelant : `Confetti.Max`, Fame du Grand Splorch sous `CapsV2.fameSplorch`, Ascension hors plafond, cadeau `UpgradeMath.giftCoins`), prix `Formulas.tileCost(…, A)` et `UpgradeMath.price`, plafonds `UpgradeMath.cap`, Conseillé `UpgradeAdvisor.next(UpgradeMath.snapshot(…))`, croissance, pression, hors ligne, Monuments par `Formulas` avec leurs champs v2.0, piste par `QuestRules.trackPeriod` et `Config/Quests.WeeklyTrack`, Plopettes par `Balance.Helpers` ; `MaxR` / `MaxA` appliqués par `Prestige`. Valeurs propres au modèle : comportement seulement (règle des 12 studs 0,75, assidu 120 min, séances, jours joués). Le modèle porte le champ `memoryR` proposé (INT-A1-MEMORY) pour le × 1,25 de la 1re boucle record.
- **A1-23. Écarts voulus avec la simulation du design** (le vrai code et le GDD font foi) : un seul floor par pression (A1-16) ; Petit Splorch sans Fame (le design : + 5) ; Atelier acheté après `Prestige.apply` (Tapis de départ, cadeau, décorations gardées valent à la boucle suivante, comme en jeu) ; piste réelle du GDD §7.5 (2 points par objectif réclamé, 5 par Défi — un par séance, 3 par période —, paliers payés dès qu'atteints, 1re période jusqu'au 2e lundi ; le design : 34 Confettis le 7e jour) ; Conseillé réel (Enclos et Lit compris). Sur les mêmes graines, design et dépôt rendent les mêmes boucles avant la 1re Ascension, et la référence de 140 jours retrouve les sorties `out/v21` (Record R 40 et A = 7 au jour 84, lignes de l'Atelier au jour 106, Monuments 2 / 8 aux jours 7 / 28, `spenderLeadTimeShare` 15 à 21 %).
- **A1-24. Les clés du §27.9** (définitions de la simulation du design) : un test par groupe et par configuration, chaque clé imprimée (valeur, limites, OK / HORS) ; jalons v1.3 sur la v2.0 au Record R (jours 7, 14, 28) et santé sur les Grands Splorch des jours 1-14 ; `ascendGapDays` par k tant que la moitié des joueurs ont fait la k-ième ; `tapis12RecordLoopByA`, `purchasesPerRecordLoopByA` pour chaque A d'au moins 3 boucles record ; `confettiUnspent` = pire médiane de fin de journée (jours 1-84) ; `monumentsDay7` pour la référence ; bornes en plus : Record R et Confettis gagnés jamais en baisse, Confettis ≥ 0, `Prestige.apply` jamais refusé. `recordRDay28` contre la référence sans Ascension (28 jours, serveur de 16) dans check.sh ; `spenderLeadTimeShare`, `atelierEffect`, profils forcés, 140 jours : la nuit (`ECON_NIGHT=<cas>`, `ECON_NIGHT=custom` pour un lancement manuel à 200 joueurs). La porte v1.3 du jeu de base reste à part, telle quelle (50 joueurs × 3 tailles, gros acheteur) : verte ; cas ajoutés : un joueur témoin, interrupteurs coupés, rend au bit près les jalons du modèle de 533e02e (une dérive du jeu de base dans le modèle échoue avant de déplacer une médiane : mutation vérifiée), et un joueur assidu, interrupteurs ouverts, fait chaque Jelly Ascend à r ≥ `Prestige.reqR(A)` et repart à `Prestige.startR(A, Tremplin)`.
- **A1-25. Résultat (forme check.sh, 20 joueurs)** : 51 réussis, **2 échoués** : `loopMaxGap` r13 de la référence au serveur de 16 = 3,075 min (≤ 3) et `coinsLostRatioGrand` J8-14 de l'assidu au serveur de 4 = 3,55 T12 (≤ 3). Pas un défaut du modèle : la simulation du design, jouée sur les mêmes 20 graines, donne 3,0 et 3,07. Marge d'équilibrage trop faible pour 20 joueurs : à 80 joueurs les deux tiennent (2,87 min, 2,50 T12), mais sur 4 jeux de 20 graines r13 va de 2,30 à 3,32, les pertes de 2,03 à 3,61 et le trou p90 de l'assidu de 11,9 à 15,8 min. **Aucune valeur de `Balance` changée** (§21 : essais écartés), **aucune limite assouplie** ; décision demandée au design et au contrat (`scratchpad/v2/notes-croisees.md`).
- **A1-26. Coût** : EconomyPacing 5 min 52 s mesurées (porte v1.3 ≈ 80 s, v2.0 ≈ 260 s), au lieu des ≈ 3,5 min du contrat (mesure du design pour la seule v2.0) ; optimisations sans changer un résultat (prix et plafonds gardés par famille, cibles des Plopettes prises dans le balayage de la pression).
- **A1-27. Jeu de nuit** (`scripts/economy-nightly.sh`, 15 cas, 3 à la fois : 26 min, 65 min de calcul) : **8 verts** (gros acheteur 200 joueurs : `spenderLeadTimeShare` 15 à 21 % de A1 à A7 ; 6 h par jour ; jamais l'Atelier, avec `atelierEffect` rapporté : l'Atelier retire 1,6 à 1,8 point de temps « sans but » aux jours 8-28 et 57-84 ; week-end 140 jours ; 20 min par jour ; profils forcés A = 10, 20, 30, 60) et **7 rouges** : `ascendGapDays` des Ascensions tardives (référence 140 jours : A11→A12 9,5 et A12→A13 9 jours, limite 10 ; assidu 140 jours : 3 jours de A22 à A36, limite 4 — les sorties du design montrent la même accélération : A10 au jour 109, A13 au 137, A20 au 92 puis A34,5 au 140) ; « Conseillé », assidu 20 joueurs : trou p90 J8-14 15,7 min ; « refuse 3 jours », assidu : J2-7 15,8 % (limite de son profil 15 % ; le tableau des profils du GDD §4.24.1 écrit « assidu ≤ 30 % dans chaque bande » et le design mesurait 16,0 % : contradiction à trancher) ; 10 min par jour : `offlinePotShare` 2,10 (≤ 2) ; Atelier complet dès le début, assidu : pertes J8-14 3,31 T12. Le reste tient et retrouve le design (assidu 140 jours : « sans but » 10,4 / 15,5 / 15,9 / 16,5 / 14,8 / 12,4 %, Record R 84,5 au jour 84, lignes de l'Atelier au jour 54, Confettis en poche 263 au pire jusqu'au jour 84).

**Journal du lot A1, étape 3, fin (5 novembre 2026)** — porte d'économie v2.0 verte (décisions du chef : (a) jamais une limite assouplie, (b) clés de queue la nuit sur assez de joueurs et alarme rapide dans check.sh, (c) le GDD fait foi contre le §27.9, (d) vrais problèmes réglés dans `Balance`, (e) check.sh plus rapide) ; mesures : `scratchpad/v2/a1-etape3-resultats.md` :

- **A1-28. La règle du bruit d'échantillon** (§27.9 « Clés de queue ») : σ20 MESURÉ (`ECON_NIGHT=spread`, 400 joueurs = 20 blocs disjoints de 20, aux 3 tailles de serveur) ; une clé dont la marge (valeur sur 400 joueurs → limite) est < 2 σ20 est « de queue » : 11 clés (référence : premier Grand Splorch, plus gros au jour 7 (bimodal), `loopMaxGap` r12 médiane, r13 médiane et p90, `ascendGapDays` A6→A7, `tapis12RecordLoopByA` et `purchasesPerRecordLoopByA` A7 ; assidu : `longestGapAssiduP90` J8-14 et J15-28, `coinsLostRatioGrand` J8-14) ; marges de 0 à 1,97 σ20. Vraie limite affirmée la nuit **sur 400 joueurs** et non 80 : à 80 joueurs (σ80 ≈ σ20 / 2), 6 des 11 restaient sous 2 σ80, plus la clé bimodale (dont le trou p90 J8-14 de l'assidu au serveur de 8 : 15,86 à 80 joueurs pour 14,93 à 400, avant réglage). check.sh : alarme rapide à la limite élargie de 2 σ20 (table `TAIL` de la spec, libellé marqué) ; toutes les autres clés y bloquent à leur vraie limite (marge ≥ 2 σ20 mesurée). Nouveaux cas de nuit `tailsRef4/8/16`, `tailsAssidu4/8/16` (les configurations de check.sh, mêmes graines, bruit imprimé) ; `ref140` et `assidu140` passent à 400 joueurs (`assidu140` tient lieu de `tailsAssidu16` : mêmes graines, mêmes 28 premiers jours, et ses clés de queue sont des clés de bandes de jours).
- **A1-29. Nuit à 80 joueurs au moins** (`ECON_NIGHT_PLAYERS` 50 → 80) ; les sous-cas assidu joués à 20 joueurs (sans Atelier, refuse 3 jours, Conseillé, Atelier complet) passent à 80 ; les profils forcés restent à 20 joueurs (ils n'affirment que les bornes et la santé des renaissances, aucune clé de queue). `scripts/economy-nightly.sh` : 20 cas, 4 à la fois, les plus longs d'abord.
- **A1-30. « Refuse 3 jours » : limites du GDD** (§4.24.1, tableau des profils : référence ≤ 20 %, assidu ≤ 30 % dans chaque bande) au lieu de celles du profil de base (le §27.9 « limites de son profil » était lu comme 5 % / 15 % aux jours 2-7) ; le trou p90 de l'assidu, dont le GDD ne dit rien pour ce profil, garde la limite de 15 min du §27.9. Résultat à 80 joueurs : vert (assidu J2-7 : 16,0 %, comme le design ; la lecture « 15 % » l'aurait fait échouer).
- **A1-31. Vrai problème n° 1, `offlinePotShare` du joueur de 10 min par jour** : 2,092 à 80 joueurs (≤ 2 ; le bruit de cette médiane sur ≈ 6 700 nuits est de l'ordre de 0,01 : pas du bruit) ; le Pot de nuit de l'Atelier passe de + 5 % à + 3 % par niveau (`Balance.OfflineV2.NightPotShares`, §21) : 1,873. Effet mesuré au passage : le trou p90 J8-14 de l'assidu (le seul rouge à 80 joueurs des clés de check.sh, 15,86 au serveur de 8) descend à 14,05-14,07 sur 400 joueurs aux 3 tailles (14,27-14,93 avant) : l'aubaine du Pot au début de la séance faisait tout acheter d'un coup, puis attendre. Attentes changées : `Formulas.spec` (`offlinePot(2, 100, 1 / 2 / 7)` = 56 / 62 / 62 au lieu de 60 / 70 / 70), `UpgradeMath.spec` (effet du Pot de nuit 25 % → 28 %), `Props_Formulas` (référence de la simulation du design : + 3 % par niveau au lieu de + 5 %, même formule).
- **A1-32. Vrai problème n° 2, les Ascensions tardives** : le GDD (§4.27, « une Ascension tous les 10 à 11 jours (référence, jusqu'au jour 140) et tous les 4 à 5 jours (assidu) », clé `ascendGapDays` 10-16 / 4-8) parle de chaque Ascension ; la nuit mesurait 9,5 et 9 jours (référence, A11→A13) et 3 jours (assidu, A22→A36). Cause : avec + 4 Grands Splorch par Ascension, (2,6 / 2)^4 = 2,86 < × 3 (l'invariant n'exige que 0,95 × 3) : la boucle record raccourcit de ≈ 3 % par Ascension, et la remontée perd un Petit Splorch toutes les 5 Ascensions (plancher de pente 4,19). Réglage (§21) : `Balance.Ascend.ReqR` devient une liste de 60 conditions, + 5 au lieu de + 4 une fois toutes les 8 Ascensions à partir de la 11e (pas moyen 4,125 ≈ ln 3 / ln 1,305 : la difficulté de la dernière boucle record reste entre 0,73 et 1 fois celle de A1 jusqu'à A60, au lieu de tomber à 0,13) ; `Balance.Ascend.PriceByA` devient une liste de 60 facteurs (0,31 dès A11, 0,29 aux Ascensions qui demandent un Grand Splorch de plus) : sans lui, le Tapis Étoilé n'était presque plus acheté dans les boucles record tardives (achats de la ligne Tapis 10,4, limite 10). Tout ce qui précède A11 est inchangé (check.sh n'en voit rien). Écartés (mesurés, 80 à 160 joueurs) : un Grand Splorch de plus toutes les 10, 11 ou 12 Ascensions (écarts de 4 jours à la limite, trou p90 J85-140 15,1-15,2), dès la 7e (Tapis 12 des boucles record A7 0,98 au serveur de 8), facteurs 0,25 à 0,30 aux Ascensions du Grand Splorch de plus (une boucle de moins de 45 s loin d'une fusion à 0,25). Attentes changées : `Prestige.spec` (`reqR(61)` 256 → 263 ; départ à MaxA 246 → 247 ; la 60e Ascension part de 250 avec le Tremplin 3, qui compte encore sous la condition suivante − 10 = 253), propriété de stabilité de `Props_Prestige` (« jamais plus dure » d'une Ascension à l'autre → au plus × 1,35, et en plus une dérive cumulée bornée à 0,7-1,05 fois la 1re : plus stricte sur 60 Ascensions, les anciennes valeurs y échouent). Témoins de `Contract_upgrades` tenus (conditions 1 à 4, départs A1 à A10, facteurs de prix 1 à 6). Texte du GDD à mettre à jour (§4.27 « puis + 4 », Atelier « 25 % → 30 % → 35 % ») : note au design (`scratchpad/v2/notes-croisees.md`).
- **A1-33. Restées au bord après réglage** (vertes, < 2 σ400 de marge ; à surveiller à chaque lot qui touche l'économie) : référence `loopMaxGap` r13 p90 4,93 / 4,90 (serveurs de 4 et 8, limite 5) et `ascendGapDays` A6→A7 = 10 (limite 10, jours entiers ; le design mesurait « 10 à 11 jours ») ; référence, jours 70 à 110 : `ascendGapDays` A7→A8, A8→A9 et A9→A10 = 10 (`ref140`, 400 joueurs ; avant le Grand Splorch de plus de la 11e, comme le design) ; et, avec 2,4 σ400 de marge, le trou p90 J85-140 de l'assidu 14,66 (limite 15 ; 12,8 avant le réglage des Ascensions, dont les boucles record tardives sont redevenues longues). Levier mesuré et non pris (pas un vrai problème, valeur du GDD) : Gants 0,025 → 0,03 par niveau (r13 p90 − 0,2 à − 0,25 min à 80 joueurs).
- **A1-34. check.sh plus rapide, rien de perdu** : les 11 configurations des deux portes (v1.3 : 3 tailles et le gros acheteur ; v2.0 : 6 configurations et la référence sans Ascension) sont jouées par 4 processus fils à la fois (`tests/sim/economy-worker.luau`, `tests/sim/EconomyIO.luau` : mêmes modules, mêmes graines ; joueurs écrits en JSON sans perte — entiers exacts, autres nombres en 17 chiffres, ±inf, NaN, tableaux à trous) ; deux cas le prouvent : « chaque configuration a rendu ses joueurs (fils sans erreur ni trace) » (un fils sort en échec à la moindre trace du harnais) et « un fils rend les mêmes joueurs que le calcul en place » (égalité au bit près) ; le joueur témoin v1.3 est pris dans les résultats de la porte au lieu d'être rejoué (`Sim.aggregate` : les médianes de `Sim.run` sur des joueurs déjà joués). Mesure (machine de 4 cœurs, rien d'autre en cours) : 56 s au lieu de 5 min 52 s (3 min 21 s de calcul) ; `ECON_WORKERS=1` (tout dans un seul processus) : 3 min 20 s, les mêmes lignes de clés au chiffre près (les 5 min 52 s d'avant étaient mesurées pendant qu'une autre voie tournait sur la même machine).
- **A1-35. Outils de mesure gardés** : `ECON_NIGHT=spread` (bruit d'une configuration, lignes `SPREAD` lisibles par un script : valeur sur tous, moyenne, σ, étendue des blocs, marge en σ, valeurs des 20 et 80 premiers joueurs) ; option `keepLog` de `EconomyModel` (sondes : journal brut avec prix, r et pièces de chaque achat ; jamais posée par la porte).
- **A1-36. Résultat** : forme check.sh d'EconomyPacing **55 réussis, 0 échoué** (56 s) ; jeu de nuit (20 cas, 4 à la fois, 47 min 31 s) **19 cas verts, 1 rouge : 128 réussis, 1 échoué** — politique « Conseillé », référence, 80 joueurs : `shortestLoopSec` « sous 45 s à plus de 10 s d'une fusion » = 1 (limite 0). Ce n'est pas du bruit ni un réglage oublié : c'est un événement rare et réel, qu'aucune valeur libre de `Balance` ne retire (Tapis offerts ≤ 5 ou ≤ 4 essayés : sans effet) ; sur 400 joueurs « Conseillé », 2 boucles sur 50 463 (A5 r18 au jour 58 : 41,6 s, 10,7 s après une fusion ; A1 r0 au jour 14 : 35,5 s, 10,8 s), contre 0 sur 400 joueurs « la moins chère d'abord » aux 3 tailles et sur 140 jours ; les deux boucles sont pleines (un achat toutes les 2 s, aucune croissance hors ligne), la cible est atteinte 8,2-8,3 s après la fusion et le modèle ajoute le geste du Petit Splorch (2,5 s) et la vérification à la pression suivante (≤ 2 s), comme la simulation du design. La limite n'est pas assouplie : décision demandée au design (`scratchpad/v2/notes-croisees.md`).

**Journal du lot A1, étape 4 : relecture indépendante (5 novembre 2026)** — chaque défaut a son cas écrit AVANT la correction et rouge sur d0ab475 (`tests/specs/Review_A1.spec.luau` ; `EconomyPacing.spec` › « règles de la porte (relecture A1) », jouée sans simulation dans check.sh comme la nuit) ; rapport `scratchpad/v2/revue-A1.md` :

- **A1-37. `Prestige.validateConfig` : l'invariant de stabilité vaut pour chaque pas de la liste des conditions.** Depuis A1-32, `Balance.Ascend.ReqR` liste les 60 conditions et `ReqStep` ne sert qu'au-delà de la 60e (jamais jouée) : seul `ReqStep` était vérifié, et une configuration envoyée en direct avec un pas de 3 dans la liste (boucle record de plus en plus courte, l'économie qui s'emballe : critique M13) passait. Maintenant `(BeyondMult / 2)^(ReqR[k] − ReqR[k − 1]) ≥ 0,95 × GrowthMult` pour k = 2 … #ReqR, et pour `ReqStep` ; la boucle de multiplications s'arrête dès que l'issue est connue (un pas hostile de 1e12 ne bloque pas le serveur). La configuration livrée (pas de 4 et de 5) passe. Attente changée : `Props_Prestige` › invariant de stabilité, la référence indépendante compte aussi chaque pas de la liste (plus stricte : sans cela la propriété aurait figé l'ancienne règle).
- **A1-38. `UpgradeMath.effect("cozyBed")` : les vraies heures du joueur.** La ligne du Lit douillet écrivait « Nuit : 8 h → 12 h » à tous, quand la ligne du Sac de nuit comptait la famille Spiky et le Sac (GDD §10.7.7 : « les valeurs sont celles du joueur ») : un joueur au Sac de nuit 1 lisait 8 h → 12 h pour 9 h → 13 h réelles (`Formulas.offlineSeconds`). Champ ajouté au contexte : `EffectCtx.nightBag` (niveau du Sac, 0-3 ; B2 le passe avec `cozyBed` et `spikyFamily`) ; l'heure de la famille Spiky est lue dans `Config/Species` (comme `Formulas.offlineSeconds`) au lieu d'un 1 écrit en dur. Sans ces champs : 8 h → 12 h, comme avant.
- **A1-39. Alarme rapide de check.sh : seul le côté de queue est élargi.** `applyAlarm` élargissait de 2 σ20 les DEUX limites d'une clé de queue ; la règle (§27.9, A1-28) ne vise que le côté dont la marge est sous 2 σ20 ; l'autre limite, à 5 σ20 ou plus, doit bloquer check.sh à sa vraie valeur. La borne basse de `coinsLostRatioGrand` J8-14 de l'assidu valait −0,56 (impossible à franchir), celle de `tapis12RecordLoopByA` A7 0,30 au lieu de 0,45 ; les bornes hautes du premier Grand Splorch, du plus gros au jour 7 et de `ascendGapDays` A6→A7 valaient 17,38, 4,24e8 et 17 au lieu de 16, 4e8 et 16. Table `TAIL` : champ `side` (« lo » ou « hi ») ; libellé « [alarme rapide −2σ | +2σ …] » ; tableau du §27.9 mis à jour. Valeurs de check.sh inchangées (toutes dans leurs vraies limites du côté qui n'est pas de queue).
- **A1-40. `everyFamilyBought` : Gants et École ouverts par le Record R.** La spec les ouvrait par le r de la boucle (r ≥ 1, r ≥ 2) ; `Config/Upgrades` les ouvre au Record R 1 et 2 (GDD §4.6.1 ; définition de la clé : « pendant qu'elle est ouverte ») : les boucles r = 0 et 1 qui suivent une Ascension (Record R ≥ 15) sortaient du dénominateur. Corrigé (`l.r ≥ 1 or l.afterAscend`, le Record R d'avant toute Ascension valant r au début de la boucle). Valeurs inchangées (Gants et École achetés dans ces boucles : 1,0 aux 3 tailles).
- **A1-41. Résultat de la relecture** : specs du lot vertes (Prestige 22, Props_Prestige 4, Static_PrestigeOnly 3, UpgradeMath 14, Props_UpgradeMath 6, UpgradeAdvisor 9, Bitset 9, TierRules 6, Static_NoPow 2, Formulas 35, Props_Formulas 26, QuestRules 31, Props_QuestRules 7, BigNumber 11, Props_BigNumber 12, Invariants 25, Props_Invariants 5, `Review_A1` 8) ; Contract* 129 ; utilisateurs (ProfileRepair 21, DataChaos 8, SquishyService 35, Static_TextSet 32, ClientBoot 11, Boot 14) ; EconomyPacing forme check.sh **57 réussis, 0 échoué** (55 + les 2 règles de la porte, 56 s) ; jeu de nuit relancé une fois (20 cas, 49 min) : **19 verts, 1 rouge, 168 réussis, 1 échoué** — la même clé qu'A1-36 (`advisor`, `shortestLoopSec` à plus de 10 s d'une fusion = 1), décision du design toujours attendue ; aucune valeur changée. Cherché sans défaut : API du §27.7, nombres du GDD, interrupteurs coupés = v1.3, puissances, NaN / inf / −0, client = serveur, bords, idempotence et champs gardés de `apply` (30 carrières de 400 prestiges : `Invariants.afterPrestige` sans violation), Conseillé (5 000 instantanés), bascules de semaine et d'année, `BigNumber` (20 000 entiers : jamais arrondi vers le haut). Risque mesuré, hors du lot : sans le champ `memoryR` (INT-A1-MEMORY, toujours au contrat), la porte reste verte à 80 joueurs mais la falaise du retour de l'assidu passe de 3,39 à 3,61 au p90 (limite 4) : le champ doit arriver avant l'ouverture de `JellyAscend`.

**Journal du lot B1, étape 1 (3 novembre 2026)** — politique de texte unique (N10) :

- **B1-1. Plus aucun `TextScaled` dans `src/client`** : `TextSize` fixe à la taille dessinée et `UITextSizeConstraint` posés par `UI/Text` seul (`Static_TextSet`) ; retours à la ligne gardés comme l'ancien `TextScaled` (qui les imposait). Sur 32 571 textes `TextScaled` des captures d'avant (3 profils TV × 2 langues), 494 seulement étaient réduits, en 6 endroits : bannières (nom d'un joueur de 20 caractères), titre des cartes de côté, grand tampon des effets, puce « MENU » (97 px pour 96), nom d'un article de la Boutique (« Selles et Traînées », 1 px) et messages (`Toast`) : ces 6 textes sont la sorte **"fit"** de `UI/Text` (exception fermée, même règle que l'ancien `TextScaled`, calculée par le jeu avec `TextService` ramené à Medium) ; tous les autres sont des **"label"** à leur taille dessinée. Aucune « sentence » dans le jeu de base (rien n'y grandit avec `PreferredTextSize`, comme avant) : B2 et B3 les posent dans des boîtes prévues pour Largest.
- **B1-2. Compensation mesurée** : deux étiquettes témoins cachées (libre et bornée, `ScreenGui` `TextWitness` sans `UIScale`, hors de l'écran, `Decorative`) donnent `Text.factor()` et le facteur appliqué malgré la contrainte ; un libellé reçoit `TextSize = taille ÷ ce facteur` (1 si la contrainte borne). `Text_policy` simule les deux moteurs (`MockInstance.textEngine`, `TextBounds` calculés) ; la question « bornes de `TextScaled` avant ou après `UIScale` » (`capRisk`, `--cap screen`) disparaît avec `TextScaled` (captures tv1080, tv720, tv2160 × EN, FR : 16 628 `capRisk` avant, 4 après, tous dans l'écran de chargement de `src/first`, note INT-B1-LOADING ; 40 440 textes identiques en taille, lignes et rectangle, aucun problème nouveau) ; reste la seule contrainte `MaxTextSize` d'un libellé, que la photo du panneau TextProbe en 4K tranche.
- **B1-3. Attente changée** : `VFXController.spec` › tampon long attendait `TextScaled = true` ; il attend maintenant `TextScaled = false`, sorte "fit" de 96 px (28 au moins), retours à la ligne (GDD v2.0 §10.1, N10).
- **B1-4. `UI/Format`** (formateur unique des nombres de `UI/*` hors montants) : espaces ordinaires en français (FredokaOne n'a ni U+00A0 ni U+202F), plafonds affichés tenus dans les places réservées (`Format_Widths`, 10 000 tirages) ; défaut du jeu de base corrigé au passage : les chiffres romains du titre du spectacle n'avaient ni L, ni XL, ni XC (« GRAND SPLORCH XXXX » au 40e) ; chances du Guide et millisecondes de Diagnostics avec la virgule française.
- **B1-5. Panneau TextProbe** : 5e onglet « Texte » de Diagnostics (administrateurs), 6 témoins (28, 36, 48 px, libres et bornés) dans des boîtes dorées de leur taille, `TextBounds` et facteur de chacun, taille de texte de Roblox, facteurs mesurés, échelle de l'écran ; 9 clés `panel.diag.tab.probe` et `panel.diag.probe.*` (EN, FR) ; onglet ajouté à `Screens.PANEL_TABS` (une ligne, pour le prouver dans `TextFit_all`). Facteurs de `TextMetrics.preferredTextSize` : pire cas 1,5 jusqu'aux photos (`preferredPhotographed = false`, générateur `metrics.mjs`).
- **B1-6. Notes d'intégration** : **INT-B1-LOADING** (contrat) : `src/first/Loading.client.luau` garde 2 `TextScaled` (message et « Réessayer », écran autonome qui ne peut pas requérir `UI/Text`) ; **INT-B1-STARS** (B5) : `Shared/Render/SquishyBuilder` garde le `TextScaled` des étoiles « ★ » au-dessus d'un squishy (à dessiner, règle 18).

**Journal du lot B1, étape 2 (3 novembre 2026)** — focus, entrées, messages et glyphes (N11, N14, INT-V2-GLYPHS a) :

- **B1-7. Cadre de focus dessiné à l'intérieur** (`FocusGuard.selectionImage`, GDD v2.0 §10.1, règle 14) : trait blanc de `Layout.Focus.Frame` (6) px et liseré sombre de `Layout.Focus.Border` (2) px tous deux DANS le rectangle de l'élément (`FocusGuard.cursorOutset` = 0 ; l'ancien curseur de `UI/Root` débordait de 12 px), respiration 0 ↔ 0,35 (fixe en Mouvement réduit) ; porté par chaque bouton de `Widgets` et de `Hud/Util` ; un élément sélectionné qui dépasse d'un `ScrollingFrame` y est ramené entier (`FocusGuard.keepInside`). N11 : grossissement 1,05 du focus seulement pour un bouton **isolé** (ni rangé par un `UI*Layout` de son parent — rail, onglets, listes —, ni dans un ancêtre qui découpe ; prop `grow = false` pour les cartes). `FocusGuard_clip.spec` : chaque élément sélectionnable de chaque panneau, de chaque onglet et du rail, à tv720, tv1080 et tv2160 (≥ 150 par profil) ; `Root.selectionImage` reste (specs du socle, copie de `src/first`).
- **B1-8. InputGuard générique** (`FocusGuard`, N14, §10.6 règle 6, §10.7.9) : à l'ouverture de toute fenêtre (`FocusGuard.open`) ✕, Entrée, Entrée du pavé et le clic sont ignorés tant que leur relâchement n'est pas vu et que `Balance.Upgrades.GuardOpen` (0,3 s) n'est pas passée ; `GuardFocus` (0,4 s) quand l'élément sous le focus change d'identifiant **sans que le joueur l'ait déplacé** : sélection rendue par le code (`restoreTop`, `refocus`, `closeNow`), L1 / R1 / L2 / R2 dans une fenêtre, attribut `FocusId` de l'élément sélectionné changé. Lecture retenue : un pas de croix du joueur n'est pas gardé (le joueur voit où il va ; une garde de 0,4 s après chaque pas rendait les boutons morts). Chaque appui est jugé à son `InputBegan` (capté même `gameProcessed`) ; un appui commencé pendant la garde est ignoré jusqu'à son relâchement (« △ puis ✕ tenu 2 s : 0 achat ») ; `Activated` est jugé sur l'appui qui vient de finir (0,25 s) ; jamais bloqué : chaque nouvel appui est jugé seul, horloge recalée = garde expirée, `WindowFocusReleased` relâche tout. Lu par `Widgets.button`, `Widgets.toggle`, les maintiens et `Hud/Util.button` (`FocusGuard.confirmReady`, `notePress`, `guard`, `guardInfo`).
- **B1-9. Maintiens de 0,6 s** (`Widgets.holdOn(bouton, { duration = Balance.Upgrades.HoldSeconds par défaut, onProgress, onEarly, canStart })`, `Widgets.hold` s'en sert) : commencés par l'`InputBegan` capté de ✕ ou d'Entrée (bouton sélectionné, ou survolé par la souris pour Entrée quand rien n'est sélectionné) ou par le clic maintenu, **jamais** par `Activated` ; un achat par appui ; relâché tôt : `onEarly`. Écart avec le §27.8 (« dans `InputController` ») : la garde et les maintiens vivent dans les modules feuilles `FocusGuard` et `Widgets`, car `InputController` requiert `PanelController` → `Panels` → `Widgets` (un panneau ne peut pas requérir `InputController`) et le moteur donne ✕ et Entrée à la sélection, jamais aux liaisons du jeu ; `InputController` est inchangé. `Upgrades_InputGuard.spec` (partie générique, 22 cas, interrupteur `UpgradesScreen` coupé et ouvert, dont le vrai client : △ ouvre le menu, ✕ tenu 2 s aussitôt n'ouvre rien) ; les cas de l'écran Améliorations sont au lot B2.
- **B1-10. Messages et onglets** : le défaut « message par-dessus les onglets pendant 3 s » (rapport des écrans, § 6.1) était déjà corrigé par la revue (`Toast.anchor`, barre de titre, 056d7af) ; `Toast_panels.spec` le prouve partout : chaque panneau et chaque onglet de `Screens.PANEL_TABS` à tv720, tv1080 et tv2160, par la file du HUD et par `Toast.show`, message déjà à l'écran à l'ouverture, R1, les 4 messages `feedback.*` les plus longs fusionnés « ×3 », panneau refermé (retour à l'emplacement du HUD) : jamais sur un onglet, le contenu, un élément sélectionnable ni le focus ; ancre coupée (mutation) : 9 cas rouges.
- **B1-11. INT-V2-GLYPHS (a)** : `Theme.Fonts.Body` passe de GothamBold à FredokaOne (messages, cartes ; `Theme.Fonts.Stamp` = LuckiestGuy) ; U+00A0 des 13 clés → repère **`{_}`** de `UI/Text` (`Text.GLUE`) : une espace ORDINAIRE qui ne coupe jamais la ligne (UI/Text coupe lui-même aux autres espaces et écrit les retours ; sans lui, `TextFit_all` montrait « Jour » / « 1 », « BOOP » / « RUSH », « 5 » / « s. », « (1 » / « sur » : 48 cas) ; « ★ » de `common.stars` et `celebrate.star` → repère **`{*}`** (`Text.STAR`, toujours après le nombre : « 5★ ! » au lieu de « ★5 ! », des espaces en tête de ligne pouvant être mangées par une coupure) : étoile dessinée (`Glyph.star`, pentagramme de 5 traits et un disque, liseré sombre, couleur du texte), espaces ordinaires à sa place dans le texte (`Text_icons.spec`) ; `Util/Format` : espaces ordinaires en français et ±inf → ±1e300 (plafond affiché, comme `BigNumber`) ; `Contract_glyphs` : 15 lignes retirées de `BASE_EXCEPTIONS` (restent 7 clés de B2 et B3), `FORMATTER_EXCEPTIONS.Format` vide.
- **B1-12. Attentes changées** : `Contract.spec` › Format français (« 1,24 M », « 1 234 567 », « 5 h 12 » : U+00A0 → U+0020, règle 18, FredokaOne n'a pas U+00A0) ; `ClientBoot.spec` › ±inf « ∞ » → « 1.00e300 » (« ∞ » absent des deux polices) ; `Console_panels.spec` › clic sur le rail 0 s après l'ouverture du menu → après 0,5 s (InputGuard, N14) ; `HUD.spec` › carte de la cible « 2★ » → « 2 » et une étoile dessinée (règle 18).
- **B1-13. Harnais** : `MockInstance.styleFeatures` (`UIShadow`, `RadialGradient` ; absents par défaut = style à plat des captures de référence ; propriétés supposées `Color`, `Transparency`, `Offset`, `BlurRadius`, `UIGradient.Type`), `ApiAudit` (classes et propriétés plus récentes que la base de Lune), `EngineProps.NEWER_DEFAULTS` ; `UI/Theme.shadow` (UIShadow ou ombre de repli : Frame frère 6 px plus bas à 50 %, qui suit sa cible), `Theme.radial`, `Theme.styleFallbacks`, `Theme.onStyleFallback` (compteur `StyleFallback` de Diagnostics, A4), `Widgets.frame({ shadow = true })` (`Theme_style.spec`) ; `MockInstance.created()` et `descendantCount(racine)` (budget d'instances, règle 20) ; valeurs par défaut des `ScrollingFrame` ; `UI/Text` pose l'attribut `TextSource` (texte d'origine, repères compris) et `Screens.keyBoxes` le lit pour relier un texte affiché à sa clé (une ligne du harnais d'écrans, comme `PANEL_TABS` à l'étape 1) ; la mesure des clés compte « {_} » et « {*} » comme 3 caractères (un peu plus large que l'affichage : prudent).
- **B1-14. Notes d'intégration** : **INT-B1-RAIL** (B2) : les symboles du rail du menu (`PanelController` : ✦ ♥ ★ ✓ ⚙) sont hors des deux polices et hors de `Contract_glyphs` (pas des clés) : à dessiner (`Glyph.star` pour ★ et ✦) ; **INT-B1-KEYTEXT** (socle `Client/Util/Platform`) : textes de repli des touches au clavier ⌫ ↑ ↓ ← → ▭ ≡ hors police ; **INT-B1-SHADOW** (B2, B3) : `Widgets.frame({ shadow = true })` sur les panneaux et les cartes, et `FocusGuard.guard()` après un changement de contenu par le code (onglet cliqué, Conseillé recalculé), `FocusId` sur les cartes ; **INT-B1-LOADING** s'étend au curseur : `src/first/Loading.client.luau` garde sa copie du curseur qui déborde de 4 px.

**Journal du lot B1, étape 3 (3 novembre 2026)** — relecture indépendante (`tests/specs/Review_B1.spec.luau`, chaque cas rouge sur 519ac44 avant sa correction ; rapport `scratchpad/v2/revue-B1.md`) :

- **B1-15. Facteur de TextService mesuré** : `UI/Text` divisait toute mesure de `TextService:GetTextSize` par le facteur du joueur, en supposant (jamais mesuré, GDD §10.1 critique B3) que TextService honore `PreferredTextSize` ; s'il ne l'honore pas, au réglage Largest les "fit" (bannières, cartes de côté, tampons, messages, MENU, noms de la Boutique) et la borne des mots grandissaient de 50 % et débordaient (bannière de 60 caractères : 47 px au lieu de 31). `Text.measurements().service` = f × hauteur TextService ÷ hauteur dessinée du témoin libre (même texte) : 1 ou f selon le moteur ; cache des mots vidé quand il change ; `Text_policy` › « le client entier » joue les deux TextService, et le nouveau « démarrage au réglage Largest : mêmes libellés qu'à Medium » (rouge sans la correction) ; cas ajoutés, aucun retiré.
- **B1-16. Phrases agrandies** : les lignes des mots tenus ensemble (`{_}`) et les étoiles (`{*}`) d'une "sentence" sont faites à sa taille À L'ÉCRAN (facteur du joueur, borné par sa contrainte quand le moteur la respecte) et refaites à chaque nouvelle mesure ; `Glyph.star` pose traits et disque en fractions de son cadre (le dessin suit la taille du cadre, plus d'arrondi des `Offset`). Aucune phrase dans le jeu de base : B2 et B3 en auraient hérité.
- **B1-17. Maintiens** : jamais sur un bouton caché (Entrée tenue dans le jeu sur un bouton resté « survolé » sous une fenêtre fermée l'achetait ou vendait, invisible) ; `Widgets.holdOn` rappelé sur un bouton arrête l'ancien maintien et coupe ses 4 connexions (le clic lançait encore l'ancien `onComplete`).
- **B1-18. Attente changée** : `Format.spec` › confetti : au-delà de 99 999, la forme courte de `BigNumber.abbreviate` refaite à l'identique dans le module pur (GDD §4.2 : « 100K », « 999K », « 1,50M », suffixe collé comme A1-18 ; plafond 1e9, borne du schéma) au lieu de « 100 K » … « 999 K » (espace sécable, et « 999 K » faux de 1 000 000 à 1e9).
- **B1-19. Maintien et focus** : un maintien en cours s'arrête sans acheter si le contenu change sous le focus (`FocusGuard.contentChanges()` : fenêtre ouverte ou refermée au-dessus, L1 / R1 / L2 / R2, `FocusId`, `guard()` ; un simple sauvetage de la sélection n'en est pas un) ; un maintien fini consomme son appui (`FocusGuard.consumePress()`) : son relâchement n'est plus un clic (ni le son Error d'un bouton que l'achat vient de griser, ni l'action du clic en plus de l'achat).
- **B1-20. TextProbe en 4K** : le facteur affiché de chaque témoin retire l'échelle des `TextBounds`, mesurée (témoin libre de 48 px du panneau ÷ témoin caché de `UI/Text`, sans UIScale) : « ×2,00 » à Medium sur la télé 4K si le moteur rend les TextBounds en pixels de l'écran ; TextBounds bruts inchangés.
- **B1-21. « 1 in {odds} » tenu ensemble en anglais** : les 8 clés EN (`common.oneIn`, `celebrate.secretTag`, `celebrate.flop`, `celebrate.glitch`, `celebrate.rainbow`, `banner.secretHatch`, `banner.rareMutation`, `panel.ranch.confirmRare`) reçoivent le repère `{_}` comme leurs 8 clés FR (« 1{_}sur ») : le tampon anglais se coupait « SECRET Prickle Puff · 1 » / « in … » (capture `stamp.secretTag` en tv1080 EN ; règle `unitSplit` de l'outil aveugle à « in »).
- **B1-22. Notes d'intégration** : **INT-B1-GLYPHS2** (B2, B3, B5) : caractères hors des deux polices écrits par le code (pas des clés, hors de `Contract_glyphs`) : « ′ » (`UI/HUD`, minutes du bouclier et du boost), « ◀ » « ▶ » (`Panels/OutfitPreview`, `Panels/SplorchPreview`), « ✓ » (`Panels/Objectives`, `Panels/Ranch`), « ♛ » (`Controllers/RanchRenderer`) ; **INT-B1-FORMATGLUE** (B2) : espaces ordinaires des formateurs français (« +5 % », « 9,0 s », « 5 h 12 », « 12 345 ») : dans une phrase à retours à la ligne, passer par `Text.GLUE` ; **INT-B1-CONFETTI4** (contrat) : « 1 000 » (`Format.confetti` FR) contre « 1000 » (`BigNumber` FR, A1-18) à 4 chiffres.
- **B1-23. Taille d'un « fit » à mots tenus ensemble** : elle était calculée sur les lignes coupées à la taille précédente (tampon « FLOP ! LE PLUS RARE · 1{_}sur 1,00M » coupé d'abord à 96 px en 2 lignes, puis réduit pour ces 2 lignes et recoupé : une ligne de 1 009 px dans 680, que le moteur recoupait n'importe où, ou un texte deux fois trop petit) ; `UI/Text` calcule maintenant la taille sur le texte d'origine coupé à chaque taille essayée (`gluedFit`, même coupe que l'écriture). Concerne les tampons, bannières et messages dont la clé porte `{_}` (FR depuis B1-11, EN depuis B1-21).

**Journal du lot B1, fin de la relecture (5 novembre 2026)** — reprise après la coupure (commit 321b332 vérifié : complet, specs vertes) ; chaque cas rouge sur 321b332 avant sa correction (`Review_B1.spec`) :

- **B1-24. Maintien : bouton vérifié PENDANT le maintien** (`Widgets`, `stepHolds`) : le bouton n'était vérifié qu'au début ; une fenêtre fermée par le code sous la souris (dernière fenêtre, sélection sur un autre bouton : ni `MouseLeave` ni `SelectionLost` pour le bouton tenu) ou un bouton grisé par le code (`Widgets.setDisabled` : plus rien à vendre, bloqueur du Grand Splorch, pièces dépensées ailleurs) achetait 0,6 s plus tard, invisible ou refusé. Le maintien s'arrête maintenant sans rien acheter (`onEarly`) dès que le bouton n'est plus affiché ou est grisé. Concerne aussi le jeu de base (maintiens Vendre / Relâcher du Ranch, Grand Splorch) : correctif de sécurité d'entrée, comme B1-17 ; aucune spec existante changée.
- **B1-25. Outil d'écrans : trois trous fermés** (notés au § 3 de la revue) : (1) `unitSplit` connaît « in » (« 1 in N » anglais) comme « sur », dans `TextFit.UNITS` (exportée) et dans `renderer.js` (même liste, vérifiée par `Review_B1`) ; (2) `Screens.numberIssue` signale aussi un nombre GROUPÉ de 6 chiffres ou plus (« 1 000 000 », « 123,456 », insécables comprises), que la règle des chiffres collés laissait passer ; (3) le scénario des tampons écrit la cote comme le jeu (`Screens` : cote la plus rare de `Logic/Odds` aux vrais réglages, écrite par `World/Util.number` comme `VFXController`) au lieu de « 1 000 000 000 » en dur : « 1 sur 2,00B » (Flop), « 1 sur 6,70M » (Secret). Captures relues (tv1080, tv720 × FR, EN, 52 écrans, 0 problème). Aucune attente de spec changée (commentaires de `Screens_display` mis à jour).
- **B1-26. `TextFitKeysPending` : les 10 clés v2.0 de A1** (`fun.decoShop`, `fun.emote`, `fun.palettes`, `fun.pennants`, `fun.saddle`, `fun.title`, `fun.trail` : `Logic/UpgradeMath` ; `unlock.item`, `unlock.monument`, `unlock.recordBonus` : `Logic/Prestige.unlockTiles`) sont de vraies clés d'affichage de B2 et B3 (écrans derrière `UpgradesScreen` et `RecordR` coupés) : une ligne en attente par clé avec sa raison (remède de la note croisée d'E1, 3 novembre), le lecteur de clés n'est pas contourné ; B2 et B3 retirent chaque ligne quand leur scénario prouve la clé (sinon `TextFit_all` › « aucune clé prouvée ne reste en attente » échoue). `TextFit_all` vert (2 100 cas).
- **B1-27. Notes d'intégration** : **INT-B1-FUNTITLE** (contrat, B2) : `Config/Upgrades.Fun`, ligne `title`, a `nameKey = "fun.title"`, la clé du TITRE DE SECTION (« Pour le plaisir » / « Just for fun », GDD §4.26 et §10.7.5 : un titre de section, puis 7 lignes dont « Titre « Confetti Star » ») ; la ligne s'afficherait « Pour le plaisir » au lieu de « Titre « Confetti Star » » (`fun.title.confettiStar`, aucune ligne de src ne la cite). Remède au choix du contrat : `nameKey = "fun.title.confettiStar"` (et l'attente de `UpgradeMath.spec` › `effect("fun.title").key`), ou une autre clé pour le titre de section ; pas fait ici (fichiers du contrat et de A1). **INT-B1-GUARD** (B2) : depuis B1-19, `FocusGuard.guard()` arrête tout maintien en cours : ne l'appeler que si l'élément sous le focus CHANGE vraiment (onglet, liste rechargée, carte du Conseillé qui change de famille), jamais à chaque recalcul du Conseillé qui rend la même cible (les pièces changent plusieurs fois par seconde : aucun maintien ne finirait).

**Journal de la porte des lots A1 et B1 (publication, 5 novembre 2026)** — agent de publication seul dans l'arbre ; petites notes croisées réglées, `./scripts/check.sh` une fois :

- **REL-1. INT-B1-FUNTITLE réglée** (B1-27) : `Config/Upgrades.Fun`, ligne `title` : `nameKey = "fun.title.confettiStar"` (« Confetti Star Title » / « Titre « Confetti Star » ») au lieu de `"fun.title"`, qui est le titre de la SECTION « Pour le plaisir » (GDD §4.26, §10.7.5) : la ligne se serait affichée « Pour le plaisir ». Remède le plus petit des deux proposés (aucune clé renommée, `Strings` inchangé, identifiant `fun.title` de la ligne inchangé, aucun effet sur l'économie : le modèle lit les lignes par identifiant). **Attente changée** : `UpgradeMath.spec` › effets, `effect("fun.title").key` attend `"fun.title.confettiStar"` (l'ancienne attente figeait le défaut). `TextFitKeysPending` : raison de `fun.title` réécrite (la clé reste en attente : préfixe `"fun."` d'`UpgradeMath`, et titre de section que B2 affichera) ; `fun.title.confettiStar` n'est citée que par `Config` (hors des sources « client » de `TextFitKeys`) : aucune ligne en attente de plus.
- **REL-2. Texte du GDD aligné sur les trois réglages de `Balance` du lot A1** (§21, A1-31, A1-32 ; note croisée du 5 novembre, 17 h) : Pot de nuit 25 → 28 → 31 % (§3, §4.19, §4.26 ligne 7, Annexe B et ses cas les plus longs), condition de l'Ascension + 5 une fois toutes les 8 Ascensions dès la 11e (§4.27 tableau et « Pourquoi »), prix × 0,31 dès A11 et × 0,29 aux Ascensions d'un Grand Splorch de plus (§1 F(A), §3, §4.6, §4.27), chiffres de l'assidu (A = 28 au jour 140, une Ascension tous les 5 jours : §4.24.1, question 9, « Ce qui reste ouvert ») et du joueur de 10 min (Pot de nuit 1,87) ; bloc « Porte d'économie du lot A1 » au Journal de révision v2.0. Les mesures historiques du design (critique B1, tableaux de §4.24.1) sont gardées, annotées. La clé rouge de la nuit (`shortestLoopSec`, « Conseillé ») est écrite dans « Ce qui reste ouvert » : décision du design, pas prise ici ; aucune limite ni valeur changée.
- **REL-3. Le jeu de nuit a sa place dans le guide de publication** (docs/05 §1, tableau des portes) : `./scripts/economy-nightly.sh` à chaque lot qui touche l'économie et avant toute ouverture d'un interrupteur de l'économie v2.0 (il n'a aucun déclencheur : ni CI, ni tâche planifiée, ni check.sh). Pas relancé par cette porte : la relecture d'A1 l'a joué sur le code final (20 cas : 19 verts, 168 réussis, 1 échoué, le cas `advisor` seul rouge, A1-41) et rien de ce qui suit ne touche l'économie (REL-1 : un nom de clé ; REL-2 : du texte).
- **REL-4. Porte des lots A1 et B1 : `./scripts/check.sh` vert** (5 novembre 2026, 18 h 02 → 18 h 22 UTC, 20 min 20 s, une fois, sur le code de REL-1 à REL-3) : StyLua propre ; Selene 0 erreur, 0 avertissement ; **4 350 réussis, 0 échoué, 0 spec non chargée** (194 fichiers de specs ; dont `EconomyPacing` 57, portes v1.3 et v2.0 en 52 s sur 4 fils ; `TextFit_all` 2 100 ; `Review_A1` et `Review_B1` 47) ; build Rojo ; `verify-place` (1 Script, 2 LocalScript, 145 ModuleScript, structure valide). Aucune correction nécessaire. Jeu de nuit non relancé (REL-3) : son seul rouge, `advisor` / `shortestLoopSec`, attend la décision du design.

**Journal du lot A2, étape 1 (données v2 et deux décisions du chef, 5 novembre 2026)** — agent seul dans l'arbre ; chaque défaut par une spec rouge d'abord :

- **A2-1. INT-A1-MEMORY (décision du chef, acceptée) : champ `memoryR`** au schéma v2 (entier 0-400, `≤ bestR`, défaut 0 ; écrivain SplorchService par `Prestige.apply` : Record R au moment du retour au record après une Ascension ; `Prestige.firstRecordLoop` donne le × 1,25 de la 1re boucle record quand r = bestR = memoryR) : `Schema.OWNERS_V2` et `defaultsFor(2)`, migration (0), `ProfileRepair` v2 (illisible, négatif ou au-delà de `bestR` → 0 : une valeur ramenée à `bestR` donnerait un × 1,25 de trop ; fractionnaire → arrondi vers le bas), tableau du §27.2 ; **témoin `v2.json` régénéré** par la migration du dépôt (seule différence : `"memoryR": 0`) ; `Contract_v2` (`V2_KEYS`, propriétaire, défaut, v1.json migré). `Prestige` inchangé (il écrivait déjà le champ quand il existe). Chaîne vérifiée (`ProfileRepair_v2` › memoryR) : profil neuf, v1.json migré et profil abîmé réparé, jusqu'à l'Ascension, au retour au record (`firstRecordLoop` vrai) et au record suivant (faux) ; jamais vrai sans retour. Note → A1 : `Invariants.profileV2` ne borne pas encore `memoryR` (notes croisées).
- **A2-2. Interrupteurs coupés (§27.2, §27.3) : rien ne change pour un joueur v1.** Tant que `SchemaV2` est coupé, la migration ne tourne pas (VERSION 1, `migrate` sans cible ≤ 1), un profil v2 n'atteint jamais la réparation (refusé : « schéma plus récent ») et `ProfileRepair` répare un profil v1 exactement comme la version de test (modèle `Schema.defaults()`, aucun champ v2 lu ni écrit, R borné à 1e6). La réparation v2 se choisit sur la **version du profil** (≥ 2), jamais sur celle du serveur : testable dès maintenant, identique sur un serveur v2. `DataChaos` › « interrupteur coupé » : v1.json relu et réécrit en v1, sans aucun champ v2 ; `ProfileRepair_v2` › « profil v1 : réparé exactement comme avant ».
- **A2-3. Migration v1 → v2 exacte : chaque champ ajouté par la v2 est ÉCRIT** (défaut v2 ou valeur calculée) au lieu d'être créé par `reconcile` seulement s'il manque : une valeur trouvée sous une clé v2 dans un profil v1 (essai, vieux bug) ne passe jamais en v2. Liste tirée de `defaultsFor(2)` contre `defaultsV1()` (clés de premier niveau, sous-clés des tables de la v1 : `tiles.star`, `caps.starRain`, `season.frostDays`…) : toujours complète ; clés inconnues gardées ; idempotence (garde sur `version`) et témoin inchangés. `Contract_v2` › « profil v1 portant des champs v2 périmés » (rouge avant).
- **A2-4. `ProfileRepair` v2, bornes et valeurs sûres (§27.2, bloc « Réparation v2 : règles du lot A2 »)** : R ≤ 400 ; `bestR = max(bestR, r)` ≤ 400 (illisible → r) ; `ascend` 0-60 ; `regainBonusA ≤ A` (illisible → A : bonus jamais donné deux fois) ; `memoryR` (A2-1) ; Confettis 0-1e9, poche > total → **total relevé** (jamais un Confetti de poche perdu) ; familles nouvelles bornées ; `atelier` à `#WorkshopRows` exactement, chaque case ≤ `#costs` ; chaque niveau ≤ `UpgradeMath.cap` tous interrupteurs ouverts (même règle qu'`Invariants` : Tapis Étoilé sans Tapis 12 ou au-delà du plafond de r, Monuments, Lit, Tremplin, Plume, bits de « Pour le plaisir » avant le Record R 1) ; ensembles de bits denses, allongés, mot abîmé → 0 (règle de `Logic/Bitset`), jamais tronqués en deçà de `Bitset.MaxBits` ; `decorBuilds` 18 × 0-10 ; statistiques v2 entières ; `unlocksSeen ≤ bestR` (illisible → `bestR`, aucune pluie de cartes) ; piste (Défis : 3 au plus, chacun une fois, id connu ; p et done réparés en place) ; booléens de l'accueil ; `season.frostDays` ; plafonds v2 ; Déco perso (64 bits ; emplacement vers un objet non possédé ou déjà posé → 0) ; cœurs (20 UserIds entiers et uniques au plus ; une liste à trous garde ses entrées lisibles, comme les Défis) ; `cosmetics.theme` connu et gagné (Record R, A, Squishydex, jours de Plop ; une autre source n'est jamais retirée ici), sinon `"color"` ; `version` entière ≥ 2. `regainBonusA` et `unlocksSeen` sont lus AVANT la forme (qui remettrait une valeur illisible à 0).
- **A2-5. Specs** : `ProfileRepair_v2` (nouveau, 13 cas : profils sains, frontière v1 / v2, 54 valeurs abîmées une par une, habillages gagnés, ensembles de bits, mauvais types, chaîne `memoryR`, 400 profils v2 et 200 profils v1 migrés abîmés à graine fixe : jamais d'erreur, sain, idempotent, JSON exact, accepté par Roblox ; mutation vérifiée : sans le plafond des niveaux ou sans le dédoublonnage des cœurs, 3 cas rouges) ; `DataChaos` + 9 cas sur des serveurs v2 (`SchemaV2` ouvert dans le harnais DU TEST, avant le premier `require` du schéma : migration malgré deux pannes, jamais deux fois ; sauvegarde perdue juste après la migration (panne jusqu'à l'abandon) : la v1 reste, le serveur suivant la migre à l'identique ; reconnexion pendant la sauvegarde de départ ; quotas 429 au chargement et au départ ; fermeture à 16 joueurs sur un magasin lent ; profil v2 abîmé ; déploiement progressif (un serveur v1 refuse sans rien écrire) ; préparation en échec) ; `Contract_v2` + 1 cas.
- **A2-6. Défaut de `DataService` (spec rouge d'abord : `DataChaos` › « préparation en échec »)** : la préparation du profil (`migrate` + `reconcile`) n'était pas protégée ; une erreur (étape de migration boguée, enregistrement illisible) tuait le fil du chargement : joueur bloqué sur l'écran de chargement, notre verrou laissé dans l'enregistrement. Maintenant : `pcall`, avertissement, verrou rendu (`releaseLoadLock`), renvoi poli `LOAD_FAILED_MESSAGE`, rien d'autre écrit. Aucun effet sur un chargement normal.
- **A2-7. `shortestLoopSec` : décision du chef sur la seule clé rouge du jeu de nuit** (cas `advisor`, référence, « sous 45 s à plus de 10 s d'une fusion » = 1 : 2 boucles sur 50 463, à 10,7 et 10,8 s de la fusion, A1-36, A1-41). L'intention de la clé est le temps que le joueur attend après une fusion avant d'atteindre la cible ; le geste du Petit Splorch (2,5 s), la file du Grand Splorch et l'attente de la pression qui voit la cible sont du temps du joueur, pas du jeu. **Mesure changée, limite inchangée** (10 s, aucune boucle au-delà) : `tests/sim/EconomyModel.luau` note pour chaque boucle `reachSinceFuse` = instant où la cible est atteinte − dernière fusion (exact sur le segment de croissance en cours : taux constant depuis `growth.t`, plus gros d'enclos inchangé depuis `bigChangedAt` ; sinon la fin du segment précédent, borne haute ; jamais avant la dernière vérification sous la cible) ; `EconomyPacing.spec` compte `reachSinceFuse > 10` (libellé « sous 45 s, cible > 10 s après une fusion ») ; `sinceFuse` (à la renaissance) reste dans le journal du modèle. Aucun comportement du modèle changé (ni tirage, ni décision), aucune valeur de `Balance` touchée. §27.9 et GDD (tableau du §4.24.1, liste des clés, « Ce qui reste ouvert » : décision prise) mis à jour. **Résultats** : `EconomyPacing` forme check.sh **57 réussis, 0 échoué** (57 s, 4 fils) ; jeu de nuit, cas `advisor` seul (`./scripts/economy-nightly.sh advisor`, 584 s) : **vert, 15 réussis, 0 échoué** (référence et assidu : la clé vaut 0 ; part sous 45 s 0,050 % et 0,027 %, plus courte 4 s et 3,3 s, toutes expliquées par une fusion).

**Journal du lot A2, étape 2 (achats de l'écran Améliorations et Confettis côté serveur, 5 novembre 2026)** — agent seul dans l'arbre ; tout derrière `UpgradesScreen`, `Confetti`, `Workshop`, `StarMat`, `Gloves`, `Monuments`, `RecordR` (et `RanchTiers` pour les paliers du ranch), coupés au lancement : jeu de base inchangé (specs du socle vertes telles quelles) :

- **A2-8. INT-V2-INTENTS (fichiers du contrat, permis par la tâche)** : `BuyUpgrade` passe de `Config/IntentsV2` à `Config/Intents` avec son handler (mêmes arguments, débit 10 / s, `activity`) ; `Contract_v2` (5 → 4 intentions v2.0 ; les vérifications de `BuyUpgrade` lisent `Config/Intents`, jamais dans les deux catalogues), `Contract_game` (`BuyUpgrade` dans la liste des intentions de jeu, `activity` vrai), `Remotes_Ranch` (+ `BuyUpgrade` dans les 18 intentions attaquées, + 2 cas écran ouvert) mis à jour dans le même lot ; `Fuzz` l'attaque tout seul. `JellyAscend` reste dans `IntentsV2` (étape 3) : aucun fichier du serveur ne cite encore la chaîne `"JellyAscend"` (`Contract_v2` › « aucun service ne branche une intention v2.0 »).
- **A2-9. Handler toujours branché, interrupteur lu à chaque message** : `UpgradesScreen` coupé = aucune réponse, aucune mutation, aucun compteur (comme sans handler, §27.3 règle 1) ; l'interrupteur s'ouvre ainsi en direct (règle 4) sans redémarrage. Couche des types (aucune réponse) : `mode` ∉ { 0, 1, 10 } refusé AVANT `UpgradeMath.plan` (qui accepte 0-40 ; `-0` vaut 0 = Max), niveau attendu entier ≥ 0, id ≤ 24 caractères ; existence : id inconnu (dont ligne en lecture seule, `fun.decoShop`, casse différente) refusé sans réponse.
- **A2-10. `UpgradeResult` TOUJOURS envoyé, refus « périmé » muet dedans** (`reason = nil`, `from = to` = niveau du serveur, `spent = 0`, instantané à jour ; compté `UpgradeStale`) : `Types.UpgradeResultPayload` et §27.5 disent « sauf périmé muet », `Config/IntentsV2` disait « UpgradeResult sans retour visible » ; sans réponse, la ligne « en cours » de l'écran dirait « Réessaie » au bout de 3 s (GDD §10.8 règle 12) : un retour visible, le contraire de « muet ». B2 reconnaît le périmé à `from == to` sans raison (note croisée) ; commentaire de `Types` à aligner par le contrat.
- **A2-11. Refus d'état, sans mutation** : profil absent ou joueur parti → rien d'envoyé (`nil`) ; sauvegarde de fin commencée (`DataService.isClosing` : sauvegarde de libération ou `BindToClose` ; une autosave en cours ne bloque rien, son instantané est copié d'un bloc avant l'écriture) → `upgrades.refused.busy` ; prestige en cours (sonde `EconomyService.setBusyProbe` posée par SplorchService : spectacle du héros, du départ à la fin) → `busy` ; configuration en vigueur refusée (A2-16) → `busy`. Ordre (§27.5) : état (session, niveau attendu) → règles (`capOf` : `locked`, `maxed`, `loopCap` pour le Tapis Étoilé au-delà du plafond de r ; prestige, configuration) → règlement du Pot → somme exacte → bloc.
- **A2-12. Somme exacte, un seul bloc** : `n, total = UpgradeMath.plan(id, niveau, mode, monnaie, plafond, r, A, Record R)` (jamais un prix recalculé) ; champ vérifié écrivable AVANT la première écriture (un Atelier illisible : refus, rien d'écrit) ; puis monnaie (une écriture), niveau(x), ranch reconstruit et contexte du revenu (familles en pièces), `TileBought` par niveau des 4 dalles de la v1.3 (objectifs inchangés), un `UpgradeBought(id, avant, après, monnaie)`, `ConfettiChanged(−total, "spend")` (Confettis) ou analytique `spendIncome` (`Tile_<dalle>` / `Upgrade_<id>`), sans yield. « Pour le plaisir » : premiers bits libres de la ligne, dans l'ordre ; Atelier : tableau dense (aucun trou).
- **A2-13. Champs v2.0 notés seulement dans un profil v2** (`PadRules.v2Profile` : `version ≥ 2`) : interrupteurs ouverts sur un serveur v1 (`SchemaV2` coupé), les familles et lignes v2.0 ont un plafond 0 (`locked`, aussi dans l'instantané) et `addConfetti` rend 0 ; les 4 dalles de la v1.3 restent achetables par l'écran. Jamais un champ v2 écrit dans une sauvegarde v1.
- **A2-14. `addConfetti(player, n, source)`, seul écrivain des gains** : sources de §27.4 (`splorch`, `petit`, `skipped`, `ascend`, `regain`, `record`, `fullPen`, `track`, `mastery` ; « spend » est le puits de `buyUpgrade`) ; n réel ≥ 1 → partie entière ; `confetti ≤ confettiTotal ≤ Balance.Confetti.Max` (le total plafonne aussi la poche) ; refus comptés `ConfettiRefused` (source inconnue, montant illisible) et `ConfettiCapped` ; `ConfettiChanged(crédit, source)` à chaque gain. `EconomyService_upgrades` › « aucun module du serveur n'écrit les Confettis hors d'EconomyService » (lecture des sources ; Schema et ProfileRepair exceptés).
- **A2-15. Instantané versionné** (`EconomyService.snapshot`, `UpgradeMath.snapshot` + plafonds 0 des lignes non notables) : la version croît de 1 dès que le CONTENU change (achat, pièces réglées, Confettis, prestige, plafond qui s'ouvre ou se ferme en direct), jamais sinon : `UpgradeResult` et le `DataPatch` de la même image portent la même version. `DataService.setPatchExtra(name, fn)` (nouveau, DataService) : valeur dérivée `upgradeSnapshot` dans l'instantané d'arrivée et dans chaque patch qui touche `coins`, `confetti`, `tiles`, `atelier`, `atelierCosmetics`, `R`, `bestR` ou `ascend` [UpgradesScreen] ; jamais un patch de plus, jamais un nom de clé du profil. Coût réseau écran ouvert : ≈ 0,8 Ko de plus par patch de pièces (JSON de 24 lignes × niveau et plafond ; ≈ 2 Ko/s par joueur qui presse 2 à 3 fois par seconde) ; à mesurer par `Soak` à l'étape I (note croisée).
- **A2-16. `Prestige.validateConfig` au chargement et en direct** : à `Init` sur `Config/Balance`, puis à chaque changement des interrupteurs de la progression (empreinte lue au tick d'EconomyService : un message LiveOps qui change la configuration la fait revérifier, sans toucher EventService, fichier d'A4). Refus compté `ConfigRefused` (compteur du service et `DiagnosticsService.report`, avertissement « ConfigRefused:<raison> » au panneau). Configuration en vigueur refusée → achats v2.0 « occupé » (un prix lu dans une table illisible n'est jamais débité) ; configuration proposée refusée → l'actuelle reste. Compteurs de §27.14 (`UpgradeStale`, `ConfigRefused`, …) : `EconomyService.counters()`, transmis à `DiagnosticsService.count(clé, joueur)` dès qu'A4 l'ajoute (note INT-A2-DIAG).
- **A2-17. Contextes d'A1 branchés (note « POUR A2 »)** : `GrowthCtx` + `star`, `A`, `bestR`, `firstRecordLoop` ; `IncomeCtx.monuments` [Monuments] (champ absent interrupteur coupé : contexte identique à la v1.3) ; `Formulas.offlineSeconds(…, Sac de nuit)`, `offlinePot(…, Pot de nuit)`, `offlineGrowth(…, maxGrowthRate)` ; `pressReward(…, Gants, Super Série)` et compteur de série plafonné par `Formulas.streakMax(superStreak)` dans `SquishyService` (fichier sans propriétaire v2.0 ; la note d'A1 et N5 « A1 + A2 » le confient à A2 : 6 lignes) — les Gants comptent aussi sur la pression de pet-sitting du propriétaire (sa pression), pas la série ; `tileCost(…, A)` (BuyTile, prix des dalles de RanchService, analytique de SplorchService). Interrupteurs coupés : Formulas ne lit aucun de ces champs, valeurs de la v1.3 au bit près (`EconomyService` 18, `SquishyService` 35, `SplorchService` 10, `RanchService` 30 verts sans changement). Aimant de l'Atelier branché aussi (§27.14 « Pot de nuit et Aimant ») : rayon du Pot `Balance.PotV2.MagnetRadii` [Workshop] dans RanchService (sinon un achat en Confettis sans effet).
- **A2-18. BuyTile v2.0 et N21** : chemin de `buyUpgrade` dès que l'écran est ouvert, ou quand la dalle du Tapis achète le Tapis Étoilé (Tapis 12, `StarMat`, profil v2) ; sinon chemin de la v1.3 (prix `Formulas.tileCost`, le nombre de l'étiquette de la dalle : la différence d'une pièce d'INT-A1-TILECOST n'apparaît jamais écran coupé). `PadRules.target` / `progress` / `visible` : la dalle du Tapis reste allumée tant que le Tapis Étoilé a un niveau ouvert dans la boucle ; RanchService (`firePad` sur le niveau affiché 13-20, prix du Tapis Étoilé pour « pièces suffisantes »). Feedback du panneau de la v1.3 gardés ; `UpgradeResult` à chaque intention BuyTile et à chaque achat sur la dalle [UpgradesScreen]. Prix × F(A) avec `Prestige.ascend` (le A de l'instantané) ; identiques à `tileCost` tant qu'aucun A ≥ 1 n'existe Jelly Ascend coupée.
- **A2-19. Grand Splorch de la v1.3 sur un profil v2 (avant `Prestige.apply`, étape 3)** : dans le même bloc, `bestR = max(bestR, r)` (note de l'étape 1) et Tapis Étoilé, Gants, École (`kept = false`) remis à zéro avec le Tapis ; sans cela `Invariants` v2 signalait `bestR` et `tiles.star > starCap(r)`, et les niveaux de la boucle passaient gratuitement à la suivante. Monuments, Enclos, Lit gardés.
- **A2-20. Attributs du ranch (`Types.RanchAttributesV2`)** posés sur le modèle `Ranches/<k>` (répliqué à tous ; ligne à ajouter au tableau du §3 par le contrat) par `RanchService.setV2Attributes(player, attrs, clear?)` : noms et sortes du contrat seulement (NaN, inf, mauvais type, chaîne > 64, nom inconnu refusés), valeurs gardées jusqu'à l'attribution du ranch, seules les valeurs changées posées, tout effacé quand le ranch est libéré. RanchService calcule `BestR` [RecordR], `Monuments` [Monuments], `TapisTier` / `GloveTier` / `ApronTier` [RanchTiers] au chargement et sur `UpgradeBought`, `Splorched`, `PrestigeApplied`, `RecordReached` (un interrupteur coupé efface les siens) ; `SplorchReady` [RecordR] vient d'EconomyService (vérifié toutes les secondes) ; `Ascend`, `AscendReady`, `PetitSplorchAt` (SplorchService, étape 3), `DecoPerso`, `HaloOn` (A4) par leur propriétaire. Tout coupé : aucun attribut, jamais.
- **A2-21. Place d'enclos offerte (N7)** : écrite par `Prestige.apply` (A1) ; `RanchService.offeredPlace(player, fullPen, n)` reconstruit le ranch et, enclos déjà plein, envoie « Enclos déjà plein : +n Confettis » (`confetti.fullPen`, clé du serveur) ; à appeler par SplorchService après `Prestige.apply` et `addConfetti(…, "fullPen")` (étape 3).
- **A2-22. Specs** : `EconomyService_upgrades` (nouveau, 22 cas), `RanchService_v2` (nouveau, 7), `RedTeam_Upgrade` (nouveau, 10 : rafales, Fuzz, modes, ids presque connus, `-0`, ligne verrouillée × 100, montants énormes, vrai Grand Splorch, deux serveurs sur un magasin partagé, 16 robots × 4 000 actions au hasard à graine fixe — achats justes ou périmés, gains, Grands Splorch, dalles, interrupteurs basculés en direct : débit toujours égal à `UpgradeMath.bulk`, une réponse par achat, `Invariants.profile` vide toutes les 250 actions), `Remotes_Ranch` (+ 3), `Contract_v2`, `Contract_game` ; mutations vérifiées : sans le refus des modes, 2 cas rouges ; sans le refus périmé, 2 ; sans la sonde du spectacle, 1. Aucun défaut du jeu de base trouvé ; aucune valeur de `Balance` changée ; `EconomyPacing` forme check.sh **57 réussis, 0 échoué** (58 s).
- **A2-23. INT-V2-INTENTS pour `JellyAscend`** (lot A2, étape 3 ; fichiers du contrat permis par la tâche) : la ligne passe de `Config/IntentsV2` à `Config/Intents` (débit 1 / 5 s, `activity`, `confirm: bool`), handler `SplorchService` ; `Contract_v2` compte 3 intentions v2.0 au lieu de 4 et vérifie la ligne dans `Config/Intents` ; `Contract_game` l'ajoute aux intentions de jeu (`activity`) ; `Remotes_Chase` l'attaque (interrupteur coupé, puis ouvert avec un attaquant prêt) ; `Fuzz` la prend tout seul. La chaîne `"JellyAscend"` est désormais permise côté serveur (`EconomyService` : empreinte des interrupteurs de la configuration).
- **A2-24. Progression v2.0 en vigueur = `EconomyService.prestigeV2(player)`** : profil v2, `RecordR` ouvert et configuration acceptée (`Prestige.validateConfig`). Raison : `Prestige.apply` fait des choses de la v2.0 sans lire d'interrupteur (décorations gardées dès le Record R 8, places offertes, cadeau du Splorch, Record R) et `RecordR` est l'interrupteur du Record R (N1) qu'il implémente. Sinon le Grand Splorch reste `applySplorch` au bit près ; le filet de l'étape 2 (A2-19 : `bestR ≥ r`, Tapis Étoilé, Gants, École à zéro) reste pour un profil v2 dont `RecordR` est coupé (invariant v2). Petit Splorch = `prestigeV2` + `PetitSplorch` ; Jelly Ascend = `prestigeV2` + `JellyAscend`. Tout coupé (et `SchemaV2` coupé) : jeu de base inchangé (specs du jeu de base vertes telles quelles).
- **A2-25. `EconomyService.applyPrestige(player, kind)`** (API du §27.7) : règlement, `Prestige.apply` (seul écrivain des champs gardés et remis à zéro), cadeau du Splorch dans le Pot (`UpgradeMath.giftCoins` : « une pluie de pièces dorées tombe dans le Pot », GDD §4.15 ; le modèle d'économie crédite le même montant en pièces), clés marquées (sauf `squishies` : les tailles sont répliquées entrée par entrée par `SquishyService.resetSizes`, appelé juste après), ranch reconstruit, contexte rafraîchi. Les gains du rapport sont versés par SplorchService dans le même bloc : Confettis par `addConfetti`, une source par part (`splorch`, `record` = prime au-delà du Record R 20, `petit`, `ascend`, `skipped` = Tremplin, `regain`, `fullPen`) ; Fame du Grand Splorch (+ 5) dans `CapsV2.fameSplorch` (50 par jour), Ascension (+ 20) hors plafond. `consumeCap` lit `Balance.CapsV2` dans un profil v2 ; `capsToday` remet aussi ces compteurs à zéro au changement de jour UTC (« remis à zéro avec les autres », Data/Schema : rien ne le faisait encore).
- **A2-26. Petit Splorch [PetitSplorch]** : décidé à l'intention `GrandSplorch` (mêmes conditions d'entrée) quand `Prestige.nextKind` vaut `"petit"` ; hors file, appliqué tout de suite d'un bloc ; `Celebrate("petitSplorch")` au joueur seul (`Types.CelebratePetitSplorch`), attribut `PetitSplorchAt` (effacé quand l'interrupteur est coupé) ; ni bannière, ni cadeaux aux autres, ni Fame ; retour au record : + 10 (`regain`), `Celebrate("regainDone", { bestR, confetti })`, `memoryR` (écrit par `Prestige.apply`). `Splorched(héros, r, 0)` reste émis (jauge, objectifs et statistiques des Grands Splorch : le Petit Splorch est un Grand Splorch hors file, GDD §1 ; le modèle d'économie compte aussi ses points de jauge). `PetitSplorch` coupé : la renaissance qui ne bat pas le record passe par la file (1 Confetti, aucune Fame).
- **A2-27. Grand Splorch v2.0** : préparation revérifiée au départ du spectacle (`Prestige.splorchReady`) : le plus gros vendu ou relâché pendant l'attente (seul le flyer est protégé) rendrait `Prestige.apply` sans effet ; la place est rendue avant tout spectacle, rien n'est remis à zéro (compteur `SplorchNotReadyAtStart`) ; les conditions d'entrée (ranch, portage, fuite) ne sont toujours pas revérifiées (GDD §4.15). Une bannière « GRAND SPLORCH » par joueur au plus toutes les `SplorchV2.BannerGap` s (mémoire par userId sur le serveur ; la « petite ligne » du GDD est au client, B3). Attente changée : `RedTeam_Upgrade` › « pendant le spectacle de son Grand Splorch » rend le héros prêt (plus gros ≥ objectif) avant le départ forcé par le signal ; aucune assertion retirée.
- **A2-28. Jelly Ascend [JellyAscend]** : `JellyAscend(confirm)` : `confirm == true`, `Prestige.ascendReady` et les conditions d'entrée vérifiés une fois ; configuration refusée → `upgrades.refused.busy` ; session en fin → rien ; un seul prestige par joueur (`SplorchService.canPrestige` ; Grand Splorch en file ou en spectacle → `ascend.queued` « Ton Grand Splorch passe d'abord ! » ; Ascension déjà en file ou en spectacle → rien, idempotent ; Grand Splorch pendant une Ascension en file → `feedback.waitingSplorch`). Même file qu'EventService (sorte « splorch » : EventService est au lot A4, note croisée) ; flyer = Meilleur Ami n° 1 (puis 2, 3, sinon le plus gros) mis en attente (aucun squishy à la clôture pendant l'attente) ; au départ, interrupteur, configuration, condition et session revérifiés (sinon place rendue, rien remis à zéro) ; `Celebrate("ascend")` à tous (`Types.CelebrateAscend`, taille du Meilleur Ami copiée au départ) ; application à `Ascend.BurstAt` (4,0 s), versements, sauvegarde, Pluie d'étoiles (`Celebrate("giftRain")` du jeu de base dont `heroId` est le héros du `Celebrate("ascend")` en cours : `StarRainSeconds` de revenu dans `CapsV2.starRain` = 3 par jour, puis rien ; un bébé de l'espèce du Meilleur Ami dans `Caps.splorchGifts`), `Banner("ascend", { ascend })`, `PrestigeApplied`, attributs `Ascend` / `AscendReady` (posés toutes les secondes, effacés interrupteur coupé). Aucun Feedback à l'entrée (aucune clé « Ta Jelly Ascend passe dans … » : le HUD lit la file d'EventState). État ouvert avant l'application nommé « spectacle » (délai 10 s ≥ 4,0 s) : `StateTimeouts` n'a pas d'état « ascendBurst » (fichier d'A1, note). API : `ascend`, `petitSplorch`, `canPrestige`, `queuedKind`, `counters`.
- **A2-29. Idempotence et données** : aucun yield entre `Prestige.apply` et le dernier versement ; la sauvegarde immédiate est lancée APRÈS les versements. Défaut trouvé dans le code neuf par `SplorchService_ascend` (spec rouge : sauvegarde immédiate écrite avec A = 1 mais 0 Confetti, l'instantané de `DataService.save` étant pris avant son premier yield, donc avant les versements qui suivaient le `task.spawn`) ; corrigé pour les trois prestiges, spec verte. Rien n'est appliqué si le joueur est parti ou si la session se termine (départ, BindToClose : `DataService.isClosing`) : l'Ascension (ou le Grand Splorch v2.0) reste à faire à la session suivante, jamais à moitié ; sauvegarde en échec : le magasin garde le profil d'avant, entier, et la suivante écrit tout le prestige une fois. Sonde « occupé » d'EconomyService élargie au spectacle de l'Ascension et à l'animation du Petit Splorch (`SplorchV2.PetitShow.Duration`).
- **A2-30. Specs de l'étape 3** : `SplorchService_ascend` (nouveau, 19 cas : interrupteurs coupés, profil v1, RecordR coupé ; Ascension complète ; Tremplin ; Pluie d'étoiles au plafond ; chaque refus ; un seul prestige par joueur ; deux fois dans la même image et rejouée ; départs à 3,9 et 4,1 s puis retour ; sauvegarde en échec ; BindToClose avec 16 joueurs en file ; Petit Splorch, retour au record, PetitSplorch coupé ; Grand Splorch v2.0, Fame 50 / jour et prime de record, plus gros vendu pendant l'attente ; sonde « occupé »), `Soak_queue` (nouveau : 16 robots, 0,5 h en ≈ 1 min ; attente médiane du 1er Grand Splorch d'un nouveau 0,1 s, max 128 s, limite 40 s ; 298 Petits Splorch hors file ; Ascension dans la file une fois ; file équitable ; Invariants, états, ressources stables, BindToClose, zéro trace), `Remotes_Chase` (+ 3 : JellyAscend coupée, ouverte avec un attaquant prêt, rafale de 1 000), `Contract_v2`, `Contract_game`, `RedTeam_Upgrade` (A2-27). Mutations vérifiées : sans la garde de fermeture à l'application, 1 cas rouge ; sans la revérification au départ, 1 ; sans la sonde du Petit Splorch, 1 ; Petit Splorch remis dans la file, `Soak_queue` rouge ; sauvegarde lancée avant les versements, 2 (A2-29). Aucune valeur de `Balance` changée ; `EconomyPacing` forme check.sh **57 réussis, 0 échoué** (56 s) ; `Soak` du jeu de base vert tel quel (0,5 h, 2,13 ms par tick).
- **A2-31. Relecture indépendante du lot A2** (5 novembre 2026, spec `Review_A2` nouvelle, rapport `scratchpad/v2/revue-A2.md`) : 4 défauts, chacun écrit rouge d'abord sur le code relu (5feb940), vert après (A2-32 à A2-35) ; aucune valeur de `Config/Balance` changée ; fichiers du lot seulement (`EconomyService`, `SplorchService`, `RanchService`) et docs/04.
- **A2-32. `UpgradeBought` sur le chemin de la v1.3 de `BuyTile`** (écran coupé) : §27.4 le veut « en plus pour tout achat, dalles comprises » ; il ne partait que de `buyUpgrade`. Effet : écran coupé (LiveOps), paliers du ranch [RanchTiers] figés jusqu'au prestige suivant, et le Carnet d'A4 ne compterait pas l'achat. Signal interne seul : interrupteurs coupés, son seul abonné (`RanchService.refreshV2`) ne pose ni n'envoie rien (jeu de base au bit près). `Review_A2` › « UpgradeBought pour tout achat ».
- **A2-33. Attributs calculés par RanchService revus quand un interrupteur change en direct** (`BestR` [RecordR], `Monuments` [Monuments], `TapisTier`, `GloveTier`, `ApronTier` [RanchTiers], règle 4 du §27.3) : empreinte de ces 3 interrupteurs lue par `RanchService.step`, `refreshV2` de chaque joueur chargé quand elle change. Avant : posés ou effacés seulement au prochain achat ou prestige (`RanchService_v2` appelait `refreshV2` à la main, attente inchangée). Tout coupé : empreinte 0, rien de fait.
- **A2-34. Record absolu (r = `MaxR` = 400)** : `SplorchReady` faux pour un profil v2 au Record absolu (le Grand Splorch y est refusé, « Record absolu ! ») ; refus étendu à **tout** profil v2, progression v2.0 coupée comprise (le Grand Splorch de la v1.3 y passait r à 401 : invariant v2 `R ≤ MaxR` cassé, puis « réparé » à 400 au chargement suivant, un Grand Splorch rejoué). Profil v1 : inchangé (pas de `MaxR` en v1.3).
- **A2-35. Décorations dorées (`decorBuilds`, §27.2 « EconomyService, au Grand Splorch », §27.14) : jamais comptées.** Règle posée (GDD §11.5 « construite dans 10 boucles ») : `EconomyService.applyPrestige`, à chaque prestige v2.0 appliqué (Grand, Petit, Ascension : chacun finit une boucle), + 1 pour chaque décoration construite à la fin de la boucle (n° k ≤ `report.decorBefore`), bornée à 10, dans le même bloc (clé marquée, sauvegardée avec le prestige) ; rien quand la progression v2.0 est coupée (Grand Splorch de la v1.3). La migration (1 par décoration construite, critique m7) compte les boucles d'avant la v2. Reste au contrat et à B4 : la réplication **publique** (« public (dorées) » du §27.2, pour les ranchs voisins) ; aujourd'hui seul le propriétaire la reçoit (DataPatch).
- **A2-36. Vérifié sain par la relecture** (cas de `Review_A2` verts du premier coup, gardés) : `Formulas.splorchTarget` = `Prestige.target` pour r = 0 … 400 (entrée dans la file, `SplorchReady` et `Prestige.apply` jugés sur le même objectif) ; plus gros vendu PENDANT son propre spectacle, avant l'éclatement : rien appliqué ni donné (filet `PrestigeRefused`), attente levée, Grand Splorch suivant normal ; Jelly Ascend avec le Meilleur Ami n° 1 au Dodo ; robot de 8 joueurs × 1 500 actions à graine fixe (achats, Grands et Petits Splorch, Ascensions, départs et retours, 10 interrupteurs changés en direct) : Confettis conservés au Confetti près (registre de `ConfettiChanged` = profil, aussi après chaque retour), Record R et A jamais en baisse, `Invariants.profile` vide après chaque action, zéro trace.
- **A2-37. Textes du contrat alignés sur le serveur** (restes des étapes 2 et 3, docs seulement) : §3 (attributs `Ranches/<k>` de `Types.RanchAttributesV2`), §10.2 (clé dérivée `upgradeSnapshot` de `DataSnapshot` / `DataPatch`), §27.5 (`UpgradeResult` toujours, refus périmé muet dedans). Le commentaire de `Types.UpgradeResultPayload` (« sauf refus périmé muet ») reste au contrat : fichier du contrat, non ouvert à cette tâche.

**État au 3 novembre 2026** : code du contrat v2.0 en place (§27.0), tous les interrupteurs coupés ; `Contract_v2.spec` (25 cas, dont la sauvegarde-témoin `v2.json`), `Contract_upgrades.spec` (13 cas), `Contract_unlocks.spec` (10 cas) et `Contract_glyphs.spec` (7 cas, dont les formateurs) verts ; jeu de base inchangé (les specs du jeu de base passent telles quelles, `Contract_game` seulement étendu aux remotes v2.0).

### 27.13 Changements de comportement du jeu de base (N1-N25) : où, qui, quelles specs

Reprise ligne par ligne du §0 du `contract-changes.md` final (après la critique : N2, N3, N10 changées, N16-N25 ajoutées), pour que ce chapitre se suffise. Chaque ligne change une valeur ou un comportement **vérifié par une spec du jeu de base** : rien ne change tant que son interrupteur est coupé (§27.3, règle 1) ; le lot qui l'**ouvre** (étape I, ou le paquet lui-même s'il n'a pas d'interrupteur) met à jour la spec dans le même lot, avec la référence au GDD et la raison au journal §27.12 (« une attente qui change avec le GDD est mise à jour avec lui », jamais un test retiré).

| # | Ce qui change | GDD | Paquet | Interrupteur | Specs du jeu de base concernées |
|---|---|---|---|---|---|
| N1 | `R` du profil = r de la boucle ; tout ce qui est « débloqué » lit `bestR` (Record R) : `Formulas.vatLevel`, `Odds.unlockedFamilies`, `Balance.Splorch.BestFriendSlotsAt`, `MinR` du Lit douillet, titres, `Splorch.Unlocks`, places de Meilleur Ami | §4.27 | A1 + A2 | `RecordR` | `Formulas`, `Odds`, `Props_Formulas`, `Props_Odds`, `SquishyService*`, `EconomyService*`, `SplorchService*`, `Panels_SplorchPreview` (B3) |
| N2 | Croissance `× 3^A × Souvenir(bestR − R)` : 3 si l'écart ≥ 3, puis 2, 1,5, et 1,25 sur la 1re boucle record après une Ascension (`Ascend.RegainMult`, `RegainTaper`) ; `niveauTapis` jusqu'à 20 | §4.3, §4.27 | A1 | `JellyAscend` (+ `StarMat`) | `Formulas`, `Props_Formulas`, `EconomyPacing` |
| N3 | Prix de la boucle `× F(A)` = produit de `Ascend.PriceByA = {0.5, 0.5, 0.5, 0.5, 0.32}` (le dernier facteur pour toutes les suivantes) ; table du Tapis Étoilé ; Gants 40 niveaux | §4.6 | A1 | `JellyAscend`, `StarMat`, `Gloves` | `Formulas` (`tileCost`), `Contract_game` (témoin des prix) |
| N4 | Revenu `× (1 + 0,01 × monuments)`, multiplicateur à part | §4.3 | A1 | `Monuments` | `Formulas`, `Props_Formulas` |
| N5 | Pression `× (1 + 0,025 × gants)` ; série jusqu'à `5 + superSérie` | §4.7 | A1 + A2 | `Gloves`, `Workshop` | `Formulas` (`pressReward`), `PressTiming`, `SquishyService` |
| N6 | Hors ligne : +1 h par Sac de nuit (16 h au plus) ; Pot 25 / 30 / 35 % ; **arrêt à 120 s de croissance maximale** avant l'objectif (`OfflineV2.MinPlaySeconds`, remplace `Offline.StopAt`, INT-V2-BALANCE) | §4.19 | A1 + A2 (`DataService` : rebase) | `Workshop` (Sac, Pot) ; arrêt à 120 s : `RecordR` | `Formulas` (`offlineSeconds`, `offlineGrowth`, `offlinePot`), `DataService` (rebase), `EconomyPacing` |
| N7 | Grand Splorch : tuiles « Croissance ×2 », déblocage, « +n Confettis » ; « Dépenser d'abord » ouvre l'écran Améliorations ; cadeau du Splorch ; places offertes ; décorations gardées ; bannière 1 / 3 min par joueur ; Fame 50 / jour ; Petit Splorch hors file | §4.15, §4.27 | A2 + B3 | `Confetti`, `Workshop`, `UpgradesScreen`, `PetitSplorch` | `SplorchService*`, `Panels_SplorchPreview`, `Banners`, `Boot`, `Soak` |
| N8 | Panneau Ranch : onglet *Dalles* retiré (l'écran Améliorations le remplace), onglet *Mon style* | §10.3 | B3 | `UpgradesScreen` (*Dalles*), `RanchSkins` (*Mon style*) | `Panels_Ranch`, `Layout_panels`, `Console_panels`, `ClientReplay` |
| N9 | Rail du menu : 8 boutons de 340 × 80, écart 16, icône 48 (v1.3 : 7 × 96, écart 12, icône 56) ; entrée **Améliorations** ; bouton de renaissance au nom de celle qui est prête | §10.2, §10.7.2 | B2 | `UpgradesScreen` | `HUD`, `Layout_hud`, `Console_hud`, `ClientReplay` ; `Contract_upgrades` › rail (fait) |
| N10 | **Politique de texte** : `TextSize` fixe + `UITextSizeConstraint.MaxTextSize`, plus de `TextScaled` (13 usages dans 7 fichiers : `LightingController`, `VFXController`, `WorldText`, `Glyph`, `Panels/Widgets`, `Toast`, `Hud/Util`) ; `UI/Text` **mesure le facteur réel** du moteur (étiquette témoin cachée, `TextBounds`, au démarrage et à chaque changement de `GuiService.PreferredTextSize`) et **compense** les libellés si la contrainte ne les borne pas ; `TextFit_all` : phrases au pire cas × 1,5, libellés à leur taille dessinée ; panneau **TextProbe** (6 étiquettes témoins, photographiées sur la PS5) | §10.1, §10.8 r. 9 | B1 (puis B4 pour `LightingController`, B5 pour `VFXController`) | aucun : politique du jeu de base, sans changement voulu à Medium, prouvée avant fusion | `TextFit_all` (outil d'écrans), `Text_policy` (nouveau : contrainte respectée **et** ignorée par le moteur), `Layout_*`, `Console_*`, `WorldText`, `Widgets_review` |
| N11 | Focus **dessiné à l'intérieur**, sans grossissement pour lignes, cartes, rail | §10.1, §10.8 r. 14 | B1 (`FocusGuard`) + B2 | aucun (jeu de base) | `FocusGuard`, `Console_*`, `Layout_*` |
| N12 | Éclairage : `LightingStyle = Soft`, `PrioritizeLightingQuality = false` au lieu de `Technology = ShadowMap` ; Directeur d'ambiance seul écrivain de `Lighting` | §11.3 | B4 (INT-V2-LIGHT) | `Ambience` | `default.project.json` (contrat), `LightingController`, `scripts/verify-place.luau` |
| N13 | Prairie des copains déplacée (r ≈ 120-150 au nord) ; bande des Monuments r ≈ 260-300 ; Observatoire ; kiosque de Big Plop | §11.1, §11.2 | B4 | `RanchTiers`, `Monuments`, `Workshop` (kiosque) | `WorldLayout`, `Props_WorldLayout`, `WorldBuild` |
| N14 | `InputGuard` à l'ouverture de **tout** panneau (relâchement de ✕ vu + 0,3 s) ; achats sur `InputBegan` capté | §10.6, §10.7.9 | B1 (`InputController`) + B2 (`PanelController`) | aucun (sécurité d'entrée du jeu de base) | `InputController`, `PanelController*`, `Console_panels` |
| N15 | `Schema.VERSION = 2` et étape `migrate(v1 → v2)` | §12.6 | P0 (fait) + A2 + I | `SchemaV2` (figé) | `Schema`, `Contract`, `Contract_game`, `DataChaos`, fixtures |
| N16 | Confettis du Grand Splorch : `3 + min(r, CapR = 20)` ; Grand Splorch sauté payé **seulement** pour ceux du Tremplin ; **+10** au retour au record après une Ascension (`RegainBonus`, `regainBonusA`) | §4.26 | A1 (`Prestige.confettiGain`) + A2 | `Confetti`, `JellyAscend` | `EconomyPacing` ; valeurs : `Contract_upgrades` (fait) |
| N17 | Décorations gardées **12 au plus** (« Déco qui reste » à 2 niveaux) | §4.6, §4.26 | A1 (`Prestige.keptDecor`) | `Workshop` | `Contract_upgrades` (fait : `SplorchV2.KeptDecorMax = 12`) ; `Props_Prestige` |
| N18 | HUD : pastille Fame et amis **hors du HUD calme** (3 s quand elle change) ; puce « Prochain achat » visible avec la carte de la cible, cible recalculée après tout prestige ; puce Menu « MENU » qui ne change jamais ; puce d'action spéciale « JELLY ASCEND ! » et « PETIT SPLORCH ! » (maintien de 1,5 s sur la puce, sans aperçu après le premier de la remontée) ; suivi « Retour au record » | §10.2 | B2 (+ A1 `UpgradeAdvisor`) | `UpgradesScreen`, `JellyAscend`, `PetitSplorch` | `HUD`, `Layout_hud`, `Console_hud`, `ClientReplay` ; rectangles réels : `Contract_upgrades` › HUD v2.0 (fait, `Layout.HudV2.Rects`) |
| N19 | **Tout achat de l'écran Améliorations, ×1 compris, par un maintien de 0,6 s** | §10.7.8 | B2 | `UpgradesScreen` | `Upgrades_InputGuard`, `Console_upgrades` (nouveaux) |
| N20 | États et cadenas en **chiffres arabes** (« Record 6 », « Boucle 7 ») ; `Format.roman` seulement pour le décor | §10.7.6 | B1 (`Format`) + B2 | `UpgradesScreen` | `Format`, `UpgradeCard` ; textes : `upgrades.state.locked` « Record {r} » (fait) |
| N21 | `BuyTile("snack")` achète aussi les niveaux 13-20 (Tapis Étoilé) quand ils sont ouverts dans la boucle | §4.6, §12.7 | A2 | `StarMat` | `EconomyService*`, `RanchService` |
| N22 | Mode photo : personnage figé **et visible** des autres (aucun masquage) | §7.5 | A4 | `PhotoMode` | `CommunityService` (`CommunityService_v2`) |
| N23 | Sieste des Plopettes après 5 min **sans intention acceptée** (pression, achat, capture, menu) ; un stick calé ne compte pas | §4.28 | A3 (`Activity.lastIntent`, §27.7) | `Helpers` | `HelperService`, `RedTeam_Helpers` ; `Activity` du jeu de base inchangé (jauge, MEGA) |
| N24 | Carte « Prêt à monter ? » : « Plus tard » à gauche, « Oui » à droite, **focus sur « Oui »** (garde 0,6 s et relâchement de ✕ gardés) ; carte Conseillé « Jelly Ascend » quand rien n'est payable depuis 5 min (`Ascend.DeclineCardAfter`) | §4.27, §10.3, §10.7.4 | B3 + A1 (`UpgradeAdvisor`) | `JellyAscend` | `Panels_SplorchPreview`, `UpgradeAdvisor`, `Upgrades_InputGuard` |
| N25 | Décorations : l'écran montre l'**effet réel** « Revenu total +1,2 % » (`UpgradeMath.effect`, 0,05 ÷ `A_bonus`), jamais « +5 % » ; la formule du revenu ne change pas | §4.3, §10.7.7 | A1 (`UpgradeMath`) + B2 | `UpgradesScreen` | `UpgradeMath`, `Format` ; texte `upgrades.effect.incomeTotal` (fait) |

**Valeurs de `Balance` refaites après la critique** (toutes dans les tables v2.0 du §27.0, témoins de `Contract_upgrades`, réglées ensuite par A1 seul avec la porte §27.9) : `Ascend.PriceByA = {0.5, 0.5, 0.5, 0.5, 0.32}` (B1 de la critique), `Ascend.RegainMult = 3` et `RegainTaper = {2, 1.5, 1.25}` (M6), `Ascend.DeclineCardAfter = 300` (M1), `Confetti.CapR = 20`, `PerSkipped = 1` (Tremplin seulement), `RegainBonus = 10` (M4, M5), `SplorchV2.KeptDecorMax = 12` (M3), `Upgrades.HoldSeconds = 0.6` pour tout achat (m16), `Helpers.NapAfter = 300` sans intention acceptée (m17), `OfflineV2.MinPlaySeconds = 120` (N6), `CapsV2.fameSplorch = 50`, `SplorchV2.BannerGap = 180` ; **invariant de stabilité** (M13) `(Splorch.BeyondMult / 2)^Ascend.ReqStep ≥ 0,95 × Ascend.GrowthMult` et `objectif(r + 1) / objectif(r) ≥ 2,5` pour tout r ≥ 16 (`Contract_upgrades` sur les valeurs de départ ; `Prestige.validateConfig` au chargement, A1, refus compté par Diagnostics). Specs nouvelles nées de la critique : `Text_policy` (B1, N10), `Soak_queue` (A2 puis I : 16 robots dont 8 vétérans en Petits Splorch, `queueWaitNewcomer` ≤ 40 s), `Props_Prestige` › invariant (A1), `UpgradeAdvisor` › « après `Prestige.apply`, `next` ne désigne jamais un niveau déjà possédé ni inexistant » (A1), `Panels_SplorchPreview` › « aucun bouton Dépenser d'abord sans ligne gardée payable » (B3), `Console_upgrades_nav` › lignes en lecture seule sélectionnables, ✕ = `Bump` (B2).

### 27.14 Services, Diagnostics, analytique, monde et HUD v2.0 (reprise du `contract-changes.md` §2.3, §5, §6, §8)

**Services serveur** (chacun derrière ses interrupteurs ; API exactes au §27.7 quand elles traversent deux paquets) :

| Service | Paquet | Ajouts v2.0 |
|---|---|---|
| `EconomyService` | A2 | `buyUpgrade` pour toutes les familles (pièces et Confettis), même chemin que `BuyTile` ; instantané versionné ; `addConfetti` (seul point d'entrée des gains) ; cadeau du Splorch ; `decorBuilds` ; Pot de nuit et Aimant (rayon) ; revenu avec Monuments ; pression avec Gants et Super Série |
| `SplorchService` | A2 | `Prestige.apply` au Grand Splorch ; Petit Splorch hors file (`PetitSplorchAt`, 1 Confetti, aucun cadeau aux autres ; aperçu au premier de la remontée seulement ; « Dépenser d'abord » seulement si une ligne gardée est payable) ; retour au record (+10, `regainBonusA`) ; étapes du record (`Celebrate("recordStep")`) ; Jelly Ascend dans la file (maintien 3 s et confirmation côté client ; application à `Ascend.BurstAt` ; Pluie d'étoiles) ; un prestige par joueur dans la file ; bannière 1 / 3 min ; Fame 50 / jour ; places offertes ; carte « Nouveau » (`RecordReached`) |
| `HelperService` (nouveau) | A3 | tick de 10 Hz appelé par ChaseService ; Plopettes du Record R + Plume ; cible et `tPress` choisis par le serveur, revérifiés à `tPress` ; règle des 12 studs ; sieste après 5 min sans intention acceptée (`Activity.lastIntent`) ; pause pendant un prestige et pendant le Rush à la clôture du propriétaire ; récompense `pressReward(…, PERFECT = non, série = 0) × Gants` ; jamais de jauge, d'objectif ni de classement ; < 0,5 ms par tick à 16 × 6 |
| `QuestService` | A4 | piste de la semaine (2 points par objectif, 5 par Défi, paliers tout seuls, première période jusqu'au 2e lundi), 3 Défis par semaine (`QuestRules.challengeFeasible`), Carnet (`stats.upgradesBought`), maîtrise d'espèce (+25 Confettis par `addConfetti`), jalons géants, `season.frostDays`, `unlocksSeen`, carte « Bienvenue dans la v2 ! » (`onboarding.welcomeV2Pending`) |
| `CommunityService` | A4 | habillages (`cosmetics.theme`, décision C2), `decoPerso`, cœurs (privés), `haloOn`, mode photo (personnage visible, N22) |
| `RanchService` | A2 | attributs `Types.RanchAttributesV2` ; kiosque de Big Plop (invite « Atelier ») |
| `EventService` | A4 | météo **visuelle** (fenêtres :08-:13 et :38-:43, suspendue pendant la Jelly Moon), place en fête (points de serveur), Pluie d'étoiles |
| `ChaseService` | A3 (note) | appelle `HelperService.step(now)` dans son tick ; pause des Plopettes pendant le Rush à la clôture du propriétaire ; aucune autre règle |
| `DataService` | A2 | `Schema.VERSION = 2` (à l'étape I), migration ; rebase hors ligne avec `MinPlaySeconds`, Sac et Pot de nuit (via `Formulas`) ; refus poli d'un profil plus récent (§27.2) |
| `LeaderboardService` | A4 | Livre des records (lecture seule, profil du joueur) ; aucun nouveau classement |
| `DiagnosticsService` | A4 | compteurs `UpgradeTimeout`, `UpgradeStale`, `StyleFallback` (`UIShadow` ou dégradé radial absents), `VisualBudgetExceeded`, `TextScaleMeasured` (facteurs mesurés par `UI/Text`), `ConfigRefused` (invariant de stabilité), `ProfileRepaired` ; côté serveur du panneau **TextProbe** (B1 dessine le panneau) |

**Analytique v2.0** (A4, seul éditeur de `Server/Util/Analytics`, note INT-ANALYTICS ; les autres paquets appellent l'API existante) : `Upgrade_<famille>`, `UpgradeMode`, `WorkshopBuy_<ligne>`, `ConfettiEarned(source, n)`, `UpgradeTimeout`, `UpgradeStale`, `NextGoalGap` (histogramme serveur), `HelperCoinsShare`, `RanchTierReached`, `AscendPreview`, `AscendDone(A, r, jours)`, `AscendDeclined` (M1), `TextScaleMeasured` (B3 de la critique), `PetitSplorch`, `WeeklyTrackTier` ; `LogEconomyEvent` : sources `Helper`, `SplorchGift`, `StarRain` (pièces) ; nouvelle monnaie `Confetti` (sources et puits). Budget inchangé : 10 requêtes par joueur et par minute ; les événements nouveaux sont cumulés par tranche de 5 min (`Analytics_v2.spec`).

**Monde v2.0** (B4, `Logic/WorldLayout`, N13) : 10 emplacements de Monuments par ranch (Z = 88 / 116, X = −36 … +36), Prairie des copains (r ≈ 135 au nord), Observatoire (r ≈ 340 au nord), kiosque de Big Plop (−30, 0, 24), maisonnette des Plopettes (Z = 60, X = −28 ; lue par A3 : `WorldLayout.helperHouse`), geyser (Z = 4-10, X = −24), 12 emplacements de Déco perso (8 petits, 4 grands), positions des paliers du ranch ; `Props_WorldLayout` : 16 ranchs, 6 studs entre les dalles, rien au-dessus de Y = 21 au centre.

**HUD v2.0** (B2, N9, N18 ; disposition dans `Config/Layout.HudV2`, vérifiée par `Contract_upgrades`) : le HUD calme montre au plus 8 éléments ; la pastille Fame et amis n'apparaît que 3 s quand elle change ; la puce Menu dit toujours « MENU » (△ + 40 px) ; le rail (jusqu'à 8 boutons de 340 × 80) remplace la puce Menu et cache la puce « Prochain achat » ; la puce d'action spéciale (bas centre, y 822-918) dit « JELLY ASCEND ! » quand l'Ascension est prête et qu'aucun Grand Splorch ne l'est, « PETIT SPLORCH ! » pendant une remontée (maintien de 1,5 s sur la puce) ; l'indicateur Souvenir de gelée prend la place du bouclier débutant (jamais les deux) ; le suivi d'objectif passe à « Retour au record » + « 4 / 15 » pendant une remontée ; le milieu de l'écran (x 560-1280, y 330-822) reste libre.

**Harnais** (B1) : facteurs de `PreferredTextSize` **photographiés sur la PS5** avec le panneau TextProbe (jamais « mesurés dans Studio ») ; en attendant, pire cas × 1,5 pour les phrases dans `TextMetrics` ; `UIShadow` et dégradé radial simulés (absents → repli à plat) ; compteur d'instances de `PlayerGui` par panneau (règle 20).
