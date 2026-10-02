/*
 * Les deux maisons : tout le contenu des fiches est ici.
 *
 * Source : les annonces Airbnb (récupérées automatiquement dans
 * data/airbnb/, voir scripts/airbnb.py). Les textes entre guillemets
 * « description » sont ceux de l'annonce, sans modification. Rien n'est
 * inventé : si une information change sur Airbnb, change-la aussi ici.
 *
 * Photos : chaque numéro correspond aux fichiers
 * assets/photos/<maison>/NN-xl.webp (grand), NN-md.webp (moyen), NN-sm.webp (petit).
 */
window.HOUSES = {
  lacanau: {
    id: "lacanau",
    page: "lacanau.html",
    name: "La Maison du Lac",
    place: "Lacanau · Le Moutchic",
    region: "Gironde, côte atlantique",
    kicker: "L'océan",
    tagline: "Piscine, jardin et lac à cinquante mètres",
    title: "Maison de famille avec piscine, au bord du lac de Lacanau",
    short: "Grande maison au bord du lac, spacieuse et confortable.",
    teaser:
      "Une maison de famille couverte de vigne vierge, ouverte sur le jardin et la piscine, à cinquante mètres du lac de Lacanau et à dix minutes de l'océan.",
    airbnbId: "662061426615418606",
    airbnbUrl: "https://www.airbnb.fr/rooms/662061426615418606",
    type: "Maison entière",
    guests: 12,
    bedrooms: 6,
    beds: 7,
    bathrooms: 2,
    toilets: 4,
    rating: 5.0,
    reviewsCount: 13,
    guestFavorite: true,
    superhost: true,
    categoryRatings: [
      ["Propreté", "5,0"], ["Précision", "5,0"], ["Arrivée", "5,0"],
      ["Communication", "5,0"], ["Emplacement", "5,0"], ["Qualité-prix", "4,8"],
    ],
    // Sujets les plus cités dans les avis (nombre d'avis qui en parlent, selon Airbnb)
    reviewTags: [["Hospitalité", 11], ["Piscine", 7], ["Décoration", 7], ["Famille", 6], ["Emplacement", 6], ["Espaces extérieurs", 5], ["Espaces intérieurs", 5], ["À proximité", 4], ["Calme", 3], ["Plage", 2]],
    // Répartition des notes (5, 4, 3, 2, 1 étoiles), en %
    ratingDistribution: [100, 0, 0, 0, 0],
    // Prix indicatif « à partir de … € la nuit ». Laisse null pour ne rien afficher.
    priceFrom: null,
    checkIn: "À partir de 16 h",
    checkOut: "Avant 10 h",
    // Coordonnées : position publiée par Airbnb. Sur la carte, on montre
    // seulement un cercle autour (l'adresse exacte est donnée après réservation).
    lat: 45.0042,
    lng: -1.1284,
    weather: { lat: 45.0042, lng: -1.1284, sea: { lat: 45.00, lng: -1.21 }, label: "Lacanau" },
    hero: [18, 20, 21, 27, 4],
    cover: 18,
    inset: 27,
    // Texte de l'annonce (sans modification)
    description: [
      { title: null, text: "Grande maison au bord du lac, spacieuse et confortable." },
      {
        title: "Le logement",
        text:
          "Notre maison est une maison de famille. Elle est un vrai havre de paix ! Nous y passons des moments merveilleux et de pur bonheur.\nCalme, et sans vis-à-vis.\nLes pièces de vie donnent sur le jardin et la piscine. 2 chambres et une salle de bain sont de plain-pied.\nLa cuisine est entièrement équipée, et est ouverte sur l'espace de vie.\nLes 4 autres chambres sont en étage. La maison a également 4 WC, pratique lorsque l'on est nombreux.",
      },
      {
        title: "Accès des voyageurs",
        text:
          "Toute la maison est accessible aux voyageurs.\nVous pouvez garer 1 voiture dans un espace dédié, et à 20 m, vous avez des stationnements gratuits.",
      },
    ],
    highlights: [
      ["pool", "Piscine privée", "Extérieure, disponible d'avril à octobre."],
      ["lake", "Le lac à 50 mètres", "Au Moutchic, avec quelques restaurants à 3 minutes à pied au bord de l'eau."],
      ["wave", "L'océan à 10 minutes", "En voiture, ou 20 minutes à vélo."],
      ["leaf", "Calme, sans vis-à-vis", "Les pièces de vie donnent sur le jardin et la piscine."],
    ],
    neighbourhood:
      "Nous sommes au Moutchic, la maison est à 50 m du lac, 10 min en voiture de l'océan (ou 20 min à vélo), 3 min en voiture du golf et 7 min en voiture du supermarché. Quelques restaurants sont à 3 min à pied au bord du lac.",
    gettingAround: "Lacanau ville et Lacanau-Océan sont à 10 min en voiture.",
    sleeping: [
      ["Chambre 1", "1 lit king size", 6],
      ["Chambre 2", "1 lit double", 9],
      ["Chambre 3", "1 lit double", 10],
      ["Chambre 4", "1 lit double", 11],
      ["Chambre 5", "1 lit double et 1 lit simple", 12],
      ["Chambre 6", "1 lit double", 13],
    ],
    amenities: [
      ["Extérieur", ["Piscine extérieure privée (d'avril à octobre)", "Jardin, vue sur le jardin", "Patio privé", "Mobilier d'extérieur", "Espace repas en plein air", "Chaises longues"]],
      ["Emplacement", ["Au bord de l'eau, juste à côté d'un plan d'eau", "Accès au lac par un sentier ou un quai", "Accès à une plage à proximité"]],
      ["Cuisine et salle à manger", ["Cuisine entièrement équipée, ouverte sur l'espace de vie", "Réfrigérateur, mini réfrigérateur et congélateur", "Lave-vaisselle", "Four en acier inoxydable et four à micro-ondes", "Plaques de cuisson", "Cafetière filtre et machine à expresso", "Bouilloire électrique, grille-pain", "Verres à vin, vaisselle et couverts", "Tout le nécessaire pour cuisiner (casseroles, poêles, huile, sel, poivre)", "Table à manger"]],
      ["Chambres et linge", ["Linge de lit en coton", "Serviettes, draps, savon et papier toilette", "Stores ou rideaux occultants", "Dressing et placards", "Cintres, fer à repasser, étendoir à linge", "Lave-linge"]],
      ["Salles de bain", ["Baignoire", "Sèche-cheveux", "Shampoing, gel douche, savon", "Eau chaude", "4 WC dans la maison"]],
      ["Vivre et travailler", ["Wifi et connexion Ethernet", "Espace de travail dédié", "Télévision", "Système audio Bluetooth", "Livres et jeux de société", "Chauffage central"]],
      ["Pratique", ["1 place de stationnement privée, gratuite", "Stationnement gratuit dans la rue, à 20 m", "Dépôt de bagages possible"]],
    ],
    notIncluded: ["Climatisation", "Sèche-linge", "Détecteur de monoxyde de carbone"],
    rules: {
      "Arrivée et départ": ["Arrivée à partir de 16 h", "Départ avant 10 h"],
      "Pendant le séjour": ["12 voyageurs maximum", "Pas d'animaux", "Pas de fête ni de soirée", "Non fumeur", "Calme de 23 h à 7 h"],
      "Bon à savoir": ["Piscine sans clôture ni verrou : surveillance des enfants indispensable", "Lac à proximité", "La maison comprend des escaliers", "Caméras de surveillance extérieures présentes", "Détecteur de fumée installé"],
    },
    registration: null,
    // La maison niveau par niveau (d'après la description de l'annonce)
    levels: [
      { name: "Le jardin", short: "Extérieur", photo: 20, items: ["Piscine privée, ouverte d'avril à octobre", "Jardin sans vis-à-vis", "Patio, salon et salle à manger d'extérieur", "Chaises longues", "Le lac à 50 mètres"] },
      { name: "Le rez-de-chaussée", short: "Rez-de-chaussée", photo: 4, items: ["Salon et salle à manger ouverts sur le jardin et la piscine", "Cuisine entièrement équipée, ouverte sur l'espace de vie", "2 chambres de plain-pied", "1 salle de bain", "Espace de travail"] },
      { name: "L'étage", short: "Étage", photo: 10, items: ["4 chambres", "Au total dans la maison : 6 chambres, 7 lits, 2 salles de bain et 4 WC"] },
    ],
    // Repères autour de la maison (distances à vol d'oiseau calculées sur la carte)
    poi: [
      ["beach", "Plage centrale de Lacanau-Océan", 45.0012, -1.2036],
      ["city", "Bordeaux, place de la Comédie", 44.8425, -0.5741],
      ["wine", "Margaux, route des grands vins", 45.0399, -0.6757],
      ["wine", "Pauillac", 45.1990, -0.7480],
      ["beach", "Cap Ferret", 44.6262, -1.2489],
      ["beach", "Dune du Pilat", 44.5893, -1.2132],
      ["travel", "Aéroport de Bordeaux-Mérignac", 44.8283, -0.7156],
      ["travel", "Gare de Bordeaux-Saint-Jean", 44.8256, -0.5560],
    ],
    photos: [
      [18, "La maison et la piscine"],
      [1, "Le salon"],
      [20, "La piscine"],
      [4, "La salle à manger, ouverte sur la piscine"],
      [21, "Coucher de soleil sur la piscine"],
      [22, "Le patio"],
      [23, "Le salon d'extérieur"],
      [6, "Chambre 1"],
      [3, "La cuisine"],
      [27, "Le ponton, sur le lac"],
      [17, "Le jardin"],
      [19, "Bord de piscine"],
      [24, "La maison, le soir"],
      [2, "Le salon, côté cheminée"],
      [5, "La salle à manger"],
      [7, "Chambre 1"],
      [8, "Chambre 1"],
      [9, "Chambre 2"],
      [10, "Chambre 3"],
      [11, "Chambre 4"],
      [12, "Chambre 5"],
      [13, "Chambre 6"],
      [14, "Salle de bain"],
      [15, "Salle de bain"],
      [16, "Espace de travail"],
      [25, "Entrée"],
      [26, "Le jardin"],
    ],
  },

  bordeaux: {
    id: "bordeaux",
    page: "bordeaux.html",
    name: "La Maison de Pierre",
    place: "Bordeaux · Centre",
    region: "Gironde, ville classée à l'Unesco",
    kicker: "La ville",
    tagline: "Pierre de taille, lumière et hypercentre à pied",
    title: "Maison de ville en pierre de taille, à dix minutes à pied de l'hypercentre",
    short: "Une maison en pierre de taille récemment rénovée, baignée de lumière, au calme.",
    teaser:
      "Une maison bordelaise en pierre de taille, récemment rénovée : grande pièce de vie sous verrière à l'étage, terrasse, cinq chambres, et l'hypercentre à dix minutes à pied.",
    airbnbId: "50226249",
    airbnbUrl: "https://www.airbnb.fr/rooms/50226249",
    type: "Maison de ville entière",
    guests: 8,
    bedrooms: 5,
    beds: 5,
    bathrooms: 2,
    toilets: 2,
    rating: 4.88,
    reviewsCount: 41,
    guestFavorite: true,
    superhost: true,
    categoryRatings: [
      ["Propreté", "4,8"], ["Précision", "5,0"], ["Arrivée", "5,0"],
      ["Communication", "5,0"], ["Emplacement", "4,9"], ["Qualité-prix", "4,6"],
    ],
    reviewTags: [["Hospitalité", 29], ["Emplacement", 23], ["Espaces intérieurs", 19], ["Décoration", 15], ["Se déplacer", 9], ["Accessibilité à pied", 8], ["Arrivée", 6], ["Départ", 6], ["Qualité du sommeil", 4], ["Calme", 3]],
    ratingDistribution: [90, 7, 2, 0, 0],
    priceFrom: null,
    checkIn: "Arrivée autonome, horaire flexible",
    checkOut: "Avant 12 h",
    // Position approximative publiée par Airbnb (l'adresse exacte est
    // communiquée après la réservation).
    lat: 44.83796,
    lng: -0.59192,
    weather: { lat: 44.8378, lng: -0.5792, label: "Bordeaux" },
    hero: [2, 1, 7, 13, 8],
    cover: 2,
    inset: 4,
    description: [
      {
        title: null,
        text:
          "Ma maison est composée de 5 chambres, dont 3 chambres, une salle de bain et un WC au rez-de-chaussée et 2 chambres en sous-sol, ainsi qu'une salle d'eau et un WC ; la pièce de vie et la terrasse se trouvent à l'étage.\nLa maison est baignée de lumière, au calme, et à proximité directe de l'hypercentre.\nC'est une maison en pierre de taille récemment rénovée.",
      },
      {
        title: "Le logement",
        text:
          "Ma maison est un lieu de bonheur, tout est à disposition, sel, poivre, huile, nous y vivons avec mes enfants, donc vous y trouverez tout ce dont vous avez besoin !",
      },
      { title: "Accès des voyageurs", text: "Toutes les pièces sont ouvertes aux voyageurs." },
      { title: "Autres remarques", text: "La maison ne peut recevoir d'animaux à cause des allergies familiales !" },
    ],
    highlights: [
      ["key", "Arrivée autonome", "Avec une boîte à clé sécurisée, à l'heure qui vous convient."],
      ["walk", "L'hypercentre à 10 minutes à pied", "Tram et bus à 4 minutes à pied de la maison."],
      ["sun", "Baignée de lumière", "Pièce de vie sous verrière et terrasse, à l'étage."],
      ["tv", "TV HD 83 pouces avec Netflix", "Et un système audio Bluetooth Bang & Olufsen."],
    ],
    neighbourhood: "Le tramway et le bus sont à 4 min à pied de la maison ! Et l'hypercentre à 10 min à pied.",
    gettingAround: "Tram et bus à 4 min à pied.",
    sleeping: [
      ["Chambre 1", "1 lit double", 18],
      ["Chambre 2", "1 lit double", 20],
      ["Chambre 3", "1 lit double", 22],
      ["Chambre 4", "1 lit double", 25],
      ["Chambre 5", "1 lit double", 26],
    ],
    amenities: [
      ["Vivre", ["Pièce de vie et terrasse à l'étage", "Patio privé et jardin", "TV HD 83 pouces avec Netflix", "Système audio Bluetooth Bang & Olufsen", "Appareils de fitness", "Livres et de quoi lire", "Chauffage radiant"]],
      ["Cuisine et salle à manger", ["Cuisine équipée", "Cuisinière à induction et four", "Four à micro-ondes", "Réfrigérateur et congélateur", "Lave-vaisselle", "Cafetière filtre et Nespresso", "Bouilloire électrique, grille-pain", "Verres à vin, vaisselle et couverts", "Tout le nécessaire pour cuisiner (casseroles, poêles, huile, sel, poivre)", "Table à manger"]],
      ["Chambres et linge", ["Linge de lit", "Serviettes, draps, savon et papier toilette", "Stores ou rideaux occultants", "Espace de rangement pour les vêtements", "Cintres, fer à repasser, étendoir à linge", "Lave-linge et sèche-linge"]],
      ["Salles de bain", ["Une salle de bain avec baignoire et une salle d'eau", "Sèche-cheveux", "Shampoing, après-shampoing, gel douche, savon", "Eau chaude"]],
      ["Famille et travail", ["Livres et jouets pour enfants (5 à 10 ans)", "Jeux de société", "Wifi et connexion Ethernet", "Espace de travail dédié"]],
      ["Pratique", ["Arrivée autonome avec boîte à clé sécurisée", "Dépôt de bagages possible", "Stationnement payant dans la rue et parking payant", "Laverie automatique à proximité", "Trousse de premiers secours", "Détecteur de fumée"]],
    ],
    notIncluded: ["Climatisation", "Stationnement privé"],
    rules: {
      "Arrivée et départ": ["Arrivée flexible, en autonomie (boîte à clé sécurisée)", "Départ avant 12 h"],
      "Pendant le séjour": ["8 voyageurs maximum", "Pas d'animaux (allergies familiales)", "Pas de fête ni de soirée", "Non fumeur", "Calme de 23 h à 7 h"],
      "Avant de partir": ["Sortir les poubelles dans les bacs devant la maison", "Défaire les lits, déposer draps et serviettes dans la buanderie", "Éteindre les lumières et les appareils, tout verrouiller"],
      "Bon à savoir": ["Ne convient pas aux bébés (moins de 2 ans)", "La maison comprend des escaliers", "Caméras de surveillance extérieures présentes", "Pas de stationnement sur place"],
    },
    // Numéro d'enregistrement de la mairie de Bordeaux (obligatoire sur toute annonce)
    registration: "3306300578621",
    levels: [
      { name: "L'étage", short: "Étage", photo: 2, items: ["La pièce de vie sous verrière : salon, cuisine et salle à manger", "La terrasse", "TV HD 83 pouces et son Bang & Olufsen"] },
      { name: "Le rez-de-chaussée", short: "Rez-de-chaussée", photo: 24, items: ["3 chambres", "1 salle de bain avec baignoire", "1 WC", "L'entrée"] },
      { name: "Le sous-sol", short: "Sous-sol", photo: null, items: ["2 chambres", "1 salle d'eau", "1 WC", "La buanderie"] },
    ],
    poi: [
      ["walk", "Place Gambetta", 44.8410, -0.5800],
      ["walk", "Place de la Comédie et Grand-Théâtre", 44.8425, -0.5741],
      ["walk", "Cathédrale Saint-André", 44.8378, -0.5777],
      ["walk", "Jardin public", 44.8487, -0.5776],
      ["walk", "Place de la Bourse et Miroir d'eau", 44.8413, -0.5694],
      ["walk", "Marché des Capucins", 44.8309, -0.5677],
      ["walk", "Quartier des Chartrons", 44.8550, -0.5700],
      ["wine", "La Cité du Vin", 44.8625, -0.5503],
      ["travel", "Gare de Bordeaux-Saint-Jean", 44.8256, -0.5560],
      ["travel", "Aéroport de Bordeaux-Mérignac", 44.8283, -0.7156],
      ["wine", "Saint-Émilion", 44.8940, -0.1550],
      ["beach", "Lacanau-Océan", 45.0012, -1.2036],
    ],
    photos: [
      [2, "La pièce de vie sous verrière"],
      [4, "La terrasse"],
      [7, "Le salon"],
      [8, "La salle à manger"],
      [1, "Le séjour"],
      [13, "La verrière, le soir"],
      [18, "Chambre"],
      [10, "Salle de bain"],
      [3, "Le séjour"],
      [12, "L'îlot"],
      [14, "Le séjour"],
      [17, "Le séjour"],
      [9, "Détail"],
      [16, "Détail"],
      [15, "Détail"],
      [5, "Détail"],
      [19, "Chambre"],
      [20, "Chambre"],
      [21, "Chambre"],
      [22, "Chambre"],
      [25, "Chambre"],
      [26, "Chambre"],
      [27, "Chambre"],
      [11, "Salle de bain"],
      [6, "Salle d'eau"],
      [23, "Salle d'eau"],
      [24, "Entrée et escalier"],
    ],
  },
};

/* Ce qu'il y a autour : informations générales et vérifiables, temps
   indicatifs en voiture ou à pied. */
window.DESTINATIONS = {
  lacanau: {
    title: "Lacanau, <em>entre lac et océan</em>",
    intro:
      "Sur la côte médocaine, Lacanau réunit deux mondes : un grand lac d'eau douce bordé de pins, idéal pour les enfants, la voile et le paddle, et l'océan, ses plages de sable fin et ses vagues réputées des surfeurs. La maison est au Moutchic, côté lac, à dix minutes de la plage.",
    places: [
      ["Le lac de Lacanau", "50 m à pied", "Baignade en eau calme, voile, paddle, kayak, pique-niques à l'ombre des pins. Quelques restaurants vous attendent au bord de l'eau, à 3 minutes à pied de la maison."],
      ["Les plages de Lacanau-Océan", "10 min en voiture", "Des kilomètres de sable face à l'Atlantique, des plages surveillées en saison et l'un des spots de surf les plus connus de la côte. Les couchers de soleil y sont spectaculaires."],
      ["Les pistes cyclables", "À proximité", "Un réseau de pistes cyclables traverse la forêt de pins entre le lac et l'océan : comptez une vingtaine de minutes à vélo jusqu'à la plage."],
      ["Le golf", "3 min en voiture", "Pour les amateurs, un parcours au milieu des pins, tout près de la maison."],
      ["Les grands vins du Médoc", "Environ 45 min", "Les châteaux de la route des vins (Margaux, Pauillac, Saint-Julien…) se visitent sur rendez-vous, pour une journée de dégustations."],
      ["Bordeaux", "Environ 1 h de route", "Et la Maison de Pierre, pour combiner océan et ville dans le même voyage."],
    ],
  },
  bordeaux: {
    title: "Bordeaux, <em>la belle endormie réveillée</em>",
    intro:
      "Façades de pierre blonde, quais réaménagés le long de la Garonne, marchés, bars à vin et tables de chefs : Bordeaux se vit à pied ou en tram. Une partie de la ville, le « Port de la Lune », est inscrite au patrimoine mondial de l'Unesco. Depuis la maison, l'hypercentre est à dix minutes à pied.",
    places: [
      ["L'hypercentre", "10 min à pied", "La rue Sainte-Catherine, la place de la Comédie et le Grand-Théâtre, les terrasses du quartier Saint-Pierre."],
      ["Le tram et le bus", "4 min à pied", "Pour rejoindre les quais, la gare Saint-Jean ou les Chartrons sans prendre la voiture."],
      ["La place de la Bourse et le Miroir d'eau", "En tram ou à pied", "La façade la plus photographiée de Bordeaux, qui se reflète dans l'un des plus grands miroirs d'eau du monde."],
      ["La Cité du Vin", "En tram", "Un musée immersif consacré aux vins du monde, avec une vue sur la Garonne depuis le belvédère."],
      ["Saint-Émilion", "Environ 45 min", "Village médiéval classé à l'Unesco, au milieu des vignes : accessible en voiture ou en train depuis la gare Saint-Jean."],
      ["Lacanau et l'océan", "Environ 1 h de route", "Et la Maison du Lac, pour finir le séjour les pieds dans l'eau."],
    ],
  },
};

/* Avis de voyageurs, extraits des commentaires publiés sur Airbnb
   (data/airbnb/raw/<maison>-reviews.json). Seule l'orthographe a été
   corrigée ; « … » marque un passage coupé. */
window.REVIEWS = {
  lacanau: [
    ["Nous parcourons parfois des centaines voire des milliers de kilomètres pour nous dépayser, j'ai juste fait quelques kilomètres pour me retrouver dans un havre de paix.", "Sandrine", "août 2022"],
    ["La maison est superbe, décorée avec beaucoup de goût, très confortable et spacieuse… Vous traversez la route et vous êtes au lac…", "Fanny", "août 2022"],
    ["The house felt like a real luxurious stay and the location was perfect for both Lacanau Lake and also Lacanau Ocean.", "Alan", "août 2023"],
    ["L'extérieur et la piscine invitent à la détente et au farniente. Un véritable havre de paix !", "Damien", "juillet 2023"],
    ["Un ameublement très complet et une décoration raffinée et harmonieuse… nous a permis de jouir d'un confort de vie exceptionnel.", "Gaspard", "juillet 2022"],
    ["The house was spotless, beautifully decorated, and had all the little touches that made it feel like home.", "Gareth", "juillet 2025"],
    ["The lake is so close that it makes for a very relaxed holiday in this beautiful part of the world.", "Hannah", "août 2024"],
    ["C'est une maison chaleureuse, décorée avec goût par les propriétaires et très fonctionnelle. Je vous la recommande les yeux fermés.", "Auriane", "décembre 2022"],
  ],
  bordeaux: [
    ["C'est super agréable d'être accueillis dans une « vraie » maison habitée et pas seulement meublée pour être louée. La double exposition est un vrai plus et l'emplacement est parfait.", "Marion", "mars 2026"],
    ["Très très belle maison avec une décoration et un charme vraiment incroyables. On a eu du mal à quitter la maison pour se balader tellement on s'y sentait bien !", "Bénédicte", "mai 2024"],
    ["The house exceeded our expectations and the terrace was the icing on the cake!", "Kellie", "avril 2026"],
    ["Décoré avec beaucoup de goût dans un style contemporain et chaleureux. On s'y sent extrêmement bien.", "Thierry", "mai 2024"],
    ["On était 8 et on ne se marchait pas dessus. La pièce de vie est spacieuse, lumineuse et bien équipée pour passer des temps conviviaux.", "Xavier", "mars 2024"],
    ["The photos don't do the house justice, it is beautiful and really well furnished.", "Aisling", "novembre 2025"],
    ["Parfait pour un groupe, avec la possibilité de visiter Bordeaux facilement mais aussi de profiter de la belle pièce de vie.", "Cyrille", "novembre 2024"],
    ["Le plus du logement est le petit patio très agréable pour prendre son petit déjeuner en groupe.", "Hervé", "août 2021"],
  ],
};
