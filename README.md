# Raise a Squishy

Jeu Roblox de type *tycoon*, **16 joueurs par serveur**, pensé d'abord pour la **console** : PS5 (manette DualSense sur une télé), puis Xbox, puis PC (clavier et souris).

À Wobbleton, chaque joueur élève des squishies en gelée qui grossissent tout seuls. On les presse pour faire jaillir des pièces, on achète des dalles qui construisent son ranch, on fusionne les jumeaux en géants. Toutes les 10 minutes, le **BOOP RUSH** fait éternuer les squishies chez les voisins : tout le serveur leur court après, et celui qui en attrape un gagne un bébé de cette créature. Personne ne perd jamais rien.

Tout le jeu est écrit en code (Luau + Rojo) : aucun travail dans Roblox Studio, aucun fichier image ou son téléversé.

---

## Sommaire

- [Plateformes](#plateformes)
- [Qualité : zéro bug](#qualité--zéro-bug)
- [Prérequis](#prérequis)
- [Construire le jeu](#construire-le-jeu)
- [Lancer les tests](#lancer-les-tests)
- [Organisation du dépôt](#organisation-du-dépôt)
- [Documentation](#documentation)
- [Publier](#publier)
- [Règles de contribution](#règles-de-contribution)

---

## Plateformes

| Ordre | Plateforme | Commandes |
|---|---|---|
| 1 | **PS5** (et PS4) | manette DualSense, glyphes PlayStation (✕ □ ○ △), vibrations |
| 2 | **Xbox** (Series et One) | manette Xbox, ses propres glyphes |
| 3 | **PC** | clavier et souris (E, Q, Maj, R, M), manette possible |

Pas de téléphone ni de tablette : le jeu n'a aucun code tactile.

Ce que cela veut dire pour l'interface :

- tout est dessiné pour une **télé à 3 m** : référence 1920 × 1080, vérifiée aussi en 4K (3840 × 2160) et en 720p ;
- **zone sûre de 5 %** sur chaque bord, texte de **28 px** au minimum ;
- chaque écran s'atteint avec **la croix, ✕ et ○ seulement** ; ○ revient toujours en arrière ;
- pas de fenêtre de chat sur console ;
- performances prévues pour les consoles les plus faibles (PS4, Xbox One).

## Qualité : zéro bug

Les règles du jeu sont robustes par construction :

- le serveur décide de tout ; les clients n'envoient que des intentions, toutes vérifiées et limitées en débit ;
- aucune règle ne dépend de la physique (pas de `Touched`, pas de fin d'animation) : le serveur mesure des distances et minute tout ;
- chaque état a un délai et une sortie ; `StreamingEnabled` est coupé ; chaque appel à un service Roblox est protégé ;
- **zéro trace** : une erreur ou un avertissement inattendu pendant un test fait échouer ce test.

Plus de 1 600 tests automatiques couvrent les 10 couches du plan qualité (règles pures, remotes hostiles, robot de longue durée, interface à la télé, économie, données, achats…).

## Prérequis

Outils listés dans `rokit.toml` :

| Outil | Version | Rôle |
|---|---|---|
| [Rojo](https://rojo.space) | 7.7.1 | construit la place `.rbxl` à partir de `src/` |
| [Lune](https://lune-org.github.io/docs) | 0.11.1 | lance les tests hors de Roblox |
| [Selene](https://kampfkarren.github.io/selene) | 0.31.0 | analyse le code (lint) |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | 2.6.0 | formate le code |

Installation : `rokit install` (ou placer les 4 binaires dans `~/.cargo/bin`).

## Construire le jeu

```bash
rojo build -o build/Game.rbxl          # place complète du jeu
lune run scripts/verify-place build/Game.rbxl   # vérifie les réglages de la place
```

Pour travailler dans Studio en direct : `rojo serve`, puis le plugin Rojo.

## Lancer les tests

```bash
./scripts/check.sh                     # porte complète : format, lint, tous les tests, build, place
lune run tests/run                     # tous les tests (environ 20 min)
lune run tests/run -- SquishyService   # seulement les specs dont le chemin contient ce mot
./scripts/soak.sh                      # robot de longue durée : 16 joueurs, 6 h simulées
stylua src tests                       # formater
selene src                             # lint : 0 erreur et 0 avertissement attendus
```

Tests importants :

| Spec | Ce qu'elle vérifie |
|---|---|
| `Boot.spec` | un serveur complet de 16 joueurs joue une vraie partie par les remotes |
| `Soak.spec` | 16 robots jouent 0,5 h (6 h avec `soak.sh`) ; aucun invariant cassé, aucune fuite |
| `ClientReplay.spec` | une partie du vrai serveur est rejouée dans le client complet, PS5 en 1080p, 4K et 720p, en anglais et en français, puis au clavier et à la souris |
| `EconomyPacing.spec` | le rythme de l'économie reste dans les tolérances du GDD |
| `RedTeam_*.spec`, `Remotes_*.spec` | charges hostiles sur chaque remote |

Les tests du vrai moteur Roblox (Open Cloud) sont décrits dans `tools/opencloud/README.md`.

## Organisation du dépôt

```
src/
  server/      services du serveur (données, ranch, économie, squishies, événements, poursuites…)
  client/      contrôleurs et interface (HUD, invites, panneaux, monde, sons)
  shared/      Config (tous les nombres), Logic (règles pures), Localization (EN et FR), Util
  first/       écran de chargement
tests/
  harness/     faux moteur Roblox pour Lune, joueurs simulés, audits télé et manette
  specs/       les tests
  sim/         simulation de l'économie
  engine/      tests qui tournent aussi dans le vrai moteur
scripts/       check.sh, soak.sh, prepublish, verify-place
tools/         Open Cloud et flux de travail
docs/          étude de marché, GDD, architecture, publication
```

## Documentation

| Document | Contenu |
|---|---|
| [docs/02-game-design-document.md](docs/02-game-design-document.md) | **GDD** : toutes les règles et tous les nombres du jeu (source de vérité) |
| [docs/04-architecture.md](docs/04-architecture.md) | architecture : paquets, services, réseau, données, console, anti-triche, plan de tests |
| [docs/05-guide-publication.md](docs/05-guide-publication.md) | guide de publication et tests manuels M1 à M18 (dont PS5 / PS4) |
| [docs/01-analyse-marche-tycoon.md](docs/01-analyse-marche-tycoon.md) | étude de marché des tycoons Roblox |
| [docs/03-decision-du-jury.md](docs/03-decision-du-jury.md) | choix du concept |
| [docs/08-etude-tycoons-2026.md](docs/08-etude-tycoons-2026.md), [docs/09-plan-contenu-complet.md](docs/09-plan-contenu-complet.md) | étude des meilleurs tycoons de 2026 et plan de contenu |
| `.claude/skills/*/SKILL.md` | règles de travail du studio (Luau, sécurité et données, interface, tests, game design) |

## Publier

1. `./scripts/check.sh` doit être vert de bout en bout.
2. `lune run scripts/prepublish` : refuse la publication si un identifiant de produit ou de passe manque, ou si les valeurs d'économie ne sont pas celles du GDD v1.3.
3. Suivre [docs/05-guide-publication.md](docs/05-guide-publication.md) : identifiants des sons et des produits, tests manuels sur une vraie PS5, une Xbox et un PC.

## Règles de contribution

- `--!strict` en haut de chaque module de `src/` ; commentaires en français, noms en anglais.
- Tous les textes du joueur passent par `Shared/Localization` (anglais **et** français) ; tous les nombres viennent de `Shared/Config`.
- Le temps passe par `Shared/Util/Clock` (les tests voyagent dans le temps).
- Un bug corrigé = un test qui échouait avant la correction. On ne supprime ni n'affaiblit jamais un test.

Statut : jeu complet en validation avant publication (tests automatiques verts ; tests manuels sur console à faire).
