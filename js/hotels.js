/*
 * ============================================================
 *  BASE DE DONNÉES DES ÉTABLISSEMENTS
 * ============================================================
 *  Établissements réels, en France. Les informations proviennent des
 *  sites officiels et offices de tourisme (septembre 2026) : vérifie-les
 *  régulièrement, les hébergements évoluent.
 *
 *  Photos : assets/hotels/<id>/1.jpg, 2.jpg… (téléchargées depuis les sites
 *  officiels par la GitHub Action « Photos », voir scripts/photos.py).
 *  Le nombre de photos de chaque hôtel est indiqué par `photos`.
 *
 *  Champs :
 *   id          identifiant unique, sans espaces ni accents (sert à l'URL)
 *   env         "ville" | "campagne" | "mer" | "montagne"
 *   type        une clé de TYPES (voir plus bas)
 *   budget      1 à 4 (voir BUDGETS) : niveau de prix indicatif pour 2 personnes
 *   lat / lng   coordonnées GPS
 *   hero        1 à 6 : place dans le diaporama plein écran de l'accueil (optionnel)
 *   bookingUrl  lien de la fiche Booking.com (vide = recherche Booking par nom)
 *
 *  Champs réservés aux hôtels qui paient une offre (voir plans dans config.js) :
 *   plan        "partenaire" | "premium"  (absent = fiche gratuite)
 *   website     site officiel de l'hôtel (réservation directe)
 *   phone       téléphone affiché sur la fiche
 *   offer       offre spéciale, ex. "-10 % en réservant en direct avec le code NUITS"
 * ============================================================
 */

window.ENVIRONMENTS = {
  ville:    { inLabel: "en ville",       cover: "hotel-particulier-montmartre", label: "Ville",    desc: "Des adresses secrètes et audacieuses au cœur des villes." },
  campagne: { inLabel: "à la campagne",  cover: "domaine-des-etangs", label: "Campagne", desc: "Forêts, vignes et falaises : le silence, les étoiles, le temps retrouvé." },
  mer:      { inLabel: "en bord de mer", cover: "phare-de-kerbel", label: "Mer",      desc: "Phare, remparts et rochers rouges : l'horizon pour seul voisin." },
  montagne: { inLabel: "à la montagne",  cover: "refuge-de-solaise", label: "Montagne", desc: "Refuges d'altitude, igloos et chalets perchés au-dessus des nuages." },
};

window.TYPES = {
  cabane:     { label: "Cabane perchée",          icon: "🌳" },
  bulle:      { label: "Bulle sous les étoiles",  icon: "🫧" },
  troglodyte: { label: "Troglodyte",              icon: "🪨" },
  phare:      { label: "Phare",                   icon: "🗼" },
  igloo:      { label: "Igloo",                   icon: "❄️" },
  chalet:     { label: "Refuge & chalet",         icon: "🏔️" },
  eau:        { label: "Sur l'eau",               icon: "🛶" },
  chateau:    { label: "Château",                 icon: "🏰" },
  historique: { label: "Lieu chargé d'histoire",  icon: "🏛️" },
  design:     { label: "Design & architecture",   icon: "✨" },
  mer:        { label: "Les pieds dans l'eau",    icon: "🌊" },
  vignoble:   { label: "Au milieu des vignes",    icon: "🍇" },
};

window.BUDGETS = {
  1: { range: "moins de 150 € la nuit" },
  2: { range: "150 à 250 € la nuit" },
  3: { range: "250 à 450 € la nuit" },
  4: { range: "plus de 450 € la nuit" },
};

window.HOTELS = [
  // ——————————————————— CAMPAGNE ———————————————————
  {
    id: "loire-valley-lodges",
    name: "Loire Valley Lodges",
    tagline: "Dix-huit cabanes d'artistes perdues dans une forêt de 300 hectares",
    city: "Esvres-sur-Indre", department: "Indre-et-Loire", region: "Centre-Val de Loire",
    hero: 3, env: "campagne", type: "cabane", budget: 3, featured: true,
    lat: 47.2856, lng: 0.7858,
    address: "1 allée de la Duporterie, 37320 Esvres-sur-Indre",
    description: [
      "Au cœur d'une forêt privée de 300 hectares, à deux heures de Paris, dix-huit suites perchées ont chacune été confiées à un artiste contemporain différent. Grandes baies vitrées, lit king size, terrasse avec jacuzzi privatif : on a l'impression de dormir dans les arbres, entouré d'œuvres originales.",
      "Ici, pas d'écran ni de Wi-Fi : un talkie-walkie suffit pour commander le dîner ou réserver un massage. Entre deux bains de forêt, un sentier de sculptures monumentales serpente sous les chênes jusqu'à la piscine de 20 mètres.",
    ],
    highlights: ["Chaque cabane décorée par un artiste", "Jacuzzi privatif sur la terrasse", "Déconnexion totale : ni écran ni Wi-Fi"],
    amenities: ["Jacuzzi privatif", "Piscine de 20 m", "Restaurant", "Bar", "Massages", "Sentier de sculptures"],
    rooms: "18 suites-lodges",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "pella-roca",
    name: "Pella Roca",
    tagline: "Quatre cabanes-spa accrochées à la colline, face à la vallée du Quercy",
    city: "Quercy Blanc", department: "Tarn-et-Garonne", region: "Occitanie",
    hero: 5, env: "campagne", type: "cabane", budget: 2, featured: true,
    lat: 44.1333, lng: 1.6167,
    address: "Tarn-et-Garonne, entre Saint-Cirq-Lapopie et Saint-Antonin-Noble-Val",
    description: [
      "Aux portes du parc naturel des Causses du Quercy, quatre cabanes perchées dominent la vallée. Chacune possède son propre jacuzzi et son sauna privatif : on passe du bain chaud à la vue panoramique sans jamais croiser personne.",
      "Le domaine de 9 hectares mêle chênes truffiers, bois et landes autour d'un pigeonnier du XVIIe siècle. Petit-déjeuner maison, paniers-repas livrés, massages, piscine chauffée et VTT électriques pour partir explorer les villages du Lot.",
    ],
    highlights: ["Jacuzzi et sauna privatifs", "Vue panoramique sur la vallée", "Domaine de chênes truffiers"],
    amenities: ["Jacuzzi privatif", "Sauna privatif", "Piscine chauffée", "Petit-déjeuner maison", "Paniers-repas", "VTT électriques"],
    rooms: "4 cabanes perchées",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "cabanes-des-grands-lacs",
    name: "Cabanes des Grands Lacs",
    tagline: "Perchées, flottantes ou sur pilotis : 29 cabanes au milieu des étangs",
    city: "Chassey-lès-Montbozon", department: "Haute-Saône", region: "Bourgogne-Franche-Comté",
    env: "campagne", type: "cabane", budget: 2,
    lat: 47.5333, lng: 6.3333,
    address: "Domaine des Grands Lacs, 70230 Chassey-lès-Montbozon",
    description: [
      "Sur 150 hectares de nature préservée, au pied des Vosges, vingt-neuf cabanes se cachent dans les arbres, flottent sur les étangs ou se dressent sur pilotis. On y accède par des escaliers, des passerelles suspendues ou des échelles, entre 4 et 9 mètres de haut.",
      "Le matin, la brume se lève sur l'eau ; le soir, seuls les grenouilles et les hiboux troublent le silence. Une adresse idéale en famille comme en amoureux.",
    ],
    highlights: ["Cabanes flottantes sur les étangs", "Passerelles suspendues", "150 hectares de nature"],
    amenities: ["Petit-déjeuner", "Paniers-repas", "Parking"],
    rooms: "29 cabanes (perchées, flottantes, sur pilotis)",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "dihan",
    name: "Dihan",
    tagline: "Hôtel de cabanes, bulles et roulottes à deux pas de Carnac",
    city: "Ploemel", department: "Morbihan", region: "Bretagne",
    env: "campagne", type: "cabane", budget: 1,
    lat: 47.6509, lng: -3.0718,
    address: "56400 Ploemel",
    description: [
      "Pionnier des nuits insolites en Bretagne, Dihan a imaginé trente-deux hébergements dans 25 hectares de bois et de prairies : cabanes perchées, cabanes-spa, bulles suspendues, cabanes sur l'étang avec bain finlandais au feu de bois, roulottes, dômes et yourtes.",
      "La mer est à 7 kilomètres, les alignements de Carnac et la côte sauvage de Quiberon tout près. Premier site d'hébergements insolites de France labellisé Écolabel européen, et refuge LPO pour les oiseaux.",
    ],
    highlights: ["32 hébergements tous différents", "Bain finlandais au feu de bois", "Écolabel européen"],
    amenities: ["Petit-déjeuner", "Bains nordiques", "Massages", "Mer à 7 km"],
    rooms: "32 hébergements insolites",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "attrap-reves-allauch",
    name: "Attrap'Rêves",
    tagline: "Dormir dans une bulle transparente, sous le ciel de Provence",
    city: "Allauch", department: "Bouches-du-Rhône", region: "Provence-Alpes-Côte d'Azur",
    env: "campagne", type: "bulle", budget: 2, featured: true,
    lat: 43.3386, lng: 5.4822,
    address: "Chemin de la Ribassière, 13190 Allauch",
    description: [
      "Pionnier des nuits en bulle en France, Attrap'Rêves a installé ses bulles transparentes dans un parc boisé d'un hectare et demi, sur les hauteurs de Marseille. Un souffleur silencieux les maintient en forme : on s'endort protégé, les yeux dans les étoiles, à 360°.",
      "Chaque bulle a son ambiance (Zen, Jungle, Glamour, Mille et Une Nuits…) et sa salle de bain privative. Un télescope et une carte du ciel attendent les voyageurs, et le petit-déjeuner est inclus.",
    ],
    highlights: ["Vue à 360° sur les étoiles", "Télescope et carte du ciel", "Petit-déjeuner inclus"],
    amenities: ["Salle de bain privative", "Télescope", "Petit-déjeuner inclus", "Serviettes et produits d'accueil"],
    rooms: "Bulles pour 2 personnes, plusieurs ambiances",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "les-hautes-roches",
    name: "Les Hautes Roches",
    tagline: "Des chambres creusées dans la falaise, au bord de la Loire",
    city: "Rochecorbon", department: "Indre-et-Loire", region: "Centre-Val de Loire",
    env: "campagne", type: "troglodyte", budget: 3, featured: true,
    lat: 47.4130, lng: 0.7558,
    address: "Quai de la Loire, 37210 Rochecorbon",
    description: [
      "Entre Tours et Vouvray, douze chambres troglodytiques ont été aménagées dans la falaise de tuffeau, celle-là même dont on a extrait les pierres des grands châteaux de la Loire. Murs de pierre blanche, lumière douce et vue sur le fleuve.",
      "Un hôtel de luxe unique en son genre en France, où l'on dîne en terrasse face à la Loire avant de regagner sa chambre au cœur de la roche.",
    ],
    highlights: ["Chambres dans la falaise de tuffeau", "Vue sur la Loire", "Vignoble de Vouvray à deux pas"],
    amenities: ["Restaurant", "Terrasse sur la Loire", "Parking"],
    rooms: "12 chambres troglodytiques",
    photos: 5, bookingUrl: "", partners: {},
  },
  {
    id: "demeure-de-la-vignole",
    name: "La Demeure de la Vignole",
    tagline: "Une piscine creusée dans la roche qui ressort à l'air libre",
    city: "Turquant", department: "Maine-et-Loire", region: "Pays de la Loire",
    env: "campagne", type: "troglodyte", budget: 2,
    lat: 47.2236, lng: 0.0292,
    address: "49730 Turquant",
    description: [
      "Perchée sur le coteau qui domine la Loire, cette demeure du XVIIe siècle compte onze chambres, dont quatre creusées directement dans le tuffeau.",
      "Son joyau : une piscine taillée dans la roche, qui serpente sous la voûte avant de ressortir quelques mètres plus loin à l'air libre. Saumur et ses caves sont à dix minutes.",
    ],
    highlights: ["Piscine troglodytique", "4 chambres dans la roche", "Vue sur la Loire"],
    amenities: ["Piscine troglodytique", "Petit-déjeuner", "Parking"],
    rooms: "11 chambres, dont 4 troglodytiques",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "rocaminori",
    name: "Rocaminori",
    tagline: "Un hôtel entier sous la plaine, éclairé par des puits de lumière",
    city: "Louresse-Rochemenier", department: "Maine-et-Loire", region: "Pays de la Loire",
    env: "campagne", type: "troglodyte", budget: 2,
    lat: 47.2436, lng: -0.3197,
    address: "49700 Louresse-Rochemenier (Doué-en-Anjou)",
    description: [
      "Sous la plaine de Doué-la-Fontaine, quinze chambres ont été aménagées dans la roche, autour de cours à ciel ouvert. La lumière tombe doucement par des puits naturels, dans une atmosphère minérale et apaisante.",
      "Le village troglodytique de Rochemenier, le Bioparc de Doué et les vignobles du Saumurois sont à quelques minutes.",
    ],
    highlights: ["Chambres sous la plaine", "Puits de lumière naturels", "Village troglodytique voisin"],
    amenities: ["Petit-déjeuner", "Parking"],
    rooms: "15 chambres troglodytiques",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "fontevraud-l-ermitage",
    name: "Fontevraud L'Ermitage",
    tagline: "Dormir dans une abbaye royale millénaire, et s'y promener la nuit",
    city: "Fontevraud-l'Abbaye", department: "Maine-et-Loire", region: "Pays de la Loire",
    env: "campagne", type: "historique", budget: 2, featured: true,
    lat: 47.1817, lng: 0.0514,
    address: "Abbaye royale de Fontevraud, 49590 Fontevraud-l'Abbaye",
    description: [
      "Au cœur de l'abbaye royale de Fontevraud, où reposent Aliénor d'Aquitaine et Richard Cœur de Lion, cinquante-quatre chambres ont été aménagées, jusque dans l'ancien dortoir des moniales. Mobilier contemporain en chêne, sur mesure, dans le respect d'un monument de plus de mille ans.",
      "Le vrai privilège se vit à la nuit tombée : quand les visiteurs sont partis, l'abbaye s'offre aux seuls hôtes pour une promenade hors du temps. Petit-déjeuner servi dans le cloître aux beaux jours.",
    ],
    highlights: ["Visite de l'abbaye après la fermeture", "Petit-déjeuner dans le cloître", "Hôtel distingué d'une Clé Michelin"],
    amenities: ["Restaurant", "Petit-déjeuner dans le cloître", "Accès à l'abbaye", "Parking"],
    rooms: "54 chambres, dont duplex et chambres mansardées",
    photos: 4, bookingUrl: "", partners: {},
  },
  {
    id: "domaine-des-etangs",
    name: "Domaine des Étangs",
    tagline: "Un château de conte de fées au milieu de 1 000 hectares d'étangs et de forêts",
    city: "Massignac", department: "Charente", region: "Nouvelle-Aquitaine",
    hero: 6, env: "campagne", type: "chateau", budget: 4,
    lat: 45.7797, lng: 0.6508,
    address: "16310 Massignac",
    description: [
      "Entre Angoulême et Limoges, un château de conte de fées se dresse au milieu de mille hectares de forêts, de prairies et d'étangs. Les chambres et suites se répartissent entre le château, la longère et les cottages des anciennes métairies.",
      "Restaurant étoilé Dyades face à la vallée, spa installé dans un ancien moulin, court de tennis sur l'eau, barques et vélos pour explorer le domaine : un art de vivre à la française, hors du temps.",
    ],
    highlights: ["1 000 hectares de nature", "Restaurant étoilé", "Spa dans un ancien moulin"],
    amenities: ["Restaurant étoilé", "Spa", "Piscines intérieure et extérieure", "Tennis", "Barques et vélos"],
    rooms: "Chambres, suites et cottages",
    photos: 6, bookingUrl: "", partners: {},
  },

  // ——————————————————— MER ———————————————————
  {
    id: "phare-de-kerbel",
    name: "Phare de Kerbel",
    tagline: "Le seul phare de France où l'on dort tout en haut",
    city: "Riantec", department: "Morbihan", region: "Bretagne",
    hero: 2, env: "mer", type: "phare", budget: 4, featured: true,
    lat: 47.7093, lng: -3.3378,
    address: "71 route de Port-Louis, 56670 Riantec",
    description: [
      "Mis en service en 1913, le phare de Kerbel veille sur la rade de Lorient. Son sommet a été transformé en studio : c'est le seul phare de France où l'on peut dormir tout en haut, avec une vue à 360° sur l'océan et la rade.",
      "Au pied de la tour, la maison du gardien et l'ancienne « chambre à l'huile » accueillent jusqu'à huit personnes, avec piscine chauffée et sauna.",
    ],
    highlights: ["Studio au sommet du phare", "Vue à 360° sur la rade de Lorient", "Piscine chauffée et sauna"],
    amenities: ["Piscine chauffée", "Sauna", "Maison du gardien", "Jardin"],
    rooms: "Studio au sommet, maison du gardien et chambre à l'huile (8 pers. max)",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "les-roches-rouges",
    name: "Les Roches Rouges",
    tagline: "Une piscine d'eau de mer taillée dans la roche rouge de l'Esterel",
    city: "Saint-Raphaël", department: "Var", region: "Provence-Alpes-Côte d'Azur",
    hero: 4, env: "mer", type: "mer", budget: 4, featured: true,
    lat: 43.4213, lng: 6.8467,
    address: "Boulevard de la 36e Division du Texas, 83530 Saint-Raphaël",
    description: [
      "Face à l'île d'Or, au cœur du massif de l'Esterel, cet hôtel cinq étoiles cultive l'esprit de la Riviera des années 1950. Toutes les chambres ont un balcon sur la Méditerranée.",
      "Son image la plus célèbre : une piscine naturelle d'eau de mer de 30 mètres, creusée dans la roche rouge et caressée par les vagues. Paddle, kayak, randonnées dans l'Esterel, cinéma en plein air et deux restaurants face à la mer.",
    ],
    highlights: ["Piscine d'eau de mer dans la roche", "Toutes les chambres face à la mer", "Face à l'île d'Or"],
    amenities: ["Piscine d'eau de mer", "Piscine d'eau douce chauffée", "Restaurant", "Paddle et kayak", "Cinéma en plein air"],
    rooms: "Chambres et suites avec balcon vue mer",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "auberge-saint-pierre",
    name: "Auberge Saint-Pierre",
    tagline: "Une maison à colombages du XVe siècle, dans les remparts du Mont-Saint-Michel",
    city: "Le Mont-Saint-Michel", department: "Manche", region: "Normandie",
    env: "mer", type: "historique", budget: 2,
    lat: 48.6358, lng: -1.5105,
    address: "Grande Rue, 50170 Le Mont-Saint-Michel",
    description: [
      "Protégée par les remparts, sur la petite rue qui grimpe vers l'abbaye, cette maison à pans de bois du XVe siècle est inscrite aux monuments historiques. Ses chambres se répartissent dans plusieurs maisons anciennes du village.",
      "Dormir sur le Mont, c'est le découvrir quand les visiteurs sont repartis : la baie à marée montante, l'abbaye illuminée, les ruelles désertes au petit matin.",
    ],
    highlights: ["Dans les remparts du Mont", "Maison du XVe siècle", "La baie au coucher du soleil"],
    amenities: ["Restaurant", "Petit-déjeuner"],
    rooms: "Chambres réparties dans des maisons anciennes",
    photos: 6, bookingUrl: "", partners: {},
  },

  // ——————————————————— VILLE ———————————————————
  {
    id: "off-paris-seine",
    name: "OFF Paris Seine",
    tagline: "Le premier hôtel flottant de Paris, avec piscine sur la Seine",
    city: "Paris", department: "Paris", region: "Île-de-France",
    env: "ville", type: "eau", budget: 3, featured: true,
    lat: 48.8413, lng: 2.3698,
    address: "Port d'Austerlitz, 75013 Paris",
    description: [
      "Amarré au pied de la gare d'Austerlitz, le OFF est le premier hôtel flottant de Paris. Deux coques surmontées d'une structure de bois, de zinc, de cuivre et de verre abritent des chambres aménagées comme des cabines, les pieds dans l'eau.",
      "Au centre, une piscine chauffée semble se jeter dans la Seine. Le soir, le bar sur le pont offre l'une des plus belles vues sur les quais.",
    ],
    highlights: ["Hôtel flottant sur la Seine", "Piscine qui semble plonger dans le fleuve", "Chambres-cabines vue sur l'eau"],
    amenities: ["Piscine chauffée", "Bar", "Restaurant", "Terrasse sur la Seine"],
    rooms: "54 chambres et 4 suites",
    photos: 5, bookingUrl: "", partners: {},
  },
  {
    id: "hotel-le-corbusier",
    name: "Hôtel Le Corbusier",
    tagline: "Dormir dans la Cité radieuse, chef-d'œuvre classé à l'UNESCO",
    city: "Marseille", department: "Bouches-du-Rhône", region: "Provence-Alpes-Côte d'Azur",
    env: "ville", type: "design", budget: 1,
    lat: 43.2613, lng: 5.3962,
    address: "280 boulevard Michelet, 13008 Marseille",
    description: [
      "C'est le seul hôtel installé dans la Cité radieuse, l'unité d'habitation imaginée par Le Corbusier et inscrite au patrimoine mondial de l'UNESCO. Chambres-cabines de 16 m² conçues selon le Modulor, studios vue mer, mobilier d'époque : un voyage dans l'architecture du XXe siècle.",
      "Le restaurant Le Ventre de l'Architecte semble suspendu au-dessus de la ville et de la mer, et l'immeuble abrite aussi un toit-terrasse, une bibliothèque et un ciné-club.",
    ],
    highlights: ["Dans un bâtiment classé UNESCO", "Chambres conçues selon le Modulor", "Vue sur la mer"],
    amenities: ["Restaurant", "Toit-terrasse", "Bibliothèque"],
    rooms: "21 chambres",
    photos: 6, bookingUrl: "", partners: {},
  },

  // ——————————————————— MONTAGNE ———————————————————
  {
    id: "refuge-de-solaise",
    name: "Le Refuge de Solaise",
    tagline: "L'hôtel le plus haut de France, à 2 551 mètres",
    city: "Val-d'Isère", department: "Savoie", region: "Auvergne-Rhône-Alpes",
    env: "montagne", type: "chalet", budget: 4, featured: true,
    lat: 45.4337, lng: 6.9929,
    address: "Sommet de la télécabine de Solaise, 73150 Val-d'Isère",
    description: [
      "Installé dans l'ancienne gare d'arrivée de la télécabine de Solaise, ce chalet de bois perché à 2 551 mètres est l'hôtel le plus haut de France. L'hiver, on ne peut y monter que par la télécabine : une fois les pistes fermées, la montagne vous appartient.",
      "Chambres et suites cosy, appartements, dortoir de 14 lits pour les petits budgets, trois restaurants dont un avec terrasse panoramique, et un espace bien-être avec piscine de 25 mètres face aux sommets.",
    ],
    highlights: ["2 551 m d'altitude", "Accès en télécabine uniquement l'hiver", "Piscine de 25 m face aux sommets"],
    amenities: ["Piscine", "Espace bien-être", "3 restaurants", "Bar", "Ski aux pieds"],
    rooms: "16 chambres, 4 appartements et un dortoir",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "village-igloo-val-thorens",
    name: "Village Igloo Val Thorens",
    tagline: "Une nuit dans la glace, sur les pistes à 2 300 mètres",
    city: "Val Thorens", department: "Savoie", region: "Auvergne-Rhône-Alpes",
    env: "montagne", type: "igloo", budget: 3,
    lat: 45.2980, lng: 6.5800,
    address: "Piste de la Combe de Thorens, 73440 Val Thorens",
    description: [
      "Sur la piste de la Combe de Thorens, un village de glace de 300 m² sort de terre chaque hiver : bar, restaurant, sculptures de glace et chambres sous des igloos.",
      "La soirée commence par une balade en raquettes et un apéritif, se poursuit par un dîner savoyard, avant une nuit au chaud dans des duvets grand froid. Petit-déjeuner compris, au pied des pistes.",
    ],
    highlights: ["Chambres sous des igloos", "Balade en raquettes et dîner savoyard", "Sculptures de glace"],
    amenities: ["Dîner savoyard inclus", "Petit-déjeuner inclus", "Balade en raquettes", "Bar de glace"],
    rooms: "4 chambres (2 à 4 personnes)",
    season: "De fin décembre à mi-avril",
    photos: 6, bookingUrl: "", partners: {},
  },
  // ——————————————————— SUITE ———————————————————
  {
    id: "alpinest",
    name: "Alpinest",
    tagline: "Des cabanes-spa dans les arbres, entre Alpes et Provence",
    city: "Serres", department: "Hautes-Alpes", region: "Provence-Alpes-Côte d'Azur",
    env: "montagne", type: "cabane", budget: 3,
    lat: 44.4286, lng: 5.7178,
    address: "05700 Serres",
    description: [
      "Au cœur du parc naturel régional des Baronnies provençales, quatre cabanes perchées se cachent dans une forêt de trois hectares, sans aucun vis-à-vis. Chacune possède son spa privatif, chauffé toute l'année.",
      "Planches, dîners du chef ou brunchs gourmands sont livrés directement à la cabane, préparés par un cuisinier formé à l'Institut Paul Bocuse. Un domaine conçu avec l'ONF, refuge LPO pour la biodiversité.",
    ],
    highlights: ["Spa privatif chauffé toute l'année", "Aucun vis-à-vis", "Dîners du chef livrés à la cabane"],
    amenities: ["Spa privatif", "Dîner livré", "Brunch", "Parking"],
    rooms: "4 cabanes perchées",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "cabanes-du-moulin",
    name: "Les Cabanes du Moulin",
    tagline: "Trois cabanes-spa perchées au bord de la rivière, à 45 minutes de Paris",
    city: "Orly-sur-Morin", department: "Seine-et-Marne", region: "Île-de-France",
    env: "campagne", type: "cabane", budget: 2,
    lat: 48.9028, lng: 3.2331,
    address: "77750 Orly-sur-Morin",
    description: [
      "Au bord du Petit Morin, trois cabanes majestueuses sont perchées à 7 mètres de haut : la Cabane de la Rivière, la Cabane Spa de la Clairière et la Cabane Spa de l'Île. Deux d'entre elles ont leur jacuzzi privatif sur la terrasse, au milieu des branches.",
      "Barque, pêche et baignade dans la rivière, pétanque, ping-pong et feu de camp pour griller des chamallows : l'évasion totale à 45 minutes de Paris, ouverte toute l'année.",
    ],
    highlights: ["Jacuzzi perché à 7 mètres", "Au bord de la rivière", "À 45 minutes de Paris"],
    amenities: ["Jacuzzi privatif", "Barque", "Chauffage", "Wi-Fi", "Feu de camp"],
    rooms: "3 cabanes perchées",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "troglododo",
    name: "Troglododo",
    tagline: "Une ferme viticole troglodytique du XVIe siècle, près d'Azay-le-Rideau",
    city: "Azay-le-Rideau", department: "Indre-et-Loire", region: "Centre-Val de Loire",
    env: "campagne", type: "troglodyte", budget: 1,
    lat: 47.2597, lng: 0.4656,
    address: "9 chemin des Caves, 37190 Azay-le-Rideau",
    description: [
      "Sur un coteau exposé plein sud face à la vallée de l'Indre, cette ancienne ferme viticole du XVIe siècle a été creusée dans le tuffeau blanc. Six de ses quatorze chambres sont troglodytiques : murs courbes, fraîcheur constante et lumière tamisée.",
      "Le château d'Azay-le-Rideau et la Loire à Vélo sont à deux pas : une adresse de charme à petit prix au cœur des châteaux de la Loire.",
    ],
    highlights: ["Chambres creusées dans le tuffeau", "Vue sur la vallée de l'Indre", "Château d'Azay-le-Rideau tout proche"],
    amenities: ["Petit-déjeuner", "Parking", "Accès Loire à Vélo"],
    rooms: "14 chambres, dont 6 troglodytiques",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "hotel-particulier-montmartre",
    name: "Hôtel Particulier Montmartre",
    tagline: "Cinq suites d'artistes et le plus grand jardin d'hôtel de Paris",
    city: "Paris", department: "Paris", region: "Île-de-France",
    env: "ville", type: "design", budget: 3, featured: true,
    lat: 48.8883, lng: 2.3353,
    address: "23 avenue Junot, 75018 Paris",
    description: [
      "Au bout d'une allée pavée, entre l'avenue Junot et la rue Lepic, se cache une ancienne demeure de la famille Hermès. On y entre comme chez des amis : cinq suites seulement, chacune imaginée avec un artiste différent.",
      "Autour de la maison, un jardin secret de 900 m² dessiné par le paysagiste Louis Benech, le plus grand jardin d'hôtel de la capitale. Le soir, le bar Le Très Particulier sert ses cocktails sous la verrière.",
    ],
    highlights: ["Seulement 5 suites d'artistes", "Jardin secret de 900 m²", "Au sommet de Montmartre"],
    amenities: ["Jardin", "Bar à cocktails", "Restaurant"],
    rooms: "5 suites de 35 à 85 m²",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "cour-des-loges",
    name: "Cour des Loges",
    tagline: "Quatre demeures Renaissance reliées par six cours, au cœur du Vieux Lyon",
    city: "Lyon", department: "Rhône", region: "Auvergne-Rhône-Alpes",
    env: "ville", type: "historique", budget: 4,
    lat: 45.7631, lng: 4.8271,
    address: "Rue du Bœuf, 69005 Lyon",
    description: [
      "Rue du Bœuf, quatre bâtiments construits entre le XIVe et le XVIe siècle sont reliés par six cours intérieures. Autour, les ruelles pavées et les traboules secrètes du Vieux Lyon.",
      "Chaque chambre est unique : certaines ont une mezzanine, une baignoire au centre de la pièce ou une vue sur les traboules. Le spa, inspiré des thermes romains, abrite une piscine sous une voûte.",
    ],
    highlights: ["Demeures des XIVe-XVIe siècles", "Six cours Renaissance", "Spa inspiré des thermes romains"],
    amenities: ["Restaurant gastronomique", "Spa", "Piscine intérieure", "Hammam", "Bar"],
    rooms: "61 chambres et suites",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "fermes-de-marie",
    name: "Les Fermes de Marie",
    tagline: "Un hameau de fermes d'alpage centenaires, au cœur de Megève",
    city: "Megève", department: "Haute-Savoie", region: "Auvergne-Rhône-Alpes",
    env: "montagne", type: "chalet", budget: 4,
    lat: 45.8567, lng: 6.6175,
    address: "74120 Megève",
    description: [
      "À quelques minutes de la place du village, un petit hameau de chalets a été construit avec les bois de fermes d'alpage vieilles de plusieurs siècles. Le charme de l'ancien, la simplicité montagnarde et le raffinement d'un cinq étoiles.",
      "La Ferme de Beauté, son spa, propose piscine, jacuzzi, sauna et hammam, avec des soins aux plantes de montagne. Pour les tribus, un chalet privé de 400 m² accueille jusqu'à dix personnes.",
    ],
    highlights: ["Chalets en bois de fermes centenaires", "Spa aux plantes de montagne", "Au cœur de Megève"],
    amenities: ["Spa", "Piscine intérieure", "Sauna et hammam", "Restaurant", "Bar", "Chalet privé"],
    rooms: "Chambres, suites et chalet privé",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "chateau-de-la-resle",
    name: "Château de la Resle",
    tagline: "Un château du XVIIe siècle rempli d'art contemporain, près de Chablis",
    city: "Montigny-la-Resle", department: "Yonne", region: "Bourgogne-Franche-Comté",
    env: "campagne", type: "chateau", budget: 3,
    lat: 47.8628, lng: 3.6817,
    address: "89230 Montigny-la-Resle",
    description: [
      "Entre Auxerre et Chablis, ce château du XVIIe siècle a gardé ses grands escaliers et sa tour ronde coiffée d'un toit pointu. À l'intérieur, meubles d'époque et œuvres d'art contemporain se répondent : chaque suite a son propre univers.",
      "Autour, un domaine de six hectares avec jardins, serres, verger et piscine chauffée. Spa avec sauna et hammam, et les caves de Chablis à dix minutes.",
    ],
    highlights: ["Art contemporain dans un château", "Seulement 7 chambres et suites", "Vignobles de Chablis à 10 min"],
    amenities: ["Piscine chauffée", "Spa", "Sauna et hammam", "Restaurant", "Jardins"],
    rooms: "2 chambres et 5 suites",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "chateau-de-mercues",
    name: "Château de Mercuès",
    tagline: "L'ancienne résidence des évêques de Cahors, perchée au-dessus du Lot",
    city: "Mercuès", department: "Lot", region: "Occitanie",
    env: "campagne", type: "chateau", budget: 3,
    lat: 44.4969, lng: 1.3906,
    address: "46090 Mercuès",
    description: [
      "Perché sur un éperon rocheux, ce château du XIIIe siècle fut pendant sept siècles la résidence d'été des comtes-évêques de Cahors. De toutes parts, la vue plonge sur la vallée du Lot et les vignes du malbec.",
      "Chaque chambre est décorée selon une époque de l'histoire. Sous les jardins, un chai voûté creusé dans la roche abrite les vins du domaine de 35 hectares, à déguster après un dîner au restaurant du château.",
    ],
    highlights: ["Château du XIIIe siècle", "Vue sur la vallée du Lot", "Chai voûté creusé dans la roche"],
    amenities: ["Restaurant", "Piscine", "Dégustation de vins", "Relais & Châteaux"],
    rooms: "25 chambres et 5 suites",
    photos: 4, bookingUrl: "", partners: {},
  },
  {
    id: "sources-de-caudalie",
    name: "Les Sources de Caudalie",
    tagline: "Un hameau de bois et de pierre au milieu des grands crus de Bordeaux",
    city: "Martillac", department: "Gironde", region: "Nouvelle-Aquitaine",
    env: "campagne", type: "vignoble", budget: 4,
    lat: 44.7358, lng: -0.5561,
    address: "Chemin de Smith Haut Lafitte, 33650 Martillac",
    description: [
      "Au milieu des vignes du Château Smith Haut Lafitte, à vingt minutes de Bordeaux, l'hôtel a été bâti avec des matériaux anciens et recyclés, comme un hameau aquitain. La suite la plus célèbre, l'Île aux Oiseaux, rappelle les cabanes tchanquées du bassin d'Arcachon, sur pilotis au-dessus de l'eau.",
      "Spa de vinothérapie, restaurant gastronomique La Grand'Vigne, auberge de campagne et bar à vins : une immersion totale dans l'art de vivre bordelais.",
    ],
    highlights: ["Au cœur d'un grand cru classé", "Suite sur pilotis au-dessus de l'eau", "Spa de vinothérapie"],
    amenities: ["Spa", "Piscine", "Restaurant gastronomique", "Bar à vins", "Visites de chai"],
    rooms: "Chambres et suites signature",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "casadelmar",
    name: "Casadelmar",
    tagline: "Bois, pierre et verre face au golfe de Porto-Vecchio",
    city: "Porto-Vecchio", department: "Corse-du-Sud", region: "Corse",
    env: "mer", type: "mer", budget: 4,
    lat: 41.6166, lng: 9.3155,
    address: "20137 Porto-Vecchio",
    description: [
      "Caché dans un parc méditerranéen de trois hectares dont les terrasses descendent jusqu'à la mer, Casadelmar est sans doute l'hôtel le plus confidentiel de Corse. L'architecte Jean-François Bodin a orienté chaque lit face à la mer.",
      "Les trente-quatre chambres et suites, de 35 à 75 m², s'ouvrent entièrement sur de grandes terrasses. Le soir, la table doublement étoilée prolonge le voyage.",
    ],
    highlights: ["Chaque lit face à la mer", "Parc de 3 hectares jusqu'à l'eau", "Restaurant deux étoiles"],
    amenities: ["Plage privée", "Piscine", "Spa", "Restaurant gastronomique"],
    rooms: "34 chambres et suites",
    photos: 6, bookingUrl: "", partners: {},
  },
  {
    id: "la-coorniche",
    name: "La Co(o)rniche",
    tagline: "Un pavillon de chasse revu par Philippe Starck, face à la dune du Pilat",
    city: "Pyla-sur-Mer", department: "Gironde", region: "Nouvelle-Aquitaine",
    hero: 1, env: "mer", type: "design", budget: 4, featured: true,
    lat: 44.5808, lng: -1.2090,
    address: "Avenue Louis Gaume, 33115 Pyla-sur-Mer",
    description: [
      "Adossé à la plus haute dune d'Europe, suspendu entre la mer et le ciel, cet ancien pavillon de chasse des années 1930 a été métamorphosé par Philippe Starck. Bois, verre et matières naturelles, dans l'esprit de l'âge d'or de la Côte d'Argent.",
      "Sa piscine à débordement semble se jeter dans le bassin d'Arcachon, face au banc d'Arguin. Au coucher du soleil, la terrasse du restaurant devient l'un des plus beaux points de vue de la côte atlantique.",
    ],
    highlights: ["Face à la dune du Pilat", "Piscine à débordement sur l'océan", "Design Philippe Starck"],
    amenities: ["Piscine à débordement", "Restaurant", "Bar", "Terrasse panoramique"],
    rooms: "29 chambres et suites",
    photos: 6, bookingUrl: "", partners: {},
  },
];

/* Chemins des photos : assets/hotels/<id>/1.jpg …
 * Un établissement sans photo n'est pas affiché (le temps de récupérer ses photos). */
window.HOTELS.forEach((h) => {
  h.images = Array.from({ length: h.photos || 0 }, (_, i) => `assets/hotels/${h.id}/${i + 1}.jpg`);
});
window.HOTELS = window.HOTELS.filter((h) => h.images.length);
