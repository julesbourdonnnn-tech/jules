// Les fichiers js/data.js, js/tarifs.js et js/prix.js du site écrivent dans
// « window » : dans le serveur, window = l'objet global. Doit être importé en premier.
globalThis.window = globalThis;
