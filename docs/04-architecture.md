# Comet Conga — Architecture technique (contrat d'implémentation)

> **Document 04.** Version 1.0 du 31 octobre 2026. Statut : **contrat figé** pour l'implémentation parallèle par 8 paquets.
> Sources : [`02-game-design-document.md`](02-game-design-document.md) (GDD, cité « GDD §x » ; le §12 est l'architecture de référence) et [`03-decision-du-jury.md`](03-decision-du-jury.md).
> Le code du contrat (configurations, types, remotes, schéma, horloge, bus de signaux, stubs) est **déjà dans le dépôt** et vérifié par `tests/specs/Contract.spec.luau` et `tests/specs/Clock.spec.luau`. En cas de doute, **le code du contrat fait foi**, puis ce document, puis le GDD.

## Sommaire

1. Objet et règles du contrat
2. Paquets et propriété des fichiers
3. Monde : dossiers, instances, attributs et tags
4. Temps : `Shared/Util/Clock`
5. Serveur : ordre d'initialisation, dépendances, crochets, cycle de vie des joueurs
6. Le tick de 10 Hz de `CongaService`
7. Signaux internes du serveur (`Server/Signals`)
8. Données sauvegardées (schéma v1) et propriétaires
9. Configuration (`Shared/Config`) et types (`Shared/Types`)
10. Réseau : remotes, charges utiles, `PathStream`, versions et recouvrement
11. Services serveur (API)
12. Modules partagés purs (API)
13. Client : ordre, propriétaires des remotes, API des contrôleurs et de l'interface
14. Localisation et sons
15. Tests et définition de « fini »
16. Décisions d'interprétation du GDD
17. Réglages d'économie
18. Modifications du socle faites par le contrat

---

## 1. Objet et règles du contrat

Ce document permet à **8 ingénieurs** d'implémenter Comet Conga **en parallèle**, sans se deviner et sans éditer les fichiers des autres. Chaque module à écrire existe déjà sous forme de **stub** : `Init()` / `Start()` ne font rien, les autres fonctions publiques lèvent `error("TODO(<paquet>): <Module>.<fonction>")`. Le jeu démarre donc déjà, serveur et client, sans erreur. Implémenter un module = remplacer les `error("TODO…")` par le comportement décrit ici, **sans changer les signatures**.

**Règles communes (toutes non négociables)**

1. `--!strict` en tête de chaque module de `src/` ; API publiques typées ; **commentaires en français, identifiants en anglais**.
2. `task.wait/spawn/delay/defer` uniquement (`wait`, `spawn`, `delay` font échouer le harnais).
3. **Autorité serveur** : le client n'envoie que des intentions. Chaque handler suit l'ordre : `RateLimit.allow` → types (`Validate`, NaN/±inf, entiers, longueurs, tables séquentielles bornées) → existence (clé de config) → état (profil chargé, personnage vivant, position) → règles métier → mutation atomique → réplication. Aucune valeur économique venant du client.
4. **Temps** : toujours `Shared/Util/Clock` (§4), jamais `os.time()`, `os.clock()`, `tick()` ni `workspace:GetServerTimeNow()` directement dans un service ou un contrôleur (exception : `RateLimit`, et les mesures purement techniques de durée de calcul).
5. **Données** : tous les nombres et contenus viennent de `src/shared/Config/*` ; aucun nombre du GDD en dur dans un service (les constantes de calendrier de `Clock` et les dimensions purement graphiques internes à une recette visuelle sont tolérées si elles sont nommées).
6. **Cycle de vie** : traiter les joueurs déjà présents au branchement de `PlayerAdded` ; nettoyer tout état par joueur à `PlayerRemoving` ; le personnage peut être `nil`, mort ou réapparaître ; `WaitForChild` côté client **toujours avec un délai**.
7. **Une seule connexion `Heartbeat` côté serveur** : celle de `CongaService` (tick). Les autres services serveur sont « stepés » par lui (§6) ou utilisent des signaux. Côté client, une connexion par image et par système au plus.
8. **Textes** : uniquement des clés de `Shared/Localization/Strings.luau`, en anglais **et** en français (§14).
9. **Visuels côté client uniquement** ; le serveur n'envoie que des événements compacts.
10. **Performance** : décor ancré, sans collision ; réserves d'instances ; budgets du GDD §12.8.
11. **Dépendances** : un module n'appelle directement que des modules initialisés **avant** lui (§5, §13.1). Vers les modules plus tardifs, il passe par les **signaux** (§7, §13.2) ou par un **crochet** que le module tardif enregistre (§5.3).
12. **Un seul propriétaire par clé de profil** (§8) : les autres lisent `DataService.get(player)` sans jamais muter, ou passent par l'API du propriétaire.

---

## 2. Paquets et propriété des fichiers

Chaque fichier appartient à **un seul** paquet. Un paquet ne crée et ne modifie que ses fichiers. Il peut **ajouter** des modules privés dans son dossier d'aide (colonne « dossier d'aide ») et des specs `tests/specs/<Nom>.spec.luau` à son nom. S'il a besoin d'un changement dans le fichier d'un autre paquet ou du contrat, il ne l'édite pas : il le signale dans ses **notes d'intégration**.

**Registres partagés** (exception) : `src/shared/Localization/Strings.luau`, `src/shared/Remotes.luau`, `src/shared/Config/Sounds.luau` et `src/shared/Types.luau`. Tout paquet peut y **ajouter** des entrées : relire le fichier juste avant chaque `Edit`, faire de **petites modifications ciblées**, ne jamais réécrire le fichier, ne jamais renommer ni supprimer une entrée existante. Pour `Strings.luau` : toujours la clé en anglais **et** en français (la spec du contrat vérifie la parité et les variables `{x}`).

| Paquet | Fichiers possédés (stubs à implémenter) | Dossier d'aide | Specs à écrire |
|---|---|---|---|
| **contrat** (architecte, figé) | `docs/04-architecture.md`, `default.project.json`, `src/shared/Types.luau`*, `src/shared/Remotes.luau`*, `src/shared/Localization/Strings.luau`*, `src/shared/Config/Sounds.luau`*, `src/shared/Config/{Nebbies,Zones,Events,Quests,Cosmetics,Settings,Monetization}.luau`, `src/shared/Config/Balance.luau` (structure), `src/shared/Util/Clock.luau`, `src/server/Data/Schema.luau`, `src/server/Signals.luau`, `src/server/Util/Notify.luau`, `src/client/Util/Prefs.luau`, `src/server/Main.server.luau`, `src/client/Main.client.luau` | — | `tests/specs/Contract.spec.luau`, `tests/specs/Clock.spec.luau`, `tests/fixtures/profiles/v0.json` |
| **logic** | `src/shared/Logic/Formulas.luau`, `SeededPath.luau`, `EventClock.luau`, `Hash.luau`, `WorldLayout.luau`, `SnipRules.luau` ; **extension** de `src/shared/Logic/Trail.luau` (§12.1, comportement existant inchangé) ; **valeurs** de `src/shared/Config/Balance.luau` (réglage §17 uniquement) | `tests/sim/` (simulation) | `Formulas`, `SeededPath`, `EventClock`, `Hash`, `WorldLayout`, `SnipRules`, `EconomyPacing` ; extension de `Trail.spec` |
| **world** | `src/shared/Render/NebbyBuilder.luau`, `src/server/Services/WorldService.luau`, `src/first/Loading.client.luau`, `src/client/Controllers/LightingController.luau` ; nouveaux fichiers de `src/server/World/` (`Build.luau` et `Lighting.luau` restent le socle, réutilisés) | `src/shared/Render/`, `src/server/World/` | `NebbyBuilder`, `WorldService`, `LightingController`, `Loading` (extension possible de `World.spec`) |
| **conga** | `src/server/Services/CongaService.luau`, `src/server/Services/SpawnService.luau`, `src/server/Util/MoveCheck.luau`, `src/shared/Logic/PathCodec.luau` | `src/server/Conga/` | `CongaService`, `SpawnService`, `MoveCheck`, `PathCodec` |
| **economy** | `src/server/Services/EconomyService.luau`, `AtlasService.luau`, `NestService.luau`, `ProductService.luau` | `src/server/Economy/` | `EconomyService`, `AtlasService`, `NestService`, `ProductService` |
| **events** | `src/server/Services/EventService.luau`, `QuestService.luau`, `CrewService.luau`, `LeaderboardService.luau`, `src/server/Data/Codes.luau`, `src/server/Data/Admins.luau` | `src/server/Events/` | `EventService`, `QuestService`, `CrewService`, `LeaderboardService` |
| **client-world** | `src/client/Controllers/WorldStateController.luau`, `CongaRenderer.luau`, `VFXController.luau` | `src/client/World/` | `WorldStateController`, `CongaRenderer`, `VFXController` |
| **client-hud** | `src/client/UI/HUD.luau`, `Minimap.luau`, `Banners.luau`, `ScreenFX.luau`, `src/client/Controllers/InputController.luau`, `OnboardingController.luau` | `src/client/UI/Hud/` | `HUD`, `Minimap`, `Banners`, `ScreenFX`, `InputController`, `OnboardingController` |
| **client-panels** | `src/client/Controllers/PanelController.luau`, `src/client/UI/Panels/{Upgrades,Supernova,Collection,Goals,Shop,Crew,Settings,ReturnScreen}.luau` | `src/client/UI/Panels/` (modules d'aide, ex. `Widgets.luau`) | `PanelController`, `Panels` |

\* registre partagé (ajouts ciblés autorisés à tous).

**Socle réutilisé, jamais réécrit** : `src/shared/{Net,Remotes}.luau`, `src/shared/Util/*`, `src/shared/Logic/Trail.luau` (hors extension logic), `src/shared/Localization/*`, `src/server/Services/{DataService,MonetizationService}.luau`, `src/server/Util/{RateLimit,Analytics}.luau`, `src/server/World/{Build,Lighting}.luau`, `src/client/UI/{Root,Theme,Create,Juice,Toast}.luau`, `src/client/Controllers/{StateController,AudioController,WorldFXController}.luau`, `src/client/Util/Prices.luau`, `tests/harness/*`. Les ajouts que le contrat y a faits sont listés au §18.

---

## 3. Monde : dossiers, instances, attributs et tags

### 3.1 Construit par le serveur (`WorldService`, paquet world)

```
workspace.Lumora (Folder)
  Island   (Model, ModelStreamingMode = Persistent)
    Ground, Glade, CraterFloor, CraterRim (Model), Cracks (Folder), Cliff (Model), Walls (Folder : 36 Parts invisibles, CanCollide)
  Beacon   (Model, Persistent, tag "Beacon")
    Base, Shaft, Top, Rings (Folder : 3 anneaux Néon tag "BeaconRing"), Star (Model),
    SkyBeam (Part porteuse : Attachment "Bottom" + "Top" à Y = 300, Beam "Beam"),
    Deposit (Cylinder Néon Ø 28, tag "BeaconDeposit", éteint hors Nuit de la Balise),
    Board (Part, stèle du tableau, r = 12, face au sud ; attributs posés par LeaderboardService)
  Nests    (Folder)
    Nest_01 … Nest_12 (Model, Persistent, tag "Nest")
      Platform, Gate (Model : PostL, PostR, Arch (Folder : 7 Parts Néon tag "NestArch")),
      Observatory (Model), BillboardAnchor (Part invisible à Y = 16),
      Spawn (SpawnLocation : Neutral, Duration 0, Transparency 1, CanCollide false),
      Perches (Folder : Perch_01 … Perch_NN, créés/détruits par WorldService.setPerchCount)
  Paths    (Folder : pas japonais)
  Lanterns (Folder : bulbes tag "Lantern" ; PointLight seulement à r 90 et r 60)
  Decor    (Folder : Meadow, Glade (cristaux, tag "Crystal" pour les 6 éclairés), Crater)
  Islets   (Folder : îlots, tag "Float")
  Clouds   (Folder : Build.cloud, tag "Float")
```

Tags animés par `WorldFXController` (socle) : `Spin`, `Float`, `Pulse`. Tags lus par le client : `Nest`, `NestArch`, `Beacon`, `BeaconRing`, `BeaconDeposit`, `Lantern`, `Crystal`. Aucune créature (Nebbies, Gloomwisps, Comète) n'existe côté serveur.

### 3.2 Attributs des Nids (`Nest_XX`)

| Attribut | Type | Écrit par | Sens |
|---|---|---|---|
| `Slot` | number | WorldService (fixe) | 1-12 |
| `OwnerUserId` | number | NestService | 0 = Nid libre |
| `OwnerName` | string | NestService | `DisplayName` du propriétaire ("" si libre) |
| `Color` | Color3 | NestService | couleur du propriétaire (`Cosmetics.NestColors[slot]`) ou gris libre |
| `Supernovas` | number | NestService | R du propriétaire (constellation, étoiles du panneau) |
| `PerchCount` | number | NestService | perchoirs construits |
| `PerchData` | string | NestService | perchés dans l'ordre des perchoirs : `"code.étoiles,code.étoiles,…"` (code décimal 12 bits, étoiles 1-5), meilleur revenu d'abord |
| `Title` | string | NestService | id de titre équipé (`Cosmetics.Titles`), "" = aucun |
| `NestTheme` | string | NestService | id de thème (`Cosmetics.Themes`) |
| `LineStyle` | string | NestService | id de style de file (`Cosmetics.Styles`) |

### 3.3 Attributs des joueurs (`Player`)

| Attribut | Type | Écrit par | Sens |
|---|---|---|---|
| `Slot` | number | NestService | Nid du joueur (0 = aucun) |
| `Zen` | boolean | NestService | Mode Zen |
| `VIP` | boolean | NestService | badge « ★ VIP » (pass VIPStar) |
| `Title`, `LineStyle`, `NestTheme` | string | NestService | cosmétiques équipés |
| `Supernovas` | number | NestService | R (miroir de la clé de profil, pour les autres clients) |
| `Rookie` | boolean | QuestService | bouclier débutant actif |
| `CrewId` | number | CrewService | 0 = aucun |
| `DashReadyAt` | number | CongaService | `Clock.now()` de fin de recharge du Dash |
| `ImmuneUntil` | number | CongaService | immunité de coupe (étincelles roses) |
| `Unstable` | boolean | CongaService | icône « connexion instable » (MoveCheck) |
| `InputType` | number | CongaService | 1 tactile, 2 clavier-souris, 3 manette |
| `Admin` | boolean | EventService | UserId listé dans `Data/Admins` |
| `ClientReady` | boolean | **client** HUD (local, non répliqué) | fin de l'écran de chargement |

### 3.4 Dossiers et écrans côté client

- `workspace.ClientWorld` (Folder, créé par **CongaRenderer**) : `Lines`, `Wild`, `Perched`, `Wisps`, `Comet` ; `workspace.ClientWorld.VFX` (créé par **VFXController** s'il manque) ; `workspace.ClientSky` (créé par **LightingController** : rideaux, neige, météores, arcs).
- `ScreenGui` (via `UI/Root.screen`, `ResetOnSpawn = false`) : `HUD` (HUD), `Minimap` (Minimap), `Banners` (Banners), `ScreenFX` (ScreenFX), `Toasts` (socle Toast), `Panels` (PanelController), `PingWheel` (InputController), `Onboarding` (OnboardingController), `Loading` (Loading, dans `PlayerGui` directement).

---

## 4. Temps : `Shared/Util/Clock`

**Une seule source de temps** pour tout le jeu, serveur et client : `src/shared/Util/Clock.luau` (implémenté et testé).

```lua
Clock.now(): number              -- secondes UTC fractionnaires = workspace:GetServerTimeNow() (+ décalage / gel)
Clock.unix(): number             -- floor(now()) : horodatages SAUVEGARDÉS (lastOnline, boosts…)
Clock.day(t: number?): number    -- floor(t / 86400) : jour UTC (remises à zéro quotidiennes)
Clock.week(t: number?): number   -- floor((t − 345600) / 604800) : semaine (lundi 00:00 UTC)
Clock.weekday(t: number?): number   -- 0 = dimanche … 6 = samedi
Clock.secondOfDay(t: number?): number
Clock.untilNextDay(t: number?): number
Clock.untilNextWeek(t: number?): number
-- Contrôle (tests, outils de développement)
Clock.freeze(t: number?)  Clock.advance(dt: number)  Clock.unfreeze()  Clock.isFrozen(): boolean
Clock.setOffset(seconds: number)  Clock.getOffset(): number  Clock.reset()
```

Règles :
- `workspace:GetServerTimeNow()` donne la même horloge UTC des deux côtés : les phases d'événements (`EventClock`), la flânerie (`SeededPath`), les fins de boost et les recharges sont comparables côté client et côté serveur.
- **Durées et recharges de gameplay** (Dash, coupes, immunités, Zen, invitations, acclamations…) : `Clock.now()`. **Horodatages sauvegardés** : `Clock.unix()` (entiers) — sauf `lastSettle`, qui garde la précision de `Clock.now()`.
- Tests : `local Clock = h:require("ReplicatedStorage.Shared.Util.Clock"); Clock.freeze(t)` puis `Clock.advance(dt)` ; chaque harnais a sa propre instance de module (aucune fuite entre tests).
- Le tick de `CongaService` appelle `tick(Clock.now())` ; les services stepés reçoivent ce `now` et ne relisent pas l'horloge pendant le tick.

---

## 5. Serveur : ordre d'initialisation, dépendances, crochets, cycle de vie

### 5.1 Ordre (GDD §12.3)

`Main.server.luau` : `Net.setup()`, puis `Init()` de tous, puis `Start()` de tous, dans cet ordre :

| # | Service | Paquet | Peut appeler directement |
|---|---|---|---|
| 1 | DataService | socle | — |
| 2 | MonetizationService | socle | 1 |
| 3 | WorldService | world | — (Build, Lighting, WorldLayout) |
| 4 | NestService | economy | 1-3 |
| 5 | EconomyService | economy | 1, 2, 4 |
| 6 | AtlasService | economy | 1, 2, 4, 5 |
| 7 | SpawnService | conga | 4 |
| 8 | EventService | events | 1, 4, 5, 6, 7 |
| 9 | CrewService | events | 1, 4, 5 |
| 10 | QuestService | events | 1, 2, 4-9 |
| 11 | ProductService | economy | 1, 2, 4, 5, 6, 8 |
| 12 | LeaderboardService | events | 1, 3, 4 |
| 13 | CongaService | conga | tous (orchestre le tick) |

Tous peuvent utiliser : `Shared/*` (Config, Logic, Types, Util, Net, Localization), `Server/Signals`, `Server/Util/{Notify,RateLimit,Analytics}`, `Server/Data/Schema`. `MoveCheck` (`Server/Util`) n'est utilisé que par CongaService.

`Init()` : créer les états, récupérer les remotes (`Net.event`), enregistrer les crochets ; **aucun yield**. `Start()` : brancher les événements (`PlayerAdded` + joueurs déjà présents, signaux, remotes).

### 5.2 Dépendances « vers le haut » : signaux

Un service ne doit jamais `require` un service plus tardif pour l'appeler. Il émet un signal de `Server/Signals` (§7), auquel le service tardif s'abonne dans son `Start()`. Exemples : EconomyService émet `UpgradeBought` (AtlasService recalcule les perchoirs, QuestService fait progresser Q2/Q5) ; EconomyService émet `Supernova` (CrewService ouvre les acclamations, NestService met à jour la constellation, QuestService envoie l'étape 10 de l'entonnoir).

### 5.3 Crochets et poussées (le service tardif informe le service précoce)

| Appelant (tardif) | Appel | Quand |
|---|---|---|
| CongaService.Init | `EconomyService.setLineBanker(CongaService.forceParade)` | une fois ; la Supernova encaisse la file d'abord |
| EconomyService.Init | `DataService.onBeforeSave(fn)` | une fois ; `fn` règle le revenu passif avant chaque sauvegarde |
| EventService | `EconomyService.setServerBoostUntil(t)` | à chaque changement du boost ×2 de serveur |
| EventService | `SpawnService.setModifiers(mods)` | à chaque changement de météo, Frenzy, Starfall |
| CrewService | `EconomyService.setCrewPresent(player, n)` | à chaque changement d'équipage ou d'activité d'un équipier |
| CongaService | `SpawnService.setActivePlayers(n)`, `EventService.setActivePlayers(n)` | au plus 1 fois par seconde |
| AtlasService | `EconomyService.settle` → mutation → `EconomyService.refreshRate` ; `NestService.setPerchCount` / `setPerchDisplay` | à chaque changement des perchés |
| ProductService | `EventService.queueGlowParty`, `AtlasService.addNebbies`, `EconomyService.*`, `NestService.unlock` | attribution d'un produit |
| QuestService | `SpawnService.spawnWelcome / spawnGuaranteedRare / setDirected` | accueil |
| CongaService | `QuestService.onSafeMoment(player)` | après une parade ou quand la file devient vide |

### 5.4 Cycle de vie d'un joueur

| Moment | Qui fait quoi |
|---|---|
| `PlayerAdded` (et joueurs déjà présents) | DataService charge (verrou de session). **NestService** attribue le Nid tout de suite (ami proche, sinon plus petit libre), pose `RespawnLocation` et l'attribut `Slot`. **CrewService** forme les équipages d'amis (si `autoCrew`, dès le profil chargé). **CongaService** crée l'état de file (slot), envoie `LineEvent "owner"` puis un `WorldSnapshot` au nouveau joueur. |
| `CharacterAdded` (chaque apparition) | **NestService** place le personnage sur son Nid tourné vers le centre (`PivotTo`) puis `Signals.ServerMoved`. **CongaService** remet `MoveCheck` (exemption 3 s) et les miettes à zéro, applique le WalkSpeed. |
| `DataService.Loaded` | **EconomyService** : gains hors ligne, `lastSettle = now`, `idleRate`, écran de retour. **AtlasService** : tri des perchoirs, `NestService.setPerchDisplay`. **NestService** : attributs (Zen, cosmétiques, Supernovas, VIP) puis `Signals.PlayerReady(player, slot)` dès que profil ET Nid sont prêts. **QuestService** : session +1, jours UTC, chaîne d'accueil (sur `PlayerReady` : Puffkins de bienvenue si `onboarding.step == 0`), bouclier. **LeaderboardService** : titre de la semaine. Tout handler revérifie `DataService.get(player)` et `player.Parent` après un yield. |
| `Humanoid.Died` / réinitialisation | **CongaService** : file détachée (Nebbies libres prioritaires pour le propriétaire, sans Second Souffle), `LineEvent "clear" (death)`, `EventService.dropComet`. |
| `PlayerRemoving` | **CongaService** : file détachée sans priorité (`clear` « leave »), `dropComet`, `LineEvent "owner"` (0). **SpawnService** : apparitions personnelles retirées. **CrewService** : retiré de son équipage. **NestService** : Nid libéré (gris). DataService sauvegarde (le crochet `onBeforeSave` règle le Glow). Chaque service vide ses tables par joueur. `RateLimit` se vide seul. |

---

## 6. Le tick de 10 Hz de `CongaService`

Une seule connexion `RunService.Heartbeat` (dans `CongaService.Start`) accumule le temps : tant que `acc ≥ Balance.Tick.Step` (0,1 s) et au plus `Balance.Tick.MaxCatchUp` (3) pas par image, elle appelle `CongaService.tick(Clock.now())` puis `acc −= 0,1` ; au-delà de 3 pas, le reste est abandonné (`acc = 0`). `tick(now)` est public pour les tests (`Clock.freeze(t)` puis `CongaService.tick(t)`).

**Ordre EXACT d'un pas (`dt = 0,1`)** :

| # | Étape | Appels |
|---|---|---|
| 1 | Horloge | `now` (paramètre) ; `tickId = (tickId + 1) % 65536` |
| 2 | Acteurs et miettes | Pour chaque joueur avec profil chargé, slot > 0, personnage vivant avec `HumanoidRootPart` : `verdict, back = MoveCheck.step(player, pos, 0.1, now, WorldLayout.groundY(pos.X, pos.Z))` ; `"rewind"` → `PivotTo(back)`, `flags.strikes`, attribut `Unstable`, `Signals.MoveViolation` ; acteur `Types.Actor` avec `valid = verdict == "ok" and not MoveCheck.isRestricted(player, now)`, `zen = NestService.isZen`, `crewId = CrewService.crewOf`, `rookie = QuestService.isRookie`, `touch = inputType == 1` ; si `verdict == "ok"` : `trail:push(pos)` et `netTrail:push(pos)` |
| 3 | Événements | `EventService.step(now)` — transitions de phase (météo, Comète, Balise, Frenzy, Nuit d'Or, Starfall), Gloomwisps |
| 4 | Apparitions | `SpawnService.step(now)` — apparitions dues, expirations |
| 5 | Captures | Acteurs `valid` dont la file a de la place : `SpawnService.query(pos, Formulas.lureRadius(lure, rush) + Balance.Catch.LatencyTolerance, now, player)`, `|Δy| ≤ Catch.MaxDy`, `SpawnService.canCatch` ; conflit : le plus proche gagne, égalité → ordre des acteurs mélangé à chaque tick ; `SpawnService.consume(id, player)` ; nœud ajouté ; `Signals.Caught` |
| 6 | Comète | `EventService.stepComet(now, actors)` — ramassage, vol, encaissement, explosion |
| 7 | Coupes | Joueurs (`valid`) × files des autres : `SnipRules.blockReason` puis `SnipRules.findCut` (balayage `prev → pos`, escorte via `CrewService.escortersOf(victim)` à ≤ 7 studs, port sûr via `WorldLayout.inHarbor`) ; puis `EventService.wispSweeps(now)` × files (rayon 2,5, `isWisp = true`) → `EventService.onWispSnip` |
| 8 | Gloomwisps éclatés | `EventService.stepWisps(now, actors)` |
| 9 | Parades | Acteurs `valid` dont le déplacement validé `prev → pos` traverse `WorldLayout.inGateBox(slot, ·)` de LEUR Nid, ou `WorldLayout.inBeaconRing(·)` si `EventService.beaconOpen()` (échantillons tous les 1 stud, §16.27) ; file non vide → parade (§11.13) |
| 10 | Entretien par joueur | WalkSpeed (`Formulas.walkSpeed`) posé seulement s'il change + `MoveCheck.noteSpeed` ; temps d'escorte (cumul, `Signals.EscortTime` par seconde pleine) ; joueurs actifs (1 / s → `SpawnService.setActivePlayers`, `EventService.setActivePlayers`) ; `Signals.LineChanged` pour chaque file modifiée ce tick |
| 11 | Services lents | `EconomyService.step(now)`, `QuestService.step(now)`, `CrewService.step(now)`, `LeaderboardService.step(now)` (chacun limite lui-même sa fréquence) |
| 12 | Diffusion | `LineEvent:FireAllClients(ops)` (UNE liste par tick, si non vide) ; `SnipEvent:FireAllClients(payload)` (une par coupe) ; `PathStream:FireAllClients(buf)` ; `SpawnService.flush(now, urgent)` ; `EventService.flush()` |

Règles du tick :
- Les fonctions stepées **ne yieldent jamais** ; tout appel réseau (DataStore, MessagingService, `IsFriendsWith`) part en `task.spawn` avec `pcall`.
- Chaque appel externe des étapes 3, 4, 6, 7 (Gloomwisps), 8 et 11 est protégé par `pcall` dans CongaService ; une erreur est signalée par `warn("[CongaService] <étape> :", err)` au plus une fois toutes les 10 s par étape, pour qu'un service défaillant ne fige pas le jeu.
- Coût visé : < 2 ms en moyenne avec 12 joueurs, 12 files de 60, 74 sauvages, 5 Gloomwisps (élagage par boîtes englobantes, grille de 16 studs).
- `EconomyService.settle` est appelé à chaque événement économique et, via `EconomyService.step`, toutes les `Balance.Idle.SettleInterval` (30) s par joueur, décalé selon l'index du joueur.

---

## 7. Signaux internes du serveur (`src/server/Signals.luau`)

Bus de `Shared/Util/Signal` (chaque handler dans son propre thread). Un signal a **un** émetteur ; n'importe quel service s'y abonne dans `Start()`. Les types viennent de `Shared/Types`.

| Signal | Arguments | Émis par | Abonnés prévus |
|---|---|---|---|
| `PlayerReady` | `(player, slot)` | NestService | QuestService (entonnoir 1 « Loaded », accueil), CongaService (WorldSnapshot si non envoyé) |
| `ServerMoved` | `(player)` | NestService (CongaService ne l'émet pas : un rembobinage anti-triche n'ouvre aucune exemption, voir §16.25) | CongaService (`MoveCheck.reset`, miettes) |
| `Caught` | `(player, CatchInfo)` | CongaService | QuestService (quêtes, stats, entonnoir 2) |
| `LineChanged` | `(player, n)` | CongaService | LeaderboardService (tableau en direct) |
| `Parade` | `(player, ParadeInfo)` | CongaService | QuestService (Q1/Q3/Q4, quotidiennes, hebdo, entonnoir 3), LeaderboardService (record, hebdo), EventService (Balise : via `onBeaconParade` direct, pas ce signal) |
| `Snipped` | `(SnipInfo)` | CongaService | QuestService (quêtes JcJ, stats), (analytics dans CongaService) |
| `Dashed` | `(player)` | CongaService | QuestService (quête 6) |
| `EscortTime` | `(player, seconds)` | CongaService | QuestService (quête 14, `stats.escortSeconds`, titre) |
| `MoveViolation` | `(player, count)` | CongaService | (analytics) |
| `UpgradeBought` | `(player, track, level)` | EconomyService | AtlasService (`perches`), QuestService (Q2, Q5, quête 7, entonnoir 4/8) |
| `Supernova` | `(player, newR)` | EconomyService | NestService (attributs), CrewService (CheerPrompt, bannière), QuestService (bouclier, entonnoir 10) |
| `IdleSettled` | `(player, glow, seconds)` | EconomyService | QuestService (quête 16) |
| `RateChanged` | `(player, idleRate)` | EconomyService | (libre) |
| `PerchesChanged` | `(player, count)` | AtlasService | QuestService (Q7) |
| `AtlasEntry` | `(player, s, f, total)` | AtlasService | QuestService (quête 24), LeaderboardService (`AtlasAllTime`) |
| `Fused` | `(player, stars)` | AtlasService | QuestService (quête 15, `stats.fusions`) |
| `EventPhase` | `(event, phase)` | EventService | QuestService (Q6), libre |
| `CometEvent` | `(CometSignal)` | EventService | QuestService (stats), analytics |
| `CometParticipation` | `(player, "hold" \| "near" \| "crew")` | EventService | QuestService (quête 4, Q6) |
| `CometHeld` | `(player, seconds)` | EventService | QuestService (quête 21, `stats.cometsHeld`) |
| `WispPopped` | `(player)` | EventService | QuestService (quête 5, stats) |
| `BeaconResult` | `(success, contributors)` | EventService | QuestService (quête 22, `stats.beaconWins`, titre) |
| `CrewChanged` | `({Player})` | CrewService | QuestService (`stats.lastCrewDay`) |
| `Cheered` | `(cheerer, hero)` | CrewService | QuestService (quête 17, stats) |
| `SettingChanged` | `(player, key, value)` | NestService | QuestService (filtre JcJ en Zen), EventService (`dropComet` si Zen), CrewService (`autoCrew`) |
| `RookieEnded` | `(player)` | QuestService | (libre) |
| `BannerRequested` | `(kind, args, source?)` | tous via `Notify.banner` | CrewService (file des bannières) |

Ajouter un signal = modifier le contrat : le demander dans les notes d'intégration.

---

## 8. Données sauvegardées (schéma v1) et propriétaires

`src/server/Data/Schema.luau` (contrat) : `Schema.VERSION = 1`, magasin `PlayerData_v1`, clé `player_<UserId>`, `Schema.defaults()`, `Schema.migrate(data, from)` (v0 « coins » → `glow`, sans effacer `coins`), `Schema.PRIVATE_KEYS = { receipts, codes, flags }`, `Schema.OWNERS` (ci-dessous, vérifié par la spec).

| Clé | Contenu | Propriétaire | API pour les autres |
|---|---|---|---|
| `version` | 1 | DataService | — |
| `glow`, `glowCarry`, `lastSettle`, `lastOnline`, `idleRate` | Glow entier, fraction ∈ [0 ; 1[, `Clock.now()` du dernier règlement, `Clock.unix()` de présence, Glow/s avec M (répliqué) | EconomyService | `addGlow`, `addGlowSeconds`, `trySpendGlow`, `settle`, `idleRate` |
| `stardust` | entier | EconomyService | `addStardust`, `addStardustCapped`, `trySpendStardust` |
| `supernovas` | R | EconomyService | `supernovas`, `Signals.Supernova` |
| `upgrades` | `{ conga, stride, lure, perches, guard }` | EconomyService | `upgradeLevel`, `Signals.UpgradeBought` |
| `boosts` | `{ personalUntil }` (`Clock.unix()`) | EconomyService | `grantPersonalBoost`, `hasBoost` |
| `caps` | `{ day, snipDust, wispDust, cheers, duo }` (jour UTC) | EconomyService | `addStardustCapped(player, n, capKey, sku)` |
| `nebbies`, `nextUid` | `[uid] = NebbyRecord`, uid = `"u" .. nextUid` | AtlasService | `addNebbies`, `record`, `release`, `fuse`, `setLock` |
| `perchIncome` | Σ revenu passif des perchés SANS M | AtlasService | lu par EconomyService |
| `atlas`, `badges`, `atlasRewards` | 7 et 4 mots de 32 bits, dernier jalon réclamé | AtlasService | `hasEntry`, `atlasCount`, `Signals.AtlasEntry` |
| `onboarding` | `{ step, p }` (0 pas commencé, 1-7, 8 fini) | QuestService | `onboardingStep` |
| `daily`, `quests`, `weekly` | calendrier, 3 quêtes du jour, Grand Défilé | QuestService | remotes |
| `rookie` | `{ sessions, playSeconds, done }` | QuestService | `isRookie`, `onSafeMoment` |
| `stats` | compteurs (§12.6 du GDD) | QuestService | signaux §7 |
| `codes` (privé) | `[CODE] = true` | QuestService | `redeem` |
| `settings` | réglages sauvegardés de `Config/Settings` | NestService | `setting`, `isZen`, `Signals.SettingChanged` |
| `cosmetics`, `unlocks` | équipés ; `{ styles, titles, themes }` | NestService | `unlock`, `grantTemporary`, `hasUnlock` |
| `weeklyBest` | `{ week, conga }` | LeaderboardService | — |
| `starterKit` | bool | ProductService | — |
| `passes`, `receipts` (privé) | passes possédés, reçus traités | MonetizationService (socle) | `ownsPass`, `PassGranted` |
| `flags` (privé) | `{ strikes, lbBanned }` | CongaService | lu par LeaderboardService |

Règles :
1. **Écriture** : seul le propriétaire mute sa clé, puis appelle `DataService.markDirty(player, clé)` (ou `DataService.set`) pour la réplication par patch. **Lecture** : tout service serveur peut lire `DataService.get(player)` (jamais muter).
2. **Monnaies entières** (`math.floor`), jamais négatives, jamais NaN ; `glowCarry ∈ [0 ; 1[`.
3. **Règle d'or du revenu passif** : `EconomyService.settle(player)` **avant** tout changement de taux (perchés, R, VIP, Double Glow, boosts, équipiers) ou de solde ; puis `EconomyService.refreshRate(player)`.
4. Plafonds du jour (`caps`) remis à zéro quand `Clock.day() ≠ caps.day` (au premier accès du jour).
5. Remise à zéro quotidienne des quêtes et hebdomadaire (`weekly`, `weeklyBest`) par comparaison avec `Clock.day()` / `Clock.week()` au chargement et dans `step`.
6. Pas d'Instance, de Vector3 ni de table mixte dans le profil (le DataStore simulé du harnais refuse).
7. Ajouter une clé = modifier le contrat (Schema + Types + OWNERS) : notes d'intégration.

---

## 9. Configuration (`Shared/Config`) et types (`Shared/Types`)

| Fichier | Contenu (GDD) | Lu par |
|---|---|---|
| `Balance.luau` | Tick, Conga, Speed, Dash, Catch, Snip, Guard, Crew, Parade, Idle, Offline, Multiplier, Upgrades (+ `UpgradeOrder`), Perches, Stash, Supernova, Starforge, Comet, Beacon, Wisps, DailyCaps, Rookie, Zen, Cheer, Ping, GlowParty, MoveCheck, Spawn, Net, Render, Leaderboard (§4, §6, §9, §12) | tous ; **valeurs** réglables par logic (§17) |
| `Nebbies.luau` | 7 raretés, 6 formes (0-5), 3 variantes (bits 1/2/4), étoiles, 36 espèces (id définitif, clé, nom, rareté, archétypes, accent, version), `ENABLED_VERSIONS`, `Named` ; aides `pack/unpack/isValidCode/atlasIndex/badgeIndex/testBit/setBit/speciesOfRarity/atlasTotal` (§4.2, §4.4, §4.13, §5.1) | tous |
| `Zones.luau` | île, 3 zones (probabilités, plafonds, intervalles, durées), sols, Balise, Nids, perchoirs (4 anneaux = 46), chemins, lanternes, décor, îlots, budget (§4.3, §11) | WorldLayout, WorldService, SpawnService |
| `Events.luau` | calendrier UTC, sels de hachage, météos (poids, formes, éclairage), Comète, Balise, Starfall, rotations, LiveOps, éclairage (cycle, base, préréglages) (§2.4, §4.15, §5.1, §11.5) | EventClock, EventService, LightingController |
| `Quests.luau` | types d'objectif, Q1-Q7, entonnoir, 25 quotidiennes, niveaux de récompense, Étoile du jour, relances, hebdo, calendrier, jalons d'Atlas (§7, §4.14, §14.1) | QuestService, AtlasService, panneaux |
| `Cosmetics.luau` | styles, auras, titres, thèmes (avec sources), 12 couleurs de Nid, couleurs de lisibilité (§5.3, §6.4) | NestService, CongaRenderer, panneaux |
| `Settings.luau` | 9 réglages (type, défaut, valeurs, sauvegardé, harborOnly, cooldown, ownerOnly) (§10.3) | Schema, NestService, Prefs, Panels/Settings |
| `Monetization.luau` | 6 passes, 6 produits (IDs 0, prix §8, effets) | MonetizationService, ProductService, Economy/Atlas, Panels/Shop |
| `Sounds.luau` | sons optionnels (IDs vides) (§9.1) | AudioController |

`Shared/Types.luau` exporte le vocabulaire commun : `NebbyCode`, `NebbyRecord`, `UpgradeTrack`, `Profile`, `LineNode`, `WildNebby`, `Actor`, `SpawnModifiers`, `CatchInfo`, `ParadeInfo`, `SnipInfo`, `CometSignal`, toutes les charges utiles réseau (§10), `SupernovaPreview`, `PanelName`, `HudElement`, `LineMirror`, `WildMirror`. **Code de Nebby** : `code = s | (f << 6) | (v << 9)` (12 bits ; `Nebbies.pack/unpack`). Un Nebby de file est toujours ★1 ; les étoiles n'existent qu'en collection.

**Versions de contenu** : `Nebbies.ENABLED_VERSIONS["v1.1"] = false`. Tout tirage (espèces, formes, météos) ne considère que le contenu activé ; l'Atlas réserve déjà les bits de la v1.1 (aucune migration à prévoir).

---

## 10. Réseau

Tous les remotes sont déclarés dans `src/shared/Remotes.luau` (vérifié par la spec du contrat) et créés par `Net.setup()`. Aucun `RemoteFunction` serveur → client. Les achats Robux passent par `MarketplaceService` (prompts côté client, `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur dans MonetizationService).

### 10.1 Client → serveur

Débit : `RateLimit.allow(player, "<Nom>", n, secondes)` ; deux limites = deux appels avec deux noms d'action. Toute charge invalide est **ignorée silencieusement** (pas de Feedback : un tricheur n'apprend rien) ; un refus **légitime** (pas assez de Glow…) renvoie un `Feedback`.

| Remote | Charge utile | Validation serveur (dans l'ordre §1.3) | Débit | Handler |
|---|---|---|---|---|
| `Dash` | — | profil chargé ; personnage vivant ; pas porteur de la Comète (Feedback `cometNoDash`) ; recharge serveur écoulée (`DashReadyAt`) | 3 / 1 s | CongaService |
| `BuyUpgrade` | `track: string` | `Validate.key(track, Balance.Upgrades, 16)` ; profil ; `settle` ; niveau < `Formulas.upgradeMaxLevel` (Feedback `maxLevel`) ; Glow ≥ coût (Feedback `notEnoughGlow {missing}`) | 10 / 1 s | EconomyService |
| `Supernova` | — | profil ; `NestService.inOwnHarbor` (Feedback `notInHarbor`) ; encaissement de la file (crochet) ; `settle` ; Glow ≥ `Formulas.supernovaCost(R)` | 1 / 2 s | EconomyService |
| `Fuse` | `uid: string` | `Validate.string(uid, 12)` ; possédé ; ★ < 5 ; 2 autres identiques non verrouillés (Feedback `fuseNeedCopies`) ; Stardust ≥ coût | 6 / 1 s | AtlasService |
| `FuseAll` | — | profil | 1 / 2 s | AtlasService |
| `Release` | `uids: {string}` | table séquentielle (`#t` = nombre de clés), 1-50 chaînes ≤ 12, uniques ; toutes possédées, non verrouillées, non Cosmiques ; sinon RIEN n'est libéré | 2 / 1 s | AtlasService |
| `SetLock` | `uid: string, locked: boolean` | chaîne ≤ 12 possédée ; booléen | 6 / 1 s | AtlasService |
| `ClaimDaily` | — | jour UTC ≠ `daily.day` (Feedback `dailyAlready`) | 1 / 1 s | QuestService |
| `ClaimQuest` | `kind: string, slot: number` | kind ∈ {daily, weekly, onboarding} ; `Validate.integer(slot, 1, 3)` (weekly, onboarding : 1) ; terminée et non réclamée | 4 / 1 s | QuestService |
| `RerollQuest` | `slot: number` | entier 1-3 ; relance restante (1, +1 VIP) ; quête non terminée | 1 / 1 s | QuestService |
| `CrewInvite` | `userId: number` | entier ; joueur présent ≠ soi ; pas déjà équipiers ; équipage < 4 ; cible sans `refuseInvites` | 1 / 3 s **et** 5 / 60 s | CrewService |
| `CrewRespond` | `inviterId: number, accept: boolean` | entier ; booléen ; invitation en attente, non expirée (20 s) | 2 / 1 s | CrewService |
| `CrewLeave` | — | dans un équipage | 1 / 5 s | CrewService |
| `Ping` | `kind: number` | entier 1-6 | 1 / 1,5 s | CrewService |
| `Cheer` | `heroId: number` | entier ; fenêtre ouverte pour ce héros ; pas déjà acclamé pour cette Supernova ; ≠ soi | 2 / 1 s | CrewService |
| `SetSetting` | `key: string, value: boolean \| string` | `Validate.key(key, Config.Settings)` ; type = `kind` ; `values` pour les chaînes ; `harborOnly` (zen) + `cooldown` 60 s ; `ownerOnly` (privateNoSnip : `game.PrivateServerOwnerId == player.UserId`, sinon Feedback `ownerOnly`) | 4 / 1 s | NestService |
| `SetInputType` | `kind: number` | entier 1-3 | 1 / 5 s | CongaService |
| `EquipCosmetic` | `kind: string, id: string` | kind ∈ {style, title, theme} ; id existant dans Cosmetics ; `NestService.hasUnlock` (Feedback `notOwned`) ; title "" = aucun | 2 / 1 s | NestService |
| `RequestWorld` | — | — | 1 / 2 s | CongaService → `WorldSnapshot` |
| `RequestPath` | `slot: number` | entier 1-12 | 4 / 1 s | CongaService → `PathSnapshot` |
| `AdminCommand` | `command: string` | chaîne ≤ 32 ; `Data/Admins[player.UserId]` ; commande ∈ `Events.LiveOps.Commands` (`"weather:<clé>"` : clé de `Events.WeatherByKey`) | 1 / 2 s | EventService |
| `RedeemCode` (Function) | `code: string` → `status: string` | chaîne ≤ 20, majuscules, `^[A-Z0-9]+$` ; existe ; non expiré ; jamais utilisé par ce compte ; statut `"ok" \| "invalid" \| "expired" \| "used" \| "busy"` | 1 / 3 s **et** 10 / 3600 s (`busy`) | QuestService |
| `RequestSnapshot` | — | (socle) | 2 / 10 s | DataService |

### 10.2 Serveur → client

| Remote | Charge utile (`Shared/Types`) | Destinataires | Émetteur | Abonné client (seul) |
|---|---|---|---|---|
| `DataSnapshot`, `DataPatch` | profil public / `(patch, removedKeys)` | le joueur | DataService | StateController |
| `PathStream` (non fiable) | `buffer` (§10.4) | tous, 10 Hz | CongaService | WorldStateController |
| `PathSnapshot` | `(slot: number, buf: buffer)` — buf au format §10.4 (runs du seul `slot`, 200 derniers points) | le demandeur | CongaService | WorldStateController |
| `WorldSnapshot` | `WorldSnapshotPayload` | arrivée, `RequestWorld` | CongaService | WorldStateController |
| `LineEvent` | `{ LineOp }` (une liste par tick, ordonnée) | tous | CongaService | WorldStateController |
| `SnipEvent` | `SnipEventPayload` | tous | CongaService | WorldStateController |
| `WildEvent` | `WildEventPayload` | tous (publics), le seul joueur concerné (personnels) ; 4 Hz | SpawnService | WorldStateController |
| `EventState` | `EventStatePayload` (état complet) | tous, à chaque changement (≤ 1 / tick) + arrivée | EventService | WorldStateController |
| `Banner` | `BannerPayload` | tous (ou un joueur si `personal`) | CrewService (file) / `Notify.personalBanner` | Banners |
| `Feedback` | `FeedbackPayload` | le joueur | tous via `Notify.feedback` | ScreenFX |
| `Celebrate` | `CelebratePayload` | le joueur | tous via `Notify.celebrate` | ScreenFX |
| `CrewState` | `CrewStatePayload` | tous, à chaque changement + arrivée | CrewService | WorldStateController |
| `CrewInvitePrompt` | `CrewInvitePayload` | la cible | CrewService | PanelController (→ Panels/Crew) |
| `CheerPrompt` | `CheerPromptPayload` | tous sauf le héros | CrewService | HUD |
| `PingShow` | `PingPayload` | tous | CrewService | WorldStateController |

**Formes exactes** (types Luau dans `src/shared/Types.luau`, qui fait foi) :

```lua
-- LineEvent : { LineOp }, appliquées par slot dans l'ordre STRICT de `ver`
{ op = "add",   slot, ver, codes = { NebbyCode }, ids = { number } }   -- capturés ce tick, ajoutés en queue
{ op = "bank",  slot, ver, count, glow, bonus, atBeacon, newEntries }  -- parade : la file est vidée
{ op = "clear", slot, ver, reason = "death" | "leave" | "reset" | "supernova", loose = { WildSpawn } }
{ op = "owner", slot, ver = 0, userId }                                -- nouvelle vie du slot (0 = libre)

-- SnipEvent : la coupe elle-même (même suite de `ver` que LineEvent pour la victime)
{ snipperSlot, victimSlot, ver, cutIndex, count, looseIds = { number }, loose = { WildSpawn },
  byWisp, wispId?, x, y, z, dust }

-- WildEvent
{ spawns = { WildSpawn }, despawns = { { id, reason = "expired" | "caught" | "cleared", slot? } } }
WildSpawn = { id, code, x, z, seed, t0, life, dizzyUntil?, prioritySlot?, fromX?, fromZ?, personal? }

-- EventState (état complet)
{ t, weather? = { key, form?, startsAt, endsAt, forced? },
  comet? = { id, phase = "warn" | "ground" | "carried" | "banked" | "burst", x, z, code, warnAt, impactAt,
             burstAt, carrierId?, carrierSince?, prevCarrierId?, endedAt? },
  beacon? = { phase = "warn" | "active" | "success" | "fail", warnAt, startsAt, endsAt, points, goal, topUserId? },
  frenzy? = { endsAt }, serverBoost? = { endsAt, source = "goldenNight" | "glowParty" | "starfall" | "liveOps", buyerId? },
  starfall? = { startsAt, endsAt, featured }, wisps = { { id, seed, t0, poppedAt?, poppedBy?, respawnAt? } },
  snipsDisabled, activePlayers }

-- WorldSnapshot
{ serverTime, tick, lines = { { slot, userId, ver, codes } }, paths = buffer, wild = { WildSpawn },
  events = EventStatePayload, crews = CrewStatePayload }

-- Divers
Banner     = { kind: BannerKind, args: { [string]: any }, priority: number, personal: boolean? }
Feedback   = { key: string, vars: { [string]: any }, tone: "info" | "success" | "warning" | "error" | "reward" }
Celebrate  = { kind: CelebrateKind, data: { [string]: any } }
CrewState  = { crews = { { id, userIds = { number } } } }
CrewInvitePrompt = { inviterId, expiresAt }     CheerPrompt = { heroId, level, expiresAt }     PingShow = { userId, kind }
```

Contraintes de charge utile : tableaux séquentiels ou dictionnaires à clés chaînes, jamais mixtes ni à trous ; positions en nombres (x, z) plutôt qu'en tables ; `Vector3` autorisé seulement dans les types serveur internes ; `buffer` pour les miettes.

### 10.3 Feedback, bannières, célébrations (`Server/Util/Notify`)

```lua
Notify.feedback(player: Player, key: string, vars: { [string]: any }?, tone: Types.FeedbackTone?)
Notify.celebrate(player: Player, kind: Types.CelebrateKind, data: { [string]: any }?)
Notify.banner(kind: Types.BannerKind, args: { [string]: any }?, source: Player?)   -- → Signals.BannerRequested → CrewService
Notify.personalBanner(player: Player, kind: Types.BannerKind, args: { [string]: any }?)
Notify.BANNER_PRIORITY: { [string]: number }   -- 1 = plus haute
```

Les fonctions ne font rien si le joueur est parti. Le client traduit `key` avec `vars`.

**Clés de Feedback** (`Strings.luau`, domaine `feedback.`) et émetteurs : `notEnoughGlow {missing}` / `notEnoughStardust {missing}` / `maxLevel` (Economy, Atlas) · `lineFull` (Conga, ≤ 1 / 5 s) · `notInHarbor` (Economy, Nest) · `zenCooldown {seconds}`, `zenOn`, `zenOff`, `ownerOnly`, `styleEquipped`, `notOwned` (Nest) · `cometNoDash`, `cometNoZen`, `dashCooldown`, `snipped`, `snipDealt {count, dust}`, `recovered`, `rookieNoDust`, `unstable` (Conga) · `fuseNeedCopies`, `fuseMaxStars`, `nebbyLocked`, `cannotRelease`, `released {count, dust}`, `autoRelease {count, dust}` (Atlas) · `questNotDone`, `alreadyClaimed`, `noReroll`, `dailyAlready`, `boostOn {minutes}` (Quest) · `crewInviteSent {name}`, `crewDeclined {name}`, `crewFull`, `crewJoined {name}`, `crewLeft`, `crewRefuses {name}`, `crewAlready`, `crewExpired`, `cheersReceived {n}`, `cheerReward {dust}`, `duoGift {name, dust}` (Crew) · `cometStolen {name}`, `cometNear {dust}`, `cometHold {dust}`, `cometCrew {dust}`, `beaconWin {dust}`, `beaconFail {dust}`, `wispPop {dust}`, `capReached`, `liveOpsDone` (Event) · `purchaseThanks`, `glowPartyQueued {minutes}` (Product).

**Bannières** (`BannerKind`, texte `banner.<kind>`, priorité `Notify.BANNER_PRIORITY`) : `mythicCatch` (1) · `rookieEnd` (1, personnelle) · `cometWarn`, `cometPickup`, `cometStolen`, `cometBanked`, `cometBurst` (2) · `supernova`, `atlasMilestone` (3) · `legendaryCatch`, `megaParade` (4) · `serverRecord` (5) · `glowParty`, `beaconStart`, `beaconWin`, `beaconTop`, `beaconFail`, `goldenNight`, `starfall` (6) · `weather`, `liveOps` (7). Arguments usuels : `userId`, `name` (DisplayName), `code` (NebbyCode : le client en tire espèce, forme), `level`, `n`, `key` (météo), `endsAt`. Serveur (CrewService) : une même source au plus 1 bannière / 10 s ; file de 3, triée par priorité ; une diffusion toutes les 3 s. Client (Banners) : file de 3, 3 s chacune.

**Célébrations** (`CelebrateKind`) et `data` : `supernova {level}` · `atlasNew {entries = { {s, f} }}` · `atlasMilestone {count, perch?, title?, style?, theme?}` · `speciesComplete {s, dust}` · `questDone {kind, slot, id}` · `questClaimed {kind, slot, glow, stardust}` · `dailyClaimed {day, glow?, stardust?, boostSeconds?, code?}` · `starforge {uid, s, f, v, stars}` · `upgrade {track, level}` · `offline {glow, seconds, nightShift}` · `purchase {product?, pass?}` · `cometBanked {glow, code}` · `rookieEnd {}` · `release {count, dust}` · `unlock {kind, id}`.

### 10.4 Format binaire `PathStream` (`src/shared/Logic/PathCodec.luau`, paquet conga)

```
u16 tick                         tick serveur modulo 65536
u8  runCount                     ≤ 255
répété runCount fois :
  u8  slot                       1-12
  u32 firstSeq                   numéro du premier point du run
  u8  n                          1-255 points
  i16 x×8, i16 y×8, i16 z×8      premier point absolu (1/8 de stud)
  (n − 1) × [i8 dx×16, i8 dy×16, i8 dz×16]   deltas depuis le point QUANTIFIÉ précédent
```

- Little-endian (bibliothèque `buffer`). Arrondi au plus proche ; un delta hors de [−127 ; 127] (plus de 7,9 studs sur un axe) **ouvre un nouveau run** absolu du même slot (seq contigus). Pas de dérive : chaque delta est calculé contre la reconstruction du point précédent.
- **Miettes réseau** : `netTrail = Trail.new(Balance.Conga.TrailLength, Balance.Conga.NetMinStep, firstSeq)` (un point par stud parcouru), poussée seulement sur un tick valide. Numérotation **contiguë par slot entre propriétaires successifs** (le nouveau propriétaire reprend à `dernier + 1`) : un client ne voit jamais un seq reculer.
- Chaque message répète pour chaque joueur les `Balance.Net.PathRepeat` (2) derniers points déjà envoyés ; un joueur arrêté n'est plus inclus après `StillResendTicks` (5) ticks de renvoi. Une perte isolée se répare seule.
- Client : points de seq ≤ dernier connu ignorés ; `firstSeq > dernier + 1` → trou → `RequestPath(slot)` (au plus 1 / s par slot) → `PathSnapshot` → `trail:reset` puis `push` des points. Paquets de `tick` plus ancien (comparaison modulo 65536) ignorés. Décodage sous `pcall`.
- Taille : ≈ 3 + 12 + 3 × (points − 1) octets par joueur en mouvement (≈ 25 octets à 10 Hz, ≈ 3 Ko/s par client à 12 joueurs).

### 10.5 Ordre des opérations de file et recouvrement

- Chaque file (par slot) a une version `ver` qui augmente de 1 à chaque op (`add`, `bank`, `clear`, coupe via `SnipEvent`) ; `owner` remet la version à 0. LineEvent et SnipEvent partagent cette suite : le client applique les ops **dans l'ordre de `ver`**, met en attente une op en avance pendant `Balance.Net.VersionBufferSeconds` (1 s), puis envoie `RequestWorld` si le trou persiste (`WorldSnapshot` remplace tout).
- Dans un même tick, l'ordre serveur est : captures (`add`), coupes (`SnipEvent`), parades (`bank`), morts/départs (`clear`) — chacune avec sa version.
- Un Nebby capturé n'apparaît PAS dans `WildEvent.despawns` : l'op `add` porte son `id` (le client le retire et anime le saut depuis sa position). Les Nebbies libérés par une coupe, une mort ou un départ voyagent DANS l'op (`loose`) et pas dans `WildEvent`. Les Épiques d'une explosion de Comète passent par `WildEvent` (envoi urgent).
- Client : un id retiré est mémorisé 5 s pour ignorer une apparition tardive ; un sauvage expire localement à `t0 + life`.
- Ids de sauvages : entiers 1-65535 réutilisés (au plus ≈ 74 vivants + libres).

### 10.6 Arrivée en cours de partie

`WorldSnapshot` (≈ 20 Ko max, une fois) : files (codes), miettes récentes (≤ 200 points par slot, format §10.4), sauvages visibles par ce joueur (publics + ses personnels), `EventState`, `CrewState`. Puis le flux normal. Le client n'utilise **jamais** les personnages des autres joueurs comme source de vérité (streaming) : minicarte, files lointaines et tableau viennent des données serveur.

---

## 11. Services serveur (API)

Chaque fiche donne : rôle, API (signatures exactes du stub), signaux, remotes, clés de profil, dépendances. Le détail des responsabilités est aussi en tête de chaque stub. GDD de référence entre parenthèses.

### 11.1 DataService (socle)

API existante : `get`, `isLoaded`, `waitFor`, `set`, `increment`, `markDirty`, `saveNow`, `Loaded` (Signal `(player, data)`), `Settings`. **Ajout du contrat** : `DataService.onBeforeSave(fn: (Player, { [string]: any }) -> ())` — crochets synchrones appelés juste avant chaque écriture (autosave 90 s, `saveNow`, départ, `BindToClose`), protégés par `pcall`. Clé : `version`.

### 11.2 MonetizationService (socle)

API existante : `registerProduct(key, handler)`, `ownsPass(player, key)`, `PassGranted` `(player, passKey)` (à l'arrivée pour chaque pass possédé, et à l'achat), `ProductGranted` `(player, productKey)`. `ProcessReceipt` unique et idempotent. Clés : `passes`, `receipts`. Les effets sont dans ProductService (§11.11).

### 11.3 WorldService (paquet world) — GDD §11

Construit Lumora dans `Init()` (synchrone, sans yield, budget ≤ `Zones.PartBudget`), pose l'éclairage de base (`World/Lighting.applyTwilight()` puis les valeurs `Events.Lighting.Base`, `Terrain.Clouds`), et fournit les points d'accroche. Arborescence et tags : §3.1.

```lua
WorldService.Init()
WorldService.Start()
WorldService.root(): Folder
WorldService.nest(slot: number): Model
WorldService.spawnLocation(slot: number): SpawnLocation
WorldService.setNestAppearance(slot: number, platform: Color3?, arch: Color3?)
WorldService.setPerchCount(slot: number, count: number)
WorldService.beacon(): Model
WorldService.board(): BasePart
WorldService.partCount(): number
```

Signaux : — . Remotes : — . Clés : — . Dépendances : `World/Build`, `World/Lighting`, `Logic/WorldLayout`, Config (`Zones`, `Cosmetics`, `Events`).

### 11.4 NestService (paquet economy) — GDD §3, §4.16, §5.3, §6.1, §6.6, §11.3

Nids (attribution, couleur, perchoirs, constellation), réglages et cosmétiques. Attributs : §3.2 et §3.3.

```lua
NestService.Init()
NestService.Start()
NestService.slotOf(player: Player): number
NestService.playerAt(slot: number): Player?
NestService.inOwnHarbor(player: Player, pos: Vector3?): boolean
NestService.teleportHome(player: Player)
NestService.setPerchDisplay(player: Player, entries: { { code: number, stars: number } })
NestService.setPerchCount(player: Player, count: number)
NestService.setting(player: Player, key: string): any
NestService.isZen(player: Player): boolean
NestService.snipsDisabled(): boolean
NestService.unlock(player: Player, kind: string, id: string)
NestService.grantTemporary(player: Player, kind: string, id: string)
NestService.hasUnlock(player: Player, kind: string, id: string): boolean
```

- Attribution : dès `PlayerAdded` ; Nid libre le plus proche (distance entre centres) de celui d'un ami Roblox présent (`player:IsFriendsWith(id)` en `pcall`, mis en cache), sinon le plus petit slot libre. Plus de Nid libre (ne devrait pas arriver avec 12 places) : slot 0, le joueur peut se promener mais rien ne se déclenche ; `Feedback` d'information.
- `teleportHome` et chaque `CharacterAdded` : `PivotTo(WorldLayout.nestCFrame(slot) + 3 studs)` tourné vers le centre, puis `Signals.ServerMoved`.
- Réglages : remote `SetSetting` (§10.1) ; Zen : dans son port sûr, recharge `Config.Settings.zen.cooldown` (60 s) ; activer Zen en portant la Comète la fait tomber (EventService écoute `SettingChanged`) ; `privateNoSnip` : réglage de serveur en mémoire (`snipsDisabled()`), réservé au propriétaire du serveur privé ; Analytics `ZenToggled`.
- Cosmétiques : remote `EquipCosmetic` ; `hasUnlock` vrai si : source `free` ; stocké dans `unlocks` ; pass possédé (`MonetizationService.ownsPass`) ; `supernova` atteint ; `stat` du profil ≥ n ; déblocage temporaire de session. `unlock` stocke et envoie `Celebrate "unlock"`.
- Constellation : sur `Signals.Supernova` et au chargement, attribut `Supernovas` (Nid et joueur).

Signaux : émet `PlayerReady`, `ServerMoved`, `SettingChanged` ; écoute `Supernova`. Remotes : `SetSetting`, `EquipCosmetic`. Clés : `settings`, `cosmetics`, `unlocks`. Dépendances : DataService, MonetizationService, WorldService, `Logic/WorldLayout`.

### 11.5 EconomyService (paquet economy) — GDD §4.1, §4.9-§4.12, §7.2

```lua
EconomyService.Init()
EconomyService.Start()
EconomyService.step(now: number)
EconomyService.settle(player: Player): number
EconomyService.refreshRate(player: Player)
EconomyService.idleRate(player: Player): number
EconomyService.multiplier(player: Player): number
EconomyService.addGlow(player: Player, amount: number, sku: string, txType: string?): number
EconomyService.addGlowSeconds(player: Player, seconds: number, sku: string, minGlow: number?): number
EconomyService.trySpendGlow(player: Player, amount: number, sku: string): boolean
EconomyService.addStardust(player: Player, amount: number, sku: string, txType: string?): number
EconomyService.addStardustCapped(player: Player, amount: number, capKey: string, sku: string): number
EconomyService.trySpendStardust(player: Player, amount: number, sku: string): boolean
EconomyService.paradeGlow(player: Player, codes: { Types.NebbyCode }, atBeacon: boolean): number
EconomyService.upgradeLevel(player: Player, track: Types.UpgradeTrack): number
EconomyService.supernovas(player: Player): number
EconomyService.supernovaPreview(player: Player): Types.SupernovaPreview
EconomyService.grantPersonalBoost(player: Player, seconds: number)
EconomyService.hasBoost(player: Player): boolean
EconomyService.setServerBoostUntil(t: number)
EconomyService.setCrewPresent(player: Player, count: number)
EconomyService.setLineBanker(fn: (Player) -> ())
```

- **Règlement paresseux** : `settle` = `Formulas.settle(glow, glowCarry, idleRate, now − lastSettle)` ; met `lastSettle = now`, `lastOnline = Clock.unix()` ; émet `Signals.IdleSettled` ; analytics `Idle` cumulée par tranche de 5 min. `step(now)` règle chaque joueur toutes les 30 s (décalage = index du joueur × 30 / nombre de joueurs).
- **Taux** : `idleRate = perchIncome × M` avec `M = Formulas.multiplier { supernovas, vip = ownsPass("VIPStar"), crewPresent (poussé), doubleGlow = ownsPass("DoubleGlow"), boost = personalUntil > now or serverBoostUntil > now }` ; `refreshRate` met à jour la clé répliquée `idleRate` et émet `RateChanged`. Les fins de boost sont détectées dans `step` (settle à l'instant de fin, puis taux recalculé).
- **Hors ligne** (sur `Loaded`) : `Formulas.offlineGlow(perchIncome × Formulas.offlineMultiplier(R, vip, doubleGlow), Clock.unix() − lastOnline, nightShift)` ; crédit (`Offline`), puis écran de retour si gain ≥ `ReturnMinRatio` × coût de la prochaine Supernova ou ≥ `ReturnMinGlow` → `Notify.celebrate(player, "offline", { glow, seconds, nightShift })`. Premier chargement (`lastOnline == 0`) : aucun gain.
- **Améliorations** : remote `BuyUpgrade` (§10.1) → niveau + 1, `Signals.UpgradeBought`, `Notify.celebrate "upgrade"`, analytics `Upgrade_<piste>_<niveau>` (Shop).
- **Supernova** : remote `Supernova` (§10.1) → crochet `lineBanker(player)` (parade forcée) → `settle` → coût → `glow = 0`, `glowCarry = 0`, `upgrades.conga/stride/lure = 0` (`ResetOnSupernova`), `supernovas += 1` → `refreshRate` → `Signals.Supernova(player, R)`, `Notify.banner("supernova", { userId, name, level })`, `Notify.celebrate "supernova"`, analytics `Supernova_<R>` (Gameplay) et `SupernovaReached`.
- **Stardust** : `addStardustCapped` remet `caps` à zéro au changement de jour UTC, accorde `min(amount, plafond − déjà)` et renvoie l'accordé (0 → `Feedback capReached` à la charge de l'appelant).
- **Boosts** : personnels `personalUntil = max(now, personalUntil) + seconds` (jamais de cumul ×4) ; de serveur poussés par EventService.
- `paradeGlow` = `Formulas.paradeGlow(codes, M, isZen, atBeacon)` (M au moment de la parade).
- Analytics (§14.2) : chaque crédit/débit avec `itemSku` fourni par l'appelant (`Parade`, `ParadeBeacon`, `Comet`, `Wisp`, `Quest_<id>`, `Login_D<n>`, `Code_<code>`, `Product_<clé>`, `Release_<rareté>`, `Snip`, `Beacon`, `Cheer`, `Duo`, `Starforge_<★>`).

Signaux : émet `UpgradeBought`, `Supernova`, `IdleSettled`, `RateChanged`. Remotes : `BuyUpgrade`, `Supernova`. Clés : `glow`, `glowCarry`, `lastSettle`, `lastOnline`, `idleRate`, `stardust`, `supernovas`, `upgrades`, `boosts`, `caps`. Dépendances : DataService, MonetizationService, NestService, `Logic/Formulas`.

### 11.6 AtlasService (paquet economy) — GDD §4.9, §4.13, §4.14

```lua
AtlasService.Init()
AtlasService.Start()
AtlasService.addNebbies(player: Player, codes: { Types.NebbyCode }, source: string, stars: number?): { Types.Uid }
AtlasService.record(player: Player, uid: Types.Uid): Types.NebbyRecord?
AtlasService.perched(player: Player): { Types.Uid }
AtlasService.perchCount(player: Player): number
AtlasService.stashCap(player: Player): number
AtlasService.atlasCount(player: Player): number
AtlasService.hasEntry(player: Player, s: number, f: number): boolean
AtlasService.refreshPerches(player: Player)
AtlasService.fuse(player: Player, uid: Types.Uid): (boolean, string?)
AtlasService.fuseAll(player: Player): number
AtlasService.release(player: Player, uids: { Types.Uid }): number
AtlasService.setLock(player: Player, uid: Types.Uid, locked: boolean): boolean
```

- `addNebbies` (après `EconomyService.settle`) : crée les enregistrements `{ s, f, v, st = 1 }` (uid `"u" .. nextUid`) ; nouvelles entrées d'Atlas (bit `Nebbies.atlasIndex`) et badges (`badgeIndex`) → `Celebrate "atlasNew"`, `Signals.AtlasEntry` ; jalons atteints (`Config/Quests.Atlas`) réclamés automatiquement (perchoirs, `NestService.unlock` pour titre/style/thème, `Celebrate "atlasMilestone"`, bannière personnelle) ; espèce complète (toutes les formes activées) → +100 Stardust, `Celebrate "speciesComplete"` ; tri des perchoirs ; débordement de la réserve (§4.9) ; `refreshRate`.
- Tri des perchoirs : revenu passif décroissant (`Formulas.passiveIncome`), égalité → rareté, puis uid ; `perchIncome` = Σ des perchés ; `NestService.setPerchCount(player, perchCount)` et `setPerchDisplay(player, entries)` ; `Signals.PerchesChanged` si le nombre change.
- Recalcul sur `Signals.UpgradeBought` (piste `perches`), `MonetizationService.PassGranted` (`ExtraPerches`, `StashPlus`) et jalons.
- Starforge : `fuse(uid)` consomme 2 autres Nebbies identiques (même s, f, v, st) non verrouillés (le choisi peut l'être), Stardust `Formulas.fuseCost(st)` ; `fuseAll` boucle en prenant d'abord la fusion qui augmente le plus le revenu perché, tant que la Stardust suffit ; `Signals.Fused`, `Celebrate "starforge"`, analytics `Starforge_<★>`.
- `release(uids)` : tout ou rien (§10.1) ; Stardust = Σ `Formulas.releaseDust` ; `Feedback released`, `Celebrate "release"`.

Signaux : émet `PerchesChanged`, `AtlasEntry`, `Fused` ; écoute `UpgradeBought`, `PassGranted`. Remotes : `Fuse`, `FuseAll`, `Release`, `SetLock`. Clés : `nebbies`, `nextUid`, `perchIncome`, `atlas`, `badges`, `atlasRewards`. Dépendances : DataService, MonetizationService, NestService, EconomyService, `Logic/Formulas`.

### 11.7 SpawnService (paquet conga) — GDD §3, §4.3-§4.5, §4.15.2, §4.15.5

```lua
SpawnService.Init()
SpawnService.Start()
SpawnService.step(now: number)
SpawnService.setModifiers(mods: Types.SpawnModifiers)
SpawnService.setActivePlayers(n: number)
SpawnService.query(pos: Vector3, radius: number, now: number, player: Player?): { Types.WildNebby }
SpawnService.positionOf(wild: Types.WildNebby, now: number): Vector3
SpawnService.canCatch(player: Player, slot: number, wild: Types.WildNebby, now: number): boolean
SpawnService.consume(id: number, player: Player): Types.WildNebby?
SpawnService.spawnLoose(codes: { Types.NebbyCode }, from: { Vector3 }, now: number, opts: LooseOptions?): { Types.WildSpawn }
SpawnService.spawnPersonal(player: Player, code: Types.NebbyCode, pos: Vector3, life: number?): number
SpawnService.spawnWelcome(player: Player): { number }
SpawnService.spawnGuaranteedRare(player: Player): number?
SpawnService.setDirected(player: Player, enabled: boolean)
SpawnService.flush(now: number, urgent: boolean?)
SpawnService.snapshotFor(player: Player): { Types.WildSpawn }
SpawnService.clearPlayer(player: Player)
SpawnService.aliveCount(zoneKey: string?): number
SpawnService.toSpawn(wild: Types.WildNebby): Types.WildSpawn
```

- Apparitions : à chaque intervalle de zone (`zone.interval / mods.intervalDiv`), si `aliveCount(zone) < Formulas.effectiveCap(zone.cap, actifs, mods.capMult)` : rareté (`Hash`/`Random` serveur), espèce uniforme activée, forme météo (probabilité `mods.formChance`), espèce vedette (`mods.featured`, `featuredChance`) dont Starborn (`starbornChance`), Golden 1 %, Huge 0,5 % ; point de `WorldLayout.spawnPoints(zone)` à ≥ 6 studs des sauvages (10 essais) ; `seed` aléatoire serveur, `t0 = now`, durée de vie de la zone. Le hasard serveur peut utiliser `Random.new()` (aucune exigence de déterminisme entre serveurs ; seule la flânerie l'est).
- Position : `anchor + SeededPath.wander(seed, now − t0)` (les libres : à leur point d'atterrissage, après l'arc de `Snip.ScatterTime`).
- `canCatch` : `onlyFor` (0 ou ce joueur), étourdi (`dizzyUntil > now` sauf si `prioritySlot == slot`), plafond de groupe.
- Libres : `spawnLoose` disperse chaque Nebby avec `SeededPath.scatterPoint` puis `WorldLayout.clampToIsland` ; `silent = true` pour ceux qui voyagent dans LineEvent/SnipEvent.
- Personnels : jamais comptés dans les plafonds ; `WildEvent` au seul joueur ; `spawnGuaranteedRare` une fois par compte (QuestService le décide).
- `flush` : `WildEvent` à tous (publics) et à chaque joueur (personnels), au plus toutes les `Spawn.WildEventInterval` (0,25 s) sauf `urgent`.

Signaux : — . Remotes : émet `WildEvent`. Clés : — . Dépendances : NestService, `Logic/{WorldLayout,SeededPath,Formulas,Hash}`, Config.

### 11.8 EventService (paquet events) — GDD §2.4, §4.15, §7.6

```lua
EventService.Init()
EventService.Start()
EventService.step(now: number)
EventService.stepComet(now: number, actors: { Types.Actor })
EventService.wispSweeps(now: number): { WispSweep }
EventService.onWispSnip(wispId: number, victim: Player, count: number)
EventService.stepWisps(now: number, actors: { Types.Actor })
EventService.flush()
EventService.isTruce(): boolean
EventService.beaconOpen(): boolean
EventService.onBeaconParade(player: Player, count: number)
EventService.isCarrier(player: Player): boolean
EventService.carrier(): Player?
EventService.dropComet(player: Player)
EventService.weatherForm(): number?
EventService.serverBoostActive(): boolean
EventService.queueGlowParty(buyer: Player, seconds: number): number
EventService.glowPartyRemaining(): number
EventService.setActivePlayers(n: number)
EventService.runLiveOps(command: string)
EventService.snapshot(): Types.EventStatePayload
```

- **Phases** dérivées de `EventClock` à chaque `step(now)` (et forçables par LiveOps) ; à chaque transition : `Notify.banner` (`weather`, `cometWarn`, `beaconStart`, `starfall`…), `Signals.EventPhase(event, phase)`, `SpawnService.setModifiers` (météo : `form`, `formChance = Balance.Spawn.WeatherFormChance` ; Meteor : `intervalDiv ×3`, `capMult ×1,5` ; Frenzy : `÷4`, `×2` ; Starfall : `featured`, chances), `EconomyService.setServerBoostUntil`.
- **Comète** : phases `warn` (−8 s) → `ground` (impact `EventClock.cometImpact(id)`, contenu `EventClock.cometContent(id)`, forme = météo active à l'impact) → `carried` → `banked` | `burst` (`impactAt + 75`). Ramassage : premier acteur `valid`, non Zen, à ≤ `PickupRadius` (XZ) ; vol : acteur `valid` non équipier dont le balayage passe à ≤ `StealRadius` du porteur (`Trail.segmentDistanceXZ` entre les deux balayages), sauf immunité du nouveau porteur (2 s) et interdiction de reprise de l'ancien (4 s) ; encaissement : porteur dans `WorldLayout.inGateBox(son slot)` → `AtlasService.addNebbies({code}, "comet")`, `EconomyService.addGlowSeconds(120)`, bannière, `Celebrate "cometBanked"` ; explosion : 5 Épiques libres (`SpawnService.spawnLoose` au point, `group = "burst:<id>"`, `groupCap = 1`). Récompenses de participation et équipiers (§4.15.2), `Signals.CometParticipation` / `CometHeld` / `CometEvent`, analytics `CometHeld`, `CometBanked`, `CometBurst`. Le porteur est ralenti (×0,85) et privé de Dash par CongaService (`isCarrier`).
- **Balise** : `warn` (−15 s), `active` (trêve : `isTruce()`, `beaconOpen()`), barre `points / goal` (`Formulas.beaconGoal(actifs, échecs consécutifs)` figé au début), contributeurs ; réussite immédiate quand `points ≥ goal` (`success`) → Frenzy 60 s → Nuit d'Or 5 min (boost) ; échec à la fin ; récompenses (+40 / +15 Stardust par contributeur), bannière du meilleur contributeur, `Signals.BeaconResult`, analytics `BeaconResult`.
- **Gloomwisps** : `Formulas.wispCount(actifs, balise ou Starfall)` ; chacun `{ id, seed, t0 }` ; position `SeededPath.chordAt` ; `wispSweeps` donne le balayage depuis le tick précédent (vide pendant la trêve) ; `stepWisps` éclate ceux dont un acteur `valid` passe à ≤ `PopRadius` (+10 Stardust plafonnée `wispDust`, 20 s de revenu, `Signals.WispPopped`, analytics `WispPopped`) ; réapparition 10 s plus tard avec une nouvelle `seed`.
- **Starfall Saturday** : comètes toutes les 3 min (EventClock), Rainbow, boost 20 min, présence par joueur ≥ 5 min → Nebby vedette Starborn (`AtlasService.addNebbies`, source `"starfall"`) à la fin.
- **Boost de serveur** : une seule échéance `serverBoostUntil` ; Nuit d'Or et Starfall : `max(fin, now + durée)` ; Glow Party : `max(now, fin) + secondes` ; `EventState.serverBoost`.
- **LiveOps** : remote `AdminCommand` (§10.1) → `MessagingService:PublishAsync(Events.LiveOps.Topic, { cmd, at })` en `task.spawn` + exécution locale ; `SubscribeAsync` au démarrage (pcall) → `runLiveOps` ; attribut `Admin`.
- `flush` envoie `EventState` (état complet) si quelque chose a changé ; `snapshot()` pour WorldSnapshot.

Signaux : émet `EventPhase`, `CometEvent`, `CometParticipation`, `CometHeld`, `WispPopped`, `BeaconResult` ; écoute `SettingChanged` (Zen → `dropComet`). Remotes : `AdminCommand` ; émet `EventState`. Clés : — (mémoire). Dépendances : DataService, NestService, EconomyService, AtlasService, SpawnService, `Logic/{EventClock,SeededPath,Formulas,Trail,WorldLayout}`, `Data/Admins`.

### 11.9 CrewService (paquet events) — GDD §6.1-§6.3, §6.5, §6.6

```lua
CrewService.Init()
CrewService.Start()
CrewService.step(now: number)
CrewService.crewOf(player: Player): number
CrewService.areCrewmates(a: Player, b: Player): boolean
CrewService.crewmates(player: Player): { Player }
CrewService.escortersOf(victim: Player): { Player }
CrewService.banner(kind: Types.BannerKind, args: { [string]: any }, source: Player?)
CrewService.snapshot(): Types.CrewStatePayload
```

- Équipages (mémoire, ids croissants) de 4 au plus ; amis Roblox présents regroupés automatiquement si les deux ont `autoCrew` ; invitations (§10.1) ; un départ du serveur retire le joueur ; un équipage d'un seul membre est dissous. À chaque changement : `CrewState` à tous, attribut `CrewId`, `Signals.CrewChanged`, `EconomyService.setCrewPresent(membre, n)` pour chaque membre (équipiers présents et actifs, ≤ 3), analytics `CrewFormed`.
- Pings → `PingShow`. Acclamations : sur `Signals.Supernova`, `CheerPrompt { heroId, level, expiresAt = now + 10 }` à tous sauf le héros ; `Cheer` accepté une fois par acclameur et par Supernova ; +5 Stardust plafonnée (`cheers`) ; `Signals.Cheered` ; à la fermeture de la fenêtre, `Feedback cheersReceived {n}` au héros.
- Bannières : abonné à `Signals.BannerRequested` ; règles §10.3 ; `Banner` à tous.
- Cadeau Duo : temps cumulé par paire d'amis présents (step), à 600 s → 50 Stardust à chacun si `caps.duo` est faux (`addStardustCapped(…, "duo", "Duo")`), `Feedback duoGift`.

Signaux : émet `CrewChanged`, `Cheered` ; écoute `BannerRequested`, `Supernova`, `SettingChanged`. Remotes : `CrewInvite`, `CrewRespond`, `CrewLeave`, `Ping`, `Cheer` ; émet `CrewState`, `CrewInvitePrompt`, `CheerPrompt`, `PingShow`, `Banner`. Clés : — . Dépendances : DataService, NestService, EconomyService.

### 11.10 QuestService (paquet events) — GDD §3, §4.16, §7.3-§7.5, §14.1

```lua
QuestService.Init()
QuestService.Start()
QuestService.step(now: number)
QuestService.isRookie(player: Player): boolean
QuestService.onSafeMoment(player: Player)
QuestService.onboardingStep(player: Player): number
QuestService.drawDaily(userId: number, day: number, zen: boolean, crewRecent: boolean): { number }
QuestService.redeem(player: Player, code: string): string
```

- Progression : abonné aux signaux du §7 ; table de correspondance `goal.kind` → signal dans l'en-tête de `Config/Quests.luau`. Accueil : une quête à la fois (`onboarding.step`, progression `onboarding.p`), récompense automatique à la complétion, `Celebrate "questDone"`, étape d'entonnoir ; au premier `PlayerReady` (`step == 0`) : `SpawnService.spawnWelcome`, `setDirected(true)` jusqu'à la fin de Q3, `step = 1`. Q4 : `spawnGuaranteedRare` à son début (une fois). Q6 : capture d'une forme météo ou `CometParticipation`.
- Entonnoir (`Analytics.funnel`, §14.1) : 1 sur `PlayerReady` (première session), 2 premier `Caught`, 3 première `Parade`, 4 premier `UpgradeBought`, 5-9 quêtes Q1/Q3/Q4/Q5/Q6, 10 première `Supernova`.
- Quotidiennes : `drawDaily(userId, day, zen, crewRecent)` = pour chaque niveau (`DailyTierOrder`), `Hash.int` sur le pool filtré, sans doublon ; tirage fait au premier accès du jour ; relance = `Hash(day, userId, rerolls, slot)` dans le même niveau ; récompenses (`DailyTiers`) via EconomyService (`Quest_<id>`) ; les 3 réclamées → `DailyStar` (boost).
- Hebdo : `weekly.banked` sur `Parade` ; réclamation → Légendaire de la semaine (`EventClock.rotation("GrandParadeLegendary", Clock.week())`) + 300.
- Calendrier : `ClaimDaily` → `Calendar[daily.step]`, `daily.step = step % 7 + 1`, `daily.day = Clock.day()` (pas de remise à 1 si un jour est manqué).
- Codes : `Data/Codes`, `codes[CODE] = true`.
- Bouclier : actif tant que `rookie.done == false` et `Formulas.rookieEligible(sessions, playSeconds, R)` ; quand il devient inéligible, fin différée au prochain `onSafeMoment` → `rookie.done = true`, attribut `Rookie = false`, `Notify.personalBanner "rookieEnd"`, `Signals.RookieEnded`, analytics `RookieShieldEnded`.
- `step` : temps de jeu (`stats.playSeconds`, `rookie.playSeconds`), changements de jour, échéance du bouclier.
- Titres de statistiques (`Cosmetics.Titles`, source `stat`) → `NestService.unlock`.

Signaux : émet `RookieEnded` ; écoute la plupart des signaux §7. Remotes : `ClaimDaily`, `ClaimQuest`, `RerollQuest`, `RedeemCode`. Clés : `onboarding`, `daily`, `quests`, `weekly`, `rookie`, `stats`, `codes`. Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService, SpawnService, EventService, CrewService, `Logic/{Hash,Formulas,EventClock}`, `Data/Codes`.

### 11.11 ProductService (paquet economy) — GDD §8

```lua
ProductService.Init()
ProductService.Start()
ProductService.glowAmount(player: Player, productKey: string): number
ProductService.grant(player: Player, productKey: string): boolean
```

- `Init` : `MonetizationService.registerProduct(clé, function(player, data) return ProductService.grant(player, clé) end)` pour chaque produit de la config (même à id 0). Un handler ne retourne `true` que si l'effet est appliqué (profil chargé) — MonetizationService gère l'idempotence et la sauvegarde.
- Glow : `EconomyService.addGlowSeconds(player, idleSeconds, "Product_<clé>", minGlow)` (montant calculé à l'attribution). GlowParty : `EventService.queueGlowParty(player, 600)` + `Notify.banner("glowParty", …)` + `Feedback glowPartyQueued`. StardustJar : +400. StarterKit : `AtlasService.addNebbies(Named.StarterKit, "product")`, `NestService.unlock(player, "styles", "comet_tail")`, boost 20 min, `starterKit = true`.
- Passes (`PassGranted`) : VIPStar, DoubleGlow → `EconomyService.settle` + `refreshRate` (+ attribut VIP par NestService) ; ExtraPerches, StashPlus → `AtlasService.refreshPerches` ; NightShift, CongaStyles : lus dynamiquement.
- `Celebrate "purchase"` ; analytics IAP `Product_<clé>`.

Signaux : écoute `PassGranted`. Remotes : — . Clés : `starterKit`. Dépendances : DataService, MonetizationService, NestService, EconomyService, AtlasService, EventService.

### 11.12 LeaderboardService (paquet events) — GDD §6.4, §6.7

```lua
LeaderboardService.Init()
LeaderboardService.Start()
LeaderboardService.step(now: number)
LeaderboardService.liveTop(): { BoardEntry }
LeaderboardService.serverRecord(): BoardEntry?
LeaderboardService.weeklyTop(): { BoardEntry }
```

- Direct : top `TopLive` (5) des files en cours (sur `LineChanged`), rafraîchi chaque seconde ; record de parade du serveur (sur `Parade`, bannière `serverRecord` si battu) ; attributs de la stèle `WorldService.board()` : `Live`, `Record`, `Weekly` au format `"userId:name:n;…"`.
- Hebdo : `weeklyBest` (semaine `Clock.week()`) ; record battu → file d'écriture `OrderedDataStore("WeeklyConga_" .. week)` vidée toutes les 60 s ; `AtlasAllTime` sur `AtlasEntry` ; lecture du top 10 toutes les 120 s ; tout appel DataStore en `task.spawn` + `pcall` + nouvelles tentatives ; jamais pour `flags.lbBanned`.
- Arrivée : top 10 de la semaine précédente → `NestService.grantTemporary(player, "titles", "conga_royal")`.

Signaux : écoute `LineChanged`, `Parade`, `AtlasEntry`. Remotes : — . Clés : `weeklyBest`. Dépendances : DataService, WorldService, NestService.

### 11.13 CongaService (paquet conga) — GDD §4.5-§4.8, §4.16, §12.3, §12.4, §12.7

```lua
CongaService.Init()
CongaService.Start()
CongaService.tick(now: number)
CongaService.lineLength(player: Player): number
CongaService.lineCodes(player: Player): { Types.NebbyCode }
CongaService.lineCapacity(player: Player): number
CongaService.nodePositions(player: Player): { Vector3 }
CongaService.forceParade(player: Player): number
CongaService.isActive(player: Player): boolean
CongaService.activeCount(): number
CongaService.inputType(player: Player): number
CongaService.worldSnapshot(player: Player): Types.WorldSnapshotPayload
```

État par joueur : slot, `trail` (`Trail.new(170, 0.5)`), `netTrail` (`Trail.new(170, 1.0, firstSeq)`), nœuds (`{ LineNode }`), version de file, recharges (Dash, coupe, paires), immunité et coupes récentes de victime, Second Souffle, Snip Rush, compteur de captures horaire, type d'entrée, temps d'escorte, activité (distance sur 60 s).

- **Positions des nœuds** : `trail:sample(n, Spacing, HeadGap)` (abscisse curviligne, aucune spirale à l'arrêt).
- **Captures** (étape 5) : rayon `Formulas.lureRadius(lure, rush) + LatencyTolerance`, `|Δy| ≤ MaxDy` ; capacité `Formulas.congaCapacity(conga)` ; file pleine → `Feedback lineFull` (≤ 1 / 5 s) ; reprise d'un Nebby libre prioritaire → `CatchInfo.recovered`, `Feedback recovered` ; 1 500 captures / h → suspension 5 min + `flags.lbBanned` ; bannière `mythicCatch` / `legendaryCatch` (rareté ≥ 5, avec `Rarities.banner`).
- **Coupes** (étape 7) : `SnipRules.blockReason` avec l'état ; `SnipRules.findCut` (rayon `SnipRules.radius(touch, isWisp)`) ; `c = SnipRules.cutFrom(k, n)` ; nœuds c…n retirés ; `SpawnService.spawnLoose(codes, positions, now, { prioritySlot = victime, silent = true })` ; `SnipRules.applyCut` (immunité, coupes récentes, attribut `ImmuneUntil`) ; recharges coupeur (1,5 s) et paire (20 s) ; Second Souffle victime (+4, 3 s) ; Snip Rush coupeur (Attrait ×1,5, 3 s) ; Stardust `RushDustPerNebby × count` via `addStardustCapped(…, "snipDust", "Snip")` sauf coupeur sous bouclier (Feedback `rookieNoDust`) ; `SnipEvent` ; `Feedback snipped` (victime), `snipDealt` (coupeur) ; `Signals.Snipped` ; analytics `SnipDealt`, `SnipReceived`, `SnipByInput`, et `PostSnipQuit` si la victime part < 60 s après ; file vide → `QuestService.onSafeMoment`.
- **Parades** (étape 9) : `glow = EconomyService.paradeGlow(player, codes, atBeacon)` → `EconomyService.addGlow(…, atBeacon and "ParadeBeacon" or "Parade")` → `AtlasService.addNebbies(codes, "parade")` → si `atBeacon` : `EventService.onBeaconParade(player, n)` → `LineEvent bank` → `Signals.Parade` (avec `idleSeconds = glow / idleRate`) → `n ≥ MegaParade` : bannière `megaParade` → `QuestService.onSafeMoment` → analytics `ParadeLength`. `forceParade` fait la même chose sans test de porte (`forced = true`).
- **WalkSpeed** : `Formulas.walkSpeed { stride, n, guard = Formulas.guardLinks(guard), carrier = EventService.isCarrier, dashing, secondWind }`. Dash : remote `Dash` → `DashReadyAt = now + Formulas.dashCooldown(R)`, `Signals.Dashed`.
- **Mort / départ / Supernova** : `LineEvent clear` (`death` : libres prioritaires pour le propriétaire ; `leave` : sans priorité). La Supernova encaisse la file par `forceParade` (op `bank` normale, `ParadeInfo.forced = true`) : la raison `supernova` reste dans le contrat mais n'est jamais envoyée ; `reset` seulement si le slot d'un joueur change alors qu'il a une file (cas anormal).
- **Diffusion** : §10.4-§10.6. `RequestWorld` → `worldSnapshot(player)`. `RequestPath(slot)` → `PathSnapshot`.
- **MoveCheck** : §11.14 ; analytics `MoveViolation` (au départ, nombre de la session).
- `Init` pose `EconomyService.setLineBanker(CongaService.forceParade)`.

Signaux : émet `Caught`, `LineChanged`, `Parade`, `Snipped`, `Dashed`, `EscortTime`, `MoveViolation` ; écoute `ServerMoved`, `PlayerReady`. Remotes : `Dash`, `SetInputType`, `RequestWorld`, `RequestPath` ; émet `PathStream`, `PathSnapshot`, `WorldSnapshot`, `LineEvent`, `SnipEvent`. Clés : `flags`. Dépendances : tous les services précédents, `Util/MoveCheck`, `Logic/*`.

### 11.14 MoveCheck (paquet conga) — GDD §12.7

```lua
MoveCheck.reset(player: Player, pos: Vector3, now: number)
MoveCheck.noteSpeed(player: Player, walkSpeed: number, now: number)
MoveCheck.step(player: Player, pos: Vector3, dt: number, now: number, groundY: number): (Verdict, Vector3?)
MoveCheck.isRestricted(player: Player, now: number): boolean
MoveCheck.lastValid(player: Player): Vector3?
MoveCheck.violations(player: Player): number
MoveCheck.recentRewinds(player: Player, now: number): number
MoveCheck.clear(player: Player)
```

Module d'état pur (pas de service Roblox) : CongaService fournit positions, `dt`, `now`, hauteur du sol et WalkSpeed. Règles exactes dans l'en-tête du stub et `Balance.MoveCheck`. Jamais d'accusation : seul l'attribut `Unstable` (icône neutre) est montré.

---

## 12. Modules partagés purs (API)

Aucun service Roblox, aucune lecture d'horloge (le temps est un paramètre), aucune Instance (sauf `NebbyBuilder`, qui crée des Instances sans les parenter). Testés sous Lune. Mêmes résultats sous Lune et sous Roblox (pas de `math.random` ; `Random.new(seed)` interdit dans les modules déterministes : utiliser `Hash`).

### 12.1 `Shared/Logic` (paquet logic, sauf `PathCodec` : conga)

**Hash** — PRNG entier déterministe (GDD §4.15.1, §7.5). Valeurs de référence figées dans `Hash.spec`.

```lua
Hash.u32(...: number): number
Hash.unit(...: number): number
Hash.int(min: number, max: number, ...: number): number
Hash.range(min: number, max: number, ...: number): number
Hash.pickWeighted(weights: { number }, r: number): number
Hash.string(s: string): number
Hash.stream(seed: number): Stream
```

**EventClock** — phases à l'instant t (GDD §2.4, §4.15). Types exportés : `WeatherWindow`, `CometSlot` (`id = impactAt`), `BeaconWindow`, `StarfallWindow`, `NextEvent`.

```lua
EventClock.day(t: number): number
EventClock.week(t: number): number
EventClock.weekday(t: number): number
EventClock.weatherKeyForSlot(slot: number): string
EventClock.weather(t: number): WeatherWindow?
EventClock.nextWeather(t: number): WeatherWindow
EventClock.comet(t: number): CometSlot?
EventClock.nextComet(t: number): CometSlot
EventClock.cometImpact(id: number): Vector3
EventClock.cometContent(id: number): (number, number)
EventClock.beacon(t: number): BeaconWindow?
EventClock.nextBeacon(t: number): BeaconWindow
EventClock.starfall(t: number): StarfallWindow?
EventClock.nextStarfall(t: number): StarfallWindow
EventClock.nextEvent(t: number): NextEvent
EventClock.featuredSpecies(week: number): number
EventClock.weeklyWanderer(week: number): number
EventClock.grandParadeLegendary(week: number): number
EventClock.rotation(name: string, week: number): number
```

Règles : météo `slot = floor(t / 360)`, active sur `[slot×360 + 120 ; slot×360 + 270[`, clé tirée par `Hash.unit(slot, Events.Salts.Weather)` contre les poids cumulés des météos activées (somme normalisée) ; pendant Starfall : `rainbow` sur toute la fenêtre du show. Comète : impact à chaque multiple de 600, `warnAt = impactAt − 8`, `burstAt = impactAt + 75` ; pendant Starfall (samedi 16:00-16:20) : impacts à 16:00, 16:03 … 16:18 et aucun impact normal dans la fenêtre. Balise : `startsAt = k × 1800 + 1500`, durée 180, alerte 15 s, aucune pendant Starfall. Le planning est **identique sur tous les serveurs**.

**SeededPath** — trajectoires déterministes (GDD §4.3, §4.15.4). Type `ChordCursor`.

```lua
SeededPath.wander(seed: number, dt: number): Vector3
SeededPath.chordAt(seed: number, t0: number, t: number): (Vector3, Vector3)
SeededPath.newChordCursor(seed: number, t0: number): ChordCursor
SeededPath.cometSky(id: number, impact: Vector3, alpha: number): Vector3
SeededPath.scatterPoint(seed: number, index: number, origin: Vector3): Vector3
```

**WorldLayout** — géométrie de Lumora (GDD §4.3, §4.7, §4.8, §11). Types `DecorLayout`, `CrystalSpot`, `LanternSpot`. Slot 1-12 ↔ Nid k = slot − 1 à l'angle 30° × k ; `gateCFrame` regarde le centre ; `inGateBox` teste la boîte 12 × 10 × 4 dans le repère de la porte ; `harborSlot` < 25 studs (XZ) d'une porte ; `zoneAt` selon `Zones.List` ; `spawnPoints` mis en cache.

```lua
WorldLayout.radiusXZ(pos: Vector3): number
WorldLayout.nestCenter(slot: number): Vector3
WorldLayout.nestCFrame(slot: number): CFrame
WorldLayout.gateCFrame(slot: number): CFrame
WorldLayout.inGateBox(slot: number, pos: Vector3): boolean
WorldLayout.harborSlot(pos: Vector3): number?
WorldLayout.inHarbor(pos: Vector3): boolean
WorldLayout.inOwnHarbor(slot: number, pos: Vector3): boolean
WorldLayout.inBeaconRing(pos: Vector3): boolean
WorldLayout.zoneAt(pos: Vector3): string?
WorldLayout.groundY(x: number, z: number): number
WorldLayout.clampToIsland(pos: Vector3, margin: number?): Vector3
WorldLayout.spawnPoints(zoneKey: string): { Vector3 }
WorldLayout.perchCFrame(slot: number, index: number): CFrame
WorldLayout.welcomePoints(slot: number, count: number): { Vector3 }
WorldLayout.observatoryCFrame(slot: number): CFrame
WorldLayout.constellationPoint(slot: number, index: number): Vector3
WorldLayout.boardCFrame(): CFrame
WorldLayout.pathStones(): { Vector3 }
WorldLayout.lanterns(): { LanternSpot }
WorldLayout.decor(): DecorLayout
```

**SnipRules** — ordre unique des règles de coupe (GDD §4.7). Types `Party`, `PairInput`, `CutInput`. Raisons de `blockReason`, dans l'ordre : `"truce"`, `"disabled"`, `"self"`, `"crew"`, `"zen"`, `"rookie"`, `"immune"`, `"perMinute"`, `"snipperCooldown"`, `"pairCooldown"`, `"flagged"` ; `nil` = coupe possible. Pour un Gloomwisp (`isWisp`, `snipper = nil`) : pas de `self`/`crew`/`snipperCooldown`, mais Zen, bouclier, immunité et plafond par minute s'appliquent.

```lua
SnipRules.blockReason(input: PairInput): string?
SnipRules.isImmune(now: number, immuneUntil: number, recent: { number }): boolean
SnipRules.radius(touch: boolean, isWisp: boolean): number
SnipRules.lossCap(n: number): number
SnipRules.cutFrom(k: number, n: number): number
SnipRules.boundsOverlap(from: Vector3, to: Vector3, radius: number, nodes: { Vector3 }, firstIndex: number): boolean
SnipRules.findCut(input: CutInput): (number?, Vector3?)
SnipRules.applyCut(now: number, immuneUntil: number, recent: { number }): (number, { number })
```

**Formulas** — toutes les formules (GDD §4). Types `WalkSpeedParams`, `MultiplierParams`, `SettleResult`. Les tables de coûts du GDD §4.11 doivent être retrouvées au Glow près.

```lua
Formulas.upgradeCost(track: Types.UpgradeTrack, level: number): number
Formulas.upgradeMaxLevel(track: Types.UpgradeTrack, supernovas: number): number
Formulas.congaCapacity(congaLevel: number): number
Formulas.congaBonus(n: number, zen: boolean?): number
Formulas.guardLinks(guardLevel: number): number
Formulas.lureRadius(lureLevel: number, rush: boolean?): number
Formulas.baseWalkSpeed(strideLevel: number): number
Formulas.walkSpeed(p: WalkSpeedParams): number
Formulas.dashCooldown(supernovas: number): number
Formulas.nebbyMultiplier(f: number, v: number): number
Formulas.paradeValue(code: Types.NebbyCode): number
Formulas.passiveIncome(rec: Types.NebbyRecord): number
Formulas.multiplier(p: MultiplierParams): number
Formulas.offlineMultiplier(supernovas: number, vip: boolean, doubleGlow: boolean): number
Formulas.paradeGlow(codes: { Types.NebbyCode }, M: number, zen: boolean, atBeacon: boolean): number
Formulas.offlineGlow(rate: number, seconds: number, nightShift: boolean): (number, number)
Formulas.settle(glow: number, carry: number, rate: number, dt: number): SettleResult
Formulas.glowForSeconds(rate: number, seconds: number, minGlow: number?): number
Formulas.supernovaCost(supernovas: number): number
Formulas.auraFor(supernovas: number): string?
Formulas.atlasPerchMilestones(entries: number): number
Formulas.perchCount(perchLevel: number, atlasEntries: number, extraPerches: boolean): number
Formulas.stashCap(stashPlus: boolean): number
Formulas.fuseCost(stars: number): number?
Formulas.releaseDust(rarity: number, stars: number): number?
Formulas.capScale(activePlayers: number): number
Formulas.effectiveCap(baseCap: number, activePlayers: number, capMult: number): number
Formulas.beaconGoal(activePlayers: number, consecutiveFails: number): number
Formulas.wispCount(activePlayers: number, suppressed: boolean): number
Formulas.rookieEligible(sessions: number, playSeconds: number, supernovas: number): boolean
```

**Trail** (socle + extension logic) — miettes de chemin. Ajouts : `Trail.new(maxLength, minStep?, firstSeq?)`, champ `firstSeq`, et :

```lua
Trail.new(maxLength: number, minStep: number?): Trail
Trail.reset(self: Trail, position: Vector3)
Trail.setMaxLength(self: Trail, maxLength: number)
Trail.head(self: Trail): Vector3?
Trail.push(self: Trail, position: Vector3)
Trail.sample(self: Trail, count: number, spacing: number, firstGap: number?): { Vector3 }
Trail.findCut(positions: { Vector3 }, intruders: { Vector3 }, radius: number, fromIndex: number, maxHeightDifference: number?): (number?, number?)
Trail.lastSeq(self: Trail): number
Trail.since(self: Trail, seq: number, maxCount: number?): (number, { Vector3 })
Trail.segmentDistanceXZ(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3): (number, number, number)
Trail.findCutSwept(nodes: { Vector3 }, from: Vector3, to: Vector3, radius: number, firstSegment: number, maxDy: number?, skip: ((k: number, point: Vector3) -> boolean)?): (number?, Vector3?)
```

`push` attribue le numéro suivant à chaque point ajouté ; le retrait des vieux points avance `firstSeq` ; `reset` (saut ≥ 40 studs) continue la numérotation. `findCutSwept` ne doit rater **aucun** segment à 3,6 studs par tick (vitesse de Dash). Le comportement existant (`push`, `sample`, `findCut`) et `Trail.spec` restent inchangés.

**PathCodec** (paquet conga) — §10.4. Constantes `MAX_POINTS = 255`, `MAX_RUNS = 255`, `ABS_SCALE = 8`, `DELTA_SCALE = 16`, `HEADER_BYTES = 3`, `RUN_HEADER_BYTES = 12`, `DELTA_BYTES = 3`.

```lua
PathCodec.encode(tick: number, runs: { Types.PathEntry }): buffer
PathCodec.decode(buf: buffer): (number, { Types.PathEntry })
PathCodec.split(slot: number, firstSeq: number, points: { Vector3 }): { Types.PathEntry }
PathCodec.size(runs: { Types.PathEntry }): number
```

### 12.2 `Shared/Render/NebbyBuilder` (paquet world) — GDD §5.2, §4.2, §4.4, §11.6

Constructeur pur de modèles (≤ 8 pièces en détail complet), utilisé par le client (CongaRenderer, panneaux). Types `Lod = "full" | "ball" | "hidden"`, `BuildOptions`, `AnimState`, `Rig` (pièces + décalages pour un seul `BulkMoveTo`).

```lua
NebbyBuilder.build(code: Types.NebbyCode, stars: number, lod: Lod, opts: BuildOptions?): Rig
NebbyBuilder.setLod(rig: Rig, lod: Lod): Rig
NebbyBuilder.animate(rig: Rig, state: AnimState)
NebbyBuilder.appendCFrames(rig: Rig, root: CFrame, parts: { BasePart }, cframes: { CFrame })
NebbyBuilder.bodySize(code: Types.NebbyCode): number
NebbyBuilder.bodyColor(code: Types.NebbyCode, t: number?): Color3
NebbyBuilder.partCount(code: Types.NebbyCode, lod: Lod): number
NebbyBuilder.buildWisp(): Rig
NebbyBuilder.buildCometOrb(): Rig
NebbyBuilder.buildCometSky(): Model
NebbyBuilder.destroy(rig: Rig)
```

---

## 13. Client

### 13.1 Ordre d'initialisation (`Main.client.luau`)

| # | Module | Paquet | Rôle |
|---|---|---|---|
| 1 | `UI/Root` | socle | écrans et échelle |
| 2 | `Controllers/StateController` | socle | miroir du profil |
| 3 | `Controllers/AudioController` | socle (+ `setMusicEnabled`) | sons |
| 4 | `Util/Prefs` | contrat | réglages, langue, traduction |
| 5 | `Controllers/WorldFXController` | socle | tags Spin/Float/Pulse |
| 6 | `Controllers/WorldStateController` | client-world | miroir du monde |
| 7 | `Controllers/LightingController` | world | cycle et préréglages |
| 8 | `Controllers/CongaRenderer` | client-world | créatures et Nids |
| 9 | `Controllers/VFXController` | client-world | effets 3D |
| 10 | `UI/ScreenFX` | client-hud | juice d'écran, Feedback, Celebrate |
| 11 | `UI/Banners` | client-hud | bannières |
| 12 | `Controllers/PanelController` | client-panels | navigation des panneaux |
| 13 | `Controllers/InputController` | client-hud | actions, pings, type d'entrée |
| 14 | `UI/HUD` | client-hud | interface permanente |
| 15 | `UI/Minimap` | client-hud | minicarte |
| 16 | `Controllers/OnboardingController` | client-hud | accueil |

Un module n'appelle directement que ceux listés avant lui ; vers le bas de la liste, il écoute leurs signaux. Tous lisent `StateController` (profil), `Prefs` (réglages, `Prefs.t`), `Shared/*`. `UI/Panels/*` ne sont pas dans la liste : PanelController les `require` et les construit à la demande.

### 13.2 Propriétaires des remotes côté client et signaux client

Chaque remote serveur → client a **un seul** abonné (§10.2) ; les autres modules passent par ses signaux :

| Module | Signaux exposés |
|---|---|
| WorldStateController | `Ready`, `LineOp`, `Caught`, `Banked`, `Snipped`, `Cleared`, `OwnerChanged`, `WildAdded`, `WildRemoved`, `EventChanged`, `CrewsChanged`, `PingShown` |
| ScreenFX | `FeedbackReceived`, `Celebrated` |
| Banners | `Shown` |
| InputController | `Dashed`, `InputTypeChanged`, `CheerRequested`, `MinimapToggled` |
| PanelController | `Opened`, `Closed`, `BadgeChanged` |
| Prefs | `Changed`, `LanguageChanged` |
| StateController (socle) | `Changed`, `ReadySignal` |

Réactions croisées imposées (pour éviter les doublons) :
- **Capture** : CongaRenderer anime le saut ; VFXController joue particules, colonnes, focale, « +1 espèce » ; HUD fait pulser le compteur de file.
- **Parade** (`Banked`) : CongaRenderer fait marcher la file vers le Nid puis sauter sur les perchoirs ; VFXController joue « +valeur », feux d'artifice, flash de l'arche ; ScreenFX (joueur local) joue le tampon « PARADE ×… » et les pièces vers la pastille Glow (`HUD.anchor("glow")`).
- **Coupe** (`Snipped`) : CongaRenderer anime les arcs de dispersion et l'étourdissement ; VFXController joue « SNIP ! » 3D, étincelles, anneau Snip Rush, traînées ; ScreenFX joue la vignette rose de la victime locale.
- **Supernova** : VFXController joue la séquence 3D quand l'attribut `Supernovas` d'un Nid augmente (tous les Nids) ; ScreenFX joue le titre sur `Celebrate "supernova"` (héros) ; HUD affiche le bouton ACCLAMER sur `CheerPrompt`.
- **Amélioration** : ScreenFX, sur `Celebrate "upgrade"`, appelle `VFXController.playUpgrade(track, level)`.
- **Dash** : InputController appelle `VFXController.playDash()`.

### 13.3 `Util/Prefs` (contrat, implémenté)

```lua
Prefs.Init()  Prefs.Start()
Prefs.get(key: string): any                 -- profile.settings (défauts de Config/Settings avant l'instantané)
Prefs.reducedMotion(): boolean              -- réglage OU GuiService.ReducedMotionEnabled
Prefs.lowGraphics(): boolean
Prefs.language(): "en" | "fr"               -- réglage « lang », "auto" → LocaleId
Prefs.t(key: string, vars: { [string]: any }?): string
Prefs.number(n: number): string             -- Format.abbreviate(n, langue)
Prefs.commas(n: number): string
Prefs.duration(seconds: number): string
Prefs.Changed: Signal<string, any>          -- (clé, valeur)
Prefs.LanguageChanged: Signal<"en" | "fr">
```

Applique : `Juice.forceReducedMotion`, `Juice.cameraShakeEnabled`, `AudioController.enabled` (sfx), `AudioController.setMusicEnabled` (musique). Chaque module d'interface ré-applique ses textes sur `LanguageChanged`. Les modules d'effets consultent `Prefs.reducedMotion()` et `Prefs.lowGraphics()` à chaque effet.

### 13.4 LightingController (paquet world) — GDD §11.5

```lua
LightingController.Init()
LightingController.Start()
LightingController.cycleClockTime(t: number): number
LightingController.currentPreset(): string?
LightingController.setPreset(key: string?)
```

Cycle de 12 min sur `Clock.now()` (une connexion `RenderStepped`) ; préréglages `Events.Lighting.Presets` (tween 3 s `Sine InOut`) selon `EventClock.weather` et l'état de `WorldStateController` (Balise, Nuit d'Or, alerte Comète, LiveOps) ; effets dans `workspace.ClientSky` ; anneaux `BeaconRing` / `BeaconDeposit` et faisceau de la Balise.

### 13.5 Loading (paquet world) — `src/first/Loading.client.luau`

LocalScript autonome de `ReplicatedFirst` (aucun `require` de `ReplicatedStorage`). Retire l'écran par défaut, montre un Nebby en Frames qui rebondit et 3 points, se ferme (fondu 0,3 s) quand `game:IsLoaded()` et que l'attribut **local** `Players.LocalPlayer.ClientReady` est vrai (posé par HUD). Après 20 s : « Ton Nid se réveille… / Your Nest is waking up… » (textes embarqués FR/EN selon `LocaleId`) et bouton Réessayer (`TeleportService:Teleport(game.PlaceId)`). Le harnais monte `src/first` dans `ReplicatedFirst` : `h:run("ReplicatedFirst.Loading")`.

### 13.6 WorldStateController (paquet client-world) — GDD §12.4

```lua
WorldStateController.Init()
WorldStateController.Start()
WorldStateController.isReady(): boolean
WorldStateController.localSlot(): number
WorldStateController.slotOf(userId: number): number
WorldStateController.userAt(slot: number): number
WorldStateController.line(slot: number): Types.LineMirror?
WorldStateController.lineLength(slot: number): number
WorldStateController.trail(slot: number): Trail.Trail?
WorldStateController.wilds(): { [number]: Types.WildMirror }
WorldStateController.wildPosition(wild: Types.WildMirror, t: number): Vector3
WorldStateController.events(): Types.EventStatePayload?
WorldStateController.wispPosition(id: number, t: number): Vector3?
WorldStateController.cometPosition(t: number): Vector3?
WorldStateController.crews(): Types.CrewStatePayload
WorldStateController.crewOf(userId: number): number
WorldStateController.isCrewmate(userId: number): boolean
WorldStateController.requestWorld()
```

Signaux :

```lua
WorldStateController.Ready: Signal.Signal<>
WorldStateController.LineOp: Signal.Signal<number, Types.LineOp>
WorldStateController.Caught: Signal.Signal<number, Types.NebbyCode, number, Vector3?>
WorldStateController.Banked: Signal.Signal<number, Types.LineBankOp>
WorldStateController.Snipped: Signal.Signal<Types.SnipEventPayload>
WorldStateController.Cleared: Signal.Signal<number, string>
WorldStateController.OwnerChanged: Signal.Signal<number, number>
WorldStateController.WildAdded: Signal.Signal<Types.WildMirror>
WorldStateController.WildRemoved: Signal.Signal<number, string, number>
WorldStateController.EventChanged: Signal.Signal<Types.EventStatePayload, Types.EventStatePayload?>
WorldStateController.CrewsChanged: Signal.Signal<Types.CrewStatePayload>
WorldStateController.PingShown: Signal.Signal<number, number>
```

### 13.7 CongaRenderer (paquet client-world) — GDD §5.2, §6.4, §9.3, §12.8

```lua
CongaRenderer.Init()
CongaRenderer.Start()
CongaRenderer.nodePositions(slot: number): { Vector3 }
CongaRenderer.nodeModel(slot: number, index: number): Model?
CongaRenderer.wildModel(id: number): Model?
CongaRenderer.renderedParts(): number
```

Rendu des files des autres depuis `WorldStateController.trail(slot)`, de la file locale depuis un `Trail` local alimenté chaque image ; un seul `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` par image ; LOD, budgets et lisibilité (§3.2, `Cosmetics.Readability`) ; Nids depuis leurs attributs (perchés, panneau, constellation, liens d'équipage) ; stèle (attributs `Live`, `Record`, `Weekly`).

### 13.8 VFXController (paquet client-world) — GDD §9.1, §9.4

```lua
VFXController.Init()
VFXController.Start()
VFXController.floatText(worldPos: Vector3, text: string, color: Color3, scale: number?)
VFXController.ring(worldPos: Vector3, radius: number, color: Color3, duration: number)
VFXController.burst(worldPos: Vector3, color: Color3, count: number)
VFXController.pillar(worldPos: Vector3, color: Color3, duration: number, height: number?)
VFXController.fovPunch(delta: number, outTime: number, backTime: number)
VFXController.haptic(strength: number, duration: number)
VFXController.fireworks(worldPos: Vector3, count: number, color: Color3?)
VFXController.playDash()
VFXController.playUpgrade(track: string, level: number)
VFXController.playSupernova(slot: number, level: number)
```

### 13.9 ScreenFX (paquet client-hud) — GDD §9.1, §9.2, §9.4

```lua
ScreenFX.Init()
ScreenFX.Start()
ScreenFX.stamp(text: string, color: Color3, style: StampStyle?)
ScreenFX.flyCoins(fromScreen: Vector2, target: GuiObject, count: number)
ScreenFX.floater(text: string, screenPos: Vector2, color: Color3)
ScreenFX.vignette(color: Color3, duration: number)
ScreenFX.confetti(count: number)
```

Signaux :

```lua
ScreenFX.FeedbackReceived: Signal.Signal<Types.FeedbackPayload>
ScreenFX.Celebrated: Signal.Signal<Types.CelebratePayload>
```

### 13.10 Banners (paquet client-hud) — GDD §6.5

```lua
Banners.Init()
Banners.Start()
Banners.show(payload: Types.BannerPayload)
Banners.queued(): { Types.BannerPayload }
```

### 13.11 InputController (paquet client-hud) — GDD §6.3, §10.4

```lua
InputController.Init()
InputController.Start()
InputController.dash(): boolean
InputController.dashReadyAt(): number
InputController.inputType(): number
InputController.openPingWheel()
InputController.closePingWheel()
InputController.ping(kind: number): boolean
```

Signaux :

```lua
InputController.Dashed: Signal.Signal<>
InputController.InputTypeChanged: Signal.Signal<number>
InputController.CheerRequested: Signal.Signal<>
InputController.MinimapToggled: Signal.Signal<>
```

### 13.12 HUD (paquet client-hud) — GDD §10.2

```lua
HUD.Init()
HUD.Start()
HUD.reveal(element: Types.HudElement, animate: boolean?)
HUD.isRevealed(element: Types.HudElement): boolean
HUD.revealAll()
HUD.anchor(element: Types.HudElement): GuiObject?
HUD.attention(element: Types.HudElement, on: boolean)
```

`HudElement` : `"glow" | "stardust" | "line" | "dash" | "ping" | "rail" | "rail.Upgrades" | "rail.Collection" | "rail.Goals" | "rail.Shop" | "eventPill" | "minimap" | "status" | "questTracker" | "crew" | "settings"`. Le HUD prédit le Glow (`glow + idleRate × (Clock.now() − lastSettle) + glowCarry`, borné à ≥ valeur serveur), anime les compteurs, possède `CheerPrompt` et pose `ClientReady`.

### 13.13 Minimap (paquet client-hud) — GDD §6.4

```lua
Minimap.Init()
Minimap.Start()
Minimap.setExpanded(expanded: boolean)
Minimap.toggle()
Minimap.project(worldPos: Vector3): Vector2
```

### 13.14 OnboardingController (paquet client-hud) — GDD §3

```lua
OnboardingController.Init()
OnboardingController.Start()
OnboardingController.step(): number
OnboardingController.currentHint(): string?
```

### 13.15 PanelController (paquet client-panels) — GDD §10.3, §10.4

```lua
PanelController.Init()
PanelController.Start()
PanelController.open(name: Types.PanelName, args: any?)
PanelController.close()
PanelController.back()
PanelController.toggle(name: Types.PanelName)
PanelController.current(): Types.PanelName?
PanelController.hasAction(name: Types.PanelName): boolean
PanelController.nextTab(direction: number)
```

Signaux :

```lua
PanelController.Opened: Signal.Signal<Types.PanelName>
PanelController.Closed: Signal.Signal<Types.PanelName>
PanelController.BadgeChanged: Signal.Signal<Types.PanelName, boolean>
```

Interface d'un panneau (`PanelController.Panel`) : `name`, `tabs?`, `build(parent: Frame)`, `onOpen(args: any?)`, `onClose()`, `hasAction(): boolean`, `selectTab?(tab: string)`. `PanelName` : `"Upgrades" | "Supernova" | "Collection" | "Goals" | "Shop" | "Crew" | "Settings" | "ReturnScreen"`. Arguments d'ouverture utilisés : `{ focus = "conga" }` (Upgrades, accueil), `{ tab = "atlas" }` (Collection), `{ data = … }` (ReturnScreen).

### 13.16 Panneaux `UI/Panels/*` (paquet client-panels) — GDD §10.3

| Panneau | Contenu (détail dans l'en-tête du stub) | Remotes émis | Fonctions en plus |
|---|---|---|---|
| Upgrades | 5 cartes, bouton Supernova + anneau, carte unique à l'accueil | `BuyUpgrade` | — |
| Supernova | aperçu Gardé / Remis à zéro, maintien 1 s, « Rentre au Nid » | `Supernova` | — |
| Collection | onglets Perchoirs, Réserve (virtualisée), Forge, Atlas, Guide | `Fuse`, `FuseAll`, `Release`, `SetLock` | `selectTab` |
| Goals | Aujourd'hui, Calendrier, Semaine, Accueil | `ClaimQuest`, `RerollQuest`, `ClaimDaily` | `selectTab` |
| Shop | Passes, Boosts & Glow (≈ montants), Codes ; prix via `Client/Util/Prices` | `RedeemCode` (Function) ; prompts `MarketplaceService` | `selectTab` |
| Crew | équipage, joueurs, inviter, quitter, carte d'invitation | `CrewInvite`, `CrewRespond`, `CrewLeave` | `showInvite(payload)` |
| Settings | interrupteurs de `Config/Settings`, langue, styles, LiveOps (Admin) | `SetSetting`, `EquipCosmetic`, `AdminCommand` | — |
| ReturnScreen | écran de retour hors ligne | — | `present(data)` |

---

## 14. Localisation et sons

- **Toutes** les chaînes visibles viennent de `src/shared/Localization/Strings.luau` (registre partagé, ≈ 490 clés EN/FR livrées). Domaines : `common`, `loading`, `hud`, `onboarding`, `rarity`, `form`, `variant`, `zone`, `weather`, `event`, `banner`, `feedback`, `celebrate`, `stamp`, `panel.<Nom>.title`, `upgrades`, `supernova`, `collection`, `atlas`, `guide`, `goals`, `calendar`, `weekly`, `quest.onboarding.q1…q7`, `quest.daily.<1-25>` (+ `.desc`), `shop` (dont `shop.pass.<Clé>.name/desc`, `shop.product.<Clé>.name/desc`), `code.<statut>`, `crew`, `settings.<clé>` (+ `.desc`), `liveops`, `style`, `aura`, `title`, `theme`, `ping.<1-6>`, `return`, `board`, `nest`.
- Variables `{nom}` alphanumériques ; mêmes variables en EN et en FR (vérifié). Les noms d'espèces (`Config/Nebbies`, champ `name`) et les noms propres de l'IP restent en anglais.
- Côté client : `Prefs.t(clé, vars)` ; nombres `Prefs.number` (EN « 1.24M », FR « 1,24 M ») ; durées `Prefs.duration`. Les textes construits gardent `AutoLocalize = true` pour la traduction automatique Roblox des autres langues.
- Ajouter une clé : petite modification ciblée, EN **et** FR, sans toucher aux autres.
- **Sons** : `src/shared/Config/Sounds.luau` (registre partagé) ; clés du GDD §9 : `Click, Pop, Coin, Reward, LevelUp, Error, Whoosh, Music, Catch, CatchRare, Snip, Scatter, Bank, Dash, CometWarn, CometImpact, CometSwipe, BeaconStart, BeaconWin, WispPop, Supernova, Ping, Cheer` ; IDs vides (jeu jouable en silence) ; `AudioController.play(clé, variation?)`.

---

## 15. Tests et définition de « fini »

**Commandes** : `~/.cargo/bin/stylua <fichiers>`, `~/.cargo/bin/selene src` (0 erreur, 0 avertissement dans ses fichiers), `~/.cargo/bin/lune run tests/run -- <filtre>`, puis toute la suite `~/.cargo/bin/lune run tests/run` et `./scripts/check.sh`.

**Conventions de spec** (`tests/specs/<Nom>.spec.luau`, voir la skill roblox-qa-testing) :
- Temps : `Clock.freeze(t)` et `Clock.advance(dt)` sur l'instance du harnais ; jamais d'attente réelle longue.
- Isolation : les modules sont des tables simples ; une spec peut **remplacer une fonction d'une dépendance** (y compris un stub `TODO` d'un autre paquet) avant `h:boot()` ou avant l'appel testé, ex. `local Nest = h:require("ServerScriptService.Server.Services.NestService"); Nest.slotOf = function() return 1 end`.
- Tick : `CongaService.tick(now)` directement (pas besoin de `h:step`) ; services lents : `X.step(now)`.
- Couverture minimale de chaque paquet : chemins heureux ; cas limites ; **charges malveillantes** sur chacun de ses remotes (NaN, ±inf, mauvais types, tables énormes ou mixtes, uid d'un autre joueur, débit excessif) → aucune mutation, aucune erreur ; **cycle de vie** (arrivée avant/après le démarrage, départ, réapparition, personnage absent, départ pendant un yield).
- Ne jamais supprimer ni affaiblir un test existant (dont `Contract.spec` : un paquet peut ajouter des fonctions, pas retirer celles du contrat).

**Spécifiques** (GDD §12.9) : `Formulas.spec` (tables du §4.11), `Trail.spec` (extension), `SnipRules.spec` (chaque règle et combinaisons), `SeededPath.spec`, `EventClock.spec` (minuit, :25, :55, samedi 16:00 et 16:20, 100 000 créneaux à ±1 %), `Hash.spec` (valeurs de référence), `PathCodec.spec` (aller-retour, runs multiples, buffers tronqués), `EconomyPacing.spec` (porte bloquante §4.18 : 200 joueurs × 28 jours ; médianes dans les tolérances), `EconomyService/AtlasService/ProductService.spec` (achats, Supernova, Starforge, libération, réserve pleine, rejeu de reçu).

**Intégration** (tout le jeu, aucun remplacement de fonction) :
- `Boot.spec` : serveur complet, 12 joueurs (`tests/harness/Bots` : marche honnête, cerveaux qui chassent et paradent) ; coupes, améliorations et Supernova par les remotes ; météo, Grande Comète (ramassage, vol, encaissement), Nuit de la Balise et Starfall Saturday par voyage dans le temps (`Clock`) ; réapparitions, départs et retours (profil persisté) ; fermeture. Tous les envois du serveur passent par les règles de sérialisation des remotes Roblox (`tests/harness/Wire`) et chaque Feedback / bannière / célébration est vérifié contre `Strings` (EN et FR, variables comprises).
- `ClientGame.spec` : un vrai serveur joue une partie ; tout ce qu'il envoie à un joueur (remotes, attributs répliqués, perchoirs, position du personnage) est enregistré puis rejoué dans le vrai client (`Main.client`) au même instant ; à des points de contrôle, le miroir du client (files, miettes, sauvages, événements, équipages, profil) doit être identique à l'état du serveur, sans `RequestWorld` ni `RequestPath`. Puis chaque panneau, onglet et bouton est pressé (EN puis FR) et les intentions produites sont livrées au vrai serveur. Variante : arrivée en cours de partie (tactile, français).
- Les deux specs auditent aussi l'API Roblox (`tests/harness/ApiAudit`) : chaque classe créée, chaque propriété écrite (objectifs des tweens compris) et chaque membre lu inconnu du harnais sont confrontés à la base de réflexion de Roblox livrée avec Lune (existence, type, droit d'écriture, type interpolable) — une faute de frappe de propriété, qui passe sous Lune, casserait dans Roblox.
- `Boot.spec` couvre aussi les courses de cycle de vie : joueurs présents avant le démarrage des services, départ pendant le chargement du profil puis retour, personnage absent, mort avant la porte, réapparitions en rafale.

**Définition de fini** : plus aucun `error("TODO(<paquet>)…")` dans ses fichiers ; comportement conforme au GDD et à ce document ; specs ci-dessus ; `selene src` sans erreur ; fichiers formatés ; suite complète lancée et résultat rapporté honnêtement ; notes d'intégration pour tout besoin hors de ses fichiers.

---

## 16. Décisions d'interprétation du GDD

Points où le GDD laissait un choix, tranchés ici pour que tous implémentent la même chose.

1. **Plafonds journaliers (`caps`) chez EconomyService** et non QuestService : EventService (Gloomwisps) et CrewService (acclamations, Duo) sont initialisés avant QuestService (§12.3 du GDD) et doivent consulter le plafond ; EconomyService, propriétaire de la Stardust, est plus tôt.
2. **Statistiques (`stats`) chez QuestService**, alimentées uniquement par les signaux du §7.
3. **Réglages et cosmétiques chez NestService** (Zen exige le port sûr de son Nid ; l'identité visible vit sur le Nid).
4. **Quêtes d'accueil récompensées automatiquement** (FTUE sans fenêtre modale) ; `ClaimQuest("onboarding", 1)` reste accepté s'il reste une récompense due.
5. **Balise réussie dès que la barre est pleine** (Frenzy immédiate, la trêve continue jusqu'à la fin de la fenêtre) ; échec constaté à la fin. L'objectif est figé au début de la nuit.
6. **SnipEvent porte la coupe elle-même** et partage la suite de versions de LineEvent ; Nebbies libérés transmis dans l'op (pas dans WildEvent) ; capturés retirés via l'op `add`.
7. **Comète lâchée** (départ, mort, passage en Zen du porteur) : elle retombe au sol à la dernière position valide du porteur, l'ancien porteur ne peut pas la reprendre pendant 4 s.
8. **Contenu de la Comète** : sans variante ; forme de la météo active **à l'impact** (Prismatic pendant Starfall).
9. **Glow Party jamais refusée** : un reçu payé est toujours honoré ; la file de 60 min est une limite de bouton (masqué au-delà de 20 min restantes) ; durée ajoutée depuis `max(now, fin actuelle)`.
10. **Starter Kit acheté deux fois** (course rarissime) : honoré à nouveau.
11. **Boosts personnels** : durées prolongées (`max(now, fin) + durée`), jamais de ×4 ; boost de serveur unique (Nuit d'Or, Starfall, Glow Party, LiveOps).
12. **Supernova** : le Glow restant après paiement est remis à 0 (« Remis à zéro : Glow »).
13. **Numéros de miettes contigus par slot** entre propriétaires successifs ; un slot peut avoir plusieurs runs dans un message `PathStream`.
14. **Fin du bouclier débutant** décidée par QuestService mais appliquée au prochain moment sûr signalé par CongaService (`onSafeMoment` : parade ou file vide).
15. **uid** des Nebbies : `"u" .. nextUid` (clés de chaîne non numériques, sûres en JSON et en remote).
16. **Quête « Économiste »** : secondes de revenu passif réglées en ligne (`Signals.IdleSettled`), objectif 1 800 s.
17. **Quête « Gros défilé »** : `ParadeInfo.idleSeconds = glow / idleRate` (0 si `idleRate = 0`).
18. **Joueur actif** (≥ 4 studs en 60 s) calculé par CongaService et poussé une fois par seconde.
19. **Tick signalé par MoveCheck** : pas de miette poussée, pas de capture, coupe, parade, vol ni ramassage de Comète, ni éclatement de Gloomwisp.
20. **Hasard serveur des apparitions** libre (`Random.new()`) ; seuls la flânerie, la météo, la Comète, les quêtes du jour, le décor et les Gloomwisps sont déterministes (`Hash`).
21. **Treizième joueur sans Nid** (configuration anormale) : slot 0, aucun gameplay déclenché.
22. **Cordes des Gloomwisps continues** : chaque corde part du point d'arrivée de la précédente.
23. **Mort** : Nebbies libres prioritaires pour le propriétaire (étourdis pour les autres), sans Second Souffle ; **départ** : sans priorité.
24. **`MaxPlayers = 12`** posé aussi dans `default.project.json` (le Creator Hub reste la référence en production).
25. **MoveCheck (GDD §12.7)** : appliquée à chaque tick de 0,1 s, la seule tolérance de +4 studs du GDD laisserait passer ≈ 4× la vitesse ; MoveCheck ajoute donc un contrôle du déplacement **soutenu sur 1 s** (tolérance comptée une fois). La référence de chaque tick est la dernière position validée (un téléport n'est jamais accepté au tick suivant), avec au plus 1,5 s de crédit à l'arrêt (gels réseau). Pendant l'exemption de 3 s après une apparition, les positions restent contrôlées : une position invraisemblable est refusée sans compter ni rembobiner. Après un rembobinage, une période de grâce absorbe les positions encore en vol (pas de nouveau rembobinage, pas de compte pour `lbBanned`). Un rembobinage n'émet pas `ServerMoved` (pas d'exemption enchaînable).
26. **Acteur d'un tick refusé** (`valid = false`) : `pos = prev` = dernière position validée (jamais la position brute) ; `prev → pos` est toujours un déplacement validé, que tous les balayages utilisent (coupes, vol et encaissement de la Comète, Gloomwisps, portes).
27. **Portes et anneau testés le long du pas validé** : à 10 Hz, avec un Dash (3,6 studs par tick) et la gigue du réseau, deux échantillons peuvent tomber de part et d'autre de la boîte de porte (4 studs de profondeur). Parades (CongaService) et encaissement de la Comète (EventService) testent donc `prev → pos` tous les 1 stud.
28. **Analytique `SnipByInput`** : valeur = type d'entrée du coupeur (1 tactile, 2 clavier-souris, 3 manette), `Util/Analytics` n'ayant pas de champs personnalisés. `WispSnip` est envoyée par CongaService seul (pas par `EventService.onWispSnip`).

---

## 17. Réglages d'économie

Section tenue par le paquet **logic** (simulation `tests/specs/EconomyPacing.spec.luau`, GDD §4.18). Seules les **valeurs** de `src/shared/Config/Balance.luau` peuvent changer, dans l'esprit du GDD. Chaque réglage est consigné ici : date, clé, ancienne → nouvelle valeur, médianes simulées avant / après, raison.

| Date | Clé | Avant → après | Effet mesuré | Raison |
|---|---|---|---|---|
| 31/10/2026 | `Balance.Supernova.Costs[4..12]` (R3 → R4 et au-delà) | 120 M, 300 M, 700 M, 1,8 G, 4 G, 8 G, 14 G, 22 G, 34 G → **240 M, 600 M, 1,4 G, 3,6 G, 8 G, 16 G, 28 G, 44 G, 68 G** (× 2) | Supernova 10 : jour 16 → **21** ; Supernova 6 + ★3 : jour 6 (limite basse) → **7** ; S1, S3 et Atlas inchangés (mesuré seul, formes à 0,4) | Avec les valeurs du GDD, les perchoirs remplis de Légendaires/Mythiques (et leurs étoiles) font exploser le revenu passif après R3 : S10 arrivait 2 jours avant la fenêtre. Premier levier du GDD §4.18 ; `Costs[1] = 400 000` (objectif affiché dès l'accueil, figé par `Contract.spec`), `Costs[2]` et `Costs[3]` (rythme de S3) gardés. |
| 31/10/2026 | `Balance.Supernova.BeyondBase` | 34 G → **68 G** | — | Raccord sans saut avec `Costs[12]` (R ≥ 12 : `BeyondBase × 1,5^(R − 11)`). |
| 31/10/2026 | `Balance.Spawn.WeatherFormChance` | 0,4 → **0,2** | 50 % de l'Atlas : jour 6 → **12** ; entrées au jour 28 : 114 → 99 (66 %) ; Supernova 1 : 21,8 → **25,0 min** (moins de Nebbies à ×2-×6 au début) ; S3, S6, S10 inchangées | Les formes météo (4 × 30 entrées) remplissaient l'Atlas deux fois trop vite. Seul levier de `Balance` sur le rythme de l'Atlas ; une fenêtre météo reste visible (1 apparition sur 5 pendant une fenêtre à forme, soit ≈ 1 capture sur 14 au total), la chasse aux formes reste un objectif de J2-J28. Alternative si le design tient aux 40 % : allonger `Zones.*.interval` (contrat). |

**Résultat retenu** (200 joueurs × 28 jours, médianes ; tolérances du GDD §4.18) :

| Jalon | Cible GDD | Tolérance | Valeurs du GDD | Après réglage |
|---|---|---|---|---|
| Première parade | 12 s | ≤ 20 s | 10,5 s | 10,5 s |
| Première amélioration | 20 s | ≤ 30 s | 18,5 s | 18,5 s |
| Supernova 1 | 25 min | 20-35 min | 21,8 min | **25,0 min** |
| Supernova 3 | jour 3 | jour 2-4 | jour 3 | jour 3 |
| Supernova 6 + premier ★3 | jour 7 | jour 6-8 | jour 6 | **jour 7** (★3 dès le jour 2) |
| 50 % de l'Atlas | jour 14 | jour 10-16 | jour 6 ✗ | **jour 12** |
| Supernova 10 | jour 21 | jour 18-24 | jour 16 ✗ | **jour 21** |
| 80 % de l'Atlas | jour 28 | — | non atteint (114/150) | non atteint (99/150), longue traîne |

**Modèle** (`tests/sim/Pacing.luau`, constantes `Pacing.Model`) : joueur de référence du §4.18 (30 min par jour, 35 le premier, hors ligne gratuit 50 % / 8 h, aucun achat), sessions à une heure UTC tirée au hasard (météo et Comètes réelles d'`EventClock`, Starfall compris). Toutes les valeurs de jeu viennent de `Config/*` et de `Logic/Formulas` ; seules les hypothèses de comportement sont propres au modèle :
- serveur de référence de 8 joueurs actifs (`capScale` 0,75) répartis entre les zones selon une distribution idéale libre (joueurs ∝ valeur de parade apparue par seconde : ≈ 1,2 Prairie, 2,3 Clairière, 4,5 Cratère) ; chaque capture coûte `max(part du flux d'apparition de la zone, marche jusqu'au Nebby le plus proche − Attrait) + 0,3 s + temps de recherche` ;
- temps de recherche de 10 s par capture, **calibré avant tout réglage** sur le bilan à 5 minutes du GDD §3 (4 à 6 parades et 4 à 6 améliorations : le modèle donne 5 et 5) ;
- zone choisie selon la capacité de file (< 6 Prairie, < 12 Clairière, sinon Cratère) ; trajet = distance moyenne de la porte aux 20 % de points d'apparition les plus proches ;
- pertes par coupe : 12 % des Nebbies hors Prairie (aucune sous bouclier débutant) ; Comètes gagnées 1 fois sur 6 (Nebby + 120 s de revenu + 50 Stardust) ;
- Supernova dès que possible ; sinon améliorations au moins cher d'abord, sauf celles qui coûtent plus de 10 % de la Supernova visée (épargne) ; pendant la chaîne d'accueil du 1er jour, une amélioration par retour au Nid (panneau à une carte, §3), rien avant la 1re parade ;
- chaîne d'accueil Q1-Q7, calendrier, 3 quêtes du jour (facile et moyenne toujours, difficile 2 jours sur 3, à 25 / 50 / 75 % de la session), Étoile du jour, Grand Défilé ;
- fin de session : Tout fusionner (meilleur revenu obtenu d'abord), tri des perchoirs, libération automatique des C/U/R en trop contre leur Stardust.

La spec vérifie aussi que la porte est déterministe et qu'elle échoue réellement si l'équilibrage dérive (Supernovas 10 fois moins chères → S1, S6 et S10 hors tolérance).

---

## 18. Modifications du socle faites par le contrat

Ajouts minimaux et testés (aucune réécriture) :

| Fichier | Ajout | Pourquoi | Test |
|---|---|---|---|
| `src/server/Services/DataService.luau` | `DataService.onBeforeSave(fn)` (crochets synchrones avant chaque écriture) | GDD §12.6 : `settle` avant chaque sauvegarde, y compris au départ et à la fermeture | `DataService.spec` |
| `src/shared/Util/Format.luau` | correction : `abbreviate(100000)` donnait « 1K » (les zéros entiers étaient retirés) ; paramètre `lang` (FR : « 1,24 M », espaces insécables) pour `abbreviate`, `commas`, `duration` | GDD §13.1 ; affichage juste des compteurs | `Contract.spec` |
| `src/client/UI/Juice.luau` | `Juice.forceReducedMotion` | réglage « Mouvement réduit » du joueur (GDD §9.1) | `Contract.spec` |
| `src/client/Controllers/AudioController.luau` | `setMusicEnabled`, `isMusicEnabled` | réglage « Musique » (GDD §10.3) | `Contract.spec` |
| `src/shared/Logic/Trail.luau` | stubs de l'extension (paquet logic) | GDD §4.7, §12.4 | `Contract.spec` |
| `tests/harness/Harness.luau` | montage de `src/first` dans `ReplicatedFirst` | tester l'écran de chargement | `Contract.spec` |
| `tests/specs/{DataService,MonetizationService,ClientBoot}.spec.luau` | portées du schéma d'exemple (`coins`) au schéma v1 (`glow`, `stardust`), mêmes vérifications + migration v0 et crochet de sauvegarde | schéma v1 | — |
