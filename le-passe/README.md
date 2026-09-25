# Le Passe — site web

Site vitrine du **Passe**, le studio de création de sites web pour restaurants de Jules Bourdon.
Comme Nuits Singulières, le site est **100 % statique** (HTML, CSS, JavaScript) : pas de base de données, hébergement gratuit, modifiable avec un simple éditeur de texte.

- 🧭 **L'histoire et la marque** : [HISTOIRE.md](HISTOIRE.md)
- 📈 **Le plan d'action commercial** : [STRATEGIE.md](STRATEGIE.md)
- 🎨 **La charte graphique** : page `identite.html` (logo, couleurs, polices, ton, carte de visite, signature e-mail)

## Ce que contient le site

| Page | Rôle |
|---|---|
| `index.html` | L'accueil : le constat, l'histoire du passe, ce que fait un bon site, **la carte des offres**, la mise en place, les réalisations, la calculette « L'addition », les questions, et le formulaire « Le bon » |
| `demos/maison-garance/` | Démo d'un bistrot de saison imaginaire : ardoise du jour, carte avec filtres et allergènes, « ouvert maintenant » calculé en direct, version anglaise, réservation avec créneaux |
| `demos/brasa/` | Démo d'un grill imaginaire : commande à emporter avec panier, bons cadeaux personnalisés, agenda des soirées |
| `identite.html` | La charte de marque (non indexée par Google) |
| `mentions-legales.html` | Mentions légales et données personnelles |
| `404.html` | Page d'erreur « Cette assiette n'est jamais sortie » |

Détails soignés : bon de commande en forme de ticket de cuisine, tampon « ENVOYÉ », téléphone qui affiche la vraie démo, bandeau défilant, apparitions au défilement (désactivées si le visiteur préfère moins d'animations), bouton « Passer commande » fixé en bas sur mobile, données structurées Google (`ProfessionalService`, `FAQPage`), image de partage pour les réseaux.

**Polices hébergées sur le site** (dossier `fonts/`) : aucune requête vers Google ni vers un autre service, donc plus rapide et sans souci RGPD. C'est aussi un argument à vendre à tes clients.

## ✅ À faire avant de mettre en ligne

1. **Coordonnées** dans `js/config.js` : téléphone, WhatsApp, Instagram, zone de déplacement. L'e-mail est provisoirement `contact@nuitsinguliere.com` (il fonctionne déjà) : remplace-le par `bonjour@<ton-domaine>` dès que le domaine est acheté.
2. **Mentions légales** dans `js/config.js` : `siret`, `address`, `tvaNote`. **Obligatoire** dès que tu vends (voir `STRATEGIE.md`, section 1).
3. **Nom de domaine** : le site est écrit pour `lepasse.studio` (à vérifier et acheter). Si tu en choisis un autre, remplace `lepasse.studio` partout (rechercher-remplacer dans le dossier `le-passe/`) : `index.html`, `robots.txt`, `sitemap.xml`, `identite.html`, `wrangler.jsonc`.
4. **Ton histoire** : ajoute deux ou trois faits vrais de ton parcours et une photo de toi dans la section « L'histoire » de `index.html` (voir `HISTOIRE.md`, « À personnaliser »).
5. **Tes prix** : ils sont dans la section `#carte` de `index.html` (et répétés dans les données structurées en haut du fichier, et dans la calculette de `js/main.js`, constante `OFFERS`). Ce sont des propositions cohérentes avec le marché des indépendants : ajuste-les librement.

## Mise en ligne (Cloudflare)

Le site a **son propre Worker Cloudflare, « le-passe »**, séparé de Nuits Singulières (le dossier `le-passe/` est exclu de nuitsinguliere.com par le `.assetsignore` à la racine).

- **Automatique** : la GitHub Action « Le Passe » (`.github/workflows/le-passe.yml`) publie le site à chaque modification du dossier `le-passe/` sur la branche principale du dépôt. Elle utilise les mêmes secrets que le reste du dépôt (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). L'adresse provisoire s'affiche dans le journal : `https://le-passe.<ton-compte>.workers.dev`.
- **À la main** : depuis le dossier `le-passe/`, `npx wrangler deploy`.
- **Nom de domaine** : une fois acheté sur Cloudflare, retire les `//` devant le bloc `routes` de `wrangler.jsonc`.

### Recevoir les demandes du formulaire « Le bon »

Sans rien configurer, le formulaire ouvre un **e-mail pré-rempli** chez le visiteur : aucune demande n'est perdue, mais il doit cliquer sur « Envoyer ». Pour que les demandes arrivent directement :

1. **Stockage** : Cloudflare → Stockage et bases de données → KV → créer `le-passe-demandes`, puis coller son identifiant dans `wrangler.jsonc` (bloc `kv_namespaces`, retirer les `//`).
2. **Alerte sur ton téléphone** (conseillé) : installe l'application gratuite **ntfy**, abonne-toi à un sujet au nom difficile à deviner (ex. `lepasse-jules-8f3k2`), puis dans Cloudflare → Workers → le-passe → Paramètres → Variables, ajoute `NOTIFY_URL` = `https://ntfy.sh/lepasse-jules-8f3k2`. Chaque nouveau bon sonne sur ton téléphone. (Une adresse de webhook Discord ou Slack fonctionne aussi.)
3. **Export** : ajoute un secret `LEADS_KEY` (un mot de passe), puis ouvre `https://<ton-site>/api/demandes.csv?key=<LEADS_KEY>` : toutes les demandes dans un fichier à ouvrir avec Excel.

## Voir le site en local

```bash
cd le-passe
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

(En local, le formulaire ouvre l'e-mail pré-rempli, c'est normal.)

## Modifier

| Quoi | Où |
|---|---|
| Coordonnées, SIRET, TVA | `js/config.js` |
| Textes, offres, prix, questions | `index.html` |
| Couleurs, polices, espacements | variables en haut de `css/style.css` |
| Calculette (prix de référence) | `js/main.js`, constante `OFFERS` |
| Logo | `assets/*.svg` (vectoriels) et `assets/*.png` |
| Captures des réalisations | `assets/demos/*.jpg` |
| Démos | un seul fichier par démo : `demos/<nom>/index.html` |

### Ajouter une vraie réalisation
Remplace une carte de la section `#realisations` de `index.html` : capture d'écran du site du client dans `assets/demos/` (1 200 × 800 px, en JPG), le nom, deux lignes de description, et le lien. Garde Nuits Singulières : c'est ta meilleure preuve technique.

### Partir d'une démo pour un client
Copie `demos/maison-garance/` (ou `demos/brasa/`), renomme, retire la barre « Démo », change les couleurs (variables en haut du fichier), les textes, la carte (constante `MENU`), l'ardoise (`ARDOISE`) et les horaires (`HOURS`). Remplace les illustrations d'assiettes par les photos du restaurant.

## Structure

```
le-passe/
  index.html            Accueil
  identite.html         Charte de marque
  mentions-legales.html
  404.html
  css/style.css         Styles (couleurs et polices en haut)
  js/config.js          ← tes coordonnées et mentions légales
  js/main.js            Menu, calculette, formulaire
  fonts/                Polices hébergées sur le site
  assets/               Logo (SVG, PNG), icônes, image de partage, captures
  demos/                Maison Garance, Brasa
  worker/index.js       Réception des demandes du formulaire
  wrangler.jsonc        Configuration Cloudflare
  HISTOIRE.md           La marque et l'histoire
  STRATEGIE.md          Le plan d'action commercial
```
