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
    // Si la liste est vide : hôtels Premium puis coups de cœur.
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

  /* ---------- Offres payantes pour les hôteliers (idée 1) ----------
   * paymentLink : colle un lien de paiement Stripe (Stripe > Liens de paiement,
   * abonnement mensuel). Si vide, le bouton ouvre le formulaire de contact. */
  plans: {
    decouverte: {
      name: "Découverte", price: 0, period: "",
      pitch: "Pour les lieux que nous sélectionnons",
      features: ["Fiche complète avec photos", "Présence sur la carte et dans la recherche", "Lien de réservation"],
      paymentLink: "",
    },
    partenaire: {
      name: "Partenaire", price: 29, period: "/ mois",
      pitch: "Pour gagner en visibilité",
      features: ["Tout Découverte", "Badge « Partenaire » et remontée dans les résultats", "Lien vers votre site et votre téléphone (réservation directe)", "Encart « Offre spéciale »", "Rapport mensuel de clics"],
      paymentLink: "",
      highlight: false,
    },
    premium: {
      name: "Premium", price: 79, period: "/ mois",
      pitch: "Pour remplir les dates creuses",
      features: ["Tout Partenaire", "Mise en avant dans les « Coups de cœur » de l'accueil", "1 publication Instagram par mois", "Mention dans la newsletter chaque mois", "Photos illimitées"],
      paymentLink: "",
      highlight: true,
    },
  },
  // Prestations ponctuelles (sponsoring Instagram / newsletter)
  extras: [
    { name: "Publication Instagram dédiée (carrousel + story)", price: 150 },
    { name: "Newsletter dédiée à votre établissement", price: 200 },
    { name: "Pack lancement : Premium 3 mois + 1 publication dédiée", price: 290 },
  ],

  /* ---------- Statistiques ----------
   * Plausible (https://plausible.io, respectueux du RGPD, sans bandeau cookies) :
   * mets ton domaine ici pour mesurer les visites et les clics "Réserver"
   * de chaque hôtel — c'est ce qui te permettra d'envoyer des rapports aux hôteliers. */
  analytics: {
    plausibleDomain: "", // ex : "nuits-singulieres.fr"
  },
};
