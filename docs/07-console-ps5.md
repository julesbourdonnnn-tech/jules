# Comet Conga — Console PlayStation 5 (DualSense, téléviseur à 3 m)

> **Document 07.** Version 1.0 du 31 octobre 2026. Statut : **design console figé** et socle implémenté ; le reste est réparti en 3 groupes (§11).
> Sources : documentation officielle Roblox (*Console development guidelines*, *Gamepad input*, *Content maturity and compliance*), [`02-game-design-document.md`](02-game-design-document.md) (GDD, §10.4 mis à jour par ce document), [`04-architecture.md`](04-architecture.md) (contrat, §13).
> Contexte : le propriétaire du jeu joue sur PS5 avec une manette DualSense, sur un téléviseur vu à environ 3 m. Le jeu reste « mobile d'abord » ; ce document ajoute le **mode 10 pieds** sans rien retirer au tactile ni au clavier.

## Sommaire

0. Règles officielles retenues
1. Audit de l'existant (manette seule, téléviseur)
2. Détection de la plateforme (`Client/Util/Platform`)
3. Échelle « 10 pieds » et tailles minimales
4. Zone sûre TV
5. Glyphes de boutons
6. Correspondance complète de la DualSense
7. Navigation écran par écran
8. Chat
9. Retours : vibrations et sons de navigation
10. Tests : harnais console et règle → spec
11. Répartition du travail restant (3 groupes)
12. Publication console

---

## 0. Règles officielles retenues

| # | Règle (documentation Roblox) | Traduction pour Comet Conga |
|---|---|---|
| R1 | Expérience « 10 pieds » : tailles relatives, facteur d'échelle, agrandir quand `GuiService.ViewportDisplaySize` vaut `Enum.DisplaySize.Large` | §3 : UIScale proportionnel sans plafond sur écran Large ou console |
| R2 | `GuiService:IsTenFootInterface()` est la seule détection garantie d'une console | §2 : `Platform.isTenFoot()` (sous `pcall`) |
| R3 | Éléments importants dans la zone sûre TV | §4 : marge de 5 % de chaque côté dans `Root.safe` |
| R4 | Chaque élément interactif atteignable avec les 4 directions + valider + retour | §7, vérifié par `tests/harness/Layout` (§10) |
| R5 | Actions clés en peu de gestes, raccourcis | §6 : R2 Dash, croix directionnelle, △ menus, L2/R2 entre panneaux |
| R6 | **Pas de fenêtre de chat sur console** | §8 : `ChatWindowConfiguration.Enabled = false` (et barre de saisie) |
| R7 | Icônes de boutons adaptées à l'appareil (`UserInputService:GetImageForKeyCode`) ; jamais « X », « Y », « LB » en dur (ButtonX est le **Carré** d'une DualSense) | §5 : `UI/Glyph` |
| R8 | Vibrations avec modération (`HapticEffect`) | §9.1 : carte unique, délai minimal, priorités, réglage |
| R9 | Retour sonore de la navigation | §9.2 : sons `Select`, `Back`, `Tab`, `Bump` |
| R10 | Schéma conventionnel : ButtonA (✕) valider / sauter, ButtonB (○) retour, Thumbstick1 marche, Thumbstick2 caméra, R2/L2 actions principales, L1/R1/ButtonX/ButtonY actions secondaires | §6 |
| R11 | Navigation directionnelle sur mesure plutôt que le curseur virtuel | `StarterGui.VirtualCursorMode = Disabled` (projet Rojo) |
| R12 | Informations de maturité du contenu obligatoires pour la console | §12 |

Vocabulaire : ✕ Croix (`ButtonA`), ○ Rond (`ButtonB`), □ Carré (`ButtonX`), △ Triangle (`ButtonY`), L1/R1 (`ButtonL1`/`ButtonR1`), L2/R2 (`ButtonL2`/`ButtonR2`), croix directionnelle (`DPadUp/Down/Left/Right`), stick gauche (`Thumbstick1`), stick droit (`Thumbstick2`), Options (`ButtonStart`, réservé au menu Roblox), Create / pavé tactile (`ButtonSelect`, réservé à Roblox).

---

## 1. Audit de l'existant (manette seule, téléviseur)

Audit du code au 31/10/2026, confirmé en démarrant le **vrai client** en console manette seule dans le harnais (§10) : `Gamepad.audit` sur le HUD, navigation depuis △, ouverture de chaque panneau. « Socle » = corrigé par ce document ; G1/G2/G3 = groupe chargé de la correction (§11).

| Id | Domaine | Constat | Règle | Correction |
|---|---|---|---|---|
| A1 | Projet | Curseur virtuel laissé au réglage par défaut | R11 | **Socle** : `StarterGui.VirtualCursorMode = "Disabled"` (`default.project.json`) |
| A2 | Root | UIScale plafonné à 1,25 : en 1080p le HUD occupe 17 % de moins de l'écran qu'en 720p ; aucune lecture de `ViewportDisplaySize` ni de `IsTenFootInterface` | R1, R2 | **Socle** : `Platform.uiScale` (§3) |
| A3 | Root | Marges de 12 × 8 px de référence : rien ne protège du débordement TV | R3 | **Socle** : `Platform.safePadding` (§4) |
| A4 | Chat | Fenêtre de chat et barre de saisie actives sur console | R6 | **Socle** : `Platform.applyChatRule` (§8) |
| A5 | Glyphes | Aucun usage de `GetImageForKeyCode` ; repères de touches en texte | R7 | **Socle** : `Platform.glyph` + `UI/Glyph` ; adoption G1-G3 |
| A6 | HUD | Repère du Dash « X » à la manette (lettre Xbox ; c'est □ sur DualSense) — relevé par `Gamepad.audit` | R7 | G2 |
| A7 | HUD | Repères de touches de 16 px (< 18 px minimum) et seulement pour Dash (« X ») et Ping (« ↑ ») ; rien sur le rail, Équipage, Réglages, la minicarte, ACCLAMER, le suivi de quête | R1, R5, R7 | G2 |
| A8 | Entrées | Dash seulement sur □ ; R2 (action principale conventionnelle) libre | R5, R10 | G1 |
| A9 | Entrées | △ sélectionne le 1er bouton du rail, mais ni ○ ni △ ne rendent la main au jeu : la sélection reste, le stick gauche navigue au lieu de faire marcher (relevé par le harnais) | R4 | G1 |
| A10 | Entrées | △ panneau ouvert : sélectionne un bouton du rail **derrière** la fenêtre | R4 | G1 |
| A11 | Entrées | Croix ← libre ; le suivi de quête ne se replie qu'au toucher | R5 | G1 (liaison), G2 (repli) |
| A12 | Roue de pings | Bouton central « ✕ » pour fermer : sur PlayStation ✕ veut dire *valider* ; pas de repère ✕ / ○ ; touches 1-6 affichées au clavier seulement | R7 | G1 |
| A13 | Entrées | Type d'entrée calculé par InputController seul (dernier type d'entrée), sans `PreferredInput` | R2 | G1 : s'appuyer sur `Platform.inputKind()` |
| A14 | Panneaux | Fenêtre en `SelectionGroup` mais `SelectionBehavior*` = Escape : depuis chacun des 7 panneaux, la sélection s'échappe vers les 10 boutons du HUD derrière (relevé par `Layout.escapes`) | R4 | G3 |
| A15 | Panneaux | Bouton Fermer dessiné « ✕ » : confusion avec la Croix (valider) ; pas de repère ○ ni L1/R1 | R7 | G3 |
| A16 | Panneaux | Aucun raccourci entre panneaux à la manette (Boutique = △ puis 3 × ↓ puis ✕) | R5 | G3 (L2/R2) |
| A17 | Panneaux | Fermeture : sélection effacée, même si le panneau a été ouvert depuis le rail | R4 | G3 |
| A18 | Boutique | Après la fenêtre d'achat Roblox, la sélection n'est pas rendue au bouton Acheter ; Codes : parcours clavier virtuel non défini | R4, R5 | G3 |
| A19 | Collection | Grille virtualisée : en descendant à la croix, les cases sont réaffectées pendant le défilement et la sélection peut sauter sur un autre Nebby | R4 | G3 |
| A20 | Textes | « Tap Upgrade » / « Touche Améliorer », « Tap a Nebby… » / « Touche un Nebby… » : consignes tactiles affichées à la manette ; main animée (geste tactile) | R7 | G2 (accueil), G3 (Collection) |
| A21 | Supernova | Maintien à la manette déjà géré (✕ sur le bouton sélectionné) mais sans repère ✕, sans vibration de début ni de fin | R7, R8 | G3 |
| A22 | Équipage | Carte d'invitation (hors fenêtre) atteignable seulement par la sélection par défaut de Roblox ; aucun repère | R4, R5 | G3 (cible), G2 (△) |
| A23 | Chargement | « Réessayer » jamais sélectionné : sans curseur virtuel, une manette ne peut pas l'atteindre ; échelle propre ×1,2 bornée à 1,4 | R1, R4 | G2 |
| A24 | Vibrations | Une seule vibration (capture Épique+, `SetMotor` tactile d'abord), sans délai minimal ni réglage | R8 | **Socle** : `Util/Haptics` et réglage « Vibrations » (`Config/Settings.vibration`) ; branchement G1 (jeu), G3 (interface) |
| A25 | Sons | Aucun son de déplacement de sélection, de retour ni de bout de liste ; changement d'onglet = `Click` | R9 | **Socle** : clés `Select`, `Back`, `Tab`, `Bump` ; G1 (global), G3 (onglets) |
| A26 | Caméra | Panneau ouvert : le stick droit fait tourner la caméra derrière la fenêtre | R4 | G3 (stick droit = défilement) |
| A27 | Harnais | Pas de console simulée, pas de navigation, pas de géométrie (`AbsoluteSize` = 100 × 100 partout) | — | **Socle** : §10 |

Ce qui marche déjà et reste la base : liaisons `ContextActionService` (Q/croix ↑ roue, M/croix ↓ minicarte, F/croix → acclamer, Y rail), panneaux : ○ / Échap retour, L1/R1 onglets (liés à haute priorité et absorbés), sélection par défaut de chaque panneau (`Panel.defaultSelection`), `Selectable` sur tous les boutons, `NextSelection*` du rail et de la roue, pulsation `Juice.press` à la sélection, maintien de Supernova à ✕.

---

## 2. Détection de la plateforme (`Client/Util/Platform`, implémenté)

Module client sans dépendance vers les autres contrôleurs, **premier** de `Main.client.luau` (avant `UI/Root`, qui l'utilise). Ses lectures fonctionnent avant `Init`.

```lua
Platform.TOUCH, Platform.KEYBOARD, Platform.GAMEPAD   -- 1, 2, 3 (même codage qu'InputController et SnipByInput)
Platform.isTenFoot(): boolean          -- GuiService:IsTenFootInterface() sous pcall (false si l'appel échoue)
Platform.displaySize(): Enum.DisplaySize
Platform.isLargeDisplay(): boolean     -- console OU ViewportDisplaySize == Large
Platform.inputKind(): number           -- entrée préférée
Platform.usingGamepad(): boolean
Platform.gamepadConnected(): boolean
Platform.kindFor(inputType): number?   -- UserInputType → 1/2/3 (nil : Focus, etc.)
Platform.glyph(keyCode): Glyph         -- §5
Platform.isGamepadKey(keyCode): boolean
Platform.uiScale(viewport?, large?): number      -- §3
Platform.safePadding(viewport?, large?): Vector2 -- §4 (px de référence)
Platform.chatWindowAllowed(): boolean            -- §8
Platform.applyChatRule()
Platform.Changed: Signal<string>       -- "input" | "display" | "gamepad"
```

**Entrée préférée** : console → manette d'emblée ; sinon `UserInputService.PreferredInput` (Gamepad / MicroGamepad → manette, Touch → tactile, KeyboardAndMouse → clavier-souris), à défaut `GetLastInputType()`, à défaut les drapeaux `GamepadEnabled` / `TouchEnabled` / `KeyboardEnabled`. Ensuite, **le plus récent** de `LastInputTypeChanged` et du changement de `PreferredInput` l'emporte (un joueur PC qui prend sa manette voit aussitôt les glyphes de la manette). Toutes les API ont été confrontées à la base de réflexion livrée avec Lune (version 0.741) : `GuiService.ViewportDisplaySize`, `UserInputService.PreferredInput`, `Enum.PreferredInput`, `Enum.DisplaySize`, `ChatWindowConfiguration.Enabled`, `ChatInputBarConfiguration.Enabled`, `HapticEffect.Type`, `Enum.HapticEffectType`, `GuiObject.SelectionBehavior*`, `StarterGui.VirtualCursorMode` existent ; aucun équivalent ancien n'a été nécessaire.

---

## 3. Échelle « 10 pieds » et tailles minimales

**Règle exacte** (`Platform.uiScale`, `Config/Console`, appliquée par `UI/Root` à tous les écrans) :

| Écran | UIScale | 1280 × 720 | 1920 × 1080 | 3840 × 2160 |
|---|---|---|---|---|
| Ordinaire (téléphone, tablette, PC) | `clamp(min(L/1280, H/720), 0,6, 1,25)` (GDD §10.1, inchangé) | 1 | 1,25 | 1,25 |
| **Large ou console** | `max(0,6, min(L/1280, H/720))`, **sans plafond** | 1 | **1,5** | 3 |

Justification : un téléviseur de 55 pouces vu à 3 m occupe à peu près le même angle (≈ 13° de haut) qu'un téléphone tenu à bout de bras (≈ 11°). En gardant la référence 1280 × 720 **proportionnelle** à l'écran (au lieu de la plafonner à 1,25), chaque élément du HUD a sur le téléviseur la taille angulaire qu'il a sur un téléphone ; avec la zone sûre (§4), la surface utile vaut 1152 × 648 px de référence, soit la surface des téléphones de 390 dp que le HUD sait déjà gérer.

**Tailles minimales** (px de référence ; réels en 1080p = × 1,5) :

| Élément | Minimum | Réel en 1080p | Vérification |
|---|---|---|---|
| Texte lisible (tout texte que le joueur doit lire) | **18** (`Config/Console.MinTextSize`) | 27 px = 2,5 % de la hauteur | `Gamepad.audit` : pour un texte `TextScaled`, la plus grande taille où il tient en largeur **et** en hauteur (retours à la ligne compris, `MaxTextSize` du `UITextSizeConstraint` en plafond, largeur estimée par classe de caractère) ≥ 18 ; « texte coupé » s'il ne tient pas même à un `MinTextSize` ≥ 18 |
| Glyphe de bouton | **36** (`GlyphSize`) | 54 px | taille du cadre `Glyph` |
| Bouton principal / secondaire | 96 / 80 (GDD §10.1) | 144 / 120 px | inchangé |
| Repère de touche texte (`KeyCap` actuel) | interdit sous 18 : remplacé par `UI/Glyph` | — | `Gamepad.audit` |

Un texte purement décoratif (fond, filigrane) porte l'attribut `Decorative = true` et sort de l'audit. Le nombre de textes visibles n'augmente pas sur console : la divulgation progressive reste celle du GDD (§10.1), les listes longues restent dans des `ScrollingFrame`.

---

## 4. Zone sûre TV

- Sur écran Large ou console, la marge intérieure (`UIPadding`) de chaque `Root.safe` vaut **5 % de l'écran de chaque côté** (`Config/Console.TvSafeMargin`), en px de référence : `ceil(L × 0,05 / UIScale)` et `ceil(H × 0,05 / UIScale)`, jamais moins que les marges ordinaires (12 × 8). En 1920 × 1080 : **64 × 36** px de référence = 96 × 54 px réels. Ailleurs : 12 × 8 (inchangé). `Root.padding()` donne la marge courante.
- Tout ce qui est placé dans `Root.safe` est donc dans la zone sûre sans code supplémentaire ; les modules qui calculent des positions (HUD : `toLocal`, `contentSize`) lisent déjà les `Offset` de cette marge.
- Exceptions **décoratives** autorisées hors zone : fond d'écran de chargement, vignette rose de ScreenFX, voile d'assombrissement des panneaux, flash blanc, contour rose d'alerte (ils portent `Decorative = true` s'ils contiennent du texte).
- La zone est recalculée quand `ViewportSize` ou `ViewportDisplaySize` change (`Platform.Changed("display")`).
- Vérification : `Gamepad.audit(h)` signale tout objet sélectionnable ou texte visible qui déborde des 5 % (§10).

---

## 5. Glyphes de boutons

**Stratégie** (`Platform.glyph`, `UI/Glyph`) :

1. Manette : **image Roblox** `UserInputService:GetImageForKeyCode(keyCode)` — icônes PlayStation sur PlayStation, Xbox sur Xbox, sans rien coder en dur.
2. Repli si l'image manque ou si l'appel échoue : **neutre**, jamais une lettre Xbox. Boutons de façade : **losange de 4 points** dont le point de la position est plein (✕ = bas, ○ = droite, □ = gauche, △ = haut) ; gâchettes et boutons de tranche : « L1 », « R1 », « L2 », « R2 », « L3 », « R3 » ; croix directionnelle : « ↑ ↓ ← → » ; sticks : « L », « R ».
3. Clavier-souris : texte de la touche selon la **disposition du joueur** (`GetStringForKeyCode` : sur AZERTY, `KeyCode.Q` s'affiche « A »), noms courts pour les touches spéciales (« Shift », « Esc », « Enter »…).
4. Tactile : aucun repère.

`UI/Glyph` (implémenté) :

```lua
local g = Glyph.new(parent, { keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonR2 }, { size = 36, position = …, anchor = … })
g:set({ gamepad = Enum.KeyCode.ButtonB })  g:refresh()  g:shown()  g:destroy()
```

Le cadre porte les attributs `GlyphKey` (nom de la `KeyCode` affichée, `""` si masqué) et `GlyphMode` (`image` | `text` | `diamond` | `hidden`) ; tous les glyphes se mettent à jour sur `Platform.Changed` (une seule connexion pour le module). **Règle** : tout repère de touche du jeu passe par `UI/Glyph` ; les textes « X », « Y », « LB », « RB »… sont interdits à l'écran sur console (`Gamepad.audit`). Les consignes ne citent jamais une touche dans une phrase traduite : un glyphe est posé **à côté** d'un texte court (« ✕ » + « Acheter »), ce qui marche dans toutes les langues et sur toutes les manettes.

---

## 6. Correspondance complète de la DualSense

### 6.1 En jeu (aucun panneau, aucune sélection)

| Action | DualSense | KeyCode | Clavier / souris | Tactile | Propriétaire |
|---|---|---|---|---|---|
| Se déplacer | Stick gauche | `Thumbstick1` | WASD / flèches | Joystick | Roblox |
| Caméra | Stick droit | `Thumbstick2` | Clic droit + souris | Glisser | Roblox |
| Sauter | ✕ Croix | `ButtonA` | Espace | Bouton saut | Roblox |
| **Dash** | **R2** (et □ Carré) | `ButtonR2` (+ `ButtonX`) | Maj gauche ou E | Bouton Dash | InputController |
| Roue de pings | Croix ↑ | `DPadUp` | Q | Bouton Ping | InputController |
| Minicarte agrandie / réduite | Croix ↓ | `DPadDown` | M | Appui | InputController → Minimap |
| **Acclamer** (pendant les 10 s du bouton) | Croix → | `DPadRight` | F | Bouton ACCLAMER | InputController → HUD |
| Suivi de quête replié / déplié | Croix ← | `DPadLeft` | — | Appui | InputController (`QuestToggled`) → HUD |
| **Menus** (sélection sur le rail, §7) | △ Triangle | `ButtonY` | U, C, J, B, G (directs) | Rail | InputController → HUD |
| Menu Roblox | Options | `ButtonStart` | Échap | Bouton Roblox | **Roblox, jamais lié** |
| Sélection automatique Roblox | Create / pavé | `ButtonSelect` | — | — | **Roblox, jamais lié** |
| Libres (volontairement) | L1, R1, L2, L3, R3 | — | — | — | — |

L1, R1 et L2 restent libres en jeu : un enfant qui les presse par erreur ne déclenche rien. □ garde le Dash (GDD d'origine) en second choix.

### 6.2 Mode menu du HUD (après △)

| Action | DualSense | Effet |
|---|---|---|
| Déplacer la sélection | Croix / stick gauche | Rail, Équipage, Réglages, suivi de quête, minicarte, Ping, Dash, ACCLAMER, carte d'invitation |
| Activer | ✕ | `Activated` du bouton |
| Revenir au jeu | ○ ou △ | Sélection effacée, son `Back` |
| Dash | R2 / □ | Toujours actif |

Repère du mode menu : tant que la sélection est dans le HUD ou la minicarte (après △, ou après ○ qui ferme un panneau ouvert depuis le rail et rend la sélection au bouton du rail), l'icône au-dessus du rail (`RailGlyph`) passe de △ à **○** avec le libellé « Play » / « Jouer » à côté (`RailHint`, clé `hud.backToGame`, ≥ 18 px, manette seulement). Sélection effacée ou partie ailleurs (fenêtre de panneau, carte d'invitation) : △ revient, libellé masqué ; rafraîchi sur `Prefs.LanguageChanged` et `Platform.Changed`.

Sélection de départ : la carte d'invitation d'équipage visible (`PanelController.focusTarget()` : passagère, 20 s, et reliée à aucun bouton du HUD), sinon la cible de l'accueil (main / pulsation), sinon le bouton du rail qui porte une pastille « ! », sinon le dernier bouton du rail utilisé, sinon le premier bouton affiché (Améliorer). Améliorer = **△ ✕** (2 gestes). Tant que la carte d'invitation montre △ sur Accepter, le △ de l'instruction d'accueil est masqué (un seul △ à l'écran).

### 6.3 Panneaux

| Action | DualSense | KeyCode | Propriétaire |
|---|---|---|---|
| Déplacer la sélection | Croix / stick gauche | moteur Roblox | — |
| Valider | ✕ | `ButtonA` | moteur Roblox |
| **Retour** (Supernova → Améliorer → bouton du rail d'origine → jeu) | ○ | `ButtonB` | PanelController |
| Tout fermer, retour direct au jeu | △ | `ButtonY` | InputController |
| Onglet précédent / suivant, **en boucle** | L1 / R1 | `ButtonL1` / `ButtonR1` | PanelController |
| **Panneau précédent / suivant**, en boucle, panneaux autorisés seulement (garde du HUD) : Améliorer → Collection → Objectifs → Boutique → Équipage → Réglages | L2 / R2 | `ButtonL2` / `ButtonR2` | PanelController |
| Faire défiler la liste du panneau | Stick droit | `Thumbstick2` (absorbé) | PanelController |
| Confirmer la Supernova | **Maintenir ✕ 1 s** sur « Maintiens pour confirmer » | `ButtonA` | Panels/Supernova |
| Dash | **aucun** : □ absorbé comme R2 (la sélection tient le stick ; un appui égaré ne doit pas sortir le personnage du port sûr derrière la fenêtre) ; le clavier garde Maj / E | `ButtonX` | InputController |

Gestes : Boutique = △ ✕ R2 R2 R2 (ou △ ↓ ↓ ↓ ✕) ; chaque panneau est à au plus 3 gestes de son voisin.

### 6.4 Roue de pings

| Action | DualSense | Action CAS |
|---|---|---|
| Ouvrir / refermer | Croix ↑ | `CC_PingWheel` |
| Viser un secteur | Stick gauche (direction) ; ou croix ← / → : anneau en boucle, le **1er appui vise le secteur 1** (← depuis 1 → 6) | `CC_PingStick`, `CC_PingNav` |
| Envoyer | ✕ ; ✕ **sans secteur visé ferme** sans envoyer | `CC_PingConfirm` |
| Fermer sans envoyer | ○ (son `Back`) | `CC_Close` |

La roue ne pose **aucune** sélection `GuiService` : la croix, le stick et ✕ passent tous par ContextActionService (InputController) ; roue ouverte, la croix ← ne replie pas le suivi de quête. Envoi : remote `Ping(kind)` au plus 1 / 1,5 s et emote locale `Humanoid:PlayEmote` (2 → `point`, 4 → `cheer`, 6 → `wave`). Repères : ✕ « Envoyer » et ○ « Fermer » au centre de la roue (le « ✕ » dessiné du centre disparaît à la manette).

### 6.5 Supernova (maintien à la manette)

1. Améliorer → bouton Supernova (✕) ; la sélection par défaut de l'aperçu est le bouton **Maintenir**, accompagné du glyphe ✕. L'aperçu montre d'abord les **gains** (visibles sans défiler avant ce geste irréversible), puis les colonnes « Tu gardes » / « Remis à zéro » ; ↓ depuis Maintenir fait défiler l'aperçu.
2. Maintenir ✕ : l'anneau se remplit en `Balance.Supernova.HoldSeconds` (1 s) ; vibration `holdStart` au début.
3. Relâcher avant la fin, ou déplacer la sélection : annulé, aucun envoi.
4. À la fin : remote `Supernova`, son `Reward`, vibration `supernova` (héros) quand la célébration arrive.
5. Hors du port sûr : refus (secousse, vibration `refuse`, « Rentre au Nid »).
6. ○ revient à Améliorer.

### 6.6 Boutique et achats

| Étape | Manette |
|---|---|
| Ouvrir | △ ✕ puis R2 jusqu'à Boutique (ou △, ↓ × 3, ✕) |
| Onglets Passes / Boosts & Glow / Codes | L1 / R1 |
| Acheter | ✕ sur Acheter → fenêtre d'achat **Roblox** (navigable à la manette par Roblox : ✕ confirmer, ○ annuler) |
| Pendant la fenêtre | sélection du jeu vide : `Panels/Shop` appelle `PanelController.holdSelection(true)` après un appel réussi à `PromptGamePassPurchase` / `PromptProductPurchase` (repli : sélection effacée moins de `Config/Console.PromptHoldWindow` = 3 s après ✕ sur ce même bouton) |
| Après la fenêtre (`PromptProductPurchaseFinished`, `PromptGamePassPurchaseFinished`) | `holdSelection(false)`, puis la sélection revient sur le même bouton Acheter si le panneau est encore ouvert |
| Codes | ✕ sur le champ → clavier virtuel de la console ; validation du clavier → envoi automatique du code, sélection sur « Valider » |

Garde existante contre le double affichage de la fenêtre d'achat conservée.

### 6.7 Autres écrans

| Écran | Manette |
|---|---|
| Chargement « Ton Nid se réveille… » | « Réessayer » sélectionné d'office (manette ou console), glyphe ✕ à côté ; « Réessayer » attend tant que l'attribut `ProfileLoading` (> 0, posé par DataService pendant ses essais) est posé, puis 10 s (au plus 60 s) ; tant que l'écran est là, △ / ○ / croix / L1-R2 / raccourcis d'InputController passent sans rien faire (`Pass`, ni sélection effacée, ni son, ni `RailRequested`) et `HUD.selectRail()` ne sélectionne rien |
| Écran de retour hors ligne | OK sélectionné, ✕ ou ○ ferment |
| Équipage, « Inviter un ami » | fenêtre d'invitation Roblox (`SocialService:PromptGameInvite`) : `holdSelection(true)` pendant la fenêtre, rendue à « Inviter un ami » sur `SocialService.GameInvitePromptClosed` si le panneau est encore ouvert |
| Carte d'invitation d'équipage | △ la sélectionne (Accepter), ✕ accepte, → puis ✕ refuse ; ○ revient au jeu sans répondre. Glyphe d'Accepter : △ tant que rien n'est sélectionné sur la carte, ← depuis « Non merci », ✕ une fois Accepter sélectionné. Panneau ouvert : la carte attend sa fermeture (même échéance, pastille « ! » d'Équipage tant qu'elle n'a pas expiré) |
| Bouton ACCLAMER | glyphe croix → sur le bouton ; aussi atteignable au menu du HUD |
| Minicarte | glyphe croix ↓ au bord de la minicarte |

---

## 7. Navigation écran par écran

Règles communes :
- **Une seule source de sélection** : `GuiService.SelectedObject`. Aucune sélection en jeu (le stick fait marcher) ; une sélection n'est posée que si l'entrée préférée est la manette.
- Chaque fenêtre modale est un `SelectionGroup` avec `SelectionBehaviorUp/Down/Left/Right = Stop` : la sélection ne s'échappe jamais vers le HUD derrière.
- Chaque objet sélectionnable visible d'un écran est atteignable depuis la sélection par défaut avec les 4 directions (graphe `NextSelection*` explicite là où la géométrie hésite, sinon la sélection directionnelle de Roblox).
- ○ recule d'**un** niveau ; △ ramène au jeu ; L1/R1 onglets ; L2/R2 panneaux.
- **Bouclage** : anneaux (roue de pings), onglets (L1/R1) et panneaux (L2/R2) bouclent ; listes et grilles **ne bouclent pas**. ↑ / ↓ sans rien de sélectionnable de ce côté (lignes en lecture seule de l'Atlas, du Guide, aperçu de la Supernova) font défiler la liste de **70 %** de sa hauteur visible (une sélection dans la liste reste à l'écran) ; son `Bump` + vibration `listEnd` seulement au **vrai** bout de la liste, ou pour ← / → au bord de la fenêtre.
- Un panneau qui change de contenu (onglet, achat, fusion) remet une sélection valide (jamais un objet masqué ou détruit) : sélection par défaut du panneau si elle est affichée, sinon le bouton de l'**onglet affiché**, sinon le premier onglet, sinon Fermer (`PanelController.defaultSelection`).
- **Sélection visible à 3 m** : tout objet sélectionnable du jeu reçoit `SelectionImageObject = Root.selectionImage()` (trait blanc de 6 px bordé d'un liseré sombre de 2 px, débord 4 px, respiration 0↔0,35 en 1,2 s hors Mouvement réduit ; implémenté) en plus de la pulsation `Juice.press` existante. « Réessayer » de l'écran de chargement (`src/first/Loading.client`, autonome) en recopie le dessin, sans respiration.
- **Sélection jamais perdue dans un panneau** : une sélection effacée pendant qu'un panneau est ouvert (pavé tactile / Créer de la DualSense, menu du système refermé…) est rendue tout de suite (dernier objet de la fenêtre s'il est encore affiché, sinon la sélection par défaut). Elle ne reste vide que tant qu'une fenêtre Roblox tient la manette : fenêtre d'achat (✕ puis sélection effacée dans les 3 s, ou `PanelController.holdSelection(true)`), fenêtre d'invitation, menu du système ouvert. Croix ↑ / ↓ / → sans sélection, panneau ouvert : absorbées (`PanelNavGuard` de PanelController) — ni roue de pings, ni minicarte, ni ACCLAMER derrière la fenêtre ; au clavier, Q, M et F passent de même (InputController). Croix ← non liée (le suivi de quête passe déjà).
- **Double appui** : une fermeture demandée moins de `Config/Console.ToggleCloseGuard` (0,35 s) après l'ouverture du même panneau (`InputController.togglePanel` : rail, Équipage, Réglages, raccourcis clavier) est ignorée — un double appui n'ouvre pas puis referme aussitôt.

| Écran | Sélection par défaut | ○ | L1 / R1 | L2 / R2 | Bouclage |
|---|---|---|---|---|---|
| Jeu | aucune | — | — | R2 = Dash | — |
| Menu du HUD (△) | §6.2 | retour au jeu | — | — | non (le rail s'arrête en haut et en bas ; ↑ depuis le 1er bouton → Équipage) |
| Roue de pings | aucune au stick ; secteur 1 à la croix | ferme | — | — | anneau |
| Améliorer | carte qui pulse (accueil), sinon la moins chère achetable, sinon Conga | → bouton du rail d'origine (ou jeu) | — | panneaux | non |
| Supernova | Maintenir | → Améliorer | — | panneaux | non |
| Collection | Perchoirs : 1re case ; Réserve : « Sélectionner » ; Forge : « Tout fusionner » ; Atlas : 1re entrée ; Guide : 1re ligne | → rail | onglets | panneaux | non |
| Objectifs | « Réclamer » disponible, sinon 1re carte | → rail | onglets | panneaux | non |
| Boutique | 1er « Acheter » de l'onglet ; Codes : champ | → rail | onglets | panneaux | non |
| Équipage | 1er « Inviter » visible, sinon « Inviter un ami » | → rail | — | panneaux | non |
| Réglages | 1er interrupteur | → rail | — | panneaux | non |
| Écran de retour | OK | ferme | — | — | — |
| Chargement (échec) | Réessayer | — | — | — | — |

Repères visibles à la manette : ○ sur le bouton Fermer (le « ✕ » dessiné disparaît) ; sur la **Supernova**, ○ est sur Retour (→ Améliorer) et Fermer porte **△** (tout fermer) ; L1 et R1 aux deux bouts de la barre d'onglets, L2 et R2 aux coins de l'en-tête, ✕ sur le bouton Maintenir, △ sur le rail du HUD (○ « Jouer » en mode menu, §6.2).

Retours : seul ○ (`PanelController.back()`) rend la sélection au bouton du rail d'origine ; △ (`PanelController.close()` puis sélection effacée) ne rend **jamais** de sélection, ni tout de suite ni après l'animation de fermeture ; le HUD ne re-sélectionne pas de lui-même après un ○ ou un △ (seul △ en jeu appelle `HUD.selectRail`).

---

## 8. Chat

- **Console** (`Platform.isTenFoot()`) : `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)` (nouveaux essais toutes les `Config/Console.ChatCoreRetry` = 0,5 s pendant `ChatWaitTimeout` si le CoreGui n'est pas prêt ; avertissement seulement si tous échouent), **et** `TextChatService.ChatWindowConfiguration.Enabled = false` **et** `ChatInputBarConfiguration.Enabled = false` (la barre seule ne sert à rien sans fenêtre et taper à la manette n'est pas une interaction console). Les configurations sont attendues au plus `Config/Console.ChatWaitTimeout` (10 s), sans avertissement si elles n'existent pas (ancien chat).
- La place déclare `TextChatService.ChatVersion = TextChatService` (`default.project.json`, vérifié par `scripts/verify-place.luau` : la base de réflexion de Rojo / Lune donnerait sinon `LegacyChatService`).
- Les **bulles** restent (`BubbleChatConfiguration` inchangée) : un joueur console voit ce que disent les autres au-dessus de leur tête.
- Communication console : la **roue de pings** (6 messages illustrés, emotes) remplace le chat.
- PC et mobile : rien n'est changé.
- Implémenté : `Platform.applyChatRule()`, appelé par `Platform.Start()`.

---

## 9. Retours : vibrations et sons de navigation

### 9.1 Carte des vibrations (`Util/Haptics`, `Config/Console.Haptics`, implémenté)

`Haptics.play(événement, atténuation?)` : `HapticEffect` du type indiqué (une instance réutilisée par type, dans `workspace`) ; repli `HapticService:SetMotor(Gamepad1, moteur, force)` pendant la durée si `HapticEffect` est indisponible. **Modération** : jamais au clavier-souris ; au téléphone seulement les événements « mobile » (GDD §9.1) ; délai minimal de **0,25 s** entre deux vibrations, sauf priorité supérieure ; atténuation < 0,35 ignorée ; réglage « Vibrations » (`Config/Settings.vibration`, activé par défaut, juste après « Effets sonores » dans Réglages ; `false` → rien). Jamais de vibration sur un simple déplacement de sélection, un Dash ou une capture ordinaire.

| Événement | Quand | HapticEffectType | Repli (moteur, force, durée) | Priorité | Mobile | Branché par |
|---|---|---|---|---|---|---|
| `refuse` | bouton de panneau refusé (pas assez, verrouillé, hors du port) ; jamais pour un Dash en recharge | UIClick | Small, 0,25, 0,05 s | 1 | non | G3 |
| `listEnd` | bout de liste atteint | UIClick | Small, 0,2, 0,04 s | 1 | non | G3 |
| `holdStart` | début du maintien de Supernova | UIClick | Small, 0,25, 0,05 s | 1 | non | G3 |
| `catchEpic` | capture Épique (GDD §9.4) | GameplayCollision | Small, 0,4, 0,08 s | 2 | oui | G1 (VFXController) |
| `catchLegendary` | capture Légendaire+ | GameplayCollision | Large, 0,6, 0,15 s | 3 | oui | G1 |
| `snipper` | j'ai coupé une file | GameplayCollision | Small, 0,35, 0,08 s | 2 | non | G1 |
| `snipped` | ma file est coupée | GameplayCollision | Large, 0,7, 0,25 s | 4 | non | G1 |
| `parade` | parade ≥ 15 Nebbies | UINotification | Small, 0,35, 0,12 s | 2 | non | G1 |
| `cometWarn` | alerte Comète (−8 s) | UINotification | Small, 0,3, 0,12 s | 2 | non | G1 |
| `cometImpact` | impact à < 120 studs, atténué `1 − d/120` | GameplayExplosion | Large, 0,8, 0,3 s | 4 | non | G1 |
| `cometGrab` | je ramasse ou vole la Comète | GameplayCollision | Large, 0,5, 0,15 s | 3 | non | G1 |
| `supernova` | ma Supernova (héros) | GameplayExplosion | Large, 1, 0,4 s | 5 | non | G1 |

`VFXController.haptic(force, durée)` (contrat) reste et passe par le même délai minimal.

### 9.2 Sons de navigation (`Config/Sounds`, clés ajoutées, sons publiés par Roblox depuis r4)

| Clé | Quand | Joué par |
|---|---|---|
| `Select` | la sélection change (manette), au plus 1 / `NavSoundInterval` (0,06 s) ; pas à la pose initiale par le code | G1 (écoute globale de `GuiService.SelectedObject`) |
| `Back` | ○ recule (panneau, menu du HUD, roue) | G1 (HUD, roue), G3 (panneaux) |
| `Tab` | L1/R1 (onglet) et L2/R2 (panneau) | G3 |
| `Bump` | bout de liste (avec `listEnd`) | G3 |
| `Click`, `Whoosh`, `Error` | activation, ouverture de panneau, refus (existants) | inchangé |

Le jeu reste entièrement jouable en silence (GDD §9.1).

---

## 10. Tests : harnais console et règle → spec

### 10.1 Harnais (implémenté)

| Ajout | Effet |
|---|---|
| `Harness.new({ mode = "client", console = true })` | `IsTenFootInterface()` vrai, `ViewportDisplaySize = Large`, écran 1920 × 1080 (caméra et `ScreenGui`), manette seule (`GamepadEnabled`, ni tactile ni clavier ni souris), `PreferredInput = Gamepad`, dernier type d'entrée `Gamepad1`, `GetImageForKeyCode` → icônes PlayStation (`Gamepad.PS_GLYPHS`) ; option `viewport` |
| Tous les clients | `TextChatService` avec `ChatWindowConfiguration`, `ChatInputBarConfiguration`, `BubbleChatConfiguration` ; `GetImageForKeyCode` (Xbox hors console) ; `GetStringForKeyCode` (chiffres) ; `GamepadConnected/Disconnected` ; `HapticService` et `HapticEffect` journalisés dans `h.log.haptics` ; `SelectionGained` / `SelectionLost` émis quand `GuiService.SelectedObject` change ; boutons, champs et cadres défilants `Selectable` par défaut (comme Roblox) ; liaisons CAS avec touches et priorités (`h.actionBindings`) |
| `tests/harness/Layout` | géométrie des interfaces (Size, Position, AnchorPoint, UIPadding, UIScale cumulés, UISizeConstraint, UIAspectRatioConstraint, UIListLayout, UIGridLayout, ScrollingFrame, AutomaticSize des conteneurs) → `AbsolutePosition` / `AbsoluteSize` ; navigation : `step` (explicite puis géométrique, `SelectionGroup` + `SelectionBehavior`), `reachable`, `unreachable`, `escapes` |
| `tests/harness/Gamepad` | `press` / `release` / `tap` / `stick` : croix = navigation quand une sélection existe, ✕ = `Activated` au relâchement, autres boutons = actions CAS par priorité (Pass propage) ; `audit(h, { root })` : glyphes non PlayStation, textes de boutons Xbox, textes < 18 px, débordement de la zone sûre |

Modèle d'entrée documenté dans l'en-tête de `Gamepad.luau` (approximation du moteur ; la fonction de score de la sélection directionnelle n'est pas celle, non documentée, de Roblox : les specs vérifient l'atteignabilité, pas un chemin exact). Limite connue : `Layout.step` part du rectangle **après** `UIScale` ; un bouton sélectionné grossi de 5-6 % autour de son coin haut gauche (`Widgets` / `Juice`) peut, au bord gauche d'une grille, faire passer la croix ← sur la case du dessous là où le moteur s'arrêterait sans doute. Les specs de grilles visent donc des index exacts (`Console_panels.spec`, Réserve) plutôt que d'enchaîner des ← au bord.

`ApiAudit` connaît `Humanoid:PlayEmote` (vraie méthode Roblox absente de la base de réflexion, appelée sous pcall par les pings à emote et l'acclamation).

### 10.2 Règle → test

| Règle | Spec | Vérification |
|---|---|---|
| Détection console sous pcall, entrée préférée, glyphes, échelle, zone sûre | `Console.spec` (socle) | valeurs exactes, IsTenFootInterface qui échoue, AZERTY, repli losange |
| Root 1,5 et 64 × 36 sur console, inchangé ailleurs | `Console.spec` | `RootScale`, `UIPadding`, `Layout.rect` |
| Pas de fenêtre de chat | `Console.spec` | console / PC / téléphone / configuration tardive ou absente |
| Vibrations modérées | `Console.spec` | type, délai, priorité, repli SetMotor, réglage, clavier, mobile |
| Curseur virtuel désactivé | `Console.spec` | `default.project.json` |
| Cadre de sélection visible à 3 m | `Console.spec` | `Root.selectionImage()` (trait blanc 6 px + liseré sombre 2 px, API auditée ; copie de « Réessayer » : `Fix_r4_release.spec`) |
| Interfaces entre groupes | `Console.spec` | garde transmise à PanelController, `QuestToggled`, `focusTarget` |
| Réglage « Vibrations » | `Console.spec`, `Panels.spec` | profil `settings.vibration` suivi en direct ; ligne affichée dans Réglages |
| Démarrage console complet, API valide | `Console.spec` | `Main.client` + `ApiAudit` : 0 erreur, 0 avertissement, 0 écart |
| Entrées : R2/□ Dash, △ entre et sort du menu, ○ sort, croix ←, roue ✕/○, haptique de jeu, sons de navigation | `Console_input.spec` (G1) | `Gamepad.tap` sur le vrai client console |
| HUD, accueil, minicarte, bannières, toasts, chargement : glyphes PlayStation, textes ≥ 18, zone sûre, tout atteignable depuis △ | `Console_hud.spec` (G2) | `Gamepad.audit`, `Layout.unreachable` |
| Chaque panneau : ○ recule, L1/R1, L2/R2, aucune fuite de sélection, tout atteignable, glyphes PlayStation | `Console_panels.spec` (G3) | `Layout.escapes`, `Layout.unreachable`, `Gamepad.audit` |
| Interfaces croisées G1-G3 : □ absorbé panneau ouvert, △ sans sélection rendue, une seule vibration `supernova`, pings à emote audités | `Console_release.spec` | `Gamepad.tap` / `press` / `release`, `Haptics.Played`, `ApiAudit` |

---

## 11. Répartition du travail restant (3 groupes, fichiers disjoints)

Règles communes : chaque groupe ne modifie que ses fichiers, plus les registres partagés (`Localization/Strings.luau`, `Remotes.luau`, `Config/Sounds.luau` : relire juste avant chaque petite modification, EN et FR) et ses nouvelles specs. Ne pas modifier les modules du socle (`Util/Platform`, `Util/Haptics`, `UI/Glyph`, `UI/Root`, `Config/Console`, `tests/harness/*`) : un besoin y est signalé dans les notes d'intégration. Interfaces entre groupes déjà posées par le socle : `InputController.QuestToggled` (G1 émet, G2 écoute), `PanelController.setGate` / `allowed` (G1 transmet la garde du HUD, G3 l'utilise), `PanelController.focusTarget()` (G3 l'implémente, G2 l'appelle depuis `HUD.selectRail`).

| Groupe | Fichiers | Spec |
|---|---|---|
| **G1 — Entrées, audio, vibrations** | `Controllers/InputController.luau`, `Controllers/AudioController.luau`, `Controllers/VFXController.luau` | `tests/specs/Console_input.spec.luau` |
| **G2 — HUD et écrans permanents** | `UI/HUD.luau`, `UI/Hud/*`, `UI/Minimap.luau`, `UI/Banners.luau`, `UI/ScreenFX.luau`, `UI/Toast.luau`, `Controllers/OnboardingController.luau`, `src/first/Loading.client.luau` | `tests/specs/Console_hud.spec.luau` |
| **G3 — Panneaux** | `Controllers/PanelController.luau`, `UI/Panels/*` | `tests/specs/Console_panels.spec.luau` |

Compatibilité avec les specs existantes : les repères clavier `KeyCap` (TextLabel « E », « Q », « U »…) **restent** pour le clavier (specs `HUD`, `Fix_client-hud_r1`) mais sont masqués à la manette ; à la manette s'affiche un `UI/Glyph` nommé `PadGlyph`. Aucun test existant n'est supprimé ni affaibli.

### G1 — Entrées, audio, vibrations

1. **A8, §6.1** — Dash aussi sur `ButtonR2` (garder □, Maj gauche, E).
2. **A13, §2** — `InputController.inputType()` et `InputTypeChanged` suivent `Platform.inputKind()` / `Platform.Changed("input")` (`Platform.Init()` appelé dans `InputController.Init`, idempotent) ; envoi `SetInputType` (1 / 5 s) inchangé.
3. **A9, A10, §6.2-§6.3** — △ : panneau ouvert → `PanelController.close()` puis sélection effacée ; sinon sélection active (menu du HUD, carte d'invitation) → effacée ; sinon `RailRequested`. ○ (`CC_Close`) : roue ouverte → fermée ; sinon, sans panneau, sélection active → effacée. Son `Back` à chaque retour.
4. **A11** — croix ← (`DPadLeft`, action `CC_Quest`) → `InputController.QuestToggled`.
5. **A12, §6.4** — roue de pings à la manette : `PadGlyph` ○ (`ButtonB`) au centre à la place du « ✕ » dessiné, repère ✕ (`ButtonA`) « envoyer » ; `KeyCap` 1-6 gardés au clavier, masqués à la manette ; textes ≥ 18 px.
6. **A25, §9.2** — `AudioController` : son `Select` quand `GuiService.SelectedObject` passe d'un objet à un autre (manette), au plus 1 / `NavSoundInterval` ; rien à la pose initiale ni à l'effacement.
7. **A24, §9.1** — vibrations du jeu via `Util/Haptics` : `catchEpic` / `catchLegendary` (captures du joueur local, remplace l'appel actuel), `snipper` / `snipped`, `parade` (≥ 15), `cometImpact` (atténuée `1 − d/120`), `cometWarn`, `cometGrab`, `supernova` (héros local) ; `VFXController.haptic(force, durée)` (contrat) garde sa signature, manette d'abord quand elle est l'entrée préférée, et respecte le délai minimal.
8. **Spec** `Console_input.spec` : client console complet ; R2 et □ envoient `Dash` ; △ sélectionne le rail puis rend la main ; ○ rend la main ; △ panneau ouvert ferme tout ; ← émet `QuestToggled` ; roue : `Gamepad.audit` vide, `PadGlyph` central = `ButtonB` en image PlayStation, stick + ✕ envoie `Ping`, ○ ferme (`Back`) ; `Select` joué au déplacement, pas à la pose ; vibrations journalisées (`h.log.haptics`) pour une capture Épique et une coupe subie, aucune au clavier ni avec le réglage désactivé ; `ApiAudit` vide.

### G2 — HUD et écrans permanents

1. **A6, A7, §5** — `PadGlyph` (UI/Glyph) : Dash `ButtonR2`, Ping `DPadUp`, minicarte `DPadDown`, ACCLAMER `DPadRight`, suivi de quête `DPadLeft`, un △ (`ButtonY`) au-dessus du rail ; `KeyCap` masqués à la manette (texte clavier via `Platform.glyph(...).text`, disposition du joueur) ; plus aucun « X ».
2. **§7** — `SelectionImageObject = Root.selectionImage()` sur tous les boutons du HUD et de la minicarte (`Hud/Widgets.button`, minicarte).
3. **A9, §6.2** — `HUD.selectRail()` : carte d'invitation (`PanelController.focusTarget()`) > cible de l'accueil > bouton du rail à pastille « ! » > dernier panneau du rail ouvert (`PanelController.Opened`) > premier bouton affiché ; graphe `NextSelection*` complété pour que tout le HUD et la minicarte soient atteignables depuis cette cible (accueil partiel, HUD complet, bouton ACCLAMER affiché).
4. **A11** — `InputController.QuestToggled` replie / déplie le suivi de quête.
5. **A20, §6.2** — accueil à la manette : clé `onboarding.openUpgrade` (EN « Open Upgrade », FR « Ouvre Améliorer ») avec glyphe △ à la place de « Touche Améliorer », puis ✕ quand le rail est sélectionné ; main animée remplacée par le glyphe à la manette ; glyphe R2 pendant la pulsation du Dash (Q5). `OnboardingPlan` reste pur (fait `gamepad` en entrée).
6. **A23, §6.7** — `Loading.client` (autonome) : règle d'échelle TV recopiée de `Config/Console` (vérifiée par la spec) ; « Réessayer » sélectionné d'office si `IsTenFootInterface()` (sous pcall) ou `GamepadEnabled` ; icône ✕ (`GetImageForKeyCode(ButtonA)`) à côté.
7. **§3-§4** — mise en page à 1920 × 1080 (UIScale 1,5, zone sûre 64 × 36) : aucun chevauchement (rangée du haut, colonne de droite, rail, compteur de file, Dash/Ping, ACCLAMER, consigne d'accueil), bannières, toasts, tampons et textes flottants de ScreenFX ≥ 18 px et dans la zone sûre ; minicarte agrandie dans la zone sûre ; fonds plein écran marqués `Decorative`.
8. **Spec** `Console_hud.spec` : client console complet, HUD complet puis accueil (étapes 1-3) ; `Gamepad.audit` vide avec bannière, 3 toasts, tampon et minicarte agrandie ; △ → cible attendue ; `Layout.unreachable` vide sur le HUD et la minicarte ; ← replie le suivi ; glyphes `ButtonR2`, `DPadUp`, `DPadDown`, `DPadRight` en images PlayStation ; chargement : Réessayer sélectionné, échelle 1,5 en 1080p, constantes égales à `Config/Console`.

### G3 — Panneaux

1. **A14, §7** — fenêtre (et carte d'invitation) : `SelectionBehaviorUp/Down/Left/Right = Stop` ; après un changement d'onglet ou de contenu, sélection toujours valide (sinon `defaultSelection`) ; `SelectionImageObject = Root.selectionImage()` dans `Panels/Widgets`.
2. **A15, §7** — en-tête à la manette : `PadGlyph` ○ sur Fermer / Retour (le « ✕ » dessiné masqué), L1 / R1 aux bouts de la barre d'onglets (≥ 2 onglets visibles), L2 / R2 aux coins de l'en-tête.
3. **A16, §6.3** — L2 / R2 (liés à `ACTION_PRIORITY` pendant qu'un panneau est ouvert, absorbés : pas de Dash) : panneau précédent / suivant en boucle (Améliorer, Collection, Objectifs, Boutique, Équipage, Réglages ; Supernova compte comme Améliorer), seulement si `PanelController.allowed(nom)` ; son `Tab`.
4. **A17, §7** — à l'ouverture, retenir la sélection hors fenêtre (bouton du rail) ; ○ qui ferme la rend si elle est encore visible (manette) ; son `Back`.
5. **A26** — stick droit (`Thumbstick2`, absorbé) : fait défiler la liste qui contient la sélection.
6. **A25, §9** — L1/R1 : son `Tab` (au lieu de `Click`) ; croix ↑ / ↓ sans changement de sélection à l'image suivante : la liste défile de 70 % de sa hauteur visible ; `Bump` + `Haptics.play("listEnd")` seulement au vrai bout de la liste ou pour ← / → ; refus (`Widgets.refuse`) : `Haptics.play("refuse")`.
7. **A21, §6.5** — Supernova : `PadGlyph` ✕ sur Maintenir, `Haptics.play("holdStart")` au début du maintien, refus avec vibration.
8. **A18, §6.6** — Boutique : après `PromptProductPurchaseFinished` / `PromptGamePassPurchaseFinished`, re-sélection du bouton Acheter pressé ; Codes : validation du clavier virtuel (`FocusLost` avec Entrée) → envoi du code et sélection de « Valider ».
9. **A19** — `VirtualGrid` / Collection : la sélection suit l'**index** quand les cases sont réaffectées au défilement ; la croix ↓ sur la dernière rangée visible fait défiler d'une rangée ; tous les Nebbies atteignables.
10. **A20** — Collection : clés neutres `collection.selectHint.pad` (« Choose a Nebby to see it » / « Choisis un Nebby pour le voir ») et `collection.releaseHint.pad` (« Choose Nebbies to release » / « Choisis des Nebbies à libérer ») à la manette.
11. **A22, §6.7** — carte d'invitation : `PanelController.focusTarget()` renvoie Accepter tant qu'elle est visible ; Accepter ↔ Refuser reliés ; glyphe d'Accepter △ tant que rien n'est sélectionné sur la carte, ← depuis Refuser, ✕ une fois Accepter sélectionné ; panneau ouvert : la carte attend sa fermeture (même échéance, pastille « ! » d'Équipage).
12. **Spec** `Console_panels.spec` : client console complet ; pour chaque panneau et chaque onglet : sélection par défaut dans la fenêtre, `Layout.escapes` vide, `Layout.unreachable` vide, `Gamepad.audit` vide ; ○ (Supernova → Améliorer → bouton du rail), L1/R1 en boucle, L2/R2 en boucle avec la garde, R2 sans Dash panneau ouvert ; Supernova maintenue au `Gamepad.press/release` (relâchement anticipé = rien, `holdStart` journalisé) ; Boutique : re-sélection après la fenêtre d'achat ; Réserve de 60 Nebbies parcourue à la croix jusqu'au dernier.

### Intégration (validation de publication)

Groupes G1-G3 livrés ; notes croisées résolues (spec `Console_release.spec`) :

- **G1** — `InputController.inputType()` / `InputTypeChanged` suivent l'entrée préférée (`Platform.inputKind`) ; actions `CC_Quest` (croix ←) et `CC_PingNav` (anneau de la roue) ; △ et ○ reculent d'un pas avec `Back`. **□ panneau ouvert : absorbé sans Dash** (comme R2, §6.3). Vibration `supernova` du héros jouée par InputController seul (le panneau Supernova ne joue que `holdStart` et `refuse`). `AudioController.playNav()` et l'écoute de `SelectedObject` (son `Select`, au plus 1 / `NavSoundInterval` : un double déplacement dans la même image — défilement de la Réserve — ne joue qu'un son).
- **G2** — `HUD.selectRail()` : carte d'invitation (`PanelController.focusTarget()`, ignorée si hors écran) > cible de l'accueil > rail à pastille « ! » > dernier panneau du rail ouvert (`Opened`, Supernova = Améliorer) > premier bouton affiché. Instances `PadGlyph` (repères de touches), `RailGlyph` (△ au-dessus du rail), `HandGlyph` (main de l'accueil remplacée par la touche). À la manette, △ à y = 144-180 et le rail descend à y = 188 ; pas de grille 2 × 2 sur console. Barre de la Balise bornée à 320-420 px selon la largeur intérieure (jamais sous Équipage / Réglages). `Hud/OnboardingPlan` : fait `gamepad` ; clé `onboarding.openUpgrade` (EN / FR). `Loading.client` : `REFERENCE` (1280 × 720) et `TV_SCALE_MIN` (0,6) recopiés de `Config/Console` (vérifiés par la spec). Toasts, bannières, tampons, titre Supernova, cartes d'Atlas : ≥ 18 px et dans `Root.safe`, sans modification.
- **G3** — nouvelles API (docs/04 §13.15) : `PanelController.cyclePanel`, `PanelController.select`, `Crew.inviteTarget()` (Accepter) / `Crew.inviteCard()`, `VirtualGrid` option `selectable` et `reveal(index)` ; actions CAS `PanelBack`, `PanelTabPrev` / `PanelTabNext`, `PanelPrev` / `PanelNext` (L2 / R2), `PanelScroll` (stick droit) à `High + 50`, liées seulement panneau ouvert.
- **Limites connues** (sans effet en jeu) : `VFXController.haptic` (contrat) attend le délai après `Haptics.Played`, mais `Haptics.play` ne voit pas une vibration lancée par `VFXController.haptic` (horodatage privé) ; aucun appel dans le jeu. Une API `Haptics.note()` rendrait le délai commun dans les deux sens si l'appel revient. Navigation du harnais après `UIScale` : voir §10.1.

---

## 12. Publication console

- Remplir le **questionnaire de maturité du contenu** (Creator Dashboard → Publish settings → Content rating) : obligatoire pour la console ; Comet Conga vise **Minimal** (aucune violence réaliste, pas de sang, pas de peur ; coupe = dispersion comique).
- Activer la console dans les paramètres de l'expérience (appareils pris en charge) seulement après le passage des specs console (§10.2) et un essai sur une vraie PS5 : lisibilité à 3 m (55 et 43 pouces), zone sûre avec l'ajustement de zone d'affichage de la PS5, tous les écrans à la manette sans curseur, achats d'essai, vibrations jugées « modérées » par un enfant.
- Rejouer la checklist release de la skill `roblox-qa-testing` avec une manette dans Studio (émulateur de manette) avant l'essai sur PS5.
