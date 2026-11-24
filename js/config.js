/*
 * ============================================================
 *  CONFIGURATION DU SITE — nom, contact, réseaux sociaux,
 *  newsletter et statistiques.
 * ============================================================
 */
window.SITE_CONFIG = {
  siteName: "Nuits Singulières",
  tagline: "Les hôtels les plus extraordinaires de France",
  contactEmail: "contact@nuitsinguliere.com",
  siteUrl: "https://nuitsinguliere.com", // ton nom de domaine, sert aux liens générés dans le Studio

  // L'auteur des avis (page « Qui suis-je », signature des avis testés)
  author: {
    name: "Jules Bourdon",
    title: "Hôtelier passé par des maisons 3, 4 et 5 étoiles, en France et à l'étranger",
  },

  // Nuits Singulières est un site de conseil indépendant : aucune affiliation,
  // aucune commission. Les boutons « Réserver en direct » mènent au site
  // officiel de chaque établissement (champ website dans js/hotels.js).

  /* ---------- Réseaux sociaux (idée 8) ---------- */
  social: {
    instagram: "", // ton @ sans le @ (vide = liens Instagram masqués sur le site)
    tiktok: "",
    pinterest: "",
    // Page « lien en bio » (liens.html) : ids des hôtels, du plus récent au plus ancien.
    // Ajoute ici l'id de chaque hôtel que tu publies sur Instagram.
    // Si la liste est vide : nos coups de cœur.
    bioHotels: [],
  },

  /* ---------- Newsletter ----------
   * Les inscriptions sont enregistrées par le Worker Cloudflare du site
   * (worker/index.js). Export CSV : voir README.md (« newsletter.csv »). */
  newsletter: {
    title: "La lettre de Jules",
    pitch: "Une fois par mois : les nouveaux établissements du site, mes derniers avis testés et les hôtels qui rejoignent mes coups de cœur. Gratuit, sans publicité.",
  },

  /* ---------- Statistiques ----------
   * Plausible (https://plausible.io, respectueux du RGPD, sans bandeau cookies) :
   * mets ton domaine ici pour mesurer les visites et les clics "Réserver"
   * de chaque hôtel : tu vois quels lieux font le plus cliquer. */
  analytics: {
    plausibleDomain: "", // ex : "nuits-singulieres.fr"
  },
};
