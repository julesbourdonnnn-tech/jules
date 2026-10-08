/*
 * Moments où il y a beaucoup de monde à Lacanau ou à Bordeaux : vacances scolaires,
 * ponts, grands événements. Utilisé par l'espace propriétaire (admin.html → Prix)
 * pour repérer les dates où augmenter les prix.
 *
 * du / au : première et dernière NUIT concernée (format AAAA-MM-JJ).
 * impact : 1 = un peu plus de demande, 2 = forte demande, 3 = très forte demande.
 * hausse : augmentation conseillée, en %, par rapport au prix habituel.
 * confirme : false = dates estimées d'après les éditions précédentes, à vérifier.
 * Dates relevées en octobre 2026 (agendas de Bordeaux Tourisme, Éducation nationale, organisateurs).
 */
globalThis.EVENEMENTS = [
  // ——— 2026 ———
  { nom: "Vacances de la Toussaint", du: "2026-10-17", au: "2026-11-01", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 10, confirme: true, info: "Toutes zones : familles en vacances." },
  { nom: "Marathon de Bordeaux", du: "2026-11-06", au: "2026-11-07", maisons: ["bordeaux"], impact: 2, hausse: 15, confirme: true, info: "Retour du marathon (dimanche 8 novembre) : coureurs et accompagnants arrivent la veille." },
  { nom: "Vacances de Noël", du: "2026-12-19", au: "2027-01-03", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 15, confirme: true, info: "Toutes zones. Grandes tablées familiales." },
  { nom: "Nouvel An", du: "2026-12-30", au: "2027-01-01", maisons: ["lacanau", "bordeaux"], impact: 3, hausse: 30, confirme: true, info: "Les nuits les plus demandées de l'hiver : séjour minimum conseillé." },
  // ——— 2027 ———
  { nom: "Jumping international de Bordeaux", du: "2027-02-03", au: "2027-02-06", maisons: ["bordeaux"], impact: 2, hausse: 15, confirme: true, info: "Concours hippique international (4 au 7 février), Parc des expositions." },
  { nom: "Vacances d'hiver, zone C (Paris, Toulouse, Montpellier)", du: "2027-02-06", au: "2027-02-21", maisons: ["lacanau", "bordeaux"], impact: 1, hausse: 5, confirme: true, info: "Clientèle parisienne et toulousaine." },
  { nom: "Vacances d'hiver, zone A (Bordeaux, Lyon…)", du: "2027-02-13", au: "2027-02-28", maisons: ["lacanau", "bordeaux"], impact: 1, hausse: 5, confirme: true, info: "Zone de la Gironde." },
  { nom: "Vacances d'hiver, zone B (Nantes, Lille, Marseille…)", du: "2027-02-20", au: "2027-03-07", maisons: ["lacanau", "bordeaux"], impact: 1, hausse: 5, confirme: true, info: "" },
  { nom: "Semaine sainte (Espagne)", du: "2027-03-20", au: "2027-03-28", maisons: ["lacanau", "bordeaux"], impact: 1, hausse: 5, confirme: true, info: "Vacances espagnoles : le site existe maintenant en espagnol." },
  { nom: "Week-end de Pâques", du: "2027-03-26", au: "2027-03-28", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 15, confirme: true, info: "Lundi de Pâques le 29 mars." },
  { nom: "Escales du livre", du: "2027-04-01", au: "2027-04-03", maisons: ["bordeaux"], impact: 1, hausse: 5, confirme: true, info: "Festival littéraire (2 au 4 avril)." },
  { nom: "Vacances de printemps, zone C", du: "2027-04-03", au: "2027-04-18", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 10, confirme: true, info: "Paris, Toulouse, Montpellier." },
  { nom: "Vacances de printemps, zone A", du: "2027-04-10", au: "2027-04-25", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 10, confirme: true, info: "Gironde, Lyon, Grenoble…" },
  { nom: "Vacances de printemps, zone B", du: "2027-04-17", au: "2027-05-02", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 10, confirme: true, info: "Nantes, Lille, Marseille…" },
  { nom: "Pont de l'Ascension", du: "2027-05-05", au: "2027-05-08", maisons: ["lacanau", "bordeaux"], impact: 3, hausse: 25, confirme: true, info: "Jeudi 6 mai : le plus long pont de l'année, très demandé à l'océan." },
  { nom: "Foire internationale de Bordeaux", du: "2027-05-15", au: "2027-05-23", maisons: ["bordeaux"], impact: 1, hausse: 5, confirme: false, info: "En mai, dates exactes pas encore publiées." },
  { nom: "Week-end de Pentecôte", du: "2027-05-14", au: "2027-05-16", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 15, confirme: true, info: "Lundi de Pentecôte le 17 mai." },
  { nom: "Vacances d'été — juillet", du: "2027-07-03", au: "2027-07-31", maisons: ["lacanau", "bordeaux"], impact: 3, hausse: 10, confirme: true, info: "Début des vacances le 3 juillet. Les prix Airbnb d'été sont déjà élevés : hausse modérée." },
  { nom: "Bordeaux Fête le Vin + Tall Ships Races", du: "2027-07-06", au: "2027-07-11", maisons: ["bordeaux"], impact: 3, hausse: 40, confirme: true, info: "7 au 11 juillet : la fête du vin et la course des grands voiliers ensemble, des centaines de milliers de visiteurs. Tout est complet très tôt." },
  { nom: "Caraïbos Lacanau Pro (surf)", du: "2027-07-06", au: "2027-07-13", maisons: ["lacanau"], impact: 2, hausse: 20, confirme: false, info: "Compétition internationale de surf, désormais en juillet (2026 : 8 au 14 juillet). Dates 2027 à confirmer." },
  { nom: "Vacances d'été — août", du: "2027-08-01", au: "2027-08-28", maisons: ["lacanau", "bordeaux"], impact: 3, hausse: 10, confirme: false, info: "Pleine saison, surtout autour du 15 août. Fin des vacances 2027 pas encore publiée." },
  { nom: "Marathon du Médoc", du: "2027-09-03", au: "2027-09-04", maisons: ["lacanau", "bordeaux"], impact: 2, hausse: 20, confirme: false, info: "Samedi 4 septembre prévu (Pauillac) : 8 000 coureurs déguisés et leurs proches, tout le Médoc est complet." },
];
