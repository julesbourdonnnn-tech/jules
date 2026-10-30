---
name: roblox-publish
description: Construire, ouvrir dans Roblox Studio et publier le jeu (rojo build/serve, activation des API DataStore, création des gamepasses et produits développeur, questionnaire de maturité, icône/miniatures, paramètres d'expérience, lancement et suivi analytics). À charger pour « publier », « mettre en ligne », « tester dans Studio », « créer les gamepasses », « préparer le lancement ».
---

# Construire et publier

## 1. Obtenir une place jouable

```bash
rojo build -o build/Game.rbxl     # fichier à ouvrir dans Roblox Studio (double-clic)
```

Développement en direct : `rojo serve` puis, dans Studio, le plugin Rojo → *Connect* (localhost:34872). Les fichiers de `src/` se synchronisent à chaque sauvegarde.

## 2. Premier lancement dans Studio

1. Ouvrir `build/Game.rbxl` → *File › Publish to Roblox* (créer une nouvelle expérience).
2. *Game Settings › Security* : activer **Enable Studio Access to API Services** (DataStore en Studio).
3. *Game Settings › Avatar* : R15, échelles par défaut.
4. *Test › Clients and Servers* : 3 joueurs, *Local Server*, pour tester le multijoueur.
5. *Test › Device* : émulateur téléphone pour l'UI mobile.

Sans l'accès API, le jeu bascule sur une sauvegarde en mémoire et l'écrit dans la sortie (rien n'est perdu en production).

## 3. Monétisation

1. Creator Hub → l'expérience → *Monetization › Passes* : créer chaque gamepass listé dans `src/shared/Config/Monetization.luau` (nom, prix, icône), copier l'ID.
2. *Monetization › Developer Products* : idem pour les produits.
3. Coller les IDs dans `Monetization.luau` (un ID à 0 = article masqué), `rojo build`, republier.
4. Vérifier chaque achat en Studio (les achats y sont simulés, gratuits).

## 4. Page de l'expérience

- **Questionnaire de maturité** (obligatoire) : répondre honnêtement ; le jeu vise *Minimal*.
- Icône 512×512 et 3 à 5 miniatures 1920×1080 (captures en jeu avec l'UI masquée).
- Titre court et clair + description avec les mots-clés du genre ; langue EN + FR.
- Genre et sous-genre corrects (ils pilotent les recommandations).
- Paramètres : 12-16 joueurs par serveur, appareils téléphone/tablette/ordinateur/console cochés.
- *Localization* : activer la traduction automatique pour les langues secondaires.

## 5. Lancement

- Publier en **privé**, tester avec 2-3 amis, puis passer en public.
- Suivre dans *Analytics* : rétention J1/J7, durée de session, conversion des payeurs, funnel FTUE (événements `AnalyticsService:LogOnboardingFunnelStepEvent`).
- Mises à jour régulières (toutes les 1 à 2 semaines) annoncées dans le jeu.
- Publicité : campagnes « Sponsored Experiences » sur petit budget pour mesurer l'accroche (CTR de l'icône, rétention des nouveaux joueurs) avant d'augmenter.
