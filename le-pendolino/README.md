# Le Pendolino — site vitrine

Site one-page de la pizzeria artisanale **Le Pendolino**, 70 Grande Rue, 26120 Montmeyran.
100 % statique (HTML + Tailwind CSS compilé + un petit fichier JavaScript), sans framework : il s'ouvre en double-cliquant sur `index.html` et se publie tel quel.

## Arborescence

```
le-pendolino/
├── index.html          La page (toutes les sections)
├── 404.html            Page « introuvable »
├── css/style.css       Feuille de style générée par Tailwind (ne pas modifier à la main)
├── src/input.css       Source des styles : composants (.btn, .menu-card, .badge…) et animations
├── tailwind.config.js  Palette, polices, ombres
├── js/main.js          Menu mobile, onglets de la carte, carrousel d'avis, apparitions, « Ouvert / Fermé »
├── assets/favicon.svg  Icône d'onglet
├── robots.txt, sitemap.xml, _headers
└── wrangler.jsonc      Mise en ligne Cloudflare (Worker « le-pendolino »)
```

### Sections de la page

| Ancre | Section | Contenu |
|---|---|---|
| `#top` | A. En-tête fixe | Logo, liens Menu / La Pizzeria / Avis / Contact, bouton « Commander / Réserver ». Transparent sur la photo, plein au défilement. Menu plein écran sur mobile. |
| — | B. Accueil | Photo plein écran, titre, deux boutons (« Voir le Menu », « Appeler pour commander »), trois arguments. |
| `#menu` | C. La carte | Onglets Pizzas Rouges / Blanches / Desserts / Boissons (accessibles au clavier), cartes avec prix et badges « Fait Maison », « Incontournable », « Végétarien ». |
| `#pizzeria` | D. Savoir-faire | Maturation lente, produits italiens et locaux, cuisson minute + grille façon Instagram. |
| `#avis` | E. Avis | Carrousel (boutons, glisser au doigt, défilement automatique en pause au survol). |
| `#contact` | F. Infos pratiques | Adresse + itinéraire Google Maps, téléphone cliquable, horaires (jour en cours surligné, « Ouvert / Fermé » à l'heure de Paris), Instagram, plan. |

Sur mobile, une barre fixe en bas d'écran propose « Commander » et « Itinéraire ».

## ⚠️ À compléter avant la mise en ligne

Chaque endroit est repéré par un commentaire `À COMPLÉTER` dans `index.html`.

1. **Téléphone** : `04 75 00 00 00` / `tel:+33475000000` est un numéro factice. Remplacer partout (rechercher `33475000000` et `04 75 00 00 00`), y compris dans le bloc JSON-LD en haut de page. Pour un système de commande en ligne, remplacer le lien du bouton « Commander / Réserver ».
2. **Horaires** : ceux du pied de page sont des exemples. Modifier le tableau (le texte **et** l'attribut `data-open="18:00-21:30"`, qui sert au badge « Ouvert / Fermé » ; jour fermé = pas d'attribut) et le bloc `openingHoursSpecification` du JSON-LD.
3. **Carte et prix** : les pizzas et prix sont des exemples. Copier un `<article class="menu-card">` pour ajouter un produit ; badges disponibles : `badge-house`, `badge-star`, `badge-veg`.
4. **Avis clients** : les avis affichés sont des **exemples de mise en page**, pas de vrais avis. Les remplacer par de vrais avis Google / TripAdvisor (texte exact, prénom + initiale avec l'accord du client) — publier de faux avis est interdit (pratique commerciale trompeuse).
5. **Photos** : ce sont des photos Unsplash d'illustration (libres de droits). Pour la grille Instagram et la section « La pizzeria », les remplacer par les vraies photos du compte @lependolino : déposer les fichiers dans `assets/` (format `.webp` ou `.jpg`, ~800 px de large) et changer les `src`. Si une photo ne se charge pas, un emplacement décoratif s'affiche à la place.
6. **Nom de domaine** : `https://lependolino.fr/` est supposé dans `index.html` (canonical, JSON-LD), `robots.txt` et `sitemap.xml`. Adapter au domaine réel.
7. **Fiche Google Business Profile** : vérifier que nom, adresse et téléphone y sont rigoureusement identiques à ceux du site (essentiel pour le référencement local).

## Modifier les styles

Après une modification des classes dans `index.html`, `404.html`, `js/main.js` ou `src/input.css`, régénérer la feuille de style depuis ce dossier :

```sh
npx tailwindcss@3.4.17 -i src/input.css -o css/style.css --minify
```

Couleurs disponibles dans les classes : `cream`, `tomato`, `basil`, `charcoal`, `copper` (+ variantes `-dark`).
Le cuivré `copper` (#D4A373) sert sur fonds sombres ; sur fond crème, utiliser `copper-dark` pour le texte (contraste suffisant).

## Mise en ligne

Le dossier est exclu du site Nuits Singulières (`.assetsignore` à la racine) et se publie à part :

```sh
cd le-pendolino
npx wrangler deploy
```

Ou n'importe quel hébergeur statique (Netlify, GitHub Pages, OVH…) : envoyer le contenu du dossier, sans `src/`, `tailwind.config.js` ni `wrangler.jsonc`.

## Performances et accessibilité

- Une seule feuille de style compilée (~40 Ko, aucune dépendance JS), photo d'accueil préchargée en plusieurs tailles, autres images et carte Google chargées à la demande.
- Balises sémantiques (`header`, `nav`, `main`, `section`, `article`, `figure`, `address`, `footer`), lien d'évitement, onglets ARIA, focus visibles.
- Animations désactivées si le visiteur a demandé à réduire les animations.
- Données structurées `schema.org/Restaurant` pour Google.
