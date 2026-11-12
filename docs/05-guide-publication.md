# Raise a Squishy — Guide de publication et tests manuels M1 à M23

*Paquet meta (docs/04 §2, §17.1, remarque A28). Ce guide dit, pas à pas, comment vérifier le jeu avant
la publication : les portes automatiques, puis les **18 tests manuels** du GDD §18 et les **5 tests de la
v2.0** (M19 à M23 : écran Améliorations, Jelly Ascend, mode photo, jumelles, photos du panneau TextProbe),
avec une section **PS5 / PS4** et la **liste du premier essai de la v2.0 sur PS5** (§7). La partie
« vrai moteur Roblox » (Open Cloud) est détaillée dans `tools/opencloud/README.md`.*

*Depuis le lot I (12 novembre 2026), le jeu livré EST la v2.0 : les 23 interrupteurs v2.0 de
`Config/Features` sont ouverts, `SchemaV2` aussi (docs/04 §27.3).*

---

## 1. Avant tout : les portes automatiques (bloquantes)

| Porte | Commande | Vert si |
|---|---|---|
| Formatage, lint, specs, build, place | `./scripts/check.sh` | « Tout est vert. » : StyLua, Selene (0 erreur, 0 avertissement), toutes les specs Lune (dont `EconomyPacing`, `ZeroLog` actif sur chaque spec du jeu), build Rojo, `verify-place` |
| Économie v2.0 (nuit) | `./scripts/economy-nightly.sh` (≈ 50 à 64 min sur 4 cœurs, les 4 cœurs pris : rien d'autre en même temps ; aucun déclencheur automatique) | 20 cas verts (docs/04 §27.9 : clés de queue à leur vraie limite sur 400 joueurs, 140 jours, profils forcés) ; **à lancer à chaque lot qui touche l'économie** et avant chaque publication |
| Captures de nuit (lot I) | `./scripts/screens-nightly.sh [dossier]` (≈ 6 min ; un seul processus Lune ; jamais en même temps que `check.sh` ni la nuit d'économie) | code 0 et « ✅ matrice de nuit » : le jeu ouvert (groupe `launch` de l'outil d'écrans : HUD, menu, chaque panneau du rail et chaque onglet) à tv1080, tv720, tv2160 × FR, EN × texte Medium et × 1,5 × graphismes normaux et réduits, images dans un dossier temporaire hors de git, synthèse `report.json` (images, défauts relevés) ; code 1 au moindre problème de l'outil. Regarder les images ; les gardes bloquantes restent `TextFit_all`, `Screens_display` et `Upgrades_Reference` (24 états de référence, dans `check.sh`) |
| Robot de longue durée (nuit) | `SOAK_HOURS=6 ./scripts/soak.sh` (`Soak` et `Soak_queue`) puis `SOAK_HOURS=6 lune run tests/run -- Review_A4` (Soak de tous les interrupteurs, 1,2 h) | `Soak.spec` : 16 robots, configuration de lancement, invariants du §17.2 à chaque tick, Ascensions (Record R jamais en baisse, aucun squishy perdu, Confettis jamais négatifs), ≤ 10 ms par tick en moyenne, zéro erreur ; Plopettes ; coupure d'urgence (SchemaV2 seul ouvert : aucune intention v2.0 répondue) |
| Vrai moteur (couche i) | `lune run tools/opencloud/run-server-tests` | code 0 ; code 2 = pas de clé (alors les tests manuels ci-dessous la remplacent, et le manque est écrit dans le rapport qualité) |
| Prépublication | `lune run scripts/prepublish` | chaque article visible de la Boutique a son identifiant ; refus si `Balance.GddValues ~= "1.3"` (note INT-PREPUBLISH) ou si `Balance.GddValuesV2 ~= "2.0"` (lot I : tables v2.0 du GDD v2.0) |
| Place construite | `rojo build -o build/Game.rbxl` puis `lune run scripts/verify-place build/Game.rbxl` (dans `check.sh`) | structure valide ; éclairage **v2.0** (`LightingStyle = Soft`, `PrioritizeLightingQuality = false`, pas de `Technology`) ; `--lighting v1.3` vérifie l'ancienne place |

Règle zéro trace pendant **tous** les tests manuels : la fenêtre *Output* de Studio, ou le panneau
Diagnostics en ligne, reste à **zéro erreur et zéro avertissement**. Une erreur vue devient d'abord une
spec qui la reproduit (`tests/specs/Fix_*.spec.luau`), puis la correction.

## 2. Préparer une session de test

1. **Administrateurs** : ajouter son UserId dans `src/server/Data/Admins.luau`
   (`[123456789] = true`), jamais côté client. Seuls ces comptes reçoivent le « bonjour » du panneau
   Diagnostics (l'entrée apparaît dans Réglages) et peuvent envoyer les commandes de l'onglet **Outils**.
2. **Commandes d'administrateur** (onglet Outils du panneau Diagnostics, intention `AdminCommand`) :
   - `forceRush`, `forceMega` : lancer un BOOP RUSH ou un MEGA SQUISH tout de suite ;
   - `clock` (`arg` = secondes) : décaler l'horloge du serveur — **en Studio seulement** (ignorée ailleurs) ;
   - `party` : fête d'administrateur ; `feature` (`arg` = `clé=valeur`, ex. `MegaSquish=false`) ;
   - `testError` (`arg` = `server` ou `client`) : erreur volontaire (M17) ;
   - `photo` : cache le HUD des administrateurs pour les vignettes.
3. **Studio** : *Test* → *Local Server* (1 à 4 joueurs) ; *Emulation* pour les résolutions
   1280 × 720, 1920 × 1080 et 3840 × 2160 ; *Network* → latence simulée (M10, M18).
4. **Profil neuf** : un compte de test jamais venu (ou effacer sa clé `player_<UserId>` du magasin
   `PlayerData_v1` d'une expérience de test). Ne jamais tester l'accueil avec un compte d'équipe.
5. **Panneau Diagnostics** (Réglages → Diagnostics, administrateurs) :
   - **Ce serveur** : version de la place, heure UTC, durée de vie, joueurs, temps moyen et maximal du
     tick, mémoire, états fermés par leur délai, puis les erreurs et avertissements triés par nombre ;
     ✕ sur une ligne ouvre ses 3 exemples (texte, pile, contexte) ;
   - **Mon client** : images par seconde, mémoire, ping, instances, connexions, qualité, erreurs de ce
     client ;
   - **Aujourd'hui** : totaux de tous les serveurs depuis 00:00 UTC (écrits toutes les 5 min).
   Photographier le panneau (PS5 : bouton Create ; PC : capture d'écran) et l'envoyer avec le compte
   rendu du test.

---

## 3. Les 23 tests manuels

Chaque test : **préparation**, **gestes**, **attendu**, **Diagnostics** (ce qu'on y lit). Un test est
réussi si tout l'attendu est vu **et** si Diagnostics ne montre aucune nouvelle ligne. M19 à M23 sont les
tests de la v2.0 (lot I) ; M7 et M9 passent aussi par les écrans de la v2.0 (écran Améliorations, aperçu
de l'Ascension, Mon style, piste de la semaine, Carnet, Records, mode photo, jumelles).

### M1 — Première session seul, 5 min, à la manette seulement

- **Préparation** : profil neuf ; manette seule (aucune touche du clavier) ; Studio ou serveur privé.
  Trois passages : (a) normal ; (b) Rush forcé à 0:30 (`forceRush`) ; (c) MEGA forcé à 1:30 (`forceMega`).
- **Gestes** : ne rien lire d'autre que le jeu ; suivre seulement les consignes (glyphe + mot).
- **Attendu** : arrivée dans son propre ranch ; le petit Plop posé devant soi dans les premières
  secondes ; première pression vers 0:10 (« +10 ») ; Tapis à Goûter vers 0:20-0:25 ; jumeau de Plop à
  0:40 ; fusion vers 1:00 ; Pot vers 1:30 ; capture de Mochi Mew à 2:00 ; premier tirage à 2:45 ;
  démonstration de Big Plop à 3:00 ; monture vers 4:30 ; carte des 3 objectifs à 5:00, puis la puce
  Menu. Jamais deux consignes à la fois ; chaque consigne montre le bon glyphe ; une consigne ignorée
  90 s se range et l'accueil continue ; en (b) et (c), Rush et MEGA restent discrets (aucune bannière,
  ciel à 30 %, musique à −12 dB) jusqu'à l'étape 9 ; Presser (□) et Prendre (○) jamais confondus.
- **Diagnostics** : *Ce serveur* sans ligne ; « États fermés par leur délai » = 0 (une consigne rangée
  après 90 s n'est **pas** une faute et n'y apparaît pas).

### M2 — Rendu sur une vraie télé

- **Préparation** : télé à 3 m ; Studio en *Team Test* ou serveur privé ; `clock` pour avancer jusqu'à
  une Jelly Moon (Studio) ; Réglages → Graphismes légers, puis normal.
- **Gestes** : tour de la ville et des ranchs ; attendre ou forcer un Rush et un MEGA ; Jelly Moon.
- **Attendu** : pastel lisible à 3 m ; raretés reconnaissables par la couleur **et** la forme ; rien
  qui clignote au-dessus de 3 Hz ; Graphismes légers moins chargé mais complet.
- **Diagnostics** : *Mon client* : qualité « normale » sur PC, images par seconde ≥ 60 ; aucune ligne.

### M3 — Physique et déplacements

- **Préparation** : 2 joueurs (un propriétaire, un intrus) ; monture débloquée à chaque selle
  (profil de test avec `biggestEver` suffisant).
- **Gestes** : traverser son portail, puis celui d'un autre ; sauter contre le mur de clôture (30 studs),
  en monture aussi ; bords du plateau ; courir et sauter 1 min à chaque selle puis presser et attraper
  depuis la monture ; bondir (R2) contre une maison ; tomber du plateau.
- **Attendu** : l'intrus rebondit, personne n'entre ni n'enjambe la clôture ; aucun « connexion
  instable » pour un cavalier honnête ; presser et attraper marchent depuis la monture ; personne ne
  reste coincé ; retour sur le plateau après une chute ; réapparition toujours dans son ranch.
- **Diagnostics** : aucune ligne `MoveViolation` côté analytique pour le cavalier honnête ; *Ce serveur*
  vide.

### M4 — Vraies sauvegardes

- **Préparation** : expérience de test avec DataStores activés.
- **Gestes** : jouer 5 min (acheter une dalle, fusionner, nourrir Plop) ; quitter ; revenir ; changer
  aussitôt de serveur ; arrêter les serveurs (Creator Hub → *Shut down all servers*) ; revenir.
- **Attendu** : rien de perdu, jamais de retour en arrière (pièces, dalles, Squishydex, jours de Plop,
  étape de l'accueil, objectifs du jour) ; l'accueil reprend à l'étape suivante sans rejouer les
  naissances scriptées.
- **Diagnostics** : aucune ligne `[DataService]` ; *Aujourd'hui* sans `ProfileRepaired:*` pour ce compte.

### M5 — Achats

- **Préparation** : passes et produits créés, identifiants collés (`scripts/prepublish` vert).
- **Gestes** : chaque pass et produit en essai gratuit de Studio ; puis un vrai petit achat en privé,
  **dont un sur PS5** ; une Squish Party avec 2 joueurs ; un Grand Splorch après l'achat d'un pass.
- **Attendu** : effet reçu une seule fois ; pass gardé après un Grand Splorch ; Squish Party pour tout
  le serveur ; nom de l'acheteur caché par défaut ; après la fenêtre d'achat PlayStation, la sélection
  revient sur le bouton Acheter.
- **Diagnostics** : aucune ligne `[Monetization]` ; un reçu rejoué n'apparaît jamais comme un double
  crédit.

### M6 — 16 vrais joueurs pendant 30 min

- **Préparation** : 16 comptes, dont **une PS4 ou une Xbox One** et une PS5 ; un administrateur.
- **Gestes** : jouer normalement 30 min, dont au moins un Rush, un MEGA et un Grand Splorch.
- **Attendu** : ≥ 30 images/s en permanence sur la PS4 / Xbox One (la qualité adaptative peut
  descendre), 60 sur la PS5 ; mémoire < 900 Mo.
- **Diagnostics** : *Ce serveur* : temps moyen du tick < 3 ms visé, maximum sans pic durable ; mémoire
  du serveur stable ; aucune ligne. *Mon client* sur la PS4 : qualité peut-être « réduite »
  (analytique `QualityReduced`), jamais d'erreur.

### M7 — Textes en français et en anglais, 3 résolutions

- **Préparation** : Studio, émulateur 1280 × 720, 1920 × 1080, 3840 × 2160 ; Réglages → Langue EN puis
  FR ; puis une vraie télé 4K.
- **Gestes** : ouvrir chaque écran (menu, 9 panneaux, cartes, écran de retour, aperçu du Grand
  Splorch).
- **Attendu** : rien de coupé ni sous 28 px TV ; aucun chevauchement ; nombres au format de la langue
  (« 12,3 K » en français).
- **Diagnostics** : *Mon client* vide (un texte manquant laisserait une clé et un avertissement).

### M8 — Particules

- **Gestes** : Grand Splorch, MEGA réussi, naissance Secret (profil de test), flocons d'hiver.
- **Attendu** : beaux, lisibles, budget tenu (aucune chute d'images par seconde visible).
- **Diagnostics** : *Mon client* : images par seconde ; aucune ligne.

### M9 — Manette seule 30 min sur une vraie PS5

- **Préparation** : PS5, manette DualSense, aucun clavier branché.
- **Gestes** : parcourir **chaque** écran avec la croix, ✕ et ○ (croix ↓ ou △ pour le menu) ; marteler □
  devant des squishies prêts ; enfoncer L3 et R3 par erreur ; laisser une carte s'ouvrir pendant une
  poursuite.
- **Attendu** : chaque écran atteint ; ○ revient toujours ; la sélection n'est jamais perdue ni bloquée ;
  aucune carte ne vole la manette ; □ presse toujours un squishy prêt ; L3 et R3 ne font rien.
- **Diagnostics** : *Mon client* : aucune ligne `FocusRescued:*` (un sauvetage du focus = un trou de
  navigation à corriger) ; analytique `FocusRescued` à 0.

### M10 — Poursuite avec 250 ms de latence

- **Préparation** : Studio, *Network* → 250 ms ; Rush forcé ; un squishy en fuite à 16 studs/s.
- **Gestes** : 40 captures : de près (≤ 5 studs), de loin (> 7 studs), par bond (R2) et □ juste après un
  bond.
- **Attendu** : ≥ 95 % des captures accordées quand le joueur la voyait à 5 studs ou moins, aucune
  au-delà de 7 ; un bond qui atterrit sur la créature l'attrape ; □ juste après un bond jamais refusé.
- **Diagnostics** : aucune ligne ; *Ce serveur* : aucun état `leap` fermé par son délai.

### M11 — Vraie PS5 à 3 m, puis une Xbox

- **Préparation** : télés de 43 et 55 pouces, mode Jeu coupé puis activé ; puis une Xbox.
- **Gestes** : M1 rapide, une partie de 10 min, un Rush.
- **Attendu** : tout lisible, rien de coupé, zone sûre respectée ; vibrations modérées et au bon moment
  (PERFECT, capture, retour d'un squishy, jamais quand il s'enfuit) ; invites □ / ○ claires ; PERFECT
  réussi à peu près aussi souvent qu'au PC ; glyphes PlayStation sur PS5 et Xbox sur Xbox.
- **Diagnostics** : *Mon client* : appareil « console » (`SetInputType` : manette, 10 pieds) ; aucune
  ligne.

### M12 — Écouter chaque son

- **Gestes** : Réglages → sons ; jouer chaque moment (d'abord les sons remplis en dernier), dont les sons
  d'interface (navigation, ✕, ○, `Bump`).
- **Attendu** : agréables, pas trop forts, `Sneeze` drôle et doux ; un son qui déplaît est vidé (le jeu
  reste jouable en silence).
- **Diagnostics** : aucune ligne (un identifiant de son invalide produit un avertissement du moteur).

### M13 — Session de 60 min à plusieurs

- **Gestes** : 3 joueurs ou plus pendant 60 min.
- **Attendu** : pas de ralentissement ; mémoire stable ; carte « Plop a sommeil » à 60 min (et 120 min
  si on continue).
- **Diagnostics** : *Ce serveur* : mémoire stable, tick stable, aucune ligne ; *Aujourd'hui* sans
  nouvelle clé.

### M14 — Un enfant de 8-10 ans accompagné, à la manette devant la télé

- **Gestes** : un Rush en mode Rush, puis en mode Cozy, puis un Grand Splorch.
- **Attendu** : il comprend le choix, rit pendant la poursuite, ne se sent pas volé, retrouve seul le
  bouton « Mode Cozy » après un boop, lit les textes depuis le canapé, ne se perd pas dans les menus, voit
  son squishy revenir après le Grand Splorch.
- **Diagnostics** : aucune ligne ; noter les hésitations dans le compte rendu (aucun chiffre ne les
  remplace).

### M15 — Rush à 6 joueurs

- **Préparation** : 6 joueurs : un boopeur, un propriétaire loin de sa clôture, 4 poursuivants.
- **Attendu** : la poursuite dure plus de 6 s ; le boopeur ne l'attrape pas tout de suite ; le
  propriétaire voit sa flèche ; à l'image, une bulle-bébé, jamais un animal emporté.
- **Diagnostics** : aucune ligne ; aucun état `escape` ou `boopHold` fermé par son délai.

### M16 — Clavier et souris sur PC

- **Gestes** : M1, puis le parcours de M9 à la souris et au clavier (M ou ; pour le menu).
- **Attendu** : tout se fait au clavier-souris ; Échap reste à Roblox ; Retour arrière revient en
  arrière ; les glyphes passent du clavier à la manette dès qu'on la prend, et inversement.
- **Diagnostics** : *Mon client* : appareil « pcKeyboard » puis « pcGamepad » après la prise de la
  manette ; aucune ligne.

### M17 — Diagnostics

- **Préparation** : un compte administrateur et un compte ordinaire sur le même serveur.
- **Gestes** : onglet Outils → `testError` `server`, puis `testError` `client` ; ouvrir *Ce serveur*,
  *Mon client*, puis *Aujourd'hui* après 5 min ; avec le compte ordinaire, chercher l'entrée.
- **Attendu** : l'erreur serveur apparaît dans *Ce serveur* ; l'erreur client dans *Mon client* puis dans
  *Ce serveur* (source « client ») ; les deux dans *Aujourd'hui* après l'écriture des 5 min ; **aucun nom
  de joueur** (noms remplacés par `<joueur>`, nombres par `#`) ; le compte ordinaire ne voit pas l'entrée
  Diagnostics et n'obtient **aucune** réponse à une demande.
- **Diagnostics** : exactement les deux lignes provoquées (ce test est le seul où une ligne est
  attendue) ; analytique `ServerError` et `ClientError` une fois chacune.

### M18 — Pannes et imprévus

- **Gestes** : couper le réseau du client 20 s ; changer de manette, la débrancher ; rejoindre pendant un
  Rush, un MEGA ou le Grand Splorch d'un autre ; mourir en portant un squishy ou pendant un boop.
- **Attendu** : rien de bloqué ni de faux ; le squishy porté revient à sa place ; les créatures finies
  disparaissent ; l'état du client se recale tout seul (`RequestWorld` toutes les 3 s) ; une arrivée
  pendant le spectacle d'un autre montre le spectacle en cours, et un héros parti avant l'éclatement
  l'arrête sans pluie de cadeaux.
- **Diagnostics** : *Ce serveur* : aucun état fermé par son délai (`carry`, `boopHold`, `spectacle`) ;
  *Mon client* : aucune ligne `WaitForChild` arrivée à son délai.

### M19 — Écran Améliorations à la manette (v2.0)

- **Préparation** : profil avec des pièces (au moins une carte « Prêt »), PS5, manette seule.
- **Gestes** : △ ouvre le menu, croix jusqu'à « Améliorations », ✕ ; puis ressortir et revenir par le
  kiosque de Big Plop (□ « Atelier » devant lui) et par la puce « Prochain achat » du HUD ; sur une
  carte prête, **maintenir ✕ 0,6 s** (l'anneau se remplit) ; relâcher trop tôt une autre fois ; L1 / R1
  sur les 4 onglets ; □ change le mode d'achat (×1, ×10, Max) ; ○.
- **Attendu** : rien n'est acheté par un simple appui ; l'achat part à la fin de l'anneau, une seule fois ;
  « En cours » puis le nouveau niveau ; relâché trop tôt : rien ; l'onglet Plopettes verrouillé montre le
  cadenas et « Record 2 » ; ○ ouvert depuis le kiosque ou la puce rend la main au jeu en un appui, ouvert
  depuis le menu il revient au menu.
- **Diagnostics** : aucune ligne ; aucun achat en double dans *Aujourd'hui* (`UpgradeBought`).

### M20 — Jelly Ascend : maintien de 3 s (v2.0)

- **Préparation** : profil de test au Record R 15 (r = Record R), ou `clock` en Studio.
- **Gestes** : aperçu du Grand Splorch → onglet de l'Ascension ; maintenir ✕ et relâcher à 1 s, puis
  maintenir 3 s ; à la carte « Prêt à monter ? », choisir « Pas encore » une fois, puis monter.
- **Attendu** : relâché avant 3 s, rien ; au bout de 3 s, la carte ; « Pas encore » ne coûte rien ; après
  la montée : ciel et faisceau de l'Observatoire, Record R gardé, Confettis gagnés, aucun squishy perdu ;
  le Petit Splorch suivant part sans file d'attente.
- **Diagnostics** : aucune ligne ; *Aujourd'hui* : `AscendDone` une fois.

### M21 — Mode photo et bouton Create (v2.0)

- **Préparation** : PS5, un ranch construit (paliers, Monuments si possible), une météo ou une fête.
- **Gestes** : Réglages → « Mode photo » → « Cheese ! » ; stick gauche (bouger), stick droit (tourner),
  L2 / R2 (zoom), □ (les 4 filtres : Sans filtre, Chaud, Rose, Rêve) ; photo avec le bouton **Create**
  de la manette ; ○ pour sortir. Recommencer pendant qu'une carte arrive.
- **Attendu** : plus aucun HUD ni texte flottant (« z » des Plopettes, étiquette du Chantier) sur la photo ;
  le nom du filtre s'affiche 2 s puis disparaît ; la carte attend la sortie du mode photo ; ○ rend
  l'écran et la caméra comme avant.
- **Diagnostics** : aucune ligne ; joindre la photo prise avec Create au compte rendu.

### M22 — Jumelles devant le ranch d'un voisin (v2.0)

- **Préparation** : 2 joueurs sur le serveur, dont un ami ; un joueur bloqué si possible.
- **Gestes** : devant le portail d'un voisin, □ « Regarder » ; ✕ donne un cœur ; △ ouvre le menu
  par-dessus, ○ le ferme ; ○ ferme les jumelles ; s'éloigner de plus de 14 studs les jumelles ouvertes ;
  se placer devant le portail du joueur bloqué.
- **Attendu** : vue zoomée sur le ranch du voisin en moins d'une demi-seconde ; un cœur au plus par jour et
  par voisin ; s'éloigner referme ; aucune invite « Regarder » devant un joueur bloqué ; ○ rend la caméra
  exactement comme avant.
- **Diagnostics** : aucune ligne.

### M23 — Photos du panneau TextProbe (v2.0)

- **Préparation** : PS5 sur la vraie télé à 3 m ; un compte administrateur.
- **Gestes** : Réglages → Diagnostics → onglet **Texte** ; photographier la télé (bouton Create, puis
  aussi au téléphone pour avoir la vraie télé) à chacun des 4 réglages « Taille du texte » de Roblox.
- **Attendu** : les 6 étiquettes témoins tiennent chacune dans sa boîte ; les chiffres (TextBounds,
  facteurs, échelle) sont lisibles sur la photo.
- **Diagnostics** : les 4 photos vont avec le compte rendu ; leurs chiffres sont reportés dans
  `tests/harness/TextMetrics.luau` par l'équipe (mesure du vrai rendu des polices FredokaOne et
  LuckiestGuy).

---

## 4. Section PS5 et PS4 (et Xbox)

| Étape | PS5 | PS4 (ou Xbox One) |
|---|---|---|
| Installer | Roblox depuis le PlayStation Store ; compte de test **privé** ; serveur privé du jeu | idem |
| Tests à faire | M1 (manette), M5 (un achat), M6 (la PS5 du test à 16), **M9** (30 min manette seule), **M11** (télé à 3 m), M14, M18, **M19 à M23** (v2.0), puis la liste du §7 | **M6** (≥ 30 images/s, qualité adaptative, 16 ranchs construits), M11 (lisibilité), M18 |
| Où regarder | panneau Diagnostics → *Mon client* (images par seconde, mémoire, qualité) ; photo du panneau avec le bouton **Create** | idem ; noter si la qualité passe en « réduite » et quand |
| Réglages de la console | mode Jeu de la télé coupé puis activé ; zone sûre de la PS5 par défaut | idem |
| Glyphes | PlayStation (□ ○ △ ✕, L1 R1 L2 R2) partout, jamais de lettres Xbox | Xbox (A B X Y) sur Xbox |
| Vibrations | modérées, au bon moment, coupables dans Réglages | idem (manette Xbox) |
| Bloquant | une sélection perdue, un texte coupé, un glyphe faux, une chute sous 30 images/s durable, une ligne dans Diagnostics | idem |

Activer la console dans le Creator Hub **seulement après** M6, M9 et M11 réussis.

## 5. Réglages de publication (propriétaire)

- Taille du serveur **16** (Creator Hub) et `Players.MaxPlayers = 16` dans le projet (à vérifier dans
  `default.project.json`) ; une place réservée aux amis.
- Types d'appareils : **Ordinateur + Console** ; Téléphone et Tablette décochés ; VR coupée.
- Questionnaire de maturité (cible Minimal ; « non » aux objets aléatoires payants) ; langues EN et FR.
- `StreamingEnabled` coupé, `VirtualCursorMode = Disabled`, `StarterGui.ClipsDescendantsSupportsRotation =
  Enabled`, éclairage unifié de la v2.0 (`Lighting.LightingStyle = Soft`, `PrioritizeLightingQuality =
  false`, plus de `Technology`) : vérifiés par `Contract_game.spec` (projet) et `scripts/verify-place.luau`
  (place construite).
- **Sauvegardes v2 (depuis le lot I, `SchemaV2` ouvert)** : chaque joueur de la v1.3 est migré en v2 à
  son premier chargement, une seule fois, sans rien perdre (`Migration_I.spec`). Publier la v2.0 avec
  **« Shut down all servers »** (ou « Migrate to latest update ») pour qu'aucun ancien serveur v1 ne
  reste allumé : un ancien serveur refuse un profil v2 (le joueur est renvoyé poliment, rien n'est écrit)
  et le serveur à jour le relit ensuite. **Ne jamais republier une place plus ancienne** une fois une
  sauvegarde v2 écrite (elle refuserait chaque joueur migré). `SchemaV2` ne se coupe jamais : la coupure
  d'urgence de LiveOps coupe les autres interrupteurs (docs/04 §27.2).
- Administrateurs LiveOps et Diagnostics dans `src/server/Data/Admins.luau`.
- Couche i : clé Open Cloud limitée à la place de test privée, par variable d'environnement, **jamais
  dans le dépôt** (`tools/opencloud/README.md`).
- Experience Event de la Jelly Moon déclaré pour le samedi ; icône et vignettes capturées en jeu
  (`photo`).
- Date de repli : si une porte n'est pas verte le 10 décembre, sortie le samedi 9 janvier 2027.

## 6. Compte rendu d'un test manuel (modèle)

```
Test : M__        Date / heure UTC :        Version de la place :
Appareil : PS5 / PS4 / Xbox / PC          Télé / écran, distance :
Réussi : oui / non
Écarts vus (avec l'heure) :
Photo du panneau Diagnostics (Ce serveur, Mon client) : jointe / aucune ligne
Spec ajoutée pour chaque écart : tests/specs/Fix_<…>.spec.luau
```

## 7. Premier essai de la v2.0 sur PS5 : la liste du propriétaire (lot I)

Ici, personne n'a pu voir la 3D, entendre les sons, sentir les vibrations ni voir le vrai rendu des
textes : les tests automatiques ne regardent que des chiffres et des captures dessinées. Avec la manette,
regardez chaque ligne et notez « bien » ou ce qui ne va pas (une photo avec le bouton Create aide).

**Le ranch et le monde (3D)**
1. Le ranch change quand on achète : les 6 paliers du Tapis (petit arc, puis couronne d'étoiles, puis
   arc-en-ciel), la Cuve, le Pot, la fontaine, les lanternes, le portail arc-en-ciel. Beau ? Rien qui flotte ?
2. Une fête « palier » joue quand un palier du Tapis monte (anneau et ola des squishies).
3. Les Monuments (10 dessins) et les objets de Déco perso : à leur place, jolis, rien dans les murs.
4. L'Observatoire et le kiosque de Big Plop sur la place : faciles à trouver, invite □ « Atelier » claire.
5. Le halo au-dessus du ranch et le ciel spécial après une Jelly Ascend : beaux, pas trop forts.
6. Les Plopettes : elles sortent de leur maisonnette, pressent les squishies, font la sieste (« z »).
7. Les visages des squishies et leurs petites scènes (personnalités) : drôles, jamais bizarres.
8. Les spectacles : Petit Splorch, Jelly Ascend (faisceau de l'Observatoire), nouveau tour appris.
9. La météo (pluie, neige, vent…) : jolie, jamais gênante pour jouer.
10. La place en fête : décorations, ballons, ça monte avec les joueurs.
11. Les bulles des signaux de la croix (main, cœur, étoile) au-dessus des joueurs, à 10 m et à 50 m.

**La caméra**
12. La caméra des spectacles (Grand Splorch, Ascension) : on voit bien, puis elle revient toute seule.
13. Le mode photo (Réglages → Mode photo → Cheese !) : sticks, L2 / R2, □ pour les 4 filtres, ○ pour
    sortir ; sur la photo, aucun texte qui flotte ; la caméra revient comme avant.
14. Les jumelles devant le portail d'un voisin (□) : le zoom est doux, pas de mal au cœur ; ○ revient.

**Le son et les vibrations**
15. Les sons de la v2.0 : beaucoup sont encore **muets exprès** (identifiants vides : Plopettes,
    Chantier, tours, Ascension, Confettis, météo, fête, Cheese) ; ils seront remplis au lot de QA final.
    Notez seulement si un son joue faux ou trop fort.
16. Les vibrations : palier du Tapis, Chantier fini, Jelly Ascend : modérées, au bon moment, coupables
    dans Réglages.

**Les textes**
17. Les textes sur la vraie télé (polices FredokaOne et LuckiestGuy) : rien de coupé, lisible à 3 m, en
    français et en anglais (Réglages → Langue).
18. Le panneau TextProbe (Réglages → Diagnostics → Texte) : une photo à chacun des 4 réglages « Taille
    du texte » de Roblox (M23).

**Ce que la v2.0 a changé à l'image de la v1.3** (prévu, à confirmer à l'œil)
19. Les étoiles au-dessus des squishies sont maintenant dessinées (plus de caractère « ★ »).
20. La selle et la traînée de la monture se voient enfin (le pack de selles payant).
21. Le squishy dessiné suit sa tenue, sa mutation et ses étoiles.
22. Après le travelling du Grand Splorch, la caméra revient exactement comme avant (focale comprise).
23. L'éclairage de la place est l'éclairage « Soft » (unifié) : couleurs douces, ombres propres, rien de
    trop sombre la nuit.

**La vitesse**
24. Avec 16 ranchs construits, sur une **PS4** et une **Xbox One** : au moins 30 images par seconde
    (Diagnostics → Mon client), même pendant une fête ou un Rush.

**La manette**
25. Une ligne qui sort de l'écran en bas d'une liste reste atteignable à la croix (Records, piste, Carnet).
26. Deux boutons côte à côte (dont un un peu plus gros quand il est choisi) : ↑ et ↓ passent bien de l'un
    à l'autre, la sélection ne se perd jamais.

**Vos trois questions**
27. Petit Splorch : la copie qui saute est le squishy montré à tous, pas celui que vous avez choisi.
    Est-ce bien ainsi ? (M42)
28. MEGA : le GDD dit « les squishies à 120 studs réagissent », mais les enclos sont à 194-219 studs de la
    place : seuls un squishy porté ou une monture près de la place réagissent. Garder 120 ou passer à 220 ? (M43)
29. Cascade de construction : le minuteur de 10 s court aussi écran Améliorations ouvert (un joueur qui
    reste longtemps dans l'écran voit ses achats posés sans cascade). Garder, ou compter les 10 s depuis
    la fermeture de l'écran ? (M44)
