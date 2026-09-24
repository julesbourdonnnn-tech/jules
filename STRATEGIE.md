# Plan d'action : gagner des commissions

Le modèle est simple : un visiteur découvre un lieu sur le site, clique sur **« Voir les disponibilités »**, réserve sur Booking.com… et tu touches une commission, **sans surcoût pour lui**. Aucune vente aux hôtels, aucun abonnement.

```
 Google + Instagram + newsletter  ──►  visiteurs  ──►  fiche d'un lieu  ──►  clic Booking  ──►  réservation = commission
```

Tout se joue donc sur deux leviers : **amener du monde** et **donner envie de cliquer**.

---

## 1. Brancher l'affiliation

1. Termine ton inscription sur **CJ** (formulaire W-8BEN, paiement en euros, IBAN) et postule au programme **Booking.com**.
2. Une fois accepté, récupère ton identifiant d'affiliation et envoie-le-moi (ou colle-le dans `js/config.js`, champ `booking.aid`) : il sera ajouté automatiquement à **tous** les boutons de réservation du site.
3. Chaque lien porte déjà un **libellé de suivi** (`site-web-<provenance>-<lieu>`) : dans ton tableau de bord, tu verras quel lieu et quel canal (Instagram, newsletter, Google) rapportent.

> Si Booking refuse au début, c'est fréquent pour un site neuf : redemande après 1 à 2 mois, avec du trafic et quelques guides publiés.

Autres programmes à ajouter plus tard (plus de chances de toucher une commission) : Expedia / Hotels.com, Agoda, Trip.com, ou des plateformes qui regroupent plusieurs marques (Awin, Travelpayouts).

---

## 2. Amener des visiteurs

### Google (le plus rentable sur la durée)
- Déclare `https://ton-domaine/sitemap.xml` dans la **Google Search Console**.
- Chaque lieu a sa page, chaque thème son guide : plus il y a de lieux et de guides, plus Google t'envoie de monde. Objectif : **60 à 100 lieux** et **20 guides**.
- Les guides qui marchent le mieux : géographiques (« près de Paris », « en Bretagne ») et par occasion (« Saint-Valentin », « anniversaire », « avec jacuzzi privatif »).

### Instagram
| Jour | Format | Contenu |
|---|---|---|
| Lundi | Carrousel | Un lieu coup de cœur (généré par le Studio) |
| Mercredi | Carrousel | Un top : « 5 cabanes à moins de 2 h de Paris » |
| Vendredi | Carrousel | Idée week-end : un lieu + quoi faire autour |
| Tous les jours | Story | Sondage « Tu dormirais où ? », lien vers le site |

- Lien en bio : `https://ton-domaine/liens.html?src=instagram`.
- Tague l'établissement et demande-lui de repartager : c'est gratuit et son audience est déjà intéressée.
- Pense aux dates clés : Saint-Valentin, fête des mères, ponts de mai, vacances scolaires, Noël.

### Newsletter
- Compte **Brevo** gratuit, une lettre par semaine avec 3 lieux (générée par le Studio, onglet Newsletter).
- Les liens portent `src=newsletter` : tu sais exactement ce qu'elle rapporte.

---

## 3. Donner envie de cliquer
- Des **photos superbes** et des descriptions qui font rêver : c'est ce qui déclenche le clic.
- Des lieux **réservables sur Booking** en priorité : un lieu absent de Booking ne rapporte rien (le bouton mène alors à une recherche).
- Quand ton identifiant est actif, renseigne pour chaque lieu le lien exact de sa fiche Booking (champ `bookingUrl` dans `js/hotels.js`) : moins de clics pour le visiteur, plus de réservations.

---

## 4. Règles à respecter (France)
- **Liens affiliés** : mention visible sur le site (déjà en pied de page et sur la page lien en bio).
- **Photos** : uniquement des photos autorisées par les établissements (demande-leur par e-mail, ils acceptent presque toujours) ou libres de droits.
- **Newsletter (RGPD)** : consentement à l'inscription et lien de désinscription dans chaque e-mail (déjà prévu).
- **Déclaration** : déclare tes commissions (micro-entreprise conseillée dès que ça devient régulier).

---

## 5. Les chiffres à suivre chaque mois
| Indicateur | Où | Pourquoi |
|---|---|---|
| Visiteurs du site | Plausible ou Cloudflare Web Analytics | ton audience |
| Clics « Voir les disponibilités » | Plausible (objectif « Réservation ») | tes commissions futures |
| Réservations et commissions | tableau de bord CJ / Booking, colonne *label* | quel lieu et quel canal rapportent |
| Abonnés Instagram et newsletter | Instagram, Brevo | ton audience fidèle |
