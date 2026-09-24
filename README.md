# Nuits Singulières

Site vitrine des hôtels les plus extraordinaires de France (cabanes, bulles, phares, châteaux, igloos…), avec liens d'affiliation vers Booking.com.

Le site est **100 % statique** (HTML, CSS, JavaScript). Pas de serveur, pas de base de données : on l'héberge gratuitement et on le modifie avec un simple éditeur de texte.

## Fonctionnalités

- **Accueil** : grande photo, barre de recherche (destination, ambiance, budget)
- **4 ambiances** : Ville, Campagne, Mer, Montagne
- **12 types d'expériences** : cabane perchée, bulle, château, troglodyte, phare, igloo, chalet, sur l'eau, yourte/tipi, lieu historique, design, atypique
- **Filtres** : texte, ambiance, type, budget maximum, tri (recommandés, prix, distance)
- **« Près de chez moi »** : le visiteur tape son adresse (autocomplétion via le service public d'adresses français, gratuit et sans clé) ou clique sur « Me localiser ». Les hôtels sont alors triés par distance, avec un filtre de rayon (50, 100, 200, 400 km). La position est mémorisée dans le navigateur et la distance s'affiche aussi sur chaque fiche.
- **Carte interactive** de tous les hôtels (OpenStreetMap), avec les prix sur les repères
- **Fiche hôtel** : galerie photo avec visionneuse plein écran, description, points forts, équipements, infos pratiques, carte, suggestions d'hôtels similaires, bouton de réservation (fixé en bas d'écran sur mobile)
- **Affiliation** : ton identifiant Booking est ajouté automatiquement à chaque lien. Tu peux aussi ajouter des boutons Expedia, Hotels.com ou « Site officiel ».
- **Référencement (SEO)** : titre et description propres à chaque fiche, données structurées `schema.org/Hotel`
- Liens partageables : les filtres sont dans l'URL (ex. `index.html?env=mer&max=200`)

## Voir le site en local

Double-clique sur `index.html`, ou pour que tout fonctionne (géolocalisation comprise) :

```bash
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

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

## Ajouter ou modifier un hôtel

⚠️ **Les 24 hôtels fournis sont des exemples fictifs** pour montrer le rendu. Remplace-les par de vrais établissements avant la mise en ligne.

Tout se passe dans `js/hotels.js`. Copie un bloc `{ ... },` et modifie-le :

| Champ | Exemple | Rôle |
|---|---|---|
| `id` | `"cabane-du-lac"` | identifiant unique, sans espaces ni accents (sert à l'URL) |
| `name`, `tagline` | | nom et phrase d'accroche |
| `city`, `department`, `region`, `address` | | localisation affichée |
| `env` | `"mer"` | `ville`, `campagne`, `mer` ou `montagne` |
| `type` | `"cabane"` | une clé de la liste `TYPES` en haut du fichier |
| `price` | `180` | prix « à partir de » par nuit, en € |
| `featured` | `true` | apparaît dans les « Coups de cœur » |
| `lat`, `lng` | `44.394`, `-1.163` | coordonnées GPS (clic droit sur Google Maps → cliquer sur les chiffres pour les copier) |
| `description` | `["Paragraphe 1", "Paragraphe 2"]` | texte de la fiche |
| `highlights`, `amenities` | `["Spa", "Piscine"]` | points forts et équipements |
| `rooms`, `checkIn`, `checkOut` | | infos pratiques |
| `images` | `["https://…jpg", …]` | photos, la première sert de couverture |
| `bookingUrl` | `"https://www.booking.com/hotel/fr/xxx.html"` | lien de la fiche Booking ; si vide, le site ouvre une recherche Booking avec le nom de l'hôtel |
| `partners` | `{ expedia: "https://…", direct: "https://…" }` | boutons de réservation secondaires (optionnels) |

### Photos : attention aux droits

Tu **n'as pas le droit** de copier les photos de Booking ou du site d'un hôtel sans autorisation. Solutions :
- demander à l'hôtel ses photos presse (ils disent presque toujours oui : c'est de la visibilité gratuite pour eux) ;
- utiliser l'API de contenu fournie par ton programme d'affiliation une fois accepté ;
- utiliser tes propres photos.

Les photos d'exemple viennent d'Unsplash. Si une photo ne charge pas, une image de remplacement s'affiche automatiquement.

## Personnaliser

- **Nom du site, e-mail** : `js/config.js` (et les balises `<title>` dans les fichiers `.html`)
- **Couleurs et polices** : variables en haut de `css/style.css`
- **Ambiances et types d'expériences** : `ENVIRONMENTS` et `TYPES` en haut de `js/hotels.js`
- **Mentions légales** : complète `mentions-legales.html` (obligatoire en France)

## Structure

```
index.html            Accueil + recherche + carte
hotel.html            Fiche hôtel (hotel.html?id=...)
mentions-legales.html
css/style.css
js/config.js          ← identifiants d'affiliation
js/hotels.js          ← la liste des hôtels
js/common.js          liens, géolocalisation, en-tête et pied de page
js/app.js             logique de l'accueil
js/hotel.js           logique de la fiche
```

## Prochaines étapes conseillées

1. Remplacer les exemples par 30 à 50 vrais hôtels, avec leurs liens Booking
2. Générer une vraie page HTML par hôtel pour un meilleur référencement Google (aujourd'hui les fiches sont construites en JavaScript)
3. Ajouter des pages « guides » (« 10 cabanes perchées à moins de 2 h de Paris ») : c'est ce qui attire le trafic Google
4. Ajouter la même chose pour les restaurants
