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

**E-mail de démarchage** (modèle 1 dans demarchage/modele-email.md) : expéditeur nuitssingulieres@gmail.com. Le premier e-mail est une **présentation, jamais une demande** (Jules trouve « forceur » tout ce qui pousse l'hôtel à inviter). Ordre : présentation courte de Jules et du site ; « J'ai consacré une fiche à [lieu] » avec une phrase personnelle sur ce qui le rend unique (mention du coup de cœur seulement s'il en fait déjà partie) et le lien ; invitation à regarder la fiche et à dire si elle convient (correction, nouveauté, accord ou autres photos) ; puis une seule phrase légère : « si un jour l'occasion se présente de venir passer une nuit chez vous, je pourrais vous consacrer un article et un véritable avis de professionnel, ce qui donne le plus envie à mes lecteurs de réserver, directement chez vous ». Pas de liste d'avantages, pas de « j'aimerais vivre », pas de promesse de coup de cœur ou de place dans un guide, jamais « flexible sur mes dates ». La mention « séjour offert » et la liberté de l'avis s'expliquent seulement quand l'hôtel propose un séjour. Environ 180 à 220 mots. Signature « Jules Bourdon / Fondateur | Nuits Singulières / https://nuitsinguliere.com ».

**Google (SEO)** : `<title>` de moins de 60 caractères avec le lieu et le type d'hôtel ; description de 140 à 155 caractères avec la promesse ; un seul H1 ; liens internes vers la fiche, le guide de la région et le coup de cœur.

## Relecture finale

Lire à voix haute : est-ce que Jules dirait ça à un ami ? Retirer un adjectif sur deux. Vérifier chaque fait. Montrer le texte à Jules avant publication.
