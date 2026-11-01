---
name: roblox-ui-juice
description: Interfaces Roblox construites en code pour Raise a Squishy, mobile d'abord et jouables sur téléviseur (ScreenGui via Client/UI/Root, UIScale, zones sûres, cibles tactiles, couche console PS5 reprise de Comet Conga) et catalogue d'effets « juice » (tweens, popups de gains, particules, secousses caméra, compteurs animés, sons optionnels). À charger pour toute UI, HUD, menu, notification, animation, effet visuel ou retour joueur.
---

# UI mobile d'abord & « juice »

## Construction de l'UI en code

- Un `ScreenGui` par écran logique, toujours créé par `Root.screen(nom, ordre)` / `Root.safe(nom, ordre)` : `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling`, conteneur `Safe` qui porte l'`UIScale` et la marge intérieure.
- **Zone sûre** : tout ce qui compte va dans `Safe` (marge 12 × 8 px ; sur console ou écran Large, 5 % de l'écran de chaque côté).
- Mise à l'échelle (fournie par `Root`, règles dans `Util/Platform`) : référence 1280×720, `clamp(min(L/1280, H/720), 0,6, 1,25)` ; sur téléviseur, sans plafond (1,5 en 1080p, 3 en 4K).
- Cibles tactiles **≥ 44×44 px** après mise à l'échelle ; boutons principaux ≥ 64 px.
- Le bouton de saut mobile est en bas à droite : ne rien placer dans ce coin ; le joystick est en bas à gauche.
- Style : `UICorner` (8-16 px), `UIStroke` (2-3 px, couleur sombre, `ApplyStrokeMode = Border` pour les cadres et `Contextual` pour les textes), `UIGradient` léger, police `Enum.Font.FredokaOne`/`GothamBold` (via `Font.fromEnum`).
- Textes : `TextScaled = true` + `UITextSizeConstraint` (max, et min ≥ 18 px de référence : lisible à 3 m) pour éviter les textes géants ; prévoir 25 % de longueur en plus pour le français.
- Manette/PC : chaque bouton principal a un raccourci clavier (`ContextActionService`) et `Selectable = true` ; afficher les touches sur PC.
- Console / téléviseur (couche reprise de Comet Conga, voir son `docs/07-console-ps5.md`) : repères de touches **uniquement** via `Client/UI/Glyph` (icône `GetImageForKeyCode`, PlayStation sur PS5 ; jamais « X », « Y », « LB » en dur) ; échelle et zone sûre TV fournies par `Root` (`Util/Platform`) ; curseur de sélection commun `Root.selectionImage()` (blanc, liseré sombre, jamais la couleur d'un état) ; fenêtres modales en `SelectionGroup` avec `SelectionBehavior* = Stop` ; ○ recule, △ ouvre le rail de menus, L1/R1 onglets ; pas de fenêtre de chat sur console (`Platform.applyChatRule`) ; vibrations via `Util/Haptics` seulement (modérées, désactivables) ; textes ≥ 18 px de référence. Commandes du jeu : docs/03 §8.7 (□ action unique en `ProximityPrompt`, R2 bondir, L2 monter).
- Toutes les chaînes viennent de `Shared/Localization` (EN/FR).

## Catalogue de juice (côté client uniquement)

| Événement | Effet | Paramètres |
|-----------|-------|-----------|
| Clic bouton | Échelle 1 → 0.9 → 1 | 0.08 s `Quad Out` puis 0.15 s `Back Out` |
| Survol | Échelle 1.05 + éclaircir | 0.12 s |
| Ouverture panneau | Position +40 px → 0, transparence 1 → 0, échelle 0.85 → 1 | 0.25 s `Back Out` |
| Fermeture panneau | Inverse | 0.15 s `Quad In` |
| Gain de monnaie | Popup « +123 » qui monte de 60 px et s'efface, couleur selon montant | 0.7 s `Quad Out` |
| Compteur | Le nombre défile de l'ancienne à la nouvelle valeur + « pop » d'échelle 1.15 | 0.4 s |
| Gros gain | Particules (étoiles) à l'écran + secousse caméra légère + flash blanc 10 % | 0.3 s |
| Montée de niveau | Bannière qui glisse du haut, rayons rotatifs derrière, confettis | 2 s |
| Objet ramassé | L'objet saute (0.2 s) puis se réduit vers le HUD | 0.35 s `Back In` |
| Refus (pas assez) | Shake horizontal du bouton ±6 px ×3 + teinte rouge | 0.25 s |
| Notification | `Toast.show(texte traduit, ton)` : en haut, sous les bannières (`Toast.TopY`), empilable (max 3), auto-fermeture 3 s | |

Règles :
- **Un seul tween actif par propriété** : annuler le précédent (`tween:Cancel()`) avant d'en lancer un autre sur la même instance.
- Pool de popups (réutiliser 20 TextLabels) pour ne jamais créer d'instances en rafale.
- Secousse caméra : décaler `Humanoid.CameraOffset` (bruit `math.noise`), jamais `Camera.CFrame` directement en mode Custom ; amplitude max 0.4 stud, durée max 0.3 s, désactivable dans les paramètres.
- Respecter le réglage « réduire les mouvements » (`GuiService.ReducedMotionEnabled`) : remplacer les mouvements par des fondus.
- Sons : `Shared/Config/Sounds.luau` (sons publiés par Roblox seulement, provenance sur la ligne), joués par `AudioController.play` ; un ID vide = son ignoré silencieusement ; préchargement et garde-fous (copies par image, simultanées, durée max) déjà faits par `AudioController`.
- Écran de chargement : `src/first/Loading.client.luau`, sans texte pendant le chargement, fermé quand l'attribut local `ClientReady` est posé (le HUD du jeu le pose une fois construit).

## Animations dans le monde (sans assets)

- Objets qui flottent : `TweenService` sur `CFrame` avec `RepeatCount = -1`, `Reverses = true` (sinusoïde de 0.5-1 stud, 1.5-2.5 s).
- Rotation continue : `RunService.RenderStepped` côté client sur un **seul** gestionnaire qui fait tourner une liste de parts (pas une boucle par objet).
- Apparition : échelle via `Size` de 0 → taille finale `Back Out` 0.4 s + `ParticleEmitter:Emit(20)`.
- Lueur : `PointLight` + matériau `Neon` + `Highlight` (max ~30 Highlight simultanés, limite moteur).
- Trajets : `Beam` entre deux `Attachment` avec `TextureSpeed` pour un flux animé.
