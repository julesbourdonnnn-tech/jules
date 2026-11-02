# Tests du vrai moteur Roblox (Open Cloud, couche i)

Les specs de `tests/engine/*.spec.luau` sont **portables** : elles tournent sous Lune (avec un `T`
minimal, vérifié par `tests/specs/OpenCloud.spec.luau`) **et** dans un vrai serveur Roblox, lancées par
`tools/opencloud/run-server-tests.luau`.

## Ce que fait l'outil

1. `rojo build tests/engine.project.json -o build/EngineTests.rbxl` : la place de test = `src` +
   `tests/engine` sous `ServerStorage.EngineTests` (lanceur `Runner`). **Jamais `default.project.json`.**
2. Publication comme nouvelle version d'une **place de test privée** :
   `POST https://apis.roblox.com/universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions?versionType=Saved`
   (en-tête `x-api-key`, corps : la place binaire).
3. Tâche d'exécution Luau sur cette version :
   `POST https://apis.roblox.com/cloud/v2/universes/{u}/places/{p}/versions/{v}/luau-execution-session-tasks`
   avec `{ script = "… return Runner.runJson()", timeout = "300s" }`.
4. Attente de l'état `COMPLETE` ou `FAILED` (lecture toutes les 3 s, 7 min au plus), puis lecture des
   journaux (`…/logs?view=STRUCTURED`).
5. Code de sortie : **0** tout est vert ; **1** un test échoue, une erreur du moteur, ou une ligne
   `ERROR` / `WARNING` dans les journaux ; **2** non lancé (clé ou identifiants absents).

## Mise en route (une fois)

1. Créer une **place de test privée** dans une expérience à part (jamais la place publiée du jeu) :
   Creator Hub → Créations → nouvelle expérience « Raise a Squishy — tests » → laisser **privée**.
   Noter l'`UNIVERSE_ID` (identifiant de l'expérience) et le `PLACE_ID` (place de départ).
2. Activer les API DataStore de cette expérience (Paramètres → Sécurité → « Enable Studio Access to
   API Services ») : le test d'aller-retour écrit dans le magasin dédié `EngineTest_v1`.
3. Creator Hub → Open Cloud → API Keys → créer une clé :
   - **universe-places** : `write` sur cette expérience (publication de versions) ;
   - **luau-execution-sessions** : `read` et `write` sur cette expérience ;
   - adresse IP : celle de la machine qui lance les tests (ou `0.0.0.0/0` pour un poste de travail).
4. Exporter les variables **dans le shell**, jamais dans le dépôt :

```bash
export ROBLOX_API_KEY="…"      # la clé (secrète)
export UNIVERSE_ID="1234567890"
export PLACE_ID="9876543210"
lune run tools/opencloud/run-server-tests
```

## Lire le résultat

- `N réussis, M échoués (vrai moteur)` puis une ligne `✗ …` par test échoué.
- `erreur du moteur : …` : une erreur vue par `ScriptContext.Error` pendant la tâche.
- `journal : WARNING …` : un avertissement du moteur (par exemple « Infinite yield possible ») ; la règle
  zéro trace s'applique aussi dans le vrai moteur.
- Code 2 : rien n'a été envoyé (message « Tests du vrai moteur NON LANCÉS »).

## Écrire une spec du moteur

Un module `tests/engine/<Nom>.spec.luau` qui rend `function(T)` et n'utilise que `T.describe`, `T.it`,
`T.expect`, `T.require("ReplicatedStorage.Shared.Logic.Formulas")`, `T.service("Workspace")` et
`T.logErrors()`. Aucun module de test hors moteur, aucun harnais, aucun `Bots`
(`Contract_game.spec` refuse toute importation de la bibliothèque standard de Lune dans `tests/engine`).
Ajoutez-la : `OpenCloud.spec` vérifie qu'elle passe aussi sous Lune.
