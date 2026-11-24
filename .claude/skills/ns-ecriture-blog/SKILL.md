---
name: ns-ecriture-blog
description: Plume et ligne éditoriale de Nuits Singulières (nuitsinguliere.com). Utiliser pour écrire ou relire tout texte du site ou autour du site dans la voix de Jules Bourdon : fiches d'hôtels, guides, page Qui suis-je, lettre mensuelle (newsletter), légendes Instagram, e-mails de démarchage aux hôtels, réponses aux questions des lecteurs, titres et descriptions pour Google. Ne concerne pas maisons/ ni le-passe/.
---

# La voix de Nuits Singulières

**Qui parle :** Jules Bourdon, fondateur de Nuits Singulières, hôtelier passé par des maisons 3, 4 et 5 étoiles. Site de conseil indépendant : ni commission, ni publicité, ni affiliation.
**Le ton :** un carnet d'hôtelier passionné, chaleureux et précis. On écrit à la première personne, comme un ami du métier qui conseille. Jamais commercial, jamais impersonnel.

## Principes

1. **Concret avant tout** : un chiffre, un lieu, un geste (« un phare de 1913 », « 50 mètres du château »). Les faits viennent de js/hotels.js ou d'une source vérifiée.
2. **Une idée par phrase**, phrases courtes, rythme varié. Lisible sur téléphone.
3. **Le conseil du pro** : chaque texte apporte quelque chose d'utile (quelle chambre, quelle saison, combien de nuits, piège à éviter).
4. **Vrai, toujours** : aucun vécu inventé, aucune affirmation invérifiable. Distinguer « repéré » (pas encore testé) et « testé ».
5. **Français soigné** : espaces avant « : ; ? ! », guillemets « », pas de majuscules inutiles, accents sur les capitales (« À »).

## Mots

- À bannir : niché, havre de paix, écrin, pépite, incontournable, idéalement situé, expérience unique (sans preuve), « n'attendez plus », points d'exclamation en série.
- Préférer : précis et sensoriel (bois clair, lumière du soir, le bruit des vagues) ; verbes d'action.
- Vocabulaire maison : « Le coup de cœur du moment », « Testé », « Repéré », « La lettre de Jules », « Réserver en direct ».
- Jamais : « partenaire », « sponsorisé », « meilleur prix », promesses de place dans un guide.

## Formats

**Fiche (js/hotels.js)** : `tagline` (une promesse, moins de 90 caractères), `description` (2 paragraphes : le lieu, puis l'expérience), `highlights` (3 points), `forYou` / `notForYou` honnêtes.

**Guide (js/guides.js)** : intro de 2 ou 3 phrases à la première personne qui pose l'envie, puis la sélection ; les adresses testées en premier ; un conseil pratique par adresse. Titre avec le mot-clé principal (« hôtel insolite près de Lyon ») et la promesse.

**Lettre mensuelle (Brevo)** : objet de moins de 45 caractères, une ouverture personnelle (où je suis allé ce mois-ci), 1 avis testé mis en avant, 2 ou 3 adresses repérées, 1 conseil de saison, signature « Jules ». Lien de désinscription obligatoire.

**Instagram** : première ligne qui accroche (l'image racontée), 3 à 5 lignes, le conseil, l'établissement tagué, mention « séjour offert » si c'est le cas, lien en bio.

**E-mail de démarchage** (modèles dans demarchage/modele-email.md) : expéditeur nuitssingulieres@gmail.com ; présentation courte, un paragraphe vraiment personnalisé sur ce qui rend le lieu unique et ce que Jules aimerait y vivre, les bénéfices (avis de professionnel vécu et signé, réservations en direct sans commission, article dans la lettre mensuelle, retours en privé), la mention « séjour offert » et la liberté de l'avis, la demande d'autorisation pour les photos, signature « Jules Bourdon / Fondateur | Nuits Singulières / https://nuitsinguliere.com ». Ne jamais dire que Jules est flexible sur ses dates. Ne jamais promettre le coup de cœur ni une place dans un guide en échange d'une invitation. Rester court (environ 250 mots).

**Google (SEO)** : `<title>` de moins de 60 caractères avec le lieu et le type d'hôtel ; description de 140 à 155 caractères avec la promesse ; un seul H1 ; liens internes vers la fiche, le guide de la région et le coup de cœur.

## Relecture finale

Lire à voix haute : est-ce que Jules dirait ça à un ami ? Retirer un adjectif sur deux. Vérifier chaque fait. Montrer le texte à Jules avant publication.
