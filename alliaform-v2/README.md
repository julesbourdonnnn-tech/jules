# AlliaForm — version 2

Deuxième proposition pour le site **[alliaform.fr](https://www.alliaform.fr)**, à comparer avec la première (dossier `alliaform/`). Mêmes informations, même sérieux, mais une tout autre personnalité.

## L'intention

Ne pas ressembler à un site « généré » : pas de cartes arrondies, d'ombres portées, d'icônes dans des pastilles ni de dégradés. À la place, la rigueur d'une mise en page éditoriale, celle d'un magazine ou d'une institution culturelle bordelaise comme le CAPC voisin :

- **Une grille de 12 colonnes et des filets** : chaque section commence par un trait fin, son numéro et son nom dans la marge, son titre à droite.
- **Deux polices qui se répondent** : Schibsted Grotesk, une linéale de presse, pour les titres ; Newsreader, une serif de lecture, pour les textes.
- **Encre, pierre et une seule couleur**, le vermillon : le soleil du dessin, les numéros de section, les heures.
- **Un dessin à l'encre fait pour le lieu** : les façades des quais des Chartrons, le tram, la Garonne et, au loin, le pont Chaban-Delmas.
- **Le concret plutôt que les slogans** : les plans des salles, le détail coté d'une place (« un mètre de table par personne »), le déroulé d'une journée, les prix alignés comme sur une carte.

## Ce que contient la page

| Section | Contenu |
|---|---|
| Accueil | « Quatre salles pour former à Bordeaux. », adresse, tram, date d'ouverture, le dessin des quais |
| 01 Les salles | Les deux formats (12 et 25 places) en très grands chiffres, leurs plans, puis la fiche technique et le détail coté d'une place |
| 02 Une journée ici | La frise de la journée (8 h – 18 h). Un repère indique l'heure qu'il est à Bordeaux, en semaine |
| 03 Tarifs | La carte des prix, avec la demi-journée et la formule déjeuner |
| 04 Centre d'examen | TOEFL, TOEIC, GMAT et certifications Pearson VUE, avec les liens d'inscription officiels |
| 05 Organismes de formation | Logistique et administratif, accompagnement commercial, examens et concours |
| 06 Depuis 2012 | L'histoire en un paragraphe, puis les dates clés |
| 07 Venir | Tram B, tram C, parking, accessibilité, plan OpenStreetMap en noir et blanc |
| 08 Questions | Les questions fréquentes, toutes visibles |
| 09 Contact | **Une lettre à compléter** : « Je m'appelle…, je cherche… pour… ». L'estimation se calcule en direct et la lettre devient un e-mail prêt à envoyer |

Comme la version 1 : site 100 % statique, aucun cookie, polices hébergées sur le site, accessibilité vérifiée (axe : 0 erreur), données structurées Google, redirection des anciennes adresses WordPress.

## ✅ À vérifier avant la mise en ligne

Les mêmes points que la version 1 (voir `alliaform/README.md`) : **tarifs**, **examens proposés**, **accès**, **mentions légales** (numéro de TVA calculé à partir du SIREN). Le logo de cette version est purement typographique (« AlliaForm » en Schibsted Grotesk) ; l'icône est un « A. » avec un point vermillon.

## Mise en ligne (Cloudflare)

Cette version a son propre Worker, **« alliaform-v2 »** : on peut publier les deux versions sur des adresses provisoires pour les comparer, puis brancher `alliaform.fr` sur celle qui est retenue.

1. Cloudflare → Workers & Pages → Créer → Importer un dépôt Git → `jules`, **répertoire racine = `alliaform-v2`**, commande de déploiement `npx wrangler deploy`.
2. Version retenue : retirer les `//` devant le bloc `routes` de son `wrangler.jsonc` (et seulement de celui-là).

À la main, depuis ce dossier : `npx wrangler deploy`.

## Voir le site en local

```bash
cd alliaform-v2
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

## Modifier

| Quoi | Où |
|---|---|
| Textes, questions, coordonnées | `index.html` |
| Tarifs | section « Tarifs » de `index.html`, les « À partir de » des deux salles, les `Offer` des données structurées, et `js/main.js` (constantes `ROOMS` et `LUNCH`) |
| Couleurs, polices, grille | variables en haut de `css/style.css` |
| Dessin des quais | `assets/quais-gravure.svg` |
| Plans des salles | dessins SVG directement dans `index.html` |
