# Raise a Squishy — Game Design Document

> **Document 02 : conception du jeu (GDD).** Version 1.0 du 1er novembre 2026. Statut : à valider par le propriétaire, puis base de la production.
> Documents liés : [`01-analyse-marche-tycoon.md`](01-analyse-marche-tycoon.md) (étude de marché, citée « Étude §x ») et [`03-decision-du-jury.md`](03-decision-du-jury.md) (concept final au §8, idées greffées au §6, faiblesses corrigées au §7, calendrier au §8.10, risques au §9).
> Modèle de format : le GDD de Comet Conga (`/home/user/jules/roblox-game/docs/02-game-design-document.md`), sa couche console (`07-console-ps5.md`) et les leçons de son rapport qualité (`06-rapport-qualite.md`).
> **Règle de lecture.** Chaque chiffre de ce document est une **valeur de départ décidée**, à placer telle quelle dans `src/shared/Config/*`. Les valeurs d'économie sont vérifiées par la simulation Lune du §4.24, qui bloque la publication si un jalon sort de sa tolérance. Ensuite, les données réelles peuvent ajuster ces valeurs sans toucher au code.

**Conventions**
- Distances en *studs*. Temps en secondes (s), minutes (min) ou heures (h). Horaires en **UTC**.
- `floor` = arrondi à l'entier inférieur. Les monnaies sont calculées par le serveur seulement.
- Les noms propres de l'univers (Raise a Squishy, Wobbleton, Plop, les noms d'espèces, BOOP RUSH, MEGA SQUISH, Grand Splorch, Squishydex, Jelly Moon…) restent en anglais dans les deux langues : c'est notre propriété intellectuelle. Les mots du quotidien sont traduits (§15).
- Clé de configuration entre crochets, par exemple [`Balance.Press.Cooldown`].
- « R » = nombre de Grand Splorch déjà faits par le joueur (son niveau de renaissance).
- **Au lancement** = la colonne « Au lancement » du §8.10 du jury. Tout le reste est dans la liste « Plus tard » (§17).

**Glossaire**

| Terme | Sens |
|---|---|
| **Squishy** (pl. squishies) | Créature en gelée à élever. Elle grossit seule et rapporte des pièces |
| **Ranch** | La base personnelle du joueur. Personne d'autre n'y entre jamais |
| **Wobbleton** | La ville pastel au centre de la carte, entourée des 16 ranchs |
| **Plop** | La mascotte. C'est aussi le nom de la première espèce (« ton petit Plop ») |
| **SPLORCH** (presser) | Appuyer sur un squishy : il s'écrase, rebondit et crache des pièces |
| **PERFECT** | Presser au sommet du rebond : bonus, jamais d'échec |
| **Dalle** (tile) | Pastille lumineuse au sol du ranch. On marche dessus pour acheter |
| **Tapis à Goûter** (Snack Mat) | Dalle qui fait grossir plus vite tous les squishies du ranch |
| **Cuve à Gelée** (Jelly Vat) | Machine gratuite qui fait naître des squishies au hasard (probabilités affichées) |
| **Bassin de Fusion** (Fusion Pool) | Deux jumeaux lancés dedans fusionnent ; le résultat peut fusionner encore (combo) |
| **Jumeaux** | Deux squishies de la même espèce avec le même nombre d'étoiles |
| **Pot à Pièces** (Coin Pot) | Le revenu passif s'y accumule ; on marche dessus pour encaisser |
| **Créature en fuite** (runaway) | Squishy personnel qui sort de ta Fontaine de Gelée toutes les 60 s |
| **Golden Wobbler** | Créature dorée partagée, lâchée 4 fois par heure dans la ville |
| **BOOP RUSH** | Événement de 90 s toutes les 10 min : on boope un nez par-dessus une clôture, le squishy s'enfuit en ville, tout le monde court |
| **Mode Rush / mode Cozy** | Chaque joueur choisit : participer au BOOP RUSH, ou rester tranquille |
| **Wild Wobbler** | Créature sans propriétaire lâchée par le serveur pendant le Rush, pour tous les joueurs |
| **MEGA SQUISH** | Un squishy géant atterrit sur la place ; tout le serveur le presse ensemble |
| **Jauge du serveur** (Wobble Meter) | Remplie par les actions de tous ; pleine = ×2 pour tout le serveur pendant 5 min |
| **Grand Splorch** | La renaissance (rebirth) : le plus gros squishy éclate en cadeaux pour tout le serveur |
| **Étagère à trophées** (Trophy Shelf) | Garde la taille record de chaque espèce, avec un petit bonus permanent |
| **Squishydex** | Le livre de collection : 26 espèces, 234 entrées de mutation, des badges d'étoiles |
| **Fame** (célébrité) | Score permanent gagné quand on est boopé, qu'on relâche un squishy, etc. Donne un bonus de revenu |
| **Meilleur Ami** (Best Friend) | Squishy choisi : jamais boopable, il te suit en ville |
| **Jelly Moon** (Lune de Gelée) | Le rendez-vous du samedi : mutations rares, Mythiques boopables, MEGA lunaire |

**Sommaire**

0. Fiche d'identité · 1. Vision, piliers, public, KPI · 2. Boucle de jeu et horloge commune · 3. Les 5 premières minutes · 4. Systèmes détaillés (monnaies, nombres géants, formules, raretés, mutations, dalles, presser, Pot, Cuve, Bassin, fuites, monture, Grand Splorch, Étagère, Squishydex, Fame, hors ligne, BOOP RUSH, MEGA SQUISH, jauge et Jelly Moon, simulation, plafonds) · 5. Contenu (26 espèces, fabrication, Plop, cosmétiques) · 6. Social et multijoueur · 7. Rétention · 8. Monétisation · 9. Juice, animation et sons · 10. Interface, commandes, vibrations et console · 11. Monde · 12. Architecture technique · 13. Sécurité des enfants · 14. Accessibilité · 15. Localisation · 16. Analytics · 17. Lancement et « Plus tard » · 18. Checklist de lancement · 19. Risques · 20. Questions ouvertes · Annexe A. Écarts avec le concept

---

## 0. Fiche d'identité

| Élément | Valeur |
|---|---|
| Titre | **Raise a Squishy** (titre de travail ; secours : *Squishy Ranch*). Aucun des deux n'est vérifié (§20) |
| Accroche | EN « Raise squishy jelly pets, grow them to a TRILLION… and make them sneeze at the neighbours! » ; FR « Élève des squishies tout mous, fais-les grossir jusqu'à 1 000 milliards… et fais-les éternuer chez les voisins ! » |
| Genre | Tycoon de créatures : croissance automatique + collection + fusion + renaissance, avec des poursuites amicales et des événements coopératifs de serveur |
| Joueurs | **16 par serveur** (`Players.MaxPlayers = 16`), **16 ranchs** |
| Plateformes | Téléphone d'abord (≈ 80 % des joueurs, chiffre de l'exercice 2024, Étude §6.1), PC, console (PS5 avec DualSense sur une télé, Xbox) dès le premier jour |
| Contrôles | Un seul bouton d'action selon le contexte (□ / E / gros bouton tactile), plus Bondir (R2 / Maj) et Monter (L2 / R) |
| Classification visée | **Minimal** au questionnaire de maturité (Mild au pire) ; éligible aux catalogues Roblox Kids et Select |
| Session cible | 15 à 30 min. Le rythme fixe (fuite 60 s, Rush 10 min, MEGA 30 min) pousse au-delà de 10 min (seuil des Creator Rewards) |
| Public | 6-14 ans au cœur, satisfaisant pour les ados et les adultes collectionneurs |
| Monétisation | 4 passes « Pour toujours » et 3 familles de produits **à résultat connu**. Aucun hasard payant, aucune pub vidéo |
| Code | Luau `--!strict`, Rojo, aucun travail manuel dans Studio. Estimation ≈ 12 000 lignes de jeu au premier passage, hors tests (Comet Conga a fini à 58 500 lignes après 6 tours de QA : prévoir large) |
| Contenu au lancement | 24 espèces (6 familles × 4) + 2 secrètes, 7 raretés, 9 mutations, 1 ville, 16 ranchs, 6 événements récurrents (créature en fuite, Golden Wobbler, BOOP RUSH, MEGA SQUISH, jauge du serveur, Jelly Moon) |
| Date visée | **Samedi 12 décembre 2026** (costume d'hiver). Repli : samedi 9 janvier 2027 si les portes de qualité ne sont pas vertes (§18) |

---

## 1. Vision, pitch, piliers, public, positionnement

### 1.1 Pitch

**Pitch court (page du jeu).** À Wobbleton, élève des squishies en gelée qui grossissent toutes seules, presse-les pour faire jaillir des pièces, fusionne les jumeaux en géants… et toutes les 10 minutes, fais-les éternuer chez les voisins !

**Pitch long.** Chaque joueur a son ranch, au bord d'une ville pastel posée sur des collines de bonbons. Ses squishies grossissent de +1 chaque seconde et rapportent des pièces. Le joueur les presse (SPLORCH !) pour un gros jet de pièces, achète des dalles qui construisent son ranch en rebondissant, fait naître de nouvelles espèces dans sa Cuve à Gelée et lance les jumeaux dans le Bassin de Fusion pour des combos géants. Quand un squishy est assez gros, il pose une selle dessus et rebondit à travers la ville.

Toutes les 10 minutes, la sirène du **BOOP RUSH** retentit. Les joueurs qui l'ont choisi boopent le nez des squishies curieux par-dessus les clôtures : ATCHOUM, le squishy saute et rebondit dans la ville, et tout le monde lui court après. Celui qui l'attrape gagne un bébé de cette créature. Le propriétaire ne perd jamais rien : il récupère son squishy, gagne de la Fame et des pièces. Toutes les 30 minutes, un **MEGA SQUISH** grand comme une maison atterrit sur la place et tout le serveur le presse ensemble. Et quand le squishy d'un joueur devient énorme, il l'envoie au-dessus de la place : le **Grand Splorch** fait pleuvoir des cadeaux sur tout le serveur. Chaque samedi, la **Jelly Moon** apporte des mutations rares.

### 1.2 Piliers de design

Chaque fonctionnalité doit servir au moins un pilier. Ce qui n'en sert aucun est coupé.

| # | Pilier | Ce que ça impose |
|---|---|---|
| P1 | **Tout est mou et satisfaisant** | Chaque geste a un retour « ASMR » : écrasement, rebond, son un peu différent à chaque fois, pièces qui volent. Presser est le revenu actif |
| P2 | **On ne perd jamais rien** | Pas de vol. Le propriétaire gagne toujours quelque chose quand on boope son squishy. Le rebirth fait des cadeaux à tout le monde. Personne n'entre jamais dans le ranch d'un autre |
| P3 | **Le serveur vit au même rythme** | Une horloge UTC commune à tous les serveurs : fuite toutes les 60 s, Golden Wobbler 4 fois par heure, BOOP RUSH toutes les 10 min, MEGA SQUISH toutes les 30 min, Jelly Moon le samedi. Un seul grand spectacle à la fois |
| P4 | **La taille se voit** | Échelle logarithmique : un squishy de taille 1 million est 4,6 fois plus gros qu'un nouveau-né, et ça se voit de loin. Les nombres géants restent lisibles à 3 m |
| P5 | **Un bouton, trois écrans** | Une action contextuelle unique (□ / E / gros bouton). Tout se fait au téléphone, au clavier et à la manette, sans glisser-déposer, sans curseur |
| P6 | **Juste, sûr, sans bug** | Autorité du serveur sur tout. Monétisation déterministe. Peu de systèmes, chacun poli. Ce que le joueur voit est ce que le serveur vérifie |

### 1.3 Public cible

Repère de l'étude : comptes à âge vérifié, 34 % de moins de 13 ans, 37 % de 13-17 ans, 29 % de 18 ans et plus (Étude §2).

| Persona | Profil | Ce qu'il cherche | Ce que Raise a Squishy lui donne |
|---|---|---|---|
| **Léa, 8 ans**, téléphone, joue avec son grand frère | Lit peu, aime les animaux mignons | Des créatures à câliner, des récompenses fréquentes, ne pas se faire embêter | Un seul bouton, première récompense à 10 s, mode Cozy, ranch où personne n'entre, Meilleur Ami qui la suit |
| **Noah, 12 ans**, PS5 au salon avec deux amis | Aime courir, filmer, battre ses amis | Poursuites, combos, gros nombres | BOOP RUSH, bond à visée automatique, combos ×5, monture, classements de la semaine |
| **Sam, 24 ans**, PC le soir | Collectionneur, optimise | Profondeur, objectifs longs | 260 tampons de Squishydex, mutations rares, étoiles, Étagère à trophées, Grand Splorch à l'infini |

### 1.4 Positionnement marché

| Constat de l'étude | Réponse de Raise a Squishy |
|---|---|
| La boucle « obtenir une unité → revenu passif → améliorer → rebirth + interaction sociale » a fait les records 2025-2026 (Étude §4.1) | On garde la boucle entière. Le verbe social devient **booper et poursuivre**, pas voler |
| Le vol fait fuir quand il fait perdre : Grow a Garden 2 effondré, clips d'enfants en pleurs (Étude §5.2) | Rien n'est jamais pris. La poursuite donne une **copie bébé** au gagnant, et le propriétaire gagne aussi |
| Les créatures originales hors œufs sont un sous-genre libre (Étude §4.5) | 26 espèces à nous, en gelée, faites en formes simples. Pas d'œufs, pas de brainrot, pas de licence |
| Chevaucher ses créatures (Ride A Pet) et « +1 chaque seconde » (+1 Speed) attirent (Étude §2.2) | Monture dès 4 min ; la taille grossit de +1/s et se voit |
| L'algorithme note la fidélité à 28 jours, l'abandon en première partie et les jours entre amis (Étude §6.2) | Récompense à 10 s, croissance hors ligne visible, Plop à nourrir (jours au total), ranchs voisins, bonus d'amis |
| Les records viennent d'événements à heure fixe et de la mise à jour du samedi (Étude §4.2) | Horloge UTC commune, Jelly Moon chaque samedi, une espèce de plus chaque semaine sous forme de données |
| Le chat demande une vérification d'âge (Étude §6.3) | Tout marche sans chat : emotes, mécaniques, bannières |
| Achats trompeurs dans 14 des 15 jeux les plus rentables étudiés (Étude §4.4) | Résultat connu, prix en Robux clairs, aucun faux minuteur, aucune proposition dans les 10 premières minutes |

**Ce que le jeu n'est pas.** Pas de base à défendre, pas d'objet volé, pas d'œuf payant, pas de tapis roulant d'achat, pas de mème. Le BOOP RUSH n'a lieu que dans la ville, jamais dans un ranch.

### 1.5 Objectifs chiffrés (KPI)

Repères GameAnalytics 2026 : médiane J1 10,3 % / J7 1,6 % / J30 0,5 % ; top 1 % ≈ 22,2 / 9,1 / 4,7 % (Étude §4.3).

| KPI | Seuil de lancement | Objectif | Alerte |
|---|---|---|---|
| Rétention J1 | ≥ 15 % | 18-22 % | < 12 % |
| Rétention J7 | ≥ 5 % | 6-9 % | < 3 % |
| Rétention J30 | ≥ 2 % | 3-4,7 % | < 1 % |
| Session moyenne | ≥ 12 min | ≥ 15 min | < 10 min |
| Abandon avant la première pression | ≤ 5 % | ≤ 3 % | > 8 % |
| Abandon avant le premier Grand Splorch (joueurs de la 1re session restés ≥ 5 min) | ≤ 35 % | ≤ 25 % | > 45 % |
| **Départ dans les 2 min après un premier boop subi** | pas plus de 1,5 fois le taux de départ des autres joueurs au même moment | ≤ 1,2 fois | > 2 fois (déclenche le §16.4) |
| Part des joueurs en mode Rush | ≥ 40 % | 55-75 % | < 30 % |
| Réussite du MEGA SQUISH | 75-85 % | 80 % | < 65 % ou > 92 % |
| Conversion payeurs | 1,5 % | 2-3 % | — |
| Sessions avec au moins un ami Roblox sur le serveur | ≥ 15 % | ≥ 25 % | < 10 % |

---

## 2. Boucle de jeu

### 2.1 Boucle principale (10 à 60 s)

```
            ┌──────────────────────────────────────────────────────────────┐
            │                                                              │
            ▼                                                              │
   ┌────────────────┐   +1 taille/s (×Tapis, ×2^R)   ┌────────────────┐     │
   │ 1. GRANDIR     │ ─────────────────────────────▶ │ 2. PRESSER     │     │
   │ (tout seul)    │   revenu passif → Pot          │ SPLORCH !      │     │
   └────────────────┘                                │ pièces ×12 s   │     │
            ▲                                        │ PERFECT ×2     │     │
            │                                        └───────┬────────┘     │
            │                                                │ pièces       │
   ┌────────────────┐   jumeaux                      ┌───────▼────────┐     │
   │ 5. FUSIONNER   │ ◀───────────────────────────── │ 3. CONSTRUIRE  │     │
   │ Bassin, combo  │                                │ dalles : Tapis,│     │
   │ (a+b)×1,25     │                                │ déco, Cuve…    │     │
   └───────┬────────┘                                └───────┬────────┘     │
           │                                                 │              │
           │            ┌────────────────┐                   │              │
           └──────────▶ │ 4. FAIRE NAÎTRE│ ◀─────────────────┘              │
                        │ Cuve, fuites,  │   nouveaux squishies             │
                        │ Golden, bébés  │ ─────────────────────────────────┘
                        └────────────────┘
   Méta : quand le plus gros squishy atteint l'objectif → GRAND SPLORCH (×2 croissance pour toujours)
```

1. **Grandir.** Chaque squishy grossit tout seul (+1 par seconde au départ) et remplit le Pot à Pièces.
2. **Presser.** Le joueur presse un squishy prêt : il gagne 12 secondes de revenu de ce squishy d'un coup, ×2 si PERFECT. Chaque squishy se recharge en 8 s.
3. **Construire.** Les pièces achètent des dalles : le Tapis à Goûter (croissance), des décorations (+5 % de revenu chacune), la vitesse et la qualité de la Cuve, des places d'enclos.
4. **Faire naître.** La Cuve fait naître un squishy gratuit à intervalle fixe. Les créatures en fuite, le Golden Wobbler, le BOOP RUSH et le MEGA SQUISH en apportent d'autres.
5. **Fusionner.** Deux jumeaux lancés dans le Bassin fusionnent : taille (a + b) × 1,25 et une étoile de plus. Le résultat peut fusionner encore (combo).

**La décision de chaque minute :** presser maintenant (pièces tout de suite), acheter le prochain Tapis (croissance pour tout le ranch), ou garder des jumeaux dans le Bassin pour préparer un combo ×4.

### 2.2 Boucles secondaires

| Boucle | Durée | Contenu | But |
|---|---|---|---|
| **Rythme du serveur** | 60 s / 10 min / 30 min | Créature en fuite personnelle (60 s), Golden Wobbler (4 par heure), BOOP RUSH (90 s toutes les 10 min), MEGA SQUISH (toutes les 30 min), jauge du serveur | Un rendez-vous toutes les quelques minutes, sessions de plus de 10 min |
| **Boucle de renaissance** | 13 min au début, puis de plus en plus long | Atteindre l'objectif de taille → Grand Splorch → tout regrandit 2 fois plus vite | Le plaisir de « recommencer plus vite et plus gros » |
| **Boucle quotidienne** | 1 jour | Croissance hors ligne visible, Nourrir Plop (jours au total), 3 objectifs du jour | Habitude J2-J7 |
| **Boucle hebdomadaire** | 7 jours | Jelly Moon le samedi (et rattrapage le dimanche), 5 classements de la semaine, une nouvelle espèce par semaine (données) | Pic du samedi, rendez-vous |
| **Boucle de collection** | jours → semaines | Squishydex (26 espèces, 234 mutations, badges d'étoiles), bonus de famille, Étagère à trophées, Fame | Profondeur J8-J28 |
| **Boucle sociale** | continue | Ranchs voisins, bonus d'amis, pet-sitting, poursuites, MEGA, jauge, cadeaux du Grand Splorch, emotes, applaudissements | Jeu entre amis, signal de classement |

### 2.3 Méta-progression

| Couche | Horloge | Ce qui progresse | Remis à zéro par le Grand Splorch ? |
|---|---|---|---|
| Ranch | minutes | Pièces, Tapis à Goûter, décorations, vitesse, qualité et buses de la Cuve | **Oui** |
| Taille | minutes → heures | Taille de chaque squishy | **Oui** (chacun redevient taille 1) |
| Enclos | heures → jours | Places d'enclos (4 → 18, 24 avec le pass), Lit douillet | Non |
| Collection | jours | Squishies (espèce, mutation, étoiles), Squishydex, bonus de famille, Meilleurs Amis | Non |
| Prestige | jours → semaines | R : croissance ×2 par Grand Splorch, familles et niveaux de Cuve débloqués, Étagère à trophées | — |
| Social | semaines | Fame, jours de Plop, titres, classements | Non |

### 2.4 Horloge commune (UTC, identique sur tous les serveurs)

Toutes les phases viennent du module pur `EventClock` (§12.4), à partir de `Clock.now()` (même heure UTC côté serveur et côté client). Les joueurs apprennent le rythme : « Rush à :05, :15, :25… ».

| Minute de l'heure | Événement | Durée |
|---|---|---|
| :00:30, :10:30, :30:30, :40:30 | **Golden Wobbler** lâché sur la place | 30 s |
| :04:50, :14:50… (10 s avant) | Sirène du BOOP RUSH | 10 s |
| :05, :15, :25, :35, :45, :55 | **BOOP RUSH** | 90 s (jusqu'à :06:30, :16:30…) |
| :19:45 et :49:45 | Alerte MEGA SQUISH (ombre au sol) | 15 s |
| :20 et :50 | **MEGA SQUISH** | 60 s de pression + 5 s d'éclatement |
| Samedi 16:00-16:20, 18:00-18:20, 20:00-20:20, 22:00-22:20 | **Jelly Moon** (le MEGA de :20 devient MEGA MOON SQUISH) | 20 min (+ le MEGA de :20) |
| Dimanche 16:00-16:20 | Jelly Moon de rattrapage | 20 min |
| 00:00 chaque jour | Remise à zéro quotidienne (objectifs, plafonds journaliers, Nourrir Plop) | — |
| Lundi 00:00 | Remise à zéro hebdomadaire (classements) | — |

Heures à Paris en hiver : Jelly Moon à 17 h, 19 h, 21 h et 23 h le samedi, 17 h le dimanche. À New York en hiver : 11 h, 13 h, 15 h, 17 h.

**Un seul grand spectacle à la fois** [`Events.SpectacleGap = 20`]. Les grands spectacles sont : BOOP RUSH, MEGA SQUISH, Grand Splorch, danse de Plop (jauge pleine). Deux grands spectacles sont toujours séparés d'au moins 20 s. Les horaires fixes le garantissent entre Rush, MEGA et Golden Wobbler (le Golden n'est pas un grand spectacle). Le Grand Splorch et la danse de Plop, déclenchés par les joueurs, attendent dans une **file du serveur** : le HUD affiche « Ton Grand Splorch passe dans 0:35 ». Un Grand Splorch au plus toutes les 20 s par serveur, dans l'ordre d'arrivée. Pendant un Rush (90 s), l'attente maximale est donc de 110 s.

---

## 3. Les 5 premières minutes (FTUE)

**Règles.** Pas de tutoriel écrit. Un chemin lumineux au sol, les gestes de Plop (la mascotte), et un mot court à côté de l'icône du bouton (4 mots au plus). Jamais plus d'une consigne à l'écran. Une récompense ou un chiffre qui bouge au moins toutes les 15 s. Aucune fenêtre bloquante pendant les 60 premières secondes. Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé (la Boutique Robux reste cachée). Chaque étape numérotée est envoyée à `AnalyticsService:LogOnboardingFunnelStepEvent` (§16.1).

**Pendant l'accueil, l'horloge est réglée pour l'apprentissage** : la Cuve et les créatures en fuite suivent le script ci-dessous jusqu'à 5:00 de jeu, puis reprennent leurs règles normales (§4.9, §4.11). Les événements de serveur (Rush, MEGA, Golden) gardent leur horaire UTC ; le joueur peut les regarder.

| Temps | Ce que voit et fait le joueur | Ce que fait le système | Étape |
|---|---|---|---|
| Chargement | Écran construit en code (`ReplicatedFirst`) : un Plop rebondit, 3 points animés, aucun texte long | Chargement du profil avec verrou de session (§12.6). En cas d'échec : écran « Ton ranch se réveille… » et bouton Réessayer, jamais de profil vide sauvegardé | — |
| 0:00 | Le personnage apparaît **dans son propre ranch**, face au Pot et au premier squishy. Les amis Roblox déjà sur le serveur ont le ranch voisin | `RanchService` attribue le ranch (à côté d'un ami s'il y en a un) | 1 « Chargé » |
| 0:00-0:10 | Plop, la mascotte, arrive en rebondissant et pose **ton petit Plop** (taille 1). Le compteur au-dessus de lui défile : 2, 3, 4… Grand anneau au sol avec l'icône du bouton (□ / E / bouton tactile) et le mot « Presser » | Croissance +1/s. Le reste du HUD est caché : seul le compteur de pièces (0) est visible | — |
| ~0:10 | **Premier SPLORCH** : Plop s'écrase, rebondit, fontaine de pièces, « +10 » en gros, petite vibration (manette) | Récompense de pression `max(10, floor(12 × revenu))` = 10 (§4.7) | 2 « Première pression » |
| 0:10-0:25 | Deuxième pression possible à 0:18 (anneau qui se remplit sous Plop). Des flèches au sol mènent à la première dalle : **Tapis à Goûter, 25** | — | — |
| ~0:25 | Le joueur marche sur la dalle : le Tapis se construit en rebondissant. Plop passe à **+2/s** (le « +2 » flotte au-dessus de lui). **Première récompense en moins de 30 s** | Achat Tapis niveau 1 | 3 « Premier achat » |
| ~0:40 | La **Cuve à Gelée** se construit toute seule (gratuite). Sa première goutte éclot : « **Jumeau de Plop** ! », annoncé comme tel. Ce n'est pas un tirage au hasard | Naissance scriptée : Plop, 0 étoile, taille 1 | 4 « Cuve » |
| ~1:00 | Leçon de fusion. « Prendre » (□) au-dessus du jumeau, trois pas, « Lancer » (□) dans le Bassin, où Plop attend déjà (Plop la mascotte l'y a posé). SPLORCH géant, **une étoile apparaît**, le revenu saute. Taille ≈ (96 + 41) × 1,25 = 171 | Fusion (§4.10). Le joueur a compris : grandir, presser, fusionner | 5 « Première fusion » |
| ~1:30 | Le **Pot à Pièces** brille : le joueur marche dessus, gros chiffre (≈ 240). Deux nouvelles dalles s'allument : Tapis niveau 2 (100) et la première décoration, Clôture rebondissante (80) | Encaissement du Pot (§4.8) | 6 « Premier Pot » |
| ~2:00 | **Ta** créature en fuite saute de la Fontaine de Gelée, devant ton portail, marquée d'un anneau à ta couleur. Flèche, icône □ (« Attraper ») et icône R2 (« Bondir »). Attrapée : tampon « NOUVEAU ! Mochi Mew » dans le Squishydex | Fuite personnelle scriptée : Mochi Mew, Commun | 7 « Première capture » |
| ~2:45 | **Premier vrai tirage** de la Cuve. Les probabilités apparaissent en barres simples sur la Cuve, avec l'étiquette « Nouveauté garantie (3) » : les 3 premiers tirages donnent une espèce que le joueur n'a pas encore (§4.9). Un tirage Rare ou mieux lance une bannière serveur | Tirage normal (qualité 0) | 8 « Premier tirage » |
| ~3:00 | Le HUD affiche l'horloge du prochain événement (« BOOP RUSH 2:00 »). **Si aucun Rush ni MEGA ne commence avant 4:00 de jeu**, Plop fait sa **démonstration** : il éternue devant ton portail (ATCHOUM) et s'enfuit en rebondissant. Le joueur le poursuit sans rien risquer et gagne un **bébé Plop** (10 % de la taille de son Plop). Sinon, le joueur vit le vrai Rush à l'abri : son ranch porte le **bouclier débutant** pendant 15 min | Démonstration personnelle (§4.21.6) | — |
| ~3:50 | Plop atteint la **taille 1 200** : une selle apparaît, icône L2 (« Monter »). Il rebondit 1,4 fois plus vite. Une flèche mène à la place : statue du plus gros squishy du serveur, Boutique (vente de squishies), Autel de la Lune avec le compte à rebours du samedi, jauge du serveur | Seuil de selle (§4.12) | 9 « Première balade » |
| ~5:00 | Petit panneau : **3 objectifs du jour** (presser 30, attraper 2, fusionner 1) et « **Nourris Plop : Jour 1** ». Le HUD complet est affiché | Objectifs du jour 1 fixes (§7.4) | 10 « Objectifs » |
| ~12-15 min | Le plus gros squishy atteint **15 000** : « Grand Splorch prêt ! » | Objectif R0 (§4.15) | 11 « Premier Grand Splorch » |

**Cible à 5:00** (vérifiée par la simulation, §4.24) : 3 à 4 squishies, au moins 1 fusion, au moins 1 capture, la première balade faite, et 1 000 à 2 000 pièces en poche. À 5:00, les 4 places d'enclos de départ sont pleines : la Cuve garde sa goutte suivante (« Plein ! ») et la dalle Enclos (1 200) devient le prochain objectif naturel.

**Cas particuliers**
- *Arrivée pendant un BOOP RUSH* : le joueur voit la poursuite. La carte du choix Rush/Cozy (§4.21.1) n'apparaît qu'au premier Rush qui commence après 3:00 de jeu. Son ranch porte le bouclier débutant.
- *Arrivée juste avant un MEGA SQUISH* : la flèche vers la place n'apparaît qu'après 3:50. Le joueur peut y aller avant ; s'il presse le MEGA, il gagne comme tout le monde.
- *Serveur presque vide* : la démonstration de Plop et les Wild Wobblers (§4.21.5) donnent quand même une poursuite.
- *Retour d'un joueur* (pas la première session) : écran de retour (§7.2), puis le HUD complet.
- *Accueil interrompu* (départ avant 5:00) : l'étape atteinte est sauvegardée (`onboarding.step`) ; au retour, l'accueil reprend à l'étape suivante sans rejouer les naissances scriptées.

---

## 4. Systèmes détaillés

### 4.1 Monnaies et scores

Une seule monnaie à dépenser, pour rester simple. Tout est calculé et gardé par le serveur.

| Ressource | Rôle | Sources | Puits | Remise à zéro |
|---|---|---|---|---|
| **Pièces** (Coins) | Construire le ranch de la boucle en cours | Revenu passif (Pot), pressions, combos, vente de squishies, récompenses d'événements, objectifs du jour, produits Robux « Paquet de pièces » | Dalles du ranch, places d'enclos, Lit douillet | Oui, à chaque Grand Splorch |
| **Fame** (célébrité) | Score permanent, bonus de revenu | Être boopé (+1), capture « Héros » (+2), relâcher un squishy (+1), Grand Splorch (+5), participer au MEGA (+1) | Aucun (on ne la dépense pas) | Jamais |
| **R** (niveau de Grand Splorch) | Prestige | +1 par Grand Splorch | — | Jamais |
| **Jours de Plop** | Fidélité | +1 par jour UTC où l'on nourrit Plop | — | Jamais (total, jamais une série) |

**Sources et puits de pièces (valeurs exactes)**

| Source | Montant |
|---|---|
| Revenu passif | Somme des revenus des squishies du ranch (§4.3), versée dans le Pot |
| Pression | `max(10, floor(12 × revenu du squishy))`, ×2 si PERFECT, +10 % par PERFECT de suite (max +50 %) (§4.7) |
| Combo de fusion | Étape k : `20 × k ×` revenu du squishy obtenu (§4.10) |
| Vente d'un squishy | 60 s de son revenu (minimum 10) (§4.13) |
| Créature dorée vue de près, MEGA réussi, cadeau de Grand Splorch | 60 s du revenu du joueur (§4.11, §4.22, §4.15) |
| Capture « Héros » de son propre squishy en fuite | 120 s du revenu du joueur (§4.21) |
| Squishy boopé rendu au propriétaire | 60 s du revenu du propriétaire (§4.21) |
| Pet-sitting (presser chez un ami) | Le propriétaire : la pression normale ; le visiteur : 10 s de son propre revenu (§6.4) |
| Applaudir un Grand Splorch | 10 s du revenu (10 récompensés par jour) (§6.7) |
| Objectifs du jour | 3, 6 ou 10 min de revenu (§7.4) |
| Hors ligne | 25 % du revenu de départ, plafonné (§4.19) |

« Revenu du joueur » = la somme des revenus de ses squishies dans les enclos, multiplicateurs compris, au moment de la récompense. Les récompenses « en secondes de revenu » restent ainsi justes à tous les niveaux.

### 4.2 Nombres géants

**Stockage.** Les tailles et les pièces sont des nombres `number` de Luau (double précision, jusqu'à ≈ 1,8e308). Sous 1e15, les pièces restent des entiers exacts (`floor` après chaque calcul). Au-dessus, l'arrondi du double est accepté (il ne se voit pas à l'écran). Le serveur borne toute valeur à `[0 ; 1e300]` et refuse `NaN` et l'infini avant chaque écriture (les DataStores refusent ces valeurs en JSON).

**Affichage** (`Shared/Util/Format.abbreviate(n, lang)`) :
- moins de 10 000 : le nombre entier, avec séparateur des milliers (EN « 9,876 » ; FR « 9 876 » avec espace fine insécable U+202F) ;
- à partir de 10 000 : **3 chiffres significatifs, tronqués** (jamais arrondis vers le haut : 999 999 s'affiche 999K, pas 1.00M), puis le suffixe ;
- en français : virgule décimale et espace fine insécable avant le suffixe (« 1,23 M ») ;
- au-delà de 1e36 : notation « 1.23e36 » (EN) / « 1,23e36 » (FR) ;
- les bannières de jalons écrivent le mot entier (« 1 TRILLION! », « 1 BILLION (1 000 milliards) ! »).

| Puissance | EN | Mot EN | FR | Mot FR |
|---|---|---|---|---|
| 1e3 | K | thousand | k | mille |
| 1e6 | M | million | M | million |
| 1e9 | B | billion | Md | milliard |
| 1e12 | T | trillion | Bn | billion (mille milliards) |
| 1e15 | Qa | quadrillion | Bd | billiard |
| 1e18 | Qi | quintillion | Tn | trillion |
| 1e21 | Sx | sextillion | Td | trilliard |
| 1e24 | Sp | septillion | Qn | quadrillion |
| 1e27 | Oc | octillion | Qd | quadrilliard |
| 1e30 | No | nonillion | Qt | quintillion |
| 1e33 | Dc | decillion | Qtd | quintilliard |

Exemples : 12 345 → EN « 12.3K », FR « 12,3 k » ; 4 560 000 000 → EN « 4.56B », FR « 4,56 Md » ; 7,8e12 → EN « 7.80T », FR « 7,80 Bn ». En français, la fiche d'un squishy et l'info-bulle de la taille montrent aussi le mot entier (« 7,80 Bn = 7,80 billions = 7 800 milliards »). Le choix des suffixes français est une question ouverte (§20, n° 2).

**Échelle de taille visuelle** (`Shared/Logic/SizeScale`) :

```
échelle(S) = 1 + 0,6 × log10(max(1, S))
diamètre du corps = 2 studs × échelle
```

| Taille S | 1 | 100 | 1 200 (selle) | 1 million | 1 milliard | 1e12 | 1e15 | 1e30 |
|---|---|---|---|---|---|---|---|---|
| Échelle | 1× | 2,2× | 2,85× | **4,6×** | 6,4× | 8,2× | 10× | 19× |
| Diamètre (studs) | 2 | 4,4 | 5,7 | 9,2 | 12,8 | 16,4 | 20 | 38 |

Plafonds d'affichage (la taille réelle et le nombre restent exacts) : **4×** dans un enclos (diamètre 8, pour que 24 squishies tiennent) ; **6×** comme monture ; **19×** pour la silhouette du meilleur squishy qui flotte au-dessus du ranch (§6.6) et pour la statue de la place. Au-delà du plafond de l'enclos, une petite couronne de taille (anneau doré qui tourne) indique « plus gros que ce que l'enclos montre ».

### 4.3 Le squishy : données et formules

Un squishy est une ligne de données dans le profil (§12.6) : `{ s = espèce 1-26, m = mutation 0-9, st = étoiles 0-5, z = taille, bf = emplacement de Meilleur Ami 0-3, lk = verrou, o = tenue }`. Il est dessiné par le client à partir de ces valeurs (§5.2).

**Croissance** (par seconde, identique pour tous les squishies du ranch) :

```
croissance = 1 × 2^R × (1 + niveauTapis) × (1 + 0,10 × familleJellyComplète) × B
```

- `niveauTapis` de 0 à 12 (§4.6) ; `familleJellyComplète` vaut 1 si les 4 espèces de la famille Jelly sont dans le Squishydex (§4.17) ;
- `B` = 2 si un boost ×2 est actif (jauge du serveur, Squish Party, boost personnel), sinon 1. Les boosts ×2 ne se cumulent jamais entre eux (§4.25).

**Revenu** (pièces par seconde, pour un squishy dans un enclos) :

```
revenu = 0,02 × rareté × taille × mutation × (1 + 0,5 × étoiles) × A × P × B
A = 1 + 0,05 × décorations          (12 au plus → +60 %)
      + 0,10 × amisPrésents         (4 au plus → +40 %)
      + 0,01 × min(300, Fame)       (+300 % au plus)
      + bonus de l'Étagère à trophées (+208 % au plus, §4.16)
      + 0,01 × pages dorées du Squishydex (+26 % au plus, §4.17)
P = 2 avec le pass ×2 Pièces, sinon 1
```

Exemple : un Plop Commun de taille 1 000, sans mutation, 1 étoile, sans bonus : 0,02 × 1 × 1 000 × 1 × 1,5 = **30 pièces/s**. Le R n'apparaît pas dans le revenu : il agit par la taille (croissance ×2^R), ce qui revient au facteur « rebirth » du concept sans compter deux fois.

Les squishies de la Boîte à dodo (§4.14) ne grandissent pas et ne rapportent rien. Ceux du Bassin de Fusion grandissent et rapportent comme dans un enclos.

### 4.4 Raretés

La couleur du corps vient de l'espèce (§5.1). La rareté se lit à l'**aura** (couleur **et** forme, pour les daltoniens) et à la couleur de l'étiquette.

| Rareté (EN / FR) | Multiplicateur de revenu | Couleur | Aura (forme lisible sans couleur) | Espèces au lancement |
|---|---|---|---|---|
| Common / Commun | ×1 | Gris clair (220, 220, 225) | Aucune | 6 |
| Uncommon / Peu commun | ×3 | Vert (120, 220, 130) | **Cercle** plat au sol | 6 |
| Rare / Rare | ×10 | Bleu (90, 170, 255) | **3 points** qui tournent (triangle) | 3 |
| Epic / Épique | ×40 | Violet (180, 110, 255) | **Carré** de 4 losanges qui tournent | 5 |
| Legendary / Légendaire | ×200 | Or (255, 200, 60) | **Couronne-étoile** à 5 branches + `PointLight` | 3 |
| Mythic / Mythique | ×1 000 | Rose (255, 110, 190) | **Double anneau** + contour `Highlight` (budget §12.9) | 1 |
| Secret / Secret | ×5 000 | Arc-en-ciel sur fond noir | **Losange** flottant + étincelles « ? » | 2 |

### 4.5 Mutations

Une mutation au plus par squishy. Elle multiplie le revenu. Une fusion garde la meilleure des deux (le plus gros multiplicateur).

| Id | Mutation (EN / FR) | Multiplicateur | Aspect (données de rendu) | Chance par naissance dans la Cuve (buses niveau 0) | Buses niveau 5 (×3,5) |
|---|---|---|---|---|---|
| 1 | Jelly / Gelée | ×1,5 | Corps en matériau `Glass` (transparence 0,2) avec un petit noyau visible dedans | 4 % | 14 % |
| 2 | Neon / Néon | ×2 | Yeux, oreilles et motif en matériau `Neon` ; lueur douce | 2 % | 7 % |
| 3 | Frosted / Givré | ×3 | Matériau `Ice`, 2 flocons par seconde (particules) | 1 % | 3,5 % |
| 4 | Golden / Doré | ×5 | Matériau `Foil` doré (255, 205, 60), `Sparkles` | 0,4 % | 1,4 % |
| 5 | Galaxy / Galaxie | ×8 | Corps bleu nuit (25, 20, 60) parsemé de 6 points `Neon`, coque `ForceField` | 0,15 % | 0,525 % |
| 6 | Rainbow / Arc-en-ciel | ×12 | Teinte qui fait le tour du cercle des couleurs en 6 s (client) | 0,05 % | 0,175 % |
| 7 | Lunar / Lunaire | ×20 | Argent bleuté (210, 220, 255), croissant de lune sur le front, petit troisième œil mignon, 2 gouttes qui perlent ; **seulement pendant la Jelly Moon** | 0 % (3 % pendant la Jelly Moon, non multiplié par les buses) | — |
| 8 | Glitch / Glitch | ×40 | Couleurs qui changent par paliers 2 fois par seconde (jamais plus de 3 changements/s), 4 petits cubes qui orbitent. Mouvement réduit : damier fixe | 0,004 % (1 sur 25 000) | 0,014 % |
| 9 | **Flop** / Flop | ×100 | **Le raté magnifique** : dégonflé (hauteur ×0,6, largeur ×1,25), yeux mi-clos, petite moue, couleurs ternes ; il fait « blorp » toutes les 6 à 10 s. Un Plop Flop est le « **Flop Plop** », l'autocollant du jeu | 0,0005 % (1 sur 200 000) | 0,00175 % (1 sur 57 143) |

- **Tirage** : un seul nombre au hasard dans [0 ; 1[, comparé aux chances cumulées en partant de la plus rare (Flop, puis Glitch… puis Gelée). Au-delà du total : pas de mutation. Total à buses 0 : 7,6 % ; buses 5 : 26,6 %.
- **Buses à mutation** (dalle de la Cuve, niveaux 0 à 5) : toutes les chances sauf Lunaire × `(1 + 0,5 × niveau)`.
- **Jelly Moon** : toutes les chances × 2, plus Lunaire 3 % (total à buses 5 : 56,2 %).
- **Autres sources** : Golden Wobbler (Doré garanti), Goutte de Lune (Lunaire garanti, §4.23), bébés du MEGA (chances de mutation × 2), bébés du Rush (même mutation que l'original), cadeaux du Grand Splorch (sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible).
- **Étiquette « 1 sur X »** lors d'une naissance rare : calculée en direct = 1 / (chance de la rareté × chance de la mutation) aux réglages du moment, arrondie à 2 chiffres significatifs. Jamais un chiffre inventé.

### 4.6 Le ranch et ses dalles

Le ranch se construit en marchant sur des dalles lumineuses. Chaque dalle montre une icône, le prix et le niveau. Un achat se construit en rebondissant (§9.4). Les dalles apparaissent dans l'ordre : une nouvelle dalle s'allume quand la précédente a été achetée une fois.

Prix : `floor(base × croissance^L)` où L = niveau actuel (le premier achat coûte la base). Les dalles de la boucle sont **multipliées par 2^R** (comme la croissance), pour que la construction garde son sens à chaque boucle. Les places d'enclos et le Lit douillet ne le sont pas (ils sont permanents).

| Dalle | Effet par niveau | Niveaux | Base | Croissance | Grand Splorch |
|---|---|---|---|---|---|
| **Tapis à Goûter** (Snack Mat) | Croissance × (1 + niveau) : +1/s → +13/s au niveau 12 | 12 | 25 | ×4,0 | Remis à zéro |
| **Décorations** (12 dalles différentes, une fois chacune) | +5 % de revenu chacune | 12 | 80 | ×2,6 | Remises à zéro |
| **Vitesse de la Cuve** | Intervalle = 90 × 0,85^niveau s (90 → 17,7 s) | 10 | 800 | ×2,5 | Remise à zéro |
| **Qualité de la Cuve** | Table de raretés suivante (§4.9). Niveau maximum = min(8, 1 + R) | 8 | 3 000 | ×3,5 | Remise à zéro |
| **Buses à mutation** (dès R = 1) | Chances de mutation × (1 + 0,5 × niveau) | 5 | 20 000 | ×4,0 | Remises à zéro |
| **Enclos** | +1 place (4 → 18) | 14 | 1 200 | ×2,2 | **Gardé** |
| **Lit douillet** (dès R = 1) | Limite hors ligne 8 h → 12 h | 1 | 250 000 | — | **Gardé** |

**Coûts calculés (R = 0 ; multiplier par 2^R pour les dalles de la boucle)**

| Niveau → | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Tapis à Goûter | 25 | 100 | 400 | 1 600 | 6 400 | 25 600 | 102 400 | 409 600 | 1,64 M | 6,55 M | 26,2 M | 105 M |
| Décorations | 80 | 208 | 540 | 1 406 | 3 655 | 9 505 | 24 713 | 64 254 | 167 061 | 434 360 | 1,13 M | 2,94 M |
| Vitesse de la Cuve | 800 | 2 000 | 5 000 | 12 500 | 31 250 | 78 125 | 195 312 | 488 281 | 1,22 M | 3,05 M | — | — |
| Qualité de la Cuve | 3 000 | 10 500 | 36 750 | 128 625 | 450 187 | 1,58 M | 5,51 M | 19,3 M | — | — | — | — |
| Buses à mutation | 20 000 | 80 000 | 320 000 | 1,28 M | 5,12 M | — | — | — | — | — | — | — |
| Enclos | 1 200 | 2 640 | 5 808 | 12 777 | 28 110 | 61 843 | 136 055 | 299 322 | 658 510 | 1,45 M | 3,19 M | 7,01 M |

Enclos niveaux 12 et 13 : 15,4 M et 33,9 M (total des 14 niveaux ≈ 62 M, un objectif de plusieurs jours).

**Les 12 décorations** (dans l'ordre d'apparition) : Bouncy Fence (clôture rebondissante), Candy Lamp (lampadaire bonbon), Jelly Flowers (fleurs de gelée), Gumdrop Path (chemin de bonbons), Cloud Bench (banc nuage), Lollipop Trees (arbres sucettes), Marshmallow Rocks (rochers guimauve), Bubble Pond (mare à bulles), Sprinkle Arch (arche à vermicelles), Pudding Hut (cabane pudding), Rainbow Kite (cerf-volant arc-en-ciel), Star Windmill (moulin étoilé).

**Ordre d'apparition des dalles** : Tapis → (Cuve, gratuite) → (Bassin, gratuit) → Tapis 2 + Bouncy Fence → Enclos (quand les enclos sont pleins) → Vitesse de la Cuve (après 5:00) → Qualité de la Cuve (après 5:00) → autres décorations → Buses (R ≥ 1) → Lit douillet (R ≥ 1). Après un Grand Splorch, toutes les dalles déjà découvertes restent visibles.

**Ce qui ne s'achète jamais** : la Cuve, le Bassin, la Fontaine de Gelée, le Pot, l'Étagère à trophées, le bol de Plop. Ils sont là dès l'accueil et ne sont jamais remis à zéro.

### 4.7 Presser (SPLORCH) et PERFECT

- **Geste** : action contextuelle (□ à la manette, E au clavier, appui sur le squishy ou sur le gros bouton au téléphone) sur un squishy de son ranch à 10 studs au plus. Tout le geste est une invite contextuelle (`ProximityPrompt` créé par le client, touche manette par défaut □ = `ButtonX`, clavier E), affichée en grand pour la télé.
- **Recharge** : 8 s par squishy [`Balance.Press.Cooldown`]. Un anneau se remplit sous le squishy ; prêt, il est un peu gonflé et brille.
- **Récompense** : `floor(max(10, 12 × revenu) × (PERFECT ? 2 : 1) × (1 + 0,10 × min(5, série)) × (familleKittyComplète ? 1,10 : 1))`.
- **PERFECT** : chaque squishy rebondit au repos avec une période de 1,2 s, calée sur `Clock.now()` et un décalage propre (`hash(uid)`), donc identique côté client et côté serveur. La fenêtre PERFECT dure **0,24 s** autour du sommet du rebond (±0,12 s), soit 20 % du cycle. Un petit anneau blanc se resserre vers le squishy pour montrer le bon moment.
- **Série PERFECT** : chaque PERFECT de suite ajoute +10 % (max +50 % à 5 de suite). Une pression non PERFECT remet la série à 0, sans aucune punition (la récompense de base reste). 6 s sans pression remettent aussi la série à 0. Le son monte d'un demi-ton à chaque marche.
- **Vérification serveur** : le client envoie `Press(uid, tClient)`. Le serveur accepte `tClient` s'il est dans `[maintenant − 0,35 s ; maintenant + 0,05 s]`, sinon il prend `maintenant`. Il calcule la phase du rebond à `tClient`. Au pire, un tricheur obtient ce qu'obtient un joueur adroit (×2) : c'est borné et accepté.
- **Jauge du serveur** : +1 par pression, +1 de plus si PERFECT (§4.23).
- Débit maximal accepté : 12 pressions/s par joueur (au-delà, ignorées sans message).

### 4.8 Le Pot à Pièces

- Le revenu passif s'accumule dans le Pot (calcul paresseux, §12.3). Le montant flotte au-dessus du Pot.
- **Encaisser** : marcher à 5 studs au plus du Pot (position vérifiée par le serveur à chaque tick). Pas de limite de contenu en ligne : le Pot ne fait jamais perdre de pièces.
- **Pass Pot automatique** : le Pot s'encaisse tout seul toutes les 5 s, où que soit le joueur. Confort seulement.
- Hors ligne : le Pot reçoit 25 % du revenu, dans la limite hors ligne (§4.19).

### 4.9 La Cuve à Gelée

- **Fonctionnement** : la Cuve se remplit (niveau de gelée visible) pendant l'intervalle, puis une goutte tombe et éclot en 2 s dans la première place d'enclos libre. Gratuit. Si les enclos sont pleins, la goutte attend dans la Cuve (« Plein ! ») et le minuteur s'arrête. La Cuve ne tourne que si le joueur est en ligne.
- **Intervalle** : `90 × 0,85^vitesse` s (90 → 17,7 s), ×0,9 avec la famille Bunny complète (§4.17).
- **Rareté** : tirée dans la table du niveau de Qualité (en %). **Affichée sur la Cuve** en barres simples et en détail dans l'onglet Guide du Squishydex.

| Qualité | Commun | Peu commun | Rare | Épique | Légendaire | Mythique | Secret |
|---|---|---|---|---|---|---|---|
| 0 | 80 | 17 | 2,6 | 0,4 | — | — | — |
| 1 | 74 | 21 | 4 | 0,9 | 0,1 | — | — |
| 2 | 67 | 25 | 6 | 1,7 | 0,28 | 0,02 | — |
| 3 | 60 | 28 | 8,5 | 2,9 | 0,55 | 0,05 | — |
| 4 | 52 | 31 | 11,5 | 4,5 | 0,9 | 0,1 | — |
| 5 | 45 | 32 | 15 | 6,5 | 1,3 | 0,19 | 0,01 |
| 6 | 38 | 33 | 18 | 8,7 | 1,95 | 0,33 | 0,02 |
| 7 | 31,5 | 33 | 21 | 11 | 2,9 | 0,57 | 0,03 |
| 8 | 25 | 32 | 24 | 14 | 4 | 0,96 | 0,04 (1 sur 2 500) |

- **Espèce** : tirée au hasard, à chances égales, parmi les espèces de la rareté tirée **dans les familles débloquées** : R = 0 → Jelly, Kitty, Froggy ; R = 1 → + Axolo ; R = 3 → + Bunny ; R = 5 → + Spiky. Si la rareté tirée n'a aucune espèce débloquée, on prend la rareté juste en dessous. Les bébés (Rush, MEGA, cadeaux, Golden) viennent de **toutes** les familles : les autres joueurs font découvrir les familles plus tôt.
- **Secrets** : un tirage Secret donne Royal Plop ; pendant la Jelly Moon, il donne Moonplop ou Royal Plop à chances égales.
- **Nouveauté garantie** : les 3 premiers tirages naturels du compte prennent une espèce **pas encore possédée** dans la rareté tirée, s'il en reste. La rareté, elle, suit la table affichée. La Cuve affiche « Nouveauté garantie (3) ».
- **Protection contre la malchance** : après 40 naissances de suite sans Rare ou mieux, la suivante est au moins Rare ; après 150 sans Épique ou mieux, au moins Épique. Les compteurs sont affichés dans le Guide (« Rare garanti dans 12 »). C'est une règle publique, pas un hasard caché.
- **Mutation** : tirage du §4.5.
- Naissance : taille 1, 0 étoile. Les naissances Rare+ ont leur propre animation (§9.4) ; Légendaire+ lancent une bannière serveur.

### 4.10 Le Bassin de Fusion et les combos

- **Jumeaux** : même espèce **et** même nombre d'étoiles. La mutation peut être différente.
- **Lancer** : « Prendre » (□) sur un squishy de l'enclos : il se pose sur la tête du joueur (marche normale). « Lancer » (□) à 12 studs au plus du Bassin : il décrit un arc et plonge. « Poser » (○ / Q / bouton) le renvoie à sa place. Un joueur porte un seul squishy à la fois.
- **Dans le Bassin** : 5 places d'attente [`Balance.Fusion.PoolSlots = 5`] (6 avec la famille Axolo complète). Un squishy qui attend compte dans les places d'enclos, grandit et rapporte normalement. Si le Bassin est plein et qu'aucun jumeau n'y attend : refus doux (« Bassin plein ! »), le squishy reste porté.
- **Fusion** : si un jumeau attend, les deux fusionnent après 0,4 s :

```
taille   = (a + b) × 1,25
étoiles  = min(5, étoiles + 1)          (deux 5 étoiles donnent un 5 étoiles plus gros)
mutation = celle qui a le plus gros multiplicateur
Meilleur Ami, tenue, verrou : gardés si l'un des deux les avait
```

- **Combo en chaîne** : après chaque fusion, le serveur cherche dans le Bassin un jumeau du résultat (même espèce, nouveau nombre d'étoiles). S'il y en a un, ils fusionnent 0,6 s plus tard, et ainsi de suite. Le combo n compte les fusions de la chaîne.
- **Récompense de combo** : à l'étape k (1, 2, 3…), `20 × k ×` revenu du squishy obtenu, en pièces ; jauge du serveur +3 par étape. Combo ≥ 3 : message personnel ; ≥ 4 : bannière serveur ; ≥ 5 : bannière + grand tampon « COMBO x5 ! ».
- **Exemple** : le Bassin contient un Plop 0★, un Plop 1★ et un Plop 2★. Le joueur lance un Plop 0★ : 0★+0★ → 1★ (combo 1), +1★ → 2★ (combo 2), +2★ → 3★ (combo 3). Avec 5 places, le combo maximal sans 5 étoiles est ×5.
- **Version menu** (console, accessibilité, téléphone) : panneau Ranch → « Fusionner » : choisir A, puis choisir B (seuls les jumeaux de A sont proposés). Les deux sautent dans le Bassin et suivent la même règle, combo compris. Jamais de glisser-déposer.
- Aucun hasard, aucun coût.

### 4.11 Créatures en fuite et Golden Wobbler

**Créature en fuite personnelle**
- Elle saute de **ta** Fontaine de Gelée (devant ton portail, côté rue), 60 s après la fin de la précédente (50 s avec la famille Froggy complète). Première à 2:00 de jeu (accueil).
- Elle n'est visible et attrapable **que par toi** (envoyée à ton seul client), avec un anneau à ta couleur.
- Trajet : petits bonds (un bond de 4,5 studs toutes les 0,5 s, une pause de 0,6 s tous les 3 bonds, soit ≈ 7,5 studs/s en moyenne), à 35 studs au plus de la Fontaine, pendant **20 s** au plus. Ensuite elle replonge dans la Fontaine : aucune punition, la suivante viendra.
- Attraper : action contextuelle à **5 studs** au plus (le serveur accepte jusqu'à 6,5 studs pour la latence).
- Contenu : rareté tirée dans la table de Qualité max(1, qualité actuelle), familles débloquées, mutation tirée (buses comprises), **taille = 5 % du plus gros squishy du joueur** (minimum 1), 0 étoile.
- En pause pendant : un BOOP RUSH, un MEGA SQUISH, son propre Grand Splorch, l'accueil entre 2:45 et 5:00, et quand enclos, Boîte à dodo et Boîte aux lettres sont pleins.

**Golden Wobbler (partagé)**
- Lâché depuis la fontaine de la place à **:00:30, :10:30, :30:30 et :40:30** UTC.
- Visible par tous, y compris les joueurs Cozy. Trajet calculé par le serveur dans les rues de la ville (§12.5), **30 s**, vitesse 14 studs/s au début qui baisse jusqu'à 10 studs/s.
- Le premier qui l'attrape (5 studs, tolérance 6,5) gagne un squishy **Doré garanti**, de rareté tirée dans la table de Qualité 4, toutes familles, **taille = 25 % de son plus gros squishy** (minimum 10).
- Tous les joueurs à 30 studs au plus au moment de la capture : 60 s de leur revenu et jauge +4.
- Personne ne l'attrape : il éclate en confettis dorés ; les joueurs à 30 studs reçoivent 30 s de leur revenu.
- **Course amicale** : le gagnant ne peut pas gagner le Golden Wobbler suivant pendant 20 min (il peut courir et toucher la récompense « de près », mais l'invite « Attraper » ne lui est pas proposée ; message « Laisse les autres gagner celle-ci ! »).

### 4.12 Monter sur son squishy

| Seuil de taille | Selle | Effet |
|---|---|---|
| **1 200** (atteint vers 3:50 au premier jeu) | Petite selle | Vitesse **×1,4** (WalkSpeed 16 → 22,4), saut 7,2 → 8,6 studs |
| 1 000 000 | Grande selle | Même vitesse ×1,4, saut 10,8 studs, éclaboussure à l'atterrissage |
| 1e12 | Selle géante | Même vitesse ×1,4, saut 13 studs, onde de choc visuelle à l'atterrissage |

- **Monture** : par défaut le plus gros squishy qui a une selle ; changeable dans le panneau Ranch.
- **Monter / descendre** : L2 / R / bouton tactile « Monter », n'importe où. La monture saute vers le joueur (petit pop depuis le ranch). Le serveur règle WalkSpeed, `JumpHeight` et `HipHeight` ; le client dessine la monture (échelle plafonnée à 6×) sous le personnage.
- La vitesse est la même pour toutes les selles : la monture est un plaisir et un signe de statut, pas un avantage acheté. Toutes les selles sont gagnées par la taille ; le pack Selles et Traînées ne change que l'apparence.
- On descend tout seul pour « Prendre » un squishy, nourrir Plop ou entrer dans le Bassin. On peut presser, attraper et booper depuis sa monture.

**Bondir** (R2 / Maj / bouton tactile « Bondir ») : petit élan de **12 studs en 0,35 s**, recharge **4 s**. Visée automatique : si une créature attrapable (fuite, Golden, Wild Wobbler, squishy en fuite du Rush) est à 18 studs au plus, dans un cône de ±30° devant la caméra, le bond part vers elle ; sinon, droit devant. Le client fait le bond tout de suite (sensation immédiate) et envoie `Leap(dirX, dirZ)` ; le serveur accorde la distance en plus au contrôle de déplacement seulement si la recharge est respectée (§12.8).

### 4.13 Vendre et relâcher

- **Vendre** (Boutique de la place, ou panneau Ranch → Vendre) : 60 s du revenu actuel du squishy (minimum 10). Refusé pour un Meilleur Ami ou un squishy verrouillé. Maintien de 0,6 s pour un Rare ou mieux.
- **Relâcher** (panneau Ranch → Relâcher, ou à la Prairie des adieux sur les collines) : le squishy fait un signe et part en rebondissant vers les collines. **+1 Fame** (20 Fame au plus par jour de cette façon). Il ne revient pas.
- **Verrou** (cadenas) : un squishy verrouillé ne peut être ni vendu, ni relâché, ni lancé par erreur. Il peut fusionner si le joueur le choisit.

### 4.14 Enclos, Boîte à dodo, Boîte aux lettres

| Lieu | Places | Grandit et rapporte ? | Boopable ? |
|---|---|---|---|
| Enclos (dont le Bassin) | 4 au départ, +1 par niveau de la dalle Enclos (18), **+6 avec le pass Grand Ranch (24 au plus, jamais plus)** | Oui | Oui (sauf protections) |
| Boîte à dodo (Dodo Box) | 60 | Non (ils dorment) | Non |
| Boîte aux lettres (cadeaux) | 20 | Non | Non |

- Une naissance de la Cuve va dans un enclos libre, sinon la goutte attend dans la Cuve.
- Une créature attrapée ou un bébé reçu va dans un enclos libre, sinon dans la Boîte à dodo, sinon dans la Boîte aux lettres. Si les trois sont pleines : le bébé devient 60 s de revenu, avec un message clair. Jamais une perte silencieuse.
- Échanger un squishy entre enclos et Boîte à dodo : panneau Ranch, 2 gestes.
- **24 squishies affichés au plus par ranch** (16 ranchs × 24 = 384 sur le serveur), avec niveaux de détail (§5.2, §12.9).

### 4.15 Grand Splorch (renaissance)

**Condition** : le plus gros squishy du joueur atteint l'objectif de son niveau R. Le joueur doit être dans son ranch et ne rien porter.

| R → R+1 | Objectif (taille du plus gros) | R → R+1 | Objectif |
|---|---|---|---|
| 0 → 1 | **15 000** | 10 → 11 | 310 M |
| 1 → 2 | 40 000 | 11 → 12 | 830 M |
| 2 → 3 | 110 000 | 12 → 13 | 2,3 B |
| 3 → 4 | 300 000 | 13 → 14 | 6,1 B |
| 4 → 5 | 800 000 | 14 → 15 | 16 B |
| 5 → 6 | 2,2 M | 15 → 16 | 44 B |
| 6 → 7 | 5,8 M | 16 → 17 | 120 B |
| 7 → 8 | 16 M | 17 → 18 | 320 B |
| 8 → 9 | 42 M | 18 → 19 | 870 B |
| 9 → 10 | 110 M | 19 → 20 | 2,4 T |
| R ≥ 20 | objectif précédent × 2,7, arrondi à 2 chiffres significatifs | | |

La table vit en configuration [`Balance.Splorch.Targets`] : elle suit `15 000 × 2,7^R` arrondi, et la simulation peut l'ajuster ligne par ligne.

**Écran d'aperçu obligatoire** : en haut, les **gains** (visibles sans défiler) ; puis deux colonnes « Tu gardes » / « Repart de zéro » ; le prochain objectif ; un bouton à **maintenir 1,5 s** (✕ à la manette). Rien ne part par erreur.

| Gagné | Repart de zéro | Gardé |
|---|---|---|
| Croissance ×2 pour toujours (×2^(R+1)) ; +1 au niveau maximal de Qualité de la Cuve (jusqu'à 8) ; à R = 1 : famille Axolo, Buses, Lit douillet ; à R = 3 : famille Bunny, 2e Meilleur Ami ; à R = 5 : famille Spiky ; à R = 10 : 3e Meilleur Ami ; +5 Fame ; titres à R = 5, 10, 15, 20 | Pièces, Pot, Tapis à Goûter, décorations, Vitesse, Qualité et Buses de la Cuve ; la **taille** de chaque squishy (retour à 1) | Tous les squishies (espèce, mutation, étoiles, tenue), places d'enclos, Lit douillet, Boîte à dodo, Boîte aux lettres, Squishydex, bonus de famille, Fame, jours de Plop, Étagère à trophées, Meilleurs Amis, passes et achats « Pour toujours », réglages, statistiques |

**Le spectacle** (6 s, détail au §9.4) : le plus gros squishy s'envole vers la place, gonfle et éclate au ralenti au-dessus du MEGA pad. Une pluie de pièces et de bébés tombe sur **chaque joueur du serveur** (Cozy compris). Puis le squishy se reforme tout petit dans son enclos (taille 1, il garde tout le reste). Bannière serveur. Forte vibration pour le héros. Capture vidéo proposée (§9.5).

**Cadeaux pour les autres joueurs** (payés par le jeu, jamais pris au héros) : 60 s de leur revenu + **1 bébé** de l'espèce éclatée (taille = 5 % de leur plus gros squishy, minimum 1 ; 0 étoile ; sans mutation, sauf 10 % de chance de copier une mutation Doré ou plus faible). 10 bébés de Grand Splorch au plus par jour et par joueur (ensuite, les pièces seulement). Réglage « Recevoir les cadeaux » (activé par défaut).

**Applaudir** : chaque autre joueur voit un bouton APPLAUDIR pendant 8 s (croix → à la manette). Voir §6.7.

**File du serveur** : voir §2.4. Pendant l'attente, le squishy « se prépare » (il tremble et brille) ; le joueur peut continuer à jouer.

### 4.16 L'Étagère à trophées

- Une étagère dans le ranch, avec une place par espèce (26). Elle garde la **taille record** jamais atteinte par un squishy de cette espèce (mise à jour en direct et à chaque Grand Splorch). On ne sent jamais qu'on a « perdu » sa créature.
- Chaque trophée est une petite statue de l'espèce, avec la taille record écrite dessous.

| Palier du record | Statue | Bonus de revenu permanent (additif dans A) |
|---|---|---|
| ≥ 1 000 | Bronze | +2 % |
| ≥ 1 million | Argent | +4 % |
| ≥ 1 milliard | Or | +6 % |
| ≥ 1e12 | Cristal | +8 % |

Maximum : 26 × 8 % = +208 %.

### 4.17 Le Squishydex

- **26 pages d'espèces** (tampon de l'espèce, forme normale) et **234 entrées de mutation** (26 espèces × 9 mutations). Total : 260 tampons. Plus 130 **badges d'étoiles** (★1 à ★5 atteint, par espèce).
- Une entrée est tamponnée dès que le joueur possède un squishy qui la remplit (naissance, capture, bébé, fusion, cadeau). Elle reste même si le squishy part.
- Fiche d'espèce : nom, famille, rareté, aspect, mutations trouvées (silhouettes grises pour les autres), meilleur exemplaire, taille record.
- **Page dorée** : les 9 mutations d'une espèce trouvées → la page devient dorée, +1 % de revenu (additif dans A).
- **Bonus de famille** (les 4 espèces de la famille tamponnées) :

| Famille | Bonus permanent |
|---|---|
| Jelly | +10 % de croissance |
| Kitty | +10 % de pièces par pression |
| Froggy | Créature en fuite toutes les 50 s au lieu de 60 |
| Axolo | +1 place dans le Bassin de Fusion (6) |
| Bunny | Intervalle de la Cuve −10 % |
| Spiky | Limite hors ligne +1 h |

- **Jalons** (tampons d'espèces + de mutations) : 10 → titre « Little Collector » ; 25 → couleur de selle Menthe ; 50 → traînée Bulles ; 75 → titre « Squishologist » ; 100 → drapeau de ranch Squishydex ; 130 → couleur de selle Lavande ; 160 → thème de ranch « Moonlit » ; 200 → titre « Dex Master » ; 260 → Squishydex doré et emote couronne. Tous gratuits, tous cosmétiques.
- Onglet **Guide** : toutes les probabilités (Cuve par niveau, mutations, Golden, MEGA, Wild Wobblers, cadeaux), les compteurs de la protection contre la malchance, les règles du BOOP RUSH.

### 4.18 Fame

- Sources : squishy boopé puis rendu (+1, 30 par jour au plus), capture « Héros » (+2), relâcher (+1, 20 par jour au plus), Grand Splorch (+5), participer à un MEGA SQUISH avec au moins 10 points (+1).
- Effet : +1 % de revenu par point, jusqu'à 300 points (+300 %). Au-delà, la Fame continue de monter pour le prestige (affichée sous le panneau du ranch).
- **Au lancement**, la Fame n'est créditée que si le propriétaire est sur le serveur (c'est toujours le cas : seuls les présents sont boopables). La lignée complète (bébés nés partout) arrive en janvier (§17).

### 4.19 Hors ligne

- Calculé une seule fois au chargement : `durée = clamp(Clock.unix() − lastOnline, 0, limite)`.
- **Croissance hors ligne** : chaque squishy des enclos grandit de `croissance sans boost × 50 % × durée`.
- **Pièces hors ligne** : le Pot reçoit `revenu au départ (sans boost) × 25 % × durée`.
- **Limite** : 8 h ; 12 h avec le Lit douillet (acheté avec des pièces, gardé pour toujours) ; +1 h avec la famille Spiky. Aucun achat Robux ne change cette limite.
- **Écran de retour** (§7.2) : « Plop a grossi de +X pendant ton absence ! » (le Meilleur Ami n° 1, sinon le plus gros), et Plop est réellement plus gros. Si l'objectif de Grand Splorch est atteint, l'écran le dit.

### 4.20 Nourrir Plop, objectifs du jour, carte « Plop a sommeil »

- **Nourrir Plop** : un grand bol dans le ranch. Une fois par jour UTC, maintenir l'action **5 s** devant le bol : Plop mange (nom nom), le compteur de jours monte de 1. Les paliers comptent le **total de jours**, jamais une série : rater un jour ne fait rien perdre. « Jour 42 » flotte au-dessus du ranch. Paliers et récompenses : §7.3.
- **Objectifs du jour** : 3 par jour (facile, moyen, difficile), §7.4.
- **Carte « Plop a sommeil »** : après 60 min de jeu dans la session (puis après 120 min), une petite carte : « Tes squishies continuent de grandir pendant que tu te reposes. » Bouton « OK ». Aucune pénalité, aucun boost pour rester.

### 4.21 BOOP RUSH

Interrupteur de configuration [`Features.BoopRush`] : `"on"` (lancement), `"events"` (seulement pendant la Jelly Moon et les Squish Parties d'administrateur), `"off"`. Changeable sans nouvelle version (§12.2). Avec `"off"`, les Wild Wobblers sont quand même lâchés aux mêmes heures pour tous.

#### 4.21.1 Le choix du mode, des deux côtés

- Au premier Rush qui commence après 3:00 de jeu, une carte s'ouvre avec la sirène : deux gros boutons, « **Je joue au BOOP RUSH** » et « **Je reste tranquille** » (mode Cozy), avec un dessin pour chaque. Sans réponse en 20 s : **Cozy** (le choix le plus sûr).
- **Seuls les joueurs en mode Rush peuvent booper et être boopés**, et attraper les squishies en fuite du Rush.
- Les joueurs Cozy poursuivent les **Wild Wobblers** et le **Golden Wobbler**, pressent le MEGA, reçoivent les cadeaux du Grand Splorch, la jauge et les Squish Parties. Les squishies d'un ranch Cozy ne viennent jamais à la clôture.
- Changer de mode : Réglages, à tout moment, recharge 60 s ; un changement demandé pendant un Rush s'applique à sa fin.
- **Serveurs privés** : Cozy pour tous par défaut. Le propriétaire du serveur privé peut activer « BOOP RUSH autorisé » ; chacun choisit ensuite son mode.
- Repère visuel : badge rose « boop » ou petite couverture « cozy » sur le panneau du ranch.

#### 4.21.2 Déroulé

| Phase | Détail |
|---|---|
| Sirène (−10 s) | Le ciel vire au rose, musique de gloussements, double vibration (manette), bannière « BOOP RUSH dans 10 ! » |
| Début (:X5:00) | Dans chaque ranch en mode Rush, jusqu'à **4 squishies curieux** éligibles viennent s'appuyer à la clôture, côté rue (choisis au hasard, renouvelés toutes les 20 s) |
| Booper | Un joueur Rush, depuis la rue, **maintient l'action 2,5 s** sur le nez d'un squishy à la clôture (8 studs au plus). **5 s** si le propriétaire est à 25 studs au plus de sa clôture (s'il arrive pendant le maintien, le temps restant double). Lâcher, s'éloigner à plus de 8 studs ou un refus = annulé |
| ATCHOUM | Le squishy éternue (nuage pastel brillant, jamais de morve), saute la clôture et rebondit dans la ville sur un **chemin calculé par le serveur** (§12.5) |
| Fuite | **25 s au plus**. Vitesse 16 studs/s au départ, qui baisse de 0,32 stud/s chaque seconde jusqu'à 8 studs/s à 25 s (≈ 300 studs parcourus). Bonds de 0,45 s. Jamais dans un ranch : seulement les rues et la place. Anneau à la couleur du propriétaire, contour `Highlight` |
| Attraper | Action contextuelle à **5 studs** au plus (tolérance serveur 6,5). Le bond à visée automatique aide (§4.12) |
| Fin (:X6:30) | Les squishies à la clôture rentrent. Les fuites en cours continuent jusqu'à leurs 25 s |

#### 4.21.3 Le propriétaire gagne toujours

| Qui attrape | Le propriétaire | L'attrapeur |
|---|---|---|
| **Le propriétaire** | Capture « **Héros** » : +10 % de taille pour ce squishy, 120 s de son revenu, +2 Fame | — |
| **Un autre joueur Rush** | Récupère l'original (rendu à sa place), +1 Fame, 60 s de son revenu | Un **bébé** : même espèce, même mutation, 0 étoile, taille = `min(10 % de l'original, 2 × son propre plus gros squishy)`, minimum 1 |
| **Personne** (25 s écoulées) | Le squishy rentre tout seul avec **+5 % de taille** | — |

Si le propriétaire quitte le serveur pendant la fuite, le squishy rentre aussitôt chez lui (sauvegardé à sa place).

#### 4.21.4 Protections

| Protection | Règle exacte |
|---|---|
| Fuites par ranch | **2 au plus par ranch et par Rush** |
| Cadence du boopeur | **1 boop réussi toutes les 20 s** par joueur ; et 1 seul boop réussi par paire boopeur → ranch et par Rush |
| Meilleur Ami | **Jamais boopable** (1 emplacement ; 2 à R = 3 ; 3 à R = 10). Il ne vient pas à la clôture |
| Mythique et Secret | Boopables **seulement pendant la Jelly Moon** |
| Propriétaire proche | Booper prend **2 fois plus longtemps** (5 s) si le propriétaire est à 25 studs au plus de sa clôture |
| Bouclier débutant | Ranch non boopable tant que le joueur a **moins de 15 min de jeu cumulé**. Il peut booper les autres s'il a choisi le mode Rush |
| Petits serveurs | **Wild Wobblers** (§4.21.5) quand il y a moins de 6 joueurs |
| Pas de fuite en cascade | Un squishy rentré d'une fuite n'est plus boopable jusqu'à la fin de ce Rush ; un squishy porté, dans le Bassin, dans la Boîte à dodo ou né il y a moins de 60 s ne vient pas à la clôture |
| Limite du serveur | 10 fuites en même temps au plus sur le serveur (au-delà, boop refusé : « Trop de squishies en fuite ! ») |
| Bébés | 10 bébés de Rush au plus par jour et par joueur (ensuite : 60 s de revenu à la place) |
| Joueurs bloqués (règle souple) | Le client lit `StarterGui:GetBlockedUserIds()` et l'envoie au serveur (`ReportBlocked`, 200 identifiants au plus). Le serveur refuse les boops entre deux joueurs dont l'un a bloqué l'autre. C'est une liste fournie par le client : un plus, pas une garantie. La vraie protection reste le mode Cozy |

**Ordre de vérification serveur d'un boop** (module pur `RushRules`, testé règle par règle) :

```
si Features.BoopRush == "off" ou (== "events" et pas d'événement)   → refus
si pas de Rush en cours                                              → refus
si boopeur pas en mode Rush, ou propriétaire pas en mode Rush        → refus
si boopeur == propriétaire                                           → refus
si bouclier débutant du propriétaire                                 → refus
si l'un a bloqué l'autre (liste souple)                              → refus
si recharge du boopeur (20 s) ou paire déjà faite ce Rush            → refus
si le squishy n'est pas à la clôture, ou Meilleur Ami                → refus
si Mythique ou Secret hors Jelly Moon                                → refus
si 2 fuites déjà pour ce ranch, ou 10 sur le serveur                 → refus
si boopeur à plus de 8 studs (position validée, budget d'action §12.8) → refus
maintien = 2,5 s, ou 5 s si propriétaire à ≤ 25 studs de sa clôture
fin du maintien sans rupture → FUITE (chemin, horodatage, diffusion)
```

#### 4.21.5 Wild Wobblers

- À chaque Rush : `3 + 2 × max(0, 6 − N)` Wild Wobblers, où N = joueurs sur le serveur (16 joueurs → 3 ; 5 → 5 ; 1 → 13). Lâchés depuis la fontaine de la place et les bouts des rues radiales : un tiers au début, puis par vagues toutes les 15 s.
- Sans propriétaire. Visibles et attrapables par **tous** (Rush et Cozy). Même chemin et même vitesse que les squishies en fuite (25 s).
- Récompense : un bébé d'une espèce au hasard (toutes familles), rareté tirée dans la table de Qualité 3, mutation tirée (buses 0), **taille = 15 % du plus gros squishy de l'attrapeur** (minimum 5). **2 au plus par joueur et par Rush.**
- Avec `Features.BoopRush = "off"`, ils sortent quand même aux heures du Rush (« Wobbler Time »), pour tous.

#### 4.21.6 La démonstration de Plop

Pendant l'accueil (§3), si aucun Rush ni MEGA ne commence avant 4:00 de jeu, Plop (la mascotte) éternue devant le portail du nouveau joueur et s'enfuit pendant 20 s (8 studs/s, visible par lui seul). Attrapé : un bébé Plop (10 % de la taille du Plop du joueur, minimum 10). Raté : Plop revient, fait un clin d'œil, et la démonstration ne se rejoue pas.

### 4.22 MEGA SQUISH

| Phase | Détail |
|---|---|
| Alerte (:19:45, :49:45) | Grande ombre ronde sur la place, bannière « MEGA SQUISH ! », compte à rebours de 15 s |
| Atterrissage (:20:00, :50:00) | Un squishy géant (24 studs de diamètre, espèce de la semaine en rotation) tombe sur le MEGA pad. Onde de choc, vibration atténuée par la distance (§10.5) |
| Pression (60 s) | Chaque joueur à 20 studs au plus du centre presse (action contextuelle). **1 point** par pression, **3 points** si PERFECT (le géant rebondit avec une période de 2 s ; fenêtre ±0,2 s autour du sommet). Recharge 0,4 s par joueur. La barre de serveur se remplit au-dessus du géant |
| Objectif | `ceil((30 + 50 × N) × indulgence)`, N = joueurs sur le serveur à l'atterrissage (Cozy compris). Indulgence 1 ; 0,8 après un échec ; 0,65 après 2 échecs de suite ; retour à 1 après une réussite. Cible de conception : **≈ 80 % de réussite** |
| Réussite | Le géant ÉCLATE en pluie de bébés. Paliers fixes par participant : ≥ 10 points → 1 bébé ; ≥ 40 → 2 ; ≥ 80 → 3. Plus 60 s de revenu, +1 Fame, jauge +5 |
| Échec | Le géant soupire et s'envole doucement. Chaque participant (≥ 10 points) : 60 s de revenu, « Presque ! » |

- **Bébé du MEGA** : espèce au hasard (toutes familles), rareté dans la table de Qualité min(8, qualité du joueur + 2), **chances de mutation × 2**, taille = 20 % du plus gros squishy du joueur (minimum 10), 0 étoile.
- **MEGA MOON SQUISH** (à :20 pendant une Jelly Moon) : mêmes règles, et chaque bébé a 25 % de chance d'être Lunaire.
- Pendant le MEGA, on peut continuer à presser chez soi ; les créatures en fuite personnelles sont en pause.

### 4.23 Jauge du serveur (Wobble Meter) et Jelly Moon

**Jauge du serveur**

Le concept proposait d'additionner la taille de tous les squishies. Avec des tailles de 1 à 1e30, un seul vétéran remplirait la jauge et un nouveau n'y compterait jamais. La jauge compte donc les **actions** de tous, ce qui donne à chacun, même débutant, une vraie part (Annexe A).

| Action (n'importe quel joueur) | Points |
|---|---|
| Pression | 1 (+1 si PERFECT) |
| Naissance dans la Cuve | 2 |
| Pression de pet-sitting | 2 |
| Fusion (par étape de combo) | 3 |
| Créature en fuite attrapée, Wild Wobbler attrapé, Golden vu de près | 4 |
| Capture pendant le Rush (bébé ou Héros) | 6 |
| Participation au MEGA (≥ 10 points) | 5 |
| Nourrir Plop | 10 |
| Grand Splorch | 25 |

- **Objectif** = `500 × max(2, N)` points (N = joueurs sur le serveur, recalculé en direct). Avec 16 joueurs actifs (≈ 30 points par minute chacun), la jauge se remplit en ≈ 15 à 20 min ; un joueur seul la remplit en ≈ 35 min.
- **Pleine** : Plop danse sur la place (8 s, grand spectacle, file du §2.4), puis **WOBBLE PARTY** : ×2 pièces et croissance pour tout le serveur pendant **5 min**. La jauge est figée pendant la fête, puis repart de 0.
- Grande jarre de gelée sur la place + petite barre dans le HUD.

**Jelly Moon (samedi, et rattrapage le dimanche)**

| Élément | Règle |
|---|---|
| Horaire | Samedi 16:00, 18:00, 20:00, 22:00 UTC (20 min chacune) ; dimanche 16:00 UTC (20 min). Le MEGA de :20 qui suit chaque séance devient MEGA MOON SQUISH |
| Ambiance | Ciel violet et sarcelle, grosse lune, musique douce un peu étrange. Les squishies Lunaires ont un petit troisième œil et des gouttes qui perlent. Mignon et bizarre, **jamais effrayant** |
| Mutations | Chances × 2 et Lunaire 3 % (§4.5) |
| BOOP RUSH | Les Rush de :05 et :15 rendent **Mythiques et Secrets boopables** |
| Espèce de la Lune | Moonplop (Secret) peut naître ; ensuite, chaque semaine, une nouvelle espèce arrive en données et fait ses débuts pendant la Lune (§7.6) |
| Autel de la Lune | Sur la place. Un joueur présent au moins 5 min pendant une séance reçoit **1 Goutte de Lune** à la fin de la séance : une naissance de Qualité (la sienne + 1) avec mutation **Lunaire garantie**. Une par séance au plus |

### 4.24 Rythme de progression et simulation (porte de qualité)

Joueur de référence : 35 min de jeu actif le premier jour, puis 30 min par jour ; une pression toutes les 2 s sur le squishy prêt le plus rentable, PERFECT 40 % du temps ; Pot encaissé toutes les 40 s ; achats au moins cher utile d'abord (Tapis, Enclos si plein, décorations, puis Cuve) ; fusion dès qu'une paire de jumeaux existe ; 85 % des créatures en fuite attrapées ; hors ligne 16 h par nuit ; boosts ×2 20 % du temps ; événements moyens (60 % des Rush avec un bébé, 50 % des Wild Wobblers, 2 bébés par MEGA, 30 % des Golden, 1 cadeau de Grand Splorch toutes les 20 min) ; aucun achat Robux.

| Jalon | Cible (médiane) | Tolérance |
|---|---|---|
| Première pression | 10 s | ≤ 15 s |
| Premier achat (Tapis) | 25 s | ≤ 30 s |
| À 5:00 : squishies | 4 | 3-4 |
| À 5:00 : fusions | 1-2 | ≥ 1 |
| À 5:00 : captures | 1-2 | ≥ 1 |
| Première balade (taille 1 200) | 3:50 | ≤ 5:00 |
| À 5:00 : pièces en poche | 1 500 | 1 000-2 000 |
| Premier Grand Splorch | 13 min | **12-15 min** (médiane) ; 10-18 min pour 80 % des joueurs |
| À 30 min : R | 2 | 1-3 |
| À 30 min : tampons de Squishydex | 13 | 10-18 |
| Fin du jour 1 (35 min) : R | 2 | 2-3 |
| Fin du jour 7 : R | 9 | 7-11 |
| Fin du jour 7 : plus gros squishy (avant Grand Splorch) | ≈ 1,5e7 | 5e6-5e7 |
| Fin du jour 7 : tampons de Squishydex (espèces + mutations) | 90 | 75-110 |
| Fin du jour 7 : au moins un Épique ou mieux | 100 % des joueurs | ≥ 95 % |
| Fin du jour 28 : R | 17 | 14-20 |
| Premier squishy de 1e12 (1 000 milliards) | vers le jour 35 (joueur à 30 min/jour) ; vers le jour 10 pour un joueur à 2 h/jour | — (longue traîne) |

**Simulation (porte bloquante).** Un test Lune (`tests/specs/EconomyPacing.spec.luau`) simule 200 joueurs de référence sur 28 jours avec les tables de `Shared/Config/Balance` et `Shared/Config/Squishies`, le même code de formules que le jeu (`Shared/Logic/Formulas`, `Odds`, `FusionRules`), et une graine fixe. Le test échoue si la médiane d'un jalon sort de sa tolérance. Un prototype hors moteur de ce modèle, écrit pour ce GDD avec ces valeurs exactes, donne : pièces à 5:00 médiane 1 290 (10 %-90 % : 304-10 100), 4 squishies, 2 fusions, 2 captures, première balade à 3:52, premier Grand Splorch à 12,8 min (11,7-15,7), R = 2 à 30 min et en fin de jour 1, R = 9 au jour 7, R = 13 au jour 14, R = 17 au jour 28, 89 tampons au jour 7. Le prototype ne compte ni la Fame, ni les trophées, ni les bonus de famille, ni les captures « Héros » : les cibles ci-dessus sont donc légèrement prudentes.

Leviers sans code : `Balance.Splorch.Targets`, `Balance.Tiles.*.Base/Growth`, `Balance.Vat.Interval`, `Balance.Income.Coef` (0,02), `Balance.Press.Seconds` (12), `Balance.Offline.*`.

### 4.25 Boosts, plafonds et limites anti-abus

**Boosts ×2** : boost de serveur (Wobble Party gratuite, Squish Party payée, Squish Party d'administrateur) et boost personnel (objectifs, Nourrir Plop). Ils ne se cumulent jamais : `B` vaut 2 au plus. Une Squish Party payée n'est jamais « mangée » par un boost gratuit : la fête payée passe d'abord, la Wobble Party attend son tour. Un boost personnel est **mis en pause** pendant un boost de serveur (son minuteur s'arrête), pour que le joueur ne perde rien.

| Plafond ou limite | Valeur |
|---|---|
| Bébés de BOOP RUSH | 10 par jour et par joueur |
| Wild Wobblers | 2 par joueur et par Rush |
| Golden Wobbler | Le gagnant ne peut pas regagner pendant 20 min |
| Bébés de Grand Splorch reçus | 10 par jour |
| Bébés du MEGA | 3 par MEGA (paliers) |
| Taille de **tout** bébé ou cadeau | Au plus **2 × le plus gros squishy** du joueur qui le reçoit |
| Fame d'être boopé | 30 par jour |
| Fame en relâchant | 20 par jour |
| Pressions de pet-sitting récompensées | 300 par jour |
| Applaudissements récompensés | 10 par jour |
| Pressions | 12 par seconde au plus (au-delà, ignorées) |
| Fuites du Rush | 2 par ranch et par Rush ; 10 en même temps sur le serveur |
| Squish Party | File de 30 min au plus par serveur ; 1 achat toutes les 20 min par joueur |
| Comptes multiples qui se boopent | Bornés par les plafonds de bébés, la taille ≤ 2 × le plus gros, et 1 boop par paire et par Rush |
| Vitesse, téléportation, bond sans recharge | Contrôle de déplacement avec budget d'action (§12.8) |
| Rafales de messages réseau | Seau à jetons par action (§12.7) |
| Échanges et dons de squishies | Aucun au lancement (les colis entre amis arrivent en janvier, §17) |

---

## 5. Contenu complet

### 5.1 Les 26 espèces

L'identifiant numérique est **définitif** (il est sauvegardé) : on ne réordonne jamais la table, on ajoute à la fin. Chaque espèce est **une ligne de données** de `Shared/Config/Squishies` : proportions du corps (X / Y / Z), haut de tête (oreilles, collerette…), yeux, couleurs (principale / secondaire, RGB), motif, tremblement (fréquence, amplitude d'écrasement). Une nouvelle espèce par semaine = une nouvelle ligne, sans nouveau code (§7.6).

| Id | Clé | Nom | Famille | Rareté | Corps X / Y / Z | Haut de tête | Yeux | Couleurs | Motif | Tremblement | Aspect en une ligne |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `plop` | Plop | Jelly | Commun | 1,0 / 1,0 / 1,0 | Antenne en goutte | Grands brillants | (140, 220, 255) / (255, 255, 255) | Ventre clair | 1,0 Hz / 8 % | Boule de gelée bleu menthe, une goutte sur la tête, joues roses : la mascotte |
| 2 | `wibble` | Wibble | Jelly | Peu commun | 0,9 / 1,2 / 0,9 | Calotte de caramel | Endormis | (255, 214, 140) / (170, 100, 50) | Calotte | 1,4 Hz / 12 % | Pudding au caramel qui tremblote et a toujours l'air de faire la sieste |
| 3 | `jiggleberry` | Jiggleberry | Jelly | Rare | 1,0 / 1,05 / 1,0 | Feuille | Points | (240, 80, 120) / (120, 200, 90) | 8 pépins clairs | 1,2 Hz / 10 % | Framboise de gelée toute bosselée, coiffée d'une feuille |
| 4 | `grand_gloop` | Grand Gloop | Jelly | Légendaire | 1,3 / 0,9 / 1,3 | Couronne minuscule | Étoiles | (120, 160, 255) / (255, 220, 120) | Dégradé en 3 couches | 0,7 Hz / 6 % | Grande gelée royale en trois couches brillantes |
| 5 | `mochi_mew` | Mochi Mew | Kitty | Commun | 1,05 / 0,95 / 1,0 | Oreilles de chat | Points | (250, 245, 240) / (255, 180, 200) | Intérieur d'oreilles rose | 1,1 Hz / 8 % | Chat-mochi tout blanc, oreilles roses, petites moustaches |
| 6 | `purrpudding` | Purrpudding | Kitty | Peu commun | 1,0 / 1,0 / 1,0 | Oreilles de chat | Fermés, heureux | (255, 170, 90) / (200, 110, 50) | Rayures tigrées | 1,2 Hz / 10 % | Pudding tigré orange qui ronronne les yeux fermés |
| 7 | `whiskerwob` | Whiskerwob | Kitty | Épique | 0,95 / 1,1 / 0,95 | Oreilles + longues moustaches-antennes | Étoiles | (190, 150, 255) / (255, 240, 255) | Queue en spirale | 1,0 Hz / 9 % | Chat lilas aux moustaches qui ondulent comme des antennes |
| 8 | `blossompurr` | Blossompurr | Kitty | Mythique | 1,0 / 1,0 / 1,0 | Oreilles + couronne de fleurs | Cœurs | (255, 170, 210) / (255, 255, 255) | Pétales qui tombent (3/s) | 0,9 Hz / 7 % | Chat rose cerisier couronné de fleurs, qui sème des pétales |
| 9 | `ribbit_drop` | Ribbit Drop | Froggy | Commun | 1,1 / 0,9 / 1,0 | Yeux globuleux sur le dessus | Globuleux | (120, 210, 110) / (230, 250, 180) | Ventre clair | 1,3 Hz / 10 % | Goutte-grenouille verte au grand sourire |
| 10 | `lilypuff` | Lilypuff | Froggy | Peu commun | 1,1 / 0,85 / 1,1 | Yeux globuleux + chapeau nénuphar | Globuleux | (90, 200, 190) / (140, 230, 120) | Taches de mare | 1,1 Hz / 9 % | Grenouille sarcelle coiffée d'une feuille de nénuphar |
| 11 | `croakaroo` | Croakaroo | Froggy | Rare | 0,9 / 1,15 / 0,9 | Yeux globuleux | Globuleux, clin d'œil | (255, 220, 80) / (255, 140, 60) | Taches orange | 1,5 Hz / 12 % | Grenouille jaune à taches orange, toujours prête à sauter |
| 12 | `boingtoad` | Boingtoad | Froggy | Épique | 1,0 / 1,0 / 1,0 | Yeux globuleux + ressort sous le ventre | Étoiles | (160, 110, 230) / (255, 230, 120) | Taches en étoile | 2,0 Hz / 18 % | Crapaud violet monté sur ressort, qui rebondit plus que tout le monde |
| 13 | `frillo` | Frillo | Axolo | Commun | 1,1 / 0,9 / 1,15 | Collerette (3 branches de chaque côté) | Points | (255, 175, 200) / (255, 110, 150) | — | 1,0 Hz / 8 % | Axolotl rose aux petites branches qui ondulent |
| 14 | `gillygum` | Gillygum | Axolo | Peu commun | 1,1 / 0,9 / 1,15 | Collerette en bulles de chewing-gum | Brillants | (150, 170, 255) / (255, 140, 220) | Bulles | 1,1 Hz / 9 % | Axolotl bleu dont la collerette fait des bulles roses |
| 15 | `lotlolly` | Lotlolly | Axolo | Épique | 1,0 / 1,0 / 1,1 | Collerette | Clin d'œil | (255, 200, 120) / (120, 220, 255) | Spirale de sucette | 1,0 Hz / 9 % | Axolotl en spirale de sucette, qui fait un clin d'œil |
| 16 | `coralotl` | Coralotl | Axolo | Légendaire | 1,15 / 1,0 / 1,2 | Couronne de corail | Brillants | (255, 120, 100) / (255, 230, 200) | 5 petites bosses de récif | 0,8 Hz / 7 % | Axolotl couleur corail, couronné d'un récif lumineux |
| 17 | `bunbun` | Bunbun | Bunny | Commun | 1,0 / 1,0 / 1,0 | Longues oreilles tombantes | Points | (255, 240, 210) / (255, 190, 200) | Bout de nez rose | 1,2 Hz / 9 % | Lapin crème aux oreilles qui tombent |
| 18 | `hopscotch` | Hopscotch | Bunny | Peu commun | 0,95 / 1,05 / 0,95 | Une oreille droite, une tombante | Endormis | (180, 195, 220) / (255, 255, 255) | Chaussettes blanches | 1,4 Hz / 11 % | Lapin gris-bleu, une oreille levée, une oreille baissée |
| 19 | `clover_hop` | Clover Hop | Bunny | Rare | 1,0 / 1,0 / 1,0 | Longues oreilles + trèfle | Brillants | (160, 230, 170) / (90, 170, 90) | Trèfle sur le ventre | 1,3 Hz / 10 % | Lapin menthe porte-bonheur, un trèfle sur la tête |
| 20 | `moonhop` | Moonhop | Bunny | Épique | 1,0 / 1,05 / 1,0 | Oreilles à bouts en croissant | Étoiles | (60, 70, 140) / (255, 240, 160) | Taches d'étoiles | 1,0 Hz / 9 % | Lapin bleu nuit constellé, aux oreilles en croissant de lune |
| 21 | `nubbin` | Nubbin | Spiky | Commun | 1,05 / 0,95 / 1,05 | 3 bosses douces sur le dos | Points | (255, 200, 160) / (255, 150, 120) | — | 1,1 Hz / 8 % | Petit dragon pêche avec trois bosses toutes molles |
| 22 | `prickle_puff` | Prickle Puff | Spiky | Peu commun | 1,0 / 1,0 / 1,0 | 7 pics doux | Brillants | (200, 150, 110) / (255, 230, 200) | Ventre crème | 1,2 Hz / 10 % | Hérisson de gelée aux pics tout mous |
| 23 | `drago_drop` | Drago Drop | Spiky | Épique | 1,0 / 1,0 / 1,05 | Petites ailes + cornes douces | Étoiles | (130, 200, 255) / (255, 255, 255) | Écailles claires | 1,0 Hz / 9 % | Bébé dragon bleu ciel aux ailes trop petites pour voler |
| 24 | `emberwob` | Emberwob | Spiky | Légendaire | 1,1 / 1,05 / 1,1 | Crête en forme de flamme, toute douce (sans feu) | Brillants | (255, 130, 60) / (255, 220, 120) | Ventre doré | 0,9 Hz / 7 % | Dragon orange chaud à la crête de flamme en gelée |
| 25 | `royal_plop` | Royal Plop | (Secret) | Secret | 1,05 / 1,05 / 1,05 | Couronne + petite cape | Étincelles | (140, 220, 255) / (255, 210, 80) | Goutte dorée | 1,0 Hz / 8 % | Plop couronné à cape rouge, goutte dorée sur la tête |
| 26 | `moonplop` | Moonplop | (Secret) | Secret | 1,0 / 1,0 / 1,0 | Antenne en croissant | 3 yeux (un petit au milieu) | (210, 220, 255) / (150, 130, 255) | Gouttes qui perlent | 0,8 Hz / 7 % | Plop argenté de la Lune, avec un petit troisième œil tout mignon ; naît seulement pendant la Jelly Moon |

Répartition : Commun 6, Peu commun 6, Rare 3, Épique 5, Légendaire 3, Mythique 1, Secret 2. Chaque famille a 4 espèces : un Commun, un Peu commun, puis deux plus rares. Les Secrets n'ont pas de famille (page « Secrets » du Squishydex) et ne comptent pas dans les bonus de famille.

**Champs réservés pour plus tard** dans chaque ligne (valeur au lancement) : `release = 0` (horodatage UTC d'arrivée ; les lignes futures sont publiées en avance et s'activent seules), `duo = false` (espèce Duo, janvier), `recipe = nil` (combinaison World First, janvier), `limitedUntil = 0` et `encore = {}` (semaines « Encore », février).

**Rotation du MEGA SQUISH** : le géant prend l'espèce `((semaine + numéro du MEGA dans la semaine) mod 24) + 1`, Secrets exclus (semaine = `Clock.week()`).

**Noms** : tous inventés pour ce jeu. On évite tout ce qui rappelle Squishmallows (pas de « -mallow »), les personnages connus et les mèmes. Vérification de marque avant publication (§18).

### 5.2 Fabrication des squishies en formes simples (`Shared/Render/SquishyBuilder`)

Construits **côté client** à partir de la ligne de données et de 4 nombres (espèce, mutation, étoiles, taille). Toutes les pièces sont ancrées, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false`. **12 pièces au plus** par squishy en détail complet.

| Pièce | Primitive | Dimensions (× diamètre D) | Matériau / couleur |
|---|---|---|---|
| Corps | Ball, mise à l'échelle X / Y / Z de la ligne | D | SmoothPlastic, couleur principale (ou mutation) |
| Ventre / motif | 1 à 4 petites Balls ou Cylinders plats | 0,1 à 0,5 D | Couleur secondaire |
| Yeux (2, ou 3 pour Moonplop) | Ball | 0,22 D, à (±0,2 ; +0,12 ; −0,44) D | Noir, Reflectance 0,3 ; reflet blanc 0,07 D |
| Joues (2) | Cylinder plat | Ø 0,18 D, épaisseur 0,03 D | Rose (255, 160, 190) |
| Bouche | 3 petites Balls en arc (sourire) | 0,04 D chacune | Brun foncé (90, 50, 50) |
| Haut de tête | 1 à 3 pièces selon le type (Ball, WedgePart, Cylinder) | 0,2 à 0,5 D | Couleur secondaire |

**Étoiles** : 1 à 5 petites étoiles `Neon` dorées en arc au-dessus de la tête (BillboardGui en dessous de 60 studs, rien au-delà).

**Niveaux de détail** (distance à la caméra) : < 60 studs = modèle complet animé à chaque image ; 60-140 studs = corps + yeux (3 pièces), animation à 15 Hz ; > 140 studs = corps seul, immobile ; ranchs à plus de 220 studs = seulement la silhouette du meilleur squishy et un compteur « ×N ». Graphismes légers : distances × 0,6.

**Animation de repos** (client, aucun trafic réseau) : rebond de période 1,2 s (celle du PERFECT), hauteur 0,18 D ; à chaque contact avec le sol, écrasement `(1 + a, 1 − a, 1 + a)` pendant 0,1 s (a = amplitude de tremblement de la ligne), puis tremblement amorti à la fréquence de la ligne ; clignement toutes les 3 à 6 s (yeux à 0,1 en Y pendant 0,08 s) ; regarde le joueur le plus proche à 15 studs au plus. Seul le corps change de taille (une écriture de `Size`) ; les autres pièces suivent par `BulkMoveTo`. Au plus 80 squishies animés à pleine cadence sur un client.

### 5.3 Plop, la mascotte

- Un grand Plop (diamètre 6 studs), bleu menthe, avec un petit nœud papillon jaune, sur sa scène au bord de la place. Il fait coucou, montre la jauge, danse quand elle est pleine.
- Pendant l'accueil, une copie de Plop, visible seulement par le nouveau joueur, vient dans son ranch : il pose le petit Plop, montre les dalles du doigt, fait la démonstration d'éternuement (§4.21.6).
- Il ne parle jamais avec des phrases : des gestes, des icônes et des petits sons (« plop ! »).

### 5.4 Cosmétiques

| Catégorie | Élément | Obtention |
|---|---|---|
| Selles (couleur) | Classique (couleur du ranch) | Gratuit |
| | Pêche / Fraise | Plop jour 3 / jour 21 |
| | Menthe / Lavande | Squishydex 25 / 130 |
| | Nuage, Rayures bonbon, Étoilée, Cookie, Bulle, Royale | Pack Selles et Traînées |
| Traînées (derrière la monture) | Bulles / Vermicelles | Squishydex 50 / Plop jour 50 |
| | Ruban arc-en-ciel, Paillettes, Gouttes de gelée, Étoiles, Flocons, Notes de musique | Pack Selles et Traînées |
| Tenues (sur un squishy choisi) | Bavoir de Plop | Plop jour 7 |
| | Pull douillet, Couronne de gelée, Écharpe d'hiver | Produits Robux (§8.3) |
| Titres (sous le nom) | Little Collector, Squishologist, Dex Master | Squishydex 10 / 75 / 200 |
| | Splorch Star, Splorch Legend, Splorch Hero, Jelly Titan | R = 5 / 10 / 15 / 20 |
| | Plop's Best Friend | Plop jour 30 |
| | Biggest Squish, Combo Star, Top Catcher, Super Helper, Big Heart | Top 10 d'un classement de la semaine (pendant la semaine suivante) |
| Thème de ranch | Couleur du ranch / Moonlit / Candy Night | Gratuit / Squishydex 160 / Plop jour 75 |
| Drapeaux de ranch | Squishydex / « Jour 14 » | Squishydex 100 / Plop jour 14 |
| Emotes en plus | Belly Flop / Couronne | Plop jour 10 / Squishydex 260 |

**Palette des 16 ranchs** (couleur du propriétaire) : 1 Corail (255, 130, 120) · 2 Pêche (255, 180, 130) · 3 Citron (250, 225, 100) · 4 Citron vert (170, 225, 100) · 5 Menthe (110, 225, 170) · 6 Sarcelle (70, 205, 205) · 7 Ciel (110, 180, 255) · 8 Pervenche (140, 150, 250) · 9 Lilas (185, 140, 250) · 10 Orchidée (225, 130, 225) · 11 Rose (255, 130, 180) · 12 Framboise (230, 90, 130) · 13 Caramel (215, 160, 100) · 14 Sable (225, 205, 160) · 15 Écume (150, 235, 215) · 16 Nuage (180, 195, 215). Ranch libre : gris (130, 130, 140), sans lumière.

### 5.5 Récapitulatif du contenu au lancement

| Type | Au lancement |
|---|---|
| Espèces | 24 (6 familles × 4) + 2 Secrets = 26 |
| Raretés | 7 |
| Mutations | 9 (dont Lunaire, seulement le samedi, et Flop, la plus rare) |
| Squishydex | 26 pages d'espèces + 234 entrées de mutation + 130 badges d'étoiles ; 6 bonus de famille ; 9 jalons |
| Dalles | Tapis à Goûter (12 niveaux), 12 décorations, Vitesse (10), Qualité (8), Buses (5), Enclos (14), Lit douillet |
| Événements récurrents | Créature en fuite personnelle, Golden Wobbler, BOOP RUSH + Wild Wobblers, MEGA SQUISH, jauge du serveur et Wobble Party, Jelly Moon |
| Rétention | Nourrir Plop (12 paliers), 3 objectifs du jour (pool de 18), 5 classements de la semaine, carte « Plop a sommeil » |
| Cosmétiques | 11 selles, 8 traînées, 4 tenues, 12 titres + 5 titres de la semaine, 3 thèmes, 2 drapeaux, 2 emotes en plus |
| Monde | Wobbleton (place, rues, collines), 16 ranchs, costume d'hiver « Frost & Sprinkles » |

---

## 6. Social et multijoueur (16 joueurs)

Tout fonctionne **sans chat** : le chat exige une vérification d'âge (Étude §6.3). Le jeu ne lit jamais le texte du chat. Sur console, la fenêtre de chat est coupée (§10.6).

### 6.1 Attribution des ranchs et ranchs voisins

- 16 ranchs pour 16 places. À l'arrivée, `RanchService` donne un ranch libre. **Si un ami Roblox est déjà sur le serveur**, le joueur reçoit le ranch libre le plus proche du sien (vérifié avec `Player:IsFriendsWith`, sous `pcall`, résultat mis en cache pour la session). Les amis qui rejoignent ensemble sont donc voisins.
- Le personnage apparaît dans son ranch (`SpawnLocation` du ranch). Après une chute ou une réinitialisation, il réapparaît dans son ranch.
- Si la taille du serveur est réglée au-delà de 16 dans le Creator Hub, un joueur sans ranch voit un message amical puis est renvoyé après 30 s (« Wobbleton est pleine ! Rejoins un autre serveur. »), sauf si un ranch se libère (leçon de Comet Conga, analytics `ServerFullKick`).

### 6.2 Bonus d'amis

**+10 % de revenu par ami Roblox présent sur le serveur, +40 % au plus** (4 amis). Un petit cœur avec le nombre d'amis s'affiche à côté du compteur de pièces. Les ranchs d'amis sont reliés la nuit par un ruban lumineux (repère visuel, image de vignette).

### 6.3 On n'entre jamais chez les autres

- Chaque ranch a une clôture (solide pour tous) et un **portail de gelée** : le propriétaire le traverse, les autres rebondissent dessus.
- Côté serveur, à chaque tick (10 Hz), un joueur dont la position est dans le ranch d'un autre est repoussé doucement à 6 studs devant le portail (`PivotTo`), avec un petit rebond et le message « C'est le ranch de Mira ! » (ou « C'est le ranch 7 ! » si le nom est caché). Aucune exception, même pour les amis.
- Pendant le BOOP RUSH, on boope **par-dessus la clôture**, depuis la rue. La poursuite a lieu **dans la ville**.

### 6.4 Pet-sitting (presser chez un ami)

- Quand un **ami Roblox** se tient devant ta clôture (à 10 studs au plus), jusqu'à 3 de tes squishies prêts viennent à la clôture (hors Rush ; ils ne s'enfuient jamais).
- L'ami les presse depuis la rue (même geste que chez soi, PERFECT compris). **Le propriétaire** reçoit la récompense normale de la pression (sans PERFECT). **Le visiteur** reçoit 10 s de son propre revenu (×2 si PERFECT) et 1 point du classement « Plus serviable ». La recharge de 8 s du squishy s'applique.
- 300 pressions de pet-sitting récompensées par jour et par visiteur. Fonctionne même si le propriétaire est occupé ailleurs sur le serveur.

### 6.5 Emotes et signaux

| Signal | Croix directionnelle | Clavier | Icône | Emote jouée |
|---|---|---|---|---|
| Salut | ↑ | 1 | Main | `wave` |
| Merci | → | 2 | Cœur | `wave` |
| À l'aide | ↓ | 3 | Bouée | `point` |
| Bravo | ← | 4 | Étoile | `cheer` |

- Téléphone : bouton Emote (72 px de référence) qui ouvre 4 secteurs.
- Affichage : bulle-icône de 3 × 3 studs au-dessus de la tête pendant 2,5 s, visible jusqu'à 150 studs.
- Limite : 1 signal toutes les 1,5 s (le serveur accepte 1 toutes les 1,2 s pour absorber la gigue du réseau, leçon de Comet Conga).
- L'emote est jouée par le client sur son propre personnage (`Humanoid:PlayEmote`, sous `pcall`).

### 6.6 Voir ce que font les autres

- **Silhouette** : le meilleur squishy de chaque ranch flotte au-dessus du ranch (Y = 40), à sa vraie échelle jusqu'à 19×, avec sa taille. On voit de loin qui a le plus gros.
- **Statue de la place** : le plus gros squishy du serveur, en direct, sur un socle avec le nom du propriétaire (ou « Ranch 7 ») et sa taille.
- **Fanfare des records du serveur** : le premier joueur du serveur à dépasser 1 million, 1 milliard, 1e12 et 1e15 a droit à une fanfare et une bannière (une fois par seuil et par serveur).
- **Bannières de serveur** : file de 3 au plus, 3 s chacune, priorité décroissante : Grand Splorch > naissance Secret ou Mythique > combo ≥ 5 > naissance Légendaire > fanfare de record > Golden Wobbler attrapé > Squish Party offerte. Un même joueur déclenche au plus une bannière toutes les 10 s. Exemples : « Mira : GRAND SPLORCH ! », « Noah a fait naître un SECRET Royal Plop (1 sur 2 500) ! », « Léa : COMBO x5 ! ».

### 6.7 Grand Splorch des autres : cadeaux et applaudissements

- Chaque Grand Splorch fait pleuvoir sur **tous** les autres joueurs : 60 s de leur revenu et un bébé (§4.15).
- Pendant 8 s, chaque autre joueur voit un gros bouton **APPLAUDIR** (croix → à la manette, F au clavier). Appuyer joue l'emote `cheer` et lance un arc de confettis vers le héros. L'applaudisseur gagne 10 s de son revenu (10 applaudissements récompensés par jour) ; le héros voit « 12 joueurs t'applaudissent ! ».

### 6.8 Moments coopératifs

- **MEGA SQUISH** (§4.22) : tout le serveur presse le géant ; chaque participant reçoit au moins un bébé en cas de réussite.
- **Jauge du serveur** (§4.23) : chaque action de chacun compte ; pleine, tout le monde gagne ×2 pendant 5 min.
- **Golden Wobbler** (§4.11) : course amicale ; tous ceux qui sont près gagnent quelque chose.
- **Squish Party** (§8.3) : un achat qui profite à tout le serveur.

### 6.9 Classements de la semaine

| Classement | Mesure | Dépend de l'argent ? |
|---|---|---|
| **Plus gros squishy** (Biggest Squish) | Plus grande taille atteinte cette semaine | Non : le pass ×2 Pièces ne touche jamais la taille ; la Squish Party profite à tout le serveur |
| **Meilleur combo** (Combo Star) | Plus long combo de fusion (égalité : taille du résultat) | Non |
| **Meilleure capture** (Top Catcher) | Plus forte valeur de capture = rareté × mutation de la créature attrapée (fuite, Golden, Rush, Wild Wobbler) ; égalité : taille | Non |
| **Plus serviable** (Super Helper) | Pressions de pet-sitting récompensées | Non |
| **Plus généreux** (Big Heart) | Bébés donnés : bébés reçus par d'autres grâce à tes squishies en fuite et à tes Grands Splorch | Non |

- Stockage : un `OrderedDataStore` par classement et par semaine (`Weekly_<clé>_<semaine>`). Écriture quand un joueur bat son record de la semaine (file par serveur, vidée toutes les 60 s) ; lecture du top 10 toutes les 120 s. Tableau du serveur en direct.
- Remise à zéro le lundi 00:00 UTC. Le top 10 de chaque classement porte le titre de la semaine pendant la semaine suivante.
- Les joueurs exclus par l'anti-triche (§12.8) ne sont pas écrits.
- **Cacher mon nom** (Réglages, désactivé par défaut) : le joueur apparaît comme « Squishy Fan #4821 » (nombre tiré du hash de son identifiant) dans les bannières, les classements, sur la statue et sur le panneau de son ranch.

### 6.10 Serveurs privés

Gratuits. **BOOP RUSH en mode Cozy pour tous par défaut** ; le propriétaire du serveur privé peut l'autoriser (§4.21.1). Tout le reste est identique.

### 6.11 Moments viraux prévus

| Moment | Pourquoi il se filme (clip ≤ 30 s) |
|---|---|
| La sirène du BOOP RUSH | Ciel rose, gloussements, des squishies éternuent par-dessus 16 clôtures, tout le serveur court en ville. Du chaos sans enfant qui pleure |
| Le Grand Splorch | Un géant éclate au ralenti au-dessus de la place, pluie de cadeaux, 15 joueurs applaudissent |
| Le combo géant | « COMBO x5 ! », un squishy qui remplit l'enclos |
| L'éclosion rare | Bannière serveur, ralenti, « SECRET Royal Plop · 1 sur 2 500 » |
| Le Flop Plop | La créature la plus rare a l'air ratée et fait « blorp » : le mème |
| Un Mythique boopé pendant la Jelly Moon | Un géant lumineux traverse la ville, poursuivi par 15 joueurs, certains sur leur monture |
| Chevaucher un squishy grand comme une maison | Rebondir par-dessus les autres |
| MEGA SQUISH | Tout le serveur presse un géant jusqu'à ce qu'il ÉCLATE en pluie de bébés |
| « De 0 à 1 million de milliards » | Nombres géants à l'écran, statue de la place qui grandit en direct |

---

## 7. Rétention

### 7.1 Crochets par horizon (fidélité sur 28 jours, Étude §6.2)

| Horizon | Crochets |
|---|---|
| **J1** | Récompense à 10 s ; fusion à 1:00 ; capture à 2:00 ; monture à 3:50 ; premier Grand Splorch vers 13 min ; un événement de serveur au plus toutes les 10 min ; message « Tes squishies grandissent même quand tu dors » à 10 min de jeu et en bas du panneau Réglages |
| **J2-J7** | Écran de retour (croissance hors ligne visible) ; Nourrir Plop (jours au total) ; 3 objectifs du jour ; nouvelles familles à R = 1, 3, 5 ; Squishydex ; Meilleur Ami ; première Jelly Moon |
| **J8-J28** | Grands Splorch 9 à 17 ; mutations rares (Galaxie, Arc-en-ciel, Glitch, Flop) ; étoiles ★5 ; Étagère à trophées ; Fame ; classements de la semaine ; une espèce nouvelle chaque semaine ; costumes de saison |

### 7.2 Écran de retour

S'ouvre au chargement si le joueur a été absent au moins 10 min. Contenu : « Pendant ton absence (5 h 12) : **Plop a grossi de +X** » (le Meilleur Ami n° 1, sinon le plus gros), le Plop qui gonfle à l'écran (0,8 s, `Quint Out`), « +Y pièces dans ton Pot », et « Grand Splorch prêt ! » si l'objectif est atteint. Un bouton « Super ! » (96 px de référence), sélectionné d'office à la manette. Aucune publicité, aucune offre.

### 7.3 Nourrir Plop (jours au total)

Une fois par jour UTC, maintenir 5 s devant le bol. Les jours sans palier : boost personnel ×2 (croissance et pièces) pendant 5 min. Les paliers comptent le total de jours, jamais une série.

| Jours au total | Récompense (en plus d'un boost personnel ×2 de 15 min) |
|---|---|
| 1 | Autocollant « Jour 1 » au-dessus du ranch |
| 2 | Pièces = 10 min de revenu |
| 3 | Selle Pêche |
| 5 | Traînée Bulles roses |
| 7 | Tenue « Bavoir de Plop » |
| 10 | Emote Belly Flop |
| 14 | Drapeau « Jour 14 » |
| 21 | Selle Fraise |
| 30 | Titre « Plop's Best Friend » |
| 50 | Traînée Vermicelles |
| 75 | Thème de ranch « Candy Night » |
| 100 | Bol doré et couronne pour Plop |

### 7.4 Objectifs du jour

Chaque jour UTC : 3 objectifs (facile, moyen, difficile), tirés de manière déterministe (`Hash(jour, UserId)`) dans le pool ci-dessous. 1 relance gratuite par jour. Les objectifs **Rush** ne sont jamais proposés à un joueur Cozy ; les objectifs **Ami** seulement à un joueur qui a joué avec un ami dans les 7 derniers jours. **Jour 1** (accueil) : fixes, « Presse 30 squishies », « Attrape 2 créatures », « Fais 1 fusion ».

Récompenses : facile = 3 min de revenu ; moyen = 6 min de revenu + boost personnel ×2 de 5 min ; difficile = 10 min de revenu + boost personnel ×2 de 10 min. **Les 3 terminés** : une « Goutte chanceuse » (une naissance de Qualité + 1, chances de mutation × 2).

| # | Niveau | Objectif | But |
|---|---|---|---|
| 1 | Facile | Presse des squishies | 30 pressions |
| 2 | Facile | PERFECT ! | 10 PERFECT |
| 3 | Facile | Attrape des créatures en fuite | 2 |
| 4 | Facile | Construis | 3 dalles achetées |
| 5 | Facile | Vide ton Pot | 5 encaissements |
| 6 | Facile | Salut ! | 3 emotes |
| 7 | Moyen | Fusionne | 2 fusions |
| 8 | Moyen | Fais naître | 5 naissances dans la Cuve |
| 9 | Moyen | Série PERFECT | 5 PERFECT de suite |
| 10 | Moyen | MEGA SQUISH | Participer (≥ 10 points) |
| 11 | Moyen | Course dorée | Attraper un Golden Wobbler ou être à 30 studs de sa capture |
| 12 | Moyen | Pet-sitting (Ami) | 10 pressions chez un ami |
| 13 | Moyen | Boop ! (Rush) | 1 boop réussi ou 1 capture pendant un Rush |
| 14 | Difficile | Combo ! | 1 combo ×3 |
| 15 | Difficile | Grande éclosion | 1 naissance Rare ou mieux |
| 16 | Difficile | Grand Splorch | 1 Grand Splorch |
| 17 | Difficile | Wild Wobblers | 2 Wild Wobblers attrapés |
| 18 | Difficile | Collectionneur | 3 nouveaux tampons de Squishydex |

### 7.5 Rendez-vous de la semaine

- **Jelly Moon** chaque samedi (4 séances) et le dimanche (§4.23). Déclarée comme *Experience Event* dans le Creator Hub.
- **Une nouvelle espèce par semaine** (§7.6), qui fait ses débuts pendant la Jelly Moon.
- **Classements de la semaine** (§6.9).
- **Squish Parties d'administrateur** annoncées à l'avance sur les réseaux : un sujet `MessagingService` « LiveOps » permet à une liste blanche d'administrateurs (UserIds dans la configuration serveur) de lancer sur tous les serveurs : 5 Golden Wobblers en 5 min + ×2 gratuit pour tous pendant 10 min. C'est notre version des sessions « admin abuse » (Étude §5.1), sans aucune vente.

### 7.6 Cadence des mises à jour

Rythme tenable (le créateur de Grow a Garden s'est épuisé en hebdomadaire, Étude §4.3) :
- **chaque semaine** : une nouvelle espèce, ajoutée comme ligne de données avec son horodatage `release`. Les lignes sont publiées **en avance** (dans une version du jeudi) et s'activent toutes seules le samedi à 16:00 UTC. Aucun serveur n'a besoin d'être redémarré le samedi ;
- **toutes les 2 semaines** : un ajout de configuration (tenues, décorations, objectifs) ;
- **chaque saison** : un costume (préréglages d'éclairage, décorations, tenue), selon le calendrier de costumes. Au lancement : hiver « Frost & Sprinkles » (neige de sucre glace, guirlandes de bonbons, Écharpe d'hiver).

---

## 8. Monétisation

### 8.1 Principes non négociables

1. **Aucun hasard payant** : ni œuf, ni coffre, ni roue, ni chance payante, ni avantage payant pour attraper ou booper.
2. **Jamais payer pour sauter un minuteur** : ni la Cuve, ni la Gelée lente (janvier).
3. **Pas de faux compte à rebours**, pas de « plus que 2 en stock », pas de prix caché derrière une monnaie intermédiaire. Chaque bouton montre le prix en Robux et exactement ce qu'on reçoit.
4. **Aucune proposition d'achat pendant les 10 premières minutes de jeu cumulé** : la Boutique Robux est cachée, aucun écran ne propose d'acheter.
5. **Aucune publicité vidéo récompensée** au lancement (et aucun code pour en afficher).
6. **Boutique cachée tant que les identifiants sont à 0** : un article dont l'identifiant vaut `0` dans `Shared/Config/Monetization` est désactivé et invisible ; si tous valent 0, l'onglet Boutique Robux n'apparaît pas (leçon de Comet Conga).
7. **Prix lus à l'exécution** (`MarketplaceService:GetProductInfoAsync`) pour la tarification gérée par Roblox (Managed Pricing) ; le prix en configuration n'est qu'un affichage de repli.
8. **`ProcessReceipt` idempotent** (service repris de Comet Conga) : `PurchaseId` mémorisé (100 derniers), `PurchaseGranted` renvoyé seulement après une sauvegarde réussie.
9. **PolicyService** : au chargement, `PolicyService:GetPolicyInfoForPlayerAsync` (sous `pcall`, 3 essais). Si `ArePaidRandomItemsRestricted` est vrai, le joueur ne voit **ni les Paquets de pièces, ni le pass ×2 Pièces, ni la Squish Party** : les pièces achètent des améliorations de la Cuve (un tirage gratuit), donc on évite toute pièce liée à des Robux (question ouverte n° 3, §20). Si l'appel échoue, on applique la règle la plus stricte. Les probabilités des naissances gratuites sont **toujours** affichées.
10. Le pass ×2 Pièces ne touche **que les pièces**, jamais la taille ; rien ne s'achète qui change un classement.

### 8.2 Passes (« Pour toujours », gardés après chaque Grand Splorch)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `AutoPot` | Pot automatique | 149 R$ | Le Pot s'encaisse tout seul toutes les 5 s, où qu'on soit. Confort seulement |
| `DoubleCoins` | ×2 Pièces | 249 R$ | ×2 sur toutes les pièces (revenu, pressions, combos, ventes, récompenses en pièces). Jamais la taille |
| `BigRanch` | Grand Ranch | 199 R$ | +6 places d'enclos (24 au plus) |
| `SaddlesTrails` | Pack Selles et Traînées | 99 R$ | 6 selles et 6 traînées. Purement décoratif : aucun avantage de vitesse ni de capture |

Chaque carte de pass porte l'étiquette « Pour toujours » / « Forever ».

### 8.3 Produits (achats ponctuels, résultat connu)

| Clé | Nom | Prix de départ | Effet |
|---|---|---|---|
| `SquishParty` | Squish Party | 99 R$ | ×2 pièces **et** croissance pour **tout le serveur** pendant 10 min. Ne se cumule pas : file d'attente de 30 min au plus par serveur (bouton masqué au-delà). Un achat toutes les 20 min par joueur (« Disponible dans 12:40 » : un vrai minuteur). Le nom de l'acheteur est affiché **seulement s'il le choisit** (case « Montrer mon nom », décochée par défaut) ; sinon « Un joueur généreux offre une Squish Party ! » |
| `CoinsSmall` | Petit paquet de pièces | 49 R$ | Pièces = **30 min** du revenu actuel (minimum 5 000) |
| `CoinsBig` | Gros paquet de pièces | 149 R$ | Pièces = **120 min** du revenu actuel (minimum 20 000) |
| `OutfitSweater` | Pull douillet | 49 R$ | Une tenue, à mettre sur le squishy de son choix |
| `OutfitCrown` | Couronne de gelée | 79 R$ | Idem |
| `OutfitWinter` | Écharpe d'hiver | 49 R$ | Idem (costume de saison du lancement) |

- Le montant des paquets de pièces est **calculé par le serveur au moment de l'attribution** et affiché avant l'achat (« ≈ 1,2 M pièces »), calculé par le client à partir du revenu répliqué.
- **Tenues** : on voit le squishy porter la tenue (aperçu 3D qui tourne) **avant** d'acheter. Une tenue achetée appartient au compte : on la met sur un squishy, on la change gratuitement ; une tenue va sur un squishy à la fois. Si ce squishy est vendu ou relâché, la tenue revient dans la garde-robe. Une fusion garde la tenue.

### 8.4 Ce qui est volontairement exclu

Œufs, coffres, roues ; chance payante ; avantage pour booper ou attraper ; immunité payante ; « passer le minuteur » ; plafond hors ligne payant (le pass « Offline Plus » du concept est supprimé : le Lit douillet s'achète en pièces) ; récompense d'invitation ; publicité vidéo récompensée ; nom de l'acheteur affiché par défaut.

**Plus tard (janvier)** : piste premium de la saison de 28 jours (≈ 399 R$), uniquement décorative, toutes les récompenses visibles avant l'achat (§17).

### 8.5 Attentes honnêtes

Taux DevEx standard 0,0038 $/R$ et 70 % net sur les ventes. Conversion visée 1,5 à 3 %. Revenus portés par ×2 Pièces, Grand Ranch et Squish Party, plus les Creator Rewards (sessions de 10 min et plus, nouveaux joueurs amenés sur Roblox). Le modèle juste rapporte moins par joueur que les concurrents prédateurs : c'est un choix assumé, car l'algorithme récompense la fidélité et les dépenses des joueurs baissent (bookings −12 % au 3e trimestre 2026, Étude §4.4).

---

## 9. Juice et animation

### 9.1 Module commun et règles

Tous les effets passent par le module client `UI/Juice` (repris de Comet Conga : `tween`, `pulse`, `press`, `popIn`, `popOut`, `shake`, `countTo`, `flash`, `cameraShake`, compatible Mouvement réduit), par `Controllers/VFXController` (repris et étendu : `floatText`, `stamp`, `flyCoins`, `ring`, `burst`, `pillar`, `fovPunch`, `haptic`) et par un nouveau module `Render/Squash` :

| Fonction | Rôle |
|---|---|
| `Squash.play(squishy, profil)` | Joue un profil d'écrasement et d'étirement sur le corps (une écriture de `Size` par image, les autres pièces suivent par `BulkMoveTo`) |
| `Squash.PROFILES` | `press`, `perfect`, `land`, `hatch`, `fuse`, `sneeze`, `hop`, `mount` (valeurs ci-dessous) |
| `VFXController.blobs(pos, couleur, n)` | Gouttes de gelée (réserve de 120 Balls réutilisées) |
| `VFXController.capsule(joueur, bébé)` | Capsule de bébé qui tombe du ciel près d'un joueur, éclate, puis le bébé saute vers son ranch |

**Règles**
- Une seule animation par propriété à la fois (la nouvelle annule l'ancienne). Aucune création d'instances en rafale : réserves de pièces, de BillboardGui et d'émetteurs.
- Les écrasements gardent à peu près le volume (X × Y × Z ≈ 1) : un squishy écrasé s'élargit.
- Secousse de caméra par `Humanoid.CameraOffset` (bruit de Perlin, amplitude ≤ 0,4, durée ≤ 0,3 s). Les pièces 3D disparaissent en **rétrécissant** (Transparency reste 0 ou 1, sauf la gelée Jelly, exception unique).
- Les textes « +N » utilisent `Format.abbreviate` (§4.2) dans la langue du joueur.
- Un son vide ou qui ne se charge pas est muet : le jeu reste jouable en silence (§9.6).

**Mouvement réduit** (réglage, et suit `GuiService.ReducedMotionEnabled`) : pas de secousse, pas de coup de focale, pas de flash, pas de ralenti (les séquences se jouent à vitesse normale), pas de travelling de caméra du Grand Splorch (une flèche montre la place), amplitudes d'écrasement × 0,5, Glitch en damier fixe, Arc-en-ciel en dégradé fixe, déplacements d'interface remplacés par des fondus. Aucun clignotement au-dessus de 3 Hz, réglage ou pas.

**Graphismes légers** (réglage) : particules × 0,3 ; pas de `Trail` sauf derrière les squishies en fuite ; `Highlight` seulement sur la cible et les squishies en fuite ; distances de détail × 0,6 ; 40 squishies animés au plus ; lumières coupées au-delà de 60 studs ; pas de `BlurEffect` ; ombres coupées sur les décors.

### 9.2 Interface

| Interaction | Tweens | Effets | Son |
|---|---|---|---|
| Appui sur un bouton | `UIScale` 1 → 0,92 en 0,06 s (`Quad Out`) ; au relâchement 0,92 → 1,05 → 1 en 0,18 s (`Back Out`) ; +10 % de luminosité pendant l'appui. Doigt qui glisse hors du bouton : retour à 1 | — | `Click` |
| Sélection manette | Cadre blanc de 6 px bordé de sombre (2 px), respiration 0 ↔ 0,35 en 1,2 s ; pulsation `Juice.press` | — | `Select` (au plus 1 toutes les 0,06 s) |
| Refus (pas assez de pièces, enclos pleins) | Secousse horizontale ±6 px × 3 en 0,25 s, contour rouge 0,25 s | Message « Il manque 1,2K pièces » | `Error` |
| Ouverture de panneau | `UIScale` 0,85 → 1 en 0,22 s (`Back Out`) + fondu 0,15 s ; `BlurEffect` 0 → 8 en 0,2 s (sauf Graphismes légers) | — | `Whoosh` |
| Fermeture / retour | `UIScale` 1 → 0,9 + fondu en 0,12 s (`Quad In`) | — | `Back` |
| Onglet / panneau suivant | Soulignement qui glisse en 0,15 s | — | `Tab` |
| Bout de liste | Rebond de la liste de 8 px en 0,15 s | Vibration `listEnd` | `Bump` |
| Compteur de pièces | Défilement `countTo` 0,5 s (`Quint Out`) + pop `UIScale` 1,15 → 1 en 0,2 s ; le revenu passif défile sans pop | — | `Coin` (8 par seconde au plus) |
| Bouton qui attire l'attention | Pulsation `UIScale` 1 → 1,08, sinus 0,8 s | Glyphe ou main dessinée pendant l'accueil | — |

### 9.3 Les squishies (client, aucun trafic réseau)

| État | Animation |
|---|---|
| Au repos | Rebond de période 1,2 s (hauteur 0,18 D), écrasement au contact (1 + a ; 1 − a ; 1 + a) pendant 0,1 s puis tremblement amorti à la fréquence de l'espèce ; clignement toutes les 3-6 s ; flâne dans l'enclos (pas de 2 studs toutes les 4-8 s) ; regarde le joueur le plus proche |
| Prêt à presser | Corps gonflé de 4 %, petit reflet qui passe toutes les 2 s ; anneau PERFECT qui se resserre vers lui à chaque cycle quand il est la cible |
| En recharge | Anneau qui se remplit au sol en 8 s ; corps normal |
| Porté | Sur la tête du joueur, bat des pieds (oscillation ±10° à 3 Hz) |
| Dans le Bassin | Flotte (Y ± 0,3 à 0,5 Hz), petites bulles 1 par seconde |
| Curieux à la clôture (Rush) | Pattes posées sur la clôture, se dandine (±8° à 1,5 Hz), nez qui remue |
| Meilleur Ami en ville | Suit le joueur à 4 studs derrière, par petits bonds |
| Monture | Rebondit à chaque pas (écrasement 8 % au rythme de la course) |
| Dans la Boîte à dodo | Icône endormie dans le panneau (pas de modèle dans le monde) |

### 9.4 Moments de jeu

« D » = diamètre du corps. Durées en secondes. « MR » = Mouvement réduit.

| Moment | Tweens et mouvement | Particules / 3D | Caméra / écran | Texte | Son | Vibration |
|---|---|---|---|---|---|---|
| **Presser** | Profil `press` : (1 ; 1 ; 1) → (1,35 ; 0,60 ; 1,35) en 0,06 (`Quad Out`) → (0,85 ; 1,25 ; 0,85) en 0,12 (`Quad Out`) → (1 ; 1 ; 1) en 0,35 (`Elastic Out`) | 8 gouttes couleur du corps ; 6 à 10 pièces (client) jaillissent en arc 0,5 puis volent vers le compteur en 0,4 (`Quad In`) | Pop du compteur | « +1,2K » : échelle 0 → 1,2 → 1 en 0,2 (`Back Out`), monte de 3 studs en 0,8 | `Press`, hauteur au hasard entre 0,92 et 1,08 (un son un peu différent à chaque fois) | `pressTick` (2 par seconde au plus) |
| **PERFECT** | Profil `perfect` : (1,45 ; 0,50 ; 1,45) puis comme `press` | Anneau `Neon` blanc 0 → 1,6 D en 0,25 ; 14 étincelles | — | Tampon « PERFECT ! » doré : 0 → 1,3 → 1 en 0,25 (`Back Out`) ; « ×3 » sous le tampon pour la série | `Perfect`, hauteur 1,0595^série (un demi-ton de plus par marche) | `perfect` |
| Série de 5 | — | 20 étincelles dorées en gerbe | Légère lueur dorée aux bords de l'écran 0,4 (pas en MR) | « PERFECT ×5 ! » | `StreakMax` | `perfect` |
| **Dalle achetée** | L'objet sort du sol : échelle Y 0 → 1,15 → 1 en 0,45 (`Back Out`), puis (1,08 ; 0,92) → 1 en 0,3 | 12 vermicelles colorés | — | « Tapis à Goûter Niv. 2 » flottant | `TileBuild` | — |
| **Pot encaissé** | Couvercle qui saute (0,15) | Geyser de 12 à 20 pièces, qui volent vers le compteur (décalage 0,03) | Compteur `countTo` 0,5 + pop 1,15 | « +4,5K » doré | `PotCollect` puis `Coin` | — |
| **Cuve qui se remplit** | Niveau de gelée qui monte en continu ; à 90 %, la Cuve tremble (échelle 1,03, sinus 3 Hz) | 2 bulles par seconde | — | — | `VatBubble` (petit blip à 90 %) | — |
| **Naissance Commun / Peu commun** | La goutte tombe (0,3), s'écrase (1,4 ; 0,6 ; 1,4), la coque se fend en 6 gouttes, le squishy sort : 0 → 1,1 → 1 en 0,35 (`Back Out`) | 10 particules couleur de rareté | — | « + Mochi Mew » (taille selon la rareté : ×0,8 Commun → ×1,6 Secret) ; « NOUVEAU ! » doré si nouvelle entrée | `Hatch` | — |
| Naissance Rare / Épique | Idem | + colonne `Neon` 0,8 (Ø 1,5 → 0, hauteur 25) ; 20 particules | Épique : focale 70 → 73 → 70 en 0,3 (pas en MR) | — | `HatchRare` | Épique : `catch` |
| Naissance Légendaire | Le pop se joue au **ralenti** (0,4× pendant 0,6 ; pas en MR) | Faisceau doré de 4 s visible par tout le serveur ; 40 confettis | Flash blanc 0,12 (opacité 30 %, pas en MR) ; secousse 0,25, amplitude 0,25 | Bannière serveur ; étiquette « 1 sur X » | `HatchLegend` | `hatchLegend` |
| Naissance Mythique / Secret | Idem, ralenti 0,8 | + anneau arc-en-ciel 0 → 30 studs en 1,0 ; 60 confettis multicolores | Idem + capture vidéo automatique (§9.5) | Grande étiquette « SECRET Royal Plop · 1 sur 2 500 » pendant 3 s | `HatchLegend` (hauteur 0,9 pour Secret) | `hatchLegend` |
| **Mutation révélée** | Après la sortie, un reflet blanc balaie le corps (0,4) et le matériau change | 10 particules couleur de mutation | — | « Doré ! », « Galaxie ! »… | `MutationReveal` | — |
| Mutation **Flop** | Au lieu du reflet : le squishy se dégonfle, Y 1 → 0,6 en 0,5 (`Quad Out`), yeux mi-clos, petit nuage gris qui tourne 2 s au-dessus | 6 gouttes ternes | — | « FLOP ! » qui tremble | `Blorp` | `hatchLegend` |
| **Prendre** | Saute sur la tête du joueur : parabole 0,25 (sommet 3 studs), atterrissage (1,2 ; 0,8 ; 1,2) → 1 en 0,15 | — | — | — | `Pickup` | — |
| **Lancer** | Arc 0,5 (sommet 6 studs) vers le Bassin | Éclaboussure : 16 gouttes + anneau sur l'eau | — | — | `Throw` puis `Splash` | — |
| **Fusion** | Les jumeaux tournent l'un autour de l'autre 0,6 (2 tours, en accélérant), éclair blanc (sphère 0 → 1,3 D → 0 en 0,2), le résultat sort : 0,6 → 1,25 → 1 en 0,4 (`Elastic Out`) ; l'étoile vole du centre vers l'arc d'étoiles (0,3) | 24 particules aux couleurs de l'espèce | Focale 70 → 74 → 70 en 0,3 (pas en MR) | « ★2 ! » | `Fuse` | `fusion` |
| **Combo** (étape k) | Comme la fusion, 0,6 entre deux étapes | Particules + k × 4 | Lueur chaude aux bords, plus forte à chaque étape ; k ≥ 4 : secousse 0,2, amplitude 0,2 (pas en MR) | « COMBO x2 ! », « x3 ! »… taille 1 + 0,15 k ; k ≥ 4 : bannière | `ComboStep`, hauteur 1 + 0,08 k | `fusion`, force + 0,05 par étape |
| COMBO ×5 | — | 50 confettis dorés | Grand tampon « COMBO x5 ! » (0,5, `Elastic Out`) ; capture vidéo automatique | Bannière serveur | `ComboBig` | `comboBig` |
| **Créature en fuite apparaît** | La Fontaine crache une colonne de gelée (0,4), la créature sort en arc (0,6) et atterrit écrasée | Anneau à la couleur du joueur sous elle | Flèche au bord de l'écran si elle est hors champ | — | `RunawayAppear` | — |
| **Bond d'une créature** (fuite, Rush, Wild, Golden) | Profil `hop` : étirement (0,85 ; 1,25 ; 0,85) au départ, écrasement (1,3 ; 0,7 ; 1,3) à l'atterrissage pendant 0,08 | 3 bouffées de poussière par atterrissage (pas en Graphismes légers) | — | — | `Giggle` toutes les 2 à 3 s (son 3D, portée 60 studs) | — |
| **Booper** (maintien) | Anneau de progression autour du nez (2,5 ou 5 s) ; le nez remue ; le squishy inspire : Y 1 → 1,15 pendant le maintien | — | — | « Boop… » | `BoopHold` (petit souffle qui monte) | — |
| **ATCHOUM** | Profil `sneeze` : (1,5 ; 0,6 ; 1,5) en 0,08, puis saut par-dessus la clôture (arc 0,7, sommet 8 studs) | Nuage pastel brillant (20 particules blanches et roses, **jamais vertes**) | — | « ACHOO! » / « ATCHOUM ! » (`Elastic Out`) | `Sneeze` | Boopeur : `boopDone` ; propriétaire : `booped` |
| **Poursuite** | Bonds en continu (profil `hop`) | Anneau à la couleur du propriétaire + contour `Highlight` ; traînée de 6 gouttes ; anneau de temps au-dessus (25 s qui se vident) | Flèche au bord de l'écran vers la fuite la plus proche à 120 studs (joueurs Rush) | — | `MusicRush` (pendant le Rush) | — |
| **Bondir** | — | `Trail` sur la `HumanoidRootPart` pendant 0,35 ; 6 bouffées de poussière | Focale 70 → 76 en 0,1, retour en 0,4 (`Quad InOut`) (pas en MR) | Le bouton Bondir montre un balayage de recharge (4 s), puis pop 1,15 quand il est prêt | `Leap` | — |
| **Attraper** (fuite, Wild, Golden) | La créature se roule en boule, saute dans les bras du joueur (parabole 0,3), puis disparaît en rétrécissant (0,2) et réapparaît dans l'enclos | 14 particules | — | « +1 Mochi Mew » ; « NOUVEAU ! » si nouvelle entrée | `Catch` (Golden : `CatchGolden`) | `catch` |
| Attraper le squishy d'un autre (Rush) | Idem ; l'original repart vers son ranch avec un cœur | — | — | Attrapeur : « Bébé Purrpudding ! » ; propriétaire : « Noah a attrapé ton Wibble ! +1 Fame » (ou « Ranch 7 » si nom caché) | `BabyGet` ; propriétaire : `Return` | `catch` |
| **Capture Héros** | Le squishy grossit de 10 % sous les yeux (0,3) | 30 particules | — | Tampon « HÉROS ! » / « HERO! » doré (0,4, `Back Out`) | `HeroCatch` | `catch` (force 0,5) |
| Personne n'attrape | Le squishy rentre en bondissant ; au portail, il grossit de 5 % avec une étincelle | 8 étincelles | — | Propriétaire : « Wibble est rentré plus gros ! +5 % » | `Return` | — |
| **Monter** | La monture apparaît (0 → 1 en 0,25, `Back Out`), le joueur saute dessus (arc 0,3) ; profil `mount` : (1,25 ; 0,75 ; 1,25) en 0,12 | — | — | — | `MountUp` | — |
| Atterrissage en monture | (1,3 ; 0,7 ; 1,3) en 0,1 | 8 bouffées ; Grande selle : anneau d'éclaboussure ; Selle géante : onde 0 → 12 studs en 0,4 | — | — | `RideLand` | — |
| **Grand Splorch** (6 s) | 0,0 : le squishy brille (pulsation blanche 0,3) et s'élève de 8 studs (0,6, `Quad Out`). 0,6 : il vole vers la place sur une courbe (1,4, `Sine InOut`). 2,0 : à 40 studs au-dessus du MEGA pad, il gonfle de ×1 à ×2,5 en 1,2 (`Quad In`), en tremblant (±6 % de 4 à 8 Hz). 3,2 : **éclatement au ralenti** (0,8 ; pas en MR). 5,2 : il se reforme tout petit dans son enclos (0 → 1 en 0,4, `Back Out`) | 3,2 : 60 gouttes de gelée qui retombent, onde 0 → 80 studs en 0,8, `Bloom` +0,6 pendant 0,4. 4,0 : pluie de cadeaux : pour **chaque** joueur, 6 à 10 pièces et une capsule de bébé tombent près de lui (1,2) | Héros : caméra qui suit le vol (pas en MR) ; secousse 0,3, amplitude 0,35 à l'éclatement ; flash blanc 0,1 (pas en MR). Autres : secousse atténuée par la distance. Visible de toute la carte | 5,2 : titre « GRAND SPLORCH III » qui s'écrit en 0,6 (`MaxVisibleGraphemes`) ; bannière serveur ; bouton APPLAUDIR chez les autres (8 s) | 2,0 `SplorchCharge` ; 3,2 `SplorchPop` ; 4,0 `GiftRain` ; 5,2 `Reward` | Héros : `splorch` ; autres : `catch` à la capsule |
| **MEGA SQUISH : alerte** | Ombre ronde qui grandit de 0 à 24 studs en 15 s et pulse | — | — | Bannière « MEGA SQUISH ! » + compte à rebours | `MegaWarn` | — |
| MEGA : atterrissage | Chute de 120 studs en 0,6 (`Quad In`) ; écrasement (1,4 ; 0,55 ; 1,4) en 0,15 puis `Elastic Out` 0,8 | 3 anneaux 0 → 60 studs décalés de 0,15 ; 40 bouffées de poussière | Secousse 0,3, amplitude `0,4 × (1 − d / 120)` si d < 120 studs | — | `MegaLand` | `megaLand` atténuée |
| MEGA : pression | Creux local (1,04 ; 0,96 ; 1,04) en 0,08 à chaque pression locale ; le serveur envoie un battement toutes les 0,25 s, écrasement proportionnel au nombre de pressions | « +1 » / « +3 » flottants | Barre de serveur qui se remplit (`Back Out`, 0,3) ; à 90 %, le géant tremble (±4 % à 6 Hz) et écarquille les yeux | — | `MegaPress`, hauteur de 0,9 à 1,3 selon la progression | `pressTick` |
| MEGA : ÉCLATE | Gonfle 1 → 1,3 en 0,3 (`Quad In`) puis éclate | 80 gouttes ; pluie de capsules de bébés (une par bébé, près de chaque participant) ; 60 confettis | Flash blanc 0,12 (pas en MR) ; coup de focale | « MEGA SPLORCH ! » | `MegaPop` puis `GiftRain` | `megaPop` |
| MEGA : échec | Le géant soupire (Y 1 → 0,9 → 1 en 1) et s'envole doucement (2) | — | — | « Presque ! » | `MegaSigh` | — |
| **Jauge pleine** | La jarre déborde ; Plop danse 8 s (sauts, 2 tours sur lui-même, dandinements) ; un grand ballon Plop de 20 studs monte au-dessus de la place pendant la danse | 40 confettis | Ciel légèrement doré pendant 5 min ; pastille « WOBBLE PARTY ×2 5:00 » | Bannière | `GaugeFull` | — |
| **Golden Wobbler** | Geyser doré de la fontaine, la créature sort en arc | 30 étincelles ; traînée dorée de 8 particules par seconde | — | Bannière à la capture | `GoldenAppear` ; à la capture `CatchGolden` | `catch` |
| **Sirène du BOOP RUSH** | Les squishies curieux trottent vers la clôture (un bond de 0,3 par pas) | — | Ciel rose (`Tint` (255, 200, 225)) en 2 s ; pastille rose « BOOP RUSH 1:30 » | « BOOP RUSH ! » | `RushSiren` puis `MusicRush` pendant 90 s | `rushSiren` |
| **Jelly Moon** début / fin | Transition du ciel 4 s (nuit, grosse lune, teinte violet-sarcelle) ; les Lunaires ont 2 gouttes qui perlent (boucle de 3 s) | Lucioles lunaires (12 sur l'écran) | — | Bannière « JELLY MOON ! » | `MoonStart` puis `MusicMoon` | — |
| **Nourrir Plop** | Anneau de maintien 5 s autour du bol ; Plop ouvre et ferme la bouche 4 fois, gonfle à 1,05 et revient | 6 cœurs | — | Tampon « Jour 42 ! » | `FeedPlop` ; palier : `Reward` | — |
| **Nouvelle entrée de Squishydex** | Carte qui glisse de la droite en 0,3 (`Back Out`), reflet `UIGradient` 0,6 | — | — | « NOUVEAU ! Gillygum · Néon » | `DexNew` | — |
| **Objectif terminé** | Barre remplie en 0,3, carte qui pulse à 1,1, coche qui se dessine | La récompense vole vers son compteur | — | — | `ObjectiveDone` | — |
| **Fanfare de record du serveur** | — | 3 feux d'artifice au-dessus de la place | — | Bannière dorée « Premier à 1 MILLIARD ! » | `Fanfare` | — |
| **Portail refusé** (intrus) | Le portail de gelée se bombe (Z 1 → 1,3 → 1 en 0,3), le joueur est repoussé sur un petit arc | — | — | « C'est le ranch de Mira ! » | `Boing` | — |
| **Achat Robux** | Pluie de 30 pièces (1) | Squish Party : bannière dans le ciel + confettis pour tout le serveur | — | « Merci ! » | `Reward` | — |
| **Emote** | Icône 0 → 1,2 → 1 en 0,25 (`Back Out`), tenue 2,5, fondu 0,2 | — | — | — | `Emote` | — |

### 9.5 Captures et clips

- Réglage « Clips » (activé par défaut), et seulement si `PolicyService` renvoie `IsContentSharingAllowed = true` pour ce joueur.
- Capture vidéo automatique (`CaptureService:StartVideoCaptureAsync`, côté client) pour : naissance Légendaire ou mieux, COMBO ×5, son propre Grand Splorch (case « Filmer mon Grand Splorch » sur l'écran d'aperçu, cochée par défaut). Arrêt après 8 s (`StopVideoCapture` ; Roblox arrête de toute façon à 30 s).
- À la fin, une petite carte : « Garder ton clip ? » avec Enregistrer (`PromptSaveCapturesToGallery`), Partager (`PromptShareCapture`) et Fermer. Le jeu **ne partage jamais tout seul**.

### 9.6 Sons

**Provenance.** Chaque son vient **uniquement** des dépôts officiels de Roblox : **Roblox/resources** (Feature Packages, `SharedConstants.lua`, jeux d'exemple *Plant* et *Gold Rush*) et **Roblox/creator-docs** (tutoriels audio, modules). La source exacte (dépôt, fichier, ligne ou constante) est écrite **sur la ligne** de chaque son dans `Shared/Config/Sounds.luau`, au format `rbxassetid://<nombre>` (leçon de Comet Conga). Rien n'est téléversé.

**Sécurité.** Une clé vide (`id = ""`) est muette ; un son qui ne se charge pas est retiré au préchargement (un avertissement par clé, aucune erreur). Le jeu est entièrement jouable sans aucun son. Garde-fous de lecture (`AudioController`, repris) : 3 copies au plus par image et 4 en même temps pour une clé ; durée maximale 4 s (fondu 0,3 s) ; un seul jingle à la fois ; réglages Musique et Effets respectés. Deux clés qui partagent un enregistrement diffèrent d'au moins 15 % de hauteur.

**Liste des moments sonores (clés).** Les candidats marqués « Comet » sont des sons officiels déjà retrouvés et vérifiés pour Comet Conga (`/home/user/jules/roblox-game/src/shared/Config/Sounds.luau`) ; les autres sont à chercher dans les mêmes dépôts. **Chaque son doit être écouté dans Studio avant la publication** (§18).

| Clé | Moment | Candidat |
|---|---|---|
| `Click`, `Pop` | Bouton pressé ; petite apparition | Comet (`BUTTON_ACTIVATED`, Pop plus aigu) |
| `Whoosh`, `Back`, `Tab`, `Select`, `Bump` | Panneau ouvert ; retour ○ ; onglet ; sélection manette ; bout de liste | Comet (`PROMPT_OPENED`, `PROMPT_CLOSED`, `BUTTON_HOVER`, hauteurs différentes) |
| `Error` | Refus | Comet (`PROMPT_CLOSED` plus grave) |
| `Coin` | Pièces qui arrivent au compteur | Comet (*Plant* « Coins ») |
| `Reward`, `LevelUp` | Récompense, achat Robux ; palier | Comet (`PURCHASE_EFFECT` ; « retro jingle ») |
| `Music`, `MusicMoon`, `MusicRush` | Musique de jour ; Jelly Moon (plus douce) ; BOOP RUSH (gloussements, rapide) | Comet `Music` pour le jour ; les deux autres à chercher |
| `Press` | SPLORCH (hauteur au hasard 0,92-1,08) | À chercher (son mou, « squish ») ; repli : `Pop` grave |
| `Perfect`, `StreakMax` | PERFECT (hauteur qui monte) ; série de 5 | À chercher ; repli : `Click` aigu |
| `PotCollect`, `TileBuild`, `VatBubble` | Pot ; dalle construite ; Cuve presque pleine | À chercher |
| `Hatch`, `HatchRare`, `HatchLegend`, `MutationReveal` | Naissances ; révélation de mutation | `Catch` / `CatchRare` / `BeaconWin` de Comet comme replis |
| `Blorp` | Le cri du Flop | À chercher (son grave et mou) |
| `Pickup`, `Throw`, `Splash` | Prendre ; lancer ; plongeon dans le Bassin | À chercher |
| `Fuse`, `ComboStep`, `ComboBig` | Fusion ; étape de combo (hauteur qui monte) ; combo ×5 | À chercher ; repli : `LevelUp` |
| `RunawayAppear`, `Giggle`, `Catch`, `CatchGolden` | Créature qui sort ; gloussement ; capture ; Golden attrapé | Comet `Catch`, `CatchRare` |
| `Leap`, `MountUp`, `RideLand` | Bondir ; monter ; atterrir en monture | Comet `Dash` comme repli de `Leap` |
| `RushSiren`, `BoopHold`, `Sneeze`, `Return`, `BabyGet`, `HeroCatch` | Sirène ; maintien du boop ; ATCHOUM ; retour au ranch ; bébé gagné ; capture Héros | À chercher ; `Sneeze` doit rester drôle et doux |
| `MegaWarn`, `MegaLand`, `MegaPress`, `MegaPop`, `MegaSigh` | MEGA SQUISH | Comet `CometWarn`, `CometImpact` comme replis |
| `GaugeFull`, `GoldenAppear`, `MoonStart`, `Fanfare` | Jauge pleine ; Golden ; Jelly Moon ; record | Comet `BeaconWin` comme repli de `Fanfare` |
| `SplorchCharge`, `SplorchPop`, `GiftRain` | Grand Splorch | Comet `Supernova` comme repli de `SplorchPop` |
| `FeedPlop`, `DexNew`, `ObjectiveDone`, `Emote`, `Boing` | Nourrir Plop ; Squishydex ; objectif ; emote ; portail refusé | À chercher |

---

## 10. Interface, commandes et console

### 10.1 Principes

- Tout est construit en code (`Frame`, `TextLabel`, `TextButton`, `UIGradient`, `UIStroke`, `UICorner`, `UIScale`, `UIListLayout`, `UISizeConstraint`). Aucune image téléversée : icônes en formes de Frames et grands glyphes ; glyphes de manette fournis par Roblox (`GetImageForKeyCode`).
- Un `ScreenGui` par écran logique, `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling`.
- **Mise à l'échelle** (reprise de la couche console de Comet Conga, `Client/Util/Platform` et `UI/Root`) : résolution de référence 1280 × 720. Écran ordinaire : `UIScale = clamp(min(L/1280, H/720), 0,6, 1,25)`. **Écran Large ou console** : `max(0,6, min(L/1280, H/720))` sans plafond (**1,5 en 1080p**, 3 en 4K).
- **Tailles minimales de référence** : texte lisible **18 px** (27 px réels en 1080p sur console) ; glyphe de bouton 36 px ; bouton principal 96 px, secondaire 80 px ; cible tactile ≥ 56 px réels.
- **Zones réservées** au téléphone : joystick (quart inférieur gauche) et saut (coin inférieur droit) jamais recouverts.
- Style : `UICorner` 14-18 px ; `UIStroke` 3 px bleu nuit (30, 25, 60) ; dégradés pastel ; police `FredokaOne` pour le texte, `LuckiestGuy` pour les tampons.
- **Affichage progressif** : pendant l'accueil, seuls les éléments déjà présentés sont visibles (§3).

### 10.2 HUD

| Élément | Position (référence) | Taille | Contenu |
|---|---|---|---|
| Pastille Pièces | Haut gauche (16, 16) | 260 × 64 | Pièce dessinée, montant (34 px), revenu « +1,2K/s » (18 px) |
| Pastille Fame et amis | Sous les pièces (16, 88) | 200 × 40 | Étoile + Fame ; cœur + nombre d'amis présents |
| Indicateurs d'état | Sous la pastille Fame | 48 × 48 chacun | Bouclier débutant (minutes restantes), boost ×2 (minuteur), mode Rush/Cozy |
| Pastille d'événement | Haut centre | 340 × 48 | Prochain événement « BOOP RUSH 3:12 » ; événement en cours en couleur (Rush rose, MEGA jaune, Lune violet, Wobble Party orange) |
| Barre du MEGA | Sous la pastille | 420 × 28 | Progression du serveur, objectif, temps restant |
| Jauge du serveur | Sous la pastille (hors MEGA) | 220 × 14 | Remplissage, icône Plop |
| Rail de menus | Gauche, de y = 160 à y = 592 | 5 boutons de 80 × 80, écart 8 | Ranch, Squishydex, Objectifs, Classements, Boutique (Boutique cachée avant 10 min de jeu et si tous les identifiants valent 0) ; pastille « ! » si une action est possible |
| Suivi d'objectif | Droite (−16, 16) | 260 × 72 | Objectif long : anneau « Grand Splorch 12K / 15K » ; repliable |
| Bouton GRAND SPLORCH | Bas centre (y = −120), quand l'objectif est atteint | 220 × 80 | Brille et pulse ; ouvre l'aperçu |
| Carte de la cible | Bas centre (y = −24) | 320 × 64 | Squishy visé : nom, rareté (couleur + forme), taille, revenu, étoiles, mutation |
| Bouton Action (téléphone) | Au-dessus du bouton de saut (position lue dans `TouchGui.TouchControlFrame.JumpButton`, décalage −16 px) | 120 × 120 | Le mot change : Presser, Prendre, Lancer, Attraper, Booper, Nourrir |
| Boutons Bondir et Monter (téléphone) | À gauche du bouton Action | 88 × 88 chacun | Balayage de recharge sur Bondir |
| Bouton Emote (téléphone) | Au-dessus de Bondir | 72 × 72 | Ouvre 4 secteurs de 96 px |
| Bouton APPLAUDIR | Bas centre, au-dessus de la carte de cible | 200 × 88 | 8 s, anneau de temps |
| Bannières | Haut centre, sous la pastille | 640 × 72 | §6.6 |
| Messages (toasts) | Haut centre | 480 × 56 | 3 au plus (module `UI/Toast` repris) |

Sur PC et console, il n'y a pas de bouton Action à l'écran : l'invite contextuelle apparaît dans le monde, au-dessus de la cible, avec le glyphe (□ ou E) et un mot court (« Presser »).

### 10.3 Écrans

| Écran | Accès | Contenu | Remarques |
|---|---|---|---|
| Chargement | Automatique | Plop qui rebondit, points animés | `ReplicatedFirst`, code seul |
| Échec de chargement | Automatique | « Ton ranch se réveille… » + Réessayer | Réessayer attend la fin des essais du DataService (attribut `ProfileLoading`), sélectionné d'office à la manette (leçon de Comet Conga) |
| Écran de retour | Au chargement | §7.2 | « Super ! » sélectionné d'office |
| Carte du choix Rush / Cozy | Premier Rush après 3:00 de jeu ; Réglages | Deux gros boutons illustrés | Sans réponse en 20 s : Cozy |
| **Ranch** | Rail | Onglets : *Enclos* (grille des squishies, tri, verrou, Meilleur Ami, monture), *Dodo* (Boîte à dodo, échanger), *Lettres* (Boîte aux lettres), *Fusionner* (choisir A puis B), *Vendre / Relâcher* (sélection multiple, maintien 0,6 s pour Rare+), *Dalles* (liste de toutes les dalles avec prix : on peut aussi acheter d'ici, utile à la manette et pour l'accessibilité) | Grille virtualisée ; la sélection suit l'index au défilement (leçon de Comet) |
| **Squishydex** | Rail | Onglets : *Espèces* (26 pages), *Mutations* (grille 26 × 9), *Familles* (bonus), *Étoiles*, *Guide* (toutes les probabilités et règles) | Silhouettes grises pour ce qui manque |
| **Objectifs** | Rail | *Aujourd'hui* (3 objectifs, relance), *Plop* (jours au total, paliers), *Accueil* (tant qu'il n'est pas fini) | |
| **Classements** | Rail | 5 onglets (§6.9) : top 10 de la semaine, tableau du serveur, ma meilleure valeur | |
| **Boutique** | Rail (après 10 min) | *Passes*, *Fête et pièces*, *Tenues* (aperçu 3D) ; prix lus à l'exécution | Cachée si aucun identifiant ; masquage PolicyService (§8.1) |
| **Aperçu du Grand Splorch** | Bouton GRAND SPLORCH | Gains en haut, puis « Tu gardes » / « Repart de zéro », prochain objectif, case « Filmer », bouton à maintenir 1,5 s | Hors du ranch : « Rentre dans ton ranch » |
| **Réglages** | Icône | Mode Rush/Cozy, Cacher mon nom, Recevoir les cadeaux, Clips, Mouvement réduit, Graphismes légers, Musique, Effets sonores, Vibrations, Langue (Auto / English / Français) ; propriétaire d'un serveur privé : « BOOP RUSH autorisé » | Interrupteurs de 80 × 48 ; message « Tes squishies grandissent même quand tu dors » en bas |

Panneaux : `Size = UDim2.fromScale(0,72 ; 0,86)` avec `UISizeConstraint` (min 480 × 320, max 900 × 600) ; onglets de 56 px ; bouton Fermer 64 × 64. Un seul panneau ouvert à la fois. Ouvrir un panneau ne met pas le jeu en pause.

### 10.4 Commandes

Noms PlayStation (DualSense) avec la `KeyCode` générique de Roblox entre parenthèses. Sur Xbox, les mêmes `KeyCode` portent les noms Xbox ; le jeu affiche **toujours** l'icône de l'appareil (`UserInputService:GetImageForKeyCode`), jamais une lettre écrite en dur.

| Action | Téléphone | Clavier / souris | Manette (DualSense — `KeyCode`) |
|---|---|---|---|
| Se déplacer | Joystick | WASD (ZQSD reconnu tout seul en AZERTY) / flèches | Stick gauche (`Thumbstick1`) |
| Caméra | Glisser | Clic droit + souris | Stick droit (`Thumbstick2`) ; la caméra cadre seule la cible en cours si le stick n'a pas bougé depuis 2 s (30°/s au plus) |
| Sauter (plus haut sur sa monture) | Bouton saut Roblox | Espace | ✕ (`ButtonA`) |
| **Action contextuelle** : presser, prendre, lancer, attraper, booper (maintien 2,5 s), nourrir Plop (maintien 5 s) | Toucher le squishy, ou le bouton Action | E, ou clic sur la cible | **□** (`ButtonX`, touche manette par défaut des `ProximityPrompt`) |
| **Bondir** (visée automatique en poursuite) | Bouton Bondir | Maj gauche | **R2** (`ButtonR2`) |
| **Monter / descendre** | Bouton Monter | R | **L2** (`ButtonL2`) |
| Changer de cible (au calme, dans son ranch) | Toucher un squishy | Clic sur un squishy | L1 / R1 (`ButtonL1` / `ButtonR1`) |
| Poser le squishy porté | Bouton Poser (remplace Bondir pendant le portage) | Q | ○ (`ButtonB`) |
| Rail de menus | Rail | Tab (sélectionne le rail) | △ (`ButtonY`) |
| Emotes : salut, merci, à l'aide, bravo | Bouton Emote | 1, 2, 3, 4 | Croix ↑, →, ↓, ← (`DPadUp/Right/Down/Left`) |
| Applaudir (pendant 8 s) | Bouton APPLAUDIR | F | Croix → (remplace « merci » pendant ces 8 s) |
| Menu Roblox | Bouton Roblox | Échap (**jamais lié par le jeu**, leçon de Comet) | Options (`ButtonStart`, réservé) |
| Pavé tactile / Create | — | — | `ButtonSelect`, réservé à Roblox |

- **Pas de verrouillage de la souris** (`StarterPlayer.EnableMouseLockOption = false`) : Maj sert à Bondir.
- **Cibles** : en poursuite, visée automatique sur la créature attrapable la plus proche (18 studs, cône ±30°) ; un marqueur blanc la montre ; □ l'attrape à 5 studs, R2 bondit vers elle. L1 / R1 ne servent qu'au calme, dans son ranch, pour choisir le squishy à presser ou prendre (dans une mêlée de 16 joueurs sur une télé, changer de cible serait illisible).
- Les actions passent par `ContextActionService` ; les invites contextuelles sont des `ProximityPrompt` créés par le client (glyphe, mot, maintien) dont le déclenchement envoie une intention au serveur (§12.7).

**Dans les menus (manette)** : ✕ valide ; ○ recule d'un niveau ; △ ferme tout et revient au jeu ; L1 / R1 changent d'onglet (en boucle) ; L2 / R2 changent de panneau (en boucle : Ranch → Squishydex → Objectifs → Classements → Boutique → Réglages) — **seulement quand un panneau est ouvert**, sinon L2 = Monter et R2 = Bondir ; stick droit fait défiler ; □ est absorbé (aucune action derrière la fenêtre).

### 10.5 Vibrations

`Util/Haptics` (repris de Comet Conga) : `HapticEffect` du type indiqué (une instance réutilisée par type), repli `HapticService:SetMotor` pendant la durée. **Modération** : jamais au clavier-souris ; au téléphone, seulement la colonne « Téléphone » ; **délai minimal de 0,25 s** entre deux vibrations, sauf priorité supérieure ; atténuation < 0,35 ignorée ; réglage « Vibrations » (activé par défaut). Seuls les moteurs standard sont utilisés : aucun effet propre à la DualSense (gâchettes adaptatives) n'est supposé. Jamais de vibration sur un déplacement de sélection, un bond ou une marche.

| Événement | Quand | `HapticEffectType` | Repli (moteur, force, durée) | Priorité | Téléphone |
|---|---|---|---|---|---|
| `pressTick` | Pression (et pression sur le MEGA) — **2 par seconde au plus** | UIClick | Small, 0,15, 0,03 s | 1 | non |
| `perfect` | PERFECT ; série de 5 | UIClick | Small, 0,3, 0,05 s | 2 | non |
| `refuse` | Bouton refusé | UIClick | Small, 0,25, 0,05 s | 1 | non |
| `listEnd` | Bout de liste | UIClick | Small, 0,2, 0,04 s | 1 | non |
| `holdStart` | Début d'un maintien (Grand Splorch, boop, Nourrir Plop) | UIClick | Small, 0,25, 0,05 s | 1 | non |
| `catch` | Capture (fuite, Golden, Wild, Rush, Héros, capsule de cadeau) ; naissance Épique | GameplayCollision | Small, 0,35, 0,08 s | 2 | non |
| `fusion` | Chaque étape de fusion (force + 0,05 par étape) | GameplayCollision | Small, 0,4, 0,08 s | 2 | oui |
| `comboBig` | Combo ≥ 4 | GameplayCollision | Large, 0,6, 0,2 s | 3 | oui |
| `boopDone` | Mon boop a réussi | GameplayCollision | Small, 0,3, 0,06 s | 2 | non |
| `booped` | Un de mes squishies s'enfuit | UINotification | Small, 0,3, 0,12 s | 2 | non |
| `rushSiren` | Sirène du BOOP RUSH : **double impulsion** (2 × 0,1 s, écart 0,15 s) | UINotification | Small, 0,4, 2 × 0,1 s | 3 | non |
| `megaLand` | Atterrissage du MEGA à moins de 120 studs, atténué `1 − d/120` | GameplayExplosion | Large, 0,7, 0,25 s | 3 | non |
| `megaPop` | Le MEGA éclate (participant) | GameplayExplosion | Large, 0,8, 0,3 s | 4 | non |
| `hatchLegend` | Naissance Légendaire ou mieux ; Flop — **forte impulsion de 300 ms** | GameplayExplosion | Large, 0,8, 0,3 s | 4 | oui |
| `splorch` | Mon Grand Splorch (à l'éclatement) | GameplayExplosion | Large, 1,0, 0,4 s | 5 | oui |

### 10.6 Console et téléviseur (couche reprise de Comet Conga)

Le joueur est assis à 2,5-3 m de la télé. Règles officielles retenues (documentation Roblox *Console development guidelines*, *Gamepad input*) et leur traduction :

| Règle | Traduction pour Raise a Squishy |
|---|---|
| Tailles relatives, agrandir sur écran Large | UIScale proportionnel sans plafond sur console (1,5 en 1080p), §10.1 |
| `GuiService:IsTenFootInterface()` = seule détection sûre d'une console | `Platform.isTenFoot()` sous `pcall` |
| Zone sûre TV | Marge intérieure de **5 %** de chaque côté sur écran Large ou console (64 × 36 px de référence en 1080p) ; seuls les fonds décoratifs en sortent |
| Tout atteignable avec 4 directions + valider + retour | Chaque fenêtre est un `SelectionGroup` avec `SelectionBehavior* = Stop` ; graphe `NextSelection*` explicite là où la géométrie hésite ; vérifié par `tests/harness/Layout` et `Gamepad` (déjà dans le dépôt) |
| Actions clés en peu de gestes | Action unique □, R2 bondir, L2 monter, △ rail, L2/R2 entre panneaux ; chaque panneau à 3 gestes au plus de son voisin |
| Icônes de la manette du joueur | `UI/Glyph` : `GetImageForKeyCode`, repli neutre en losange (jamais « X » ou « LB » écrits) ; au clavier, texte de la touche selon la disposition (`GetStringForKeyCode` : sur AZERTY, `KeyCode.Q` s'affiche « A ») |
| **Pas de fenêtre de chat sur console** | `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)` (nouveaux essais pendant 10 s), `TextChatService.ChatWindowConfiguration.Enabled = false`, `ChatInputBarConfiguration.Enabled = false`. Les bulles restent. Communication : les 4 emotes |
| Vibrations avec modération | §10.5 |
| Sons de navigation | `Select`, `Back`, `Tab`, `Bump` (§9.6) |
| Navigation sur mesure plutôt que curseur virtuel | `StarterGui.VirtualCursorMode = Disabled` (déjà dans `default.project.json`) |
| Informations de maturité obligatoires | Questionnaire rempli avant d'activer la console (§18) |

**Modules repris tels quels** (copiés depuis Comet Conga, puis adaptés seulement là où ce GDD le dit) : `Client/Util/Platform`, `UI/Glyph`, `Util/Haptics` (table d'événements remplacée par celle du §10.5), `Config/Console`, `UI/Root` (échelle TV, zone sûre, `selectionImage` blanc de 6 px), le modèle de `PanelController` (○ recule, △ ferme, L1/R1, L2/R2, sélection jamais perdue, garde contre le double appui de 0,35 s, `holdSelection` pendant les fenêtres d'achat et d'invitation de Roblox), et le harnais `tests/harness/Gamepad` + `Layout`.

**Navigation écran par écran**

| Écran | Sélection par défaut | ○ | L1 / R1 | L2 / R2 |
|---|---|---|---|---|
| Jeu | aucune (le stick fait marcher) | Poser le squishy porté | Changer de cible (dans le ranch) | Monter / Bondir |
| Rail (après △) | Bouton à pastille « ! », sinon le dernier utilisé, sinon Ranch | Retour au jeu | — | — |
| Ranch | 1re case de l'onglet ; *Fusionner* : « Choisir A » ; *Dalles* : la moins chère achetable | → bouton du rail d'origine | Onglets | Panneaux |
| Squishydex | 1re entrée ; *Guide* : 1re ligne (↑ / ↓ font défiler de 70 % les listes en lecture seule) | → rail | Onglets | Panneaux |
| Objectifs | « Réclamer » disponible, sinon 1re carte | → rail | Onglets | Panneaux |
| Classements | Onglet en cours | → rail | Onglets | Panneaux |
| Boutique | 1er « Acheter » de l'onglet | → rail | Onglets | Panneaux |
| Réglages | 1er interrupteur | → rail | — | Panneaux |
| Aperçu du Grand Splorch | Bouton « Maintenir » (glyphe ✕) | → jeu | — | — |
| Carte du choix Rush / Cozy | « Je reste tranquille » (le choix sûr) | = Cozy | — | — |
| Écran de retour | « Super ! » | Ferme | — | — |
| Échec de chargement | Réessayer | — | — | — |

**Réglages de la place** (`default.project.json`, fichier d'un autre rôle) : `Players.MaxPlayers = 16`, `StreamingEnabled = true`, `VirtualCursorMode = Disabled`, `EnableMouseLockOption = false`, `TextChatService.ChatVersion = TextChatService`. La taille du serveur se règle aussi à 16 dans le Creator Hub (§18).

---

## 11. Monde : Wobbleton, construite en formes simples

### 11.1 Plan (vue de dessus, rayons en studs, origine au centre de la place)

```
                        r = 320  bord du plateau (collines de bonbons jusqu'à r = 420)
             ┌──────────────────────────────────────────────────────────┐
             │  16 RANCHS de r = 178 (portail) à r = 250 (fond),         │
             │  un tous les 22,5°, 64 studs de large                     │
             │     ┌────────────────────────────────────────────┐        │
             │     │  Grand boulevard r = 166 (12 de large)      │        │
             │     │  trottoirs r 170-178 : Fontaines de Gelée   │        │
             │     │     ┌──────────────────────────────┐        │        │
             │     │     │ QUARTIERS r 55-160 : maisons │        │        │
             │     │     │ bonbons, jardins, 8 rues     │        │        │
             │     │     │ radiales, anneau r = 95      │        │        │
             │     │     │     ┌──────────────┐         │        │        │
             │     │     │     │ PLACE r < 50 │         │        │        │
             │     │     │     │ MEGA pad,    │         │        │        │
             │     │     │     │ statue, Lune │         │        │        │
             │     │     │     └──────────────┘         │        │        │
             │     │     └──────────────────────────────┘        │        │
             │     └────────────────────────────────────────────┘        │
             │  Prairie des adieux (relâcher) : r = 280, au nord          │
             └──────────────────────────────────────────────────────────┘
```

| Élément | Construction | Position / dimensions |
|---|---|---|
| Plateau | Cylinder vertical, matériau Grass menthe (200, 240, 210) | Rayon 320, dessus à Y = 0 |
| Collines | 40 Balls aplaties pastel (rose, menthe, citron), tag `Float` lent pour quelques nuages | r 320-420, hauteur 10-40 ; murs invisibles à r = 322 |
| Place | Disque de pavés crème (255, 245, 220), bordure rose | r < 50 |
| MEGA pad | Cylinder rose clair Ø 30, épaisseur 0,6, anneau `Neon` qui s'allume à l'alerte | Centre de la place |
| Statue | Socle Marble Ø 10 × 3 ; le squishy est dessiné par le client à partir de l'attribut `Statue` (espèce, mutation, taille) | Nord de la place (0, 0, −38) |
| Boutique | Petite échoppe en Parts (toit rayé), comptoir avec invite « Vendre » et « Boutique » | Est de la place (38, 0, 0) |
| Autel de la Lune | Arche Marble + croissant `Neon`, compte à rebours du samedi (`SurfaceGui`) | Ouest de la place (−38, 0, 0) |
| Jarre de la jauge | Cylinder `Glass` Ø 8 × 12 qui se remplit (gelée `Neon` dont la hauteur suit la jauge) | Sud de la place (0, 0, 38) |
| Scène de Plop | Disque surélevé Ø 10 | Sud-est (27, 0, 27) |
| Fontaine dorée | Vasque Ø 8 (départ du Golden Wobbler) | Nord-est (20, 0, −20) |
| Tableaux des classements | 5 panneaux `SurfaceGui` en arc | Nord, r = 46 |
| Rues | Pavés roses (255, 230, 240) : anneau intérieur r = 95 (10 de large), grand boulevard r = 166 (12 de large), 8 rues radiales de r = 50 à r = 166 | ≈ 400 pièces |
| Quartiers | 24 maisons-bonbons non accessibles (corps Part + toit Wedge + 2 fenêtres `Neon`), sucettes, buissons-guimauves | Entre les rues |
| Lampadaires | Poteau Cylinder + Ball `Neon` (couleurs pastel) ; `PointLight` seulement un sur deux | 64 le long des rues (32 lumières) |
| Prairie des adieux | Champ de fleurs, panneau « Bye bye ! » | r = 280, nord |

**Graphe des rues** (`Shared/Logic/WorldLayout`, utilisé par `SeededPath`) : nœuds sur l'anneau de la place (r = 50, tous les 45°), sur l'anneau intérieur (r = 95, tous les 22,5°) et sur le boulevard (r = 166, tous les 11,25°, donc un nœud devant chaque portail) ; arêtes le long des rues. Les fuites, les Wild Wobblers et le Golden Wobbler ne quittent jamais ce graphe : ils n'entrent jamais dans un ranch.

### 11.2 Un ranch (repère local : X en travers de −32 à +32, Z du portail (0) vers le fond (72))

| Pièce | Construction | Position locale |
|---|---|---|
| Clôture | Poteaux sucre d'orge tous les 8 studs + lisses arrondies, hauteur 4, couleur du ranch ; solide pour tous | Tout le tour |
| Portail de gelée | Membrane `Glass` (seule transparence permise avec la gelée Jelly) entre deux poteaux, 8 de large ; le propriétaire passe, les autres rebondissent (§6.3) | Z = 0, X = 0 |
| Fontaine de Gelée | Vasque Ø 5 avec jet de gelée | Côté rue : Z = −6, X = +12 |
| Panneau du ranch | BillboardGui : nom (ou « Ranch 7 »), couronne R, Fame, « Jour 42 », badge Rush ou Cozy | Au-dessus du portail, Y = 14, distance max 150 |
| Enclos | Zone logique de 54 × 36 (4 rangées × 6 places), sol en tapis pastel | Z 8 à 44 |
| Pot à Pièces | Grosse marmite dorée (Cylinder + Ball), montant au-dessus | Z = 6, X = −20 |
| Tapis à Goûter | Grand tapis à motif biscuit sous les enclos ; il change de couleur et de motif à chaque niveau | Sous la zone des enclos |
| Cuve à Gelée | Cylinder `Glass` Ø 6 × 9 + couvercle + tuyau ; niveau de gelée `Neon` visible | Z = 52, X = −20 |
| Bassin de Fusion | Bassin Ø 12, eau pastel `Glass`, 5 (ou 6) places flottantes | Z = 52, X = +6 |
| Dalles d'achat | Disques `Neon` Ø 4 avec icône et prix (`SurfaceGui`) | Rangée Z = 62, X de −24 à +24 |
| Décorations | 12 emplacements fixes | Autour des enclos et du chemin |
| Bol de Plop | Grand bol rose Ø 4 | Z = 58, X = +22 |
| Coussin du Meilleur Ami | Coussin rond Ø 4 | Z = 10, X = +22 |
| Étagère à trophées | 3 étagères de 9 places, petites statues dessinées par le client | Fond : Z = 70 |
| Apparition | `SpawnLocation` transparente, sans collision, `Neutral = true` | Z = 30, X = 0, face au Pot |
| Silhouette | Le meilleur squishy (client) | Z = 36, Y = 40 |

Ranch k (k = 0…15) centré sur l'angle `22,5° × k + 11,25°`, portail à r = 178, orienté vers la place. Distance entre deux portails voisins : ≈ 69,8 studs.

### 11.3 Éclairage et palette

| Propriété | Valeur |
|---|---|
| `ClockTime` | 14,5 fixe (plein jour pastel) ; la nuit seulement pendant la Jelly Moon (0,0) |
| `Ambient` / `OutdoorAmbient` / `Brightness` | (150, 140, 170) / (190, 180, 210) / 2,5 |
| `Atmosphere` | Density 0,25, Color (255, 220, 240), Decay (170, 200, 255), Haze 1,2 |
| `BloomEffect` | Intensity 0,6, Size 20, Threshold 1,3 |
| `ColorCorrectionEffect` | Saturation 0,2, Contrast 0,05 |
| `Technology` | Future (réglage du projet) ; repli ShadowMap si le profilage sur téléphone l'exige |

| Préréglage (tween de 2 à 4 s, client) | Changements |
|---|---|
| BOOP RUSH | `Tint` (255, 200, 225), Atmosphere Color (255, 190, 220) |
| Jelly Moon | `ClockTime` 0, `MoonAngularSize` 30, `StarCount` 4000, Tint (200, 190, 255), Atmosphere Color (150, 120, 220) |
| Wobble Party / Squish Party | Tint (255, 240, 210), Bloom 0,8 |
| Hiver « Frost & Sprinkles » (lancement) | Plaques de « sucre glace » (Parts blanches `Sand`), guirlandes de bonbons `Neon` sur les lampadaires, flocons de sucre (`ParticleEmitter` qui suit la caméra, 10 par seconde, budget §12.9) |

Matériaux : SmoothPlastic (squishies, maisons), `Neon` (accents, dalles, lampes), `Glass` (gelée, Cuve, Bassin, portails), Grass (sol), Marble (statue, autel), `Foil`, `Ice`, `ForceField` (mutations). Lisibilité au téléphone : sol pastel peu saturé, créatures vives.

### 11.4 Budget de construction

Carte ≈ 4 000 pièces (plafond 4 500) : plateau, collines et murs ≈ 120 ; place ≈ 250 ; rues ≈ 400 ; quartiers ≈ 800 ; lampadaires ≈ 130 ; ranchs 16 × ≈ 140 (tout construit) ≈ 2 240. Les squishies, les créatures en fuite, les statues et les effets sont **côté client** et ne comptent pas ici (§12.9). La place et les panneaux des ranchs sont en `ModelStreamingMode = Persistent`.

---

## 12. Architecture technique

### 12.1 Principes

1. **Le serveur décide de tout.** Les clients n'envoient que des **intentions** (« je presse ce squishy », « je bondis ») ; le serveur vérifie chaque message (types, `NaN` et infini, bornes, appartenance, tailles des tables), le limite en débit, puis décide. Aucune valeur économique venant d'un client n'est acceptée.
2. **Les squishies sont des données.** Le serveur garde les profils et l'état public des ranchs ; les clients dessinent tout (squishies, créatures, effets) à partir de ces données. Rien de physique n'est répliqué pour les créatures.
3. **Calcul paresseux** : aucune boucle par seconde et par squishy. Taille et Pot se calculent à partir d'horodatages (§12.3).
4. **Une seule horloge** (`Shared/Util/Clock`, reprise de Comet) et des phases d'événements déterministes (`EventClock`) : serveur et clients calculent les mêmes horaires et les mêmes trajets de créatures.
5. **Contenu piloté par les données** : espèces, mutations, raretés, dalles, événements, objectifs, prix, sons sont des tables de `Shared/Config`.
6. **Réutiliser la base de Comet Conga**, durcie par 6 tours de QA : `DataService` (verrou de session, reprise du verrou, migrations, réplication par patchs), `MonetizationService` (reçus idempotents), `Net`/`Remotes`, `Validate`, `RateLimit`, `Trove`, `Signal`, `Clock`, `Hash`, `MoveCheck` (budget d'action), `Juice`, `Toast`, `Theme`, `Build`, `Prices`, `Analytics`, `Notify`, la couche console (§10.6) et le harnais de tests Lune (déjà présent dans `tests/harness`).
7. `--!strict` partout, API publiques typées, commentaires en français, identifiants en anglais. `task.wait/spawn/delay/defer` seulement. Compatible `SignalBehavior = Deferred`. **Cycle de vie** : joueurs déjà présents traités au branchement de `PlayerAdded` ; nettoyage complet à `PlayerRemoving` (`Trove` par joueur) ; personnages absents ou en réapparition toujours tolérés ; tout `WaitForChild` côté client a un délai.
8. Tout texte vu par le joueur passe par des clés de `Shared/Localization/Strings` (anglais **et** français). Tous les nombres viennent de `Shared/Config/*`.

### 12.2 Arbre Rojo et interrupteurs

```
src/
  first/            → ReplicatedFirst
    Loading.client.luau            écran de chargement en code (repris, adapté)
  shared/           → ReplicatedStorage.Shared
    Net.luau, Remotes.luau          (repris ; liste du §12.7)
    Types.luau
    Config/
      Balance.luau                  revenu, croissance, pression, dalles, Grand Splorch, hors ligne, plafonds
      Squishies.luau                26 espèces (lignes de données §5.1), familles et bonus
      Rarities.luau, Mutations.luau tables du §4.4 et du §4.5
      Vat.luau                      tables de qualité, protection contre la malchance, nouveauté garantie
      Events.luau                   horaires (§2.4), Rush, MEGA, Golden, Wild Wobblers, jauge, Lune
      Quests.luau                   objectifs du jour, paliers de Plop, jalons du Squishydex
      Cosmetics.luau                selles, traînées, tenues, titres, thèmes, palette des ranchs
      Monetization.luau             passes et produits, identifiants à 0 au départ
      Sounds.luau                   clés du §9.6, provenance sur chaque ligne
      Console.luau, Settings.luau   (repris)
      Features.luau                 interrupteurs (ci-dessous)
    Logic/                          modules PURS (aucun service Roblox), testés sous Lune
      Formulas.luau                 croissance, revenu, pression, coûts, objectifs, hors ligne, Pot (forme exacte §12.3)
      Odds.luau                     tirages de rareté, d'espèce, de mutation, protections, « 1 sur X »
      FusionRules.luau              jumeaux, fusion, chaîne de combo
      RushRules.luau                ordre de vérification d'un boop (§4.21.4), récompenses
      MegaRules.luau                objectif, indulgence, paliers
      SizeScale.luau                échelle logarithmique et plafonds
      EventClock.luau               phases de chaque événement à l'instant t
      SeededPath.luau               trajets des créatures (graphe des rues, bonds)
      WorldLayout.luau              positions des ranchs, de la place, graphe des rues
      PressTiming.luau              phase du rebond, fenêtre PERFECT
      Hash.luau                     (repris)
    Render/
      SquishyBuilder.luau           recettes de modèles (client)
    Localization/Strings.luau       EN + FR
    Util/                           (repris) Clock, Format (nombres géants §4.2), Signal, Tables, Trove, Validate
  server/           → ServerScriptService.Server
    Main.server.luau
    Data/Schema.luau, Data/Admins.luau
    Services/
      DataService, MonetizationService          (repris)
      WorldService          construit Wobbleton et les 16 ranchs
      RanchService          attribution, voisins, portails, poussée des intrus, état public des ranchs
      EconomyService        calcul paresseux, Pot, dalles, multiplicateurs, hors ligne, boosts
      SquishyService        collection : naissances, Cuve, enclos, Dodo, Lettres, vente, relâche, verrou, Meilleur Ami, monture, portage, Bassin et combos
      ChaseService          tick 10 Hz : créatures en fuite, Golden, Wild Wobblers, fuites du Rush, captures, bonds, contrôle de déplacement
      RushService           mode Rush/Cozy, clôtures, maintiens de boop, protections
      EventService          EventClock : Rush, MEGA, Golden, Lune, jauge, Wobble Party, file des spectacles, LiveOps
      SplorchService        Grand Splorch, spectacle, cadeaux, applaudissements, Étagère à trophées
      QuestService          accueil, Nourrir Plop, objectifs, carte « Plop a sommeil », Squishydex
      CommunityService      amis, pet-sitting, emotes, bannières, nom caché, liste de blocage (souple)
      ProductService        effets des passes et produits
      LeaderboardService    tableaux du serveur et OrderedDataStores de la semaine
    Util/ RateLimit, Analytics, Notify, MoveCheck   (repris)
  client/           → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau
    Util/ Platform, Haptics, Prefs, Prices          (repris)
    Controllers/
      StateController       miroir du profil (repris)
      WorldStateController  miroir des ranchs, des événements et des créatures
      RanchRenderer         squishies, niveaux de détail, BulkMoveTo, animations, silhouettes, statue
      ChaseRenderer         créatures en fuite, Golden, Wild Wobblers, fuites du Rush
      PromptController      invites contextuelles, cible, cycle L1/R1, visée automatique
      InputController       ContextActionService : action, bondir, monter, poser, emotes, rail
      CameraController      cadrage de la cible, travelling du Grand Splorch
      VFXController, AudioController, LightingController, OnboardingController
    UI/
      Root, Theme, Create, Juice, Toast, Glyph       (repris)
      HUD, Banners, ScreenFX, ReturnScreen, ModeCard
      Panels/ Ranch, Squishydex, Objectives, Leaderboards, Shop, Settings, SplorchPreview, OutfitPreview
tests/specs/                        §12.10
```

**Interrupteurs de configuration** (`Shared/Config/Features.luau`, lus au démarrage et sur un message LiveOps d'administrateur, sans nouvelle version) :

| Clé | Lancement | Effet |
|---|---|---|
| `BoopRush` | `"on"` | `"on"` / `"events"` (Lune et Squish Parties d'administrateur seulement) / `"off"` (Wild Wobblers seuls aux heures du Rush) |
| `MegaSquish`, `GoldenWobbler`, `JellyMoon`, `ServerGauge` | `true` | Couper un événement en cas de problème en ligne |
| `Clips` | `true` | Captures vidéo automatiques |
| `Costumes` | `"winter2026"` | Costume de saison actif (calendrier dans `Events.Costumes`) |
| `JellyAscend`, `Season`, `SlowJelly`, `Duo`, `Parcels`, `WorldFirst`, `FameLineage`, `GreatJelly` | `false` | Fonctions de janvier et février (§17) ; le code de lancement n'en contient que les crochets |
| `RewardedAds` | `false` | Aucun code de publicité au lancement ; la clé existe pour qu'on ne l'ajoute jamais « par défaut » |

### 12.3 Ordre d'initialisation, tick et calcul paresseux

`Main.server.luau` : `Net.setup()`, puis `Init()` puis `Start()` dans cet ordre : DataService → MonetizationService → WorldService → RanchService → EconomyService → SquishyService → QuestService → CommunityService → EventService → RushService → SplorchService → ProductService → LeaderboardService → ChaseService (dernier : il porte le tick).

**Tick de `ChaseService`** (accumulateur sur `RunService.Heartbeat`, pas fixe de 0,1 s, 3 pas rattrapés au plus par image) :

```
1. now = Clock.now()
2. pour chaque joueur chargé avec personnage : MoveCheck.step(...) → position validée ? peut agir ?
3. RanchService.step : intrus repoussés ; Pot encaissé si le joueur est à ≤ 5 studs (position validée)
4. EventService.step(now) : transitions de phase (Rush, MEGA, Golden, Lune, Wobble Party, file des spectacles)
5. RushService.step(now) : clôtures (renouvellement toutes les 20 s), maintiens de boop terminés ou rompus
6. Créatures : apparitions dues (fuites personnelles, Wild, Golden), fins (25 s, 20 s, 30 s)
7. Captures : intentions `Catch` reçues depuis le tick précédent, vérifiées à la position SeededPath de maintenant
8. MEGA : pressions reçues agrégées, battement diffusé toutes les 0,25 s
9. Diffusion groupée : ChaseEvent, EventState, RanchPatch
```

**Calcul paresseux** (module pur `Formulas`). Entre deux événements, la croissance `g` du ranch est constante, donc chaque taille est linéaire : `z(t) = z0 + g × (t − t0)`. Le revenu total `I(t)` est donc lui aussi linéaire : `I(t) = I0 + I' × (t − t0)`, avec `I' = Σ 0,02 × rareté × mutation × (1 + 0,5 × étoiles) × A × P × B × g`. Le Pot est l'intégrale exacte :

```
pot(t) = pot0 + I0 × Δ + ½ × I' × Δ²      (Δ = t − t0)
```

Le serveur « règle » (`settle`) le ranch à chaque événement qui change `g`, `A`, `P` ou `B` (achat, naissance, fusion, vente, boost qui commence ou finit, ami qui arrive ou part, Grand Splorch), avant chaque sauvegarde, et toutes les 30 s (décalé selon le joueur). Le client prédit les tailles et le Pot avec les mêmes formules, corrigé à chaque patch.

### 12.4 Le temps : `Clock` et `EventClock`

`Shared/Util/Clock` (repris de Comet, testé) : `Clock.now()` (secondes UTC fractionnaires = `workspace:GetServerTimeNow()` + décalage ou gel), `Clock.unix()` (entier, pour les horodatages **sauvegardés**), `Clock.day()`, `Clock.week()` (lundi 00:00 UTC), `Clock.weekday()`, `Clock.secondOfDay()`, `Clock.untilNextDay()`, `Clock.untilNextWeek()` ; contrôle pour les tests : `Clock.freeze(t)`, `Clock.advance(dt)`, `Clock.unfreeze()`, `Clock.setOffset(s)`. Règle : durées de jeu et recharges en `Clock.now()` ; horodatages sauvegardés en `Clock.unix()`. **Aucun module ne lit `os.time()` ni `tick()` directement** : les tests font voyager le temps.

`Shared/Logic/EventClock` (nouveau, pur) :

```lua
EventClock.rush(t): { active: boolean, index: number, startsAt: number, endsAt: number, sirenAt: number }
EventClock.mega(t): { active: boolean, index: number, warnAt: number, landsAt: number, endsAt: number, moon: boolean }
EventClock.golden(t): { active: boolean, index: number, spawnAt: number, endsAt: number }
EventClock.moon(t): { active: boolean, session: number?, startsAt: number, endsAt: number }  -- samedi ×4, dimanche ×1
EventClock.nextEvent(t): { kind: string, at: number }        -- pour la pastille du HUD
EventClock.megaSpecies(t): number                            -- rotation §5.1
EventClock.seed(kind: string, index: number): number         -- graine des trajets (Hash)
```

Tests à des instants clés : minuit, :04:50, :05:00, :06:30, :19:45, :20:00, :21:05, samedi 15:59:59, 16:00, 16:20, 22:20, dimanche 16:00, changement de semaine.

### 12.5 Trajets des créatures et réplication

- **`SeededPath`** : `escape(seed, t0, startNode)` renvoie une fonction `pos(t)` : marche au hasard (graine) sur le graphe des rues, sans demi-tour immédiat, vitesse `v(t) = 16 − 0,32 × (t − t0)` studs/s (bornée à 8), bonds de 0,45 s (hauteur visuelle seulement). `hopAround(seed, t0, centre, rayon)` pour les créatures en fuite personnelles. Même code côté serveur et côté client : le serveur ne diffuse que la graine, l'instant de départ et le nœud de départ.
- **Capture** : le serveur compare la position validée du joueur (MoveCheck) à `pos(maintenant)` : distance ≤ 6,5 studs (5 + 1,5 de tolérance de latence), écart vertical ≤ 8.
- **`ChaseEvent`** (fiable, groupé à 4 Hz) : `spawn = { id (u16), kind (runaway | escape | wild | golden | demo), species, mutation, size, ownerSlot?, seed, t0, startNode, duration }` et `finish = { id, reason (caught | returned | expired), bySlot? }`. Les créatures personnelles (fuite, démonstration de Plop) ne sont envoyées qu'au client concerné.
- **État des ranchs** : `RanchSnapshot` à l'arrivée (16 ranchs, ≈ 15 Ko), puis `RanchPatch` groupé par image : par ranch `{ g, gAt, tiles, decor, R, fame, day, mode, hidden, name }` et par squishy `{ op = add | remove | update, uid, s, m, st, z, zAt, bf, o, at }`. Le client calcule `z(t) = z + g × (t − zAt)`. Aucun envoi par seconde.
- **Arrivée en cours de partie** : `RanchSnapshot` + `EventState` + créatures actives, une seule fois.

### 12.6 Données sauvegardées (schéma v1)

Magasin `PlayerData_v1`, clé `player_<UserId>`, gérés par le `DataService` repris de Comet Conga, avec ses règles durcies :

- **Verrou de session** posé au chargement (`UpdateAsync`), avec un jeton propre à ce chargement. Un verrou d'un autre serveur plus jeune que 30 min fait réessayer toutes les 5 s ; il n'est **repris** qu'après **5 lectures réussies** qui l'ont vu (au moins 25 s d'observation pendant que les DataStores répondent), **jamais parce que des erreurs ont épuisé les essais** (sinon renvoi poli « reviens dans un instant », rien d'écrit). Le serveur qui détient le verrou réessaie sa sauvegarde de départ en panne toutes les 15 s au plus pendant 5 min : un enfant qui revient sur un autre serveur après une panne retrouve ce qu'il a gagné (leçon `Fix_final_data_lock` de Comet).
- Chaque écriture refuse d'écraser un enregistrement verrouillé par un autre serveur ou de **schéma plus récent** (dans ce cas le joueur est renvoyé : « Ce serveur n'est pas à jour »).
- Attribut répliqué `ProfileLoading` pendant les essais (lu par l'écran de chargement).
- Jamais de profil par défaut sauvegardé par-dessus un échec de chargement ; en ligne, jamais de repli en mémoire si les DataStores sont indisponibles.
- Sauvegarde automatique toutes les 90 s, au départ, à la fermeture (`BindToClose`), et immédiate après un achat Robux (le reçu n'est acquitté qu'après une écriture réussie). `settle` est appelé avant chaque sauvegarde.

```lua
Schema.VERSION = 1
Schema.PRIVATE_KEYS = { receipts = true, flags = true }

function Schema.defaults()
  return {
    version = 1,
    -- économie (§4.1, §4.6, §4.8)
    coins = 0, pot = 0, lastSettle = 0, lastOnline = 0, R = 0,
    tiles = { snack = 0, decor = 0, vatSpeed = 0, vatQuality = 0, nozzles = 0, pens = 0, cozyBed = false },
    boosts = { personalLeft = 0 },   -- secondes restantes du boost personnel (en pause pendant un boost de serveur)
    -- collection (§4.3, §4.9, §4.14)
    squishies = {},   -- [uid] = { s = 1-26, m = 0-9, st = 0-5, z = taille, zAt = Clock.now() du dernier règlement,
                      --           bf = 0-3, lk = bool, o = tenue ou "", at = "pen"|"pool"|"dodo"|"mail" }
    nextUid = 1,
    mount = "",       -- uid de la monture choisie ("" = la plus grosse sellée)
    vat = { fillAt = 0, pending = false, pityRare = 0, pityEpic = 0, newPulls = 3 },
    runaway = { nextAt = 0 },
    dex = {
      species = 0,                          -- 26 bits
      mutations = { 0, 0, 0, 0, 0, 0, 0, 0 },  -- 8 mots de 32 bits : bit (s − 1) × 9 + (m − 1), 234 utilisés, réserve jusqu'à 28 espèces
      stars = { 0, 0, 0, 0, 0 },            -- badge ★k : bit s − 1 du mot k
      rewards = 0,                          -- dernier jalon réclamé
    },
    trophies = {},    -- [s] = taille record
    outfits = { owned = {}, worn = {} },   -- owned[id] = nombre ; worn[id] = uid
    -- social et rétention (§6, §7)
    fame = 0, plopDays = 0, lastFeedDay = 0,
    onboarding = { step = 0, done = false },
    objectives = { day = 0, list = {}, rerolls = 0, allClaimed = false },  -- list = { { id, p, done, claimed } × 3 }
    caps = { day = 0, rushBabies = 0, splorchGifts = 0, fameBooped = 0, fameRelease = 0, petSit = 0, claps = 0 },
    mode = { rush = false, chosen = false, changedAt = 0 },
    golden = { lastWinAt = 0 },
    party = { lastBuyAt = 0 },
    weekly = { week = 0, biggest = 0, combo = 0, catchScore = 0, helpful = 0, generous = 0 },
    settings = { hideName = false, receiveGifts = true, clips = true, reducedMotion = false, lowGraphics = false,
                 music = true, sfx = true, vibration = true, lang = "auto", partyShowName = false },
    stats = { presses = 0, perfects = 0, fusions = 0, bestCombo = 0, hatches = 0, catches = 0, boops = 0,
              booped = 0, heroCatches = 0, megas = 0, splorches = 0, playSeconds = 0, sessions = 0,
              firstBoopReceivedAt = 0, lastFriendDay = 0, biggestEver = 0 },
    -- réservé pour plus tard (§17) : valeurs neutres, jamais lues au lancement
    ascend = 0,                                                  -- Jelly Ascend
    season = { id = 0, xp = 0, premium = false, claimed = {} },  -- saison de 28 jours
    slowJelly = { slots = {} },                                  -- Gelée lente 1 / 4 / 12 h
    parcels = { inbox = {}, sentDay = 0, sent = 0 },             -- colis entre amis
    fameLineage = 0,                                             -- lignée de Fame (registre séparé)
    worldFirst = {},                                             -- trouvailles World First
    costumes = {},                                               -- costumes de saison obtenus
    -- privé
    passes = {}, receipts = {}, flags = { strikes = 0, lbBanUntil = 0 },
  }
end
```

- **Taille** : au plus 24 + 60 + 20 = 104 squishies × ≈ 70 octets ≈ 7 Ko ; profil complet < 20 Ko.
- **Règles** : `coins`, `pot`, `z` dans `[0 ; 1e300]`, jamais `NaN` ; uid = chaîne base 36 de `nextUid` (8 caractères au plus) ; invariants vérifiés en développement après chaque mutation (au plus 24 squishies `pen`/`pool`, 60 `dodo`, 20 `mail` ; un seul squishy par emplacement de Meilleur Ami ; tenue portée par un uid qui existe).
- **Migrations** : `Schema.migrate(data, from)`, étapes pures testées sur une sauvegarde-témoin (`tests/fixtures/profiles/v<n>.json`) ; on n'efface jamais un champ dans la version qui le remplace ; `reconcile` ajoute les champs nouveaux avec leur valeur par défaut. Les champs réservés ci-dessus évitent toute migration pour les fonctions de janvier.
- **Droit à l'effacement** : chaque `UpdateAsync` du profil renvoie `userIds = { UserId }` (procédure reprise de Comet).
- Les classements de la semaine vivent dans des `OrderedDataStore` séparés (§6.9) ; la lignée de Fame aura son propre registre (janvier).

### 12.7 Messages réseau (remotes)

Déclarés dans `Shared/Remotes.luau`, créés par `Net.setup()`. Chaque handler serveur suit l'ordre : **débit** (`RateLimit.allow`, seau à jetons par action, vidé au départ) → **types** (`Validate` : nombres finis, entiers, longueurs de chaînes, tables séquentielles bornées) → **existence** (clé de configuration, uid possédé) → **état** (profil chargé, personnage vivant, position validée, `MoveCheck.canAct`) → **règles métier** → mutation atomique → réplication. Un message refusé ne produit **aucune** mutation et au plus un `Feedback` neutre.

**Client → serveur (intentions)**

| Remote | Charge utile | Validation serveur | Débit max |
|---|---|---|---|
| `Press` | `uid: string, tClient: number` | uid possédé, dans un enclos ou le Bassin, à ≤ 10 studs (position validée), recharge de 8 s écoulée ; `tClient` fini, accepté s'il est dans [maintenant − 0,35 ; maintenant + 0,05] | 12 / s |
| `PickUp` | `uid: string` | Possédé, dans un enclos, à ≤ 10 studs, rien de porté, pas en monture | 4 / s |
| `PutDown` | — | Quelque chose est porté | 4 / s |
| `Throw` | — | Quelque chose est porté, à ≤ 12 studs du Bassin ; place ou jumeau disponible | 4 / s |
| `FuseMenu` | `uidA: string, uidB: string` | Différents, possédés, jumeaux, hors Dodo et Lettres | 2 / s |
| `BuyTile` | `tile: string` | `tile` ∈ {snack, decor, vatSpeed, vatQuality, nozzles, pens, cozyBed} ; niveau < maximum (et ≤ min(8, 1 + R) pour la qualité) ; condition R ; règlement puis pièces ≥ prix. Position non exigée (achat possible depuis le panneau Ranch) | 10 / s |
| `MoveSquishy` | `uid: string, to: string` | `to` ∈ {pen, dodo} ; place libre ; pas porté, pas en fuite | 4 / s |
| `ClaimMail` | `uid: string` | Dans la Boîte aux lettres ; place libre | 4 / s |
| `Sell` / `Release` | `uids: {string}` | Table séquentielle de 1 à 24 chaînes uniques, possédées, ni Meilleur Ami, ni verrouillées, ni en fuite | 2 / s |
| `SetLock` | `uid: string, locked: boolean` | Possédé | 6 / s |
| `SetBestFriend` | `uid: string, slot: number` | Entier 1 à 3, emplacement débloqué (R), possédé | 2 / s |
| `SetMount` | `uid: string` | Possédé, taille ≥ 1 200 | 2 / s |
| `Ride` | `on: boolean` | Une monture existe ; rien de porté | 2 / s |
| `Leap` | `dirX: number, dirZ: number` | Finis, norme entre 0,5 et 1,5 ; recharge de 4 s écoulée → MoveCheck accorde +12 studs pendant 0,35 s | 3 / s |
| `Catch` | `id: number` | Entier ; créature active ; attrapable par ce joueur (personnelle, mode Rush pour une fuite du Rush, recharge du Golden) ; distance ≤ 6,5 à `pos(maintenant)` ; `canAct` | 6 / s |
| `BoopHold` | `ownerId: number, uid: string, holding: boolean` | Entiers et chaîne bornés ; ordre `RushRules` (§4.21.4) au début ; distance ≤ 8 vérifiée à chaque tick pendant le maintien ; le serveur termine le boop lui-même à 2,5 s ou 5 s | 4 / s |
| `MegaPress` | `tClient: number` | MEGA actif, à ≤ 20 studs du centre, recharge de 0,4 s | 3 / s |
| `FeedPlop` | `holding: boolean` | À ≤ 8 studs du bol, pas encore nourri aujourd'hui ; 5 s mesurées par le serveur | 2 / s |
| `GrandSplorch` | `film: boolean` | Plus gros ≥ objectif ; dans son ranch ; rien de porté ; maintien de 1,5 s mesuré côté client (geste), refait après la file | 1 / 2 s |
| `ClaimObjective` / `RerollObjective` | `slot: number` | Entier 1 à 3 ; terminé et non réclamé / relance disponible et non terminé | 4 / s |
| `ClaimDexReward` | — | Jalon atteint et non réclamé | 2 / s |
| `SetMode` | `rush: boolean` | Recharge de 60 s ; serveur privé sans autorisation : refusé ; pendant un Rush : appliqué à la fin | 1 / s |
| `SetSetting` | `key: string, value: boolean \| string` | Clé dans la liste du §10.3 ; type attendu ; `lang` ∈ {auto, en, fr} ; `allowRush` : propriétaire du serveur privé | 4 / s |
| `EquipOutfit` | `outfit: string, uid: string?` | Tenue possédée (nombre > portées) ; uid possédé ou `nil` (retirer) | 2 / s |
| `Emote` | `kind: number` | Entier 1 à 4 | client 1 / 1,5 s ; serveur 1 / 1,2 s |
| `Clap` | `heroId: number` | Fenêtre d'applaudissement ouverte pour ce héros ; pas déjà applaudi | 2 / s |
| `ReportBlocked` | `userIds: {number}` | Table séquentielle de 0 à 200 entiers positifs | 1 / 10 s |
| `SetInputType` | `kind: number` | Entier 1 à 3 (tactile, clavier-souris, manette) — **analytique seulement**, ne donne aucun avantage | 1 / 5 s |
| `RequestSnapshot` / `RequestWorld` | — | — | 1 / 2 s |

Aucun `RemoteFunction` ne va du serveur vers le client. Les achats Robux passent par `MarketplaceService:Prompt…Purchase` côté client et `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur, sans remote du jeu.

**Serveur → client**

| Remote | Charge utile | Destinataires |
|---|---|---|
| `DataSnapshot`, `DataPatch` | Profil public, patchs groupés par image (repris) | Le joueur |
| `RanchSnapshot`, `RanchPatch` | §12.5 | Tous |
| `ChaseEvent` | §12.5 | Tous, ou un seul pour les créatures personnelles |
| `EventState` | `{ rush, mega, golden, moon, gauge, boost, spectacleQueue }` | Tous, à chaque changement |
| `MegaBeat` | `{ points, target, presses }` | Tous, 4 Hz pendant le MEGA |
| `Fence` | `{ ranchSlot, uids }` (squishies à la clôture) | Tous, pendant le Rush et le pet-sitting |
| `BoopState` | `{ booperSlot, ownerSlot, uid, endsAt }` (maintien en cours) | Tous |
| `Banner` | `{ kind, args }` | Tous |
| `Feedback` | `{ key, vars, tone }` | Le joueur |
| `Celebrate` | `{ kind, data }` (naissance, fusion, combo, capture, Grand Splorch, palier, objectif) | Le joueur (et tous pour le Grand Splorch) |
| `EmoteShow` | `{ userId, kind }` | Tous |
| `ClapPrompt` | `{ heroId, endsAt }` | Tous sauf le héros |
| `ModePrompt` | — (carte du choix Rush / Cozy) | Le joueur |

### 12.8 Anti-triche

| Menace | Parade |
|---|---|
| Vitesse, téléportation, bond sans recharge | **`MoveCheck` repris de Comet avec son budget d'action** : un « seau » de studs dont le plafond est la règle d'un tick (`vmax × dt × 1,5 + 4`), rempli à `vmax × 1,5` studs/s ; chaque position acceptée retire sa distance ; la dette passe d'un message à l'autre. Tant que la dette n'est pas remboursée, le joueur **ne peut pas agir** (attraper, booper, presser, encaisser le Pot, presser le MEGA). `vmax` = WalkSpeed serveur maximal des 0,5 dernières secondes (16, ou 22,4 en monture) ; un bond accordé par le serveur ajoute 12 studs sur 0,35 s. Une infraction **signale seulement** ; 3 en 5 s → retour à la dernière position valide (`PivotTo`), 3 s sans action, icône neutre « connexion instable » (jamais d'accusation). Gel réseau honnête jusqu'à 1,5 s toléré. Exemptions 3 s après une apparition ou un `PivotTo` du serveur |
| Vol, passe-muraille | Altitude > sol + 14 pendant plus de 1,5 s, hors du plateau (r > 322) ou sous le sol → retour à la dernière position valide (règles de hauteur de Comet) |
| Entrer dans un ranch | Poussée hors du ranch à chaque tick (§6.3) ; position validée seulement |
| Debout sur un autre joueur | **Aucune collision entre personnages** (groupe de collision `Characters` qui ne se touche pas lui-même) : personne ne porte personne, personne ne bloque un portail (leçon du tour 5 de Comet) |
| Valeurs envoyées par le client | Aucune valeur économique acceptée. `tClient` des pressions borné à 0,35 s dans le passé (§4.7). Le type d'entrée est seulement analytique (aucun bonus « tactile », leçon de Comet) |
| Rafales de remotes | Seau à jetons par action (§12.7) |
| Fermes de bébés (comptes complices) | Plafonds journaliers, taille ≤ 2 × le plus gros du receveur, 1 boop par paire et par Rush, recharge de 20 s, 2 fuites par ranch |
| Robots qui pressent | Rien à gagner hors de son propre ranch ; débit borné ; récompenses en secondes de revenu (un robot ne crée pas de valeur infinie) |
| Classements | Exclusion après 10 retours forcés en 10 min, **jusqu'à la fin de la semaine suivante** (`flags.lbBanUntil`), jamais à vie (question laissée ouverte par Comet, tranchée ici) |
| Lecture de secrets | Administrateurs LiveOps et réglages anti-triche dans `ServerScriptService` seulement |
| Achats | `ProcessReceipt` unique et idempotent ; passes vérifiés à l'arrivée et à l'achat, vérifications bornées en débit (repris) |
| Duplication | Aucun échange au lancement ; toutes les mutations de collection se font sur le profil d'un seul joueur, sous verrou de session. Un bébé est une **création** du serveur, jamais un déplacement entre profils |

### 12.9 Budgets de performance

Appareil de référence : téléphone Android modeste (≈ 3 Go de RAM). Les mesures se font sur un vrai appareil (l'émulateur de Studio ne mesure pas la mémoire réelle).

| Ressource | Budget |
|---|---|
| Images par seconde | 60 visées, jamais moins de 30 avec 16 joueurs, 384 squishies affichables et un Rush complet |
| Pièces de la carte | ≤ 4 500 (prévu ≈ 4 000) |
| Pièces de squishies rendues | ≤ 2 500 ; ≤ 80 squishies en détail complet (12 pièces) et animés à pleine cadence ; le reste en 3 ou 1 pièce |
| Mise à jour des squishies | Un `workspace:BulkMoveTo(..., Enum.BulkMoveMode.FireCFrameChanged)` par image ; 15 Hz entre 60 et 140 studs ; immobiles au-delà |
| `Highlight` | **≤ 20** sur un client (la limite d'affichage du moteur est 255, d'après la documentation officielle) : cible 1, squishies en fuite du Rush ≤ 10, Mythiques et Secrets les plus proches ≤ 6, Golden 1, réserve 2 |
| Lumières actives | ≤ 40 : 32 lampadaires, ranch local, Légendaires+ les plus proches ≤ 6 |
| Particules à l'écran | ≤ 300 ; émetteurs réutilisés ; flocons d'hiver compris |
| Créatures | ≤ 10 fuites du Rush + ≤ 13 Wild Wobblers + 1 Golden + 16 créatures personnelles (une par joueur, vue par lui seul) |
| Serveur | Tick de 10 Hz < 3 ms en moyenne avec 16 joueurs ; aucune autre boucle par image |
| Réseau entrant par client | ≤ 8 Ko/s en moyenne ; pic < 40 Ko/s (arrivée) |
| Mémoire client | < 900 Mo (console développeur) |
| DataStores | Sauvegarde automatique 90 s ; écritures des classements groupées par minute |

**StreamingEnabled** (réglages du projet : `StreamingMinRadius = 64`, `StreamingTargetRadius = 512`). Les squishies et les créatures ne dépendent pas du streaming (dessinés par le client à partir des données). Place, panneaux des ranchs et statue en `ModelStreamingMode = Persistent`. Les ranchs lointains peuvent sortir du rayon : seule la silhouette (client) reste. Rien ne dépend des personnages des autres joueurs (positions des créatures et des événements calculées par `SeededPath` et `EventClock`).

### 12.10 Tests et portes de qualité

**Tests Lune** (`tests/specs/`, lancés par `./scripts/check.sh` avec StyLua, Selene, build Rojo et vérification de la place), avec le harnais déjà présent (`tests/harness` : `Harness`, `Bots`, `Gamepad`, `Layout`, `ApiAudit`, `Wire`, `Services`) :

| Fichier | Couvre |
|---|---|
| `Format.spec` | Nombres géants EN/FR de 0 à 1e36, troncature, séparateurs, `NaN`/infini refusés |
| `SizeScale.spec` | 1 → 1×, 1e6 → 4,6×, plafonds 4 / 6 / 19 |
| `Formulas.spec` | Croissance, revenu, pression, coûts × 2^R, objectifs, hors ligne, intégrale exacte du Pot ; invariants (jamais négatif ni `NaN`) |
| `Odds.spec` | Chaque table somme à 100 ; 1 000 000 tirages à ±1 % des chances ; nouveauté garantie ; protections Rare 40 / Épique 150 ; familles débloquées ; Secrets et Lune ; « 1 sur X » |
| `FusionRules.spec` | Jumeaux, (a+b)×1,25, étoiles max 5, meilleure mutation, chaînes jusqu'à ×5 et ×6 (Axolo), Bassin plein |
| `RushRules.spec` | Chaque ligne du §4.21.4 isolée et combinée ; récompenses des 3 issues ; plafonds journaliers |
| `MegaRules.spec` | Objectif pour N = 1 à 16, indulgence, paliers |
| `EventClock.spec` | Instants clés (§12.4), séances de Lune, écart de 20 s entre spectacles |
| `SeededPath.spec` | Déterminisme, vitesse, jamais hors du graphe, jamais dans un ranch, 25 s au plus |
| `PressTiming.spec` | Fenêtre PERFECT, `tClient` borné |
| `Schema.spec` | Valeurs par défaut, `reconcile`, migrations depuis les sauvegardes-témoins |
| `Remotes.spec` | Chaque handler bombardé de charges malveillantes (`NaN`, ±inf, mauvais types, tables énormes, uid d'un autre joueur, débit excessif) → aucune mutation |
| `Economy.spec`, `Squishy.spec`, `Splorch.spec`, `Quest.spec` | Services sur un serveur simulé : dalles, Cuve, Bassin, vente, Dodo, Lettres, Grand Splorch et cadeaux, Étagère, Nourrir Plop, objectifs |
| `Rush.spec`, `Chase.spec`, `Mega.spec` | Rush complet à 16 joueurs simulés (`Bots`), modes, protections, Wild Wobblers, captures avec latence, MEGA |
| `MoveCheck.spec` | Repris de Comet, plus monture (22,4) et bond accordé |
| `EconomyPacing.spec` | **Simulation du §4.24 (porte bloquante)** |
| `Boot.spec` | Serveur complet de **16 joueurs simulés** pendant 30 min de temps simulé : arrivées, départs, morts, Rush, MEGA, Grands Splorch, fermeture |
| `ClientGame.spec` | Partie serveur enregistrée puis rejouée dans le vrai client, chaque panneau en anglais puis en français, arrivée en cours de partie |
| `Console*.spec` | Manette seule : tout atteignable, sélection qui ne s'échappe pas, glyphes PlayStation, textes ≥ 18 px, zone sûre, pas de fenêtre de chat, vibrations modérées |
| `Contract.spec` | Parité EN/FR de chaque clé et de ses variables ; provenance de chaque son ; identifiants de monétisation à 0 = articles cachés |
| `DataService.spec`, `MonetizationService.spec` | Repris, étendus au nouveau schéma (pannes de DataStore injectées, reprise du verrou, reçu rejoué) |

**Tests dans Studio** (plan manuel avant publication, §18) : rendu, physique, vrais DataStores, vrais achats, 16 vrais joueurs sur un Android modeste, textes FR, particules, téléphone en main, PS5 à 3 m, écoute de chaque son.

### 12.11 Budget de lignes et ligne de coupe

| Bloc | Estimation |
|---|---|
| Base reprise de Comet (données, monétisation, réseau, utilitaires, console, UI de base) | ≈ 4 000 lignes (à adapter) |
| Shared (logique et configuration) | ≈ 2 500 |
| Serveur (14 services) | ≈ 4 500 |
| Client (rendu, contrôleurs, HUD, panneaux) | ≈ 5 000 |
| **Total jeu au premier passage** | **≈ 12 000 nouvelles lignes** (hors base reprise et hors tests ; prévoir beaucoup plus après la QA) |

**Ligne de coupe** (retirée dans cet ordre si le calendrier dérape) : aperçu 3D des tenues (remplacé par une image fixe dessinée en Frames), classements mondiaux (on garde le tableau du serveur), badges d'étoiles du Squishydex, applaudissements, pet-sitting, clips automatiques, fanfares de records, Prairie des adieux (relâcher seulement par le menu). **Jamais coupé** : grandir, presser et PERFECT, Cuve, Bassin et combos, créatures en fuite et Golden, monture, BOOP RUSH avec ses protections et son interrupteur, Wild Wobblers, MEGA SQUISH, jauge, Grand Splorch et Étagère, Jelly Moon, Nourrir Plop, objectifs, mode Cozy, couche console.

---

## 13. Sécurité des enfants

| Règle | Comment |
|---|---|
| **Mode Rush ou Cozy, choisi par chaque joueur** | Carte au premier Rush, Cozy si pas de réponse en 20 s ; seuls deux joueurs en mode Rush peuvent se booper ; changeable à tout moment (§4.21.1) |
| **Serveurs privés en Cozy par défaut** | Le propriétaire peut autoriser le Rush (§6.10) |
| **On n'entre jamais chez les autres** | Clôture solide, portail de gelée, poussée du serveur à chaque tick (§6.3). Le Rush se joue par-dessus la clôture et en ville |
| **Le propriétaire gagne toujours** | Fame, pièces, taille en plus ; l'original revient toujours ; le gagnant reçoit une copie bébé (§4.21.3) |
| **Rien n'est jamais perdu** | Pas de vol, pas de base pillable, Grand Splorch qui donne au lieu de prendre, Étagère à trophées, jours de Plop au total (jamais une série qui retombe) |
| **Protections du Rush** | Meilleur Ami jamais boopable, 2 fuites par ranch, 1 boop toutes les 20 s, propriétaire proche = 2 fois plus long, bouclier débutant de 15 min, Mythiques seulement pendant la Lune (§4.21.4) |
| **Cacher mon nom** | Bannières, classements, statue et panneau du ranch montrent « Squishy Fan #4821 » (§6.9) ; le nom de l'acheteur d'une Squish Party n'est montré que s'il le choisit |
| **Aucun texte libre** | Pas de nom de squishy à écrire, pas de champ de texte (pas de codes au lancement), pas de dépendance au chat ; fenêtre de chat coupée sur console ; 4 emotes illustrées |
| **Joueurs bloqués** | Règle souple : pas de boop entre deux joueurs dont l'un a bloqué l'autre (liste lue côté client) |
| **Ton** | Mignon, satisfaisant ; la Jelly Moon est « un peu étrange » (troisième œil mignon, gouttes, lueur), jamais effrayante ; aucune violence (un boop est une pichenette sur le nez, l'éternuement est un nuage pastel brillant, jamais de morve) ; pas de sang, pas de peur, pas de moquerie |
| **Classification visée : Minimal** | Questionnaire de maturité rempli avant le lancement et avant d'activer la console (§18) ; catalogues Roblox Kids et Select visés |
| **Argent** | Aucun hasard payant, aucune pub vidéo récompensée, aucun faux minuteur, aucune proposition d'achat dans les 10 premières minutes, prix clairs, `PolicyService` respecté (§8.1) |
| **Pause** | Carte « Plop a sommeil » après 60 min, sans pénalité ni récompense pour rester (§4.20) |
| **Partage** | Clips seulement si `IsContentSharingAllowed` ; le jeu ne partage jamais tout seul (§9.5) |
| **Mesure** | Départs dans les 2 min après un premier boop subi, comparés aux autres joueurs, dès le premier jour (§16.3, action au §16.4) |

---

## 14. Accessibilité

| Besoin | Réponse |
|---|---|
| Daltonisme | Rareté = couleur **et** forme de l'aura (§4.4) ; mutation = matériau **et** nom ; squishies en fuite = anneau **et** contour ; mode Rush ou Cozy = badge **et** dessin |
| Sensibilité au mouvement | Mouvement réduit (§9.1) ; jamais plus de 3 changements de couleur par seconde (Glitch) ; aucun flash répété |
| Lecture difficile, jeunes enfants | Aucun tutoriel écrit ; icônes, gestes de Plop, 4 mots au plus par consigne ; un seul bouton d'action |
| Jeu sans son | Tout retour est d'abord visuel ; musique et effets réglables séparément |
| Motricité | Jouable à une main au téléphone (joystick + bouton Action) ; maintiens limités au boop (2,5 s), à Nourrir Plop (5 s) et à la confirmation du Grand Splorch (1,5 s) ; **aucun geste précis obligatoire** (le PERFECT est un bonus, jamais un échec) ; fusion au menu sans glisser-déposer ; cibles ≥ 56 px réels |
| Stress de la compétition | Mode Cozy, serveurs privés en Cozy, bouclier débutant, Golden « course amicale » |
| Appareils modestes | Graphismes légers, niveaux de détail, budgets du §12.9 |
| Téléviseur et manette | Interface proportionnelle (1,5 en 1080p), textes ≥ 27 px réels, zone sûre de 5 %, glyphes de l'appareil, tout à la manette sans curseur, vibrations modérées et désactivables, pas de fenêtre de chat (§10.6) |

---

## 15. Localisation (anglais et français)

- **Détection** : `Localization.languageFor(player.LocaleId)` (module repris) : `fr-*` → français, sinon anglais. Le réglage « Langue » (Auto / English / Français) passe avant.
- **Toutes les chaînes** dans `Shared/Localization/Strings.luau`, clés `domaine.nom`, variables `{n}`. Anglais **et** français écrits à la main ; un test vérifie la parité des clés et des variables (`Contract.spec`). Les autres langues : affichage anglais avec `AutoLocalize = true` (traduction automatique de Roblox) ; l'interface très illustrée limite la dépendance au texte.
- **Consignes et glyphes** : une consigne ne cite jamais une touche dans une phrase ; le glyphe est posé **à côté** d'un mot court (□ + « Presser »), ce qui marche dans les deux langues et sur toutes les manettes.
- **Nombres** : §4.2 (suffixes et séparateurs propres à chaque langue).
- **Longueur** : le français est ≈ 25 % plus long. Chaque texte a `TextScaled` + `UITextSizeConstraint` ; chaque écran est vérifié en français au plus petit téléphone (568 × 320) sans passer sous 18 px (leçon de Comet : prévoir des libellés français courts dès le départ).

| EN | FR |
|---|---|
| Raise a Squishy, Wobbleton, Plop, noms d'espèces, BOOP RUSH, MEGA SQUISH, Grand Splorch, Squishydex, Jelly Moon, Golden Wobbler, Wild Wobbler, Wobble Party, Squish Party, Fame | identiques (noms propres) |
| Coins / Press / SPLORCH! / PERFECT! | Pièces / Presser / SPLORCH ! / PERFECT ! |
| Snack Mat / Jelly Vat / Fusion Pool / Coin Pot / Jelly Fountain | Tapis à Goûter / Cuve à Gelée / Bassin de Fusion / Pot à Pièces / Fontaine de Gelée |
| Pens / Dodo Box / Mailbox / Trophy Shelf | Enclos / Boîte à dodo / Boîte aux lettres / Étagère à trophées |
| Pick up / Throw / Put down / Catch / Leap / Ride / Boop | Prendre / Lancer / Poser / Attraper / Bondir / Monter / Booper |
| Best Friend / Mount / Saddle / Outfit | Meilleur Ami / Monture / Selle / Tenue |
| Rush mode / Cozy mode / Newcomer shield | Mode Rush / Mode Cozy / Bouclier débutant |
| Server meter / Daily goals / Feed Plop / Day 42 | Jauge du serveur / Objectifs du jour / Nourris Plop / Jour 42 |
| Achoo! / HERO! / So close! | Atchoum ! / HÉROS ! / Presque ! |
| Common / Uncommon / Rare / Epic / Legendary / Mythic / Secret | Commun / Peu commun / Rare / Épique / Légendaire / Mythique / Secret |
| Jelly / Neon / Frosted / Golden / Galaxy / Rainbow / Lunar / Glitch / Flop | Gelée / Néon / Givré / Doré / Galaxie / Arc-en-ciel / Lunaire / Glitch / Flop |

---

## 16. Analytics

Tout passe par `Server/Util/Analytics` (repris, appels protégés par `pcall`). Trois champs personnalisés pour segmenter : `inputType` (tactile / clavier / manette), `serverBand` (1-5, 6-10, 11-16 joueurs), `sessionBand` (1re session, 2-5, 6 et plus).

### 16.1 Entonnoir d'accueil (`LogOnboardingFunnelStepEvent`)

| Étape | Nom | Déclencheur |
|---|---|---|
| 1 | Loaded | Profil chargé, personnage dans son ranch |
| 2 | FirstPress | Première pression |
| 3 | FirstTile | Premier achat (Tapis à Goûter) |
| 4 | VatBuilt | Jumeau de Plop né |
| 5 | FirstFusion | Première fusion |
| 6 | FirstPot | Premier encaissement du Pot |
| 7 | FirstCatch | Première créature attrapée |
| 8 | FirstPull | Premier vrai tirage de la Cuve |
| 9 | FirstRide | Première balade (selle) |
| 10 | Objectives | Panneau des objectifs du jour vu (≈ 5:00) |
| 11 | FirstSplorch | Premier Grand Splorch |

### 16.2 Économie (`LogEconomyEvent`)

| Flux | Monnaie | `itemSku` | Type de transaction |
|---|---|---|---|
| Source | Coins | `Pot` (cumulé, un événement par tranche de 5 min), `Press`, `Combo`, `Sell`, `Offline`, `Golden`, `Mega`, `RushHero`, `RushReturn`, `SplorchGift`, `PetSit`, `Clap`, `Objective_<id>`, `Product_<clé>` | Gameplay, TimedReward, Onboarding, IAP |
| Puits | Coins | `Tile_<dalle>_<niveau>`, `CozyBed` | Shop |

### 16.3 Événements personnalisés (`LogCustomEvent`)

| Événement | Valeur | Question |
|---|---|---|
| `RushModeChosen` | 1 Rush / 0 Cozy / −1 sans réponse | Combien choisissent le Rush ? |
| `FirstBoopReceived` | Secondes de jeu cumulé | Quand le premier boop arrive-t-il ? |
| `PostBoopQuit` | Secondes entre le premier boop subi et le départ (si < 120) | **Indicateur de frustration n° 1** |
| `QuitBaseline` | 1 par départ d'un joueur qui n'a pas été boopé dans les 2 dernières min (même tranche de temps de jeu) | Référence pour comparer `PostBoopQuit` |
| `BoopDone`, `EscapeOutcome` | 1 ; 0 propriétaire / 1 autre / 2 personne | Équilibre de la poursuite |
| `RushCatchByInput` | 1 par capture, segmenté par `inputType` | Le tactile est-il désavantagé ? |
| `MegaResult` | 1 réussite / 0 échec, avec N | Calibrage de l'objectif |
| `GaugeFilled` | Minutes depuis la dernière fois | Calibrage de la jauge |
| `SplorchReached` | R et minutes depuis le précédent | Rythme réel contre §4.24 |
| `ComboLength` | n | Les combos sont-ils compris ? |
| `HatchRarity`, `MutationGot` | Rareté ; mutation | Tables réelles contre affichées |
| `RideStart` | Secondes de jeu | La monture est-elle trouvée ? |
| `PetSitPress`, `FriendsOnServer` | 1 ; nombre d'amis | Jeu entre amis |
| `ShopOpened`, `ShopHiddenByPolicy` | 1 | Effet de `PolicyService` |
| `MoveViolation` | Nombre d'infractions dans la session | Faux positifs de l'anti-triche |
| `ServerFullKick` | 1 | Taille du serveur mal réglée ? |
| `SleepyCardShown` | 60 ou 120 | Sessions très longues |
| `SessionLength` | Minutes (au départ) | Durée de session |

### 16.4 Seuils d'alerte et actions (par la configuration, sans nouvelle version)

| Signal | Seuil | Action |
|---|---|---|
| `PostBoopQuit` comparé à `QuitBaseline` | > 1,5 fois après une semaine de mesures (seuil à confirmer avec ces mesures) | Premier boop subi seulement après 30 min de jeu (bouclier allongé), puis si besoin `Features.BoopRush = "events"`. Le Grand Splorch porte alors le côté viral. Plan B : les mécaniques de Stack a Squishy (jury §9) |
| Part en mode Rush | < 30 % | Revoir la carte du choix (dessins, ordre) ; montrer un clip de Rush pendant l'accueil |
| Réussite du MEGA | < 65 % ou > 92 % | Coefficient 50 par joueur ± 10 |
| Médiane du premier Grand Splorch | hors 12-15 min | `Balance.Splorch.Targets[1]` |
| Perte entre les étapes 2 et 3 de l'accueil | > 10 % | Raccourcir le chemin vers le Tapis, renforcer le geste de Plop |
| Écart de captures tactile / clavier | > 25 % | Rayon de capture 5 → 6 studs pour **tous** (jamais un bonus déclaré par le client) |
| `MoveViolation` chez des joueurs honnêtes | > 1 % des sessions | Marge de `MoveCheck` 1,5 → 1,8 |

---

## 17. Lancement et « Plus tard »

### 17.1 Au lancement (samedi 12 décembre 2026, costume d'hiver)

- **Monde** : Wobbleton, 16 ranchs, construits en code ; costume « Frost & Sprinkles ».
- **Boucle** : grandir, presser + PERFECT et séries, Pot, dalles, Cuve à Gelée (tables, protections, nouveauté garantie), Bassin de Fusion et combos, créatures en fuite personnelles et Golden Wobbler, monture et bond.
- **Social et événements** : BOOP RUSH (mode Rush/Cozy, interrupteur), Wild Wobblers, bouclier débutant, démonstration de Plop, MEGA SQUISH, jauge du serveur et Wobble Party, Grand Splorch et ses cadeaux, applaudissements, Étagère à trophées, Jelly Moon (4 séances le samedi, rattrapage le dimanche), Flop Plop, ranchs voisins, bonus d'amis, pet-sitting, emotes, 5 classements de la semaine, nom caché.
- **Rétention** : Nourrir Plop (jours au total), objectifs du jour, Squishydex et bonus de famille, carte « Plop a sommeil », écran de retour.
- **Monétisation** : 4 passes et 3 familles de produits du §8, sans publicité, PolicyService.
- **Technique** : schéma v1 avec champs réservés, couche console, anti-triche, analytics, EN/FR, Mouvement réduit, Graphismes légers.

### 17.2 Plus tard (janvier et février 2027) : liste courte et crochets à laisser dès le lancement

| Quand | Fonction | Crochets que le code de lancement doit laisser |
|---|---|---|
| Janvier | **Jelly Ascend** (2e prestige après 10 Grands Splorch) | Champ `ascend = 0` ; interrupteur `Features.JellyAscend = false` ; l'aperçu du Grand Splorch a une ligne réservée (cachée) |
| Janvier | **Saison de 28 jours** et sa piste premium décorative (≈ 399 R$) | Champ `season` ; `Features.Season = false` ; clé `SeasonPass` à 0 dans `Monetization` (cachée) |
| Janvier | **Lignée de Fame complète** et son tableau | Champ `fameLineage` ; `Features.FameLineage = false` ; au lancement, Fame créditée seulement si le propriétaire est présent (§4.18) |
| Janvier | **Gelée lente** (fournées de 1, 4 ou 12 h, hors ligne, meilleures raretés, jamais accélérée contre de l'argent) | Champ `slowJelly` (horodatages `Clock.unix()`) ; `Features.SlowJelly = false` ; un emplacement de dalle réservé à côté de la Cuve |
| Janvier | **Espèces Duo et colis** entre amis | Champ `duo` dans chaque ligne d'espèce ; champ `parcels` ; `Features.Duo` et `Features.Parcels = false` ; aucun échange au lancement |
| Janvier | **World First et énigme du lundi** | Champ `recipe` dans chaque ligne d'espèce ; champ `worldFirst` ; `Features.WorldFirst = false` ; sujet `MessagingService` « WorldFirst » réservé |
| Janvier | **Costume galette des rois** (squishy « fève » caché) | Calendrier `Events.Costumes` (dates) ; `Features.Costumes` |
| Février | **Grande Gelée entre serveurs** (risque technique) | `Features.GreatJelly = false` ; rien d'autre au lancement |
| Février | **Semaines « Encore »** (retour d'espèces limitées) | Champs `limitedUntil` et `encore` dans les lignes d'espèces |
| Février | Costumes Saint-Valentin et printemps | Calendrier `Events.Costumes` |
| Chaque semaine après le lancement | Une nouvelle espèce | Champ `release` des lignes d'espèces (activation par la date) |

---

## 18. Checklist de lancement

**Portes de qualité (bloquantes)**
1. `./scripts/check.sh` vert : StyLua, Selene (0 erreur), tests Lune **dont `EconomyPacing`** (§4.24), build Rojo, vérification de la place.
2. `Boot.spec` : serveur de 16 joueurs simulés pendant 30 min de temps simulé, sans erreur.
3. Specs console vertes (`Console*.spec`) : tout atteignable à la manette, aucune fuite de sélection, glyphes PlayStation, textes ≥ 18 px, zone sûre, pas de fenêtre de chat.
4. Exercices DataStore : échec de chargement (rien n'est sauvegardé), arrêt du serveur (`BindToClose` sauvegarde tout), retour sur un autre serveur après une panne (rien de perdu), rejeu de `ProcessReceipt` (aucun double crédit).
5. Contre-audit anti-triche indépendant (« red team ») sur le Rush, les captures, le MEGA et le portail des ranchs.

**Tests manuels dans Studio et en ligne** (environ une journée, plus le test à 16)

| # | Test | Résultat attendu |
|---|---|---|
| M1 | Première session seul, 5 min, sans rien lire d'autre que le jeu | Pression à 10 s, Tapis à 25 s, fusion à 1:00, capture à 2:00, monture vers 3:50 ; jamais deux consignes à la fois |
| M2 | Rendu : tour de la ville et des ranchs, un Rush, un MEGA, une Jelly Moon (horloge avancée), Graphismes légers | Pastel lisible, raretés reconnaissables par la couleur **et** la forme, rien qui clignote |
| M3 | Physique : portails (propriétaire et intrus), bords du plateau, monture, bond | L'intrus rebondit, personne n'entre, retour sur le plateau après une chute |
| M4 | Vraies sauvegardes : jouer, quitter, revenir, changer de serveur aussitôt, arrêter les serveurs | Rien de perdu, jamais de retour en arrière |
| M5 | Achats : chaque pass et produit (essais gratuits), puis un vrai petit achat en privé | Effet reçu une fois ; pass gardé après un Grand Splorch ; Squish Party pour tout le serveur ; nom caché par défaut |
| M6 | **16 vrais joueurs** pendant 30 min, dont un Android modeste | ≥ 30 images/s en permanence, mémoire < 900 Mo, aucune erreur |
| M7 | Textes en français et en anglais, du plus petit téléphone (568 × 320) à la 4K | Rien de coupé ni sous 18 px ; nombres au format de la langue |
| M8 | Particules : Grand Splorch, MEGA, naissance Secret, flocons d'hiver | Beaux, lisibles, budget tenu |
| M9 | Téléphone en main, à une main, 15 min | Bouton Action au pouce, rien sous le joystick |
| M10 | Poursuite avec 250 ms de latence simulée | Les captures accordées correspondent à ce que voit le joueur (≤ 6,5 studs) |
| M11 | Manette dans Studio, puis **vraie PS5 à 3 m** (télés de 43 et 55 pouces) | Tout à la manette, tout lisible, rien de coupé, vibrations modérées |
| M12 | **Écouter chaque son** (d'abord ceux remplis en dernier) | Agréables, pas trop forts, `Sneeze` drôle et doux ; un son qui déplaît est vidé (jeu jouable en silence) |
| M13 | Session de 60 min à plusieurs | Aucune erreur, pas de ralentissement, carte « Plop a sommeil » à 60 min |
| M14 | Un enfant de 8-10 ans accompagné joue un Rush en mode Rush puis en mode Cozy | Il comprend le choix, rit pendant la poursuite, ne se sent pas volé |

**Réglages de publication** (propriétaire)
- Taille du serveur **16** (Creator Hub) et `Players.MaxPlayers = 16` dans le projet ; remplissage maximal, une place réservée aux amis.
- Questionnaire de maturité (cible Minimal) ; langues EN et FR ; traduction automatique activée ; console activée **seulement après** M11.
- Créer les passes et produits, coller leurs identifiants, vérifier la Boutique (script de prépublication repris de Comet).
- Administrateurs LiveOps (`Data/Admins.luau`).
- *Experience Event* de la Jelly Moon déclaré pour le samedi.
- Icône et vignettes capturées en jeu (commande de développement « Photo ») ; test d'icône Raise a Squishy contre Squishy Ranch.
- **Recherche de nom et de marque** : « Raise a Squishy », « Squishy Ranch », « Plop », « Wobbleton », noms d'espèces (y compris contre Squishmallows).
- Date de repli : si une porte n'est pas verte le 10 décembre, sortie le **samedi 9 janvier 2027** avec le costume galette des rois.

---

## 19. Risques et parades

| # | Risque | Probabilité / impact | Parades | Indicateur |
|---|---|---|---|---|
| 1 | **Le BOOP RUSH semble être du vol** pour les plus jeunes | Moyenne / fort | Mode choisi des deux côtés, Cozy par défaut sans réponse, boop par-dessus la clôture, propriétaire gagnant, Meilleur Ami protégé, bouclier de 15 min, interrupteur `"events"` / `"off"` | `PostBoopQuit` contre `QuitBaseline` (§16.4) |
| 2 | **Économie déséquilibrée** (inflation par les bébés et les fusions, ou blocage) | Moyenne / moyen | Taille des bébés ≤ 2 × le plus gros, plafonds journaliers, récompenses en secondes de revenu, simulation bloquante, tables en configuration | Médianes du §4.24, `SplorchReached` |
| 3 | **Calendrier serré** (6 semaines) | Forte / fort | Base de Comet reprise, ligne de coupe (§12.11), date de repli du 9 janvier | Portes du §18 |
| 4 | **Performance au téléphone** : 16 ranchs, 384 squishies animés | Moyenne / fort | Rendu client, niveaux de détail, 80 animés au plus, `BulkMoveTo`, budgets du §12.9, Graphismes légers, test M6 | Images/s par appareil |
| 5 | **Litiges « je l'ai attrapé ! »** avec la latence | Moyenne / moyen | Trajets déterministes identiques client/serveur, tolérance de 1,5 stud, effets seulement après confirmation, test M10 | Captures par type d'entrée |
| 6 | **Serveurs peu peuplés** sans poursuite | Moyenne / moyen | Wild Wobblers (jusqu'à 13), démonstration de Plop, Golden, MEGA réussissable seul (objectif 80 pour 1 joueur) | `serverBand`, rétention par tranche |
| 7 | **Noms non vérifiés** (titre, Plop, Wobbleton, espèces) | Inconnue / fort | Recherche Roblox et marques avant publication ; titre de secours Squishy Ranch | Checklist §18 |
| 8 | **Formes simples moins belles** que des modèles 3D | Moyenne / moyen | Direction artistique forte (pastel, écrasement, rebond), test d'icône tôt | Taux de clic sur l'icône |
| 9 | **Copies en 2 à 6 semaines** | Forte / moyen | Une espèce par semaine en données, mascotte forte, progression (Fame, Étagère, jours de Plop) gardée dans la sauvegarde | Joueurs simultanés |
| 10 | **Classification** : le côté étrange de la Lune | Faible / fort | Rester mignon ; questionnaire avant le lancement | Note reçue |
| 11 | **Dérive des règles de Roblox** (hasard payant, publicités, Kids/Select) | Faible / fort | Aucun hasard payant, `PolicyService`, aucune publicité, revue à chaque version | Revue mensuelle |
| 12 | **Faux positifs de l'anti-triche** | Moyenne / moyen | Signaler avant de ramener, gel de 1,5 s toléré, ton neutre, exclusion des classements limitée dans le temps | `MoveViolation` |
| 13 | **Sons manquants ou désagréables** (bibliothèque officielle limitée) | Moyenne / faible | Jeu jouable en silence, écoute obligatoire (M12), replis documentés (§9.6) | Retours des testeurs |
| 14 | **Part des joueurs console inconnue** (~3 %, exercice 2024) | Certaine / faible | La PS5 est un atout de qualité, pas une promesse de trafic ; aucun effet propre à la DualSense | `inputType` |
| 15 | **Plafond de revenus** d'une monétisation juste | Certaine / moyen | Assumé : fidélité d'abord ; Squish Party sociale ; Creator Rewards | ARPDAU |

---

## 20. Questions ouvertes pour le propriétaire

1. **Titre** : Raise a Squishy ou Squishy Ranch, après la recherche de nom et de marque et le test d'icône ?
2. **Suffixes français des grands nombres** : la version correcte en français (k, M, Md, Bn, Bd…) choisie ici, ou les suffixes internationaux (K, M, B, T…) que beaucoup d'enfants voient déjà dans les jeux Roblox ? Un petit test avec des enfants français aiderait.
3. **PolicyService** : dans les pays où `ArePaidRandomItemsRestricted` est vrai, nous cachons les Paquets de pièces **et** le pass ×2 Pièces **et** la Squish Party (règle la plus prudente, §8.1). Préférez-vous ne cacher que les Paquets de pièces (achat direct de monnaie) ?
4. **Classement « Plus gros squishy »** : il sera dominé par les joueurs anciens. Garder tel quel, ou le remplacer par « Plus forte croissance de la semaine » (taille gagnée en proportion) ?
5. **Squish Party** : 99 R$, 10 min, un achat toutes les 20 min par joueur, nom caché par défaut. D'accord ?
6. **Jelly Moon de 22:00 UTC** (23 h à Paris) : la garder pour les Amériques, ou la remplacer par une séance à 14:00 UTC ?
7. **Clips automatiques** (capture vidéo des moments rares) activés par défaut, ou désactivés par défaut ?
8. **Cadeaux du Grand Splorch** : tout le monde les reçoit (réglage pour refuser). Faut-il les limiter aux joueurs qui étaient sur la place, pour encourager à venir voir ?
9. **Pet-sitting** : réservé aux amis Roblox (choix actuel), ou ouvert à tous les joueurs du serveur ?
10. **Wild Wobblers** sur les grands serveurs : 3 par Rush pour les joueurs Cozy. Assez, ou en faut-il plus pour qu'ils s'amusent autant ?
11. **Meilleur Ami qui suit le joueur en ville** : d'accord sur le principe (charge de rendu : 16 créatures en plus) ?
12. **Date** : confirmez-vous la règle « sortie le 12 décembre seulement si toutes les portes du §18 sont vertes le 10 décembre, sinon le 9 janvier » ?

---

## Annexe A. Écarts décidés par rapport au concept du jury (§8)

Détails et justifications du concept : [`03-decision-du-jury.md`](03-decision-du-jury.md).

| Point du concept | Décision de ce GDD | Pourquoi |
|---|---|---|
| Une goutte de Cuve toutes les 45 s au début | **90 s** au niveau 0, jusqu'à 17,7 s avec la dalle Vitesse | Avec 45 s, le joueur aurait 6 squishies à 5:00 au lieu de 3-4 (cible du jury) ; la simulation tient la cible avec 90 s |
| Selle à la taille 100 vers 4:00 | **Selle à 1 200** | Avec +1/s, le Tapis et la fusion de 1:00, Plop dépasse 100 avant 1:00 ; 1 200 tombe vers 3:50 |
| Jauge du serveur = somme des tailles | **Jauge = actions de tous** (§4.23) | Avec des tailles de 1 à 1e30, un vétéran la remplirait seul et un débutant n'y compterait jamais |
| Rush à :00, :10… et MEGA à :00, :30 | **Rush à :05, :15… ; MEGA à :20, :50 ; Golden à :00:30, :10:30, :30:30, :40:30** | Un seul grand spectacle à la fois avec 20 s d'écart (greffe n° 9) |
| « La croissance est doublée pour toujours » | Croissance × 2 par Grand Splorch, **objectif × 2,7** par niveau | Avec un objectif × 2, les boucles raccourciraient sans fin ; × 2,7 donne R = 9 au jour 7 et R = 17 au jour 28 |
| Le rebirth remet à zéro « les constructions » | Tapis, décorations et Cuve repartent de zéro ; **les places d'enclos et le Lit douillet sont gardés** | Perdre des places ferait dormir des squishies : ressenti de perte, contraire au pilier P2 |
| Revenu = … × rebirth × Fame | R agit par la croissance (donc la taille) ; Fame est un bonus additif plafonné à +300 % | Éviter de compter le rebirth deux fois et l'inflation |
| Hors ligne 8 h (12 h avec des pièces) | Croissance hors ligne à 50 %, Pot à 25 %, 8 h ; 12 h avec le **Lit douillet** (250 000 pièces, gardé pour toujours) | Le hors ligne à 100 % rendait chaque retour égal à un Grand Splorch immédiat ; un achat en pièces doit survivre au rebirth |
| Squishydex « 26 × 9 = 234 entrées » | 26 pages d'espèces + **234 entrées de mutation** + 130 badges d'étoiles | Les 9 mutations comptent toutes ; la forme normale est la page de l'espèce |
| Premier tirage au hasard pendant l'accueil | Hasard réel, avec « **Nouveauté garantie** » sur les 3 premiers tirages (espèce, jamais la rareté) | Éviter une fusion de plus à 5:00 et donner une découverte sans truquer les chances affichées |
| Prix des passes « 249-299 » | ×2 Pièces à **249 R$** | Palier courant ; ajustable par les prix gérés de Roblox |
| Codes promo (non cités au lancement) | **Pas de codes au lancement** | Aucun champ de texte libre (sécurité des enfants) ; à revoir plus tard |
| Exclusion des classements par l'anti-triche | **Limitée dans le temps** (fin de la semaine suivante) | Question laissée ouverte par Comet Conga (rapport qualité §6.3.7) : on évite une punition à vie pour un mauvais réseau |
