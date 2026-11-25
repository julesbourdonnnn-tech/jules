---
name: ns-commis-veille
description: Mission quotidienne des commis de Nuits Singulières (nuitsinguliere.com) - vérifier les établissements du site (fermetures, réouvertures, nouveautés, offres, événements) et publier les informations confirmées sur les fiches. Utiliser pour toute session de veille des établissements, déclenchée par la tâche planifiée quotidienne ou à la demande de Jules. Ne concerne pas maisons/ ni le-passe/.
---

# Commis de veille : garder les fiches à jour

Les lecteurs choisissent leur nuit sur Nuits Singulières : chaque fiche doit dire la vérité **aujourd'hui**. Ta mission est de vérifier un lot d'établissements par jour et de publier ce qui a changé.

**Budget : une heure maximum par jour.** Au bout de 50 minutes, arrête la recherche, publie ce qui est prêt et fais le compte rendu.

Jules a donné son accord explicite (25 novembre 2026) : les commis **publient directement** les informations confirmées, selon les règles ci-dessous, et lui envoient un compte rendu chaque jour. Lis aussi la compétence `ns-gestion-site` (règles de publication).

## 1. Préparer

```bash
cd /home/user/jules   # ou la racine du dépôt
git fetch origin claude/french-hotels-marketplace-vqleii claude/gifted-ritchie-r1ffn4
git checkout claude/french-hotels-marketplace-vqleii && git merge --ff-only origin/claude/french-hotels-marketplace-vqleii
node scripts/veille.js lot 10      # les 10 établissements les moins récemment vérifiés
```

## 2. Vérifier chaque établissement (environ 4 minutes chacun)

Pour chacun, cherche sur le web (recherche web, en français) :
- **Le site officiel** (champ `website`) : bandeau de fermeture, dates d'ouverture saisonnière, actualités, offres, nouvelles chambres, nouveau chef ou restaurant.
  Si l'outil WebFetch (ou un agent web-fetch) est disponible, ouvre la page d'accueil et la page « infos pratiques » du site officiel. Sinon, **un résultat de recherche qui provient du domaine officiel de l'établissement compte comme source officielle** (cite l'URL de cette page).
- Fais **au moins 2 ou 3 recherches par établissement** (fermeture, saison/ouverture, nouveautés ou offres) : une seule recherche ne suffit pas.
- **Les actualités récentes** : `"<nom>" <ville> fermeture`, `"<nom>" réouverture`, `"<nom>" nouveauté 2026`, `"<nom>" offre`.
- La presse locale, l'office de tourisme, le guide Michelin, Relais & Châteaux.

Ce qu'on cherche, par ordre d'importance :
1. **Fermeture** (travaux, saison, définitive) ou **réouverture**.
2. **Nouveauté** utile au lecteur : nouvelle chambre ou cabane, spa, restaurant, distinction (étoile, clé Michelin), changement d'accès.
3. **Offre en cours** sur le site officiel (avec date de fin) ou **événement** (marché de Noël, soirée, saison de ski).
4. Une info pratique qui a changé (animaux, accès en train, âge minimum).

## 3. Règles de fiabilité (non négociables)

- Une information n'est publiée que si elle vient du **site officiel de l'établissement** ou de **deux sources fiables et indépendantes** (presse, office de tourisme, Michelin). Les sites de réservation (Booking, Expedia, lastminute…) servent d'indice, jamais de preuve seule.
- **Jamais d'invention**, jamais de supposition, jamais de prix précis inventé. Dans le doute, ne publie pas et signale-le dans le compte rendu.
- Une **offre** a toujours une date de fin (`until`). Sans date de fin connue, mets au plus 30 jours.
- Les informations datées de plus de 12 mois ne sont pas des actualités.
- Ne touche jamais aux avis testés (`review`), aux notes, au coup de cœur, aux photos, aux textes de présentation, ni aux dossiers `maisons/` et `le-passe/`.

## 4. Enregistrer

**Dans `data/veille.json`**, pour chaque établissement vérifié (même sans nouveauté) :

```json
"phare-de-kerbel": {
  "checked": "2026-11-25",
  "news": [
    { "date": "2026-11-25", "type": "offre", "text": "Phrase claire, 15 à 240 caractères, sans HTML.", "source": "https://…", "until": "2026-12-20" }
  ]
}
```
- `checked` : la date du jour, toujours mise à jour.
- `type` : `fermeture`, `reouverture`, `nouveaute`, `offre`, `evenement` ou `info`.
- `text` : une phrase utile au lecteur, au présent, sans superlatif ni promotion (« L'hôtel propose -15 % sur les nuits en semaine en décembre, en réservant sur son site. »).
- Garde les actualités encore valables ; supprime celles qui sont dépassées ou démenties.

**Fermeture ou réouverture** : modifie aussi `js/hotels.js`.
- Fermeture temporaire : ajoute dans la fiche `closed: { until: "AAAA-MM-JJ", label: "Fermé pour travaux jusqu'au …", note: "Phrase avec la source et les dates." }`. Le lieu sort des listes et des guides, sa fiche affiche un bandeau, et il revient seul à la date indiquée.
- Fermeture définitive confirmée par deux sources : `closed: { label: "Fermé définitivement", note: "…" }` (sans `until`), et signale-le à Jules en tête du compte rendu.
- Réouverture confirmée : retire le champ `closed`.
- **Fermeture saisonnière** (ex. cabanes fermées l'hiver, refuge fermé hors saison) : c'est une information essentielle pour le lecteur, **publie-la** dès que le site officiel donne les dates de saison, en actualité `fermeture` (« Fermé pour l'hiver depuis le … ; réouverture le … » ou « dates 2027 pas encore annoncées »), avec `until` si la date de réouverture est connue. Pas de champ `closed` : le lieu reste dans les listes.

## 5. Contrôler et publier

```bash
node scripts/veille.js verifier     # doit afficher ✓
node scripts/build.js               # régénère les fiches
git add -A data/veille.json js/hotels.js hotels guides index.html sitemap.xml robots.txt data/lastmod.json
git commit -m "Veille du <date> : <n> établissements vérifiés"   # terminer par les lignes d'attribution demandées
git fetch origin claude/french-hotels-marketplace-vqleii claude/gifted-ritchie-r1ffn4
git rebase origin/claude/french-hotels-marketplace-vqleii           # si des robots ont poussé entre-temps
# les deux branches distantes doivent pointer sur le même commit (le parent du tien) ; sinon, n'insiste pas et signale-le
git push --atomic origin HEAD:refs/heads/claude/french-hotels-marketplace-vqleii HEAD:refs/heads/claude/gifted-ritchie-r1ffn4
```
Ne réécris jamais l'historique distant, ne force jamais. Réessaie jusqu'à 4 fois en cas d'erreur réseau. S'il n'y a rien de nouveau, publie quand même les dates `checked` (c'est ce qui affiche « Informations vérifiées le … » sur les fiches).

## 6. Compte rendu pour Jules (en français simple, court)

```
Veille du 25 novembre : 10 établissements vérifiés.
⚠️ À savoir : … (fermetures, informations douteuses à trancher par Jules)
Publié : • Phare de Kerbel : offre -15 % en semaine jusqu'au 20 décembre (site officiel)
Rien de nouveau : Alpinest, Auberge Saint-Pierre, …
Prochain lot : …
```
Termine par ce que tu n'as pas pu vérifier (site injoignable, source unique) pour que Jules décide.
