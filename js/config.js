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
  siteUrl: "https://nuitsinguliere.com", // ton nom de domaine, sert aux liens générés dans le Studio

  // Booking.com Affiliate Partner Programme
  // -> https://www.booking.com/affiliate-program/
  // Une fois accepté, colle ton "aid" (Affiliate ID) ci-dessous.
  // Il est ajouté automatiquement à TOUS les liens Booking du site.
  booking: {
    aid: "",           // ex : "1234567"
    label: "site-web", // libre : sert à suivre d'où viennent les clics dans ton tableau de bord
  },

  // Autres sites de réservation, pour que le visiteur compare (optionnels).
  // Dès que tu renseignes `param` (ton identifiant d'affiliation, sous la
  // forme "nom=valeur"), un bouton « Comparer sur … » apparaît sur chaque
  // fiche, avec les dates choisies par le visiteur. Tant que `param` est vide,
  // le bouton reste caché : un lien non affilié ne te rapporterait rien.
  // Un lien direct peut aussi être donné par établissement (champ `partners`
  // de hotels.js), il s'affiche alors même sans identifiant.
  partners: {
    expedia:   { name: "Expedia",    param: "", search: "https://www.expedia.fr/Hotel-Search" },
    hotelscom: { name: "Hotels.com", param: "", search: "https://fr.hotels.com/Hotel-Search" },
    direct:    { name: "Site officiel", param: "" }, // lien direct vers l'établissement (champ partners.direct)
  },

  // Idées cadeaux : coffrets séjours insolites (programmes d'affiliation
  // Wonderbox, Smartbox… via Awin ou CJ). Colle ton lien affilié dans `url` :
  // le bloc s'affiche alors dans le guide « Offrir une nuit insolite ».
  gifts: [
    { name: "Wonderbox", pitch: "Coffrets cadeaux « séjour insolite »", url: "" },
    { name: "Smartbox",  pitch: "Coffrets cadeaux nuits insolites et week-ends", url: "" },
  ],

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
    pitch: "Chaque dimanche, 3 adresses extraordinaires et des idées de week-end pour s’évader.",
  },

  /* ---------- Statistiques ----------
   * Plausible (https://plausible.io, respectueux du RGPD, sans bandeau cookies) :
   * mets ton domaine ici pour mesurer les visites et les clics "Réserver"
   * de chaque hôtel : tu vois quels lieux font le plus cliquer. */
  analytics: {
    plausibleDomain: "", // ex : "nuits-singulieres.fr"
  },
};
