# Comet Conga — Game Design Document

> **Document 02 : conception du jeu (GDD).** Version 1.0 du 30 octobre 2026. Statut : validé pour la production du MVP.
> Documents liés : [`01-analyse-marche.md`](01-analyse-marche.md) (étude de marché, citée ci-dessous « Rapport §x ») et [`03-decision-du-jury.md`](03-decision-du-jury.md) (concepts comparés, notes, idées greffées, défauts corrigés).
> **Règle de lecture.** Chaque chiffre de ce document est une valeur de départ, à placer telle quelle dans les modules `Shared/Config/*`. Les valeurs d'économie sont validées par la simulation Lune décrite au §4.18 ; elles peuvent ensuite être ajustées par les données, sans toucher au code.

**Conventions**
- Distances en *studs*. Temps en secondes (s), minutes (min) ou heures (h). Horaires en **UTC**.
- `floor` = arrondi à l'entier inférieur. Les monnaies sont toujours des entiers côté serveur.
- Les noms propres de l'univers (Comet Conga, Nebbies, Lumora, Nest, Gloomwisp, Supernova, Starforge…) restent en anglais dans les deux langues : c'est notre propriété intellectuelle. Les mots du quotidien sont traduits (§13).
- Clé technique entre crochets, par exemple [`Balance.Snip.Radius`], quand une valeur doit vivre en configuration.

**Glossaire**

| Terme | Sens |
|---|---|
| **Nebby** (pl. Nebbies) | Bébé comète, la créature à collectionner |
| **Conga** | La file de Nebbies qui suit le joueur |
| **Lead Trio / Guard Links** | Les premiers Nebbies de la file, jamais coupables (3 au départ, jusqu'à 8) |
| **Snip** (coupe) | Un joueur traverse la file d'un autre et en détache la queue |
| **Parade** | Encaissement : le joueur passe la porte de son Nid avec sa file |
| **Nest** (Nid) | La base personnelle : perchoirs, réserve, observatoire. Jamais pillable |
| **Glow** | Monnaie principale (revenus de parade et revenu passif) |
| **Stardust** | Monnaie secondaire (fusion Starforge) |
| **Supernova** | Renaissance (prestige) |
| **Star Atlas** | Livre de collection |
| **Gloomwisp** | Petite boule d'ombre (adversaire non joueur) qui grignote les files sur les serveurs peu peuplés |
| **Port sûr** | Zone de 25 studs autour de chaque porte de Nid où l'on ne peut pas couper |

---

## 0. Fiche d'identité

| Élément | Valeur |
|---|---|
| Titre | **Comet Conga** (à confirmer par une recherche de nom et de marque, voir §16) |
| Accroche | « Attrape des bébés comètes, mène la plus longue conga lumineuse du ciel… et ne te fais pas couper ! » |
| Genre | Simulation : collection + revenu passif + améliorations + renaissance, avec course-poursuite non violente et événements de serveur coopératifs |
| Joueurs | **12 par serveur** (MaxPlayers = 12), 12 Nids |
| Plateformes | Mobile d'abord (≈ 80 % des joueurs, Rapport §2.4), PC, manette (console) |
| Contrôles | Joystick + **un seul bouton d'action : Dash**. Saut par défaut Roblox |
| Classification visée | **Minimal** (au pire Mild) au questionnaire de maturité ; éligible aux catalogues Kids et Select |
| Session cible | 15 à 30 min (le cycle d'événements de 10 et 30 min tire la session au-delà du seuil de 10 min des Creator Rewards) |
| Public | 9-17 ans au cœur, satisfaisant pour les 18+ ; lisible pour les moins de 13 ans |
| Monétisation | 6 game passes et 6 produits développeur **déterministes** ; aucun objet aléatoire payant |
| Code | ≈ 8 000 lignes de Luau `--!strict` (≈ 5 600 nouvelles + base réutilisée), Rojo, sans travail manuel dans Studio |
| Contenu au lancement | 30 espèces × 5 formes = 150 entrées d'Atlas (+60 badges Doré/Géant), 1 île, 3 zones, 4 météos à mutation + 1 météo d'abondance, 4 événements récurrents |

---

## 1. Vision, pitch, piliers, public, positionnement

### 1.1 Pitch

**Pitch court (store, 1 phrase).** Sur Lumora, une île flottante au crépuscule, des bébés comètes tombent du ciel : marche dessus, ils te suivent en file lumineuse ; ramène la plus longue conga possible jusqu'à ton Nid… avant qu'un autre joueur ne te la coupe.

**Pitch long.** Comet Conga est un jeu social de collection et de poursuite pour 12 joueurs. Toucher un Nebby suffit à l'attraper : il saute dans la file derrière toi, sans aucun bouton. Plus la file est longue, plus le **Conga Bonus** est gros quand tu la fais défiler à travers la porte de ton Nid. Là, les Nebbies se posent sur des perchoirs et produisent du Glow en continu, même hors ligne.

Le piquant : n'importe quel autre joueur peut traverser ta file et la **couper**. SNIP ! La queue se détache, les Nebbies s'éparpillent et tout le monde se rue dessus. Trois règles rendent ça juste : tes premiers Nebbies (le **Lead Trio**) ne sont jamais coupables, ton Nid ne peut **jamais** être pillé, et une coupe a un plafond. Tu ne perds que ce que tu portes à découvert : le seul vrai risque, c'est ta propre gourmandise.

Toutes les 10 minutes (à :00, :10, :20… UTC), une **Grande Comète** s'écrase au centre ; tout le serveur poursuit celui qui la porte, et la toucher la vole. Toutes les 30 minutes, l'île décrète une trêve, la **Nuit de la Balise** : tout le monde coopère pour allumer la Balise et déclencher une pluie d'étoiles. Les amis forment des **équipages** et escortent mutuellement leurs files comme des gardes du corps.

### 1.2 Piliers de design

Chaque fonctionnalité doit servir au moins un pilier ; tout ce qui n'en sert aucun est coupé.

| # | Pilier | Ce que ça impose |
|---|---|---|
| P1 | **Marcher, c'est jouer** | Le déplacement est l'unique entrée de gameplay. Capturer, couper, encaisser se font en marchant. Un seul bouton (Dash). Jouable à une main sur téléphone |
| P2 | **Tu ne perds que ce que tu portes** | Aucune perte de ce qui est encaissé. Le risque est choisi (rentrer maintenant ou pousser vers le Cratère). Protections lisibles : Lead Trio, port sûr, bouclier débutant, plafonds de perte |
| P3 | **Le serveur vit au même rythme** | Une horloge UTC commune : météo toutes les 6 min, Comète toutes les 10 min, Balise toutes les 30 min, Starfall Saturday chaque samedi. Chaque moment est visible de partout sur la carte |
| P4 | **Une collection profonde et lisible** | 7 raretés, formes météo, variantes Doré/Géant, étoiles de fusion. La rareté se lit à la couleur **et** à l'aura (daltoniens). Probabilités affichées |
| P5 | **Juste, fluide, sans bug** | Autorité serveur sur tout. Monétisation déterministe. Peu de systèmes, chacun poli. Ce que le joueur voit est ce que le serveur teste |

### 1.3 Public cible

Répartition des comptes à âge vérifié : 34 % de moins de 13 ans, 37 % de 13-17 ans, 29 % de 18 ans et plus (Rapport §2.2).

| Persona | Profil | Ce qu'il cherche | Ce que Comet Conga lui donne |
|---|---|---|---|
| **Léa, 10 ans**, téléphone, joue avec sa cousine | Courte attention, lit peu | Des créatures mignonnes, des récompenses fréquentes, ne pas se faire embêter | Capture sans bouton, récompense à 12 s, bouclier débutant toute la première session, Mode Zen, Nid jamais pillable |
| **Noah, 14 ans**, PC ou manette, joue avec ses amis | Compétitif, aime « troller » gentiment | Des poursuites, du skill, des moments à filmer | Coupes, Dash, Grande Comète « chat perché », escortes d'équipage, classement hebdomadaire de la plus longue parade |
| **Sam, 24 ans**, joue le soir | Collectionneur, optimise | Profondeur, objectifs longs | Atlas de 150 puis 216 entrées, chasse aux formes et variantes, Starforge ★5, Supernovas, rendez-vous du samedi |

### 1.4 Positionnement marché

| Constat du marché (Rapport) | Réponse de Comet Conga |
|---|---|
| La boucle « collecte → revenu passif → amélioration/renaissance + interaction sociale » a produit les records de 2025-2026 (Steal a Brainrot ~25 M CCU, Grow a Garden ~22 M, Steal An Egg ~14,3 M) (§1, §3.1) | On garde la boucle entière et on change le verbe social : **mener et couper des files** au lieu de piller des bases |
| Les clips d'enfants bouleversés par le vol de leur base font churner ; Spyder Games a attaqué au moins 4 imitateurs ; Grow a Garden 2 a perdu 91,5 % en 30 jours (§3.1, §3.3) | Pas de base pillable, pas de tapis roulant, pas de vol d'objets encaissés. Le frisson de la poursuite reste, la perte d'un objet rare déjà gagné disparaît |
| Les jeux mèmes s'effondrent en un mois ; il faut une IP originale (§1, §4.5) | Univers, créatures, noms et visuels 100 % originaux et générés en primitives |
| Les records viennent d'événements programmés et d'un jour de mise à jour fixe (§3.2, §5.4) | Horloge UTC commune à tous les serveurs + Starfall Saturday 16:00 UTC, une heure avant la mise à jour de 17:00 UTC |
| L'algorithme note la rétention sur 28 jours, l'abandon en première session et le jeu entre amis (§5.1) | Récompense à 12 s, bouclier débutant, crochets J1 / J2-7 / J8-28 distincts, équipages, bonus d'amis, serveurs privés gratuits |
| Coopération et tension légère sont le pilier montant ; viser Mild pour Kids/Select (§4.1, §9.1) | Nuit de la Balise (trêve coopérative), Gloomwisps mignons, aucune violence |
| Le chat demande une vérification d'âge (§7) | Toute la communication passe par les mécaniques, les équipages et une roue de 6 pings |
| Payeurs en baisse, régulateurs attentifs aux dark patterns (§5.5) | Achats à résultat connu, prix lus à l'exécution, aucun faux minuteur, aucun « presque gagné » |
| Mobile d'abord, téléphones bas de gamme (§6.1, §6.3) | Joystick + Dash, boutons ≥ 56 px, rendu client avec niveaux de détail, budget de pièces et de lumières |

**Ce que le jeu n'est pas.** Pas de tapis roulant d'achat, pas de base à défendre, pas de plantation, pas d'œufs payants, pas de mème. La file qu'on peut couper est une convention générique de jeu d'arcade (famille Snake / .io) : chez nous on ne grandit pas en mangeant, les collisions ne tuent pas et le terrain n'est pas une arène nue.

### 1.5 Objectifs chiffrés (KPI)

Repères GameAnalytics 2026 : médiane J1 10,3 % / J7 1,6 % / J30 0,5 % ; top 1 % ≈ 22 / 9 / 4,7 % (Rapport §5.3).

| KPI | Seuil de lancement | Objectif | Alerte |
|---|---|---|---|
| Rétention J1 | ≥ 15 % | 18-22 % | < 12 % |
| Rétention J7 | ≥ 5 % | 6-9 % | < 3 % |
| Rétention J30 | ≥ 2 % | 3-4,7 % | < 1 % |
| Session moyenne | ≥ 12 min | ≥ 15 min | < 10 min |
| Abandon avant la 1re parade | ≤ 10 % | ≤ 6 % | > 15 % |
| Taux d'abandon après coupe (quitte < 60 s après avoir été coupé) | ≤ 5 % des coupes subies | ≤ 3 % | > 8 % |
| Conversion payeurs | 1,5 % | 2-3 % | — |
| Jours de jeu entre amis (part des sessions avec un ami) | ≥ 15 % | ≥ 25 % | < 10 % |

---

## 2. Boucle de jeu

### 2.1 Boucle principale : les 4C (une course = 30 à 90 s)

```
          ┌──────────────────────────────────────────────────────────────┐
          │                                                              │
          ▼                                                              │
   ┌─────────────┐   marcher sur un Nebby    ┌─────────────┐              │
   │ 1. CATCH    │ ────────────────────────▶ │ 2. CONGA    │              │
   │ (capturer)  │    (aucun bouton)         │ la file     │              │
   └─────────────┘                           │ s'allonge,  │              │
          ▲                                  │ Bonus ×1,08 │              │
          │                                  │ par Nebby   │              │
          │  repartir                        └──────┬──────┘              │
          │                                         │  rentrer au Nid     │
          │                       risque : SNIP ! ◀─┤  (ou pousser plus   │
          │                       (queue perdue,    │   loin = plus de    │
          │                        mêlée générale)  │   bonus, plus de    │
          │                                         ▼   risque)           │
   ┌─────────────┐  Glow, Stardust            ┌─────────────┐             │
   │ 4. CLIMB    │ ◀───────────────────────── │ 3. CASH-IN  │             │
   │ améliorer,  │                            │ Parade à la │             │
   │ fusionner,  │                            │ porte du Nid│             │
   │ Supernova   │                            │ → perchoirs │─ revenu ────┘
   └─────────────┘                            │   (idle)    │  passif
                                              └─────────────┘  continu
```

1. **Catch.** Le joueur passe à moins de son rayon d'**Attrait** (5 studs au départ) d'un Nebby sauvage : le serveur l'attrape automatiquement s'il reste de la place dans la file.
2. **Conga.** Le Nebby rejoint la file, espacé de 2,6 studs. Le Conga Bonus monte de 0,08 par Nebby. Chaque Nebby au-delà des Guard Links ralentit de 0,4 % (max −15 %). La file est coupable au-delà des Guard Links.
3. **Cash-in.** Le joueur traverse la porte de son Nid : **Parade**. Glow = Σ valeurs × Conga Bonus × multiplicateurs. Les meilleurs Nebbies vont sur les perchoirs (revenu passif), le reste en réserve.
4. **Climb.** Le Glow paie 5 améliorations ; la Stardust paie les fusions Starforge ; la Supernova remet à zéro contre un bonus permanent.

**La décision centrale de chaque course :** encaisser 6 Communs en sécurité tout de suite (×1,40) ou pousser vers le Cratère pour une file de 20 (×2,52) pendant que 11 joueurs lorgnent ta queue.

### 2.2 Boucles secondaires

| Boucle | Durée | Contenu | But |
|---|---|---|---|
| **Cycle d'événements** | 6 / 10 / 30 min | Météo à mutation (2 min 30 toutes les 6 min), Grande Comète (toutes les 10 min), Nuit de la Balise (3 min toutes les 30 min) | Donner un rendez-vous toutes les quelques minutes, prolonger la session |
| **Boucle quotidienne** | 1 jour | Calendrier de connexion indulgent, 3 quêtes du jour, gains hors ligne, cadeau Duo entre amis | Habitude J2-J7 |
| **Boucle hebdomadaire** | 7 jours | Starfall Saturday, quête « Grand Défilé », classement hebdo de la plus longue parade (remise à zéro le lundi) | Pic de serveurs, rendez-vous |
| **Boucle de collection** | jours → semaines | Atlas (espèces × formes), badges Doré/Géant, Starforge ★2 à ★5, jalons (perchoirs, titres, traînées) | Profondeur J8-J28 |
| **Boucle sociale** | continue | Équipages, escorte, pings, acclamations de Supernova, Comète partagée | Co-play, signal de classement |

### 2.3 Méta-progression

| Couche | Horloge | Ce qui progresse | Remis à zéro par la Supernova ? |
|---|---|---|---|
| Course | 30-90 s | File, Conga Bonus | — |
| Améliorations | minutes | Longueur de conga, Foulée, Attrait | **Oui** |
| Nid | heures | Perchoirs, Guard Links | Non |
| Collection | jours | Nebbies possédés, étoiles Starforge, Atlas | Non |
| Prestige | jours → semaines | Supernova (+40 % de revenu chacune, +5 au plafond de file, Dash plus court, auras, constellation au-dessus du Nid) | — |
| Saison sociale | semaines | Classements, titres, Starborn de la semaine | Non |

### 2.4 Horloge commune (UTC, identique sur tous les serveurs)

Toutes les phases dérivent de `os.time()` côté serveur et de `workspace:GetServerTimeNow()` côté client, via le module pur `EventClock` (§12). Les joueurs apprennent le rythme : « comète à :00, :10, :20… ».

| Minute de l'heure | Événement |
|---|---|
| :00, :10, :20, :30, :40, :50 | **Grande Comète** (alerte 8 s avant, impact pile à la minute) |
| :02:00-:04:30, :08:00-:10:30, :14:00-:16:30… (toutes les 6 min) | **Fenêtre météo** de 150 s |
| :25:00-:28:00 et :55:00-:58:00 | **Nuit de la Balise** (trêve, objectif commun) |
| Samedi 16:00-16:20 UTC | **Starfall Saturday** (remplace le planning normal pendant 20 min) |
| Samedi 17:00 UTC | Publication des mises à jour |
| Lundi 00:00 UTC | Remise à zéro hebdomadaire (classement, quête Grand Défilé) |
| 00:00 UTC chaque jour | Remise à zéro quotidienne (quêtes, connexion, plafonds de Stardust) |

---

## 3. FTUE : les 5 premières minutes

**Règles.** Jamais plus d'une instruction à l'écran ; icônes plutôt que texte (4 mots maximum par consigne) ; une récompense ou un chiffre qui bouge au moins toutes les 15 s ; aucune fenêtre modale bloquante pendant les 60 premières secondes ; aucune coupe possible sur la file du joueur pendant toute la première session (bouclier débutant). Les étapes numérotées sont envoyées à `AnalyticsService:LogOnboardingFunnelStepEvent` (§14).

| Temps | Ce que voit et fait le joueur | Ce que fait le système | Étape funnel |
|---|---|---|---|
| Chargement | Écran de chargement construit en code (`ReplicatedFirst`) : un Nebby rebondit, 3 points animés, aucun texte long | Chargement du profil (verrou de session). En cas d'échec définitif : écran « Réessayer » amical, jamais de profil vide sauvegardé | — |
| 0,0 s | Le personnage apparaît **sur son propre Nid** (attribué automatiquement, à côté d'un ami s'il y en a un), tourné vers le centre | `NestService` attribue le Nid ; `RespawnLocation` = SpawnLocation du Nid | 1 « Chargé » |
| 0,0-1,5 s | Travelling caméra de 1,5 s : du ciel au-dessus du Nid vers le Cratère (on voit les files lumineuses des autres), retour derrière le joueur | Caméra `Scriptable` tweenée (`Sine InOut`) ; sautée si Mouvement réduit | — |
| 1,5 s | Contrôle rendu. Le HUD apparaît avec 3 éléments seulement : compteur de Glow (0), compteur de file (0/3), bouton Dash. 6 empreintes Néon s'allument une à une de la porte vers 3 **Puffkins de bienvenue** à 12 studs devant la porte | Les 3 Puffkins sont « personnels » (`onlyFor` = ce joueur, invisibles et non attrapables par les autres), placés dans le port sûr | — |
| 3-8 s | Le joueur marche dessus : pop, pop, pop. Chaque capture a tout le juice (§9). Au-dessus de sa tête : « Conga ×3 ! » puis « ×1,16 » | Captures décidées par le serveur (tick 10 Hz) | 2 « Première capture » |
| ~8 s | Les empreintes s'inversent et pointent vers la porte ; l'arche de la porte pulse en doré ; un faisceau (Beam) relie le joueur à la porte | — | — |
| ~12 s | Il traverse la porte : **PREMIÈRE RÉCOMPENSE**. Tampon « PARADE ×1,16 ! », « +69 », des pièces volent vers le compteur. Les 3 Puffkins sautent sur 3 perchoirs ; chacun émet un « +1 » par seconde | Parade : 3 × 20 × 1,16 = 69,6 → **69 Glow**. Revenu passif : **3 Glow/s** | 3 « Première parade » |
| ~14 s | L'icône **Améliorer** apparaît dans le rail de gauche (pop + pulsation) avec une main animée | Affichage progressif de l'interface (rail caché jusqu'ici) | — |
| ~18-22 s | Le joueur touche l'icône : le panneau s'ouvre sur **une seule carte en surbrillance** « Conga +1 · 50 ». Il achète : onde de choc au sol, une silhouette fantôme rejoint la file. Le panneau se ferme seul après 0,6 s | Coût Conga niveau 0 = 50 Glow ; plafond de file 3 → 4 | 4 « Première amélioration » |
| ~25 s | Le suivi de quête glisse à droite : icône file + « Parade de 4 » ; une flèche au sol vers le groupe de Nebbies le plus proche | Chaîne d'accueil Q1 (§7.4) | — |
| 30 s-1 min | Q1 « Parade de 4 » (+50 Glow) puis Q2 « Conga ×2 » (2 achats, plafond 6) | Le serveur garantit au moins 6 Nebbies Communs dans la Prairie à moins de 40 studs du Nid (apparition dirigée si besoin) | 5 « Parade de 4 » |
| 1-2 min | Q3 « Parade de 6 » (+150 Glow). Le joueur voit d'autres files se faire couper ; sa propre file porte une **bulle dorée** (bouclier débutant) et une icône bouclier près du compteur de file | Bouclier actif toute la première session (§4.16). Le joueur peut couper les autres : sa première coupe le rend fier | 6 « Parade de 6 » |
| 2-3 min | Q4 « Attrape un Rare » : un pilier bleu marque le Rare le plus proche dans la Clairière. S'il n'y en a aucun, un Rare personnel apparaît à 60-90 studs du centre | Apparition dirigée `onlyFor`, une seule fois par compte | — |
| ~3 min | Il encaisse son premier Rare : l'**Atlas** se débloque (page qui tourne, « 5/150 ») ; l'icône Collection rejoint le rail | — | 7 « Atlas débloqué » |
| 3-4 min | Q5 « Achète Foulée » (vitesse) : l'icône du bouton Dash pulse une fois pour montrer qu'il existe | — | 8 « Foulée achetée » |
| 3-5 min | Une fenêtre météo s'ouvre (au plus tard 3 min 30 après l'arrivée, garanti par l'horloge) : le ciel vire au vert-violet, bannière « Nebbies Aurora ×2 · 2:30 ». Q6 « Attrape un Nebby météo ». Si la Comète tombe pendant ces minutes, Q6 accepte aussi « Participe à la Comète » | — | 9 « Premier événement » |
| ~5 min | Le Nid affiche un anneau de progression vers la **Supernova (400 000 Glow)** ; le suivi de quête montre ce prochain objectif long | — | — |
| ~20-35 min | Première Supernova (cible de rythme, §4.18) | — | 10 « Première Supernova » |

**Bilan à 5 minutes** : 4 à 6 parades, 4 à 6 améliorations, au moins une coupe vue (sans en subir), au moins un événement de serveur vécu, 5 à 8 entrées d'Atlas, un objectif long visible.

**Cas particuliers**
- *Arrivée pendant une Nuit de la Balise* : la trêve est active, la chaîne d'accueil continue normalement (aucune coupe possible de toute façon).
- *Arrivée juste avant une Comète* : l'alerte s'affiche mais la quête Q6 n'est proposée qu'après Q3 ; la Comète reste un spectacle à regarder.
- *Serveur presque vide* : les Gloomwisps (§4.15.4) ne touchent pas une file sous bouclier ; le joueur les voit « grignoter » d'autres files ou passer, et peut les éclater pour de la Stardust.
- *Retour d'un joueur* (pas la première session) : écran de retour « Pendant ton absence : +X Glow » (§7.2), puis le HUD complet.

---

## 4. Systèmes détaillés

### 4.1 Monnaies

Deux monnaies seulement, chacune avec un rôle clair. Toutes deux sont des entiers gérés exclusivement par le serveur.

| Monnaie | Rôle | Sources | Puits | Remise à zéro |
|---|---|---|---|---|
| **Glow** | Progression de la partie en cours | Parades, revenu passif des perchoirs, gains hors ligne, quêtes, calendrier, Comète, Balise, Gloomwisps, codes, produits « Glow » | 5 améliorations, Supernova | Oui, à chaque Supernova |
| **Stardust** | Collection à long terme | Libération de Nebbies, coupes, Gloomwisps, Comète, Balise, quêtes, calendrier, acclamations, cadeau Duo, codes, produit « Bocal de Stardust » | Fusions Starforge (MVP) ; boutique de l'Observatoire (v1.1) | Jamais |

**Sources et puits de Stardust (valeurs exactes)**

| Source | Montant | Plafond |
|---|---|---|
| Libérer un Nebby | Commun 1, Peu commun 4, Rare 15, Épique 60, Légendaire 300, Mythique 1 500 (× 3^(★−1)) | Aucun |
| Couper un autre joueur | 5 par Nebby détaché | 200 / jour (UTC) |
| Éclater un Gloomwisp | 10 | 300 / jour |
| Grande Comète | 50 si tenue ≥ 3 s ; 15 si à ≤ 20 studs lors de l'encaissement ou de l'explosion ; 25 pour chaque équipier de l'encaisseur | Aucun |
| Nuit de la Balise | 40 par contributeur si réussie, 15 si échouée | Aucun |
| Quêtes du jour | 40 / 60 / 100 (facile / moyenne / difficile) | 3 quêtes + 1 relance |
| Calendrier de connexion | Jour 2 : 50 ; Jour 4 : 150 ; Jour 7 : 100 | 1 / jour |
| Acclamer une Supernova | 5 | 10 acclamations récompensées / jour |
| Cadeau Duo (10 min dans le même serveur qu'un ami Roblox) | 50 | 1 / jour |
| Produit « Bocal de Stardust » | 400 | — |

| Puits de Stardust | Coût |
|---|---|
| Fusion ★1 → ★2 | 25 |
| Fusion ★2 → ★3 | 120 |
| Fusion ★3 → ★4 | 600 |
| Fusion ★4 → ★5 | 3 000 |

### 4.2 Raretés et valeurs

| Rareté | Revenu passif (Glow/s) | Valeur de parade | Stardust à la libération | Taille du corps (studs) | Couleur du corps | Aura (lisible sans couleur) |
|---|---|---|---|---|---|---|
| Commun | 1 | 20 | 1 | 1,6 | Crème (255, 236, 200) | Aucune |
| Peu commun | 4 | 80 | 4 | 1,8 | Menthe (140, 235, 190) | Petite antenne Néon |
| Rare | 15 | 300 | 15 | 2,0 | Bleu ciel (110, 190, 255) | Instance `Sparkles` |
| Épique | 60 | 1 200 | 60 | 2,3 | Violet (180, 120, 255) | `ParticleEmitter` en orbite (3 particules) |
| Légendaire | 300 | 6 000 | 300 | 2,6 | Or (255, 200, 70) | `PointLight` + `Trail` |
| Mythique | 1 500 | 30 000 | 1 500 | 2,8 | Rose prisme (255, 120, 190) | `Highlight` (budget §12.8) + couronne de 3 petites boules Néon |
| Cosmique (événements) | 10 000 | 200 000 | non libérable | 3,0 | Cycle de teinte HSV (client) | Coque matériau `ForceField` + cycle HSV |

Règle : **valeur de parade = 20 × revenu passif**. Un Nebby perché rapporte donc sa valeur de parade toutes les 20 s.

### 4.3 Zones et apparitions

L'île est un disque de 180 studs de rayon centré en (0, 0, 0). Les zones sont des anneaux (rayon mesuré dans le plan XZ).

| Zone | Rayon | Probabilités par rareté | Plafond vivant (12 joueurs) | Intervalle d'apparition | Durée de vie |
|---|---|---|---|---|---|
| **Prairie** (Outer Meadow) | 110-170 | Commun 78 / Peu commun 19 / Rare 3 | 40 | 0,4 s | 90 s |
| **Clairière** (Mid Glade) | 55-110 | Commun 35 / Peu commun 40 / Rare 20 / Épique 5 | 24 | 0,8 s | 75 s |
| **Cratère** | 16-55 | Peu commun 25 / Rare 45 / Épique 23 / Légendaire 6,5 / Mythique 0,5 | 10 | 2,5 s | 60 s |

- **Échelle de population** : plafond effectif = `round(plafond × capScale)` avec `capScale = clamp((joueursActifs + 4) / 16, 0,5, 1,0)`. Un joueur est **actif** s'il a parcouru au moins 4 studs pendant les 60 dernières secondes.
- À chaque intervalle, si la zone est sous son plafond, une apparition a lieu. Espèce : tirage uniforme parmi les espèces de la rareté tirée (espèces disponibles dans la version).
- **Points d'apparition** : grille précalculée par `WorldLayout` (pas de 6 studs) qui exclut les décors, le port sûr élargi (30 studs autour de chaque porte) et la Balise (rayon < 16). Un nouveau Nebby est placé à ≥ 6 studs de tout Nebby sauvage existant (10 essais, sinon on saute ce tour).
- **Déplacement** : chaque Nebby sauvage flâne autour de son point d'ancrage selon `SeededPath.wander(seed, t − t0)` : courbe de Lissajous d'amplitude 1,6 stud, fréquences tirées dans [0,35 ; 0,60] rad/s. Serveur et clients calculent la même position à partir de `workspace:GetServerTimeNow()` : rien de physique n'est répliqué.
- **Fin de vie** : à l'expiration, le Nebby rapetisse (0,4 s) et disparaît.
- **Apparitions personnelles** (`onlyFor`) : Puffkins de bienvenue, Rare garanti de la quête Q4. Envoyées à ce seul client, attrapables par lui seul, hors plafonds.
- **Probabilités affichées** dans l'onglet « Guide » de la Collection (zones, météo, variantes, Comète). Le hasard est gratuit, mais on l'affiche quand même.

### 4.4 Formes (météo) et variantes

Chaque Nebby a **une forme** et **des variantes** cumulables. Multiplicateurs appliqués au revenu passif et à la valeur de parade.

| Forme | Multiplicateur | Source | Rendu |
|---|---|---|---|
| Normale | ×1 | Toujours | Matériau SmoothPlastic |
| **Aurora** | ×2 | Météo Aurora Drift | Accents Néon vert-violet, corps légèrement bleuté |
| **Frozen** (Givrée) | ×2,5 | Météo Frostfall | Matériau `Ice` |
| **Blazing** (Ardente) | ×3 | Météo Solar Flare | Corps orange-rouge + petite instance `Fire` (Size 2) |
| **Eclipse** | ×4 | Météo Eclipse (**v1.1**) | Corps noir, yeux Néon violets |
| **Prismatic** | ×6 | Météo Rainbow Comet (~1 fenêtre sur 14) et Starfall Saturday | Matériau `Glass`, teinte qui cycle (client) |

Pendant une fenêtre météo à mutation, **40 %** des apparitions reçoivent la forme de cette météo.

| Variante | Multiplicateur | Probabilité | Rendu |
|---|---|---|---|
| **Golden** (Doré) | ×4 | 1 % de toute apparition | Couleur or (255, 205, 60), matériau `Foil` |
| **Huge** (Géant) | ×3 | 0,5 % | Échelle ×2 |
| **Starborn** | ×2 | Uniquement pendant Starfall Saturday (§4.15.5) | Halo en étoile Néon à 5 branches |

Les variantes se cumulent : un Prismatic Golden Huge vaut ×72. Le Nebby le plus rare imaginable (Mythique Prismatic Golden Huge) est un objectif de vitrine, pas un objectif de rythme.

### 4.5 Capture

- **Test** (serveur, chaque tick de 0,1 s) : distance XZ entre la `HumanoidRootPart` du joueur et la position `SeededPath` du Nebby ≤ **Attrait + 0,75** (tolérance de latence), écart vertical ≤ 6.
- **Attrait** (rayon) : 5 studs + 0,5 par niveau d'amélioration (max 11). **Snip Rush** (après une coupe réussie) : Attrait × 1,5 pendant 3 s.
- **File pleine** : le Nebby n'est pas attrapé ; le compteur de file clignote en rouge « PLEINE » et une flèche pointe vers le Nid (au plus une fois toutes les 5 s).
- **Nebbies « libres »** (issus d'une coupe ou d'une explosion de Comète) : *étourdis* 1,2 s pour tout le monde **sauf la victime de la coupe**, qui peut les reprendre immédiatement (priorité au propriétaire). Ils disparaissent au bout de 20 s.
- **Ordre** : si plusieurs joueurs sont à portée dans le même tick, le plus proche gagne ; égalité → le premier dans l'ordre de traitement, tiré au hasard à chaque tick.
- Un Nebby capturé garde son espèce, sa forme et ses variantes ; il n'a pas d'étoile (★1).

### 4.6 La file (Conga)

| Paramètre | Valeur | Clé |
|---|---|---|
| Écart entre deux Nebbies | 2,6 studs | `Balance.Conga.Spacing` |
| Distance tête → 1er Nebby | 3,0 studs | `Balance.Conga.HeadGap` |
| Capacité de la file | 3 + niveau Conga ; plafond de niveau = 12 + 5 × R ; plafond absolu 60 | `Balance.Conga.*` |
| **Conga Bonus** | `min(5, 1 + 0,08 × (n − 1))` où n = Nebbies dans la parade (×5 atteint à n = 51) | `Balance.Conga.BonusStep`, `BonusMax` |
| Ralentissement | −0,4 % de vitesse par Nebby au-delà des Guard Links, max −15 % | `Balance.Conga.SlowPerNebby`, `SlowMax` |
| **Dash** | +10 de WalkSpeed pendant 1,0 s ; recharge `max(5, 7 − 0,25 × R)` s | `Balance.Dash.*` |

**Vitesse (WalkSpeed), toujours fixée par le serveur :**

```
base      = 16 + 0,5 × niveauFoulée                       (16 → 26)
ralenti   = 1 − min(0,15 ; 0,004 × max(0, n − GuardLinks))
comète    = 0,85 si porteur de la Comète, sinon 1
WalkSpeed = base × ralenti × comète
            + 10 pendant un Dash (interdit au porteur de la Comète)
            + 4  pendant Second Souffle (3 s après avoir été coupé)
```

**Position des Nebbies.** Le Nebby i se trouve sur le chemin parcouru par le joueur, à la distance `HeadGap + (i − 1) × Spacing` derrière la tête (abscisse curviligne sur les miettes de chemin, §12.4). La file ne s'enroule pas à l'arrêt : à l'arrêt, les Nebbies « dansent » sur place (rebond plus fort), mais restent sur le chemin. Ainsi la géométrie vue par les clients est exactement celle testée par le serveur.

**Mort, réinitialisation, départ.** Si le personnage meurt ou se réinitialise, toute la file se détache comme après une coupe (priorité au propriétaire, sans Second Souffle). Si le joueur quitte le serveur, sa file se détache sans priorité.

### 4.7 La coupe (Snip)

**Principe.** Un joueur coupe la file d'un autre en faisant passer son corps à travers un segment coupable. Le segment touché et tout ce qui est derrière se détachent, dans la limite du plafond.

**Constantes**

| Paramètre | Valeur | Clé |
|---|---|---|
| Rayon de coupe (corps du coupeur ↔ segment de file) | 2,8 studs (+0,3 « aide tactile » si l'entrée est tactile) ; écart vertical ≤ 4 (sauter par-dessus une file au sommet du saut ne la coupe pas) | `Balance.Snip.Radius`, `TouchAssist`, `MaxDy` |
| Test | **balayé** : segment parcouru par le coupeur pendant le tick (position précédente → actuelle) contre chaque segment coupable de la victime ; distance segment-segment dans le plan XZ | — |
| Guard Links (non coupables) | 3 au départ (Lead Trio), +1 par niveau, max 8 | `Balance.Guard.*` |
| Recharge du coupeur | 1,5 s | `Balance.Snip.SnipperCooldown` |
| Recharge par paire (même coupeur → même victime) | 20 s | `Balance.Snip.PairCooldown` |
| Immunité de la victime après une coupe | 8 s (file entourée d'étincelles roses) | `Balance.Snip.VictimImmunity` |
| **Plafond par minute** | Au plus **2 coupes subies par fenêtre glissante de 60 s**. Après la 2e, immunité jusqu'à 60 s après la 1re | `Balance.Snip.MaxPerMinute` |
| **Plafond par coupe** | Au plus `max(6, floor(0,35 × n))` Nebbies détachés ; si la coupe en libérerait davantage, le point de coupe recule vers la queue | `Balance.Snip.LossCapMin`, `LossCapRatio` |
| Port sûr | Aucune coupe si le point touché est à moins de 25 studs du centre de **n'importe quelle** porte de Nid | `Balance.Snip.HarborRadius` |
| Escorte | Un Nebby à moins de 7 studs (XZ) d'un équipier de la victime n'est pas coupable | `Balance.Crew.EscortRadius` |
| Dispersion | Chaque Nebby détaché vole (arc de 0,55 s) vers un point à 4-9 studs de sa position, tiré par le serveur, ramené dans l'île | `Balance.Snip.Scatter*` |
| Étourdissement | 1,2 s pour tous sauf la victime (0 s) | `Balance.Snip.Dizzy` |
| Second Souffle (victime) | +4 WalkSpeed pendant 3 s | `Balance.Snip.SecondWind*` |
| Snip Rush (coupeur) | Attrait ×1,5 pendant 3 s ; +5 Stardust par Nebby détaché (plafond 200/jour) | `Balance.Snip.Rush*` |

**Ordre d'évaluation serveur (par tick, pour chaque paire coupeur A → victime B) :**

```
si trêve de la Balise active                      → ignorer
si A == B, ou A et B dans le même équipage        → ignorer
si A ou B en Mode Zen                             → ignorer
si B sous bouclier débutant                       → ignorer
si B immunisé (8 s, ou plafond par minute)        → ignorer
si recharge de A (1,5 s) ou de la paire (20 s)    → ignorer
si A en infraction de mouvement ce tick (§12.7)   → ignorer
si boîte englobante(balayage A) ∩ boîte(file B) = ∅ → ignorer   (élagage)
pour k = G+1 … n (du plus proche de la tête au plus loin) :
    segment k = [nœud k−1, nœud k]    (nœud 1 à HeadGap derrière la tête)
    si nœud k escorté                 → continuer
    si point touché dans un port sûr  → continuer
    si distance(balayage A, segment k) ≤ rayon → COUPE en k ; sortir
COUPE en k :
    c = max(k, n − plafond + 1)      (plafond = max(6, floor(0,35 n)))
    détacher les nœuds c … n ; appliquer immunités, recharges, Second Souffle, Snip Rush
    diffuser LineEvent "cut" + WildEvent (Nebbies libres) + effets
```

Le premier segment touché le plus près de la tête est retenu. Les effets visuels de coupe ne sont joués **qu'à la confirmation du serveur**.

**Coupes par les Gloomwisps** : même procédure, avec un rayon de 2,5 studs, sans recharge du coupeur ni récompense, mais elles comptent dans le plafond par minute et déclenchent l'immunité de la victime.

### 4.8 Parade (encaissement)

- **Déclenchement** : la position serveur de la `HumanoidRootPart` entre dans la boîte de la porte de **son propre** Nid (12 × 10 × 4 studs, orientée face au centre). Pendant la Nuit de la Balise, l'anneau de la Balise (8 ≤ r ≤ 16) sert aussi de porte.
- **Calcul** :

```
valeur(nebby) = valeurParade[rareté] × multForme × (Golden ? 4 : 1) × (Huge ? 3 : 1) × (Starborn ? 2 : 1)
CongaBonus    = min(5, 1 + 0,08 × (n − 1))       ; plafonné à 2,5 en Mode Zen
Glow gagné    = floor( Σ valeur × CongaBonus × M × (à la Balise ? 1,5 : 1) )
```

où M est le multiplicateur global (§4.10), évalué **au moment de la parade**.

- **Exemple** : file de 20 au Cratère = 4 Rares (4 × 300), 8 Peu communs (8 × 80), 6 Épiques (6 × 1 200), 1 Légendaire (6 000), 1 Commun Aurora (40). Σ = 15 080. Bonus = 1 + 0,08 × 19 = 2,52. Joueur R = 1 avec 1 équipier présent : M = 1 + 0,40 + 0,10 = 1,50. Gain = floor(15 080 × 2,52 × 1,50) = **57 002 Glow**.
- **Destination** : chaque Nebby encaissé rejoint la collection ; le tri automatique place les meilleurs revenus passifs sur les perchoirs, le reste en réserve (§4.9). Les nouvelles entrées d'Atlas sont validées à ce moment.
- **Bannières** : n ≥ 30 → bannière serveur « Méga Parade » ; record de file du serveur battu → bannière « Record du serveur ».

### 4.9 Perchoirs, réserve, revenu passif, hors ligne

- **Perchoirs** : 3 au départ, +1 par niveau d'amélioration (27 niveaux → 30), +1 par jalon d'Atlas (max +10), +6 avec le pass Extra Perches. **Maximum 46.**
- **Tri automatique** : les Nebbies sont classés par revenu passif décroissant ; les N premiers sont perchés. Aucun placement manuel (pas de bug de placement, pas d'interface lourde). Le joueur peut **verrouiller** un Nebby (cadenas) pour qu'il ne soit jamais libéré ni consommé par une fusion automatique.
- **Réserve** : 300 places (600 avec Stash Plus). Si elle déborde après une parade : libération automatique des Nebbies non verrouillés les moins rentables, **uniquement Communs, Peu communs et Rares**, contre leur Stardust, avec un toast récapitulatif. Si cela ne suffit pas, les nouveaux arrivants excédentaires sont libérés (la parade a déjà payé leur Glow).
- **Revenu passif d'un Nebby** = `passif[rareté] × multForme × variantes × multÉtoile[★]`.
- **Revenu passif total** = `Σ (Nebbies perchés) × M`.
- **Accumulation paresseuse** (pas de boucle par seconde côté serveur) : le profil garde `idleRate` et `lastSettle` (temps serveur). À chaque événement qui change le taux ou le solde (parade, achat, amélioration, changement de perchoirs, début ou fin de boost, entrée/sortie d'équipier) et toutes les 30 s, le serveur crédite `floor(idleRate × (maintenant − lastSettle) + reste)` et garde la fraction dans `glowCarry`. Le client affiche une prédiction (`glow + idleRate × (temps − lastSettle)`), corrigée à chaque patch.
- **Hors ligne** : au chargement, `durée = clamp(os.time() − lastOnline, 0, plafond)`, gain = `floor(idleRateHorsLigne × durée × taux)`. Plafond 8 h et taux 50 % ; avec Night Shift, 12 h et 75 %. `idleRateHorsLigne` exclut les boosts temporaires et le bonus d'équipage. Affiché sur l'écran de retour (§7.2).

### 4.10 Multiplicateur global M

```
M = (1 + 0,40 × R + 0,25 × VIP + 0,10 × min(3, équipiersPrésents))
    × (pass Double Glow ? 2 : 1)
    × (boost actif ? 2 : 1)
```

- `boost actif` = boost personnel ×2 (calendrier, quêtes, Starter Kit) **ou** boost de serveur ×2 (Glow Party, Nuit d'Or après la Balise, Starfall Saturday). Les boosts ×2 ne se cumulent pas entre eux : M dépasse donc au maximum ×4 l'additif de base.
- Les équipiers comptent seulement s'ils sont sur le même serveur et actifs.

### 4.11 Améliorations

Coût du niveau L (L = niveau actuel, le premier achat est donc au coût de base) : `floor(base × croissance^L)`.

| Amélioration | Effet par niveau | Niveaux | Base | Croissance | Remise à zéro (Supernova) |
|---|---|---|---|---|---|
| **Conga** (longueur) | +1 place dans la file (3 → 15 à R0) | 12 + 5 × R (max 57) | 50 | 1,55 jusqu'au niveau 12, puis 1,20 | Oui |
| **Foulée** (Stride) | +0,5 WalkSpeed (16 → 26) | 20 | 80 | 1,42 | Oui |
| **Attrait** (Lure) | +0,5 stud de rayon de capture (5 → 11) | 12 | 70 | 1,50 | Oui |
| **Perchoirs** | +1 perchoir (3 → 30) | 27 | 200 | 1,75 | Non |
| **Guard Links** | +1 Nebby non coupable (3 → 8) | 5 | 5 000 | 4,0 | Non |

Formule Conga exacte : `floor(50 × 1,55^min(L, 12) × 1,20^max(0, L − 12))`.

**Coûts calculés (premiers niveaux)**

| Niveau → | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Conga | 50 | 77 | 120 | 186 | 288 | 447 | 693 | 1 074 | 1 665 | 2 581 | 4 002 | 6 203 |
| Foulée | 80 | 113 | 161 | 229 | 325 | 461 | 655 | 931 | 1 322 | 1 877 | 2 666 | 3 786 |
| Attrait | 70 | 105 | 157 | 236 | 354 | 531 | 797 | 1 196 | 1 794 | 2 691 | 4 036 | 6 054 |
| Perchoirs | 200 | 350 | 612 | 1 071 | 1 875 | 3 282 | 5 744 | 10 053 | 17 592 | 30 787 | 53 877 | 94 286 |

Guard Links : 5 000 / 20 000 / 80 000 / 320 000 / 1 280 000. Totaux : Foulée 211 445 ; Attrait 18 021 ; Conga niveaux 0-11 : 17 386 ; Perchoirs 27 niveaux ≈ 9,7 × 10⁸.

**Équité** : Foulée, Attrait et Guard Links (tout ce qui touche aux autres joueurs) ne s'achètent **qu'en Glow**, jamais en Robux, et sont plafonnés pour tous (WalkSpeed max 26 + Dash).

### 4.12 Supernova (renaissance)

- **Conditions** : Glow ≥ coût, et le joueur se trouve dans le port sûr de son Nid. Si sa file n'est pas vide, elle est encaissée automatiquement (parade normale) juste avant.
- **Écran d'aperçu obligatoire** : deux colonnes « Tu gardes » / « Remis à zéro », gain de la prochaine Supernova, bouton de confirmation maintenu 1 s (évite les erreurs).

| R actuel → R+1 | Coût (Glow) |
|---|---|
| 0 → 1 | 400 000 |
| 1 → 2 | 10 000 000 |
| 2 → 3 | 40 000 000 |
| 3 → 4 | 120 000 000 |
| 4 → 5 | 300 000 000 |
| 5 → 6 | 700 000 000 |
| 6 → 7 | 1 800 000 000 |
| 7 → 8 | 4 000 000 000 |
| 8 → 9 | 8 000 000 000 |
| 9 → 10 | 14 000 000 000 |
| 10 → 11 | 22 000 000 000 |
| 11 → 12 | 34 000 000 000 |
| R ≥ 12 | `34 × 10⁹ × 1,5^(R − 11)` |

Le coût est une **table de configuration** (`Balance.Supernova.Costs`) et non une formule unique : la collection et les perchoirs se conservent, le revenu croît donc vite au début puis ralentit ; la table suit cette courbe (validée par la simulation, §4.18).

| Gagné à chaque Supernova | Remis à zéro | Conservé |
|---|---|---|
| +40 % de revenu permanent (additif) ; +5 au plafond de niveaux Conga (jusqu'à 60 places) ; recharge du Dash −0,25 s (min 5 s) ; une étoile de plus dans la constellation publique du Nid ; aura de file tous les 3 R : Argent (R3), Or (R6), Nova (R9), Galaxie (R12) | Glow, niveaux Conga, Foulée, Attrait | Tous les Nebbies et leurs étoiles, perchoirs, Guard Links, Stardust, Atlas, cosmétiques, quêtes, statistiques |

À chaque Supernova : bannière serveur, séquence visuelle de 2,5 s (§9), et rituel d'**acclamation** pour tout le serveur (§6.6).

### 4.13 Starforge (fusion déterministe)

- 3 Nebbies **identiques** (même espèce, même forme, mêmes variantes, même nombre d'étoiles) → 1 Nebby avec une étoile de plus. Aucun hasard.
- Les Nebbies verrouillés ne sont jamais pris comme « matière » sauf s'ils sont celui que le joueur a choisi.
- Bouton « Tout fusionner » : fusionne en boucle tant que c'est possible et que la Stardust suffit, en commençant par les fusions qui augmentent le plus le revenu perché.

| Étoiles | Multiplicateur de revenu | Coût en Stardust | Copies ★1 nécessaires |
|---|---|---|---|
| ★1 | ×1 | — | 1 |
| ★2 | ×3,5 | 25 | 3 |
| ★3 | ×12 | 120 | 9 |
| ★4 | ×43 | 600 | 27 |
| ★5 | ×150 | 3 000 | 81 |

Chaque fusion rapporte plus que les 3 Nebbies séparés (×3,5 contre ×3) **et** libère 2 perchoirs : elle est toujours avantageuse.

### 4.14 Star Atlas (livre de collection)

- **Entrée** = espèce × forme. MVP : 30 espèces × 5 formes = **150 entrées** ; v1.1 ajoute 6 espèces et la forme Eclipse : 36 × 6 = **216**.
- **Badges** séparés : Golden et Huge par espèce (60 au MVP, 72 en v1.1) ; Starborn par espèce (événementiel).
- Une entrée est validée **à l'encaissement** (ou à la réception d'une récompense). Pendant la course, un petit « ? » doré flotte au-dessus d'un Nebby encore inconnu : on veut rentrer pour l'enregistrer.
- Chaque espèce a une fiche : nom, rareté, zones, formes trouvées (silhouettes grises pour les manquantes), meilleur exemplaire possédé.

**Jalons (toutes les 12 entrées)**

| Entrées | Récompense |
|---|---|
| 12, 24, 36, 48, 60, 72, 84, 96, 108, 120 | +1 perchoir chacun (10 au total) |
| 132 | Titre « Cartographe » + traînée de file « Constellation » |
| 144 | Thème de Nid « Atlas » (couleurs de la plateforme et de l'arche) |
| 156, 168… (v1.1) | Titres, couleurs de traînée |
| Une espèce complète (toutes ses formes) | +100 Stardust et l'espèce s'affiche dorée dans l'Atlas |

### 4.15 Événements

#### 4.15.1 Météo

- **Créneau** = `floor(t / 360)` (t = secondes UTC). Fenêtre active de `début + 120 s` à `début + 270 s` (150 s).
- **Type** tiré de manière déterministe : `Hash.u32(créneau, SEL_METEO) / 2³²` comparé aux poids cumulés. Même résultat sur tous les serveurs.

| Météo | Poids | Effet |
|---|---|---|
| Aurora Drift | 30 | 40 % des apparitions en forme Aurora |
| Frostfall | 26 | 40 % en forme Frozen |
| Solar Flare | 20 | 40 % en forme Blazing |
| Meteor Shower | 17 | Pas de forme ; intervalles d'apparition ÷3, plafonds ×1,5 |
| Rainbow Comet | 7 | 40 % en forme Prismatic (≈ une fenêtre toutes les 86 min) |
| Eclipse (v1.1) | 10 (les autres poids sont réduits proportionnellement) | 40 % en forme Eclipse |

- Bannière à l'ouverture : « Nebbies Aurora ×2 · 2:30 » ; la pastille d'événement du HUD affiche le compte à rebours. Une Comète qui tombe pendant une fenêtre porte la forme de la météo.

#### 4.15.2 La Grande Comète (toutes les 10 min)

| Phase | Détail |
|---|---|
| Alerte (−8 s) | Bannière « COMÈTE ! », la lumière ambiante baisse, la Comète traverse le ciel sur une courbe de Bézier de 6 s |
| Impact (:X0:00 pile) | Point d'impact déterministe : `Hash(créneau)` → rayon 10-40 du Cratère, angle 0-360°. Ondes de choc, pilier de lumière |
| Contenu | Un Nebby : Légendaire 80 % / Mythique 18 % / Cosmique 2 % (gratuit, probabilités affichées) ; espèce uniforme dans la rareté ; forme de la météo active s'il y en a une |
| Ramassage | Le premier joueur dont la position serveur passe à ≤ 4 studs (XZ) devient **porteur**. Interdit en Mode Zen |
| Porteur | Vitesse ×0,85, pas de Dash, `Highlight` doré, anneau doré tournant au-dessus de la tête, faisceau vertical visible de toute la carte, icône clignotante sur la minicarte. Le HUD de tous affiche « ☄ COMÈTE 0:45 — Mira » |
| Vol (« chat perché ») | Tout joueur non équipier qui passe à ≤ 4,0 studs du porteur (test balayé) prend la Comète. Le nouveau porteur est immunisé 2 s ; l'ancien ne peut pas la reprendre pendant 4 s. Le port sûr **ne protège pas** la Comète. Le bouclier débutant non plus (règle simple et annoncée : « la Comète est à tout le monde ») |
| Encaissement | Le porteur traverse la porte de son Nid : il garde le Nebby + Glow égal à 120 s de son revenu passif. Feu d'artifice, bannière |
| Explosion | 75 s après l'impact si personne ne l'a encaissée : elle éclate en 5 Nebbies Épiques libres dans le Cratère ; **1 au maximum par joueur** |
| Participation | Tenue ≥ 3 s : +50 Stardust. À ≤ 20 studs lors de l'encaissement ou de l'explosion : +15 Stardust + Glow = 30 s de son propre revenu passif. Équipiers de l'encaisseur : +25 Stardust |

Le porteur garde sa file, qui reste coupable normalement.

#### 4.15.3 Nuit de la Balise (trêve, :25-:28 et :55-:58)

- Alerte 15 s avant. Le ciel passe en pleine nuit, la Balise s'allume.
- **Trêve** : aucune coupe (joueurs et Gloomwisps ; les Gloomwisps s'effacent).
- **Nourrir la Balise** : faire une parade dans l'anneau de la Balise. Elle paie ×1,5 et les Nebbies partent quand même au Nid : contribuer ne coûte rien. Chaque Nebby encaissé = 1 point sur la barre de serveur.
- **Objectif** = `max(20, 10 × joueursActifs) × miséricorde`. Miséricorde = 0,75 après 2 échecs consécutifs, 0,5 après 3 et plus ; remise à 1 après une réussite. Cible de conception : ≈ 80 % de réussite.
- **Réussite** : *Starfall Frenzy* 60 s (intervalles d'apparition ÷4, plafonds ×2), puis **Nuit d'Or** : boost ×2 de serveur pendant 5 min. Chaque contributeur gagne 40 Stardust ; bannière pour le meilleur contributeur.
- **Échec** : chaque contributeur gagne 15 Stardust ; la Balise « s'endort » avec un petit soupir lumineux (pas de punition).

#### 4.15.4 Gloomwisps (tension non joueur pour les petits serveurs)

- **Nombre actif** = `max(0, 5 − floor(joueursActifs / 3))` : 1-2 joueurs → 5 ; 3-5 → 4 ; 6-8 → 3 ; 9-11 → 2 ; 12 → 1. Aucun pendant la Nuit de la Balise ni pendant Starfall Saturday.
- **Trajet déterministe** (`SeededPath.chord`) : une corde droite entre deux points du cercle r = 165, à 7 studs/s ; à l'arrivée, pause de 4 s puis nouvelle corde (seed suivante). Un `Beam` en pointillés montre les 15 prochains studs de leur trajet : on les voit venir.
- **Grignotage** : un Gloomwisp coupe les segments coupables qu'il traverse (rayon 2,5) selon les règles du §4.7 (port sûr, bouclier, Zen, immunités respectés).
- **Éclater** : un joueur dont le corps passe à ≤ 4,5 studs l'éclate : +10 Stardust (300/jour max) + Glow = 20 s de son revenu passif. Il réapparaît sur une nouvelle corde 10 s plus tard.
- Apparence mignonne, jamais effrayante (§11.6). Pas de faux joueurs : les Gloomwisps sont clairement des créatures du monde.

#### 4.15.5 Starfall Saturday (samedi 16:00-16:20 UTC)

- 17:00 à Paris en hiver (18:00 en été), 11:00 à New York en hiver (12:00 en été) ; une heure avant la mise à jour de 17:00 UTC.
- Météo Rainbow Comet continue pendant 20 min (40 % de formes Prismatic).
- Grande Comète **toutes les 3 min** (16:00, 16:03… 16:18 : 7 comètes) ; la Nuit de la Balise et les Gloomwisps sont suspendus.
- Boost ×2 de serveur pendant 20 min.
- **Espèce vedette de la semaine** (rotation déterministe sur 12 semaines, table `Events.FeaturedSpecies`) : 25 % des apparitions ; parmi elles, 8 % portent la variante **Starborn** (×2). Présent au moins 5 min pendant le show → 1 Nebby vedette Starborn garanti envoyé au Nid à la fin.
- Les Starborn sont réellement limités : chaque espèce Starborn ne revient que lors d'un **Encore annuel** annoncé à l'avance.

### 4.16 Protection des joueurs

| Protection | Règle exacte | Pourquoi |
|---|---|---|
| **Bouclier débutant** (Rookie Shield) | Actif si `session == 1` **ou** (`tempsDeJeuCumulé < 30 min` **et** `R == 0`). La file entière porte une bulle dorée ; elle ne peut être coupée ni par un joueur ni par un Gloomwisp. Le joueur protégé peut couper les autres, mais ces coupes ne rapportent pas de Stardust (pas d'intérêt à créer des comptes secondaires). Le retrait n'a jamais lieu en pleine course : il attend la prochaine parade ou une file vide, puis une bannière « Tu es prêt ! » l'annonce | La première session (la plus surveillée par l'algorithme) se fait sans frustration |
| **Mode Zen** (Calm) | Réglage personnel. Activable ou désactivable seulement dans le port sûr de son Nid, recharge 60 s. En Zen : on ne peut ni couper ni être coupé (Gloomwisps compris), on ne peut pas porter la Comète (récompenses de proximité conservées), Conga Bonus plafonné à **×2,5** au lieu de ×5. Halo turquoise sous le personnage | Les joueurs sensibles jouent sans stress ; le plafond garde la poursuite plus rentable |
| **Serveurs privés** (gratuits) | Le propriétaire peut activer « Coupes désactivées » pour tout le serveur (sans plafond de bonus) | Jouer entre amis sans conflit |
| **Plafonds de perte** | §4.7 : 2 coupes / 60 s, 35 % de la file par coupe, 8 s d'immunité, priorité de reprise à la victime, Second Souffle | Une mauvaise minute ne ruine jamais une session |
| **Nid** | Jamais pillable, aucun Nebby encaissé ne peut être perdu | Pilier P2 |

### 4.17 Limites anti-abus

| Abus | Limite |
|---|---|
| Ferme à coupes (coupeurs automatiques, comptes complices) | Stardust de coupe ≤ 200/jour ; recharge par paire 20 s ; victimes plafonnées à 2 coupes/min ; coupes sous bouclier débutant sans récompense ; équipiers ne peuvent pas se couper |
| Ferme à Gloomwisps | 300 Stardust/jour |
| Captures automatisées | ≤ 1 500 captures par heure et par joueur (bien au-dessus d'un humain) ; au-delà, captures suspendues 5 min et drapeau d'exclusion des classements |
| Vitesse/téléportation | Contrôle de déplacement (§12.7) |
| Rafales de remotes | Seau à jetons par action (§12.5) |
| Codes | Une fois par compte, liste côté serveur uniquement, date d'expiration |
| Glow Party | File d'attente de 60 min maximum ; bouton d'achat masqué au-delà de 20 min restantes |
| Acclamations | 10 récompensées par jour ; 1 par Supernova |
| Revente / transfert | Aucun échange ni don au MVP (le don entre amis arrivera avec un journal de séquestre en deux phases, §15) |

### 4.18 Rythme de progression et simulation

Joueur de référence : 30 min de jeu actif par jour (35 min le premier jour), gains hors ligne gratuits (50 %, 8 h), aucun achat.

| Jalon | Cible | Tolérance |
|---|---|---|
| Première parade | 12 s | ≤ 20 s |
| Première amélioration | 20 s | ≤ 30 s |
| Supernova 1 | 25 min (1re session) | 20-35 min |
| Supernova 3 | fin du jour 3 | jour 2-4 |
| Supernova 6 + premier ★3 | jour 7 | jour 6-8 |
| 50 % de l'Atlas | jour 14 | jour 10-16 |
| Supernova 10 | jour 21 | jour 18-24 |
| 80 % de l'Atlas | jour 28 | — (Prismatic, Cosmique et variantes forment la longue traîne) |

**Simulation de rythme (porte de qualité).** Un test Lune (`tests/specs/EconomyPacing.spec.luau`) simule 200 joueurs de référence sur 28 jours avec les tables de `Shared/Config/Balance` et `Nebbies` : courses (zone choisie selon la capacité de file), pertes par coupe (12 % hors Prairie), comètes gagnées 1 fois sur 6, quêtes, hors ligne, achats d'améliorations au moins cher d'abord, fusions dès que possible. Le test échoue si la médiane d'un jalon sort de sa tolérance. Une première version de ce modèle (prototype hors moteur) donne : Supernova 1 entre 19 et 35 min, S3 au jour 3, S6 aux jours 6-7, S10 aux jours 17-22 sans compter les perchoirs d'Atlas ni les bonus d'équipage : les tables ci-dessus sont donc légèrement prudentes.

Leviers d'ajustement sans code : `Supernova.Costs`, `Upgrades.*.Base/Growth`, `Offline.Rate/Cap`, `Zones.*.Interval`.

---

## 5. Contenu complet

### 5.1 Les 36 espèces de Nebbies

L'identifiant numérique est **définitif** (il est sauvegardé) : on ne réordonne jamais la table, on ajoute à la fin. Les 6 espèces « v1.1 » ont déjà leur identifiant réservé. La couleur du **corps** est celle de la rareté (§4.2) ; la couleur d'**accent** distingue l'espèce.

| Id | Clé | Nom | Rareté | Archétype(s) | Accent (RGB) | Version | Note |
|---|---|---|---|---|---|---|---|
| 1 | `puffkin` | Puffkin | Commun | Puff | 255, 255, 255 | MVP | Nebbies de bienvenue |
| 2 | `pebblit` | Pebblit | Commun | Moon | 170, 160, 150 | MVP | |
| 3 | `dewdrop` | Dewdrop | Commun | Twin | 150, 220, 255 | MVP | |
| 4 | `mossmop` | Mossmop | Commun | Sprout | 120, 190, 90 | MVP | |
| 5 | `sprigglet` | Sprigglet | Commun | Sprout | 190, 230, 110 | MVP | |
| 6 | `bumblume` | Bumblume | Commun | Wing | 255, 215, 90 | MVP | |
| 7 | `nibbit` | Nibbit | Commun | Horn | 255, 170, 140 | MVP | |
| 8 | `fluffle` | Fluffle | Commun | Puff | 215, 190, 245 | v1.1 | |
| 9 | `bluebell_puff` | Bluebell Puff | Peu commun | Puff | 90, 140, 255 | MVP | |
| 10 | `ringlet` | Ringlet | Peu commun | Ring | 255, 240, 150 | MVP | |
| 11 | `twinkleaf` | Twinkleaf | Peu commun | Sprout | 120, 255, 200 | MVP | |
| 12 | `glimbug` | Glimbug | Peu commun | Wing | 255, 160, 220 | MVP | |
| 13 | `mintwhisk` | Mintwhisk | Peu commun | Spike | 90, 210, 170 | MVP | |
| 14 | `pebblepop` | Pebblepop | Peu commun | Moon | 200, 170, 255 | MVP | |
| 15 | `cloudlet` | Cloudlet | Peu commun | Twin | 240, 245, 255 | v1.1 | |
| 16 | `cometcub` | Cometcub | Rare | Comet | 255, 180, 90 | MVP | Starter Kit |
| 17 | `prismpaw` | Prismpaw | Rare | Horn | 180, 255, 255 | MVP | |
| 18 | `frostfinch` | Frostfinch | Rare | Wing | 200, 240, 255 | MVP | Starter Kit |
| 19 | `lanternling` | Lanternling | Rare | Ring | 255, 210, 120 | MVP | |
| 20 | `daybreak_puff` | Daybreak Puff | Rare | Puff | 255, 190, 150 | MVP | Calendrier jour 5, Starter Kit |
| 21 | `mooncap` | Mooncap | Rare | Moon | 230, 230, 255 | MVP | |
| 22 | `spinnaroo` | Spinnaroo | Rare | Spike | 255, 130, 130 | v1.1 | |
| 23 | `glimmerwhale` | Glimmerwhale | Épique | Twin | 120, 200, 255 | MVP | |
| 24 | `starhorn` | Starhorn | Épique | Horn | 255, 235, 120 | MVP | |
| 25 | `aurorabbit` | Aurorabbit | Épique | Crown | 170, 255, 200 | MVP | |
| 26 | `nebulynx` | Nebulynx | Épique | Spike | 210, 140, 255 | MVP | |
| 27 | `orbitoad` | Orbitoad | Épique | Ring | 140, 255, 170 | MVP | |
| 28 | `galaxifox` | Galaxifox | Épique | Spike | 255, 150, 210 | v1.1 | |
| 29 | `nova_nimbus` | Nova Nimbus | Légendaire | Puff + Ring | 255, 255, 220 | MVP | |
| 30 | `eclipse_owlet` | Eclipse Owlet | Légendaire | Wing + Moon | 120, 100, 200 | MVP | |
| 31 | `sunwyrm` | Sunwyrm | Légendaire | Spike + Crown | 255, 150, 60 | MVP | |
| 32 | `celestikoi` | Celestikoi | Légendaire | Comet | 255, 120, 120 | v1.1 | |
| 33 | `prismara` | Prismara | Mythique | Crown | 255, 200, 255 | MVP | |
| 34 | `chronomoth` | Chronomoth | Mythique | Wing | 160, 255, 240 | MVP | |
| 35 | `astralope` | Astralope | Mythique | Horn | 255, 230, 180 | v1.1 | |
| 36 | `grand_nebula` | Grand Nebula | Cosmique | Comet + Ring | cycle HSV | MVP | Comète (2 %) et événements uniquement |

Répartition : MVP 7 / 6 / 6 / 5 / 3 / 2 / 1 = 30 espèces ; complet 8 / 7 / 7 / 6 / 4 / 3 / 1 = 36.

**Rotations déterministes** (indice de semaine `w = floor((t − 345 600) / 604 800)`, semaines commençant le lundi 00:00 UTC) :

| Usage | Table | Sélection |
|---|---|---|
| « Weekly Wanderer » (calendrier jour 7) | Épiques 23, 24, 25, 26, 27 | `w mod 5` |
| Légendaire de la quête « Grand Défilé » | 29, 30, 31 | `w mod 3` |
| Espèce vedette de Starfall Saturday | 1, 9, 16, 23, 4, 12, 19, 25, 6, 14, 21, 27 | `w mod 12` |

### 5.2 Fabrication des Nebbies en primitives (`NebbyBuilder`)

Construits **côté client** à partir de 4 nombres (espèce, forme, variantes, étoiles). Toutes les pièces sont ancrées, `CanCollide = CanQuery = CanTouch = false`, `CastShadow = false`. Au maximum **8 pièces** par Nebby en détail complet.

| Pièce | Primitive | Dimensions (× taille du corps T) | Matériau / couleur |
|---|---|---|---|
| Corps | Ball | T | SmoothPlastic, couleur de rareté (ou forme / variante) |
| Yeux (2) | Ball | 0,28 T, à (±0,22 ; +0,12 ; −0,42) T | SmoothPlastic noir, Reflectance 0,3 |
| Joues (2) | Cylinder plat | diamètre 0,20 T, épaisseur 0,03 T, à (±0,32 ; −0,08 ; −0,38) T | Rose (255, 160, 190) |
| Accent | 1 à 3 pièces selon l'archétype | voir ci-dessous | Couleur d'accent de l'espèce |

| Archétype | Accent | Animation (client) |
|---|---|---|
| Puff | 3 petites Balls (0,45 T) groupées sur le dessus | Léger gonflement ±5 % |
| Sprout | Tige Cylinder (0,08 × 0,4 T) + 2 WedgeParts feuilles | Balancement ±10° |
| Horn | 1 CornerWedge (0,3 × 0,4 × 0,3 T) sur le front | — |
| Wing | 2 WedgeParts latérales | Battement ±25° à 6 Hz |
| Ring | Halo Cylinder Néon plat (diamètre 1,1 T, épaisseur 0,06) au-dessus de la tête | Rotation 1 tour / 3 s |
| Twin | Seconde Ball (0,6 T) sur le côté | Rebond décalé |
| Spike | 3 WedgeParts piques sur le dos | — |
| Moon | 2 Balls « cratères » (0,3 T) enfoncées, couleur du corps × 0,8 | — |
| Crown | 3 WedgeParts dorées sur le dessus | — |
| Comet | Ball de queue (0,5 T) derrière + `Trail` (détail complet uniquement) | Queue qui ondule |

Les Légendaires combinent deux archétypes (au plus 3 pièces d'accent au total). **Niveaux de détail** : < 50 studs = modèle complet ; 50-120 studs = une seule Ball (couleur du corps, Néon si Mythique+) ; > 120 studs = rien pour un Nebby sauvage, et pour une file seulement le Nebby de tête + une étiquette « ×N ».

### 5.3 Cosmétiques

| Catégorie | Élément | Obtention |
|---|---|---|
| Style de file (anneau Néon sous chaque Nebby + `Trail` sur le dernier) | Défaut (couleur du Nid) | Gratuit |
| | Constellation | Atlas 132 entrées |
| | Étoile Royale | Pass VIP Star |
| | Comet Tail | Starter Kit |
| | Rainbow Ripple, Ember, Bubbles, Starlight, Frost, Neon Wave | Pass Conga Styles |
| Aura de file (lueur des anneaux + couronne du Nebby de tête) | Argent, Or, Nova, Galaxie | Supernova 3, 6, 9, 12 |
| Titres (sous le nom) | Cartographe | Atlas 132 |
| | Chasseur de Comètes | 10 Comètes encaissées |
| | Gardien de la Balise | 20 Balises réussies avec contribution |
| | Roi / Reine de la Conga | Top 10 hebdomadaire de la plus longue parade (pendant la semaine suivante) |
| | Ange gardien | 100 minutes d'escorte d'équipier |
| Thème de Nid (plateforme + arche) | Couleur du Nid | Gratuit |
| | Atlas | Atlas 144 entrées |
| | Or Royal | Pass VIP Star |

**Palette des 12 Nids** (couleur du propriétaire) : 1 Corail (255, 120, 110) · 2 Mandarine (255, 165, 80) · 3 Citron (250, 220, 90) · 4 Citron vert (160, 220, 90) · 5 Menthe (90, 220, 170) · 6 Sarcelle (60, 200, 210) · 7 Ciel (90, 170, 255) · 8 Indigo (120, 120, 240) · 9 Violet (170, 110, 240) · 10 Orchidée (220, 110, 220) · 11 Rose (255, 110, 170) · 12 Sable (220, 190, 150). Nid libre : gris (120, 120, 130), sans lumière.

### 5.4 Récapitulatif du contenu au lancement

| Type | MVP (v1.0) | Complet (v1.1) |
|---|---|---|
| Espèces | 30 | 36 |
| Formes | 5 (Normale, Aurora, Frozen, Blazing, Prismatic) | 6 (+ Eclipse) |
| Variantes | Golden, Huge, Starborn | idem |
| Entrées d'Atlas | 150 (+60 badges Golden/Huge) | 216 (+72) |
| Météos | 5 (dont Meteor Shower sans forme) | 6 |
| Événements récurrents | Grande Comète, Nuit de la Balise + Frenzy, Gloomwisps, Starfall Saturday | + Œufs de Comète, boutique de l'Observatoire |
| Zones | Prairie, Clairière, Cratère | idem |
| Améliorations | 5 pistes | idem |
| Quêtes | 7 d'accueil, 25 quotidiennes, 1 hebdomadaire | + Star Path (30 paliers) en v1.2 |
| Cosmétiques | 11 styles et auras, 5 titres, 3 thèmes de Nid | + décorations de Nid (v1.2) |

---

## 6. Social

Tout fonctionne **sans chat** (le chat exige une vérification d'âge, Rapport §7). Le jeu ne lit jamais le texte du chat.

### 6.1 Équipages (Crews)

| Règle | Valeur |
|---|---|
| Taille | 4 joueurs maximum |
| Formation automatique | Les amis Roblox présents sur le serveur forment un équipage automatiquement (réglage « Équipage auto avec mes amis », activé par défaut ; vérifié côté serveur avec `Player:IsFriendsWith`, en `pcall`, résultat mis en cache) |
| Invitation | Panneau **Équipage** : liste des joueurs du serveur avec un bouton « Inviter » (56 px). La cible voit une carte « Mira t'invite » avec ✓ / ✕ pendant 20 s. Limite : 1 invitation / 3 s, 5 / min ; réglage « Refuser les invitations » |
| Effets | Les équipiers ne peuvent pas se couper ; **Escorte** : un Nebby d'une file à ≤ 7 studs d'un équipier du propriétaire n'est pas coupable (petites bulles bleues) ; bonus de Glow +10 % par équipier présent (max +30 %) ; crédit de Comète partagé (+25 Stardust) |
| Placement | À l'arrivée, si un ami a déjà un Nid, on attribue le Nid libre le plus proche du sien. Les Nids d'un même équipage sont reliés la nuit par un `Beam` cyan → or (repère visuel, image de vignette) |
| Quitter | Bouton « Quitter l'équipage » (recharge 5 s) ; un départ du serveur retire de l'équipage |

L'escorte crée un vrai rôle de **garde du corps** : le corps d'un équipier ne couvre qu'une partie d'une longue file, donc son placement compte. **Temps d'escorte** (quêtes, titre « Ange gardien ») : secondes pendant lesquelles au moins un Nebby coupable d'un équipier est à ≤ 7 studs de toi, hors des ports sûrs et hors trêve.

### 6.2 Jouer ensemble (co-play)

- **Bonus d'équipage** (ci-dessus), **Nids voisins**, **serveurs privés gratuits**.
- **Cadeau Duo** : après 10 min cumulées sur le même serveur qu'un ami Roblox, les deux reçoivent 50 Stardust (une fois par jour et par joueur).
- **Bouton Inviter** (`SocialService:PromptGameInvite`) sans récompense attachée : on récompense le jeu ensemble, jamais l'envoi d'invitations (risque de politique « invitations incitées »).

### 6.3 Roue de pings

| Ping | Icône (dessinée en Frames) | Emote par défaut jouée |
|---|---|---|
| Aide ! | Bouée | — |
| Suis-moi | Flèche | `point` |
| Comète ! | Comète | — |
| Bravo ! | Étoile | `cheer` |
| Attention ! | Point d'exclamation | — |
| Merci | Cœur | `wave` |

Ouverture : touche Q, croix directionnelle haut, ou bouton tactile (72 px). Sélection : 1-6, clic, ou stick. Affichage : BillboardGui de 4 × 4 studs au-dessus de la tête pendant 2,5 s, visible jusqu'à 200 studs. Limite : 1 ping / 1,5 s. Les emotes sont jouées par le client sur son propre personnage (`Humanoid:PlayEmote`).

### 6.4 Voir ce que font les autres

- **Minicarte** circulaire (Frames) en haut à droite : point par joueur (taille selon la longueur de file, couleur du Nid), Comète clignotante, Balise, Gloomwisps en violet. Calculée depuis les données de chemin du serveur, donc indépendante du streaming.
- **Tableau « Plus longues congas »** (SurfaceGui sur la Balise) : top 5 en direct + record du serveur + top 10 mondial de la semaine.
- **Lisibilité des files** (aide pour les plus jeunes) : quand un autre joueur est à ≤ 20 studs, ses Nebbies coupables portent un anneau rose et ses Guard Links un anneau doré ; quand un non-équipier approche à ≤ 15 studs de ta propre queue coupable, elle passe en contour pointillé rose (« attention »).

### 6.5 Bannières de serveur

File d'attente de 3 maximum, 3 s chacune, priorité décroissante : Mythique+ capturé > Comète (vol, encaissement, explosion) > Supernova > Méga Parade (≥ 30) > record de file du serveur > Glow Party. Un même joueur déclenche au plus une bannière toutes les 10 s. Exemples : « Mira a attrapé un MYTHIQUE ! », « COMÈTE VOLÉE par Noah ! », « Léa : SUPERNOVA III ! ».

### 6.6 Acclamations de Supernova et constellations

- Quand un joueur fait une Supernova, tous les autres voient un gros bouton **ACCLAMER !** pendant 10 s (anneau de temps). Appuyer joue l'emote `cheer` et lance un arc de confettis vers le Nid du héros ; l'acclameur gagne 5 Stardust (10 fois par jour) ; le héros voit « 9 joueurs t'acclament ! ».
- **Constellation publique** au-dessus de chaque Nid (Y = 45) : une étoile Néon par Supernova, reliée à la précédente par un `Beam`. Le rang de chacun se lit de loin et donne aux nouveaux un objectif visible.

### 6.7 Classements

| Classement | Portée | Stockage | Rafraîchissement |
|---|---|---|---|
| Plus longue conga en cours | Serveur | Mémoire | Chaque seconde |
| Plus longue parade de la semaine | Mondial | `OrderedDataStore` `WeeklyConga_<w>` | Écriture quand un joueur bat son record de la semaine (file d'écriture par serveur, vidée toutes les 60 s) ; lecture du top 10 toutes les 120 s |
| Star Atlas (entrées) | Mondial | `OrderedDataStore` `AtlasAllTime` | Idem |

Les joueurs signalés par l'anti-triche (§12.7) ne sont pas écrits. Les classements récompensent l'adresse et la collection, pas la dépense : pas de classement de Glow total.

### 6.8 Moments viraux prévus

| Moment | Pourquoi il se filme (clip ≤ 30 s, onglet Moments) |
|---|---|
| Course-poursuite de la Comète | Faisceau visible de partout, « chat perché » à 12, retournements de situation |
| Coupe d'une file de 40+ | Explosion de Nebbies, mêlée générale, tampon « SNIP ! » |
| Conga de 50 Nebbies qui serpente dans le Cratère | Image iconique de vignette |
| Supernova | Flash, sphère de lumière, 11 joueurs qui acclament |
| Starfall Frenzy | Le ciel pleut des Nebbies après un effort commun |
| Escorte d'équipage | Deux gardes du corps qui encadrent une file géante jusqu'à la porte |

---

## 7. Rétention

### 7.1 Crochets par horizon (algorithme 28 jours, Rapport §5.1)

| Horizon | Crochets |
|---|---|
| **J1** | Récompense à 12 s ; bouclier débutant toute la session ; chaîne d'accueil ; première Comète en ≤ 10 min (5 en moyenne) ; Supernova 1 dans la session ; message de fin « Ton Nid travaille même quand tu dors » affiché à 10 min de jeu et dans le menu |
| **J2-J7** | Écran de retour avec gains hors ligne ; calendrier de 7 jours indulgent ; 3 quêtes du jour ; chasse aux formes météo ; Supernovas 2 à 6 ; Atlas ; cadeau Duo |
| **J8-J28** | Supernovas 7 à 12 et auras ; Starforge ★3-★5 ; Prismatic, Golden, Huge ; quête hebdomadaire ; classements hebdomadaires ; Starfall Saturday et ses Starborn ; contenu toutes les 2 semaines |

### 7.2 Écran de retour

S'ouvre au chargement si les gains hors ligne ≥ 1 % du coût de la prochaine Supernova ou ≥ 1 000 Glow. Contenu : « Pendant ton absence (5 h 12) : +1,24 M Glow » ; le compteur défile (0,8 s, `Quint Out`) avec une fontaine de pièces ; bouton « Super ! » (96 px). Si le pass Night Shift n'est pas possédé, une ligne discrète, jamais insistante : « Night Shift : 75 % pendant 12 h ».

### 7.3 Calendrier de connexion (7 jours, indulgent)

Une réclamation par jour UTC. **Un jour manqué met la série en pause** (on reprend au même jour) : rien n'est jamais perdu. Après le jour 7, le cycle recommence au jour 1.

| Jour | Récompense |
|---|---|
| 1 | Glow = 5 min de revenu passif (min. 500) |
| 2 | 50 Stardust |
| 3 | Boost personnel ×2 pendant 15 min |
| 4 | 150 Stardust |
| 5 | Nebby Rare **Daybreak Puff** |
| 6 | Boost personnel ×2 pendant 30 min |
| 7 | Nebby Épique **Weekly Wanderer** (rotation §5.1) + 100 Stardust |

### 7.4 Chaîne d'accueil (quêtes Q1-Q7)

| Quête | Objectif | Récompense |
|---|---|---|
| Q1 | Parade d'au moins 4 Nebbies | 50 Glow |
| Q2 | Acheter 2 niveaux de Conga | 80 Glow |
| Q3 | Parade d'au moins 6 Nebbies | 150 Glow |
| Q4 | Encaisser un Rare (pilier bleu + Rare garanti) | Déblocage de l'Atlas + 100 Stardust |
| Q5 | Acheter 1 niveau de Foulée | 200 Glow |
| Q6 | Attraper un Nebby météo **ou** participer à une Comète | 300 Glow + 50 Stardust |
| Q7 | Atteindre 10 perchoirs | Boost personnel ×2 pendant 10 min |
| Ensuite | Objectif long affiché en permanence : « Supernova · 400 000 » | — |

### 7.5 Quêtes du jour

Chaque jour UTC : 3 quêtes (1 facile, 1 moyenne, 1 difficile) tirées de manière déterministe (`Hash(jour, UserId)`) dans le pool ci-dessous. 1 relance gratuite par jour (+1 avec VIP). Les quêtes marquées **JcJ** ne sont jamais proposées à un joueur en Mode Zen ; les quêtes **Équipage** seulement à un joueur qui a eu un équipage dans les 7 derniers jours.

Récompenses : facile 40 Stardust + Glow = 3 min de revenu passif ; moyenne 60 + 6 min ; difficile 100 + 10 min. Les 3 terminées : « Étoile du jour », boost personnel ×2 pendant 15 min.

| # | Niveau | Quête | Objectif |
|---|---|---|---|
| 1 | Facile | Attrape des Nebbies | 40 captures |
| 2 | Facile | Fais 5 parades | 5 parades |
| 3 | Facile | Parade de 8 | 1 parade ≥ 8 |
| 4 | Facile | Participe à une Comète | Tenir ≥ 3 s ou être à ≤ 20 studs à la fin |
| 5 | Facile | Éclate 3 Gloomwisps | 3 |
| 6 | Facile | Dash ! | 15 Dash |
| 7 | Facile | Achète 5 améliorations | 5 niveaux |
| 8 | Facile | Nourris la Balise | 5 Nebbies encaissés à la Balise |
| 9 | Moyen | Parade de 15 | 1 parade ≥ 15 |
| 10 | Moyen | Chasse aux Rares | 5 Rares capturés |
| 11 | Moyen | Chasseur de météo | 3 Nebbies de forme météo |
| 12 | Moyen | Snip ! (JcJ) | Détacher 5 Nebbies en coupant |
| 13 | Moyen | Visite du Cratère | 10 captures dans le Cratère |
| 14 | Moyen | Ange gardien (Équipage) | 30 s d'escorte |
| 15 | Moyen | Forgeron | 2 fusions Starforge |
| 16 | Moyen | Économiste | Gagner 30 min de revenu passif en Glow |
| 17 | Moyen | Supporter | Acclamer 2 Supernovas |
| 18 | Difficile | Parade de 25 | 1 parade ≥ 25 |
| 19 | Difficile | Épiques en série | 3 Épiques capturés |
| 20 | Difficile | Grand trésor | 1 Légendaire ou mieux capturé |
| 21 | Difficile | Porteur de Comète | Tenir la Comète 10 s au total |
| 22 | Difficile | Balise allumée | 1 Nuit de la Balise réussie avec contribution |
| 23 | Difficile | Grand Snip (JcJ) | Détacher 15 Nebbies en coupant |
| 24 | Difficile | Collectionneur | 3 nouvelles entrées d'Atlas |
| 25 | Difficile | Gros défilé | 1 parade rapportant ≥ 10 min de revenu passif |

**Quête hebdomadaire « Grand Défilé »** : encaisser 300 Nebbies dans la semaine → le Légendaire de la semaine (rotation §5.1) + 300 Stardust. Remise à zéro lundi 00:00 UTC.

### 7.6 Événements de serveur et rendez-vous

Rappel : Comète toutes les 10 min, météo toutes les 6 min, Balise toutes les 30 min (§2.4) ; **Starfall Saturday** chaque samedi à 16:00 UTC (§4.15.5). Le show est déclaré comme *Experience Event* dans le Creator Hub (jusqu'à 10 événements publiés, Rapport §5.2). Un sujet `MessagingService` « LiveOps » permet à une liste blanche d'administrateurs (UserIds dans la config serveur) de déclencher un événement de la table sur tous les serveurs (par exemple une Comète supplémentaire pendant un live).

### 7.7 Cadence des mises à jour

Rythme soutenable (l'équipe de Grow a Garden s'est épuisée en hebdomadaire, Rapport §5.4) :
- **chaque semaine** : Starfall Saturday automatique (nouvelle espèce vedette par rotation), notes de version en jeu, un code promo sur les réseaux ;
- **toutes les 2 semaines** : un ajout de contenu par la configuration (espèces, météo, cosmétiques, quêtes), publié le samedi à 17:00 UTC ;
- **chaque mois** : un événement à thème (par exemple Halloween Eclipse, Hiver Frostfall), fait de préréglages d'éclairage et de données.

---

## 8. Monétisation

### 8.1 Principes non négociables

1. **Aucun objet aléatoire payant** : ni œuf, ni coffre, ni roue, ni boost de chance payant.
2. Tout ce qui touche aux **autres joueurs** (Foulée, Attrait, Guard Links, Dash) s'obtient seulement en jouant ; pas d'immunité de coupe payante, pas d'« annuler la coupe pour 15 R$ ».
3. **Prix lus à l'exécution** avec `MarketplaceService:GetProductInfoAsync` (module `Client/Util/Prices` existant) pour la tarification gérée (*Managed Pricing* : prix régionaux et tests A/B) ; le prix en config n'est qu'un repli d'affichage. IDs fictifs (`0` = article désactivé et masqué) dans `Shared/Config/Monetization`.
4. `ProcessReceipt` **idempotent** (service existant) : `PurchaseId` mémorisé (100 derniers), `PurchaseGranted` renvoyé seulement après une sauvegarde réussie.
5. Pas de faux minuteur, pas de « promo du jour » permanente, pas de prix cachés derrière une monnaie intermédiaire : chaque bouton affiche le prix en Robux et exactement ce qu'on reçoit.
6. Les articles limités (Starborn) le sont vraiment ; ils ne reviennent que lors de l'Encore annuel annoncé.

### 8.2 Game passes (permanents)

| Clé | Nom | Prix indicatif | Effet |
|---|---|---|---|
| `VIPStar` | VIP Star | 199 R$ | +25 % Glow (additif dans M) ; badge doré « ★ VIP » sous le nom ; thème de Nid « Or Royal » ; style de file « Étoile Royale » ; +1 relance de quête par jour |
| `DoubleGlow` | Double Glow | 299 R$ | ×2 sur le revenu passif et les parades |
| `NightShift` | Night Shift | 99 R$ | Gains hors ligne à 75 % pendant 12 h (au lieu de 50 % pendant 8 h) |
| `ExtraPerches` | Extra Perches | 149 R$ | +6 perchoirs |
| `StashPlus` | Stash Plus | 99 R$ | Réserve 300 → 600 places |
| `CongaStyles` | Conga Styles | 79 R$ | 6 styles de file cosmétiques |

Le pass « Long Conga » (+10 places de file) du concept initial est **supprimé** : il vendait un plafond de Conga Bonus plus élevé dans un affrontement entre joueurs, perçu comme payer pour gagner (jury, §03).

### 8.3 Produits développeur (consommables, déterministes)

| Clé | Nom | Prix indicatif | Effet |
|---|---|---|---|
| `GlowPouch` | Bourse de Glow | 25 R$ | Glow = 10 min du revenu passif actuel (min. 1 000) |
| `GlowSack` | Sac de Glow | 89 R$ | 40 min (min. 4 000) |
| `GlowCrate` | Caisse de Glow | 199 R$ | 120 min (min. 12 000) |
| `GlowParty` | Glow Party | 99 R$ | Boost ×2 de **tout le serveur** pendant 10 min ; bannière dans le ciel « Glow Party offerte par Mira ! » ; cœurs « Merci » envoyables par les autres. File d'attente cumulable jusqu'à 60 min ; bouton masqué au-delà de 20 min restantes. La Nuit d'Or (Balise) donne le même boost gratuitement |
| `StardustJar` | Bocal de Stardust | 49 R$ | 400 Stardust |
| `StarterKit` | Starter Kit | 49 R$, **une fois par compte** | 3 Rares fixes (Cometcub, Frostfinch, Daybreak Puff), style de file « Comet Tail », boost personnel ×2 pendant 20 min. Visible tant qu'il n'est pas acheté, sans compte à rebours |

Le montant des produits Glow est calculé **par le serveur au moment de l'attribution** et affiché sur le bouton avant l'achat avec « ≈ » (calcul client depuis le revenu passif répliqué).

### 8.4 Ce qui est volontairement exclu

Œufs, coffres et roues en Robux ; boosts de chance payants ; immunité payante ; annulation de coupe payante ; « passer le minuteur » ; récompenses d'invitation ; publicités hors du cadre officiel. **Vidéo récompensée** : seulement après 2 000 visiteurs mensuels, là où `PolicyService` renvoie `AreAdsAllowed = true`, facultative (« doubler mes gains hors ligne », 1 fois par jour), en v1.3 au plus tôt.

### 8.5 Attentes honnêtes

Taux DevEx standard 0,0038 $/R$ et 70 % net sur les ventes (Rapport §5.5). Conversion visée 1,5 à 3 %. Revenus portés par Double Glow, VIP Star et Glow Party. Le modèle juste rapporte moins par joueur que les concurrents prédateurs : c'est un choix assumé, car l'algorithme 2026 récompense la rétention et le nombre de payeurs baisse.

---

## 9. Juice et animation

### 9.1 Module commun

Tous les effets passent par le module client `UI/Juice` (existant : `tween`, `pulse`, `press`, `popIn`, `popOut`, `shake`, `countTo`, `flash`, `cameraShake`, compatible Mouvement réduit) et un nouveau `Controllers/VFXController` qui ajoute :

| Fonction | Rôle |
|---|---|
| `floatText(worldPos, text, color, scale)` | Texte « +N » dans le monde (réserve de 20 BillboardGui réutilisés) |
| `stamp(text, color)` | Tampon centré (police `LuckiestGuy`, `UIStroke` 3 px) |
| `flyCoins(fromScreen, toGui, n)` | Pièces (Frames dorées rondes) sur courbe de Bézier |
| `ring(worldPos, radius, color, duration)` | Onde Néon au sol (Cylinder plat) |
| `burst(worldPos, color, count)` | `ParticleEmitter:Emit` sur un émetteur réutilisé (texture par défaut) |
| `pillar(worldPos, color, duration, height)` | Colonne Néon qui s'amincit |
| `fovPunch(delta, outTime, backTime)` | Coup de focale |
| `haptic(strength, duration)` | Vibration mobile via `HapticService` si supportée |

**Règles** : une seule animation par propriété à la fois (annuler l'ancienne) ; aucune création d'instances en rafale (réserves) ; secousse caméra via `Humanoid.CameraOffset` (bruit de Perlin, amplitude ≤ 0,4, durée ≤ 0,3 s) ; les fondus de pièces 3D se font en **rétrécissant** la pièce (on garde Transparency à 0 ou 1). Les sons sont optionnels : chaque clé de `Shared/Config/Sounds` a un ID vide par défaut et le jeu reste entièrement jouable en silence.

**Réglages.** *Mouvement réduit* (suit aussi `GuiService.ReducedMotionEnabled`) : pas de secousse, pas de coup de focale, pas de flash, pas de travelling d'arrivée ; les déplacements d'interface deviennent des fondus. *Graphismes légers* : particules ×0,3, pas de `Trail` sauf la Comète, `Highlight` seulement sur le porteur de la Comète, distances de détail ×0,6, lumières coupées au-delà de 60 studs.

### 9.2 Interface

| Interaction | Tweens | Effets | Son |
|---|---|---|---|
| Appui sur un bouton | `UIScale` 1 → 0,92 en 0,06 s (`Quad Out`) ; au relâchement 0,92 → 1,05 → 1 en 0,18 s (`Back Out`) ; couleur +10 % de luminosité pendant l'appui | — | `Click` |
| Survol (PC) | `UIScale` → 1,05 en 0,12 s (`Quad Out`) | — | — |
| Refus (pas assez) | Secousse horizontale ±6 px × 3 en 0,25 s ; contour rouge 0,25 s | Toast « Il manque 1,2K Glow » | `Error` |
| Ouverture de panneau | `UIScale` 0,85 → 1 en 0,22 s (`Back Out`) + `CanvasGroup.GroupTransparency` 1 → 0 en 0,15 s ; `BlurEffect` 0 → 8 en 0,2 s (sauf Graphismes légers) | — | `Whoosh` |
| Fermeture de panneau | `UIScale` 1 → 0,9 + fondu en 0,12 s (`Quad In`) | — | — |
| Compteur de monnaie | Défilement `countTo` 0,5 s (`Quint Out`) + pop `UIScale` 1,15 → 1 en 0,2 s (`Back Out`). Le revenu passif défile sans pop | — | `Coin` (au plus 8 / s) |
| Reflet des boutons principaux | `UIGradient.Offset` −1 → 1 en 0,6 s toutes les 4 s | — | — |
| Bouton qui attire l'attention | Pulsation `UIScale` 1 → 1,08, sinus 0,8 s, en boucle | Main dessinée en Frames pendant l'accueil | — |

### 9.3 Nebbies (tout côté client, aucun trafic réseau)

| Situation | Animation |
|---|---|
| Sauvage, au repos | Rebond `Y = sin(2,2 t + φ) × 0,25` ; clignement toutes les 3-6 s (yeux à 0,1 en Y pendant 0,08 s, seulement à ≤ 40 studs) ; regarde le joueur le plus proche à ≤ 15 studs (rotation lissée à 15 % par image) ; flânerie `SeededPath` |
| Dans une file | Vague `Y = sin(4 t + 0,5 i) × 0,35` ; chaque Nebby fait face au précédent ; inclinaison dans les virages `clamp(vitesseAngulaire × 0,15, ±15°)` |
| File à l'arrêt (> 1 s) | Petite danse sur place : sauts de 0,6 stud à 3 Hz, décalés le long de la file |
| File ≥ 20 | Couronne Néon sur le Nebby de tête + `Highlight` de contour à la couleur du Nid (4 files les plus proches au maximum) |
| File ≥ 40 | Paillettes au sol sous la tête de file (`ParticleEmitter`, 10 / s) |
| Perché au Nid | Rebond lent ; « +N » toutes les 2,5 s pour les 8 Nebbies les plus rentables du Nid local seulement |

### 9.4 Gameplay

| Interaction | Tweens et mouvement | Particules / 3D | Caméra / écran | Texte | Son |
|---|---|---|---|---|---|
| **Capture** | Saut vers sa place dans la file sur une parabole de 0,3 s (sommet 4 studs) ; à l'atterrissage écrasement (1,25 ; 0,75 ; 1,25) → 1 en 0,2 s (`Back Out`) | 10 particules à la couleur de rareté | Compteur de file : pop 1,15 en 0,15 s ; « ×1,24 » au-dessus de la tête pulse | « +1 Puffkin » (taille selon la rareté : Commun ×0,8 → Mythique ×1,6) ; « ? » doré si nouvelle entrée d'Atlas | `Catch`, hauteur 1 + min(0,5 ; 0,01 × n) |
| Capture Rare+ | + colonne Néon 0,6 s (diamètre 1,5 → 0, hauteur 30) | — | — | — | `CatchRare` |
| Capture Épique+ | — | — | Focale 70 → 74 → 70 en 0,25 s ; vibration légère 0,08 s | — | — |
| Capture Légendaire+ | — | Colonne de lumière de 4 s visible par tout le serveur | — | Bannière de serveur (glisse en 0,25 s `Back Out`, reste 3 s) | — |
| Capture Mythique+ | — | Confettis multicolores (60 particules) | Flash blanc 0,12 s (opacité 35 %) ; secousse 0,3 s, amplitude 0,3 | — | — |
| **File pleine** | Compteur de file : 2 clignotements rouges en 0,3 s | — | — | Petit tampon « PLEINE » + flèche vers le Nid pendant 2 s | `Error` (doux) |
| **Coupe** (au point de coupe) | Le Nebby coupé flashe en blanc 0,1 s | 12 étincelles blanches | — | « SNIP ! » : échelle 0 → 1,4 → 1 en 0,35 s (`Elastic Out`), police `LuckiestGuy`, contour 3 px | `Snip` |
| Dispersion | Chaque Nebby libre vole sur un arc de 0,55 s (hauteur 3) vers son point ; il atterrit étourdi : 3 petites boules Néon tournent autour de sa tête pendant 1,2 s (2 tours/s) | Pour la victime seulement : anneau doré sous ses propres Nebbies (priorité) | — | — | `Scatter` |
| Côté victime | — | Traînées de vitesse aux pieds pendant 3 s (Second Souffle) | Vignette rose sur les bords (4 Frames à `UIGradient`) qui pulse 0,4 s ; secousse 0,25 s, amplitude 0,35 | « Récupère-les ! » 1,5 s | — |
| Côté coupeur | — | Anneau « Snip Rush » Néon de 6 studs aux pieds pendant 3 s | — | « +7 libres ! » et « +35 ✦ » | `Snip` (plus aigu) |
| **Reprise** d'un Nebby libre | Comme une capture | Comme une capture | — | « Récupéré ! » (victime) | `Catch` |
| **Parade** | Les Nebbies franchissent la porte et sautent sur les perchoirs, un toutes les 0,06 s, séquence plafonnée à 2 s (par groupes de 2-3 au-delà de 33) | Mini « +valeur » sur les 12 premiers puis un total ; ≥ 15 : 3 feux d'artifice Néon au-dessus du Nid ; arche de la porte qui flashe | Tampon central « PARADE ×2,36 ! » : échelle 2 → 1 et rotation −8° → 0 en 0,25 s (`Back Out`), tenu 0,8 s ; 8-16 pièces volent de la porte (position écran) au compteur en 0,5 s, décalées de 0,03 s (`Quad In`) | Total « +57K » doré | `Bank` puis `Coin` |
| **Dash** | — | `Trail` sur la `HumanoidRootPart` (2 attachements) pendant 1 s ; nuage de 8 particules | Focale 70 → 78 en 0,12 s (`Quad Out`), retour en 0,5 s (`Quad InOut`) | Le bouton affiche un balayage radial de recharge puis pop 1,15 + flash quand il est prêt | `Dash` |
| **Amélioration** | Barre de stat remplie en 0,3 s (`Quad Out`), niveau qui défile | Anneau Néon aux pieds 0 → 12 studs en 0,4 s en s'amincissant ; Conga : silhouette fantôme (Ball `ForceField`) au bout de la file pendant 1 s ; Perchoir : le perchoir pousse du sol (taille Y 0 → finale en 0,35 s `Back Out`) + 10 particules de terre | — | « Niv. 8 » | `LevelUp` |
| **Supernova** (2,5 s) | t = 0 : `ExposureCompensation` 0 → 1,5 en 0,6 s + teinte blanche ; t = 0,3 : faisceau du Nid vers le ciel (largeur 0 → 8) ; t = 0,6 : sphère Néon 0 → 40 studs en 0,8 s (`Quad Out`) puis effondrement 0,4 s (`Back In`) ; t = 2,0 : retour de l'éclairage en 0,5 s | Nouvelle étoile de constellation : pop 0 → 1,2 (`Back Out`) puis `Beam` tracé en 0,6 s | Secousse 0,3 s (héros) | Titre « SUPERNOVA III » qui s'écrit en 0,6 s (`MaxVisibleGraphemes`) ; bannière de serveur | `Supernova` |
| **Comète : alerte** (−8 s) | Lumière ambiante −30 % en 2 s ; la Comète (Ball Néon de 6 studs + `Fire` + `Trail` + `Sparkles`) traverse le ciel en 6 s | — | Bannière « COMÈTE ! » (0,25 s `Back Out`) | — | `CometWarn` |
| Comète : impact | — | 3 anneaux Néon 0 → 60 studs décalés de 0,15 s (0,8 s `Quad Out`) ; `PointLight` 0 → 8 → 1 en 1 s (portée 40) ; pilier `Beam` vers le ciel tant qu'elle n'est pas portée | Secousse 0,3 s d'amplitude `0,4 × (1 − d / 120)` si d < 120 studs | — | `CometImpact` |
| Comète : porteur | Anneau de 8 boules dorées qui tourne au-dessus de la tête | `Highlight` doré (remplissage 0,7) ; faisceau vertical de 200 studs (largeur 3) | Icône clignotante (2 Hz) sur la minicarte | HUD de tous : « ☄ COMÈTE 0:45 — Mira » | — |
| Comète : vol | L'orbe file en 0,2 s sur un arc vers le nouveau porteur | — | — | Tampon « COMÈTE VOLÉE ! » (voleur), toast (volé) | `CometSwipe` |
| Comète : encaissement / explosion | — | 5 feux d'artifice / l'orbe clignote 3 fois en 0,5 s puis lance 5 Épiques en arcs de 0,6 s | — | Bannière | `Reward` |
| **Météo** début / fin | Éclairage vers le préréglage en 3 s (`Sine InOut`), retour en 3 s | Particules de météo (§11.5) | — | Bannière 3 s + compte à rebours dans la pastille | `Whoosh` |
| **Balise** début | `ClockTime` → 21,5 en 4 s ; anneaux Néon de la Balise s'allument un à un (0,1 s chacun) ; faisceau 2 → 6 de large | — | Barre de serveur qui glisse en haut | « NUIT DE LA BALISE · TRÊVE » | `BeaconStart` |
| Balise : contribution | 5 orbes Néon volent du joueur vers la Balise en 0,5 s | — | Barre qui se remplit (`Back Out`, 0,3 s) | « +12 » | `Coin` |
| Balise : réussite | Flash de la Balise ; pluie de 60 étoiles Néon pendant le Frenzy ; éclairage doré pendant la Nuit d'Or | — | — | « STARFALL FRENZY ! » | `BeaconWin` |
| Balise : échec | La Balise s'assombrit avec une bouffée bleue (1 s) | — | — | Toast « Presque ! +15 ✦ » | — |
| **Gloomwisp** | Tremblement d'échelle ±8 % à 2 Hz ; `Beam` en pointillés devant lui | Grignotage : « miam ! » + 6 bouffées sombres | — | — | — |
| Gloomwisp éclaté | Écrasement (Y 0,6 puis X 0,6) en 0,15 s | 16 étincelles blanches ; une petite lueur s'envole | — | « +10 ✦ » | `WispPop` |
| **Bouclier débutant** | Bulle dorée (Ball `ForceField` 1,3 × T) sur chaque Nebby en détail complet ; à la fin, les bulles éclatent une à une (0,05 s chacune) | — | — | Bannière personnelle « Tu es prêt ! » | `Reward` |
| **Mode Zen** | Anneau turquoise sous le personnage (fondu 0,3 s) | — | — | Toast | `Click` |
| **Calendrier** | Carte qui se retourne (rotation 0 → 90 en 0,15 s, changement, 90 → 0 en 0,15 s) ; les points de série se remplissent | La récompense vole vers son compteur | — | — | `Reward` |
| **Quête** terminée | Barre remplie en 0,3 s ; la carte pulse à 1,1 ; une coche se dessine ; « Réclamer » pulse | Récompense qui vole vers le compteur | — | — | `Reward` |
| **Atlas** : nouvelle entrée | Carte qui glisse de la droite en 0,3 s (`Back Out`) ; reflet `UIGradient` en 0,6 s | — | — | « NOUVEAU ! Prismpaw · Aurora » | `Pop` |
| Atlas : jalon | — | Confettis à l'écran | — | Bannière personnelle | `LevelUp` |
| **Starforge** | 3 icônes tournent autour du centre en accélérant (1,2 s), flash blanc 0,15 s, le résultat pop en 0,3 s (`Back Out`), les étoiles apparaissent une à une (0,1 s) | — | — | « ★3 ! » | `LevelUp` |
| **Libération** | L'icône rétrécit en 0,2 s (`Quad In`) | Particules de Stardust vers le compteur | — | « +60 ✦ » | `Pop` |
| **Achat Robux** | Pluie de 30 pièces (1 s) | Glow Party : bannière dans le ciel + confettis dorés pour tout le serveur | — | « Merci ! » | `Reward` |
| **Ping** | Icône 0 → 1,2 → 1 en 0,25 s (`Back Out`), tenue 2,5 s, fondu 0,2 s | — | — | — | `Ping` |
| **Acclamation** | Le bouton monte du bas en 0,3 s (`Back Out`) avec un anneau de 10 s | Arc de confettis (20 particules + `Beam` en arc) vers le Nid du héros | — | « 9 joueurs t'acclament ! » (héros) | `Cheer` |
| **Équipage** formé | `Beam` entre les Nids tracé en 0,6 s | Petite étoile bleue au-dessus des équipiers | — | Toast avec les deux noms | `Pop` |
| **Retour hors ligne** | Compteur qui défile en 0,8 s (`Quint Out`) | Fontaine de pièces | — | « Pendant ton absence : +1,24M » | `Coin` |

---

## 10. UI/UX mobile d'abord

### 10.1 Principes

- Tout est construit en code (`Frame`, `TextLabel`, `TextButton`, `UIGradient`, `UIStroke`, `UICorner`, `UIScale`, `UIListLayout`, `UISizeConstraint`). Aucune image importée : les icônes sont des formes en Frames et de grands glyphes.
- Un `ScreenGui` par écran logique, `ResetOnSpawn = false`, `ScreenInsets = CoreUISafeInsets`, `ZIndexBehavior = Sibling`. Marge de 16 px de référence sur les bords.
- **Mise à l'échelle** : résolution de référence 1280 × 720 ; `UIScale = clamp(hauteurViewport / 720, 0,6 ; 1,25)`.
- **Tailles minimales de référence** : bouton principal 96 px (≈ 58 px réels à l'échelle 0,6 sur un téléphone), bouton secondaire 80 px (≈ 48 px), cible tactile absolue ≥ 56 px réels pour Dash et Ping. Texte ≥ 18 px de référence, `TextScaled` + `UITextSizeConstraint`.
- **Zones réservées** : le joystick dynamique (quart inférieur gauche) et le bouton de saut (coin inférieur droit) ne sont jamais recouverts.
- Style : `UICorner` 12-16 px ; `UIStroke` 2-3 px bleu nuit (16, 12, 30) ; dégradé vertical léger ; police `FredokaOne` pour le texte, `LuckiestGuy` pour les tampons ; couleurs de `UI/Theme` (les couleurs de rareté y sont mises à jour selon §4.2).
- Affichage progressif : le HUD complet n'apparaît qu'au fil de l'accueil (§3).

### 10.2 HUD

| Élément | Ancrage / position (référence) | Taille | Contenu |
|---|---|---|---|
| Pastille Glow | Haut gauche (16, 16) | 260 × 64 | Pièce dessinée, valeur (34 px), revenu « +1,2K/s » (18 px) |
| Pastille Stardust | Haut gauche (16, 88) | 200 × 48 | Étoile dessinée, valeur. Apparaît à Q4 |
| Icônes secondaires | À droite des pastilles | 56 × 56 | Équipage, Réglages |
| Pastille d'événement | Haut centre | 320 × 48 | Prochain événement « ☄ 3:12 », ou événement en cours en couleur ; pendant la Comète : « ☄ COMÈTE 0:45 — Mira » ; pendant la Balise : barre de serveur 420 × 28 dessous |
| Minicarte | Haut droite (−16, 16) | 150 × 150 (cercle) | §6.4 ; touche M ou appui pour l'agrandir à 300 × 300 |
| Indicateurs d'état | Sous la minicarte | 48 × 48 | Bouclier débutant, Zen, boost ×2 (avec minuteur) |
| Suivi de quête | Droite, sous la minicarte | 260 × 72 | Icône + 4 mots + barre ; repliable |
| Rail de menus | Gauche, de y = 150 à y = 470 | 4 boutons de 80 × 80, écart 8 | Améliorer, Collection, Objectifs, Boutique ; pastille rouge « ! » si action possible |
| Compteur de file | Bas centre (y = −24) | 360 × 56 | « 7/15 », barre, « ×1,48 » ; vide : « Attrape des Nebbies ! » |
| Bouton Dash | En haut à gauche du bouton de saut tactile (position lue à l'exécution dans `TouchGui.TouchControlFrame.JumpButton`, décalage −16 px) ; sur PC/manette : bas droite | 112 × 112 | Icône éclair, balayage de recharge |
| Bouton Ping | À gauche du Dash | 72 × 72 | Ouvre la roue (6 secteurs de 96 px) |
| Bannières | Haut centre, sous la pastille | 640 × 72 | §6.5 |
| Toasts | Haut centre | 480 × 56 | Module `UI/Toast` existant (3 maximum) |
| Bouton ACCLAMER | Bas centre au-dessus du compteur de file | 200 × 88 | 10 s, anneau de temps |

### 10.3 Écrans

| Écran | Accès | Contenu | Remarques |
|---|---|---|---|
| Chargement | Automatique | Nebby qui rebondit, points animés | `ReplicatedFirst`, code seulement |
| Échec de chargement | Automatique | « Ton Nid se réveille… » + bouton Réessayer (téléportation vers le même jeu) | Jamais de profil vide |
| Retour hors ligne | Au chargement | §7.2 | |
| **Améliorer** | Rail, touche U | 5 cartes (icône, niveau, effet actuel → suivant, prix, bouton Acheter 96 px) ; bouton **Supernova** en bas avec anneau de progression | La carte achetable la moins chère pulse |
| **Supernova** (aperçu) | Depuis Améliorer | Deux colonnes Gardé / Remis à zéro, gains, bouton à maintenir 1 s | Hors port sûr : message « Rentre au Nid » |
| **Collection** | Rail, touche C | Onglets : *Perchoirs* (Nebbies perchés, revenu de chacun), *Réserve* (grille, tri, verrou, libérer en lot), *Forge* (fusions possibles en haut, « Tout fusionner »), *Atlas* (grille d'espèces × formes, jalons), *Guide* (probabilités par zone, météo, Comète, variantes) | Grille virtualisée (seules les cases visibles existent) |
| **Objectifs** | Rail, touche J | Onglets : *Aujourd'hui* (3 quêtes, relance), *Calendrier* (7 jours), *Semaine* (Grand Défilé), *Accueil* (tant que non finie) | |
| **Boutique** | Rail, touche B | Onglets : *Passes*, *Boosts & Glow* (montants calculés), *Codes* (champ + Valider) | Prix lus à l'exécution |
| **Équipage** | Icône, touche G | Équipage actuel, liste des joueurs (Inviter), bouton Inviter un ami, Quitter | |
| **Réglages** | Icône | Mode Zen, Mouvement réduit, Graphismes légers, Musique, Effets sonores, Équipage auto, Refuser les invitations, Langue (Auto / English / Français) ; dans un serveur privé dont on est propriétaire : Coupes désactivées | Interrupteurs de 80 × 48 |

Panneaux : `Size = UDim2.fromScale(0,72 ; 0,86)` avec `UISizeConstraint` (min 480 × 320, max 900 × 600) ; onglets de 56 px de haut ; bouton Fermer 64 × 64 en haut à droite. Un seul panneau ouvert à la fois ; ouvrir un panneau ne met pas le jeu en pause (le serveur continue).

### 10.4 PC et manette

| Action | Tactile | Clavier / souris | Manette |
|---|---|---|---|
| Se déplacer | Joystick | WASD / flèches | Stick gauche |
| Sauter | Bouton Roblox | Espace | A |
| **Dash** | Bouton Dash | Maj gauche ou E | X |
| Roue de pings | Bouton Ping | Q puis 1-6 ou clic | Croix haut puis stick + A |
| Menus | Rail | U, C, J, B, G ; Échap ferme | Y ouvre le rail (sélection `GuiService.SelectedObject`), B ferme, LB/RB changent d'onglet |
| Minicarte | Appui | M | Croix bas |
| Acclamer | Bouton | F | Croix droite |

Les actions passent par `ContextActionService` (stable) avec les boutons tactiles créés par notre interface. L'option de verrouillage de la souris (Maj) est désactivée (`StarterPlayer.EnableMouseLockOption = false`) car Maj sert au Dash et le jeu n'a pas besoin de visée. Tous les boutons d'interface ont `Selectable = true` et un ordre de navigation manette explicite (`NextSelection*`).

---

## 11. Monde : Lumora, construite en primitives

### 11.1 Plan (vue de dessus, rayon en studs, origine au centre)

```
                         r = 180  bord de l'île (falaise + murs invisibles r = 181)
              ┌───────────────────────────────────────────────┐
              │   Nids sur l'anneau r = 150, tous les 30°     │
              │   (porte vers le centre à r = 131)            │
              │      ┌───────────────────────────────┐        │
              │      │  PRAIRIE   r 110-170          │        │
              │      │    ┌─────────────────────┐    │        │
              │      │    │ CLAIRIÈRE r 55-110  │    │        │
              │      │    │   ┌─────────────┐   │    │        │
              │      │    │   │ CRATÈRE     │   │    │        │
              │      │    │   │ r 16-55     │   │    │        │
              │      │    │   │  ★ BALISE   │   │    │        │
              │      │    │   │  r < 16     │   │    │        │
              │      │    │   └─────────────┘   │    │        │
              │      │    └─────────────────────┘    │        │
              │      └───────────────────────────────┘        │
              │   12 chemins radiaux : porte (r 131) → bord du │
              │   Cratère (r 58), lanternes à r 120, 90, 60    │
              └───────────────────────────────────────────────┘
       îlots flottants décoratifs à r 230-260 ; mer de nuages à Y = −60
```

| Élément | Construction | Position / dimensions |
|---|---|---|
| Île | Cylinder, axe vertical, Grass (82, 170, 160) | Centre (0, −10, 0), diamètre 360, épaisseur 20 → dessus à Y = 0 |
| Clairière | Disque Cylinder de 0,2 d'épaisseur, Grass lavande (140, 150, 205) | Diamètre 220, dessus à Y = 0,1 |
| Cratère (sol) | Disque Basalt (60, 58, 80) | Diamètre 110, dessus à Y = 0,3 |
| Cratère (rebord) | 12 segments de 2 WedgeParts dos à dos (pente vers l'intérieur et l'extérieur), hauteur 2,5, Basalt | Anneau r 52-58, interrompu par 12 ouvertures de 8 studs alignées sur les chemins |
| Fissures | 18 Parts Néon cyan (90, 230, 255), 0,2 × 0,05 × 6-12 | Au sol du Cratère, orientations tirées par seed |
| Falaise | 48 WedgeParts Slate (90, 95, 120) | Sous le bord, de r 176 à 182, jusqu'à Y = −30 |
| Murs invisibles | 36 Parts 2 × 40 × 32, `Transparency = 1`, `CanCollide = true` | r = 181 |
| Îlots flottants | 6 × (Ball Slate de 14 + Cylinder Grass de 16 × 2), tag `Float` (amplitude 2, période 6 s) | r 230-260, Y 10-30 |
| Mer de nuages | 40 Balls blanches aplaties (Build.cloud), tag `Float` | Y = −60, r 200-420 |
| Chemins | Pas japonais : Cylinders plats de 4 × 0,2, Slate clair (200, 195, 215), tous les 6 studs | 12 rayons, de r 131 à r 58 (≈ 144 pièces) |
| Lanternes | Poteau Cylinder 0,6 × 6 Wood (110, 80, 60) + Ball Néon 1,4 (255, 210, 140) ; `PointLight` (portée 12, luminosité 1,2) seulement à r 90 et r 60 | Sur chaque chemin à r 120, 90, 60 (36 lanternes, 24 lumières) |

### 11.2 La Balise (centre)

Pile de Cylinders Marble (235, 230, 250) : socle Ø 14 × 3, fût Ø 10 × 8, sommet Ø 6 × 10 ; entre chaque étage un anneau Néon cyan de 0,6 d'épaisseur. Étoile au sommet (Y ≈ 26) : deux Parts Néon dorées 8 × 1 × 1 croisées + Ball Néon de 3. `Beam` vers le ciel (attachement à Y = 300), largeur 2 (6 pendant la Balise). Anneau de dépôt : Cylinder Néon plat Ø 28 × 0,2, allumé seulement pendant la Nuit de la Balise (zone de parade 8 ≤ r ≤ 16). `SurfaceGui` du tableau des congas sur une stèle à r = 12, face au sud. Collision : r < 8.

### 11.3 Les 12 Nids

Nid k (k = 0 … 11) centré en `(150 cos(30° k), 0, 150 sin(30° k))`, orienté vers le centre.

| Pièce | Construction | Dimensions / position (repère local : Z vers le centre) |
|---|---|---|
| Plateforme | Cylinder couleur du propriétaire (gris si libre) | Ø 34, épaisseur 0,4, dessus à Y = 0,2 |
| Porte | 2 poteaux Cylinder Marble Ø 1,6 × 10 à ±6 + arche de 7 Parts Néon (couleur du propriétaire) en demi-cercle de Y 10 à 13 | À 19 studs du centre du Nid côté centre de l'île (r = 131) |
| Zone de parade | Boîte logique 12 × 10 × 4 (aucune pièce : test mathématique côté serveur) | Centrée sur la porte |
| Observatoire | Tour Cylinder Ø 6 × 14 Marble + dôme Ball Glass Ø 7 + télescope Cylinder Ø 1,4 × 6 incliné à 35° | Derrière la plateforme, hors de celle-ci (r = 172) |
| Perchoirs | Cylinder Wood Ø 2,2 × 1,2 surmonté d'un anneau Néon fin (couleur du propriétaire), `CanCollide = false` | Arcs de 300° ouverts côté porte : r 13 (15 places), r 9,5 (11), r 6 (7) au sol, et r 11 en hauteur à Y = 7 (13 disques Néon flottants) = 46 ; seuls les perchoirs débloqués existent |
| Panneau | BillboardGui (nom, « ★ R », titre) | Y = 16, distance max 120 |
| Constellation | Balls Néon de 1,2 + `Beam` (client) | Y = 45 au-dessus de l'observatoire |
| Apparition | `SpawnLocation` transparente, sans collision, `Neutral = true`, `Duration = 0` | Centre de la plateforme, face à la porte |
| Lumière | `SpotLight` sur le meilleur perchoir | Seulement le Nid du joueur local (côté client) |

Distance entre deux portes voisines : 67,8 studs ; les ports sûrs (r 25) ne se chevauchent pas.

### 11.4 Décor par zone

| Zone | Décor (positions tirées par seed fixe, hors grille d'apparition) | Quantité |
|---|---|---|
| Prairie | *Puffbloom* : tige Cylinder 0,3 × 3 + Ball Néon pastel 1,2 ; *Mushcap* : pied Cylinder 1 × 2 + chapeau Ball 3 SmoothPlastic enfoncé + 3 points Ball blancs ; petites clôtures Wood près des Nids | 60 + 30 + 24 |
| Clairière | Grappes de 3-5 WedgeParts Glass cyan (120, 230, 255) inclinées (Transparency 0,25, seule exception à la règle 0/1, ≤ 80 pièces) ; 6 portent une `PointLight` ; pierres flottantes tag `Spin` autour des grappes | 16 grappes + 8 pierres |
| Cratère | Fissures Néon, 6 petits rochers Basalt (Build.rock) | — |

### 11.5 Éclairage et palette

**Propriétés de base** : posées une fois au démarrage par le serveur (`World/Lighting.luau`, déjà écrit avec des valeurs proches de celles-ci) ; ensuite **le client** anime le cycle et les préréglages à partir de l'horloge commune (`LightingController`), sans réplication. Les valeurs ci-dessous sont la cible ; la direction artistique peut les ajuster de ±20 %.

| Propriété | Valeur |
|---|---|
| `ClockTime` | `17,6 + 2,9 × (0,5 − 0,5 cos(2π t / 720))` : du crépuscule doré (17,6) à la nuit étoilée (20,5) en boucle de 12 min |
| `Ambient` / `OutdoorAmbient` / `Brightness` | (110, 95, 140) / (150, 130, 190) / 2 |
| `Sky` | Textures par défaut, `StarCount` 3000, `MoonAngularSize` 30, `SunAngularSize` 15 |
| `Atmosphere` | Density 0,3, Offset 0,25, Color (199, 170, 255), Decay (106, 112, 255), Glare 0,4, Haze 1,6 |
| `BloomEffect` | Intensity 0,8, Size 24, Threshold 1,2 |
| `ColorCorrectionEffect` | Saturation 0,15, Contrast 0,05 |
| `SunRaysEffect` | Intensity 0,05 |
| `Clouds` (sous `Terrain`) | Cover 0,6, Color (220, 200, 255) |
| `Technology` | Future (réglage du projet) ; repli ShadowMap si le profilage l'exige |

**Préréglages (tween de 3 s)**

| Préréglage | Changements | Effets supplémentaires (client) |
|---|---|---|
| Aurora Drift | Tint (215, 255, 235) ; Atmosphere Color (170, 255, 210), Decay (150, 90, 255) | 6 rideaux `Beam` vert-violet très haut dans le ciel |
| Frostfall | Haze 2,4, Color (220, 235, 255) ; Tint (225, 240, 255) | Neige : `ParticleEmitter` sur une pièce qui suit la caméra (60 / s, vitesse 4-6, durée 6 s) |
| Solar Flare | Tint (255, 225, 190) ; Atmosphere Color (255, 190, 150) ; Bloom 1,1 | — |
| Meteor Shower | — | Traits Néon qui tombent dans le ciel (réserve de 10, un toutes les 0,4 s) |
| Rainbow Comet | Tint qui cycle en HSV (saturation 0,12) sur 8 s | 5 arcs `Beam` arc-en-ciel |
| Eclipse (v1.1) | Brightness 1,2, Tint (190, 170, 255), MoonAngularSize 20 | — |
| Nuit de la Balise | `ClockTime` 21,5, StarCount 5000 | Faisceau de la Balise ×3 |
| Alerte Comète | OutdoorAmbient −30 % en 2 s | — |

**Palette des matériaux** : Grass (sol), Basalt (Cratère), Slate (chemins, falaise), Marble (Balise, portes), Wood (perchoirs, lanternes, clôtures), Glass (cristaux, dôme), Neon (créatures, arches, fissures, anneaux), SmoothPlastic (Nebbies, champignons), Ice/Foil/ForceField (formes et variantes). Lisibilité sur téléphone : sol assez sombre et désaturé, acteurs vifs en Néon.

### 11.6 Gloomwisp et Comète

- **Gloomwisp** : Ball SmoothPlastic indigo foncé (45, 35, 80) de 2,4 + 3 petites Balls « bouffées » + 2 yeux Néon blancs ovales ; `Trail` violet ; toujours rond et mignon, jamais de dents ni de cri.
- **Grande Comète** : Ball Néon de 6 (255, 230, 180) + `Fire` (Size 10, Heat 15, couleurs orange → or) + `Trail` + `Sparkles`. Au sol : orbe de 3 studs qui flotte et tourne, entouré d'un anneau Néon doré.

### 11.7 Budget de construction

Carte ≈ 2 000 à 2 500 pièces (plafond 3 000) : île et falaise ≈ 100, Cratère ≈ 70, Balise ≈ 20, chemins et lanternes ≈ 250, décor ≈ 500, Nids ≈ 12 × (20 + perchoirs débloqués). Les Nebbies, les Gloomwisps et les effets sont **côté client** et ne comptent pas dans ce budget (§12.8). Le cœur de l'île et les Nids sont en `ModelStreamingMode = Persistent`.

---

## 12. Architecture technique

### 12.1 Principes

1. **Le déplacement est la seule entrée de gameplay.** Capture, coupe, parade, Comète et Gloomwisps sont décidés par le serveur dans un tick de 10 Hz, à partir des positions serveur des personnages. Aucun remote « j'ai attrapé / j'ai coupé ».
2. **Le serveur est la seule source de la géométrie des files.** Il diffuse ses miettes de chemin ; les clients dessinent les files des autres joueurs à partir de ces miettes. Ce que le joueur voit est ce que le serveur teste.
3. **Rien de physique n'est répliqué.** Nebbies, Gloomwisps, Comète et effets sont des pièces ancrées côté client. Les créatures sauvages bougent selon des fonctions déterministes du temps serveur (`SeededPath`).
4. **Accumulation paresseuse** du revenu passif : aucune boucle par seconde et par joueur.
5. **Contenu piloté par les données** : espèces, météos, événements, quêtes, prix sont des tables de `Shared/Config`.
6. **Réutiliser la base existante** (≈ 2 600 lignes testées) : `DataService` (verrou de session, migrations, réplication par patchs), `MonetizationService` (reçus idempotents), `Net`/`Remotes`, `Validate`, `RateLimit`, `Trove`, `Signal`, `Juice`, `Toast`, `Theme`, `Build`, `WorldFXController`, `Prices`, `Analytics`, harnais Lune avec pannes de DataStore injectables. Pas de ProfileStore : le `DataService` maison couvre déjà le verrou de session et il est testé.
7. `--!strict` partout, compatible `SignalBehavior = Deferred`, joueurs déjà présents traités au branchement de `PlayerAdded`, `WaitForChild` toujours avec délai, nettoyage par joueur avec `Trove`.

### 12.2 Arbre Rojo

```
default.project.json            (+ ReplicatedFirst, réglages Workspace/StarterPlayer ci-dessous)
src/
  first/            → ReplicatedFirst
    Loading.client.luau           écran de chargement en code
  shared/           → ReplicatedStorage.Shared
    Net.luau, Remotes.luau        (existant ; Remotes complété §12.5)
    Config/
      Balance.luau                économie, améliorations, Supernova, file, coupe, Dash, Comète, Balise
      Nebbies.luau                raretés, 36 espèces, formes, variantes, étoiles
      Zones.luau                  anneaux, probabilités, plafonds, intervalles, durées de vie
      Events.luau                 horloge, météos et poids, rotations, Starfall, Gloomwisps
      Quests.luau                 accueil, pool quotidien, hebdo, calendrier, jalons d'Atlas
      Cosmetics.luau              styles, auras, titres, thèmes, palette des Nids
      Monetization.luau           (existant, rempli : 6 passes, 6 produits, IDs à 0)
      Sounds.luau                 (existant, clés ajoutées, IDs vides)
    Logic/                        modules PURS (aucun service Roblox) testés sous Lune
      Formulas.luau               coûts, bonus, M, valeurs, revenu, hors ligne, plafonds
      Trail.luau                  (déjà écrit) miettes de chemin, position des nœuds (`sample`), coupe point à point (`findCut`) ;
                                  à compléter : distance segment-segment et test balayé (`findCutSwept`)
      SeededPath.luau             flânerie Lissajous, cordes des Gloomwisps, trajectoire de la Comète
      EventClock.luau             phase de chaque événement à l'instant t (UTC)
      Hash.luau                   PRNG entier (xorshift32 / splitmix) déterministe
      WorldLayout.luau            positions des Nids, portes, zones, grille d'apparition, hauteur du sol
      SnipRules.luau              ordre d'évaluation des règles de coupe (§4.7)
    Render/
      NebbyBuilder.luau           recettes de modèles (utilisé par le client)
    Localization/                 (existant) Strings.luau complété EN/FR
    Util/                         (existant) Format, Signal, Tables, Trove, Validate
  server/           → ServerScriptService.Server
    Main.server.luau              ordre d'initialisation (§12.3)
    Data/Schema.luau              schéma v1 (§12.6)
    Data/Codes.luau               codes promo (serveur uniquement)
    Data/Admins.luau              UserIds autorisés pour LiveOps
    Services/
      DataService.luau            (existant)
      MonetizationService.luau    (existant)
      WorldService.luau           construit l'île au démarrage avec World/Build
      NestService.luau            attribution des Nids, attributs de perchoirs, constellation
      EconomyService.luau         accumulation, hors ligne, M, améliorations, Supernova, boosts
      AtlasService.luau           collection, tri, réserve, verrous, libération, Starforge, Atlas
      SpawnService.luau           Nebbies sauvages et libres, apparitions personnelles
      CongaService.luau           tick 10 Hz : miettes, captures, coupes, parades, diffusion
      EventService.luau           météo, Comète, Balise, Frenzy, Gloomwisps, Starfall, LiveOps
      QuestService.luau           accueil, quotidiennes, hebdo, calendrier, codes, plafonds journaliers
      CrewService.luau            équipages, escorte, pings, acclamations, bannières, cadeau Duo
      ProductService.luau         effets des passes et produits (handlers MonetizationService)
      LeaderboardService.luau     tableau du serveur, OrderedDataStores hebdo et Atlas
    Util/
      RateLimit.luau, Analytics.luau  (existant)
      MoveCheck.luau              contrôle de déplacement
    World/Build.luau              (existant)
    World/Lighting.luau           (déjà écrit) valeurs d'éclairage de base posées au démarrage
  client/           → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau
    Controllers/
      StateController.luau        (existant) miroir du profil
      AudioController.luau        (existant)
      WorldFXController.luau      (existant) tags Spin/Float/Pulse
      WorldStateController.luau   miroir du monde : files, miettes (PathStream), sauvages, événements, équipages
      CongaRenderer.luau          rendu des files et des sauvages, niveaux de détail, BulkMoveTo
      VFXController.luau          effets du §9
      LightingController.luau     cycle de lumière et préréglages météo
      InputController.luau        ContextActionService, Dash, pings, raccourcis, type d'entrée
      OnboardingController.luau   accueil (empreintes, flèches, affichage progressif)
    UI/
      Root, Theme, Create, Juice, Toast   (existant)
      HUD.luau, Minimap.luau, Banners.luau
      Panels/ Upgrades.luau, Supernova.luau, Collection.luau, Goals.luau,
              Shop.luau, Crew.luau, Settings.luau, ReturnScreen.luau
    Util/Prices.luau              (existant)
tests/specs/                      §12.9
```

**Réglages du projet** : `Workspace.StreamingEnabled = true`, `StreamingMinRadius = 64`, `StreamingTargetRadius = 512`, `SignalBehavior = Deferred` ; `StarterPlayer.EnableMouseLockOption = false`, `CharacterWalkSpeed = 16`, `CharacterJumpHeight = 7,2` ; `Players.MaxPlayers` = 12 et « Server Fill » (remplissage maximal, 1 place réservée aux amis) se règlent dans le Creator Hub.

### 12.3 Ordre d'initialisation et tick serveur

`Main.server.luau` : `Net.setup()` puis `Init()` puis `Start()` dans cet ordre : DataService → MonetizationService → WorldService → NestService → EconomyService → AtlasService → SpawnService → EventService → CrewService → QuestService → ProductService → LeaderboardService → CongaService (dernier : il orchestre le tick).

**Tick de `CongaService`** (accumulateur sur `RunService.Heartbeat`, pas fixe de 0,1 s, au plus 3 pas rattrapés par image) :

```
1. now = workspace:GetServerTimeNow()
2. pour chaque joueur chargé avec personnage :
     MoveCheck.step(joueur, position HRP, dt) → valide ? ; mémoriser position précédente
     si valide : trail:push(position)   (module Trail, pas minimal 0,5 stud)
3. EventService.step(now)        transitions de phase (météo, Comète, Balise, Frenzy), positions des Gloomwisps
4. SpawnService.step(now)        apparitions dues, expirations
5. Captures                      joueurs avec place libre × Nebbies sauvages proches (grille spatiale de 16 studs)
6. Comète                        ramassage, vol (« chat perché »), encaissement, explosion
7. Coupes                        joueurs × files puis Gloomwisps × files (SnipRules + Trail)
8. Gloomwisps éclatés
9. Parades                       test des boîtes de porte (et anneau de la Balise)
10. Diffusion                    PathStream (non fiable), LineEvent / WildEvent / SnipEvent groupés
```

`EconomyService.settle` est appelé à chaque événement économique et toutes les 30 s par joueur (décalé selon l'index du joueur pour lisser la charge).

### 12.4 Réseau des files (« ce que tu vois est ce qui compte »)

- **Miettes serveur** : par joueur, un historique `Trail` (module pur existant) limité à 170 studs de chemin, pas minimal 0,5 stud (longueur utile maximale : 3 + 59 × 2,6 = 156,4 studs). Un saut de plus de 40 studs (téléportation, retour forcé de l'anti-triche) remet l'historique à zéro : la file se « redéroule » alors derrière le joueur. Le flux réseau sous-échantillonne l'historique à **un point par stud parcouru** et numérote ces points (séquence croissante).
- **Nœuds** : le nœud i est à l'abscisse curviligne `HeadGap + (i − 1) × Spacing` depuis le point le plus récent (`trail:sample(n, Spacing, HeadGap)`). Pas d'enroulement à l'arrêt : la forme d'une file ne dépend que du chemin.
- **Diffusion `PathStream`** (`UnreliableRemoteEvent`, 10 Hz, un `buffer` par message) : `u16 tick`, `u8 nbJoueurs`, puis par joueur `u8 slot` (index du Nid 1-12), `u32 seqPremier`, `u8 nbPoints`, premier point absolu (`i16 x×8`, `i16 y×8`, `i16 z×8`), points suivants en deltas (`i8 dx×16`, `i8 dy×16`, `i8 dz×16`). Chaque message répète les 2 derniers points du précédent : la perte d'un paquet isolé se répare seule. ≈ 25 octets par joueur en mouvement, ≈ 3 Ko/s par client avec 12 joueurs.
- **Trou détecté** (séquence manquante) : le client envoie `RequestPath(slot)` et reçoit `PathSnapshot` (fiable) avec les 200 derniers points.
- **Contenu des files** (espèce, forme, variantes de chaque nœud) : `LineEvent` fiable avec un numéro de version par file (`add`, `cut`, `bank`, `clear`). Version inattendue → `RequestWorld`.
- **Arrivée en cours de partie** : `WorldSnapshot` (files, miettes récentes, Nebbies sauvages, état des événements, équipages), ≈ 20 Ko une seule fois.
- **Rendu** : les files des **autres** joueurs sont dessinées depuis les miettes serveur. Le premier tronçon (tête → nœud 1) est raccordé à la position affichée du personnage s'il est chargé ; tous les nœuds coupables (au-delà de 3 + 2 × 2,6 = 8,2 studs) sont exactement sur le chemin serveur. La file **du joueur local** est dessinée depuis ses propres miettes locales (fluidité) : il ne peut pas se couper lui-même, et ses coupes subies sont confirmées par le serveur.
- **Streaming** : rien ne dépend des personnages des autres. Minicarte, niveaux de détail lointains, tableau et moments « visibles de partout » utilisent les miettes. Les personnages lointains peuvent sortir du rayon de streaming sans conséquence.
- **Test balayé** : à vitesse de Dash (≈ 3,6 studs par tick), le coupeur pourrait « sauter » par-dessus un segment ; on teste donc le segment [position précédente → actuelle] contre chaque segment coupable (distance segment-segment XZ). Le rayon généreux (2,8 + 0,3 tactile) absorbe le décalage de latence ; si le test à 250 ms échoue (§12.9), la v1.1 ajoute une compensation de latence (recul des nœuds de la victime le long de son chemin de `vitesse × ping/2`).
- **Sauvages** : `WildEvent` fiable groupé à 4 Hz : apparitions `{id u16, espèce, forme, variantes, ancre x/z, seed, t0, vie, étourdiJusqua?, prioritéSlot?}` et disparitions `{id, raison (capturé / expiré / éclaté), slot}`. Les apparitions `onlyFor` ne sont envoyées qu'au client concerné.

### 12.5 Remotes

Déclarés dans `Shared/Remotes.luau`, créés par `Net.setup()`. Chaque handler serveur suit l'ordre : débit (`RateLimit.allow`) → types (`Validate`, `math.isfinite`, entiers, longueur des chaînes, tables séquentielles bornées) → existence (clé de config) → état (profil chargé, personnage vivant, position) → règles métier → mutation atomique → réplication.

**Client → serveur**

| Remote | Type | Charge utile | Validation serveur | Débit max |
|---|---|---|---|---|
| `Dash` | Event | — | Profil chargé, pas porteur de Comète, recharge serveur écoulée | 3 / s |
| `BuyUpgrade` | Event | `track: string` | ∈ {conga, stride, lure, perches, guard} ; niveau < max ; règlement (`settle`) puis Glow ≥ coût | 10 / s |
| `Supernova` | Event | — | Glow ≥ coût ; dans le port sûr de son Nid (la file est encaissée d'abord) | 1 / 2 s |
| `Fuse` | Event | `uid: string` | ≤ 12 caractères ; possédé ; 2 autres identiques non verrouillés ; ★ < 5 ; Stardust ≥ coût | 6 / s |
| `FuseAll` | Event | — | — | 1 / 2 s |
| `Release` | Event | `uids: {string}` | Table séquentielle de 1 à 50 chaînes uniques ; toutes possédées, non verrouillées, non Cosmiques | 2 / s |
| `SetLock` | Event | `uid: string, locked: boolean` | Possédé | 6 / s |
| `ClaimDaily` | Event | — | Jour UTC différent du dernier réclamé | 1 / s |
| `ClaimQuest` | Event | `kind: string, slot: number` | kind ∈ {daily, weekly, onboarding} ; slot entier 1-3 ; quête terminée et non réclamée | 4 / s |
| `RerollQuest` | Event | `slot: number` | Entier 1-3 ; relance disponible ; quête non terminée | 1 / s |
| `CrewInvite` | Event | `userId: number` | Entier ; joueur présent, différent ; pas déjà équipiers ; équipage < 4 ; la cible accepte les invitations | 1 / 3 s et 5 / min |
| `CrewRespond` | Event | `inviterId: number, accept: boolean` | Invitation en attente et non expirée (20 s) | 2 / s |
| `CrewLeave` | Event | — | Dans un équipage | 1 / 5 s |
| `Ping` | Event | `kind: number` | Entier 1-6 | 1 / 1,5 s |
| `Cheer` | Event | `heroId: number` | Fenêtre d'acclamation ouverte pour ce héros ; pas déjà acclamé | 2 / s |
| `SetSetting` | Event | `key: string, value: boolean \| string` | Clé dans la liste ; type attendu ; `zen` : dans le port sûr et recharge de 60 s ; `lang` ∈ {auto, en, fr} ; `privateNoSnip` : propriétaire du serveur privé | 4 / s |
| `SetInputType` | Event | `kind: number` | Entier 1-3 (tactile, clavier-souris, manette) | 1 / 5 s |
| `EquipCosmetic` | Event | `kind: string, id: string` | Possédé (ou pass) | 2 / s |
| `RequestWorld` | Event | — | — | 1 / 2 s |
| `RequestPath` | Event | `slot: number` | Entier 1-12 | 4 / s |
| `RedeemCode` | Function | `code: string` → `status: string` | ≤ 20 caractères, mis en majuscules, `[A-Z0-9]` ; existe, non expiré, jamais utilisé par ce compte | 1 / 3 s et 10 / h |
| `RequestSnapshot` | Event | — | (existant) | (existant) |

Aucun `RemoteFunction` serveur → client. Les achats Robux passent par `MarketplaceService:Prompt…Purchase` côté client et `ProcessReceipt` / `PromptGamePassPurchaseFinished` côté serveur, sans remote du jeu.

**Serveur → client**

| Remote | Type | Charge utile | Destinataires |
|---|---|---|---|
| `DataSnapshot`, `DataPatch` | Event | Profil public / patchs (existant) | Le joueur |
| `PathStream` | Unreliable | `buffer` (§12.4) | Tous, 10 Hz |
| `PathSnapshot` | Event | `slot, seqPremier, buffer` | Le demandeur |
| `WorldSnapshot` | Event | Table complète (§12.4) | Arrivée, `RequestWorld` |
| `LineEvent` | Event | `{op, slot, ver, …}` | Tous |
| `WildEvent` | Event | `{spawns, despawns}` | Tous (ou un seul pour `onlyFor`), 4 Hz |
| `SnipEvent` | Event | `{snipperSlot, victimSlot, cutIndex, looseIds, byWisp}` | Tous |
| `EventState` | Event | `{weather, comet, beacon, frenzy, serverBoost, starfall, wisps}` | Tous, à chaque changement |
| `Banner` | Event | `{kind, args}` | Tous |
| `Feedback` | Event | `{key, vars, tone}` (refus, confirmations) | Le joueur |
| `Celebrate` | Event | `{kind, data}` (Supernova, Atlas, quête, jalon, Starforge) | Le joueur |
| `CrewState` | Event | `{crews = {{userIds}}}` | Tous |
| `CrewInvitePrompt` | Event | `{inviterId}` | La cible |
| `CheerPrompt` | Event | `{heroId, level}` | Tous sauf le héros |
| `PingShow` | Event | `{userId, kind}` | Tous |

### 12.6 Données sauvegardées (schéma v1)

Clé DataStore : celle du `DataService` existant (`player_<UserId>`), magasin `PlayerData_v1`. Le jeu n'étant pas publié, la v1 remplace le schéma d'exemple (`coins`).

```lua
Schema.VERSION = 1
Schema.PRIVATE_KEYS = { receipts = true, codes = true, flags = true }

function Schema.defaults()
  return {
    version = 1,
    -- économie (§4.9)
    glow = 0, glowCarry = 0, lastSettle = 0, lastOnline = 0,
    stardust = 0, supernovas = 0,
    upgrades = { conga = 0, stride = 0, lure = 0, perches = 0, guard = 0 },
    boosts = { personalUntil = 0 },                   -- os.time()
    -- collection (§4.13, §4.14)
    nebbies = {},  -- [uid: string] = { s = espèce 1-36, f = forme 0-5, v = bits (1 Golden, 2 Huge, 4 Starborn), st = étoiles 1-5, lk = verrou (bool) }
    nextUid = 1,
    atlas = { 0, 0, 0, 0, 0, 0, 0 },   -- 7 mots de 32 bits : bit (s − 1) × 6 + f
    badges = { 0, 0, 0, 0 },           -- Golden : bit s − 1 ; Huge : 36 + s − 1 ; Starborn : 72 + s − 1
    atlasRewards = 0,                  -- dernier jalon réclamé
    -- objectifs (§7)
    onboarding = { step = 0 },
    daily = { day = 0, step = 1 },                         -- jour UTC du dernier claim, prochain jour du calendrier
    quests = { day = 0, list = {}, rerolls = 0, starClaimed = false },  -- list = { { id, p, done, claimed } × 3 }
    weekly = { week = 0, banked = 0, claimed = false },
    caps = { day = 0, snipDust = 0, wispDust = 0, cheers = 0, duo = false },
    rookie = { sessions = 0, playSeconds = 0, done = false },
    -- social et cosmétiques
    settings = { zen = false, reducedMotion = false, lowGraphics = false, music = true, sfx = true,
                 autoCrew = true, refuseInvites = false, lang = "auto" },
    cosmetics = { style = "default", title = "", nestTheme = "default" },
    unlocks = { styles = {}, titles = {}, themes = {} },
    weeklyBest = { week = 0, conga = 0 },
    starterKit = false,
    stats = { catches = 0, parades = 0, longestParade = 0, snipsDealt = 0, nebbiesSnipped = 0,
              snipsTaken = 0, cometsHeld = 0, cometsBanked = 0, beaconWins = 0, wispsPopped = 0,
              cheersGiven = 0, cheersReceived = 0, escortSeconds = 0, playSeconds = 0,
              sessions = 0, lastCrewDay = 0, fusions = 0 },
    -- existant / privé
    passes = {}, receipts = {}, codes = {}, flags = { strikes = 0, lbBanned = false },
  }
end
```

- **Taille** : au plus 646 Nebbies (46 perchés + 600 en réserve) × ≈ 45 octets ≈ 29 Ko ; profil complet < 50 Ko.
- **Règles** : les monnaies sont des entiers ; `glowCarry` ∈ [0 ; 1[ ; après chaque mutation, invariants vérifiés en développement (jamais négatif, jamais NaN, perchés ⊂ nebbies).
- **Migrations** : `Schema.migrate(data, from)` applique les étapes dans l'ordre, chacune pure et testée sur une sauvegarde-témoin de la version précédente (`tests/fixtures/profiles/v<n>.json`). On n'efface jamais un champ dans la version qui le remplace ; `reconcile` ajoute les nouveaux champs avec leur valeur par défaut. La disposition des bits de l'Atlas réserve déjà 36 espèces × 6 formes : la v1.1 (Eclipse, 6 espèces) ne demande **aucune** migration.
- **Échec de chargement** : jamais de profil par défaut sauvegardé par-dessus (comportement existant du `DataService`) ; l'écran « Réessayer » s'affiche.
- **Sauvegarde** : automatique toutes les 90 s, au départ, à la fermeture (`BindToClose` en parallèle), et immédiate après un achat Robux (existant). `settle` est appelé avant chaque sauvegarde.

### 12.7 Anti-triche

| Menace | Parade |
|---|---|
| Vitesse, téléportation | `MoveCheck` : déplacement XZ autorisé par tick = `vmax × dt × 1,5 + 4`, avec `vmax` = WalkSpeed serveur maximal des 0,5 dernières secondes. Montée verticale ≤ 12 studs/s ; chute libre ignorée. Une infraction **signale seulement** : ce tick ne peut ni attraper, ni couper, ni encaisser. 3 infractions en 5 s → retour à la dernière position valide (`PivotTo`), 3 s sans capture/coupe/parade, icône « connexion instable » (ton neutre, jamais d'accusation). Exemptions : 3 s après une apparition ou un `PivotTo` serveur |
| Vol, passe-muraille | Altitude > sol + 14 pendant plus de 1,5 s, r > 182 ou Y < −5 → retour à la dernière position valide |
| WalkSpeed modifié en local | Sans effet : seul le déplacement mesuré compte (ligne ci-dessus) |
| Bots de coupe ou de ferme (trajets scriptés) | Impossible à exclure totalement en code seul : plafonds journaliers de Stardust, recharges par paire, plafond de pertes par victime, 1 500 captures/h max, exclusion des classements après 10 retours forcés en 10 min, événement analytique pour revue. Les dégâts sur les autres restent bornés par le §4.16 |
| Remotes abusifs | Validation + seau à jetons par action (§12.5), vidé au départ du joueur |
| Valeurs envoyées par le client | Aucune valeur économique n'est acceptée. Seul le type d'entrée est déclaratif (+0,3 stud au plus) |
| Lecture de secrets | Codes, administrateurs et logique anti-triche dans `ServerScriptService` uniquement |
| Achats | `ProcessReceipt` unique et idempotent ; passes vérifiés à l'arrivée et à l'achat (existant) |
| Duplication | Aucun échange au MVP ; toutes les mutations de collection se font sur le profil d'un seul joueur, sous verrou de session |

### 12.8 Budget de performance

Appareil de référence : téléphone Android bas de gamme (≈ 3 Go de RAM). L'émulateur de Studio ne mesure pas la mémoire réelle : les tests se font sur un vrai appareil.

| Ressource | Budget |
|---|---|
| Images par seconde | 60 stables visés, jamais moins de 30 avec 12 joueurs et 12 files de 60 |
| Pièces de la carte | ≤ 3 000 (prévu ≈ 2 000-2 500) |
| Pièces de Nebbies rendues | ≤ 1 500 ; ≤ 100 Nebbies en détail complet (8 pièces), le reste en une Ball ou masqué |
| Mise à jour des files | Un seul `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` par image ; files lointaines (> 120 studs) mises à jour à 20 Hz |
| Lumières actives | ≤ 40 : 24 lanternes, 6 cristaux, 2 Balise, 1 Nid local, ≤ 6 Légendaires+ les plus proches, Comète |
| `Highlight` | ≤ 12 (limite moteur 31) : porteur de Comète 1, files ≥ 20 les plus proches 4, Mythiques+ les plus proches 6, réserve 1 |
| Particules à l'écran | ≤ 300 ; émetteurs réutilisés |
| Serveur | Tick de 10 Hz < 2 ms en moyenne (12 joueurs, 12 files de 60, 74 sauvages, 5 Gloomwisps), élagage par boîtes englobantes ; aucune autre boucle par image |
| Réseau entrant par client | ≤ 6 Ko/s en moyenne (dont `PathStream` ≈ 3 Ko/s) ; pic < 30 Ko/s (instantané d'arrivée) |
| Mémoire client | < 900 Mo (console développeur) |
| DataStore | Autosave 90 s ; écritures de classement groupées par minute (budget 2026 : 300 + 20 × CCU écritures/min) |

### 12.9 Tests et portes de qualité

**Tests Lune** (`tests/specs/`, lancés par `scripts/check.sh` avec StyLua, Selene, build Rojo et vérification de la place) :

| Fichier | Couvre |
|---|---|
| `Formulas.spec` | Coûts, bonus, M, valeurs, revenu, hors ligne ; invariants (jamais négatif ni NaN, `floor`) |
| `Trail.spec` | Insertion des miettes (pas 0,5 stud, remise à zéro au-delà de 40 studs), position du nœud i, distance segment-segment, test balayé à 3,6 studs/tick qui ne rate aucun segment, sous-échantillonnage réseau à 1 stud |
| `SnipRules.spec` | Chaque règle du §4.7 isolément et combinée : trêve, équipiers, Zen, bouclier, immunité, plafond par minute, recharges, port sûr, escorte, plafond par coupe, Gloomwisps |
| `SeededPath.spec` | Déterminisme, amplitude ≤ 1,6, cordes des Gloomwisps dans l'île |
| `EventClock.spec` | Phases à des instants clés (minuit, :25, :55, samedi 16:00 et 16:20) ; répartition des météos sur 100 000 créneaux à ±1 % des poids |
| `Hash.spec` | Valeurs de référence (identiques sous Lune et sous Roblox) |
| `Schema.spec` | Valeurs par défaut, `reconcile`, migrations depuis les sauvegardes-témoins |
| `Remotes.spec` | Chaque handler reçoit des charges malveillantes (NaN, ±inf, mauvais types, tables énormes, uid d'un autre joueur, débit excessif) → aucune mutation |
| `Economy.spec` | Améliorations, Supernova, Starforge, libération, réserve pleine, produits (rejeu de `ProcessReceipt`) |
| `Quests.spec` | Tirage déterministe, filtres JcJ et Équipage, remises à zéro UTC, calendrier en pause |
| `EconomyPacing.spec` | Simulation du §4.18 (porte bloquante) |
| `DataService.spec`, `MonetizationService.spec` | Existants, étendus au nouveau schéma (pannes de DataStore injectées) |

**Tests en jeu** (Studio « Clients and Servers », 4 à 8 clients) : latence simulée de 250 ms (réglage de réplication de Studio) pour la justesse des coupes **dès la semaine 2 de production**, pas à la fin ; session de 30 min sans erreur dans la sortie ; puis test de charge à 12 joueurs sur un vrai Android bas de gamme.

### 12.10 Budget de lignes

| Bloc | Modules (lignes estimées) | Total |
|---|---|---|
| Base réutilisée | DataService, MonetizationService, Net, Juice, Build, Toast, Theme, utilitaires, contrôleurs existants | ≈ 2 400 |
| Shared (logique) | Formulas 110, Trail 200 (dont 160 déjà écrits), SeededPath 60, EventClock 110, Hash 30, WorldLayout 90, SnipRules 80, NebbyBuilder 240 | 920 |
| Serveur | Schema 60, WorldService 320, NestService 140, EconomyService 280, AtlasService 160, SpawnService 180, CongaService 480, MoveCheck 60, EventService 360, QuestService 220, CrewService 200, ProductService 100, LeaderboardService 50, Main 20 | 2 630 |
| Client | Loading 50, WorldStateController 180, CongaRenderer 340, VFXController 300, LightingController 90, InputController 80, OnboardingController 80, HUD 220, Minimap 70, Banners 60, panneaux 600 | 2 070 |
| **Total code** | | **≈ 8 000** (8 020) |
| Hors budget | Données de config et textes EN/FR (≈ 1 100 lignes), tests Lune (≈ 1 300 lignes) | — |

**Ligne de coupe** (retirée dans cet ordre si le budget dérape, ≈ 450 lignes) : classement mondial hebdomadaire (−50), Starborn de Starfall Saturday (−40), acclamations (−60), constellations des Nids (−50), invitations d'équipage hors amis (−70), minicarte remplacée par des flèches de bord d'écran (−40), codes promo (−50), pass Conga Styles (−60), quête hebdomadaire (−30). Le cœur (capture, file, coupe et ses protections, parade, Supernova, Comète, Balise, Gloomwisps, Mode Zen) n'est jamais coupé.

---

## 13. Localisation et accessibilité

### 13.1 Langues

- **Détection** : `Localization.languageFor(player.LocaleId)` (module existant) : `fr-*` → français, sinon anglais. Réglage « Langue » (Auto / English / Français) prioritaire.
- **Toutes les chaînes** dans `Shared/Localization/Strings.luau`, clés `domaine.nom`, variables `{n}`. Anglais et français écrits à la main. Les autres langues : affichage anglais avec `AutoLocalize = true` pour que la traduction automatique de Roblox (17 langues) prenne le relais sur les textes capturés ; l'interface très iconique limite la dépendance au texte.
- **Nombres** : `Format.abbreviate(n, lang)` étendu : EN « 1.24M », FR « 1,24 M » ; séparateur des milliers : virgule (EN), espace insécable (FR).
- **Longueur** : le français est ≈ 25 % plus long : chaque texte a `TextScaled` + `UITextSizeConstraint`, et les écrans sont vérifiés en français.

| Terme | EN | FR |
|---|---|---|
| Nebby, Nest, Glow, Stardust, Supernova, Starforge, Star Atlas, Gloomwisp, Lead Trio, Guard Links, Comet Conga, Lumora | identiques (noms propres de l'IP) | identiques |
| Parade | Parade | Parade |
| Snip | SNIP! | SNIP ! |
| Upgrades / Stride / Lure / Perches / Stash | Upgrades / Stride / Lure / Perches / Stash | Améliorer / Foulée / Attrait / Perchoirs / Réserve |
| Great Comet / Beacon Night / Calm mode / Rookie Shield / Crew | Great Comet / Beacon Night / Calm Mode / Rookie Shield / Crew | Grande Comète / Nuit de la Balise / Mode Zen / Bouclier débutant / Équipage |

### 13.2 Accessibilité

| Besoin | Réponse |
|---|---|
| Daltonisme | Rareté = couleur **et** aura / forme (§4.2) ; segments coupables = anneau **et** contour pointillé ; équipiers = étoile au-dessus de la tête |
| Sensibilité au mouvement | Mouvement réduit (§9.1) ; aucun flash répété au-dessus de 3 Hz |
| Lecture difficile / jeunes enfants | Accueil sans texte long, icônes, 4 mots maximum par consigne |
| Jeu sans son | Tout retour est d'abord visuel ; sons optionnels désactivables séparément (musique, effets) |
| Motricité | Jouable à une main sur téléphone (joystick + Dash) ; aucun appui maintenu sauf la confirmation de Supernova (1 s) ; cibles ≥ 56 px |
| Stress de la compétition | Mode Zen, serveurs privés sans coupe, bouclier débutant |
| Menus ouverts hors du Nid | Le jeu continue (multijoueur) : quand un panneau est ouvert hors du port sûr, un contour rose de l'écran prévient si un non-équipier approche de la file |
| Appareils modestes | Graphismes légers, niveaux de détail, budgets du §12.8 |

---

## 14. Analytics

Tout passe par `Server/Util/Analytics` (existant, appels protégés par `pcall`). Champs personnalisés (3 au maximum) pour segmenter : `inputType` (tactile / clavier / manette), `serverBand` (1-4, 5-8, 9-12 joueurs), `sessionBand` (1re session, sessions 2-5, 6+).

### 14.1 Entonnoir d'accueil (`LogOnboardingFunnelStepEvent`)

| Étape | Nom | Déclencheur |
|---|---|---|
| 1 | Loaded | Profil chargé et personnage sur le Nid |
| 2 | FirstCatch | Première capture |
| 3 | FirstParade | Première parade (première récompense) |
| 4 | FirstUpgrade | Premier achat d'amélioration |
| 5 | Parade4 | Q1 terminée |
| 6 | Parade6 | Q3 terminée |
| 7 | AtlasUnlocked | Premier Rare encaissé |
| 8 | StrideBought | Q5 terminée |
| 9 | FirstEvent | Q6 terminée |
| 10 | FirstSupernova | Première Supernova |

### 14.2 Économie (`LogEconomyEvent`)

| Flux | Monnaie | `itemSku` | Type de transaction |
|---|---|---|---|
| Source | Glow | `Parade`, `ParadeBeacon`, `Idle` (cumulé, un événement par tranche de 5 min), `Offline`, `Comet`, `Wisp`, `Quest_<id>`, `Login_D<n>`, `Code_<code>`, `Product_<clé>` | Gameplay, TimedReward, Onboarding, IAP |
| Puits | Glow | `Upgrade_<piste>_<niveau>`, `Supernova_<R>` | Shop, Gameplay |
| Source | Stardust | `Release_<rareté>`, `Snip`, `Wisp`, `Comet`, `Beacon`, `Quest_<id>`, `Login_D<n>`, `Cheer`, `Duo`, `Product_StardustJar` | Gameplay, TimedReward, IAP |
| Puits | Stardust | `Starforge_<★>` | Shop |

### 14.3 Événements personnalisés (`LogCustomEvent`)

| Événement | Valeur | Question à laquelle il répond |
|---|---|---|
| `SnipDealt` / `SnipReceived` | Nebbies détachés | Fréquence et ampleur des coupes |
| `PostSnipQuit` | Secondes entre la coupe et le départ (si < 60) | **Indicateur de frustration n°1** |
| `SnipByInput` | 1 par coupe, segmenté par `inputType` | Le tactile est-il désavantagé ? |
| `ParadeLength` | n | Prise de risque réelle |
| `CometHeld` / `CometBanked` / `CometBurst` | Secondes / 1 / 1 | Équilibre de la Comète |
| `BeaconResult` | 1 réussite / 0 échec | Calibrage de l'objectif |
| `WispPopped` / `WispSnip` | 1 / Nebbies détachés | Utilité des Gloomwisps |
| `ZenToggled` | 1 activé / 0 désactivé | Qui fuit la compétition ? |
| `RookieShieldEnded` | Minutes jouées | Durée réelle du bouclier |
| `SupernovaReached` | R | Rythme réel vs §4.18 |
| `MoveViolation` | Nombre d'infractions dans la session | Faux positifs de l'anti-triche |
| `SessionLength` | Minutes (au départ) | Durée de session |
| `CrewFormed` | Taille | Co-play |

### 14.4 Seuils d'alerte et actions

| Signal | Seuil | Action (par la configuration) |
|---|---|---|
| `PostSnipQuit` / coupes subies | > 8 % | Immunité 8 → 12 s, plafond par coupe 35 → 25 %, mise en avant du Mode Zen |
| Écart de réussite des coupes tactile vs clavier | > 25 % | `TouchAssist` 0,3 → 0,6 |
| Réussite de la Balise | < 65 % ou > 90 % | Objectif par joueur 10 ± 2 |
| Perte entre étapes 2 et 3 de l'accueil | > 10 % | Raccourcir la distance des Puffkins, renforcer le guidage |
| Médiane de la Supernova 1 | hors 20-35 min | `Supernova.Costs[1]` |
| `MoveViolation` chez des joueurs honnêtes (signalements) | > 1 % des sessions | Marge de `MoveCheck` 1,5 → 1,8 |

---

## 15. MVP et feuille de route

### 15.1 v1.0 : ce qui est livré au lancement

- **Monde** : l'île, 3 zones, 12 Nids, la Balise, chemins et décor, construits entièrement en code ; cycle d'éclairage et 5 préréglages météo.
- **Contenu** : 30 espèces ; formes Aurora, Frozen, Blazing, Prismatic ; variantes Golden, Huge, Starborn ; météo Meteor Shower.
- **Boucle cœur** : capture sans bouton, file, Conga Bonus, ralentissement, Dash, coupe (test balayé, toutes les règles et plafonds du §4.7), dispersion, Second Souffle, Snip Rush, port sûr, parade.
- **Progression** : 5 améliorations, perchoirs à tri automatique, réserve et verrous, libération, Starforge ★2-★5, Supernova avec aperçu, Atlas avec jalons et onglet Guide (probabilités), gains hors ligne, revenu passif paresseux.
- **Événements** : météo toutes les 6 min, Grande Comète toutes les 10 min, Nuit de la Balise + Starfall Frenzy + Nuit d'Or, Gloomwisps sur les petits serveurs, Starfall Saturday automatique, déclenchement LiveOps par les administrateurs.
- **Protection** : bouclier débutant toute la première session, Mode Zen, serveurs privés sans coupe.
- **Rétention et social** : chaîne d'accueil Q1-Q7, calendrier de 7 jours indulgent, 3 quêtes du jour (pool de 25), quête hebdomadaire, codes ; équipages (amis automatiques + invitations) avec escorte, Nids voisins, cadeau Duo, roue de pings, minicarte, bannières, acclamations, constellations, tableau du serveur, 2 classements mondiaux.
- **Monétisation** : 6 passes, 6 produits, prix lus à l'exécution, reçus idempotents.
- **Technique** : profil v1 et migrations, `MoveCheck`, analytics complètes (§14), réglages (Zen, Mouvement réduit, Graphismes légers, musique, effets, langue), EN/FR.

### 15.2 Portes de qualité avant le lancement public

1. `scripts/check.sh` vert (StyLua, Selene, tests Lune dont `EconomyPacing`, build, vérification de la place).
2. Test de justesse des coupes à 250 ms de latence simulée : sur 100 traversées franches filmées, ≥ 95 coupes confirmées, et aucune coupe accordée à plus de 3,5 studs de distance visible.
3. 12 joueurs pendant 30 min sur un Android bas de gamme : ≥ 30 images/s en permanence, mémoire < 900 Mo, aucune erreur.
4. Exercices DataStore : échec de chargement (rien n'est sauvegardé), arrêt du serveur (`BindToClose` sauvegarde tout), rejeu de `ProcessReceipt` (aucun double crédit).
5. Playtest discret avec 10-20 joueurs (dont des moins de 13 ans accompagnés) : abandon après coupe < 5 %, accueil compris sans aide.
6. Questionnaire de maturité rempli (cible Minimal), traduction automatique activée, Experience Event du samedi déclaré, icône et vignettes capturées en jeu (§16, risque 8).
7. Recherche de nom et de marque pour « Comet Conga » et « Nebbies » (§16, risque 7).

### 15.3 Après le lancement (publication le samedi à 17:00 UTC)

| Quand | Version | Contenu |
|---|---|---|
| Chaque semaine | — | Starfall Saturday (espèce vedette en rotation), code promo, réglages issus des analytics |
| **Semaine 2** | v1.1 « Éclipse » | Météo et forme **Eclipse** (×4) et les **6 espèces** réservées → Atlas à 216 entrées ; **Œufs de Comète** (2 couveuses dans l'observatoire, espèce connue d'avance, éclosion en 4 h réelles, gagnés en réussissant une Balise ou en tenant la Comète) ; **boutique de l'Observatoire** (4 emplacements déterministes, réassort toutes les 4 h UTC, payée en Stardust) ; compensation de latence des coupes si la porte 2 a été juste |
| **Semaine 4** | v1.2 « Saison 1 » | **Star Path** gratuit de 30 paliers sur 28 jours (XP par quêtes et événements ; cosmétiques, Stardust, Nebbies d'espèces fixes ; pas de piste payante) ; **décorations de Nid** et « J'aime » des Nids (Star Rep) ; bouton **REGARDER** sur les bannières (caméra vers le joueur 3 s) ; événement d'hiver (préréglages Frostfall) |
| **Semaine 6** | v1.3 | 4 espèces ; nouvelle météo saisonnière ; vidéo récompensée facultative si ≥ 2 000 visiteurs mensuels et `AreAdsAllowed` |
| **Semaine 8** | v1.4 « Amis » | **Dons entre amis** de Nebbies Commun à Épique (sens unique, 3/jour, même serveur) avec un **journal de séquestre en deux phases** (retrait marqué « en transit » chez le donneur, crédit chez le receveur, confirmation, reprise automatique au chargement si une phase manque) — seulement si les KPI de co-play le justifient ; deuxième constellation de prestige (R13-R24) ; premier **Encore** annoncé |
| Chaque mois | — | Événement à thème (préréglages d'éclairage, météo, cosmétiques), uniquement par la configuration |

---

## 16. Risques et parades

| # | Risque | Probabilité / impact | Parades | Indicateur |
|---|---|---|---|---|
| 1 | **Frustration des coupes** (surtout chez les moins de 13 ans), qui ferait chuter la rétention J1 | Moyenne / fort | Rien d'encaissé n'est perdu ; Lead Trio et Guard Links ; bouclier toute la 1re session ; plafonds par coupe et par minute ; immunité 8 s ; priorité de reprise ; Second Souffle ; port sûr ; trêves ; Mode Zen ; équipages ; serveurs privés | `PostSnipQuit` (§14.4) |
| 2 | **Litiges « je l'ai touché ! »** à forte latence | Moyenne / moyen | Le serveur est la seule source de la géométrie ; test balayé ; rayon généreux ; effets seulement après confirmation ; test à 250 ms dès la semaine 2 de production ; compensation de latence prête pour la v1.1 | Porte 2 du §15.2 |
| 3 | **Performances** avec 12 longues files sur téléphone modeste | Moyenne / fort | Niveaux de détail, `BulkMoveTo`, plafond de 60, rendu client, budgets du §12.8, Graphismes légers | Porte 3 ; images/s par appareil |
| 4 | **Équilibre de l'économie** (blocage ou inflation) | Moyenne / moyen | Tables de configuration, simulation bloquante, analytics des sources et puits | Médianes des jalons du §4.18 |
| 5 | **Dépendance au live-ops** | Forte / fort | Contenu par configuration, événements automatiques, cadence de 2 semaines tenable ; l'équipe doit s'engager sur plusieurs mois | Calendrier tenu |
| 6 | **Serveurs peu peuplés** sans poursuite | Moyenne / moyen | Gloomwisps dès le MVP, Comète et météo amusantes en solo, « Server Fill » au maximum ; jamais de faux joueurs | `serverBand`, rétention par bande |
| 7 | **Nom et marque** non vérifiés (« Comet Conga », « Nebbies ») | Inconnue / fort | Recherche Roblox et marques avant publication ; noms de repli : *Conga Comets*, *Nebby Parade* | Porte 7 |
| 8 | **Visuels de découverte** (icône, vignettes) hors du pipeline en code | Certaine / moyen | Commande de développement « Photo » (caméra, éclairage et files mis en scène en jeu) pour capturer les images ; téléversement manuel dans le Creator Hub | Taux de clic (play-through) |
| 9 | **Bots de coupe ou de ferme** (trajets scriptés) | Moyenne / moyen | Plafonds, recharges par paire, pertes bornées par victime, exclusion des classements, revue des journaux | `MoveViolation`, signalements |
| 10 | **Dérive des règles de Roblox** (objets aléatoires, publicités, catalogues Kids/Select) | Faible / fort | Aucun aléatoire payant, probabilités gratuites affichées, revue des règles à chaque version, questionnaire de maturité à jour | Revue mensuelle |
| 11 | **Plafond de revenus** d'une monétisation juste | Certaine / moyen | Assumé : rétention et confiance d'abord ; Glow Party sociale, passes clairs | ARPDAU vs repères |
| 12 | **Fin de la vague « vol/collection »** | Moyenne / moyen | IP propre, profondeur de collection et coopération qui survivent à la tendance ; chiffres de marché seulement indicatifs (écarts jusqu'à ×2, Rapport §1) | CCU, rétention J30 |
| 13 | **Faux positifs de l'anti-triche** (saccades, mauvais réseau) | Moyenne / moyen | Signaler avant de ramener ; 3 infractions en 5 s ; ton neutre ; marges réglables | `MoveViolation` |
| 14 | **Dépassement du budget de code** | Moyenne / moyen | Base réutilisée, ligne de coupe préparée (§12.10), cœur protégé | Lignes par module chaque semaine |

---

## Annexe A. Corrections apportées au concept après le jury

Détail des notes et justifications : [`03-decision-du-jury.md`](03-decision-du-jury.md).

| Défaut relevé | Correction dans ce GDD |
|---|---|
| Frustration des coupes, bouclier trop court (8 min) | Bouclier débutant **toute la première session** puis jusqu'à 30 min cumulées ; plafonds par coupe (35 %) et par minute (2 coupes) ; immunité 8 s ; priorité de reprise ; Mode Zen (§4.7, §4.16) |
| Serveurs de 2-4 joueurs sans drame | **Gloomwisps dans le MVP**, nombre inversement proportionnel à la population ; remplissage maximal des serveurs (§4.15.4) |
| Géométrie client/serveur divergente, streaming des personnages | Le serveur diffuse ses miettes de chemin (module `Trail`) ; les clients dessinent les files des autres à partir d'elles ; aucune dépendance aux personnages chargés (§12.4) |
| Spirale à l'arrêt qui casse l'hypothèse « le décalage reste le long du chemin » | **Spirale supprimée** : danse sur place, la file reste sur le chemin (§4.6) |
| Dash plus rapide que le rayon de coupe par tick | **Test balayé** segment contre segment (§4.7, §12.4) |
| Retour en arrière de l'anti-triche trop agressif | Signaler d'abord, ramener après 3 infractions en 5 s, exemptions, marges réglables (§12.7) |
| Bots de trajets scriptés | Plafonds journaliers, recharges par paire, pertes par victime bornées, exclusion des classements (§4.17, §12.7) |
| Pass « Long Conga » perçu comme payer pour gagner | **Supprimé**, remplacé par Stash Plus (réserve) (§8.2) |
| Récompense d'invitation (risque de politique) | Remplacée par des récompenses de **jeu ensemble** (bonus d'équipage, cadeau Duo) (§6.2) |
| Asymétrie tactile / clavier dans les poursuites | Aide tactile +0,3 stud, Dash au pouce, mesure par type d'entrée et seuil d'action (§4.7, §14.4) |
| Combinatoire des règles | Un module pur `SnipRules` avec un ordre d'évaluation unique et testé règle par règle (§4.7, §12.9) |
| Périmètre trop large pour ≈ 7 400 lignes nouvelles | Base existante réutilisée, Œufs/boutique/Star Path/décorations/« Regarder »/dons déplacés en v1.1-v1.4, ligne de coupe chiffrée (§12.10, §15) |
| Comète transmise par la coupe de la file (complexe) | Comète transmise par **contact avec le porteur** (« chat perché »), simple test de proximité (§4.15.2) |
