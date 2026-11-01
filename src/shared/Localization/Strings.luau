--!strict
-- Textes du jeu. Clés en « domaine.nom ». Variables entre accolades : {amount}.
-- Registre partagé : ajouts ciblés autorisés, TOUJOURS en anglais ET en français (Contract.spec :
-- parité stricte et mêmes variables {x}). Socle : seulement les clés génériques utilisées par les
-- modules du socle (boutons communs, écran de chargement, réglages). Les textes du jeu s'ajoutent
-- par domaine (hud.*, shop.*, feedback.*, banner.*…).
-- src/first/Loading.client.luau recopie loading.wake et loading.retry (il s'affiche avant la
-- réplication de ReplicatedStorage) : une spec vérifie que les deux copies restent identiques.

local Strings: { [string]: { [string]: string } } = {}

Strings.en = {
	["common.ok"] = "OK",
	["common.close"] = "Close",
	["common.back"] = "Back",
	["common.retry"] = "Retry",
	["common.confirm"] = "Confirm",
	["common.cancel"] = "Cancel",
	["common.buy"] = "Buy",
	["common.owned"] = "Owned",
	["common.free"] = "Free",
	["common.on"] = "On",
	["common.off"] = "Off",
	["common.loading"] = "Loading…",
	["common.robux"] = "R$ {price}",
	["loading.wake"] = "Almost ready…",
	["loading.retry"] = "Retry",
	["settings.reducedMotion"] = "Reduced Motion",
	["settings.reducedMotion.desc"] = "No shakes, flashes or camera moves",
	["settings.lowGraphics"] = "Low Graphics",
	["settings.lowGraphics.desc"] = "Fewer effects for smoother play",
	["settings.music"] = "Music",
	["settings.music.desc"] = "Background music",
	["settings.sfx"] = "Sound effects",
	["settings.sfx.desc"] = "Game sounds",
	["settings.vibration"] = "Vibration",
	["settings.vibration.desc"] = "Controller and phone rumble",
	["settings.lang"] = "Language",
	["settings.lang.desc"] = "Language of the game",
	["settings.lang.auto"] = "Auto",
	["settings.lang.en"] = "English",
	["settings.lang.fr"] = "Français",
}

Strings.fr = {
	["common.ok"] = "OK",
	["common.close"] = "Fermer",
	["common.back"] = "Retour",
	["common.retry"] = "Réessayer",
	["common.confirm"] = "Confirmer",
	["common.cancel"] = "Annuler",
	["common.buy"] = "Acheter",
	["common.owned"] = "Possédé",
	["common.free"] = "Gratuit",
	["common.on"] = "Activé",
	["common.off"] = "Désactivé",
	["common.loading"] = "Chargement…",
	["common.robux"] = "{price} R$",
	["loading.wake"] = "Presque prêt…",
	["loading.retry"] = "Réessayer",
	["settings.reducedMotion"] = "Mouvement réduit",
	["settings.reducedMotion.desc"] = "Pas de secousses, de flashs ni de mouvements de caméra",
	["settings.lowGraphics"] = "Graphismes légers",
	["settings.lowGraphics.desc"] = "Moins d'effets pour plus de fluidité",
	["settings.music"] = "Musique",
	["settings.music.desc"] = "Musique d'ambiance",
	["settings.sfx"] = "Effets sonores",
	["settings.sfx.desc"] = "Sons du jeu",
	["settings.vibration"] = "Vibrations",
	["settings.vibration.desc"] = "Vibrations de la manette et du téléphone",
	["settings.lang"] = "Langue",
	["settings.lang.desc"] = "Langue du jeu",
	["settings.lang.auto"] = "Auto",
	["settings.lang.en"] = "English",
	["settings.lang.fr"] = "Français",
}

return Strings
