# Nuits Singulières

Site vitrine des hôtels les plus extraordinaires de France (cabanes, bulles, phares, châteaux, igloos…), avec liens d'affiliation vers Booking.com.

Le site est **100 % statique** (HTML, CSS, JavaScript). Pas de serveur, pas de base de données : on l'héberge gratuitement et on le modifie avec un simple éditeur de texte.

## Fonctionnalités

- **Accueil immersif** : diaporama plein écran des coups de cœur, barre de recherche avec suggestions (hôtels, régions), bandeau défilant des expériences
- **4 ambiances** en accordéon animé : Ville, Campagne, Mer, Montagne
- **Expériences** dans un rail horizontal : cabane perchée, bulle, troglodyte, phare, igloo, refuge, sur l'eau, château, lieu historique, design, pieds dans l'eau, vignes
- **Coups de cœur** : projecteur animé avec photos, description et miniatures
- **« Surprenez-moi »** 🎲 : tire un établissement au hasard, avec une animation de machine à sous
- **Favoris** ♡ : le visiteur garde ses coups de cœur dans un tiroir, mémorisés dans son navigateur
- **Filtres** : texte, ambiance, expérience, budget (€ à €€€€), tri (recommandés, budget, distance, nom)
- **Cartes avec mini-diaporama** : on fait défiler les photos de chaque établissement sans quitter la liste
- **« Près de chez moi »** : le visiteur tape son adresse (autocomplétion via le service public d'adresses français, gratuit et sans clé) ou clique sur « Me localiser ». Les établissements sont alors triés par distance, avec un filtre de rayon (50, 100, 200, 400 km). La distance s'affiche aussi sur chaque fiche.
- **Carte de France interactive** (`carte.html`) : tous les lieux avec leur photo en médaillon, regroupés quand on dézoome, fonds Plan / Satellite / Nuit, recherche et filtres, aperçu du lieu au clic, lien partageable (`carte.html?h=phare-de-kerbel`), adaptée au mobile. Une vitrine animée (contour de la France avec un point par lieu) y mène depuis l'accueil
- **Vue carte sur l'accueil** (OpenStreetMap), synchronisée avec une liste
- **Fiche immersive** : photo plein écran avec effet de profondeur, onglets qui suivent la lecture, mosaïque de photos, visionneuse plein écran (glisser sur mobile), carte, partage, suggestions similaires, bouton de réservation fixé en bas sur mobile
- **Animations** douces à l'apparition des sections (désactivées si le visiteur a demandé moins d'animations)
- **Affiliation** : ton identifiant Booking est ajouté automatiquement à chaque lien. Tu peux aussi ajouter des boutons Expedia, Hotels.com ou « Site officiel ».
- **Référencement (SEO)** : titre et description propres à chaque fiche, données structurées `schema.org/Hotel`
- Liens partageables : les filtres sont dans l'URL (ex. `index.html?env=mer&budget=2`)

### Offres payantes pour les hôteliers (`hoteliers.html`)
- Page de vente avec 3 offres (Découverte gratuite, Partenaire 29 €/mois, Premium 79 €/mois) et des prestations à la carte, tarifs dans `config.js`
- Formulaire de candidature (Netlify Forms), pré-rempli quand on arrive depuis le lien « Vous êtes le propriétaire ? » d'une fiche
- Les hôtels avec `plan: "partenaire"` ou `"premium"` ont un badge « Partenaire », remontent dans le tri « Recommandés », et leur fiche affiche leur site, leur téléphone et une « Offre spéciale »
- Les hôtels Premium passent en tête des « Coups de cœur »

### Instagram et newsletter
- Inscription à la newsletter sur l'accueil, chaque fiche et le pied de page (Netlify Forms)
- Section Instagram sur l'accueil et page **lien en bio** `liens.html`
- **Studio** (`studio.html`, outil interne) : génère les carrousels et stories Instagram avec leur légende, l'e-mail HTML de la newsletter et le rapport mensuel à envoyer aux hôteliers
- **Suivi de provenance** : les liens `?src=instagram` / `?src=newsletter` sont ajoutés au libellé Booking. Ton tableau de bord Booking montre ainsi quel canal rapporte.
- Statistiques Plausible optionnelles : visites et clics « Réservation », « Site officiel » et « Téléphone » par hôtel

➡️ Le plan d'action complet (outils, calendrier Instagram, e-mails aux hôteliers, règles légales) est dans **[STRATEGIE.md](STRATEGIE.md)**.

## Pages pour Google (générées automatiquement)

Chaque établissement a sa **vraie page** (`hotels/<id>.html`) et chaque thème son **guide** (`guides/<slug>.html`), avec titre, description, image de partage et données structurées pour Google. Le plan du site (`sitemap.xml`) et `robots.txt` sont générés aussi.

Ces pages sont fabriquées par `node scripts/build.js` à partir de `js/hotels.js` et `js/guides.js`. **Tu n'as rien à lancer** : la GitHub Action « Build » les régénère à chaque modification, et Netlify aussi à chaque déploiement.

- **Ajouter un guide** : copie un bloc dans `js/guides.js` (titre, texte d'introduction, conseils, et règle de sélection des établissements).
- **Avant la mise en ligne** : mets ton vrai nom de domaine dans `siteUrl` (`js/config.js`), puis déclare `https://ton-domaine.fr/sitemap.xml` dans la Google Search Console.

## Voir le site en local

Double-clique sur `index.html`, ou pour que tout fonctionne (géolocalisation comprise) :

```bash
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

## Mise en ligne sur Cloudflare Pages (automatique)

La GitHub Action « Cloudflare » publie le site sur **https://jules.jules-bourdonnnn.workers.dev** à chaque modification. À faire une seule fois :
1. Sur Cloudflare : **My Profile → API Tokens → Create Token**, modèle « Edit Cloudflare Workers » (ou un jeton personnalisé avec la permission *Account → Cloudflare Pages → Edit*). Copie le jeton.
2. Note ton **Account ID** (colonne de droite de la page d'accueil de ton compte Cloudflare, ou dans l'URL `dash.cloudflare.com/<account-id>`).
3. Sur GitHub : **Settings → Secrets and variables → Actions → New repository secret** : ajoute `CLOUDFLARE_API_TOKEN` et `CLOUDFLARE_ACCOUNT_ID`.
4. Onglet **Actions → Cloudflare → Run workflow**.

Seul le dossier `dist/` (préparé par `scripts/dist.js`) est publié : les outils internes (`_review`, `data`, `scripts`) ne sont pas en ligne.

## Mettre en ligne (gratuit)

- **Netlify** : glisse-dépose le dossier sur <https://app.netlify.com/drop>
- **GitHub Pages** : Settings → Pages → Branch `main` → `/ (root)`
- Achète ensuite un nom de domaine (≈ 10 €/an) et relie-le dans les réglages de l'hébergeur

## Gagner de l'argent : l'affiliation

1. Inscris-toi au **Booking.com Affiliate Partner Programme** (https://www.booking.com/affiliate-program/) — il faut généralement avoir le site en ligne avec du contenu.
2. Récupère ton **aid** (Affiliate ID) et colle-le dans `js/config.js` :
   ```js
   booking: { aid: "1234567", label: "site-web" },
   ```
3. C'est tout : chaque bouton « Voir les disponibilités » embarque ton identifiant.

> **À savoir sur la « marge »** : avec l'affiliation, tu ne peux pas ajouter ta marge au prix. C'est Booking qui te reverse une partie de sa propre commission sur chaque séjour réalisé (ni annulé, ni no-show). Le client paie le même prix que sur Booking : c'est ce qui rend le modèle honnête et facile à vendre.

Autres programmes à ajouter ensuite : Expedia Group (Expedia, Hotels.com, Vrbo), Agoda, Trip.com, ou des plateformes qui regroupent plusieurs marques comme Travelpayouts ou Awin. Pour les hôtels indépendants, négocie directement une commission ou un abonnement mensuel pour une fiche mise en avant.

## Ajouter ou modifier un établissement

Les établissements sont de **vrais lieux** en France, décrits à partir de leurs sites officiels et des offices de tourisme (septembre 2026). Vérifie les informations de temps en temps, les hébergements évoluent.

Tout se passe dans `js/hotels.js`. Copie un bloc `{ ... },` et modifie-le :

| Champ | Exemple | Rôle |
|---|---|---|
| `id` | `"cabane-du-lac"` | identifiant unique, sans espaces ni accents (sert à l'URL et au dossier photos) |
| `name`, `tagline` | | nom et phrase d'accroche |
| `city`, `department`, `region`, `address` | | localisation affichée |
| `env` | `"mer"` | `ville`, `campagne`, `mer` ou `montagne` |
| `type` | `"cabane"` | une clé de la liste `TYPES` en haut du fichier |
| `budget` | `2` | 1 à 4 (€ à €€€€), voir `BUDGETS` |
| `featured` | `true` | apparaît dans le diaporama d'accueil et les « Coups de cœur » |
| `lat`, `lng` | `44.394`, `-1.163` | coordonnées GPS (clic droit sur Google Maps, puis clic sur les chiffres pour les copier) |
| `description` | `["Paragraphe 1", "Paragraphe 2"]` | texte de la fiche |
| `highlights`, `amenities` | `["Spa", "Piscine"]` | points forts et équipements |
| `rooms`, `season` | | infos pratiques |
| `photos` | `5` | nombre de photos dans `assets/hotels/<id>/` |
| `bookingUrl` | `"https://www.booking.com/hotel/fr/xxx.html"` | lien de la fiche Booking ; si vide, le site ouvre une recherche Booking avec le nom de l'hôtel |
| `partners` | `{ expedia: "https://…" }` | boutons de réservation secondaires (optionnels) |
| `plan` | `"partenaire"` ou `"premium"` | offre payée par l'hôtel (absent = gratuit) |
| `website`, `phone`, `offer` | | affichés seulement si l'hôtel a une offre payante |

### Photos : récupération automatique

Les photos viennent des sites officiels des établissements. C'est une **GitHub Action** (onglet *Actions* du dépôt) qui s'en charge :

1. Ajoute l'hôtel et l'adresse de ses pages (site officiel, page « chambres » ou « galerie ») dans `data/photo-sources.json`, puis pousse la modification.
2. L'Action visite ces pages et crée une planche-contact numérotée dans `_review/<id>.jpg`.
3. Choisis les meilleures photos (dans l'ordre voulu, la 1re sert de couverture) dans `data/photo-selection.json` :
   ```json
   { "cabane-du-lac": [3, 1, 7, 12, 5] }
   ```
4. Pousse la modification : l'Action télécharge ces photos, les optimise (grande version + vignette) et les range dans `assets/hotels/<id>/`.
5. Mets `photos: 5` (le nombre choisi) dans la fiche de l'hôtel.

Les photos appartiennent aux établissements. Pour une utilisation durable, demande-leur l'autorisation (ils acceptent presque toujours, c'est de la visibilité gratuite) et crédite-les.

## Personnaliser

- **Nom du site, e-mail, domaine, Instagram, tarifs, liens de paiement Stripe** : `js/config.js` (et les balises `<title>` dans les fichiers `.html`)
- **Couleurs et polices** : variables en haut de `css/style.css`
- **Ambiances et types d'expériences** : `ENVIRONMENTS` et `TYPES` en haut de `js/hotels.js`
- **Mentions légales** : complète `mentions-legales.html` (obligatoire en France)

## Structure

```
index.html            Accueil + recherche + carte + newsletter
hotels/<id>.html      Fiche de chaque établissement (générée)
guides/               Guides thématiques (générés)
hotel.html            Redirige les anciennes adresses hotel.html?id=…
hoteliers.html        Offres payantes et candidature des hôteliers
liens.html            Page « lien en bio » Instagram
studio.html           Outil interne : visuels Instagram, newsletter, rapports
mentions-legales.html
STRATEGIE.md          Plan d'action idées 1 et 8
css/style.css
js/config.js          ← identifiants d'affiliation
js/hotels.js          ← la liste des hôtels
js/core.js            briques d'affichage partagées (site et générateur)
js/guides.js          ← la liste des guides
js/common.js          favoris, menus, géolocalisation, formulaires
scripts/build.js      générateur des pages statiques
js/app.js             logique de l'accueil
js/hotel.js           interactions de la fiche (carte, photos, partage)
js/carte.js           carte interactive (carte.html)
vendor/               Leaflet et Leaflet.markercluster (cartes), licences incluses
js/hoteliers.js       offres et formulaire hôteliers
js/studio.js          logique du Studio
```

## Prochaines étapes conseillées

1. Remplacer les exemples par 30 à 50 vrais hôtels, avec leurs liens Booking
2. Générer une vraie page HTML par hôtel pour un meilleur référencement Google (aujourd'hui les fiches sont construites en JavaScript)
3. Ajouter des pages « guides » (« 10 cabanes perchées à moins de 2 h de Paris ») : c'est ce qui attire le trafic Google
4. Ajouter la même chose pour les restaurants
