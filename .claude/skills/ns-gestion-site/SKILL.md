---
name: ns-gestion-site
description: Créateur et gestionnaire du site Nuits Singulières (nuitsinguliere.com, racine du dépôt julesbourdonnnn-tech/jules). Utiliser pour toute modification du site : ajouter ou modifier un hôtel, un guide, une page, le design, les photos, la newsletter, les statistiques, le référencement, puis vérifier et publier en ligne. Contient les règles de publication à respecter absolument.
---

# Gérer et publier Nuits Singulières

## Règles absolues

- **Ne jamais toucher** aux dossiers `maisons/` (site Sable & Pierre) ni `le-passe/` (autre site). Ils sont gérés ailleurs.
- **Ne rien pousser sans l'accord de Jules.** Il n'est pas technique : tout expliquer simplement, en français.
- La branche par défaut est `claude/french-hotels-marketplace-vqleii`. Des robots y poussent toutes les 4 h les données de Sable & Pierre et les recopient sur `claude/gifted-ritchie-r1ffn4`. **Ne jamais réécrire l'historique** et toujours pousser **le même commit sur les deux branches en une seule opération atomique**.
- Ne jamais transmettre les adresses e-mail privées de Jules ni la clé d'administration à un service extérieur.

## Comment le site est fait

- Site statique généré par `node scripts/build.js` à partir de `js/hotels.js` (fiches), `js/guides.js` (guides), `js/core.js` (fonctions communes), `js/config.js` (réglages). Il produit `hotels/*.html`, `guides/*.html`, `sitemap.xml`, `robots.txt`, `data/lastmod.json` : toujours relancer le build et enregistrer ces fichiers.
- Pages écrites à la main : `index.html`, `a-propos.html`, `professionnels.html`, `carte.html`, `quiz.html`, `liens.html`, `mentions-legales.html`, `signature.html`… Styles dans `css/style.css`, scripts dans `js/app.js` et `js/common.js`.
- Hébergement : Worker Cloudflare « jules » (`wrangler.jsonc`), déployé automatiquement à chaque poussée sur la branche par défaut. `worker/index.js` gère `/api/*` : newsletter (KV), statistiques sans cookie (D1), questions des lecteurs, comptes lecteurs pour retrouver ses favoris (`/api/compte…`, tables D1 `accounts` et `sessions`, page `compte.html`), page d'administration (mot de passe provisoire pour un lecteur qui a oublié le sien). Les fichiers internes à ne pas publier sont listés dans `.assetsignore` (y ajouter tout nouveau dossier interne).
- Un hôtel sans photo n'est pas affiché. Photos officielles : ajouter l'hôtel dans `data/photo-sources.json` et pousser ; l'Action GitHub « Photos » crée une planche `_review/<id>.jpg` ; choisir les numéros dans `data/photo-selection.json` et pousser ; l'Action télécharge `assets/hotels/<id>/N.jpg`. Toujours avoir l'autorisation de l'hôtel (ou utiliser les photos de Jules avec `photoCredit`).
- **Photos : uniquement le site officiel de l'établissement** dans `data/photo-sources.json` (jamais un blog, un concurrent comme hotels-insolites.com, un office de tourisme, Booking ou Michelin). Vérifier `assets/hotels/<id>/source.json` après chaque téléchargement. Une sélection peut lister des URL exactes au lieu de numéros.
- **Agents** (conversation « Agents · Nuits Singulières ») : commis de veille (`ns-commis-veille`) et agent technique (`ns-agent-technique`, outil `node scripts/controle-site.js`) tous les deux jours ; éclaireur (`ns-eclaireur`) une fois par mois pour 1 à 3 nouveaux établissements choisis par Jules.
- **Veille des établissements** : `data/veille.json` (date de vérification et actualités affichées sur les fiches), outil `node scripts/veille.js lot|verifier|etat`, mission décrite dans la compétence `ns-commis-veille` (commis quotidiens, publication directe autorisée par Jules selon des règles strictes).
- **Fermeture temporaire** : champ `closed: { until, label, note }` dans `js/hotels.js`. La fiche reste en ligne avec un bandeau, le lieu sort des listes et des guides jusqu'à la date. Vérifier chaque trimestre que les lieux sont ouverts.
- Le réseau de l'environnement bloque nuitsinguliere.com, booking.com et la plupart des sites d'hôtels : utiliser la recherche web pour les faits, l'Action GitHub pour les photos.

## Vérifier avant de publier

1. `node scripts/build.js` (doit afficher le nombre de fiches et de guides, sans erreur).
2. Contrôle des liens et des erreurs JavaScript : un script Playwright qui parcourt les pages en `file://` (le serveur http local est refusé). Ignorer les fausses alertes propres au `file://` (chemins absolus de 404.html, listing du dossier racine).
3. Captures Playwright des pages modifiées en 1280 px et 390 px ; vérifier qu'il n'y a pas de débordement horizontal sur téléphone.
4. Montrer le résultat à Jules (captures) quand le changement est visible.

## Publier (après accord de Jules)

```bash
git add -A && git commit -m "…"   # terminer le message par les lignes d'attribution demandées
git fetch origin claude/french-hotels-marketplace-vqleii claude/gifted-ritchie-r1ffn4
# vérifier que les deux branches distantes sont égales au parent du commit (HEAD~1) ; sinon, rebaser sans réécrire l'historique distant
git push --atomic origin HEAD:refs/heads/claude/french-hotels-marketplace-vqleii HEAD:refs/heads/claude/gifted-ritchie-r1ffn4
```
Réessayer jusqu'à 4 fois en cas d'erreur réseau. Puis confirmer le déploiement : une nouvelle version doit apparaître sur `https://api.cloudflare.com/client/v4/accounts/afc5e1bdc37caf08c7d8e2411f0aec83/workers/scripts/jules/versions`.

## Bonnes pratiques de créateur de site

- **Mobile d'abord** : la majorité des visiteurs viennent d'Instagram sur téléphone.
- **Vitesse** : images en `N.jpg` + `N-sm.jpg`, chargement différé, pas de bibliothèque lourde.
- **Accessibilité** : textes alternatifs, contrastes suffisants, boutons de 44 px minimum.
- **Référencement** : une page par hôtel et par guide, titres et descriptions uniques, données structurées (Hotel, Review, WebSite, Organization) déjà générées par le build, sitemap à jour, Google Search Console.
- **Cohérence** : réutiliser les composants et variables CSS existants (`--forest`, `--terracotta`, `--gold`, `--serif`…) plutôt que d'en créer de nouveaux.
- **Indépendance** : aucun lien d'affiliation, bouton « Réserver en direct » vers le site officiel, mentions légales à jour.
- Pour les textes, suivre les compétences ns-ecriture-blog et ns-avis-hotel.
