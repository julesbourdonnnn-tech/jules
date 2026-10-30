---
name: roblox-game-design
description: Game design Roblox fondé sur l'analyse de marché 2025-2026 (docs/01-analyse-marche.md) — boucles qui fonctionnent, première minute, rétention J1/J7/J28, co-op, événements live, monétisation équitable et conforme, équilibrage de l'économie, ajout de contenu data-driven. À charger pour concevoir/équilibrer une fonctionnalité, ajouter du contenu, planifier une mise à jour ou un événement, ou fixer des prix.
---

# Game design Roblox (marché 2025-2026)

Sources détaillées : `docs/01-analyse-marche.md` (rapport), `docs/02-game-design-document.md` (GDD du jeu), `docs/03-decision-du-jury.md`.

## Ce que l'algorithme récompense (depuis 2026)

- **Rétention à 28 jours** et taux de rebond de la première session (négatif). Les pics de lancement comptent peu.
- **Taux de « play-through »** : icône et miniature qui donnent envie de cliquer, puis premier jeu immédiatement compréhensible.
- **Co-play** : jouer avec des amis est un signal de classement à part entière.
- Sessions de **10 min ou plus** et habitude quotidienne.
- La publicité payante et le trafic externe **n'améliorent pas** le classement.

Repères de rétention (GameAnalytics 2026) : médiane J1 10 %, J7 1,6 %, J30 0,5 % ; top 1 % : J1 22 %, J7 9 %, J30 4,7 %.

## La boucle qui gagne

**Collecter → revenu passif/idle → améliorer → renaissance (rebirth/prestige)**, plus **une interaction sociale** (co-op, échange/don, rivalité amicale). Le tout doit être compréhensible en 10 secondes, avec une vraie profondeur de collection : raretés, variantes ou mutations, livre de collection.

- Pas de clone pur ni de skin de mème : les jeux « brainrot » tombent sous 1K CCU en un mois, les clones sont attaqués en justice, les suites n'héritent pas de l'audience. Il faut des **personnages et un univers originaux**.
- Le contenu doit être **data-driven** : un nouvel objet, une zone ou un événement = une entrée de config, pas du code.

## Première minute (FTUE)

1. 0-5 s : le joueur apparaît face à l'action, avec un objectif visible (flèche ou faisceau), sans texte long.
2. ≤ 30 s : **première récompense**, avec beaucoup de juice (son, particules, compteur qui défile).
3. ≤ 2 min : première amélioration achetée, et la boucle complète a été vécue une fois.
4. ≤ 5 min : un objectif à moyen terme apparaît (prochaine zone, prochaine rareté), ainsi que la quête du jour.

## Crochets de rétention

| Horizon | Crochets |
|---------|----------|
| J1 | objectif immédiat, progression visible, première rareté |
| J2-J7 | récompense quotidienne + série, quêtes du jour, gains hors-ligne plafonnés, livre de collection |
| J8-J28 | renaissance/prestige, objets rares, événements hebdo, nouvelles zones |
| Rendez-vous | événement serveur à heure fixe (ex. samedi, 1 h avant la mise à jour), boutique qui tourne avec un minuteur visible |

## Social sans chat

Le chat exige une vérification d'âge : le jeu ne doit jamais en dépendre. Il faut plutôt des **emotes**, des pings rapides, des bonus d'équipe ou d'amis (« +10 % par ami sur le serveur »), des invitations (`SocialService:PromptGameInvite`), des événements de serveur communs, des classements et des moments faits pour être filmés (révélation rare, gros effet).

## Monétisation équitable (et conforme)

- **Gamepasses** (valeur permanente, 49-249 R$) : x2 monnaie, VIP, auto-collecte, emplacements en plus.
- **Produits développeur** (consommables) : packs de monnaie, boosts temporaires, passer un minuteur, boost de serveur (achat « social » qui profite à tous), pack de démarrage unique.
- **Prix lus dynamiquement** via `MarketplaceService:GetProductInfo` (tarification régionale et tests de prix gérés par Roblox) ; les prix en config ne servent que de repli.
- **Aucun objet aléatoire payant** : les tirages se paient en monnaie *gagnée en jeu* uniquement. Si un jour ils deviennent payants, il faut afficher les probabilités exactes et vérifier `PolicyService.ArePaidRandomItemsRestricted`.
- Pas de dark patterns : pas de faux compte à rebours, pas de « presque gagné », prix en Robux toujours clairs.
- Ne jamais récompenser le fait de regarder un flux continu (motif de retrait d'un jeu en 2026).
- Tout ce qui compte reste accessible gratuitement.

## Équilibrage de l'économie

- Coûts exponentiels : `cost(n) = base × growth^n` avec `growth` entre 1.12 et 1.35 ; revenus linéaires ou légèrement super-linéaires.
- Temps cible jusqu'à chaque palier : on vise 30 s, 2 min, 5 min, 15 min, 45 min, 2 h…, puis on règle `base` et `growth` pour tenir ces temps.
- Gains hors-ligne plafonnés (ex. 2 à 8 h) et à taux réduit (≈ 25-50 %).
- La renaissance remet la monnaie à zéro contre un multiplicateur permanent (+10 à 25 % par niveau), avec un coût qui croît.
- Toujours `math.floor` sur la monnaie, et tests d'invariants : jamais négatif, jamais NaN.

## Conformité

- Remplir le **questionnaire de maturité** (sinon le jeu reste invisible), et viser *Minimal/Mild* (catalogues Kids et Select).
- Localisation EN/FR au minimum, plus la traduction automatique Roblox. Une UI riche en icônes passe mieux qu'une UI chargée de texte.

## Rythme live-ops

Mise à jour à jour fixe (toutes les 1 à 2 semaines), événement programmé avant chaque mise à jour, codes promo, notes de version dans le jeu. Les jeux sortent des classements surtout **quand les mises à jour s'arrêtent**.
