/*
 * ============================================================
 *  CONFIGURATION DU SITE — c'est ici que tu mets tes identifiants
 *  d'affiliation, tes tarifs et tes réseaux sociaux.
 * ============================================================
 */
window.SITE_CONFIG = {
  siteName: "Nuits Singulières",
  tagline: "Les hôtels les plus extraordinaires de France",
  contactEmail: "contact@exemple.fr",
  siteUrl: "https://jules.jules-bourdonnnn.workers.dev", // ton nom de domaine, sert aux liens générés dans le Studio

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

  /* ---------- Réseaux sociaux (idée 8) ---------- */
  social: {
    instagram: "nuits.singulieres", // ton @ sans le @
    tiktok: "",
    pinterest: "",
    // Page « lien en bio » (liens.html) : ids des hôtels, du plus récent au plus ancien.
    // Ajoute ici l'id de chaque hôtel que tu publies sur Instagram.
    // Si la liste est vide : nos coups de cœur.
    bioHotels: [],
  },

  /* ---------- Newsletter (idée 8) ----------
   * Par défaut, les inscriptions sont recueillies par Netlify Forms
   * (onglet "Forms" de ton tableau de bord Netlify, export CSV possible
   * vers Brevo, Mailchimp…). Aucune configuration nécessaire. */
  newsletter: {
    title: "La lettre des nuits rares",
    pitch: "Chaque dimanche, 3 adresses extraordinaires, des idées de week-end et des offres réservées aux abonnés.",
  },

  /* ---------- Statistiques ----------
   * Plausible (https://plausible.io, respectueux du RGPD, sans bandeau cookies) :
   * mets ton domaine ici pour mesurer les visites et les clics "Réserver"
   * de chaque hôtel : tu vois quels lieux font le plus cliquer. */
  analytics: {
    plausibleDomain: "", // ex : "nuits-singulieres.fr"
  },
};
