---
name: roblox-ui-juice
description: Interfaces Roblox construites en code pour Raise a Squishy, console d'abord (PS5 avec manette DualSense sur une télé à 3 m, puis Xbox, puis PC clavier et souris ; ni téléphone, ni tablette, ni tactile) : disposition télé 1920 × 1080 px TV via Client/UI/Root, zone sûre de 5 %, texte ≥ 28 px TV, glyphes PlayStation, navigation à la croix + ✕ + ○, invites dessinées par le jeu (aucune ProximityPrompt), vibrations, sons d'interface, et catalogue d'effets « juice » (tweens, popups de gains, particules, compteurs animés). À charger pour toute UI, HUD, menu, notification, animation, effet visuel ou retour joueur.
---

# UI console d'abord & « juice »

Contrat complet : `docs/04-architecture.md` §14 (disposition télé, navigation, glyphes, vibrations, sons) et §3.4 (interactions) ; GDD `docs/02-game-design-document.md` §10.

## Construction de l'UI en code (disposition télé, la seule)

- Plateformes, dans l'ordre : **PS5** (manette DualSense, télé à 3 m), puis **Xbox**, puis **PC** (clavier et souris, en second). **Aucun code tactile**, aucun téléphone, aucune tablette : `Contract_game.spec` fouille `src/` à la recherche de tout chemin tactile.
- Un `ScreenGui` par écran logique, toujours créé par `Root.screen(nom, ordre)` / `Root.safe(nom, ordre)` : `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling`, conteneur `Safe` qui porte l'`UIScale` et la marge intérieure.
- **Référence 1920 × 1080 px TV** (`Config/Layout.Reference`), une seule règle sur tous les écrans : `UIScale = max(0,5 ; min(L / 1920, H / 1080))`, sans plafond (1 en 1080p, 2 en 4K, 0,667 en 720p). Vérifier les 3 résolutions : 1920 × 1080, 3840 × 2160 et 1280 × 720.
- **Zone sûre de 5 %** de chaque côté sur tous les écrans (x 96-1824, y 54-1026) : tout ce qui compte va dans `Safe`. Un fond décoratif qui déborde porte l'attribut `Decorative = true`.
- Tailles minimales (px TV) : **texte 28** (courant 32, boutons 40, titres 48-56, compteurs 56-72) ; glyphe 48 (64 pour l'invite □) ; bouton 80 de haut (96 pour le principal) ; 16 px entre deux éléments sélectionnables. Chaque texte : `TextScaled = true` + `UITextSizeConstraint` (minimum 28) ; s'il ne tient pas à 28 en anglais **et** en français, la spec échoue et on raccourcit le libellé.
- HUD : rectangles fixes de `Config/Layout.Hud` (4 colonnes accrochées à la zone sûre), aucun recouvrement, le milieu de l'écran reste libre. Panneaux 1440 × 860 centrés, un seul ouvert, le jeu continue.
- Style : `UICorner` 14-18 px, `UIStroke` 3 px bleu nuit, dégradés pastel, FredokaOne (texte) et LuckiestGuy (tampons). Aucune image téléversée : formes en Frames et glyphes de Roblox.
- **Navigation à la manette seule (règle des 3 touches)** : la croix (ou le stick gauche) déplace la sélection, ✕ valide, ○ recule d'un niveau (depuis le premier niveau, il rend la main au jeu). La croix, ✕ et ○ suffisent pour atteindre chaque écran et en revenir ; △, L1 / R1 (onglets) et L2 / R2 (panneaux) ne sont que des raccourcis. Curseur virtuel désactivé ; sélection commune `Root.selectionImage()` ; fenêtres en `SelectionGroup` avec `SelectionBehavior* = Stop` ; jamais de sélection vide ou hors de la fenêtre.
- **Glyphes** : uniquement via `Client/UI/Glyph` (`GetImageForKeyCode` : PlayStation sur PS5, Xbox sur Xbox, touche du clavier sur PC) ; jamais « X », « Y », « LB » ni « Menu » écrits en dur. Un libellé qui suit une touche utilise `Widgets.followGlyph` (les touches du clavier sont plus larges).
- **Invites du monde : aucune `ProximityPrompt`** (GDD §10.4). `PromptController` choisit la cible par distance (`Logic/TargetRules`), `UI/Prompt` dessine l'invite, `InputController` lie les touches par `ContextActionService` seulement quand une invite est affichée et qu'aucune fenêtre n'est ouverte. Textes du monde par `UI/WorldText` (`BillboardGui` en px TV).
- Commandes : □ action principale (presser, lancer, attraper, booper), ○ Prendre / Poser, R2 Bondir, L2 Monter, △ ou croix ↓ Menu. Clavier : E, Q, Maj, R, M (jamais Tab).
- **Pas de fenêtre de chat** sur console (`Platform.applyChatRule`). Vibrations via `Util/Haptics` seulement (catalogue `Config/Console.Haptics.Events`, modérées, désactivables). Sons d'interface (`Click`, `Back`, `Bump`…) par `AudioController`.
- Une attente d'objet côté client : `WaitForChild(nom, délai)` toujours avec un délai et un repli (`StreamingEnabled` est coupé, mais un objet peut arriver en retard).
- Toutes les chaînes viennent de `Shared/Localization` (EN et FR).

## Catalogue de juice (côté client uniquement)

| Événement | Effet | Paramètres |
|-----------|-------|-----------|
| Clic bouton | Échelle 1 → 0.9 → 1 | 0.08 s `Quad Out` puis 0.15 s `Back Out` |
| Sélection (manette) | Échelle 1.05 + cadre blanc qui respire | 0.12 s, respiration 1,2 s |
| Ouverture panneau | Position +40 px → 0, transparence 1 → 0, échelle 0.85 → 1 | 0.25 s `Back Out` |
| Fermeture panneau | Inverse | 0.15 s `Quad In` |
| Gain de monnaie | Popup « +123 » qui monte de 60 px et s'efface, couleur selon montant | 0.7 s `Quad Out` |
| Compteur | Le nombre défile de l'ancienne à la nouvelle valeur + « pop » d'échelle 1.15 | 0.4 s |
| Gros gain | Particules (étoiles) à l'écran + secousse caméra légère + flash blanc 10 % | 0.3 s |
| Montée de niveau | Bannière qui glisse du haut, rayons rotatifs derrière, confettis | 2 s |
| Objet ramassé | L'objet saute (0.2 s) puis se réduit vers le HUD | 0.35 s `Back In` |
| Refus (pas assez) | Shake horizontal du bouton ±6 px ×3 + teinte rouge | 0.25 s |
| Notification | `Toast.message(texte traduit, ton)` : file unique du HUD (`Hud/Messages`), un message à la fois après la bannière, 3 au plus en attente, 2,5 s chacun (GDD §10.2) | |

Règles :
- **Un seul tween actif par propriété** : annuler le précédent (`tween:Cancel()`) avant d'en lancer un autre sur la même instance.
- Pool de popups (réutiliser 20 TextLabels) pour ne jamais créer d'instances en rafale.
- Secousse caméra : décaler `Humanoid.CameraOffset` (bruit `math.noise`), jamais `Camera.CFrame` directement en mode Custom ; amplitude max 0.4 stud, durée max 0.3 s, désactivable dans les paramètres.
- Respecter **Mouvement réduit** (`QualityController.reduced()`, réglage du jeu et `GuiService.ReducedMotionEnabled`) : remplacer les mouvements par des fondus. Respecter **Graphismes légers** (pas de particules secondaires). Budgets de PS4 / Xbox One : instances en pool, une seule boucle par image par système, quotas de `RanchRenderer`, `ChaseRenderer` et `VFXController`.
- Sons : `Shared/Config/Sounds.luau` (sons publiés par Roblox seulement, provenance sur la ligne), joués par `AudioController.play` ; un ID vide = son ignoré silencieusement ; préchargement et garde-fous (copies par image, simultanées, durée max) déjà faits par `AudioController`. Musique : `AudioController.setMusic(clé, dB)` (fondu croisé entre `Music`, `MusicMoon`, `MusicRush`), choisie par `LightingController` seulement.
- Écran de chargement : `src/first/Loading.client.luau`, sans texte pendant le chargement, fermé quand l'attribut local `ClientReady` est posé (le HUD du jeu le pose une fois construit).

## Animations dans le monde (sans assets)

- Objets qui flottent : `TweenService` sur `CFrame` avec `RepeatCount = -1`, `Reverses = true` (sinusoïde de 0.5-1 stud, 1.5-2.5 s).
- Rotation continue : `RunService.RenderStepped` côté client sur un **seul** gestionnaire qui fait tourner une liste de parts (pas une boucle par objet).
- Apparition : échelle via `Size` de 0 → taille finale `Back Out` 0.4 s + `ParticleEmitter:Emit(20)`.
- Lueur : `PointLight` + matériau `Neon` + `Highlight` (max ~30 Highlight simultanés, limite moteur ; moins sur PS4 / Xbox One).
- Décor : `Anchored = true`, `CanCollide = CanTouch = CanQuery = false`. Une animation ne décide jamais d'une règle : le serveur minute tout (`Clock`), le client ne fait que dessiner.
- Trajets : `Beam` entre deux `Attachment` avec `TextureSpeed` pour un flux animé.
