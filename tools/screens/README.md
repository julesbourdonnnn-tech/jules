# Captures d'écran hors moteur (tools/screens)

Cet outil fabrique de **vraies images** de l'interface de Raise a Squishy, sans Roblox Studio, et
**contrôle chaque texte** : est-ce qu'il tient dans sa boîte, est-ce qu'il est assez grand pour un
téléviseur à 3 m, est-ce qu'il sort de la zone sûre, est-ce qu'il est lisible sur son fond, etc.

Il n'est **jamais livré** dans le jeu : Rojo ne prend que `src/` (`default.project.json` ne
mentionne pas `tools/`). Les aides de test sont dans `tests/harness/`.

Repris de l'outil de Comet Conga, adapté à ce jeu : console d'abord (PS5, manette), 28 px minimum,
zone sûre de 5 % partout, aucun téléphone ni tablette.

## En une commande

```bash
./tools/screens/run.sh
```

Cela prend environ 6 minutes (3 min de captures, 3 min de dessin) et produit, dans
`/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/rs-captures/`
(autre dossier : `--out <dossier>` ou variable `RS_CAPTURES`) :

| Fichier | Contenu |
|---|---|
| `index.html` | **planche contact** : toutes les vignettes, filtres par appareil, écran et type de problème |
| `<appareil>-<langue>/<écran>.png` | l'image à la taille réelle de l'écran (ex. 1920 × 1080) |
| `<appareil>-<langue>/<écran>.billboards.png` | les textes du monde (invites, panneaux des ranchs…) à leur taille en pixels |
| `<appareil>-<langue>/<écran>.report.json` | les problèmes trouvés sur cet écran |
| `summary.json` | totaux par type, pires problèmes, problèmes regroupés (même objet sur tous les formats) |
| `keys.json` | chaque clé de texte : prouvée (nombre de boîtes), en échec, ou jamais affichée |
| `json/` | les instantanés bruts (une description de chaque objet visible) |

Options utiles :

```bash
./tools/screens/run.sh --profiles tv1080 --langs fr --screens panel.Ranch   # seulement le Ranch, TV, français
./tools/screens/run.sh --groups mid                  # un seul groupe d'écrans
./tools/screens/run.sh --pending --keys-pending      # régénère aussi les deux listes « en attente »
./tools/screens/run.sh --cap screen                  # dessine l'autre hypothèse sur TextScaled (voir plus bas)
RS_CAPTURES=/tmp/mes-captures ./tools/screens/run.sh
```

Appareils (`--profiles`) : `tv1080` (PS5, 1920 × 1080), `tv2160` (PS5, 3840 × 2160), `tv720`
(1280 × 720), tous à la manette avec les glyphes PlayStation, et `pc` (1366 × 768, clavier-souris).
Langues : `fr`, `en`. Groupes (`--groups`) :

| Groupe | Écrans |
|---|---|
| `loading` | écran de chargement, puis « Réessayer » |
| `new` | nouveau joueur : HUD, les 11 étapes de l'accueil, Objectifs › Accueil, Ranch, Réglages |
| `mid` | HUD dans chaque mode (Cozy, BOOP RUSH, MEGA, Jelly Moon, Golden, fête, sieste de Big Plop, tout ensemble), chaque invite du monde, le menu, **chaque panneau et chaque onglet**, les fiches (✕ sur une case), les sous-listes de Style, les listes déroulées jusqu'au bout, les 18 objectifs, les cartes (booped, retour, objectifs, Squishydex, Plop a sommeil, choix Rush / Cozy, carte rouverte), l'écran de retour |
| `late` | fin de partie (Grand Splorch XII, tout possédé) : HUD et tous les panneaux |
| `huge` | très grands nombres : 1,2 M, 1,2 T, 987 Qa, 4,56 Dc, 999 Dc (dernier suffixe), 1,23e36 |
| `fx` | toutes les bannières, les messages les plus longs, les messages de célébration, les grands tampons et les textes flottants des effets, l'aperçu du Grand Splorch hors du ranch |

Les noms sont les plus longs possibles : joueurs de 20 caractères, nom d'espèce et de mutation les
plus longs de la langue, titre le plus long, nombres de 1e18 à 999 Dc.

## Comment ça marche

1. **`capture.luau`** (Lune) démarre le **vrai client** du jeu dans le harnais de test
   (`tests/harness/Screens.luau`), avec l'appareil et la langue choisis. Il lui envoie des messages
   « serveur » réalistes (profil du joueur, ranchs des 16 joueurs, bannières, célébrations, cartes,
   classements…) pour amener l'interface dans chaque état, ouvre chaque écran, calcule la mise en
   page (`tests/harness/Layout.luau`, mode fidèle : textes mesurés) et écrit un fichier JSON par
   écran (`tests/harness/ScreenDump.luau`). Il relie aussi chaque texte affiché à sa clé de
   traduction et mesure chaque clé dans les deux langues (`tests/harness/TextFitKeys.luau`).
2. **`render.mjs`** (Node + Playwright) ouvre Chromium, charge les **vraies polices** depuis Google
   Fonts et dessine chaque JSON avec les règles de Roblox (`renderer.js`). Il écrit l'image, le
   rapport et la planche contact.
3. **`metrics.mjs`** mesure dans le navigateur la largeur de chaque caractère des textes du jeu
   (anglais et français) et écrit `tests/harness/TextMetrics.luau`. C'est ce qui permet aux tests
   Lune de mesurer les textes sans navigateur. À relancer quand on ajoute des caractères nouveaux :
   `/opt/node22/bin/node tools/screens/metrics.mjs`.

Le harnais remplace aussi `TextService:GetTextSize` par la vraie mesure : le jeu, qui mesure le mot
le plus long de ses libellés (`Widgets.longestWord`), voit les mêmes largeurs que l'outil.

## Polices

| Police Roblox | Police utilisée ici | Remarque |
|---|---|---|
| FredokaOne | Fredoka One | la même police (titres, boutons, panneaux) |
| LuckiestGuy | Luckiest Guy | la même police |
| GothamBold (graisse 700) | **Montserrat 700** | Gotham n'est pas libre : Montserrat est la plus proche ; les largeurs diffèrent un peu |
| SourceSans, Arial (anciennes) | Source Sans 3, Arimo | seulement pour les textes jamais réglés |

**Taille du texte** : dans Roblox, `TextSize` est la **hauteur d'une ligne**, pas la taille CSS.
L'outil dessine donc une police CSS de `TextSize ÷ (hauteur de ligne de la police)`.

## Règles de Roblox reproduites

- **TextScaled** : la plus grande taille **entière** (au plus 100, et dans les bornes du
  `UITextSizeConstraint`) où le texte tient dans sa boîte. TextScaled active **toujours** les
  retours à la ligne, et un mot plus large que la boîte est **coupé entre deux lettres**.
- **TextWrapped** : retour à la ligne aux espaces, jamais à l'espace insécable.
- **TextTruncate** : la fin qui ne tient pas est remplacée par « … ».
- `UIScale` (cumulés), `UIPadding`, `UIListLayout`, `UIGridLayout`, tailles automatiques, découpe
  (`ClipsDescendants`), `UIStroke`, `UICorner`, `UIGradient` (sur un `CanvasGroup`, il teinte
  **tout** le groupe), transparences, `ZIndex`, `DisplayOrder`.
- Cadre blanc : objet **sélectionné** à la manette, comme le dessine le jeu. Pointillés roses :
  **zone sûre** (5 % de chaque côté, sur tous les écrans de ce jeu).
- Le monde 3D n'est pas dessiné : un ciel clair et de l'herbe le remplacent.

## Les problèmes cherchés

| Type | Signification |
|---|---|
| `overflow` | le texte ne tient pas dans sa boîte à la taille qu'utiliserait Roblox |
| `splitWord` | un mot est coupé en deux par le retour à la ligne (« Squishyde / x ») |
| `unitSplit` | une unité est séparée de son nombre (« toutes les 5 » / « s. ») |
| `clipped` | le texte est coupé par un parent |
| `truncated` | « … » coupe le texte (grave s'il cache un nombre ou un mot entier) |
| `small`, `smallFixed` | texte sous **28 px de référence × échelle de l'écran** (28 px réels en 1080p, 56 en 4K, 18,7 en 720p) |
| `orphan` | un « ! » ou un « ? » seul sur sa ligne |
| `offscreen`, `unsafe` | un objet sort de l'écran, ou de la zone sûre |
| `overlap` | deux textes ou deux boutons se chevauchent |
| `contrast` | contraste du texte sur son fond < 3 (le contour du texte compte) |
| `tinted` | texte teinté par le dégradé d'un `CanvasGroup` parent |
| `selection` | curseur de sélection invisible, hors de l'écran ou caché par un parent |
| `covered` | un message (toast) se dessine par-dessus le panneau ouvert |
| `empty`, `question`, `rawKey`, `placeholder`, `defaultText` | boîte visible vide, « ? » à la place d'une donnée, clé de traduction, `{variable}`, texte jamais posé |
| `noChange` | « 60 → 60 » : la flèche annonce un changement qui n'existe pas |
| `peek` | **information** : rangée entrouverte voulue en bas d'une liste (elle annonce la suite) |
| `capRisk` | **information** : voir « À vérifier sur une vraie console » |

## Les tests automatiques

- `tests/specs/TextFit_all.spec.luau` rejoue **tous** les écrans sur les 4 appareils et les 2
  langues, sans navigateur, et vérifie : pas de débordement, pas de mot coupé, pas d'unité séparée,
  pas de « … » qui cache un nombre ou un mot, pas de texte sous le minimum lisible, pas de
  ponctuation seule, pas de clé brute, de `{variable}`, de « ? » ni de texte jamais posé. Puis il
  mesure **chaque clé** de `Localization/Strings.luau`, en anglais et en français, dans chaque boîte
  où le jeu l'affiche (ou dans les boîtes de sa famille : toutes les clés `feedback.*` passent par
  l'emplacement de message, etc.).
- `tests/specs/Screens_display.spec.luau` vérifie sur les vrais écrans (TV 1080p et 720p, deux
  langues) : contraste ≥ 3, rien ne dépasse de sa fenêtre, curseur visible, aucune ligne coupée en
  deux par un parent, aucun texte teinté par un dégradé.

Les problèmes **déjà connus** sont listés : `tests/fixtures/TextFitPending.luau` (écrans, vide
aujourd'hui) et `tests/fixtures/TextFitKeysPending.luau` (clés utilisées par l'interface mais
jamais affichées par un scénario, chacune avec sa raison). Une clé que l'interface n'utilise pas
encore (clé du contrat pour un écran à venir, texte du serveur seul) est acceptée sans ligne : dès
qu'un écran l'utilise, la spec demande un scénario qui la montre, ou une raison. La spec **échoue** sur un problème nouveau (corriger l'interface, ne jamais
l'ajouter à la liste pour le cacher) et sur un problème réparé encore listé (retirer sa ligne). Une
raison écrite à la main dans la liste des clés est gardée quand on la régénère.

## À vérifier sur une vraie console

- **Bornes de TextScaled et UIScale** : l'outil suppose que `MinTextSize`, `MaxTextSize` et le
  plafond de 100 comptent **avant** l'agrandissement `UIScale` de UI/Root (×2 en 4K, ×0,667 en
  720p). Si Roblox les compte **après** (en pixels d'écran), presque tous les textes seraient deux
  fois plus petits en 4K (sous le minimum lisible) et beaucoup déborderaient en 720p et sur PC
  (`MinTextSize` 28 px d'écran > la boîte). Le type `capRisk` donne, pour chaque texte, la taille
  dans les deux cas ; `./tools/screens/run.sh --cap screen` dessine l'autre hypothèse. Une photo
  d'un écran en 4K et en 720p sur la vraie console tranche la question.
- **PreferredTextSize** (taille de texte choisie dans les réglages de Roblox) : le jeu ne la lit pas
  aujourd'hui ; l'outil ne la simule donc pas.
- Barre Roblox du haut : 58 px réservés partout (comme le harnais).

## Différences connues avec le vrai Roblox

- Mesure du texte : vraies polices dans Chromium, mais Gotham est remplacée par Montserrat ; les
  tests Lune ignorent le crénage : `summary.json` → `calibration` dit combien de tailles TextScaled
  Luau et navigateur diffèrent (en général 0, parfois 1 px).
- Pas de monde 3D, pas d'images réelles (cases neutres), pas d'animations : chaque capture est un
  instant figé.
- Polices de secours des symboles et emoji : Noto ici, celles de Roblox en jeu.
