---
name: roblox-security-datastore
description: Sécurité réseau (RemoteEvents/RemoteFunctions anti-exploit, validation serveur, limitation de débit, anti-triche de déplacement MoveCheck) et persistance DataStore sans perte (session locking, UpdateAsync, retries, BindToClose, migrations, achats MarketplaceService idempotents) de Raise a Squishy, socle repris de Comet Conga. À charger pour toute modification de remotes, d'économie, de sauvegarde, de déplacement, de gamepass ou de produit développeur.
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
- **Session lock** (déjà fait dans `Server/Services/DataService`) : au chargement, poser `record.lock = { jobId = game.JobId, time = os.time(), session = jeton }` (jeton propre à ce chargement) ; chaque écriture vérifie que le verrou porte encore notre `jobId` et notre jeton. Verrou d'un autre serveur de moins de 30 min : réessayer toutes les 6 s, et ne le reprendre qu'après **5 lectures réussies** qui l'ont vu (≥ 30 s d'observation pendant que le DataStore répond ; compter hors de la transformation d'`UpdateAsync`, qui peut être rejouée). **Jamais** le reprendre parce que des erreurs DataStore ont épuisé les essais : renvoi poli (« reviens dans un instant »), rien d'écrit. Le serveur qui détient le verrou réessaie sa sauvegarde de départ après une panne (toutes les 16 s au plus) : garder `RELEASE_RETRY_MAX + 10 ≤ LOCKED_RETRY_DELAY × (LOAD_ATTEMPTS − 1)` (sinon l'enfant qui revient sur un autre serveur perd ses gains de la panne), et `16 joueurs × 60 / RELEASE_RETRY_MAX ≤ 60` essais par minute (budget de base d'`UpdateAsync` d'un serveur plein dont tous les joueurs sont partis). Exemple Comet Conga : 12 joueurs, 5 s et 15 s ; ici 16 joueurs, 6 s et 16 s (`Fix_final_data_lock.spec`).
- **Serveur en ligne sans DataStore** : jamais de repli en mémoire (une session jamais sauvegardée, des achats acquittés puis perdus) ; renvoi poli et nouvel essai en arrière-plan. Repli en mémoire **dans Studio seulement**.
- Sauvegarde de départ en panne : nouveaux essais en arrière-plan (même instantané, crochets `onBeforeSave` jamais rejoués) ; une reconnexion sur le même serveur attend puis charge des données à jour, jamais périmées.
- Chaque écriture `UpdateAsync` d'un profil passe `{ UserId }` (demandes d'effacement de Roblox).
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
- Tous les IDs dans `Shared/Config/Monetization.luau` ; un ID à `0` = désactivé proprement (le bouton d'achat se cache) ; `lune run scripts/prepublish` liste ceux qui manquent avant la publication.
- Reçu acquitté (`PurchaseGranted`) **seulement après une sauvegarde réussie**, y compris pour un reçu rejoué ; serveur en fermeture : `NotProcessedYet` (crédité à la session suivante).
- `PromptGamePassPurchaseFinished` n'est qu'un indice (un exploit peut l'émettre) : `UserOwnsGamePassAsync` fait foi ; vérifications bornées par joueur (`RateLimit` « PassVerify ») et réponse « non possédé » retenue un moment.

## 3 bis. Anti-triche de déplacement (Server/Util/MoveCheck)

Le service du tick de jeu (10 Hz) appelle `MoveCheck.step(player, root.Position, dt, now, groundY)` dans un `pcall`, après `noteSpeed(player, WalkSpeed, now)` à chaque changement de vitesse serveur et `reset(player, pos, now)` à chaque apparition ou `PivotTo` serveur (`Signals.ServerMoved`).

- `"rewind"` → `PivotTo` vers la position rendue ; `"flag"` ou rafale (3e valeur) → **ce tick n'agit sur rien** (aucune capture, boop, ramassage, zone de jeu). Hors tick (action par remote qui exige d'être à un endroit) : `MoveCheck.canAct(player, now)` et `MoveCheck.lastValid(player)`, jamais la racine brute du client.
- Budget d'action (passe de finition de Comet Conga) : un bond ou une chaîne de petits pas trop longs laisse une **dette** ; le joueur n'agit de nouveau qu'une fois remboursé. Les gels réseau honnêtes (0,7 à 1,5 s) ne sont jamais punis.
- Seuils dans `Server/Movement/Tuning` (serveur seulement, jamais répliqués) ; bornes du monde (`CenterX/Z`, `MaxRadius`) et vitesse maximale à régler sur la carte et les montures du jeu ; surface analytique du terrain via `MoveCheck.setSurface(fn)`.
- Jamais d'accusation : l'interface dit « connexion instable » ; aucune collision entre personnages (un enfant porté par un autre ne doit pas passer pour un tricheur, Comet Conga tour 5).

## 4. Classements

- `OrderedDataStore` mis à jour au plus toutes les 60 s par serveur, lecture `GetSortedAsync` toutes les 60-120 s ; affichage via `leaderstats` + panneau dans le monde.
