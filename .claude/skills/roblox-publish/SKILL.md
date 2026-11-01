---
name: roblox-publish
description: Construire, ouvrir dans Roblox Studio et publier le jeu (rojo build/serve, activation des API DataStore, création des gamepasses et produits développeur, administrateurs, codes, semaine du premier Starfall, questionnaire de maturité, icône/miniatures, paramètres d'expérience, console PS5, lancement et suivi analytics). À charger pour « publier », « mettre en ligne », « tester dans Studio », « créer les gamepasses », « préparer le lancement », « jouer sur PS5 ».
---

# Construire et publier

**Source de vérité : [`docs/05-guide-publication.md`](../../../docs/05-guide-publication.md)** (guide pas à pas en français simple pour le propriétaire, non programmeur). Cette skill en est le résumé pour Claude ; en cas d'écart, le guide fait foi et cette skill doit être corrigée. Rapport qualité et plan de test manuel dans Studio : [`docs/06-rapport-qualite.md`](../../../docs/06-rapport-qualite.md). Console : [`docs/07-console-ps5.md`](../../../docs/07-console-ps5.md).

Règle d'écriture : toute étape de menu Studio / Creator Hub non confirmée par une documentation officielle est marquée **« à vérifier »** (les menus changent souvent de nom). Ne jamais inventer un menu présenté comme certain.

## 1. Outils et place jouable (guide §1-§3)

```bash
rokit install                     # versions de rokit.toml (Rojo 7.7.1, Selene, StyLua, Lune)
./scripts/check.sh                # porte complète : doit finir par « ✅ Tout est vert. »
rojo build -o build/Game.rbxl     # fichier à ouvrir dans Roblox Studio (double-clic)
```

- Aftman : pas de `aftman.toml` dans le projet → `aftman add rojo-rbx/rojo@7.7.1`.
- Direct : `rojo serve` puis, dans Studio, plugin Rojo (`rojo plugin install` ou Creator Store) → *Connect* (localhost:34872).
- Studio : **Play** seul ; *Test › Clients and Servers* : *Local Server*, 2-4 joueurs ; *Test › Device* : téléphones et tablette.

## 2. Première publication et DataStores (guide §4)

1. `build/Game.rbxl` ouvert → *File › Publish to Roblox* → nouvelle expérience, gardée **privée**.
2. *Game Settings › Security* : **Enable Studio Access to API Services**.
3. Sans cet accès, `DataService` bascule sur une sauvegarde **en mémoire** et l'écrit dans Output (`[DataService] DataStore indisponible dans Studio (…) : sauvegarde EN MÉMOIRE uniquement.`). Avec l'accès, Studio écrit dans les **vraies** données : après le lancement, tester dans une copie de l'expérience.
4. Mise à jour : même commande de build, puis *Publish to Roblox* vers l'**expérience existante** (les réglages du Creator Hub sont conservés).

## 3. Monétisation (guide §5)

`src/shared/Config/Monetization.luau` : `id = 0` = article masqué (pas en boutique, aucun achat proposé). Prix réel lu à l'exécution (`src/client/Util/Prices.luau`) ; `price` n'est qu'un repli d'affichage, à garder identique au Creator Hub.

| Passes (Creator Hub › *Monetization › Passes*, à vérifier) | Prix | Produits (*Monetization › Developer Products*, à vérifier) | Prix |
|---|---|---|---|
| `VIPStar` « VIP Star » | 199 | `GlowPouch` « Glow Pouch » | 25 |
| `DoubleGlow` « Double Glow » | 299 | `GlowSack` « Glow Sack » | 89 |
| `NightShift` « Night Shift » | 99 | `GlowCrate` « Glow Crate » | 199 |
| `ExtraPerches` « Extra Perches » | 149 | `GlowParty` « Glow Party » | 99 |
| `StashPlus` « Stash Plus » | 99 | `StardustJar` « Stardust Jar » | 49 |
| `CongaStyles` « Conga Styles » | 79 | `StarterKit` « Starter Kit » (une fois par compte) | 49 |

Créer, mettre en vente, copier l'ID, remplacer **seulement** le `0` de `id = 0,`, `check.sh`, rebuild, republier, puis tester chaque achat dans Studio (achats d'essai gratuits). Jamais d'objet aléatoire payant (GDD §8.1).

## 4. Réglages du code avant lancement (guide §6)

- **Admins LiveOps** : `src/server/Data/Admins.luau`, `[UserId] = true` ; section LiveOps en bas de Réglages (attribut Player `Admin`), commandes de `Events.LiveOps.Commands` (comet, weather:<clé>, frenzy, goldenNight) relayées par MessagingService.
- **Codes** : `src/server/Data/Codes.luau` ; `COMETCONGA` (200 Stardust + 10 min ×2, jusqu'au 31/12/2027 23:59:59 UTC) ; `[A-Z0-9]`, ≤ 20 caractères, `expires` en secondes Unix UTC, une fois par compte.
- **Premier Starfall Saturday** : `src/shared/Config/Events.luau`, `Starfall.LaunchWeek` = semaine `floor((t − 345600) / 604800)` du premier samedi 16:00 UTC après la publication (2966 = 14/11/2026 ; +1 par semaine). Fixe les 12 semaines Starborn.
- **Sons** : `src/shared/Config/Sounds.luau` ; tous remplis (sons publiés par Roblox, provenance sur la ligne) ; neuf remplis en dernier, « à confirmer à l'écoute » sur leur ligne (`Scatter`, `Bank`, `Dash`, `CometWarn`, `CometSwipe`, `BeaconStart`, `WispPop`, `Ping`, `Cheer` ; `CometWarn` et `Ping` les moins sûrs) : à écouter en premier, un son vidé (`id = ""`) devient muet sans rien casser. Un son rempli = format exact `rbxassetid://<nombre>` + provenance en commentaire sur sa ligne (`tests/specs/Contract.spec.luau`).
- **Boutique** : avant de publier en ligne, `lune run scripts/prepublish` doit afficher « ✅ Boutique prête » (les 12 ids de `Config/Monetization` renseignés).

## 5. Expérience et page du jeu (guide §7-§10)

- **12 joueurs** par serveur (12 Nids) : réglage du Creator Hub, qui fait foi (le `MaxPlayers = 12` de `default.project.json` ne suffit pas en ligne) ; *Server Fill* au maximum (à vérifier).
- Appareils : téléphone, tablette, ordinateur ; **console seulement après le §6 ci-dessous**. Genre Simulation. Serveurs privés gratuits (GDD §4.16).
- **Questionnaire de maturité** (obligatoire, chemin officiel : Creator Dashboard › expérience › *Publish settings › Content rating* › *Start* … *Submit*) : viser Minimal (au pire Mild, toujours éligible Roblox Kids / Select) ; non pour objets aléatoires payants, échanges payés, hangout, création libre, IA, médias. À refaire si le contenu change.
- Icône (un Nebby lumineux + début de file, sans texte ou presque) et 3-5 miniatures en jeu (conga de 50 dans le Cratère, SNIP !, Grande Comète, parade, Supernova) ; dimensions : celles demandées par le Creator Hub.
- Langues : FR/EN déjà dans `src/shared/Localization/Strings.luau` (choix automatique par `LocaleId`, réglage Langue) ; traduction automatique de Roblox pour les autres langues ; titre et description traduits en français dans *Localization* (à vérifier).
- Starfall Saturday déclaré en *Experience Event* (GDD §7.6, menu à vérifier). Noms « Comet Conga » / « Nebbies » vérifiés avant publication (GDD §16).

## 6. PlayStation 5 (guide §11)

Sources autorisées : documentation officielle Roblox (*Console development guidelines*, *Gamepad input*, *Content maturity and compliance*) et `docs/07-console-ps5.md` ; le reste est « à vérifier ».

1. Questionnaire de maturité rempli (exigé pour la console ; sans lui la jouabilité est restreinte pour tous).
2. Test manette dans Studio : **Controller Emulator** (officiel ; emplacement du menu à vérifier) ou manette USB.
3. Console ajoutée aux appareils de l'expérience seulement après les specs `Console*` (vertes) et ce test ; emplacement exact à vérifier.
4. Sur la PS5 (à vérifier : app Roblox du PlayStation Store, favoris ou recherche ; jeu privé ou non classé joignable ? achats sur PlayStation ?).
5. Essai réel (docs/07 §12) : lisibilité à 3 m (55" et 43"), zone sûre avec l'ajustement d'affichage de la PS5, tout à la manette, achats d'essai, vibrations modérées, pas de fenêtre de chat.

## 7. Lancement et suivi (guide §12-§14)

- Check-lists avant / après lancement : guide §12 et §14. Plan de test manuel M1-M13 : docs/06 §5. Questions de design ouvertes : docs/06 §7.
- Publication suggérée le samedi 17:00 UTC (GDD §15.3), privé → testeurs (10-20, dont des moins de 13 ans accompagnés) → public.
- Analytics (`src/server/Util/Analytics.luau`) : entonnoir `LogOnboardingFunnelStepEvent` en 10 étapes (`Config/Quests.Funnel` : Loaded … FirstSupernova) ; `LogEconomyEvent` (Glow, Stardust) ; `LogCustomEvent` (`SessionLength`, `PostSnipQuit`, `SnipDealt`, `SnipReceived`, `SnipByInput`, `ParadeLength`, `CometHeld`, `CometBanked`, `WispPopped`, `WispSnip`, `ZenToggled`, `RookieShieldEnded`, `SupernovaReached`, `MoveViolation`, `CrewFormed`, `Pass_<clé>`, `Product_<clé>`, `ProductEffectFailed_<clé>`).
- Seuils (GDD §1.5, §14.4) : J1 ≥ 15 %, J7 ≥ 5 %, J30 ≥ 2 %, session ≥ 12 min, conversion 1,5 %, `PostSnipQuit` ≤ 5 % des coupes subies ; réactions par la configuration seulement.
- Cadence (GDD §7.7) : code et Starfall chaque semaine, contenu toutes les 2 semaines (samedi 17:00 UTC), événement à thème chaque mois. Publicité sponsorisée seulement une fois les repères de rétention atteints (docs/01 §5.3).
