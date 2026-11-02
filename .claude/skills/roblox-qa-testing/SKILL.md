---
name: roblox-qa-testing
description: Assurance qualité de Raise a Squishy — harnais de tests Lune (tests/harness, repris de Comet Conga) qui simule Roblox (require Rojo, Players, DataStore, Marketplace, remotes, console), joueurs simulés génériques (Bots), simulation d'économie (tests/sim), écriture de specs, classes de bugs Roblox à traquer et checklist avant publication. À charger pour écrire/lancer des tests, chasser un bug, faire une revue de code ou préparer une release.
---

# QA & tests

## Lancer les vérifications

```bash
stylua --check src tests     # formatage
selene src                   # lint
lune run tests/run           # tous les tests
lune run tests/run -- Data   # seulement les specs dont le chemin contient « Data »
rojo build -o build/Game.rbxl
./scripts/check.sh           # les cinq contrôles d'un coup (porte avant commit)
lune run scripts/prepublish  # avant de publier : chaque article de la boutique a son numéro
```

## Le harnais (tests/harness)

`Harness.new({ mode = "server" | "client", console = bool })` monte `src/` comme Rojo dans un DataModel simulé (l'option `touch` du socle ne sert qu'au message `device.touch` : le jeu n'a aucun chemin tactile) :

| API | Effet |
|-----|-------|
| `h:require("ReplicatedStorage.Shared.Config")` | charge un module avec un vrai `require(script.Parent.X)` |
| `h:boot()` | exécute `Main.server.luau` (ou `Main.client.luau` en mode client) |
| `h:addPlayer({ userId = 1, name = "A", locale = "fr-fr" })` | PlayerAdded + personnage |
| `h:removePlayer(p)` / `h:respawn(p)` | départ / réapparition |
| `h:moveTo(p, Vector3)` | déplace le personnage (HumanoidRootPart) |
| `h:makeFriends(a, b)` | amis Roblox (`IsFriendsWith`, `GetFriendsAsync`) |
| `h:fireServer("ReplicatedStorage.Remotes.X", p, ...)` | simule un client (y compris un tricheur) |
| `h:invokeServer(path, p, ...)` | RemoteFunction |
| `h:createRemotes()` | (mode client) crée les remotes déclarés, comme le serveur |
| `h:fireClient(path, ...)` | (mode client) le serveur parle au client |
| `h:sentTo(p, "RemoteName")` | liste des `FireClient` reçus par p |
| `h.log.allClientEvents` | `FireAllClients` |
| `h:step(dt, frames)` | fait avancer Heartbeat/RenderStepped |
| `h:settle(n)` | laisse finir les threads en attente |
| `h:purchaseProduct(p, productId, purchaseId?)` | appelle `ProcessReceipt` |
| `h:grantPass(p, passId)` | possession + `PromptGamePassPurchaseFinished` |
| `h.dataStoreFailures = 3` | les 3 prochains appels DataStore échouent (tester les retries) |
| `h.dataStores["Nom/global"]` | inspecter les sauvegardes |
| `h:close()` | exécute les callbacks `BindToClose` |
| `h:dispose()` / `Harness.disposeAll()` | annule les threads encore en attente du code monté (boucles d'autosave, `task.delay`…) ; le lanceur appelle `disposeAll()` après chaque spec : aucune spec ne garde un harnais pour la suivante, la mémoire reste stable (~0,8 Go pour toute la suite) |
| `h:warnings()` | `warn()` + « Infinite yield possible » |
| `h.log.kicks`, `h.log.prompts`, `h.log.analytics` | journaux |

Aides d'intégration (même dossier) :

| Module | Rôle |
|--------|------|
| `Bots` | boîte à outils générique de joueurs simulés : serveur complet (`Bots.boot(Harness, { t0, before, schema, groundY })`), N joueurs avec personnages et profils (`spawn(16)`, `join`, `leave`, `respawn`, `place`), marche honnête (`stepToward`, `walkAll`), réseau simulé (`jitter(p, 2 ou 3)` : paquets groupés, `freeze(p, s)` : gel puis rattrapage), cerveaux (`setBrain`, `brains`, exemple `wander`), voyage dans le temps (`travelTo`), MoveCheck appelé à chaque tick (`moveCheck()` → `count(p, "flag")`, `problems()`), clés de jeu fictives pour les specs du socle (`extendSchema`), `os.clock` contrôlé (`fakeOsClock`). Les paquets du jeu l'étendent avec leurs cerveaux et leurs scènes (exemple Comet Conga : `hunt`, `stageSnip`) |
| `Wire` | enregistre ce que le serveur envoie à un joueur (règles de sérialisation des remotes Roblox : tables mixtes ou à trous, NaN, Instances, buffer > 900 octets…), le monde construit (`world = "World"`, attributs, dossiers suivis par `track`) puis le rejoue dans un client complet ; `saveContext` / `restoreContext` pour reparler au serveur après le client |
| `ApiAudit` | pendant un test, confronte classes, propriétés écrites (tweens compris), types et droits d'écriture à la base de réflexion de Roblox livrée avec Lune |
| `Layout` | géométrie simulée des interfaces de PlayerGui (`Layout.apply(h)` → `AbsolutePosition` / `AbsoluteSize` ; Size, Position, AnchorPoint, UIPadding, UIScale, contraintes, UIListLayout, UIGridLayout, ScrollingFrame) et navigation manette (`step`, `reachable`, `unreachable`, `escapes` : NextSelection* puis sélection directionnelle, SelectionGroup + SelectionBehavior) |
| `Gamepad` | manette simulée (`press`, `release`, `tap`, `stick` : croix = navigation si une sélection existe, ✕ = `Activated`, sinon actions CAS par priorité) et `Gamepad.audit(h, { root })` : glyphes non PlayStation, lettres Xbox, textes < 18 px, débordement de la zone sûre TV |

Simulation (`tests/sim/Sim.luau`) : cadre déterministe pour la simulation d'économie obligatoire (`Sim.run({ players, days, simulate, gates, reported })`, médianes et p10/p90, `Sim.failures`, `Sim.report`). Le modèle du jeu l'utilise avec les vraies tables de `Shared/Config`.

Console : `Harness.new({ mode = "client", console = true })` simule une PS5 sur téléviseur (`IsTenFootInterface()` vrai, `ViewportDisplaySize = Large`, écran 1920 × 1080, manette seule, `PreferredInput = Gamepad`, icônes PlayStation de `GetImageForKeyCode`). Vibrations journalisées dans `h.log.haptics`. Liaisons ContextActionService (touches, priorité) : `h.actionBindings`.

Fidélité volontaire :
- Chaque connexion de signal tourne dans son propre thread ; **une erreur dans une connexion fait échouer le test** (comme une ligne rouge dans la sortie Studio).
- Accéder à un enfant inexistant d'un dossier de scripts lève « X is not a valid member » (fautes de chemin).
- Le DataStore simulé refuse ce que Roblox refuse : Vector3/Instance, NaN/inf, tables mixtes.
- `wait()`, `spawn()`, `delay()` lèvent une erreur.
- `Random.new(seed)` est déterministe.

Limite connue : deux harnais vivants en même temps (deux « serveurs » sur les mêmes sauvegardes) partagent les crochets globaux de `MockInstance` : méthodes de classe `DataStoreService` / `DataModel`, `onKick` et `onFireClient` vont toutes au harnais créé **en dernier**. Contournement (voir `tests/specs/Fix_final_data_lock.spec.luau`) : remplacer `MockInstance.classMethods.DataStoreService.GetDataStore` seulement pendant chaque `Init` du DataService, lire `player.KickedWith` plutôt que `h.log.kicks`, et ne démarrer que le DataService (pas `h:boot()`) sur le second serveur.

Une spec :

```lua
--!nocheck
return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	describe("Economy", function()
		it("refuse un achat sans assez d'argent", function()
			local h = Harness.new()
			h:boot()
			local p = h:addPlayer({ userId = 1 })
			h:settle()
			h:fireServer("ReplicatedStorage.Remotes.RequestBuy", p, "item_x")
			expect(...).toBe(...)
		end)
	end)
end
```

Fichiers : `tests/specs/<Système>.spec.luau`. Une spec par système, et des tests de **démarrage complet** (`Boot.spec.luau`, à écrire pour le jeu) qui lancent un serveur de **16 joueurs** (Bots) pendant plusieurs centaines de ticks, puis rejouent une partie dans le vrai client (Wire). Un défaut trouvé en QA = un test qui échoue d'abord, puis la correction ; le test reste (`Fix_*`). On ne supprime ni n'affaiblit jamais un test pour le faire passer.

Specs d'intégration du jeu (docs/04 §18.3) : `Boot.spec` (serveur complet, 16 joueurs, par les remotes), `Soak.spec` (robot de longue durée, 0,5 h dans `check.sh`, 6 h avec `scripts/soak.sh`), `ClientReplay.spec` (partie réelle du serveur rejouée dans le client complet, PS5 1080p / 4K / 720p, EN et FR, puis clavier et souris), `EconomyPacing` (porte de rythme de l'économie). Règle zéro trace : une erreur ou un avertissement inattendu fait échouer la spec (`tests/harness/ZeroLog`, `T.expectWarning` pour un avertissement voulu).

Leçons de Comet Conga (docs/06 de Comet Conga) : figer `Clock` et `os.clock` (`Bots.fakeOsClock`) plutôt qu'attendre en temps réel ; ne jamais dépendre de l'ordre de parcours d'une table ; relancer la suite deux fois avant une publication pour repérer les tests instables.

## Classes de bugs Roblox à traquer systématiquement

1. **Course au démarrage** : joueur arrivé avant la connexion `PlayerAdded` ; personnage chargé avant `CharacterAdded`.
2. **Données pas encore chargées** : remote reçu avant la fin du chargement DataStore → handler doit ignorer (`if not data then return end`).
3. **Joueur parti pendant un yield** : après chaque `GetAsync`/`task.wait`, vérifier `player.Parent ~= nil`.
4. **Personnage mort/absent** : `player.Character` nil, `HumanoidRootPart` nil, `Humanoid.Health <= 0`.
5. **Fuites** : connexions jamais déconnectées, tables indexées par `Player` jamais vidées à `PlayerRemoving`.
6. **Remotes abusés** : spam, types inattendus (table, NaN, chaîne énorme), objets hors de portée, ids inexistants.
7. **Double récompense** : clic multiple, ProcessReceipt rejoué, quête validée deux fois, récompense quotidienne réclamée en boucle (comparer avec l'horodatage serveur `os.time()`, jamais celui du client).
8. **Économie** : nombres négatifs, débordements, arrondis (toujours `math.floor` pour la monnaie), multiplicateurs cumulés involontairement.
9. **UI** : textes qui débordent ou passent sous 28 px TV (1920 × 1080, 3840 × 2160, 1280 × 720, EN et FR), éléments hors de la zone sûre de 5 %, sélection manette vide ou hors de la fenêtre, touche du jeu liée derrière une fenêtre, tweens concurrents sur la même propriété, panneaux ouverts en double (`TvAudit.run`).
10. **Respawn** : UI détruite à la réapparition (`ResetOnSpawn = false`), effets attachés à l'ancien personnage.
11. **Arrêt serveur** : `BindToClose` doit sauvegarder tout le monde avant 30 s.
12. **Objet en retard côté client** (`StreamingEnabled` est coupé, mais la réplication n'est pas instantanée) : `WaitForChild` sans délai → attente infinie ; toujours un délai et un repli.

## Checklist release

- [ ] Les 4 commandes de vérification passent.
- [ ] Test de démarrage complet : 0 erreur, 0 avertissement « Infinite yield ».
- [ ] Test « tricheur » : chaque remote reçoit des charges invalides sans erreur ni effet.
- [ ] Test DataStore : pannes simulées → retries → aucune perte ; données corrompues → migration/reconcile.
- [ ] Achats : ProcessReceipt idempotent (même PurchaseId deux fois = un seul crédit).
- [ ] Studio : jouer en mode « Local Server » avec 3 joueurs, à la manette (émulateur console 1080p et 4K), puis au clavier et à la souris.
- [ ] Console : specs `Console*.spec` vertes (manette seule, glyphes PlayStation, zone sûre, pas de fenêtre de chat) puis essai sur une vraie PS5 à 3 m.
- [ ] Anti-triche : 16 joueurs honnêtes simulés (gigue, gels de 0,7 à 1,5 s, réapparitions) sans aucune infraction ; chaque triche reproduite reste bloquée.
- [ ] Économie : la spec de simulation passe (portes de rythme dans leurs tolérances).
- [ ] Sons : chaque son écouté dans Studio ; `scripts/prepublish` vert.
