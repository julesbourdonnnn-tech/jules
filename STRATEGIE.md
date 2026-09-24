# Plan d'action : idées 1 et 8

Deux moteurs qui s'alimentent l'un l'autre :

```
 Instagram + newsletter  ──►  trafic  ──►  site  ──►  clics Booking (commission)
         ▲                                  │
         └──── contenu gratuit des hôtels ◄─┴──►  hôteliers qui paient pour être mis en avant
```

- **Idée 8 (audience)** : Instagram et la newsletter amènent des visiteurs. Plus tu as d'abonnés, plus ta mise en avant vaut cher.
- **Idée 1 (revenus)** : commissions Booking sur les réservations, plus abonnements des hôteliers (29 € ou 79 €/mois) et prestations ponctuelles (publication dédiée 150 €, newsletter dédiée 200 €).

Tous les tarifs se modifient dans `js/config.js`.

---

## Les outils (tous gratuits au départ)

| Besoin | Outil | Où c'est branché |
|---|---|---|
| Hébergement + formulaires | **Netlify** (formulaires gratuits jusqu'à 100 envois/mois) | automatique : newsletter et candidatures hôteliers |
| Envoi de la newsletter | **Brevo** (français, 300 e-mails/jour gratuits) | importer le CSV exporté de Netlify, coller le HTML du Studio |
| Paiement des hôteliers | **Stripe** → « Liens de paiement », abonnement mensuel | `plans.xxx.paymentLink` dans `config.js` |
| Statistiques | **Plausible** (≈ 9 €/mois, sans bandeau cookies) | `analytics.plausibleDomain` dans `config.js` |
| Programmation Instagram | **Meta Business Suite** (gratuit) | programmer les carrousels du Studio |
| Visuels | **Studio** du site : `studio.html` | voir ci-dessous |

Dans Plausible, crée les objectifs (« Goals ») : `Réservation`, `Site officiel`, `Téléphone`, `Newsletter`, `Formulaire`. Le site les envoie déjà, avec le nom de l'hôtel et la provenance (instagram, newsletter…).

---

## Le Studio (`studio.html`)

C'est ton atelier interne. Il n'est pas référencé sur Google et aucun lien du site n'y mène.

1. **Publication Instagram** : tu choisis un hôtel et le Studio crée un carrousel de 5 visuels (1080 × 1350) ou une story, plus la légende et le lien suivi. Pour un hôtel Premium, la mention « Collaboration commerciale » est cochée automatiquement.
2. **Newsletter** : tu choisis 3 hôtels et le Studio produit l'e-mail HTML prêt à coller dans Brevo, avec les liens suivis `src=newsletter`.
3. **Rapport hôtelier** : tu saisis les chiffres du mois (Plausible et Instagram) et le Studio rédige l'e-mail de bilan pour tes partenaires. C'est ce qui justifie leur abonnement.

> Les photos doivent autoriser l'export. Les photos Unsplash le permettent. Pour les photos fournies par les hôtels, mets-les dans le dossier `assets/` du site pour que le Studio puisse les exporter.

---

## Démarrage en 8 semaines

### Semaines 1 et 2 : les fondations
- [ ] Créer une **micro-entreprise** (gratuit sur autoentrepreneur.urssaf.fr). Il faut un SIRET pour facturer les hôteliers et toucher les commissions.
- [ ] Acheter le nom de domaine, mettre le site sur Netlify, remplir `config.js` et `mentions-legales.html`.
- [ ] Remplacer les 24 hôtels d'exemple par **30 vrais établissements**, en demandant leurs photos (e-mail n°1 ci-dessous).
- [ ] Créer le compte Instagram (compte professionnel), avec le lien en bio : `https://ton-domaine.fr/liens.html?src=instagram`.
- [ ] Demander l'inscription au programme d'affiliation Booking.

### Semaines 3 et 4 : la régularité
- [ ] Instagram : **4 carrousels par semaine et une story par jour** (voir le calendrier).
- [ ] Première newsletter, même avec 20 abonnés : la régularité compte plus que le nombre.
- [ ] Ajouter chaque hôtel publié en tête de `social.bioHotels`.

### Semaines 5 à 8 : la vente
- [ ] Contacter les hôtels qui ont le plus de clics (Plausible) avec l'e-mail n°2. Tu arrives avec des chiffres réels, c'est ton meilleur argument.
- [ ] Proposer l'offre de lancement : « Premium 1 mois offert », puis 79 €/mois.
- [ ] Envoyer le premier rapport mensuel à chaque partenaire (onglet Rapport du Studio).

---

## Calendrier Instagram type

| Jour | Format | Contenu |
|---|---|---|
| Lundi | Carrousel | Un hôtel coup de cœur (Studio) |
| Mardi | Story | Sondage « Tu dormirais où ? » entre 2 hôtels |
| Mercredi | Carrousel | Un **top thématique** : « 5 cabanes à moins de 2 h de Paris » |
| Jeudi | Reel | Vidéo de l'hôtel (demandée à l'hôtelier) ou diaporama du Studio en format story |
| Vendredi | Carrousel | « Idée week-end » : un hôtel + ce qu'on peut faire autour |
| Dimanche | Story | « La newsletter vient de partir » + lien |

Ce qui marche le mieux dans cette niche :
- **Les tops thématiques et géographiques**, que les gens enregistrent et partagent.
- **Les « enregistre pour plus tard »** : les enregistrements pèsent lourd dans l'algorithme.
- **Taguer l'hôtel** et lui demander de repartager. C'est gratuit, et leur audience est déjà intéressée.
- Quelques **hashtags ciblés** (le Studio en propose 5) plutôt que 30 génériques.
- Les **dates clés** : Saint-Valentin, fête des mères, ponts de mai, vacances scolaires, Noël (idées cadeaux).

---

## Modèles d'e-mails aux hôteliers

### E-mail n°1 : référencement gratuit (demande de photos)

> **Objet : [Nom de l'hôtel] sur Nuits Singulières**
>
> Bonjour,
>
> Je prépare Nuits Singulières, une sélection des hôtels les plus extraordinaires de France, et j'aimerais y présenter [nom de l'hôtel] : [une phrase précise sur ce qui t'a plu].
>
> Le référencement est gratuit. Auriez-vous 4 ou 5 photos (HD, libres de droits pour le web) et 2 ou 3 lignes sur ce qui rend votre lieu unique ? Je publierai aussi votre établissement sur notre Instagram @[compte], en vous identifiant.
>
> Belle journée,
> [Prénom] — [site]

### E-mail n°2 : proposer l'offre payante (après 1 à 2 mois)

> **Objet : [X] voyageurs ont cliqué pour réserver chez vous ce mois-ci**
>
> Bonjour,
>
> Petit bilan : ce mois-ci, votre fiche a reçu [X] visites et [Y] clics vers la réservation.
>
> Aujourd'hui ces clics partent vers Booking. Avec l'offre Partenaire (29 €/mois, sans engagement), votre site et votre téléphone apparaissent sur la fiche : les voyageurs peuvent réserver en direct, **sans commission**. Une seule réservation directe par mois rembourse largement l'abonnement.
>
> L'offre Premium (79 €/mois) ajoute une publication Instagram par mois, une présence dans la newsletter et en page d'accueil.
>
> Pour le lancement, je vous offre le premier mois. Voulez-vous que je l'active ?
>
> [Prénom]

---

## Règles à respecter (France)

- **Liens affiliés** : mention visible sur le site (déjà en pied de page et sur la page lien en bio).
- **Contenus payés** : la loi du 9 juin 2023 sur l'influence commerciale impose la mention **« Collaboration commerciale »** (ou « Publicité ») sur toute publication payée par une marque. Coche la case dans le Studio, et active aussi le label « Partenariat rémunéré » d'Instagram.
- **Classement influencé par le paiement** : le Code de la consommation impose de l'indiquer. C'est fait avec le badge « Partenaire », le pied de page et les mentions légales.
- **Newsletter (RGPD)** : consentement explicite (formulaire), lien de désinscription dans chaque e-mail (déjà dans le modèle), pas de revente des adresses.
- **Photos** : uniquement des photos fournies ou autorisées par les hôtels, ou libres de droits.
- **Facturation** : factures aux hôteliers avec la mention « TVA non applicable, art. 293 B du CGI » tant que tu restes en franchise de TVA.

---

## Les chiffres à suivre chaque mois

| Indicateur | Où | Pourquoi |
|---|---|---|
| Visiteurs du site | Plausible | ton audience |
| Clics « Réservation » | Plausible (objectif) | tes commissions futures |
| Réservations et commissions | tableau de bord Booking, colonne *label* | savoir quel canal rapporte (`site-web-instagram-…`, `site-web-newsletter-…`) |
| Abonnés Instagram et newsletter | Instagram, Brevo | ce qui fait monter le prix de ta mise en avant |
| Hôteliers payants | Stripe | ton revenu récurrent |

Exemple de calcul (pas une promesse) : 10 partenaires à 29 € et 5 Premium à 79 € rapportent 685 €/mois récurrents, avant les commissions Booking et les prestations ponctuelles.
