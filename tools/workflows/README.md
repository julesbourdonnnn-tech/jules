# Recettes de fabrication (workflows Claude Code)

Ce dossier contient les scripts qui ont servi à fabriquer Comet Conga avec Claude Code.
Chaque script fait travailler plusieurs agents à la suite : recherche, fabrication, relecture, correction, sauvegarde.
Ils ne font pas partie du jeu : Rojo ne les met pas dans `Game.rbxl`, et `./scripts/check.sh` ne les vérifie pas.

| Fichier | À quoi il a servi |
|---|---|
| `1-etude-marche-et-gdd.js` | Étude du marché Roblox, 3 concepts, vote d'un jury, puis le document de conception (GDD) |
| `2-fabrication-du-jeu.js` | Architecture, puis 6 lots de code fabriqués en parallèle, chacun relu par un autre agent, puis intégration et premiers tours de QA |
| `3-qa-et-polissage.js` | Tours de QA (sécurité, données, robustesse, expérience joueur), corrections, validation complète |
| `4-finition-anti-triche-sons.js` | Contre-audit anti-triche indépendant, sons officiels Roblox, restes des tours 3 et 4, QA tours 5 et 6, documentation finale |
| `5-etude-marche-tycoon.js` | Étude des tendances pour le prochain jeu (un tycoon) : 5 angles de recherche, synthèse, 3 concepts, 3 juges |

## Les réutiliser

1. Copier le script voulu et adapter en haut du fichier le dossier du projet (`ROOT`), la branche Git et les noms de fichiers.
2. Le lancer depuis Claude Code avec l'outil Workflow (`scriptPath`).
3. Les lignes d'attribution des commits se passent dans `args.attribution`. Sinon, les commits n'ont pas de lignes d'attribution.

Les chemins vers le dossier temporaire de la session d'origine (`/tmp/claude-0/...`) sont à remplacer, car ce dossier disparaît à la fin de chaque session.
