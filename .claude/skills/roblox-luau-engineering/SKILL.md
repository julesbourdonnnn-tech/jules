---
name: roblox-luau-engineering
description: Standards d'ingénierie Luau/Roblox de ce projet (Rojo, structure des modules, typage, cycle de vie, nettoyage des connexions, performance, outils selene/stylua/lune). À charger AVANT d'écrire ou de modifier du code Luau dans src/, ou quand on demande « ajoute un système », « nouveau module », « refactor Luau », « Roblox code », « Rojo ».
---

# Ingénierie Luau / Roblox — standards du projet

## Arborescence Rojo (default.project.json)

| Dossier disque  | Instance Roblox                                   | Rôle |
|-----------------|---------------------------------------------------|------|
| `src/shared/`   | `ReplicatedStorage.Shared`                        | Config, constantes, logique pure, types, utilitaires partagés |
| `src/server/`   | `ServerScriptService.Server`                      | Services serveur (autorité absolue sur l'état du jeu) |
| `src/client/`   | `StarterPlayer.StarterPlayerScripts.Client`       | Contrôleurs client : UI, effets, entrées, caméra |

Conventions de fichiers Rojo :
- `Nom.luau` → ModuleScript ; `Nom.server.luau` → Script ; `Nom.client.luau` → LocalScript.
- `init.luau` dans un dossier → le dossier devient le ModuleScript.
- **Un seul point d'entrée par côté** : `src/server/Main.server.luau` et `src/client/Main.client.luau` qui chargent les services/contrôleurs dans un ordre déterministe (`Init()` de tous, puis `Start()` de tous).

## Squelette d'un service / contrôleur

```lua
--!strict
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

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

## Socle existant (à réutiliser, ne pas réécrire)

| Module | Usage |
|--------|-------|
| `Shared/Net` + `Shared/Remotes` | déclarer un remote dans `Remotes.luau`, puis `Net.event("Nom")` |
| `Shared/Util/Signal`, `Trove`, `Tables`, `Format`, `Validate` | signaux, nettoyage, copies/reconcile, affichage, validation d'entrées |
| `Shared/Localization` (+ `Strings.luau`) | textes EN/FR, `Localization.translator(lang)` |
| `Server/Services/DataService` + `Server/Data/Schema` | données joueur, `DataService.get/set/increment/markDirty/saveNow`, `DataService.Loaded` |
| `Server/Services/MonetizationService` | `registerProduct`, `ownsPass`, `PassGranted` |
| `Server/Util/RateLimit` | `RateLimit.allow(player, "Action", n, perSeconds)` |
| `Client/Controllers/StateController` | `State.get(key)`, `State.observe(key, fn)` |
| `Client/Controllers/AudioController` | `AudioController.play("Coin")` |
| `Client/UI/Root`, `Theme`, `Create`, `Juice`, `Toast` | écrans responsives, charte, construction d'UI, effets, notifications |

## Performance (mobile d'abord)

- Viser ≤ 3 000 parts dans le monde généré, `Anchored = true` et `CanCollide/CanTouch/CanQuery = false` sur tout le décoratif.
- `CastShadow = false` sur les petites pièces décoratives.
- `StreamingEnabled` activé ; ne jamais supposer qu'une part lointaine existe côté client.
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
