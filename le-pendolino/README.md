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

## ⚠️ À vérifier avant la mise en ligne

Infos réelles déjà intégrées : téléphone **04 75 82 83 08**, vente **à emporter uniquement**, **cuisson au feu de bois**, carte **Base Tomate** (19 pizzas, prix de la carte papier), note Google **4,4/5** et extraits d'avis.

1. **Horaires** : les annuaires en ligne se contredisent. Le site affiche « lundi fermé, mardi → dimanche 17h30 – 21h00 », **à confirmer** (surtout le dimanche). Modifier le tableau (texte **et** attribut `data-open="17:30-21:00"` ; jour fermé = pas d'attribut) et le bloc `openingHoursSpecification` du JSON-LD.
2. **Autres pages de la carte** (base crème, desserts, boissons…) : copier un `<article class="dish">` dans la grille de la carte (changer `data-pizza` pour la mini-pizza dessinée ; tampons : `stamp-house`, `stamp-star`, `stamp-veg`). Pour plusieurs catégories, remettre des onglets (le script `js/main.js` gère déjà `role="tab"` / `role="tabpanel"`).
3. **Avis** : ce sont des extraits courts de vrais avis (Google, TripAdvisor) trouvés via les annuaires. Pour en ajouter, copier le texte exact depuis la fiche Google, sans le modifier. La note 4,4/5 est à mettre à jour de temps en temps.
4. **Logo** : le logo de l'en-tête est une reprise simplifiée (soleil rouge, pelle, écriture). Remplacer par le fichier du vrai logo si disponible.
5. **Photos** : ce sont des photos Unsplash d'illustration. Les remplacer par les vraies photos du compte @lependolino : déposer les fichiers dans `assets/` (format `.webp` ou `.jpg`, ~800 px de large) et changer les `src`. Si une photo ne se charge pas, une pizza dessinée la remplace (attribut `data-pizza`).
   Mini-pizzas disponibles : `margarita`, `jambon`, `royale`, `orientale`, `chorizo`, `viande`, `calzone`, `calzone3`, `napolitaine`, `piemontaise`, `parme`, `saisons`, `fromages`, `bolognaise`, `fromagere`, `mexicaine`, `locale`, `troisbecs`, `roquette` ; changer `data-seed` donne une autre disposition.
6. **Nom de domaine** : `https://lependolino.fr/` est supposé dans `index.html` (canonical, JSON-LD), `robots.txt` et `sitemap.xml`. Adapter au domaine réel.
7. **Fiche Google Business Profile** : nom, adresse, téléphone et horaires doivent être identiques à ceux du site (essentiel pour le référencement local).

## Modifier les styles

Après une modification des classes dans `index.html`, `404.html`, `js/main.js` ou `src/input.css`, régénérer la feuille de style depuis ce dossier :

```sh
npx tailwindcss@3.4.17 -i src/input.css -o css/style.css --minify
```

Couleurs : `cream`, `mozza`, `tomato`, `basil`, `charcoal`, `copper` (+ variantes). Polices : `font-script` (Kaushan Script, logo), `font-display` (Playfair Display), `font-sans` (Plus Jakarta Sans), `font-hand` (Caveat, notes manuscrites), `font-board` (Oswald, tableau des départs).
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
