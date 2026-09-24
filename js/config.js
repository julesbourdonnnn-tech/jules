/*
 * ============================================================
 *  CONFIGURATION DU SITE — c'est ici que tu mets tes identifiants
 *  d'affiliation. Aucune autre modification n'est nécessaire.
 * ============================================================
 */
window.SITE_CONFIG = {
  siteName: "Nuits Singulières",
  tagline: "Les hôtels les plus extraordinaires de France",
  contactEmail: "contact@exemple.fr",

  // Booking.com Affiliate Partner Programme
  // -> https://www.booking.com/affiliate-program/
  // Une fois accepté, colle ton "aid" (Affiliate ID) ci-dessous.
  // Il est ajouté automatiquement à TOUS les liens Booking du site.
  booking: {
    aid: "",           // ex : "1234567"
    label: "site-web", // libre : sert à suivre d'où viennent les clics dans ton tableau de bord
  },

  // Autres partenaires (optionnels). Si un hôtel a un lien "partners.xxx"
  // dans hotels.js, un bouton secondaire s'affiche sur sa fiche.
  partners: {
    expedia:  { name: "Expedia",   param: "" }, // ex : "affcid=XXXX" (Expedia Group Affiliate Program)
    hotelscom:{ name: "Hotels.com",param: "" },
    direct:   { name: "Site officiel", param: "" }, // lien direct négocié avec l'hôtel
  },
};
