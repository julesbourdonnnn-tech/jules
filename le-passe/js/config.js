/*
 * ============================================================
 *  LE PASSE — tes coordonnées, à un seul endroit.
 *  Tout ce qui est vide est simplement masqué sur le site.
 * ============================================================
 */
window.LP_CONFIG = {
  // Adresse qui reçoit les demandes (formulaire « Le bon » et liens e-mail).
  // Provisoire : l'adresse de Nuits Singulières, qui fonctionne déjà.
  // À remplacer par bonjour@<ton-domaine> dès que le domaine est acheté.
  email: "contact@nuitsinguliere.com",

  // Téléphone affiché et bouton WhatsApp (format international, sans espaces
  // pour whatsapp : "33612345678"). Vide = masqué.
  phone: "",        // ex : "06 12 34 56 78"
  whatsapp: "",     // ex : "33612345678"

  instagram: "",    // ton @ sans le @ (vide = masqué)

  // Zone où tu te déplaces en personne (vide = « partout en France, en visio »).
  // ex : "Lyon et sa région"
  zone: "",

  // ---------- Mentions légales (OBLIGATOIRES avant de vendre) ----------
  // Dès ton immatriculation (micro-entreprise, sur formalites.entreprise.gouv.fr) :
  siret: "",        // ex : "123 456 789 00012"
  address: "",      // adresse professionnelle (ou de domiciliation)
  // En micro-entreprise sous le seuil de TVA, la mention ci-dessous est obligatoire
  // sur les devis et factures. Laisse vide si tu factures la TVA.
  tvaNote: "",      // ex : "TVA non applicable, art. 293 B du CGI."

  // Enregistrement des demandes par le Worker Cloudflare (worker/index.js).
  // Si l'envoi échoue (site ouvert en local, Worker absent…), le formulaire
  // ouvre automatiquement un e-mail pré-rempli : aucune demande n'est perdue.
  api: "/api/contact",
};
