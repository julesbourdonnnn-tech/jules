# Sable & Pierre — les maisons de Lacanau et Bordeaux

Site de présentation et de réservation de deux maisons de famille en Gironde :

- **La Maison du Lac** — Lacanau, Le Moutchic : 12 voyageurs, 6 chambres, piscine privée, lac à 50 m, océan à 10 min ([annonce Airbnb](https://www.airbnb.fr/rooms/662061426615418606))
- **La Maison de Pierre** — Bordeaux : 8 voyageurs, 5 chambres, pierre de taille, verrière et terrasse, hypercentre à 10 min à pied ([annonce Airbnb](https://www.airbnb.fr/rooms/50226249))

Comme les autres sites du dépôt, il est **100 % statique** (HTML, CSS, JavaScript), sans base de données, et se modifie avec un simple éditeur de texte.

## ✅ À faire avant de mettre en ligne

1. **Ton e-mail** dans `js/config.js` (`email`) : c'est là qu'arrivent les demandes de réservation directe. Il est provisoirement réglé sur `contact@nuitsinguliere.com`.
2. **Téléphone, WhatsApp, Instagram** dans `js/config.js` (facultatif : laissés vides, ils ne s'affichent pas).
3. **Le nom du site** : « Sable & Pierre » (le sable de Lacanau, la pierre blonde de Bordeaux) et les noms des maisons (« la Maison du Lac », « la Maison de Pierre ») sont des propositions. Pour les changer : `js/config.js`, `js/data.js` (champ `name`) et les titres des fichiers `.html`.
4. **Les disponibilités en direct** (fortement conseillé, voir plus bas) : 5 minutes de réglage.

## Ce que contient le site

| Page | Contenu |
|---|---|
| `index.html` | Accueil : écran partagé « l'océan / la ville », **recherche de dates** qui vérifie en direct les disponibilités des deux maisons (et propose la prochaine date libre), présentation des maisons, galerie à faire glisser, les environs avec la météo en direct, **« Quand venir ? »** (climat mois par mois), comparateur, avis, questions fréquentes |
| `lacanau.html`, `bordeaux.html` | Fiche complète : diaporama, description de l'annonce, **plan niveau par niveau**, mosaïque et **visite photo pièce par pièce**, chambres, équipements, **avis détaillés** (notes par critère, répartition, sujets cités), **calendrier des disponibilités réelles**, carte du quartier avec **repères et distances**, climat, règlement, bouton de partage |
| `mentions-legales.html` | Mentions légales et données personnelles |
| `404.html` | Page d'erreur |

Détails : polices hébergées sur le site, aucun cookie, accessible au clavier et aux lecteurs d'écran (audit automatique sans erreur), compatible avec les anciens Safari, animations désactivées si le visiteur le demande, barre « Réserver » qui suit la lecture, **images de partage** soignées pour WhatsApp, Messages et Facebook, icône pour l'écran d'accueil du téléphone, données structurées Google (`VacationRental`).

### Comment on réserve

Sur chaque fiche, le visiteur choisit ses dates dans le calendrier (les nuits déjà prises sont grisées, la durée minimale de séjour est respectée, les prochains week-ends libres sont proposés en un clic) et le nombre de voyageurs, puis :

- **« Voir le prix et réserver »** ouvre l'annonce Airbnb **avec les dates et les voyageurs déjà remplis** : il voit le prix exact et réserve avec le paiement sécurisé d'Airbnb.
- **« Demande de réservation directe »** : un formulaire (nom, e-mail, téléphone, message) qui t'envoie la demande avec les dates. Sans réglage, il ouvre un e-mail pré-rempli chez le visiteur ; avec le stockage activé (voir plus bas), la demande arrive directement et sonne sur ton téléphone.

Les dates choisies sont gardées pendant la visite, et une adresse comme `bordeaux.html?arrivee=2026-12-24&depart=2026-12-27&voyageurs=6` pré-remplit le calendrier (pratique à envoyer à quelqu'un).

### Afficher un prix « à partir de »

Airbnb ne permet pas de lire les prix automatiquement. Si tu veux afficher un prix indicatif (« À partir de 450 € la nuit ») sur la fiche, dans la réservation et sur l'accueil, renseigne `priceFrom` pour chaque maison dans `js/data.js` (par exemple `priceFrom: 450,`). Laisse `null` pour ne rien afficher.

## Ce qui se met à jour tout seul

La GitHub Action **« Maisons — données »** (`.github/workflows/maisons-donnees.yml`) tourne toutes les 4 heures, une fois la branche fusionnée dans `main` :

- **Disponibilités** (`scripts/disponibilites.py` → `js/disponibilites.js`) : pour les 12 prochains mois, les nuits libres, les jours d'arrivée et de départ possibles et la durée minimale de séjour, lus dans le calendrier Airbnb de chaque annonce. **Rien à régler.** Quand tu bloques des dates sur Airbnb, le site suit dans les 4 heures.
- **Climat** (`scripts/climat.py` → `js/climat.js`) : moyennes 2015–2024 (températures, jours de pluie, température de l'océan à Lacanau), calculées une fois à partir des archives Open-Meteo. Pour les recalculer : Actions → « Maisons — données » → Run workflow → climat = oui.

## D'où viennent les textes et les photos

Tout vient **des deux annonces Airbnb**, sans rien inventer :

- La GitHub Action **« Maisons — photos Airbnb »** (`.github/workflows/maisons-airbnb.yml`, script `scripts/airbnb.py`) télécharge les annonces, les **27 photos de chaque maison** (en trois tailles, au format WebP, bandes noires des captures d'écran retirées) et les avis des voyageurs. Résultats : `assets/photos/`, `data/airbnb/<maison>.json` (détail de l'annonce) et `data/airbnb/raw/<maison>-reviews.json` (avis).
- Les textes affichés sont dans **`js/data.js`** : description de l'annonce (mot pour mot), chambres, équipements, règlement, notes, ordre et légendes des photos, avis cités. Les informations sur les environs (`DESTINATIONS`) sont des informations générales, avec des temps de trajet indicatifs.

**Si tu modifies une annonce sur Airbnb** (nouvelles photos, nouvel équipement…) : GitHub → Actions → « Maisons — photos Airbnb » → *Run workflow*. Puis mets à jour `js/data.js` (par exemple ajoute la nouvelle photo dans la liste `photos`). Pour retélécharger des photos déjà présentes, supprime d'abord les fichiers `assets/photos/<maison>/NN-*.webp` correspondants.

## Mise en ligne (Cloudflare)

Le site a **son propre Worker Cloudflare, « lacanau »**, séparé de Nuits Singulières et du Passe (le dossier `maisons/` est exclu de nuitsinguliere.com par le `.assetsignore` à la racine).

- **Recommandé (comme pour les autres sites)** : Cloudflare → Workers & Pages → Créer → Importer un dépôt Git → `jules`, puis dans les réglages de build : **répertoire racine = `maisons`**, commande de déploiement `npx wrangler deploy`. Cloudflare publie le site à chaque modification.
- **Autre option** : la GitHub Action « Sable & Pierre » (`.github/workflows/maisons.yml`) publie le site à chaque modification du dossier `maisons/` sur la branche principale, avec les secrets déjà utilisés par le dépôt (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). Adresse provisoire : `https://lacanau.<ton-compte>.workers.dev`.
- **À la main** : depuis le dossier `maisons/`, `npx wrangler deploy`.
- **Nom de domaine** : une fois acheté sur Cloudflare, retire les `//` devant le bloc `routes` de `wrangler.jsonc` (en y mettant ton domaine), et renseigne `url` dans `js/config.js`.

### Disponibilités encore plus fraîches (facultatif)

Les disponibilités sont déjà mises à jour toutes les 4 heures (voir plus haut). Pour une mise à jour toutes les 30 minutes, tu peux en plus brancher le lien iCal de chaque annonce :

1. Sur Airbnb, dans le calendrier de la maison : **Disponibilités → Connecter des calendriers (ou « Synchroniser les calendriers ») → Exporter le calendrier**. Copie le lien (il se termine par `.ics?s=…`).
2. Dans Cloudflare : **Workers → lacanau → Paramètres → Variables et secrets**, ajoute un secret `ICAL_LACANAU` avec le lien de Lacanau, et `ICAL_BORDEAUX` avec celui de Bordeaux.

Les nuits prises selon ce lien s'ajoutent à celles du fichier automatique.

### Recevoir les demandes de réservation directe

1. **Stockage** : Cloudflare → Stockage et bases de données → KV → créer `sable-et-pierre-demandes`, puis coller son identifiant dans `wrangler.jsonc` (bloc `kv_namespaces`, retirer les `//`).
2. **Alerte sur ton téléphone** (conseillé) : installe l'application gratuite **ntfy**, abonne-toi à un sujet au nom difficile à deviner (ex. `sable-pierre-jules-7k2p`), puis ajoute dans les variables du Worker `NOTIFY_URL` = `https://ntfy.sh/sable-pierre-jules-7k2p`. (Une adresse de webhook Discord ou Slack fonctionne aussi.)
3. **Export** : ajoute un secret `DEMANDES_KEY` (un mot de passe), puis ouvre `https://<ton-site>/api/demandes.csv?key=<DEMANDES_KEY>` : toutes les demandes dans un fichier Excel.

## Voir le site en local

```bash
cd maisons
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

(En local, le calendrier n'est pas synchronisé et la demande directe ouvre un e-mail pré-rempli : c'est normal.)

## Modifier

- **Textes, chambres, équipements, photos** : `js/data.js`
- **Avis cités** : `REVIEWS` à la fin de `js/data.js`
- **Questions fréquentes, comparateur** : directement dans `index.html`
- **Couleurs et polices** : en haut de `css/style.css` (bleu océan pour Lacanau, bordeaux pour Bordeaux, or pour les accents)
