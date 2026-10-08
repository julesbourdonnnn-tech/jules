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
  // Remise accordée aux réservations directes, en % (nuits et ménage ; la taxe de séjour n'est pas remisée)
  remiseDirecte: 10,
  // Conditions d'annulation (affichées avant le paiement, à adapter)
  annulation: [
    "Cancelación gratuita hasta 30 días antes de la llegada: reembolso íntegro.",
    "Entre 30 y 14 días antes de la llegada: reembolso del 50 %.",
    "Menos de 14 días antes de la llegada: sin reembolso.",
  ],
};
