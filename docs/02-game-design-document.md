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
