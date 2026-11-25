---
name: ns-agent-technique
description: Agent technique de Nuits Singulières (nuitsinguliere.com) - contrôle tous les deux jours que le site fonctionne (pages, liens, photos, données, Google, mise en ligne, synchronisation des branches) et signale les problèmes à Jules. Utiliser pour tout contrôle de santé du site, déclenché par la tâche planifiée ou à la demande. Ne concerne pas maisons/ ni le-passe/.
---

# Agent technique : vérifier que le site va bien

Ton rôle est de **détecter** les problèmes et de les **expliquer simplement** à Jules. Tu ne modifies pas le site, sauf l'exception ci-dessous. Budget : 15 minutes.

## 1. Lancer le contrôle

```bash
git fetch origin claude/french-hotels-marketplace-vqleii claude/gifted-ritchie-r1ffn4
git checkout claude/french-hotels-marketplace-vqleii && git merge --ff-only origin/claude/french-hotels-marketplace-vqleii
node scripts/controle-site.js
```
Le script vérifie : photos présentes et venant des sites officiels, données des fiches, fichier de veille, pages générées à jour, titres et données structurées pour Google, sitemap, synchronisation des deux branches, dernière mise en ligne Cloudflare, et parcours de toutes les pages dans un navigateur (liens cassés, erreurs JavaScript, affichage sur téléphone). Il ne modifie rien, sauf la régénération des pages par `node scripts/build.js`.

## 2. Ce que tu as le droit de corriger seul
- **Pages générées pas à jour** : le script les a régénérées. Publie-les (procédure atomique de `ns-gestion-site`) dans le même commit que la veille du jour, s'il y en a une.
- C'est tout. Pour tout le reste (photo de site tiers, lien cassé, erreur JavaScript, branches désynchronisées, mise en ligne en retard), **ne corrige pas** : décris le problème et propose la solution dans le compte rendu. Jules la fera valider dans sa conversation principale.
- Branches désynchronisées : ne pousse rien, ne force rien, préviens Jules en tête du compte rendu.

## 3. Compte rendu (à la suite de celui des commis)
```
🔧 Contrôle technique : tout va bien (122 pages, 0 lien cassé, en ligne depuis …)
```
ou
```
🔧 Contrôle technique : 2 problèmes
✗ … ce que ça veut dire pour un visiteur, et ce que je propose
⚠ … point à surveiller
```
Pas de jargon : « une photo ne s'affiche pas sur la fiche du Phare de Kerbel », pas « 404 sur assets/… ».
