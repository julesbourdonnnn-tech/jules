/*
 * Tarifs et conditions des réservations directes.
 * Ce fichier est lu par le site (affichage du prix) ET par le serveur
 * (calcul du montant réellement payé) : c'est le seul endroit à modifier.
 *
 * Tous les montants sont en euros, TTC.
 * null = pas encore renseigné : le site affiche alors « prix sur demande »
 * et la réservation se fait sous forme de demande, sans paiement en ligne.
 */
globalThis.TARIFS = {
  lacanau: {
    // Prix d'une nuit par défaut (hors saisons ci-dessous)
    nuit: null,
    // Saisons : prix de la nuit entre deux dates (jour-mois, bornes incluses).
    // Exemple : { nom: "Été", du: "07-01", au: "08-31", nuit: 650 }
    saisons: [],
    // Frais de ménage, une fois par séjour
    menage: null,
    // Taxe de séjour, par adulte (18 ans et plus) et par nuit (voir la mairie de Lacanau)
    taxeSejour: 0,
    // Caution (information affichée, non prélevée)
    caution: null,
  },
  bordeaux: {
    nuit: null,
    saisons: [],
    menage: null,
    // Taxe de séjour, par adulte et par nuit (voir Bordeaux Métropole)
    taxeSejour: 0,
    caution: null,
  },
  // Conditions d'annulation (affichées avant le paiement, à adapter)
  annulation: [
    "Annulation gratuite jusqu'à 30 jours avant l'arrivée : remboursement intégral.",
    "Entre 30 et 14 jours avant l'arrivée : remboursement de 50 %.",
    "Moins de 14 jours avant l'arrivée : aucun remboursement.",
  ],
};
