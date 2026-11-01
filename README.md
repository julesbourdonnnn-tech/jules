# Comet Conga

> Projet Roblox professionnel, entièrement en code (Luau + Rojo) : monde, interface et effets sont générés par script. Aucun asset externe n'est requis.

> **Attrape des bébés comètes, mène la plus longue conga lumineuse du ciel… et ne te fais pas couper !**

Sur **Lumora**, une île flottante au crépuscule, des bébés comètes (les **Nebbies**) tombent du ciel. Marche dessus : ils te suivent en file lumineuse. Ramène la plus longue conga possible jusqu'à ton **Nid** pour gagner du Glow, pendant que les 11 autres joueurs essaient de te la couper (« SNIP ! »).

| | |
|---|---|
| **Genre** | Collection + revenu passif + améliorations + renaissance, avec course-poursuite non violente et événements de serveur coopératifs |
| **Joueurs** | 12 par serveur, mobile d'abord (joystick + un seul bouton : Dash) |
| **Boucle** | Attraper → Conga (bonus ×1,08 par Nebby, jusqu'à ×5) → Parade au Nid → Progresser (5 améliorations, Starforge, Supernova) |
| **Rythme commun** | Météo à mutation toutes les 6 min · Grande Comète toutes les 10 min · Nuit de la Balise (trêve coopérative) toutes les 30 min · Starfall Saturday chaque samedi 16:00 UTC |
| **Équité** | Le Nid n'est jamais pillable, le Lead Trio ne se coupe jamais, bouclier débutant, Mode Zen, monétisation 100 % déterministe |
| **Collection** | 30 espèces au lancement (36 prévues), formes météo, variantes Doré/Géant/Starborn, Star Atlas, fusions ★1 → ★5 |

Le choix du concept vient d'une étude de marché Roblox 2025-2026 et d'un jury de 3 concepts concurrents : voir les documents ci-dessous.

## État du projet (31 octobre 2026)

| | |
|---|---|
| **Jouable sur** | Téléphone et tablette (tactile), ordinateur (clavier-souris), **PlayStation 5** et Xbox (manette, interface adaptée au téléviseur) |
| **Langues** | Français et anglais, choisis automatiquement (ou dans Réglages) |
| **Vérification** | `./scripts/check.sh` vert : **1 619 tests automatiques** (112 fichiers), 0 échec ; 0 erreur et 0 avertissement d'analyse |
| **Fait** | Version 1.0 du GDD complète, 4 tours de QA (sécurité, données, robustesse, expérience joueur, conformité, bonnes pratiques Roblox) |
| **Reste à faire à la main avant de publier** | Créer les 6 passes et 6 produits dans le Creator Hub et coller leurs numéros ; administrateurs et date du premier Starfall Saturday ; écouter les sons et la musique (d'abord les neuf « à confirmer à l'écoute ») ; questionnaire de maturité, icône, miniatures ; tests dans Roblox Studio (rendu, physique, vraies sauvegardes et vrais achats, 12 vrais joueurs, téléphone modeste) et essai sur une vraie PS5 ; répondre à 7 questions de design |

Détails : [guide de publication](docs/05-guide-publication.md) · [rapport qualité](docs/06-rapport-qualite.md) · [console PS5](docs/07-console-ps5.md).

## Documents

| Document | Contenu |
|----------|---------|
| [`docs/01-analyse-marche.md`](docs/01-analyse-marche.md) | Étude du marché Roblox 2025-2026 : jeux à succès, tendances, algorithme, monétisation, audience, sources |
| [`docs/02-game-design-document.md`](docs/02-game-design-document.md) | Game Design Document complet (règles, chiffres, monde, UI, architecture) |
| [`docs/03-decision-du-jury.md`](docs/03-decision-du-jury.md) | Les 3 concepts étudiés, les notes et les raisons du choix |
| [`docs/04-architecture.md`](docs/04-architecture.md) | Contrat technique : modules, API, réseau, données |
| [`docs/05-guide-publication.md`](docs/05-guide-publication.md) | **Guide pas à pas** du dépôt au jeu publié : outils, Studio, passes et produits, réglages, maturité, page du jeu, PS5, check-lists avant et après le lancement |
| [`docs/06-rapport-qualite.md`](docs/06-rapport-qualite.md) | Rapport qualité : résultat des tests, méthode, ce qui reste à vérifier dans Studio (plan de test), résultats de QA, questions de design ouvertes |
| [`docs/07-console-ps5.md`](docs/07-console-ps5.md) | Console PS5 / téléviseur : correspondance DualSense, échelle 10 pieds, zone sûre, glyphes, navigation, vibrations, chat, tests |

## Démarrer en 5 minutes

1. Installer **Roblox Studio** (site de Roblox, page *Create*) et [Rokit](https://github.com/rojo-rbx/rokit), puis dans ce dossier : `rokit install` (installe Rojo, Selene, StyLua, Lune aux versions de `rokit.toml`).
2. Vérifier : `./scripts/check.sh` doit finir par « ✅ Tout est vert. ».
3. Construire le jeu : `rojo build -o build/Game.rbxl`
4. Double-cliquer sur `build/Game.rbxl` pour l'ouvrir dans **Roblox Studio**, puis **Play**. Pour jouer à plusieurs : onglet *Test*, *Local Server*, 2 à 4 joueurs.

Pour développer en direct : `rojo serve`, puis, dans Studio, ouvrir le plugin Rojo (`rojo plugin install`) et cliquer sur *Connect*.

Publier le jeu : suivre le [guide de publication](docs/05-guide-publication.md) (résumé pour Claude : skill [`roblox-publish`](.claude/skills/roblox-publish/SKILL.md)).

## Vérifier la qualité

```bash
./scripts/check.sh
```

Le script enchaîne cinq vérifications :
1. formatage (StyLua) ;
2. lint (Selene) ;
3. tests automatisés (Lune) ;
4. build Rojo ;
5. contrôle de l'intégrité du fichier `.rbxl`.

Les tests tournent **hors de Roblox**. Le harnais `tests/harness/` simule le moteur : `require` façon Rojo, joueurs, DataStore avec pannes injectables, achats et remotes. On peut ainsi tester la logique serveur et client, la sauvegarde et les tentatives de triche à chaque commit.

## Structure

```
src/
  first/    → ReplicatedFirst                (écran de chargement)
  shared/   → ReplicatedStorage.Shared       (config, textes EN/FR, réseau, utilitaires)
  server/   → ServerScriptService.Server     (services serveur : autorité sur tout)
  client/   → StarterPlayerScripts.Client    (interface, effets, contrôles)
tests/
  harness/  → simulateur Roblox pour Lune
  specs/    → tests (*.spec.luau)
  sim/      → simulation du rythme de l'économie
docs/       → marché, GDD, jury, architecture, publication, qualité, console
.claude/skills/ → savoir-faire Roblox réutilisable par Claude
```

## Skills Claude du projet

| Skill | Quand |
|-------|-------|
| `roblox-luau-engineering` | écrire ou modifier du code Luau |
| `roblox-security-datastore` | remotes, économie, sauvegarde, achats |
| `roblox-ui-juice` | interface, animations, effets |
| `roblox-qa-testing` | tests, chasse aux bugs, revue |
| `roblox-game-design` | équilibrage, contenu, événements, prix |
| `roblox-publish` | build, Studio, publication, lancement |

Le plugin **roblox-dev** de l'Anthropic Directory complète ces skills.
