---
name: ns-eclaireur
description: Éclaireur de Nuits Singulières (nuitsinguliere.com) - chaque mois, repère de nouveaux établissements vraiment singuliers en France, prépare un dossier de candidats pour Jules, puis crée les fiches (1 à 3 par mois) des lieux que Jules a choisis. Utiliser pour la recherche mensuelle de nouveaux lieux ou quand Jules valide des candidats. Ne concerne pas maisons/ ni le-passe/.
---

# Éclaireur : trouver les prochaines adresses

Objectif : **1 à 3 nouveaux établissements par mois**, choisis par Jules. La sélection fait la valeur du site (« des adresses choisies une à une ») : tu proposes, **Jules décide**.

## Étape 1 (début de mois) : le dossier de candidats

1. Regarde ce qui manque sur le site : `node scripts/veille.js etat` et la répartition par région, type (`js/hotels.js`, `window.TYPES`) et budget. Privilégie les régions, ambiances et budgets peu représentés, et les idées de saison (escapades d'hiver, printemps, été).
2. Cherche sur le web 4 à 6 lieux **vraiment singuliers** en France : architecture, histoire, cadre ou expérience qu'on ne trouve pas ailleurs (cabane, phare, troglodyte, château, bulle, bateau, refuge, lieu d'architecte…). Pas de « bel hôtel » banal.
3. Pour chacun, vérifie : qu'il est **ouvert** et a un **site officiel** ; des avis clients récents bons (note globale, pas de scandale) ; qu'il n'est **pas déjà sur le site** (cherche son nom et sa ville dans `js/hotels.js`) ; des photos de qualité sur son site officiel.
4. Présente le dossier à Jules :
```
🧭 Éclaireur – candidats de décembre (choisis-en 1 à 3)
1. Nom (ville, région) · type · budget indicatif
   Pourquoi il est singulier, en 2 phrases. Site officiel : … · Avis : 4,7/5 (Google, 900 avis)
   Il comblerait : … (région ou ambiance peu présente sur le site)
```
Puis **attends la réponse de Jules** (il écrit dans cette conversation, par exemple « je prends 1 et 3 »). Ne crée aucune fiche sans son choix.

## Étape 2 (après le choix de Jules) : créer les fiches

Le choix de Jules vaut accord pour publier ces fiches. Pour chacune :
1. **Fiche** dans `js/hotels.js`, au même format que les fiches existantes (id en minuscules avec tirets, name, tagline, city, department, region, env, type, budget, lat, lng, address, description en 2 paragraphes, highlights, amenities, rooms, forYou, notForYou, website, tags vérifiés). Voix de Jules à la première personne, ton de la compétence `ns-ecriture-blog`. C'est un **repérage** : pas de `review`, pas de note, pas de coup de cœur. Uniquement des faits vérifiés (site officiel, sources fiables) ; jamais d'invention.
2. **Photos** : ajoute l'établissement dans `data/photo-sources.json` avec **uniquement des pages de son site officiel**. Mets `photos: 0` dans la fiche pour l'instant. Publie (procédure atomique). L'Action GitHub « Photos » crée une planche `_review/<id>.jpg` et pousse sur les deux branches (attends son commit, puis `git merge --ff-only`).
3. Regarde la planche, choisis jusqu'à 6 photos qui montrent vraiment le lieu (pas de photo de la région, de logo ou de visuel publicitaire générique), écris-les dans `data/photo-selection.json`, publie. Après le téléchargement par l'Action, vérifie `assets/hotels/<id>/source.json` (domaine officiel uniquement), passe `photos` au bon nombre, puis `node scripts/build.js`, `node scripts/controle-site.js --vite`, et publie.
4. Prépare pour Jules **l'e-mail de présentation** à l'établissement (modèle dans `demarchage/modele-email.md`) : sa fiche vient d'être créée, demande d'autorisation écrite pour les photos, proposition de séjour test. Jules l'envoie lui-même depuis nuitssingulieres@gmail.com.
5. Compte rendu : liens des nouvelles fiches, et l'e-mail prêt à copier.

## Règles
- Jamais plus de 3 nouvelles fiches par mois.
- Photos : site officiel uniquement (jamais un blog, un concurrent, Booking, un office de tourisme).
- Ne touche à aucune autre fiche, à aucun avis, ni aux dossiers `maisons/` et `le-passe/`.
