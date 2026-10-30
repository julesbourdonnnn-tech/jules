# Décision du jury de validation (greenlight)

> **Document 03 : choix du concept.** Date : 30 octobre 2026.
> Entrée : l'étude de marché [`01-analyse-marche.md`](01-analyse-marche.md). Sortie : le GDD [`02-game-design-document.md`](02-game-design-document.md), qui intègre les corrections exigées ci-dessous.

## 1. Méthode

- **Trois concepts finalistes**, tous originaux, tous construisibles en code avec Rojo, sans modèle, image, animation ni son importés :
  - **Comet Conga** : collection et poursuite sociale. On mène une file de bébés comètes (Nebbies) qu'on encaisse à son Nid ; les autres peuvent couper la queue de la file.
  - **Glowkeepers** : collection cosy de créatures de lumière (Glowbs), revenu passif, nuit coopérative (« la Hush ») contre de petites ombres (Murklings).
  - **Bloop Isles** : fusion et revenu passif sur son île (Bloops), baleine céleste à nourrir ensemble, tempêtes à éclater, prestige en constellations.
- **Trois juges**, chacun avec un angle différent :
  - **Juge 1 — Marché et édition** : potentiel de découverte, de CCU et de rétention selon l'algorithme 2026.
  - **Juge 2 — Direction technique** : faisabilité sans bug, réseau, sécurité, périmètre de code, réutilisation de la base existante.
  - **Juge 3 — Joueur** : plaisir réel d'un joueur de 10 à 16 ans sur téléphone, au jour 1 comme au jour 7.
- **Six critères notés sur 10** : adéquation au marché, plaisir de jeu, rétention, monétisation, faisabilité sans bug, originalité et conformité. Le comité a calculé un **total pondéré** sur les trois juges (les poids favorisent légèrement les critères de marché, de plaisir et de rétention) ; la somme brute et la moyenne sont données à titre de contrôle et donnent le même ordre.

## 2. Classement

| Rang | Concept | Total pondéré (3 juges) | Somme brute (/180) | Moyenne (/10) |
|---|---|---|---|---|
| **1** | **Comet Conga** | **154,1** | 136,0 | 7,56 |
| 2 | Bloop Isles | 143,1 | 126,0 | 7,00 |
| 3 | Glowkeepers | 138,5 | 122,0 | 6,78 |

**Décision : Comet Conga est retenu**, sous réserve des corrections obligatoires du §6, toutes intégrées au GDD.

## 3. Notes détaillées

### 3.1 Par juge

| Concept | Juge | Marché | Plaisir | Rétention | Monétisation | Faisabilité | Originalité / conformité | Somme |
|---|---|---|---|---|---|---|---|---|
| Comet Conga | J1 Marché | 9 | 8,5 | 8 | 7 | 6 | 8 | 46,5 |
| Comet Conga | J2 Technique | 8 | 8,5 | 8 | 7 | 4,5 | 7,5 | 43,5 |
| Comet Conga | J3 Joueur | 8 | 9 | 8 | 7 | 6 | 8 | 46,0 |
| Glowkeepers | J1 Marché | 6,5 | 6 | 8,5 | 6,5 | 7,5 | 7 | 42,0 |
| Glowkeepers | J2 Technique | 7,5 | 6,5 | 8 | 7 | 6,5 | 6,5 | 42,0 |
| Glowkeepers | J3 Joueur | 7 | 6 | 8 | 5 | 6 | 6 | 38,0 |
| Bloop Isles | J1 Marché | 5 | 6,5 | 6 | 8 | 9 | 8,5 | 43,0 |
| Bloop Isles | J2 Technique | 6 | 6,5 | 5,5 | 6,5 | 9 | 8,5 | 42,0 |
| Bloop Isles | J3 Joueur | 6 | 6 | 6 | 7 | 9 | 7 | 41,0 |

### 3.2 Moyenne par critère

| Critère | Comet Conga | Glowkeepers | Bloop Isles |
|---|---|---|---|
| Adéquation au marché | **8,33** | 7,00 | 5,67 |
| Plaisir de jeu | **8,67** | 6,17 | 6,33 |
| Rétention | 8,00 | **8,17** | 5,83 |
| Monétisation | 7,00 | 6,17 | **7,17** |
| Faisabilité sans bug | 5,50 | 6,67 | **9,00** |
| Originalité et conformité | 7,83 | 6,50 | **8,00** |

**Lecture.** Comet Conga gagne nettement sur le marché et le plaisir, et fait jeu égal en rétention. Son point faible est la faisabilité (5,5, et 4,5 pour le juge technique) : c'est là que portent l'essentiel des corrections. Bloop Isles est de loin le plus sûr à construire, mais le plus faible sur le marché, la rétention et le social. Glowkeepers a la meilleure architecture de rétention mais peu de tension et une faute de conformité (chance payante).

## 4. Justifications des juges

### 4.1 Comet Conga

- **J1 Marché (46,5).** Le meilleur pour la découverte et la croissance du CCU. C'est le seul concept qui garde intacte la formule des records 2025-2026 (collecte, revenu passif, amélioration, renaissance, conflit social, « ramener chez soi ») tout en changeant le verbe : on coupe des files au lieu de piller des bases, ce qui évite le terrain des procès de Spyder Games. Le déplacement est l'entrée principale, idéal sur Roblox et sur mobile (un joystick + Dash). Les clips sont prévus dès la conception : coupes et mêlées, Comète « patate chaude » avec faisceau visible de partout, files de 50 Nebbies, Supernovas, tous adaptés à l'onglet Moments. Le risque est choisi par le joueur (« tu ne perds que ce que tu portes »). Rétention solide (hors ligne, série indulgente, Atlas de 216 entrées, Starforge, Supernovas, cadence de 10 et 30 min qui pousse les sessions au-delà de 15 min, rendez-vous du samedi). Points perdus : la frustration des coupes peut augmenter l'abandon en première session chez les moins de 13 ans, le signal le plus pesé par l'algorithme, et la poursuite retombe sur des serveurs de 2 à 4 joueurs. Monétisation juste mais plus mince. Faisabilité la plus faible des trois : miettes de chemin reproduites sur le serveur et chaque client, test de coupe à 10 Hz, anti-triche par retour en arrière, escorte et transfert de Comète forment la surface la plus exposée aux désynchronisations. Construisible, à condition de couper fort dans le MVP et de tester à 250 ms de latence avant le lancement.
- **J2 Technique (43,5).** Le meilleur jeu sur le papier : un verbe physique et identitaire, une Comète qui fait d'excellents clips, la boucle la plus proche de ce qui a marché, et rien d'encaissé ne se perd. Mais c'est de loin la construction la plus risquée, et l'estimation de 7 400 lignes oublie le plus dur. (1) **Streaming** : avec un rayon de 64 studs, les personnages lointains sortent du streaming ; les clients ne peuvent plus enregistrer leurs miettes, et les nouveaux arrivants n'ont aucun historique. Il faut que le serveur diffuse les chemins, ce qui est du réseau non budgété. (2) **Autorité** : le serveur coupe sur ses miettes à 10 Hz pendant que chaque client dessine les siennes ; l'enroulement en spirale à l'arrêt casse l'argument « le décalage reste le long du chemin » ; au Dash, un joueur parcourt 3,6 studs par tick, plus que le rayon de 2,8 : il faut un test balayé segment contre segment. (3) **Triche** : des trajets scriptés (bots de coupe, bots de ferme) passent tous les contrôles de vitesse, et nuisent directement aux autres. (4) **Combinatoire** : Guard Links, escorte, équipages, port sûr, immunités, recharges, bouclier, trêve, exception de la Comète, étourdissement, Second Souffle… beaucoup de cas limites. Conformité : le pass Long Conga vend un plafond de bonus plus haut dans un affrontement, ce qui sera perçu comme payer pour gagner. Livrable seulement avec une équipe réseau solide et du temps pour itérer.
- **J3 Joueur (46,0).** Le concept qu'un enfant de 10 à 16 ans sur téléphone aimera le plus. On marche, les créatures sautent dans une file lumineuse sans bouton : les 15 premières secondes sont physiques et drôles. « J'encaisse maintenant ou je pousse vers le Cratère ? » est un vrai choix de gourmandise à chaque course. Coupes, Comète toutes les 10 min et trêve de la Balise créent des moments partagés par tout le serveur. Les amis ont un vrai rôle (équipages, escorte). Le frisson du vol sans le sel du pillage : rien d'encaissé n'est en jeu, l'avant de la file est protégé, il y a un bouclier débutant et un port sûr. Après une semaine, ça tient grâce aux mutations, à l'Atlas, à la Starforge, aux auras et au samedi. C'est le seul concept où l'avatar et le déplacement comptent. Faiblesse : la faisabilité ; des désaccords « je l'ai touché ! », et 12 files de 60 Nebbies à animer sur un Android modeste. Le MVP est serré pour ≈ 7 400 lignes.

### 4.2 Glowkeepers

- **J1 Marché (42,0).** La meilleure architecture de rétention à long terme (cinq horloges, cocons de 4 h à espèce connue, boutique qui se réassortit toutes les 4 h, protection de série, arbre de talents, zones débloquées), alignée sur la fenêtre de 28 jours. Mais il abandonne le conflit social qui a porté les pics 2025-2026 ; la boucle de jour (marcher, attraper avec un anneau de timing, placer) est répétitive et se joue surtout seul ; la Hush se résume à tapoter des ombres, peu viral. Les portails vers des zones à 1 500 studs dispersent le serveur. Technique saine (trajectoires déterministes, accumulation paresseuse, emplacements fixes, aucun JcJ) mais 22 remotes et ≈ 7 800 lignes, au plafond. Faute de conformité : « Festival Lanterns » vend un boost de chance sur des apparitions aléatoires, contraire à sa propre règle.
- **J2 Technique (42,0).** Excellents réflexes d'architecture : créatures sur trajectoire déterministe (`SeededPath` + temps serveur, validation par la même fonction), accumulation paresseuse, emplacements fixes, captures non exclusives. Ce qui pénalise : l'étendue (≈ 20 systèmes) et des pièges cachés : le don « atomique » entre deux profils verrouillés ne l'est pas (un crash entre deux sauvegardes duplique ou détruit un objet) ; les portails demandent du préchargement de streaming ; les vagues de Murklings dépassent la réserve de 40. Boost de chance payant : zone grise réglementaire.
- **J3 Joueur (38,0).** Rétention solide et conseil du rapport suivi (« mignon le jour, légère tension la nuit »). Mais la boucle ressemble à un simulateur de familiers classique (attraper, placer, nourrir, fusionner) ; les captures partagées suppriment la rivalité qui fait crier les amis ; la Hush et le Chorus deviennent une corvée de tapotage au jour 7 ; beaucoup de gestion de menus ; serveur dispersé. Monétisation : chance payante.

### 4.3 Bloop Isles

- **J1 Marché (43,0).** Le plus robuste et le plus conforme : logique de fusion sur tableau, réplication par attributs, tout ancré, meilleure réutilisation de la base, « Rainbow Rain » comme cadeau de serveur déterministe. Mais le cœur consiste à tapoter un enclos 2D sur son île, avatar presque inutile : une app de fusion mobile dans Roblox. Fusion-idle non prouvée en haut des classements, public jeune (7-13 ans), peu d'interaction entre les événements de 6 min : l'exigence d'« interaction sociale significative » n'est que faiblement remplie. Seulement 3 familles au lancement : les jours 8-28 dépendent de mises à jour livrées à l'heure. Peu de drame, donc peu de clips.
- **J2 Technique (42,0).** De loin le plus constructible, et le seul ancré dans le dépôt réel (base de 2 580 lignes vérifiée). Fusions d'entiers sur tableau fixe, état répliqué par attributs, indépendant du streaming, sûr pour les arrivants et les signaux différés ; surface de remotes petite et validée ; cadeau social déterministe ; 5 250 nouvelles lignes, confortable. Faiblesses de design : 3 familles épuisées en 3 à 5 jours ; social mince (tout peut se faire depuis le panneau 2D) ; le bonus de combo, avec « Tout fusionner » compté comme combo toutes les 8 s, devient un amplificateur de revenus dépendant de la latence. Choix du juge technique comme châssis, à condition de greffer de la profondeur sociale et du contenu.
- **J3 Joueur (41,0).** La meilleure première minute (récompense à 3 s, fusion à 12 s, retours très satisfaisants) et la plus petite surface de bugs. Mais tapoter deux blobs dans son enclos n'utilise ni l'avatar ni les autres joueurs ; « Tout fusionner » et le pass Auto-Merge automatisent le seul verbe ; contenu mince avant la semaine 2 ; les 13-16 ans risquent de partir dès la première semaine ; clips mignons mais sans drame.

## 5. Idées greffées

### 5.1 Retenues dans le MVP

| Idée | Origine | Où dans le GDD |
|---|---|---|
| Revenu passif par **accumulation paresseuse** (taux + dernier règlement), hors ligne calculé une fois au chargement | Glowkeepers (J1, J2, J3) | §4.9 |
| Créatures sur **trajectoires déterministes** (`SeededPath` + temps serveur), validation par la même fonction | Glowkeepers (J1, J2) | §4.3, §4.15.4, §12.4 |
| **Gloomwisps dans le MVP** (version de la Hush), menace non joueur pour les petits serveurs, sans faux joueurs | Glowkeepers (J1) | §4.15.4 |
| **Mode Zen** (Cozy/Calm) et serveurs privés sans coupe | Glowkeepers (J1, J3) | §4.16 |
| Commande de développement **« Photo »** pour l'icône et les vignettes | Glowkeepers (J1, J3) | §16 risque 8 |
| **Acclamations de Supernova** (emote `cheer`, confettis, petite récompense) | Bloop Isles (J1, J3) | §6.6 |
| **Constellation publique** au-dessus de chaque Nid | Bloop Isles, Glowkeepers (J1, J3) | §6.6 |
| **Horloge UTC commune** à tous les serveurs, affichée dans le HUD | Bloop Isles (J1, J2, J3) | §2.4 |
| Récompenses d'événement **proportionnelles à la progression** (« X secondes de ton revenu passif ») | Bloop Isles (J1) | §4.15, §7.5 |
| **Écran d'aperçu de la Supernova** (gardé / remis à zéro) | Bloop Isles (J1) | §4.12 |
| **Nids voisins** pour les amis, rayons de lumière entre Nids d'un équipage | Bloop Isles, Glowkeepers (J1, J3) | §6.1 |
| Récompenser le **jeu ensemble**, pas l'envoi d'invitations | Bloop Isles (J1, J3) | §6.2 |
| **Plafonds de ramassage** par joueur dans les mêlées (Épiques de la Comète : 1 par joueur) et **consolation de proximité** | Bloop Isles (J3) | §4.15.2 |
| **Mutations rendues par le matériau** (Ice, Glass, Foil, ForceField) | Bloop Isles (J3) | §4.4 |
| **Lisibilité des cibles** : segments coupables et propre queue exposée signalés | Bloop Isles (J3) | §6.4 |
| **Règle de miséricorde** de la Balise et objectif proportionnel aux joueurs actifs (≈ 80 % de réussite) | Glowkeepers (J3) | §4.15.3 |
| **Achat social déterministe** (Glow Party) avec version gratuite gagnée en coopérant | Bloop Isles, Comet Conga (J2) | §8.3, §4.15.3 |
| **Comète « contenue »** : transmise par simple proximité entre deux personnages, immunité après passage, minuteur | Comet Conga, recadré par J2 | §4.15.2 |
| Rendu client des files avec `BulkMoveTo` et **niveaux de détail** | Comet Conga, Glowkeepers (J2) | §5.2, §12.8 |
| **Réutiliser la base du dépôt** (DataService, MonetizationService, Net/Validate/RateLimit, Juice, Build, harnais Lune) plutôt que ProfileStore | Bloop Isles, Glowkeepers (J1, J2) | §12.1 |
| Simulation de rythme Lune **bloquante**, entonnoir d'accueil numéroté, Mouvement réduit, Graphismes légers, sons vides par défaut | Les trois (J2) | §4.18, §14, §9.1 |
| **Dons reportés** jusqu'à l'existence d'un journal de séquestre en deux phases | Les trois (J2) | §15.3 (v1.4) |

### 5.2 Reportées après le lancement

| Idée | Origine | Version | Raison du report |
|---|---|---|---|
| Œufs à espèce connue d'avance, éclosion en 4 h (rendez-vous J2-J7) | Glowkeepers (J1, J3) | v1.1 | Bon crochet, mais le MVP a déjà calendrier, quêtes, hors ligne et météo ; on protège le budget du réseau des files |
| Boutique déterministe en Stardust avec réassort réel toutes les 4 h | Glowkeepers (J1, J3) | v1.1 | Même raison ; deuxième puits de Stardust |
| Star Path saisonnier gratuit (28 jours) | Comet Conga | v1.2 | Périmètre |

### 5.3 Écartées

| Idée | Origine | Raison |
|---|---|---|
| Chaîne de **combos de capture** avec bonus de paiement | Bloop Isles (J1, J3) | Redondant avec le Conga Bonus, qui récompense déjà l'enchaînement ; le juge technique a montré qu'un bonus de combo devient un amplificateur d'économie |
| Jeton de protection de série (une fois par semaine) | Glowkeepers (J1) | Remplacé par une règle plus généreuse et plus simple : un jour manqué met la série en **pause**, rien n'est perdu |
| Arbre de talents en monnaie de prestige | Glowkeepers (J1) | Périmètre ; la Supernova a déjà des gains clairs (revenu, plafond de file, Dash, auras) |
| Héritage des mutations | Bloop Isles (J2) | Sans objet : la Starforge exige des Nebbies identiques |
| Miroir 2D d'une grille 3D pour la manette | Bloop Isles (J2) | Sans objet (aucune grille 3D à manipuler) ; la navigation manette des panneaux est prévue (§10.4) |
| Boost de chance payant (« Festival Lanterns ») | Glowkeepers | Chance payante : contraire à la contrainte « aucun aléatoire payant » |
| Portails vers des zones lointaines | Glowkeepers | Disperse le serveur et complique le streaming |

## 6. Défauts rédhibitoires relevés sur Comet Conga et corrections

Tous sont corrigés dans le GDD (annexe A du GDD).

| # | Défaut (juge) | Gravité | Correction | GDD |
|---|---|---|---|---|
| 1 | Frustration des coupes chez les moins de 13 ans → abandon en 1re session (J1, J3) | Bloquant | Bouclier débutant **toute la première session**, puis jusqu'à 30 min cumulées sans Supernova ; plafond par coupe (35 % de la file, min 6) ; **2 coupes subies max par minute** ; immunité 8 s ; priorité de reprise à la victime ; Mode Zen ; taux d'abandon après coupe mesuré avec seuil d'action et porte de lancement | §4.7, §4.16, §14.4, §15.2 |
| 2 | Serveurs de 2-4 joueurs sans drame (J1, J3) | Bloquant | **Gloomwisps dans le MVP**, nombre inversement proportionnel aux joueurs actifs ; Comète et météo amusantes seul ; remplissage maximal des serveurs | §4.15.4 |
| 3 | Streaming : personnages lointains déchargés, pas d'historique pour les arrivants (J2) | Bloquant | Le **serveur diffuse ses miettes** (`PathStream` compressé, ≈ 3 Ko/s) ; instantané d'arrivée ; minicarte, détails lointains et tableau indépendants des personnages | §12.4 |
| 4 | Autorité : géométrie client ≠ serveur, spirale à l'arrêt (J2, J3) | Bloquant | Le serveur est la **seule source** de la géométrie des files des autres ; **spirale supprimée** ; effets de coupe seulement à la confirmation | §4.6, §12.4 |
| 5 | Dash plus rapide que le rayon par tick (J2) | Bloquant | **Test balayé** segment contre segment, testé à 3,6 studs/tick | §4.7, §12.9 |
| 6 | Retour en arrière de l'anti-triche trop agressif à forte latence (J1) | Majeur | Signaler d'abord ; retour seulement après 3 infractions en 5 s ; exemptions ; marges réglables ; événement analytique des faux positifs | §12.7, §14.4 |
| 7 | Bots de trajets scriptés (J2) | Majeur | Plafonds journaliers de Stardust, recharge par paire 20 s, pertes bornées par victime, 1 500 captures/h, exclusion des classements. Risque résiduel assumé et suivi | §4.17, §12.7, §16 |
| 8 | Combinatoire des règles (J2) | Majeur | Module pur `SnipRules`, ordre d'évaluation unique écrit noir sur blanc, un test par règle et par combinaison | §4.7, §12.9 |
| 9 | Pass Long Conga = payer pour gagner (J2) | Majeur | **Supprimé** (remplacé par Stash Plus) | §8.2 |
| 10 | Récompense d'invitation = risque de politique (J3) | Majeur | Remplacée par des récompenses de jeu ensemble (bonus d'équipage, cadeau Duo) | §6.2 |
| 11 | Asymétrie tactile / clavier (J3) | Moyen | Aide tactile +0,3 stud, Dash placé sous le pouce, mesure de réussite par type d'entrée, seuil d'action | §4.7, §10.2, §14.4 |
| 12 | Périmètre trop large (J1, J2, J3) | Majeur | Base réutilisée ; Œufs, boutique, Star Path, décorations, bouton « Regarder » et dons déplacés en v1.1-v1.4 ; budget ≈ 8 000 lignes avec ligne de coupe chiffrée ; cœur protégé | §12.10, §15 |
| 13 | Test à 250 ms trop tardif (J1) | Majeur | Test de latence dès la **semaine 2** de production et porte chiffrée avant lancement | §12.9, §15.2 |
| 14 | Transfert de Comète par la coupe de la file (J2) | Moyen | Transfert par **contact avec le porteur**, simple test de proximité | §4.15.2 |

## 7. Pourquoi pas les deux autres

- **Bloop Isles** serait le plus simple à livrer sans bug, mais son cœur se joue seul dans un panneau 2D : il ne remplit que faiblement l'exigence d'interaction sociale, vise un public plus jeune et plus étroit, et manque de contenu pour les jours 8 à 28. Il gagnerait la course technique, pas celle du marché. Ses meilleures idées (horloge commune, acclamations, constellations publiques, aperçu de prestige, achats sociaux déterministes) sont greffées sur Comet Conga.
- **Glowkeepers** a la meilleure ossature de rétention et de bonnes pratiques techniques, mais pas de tension sociale, un serveur dispersé, beaucoup de systèmes et une faute de conformité. Son architecture (trajectoires déterministes, accumulation paresseuse) et sa menace coopérative de nuit (devenue les Gloomwisps) sont greffées sur Comet Conga.

## 8. Conditions du feu vert

Comet Conga passe en production avec ces conditions, reprises comme portes de qualité dans le GDD (§15.2) :

1. Les 14 corrections du §6 sont implémentées et testées.
2. Le test de justesse des coupes à 250 ms est passé dès la deuxième semaine de production ; en cas d'échec, la compensation de latence est avancée dans le MVP.
3. La simulation de rythme Lune et l'ensemble des tests sont verts.
4. Le test de charge à 12 joueurs sur un Android bas de gamme tient 30 images/s.
5. Un playtest avec de jeunes joueurs montre moins de 5 % d'abandon après une coupe.
6. La recherche de nom et de marque (« Comet Conga », « Nebbies ») est faite avant toute publication.

**Risque principal restant** : le réseau des files reste le système le plus délicat du projet. Il est isolé dans des modules purs et testés (`Trail`, `SnipRules`), il est traité en premier dans le planning, et toutes les protections de joueurs limitent l'impact d'une erreur résiduelle.
