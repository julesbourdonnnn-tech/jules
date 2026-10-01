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
| `index.html` | Accueil : écran partagé « l'océan / la ville » (la moitié survolée s'agrandit), présentation des deux maisons, galerie à faire glisser, les environs (onglets Lacanau / Bordeaux, météo et température de l'océan en direct), comparateur, avis, questions fréquentes |
| `lacanau.html`, `bordeaux.html` | Fiche complète : diaporama plein écran, chiffres clés, description de l'annonce, mosaïque de photos et visionneuse plein écran (clavier, glisser du doigt), chambres, équipements, avis et notes détaillées, **calendrier de réservation**, carte du quartier, règlement, lien vers l'autre maison |
| `mentions-legales.html` | Mentions légales et données personnelles |
| `404.html` | Page d'erreur |

Détails : polices hébergées sur le site (aucune requête vers Google), aucun cookie, animations douces désactivées si le visiteur a demandé moins d'animations, barre « Réserver » fixée en bas sur mobile, données structurées Google (`VacationRental`) avec la note des voyageurs.

### Comment on réserve

Sur chaque fiche, le visiteur choisit ses dates dans le calendrier et le nombre de voyageurs, puis :

- **« Voir le prix et réserver »** ouvre l'annonce Airbnb **avec les dates et les voyageurs déjà remplis** : il voit le prix exact et réserve avec le paiement sécurisé d'Airbnb.
- **« Demande de réservation directe »** : un formulaire (nom, e-mail, téléphone, message) qui t'envoie la demande avec les dates. Sans réglage, il ouvre un e-mail pré-rempli chez le visiteur ; avec le stockage activé (voir plus bas), la demande arrive directement et sonne sur ton téléphone.

Les dates choisies sont gardées pendant la visite, et une adresse comme `bordeaux.html?arrivee=2026-12-24&depart=2026-12-27&voyageurs=6` pré-remplit le calendrier (pratique à envoyer à quelqu'un).

## D'où viennent les textes et les photos

Tout vient **des deux annonces Airbnb**, sans rien inventer :

- La GitHub Action **« Maisons — photos Airbnb »** (`.github/workflows/maisons-airbnb.yml`, script `scripts/airbnb.py`) télécharge les annonces, les **27 photos de chaque maison** (en trois tailles, au format WebP, bandes noires des captures d'écran retirées) et les avis des voyageurs. Résultats : `assets/photos/`, `data/airbnb/<maison>.json` (détail de l'annonce) et `data/airbnb/raw/<maison>-reviews.json` (avis).
- Les textes affichés sont dans **`js/data.js`** : description de l'annonce (mot pour mot), chambres, équipements, règlement, notes, ordre et légendes des photos, avis cités. Les informations sur les environs (`DESTINATIONS`) sont des informations générales, avec des temps de trajet indicatifs.

**Si tu modifies une annonce sur Airbnb** (nouvelles photos, nouvel équipement…) : GitHub → Actions → « Maisons — photos Airbnb » → *Run workflow*. Puis mets à jour `js/data.js` (par exemple ajoute la nouvelle photo dans la liste `photos`). Pour retélécharger des photos déjà présentes, supprime d'abord les fichiers `assets/photos/<maison>/NN-*.webp` correspondants.

## Mise en ligne (Cloudflare)

Le site a **son propre Worker Cloudflare, « sable-et-pierre »**, séparé de Nuits Singulières et du Passe (le dossier `maisons/` est exclu de nuitsinguliere.com par le `.assetsignore` à la racine).

- **Recommandé (comme pour les autres sites)** : Cloudflare → Workers & Pages → Créer → Importer un dépôt Git → `jules`, puis dans les réglages de build : **répertoire racine = `maisons`**, commande de déploiement `npx wrangler deploy`. Cloudflare publie le site à chaque modification.
- **Autre option** : la GitHub Action « Sable & Pierre » (`.github/workflows/maisons.yml`) publie le site à chaque modification du dossier `maisons/` sur la branche principale, avec les secrets déjà utilisés par le dépôt (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). Adresse provisoire : `https://sable-et-pierre.<ton-compte>.workers.dev`.
- **À la main** : depuis le dossier `maisons/`, `npx wrangler deploy`.
- **Nom de domaine** : une fois acheté sur Cloudflare, retire les `//` devant le bloc `routes` de `wrangler.jsonc` (en y mettant ton domaine), et renseigne `url` dans `js/config.js`.

### Afficher les vraies disponibilités (calendrier Airbnb)

Le calendrier du site peut griser automatiquement les nuits déjà réservées, en lisant ton calendrier Airbnb (mis à jour toutes les 30 minutes) :

1. Sur Airbnb, dans le calendrier de la maison : **Disponibilités → Connecter des calendriers (ou « Synchroniser les calendriers ») → Exporter le calendrier**. Copie le lien (il se termine par `.ics?s=…`).
2. Dans Cloudflare : **Workers → sable-et-pierre → Paramètres → Variables et secrets**, ajoute un secret `ICAL_LACANAU` avec le lien de Lacanau, et `ICAL_BORDEAUX` avec celui de Bordeaux.

C'est tout : sous le calendrier, le message devient « Disponibilités synchronisées avec le calendrier Airbnb ». Sans ce réglage, le calendrier fonctionne quand même et Airbnb vérifie les dates à l'étape suivante.

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
