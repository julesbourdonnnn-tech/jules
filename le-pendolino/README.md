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
| `#top` | A. En-tête | Logo à tampon tournant, liens Menu / La Pizzeria / Avis / Contact, bouton « Commander / Réserver ». Menu plein écran (nappe vichy) sur mobile. |
| — | B. Accueil | Titre, notes écrites à la main, grande pizza dessinée qui tourne sur sa pelle, tampon « Fait maison », pastille « Ouvert ce soir dès… » calculée en direct. Puis un bandeau défilant des pizzas. |
| — | De la farine au four | Les 4 étapes : pétrissage, maturation, façonnage, cuisson. |
| `#menu` | C. La carte | Onglets en forme de billets, feuille de menu avec pointillés, une mini-pizza dessinée par recette (elle tourne au survol), tampons « Fait maison », « Incontournable », « Végétarien ». |
| `#pizzeria` | D. Savoir-faire | Texte, provenance des produits, photos façon polaroïd, bande Instagram. |
| `#avis` | E. Avis | Mots scotchés en carrousel (boutons, glisser au doigt, défilement automatique). |
| `#contact` | F. Infos pratiques | Adresse + itinéraire, téléphone, Instagram, horaires sur un tableau des départs à palettes (le jour et l'état « En cuisson / Ce soir / Repos » sont calculés à l'heure de Paris), plan. |

Sur mobile, une barre fixe en bas d'écran propose « Commander » et « Itinéraire ».

## ⚠️ À compléter avant la mise en ligne

Chaque endroit est repéré par un commentaire `À COMPLÉTER` dans `index.html`.

1. **Téléphone** : `04 75 00 00 00` / `tel:+33475000000` est un numéro factice. Remplacer partout (rechercher `33475000000` et `04 75 00 00 00`), y compris dans le bloc JSON-LD en haut de page. Pour un système de commande en ligne, remplacer le lien du bouton « Commander / Réserver ».
2. **Horaires** : ceux du pied de page sont des exemples. Modifier le tableau (le texte **et** l'attribut `data-open="18:00-21:30"`, qui sert à l’état « ouvert / fermé » en direct ; jour fermé = pas d'attribut) et le bloc `openingHoursSpecification` du JSON-LD.
3. **Carte et prix** : les pizzas et prix sont des exemples. Copier un `<article class="dish">` pour ajouter un produit (changer `data-pizza` pour sa mini-pizza) ; tampons disponibles : `stamp-house`, `stamp-star`, `stamp-veg`.
4. **Textes** : les notes manuscrites (« basilic cueilli ce matin », « la reine de la maison »…) et la description du savoir-faire sont à relire avec l'équipe pour qu'elles collent à la réalité.
5. **Avis clients** : les avis affichés sont des **exemples de mise en page**, pas de vrais avis. Les remplacer par de vrais avis Google / TripAdvisor (texte exact, prénom + initiale avec l'accord du client) — publier de faux avis est interdit (pratique commerciale trompeuse).
6. **Photos** : ce sont des photos Unsplash d'illustration (libres de droits). Pour la grille Instagram et la section « La pizzeria », les remplacer par les vraies photos du compte @lependolino : déposer les fichiers dans `assets/` (format `.webp` ou `.jpg`, ~800 px de large) et changer les `src`. Si une photo ne se charge pas, une pizza dessinée sur une nappe, du bois ou de l'ardoise la remplace automatiquement (attribut `data-pizza`).
   Les pizzas dessinées (accueil, carte) sont générées par `js/main.js` : recettes disponibles `margherita`, `regina`, `diavola`, `napoli`, `ortolana`, `calzone`, `quattro`, `chevre`, `mortadella`, `tartufo`, `montagnarde`, `salmone` ; changer `data-seed` donne une autre disposition.
7. **Nom de domaine** : `https://lependolino.fr/` est supposé dans `index.html` (canonical, JSON-LD), `robots.txt` et `sitemap.xml`. Adapter au domaine réel.
8. **Fiche Google Business Profile** : vérifier que nom, adresse et téléphone y sont rigoureusement identiques à ceux du site (essentiel pour le référencement local).

## Modifier les styles

Après une modification des classes dans `index.html`, `404.html`, `js/main.js` ou `src/input.css`, régénérer la feuille de style depuis ce dossier :

```sh
npx tailwindcss@3.4.17 -i src/input.css -o css/style.css --minify
```

Couleurs : `cream`, `mozza`, `tomato`, `basil`, `charcoal`, `copper` (+ variantes). Polices : `font-display` (Playfair Display), `font-sans` (Plus Jakarta Sans), `font-hand` (Caveat, notes manuscrites), `font-board` (Oswald, tableau des départs).
Le cuivré `copper` (#D4A373) sert sur fonds sombres ; sur fond crème, utiliser `copper-dark` pour le texte (contraste suffisant).

## Mise en ligne

Le dossier est exclu du site Nuits Singulières (`.assetsignore` à la racine) et se publie à part :

```sh
cd le-pendolino
npx wrangler deploy
```

Ou n'importe quel hébergeur statique (Netlify, GitHub Pages, OVH…) : envoyer le contenu du dossier, sans `src/`, `tailwind.config.js` ni `wrangler.jsonc`.

## Performances et accessibilité

- Une seule feuille de style compilée (~40 Ko), aucune bibliothèque JS ; les illustrations sont dessinées dans le navigateur (aucune image à télécharger pour l'accueil et la carte). Photos et plan chargés à la demande.
- Balises sémantiques (`header`, `nav`, `main`, `section`, `article`, `figure`, `address`, `footer`), lien d'évitement, onglets ARIA, focus visibles.
- Animations désactivées si le visiteur a demandé à réduire les animations.
- Données structurées `schema.org/Restaurant` pour Google.
