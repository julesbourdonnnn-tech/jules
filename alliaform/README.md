# AlliaForm — nouveau site

Refonte du site **[alliaform.fr](https://www.alliaform.fr)** : location de salles de formation équipées à Bordeaux (Cité Mondiale) et centre d'examen officiel.

Comme les autres sites du dépôt, il est **100 % statique** (HTML, CSS, JavaScript) : pas de WordPress, pas de base de données, pas de mises à jour de sécurité à surveiller. Hébergement gratuit, modifiable avec un simple éditeur de texte.

## Ce que contient le site

| Section | Rôle |
|---|---|
| Accueil | La promesse en une phrase (« Vous formez, nous nous occupons du reste. »), l'illustration des quais des Chartrons, la carte « Votre salle est prête », les chiffres clés |
| Salles et tarifs | **Configurateur** : on choisit la salle (12 ou 25 places), les ordinateurs et la disposition (en classe ou en U) ; le plan de la salle et le prix se mettent à jour. Puis tous les tarifs, en toute transparence |
| Tout compris | Les 8 prestations incluses (matériel, fibre, pauses, accueil, confort, accessibilité…) |
| Services | L'offre modulaire pour les organismes de formation : location, logistique et administratif, accompagnement commercial, examens |
| Examens | TOEFL, TOEIC, GMAT et Pearson VUE, avec les liens d'inscription officiels et les étapes |
| Histoire | L'origine d'AlliaForm et les investissements depuis 2012 |
| Accès | Adresse, tram, gare, parking, accessibilité, plan OpenStreetMap et itinéraire |
| Questions | Les 8 questions les plus fréquentes |
| Devis | **Formulaire avec estimation en direct**, qui prépare un e-mail complet (dates, salle, participants, déjeuner) ; bouton « Copier ma demande » si la messagerie ne s'ouvre pas |

Détails soignés : conçu d'abord pour le téléphone (barre « Appeler / Devis » fixée en bas), apparitions douces au défilement (désactivées si le visiteur préfère moins d'animations), navigation au clavier, données structurées Google (`LocalBusiness` avec les tarifs, `FAQPage`), image de partage pour les réseaux, **aucun cookie ni traceur**, polices hébergées sur le site (aucune requête vers Google).

## ✅ À vérifier avant la mise en ligne

Le site actuel n'étant pas consultable depuis l'outil de création, les informations ont été reprises de ses pages publiques, de son catalogue de prestations et d'annuaires officiels. **Merci de relire ces points** :

1. **Tarifs** (HT, la journée) : salle 12 places 240 €, + 6 ordinateurs 290 €, + 12 ordinateurs 330 € ; salle 25 places 420 €, + 25 ordinateurs 600 € ; formule déjeuner 20 € HT par personne. Le tarif demi-journée n'étant pas publié, le site indique « tarif réduit, sur devis ».
2. **Examens** : TOEFL iBT® (ETS), TOEIC® (ETS Global), GMAT™ et certifications Pearson VUE. Retirer une carte si un examen n'est plus proposé.
3. **Accès** : tram B arrêt CAPC à 200 m, tram C arrêt Paul Doumer, parking de 842 places sous la Cité Mondiale.
4. **Mentions légales** (`mentions-legales.html`) : SAS au capital de 44 000 €, RCS Bordeaux 750 834 053, siège 20 quai des Chartrons, directeur de la publication Romain Bourdon. Le numéro de TVA **FR84 750 834 053** a été calculé à partir du SIREN (clé officielle) : le comparer à une facture.
5. **Logo** : le symbole des deux arches (une arcade bordelaise, une porte ouverte) est une proposition. Pour garder l'ancien logo, remplacer le symbole `i-logo` en haut des fichiers HTML et les images de `assets/`.

## Pour aller plus loin (fortement conseillé)

- **De vraies photos des salles** : rien ne rassure davantage. 4 à 6 photos lumineuses (une salle de chaque type, l'espace pause, l'accueil). Elles peuvent remplacer l'illustration de l'accueil (`assets/quais.svg`) ou s'ajouter dans la section « Tout compris ». Format conseillé : JPG de 1 600 px de large.
- **Avis Google** : ajouter deux ou trois avis réels (avec le prénom et l'entreprise, avec leur accord) dans une section « Ils nous font confiance ».
- **Anciens PDF** : le plan d'accès (`/media/plan_acces.pdf`) et le catalogue (`/catalogue/…`) de l'ancien site ne sont pas repris. Pour les garder, copier les fichiers dans les mêmes dossiers.

## Mise en ligne (Cloudflare)

Le site a **son propre Worker Cloudflare, « alliaform »**, séparé de Nuits Singulières et du Passe (le dossier est exclu de nuitsinguliere.com par le `.assetsignore` à la racine du dépôt).

1. Cloudflare → Workers & Pages → Créer → Importer un dépôt Git → `jules`, puis dans les réglages de build : **répertoire racine = `alliaform`**, commande de déploiement `npx wrangler deploy`. Le site est alors publié à chaque modification, sur une adresse provisoire `https://alliaform.<compte>.workers.dev` : idéal pour relire avant de basculer.
2. **Nom de domaine** : une fois `alliaform.fr` géré par Cloudflare (DNS), retirer les `//` devant le bloc `routes` de `wrangler.jsonc`. L'ancien site WordPress peut être coupé ensuite.
3. **Anciennes adresses** : le fichier `_redirects` renvoie les pages de l'ancien site (salles, centre d'examen, TOEFL, actualités…) vers la bonne section de la nouvelle page. Google ne perd rien.
4. Déclarer `https://www.alliaform.fr/sitemap.xml` dans la Google Search Console, et mettre à jour le lien du site sur la fiche Google, LinkedIn et Facebook.

À la main, depuis ce dossier : `npx wrangler deploy`.

## Voir le site en local

```bash
cd alliaform
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

## Modifier

| Quoi | Où |
|---|---|
| Textes, questions fréquentes, coordonnées | `index.html` |
| Tarifs | `js/main.js` (constante `ROOMS` et `LUNCH`) **et** le tableau « Tous nos tarifs » de `index.html` (et les `Offer` des données structurées en haut du fichier) |
| Couleurs, polices, espacements | variables en haut de `css/style.css` |
| Illustration de l'accueil | `assets/quais.svg` |
| Logo et icônes | symbole `i-logo` dans les fichiers HTML, `assets/*.svg` et `assets/*.png` (`logo.png` et `icone-512.png` servent aussi de photo de profil LinkedIn, Facebook ou Google) |
| Mentions légales | `mentions-legales.html` |

## Structure

```
alliaform/
  index.html             La page d'accueil (une seule page, avec ses sections)
  mentions-legales.html
  404.html               « Cette salle n'existe pas. »
  css/style.css          Styles (couleurs et polices en haut)
  js/main.js             Menu, configurateur de salle, formulaire de devis
  fonts/                 Polices Figtree et Fraunces, hébergées sur le site
  assets/                Illustration, logo, icônes, image de partage
  _headers, _redirects   En-têtes HTTP et redirections des anciennes adresses
  robots.txt, sitemap.xml
  wrangler.jsonc         Configuration Cloudflare
```
