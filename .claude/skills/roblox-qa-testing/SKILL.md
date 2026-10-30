---
name: roblox-qa-testing
description: Assurance qualité du jeu Roblox — harnais de tests Lune (tests/harness) qui simule Roblox (require Rojo, Players, DataStore, Marketplace, remotes), écriture de specs, classes de bugs Roblox à traquer et checklist avant publication. À charger pour écrire/lancer des tests, chasser un bug, faire une revue de code ou préparer une release.
---

# QA & tests

## Lancer les vérifications

```bash
stylua --check src tests     # formatage
selene src                   # lint
lune run tests/run           # tous les tests
lune run tests/run -- Data   # seulement les specs dont le chemin contient « Data »
rojo build -o build/Game.rbxl
```

## Le harnais (tests/harness)

`Harness.new({ mode = "server" | "client", touch = bool })` monte `src/` comme Rojo dans un DataModel simulé :

| API | Effet |
|-----|-------|
| `h:require("ReplicatedStorage.Shared.Config")` | charge un module avec un vrai `require(script.Parent.X)` |
| `h:boot()` | exécute `Main.server.luau` (ou `Main.client.luau` en mode client) |
| `h:addPlayer({ userId = 1, name = "A", locale = "fr-fr" })` | PlayerAdded + personnage |
| `h:removePlayer(p)` / `h:respawn(p)` | départ / réapparition |
| `h:fireServer("ReplicatedStorage.Remotes.X", p, ...)` | simule un client (y compris un tricheur) |
| `h:invokeServer(path, p, ...)` | RemoteFunction |
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
| `h:warnings()` | `warn()` + « Infinite yield possible » |
| `h.log.kicks`, `h.log.prompts`, `h.log.analytics` | journaux |

Fidélité volontaire :
- Chaque connexion de signal tourne dans son propre thread ; **une erreur dans une connexion fait échouer le test** (comme une ligne rouge dans la sortie Studio).
- Accéder à un enfant inexistant d'un dossier de scripts lève « X is not a valid member » (fautes de chemin).
- Le DataStore simulé refuse ce que Roblox refuse : Vector3/Instance, NaN/inf, tables mixtes.
- `wait()`, `spawn()`, `delay()` lèvent une erreur.
- `Random.new(seed)` est déterministe.

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

Fichiers : `tests/specs/<Système>.spec.luau`. Une spec par système, et des tests de **démarrage complet** (`Boot.spec.luau`) qui lancent serveur et client et simulent 3 joueurs pendant plusieurs centaines de frames.

## Classes de bugs Roblox à traquer systématiquement

1. **Course au démarrage** : joueur arrivé avant la connexion `PlayerAdded` ; personnage chargé avant `CharacterAdded`.
2. **Données pas encore chargées** : remote reçu avant la fin du chargement DataStore → handler doit ignorer (`if not data then return end`).
3. **Joueur parti pendant un yield** : après chaque `GetAsync`/`task.wait`, vérifier `player.Parent ~= nil`.
4. **Personnage mort/absent** : `player.Character` nil, `HumanoidRootPart` nil, `Humanoid.Health <= 0`.
5. **Fuites** : connexions jamais déconnectées, tables indexées par `Player` jamais vidées à `PlayerRemoving`.
6. **Remotes abusés** : spam, types inattendus (table, NaN, chaîne énorme), objets hors de portée, ids inexistants.
7. **Double récompense** : clic multiple, ProcessReceipt rejoué, quête validée deux fois, récompense quotidienne réclamée en boucle (comparer avec l'horodatage serveur `os.time()`, jamais celui du client).
8. **Économie** : nombres négatifs, débordements, arrondis (toujours `math.floor` pour la monnaie), multiplicateurs cumulés involontairement.
9. **UI** : textes qui débordent sur petit écran, boutons sous le joystick/saut mobile, tweens concurrents sur la même propriété, panneaux ouverts en double.
10. **Respawn** : UI détruite à la réapparition (`ResetOnSpawn = false`), effets attachés à l'ancien personnage.
11. **Arrêt serveur** : `BindToClose` doit sauvegarder tout le monde avant 30 s.
12. **StreamingEnabled** : le client suppose qu'une part lointaine existe → `WaitForChild` infini.

## Checklist release

- [ ] Les 4 commandes de vérification passent.
- [ ] Test de démarrage complet : 0 erreur, 0 avertissement « Infinite yield ».
- [ ] Test « tricheur » : chaque remote reçoit des charges invalides sans erreur ni effet.
- [ ] Test DataStore : pannes simulées → retries → aucune perte ; données corrompues → migration/reconcile.
- [ ] Achats : ProcessReceipt idempotent (même PurchaseId deux fois = un seul crédit).
- [ ] Studio : jouer en mode « Local Server » avec 3 joueurs, émulateur téléphone (iPhone SE + tablette) et manette.
