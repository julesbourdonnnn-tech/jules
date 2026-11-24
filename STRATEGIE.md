# Plan d'action : un site de conseil d'hôtelier

Nuits Singulières est le carnet de conseils de Jules Bourdon, hôtelier dans le luxe en France et à l'étranger. **Pas d'argent en jeu** : ni commission, ni publicité, ni paiement des établissements. L'objectif est double :

1. **Aider les voyageurs** à choisir une nuit qui sort de l'ordinaire, avec un regard de professionnel.
2. **Servir de carte de visite** pour contacter les établissements et tester leurs chambres.

```
 Repérer un lieu  ──►  fiche « Repéré »  ──►  contact avec l'établissement  ──►  séjour test  ──►  avis « Testé »
```

---

## 1. Démarcher les établissements

- Les modèles d'e-mails sont dans `demarchage/modele-email.md` : premier contact, proposition de séjour test, remerciement.
- Joins toujours le lien de la page **Vous êtes un établissement ?** : `https://nuitsinguliere.com/professionnels.html`.
- Commence par les lieux **déjà présents sur le site** : tu peux leur montrer leur fiche, c'est concret et flatteur.
- Demande l'**autorisation d'utiliser leurs photos** (garde l'e-mail de réponse) : c'est la seule zone grise actuelle du site.
- Tiens un petit tableau de suivi : établissement, date d'envoi, réponse, séjour prévu.

## 2. Tester et publier un avis

1. Pendant le séjour, remplis la grille `demarchage/grille-de-test.md` (notes sur 10, points forts et faibles, conseil du pro).
2. Envoie-la-moi : j'ajoute le champ `review` à la fiche (ou fais-le toi-même, l'exemple est en haut de `js/hotels.js`).
3. La fiche affiche alors l'avis en tête de page, et le lieu reçoit le badge **« ✓ Testé »** partout sur le site.
4. Envoie le lien à l'établissement pour le remercier : il le partagera souvent.

## 3. Faire connaître le site

### Google (le plus important sur la durée)
- Déclare `https://nuitsinguliere.com/sitemap.xml` dans la **Google Search Console**.
- Chaque lieu a sa page, chaque thème son guide. Les **avis testés** sont le meilleur contenu possible pour Google : un vrai séjour, signé par un professionnel.
- Guides de saison à préparer à l'avance : Saint-Valentin (dès janvier), fête des mères, ponts de mai, été, automne, Noël et Nouvel An.

### Instagram
- Un séjour test = un carrousel (le Studio du site génère les visuels) + quelques stories pendant le séjour.
- Tague l'établissement : il repartage souvent, son audience est déjà intéressée.
- Lien en bio : `https://nuitsinguliere.com/liens.html?src=instagram`.

### Newsletter
- Compte **Brevo** gratuit, une lettre par semaine ou par mois avec tes derniers avis (onglet Newsletter du Studio).

---

## 4. Règles à respecter (France)
- **Séjour offert = mention obligatoire** (loi du 9 juin 2023 sur l'influence commerciale) : `invited: true` dans l'avis affiche la mention automatiquement.
- **Avis libres** : ne jamais soumettre un avis à la relecture de l'établissement, ni accepter de contrepartie pour une meilleure note.
- **Photos** : uniquement des photos autorisées par les établissements, ou les tiennes.
- **Newsletter (RGPD)** : consentement à l'inscription et lien de désinscription dans chaque e-mail (déjà prévu).

---

## 5. Les chiffres à suivre chaque mois
| Indicateur | Où | Pourquoi |
|---|---|---|
| Visiteurs du site | Cloudflare (mesure d'audience intégrée) ou Plausible | ton audience |
| Pages trouvées sur Google | Google Search Console | le référencement progresse-t-il ? |
| Établissements contactés / séjours tests | ton tableau de suivi | ton rythme de tests |
| Abonnés Instagram et newsletter | Instagram, Brevo | ton audience fidèle |
