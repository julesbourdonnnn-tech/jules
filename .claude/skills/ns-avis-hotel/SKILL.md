---
name: ns-avis-hotel
description: Critique hôtelier pour Nuits Singulières (nuitsinguliere.com, racine du dépôt). Utiliser pour écrire, réécrire ou relire un avis « Testé » de Jules Bourdon après un séjour, préparer les questions à lui poser au retour, noter un hôtel, ou rédiger la recommandation d'une fiche. Ne concerne pas les dossiers maisons/ ni le-passe/.
---

# Écrire un avis « Testé » qui donne envie

Un avis Nuits Singulières est un **récit de séjour signé par un hôtelier**. Il doit donner au lecteur l'envie d'y aller, et à l'hôtelier l'envie d'être le prochain testé. Ce n'est pas une liste « c'est bien / c'est pas bien ».

## 1. Avant d'écrire : récolter le vécu

Ne jamais inventer un fait du séjour (geste du personnel, plat mangé, activité faite, météo, vue). L'avis est signé par Jules : tout doit être vrai.
Si un détail manque, **poser les questions** à Jules, en français simple, en une seule liste :

- Dates, chambre exacte, nombre de nuits, séjour offert ou payé, lien éventuel avec l'hôtel (ancien employeur…).
- L'arrivée : première impression, accueil (prénom, geste marquant ?).
- La chambre : vue, volume, literie, salle de bain, le détail qui l'a marqué, ce qui manquait.
- La table : dîner pris sur place ? petit-déjeuner ? un plat ou un produit marquant ?
- Les espaces : spa, piscine, parc, bar… utilisés ou non.
- Le moment qu'il retient (celui qu'il raconterait à un ami).
- Ce qu'il a moins aimé, et le conseil qu'il donnerait (chambre à demander, saison, durée).
- Ses photos et l'autorisation pour celles de l'hôtel.

Compléter avec des **faits publics vérifiés** sur l'hôtel (histoire, nombre de chambres, nom du restaurant, équipements) via une recherche web ; écarter tout chiffre contradictoire entre sources. Les présenter comme des faits sur le lieu, pas comme du vécu.

Quand un récit a besoin d'un détail que Jules n'a pas donné, l'écrire **entre crochets dans le brouillon** et le lister à la fin (« à confirmer ») au lieu de le publier.

## 2. La structure (champs de `review` dans js/hotels.js)

| Champ | Rôle | Conseils |
|---|---|---|
| `title` | Titre de magazine | Une promesse d'expérience, 5 à 10 mots. « Changer d'époque à une heure de Paris ». Pas le nom de l'hôtel. |
| `lead` | Chapeau (lettrine) | 3 à 4 phrases au présent qui font entrer dans le lieu : un trajet, une porte, une image. Finir sur ce qui rend l'adresse unique. |
| `text` | 3 ou 4 parties `[intertitre, paragraphe]` | Intertitres narratifs (« La piscine, le vrai secret de la maison »), jamais « Le lieu / La chambre ». 70 à 110 mots chacune. |
| `moment` | « Le moment que je retiens » | Une seule image vécue, sensorielle, en une phrase. Doit être vraie. |
| `verdict` | Synthèse | Une phrase qui résume et nuance (« à condition de… »). |
| `scores` | Notes sur 10 | accueil, chambre, literie, table, service, valeur. Cohérentes avec le texte ; pas de 10. |
| `pros` / `cons` / `good2know` | Listes courtes | 3 à 5 éléments concrets. Les défauts restent écrits, avec tact et une solution. |
| `recommend` | Encadré « Ma recommandation » | `who`, `room`, `when`, `length`, `dontMiss` : une phrase utile chacun. |
| `tip` | Le conseil du pro | La phrase qu'un concierge glisserait à l'oreille. |
| `stay`, `date`, `invited`, `disclosure` | Transparence | `invited: true` affiche la mention « séjour offert » (loi du 9 juin 2023). |

## 3. Le style

- **Je**, présent de narration, phrases variées ; une image concrète par paragraphe.
- Montrer plutôt qu'affirmer : « on y fait de vraies longueurs » plutôt que « belle piscine ».
- Le regard de l'hôtelier fait la différence : accueil, attention au détail, cohérence du service, rapport qualité-prix, conseil de chambre. Le dire avec simplicité, sans jargon.
- Vendre en restant crédible : un vrai bémol bien amené rend tout l'éloge plus fort.
- À bannir : « niché », « havre de paix », « écrin », « véritable pépite », « idéalement situé », superlatifs vides, points d'exclamation, anglicismes inutiles, promesses invérifiables (« mes lecteurs adorent »).
- Mots corrects : « séjour offert », jamais « partenariat » ; « réserver en direct », jamais de lien d'affiliation.

## 4. Éthique (non négociable)

- Avis libre : jamais relu ni validé par l'hôtel, jamais de note contre une invitation.
- Le « coup de cœur du moment » dépend du lieu seul, jamais d'une invitation ; ne jamais le promettre.
- Tout lien particulier est déclaré dans `disclosure`.

## 5. Contrôle avant publication

1. Chaque fait vécu vient de Jules ; chaque fait public est sourcé.
2. Notes cohérentes avec le récit ; le bémol figure dans `cons` ou `good2know`.
3. `node scripts/build.js`, puis capture Playwright de `#avis` sur ordinateur (1280 px) et téléphone (390 px).
4. Montrer l'aperçu à Jules et lister ce qu'il doit confirmer. Publier seulement après son accord (voir la compétence ns-gestion-site).
