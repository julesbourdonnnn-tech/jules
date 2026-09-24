/*
 * ============================================================
 *  GUIDES THÉMATIQUES (pages « guides/<slug>.html »)
 * ============================================================
 *  Chaque guide sélectionne automatiquement les établissements de
 *  js/hotels.js qui correspondent à son thème (match) ou une liste
 *  choisie à la main (ids). Les titres s'adaptent au nombre d'adresses.
 *  Après modification, les pages sont régénérées par « node scripts/build.js »
 *  (fait automatiquement par la GitHub Action « Build »).
 * ============================================================
 */
(function (global) {
  const PARIS = { lat: 48.8566, lng: 2.3522 };
  const km = (a, b) => {
    const R = 6371, rad = (d) => (d * Math.PI) / 180;
    const x = Math.sin(rad(b.lat - a.lat) / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(x));
  };
  const plural = (n, one, many) => (n > 1 ? many : one);

  global.GUIDES = [
    {
      slug: "nuit-insolite-en-amoureux",
      kicker: "En amoureux",
      short: "Nuits insolites en amoureux",
      title: (n) => `${n} nuits insolites pour un week-end en amoureux`,
      description: "Bulle sous les étoiles, phare, cabane avec jacuzzi, jardin secret à Montmartre : notre sélection d'hébergements insolites pour une escapade à deux en France.",
      ids: ["attrap-reves-allauch", "phare-de-kerbel", "loire-valley-lodges", "pella-roca", "hotel-particulier-montmartre", "les-roches-rouges", "la-coorniche", "alpinest", "cabanes-du-moulin", "les-hautes-roches"],
      cover: "attrap-reves-allauch",
      intro: [
        "Pour un anniversaire, une demande en mariage ou simplement deux jours rien qu'à deux, rien ne vaut un lieu qui sort de l'ordinaire. On a rassemblé ici nos adresses les plus romantiques : on s'y endort sous les étoiles, au sommet d'un phare ou dans les arbres, loin de tout.",
        "Elles cultivent toutes l'intimité, avec un décor qu'on n'oublie pas ; plusieurs offrent un spa ou un jacuzzi privatif.",
      ],
      tips: [
        "Réservez tôt pour les dates clés (Saint-Valentin, ponts de mai, week-ends d'été) : ces lieux comptent souvent très peu de chambres.",
        "Demandez à l'établissement s'il propose des attentions à ajouter à la réservation (bouteille, fleurs, dîner livré, massage).",
        "Vérifiez les heures d'arrivée : certains lieux isolés demandent d'arriver avant la nuit.",
      ],
    },
    {
      slug: "cabanes-perchees",
      kicker: "Cabanes perchées",
      short: "Les plus belles cabanes perchées",
      title: (n) => `Les ${n} plus belles cabanes perchées de France`,
      description: "Cabanes dans les arbres avec jacuzzi, cabanes d'artistes, cabanes flottantes : notre sélection des plus belles cabanes perchées où dormir en France.",
      match: (h) => h.type === "cabane",
      cover: "loire-valley-lodges",
      intro: [
        "Dormir dans les arbres, c'est retrouver ses rêves d'enfant avec le confort d'aujourd'hui. Les cabanes de notre sélection vont de l'adresse bohème au véritable hôtel de luxe perché, avec baies vitrées, jacuzzi privatif et dîner livré à la cabane.",
        "On y accède par des escaliers, des passerelles suspendues ou des échelles, puis la forêt fait le reste : le chant des oiseaux au réveil, le vent dans les branches, et le silence.",
      ],
      tips: [
        "Vérifiez l'accès : certaines cabanes se rejoignent par des passerelles ou des échelles, peu pratiques avec de gros bagages ou de très jeunes enfants.",
        "Pour profiter d'un bain nordique ou d'un jacuzzi en plein air, les nuits de printemps et d'automne sont idéales.",
        "Emportez une lampe frontale et des chaussures confortables : les chemins de forêt sont peu éclairés la nuit.",
      ],
    },
    {
      slug: "week-end-insolite-pres-de-paris",
      kicker: "Près de Paris",
      short: "Week-end insolite près de Paris",
      title: (n) => `Week-end insolite près de Paris : ${n} ${plural(n, "adresse", "adresses")} à moins de 300 km`,
      description: "Cabanes perchées, hôtels troglodytes, abbaye royale, château : les hébergements insolites à moins de 300 km de Paris pour un week-end dépaysant.",
      match: (h) => h.city !== "Paris" && km(PARIS, h) <= 300,
      sort: (a, b) => km(PARIS, a) - km(PARIS, b),
      note: (h) => `À ${Math.round(km(PARIS, h) / 5) * 5} km de Paris à vol d'oiseau`,
      cover: "cabanes-du-moulin",
      intro: [
        "Pas besoin de partir loin pour changer d'air. À quelques heures de Paris, on peut dormir dans une cabane au bord d'une rivière, dans une chambre creusée dans la falaise au bord de la Loire ou dans une abbaye royale millénaire.",
        "Les adresses sont classées de la plus proche à la plus éloignée de Paris, avec la distance à vol d'oiseau : de quoi choisir selon le temps dont vous disposez.",
      ],
      tips: [
        "Partez le vendredi en fin de matinée ou le samedi tôt pour éviter les bouchons de sortie de Paris.",
        "La vallée de la Loire est aussi accessible en train : pensez-y pour les adresses proches de Tours ou de Saumur.",
        "Combinez votre nuit avec une visite : les châteaux de la Loire et le Mont-Saint-Michel sont à deux pas de plusieurs de ces adresses.",
      ],
    },
    {
      slug: "hotels-troglodytes",
      kicker: "Troglodytes",
      short: "Dormir dans un hôtel troglodyte",
      title: (n) => `Dormir dans la roche : ${n} hôtels troglodytes en France`,
      description: "Chambres creusées dans le tuffeau, piscine sous la roche, hôtel sous la plaine : les plus beaux hôtels troglodytes de France, en Val de Loire.",
      match: (h) => h.type === "troglodyte",
      cover: "demeure-de-la-vignole",
      intro: [
        "Le Val de Loire est le pays des troglodytes : pendant des siècles, on y a extrait le tuffeau, cette pierre blanche qui a servi à bâtir les châteaux. Les cavités laissées dans les falaises sont devenues des maisons, des caves… et aujourd'hui des chambres d'hôtel étonnantes.",
        "Murs de pierre, voûtes, lumière tamisée : dormir dans la roche est une expérience calme et enveloppante, à deux pas des vignobles et des châteaux.",
      ],
      tips: [
        "La température reste fraîche et stable toute l'année dans la roche : prévoyez une petite laine même en été.",
        "Profitez-en pour visiter les caves et les villages troglodytiques de la région.",
        "Si vous êtes sensible à l'humidité, demandez à l'établissement comment les chambres sont ventilées et chauffées.",
      ],
    },
    {
      slug: "spa-jacuzzi-privatif",
      kicker: "Spa privatif",
      short: "Nuits insolites avec spa privatif",
      title: (n) => `${n} nuits insolites avec spa ou jacuzzi privatif`,
      description: "Cabanes perchées avec jacuzzi, sauna privatif, spa en pleine forêt : les hébergements insolites où l'on profite d'un bain chaud rien qu'à deux.",
      match: (h) => h.amenities.some((a) => /privatif/i.test(a) && /(spa|jacuzzi|sauna)/i.test(a)),
      cover: "pella-roca",
      intro: [
        "Un bain chaud sous les arbres, un sauna face à la vallée, un jacuzzi sur sa terrasse perchée : ces adresses offrent un espace bien-être rien que pour vous, sans horaires ni voisins.",
        "C'est l'une des expériences les plus recherchées pour une nuit insolite, à réserver en priorité pour les saisons fraîches.",
      ],
      tips: [
        "Le bain est souvent chauffé en permanence : pensez à demander l'heure à laquelle il est prêt à votre arrivée.",
        "Emportez un peignoir léger ou des sandales si l'établissement ne les fournit pas.",
        "Hydratez-vous bien : chaleur et bulles se marient bien avec une bonne bouteille d'eau.",
      ],
    },
    {
      slug: "hotels-insolites-bord-de-mer",
      kicker: "Bord de mer",
      short: "Hôtels insolites en bord de mer",
      title: (n) => `${n} hôtels insolites en bord de mer`,
      description: "Un phare, une maison dans les remparts du Mont-Saint-Michel, une piscine d'eau de mer dans la roche : les hôtels insolites les pieds dans l'eau en France.",
      match: (h) => h.env === "mer",
      cover: "phare-de-kerbel",
      intro: [
        "De la Bretagne à la Corse, l'horizon change tout. Dans cette sélection, on dort au sommet d'un phare, dans les remparts du Mont-Saint-Michel, face à la dune du Pilat ou au-dessus d'une piscine d'eau de mer creusée dans la roche rouge de l'Esterel.",
        "Des adresses pour les amoureux de grand large, de couchers de soleil et de baignades au petit matin.",
      ],
      tips: [
        "Sur la côte atlantique, consultez l'horaire des marées : le paysage change complètement entre marée haute et marée basse.",
        "Les ailes de saison (mai-juin, septembre) offrent souvent une mer encore douce et beaucoup moins de monde.",
        "Réservez tôt pour juillet et août, surtout pour les chambres avec vue sur la mer.",
      ],
    },
    {
      slug: "hotels-insolites-montagne",
      kicker: "Montagne",
      short: "Hôtels insolites à la montagne",
      title: (n) => `${n} hôtels insolites à la montagne`,
      description: "L'hôtel le plus haut de France, un village d'igloos, des cabanes-spa et un hameau de fermes d'alpage : nos hébergements insolites à la montagne.",
      match: (h) => h.env === "montagne",
      cover: "refuge-de-solaise",
      intro: [
        "À la montagne, l'insolite prend de la hauteur : un refuge à 2 551 mètres accessible en télécabine, un village d'igloos sur les pistes, des cabanes-spa entre Alpes et Provence ou un hameau de chalets bâtis avec le bois de fermes centenaires.",
        "Des adresses pour les skieurs comme pour les contemplatifs, qui veulent voir le soleil se coucher sur les sommets.",
      ],
      tips: [
        "Vérifiez les dates d'ouverture : certains hébergements d'altitude ne sont ouverts qu'en saison.",
        "En hiver, renseignez-vous sur l'accès (télécabine, piste, équipements pour la voiture).",
        "Prévoyez des vêtements chauds même en été : les soirées sont fraîches en altitude.",
      ],
    },
    {
      slug: "dormir-dans-un-chateau",
      kicker: "Châteaux & histoire",
      short: "Dormir dans un château",
      title: (n) => `Dormir dans un château ou un lieu d'histoire : ${n} adresses`,
      description: "Abbaye royale, château des évêques de Cahors, demeures Renaissance, maison du XVe siècle sur le Mont-Saint-Michel : dormir dans l'histoire de France.",
      match: (h) => h.type === "chateau" || h.type === "historique",
      cover: "domaine-des-etangs",
      intro: [
        "Dormir là où des rois, des évêques ou des moniales ont vécu : ces adresses ouvrent les portes de lieux chargés d'histoire, restaurés avec soin et souvent entourés de parcs, de vignes ou de remparts.",
        "Abbaye royale, châteaux médiévaux, demeures Renaissance : un voyage dans le temps, avec le confort d'aujourd'hui.",
      ],
      tips: [
        "Demandez si une visite privée ou une promenade après la fermeture au public est proposée aux hôtes.",
        "Les chambres historiques n'ont pas toutes le même confort ni la même vue : lisez bien la description avant de réserver.",
        "Les monuments se visitent souvent mieux hors saison, sans la foule.",
      ],
    },
    {
      slug: "hotels-insolites-vallee-de-la-loire",
      kicker: "Val de Loire",
      short: "Hôtels insolites en Val de Loire",
      title: (n) => `Val de Loire : ${n} hébergements insolites entre châteaux et vignes`,
      description: "Cabanes d'artistes, troglodytes, abbaye royale : les hébergements insolites du Val de Loire, en Touraine et en Anjou.",
      match: (h) => h.region === "Centre-Val de Loire" || h.region === "Pays de la Loire",
      cover: "les-hautes-roches",
      intro: [
        "Châteaux, vignobles, falaises de tuffeau et forêts : le Val de Loire concentre certaines des nuits les plus originales de France, à quelques heures de Paris.",
        "Troglodytes, cabanes d'artistes ou abbaye royale : de quoi composer un week-end entre visites de châteaux, dégustations et balades à vélo le long de la Loire.",
      ],
      tips: [
        "La Loire à Vélo longe plusieurs de ces adresses : pensez à louer des vélos sur place.",
        "Réservez vos visites de châteaux à l'avance en haute saison.",
        "Profitez-en pour découvrir les vins de la région : Vouvray, Saumur-Champigny, Chinon…",
      ],
    },
    {
      slug: "hotels-insolites-en-ville",
      kicker: "En ville",
      short: "Hôtels insolites en ville",
      title: (n) => `${n} hôtels insolites en ville : Paris, Lyon, Marseille`,
      description: "Un hôtel flottant sur la Seine, un jardin secret à Montmartre, la Cité radieuse de Le Corbusier, des demeures Renaissance à Lyon : les hôtels insolites en ville.",
      match: (h) => h.env === "ville",
      cover: "hotel-particulier-montmartre",
      intro: [
        "L'insolite n'est pas réservé à la campagne. En ville aussi, certaines adresses surprennent : un hôtel qui flotte sur la Seine, une maison secrète au sommet de Montmartre, un chef-d'œuvre de l'architecture moderne ou quatre demeures Renaissance reliées par des cours intérieures.",
        "Idéal pour un city-break qui sort de l'ordinaire, sans renoncer aux musées, aux restaurants et à la vie de quartier.",
      ],
      tips: [
        "En centre-ville, renseignez-vous sur le stationnement : il est souvent payant et limité.",
        "Les hôtels les plus singuliers ont peu de chambres : réservez tôt les week-ends.",
        "Demandez les bonnes adresses du quartier à la réception : c'est souvent le meilleur guide.",
      ],
    },
    {
      slug: "nuits-insolites-petit-budget",
      kicker: "Petits budgets",
      short: "Nuits insolites à petit prix",
      title: (n) => `${n} nuits insolites pour moins de 250 € la nuit`,
      description: "Troglodytes, cabanes, bulle, hôtel Le Corbusier : les hébergements insolites de notre sélection à moins de 250 € la nuit (budget indicatif).",
      match: (h) => h.budget <= 2,
      sort: (a, b) => a.budget - b.budget,
      cover: "hotel-le-corbusier",
      intro: [
        "Une nuit extraordinaire n'est pas forcément hors de prix. Toutes les adresses de ce guide ont un budget indicatif inférieur à 250 € la nuit pour deux, et plusieurs sont sous la barre des 150 €.",
        "Les prix varient selon la saison, le jour de la semaine et le type de chambre : vérifiez toujours le tarif exact pour vos dates.",
      ],
      tips: [
        "Les nuits en semaine et hors vacances scolaires sont souvent nettement moins chères.",
        "Comparez les types de chambres : la différence de prix peut être importante au sein d'un même établissement.",
        "Regardez ce qui est inclus (petit-déjeuner, dîner, activités) avant de comparer les tarifs.",
      ],
    },
    {
      slug: "hotels-insolites-paris",
      kicker: "Paris & alentours",
      short: "Hôtels insolites à Paris",
      title: (n) => `${n} hôtels insolites à Paris et aux portes de Paris`,
      description: "Une piscine Art déco, une ancienne maison close, un hôtel flottant, un jardin secret à Montmartre et le seul hôtel du château de Versailles : les nuits les plus singulières de Paris.",
      match: (h) => h.region === "Île-de-France" && h.env === "ville",
      cover: "molitor",
      intro: [
        "Paris compte des milliers d'hôtels, mais très peu de lieux vraiment à part. Ceux-ci racontent une histoire : une piscine mythique des années 1930, une maison close de la Belle Époque, un bateau amarré sur la Seine, une maison secrète sur la butte Montmartre, et même le seul hôtel du domaine de Versailles.",
        "Des adresses pour une nuit exceptionnelle à deux, un anniversaire ou simplement redécouvrir la capitale autrement.",
      ],
      tips: [
        "Les week-ends partent vite : réservez plusieurs semaines à l'avance, surtout au printemps et à l'automne.",
        "Venez en transports en commun : le stationnement est rare et cher dans Paris.",
        "Pour Versailles, renseignez-vous sur les visites privées du château réservées aux hôtes.",
      ],
    },
    {
      slug: "dormir-en-altitude",
      kicker: "En altitude",
      short: "Dormir en altitude",
      title: (n) => `Dormir au-dessus des nuages : ${n} nuits en altitude`,
      description: "Observatoire du Pic du Midi, refuge au bord de la Mer de Glace, hôtel le plus haut de France, refuges accessibles à ski : les nuits les plus hautes de France.",
      match: (h) => h.env === "montagne" && /refuge|pic|igloo/i.test(h.id),
      cover: "pic-du-midi",
      intro: [
        "Il y a des nuits qu'on ne passe qu'une fois dans sa vie : au sommet du Pic du Midi, dans un observatoire à 2 877 mètres ; au bord de la Mer de Glace, dans un refuge de 1880 ; dans l'hôtel le plus haut de France ou dans un igloo sur les pistes.",
        "Leur point commun : quand les remontées ferment, la montagne se vide, et l'on se retrouve seul face aux sommets, au coucher du soleil puis sous un ciel constellé d'étoiles.",
      ],
      tips: [
        "Respectez les horaires d'accès (téléphérique, train, télécabine) : une fois fermés, il est impossible de monter.",
        "L'altitude fatigue : buvez beaucoup d'eau et évitez les efforts intenses le premier soir.",
        "Même en été, emportez des vêtements chauds pour la nuit et le lever du soleil.",
      ],
    },
  ];
})(typeof window !== "undefined" ? window : globalThis);
