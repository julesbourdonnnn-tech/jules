# Comet Conga — Guide de publication (du dépôt au jeu en ligne)

> **Document 05.** Version du 31 octobre 2026, mise à jour le 1er novembre 2026 (sons, sauvegardes en panne, serveur trop grand). Pour le propriétaire du jeu : aucune connaissance en programmation n'est nécessaire.
> Le jeu est entièrement écrit en code dans ce dossier. Ce guide explique comment le transformer en jeu Roblox publié, pas à pas.
> Documents liés : [`06-rapport-qualite.md`](06-rapport-qualite.md) (ce qui est vérifié, plan de test dans Studio), [`07-console-ps5.md`](07-console-ps5.md) (manette et téléviseur), [`02-game-design-document.md`](02-game-design-document.md) (règles du jeu, §8 monétisation, §14 analytics, §15 lancement).

**Comment lire ce guide**

- Les étapes sont dans l'ordre. Cochez-les au fur et à mesure.
- **« à vérifier »** signale une étape que nous n'avons pas pu confirmer dans une documentation officielle de Roblox. Roblox renomme souvent ses menus (Studio et Creator Hub). Si un menu porte un autre nom, prenez le plus proche. Tant que le jeu est **privé**, une erreur de réglage ne touche aucun joueur.
- Les textes `comme ceci` sont des noms de fichiers ou des commandes à recopier tels quels.
- Les modifications de fichiers décrites ici sont petites (coller un numéro, ajouter une ligne). Après chaque modification, relancez la vérification (`./scripts/check.sh`, étape 2.2) ou demandez à l'équipe technique de le faire.

## Sommaire

1. Installer les outils
2. Construire le jeu
3. Tester dans Roblox Studio
4. Première publication (privée) et sauvegardes
5. Créer les 6 passes et les 6 produits, puis coller leurs numéros
6. Réglages à faire dans le code avant le lancement
7. Paramètres de l'expérience (12 joueurs, appareils, genre, accès)
8. Questionnaire de maturité du contenu
9. Page du jeu : titre, description, icône, miniatures
10. Langues : français et anglais
11. Jouer sur PlayStation 5
12. Check-list avant le lancement
13. Le jour du lancement
14. Check-list après le lancement (analytics)
15. Publier une mise à jour plus tard
16. Récapitulatif des fichiers à modifier

---

## 1. Installer les outils

### 1.1 Roblox Studio

1. Créez (ou utilisez) votre compte Roblox. Ce compte sera **propriétaire** du jeu.
2. Téléchargez **Roblox Studio** depuis le site officiel de Roblox (page *Create*), installez-le, puis connectez-vous avec ce compte.

### 1.2 Rojo et les autres outils (Rokit, recommandé)

Rojo transforme les fichiers du dossier `src/` en une « place » Roblox. Le projet indique les versions exactes de ses outils dans `rokit.toml` (Rojo 7.7.1, Selene, StyLua, Lune).

1. Installez **Rokit** (gestionnaire d'outils pour Roblox, site : https://github.com/rojo-rbx/rokit).
2. Ouvrez un terminal dans le dossier du projet, puis tapez :

   ```bash
   rokit install
   ```

   Cette commande installe Rojo, Selene, StyLua et Lune aux bonnes versions.

**Si vous utilisez déjà Aftman** (ancien outil équivalent) : le projet ne fournit pas de fichier `aftman.toml`. Installez au minimum Rojo avec `aftman add rojo-rbx/rojo@7.7.1`. Rokit reste le choix le plus simple.

### 1.3 Le plugin Rojo dans Studio (pour la synchronisation en direct, facultatif)

Le plugin permet à Studio de recevoir les fichiers du projet pendant que vous travaillez. Deux façons de l'installer :

- dans un terminal : `rojo plugin install` (Studio doit être fermé, puis rouvert) ;
- ou dans Studio, depuis la boutique des plugins (Creator Store), en cherchant **Rojo** (publié par l'équipe Rojo).

Vous n'avez **pas besoin** du plugin pour publier : la méthode simple de l'étape 2 suffit.

---

## 2. Construire le jeu

### 2.1 Fabriquer le fichier du jeu

Dans un terminal, dans le dossier du projet :

```bash
rojo build -o build/Game.rbxl
```

Le fichier `build/Game.rbxl` contient tout le jeu : l'île, l'interface, les effets, les règles. Il ne dépend d'aucun fichier extérieur (aucune image ni modèle téléversé).

### 2.2 Vérifier que tout est correct

```bash
./scripts/check.sh
```

Cette commande enchaîne cinq contrôles : formatage du code, analyse du code, **tous les tests automatiques**, construction de `build/Game.rbxl` et contrôle du fichier construit. Elle doit finir par **« ✅ Tout est vert. »**. Si un contrôle échoue, ne publiez pas : transmettez le message à l'équipe technique.

Avant une publication **en ligne**, lancez aussi `lune run scripts/prepublish` : il doit afficher « ✅ Boutique prête » (les 12 numéros du Creator Hub sont collés, §5.5). Tant que ce n'est pas le cas, il liste les articles encore à `0` et échoue ; `./scripts/check.sh` reste vert, lui, car la boutique vide est un état normal pendant le développement (l'icône Boutique est alors masquée).

### 2.3 Variante « en direct » (facultatif)

```bash
rojo serve
```

Puis, dans Studio, ouvrez le plugin Rojo et cliquez sur **Connect** (adresse `localhost`, port `34872`). Chaque fichier modifié dans `src/` est alors recopié tout de suite dans Studio. Pratique pour régler un chiffre et le tester aussitôt.

---

## 3. Tester dans Roblox Studio

### 3.1 Ouvrir le jeu

Double-cliquez sur `build/Game.rbxl` : Studio s'ouvre sur l'île de Lumora. (Ou, dans Studio : *File › Open from File*.)

### 3.2 Jouer seul (Play)

1. Cliquez sur **Play** (touche F5).
2. Vérifiez la première minute : écran « Ton Nid se réveille… », première capture de Nebby, première parade au Nid, premier achat dans **Améliorer**.
3. Ouvrez la fenêtre **Output** (*View › Output*) : il ne doit y avoir **aucune ligne rouge**.
4. Avant la première publication, un avertissement est normal : `[DataService] DataStore indisponible dans Studio (…) : sauvegarde EN MÉMOIRE uniquement.` Le jeu fonctionne, mais rien n'est gardé entre deux essais. L'étape 4.2 corrige cela.
5. Cliquez sur **Stop**.

### 3.3 Jouer à plusieurs (serveur local)

1. Onglet **Test** › zone *Clients and Servers* : choisissez **Local Server** et **2 à 4 joueurs**, puis **Start**. Studio ouvre une fenêtre « serveur » et une fenêtre par joueur. (Noms des menus : à vérifier dans votre version de Studio.)
2. Testez ce qui demande plusieurs joueurs : couper la file d'un autre (« SNIP ! »), le bouclier débutant, les équipages, la Grande Comète, la roue de pings.
3. Fermez toutes les fenêtres avec **Cleanup** / **Stop**.

Le plan de test complet dans Studio (téléphone, manette, latence, 30 minutes de jeu…) est dans [`06-rapport-qualite.md`](06-rapport-qualite.md) §5.

### 3.4 Simuler un téléphone

Onglet **Test** › **Device** (émulateur d'appareil) : choisissez un petit téléphone puis une tablette, et rejouez la première minute. Le jeu est conçu **d'abord pour le téléphone** (joystick + un seul bouton : Dash). L'émulateur ne mesure ni la mémoire ni la vitesse réelles : un essai sur un vrai téléphone Android modeste reste nécessaire (§12).

---

## 4. Première publication (privée) et sauvegardes

### 4.1 Publier

1. Dans Studio, avec `build/Game.rbxl` ouvert : *File › Publish to Roblox* (Alt + P).
2. Choisissez **créer une nouvelle expérience**. Nom : **Comet Conga** (voir §12 : vérifier d'abord que le nom est libre). Propriétaire : votre compte (ou votre groupe).
3. Validez. Le jeu existe maintenant sur Roblox. Gardez-le **privé** jusqu'au lancement (§7.4). Nouvelle expérience privée par défaut : à vérifier.

### 4.2 Activer l'accès aux sauvegardes (DataStores) dans Studio

Sans ce réglage, les essais dans Studio n'enregistrent rien (sauvegarde en mémoire, voir §3.2).

1. Dans Studio : **Game Settings** (onglet *Home*) › **Security**.
2. Activez **Enable Studio Access to API Services**, puis **Save**.
3. Relancez **Play** : l'avertissement `DataStore indisponible` ne doit plus apparaître ; votre Glow est retrouvé d'un essai à l'autre.

**Attention après le lancement** : avec ce réglage, les essais dans Studio écrivent dans les **vraies** sauvegardes des joueurs (dont la vôtre). Une fois le jeu public, faites vos essais risqués dans une **copie** du jeu (une seconde expérience privée) ou désactivez ce réglage.

**En ligne, jamais de sauvegarde « en mémoire »** : ce repli n'existe que dans Studio. Si les sauvegardes de Roblox sont en panne quand un joueur arrive sur un serveur en ligne, il est renvoyé avec le message « Tes données n'ont pas pu être chargées, reviens dans un instant. » et peut revenir plus tard ; aucun achat n'est validé tant que sa progression ne peut pas être sauvegardée. Si la panne arrive pendant la partie, le serveur réessaie de sauvegarder les joueurs qui partent pendant 5 minutes au plus ; au-delà, il écrit une ligne `[DataService] PERTE` dans le journal (§14.4).

---

## 5. Créer les 6 passes et les 6 produits, puis coller leurs numéros

Toute la boutique est décrite dans `src/shared/Config/Monetization.luau`. Chaque article a un numéro `id` qui vaut aujourd'hui **0**. **Un `id` à 0 cache l'article** : il n'apparaît pas dans la boutique et rien n'est proposé à l'achat. Le jeu peut donc être publié avec seulement une partie de la boutique.

**Règle du jeu** (GDD §8.1) : aucun objet aléatoire payant, rien qui donne un avantage contre les autres joueurs. Ne créez pas d'autres articles sans en parler à l'équipe.

### 5.1 Les 6 game passes (achat définitif)

| Clé dans le fichier | Nom à donner dans le Creator Hub | Prix (Robux) | Ce que le joueur reçoit |
|---|---|---|---|
| `VIPStar` | **VIP Star** | **199** | +25 % de Glow, badge doré ★ VIP, Nid Or Royal, file Étoile Royale, +1 relance de quête par jour |
| `DoubleGlow` | **Double Glow** | **299** | ×2 sur le revenu passif et les parades |
| `NightShift` | **Night Shift** | **99** | Gains hors ligne à 75 % pendant 12 h (au lieu de 50 % pendant 8 h) |
| `ExtraPerches` | **Extra Perches** | **149** | +6 perchoirs |
| `StashPlus` | **Stash Plus** | **99** | Réserve 300 → 600 places |
| `CongaStyles` | **Conga Styles** | **79** | 6 styles de file cosmétiques |

### 5.2 Les 6 produits développeur (achat répétable)

| Clé dans le fichier | Nom à donner dans le Creator Hub | Nom affiché en français dans le jeu | Prix (Robux) | Ce que le joueur reçoit |
|---|---|---|---|---|
| `GlowPouch` | **Glow Pouch** | Bourse de Glow | **25** | 10 min de son revenu passif (au moins 1 000 Glow) |
| `GlowSack` | **Glow Sack** | Sac de Glow | **89** | 40 min de son revenu passif (au moins 4 000) |
| `GlowCrate` | **Glow Crate** | Caisse de Glow | **199** | 120 min de son revenu passif (au moins 12 000) |
| `GlowParty` | **Glow Party** | Glow Party | **99** | Glow ×2 pour **tout le serveur** pendant 10 min |
| `StardustJar` | **Stardust Jar** | Bocal de Stardust | **49** | 400 Stardust |
| `StarterKit` | **Starter Kit** | Starter Kit | **49** | 3 Nebbies Rares (Cometcub, Frostfinch, Daybreak Puff), file Comet Tail, Glow ×2 pendant 20 min. **Une fois par compte** |

Les noms et descriptions affichés **dans la boutique du jeu** viennent du fichier de textes `src/shared/Localization/Strings.luau` (anglais et français). Le nom saisi dans le Creator Hub apparaît surtout dans la **fenêtre d'achat de Roblox** : utilisez le nom anglais du tableau.

**Le prix qui compte est celui du Creator Hub** : le jeu lit le vrai prix au moment de l'affichage (module `src/client/Util/Prices.luau`). Le prix du fichier ne sert que de secours. Mettez quand même les mêmes prix aux deux endroits.

### 5.3 Créer un game pass dans le Creator Hub

1. Ouvrez le **Creator Hub** (https://create.roblox.com/dashboard/creations) et cliquez sur **Comet Conga**.
2. Menu de gauche : **Monetization › Passes** (à vérifier), puis **Create a Pass**.
3. Nom (tableau 5.1), description courte (colonne « Ce que le joueur reçoit »), image facultative. Créez.
4. Ouvrez le pass, partie **Sales** (vente) : mettez-le **en vente** et saisissez le **prix** du tableau. Enregistrez. (Noms exacts : à vérifier.)
5. Copiez son **numéro** (ID) : il apparaît dans l'adresse de la page du pass ou dans le menu « ⋯ » (*Copy Asset ID*, à vérifier). C'est un grand nombre, par exemple `1234567890`.
6. Recommencez pour les 6 passes.

### 5.4 Créer un produit développeur

1. Même expérience : **Monetization › Developer Products** (à vérifier), puis **Create a Developer Product**.
2. Nom et prix du tableau 5.2, description courte. Enregistrez.
3. Copiez son **numéro** (ID) (menu « ⋯ », *Copy Product ID*, à vérifier).
4. Recommencez pour les 6 produits.

### 5.5 Coller les numéros dans le jeu

Ouvrez `src/shared/Config/Monetization.luau` avec un éditeur de texte (Visual Studio Code, ou même le Bloc-notes). Pour chaque article, remplacez **seulement** le `0` de la ligne `id = 0,` par le numéro copié. Exemple pour VIP Star :

```lua
	VIPStar = {
		id = 1234567890,   -- ← avant : id = 0,
		price = 199,
```

Ne touchez à rien d'autre (virgules, accolades). Si vous avez changé un prix dans le Creator Hub, changez aussi `price` ici.

Ensuite :

1. `./scripts/check.sh` → « ✅ Tout est vert. » ;
2. lancer `lune run scripts/prepublish` avant de publier (doit afficher « ✅ Boutique prête ») : tant qu'un des 12 numéros est encore à 0, le script liste les articles à compléter et échoue ;
3. `rojo build -o build/Game.rbxl`, ouvrir le fichier, *File › Publish to Roblox* vers **la même expérience** (étape 15) ;
4. dans Studio, **Play**, ouvrez la **Boutique** : les articles apparaissent avec leur prix. Achetez chaque article : **dans Studio, les achats sont des achats d'essai, gratuits**. Vérifiez que chaque effet arrive (Glow, Stardust, Nebbies, styles, ×2…).

---

## 6. Réglages à faire dans le code avant le lancement

### 6.1 Administrateurs (événements « LiveOps »)

Un administrateur peut déclencher, sur **tous les serveurs**, une Comète supplémentaire, une météo, une Starfall Frenzy ou une Nuit d'Or (pratique pendant un live). La liste est dans `src/server/Data/Admins.luau`, vide aujourd'hui (fonction désactivée).

1. Trouvez votre **UserId** : sur roblox.com, ouvrez votre profil ; l'adresse ressemble à `roblox.com/users/123456789/profile` ; le nombre est votre UserId.
2. Dans `src/server/Data/Admins.luau`, remplacez la ligne

   ```lua
   local Admins: { [number]: boolean } = {}
   ```

   par (une ligne `[UserId] = true,` par administrateur) :

   ```lua
   local Admins: { [number]: boolean } = {
   	[123456789] = true,
   }
   ```

3. Dans le jeu, un administrateur voit une section **LiveOps** en bas du panneau **Réglages**. Les autres joueurs ne la voient pas, et le serveur refuse la commande s'ils essaient quand même.

N'ajoutez que des personnes de confiance. Cette liste reste sur le serveur, elle n'est jamais envoyée aux joueurs.

### 6.2 Codes promo

Les codes sont dans `src/server/Data/Codes.luau`. Un code de lancement existe déjà :

| Code | Récompense | Valable jusqu'au |
|---|---|---|
| `COMETCONGA` | 200 Stardust + 10 min de Glow ×2 | 31/12/2027 23:59:59 UTC |

Chaque code ne marche **qu'une fois par compte**. Pour en ajouter un, copiez le bloc `COMETCONGA = { … },` et changez :

- le **nom** : lettres majuscules A-Z et chiffres seulement, 20 caractères au plus ;
- `expires` : la date de fin en « secondes Unix » (UTC). Demandez-la à l'équipe ou utilisez un convertisseur de date Unix ;
- `reward` : au choix `glow`, `stardust`, `boostSeconds` (durée du ×2 en secondes), `idleSeconds` + `minGlow` (comme les produits Glow), `species` (numéro d'espèce).

Le GDD (§7.7) prévoit un nouveau code chaque semaine, annoncé sur les réseaux, publié le samedi à 17:00 UTC.

### 6.3 Date du premier Starfall Saturday (obligatoire si vous ne publiez pas le 7 novembre 2026)

Chaque samedi à 16:00 UTC, le show **Starfall Saturday** met en avant une espèce. Pendant les **12 premières semaines** après le lancement, chaque espèce vedette peut porter la variante rare **Starborn**, une seule fois (vraie rareté, GDD §8.1). Le jeu doit donc connaître la **semaine du premier show**.

Dans `src/shared/Config/Events.luau`, la ligne `LaunchWeek = 2966,` correspond au show du **samedi 14/11/2026**, pour une publication le samedi 07/11/2026. Si vous publiez à une autre date, remplacez 2966 par le numéro du **premier samedi qui suit la publication** :

| Premier show (samedi, 16:00 UTC) | `LaunchWeek` |
|---|---|
| 14/11/2026 | 2966 |
| 21/11/2026 | 2967 |
| 28/11/2026 | 2968 |
| 05/12/2026 | 2969 |
| 12/12/2026 | 2970 |
| 19/12/2026 | 2971 |
| 26/12/2026 | 2972 |
| 02/01/2027 | 2973 |
| 09/01/2027 | 2974 |
| 16/01/2027 | 2975 |

(Une semaine plus tard = +1.) Le GDD (§7.6) conseille aussi de déclarer ce show comme **Experience Event** dans le Creator Hub (à vérifier : emplacement exact du menu).

### 6.4 Sons (à écouter avant le lancement)

**Ce qui est déjà fait.** Le jeu a ses 27 sons, déjà branchés : boutons, navigation à la manette, musique de fond, capture, coupe « SNIP ! », parade, Dash, Comète, Balise, Supernova, pings… Ce sont tous des **sons publiés par Roblox lui-même** dans ses dépôts officiels (Roblox/resources et Roblox/creator-docs sur GitHub). Ils sont donc publics et utilisables sans rien téléverser. La liste est dans `src/shared/Config/Sounds.luau` : une ligne par son, avec sa source écrite au bout de la ligne. Le détail (quel son pour quel moment, d'où il vient) est dans le rapport qualité ([`06-rapport-qualite.md`](06-rapport-qualite.md) §6.3.4).

**Ce qui reste à faire : écouter.** Aucun test automatique ne peut dire si un son est joli, pas trop fort, ou toujours disponible chez Roblox. Avant le lancement, jouez dans Studio **avec le son** (test M12 du rapport qualité) et notez les sons qui ne vont pas.

- Écoutez d'abord les **neuf sons « à confirmer à l'écoute »** (mention écrite sur leur ligne) : `CometWarn` (alerte de la Comète, peut-être trop discret) et `Ping` (petit « clink ») en premier, car ce sont des enregistrements nouveaux ; puis `Scatter` (Nebbies dispersés après une coupe), `Bank` (encaissement), `Dash`, `CometSwipe` (Comète volée), `BeaconStart` (début de la Nuit de la Balise), `WispPop` (Gloomwisp éclaté) et `Cheer` (acclamation). Ces sept-là réemploient un son déjà choisi, joué plus grave ou plus aigu.
- Puis tous les autres, musique comprise, en naviguant dans les menus au toucher et à la manette.

**Changer un son qui ne vous plaît pas : demandez-le à l'équipe technique (ou à Claude).** Ce n'est pas difficile, mais trois règles sont vérifiées par les tests :

1. **Le vider** : remplacer le numéro par `""` (exemple : `CometWarn = { id = "", volume = 0.7 },`). Le son devient muet ; le jeu reste entièrement jouable. Exception : les huit sons d'interface (`Click`, `Pop`, `Error`, `Whoosh`, `Select`, `Back`, `Tab`, `Bump`) doivent rester remplis, car la PS5 a besoin de retours sonores : on les remplace, on ne les vide pas.
2. **Le remplacer** : mettre un autre numéro, au format exact `"rbxassetid://<nombre>"` (un nombre seul ou une adresse de page donnerait un son muet), et écrire sa source en commentaire au bout de la même ligne. Aujourd'hui, les tests n'acceptent que des sons tirés des deux dépôts officiels de Roblox (le commentaire doit citer `Roblox/resources` ou `Roblox/creator-docs` et le fichier source). Un son pris ailleurs, par exemple dans le Creator Store, demande d'adapter cette règle, et de vérifier qu'il est bien utilisable dans votre jeu (droits d'utilisation : à vérifier sur sa page).
3. **Mettre le test des sons à jour en même temps** : `tests/specs/Fix_r5_audio.spec.luau` garde le numéro, le volume et la hauteur de 20 des 27 sons (tous sauf sept sons d'interface). Après un changement, `./scripts/check.sh` signale ce test en rouge tant qu'il n'est pas mis à jour : c'est normal, il sert à éviter les changements par erreur. Ne publiez qu'une fois la vérification de nouveau verte.

Le volume (`volume` : 0.5 = moyen, plus petit = plus doux) et la hauteur (`pitch` : 1 = normale, plus grand = plus aigu) se règlent sur la même ligne, avec la même mise à jour du test.

---

## 7. Paramètres de l'expérience

Ces réglages se font dans le **Creator Hub** (page de l'expérience) ou dans **Studio › Game Settings**. Emplacements exacts : à vérifier.

### 7.1 Nombre de joueurs : 12

Le jeu a **12 Nids** : un serveur ne doit jamais dépasser **12 joueurs**. Le fichier du projet indique déjà 12, mais **c'est le réglage du Creator Hub qui fait foi** en ligne (docs/04 §16, point 24).

- Creator Hub › expérience › **Places** › place de départ › réglages d'accès : **taille du serveur (Server Size / Max Players) = 12** (à vérifier).
- Avec une taille plus grande, les joueurs au-delà du 12e n'ont pas de Nid : ils voient un message, puis sont renvoyés poliment après 30 s (« Cette île est pleine ! Rejoins un autre serveur. ») sauf si un Nid se libère entre-temps. Gardez donc **12**.
- Remplissage des serveurs (*Server Fill*) : **remplir au maximum** (GDD §16, risque 6 : un serveur plein est plus amusant) (à vérifier).

### 7.2 Appareils

Cochez **téléphone, tablette, ordinateur**. Pour la **console** (PlayStation, Xbox), suivez d'abord le §11. Pas de VR. (Liste « Playable Devices » dans *Game Settings › Basic Info* : à vérifier.)

### 7.3 Genre

Genre **Simulation** (GDD §0 : collection + revenu passif + améliorations + renaissance). Choisissez le sous-genre le plus proche d'un jeu de collection et de progression (par exemple un « simulateur incrémental », à vérifier dans la liste). Le genre aide Roblox à recommander le jeu aux bons joueurs.

### 7.4 Accès

- **Privé** jusqu'au lancement (vous et les testeurs invités).
- **Public** le jour du lancement (§13).

### 7.5 Serveurs privés

Le GDD prévoit des **serveurs privés gratuits** (§4.16) : le propriétaire d'un serveur privé peut désactiver les coupes pour jouer entre amis. Activez les serveurs privés au prix de 0 Robux (menu : à vérifier).

---

## 8. Questionnaire de maturité du contenu

**Obligatoire.** D'après la documentation officielle de Roblox (*Content maturity and compliance*) : un jeu sans informations de maturité est **automatiquement restreint** pour tous les joueurs. Il faut aussi y répondre pour être disponible sur **console**.

**Où** (chemin confirmé par la documentation officielle) :

1. Creator Hub (Creator Dashboard) › cliquez sur la vignette de **Comet Conga** › page *Overview*.
2. Menu de gauche : **Publish settings › Content rating**.
3. **Start** (ou **Restart** si vous l'avez déjà rempli), répondez à chaque page, **Save and Continue**.
4. La page **Questionnaire Preview** montre vos réponses, l'étiquette obtenue et les régions éventuellement non conformes. **Edit** pour corriger, sinon **Submit** : l'étiquette s'affiche aussitôt sur la page du jeu.

**Objectif** : étiquette **Minimal** (au pire **Mild**). Les deux rendent le jeu accessible aux catalogues enfants de Roblox (*Roblox Kids*, 5-8 ans, et *Roblox Select*, 9-15 ans). Roblox ajoute pour ces catalogues d'autres conditions de publication que nos documents ne détaillent pas : à vérifier dans la page officielle *Roblox Kids and Select*.

**Répondez toujours honnêtement**, en pensant au contenu **le plus fort** du jeu. Une réponse fausse peut entraîner une modération du jeu et du compte. Réponses qui décrivent Comet Conga tel qu'il est :

| Catégorie | Réponse | Pourquoi |
|---|---|---|
| Violence | Non, ou au plus « Mild » | Personne n'est blessé : la « coupe » détache des Nebbies de la file, qui sautent un peu plus loin, étourdis une seconde, puis peuvent être rattrapés. Si vous jugez que couper une file est une forme de violence, répondez « Mild » : avec « Occasional », l'étiquette reste Minimal ; avec « Repeated » (les coupes sont fréquentes), elle devient **Mild**, toujours accessible aux enfants |
| Sang | Non | Aucun sang |
| Peur | Non | Les Gloomwisps sont de petites boules indigo aux yeux ronds, « toujours mignonnes, jamais de dents ni de cri » (GDD §11.6), dont on voit le trajet à l'avance |
| Humour grossier | Non | — |
| Jeux d'argent (non jouables) | Non | — |
| Langage grossier | Non | Les textes du jeu sont écrits par nous |
| Thèmes romantiques, alcool | Non | — |
| Lieu de rencontre social (*social hangout*) | Non | Le but est d'attraper et de collectionner, pas de discuter |
| Création libre (dessin…) | Non | Rien n'est dessiné par les joueurs |
| Sujet sensible | Non | — |
| **Objets aléatoires payants** | **Non** | Tous les achats sont fixés d'avance (GDD §8.1) ; rien ne s'achète au hasard |
| **Échange d'objets payés** | **Non** | Aucun échange entre joueurs |
| Médias partagés | Non | Le jeu n'a pas d'outil de partage de vidéos ou d'images |
| Interaction avec une IA générative | Non | Aucune IA dans le jeu |

À **refaire** à chaque mise à jour qui changerait une de ces réponses (règle officielle).

---

## 9. Page du jeu : titre, description, icône, miniatures

### 9.1 Titre et description

- Titre : **Comet Conga** (après la vérification du nom, §12).
- Accroche (GDD §0) : « Attrape des bébés comètes, mène la plus longue conga lumineuse du ciel… et ne te fais pas couper ! » / *“Catch baby comets, lead the longest glowing conga in the sky… and don't get snipped!”*
- Description : en 3 lignes, la boucle du jeu (attraper → faire la file → parader au Nid → améliorer), puis les rendez-vous (Comète toutes les 10 min, Nuit de la Balise, Starfall Saturday chaque samedi 16:00 UTC) et le code `COMETCONGA`. Mots-clés du genre (collection, simulateur), sans liste de mots-clés artificielle.

### 9.2 Icône (une image carrée)

L'icône décide si un joueur clique (taux de clic, docs/01). Elle doit se lire en tout petit :

- **un** Nebby en gros plan, joyeux, très lumineux, sur le ciel du crépuscule ;
- derrière lui, le début d'une file de Nebbies colorés (la « conga ») ;
- pas de texte, ou seulement « Comet Conga » très lisible ;
- couleurs vives (or, rose, violet), fond sombre pour faire ressortir la lumière.

### 9.3 Miniatures (3 à 5 images au format paysage)

Moments à montrer (GDD §6.8, « moments viraux ») :

1. **Une conga de 50 Nebbies** qui serpente dans le Cratère (l'image « signature ») ;
2. **« SNIP ! »** : une file coupée qui explose en Nebbies, joueurs qui se précipitent ;
3. **la Grande Comète** : faisceau doré, joueur porteur poursuivi ;
4. **une parade** au Nid avec les Nebbies perchés ;
5. **la Supernova** : flash et sphère de lumière.

**Comment les obtenir** : le jeu est construit en code, il n'existe donc pas d'images toutes faites. Faites des **captures d'écran en jeu** (dans Studio ou en ligne, à plusieurs pour avoir des files longues), en masquant l'interface si possible (option de Roblox pour masquer l'interface, à vérifier), puis téléversez-les dans le Creator Hub (page de l'expérience, partie des visuels, à vérifier). Les dimensions demandées sont indiquées sur cette page.

---

## 10. Langues : français et anglais

- **Déjà dans le jeu** : tous les textes existent en **anglais et en français** (`src/shared/Localization/Strings.luau`). Le jeu choisit seul : français si la langue du compte du joueur est le français, anglais sinon. Le joueur peut aussi choisir dans **Réglages › Langue** (Auto / English / Français).
- **Autres langues** : le jeu laisse la traduction automatique de Roblox traduire les textes de l'interface. Dans le Creator Hub, partie **Localization** de l'expérience : activez la capture automatique des textes et la traduction automatique (noms : à vérifier).
- **Page du jeu** : dans la même partie Localization, ajoutez le **français** et traduisez le titre et la description (à vérifier).
- Les noms propres restent identiques dans les deux langues : Nebby, Nest, Glow, Stardust, Supernova, Comet Conga, Lumora… (GDD §13.1).

---

## 11. Jouer sur PlayStation 5

Le jeu est prévu pour la manette **DualSense** et un téléviseur vu à environ 3 m : interface agrandie, zone sûre du téléviseur, icônes PlayStation sur les boutons, tout se fait à la manette sans curseur, vibrations modérées, pas de fenêtre de chat. Le détail technique est dans [`07-console-ps5.md`](07-console-ps5.md).

> **Sources de cette section** : uniquement la documentation officielle de Roblox (*Console development guidelines*, *Gamepad input*, *Content maturity and compliance*) et `docs/07-console-ps5.md`. Tout ce que ces documents ne confirment pas est marqué **« à vérifier »**.

### 11.1 Ce que Roblox exige pour la console

| Règle | Source | État dans Comet Conga |
|---|---|---|
| Fournir les informations de **maturité du contenu** : « toujours » pour un jeu conçu pour la console, pour une sortie sans accroc et pour limiter le risque d'être retiré des consoles | *Console development guidelines* | À faire : questionnaire du §8 |
| Interface « 10 pieds » (joueur à 2,5-3 m de l'écran), zone sûre du téléviseur | *Console development guidelines* | Fait (docs/07 §3, §4) |
| Tout atteindre avec les 4 directions + valider + retour, actions clés en peu de gestes | *Console development guidelines* | Fait (docs/07 §6, §7), vérifié par les tests automatiques |
| **Pas de fenêtre de chat** sur console | *Console development guidelines* | Fait : les bulles au-dessus des têtes restent, la **roue de pings** remplace le chat (docs/07 §8) |
| Icônes de boutons de l'appareil (PlayStation sur PlayStation) | *Console development guidelines* | Fait (docs/07 §5) |
| Vibrations utilisées avec modération, sons de navigation | *Console development guidelines* | Fait ; réglage « Vibrations » pour les couper (docs/07 §9) |

### 11.2 Étape 1 : remplir le questionnaire de maturité

Faites le §8 **avant** tout essai sur PS5. Rappel officiel : sans informations de maturité, la jouabilité du jeu est restreinte pour tous les joueurs.

### 11.3 Étape 2 : tester la manette dans Studio (avant la vraie PS5)

La documentation officielle conseille de tester souvent **avec une manette branchée** ou avec le **Controller Emulator** de Studio. Roblox accepte les manettes USB, dont les manettes PlayStation.

- **Controller Emulator** (confirmé par la documentation officielle) : il permet de tester la manette dans Studio **sans manette branchée** ; il affiche une image de la manette simulée et allume ses boutons quand ils sont utilisés. Où le trouver dans Studio : à vérifier (probablement dans l'onglet **Test**).
- **Ou** branchez une manette DualSense en USB à l'ordinateur, puis **Play**.

À tester (environ 15 minutes) :

1. Marcher (stick gauche), **Dash** (R2), sauter (✕).
2. △ : la sélection va sur le menu de gauche ; croix pour choisir ; ✕ pour ouvrir.
3. Dans **chaque** menu : croix pour se déplacer, ✕ pour valider, ○ pour revenir, L1 / R1 pour les onglets, L2 / R2 pour passer au menu suivant, stick droit pour faire défiler. Rien ne doit être inaccessible.
4. **Supernova** : maintenir ✕ 1 seconde.
5. Roue de pings : croix ↑, choisir avec le stick, ✕ pour envoyer, ○ pour fermer.
6. Boutique : ✕ sur Acheter → fenêtre d'achat d'essai de Studio → la sélection revient sur le bouton Acheter.

Limite : l'agrandissement de l'interface et la zone sûre du téléviseur ne s'activent que sur une vraie console ou sur un écran que Roblox déclare « grand » (docs/07 §2-§3). Que Studio sache simuler ce cas : à vérifier. Le rendu TV se juge donc sur la PS5.

### 11.4 Étape 3 : autoriser la console dans les appareils du jeu

Ajoutez **Console** aux appareils sur lesquels l'expérience peut être jouée. `docs/07-console-ps5.md` §12 demande de le faire **seulement après** les tests automatiques console (déjà verts) et l'essai de l'étape 11.3.

- Emplacement exact du réglage (liste des appareils jouables, dans *Game Settings › Basic Info* de Studio ou dans le Creator Hub) : **à vérifier**, les documents officiels téléchargés ne le décrivent pas.
- Une éventuelle validation supplémentaire de Roblox avant l'arrivée sur console : **à vérifier**.

### 11.5 Étape 4 : trouver et lancer le jeu sur la PS5

Les documents officiels téléchargés **ne décrivent pas** l'application Roblox de la PS5. Démarche probable, **entièrement à vérifier** :

1. Sur la PS5, installez l'application **Roblox** depuis le PlayStation Store, ouvrez-la et connectez-vous avec un compte Roblox (le vôtre, propriétaire du jeu, ou un compte de test).
2. Pour retrouver le jeu facilement : sur un ordinateur, ouvrez la page de Comet Conga sur roblox.com avec ce même compte et ajoutez-la aux **favoris** ; elle devrait apparaître dans les favoris ou les jeux récents de l'application PS5.
3. Sinon, utilisez la **recherche** de l'application avec « Comet Conga » (une fois le jeu public).

Points **à vérifier** avant de compter dessus :

- un jeu **privé** peut-il être rejoint depuis la PS5 par son propriétaire ou un testeur ?
- un jeu **sans étiquette de maturité** (questionnaire non rempli) est-il visible sur PS5 ? (La documentation officielle dit seulement qu'il est restreint pour tous les joueurs : remplissez donc le questionnaire avant.)
- les réglages d'âge et de contrôle parental du compte PlayStation ou du compte Roblox peuvent-ils bloquer le jeu ?
- les **achats** (Robux, passes, produits) sur PlayStation fonctionnent-ils comme ailleurs ? Le jeu utilise les fenêtres d'achat standard de Roblox, navigables à la manette (docs/07 §6.6), mais aucun document officiel téléchargé ne parle des achats sur PlayStation.

### 11.6 Étape 5 : l'essai sur la vraie PS5 (docs/07 §12)

| À vérifier sur le téléviseur | Comment |
|---|---|
| Lisibilité à 3 m | Asseyez-vous à 3 m, sur un téléviseur de 55 pouces puis de 43 pouces si possible : chaque texte doit se lire sans effort |
| Zone sûre | Réglez la zone d'affichage de la PS5 (réglage d'écran de la console) : rien d'important ne doit être coupé sur les bords |
| Tout à la manette | Chaque menu, onglet et bouton est atteignable sans curseur |
| Achats | Un achat d'essai d'un petit article (à vérifier, voir 11.5) |
| Vibrations | Un enfant les juge « agréables », pas « trop fortes » ; sinon Réglages › Vibrations les coupe |
| Chat | Aucune fenêtre de chat ; les bulles et la roue de pings fonctionnent |
| Sons | Sons de navigation à chaque déplacement de sélection, retour (○), onglet |

### 11.7 Les commandes de la DualSense

**En jeu**

| Je veux… | Bouton |
|---|---|
| Me déplacer | Stick gauche |
| Tourner la caméra | Stick droit |
| Sauter | ✕ Croix |
| **Dash** (accélération) | **R2** (ou □ Carré) |
| Ouvrir la roue de pings (messages rapides) | Croix directionnelle ↑ |
| Agrandir / réduire la minicarte | Croix directionnelle ↓ |
| Acclamer (quand le bouton ACCLAMER apparaît) | Croix directionnelle → |
| Replier / déplier le suivi de quête | Croix directionnelle ← |
| **Ouvrir les menus** | **△ Triangle**, puis croix pour choisir, ✕ pour ouvrir |
| Revenir au jeu depuis le menu de gauche | ○ Rond ou △ |
| Menu de Roblox | Options (géré par Roblox) |

L1, R1 et L2 ne font rien en jeu (volontaire : un appui par erreur ne déclenche rien).

**Dans un menu**

| Je veux… | Bouton |
|---|---|
| Déplacer la sélection | Croix directionnelle ou stick gauche |
| Valider, acheter | ✕ Croix |
| Revenir en arrière d'un niveau | ○ Rond |
| Tout fermer et revenir au jeu | △ Triangle |
| Onglet précédent / suivant | L1 / R1 |
| Menu précédent / suivant (Améliorer, Collection, Objectifs, Boutique, Équipage, Réglages) | L2 / R2 |
| Faire défiler une liste | Stick droit |
| Confirmer la **Supernova** | **Maintenir ✕ pendant 1 seconde** |
| Taper un code (Boutique › Codes) | ✕ sur le champ : le clavier de la console s'ouvre |

**Roue de pings**

| Je veux… | Bouton |
|---|---|
| Choisir un message | Stick gauche, ou croix ← / → |
| Envoyer | ✕ |
| Fermer sans envoyer | ○ |

Exemples d'enchaînements : Améliorer = △ puis ✕ ; Boutique = △, ✕, puis R2 trois fois.

---

## 12. Check-list avant le lancement

**Technique**

- [ ] `./scripts/check.sh` se termine par « ✅ Tout est vert. » (§2.2).
- [ ] Numéros des 6 passes et 6 produits collés dans `src/shared/Config/Monetization.luau` (§5) : `lune run scripts/prepublish` affiche « ✅ Boutique prête ».
- [ ] Chaque achat testé dans Studio (achats d'essai gratuits) : l'effet arrive, une seule fois.
- [ ] Administrateurs ajoutés dans `src/server/Data/Admins.luau` (§6.1).
- [ ] `LaunchWeek` recalé sur la date réelle dans `src/shared/Config/Events.luau` (§6.3).
- [ ] Code de lancement `COMETCONGA` vérifié dans `src/server/Data/Codes.luau` (§6.2).
- [ ] Chaque son écouté dans Studio, en commençant par les neuf « à confirmer à l'écoute » (`CometWarn` et `Ping` d'abord) ; un son qui déplaît vidé ou remplacé par l'équipe technique, avec le test des sons mis à jour (§6.4).
- [ ] Plan de test dans Studio déroulé ([`06-rapport-qualite.md`](06-rapport-qualite.md) §5) : seul, à plusieurs, téléphone, manette, latence, 30 minutes sans erreur.
- [ ] 12 joueurs pendant 30 min sur un **vrai téléphone Android modeste** : au moins 30 images par seconde, aucune erreur (GDD §15.2, porte 3).
- [ ] Sauvegardes : quitter et revenir garde la progression ; achat suivi d'une déconnexion : rien n'est perdu ni crédité deux fois (GDD §15.2, porte 4).

**Creator Hub**

- [ ] Nom « Comet Conga » et « Nebbies » vérifiés (recherche sur Roblox et recherche de marque ; noms de repli : *Conga Comets*, *Nebby Parade*, GDD §16).
- [ ] Taille du serveur : 12 (§7.1).
- [ ] Appareils : téléphone, tablette, ordinateur ; console seulement après le §11 (§7.2).
- [ ] Genre Simulation (§7.3) ; serveurs privés gratuits (§7.5).
- [ ] Questionnaire de maturité soumis : Minimal ou Mild (§8).
- [ ] Icône et 3 à 5 miniatures téléversées (§9).
- [ ] Traduction automatique activée, titre et description en français (§10).
- [ ] Starfall Saturday déclaré en *Experience Event* (§6.3).

**Joueurs**

- [ ] Test privé avec 10 à 20 joueurs, dont des enfants de moins de 13 ans accompagnés : l'accueil se comprend sans aide, peu de joueurs quittent après s'être fait couper (GDD §15.2, porte 5).
- [ ] Essai sur PS5 (§11.6), si la console est activée au lancement.
- [ ] Questions de design ouvertes tranchées ([`06-rapport-qualite.md`](06-rapport-qualite.md) §7).

---

## 13. Le jour du lancement

Le GDD (§15.3) propose une publication le **samedi à 17:00 UTC** (juste après le show Starfall de 16:00).

1. Dernière publication depuis Studio (§15), puis **Play** en ligne avec votre compte : tout fonctionne.
2. Creator Hub : passez l'expérience en **Public**.
3. Annoncez le code `COMETCONGA`.
4. Restez joignable les premières heures : surveillez les signalements et les erreurs (§14).

L'étude de marché ([`01-analyse-marche.md`](01-analyse-marche.md) §5.3) rappelle que Roblox conseille d'atteindre les repères de rétention **avant** d'acheter de la publicité. Ensuite, des campagnes sponsorisées à petit budget permettent de mesurer l'attrait de l'icône avant d'augmenter.

---

## 14. Check-list après le lancement (analytics)

### 14.1 Ce que le jeu envoie déjà à Roblox

Tout passe par `src/server/Util/Analytics.luau`. Vous lisez les résultats dans le Creator Hub, partie **Analytics** de l'expérience (noms des tableaux : à vérifier).

**Entonnoir d'accueil** (une étape par moment clé de la première session, GDD §14.1) :

| Étape | Nom | Le joueur vient de… |
|---|---|---|
| 1 | `Loaded` | arriver sur son Nid |
| 2 | `FirstCatch` | attraper son premier Nebby |
| 3 | `FirstParade` | faire sa première parade |
| 4 | `FirstUpgrade` | acheter sa première amélioration |
| 5 | `Parade4` | finir la quête « Parade de 4 » |
| 6 | `Parade6` | finir la quête « Parade de 6 » |
| 7 | `AtlasUnlocked` | encaisser son premier Rare (Atlas débloqué) |
| 8 | `StrideBought` | acheter Foulée |
| 9 | `FirstEvent` | vivre son premier événement |
| 10 | `FirstSupernova` | faire sa première Supernova |

**Économie** : chaque gain et dépense de Glow et de Stardust (parades, revenu passif, quêtes, codes, achats, améliorations, Supernova, Starforge).

**Événements personnalisés** : `SessionLength` (minutes jouées), `PostSnipQuit` (départ moins de 60 s après une coupe), `SnipDealt` / `SnipReceived`, `SnipByInput` (1 tactile, 2 clavier, 3 manette), `ParadeLength`, `CometHeld` / `CometBanked`, `WispPopped` / `WispSnip`, `ZenToggled`, `RookieShieldEnded`, `SupernovaReached`, `MoveViolation` (anti-triche), `CrewFormed`, `Pass_<nom>` et un événement par produit acheté (`Product_<nom>`), `ProductEffectFailed_<nom>` (achat payé dont l'effet a échoué : à surveiller de près).

### 14.2 Les chiffres à suivre (objectifs du GDD §1.5)

| Indicateur | Seuil de lancement | Objectif | Alerte |
|---|---|---|---|
| Rétention J1 (revient le lendemain) | ≥ 15 % | 18-22 % | < 12 % |
| Rétention J7 | ≥ 5 % | 6-9 % | < 3 % |
| Rétention J30 | ≥ 2 % | 3-4,7 % | < 1 % |
| Durée moyenne de session | ≥ 12 min | ≥ 15 min | < 10 min |
| Abandon avant la 1re parade (étapes 1 → 3) | ≤ 10 % | ≤ 6 % | > 15 % |
| Départs juste après une coupe (`PostSnipQuit` / coupes subies) | ≤ 5 % | ≤ 3 % | > 8 % |
| Conversion en payeurs | 1,5 % | 2-3 % | — |
| Sessions jouées avec un ami | ≥ 15 % | ≥ 25 % | < 10 % |

### 14.3 Quoi faire si un chiffre est mauvais (GDD §14.4)

Toutes ces corrections sont des **réglages de chiffres** dans `src/shared/Config/`, sans réécrire le jeu ; demandez-les à l'équipe technique :

| Signal | Réglage prévu |
|---|---|
| Trop de départs après une coupe (> 8 %) | Immunité après coupe plus longue (8 → 12 s), coupe max plus petite (35 → 25 %), Mode Zen mis en avant |
| Les joueurs sur téléphone coupent beaucoup moins que les autres (> 25 % d'écart, `SnipByInput`) | Aide au tactile renforcée (voir aussi la question ouverte n°1 du rapport qualité) |
| Beaucoup d'abandons entre la 1re capture et la 1re parade | Nebbies de départ plus proches, guidage renforcé |
| Première Supernova trop rapide ou trop lente (hors 20-35 min) | Coût de la Supernova 1 |
| Joueurs honnêtes signalés par l'anti-triche (`MoveViolation`, > 1 % des sessions) | Marge de l'anti-triche 1,5 → 1,8 |

### 14.4 Routine

- [ ] **Chaque jour, la première semaine** : erreurs du jeu (console développeur en ligne, ou rapports d'erreurs du Creator Hub, à vérifier), `ProductEffectFailed_*` (doit rester à 0), lignes `[DataService] PERTE` dans les erreurs (sauvegarde perdue après une longue panne de Roblox : à transmettre à l'équipe technique), signalements de joueurs.
- [ ] **Chaque semaine** : rétention J1/J7, durée de session, entonnoir, conversion ; un nouveau code (§6.2) ; Starfall Saturday automatique.
- [ ] **Toutes les 2 semaines** : un ajout de contenu par la configuration, publié le samedi à 17:00 UTC (GDD §7.7).
- [ ] **À chaque mise à jour** : refaire le questionnaire de maturité si le contenu change (§8).
- [ ] **Si Roblox vous demande d'effacer les données d'un joueur** (droit à l'effacement) : transmettre la demande à l'équipe technique, dans le délai indiqué par Roblox ; la procédure est dans [`04-architecture.md`](04-architecture.md) §8.

---

## 15. Publier une mise à jour plus tard

1. Modifier les fichiers (ou demander la modification à l'équipe technique).
2. `./scripts/check.sh` → « ✅ Tout est vert. »
3. `rojo build -o build/Game.rbxl`.
4. Ouvrir `build/Game.rbxl` dans Studio, **Play** pour un essai rapide.
5. *File › Publish to Roblox* → choisir **l'expérience existante** Comet Conga et sa place de départ (et non « nouvelle expérience »). Les réglages du Creator Hub (prix, questionnaire, icône, accès) sont gardés : ils sont rangés sur Roblox, pas dans le fichier.
6. Les serveurs déjà ouverts gardent l'ancienne version jusqu'à leur fermeture. Le Creator Hub permet de redémarrer les serveurs pour passer tout le monde à la nouvelle version (à vérifier). La progression des joueurs est sauvegardée avant chaque fermeture de serveur.

---

## 16. Récapitulatif des fichiers à modifier

| Fichier | Quoi | Section |
|---|---|---|
| `src/shared/Config/Monetization.luau` | Numéros (`id`) des 6 passes et 6 produits ; prix si changés | §5 |
| `src/server/Data/Admins.luau` | UserIds des administrateurs LiveOps | §6.1 |
| `src/server/Data/Codes.luau` | Codes promo et leurs dates de fin | §6.2 |
| `src/shared/Config/Events.luau` | `LaunchWeek` (semaine du premier Starfall Saturday) | §6.3 |
| `src/shared/Config/Sounds.luau` et `tests/specs/Fix_r5_audio.spec.luau` | Après écoute, les sons à vider ou remplacer (d'abord les neuf « à confirmer à l'écoute ») : par l'équipe technique, qui met le test à jour | §6.4 |

Rien d'autre n'est nécessaire pour publier. Tout le reste (île, interface, règles, textes FR/EN, manette) est déjà dans le code et testé ([`06-rapport-qualite.md`](06-rapport-qualite.md)).
