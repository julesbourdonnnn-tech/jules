# Sable & Pierre — les maisons de Lacanau et Bordeaux

Site de présentation et de réservation de deux maisons de famille en Gironde :

- **La Maison du Lac** — Lacanau, Le Moutchic : 12 voyageurs, 6 chambres, piscine privée, lac à 50 m, océan à 10 min ([annonce Airbnb](https://www.airbnb.fr/rooms/662061426615418606))
- **La Maison de Pierre** — Bordeaux : 8 voyageurs, 5 chambres, pierre de taille, verrière et terrasse, hypercentre à 10 min à pied ([annonce Airbnb](https://www.airbnb.fr/rooms/50226249))

Comme les autres sites du dépôt, il est **100 % statique** (HTML, CSS, JavaScript), sans base de données, et se modifie avec un simple éditeur de texte.

## ✅ À faire avant de mettre en ligne

1. **E-mail du site** : `contact.sablepierre@gmail.com`, réglé dans `js/config.js` (`email`) : c'est là qu'arrivent les demandes de réservation directe.
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

### Réservation directe (sans Airbnb)

Le voyageur réserve **directement sur le site, sans frais de plateforme** :

1. Il choisit ses dates (les nuits prises sont grisées, la durée minimale est respectée) et ses voyageurs : **le prix détaillé s'affiche** : le prix Airbnb de ces dates, **moins 10 %** (remise réservation directe), à côté du bouton « Réserver sur Airbnb » pour comparer.
2. Il indique ses coordonnées, accepte les **conditions de réservation** (`conditions.html`) et paie par carte sur la page sécurisée **Stripe**. Sa carte n'est **pas débitée** : le montant est seulement réservé (empreinte bancaire). Les dates sont bloquées sur le site pendant le paiement.
3. Tu reçois un **e-mail** sur contact.sablepierre@gmail.com (envoyé par reservations@sable-et-pierre.com via Cloudflare Email Routing) et, si `NOTIFY_URL` est réglé, une alerte ntfy. Bouton « Tester les alertes » dans `/admin.html` pour vérifier. Dans ton **espace propriétaire** (`/admin.html`), tu cliques **Accepter** (la carte est débitée, Stripe envoie le reçu au voyageur, et un e-mail de confirmation pré-rempli s'ouvre pour toi) ou **Refuser** (l'empreinte est libérée, rien n'est débité).
4. Le voyageur suit sa réservation sur sa page personnelle (`/reservation.html?id=…`).

**Statistiques** : dans `/admin.html` → « Fréquentation et résultats » : visites par jour, pages vues, visiteurs en ce moment, sources (Google, Instagram, accès direct…), pays, appareils, clics « Réserver en direct » / « Réserver sur Airbnb », demandes, réservations confirmées et chiffre d'affaires direct, sur 7 jours, 30 jours, 90 jours ou 12 mois. Mesure anonyme sans cookie (base D1 « sable-et-pierre-stats »), robots et visites du propriétaire exclus.

**Calendrier** : en haut de `/admin.html`, un calendrier mois par mois montre les demandes à valider, les réservations confirmées et les nuits prises sur Airbnb, pour une maison ou les deux. Un clic sur une réservation ouvre sa fiche.

**Codes promo** : dans `/admin.html` → « Codes promo », crée un code (réduction en %, ou prix total fixe, ex. 1 € pour un essai), pour une maison ou les deux, avec un nombre d'utilisations maximum. Le voyageur le saisit au moment de réserver ; le serveur vérifie le code et recalcule le prix (minimum 1 €). Un paiement abandonné ou une réservation refusée ne consomme pas le code.

⚠️ Une empreinte bancaire reste valable **7 jours** : valide les réservations dans ce délai (idéalement sous 24 h).

Tant que les tarifs ou la clé Stripe ne sont pas renseignés, le site fonctionne en **demande de réservation** : le voyageur envoie ses dates et ses coordonnées sans payer, tu la retrouves dans l'espace propriétaire et tu lui réponds.

#### Mise en route (une seule fois)

1. **Les prix** sont ceux d'Airbnb, relevés automatiquement chaque jour (voir plus bas) : rien à faire. Dans `js/tarifs.js` tu règles la remise (`remiseDirecte`, 10 %), la caution et les conditions d'annulation. Si un jour tu veux tes propres prix, renseigne `nuit` (et `saisons`, `menage`, `taxeSejour`) : ils remplacent alors les prix Airbnb.
2. **Stripe** : crée un compte sur stripe.com (gratuit, avec ton IBAN), puis Développeurs → Clés API → copie la **clé secrète** (`sk_live_…`). Pour essayer d'abord sans vrai paiement, utilise la clé de test (`sk_test_…`) et la carte 4242 4242 4242 4242.
3. Dans **Cloudflare → Workers & Pages → lacanau → Settings → Variables and secrets**, ajoute (type « Secret ») :
   - `STRIPE_SECRET_KEY` : la clé Stripe ;
   - `ADMIN_KEY` : un mot de passe long, pour entrer dans `/admin.html` ;
   - `NOTIFY_URL` (conseillé) : installe l'app gratuite **ntfy**, abonne-toi à un sujet au nom difficile à deviner (ex. `sable-pierre-7k2p9x`), et mets `https://ntfy.sh/sable-pierre-7k2p9x`. Chaque réservation sonne sur ton téléphone.
4. **Éviter les doubles réservations avec Airbnb** :
   - Airbnb → site : déjà automatique (calendrier lu toutes les 4 h, voir plus bas).
   - Site → Airbnb : dans `/admin.html`, ouvre « Synchroniser avec Airbnb », copie le lien de chaque maison, puis dans Airbnb : calendrier de l'annonce → Disponibilités → Connecter des calendriers → **Importer un calendrier**. Airbnb bloquera les dates réservées ici.

Le stockage des réservations (« sable-et-pierre-reservations ») est déjà créé et branché.

### Prix « à partir de »

L'accueil et le haut des fiches affichent « À partir de … € la nuit en direct » : le prix de nuit Airbnb le plus bas des 12 prochains mois, remise déduite. Pour imposer un autre chiffre, renseigne `priceFrom` dans `js/data.js`.

## Ce qui se met à jour tout seul

La GitHub Action **« Maisons — données »** (`.github/workflows/maisons-donnees.yml`) tourne toutes les 4 heures, une fois la branche fusionnée dans `main` :

- **Disponibilités** (`scripts/disponibilites.py` → `js/disponibilites.js`) : pour les 12 prochains mois, les nuits libres, les jours d'arrivée et de départ possibles et la durée minimale de séjour, lus dans le calendrier Airbnb de chaque annonce. **Rien à régler.** Quand tu bloques des dates sur Airbnb, le site suit dans les 4 heures.
- **Prix** (`scripts/prix_airbnb.py` → `js/tarifs-airbnb.js`), une fois par jour : pour chaque quinzaine des 12 prochains mois, le prix affiché par Airbnb (nuit, frais du séjour, taxes). Quand tu changes tes prix sur Airbnb, le site suit le lendemain, toujours avec la remise de 10 %. Si un relevé échoue, les prix précédents sont gardés.
- **Climat** (`scripts/climat.py` → `js/climat.js`) : moyennes 2015–2024 (températures, jours de pluie, température de l'océan à Lacanau), calculées une fois à partir des archives Open-Meteo. Pour les recalculer : Actions → « Maisons — données » → Run workflow → climat = oui.

## D'où viennent les textes et les photos

Tout vient **des deux annonces Airbnb**, sans rien inventer :

- La GitHub Action **« Maisons — photos Airbnb »** (`.github/workflows/maisons-airbnb.yml`, script `scripts/airbnb.py`) télécharge les annonces, les **27 photos de chaque maison** (en trois tailles, au format WebP, bandes noires des captures d'écran retirées) et les avis des voyageurs. Résultats : `assets/photos/`, `data/airbnb/<maison>.json` (détail de l'annonce) et `data/airbnb/raw/<maison>-reviews.json` (avis).
- Les textes affichés sont dans **`js/data.js`** : description de l'annonce (mot pour mot), chambres, équipements, règlement, notes, ordre et légendes des photos, avis cités. Les informations sur les environs (`DESTINATIONS`) sont des informations générales, avec des temps de trajet indicatifs.

**Si tu modifies une annonce sur Airbnb** (nouvelles photos, nouvel équipement…) : GitHub → Actions → « Maisons — photos Airbnb » → *Run workflow*. Puis mets à jour `js/data.js` (par exemple ajoute la nouvelle photo dans la liste `photos`). Pour retélécharger des photos déjà présentes, supprime d'abord les fichiers `assets/photos/<maison>/NN-*.webp` correspondants.

## Mise en ligne (Cloudflare)

Le site a **son propre Worker Cloudflare, « lacanau »**, séparé de Nuits Singulières et du Passe (le dossier `maisons/` est exclu de nuitsinguliere.com par le `.assetsignore` à la racine).

- **En place** : le projet Cloudflare « lacanau » est relié au dépôt `jules` (répertoire racine `maisons`, commande de déploiement `npx wrangler deploy`). Chaque modification poussée sur sa branche de production republie le site.
- **Pour le créer à nouveau (comme pour les autres sites)** : Cloudflare → Workers & Pages → Créer → Importer un dépôt Git → `jules`, puis dans les réglages de build : **répertoire racine = `maisons`**, commande de déploiement `npx wrangler deploy`. Cloudflare publie le site à chaque modification.
- **Autre option** : la GitHub Action « Sable & Pierre » (`.github/workflows/maisons.yml`) publie le site à chaque modification du dossier `maisons/` sur la branche principale, avec les secrets déjà utilisés par le dépôt (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). Adresse provisoire : `https://lacanau.<ton-compte>.workers.dev`.
- **À la main** : depuis le dossier `maisons/`, `npx wrangler deploy`.
- **Nom de domaine** : **https://sable-et-pierre.com** (acheté sur Cloudflare, branché par le bloc `routes` de `wrangler.jsonc` ; `www.sable-et-pierre.com` renvoie vers l'adresse sans www). L'adresse `lacanau.….workers.dev` continue de fonctionner.

### Disponibilités encore plus fraîches (facultatif)

Les disponibilités sont déjà mises à jour toutes les 4 heures (voir plus haut). Pour une mise à jour toutes les 30 minutes, tu peux en plus brancher le lien iCal de chaque annonce :

1. Sur Airbnb, dans le calendrier de la maison : **Disponibilités → Connecter des calendriers (ou « Synchroniser les calendriers ») → Exporter le calendrier**. Copie le lien (il se termine par `.ics?s=…`).
2. Dans Cloudflare : **Workers → lacanau → Paramètres → Variables et secrets**, ajoute un secret `ICAL_LACANAU` avec le lien de Lacanau, et `ICAL_BORDEAUX` avec celui de Bordeaux.

Les nuits prises selon ce lien s'ajoutent à celles du fichier automatique.

## Référencement (Google, Bing)

- Chaque page a un titre et une description pensés pour les recherches (« location maison avec piscine Lacanau 12 personnes », « location maison Bordeaux centre 8 personnes », « vacances en famille »…), une adresse canonique et des données structurées (`VacationRental`, `FAQPage`, fil d'Ariane).
- **Guides** : `vacances-famille-lacanau.html` et `vacances-famille-bordeaux.html`, des pages de conseils pour les familles qui renvoient vers les maisons.
- `sitemap.xml` (plan du site) et `robots.txt`.
- Le contenu des fiches (`lacanau.html`, `bordeaux.html`) est aussi écrit en HTML simple, lisible par tous les moteurs. **Après une modification de `js/data.js` ou l'ajout d'une page**, relance `node scripts/seo.mjs` (met à jour ce contenu et le plan du site).

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
