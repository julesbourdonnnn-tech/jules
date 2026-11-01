# Captures d'écran hors moteur (tools/screens)

Cet outil fabrique de **vraies images** de l'interface de Comet Conga, sans Roblox Studio, et
**contrôle chaque texte** : est-ce qu'il tient dans sa boîte, est-ce qu'il est assez grand pour un
téléviseur, est-ce qu'il dépasse de l'écran, etc.

Il n'est **jamais livré** dans le jeu : Rojo ne prend que `src/` (`default.project.json` ne change
pas). Les aides de test sont dans `tests/harness/`.

## En une commande

```bash
./tools/screens/run.sh
```

Cela prend environ 6 minutes et produit, dans
`/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/cc-captures/`
(autre dossier : `--out <dossier>` ou variable `CC_CAPTURES`) :

| Fichier | Contenu |
|---|---|
| `index.html` | **planche contact** : toutes les vignettes, filtres par appareil, écran et type de problème |
| `<appareil>-<langue>/<écran>.png` | l'image à la taille réelle de l'écran (ex. 1920 × 1080) |
| `<appareil>-<langue>/<écran>.billboards.png` | les panneaux du monde (noms au-dessus des Nids…) à leur taille en pixels |
| `<appareil>-<langue>/<écran>.report.json` | les problèmes trouvés sur cet écran |
| `summary.json` | totaux par type, pires problèmes, problèmes regroupés (même objet sur tous les formats) |
| `json/` | les instantanés bruts (une description de chaque objet visible) |

Options utiles :

```bash
./tools/screens/run.sh --profiles tv1080 --langs fr --screens upgrades   # seulement Améliorer, TV, français
./tools/screens/run.sh --groups mid                                       # un seul groupe d'écrans
./tools/screens/run.sh --pending       # régénère aussi tests/fixtures/TextFitPending.luau
CC_CAPTURES=/tmp/mes-captures ./tools/screens/run.sh
```

Appareils (`--profiles`) : `tv1080`, `tv2160`, `tv720` (console, manette), `phone` (844 × 390,
tactile), `tablet` (1024 × 768, tactile), `pc` (1366 × 768, clavier-souris). Langues : `fr`, `en`.
Groupes (`--groups`) : `loading`, `new` (nouveau joueur), `mid` (milieu de partie, tous les panneaux
et onglets), `late` (niveaux au maximum), `huge` (1e6 à 1e30 de Glow et de Stardust), `fx` (toasts,
bannières, célébrations, tampons).

## Comment ça marche

1. **`capture.luau`** (Lune) démarre le **vrai client** du jeu dans le harnais de test
   (`tests/harness/Screens.luau`), avec l'appareil et la langue choisis. Il lui envoie des messages
   « serveur » réalistes (sauvegarde du joueur, mises à jour, bannières, célébrations, invitations…)
   pour amener l'interface dans chaque état, ouvre chaque écran, calcule la mise en page
   (`tests/harness/Layout.luau`, mode fidèle : textes mesurés) et écrit un fichier JSON par écran
   (`tests/harness/ScreenDump.luau`).
2. **`render.mjs`** (Node + Playwright) ouvre Chromium, charge les **vraies polices** depuis Google
   Fonts et dessine chaque JSON avec les règles de Roblox (`renderer.js`). Il écrit l'image, le
   rapport et la planche contact.
3. **`metrics.mjs`** mesure dans le navigateur la largeur de chaque caractère des textes du jeu
   (anglais et français) et écrit `tests/harness/TextMetrics.luau`. C'est ce qui permet aux tests
   Lune (`tests/harness/TextFit.luau`, `tests/specs/TextFit_all.spec.luau`) de mesurer les textes
   sans navigateur. À relancer quand on ajoute des caractères nouveaux :
   `node tools/screens/metrics.mjs`.

## Polices

| Police Roblox | Police utilisée ici | Remarque |
|---|---|---|
| FredokaOne | Fredoka One | la même police |
| LuckiestGuy | Luckiest Guy | la même police |
| GothamBold (GothamSSm, graisse 700) | **Montserrat 700** | Gotham n'est pas libre : Montserrat est la plus proche ; les largeurs diffèrent un peu |
| SourceSans, Arial (anciennes) | Source Sans 3, Arimo | seulement pour les textes jamais réglés |

Les symboles absents de ces polices (☺ ⚙ ✦ emoji…) passent par les polices Noto, comme Roblox qui a
aussi ses polices de secours (pas les mêmes dessins).

**Taille du texte** : dans Roblox, `TextSize` est la **hauteur d'une ligne**, pas la taille CSS.
L'outil dessine donc une police CSS de `TextSize ÷ (hauteur de ligne de la police)`.

## Règles de Roblox reproduites

- **TextScaled** : la plus grande taille **entière** (au plus 100, et dans les bornes du
  `UITextSizeConstraint`) où le texte tient dans sa boîte, en largeur et en hauteur. TextScaled
  active **toujours** les retours à la ligne (documentation Roblox de `TextLabel.TextScaled`).
- **TextWrapped** : retour à la ligne aux espaces (jamais à l'espace insécable) ; un mot trop long
  est coupé en deux (signalé).
- **TextTruncate AtEnd** : la fin qui ne tient pas est remplacée par « … ».
- Alignements, `LineHeight`, marges `UIPadding`, RichText simple (gras, italique, couleur, contour).
- `UIStroke` (contour du texte ou du cadre), `UICorner`, `UIGradient` (sur un `CanvasGroup`, il
  teinte **tout** le groupe, textes compris), transparences, `ZIndex`, `DisplayOrder`, découpe par
  `ClipsDescendants`, listes défilantes.
- Les images sont des **cases neutres** avec leur identifiant ; les icônes de manette PlayStation
  sont dessinées (✕ ○ □ △, L1, R2…).
- Pointillés roses : **zone sûre TV** (5 % de chaque côté). Cadre blanc : objet **sélectionné** à
  la manette, comme le dessine le jeu.
- Le monde 3D n'est pas dessiné : un ciel clair et de l'herbe le remplacent (c'est le pire cas pour
  lire un texte blanc sans fond).

## Les problèmes cherchés (rapport)

| Type | Signification |
|---|---|
| `overflow` | le texte ne tient pas dans sa boîte à la taille qu'utiliserait Roblox |
| `clipped` | le texte est coupé par un parent |
| `truncated` | « … » coupe le texte (`severe` : il cache un nombre ou un mot entier) |
| `small` | texte TextScaled plus petit que **18 px de référence × échelle de l'écran** (docs/07 : 27 px réels sur une TV 1080p) |
| `smallFixed` | même chose pour un texte de taille fixe |
| `splitWord` | un mot est coupé en deux par le retour à la ligne |
| `orphan` | un « ! » ou un « ? » se retrouve seul sur sa ligne |
| `offscreen` | un objet sort de l'écran |
| `unsafe` | (console) un texte ou un bouton sort de la zone sûre TV |
| `overlap` | deux textes, ou deux boutons, se chevauchent (ni parent ni enfant, sans fond opaque entre eux) |
| `contrast` | contraste du texte sur ce qui est dessiné derrière < 3 (le contour du texte compte) |
| `tinted` | la couleur d'un texte est assombrie par le dégradé d'un `CanvasGroup` parent |
| `empty`, `question`, `rawKey`, `placeholder`, `defaultText` | boîte visible vide, « ? » à la place d'une donnée, clé de traduction, `{variable}`, texte jamais réglé (Roblox afficherait « Label ») |
| `noChange` | « 60 → 60 places » : la flèche annonce un changement qui n'existe pas |
| `capRisk` | **information** : voir « À vérifier sur une vraie console » |

## Le test automatique

`tests/specs/TextFit_all.spec.luau` rejoue **tous** les écrans sur les 6 appareils et les 2
langues, sans navigateur (mesures de `TextMetrics.luau`), et vérifie : pas de débordement, pas de
« … » qui cache un nombre ou un mot entier, pas de TextScaled sous le minimum lisible, pas de mot
coupé, pas de ponctuation seule, pas de clé brute, de `{variable}`, de « ? » ni de texte jamais
réglé.

Les problèmes **déjà présents** sont listés dans `tests/fixtures/TextFitPending.luau` : la spec
saute ces écrans (ligne jaune « EN ATTENTE » avec la liste). Elle **échoue** :

- sur un problème **nouveau** (corriger l'interface, ne jamais l'ajouter à la liste pour le cacher) ;
- sur un problème **réparé** qui est encore listé : retirer sa ligne, la spec le vérifiera ensuite.

Pour refaire la liste après une série de corrections : `./tools/screens/run.sh --pending` (ou
`lune run tools/screens/capture -- --out /tmp/x --pending`), puis relire la différence avec git.

## Différences connues avec le vrai Roblox

- **Mesure du texte** : vraies polices dans Chromium, mais Gotham est remplacée par Montserrat ; les
  tests Lune ignorent le crénage (paires de lettres) : `summary.json` → `calibration` dit combien de
  tailles TextScaled Luau et navigateur diffèrent (en général de 0 ou 1 px).
- **À vérifier sur une vraie console** : l'outil suppose que les bornes de TextScaled
  (`MaxTextSize`, `MinTextSize` et le plafond de 100) comptent **avant** l'agrandissement `UIScale`
  (×1,5 sur une TV 1080p), comme le prévoit docs/07. Si Roblox les compte **après**, presque tous
  les textes sont 1,5 fois plus petits sur TV. Le type `capRisk` donne, pour chaque texte, la taille
  dans les deux cas ; `node tools/screens/render.mjs --in <json> --out <dossier> --cap screen`
  dessine l'autre hypothèse. Comparer avec une photo de la TV tranche la question.
- Barre Roblox du haut : 58 px réservés sur tous les appareils (comme le harnais) ; sur console, la
  vraie valeur peut être différente.
- Pas de monde 3D, pas d'images réelles (cases neutres), pas d'animations : chaque capture est un
  instant figé (les effets en cours d'animation sont pris à mi-chemin).
- Polices de secours des symboles et emoji : Noto ici, celles de Roblox en jeu.
- Contour `UIStroke` d'un `CanvasGroup` dessiné par-dessus le groupe ; rotation et découpe :
  approximation (rectangle de découpe tourné avec l'objet).
- Retour à la ligne : même règle que Roblox pour les espaces, mais l'algorithme exact de Roblox
  (césure des mots très longs) peut différer d'un caractère.
