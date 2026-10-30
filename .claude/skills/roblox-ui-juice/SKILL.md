---
name: roblox-ui-juice
description: Interfaces Roblox construites en code, mobile d'abord (ScreenGui, UIScale, zones sûres, cibles tactiles) et catalogue d'effets « juice » (tweens, popups de gains, particules, secousses caméra, compteurs animés, sons optionnels). À charger pour toute UI, HUD, menu, notification, animation, effet visuel ou retour joueur.
---

# UI mobile d'abord & « juice »

## Construction de l'UI en code

- Un `ScreenGui` par écran logique, `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `ZIndexBehavior = Sibling`.
- **Zone sûre** : respecter `GuiService:GetGuiInset()` et les encoches ; rien d'important à moins de 12 px des bords.
- Mise à l'échelle : un `UIScale` racine calculé depuis la taille de `workspace.CurrentCamera.ViewportSize` (référence 1280×720, borner entre 0.6 et 1.4).
- Cibles tactiles **≥ 44×44 px** après mise à l'échelle ; boutons principaux ≥ 64 px.
- Le bouton de saut mobile est en bas à droite : ne rien placer dans ce coin ; le joystick est en bas à gauche.
- Style : `UICorner` (8-16 px), `UIStroke` (2-3 px, couleur sombre, `ApplyStrokeMode = Border` pour les cadres et `Contextual` pour les textes), `UIGradient` léger, police `Enum.Font.FredokaOne`/`GothamBold` (via `Font.fromEnum`).
- Textes : `TextScaled = true` + `UITextSizeConstraint` (max) pour éviter les textes géants.
- Manette/PC : chaque bouton principal a un raccourci clavier (`ContextActionService`) et `Selectable = true` ; afficher les touches sur PC.
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
| Notification | Toast en haut, empilable (max 3), auto-fermeture 3 s | |

Règles :
- **Un seul tween actif par propriété** : annuler le précédent (`tween:Cancel()`) avant d'en lancer un autre sur la même instance.
- Pool de popups (réutiliser 20 TextLabels) pour ne jamais créer d'instances en rafale.
- Secousse caméra : décaler `Humanoid.CameraOffset` (bruit `math.noise`), jamais `Camera.CFrame` directement en mode Custom ; amplitude max 0.4 stud, durée max 0.3 s, désactivable dans les paramètres.
- Respecter le réglage « réduire les mouvements » (`GuiService.ReducedMotionEnabled`) : remplacer les mouvements par des fondus.
- Sons : `Shared/Config/Sounds.luau`, un ID vide = son ignoré silencieusement ; précharger avec `ContentProvider:PreloadAsync` dans un `task.spawn`.

## Animations dans le monde (sans assets)

- Objets qui flottent : `TweenService` sur `CFrame` avec `RepeatCount = -1`, `Reverses = true` (sinusoïde de 0.5-1 stud, 1.5-2.5 s).
- Rotation continue : `RunService.RenderStepped` côté client sur un **seul** gestionnaire qui fait tourner une liste de parts (pas une boucle par objet).
- Apparition : échelle via `Size` de 0 → taille finale `Back Out` 0.4 s + `ParticleEmitter:Emit(20)`.
- Lueur : `PointLight` + matériau `Neon` + `Highlight` (max ~30 Highlight simultanés, limite moteur).
- Trajets : `Beam` entre deux `Attachment` avec `TextureSpeed` pour un flux animé.
