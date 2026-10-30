---
name: roblox-security-datastore
description: Sécurité réseau (RemoteEvents/RemoteFunctions anti-exploit, validation serveur, limitation de débit) et persistance DataStore sans perte (session locking, UpdateAsync, retries, BindToClose, migrations, achats MarketplaceService idempotents). À charger pour toute modification de remotes, d'économie, de sauvegarde, de gamepass ou de produit développeur.
---

# Sécurité & sauvegarde

## 1. Le client ment toujours

Le client n'envoie que des **intentions** (« je veux acheter l'objet 12 »), jamais des résultats (« j'ai 500 pièces »).

Chaque handler serveur suit cet ordre :

```lua
Remotes.BuyItem.OnServerEvent:Connect(function(player: Player, itemId: unknown)
	-- 1. Débit : refuser si trop d'appels
	if not RateLimit.allow(player, "BuyItem", 5, 1) then return end   -- 5 par seconde
	-- 2. Types : rejeter tout ce qui n'est pas exactement attendu
	if typeof(itemId) ~= "string" or #itemId > 32 then return end
	-- 3. Existence : la clé doit exister dans la config serveur
	local item = Config.Items[itemId]
	if not item then return end
	-- 4. État : le joueur a-t-il ses données chargées ? est-il vivant/à portée ?
	local data = DataService.get(player)
	if not data then return end
	-- 5. Règles métier : coût, prérequis, plafonds
	if data.coins < item.cost then return end
	-- 6. Mutation atomique + notification au client
	data.coins -= item.cost
	...
end)
```

Règles :
- Valider les nombres avec `x == x` (NaN), `math.abs(x) ~= math.huge`, bornes min/max, entier si attendu (`x % 1 == 0`).
- Les chaînes : longueur max ; les tables venant du client sont interdites sauf nécessité (et alors valider chaque champ).
- **Proximité** : pour toute interaction avec un objet du monde, vérifier côté serveur la distance `(root.Position - target.Position).Magnitude <= MAX + marge`.
- **Cooldowns** côté serveur (horodatage `os.clock()` par joueur), le cooldown client n'est que cosmétique.
- Préférer `RemoteEvent` ; `RemoteFunction` uniquement client→serveur (jamais serveur→client : un client peut bloquer le serveur).
- Les remotes sont créés **par le serveur** dans un dossier `ReplicatedStorage.Remotes` au démarrage ; le client les récupère avec `WaitForChild`.
- `UnreliableRemoteEvent` pour les effets purement cosmétiques à haute fréquence.

## 2. DataStore sans perte

- Une clé par joueur : `"player_" .. userId`.
- **Session lock** : à l'écriture, stocker `{ lockId = game.JobId, lockTime = os.time() }` ; au chargement, si un verrou d'un autre serveur a moins de 30 min, réessayer (jusqu'à ~5 fois, 5 s d'écart) puis voler le verrou.
- Toujours `UpdateAsync` (jamais `SetAsync` pour les données joueur).
- Retries avec backoff exponentiel (1, 2, 4, 8 s) sur erreur ; respecter `DataStoreService:GetRequestBudgetForRequestType`.
- Autosave toutes les 60-120 s, sauvegarde à `PlayerRemoving`, et `game:BindToClose` qui sauvegarde tous les joueurs **en parallèle** et attend la fin (≤ 25 s).
- Schéma versionné : `data.version` + fonction `migrate(data)` + fusion avec `DEFAULTS` (`reconcile`) pour ajouter les nouveaux champs sans écraser.
- Si le chargement échoue définitivement : **kicker** le joueur avec un message clair plutôt que de lui donner des données vides qui écraseraient sa sauvegarde.
- En Studio sans accès API : basculer sur un stockage mémoire (`RunService:IsStudio()` + pcall de test) et le signaler dans la sortie.

## 3. Achats (MarketplaceService)

- `MarketplaceService.ProcessReceipt` est **unique** dans tout le jeu (un seul service le définit).
- Idempotence : stocker les `PurchaseId` déjà traités dans les données du joueur (liste bornée, ex. 50 derniers) ; si déjà présent → `PurchaseGranted`.
- Retourner `NotProcessedYet` si le joueur n'est pas là ou si ses données ne sont pas chargées.
- Gamepasses : vérifier `UserOwnsGamePassAsync` (pcall + cache) à l'arrivée, et écouter `PromptGamePassPurchaseFinished` pour accorder immédiatement.
- Tous les IDs dans `Shared/Config/Monetization.luau` ; un ID à `0` = désactivé proprement (le bouton d'achat se cache).

## 4. Classements

- `OrderedDataStore` mis à jour au plus toutes les 60 s par serveur, lecture `GetSortedAsync` toutes les 60-120 s ; affichage via `leaderstats` + panneau dans le monde.
