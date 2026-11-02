---
name: roblox-luau-engineering
description: Standards d'ingénierie Luau/Roblox de Raise a Squishy (Rojo, structure des modules, socle repris de Comet Conga, typage, cycle de vie, nettoyage des connexions, performance, outils selene/stylua/lune). À charger AVANT d'écrire ou de modifier du code Luau dans src/, ou quand on demande « ajoute un système », « nouveau module », « refactor Luau », « Roblox code », « Rojo ».
---

# Ingénierie Luau / Roblox — standards du projet

## Arborescence Rojo (default.project.json)

| Dossier disque  | Instance Roblox                                   | Rôle |
|-----------------|---------------------------------------------------|------|
| `src/shared/`   | `ReplicatedStorage.Shared`                        | Config, constantes, logique pure, types, utilitaires partagés |
| `src/server/`   | `ServerScriptService.Server`                      | Services serveur (autorité absolue sur l'état du jeu) |
| `src/client/`   | `StarterPlayer.StarterPlayerScripts.Client`       | Contrôleurs client : UI, effets, entrées, caméra |
| `src/first/`    | `ReplicatedFirst`                                 | Écran de chargement autonome (n'exige rien de ReplicatedStorage) |

Projet Rojo « RaiseASquishy » : 16 joueurs par serveur, console d'abord (PS5, puis Xbox, puis PC ; aucun code tactile), **`StreamingEnabled = false`** (choix délibéré, GDD §12.9 : tout le monde est toujours là côté client, vérifié par `scripts/verify-place`), `Lighting.Technology = ShadowMap` (console la plus faible), `SignalBehavior = Deferred`, `TextChatService` sans fenêtre de chat sur console, curseur virtuel désactivé (navigation manette directionnelle), personnage neutre (WalkSpeed 16, JumpHeight 7,2).

Conventions de fichiers Rojo :
- `Nom.luau` → ModuleScript ; `Nom.server.luau` → Script ; `Nom.client.luau` → LocalScript.
- `init.luau` dans un dossier → le dossier devient le ModuleScript.
- **Un seul point d'entrée par côté** : `src/server/Main.server.luau` et `src/client/Main.client.luau` qui chargent les services/contrôleurs dans un ordre déterministe (`Init()` de tous, puis `Start()` de tous).

## Squelette d'un service / contrôleur

```lua
--!strict
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Settings = require(Shared.Config.Settings) -- les nombres viennent de Shared/Config/*

local MyService = {}

function MyService.Init()
	-- créer les remotes / états, AUCUN yield long ici
end

function MyService.Start()
	-- connecter les événements, lancer les boucles (task.spawn)
end

return MyService
```

## Règles non négociables

1. `--!strict` en tête de chaque module ; types exportés (`export type`) pour les données échangées.
2. **Jamais** `wait()`, `spawn()`, `delay()` → `task.wait`, `task.spawn`, `task.delay`, `task.defer`.
3. Toute connexion créée pour un joueur/personnage est stockée et **déconnectée** au départ (`Players.PlayerRemoving`, `Humanoid.Died`, `Instance.Destroying`). Utiliser un « Janitor/Trove » maison (`Shared/Util/Trove.luau`).
4. `PlayerAdded` : toujours traiter aussi les joueurs **déjà présents** (`for _, p in Players:GetPlayers()`), car le script peut démarrer après eux.
5. `CharacterAdded` : brancher la logique à chaque réapparition, et gérer le personnage déjà existant.
6. `WaitForChild` uniquement côté client et sur des objets répliqués garantis ; toujours avec un timeout quand l'objet est optionnel. Côté serveur, créer les objets au lieu de les attendre.
7. Pas d'état global mutable partagé entre modules sans propriétaire clair : un seul service possède une donnée, les autres passent par son API.
8. Toute valeur venant du client est **non fiable** (voir skill `roblox-security-datastore`).
9. Boucles : une seule boucle `RunService.Heartbeat` par système, jamais de `while true do task.wait() end` sans condition de sortie liée au cycle de vie.
10. Nombres affichés : formater via `Shared/Util/Format.luau` (1.2K, 3.4M…), jamais de concaténation brute de grands nombres.
11. Pas de `pcall` qui avale les erreurs en silence : logger avec `warn("[Système] message", err)`.
12. Les instances créées en boucle (projectiles, popups, particules) sont **recyclées** ou détruites (`Debris:AddItem` ou `task.delay(d, inst.Destroy, inst)`).
13. **Événements différés** (`SignalBehavior = Deferred`, défaut Roblox) : ne jamais déclencher un événement puis lire tout de suite l'effet de ses handlers ; utiliser `:Once()` pour les attentes uniques.
14. Le code serveur (logique, config secrète, économie) vit dans `ServerScriptService` ; `ReplicatedStorage` ne contient que ce que le client a le droit de lire.
15. Charges utiles des remotes et des sauvegardes : tables **soit tableau, soit dictionnaire à clés chaîne** (jamais mixtes ni à trous), pas de NaN/inf, pas d'Instance dans les sauvegardes.
16. Contenu **data-driven** : objets, zones, quêtes et événements sont des entrées dans `src/shared/Config/*.luau`. Ajouter du contenu ne doit pas demander de nouveau code.
17. **Temps** : toujours `Shared/Util/Clock` (`Clock.now()`, `Clock.unix()`…), jamais `os.time()` / `workspace:GetServerTimeNow()` directement, pour que les tests voyagent dans le temps. Exceptions : `RateLimit` et les mesures purement techniques (`os.clock`).
18. **Textes** : toujours une clé de `Shared/Localization/Strings.luau`, en anglais ET en français (même jeu de variables `{x}`) ; le serveur envoie des clés, le client traduit (`Prefs.t`).
19. Ordres de démarrage explicites : `ORDER` de `Main.server.luau` (un service n'appelle directement que ceux d'avant ; vers le haut, `Server/Signals`) et `ORDER` de `Main.client.luau`. Chaque `require`, `Init` et `Start` est isolé (`xpcall`) : une panne est signalée, la suite démarre.

## Socle existant (repris de Comet Conga : à réutiliser, ne pas réécrire)

Chaque module garde les correctifs de 6 tours de QA et d'un contre-audit anti-triche ; leurs tests sont dans `tests/specs` (fichiers `Fix_*` d'origine gardés pour la traçabilité). La surface d'API est figée par `tests/specs/Contract.spec.luau` : on peut ajouter, jamais retirer ni renommer.

| Module | Usage |
|--------|-------|
| `Shared/Net` + `Shared/Remotes` | déclarer un remote dans `Remotes.luau` (une ligne : type, charge utile, propriétaire), puis `Net.event("Nom")` |
| `Shared/Util/Clock` | heure UTC commune serveur/client ; `freeze`, `advance` pour les tests |
| `Shared/Util/Signal`, `Trove`, `Tables`, `Format`, `Validate` | signaux, nettoyage, copies/reconcile, affichage (nombres géants : suffixes puis « 1.23e45 », FR « 1,24 M »), validation d'entrées |
| `Shared/Localization` (+ `Strings.luau`) | textes EN/FR, `Localization.translator(lang)` |
| `Shared/Config/Settings`, `Console`, `Sounds`, `Monetization` | réglages joueur, couche console (échelle TV, zone sûre, vibrations), sons officiels Roblox, boutique (modèle vide) |
| `Server/Services/DataService` + `Server/Data/Schema` | données joueur : `get`, `waitFor`, `set`, `increment`, `markDirty`, `markDirtyEntry` (une entrée d'une grande table), `saveNow`, `onBeforeSave`, `setStreamOrder`, `Loaded` ; grandes tables envoyées par morceaux (`Schema.STREAMED_KEYS`) |
| `Server/Services/MonetizationService` | `registerProduct`, `ownsPass`, `PassGranted`, `PassPurchased`, `PassRevoked`, `ProductGranted` |
| `Server/Util/RateLimit`, `Analytics`, `Notify` | débit par joueur, analytique sans risque, retours au joueur (`feedback`, `celebrate`, `banner`, `personalBanner`) |
| `Server/Util/MoveCheck` + `Server/Movement/Tuning` | anti-triche de déplacement (budget d'action, gels réseau tolérés) ; seuils serveur seulement |
| `Server/Signals` | bus interne (`ServerMoved`, `MoveViolation`, `BannerRequested`, + ceux du jeu) |
| `Client/Util/Platform`, `Haptics`, `Prefs`, `Prices` | console/écran/entrée et règle du chat, vibrations modérées, réglages appliqués + `Prefs.t`, prix Robux en direct |
| `Client/Controllers/StateController` | `State.get(key)`, `State.observe(key, fn)` |
| `Client/Controllers/AudioController` | `AudioController.play("Click")`, son de navigation manette |
| `Client/UI/Root`, `Theme`, `Create`, `Juice`, `Toast`, `Glyph` | écrans responsives (échelle TV, zone sûre), charte, construction d'UI, effets, notifications, icônes de touches PlayStation/Xbox |
| `src/first/Loading.client.luau` | écran de chargement (Réessayer à la manette, échelle TV, attend `ClientReady`) |

## Performance (budgets PS4 / Xbox One, 16 joueurs)

- Viser ≤ 3 000 parts dans le monde généré, `Anchored = true` et `CanCollide/CanTouch/CanQuery = false` sur tout le décoratif.
- `CastShadow = false` sur les petites pièces décoratives.
- `StreamingEnabled` coupé, mais un objet peut arriver en retard : côté client, `WaitForChild(nom, délai)` **toujours** avec un délai et un repli ; jamais de règle du jeu qui lit la physique (`Touched`, fin d'animation) : distances sur la position validée et minuteurs du serveur (`Clock`) ; chaque état a un délai et une sortie (`Logic/StateTimeouts`).
- Instances en pool, **une seule boucle Heartbeat par système**, budgets nommés (quotas de `RanchRenderer`, `ChaseRenderer`, `VFXController` ; ≤ 3 000 `GuiObject`) ; aucune `ProximityPrompt` (invites dessinées par `UI/Prompt`).
- Effets visuels **côté client** uniquement ; le serveur envoie des événements compacts.
- Remotes : regrouper les mises à jour (au plus ~10 envois/s/joueur), payloads petits (ids, nombres).
- Pas de `:GetDescendants()` par frame ; mettre en cache.

## Outils (à lancer avant chaque commit)

```bash
stylua src tests            # formatage
selene src                  # lint (std luau + roblox_lite.yml)
lune run tests/run          # tests unitaires (harnais qui émule require/Rojo)
rojo build -o build/Game.rbxl   # place jouable à ouvrir dans Roblox Studio
```

Un changement n'est « fini » que si les quatre commandes passent sans erreur.
